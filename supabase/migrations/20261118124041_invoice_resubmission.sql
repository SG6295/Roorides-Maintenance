-- MAIN-120: a rejected outsource invoice is corrected and resubmitted.
--
-- Reject stays final for finance's status; the only way out is resubmission by a
-- maintenance exec or super_admin, which lands the invoice at Resubmitted (or Hold, when
-- maintenance reports Hold) with a fresh submission date. A rejected invoice is locked
-- like an accepted one, and resubmission is the only way through that lock.
--
-- Two entry points share one finishing step:
--   * resubmit_outsource_invoice(p_invoice_id, p_resubmission jsonb) — the Resubmit
--     popup, for every kind of invoice: the file, the supplier and the invoice fields.
--   * save_batch_service_invoice / save_purchase_invoice with `resubmit: true` (and an
--     optional `resubmit_note`) inside p_invoice — line changes, on the invoice's own
--     page. No new parameter: under CREATE OR REPLACE that would add an overload.
-- Both raise the transaction-local app.invoice_resubmission flag, which the guards let
-- through (as app.finance_submission is), and end in complete_invoice_resubmission.
--
-- The lock is also enforced on the tables that hold an invoice's other details — the
-- job card's file and supplier, a purchase invoice's header and lines — so a direct API
-- write cannot change a rejected, accepted or GST-closed invoice either. A batch's tables
-- have no client write policies; save_batch_service_invoice holds the rule there.

-- ── Resubmitted ─────────────────────────────────────────────────────────────

ALTER TABLE public.outsource_invoices DROP CONSTRAINT outsource_invoices_finance_payment_status_check;
ALTER TABLE public.outsource_invoices ADD CONSTRAINT outsource_invoices_finance_payment_status_check
    CHECK (finance_payment_status = ANY (ARRAY[
        'New', 'New (invoice pending)', 'Resubmitted', 'Hold', 'Reject', 'Accepted',
        'GST reconciled & closed', 'GST not applicable & closed'
    ]));

-- ── What one invoice is, for "did the resubmission change anything" ──────────

-- Invoker: called inside the save and resubmit functions, by an exec or as their owner.
CREATE FUNCTION public.outsource_invoice_snapshot(p_invoice_id uuid) RETURNS jsonb
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

REVOKE EXECUTE ON FUNCTION public.outsource_invoice_snapshot(uuid) FROM PUBLIC, anon;

-- ── The finishing step every resubmission ends in ───────────────────────────

