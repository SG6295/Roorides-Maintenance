-- MAIN-134: finished tickets turned Violated when rated after their deadline.
--
-- tickets.resolved_at and closed_at were never written, so both verdict functions fell
-- through COALESCE(resolved_at, closed_at, now()) to the moment of recalculation. The
-- supervisor's rating moves a ticket to Closed, which recalculates, so any ticket rated
-- after its deadline was judged at the rating time instead of when the work finished.
--
-- This migration:
--   1. makes resolved_at / closed_at timestamptz (they held nothing, so nothing converts);
--   2. stamps them when a ticket enters Resolved / Closed;
--   3. judges a finished ticket at resolved_at only - never closed_at, never now();
--   4. backfills both from audit_logs and re-judges finished tickets.
--
-- MAIN-135 later replaces the verdict with the latest activity complete time across the
-- issues; the stamping trigger stays as it is (a ticket re-entering Resolved is restamped).

-- ---------------------------------------------------------------------------------------
-- 1. Column types
-- ---------------------------------------------------------------------------------------

-- maintenance_dashboard_stats reads resolved_at, and a column used by a view cannot change
-- type. Nothing in the app reads the view; it is recreated unchanged, grants included.
DROP VIEW IF EXISTS public.maintenance_dashboard_stats;

ALTER TABLE public.tickets
    ALTER COLUMN resolved_at TYPE timestamp with time zone USING resolved_at AT TIME ZONE 'UTC',
    ALTER COLUMN closed_at   TYPE timestamp with time zone USING closed_at   AT TIME ZONE 'UTC';

CREATE VIEW public.maintenance_dashboard_stats AS
 SELECT count(*) AS total_tickets,
    count(*) FILTER (WHERE status::text = 'New'::text) AS pending_tickets,
    count(*) FILTER (WHERE overall_sla_status::text = 'Violated'::text) AS completion_sla_violated,
    ( SELECT count(*) AS count
           FROM job_cards
          WHERE job_cards.type::text = 'InHouse'::text) AS inhouse_count,
    ( SELECT count(*) AS count
           FROM job_cards
          WHERE job_cards.type::text = 'Outsource'::text) AS outsource_count,
    COALESCE(avg(EXTRACT(day FROM
        CASE
            WHEN status::text = 'Resolved'::text THEN resolved_at
            ELSE now()
        END - created_at::timestamp with time zone)), 0::numeric) AS avg_tat_days
   FROM tickets;

ALTER VIEW public.maintenance_dashboard_stats OWNER TO postgres;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO anon;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO authenticated;
GRANT ALL ON TABLE public.maintenance_dashboard_stats TO service_role;

COMMENT ON COLUMN public.tickets.resolved_at IS
    'When the ticket entered Resolved (its last issue marked Done). Stamped by stamp_ticket_resolved_closed_at; the completion SLA is judged against it (MAIN-134).';
COMMENT ON COLUMN public.tickets.closed_at IS
    'When the ticket entered Closed (its last issue rated). Stamped by stamp_ticket_resolved_closed_at (MAIN-134).';

-- ---------------------------------------------------------------------------------------
-- 2. Stamp on entry
-- ---------------------------------------------------------------------------------------

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

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_stamp_ticket_resolved_closed_at ON public.tickets;
CREATE TRIGGER trg_stamp_ticket_resolved_closed_at
    BEFORE UPDATE OF status ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION stamp_ticket_resolved_closed_at();

-- ---------------------------------------------------------------------------------------
-- 3. Judge a finished ticket at resolved_at
-- ---------------------------------------------------------------------------------------
-- A finished ticket with no resolved_at keeps its stored verdict rather than being judged
-- at now(), which is the bug. After the backfill below no such ticket exists.

CREATE OR REPLACE FUNCTION public.recalculate_ticket_sla_on_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
    v_final_sla   timestamptz;
    v_resolved_at timestamptz;
BEGIN
    SELECT final_sla_end_date, resolved_at
    INTO v_final_sla, v_resolved_at
    FROM tickets WHERE id = NEW.id;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN NEW.status::text IN ('Resolved', 'Closed') AND v_resolved_at IS NULL
                THEN overall_sla_status
            WHEN NEW.status::text IN ('Resolved', 'Closed') AND v_final_sla >= v_resolved_at
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
$function$;

CREATE OR REPLACE FUNCTION public.calculate_ticket_overall_sla()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
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
    RETURNING final_sla_end_date, status::text, resolved_at
    INTO v_final_sla, v_status, v_resolved_at;

    UPDATE tickets
    SET overall_sla_status =
        CASE
            WHEN v_final_sla IS NULL
                THEN 'Pending'::sla_status_enum
            WHEN v_status IN ('Resolved', 'Closed') AND v_resolved_at IS NULL
                THEN overall_sla_status
            WHEN v_status IN ('Resolved', 'Closed') AND v_final_sla >= v_resolved_at
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
$function$;

-- ---------------------------------------------------------------------------------------
-- 4. Backfill and re-judge
-- ---------------------------------------------------------------------------------------
-- Issue audit rows are keyed by ticket (record_id = ticket_id).
--
-- resolved_at: the last time any of the ticket's issues moved into Done - the moment
-- update_ticket_status_on_issue_change moved the ticket to Resolved.
--
-- closed_at: the moment the last issue was first rated. Not issues.rated_at: re-rating
-- from the Feedback page rewrites it, which would date the close after the fact.

UPDATE public.tickets t
SET resolved_at = d.last_done
FROM (
    SELECT a.record_id AS ticket_id, max(a.performed_at) AS last_done
    FROM public.audit_logs a
    WHERE a.table_name = 'issues'
      AND a.new_data->>'status' = 'Done'
      AND coalesce(a.old_data->>'status', '') <> 'Done'
    GROUP BY a.record_id
) d
WHERE d.ticket_id = t.id
  AND t.status IN ('Resolved', 'Closed')
  AND t.resolved_at IS NULL;

UPDATE public.tickets t
SET closed_at = r.closed_ev
FROM (
    SELECT ticket_id, max(first_rated) AS closed_ev
    FROM (
        SELECT a.record_id AS ticket_id, a.new_data->>'id' AS issue_id,
               min(a.performed_at) AS first_rated
        FROM public.audit_logs a
        WHERE a.table_name = 'issues'
          AND a.new_data->>'rating' IS NOT NULL
          AND a.old_data->>'rating' IS NULL
        GROUP BY a.record_id, a.new_data->>'id'
    ) per_issue
    GROUP BY ticket_id
) r
WHERE r.ticket_id = t.id
  AND t.status = 'Closed'
  AND t.closed_at IS NULL;

-- Re-judge finished tickets with a deadline. NA (pre-tracking) is left alone.
UPDATE public.tickets
SET overall_sla_status =
    CASE WHEN final_sla_end_date >= resolved_at
         THEN 'Adhered'::sla_status_enum
         ELSE 'Violated'::sla_status_enum
    END
WHERE status IN ('Resolved', 'Closed')
  AND final_sla_end_date IS NOT NULL
  AND resolved_at IS NOT NULL
  AND overall_sla_status <> 'NA'
  AND overall_sla_status IS DISTINCT FROM
      CASE WHEN final_sla_end_date >= resolved_at
           THEN 'Adhered'::sla_status_enum
           ELSE 'Violated'::sla_status_enum
      END;
