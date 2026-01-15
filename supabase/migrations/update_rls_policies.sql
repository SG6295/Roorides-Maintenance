
-- Update Users Table Policies
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Allow users to read their own profile
CREATE POLICY "Users can read own profile" ON users
  FOR SELECT USING (auth.uid() = id);

-- Allow Maintenance Execs to read ALL profiles
CREATE POLICY "Execs can read all profiles" ON users
  FOR SELECT USING (
    exists (
      select 1 from users where id = auth.uid() and role = 'maintenance_exec'
    )
  );

-- Allow Maintenance Execs to update users (e.g. deactivate)
CREATE POLICY "Execs can update users" ON users
  FOR UPDATE USING (
    exists (
      select 1 from users where id = auth.uid() and role = 'maintenance_exec'
    )
  );
  
-- Allow Service Role (Edge Function) to insert users
-- (Service role bypasses RLS by default, but good to be explicit if we ever change that)
-- but actually standard authenticated users (supervisors) should NOT be able to insert.

-- Update Tickets Table Policies for Site Isolation

-- Drop existing generic policies if any
DROP POLICY IF EXISTS "Enable read access for all users" ON tickets;
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON tickets;
DROP POLICY IF EXISTS "Enable update for users based on email" ON tickets;

-- Policy 1: Execs can see ALL tickets
CREATE POLICY "Execs can see all tickets" ON tickets
  FOR SELECT USING (
    exists (
      select 1 from users where id = auth.uid() and role = 'maintenance_exec'
    )
  );

-- Policy 2: Supervisors/Others can see tickets for THEIR assigned site
CREATE POLICY "Site-restricted ticket access" ON tickets
  FOR SELECT USING (
    site in (
      select site from users where id = auth.uid()
    )
    OR
    created_by_user_id = auth.uid() 
  );

-- Policy 3: Supervisors can INSERT tickets
CREATE POLICY "Supervisors can create tickets" ON tickets
  FOR INSERT WITH CHECK (
    auth.uid() = created_by_user_id
  );

-- Policy 4: Execs can UPDATE tickets (for assignment/status)
CREATE POLICY "Execs can update tickets" ON tickets
  FOR UPDATE USING (
    exists (
      select 1 from users where id = auth.uid() and role = 'maintenance_exec'
    )
  );
