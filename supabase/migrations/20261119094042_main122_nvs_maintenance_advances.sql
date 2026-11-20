-- MAIN-122: NVS Maintenance account is repaid like Manjunath, Gokilavanan and PCN.
-- An advance it paid on an accepted invoice now goes under Advances to repay, and the
-- supplier ledger marks it as to be repaid. Accounts stays company money.
--
-- The people who are repaid were listed in five places; advance_people() is now the
-- one list, in display order, and the app mirrors it in ADVANCE_PEOPLE
-- (src/constants/supplierLedger.js). Adding a person is a change to this function and
-- that constant. Each value must also be a Paid By option (outsource_invoices_paid_by_check).
-- No return columns change, so CREATE OR REPLACE is enough.

CREATE OR REPLACE FUNCTION public.advance_people() RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select array['NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN', 'NVS Maintenance account']
$$;

ALTER TABLE public.advance_repayments DROP CONSTRAINT advance_repayments_person_check;
ALTER TABLE public.advance_repayments ADD CONSTRAINT advance_repayments_person_check
    CHECK (person = any(public.advance_people()));

CREATE OR REPLACE FUNCTION public.advance_ledger_lines() RETURNS TABLE(person text, entry_at timestamp with time zone, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select oi.paid_by, coalesce(oi.accepted_at, oi.updated_at), oi.id, 'advance',
         oi.advance_amount, true, public.invoice_submitted_day(oi),
         oi.invoice_no, jc.job_card_number, bs.batch_number,
         jsonb_build_object(
             'supplier', s.entity_name, 'supplier_id', s.id,
             'approved', oi.approved_amount, 'to_supplier', oi.approved_amount - oi.advance_amount,
             'purchase_invoice_id', oi.purchase_invoice_id,
             'purchase_invoice_kind', pi.kind)
  from   public.outsource_invoices oi
  left join public.job_cards         jc on jc.id = oi.job_card_id
  left join public.batch_services    bs on bs.id = oi.batch_service_id
  left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
  left join public.suppliers         s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id)
  where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')
    and  oi.advance_amount > 0
    and  oi.paid_by = any(public.advance_people())

  union all

  select r.person, r.created_at, r.id,
         case when r.status = 'Cancelled' then 'cancelled' else 'repayment' end,
         -r.amount, r.status = 'Active', null, null, null, null,
         jsonb_build_object(
             'paid_on', r.paid_on, 'payment_method', r.payment_method, 'bank', r.bank, 'utr', r.utr,
             'recorded_by', ru.name, 'cancelled_at', r.cancelled_at,
             'cancelled_by', cu.name, 'cancel_reason', r.cancel_reason)
  from   public.advance_repayments r
  left join public.users ru on ru.id = r.recorded_by
  left join public.users cu on cu.id = r.cancelled_by
$$;

