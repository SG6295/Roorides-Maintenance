-- MAIN-119, revised after review: the ledger in recording order, advances to repay
-- per person, reversible adjustments.
--
-- • Entries are ordered by when they were recorded, as Tally orders them: an invoice
--   and its advance at the moment finance accepted it (accepted_at), a payment when it
--   was recorded, an adjustment at the end of its as-of day. Due dates still count from
--   the day the invoice reached finance, so finance taking time to accept moves nothing.
-- • Paid By takes the repayment ledgers' names, so an advance and its repayment match
--   without a mapping table. Accounts and NVS Maintenance account are company money.
-- • Supplier payments are vendor-only (Bill accounted). Repaying a person who paid an
--   advance has its own table and statement, on the same Wednesday runs.
-- • A reconciliation adjustment can be reversed with a reason.

-- ── A. Paid By = repayment ledger names ──────────────────────────────────────────
-- Mirrors PAID_BY_OPTIONS in src/constants/outsourceInvoices.js — keep in step. The
-- rename is housekeeping, kept out of the invoice history.

alter table public.outsource_invoices disable trigger outsource_invoices_audit;

alter table public.outsource_invoices drop constraint outsource_invoices_paid_by_check;

update public.outsource_invoices
set    paid_by = case paid_by
                     when 'Manjunath'   then 'NVS 659 Manjunath'
                     when 'Gokilavanan' then 'NVS 2954 Gokilavanan'
                     when 'Nithin'      then 'PCN'
                 end
where  paid_by in ('Manjunath', 'Gokilavanan', 'Nithin');

alter table public.outsource_invoices
  add constraint outsource_invoices_paid_by_check
  check (paid_by = any (array[
    'Accounts'::text,
    'NVS Maintenance account'::text,
    'NVS 659 Manjunath'::text,
    'NVS 2954 Gokilavanan'::text,
    'PCN'::text
  ]));

-- ── B. When the invoice entered the ledger ───────────────────────────────────────
-- Stamped when finance moves it into Accepted, kept through a GST close, cleared when it
-- goes back to Hold or on to Reject. Invoices already accepted take the time of their
-- last move into Accepted from the history.

alter table public.outsource_invoices add column accepted_at timestamptz;

update public.outsource_invoices oi
set    accepted_at = coalesce(
           (select max(a.performed_at)
            from   public.audit_logs a
            where  a.table_name = 'outsource_invoices'
              and  a.record_id  = oi.id
              and  a.new_data->>'finance_payment_status' = 'Accepted'),
           oi.updated_at)
where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed');

alter table public.outsource_invoices enable trigger outsource_invoices_audit;

create function public.stamp_outsource_invoice_accepted_at() returns trigger
    language plpgsql
    set search_path to 'public'
    as $$
BEGIN
    IF NEW.finance_payment_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
        IF TG_OP = 'UPDATE' AND OLD.finance_payment_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
            NEW.accepted_at := OLD.accepted_at;
        ELSE
            NEW.accepted_at := now();
        END IF;
    ELSE
        NEW.accepted_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;

alter function public.stamp_outsource_invoice_accepted_at() owner to postgres;

-- Named to sort after outsource_invoices_guard_status_owners, so the guard judges the
-- person's change first.
create trigger outsource_invoices_stamp_accepted_at
  before insert or update on public.outsource_invoices
  for each row execute function public.stamp_outsource_invoice_accepted_at();

-- ── C. Supplier payments are vendor-only ─────────────────────────────────────────

alter table public.supplier_payments drop constraint supplier_payments_ledger_check;
alter table public.supplier_payments alter column ledger set default 'Bill accounted';
alter table public.supplier_payments
  add constraint supplier_payments_ledger_check check (ledger = 'Bill accounted');

-- ── D. Reversible adjustments ────────────────────────────────────────────────────

alter table public.supplier_ledger_adjustments
  add column status         text not null default 'Active',
  add column reversed_at    timestamptz,
  add column reversed_by    uuid references public.users(id),
  add column reverse_reason text;

