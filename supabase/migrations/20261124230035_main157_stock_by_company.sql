-- MAIN-157 (epic MAIN-154): "Billed to" on purchases, and stock split by company.
--
-- Stock belongs to the company that paid for it. Each workshop's stock is now held per
-- company (NVS Travels / NVS Travel Solutions Pvt Ltd); everything that exists today is
-- NVS Travels. Purchases and refurbishments say who they are billed to and add stock to
-- that company; moves between workshops keep the company; audits count each company's
-- stock separately; scrap belongs to the company whose vehicle or stock it came from.
--
-- Until MAIN-159 (spares only from the vehicle's own company, with transfers), a job
-- card draws its vehicle's company's stock first and the other company's for the rest.
-- issue_parts.stock_draws records what came from where, so removing the spare puts it
-- back exactly and MAIN-159/160 can post the transfers.

-- ─── Companies that can own stock ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.stock_company_label(p_company text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
    SELECT CASE p_company
               WHEN 'nvs_travels'          THEN 'NVS Travels'
               WHEN 'nvs_travel_solutions' THEN 'NVS Travel Solutions Pvt Ltd'
               ELSE coalesce(p_company, '—')
           END
$function$;

COMMENT ON FUNCTION public.stock_company_label(text) IS
    'Display name of a stock company (MAIN-157). Mirrors companyLabel() in src/constants/vehicleCompanies.js.';

-- The company whose stock a job card draws from first: its vehicle's. A vehicle that is
-- Unknown cannot have work (MAIN-155), and one not in the vehicle list falls back to
-- NVS Travels, which owned everything before the split.
CREATE OR REPLACE FUNCTION public.job_card_stock_company(p_job_card_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT coalesce(
        (SELECT v.company
         FROM   public.job_cards jc
         JOIN   public.vehicles  v ON v.registration_number = jc.vehicle_number
         WHERE  jc.id = p_job_card_id
           AND  v.company IN ('nvs_travels', 'nvs_travel_solutions')
         LIMIT  1),
        'nvs_travels')
$function$;

REVOKE ALL ON FUNCTION public.job_card_stock_company(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.job_card_stock_company(uuid) TO authenticated, service_role;

-- ─── Columns ─────────────────────────────────────────────────────────────────────────
-- Every one is NOT NULL with DEFAULT 'nvs_travels': the default fills today's rows (all
-- NVS Travels by decision) and keeps the prod→staging seed working. The purchase forms
-- and save functions refuse a missing Billed to, so the default never stands in for one.

ALTER TABLE public.part_stock
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT part_stock_company_check CHECK (company IN ('nvs_travels', 'nvs_travel_solutions'));
ALTER TABLE public.part_stock DROP CONSTRAINT part_stock_pkey;
ALTER TABLE public.part_stock ADD CONSTRAINT part_stock_pkey PRIMARY KEY (part_id, location_id, company);
COMMENT ON TABLE public.part_stock IS
    'Authoritative stock per part per workshop per company (MAIN-157). parts.quantity_in_stock is the derived total across both.';

ALTER TABLE public.purchase_invoices
    ADD COLUMN billed_to text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT purchase_invoices_billed_to_check CHECK (billed_to IN ('nvs_travels', 'nvs_travel_solutions'));
COMMENT ON COLUMN public.purchase_invoices.billed_to IS
    'The company that paid for this purchase or refurbishment, and so owns its stock (MAIN-157). Invoices from before then are NVS Travels.';

ALTER TABLE public.stock_transfer_items
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT stock_transfer_items_company_check CHECK (company IN ('nvs_travels', 'nvs_travel_solutions'));
COMMENT ON COLUMN public.stock_transfer_items.company IS
    'Whose stock moved. A move between workshops never changes the company (MAIN-157).';

ALTER TABLE public.stock_audit_items
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT stock_audit_items_company_check CHECK (company IN ('nvs_travels', 'nvs_travel_solutions'));
ALTER TABLE public.stock_audit_items DROP CONSTRAINT stock_audit_items_unique_part;
ALTER TABLE public.stock_audit_items
    ADD CONSTRAINT stock_audit_items_unique_part UNIQUE (audit_id, part_id, company);
COMMENT ON COLUMN public.stock_audit_items.company IS
    'Whose stock this line counts — the count sheet''s Belongs to column (MAIN-157). Each company''s stock at the workshop is confirmed separately.';

ALTER TABLE public.scrap_inventory
    ADD COLUMN company text NOT NULL DEFAULT 'nvs_travels',
    ADD CONSTRAINT scrap_inventory_company_check CHECK (company IN ('nvs_travels', 'nvs_travel_solutions'));
COMMENT ON COLUMN public.scrap_inventory.company IS
    'The company this scrap belongs to (MAIN-157): from a job card, its vehicle''s company; from an audit, the counted stock''s company. Scrap from before then is NVS Travels.';

ALTER TABLE public.issue_parts
    ADD COLUMN stock_draws jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN public.issue_parts.stock_draws IS
    'How much of this spare came from each company''s stock, e.g. {"nvs_travels": 2} (MAIN-157). Empty on outsourced cards. Removing the spare returns exactly this. An empty object on an in-house line from before MAIN-157 reaching an environment means it was all NVS Travels.';

-- In-house spares used so far were all NVS Travels stock. (Service-role context, so the
-- Unknown-vehicle guard lets it through.)
UPDATE public.issue_parts ip
SET    stock_draws = jsonb_build_object('nvs_travels', ip.quantity_used)
FROM   public.issues i
JOIN   public.job_cards jc ON jc.id = i.job_card_id
WHERE  i.id = ip.issue_id
  AND  jc.type <> 'Outsource'
  AND  ip.quantity_used > 0;

-- ─── The one stock writer ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.apply_part_stock_delta(p_part_id uuid, p_location_id uuid, p_company text, p_delta numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_available numeric;
    v_part      text;
    v_location  text;
BEGIN
    IF p_location_id IS NULL THEN
        RAISE EXCEPTION 'Cannot change stock without a workshop location.';
    END IF;
    IF p_company IS NULL OR p_company NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION 'Cannot change stock without saying which company owns it.';
    END IF;

    INSERT INTO public.part_stock (part_id, location_id, company, quantity)
    VALUES (p_part_id, p_location_id, p_company, 0)
    ON CONFLICT (part_id, location_id, company) DO NOTHING;

    SELECT quantity INTO v_available
    FROM   public.part_stock
    WHERE  part_id = p_part_id AND location_id = p_location_id AND company = p_company
    FOR UPDATE;

    IF v_available + p_delta < 0 THEN
        SELECT name INTO v_part     FROM public.parts              WHERE id = p_part_id;
        SELECT name INTO v_location FROM public.workshop_locations WHERE id = p_location_id;
        RAISE EXCEPTION 'Not enough stock: % has % available at % for %, needed %.',
            COALESCE(v_part, 'part'), v_available, COALESCE(v_location, 'this location'),
            public.stock_company_label(p_company), abs(p_delta);
    END IF;

    UPDATE public.part_stock
    SET    quantity   = quantity + p_delta,
           updated_at = now()
    WHERE  part_id = p_part_id AND location_id = p_location_id AND company = p_company;
END;
$function$;

REVOKE ALL ON FUNCTION public.apply_part_stock_delta(uuid, uuid, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_part_stock_delta(uuid, uuid, text, numeric) TO service_role;

-- ─── Purchases add stock to the company they are billed to ───────────────────────────
CREATE OR REPLACE FUNCTION public.add_part_to_inventory()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_location_id uuid;
    v_company     text;
BEGIN
    SELECT pi.location_id, pi.billed_to INTO v_location_id, v_company
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_company, NEW.quantity);
    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.adjust_part_inventory_on_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_location_id uuid;
    v_company     text;
BEGIN
    SELECT pi.location_id, pi.billed_to INTO v_location_id, v_company
    FROM   public.purchase_invoices pi
    WHERE  pi.id = NEW.invoice_id;

    IF NEW.part_id = OLD.part_id THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_company, NEW.quantity - OLD.quantity);
    ELSE
        PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, v_company, -OLD.quantity);
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_company, NEW.quantity);
    END IF;

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_part_inventory_on_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_location_id uuid;
    v_company     text;
BEGIN
    SELECT pi.location_id, pi.billed_to INTO v_location_id, v_company
    FROM   public.purchase_invoices pi
    WHERE  pi.id = OLD.invoice_id;

    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, v_company, -OLD.quantity);
    RETURN OLD;
