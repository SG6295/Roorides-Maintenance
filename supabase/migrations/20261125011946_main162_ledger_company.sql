-- MAIN-162 (epic MAIN-154): supplier and advance ledgers split by company.
--
-- Each company owes its suppliers and repays its people separately, as Tally keeps them.
-- An invoice and its advance belong to the invoice's stored company (outsource_invoices.company,
-- MAIN-161). Payments, repayments and reconciliations store their own; everything recorded
-- before this is NVS Travels. Every figure — balance, Wednesday buckets, open items, running
-- balance, awaiting acceptance — is worked out per supplier (or person) AND company, so a
-- payment in one company never clears an invoice in the other. Credit days stay per supplier.
--
-- The readers and reconcile_supplier_balance gain p_company; their argument lists change, so
-- they are dropped and recreated (CREATE OR REPLACE would leave the old version as a second
-- overload). The two record functions take the company inside p_payment — no new parameter.

-- ── 1. The company column ────────────────────────────────────────────────────────

ALTER TABLE public.supplier_payments
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT supplier_payments_company_check
        CHECK (company = ANY (ARRAY['nvs_travels'::text, 'nvs_travel_solutions'::text]));

ALTER TABLE public.advance_repayments
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT advance_repayments_company_check
        CHECK (company = ANY (ARRAY['nvs_travels'::text, 'nvs_travel_solutions'::text]));

ALTER TABLE public.supplier_ledger_adjustments
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT supplier_ledger_adjustments_company_check
        CHECK (company = ANY (ARRAY['nvs_travels'::text, 'nvs_travel_solutions'::text]));

COMMENT ON COLUMN public.supplier_payments.company IS
    'MAIN-162: whose supplier ledger the payment is in. Fixed once recorded — a wrong one is cancelled and recorded again.';
COMMENT ON COLUMN public.advance_repayments.company IS
    'MAIN-162: which company repaid the advance. Fixed once recorded — a wrong one is cancelled and recorded again.';
COMMENT ON COLUMN public.supplier_ledger_adjustments.company IS
    'MAIN-162: whose supplier ledger was reconciled.';

DROP INDEX IF EXISTS public.supplier_payments_supplier_id_idx;
CREATE INDEX supplier_payments_supplier_id_idx ON public.supplier_payments USING btree (supplier_id, company, paid_on);
DROP INDEX IF EXISTS public.supplier_ledger_adjustments_supplier_id_idx;
CREATE INDEX supplier_ledger_adjustments_supplier_id_idx ON public.supplier_ledger_adjustments USING btree (supplier_id, company, as_of);
DROP INDEX IF EXISTS public.advance_repayments_person_idx;
CREATE INDEX advance_repayments_person_idx ON public.advance_repayments USING btree (person, company, created_at);

-- Refuses anything but the two companies, with a readable message.
CREATE FUNCTION public.assert_ledger_company(p_company text) RETURNS void
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public'
    AS $$
BEGIN
    IF p_company IS NULL OR NOT (p_company = ANY (ARRAY['nvs_travels', 'nvs_travel_solutions'])) THEN
        RAISE EXCEPTION 'Choose which company this is for.' USING HINT = 'LEDGER_COMPANY_REQUIRED';
    END IF;
END;
$$;

-- ── 2. The derived lines carry the company ───────────────────────────────────────
-- Return columns change, so drop the dependants first and recreate them.

DROP FUNCTION public.get_supplier_balances(uuid);
DROP FUNCTION public.get_supplier_open_items(uuid);
DROP FUNCTION public.get_supplier_statement(uuid);
DROP FUNCTION public.get_advance_balances();
DROP FUNCTION public.get_advance_open_items(text);
DROP FUNCTION public.get_advance_statement(text);
DROP FUNCTION public.reconcile_supplier_balance(uuid, date, text, numeric, text);
DROP FUNCTION public.supplier_open_items(date);
DROP FUNCTION public.advance_open_items(date);
DROP FUNCTION public.supplier_ledger_lines();
DROP FUNCTION public.advance_ledger_lines();

