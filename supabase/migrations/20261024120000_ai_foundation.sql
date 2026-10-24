-- KI-Fundament: Cache pro Haushalt mit Zeilenrechten, Verbrauchsübersicht.
-- Alle KI-Routen arbeiten mit der Session des Nutzers, RLS gilt also auch hier.

alter table public.ep_ai_cache
  add column household_id uuid not null references public.ep_households(id) on delete cascade,
  add column feature text not null;
create index ep_ai_cache_household on public.ep_ai_cache (household_id, feature);

create policy ep_ai_cache_select on public.ep_ai_cache for select to authenticated
  using (household_id in (select public.ep_my_household_ids()));
create policy ep_ai_cache_insert on public.ep_ai_cache for insert to authenticated
  with check (household_id in (select public.ep_my_household_ids()));
create policy ep_ai_cache_update on public.ep_ai_cache for update to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

-- Verbrauch für Limits und Anzeige; Monats- und Tagesgrenzen in Berliner Zeit.
-- security invoker: es zählen nur Zeilen, die der Aufrufer sehen darf.
create or replace function public.ep_ai_usage_summary(p_household uuid, p_member uuid)
returns table (month_calls int, month_cache_hits int, month_cost_eur numeric, my_calls_today int)
language sql stable security invoker set search_path = ''
as $$
  with b as (
    select
      date_trunc('month', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin' as month_start,
      date_trunc('day', now() at time zone 'Europe/Berlin') at time zone 'Europe/Berlin' as day_start
  )
  select
    count(*) filter (where not u.cache_hit)::int,
    count(*) filter (where u.cache_hit)::int,
    coalesce(sum(u.cost_eur), 0),
    count(*) filter (where not u.cache_hit and u.member_id = p_member and u.created_at >= b.day_start)::int
  from b
  left join public.ep_ai_usage u
    on u.household_id = p_household and u.created_at >= b.month_start
  group by b.month_start, b.day_start
$$;

revoke execute on function public.ep_ai_usage_summary(uuid, uuid) from public, anon;
grant execute on function public.ep_ai_usage_summary(uuid, uuid) to authenticated;
