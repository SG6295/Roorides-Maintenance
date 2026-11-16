-- MAIN-136: SLA settings change only through review and confirm, in numbered versions.
--
--   * Acceptance SLA Threshold, Turnaround Time (working days) and Weekly Offs are saved
--     together as a numbered version (sla_versions + sla_version_turnaround), with who,
--     why and when it starts. A version ends when the next non-cancelled one starts, so
--     the end is derived, never stored.
--   * A ticket records the version active when it was raised (its Acceptance SLA
--     Threshold and Weekly Offs); an issue the version active when it was added (its
--     Turnaround Time). Changing a setting never moves an existing deadline.
--   * Holidays are not versioned: adding or removing one recalculates every tracked
--     deadline whose window covers the date, finished or not, and re-judges the statuses.
--     Only today or later (IST). Every change is logged in sla_holiday_changes.
--   * Every write goes through apply_sla_change (super_admin only); the tables have
--     SELECT policies only. preview_sla_changes shows the effect of a draft without
--     writing anything.
--   * Today's settings become Version 1, active from the start of SLA tracking, and every
--     tracked ticket and issue is assigned to it. All their stored deadlines already match
--     those settings; the migration checks that and aborts otherwise.
--
-- This replaces the MAIN-45 recalculation triggers on sla_rules_config, holidays and
-- system_settings: only holidays may move an existing deadline now, and they do it inside
-- apply_sla_change. sla_rules_config and the two system_settings keys are dropped, so
-- nothing is left that looks like a setting but isn't read (the MAIN-47 lesson).
--
-- Service-role writes (auth.uid() IS NULL) keep a version and deadlines they supply, so
-- the prod->staging seed copies prod's values instead of recomputing them.

-- ---------------------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------------------

CREATE TABLE public.sla_versions (
    id                uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    -- Assigned by apply_sla_change (max + 1, under a lock); the seed copies prod's.
    version_number    integer NOT NULL UNIQUE,
    acceptance_days   integer DEFAULT 2 NOT NULL,
    weekly_offs       integer[] DEFAULT '{0,6}'::integer[] NOT NULL,
    starts_at         timestamp with time zone DEFAULT now() NOT NULL,
    reason            text DEFAULT ''::text NOT NULL,
    created_by        uuid,
    created_by_name   text,
    created_at        timestamp with time zone DEFAULT now() NOT NULL,
    cancelled_at      timestamp with time zone,
    cancelled_by      uuid,
    cancelled_by_name text,
    cancel_reason     text,
    CONSTRAINT sla_versions_acceptance_days_check CHECK (acceptance_days BETWEEN 1 AND 365),
    CONSTRAINT sla_versions_weekly_offs_check CHECK (
        weekly_offs <@ '{0,1,2,3,4,5,6}'::integer[] AND cardinality(weekly_offs) < 7),
    CONSTRAINT sla_versions_cancel_check CHECK ((cancelled_at IS NULL) = (cancel_reason IS NULL))
);

COMMENT ON TABLE public.sla_versions IS
    'Numbered SLA settings (MAIN-136): Acceptance SLA Threshold, Weekly Offs, and Turnaround Time in sla_version_turnaround. A version is active from starts_at until the next non-cancelled version starts. Written only by apply_sla_change. created_by/cancelled_by are not foreign keys and the names are snapshots, so history survives a user being deleted or renamed.';
COMMENT ON COLUMN public.sla_versions.weekly_offs IS 'Days of the week that are not working days, 0 = Sunday ... 6 = Saturday.';

CREATE TABLE public.sla_version_turnaround (
    version_id uuid NOT NULL REFERENCES public.sla_versions(id),
    category   public.issue_category NOT NULL,
    severity   public.issue_severity NOT NULL,
    sla_days   integer DEFAULT 3 NOT NULL,
    PRIMARY KEY (version_id, category, severity),
    CONSTRAINT sla_version_turnaround_days_check CHECK (sla_days BETWEEN 1 AND 365)
);

COMMENT ON TABLE public.sla_version_turnaround IS
    'Turnaround Time (working days) per category and severity, one row per pair for every version (MAIN-136). Replaces sla_rules_config.';

CREATE TABLE public.sla_holiday_changes (
    id                uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    holiday_date      date NOT NULL,
    description       text,
    action            text DEFAULT 'add'::text NOT NULL,
    reason            text DEFAULT ''::text NOT NULL,
    performed_by      uuid,
    performed_by_name text,
    performed_at      timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT sla_holiday_changes_action_check CHECK (action IN ('add', 'remove'))
);

COMMENT ON TABLE public.sla_holiday_changes IS
    'Every holiday added or removed, with the reason (MAIN-136). Written only by apply_sla_change; survives the holiday row being deleted.';

