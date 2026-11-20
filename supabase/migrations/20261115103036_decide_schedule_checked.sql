-- Plan the winner only while the slot still matches the scheduling preview.
create function public.ep_decide_schedule_checked(
  p_session uuid, p_date date, p_meal text, p_expected_slot jsonb
)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  scheduled_session public.ep_decide_sessions;
begin
  if p_meal is null or p_meal not in ('mittag', 'abend') then
    raise exception 'Mittag oder Abend';
  end if;
  if p_date is null or p_date < public.ep_today() then
    raise exception 'Der Termin muss heute oder später sein.';
  end if;

  update public.ep_decide_sessions as game set date = p_date, meal = p_meal
  where game.id = p_session and game.status = 'done' and game.date is null
    and exists (select 1 from public.ep_recipes as recipe
                where recipe.id = game.winner_recipe_id and recipe.household_id = game.household_id)
  returning game.* into scheduled_session;
  if not found then
    raise exception 'Die Runde kann nicht mehr eingeplant werden.';
  end if;

  if p_expected_slot is null or p_expected_slot = 'null'::jsonb then
    insert into public.ep_meal_plan (household_id, date, meal, recipe_id)
    values (scheduled_session.household_id, p_date, p_meal, scheduled_session.winner_recipe_id)
    on conflict (household_id, date, meal) do nothing;
  else
    update public.ep_meal_plan as target
    set recipe_id = scheduled_session.winner_recipe_id, leftover_of = null, status = 'geplant',
        shopped_at = case when target.recipe_id = scheduled_session.winner_recipe_id
                                and target.leftover_of is null and target.status = 'geplant'
                          then target.shopped_at end
    where target.household_id = scheduled_session.household_id and target.date = p_date and target.meal = p_meal
      and target.id = (p_expected_slot ->> 'id')::uuid
      and target.status = (p_expected_slot ->> 'status')
      and target.recipe_id is not distinct from (p_expected_slot ->> 'recipe_id')::uuid
      and target.leftover_of is not distinct from (p_expected_slot ->> 'leftover_of')::uuid
      and target.note is not distinct from (p_expected_slot ->> 'note')
      and target.shopped_at is not distinct from (p_expected_slot ->> 'shopped_at')::timestamptz;
  end if;

  if not found then
    raise sqlstate 'PT409' using message = 'Der Termin wurde inzwischen geändert.';
  end if;
end;
$$;

revoke execute on function public.ep_decide_schedule_checked(uuid, date, text, jsonb) from public, anon;
grant execute on function public.ep_decide_schedule_checked(uuid, date, text, jsonb) to authenticated;
