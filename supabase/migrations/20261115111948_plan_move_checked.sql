-- Keep the reviewed source and destination locked through the existing swap.
create function public.ep_plan_move_checked(
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
     or p_from_meal is null or p_from_meal not in ('mittag', 'abend')
     or p_to_meal is null or p_to_meal not in ('mittag', 'abend')
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

revoke execute on function public.ep_plan_move_checked(uuid, date, text, date, text, jsonb, jsonb) from public, anon;
grant execute on function public.ep_plan_move_checked(uuid, date, text, date, text, jsonb, jsonb) to authenticated;