ALTER TABLE public.tickets ADD COLUMN sla_version_id uuid REFERENCES public.sla_versions(id);
ALTER TABLE public.issues  ADD COLUMN sla_version_id uuid REFERENCES public.sla_versions(id);

COMMENT ON COLUMN public.tickets.sla_version_id IS
    'SLA version active when the ticket was raised: its Acceptance SLA Threshold and Weekly Offs. NULL for tickets raised before SLA tracking (MAIN-136).';
COMMENT ON COLUMN public.issues.sla_version_id IS
    'SLA version active when the issue was added: its Turnaround Time. Working days follow the ticket''s version. NULL on tickets raised before SLA tracking (MAIN-136).';

CREATE INDEX tickets_sla_version_id_idx ON public.tickets (sla_version_id);
CREATE INDEX issues_sla_version_id_idx  ON public.issues (sla_version_id);

ALTER TABLE public.sla_versions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sla_version_turnaround ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sla_holiday_changes    ENABLE ROW LEVEL SECURITY;

-- Everyone who can see a ticket can see which version it was judged under.
CREATE POLICY "Everyone can read SLA versions" ON public.sla_versions FOR SELECT USING (true);
CREATE POLICY "Everyone can read SLA turnaround" ON public.sla_version_turnaround FOR SELECT USING (true);
CREATE POLICY "Execs read holiday changes" ON public.sla_holiday_changes FOR SELECT USING (public.is_maintenance_exec());

-- Holidays are written only through apply_sla_change.
DROP POLICY "Super admins can insert holidays" ON public.holidays;
DROP POLICY "Super admins can update holidays" ON public.holidays;
DROP POLICY "Super admins can delete holidays" ON public.holidays;

-- ---------------------------------------------------------------------------------------
-- 2. Working days and versions
-- ---------------------------------------------------------------------------------------

-- Pure: every setting is an argument, so the preview can pass candidate settings and get
-- exactly what the live path would compute. The time of day is kept; days are IST dates.
CREATE FUNCTION public.add_working_days(start_ts timestamp with time zone, n_days integer,
                                        p_weekly_offs integer[], p_holidays date[])
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_date     date;
    v_time     time;
    days_added int := 0;
BEGIN
    IF start_ts IS NULL OR n_days IS NULL OR p_weekly_offs IS NULL THEN
        RETURN NULL;
    END IF;
    IF cardinality(p_weekly_offs) >= 7 THEN
        RAISE EXCEPTION 'add_working_days: every day of the week is a weekly off.';
    END IF;

    v_date := (start_ts AT TIME ZONE 'Asia/Kolkata')::date;
    v_time := (start_ts AT TIME ZONE 'Asia/Kolkata')::time;

    WHILE days_added < n_days LOOP
        v_date := v_date + 1;
        IF EXTRACT(DOW FROM v_date)::int = ANY (p_weekly_offs)
           OR v_date = ANY (COALESCE(p_holidays, '{}')) THEN
            CONTINUE;
        END IF;
        days_added := days_added + 1;
    END LOOP;

    RETURN (v_date + v_time) AT TIME ZONE 'Asia/Kolkata';
END;
$function$;

