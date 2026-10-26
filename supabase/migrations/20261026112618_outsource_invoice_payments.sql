-- MAIN-95: finance records payments against outsource invoices.
--
-- Finance records what was actually paid — in one or more payments — and cancels a
-- payment whose transaction failed and was refunded. The invoice's finance status then
-- follows from what is still due: Due → Partly Paid → Paid.
--
-- Prod holds 0 payment rows, so every new column is safe to add.

-- ── Payment details ──────────────────────────────────────────────────────────────
-- ledger, payment_method and bank mirror LEDGER_OPTIONS, PAYMENT_METHODS and
-- BANK_OPTIONS in src/constants/outsourceInvoices.js — keep in step. They stay
-- nullable at the column level; record_outsource_invoice_payment requires them.

alter table public.outsource_invoice_payments
  add column tds_amount     numeric(12,2) not null default 0,
  add column round_off      numeric(12,2) not null default 0,
  add column ledger         text,
  add column payment_method text,
  add column bank           text,
  add column utr            text,
  add column status         text not null default 'Active',
  add column cancelled_at   timestamptz,
  add column cancelled_by   uuid references public.users(id),
  add column cancel_reason  text;

alter table public.outsource_invoice_payments
  add constraint outsource_invoice_payments_amounts_check
    check (amount_paid >= 0 and tds_amount >= 0 and amount_paid + tds_amount > 0),
  -- Round-off only ever closes a sub-rupee remainder.
  add constraint outsource_invoice_payments_round_off_check
    check (round_off >= 0 and round_off < 1),
  add constraint outsource_invoice_payments_ledger_check
    check (ledger = any (array['Bill accounted'::text, 'NVS 659 Manjunath'::text, 'NVS 2954 Gokilavanan'::text, 'PCN'::text])),
  add constraint outsource_invoice_payments_method_check
    check (payment_method = any (array['UPI'::text, 'NEFT'::text, 'RTGS'::text, 'IMPS'::text, 'Cash'::text])),
  add constraint outsource_invoice_payments_bank_check
    check (bank = any (array['Union Bank of India'::text, 'Kotak Mahindra'::text])),
  -- Every method but cash leaves a bank trail.
  add constraint outsource_invoice_payments_bank_trail_check
    check (payment_method is null or payment_method = 'Cash'
           or (bank is not null and nullif(btrim(utr), '') is not null)),
  add constraint outsource_invoice_payments_status_check
    check (status = any (array['Active'::text, 'Cancelled'::text])),
  add constraint outsource_invoice_payments_cancel_reason_check
    check (status = 'Active' or (cancelled_at is not null and nullif(btrim(cancel_reason), '') is not null));

-- ── Finance status gains Partly Paid ─────────────────────────────────────────────
-- Mirrors FINANCE_PAYMENT_STATUSES in src/constants/outsourceInvoices.js.

alter table public.outsource_invoices
  drop constraint outsource_invoices_finance_payment_status_check;

alter table public.outsource_invoices
  add constraint outsource_invoices_finance_payment_status_check
  check (finance_payment_status = any (array[
    'Due'::text,
    'Partly Paid'::text,
    'Paid'::text,
    'Hold - on request'::text,
    'Hold - further details required'::text,
    'Reject - duplicate'::text,
    'Reject - incorrect/insufficient details'::text,
    'Reject - other'::text
  ]));

-- ── Paid By spelling: Gokilavannan → Gokilavanan ─────────────────────────────────
-- No row holds the old spelling. Mirrors PAID_BY_OPTIONS.

alter table public.outsource_invoices
  drop constraint outsource_invoices_paid_by_check;

alter table public.outsource_invoices
  add constraint outsource_invoices_paid_by_check
  check (paid_by = any (array[
    'Accounts'::text,
    'Nithin'::text,
    'Manjunath'::text,
    'Gokilavanan'::text,
    'NVS Maintenance account'::text
  ]));

-- ── Settlement arithmetic ────────────────────────────────────────────────────────
-- Settled = active Paid + TDS + Round-off. All numeric, so exact to the paisa.

create function public.outsource_invoice_settled(p_invoice_id uuid) returns numeric
    language sql stable security definer
    set search_path to 'public'
    as $$
  select coalesce(sum(amount_paid + tds_amount + round_off), 0)
  from   public.outsource_invoice_payments
  where  outsource_invoice_id = p_invoice_id
    and  status = 'Active'
