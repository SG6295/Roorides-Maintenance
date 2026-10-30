-- MAIN-112: a multi-vehicle invoice can be cancelled — with a reason — and restored, and
-- an outsourced job card linked to one cannot be switched to in-house.
--
-- Cancelling: the exec or super_admin, only while no active payment exists (finance
-- cancels a payment first; refusing here keeps the money records straight). A cancelled
-- invoice stays in the Outsource Invoices list, flagged, but cannot be edited or paid and
-- drops out of the summary tiles. Its job card links are released, so a cancelled invoice
-- never holds a job card back; the history keeps who was linked.
--
-- Restoring: the reverse, and because the links were released, every Other line must be
-- given its outsourced job card again — the same rule save_batch_service_invoice holds.
-- Other lines may be relinked too.
--
-- Both are functions with their own exec check, like save_batch_service_invoice: the
-- batch tables have no client write policies. Both lock the invoice row first, the same
-- lock record_outsource_invoice_payment takes, so a payment cannot slip in between.

alter table public.batch_services
    add column status        text not null default 'Active',
    add column cancel_reason text,
    add column cancelled_at  timestamptz,
    add column cancelled_by  uuid;

alter table public.batch_services
    add constraint batch_services_status_check check (status in ('Active', 'Cancelled')),
    add constraint batch_services_cancel_reason_check
        check (status <> 'Cancelled' or btrim(cancel_reason) <> '');

-- Same trigger function; the batch's status and cancel reason are logged, so the invoice
-- history shows who cancelled or restored it and why.
create or replace function public.log_batch_service_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_fields  text[];
    v_new     jsonb;
    v_old     jsonb;
    v_changed text[];
    v_logged  text[];
    v_batch   uuid;
BEGIN
    IF TG_TABLE_NAME = 'batch_services' THEN
        v_fields := array['supplier_id', 'invoice_url', 'status', 'cancel_reason'];
        v_batch  := coalesce(NEW.id, OLD.id);
    ELSE
        v_fields := array['vehicle_number', 'site', 'work_type', 'work_type_other',
                          'rate', 'quantity', 'amount', 'job_card_id'];
        v_batch  := coalesce(NEW.batch_service_id, OLD.batch_service_id);
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_new := to_jsonb(NEW);
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'INSERT',
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD);
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'DELETE',
                (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN OLD;
    END IF;

    v_new := to_jsonb(NEW);
    v_old := to_jsonb(OLD);
    SELECT array_agg(f) INTO v_changed
    FROM   unnest(v_fields) f
    WHERE  v_new->f IS DISTINCT FROM v_old->f;

    IF v_changed IS NULL THEN
        RETURN NEW;
    END IF;

    v_logged := v_changed;
    IF TG_TABLE_NAME = 'batch_service_vehicles' THEN
        SELECT v_logged || array_agg(f) INTO v_logged
        FROM   unnest(array['vehicle_number', 'work_type']) f
        WHERE  NOT f = any (v_changed);
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES (TG_TABLE_NAME, v_batch, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_logged) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_logged) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$$;

-- Same function, refusing to edit a cancelled invoice.
create or replace function public.save_batch_service_invoice(
    p_batch_id uuid,
    p_batch    jsonb,
    p_invoice  jsonb,
    p_lines    jsonb
) returns uuid
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_batch_id   uuid := p_batch_id;
    v_invoice_id uuid;
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
        -- Lock the invoice first so a payment cannot be recorded between the check and
        -- the edit; record_outsource_invoice_payment takes the same lock.
        SELECT id INTO v_invoice_id
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

        IF EXISTS (SELECT 1 FROM public.outsource_invoice_payments
                   WHERE outsource_invoice_id = v_invoice_id AND status = 'Active') THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_LOCKED',
                'error_message', 'Finance has recorded a payment against this invoice, so it can no longer be edited.'
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

-- Errors: UNAUTHORIZED, BATCH_NOT_FOUND, BATCH_NOT_ACTIVE, BATCH_HAS_PAYMENTS,
--   CANCEL_REASON_REQUIRED.
create function public.cancel_batch_service_invoice(p_batch_id uuid, p_reason text)
    returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_invoice_id uuid;
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

    SELECT id INTO v_invoice_id
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

    IF EXISTS (SELECT 1 FROM public.outsource_invoice_payments
               WHERE outsource_invoice_id = v_invoice_id AND status = 'Active') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_HAS_PAYMENTS',
            'error_message', 'Finance has recorded a payment against this invoice. Ask finance to cancel the payment first.'
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

alter function public.cancel_batch_service_invoice(uuid, text) owner to postgres;
grant all on function public.cancel_batch_service_invoice(uuid, text) to authenticated, service_role;

