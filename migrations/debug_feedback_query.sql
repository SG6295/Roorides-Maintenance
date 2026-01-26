-- Diagnostic: Check if there are any issues with feedback
-- Run these queries in Supabase SQL Editor to debug

-- 1. Check if there are any issues with Done status
SELECT id, issue_number, status, feedback, feedback_comment, feedback_date 
FROM issues 
WHERE status = 'Done' 
LIMIT 10;

-- 2. Check if any issues have feedback (feedback is not null)
SELECT id, issue_number, status, feedback, feedback_comment, feedback_date 
FROM issues 
WHERE feedback IS NOT NULL
LIMIT 10;

-- 3. Check the data types and values in tickets.supervisor_id
SELECT id, ticket_number, supervisor_id 
FROM tickets 
LIMIT 5;

-- 4. Check the user structure - what are the ID fields?
SELECT id, employee_id, name, role 
FROM users
LIMIT 5;
