-- Physical stock counts (MAIN-30).
--
-- Finance counts a workshop's shelves on paper, then reconciles the result here. Until
-- now stock could only move through a purchase invoice, job-card consumption or a
-- transfer, so breakage, theft and unrecorded usage had no legitimate correction path.
--
-- Two things drive the shape of these tables:
--
--   1. An audit records what it FOUND, not what stock should become. system_qty is
--      snapshotted when the count sheet is generated and never changes; the variance is
--      derived from it. Parts legitimately consumed while the audit is open are applied
--      by their own triggers as usual, and completing the audit posts the variance on
--      top of whatever the live figure is by then. That way a mid-audit job card is
--      never silently reversed.
--
--   2. A completed audit is immutable. There is no reversal and no edit; a wrong count
--      is corrected by running another audit. Same principle as stock_transfers.
--
-- Writes go through the SECURITY DEFINER functions in the companion migration only, so
-- these tables carry SELECT policies and nothing else.

CREATE TABLE IF NOT EXISTS public.stock_audits (
    id                      uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    location_id             uuid NOT NULL REFERENCES public.workshop_locations(id),
    status                  text NOT NULL DEFAULT 'counting',
    notes                   text,

    -- Naive timestamps deliberately, matching stock_transfers.transferred_at,
    -- issue_parts.added_at and purchase_invoices.created_at. The movements query in the
    -- companion migration compares directly against all three; straddling timestamptz
    -- and timestamp would make every one of those comparisons timezone-dependent.
    started_by              uuid REFERENCES public.users(id),
    started_by_name         text NOT NULL DEFAULT '',
    started_at              timestamp without time zone NOT NULL DEFAULT now(),

    counts_uploaded_by      uuid REFERENCES public.users(id),
    counts_uploaded_by_name text NOT NULL DEFAULT '',
    counts_uploaded_at      timestamp without time zone,

    completed_by            uuid REFERENCES public.users(id),
    completed_by_name       text NOT NULL DEFAULT '',
    completed_at            timestamp without time zone,

    cancelled_by            uuid REFERENCES public.users(id),
    cancelled_by_name       text NOT NULL DEFAULT '',
    cancelled_at            timestamp without time zone,
    cancel_reason           text,

    -- Rollups, written once at completion so the summary never re-derives.
    total_parts             integer NOT NULL DEFAULT 0,
    variance_parts          integer NOT NULL DEFAULT 0,
    net_units               numeric(12,2) NOT NULL DEFAULT 0,
    net_value               numeric(14,2) NOT NULL DEFAULT 0,
    unvalued_parts          integer NOT NULL DEFAULT 0,

    CONSTRAINT stock_audits_status_check
        CHECK (status IN ('counting', 'review', 'completed', 'cancelled'))
);

CREATE INDEX IF NOT EXISTS stock_audits_location_idx ON public.stock_audits (location_id);
CREATE INDEX IF NOT EXISTS stock_audits_status_idx   ON public.stock_audits (status);
CREATE INDEX IF NOT EXISTS stock_audits_started_idx  ON public.stock_audits (started_at DESC);

-- Only one audit may be open at a workshop at a time. This index is the whole
-- enforcement: two concurrent start_stock_audit() calls cannot both win.
CREATE UNIQUE INDEX IF NOT EXISTS stock_audits_one_open_per_location
    ON public.stock_audits (location_id)
    WHERE status IN ('counting', 'review');

