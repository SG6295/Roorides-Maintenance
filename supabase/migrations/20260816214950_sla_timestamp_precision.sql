-- MAIN-45, part 2 of 4: SLA deadlines become timestamps in IST.
--
-- Before this, a deadline was a bare `date` produced by `DATE(created_at) + rule_days`.
-- Three things were wrong with that:
--
--   1. The creation time was thrown away, so a ticket raised at 09:00 and one raised at
--      23:00 the same day shared a deadline.
--   2. DATE(created_at) takes the *UTC* date of a UTC-holding naive column, so a ticket
--      raised between 00:00 and 05:29 IST started its clock a day early.
--   3. Breach was tested with CURRENT_DATE, so a ticket only turned Violated when the
--      calendar rolled over rather than when the deadline actually passed.
--
-- Deadlines are now timestamptz, computed in IST, carrying the time of day the work was
-- raised, and compared against now().
--
-- Policy change that rides along (see the ticket's 2026-08-17 decision): completion SLA
-- previously counted plain calendar days while only acceptance SLA counted working days.
-- Both now count working days, skipping sla_weekly_offs and the holidays calendar. This
-- lengthens completion deadlines, so adherence figures are not comparable across this
-- migration.

-- 1. add_working_days now carries the time of day.
--
-- Which calendar day a deadline lands on is a local question, so the walk happens in IST
-- wall-clock and the result is converted back to an absolute instant. The old
-- (date, integer) form is dropped so there is exactly one definition of a working day.

CREATE OR REPLACE FUNCTION public.add_working_days(start_ts timestamptz, n_days integer)
    RETURNS timestamptz
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_local      timestamp;
    v_date       date;
    v_time       time;
    days_added   int := 0;
    iterations   int := 0;
    weekly_offs  jsonb;
    dow          int;
    is_holiday   boolean;
BEGIN
    IF start_ts IS NULL OR n_days IS NULL THEN
        RETURN NULL;
    END IF;

    v_local := start_ts AT TIME ZONE 'Asia/Kolkata';
    v_date  := v_local::date;
    v_time  := v_local::time;

    SELECT value::jsonb INTO weekly_offs
      FROM system_settings WHERE key = 'sla_weekly_offs';
    IF weekly_offs IS NULL THEN weekly_offs := '[0,6]'::jsonb; END IF;

    WHILE days_added < n_days LOOP
        -- Guard against a configuration that marks every day an off-day: without this the
        -- loop never terminates and the trigger hangs whatever transaction called it.
        iterations := iterations + 1;
        IF iterations > 3650 THEN
            RAISE EXCEPTION
                'add_working_days: no working day found within 10 years of %. Check system_settings.sla_weekly_offs (currently %) - every weekday may be marked an off-day.',
                start_ts, weekly_offs;
        END IF;

        v_date := v_date + 1;
        dow := EXTRACT(DOW FROM v_date)::int;

        -- Skip weekly offs (day-of-week integers: 0=Sun ... 6=Sat)
        IF weekly_offs @> to_jsonb(dow) THEN CONTINUE; END IF;

        -- Skip holidays
        SELECT EXISTS (SELECT 1 FROM holidays WHERE date = v_date) INTO is_holiday;
        IF is_holiday THEN CONTINUE; END IF;

        days_added := days_added + 1;
    END LOOP;

    RETURN (v_date + v_time) AT TIME ZONE 'Asia/Kolkata';
END;
$$;

DROP FUNCTION IF EXISTS public.add_working_days(date, integer);

-- 2. The deadline columns become timestamps.
--
-- Existing values are discarded rather than reinterpreted (ticket decision 2). A stored
-- `date` cannot say which instant it meant, and inventing one would manufacture verdicts
-- that were never measured. Production holds 1,653 tickets, all Resolved or Rejected and
-- none open, so nothing in flight loses a deadline. Part 4 marks the verdicts NA.

-- trg_update_ticket_sla_agg lists sla_end_date in its UPDATE OF clause, and Postgres
-- refuses to alter the type of a column a trigger definition names. Drop it around the
-- change and put it back identically.
DROP TRIGGER IF EXISTS trg_update_ticket_sla_agg ON public.issues;

ALTER TABLE public.issues
    ALTER COLUMN sla_end_date TYPE timestamptz USING NULL::timestamptz;

ALTER TABLE public.tickets
    ALTER COLUMN final_sla_end_date TYPE timestamptz USING NULL::timestamptz;

CREATE TRIGGER trg_update_ticket_sla_agg
    AFTER INSERT OR UPDATE OF sla_end_date, status, category, severity ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.calculate_ticket_overall_sla();

-- The acceptance deadline is now stored rather than recomputed in JavaScript. TicketCard
-- used to build it with addDays(), plain 24-hour days, while the database used working
-- days - so across a weekend the badge and the stored verdict could disagree. One value,
-- computed once, in the place that owns the definition.
ALTER TABLE public.tickets
    ADD COLUMN IF NOT EXISTS acceptance_sla_end_date timestamptz;

COMMENT ON COLUMN public.tickets.acceptance_sla_end_date IS
    'When acceptance is due, in working days from creation. Stamped on insert; recomputed if acceptance_sla_days changes while the ticket is still awaiting acceptance.';

-- 3. Issue deadline.

CREATE OR REPLACE FUNCTION public.calculate_issue_sla_dynamic()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    rule_days INTEGER;
BEGIN
    -- Recalculate on INSERT, or on UPDATE when category/severity actually changed.
    IF TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND (
           NEW.category  IS DISTINCT FROM OLD.category OR
           NEW.severity  IS DISTINCT FROM OLD.severity
       ))
    THEN
        SELECT sla_days INTO rule_days
        FROM sla_rules_config
        WHERE category = NEW.category AND severity = NEW.severity;

        IF rule_days IS NULL THEN rule_days := 3; END IF;

        NEW.sla_days := rule_days;
        -- created_at is `timestamp without time zone` holding UTC; name the zone rather
        -- than relying on the session default.
        NEW.sla_end_date := add_working_days(NEW.created_at AT TIME ZONE 'UTC', rule_days);
    END IF;

    RETURN NEW;