END;
$function$;

-- A change of workshop or of Billed to moves the invoice's stock with it — refused, like
-- a workshop change, if some of it has already been used.
CREATE OR REPLACE FUNCTION public.move_invoice_stock_on_location_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    r RECORD;
BEGIN
    IF (NEW.location_id, NEW.billed_to) IS NOT DISTINCT FROM (OLD.location_id, OLD.billed_to) THEN
        RETURN NEW;
    END IF;

    FOR r IN
        SELECT part_id, quantity FROM public.purchase_invoice_items WHERE invoice_id = NEW.id
    LOOP
        PERFORM public.apply_part_stock_delta(r.part_id, OLD.location_id, OLD.billed_to, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, NEW.location_id, NEW.billed_to,  r.quantity);
    END LOOP;

    RETURN NEW;
END;
$function$;

DROP TRIGGER trigger_move_invoice_stock_on_location_change ON public.purchase_invoices;
CREATE TRIGGER trigger_move_invoice_stock_on_location_change
    AFTER UPDATE OF location_id, billed_to ON public.purchase_invoices
    FOR EACH ROW EXECUTE FUNCTION public.move_invoice_stock_on_location_change();

CREATE OR REPLACE FUNCTION public.guard_refurbishment_invoice_header()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF OLD.kind = 'refurbishment' THEN
        RAISE EXCEPTION 'This invoice came from a scrap refurbishment, so its workshop and Billed to cannot be changed.';
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER trigger_guard_refurbishment_invoice_header ON public.purchase_invoices;
CREATE TRIGGER trigger_guard_refurbishment_invoice_header
    BEFORE UPDATE ON public.purchase_invoices
    FOR EACH ROW
    WHEN ((old.location_id IS DISTINCT FROM new.location_id) OR (old.billed_to IS DISTINCT FROM new.billed_to))
    EXECUTE FUNCTION public.guard_refurbishment_invoice_header();

