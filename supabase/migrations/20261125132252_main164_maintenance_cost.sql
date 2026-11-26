-- MAIN-164: Vehicle history and analytics costs.
--
-- 1. maintenance_cost_lines(p_filters jsonb) (service-role only) — every line the
--    vehicle page and Analytics › Maintenance cost add up, derived on the fly (nothing
--    stored); get_maintenance_cost(p_filters jsonb) is the reader the app calls. It checks
--    the caller and returns every line in ONE compact jsonb ({columns, rows}) because the
--    fleet has ~12,000 lines and PostgREST pages set-returning functions at 1,000 rows,
--    which would re-run the query a dozen times per screen:
--      kind 'spare'      an in-house spare at its first-in-first-out cost incl. GST
--                        (spare_cost_amount, which already uses a transfer's amount)
--      kind 'outsourced' an outsourced job card's own invoice, Approved Amount split
--                        equally across the card's issues (one row per issue)
--      kind 'mvi'        a multi-vehicle invoice line
--      kind 'labour'     an issue's labour hours (no rupees), dated by completed_on
--      kind 'job_card'   one row per job card (amount 0) so cards without a cost count
--    Each row carries date (IST), vehicle, company, hub, site, category and the job
--    card's typed odometer. get_maintenance_cost: exec, super_admin and finance only.
--    p_filters: {"from": "YYYY-MM-DD", "to": "YYYY-MM-DD", "vehicle": "<reg>"} — all
--    optional. jsonb on purpose: do not add a parameter (a second overload).
--
-- 2. guard_job_card_odometer — a job card can't leave Open without an odometer
--    reading, and a closed card's reading can't be cleared. Service-role writes pass.

-- ---------------------------------------------------------------------------
-- 1. Cost lines
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.maintenance_cost_lines(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
    line_id               text,
    kind                  text,
    cost_date             date,
    vehicle_number        text,
    company               text,
    hub                   text,
    site                  text,
    category              text,
    split_count           integer,
    amount                numeric,
    hours                 numeric,
    price_missing         boolean,
    awaiting_finance      boolean,
    job_card_id           uuid,
    job_card_number       integer,
    job_card_status       text,
    job_card_type         text,
    job_card_odometer     integer,
    batch_number          integer,
    work_type             text,
    work_type_other       text,
    part_name             text,
    quantity              numeric,
    unit                  text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_from    date := nullif(p_filters->>'from', '')::date;
    v_to      date := nullif(p_filters->>'to', '')::date;
    v_vehicle text := nullif(btrim(p_filters->>'vehicle'), '');
BEGIN
    RETURN QUERY
    WITH jc AS (
        SELECT j.id, j.job_card_number, j.vehicle_number, j.site, j.status::text AS status,
               j.type::text AS type, j.odometer, j.created_at, j.completed_at,
               w.name AS hub,
               public.vehicle_company_at(j.vehicle_number, j.created_at AT TIME ZONE 'UTC') AS company
        FROM   public.job_cards j
        LEFT   JOIN public.workshop_locations w ON w.id = j.location_id
        WHERE  v_vehicle IS NULL OR j.vehicle_number = v_vehicle
    ),
    lines AS (
        -- One row per job card, so cards with no cost still count.
        SELECT 'job_card:' || jc.id::text AS line_id, 'job_card'::text AS kind,
               ((jc.created_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date AS cost_date,
               jc.vehicle_number, jc.company, jc.hub, jc.site,
               NULL::text AS category, NULL::integer AS split_count,
               0::numeric AS amount, NULL::numeric AS hours,
               false AS price_missing, false AS awaiting_finance,
               jc.id AS job_card_id, jc.job_card_number, jc.status AS job_card_status,
               jc.type AS job_card_type, jc.odometer AS job_card_odometer,
               NULL::integer AS batch_number, NULL::text AS work_type, NULL::text AS work_type_other,
               NULL::text AS part_name, NULL::numeric AS quantity, NULL::text AS unit
        FROM   jc

        UNION ALL
        -- In-house spares. Spares on an outsourced card are not a cost: the card's
        -- value is its invoice (job_card_value).
        SELECT 'spare:' || ip.id::text, 'spare',
               ((ip.added_at AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date,
               jc.vehicle_number, jc.company, jc.hub, jc.site,
               i.category::text, NULL::integer,
               coalesce(c.amt, 0), NULL::numeric,
               c.amt IS NULL, false,
               jc.id, jc.job_card_number, jc.status, jc.type, jc.odometer,
               NULL::integer, NULL::text, NULL::text,
               p.name, ip.quantity_used, p.unit
        FROM   jc
        JOIN   public.issues i       ON i.job_card_id = jc.id
        JOIN   public.issue_parts ip ON ip.issue_id = i.id
        JOIN   public.parts p        ON p.id = ip.part_id
        CROSS  JOIN LATERAL (SELECT public.spare_cost_amount(ip.id) AS amt) c
        WHERE  jc.type = 'InHouse'

        UNION ALL
        -- Outsourced job cards: their own invoice's Approved Amount, split equally
        -- across the card's issues. Rejected invoices are left out.
        SELECT 'outsourced:' || oi.id::text || ':' || i.id::text, 'outsourced',
               coalesce(oi.date_of_activity,
                        ((coalesce(jc.completed_at, jc.created_at) AT TIME ZONE 'UTC') AT TIME ZONE 'Asia/Kolkata')::date),
               jc.vehicle_number, jc.company, jc.hub, jc.site,
               i.category::text, n.cnt::integer,
               oi.approved_amount / n.cnt, NULL::numeric,
               false,
               oi.finance_payment_status NOT IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed'),
               jc.id, jc.job_card_number, jc.status, jc.type, jc.odometer,
               NULL::integer, NULL::text, NULL::text,
               NULL::text, NULL::numeric, NULL::text
        FROM   jc
        JOIN   public.outsource_invoices oi ON oi.job_card_id = jc.id
        JOIN   public.issues i ON i.job_card_id = jc.id
        CROSS  JOIN LATERAL (SELECT count(*) AS cnt FROM public.issues i2 WHERE i2.job_card_id = jc.id) n
        WHERE  jc.type = 'Outsource'
          AND  oi.approved_amount IS NOT NULL
          AND  oi.finance_payment_status <> 'Reject'

        UNION ALL
        -- Multi-vehicle invoice lines (cancelled invoices and rejected ones left out).
        SELECT 'mvi:' || bsv.id::text, 'mvi',
               coalesce(oi.date_of_activity, ((bs.created_at) AT TIME ZONE 'Asia/Kolkata')::date),
               bsv.vehicle_number, bs.billed_to, NULL::text, bsv.site,
               NULL::text, NULL::integer,
               bsv.amount, NULL::numeric,
               false,
               coalesce(oi.finance_payment_status, 'New') NOT IN ('Accepted', 'GST reconciled & closed', 'GST not applicable & closed'),
               bsv.job_card_id, lj.job_card_number, NULL::text, NULL::text, NULL::integer,
               bs.batch_number, bsv.work_type, bsv.work_type_other,
               NULL::text, bsv.quantity::numeric, NULL::text
        FROM   public.batch_service_vehicles bsv
        JOIN   public.batch_services bs ON bs.id = bsv.batch_service_id
        LEFT   JOIN public.outsource_invoices oi ON oi.batch_service_id = bs.id
        LEFT   JOIN public.job_cards lj ON lj.id = bsv.job_card_id
        WHERE  bs.status <> 'Cancelled'
          AND  coalesce(oi.finance_payment_status, 'New') <> 'Reject'
          AND  (v_vehicle IS NULL OR bsv.vehicle_number = v_vehicle)

        UNION ALL
        -- Labour hours per issue, as issueLabourHours() counts them: technicians'
        -- hours when any are recorded, else the pre-MAIN-116 unattributed hours.
        SELECT 'labour:' || i.id::text, 'labour',
               i.completed_on,
               jc.vehicle_number, jc.company, jc.hub, jc.site,
               i.category::text, NULL::integer,
               0::numeric, h.hrs,
               false, false,
               jc.id, jc.job_card_number, jc.status, jc.type, jc.odometer,
               NULL::integer, NULL::text, NULL::text,
               NULL::text, NULL::numeric, NULL::text
        FROM   jc
        JOIN   public.issues i ON i.job_card_id = jc.id
        CROSS  JOIN LATERAL (
            SELECT CASE WHEN EXISTS (SELECT 1 FROM public.issue_labour il WHERE il.issue_id = i.id)
                        THEN (SELECT sum(il.hours) FROM public.issue_labour il WHERE il.issue_id = i.id)
                        ELSE nullif(i.labour_hours, 0)
                   END AS hrs
        ) h
        WHERE  h.hrs IS NOT NULL
    )
    SELECT l.line_id, l.kind, l.cost_date, l.vehicle_number, l.company, l.hub, l.site,
           l.category, l.split_count, l.amount, l.hours, l.price_missing, l.awaiting_finance,
           l.job_card_id, l.job_card_number, l.job_card_status, l.job_card_type, l.job_card_odometer,
           l.batch_number, l.work_type, l.work_type_other, l.part_name, l.quantity, l.unit
    FROM   lines l
    WHERE  (v_from IS NULL OR l.cost_date >= v_from)
      AND  (v_to   IS NULL OR l.cost_date <= v_to)
      -- Labour on an item not yet Done has no date: it belongs to no period.
      AND  (l.kind <> 'labour' OR l.cost_date IS NOT NULL)
    ORDER  BY l.line_id;
END;
$$;

COMMENT ON FUNCTION public.maintenance_cost_lines(jsonb) IS
'MAIN-164: every maintenance cost line (in-house spares, outsourced invoices split across issues, multi-vehicle invoice lines), labour hours and one row per job card, with date (IST), vehicle, company, hub, site and category. Service-role only; the app reads it through get_maintenance_cost. p_filters {from, to, vehicle} is jsonb — do not add a parameter.';

REVOKE ALL ON FUNCTION public.maintenance_cost_lines(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.maintenance_cost_lines(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_maintenance_cost(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NOT (public.is_maintenance_exec() OR public.is_finance()) THEN
        RAISE EXCEPTION 'Only maintenance executives, super admins and finance can see maintenance costs.'
            USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'columns', jsonb_build_array(
            'line_id', 'kind', 'cost_date', 'vehicle_number', 'company', 'hub', 'site',
            'category', 'split_count', 'amount', 'hours', 'price_missing', 'awaiting_finance',
            'job_card_id', 'job_card_number', 'job_card_status', 'job_card_type', 'job_card_odometer',
            'batch_number', 'work_type', 'work_type_other', 'part_name', 'quantity', 'unit'),
        'rows', coalesce((
            SELECT jsonb_agg(jsonb_build_array(
                       l.line_id, l.kind, l.cost_date, l.vehicle_number, l.company, l.hub, l.site,
                       l.category, l.split_count, l.amount, l.hours, l.price_missing, l.awaiting_finance,
                       l.job_card_id, l.job_card_number, l.job_card_status, l.job_card_type, l.job_card_odometer,
                       l.batch_number, l.work_type, l.work_type_other, l.part_name, l.quantity, l.unit)
                   ORDER BY l.line_id)
            FROM public.maintenance_cost_lines(p_filters) l), '[]'::jsonb)
    );
END;
$$;

COMMENT ON FUNCTION public.get_maintenance_cost(jsonb) IS
'MAIN-164: the app''s reader for maintenance_cost_lines — exec, super_admin and finance only; every line in one jsonb {columns, rows} (rows are arrays in column order). p_filters {from, to, vehicle} is jsonb — do not add a parameter.';

REVOKE ALL ON FUNCTION public.get_maintenance_cost(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_maintenance_cost(jsonb) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Odometer required before a job card is closed
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.guard_job_card_odometer()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
    -- Service-role writes (the prod→staging seed) pass, like the other guards.
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    IF OLD.status = 'Open' AND NEW.status <> 'Open' AND NEW.odometer IS NULL THEN
        RAISE EXCEPTION 'Enter the odometer reading before closing job card %.', NEW.job_card_number
            USING HINT = 'ODOMETER_REQUIRED';
    END IF;

    IF NEW.status <> 'Open' AND OLD.odometer IS NOT NULL AND NEW.odometer IS NULL THEN
        RAISE EXCEPTION 'Job card % is closed, so its odometer reading can be corrected but not removed.', NEW.job_card_number
            USING HINT = 'ODOMETER_REQUIRED';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_job_card_odometer() IS
'MAIN-164: a job card cannot leave Open without an odometer reading, and a closed card''s reading cannot be cleared. Old closed cards with no reading are left alone. Service-role writes pass.';

DROP TRIGGER IF EXISTS trg_guard_job_card_odometer ON public.job_cards;
CREATE TRIGGER trg_guard_job_card_odometer
    BEFORE UPDATE OF status, odometer ON public.job_cards
    FOR EACH ROW EXECUTE FUNCTION public.guard_job_card_odometer();
