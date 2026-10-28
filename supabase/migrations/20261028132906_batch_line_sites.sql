-- MAIN-99: a multi-vehicle invoice's vehicles can belong to different sites, so the site
-- moves from the batch to each vehicle line.
--
-- The form fills a line's site from the vehicle's current vehicle_sites links — fixed
-- when there is one, a choice among them when there are several. The database only
-- requires that a site is present: vehicle_sites is rebuilt nightly from the Roorides
-- feed, so checking "one of the vehicle's sites" here would make an old batch
-- uncorrectable once its bus moves.
--
-- The column is nullable at the table level (a new NOT NULL column needs a default for
-- the prod→staging sync, and there is no sensible default site); the save function, the
-- only write path, refuses a line without one.
--
-- batch_services.site is dropped: MAIN-99 has not reached production, and its only rows
-- are staging test data, backfilled onto their lines first.

alter table public.batch_service_vehicles add column site text;

update public.batch_service_vehicles v
set    site = b.site
from   public.batch_services b
where  b.id = v.batch_service_id;

alter table public.batch_service_vehicles
    add constraint batch_service_vehicles_site_check check (btrim(site) <> '');

-- Same trigger function, with site tracked on the line instead of the batch.
create or replace function public.log_batch_service_change() returns trigger
    language plpgsql security definer
    set search_path to 'public'
    as $$
DECLARE
    v_fields  text[];
    v_new     jsonb;
    v_old     jsonb;
    v_changed text[];
    v_batch   uuid;
BEGIN
    IF TG_TABLE_NAME = 'batch_services' THEN
        v_fields := array['description', 'supplier_id', 'invoice_url'];
        v_batch  := coalesce(NEW.id, OLD.id);
    ELSE
        v_fields := array['vehicle_number', 'site', 'amount'];
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

    -- A line update logs its vehicle too, so the entry says which bus changed.
    IF TG_TABLE_NAME = 'batch_service_vehicles' AND NOT 'vehicle_number' = any (v_changed) THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
        VALUES (TG_TABLE_NAME, v_batch, 'UPDATE',
                (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed || 'vehicle_number'::text) f),
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed || 'vehicle_number'::text) f),
                v_changed,
                auth.uid());
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES (TG_TABLE_NAME, v_batch, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$$;

alter table public.batch_services drop column site;

-- Same signature, so CREATE OR REPLACE replaces it. Differences from the first version:
-- p_batch no longer carries a site, each line must, and a line's site is updated like
-- its amount.
--
-- p_batch:   { description, supplier_id, invoice_url }
-- p_invoice: { date_of_activity, invoice_no, paid_by, invoice_value, approved_amount,
--              advance_amount, maintenance_payment_status, payby_date }
-- p_lines:   [{ vehicle_number, site, amount }, ...]  — the full set, matched on
--            vehicle_number (see the first version's notes).
--
-- Errors: UNAUTHORIZED, BATCH_NOT_FOUND, BATCH_LOCKED, INVOICE_DETAILS_INCOMPLETE,
--   NO_VEHICLES, DUPLICATE_VEHICLE, LINE_SITE_REQUIRED, LINES_MISMATCH.
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

    IF nullif(btrim(p_batch->>'description'), '') IS NULL
       OR nullif(p_batch->>'supplier_id', '') IS NULL
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
            'error_message', 'Fill in the work details, every invoice field and the invoice file.'
        )::text;
    END IF;

    IF jsonb_array_length(coalesce(p_lines, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_VEHICLES',
            'error_message', 'Add at least one vehicle.'
        )::text;
    END IF;

    IF (SELECT count(*) <> count(DISTINCT l->>'vehicle_number')
        FROM jsonb_array_elements(p_lines) l) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'DUPLICATE_VEHICLE',
            'error_message', 'A vehicle appears on more than one line.'
        )::text;
    END IF;

    IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l
               WHERE nullif(btrim(l->>'site'), '') IS NULL) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINE_SITE_REQUIRED',
            'error_message', 'Choose a site for every vehicle.'
        )::text;
    END IF;

    v_approved := (p_invoice->>'approved_amount')::numeric;
    SELECT sum((l->>'amount')::numeric) INTO v_lines_sum FROM jsonb_array_elements(p_lines) l;

    IF v_lines_sum IS DISTINCT FROM v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'LINES_MISMATCH',
            'error_message', format('Vehicle amounts add up to %s but the approved amount is %s.',
                                    v_lines_sum, v_approved)
        )::text;
    END IF;

    IF v_batch_id IS NULL THEN
        INSERT INTO public.batch_services (description, supplier_id, invoice_url)
        VALUES (
            btrim(p_batch->>'description'),
            (p_batch->>'supplier_id')::uuid,
            btrim(p_batch->>'invoice_url')
        )
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

        IF EXISTS (SELECT 1 FROM public.outsource_invoice_payments
                   WHERE outsource_invoice_id = v_invoice_id AND status = 'Active') THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_LOCKED',
                'error_message', 'Finance has recorded a payment against this invoice, so it can no longer be edited.'
            )::text;
        END IF;

        UPDATE public.batch_services
        SET    description = btrim(p_batch->>'description'),
               supplier_id = (p_batch->>'supplier_id')::uuid,
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
          AND  vehicle_number NOT IN (
                   SELECT l->>'vehicle_number' FROM jsonb_array_elements(p_lines) l
               );

        UPDATE public.batch_service_vehicles v
        SET    amount = (l->>'amount')::numeric,
               site   = btrim(l->>'site')
        FROM   jsonb_array_elements(p_lines) l
        WHERE  v.batch_service_id = v_batch_id
          AND  v.vehicle_number   = l->>'vehicle_number'
          AND  (v.amount IS DISTINCT FROM (l->>'amount')::numeric
                OR v.site IS DISTINCT FROM btrim(l->>'site'));
    END IF;

    INSERT INTO public.batch_service_vehicles (batch_service_id, vehicle_number, site, amount)
    SELECT v_batch_id, l->>'vehicle_number', btrim(l->>'site'), (l->>'amount')::numeric
    FROM   jsonb_array_elements(p_lines) l
    WHERE  NOT EXISTS (
               SELECT 1 FROM public.batch_service_vehicles v
               WHERE  v.batch_service_id = v_batch_id
                 AND  v.vehicle_number   = l->>'vehicle_number'
           );

    RETURN v_batch_id;
END;
$$;