CREATE OR REPLACE FUNCTION public.supplier_ledger_lines() RETURNS TABLE(supplier_id uuid, entry_at timestamp with time zone, seq integer, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_id uuid, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with inv as (
      select oi.*,
             coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) as sup_id,
             public.invoice_submitted_day(oi)               as submitted_day,
             coalesce(oi.accepted_at, oi.updated_at)        as entered_at,
             oi.paid_by = any(public.advance_people()) as by_person,
             jc.job_card_number, bs.batch_number,
             pi.kind as purchase_invoice_kind
      from   public.outsource_invoices oi
      left join public.job_cards         jc on jc.id = oi.job_card_id
      left join public.batch_services    bs on bs.id = oi.batch_service_id
      left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
      where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
        and  (bs.id is null or bs.status = 'Active')
  )
  select inv.sup_id, inv.entered_at, 1, inv.id, 'invoice',
         inv.approved_amount, true,
         inv.submitted_day + coalesce(s.payment_terms_days, 0),
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object(
             'finance_status',  inv.finance_payment_status,
             'submitted_on',    inv.submitted_day,
             'paid_by',         inv.paid_by,
             'advance',         inv.advance_amount,
             'to_supplier',     inv.approved_amount - inv.advance_amount,
             'advance_by_person', inv.by_person,
             'purchase_invoice_id', inv.purchase_invoice_id,
             'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.entered_at, 2, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by, 'advance_by_person', inv.by_person,
                            'purchase_invoice_id', inv.purchase_invoice_id,
                            'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv
  where  inv.advance_amount > 0

  union all

  select p.supplier_id, p.created_at, 3, p.id,
         case when p.status = 'Cancelled' then 'cancelled' else 'payment' end,
         -(p.amount_paid + p.tds_amount),
         p.status = 'Active',
         null, null, null, null, null,
         jsonb_build_object(
             'paid_on', p.paid_on, 'amount_paid', p.amount_paid, 'tds_amount', p.tds_amount,
             'payment_method', p.payment_method, 'bank', p.bank, 'utr', p.utr,
             'recorded_by', ru.name, 'cancelled_at', p.cancelled_at,
             'cancelled_by', cu.name, 'cancel_reason', p.cancel_reason)
  from   public.supplier_payments p
  left join public.users ru on ru.id = p.recorded_by
  left join public.users cu on cu.id = p.cancelled_by

  union all

  select a.supplier_id, least(public.end_of_ist_day(a.as_of), a.created_at), 4, a.id,
         case when a.status = 'Reversed' then 'reversed' else 'adjustment' end,
         a.amount, a.status = 'Active', a.as_of, null, null, null, null,
         jsonb_build_object(
             'as_of', a.as_of, 'confirmed_against', a.confirmed_against,
             'system_balance', a.system_balance, 'confirmed_balance', a.confirmed_balance,
             'reason', a.reason, 'created_by', u.name, 'created_at', a.created_at,
             'reversed_at', a.reversed_at, 'reversed_by', ru.name, 'reverse_reason', a.reverse_reason)
  from   public.supplier_ledger_adjustments a
  left join public.users u  on u.id  = a.created_by
  left join public.users ru on ru.id = a.reversed_by
$$;

CREATE OR REPLACE FUNCTION public.get_advance_balances() RETURNS TABLE(person text, owed numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, last_repaid_on date)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH people(person, ord) AS (
        SELECT * FROM unnest(public.advance_people()) WITH ORDINALITY
    ),
    bal AS (
        SELECT l.person AS p, sum(l.amount) FILTER (WHERE l.counts) AS total
        FROM   public.advance_ledger_lines() l GROUP BY l.person
    ),
    open_items AS (
        SELECT o.person AS p,
               sum(o.remaining) FILTER (WHERE o.bucket = 'overdue')        AS overdue,
               sum(o.remaining) FILTER (WHERE o.bucket = 'this_wednesday') AS this_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'next_wednesday') AS next_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'later')          AS later
        FROM   public.advance_open_items(v_today) o GROUP BY o.person
    )
    SELECT pe.person, coalesce(bal.total, 0),
           coalesce(oi.overdue, 0), coalesce(oi.this_wed, 0), coalesce(oi.next_wed, 0), coalesce(oi.later, 0),
           (SELECT max(r.paid_on) FROM public.advance_repayments r WHERE r.person = pe.person AND r.status = 'Active')
    FROM   people pe
    LEFT JOIN bal        ON bal.p = pe.person
    LEFT JOIN open_items oi ON oi.p = pe.person
    ORDER  BY pe.ord;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_advance_repayment(p_person text, p_payment jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_amount  numeric := coalesce(nullif(p_payment->>'amount', '')::numeric, 0);
    v_paid_on date    := nullif(p_payment->>'paid_on', '')::date;
    v_method  text    := nullif(p_payment->>'payment_method', '');
    v_id      uuid;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF p_person IS NULL OR NOT (p_person = any(public.advance_people())) THEN
        RAISE EXCEPTION 'Choose who is being repaid.';
    END IF;
    -- One repayment at a time per person.
    PERFORM pg_advisory_xact_lock(hashtext('advance_repayments:' || p_person));

    IF v_amount <> round(v_amount, 2) THEN
        RAISE EXCEPTION 'Amounts can have at most two decimals.';
    END IF;
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Enter the amount repaid.';
    END IF;
    IF v_paid_on IS NULL THEN
        RAISE EXCEPTION 'Enter the date the repayment was made.';
    END IF;
    IF v_paid_on > (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
        RAISE EXCEPTION 'The repayment date cannot be in the future.';
    END IF;
    IF v_method IS NULL THEN
        RAISE EXCEPTION 'Choose the payment method.';
    END IF;
    IF v_method <> 'Cash' AND (nullif(p_payment->>'bank', '') IS NULL OR nullif(btrim(p_payment->>'utr'), '') IS NULL) THEN
        RAISE EXCEPTION 'Bank and UTR are required for every method except Cash.';
    END IF;

    INSERT INTO public.advance_repayments (person, paid_on, amount, payment_method, bank, utr, recorded_by)
    VALUES (
        p_person, v_paid_on, v_amount, v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;
