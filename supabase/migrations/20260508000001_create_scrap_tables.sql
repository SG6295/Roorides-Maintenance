BEGIN;

-- ── Scrap Inventory Module — Phase 1 ─────────────────────────────────────────
-- Migration 2/3: Tables, issue_parts columns, indexes, RLS policies.

-- ── 1. issue_parts: add outsource disposition columns ────────────────────────

ALTER TABLE public.issue_parts
    ADD COLUMN outsource_part_disposition       public.outsource_part_disposition,
    ADD COLUMN outsource_vendor_credit_amount   numeric(10,2);

ALTER TABLE public.issue_parts
    ADD CONSTRAINT issue_parts_outsource_credit_consistency
    CHECK (
        (outsource_part_disposition = 'retained_by_vendor_with_credit')
        =
        (outsource_vendor_credit_amount IS NOT NULL)
    );

-- ── 2. scrap_inventory ───────────────────────────────────────────────────────

CREATE TABLE public.scrap_inventory (
    id                                      uuid        NOT NULL DEFAULT extensions.uuid_generate_v4(),
    source_ticket_id                        uuid        NOT NULL,
    source_job_card_id                      uuid        NOT NULL,
    source_issue_id                         uuid        NOT NULL,
    source_issue_part_id                    uuid        NOT NULL,
    source_vehicle_number                   text        NOT NULL,
    part_id_snapshot                        uuid,
    part_name_snapshot                      text        NOT NULL,
    part_number_snapshot                    text,
    quantity_snapshot                       numeric(10,2) NOT NULL,
    unit_snapshot                           text        NOT NULL,
    description                             text,
    notes                                   text,
    estimated_value                         numeric(10,2),
    photos                                  text[]      NOT NULL DEFAULT '{}',
    status                                  public.scrap_item_status NOT NULL DEFAULT 'in_storage',
    received_by                             uuid,
    received_at                             timestamptz,
    current_location                        text,
    outsource_part_disposition_snapshot     public.outsource_part_disposition,
    outsource_vendor_credit_amount_snapshot numeric(10,2),
    created_at                              timestamptz NOT NULL DEFAULT now(),
    created_by                              uuid        NOT NULL,
    updated_at                              timestamptz NOT NULL DEFAULT now(),
    updated_by                              uuid,

    CONSTRAINT scrap_inventory_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_inventory_source_ticket_fkey
        FOREIGN KEY (source_ticket_id)   REFERENCES public.tickets(id),
    CONSTRAINT scrap_inventory_source_job_card_fkey
        FOREIGN KEY (source_job_card_id) REFERENCES public.job_cards(id),
    CONSTRAINT scrap_inventory_source_issue_fkey
        FOREIGN KEY (source_issue_id)    REFERENCES public.issues(id),
    CONSTRAINT scrap_inventory_source_issue_part_fkey
        FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id),
    CONSTRAINT scrap_inventory_received_by_fkey
        FOREIGN KEY (received_by)        REFERENCES public.users(id),
    CONSTRAINT scrap_inventory_created_by_fkey
        FOREIGN KEY (created_by)         REFERENCES public.users(id),
    CONSTRAINT scrap_inventory_updated_by_fkey
        FOREIGN KEY (updated_by)         REFERENCES public.users(id)
);

ALTER TABLE public.scrap_inventory OWNER TO postgres;

-- ── 3. scrap_excluded_parts ──────────────────────────────────────────────────

CREATE TABLE public.scrap_excluded_parts (
    id                    uuid        NOT NULL DEFAULT extensions.uuid_generate_v4(),
    source_job_card_id    uuid        NOT NULL,
    source_issue_id       uuid        NOT NULL,
    source_issue_part_id  uuid        NOT NULL,
    part_id_snapshot      uuid,
    part_name_snapshot    text        NOT NULL,
    quantity_snapshot     numeric(10,2) NOT NULL,
    reason                public.scrap_exclusion_reason NOT NULL,
    notes                 text,
    excluded_by           uuid        NOT NULL,
    excluded_at           timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT scrap_excluded_parts_pkey
        PRIMARY KEY (id),
    CONSTRAINT scrap_excluded_parts_source_job_card_fkey
        FOREIGN KEY (source_job_card_id)   REFERENCES public.job_cards(id),
    CONSTRAINT scrap_excluded_parts_source_issue_fkey
        FOREIGN KEY (source_issue_id)      REFERENCES public.issues(id),
    CONSTRAINT scrap_excluded_parts_source_issue_part_fkey
        FOREIGN KEY (source_issue_part_id) REFERENCES public.issue_parts(id),
    CONSTRAINT scrap_excluded_parts_excluded_by_fkey
        FOREIGN KEY (excluded_by)          REFERENCES public.users(id)
);

