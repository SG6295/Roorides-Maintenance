-- MAIN-135: the SLA follows the agreed business rules.
--
--   1. The Turnaround clock starts when the ticket is raised: each issue's deadline is the
--      ticket's raise time + the issue's Turnaround Time in working days, including issues
--      added later. The ticket's deadline is the longest of its issues'.
--   2. Every issue has its own SLA status, judged at its activity complete time
--      (issues.completed_at, new): stamped when the issue is marked Done, correctable by the
--      exec but never into the future, and every change logged on the ticket timeline.
--   3. A ticket's finish is the latest activity complete time among its issues, once every
--      issue is Done.
--   4. Pending / Adhered / Violated / Not applicable (NA). NA: a ticket with no issues, and
--      tickets and issues raised before SLA tracking (6 May - 13 Aug 2026).
--   5. A ticket can't be rejected while it has issues. Past Rejected tickets that had issues
--      are judged, with their issues, at their rejection time.
--   6. Stored statuses are never more than an hour old (pg_cron, hourly).
--   7. An issue can leave Done only while it is unrated; its ticket goes back to Work In
--      Progress and resolved_at is cleared.
--   8. An issue added to a Resolved ticket sends it back to Work In Progress. Closed and
--      Rejected tickets take no new issues.
--
-- refresh_ticket_sla() holds rules 2-5 and is what every trigger and the hourly job call.
-- Deadlines are not recomputed by it: they are fixed when an issue is added or its
-- category/severity changes, and by recalculate_open_slas() for open work when the SLA
-- settings change. The backfill is the next migration.
--
-- Guards let service-role writes (auth.uid() IS NULL) through, as the other guards do:
-- the prod->staging seed inserts issues into Closed and Rejected tickets.

-- ---------------------------------------------------------------------------------------
-- 1. Activity complete time
-- ---------------------------------------------------------------------------------------

ALTER TABLE public.issues ADD COLUMN completed_at timestamp with time zone;

COMMENT ON COLUMN public.issues.completed_at IS
    'Activity complete time: when the issue was finished. Stamped when it is marked Done, cleared when it leaves Done; the exec may correct it, never into the future. Every change is logged on the ticket timeline. The issue''s SLA is judged against it (MAIN-135).';
COMMENT ON COLUMN public.issues.completed_on IS
    'IST date of completed_at, kept in step by set_issue_completed_on. Labour analytics place hours by this date.';
COMMENT ON COLUMN public.issues.sla_status IS
    'The issue''s own SLA status, written by refresh_ticket_sla (MAIN-135).';

-- A write that sets only completed_on (a date, no time) gets 00:00 IST on that date.
CREATE OR REPLACE FUNCTION public.set_issue_completed_on()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.status::text <> 'Done' THEN
        NEW.completed_at := NULL;
        NEW.completed_on := NULL;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE'
       AND NEW.completed_on IS DISTINCT FROM OLD.completed_on
       AND NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at
       AND NEW.completed_on IS NOT NULL THEN
        NEW.completed_at := NEW.completed_on::timestamp AT TIME ZONE 'Asia/Kolkata';
    END IF;

    -- On reaching Done the row carries the NULL it was cleared to, so this stamps now
    -- unless the caller sent a time or a date of its own.
    IF NEW.completed_at IS NULL THEN
        NEW.completed_at := COALESCE(NEW.completed_on::timestamp AT TIME ZONE 'Asia/Kolkata', now());
    END IF;

    IF NEW.completed_at > now() THEN
        RAISE EXCEPTION 'The activity complete time cannot be in the future.';
    END IF;

    NEW.completed_on := (NEW.completed_at AT TIME ZONE 'Asia/Kolkata')::date;
    RETURN NEW;
END;
$function$;

-- Column triggers fire on the UPDATE's SET list, not on what a BEFORE trigger changes, so
-- status is listed: reaching or leaving Done changes completed_at.
DROP TRIGGER IF EXISTS trg_set_issue_completed_on ON public.issues;
CREATE TRIGGER trg_set_issue_completed_on
    BEFORE INSERT OR UPDATE OF status, completed_on, completed_at ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.set_issue_completed_on();

