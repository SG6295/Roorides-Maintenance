-- MAIN-159 (epic MAIN-154): spares only from the vehicle's own company, with transfers.
--
-- An in-house spare draws its vehicle's company's stock at the workshop first. When that
-- is not enough and the other company holds the rest, the rest can be used only through
-- a confirmed transfer (user decision 2026-11-25: take what the vehicle's company has,
-- transfer the rest). add_spare() quotes the transfer — quantity, first-in-first-out cost
-- incl. GST, GST at the rate of the lots it comes from, both companies — and posts it
-- once the exec confirms that amount.
--
-- A transfer's amount is frozen when posted: a bill entered late re-costs the supplying
-- company's queue (MAIN-158) but never a posted transfer, so a reconciled ledger stays
-- reconciled. The spare's cost (and its job card's value) uses the frozen amount for the
-- transferred quantity.
--
-- In the company ledgers (user decision 2026-11-25) a transfer moves Spent to date — the
-- vehicle's company +amount, the supplying company −amount — and Owed between companies
-- both ways. Removing the spare reverses it: the transfer stays on its date, and the
-- reversal is its own line on the day the spare was removed.
--
-- Service-role writes (the prod→staging seed, MAIN-160's backfill) keep drawing both
-- companies as before.

-- ── Transfers ────────────────────────────────────────────────────────────────

CREATE TABLE public.spare_transfers (
    id               uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    -- Not foreign keys: a transfer outlives the spare (and its history the job card).
    issue_part_id    uuid NOT NULL,
    issue_id         uuid,
    job_card_id      uuid,
    job_card_number  integer,
    vehicle_number   text,
    part_id          uuid NOT NULL REFERENCES public.parts(id),
    part_name        text NOT NULL,
    unit             text,
    quantity         numeric(12,2) NOT NULL,
    from_company     text NOT NULL,
    to_company       text NOT NULL,
    amount           numeric(14,2) NOT NULL,
    gst              numeric(14,2) NOT NULL,
    gst_breakdown    jsonb DEFAULT '[]'::jsonb NOT NULL,
    source           text DEFAULT 'job_card' NOT NULL,
    posted_at        timestamptz DEFAULT now() NOT NULL,
    posted_by        uuid,
    posted_by_name   text,
    status           text DEFAULT 'Active' NOT NULL,
    reversed_at      timestamptz,
    reversed_by      uuid,
    reversed_by_name text,
    CONSTRAINT spare_transfers_companies_check CHECK (
        from_company IN ('nvs_travels', 'nvs_travel_solutions')
        AND to_company IN ('nvs_travels', 'nvs_travel_solutions')
        AND from_company <> to_company),
    CONSTRAINT spare_transfers_quantity_check CHECK (quantity > 0),
    CONSTRAINT spare_transfers_amount_check CHECK (amount >= 0 AND gst >= 0 AND gst <= amount),
    CONSTRAINT spare_transfers_source_check CHECK (source IN ('job_card', 'backfill')),
    CONSTRAINT spare_transfers_status_check CHECK (status IN ('Active', 'Reversed')),
    CONSTRAINT spare_transfers_reversed_check CHECK ((status = 'Reversed') = (reversed_at IS NOT NULL))
);

COMMENT ON TABLE public.spare_transfers IS
    'MAIN-159: spares one company''s stock supplied to the other company''s vehicle. Amount (incl. GST) frozen when posted; posted only by add_spare() (and MAIN-160''s backfill). Reversed, never deleted, when the spare is removed. Read by company_ledger_lines.';

CREATE UNIQUE INDEX spare_transfers_one_active_idx ON public.spare_transfers (issue_part_id) WHERE status = 'Active';
CREATE INDEX spare_transfers_issue_part_idx ON public.spare_transfers (issue_part_id);
CREATE INDEX spare_transfers_from_idx ON public.spare_transfers (from_company);
CREATE INDEX spare_transfers_to_idx ON public.spare_transfers (to_company);

ALTER TABLE public.spare_transfers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exec and finance view spare transfers" ON public.spare_transfers
    FOR SELECT USING (public.is_maintenance_exec() OR public.is_finance());

GRANT SELECT ON public.spare_transfers TO authenticated;
GRANT ALL ON public.spare_transfers TO service_role;

-- ── Drawing stock ────────────────────────────────────────────────────────────

-- The vehicle's company's stock first; the other company's only under a confirmed
-- transfer (the transaction-local app.spare_transfer flag, raised by add_spare alone).
CREATE OR REPLACE FUNCTION public.deduct_part_from_inventory() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card_id   uuid;
    v_job_card_type text;
    v_location_id   uuid;
    v_first         text;
    v_second        text;
    v_have_first    numeric;
    v_have_total    numeric;
    v_take_first    numeric;
    v_part          record;
    v_location      text;
BEGIN
    SELECT jc.id, jc.type, jc.location_id INTO v_job_card_id, v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        NEW.stock_draws := '{}'::jsonb;
        RETURN NEW;
    END IF;

    IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Cannot change stock without a workshop location.';
    END IF;

    v_first  := public.job_card_stock_company(v_job_card_id);
    v_second := CASE v_first WHEN 'nvs_travels' THEN 'nvs_travel_solutions' ELSE 'nvs_travels' END;

    -- Both rows locked, in a fixed order, before either is read.
    PERFORM 1 FROM public.part_stock
    WHERE  part_id = NEW.part_id AND location_id = v_location_id
    ORDER  BY company
    FOR UPDATE;

    SELECT coalesce(sum(quantity) FILTER (WHERE company = v_first), 0), coalesce(sum(quantity), 0)
    INTO   v_have_first, v_have_total
    FROM   public.part_stock
    WHERE  part_id = NEW.part_id AND location_id = v_location_id;

    SELECT name, unit INTO v_part FROM public.parts WHERE id = NEW.part_id;

    IF v_have_total < NEW.quantity_used THEN
        SELECT name INTO v_location FROM public.workshop_locations WHERE id = v_location_id;
        RAISE EXCEPTION 'Not enough stock: % has % available at %, needed %.',
            COALESCE(v_part.name, 'part'), v_have_total, COALESCE(v_location, 'this location'), NEW.quantity_used;
    END IF;

    v_take_first := least(v_have_first, NEW.quantity_used);

    IF NEW.quantity_used - v_take_first > 0
       AND auth.uid() IS NOT NULL
       AND coalesce(current_setting('app.spare_transfer', true), '') <> 'on' THEN
        RAISE EXCEPTION '%: % must be transferred from %, which holds the stock at this workshop.',
            v_part.name,
            CASE WHEN v_take_first > 0
                 THEN format('%s %s are under %s, the other %s', v_take_first, coalesce(v_part.unit, ''),
                             public.stock_company_label(v_first), NEW.quantity_used - v_take_first)
                 ELSE format('%s has none, so all %s', public.stock_company_label(v_first), NEW.quantity_used)
            END,
            public.stock_company_label(v_second)
            USING HINT = 'NEEDS_TRANSFER',
                  DETAIL = json_build_object('part_id', NEW.part_id, 'part_name', v_part.name, 'unit', v_part.unit,
                                             'to_company', v_first, 'from_company', v_second,
                                             'own_quantity', v_take_first,
                                             'quantity', NEW.quantity_used - v_take_first)::text;
    END IF;

    NEW.stock_draws := '{}'::jsonb;

    IF v_take_first > 0 THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_first, -v_take_first);
        NEW.stock_draws := NEW.stock_draws || jsonb_build_object(v_first, v_take_first);
    END IF;
    IF NEW.quantity_used - v_take_first > 0 THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_second, -(NEW.quantity_used - v_take_first));
        NEW.stock_draws := NEW.stock_draws || jsonb_build_object(v_second, NEW.quantity_used - v_take_first);
    END IF;

    RETURN NEW;