CREATE FUNCTION public.sla_holiday_dates()
 RETURNS date[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT COALESCE(array_agg(date ORDER BY date), '{}') FROM holidays;
$function$;

-- The version active at a moment: the latest non-cancelled one started by then.
CREATE FUNCTION public.sla_version_at(p_at timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT id FROM sla_versions
    WHERE cancelled_at IS NULL AND starts_at <= p_at
    ORDER BY starts_at DESC
    LIMIT 1;
$function$;

-- ---------------------------------------------------------------------------------------
-- 3. Version 1 and the backfill
-- ---------------------------------------------------------------------------------------

-- 14 Aug 2026 00:00 IST, the start of SLA tracking (is_sla_tracked).
INSERT INTO public.sla_versions (version_number, acceptance_days, weekly_offs, starts_at, reason, created_at)
SELECT 1,
       COALESCE((SELECT value::int FROM public.system_settings WHERE key = 'acceptance_sla_days'), 2),
       COALESCE((SELECT ARRAY(SELECT jsonb_array_elements_text(value::jsonb)::int ORDER BY 1)
                 FROM public.system_settings WHERE key = 'sla_weekly_offs'), '{0,6}'),
       timestamptz '2026-08-14 00:00:00+05:30',
       'Settings in force when SLA tracking began. Recorded when SLA versions were introduced (MAIN-136).',
       now();

INSERT INTO public.sla_version_turnaround (version_id, category, severity, sla_days)
SELECT v.id, r.category, r.severity, r.sla_days
FROM public.sla_rules_config r, public.sla_versions v
WHERE v.version_number = 1;

UPDATE public.tickets
SET sla_version_id = (SELECT id FROM public.sla_versions WHERE version_number = 1)
WHERE public.is_sla_tracked(created_at);

UPDATE public.issues i
SET sla_version_id = t.sla_version_id
FROM public.tickets t
WHERE t.id = i.ticket_id
  AND t.sla_version_id IS NOT NULL;

-- Version 1 must reproduce every stored deadline, or assigning it would be a lie.
DO $check$
DECLARE
    v_pairs     int;
    v_issues    int;
    v_tickets   int;
BEGIN
    SELECT count(*) INTO v_pairs
    FROM public.sla_version_turnaround t JOIN public.sla_versions v ON v.id = t.version_id
    WHERE v.version_number = 1;
    IF v_pairs <> (SELECT count(*) FROM unnest(enum_range(NULL::public.issue_category)) c,
                                         unnest(enum_range(NULL::public.issue_severity)) s) THEN
        RAISE EXCEPTION 'MAIN-136: Version 1 has % Turnaround Time rows, expected one per category and severity.', v_pairs;
    END IF;

    SELECT count(*) INTO v_issues
    FROM public.issues i
    JOIN public.tickets t ON t.id = i.ticket_id
    JOIN public.sla_versions tv ON tv.id = t.sla_version_id
    JOIN public.sla_version_turnaround r
      ON r.version_id = i.sla_version_id AND r.category = i.category AND r.severity = i.severity
    WHERE i.sla_days IS DISTINCT FROM r.sla_days
       OR i.sla_end_date IS DISTINCT FROM public.add_working_days(
              t.created_at AT TIME ZONE 'UTC', r.sla_days, tv.weekly_offs, public.sla_holiday_dates());

    SELECT count(*) INTO v_tickets
    FROM public.tickets t
    JOIN public.sla_versions tv ON tv.id = t.sla_version_id
    WHERE t.acceptance_sla_end_date IS DISTINCT FROM public.add_working_days(
              t.created_at AT TIME ZONE 'UTC', tv.acceptance_days, tv.weekly_offs, public.sla_holiday_dates());

    IF v_issues > 0 OR v_tickets > 0 THEN
        RAISE EXCEPTION 'MAIN-136: Version 1 does not reproduce % issue and % acceptance deadlines.', v_issues, v_tickets;
    END IF;

    IF EXISTS (SELECT 1 FROM public.issues i JOIN public.tickets t ON t.id = i.ticket_id
               WHERE public.is_sla_tracked(t.created_at) AND i.sla_version_id IS NULL) THEN
        RAISE EXCEPTION 'MAIN-136: a tracked issue was left without a version.';
    END IF;
END;
$check$;

-- ---------------------------------------------------------------------------------------
-- 4. Deadlines come from the recorded version
-- ---------------------------------------------------------------------------------------

-- Ticket: stamps its version and its acceptance deadline. A service-role insert (the seed)
-- keeps what it supplies.
CREATE OR REPLACE FUNCTION public.trg_stamp_acceptance_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_version sla_versions%ROWTYPE;
BEGIN
    IF auth.uid() IS NOT NULL OR NEW.sla_version_id IS NULL THEN
        NEW.sla_version_id := CASE WHEN is_sla_tracked(NEW.created_at)
                                   THEN sla_version_at(NEW.created_at AT TIME ZONE 'UTC') END;
    END IF;

    IF auth.uid() IS NOT NULL OR NEW.acceptance_sla_end_date IS NULL THEN
        SELECT * INTO v_version FROM sla_versions WHERE id = NEW.sla_version_id;
        NEW.acceptance_sla_end_date := CASE WHEN FOUND THEN
            add_working_days(NEW.created_at AT TIME ZONE 'UTC', v_version.acceptance_days,
                             v_version.weekly_offs, sla_holiday_dates()) END;
    END IF;

    RETURN NEW;
END;
$function$;

-- Issue: stamps its version on insert. The deadline is the ticket's raise time + the
-- issue version's Turnaround Time, counted with the ticket version's Weekly Offs; fixed on
-- insert and recomputed with the same versions when the category or severity is corrected.
CREATE OR REPLACE FUNCTION public.calculate_issue_sla_dynamic()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_raised       timestamp;
    v_ticket_offs  integer[];
    v_days         integer;
BEGIN
    IF TG_OP = 'UPDATE'
       AND NEW.category IS NOT DISTINCT FROM OLD.category
       AND NEW.severity IS NOT DISTINCT FROM OLD.severity THEN
        RETURN NEW;
    END IF;

    SELECT t.created_at, v.weekly_offs INTO v_raised, v_ticket_offs
    FROM tickets t LEFT JOIN sla_versions v ON v.id = t.sla_version_id
    WHERE t.id = NEW.ticket_id;

    IF TG_OP = 'INSERT' THEN
        IF auth.uid() IS NOT NULL OR NEW.sla_version_id IS NULL THEN
            NEW.sla_version_id := CASE WHEN is_sla_tracked(v_raised)
                                       THEN sla_version_at(NEW.created_at AT TIME ZONE 'UTC') END;
        END IF;
        IF auth.uid() IS NULL AND NEW.sla_end_date IS NOT NULL THEN
            RETURN NEW;
        END IF;
    END IF;

    SELECT sla_days INTO v_days
    FROM sla_version_turnaround
    WHERE version_id = NEW.sla_version_id AND category = NEW.category AND severity = NEW.severity;

    -- A pre-tracking ticket's issues have no version and no deadline (MAIN-45).
    NEW.sla_days := COALESCE(v_days, NEW.sla_days);
    NEW.sla_end_date := add_working_days(v_raised AT TIME ZONE 'UTC', v_days, v_ticket_offs, sla_holiday_dates());

    RETURN NEW;
END;
$function$;

-- A recorded version never changes, except by the service role.
CREATE FUNCTION public.guard_sla_version_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NOT NULL AND NEW.sla_version_id IS DISTINCT FROM OLD.sla_version_id THEN
        RAISE EXCEPTION 'The SLA version a ticket or issue was recorded under can''t be changed.';
    END IF;
    RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_guard_ticket_sla_version BEFORE UPDATE OF sla_version_id ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.guard_sla_version_change();
CREATE TRIGGER trg_guard_issue_sla_version BEFORE UPDATE OF sla_version_id ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.guard_sla_version_change();

-- Acceptance is judged against the stored deadline only. No deadline (a pre-tracking
-- ticket) is NA rather than Violated.
CREATE OR REPLACE FUNCTION public.evaluate_acceptance_sla(p_ticket_id uuid, p_first_issue_created timestamp with time zone)
 RETURNS sla_status_enum
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_deadline timestamptz;
BEGIN
    SELECT acceptance_sla_end_date INTO v_deadline FROM tickets WHERE id = p_ticket_id;
    RETURN sla_verdict(v_deadline, p_first_issue_created);
END;
$function$;

CREATE OR REPLACE FUNCTION public.stamp_rejected_at_and_evaluate_acceptance_sla()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_first_issue timestamptz;
BEGIN
  IF NEW.status = 'Rejected' AND (OLD.status IS DISTINCT FROM 'Rejected') THEN
    NEW.rejected_at := NOW();

    -- Only if not already judged by the first-issue trigger
    IF NEW.acceptance_sla_status = 'Pending' THEN
      SELECT MIN(created_at) AT TIME ZONE 'UTC' INTO v_first_issue
        FROM issues WHERE ticket_id = NEW.id;

      -- Against the first issue if there is one, otherwise the rejection
      NEW.acceptance_sla_status := sla_verdict(NEW.acceptance_sla_end_date,
                                               COALESCE(v_first_issue, NEW.rejected_at));
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------------------------------
-- 5. The MAIN-45 recalculation triggers go; the settings they watched go with them
-- ---------------------------------------------------------------------------------------

DROP TRIGGER trg_holidays_recalc ON public.holidays;
DROP TRIGGER trg_system_settings_sla_recalc ON public.system_settings;
DROP TABLE public.sla_rules_config;   -- its trigger and policies go with it
DROP FUNCTION public.trg_recalculate_open_slas();
DROP FUNCTION public.recalculate_open_slas();
DROP FUNCTION public.acceptance_deadline(timestamp with time zone);
DROP FUNCTION public.add_working_days(timestamp with time zone, integer);

DELETE FROM public.system_settings WHERE key IN ('acceptance_sla_days', 'sla_weekly_offs');

-- ---------------------------------------------------------------------------------------
-- 6. What a change would do
-- ---------------------------------------------------------------------------------------

-- One row per tracked ticket with what its verdicts read. finished_at is when the
-- Turnaround verdict became final (rejection, or the latest activity complete time once
-- every issue is Done); accepted_at is the acceptance event (first issue, or rejection).
-- Mirrors refresh_ticket_sla and the acceptance triggers.
CREATE FUNCTION public.sla_ticket_facts()
 RETURNS TABLE (ticket_id uuid, raised_at timestamptz, ticket_status text, sla_version_id uuid,
                issue_count int, finished_at timestamptz, accepted_at timestamptz,
                final_sla_end_date timestamptz, overall_sla_status sla_status_enum,
                acceptance_sla_end_date timestamptz, acceptance_sla_status sla_status_enum)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    SELECT t.id,
           t.created_at AT TIME ZONE 'UTC',
           t.status::text,
           t.sla_version_id,
           COALESCE(i.n, 0)::int,
           CASE WHEN t.status = 'Rejected' THEN t.rejected_at
                WHEN i.all_done THEN i.last_done END,
           COALESCE(i.first_added, CASE WHEN t.status = 'Rejected' THEN t.rejected_at END),
           t.final_sla_end_date, t.overall_sla_status,
           t.acceptance_sla_end_date, t.acceptance_sla_status
    FROM tickets t
    LEFT JOIN (
        SELECT ticket_id, count(*) n, bool_and(status = 'Done') all_done,
               max(completed_at) last_done, min(created_at) AT TIME ZONE 'UTC' first_added
        FROM issues GROUP BY ticket_id
    ) i ON i.ticket_id = t.id
    WHERE t.sla_version_id IS NOT NULL;
$function$;

-- Every tracked deadline that would move under the given holiday list, with its status
-- before and after. Only deadlines on or after today (IST) can cover a date that may be
-- changed, so older ones are not recomputed. kind: 'issue', 'ticket' (Turnaround) or
-- 'acceptance'. Used by preview_sla_changes to count and by apply_sla_change to write.
CREATE FUNCTION public.sla_holiday_effects(p_holidays date[])
 RETURNS TABLE (kind text, ticket_id uuid, issue_id uuid,
                old_deadline timestamptz, new_deadline timestamptz,
                old_status sla_status_enum, new_status sla_status_enum)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    WITH today AS (
        SELECT ((now() AT TIME ZONE 'Asia/Kolkata')::date)::timestamp AT TIME ZONE 'Asia/Kolkata' AS starts
    ),
    f AS (SELECT * FROM sla_ticket_facts()),
    iss AS (
        SELECT i.id, i.ticket_id, i.sla_end_date AS old_deadline, i.sla_status AS old_status,
               add_working_days(f.raised_at, i.sla_days, v.weekly_offs, p_holidays) AS new_deadline,
               CASE WHEN f.ticket_status = 'Rejected' THEN f.finished_at
                    WHEN i.status = 'Done' THEN i.completed_at END AS finish
        FROM issues i
        JOIN f ON f.ticket_id = i.ticket_id
        JOIN sla_versions v ON v.id = f.sla_version_id
        WHERE i.sla_end_date >= (SELECT starts FROM today)
    ),
    moved_issues AS (
        SELECT *, sla_verdict(new_deadline, finish) AS new_status
        FROM iss WHERE new_deadline IS DISTINCT FROM old_deadline
    ),
    moved_tickets AS (
        SELECT f.*, d.new_deadline
        FROM f
        JOIN LATERAL (
            SELECT max(COALESCE(m.new_deadline, i.sla_end_date)) AS new_deadline
            FROM issues i LEFT JOIN moved_issues m ON m.id = i.id
            WHERE i.ticket_id = f.ticket_id
        ) d ON true
        WHERE f.ticket_id IN (SELECT ticket_id FROM moved_issues)
    ),
    acc AS (
        SELECT f.*, add_working_days(f.raised_at, v.acceptance_days, v.weekly_offs, p_holidays) AS new_deadline
        FROM f JOIN sla_versions v ON v.id = f.sla_version_id
        WHERE f.acceptance_sla_end_date >= (SELECT starts FROM today)
    )
    SELECT 'issue', ticket_id, id, old_deadline, new_deadline, old_status, new_status
    FROM moved_issues
    UNION ALL
    SELECT 'ticket', ticket_id, NULL, final_sla_end_date, new_deadline, overall_sla_status,
           sla_verdict(new_deadline, finished_at)
    FROM moved_tickets
    WHERE new_deadline IS DISTINCT FROM final_sla_end_date
    UNION ALL
    SELECT 'acceptance', ticket_id, NULL, acceptance_sla_end_date, new_deadline, acceptance_sla_status,
           sla_verdict(new_deadline, accepted_at)
    FROM acc
    WHERE new_deadline IS DISTINCT FROM acceptance_sla_end_date;
$function$;

-- On-time % for the last 30 and 90 days, as it is and as it would have been under candidate
-- settings. Per ticket, Turnaround and Acceptance separately; Adhered / (Adhered + Violated),
-- counting a ticket in a window when its verdict was reached in it: finished, rejected or
-- accepted then, or turned Violated by its deadline passing then. Pending is left out.
-- Nothing is written.
CREATE FUNCTION public.sla_on_time_whatif(p_acceptance_days integer, p_weekly_offs integer[],
                                          p_turnaround jsonb, p_holidays date[])
 RETURNS TABLE (window_days int, sla text, as_is_adhered int, as_is_judged int,
                would_be_adhered int, would_be_judged int)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    WITH cand AS (
        SELECT (e->>'category')::issue_category AS category, (e->>'severity')::issue_severity AS severity,
               (e->>'sla_days')::int AS sla_days
        FROM jsonb_array_elements(p_turnaround) e
    ),
    f AS (SELECT * FROM sla_ticket_facts()),
    tk AS (
        SELECT f.*,
               (SELECT max(add_working_days(f.raised_at, c.sla_days, p_weekly_offs, p_holidays))
                FROM issues i JOIN cand c ON c.category = i.category AND c.severity = i.severity
                WHERE i.ticket_id = f.ticket_id) AS cand_deadline,
               add_working_days(f.raised_at, p_acceptance_days, p_weekly_offs, p_holidays) AS cand_acc_deadline
        FROM f
    ),
    verdicts AS (
        -- Turnaround: tickets with issues only (no issues is NA).
        SELECT 'Turnaround' AS sla,
               overall_sla_status AS as_is,
               COALESCE(finished_at, final_sla_end_date) AS as_is_at,
               sla_verdict(cand_deadline, finished_at) AS would_be,
               COALESCE(finished_at, cand_deadline) AS would_be_at
        FROM tk WHERE issue_count > 0
        UNION ALL
        SELECT 'Acceptance',
               acceptance_sla_status,
               COALESCE(accepted_at, acceptance_sla_end_date),
               sla_verdict(cand_acc_deadline, accepted_at),
               COALESCE(accepted_at, cand_acc_deadline)
        FROM tk
    )
    SELECT w.days, v.sla,
           count(*) FILTER (WHERE v.as_is = 'Adhered' AND v.as_is_at >= now() - make_interval(days => w.days))::int,
           count(*) FILTER (WHERE v.as_is IN ('Adhered', 'Violated') AND v.as_is_at >= now() - make_interval(days => w.days))::int,
           count(*) FILTER (WHERE v.would_be = 'Adhered' AND v.would_be_at >= now() - make_interval(days => w.days))::int,
           count(*) FILTER (WHERE v.would_be IN ('Adhered', 'Violated') AND v.would_be_at >= now() - make_interval(days => w.days))::int
    FROM verdicts v, (VALUES (30), (90)) w(days)
    GROUP BY w.days, v.sla
    ORDER BY v.sla DESC, w.days;
$function$;

-- ---------------------------------------------------------------------------------------
-- 7. Review and save
-- ---------------------------------------------------------------------------------------
--
-- p_change:
--   { "base_version_id": uuid,            -- the latest version when the draft was opened
--     "reason": text,                     -- one per confirm, required
--     "starts_at": timestamptz | null,    -- null = now
--     "version": { "acceptance_days": int, "weekly_offs": [int],
--                  "turnaround": [{ "category", "severity", "sla_days" }] } | null,
--     "holidays_add": [{ "date", "description" }],
--     "holidays_remove": [date] }
-- apply_sla_change also takes { "action": "cancel_version", "version_id", "reason" }.

CREATE FUNCTION public.sla_change_error(p_code text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    RAISE EXCEPTION '%', json_build_object('error_code', p_code, 'error_message', p_message)::text;
END;
$function$;

-- Checks a draft and returns the candidate holiday list. Shared by preview and save.
CREATE FUNCTION public.sla_validate_change(p_change jsonb)
 RETURNS date[]
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
    v_today   date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_version jsonb := NULLIF(p_change->'version', 'null'::jsonb);
    v_add     date[];
    v_remove  date[];
    v_latest  sla_versions%ROWTYPE;
    v_pairs   int;
    -- One Turnaround Time per category and severity.
    v_expected int := cardinality(enum_range(NULL::issue_category)) * cardinality(enum_range(NULL::issue_severity));
BEGIN
    SELECT COALESCE(array_agg((e->>'date')::date), '{}') INTO v_add
    FROM jsonb_array_elements(COALESCE(p_change->'holidays_add', '[]')) e;
    SELECT COALESCE(array_agg(e::date), '{}') INTO v_remove
    FROM jsonb_array_elements_text(COALESCE(p_change->'holidays_remove', '[]')) e;

    IF v_version IS NULL AND cardinality(v_add) = 0 AND cardinality(v_remove) = 0 THEN
        PERFORM sla_change_error('NOTHING_TO_SAVE', 'There are no changes to save.');
    END IF;

    SELECT * INTO v_latest FROM sla_versions WHERE cancelled_at IS NULL ORDER BY version_number DESC LIMIT 1;
    IF (p_change->>'base_version_id')::uuid IS DISTINCT FROM v_latest.id THEN
        PERFORM sla_change_error('STALE_DRAFT',
            'The SLA settings were changed by someone else since you opened this page. Reload and make your changes again.');
    END IF;

    IF v_version IS NOT NULL THEN
        IF v_latest.starts_at > now() THEN
            PERFORM sla_change_error('VERSION_SCHEDULED', format(
                'Version %s is scheduled to start on %s. Cancel it before saving a new version.',
                v_latest.version_number, to_char(v_latest.starts_at AT TIME ZONE 'Asia/Kolkata', 'DD Mon YYYY HH24:MI')));
        END IF;
        IF (p_change->>'starts_at') IS NOT NULL AND (p_change->>'starts_at')::timestamptz <= now() THEN
            PERFORM sla_change_error('START_IN_PAST', 'A scheduled start must be in the future.');
        END IF;
        IF COALESCE((v_version->>'acceptance_days')::int, 0) NOT BETWEEN 1 AND 365 THEN
            PERFORM sla_change_error('INVALID_ACCEPTANCE', 'Acceptance SLA Threshold must be between 1 and 365 working days.');
        END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(COALESCE(v_version->'weekly_offs', '[]')) d
                   WHERE d::int NOT BETWEEN 0 AND 6)
           OR jsonb_array_length(COALESCE(v_version->'weekly_offs', '[]')) >= 7 THEN
            PERFORM sla_change_error('INVALID_WEEKLY_OFFS', 'Weekly Offs must leave at least one working day.');
        END IF;
        SELECT count(DISTINCT (e->>'category', e->>'severity')) INTO v_pairs
        FROM jsonb_array_elements(COALESCE(v_version->'turnaround', '[]')) e
        WHERE (e->>'sla_days')::int BETWEEN 1 AND 365;
        IF v_pairs <> v_expected OR jsonb_array_length(v_version->'turnaround') <> v_expected THEN
            PERFORM sla_change_error('INVALID_TURNAROUND',
                'Every category and severity needs a Turnaround Time between 1 and 365 working days.');
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM unnest(v_add || v_remove) d WHERE d < v_today) THEN
        PERFORM sla_change_error('HOLIDAY_IN_PAST', 'Holidays before today can''t be added or removed.');
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_add) d WHERE d = ANY (sla_holiday_dates()))
       OR cardinality(v_add) <> (SELECT count(DISTINCT d) FROM unnest(v_add) d) THEN
        PERFORM sla_change_error('HOLIDAY_EXISTS', 'That date is already a holiday.');
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(v_remove) d WHERE NOT d = ANY (sla_holiday_dates())) THEN
        PERFORM sla_change_error('HOLIDAY_NOT_FOUND', 'That holiday has already been removed.');
    END IF;

    RETURN ARRAY(SELECT d FROM unnest(sla_holiday_dates()) d WHERE NOT d = ANY (v_remove)
                 UNION SELECT unnest(v_add) ORDER BY 1);