$$;

create function public.derive_finance_payment_status(p_payable numeric, p_settled numeric) returns text
    language sql immutable
    as $$
  select case
           when p_settled <= 0       then 'Due'
           when p_settled < p_payable then 'Partly Paid'
           else                           'Paid'
         end
$$;

-- Writes the derived status. The transaction-local flag tells
-- guard_outsource_invoice_status_owners that this change comes from the
-- recalculation, not a person picking Paid or Partly Paid by hand.
create function public.apply_finance_status_recalc(p_invoice_id uuid) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    PERFORM set_config('app.finance_status_recalc', 'on', true);

    UPDATE public.outsource_invoices oi
    SET    finance_payment_status = public.derive_finance_payment_status(
               coalesce(oi.approved_amount, 0) - coalesce(oi.advance_amount, 0),
               public.outsource_invoice_settled(oi.id))
    WHERE  oi.id = p_invoice_id;

    PERFORM set_config('app.finance_status_recalc', 'off', true);
END;
$$;

-- Internal only: no client should call these directly.
revoke all on function public.outsource_invoice_settled(uuid) from public, anon, authenticated;
revoke all on function public.apply_finance_status_recalc(uuid) from public, anon, authenticated;

-- ── Guard: Paid and Partly Paid come only from the recalculation ─────────────────
-- Extends MAIN-90's guard. The recalculation sets app.finance_status_recalc and
-- passes untouched; anyone setting Paid or Partly Paid by hand is refused — this is
-- data integrity rather than a permission, so it holds for super_admin as well.

create or replace function public.guard_outsource_invoice_status_owners() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_role text;
    v_finance_changed boolean;
    v_maintenance_changed boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF current_setting('app.finance_status_recalc', true) = 'on' THEN
        RETURN NEW;
    END IF;

    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();

    IF TG_OP = 'INSERT' THEN
        v_finance_changed     := NEW.finance_payment_status <> 'Due' OR NEW.finance_remark IS NOT NULL;
        v_maintenance_changed := NEW.maintenance_payment_status IS NOT NULL;
    ELSE
        v_finance_changed     := NEW.finance_payment_status IS DISTINCT FROM OLD.finance_payment_status
                              OR NEW.finance_remark         IS DISTINCT FROM OLD.finance_remark;
        v_maintenance_changed := NEW.maintenance_payment_status IS DISTINCT FROM OLD.maintenance_payment_status;
    END IF;

    IF v_finance_changed AND v_role IS DISTINCT FROM 'finance' AND v_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Only finance can change the payment status reported by finance.'
            USING ERRCODE = '42501';
    END IF;

    IF v_maintenance_changed AND v_role = 'finance' THEN
        RAISE EXCEPTION 'Finance cannot change the payment status reported by maintenance.'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.finance_payment_status IN ('Paid', 'Partly Paid')
       AND (TG_OP = 'INSERT' OR NEW.finance_payment_status IS DISTINCT FROM OLD.finance_payment_status) THEN
        RAISE EXCEPTION 'Paid and Partly Paid are set by recording payments, not by hand.'
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

-- Between MAIN-90 and this migration finance could pick Paid by hand. Any such status
-- not backed by payments goes back to what the payments say (Due, with none
-- recorded). Prod held none when this was written; staging held one from testing.
update public.outsource_invoices oi
set    finance_payment_status = public.derive_finance_payment_status(
           coalesce(oi.approved_amount, 0) - coalesce(oi.advance_amount, 0),
           public.outsource_invoice_settled(oi.id))
where  oi.finance_payment_status in ('Paid', 'Partly Paid');

-- ── Recalculate when Approved or Advance changes ─────────────────────────────────
-- Only once money has moved: an invoice still at Due/Hold/Reject with no payments
-- keeps finance's own status when the exec edits an amount. Named to sort after
-- outsource_invoices_guard_status_owners, so the guard judges the exec's own change
-- and this then adjusts the status.

create function public.recalc_finance_status_on_amount_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_settled numeric;
BEGIN
    IF NEW.approved_amount IS NOT DISTINCT FROM OLD.approved_amount
       AND NEW.advance_amount IS NOT DISTINCT FROM OLD.advance_amount THEN
        RETURN NEW;
    END IF;

    v_settled := public.outsource_invoice_settled(NEW.id);

    IF v_settled > 0 OR OLD.finance_payment_status IN ('Paid', 'Partly Paid') THEN
        NEW.finance_payment_status := public.derive_finance_payment_status(
            coalesce(NEW.approved_amount, 0) - coalesce(NEW.advance_amount, 0), v_settled);
    END IF;

    RETURN NEW;
