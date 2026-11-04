-- MAIN-119: a reconciliation sits where it was posted, not after it.
--
-- An adjustment went at the end of its as-of day. Reconciling "as of today" at 5 pm
-- then put the adjustment after an invoice accepted at 7 pm, though the frozen figure
-- never included it. It now sits at the end of its as-of day or at the moment it was
-- posted, whichever is earlier — the same cut-off its frozen figure was taken at. Both
-- signatures are unchanged, so they are replaced in place and keep their grants.

create or replace function public.supplier_ledger_lines()
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
      AND  l.entry_at <= least(public.end_of_ist_day(p_as_of), now());

    INSERT INTO public.supplier_ledger_adjustments
        (supplier_id, as_of, confirmed_against, system_balance, confirmed_balance, reason, created_by)
    VALUES (p_supplier_id, p_as_of, p_confirmed_against, v_system, p_confirmed_balance, btrim(p_reason), auth.uid())
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;
