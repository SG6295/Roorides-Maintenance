-- MAIN-166: GST breakdown on job card and multi-vehicle invoices.
--
-- A job card or multi-vehicle invoice records its GST as rows in
-- outsource_invoices.gst_breakdown: [{rate, before_gst, gst, incl_gst}, ...], one row per
-- rate, adding up to the Invoice Value. Purchases and refurbishments keep their per-line
-- GST and never carry a breakdown. The column sits on the invoice row, so the Accepted /
-- Reject lock (guard_outsource_invoice_status_owners compares the whole row), the
-- prod->staging seed and the backups cover it with no change.

-- The GST rates the app offers, mirrored by GST_RATES in src/constants/gstRates.js.
CREATE OR REPLACE FUNCTION public.gst_rates() RETURNS numeric[]
    LANGUAGE sql IMMUTABLE
    AS $$ SELECT ARRAY[0, 5, 12, 18, 28, 40]::numeric[] $$;

COMMENT ON FUNCTION public.gst_rates() IS 'MAIN-166: the GST rates offered on invoices and purchase lines. Mirrored by GST_RATES in src/constants/gstRates.js.';

ALTER TABLE public.outsource_invoices ADD COLUMN gst_breakdown jsonb;

ALTER TABLE public.outsource_invoices
    ADD CONSTRAINT outsource_invoices_gst_breakdown_array_check
    CHECK (gst_breakdown IS NULL OR jsonb_typeof(gst_breakdown) = 'array');

COMMENT ON COLUMN public.outsource_invoices.gst_breakdown IS 'MAIN-166: a job card or multi-vehicle invoice''s GST, one row per rate: {rate, before_gst, gst, incl_gst}, adding up to the Invoice Value. Required on every save by guard_invoice_gst_breakdown; NULL on purchases (their GST is on their lines) and on job card invoices saved before MAIN-166.';

-- The bill's total GST, or NULL when there is no breakdown.
CREATE OR REPLACE FUNCTION public.gst_breakdown_total(p_rows jsonb) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE WHEN p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN NULL
                ELSE (SELECT coalesce(sum((r->>'gst')::numeric), 0) FROM jsonb_array_elements(p_rows) r) END
$$;

COMMENT ON FUNCTION public.gst_breakdown_total(jsonb) IS 'MAIN-166: the total GST of an invoice''s GST breakdown; NULL when it has none.';

-- What is wrong with a GST breakdown, or NULL. Mirrored by gstBreakdownProblem in
-- src/utils/gstBreakdown.js.
CREATE OR REPLACE FUNCTION public.gst_breakdown_problem(p_rows jsonb, p_invoice_value numeric) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public'
    AS $_$
DECLARE
    v_row    jsonb;
    v_rate   numeric;
    v_before numeric;
    v_gst    numeric;
    v_incl   numeric;
    v_sum    numeric := 0;
    v_rates  numeric[] := '{}';
    v_money  constant text := '^[0-9]{1,10}(\.[0-9]{1,2})?$';
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RETURN 'Add the GST breakdown.';
    END IF;

    FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        IF jsonb_typeof(v_row) <> 'object'
           OR coalesce(v_row->>'rate', '')       !~ v_money
           OR coalesce(v_row->>'before_gst', '') !~ v_money
           OR coalesce(v_row->>'gst', '')        !~ v_money
           OR coalesce(v_row->>'incl_gst', '')   !~ v_money THEN
            RETURN 'Every GST row needs a rate and its amounts.';
        END IF;

        v_rate   := (v_row->>'rate')::numeric;
        v_before := (v_row->>'before_gst')::numeric;
        v_gst    := (v_row->>'gst')::numeric;
        v_incl   := (v_row->>'incl_gst')::numeric;

        IF NOT v_rate = ANY (public.gst_rates()) THEN
            RETURN format('%s%% is not a GST rate.', trim_scale(v_rate));
        END IF;

        IF v_rate = ANY (v_rates) THEN
            RETURN 'Use one row per GST rate.';
        END IF;
        v_rates := v_rates || v_rate;

        IF v_incl <= 0 THEN
            RETURN 'Every GST row needs an amount.';
        END IF;

        IF v_before + v_gst <> v_incl THEN
            RETURN 'On each GST row, the amount before GST and the GST must add up to the amount incl. GST.';
        END IF;

        -- Within a paisa: the amount not typed is rounded to the paisa.
        IF abs(v_gst - v_before * v_rate / 100) > 0.01 THEN
            RETURN format('The GST on the %s%% row does not match its rate.', trim_scale(v_rate));
        END IF;

        v_sum := v_sum + v_incl;
    END LOOP;

    IF p_invoice_value IS NULL OR v_sum <> p_invoice_value THEN
        RETURN format('The GST rows add up to ₹%s but the Invoice Value is ₹%s.',
                      to_char(v_sum, 'FM999999999990.00'),
                      coalesce(to_char(p_invoice_value, 'FM999999999990.00'), '—'));
    END IF;

    RETURN NULL;
