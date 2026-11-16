-- MAIN-140: issue categories and holiday access.
--
-- 1. AdBlue is renamed Emission. RENAME VALUE relabels every existing issue and SLA
--    Turnaround row too (1,130 issues in prod), so history reads as one category.
--    audit_logs rows that recorded "AdBlue" as text are left as written.
--
-- 2. Other is retired, not dropped: 487 issues in prod use it (13 open), so it stays in
--    the enum. No issue can be added as Other or moved to it (service-role writes pass,
--    for the prod→staging seed); an existing Other issue keeps its category and its
--    deadline. A new SLA version carries no Turnaround Time for Other.
--
-- 3. Maintenance execs may add and remove holidays. apply_sla_change and
--    preview_sla_changes let them through when the change touches holidays only; a new
--    version and cancelling one stay super_admin-only.

ALTER TYPE public.issue_category RENAME VALUE 'AdBlue' TO 'Emission';

CREATE OR REPLACE FUNCTION public.is_issue_category_retired(p_category public.issue_category) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
    SELECT p_category = 'Other';
$$;

CREATE OR REPLACE FUNCTION public.guard_issue_category() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;
    IF is_issue_category_retired(NEW.category)
       AND (TG_OP = 'INSERT' OR NEW.category IS DISTINCT FROM OLD.category) THEN
        RAISE EXCEPTION '% is no longer an issue category. Pick another one.', NEW.category;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_issue_category ON public.issues;
CREATE TRIGGER trg_guard_issue_category
    BEFORE INSERT OR UPDATE OF category ON public.issues
    FOR EACH ROW EXECUTE FUNCTION public.guard_issue_category();

-- One Turnaround Time per *current* category and severity.
CREATE OR REPLACE FUNCTION public.sla_validate_change(p_change jsonb) RETURNS date[]
    LANGUAGE plpgsql STABLE
    SET search_path TO 'public'
    AS $$
DECLARE
    v_today   date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
    v_version jsonb := NULLIF(p_change->'version', 'null'::jsonb);
    v_add     date[];
    v_remove  date[];
    v_latest  sla_versions%ROWTYPE;
    v_pairs   int;
    -- One Turnaround Time per current category and severity.
    v_expected int := (SELECT count(*) FROM unnest(enum_range(NULL::issue_category)) c
                       WHERE NOT is_issue_category_retired(c))
                      * cardinality(enum_range(NULL::issue_severity));
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
        WHERE (e->>'sla_days')::int BETWEEN 1 AND 365
          AND NOT is_issue_category_retired((e->>'category')::issue_category);
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
$$;

-- Who may make this change: super admins anything, maintenance execs holidays only.
CREATE OR REPLACE FUNCTION public.sla_assert_change_allowed(p_change jsonb) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    IF is_super_admin() THEN
        RETURN;
    END IF;
    IF is_maintenance_exec()
       AND p_change->>'action' IS DISTINCT FROM 'cancel_version'
       AND NULLIF(p_change->'version', 'null'::jsonb) IS NULL THEN
        RETURN;
    END IF;
    PERFORM sla_change_error('UNAUTHORIZED', 'Only super admins can change SLA settings other than holidays.');
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_sla_change(p_change jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
    PERFORM sla_assert_change_allowed(p_change);
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
$$;

CREATE OR REPLACE FUNCTION public.preview_sla_changes(p_change jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_holidays date[];
    v_version  jsonb := NULLIF(p_change->'version', 'null'::jsonb);
    v_offs     integer[];
    v_result   jsonb := '{}';
BEGIN
    PERFORM sla_assert_change_allowed(p_change);

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
$$;

-- The what-if: a new version has no Turnaround Time for a retired category, so those
-- issues keep the days they were given rather than dropping out of their ticket's deadline.
CREATE OR REPLACE FUNCTION public.sla_on_time_whatif(p_acceptance_days integer, p_weekly_offs integer[], p_turnaround jsonb, p_holidays date[]) RETURNS TABLE(window_days integer, sla text, as_is_adhered integer, as_is_judged integer, would_be_adhered integer, would_be_judged integer)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    WITH cand AS (
        SELECT (e->>'category')::issue_category AS category, (e->>'severity')::issue_severity AS severity,
               (e->>'sla_days')::int AS sla_days
        FROM jsonb_array_elements(p_turnaround) e
    ),
    f AS (SELECT * FROM sla_ticket_facts()),
    tk AS (
        SELECT f.*,
               (SELECT max(add_working_days(f.raised_at, COALESCE(c.sla_days, i.sla_days), p_weekly_offs, p_holidays))
                FROM issues i LEFT JOIN cand c ON c.category = i.category AND c.severity = i.severity
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
$$;
