-- MAIN-163 Reconciling the company ledgers (epic MAIN-154).
--
-- Finance reconciles each company's ledger against Tally the way a supplier's balance is
-- reconciled (MAIN-119): enter the figure confirmed as of a date; the app freezes its own
-- figure over everything entered up to the end of that day (or up to now, for today), and
-- the difference is posted as an adjustment line. An adjustment posted in error is
-- reversed with a reason; it stays on the ledger, struck through, and out of every total.
--
-- A company ledger has two running figures, and each is reconciled on its own
-- (user decision 2026-11-25): `balance` = 'spent' (Spent to date) or 'owed' (Owed between
-- companies, positive = the other company owes this one). An adjustment moves only the
-- figure it reconciles and carries no GST.
--
-- Each company keeps its own books, so an adjustment to one company's Owed figure does not
-- post the opposite entry into the other company's ledger.
--
-- The ledger is otherwise derived (MAIN-156); this table is its only stored line. It has a
-- SELECT policy only — every write goes through the two functions below.

-- ── Table ─────────────────────────────────────────────────────────────────────────
CREATE TABLE public.company_ledger_adjustments (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company           text NOT NULL,
    balance           text NOT NULL,
    as_of             date NOT NULL,
    confirmed_against text NOT NULL DEFAULT 'Tally',
    system_balance    numeric NOT NULL,
    confirmed_balance numeric NOT NULL,
    amount            numeric GENERATED ALWAYS AS (confirmed_balance - system_balance) STORED,
    reason            text NOT NULL,
    created_by        uuid REFERENCES public.users(id),
    created_at        timestamptz NOT NULL DEFAULT now(),
    status            text NOT NULL DEFAULT 'Active',
    reversed_at       timestamptz,
    reversed_by       uuid REFERENCES public.users(id),
    reverse_reason    text,
    CONSTRAINT company_ledger_adjustments_company_check
        CHECK (company = ANY (ARRAY['nvs_travels', 'nvs_travel_solutions'])),
    CONSTRAINT company_ledger_adjustments_balance_check
        CHECK (balance = ANY (ARRAY['spent', 'owed'])),
    CONSTRAINT company_ledger_adjustments_source_check
        CHECK (confirmed_against = 'Tally'),
    CONSTRAINT company_ledger_adjustments_reason_check
        CHECK (nullif(btrim(reason), '') IS NOT NULL),
    CONSTRAINT company_ledger_adjustments_status_check
        CHECK (status = ANY (ARRAY['Active', 'Reversed'])),
    CONSTRAINT company_ledger_adjustments_reverse_reason_check
        CHECK (status = 'Active' OR (reversed_at IS NOT NULL AND nullif(btrim(reverse_reason), '') IS NOT NULL))
);

CREATE INDEX company_ledger_adjustments_company_idx
    ON public.company_ledger_adjustments USING btree (company, balance, as_of);

COMMENT ON TABLE public.company_ledger_adjustments IS
  'MAIN-163: reconciliations of a company ledger against Tally. balance = spent (Spent to date) or owed (Owed between companies). amount = confirmed − app figure. Written only by reconcile_company_ledger / reverse_company_ledger_adjustment.';

ALTER TABLE public.company_ledger_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exec and finance read company ledger adjustments" ON public.company_ledger_adjustments
    FOR SELECT USING (public.is_maintenance_exec() OR public.is_finance());

GRANT SELECT ON public.company_ledger_adjustments TO authenticated;
GRANT ALL ON public.company_ledger_adjustments TO service_role;


-- ── Ledger lines: the MAIN-156/166 lines, plus adjustments ─────────────────────────
CREATE OR REPLACE FUNCTION public.company_ledger_lines(p_company text)
RETURNS TABLE(
    entry_at   timestamptz,
    seq        integer,
    line_id    uuid,
    kind       text,
    doc_date   date,
    spend      numeric,
    owed       numeric,
    gst        numeric,
    gst_status text,
    detail     jsonb)
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
$$;

REVOKE ALL ON FUNCTION public.company_ledger_lines(text) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.company_ledger_lines(text) TO service_role;

