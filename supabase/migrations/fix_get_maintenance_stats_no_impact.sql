-- Fix: remove t.impact (column does not exist on tickets);
-- replace impact_breakdown with severity_breakdown from issues.

DROP FUNCTION IF EXISTS get_maintenance_stats(DATE, DATE, TEXT);

CREATE OR REPLACE FUNCTION get_maintenance_stats(
  start_date_input DATE DEFAULT NULL,
  end_date_input   DATE DEFAULT NULL,
  site_filter      TEXT DEFAULT NULL
)
RETURNS TABLE(
  total_tickets        BIGINT,
  status_new           BIGINT,
  status_accepted      BIGINT,
  status_wip           BIGINT,
  status_resolved      BIGINT,
  status_closed        BIGINT,
  status_rejected      BIGINT,

  -- Completion (overall) SLA — live for open tickets
  overall_pending      BIGINT,
  overall_adhered      BIGINT,
  overall_violated     BIGINT,

  -- Acceptance SLA — live for open tickets with no issues yet
  accept_pending       BIGINT,
  accept_adhered       BIGINT,
  accept_violated      BIGINT,

  -- Issue-level aggregates
  total_issues         BIGINT,
  category_breakdown   JSONB,
  severity_breakdown   JSONB,
  work_type_breakdown  JSONB,
  rating_breakdown     JSONB,
  avg_tat              NUMERIC
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
      t.final_sla_end_date,
      t.overall_sla_status,
      t.acceptance_sla_status,
      CASE
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND CURRENT_DATE > t.final_sla_end_date::date THEN 'Violated'
        ELSE 'Pending'
      END AS effective_overall_sla,
      CASE
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND CURRENT_DATE > add_working_days(t.created_at::date, v_sla_days) THEN 'Violated'
        ELSE 'Pending'
      END AS effective_acceptance_sla
    FROM tickets t
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
  )
  SELECT
    COUNT(*)::BIGINT AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT AS status_accepted,
    COUNT(*) FILTER (WHERE td.status IN ('Work In Progress', 'Work in Progress'))::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT AS status_rejected,

    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Pending')::BIGINT AS overall_pending,
    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Adhered')::BIGINT AS overall_adhered,
    COUNT(*) FILTER (WHERE td.effective_overall_sla = 'Violated')::BIGINT AS overall_violated,

    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Pending')::BIGINT AS accept_pending,
    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Adhered')::BIGINT AS accept_adhered,
    COUNT(*) FILTER (WHERE td.effective_acceptance_sla = 'Violated')::BIGINT AS accept_violated,

    (SELECT COUNT(*) FROM issue_data)::BIGINT AS total_issues,

    COALESCE((
      SELECT jsonb_object_agg(category, cnt)
        FROM (SELECT category, COUNT(*) AS cnt FROM issue_data
               WHERE category IS NOT NULL GROUP BY category) x
    ), '{}'::jsonb) AS category_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(severity, cnt)
        FROM (SELECT severity, COUNT(*) AS cnt FROM issue_data
               WHERE severity IS NOT NULL GROUP BY severity) x
    ), '{}'::jsonb) AS severity_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(work_type, cnt)
        FROM (SELECT work_type, COUNT(*) AS cnt FROM issue_data
               WHERE work_type IS NOT NULL GROUP BY work_type) x
    ), '{}'::jsonb) AS work_type_breakdown,

    COALESCE((
      SELECT jsonb_object_agg(rating, cnt)
        FROM (SELECT rating, COUNT(*) AS cnt FROM issue_data
               WHERE rating IS NOT NULL GROUP BY rating) x
    ), '{}'::jsonb) AS rating_breakdown,

    ROUND(AVG(
      CASE
        WHEN td.resolved_at IS NOT NULL THEN EXTRACT(EPOCH FROM (td.resolved_at - td.created_at)) / 86400.0
        WHEN td.closed_at   IS NOT NULL THEN EXTRACT(EPOCH FROM (td.closed_at   - td.created_at)) / 86400.0
        ELSE NULL
      END
    )::NUMERIC, 1) AS avg_tat

  FROM ticket_data td;
END;
$$ LANGUAGE plpgsql;
