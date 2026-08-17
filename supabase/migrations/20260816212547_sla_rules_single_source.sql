-- MAIN-47: SLA Settings edits sla_rules, but deadlines are computed from sla_rules_config.
--
-- Two tables held SLA day-counts. The settings page read and wrote `sla_rules`;
-- calculate_issue_sla_dynamic() has always read `sla_rules_config`. So editing a rule
-- in the UI changed a row nothing consumed, and the two had already drifted:
-- `sla_rules.category` is plain text and carried "GPS/Camera" with no AdBlue row at all,
-- while `sla_rules_config` is enum-constrained and matches issue_category exactly.
--
-- This makes sla_rules_config the single source and removes the decoy.

-- ── 1. Lock down sla_rules_config ────────────────────────────────────────────
--
-- The table the triggers actually read had RLS disabled while sitting in the
-- PostgREST-exposed public schema, with INSERT/UPDATE/DELETE/TRUNCATE granted to
-- anon and authenticated. The anon key ships in the frontend bundle, so the SLA
-- rules driving every deadline were world-writable. Supabase's linter flagged it
-- at ERROR level (rls_disabled_in_public).
--
-- The protection had gone on `sla_rules` — the table nothing reads. These policies
-- mirror the ones it had.

ALTER TABLE public.sla_rules_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Everyone can read SLA rules config"
    ON public.sla_rules_config
    FOR SELECT
    USING (true);

CREATE POLICY "Super admins can update SLA rules config"
    ON public.sla_rules_config
    FOR UPDATE
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- The rule set is a fixed grid of issue_category x issue_severity: rows are edited,
-- never added or removed. No INSERT/DELETE policy is created, so RLS denies both.
--
-- TRUNCATE is revoked rather than left to RLS: unlike INSERT/UPDATE/DELETE, TRUNCATE
-- is NOT subject to row security, so enabling RLS alone would not have stopped it.
REVOKE INSERT, DELETE, TRUNCATE ON public.sla_rules_config FROM anon, authenticated;

-- ── 2. Retire sla_rules ──────────────────────────────────────────────────────
--
-- Superseded by sla_rules_config, whose 14 rows (7 categories x Major/Minor) already
-- cover everything these 12 held. Day values agreed wherever the categories lined up,
-- so nothing is lost. Dropping rather than renaming: a rename in staging ahead of prod
-- breaks the prod->staging seed, a drop does not (the seed enumerates staging's tables).
--
-- For the record, the contents at drop time:
--   Major:  Body 30, Electrical 7, GPS/Camera 3, Mechanical 15, Other 7, Tyre 15
--   Minor:  Body 3,  Electrical 3, GPS/Camera 3, Mechanical 3,  Other 3, Tyre 3

DROP TABLE IF EXISTS public.sla_rules;
