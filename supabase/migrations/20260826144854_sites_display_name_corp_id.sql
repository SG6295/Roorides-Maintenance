-- MAIN-52: full school names on the site pickers.
--
-- sites.name is the short code from the Roorides vehicle feed (CSS, MSDGS, TSB) and is
-- the value every free-text site column matches on, so it stays exactly as it is. These
-- two columns are the human-readable layer on top, populated by sync-roorides-vehicles
-- from GET /api/ManageCorp/GetAllCorporation/0/0 and joined on corpShortName.
--
-- Both are nullable: a site only gets a name once the mapping endpoint returns a
-- corporation whose short name matches, and formatSiteLabel() falls back to the bare
-- code until then. Nothing reads these for authorisation — they are display only.

ALTER TABLE public.sites
    ADD COLUMN IF NOT EXISTS display_name text,
    ADD COLUMN IF NOT EXISTS corp_id integer;

COMMENT ON COLUMN public.sites.display_name IS
    'Full school name (corpName) from the Roorides corporation mapping. Display only; NULL until the sync finds a matching corpShortName.';

COMMENT ON COLUMN public.sites.corp_id IS
    'Roorides corpId for this site. Display only; NULL until the sync finds a matching corpShortName.';
