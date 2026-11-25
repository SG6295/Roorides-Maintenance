-- MAIN-160 (epic MAIN-154): transfers for spares and invoices from before MAIN-159.
--
-- Before MAIN-159 a spare on a Pvt Ltd (or still Unknown) vehicle took NVS Travels stock
-- with no transfer. This posts one transfer per such spare line (spare_transfers,
-- source = 'backfill'), dated when the spare was added, at the first-in-first-out cost
-- MAIN-158 already gave it (stock_cost_draws) — nothing is re-costed.
--
-- A job card belongs to the company its vehicle had when the card was opened. The
-- vehicle's first recorded company (initial load or first assignment) counts from the
-- beginning; only a sale changes it, from the sale's date (vehicle_company_at). In prod
-- every change row is the initial load of 24 Nov 2026, after these cards were opened.
--
-- Unlike a live transfer (frozen at the confirmed amount), a backfilled transfer follows
-- its spare's cost: whenever rebuild_part_cost re-costs the part, the backfilled
-- transfers it supplied are re-priced (user decision 2026-11-25).
--
-- Unknown vehicles: their spares are posted when finance first assigns the vehicle — to
-- Pvt Ltd that posts the NVS Travels draws; to NVS Travels it posts nothing.
--
-- Outsourced job card invoices from before go-live stay NVS Travels (MAIN-161). Where the
-- card's company is Pvt Ltd, the ledger adds a transfer of the Approved Amount — worked
-- out, not stored, so it follows the invoice: in once finance accepts it, out again on
-- Hold or Reject, its amount whatever the invoice's is.

-- ── Whose a job card is ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.vehicle_company_at(p_registration text, p_at timestamptz) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT coalesce(
        -- The latest sale on or before then.
        (SELECT c.new_company
         FROM   public.vehicle_company_changes c
         JOIN   public.vehicles v ON v.id = c.vehicle_id
         WHERE  v.registration_number = p_registration
           AND  c.kind = 'sale' AND c.created_at <= p_at
         ORDER  BY c.created_at DESC
         LIMIT  1),
        -- Else the first company it was recorded under, which counts from the beginning.
        (SELECT c.new_company
         FROM   public.vehicle_company_changes c
         JOIN   public.vehicles v ON v.id = c.vehicle_id
         WHERE  v.registration_number = p_registration
           AND  c.kind IN ('initial_load', 'assignment')
         ORDER  BY c.created_at
         LIMIT  1),
        'unknown')
$$;

COMMENT ON FUNCTION public.vehicle_company_at(text, timestamptz) IS
    'MAIN-160: the company a vehicle belonged to at a moment — the latest sale on or before it, else its first recorded company (initial load or first assignment, counting from the beginning), else unknown.';

