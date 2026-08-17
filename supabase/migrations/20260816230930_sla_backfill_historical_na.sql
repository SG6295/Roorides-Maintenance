-- MAIN-45, part 4 of 4: settle every pre-existing row.
--
-- Part 2 discarded the old `date` deadlines when it changed the column type: a stored date
-- cannot say which instant it meant, and inventing one would manufacture verdicts that
-- were never measured. This decides what each existing row should say instead.
--
-- Two populations, treated differently:
--
--   Finished tickets (Resolved / Closed / Rejected) keep no verdict. Their SLA was judged
--   under the old semantics - calendar days, date-granular, breaching at midnight UTC -
--   and cannot be honestly restated under the new ones. They are marked NA, which
--   reporting must read as "no SLA data", never as Adhered. This is ticket decision 3.
--
--   Open tickets are recomputed rather than abandoned. They are still in flight, so a
--   correct new-style deadline is exactly what they need. Ticket decision 2 anticipated
--   this ("only open tickets would get a recomputed deadline") and noted it was moot for
--   production, which holds 1,653 tickets and none open. It is not moot everywhere:
--   staging carries 3, and the app has to come out of this migration coherent on both.
--
-- On production this therefore collapses to exactly the blanket-NA the ticket describes.

-- 1. Give every in-flight ticket an acceptance deadline under the new definition.
UPDATE public.tickets
SET acceptance_sla_end_date = public.acceptance_deadline(created_at AT TIME ZONE 'UTC')
WHERE status NOT IN ('Resolved', 'Closed', 'Rejected');

-- 2. Recompute issue deadlines for open work. trg_update_ticket_sla_agg rolls each one up
--    into tickets.final_sla_end_date and re-derives overall_sla_status, so this covers the
--    completion side of both tables in one pass.
SELECT public.recalculate_open_slas();

-- 3. Re-judge acceptance on open tickets that already received their first issue. The
--    inputs are both still known - the first issue's creation time and the deadline just
--    stamped in step 1 - so this is a genuine remeasurement, not a guess. Open tickets
--    with no issue yet keep acceptance_sla_status = 'Pending' and will be judged normally
--    when their first issue arrives.
UPDATE public.tickets t
SET acceptance_sla_status = public.evaluate_acceptance_sla(t.id, fi.first_issue)
FROM (
    SELECT ticket_id, MIN(created_at) AT TIME ZONE 'UTC' AS first_issue
    FROM public.issues
    GROUP BY ticket_id
) fi
WHERE fi.ticket_id = t.id
  AND t.status NOT IN ('Resolved', 'Closed', 'Rejected');

-- 4. An open ticket with no issues has nothing to complete yet, so its completion SLA is
--    Pending rather than whatever the old logic last wrote.
UPDATE public.tickets
SET overall_sla_status = 'Pending'
WHERE status NOT IN ('Resolved', 'Closed', 'Rejected')
  AND final_sla_end_date IS NULL;

-- 5. Finished tickets: no verdict, no deadline. Left last so nothing above can re-derive
--    them. This updates neither `status` nor the transition into Rejected, so it wakes
--    neither trg_ticket_sla_on_status_change nor the rejected-at stamper.
UPDATE public.tickets
SET overall_sla_status    = 'NA',
    acceptance_sla_status = 'NA',
    final_sla_end_date    = NULL,
    acceptance_sla_end_date = NULL
WHERE status IN ('Resolved', 'Closed', 'Rejected');

-- issues.sla_end_date was already emptied by the type change in part 2 and is left NULL
-- for finished work. issues.sla_status is deliberately untouched: no trigger has ever
-- written it and nothing reads it, so setting it here would lend it a meaning it does not
-- have. It wants removing, but that is not this ticket's business.