-- Runs after the edit, with the flag raised. Refuses unless the result is a resubmittable
-- invoice that differs from p_before, then sets the starting status as first submission
-- does and writes the one history entry finance reads.
CREATE FUNCTION public.complete_invoice_resubmission(p_invoice_id uuid, p_before jsonb, p_note text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;

REVOKE EXECUTE ON FUNCTION public.complete_invoice_resubmission(uuid, jsonb, text) FROM PUBLIC, anon;

-- ── The Resubmit popup ───────────────────────────────────────────────────────

-- p_resubmission: supplier_id, invoice_file_url, the invoice fields as columns
-- (invoiceFormToRow), and an optional note. A purchase invoice takes its number and date
-- from these too, so the two cannot drift. Its lines, and a batch's, change only on
-- their own page.
CREATE FUNCTION public.resubmit_outsource_invoice(p_invoice_id uuid, p_resubmission jsonb) RETURNS void
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
    v_payby     date    := nullif(p_resubmission->>'payby_date', '')::date;
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
       OR v_advance   IS NULL OR v_advance  > v_approved
       OR v_payby     IS NULL OR v_payby < v_date THEN
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
           payby_date                 = v_payby
    WHERE  id = p_invoice_id;

    PERFORM public.complete_invoice_resubmission(p_invoice_id, v_before, p_resubmission->>'note');

    PERFORM set_config('app.invoice_resubmission', 'off', true);
END;
$_$;

REVOKE EXECUTE ON FUNCTION public.resubmit_outsource_invoice(uuid, jsonb) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.resubmit_outsource_invoice(uuid, jsonb) TO authenticated;

-- ── The status guard: Reject joins the lock; Resubmitted moves as New ────────

CREATE OR REPLACE FUNCTION public.guard_outsource_invoice_status_owners() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_role                text;
    v_finance_changed     boolean;
    v_maintenance_changed boolean;
    v_old                 text;
    v_new                 text;
    v_no_file             boolean;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF current_setting('app.finance_submission', true) = 'on'
       OR current_setting('app.invoice_resubmission', true) = 'on' THEN
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

    IF OLD.finance_payment_status IN ('Reject', 'Accepted', 'GST reconciled & closed', 'GST not applicable & closed')
       AND (to_jsonb(NEW) - array['finance_payment_status', 'finance_remark', 'updated_at'])
           IS DISTINCT FROM
           (to_jsonb(OLD) - array['finance_payment_status', 'finance_remark', 'updated_at']) THEN
        IF OLD.finance_payment_status = 'Reject' THEN
            RAISE EXCEPTION 'Finance has rejected this invoice. Resubmit it to change its details.'
                USING ERRCODE = '42501';
        END IF;
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
                OR (v_old = 'Resubmitted'    AND v_new IN ('Hold', 'Reject', 'Accepted'))
                OR (v_old IN ('New (invoice pending)', 'Hold') AND v_new IN ('New (invoice pending)', 'Hold', 'Reject'))
                OR (v_old = 'Accepted'       AND v_new IN ('Hold', 'Reject', 'GST reconciled & closed', 'GST not applicable & closed'))) THEN
            RAISE EXCEPTION 'Finance status cannot move from % to %.', v_old, v_new;
        END IF;

        v_no_file := public.purchase_invoice_file_missing(NEW.purchase_invoice_id);

        IF v_no_file AND v_new = 'Accepted' THEN
            RAISE EXCEPTION 'The invoice file has not been uploaded yet, so this invoice cannot be accepted.';
        END IF;

        IF v_no_file AND v_new = 'New' THEN
            RAISE EXCEPTION 'The invoice file has not been uploaded yet, so this invoice goes back to New (invoice pending).';
        END IF;

        IF NOT v_no_file AND v_new = 'New (invoice pending)' THEN
            RAISE EXCEPTION 'This invoice has its file, so it is not pending.';
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

-- ── The same lock on the tables holding the invoice's other details ─────────

CREATE FUNCTION public.guard_locked_invoice_details() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_status text;
BEGIN
    -- Service-role writes (the prod→staging seed) and resubmissions pass.
    IF auth.uid() IS NULL OR current_setting('app.invoice_resubmission', true) = 'on' THEN
        RETURN coalesce(NEW, OLD);
    END IF;

    IF TG_TABLE_NAME = 'job_cards' THEN
        IF (NEW.invoice_url, NEW.supplier_id) IS NOT DISTINCT FROM (OLD.invoice_url, OLD.supplier_id) THEN
            RETURN NEW;
        END IF;
        SELECT finance_payment_status INTO v_status
        FROM   public.outsource_invoices WHERE job_card_id = NEW.id;

    ELSIF TG_TABLE_NAME = 'purchase_invoices' THEN
        -- The notes stay editable, as under the Accepted lock (MAIN-129).
        IF (to_jsonb(NEW) - 'notes') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'notes') THEN
            RETURN NEW;
        END IF;
        SELECT finance_payment_status INTO v_status
        FROM   public.outsource_invoices WHERE purchase_invoice_id = NEW.id;

    ELSE  -- purchase_invoice_items
        -- save_purchase_invoice rewrites every kept line; an unchanged one passes.
        IF TG_OP = 'UPDATE'
           AND (NEW.invoice_id, NEW.part_id, NEW.quantity, NEW.unit_price, NEW.gst_rate, NEW.discount_amount)
               IS NOT DISTINCT FROM
               (OLD.invoice_id, OLD.part_id, OLD.quantity, OLD.unit_price, OLD.gst_rate, OLD.discount_amount) THEN
            RETURN NEW;
        END IF;
        SELECT finance_payment_status INTO v_status
        FROM   public.outsource_invoices
        WHERE  purchase_invoice_id = coalesce(NEW.invoice_id, OLD.invoice_id);
    END IF;

    IF v_status = 'Reject' THEN
        RAISE EXCEPTION 'Finance has rejected this invoice. Resubmit it to change its details.'
            USING ERRCODE = '42501';
    END IF;

    IF v_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
        RAISE EXCEPTION 'Finance has accepted this invoice, so its details can no longer be changed.'
            USING ERRCODE = '42501';
    END IF;

    RETURN coalesce(NEW, OLD);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.guard_locked_invoice_details() FROM PUBLIC, anon;

