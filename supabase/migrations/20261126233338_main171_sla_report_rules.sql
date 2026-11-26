-- MAIN-171: Analytics › SLA & tickets — every breakdown adds up to its total.
--
-- 1. One rule per number (the shape MAIN-152's drill-down will reuse): two row-level
--    functions return every ticket and every issue in the selection, each already
--    labelled with the bucket it counts in. get_maintenance_stats only counts those
--    rows, so a drill-down that lists the same rows always matches the number.
--      * Every issue category, not four fixed names (Emission, GPS and retired Other
--        were missing).
--      * Job card type comes from the job card (job_cards.type). An issue with no job
--        card is 'none' ("No job card yet").
--      * A ticket's job card type: Outsource if any of its issues is on an Outsource job
--        card, else InHouse if any is on an In-house one, else 'none'; a ticket with no
--        issues is 'no_issues'.
--      * Days are Indian: tickets.created_at is timestamp WITHOUT time zone holding UTC,
--        so it is converted UTC -> Asia/Kolkata before taking the date.
-- 2. get_maintenance_stats(date, date, text[]) is replaced by get_maintenance_stats(jsonb)
--    returning jsonb. Its return columns change, so it is dropped, not replaced.
--    p_filters is jsonb — do not add a parameter (CREATE OR REPLACE would leave a
--    second overload behind).
-- 3. issues.work_type is dropped. Nothing ever set it to anything but InHouse; the job
--    card's type is the only work type. work_type_enum stays (job_cards.type uses it).
-- 4. Two functions that relied on the session time zone being UTC now say so
--    explicitly (same results today):
--      * job_card_invoice_company compared vehicle_company_changes.created_at
--        (timestamptz) with job_cards.created_at (timestamp, UTC) implicitly.
--      * part_cost_lots cast opening_stock_lots.created_at (timestamptz) to timestamp
--        implicitly.

-- ── 1. Row-level rules ───────────────────────────────────────────────────────────

CREATE FUNCTION public.analytics_ticket_rows(p_filters jsonb)
RETURNS TABLE (
    ticket_id        uuid,
    ticket_number    integer,
    site             text,
    raised_on        date,
    status           text,
    acceptance       text,
    completion       text,
    job_card_type    text
)
LANGUAGE sql
STABLE
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
           END
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

COMMENT ON FUNCTION public.analytics_ticket_rows(jsonb) IS
    'MAIN-171: every ticket in the Analytics selection ({from, to, sites}) with the bucket it counts in. '
    'get_maintenance_stats counts these rows; a drill-down lists them (MAIN-152).';

CREATE FUNCTION public.analytics_issue_rows(p_filters jsonb)
RETURNS TABLE (
    issue_id         uuid,
    ticket_id        uuid,
    ticket_number    integer,
    site             text,
    raised_on        date,
    ticket_status    text,
    severity         text,
    category         text,
    job_card_type    text,
    rating           text,
    rating_pending   boolean
)
LANGUAGE sql
STABLE
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
           (i.rating IS NULL AND t.status IN ('Resolved', 'Closed'))
    FROM   public.analytics_ticket_rows(p_filters) t
    JOIN   public.issues i ON i.ticket_id = t.ticket_id
    LEFT   JOIN public.job_cards jc ON jc.id = i.job_card_id
$$;

COMMENT ON FUNCTION public.analytics_issue_rows(jsonb) IS
    'MAIN-171: every issue on the tickets of analytics_ticket_rows, with the buckets it counts in. '
    'job_card_type is the job card''s type, or none when the issue has no job card.';

-- ── 2. The report counts those rows ──────────────────────────────────────────────

DROP FUNCTION public.get_maintenance_stats(date, date, text[]);

CREATE FUNCTION public.get_maintenance_stats(p_filters jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
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
            'collected', (SELECT count(*) FROM iss WHERE rating IS NOT NULL),
            'by_rating', coalesce((SELECT jsonb_object_agg(rating, n)
                                   FROM (SELECT rating, count(*) n FROM iss WHERE rating IS NOT NULL GROUP BY 1) s), '{}'::jsonb)
        )
    )
$$;

COMMENT ON FUNCTION public.get_maintenance_stats(jsonb) IS
    'MAIN-171: Analytics › SLA & tickets. p_filters = {from, to, sites}; counts analytics_ticket_rows / '
    'analytics_issue_rows. jsonb argument — do not add a parameter.';