END;
$_$;

COMMENT ON FUNCTION public.gst_breakdown_problem(jsonb, numeric) IS 'MAIN-166: why a GST breakdown is invalid for an Invoice Value, or NULL. Mirrored by gstBreakdownProblem in src/utils/gstBreakdown.js.';

-- Every user write of a job card or multi-vehicle invoice carries a valid breakdown.
-- An old invoice without one passes until its details are changed, so finance's status
-- and remark never need it. Service-role writes (the prod->staging seed) pass.
CREATE OR REPLACE FUNCTION public.guard_invoice_gst_breakdown() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_problem text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.purchase_invoice_id IS NOT NULL THEN
        IF NEW.gst_breakdown IS NOT NULL THEN
            RAISE EXCEPTION 'A purchase''s GST is recorded on its lines, not as a GST breakdown.'
                USING HINT = 'GST_BREAKDOWN';
        END IF;
        RETURN NEW;
    END IF;

    IF NEW.gst_breakdown IS NOT NULL THEN
        v_problem := public.gst_breakdown_problem(NEW.gst_breakdown, NEW.invoice_value);
        IF v_problem IS NOT NULL THEN
            RAISE EXCEPTION '%', v_problem USING HINT = 'GST_BREAKDOWN';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT'
       OR OLD.gst_breakdown IS NOT NULL
       OR (NEW.invoice_no, NEW.date_of_activity, NEW.paid_by, NEW.invoice_value,
           NEW.approved_amount, NEW.advance_amount, NEW.maintenance_payment_status)
          IS DISTINCT FROM
          (OLD.invoice_no, OLD.date_of_activity, OLD.paid_by, OLD.invoice_value,
           OLD.approved_amount, OLD.advance_amount, OLD.maintenance_payment_status) THEN
        RAISE EXCEPTION 'Add the GST breakdown. Its rows must add up to the Invoice Value.'
            USING HINT = 'GST_BREAKDOWN';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_invoice_gst_breakdown() IS 'MAIN-166: a job card or multi-vehicle invoice is saved only with a valid GST breakdown; a purchase never carries one. An invoice from before MAIN-166 passes until its details change. Service-role writes pass.';

CREATE TRIGGER outsource_invoices_gst_breakdown
    BEFORE INSERT OR UPDATE ON public.outsource_invoices
    FOR EACH ROW EXECUTE FUNCTION public.guard_invoice_gst_breakdown();

-- Every change to the breakdown shows in the invoice history.
CREATE OR REPLACE FUNCTION public.log_outsource_invoice_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_fields  text[] := array[
        'maintenance_payment_status', 'finance_payment_status', 'finance_remark', 'paid_by',
        'invoice_value', 'approved_amount', 'advance_amount', 'payby_date', 'submitted_on', 'gst_breakdown'
    ];
    v_new     jsonb := to_jsonb(NEW);
    v_old     jsonb;
    v_changed text[];