CREATE TRIGGER trigger_guard_locked_invoice_job_card
    BEFORE UPDATE OF invoice_url, supplier_id ON public.job_cards
    FOR EACH ROW EXECUTE FUNCTION public.guard_locked_invoice_details();

CREATE TRIGGER trigger_guard_locked_invoice_header
    BEFORE UPDATE ON public.purchase_invoices
    FOR EACH ROW EXECUTE FUNCTION public.guard_locked_invoice_details();

CREATE TRIGGER trigger_guard_locked_invoice_line
    BEFORE INSERT OR UPDATE OR DELETE ON public.purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.guard_locked_invoice_details();

-- ── History: a resubmission is one entry ─────────────────────────────────────

-- complete_invoice_resubmission writes the resubmission's single entry, so the per-row
-- entries are skipped while the flag is up.
CREATE OR REPLACE FUNCTION public.log_outsource_invoice_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_fields  text[] := array[
        'maintenance_payment_status', 'finance_payment_status', 'finance_remark', 'paid_by',
        'invoice_value', 'approved_amount', 'advance_amount', 'payby_date', 'submitted_on'
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
$$;

-- A batch's vendor and file changed by a resubmission are in its entry; its line
-- changes are still logged here, and the drawer folds them into that entry.
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

-- ── Line changes resubmit on the invoice's own page ──────────────────────────

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

    IF v_resubmit THEN
        PERFORM public.complete_invoice_resubmission(v_invoice_id, v_before, p_invoice->>'resubmit_note');
        PERFORM set_config('app.invoice_resubmission', 'off', true);
    END IF;

    RETURN v_batch_id;
END;
$_$;

CREATE OR REPLACE FUNCTION public.save_purchase_invoice(p_invoice_id uuid, p_invoice jsonb, p_items jsonb) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_invoice_id    uuid := p_invoice_id;
    v_item          jsonb;
    v_supplier_id   uuid := nullif(p_invoice->>'supplier_id', '')::uuid;
    v_supplier_name text;
    v_file          text := nullif(p_invoice->>'invoice_file_url', '');
    v_old           public.purchase_invoices%ROWTYPE;
    v_status        text;
    v_has_finance   boolean := false;
    v_finance_id    uuid;
    -- A rejected invoice changes only by being resubmitted (MAIN-120); the table guards
    -- refuse any other change but the notes.
    v_resubmit      boolean := coalesce((p_invoice->>'resubmit')::boolean, false);
    v_before        jsonb;
BEGIN
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION 'Only maintenance executives can record or edit a purchase invoice.'
            USING ERRCODE = '42501';
    END IF;

    IF v_invoice_id IS NOT NULL THEN
        SELECT * INTO v_old
        FROM   public.purchase_invoices
        WHERE  id = v_invoice_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invoice not found.';
        END IF;

        -- Locked first, so finance cannot accept it in the middle of the save.
        SELECT id, finance_payment_status INTO v_finance_id, v_status
        FROM   public.outsource_invoices
        WHERE  purchase_invoice_id = v_invoice_id
        FOR UPDATE;
        v_has_finance := FOUND;
    END IF;

    IF v_resubmit AND v_status IS DISTINCT FROM 'Reject' THEN
        RAISE EXCEPTION 'Only a rejected invoice can be resubmitted.';
    END IF;

    IF v_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
        IF (p_invoice->>'invoice_number', (p_invoice->>'invoice_date')::date, v_file,
            (p_invoice->>'location_id')::uuid, coalesce(v_supplier_id, v_old.supplier_id))
           IS DISTINCT FROM
           (v_old.invoice_number, v_old.invoice_date, v_old.invoice_file_url,
            v_old.location_id, v_old.supplier_id)
           OR EXISTS (
               SELECT id, part_id, quantity, unit_price, gst_rate, discount_amount
               FROM   public.purchase_invoice_items
               WHERE  invoice_id = v_invoice_id
               EXCEPT
               SELECT (i->>'id')::uuid, (i->>'part_id')::uuid, (i->>'quantity')::numeric,
                      (i->>'unit_price')::numeric, coalesce((i->>'gst_rate')::numeric, 0),
                      coalesce((i->>'discount_amount')::numeric, 0)
               FROM   jsonb_array_elements(p_items) i
           )
           OR EXISTS (
               SELECT (i->>'id')::uuid, (i->>'part_id')::uuid, (i->>'quantity')::numeric,
                      (i->>'unit_price')::numeric, coalesce((i->>'gst_rate')::numeric, 0),
                      coalesce((i->>'discount_amount')::numeric, 0)
               FROM   jsonb_array_elements(p_items) i
               EXCEPT
               SELECT id, part_id, quantity, unit_price, gst_rate, discount_amount
               FROM   public.purchase_invoice_items
               WHERE  invoice_id = v_invoice_id
           ) THEN
            RAISE EXCEPTION 'Finance has accepted this invoice, so only its notes can be changed.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_has_finance AND v_old.invoice_file_url IS NOT NULL AND v_file IS NULL THEN
        RAISE EXCEPTION 'The invoice file cannot be removed once attached. Replace it instead.';
    END IF;

    IF v_supplier_id IS NULL THEN
        IF v_invoice_id IS NULL OR v_old.supplier_id IS NOT NULL THEN
            RAISE EXCEPTION 'Choose the supplier, or add them.';
        END IF;
        v_supplier_name := v_old.supplier_name;
    ELSIF v_supplier_id IS NOT DISTINCT FROM v_old.supplier_id THEN
        v_supplier_name := v_old.supplier_name;
    ELSE
        SELECT entity_name INTO v_supplier_name
        FROM   public.suppliers
        WHERE  id = v_supplier_id AND status = 'approved';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Choose an approved supplier.';
        END IF;
    END IF;

    IF v_resubmit THEN
        v_before := public.outsource_invoice_snapshot(v_finance_id);
        PERFORM set_config('app.invoice_resubmission', 'on', true);
    END IF;

    IF v_invoice_id IS NULL THEN
        INSERT INTO public.purchase_invoices
            (invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, created_by)
        VALUES (
            p_invoice->>'invoice_number',
            v_supplier_id,
            v_supplier_name,
            (p_invoice->>'invoice_date')::date,
            nullif(p_invoice->>'notes', ''),
            v_file,
            (p_invoice->>'location_id')::uuid,
            auth.uid()
        )
        RETURNING id INTO v_invoice_id;
    ELSE
        UPDATE public.purchase_invoices
        SET    invoice_number   = p_invoice->>'invoice_number',
               supplier_id      = v_supplier_id,
               supplier_name    = v_supplier_name,
               invoice_date     = (p_invoice->>'invoice_date')::date,
               notes            = nullif(p_invoice->>'notes', ''),
               invoice_file_url = v_file,
               location_id      = (p_invoice->>'location_id')::uuid
        WHERE  id = v_invoice_id;

        DELETE FROM public.purchase_invoice_items
        WHERE  invoice_id = v_invoice_id
          AND  id NOT IN (
                   SELECT (i->>'id')::uuid
                   FROM   jsonb_array_elements(p_items) i
                   WHERE  i->>'id' IS NOT NULL
               );
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        IF v_item->>'id' IS NOT NULL AND p_invoice_id IS NOT NULL THEN
            UPDATE public.purchase_invoice_items
            SET    quantity        = (v_item->>'quantity')::numeric,
                   unit_price      = (v_item->>'unit_price')::numeric,
                   gst_rate        = coalesce((v_item->>'gst_rate')::numeric, 0),
                   discount_amount = coalesce((v_item->>'discount_amount')::numeric, 0)
            WHERE  id = (v_item->>'id')::uuid
              AND  invoice_id = v_invoice_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Line item does not belong to this invoice.';
            END IF;
        ELSE
            INSERT INTO public.purchase_invoice_items
                (invoice_id, part_id, quantity, unit_price, gst_rate, discount_amount)
            VALUES (
                v_invoice_id,
                (v_item->>'part_id')::uuid,
                (v_item->>'quantity')::numeric,
                (v_item->>'unit_price')::numeric,
                coalesce((v_item->>'gst_rate')::numeric, 0),
                coalesce((v_item->>'discount_amount')::numeric, 0)
            );
        END IF;
    END LOOP;

    UPDATE public.purchase_invoices
    SET    total_amount = (
               SELECT coalesce(sum(line_total), 0)
               FROM   public.purchase_invoice_items
               WHERE  invoice_id = v_invoice_id
           )
    WHERE  id = v_invoice_id;

    IF p_invoice_id IS NULL OR v_has_finance THEN
        PERFORM public.save_purchase_finance_invoice(v_invoice_id, p_invoice);
    END IF;

    IF v_resubmit THEN
        PERFORM public.complete_invoice_resubmission(v_finance_id, v_before, p_invoice->>'resubmit_note');
        PERFORM set_config('app.invoice_resubmission', 'off', true);
    END IF;

    RETURN v_invoice_id;
END;
$$;

-- ── Counts: Resubmitted waits with New ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_outsource_invoice_summary(p_maintenance_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_finance_payment_status text[] DEFAULT NULL::text[]) RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint, pending_count bigint)
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
    WHERE (bs.status = 'Active' OR jc.status = 'Completed' OR oi.purchase_invoice_id IS NOT NULL)
      AND public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