-- Billed to is required, travels inside p_invoice (no new parameter), is locked with the
-- other details while finance has the invoice Accepted, and moves the stock when changed.
CREATE OR REPLACE FUNCTION public.save_purchase_invoice(p_invoice_id uuid, p_invoice jsonb, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
    v_billed_to     text := nullif(p_invoice->>'billed_to', '');
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

    IF v_billed_to IS NULL OR v_billed_to NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION 'Choose who the purchase is billed to: NVS Travels or NVS Travel Solutions Pvt Ltd.';
    END IF;

    IF v_resubmit AND v_status IS DISTINCT FROM 'Reject' THEN
        RAISE EXCEPTION 'Only a rejected invoice can be resubmitted.';
    END IF;

    IF v_status IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed') THEN
        IF (p_invoice->>'invoice_number', (p_invoice->>'invoice_date')::date, v_file,
            (p_invoice->>'location_id')::uuid, coalesce(v_supplier_id, v_old.supplier_id), v_billed_to)
           IS DISTINCT FROM
           (v_old.invoice_number, v_old.invoice_date, v_old.invoice_file_url,
            v_old.location_id, v_old.supplier_id, v_old.billed_to)
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
            (invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, billed_to, created_by)
        VALUES (
            p_invoice->>'invoice_number',
            v_supplier_id,
            v_supplier_name,
            (p_invoice->>'invoice_date')::date,
            nullif(p_invoice->>'notes', ''),
            v_file,
            (p_invoice->>'location_id')::uuid,
            v_billed_to,
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
               location_id      = (p_invoice->>'location_id')::uuid,
               billed_to        = v_billed_to
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
$function$;

CREATE OR REPLACE FUNCTION public.record_refurbishment(p_invoice jsonb, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    v_billed_to   text := NULLIF(p_invoice->>'billed_to', '');
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

    IF v_billed_to IS NULL OR v_billed_to NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'BILLED_TO_REQUIRED',
            'error_message', 'Choose who the refurbishment is billed to.',
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
        (kind, invoice_number, supplier_id, supplier_name, invoice_date, notes, invoice_file_url, location_id, billed_to, created_by)
    VALUES (
        'refurbishment',
        btrim(p_invoice->>'invoice_number'),
        v_supplier_id,
        v_supplier,
        v_inv_date,
        NULLIF(p_invoice->>'notes', ''),
        btrim(p_invoice->>'invoice_file_url'),
        v_location,
        v_billed_to,
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
            -- Scrap belongs to a company too; the refurbished stock goes to the Billed to
            -- company, so nothing passes between the companies unrecorded (MAIN-157).
            IF v_scrap.company <> v_billed_to THEN
                RAISE EXCEPTION '%', json_build_object(
                    'error_code',    'COMPANY_MISMATCH',
                    'error_message', format('"%s" is %s scrap, but this refurbishment is billed to %s.',
                                            v_scrap.part_name_snapshot,
                                            public.stock_company_label(v_scrap.company),
                                            public.stock_company_label(v_billed_to)),
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
        WHERE  original_part_id = v_part_id OR refurbished_part_id = v_part_id
        LIMIT  1;

        IF v_refurb_id IS NULL THEN
            -- A part already carrying the refurbished name is that part (MAIN-148), so
            -- originals of the same name share one refurbished part.
            SELECT id INTO v_refurb_id
            FROM   public.parts
            WHERE  name_key = public.part_name_key(v_part_name || ' (Refurbished)');

            IF v_refurb_id IS NULL THEN
                INSERT INTO public.parts (name, part_number, unit, quantity_in_stock)
                VALUES (v_part_name || ' (Refurbished)', v_part_number, v_part_unit, 0)
                RETURNING id INTO v_refurb_id;
            END IF;

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
                    location_id, company, created_by, updated_by
                ) VALUES (
                    v_scrap.source_ticket_id, v_scrap.source_job_card_id, v_scrap.source_issue_id,
                    v_scrap.source_issue_part_id, v_scrap.source_vehicle_number, v_scrap.source_audit_reason_id,
                    v_scrap.part_id_snapshot, v_scrap.part_name_snapshot, v_scrap.part_number_snapshot,
                    v_quantity, v_scrap.unit_snapshot, v_scrap.description, v_scrap.notes, v_scrap.photos, 'refurbished',
                    v_scrap.received_by, v_scrap.received_at, v_scrap.current_location,
                    v_scrap.outsource_part_disposition_snapshot,
                    v_scrap.outsource_vendor_credit_amount_snapshot,
                    v_scrap.location_id, v_scrap.company, v_scrap.created_by, auth.uid()
                )
                RETURNING id INTO v_final_scrap;

                -- The insert trigger re-derives the workshop and company from the job card.
                UPDATE public.scrap_inventory
                SET    location_id = v_scrap.location_id,
                       company     = v_scrap.company
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
$function$;

-- A resubmission that only corrects Billed to is a change (MAIN-120 refuses "nothing
-- changed"), and the history names it.
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
        'maintenance_payment_status', oi.maintenance_payment_status,
        'payby_date',                 oi.payby_date,
        'supplier_id',                coalesce(jc.supplier_id, bs.supplier_id, pi.supplier_id),
        'invoice_file',               coalesce(jc.invoice_url, bs.invoice_url, pi.invoice_file_url),
        'billed_to',                  pi.billed_to,
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

-- ─── Job card spares ─────────────────────────────────────────────────────────────────
-- Until MAIN-159: the vehicle's company's stock first, the other company's for the rest,
-- recorded on the line. Now BEFORE INSERT so the draws can be written onto the row.

CREATE OR REPLACE FUNCTION public.deduct_part_from_inventory()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_job_card_id   uuid;
    v_job_card_type text;
    v_location_id   uuid;
    v_first         text;
    v_second        text;
    v_have_first    numeric;
    v_have_total    numeric;
    v_take_first    numeric;
    v_part          text;
    v_location      text;
BEGIN
    SELECT jc.id, jc.type, jc.location_id INTO v_job_card_id, v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = NEW.issue_id;

    IF v_job_card_type = 'Outsource' THEN
        NEW.stock_draws := '{}'::jsonb;
        RETURN NEW;
    END IF;

    IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Cannot change stock without a workshop location.';
    END IF;

    v_first  := public.job_card_stock_company(v_job_card_id);
    v_second := CASE v_first WHEN 'nvs_travels' THEN 'nvs_travel_solutions' ELSE 'nvs_travels' END;

    -- Both rows locked, in a fixed order, before either is read.
    PERFORM 1 FROM public.part_stock
    WHERE  part_id = NEW.part_id AND location_id = v_location_id
    ORDER  BY company
    FOR UPDATE;

    SELECT coalesce(sum(quantity) FILTER (WHERE company = v_first), 0), coalesce(sum(quantity), 0)
    INTO   v_have_first, v_have_total
    FROM   public.part_stock
    WHERE  part_id = NEW.part_id AND location_id = v_location_id;

    IF v_have_total < NEW.quantity_used THEN
        SELECT name INTO v_part     FROM public.parts              WHERE id = NEW.part_id;
        SELECT name INTO v_location FROM public.workshop_locations WHERE id = v_location_id;
        RAISE EXCEPTION 'Not enough stock: % has % available at %, needed %.',
            COALESCE(v_part, 'part'), v_have_total, COALESCE(v_location, 'this location'), NEW.quantity_used;
    END IF;

    v_take_first := least(v_have_first, NEW.quantity_used);
    NEW.stock_draws := '{}'::jsonb;

    IF v_take_first > 0 THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_first, -v_take_first);
        NEW.stock_draws := NEW.stock_draws || jsonb_build_object(v_first, v_take_first);
    END IF;
    IF NEW.quantity_used - v_take_first > 0 THEN
        PERFORM public.apply_part_stock_delta(NEW.part_id, v_location_id, v_second, -(NEW.quantity_used - v_take_first));
        NEW.stock_draws := NEW.stock_draws || jsonb_build_object(v_second, NEW.quantity_used - v_take_first);
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER trigger_deduct_part_inventory ON public.issue_parts;
-- Named after trg_guard_unassigned_vehicle alphabetically, so the Unknown-vehicle guard
-- still runs first.
CREATE TRIGGER trigger_deduct_part_inventory
    BEFORE INSERT ON public.issue_parts
    FOR EACH ROW EXECUTE FUNCTION public.deduct_part_from_inventory();

CREATE OR REPLACE FUNCTION public.restore_part_to_inventory()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_job_card_type text;
    v_location_id   uuid;
    d               RECORD;
BEGIN
    SELECT jc.type, jc.location_id INTO v_job_card_type, v_location_id
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  i.id = OLD.issue_id;

    IF v_location_id IS NULL THEN
        RETURN OLD;
    END IF;

    -- Exactly what was drawn, to the company it came from.
    IF OLD.stock_draws <> '{}'::jsonb THEN
        FOR d IN SELECT key AS company, value::numeric AS quantity FROM jsonb_each_text(OLD.stock_draws)
        LOOP
            PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, d.company, d.quantity);
        END LOOP;
        RETURN OLD;
    END IF;

    -- A line with no record of its draws is outsourced (no stock) or from before
    -- MAIN-157, when all stock was NVS Travels.
    IF v_job_card_type = 'Outsource' THEN
        RETURN OLD;
    END IF;

    PERFORM public.apply_part_stock_delta(OLD.part_id, v_location_id, 'nvs_travels', OLD.quantity_used);
    RETURN OLD;
END;
$function$;

-- ─── Scrap from a job card belongs to its vehicle's company ──────────────────────────

CREATE OR REPLACE FUNCTION public.set_scrap_location_from_job_card()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.source_job_card_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT jc.location_id INTO NEW.location_id
    FROM   public.job_cards jc
    WHERE  jc.id = NEW.source_job_card_id;

    IF NEW.location_id IS NULL THEN
        NEW.location_id := 'a1e1d4c0-0000-4000-8000-000000000001';
    END IF;

    -- The part came off the vehicle, so it is the vehicle's company's (MAIN-157).
    NEW.company := public.job_card_stock_company(NEW.source_job_card_id);

    RETURN NEW;
END;
$function$;

-- ─── Moves between workshops keep the company ────────────────────────────────────────
-- Each line says whose stock it is, inside p_items (no new parameter).
CREATE OR REPLACE FUNCTION public.transfer_stock(p_from uuid, p_to uuid, p_items jsonb, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_transfer_id uuid;
    v_role        text;
    r             RECORD;
    v_count       integer := 0;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('maintenance_exec', 'super_admin') THEN
        RAISE EXCEPTION 'Only a maintenance executive or super admin can move stock between workshops.';
    END IF;

    IF p_from = p_to THEN
        RAISE EXCEPTION 'Source and destination workshop must be different.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_from AND is_active) THEN
        RAISE EXCEPTION 'The source workshop is not an active location.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_to AND is_active) THEN
        RAISE EXCEPTION 'The destination workshop is not an active location.';
    END IF;

    INSERT INTO public.stock_transfers (from_location_id, to_location_id, notes, transferred_by)
    VALUES (p_from, p_to, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid())
    RETURNING id INTO v_transfer_id;

    FOR r IN
        SELECT (elem->>'part_id')::uuid  AS part_id,
               (elem->>'quantity')::numeric AS quantity,
               NULLIF(elem->>'company', '') AS company
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        IF r.part_id IS NULL OR r.quantity IS NULL OR r.quantity <= 0 THEN
            RAISE EXCEPTION 'Every line needs a part and a quantity greater than zero.';
        END IF;
        IF r.company IS NULL OR r.company NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
            RAISE EXCEPTION 'Say whose stock is moving: NVS Travels or NVS Travel Solutions Pvt Ltd.';
        END IF;

        PERFORM public.apply_part_stock_delta(r.part_id, p_from, r.company, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, p_to,   r.company,  r.quantity);

        INSERT INTO public.stock_transfer_items (transfer_id, part_id, quantity, company)
        VALUES (v_transfer_id, r.part_id, r.quantity, r.company);

        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one part to move.';
    END IF;

    RETURN v_transfer_id;
END;
$function$;

-- ─── Stock audits: each company's stock at the workshop is counted separately ────────

-- One sheet line per part per company that holds it here.
CREATE OR REPLACE FUNCTION public.start_stock_audit(p_location_id uuid, p_notes text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_audit_id uuid;
    v_role     text;
    v_name     text;
    v_open_by  text;
    v_open_at  timestamp without time zone;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can run a stock audit.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.workshop_locations WHERE id = p_location_id AND is_active
    ) THEN
        RAISE EXCEPTION 'That workshop is not an active location.';
    END IF;

    SELECT started_by_name, started_at INTO v_open_by, v_open_at
    FROM   public.stock_audits
    WHERE  location_id = p_location_id
      AND  status IN ('counting', 'review');

    IF v_open_at IS NOT NULL THEN
        RAISE EXCEPTION 'An audit is already open at this workshop, started by % on %. Complete or cancel it before starting another.',
            COALESCE(NULLIF(v_open_by, ''), 'someone'),
            to_char(v_open_at, 'DD Mon YYYY');
    END IF;

    INSERT INTO public.stock_audits (location_id, started_by, started_by_name, notes)
    VALUES (p_location_id, auth.uid(), COALESCE(v_name, ''),
            NULLIF(btrim(COALESCE(p_notes, '')), ''))
    RETURNING id INTO v_audit_id;

    -- Only what is actually stocked here. Printing the whole catalogue would mean 300+
    -- rows of zeroes to write out by hand at a workshop that stocks seven parts, and a
    -- blank row blocks the upload. Anything physically present but unlisted comes back
    -- on one of the sheet's blank "found" rows instead.
    --
    -- A workshop with no stock at all yields an empty sheet on purpose: that is how a new
    -- workshop's opening stock gets entered, entirely through found rows.
    INSERT INTO public.stock_audit_items (
        audit_id, part_id, company, part_name_snapshot, part_number_snapshot, unit_snapshot, system_qty
    )
    SELECT v_audit_id, p.id, ps.company, p.name, p.part_number, COALESCE(p.unit, 'pcs'), ps.quantity
    FROM   public.part_stock ps
    JOIN   public.parts p ON p.id = ps.part_id
    WHERE  ps.location_id = p_location_id
      AND  ps.quantity > 0;

    RETURN v_audit_id;
END;
$function$;

-- Each row carries its Belongs to inside p_counts; a found row must say it.
CREATE OR REPLACE FUNCTION public.submit_stock_audit_counts(p_audit_id uuid, p_counts jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role     text;
    v_name     text;
    v_status   text;
    v_location uuid;
    r          RECORD;
    v_blank    integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can upload a count sheet.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status NOT IN ('counting', 'review') THEN
        RAISE EXCEPTION 'This audit is already % and cannot take new counts.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid        AS part_id,
               (elem->>'counted_qty')::numeric AS counted_qty,
               NULLIF(elem->>'company', '')    AS company
        FROM   jsonb_array_elements(p_counts) AS elem
    LOOP
        IF r.part_id IS NULL OR r.counted_qty IS NULL THEN
            RAISE EXCEPTION 'Every row on the sheet needs a part and a counted quantity.';
        END IF;
        IF r.counted_qty < 0 THEN
            RAISE EXCEPTION 'A counted quantity cannot be negative.';
        END IF;
        IF r.company IS NULL OR r.company NOT IN ('nvs_travels', 'nvs_travel_solutions') THEN
            RAISE EXCEPTION 'Every row on the sheet needs Belongs to: NVS Travels or NVS Travel Solutions Pvt Ltd.';
        END IF;

        -- A changed count makes the explanation of the old difference meaningless.
        DELETE FROM public.stock_audit_item_reasons l
        USING  public.stock_audit_items i
        WHERE  l.audit_item_id = i.id
          AND  i.audit_id = p_audit_id
          AND  i.part_id = r.part_id
          AND  i.company = r.company
          AND  i.counted_qty IS DISTINCT FROM r.counted_qty;

        UPDATE public.stock_audit_items
        SET counted_qty = r.counted_qty
        WHERE audit_id = p_audit_id AND part_id = r.part_id AND company = r.company;

        IF NOT FOUND THEN
            -- Written onto a blank row: stock the app did not know was here.
            INSERT INTO public.stock_audit_items (
                audit_id, part_id, company, part_name_snapshot, part_number_snapshot,
                unit_snapshot, system_qty, counted_qty, was_found_row
            )
            SELECT p_audit_id, p.id, r.company, p.name, p.part_number, COALESCE(p.unit, 'pcs'),
                   COALESCE(ps.quantity, 0), r.counted_qty, true
            FROM   public.parts p
            LEFT   JOIN public.part_stock ps
                   ON ps.part_id = p.id AND ps.location_id = v_location AND ps.company = r.company
            WHERE  p.id = r.part_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'A part written onto the sheet is not in the catalogue. Add it under Parts Catalog first, then upload again.';
            END IF;
        END IF;
    END LOOP;

    -- Nothing printed on the sheet may come back blank.
    SELECT count(*) INTO v_blank
    FROM   public.stock_audit_items
    WHERE  audit_id = p_audit_id AND counted_qty IS NULL;

    IF v_blank > 0 THEN
        RAISE EXCEPTION '% part(s) on the sheet have no counted quantity. Every row must be filled in before the sheet can be uploaded.', v_blank;
    END IF;

    UPDATE public.stock_audits
    SET status                  = 'review',
        counts_uploaded_by      = auth.uid(),
        counts_uploaded_by_name = COALESCE(v_name, ''),
        counts_uploaded_at      = now()
    WHERE id = p_audit_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_stock_audit_reasons(p_audit_id uuid, p_items jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role      text;
    v_status    text;
    r           RECORD;
    l           RECORD;
    v_item_id   uuid;
    v_variance  numeric;
    v_part_name text;
    v_total     numeric;
    v_sort      integer;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can explain an audit mismatch.';
    END IF;

    SELECT status INTO v_status FROM public.stock_audits WHERE id = p_audit_id FOR UPDATE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Reasons can only be set while the audit is under review. This one is %.', v_status;
    END IF;

    FOR r IN
        SELECT (elem->>'part_id')::uuid AS part_id,
               COALESCE(NULLIF(elem->>'company', ''), 'nvs_travels') AS company,
               COALESCE(elem->'lines', '[]'::jsonb) AS lines
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        v_item_id := NULL;
        SELECT id, variance, part_name_snapshot INTO v_item_id, v_variance, v_part_name
        FROM   public.stock_audit_items
        WHERE  audit_id = p_audit_id AND part_id = r.part_id AND company = r.company;

        IF v_item_id IS NULL THEN
            RAISE EXCEPTION 'One of those parts is not part of this audit.';
        END IF;

        DELETE FROM public.stock_audit_item_reasons WHERE audit_item_id = v_item_id;

        v_total := 0;
        v_sort  := 0;

        FOR l IN
            SELECT round((e->>'quantity')::numeric, 2) AS quantity,
                   NULLIF(btrim(COALESCE(e->>'reason', '')), '') AS reason,
                   NULLIF(btrim(COALESCE(e->>'notes',  '')), '') AS notes
            FROM   jsonb_array_elements(r.lines) AS e
        LOOP
            IF l.quantity IS NULL OR l.quantity <= 0 THEN
                RAISE EXCEPTION 'Every reason needs a quantity above zero (%).', v_part_name;
            END IF;
            IF l.reason IS NULL THEN
                RAISE EXCEPTION 'Every line needs a reason (%).', v_part_name;
            END IF;
            IF l.reason NOT IN ('missing', 'stolen', 'damaged', 'found', 'other') THEN
                RAISE EXCEPTION 'Unknown reason "%".', l.reason;
            END IF;
            IF l.reason = 'other' AND l.notes IS NULL THEN
                RAISE EXCEPTION 'A note is required when the reason is Other (%).', v_part_name;
            END IF;
            IF l.reason = 'found' AND COALESCE(v_variance, 0) <= 0 THEN
                RAISE EXCEPTION 'Found / excess only applies where more was counted than expected (%).', v_part_name;
            END IF;
            IF l.reason IN ('missing', 'stolen', 'damaged') AND COALESCE(v_variance, 0) >= 0 THEN
                RAISE EXCEPTION 'Missing, Stolen and Damaged only apply to a shortfall (%).', v_part_name;
            END IF;

            INSERT INTO public.stock_audit_item_reasons (audit_item_id, quantity, reason, notes, sort_order)
            VALUES (v_item_id, l.quantity, l.reason, l.notes, v_sort);

            v_total := v_total + l.quantity;
            v_sort  := v_sort + 1;
        END LOOP;

        IF v_total > abs(COALESCE(v_variance, 0)) THEN
            RAISE EXCEPTION 'The quantities for "%" add up to %, more than the difference of %.',
                v_part_name, v_total, abs(COALESCE(v_variance, 0));
        END IF;
    END LOOP;
END;
$function$;

-- Corrects and scraps each company's line against that company's stock.
CREATE OR REPLACE FUNCTION public.complete_stock_audit(p_audit_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_role        text;
    v_name        text;
    v_status      text;
    v_location    uuid;
    r             RECORD;
    v_live        numeric;
    v_unit_value  numeric;
    v_total       integer := 0;
    v_var_parts   integer := 0;
    v_net_units   numeric := 0;
    v_net_value   numeric := 0;
    v_unvalued    integer := 0;
    v_unexplained integer;
BEGIN
    SELECT role, name INTO v_role, v_name FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('finance', 'super_admin') THEN
        RAISE EXCEPTION 'Only finance or a super admin can complete a stock audit.';
    END IF;

    SELECT status, location_id INTO v_status, v_location
    FROM   public.stock_audits WHERE id = p_audit_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'That audit no longer exists.';
    END IF;
    IF v_status <> 'review' THEN
        RAISE EXCEPTION 'Only an audit under review can be completed. This one is %.', v_status;
    END IF;

    SELECT count(*) INTO v_unexplained
    FROM   public.stock_audit_items i
    WHERE  i.audit_id = p_audit_id
      AND  i.variance <> 0
      AND  COALESCE((SELECT sum(l.quantity)
                     FROM   public.stock_audit_item_reasons l
                     WHERE  l.audit_item_id = i.id), 0) <> abs(i.variance);

    IF v_unexplained > 0 THEN
        RAISE EXCEPTION '% mismatch(es) still need reasons that add up to the difference before the audit can be completed.', v_unexplained;
    END IF;

    FOR r IN
        SELECT * FROM public.stock_audit_items
        WHERE  audit_id = p_audit_id
        ORDER  BY part_name_snapshot, company
    LOOP
        SELECT quantity INTO v_live
        FROM   public.part_stock
        WHERE  part_id = r.part_id AND location_id = v_location AND company = r.company;
        v_live := COALESCE(v_live, 0);

        -- Latest purchase price per unit, net of discount and before GST — the same
        -- arithmetic purchase_invoice_items.line_total uses.
        SELECT (pii.quantity * pii.unit_price - pii.discount_amount) / NULLIF(pii.quantity, 0)
        INTO   v_unit_value
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = r.part_id
        ORDER  BY pi.invoice_date DESC, pi.created_at DESC
        LIMIT  1;

        IF COALESCE(r.variance, 0) <> 0 THEN
            -- apply_part_stock_delta guards this too, but it cannot know the count is
            -- what pushed the workshop negative, so check here for a usable message.
            IF v_live + r.variance < 0 THEN
                RAISE EXCEPTION 'Cannot write off % of "%" (%): only % left at this workshop after activity during the audit. Re-count that part and run a fresh audit.',
                    abs(r.variance), r.part_name_snapshot, public.stock_company_label(r.company), v_live;
            END IF;

            PERFORM public.apply_part_stock_delta(r.part_id, v_location, r.company, r.variance);

            v_var_parts := v_var_parts + 1;
            v_net_units := v_net_units + r.variance;

            IF v_unit_value IS NULL THEN
                v_unvalued := v_unvalued + 1;
            ELSE
                v_net_value := v_net_value + round(r.variance * v_unit_value, 2);
            END IF;

            -- One scrap item per Damaged line, so each keeps its own comment. Parts set
            -- to skip scrap at job card closure skip it here too.
            INSERT INTO public.scrap_inventory (
                source_audit_reason_id, part_id_snapshot, part_name_snapshot,
                part_number_snapshot, quantity_snapshot, unit_snapshot, notes,
                status, location_id, company, created_by
            )
            SELECT l.id, r.part_id, r.part_name_snapshot, r.part_number_snapshot,
                   l.quantity, r.unit_snapshot, l.notes,
                   'in_storage'::public.scrap_item_status, v_location, r.company, auth.uid()
            FROM   public.stock_audit_item_reasons l
            JOIN   public.parts p ON p.id = r.part_id
            WHERE  l.audit_item_id = r.id
              AND  l.reason = 'damaged'
              AND  NOT p.default_exclude_from_scrap;
        END IF;

        UPDATE public.stock_audit_items
        SET moved_during_audit  = v_live - r.system_qty,
            applied_delta       = COALESCE(r.variance, 0),
            final_qty           = v_live + COALESCE(r.variance, 0),
            unit_value_snapshot = v_unit_value,
            variance_value      = CASE
                                      WHEN v_unit_value IS NULL THEN NULL
                                      ELSE round(COALESCE(r.variance, 0) * v_unit_value, 2)
                                  END
        WHERE id = r.id;

        v_total := v_total + 1;
    END LOOP;

    UPDATE public.stock_audits
    SET status            = 'completed',
        completed_by      = auth.uid(),
        completed_by_name = COALESCE(v_name, ''),
        completed_at      = now(),
        total_parts       = v_total,
        variance_parts    = v_var_parts,
        net_units         = v_net_units,
        net_value         = v_net_value,
        unvalued_parts    = v_unvalued
    WHERE id = p_audit_id;

    RETURN p_audit_id;
END;
$function$;

-- Adds the company of each movement, so a line is explained by its own company's
-- movements. The return type changes, hence DROP + CREATE.
DROP FUNCTION public.stock_audit_movements(uuid);

CREATE FUNCTION public.stock_audit_movements(p_audit_id uuid)
 RETURNS TABLE(part_id uuid, company text, source text, quantity numeric, reference text, vehicle_number text, occurred_at timestamp without time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    WITH a AS (
        SELECT sa.id, sa.location_id, sa.started_at
        FROM   public.stock_audits sa
        WHERE  sa.id = p_audit_id
          -- Mirrors the SELECT policy on stock_audits.
          AND  EXISTS (
                   SELECT 1 FROM public.users u
                   WHERE u.id = auth.uid()
                     AND u.role IN ('finance', 'super_admin', 'maintenance_exec')
               )
    )
    -- Consumed on a job card, per company it was drawn from. Outsource job cards never
    -- touch stock, so they are excluded exactly as deduct_part_from_inventory() excludes
    -- them; a line with no recorded draws is from before MAIN-157, all NVS Travels.
    SELECT ip.part_id,
           d.company,
           'consumption'::text,
           -d.quantity,
           'JC-' || jc.job_card_number::text,
           jc.vehicle_number,
           ip.added_at
    FROM   a
    JOIN   public.job_cards   jc ON jc.location_id = a.location_id AND jc.type <> 'Outsource'
    JOIN   public.issues      i  ON i.job_card_id = jc.id
    JOIN   public.issue_parts ip ON ip.issue_id = i.id
    CROSS  JOIN LATERAL (
               SELECT e.key AS company, e.value::numeric AS quantity
               FROM   jsonb_each_text(ip.stock_draws) e
               UNION ALL
               SELECT 'nvs_travels', ip.quantity_used
               WHERE  ip.stock_draws = '{}'::jsonb
           ) d
    WHERE  ip.added_at > a.started_at

    UNION ALL

    -- Inwarded on a purchase invoice, to the company it is billed to.
    SELECT pii.part_id,
           pi.billed_to,
           'purchase'::text,
           pii.quantity,
           pi.invoice_number,
           NULL::text,
           pi.created_at
    FROM   a
    JOIN   public.purchase_invoices      pi  ON pi.location_id = a.location_id
    JOIN   public.purchase_invoice_items pii ON pii.invoice_id = pi.id
    WHERE  pi.created_at > a.started_at

    UNION ALL

    -- Moved to or from another workshop.
    SELECT sti.part_id,
           sti.company,
           CASE WHEN st.to_location_id = a.location_id
                THEN 'transfer_in' ELSE 'transfer_out' END,
           CASE WHEN st.to_location_id = a.location_id
                THEN sti.quantity ELSE -sti.quantity END,
           wl.name,
           NULL::text,
           st.transferred_at
    FROM   a
    JOIN   public.stock_transfers st
           ON (st.from_location_id = a.location_id OR st.to_location_id = a.location_id)
    JOIN   public.stock_transfer_items sti ON sti.transfer_id = st.id
    JOIN   public.workshop_locations wl
           ON wl.id = CASE WHEN st.to_location_id = a.location_id
                           THEN st.from_location_id ELSE st.to_location_id END
    WHERE  st.transferred_at > a.started_at

    ORDER BY 7 DESC;
$function$;

REVOKE ALL ON FUNCTION public.stock_audit_movements(uuid) FROM PUBLIC, anon;
GRANT ALL ON FUNCTION public.stock_audit_movements(uuid) TO authenticated, service_role;

-- ─── The old three-argument stock writer ─────────────────────────────────────────────
-- Every caller now names the company; dropping it makes a missed caller fail loudly
-- instead of quietly putting stock under the wrong company.
DROP FUNCTION public.apply_part_stock_delta(uuid, uuid, numeric);
