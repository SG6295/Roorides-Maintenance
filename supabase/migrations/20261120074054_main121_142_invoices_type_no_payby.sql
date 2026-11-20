-- MAIN-121: stop asking for, requiring or writing the Pay By Date.
-- The supplier ledger (MAIN-119) works out when an invoice is due, so the date the
-- exec typed is unused. outsource_invoices.payby_date, its index and its stored values
-- are kept: an update no longer writes the column at all, so a save cannot clear a
-- past value, and the history trigger still renders past changes to it.
-- Every function keeps its signature (jsonb arguments), so CREATE OR REPLACE replaces
-- it rather than adding an overload.

CREATE OR REPLACE FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_job_card job_cards%ROWTYPE;
    v_invoice  outsource_invoices%ROWTYPE;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can finalize outsource invoices.',
            'details',       null
        )::text;
    END IF;

    SELECT * INTO v_job_card
    FROM   public.job_cards
    WHERE  id     = p_job_card_id
      AND  status = 'Completed - Invoice Pending'
      AND  type   = 'Outsource';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'JOB_CARD_NOT_ELIGIBLE',
            'error_message', 'Job card not found or is not an Outsource card with status "Completed - Invoice Pending".',
            'details',       null
        )::text;
    END IF;

    -- A linked multi-vehicle invoice line bills the work, so the card's own invoice is
    -- not needed to finalize.
    IF NOT EXISTS (
        SELECT 1 FROM public.batch_service_vehicles WHERE job_card_id = p_job_card_id
    ) THEN
        IF v_job_card.invoice_url IS NULL THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVOICE_FILE_REQUIRED',
                'error_message', 'An invoice file must be uploaded before finalizing.',
                'details',       null
            )::text;
        END IF;

        SELECT * INTO v_invoice
        FROM   public.outsource_invoices
        WHERE  job_card_id = p_job_card_id;

        IF NOT FOUND
           OR v_invoice.invoice_no                 IS NULL
           OR v_invoice.invoice_value              IS NULL
           OR v_invoice.approved_amount            IS NULL
           OR v_invoice.advance_amount             IS NULL
           OR v_invoice.date_of_activity           IS NULL
           OR v_invoice.maintenance_payment_status IS NULL
           OR v_invoice.paid_by                    IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVOICE_DETAILS_INCOMPLETE',
                'error_message', 'Invoice details are incomplete. Please fill in all required fields before finalizing.',
                'details',       null
            )::text;
        END IF;
    END IF;

    UPDATE public.job_cards
    SET    status  = 'Completed',
           remarks = coalesce(p_remarks, remarks)
    WHERE  id = p_job_card_id;

    RETURN json_build_object(
        'success',     true,
        'job_card_id', p_job_card_id
    );
END;
$$;


