-- Re-evaluate overall_sla_status for tickets that were previously stuck as Pending
-- after final_sla_end_date was backfilled.
UPDATE tickets t
SET overall_sla_status =
    CASE
        WHEN t.final_sla_end_date IS NULL
            THEN 'Pending'::sla_status_enum
        WHEN t.status::text IN ('Resolved', 'Closed')
             AND t.final_sla_end_date >= COALESCE(t.resolved_at::date, t.closed_at::date, CURRENT_DATE)
            THEN 'Adhered'::sla_status_enum
        WHEN t.status::text IN ('Resolved', 'Closed')
            THEN 'Violated'::sla_status_enum
        WHEN t.final_sla_end_date < CURRENT_DATE
            THEN 'Violated'::sla_status_enum
        ELSE 'Pending'::sla_status_enum
    END
WHERE t.overall_sla_status = 'Pending';
