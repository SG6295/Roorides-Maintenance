-- Rewrite get_maintenance_stats returning every field Analytics.jsx expects.
-- Key facts confirmed from DB:
--   issues.severity   = 'Major' | 'Minor'
--   issues.category   = 'Electrical' | 'Mechanical' | 'Body' | 'Tyre' | 'GPS' | 'AdBlue' | 'Other'
--   issues.work_type  = 'InHouse' | 'Outsource' (or NULL)
--   issues.rating     = 'Good' | 'Ok' | 'Bad' (or NULL)
--   tickets has NO rating column — ratings live only on issues

DROP FUNCTION IF EXISTS get_maintenance_stats(DATE, DATE, TEXT);

CREATE OR REPLACE FUNCTION get_maintenance_stats(
  start_date_input DATE DEFAULT NULL,
  end_date_input   DATE DEFAULT NULL,
  site_filter      TEXT DEFAULT NULL
)
RETURNS TABLE(
  total_tickets           BIGINT,
  status_new              BIGINT,
  status_pending          BIGINT,   -- alias for status_new (UI compat)
  status_accepted         BIGINT,
  status_wip              BIGINT,
  status_resolved         BIGINT,
  status_closed           BIGINT,
  status_rejected         BIGINT,
  status_completed        BIGINT,   -- resolved + closed (UI compat)

  major_total             BIGINT,
  major_electrical        BIGINT,
  major_mechanical        BIGINT,
  major_body              BIGINT,
  major_tyre              BIGINT,

  minor_total             BIGINT,
  minor_electrical        BIGINT,
  minor_mechanical        BIGINT,
  minor_body              BIGINT,
  minor_tyre              BIGINT,

  type_in_house           BIGINT,
  type_outsource          BIGINT,

  accept_pending          BIGINT,
  accept_adhered          BIGINT,
  accept_violated         BIGINT,

  -- Overall / Completion SLA split by work type
  comp_in_wip_within      BIGINT,
  comp_in_adhered         BIGINT,
  comp_in_violated        BIGINT,
  comp_out_wip_within     BIGINT,
  comp_out_adhered        BIGINT,
  comp_out_violated       BIGINT,

  -- Ratings (from issues)
  rating_pending          BIGINT,
  rating_collected        BIGINT,
  rating_good             BIGINT,
  rating_ok               BIGINT,
  rating_bad              BIGINT,
  csat_score_sum          BIGINT,
  total_completed_tickets BIGINT
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
      -- Effective overall SLA (live for open tickets)
      CASE
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND CURRENT_DATE > t.final_sla_end_date::date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_overall,
      -- Effective acceptance SLA (live for no-issue open tickets)
      CASE
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND CURRENT_DATE > add_working_days(t.created_at::date, v_sla_days) THEN 'Violated'
        ELSE 'Pending'
      END AS eff_accept,
      -- Dominant work type for SLA split (InHouse vs Outsource)
      CASE
        WHEN EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'Outsource')
         AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'InHouse')
        THEN 'Outsource'
        ELSE 'InHouse'
      END AS dominant_work_type
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
    -- Status counts
    COUNT(*)::BIGINT AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_pending,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT AS status_accepted,
    COUNT(*) FILTER (WHERE td.status IN ('Work In Progress', 'Work in Progress'))::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT AS status_rejected,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS status_completed,

    -- Major issues by category
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major')::BIGINT AS major_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Electrical')::BIGINT AS major_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Mechanical')::BIGINT AS major_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Body')::BIGINT AS major_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Tyre')::BIGINT AS major_tyre,

    -- Minor issues by category
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor')::BIGINT AS minor_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Electrical')::BIGINT AS minor_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Mechanical')::BIGINT AS minor_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Body')::BIGINT AS minor_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Tyre')::BIGINT AS minor_tyre,

    -- Work type
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'InHouse')::BIGINT AS type_in_house,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'Outsource')::BIGINT AS type_outsource,

    -- Acceptance SLA
    COUNT(*) FILTER (WHERE td.eff_accept = 'Pending')::BIGINT AS accept_pending,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Adhered')::BIGINT AS accept_adhered,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Violated')::BIGINT AS accept_violated,

    -- Completion SLA — split by dominant work type
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_violated,

    -- Ratings (from issues)
    (SELECT COUNT(*) FROM issue_data
      JOIN ticket_data td2 ON td2.id = issue_data.ticket_id
      WHERE issue_data.rating IS NULL AND td2.status IN ('Resolved', 'Closed'))::BIGINT AS rating_pending,
    (SELECT COUNT(*) FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS rating_collected,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Good')::BIGINT AS rating_good,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Ok')::BIGINT AS rating_ok,
    (SELECT COUNT(*) FROM issue_data WHERE rating = 'Bad')::BIGINT AS rating_bad,
    (SELECT COALESCE(SUM(CASE WHEN rating = 'Good' THEN 2 WHEN rating = 'Ok' THEN 1 ELSE 0 END), 0)
       FROM issue_data WHERE rating IS NOT NULL)::BIGINT AS csat_score_sum,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS total_completed_tickets

  FROM ticket_data td;

END;
$$ LANGUAGE plpgsql;