END;
$$;

-- ── Quoting a transfer ───────────────────────────────────────────────────────

-- The GST rate behind stock found in an audit: that of the part's latest cost, chosen as
-- part_cost_lots chooses it (latest purchase, else latest opening price).
CREATE OR REPLACE FUNCTION public.part_latest_cost_gst_rate(p_part_id uuid) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT x.rate FROM (
        SELECT pii.gst_rate::numeric AS rate, 1 AS r, pi.invoice_date::timestamp AS t, pi.created_at AS t2
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = p_part_id AND NOT public.is_workshop_move_invoice(pi.purchase_number)
        UNION ALL
        SELECT o.gst_rate::numeric, 0, o.created_at::timestamp, o.created_at::timestamp
        FROM   public.opening_stock_lots o
        WHERE  o.part_id = p_part_id
    ) x
    ORDER BY x.r DESC, x.t DESC, x.t2 DESC
    LIMIT 1;
$$;

-- What a spare's draw from the other company comes to: quantity, cost incl. GST and GST
-- per rate of the lots it took. NULL when the spare takes nothing from the other company.
-- Reads stock_cost_draws, so it is called after the spare is inserted.
CREATE OR REPLACE FUNCTION public.spare_transfer_quote(p_issue_part_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_ip        record;
    v_to        text;
    v_from      text;
    v_qty       numeric;
    v_rows      jsonb;
    v_amount    numeric;
    v_gst       numeric;
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

    WITH d AS (
        SELECT d.amount,
               coalesce(pii.gst_rate, o.gst_rate,
                        CASE WHEN d.found_audit_item_id IS NOT NULL THEN public.part_latest_cost_gst_rate(d.part_id) END,
                        0)::numeric AS rate
        FROM   public.stock_cost_draws d
        LEFT JOIN public.purchase_invoice_items pii ON pii.id = d.purchase_item_id
        LEFT JOIN public.opening_stock_lots     o   ON o.id   = d.opening_lot_id
        WHERE  d.issue_part_id = p_issue_part_id AND d.company = v_from
    ), r AS (
        SELECT rate, sum(amount) AS incl,
               round(sum(amount) * 100 / (100 + rate), 2) AS before
        FROM   d GROUP BY rate
    )
    SELECT jsonb_agg(jsonb_build_object('rate', rate, 'before_gst', before, 'gst', incl - before, 'incl_gst', incl)
                     ORDER BY rate),
           sum(incl), sum(incl - before)
    INTO   v_rows, v_amount, v_gst
    FROM   r;

    RETURN jsonb_build_object(
        'issue_part_id',   p_issue_part_id,
        'part_id',         v_ip.part_id,
        'part_name',       v_ip.part_name,
        'unit',            v_ip.unit,
        'from_company',    v_from,
        'to_company',      v_to,
        'quantity',        v_qty,
        'own_quantity',    v_ip.quantity_used - v_qty,
        'amount',          coalesce(v_amount, 0),
        'gst',             coalesce(v_gst, 0),
        'gst_breakdown',   coalesce(v_rows, '[]'::jsonb),
        'job_card_number', v_ip.job_card_number,
        'vehicle',         v_ip.vehicle_number);
END;
$$;

REVOKE ALL ON FUNCTION public.spare_transfer_quote(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spare_transfer_quote(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.part_latest_cost_gst_rate(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.part_latest_cost_gst_rate(uuid) TO service_role;

-- ── Adding a spare ───────────────────────────────────────────────────────────

-- The one way the app adds a spare. p_spare: { issue_id, part_id, quantity_used,
-- confirm_transfer?: { amount } }. Without confirm_transfer, a spare that needs the other
-- company's stock is refused with HINT NEEDS_TRANSFER and the quote in DETAIL (worked out
-- by adding it in a subtransaction that is rolled back). With it, the spare is added and
-- the transfer posted — unless the quote no longer matches what was confirmed
-- (TRANSFER_CHANGED, new quote in DETAIL). p_spare is jsonb: do not add a parameter.
CREATE OR REPLACE FUNCTION public.add_spare(p_spare jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_issue   uuid    := (p_spare ->> 'issue_id')::uuid;
    v_part    uuid    := (p_spare ->> 'part_id')::uuid;
    v_qty     numeric := (p_spare ->> 'quantity_used')::numeric;
    v_confirm numeric := (p_spare -> 'confirm_transfer' ->> 'amount')::numeric;
    v_id      uuid;
    v_quote   jsonb;
    v_hint    text;
    v_detail  text;
    v_user    text;
    v_tid     uuid;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION 'Only maintenance executives can add spares.' USING ERRCODE = '42501';
    END IF;
    IF v_issue IS NULL OR v_part IS NULL THEN
        RAISE EXCEPTION 'Choose the work item and the part.' USING ERRCODE = '22023';
    END IF;
    IF v_qty IS NULL OR v_qty <= 0 THEN
        RAISE EXCEPTION 'Enter a quantity greater than 0.' USING ERRCODE = '22023';
    END IF;

    IF v_confirm IS NULL THEN
        BEGIN
            INSERT INTO public.issue_parts (issue_id, part_id, quantity_used, added_by)
            VALUES (v_issue, v_part, v_qty, auth.uid())
            RETURNING id INTO v_id;
            RETURN jsonb_build_object('issue_part_id', v_id, 'transfer', NULL);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
            IF v_hint IS DISTINCT FROM 'NEEDS_TRANSFER' THEN
                RAISE;
            END IF;
        END;

        -- Work out the quote by adding the spare for real, then rolling it back.
        BEGIN
            PERFORM set_config('app.spare_transfer', 'on', true);
            INSERT INTO public.issue_parts (issue_id, part_id, quantity_used, added_by)
            VALUES (v_issue, v_part, v_qty, auth.uid())
            RETURNING id INTO v_id;
            v_quote := public.spare_transfer_quote(v_id);
            RAISE EXCEPTION 'quote' USING HINT = 'TRANSFER_QUOTE_ROLLBACK', DETAIL = coalesce(v_quote, '{}'::jsonb)::text;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_detail = PG_EXCEPTION_DETAIL;
            IF v_hint IS DISTINCT FROM 'TRANSFER_QUOTE_ROLLBACK' THEN
                RAISE;   -- e.g. PART_NEEDS_PRICE for the other company's stock
            END IF;
            v_quote := v_detail::jsonb;
        END;

        RAISE EXCEPTION 'This spare needs % % transferred from %. Confirm the transfer to add it.',
            v_quote ->> 'quantity', coalesce(v_quote ->> 'unit', ''), public.stock_company_label(v_quote ->> 'from_company')
            USING HINT = 'NEEDS_TRANSFER', DETAIL = (v_quote - 'issue_part_id')::text;
    END IF;

    -- Confirmed.
    PERFORM set_config('app.spare_transfer', 'on', true);
    INSERT INTO public.issue_parts (issue_id, part_id, quantity_used, added_by)
    VALUES (v_issue, v_part, v_qty, auth.uid())
    RETURNING id INTO v_id;
    PERFORM set_config('app.spare_transfer', '', true);

    v_quote := public.spare_transfer_quote(v_id);

    IF v_quote IS NULL THEN
        -- The vehicle's company has enough stock now: nothing to transfer.
        RETURN jsonb_build_object('issue_part_id', v_id, 'transfer', NULL);
    END IF;

    IF round((v_quote ->> 'amount')::numeric, 2) <> round(v_confirm, 2) THEN
        RAISE EXCEPTION 'The transfer now comes to ₹% instead of ₹% — the stock or its prices changed. Check the new figures and confirm again.',
            to_char((v_quote ->> 'amount')::numeric, 'FM999999990.00'), to_char(v_confirm, 'FM999999990.00')
            USING HINT = 'TRANSFER_CHANGED', DETAIL = (v_quote - 'issue_part_id')::text;
    END IF;

    SELECT name INTO v_user FROM public.users WHERE id = auth.uid();

    INSERT INTO public.spare_transfers (
        issue_part_id, issue_id, job_card_id, job_card_number, vehicle_number,
        part_id, part_name, unit, quantity, from_company, to_company,
        amount, gst, gst_breakdown, source, posted_by, posted_by_name)
    SELECT v_id, v_issue, i.job_card_id, (v_quote ->> 'job_card_number')::integer, v_quote ->> 'vehicle',
           v_part, v_quote ->> 'part_name', v_quote ->> 'unit', (v_quote ->> 'quantity')::numeric,
           v_quote ->> 'from_company', v_quote ->> 'to_company',
           (v_quote ->> 'amount')::numeric, (v_quote ->> 'gst')::numeric, v_quote -> 'gst_breakdown',
           'job_card', auth.uid(), v_user
    FROM   public.issues i WHERE i.id = v_issue
    RETURNING id INTO v_tid;

    RETURN jsonb_build_object('issue_part_id', v_id,
                              'transfer', (v_quote - 'issue_part_id') || jsonb_build_object('id', v_tid));
END;
$$;

REVOKE ALL ON FUNCTION public.add_spare(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_spare(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_spare(jsonb) TO service_role;

-- ── Removing a spare reverses its transfer ───────────────────────────────────

-- BEFORE DELETE so it runs whatever removes the spare (the delete RPC, an issue or job
-- card being deleted). The stock itself goes back through stock_draws, as before.
CREATE OR REPLACE FUNCTION public.reverse_spare_transfer_on_delete() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    UPDATE public.spare_transfers t
    SET    status           = 'Reversed',
           reversed_at      = now(),
           reversed_by      = auth.uid(),
           reversed_by_name = (SELECT name FROM public.users WHERE id = auth.uid())
    WHERE  t.issue_part_id = OLD.id AND t.status = 'Active';
    RETURN OLD;
END;
$$;

CREATE TRIGGER trg_reverse_spare_transfer BEFORE DELETE ON public.issue_parts
    FOR EACH ROW EXECUTE FUNCTION public.reverse_spare_transfer_on_delete();

-- A transferred spare's quantity, part, work item and draws are fixed: changing them
-- would move stock the posted transfer no longer matches. Remove and add it again.
CREATE OR REPLACE FUNCTION public.guard_transferred_spare() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;
    IF (NEW.part_id, NEW.issue_id, NEW.quantity_used, NEW.stock_draws)
       IS NOT DISTINCT FROM (OLD.part_id, OLD.issue_id, OLD.quantity_used, OLD.stock_draws) THEN
        RETURN NEW;
    END IF;
    IF EXISTS (SELECT 1 FROM public.spare_transfers WHERE issue_part_id = OLD.id AND status = 'Active') THEN
        RAISE EXCEPTION 'This spare came from the other company''s stock through a transfer, so it cannot be changed. Remove it and add it again.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_guard_transferred_spare BEFORE UPDATE ON public.issue_parts
    FOR EACH ROW EXECUTE FUNCTION public.guard_transferred_spare();

-- ── Cost and value use the frozen amount ─────────────────────────────────────

-- A spare's cost incl. GST, for anyone: its own company's draws at first-in-first-out
-- cost plus its transfer's frozen amount. NULL when it has no draws or a draw has no price.
CREATE OR REPLACE FUNCTION public.spare_cost_amount(p_issue_part_id uuid) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    WITH t AS (
        SELECT from_company, amount FROM public.spare_transfers
        WHERE  issue_part_id = p_issue_part_id AND status = 'Active'
    )
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM public.stock_cost_draws d WHERE d.issue_part_id = p_issue_part_id) THEN NULL
        WHEN EXISTS (SELECT 1 FROM public.stock_cost_draws d
                     WHERE d.issue_part_id = p_issue_part_id AND d.unit_cost IS NULL
                       AND d.company IS DISTINCT FROM (SELECT from_company FROM t)) THEN NULL
        ELSE coalesce((SELECT sum(d.amount) FROM public.stock_cost_draws d
                       WHERE d.issue_part_id = p_issue_part_id
                         AND d.company IS DISTINCT FROM (SELECT from_company FROM t)), 0)
           + coalesce((SELECT amount FROM t), 0)
    END;
$$;

REVOKE ALL ON FUNCTION public.spare_cost_amount(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spare_cost_amount(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.spare_cost(ip public.issue_parts) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT CASE
        WHEN NOT (public.is_maintenance_exec() OR public.is_finance()) THEN NULL
        ELSE public.spare_cost_amount(ip.id)
    END;
$$;

CREATE OR REPLACE FUNCTION public.job_card_value(jc public.job_cards) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT CASE
        WHEN NOT (public.is_maintenance_exec() OR public.is_finance()) THEN NULL
        WHEN jc.type = 'Outsource' THEN coalesce(
            (SELECT max(oi.approved_amount) FROM public.outsource_invoices oi WHERE oi.job_card_id = jc.id),
            (SELECT sum(bsv.amount)
             FROM   public.batch_service_vehicles bsv
             JOIN   public.batch_services bs ON bs.id = bsv.batch_service_id
             WHERE  bsv.job_card_id = jc.id AND bs.status <> 'Cancelled'))
        WHEN EXISTS (
            SELECT 1 FROM public.issues i
            JOIN   public.issue_parts ip ON ip.issue_id = i.id
            WHERE  i.job_card_id = jc.id
              AND  EXISTS (SELECT 1 FROM public.stock_cost_draws d WHERE d.issue_part_id = ip.id)
              AND  public.spare_cost_amount(ip.id) IS NULL) THEN NULL
        ELSE coalesce((
            SELECT sum(public.spare_cost_amount(ip.id)) FROM public.issues i
            JOIN   public.issue_parts ip ON ip.issue_id = i.id
            WHERE  i.job_card_id = jc.id), 0)
    END;
$$;

-- The spare's active transfer, for the job card screen: which company supplied how much.
-- The amount only for those who see costs.
CREATE OR REPLACE FUNCTION public.spare_transfer(ip public.issue_parts) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT jsonb_build_object(
               'id',           t.id,
               'from_company', t.from_company,
               'to_company',   t.to_company,
               'quantity',     t.quantity,
               'amount',       CASE WHEN public.is_maintenance_exec() OR public.is_finance() THEN t.amount END,
               'gst',          CASE WHEN public.is_maintenance_exec() OR public.is_finance() THEN t.gst END,
               'posted_at',    t.posted_at)
    FROM   public.spare_transfers t
    WHERE  t.issue_part_id = ip.id AND t.status = 'Active';
$$;

REVOKE ALL ON FUNCTION public.spare_transfer(public.issue_parts) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.spare_transfer(public.issue_parts) TO authenticated;
GRANT EXECUTE ON FUNCTION public.spare_transfer(public.issue_parts) TO service_role;

-- ── Company ledgers ──────────────────────────────────────────────────────────

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
$$;
