BEGIN;

-- ── Scrap Inventory Module — Phase 5 Fix ─────────────────────────────────────
-- Relax source_issue_part_id FKs to ON DELETE SET NULL on both
-- scrap_inventory and scrap_excluded_parts.
--
-- Motivation: delete_issue_part_with_scrap_check reverses any in_storage scrap
-- entry before calling DELETE on issue_parts. Without this change, the NO ACTION
-- FK fires anyway (evaluated at statement end) and blocks the DELETE even after
-- reversal. Making the columns nullable + SET NULL lets the issue_parts row be
-- physically removed while preserving the scrap/excluded rows with all snapshot
-- fields intact for audit purposes. Reversed rows remain; only the FK pointer
-- becomes NULL.

-- ── scrap_inventory ───────────────────────────────────────────────────────────

ALTER TABLE public.scrap_inventory
    ALTER COLUMN source_issue_part_id DROP NOT NULL;

ALTER TABLE public.scrap_inventory
    DROP CONSTRAINT scrap_inventory_source_issue_part_fkey;

ALTER TABLE public.scrap_inventory
    ADD CONSTRAINT scrap_inventory_source_issue_part_fkey
    FOREIGN KEY (source_issue_part_id)
    REFERENCES public.issue_parts(id)
    ON DELETE SET NULL;

-- ── scrap_excluded_parts ──────────────────────────────────────────────────────

ALTER TABLE public.scrap_excluded_parts
    ALTER COLUMN source_issue_part_id DROP NOT NULL;

ALTER TABLE public.scrap_excluded_parts
    DROP CONSTRAINT scrap_excluded_parts_source_issue_part_fkey;

ALTER TABLE public.scrap_excluded_parts
    ADD CONSTRAINT scrap_excluded_parts_source_issue_part_fkey
    FOREIGN KEY (source_issue_part_id)
    REFERENCES public.issue_parts(id)
    ON DELETE SET NULL;

-- ── Verification ─────────────────────────────────────────────────────────────
-- Expect both rows to return confdeltype = 'n' (SET NULL).

SELECT conname, confdeltype
FROM   pg_constraint
WHERE  conname IN (
    'scrap_inventory_source_issue_part_fkey',
    'scrap_excluded_parts_source_issue_part_fkey'
);

ROLLBACK; -- change to COMMIT once output looks correct
