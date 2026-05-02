-- Implement Assignment SLA tracking.
-- "Assigned" = first issue created on the ticket.
-- Deadline = ticket.created_at + assignment_sla_days working days
--   (skipping weekly offs from system_settings.sla_weekly_offs and holidays table).

-- Step 1: Add assignment_sla_status column to tickets
ALTER TABLE tickets ADD COLUMN IF NOT EXISTS assignment_sla_status sla_status_enum DEFAULT 'Pending';

-- Step 2: Helper — add N working days to a date
CREATE OR REPLACE FUNCTION add_working_days(start_date DATE, n_days INT)
RETURNS DATE
LANGUAGE plpgsql STABLE AS $$
DECLARE
    current_d   DATE := start_date;
    days_added  INT  := 0;
    weekly_offs JSONB;
    dow         INT;
    is_holiday  BOOLEAN;
BEGIN
    SELECT value::jsonb INTO weekly_offs
    FROM system_settings WHERE key = 'sla_weekly_offs';
    IF weekly_offs IS NULL THEN weekly_offs := '[0,6]'::jsonb; END IF;

    WHILE days_added < n_days LOOP
        current_d := current_d + 1;
        dow := EXTRACT(DOW FROM current_d)::INT;

        -- Skip weekly offs (day-of-week integers: 0=Sun … 6=Sat)
        IF weekly_offs @> to_jsonb(dow) THEN CONTINUE; END IF;

        -- Skip holidays
        SELECT EXISTS (SELECT 1 FROM holidays WHERE date = current_d) INTO is_holiday;
        IF is_holiday THEN CONTINUE; END IF;

        days_added := days_added + 1;
    END LOOP;

    RETURN current_d;
END;
$$;

-- Step 3: Evaluate assignment SLA for a given ticket + first-issue timestamp
CREATE OR REPLACE FUNCTION evaluate_assignment_sla(
    p_ticket_id            UUID,
    p_first_issue_created  TIMESTAMPTZ
)
RETURNS sla_status_enum
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_created_at  DATE;
    v_sla_days    INT;
    v_deadline    DATE;
BEGIN
    SELECT created_at::date INTO v_created_at FROM tickets WHERE id = p_ticket_id;

    SELECT value::INT INTO v_sla_days
    FROM system_settings WHERE key = 'assignment_sla_days';
    IF v_sla_days IS NULL THEN v_sla_days := 2; END IF;

    v_deadline := add_working_days(v_created_at, v_sla_days);

    IF p_first_issue_created::date <= v_deadline THEN
        RETURN 'Adhered'::sla_status_enum;
    ELSE
        RETURN 'Violated'::sla_status_enum;
    END IF;
END;
$$;

-- Step 4: Trigger function — fires after every issue INSERT
-- Only acts when this is the first issue for the ticket
CREATE OR REPLACE FUNCTION trg_set_assignment_sla_on_first_issue()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_prior_count INT;
BEGIN
    SELECT COUNT(*) INTO v_prior_count
    FROM issues
    WHERE ticket_id = NEW.ticket_id AND id != NEW.id;

    IF v_prior_count = 0 THEN
        UPDATE tickets
        SET assignment_sla_status = evaluate_assignment_sla(NEW.ticket_id, NEW.created_at)
        WHERE id = NEW.ticket_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assignment_sla_on_first_issue ON issues;
CREATE TRIGGER trg_assignment_sla_on_first_issue
AFTER INSERT ON issues
FOR EACH ROW EXECUTE FUNCTION trg_set_assignment_sla_on_first_issue();

-- Step 5: Backfill all existing tickets that already have at least one issue
UPDATE tickets t
SET assignment_sla_status = evaluate_assignment_sla(
    t.id,
    (SELECT MIN(created_at) FROM issues WHERE ticket_id = t.id)
)
WHERE EXISTS (SELECT 1 FROM issues WHERE ticket_id = t.id);

-- Step 6: Rewrite get_maintenance_stats to use real assignment_sla_status
CREATE OR REPLACE FUNCTION get_maintenance_stats(
    start_date_input DATE,
    end_date_input   DATE,
    site_filter      TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql AS $$
DECLARE
  result JSON;
BEGIN
  WITH filtered_tickets AS (
    SELECT
      t.id,
      t.status,
      t.site,
      t.overall_sla_status,
      t.assignment_sla_status,
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
      COUNT(*)                                                      AS total_tickets,
      COUNT(*) FILTER (WHERE status IN ('New', 'Pending'))          AS status_pending,
      COUNT(*) FILTER (WHERE status = 'Accepted')                   AS status_assigned,
      COUNT(*) FILTER (WHERE status IN ('Resolved', 'Closed'))      AS status_completed,
      COUNT(*) FILTER (WHERE status = 'Rejected')                   AS status_rejected,
      COUNT(*) FILTER (WHERE overall_sla_status = 'Adhered')        AS comp_adhered,
      COUNT(*) FILTER (WHERE overall_sla_status = 'Violated')       AS comp_violated,
      COUNT(*) FILTER (WHERE assignment_sla_status = 'Pending')     AS assign_pending,
      COUNT(*) FILTER (WHERE assignment_sla_status = 'Adhered')     AS assign_adhered,
      COUNT(*) FILTER (WHERE assignment_sla_status = 'Violated')    AS assign_violated
    FROM filtered_tickets
    GROUP BY month_key, month_label
  ),
  issue_stats AS (
    SELECT
      month_key,
      month_label,
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
      COUNT(*) FILTER (WHERE work_type = 'InHouse')                           AS type_in_house,
      COUNT(*) FILTER (WHERE work_type = 'Outsource')                         AS type_outsource,
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

      COALESCE(t.assign_pending,    0) AS assign_unassigned_within,
      COALESCE(t.assign_adhered,    0) AS assign_adhered,
      COALESCE(t.assign_violated,   0) AS assign_violated,

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
