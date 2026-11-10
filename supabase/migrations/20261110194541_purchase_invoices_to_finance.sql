-- MAIN-129: every purchase invoice goes to finance and, once accepted, the supplier ledger.
--
-- A purchase invoice carries the outsource invoice details on an outsource_invoices row
-- owned by it (purchase_invoice_id, from MAIN-123). Record Purchase and Bulk Upload
-- create that row through save_purchase_invoice, Edit Purchase keeps it in step with
-- the header, and the lines must add up to its Approved Amount.
--
-- An invoice saved without its file reaches finance as "New (invoice pending)": finance
-- cannot accept it, and the file arriving moves it to New.
--
-- Invoices recorded before this have no finance row and are left alone: they save as
-- before and never go to finance (they live in Google Sheets).

ALTER TABLE public.outsource_invoices DROP CONSTRAINT outsource_invoices_finance_payment_status_check;
ALTER TABLE public.outsource_invoices ADD CONSTRAINT outsource_invoices_finance_payment_status_check
    CHECK (finance_payment_status = ANY (ARRAY['New', 'New (invoice pending)', 'Hold', 'Reject', 'Accepted',
                                               'GST reconciled & closed', 'GST not applicable & closed']));

-- True when this finance invoice belongs to a purchase invoice that has no file yet.
CREATE FUNCTION public.purchase_invoice_file_missing(p_purchase_invoice_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT p_purchase_invoice_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.purchase_invoices
                   WHERE  id = p_purchase_invoice_id AND invoice_file_url IS NULL)
$$;