ALTER TABLE public.scrap_excluded_parts OWNER TO postgres;

-- ── 4. Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX idx_scrap_inventory_job_card_id
    ON public.scrap_inventory USING btree (source_job_card_id);

CREATE INDEX idx_scrap_inventory_issue_part_id
    ON public.scrap_inventory USING btree (source_issue_part_id);

CREATE INDEX idx_scrap_inventory_status
    ON public.scrap_inventory USING btree (status);

CREATE INDEX idx_scrap_inventory_created_at
    ON public.scrap_inventory USING btree (created_at DESC);

CREATE INDEX idx_scrap_inventory_ticket_id
    ON public.scrap_inventory USING btree (source_ticket_id);

CREATE INDEX idx_scrap_excluded_parts_job_card_id
    ON public.scrap_excluded_parts USING btree (source_job_card_id);

CREATE INDEX idx_scrap_excluded_parts_issue_part_id
    ON public.scrap_excluded_parts USING btree (source_issue_part_id);

-- ── 5. Row Level Security ────────────────────────────────────────────────────

ALTER TABLE public.scrap_inventory        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scrap_excluded_parts   ENABLE ROW LEVEL SECURITY;

-- scrap_inventory: execs have full access
CREATE POLICY "Execs manage scrap_inventory"
    ON public.scrap_inventory
    AS PERMISSIVE FOR ALL TO authenticated
    USING (public.is_maintenance_exec())
    WITH CHECK (public.is_maintenance_exec());

-- scrap_inventory: finance sees all rows, no site restriction (matches "Finance view job cards")
CREATE POLICY "Finance view scrap_inventory"
    ON public.scrap_inventory
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE id = auth.uid() AND role = 'finance'
        )
    );

-- scrap_inventory: supervisors see scrap for their sites via job_cards.site → user_sites
CREATE POLICY "Supervisors view site scrap"
    ON public.scrap_inventory
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND EXISTS (
            SELECT 1 FROM public.job_cards jc
            WHERE jc.id = scrap_inventory.source_job_card_id
              AND jc.site IN (
                  SELECT s.name
                  FROM public.user_sites us
                  JOIN public.sites s ON s.id = us.site_id
                  WHERE us.user_id = auth.uid()
              )
        )
    );

-- scrap_excluded_parts: execs see all (SELECT only — immutable audit table)
CREATE POLICY "Execs view scrap_excluded_parts"
    ON public.scrap_excluded_parts
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (public.is_maintenance_exec());

-- scrap_excluded_parts: finance sees all rows
CREATE POLICY "Finance view scrap_excluded_parts"
    ON public.scrap_excluded_parts
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users
            WHERE id = auth.uid() AND role = 'finance'
        )
    );

-- scrap_excluded_parts: supervisors see entries for their sites
CREATE POLICY "Supervisors view site scrap excluded"
    ON public.scrap_excluded_parts
    AS PERMISSIVE FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.users u
            WHERE u.id = auth.uid() AND u.role = 'supervisor'
        )
        AND EXISTS (
            SELECT 1 FROM public.job_cards jc
            WHERE jc.id = scrap_excluded_parts.source_job_card_id
              AND jc.site IN (
                  SELECT s.name
                  FROM public.user_sites us
                  JOIN public.sites s ON s.id = us.site_id
                  WHERE us.user_id = auth.uid()
              )
        )
    );

-- ── Verification ─────────────────────────────────────────────────────────────

SELECT 'scrap_inventory columns' AS check_name,
    column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'scrap_inventory'
ORDER BY ordinal_position;

SELECT 'issue_parts new columns' AS check_name,
    column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'issue_parts'
  AND column_name IN ('outsource_part_disposition', 'outsource_vendor_credit_amount');

SELECT 'indexes' AS check_name, indexname, tablename
FROM pg_indexes
WHERE tablename IN ('scrap_inventory', 'scrap_excluded_parts')
ORDER BY tablename, indexname;

SELECT 'rls policies' AS check_name, tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('scrap_inventory', 'scrap_excluded_parts')
ORDER BY tablename, policyname;

ROLLBACK; -- change to COMMIT once output looks correct
