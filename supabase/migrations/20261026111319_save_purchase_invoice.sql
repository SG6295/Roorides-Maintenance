-- MAIN-97: saving a purchase invoice is all-or-nothing.
--
-- useUpdatePurchaseInvoice made five sequential PostgREST calls (header, line deletes,
-- line updates, line inserts, total). Each was atomic; the sequence was not. Lowering a
-- line's quantity for stock already consumed makes apply_part_stock_delta raise — after
-- the header and earlier lines had committed — leaving the invoice half-saved with a
-- total that no longer matched its lines. Creating an invoice had the same shape
-- (header, then lines).
--
-- One function now does both, in one transaction.
--
-- SECURITY INVOKER: the existing "Exec and finance …" RLS policies on purchase_invoices
-- and purchase_invoice_items still decide who may save. The stock triggers it sets off
-- are already SECURITY DEFINER.
--
-- Edit order matches the old hook: the header is written first so that a workshop
-- change (trigger_move_invoice_stock_on_location_change, MAIN-72) moves the stock before
-- any line changes, and the line triggers then read the new location off the header.
--
-- total_amount is taken from the generated line_total column rather than computed by
-- the client, so it cannot drift from its lines.
--
-- p_items is jsonb so the signature never has to grow: adding a parameter under
-- CREATE OR REPLACE creates a second overload instead of replacing this one.
--
-- p_invoice: { invoice_number, supplier_name, invoice_date, notes, invoice_file_url, location_id }
-- p_items:   [{ id?, part_id, quantity, unit_price, gst_rate, discount_amount }, ...]
--            an item with an id updates that line; without one it is inserted. On edit,
--            existing lines whose id is absent are deleted.

create function public.save_purchase_invoice(
    p_invoice_id uuid,
    p_invoice    jsonb,
    p_items      jsonb
) returns uuid
    language plpgsql security invoker
    set search_path to 'public'
    as $$
DECLARE
    v_invoice_id uuid := p_invoice_id;
    v_item       jsonb;
BEGIN
    IF v_invoice_id IS NULL THEN
        INSERT INTO public.purchase_invoices
            (invoice_number, supplier_name, invoice_date, notes, invoice_file_url, location_id, created_by)
        VALUES (
            p_invoice->>'invoice_number',
            p_invoice->>'supplier_name',
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
               supplier_name    = p_invoice->>'supplier_name',
               invoice_date     = (p_invoice->>'invoice_date')::date,
               notes            = nullif(p_invoice->>'notes', ''),
               invoice_file_url = nullif(p_invoice->>'invoice_file_url', ''),
               location_id      = (p_invoice->>'location_id')::uuid
        WHERE  id = v_invoice_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invoice not found.';
        END IF;

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

alter function public.save_purchase_invoice(uuid, jsonb, jsonb) owner to postgres;
grant all on function public.save_purchase_invoice(uuid, jsonb, jsonb) to authenticated, service_role;
