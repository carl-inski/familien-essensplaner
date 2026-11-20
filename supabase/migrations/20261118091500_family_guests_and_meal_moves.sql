alter table public.ep_meal_plan
  add column family_guests integer check (family_guests between 0 and 10000);

-- Check the final state because the move RPC swaps dishes and repoints the
-- leftover rows in separate statements of the same transaction.
create function public.ep_check_leftover_timing()
returns trigger
language plpgsql security invoker set search_path = ''
as $$
declare
  child public.ep_meal_plan;
  origin public.ep_meal_plan;
  meals constant text[] := array['fruehstueck', 'mittag', 'abend', 'snack'];
begin
  if tg_op = 'UPDATE' and (old.date, old.meal, old.leftover_of) is not distinct from (new.date, new.meal, new.leftover_of) then
    return null;
  end if;
  select * into child from public.ep_meal_plan where id = new.id;
  if child.leftover_of is null or child.status = 'ausgefallen' then
    return null;
  end if;
  select * into origin from public.ep_meal_plan
    where id = child.leftover_of and household_id = child.household_id for share;
  if not found or origin.recipe_id is null or origin.leftover_of is not null or origin.status = 'ausgefallen'
    or origin.date < child.date - 10
    or (origin.date, array_position(meals, origin.meal)) >= (child.date, array_position(meals, child.meal)) then
    raise sqlstate 'PT422' using message = 'Das Ursprungsgericht muss vor den Resten und höchstens zehn Tage zurück liegen.';
  end if;
  return null;
end;
$$;

create constraint trigger ep_check_leftover_timing
  after insert or update of date, meal, leftover_of on public.ep_meal_plan
  deferrable initially deferred
  for each row execute function public.ep_check_leftover_timing();
revoke execute on function public.ep_check_leftover_timing() from public, anon, authenticated;

create function public.ep_clear_planned_meal(p_household uuid, p_id uuid, p_expected jsonb)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  current_meal public.ep_meal_plan;
  expected public.ep_meal_plan;
begin
  if p_household is null or p_household is distinct from public.ep_active_household() then
    raise exception 'Dieser Haushalt ist nicht verfügbar.';
  end if;
  select * into current_meal from public.ep_meal_plan where id = p_id and household_id = p_household for update;
  if not found then return; end if;
  expected := jsonb_populate_record(null::public.ep_meal_plan, p_expected);
  if (current_meal.id, current_meal.recipe_id, current_meal.leftover_of, current_meal.status,
      current_meal.cook_id, current_meal.cook2_id, current_meal.note, current_meal.servings_override,
      current_meal.shopped_at, current_meal.family_guests)
     is distinct from
     (expected.id, expected.recipe_id, expected.leftover_of, expected.status,
      expected.cook_id, expected.cook2_id, expected.note, expected.servings_override,
      expected.shopped_at, expected.family_guests) then
    raise sqlstate 'PT409' using message = 'Die Mahlzeit wurde inzwischen geändert.';
  end if;
  if exists (select 1 from public.ep_meal_plan where household_id = p_household
             and leftover_of = p_id and status <> 'ausgefallen') then
    raise sqlstate 'PT422' using message = 'Entferne zuerst die Reste, die mit diesem Gericht verknüpft sind.';
  end if;
  delete from public.ep_attendance
    where date = current_meal.date and meal = current_meal.meal
      and member_id in (select id from public.ep_members where household_id = p_household);
  delete from public.ep_meal_plan where household_id = p_household and id = p_id;
end;
$$;
revoke execute on function public.ep_clear_planned_meal(uuid, uuid, jsonb) from public, anon;
grant execute on function public.ep_clear_planned_meal(uuid, uuid, jsonb) to authenticated;