BEGIN
    IF current_setting('app.invoice_resubmission', true) = 'on' THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs (table_name, record_id, action, new_data, performed_by)
        VALUES ('outsource_invoices', NEW.id, 'INSERT',
                (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_fields) f),
                auth.uid());
        RETURN NEW;
    END IF;

    v_old := to_jsonb(OLD);
    SELECT array_agg(f) INTO v_changed
    FROM   unnest(v_fields) f
    WHERE  v_new->f IS DISTINCT FROM v_old->f;

    IF v_changed IS NULL THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('outsource_invoices', NEW.id, 'UPDATE',
            (SELECT jsonb_object_agg(f, v_old->f) FROM unnest(v_changed) f),
            (SELECT jsonb_object_agg(f, v_new->f) FROM unnest(v_changed) f),
            v_changed,
            auth.uid());
    RETURN NEW;
END;
$function$;

-- A resubmission that only corrects the GST counts as a change.
CREATE OR REPLACE FUNCTION public.outsource_invoice_snapshot(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT jsonb_build_object(
        'date_of_activity',           oi.date_of_activity,
        'invoice_no',                 oi.invoice_no,
        'paid_by',                    oi.paid_by,
        'invoice_value',              oi.invoice_value,
        'approved_amount',            oi.approved_amount,
        'advance_amount',             oi.advance_amount,
        'gst_breakdown',              oi.gst_breakdown,
        'maintenance_payment_status', oi.maintenance_payment_status,
        'payby_date',                 oi.payby_date,
        'supplier_id',                coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id),
        'invoice_file',               coalesce(jc.invoice_url, bs.invoice_url, pi.invoice_file_url),
        -- A purchase's (MAIN-157) or multi-vehicle invoice's (MAIN-161) Billed to.
        'billed_to',                  coalesce(bs.billed_to, pi.billed_to),
        'lines', CASE
            WHEN bs.id IS NOT NULL THEN (
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'id', v.id, 'vehicle_number', v.vehicle_number, 'site', v.site,
                           'work_type', v.work_type, 'work_type_other', v.work_type_other,
                           'rate', v.rate, 'quantity', v.quantity, 'job_card_id', v.job_card_id)
                       ORDER BY v.id), '[]'::jsonb)
                FROM   public.batch_service_vehicles v
                WHERE  v.batch_service_id = bs.id)
            WHEN pi.id IS NOT NULL THEN (
                SELECT coalesce(jsonb_agg(jsonb_build_object(
                           'id', i.id, 'part_id', i.part_id, 'quantity', i.quantity,
                           'unit_price', i.unit_price, 'gst_rate', i.gst_rate,
                           'discount_amount', i.discount_amount)
                       ORDER BY i.id), '[]'::jsonb)
                FROM   public.purchase_invoice_items i
                WHERE  i.invoice_id = pi.id)
            END,
        'lines_total', CASE
            WHEN bs.id IS NOT NULL THEN (SELECT coalesce(sum(v.amount), 0) FROM public.batch_service_vehicles v WHERE v.batch_service_id = bs.id)
            WHEN pi.id IS NOT NULL THEN (SELECT coalesce(sum(i.line_total), 0) FROM public.purchase_invoice_items i WHERE i.invoice_id = pi.id)
            END
    )
    FROM   public.outsource_invoices oi
    LEFT JOIN public.job_cards         jc ON jc.id = oi.job_card_id
    LEFT JOIN public.batch_services    bs ON bs.id = oi.batch_service_id
    LEFT JOIN public.purchase_invoices pi ON pi.id = oi.purchase_invoice_id
    WHERE  oi.id = p_invoice_id
$function$;

