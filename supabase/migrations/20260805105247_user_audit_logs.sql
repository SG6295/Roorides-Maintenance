-- User management audit log.
--
-- Deliberately separate from public.audit_logs: that table's SELECT policy is
-- `auth.role() = 'authenticated'`, so every logged-in user could read who was
-- promoted, demoted or had a password reset. This table is super_admin-only.
--
-- target_user_id and performed_by are intentionally NOT foreign keys. An
-- append-only audit log must survive deletion of its subject: ON DELETE CASCADE
-- would erase a user's whole history along with them, and ON DELETE SET NULL
-- would keep the row but lose which person it was about. Plain uuid columns keep
-- the id (entries still group by person) alongside the name/email snapshots
-- (entries still read correctly), whatever happens to the users row.
--
-- Only the service-role edge functions write here: there is no INSERT, UPDATE or
-- DELETE policy, so the log cannot be forged, skipped or edited from the browser.

CREATE TABLE IF NOT EXISTS public.user_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    target_user_id uuid NOT NULL,
    target_name text NOT NULL DEFAULT '',
    target_email text NOT NULL DEFAULT '',
    action text NOT NULL DEFAULT 'UPDATE',
    changed_fields text[] NOT NULL DEFAULT '{}',
    old_data jsonb NOT NULL DEFAULT '{}',
    new_data jsonb NOT NULL DEFAULT '{}',
    performed_by uuid,
    performed_by_name text NOT NULL DEFAULT '',
    performed_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT user_audit_logs_pkey PRIMARY KEY (id),
    CONSTRAINT user_audit_logs_action_check
        CHECK (action = ANY (ARRAY['CREATE'::text, 'UPDATE'::text, 'ACTIVATE'::text, 'DEACTIVATE'::text]))
);

CREATE INDEX IF NOT EXISTS user_audit_logs_performed_at_idx
    ON public.user_audit_logs (performed_at DESC);

CREATE INDEX IF NOT EXISTS user_audit_logs_target_idx
    ON public.user_audit_logs (target_user_id);

ALTER TABLE public.user_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_audit_logs_select ON public.user_audit_logs;
CREATE POLICY user_audit_logs_select ON public.user_audit_logs
    FOR SELECT USING (public.is_super_admin());

GRANT ALL ON TABLE public.user_audit_logs TO anon;
GRANT ALL ON TABLE public.user_audit_logs TO authenticated;
GRANT ALL ON TABLE public.user_audit_logs TO service_role;
