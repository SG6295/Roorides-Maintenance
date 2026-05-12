-- ── Scrap Inventory Module — Phase 2 ─────────────────────────────────────────
-- Migration 4/5: record_scrap_disposal RPC.
--
-- Validates all preconditions, inserts scrap_disposal header and items,
-- flips scrap_inventory.status to 'sold' for each selected item — all atomic.
-- Returns disposal_id and disposal_item_ids so the frontend can write audit logs.

CREATE OR REPLACE FUNCTION public.record_scrap_disposal(
    p_header  jsonb,
    p_items   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_disposal_id       uuid;
    v_item              jsonb;
    v_scrap_id          uuid;
    v_item_id           uuid;
    v_disposal_item_ids uuid[] := '{}';
    v_payment_mode      text;
    v_total_value       numeric(10,2);
    v_items_sum         numeric(10,2) := 0;
    v_scrap_ids         uuid[];
    v_bad_items         jsonb := '[]'::jsonb;
    v_dup_check         uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap disposals.',
            'details',       null
        )::text;
    END IF;

    -- (b) buyer_name must be non-empty
    IF trim(coalesce(p_header->>'buyer_name', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_BUYER_NAME',
            'error_message', 'Buyer name is required.',
            'details',       null
        )::text;
    END IF;

    -- (c) payment_mode must be a valid enum value
    v_payment_mode := p_header->>'payment_mode';
    IF v_payment_mode NOT IN ('cash', 'upi', 'bank_transfer', 'cheque', 'other') THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_PAYMENT_MODE',
            'error_message', 'Invalid payment mode.',
            'details',       json_build_object('received', v_payment_mode)
        )::text;
    END IF;

    -- (d) non-cash payments require a non-empty payment_reference
    IF v_payment_mode <> 'cash'
       AND trim(coalesce(p_header->>'payment_reference', '')) = ''
    THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_PAYMENT_REFERENCE',
            'error_message', 'Payment reference is required for non-cash payments.',
            'details',       json_build_object('payment_mode', v_payment_mode)
        )::text;
    END IF;

    -- (e) receipt_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_RECEIPT_PHOTO',
            'error_message', 'At least one receipt photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (f) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (g) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

    -- Check for non-existent IDs
    IF (
        SELECT count(*)
        FROM unnest(v_scrap_ids) AS rid
        WHERE NOT EXISTS (SELECT 1 FROM public.scrap_inventory WHERE id = rid)
    ) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap inventory IDs do not exist.',
            'details',       json_build_object('offending_items', coalesce(v_bad_items, '[]'::jsonb))
        )::text;
    END IF;

    -- Check for wrong-status IDs
    SELECT jsonb_agg(json_build_object('id', si.id::text, 'status', si.status::text))
    INTO v_bad_items
    FROM public.scrap_inventory si
    WHERE si.id = ANY(v_scrap_ids)
      AND si.status <> 'in_storage';

    IF v_bad_items IS NOT NULL AND jsonb_array_length(v_bad_items) > 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_SCRAP_ITEM',
            'error_message', 'One or more scrap items are not in_storage status.',
            'details',       json_build_object('offending_items', v_bad_items)
        )::text;
    END IF;

    -- (h) no duplicate scrap_inventory_id in p_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;
        IF v_scrap_id = ANY(v_dup_check) THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'DUPLICATE_SCRAP_ITEM',
                'error_message', 'The same scrap item appears more than once.',
                'details',       json_build_object('duplicate_id', v_scrap_id)
            )::text;
        END IF;
        v_dup_check := v_dup_check || v_scrap_id;
    END LOOP;

    -- (i) every value_allocated > 0; accumulate sum for step j
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF (v_item->>'value_allocated')::numeric <= 0 THEN
            RAISE EXCEPTION '%', json_build_object(
                'error_code',    'INVALID_VALUE_ALLOCATED',
                'error_message', 'value_allocated must be greater than zero.',
                'details',       json_build_object(
                    'offending_item_id', v_item->>'scrap_inventory_id',
                    'value',             v_item->>'value_allocated'
                )
            )::text;
        END IF;
        v_items_sum := v_items_sum + (v_item->>'value_allocated')::numeric(10,2);
    END LOOP;

    -- (j) sum(value_allocated) must equal p_header.total_value
    v_total_value := (p_header->>'total_value')::numeric(10,2);
    IF round(v_items_sum, 2) <> round(v_total_value, 2) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'TOTAL_VALUE_MISMATCH',
            'error_message', 'Sum of value_allocated does not match total_value.',
            'details',       json_build_object('expected', v_items_sum, 'received', v_total_value)
        )::text;
    END IF;

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_disposal header
    INSERT INTO public.scrap_disposal (
        disposal_date,
        buyer_name,
        buyer_contact,
        payment_mode,
        payment_reference,
        total_value,
        receipt_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'disposal_date')::date,
        p_header->>'buyer_name',
        p_header->>'buyer_contact',
        (p_header->>'payment_mode')::scrap_payment_mode,
        CASE WHEN v_payment_mode = 'cash' THEN NULL ELSE p_header->>'payment_reference' END,
        v_total_value,
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'receipt_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_disposal_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_disposal_items (
            disposal_id,
            scrap_inventory_id,
            value_allocated,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_disposal_id,
            si.id,
            (v_item->>'value_allocated')::numeric(10,2),
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_disposal_item_ids := v_disposal_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'sold',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',           true,
        'disposal_id',       v_disposal_id,
        'disposal_item_ids', v_disposal_item_ids
    );
END;
$$;

REVOKE ALL    ON FUNCTION public.record_scrap_disposal(jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_scrap_disposal(jsonb, jsonb) TO authenticated;
