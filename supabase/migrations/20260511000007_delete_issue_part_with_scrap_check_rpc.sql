BEGIN;

-- ── Scrap Inventory Module — Phase 5 ─────────────────────────────────────────
-- Migration 2/3: delete_issue_part_with_scrap_check RPC.
--
-- Replaces the frontend direct DELETE on issue_parts for the maintenance_exec
-- workflow.  Adds two guards:
--
--   a) Blocks deletion when the part's scrap entry has a permanent status
--      (sold / written_off / refurbished / sent_for_refurbishment).
--
--   b) Auto-reverses any in_storage scrap entry before deleting, so the
--      inventory records stay consistent (reversed entries are historical).
--
-- The existing DB trigger that restores parts.quantity_in_stock on
-- issue_parts DELETE fires normally — this RPC does not bypass it.

CREATE OR REPLACE FUNCTION public.delete_issue_part_with_scrap_check(
    p_issue_part_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_blocking_scrap jsonb;
    v_reversed_ids   uuid[] := '{}';
    v_reversed_id    uuid;
BEGIN
    -- (a) Caller must be maintenance_exec or super_admin
    IF NOT public.is_maintenance_exec() THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'UNAUTHORIZED',
            'error_message', 'Only maintenance executives can remove parts.',
            'details',       null
        )::text;
    END IF;

    -- (b) Detect permanent-status scrap that would be orphaned by the delete
    SELECT public.get_blocking_scrap_for_issue_part(p_issue_part_id)
    INTO   v_blocking_scrap;

    IF v_blocking_scrap IS NOT NULL THEN
        RAISE EXCEPTION '%', json_build_object(
            'error_code',    'SCRAP_BLOCKING_DELETE',
            'error_message', 'Cannot remove this part — the associated scrap record has been '
                             || (v_blocking_scrap->>'status')
                             || ' and cannot be undone.',
            'details',       v_blocking_scrap
                             || jsonb_build_object('issue_part_id', p_issue_part_id)
        )::text;
    END IF;

    -- (c) Auto-reverse any in_storage scrap entries for this part line.
    --     Normally at most one row qualifies, but the loop handles edge cases.
    FOR v_reversed_id IN
        UPDATE public.scrap_inventory
        SET    status     = 'reversed',
               updated_at = now(),
               updated_by = auth.uid()
        WHERE  source_issue_part_id = p_issue_part_id
          AND  status = 'in_storage'
        RETURNING id
    LOOP
        v_reversed_ids := v_reversed_ids || v_reversed_id;
    END LOOP;

    -- (d) Delete the issue_part.  The existing trigger restores inventory stock.
    DELETE FROM public.issue_parts WHERE id = p_issue_part_id;

    RETURN jsonb_build_object(
        'success',               true,
        'deleted_issue_part_id', p_issue_part_id,
        'reversed_scrap_ids',    v_reversed_ids
    );
END;
$$;

REVOKE ALL    ON FUNCTION public.delete_issue_part_with_scrap_check(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_issue_part_with_scrap_check(uuid) TO authenticated;

-- ── Verification ─────────────────────────────────────────────────────────────

SELECT routine_name, security_type, routine_definition IS NOT NULL AS has_body
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name   = 'delete_issue_part_with_scrap_check';

ROLLBACK; -- change to COMMIT once output looks correct