alter table public.supplier_ledger_adjustments
  add constraint supplier_ledger_adjustments_status_check
    check (status = any (array['Active'::text, 'Reversed'::text])),
  add constraint supplier_ledger_adjustments_reverse_reason_check
    check (status = 'Active' or (reversed_at is not null and nullif(btrim(reverse_reason), '') is not null));

-- ── E. Advance repayments ────────────────────────────────────────────────────────
-- Paying back a person who paid a supplier upfront. person mirrors ADVANCE_PEOPLE in
-- src/constants/supplierLedger.js; method and bank mirror the supplier payments'.

create table public.advance_repayments (
    id             uuid primary key default gen_random_uuid(),
    person         text not null,
    paid_on        date not null,
    amount         numeric(12,2) not null,
    payment_method text not null,
    bank           text,
    utr            text,
    status         text not null default 'Active',
    recorded_by    uuid references public.users(id),
    created_at     timestamptz not null default now(),
    cancelled_at   timestamptz,
    cancelled_by   uuid references public.users(id),
    cancel_reason  text,
    constraint advance_repayments_person_check
      check (person = any (array['NVS 659 Manjunath'::text, 'NVS 2954 Gokilavanan'::text, 'PCN'::text])),
    constraint advance_repayments_amount_check check (amount > 0),
    constraint advance_repayments_method_check
      check (payment_method = any (array['UPI'::text, 'NEFT'::text, 'RTGS'::text, 'IMPS'::text, 'Cash'::text])),
    constraint advance_repayments_bank_check
      check (bank is null or bank = any (array['Union Bank of India'::text, 'Kotak Mahindra'::text])),
    constraint advance_repayments_bank_trail_check
      check (payment_method = 'Cash' or (bank is not null and nullif(btrim(utr), '') is not null)),
    constraint advance_repayments_status_check
      check (status = any (array['Active'::text, 'Cancelled'::text])),
    constraint advance_repayments_cancel_reason_check
      check (status = 'Active' or (cancelled_at is not null and nullif(btrim(cancel_reason), '') is not null))
);

create index advance_repayments_person_idx on public.advance_repayments (person, created_at);

alter table public.advance_repayments enable row level security;
create policy "Exec and finance read advance repayments" on public.advance_repayments
  for select using (public.is_maintenance_exec() or public.is_finance());
grant select on public.advance_repayments to authenticated;
grant all on public.advance_repayments to service_role;

-- ── F. Supplier ledger lines, by timestamp ───────────────────────────────────────
-- The return type changes (entry_at replaces entry_date), so every function built on
-- it is dropped and recreated; their grants are restated.

drop function public.get_supplier_statement(uuid);
drop function public.get_supplier_open_items(uuid);
drop function public.get_supplier_balances(uuid);
drop function public.supplier_open_items(date);
drop function public.supplier_ledger_lines();

-- The end of an as-of day in India: an adjustment sits after everything recorded that
-- day.
create function public.end_of_ist_day(p_date date) returns timestamptz
    language sql immutable
    as $$
  select ((p_date + 1)::timestamp at time zone 'Asia/Kolkata') - interval '1 microsecond'
$$;

alter function public.end_of_ist_day(date) owner to postgres;

-- The day an invoice reached finance: due dates count from it.
create function public.invoice_submitted_day(p_invoice public.outsource_invoices) returns date
    language sql stable
    as $$
  select coalesce(p_invoice.submitted_on, (p_invoice.created_at at time zone 'Asia/Kolkata')::date)
$$;

alter function public.invoice_submitted_day(public.outsource_invoices) owner to postgres;