CREATE OR REPLACE FUNCTION public.resubmit_outsource_invoice(p_invoice_id uuid, p_resubmission jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
    v_inv       public.outsource_invoices%ROWTYPE;
    v_before    jsonb;
    v_today     date    := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_supplier  uuid    := nullif(p_resubmission->>'supplier_id', '')::uuid;
    v_file      text    := nullif(btrim(p_resubmission->>'invoice_file_url'), '');
    v_invoice   text    := nullif(btrim(p_resubmission->>'invoice_no'), '');
    v_date      date    := nullif(p_resubmission->>'date_of_activity', '')::date;
    v_paid_by   text    := nullif(p_resubmission->>'paid_by', '');
    v_maint     text    := nullif(p_resubmission->>'maintenance_payment_status', '');
    v_inv_value numeric;
    v_approved  numeric;
    v_advance   numeric;
    v_old_supp  uuid;
    v_supp_name text;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION 'Only maintenance executives can resubmit an invoice.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.outsource_invoices WHERE id = p_invoice_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found.';
    END IF;

    IF v_inv.finance_payment_status IS DISTINCT FROM 'Reject' THEN
        RAISE EXCEPTION 'Only a rejected invoice can be resubmitted.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.batch_services
               WHERE id = v_inv.batch_service_id AND status = 'Cancelled') THEN
        RAISE EXCEPTION 'This multi-vehicle invoice is cancelled. Restore it before resubmitting.';
    END IF;

    -- CASE, because OR does not promise to test the format before the cast.
    v_inv_value := CASE WHEN coalesce(p_resubmission->>'invoice_value', '')   ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' THEN (p_resubmission->>'invoice_value')::numeric END;
    v_approved  := CASE WHEN coalesce(p_resubmission->>'approved_amount', '') ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' THEN (p_resubmission->>'approved_amount')::numeric END;
    v_advance   := CASE WHEN coalesce(p_resubmission->>'advance_amount', '')  ~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' THEN (p_resubmission->>'advance_amount')::numeric END;

    -- The rules of the invoice form (validateInvoiceForm).
    IF v_invoice IS NULL OR length(v_invoice) > 50
       OR v_date IS NULL OR v_date > v_today
       OR v_paid_by IS NULL OR v_maint IS NULL
       OR v_inv_value IS NULL OR v_inv_value <= 0
       OR v_approved  IS NULL OR v_approved > v_inv_value
       OR v_advance   IS NULL OR v_advance  > v_approved THEN
        RAISE EXCEPTION 'Check the invoice details.';
    END IF;

    SELECT coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id), pi.supplier_name
    INTO   v_old_supp, v_supp_name
    FROM   public.outsource_invoices oi
    LEFT JOIN public.job_cards         jc ON jc.id = oi.job_card_id
    LEFT JOIN public.batch_services    bs ON bs.id = oi.batch_service_id
    LEFT JOIN public.purchase_invoices pi ON pi.id = oi.purchase_invoice_id
    WHERE  oi.id = p_invoice_id;

    -- A purchase recorded before suppliers were linked (MAIN-128) may keep its typed name.
    IF v_supplier IS NULL AND v_old_supp IS NOT NULL THEN
        RAISE EXCEPTION 'Choose the supplier.';
    END IF;

    IF v_supplier IS DISTINCT FROM v_old_supp THEN
        SELECT entity_name INTO v_supp_name
        FROM   public.suppliers
        WHERE  id = v_supplier AND status = 'approved';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose an approved supplier.';
        END IF;
    END IF;

    v_before := public.outsource_invoice_snapshot(p_invoice_id);

    PERFORM set_config('app.invoice_resubmission', 'on', true);

    IF v_inv.job_card_id IS NOT NULL THEN
        UPDATE public.job_cards
        SET    supplier_id = v_supplier,
               invoice_url = v_file
        WHERE  id = v_inv.job_card_id;
    ELSIF v_inv.batch_service_id IS NOT NULL THEN
        UPDATE public.batch_services
        SET    supplier_id = v_supplier,
               invoice_url = v_file
        WHERE  id = v_inv.batch_service_id;
    ELSE
        UPDATE public.purchase_invoices
        SET    supplier_id      = v_supplier,
               supplier_name    = v_supp_name,
               invoice_number   = v_invoice,
               invoice_date     = v_date,
               invoice_file_url = v_file
        WHERE  id = v_inv.purchase_invoice_id;
    END IF;

    UPDATE public.outsource_invoices
    SET    date_of_activity           = v_date,
           invoice_no                 = v_invoice,
           paid_by                    = v_paid_by,
           invoice_value              = v_inv_value,
           approved_amount            = v_approved,
           advance_amount             = v_advance,
           maintenance_payment_status = v_maint
    WHERE  id = p_invoice_id;

    PERFORM public.complete_invoice_resubmission(p_invoice_id, v_before, p_resubmission->>'note');

    PERFORM set_config('app.invoice_resubmission', 'off', true);
END;
$_$;

CREATE OR REPLACE FUNCTION public.save_batch_service_invoice(p_batch_id uuid, p_batch jsonb, p_invoice jsonb, p_lines jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $_$
DECLARE
    v_batch_id   uuid := p_batch_id;
    v_invoice_id uuid;
    v_status     text;
    v_approved   numeric;
    v_lines_sum  numeric;
    -- A rejected invoice changes only by being resubmitted (MAIN-120).
    v_resubmit   boolean := coalesce((p_invoice->>'resubmit')::boolean, false);
    v_before     jsonb;
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
        IF v_resubmit THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'NOT_REJECTED',
                'error_message', 'Only a rejected invoice can be resubmitted.'
            )::text;
        END IF;

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
             approved_amount, advance_amount, maintenance_payment_status, created_by)
        VALUES (
            v_batch_id,
            (p_invoice->>'date_of_activity')::date,
            btrim(p_invoice->>'invoice_no'),
            p_invoice->>'paid_by',
            (p_invoice->>'invoice_value')::numeric,
            v_approved,
            (p_invoice->>'advance_amount')::numeric,
            p_invoice->>'maintenance_payment_status',
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

        IF v_status = 'Reject' AND NOT v_resubmit THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'BATCH_REJECTED',
                'error_message', 'Finance has rejected this invoice. Resubmit it to change its details.'
            )::text;
        END IF;

        IF v_resubmit AND v_status IS DISTINCT FROM 'Reject' THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'NOT_REJECTED',
                'error_message', 'Only a rejected invoice can be resubmitted.'
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

        IF v_resubmit THEN
            v_before := public.outsource_invoice_snapshot(v_invoice_id);
            PERFORM set_config('app.invoice_resubmission', 'on', true);
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
               maintenance_payment_status = p_invoice->>'maintenance_payment_status'
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

    IF v_resubmit THEN
        PERFORM public.complete_invoice_resubmission(v_invoice_id, v_before, p_invoice->>'resubmit_note');
        PERFORM set_config('app.invoice_resubmission', 'off', true);
    END IF;

    RETURN v_batch_id;
