-- MAIN-152: Analytics drill-down — click any number to see the records behind it.
--
-- The Tickets and Issues lists learn the Analytics selection as a new key in p_query
-- (never a new parameter):
--
--   p_query.analytics = { from, to, sites: [...], where: { <bucket column>: value | [values] } }
--
-- When it is present the list's own date window is ignored and its rows are exactly the
-- records analytics_ticket_rows / analytics_issue_rows return for that selection whose
-- bucket columns match `where` — the same rows get_maintenance_stats counts, so a list's
-- total always equals the number clicked. The list's own filters, search and sort still
-- apply on top.
--
-- Also:
--   * analytics_ticket_rows gains `overdue` (open and past its deadline, now) and
--     analytics_issue_rows gains `rated`, so "Currently Overdue" and "Ratings Collected"
--     are one rule each, counted and listed from the same rows. Changing a RETURNS TABLE
--     needs DROP + CREATE.
--   * get_maintenance_stats returns `overdue` (period-independent, follows the sites), so
--     the browser no longer counts it itself.
--   * ticket_list_rows carries the Analytics verdicts as columns — acceptance_sla,
--     completion_sla and the ticket's job_card_type — taken from analytics_ticket_rows,
--     so the list shows the very values Analytics counted.

DROP FUNCTION IF EXISTS public.analytics_issue_rows(jsonb);
DROP FUNCTION IF EXISTS public.analytics_ticket_rows(jsonb);

