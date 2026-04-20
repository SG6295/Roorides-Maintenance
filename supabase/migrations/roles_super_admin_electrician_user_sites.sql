-- ============================================================
-- Add super_admin + electrician roles; user_sites junction table;
-- update all RLS policies accordingly.
-- ============================================================

-- 1. Update role constraint
ALTER TABLE public.users DROP CONSTRAINT users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check
  CHECK (role = ANY (ARRAY[
    'supervisor'::text, 'maintenance_exec'::text, 'finance'::text,
    'mechanic'::text, 'electrician'::text, 'super_admin'::text
  ]));

-- 2. Update is_maintenance_exec() to include super_admin
--    Every existing policy using this fn automatically gains super_admin access.
CREATE OR REPLACE FUNCTION public.is_maintenance_exec()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec', 'super_admin')
  )
$$;

-- 3. New is_super_admin() helper
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'super_admin'
  )
$$;

-- 4. user_sites junction table (supervisor <-> multiple sites)
CREATE TABLE IF NOT EXISTS public.user_sites (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  site_id    uuid NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, site_id)
);

ALTER TABLE public.user_sites ENABLE ROW LEVEL SECURITY;

-- 5. Migrate existing single-site supervisor assignments into user_sites
INSERT INTO public.user_sites (user_id, site_id)
SELECT u.id, s.id
FROM public.users u
JOIN public.sites s ON s.name = u.site
WHERE u.role = 'supervisor' AND u.site IS NOT NULL
ON CONFLICT DO NOTHING;

-- 6. RLS for user_sites
CREATE POLICY "user_sites_select" ON public.user_sites FOR SELECT
  USING (user_id = auth.uid() OR is_maintenance_exec());

CREATE POLICY "user_sites_insert" ON public.user_sites FOR INSERT
  WITH CHECK (is_maintenance_exec());

CREATE POLICY "user_sites_delete" ON public.user_sites FOR DELETE
  USING (is_maintenance_exec());

-- 7. Clean up duplicate users policies (is_maintenance_exec covers super_admin already)
DROP POLICY IF EXISTS "Exec sees all users" ON public.users;
DROP POLICY IF EXISTS "Users see own profile" ON public.users;

-- 8. Tickets: multi-site supervisor access
DROP POLICY IF EXISTS "Supervisors see own site tickets" ON public.tickets;
DROP POLICY IF EXISTS "Site-restricted ticket access" ON public.tickets;

CREATE POLICY "Supervisors see own site tickets" ON public.tickets FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'supervisor')
    AND site IN (
      SELECT s.name FROM public.user_sites us
      JOIN public.sites s ON s.id = us.site_id
      WHERE us.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Supervisors and execs create tickets" ON public.tickets;
CREATE POLICY "Supervisors and execs create tickets" ON public.tickets FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role IN ('supervisor','maintenance_exec','super_admin'))
  );

-- 9. Issues: multi-site supervisor access
DROP POLICY IF EXISTS "Supervisors view site issues" ON public.issues;
CREATE POLICY "Supervisors view site issues" ON public.issues FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = issues.ticket_id
        AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'supervisor')
        AND t.site IN (
          SELECT s.name FROM public.user_sites us
          JOIN public.sites s ON s.id = us.site_id
          WHERE us.user_id = auth.uid()
        )
    )
  );

DROP POLICY IF EXISTS "Supervisors update own ratings" ON public.issues;
CREATE POLICY "Supervisors update own ratings" ON public.issues FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = issues.ticket_id
        AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'supervisor')
        AND t.site IN (
          SELECT s.name FROM public.user_sites us
          JOIN public.sites s ON s.id = us.site_id
          WHERE us.user_id = auth.uid()
        )
    )
  );

DROP POLICY IF EXISTS "Supervisors create issues" ON public.issues;
CREATE POLICY "Supervisors create issues" ON public.issues FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tickets t
      JOIN public.users u ON u.id = auth.uid()
      WHERE t.id = issues.ticket_id
        AND u.role = 'supervisor'
        AND t.site IN (
          SELECT s.name FROM public.user_sites us
          JOIN public.sites s ON s.id = us.site_id
          WHERE us.user_id = auth.uid()
        )
    )
  );

DROP POLICY IF EXISTS "Execs manage issues" ON public.issues;
CREATE POLICY "Execs manage issues" ON public.issues FOR ALL
  USING (is_maintenance_exec());

-- 10. Job cards
DROP POLICY IF EXISTS "Execs manage job cards" ON public.job_cards;
CREATE POLICY "Execs manage job cards" ON public.job_cards FOR ALL
  USING (is_maintenance_exec());

DROP POLICY IF EXISTS "Mechanics view assigned cards" ON public.job_cards;
CREATE POLICY "Mechanics view assigned cards" ON public.job_cards FOR SELECT
  USING (assigned_mechanic_id = auth.uid() OR is_maintenance_exec());

-- 11. Issue parts
DROP POLICY IF EXISTS "Mechanics delete issue parts on assigned cards" ON public.issue_parts;
CREATE POLICY "Mechanics delete issue parts on assigned cards" ON public.issue_parts FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM issues i JOIN job_cards jc ON jc.id = i.job_card_id
      WHERE i.id = issue_parts.issue_id
        AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())
    )
  );

