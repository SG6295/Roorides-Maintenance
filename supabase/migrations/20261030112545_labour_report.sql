-- MAIN-117: the rows behind Analytics › Labour utilisation, one per piece of labour on an
-- in-house work item.
--
--   attributed = true   an issue_labour row: one technician's hours on one work item.
--                       Work items completed in [p_from, p_to], plus those not yet Done
--                       (completed_on NULL) so the page can say how many hours are still
--                       open; the client separates the two by completed_on.
--   attributed = false  a work item's pre-MAIN-116 issues.labour_hours, which has no person
--                       attached, counted only while the item has no issue_labour rows.
--
-- SECURITY INVOKER: RLS decides what the caller sees (the page is exec/super_admin only).
-- users is LEFT JOINed so a technician the caller cannot read never drops the hours.

CREATE FUNCTION public.get_labour_report(p_from date, p_to date)
    RETURNS TABLE (
        issue_id        uuid,
        issue_number    text,
        description     text,
        category        text,
        completed_on    date,
        site            text,
        vehicle_number  text,
        job_card_number integer,
        technician_id   uuid,
        technician_name text,
        technician_role text,
        hours           numeric,
        attributed      boolean
    )
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
    SELECT i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           il.technician_id, u.name, u.role, il.hours, true
    FROM   public.issue_labour il
    JOIN   public.issues    i  ON i.id  = il.issue_id
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    LEFT JOIN public.users  u  ON u.id  = il.technician_id
    WHERE  jc.type = 'InHouse'
    AND    (i.completed_on BETWEEN p_from AND p_to OR i.completed_on IS NULL)

    UNION ALL

    SELECT i.id, i.issue_number, i.description, i.category::text, i.completed_on,
           jc.site, jc.vehicle_number, jc.job_card_number,
           NULL, NULL, NULL, i.labour_hours, false
    FROM   public.issues    i
    JOIN   public.job_cards jc ON jc.id = i.job_card_id
    WHERE  jc.type = 'InHouse'
    AND    i.labour_hours > 0
    AND    i.completed_on BETWEEN p_from AND p_to
    AND    NOT EXISTS (SELECT 1 FROM public.issue_labour il WHERE il.issue_id = i.id);
$$;

COMMENT ON FUNCTION public.get_labour_report(date, date) IS
    'Rows behind Analytics › Labour utilisation (MAIN-117): per-technician labour (attributed) and pre-MAIN-116 hours with no person (unattributed) on in-house work items, by activity complete date.';
