-- Debug: Check for triggers on issues table that might reference old columns
-- Run these in Supabase SQL Editor

-- 1. List all triggers on issues table
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'issues';

-- 2. List all views that might reference issues table
SELECT 
    table_name as view_name,
    view_definition
FROM information_schema.views
WHERE table_schema = 'public';

-- 3. Check the exact columns currently in issues table
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_name = 'issues'
ORDER BY ordinal_position;

-- 4. Look for any functions that might reference 'feedback'
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_definition ILIKE '%feedback%';