CREATE TABLE IF NOT EXISTS public.stock_audit_items (
    id                   uuid PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
    audit_id             uuid NOT NULL REFERENCES public.stock_audits(id) ON DELETE CASCADE,
    part_id              uuid NOT NULL REFERENCES public.parts(id),

    -- Snapshots, so a renamed or re-numbered part does not rewrite audit history.
    part_name_snapshot   text NOT NULL DEFAULT '',
    part_number_snapshot text,
    unit_snapshot        text NOT NULL DEFAULT 'pcs',

    system_qty           numeric(10,2) NOT NULL DEFAULT 0,
    counted_qty          numeric(10,2),
    variance             numeric(10,2) GENERATED ALWAYS AS (counted_qty - system_qty) STORED,

    -- true when the counter wrote this part onto a blank row rather than it being printed.
    was_found_row        boolean NOT NULL DEFAULT false,

    reason               text,
    reason_notes         text,

    -- Written at completion.
    moved_during_audit   numeric(10,2),
    applied_delta        numeric(10,2),
    final_qty            numeric(10,2),
    unit_value_snapshot  numeric(12,2),
    variance_value       numeric(14,2),

    CONSTRAINT stock_audit_items_counted_nonneg
        CHECK (counted_qty IS NULL OR counted_qty >= 0),
    CONSTRAINT stock_audit_items_reason_check
        CHECK (reason IS NULL OR reason IN ('missing', 'stolen', 'damaged', 'found', 'other')),
    CONSTRAINT stock_audit_items_unique_part UNIQUE (audit_id, part_id)
);

CREATE INDEX IF NOT EXISTS stock_audit_items_audit_idx ON public.stock_audit_items (audit_id);
CREATE INDEX IF NOT EXISTS stock_audit_items_part_idx  ON public.stock_audit_items (part_id);

COMMENT ON TABLE public.stock_audits IS
    'Physical stock counts, one per workshop at a time. Immutable once completed: a wrong count is corrected by running another audit, never by editing this one.';

COMMENT ON TABLE public.stock_audit_items IS
    'One counted part per audit. system_qty is frozen when the count sheet is generated; variance is measured against it, not against live stock, so parts consumed mid-audit are not silently reversed.';

COMMENT ON COLUMN public.stock_audit_items.system_qty IS
    'What the app believed was here when the count sheet was generated. Never updated.';

COMMENT ON COLUMN public.stock_audit_items.moved_during_audit IS
    'Live stock minus system_qty at the moment of completion — legitimate consumption, purchases and transfers that happened while the audit was open. Recorded for explanation only; the variance is applied on top of it.';

COMMENT ON COLUMN public.stock_audit_items.was_found_row IS
    'The part was written onto a blank row on the sheet rather than printed on it — stock the app did not know was here.';

COMMENT ON COLUMN public.stock_audit_items.unit_value_snapshot IS
    'Latest purchase price per unit, net of discount and before GST, frozen at completion. NULL when the part has never been purchased.';

ALTER TABLE public.stock_audits      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_audit_items ENABLE ROW LEVEL SECURITY;

-- Readable by the roles that can see inventory. maintenance_exec is included even though
-- it takes no part in running an audit: audit write-offs surface in Consumption History,
-- which it can already see. Writes go through the SECURITY DEFINER functions only, so no
-- INSERT/UPDATE/DELETE policies are granted.
DROP POLICY IF EXISTS "Exec and finance view stock_audits" ON public.stock_audits;
CREATE POLICY "Exec and finance view stock_audits"
    ON public.stock_audits FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('finance', 'super_admin', 'maintenance_exec')
    ));

DROP POLICY IF EXISTS "Exec and finance view stock_audit_items" ON public.stock_audit_items;
CREATE POLICY "Exec and finance view stock_audit_items"
    ON public.stock_audit_items FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid()
          AND u.role IN ('finance', 'super_admin', 'maintenance_exec')
    ));

GRANT ALL ON TABLE public.stock_audits TO anon;
GRANT ALL ON TABLE public.stock_audits TO authenticated;
GRANT ALL ON TABLE public.stock_audits TO service_role;

GRANT ALL ON TABLE public.stock_audit_items TO anon;
GRANT ALL ON TABLE public.stock_audit_items TO authenticated;
GRANT ALL ON TABLE public.stock_audit_items TO service_role;
