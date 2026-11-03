-- MAIN-118: finance invoice statuses replace per-invoice payments.
--
-- UAT showed finance pays suppliers against a ledger by credit period, not invoice by
-- invoice. Finance's status on an outsource invoice becomes a review workflow —
-- New → Hold / Reject → Accepted → GST reconciled & closed / GST not applicable & closed
-- — and the per-invoice payments of MAIN-95 go. Prod held 0 payment rows.
--
-- The column keeps its name, finance_payment_status: renaming it would touch every
-- stored history row and the prod→staging sync for no gain. Only the labels change.

-- ── A. The statuses ──────────────────────────────────────────────────────────────
-- Mirrors FINANCE_STATUSES in src/constants/outsourceInvoices.js — keep in step.
--
-- The remap below is housekeeping, not a decision anyone made, so it stays out of the
-- invoice history. The old Hold/Reject sub-reason is kept in the remark.

alter table public.outsource_invoices disable trigger outsource_invoices_audit;

drop trigger if exists outsource_invoices_recalc_finance_status on public.outsource_invoices;

alter table public.outsource_invoices
  drop constraint outsource_invoices_finance_payment_status_check;

-- The day the invoice reached finance. Due dates count from it (MAIN-119).
alter table public.outsource_invoices
  add column submitted_on date;

update public.outsource_invoices
set    finance_remark = concat_ws(' — ', 'Previously ' || finance_payment_status, finance_remark)
where  finance_payment_status like 'Hold - %' or finance_payment_status like 'Reject - %';

update public.outsource_invoices
set    finance_payment_status = case
           when finance_payment_status like 'Hold%'   then 'Hold'
           when finance_payment_status like 'Reject%' then 'Reject'
           else 'New'
       end;

-- An invoice reached finance when its job card was completed, or — for one added to
-- an already-completed card — when it was created. completed_at is UTC without a zone.
update public.outsource_invoices oi
set    submitted_on = greatest(
           (coalesce(jc.completed_at at time zone 'UTC', oi.created_at) at time zone 'Asia/Kolkata')::date,
           (oi.created_at at time zone 'Asia/Kolkata')::date)
from   public.job_cards jc
where  jc.id = oi.job_card_id
  and  jc.status = 'Completed';

update public.outsource_invoices
set    submitted_on = (created_at at time zone 'Asia/Kolkata')::date
where  batch_service_id is not null;

alter table public.outsource_invoices
  alter column finance_payment_status set default 'New';

alter table public.outsource_invoices
  add constraint outsource_invoices_finance_payment_status_check
  check (finance_payment_status = any (array[
    'New'::text,
    'Hold'::text,
    'Reject'::text,
    'Accepted'::text,
    'GST reconciled & closed'::text,
    'GST not applicable & closed'::text
  ]));

-- A rejected invoice always carries its reason.
alter table public.outsource_invoices
  add constraint outsource_invoices_reject_reason_check
  check (finance_payment_status <> 'Reject' or nullif(btrim(finance_remark), '') is not null);

alter table public.outsource_invoices enable trigger outsource_invoices_audit;

-- ── B. Guard: owners, moves, and the Accepted lock ───────────────────────────────
-- Keeps MAIN-90's owner rules and adds:
--   • the moves finance may make — New ↔ Hold; New/Hold → Reject or Accepted;
--     Accepted → Hold, Reject or either GST-closed status. Reject and both GST-closed
--     statuses are final (Reject leaves only by resubmission, MAIN-120);
--   • a fresh reason in the remark for every move into Reject;
--   • once Accepted or GST-closed, nothing but the finance status and remark may
--     change — the invoice is in the supplier ledger (MAIN-119);
--   • submitted_on is set only by the submission below.
-- These are data integrity rather than permissions, so they hold for super_admin too.
--
-- The submission raises a transaction-local app.finance_submission flag, because it
-- sets finance's status on the exec's behalf.