-- p_links: [{ id, job_card_id }] — a job card per line. Required for every Other line,
-- optional for the rest; lines left out stay unlinked.
--
-- Errors: UNAUTHORIZED, BATCH_NOT_FOUND, BATCH_NOT_CANCELLED, LINE_NOT_FOUND,
--   OTHER_WORK_INCOMPLETE, JOB_CARD_MISMATCH.
create function public.restore_batch_service_invoice(p_batch_id uuid, p_links jsonb)
    returns void
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_links jsonb := coalesce(p_links, '[]'::jsonb);
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can restore a multi-vehicle invoice.'
        )::text;
    END IF;

    PERFORM 1 FROM public.outsource_invoices WHERE batch_service_id = p_batch_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_NOT_FOUND',
            'error_message', 'Multi-vehicle invoice not found.'
        )::text;
    END IF;

    IF (SELECT status FROM public.batch_services WHERE id = p_batch_id) <> 'Cancelled' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BATCH_NOT_CANCELLED',
            'error_message', 'This multi-vehicle invoice is not cancelled.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_links) l
               WHERE NOT EXISTS (
                   SELECT 1 FROM public.batch_service_vehicles v
                   WHERE  v.id = nullif(l->>'id', '')::uuid AND v.batch_service_id = p_batch_id
               )) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINE_NOT_FOUND',
            'error_message', 'A vehicle line no longer exists. Reload the page and try again.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM public.batch_service_vehicles v
               WHERE  v.batch_service_id = p_batch_id
                 AND  v.work_type = 'Other'
                 AND  NOT EXISTS (
                          SELECT 1 FROM jsonb_array_elements(v_links) l
                          WHERE  (l->>'id')::uuid = v.id AND nullif(l->>'job_card_id', '') IS NOT NULL
                      )) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'OTHER_WORK_INCOMPLETE',
            'error_message', 'Every line of type Other needs its job card linked again before the invoice can be restored.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1
               FROM   jsonb_array_elements(v_links) l
               JOIN   public.batch_service_vehicles v ON v.id = (l->>'id')::uuid
               WHERE  nullif(l->>'job_card_id', '') IS NOT NULL
                 AND  NOT EXISTS (
                          SELECT 1 FROM public.job_cards jc
                          WHERE  jc.id = (l->>'job_card_id')::uuid
                            AND  jc.vehicle_number = v.vehicle_number
                            AND  jc.type = 'Outsource'
                      )) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_MISMATCH',
            'error_message', 'A linked job card must be an outsourced job card of the same vehicle.'
        )::text;
    END IF;

    UPDATE public.batch_services
    SET    status        = 'Active',
           cancel_reason = NULL,
           cancelled_at  = NULL,
           cancelled_by  = NULL
    WHERE  id = p_batch_id;

    UPDATE public.batch_service_vehicles v
    SET    job_card_id = (l->>'job_card_id')::uuid
    FROM   jsonb_array_elements(v_links) l
    WHERE  v.id = (l->>'id')::uuid
      AND  nullif(l->>'job_card_id', '') IS NOT NULL;
END;
$$;

alter function public.restore_batch_service_invoice(uuid, jsonb) owner to postgres;
grant all on function public.restore_batch_service_invoice(uuid, jsonb) to authenticated, service_role;

-- No payment on a cancelled invoice, however it is recorded. A trigger rather than a
-- change to record_outsource_invoice_payment, so the rule also holds for any other path.
create function public.guard_payment_on_cancelled_batch() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
BEGIN
    IF NEW.status = 'Active' AND EXISTS (
        SELECT 1
        FROM   public.outsource_invoices oi
        JOIN   public.batch_services     b ON b.id = oi.batch_service_id
        WHERE  oi.id = NEW.outsource_invoice_id
          AND  b.status = 'Cancelled'
    ) THEN
        RAISE EXCEPTION 'This multi-vehicle invoice is cancelled, so no payment can be recorded against it.';
    END IF;
    RETURN NEW;
END;
$$;

alter function public.guard_payment_on_cancelled_batch() owner to postgres;

create trigger outsource_invoice_payments_guard_cancelled_batch
    before insert or update of status on public.outsource_invoice_payments
    for each row execute function public.guard_payment_on_cancelled_batch();

-- An outsourced job card linked to a multi-vehicle invoice line stays outsourced: the
-- link is only valid for outsourced cards. Unlink it on the invoice first (or cancel the
-- invoice, which releases its links).
create function public.guard_job_card_type_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_numbers text;
BEGIN
    IF OLD.type = 'Outsource' AND NEW.type IS DISTINCT FROM OLD.type THEN
        SELECT string_agg(DISTINCT 'MVI-' || b.batch_number, ', ') INTO v_numbers
        FROM   public.batch_service_vehicles v
        JOIN   public.batch_services         b ON b.id = v.batch_service_id
        WHERE  v.job_card_id = NEW.id;

        IF v_numbers IS NOT NULL THEN
            RAISE EXCEPTION 'This job card is linked to multi-vehicle invoice %, so it must stay outsourced. Remove the link on that invoice first.',
                v_numbers;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

alter function public.guard_job_card_type_change() owner to postgres;

create trigger trigger_guard_job_card_type_change
    before update of type on public.job_cards
    for each row execute function public.guard_job_card_type_change();

-- Same signature, so CREATE OR REPLACE replaces it: a cancelled multi-vehicle invoice
-- is owed nothing, so it drops out of every tile.
create or replace function public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] DEFAULT NULL::text[],
    p_paid_by text[] DEFAULT NULL::text[],
    p_date_from date DEFAULT NULL::date,
    p_date_to date DEFAULT NULL::date,
    p_finance_payment_status text[] DEFAULT NULL::text[]
) RETURNS TABLE(total_unpaid_payable numeric, overdue_count bigint, pending_approval_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    LEFT JOIN paid_sums          ps ON ps.outsource_invoice_id = oi.id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed')
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;
