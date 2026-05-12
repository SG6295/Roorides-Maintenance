-- ── Scrap Inventory Module — Phase 2 ─────────────────────────────────────────
-- Migration 2/5: scrap_disposal and scrap_disposal_items tables, indexes, RLS.

CREATE TABLE public.scrap_disposal (
    id                 uuid           NOT NULL DEFAULT extensions.uuid_generate_v4(),
    disposal_date      date           NOT NULL,
    buyer_name         text           NOT NULL,
    buyer_contact      text,
    payment_mode       public.scrap_payment_mode NOT NULL,
    payment_reference  text,
    total_value        numeric(10,2)  NOT NULL,
    receipt_photos     text[]         NOT NULL DEFAULT '{}',
    notes              text,
    recorded_by        uuid           NOT NULL,
    recorded_at        timestamptz    NOT NULL DEFAULT now(),

    CONSTRAINT scrap_disposal_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_disposal_recorded_by_fkey
        FOREIGN KEY (recorded_by) REFERENCES public.users(id),
    CONSTRAINT scrap_disposal_payment_reference_consistency
        CHECK (
            (payment_mode = 'cash' AND payment_reference IS NULL)
            OR
            (payment_mode <> 'cash' AND payment_reference IS NOT NULL)
        )
);

ALTER TABLE public.scrap_disposal OWNER TO postgres;

CREATE TABLE public.scrap_disposal_items (
    id                   uuid           NOT NULL DEFAULT extensions.uuid_generate_v4(),
    disposal_id          uuid           NOT NULL,
    scrap_inventory_id   uuid           NOT NULL,
    value_allocated      numeric(10,2)  NOT NULL,
    part_name_snapshot   text           NOT NULL,
    quantity_snapshot    numeric(10,2)  NOT NULL,
    unit_snapshot        text           NOT NULL,
    created_at           timestamptz    NOT NULL DEFAULT now(),

    CONSTRAINT scrap_disposal_items_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_disposal_items_disposal_fkey
        FOREIGN KEY (disposal_id) REFERENCES public.scrap_disposal(id),
    CONSTRAINT scrap_disposal_items_scrap_inventory_fkey
        FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id),
    CONSTRAINT scrap_disposal_items_value_allocated_positive
        CHECK (value_allocated > 0),
    CONSTRAINT scrap_disposal_items_unique_item_per_disposal
        UNIQUE (disposal_id, scrap_inventory_id)
);

ALTER TABLE public.scrap_disposal_items OWNER TO postgres;

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX idx_scrap_disposal_recorded_by
    ON public.scrap_disposal USING btree (recorded_by);
CREATE INDEX idx_scrap_disposal_disposal_date
    ON public.scrap_disposal USING btree (disposal_date DESC);
CREATE INDEX idx_scrap_disposal_items_disposal_id
    ON public.scrap_disposal_items USING btree (disposal_id);
CREATE INDEX idx_scrap_disposal_items_scrap_inventory_id
    ON public.scrap_disposal_items USING btree (scrap_inventory_id);

-- ── Row Level Security ────────────────────────────────────────────────────────

ALTER TABLE public.scrap_disposal        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrap_disposal_items  ENABLE ROW LEVEL SECURITY;

-- scrap_disposal: execs have full access
CREATE POLICY "Execs manage scrap_disposal"
    ON public.scrap_disposal
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_maintenance_exec())
    WITH CHECK (public.is_maintenance_exec());

-- scrap_disposal: finance sees all rows (matches finance scrap_inventory access)
CREATE POLICY "Finance view scrap_disposal"
    ON public.scrap_disposal
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE id = auth.uid() AND role = 'finance'
        )
    );

-- scrap_disposal: supervisors see disposals that include items from their site's job cards
CREATE POLICY "Supervisors view site scrap_disposal"
    ON public.scrap_disposal
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND EXISTS (
            SELECT 1
            FROM public.scrap_disposal_items sdi
            JOIN public.scrap_inventory si ON si.id = sdi.scrap_inventory_id
            WHERE sdi.disposal_id = scrap_disposal.id
              AND public.job_card_site_accessible_to_user(si.source_job_card_id)
        )
    );

-- scrap_disposal_items: execs have full access
CREATE POLICY "Execs manage scrap_disposal_items"
    ON public.scrap_disposal_items
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_maintenance_exec())
    WITH CHECK (public.is_maintenance_exec());

-- scrap_disposal_items: finance sees all rows
CREATE POLICY "Finance view scrap_disposal_items"
    ON public.scrap_disposal_items
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE id = auth.uid() AND role = 'finance'
        )
    );

-- scrap_disposal_items: supervisors see items from their site's job cards
CREATE POLICY "Supervisors view site scrap_disposal_items"
    ON public.scrap_disposal_items
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND EXISTS (
            SELECT 1 FROM public.scrap_inventory si
            WHERE si.id = scrap_disposal_items.scrap_inventory_id
              AND public.job_card_site_accessible_to_user(si.source_job_card_id)
        )
    );
