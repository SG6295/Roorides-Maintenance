-- MAIN-135, part 2: judge every tracked ticket and issue once under the new rules.
--
-- The audit and re-judging triggers are off while the columns are filled, so the backfill
-- writes no timeline entries and each ticket is judged once, at the end.

ALTER TABLE public.issues DISABLE TRIGGER issue_completed_at_audit;
ALTER TABLE public.issues DISABLE TRIGGER trg_update_ticket_sla_agg;

-- 1. Activity complete time. The exact moment from audit_logs: the last time the issue
--    moved into Done (the app logs every status change, keyed by ticket, with the full row
--    in new_data). Where the exec corrected the date, or there is no such entry, 00:00 IST
--    on completed_on. set_issue_completed_on keeps completed_on in step, which also fills
--    it for the few Done issues that had none.
WITH done_ev AS (
    SELECT (a.new_data->>'id')::uuid AS issue_id, max(a.performed_at) AS last_done
    FROM public.audit_logs a
    WHERE a.table_name = 'issues'
      AND a.new_data ? 'id'
      AND a.new_data->>'status' = 'Done'
      AND coalesce(a.old_data->>'status', '') <> 'Done'
    GROUP BY 1
),
times AS (
    SELECT i.id,
           CASE WHEN i.completed_on IS NOT NULL
                     AND (d.last_done IS NULL
                          OR (d.last_done AT TIME ZONE 'Asia/Kolkata')::date <> i.completed_on)
                THEN i.completed_on::timestamp AT TIME ZONE 'Asia/Kolkata'
                ELSE d.last_done
           END AS completed_at
    FROM public.issues i
    LEFT JOIN done_ev d ON d.issue_id = i.id
    WHERE i.status = 'Done'
)
UPDATE public.issues i
SET completed_at = t.completed_at
FROM times t
WHERE t.id = i.id
  AND t.completed_at IS NOT NULL;

-- 2. Deadlines from the ticket's raise time, for every tracked issue, finished or not.
UPDATE public.issues i
SET sla_end_date = public.add_working_days(t.created_at AT TIME ZONE 'UTC', i.sla_days)
FROM public.tickets t
WHERE t.id = i.ticket_id
  AND public.is_sla_tracked(t.created_at)
  AND i.sla_end_date IS DISTINCT FROM public.add_working_days(t.created_at AT TIME ZONE 'UTC', i.sla_days);

ALTER TABLE public.issues ENABLE TRIGGER trg_update_ticket_sla_agg;
ALTER TABLE public.issues ENABLE TRIGGER issue_completed_at_audit;

-- 3. Rule 8: a finished ticket with an issue that isn't Done goes back to Work In
--    Progress (tickets 21, 497 and 2351 in prod). The stamp trigger clears resolved_at.
UPDATE public.tickets t
SET status = 'Work In Progress'
WHERE t.status IN ('Resolved', 'Closed')
  AND EXISTS (SELECT 1 FROM public.issues i WHERE i.ticket_id = t.id AND i.status <> 'Done');

-- 4. Judge everything, then turn overdue Acceptance SLAs to Violated.
SELECT public.refresh_ticket_sla(id) FROM public.tickets;
SELECT public.refresh_overdue_slas();
