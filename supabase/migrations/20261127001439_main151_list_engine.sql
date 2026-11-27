-- MAIN-151: sort, filter and search on the Tickets, Issues and Job Cards lists, in the database.
--
-- Those lists outgrew loading every record in the browser (MAIN-83; ~1,000 new rows a month
-- each). The page now asks for one page of rows, already sorted and filtered, plus the total,
-- plus — when a column menu opens — that column's values with counts.
--
-- Shape:
--   *_list_rows(p_from, p_to)  one jsonb object per record raised in the IST date window,
--                              every column the list can show, sort or filter on, plus
--                              `_q` (lower-cased text the search box matches). SECURITY
--                              INVOKER: row-level security decides who sees what, exactly as
--                              for the old PostgREST queries (supervisors see their sites).
--   list_query(p_list, p_query) the engine: filters, search, sort, page, facet. Shared by
--                              every list, so they all behave the same.
--   get_ticket_list / get_issue_list / get_job_card_list (p_query jsonb)  what the pages call.
--
-- p_query: { from, to: 'YYYY-MM-DD' (IST, on the raised date; either may be absent),
--            search: text,
--            filters: { <key>: { values: [text|null, ...] }      -- tick list (null = blank)
--                       <key>: { min, max }                      -- number between
--                       <key>: { from, to }                      -- date between ('YYYY-MM-DD')
--                       <key>: { search } },                     -- text contains
--            sort: <key>, dir: 'asc'|'desc', page (1-based), page_size (≤ 5000),
--            facet: <key> }
-- Returns { total, rows: [...] }, or with `facet` { values: [{ value, n }] } — the column's
-- values under every OTHER filter (as a spreadsheet filter does), most common first.
-- p_query is jsonb so later stories add keys, never parameters: MAIN-152's drill-down will
-- add the Analytics selection here (see analytics_ticket_rows / analytics_issue_rows).

-- ---------------------------------------------------------------------------------------
-- Engine helpers
-- ---------------------------------------------------------------------------------------

