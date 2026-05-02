-- Rewrite get_maintenance_stats to match the post-refactor schema.
-- category, severity, work_type, rating all moved from tickets → issues.
-- overall_sla_status on tickets replaces assignment_sla_status + completion_sla_status.
-- Ticket statuses: New/Pending, Accepted/Team Assigned, Work In Progress, Resolved/Completed/Closed, Rejected
-- Issue statuses: Open, Done
-- Rating values: Good / Ok / Bad (capitalised), work_type: InHouse / Outsource

CREATE OR REPLACE FUNCTION get_maintenance_stats(
    start_date_input DATE,
    end_date_input DATE,
    site_filter TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
  result JSON;
BEGIN
  WITH filtered_tickets AS (
    SELECT
      t.id,
      t.status,
      t.site,
      t.overall_sla_status,
      to_char(t.created_at, 'YYYY-MM') AS month_key,
      to_char(t.created_at, 'Mon YYYY') AS month_label
    FROM tickets t
    WHERE
      t.created_at::date >= start_date_input
      AND t.created_at::date <= end_date_input
      AND (site_filter IS NULL OR t.site = site_filter)
  ),
  filtered_issues AS (
    SELECT
      i.id,
      i.ticket_id,
      i.category,
      i.severity,
      i.work_type,
      i.rating,
      i.status AS issue_status,
      ft.month_key,
      ft.month_label,
      CASE
        WHEN i.rating = 'Good' THEN 2
        WHEN i.rating = 'Ok'   THEN 1
        ELSE 0
      END AS csat_weight
    FROM issues i
    JOIN filtered_tickets ft ON ft.id = i.ticket_id
  ),
  ticket_stats AS (
    SELECT
      month_key,
      month_label,
      COUNT(*)                                                          AS total_tickets,
      COUNT(*) FILTER (WHERE status IN ('New', 'Pending'))              AS status_pending,
      COUNT(*) FILTER (WHERE status = 'Accepted')                        AS status_assigned,
      COUNT(*) FILTER (WHERE status IN ('Resolved', 'Closed'))           AS status_completed,
      COUNT(*) FILTER (WHERE status = 'Rejected')                       AS status_rejected,
      COUNT(*) FILTER (WHERE overall_sla_status = 'Adhered')            AS comp_adhered,
      COUNT(*) FILTER (WHERE overall_sla_status = 'Violated')           AS comp_violated
    FROM filtered_tickets
    GROUP BY month_key, month_label
  ),
  issue_stats AS (
    SELECT
      month_key,
      month_label,
      -- Severity × Category breakdown
      COUNT(*) FILTER (WHERE severity = 'Major')                              AS major_total,
      COUNT(*) FILTER (WHERE severity = 'Major' AND category = 'Electrical')  AS major_electrical,
      COUNT(*) FILTER (WHERE severity = 'Major' AND category = 'Mechanical')  AS major_mechanical,
      COUNT(*) FILTER (WHERE severity = 'Major' AND category = 'Body')        AS major_body,
      COUNT(*) FILTER (WHERE severity = 'Major' AND category = 'Tyre')        AS major_tyre,
      COUNT(*) FILTER (WHERE severity = 'Minor')                              AS minor_total,
      COUNT(*) FILTER (WHERE severity = 'Minor' AND category = 'Electrical')  AS minor_electrical,
      COUNT(*) FILTER (WHERE severity = 'Minor' AND category = 'Mechanical')  AS minor_mechanical,
      COUNT(*) FILTER (WHERE severity = 'Minor' AND category = 'Body')        AS minor_body,
      COUNT(*) FILTER (WHERE severity = 'Minor' AND category = 'Tyre')        AS minor_tyre,
      -- Work type
      COUNT(*) FILTER (WHERE work_type = 'InHouse')                           AS type_in_house,
      COUNT(*) FILTER (WHERE work_type = 'Outsource')                         AS type_outsource,
      -- Ratings (issue-level)
      COUNT(*) FILTER (WHERE issue_status = 'Done' AND rating IS NULL)        AS rating_pending,
      COUNT(*) FILTER (WHERE rating IS NOT NULL)                               AS rating_collected,
      COUNT(*) FILTER (WHERE rating = 'Good')                                  AS rating_good,
      COUNT(*) FILTER (WHERE rating = 'Ok')                                    AS rating_ok,
      COUNT(*) FILTER (WHERE rating = 'Bad')                                   AS rating_bad,
      COALESCE(SUM(csat_weight) FILTER (WHERE rating IS NOT NULL), 0)         AS csat_score_sum
    FROM filtered_issues
    GROUP BY month_key, month_label
  ),
  monthly_stats AS (
    SELECT
      t.month_key,
      t.month_label,
      t.total_tickets,
      t.status_pending,
      t.status_assigned,
      t.status_completed,
      t.status_rejected,

      COALESCE(i.major_total,       0) AS major_total,
      COALESCE(i.major_electrical,  0) AS major_electrical,
      COALESCE(i.major_mechanical,  0) AS major_mechanical,
      COALESCE(i.major_body,        0) AS major_body,
      COALESCE(i.major_tyre,        0) AS major_tyre,

      COALESCE(i.minor_total,       0) AS minor_total,
      COALESCE(i.minor_electrical,  0) AS minor_electrical,
      COALESCE(i.minor_mechanical,  0) AS minor_mechanical,
      COALESCE(i.minor_body,        0) AS minor_body,
      COALESCE(i.minor_tyre,        0) AS minor_tyre,

      COALESCE(i.type_in_house,     0) AS type_in_house,
      COALESCE(i.type_outsource,    0) AS type_outsource,

      -- Assignment SLA: no dedicated column in current schema → zero-filled
      0 AS assign_unassigned_within,
      0 AS assign_adhered,
      0 AS assign_violated,

      -- Completion SLA mapped to comp_in_* (comp_out_* zero-filled)
      COALESCE(t.comp_adhered,      0) AS comp_in_adhered,
      COALESCE(t.comp_violated,     0) AS comp_in_violated,
      0                                 AS comp_in_wip_within,
      0                                 AS comp_out_adhered,
      0                                 AS comp_out_violated,
      0                                 AS comp_out_wip_within,

      COALESCE(i.rating_pending,    0) AS rating_pending,
      COALESCE(i.rating_collected,  0) AS rating_collected,
      COALESCE(i.rating_good,       0) AS rating_good,
      COALESCE(i.rating_ok,         0) AS rating_ok,
      COALESCE(i.rating_bad,        0) AS rating_bad,
      COALESCE(i.csat_score_sum,    0) AS csat_score_sum,
      t.status_completed                AS total_completed_tickets
    FROM ticket_stats t
    LEFT JOIN issue_stats i USING (month_key, month_label)
    ORDER BY t.month_key
  )
  SELECT json_agg(row_to_json(monthly_stats)) INTO result FROM monthly_stats;

  RETURN coalesce(result, '[]'::json);
END;
$$;
