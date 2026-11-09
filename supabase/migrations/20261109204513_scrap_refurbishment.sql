-- MAIN-123: refurbished scrap returns to stock as a separate "(Refurbished)" part,
-- recorded against a purchase invoice.

-- A table rather than a self-reference on parts: the prod→staging seed orders tables by
-- their foreign keys, and cannot order a table's rows against each other.
CREATE TABLE public.refurbished_part_links (
    refurbished_part_id uuid PRIMARY KEY REFERENCES public.parts(id),
    original_part_id uuid NOT NULL UNIQUE REFERENCES public.parts(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

COMMENT ON TABLE public.refurbished_part_links IS 'Which catalog part holds the refurbished stock of an original part. One per original.';

CREATE TABLE public.scrap_refurbishments (
    id uuid DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
    purchase_invoice_item_id uuid NOT NULL REFERENCES public.purchase_invoice_items(id),
    scrap_inventory_id uuid REFERENCES public.scrap_inventory(id),
    original_part_id uuid NOT NULL REFERENCES public.parts(id),
    refurbished_part_id uuid NOT NULL REFERENCES public.parts(id),
    quantity numeric(10,2) NOT NULL,
    comment text,
    created_by uuid REFERENCES public.users(id),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT scrap_refurbishments_quantity_check CHECK (quantity > 0),
    CONSTRAINT scrap_refurbishments_missing_source_comment_check
        CHECK (scrap_inventory_id IS NOT NULL OR NULLIF(btrim(comment), '') IS NOT NULL)
);

CREATE INDEX idx_scrap_refurbishments_item ON public.scrap_refurbishments (purchase_invoice_item_id);
CREATE INDEX idx_scrap_refurbishments_scrap ON public.scrap_refurbishments (scrap_inventory_id);

COMMENT ON COLUMN public.scrap_refurbishments.scrap_inventory_id IS 'NULL when the part was never recorded as scrap ("Scrap source details missing") — for example it was excluded at job card closure but kept in the scrap room. A comment is then required.';

ALTER TABLE public.refurbished_part_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrap_refurbishments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Exec and finance view refurbished_part_links" ON public.refurbished_part_links
    FOR SELECT TO authenticated USING (public.is_maintenance_exec() OR public.is_finance());

CREATE POLICY "Exec and finance view scrap_refurbishments" ON public.scrap_refurbishments
    FOR SELECT TO authenticated USING (public.is_maintenance_exec() OR public.is_finance());

-- p_invoice takes the same keys as save_purchase_invoice. p_lines is
-- [{ scrap_inventory_id, original_part_id, quantity, unit_price, gst_rate, comment }]:
-- scrap_inventory_id for a part picked from scrap, or original_part_id + comment when it
-- could not be found there.
CREATE OR REPLACE FUNCTION public.record_refurbishment(p_invoice jsonb, p_lines jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_location    uuid := NULLIF(p_invoice->>'location_id', '')::uuid;
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
       OR NULLIF(btrim(COALESCE(p_invoice->>'supplier_name', '')), '') IS NULL
       OR NULLIF(p_invoice->>'invoice_date', '') IS NULL
       OR v_location IS NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVOICE_INCOMPLETE',
            'error_message', 'Supplier, invoice number, invoice date and workshop are required.',
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

    v_invoice_id := public.save_purchase_invoice(NULL, p_invoice, '[]'::jsonb);

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

    UPDATE public.purchase_invoices
    SET    total_amount = (
               SELECT COALESCE(sum(line_total), 0)
               FROM   public.purchase_invoice_items
               WHERE  invoice_id = v_invoice_id
           )
    WHERE  id = v_invoice_id;

    RETURN v_invoice_id;
END;
$$;

-- Changing or removing a refurbishment's invoice line would move stock while the scrap
-- stayed marked refurbished. Moving the invoice to another workshop would do the same.
CREATE OR REPLACE FUNCTION public.guard_refurbishment_invoice_line() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.scrap_refurbishments WHERE purchase_invoice_item_id = OLD.id) THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'This line came from a scrap refurbishment and cannot be removed.';
        END IF;
        IF (NEW.part_id, NEW.quantity, NEW.unit_price, NEW.gst_rate, NEW.discount_amount)
           IS DISTINCT FROM (OLD.part_id, OLD.quantity, OLD.unit_price, OLD.gst_rate, OLD.discount_amount) THEN
            RAISE EXCEPTION 'This line came from a scrap refurbishment and cannot be changed.';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_guard_refurbishment_invoice_line
    BEFORE UPDATE OR DELETE ON public.purchase_invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.guard_refurbishment_invoice_line();

CREATE OR REPLACE FUNCTION public.guard_refurbishment_invoice_location() RETURNS trigger
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
        RAISE EXCEPTION 'This invoice has scrap refurbishment lines, so its workshop cannot be changed.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_guard_refurbishment_invoice_location
    BEFORE UPDATE OF location_id ON public.purchase_invoices
    FOR EACH ROW
    WHEN (OLD.location_id IS DISTINCT FROM NEW.location_id)
    EXECUTE FUNCTION public.guard_refurbishment_invoice_location();
