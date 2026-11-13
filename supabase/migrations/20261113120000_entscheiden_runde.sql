-- Entscheiden, nach Nutzerfeedback:
--  1. Je Familie höchstens eine offene Runde. Vergessene Runden (zwei Stunden ohne
--     Bewegung) gelten beim Eröffnen einer neuen als beendet.
--  2. Wann es das Gericht gibt, wird erst nach der Entscheidung gewählt. date/meal
--     dürfen leer sein; ep_decide_finish schreibt nur noch in den Plan, wenn eine
--     Runde (aus einer älteren App-Version) schon ein Datum hat. Sonst plant
--     ep_decide_schedule den Sieger ein. Kam die Runde aus dem Wochenplan,
--     merkt suggested_date/suggested_meal den Wunsch als Vorauswahl.
--  3. Zwei neue Spiele: Tellerjagd und Tauziehen.

alter table public.ep_decide_sessions alter column date drop not null;
alter table public.ep_decide_sessions alter column meal drop not null;
alter table public.ep_decide_sessions alter column meal drop default;
alter table public.ep_decide_sessions add column if not exists suggested_date date;
alter table public.ep_decide_sessions add column if not exists suggested_meal text check (suggested_meal is null or suggested_meal in ('mittag', 'abend'));

alter table public.ep_decide_sessions drop constraint if exists ep_decide_sessions_game_check;
alter table public.ep_decide_sessions add constraint ep_decide_sessions_game_check
  check (game in ('swipe', 'duell', 'rad', 'loeffel', 'jagd', 'zug'));

-- Vor dem Index: Vergessenes beenden, dann je Familie nur die jüngste offene Runde behalten
update public.ep_decide_sessions set status = 'cancelled'
 where status in ('lobby', 'playing') and updated_at < now() - interval '2 hours';
update public.ep_decide_sessions s set status = 'cancelled'
 where s.status in ('lobby', 'playing')
   and exists (select 1 from public.ep_decide_sessions o
                where o.household_id = s.household_id and o.status in ('lobby', 'playing')
                  and (o.created_at, o.id) > (s.created_at, s.id));
create unique index if not exists ep_decide_one_open on public.ep_decide_sessions (household_id)
  where status in ('lobby', 'playing');

-- Runde eröffnen. Läuft schon eine, kommt deren id mit already_open = true zurück.
create or replace function public.ep_decide_create(p_game text, p_seed int, p_candidates uuid[], p_suggested_date date, p_suggested_meal text)
returns table (id uuid, already_open boolean)
language plpgsql security invoker set search_path = ''
as $$
declare
  hh uuid := public.ep_active_household();
  me uuid;
  sid uuid;
begin
  if hh is null then raise exception 'Bitte melde dich an'; end if;
  select m.id into me from public.ep_members m where m.household_id = hh and m.user_id = (select auth.uid());
  update public.ep_decide_sessions set status = 'cancelled'
   where household_id = hh and status in ('lobby', 'playing') and updated_at < now() - interval '2 hours';
  select s.id into sid from public.ep_decide_sessions s where s.household_id = hh and s.status in ('lobby', 'playing');
  if sid is not null then
    return query select sid, true;
    return;
  end if;
  begin
    insert into public.ep_decide_sessions (household_id, created_by, game, seed, candidates, suggested_date, suggested_meal)
    values (hh, me, p_game, p_seed, p_candidates, p_suggested_date, p_suggested_meal)
    returning ep_decide_sessions.id into sid;
  exception when unique_violation then
    -- gleichzeitig eröffnet: die andere Runde gewinnt
    select s.id into sid from public.ep_decide_sessions s where s.household_id = hh and s.status in ('lobby', 'playing');
    return query select sid, true;
    return;
  end;
  insert into public.ep_decide_players (session_id, member_id) values (sid, me);
  return query select sid, false;
end $$;

-- Sieger festhalten. In den Plan nur, wenn die Runde schon ein Datum hat (ältere App-Version).
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
  if s.date is not null then
    insert into public.ep_meal_plan (household_id, date, meal, recipe_id, leftover_of, status, servings_override)
    values (s.household_id, s.date, coalesce(s.meal, 'abend'), p_recipe, null, 'geplant', null)
    on conflict (household_id, date, meal) do update
      set recipe_id = excluded.recipe_id, leftover_of = null, status = 'geplant', shopped_at = null;
  end if;
  return true;
end $$;

-- Sieger einplanen – einmal, von irgendwem aus der Familie
create or replace function public.ep_decide_schedule(p_session uuid, p_date date, p_meal text)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare s public.ep_decide_sessions;
begin
  if p_meal not in ('mittag', 'abend') then raise exception 'Mittag oder Abend'; end if;
  if p_date < public.ep_today() then raise exception 'In die Vergangenheit lässt sich nichts einplanen.'; end if;
  update public.ep_decide_sessions set date = p_date, meal = p_meal
   where id = p_session and status = 'done' and winner_recipe_id is not null and date is null
  returning * into s;
  if s.id is null then raise exception 'Das Gericht ist schon eingeplant.'; end if;
  insert into public.ep_meal_plan (household_id, date, meal, recipe_id, leftover_of, status, servings_override)
  values (s.household_id, p_date, p_meal, s.winner_recipe_id, null, 'geplant', null)
  on conflict (household_id, date, meal) do update
    set recipe_id = excluded.recipe_id, leftover_of = null, status = 'geplant', shopped_at = null;
end $$;

revoke execute on function public.ep_decide_create(text, int, uuid[], date, text) from public, anon;
grant execute on function public.ep_decide_create(text, int, uuid[], date, text) to authenticated;
revoke execute on function public.ep_decide_schedule(uuid, date, text) from public, anon;
grant execute on function public.ep_decide_schedule(uuid, date, text) to authenticated;