CREATE OR REPLACE FUNCTION public.complete_invoice_resubmission(p_invoice_id uuid, p_before jsonb, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inv      public.outsource_invoices%ROWTYPE;
    v_after    jsonb;
    v_changed  text[];
    v_status   text;
    v_remark   text;
    v_today    date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_old_data jsonb;
    v_new_data jsonb;
BEGIN
    -- Only the resubmission functions raise the flag; called directly this does nothing.
    IF current_setting('app.invoice_resubmission', true) IS DISTINCT FROM 'on' THEN
        RAISE EXCEPTION 'Resubmit the invoice from its Resubmit button or its own page.'
            USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_inv FROM public.outsource_invoices WHERE id = p_invoice_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found.';
    END IF;

    IF v_inv.finance_payment_status IS DISTINCT FROM 'Reject' THEN
        RAISE EXCEPTION 'Only a rejected invoice can be resubmitted.';
    END IF;

    IF v_inv.maintenance_payment_status NOT IN ('Approved', 'Hold') THEN
        RAISE EXCEPTION 'Set the payment status reported by maintenance to Approved or Hold to resubmit.';
    END IF;

    v_after := public.outsource_invoice_snapshot(p_invoice_id);

    IF nullif(btrim(v_after->>'invoice_file'), '') IS NULL THEN
        RAISE EXCEPTION 'Upload the invoice file to resubmit.';
    END IF;

    -- MAIN-166: a job card or multi-vehicle invoice goes back to finance with its GST.
    IF v_inv.purchase_invoice_id IS NULL AND v_inv.gst_breakdown IS NULL THEN
        RAISE EXCEPTION 'Add the GST breakdown to resubmit.';
    END IF;

    -- Compared in numeric, as the save functions do.
    IF v_after->'lines' IS NOT NULL AND v_after->'lines' <> 'null'::jsonb
       AND (v_after->>'lines_total')::numeric <> v_inv.approved_amount THEN
        RAISE EXCEPTION 'The lines add up to ₹% but the approved amount is ₹%. Change the lines on the invoice''s own page.',
            to_char((v_after->>'lines_total')::numeric, 'FM999999999990.00'),
            to_char(v_inv.approved_amount, 'FM999999999990.00');
    END IF;

    SELECT array_agg(k ORDER BY k) INTO v_changed
    FROM   jsonb_object_keys(v_after) k
    WHERE  k <> 'lines_total'
      AND  v_after->k IS DISTINCT FROM p_before->k;

    IF v_changed IS NULL THEN
        RAISE EXCEPTION 'Nothing has changed. Replace the file or correct at least one detail before resubmitting.';
    END IF;

    -- As on first submission: maintenance's Hold starts finance at Hold.
    IF v_inv.maintenance_payment_status = 'Hold' THEN
        v_status := 'Hold';
        v_remark := 'Hold set by maintenance exec';
    ELSE
        v_status := 'Resubmitted';
        v_remark := NULL;
    END IF;

    UPDATE public.outsource_invoices
    SET    finance_payment_status = v_status,
           finance_remark         = v_remark,
           submitted_on           = v_today
    WHERE  id = p_invoice_id;

    -- One entry for the whole save. Lines are named, not copied: a batch's line changes
    -- are logged per line by log_batch_service_change, and the drawer folds them in.
    SELECT jsonb_object_agg(k, CASE WHEN k = 'lines' THEN NULL ELSE p_before->k END),
           jsonb_object_agg(k, CASE WHEN k = 'lines' THEN NULL ELSE v_after->k END)
    INTO   v_old_data, v_new_data
    FROM   unnest(v_changed) k;

    IF 'supplier_id' = ANY (v_changed) THEN
        v_old_data := v_old_data || jsonb_build_object('supplier_name',
            (SELECT entity_name FROM public.suppliers WHERE id = (p_before->>'supplier_id')::uuid));
        v_new_data := v_new_data || jsonb_build_object('supplier_name',
            (SELECT entity_name FROM public.suppliers WHERE id = (v_after->>'supplier_id')::uuid));
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('outsource_invoices', p_invoice_id, 'UPDATE',
            v_old_data || jsonb_build_object(
                'finance_payment_status', v_inv.finance_payment_status,
                'finance_remark',         v_inv.finance_remark,
                'submitted_on',           v_inv.submitted_on),
            v_new_data || jsonb_build_object(
                'finance_payment_status', v_status,
                'finance_remark',         v_remark,
                'submitted_on',           v_today,
                'resubmitted',            true,
                'note',                   nullif(btrim(p_note), '')),
            v_changed || array['finance_payment_status', 'finance_remark', 'submitted_on'],
            auth.uid());
END;
$function$;

-- The Resubmit popup sends the breakdown inside p_resubmission.
CREATE OR REPLACE FUNCTION public.resubmit_outsource_invoice(p_invoice_id uuid, p_resubmission jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           maintenance_payment_status = v_maint,
           -- MAIN-166: a purchase's GST stays on its lines.
           gst_breakdown              = CASE WHEN v_inv.purchase_invoice_id IS NULL
                                             THEN nullif(p_resubmission->'gst_breakdown', 'null'::jsonb)
                                             ELSE gst_breakdown END
    WHERE  id = p_invoice_id;

    PERFORM public.complete_invoice_resubmission(p_invoice_id, v_before, p_resubmission->>'note');

    PERFORM set_config('app.invoice_resubmission', 'off', true);
END;
$function$;

-- A multi-vehicle invoice carries its breakdown inside p_invoice (no new parameter).
CREATE OR REPLACE FUNCTION public.save_batch_service_invoice(p_batch_id uuid, p_batch jsonb, p_invoice jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_batch_id   uuid := p_batch_id;
    v_invoice_id uuid;
    v_status     text;
    v_approved   numeric;
    v_lines_sum  numeric;
    -- A rejected invoice changes only by being resubmitted (MAIN-120).
    v_resubmit   boolean := coalesce((p_invoice->>'resubmit')::boolean, false);
    v_before     jsonb;
    -- Who the invoice is billed to (MAIN-161); every vehicle on it belongs there.
    v_billed_to  text := nullif(p_batch->>'billed_to', '');
    v_was_billed text;
    v_vehicle    text;
    v_owner      text;
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
       OR nullif(p_invoice->'gst_breakdown', 'null'::jsonb) IS NULL
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_DETAILS_INCOMPLETE',
            'error_message', 'Fill in the vendor, every invoice field, the GST breakdown and the invoice file.'
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

    IF v_billed_to IS NULL OR v_billed_to NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BILLED_TO_REQUIRED',
            'error_message', 'Choose the company this invoice is billed to.'
        )::text;
    END IF;

    -- Every vehicle must belong to the company billed. A saved line keeps its vehicle's
    -- company at the time, so only new lines and lines whose vehicle changed are checked,
    -- and every line when Billed to itself changes — otherwise a vehicle sold after the
    -- work would make the invoice uneditable. An Unknown vehicle is left to
    -- guard_unassigned_vehicle, which refuses it with finance's message.
    SELECT billed_to INTO v_was_billed FROM public.batch_services WHERE id = p_batch_id;

    SELECT l->>'vehicle_number', v.company INTO v_vehicle, v_owner
    FROM   jsonb_array_elements(p_lines) l
    JOIN   public.vehicles v ON v.registration_number = l->>'vehicle_number'
    LEFT JOIN public.batch_service_vehicles s
           ON s.batch_service_id = p_batch_id
          AND s.id::text = l->>'id'
    WHERE  v.company NOT IN ('unknown', v_billed_to)
      AND  (v_was_billed IS DISTINCT FROM v_billed_to
            OR s.id IS NULL
            OR s.vehicle_number IS DISTINCT FROM l->>'vehicle_number')
    LIMIT  1;

    IF v_vehicle IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'COMPANY_MISMATCH',
            'error_message', format('%s belongs to %s, so it can''t go on an invoice billed to %s.',
                                    v_vehicle, public.stock_company_label(v_owner),
                                    public.stock_company_label(v_billed_to))
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

        INSERT INTO public.batch_services (supplier_id, invoice_url, billed_to)
        VALUES ((p_batch->>'supplier_id')::uuid, btrim(p_batch->>'invoice_url'), v_billed_to)
        RETURNING id INTO v_batch_id;

        INSERT INTO public.outsource_invoices
            (batch_service_id, date_of_activity, invoice_no, paid_by, invoice_value,
             approved_amount, advance_amount, maintenance_payment_status, gst_breakdown, created_by)
        VALUES (
            v_batch_id,
            (p_invoice->>'date_of_activity')::date,
            btrim(p_invoice->>'invoice_no'),
            p_invoice->>'paid_by',
            (p_invoice->>'invoice_value')::numeric,
            v_approved,
            (p_invoice->>'advance_amount')::numeric,
            p_invoice->>'maintenance_payment_status',
            nullif(p_invoice->'gst_breakdown', 'null'::jsonb),
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
               invoice_url = btrim(p_batch->>'invoice_url'),
               billed_to   = v_billed_to
        WHERE  id = v_batch_id;

        UPDATE public.outsource_invoices
        SET    date_of_activity           = (p_invoice->>'date_of_activity')::date,
               invoice_no                 = btrim(p_invoice->>'invoice_no'),
               paid_by                    = p_invoice->>'paid_by',
               invoice_value              = (p_invoice->>'invoice_value')::numeric,
               approved_amount            = v_approved,
               advance_amount             = (p_invoice->>'advance_amount')::numeric,
               maintenance_payment_status = p_invoice->>'maintenance_payment_status',
               gst_breakdown              = nullif(p_invoice->'gst_breakdown', 'null'::jsonb)
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
$function$;

-- Finalizing an Invoice Pending card needs the breakdown too.
CREATE OR REPLACE FUNCTION public.finalize_outsource_invoice(p_job_card_id uuid, p_remarks text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           OR v_invoice.gst_breakdown              IS NULL
        THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVOICE_DETAILS_INCOMPLETE',
                'error_message', 'Invoice details are incomplete. Please fill in all required fields, including the GST breakdown, before finalizing.',
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
$function$;

-- The company ledgers show these invoices' GST, scaled to the Approved Amount.
CREATE OR REPLACE FUNCTION public.company_ledger_lines(p_company text)
 RETURNS TABLE(entry_at timestamp with time zone, seq integer, line_id uuid, kind text, doc_date date, spend numeric, owed numeric, gst numeric, gst_status text, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- Purchases and refurbishments billed to the company.
  select coalesce(oi.accepted_at, oi.updated_at, pi.created_at at time zone 'UTC'),
         1, pi.id, pi.kind, pi.invoice_date,
         pi.total_amount, 0::numeric,
         g.gst,
         case when oi.id is null then 'unknown'
              when oi.finance_payment_status = 'GST reconciled & closed'     then 'claimed'
              when oi.finance_payment_status = 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'purchase_number', pi.purchase_number,
             'invoice_no',      pi.invoice_number,
             'supplier',        coalesce(s.entity_name, pi.supplier_name),
             'finance_status',  oi.finance_payment_status,
             'invoice_id',      oi.id)
  from   public.purchase_invoices pi
  left join public.outsource_invoices oi on oi.purchase_invoice_id = pi.id
  left join public.suppliers s on s.id = pi.supplier_id
  cross join lateral (
      select coalesce(sum(i.line_total - round(i.quantity * i.unit_price - i.discount_amount, 2)), 0) as gst
      from   public.purchase_invoice_items i
      where  i.invoice_id = pi.id) g
  where  pi.billed_to = p_company
    and  pi.purchase_number not in (176, 180, 183, 185)
    and  (oi.id is null
          or oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed'))

  union all

  -- Job card and multi-vehicle invoices of the company, once finance has accepted them.
  select coalesce(oi.accepted_at, oi.updated_at), 2, oi.id,
         case when oi.job_card_id is not null then 'job_card' else 'multi_vehicle' end,
         oi.date_of_activity,
         oi.approved_amount, 0::numeric,
         -- MAIN-166: the bill's GST, scaled to the Approved Amount; NULL ("Not recorded")
         -- for an invoice without a breakdown.
         round(public.gst_breakdown_total(oi.gst_breakdown) * oi.approved_amount
               / nullif(oi.invoice_value, 0), 2),
         case oi.finance_payment_status
              when 'GST reconciled & closed'     then 'claimed'
              when 'GST not applicable & closed' then 'no_gst'
              else 'not_reconciled' end,
         jsonb_build_object(
             'invoice_no',      oi.invoice_no,
             'supplier',        s.entity_name,
             'finance_status',  oi.finance_payment_status,
             'job_card_number', jc.job_card_number,
             'vehicle',         jc.vehicle_number,
             'batch_number',    bs.batch_number,
             'vehicle_count',   (select count(distinct v.vehicle_number)
                                 from public.batch_service_vehicles v
                                 where v.batch_service_id = bs.id))
  from   public.outsource_invoices oi
  left join public.job_cards      jc on jc.id = oi.job_card_id
  left join public.batch_services bs on bs.id = oi.batch_service_id
  left join public.suppliers      s  on s.id  = coalesce(jc.supplier_id, bs.supplier_id)
  where  oi.company = p_company
    and  oi.purchase_invoice_id is null
    and  oi.finance_payment_status in ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
    and  (bs.id is null or bs.status = 'Active')

  union all

  -- Vehicles sold between the companies: in both ledgers, opposite ways round.
  select c.created_at, 3, c.id,
         case when c.old_company = p_company then 'vehicle_sold' else 'vehicle_bought' end,
         (c.created_at at time zone 'Asia/Kolkata')::date,
         0::numeric,
         case when c.old_company = p_company then c.sale_value else -c.sale_value end,
         round(c.sale_value * c.gst_percent / (100 + c.gst_percent), 2),
         'inter_company',
         jsonb_build_object(
             'vehicle',      c.registration_number,
             'other_company', case when c.old_company = p_company then c.new_company else c.old_company end,
             'gst_percent',  c.gst_percent,
             'performed_by', c.performed_by_name)
  from   public.vehicle_company_changes c
  where  c.kind = 'sale'
    and  p_company in (c.old_company, c.new_company)
$function$;

-- The Invoices page's GST column.
CREATE OR REPLACE FUNCTION public.get_outsource_invoice_rows(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with f as (
    select
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'maintenance_payment_status', 'null')) x) as ps,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'finance_payment_status', 'null')) x)     as fs,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'paid_by', 'null')) x)                    as pb,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'type', 'null')) x)                       as ty,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'company', 'null')) x)                    as co,
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
      and (f.co is null        or oi.company                    = any (f.co))
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
        -- MAIN-166: the bill's GST — a purchase's from its lines, otherwise its breakdown.
        'gst', case when p.purchase_invoice_id is not null
                    then (select sum(i.line_total - round(i.quantity * i.unit_price - i.discount_amount, 2))
                          from public.purchase_invoice_items i where i.invoice_id = p.purchase_invoice_id)
                    else public.gst_breakdown_total(p.gst_breakdown) end,
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
                   'id', pi.id, 'purchase_number', pi.purchase_number,
                   'kind', pi.kind, 'invoice_number', pi.invoice_number,
                   'invoice_file_url', pi.invoice_file_url, 'total_amount', pi.total_amount,
                   'supplier', (select jsonb_build_object('id', s.id, 'entity_name', s.entity_name)
                                from public.suppliers s where s.id = pi.supplier_id))
          from public.purchase_invoices pi where pi.id = p.purchase_invoice_id)
      )
      order by p.submitted_on desc nulls last, p.created_at desc, p.id), '[]'::jsonb)
  )
  from page p
$function$;
