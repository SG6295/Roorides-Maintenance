-- Debug: Check user 'test' setup
SELECT id, name, employee_id, site, role FROM users WHERE employee_id = 'test';

-- Debug: Check if site names match exactly (case sensitivity)
SELECT DISTINCT site FROM tickets;
SELECT DISTINCT site FROM users WHERE role = 'supervisor';

-- Debug: Test the RLS policy logic manually
-- This simulates what the RLS policy does
SELECT 
    i.id,
    i.issue_number,
    i.status,
    t.site as ticket_site,
    u.site as user_site,
    u.role,
    (t.site = u.site) as site_matches
FROM issues i
JOIN tickets t ON t.id = i.ticket_id
JOIN users u ON u.employee_id = 'test'
WHERE i.status = 'Done';