COMMENT ON FUNCTION public.company_ledger_lines(text) IS
  'MAIN-156: every line of one company''s ledger, derived from purchases, accepted invoices and vehicle sales, plus its reconciliation adjustments (MAIN-163). Internal; read through get_company_ledger.';


-- ── Writers ───────────────────────────────────────────────────────────────────────
-- p_reconciliation: { balance: 'spent'|'owed', as_of: 'yyyy-mm-dd', confirmed_balance, reason }.
-- jsonb so a later field needs no new parameter (a new parameter under CREATE OR REPLACE
-- would leave a second overload behind).
CREATE OR REPLACE FUNCTION public.reconcile_company_ledger(p_company text, p_reconciliation jsonb)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_balance   text    := p_reconciliation->>'balance';
    v_as_of     date;
    v_confirmed numeric;
    v_reason    text    := nullif(btrim(p_reconciliation->>'reason'), '');
    v_system    numeric;
    v_id        uuid;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users
                   WHERE id = auth.uid() AND role IN ('finance', 'super_admin') AND is_active) THEN
        RAISE EXCEPTION 'Only finance can reconcile the company ledgers.' USING ERRCODE = '42501';
    END IF;
    PERFORM public.assert_ledger_company(p_company);

    IF v_balance IS NULL OR v_balance NOT IN ('spent', 'owed') THEN
        RAISE EXCEPTION 'Choose which figure you are reconciling.';
    END IF;

    BEGIN
        v_as_of     := (p_reconciliation->>'as_of')::date;
        v_confirmed := (p_reconciliation->>'confirmed_balance')::numeric;
    EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
        RAISE EXCEPTION 'Enter a valid date and amount.';
    END;

    IF v_as_of IS NULL OR v_as_of > (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
        RAISE EXCEPTION 'Choose a date that is not in the future.';
    END IF;
    IF v_confirmed IS NULL OR v_confirmed <> round(v_confirmed, 2) THEN
        RAISE EXCEPTION 'Enter the confirmed figure, with at most two decimals.';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'Give a reason.';
    END IF;

    -- One reconciliation of a company at a time, so two can't freeze the same figure.
    PERFORM pg_advisory_xact_lock(hashtext('company_ledger_reconcile'), hashtext(p_company));

    SELECT coalesce(sum(CASE v_balance WHEN 'spent' THEN l.spend ELSE l.owed END), 0) INTO v_system
    FROM   public.company_ledger_lines(p_company) l
    WHERE  l.entry_at <= least(public.end_of_ist_day(v_as_of), now());

    INSERT INTO public.company_ledger_adjustments
        (company, balance, as_of, confirmed_against, system_balance, confirmed_balance, reason, created_by)
    VALUES (p_company, v_balance, v_as_of, 'Tally', v_system, v_confirmed, v_reason, auth.uid())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_company_ledger(text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_company_ledger(text, jsonb) TO authenticated, service_role;

COMMENT ON FUNCTION public.reconcile_company_ledger(text, jsonb) IS
  'MAIN-163: finance/super_admin record the Spent to date or Owed between companies figure confirmed in Tally as of a date; the app''s figure is frozen and the difference posted. Do not add a parameter — p_reconciliation is jsonb.';


CREATE OR REPLACE FUNCTION public.reverse_company_ledger_adjustment(p_adjustment_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_status text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users
                   WHERE id = auth.uid() AND role IN ('finance', 'super_admin') AND is_active) THEN
        RAISE EXCEPTION 'Only finance can reconcile the company ledgers.' USING ERRCODE = '42501';
    END IF;
    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this adjustment.';
    END IF;

    SELECT status INTO v_status FROM public.company_ledger_adjustments WHERE id = p_adjustment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Adjustment not found.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This adjustment is already reversed.';
    END IF;

    UPDATE public.company_ledger_adjustments
    SET    status         = 'Reversed',
           reversed_at    = now(),
           reversed_by    = auth.uid(),
           reverse_reason = btrim(p_reason)
    WHERE  id = p_adjustment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reverse_company_ledger_adjustment(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reverse_company_ledger_adjustment(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.reverse_company_ledger_adjustment(uuid, text) IS
  'MAIN-163: undoes a company ledger adjustment posted in error, with a reason. It stays on the ledger, struck through, and out of every total.';