END;
$function$;

-- Review changes: what the draft would do, without writing anything. The reason is not
-- needed yet.
CREATE FUNCTION public.preview_sla_changes(p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_holidays date[];
    v_version  jsonb := NULLIF(p_change->'version', 'null'::jsonb);
    v_offs     integer[];
    v_result   jsonb := '{}';
BEGIN
    IF NOT is_super_admin() THEN
        PERFORM sla_change_error('UNAUTHORIZED', 'Only super admins can change SLA settings.');
    END IF;

    v_holidays := sla_validate_change(p_change);

    IF v_version IS NOT NULL THEN
        v_offs := ARRAY(SELECT jsonb_array_elements_text(v_version->'weekly_offs')::int);
        v_result := v_result || jsonb_build_object('on_time', (
            SELECT jsonb_agg(to_jsonb(w))
            FROM sla_on_time_whatif((v_version->>'acceptance_days')::int, v_offs,
                                    v_version->'turnaround', sla_holiday_dates()) w));
    END IF;

    IF v_holidays IS DISTINCT FROM sla_holiday_dates() THEN
        v_result := v_result || jsonb_build_object('holidays', (
            SELECT jsonb_build_object(
                'tickets_moved',  count(DISTINCT e.ticket_id),
                'issues_moved',   count(*) FILTER (WHERE e.kind = 'issue'),
                'status_changes', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object('kind', kind, 'from', old_status, 'to', new_status, 'count', n)
                                     ORDER BY kind, old_status, new_status)
                    FROM (SELECT kind, old_status, new_status, count(*) n
                          FROM sla_holiday_effects(v_holidays)
                          WHERE old_status IS DISTINCT FROM new_status
                          GROUP BY 1, 2, 3) s), '[]'))
            FROM sla_holiday_effects(v_holidays) e));
    END IF;

    RETURN v_result;
