-- MAIN-131: which workshop serves each site ("Workshop hub mapping").
--
-- A table of its own rather than a column on public.sites: sites is owned by the
-- Roorides sync, which upserts it nightly. No row means the site is "Not assigned".
-- At most one workshop per site, hence site_id as the primary key.
--
-- Analytics uses it to turn a workshop pick into a set of site names.

CREATE TABLE IF NOT EXISTS public.site_workshops (
    site_id     uuid PRIMARY KEY REFERENCES public.sites(id),
    location_id uuid NOT NULL REFERENCES public.workshop_locations(id),
    updated_at  timestamp with time zone NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS site_workshops_location_id_idx
    ON public.site_workshops (location_id);

COMMENT ON TABLE public.site_workshops IS
    'Default workshop for each site (MAIN-131). No row = not assigned. Maintained by super_admin in Settings › Workshop Hub Mapping.';

ALTER TABLE public.site_workshops ENABLE ROW LEVEL SECURITY;

-- Same posture as workshop_locations: everyone signed in reads, super admins write.
DROP POLICY IF EXISTS "Authenticated read site_workshops" ON public.site_workshops;
CREATE POLICY "Authenticated read site_workshops"
    ON public.site_workshops FOR SELECT
    USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Super admins insert site_workshops" ON public.site_workshops;
CREATE POLICY "Super admins insert site_workshops"
    ON public.site_workshops FOR INSERT
    WITH CHECK (public.is_super_admin());

DROP POLICY IF EXISTS "Super admins update site_workshops" ON public.site_workshops;
CREATE POLICY "Super admins update site_workshops"
    ON public.site_workshops FOR UPDATE
    USING (public.is_super_admin())
    WITH CHECK (public.is_super_admin());

-- "Not assigned" is the absence of a row, so unassigning deletes it.
DROP POLICY IF EXISTS "Super admins delete site_workshops" ON public.site_workshops;
CREATE POLICY "Super admins delete site_workshops"
    ON public.site_workshops FOR DELETE
    USING (public.is_super_admin());

-- Pre-fill from the maintenance team's sheet (2026-11-11), matched exactly on the
-- site's full name in our system and listed here by site code. Sites that did not
-- match exactly — the sheet's NA rows, sites missing from the sheet, and SLK (the
-- sheet's "SLK Software Pvt. Ltd" is "Altimetrik India Pvt. Ltd" here) — start
-- unassigned. The workshop ids are the fixed seed ids from 20260804075631.
INSERT INTO public.site_workshops (site_id, location_id)
SELECT s.id, m.location_id
FROM (VALUES
    -- Bannerghatta
    ('AECS',   'a1e1d4c0-0000-4000-8000-000000000001'::uuid),
    ('AGRATA', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('ASLI',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('BOSCH',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('BVMGS',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('BWNS',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('CHIMES', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('DSUH',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('EARTH',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('EURO',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('GRAB',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('IFIM',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('ILB',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('ISLYEL', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('IWS',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('MSDGS',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('NVSEA',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('ORKLA',  'a1e1d4c0-0000-4000-8000-000000000001'),
    ('RATHIN', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('RTL',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('RYANEC', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('RYANKR', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('RYANMR', 'a1e1d4c0-0000-4000-8000-000000000001'),
    ('SJR',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('SVIS',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('TBA',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('TSAB',   'a1e1d4c0-0000-4000-8000-000000000001'),
    ('TSB',    'a1e1d4c0-0000-4000-8000-000000000001'),
    ('TSOR',   'a1e1d4c0-0000-4000-8000-000000000001'),
    -- Mahadevpura
    ('BWIS',   'a1e1d4c0-0000-4000-8000-000000000002'),
    ('DIA',    'a1e1d4c0-0000-4000-8000-000000000002'),
    ('DIYA',   'a1e1d4c0-0000-4000-8000-000000000002'),
    ('ESG',    'a1e1d4c0-0000-4000-8000-000000000002'),
    ('KUNS',   'a1e1d4c0-0000-4000-8000-000000000002'),
    ('MSDGSG', 'a1e1d4c0-0000-4000-8000-000000000002'),
    ('NPSKRP', 'a1e1d4c0-0000-4000-8000-000000000002'),
    ('PGMS',   'a1e1d4c0-0000-4000-8000-000000000002'),
    ('RYANHM', 'a1e1d4c0-0000-4000-8000-000000000002'),
    ('RYANSR', 'a1e1d4c0-0000-4000-8000-000000000002'),
    ('SJRHBR', 'a1e1d4c0-0000-4000-8000-000000000002'),
    ('TBSW',   'a1e1d4c0-0000-4000-8000-000000000002'),
    ('WSA',    'a1e1d4c0-0000-4000-8000-000000000002')
) AS m(site_name, location_id)
JOIN public.sites s ON s.name = m.site_name
ON CONFLICT (site_id) DO NOTHING;