CREATE OR REPLACE FUNCTION public.submit_outsource_invoice_to_finance(p_invoice_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    PERFORM set_config('app.finance_submission', 'on', true);

    UPDATE public.outsource_invoices
    SET    submitted_on           = (now() AT TIME ZONE 'Asia/Kolkata')::date,
           finance_payment_status = CASE WHEN maintenance_payment_status IN ('Hold', 'Reject')
                                         THEN maintenance_payment_status
                                         WHEN public.purchase_invoice_file_missing(purchase_invoice_id)
                                         THEN 'New (invoice pending)'
                                         ELSE 'New' END,
           finance_remark         = CASE WHEN maintenance_payment_status IN ('Hold', 'Reject')
                                         THEN maintenance_payment_status || ' set by maintenance exec'
                                         ELSE finance_remark END
    WHERE  id = p_invoice_id
      AND  submitted_on IS NULL;

    PERFORM set_config('app.finance_submission', 'off', true);
END;
$$;

-- As before, plus: a purchase invoice with no file cannot be accepted, nor moved to New;
-- finance moves it between New (invoice pending), Hold and Reject until the file arrives.
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

-- Writes a purchase invoice's finance invoice from the header already saved and the
-- details in p_invoice (paid_by, maintenance_payment_status, invoice_value,
-- approved_amount, advance_amount, payby_date): inserts it, which submits it to
-- finance, or brings an existing one in step. Invoice No and the date come from the
-- header, so the two cannot drift. Called by save_purchase_invoice and
-- record_refurbishment once the lines are in, because the lines must add up to the
-- Approved Amount.
CREATE FUNCTION public.save_purchase_finance_invoice(p_invoice_id uuid, p_invoice jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_header    public.purchase_invoices%ROWTYPE;
    v_finance   public.outsource_invoices%ROWTYPE;
    v_inv_value numeric := NULLIF(p_invoice->>'invoice_value', '')::numeric;
    v_approved  numeric := NULLIF(p_invoice->>'approved_amount', '')::numeric;
    v_advance   numeric := NULLIF(p_invoice->>'advance_amount', '')::numeric;
    v_payby     date    := NULLIF(p_invoice->>'payby_date', '')::date;
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
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved
       OR v_payby     IS NULL OR v_payby < v_header.invoice_date THEN
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
            approved_amount, advance_amount, maintenance_payment_status, payby_date, created_by
        ) VALUES (
            p_invoice_id, v_header.invoice_date, btrim(v_header.invoice_number), p_invoice->>'paid_by', v_inv_value,
            v_approved, v_advance, p_invoice->>'maintenance_payment_status', v_payby, auth.uid()
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
           maintenance_payment_status = p_invoice->>'maintenance_payment_status',
           payby_date                 = v_payby
    WHERE  id = v_finance.id;

    -- The file has arrived: the invoice is ready for finance.
    IF v_finance.finance_payment_status = 'New (invoice pending)' AND v_header.invoice_file_url IS NOT NULL THEN
        PERFORM set_config('app.finance_submission', 'on', true);
        UPDATE public.outsource_invoices SET finance_payment_status = 'New' WHERE id = v_finance.id;
        PERFORM set_config('app.finance_submission', 'off', true);
    END IF;
END;
$$;

-- As MAIN-128 left it, plus:
--   * only maintenance executives (and super_admin) save purchase invoices — finance
--     reviews them, and the status guard already refuses finance setting maintenance's
--     status;
--   * a new invoice needs the invoice details and goes to finance;
--   * an invoice with a finance invoice keeps it in step, cannot lose its file, and is
--     locked apart from its notes once finance has accepted it;
--   * an invoice with no finance invoice (recorded before MAIN-129) saves as before.
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
        SELECT finance_payment_status INTO v_status
        FROM   public.outsource_invoices
        WHERE  purchase_invoice_id = v_invoice_id
        FOR UPDATE;
        v_has_finance := FOUND;
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

    RETURN v_invoice_id;
END;
$$;

-- As MAIN-123 left it, except that it writes the header itself and leaves the finance
-- invoice to save_purchase_finance_invoice: save_purchase_invoice now expects its lines
-- in the same call, while a refurbishment's lines come after the header.
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
    v_payby       date := NULLIF(p_invoice->>'payby_date', '')::date;
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
       OR v_advance   IS NULL OR v_advance   < 0 OR v_advance  > v_approved
       OR v_payby     IS NULL OR v_payby < v_inv_date THEN
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

    INSERT INTO public.purchase_invoices
        (invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, created_by)
    VALUES (
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

-- A refurbishment invoice's workshop stays fixed, because a move would shift stock while
-- the scrap stayed marked refurbished. Its other details are now edited like any
-- purchase invoice's until finance accepts it (MAIN-129); its lines stay locked by
-- guard_refurbishment_invoice_line.
CREATE OR REPLACE FUNCTION public.guard_refurbishment_invoice_header() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   public.purchase_invoice_items pii
        JOIN   public.scrap_refurbishments sr ON sr.purchase_invoice_item_id = pii.id
        WHERE  pii.invoice_id = NEW.id
    ) THEN
        RAISE EXCEPTION 'This invoice came from a scrap refurbishment, so its workshop cannot be changed.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER trigger_guard_refurbishment_invoice_header ON public.purchase_invoices;
CREATE TRIGGER trigger_guard_refurbishment_invoice_header
    BEFORE UPDATE ON public.purchase_invoices
    FOR EACH ROW
    WHEN (OLD.location_id IS DISTINCT FROM NEW.location_id)
    EXECUTE FUNCTION public.guard_refurbishment_invoice_header();

-- Only maintenance executives and super_admin write purchase invoices; finance reads them.
DROP POLICY "Exec and finance insert invoices" ON public.purchase_invoices;
DROP POLICY "Exec and finance update invoices" ON public.purchase_invoices;
DROP POLICY "Exec and finance insert invoice items" ON public.purchase_invoice_items;
DROP POLICY "Exec and finance update invoice items" ON public.purchase_invoice_items;
DROP POLICY "Exec and finance delete invoice items" ON public.purchase_invoice_items;

CREATE POLICY "Execs insert invoices" ON public.purchase_invoices
    FOR INSERT WITH CHECK (auth.uid() = created_by AND public.is_maintenance_exec());
CREATE POLICY "Execs update invoices" ON public.purchase_invoices
    FOR UPDATE USING (public.is_maintenance_exec());
CREATE POLICY "Execs insert invoice items" ON public.purchase_invoice_items
    FOR INSERT WITH CHECK (public.is_maintenance_exec());
CREATE POLICY "Execs update invoice items" ON public.purchase_invoice_items
    FOR UPDATE USING (public.is_maintenance_exec());
CREATE POLICY "Execs delete invoice items" ON public.purchase_invoice_items
    FOR DELETE USING (public.is_maintenance_exec());

-- The tiles gain a count of invoices waiting for their file. A new return column needs
-- DROP + CREATE: CREATE OR REPLACE cannot change it.
DROP FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[]);

CREATE FUNCTION public.get_outsource_invoice_summary(p_maintenance_payment_status text[] DEFAULT NULL::text[], p_paid_by text[] DEFAULT NULL::text[], p_date_from date DEFAULT NULL::date, p_date_to date DEFAULT NULL::date, p_finance_payment_status text[] DEFAULT NULL::text[]) RETURNS TABLE(new_count bigint, hold_count bigint, reject_count bigint, accepted_count bigint, pending_count bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
    SELECT
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New')      AS new_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Hold')     AS hold_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Reject')   AS reject_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'Accepted') AS accepted_count,
        COUNT(*) FILTER (WHERE oi.finance_payment_status = 'New (invoice pending)') AS pending_count
    FROM  outsource_invoices     oi
    LEFT JOIN job_cards          jc ON jc.id = oi.job_card_id
    LEFT JOIN batch_services     bs ON bs.id = oi.batch_service_id
    WHERE (bs.status = 'Active' OR jc.status = 'Completed' OR oi.purchase_invoice_id IS NOT NULL)
      AND (p_maintenance_payment_status IS NULL OR oi.maintenance_payment_status = ANY(p_maintenance_payment_status))
      AND (p_finance_payment_status     IS NULL OR oi.finance_payment_status     = ANY(p_finance_payment_status))
      AND (p_paid_by                    IS NULL OR oi.paid_by                    = ANY(p_paid_by))
      AND (p_date_from                  IS NULL OR oi.date_of_activity >= p_date_from)
      AND (p_date_to                    IS NULL OR oi.date_of_activity <= p_date_to)
$$;

ALTER FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[]) OWNER TO postgres;
GRANT ALL ON FUNCTION public.get_outsource_invoice_summary(text[], text[], date, date, text[])
    TO anon, authenticated, service_role;

-- Waiting for its file still counts as awaiting acceptance on the supplier list.
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
          AND  oi.finance_payment_status IN ('New', 'New (invoice pending)', 'Hold')
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