CREATE FUNCTION public.supplier_ledger_lines() RETURNS TABLE(supplier_id uuid, company text, entry_at timestamp with time zone, seq integer, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_id uuid, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
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
             pi.kind as purchase_invoice_kind,
             pi.purchase_number as purchase_invoice_number
      from   public.outsource_invoices oi
      left join public.job_cards         jc on jc.id = oi.job_card_id
      left join public.batch_services    bs on bs.id = oi.batch_service_id
      left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
      where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
        and  (bs.id is null or bs.status = 'Active')
  )
  select inv.sup_id, inv.company, inv.entered_at, 1, inv.id, 'invoice',
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
             'purchase_invoice_number', inv.purchase_invoice_number,
             'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.company, inv.entered_at, 2, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by, 'advance_by_person', inv.by_person,
                            'purchase_invoice_id', inv.purchase_invoice_id,
                            'purchase_invoice_number', inv.purchase_invoice_number,
                            'purchase_invoice_kind', inv.purchase_invoice_kind)
  from   inv
  where  inv.advance_amount > 0

  union all

  select p.supplier_id, p.company, p.created_at, 3, p.id,
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

  select a.supplier_id, a.company, least(public.end_of_ist_day(a.as_of), a.created_at), 4, a.id,
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

CREATE FUNCTION public.supplier_open_items(p_today date) RETURNS TABLE(supplier_id uuid, company text, line_id uuid, kind text, entry_at timestamp with time zone, due_date date, run_date date, amount numeric, remaining numeric, bucket text, invoice_no text, job_card_number integer, batch_number integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with lines as (
      select * from public.supplier_ledger_lines() where counts
  ),
  owed as (
      select l.supplier_id, l.company, l.line_id, l.kind, l.entry_at, l.due_date, l.amount,
             l.invoice_no, l.job_card_number, l.batch_number,
             sum(l.amount) over (partition by l.supplier_id, l.company
                                 order by l.due_date, l.entry_at, l.line_id) as cum
      from   lines l
      where  l.amount > 0
  ),
  credit as (
      select supplier_id, company, -sum(amount) as total
      from   lines
      where  amount < 0
      group  by supplier_id, company
  ),
  open_items as (
      select o.*, greatest(0, least(o.amount, o.cum - coalesce(c.total, 0))) as remaining
      from   owed o
      left join credit c on c.supplier_id = o.supplier_id and c.company = o.company
  )
  select o.supplier_id, o.company, o.line_id, o.kind, o.entry_at, o.due_date,
         public.payment_run_for(o.due_date), o.amount, o.remaining,
         case
             when public.payment_run_for(o.due_date) <  public.payment_run_for(p_today)     then 'overdue'
             when public.payment_run_for(o.due_date) =  public.payment_run_for(p_today)     then 'this_wednesday'
             when public.payment_run_for(o.due_date) =  public.payment_run_for(p_today) + 7 then 'next_wednesday'
             else 'later'
         end,
         o.invoice_no, o.job_card_number, o.batch_number
  from   open_items o
  where  o.remaining > 0
$$;

CREATE FUNCTION public.advance_ledger_lines() RETURNS TABLE(person text, company text, entry_at timestamp with time zone, line_id uuid, kind text, amount numeric, counts boolean, due_date date, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select oi.paid_by, oi.company, coalesce(oi.accepted_at, oi.updated_at), oi.id, 'advance',
         oi.advance_amount, true, public.invoice_submitted_day(oi),
         oi.invoice_no, jc.job_card_number, bs.batch_number,
         jsonb_build_object(
             'supplier', s.entity_name, 'supplier_id', s.id,
             'approved', oi.approved_amount, 'to_supplier', oi.approved_amount - oi.advance_amount,
             'purchase_invoice_id', oi.purchase_invoice_id,
             'purchase_invoice_number', pi.purchase_number,
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

  select r.person, r.company, r.created_at, r.id,
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

CREATE FUNCTION public.advance_open_items(p_today date) RETURNS TABLE(person text, company text, line_id uuid, entry_at timestamp with time zone, due_date date, run_date date, amount numeric, remaining numeric, bucket text, invoice_no text, job_card_number integer, batch_number integer, supplier text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with lines as (
      select * from public.advance_ledger_lines() where counts
  ),
  owed as (
      select l.*, sum(l.amount) over (partition by l.person, l.company order by l.due_date, l.entry_at, l.line_id) as cum
      from   lines l
      where  l.amount > 0
  ),
  credit as (
      select person, company, -sum(amount) as total from lines where amount < 0 group by person, company
  ),
  open_items as (
      select o.*, greatest(0, least(o.amount, o.cum - coalesce(c.total, 0))) as remaining
      from   owed o left join credit c on c.person = o.person and c.company = o.company
  )
  select o.person, o.company, o.line_id, o.entry_at, o.due_date, public.payment_run_for(o.due_date),
         o.amount, o.remaining,
         case
             when public.payment_run_for(o.due_date) <  public.payment_run_for(p_today)     then 'overdue'
             when public.payment_run_for(o.due_date) =  public.payment_run_for(p_today)     then 'this_wednesday'
             when public.payment_run_for(o.due_date) =  public.payment_run_for(p_today) + 7 then 'next_wednesday'
             else 'later'
         end,
         o.invoice_no, o.job_card_number, o.batch_number, o.detail->>'supplier'
  from   open_items o
  where  o.remaining > 0
$$;

REVOKE ALL ON FUNCTION public.supplier_ledger_lines() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.supplier_ledger_lines() TO service_role;
REVOKE ALL ON FUNCTION public.supplier_open_items(date) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.supplier_open_items(date) TO service_role;
REVOKE ALL ON FUNCTION public.advance_ledger_lines() FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.advance_ledger_lines() TO service_role;
REVOKE ALL ON FUNCTION public.advance_open_items(date) FROM PUBLIC, anon, authenticated;
GRANT ALL ON FUNCTION public.advance_open_items(date) TO service_role;

-- ── 3. Readers, one company at a time ────────────────────────────────────────────

CREATE FUNCTION public.get_supplier_balances(p_company text, p_supplier_id uuid DEFAULT NULL::uuid) RETURNS TABLE(supplier_id uuid, supplier_number integer, entity_name text, credit_days integer, outstanding numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, this_wednesday date, last_payment_on date, last_reconciled_on date, awaiting_acceptance bigint)
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
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    WITH bal AS (
        SELECT l.supplier_id AS sid, sum(l.amount) FILTER (WHERE l.counts) AS total
        FROM   public.supplier_ledger_lines() l
        WHERE  l.company = p_company
        GROUP  BY l.supplier_id
    ),
    open_items AS (
        SELECT o.supplier_id AS sid,
               sum(o.remaining) FILTER (WHERE o.bucket = 'overdue')        AS overdue,
               sum(o.remaining) FILTER (WHERE o.bucket = 'this_wednesday') AS this_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'next_wednesday') AS next_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'later')          AS later
        FROM   public.supplier_open_items(v_today) o
        WHERE  o.company = p_company
        GROUP  BY o.supplier_id
    ),
    pending AS (
        SELECT coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) AS sid, count(*) AS n
        FROM   public.outsource_invoices oi
        LEFT JOIN public.job_cards         jc ON jc.id = oi.job_card_id
        LEFT JOIN public.batch_services    bs ON bs.id = oi.batch_service_id
        LEFT JOIN public.purchase_invoices pi ON pi.id = oi.purchase_invoice_id
        WHERE  oi.submitted_on IS NOT NULL
          AND  oi.company = p_company
          AND  oi.finance_payment_status IN ('New', 'New (invoice pending)', 'Resubmitted', 'Hold')
          AND  (bs.id IS NULL OR bs.status = 'Active')
        GROUP  BY 1
    )
    SELECT s.id, s.supplier_number, s.entity_name, s.payment_terms_days,
           coalesce(bal.total, 0),
           coalesce(oi.overdue, 0), coalesce(oi.this_wed, 0),
           coalesce(oi.next_wed, 0), coalesce(oi.later, 0),
           public.payment_run_for(v_today),
           (SELECT max(p.paid_on) FROM public.supplier_payments p
            WHERE p.supplier_id = s.id AND p.company = p_company AND p.status = 'Active'),
           (SELECT max(a.as_of) FROM public.supplier_ledger_adjustments a
            WHERE a.supplier_id = s.id AND a.company = p_company AND a.status = 'Active'),
           coalesce(pending.n, 0)
    FROM   public.suppliers s
    LEFT JOIN bal        ON bal.sid     = s.id
    LEFT JOIN open_items oi ON oi.sid   = s.id
    LEFT JOIN pending    ON pending.sid = s.id
    WHERE  (p_supplier_id IS NULL OR s.id = p_supplier_id)
      AND  (p_supplier_id IS NOT NULL OR s.status = 'approved' OR bal.sid IS NOT NULL OR pending.sid IS NOT NULL)
    ORDER  BY s.entity_name;
END;
$$;

CREATE FUNCTION public.get_supplier_open_items(p_company text, p_supplier_id uuid) RETURNS TABLE(line_id uuid, kind text, entry_at timestamp with time zone, due_date date, run_date date, amount numeric, remaining numeric, bucket text, invoice_no text, job_card_number integer, batch_number integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    SELECT o.line_id, o.kind, o.entry_at, o.due_date, o.run_date, o.amount, o.remaining,
           o.bucket, o.invoice_no, o.job_card_number, o.batch_number
    FROM   public.supplier_open_items((now() AT TIME ZONE 'Asia/Kolkata')::date) o
    WHERE  o.supplier_id = p_supplier_id AND o.company = p_company
    ORDER  BY o.due_date, o.entry_at;
END;
$$;

CREATE FUNCTION public.get_supplier_statement(p_company text, p_supplier_id uuid) RETURNS TABLE(entry_at timestamp with time zone, kind text, line_id uuid, amount numeric, counts boolean, balance numeric, due_date date, invoice_id uuid, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    SELECT l.entry_at, l.kind, l.line_id, l.amount, l.counts,
           sum(CASE WHEN l.counts THEN l.amount ELSE 0 END)
               OVER (ORDER BY l.entry_at, l.seq, l.line_id ROWS UNBOUNDED PRECEDING),
           l.due_date, l.invoice_id, l.invoice_no, l.job_card_number, l.batch_number, l.detail
    FROM   public.supplier_ledger_lines() l
    WHERE  l.supplier_id = p_supplier_id AND l.company = p_company
    ORDER  BY l.entry_at, l.seq, l.line_id;
END;
$$;

CREATE FUNCTION public.get_advance_balances(p_company text) RETURNS TABLE(person text, owed numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, last_repaid_on date)
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
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    WITH people(person, ord) AS (
        SELECT * FROM unnest(public.advance_people()) WITH ORDINALITY
    ),
    bal AS (
        SELECT l.person AS p, sum(l.amount) FILTER (WHERE l.counts) AS total
        FROM   public.advance_ledger_lines() l
        WHERE  l.company = p_company
        GROUP  BY l.person
    ),
    open_items AS (
        SELECT o.person AS p,
               sum(o.remaining) FILTER (WHERE o.bucket = 'overdue')        AS overdue,
               sum(o.remaining) FILTER (WHERE o.bucket = 'this_wednesday') AS this_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'next_wednesday') AS next_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'later')          AS later
        FROM   public.advance_open_items(v_today) o
        WHERE  o.company = p_company
        GROUP  BY o.person
    )
    SELECT pe.person, coalesce(bal.total, 0),
           coalesce(oi.overdue, 0), coalesce(oi.this_wed, 0), coalesce(oi.next_wed, 0), coalesce(oi.later, 0),
           (SELECT max(r.paid_on) FROM public.advance_repayments r
            WHERE r.person = pe.person AND r.company = p_company AND r.status = 'Active')
    FROM   people pe
    LEFT JOIN bal        ON bal.p = pe.person
    LEFT JOIN open_items oi ON oi.p = pe.person
    ORDER  BY pe.ord;
END;
$$;

CREATE FUNCTION public.get_advance_open_items(p_company text, p_person text) RETURNS TABLE(line_id uuid, entry_at timestamp with time zone, due_date date, run_date date, amount numeric, remaining numeric, bucket text, invoice_no text, job_card_number integer, batch_number integer, supplier text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    SELECT o.line_id, o.entry_at, o.due_date, o.run_date, o.amount, o.remaining, o.bucket,
           o.invoice_no, o.job_card_number, o.batch_number, o.supplier
    FROM   public.advance_open_items((now() AT TIME ZONE 'Asia/Kolkata')::date) o
    WHERE  o.person = p_person AND o.company = p_company
    ORDER  BY o.due_date, o.entry_at;
END;
$$;

CREATE FUNCTION public.get_advance_statement(p_company text, p_person text) RETURNS TABLE(entry_at timestamp with time zone, kind text, line_id uuid, amount numeric, counts boolean, balance numeric, due_date date, invoice_no text, job_card_number integer, batch_number integer, detail jsonb)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;
    PERFORM public.assert_ledger_company(p_company);

    RETURN QUERY
    SELECT l.entry_at, l.kind, l.line_id, l.amount, l.counts,
           sum(CASE WHEN l.counts THEN l.amount ELSE 0 END)
               OVER (ORDER BY l.entry_at, l.line_id ROWS UNBOUNDED PRECEDING),
           l.due_date, l.invoice_no, l.job_card_number, l.batch_number, l.detail
    FROM   public.advance_ledger_lines() l
    WHERE  l.person = p_person AND l.company = p_company
    ORDER  BY l.entry_at, l.line_id;
END;
$$;

-- ── 4. Writers store the company ─────────────────────────────────────────────────

CREATE FUNCTION public.reconcile_supplier_balance(p_company text, p_supplier_id uuid, p_as_of date, p_confirmed_against text, p_confirmed_balance numeric, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_system numeric;
    v_id     uuid;
BEGIN
    PERFORM public.assert_ledger_writer();
    PERFORM public.assert_ledger_company(p_company);

    PERFORM 1 FROM public.suppliers WHERE id = p_supplier_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier not found.';
    END IF;

    IF p_as_of IS NULL OR p_as_of > (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
        RAISE EXCEPTION 'Choose a date that is not in the future.';
    END IF;
    IF p_confirmed_balance IS NULL OR p_confirmed_balance <> round(p_confirmed_balance, 2) THEN
        RAISE EXCEPTION 'Enter the confirmed balance, with at most two decimals.';
    END IF;
    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason.';
    END IF;

    SELECT coalesce(sum(l.amount), 0) INTO v_system
    FROM   public.supplier_ledger_lines() l
    WHERE  l.supplier_id = p_supplier_id
      AND  l.company = p_company
      AND  l.counts
      AND  l.entry_at <= least(public.end_of_ist_day(p_as_of), now());

    INSERT INTO public.supplier_ledger_adjustments
        (supplier_id, company, as_of, confirmed_against, system_balance, confirmed_balance, reason, created_by)
    VALUES (p_supplier_id, p_company, p_as_of, p_confirmed_against, v_system, p_confirmed_balance, btrim(p_reason), auth.uid())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- p_payment now carries `company` (no new parameter).
CREATE OR REPLACE FUNCTION public.record_supplier_payment(p_supplier_id uuid, p_payment jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_amount  numeric := coalesce(nullif(p_payment->>'amount_paid', '')::numeric, 0);
    v_tds     numeric := coalesce(nullif(p_payment->>'tds_amount', '')::numeric, 0);
    v_paid_on date    := nullif(p_payment->>'paid_on', '')::date;
    v_method  text    := nullif(p_payment->>'payment_method', '');
    v_company text    := nullif(p_payment->>'company', '');
    v_id      uuid;
BEGIN
    PERFORM public.assert_ledger_writer();
    PERFORM public.assert_ledger_company(v_company);

    PERFORM 1 FROM public.suppliers WHERE id = p_supplier_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier not found.';
    END IF;

    IF v_amount <> round(v_amount, 2) OR v_tds <> round(v_tds, 2) THEN
        RAISE EXCEPTION 'Amounts can have at most two decimals.';
    END IF;
    IF v_amount < 0 OR v_tds < 0 THEN
        RAISE EXCEPTION 'Amounts cannot be negative.';
    END IF;
    IF v_amount + v_tds <= 0 THEN
        RAISE EXCEPTION 'Enter a paid value or a TDS amount.';
    END IF;
    IF v_paid_on IS NULL THEN
        RAISE EXCEPTION 'Enter the date the payment was made.';
    END IF;
    -- India time: the server's date is still yesterday until 05:30 IST.
    IF v_paid_on > (now() AT TIME ZONE 'Asia/Kolkata')::date THEN
        RAISE EXCEPTION 'The payment date cannot be in the future.';
    END IF;
    IF v_method IS NULL THEN
        RAISE EXCEPTION 'Choose the payment method.';
    END IF;
    IF v_method <> 'Cash' AND (nullif(p_payment->>'bank', '') IS NULL OR nullif(btrim(p_payment->>'utr'), '') IS NULL) THEN
        RAISE EXCEPTION 'Bank and UTR are required for every method except Cash.';
    END IF;

    INSERT INTO public.supplier_payments
        (supplier_id, company, paid_on, amount_paid, tds_amount, ledger, payment_method, bank, utr, recorded_by)
    VALUES (
        p_supplier_id, v_company, v_paid_on, v_amount, v_tds, 'Bill accounted', v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- p_payment now carries `company` (no new parameter).
CREATE OR REPLACE FUNCTION public.record_advance_repayment(p_person text, p_payment jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_amount  numeric := coalesce(nullif(p_payment->>'amount', '')::numeric, 0);
    v_paid_on date    := nullif(p_payment->>'paid_on', '')::date;
    v_method  text    := nullif(p_payment->>'payment_method', '');
    v_company text    := nullif(p_payment->>'company', '');
    v_id      uuid;
BEGIN
    PERFORM public.assert_ledger_writer();
    PERFORM public.assert_ledger_company(v_company);

    IF p_person IS NULL OR NOT (p_person = any(public.advance_people())) THEN
        RAISE EXCEPTION 'Choose who is being repaid.';
    END IF;
    -- One repayment at a time per person and company.
    PERFORM pg_advisory_xact_lock(hashtext('advance_repayments:' || p_person || ':' || v_company));

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

    INSERT INTO public.advance_repayments (person, company, paid_on, amount, payment_method, bank, utr, recorded_by)
    VALUES (
        p_person, v_company, v_paid_on, v_amount, v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ── 5. Grants: signed-in users call the readers and writers; each checks the role ─

REVOKE ALL ON FUNCTION public.get_supplier_balances(text, uuid) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_supplier_balances(text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_supplier_open_items(text, uuid) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_supplier_open_items(text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_supplier_statement(text, uuid) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_supplier_statement(text, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_advance_balances(text) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_advance_balances(text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_advance_open_items(text, text) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_advance_open_items(text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_advance_statement(text, text) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_advance_statement(text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.reconcile_supplier_balance(text, uuid, date, text, numeric, text) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.reconcile_supplier_balance(text, uuid, date, text, numeric, text) TO authenticated, service_role;
