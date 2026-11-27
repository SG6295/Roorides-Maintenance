-- MAIN-152 (user decision 2026-11-27): Analytics' issue figures are dated by the issue's
-- own Raised day (IST), not its ticket's. Ticket figures are unchanged. The site is still
-- the ticket's — an issue has none of its own.
-- Same signature and return columns, so CREATE OR REPLACE replaces it in place;
-- get_maintenance_stats and analytics_drill_ids pick it up unchanged, so a drill-down list
-- still equals its number. raised_on is now the issue's own IST day.

CREATE OR REPLACE FUNCTION public.analytics_issue_rows(p_filters jsonb)
RETURNS TABLE(issue_id uuid, ticket_id uuid, ticket_number integer, site text, raised_on date,
              ticket_status text, severity text, category text, job_card_type text, rating text,
              rating_pending boolean, rated boolean)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    WITH f AS (
        SELECT nullif(p_filters ->> 'from', '')::date AS d_from,
               nullif(p_filters ->> 'to',   '')::date AS d_to,
               CASE WHEN jsonb_typeof(p_filters -> 'sites') = 'array'
                         AND jsonb_array_length(p_filters -> 'sites') > 0
                    THEN ARRAY(SELECT jsonb_array_elements_text(p_filters -> 'sites'))
               END AS sites
    ),
    i AS (
        -- issues.created_at is timestamp without time zone holding UTC.
        SELECT iss.*,
               ((iss.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date AS ist_day
        FROM   public.issues iss
    )
    SELECT i.id,
           t.id,
           t.ticket_number,
           t.site,
           i.ist_day,
           t.status::text,
           i.severity::text,
           i.category::text,
           coalesce(jc.type::text, 'none'),
           i.rating::text,
           (i.rating IS NULL AND t.status::text IN ('Resolved', 'Closed')),
           (i.rating IS NOT NULL)
    FROM   i
    CROSS  JOIN f
    JOIN   public.tickets t ON t.id = i.ticket_id
    LEFT   JOIN public.job_cards jc ON jc.id = i.job_card_id
    WHERE (f.d_from IS NULL OR i.ist_day >= f.d_from)
      AND (f.d_to   IS NULL OR i.ist_day <= f.d_to)
      AND (f.sites  IS NULL OR t.site = ANY (f.sites))
$$;

COMMENT ON FUNCTION public.analytics_issue_rows(jsonb) IS 'MAIN-171/152: every issue in the Analytics selection ({from, to, sites}) — dated by its own IST Raised day, at its ticket''s site — with the buckets it counts in. job_card_type is the job card''s type, or none when the issue has no job card.';

REVOKE ALL ON FUNCTION public.analytics_issue_rows(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.analytics_issue_rows(jsonb) TO authenticated, service_role;
