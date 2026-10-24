-- Einkauf über Wochengrenzen: Pro Gericht merken, ob seine Zutaten schon gekauft sind.
-- Die Einkaufsliste zeigt alle kommenden Gerichte ohne shopped_at.

alter table public.ep_meal_plan add column shopped_at timestamptz;

-- Wird ein Slot mit einem anderen Gericht belegt, muss neu eingekauft werden
create or replace function public.ep_meal_plan_reset_shopped()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.recipe_id is distinct from old.recipe_id or new.leftover_of is distinct from old.leftover_of then
    new.shopped_at := null;
  end if;
  return new;
end
$$;
revoke execute on function public.ep_meal_plan_reset_shopped() from public, anon, authenticated;

create trigger ep_meal_plan_reset_shopped before update on public.ep_meal_plan
  for each row execute function public.ep_meal_plan_reset_shopped();

-- Was beim letzten Einkauf nicht da war, plus Dinge, die man von Hand dazuschreibt
create table public.ep_shopping_extra (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  member_id uuid references public.ep_members(id) on delete set null,
  text text not null check (length(trim(text)) between 1 and 200),
  aisle text,
  carried boolean not null default false
);
create index ep_shopping_extra_household on public.ep_shopping_extra (household_id, created_at);
create index ep_shopping_extra_member on public.ep_shopping_extra (member_id);

alter table public.ep_shopping_extra enable row level security;
create policy ep_shopping_extra_all on public.ep_shopping_extra for all to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

alter publication supabase_realtime add table public.ep_shopping_extra, public.ep_pantry;