-- Logs every change, including the stamp on Done and the clear on leaving it, in the shape
-- TicketTimeline renders for issue edits. The value is the IST time as text.
CREATE OR REPLACE FUNCTION public.log_issue_completed_at_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.completed_at IS NOT DISTINCT FROM OLD.completed_at THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, performed_by)
    VALUES ('issues', NEW.ticket_id, 'UPDATE',
            jsonb_build_object('issue_number', NEW.issue_number, 'description', NEW.description,
                               'activity_complete_time', to_char(OLD.completed_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH24:MI')),
            jsonb_build_object('issue_number', NEW.issue_number, 'description', NEW.description,
                               'activity_complete_time', to_char(NEW.completed_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH24:MI')),
            array['activity_complete_time'],
            auth.uid());

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS issue_completed_at_audit ON public.issues;
CREATE TRIGGER issue_completed_at_audit
    AFTER UPDATE OF status, completed_on, completed_at ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.log_issue_completed_at_change();

-- ---------------------------------------------------------------------------------------
-- 2. The rules
-- ---------------------------------------------------------------------------------------

-- SLA tracking started between the last NA ticket (raised 13 Aug 2026) and the first
-- tracked one (17 Aug). tickets.created_at is timestamp without time zone holding UTC;
-- 2026-08-13 18:30 UTC is 14 Aug 00:00 IST.
CREATE OR REPLACE FUNCTION public.is_sla_tracked(p_raised_at timestamp without time zone)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT p_raised_at >= timestamp '2026-08-13 18:30:00';
$function$;

-- Pending / Adhered / Violated for one deadline. p_finished_at is NULL while unfinished.
CREATE OR REPLACE FUNCTION public.sla_verdict(p_deadline timestamptz, p_finished_at timestamptz)
 RETURNS sla_status_enum
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE
        WHEN p_deadline IS NULL         THEN 'NA'
        WHEN p_finished_at IS NOT NULL  THEN CASE WHEN p_finished_at <= p_deadline THEN 'Adhered' ELSE 'Violated' END
        WHEN p_deadline < now()         THEN 'Violated'
        ELSE 'Pending'
    END::sla_status_enum;
$function$;

-- Judges one ticket and its issues against their stored deadlines. Writes only what
-- changes. Writes issues.sla_status and the ticket's deadline and status, none of which
-- the issue triggers below watch, so it cannot recurse.
CREATE OR REPLACE FUNCTION public.refresh_ticket_sla(p_ticket_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_ticket   tickets%ROWTYPE;
    v_tracked  boolean;
    v_issues   int;
    v_all_done boolean;
    v_deadline timestamptz;
    v_finish   timestamptz;
    v_status   sla_status_enum;
BEGIN
    SELECT * INTO v_ticket FROM tickets WHERE id = p_ticket_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    v_tracked := is_sla_tracked(v_ticket.created_at);

    UPDATE issues i
    SET sla_status = v.verdict
    FROM (
        SELECT id,
               CASE WHEN NOT v_tracked THEN 'NA'::sla_status_enum
                    ELSE sla_verdict(sla_end_date,
                                     CASE WHEN v_ticket.status = 'Rejected' THEN v_ticket.rejected_at
                                          WHEN status = 'Done' THEN completed_at
                                     END)
               END AS verdict
        FROM issues
        WHERE ticket_id = p_ticket_id
    ) v
    WHERE i.id = v.id
      AND i.sla_status IS DISTINCT FROM v.verdict;

    SELECT count(*), bool_and(status = 'Done'), max(sla_end_date), max(completed_at)
    INTO v_issues, v_all_done, v_deadline, v_finish
    FROM issues
    WHERE ticket_id = p_ticket_id;

    IF NOT v_tracked OR v_issues = 0 THEN
        v_status := 'NA';
    ELSE
        v_status := sla_verdict(v_deadline,
                                CASE WHEN v_ticket.status = 'Rejected' THEN v_ticket.rejected_at
                                     WHEN v_all_done THEN v_finish
                                END);
    END IF;

    UPDATE tickets
    SET final_sla_end_date = v_deadline,
        overall_sla_status = v_status
    WHERE id = p_ticket_id
      AND (final_sla_end_date IS DISTINCT FROM v_deadline
           OR overall_sla_status IS DISTINCT FROM v_status);
END;
$function$;

-- ---------------------------------------------------------------------------------------
-- 3. Triggers that call the rules
-- ---------------------------------------------------------------------------------------

-- Deadline from the ticket's raise time, fixed on insert and on a category/severity change.
CREATE OR REPLACE FUNCTION public.calculate_issue_sla_dynamic()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    rule_days INTEGER;
    v_raised  timestamp;
BEGIN
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

        SELECT created_at INTO v_raised FROM tickets WHERE id = NEW.ticket_id;

        NEW.sla_days := rule_days;
        -- created_at is `timestamp without time zone` holding UTC. A pre-tracking ticket's
        -- issues have no deadline (MAIN-45).
        NEW.sla_end_date := CASE WHEN is_sla_tracked(v_raised)
                                 THEN add_working_days(v_raised AT TIME ZONE 'UTC', rule_days)
                            END;
    END IF;

    RETURN NEW;
END;
$function$;

-- Re-judges the ticket whenever an issue is added, removed, or changes anything the
-- verdict reads. sla_end_date moves through category/severity (BEFORE trigger above) and
-- recalculate_open_slas; completed_at through status and completed_on.
CREATE OR REPLACE FUNCTION public.calculate_ticket_overall_sla()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        PERFORM refresh_ticket_sla(OLD.ticket_id);
    END IF;
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.ticket_id IS DISTINCT FROM OLD.ticket_id) THEN
        PERFORM refresh_ticket_sla(NEW.ticket_id);
    END IF;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_update_ticket_sla_agg ON public.issues;
CREATE TRIGGER trg_update_ticket_sla_agg
    AFTER INSERT OR DELETE
       OR UPDATE OF status, completed_at, completed_on, sla_end_date, category, severity, ticket_id
    ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.calculate_ticket_overall_sla();

-- A Rejected ticket is judged at rejected_at; any other status change re-judges too.
CREATE OR REPLACE FUNCTION public.recalculate_ticket_sla_on_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM refresh_ticket_sla(NEW.id);
    RETURN NEW;
END;
$function$;

-- Open work under changed SLA settings, counted from the ticket's raise time.
CREATE OR REPLACE FUNCTION public.recalculate_open_slas()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    -- Scoped by both the issue and its ticket, as before: finished work is not retouched.
    -- trg_update_ticket_sla_agg re-judges each ticket whose deadlines change.
    UPDATE issues i
    SET sla_days     = r.sla_days,
        sla_end_date = add_working_days(t.created_at AT TIME ZONE 'UTC', r.sla_days)
    FROM tickets t, sla_rules_config r
    WHERE i.ticket_id = t.id
      AND r.category  = i.category
      AND r.severity  = i.severity
      AND i.status <> 'Done'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected')
      AND is_sla_tracked(t.created_at)
      AND (i.sla_days IS DISTINCT FROM r.sla_days
           OR i.sla_end_date IS DISTINCT FROM add_working_days(t.created_at AT TIME ZONE 'UTC', r.sla_days));

    -- Acceptance deadlines, for tickets still waiting to be accepted.
    UPDATE tickets t
    SET acceptance_sla_end_date = acceptance_deadline(t.created_at AT TIME ZONE 'UTC')
    WHERE t.acceptance_sla_status = 'Pending'
      AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');
END;
$function$;

-- ---------------------------------------------------------------------------------------
-- 4. Ticket status follows its issues backwards too
-- ---------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_ticket_status_on_issue_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  ticket_status TEXT;
  total_issues INTEGER;
  done_issues INTEGER;
  rated_issues INTEGER;
  has_job_cards BOOLEAN;
BEGIN
  SELECT status INTO ticket_status FROM tickets WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);

  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE status = 'Done'),
         COUNT(*) FILTER (WHERE rating IS NOT NULL)
  INTO total_issues, done_issues, rated_issues
  FROM issues WHERE ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id);

  SELECT EXISTS(
    SELECT 1 FROM issues i
    WHERE i.ticket_id = COALESCE(NEW.ticket_id, OLD.ticket_id)
    AND i.job_card_id IS NOT NULL
  ) INTO has_job_cards;

  -- New → Accepted (on issue creation)
  IF ticket_status = 'New' AND total_issues > 0 AND TG_OP = 'INSERT' THEN
    UPDATE tickets SET status = 'Accepted' WHERE id = NEW.ticket_id;
  END IF;

  -- Accepted → Work In Progress (on job card assignment)
  IF ticket_status = 'Accepted' AND has_job_cards THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;

  -- Work In Progress → Resolved (all issues done)
  IF ticket_status = 'Work In Progress' AND total_issues > 0 AND done_issues = total_issues THEN
    UPDATE tickets SET status = 'Resolved' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;

  -- Resolved → Work In Progress (an issue added, or an unrated issue reopened; MAIN-135)
  IF ticket_status = 'Resolved' AND done_issues < total_issues THEN
    UPDATE tickets SET status = 'Work In Progress' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;

  -- Resolved → Closed (all issues have rating/feedback)
  IF ticket_status = 'Resolved' AND total_issues > 0 AND rated_issues = total_issues THEN
    UPDATE tickets SET status = 'Closed' WHERE id = COALESCE(NEW.ticket_id, OLD.ticket_id);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$function$;

-- Only the columns it reads, so refresh_ticket_sla's sla_status writes don't wake it.
DROP TRIGGER IF EXISTS trigger_update_ticket_status ON public.issues;
CREATE TRIGGER trigger_update_ticket_status
    AFTER INSERT OR UPDATE OF status, rating, job_card_id, ticket_id ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.update_ticket_status_on_issue_change();

-- Leaving Resolved for Work In Progress clears the resolved time; it is stamped afresh
-- when the ticket resolves again.
CREATE OR REPLACE FUNCTION public.stamp_ticket_resolved_closed_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.status = 'Resolved' AND OLD.status IS DISTINCT FROM 'Resolved' THEN
        NEW.resolved_at := now();
    END IF;

    IF NEW.status = 'Closed' AND OLD.status IS DISTINCT FROM 'Closed' THEN
        NEW.closed_at := now();
        -- Closed is only reached through Resolved, so this is a safety net.
        NEW.resolved_at := COALESCE(NEW.resolved_at, now());
    END IF;

    IF NEW.status::text NOT IN ('Resolved', 'Closed') AND OLD.status::text IN ('Resolved', 'Closed') THEN
        NEW.resolved_at := NULL;
        NEW.closed_at   := NULL;
    END IF;

    RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------------------
-- 5. Guards
-- ---------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.guard_ticket_reject_with_issues()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NOT NULL
       AND NEW.status = 'Rejected' AND OLD.status IS DISTINCT FROM 'Rejected'
       AND EXISTS (SELECT 1 FROM issues WHERE ticket_id = NEW.id) THEN
        RAISE EXCEPTION 'This ticket has issues, so it can''t be rejected. Delete its issues first.';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_ticket_reject_with_issues ON public.tickets;
CREATE TRIGGER trg_guard_ticket_reject_with_issues
    BEFORE UPDATE OF status ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.guard_ticket_reject_with_issues();

CREATE OR REPLACE FUNCTION public.guard_issue_on_finished_ticket()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_status text;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT status::text INTO v_status FROM tickets WHERE id = NEW.ticket_id;
    IF v_status IN ('Closed', 'Rejected') THEN
        RAISE EXCEPTION 'This ticket is %, so issues can''t be added to it.', v_status;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_issue_on_finished_ticket ON public.issues;
CREATE TRIGGER trg_guard_issue_on_finished_ticket
    BEFORE INSERT ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.guard_issue_on_finished_ticket();

CREATE OR REPLACE FUNCTION public.guard_rated_issue_reopen()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NOT NULL
       AND OLD.status = 'Done' AND NEW.status IS DISTINCT FROM 'Done'
       AND OLD.rating IS NOT NULL THEN
        RAISE EXCEPTION 'Issue % has been rated by the supervisor, so it can''t be reopened.', OLD.issue_number;
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_guard_rated_issue_reopen ON public.issues;
CREATE TRIGGER trg_guard_rated_issue_reopen
    BEFORE UPDATE OF status ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.guard_rated_issue_reopen();

-- ---------------------------------------------------------------------------------------
-- 6. Hourly refresh
-- ---------------------------------------------------------------------------------------
-- Statuses otherwise change only when something happens to the ticket, so a deadline that
-- passes quietly would leave Pending behind. Also turns the Acceptance SLA of a ticket
-- still waiting for its first issue to Violated once its deadline passes.

CREATE OR REPLACE FUNCTION public.refresh_overdue_slas()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM refresh_ticket_sla(t.id)
    FROM tickets t
    WHERE (t.overall_sla_status = 'Pending' AND t.final_sla_end_date < now())
       OR EXISTS (SELECT 1 FROM issues i
                  WHERE i.ticket_id = t.id
                    AND i.sla_status = 'Pending'
                    AND i.sla_end_date < now());

    UPDATE tickets t
    SET acceptance_sla_status = 'Violated'
    WHERE t.acceptance_sla_status = 'Pending'
      AND t.acceptance_sla_end_date < now()
      AND NOT EXISTS (SELECT 1 FROM issues i WHERE i.ticket_id = t.id);
END;
$function$;

SELECT cron.schedule('sla-hourly-refresh', '0 * * * *', $cron$SELECT public.refresh_overdue_slas()$cron$);
