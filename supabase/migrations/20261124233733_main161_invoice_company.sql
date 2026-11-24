-- MAIN-161 (epic MAIN-154): "Billed to" and a company column on invoices.
--
-- Every invoice that reaches finance now stores the company it belongs to:
--   * a purchase or refurbishment invoice — its Billed to (MAIN-157);
--   * a multi-vehicle invoice — its new, required Billed to; every vehicle on it must
--     belong to that company;
--   * a job card invoice — the company its vehicle had when the job card was opened.
-- Every invoice from before this reads NVS Travels, and stays NVS Travels even if its
-- vehicle is later assigned to Pvt Ltd (user decision, 2026-11-25): NVS Travels paid
-- those suppliers.
--
-- The Invoices page gets a Company column and filter, which the summary tiles follow.

-- ─── Columns ─────────────────────────────────────────────────────────────────────────

ALTER TABLE public.batch_services
    ADD COLUMN billed_to text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT batch_services_billed_to_check CHECK (billed_to IN ('nvs_travels', 'nvs_travel_solutions'));
COMMENT ON COLUMN public.batch_services.billed_to IS
    'The company this multi-vehicle invoice is billed to (MAIN-161). Every vehicle on it belongs to this company. Invoices from before then are NVS Travels.';

ALTER TABLE public.outsource_invoices
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT outsource_invoices_company_check CHECK (company IN ('nvs_travels', 'nvs_travel_solutions'));
COMMENT ON COLUMN public.outsource_invoices.company IS
    'The company this invoice belongs to (MAIN-161), set by outsource_invoices_set_company: a purchase''s or multi-vehicle invoice''s Billed to, or the company a job card''s vehicle had when the card was opened. Never set by hand. Invoices from before then are NVS Travels.';

-- A purchase already billed to Pvt Ltd (staging only; prod has none) takes its Billed to.
-- Run as postgres, so auth.uid() is NULL and the invoice guards let it through.
UPDATE public.outsource_invoices oi
SET    company = pi.billed_to
FROM   public.purchase_invoices pi
WHERE  pi.id = oi.purchase_invoice_id
  AND  oi.company IS DISTINCT FROM pi.billed_to;

-- ─── Which company an invoice belongs to ─────────────────────────────────────────────

