-- MAIN-176: the Labour list, and the Labour utilisation drill-down into it.
--
-- One row per labour entry: each issue_labour row (one person on one in-house work item),
-- plus one "Unattributed" row for a work item's pre-MAIN-116 issues.labour_hours with
-- nobody attached. These are exactly the rows Analytics › Labour utilisation adds up.
--
--   * labour_report_rows(p_from, p_to) — the report's row rule, once, now with each row's
--     own id (labour_id: the issue_labour id, or the issue's id for an unattributed row).
--     get_labour_report keeps its signature and output and simply reads it, so the
--     Labour utilisation page is unchanged.
--   * labour_list_rows(p_from, p_to) — the list's rows (one jsonb each), from that function.
--   * analytics_labour_rows(p_filters) — the rows a Labour utilisation figure counts:
--     {from, to, sites}; done work items only, placed by completed_on (the IST activity
--     complete date), at the job card's site. The page's trade and technician choices
--     arrive as `where` keys (technician_role, technician_id), which an unattributed row
--     never matches — the same rule filterRows (src/utils/labourReport.js) applies.
--   * list_base_rows / list_query / analytics_drill_ids learn the 'labour' list, and
--     list_query returns a `summary` for it (the tiles, over every row the view matches).
--   * get_labour_list(p_query jsonb) — the wrapper the app calls.
--
-- All SECURITY INVOKER, like the report: row-level security decides who sees what.

CREATE OR REPLACE FUNCTION public.labour_report_rows(p_from date, p_to date)
RETURNS TABLE(labour_id uuid, issue_id uuid, issue_number text, description text, category text,
              completed_on date, site text, vehicle_number text, job_card_number integer,
              technician_id uuid, technician_employee_id text, technician_name text,
              technician_role text, hours numeric, attributed boolean)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT il.id, i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           il.technician_id, u.employee_id, u.name, u.role, il.hours, true
    FROM   public.issue_labour il
    JOIN   public.issues    i  ON i.id  = il.issue_id
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    LEFT JOIN public.users  u  ON u.id  = il.technician_id
    WHERE  jc.type = 'InHouse'
    AND    (i.completed_on IS NULL
            OR ((p_from IS NULL OR i.completed_on >= p_from)
                AND (p_to IS NULL OR i.completed_on <= p_to)))

    UNION ALL

    SELECT i.id, i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           NULL, NULL, NULL, NULL, i.labour_hours, false
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  jc.type = 'InHouse'
    AND    i.labour_hours > 0
    AND    i.completed_on IS NOT NULL
    AND    (p_from IS NULL OR i.completed_on >= p_from)
    AND    (p_to   IS NULL OR i.completed_on <= p_to)
    AND    NOT EXISTS (SELECT 1 FROM public.issue_labour il WHERE il.issue_id = i.id);
$$;

COMMENT ON FUNCTION public.labour_report_rows(date, date) IS 'MAIN-176: the rows of Analytics › Labour utilisation (MAIN-117) — per-technician labour (attributed) and pre-MAIN-116 hours with nobody attached (unattributed) on in-house work items, by activity complete date; attributed labour on items not yet Done comes with a NULL date. A NULL bound = no bound. Read by get_labour_report, labour_list_rows and analytics_labour_rows.';

-- Same signature and output as before: the page reads it unchanged.
CREATE OR REPLACE FUNCTION public.get_labour_report(p_from date, p_to date)
RETURNS TABLE(issue_id uuid, issue_number text, description text, category text, completed_on date,
              site text, vehicle_number text, job_card_number integer, technician_id uuid,
              technician_employee_id text, technician_name text, technician_role text,
              hours numeric, attributed boolean)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT r.issue_id, r.issue_number, r.description, r.category, r.completed_on,
           r.site, r.vehicle_number, r.job_card_number,
           r.technician_id, r.technician_employee_id, r.technician_name, r.technician_role,
           r.hours, r.attributed
    FROM   public.labour_report_rows(p_from, p_to) r;
$$;

-- The rows one Labour utilisation figure counts (before `where`).
CREATE OR REPLACE FUNCTION public.analytics_labour_rows(p_filters jsonb)
RETURNS TABLE(labour_id uuid, issue_id uuid, completed_on date, site text,
              technician_id uuid, technician_role text, attributed boolean, hours numeric)
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
    )
    SELECT r.labour_id, r.issue_id, r.completed_on, r.site,
           r.technician_id, r.technician_role, r.attributed, r.hours
    FROM   f
    CROSS  JOIN LATERAL public.labour_report_rows(f.d_from, f.d_to) r
    WHERE  r.completed_on IS NOT NULL
      AND  (f.sites IS NULL OR r.site = ANY (f.sites));
$$;

COMMENT ON FUNCTION public.analytics_labour_rows(jsonb) IS 'MAIN-176: the labour rows a Labour utilisation figure counts — done work items in {from, to} (activity complete date) at {sites} (the job card''s site). Bucket columns for `where`: completed_on, site, technician_id, technician_role, attributed.';