REVOKE ALL ON FUNCTION public.vehicle_company_at(text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.vehicle_company_at(text, timestamptz) TO service_role;

-- ── What a spare's draw from one company comes to ────────────────────────────

-- Quantity, cost incl. GST and GST per rate of a spare's draws from p_from, read from
-- stock_cost_draws. Shared by the live quote and the backfill.
CREATE OR REPLACE FUNCTION public.spare_draw_quote(p_issue_part_id uuid, p_from text) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    WITH d AS (
        SELECT d.quantity, d.amount,
               coalesce(pii.gst_rate, o.gst_rate,
                        CASE WHEN d.found_audit_item_id IS NOT NULL THEN public.part_latest_cost_gst_rate(d.part_id) END,
                        0)::numeric AS rate
        FROM   public.stock_cost_draws d
        LEFT JOIN public.purchase_invoice_items pii ON pii.id = d.purchase_item_id
        LEFT JOIN public.opening_stock_lots     o   ON o.id   = d.opening_lot_id
        WHERE  d.issue_part_id = p_issue_part_id AND d.company = p_from
    ), r AS (
        SELECT rate, sum(amount) AS incl,
               round(sum(amount) * 100 / (100 + rate), 2) AS before
        FROM   d WHERE amount IS NOT NULL GROUP BY rate
    )
    SELECT jsonb_build_object(
        'quantity',      (SELECT coalesce(sum(quantity), 0) FROM d),
        'amount',        coalesce((SELECT sum(incl) FROM r), 0),
        'gst',           coalesce((SELECT sum(incl - before) FROM r), 0),
        'gst_breakdown', coalesce((SELECT jsonb_agg(jsonb_build_object('rate', rate, 'before_gst', before,
                                                                      'gst', incl - before, 'incl_gst', incl)
                                                    ORDER BY rate) FROM r), '[]'::jsonb),
        'priced',        NOT EXISTS (SELECT 1 FROM d WHERE amount IS NULL))
$$;

REVOKE ALL ON FUNCTION public.spare_draw_quote(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spare_draw_quote(uuid, text) TO service_role;

-- The live quote (MAIN-159), now reading spare_draw_quote. Same result as before.
CREATE OR REPLACE FUNCTION public.spare_transfer_quote(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_ip   record;
    v_to   text;
    v_from text;
    v_qty  numeric;
    v_q    jsonb;
BEGIN
    SELECT ip.*, jc.id AS jc_id, jc.job_card_number, jc.vehicle_number, p.name AS part_name, p.unit
    INTO   v_ip
    FROM   public.issue_parts ip
    JOIN   public.issues    i  ON i.id = ip.issue_id
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    JOIN   public.parts     p  ON p.id = ip.part_id
    WHERE  ip.id = p_issue_part_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    v_to   := public.job_card_stock_company(v_ip.jc_id);
    v_from := CASE v_to WHEN 'nvs_travels' THEN 'nvs_travel_solutions' ELSE 'nvs_travels' END;
    v_qty  := coalesce((v_ip.stock_draws ->> v_from)::numeric, 0);

    IF v_qty <= 0 THEN
        RETURN NULL;
    END IF;

    v_q := public.spare_draw_quote(p_issue_part_id, v_from);

    RETURN jsonb_build_object(
        'issue_part_id',   p_issue_part_id,
        'part_id',         v_ip.part_id,
        'part_name',       v_ip.part_name,
        'unit',            v_ip.unit,
        'from_company',    v_from,
        'to_company',      v_to,
        'quantity',        v_qty,
        'own_quantity',    v_ip.quantity_used - v_qty,
        'amount',          v_q -> 'amount',
        'gst',             v_q -> 'gst',
        'gst_breakdown',   v_q -> 'gst_breakdown',
        'job_card_number', v_ip.job_card_number,
        'vehicle',         v_ip.vehicle_number);
END;
$$;

-- ── Posting the backfill ─────────────────────────────────────────────────────

-- Posts a transfer for every in-house spare on the vehicle's job cards that drew the
-- other company's stock and has never had one. Returns how many it posted. Run by this
-- migration for every vehicle, and on a vehicle's first assignment.
CREATE OR REPLACE FUNCTION public.post_backfill_spare_transfers(p_registration text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_n integer;
BEGIN
    INSERT INTO public.spare_transfers (
        issue_part_id, issue_id, job_card_id, job_card_number, vehicle_number,
        part_id, part_name, unit, quantity, from_company, to_company,
        amount, gst, gst_breakdown, source, posted_at)
    SELECT ip.id, ip.issue_id, jc.id, jc.job_card_number, jc.vehicle_number,
           ip.part_id, p.name, p.unit, (ip.stock_draws ->> o.from_co)::numeric, o.from_co, o.owner,
           (q.q ->> 'amount')::numeric, (q.q ->> 'gst')::numeric, q.q -> 'gst_breakdown',
           'backfill', coalesce(ip.added_at, jc.created_at) AT TIME ZONE 'UTC'
    FROM   public.job_cards   jc
    JOIN   public.issues      i  ON i.job_card_id = jc.id
    JOIN   public.issue_parts ip ON ip.issue_id = i.id
    JOIN   public.parts       p  ON p.id = ip.part_id
    CROSS  JOIN LATERAL (
        SELECT x.owner, CASE x.owner WHEN 'nvs_travels' THEN 'nvs_travel_solutions' ELSE 'nvs_travels' END AS from_co
        FROM   (SELECT public.vehicle_company_at(jc.vehicle_number, jc.created_at AT TIME ZONE 'UTC') AS owner) x
    ) o
    CROSS  JOIN LATERAL (SELECT public.spare_draw_quote(ip.id, o.from_co) AS q) q
    WHERE  jc.vehicle_number = p_registration
      AND  jc.type = 'InHouse'
      AND  o.owner IN ('nvs_travels', 'nvs_travel_solutions')
      AND  coalesce((ip.stock_draws ->> o.from_co)::numeric, 0) > 0
      AND  NOT EXISTS (SELECT 1 FROM public.spare_transfers t WHERE t.issue_part_id = ip.id);

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.post_backfill_spare_transfers(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.post_backfill_spare_transfers(text) TO service_role;

-- First assignment of an Unknown vehicle: post its past spares (nothing, if it went to
-- NVS Travels — its spares drew NVS Travels stock). The prod→staging seed copies rows
-- with triggers off, so it posts nothing twice.
CREATE OR REPLACE FUNCTION public.backfill_transfers_on_assignment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    PERFORM public.post_backfill_spare_transfers(NEW.registration_number);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_backfill_transfers_on_assignment
    AFTER INSERT ON public.vehicle_company_changes
    FOR EACH ROW WHEN (NEW.kind = 'assignment')
    EXECUTE FUNCTION public.backfill_transfers_on_assignment();

-- ── Backfilled transfers follow their spare's cost ───────────────────────────

-- Re-prices the active backfilled transfers that took this part from this company, from
-- the draws rebuild_part_cost has just recomputed. A draw left without a price keeps the
-- transfer's last amount.
CREATE OR REPLACE FUNCTION public.refresh_backfill_transfers(p_part_id uuid, p_company text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    UPDATE public.spare_transfers t
    SET    amount        = (q.q ->> 'amount')::numeric,
           gst           = (q.q ->> 'gst')::numeric,
           gst_breakdown = q.q -> 'gst_breakdown'
    FROM   public.spare_transfers t2
    CROSS  JOIN LATERAL (SELECT public.spare_draw_quote(t2.issue_part_id, t2.from_company) AS q) q
    WHERE  t2.id = t.id
      AND  t.source = 'backfill' AND t.status = 'Active'
      AND  t.part_id = p_part_id AND t.from_company = p_company
      AND  (q.q ->> 'priced')::boolean
      AND  ((q.q ->> 'amount')::numeric, (q.q ->> 'gst')::numeric, q.q -> 'gst_breakdown')
           IS DISTINCT FROM (t.amount, t.gst, t.gst_breakdown);
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_backfill_transfers(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_backfill_transfers(uuid, text) TO service_role;

-- MAIN-158's rebuild, unchanged but for the last statement.
CREATE OR REPLACE FUNCTION public.rebuild_part_cost(p_part_id uuid, p_company text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_kind  text[];
    v_id    uuid[];
    v_qty   numeric[];
    v_cost  numeric[];
    v_n     integer;
    v_i     integer := 1;
    v_left  numeric := 0;
    v_need  numeric;
    v_take  numeric;
    c       record;
BEGIN
    IF p_part_id IS NULL OR p_company IS NULL THEN
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('stock_cost:' || p_part_id::text || ':' || p_company, 0));

    DELETE FROM public.stock_cost_draws WHERE part_id = p_part_id AND company = p_company;

    SELECT array_agg(l.kind     ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.lot_id   ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.quantity ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id),
           array_agg(l.unit_cost ORDER BY l.rnk, l.at_time, l.recorded_at, l.lot_id)
    INTO   v_kind, v_id, v_qty, v_cost
    FROM   public.part_cost_lots(p_part_id, p_company) l;

    v_n := coalesce(cardinality(v_id), 0);
    IF v_n > 0 THEN
        v_left := v_qty[1];
    END IF;

    FOR c IN
        SELECT * FROM public.part_cost_consumers(p_part_id, p_company) x
        ORDER BY x.at_time, x.consumer_id
    LOOP
        v_need := c.quantity;
        WHILE v_need > 0 LOOP
            -- Step past used-up lots.
            WHILE v_i <= v_n AND v_left <= 0 LOOP
                v_i := v_i + 1;
                IF v_i <= v_n THEN
                    v_left := v_qty[v_i];
                END IF;
            END LOOP;

            IF v_i > v_n THEN
                -- No lot left: this quantity has no price.
                INSERT INTO public.stock_cost_draws (part_id, company, issue_part_id, audit_item_id, quantity, unit_cost)
                VALUES (p_part_id, p_company,
                        CASE WHEN c.kind = 'spare' THEN c.consumer_id END,
                        CASE WHEN c.kind = 'audit' THEN c.consumer_id END,
                        v_need, NULL);
                v_need := 0;
            ELSE
                v_take := least(v_need, v_left);
                INSERT INTO public.stock_cost_draws (part_id, company, issue_part_id, audit_item_id,
                                                     purchase_item_id, opening_lot_id, found_audit_item_id,
                                                     quantity, unit_cost)
                VALUES (p_part_id, p_company,
                        CASE WHEN c.kind = 'spare' THEN c.consumer_id END,
                        CASE WHEN c.kind = 'audit' THEN c.consumer_id END,
                        CASE WHEN v_kind[v_i] = 'purchase' THEN v_id[v_i] END,
                        CASE WHEN v_kind[v_i] = 'opening'  THEN v_id[v_i] END,
                        CASE WHEN v_kind[v_i] = 'found'    THEN v_id[v_i] END,
                        v_take, v_cost[v_i]);
                v_left := v_left - v_take;
                v_need := v_need - v_take;
            END IF;
        END LOOP;
    END LOOP;

    -- MAIN-160: backfilled transfers follow the new cost; live ones stay frozen.
    PERFORM public.refresh_backfill_transfers(p_part_id, p_company);
END;
$$;

COMMENT ON TABLE public.spare_transfers IS
    'MAIN-159: spares one company''s stock supplied to the other company''s vehicle. Posted by add_spare() (source job_card, amount incl. GST frozen when confirmed) and by MAIN-160''s backfill (source backfill, amount follows the spare''s cost through rebuild_part_cost). Reversed, never deleted, when the spare is removed. Read by company_ledger_lines.';

-- ── Company ledgers: invoice transfers ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.company_ledger_lines(p_company text) RETURNS TABLE(entry_at timestamp with time zone, seq integer, line_id uuid, kind text, doc_date date, spend numeric, owed numeric, gst numeric, gst_status text, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  -- Purchases and refurbishments billed to the company.
  select coalesce(oi.accepted_at, oi.updated_at, pi.created_at at time zone 'UTC'),
         1, pi.id, pi.kind, pi.invoice_date,
         pi.total_amount, 0::numeric,
         g.gst,
         case when oi.id is null then 'unknown'
              when oi.finance_payment_status = 'GST reconciled & closed'     then 'claimed'
              when oi.finance_payment_status = 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'purchase_number', pi.purchase_number,
             'invoice_no',      pi.invoice_number,
             'supplier',        coalesce(s.entity_name, pi.supplier_name),
             'finance_status',  oi.finance_payment_status,
             'invoice_id',      oi.id)
  from   public.purchase_invoices pi
  left join public.outsource_invoices oi on oi.purchase_invoice_id = pi.id
  left join public.suppliers s on s.id = pi.supplier_id
  cross join lateral (
      select coalesce(sum(i.line_total - round(i.quantity * i.unit_price - i.discount_amount, 2)), 0) as gst
      from   public.purchase_invoice_items i
      where  i.invoice_id = pi.id) g
  where  pi.billed_to = p_company
    and  pi.purchase_number not in (176, 180, 183, 185)
    and  (oi.id is null
          or oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed'))

  union all

  -- Job card and multi-vehicle invoices of the company, once finance has accepted them.
  select coalesce(oi.accepted_at, oi.updated_at), 2, oi.id,
         case when oi.job_card_id is not null then 'job_card' else 'multi_vehicle' end,
         oi.date_of_activity,
         oi.approved_amount, 0::numeric,
         -- MAIN-166: the bill's GST, scaled to the Approved Amount; NULL ("Not recorded")
         -- for an invoice without a breakdown.
         round(public.gst_breakdown_total(oi.gst_breakdown) * oi.approved_amount
               / nullif(oi.invoice_value, 0), 2),
         case oi.finance_payment_status
              when 'GST reconciled & closed'     then 'claimed'
              when 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'invoice_no',      oi.invoice_no,
             'supplier',        s.entity_name,
             'finance_status',  oi.finance_payment_status,
             'job_card_number', jc.job_card_number,
             'vehicle',         jc.vehicle_number,
             'batch_number',    bs.batch_number,
             'vehicle_count',   (select count(distinct v.vehicle_number)
                                 from public.batch_service_vehicles v
                                 where v.batch_service_id = bs.id))
  from   public.outsource_invoices oi
  left join public.job_cards      jc on jc.id = oi.job_card_id
  left join public.batch_services bs on bs.id = oi.batch_service_id
  left join public.suppliers      s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id)
  where  oi.company = p_company
    and  oi.purchase_invoice_id is null
    and  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')

  union all

  -- Vehicles sold between the companies: in both ledgers, opposite ways round.
  select c.created_at, 3, c.id,
         case when c.old_company = p_company then 'vehicle_sold' else 'vehicle_bought' end,
         (c.created_at at time zone 'Asia/Kolkata')::date,
         0::numeric,
         case when c.old_company = p_company then c.sale_value else -c.sale_value end,
         round(c.sale_value * c.gst_percent / (100 + c.gst_percent), 2),
         'inter_company',
         jsonb_build_object(
             'vehicle',      c.registration_number,
             'other_company', case when c.old_company = p_company then c.new_company else c.old_company end,
             'gst_percent',  c.gst_percent,
             'performed_by', c.performed_by_name)
  from   public.vehicle_company_changes c
  where  c.kind = 'sale'
    and  p_company in (c.old_company, c.new_company)

  union all

  -- MAIN-163: reconciliation adjustments. Placed at the end of their as-of day, or when
  -- posted if that is earlier (today's). A reversed one stays as a line but adds nothing;
  -- its amount is in `detail`.
  select least(public.end_of_ist_day(a.as_of), a.created_at), 4, a.id,
         case when a.status = 'Reversed' then 'reversed_adjustment' else 'adjustment' end,
         a.as_of,
         case when a.status = 'Active' and a.balance = 'spent' then a.amount else 0 end,
         case when a.status = 'Active' and a.balance = 'owed'  then a.amount else 0 end,
         null::numeric,
         'adjustment',
         jsonb_build_object(
             'balance',           a.balance,
             'amount',            a.amount,
             'as_of',             a.as_of,
             'confirmed_against', a.confirmed_against,
             'system_balance',    a.system_balance,
             'confirmed_balance', a.confirmed_balance,
             'reason',            a.reason,
             'created_by',        u.name,
             'created_at',        a.created_at,
             'reversed_at',       a.reversed_at,
             'reversed_by',       ru.name,
             'reverse_reason',    a.reverse_reason)
  from   public.company_ledger_adjustments a
  left join public.users u  on u.id  = a.created_by
  left join public.users ru on ru.id = a.reversed_by
  where  a.company = p_company

  union all

  -- MAIN-159: spares transferred between the companies. The vehicle's company spends the
  -- amount and owes it; the supplying company's spending goes down by it and it is owed.
  -- GST moves with the spending. A reversal is its own line, the other way round, on the
  -- day the spare was removed.
  select x.at, x.seq, t.id,
         case when t.to_company = p_company then 'spare_transfer_in' else 'spare_transfer_out' end
             || case when x.reversal then '_reversed' else '' end,
         (x.at at time zone 'Asia/Kolkata')::date,
         x.sign * case when t.to_company = p_company then t.amount else -t.amount end,
         x.sign * case when t.to_company = p_company then -t.amount else t.amount end,
         x.sign * case when t.to_company = p_company then t.gst else -t.gst end,
         'inter_company',
         jsonb_build_object(
             'job_card_number', t.job_card_number,
             'vehicle',         t.vehicle_number,
             'part',            t.part_name,
             'unit',            t.unit,
             'quantity',        t.quantity,
             'amount',          t.amount,
             'gst_breakdown',   t.gst_breakdown,
             'other_company',   case when t.to_company = p_company then t.from_company else t.to_company end,
             'source',          t.source,
             'posted_at',       t.posted_at,
             'posted_by',       t.posted_by_name,
             'reversed_at',     t.reversed_at,
             'reversed_by',     t.reversed_by_name)
  from   public.spare_transfers t
  cross join lateral (
      select t.posted_at as at, 5 as seq, 1 as sign, false as reversal
      union all
      select t.reversed_at, 6, -1, true where t.status = 'Reversed'
  ) x
  where  p_company in (t.from_company, t.to_company)

  union all

  -- MAIN-160: a job card invoice that stays with one company (from before go-live,
  -- MAIN-161) on a card that belongs to the other moves its Approved Amount across,
  -- like a spare transfer, while finance has it accepted.
  select coalesce(oi.accepted_at, oi.updated_at), 7, oi.id,
         case when o.owner = p_company then 'invoice_transfer_in' else 'invoice_transfer_out' end,
         oi.date_of_activity,
         case when o.owner = p_company then oi.approved_amount else -oi.approved_amount end,
         case when o.owner = p_company then -oi.approved_amount else oi.approved_amount end,
         (case when o.owner = p_company then 1 else -1 end)
             * round(public.gst_breakdown_total(oi.gst_breakdown) * oi.approved_amount
                     / nullif(oi.invoice_value, 0), 2),
         'inter_company',
         jsonb_build_object(
             'invoice_no',      oi.invoice_no,
             'supplier',        s.entity_name,
             'finance_status',  oi.finance_payment_status,
             'job_card_number', jc.job_card_number,
             'vehicle',         jc.vehicle_number,
             'other_company',   case when o.owner = p_company then oi.company else o.owner end)
  from   public.outsource_invoices oi
  join   public.job_cards jc on jc.id = oi.job_card_id
  left join public.suppliers s on s.id = jc.supplier_id
  cross join lateral (
      select public.vehicle_company_at(jc.vehicle_number, jc.created_at at time zone 'UTC') as owner) o
  where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  o.owner in ('nvs_travels', 'nvs_travel_solutions')
    and  o.owner <> oi.company
    and  p_company in (oi.company, o.owner)
$$;

-- ── The backfill ─────────────────────────────────────────────────────────────

SELECT sum(public.post_backfill_spare_transfers(v.registration_number)) AS backfilled
FROM   (SELECT DISTINCT jc.vehicle_number AS registration_number FROM public.job_cards jc) v;
