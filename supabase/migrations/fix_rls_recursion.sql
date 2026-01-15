
-- Fix infinite recursion by using a SECURITY DEFINER function
-- This allows checking the user's role without triggering RLS on the users table recursively

-- 1. Create a helper function to check role safely
CREATE OR REPLACE FUNCTION public.is_maintenance_exec()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER -- Run with privileges of creator, bypassing RLS
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid()
    AND role = 'maintenance_exec'
  );
$$;

-- 2. Clean up old recursive policies on 'users'
DROP POLICY IF EXISTS "Execs can read all profiles" ON users;
DROP POLICY IF EXISTS "Execs can update users" ON users;

-- 3. Create new non-recursive policies on 'users'
CREATE POLICY "Execs can read all profiles" ON users
  FOR SELECT USING (
    is_maintenance_exec() -- Use function instead of subquery
  );

CREATE POLICY "Execs can update users" ON users
  FOR UPDATE USING (
    is_maintenance_exec()
  );

-- 4. Update 'tickets' policies as well for consistency/performance
-- (The previous ones might have worked but this is safer/faster)

DROP POLICY IF EXISTS "Execs can see all tickets" ON tickets;
DROP POLICY IF EXISTS "Execs can update tickets" ON tickets;

CREATE POLICY "Execs can see all tickets" ON tickets
  FOR SELECT USING (
    is_maintenance_exec()
  );

CREATE POLICY "Execs can update tickets" ON tickets
  FOR UPDATE USING (
    is_maintenance_exec()
  );

-- Ensure normal users can still read their own profile (this was likely fine, but good to ensure)
DROP POLICY IF EXISTS "Users can read own profile" ON users;
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT USING (auth.uid() = id);