END;
$$;

-- 4. Ticket rollup.

CREATE OR REPLACE FUNCTION public.calculate_ticket_overall_sla()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_final_sla   timestamptz;
    v_status      text;
    v_resolved_at timestamptz;
BEGIN
    UPDATE tickets
    SET final_sla_end_date = (
        SELECT MAX(sla_end_date) FROM issues WHERE ticket_id = NEW.ticket_id
    )
    WHERE id = NEW.ticket_id
    RETURNING final_sla_end_date, status::text,
              COALESCE(resolved_at, closed_at) AT TIME ZONE 'UTC'
    INTO v_final_sla, v_status, v_resolved_at;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, now())
                THEN 'Adhered'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < now()
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.ticket_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_ticket_sla_on_status_change()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_final_sla   timestamptz;
    v_resolved_at timestamptz;
BEGIN
    SELECT final_sla_end_date, COALESCE(resolved_at, closed_at) AT TIME ZONE 'UTC'
    INTO v_final_sla, v_resolved_at
    FROM tickets WHERE id = NEW.id;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed') AND v_final_sla >= COALESCE(v_resolved_at, now())
                THEN 'Adhered'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed')
                THEN 'Violated'::sla_status_enum
            WHEN v_final_sla < now()
                THEN 'Violated'::sla_status_enum
            ELSE 'Pending'::sla_status_enum
        END
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$;

-- 5. Acceptance SLA.

CREATE OR REPLACE FUNCTION public.acceptance_deadline(p_created_at timestamptz)
    RETURNS timestamptz
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_sla_days INT;
BEGIN
    SELECT COALESCE(value::int, 2) INTO v_sla_days
      FROM system_settings WHERE key = 'acceptance_sla_days';
    IF v_sla_days IS NULL THEN v_sla_days := 2; END IF;

    RETURN add_working_days(p_created_at, v_sla_days);
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_stamp_acceptance_deadline()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    NEW.acceptance_sla_end_date := acceptance_deadline(NEW.created_at AT TIME ZONE 'UTC');
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_acceptance_deadline ON public.tickets;
CREATE TRIGGER trg_stamp_acceptance_deadline
    BEFORE INSERT ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.trg_stamp_acceptance_deadline();

CREATE OR REPLACE FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamptz)
    RETURNS public.sla_status_enum
    LANGUAGE plpgsql
    STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_deadline timestamptz;
BEGIN
    SELECT COALESCE(acceptance_sla_end_date, acceptance_deadline(created_at AT TIME ZONE 'UTC'))
      INTO v_deadline
      FROM tickets WHERE id = p_ticket_id;

    IF p_first_issue_created <= v_deadline THEN
        RETURN 'Adhered'::sla_status_enum;
    ELSE
        RETURN 'Violated'::sla_status_enum;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_set_acceptance_sla_on_first_issue()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
    v_prior_count INT;