-- Escape LIKE wildcards in user-typed text so "50%" matches literally.
CREATE OR REPLACE FUNCTION public.list_like_pattern(p_text text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
    SELECT '%' || replace(replace(replace(lower(p_text), '\', '\\'), '%', '\%'), '_', '\_') || '%';
$$;

-- Does one list row pass every column filter (except p_skip, the column whose own values a
-- facet is listing)? A missing value never passes a between or contains filter.
CREATE OR REPLACE FUNCTION public.list_row_passes(p_row jsonb, p_filters jsonb, p_skip text DEFAULT NULL)
RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
    SELECT NOT EXISTS (
        SELECT 1
        FROM   jsonb_each(coalesce(p_filters, '{}'::jsonb)) AS f(k, spec)
        WHERE  f.k IS DISTINCT FROM p_skip
          AND  jsonb_typeof(f.spec) = 'object'
          AND  NOT coalesce(
                   (NOT (f.spec ? 'values') OR EXISTS (
                        SELECT 1 FROM jsonb_array_elements(f.spec -> 'values') v
                        WHERE  (v #>> '{}') IS NOT DISTINCT FROM (p_row ->> f.k)))
               AND (nullif(f.spec ->> 'min', '') IS NULL
                    OR (p_row ->> f.k)::numeric >= (f.spec ->> 'min')::numeric)
               AND (nullif(f.spec ->> 'max', '') IS NULL
                    OR (p_row ->> f.k)::numeric <= (f.spec ->> 'max')::numeric)
               AND (nullif(f.spec ->> 'from', '') IS NULL
                    OR left(p_row ->> f.k, 10) >= (f.spec ->> 'from'))
               AND (nullif(f.spec ->> 'to', '') IS NULL
                    OR left(p_row ->> f.k, 10) <= (f.spec ->> 'to'))
               AND (nullif(f.spec ->> 'search', '') IS NULL
                    OR lower(p_row ->> f.k) LIKE public.list_like_pattern(f.spec ->> 'search')),
               false)
    );
$$;

-- IST date window → the zone-less UTC bounds of tickets/issues/job_cards.created_at
-- (timestamp WITHOUT time zone holding UTC — see CLAUDE.md, Dates and time zones).
CREATE OR REPLACE FUNCTION public.list_ist_day_start_utc(p_day date)
RETURNS timestamp
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
    SELECT (p_day::timestamp AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'UTC';
$$;

-- ---------------------------------------------------------------------------------------
-- The rows of each list
-- ---------------------------------------------------------------------------------------

-- Ticket SLA, as the ticket list shows it (mirrors TicketCard's SLABadge): a New ticket
-- counts down to acceptance; a finished one shows its stored verdict; anything else counts
-- down to its final deadline. Stored verdicts are the database's (MAIN-135) — nothing here
-- judges anything, it only labels what the countdown shows.
CREATE OR REPLACE FUNCTION public.ticket_list_rows(p_from date, p_to date)
RETURNS SETOF jsonb
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
        '_q', lower(concat_ws(' ', t.ticket_number, t.vehicle_number, t.site, t.initial_remarks, t.supervisor_name))
    ))
    FROM public.tickets t
    WHERE (p_from IS NULL OR t.created_at >= public.list_ist_day_start_utc(p_from))
      AND (p_to   IS NULL OR t.created_at <  public.list_ist_day_start_utc(p_to + 1));
$$;

CREATE OR REPLACE FUNCTION public.issue_list_rows(p_from date, p_to date)
RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'id',               i.id,
        'issue_number',     i.issue_number,
        -- "T-4768-01" sorts wrongly as text (T-999 after T-1000): sort on the numbers.
        'issue_order',      coalesce(t.ticket_number, 0)::bigint * 1000
                            + coalesce(nullif(substring(i.issue_number FROM '-(\d+)$'), '')::int, 0),
        'created_at',       i.created_at,
        'raised_on',        ((i.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date,
        'description',      i.description,
        'category',         i.category,
        'severity',         i.severity,
        'status',           i.status,
        'sla_status',       i.sla_status,
        'sla_end_date',     i.sla_end_date,
        'completed_at',     i.completed_at,
        'rating',           i.rating,
        'ticket_id',        i.ticket_id,
        'ticket_number',    t.ticket_number,
        'vehicle_number',   t.vehicle_number,
        'site',             t.site,
        'job_card_id',      i.job_card_id,
        'job_card_number',  jc.job_card_number,
        -- The job card's own type (MAIN-171). NULL when the card exists but this reader
        -- cannot see job cards (supervisors), rather than a wrong "No job card yet".
        'job_card_type',    CASE WHEN i.job_card_id IS NULL THEN 'None'
                                 ELSE jc.type::text END,
        '_q', lower(concat_ws(' ', i.issue_number, i.description, t.ticket_number, t.vehicle_number, t.site, jc.job_card_number))
    ))
    FROM public.issues i
    LEFT JOIN public.tickets   t  ON t.id  = i.ticket_id
    LEFT JOIN public.job_cards jc ON jc.id = i.job_card_id
    WHERE (p_from IS NULL OR i.created_at >= public.list_ist_day_start_utc(p_from))
      AND (p_to   IS NULL OR i.created_at <  public.list_ist_day_start_utc(p_to + 1));
$$;

CREATE OR REPLACE FUNCTION public.job_card_list_rows(p_from date, p_to date)
RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'id',               jc.id,
        'job_card_number',  jc.job_card_number,
        'created_at',       jc.created_at,
        'raised_on',        ((jc.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date,
        'vehicle_number',   jc.vehicle_number,
        'site',             jc.site,
        'type',             jc.type,
        -- In-house: everyone who logged labour on it (MAIN-116); outsourced: the supplier.
        'assignee',         CASE WHEN jc.type = 'InHouse' THEN lab.names ELSE s.entity_name END,
        'location_id',      jc.location_id,
        'workshop',         wl.name,
        'status',           jc.status,
        'open_issues',      coalesce(iss.open_count, 0),
        'issue_count',      coalesce(iss.issue_count, 0),
        -- NULL for anyone who may not see costs (job_card_value checks).
        'value',            public.job_card_value(jc),
        '_q', lower(concat_ws(' ', jc.job_card_number, jc.vehicle_number, jc.site, s.entity_name, lab.names, wl.name))
    ))
    FROM public.job_cards jc
    LEFT JOIN public.suppliers          s  ON s.id  = jc.supplier_id
    LEFT JOIN public.workshop_locations wl ON wl.id = jc.location_id
    LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE i.status = 'Open') AS open_count, count(*) AS issue_count
        FROM   public.issues i WHERE i.job_card_id = jc.id
    ) iss ON true
    LEFT JOIN LATERAL (
        SELECT string_agg(DISTINCT u.name, ', ' ORDER BY u.name) AS names
        FROM   public.issues i
        JOIN   public.issue_labour il ON il.issue_id = i.id
        JOIN   public.users u ON u.id = il.technician_id
        WHERE  i.job_card_id = jc.id
    ) lab ON true
    WHERE (p_from IS NULL OR jc.created_at >= public.list_ist_day_start_utc(p_from))
      AND (p_to   IS NULL OR jc.created_at <  public.list_ist_day_start_utc(p_to + 1));
$$;

-- Every list's rows behind one name, so the engine is written once. A constant p_list lets
-- the planner skip the other branches.
CREATE OR REPLACE FUNCTION public.list_base_rows(p_list text, p_from date, p_to date)
RETURNS SETOF jsonb
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $$
    SELECT r FROM public.ticket_list_rows(p_from, p_to) r   WHERE p_list = 'tickets'
    UNION ALL
    SELECT r FROM public.issue_list_rows(p_from, p_to) r    WHERE p_list = 'issues'
    UNION ALL
    SELECT r FROM public.job_card_list_rows(p_from, p_to) r WHERE p_list = 'job_cards';
$$;

-- ---------------------------------------------------------------------------------------
-- The engine
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.list_query(p_list text, p_query jsonb)
RETURNS jsonb
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
    v_result  jsonb;
BEGIN
    IF p_list NOT IN ('tickets', 'issues', 'job_cards') THEN
        RAISE EXCEPTION 'Unknown list %', p_list;
    END IF;

    IF v_facet IS NOT NULL THEN
        SELECT jsonb_build_object('values', coalesce(jsonb_agg(jsonb_build_object('value', val, 'n', n)
                                                     ORDER BY n DESC, val NULLS LAST), '[]'::jsonb))
        INTO   v_result
        FROM (
            SELECT r ->> v_facet AS val, count(*) AS n
            FROM   public.list_base_rows(p_list, v_from, v_to) r
            WHERE  public.list_row_passes(r, v_filters, v_facet)
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
        WHERE  public.list_row_passes(r, v_filters)
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

CREATE OR REPLACE FUNCTION public.get_ticket_list(p_query jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public'
AS $$ SELECT public.list_query('tickets', p_query); $$;

CREATE OR REPLACE FUNCTION public.get_issue_list(p_query jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public'
AS $$ SELECT public.list_query('issues', p_query); $$;

CREATE OR REPLACE FUNCTION public.get_job_card_list(p_query jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public'
AS $$ SELECT public.list_query('job_cards', p_query); $$;

COMMENT ON FUNCTION public.list_query(text, jsonb) IS
    'MAIN-151: the shared list engine — filters, search, sort, page and column facets over *_list_rows. SECURITY INVOKER, so row-level security decides the rows. p_query is jsonb: add keys, never parameters.';
COMMENT ON FUNCTION public.get_ticket_list(jsonb) IS 'MAIN-151: the Tickets list (see list_query).';
COMMENT ON FUNCTION public.get_issue_list(jsonb) IS 'MAIN-151: the Issues list (see list_query).';
COMMENT ON FUNCTION public.get_job_card_list(jsonb) IS 'MAIN-151: the Job Cards list (see list_query).';

-- Signed-in users only; everything runs as the caller, under row-level security.
DO $$
DECLARE f text;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'public.list_like_pattern(text)',
        'public.list_row_passes(jsonb, jsonb, text)',
        'public.list_ist_day_start_utc(date)',
        'public.ticket_list_rows(date, date)',
        'public.issue_list_rows(date, date)',
        'public.job_card_list_rows(date, date)',
        'public.list_base_rows(text, date, date)',
        'public.list_query(text, jsonb)',
        'public.get_ticket_list(jsonb)',
        'public.get_issue_list(jsonb)',
        'public.get_job_card_list(jsonb)'
    ] LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
    END LOOP;
END $$;
