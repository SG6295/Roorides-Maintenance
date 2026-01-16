CREATE OR REPLACE FUNCTION get_maintenance_stats(
  start_date_input date,
  end_date_input date,
  site_filter text DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  WITH filtered_tickets AS (
    SELECT 
      *,
      to_char(created_at, 'YYYY-MM') as month_key,
      to_char(created_at, 'Mon YYYY') as month_label
    FROM tickets
    WHERE 
      created_at::date >= start_date_input 
      AND created_at::date <= end_date_input
      AND (site_filter IS NULL OR site = site_filter)
  ),
  monthly_stats AS (
    SELECT
      month_key,
      month_label,
      COUNT(*) as total_tickets,
      
      -- Status Counts
      COUNT(*) FILTER (WHERE status = 'Pending') as status_pending,
      COUNT(*) FILTER (WHERE status = 'Team Assigned') as status_assigned,
      COUNT(*) FILTER (WHERE status = 'Work in Progress') as status_wip,
      COUNT(*) FILTER (WHERE status = 'Completed') as status_completed,
      COUNT(*) FILTER (WHERE status = 'Rejected') as status_rejected,

      -- Work Type Counts (Major)
      COUNT(*) FILTER (WHERE impact = 'Major' AND category = 'Electrical') as major_electrical,
      COUNT(*) FILTER (WHERE impact = 'Major' AND category = 'Mechanical') as major_mechanical,
      COUNT(*) FILTER (WHERE impact = 'Major' AND category = 'Body') as major_body,
      COUNT(*) FILTER (WHERE impact = 'Major' AND category = 'Tyre') as major_tyre,
      COUNT(*) FILTER (WHERE impact = 'Major') as major_total,

      -- Work Type Counts (Minor)
      COUNT(*) FILTER (WHERE impact = 'Minor' AND category = 'Electrical') as minor_electrical,
      COUNT(*) FILTER (WHERE impact = 'Minor' AND category = 'Mechanical') as minor_mechanical,
      COUNT(*) FILTER (WHERE impact = 'Minor' AND category = 'Body') as minor_body,
      COUNT(*) FILTER (WHERE impact = 'Minor' AND category = 'Tyre') as minor_tyre,
      COUNT(*) FILTER (WHERE impact = 'Minor') as minor_total,

      -- In House vs Outsource
      COUNT(*) FILTER (WHERE work_type = 'In House') as type_in_house,
      COUNT(*) FILTER (WHERE work_type = 'Outsource') as type_outsource,

      -- SLA Metrics
      COUNT(*) FILTER (WHERE assignment_sla_status = 'Adhered') as sla_assignment_ok,
      COUNT(*) FILTER (WHERE assignment_sla_status = 'Violated') as sla_assignment_bad,
      COUNT(*) FILTER (WHERE status = 'Completed' AND completion_sla_status = 'Adhered') as sla_completion_ok,
      COUNT(*) FILTER (WHERE status = 'Completed' AND completion_sla_status = 'Violated') as sla_completion_bad,

      -- Rating Metrics
      COUNT(*) FILTER (WHERE status = 'Completed') as total_completed,
      COUNT(*) FILTER (WHERE rating IS NOT NULL) as rating_collected,
      COUNT(*) FILTER (WHERE rating = 'good') as rating_good,
      COUNT(*) FILTER (WHERE rating = 'ok') as rating_ok,
      COUNT(*) FILTER (WHERE rating = 'bad') as rating_bad

    FROM filtered_tickets
    GROUP BY month_key, month_label
    ORDER BY month_key
  )
  SELECT json_agg(row_to_json(monthly_stats)) INTO result FROM monthly_stats;

  RETURN coalesce(result, '[]'::json);
END;
$$;