create or replace function public.guard_outsource_invoice_status_owners() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_role                text;
    v_finance_changed     boolean;
    v_maintenance_changed boolean;
    v_old                 text;
    v_new                 text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF current_setting('app.finance_submission', true) = 'on' THEN
        RETURN NEW;
    END IF;

    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();

    IF TG_OP = 'INSERT' THEN
        v_finance_changed     := NEW.finance_payment_status <> 'New' OR NEW.finance_remark IS NOT NULL;
        v_maintenance_changed := NEW.maintenance_payment_status IS NOT NULL;
    ELSE
        v_finance_changed     := NEW.finance_payment_status IS DISTINCT FROM OLD.finance_payment_status
                              OR NEW.finance_remark         IS DISTINCT FROM OLD.finance_remark;
        v_maintenance_changed := NEW.maintenance_payment_status IS DISTINCT FROM OLD.maintenance_payment_status;
    END IF;

    IF v_finance_changed AND v_role IS DISTINCT FROM 'finance' AND v_role IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Only finance can change the finance status.'
            USING ERRCODE = '42501';
    END IF;

    IF v_maintenance_changed AND v_role = 'finance' THEN
        RAISE EXCEPTION 'Finance cannot change the payment status reported by maintenance.'
            USING ERRCODE = '42501';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF NEW.finance_payment_status <> 'New' OR NEW.submitted_on IS NOT NULL THEN
            RAISE EXCEPTION 'A new invoice starts at New and is submitted when it reaches finance.';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.submitted_on IS DISTINCT FROM OLD.submitted_on THEN
        RAISE EXCEPTION 'The submission date is set when the invoice reaches finance.';
    END IF;

    IF OLD.finance_payment_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
       AND (to_jsonb(NEW) - array['finance_payment_status', 'finance_remark', 'updated_at'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - array['finance_payment_status', 'finance_remark', 'updated_at']) THEN
        RAISE EXCEPTION 'Finance has accepted this invoice, so its details can no longer be changed.'
            USING ERRCODE = '42501';
    END IF;

    v_old := OLD.finance_payment_status;
    v_new := NEW.finance_payment_status;

    IF v_new IS DISTINCT FROM v_old THEN
        IF v_old = 'Reject' THEN
            RAISE EXCEPTION 'This invoice was rejected. Reject is final; the invoice can only come back by being resubmitted.';
        END IF;

        IF v_old IN ('GST reconciled & closed', 'GST not applicable & closed') THEN
            RAISE EXCEPTION 'This invoice is closed, so its finance status can no longer change.';
        END IF;

        IF NOT (   (v_old IN ('New', 'Hold') AND v_new IN ('New', 'Hold', 'Reject', 'Accepted'))
                OR (v_old = 'Accepted'       AND v_new IN ('Hold', 'Reject', 'GST reconciled & closed', 'GST not applicable & closed'))) THEN
            RAISE EXCEPTION 'Finance status cannot move from % to %.', v_old, v_new;
        END IF;

        IF v_new = 'Reject'
           AND (nullif(btrim(NEW.finance_remark), '') IS NULL
                OR NEW.finance_remark IS NOT DISTINCT FROM OLD.finance_remark) THEN
            RAISE EXCEPTION 'Give the reason for rejecting this invoice in the finance remark.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ── C. Submission: the invoice reaches finance ───────────────────────────────────
-- Stamps submitted_on (India time) and sets the starting status from maintenance's:
-- Approved → New; Hold → Hold; Reject → Reject, each of the last two with a remark
-- saying maintenance set it. Only the first time: a card reopened and closed again
-- keeps its date and whatever finance has done since, and a later change to the
-- maintenance status shows in the history without moving finance's status.

create function public.submit_outsource_invoice_to_finance(p_invoice_id uuid) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    PERFORM set_config('app.finance_submission', 'on', true);

    UPDATE public.outsource_invoices
    SET    submitted_on           = (now() AT TIME ZONE 'Asia/Kolkata')::date,
           finance_payment_status = CASE WHEN maintenance_payment_status IN ('Hold', 'Reject')
                                         THEN maintenance_payment_status ELSE 'New' END,
           finance_remark         = CASE WHEN maintenance_payment_status IN ('Hold', 'Reject')
                                         THEN maintenance_payment_status || ' set by maintenance exec'
                                         ELSE finance_remark END
    WHERE  id = p_invoice_id
      AND  submitted_on IS NULL;

    PERFORM set_config('app.finance_submission', 'off', true);
END;
$$;

-- Internal only: no client should call it directly.
revoke all on function public.submit_outsource_invoice_to_finance(uuid) from public, anon, authenticated;

-- A job card's invoice reaches finance when the card becomes Completed — through
-- close_job_card_with_scrap or finalize_outsource_invoice alike.
create function public.submit_invoice_on_job_card_completion() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    IF NEW.status = 'Completed' AND OLD.status IS DISTINCT FROM NEW.status THEN
        PERFORM public.submit_outsource_invoice_to_finance(oi.id)
        FROM   public.outsource_invoices oi
        WHERE  oi.job_card_id = NEW.id;
    END IF;
    RETURN NULL;
END;
$$;

create trigger job_cards_submit_outsource_invoice
  after update of status on public.job_cards
  for each row execute function public.submit_invoice_on_job_card_completion();

-- A multi-vehicle invoice reaches finance when it is first saved; so does a job card's
-- own invoice added after the card was completed (one closed through a linked line).
create function public.submit_invoice_on_insert() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    IF NEW.batch_service_id IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.job_cards WHERE id = NEW.job_card_id AND status = 'Completed') THEN
        PERFORM public.submit_outsource_invoice_to_finance(NEW.id);
    END IF;
    RETURN NULL;
