BEGIN;

-- ── Scrap Inventory Module — Phase 5 ─────────────────────────────────────────
-- Migration 1/3: get_blocking_scrap_for_issue_part helper function.
--
-- Returns a jsonb blob describing the permanent-status scrap entry that would
-- block deletion of the given issue_part row.  Returns NULL if no such entry
-- exists (i.e. the delete is safe to proceed).
--
-- Permanent status = sold | written_off | refurbished | sent_for_refurbishment.
-- Reversible status = in_storage | reversed — these do NOT block deletion.

CREATE OR REPLACE FUNCTION public.get_blocking_scrap_for_issue_part(
    p_issue_part_id uuid
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'is_blocking',           true,
        'scrap_inventory_id',    si.id,
        'part_name',             si.part_name_snapshot,
        'status',                si.status,
        'downstream_record_type', CASE
            WHEN si.status = 'sold'                  THEN 'disposal'
            WHEN si.status = 'written_off'           THEN 'writeoff'
            WHEN si.status IN ('refurbished',
                               'sent_for_refurbishment') THEN 'refurbishment'
            ELSE NULL
        END,
        'downstream_record_id', CASE
            WHEN si.status = 'sold' THEN (
                SELECT sdi.disposal_id
                FROM   public.scrap_disposal_items sdi
                WHERE  sdi.scrap_inventory_id = si.id
                LIMIT  1
            )
            WHEN si.status = 'written_off' THEN (
                SELECT swi.writeoff_id
                FROM   public.scrap_writeoff_items swi
                WHERE  swi.scrap_inventory_id = si.id
                LIMIT  1
            )
            ELSE NULL
        END
    )
    FROM  public.scrap_inventory si
    WHERE si.source_issue_part_id = p_issue_part_id
      AND si.status IN (
              'sold', 'written_off',
              'refurbished', 'sent_for_refurbishment'
          )
    LIMIT 1
$$;

-- ── Verification ─────────────────────────────────────────────────────────────

SELECT routine_name, routine_type
FROM   information_schema.routines
WHERE  routine_schema = 'public'
  AND  routine_name   = 'get_blocking_scrap_for_issue_part';

ROLLBACK; -- change to COMMIT once output looks correct