END;
$_$;


CREATE OR REPLACE FUNCTION public.save_purchase_finance_invoice(p_invoice_id uuid, p_invoice jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_header    public.purchase_invoices%ROWTYPE;
    v_finance   public.outsource_invoices%ROWTYPE;
    v_inv_value numeric := NULLIF(p_invoice->>'invoice_value', '')::numeric;
    v_approved  numeric := NULLIF(p_invoice->>'approved_amount', '')::numeric;
    v_advance   numeric := NULLIF(p_invoice->>'advance_amount', '')::numeric;
    v_total     numeric;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION 'Only maintenance executives can record or edit a purchase invoice.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_header FROM public.purchase_invoices WHERE id = p_invoice_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found.';
    END IF;

    -- The same rules as the invoice form on a job card or multi-vehicle invoice.
    IF NULLIF(btrim(COALESCE(v_header.invoice_number, '')), '') IS NULL
       OR v_header.invoice_date IS NULL
       OR v_header.invoice_date > (now() AT TIME ZONE 'Asia/Kolkata')::date
       OR NULLIF(p_invoice->>'paid_by', '') IS NULL
       OR NULLIF(p_invoice->>'maintenance_payment_status', '') IS NULL
       OR v_inv_value IS NULL OR v_inv_value <= 0
       OR v_approved  IS NULL OR v_approved  < 0 OR v_approved > v_inv_value
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved THEN
        RAISE EXCEPTION 'Check the invoice details.';
    END IF;

    SELECT COALESCE(sum(line_total), 0) INTO v_total
    FROM   public.purchase_invoice_items
    WHERE  invoice_id = p_invoice_id;

    -- Compared in numeric, as on a multi-vehicle invoice.
    IF v_total <> v_approved THEN
        RAISE EXCEPTION 'The lines add up to ₹%; the approved amount is ₹%.',
            to_char(v_total, 'FM999999999990.00'), to_char(v_approved, 'FM999999999990.00');
    END IF;

    SELECT * INTO v_finance
    FROM   public.outsource_invoices
    WHERE  purchase_invoice_id = p_invoice_id
    FOR UPDATE;

    IF NOT FOUND THEN
        -- The insert trigger submits it to finance.
        INSERT INTO public.outsource_invoices (
            purchase_invoice_id, date_of_activity, invoice_no, paid_by, invoice_value,
            approved_amount, advance_amount, maintenance_payment_status, created_by
        ) VALUES (
            p_invoice_id, v_header.invoice_date, btrim(v_header.invoice_number), p_invoice->>'paid_by', v_inv_value,
            v_approved, v_advance, p_invoice->>'maintenance_payment_status', auth.uid()
        );
        RETURN;
    END IF;

    -- Refused by the status guard once finance has accepted it, unless nothing changed.
    UPDATE public.outsource_invoices
    SET    date_of_activity           = v_header.invoice_date,
           invoice_no                 = btrim(v_header.invoice_number),
           paid_by                    = p_invoice->>'paid_by',
           invoice_value              = v_inv_value,
           approved_amount            = v_approved,
           advance_amount             = v_advance,
           maintenance_payment_status = p_invoice->>'maintenance_payment_status'
    WHERE  id = v_finance.id;

    -- The file has arrived: the invoice is ready for finance.
    IF v_finance.finance_payment_status = 'New (invoice pending)' AND v_header.invoice_file_url IS NOT NULL THEN
        PERFORM set_config('app.finance_submission', 'on', true);
        UPDATE public.outsource_invoices SET finance_payment_status = 'New' WHERE id = v_finance.id;
        PERFORM set_config('app.finance_submission', 'off', true);
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.record_refurbishment(p_invoice jsonb, p_lines jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location    uuid := NULLIF(p_invoice->>'location_id', '')::uuid;
    v_supplier_id uuid := NULLIF(p_invoice->>'supplier_id', '')::uuid;
    v_supplier    text;
    v_inv_date    date := NULLIF(p_invoice->>'invoice_date', '')::date;
    v_inv_value   numeric := NULLIF(p_invoice->>'invoice_value', '')::numeric;
    v_approved    numeric := NULLIF(p_invoice->>'approved_amount', '')::numeric;
    v_advance     numeric := NULLIF(p_invoice->>'advance_amount', '')::numeric;
    v_total       numeric;
    v_invoice_id  uuid;
    v_line        jsonb;
    v_scrap_id    uuid;
    v_scrap       public.scrap_inventory%ROWTYPE;
    v_final_scrap uuid;
    v_part_id     uuid;
    v_part_name   text;
    v_part_number text;
    v_part_unit   text;
    v_refurb_id   uuid;
    v_item_id     uuid;
    v_quantity    numeric;
    v_unit_price  numeric;
    v_comment     text;
    v_seen        uuid[] := '{}';
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record a refurbishment.',
            'details',       null
        )::text;
    END IF;

    IF NULLIF(btrim(COALESCE(p_invoice->>'invoice_number', '')), '') IS NULL
       OR v_supplier_id IS NULL
       OR v_inv_date IS NULL
       OR v_location IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_INCOMPLETE',
            'error_message', 'Supplier, invoice number, invoice date and workshop are required.',
            'details',       null
        )::text;
    END IF;

    SELECT entity_name INTO v_supplier
    FROM   public.suppliers
    WHERE  id = v_supplier_id AND status = 'approved';

    IF NOT FOUND THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'SUPPLIER_NOT_APPROVED',
            'error_message', 'Choose an approved supplier.',
            'details',       null
        )::text;
    END IF;

    IF NULLIF(btrim(COALESCE(p_invoice->>'invoice_file_url', '')), '') IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_FILE_REQUIRED',
            'error_message', 'Attach the invoice file.',
            'details',       null
        )::text;
    END IF;

    -- The same rules as the invoice form on a job card or multi-vehicle invoice.
    IF v_inv_date > (now() AT TIME ZONE 'Asia/Kolkata')::date
       OR NULLIF(p_invoice->>'paid_by', '') IS NULL
       OR NULLIF(p_invoice->>'maintenance_payment_status', '') IS NULL
       OR v_inv_value IS NULL OR v_inv_value <= 0
       OR v_approved  IS NULL OR v_approved  < 0 OR v_approved > v_inv_value
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INVALID',
            'error_message', 'Check the invoice details.',
            'details',       null
        )::text;
    END IF;

    IF jsonb_array_length(COALESCE(p_lines, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_LINES',
            'error_message', 'Add at least one refurbished part.',
            'details',       null
        )::text;
    END IF;

    -- In id order, so two invoices touching the same rows cannot deadlock.
    PERFORM 1
    FROM    public.scrap_inventory
    WHERE   id IN (SELECT (l->>'scrap_inventory_id')::uuid
                   FROM   jsonb_array_elements(p_lines) l
                   WHERE  l->>'scrap_inventory_id' IS NOT NULL)
    ORDER   BY id
    FOR UPDATE;

    -- Only this function may mark an invoice a refurbishment or add lines to one.
    PERFORM set_config('app.recording_refurbishment', 'on', true);

    INSERT INTO public.purchase_invoices
        (kind, invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, created_by)
    VALUES (
        'refurbishment',
        btrim(p_invoice->>'invoice_number'),
        v_supplier_id,
        v_supplier,
        v_inv_date,
        NULLIF(p_invoice->>'notes', ''),
        btrim(p_invoice->>'invoice_file_url'),
        v_location,
        auth.uid()
    )
    RETURNING id INTO v_invoice_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_scrap_id   := NULLIF(v_line->>'scrap_inventory_id', '')::uuid;
        v_quantity   := round((v_line->>'quantity')::numeric, 2);
        v_unit_price := (v_line->>'unit_price')::numeric;
        v_comment    := NULLIF(btrim(COALESCE(v_line->>'comment', '')), '');

        IF v_quantity IS NULL OR v_quantity <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_QUANTITY',
                'error_message', 'Every line needs a quantity above zero.',
                'details',       null
            )::text;
        END IF;
        IF v_unit_price IS NULL OR v_unit_price < 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_PRICE',
                'error_message', 'Every line needs a unit price.',
                'details',       null
            )::text;
        END IF;

        IF v_scrap_id IS NOT NULL THEN
            IF v_scrap_id = ANY(v_seen) THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'DUPLICATE_SCRAP_ITEM',
                    'error_message', 'The same scrap item appears more than once.',
                    'details',       json_build_object('duplicate_id', v_scrap_id)
                )::text;
            END IF;
            v_seen := v_seen || v_scrap_id;

            SELECT * INTO v_scrap FROM public.scrap_inventory WHERE id = v_scrap_id;

            IF NOT FOUND OR v_scrap.status <> 'in_storage' THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'INVALID_SCRAP_ITEM',
                    'error_message', 'One of those scrap items is no longer in storage. Refresh and try again.',
                    'details',       json_build_object('scrap_inventory_id', v_scrap_id)
                )::text;
            END IF;
            IF v_scrap.location_id <> v_location THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'WRONG_WORKSHOP',
                    'error_message', format('"%s" is held at another workshop.', v_scrap.part_name_snapshot),
                    'details',       null
                )::text;
            END IF;
            IF v_quantity > v_scrap.quantity_snapshot THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'QUANTITY_EXCEEDS_SCRAP',
                    'error_message', format('Only %s of "%s" is in scrap.', v_scrap.quantity_snapshot, v_scrap.part_name_snapshot),
                    'details',       null
                )::text;
            END IF;

            v_part_id := v_scrap.part_id_snapshot;
        ELSE
            v_part_id := NULLIF(v_line->>'original_part_id', '')::uuid;

            IF v_comment IS NULL THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'MISSING_COMMENT',
                    'error_message', 'A comment is required for a part that is not in the scrap list.',
                    'details',       null
                )::text;
            END IF;
        END IF;

        -- Locked so two invoices cannot each create a refurbished part for one original.
        SELECT name, part_number, unit INTO v_part_name, v_part_number, v_part_unit
        FROM   public.parts WHERE id = v_part_id FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_PART',
                'error_message', 'Choose the original part for every line.',
                'details',       null
            )::text;
        END IF;

        -- Matching on either side means a refurbished part that is scrapped and
        -- refurbished again goes back to the same part.
        v_refurb_id := NULL;
        SELECT refurbished_part_id INTO v_refurb_id
        FROM   public.refurbished_part_links
        WHERE  original_part_id = v_part_id OR refurbished_part_id = v_part_id;

        IF v_refurb_id IS NULL THEN
            INSERT INTO public.parts (name, part_number, unit, quantity_in_stock)
            VALUES (v_part_name || ' (Refurbished)', v_part_number, v_part_unit, 0)
            RETURNING id INTO v_refurb_id;

            INSERT INTO public.refurbished_part_links (refurbished_part_id, original_part_id)
            VALUES (v_refurb_id, v_part_id);
        END IF;

        -- The insert trigger adds the stock at the invoice's workshop.
        INSERT INTO public.purchase_invoice_items (invoice_id, part_id, quantity, unit_price, gst_rate)
        VALUES (v_invoice_id, v_refurb_id, v_quantity, v_unit_price, COALESCE((v_line->>'gst_rate')::numeric, 0))
        RETURNING id INTO v_item_id;

        v_final_scrap := NULL;
        IF v_scrap_id IS NOT NULL THEN
            IF v_quantity = v_scrap.quantity_snapshot THEN
                UPDATE public.scrap_inventory
                SET    status = 'refurbished', updated_at = now(), updated_by = auth.uid()
                WHERE  id = v_scrap_id;

                v_final_scrap := v_scrap_id;
            ELSE
                -- The original row keeps the remainder, so a sale or write-off of it
                -- still takes a whole row.
                UPDATE public.scrap_inventory
                SET    quantity_snapshot = quantity_snapshot - v_quantity,
                       updated_at = now(), updated_by = auth.uid()
                WHERE  id = v_scrap_id;

                INSERT INTO public.scrap_inventory (
                    source_ticket_id, source_job_card_id, source_issue_id,
                    source_issue_part_id, source_vehicle_number, source_audit_reason_id,
                    part_id_snapshot, part_name_snapshot, part_number_snapshot,
                    quantity_snapshot, unit_snapshot, description, notes, photos, status,
                    received_by, received_at, current_location,
                    outsource_part_disposition_snapshot,
                    outsource_vendor_credit_amount_snapshot,
                    location_id, created_by, updated_by
                ) VALUES (
                    v_scrap.source_ticket_id, v_scrap.source_job_card_id, v_scrap.source_issue_id,
                    v_scrap.source_issue_part_id, v_scrap.source_vehicle_number, v_scrap.source_audit_reason_id,
                    v_scrap.part_id_snapshot, v_scrap.part_name_snapshot, v_scrap.part_number_snapshot,
                    v_quantity, v_scrap.unit_snapshot, v_scrap.description, v_scrap.notes, v_scrap.photos, 'refurbished',
                    v_scrap.received_by, v_scrap.received_at, v_scrap.current_location,
                    v_scrap.outsource_part_disposition_snapshot,
                    v_scrap.outsource_vendor_credit_amount_snapshot,
                    v_scrap.location_id, v_scrap.created_by, auth.uid()
                )
                RETURNING id INTO v_final_scrap;

                -- The insert trigger re-derives the workshop from the job card.
                UPDATE public.scrap_inventory
                SET    location_id = v_scrap.location_id
                WHERE  id = v_final_scrap;
            END IF;
        END IF;

        INSERT INTO public.scrap_refurbishments (
            purchase_invoice_item_id, scrap_inventory_id, original_part_id,
            refurbished_part_id, quantity, comment, created_by
        ) VALUES (
            v_item_id, v_final_scrap, v_part_id, v_refurb_id, v_quantity, v_comment, auth.uid()
        );
    END LOOP;

    PERFORM set_config('app.recording_refurbishment', 'off', true);

    SELECT COALESCE(sum(line_total), 0) INTO v_total
    FROM   public.purchase_invoice_items
    WHERE  invoice_id = v_invoice_id;

    -- Compared in numeric, as on a multi-vehicle invoice.
    IF v_total <> v_approved THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'AMOUNT_MISMATCH',
            'error_message', format('The parts add up to ₹%s; the approved amount is ₹%s.',
                                    to_char(v_total, 'FM999999999990.00'),
                                    to_char(v_approved, 'FM999999999990.00')),
            'details',       null
        )::text;
    END IF;

    UPDATE public.purchase_invoices SET total_amount = v_total WHERE id = v_invoice_id;

    PERFORM public.save_purchase_finance_invoice(v_invoice_id, p_invoice);

    RETURN v_invoice_id;
