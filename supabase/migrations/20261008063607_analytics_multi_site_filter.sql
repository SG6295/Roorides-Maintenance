-- MAIN-86: Analytics can filter by several sites at once.
--
-- site_filter changes from text to text[]. The body is copied verbatim from the
-- previous definition; only the two site tests change. Every SLA rule (eff_overall,
-- eff_accept, dominant_work_type, the NA buckets) is deliberately untouched.
--
-- The filter is `t.site = ANY(site_filter)` rather than a join to unnest(site_filter):
-- a join would count a ticket once per repeat of its site in the list. NULL and an
-- empty array both mean "all sites".
--
-- The old text version is dropped first: CREATE OR REPLACE with a different parameter
-- type adds a second overload instead of replacing the first (the MAIN-57 orphan).

DROP FUNCTION IF EXISTS public.get_maintenance_stats(date, date, text);

CREATE FUNCTION public.get_maintenance_stats(start_date_input date DEFAULT NULL::date, end_date_input date DEFAULT NULL::date, site_filter text[] DEFAULT NULL::text[]) RETURNS TABLE(total_tickets bigint, status_new bigint, status_pending bigint, status_accepted bigint, status_wip bigint, status_resolved bigint, status_closed bigint, status_rejected bigint, status_completed bigint, major_total bigint, major_electrical bigint, major_mechanical bigint, major_body bigint, major_tyre bigint, minor_total bigint, minor_electrical bigint, minor_mechanical bigint, minor_body bigint, minor_tyre bigint, type_in_house bigint, type_outsource bigint, accept_pending bigint, accept_adhered bigint, accept_violated bigint, accept_na bigint, comp_in_wip_within bigint, comp_in_adhered bigint, comp_in_violated bigint, comp_in_na bigint, comp_out_wip_within bigint, comp_out_adhered bigint, comp_out_violated bigint, comp_out_na bigint, rating_pending bigint, rating_collected bigint, rating_good bigint, rating_ok bigint, rating_bad bigint, csat_score_sum bigint, total_completed_tickets bigint)
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
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
        WHEN t.overall_sla_status = 'NA' THEN 'NA'
        WHEN t.overall_sla_status IN ('Adhered', 'Violated') THEN t.overall_sla_status
        WHEN t.final_sla_end_date IS NOT NULL
             AND now() > t.final_sla_end_date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_overall,
      CASE
        WHEN t.acceptance_sla_status = 'NA' THEN 'NA'
        WHEN t.acceptance_sla_status IN ('Adhered', 'Violated') THEN t.acceptance_sla_status
        WHEN NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id)
             AND t.acceptance_sla_end_date IS NOT NULL
             AND now() > t.acceptance_sla_end_date THEN 'Violated'
        ELSE 'Pending'
      END AS eff_accept,
      CASE
        WHEN EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'Outsource')
         AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id AND i.work_type = 'InHouse')
        THEN 'Outsource'
        ELSE 'InHouse'
      END AS dominant_work_type
    FROM tickets t
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter IS NULL OR cardinality(site_filter) = 0 OR t.site = ANY(site_filter))
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter IS NULL OR cardinality(site_filter) = 0 OR t.site = ANY(site_filter))
  )
  SELECT
    COUNT(*)::BIGINT AS total_tickets,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_new,
    COUNT(*) FILTER (WHERE td.status = 'New')::BIGINT AS status_pending,
    COUNT(*) FILTER (WHERE td.status = 'Accepted')::BIGINT AS status_accepted,
    COUNT(*) FILTER (WHERE td.status = 'Work In Progress')::BIGINT AS status_wip,
    COUNT(*) FILTER (WHERE td.status = 'Resolved')::BIGINT AS status_resolved,
    COUNT(*) FILTER (WHERE td.status = 'Closed')::BIGINT AS status_closed,
    COUNT(*) FILTER (WHERE td.status = 'Rejected')::BIGINT AS status_rejected,
    COUNT(*) FILTER (WHERE td.status IN ('Resolved', 'Closed'))::BIGINT AS status_completed,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major')::BIGINT AS major_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Electrical')::BIGINT AS major_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Mechanical')::BIGINT AS major_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Body')::BIGINT AS major_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Major' AND category = 'Tyre')::BIGINT AS major_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor')::BIGINT AS minor_total,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Electrical')::BIGINT AS minor_electrical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Mechanical')::BIGINT AS minor_mechanical,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Body')::BIGINT AS minor_body,
    (SELECT COUNT(*) FROM issue_data WHERE severity = 'Minor' AND category = 'Tyre')::BIGINT AS minor_tyre,

    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'InHouse')::BIGINT AS type_in_house,
    (SELECT COUNT(*) FROM issue_data WHERE work_type = 'Outsource')::BIGINT AS type_outsource,

    COUNT(*) FILTER (WHERE td.eff_accept = 'Pending')::BIGINT AS accept_pending,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Adhered')::BIGINT AS accept_adhered,
    COUNT(*) FILTER (WHERE td.eff_accept = 'Violated')::BIGINT AS accept_violated,
    COUNT(*) FILTER (WHERE td.eff_accept = 'NA')::BIGINT AS accept_na,

    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'NA'       AND td.dominant_work_type = 'InHouse')::BIGINT AS comp_in_na,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Pending'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_wip_within,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Adhered'  AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_adhered,
    COUNT(*) FILTER (WHERE td.eff_overall = 'Violated' AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_violated,
    COUNT(*) FILTER (WHERE td.eff_overall = 'NA'       AND td.dominant_work_type = 'Outsource')::BIGINT AS comp_out_na,

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
$$;


ALTER FUNCTION public.get_maintenance_stats(date, date, text[]) OWNER TO postgres;

GRANT ALL ON FUNCTION public.get_maintenance_stats(date, date, text[]) TO anon;
GRANT ALL ON FUNCTION public.get_maintenance_stats(date, date, text[]) TO authenticated;
GRANT ALL ON FUNCTION public.get_maintenance_stats(date, date, text[]) TO service_role;