END;
$$;

create trigger outsource_invoices_recalc_finance_status
  before update on public.outsource_invoices
  for each row execute function public.recalc_finance_status_on_amount_change();

-- ── Recording a payment ──────────────────────────────────────────────────────────
-- p_payment: { amount_paid, tds_amount, round_off, paid_on, ledger, payment_method, bank, utr }
--
-- Locks the invoice row so two simultaneous payments cannot both pass the overpay
-- check. Amounts are compared as numeric, never as client-side floats.

create function public.record_outsource_invoice_payment(p_invoice_id uuid, p_payment jsonb) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_role      text;
    v_invoice   public.outsource_invoices%ROWTYPE;
    v_amount    numeric := coalesce(nullif(p_payment->>'amount_paid', '')::numeric, 0);
    v_tds       numeric := coalesce(nullif(p_payment->>'tds_amount', '')::numeric, 0);
    v_round_off numeric := coalesce(nullif(p_payment->>'round_off', '')::numeric, 0);
    v_paid_on   date    := nullif(p_payment->>'paid_on', '')::date;
    v_method    text    := nullif(p_payment->>'payment_method', '');
    v_payable   numeric;
    v_settled   numeric;
    v_after     numeric;
    v_id        uuid;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance can record payments.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_invoice FROM public.outsource_invoices WHERE id = p_invoice_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found.';
    END IF;

    IF v_amount <> round(v_amount, 2) OR v_tds <> round(v_tds, 2) OR v_round_off <> round(v_round_off, 2) THEN
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

    v_payable := coalesce(v_invoice.approved_amount, 0) - coalesce(v_invoice.advance_amount, 0);
    v_settled := public.outsource_invoice_settled(p_invoice_id);
    v_after   := v_settled + v_amount + v_tds + v_round_off;

    IF v_after > v_payable THEN
        RAISE EXCEPTION 'This would overpay by ₹%; the balance is ₹%.',
            to_char(v_after - v_payable, 'FM99,99,99,99,990.00'),
            to_char(greatest(v_payable - v_settled, 0), 'FM99,99,99,99,990.00');
    END IF;

    -- Round-off only closes a sub-rupee remainder.
    IF v_round_off > 0 AND (v_round_off >= 1 OR v_after <> v_payable) THEN
        RAISE EXCEPTION 'Round-off can only write off a remainder of less than ₹1 that settles the invoice.';
    END IF;

    INSERT INTO public.outsource_invoice_payments
        (outsource_invoice_id, paid_on, amount_paid, tds_amount, round_off,
         ledger, payment_method, bank, utr, recorded_by)
    VALUES (
        p_invoice_id, v_paid_on, v_amount, v_tds, v_round_off,
        p_payment->>'ledger',
        v_method,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE p_payment->>'bank' END,
        CASE WHEN v_method = 'Cash' THEN NULL ELSE btrim(p_payment->>'utr') END,
        auth.uid()
    )
    RETURNING id INTO v_id;

    PERFORM public.apply_finance_status_recalc(p_invoice_id);

    RETURN v_id;
END;
$$;

-- ── Cancelling a payment ─────────────────────────────────────────────────────────
-- For a transaction that failed and was refunded. The row is kept, marked
-- Cancelled, and drops out of every total.

create function public.cancel_outsource_invoice_payment(p_payment_id uuid, p_reason text) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_role    text;
    v_payment public.outsource_invoice_payments%ROWTYPE;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance can cancel payments.' USING ERRCODE = '42501';
    END IF;

    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for cancelling this payment.';
    END IF;

    SELECT * INTO v_payment FROM public.outsource_invoice_payments WHERE id = p_payment_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment not found.';
    END IF;

    -- Same lock order as recording: invoice first, then its payments.
    PERFORM 1 FROM public.outsource_invoices WHERE id = v_payment.outsource_invoice_id FOR UPDATE;
    SELECT * INTO v_payment FROM public.outsource_invoice_payments WHERE id = p_payment_id FOR UPDATE;

    IF v_payment.status = 'Cancelled' THEN
        RAISE EXCEPTION 'This payment is already cancelled.';
    END IF;

    UPDATE public.outsource_invoice_payments
    SET    status        = 'Cancelled',
           cancelled_at  = now(),
           cancelled_by  = auth.uid(),
           cancel_reason = btrim(p_reason)
    WHERE  id = p_payment_id;

    PERFORM public.apply_finance_status_recalc(v_payment.outsource_invoice_id);
