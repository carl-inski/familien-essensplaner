-- Allow optional meals in the shared plan and attendance rows.
alter table public.ep_attendance
  drop constraint ep_attendance_meal_check,
  add constraint ep_attendance_meal_check check (meal in ('fruehstueck', 'mittag', 'abend', 'snack'));

alter table public.ep_meal_plan
  drop constraint ep_meal_plan_meal_check,
  add constraint ep_meal_plan_meal_check check (meal in ('fruehstueck', 'mittag', 'abend', 'snack'));

-- The existing function grants and transactional slot checks stay in place.
-- Store the selected assignments together, and roll back if any preview is stale.
create or replace function public.ep_assistant_schedule_checked(p_household uuid, p_assignments jsonb)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  assignment jsonb;
  target_date date;
  target_meal text;
  target_recipe uuid;
  expected jsonb;
begin
  if p_household is null or not exists (select 1 from public.ep_my_household_ids() as h(id) where h.id = p_household) then
    raise exception 'Dieser Haushalt ist nicht verfügbar.';
  end if;
  if jsonb_typeof(p_assignments) is distinct from 'array' then
    raise exception 'Es fehlt eine Auswahl zum Einplanen.';
  end if;
  if jsonb_array_length(p_assignments) not between 1 and 14 or
     (select count(distinct (item ->> 'date', item ->> 'meal'))
      from jsonb_array_elements(p_assignments) as rows(item)) <> jsonb_array_length(p_assignments) then
    raise exception 'Die Auswahl enthält ungültige oder doppelte Termine.';
  end if;

  for assignment in
    select item from jsonb_array_elements(p_assignments) as rows(item)
    order by item ->> 'date', item ->> 'meal'
  loop
    target_date := (assignment ->> 'date')::date;
    target_meal := assignment ->> 'meal';
    target_recipe := (assignment ->> 'recipe_id')::uuid;
    expected := assignment -> 'expected';
    if target_date is null or target_date < public.ep_today() or
       target_meal is null or target_meal not in ('fruehstueck', 'mittag', 'abend', 'snack') or
       not exists (select 1 from public.ep_recipes as recipe
                   where recipe.id = target_recipe and recipe.household_id = p_household) then
      raise exception 'Termin oder Rezept ist nicht verfügbar.';
    end if;

    if expected is null or expected = 'null'::jsonb then
      insert into public.ep_meal_plan (household_id, date, meal, recipe_id)
      values (p_household, target_date, target_meal, target_recipe)
      on conflict (household_id, date, meal) do nothing;
    else
      update public.ep_meal_plan as target
      set recipe_id = target_recipe, leftover_of = null, status = 'geplant',
          shopped_at = case when target.recipe_id = target_recipe
                                  and target.leftover_of is null and target.status = 'geplant'
                            then target.shopped_at end
      where target.household_id = p_household and target.date = target_date and target.meal = target_meal
        and target.id = (expected ->> 'id')::uuid
        and target.status = (expected ->> 'status')
        and target.recipe_id is not distinct from (expected ->> 'recipe_id')::uuid
        and target.leftover_of is not distinct from (expected ->> 'leftover_of')::uuid
        and target.note is not distinct from (expected ->> 'note')
        and target.shopped_at is not distinct from (expected ->> 'shopped_at')::timestamptz;
    end if;
    if not found then
      raise sqlstate 'PT409' using message = 'Der Wochenplan hat sich geändert.';
    end if;
  end loop;
end;
$$;
-- Keep the reviewed source and destination locked through the existing swap.
create or replace function public.ep_plan_move_checked(
  p_household uuid, p_from_date date, p_from_meal text, p_to_date date, p_to_meal text,
  p_expected_source jsonb, p_expected_target jsonb
)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  current_meal public.ep_meal_plan;
  expected public.ep_meal_plan;
  source_found boolean := false;
  target_found boolean := false;
begin
  if p_household is null or p_household is distinct from public.ep_active_household() then
    raise exception 'Dieser Haushalt ist nicht verfügbar.';
  end if;
  if p_from_date is null or p_to_date is null or p_from_date < public.ep_today() or p_to_date < public.ep_today()
     or p_from_meal is null or p_from_meal not in ('fruehstueck', 'mittag', 'abend', 'snack')
     or p_to_meal is null or p_to_meal not in ('fruehstueck', 'mittag', 'abend', 'snack')
     or (p_from_date, p_from_meal) = (p_to_date, p_to_meal) then
    raise exception 'Die Termine sind ungültig.';
  end if;

  for current_meal in
    select * from public.ep_meal_plan
    where household_id = p_household
      and (date, meal) in ((p_from_date, p_from_meal), (p_to_date, p_to_meal))
    order by date, meal
    for update
  loop
    if (current_meal.date, current_meal.meal) = (p_from_date, p_from_meal) then
      source_found := true;
      expected := jsonb_populate_record(null::public.ep_meal_plan, nullif(p_expected_source, 'null'::jsonb));
    else
      target_found := true;
      expected := jsonb_populate_record(null::public.ep_meal_plan, nullif(p_expected_target, 'null'::jsonb));
    end if;
    if (current_meal.id, current_meal.status, current_meal.recipe_id, current_meal.leftover_of,
        current_meal.note, current_meal.shopped_at, current_meal.cook_id, current_meal.cook2_id, current_meal.servings_override)
        is distinct from
       (expected.id, expected.status, expected.recipe_id, expected.leftover_of,
        expected.note, expected.shopped_at, expected.cook_id, expected.cook2_id, expected.servings_override) then
      raise sqlstate 'PT409' using message = 'Der Wochenplan hat sich geändert.';
    end if;
  end loop;

  if not source_found or (not target_found and nullif(p_expected_target, 'null'::jsonb) is not null) then
    raise sqlstate 'PT409' using message = 'Der Wochenplan hat sich geändert.';
  end if;
  if not target_found then
    insert into public.ep_meal_plan (household_id, date, meal)
    values (p_household, p_to_date, p_to_meal)
    on conflict (household_id, date, meal) do nothing;
    if not found then
      raise sqlstate 'PT409' using message = 'Der Wochenplan hat sich geändert.';
    end if;
  end if;

  perform public.ep_plan_move(p_from_date, p_from_meal, p_to_date, p_to_meal);
end;
$$;
