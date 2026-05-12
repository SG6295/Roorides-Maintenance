-- ── Scrap Inventory Module — Phase 2 ─────────────────────────────────────────
-- Migration 3/5: scrap_writeoff and scrap_writeoff_items tables, indexes, RLS.

CREATE TABLE public.scrap_writeoff (
    id               uuid          NOT NULL DEFAULT extensions.uuid_generate_v4(),
    writeoff_date    date          NOT NULL,
    reason           public.scrap_writeoff_reason NOT NULL,
    description      text          NOT NULL,
    evidence_photos  text[]        NOT NULL DEFAULT '{}',
    notes            text,
    recorded_by      uuid          NOT NULL,
    recorded_at      timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT scrap_writeoff_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_writeoff_recorded_by_fkey
        FOREIGN KEY (recorded_by) REFERENCES public.users(id)
);

ALTER TABLE public.scrap_writeoff OWNER TO postgres;

CREATE TABLE public.scrap_writeoff_items (
    id                   uuid           NOT NULL DEFAULT extensions.uuid_generate_v4(),
    writeoff_id          uuid           NOT NULL,
    scrap_inventory_id   uuid           NOT NULL,
    part_name_snapshot   text           NOT NULL,
    quantity_snapshot    numeric(10,2)  NOT NULL,
    unit_snapshot        text           NOT NULL,
    created_at           timestamptz    NOT NULL DEFAULT now(),

    CONSTRAINT scrap_writeoff_items_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_writeoff_items_writeoff_fkey
        FOREIGN KEY (writeoff_id) REFERENCES public.scrap_writeoff(id),
    CONSTRAINT scrap_writeoff_items_scrap_inventory_fkey
        FOREIGN KEY (scrap_inventory_id) REFERENCES public.scrap_inventory(id),
    CONSTRAINT scrap_writeoff_items_unique_item_per_writeoff
        UNIQUE (writeoff_id, scrap_inventory_id)
);

ALTER TABLE public.scrap_writeoff_items OWNER TO postgres;

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX idx_scrap_writeoff_recorded_by
    ON public.scrap_writeoff USING btree (recorded_by);
CREATE INDEX idx_scrap_writeoff_writeoff_date
    ON public.scrap_writeoff USING btree (writeoff_date DESC);
CREATE INDEX idx_scrap_writeoff_items_writeoff_id
    ON public.scrap_writeoff_items USING btree (writeoff_id);
CREATE INDEX idx_scrap_writeoff_items_scrap_inventory_id
    ON public.scrap_writeoff_items USING btree (scrap_inventory_id);

-- ── Row Level Security ────────────────────────────────────────────────────────

ALTER TABLE public.scrap_writeoff        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrap_writeoff_items  ENABLE ROW LEVEL SECURITY;

-- scrap_writeoff: execs have full access
CREATE POLICY "Execs manage scrap_writeoff"
    ON public.scrap_writeoff
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_maintenance_exec())
    WITH CHECK (public.is_maintenance_exec());

-- scrap_writeoff: finance sees all rows
CREATE POLICY "Finance view scrap_writeoff"
    ON public.scrap_writeoff
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'finance')
    );

-- scrap_writeoff: supervisors see write-offs that include items from their site's job cards
CREATE POLICY "Supervisors view site scrap_writeoff"
    ON public.scrap_writeoff
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'supervisor')
        AND EXISTS (
            SELECT 1
            FROM public.scrap_writeoff_items swi
            JOIN public.scrap_inventory si ON si.id = swi.scrap_inventory_id
            WHERE swi.writeoff_id = scrap_writeoff.id
              AND public.job_card_site_accessible_to_user(si.source_job_card_id)
        )
    );

-- scrap_writeoff_items: execs have full access
CREATE POLICY "Execs manage scrap_writeoff_items"
    ON public.scrap_writeoff_items
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_maintenance_exec())
    WITH CHECK (public.is_maintenance_exec());

-- scrap_writeoff_items: finance sees all rows
CREATE POLICY "Finance view scrap_writeoff_items"
    ON public.scrap_writeoff_items
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'finance')
    );

-- scrap_writeoff_items: supervisors see items from their site's job cards
CREATE POLICY "Supervisors view site scrap_writeoff_items"
    ON public.scrap_writeoff_items
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'supervisor')
        AND EXISTS (
            SELECT 1 FROM public.scrap_inventory si
            WHERE si.id = scrap_writeoff_items.scrap_inventory_id
              AND public.job_card_site_accessible_to_user(si.source_job_card_id)
        )
    );
