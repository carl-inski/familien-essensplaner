-- Store the selected assignments together, and roll back if any preview is stale.
create function public.ep_assistant_schedule_checked(p_household uuid, p_assignments jsonb)
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
       target_meal is null or target_meal not in ('mittag', 'abend') or
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

revoke execute on function public.ep_assistant_schedule_checked(uuid, jsonb) from public, anon;
grant execute on function public.ep_assistant_schedule_checked(uuid, jsonb) to authenticated;
