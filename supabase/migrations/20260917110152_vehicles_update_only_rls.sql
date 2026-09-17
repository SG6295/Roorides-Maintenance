-- MAIN-68: vehicles enter the system only through the Roorides feed.
--
-- "Exec and finance manage vehicles" was FOR ALL, so maintenance_exec, finance and
-- super_admin could INSERT and DELETE vehicles straight from the browser. A row created
-- that way can never reconcile with the feed: the sync cannot confirm, correct or retire
-- it, and it gets no vehicle_sites rows (that table is SELECT-only to browser clients),
-- so it is invisible to every supervisor from the moment it is created.
--
-- Narrowed to UPDATE so feed-only creation is enforced by the database rather than merely
-- hidden in the UI. Nothing legitimately needs INSERT or DELETE here: the only writer is
-- sync-roorides-vehicles, which uses the service-role key and bypasses RLS entirely.
--
-- The policy is recreated rather than altered because ALTER POLICY cannot change a
-- policy's command. Renamed to match the schema's existing convention, where "manage"
-- denotes FOR ALL and "update" denotes FOR UPDATE (cf. "Exec and finance update invoices").
--
-- WITH CHECK is deliberately omitted: Postgres reuses the USING expression as the check
-- for UPDATE when it is absent, and the two would be identical.

drop policy if exists "Exec and finance manage vehicles" on public.vehicles;

create policy "Exec and finance update vehicles" on public.vehicles
  for update
  using (
    exists (
      select 1
      from public.users
      where users.id = auth.uid()
        and users.role = any (array['maintenance_exec'::text, 'finance'::text, 'super_admin'::text])
    )
  );
