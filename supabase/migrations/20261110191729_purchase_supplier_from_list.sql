-- MAIN-128: Record Purchase and Edit Purchase pick the supplier from the approved list.
--
-- save_purchase_invoice now reads supplier_id from p_invoice (still the same three
-- arguments, so CREATE OR REPLACE replaces it rather than adding an overload) and
-- takes supplier_name from the supplier row, so Purchase History reads the same.
--
-- Old invoices have only a typed supplier_name and no supplier_id. They are left as
-- they are: an edit that sends no supplier_id keeps both columns, but only while the
-- invoice has none, so a linked invoice cannot be unlinked. Keeping the same supplier
-- needs no approval check, so an invoice whose supplier was rejected later still saves.

CREATE OR REPLACE FUNCTION public.save_purchase_invoice(p_invoice_id uuid, p_invoice jsonb, p_items jsonb) RETURNS uuid
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_invoice_id    uuid := p_invoice_id;
    v_item          jsonb;
    v_supplier_id   uuid := nullif(p_invoice->>'supplier_id', '')::uuid;
    v_supplier_name text;
    v_old_id        uuid;
    v_old_name      text;
BEGIN
    IF v_invoice_id IS NOT NULL THEN
        SELECT supplier_id, supplier_name INTO v_old_id, v_old_name
        FROM   public.purchase_invoices
        WHERE  id = v_invoice_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invoice not found.';
        END IF;
    END IF;

    IF v_supplier_id IS NULL THEN
        IF v_invoice_id IS NULL OR v_old_id IS NOT NULL THEN
            RAISE EXCEPTION 'Choose the supplier, or add them.';
        END IF;
        v_supplier_name := v_old_name;
    ELSIF v_supplier_id IS NOT DISTINCT FROM v_old_id THEN
        v_supplier_name := v_old_name;
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
            nullif(p_invoice->>'invoice_file_url', ''),
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
               invoice_file_url = nullif(p_invoice->>'invoice_file_url', ''),
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

    RETURN v_invoice_id;
END;
$$;
