-- Workshop locations: the physical workshops where repairs happen and parts are held.
-- Distinct from public.sites, which are the customer/operational sites where vehicles run.
--
-- The two seed rows use fixed UUIDs so that the NOT NULL DEFAULTs added in later
-- migrations resolve to the same location in staging and production.

CREATE TABLE IF NOT EXISTS public.workshop_locations (
    id         uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    name       text NOT NULL,
    address    text,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamp without time zone DEFAULT now()
);

-- Case-insensitive uniqueness so "Bannerghatta" and "bannerghatta" can't coexist.
CREATE UNIQUE INDEX IF NOT EXISTS workshop_locations_name_lower_key
    ON public.workshop_locations (lower(name));

COMMENT ON TABLE public.workshop_locations IS
    'Physical workshops. Parts stock, job cards and scrap are located at one of these. Not the same as public.sites.';

INSERT INTO public.workshop_locations (id, name, address) VALUES
    ('a1e1d4c0-0000-4000-8000-000000000001', 'Bannerghatta', NULL),
    ('a1e1d4c0-0000-4000-8000-000000000002', 'Mahadevpura',  NULL)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.workshop_locations ENABLE ROW LEVEL SECURITY;

-- Everyone signed in needs to read locations (they appear on job cards, inventory, scrap).
DROP POLICY IF EXISTS "Authenticated read workshop_locations" ON public.workshop_locations;
CREATE POLICY "Authenticated read workshop_locations"
    ON public.workshop_locations FOR SELECT
    USING (auth.role() = 'authenticated');

-- Only super admins maintain the list (same pattern as sla_rules / holidays).
DROP POLICY IF EXISTS "Super admins insert workshop_locations" ON public.workshop_locations;
CREATE POLICY "Super admins insert workshop_locations"
    ON public.workshop_locations FOR INSERT
    WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "Super admins update workshop_locations" ON public.workshop_locations;
CREATE POLICY "Super admins update workshop_locations"
    ON public.workshop_locations FOR UPDATE
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- Deliberately no DELETE policy: locations are deactivated, never deleted, so that
-- historical job cards and invoices keep resolving to a real row.