REVOKE ALL ON FUNCTION public.analytics_ticket_rows(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.analytics_issue_rows(jsonb)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_maintenance_stats(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.analytics_ticket_rows(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.analytics_issue_rows(jsonb)  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_maintenance_stats(jsonb) TO authenticated, service_role;

-- ── 3. The issue's own work type goes ────────────────────────────────────────────

ALTER TABLE public.issues DROP COLUMN work_type;

-- ── 4. Say which zone a zone-less time is in ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.job_card_invoice_company(p_job_card_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    -- job_cards.created_at is timestamp WITHOUT time zone holding UTC: say so before
    -- comparing it with vehicle_company_changes.created_at (timestamptz), instead of
    -- relying on the session time zone being UTC (MAIN-171).
    SELECT coalesce((
        SELECT c.new_company
        FROM   public.job_cards jc
        JOIN   public.vehicles v                 ON v.registration_number = jc.vehicle_number
        JOIN   public.vehicle_company_changes c  ON c.vehicle_id = v.id
        WHERE  jc.id = p_job_card_id
          AND  c.created_at <= (jc.created_at AT TIME ZONE 'UTC')
        ORDER  BY c.created_at DESC
        LIMIT  1
    ), 'nvs_travels')
$function$;

CREATE OR REPLACE FUNCTION public.part_cost_lots(p_part_id uuid, p_company text)
 RETURNS TABLE(kind text, lot_id uuid, quantity numeric, unit_cost numeric, rnk integer, at_time timestamp without time zone, recorded_at timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_found_cost numeric;
BEGIN
    -- Times here are timestamp WITHOUT time zone holding UTC, like purchase_invoices and
    -- stock_audits. opening_stock_lots.created_at is timestamptz, so it is turned into
    -- UTC explicitly rather than by the session time zone (MAIN-171).
    -- Stock found in an audit takes the part's latest cost: its latest purchase, else
    -- its latest opening price, else nothing.
    SELECT x.cost INTO v_found_cost FROM (
        SELECT ((pii.quantity * pii.unit_price - pii.discount_amount) * (1 + pii.gst_rate / 100.0)) / pii.quantity AS cost,
               1 AS r, pi.invoice_date::timestamp AS t, pi.created_at AS t2
        FROM   public.purchase_invoice_items pii
        JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
        WHERE  pii.part_id = p_part_id AND NOT public.is_workshop_move_invoice(pi.purchase_number)
        UNION ALL
        SELECT o.unit_cost, 0, o.created_at AT TIME ZONE 'UTC', o.created_at AT TIME ZONE 'UTC'
        FROM   public.opening_stock_lots o
        WHERE  o.part_id = p_part_id
    ) x
    ORDER BY x.r DESC, x.t DESC, x.t2 DESC
    LIMIT 1;

    RETURN QUERY
    SELECT 'opening'::text, o.id, o.quantity::numeric, o.unit_cost::numeric, 0,
           o.created_at AT TIME ZONE 'UTC', o.created_at AT TIME ZONE 'UTC'
    FROM   public.opening_stock_lots o
    WHERE  o.part_id = p_part_id AND o.company = p_company
    UNION ALL
    SELECT 'purchase', pii.id, pii.quantity::numeric,
           ((pii.quantity * pii.unit_price - pii.discount_amount) * (1 + pii.gst_rate / 100.0)) / pii.quantity,
           1, pi.invoice_date::timestamp, pi.created_at
    FROM   public.purchase_invoice_items pii
    JOIN   public.purchase_invoices pi ON pi.id = pii.invoice_id
    WHERE  pii.part_id = p_part_id AND pi.billed_to = p_company
      AND  NOT public.is_workshop_move_invoice(pi.purchase_number)
    UNION ALL
    SELECT 'found', i.id, i.applied_delta::numeric, coalesce(v_found_cost, 0), 1, a.completed_at, a.completed_at
    FROM   public.stock_audit_items i
    JOIN   public.stock_audits a ON a.id = i.audit_id
    WHERE  a.status = 'completed' AND i.part_id = p_part_id AND i.company = p_company
      AND  i.applied_delta > 0;
END;
$function$;
