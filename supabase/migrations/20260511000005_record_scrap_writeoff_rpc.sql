-- ── Scrap Inventory Module — Phase 2 ─────────────────────────────────────────
-- Migration 5/5: record_scrap_writeoff RPC.
--
-- Validates all preconditions, inserts scrap_writeoff header and items,
-- flips scrap_inventory.status to 'written_off' for each selected item — all atomic.
-- Returns writeoff_id and writeoff_item_ids so the frontend can write audit logs.

CREATE OR REPLACE FUNCTION public.record_scrap_writeoff(
    p_header  jsonb,
    p_items   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_writeoff_id        uuid;
    v_item               jsonb;
    v_scrap_id           uuid;
    v_item_id            uuid;
    v_writeoff_item_ids  uuid[] := '{}';
    v_scrap_ids          uuid[];
    v_bad_items          jsonb := '[]'::jsonb;
    v_dup_check          uuid[] := '{}';
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can record scrap write-offs.',
            'details',       null
        )::text;
    END IF;

    -- (b) reason must be a valid enum value
    IF (p_header->>'reason') NOT IN (
        'lost', 'damaged_unsaleable', 'hazmat_disposal',
        'stocktake_adjustment', 'donated', 'other'
    ) THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'INVALID_REASON',
            'error_message', 'Invalid write-off reason.',
            'details',       json_build_object('received', p_header->>'reason')
        )::text;
    END IF;

    -- (c) description must be non-empty
    IF trim(coalesce(p_header->>'description', '')) = '' THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_DESCRIPTION',
            'error_message', 'Description is required.',
            'details',       null
        )::text;
    END IF;

    -- (d) evidence_photos must have at least one non-empty URL
    IF (
        SELECT count(*)
        FROM jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb)) AS url
        WHERE trim(url) <> ''
    ) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'MISSING_EVIDENCE_PHOTO',
            'error_message', 'At least one evidence photo is required.',
            'details',       null
        )::text;
    END IF;

    -- (e) p_items must be non-empty
    IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'NO_ITEMS_SELECTED',
            'error_message', 'At least one scrap item must be selected.',
            'details',       null
        )::text;
    END IF;

    -- (f) every scrap_inventory_id must exist and have status = 'in_storage'
    SELECT array_agg((item->>'scrap_inventory_id')::uuid)
    INTO v_scrap_ids
    FROM jsonb_array_elements(p_items) AS item;

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

    -- (g) no duplicate scrap_inventory_id in p_items
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

    -- ── All validation passed. Execute operations atomically. ─────────────────

    -- Step 1: Insert scrap_writeoff header
    INSERT INTO public.scrap_writeoff (
        writeoff_date,
        reason,
        description,
        evidence_photos,
        notes,
        recorded_by
    ) VALUES (
        (p_header->>'writeoff_date')::date,
        (p_header->>'reason')::scrap_writeoff_reason,
        p_header->>'description',
        ARRAY(SELECT jsonb_array_elements_text(coalesce(p_header->'evidence_photos', '[]'::jsonb))),
        p_header->>'notes',
        auth.uid()
    )
    RETURNING id INTO v_writeoff_id;

    -- Step 2: For each item, insert line + update scrap_inventory status
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_scrap_id := (v_item->>'scrap_inventory_id')::uuid;

        INSERT INTO public.scrap_writeoff_items (
            writeoff_id,
            scrap_inventory_id,
            part_name_snapshot,
            quantity_snapshot,
            unit_snapshot
        )
        SELECT
            v_writeoff_id,
            si.id,
            si.part_name_snapshot,
            si.quantity_snapshot,
            si.unit_snapshot
        FROM public.scrap_inventory si
        WHERE si.id = v_scrap_id
        RETURNING id INTO v_item_id;

        v_writeoff_item_ids := v_writeoff_item_ids || v_item_id;

        UPDATE public.scrap_inventory
        SET
            status     = 'written_off',
            updated_at = now(),
            updated_by = auth.uid()
        WHERE id = v_scrap_id;
    END LOOP;

    RETURN json_build_object(
        'success',            true,
        'writeoff_id',        v_writeoff_id,
        'writeoff_item_ids',  v_writeoff_item_ids
    );
END;
$$;

REVOKE ALL    ON FUNCTION public.record_scrap_writeoff(jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_scrap_writeoff(jsonb, jsonb) TO authenticated;
