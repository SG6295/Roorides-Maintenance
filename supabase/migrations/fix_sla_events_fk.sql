-- Fix Foreign Key to point to public.users instead of auth.users
-- This allows us to join and fetch the user's name in the frontend

-- 1. Drop the old constraint
ALTER TABLE sla_events 
DROP CONSTRAINT SLA_EVENTS_created_by_fkey;

-- 2. Add new constraint referencing public.users
ALTER TABLE sla_events 
ADD CONSTRAINT sla_events_created_by_fkey 
FOREIGN KEY (created_by) 
REFERENCES public.users(id);

-- 3. Verify RLS (Existing policies should still work as IDs are the same)
