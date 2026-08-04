-- Per-location parts stock.
--
-- parts.quantity_in_stock was a single scalar per part. It now becomes a derived
-- roll-up of part_stock, kept in sync by a trigger, so every existing screen and
-- query that reads the global number keeps working unchanged.

CREATE TABLE IF NOT EXISTS public.part_stock (
    part_id     uuid NOT NULL REFERENCES public.parts(id) ON DELETE CASCADE,
    location_id uuid NOT NULL REFERENCES public.workshop_locations(id),
    quantity    numeric(10,2) NOT NULL DEFAULT 0,
    updated_at  timestamp without time zone NOT NULL DEFAULT now(),
    PRIMARY KEY (part_id, location_id),
    CONSTRAINT part_stock_quantity_nonneg CHECK (quantity >= 0)
);

CREATE INDEX IF NOT EXISTS part_stock_location_idx ON public.part_stock (location_id);

COMMENT ON TABLE public.part_stock IS
    'Authoritative stock per part per workshop location. parts.quantity_in_stock is the derived total.';

-- Backfill: all existing stock belongs to Bannerghatta, the original workshop.
--
-- 13 parts carried a negative balance at migration time (parts consumed on job cards
-- that were never purchased through the system). A negative balance is not a real
-- physical state and the quantity >= 0 constraint rejects it, so those are clamped to 0.
-- The bi-monthly inventory audit (MAIN-30) reconciles them against a physical count.
-- The resync below then corrects parts.quantity_in_stock from -11 etc. to 0.
INSERT INTO public.part_stock (part_id, location_id, quantity)
SELECT p.id, 'a1e1d4c0-0000-4000-8000-000000000001', GREATEST(p.quantity_in_stock, 0)
FROM   public.parts p
ON CONFLICT (part_id, location_id) DO NOTHING;

-- Keep parts.quantity_in_stock equal to the sum of that part's location rows.
CREATE OR REPLACE FUNCTION public.sync_part_total_stock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_part_id uuid := COALESCE(NEW.part_id, OLD.part_id);
BEGIN
    UPDATE public.parts p
    SET    quantity_in_stock = COALESCE(
               (SELECT SUM(ps.quantity) FROM public.part_stock ps WHERE ps.part_id = v_part_id),
               0)
    WHERE  p.id = v_part_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_part_total_stock ON public.part_stock;
CREATE TRIGGER trg_sync_part_total_stock
    AFTER INSERT OR UPDATE OR DELETE ON public.part_stock
    FOR EACH ROW EXECUTE FUNCTION public.sync_part_total_stock();

-- The backfill above ran before the trigger existed, so bring the totals in line once.
-- This is what clears the 13 negative balances on parts.quantity_in_stock.
UPDATE public.parts p
SET    quantity_in_stock = COALESCE(
           (SELECT SUM(ps.quantity) FROM public.part_stock ps WHERE ps.part_id = p.id), 0)
WHERE  p.quantity_in_stock IS DISTINCT FROM COALESCE(
           (SELECT SUM(ps.quantity) FROM public.part_stock ps WHERE ps.part_id = p.id), 0);

-- Helper used by every stock trigger: move a delta into (part, location), creating
-- the row on first use. Raises a readable error when a location would go negative.
CREATE OR REPLACE FUNCTION public.apply_part_stock_delta(
    p_part_id     uuid,
    p_location_id uuid,
    p_delta       numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_available numeric;
    v_part      text;
    v_location  text;
BEGIN
    IF p_location_id IS NULL THEN
        RAISE EXCEPTION 'Cannot change stock without a workshop location.';
    END IF;

    INSERT INTO public.part_stock (part_id, location_id, quantity)
    VALUES (p_part_id, p_location_id, 0)
    ON CONFLICT (part_id, location_id) DO NOTHING;

    -- Lock the row so two concurrent consumers can't both pass the check below.
    SELECT quantity INTO v_available
    FROM   public.part_stock
    WHERE  part_id = p_part_id AND location_id = p_location_id
    FOR UPDATE;

    IF v_available + p_delta < 0 THEN
        SELECT name INTO v_part     FROM public.parts              WHERE id = p_part_id;
        SELECT name INTO v_location FROM public.workshop_locations WHERE id = p_location_id;
        RAISE EXCEPTION 'Not enough stock: % has % available at %, needed %.',
            COALESCE(v_part, 'part'), v_available, COALESCE(v_location, 'this location'), abs(p_delta);
    END IF;

    UPDATE public.part_stock
    SET    quantity = quantity + p_delta,
           updated_at = now()
    WHERE  part_id = p_part_id AND location_id = p_location_id;
END;
$$;

ALTER TABLE public.part_stock ENABLE ROW LEVEL SECURITY;

-- Mirrors the parts policies: everyone signed in can see stock, exec/finance manage it.
DROP POLICY IF EXISTS "Authenticated users view part_stock" ON public.part_stock;
CREATE POLICY "Authenticated users view part_stock"
    ON public.part_stock FOR SELECT
    USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Exec and finance manage part_stock" ON public.part_stock;
CREATE POLICY "Exec and finance manage part_stock"
    ON public.part_stock
    USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('maintenance_exec', 'super_admin', 'finance')
    ));
