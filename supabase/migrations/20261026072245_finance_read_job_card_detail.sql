-- MAIN-88: finance can view job cards (read-only).
--
-- "Finance view job cards" already lets finance read job_cards, but nothing joined to
-- it. useJobCard embeds issues -> issue_parts, each issue's ticket number and the
-- assigned mechanic's name, so a finance user opening a card saw an empty issues list,
-- no parts and no mechanic. The same gap left finance's Inventory -> Consumption History
-- tab empty, since it reads issue_parts too.
--
-- All four policies are SELECT-only. Finance gets no write path onto a job card.
--
-- is_finance() exists for the users policy: a policy on users that checks the caller's
-- role with a subquery on users recurses. SECURITY DEFINER bypasses RLS for the lookup,
-- the same way is_maintenance_exec() does. The other three policies use it as well, for
-- one spelling of "is the caller finance".

create function public.is_finance() returns boolean
    language sql stable security definer
    set search_path to 'public'
    as $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'finance'
  )
$$;

alter function public.is_finance() owner to postgres;
grant all on function public.is_finance() to anon, authenticated, service_role;

create policy "Finance view issues" on public.issues
  for select
  using (public.is_finance());

create policy "Finance view issue parts" on public.issue_parts
  for select
  using (public.is_finance());

-- Needed for the ticket number on each issue row. The Tickets and Issues pages are not
-- role-gated, so finance now sees every site's tickets and issues there too, read-only.
create policy "Finance view tickets" on public.tickets
  for select
  using (public.is_finance());

-- Names of the people a job card can be assigned to, not every profile.
create policy "Finance view mechanic profiles" on public.users
  for select
  using (public.is_finance() and role = any (array['mechanic'::text, 'electrician'::text]));