END;
$$;

create trigger outsource_invoices_submit
  after insert on public.outsource_invoices
  for each row execute function public.submit_invoice_on_insert();

alter function public.guard_outsource_invoice_status_owners() owner to postgres;
alter function public.submit_outsource_invoice_to_finance(uuid) owner to postgres;
alter function public.submit_invoice_on_job_card_completion() owner to postgres;
alter function public.submit_invoice_on_insert() owner to postgres;

-- ── D. Functions that read payments ──────────────────────────────────────────────

-- Summary tiles count by finance status. The return columns change, so DROP + CREATE;
-- the parameters are unchanged, and the grants are restated.
drop function public.get_outsource_invoice_summary(text[], text[], date, date, text[]);

create function public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] default null::text[],
    p_paid_by                    text[] default null::text[],
    p_date_from                  date   default null::date,
    p_date_to                    date   default null::date,
    p_finance_payment_status     text[] default null::text[]
) returns table(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint)
    language sql stable security definer
    set search_path to 'public'
    as $$
    SELECT
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New')      AS new_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Hold')     AS hold_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Reject')   AS reject_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Accepted') AS accepted_count
    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed')
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

alter function public.get_outsource_invoice_summary(text[], text[], date, date, text[]) owner to postgres;
grant all on function public.get_outsource_invoice_summary(text[], text[], date, date, text[])
  to anon, authenticated, service_role;

-- History without the payments branch. Signature unchanged, so replaced in place.
create or replace function public.get_outsource_invoice_history(p_invoice_id uuid)
returns table(performed_at timestamptz, performed_by_name text, source text, action text,
              changed_fields text[], old_data jsonb, new_data jsonb)
    language sql stable security definer
    set search_path to 'public'
    as $$
  select a.performed_at, u.name, 'invoice', a.action, a.changed_fields, a.old_data, a.new_data
  from   public.audit_logs a
  left join public.users u on u.id = a.performed_by
  where  a.table_name = 'outsource_invoices'
    and  a.record_id  = p_invoice_id
    and  auth.uid() is not null

  union all

  select a.performed_at, u.name,
         case a.table_name when 'batch_services' then 'batch' else 'batch_vehicle' end,
         a.action, a.changed_fields, a.old_data, a.new_data
  from   public.outsource_invoices oi
  join   public.audit_logs a
         on a.table_name in ('batch_services', 'batch_service_vehicles')
        and a.record_id = oi.batch_service_id
  left join public.users u on u.id = a.performed_by
  where  oi.id = p_invoice_id
    and  auth.uid() is not null

  union all

  select oi.created_at, u.name, 'created', 'INSERT', null, null,
         jsonb_build_object('maintenance_payment_status', coalesce(
             (select a.old_data->>'maintenance_payment_status'
              from   public.audit_logs a
              where  a.table_name = 'outsource_invoices'
                and  a.record_id  = oi.id
                and  'maintenance_payment_status' = any (a.changed_fields)
              order  by a.performed_at
              limit  1),
             oi.maintenance_payment_status))
  from   public.outsource_invoices oi
  left join public.users u on u.id = oi.created_by
  where  oi.id = p_invoice_id
    and  auth.uid() is not null
    and  not exists (
           select 1 from public.audit_logs a
           where  a.table_name = 'outsource_invoices'
             and  a.record_id  = oi.id
             and  a.action     = 'INSERT')

  order by 1 desc
