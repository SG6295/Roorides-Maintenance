BEGIN;

-- ── Scrap Inventory Module — Phase 1 ─────────────────────────────────────────
-- Migration 1/3: Create enum types used by scrap tables and issue_parts.

CREATE TYPE public.scrap_item_status AS ENUM (
    'in_storage',
    'sent_for_refurbishment',
    'refurbished',
    'sold',
    'written_off',
    'reversed'
);

CREATE TYPE public.scrap_exclusion_reason AS ENUM (
    'consumable',
    'destroyed_on_removal',
    'retained_by_vendor',
    'other'
);

CREATE TYPE public.outsource_part_disposition AS ENUM (
    'returned_to_nvs',
    'retained_by_vendor',
    'retained_by_vendor_with_credit'
);

-- ── Verification ─────────────────────────────────────────────────────────────

SELECT t.typname, e.enumlabel, e.enumsortorder
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typname IN ('scrap_item_status', 'scrap_exclusion_reason', 'outsource_part_disposition')
  AND t.typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY t.typname, e.enumsortorder;

ROLLBACK; -- change to COMMIT once output looks correct
