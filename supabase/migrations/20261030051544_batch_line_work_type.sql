-- MAIN-112: a multi-vehicle invoice's lines say what was done to each vehicle.
--
-- One vendor invoice mixes work — hub greasing on twelve buses and a puncture on three
-- of them — so the single description on the batch moves onto each line as a work type,
-- and a line's amount becomes rate × quantity. A vehicle may now appear on more than one
-- line when the work differs; the same vehicle twice with the same standard work type is
-- still refused. "Other" lines repeat freely, but each must name its work and link the
-- outsourced job card it belongs to.
--
-- The new columns are nullable at the table level (a new NOT NULL column needs a default
-- for the prod→staging sync, and none of these has a sensible one); the save function,
-- the only write path, requires them. Whether a linked job card is this vehicle's and
-- outsourced is checked there too and not by a constraint, because a job card's type can
-- change after the batch is saved.
--
-- Lines can no longer be matched on vehicle_number, so the save function matches them on
-- their id. batch_services.description is dropped: production has no batches, and
-- staging's one test batch is converted to Greasing first.

alter table public.batch_service_vehicles
    add column work_type       text,
    add column work_type_other text,
    add column rate            numeric(12,2),
    add column quantity        integer,
    add column job_card_id     uuid references public.job_cards(id);

-- Keep in step with BATCH_WORK_TYPES in src/constants/batchWorkTypes.js.
alter table public.batch_service_vehicles
    add constraint batch_service_vehicles_work_type_check
        check (work_type in ('Greasing', 'Puncture', 'Air filling', 'Washing', 'Other')),
    add constraint batch_service_vehicles_work_type_other_check
        check (work_type_other is null or (work_type = 'Other' and btrim(work_type_other) <> '')),
    add constraint batch_service_vehicles_rate_check check (rate > 0),
    add constraint batch_service_vehicles_quantity_check check (quantity >= 1),
    add constraint batch_service_vehicles_amount_rate_check
        check (rate is null or quantity is null or amount = rate * quantity);

update public.batch_service_vehicles
set    work_type = 'Greasing',
       quantity  = 1,
       rate      = amount
where  work_type is null;

-- One line per vehicle becomes one line per vehicle per standard work type. Deferred,
-- so a save that swaps two lines' work types is judged once all its rows are written.
alter table public.batch_service_vehicles drop constraint batch_service_vehicles_vehicle_key;
alter table public.batch_service_vehicles
    add constraint batch_service_vehicles_work_type_key
        exclude using btree (batch_service_id with =, vehicle_number with =, work_type with =)
        where (work_type <> 'Other')
        deferrable initially deferred;

-- The job card page looks its linked lines up.
create index batch_service_vehicles_job_card_id_idx
    on public.batch_service_vehicles (job_card_id)
    where job_card_id is not null;

-- Same trigger function: the batch no longer has a description, and a line tracks its
-- work. A line update also logs its vehicle and work type when they did not change, so
-- the entry says which line it was.
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
        v_fields := array['supplier_id', 'invoice_url'];
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

alter table public.batch_services drop column description;

-- Same signature, so CREATE OR REPLACE replaces it. Differences from the MAIN-99 version:
-- p_batch has no description; each line carries its work, rate and quantity, and its
-- amount is worked out here rather than taken from the client; lines are matched on id.
--
-- p_batch:   { supplier_id, invoice_url }
-- p_invoice: { date_of_activity, invoice_no, paid_by, invoice_value, approved_amount,
--              advance_amount, maintenance_payment_status, payby_date }
-- p_lines:   [{ id?, vehicle_number, site, work_type, work_type_other?, rate, quantity,
--              job_card_id? }, ...] — the full set. A line with an id is that saved line;
--            one without is new; a saved line missing from the set is removed.
--
-- Errors: UNAUTHORIZED, BATCH_NOT_FOUND, BATCH_LOCKED, INVOICE_DETAILS_INCOMPLETE,
--   NO_VEHICLES, LINE_SITE_REQUIRED, LINE_INCOMPLETE, OTHER_WORK_INCOMPLETE,
--   DUPLICATE_LINE, JOB_CARD_MISMATCH, LINE_NOT_FOUND, LINES_MISMATCH.
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
