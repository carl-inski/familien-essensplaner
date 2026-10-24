-- Notizen zu Rezepten (z. B. „weniger Chili“, „reicht für 2 Tage“), mit Autor und Datum

create table public.ep_recipe_notes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  recipe_id uuid not null references public.ep_recipes(id) on delete cascade,
  member_id uuid references public.ep_members(id) on delete set null,
  body text not null check (length(trim(body)) > 0 and length(body) <= 4000)
);
create index ep_recipe_notes_recipe on public.ep_recipe_notes (recipe_id, created_at desc);
create index ep_recipe_notes_member on public.ep_recipe_notes (member_id);

alter table public.ep_recipe_notes enable row level security;

-- Mitglied des Haushalts, dem das Rezept gehört?
create or replace function public.ep_recipe_in_my_household(p_recipe uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.ep_recipes r
    where r.id = p_recipe and r.household_id in (select public.ep_my_household_ids())
  )
$$;

-- Eigene Mitglieds-ID im Haushalt des Rezepts
create or replace function public.ep_my_member_for_recipe(p_recipe uuid)
returns uuid
language sql stable security definer set search_path = ''
as $$
  select m.id from public.ep_members m
  join public.ep_recipes r on r.household_id = m.household_id
  where r.id = p_recipe and m.user_id = (select auth.uid())
  limit 1
$$;

revoke execute on function public.ep_recipe_in_my_household(uuid) from public, anon;
revoke execute on function public.ep_my_member_for_recipe(uuid) from public, anon;
grant execute on function public.ep_recipe_in_my_household(uuid) to authenticated;
grant execute on function public.ep_my_member_for_recipe(uuid) to authenticated;

create policy ep_recipe_notes_select on public.ep_recipe_notes for select to authenticated
  using (public.ep_recipe_in_my_household(recipe_id));

-- Schreiben nur unter eigenem Namen
create policy ep_recipe_notes_insert on public.ep_recipe_notes for insert to authenticated
  with check (public.ep_recipe_in_my_household(recipe_id) and member_id = public.ep_my_member_for_recipe(recipe_id));

-- Ändern/Löschen: eigene Notizen, Admins alle
create policy ep_recipe_notes_update on public.ep_recipe_notes for update to authenticated
  using (
    public.ep_recipe_in_my_household(recipe_id)
    and (member_id = public.ep_my_member_for_recipe(recipe_id)
         or public.ep_is_admin((select r.household_id from public.ep_recipes r where r.id = recipe_id)))
  )
  with check (public.ep_recipe_in_my_household(recipe_id));

create policy ep_recipe_notes_delete on public.ep_recipe_notes for delete to authenticated
  using (
    public.ep_recipe_in_my_household(recipe_id)
    and (member_id = public.ep_my_member_for_recipe(recipe_id)
         or public.ep_is_admin((select r.household_id from public.ep_recipes r where r.id = recipe_id)))
  );

create or replace function public.ep_recipe_notes_touch()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  new.member_id := old.member_id; -- Autor bleibt
  new.recipe_id := old.recipe_id;
  return new;
end $$;
create trigger ep_recipe_notes_touch before update on public.ep_recipe_notes
  for each row execute function public.ep_recipe_notes_touch();
revoke execute on function public.ep_recipe_notes_touch() from public, anon, authenticated;

alter publication supabase_realtime add table public.ep_recipe_notes;