CREATE FUNCTION public.analytics_ticket_rows(p_filters jsonb)
RETURNS TABLE(ticket_id uuid, ticket_number integer, site text, raised_on date, status text,
              acceptance text, completion text, job_card_type text, overdue boolean)
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
    t AS (
        SELECT tk.*,
               ((tk.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date AS ist_day
        FROM   public.tickets tk
    )
    SELECT t.id,
           t.ticket_number,
           t.site,
           t.ist_day,
           t.status::text,
           -- A stored Pending past its deadline already counts as Violated: the hourly
           -- refresh would make it so within the hour.
           CASE
               WHEN t.acceptance_sla_status IN ('NA', 'Adhered', 'Violated') THEN t.acceptance_sla_status::text
               WHEN NOT EXISTS (SELECT 1 FROM public.issues i WHERE i.ticket_id = t.id)
                    AND t.acceptance_sla_end_date IS NOT NULL
                    AND now() > t.acceptance_sla_end_date THEN 'Violated'
               ELSE 'Pending'
           END,
           CASE
               WHEN t.overall_sla_status IN ('NA', 'Adhered', 'Violated') THEN t.overall_sla_status::text
               WHEN t.final_sla_end_date IS NOT NULL AND now() > t.final_sla_end_date THEN 'Violated'
               ELSE 'Pending'
           END,
           CASE
               WHEN j.n_issues = 0     THEN 'no_issues'
               WHEN j.n_outsource > 0  THEN 'Outsource'
               WHEN j.n_inhouse > 0    THEN 'InHouse'
               ELSE 'none'
           END,
           -- "Currently Overdue": still open and past its completion deadline, right now.
           (t.status::text NOT IN ('Resolved', 'Closed', 'Rejected')
            AND t.final_sla_end_date IS NOT NULL
            AND t.final_sla_end_date < now())
    FROM   t
    CROSS  JOIN f
    CROSS  JOIN LATERAL (
        SELECT count(i.id)                                   AS n_issues,
               count(*) FILTER (WHERE jc.type = 'Outsource') AS n_outsource,
               count(*) FILTER (WHERE jc.type = 'InHouse')   AS n_inhouse
        FROM   public.issues i
        LEFT   JOIN public.job_cards jc ON jc.id = i.job_card_id
        WHERE  i.ticket_id = t.id
    ) j
    WHERE (f.d_from IS NULL OR t.ist_day >= f.d_from)
      AND (f.d_to   IS NULL OR t.ist_day <= f.d_to)
      AND (f.sites  IS NULL OR t.site = ANY (f.sites))
$$;

COMMENT ON FUNCTION public.analytics_ticket_rows(jsonb) IS 'MAIN-171/152: every ticket in the Analytics selection ({from, to, sites}; a missing bound = no bound) with the bucket it counts in. get_maintenance_stats counts these rows; the drill-down lists them (analytics_drill_ids).';

CREATE FUNCTION public.analytics_issue_rows(p_filters jsonb)
RETURNS TABLE(issue_id uuid, ticket_id uuid, ticket_number integer, site text, raised_on date,
              ticket_status text, severity text, category text, job_card_type text, rating text,
              rating_pending boolean, rated boolean)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT i.id,
           t.ticket_id,
           t.ticket_number,
           t.site,
           t.raised_on,
           t.status,
           i.severity::text,
           i.category::text,
           coalesce(jc.type::text, 'none'),
           i.rating::text,
           (i.rating IS NULL AND t.status IN ('Resolved', 'Closed')),
           (i.rating IS NOT NULL)
    FROM   public.analytics_ticket_rows(p_filters) t
    JOIN   public.issues i ON i.ticket_id = t.ticket_id
    LEFT   JOIN public.job_cards jc ON jc.id = i.job_card_id
$$;

COMMENT ON FUNCTION public.analytics_issue_rows(jsonb) IS 'MAIN-171/152: every issue on the tickets of analytics_ticket_rows (so dated by its ticket''s IST raise day, not its own), with the buckets it counts in. job_card_type is the job card''s type, or none when the issue has no job card.';

CREATE OR REPLACE FUNCTION public.get_maintenance_stats(p_filters jsonb) RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    WITH tk AS (SELECT * FROM public.analytics_ticket_rows(p_filters)),
         iss AS (SELECT * FROM public.analytics_issue_rows(p_filters))
    SELECT jsonb_build_object(
        'tickets', jsonb_build_object(
            'total',     (SELECT count(*) FROM tk),
            'by_status', coalesce((SELECT jsonb_object_agg(status, n)
                                   FROM (SELECT status, count(*) n FROM tk GROUP BY 1) s), '{}'::jsonb)
        ),
        'acceptance', coalesce((SELECT jsonb_object_agg(acceptance, n)
                                FROM (SELECT acceptance, count(*) n FROM tk GROUP BY 1) s), '{}'::jsonb),
        'completion', coalesce((SELECT jsonb_object_agg(job_card_type, by_result)
                                FROM (SELECT job_card_type, jsonb_object_agg(completion, n) by_result
                                      FROM (SELECT job_card_type, completion, count(*) n FROM tk GROUP BY 1, 2) c
                                      GROUP BY 1) s), '{}'::jsonb),
        'issues', jsonb_build_object(
            'total',            (SELECT count(*) FROM iss),
            'by_job_card_type', coalesce((SELECT jsonb_object_agg(job_card_type, n)
                                          FROM (SELECT job_card_type, count(*) n FROM iss GROUP BY 1) s), '{}'::jsonb),
            'by_severity',      coalesce((SELECT jsonb_object_agg(severity, jsonb_build_object('total', total, 'by_category', by_category))
                                          FROM (SELECT severity, sum(n) total, jsonb_object_agg(category, n) by_category
                                                FROM (SELECT severity, category, count(*) n FROM iss GROUP BY 1, 2) c
                                                GROUP BY 1) s), '{}'::jsonb)
        ),
        'ratings', jsonb_build_object(
            'pending',   (SELECT count(*) FROM iss WHERE rating_pending),
            'collected', (SELECT count(*) FROM iss WHERE rated),
            'by_rating', coalesce((SELECT jsonb_object_agg(rating, n)
                                   FROM (SELECT rating, count(*) n FROM iss WHERE rated GROUP BY 1) s), '{}'::jsonb)
        ),
        -- Live, whatever the period: every open ticket past its deadline at the chosen sites.
        'overdue', (SELECT count(*)
                    FROM   public.analytics_ticket_rows(jsonb_build_object('sites', p_filters -> 'sites')) o
                    WHERE  o.overdue)
    )
$$;

COMMENT ON FUNCTION public.get_maintenance_stats(jsonb) IS 'MAIN-171/152: Analytics › SLA & tickets. p_filters = {from, to, sites}; counts analytics_ticket_rows / analytics_issue_rows (overdue ignores the period). jsonb argument — do not add a parameter.';

-- Whether an Analytics row's bucket columns match a drill-down's `where`
-- ({column: value | [values]}). A column the row does not have matches nothing.
CREATE OR REPLACE FUNCTION public.analytics_row_matches(p_row jsonb, p_where jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM   jsonb_each(CASE WHEN jsonb_typeof(p_where) = 'object' THEN p_where ELSE '{}'::jsonb END) AS w(k, v)
        WHERE  NOT EXISTS (
                   SELECT 1
                   FROM   jsonb_array_elements(CASE WHEN jsonb_typeof(w.v) = 'array' THEN w.v
                                                    ELSE jsonb_build_array(w.v) END) e
                   WHERE  p_row ? w.k
                     AND  (e #>> '{}') IS NOT DISTINCT FROM (p_row ->> w.k))
    );
$$;

-- The ids behind an Analytics number: the rows get_maintenance_stats counts for the
-- selection, narrowed by `where`. SECURITY INVOKER, like everything it reads.
CREATE OR REPLACE FUNCTION public.analytics_drill_ids(p_list text, p_selection jsonb) RETURNS SETOF uuid
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT a.ticket_id
    FROM   public.analytics_ticket_rows(p_selection) a
    WHERE  p_list = 'tickets' AND p_selection IS NOT NULL
      AND  public.analytics_row_matches(to_jsonb(a), p_selection -> 'where')
    UNION ALL
    SELECT a.issue_id
    FROM   public.analytics_issue_rows(p_selection) a
    WHERE  p_list = 'issues' AND p_selection IS NOT NULL
      AND  public.analytics_row_matches(to_jsonb(a), p_selection -> 'where');
$$;

COMMENT ON FUNCTION public.analytics_drill_ids(text, jsonb) IS 'MAIN-152: the ticket or issue ids behind one Analytics number — analytics_ticket_rows / analytics_issue_rows for the selection whose bucket columns match p_selection.where. Read by list_query''s analytics key.';

-- The Tickets list carries the verdicts Analytics counts (MAIN-152), from the same function.
CREATE OR REPLACE FUNCTION public.ticket_list_rows(p_from date, p_to date) RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'id',                       t.id,
        'ticket_number',            t.ticket_number,
        'created_at',               t.created_at,
        'raised_on',                ((t.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date,
        'vehicle_number',           t.vehicle_number,
        'site',                     t.site,
        'status',                   t.status,
        'remarks',                  t.initial_remarks,
        'supervisor_name',          t.supervisor_name,
        'created_by_user_id',       t.created_by_user_id,
        'acceptance_sla_end_date',  t.acceptance_sla_end_date,
        'final_sla_end_date',       t.final_sla_end_date,
        'overall_sla_status',       t.overall_sla_status,
        'sla_state', CASE
            WHEN t.status = 'New' AND t.acceptance_sla_end_date IS NOT NULL THEN
                CASE WHEN now() <= t.acceptance_sla_end_date THEN 'Awaiting acceptance' ELSE 'Acceptance late' END
            WHEN t.status IN ('Resolved', 'Closed', 'Rejected') THEN
                CASE t.overall_sla_status WHEN 'Adhered' THEN 'Adhered' WHEN 'Violated' THEN 'Violated' ELSE 'Not applicable' END
            WHEN t.status <> 'New' AND t.final_sla_end_date IS NOT NULL THEN
                CASE WHEN now() <= t.final_sla_end_date THEN 'Running' ELSE 'Overdue' END
            ELSE 'Not applicable'
        END,
        'sla_due', CASE
            WHEN t.status = 'New' THEN t.acceptance_sla_end_date
            WHEN t.status IN ('Resolved', 'Closed', 'Rejected') THEN NULL
            ELSE t.final_sla_end_date
        END,
        -- The verdicts Analytics counts (MAIN-152).
        'acceptance_sla',           a.acceptance,
        'completion_sla',           a.completion,
        'job_card_type',            a.job_card_type,
        '_q', lower(concat_ws(' ', t.ticket_number, t.vehicle_number, t.site, t.initial_remarks, t.supervisor_name))
    ))
    FROM public.tickets t
    LEFT JOIN public.analytics_ticket_rows(jsonb_build_object('from', p_from, 'to', p_to)) a ON a.ticket_id = t.id
    WHERE (p_from IS NULL OR t.created_at >= public.list_ist_day_start_utc(p_from))
      AND (p_to   IS NULL OR t.created_at <  public.list_ist_day_start_utc(p_to + 1));
$$;

-- list_query learns the `analytics` key.
CREATE OR REPLACE FUNCTION public.list_query(p_list text, p_query jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path TO 'public'
AS $$
DECLARE
    v_q       jsonb := coalesce(p_query, '{}'::jsonb);
    v_from    date  := nullif(v_q ->> 'from', '')::date;
    v_to      date  := nullif(v_q ->> 'to', '')::date;
    v_filters jsonb := CASE WHEN jsonb_typeof(v_q -> 'filters') = 'object' THEN v_q -> 'filters' ELSE '{}'::jsonb END;
    v_search  text  := nullif(btrim(v_q ->> 'search'), '');
    v_sort    text  := coalesce(nullif(v_q ->> 'sort', ''), 'created_at');
    v_desc    boolean := coalesce(v_q ->> 'dir', 'desc') <> 'asc';
    v_size    int   := least(greatest(coalesce(nullif(v_q ->> 'page_size', '')::int, 50), 1), 5000);
    v_page    int   := greatest(coalesce(nullif(v_q ->> 'page', '')::int, 1), 1);
    v_facet   text  := nullif(v_q ->> 'facet', '');
    -- MAIN-152: the Analytics selection behind a clicked number.
    v_an      jsonb := CASE WHEN jsonb_typeof(v_q -> 'analytics') = 'object' THEN v_q -> 'analytics' END;
    v_ids     uuid[];
    v_result  jsonb;
BEGIN
    IF p_list NOT IN ('tickets', 'issues', 'job_cards') THEN
        RAISE EXCEPTION 'Unknown list %', p_list;
    END IF;

    IF v_an IS NOT NULL THEN
        IF p_list NOT IN ('tickets', 'issues') THEN
            RAISE EXCEPTION 'The % list has no Analytics drill-down', p_list;
        END IF;
        -- The Analytics period replaces the list's own date window.
        v_from := NULL;
        v_to   := NULL;
        v_ids  := ARRAY(SELECT public.analytics_drill_ids(p_list, v_an));
    END IF;

    IF v_facet IS NOT NULL THEN
        SELECT jsonb_build_object('values', coalesce(jsonb_agg(jsonb_build_object('value', val, 'n', n)
                                                     ORDER BY n DESC, val NULLS LAST), '[]'::jsonb))
        INTO   v_result
        FROM (
            SELECT r ->> v_facet AS val, count(*) AS n
            FROM   public.list_base_rows(p_list, v_from, v_to) r
            WHERE  (v_ids IS NULL OR (r ->> 'id')::uuid = ANY (v_ids))
              AND  public.list_row_passes(r, v_filters, v_facet)
              AND  (v_search IS NULL OR r ->> '_q' LIKE public.list_like_pattern(v_search))
            GROUP  BY 1
            ORDER  BY 2 DESC, 1 NULLS LAST
            LIMIT  500
        ) f;
        RETURN v_result;
    END IF;

    WITH hit AS (
        SELECT r
        FROM   public.list_base_rows(p_list, v_from, v_to) r
        WHERE  (v_ids IS NULL OR (r ->> 'id')::uuid = ANY (v_ids))
          AND  public.list_row_passes(r, v_filters)
          AND  (v_search IS NULL OR r ->> '_q' LIKE public.list_like_pattern(v_search))
    ),
    page AS (
        SELECT r, row_number() OVER () AS ord
        FROM (
            SELECT r FROM hit
            ORDER  BY CASE WHEN NOT v_desc THEN r -> v_sort END ASC  NULLS LAST,
                      CASE WHEN v_desc     THEN r -> v_sort END DESC NULLS LAST,
                      r -> 'created_at' DESC,
                      r ->> 'id'
            LIMIT  v_size OFFSET (v_page - 1) * v_size
        ) p
    )
    SELECT jsonb_build_object(
               'total', (SELECT count(*) FROM hit),
               'rows',  coalesce((SELECT jsonb_agg(r - '_q' ORDER BY ord) FROM page), '[]'::jsonb))
    INTO v_result;

    RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.list_query(text, jsonb) IS 'MAIN-151/152: the shared list engine — filters, search, sort, page and column facets over *_list_rows. p_query.analytics ({from, to, sites, where}) limits Tickets/Issues to the records behind an Analytics number (analytics_drill_ids) and replaces the date window. SECURITY INVOKER, so row-level security decides the rows. p_query is jsonb: add keys, never parameters.';

-- Signed-in users only, as for the functions MAIN-151 and MAIN-171 added. Recreated
-- functions start with the default PUBLIC grant, so revoke it again.
REVOKE ALL ON FUNCTION public.analytics_ticket_rows(jsonb)        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.analytics_issue_rows(jsonb)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.analytics_row_matches(jsonb, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.analytics_drill_ids(text, jsonb)    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.analytics_ticket_rows(jsonb)        TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.analytics_issue_rows(jsonb)         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.analytics_row_matches(jsonb, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.analytics_drill_ids(text, jsonb)    TO authenticated, service_role;
