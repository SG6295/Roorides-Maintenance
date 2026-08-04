-- Location on job cards, purchase invoices and scrap.
--
-- All three default to Bannerghatta, the original workshop, which is also what the
-- existing rows are backfilled to. The DEFAULT is required so that a prod -> staging
-- sync of rows written before this migration still satisfies NOT NULL.

-- Job cards: where the repair is carried out, and the location parts are drawn from.
ALTER TABLE public.job_cards
    ADD COLUMN IF NOT EXISTS location_id uuid NOT NULL
        DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'
        REFERENCES public.workshop_locations(id);

CREATE INDEX IF NOT EXISTS job_cards_location_idx ON public.job_cards (location_id);

COMMENT ON COLUMN public.job_cards.location_id IS
    'Workshop where the repair happens. InHouse cards consume stock from this location. Distinct from job_cards.site, which is the customer site the vehicle runs at.';

-- Purchase invoices: one invoice inwards to exactly one location (all its lines).
ALTER TABLE public.purchase_invoices
    ADD COLUMN IF NOT EXISTS location_id uuid NOT NULL
        DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'
        REFERENCES public.workshop_locations(id);

CREATE INDEX IF NOT EXISTS purchase_invoices_location_idx ON public.purchase_invoices (location_id);

COMMENT ON COLUMN public.purchase_invoices.location_id IS
    'Workshop all line items on this invoice are inwarded to. One invoice cannot span two locations.';

-- Scrap: salvage sits at the workshop that removed it.
ALTER TABLE public.scrap_inventory
    ADD COLUMN IF NOT EXISTS location_id uuid NOT NULL
        DEFAULT 'a1e1d4c0-0000-4000-8000-000000000001'
        REFERENCES public.workshop_locations(id);

CREATE INDEX IF NOT EXISTS scrap_inventory_location_idx ON public.scrap_inventory (location_id);

COMMENT ON COLUMN public.scrap_inventory.location_id IS
    'Workshop holding this salvage item, inherited from the source job card. Supersedes the unused free-text current_location column.';

-- Existing scrap follows its source job card (all Bannerghatta today, but keeps the
-- two columns consistent should this migration ever run against other data).
UPDATE public.scrap_inventory s
SET    location_id = jc.location_id
FROM   public.job_cards jc
WHERE  jc.id = s.source_job_card_id
  AND  s.location_id IS DISTINCT FROM jc.location_id;

-- New scrap inherits the workshop of the job card it came off.
CREATE OR REPLACE FUNCTION public.set_scrap_location_from_job_card()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    SELECT jc.location_id INTO NEW.location_id
    FROM   public.job_cards jc
    WHERE  jc.id = NEW.source_job_card_id;

    IF NEW.location_id IS NULL THEN
        NEW.location_id := 'a1e1d4c0-0000-4000-8000-000000000001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_scrap_location ON public.scrap_inventory;
CREATE TRIGGER trg_set_scrap_location
    BEFORE INSERT ON public.scrap_inventory
    FOR EACH ROW EXECUTE FUNCTION public.set_scrap_location_from_job_card();