-- The Labour list's rows.
CREATE OR REPLACE FUNCTION public.labour_list_rows(p_from date, p_to date) RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    WITH r AS (SELECT * FROM public.labour_report_rows(p_from, p_to)),
    item AS (
        -- Everyone who logged hours on the work item, whatever the list's filters.
        SELECT il.issue_id, count(*) AS people, sum(il.hours) AS hours
        FROM   public.issue_labour il
        WHERE  il.issue_id IN (SELECT issue_id FROM r)
        GROUP  BY il.issue_id
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'id',                     r.labour_id,
        'issue_id',               r.issue_id,
        -- The engine's tie-break: the work item's own time, so an item's rows stay together.
        'created_at',             i.created_at,
        'completed_on',           r.completed_on,
        'done',                   r.completed_on IS NOT NULL,
        'attributed',             r.attributed,
        'technician_id',          r.technician_id,
        'technician_employee_id', r.technician_employee_id,
        'technician',             CASE WHEN r.attributed THEN coalesce(r.technician_name, 'Unknown')
                                       ELSE 'Unattributed' END,
        'trade',                  r.technician_role,
        'hours',                  r.hours,
        'people_on_item',         coalesce(item.people, 0),
        'item_hours',             coalesce(item.hours, r.hours),
        'issue_number',           r.issue_number,
        'category',               r.category,
        'description',            r.description,
        'job_card_number',        r.job_card_number,
        'vehicle_number',         r.vehicle_number,
        'ticket_number',          t.ticket_number,
        'site',                   r.site,
        '_q', lower(concat_ws(' ', r.technician_name, r.technician_employee_id,
                              CASE WHEN NOT r.attributed THEN 'unattributed' END,
                              r.issue_number, r.category, r.description, r.job_card_number,
                              r.vehicle_number, t.ticket_number, r.site))
    ))
    FROM   r
    JOIN   public.issues  i ON i.id = r.issue_id
    LEFT   JOIN public.tickets t ON t.id = i.ticket_id
    LEFT   JOIN item ON item.issue_id = r.issue_id;
$$;

COMMENT ON FUNCTION public.labour_list_rows(date, date) IS 'MAIN-176: one jsonb per Labour list row (labour_report_rows in the activity-complete window, plus work items not yet Done), with people_on_item / item_hours for the work item. Read through list_query.';

CREATE OR REPLACE FUNCTION public.list_base_rows(p_list text, p_from date, p_to date) RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT r FROM public.ticket_list_rows(p_from, p_to) r   WHERE p_list = 'tickets'
    UNION ALL
    SELECT r FROM public.issue_list_rows(p_from, p_to) r    WHERE p_list = 'issues'
    UNION ALL
    SELECT r FROM public.job_card_list_rows(p_from, p_to) r WHERE p_list = 'job_cards'
    UNION ALL
    SELECT r FROM public.labour_list_rows(p_from, p_to) r   WHERE p_list = 'labour';
$$;

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
      AND  public.analytics_row_matches(to_jsonb(a), p_selection -> 'where')
    UNION ALL
    SELECT a.labour_id
    FROM   public.analytics_labour_rows(p_selection) a
    WHERE  p_list = 'labour' AND p_selection IS NOT NULL
      AND  public.analytics_row_matches(to_jsonb(a), p_selection -> 'where');
$$;

COMMENT ON FUNCTION public.analytics_drill_ids(text, jsonb) IS 'MAIN-152/176: the ids behind one Analytics number — analytics_ticket_rows / analytics_issue_rows / analytics_labour_rows for the selection whose bucket columns match p_selection.where. Read by list_query''s analytics key.';

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
    IF p_list NOT IN ('tickets', 'issues', 'job_cards', 'labour') THEN
        RAISE EXCEPTION 'Unknown list %', p_list;
    END IF;

    IF v_an IS NOT NULL THEN
        IF p_list NOT IN ('tickets', 'issues', 'labour') THEN
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
    ),
    -- MAIN-176: the Labour list's tiles, over every row the view matches (not just the page).
    lab AS (
        SELECT r ->> 'issue_id'                 AS issue_id,
               (r ->> 'hours')::numeric         AS hours,
               (r ->> 'attributed')::boolean    AS attributed,
               (r ->> 'people_on_item')::int    AS people
        FROM   hit
        WHERE  p_list = 'labour'
    )
    SELECT jsonb_build_object(
               'total', (SELECT count(*) FROM hit),
               'rows',  coalesce((SELECT jsonb_agg(r - '_q' ORDER BY ord) FROM page), '[]'::jsonb))
           || CASE WHEN p_list = 'labour' THEN jsonb_build_object('summary', (
                  SELECT jsonb_build_object(
                      'total_hours',        coalesce(sum(hours), 0),
                      'entries',            count(*),
                      'work_items',         count(DISTINCT issue_id),
                      'items_2plus',        count(DISTINCT issue_id) FILTER (WHERE people >= 2),
                      'items_one',          count(DISTINCT issue_id) FILTER (WHERE people = 1),
                      'unattributed_hours', coalesce(sum(hours) FILTER (WHERE NOT attributed), 0),
                      'unattributed_items', count(DISTINCT issue_id) FILTER (WHERE NOT attributed))
                  FROM lab))
              ELSE '{}'::jsonb END
    INTO v_result;

    RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_labour_list(p_query jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$ SELECT public.list_query('labour', p_query); $$;

COMMENT ON FUNCTION public.get_labour_list(jsonb) IS 'MAIN-176: the Labour list (see list_query); its result also carries `summary` for the tiles. p_query is jsonb — do not add a parameter.';

REVOKE ALL ON FUNCTION public.labour_report_rows(date, date)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.analytics_labour_rows(jsonb)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.labour_list_rows(date, date)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_labour_list(jsonb)           FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.labour_report_rows(date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.analytics_labour_rows(jsonb)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.labour_list_rows(date, date)   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_labour_list(jsonb)         TO authenticated, service_role;