-- The company a job card's vehicle had when the card was opened: the latest entry in the
-- vehicle's company history at or before that moment. A card opened before the vehicle
-- had any (before the Vehicle Registration Master, MAIN-155) is NVS Travels, like every
-- record from then. A vehicle can't change company while a card is open, so this is also
-- its company when the work was done, even if it was sold before the invoice came in.
CREATE OR REPLACE FUNCTION public.job_card_invoice_company(p_job_card_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT coalesce((
        SELECT c.new_company
        FROM   public.job_cards jc
        JOIN   public.vehicles v                 ON v.registration_number = jc.vehicle_number
        JOIN   public.vehicle_company_changes c  ON c.vehicle_id = v.id
        WHERE  jc.id = p_job_card_id
          AND  c.created_at <= jc.created_at
        ORDER  BY c.created_at DESC
        LIMIT  1
    ), 'nvs_travels')
$$;

REVOKE ALL ON FUNCTION public.job_card_invoice_company(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.job_card_invoice_company(uuid) TO authenticated, service_role;

-- Sets outsource_invoices.company on every write, so nobody sets it by hand. A purchase
-- or multi-vehicle invoice follows its owner's Billed to; a job card invoice keeps the
-- company it was given when it was created. The prod→staging seed writes with triggers
-- off (session_replication_role = replica), so it keeps prod's values.
CREATE OR REPLACE FUNCTION public.set_outsource_invoice_company()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.purchase_invoice_id IS NOT NULL THEN
        SELECT billed_to INTO NEW.company FROM public.purchase_invoices WHERE id = NEW.purchase_invoice_id;
    ELSIF NEW.batch_service_id IS NOT NULL THEN
        SELECT billed_to INTO NEW.company FROM public.batch_services WHERE id = NEW.batch_service_id;
    ELSIF TG_OP = 'INSERT' OR NEW.job_card_id IS DISTINCT FROM OLD.job_card_id THEN
        NEW.company := public.job_card_invoice_company(NEW.job_card_id);
    ELSE
        NEW.company := OLD.company;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER outsource_invoices_set_company
    BEFORE INSERT OR UPDATE ON public.outsource_invoices
    FOR EACH ROW EXECUTE FUNCTION public.set_outsource_invoice_company();

-- When a purchase's or multi-vehicle invoice's Billed to changes, its invoice follows.
-- Both are refused by their own guards while finance has the invoice Accepted or
-- Rejected, except during a resubmission, which the invoice guard lets through too.
CREATE OR REPLACE FUNCTION public.sync_invoice_company_from_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_TABLE_NAME = 'purchase_invoices' THEN
        UPDATE public.outsource_invoices SET company = NEW.billed_to
        WHERE  purchase_invoice_id = NEW.id AND company IS DISTINCT FROM NEW.billed_to;
    ELSE
        UPDATE public.outsource_invoices SET company = NEW.billed_to
        WHERE  batch_service_id = NEW.id AND company IS DISTINCT FROM NEW.billed_to;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER purchase_invoices_sync_invoice_company
    AFTER UPDATE OF billed_to ON public.purchase_invoices
    FOR EACH ROW WHEN (OLD.billed_to IS DISTINCT FROM NEW.billed_to)
    EXECUTE FUNCTION public.sync_invoice_company_from_owner();

CREATE TRIGGER batch_services_sync_invoice_company
    AFTER UPDATE OF billed_to ON public.batch_services
    FOR EACH ROW WHEN (OLD.billed_to IS DISTINCT FROM NEW.billed_to)
    EXECUTE FUNCTION public.sync_invoice_company_from_owner();

-- ─── Resubmission compares a batch's Billed to too ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.outsource_invoice_snapshot(p_invoice_id uuid) RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT jsonb_build_object(
        'date_of_activity',           oi.date_of_activity,
        'invoice_no',                 oi.invoice_no,
        'paid_by',                    oi.paid_by,
        'invoice_value',              oi.invoice_value,
        'approved_amount',            oi.approved_amount,
        'advance_amount',             oi.advance_amount,
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
$$;

-- ─── A multi-vehicle invoice's Billed to is in its history ───────────────────────────

CREATE OR REPLACE FUNCTION public.log_batch_service_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_fields  text[];
    v_new     jsonb;
    v_old     jsonb;
    v_changed text[];
    v_logged  text[];
    v_batch   uuid;
BEGIN
    IF TG_TABLE_NAME = 'batch_services' THEN
        IF current_setting('app.invoice_resubmission', true) = 'on' THEN
            RETURN NEW;
        END IF;
        v_fields := array['supplier_id', 'invoice_url', 'billed_to', 'status', 'cancel_reason'];
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

-- ─── Saving a multi-vehicle invoice ──────────────────────────────────────────────────

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

-- ─── The Invoices list and tiles filter by company ───────────────────────────────────

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
$$;

DROP FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[]);

CREATE FUNCTION public.get_outsource_invoice_summary(
    p_maintenance_payment_status text[] DEFAULT NULL,
    p_paid_by                    text[] DEFAULT NULL,
    p_date_from                  date   DEFAULT NULL,
    p_date_to                    date   DEFAULT NULL,
    p_finance_payment_status     text[] DEFAULT NULL,
    p_type                       text[] DEFAULT NULL,
    p_company                    text[] DEFAULT NULL
) RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint, pending_count bigint)
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
      AND (p_company                    IS NULL OR oi.company = ANY(p_company))
$$;

REVOKE ALL ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[], text[], text[]) TO authenticated, service_role;