CREATE OR REPLACE FUNCTION public.get_supplier_balances(p_supplier_id uuid DEFAULT NULL::uuid) RETURNS TABLE(supplier_id uuid, entity_name text, credit_days integer, outstanding numeric, overdue numeric, due_this_wednesday numeric, due_next_wednesday numeric, later numeric, this_wednesday date, last_payment_on date, last_reconciled_on date, awaiting_acceptance bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
        SELECT coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id) AS sid, count(*) AS n
        FROM   public.outsource_invoices oi
        LEFT JOIN public.job_cards         jc ON jc.id = oi.job_card_id
        LEFT JOIN public.batch_services    bs ON bs.id = oi.batch_service_id
        LEFT JOIN public.purchase_invoices pi ON pi.id = oi.purchase_invoice_id
        WHERE  oi.submitted_on IS NOT NULL
          AND  oi.finance_payment_status IN ('New', 'New (invoice pending)', 'Resubmitted', 'Hold')
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
            WHERE a.supplier_id = s.id AND a.status = 'Active'),
           coalesce(pending.n, 0)
    FROM   public.suppliers s
    LEFT JOIN bal        ON bal.sid     = s.id
    LEFT JOIN open_items oi ON oi.sid   = s.id
    LEFT JOIN pending    ON pending.sid = s.id
    WHERE  (p_supplier_id IS NULL OR s.id = p_supplier_id)
      AND  (s.status = 'approved' OR bal.sid IS NOT NULL OR pending.sid IS NOT NULL)
    ORDER  BY s.entity_name;
