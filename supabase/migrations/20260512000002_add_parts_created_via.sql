BEGIN;

-- ── Outsource Invoices — Phase 1 (2/3) ───────────────────────────────────────
-- Adds created_via column to parts.
--
-- 'manual'            — created through the Inventory / Parts Catalog UI
-- 'outsource_jobcard' — created inline while adding parts to an outsource job card
--
-- Adding a column with a constant DEFAULT is a metadata-only change in
-- Postgres 11+ (no table rewrite). Existing rows get 'manual' automatically.

ALTER TABLE public.parts
    ADD COLUMN IF NOT EXISTS created_via text
        NOT NULL
        DEFAULT 'manual'
        CHECK (created_via IN ('manual', 'outsource_jobcard'));

-- ── Verification ──────────────────────────────────────────────────────────────

SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'parts'
  AND column_name  = 'created_via';

ROLLBACK; -- change to COMMIT once output looks correct