-- Every line of every supplier's ledger. `amount` is its effect on what the supplier is
-- owed (+ owed, − paid); `counts` is false for cancelled payments and reversed
-- adjustments, which are shown but leave the balance alone. Ordered by entry_at; an
-- advance shares its invoice's moment and sits straight after it (seq).
create function public.supplier_ledger_lines()
returns table(
    supplier_id     uuid,
    entry_at        timestamptz,
    seq             integer,
    line_id         uuid,
    kind            text,
    amount          numeric,
    counts          boolean,
    due_date        date,
    invoice_id      uuid,
    invoice_no      text,
    job_card_number integer,
    batch_number    integer,
    detail          jsonb
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  with inv as (
      select oi.*,
             coalesce(jc.supplier_id, bs.supplier_id)       as sup_id,
             public.invoice_submitted_day(oi)               as submitted_day,
             coalesce(oi.accepted_at, oi.updated_at)        as entered_at,
             oi.paid_by in ('NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN') as by_person,
             jc.job_card_number, bs.batch_number
      from   public.outsource_invoices oi
      left join public.job_cards      jc on jc.id = oi.job_card_id
      left join public.batch_services bs on bs.id = oi.batch_service_id
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
             'advance_by_person', inv.by_person)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.entered_at, 2, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by, 'advance_by_person', inv.by_person)
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

  select a.supplier_id, public.end_of_ist_day(a.as_of), 4, a.id,
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

revoke all on function public.supplier_ledger_lines() from public, anon, authenticated;