END;
$function$;

-- The only way SLA settings change. Saves a version and/or holiday changes under one
-- reason, or cancels a scheduled version.
CREATE FUNCTION public.apply_sla_change(p_change jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_uid      uuid := auth.uid();
    v_name     text;
    v_reason   text := NULLIF(btrim(p_change->>'reason'), '');
    v_version  jsonb := NULLIF(p_change->'version', 'null'::jsonb);
    v_holidays date[];
    v_target   sla_versions%ROWTYPE;
    v_new_id   uuid;
    v_number   int;
    v_moved    int := 0;
BEGIN
    IF NOT is_super_admin() THEN
        PERFORM sla_change_error('UNAUTHORIZED', 'Only super admins can change SLA settings.');
    END IF;
    IF v_reason IS NULL THEN
        PERFORM sla_change_error('REASON_REQUIRED', 'Give a reason for the change.');
    END IF;
    SELECT name INTO v_name FROM users WHERE id = v_uid;

    -- One change at a time.
    LOCK TABLE sla_versions, holidays IN SHARE ROW EXCLUSIVE MODE;

    IF p_change->>'action' = 'cancel_version' THEN
        SELECT * INTO v_target FROM sla_versions WHERE id = (p_change->>'version_id')::uuid;
        IF NOT FOUND OR v_target.cancelled_at IS NOT NULL THEN
            PERFORM sla_change_error('VERSION_NOT_SCHEDULED', 'This version is already cancelled.');
        END IF;
        IF v_target.starts_at <= now() THEN
            PERFORM sla_change_error('VERSION_STARTED', format(
                'Version %s has already started, so it can''t be cancelled.', v_target.version_number));
        END IF;
        UPDATE sla_versions
        SET cancelled_at = now(), cancelled_by = v_uid, cancelled_by_name = v_name, cancel_reason = v_reason
        WHERE id = v_target.id;
        RETURN jsonb_build_object('cancelled_version', v_target.version_number);
    END IF;

    v_holidays := sla_validate_change(p_change);

    IF v_version IS NOT NULL THEN
        SELECT COALESCE(max(version_number), 0) + 1 INTO v_number FROM sla_versions;
        INSERT INTO sla_versions (version_number, acceptance_days, weekly_offs, starts_at, reason,
                                  created_by, created_by_name)
        VALUES (v_number,
                (v_version->>'acceptance_days')::int,
                ARRAY(SELECT DISTINCT d::int FROM jsonb_array_elements_text(v_version->'weekly_offs') d ORDER BY 1),
                COALESCE((p_change->>'starts_at')::timestamptz, now()),
                v_reason, v_uid, v_name)
        RETURNING id INTO v_new_id;

        INSERT INTO sla_version_turnaround (version_id, category, severity, sla_days)
        SELECT v_new_id, (e->>'category')::issue_category, (e->>'severity')::issue_severity, (e->>'sla_days')::int
        FROM jsonb_array_elements(v_version->'turnaround') e;
    END IF;

    IF v_holidays IS DISTINCT FROM sla_holiday_dates() THEN
        INSERT INTO sla_holiday_changes (holiday_date, description, action, reason, performed_by, performed_by_name)
        SELECT h.date, h.description, 'remove', v_reason, v_uid, v_name
        FROM holidays h WHERE NOT h.date = ANY (v_holidays);
        DELETE FROM holidays WHERE NOT date = ANY (v_holidays);

        INSERT INTO holidays (date, description)
        SELECT (e->>'date')::date, NULLIF(btrim(e->>'description'), '')
        FROM jsonb_array_elements(COALESCE(p_change->'holidays_add', '[]')) e;
        INSERT INTO sla_holiday_changes (holiday_date, description, action, reason, performed_by, performed_by_name)
        SELECT (e->>'date')::date, NULLIF(btrim(e->>'description'), ''), 'add', v_reason, v_uid, v_name
        FROM jsonb_array_elements(COALESCE(p_change->'holidays_add', '[]')) e;

        -- Move the deadlines. trg_update_ticket_sla_agg re-judges each ticket whose issue
        -- deadlines move; acceptance has no such trigger, so its status is written here.
        CREATE TEMP TABLE _sla_effects ON COMMIT DROP AS
            SELECT * FROM sla_holiday_effects(sla_holiday_dates());

        UPDATE issues i SET sla_end_date = e.new_deadline
        FROM _sla_effects e WHERE e.kind = 'issue' AND e.issue_id = i.id;

        UPDATE tickets t SET acceptance_sla_end_date = e.new_deadline, acceptance_sla_status = e.new_status
        FROM _sla_effects e WHERE e.kind = 'acceptance' AND e.ticket_id = t.id;

        SELECT count(DISTINCT ticket_id) INTO v_moved FROM _sla_effects;
        DROP TABLE _sla_effects;
    END IF;

    RETURN jsonb_build_object('version_number', v_number, 'tickets_moved', v_moved);
END;
$function$;