END;
$$;

-- ── The list: what the Resubmit popup needs ──────────────────────────────────

-- Adds each owner's supplier id (already there) and a purchase's lines total, so the
-- popup can tell before saving that the lines no longer match the Approved Amount.
CREATE OR REPLACE FUNCTION public.get_outsource_invoice_rows(p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  with f as (
    select
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'maintenance_payment_status', 'null')) x) as ps,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'finance_payment_status', 'null')) x)     as fs,
      (select array_agg(x) from jsonb_array_elements_text(nullif(p_filters->'paid_by', 'null')) x)                    as pb,
      nullif(p_filters->>'date_from', '')::date as date_from,
      nullif(p_filters->>'date_to', '')::date   as date_to,
      (p_filters->>'page')::int                 as page,
      coalesce((p_filters->>'page_size')::int, 50) as page_size
  ),
  visible as (
    select oi.*, jc.id as jc_id
    from   public.outsource_invoices oi
    left join public.job_cards jc on jc.id = oi.job_card_id and jc.status = 'Completed'
    cross join f
    where (oi.batch_service_id is not null or oi.purchase_invoice_id is not null or jc.id is not null)
      and public.can_read_outsource_invoice(oi.job_card_id, oi.batch_service_id)
      and (f.ps is null        or oi.maintenance_payment_status = any (f.ps))
      and (f.fs is null        or oi.finance_payment_status     = any (f.fs))
      and (f.pb is null        or oi.paid_by                    = any (f.pb))
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