DROP POLICY IF EXISTS "Mechanics insert issue parts" ON public.issue_parts;
CREATE POLICY "Mechanics insert issue parts" ON public.issue_parts FOR INSERT
  WITH CHECK (
    auth.uid() = added_by
    AND EXISTS (
      SELECT 1 FROM issues i JOIN job_cards jc ON jc.id = i.job_card_id
      WHERE i.id = issue_parts.issue_id
        AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())
    )
  );

DROP POLICY IF EXISTS "View issue parts" ON public.issue_parts;
CREATE POLICY "View issue parts" ON public.issue_parts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM issues i JOIN job_cards jc ON jc.id = i.job_card_id
      WHERE i.id = issue_parts.issue_id
        AND (jc.assigned_mechanic_id = auth.uid() OR is_maintenance_exec())
    )
  );

-- 12. SLA rules: only super_admin can write
DROP POLICY IF EXISTS "Execs can update SLA rules" ON public.sla_rules;
CREATE POLICY "Super admins can update SLA rules" ON public.sla_rules FOR UPDATE
  USING (is_super_admin()) WITH CHECK (is_super_admin());

-- 13. system_settings: only super_admin can write
DROP POLICY IF EXISTS "Execs can insert settings" ON public.system_settings;
DROP POLICY IF EXISTS "Execs can update settings" ON public.system_settings;
CREATE POLICY "Super admins can insert settings" ON public.system_settings FOR INSERT
  WITH CHECK (is_super_admin());
CREATE POLICY "Super admins can update settings" ON public.system_settings FOR UPDATE
  USING (is_super_admin()) WITH CHECK (is_super_admin());

-- 14. Holidays: only super_admin can write
DROP POLICY IF EXISTS "Execs can manage holidays" ON public.holidays;
CREATE POLICY "Super admins can insert holidays" ON public.holidays FOR INSERT
  WITH CHECK (is_super_admin());
CREATE POLICY "Super admins can update holidays" ON public.holidays FOR UPDATE
  USING (is_super_admin());
CREATE POLICY "Super admins can delete holidays" ON public.holidays FOR DELETE
  USING (is_super_admin());

-- 15. Part units
DROP POLICY IF EXISTS "Execs manage part_units" ON public.part_units;
CREATE POLICY "Execs manage part_units" ON public.part_units FOR ALL
  USING (is_maintenance_exec());

-- 16. Parts
DROP POLICY IF EXISTS "Exec and finance manage parts" ON public.parts;
CREATE POLICY "Exec and finance manage parts" ON public.parts FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));

-- 17. Purchase invoices
DROP POLICY IF EXISTS "Exec and finance insert invoices" ON public.purchase_invoices;
DROP POLICY IF EXISTS "Exec and finance view invoices" ON public.purchase_invoices;
DROP POLICY IF EXISTS "Exec and finance update invoices" ON public.purchase_invoices;
CREATE POLICY "Exec and finance insert invoices" ON public.purchase_invoices FOR INSERT
  WITH CHECK (auth.uid() = created_by AND EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));
CREATE POLICY "Exec and finance view invoices" ON public.purchase_invoices FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));
CREATE POLICY "Exec and finance update invoices" ON public.purchase_invoices FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));

-- 18. Purchase invoice items
DROP POLICY IF EXISTS "Exec and finance delete invoice items" ON public.purchase_invoice_items;
DROP POLICY IF EXISTS "Exec and finance insert invoice items" ON public.purchase_invoice_items;
DROP POLICY IF EXISTS "Exec and finance view invoice items" ON public.purchase_invoice_items;
DROP POLICY IF EXISTS "Exec and finance update invoice items" ON public.purchase_invoice_items;
CREATE POLICY "Exec and finance delete invoice items" ON public.purchase_invoice_items FOR DELETE
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));
CREATE POLICY "Exec and finance insert invoice items" ON public.purchase_invoice_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));
CREATE POLICY "Exec and finance view invoice items" ON public.purchase_invoice_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));
CREATE POLICY "Exec and finance update invoice items" ON public.purchase_invoice_items FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));

-- 19. Finance entries
DROP POLICY IF EXISTS "Finance sees all entries" ON public.finance_entries;
CREATE POLICY "Finance sees all entries" ON public.finance_entries FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('finance','maintenance_exec','super_admin')));
DROP POLICY IF EXISTS "Finance creates entries" ON public.finance_entries;
CREATE POLICY "Finance creates entries" ON public.finance_entries FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('finance','super_admin')));
DROP POLICY IF EXISTS "Finance updates entries" ON public.finance_entries;
CREATE POLICY "Finance updates entries" ON public.finance_entries FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('finance','super_admin')));

-- 20. Suppliers
DROP POLICY IF EXISTS "suppliers_auth_select" ON public.suppliers;
CREATE POLICY "suppliers_auth_select" ON public.suppliers FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin') AND is_active = true));
DROP POLICY IF EXISTS "suppliers_exec_update" ON public.suppliers;
CREATE POLICY "suppliers_exec_update" ON public.suppliers FOR UPDATE
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','super_admin') AND is_active = true));

-- 21. Vehicles
DROP POLICY IF EXISTS "Exec and finance manage vehicles" ON public.vehicles;
CREATE POLICY "Exec and finance manage vehicles" ON public.vehicles FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role IN ('maintenance_exec','finance','super_admin')));

-- 22. Promote sg@ to super_admin
UPDATE public.users SET role = 'super_admin' WHERE email = 'sg@nvstravelsolutions.in';
