-- MAIN-119: the supplier ledger.
--
-- Finance pays outsource suppliers against a running balance, by credit period, every
-- Wednesday — not invoice by invoice. A supplier's ledger is:
--   • each outsource invoice finance has Accepted (or GST-closed) — its Approved amount
--     is owed, dated by submitted_on (MAIN-118);
--   • its Advance, if any, as a payment line "Advance – <Paid By>";
--   • supplier payments. Posted Ledger = 'Bill accounted' pays the vendor and reduces
--     the balance; posted to a person it repays that person's advance and is listed
--     for reference only;
--   • reconciliation adjustments, stock-audit style.
--
-- Invoice and advance lines are derived, not stored: an invoice moved back to Hold or
-- on to Reject simply leaves the ledger, and its amounts cannot change while Accepted
-- (MAIN-118's lock). Payments and adjustments are stored. Balances start at zero.

-- ── A. Credit days ───────────────────────────────────────────────────────────────
-- Was free text from the registration form; empty for every supplier in prod. Any
-- digits in it are kept ("30 days" → 30); blank stays NULL and counts as 0.

alter table public.suppliers
  alter column payment_terms_days type integer
  using nullif(regexp_replace(coalesce(payment_terms_days, ''), '[^0-9]', '', 'g'), '')::integer;

alter table public.suppliers
  add constraint suppliers_payment_terms_days_check
  check (payment_terms_days is null or payment_terms_days between 0 and 365);

-- ── B. Supplier payments ─────────────────────────────────────────────────────────
-- ledger, payment_method and bank mirror LEDGER_OPTIONS, PAYMENT_METHODS and
-- BANK_OPTIONS in src/constants/outsourceInvoices.js — keep in step.

create table public.supplier_payments (
    id             uuid primary key default gen_random_uuid(),
    supplier_id    uuid not null references public.suppliers(id),
    paid_on        date not null,
    amount_paid    numeric(12,2) not null default 0,
    tds_amount     numeric(12,2) not null default 0,
    ledger         text not null,
    payment_method text not null,
    bank           text,
    utr            text,
    status         text not null default 'Active',
    recorded_by    uuid references public.users(id),
    created_at     timestamptz not null default now(),
    cancelled_at   timestamptz,
    cancelled_by   uuid references public.users(id),
    cancel_reason  text,
    constraint supplier_payments_amounts_check
      check (amount_paid >= 0 and tds_amount >= 0 and amount_paid + tds_amount > 0),
    constraint supplier_payments_ledger_check
      check (ledger = any (array['Bill accounted'::text, 'NVS 659 Manjunath'::text, 'NVS 2954 Gokilavanan'::text, 'PCN'::text])),
    constraint supplier_payments_method_check
      check (payment_method = any (array['UPI'::text, 'NEFT'::text, 'RTGS'::text, 'IMPS'::text, 'Cash'::text])),
    constraint supplier_payments_bank_check
      check (bank is null or bank = any (array['Union Bank of India'::text, 'Kotak Mahindra'::text])),
    -- Every method but cash leaves a bank trail.
    constraint supplier_payments_bank_trail_check
      check (payment_method = 'Cash' or (bank is not null and nullif(btrim(utr), '') is not null)),
    constraint supplier_payments_status_check
      check (status = any (array['Active'::text, 'Cancelled'::text])),
    constraint supplier_payments_cancel_reason_check
      check (status = 'Active' or (cancelled_at is not null and nullif(btrim(cancel_reason), '') is not null))
);

create index supplier_payments_supplier_id_idx on public.supplier_payments (supplier_id, paid_on);

-- ── C. Reconciliation adjustments ────────────────────────────────────────────────
-- Finance confirms the balance against Tally or the vendor's statement as of a date.
-- The app's own figure on that date is frozen here, and the difference is the
-- adjustment line. A zero difference is still recorded: it says when finance last
-- reconciled.

create table public.supplier_ledger_adjustments (
    id                uuid primary key default gen_random_uuid(),
    supplier_id       uuid not null references public.suppliers(id),
    as_of             date not null,
    confirmed_against text not null,
    system_balance    numeric(12,2) not null,
    confirmed_balance numeric(12,2) not null,
    -- Positive raises what the supplier is owed.
    amount            numeric(12,2) generated always as (confirmed_balance - system_balance) stored,
    reason            text not null,
    created_by        uuid references public.users(id),
    created_at        timestamptz not null default now(),
    constraint supplier_ledger_adjustments_source_check
      check (confirmed_against = any (array['Tally'::text, 'Vendor statement'::text])),
    constraint supplier_ledger_adjustments_reason_check
      check (nullif(btrim(reason), '') is not null)
);

create index supplier_ledger_adjustments_supplier_id_idx on public.supplier_ledger_adjustments (supplier_id, as_of);

-- Reads: the people who can read outsource invoices' finance side. Writes go only
-- through the functions below, which check the role; there are no write policies.
alter table public.supplier_payments enable row level security;
alter table public.supplier_ledger_adjustments enable row level security;

create policy "Exec and finance read supplier payments" on public.supplier_payments
  for select using (public.is_maintenance_exec() or public.is_finance());
create policy "Exec and finance read ledger adjustments" on public.supplier_ledger_adjustments
  for select using (public.is_maintenance_exec() or public.is_finance());

grant select on public.supplier_payments to authenticated;
grant select on public.supplier_ledger_adjustments to authenticated;
grant all on public.supplier_payments to service_role;
grant all on public.supplier_ledger_adjustments to service_role;

-- ── D. Ledger lines ──────────────────────────────────────────────────────────────
-- Every line of every supplier's ledger. `amount` is its effect on what the supplier
-- is owed (+ owed, − paid); `counts` is false for reimbursements and cancelled
-- payments, which are shown but leave the balance alone. Within a day: invoices, then
-- advances, then payments, then adjustments.
--
-- Internal: the read functions below check the caller's role first.

create function public.supplier_ledger_lines()
returns table(
    supplier_id   uuid,
    entry_date    date,
    seq           integer,
    created_at    timestamptz,
    line_id       uuid,
    kind          text,
    amount        numeric,
    counts        boolean,
    due_date      date,
    invoice_id    uuid,
    invoice_no    text,
    job_card_number integer,
    batch_number  integer,
    detail        jsonb
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  with inv as (
      select oi.*,
             coalesce(jc.supplier_id, bs.supplier_id) as sup_id,
             coalesce(oi.submitted_on, (oi.created_at at time zone 'Asia/Kolkata')::date) as d,
             jc.job_card_number, bs.batch_number
      from   public.outsource_invoices oi
      left join public.job_cards      jc on jc.id = oi.job_card_id
      left join public.batch_services bs on bs.id = oi.batch_service_id
      where  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
        and  (bs.id is null or bs.status = 'Active')
  )
  select inv.sup_id, inv.d, 1, inv.created_at, inv.id, 'invoice',
         inv.approved_amount, true,
         inv.d + coalesce(s.payment_terms_days, 0),
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('finance_status', inv.finance_payment_status, 'invoice_value', inv.invoice_value)
  from   inv join public.suppliers s on s.id = inv.sup_id

  union all

  select inv.sup_id, inv.d, 2, inv.created_at, inv.id, 'advance',
         -inv.advance_amount, true, null,
         inv.id, inv.invoice_no, inv.job_card_number, inv.batch_number,
         jsonb_build_object('paid_by', inv.paid_by)
  from   inv
  where  inv.advance_amount > 0

  union all

  select p.supplier_id, p.paid_on, 3, p.created_at, p.id,
         case when p.status = 'Cancelled'        then 'cancelled'
              when p.ledger = 'Bill accounted'   then 'payment'
              else                                    'reimbursement' end,
         -(p.amount_paid + p.tds_amount),
         p.status = 'Active' and p.ledger = 'Bill accounted',
         null, null, null, null, null,
         jsonb_build_object(
             'amount_paid', p.amount_paid, 'tds_amount', p.tds_amount, 'ledger', p.ledger,
             'payment_method', p.payment_method, 'bank', p.bank, 'utr', p.utr,
             'recorded_by', ru.name, 'cancelled_at', p.cancelled_at,
             'cancelled_by', cu.name, 'cancel_reason', p.cancel_reason)
  from   public.supplier_payments p
  left join public.users ru on ru.id = p.recorded_by
  left join public.users cu on cu.id = p.cancelled_by

  union all

  select a.supplier_id, a.as_of, 4, a.created_at, a.id, 'adjustment',
         a.amount, true, null, null, null, null, null,
         jsonb_build_object(
             'confirmed_against', a.confirmed_against, 'system_balance', a.system_balance,
             'confirmed_balance', a.confirmed_balance, 'reason', a.reason, 'created_by', u.name)
  from   public.supplier_ledger_adjustments a
  left join public.users u on u.id = a.created_by
$$;

revoke all on function public.supplier_ledger_lines() from public, anon, authenticated;

-- The Wednesday payment run an amount due on p_date goes out in: that day if it is a
-- Wednesday, else the next Wednesday. Finance releases payments every Wednesday;
-- fixed by decision, not a setting. Mirrors paymentRunFor in src/utils/paymentRuns.js.
create function public.payment_run_for(p_date date) returns date
    language sql immutable
    as $$
  select p_date + ((3 - extract(isodow from p_date)::int + 7) % 7)
$$;

-- What is still open on each owed line, with payments clearing the oldest first. Used
-- for the due figures only; nothing is stored against an invoice. A positive
-- adjustment is owed from its date; advances, counted payments and negative
-- adjustments are the credit that clears them.
create function public.supplier_open_items(p_today date)
returns table(
    supplier_id uuid, line_id uuid, kind text, entry_date date, due_date date,
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
      select l.supplier_id, l.line_id, l.kind, l.entry_date,
             coalesce(l.due_date, l.entry_date) as due_date, l.amount,
             l.invoice_no, l.job_card_number, l.batch_number,
             sum(l.amount) over (partition by l.supplier_id
                                 order by l.entry_date, l.seq, l.created_at, l.line_id) as cum
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
  select o.supplier_id, o.line_id, o.kind, o.entry_date, o.due_date,
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

-- ── E. Reads ─────────────────────────────────────────────────────────────────────
-- Exec, super_admin and finance. Security definer, so the statement can name who
-- recorded a payment (finance cannot read exec/finance profiles under RLS).

-- One row per supplier that is approved or has anything in its ledger.
create function public.get_supplier_balances(p_supplier_id uuid default null)
returns table(
    supplier_id        uuid,
    entity_name        text,
    credit_days        integer,
    outstanding        numeric,
    overdue            numeric,
    due_this_wednesday numeric,
    due_next_wednesday numeric,
    later              numeric,
    this_wednesday     date,
    last_payment_on    date,
    last_reconciled_on date,
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
            WHERE a.supplier_id = s.id),
           coalesce(pending.n, 0)
    FROM   public.suppliers s
    LEFT JOIN bal     ON bal.sid     = s.id
    LEFT JOIN open_items oi ON oi.sid = s.id
    LEFT JOIN pending ON pending.sid = s.id
    WHERE  (p_supplier_id IS NULL OR s.id = p_supplier_id)
      AND  (s.status = 'approved' OR bal.sid IS NOT NULL OR pending.sid IS NOT NULL)
    ORDER  BY s.entity_name;
END;
$$;

-- One supplier's statement, oldest first, with the running balance after each line.
create function public.get_supplier_statement(p_supplier_id uuid)
returns table(
    entry_date date, kind text, line_id uuid, amount numeric, counts boolean,
    balance numeric, due_date date, invoice_id uuid, invoice_no text,
    job_card_number integer, batch_number integer, detail jsonb, created_at timestamptz
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
    SELECT l.entry_date, l.kind, l.line_id, l.amount, l.counts,
           sum(CASE WHEN l.counts THEN l.amount ELSE 0 END)
               OVER (ORDER BY l.entry_date, l.seq, l.created_at, l.line_id
                     ROWS UNBOUNDED PRECEDING),
           l.due_date, l.invoice_id, l.invoice_no, l.job_card_number, l.batch_number,
           l.detail, l.created_at
    FROM   public.supplier_ledger_lines() l
    WHERE  l.supplier_id = p_supplier_id
    ORDER  BY l.entry_date, l.seq, l.created_at, l.line_id;
END;
$$;

-- What is still open for one supplier — the invoices behind its due figures.
create function public.get_supplier_open_items(p_supplier_id uuid)
returns table(
    line_id uuid, kind text, entry_date date, due_date date, run_date date,
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
    SELECT o.line_id, o.kind, o.entry_date, o.due_date, o.run_date, o.amount, o.remaining,
           o.bucket, o.invoice_no, o.job_card_number, o.batch_number
    FROM   public.supplier_open_items((now() AT TIME ZONE 'Asia/Kolkata')::date) o
    WHERE  o.supplier_id = p_supplier_id
    ORDER  BY o.due_date, o.entry_date;
END;
$$;

-- ── F. Writes: finance and super_admin ───────────────────────────────────────────

create function public.assert_ledger_writer() returns void
    language plpgsql stable security definer
    set search_path to 'public'
    as $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.users
                   WHERE id = auth.uid() AND role IN ('finance', 'super_admin') AND is_active) THEN
        RAISE EXCEPTION 'Only finance can change the supplier ledger.' USING ERRCODE = '42501';
    END IF;
END;
$$;

revoke all on function public.assert_ledger_writer() from public, anon, authenticated;

-- Credit days. Logged to audit_logs under the supplier.
create function public.set_supplier_credit_days(p_supplier_id uuid, p_days integer) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_old integer;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF p_days IS NOT NULL AND (p_days < 0 OR p_days > 365) THEN
        RAISE EXCEPTION 'Credit days must be a whole number from 0 to 365.';
    END IF;

    SELECT payment_terms_days INTO v_old FROM public.suppliers WHERE id = p_supplier_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier not found.';
    END IF;

    IF v_old IS NOT DISTINCT FROM p_days THEN
        RETURN;
    END IF;

    UPDATE public.suppliers SET payment_terms_days = p_days WHERE id = p_supplier_id;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('suppliers', p_supplier_id, 'UPDATE',
            jsonb_build_object('payment_terms_days', v_old),
            jsonb_build_object('payment_terms_days', p_days),
            array['payment_terms_days'], auth.uid());
END;
$$;

-- p_payment: { amount_paid, tds_amount, paid_on, ledger, payment_method, bank, utr }
-- Overpaying is allowed — the balance shows as a credit — because finance sometimes
-- pays ahead; the form warns instead.
create function public.record_supplier_payment(p_supplier_id uuid, p_payment jsonb) returns uuid
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
    IF nullif(p_payment->>'ledger', '') IS NULL THEN
        RAISE EXCEPTION 'Choose the ledger the payment was posted to.';
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
        p_supplier_id, v_paid_on, v_amount, v_tds,
        p_payment->>'ledger',
        v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- For a transaction that failed and was refunded. Kept, marked Cancelled, and out of
-- every total.
create function public.cancel_supplier_payment(p_payment_id uuid, p_reason text) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_status text;
BEGIN
    PERFORM public.assert_ledger_writer();

    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for cancelling this payment.';
    END IF;

    SELECT status INTO v_status FROM public.supplier_payments WHERE id = p_payment_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment not found.';
    END IF;
    IF v_status = 'Cancelled' THEN
        RAISE EXCEPTION 'This payment is already cancelled.';
    END IF;

    UPDATE public.supplier_payments
    SET    status        = 'Cancelled',
           cancelled_at  = now(),
           cancelled_by  = auth.uid(),
           cancel_reason = btrim(p_reason)
    WHERE  id = p_payment_id;
END;
$$;

-- Freezes the app's balance at the end of p_as_of and posts the difference to the
-- confirmed balance. Locks the supplier so a payment recorded at the same moment cannot
-- slip between the figure and the adjustment.
create function public.reconcile_supplier_balance(
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
      AND  l.entry_date <= p_as_of;

    INSERT INTO public.supplier_ledger_adjustments
        (supplier_id, as_of, confirmed_against, system_balance, confirmed_balance, reason, created_by)
    VALUES (p_supplier_id, p_as_of, p_confirmed_against, v_system, p_confirmed_balance, btrim(p_reason), auth.uid())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

alter function public.supplier_ledger_lines() owner to postgres;
alter function public.payment_run_for(date) owner to postgres;
alter function public.supplier_open_items(date) owner to postgres;
alter function public.get_supplier_balances(uuid) owner to postgres;
alter function public.get_supplier_statement(uuid) owner to postgres;
alter function public.get_supplier_open_items(uuid) owner to postgres;
alter function public.assert_ledger_writer() owner to postgres;
alter function public.set_supplier_credit_days(uuid, integer) owner to postgres;
alter function public.record_supplier_payment(uuid, jsonb) owner to postgres;
alter function public.cancel_supplier_payment(uuid, text) owner to postgres;
alter function public.reconcile_supplier_balance(uuid, date, text, numeric, text) owner to postgres;

grant execute on function public.get_supplier_balances(uuid) to authenticated, service_role;
grant execute on function public.get_supplier_statement(uuid) to authenticated, service_role;
grant execute on function public.get_supplier_open_items(uuid) to authenticated, service_role;
grant execute on function public.set_supplier_credit_days(uuid, integer) to authenticated, service_role;
grant execute on function public.record_supplier_payment(uuid, jsonb) to authenticated, service_role;
grant execute on function public.cancel_supplier_payment(uuid, text) to authenticated, service_role;
grant execute on function public.reconcile_supplier_balance(uuid, date, text, numeric, text) to authenticated, service_role;