$$;

-- Cancelling a multi-vehicle invoice: refused once finance has accepted it, in place of
-- the old active-payment check. Signature unchanged.
create or replace function public.cancel_batch_service_invoice(p_batch_id uuid, p_reason text) returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_invoice_id uuid;
    v_status     text;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can cancel a multi-vehicle invoice.'
        )::text;
    END IF;

    IF nullif(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'CANCEL_REASON_REQUIRED',
            'error_message', 'Give a reason for cancelling.'
        )::text;
    END IF;

    SELECT id, finance_payment_status INTO v_invoice_id, v_status
    FROM   public.outsource_invoices
    WHERE  batch_service_id = p_batch_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_NOT_FOUND',
            'error_message', 'Multi-vehicle invoice not found.'
        )::text;
    END IF;

    IF (SELECT status FROM public.batch_services WHERE id = p_batch_id) <> 'Active' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_NOT_ACTIVE',
            'error_message', 'This multi-vehicle invoice is already cancelled.'
        )::text;
    END IF;

    IF v_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_ACCEPTED',
            'error_message', 'Finance has accepted this invoice. Ask finance to move it back to Hold first.'
        )::text;
    END IF;

    -- Release the job cards first, so the history reads "links removed, then cancelled".
    UPDATE public.batch_service_vehicles
    SET    job_card_id = NULL
    WHERE  batch_service_id = p_batch_id
      AND  job_card_id IS NOT NULL;

    UPDATE public.batch_services
    SET    status        = 'Cancelled',
           cancel_reason = btrim(p_reason),
           cancelled_at  = now(),
           cancelled_by  = auth.uid()
    WHERE  id = p_batch_id;
END;
$$;

