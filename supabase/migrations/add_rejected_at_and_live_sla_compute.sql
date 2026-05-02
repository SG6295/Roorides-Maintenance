-- ============================================================
-- Migration: add_rejected_at_and_live_sla_compute
-- 1. Add rejected_at column to tickets
-- 2. BEFORE trigger: stamp rejected_at and evaluate acceptance SLA on rejection
-- 3. Rewrite get_maintenance_stats with live SLA computation
-- 4. Migrate Pending → New (status cleanup)
-- 5. Backfill: open tickets past acceptance deadline → Violated
-- ============================================================


-- ============================================================
-- 1. Add rejected_at column
-- ============================================================
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;

-- Note: existing rejected tickets will have rejected_at = NULL (no reliable timestamp available)


-- ============================================================
-- 2. BEFORE trigger: stamp rejected_at + evaluate acceptance SLA
-- ============================================================
CREATE OR REPLACE FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla()
RETURNS TRIGGER AS $$
DECLARE
  v_sla_days      INT;
  v_deadline      DATE;
  v_first_issue   TIMESTAMPTZ;
BEGIN
  -- Only act when status transitions TO Rejected
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN

    -- Stamp the rejection timestamp
    NEW.rejected_at := NOW();

    -- Only evaluate acceptance SLA if it is still Pending (not already resolved by first-issue trigger)
    IF NEW.acceptance_sla_status = 'Pending' THEN

      SELECT COALESCE(value::int, 2)
        INTO v_sla_days
        FROM system_settings
       WHERE key = 'acceptance_sla_days';

      v_deadline := add_working_days(NEW.created_at::date, COALESCE(v_sla_days, 2));

      -- Check whether any issue was ever created
      SELECT MIN(created_at)
        INTO v_first_issue
        FROM issues
       WHERE ticket_id = NEW.id;

      IF v_first_issue IS NOT NULL THEN
        -- First issue exists; evaluate against its creation time
        IF v_first_issue::date <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      ELSE
        -- No issues ever created; evaluate against rejection time (NOW())
        IF NOW()::date <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_stamp_rejected_at_and_acceptance_sla ON tickets;
CREATE TRIGGER trg_stamp_rejected_at_and_acceptance_sla
  BEFORE UPDATE ON tickets
  FOR EACH ROW
  EXECUTE FUNCTION stamp_rejected_at_and_evaluate_acceptance_sla();


-- ============================================================
-- 3. Rewrite get_maintenance_stats with live SLA computation
-- ============================================================
DROP FUNCTION IF EXISTS get_maintenance_stats(DATE, DATE, TEXT);

CREATE OR REPLACE FUNCTION get_maintenance_stats(
  p_start_date DATE DEFAULT NULL,
  p_end_date   DATE DEFAULT NULL,
  p_site       TEXT DEFAULT NULL
)
RETURNS TABLE(
  total_tickets       BIGINT,
  status_new          BIGINT,
  status_accepted     BIGINT,
  status_wip          BIGINT,
  status_resolved     BIGINT,
  status_closed       BIGINT,
  status_rejected     BIGINT,

  -- Completion (overall) SLA — live for open tickets
  overall_pending     BIGINT,
  overall_adhered     BIGINT,
  overall_violated    BIGINT,

  -- Acceptance SLA — live for open tickets with no issues yet
  accept_pending      BIGINT,
  accept_adhered      BIGINT,
  accept_violated     BIGINT,

  -- Issue-level aggregates
  total_issues        BIGINT,
  category_breakdown  JSONB,
  impact_breakdown    JSONB,
  work_type_breakdown JSONB,
  rating_breakdown    JSONB,
  avg_tat             NUMERIC
) AS $$
DECLARE
  v_sla_days INT;
