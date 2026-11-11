-- Entscheiden: kleine Spiele, mit denen die Familie zusammen ein Gericht für eine
-- Mahlzeit findet. Jede Person spielt am eigenen Handy; die Runde läuft über Realtime.
--
-- Ablauf: Lobby → Runden (round zählt hoch, state beschreibt die aktuelle Aufgabe) → fertig.
-- Jede Person schreibt nur ihre eigene Zeile in ep_decide_players; sind alle mit der
-- Runde fertig, rechnet ein beliebiges Gerät den nächsten Stand aus (lib/decide.ts,
-- deterministisch) und schreibt ihn – abgesichert über „where round = <alt>“.

create table if not exists public.ep_decide_sessions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  created_by uuid references public.ep_members(id) on delete set null,
  date date not null,
  meal text not null default 'abend' check (meal in ('fruehstueck', 'mittag', 'abend')),
  game text not null check (game in ('swipe', 'duell', 'rad', 'loeffel')),
  status text not null default 'lobby' check (status in ('lobby', 'playing', 'done', 'cancelled')),
  round int not null default 0,
  seed int not null default (floor(random() * 2147483647))::int,
  candidates uuid[] not null default '{}',
  state jsonb not null default '{}'::jsonb,
  winner_recipe_id uuid references public.ep_recipes(id) on delete set null
);
create index if not exists ep_decide_sessions_household on public.ep_decide_sessions (household_id, created_at desc);

create table if not exists public.ep_decide_players (
  session_id uuid not null references public.ep_decide_sessions(id) on delete cascade,
  member_id uuid not null references public.ep_members(id) on delete cascade,
  joined_at timestamptz not null default now(),
  -- letzte abgegebene Runde (-1 = noch keine)
  round_done int not null default -1,
  -- Abgaben je Runde: { "0": …, "1": … }
  data jsonb not null default '{}'::jsonb,
  primary key (session_id, member_id)
);
create index if not exists ep_decide_players_member on public.ep_decide_players (member_id);

alter table public.ep_decide_sessions enable row level security;
alter table public.ep_decide_players enable row level security;

create policy ep_decide_sessions_all on public.ep_decide_sessions for all to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

-- Lesen und Entfernen (hängt jemand, kann die Runde ohne die Person weiter): ganze Familie.
-- Schreiben: nur die eigene Zeile.
create policy ep_decide_players_select on public.ep_decide_players for select to authenticated
  using (exists (select 1 from public.ep_decide_sessions s where s.id = session_id and s.household_id in (select public.ep_my_household_ids())));
create policy ep_decide_players_delete on public.ep_decide_players for delete to authenticated
  using (exists (select 1 from public.ep_decide_sessions s where s.id = session_id and s.household_id in (select public.ep_my_household_ids())));
create policy ep_decide_players_insert on public.ep_decide_players for insert to authenticated
  with check (
    exists (select 1 from public.ep_decide_sessions s where s.id = session_id and s.status = 'lobby' and s.household_id in (select public.ep_my_household_ids()))
    and exists (select 1 from public.ep_members m where m.id = member_id and m.user_id = (select auth.uid()))
  );
create policy ep_decide_players_update on public.ep_decide_players for update to authenticated
  using (exists (select 1 from public.ep_members m where m.id = member_id and m.user_id = (select auth.uid())))
  with check (exists (select 1 from public.ep_members m where m.id = member_id and m.user_id = (select auth.uid())));

create or replace function public.ep_decide_touch()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;
create or replace trigger ep_decide_touch before update on public.ep_decide_sessions
  for each row execute function public.ep_decide_touch();
revoke execute on function public.ep_decide_touch() from public, anon, authenticated;

-- Runde abschließen: Sieger festhalten und in den Wochenplan eintragen – in einem Schritt,
-- und nur einmal (nur solange die Runde noch läuft und die Rundennummer stimmt).
create or replace function public.ep_decide_finish(p_session uuid, p_round int, p_recipe uuid, p_state jsonb)
returns boolean
language plpgsql security invoker set search_path = ''
as $$
declare s public.ep_decide_sessions;
begin
  update public.ep_decide_sessions
     set status = 'done', winner_recipe_id = p_recipe, state = p_state
   where id = p_session and status = 'playing' and round = p_round and p_recipe = any(candidates)
  returning * into s;
  if s.id is null then
    return false;
  end if;
  insert into public.ep_meal_plan (household_id, date, meal, recipe_id, leftover_of, status, servings_override)
  values (s.household_id, s.date, s.meal, p_recipe, null, 'geplant', null)
  on conflict (household_id, date, meal) do update
    set recipe_id = excluded.recipe_id, leftover_of = null, status = 'geplant', shopped_at = null;
  return true;
end $$;
revoke execute on function public.ep_decide_finish(uuid, int, uuid, jsonb) from public, anon;
grant execute on function public.ep_decide_finish(uuid, int, uuid, jsonb) to authenticated;

alter publication supabase_realtime add table public.ep_decide_sessions, public.ep_decide_players;