-- Saving a multi-vehicle invoice: locked once finance has accepted it, in place of the
-- old active-payment check. Body otherwise unchanged; signature unchanged.
create or replace function public.save_batch_service_invoice(p_batch_id uuid, p_batch jsonb, p_invoice jsonb, p_lines jsonb) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_batch_id   uuid := p_batch_id;
    v_invoice_id uuid;
    v_status     text;
    v_approved   numeric;
    v_lines_sum  numeric;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can save a multi-vehicle invoice.'
        )::text;
    END IF;

    IF nullif(p_batch->>'supplier_id', '') IS NULL
       OR nullif(btrim(p_batch->>'invoice_url'), '') IS NULL
       OR nullif(btrim(p_invoice->>'invoice_no'), '') IS NULL
       OR nullif(p_invoice->>'date_of_activity', '') IS NULL
       OR nullif(p_invoice->>'paid_by', '') IS NULL
       OR nullif(p_invoice->>'invoice_value', '') IS NULL
       OR nullif(p_invoice->>'approved_amount', '') IS NULL
       OR nullif(p_invoice->>'advance_amount', '') IS NULL
       OR nullif(p_invoice->>'maintenance_payment_status', '') IS NULL
       OR nullif(p_invoice->>'payby_date', '') IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Fill in the vendor, every invoice field and the invoice file.'
        )::text;
    END IF;

    IF jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_VEHICLES',
            'error_message', 'Add at least one vehicle.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               WHERE nullif(btrim(l->>'site'), '') IS NULL) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINE_SITE_REQUIRED',
            'error_message', 'Choose a site for every vehicle.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               -- CASE, because OR does not promise to test the format before the cast.
               WHERE coalesce(l->>'work_type', '') NOT IN ('Greasing', 'Puncture', 'Air filling', 'Washing', 'Other')
                  OR NOT CASE WHEN coalesce(l->>'rate', '') ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$'
                              THEN (l->>'rate')::numeric > 0 ELSE false END
                  OR NOT CASE WHEN coalesce(l->>'quantity', '') ~ '^[0-9]{1,6}$'
                              THEN (l->>'quantity')::integer >= 1 ELSE false END) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINE_INCOMPLETE',
            'error_message', 'Every vehicle needs a type of work, a rate and a quantity of at least 1.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               WHERE l->>'work_type' = 'Other'
                 AND (nullif(btrim(l->>'work_type_other'), '') IS NULL
                      OR nullif(l->>'job_card_id', '') IS NULL)) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'OTHER_WORK_INCOMPLETE',
            'error_message', 'A line of type Other needs a description of the work and a job card.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               WHERE l->>'work_type' <> 'Other'
               GROUP BY l->>'vehicle_number', l->>'work_type'
               HAVING count(*) > 1) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DUPLICATE_LINE',
            'error_message', 'A vehicle appears twice with the same type of work.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               WHERE nullif(l->>'job_card_id', '') IS NOT NULL
                 AND NOT EXISTS (
                     SELECT 1 FROM public.job_cards jc
                     WHERE  jc.id = (l->>'job_card_id')::uuid
                       AND  jc.vehicle_number = l->>'vehicle_number'
                       AND  jc.type = 'Outsource'
                 )) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_MISMATCH',
            'error_message', 'A linked job card must be an outsourced job card of the same vehicle.'
        )::text;
    END IF;

    v_approved := (p_invoice->>'approved_amount')::numeric;
    SELECT sum((l->>'rate')::numeric * (l->>'quantity')::integer) INTO v_lines_sum
    FROM   jsonb_array_elements(p_lines) l;

    IF v_lines_sum IS DISTINCT FROM v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINES_MISMATCH',
            'error_message', format('Vehicle amounts add up to %s but the approved amount is %s.',
                                    v_lines_sum, v_approved)
        )::text;
    END IF;

    IF v_batch_id IS NULL THEN
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l WHERE nullif(l->>'id', '') IS NOT NULL) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'LINE_NOT_FOUND',
                'error_message', 'A new multi-vehicle invoice cannot carry saved lines.'
            )::text;
        END IF;

        INSERT INTO public.batch_services (supplier_id, invoice_url)
        VALUES ((p_batch->>'supplier_id')::uuid, btrim(p_batch->>'invoice_url'))
        RETURNING id INTO v_batch_id;

        INSERT INTO public.outsource_invoices
            (batch_service_id, date_of_activity, invoice_no, paid_by, invoice_value,
             approved_amount, advance_amount, maintenance_payment_status, payby_date, created_by)
        VALUES (
            v_batch_id,
            (p_invoice->>'date_of_activity')::date,
            btrim(p_invoice->>'invoice_no'),
            p_invoice->>'paid_by',
            (p_invoice->>'invoice_value')::numeric,
            v_approved,
            (p_invoice->>'advance_amount')::numeric,
            p_invoice->>'maintenance_payment_status',
            (p_invoice->>'payby_date')::date,
            auth.uid()
        );
    ELSE
        -- Lock the invoice first so finance cannot accept it between the check and the
        -- edit.
        SELECT id, finance_payment_status INTO v_invoice_id, v_status
        FROM   public.outsource_invoices
        WHERE  batch_service_id = v_batch_id
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_NOT_FOUND',
                'error_message', 'Multi-vehicle invoice not found.'
            )::text;
        END IF;

        IF (SELECT status FROM public.batch_services WHERE id = v_batch_id) = 'Cancelled' THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_CANCELLED',
                'error_message', 'This multi-vehicle invoice is cancelled. Restore it before editing.'
            )::text;
        END IF;

        IF v_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_LOCKED',
                'error_message', 'Finance has accepted this invoice, so it can no longer be edited.'
            )::text;
        END IF;

        IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
                   WHERE nullif(l->>'id', '') IS NOT NULL
                     AND NOT EXISTS (
                         SELECT 1 FROM public.batch_service_vehicles v
                         WHERE  v.id = (l->>'id')::uuid AND v.batch_service_id = v_batch_id
                     )) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'LINE_NOT_FOUND',
                'error_message', 'A vehicle line no longer exists. Reload the page and try again.'
            )::text;
        END IF;

        UPDATE public.batch_services
        SET    supplier_id = (p_batch->>'supplier_id')::uuid,
               invoice_url = btrim(p_batch->>'invoice_url')
        WHERE  id = v_batch_id;

        UPDATE public.outsource_invoices
        SET    date_of_activity           = (p_invoice->>'date_of_activity')::date,
               invoice_no                 = btrim(p_invoice->>'invoice_no'),
               paid_by                    = p_invoice->>'paid_by',
               invoice_value              = (p_invoice->>'invoice_value')::numeric,
               approved_amount            = v_approved,
               advance_amount             = (p_invoice->>'advance_amount')::numeric,
               maintenance_payment_status = p_invoice->>'maintenance_payment_status',
               payby_date                 = (p_invoice->>'payby_date')::date
        WHERE  id = v_invoice_id;

        DELETE FROM public.batch_service_vehicles
        WHERE  batch_service_id = v_batch_id
          AND  id NOT IN (
                   SELECT (l->>'id')::uuid FROM jsonb_array_elements(p_lines) l
                   WHERE  nullif(l->>'id', '') IS NOT NULL
               );

        -- The audit trigger logs only fields that changed, so an unchanged line writes
        -- no history.
        UPDATE public.batch_service_vehicles v
        SET    vehicle_number  = l->>'vehicle_number',
               site            = btrim(l->>'site'),
               work_type       = l->>'work_type',
               work_type_other = CASE WHEN l->>'work_type' = 'Other' THEN btrim(l->>'work_type_other') END,
               rate            = (l->>'rate')::numeric,
               quantity        = (l->>'quantity')::integer,
               amount          = (l->>'rate')::numeric * (l->>'quantity')::integer,
               job_card_id     = nullif(l->>'job_card_id', '')::uuid
        FROM   jsonb_array_elements(p_lines) l
        WHERE  v.batch_service_id = v_batch_id
          AND  nullif(l->>'id', '') IS NOT NULL
          AND  v.id = (l->>'id')::uuid;
    END IF;

    INSERT INTO public.batch_service_vehicles
        (batch_service_id, vehicle_number, site, work_type, work_type_other, rate, quantity, amount, job_card_id)
    SELECT v_batch_id,
           l->>'vehicle_number',
           btrim(l->>'site'),
           l->>'work_type',
           CASE WHEN l->>'work_type' = 'Other' THEN btrim(l->>'work_type_other') END,
           (l->>'rate')::numeric,
           (l->>'quantity')::integer,
           (l->>'rate')::numeric * (l->>'quantity')::integer,
           nullif(l->>'job_card_id', '')::uuid
    FROM   jsonb_array_elements(p_lines) l
    WHERE  nullif(l->>'id', '') IS NULL;

    RETURN v_batch_id;
END;
$$;

-- ── E. Retire per-invoice payments ───────────────────────────────────────────────
-- Payments move to the supplier (MAIN-119), in a table of their own. Dropping the
-- table takes its policies and its two triggers with it.

drop function public.recalc_finance_status_on_amount_change();
drop function public.record_outsource_invoice_payment(uuid, jsonb);
drop function public.cancel_outsource_invoice_payment(uuid, text);
drop function public.get_outsource_invoice_payments(uuid);
drop function public.apply_finance_status_recalc(uuid);
drop function public.outsource_invoice_settled(uuid);
drop function public.derive_finance_payment_status(numeric, numeric);

drop table public.outsource_invoice_payments;

drop function public.log_outsource_invoice_payment_change();
drop function public.guard_payment_on_cancelled_batch();
