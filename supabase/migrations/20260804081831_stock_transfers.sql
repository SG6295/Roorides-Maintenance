-- Moving parts between workshops.
--
-- One step: stock leaves the source and lands at the destination in the same
-- transaction. There is no in-transit state. A transfer cannot be edited or undone;
-- a mistake is corrected by transferring back, so the trail stays honest.

CREATE TABLE IF NOT EXISTS public.stock_transfers (
    id                 uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    from_location_id   uuid NOT NULL REFERENCES public.workshop_locations(id),
    to_location_id     uuid NOT NULL REFERENCES public.workshop_locations(id),
    notes              text,
    transferred_by     uuid REFERENCES public.users(id),
    transferred_at     timestamp without time zone NOT NULL DEFAULT now(),
    CONSTRAINT stock_transfers_distinct_locations CHECK (from_location_id <> to_location_id)
);

CREATE INDEX IF NOT EXISTS stock_transfers_from_idx ON public.stock_transfers (from_location_id);
CREATE INDEX IF NOT EXISTS stock_transfers_to_idx   ON public.stock_transfers (to_location_id);
CREATE INDEX IF NOT EXISTS stock_transfers_date_idx ON public.stock_transfers (transferred_at DESC);

CREATE TABLE IF NOT EXISTS public.stock_transfer_items (
    id          uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    transfer_id uuid NOT NULL REFERENCES public.stock_transfers(id) ON DELETE CASCADE,
    part_id     uuid NOT NULL REFERENCES public.parts(id),
    quantity    numeric(10,2) NOT NULL,
    CONSTRAINT stock_transfer_items_quantity_positive CHECK (quantity > 0)
);

CREATE INDEX IF NOT EXISTS stock_transfer_items_transfer_idx ON public.stock_transfer_items (transfer_id);
CREATE INDEX IF NOT EXISTS stock_transfer_items_part_idx     ON public.stock_transfer_items (part_id);

COMMENT ON TABLE public.stock_transfers IS
    'Audit trail of parts moved between workshops. Immutable: correct a mistake with a transfer in the opposite direction.';

-- The only supported way to move stock. Validates availability, records the transfer
-- and moves every line atomically: if one part is short, nothing moves.
CREATE OR REPLACE FUNCTION public.transfer_stock(
    p_from  uuid,
    p_to    uuid,
    p_items jsonb,
    p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_transfer_id uuid;
    v_role        text;
    r             RECORD;
    v_count       integer := 0;
BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = auth.uid();
    IF v_role IS NULL OR v_role NOT IN ('maintenance_exec', 'super_admin') THEN
        RAISE EXCEPTION 'Only a maintenance executive or super admin can move stock between workshops.';
    END IF;

    IF p_from = p_to THEN
        RAISE EXCEPTION 'Source and destination workshop must be different.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_from AND is_active) THEN
        RAISE EXCEPTION 'The source workshop is not an active location.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.workshop_locations WHERE id = p_to AND is_active) THEN
        RAISE EXCEPTION 'The destination workshop is not an active location.';
    END IF;

    INSERT INTO public.stock_transfers (from_location_id, to_location_id, notes, transferred_by)
    VALUES (p_from, p_to, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid())
    RETURNING id INTO v_transfer_id;

    FOR r IN
        SELECT (elem->>'part_id')::uuid  AS part_id,
               (elem->>'quantity')::numeric AS quantity
        FROM   jsonb_array_elements(p_items) AS elem
    LOOP
        IF r.part_id IS NULL OR r.quantity IS NULL OR r.quantity <= 0 THEN
            RAISE EXCEPTION 'Every line needs a part and a quantity greater than zero.';
        END IF;

        -- Raises with a readable message if the source is short of this part.
        PERFORM public.apply_part_stock_delta(r.part_id, p_from, -r.quantity);
        PERFORM public.apply_part_stock_delta(r.part_id, p_to,    r.quantity);

        INSERT INTO public.stock_transfer_items (transfer_id, part_id, quantity)
        VALUES (v_transfer_id, r.part_id, r.quantity);

        v_count := v_count + 1;
    END LOOP;

    IF v_count = 0 THEN
        RAISE EXCEPTION 'Select at least one part to move.';
    END IF;

    RETURN v_transfer_id;
END;
$$;

ALTER TABLE public.stock_transfers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transfer_items ENABLE ROW LEVEL SECURITY;

-- Readable by the roles that can see inventory. Writes go through transfer_stock()
-- only, which is SECURITY DEFINER, so no INSERT/UPDATE/DELETE policies are granted.
DROP POLICY IF EXISTS "Exec and finance view stock_transfers" ON public.stock_transfers;
CREATE POLICY "Exec and finance view stock_transfers"
    ON public.stock_transfers FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('maintenance_exec', 'super_admin', 'finance')
    ));

DROP POLICY IF EXISTS "Exec and finance view stock_transfer_items" ON public.stock_transfer_items;
CREATE POLICY "Exec and finance view stock_transfer_items"
    ON public.stock_transfer_items FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('maintenance_exec', 'super_admin', 'finance')
    ));