END;
$$;

alter function public.outsource_invoice_settled(uuid) owner to postgres;
alter function public.derive_finance_payment_status(numeric, numeric) owner to postgres;
alter function public.apply_finance_status_recalc(uuid) owner to postgres;
alter function public.recalc_finance_status_on_amount_change() owner to postgres;
alter function public.record_outsource_invoice_payment(uuid, jsonb) owner to postgres;
alter function public.cancel_outsource_invoice_payment(uuid, text) owner to postgres;

grant all on function public.record_outsource_invoice_payment(uuid, jsonb) to authenticated, service_role;
grant all on function public.cancel_outsource_invoice_payment(uuid, text) to authenticated, service_role;

-- Writes go only through the two functions above, which check the role. The direct
-- INSERT policy let maintenance execs add payments; it goes.
drop policy if exists "Exec finance insert invoice payments" on public.outsource_invoice_payments;

-- ── Reading payments with names ──────────────────────────────────────────────────
-- Finance cannot read exec or other finance profiles under RLS, so a plain join to
-- users would show blank names. This returns names only, nothing else from users.

create function public.get_outsource_invoice_payments(p_invoice_id uuid)
returns table(
    id                uuid,
    paid_on           date,
    amount_paid       numeric,
    tds_amount        numeric,
    round_off         numeric,
    ledger            text,
    payment_method    text,
    bank              text,
    utr               text,
    status            text,
    created_at        timestamptz,
    recorded_by_name  text,
    cancelled_at      timestamptz,
    cancelled_by_name text,
    cancel_reason     text
)
    language sql stable security definer
    set search_path to 'public'
    as $$
  select p.id, p.paid_on, p.amount_paid, p.tds_amount, p.round_off,
         p.ledger, p.payment_method, p.bank, p.utr, p.status, p.created_at,
         ru.name, p.cancelled_at, cu.name, p.cancel_reason
  from   public.outsource_invoice_payments p
  left join public.users ru on ru.id = p.recorded_by
  left join public.users cu on cu.id = p.cancelled_by
  where  p.outsource_invoice_id = p_invoice_id
    and  auth.uid() is not null
  order  by p.paid_on, p.created_at
$$;

alter function public.get_outsource_invoice_payments(uuid) owner to postgres;
grant all on function public.get_outsource_invoice_payments(uuid) to authenticated, service_role;

-- ── Summary tiles ────────────────────────────────────────────────────────────────
-- Signature unchanged, so CREATE OR REPLACE replaces it in place. Settled now counts
-- active Paid + TDS + Round-off; overdue means past the pay-by date and not Paid,
-- matching the list's red flag.

create or replace function public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] default null::text[],
    p_paid_by                    text[] default null::text[],
    p_date_from                  date   default null::date,
    p_date_to                    date   default null::date,
    p_finance_payment_status     text[] default null::text[]
) returns table(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    language sql stable security definer
    set search_path to 'public'
    as $$
    WITH paid_sums AS (
        SELECT outsource_invoice_id,
               SUM(amount_paid + tds_amount + round_off) AS total_settled
        FROM   outsource_invoice_payments
        WHERE  status = 'Active'
        GROUP  BY outsource_invoice_id
    )
    SELECT
        COALESCE(SUM(
            GREATEST(0,
                (oi.approved_amount - oi.advance_amount) - COALESCE(ps.total_settled, 0)
            )
        ), 0)                                                    AS total_unpaid_payable,

        COUNT(*) FILTER (WHERE
            oi.payby_date < CURRENT_DATE
            AND oi.finance_payment_status <> 'Paid'
        )                                                        AS overdue_count,

        COUNT(*) FILTER (WHERE oi.maintenance_payment_status = 'Hold') AS pending_approval_count

    FROM  outsource_invoices     oi
    JOIN  job_cards              jc ON jc.id = oi.job_card_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE jc.status = 'Completed'
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;