END;
$$;


-- MAIN-142: the Invoices page shows each invoice's type and filters by it.
-- One definition, so the list and the summary tiles cannot disagree. The owner is
-- whichever of job_card_id / batch_service_id / purchase_invoice_id is set
-- (outsource_invoices_one_owner_check); a purchase invoice's kind splits purchase
-- from refurbishment (MAIN-130).
CREATE OR REPLACE FUNCTION public.outsource_invoice_type(p_job_card_id uuid, p_batch_service_id uuid, p_purchase_kind text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select case
    when p_job_card_id      is not null then 'job_card'
    when p_batch_service_id is not null then 'multi_vehicle'
    when p_purchase_kind = 'refurbishment' then 'refurbishment'
    else 'purchase'
  end
$$;

-- Takes `type` (an array) in p_filters and returns invoice_type on each row.
CREATE OR REPLACE FUNCTION public.get_outsource_invoice_rows(p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with f as (
    select
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'maintenance_payment_status', 'null')) x) as ps,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'finance_payment_status', 'null')) x)     as fs,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'paid_by', 'null')) x)                    as pb,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'type', 'null')) x)                       as ty,
      nullif(p_filters->>'date_from', '')::date as date_from,
      nullif(p_filters->>'date_to', '')::date   as date_to,
      (p_filters->>'page')::int                 as page,
      coalesce((p_filters->>'page_size')::int, 50) as page_size
  ),
  visible as (
    select oi.*, jc.id as jc_id,
           public.outsource_invoice_type(oi.job_card_id, oi.batch_service_id, pi.kind) as invoice_type
    from   public.outsource_invoices oi
    left join public.job_cards jc on jc.id = oi.job_card_id and jc.status = 'Completed'
    left join public.purchase_invoices pi on pi.id = oi.purchase_invoice_id
    cross join f
    where (oi.batch_service_id is not null or oi.purchase_invoice_id is not null or jc.id is not null)
      and public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      and (f.ps is null        or oi.maintenance_payment_status = any (f.ps))
      and (f.fs is null        or oi.finance_payment_status     = any (f.fs))
      and (f.pb is null        or oi.paid_by                    = any (f.pb))
      and (f.ty is null        or public.outsource_invoice_type(oi.job_card_id, oi.batch_service_id, pi.kind) = any (f.ty))
      and (f.date_from is null or oi.date_of_activity >= f.date_from)
      and (f.date_to is null   or oi.date_of_activity <= f.date_to)
  ),
  page as (
    select v.*
    from   visible v
    -- Newest submitted first: finance's review queue (MAIN-119).
    order  by v.submitted_on desc nulls last, v.created_at desc, v.id
    offset (select coalesce(f.page * f.page_size, 0) from f)
    limit  (select case when f.page is null then null else f.page_size end from f)
  )
  select jsonb_build_object(
    'total', (select count(*) from visible),
    'rows',  coalesce(jsonb_agg(
      (to_jsonb(p) - 'jc_id') || jsonb_build_object(
        'job_card', (
          select jsonb_build_object(
                   'id', jc.id, 'job_card_number', jc.job_card_number,
                   'vehicle_number', jc.vehicle_number, 'status', jc.status,
                   'completed_at', jc.completed_at, 'invoice_url', jc.invoice_url,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = jc.supplier_id))
          from public.job_cards jc where jc.id = p.jc_id),
        'batch_service', (
          select jsonb_build_object(
                   'id', bs.id, 'batch_number', bs.batch_number, 'invoice_url', bs.invoice_url,
                   'status', bs.status, 'cancel_reason', bs.cancel_reason, 'cancelled_at', bs.cancelled_at,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = bs.supplier_id),
                   'vehicles', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'id', bsv.id, 'vehicle_number', bsv.vehicle_number, 'site', bsv.site,
                              'work_type', bsv.work_type, 'work_type_other', bsv.work_type_other,
                              'rate', bsv.rate, 'quantity', bsv.quantity, 'amount', bsv.amount,
                              'linked_job_card', (select jsonb_build_object('job_card_number', ljc.job_card_number)
                                                  from public.job_cards ljc where ljc.id = bsv.job_card_id))
                            order by bsv.vehicle_number, bsv.created_at), '[]'::jsonb)
                     from public.batch_service_vehicles bsv
                     where bsv.batch_service_id = bs.id))
          from public.batch_services bs where bs.id = p.batch_service_id),
        'purchase_invoice', (
          select jsonb_build_object(
                   'id', pi.id, 'kind', pi.kind, 'invoice_number', pi.invoice_number,
                   'invoice_file_url', pi.invoice_file_url, 'total_amount', pi.total_amount,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = pi.supplier_id))
          from public.purchase_invoices pi where pi.id = p.purchase_invoice_id)
      )
      order by p.submitted_on desc nulls last, p.created_at desc, p.id), '[]'::jsonb)
  )
  from page p
$$;


-- A new parameter can't be added with CREATE OR REPLACE (it would leave a second
-- overload), so DROP + CREATE, restating SECURITY DEFINER, search_path, owner and
-- the MAIN-127 grants: signed-in users only.
DROP FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[]);

CREATE FUNCTION public.get_outsource_invoice_summary(p_maintenance_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_finance_payment_status text[] DEFAULT NULL::text[], p_type text[] DEFAULT NULL::text[]) RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint, pending_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT
        COUNT(*) FILTER (WHERE oi.finance_payment_status IN ('New', 'Resubmitted')) AS new_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Hold')     AS hold_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Reject')   AS reject_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Accepted') AS accepted_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New (invoice pending)') AS pending_count
    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    LEFT JOIN purchase_invoices  pi ON pi.id = oi.purchase_invoice_id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed' OR oi.purchase_invoice_id IS NOT NULL)
      AND public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
      AND (p_type                       IS NULL OR public.outsource_invoice_type(oi.job_card_id, oi.batch_service_id, pi.kind) = ANY(p_type))
$$;

ALTER FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[]) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[]) TO authenticated;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[]) TO service_role;
