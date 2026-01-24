-- Part 3b: Migrate Issues (Create issues from tickets)

BEGIN;

-- Migrate Tickets -> Issues
INSERT INTO issues (ticket_id, description, category, severity, status, created_at, sla_end_date)
SELECT 
    id, 
    complaint, 
    -- Category Mapping
    CASE 
        WHEN category::text ILIKE '%electrical%' THEN 'Electrical'::issue_category
        WHEN category::text ILIKE '%mechanical%' THEN 'Mechanical'::issue_category
        WHEN category::text ILIKE '%body%' THEN 'Body'::issue_category
        WHEN category::text ILIKE '%tyre%' THEN 'Tyre'::issue_category
        WHEN category::text ILIKE '%gps%' THEN 'GPS'::issue_category
        WHEN category::text ILIKE '%adblue%' THEN 'AdBlue'::issue_category
        ELSE 'Other'::issue_category
    END,
    -- Severity Mapping
    CASE 
        WHEN impact::text ILIKE 'Major' THEN 'Major'::issue_severity
        ELSE 'Minor'::issue_severity
    END,
    -- Status Mapping
    -- Note: We check against both old and potential new values just in case
    CASE 
        WHEN status::text IN ('Resolved', 'Closed', 'Completed') THEN 'Done'::issue_status 
        ELSE 'Open'::issue_status 
    END,
    created_at,
    sla_end_date
FROM tickets
WHERE NOT EXISTS (SELECT 1 FROM issues WHERE issues.ticket_id = tickets.id);

COMMIT;