BEGIN
    SELECT COUNT(*) INTO v_prior_count
    FROM issues WHERE ticket_id = NEW.ticket_id AND id != NEW.id;

    IF v_prior_count = 0 THEN
        UPDATE tickets
        SET acceptance_sla_status =
            evaluate_acceptance_sla(NEW.ticket_id, NEW.created_at AT TIME ZONE 'UTC')
        WHERE id = NEW.ticket_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
DECLARE
  v_deadline    timestamptz;
  v_first_issue timestamptz;
BEGIN
  -- Only act when status transitions TO Rejected
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN

    NEW.rejected_at := NOW();

    -- Only evaluate if still Pending (not already resolved by the first-issue trigger)
    IF NEW.acceptance_sla_status = 'Pending' THEN

      v_deadline := COALESCE(
          NEW.acceptance_sla_end_date,
          acceptance_deadline(NEW.created_at AT TIME ZONE 'UTC')
      );

      SELECT MIN(created_at) AT TIME ZONE 'UTC'
        INTO v_first_issue
        FROM issues
       WHERE ticket_id = NEW.id;

      IF v_first_issue IS NOT NULL THEN
        -- First issue exists; evaluate against its creation time
        IF v_first_issue <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      ELSE
        -- No issues ever created; evaluate against rejection time
        IF NOW() <= v_deadline THEN
          NEW.acceptance_sla_status := 'Adhered';
        ELSE
          NEW.acceptance_sla_status := 'Violated';
        END IF;
      END IF;

    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 6. Remove the unreachable copies of the SLA rules.
--
-- update_ticket_sla() was never attached to anything: no trigger references it (the
-- similarly-named trg_update_ticket_sla_agg runs calculate_ticket_overall_sla), and it
-- reads six columns that exist on no table - impact, assigned_date, completed_date,
-- assignment_sla_status, completion_sla_status, csat_score. Attaching it would fail at
-- runtime with `record "new" has no field "impact"`. It is a fossil of a schema that
-- predates the issues table.
--
-- calculate_sla_days() hardcoded a third copy of the day table and was called only from
-- update_ticket_sla(), so it goes with it. sla_rules_config is now the only place the
-- day counts live (MAIN-47 removed the second).

DROP FUNCTION IF EXISTS public.update_ticket_sla();
DROP FUNCTION IF EXISTS public.calculate_sla_days(text, text);

-- 7. Analytics aggregate.
--
-- CURRENT_DATE comparisons become now(), the acceptance deadline comes from the stored
-- column, and NA is surfaced in its own counters rather than being folded into Pending -
-- 1,653 historical tickets would otherwise read as work still in flight.

DROP FUNCTION IF EXISTS public.get_maintenance_stats(date, date, text);

CREATE FUNCTION public.get_maintenance_stats(
    start_date_input date DEFAULT NULL::date,
    end_date_input date DEFAULT NULL::date,
    site_filter text DEFAULT NULL::text
)
RETURNS TABLE(
    total_tickets bigint, status_new bigint, status_pending bigint, status_accepted bigint,
    status_wip bigint, status_resolved bigint, status_closed bigint, status_rejected bigint,
    status_completed bigint, major_total bigint, major_electrical bigint, major_mechanical bigint,
    major_body bigint, major_tyre bigint, minor_total bigint, minor_electrical bigint,
    minor_mechanical bigint, minor_body bigint, minor_tyre bigint, type_in_house bigint,
    type_outsource bigint, accept_pending bigint, accept_adhered bigint, accept_violated bigint,
    accept_na bigint, comp_in_wip_within bigint, comp_in_adhered bigint, comp_in_violated bigint,
    comp_in_na bigint, comp_out_wip_within bigint, comp_out_adhered bigint, comp_out_violated bigint,
    comp_out_na bigint, rating_pending bigint, rating_collected bigint, rating_good bigint,
    rating_ok bigint, rating_bad bigint, csat_score_sum bigint, total_completed_tickets bigint
)
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
      AND (site_filter       IS NULL OR t.site = site_filter)
  ),
  issue_data AS (
    SELECT i.*
    FROM issues i
    JOIN tickets t ON i.ticket_id = t.id
    WHERE (start_date_input IS NULL OR t.created_at::date >= start_date_input)
      AND (end_date_input   IS NULL OR t.created_at::date <= end_date_input)
      AND (site_filter       IS NULL OR t.site = site_filter)
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
