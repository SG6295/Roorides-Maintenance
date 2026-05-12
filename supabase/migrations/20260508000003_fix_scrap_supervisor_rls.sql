BEGIN;

-- Fix: supervisor RLS policies on scrap_inventory and scrap_excluded_parts used a
-- direct job_cards join that fails because supervisors have no job_cards SELECT policy.
-- A SECURITY DEFINER helper function bypasses job_cards RLS (runs as postgres)
-- while still enforcing the site–user relationship via auth.uid().

CREATE OR REPLACE FUNCTION public.job_card_site_accessible_to_user(p_job_card_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.job_cards jc
        WHERE jc.id = p_job_card_id
          AND jc.site IN (
              SELECT s.name
              FROM public.user_sites us
              JOIN public.sites s ON s.id = us.site_id
              WHERE us.user_id = auth.uid()
          )
    );
$$;

REVOKE ALL ON FUNCTION public.job_card_site_accessible_to_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.job_card_site_accessible_to_user(uuid) TO authenticated;

DROP POLICY IF EXISTS "Supervisors view site scrap" ON public.scrap_inventory;
CREATE POLICY "Supervisors view site scrap"
    ON public.scrap_inventory
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND public.job_card_site_accessible_to_user(source_job_card_id)
    );

DROP POLICY IF EXISTS "Supervisors view site scrap excluded" ON public.scrap_excluded_parts;
CREATE POLICY "Supervisors view site scrap excluded"
    ON public.scrap_excluded_parts
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND public.job_card_site_accessible_to_user(source_job_card_id)
    );

-- Verification
SELECT proname, prosecdef, proowner::regrole
FROM pg_proc
WHERE proname = 'job_card_site_accessible_to_user';

SELECT policyname, cmd
FROM pg_policies
WHERE tablename IN ('scrap_inventory', 'scrap_excluded_parts')
  AND policyname LIKE 'Supervisors%'
ORDER BY tablename, policyname;

ROLLBACK; -- change to COMMIT once output looks correct