-- What is still open on each owed line. Credits (advances, payments, negative
-- adjustments) clear the owed lines with the earliest due date first. Used for the due
-- figures only; nothing is stored against an invoice.
create function public.supplier_open_items(p_today date)
returns table(
    supplier_id uuid, line_id uuid, kind text, entry_at timestamptz, due_date date,
    run_date date, amount numeric, remaining numeric, bucket text,
    invoice_no text, job_card_number integer, batch_number integer
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  with lines as (
      select * from public.supplier_ledger_lines() where counts
  ),
  owed as (
      select l.supplier_id, l.line_id, l.kind, l.entry_at, l.due_date, l.amount,
             l.invoice_no, l.job_card_number, l.batch_number,
             sum(l.amount) over (partition by l.supplier_id
                                 order by l.due_date, l.entry_at, l.line_id) as cum
      from   lines l
      where  l.amount > 0
  ),
  credit as (
      select supplier_id, -sum(amount) as total
      from   lines
      where  amount < 0
      group  by supplier_id
  ),
  open_items as (
      select o.*, greatest(0, least(o.amount, o.cum - coalesce(c.total, 0))) as remaining
      from   owed o
      left join credit c on c.supplier_id = o.supplier_id
  )
  select o.supplier_id, o.line_id, o.kind, o.entry_at, o.due_date,
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

revoke all on function public.supplier_open_items(date) from public, anon, authenticated;

create function public.get_supplier_balances(p_supplier_id uuid default null)
returns table(
    supplier_id         uuid,
    entity_name         text,
    credit_days         integer,
    outstanding         numeric,
    overdue             numeric,
    due_this_wednesday  numeric,
    due_next_wednesday  numeric,
    later               numeric,
    this_wednesday      date,
    last_payment_on     date,
    last_reconciled_on  date,
    awaiting_acceptance bigint
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH bal AS (
        SELECT l.supplier_id AS sid, sum(l.amount) FILTER (WHERE l.counts) AS total
        FROM   public.supplier_ledger_lines() l
        GROUP  BY l.supplier_id
    ),
    open_items AS (
        SELECT o.supplier_id AS sid,
               sum(o.remaining) FILTER (WHERE o.bucket = 'overdue')        AS overdue,
               sum(o.remaining) FILTER (WHERE o.bucket = 'this_wednesday') AS this_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'next_wednesday') AS next_wed,
               sum(o.remaining) FILTER (WHERE o.bucket = 'later')          AS later
        FROM   public.supplier_open_items(v_today) o
        GROUP  BY o.supplier_id
    ),
    pending AS (
        SELECT coalesce(jc.supplier_id, bs.supplier_id) AS sid, count(*) AS n
        FROM   public.outsource_invoices oi
        LEFT JOIN public.job_cards      jc ON jc.id = oi.job_card_id
        LEFT JOIN public.batch_services bs ON bs.id = oi.batch_service_id
        WHERE  oi.submitted_on IS NOT NULL
          AND  oi.finance_payment_status IN ('New', 'Hold')
          AND  (bs.id IS NULL OR bs.status = 'Active')
        GROUP  BY 1
    )
    SELECT s.id, s.entity_name, s.payment_terms_days,
           coalesce(bal.total, 0),
           coalesce(oi.overdue, 0), coalesce(oi.this_wed, 0),
           coalesce(oi.next_wed, 0), coalesce(oi.later, 0),
           public.payment_run_for(v_today),
           (SELECT max(p.paid_on) FROM public.supplier_payments p
            WHERE p.supplier_id = s.id AND p.status = 'Active'),
           (SELECT max(a.as_of) FROM public.supplier_ledger_adjustments a
            WHERE a.supplier_id = s.id AND a.status = 'Active'),
           coalesce(pending.n, 0)
    FROM   public.suppliers s
    LEFT JOIN bal        ON bal.sid     = s.id
    LEFT JOIN open_items oi ON oi.sid   = s.id
    LEFT JOIN pending    ON pending.sid = s.id
    WHERE  (p_supplier_id IS NULL OR s.id = p_supplier_id)
      AND  (s.status = 'approved' OR bal.sid IS NOT NULL OR pending.sid IS NOT NULL)
    ORDER  BY s.entity_name;
END;
$$;

create function public.get_supplier_statement(p_supplier_id uuid)
returns table(
    entry_at timestamptz, kind text, line_id uuid, amount numeric, counts boolean,
    balance numeric, due_date date, invoice_id uuid, invoice_no text,
    job_card_number integer, batch_number integer, detail jsonb
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT l.entry_at, l.kind, l.line_id, l.amount, l.counts,
           sum(CASE WHEN l.counts THEN l.amount ELSE 0 END)
               OVER (ORDER BY l.entry_at, l.seq, l.line_id ROWS UNBOUNDED PRECEDING),
           l.due_date, l.invoice_id, l.invoice_no, l.job_card_number, l.batch_number, l.detail
    FROM   public.supplier_ledger_lines() l
    WHERE  l.supplier_id = p_supplier_id
    ORDER  BY l.entry_at, l.seq, l.line_id;
END;
$$;

create function public.get_supplier_open_items(p_supplier_id uuid)
returns table(
    line_id uuid, kind text, entry_at timestamptz, due_date date, run_date date,
    amount numeric, remaining numeric, bucket text,
    invoice_no text, job_card_number integer, batch_number integer
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT o.line_id, o.kind, o.entry_at, o.due_date, o.run_date, o.amount, o.remaining,
           o.bucket, o.invoice_no, o.job_card_number, o.batch_number
    FROM   public.supplier_open_items((now() AT TIME ZONE 'Asia/Kolkata')::date) o
    WHERE  o.supplier_id = p_supplier_id
    ORDER  BY o.due_date, o.entry_at;
END;
$$;

-- ── G. Supplier writes ───────────────────────────────────────────────────────────

-- Vendor payments only: the ledger is always Bill accounted. Signature unchanged.
create or replace function public.record_supplier_payment(p_supplier_id uuid, p_payment jsonb) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_amount  numeric := coalesce(nullif(p_payment->>'amount_paid', '')::numeric, 0);
    v_tds     numeric := coalesce(nullif(p_payment->>'tds_amount', '')::numeric, 0);
    v_paid_on date    := nullif(p_payment->>'paid_on', '')::date;
    v_method  text    := nullif(p_payment->>'payment_method', '');
    v_id      uuid;
BEGIN
    PERFORM public.assert_ledger_writer();

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
        (supplier_id, paid_on, amount_paid, tds_amount, ledger, payment_method, bank, utr, recorded_by)
    VALUES (
        p_supplier_id, v_paid_on, v_amount, v_tds, 'Bill accounted', v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- The app's figure is everything recorded up to the end of the as-of day, reversed
-- adjustments aside. Signature unchanged.
create or replace function public.reconcile_supplier_balance(
    p_supplier_id       uuid,
    p_as_of             date,
    p_confirmed_against text,
    p_confirmed_balance numeric,
    p_reason            text
) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_system numeric;
    v_id     uuid;
BEGIN
    PERFORM public.assert_ledger_writer();

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
      AND  l.counts
      AND  l.entry_at <= public.end_of_ist_day(p_as_of);

    INSERT INTO public.supplier_ledger_adjustments
        (supplier_id, as_of, confirmed_against, system_balance, confirmed_balance, reason, created_by)
    VALUES (p_supplier_id, p_as_of, p_confirmed_against, v_system, p_confirmed_balance, btrim(p_reason), auth.uid())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Undoes an adjustment posted in error. Kept, marked Reversed, and out of every total.
create function public.reverse_ledger_adjustment(p_adjustment_id uuid, p_reason text) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_status text;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing this adjustment.';
    END IF;

    SELECT status INTO v_status FROM public.supplier_ledger_adjustments WHERE id = p_adjustment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Adjustment not found.';
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This adjustment is already reversed.';
    END IF;

    UPDATE public.supplier_ledger_adjustments
    SET    status         = 'Reversed',
           reversed_at    = now(),
           reversed_by    = auth.uid(),
           reverse_reason = btrim(p_reason)
    WHERE  id = p_adjustment_id;
END;
$$;

-- ── H. Advances to repay ─────────────────────────────────────────────────────────
-- Owed to a person: the advance on each accepted invoice whose Paid By is theirs, due
-- on the first Wednesday on or after the day the invoice reached finance (people have
-- no credit days). Repayments clear the earliest-due advances first.

create function public.advance_ledger_lines()
returns table(
    person          text,
    entry_at        timestamptz,
    line_id         uuid,
    kind            text,
    amount          numeric,
    counts          boolean,
    due_date        date,
    invoice_no      text,
    job_card_number integer,
    batch_number    integer,
    detail          jsonb
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  select oi.paid_by, coalesce(oi.accepted_at, oi.updated_at), oi.id, 'advance',
         oi.advance_amount, true, public.invoice_submitted_day(oi),
         oi.invoice_no, jc.job_card_number, bs.batch_number,
         jsonb_build_object(
             'supplier', s.entity_name, 'supplier_id', s.id,
             'approved', oi.approved_amount, 'to_supplier', oi.approved_amount - oi.advance_amount)
  from   public.outsource_invoices oi
  left join public.job_cards      jc on jc.id = oi.job_card_id
  left join public.batch_services bs on bs.id = oi.batch_service_id
  left join public.suppliers      s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id)
  where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')
    and  oi.advance_amount > 0
    and  oi.paid_by in ('NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN')

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

revoke all on function public.advance_ledger_lines() from public, anon, authenticated;

create function public.advance_open_items(p_today date)
returns table(
    person text, line_id uuid, entry_at timestamptz, due_date date, run_date date,
    amount numeric, remaining numeric, bucket text,
    invoice_no text, job_card_number integer, batch_number integer, supplier text
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  with lines as (
      select * from public.advance_ledger_lines() where counts
  ),
  owed as (
      select l.*, sum(l.amount) over (partition by l.person order by l.due_date, l.entry_at, l.line_id) as cum
      from   lines l
      where  l.amount > 0
  ),
  credit as (
      select person, -sum(amount) as total from lines where amount < 0 group by person
  ),
  open_items as (
      select o.*, greatest(0, least(o.amount, o.cum - coalesce(c.total, 0))) as remaining
      from   owed o left join credit c on c.person = o.person
  )
  select o.person, o.line_id, o.entry_at, o.due_date, public.payment_run_for(o.due_date),
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

revoke all on function public.advance_open_items(date) from public, anon, authenticated;

-- One row per person, always all three.
create function public.get_advance_balances()
returns table(
    person text, owed numeric, overdue numeric, due_this_wednesday numeric,
    due_next_wednesday numeric, later numeric, last_repaid_on date
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
DECLARE
    v_today date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH people(person, ord) AS (
        VALUES ('NVS 659 Manjunath', 1), ('NVS 2954 Gokilavanan', 2), ('PCN', 3)
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

create function public.get_advance_statement(p_person text)
returns table(
    entry_at timestamptz, kind text, line_id uuid, amount numeric, counts boolean,
    balance numeric, due_date date, invoice_no text, job_card_number integer,
    batch_number integer, detail jsonb
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT l.entry_at, l.kind, l.line_id, l.amount, l.counts,
           sum(CASE WHEN l.counts THEN l.amount ELSE 0 END)
               OVER (ORDER BY l.entry_at, l.line_id ROWS UNBOUNDED PRECEDING),
           l.due_date, l.invoice_no, l.job_card_number, l.batch_number, l.detail
    FROM   public.advance_ledger_lines() l
    WHERE  l.person = p_person
    ORDER  BY l.entry_at, l.line_id;
END;
$$;

create function public.get_advance_open_items(p_person text)
returns table(
    line_id uuid, entry_at timestamptz, due_date date, run_date date, amount numeric,
    remaining numeric, bucket text, invoice_no text, job_card_number integer,
    batch_number integer, supplier text
)
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
#variable_conflict use_column
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only finance and maintenance executives can see the supplier ledger.' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    SELECT o.line_id, o.entry_at, o.due_date, o.run_date, o.amount, o.remaining, o.bucket,
           o.invoice_no, o.job_card_number, o.batch_number, o.supplier
    FROM   public.advance_open_items((now() AT TIME ZONE 'Asia/Kolkata')::date) o
    WHERE  o.person = p_person
    ORDER  BY o.due_date, o.entry_at;
END;
$$;

-- p_payment: { amount, paid_on, payment_method, bank, utr }
create function public.record_advance_repayment(p_person text, p_payment jsonb) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_amount  numeric := coalesce(nullif(p_payment->>'amount', '')::numeric, 0);
    v_paid_on date    := nullif(p_payment->>'paid_on', '')::date;
    v_method  text    := nullif(p_payment->>'payment_method', '');
    v_id      uuid;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF p_person IS NULL OR p_person NOT IN ('NVS 659 Manjunath', 'NVS 2954 Gokilavanan', 'PCN') THEN
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

create function public.cancel_advance_repayment(p_repayment_id uuid, p_reason text) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_status text;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for cancelling this repayment.';
    END IF;

    SELECT status INTO v_status FROM public.advance_repayments WHERE id = p_repayment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Repayment not found.';
    END IF;
    IF v_status = 'Cancelled' THEN
        RAISE EXCEPTION 'This repayment is already cancelled.';
    END IF;

    UPDATE public.advance_repayments
    SET    status = 'Cancelled', cancelled_at = now(), cancelled_by = auth.uid(), cancel_reason = btrim(p_reason)
    WHERE  id = p_repayment_id;
END;
$$;

alter function public.supplier_ledger_lines() owner to postgres;
alter function public.supplier_open_items(date) owner to postgres;
alter function public.get_supplier_balances(uuid) owner to postgres;
alter function public.get_supplier_statement(uuid) owner to postgres;
alter function public.get_supplier_open_items(uuid) owner to postgres;
alter function public.reverse_ledger_adjustment(uuid, text) owner to postgres;
alter function public.advance_ledger_lines() owner to postgres;
alter function public.advance_open_items(date) owner to postgres;
alter function public.get_advance_balances() owner to postgres;
alter function public.get_advance_statement(text) owner to postgres;
alter function public.get_advance_open_items(text) owner to postgres;
alter function public.record_advance_repayment(text, jsonb) owner to postgres;
alter function public.cancel_advance_repayment(uuid, text) owner to postgres;

grant execute on function public.get_supplier_balances(uuid) to authenticated, service_role;
grant execute on function public.get_supplier_statement(uuid) to authenticated, service_role;
grant execute on function public.get_supplier_open_items(uuid) to authenticated, service_role;
grant execute on function public.reverse_ledger_adjustment(uuid, text) to authenticated, service_role;
grant execute on function public.get_advance_balances() to authenticated, service_role;
grant execute on function public.get_advance_statement(text) to authenticated, service_role;
grant execute on function public.get_advance_open_items(text) to authenticated, service_role;
grant execute on function public.record_advance_repayment(text, jsonb) to authenticated, service_role;
grant execute on function public.cancel_advance_repayment(uuid, text) to authenticated, service_role;