BEGIN
  SELECT COALESCE(value::int, 2)
    INTO v_sla_days
    FROM system_settings
   WHERE key = 'acceptance_sla_days';

  RETURN QUERY
  WITH ticket_data AS (
    SELECT
      t.id,
      t.status,
      t.created_at,
      t.resolved_at,
      t.closed_at,
      t.impact,
      t.final_sla_end_date,
      t.overall_sla_status,
      t.acceptance_sla_status,
      -- Live overall SLA: use stored outcome for closed tickets; compute for open ones
      CASE
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND CURRENT_DATE > t.final_sla_end_date::date            THEN 'Violated'
        ELSE 'Pending'
      END AS effective_overall_sla,
      -- Live acceptance SLA: use stored outcome; fall back to deadline check for no-issue tickets
      CASE
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND CURRENT_DATE > add_working_days(t.created_at::date, v_sla_days) THEN 'Violated'
        ELSE 'Pending'
      END AS effective_acceptance_sla
    FROM tickets t
    WHERE (p_start_date IS NULL OR t.created_at::date >= p_start_date)
      AND (p_end_date   IS NULL OR t.created_at::date <= p_end_date)
      AND (p_site       IS NULL OR t.site = p_site)
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (p_start_date IS NULL OR t.created_at::date >= p_start_date)
      AND (p_end_date   IS NULL OR t.created_at::date <= p_end_date)
      AND (p_site       IS NULL OR t.site = p_site)
  )
  SELECT
    COUNT(*)::BIGINT                                                                AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT                              AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT                         AS status_accepted,
    COUNT(*) FILTER (WHERE td.status IN ('Work In Progress', 'Work in Progress'))::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT                         AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT                           AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT                         AS status_rejected,

    -- Overall SLA
    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Pending')::BIGINT           AS overall_pending,
    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Adhered')::BIGINT           AS overall_adhered,
    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Violated')::BIGINT          AS overall_violated,

    -- Acceptance SLA
    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Pending')::BIGINT        AS accept_pending,
    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Adhered')::BIGINT        AS accept_adhered,
    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Violated')::BIGINT       AS accept_violated,

    -- Issue aggregates
    (SELECT COUNT(*) FROM issue_data)::BIGINT                                      AS total_issues,

    COALESCE((
      SELECT jsonb_object_agg(category, cnt)
        FROM (SELECT category, COUNT(*) AS cnt FROM issue_data
               WHERE category IS NOT NULL GROUP BY category) x
    ), '{}'::jsonb)                                                                 AS category_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(impact, cnt)
        FROM (SELECT impact, COUNT(*) AS cnt FROM ticket_data
               WHERE impact IS NOT NULL GROUP BY impact) x
    ), '{}'::jsonb)                                                                 AS impact_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(work_type, cnt)
        FROM (SELECT work_type, COUNT(*) AS cnt FROM issue_data
               WHERE work_type IS NOT NULL GROUP BY work_type) x
    ), '{}'::jsonb)                                                                 AS work_type_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(rating, cnt)
        FROM (SELECT rating, COUNT(*) AS cnt FROM issue_data
               WHERE rating IS NOT NULL GROUP BY rating) x
    ), '{}'::jsonb)                                                                 AS rating_breakdown,

    ROUND(AVG(
      CASE
        WHEN td.resolved_at IS NOT NULL THEN EXTRACT(EPOCH FROM (td.resolved_at - td.created_at)) / 86400.0
        WHEN td.closed_at   IS NOT NULL THEN EXTRACT(EPOCH FROM (td.closed_at   - td.created_at)) / 86400.0
        ELSE NULL
      END
    )::NUMERIC, 1)                                                                  AS avg_tat

  FROM ticket_data td;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- 4. Migrate legacy Pending status → New
-- ============================================================
UPDATE tickets SET status = 'New' WHERE status = 'Pending';


-- ============================================================
-- 5. Backfill: open tickets past acceptance SLA deadline → Violated
--    (tickets with no issues that the first-issue trigger never fired for)
-- ============================================================
UPDATE tickets t
SET acceptance_sla_status = 'Violated'
WHERE t.acceptance_sla_status = 'Pending'
  AND t.status NOT IN ('Resolved', 'Closed', 'Rejected')
  AND NOT EXISTS (SELECT 1 FROM issues WHERE ticket_id = t.id)
  AND CURRENT_DATE > add_working_days(
        t.created_at::date,
        (SELECT COALESCE(value::int, 2) FROM system_settings WHERE key = 'acceptance_sla_days')
      );
