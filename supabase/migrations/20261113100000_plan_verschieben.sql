-- Gericht verschieben: tauscht den Inhalt zweier Mahlzeiten in einem Schritt.
-- Das Ziel darf leer sein. Käufe (ep_purchases) und Reste-Verweise wandern mit dem
-- Gericht, Koch und Notiz bleiben beim Tag. Portionen rechnen sich am neuen Tag neu.
-- Dieselben Regeln bildet lib/plan-change.ts für die Vorschau nach.

create or replace function public.ep_plan_move(p_from_date date, p_from_meal text, p_to_date date, p_to_meal text)
returns void
language plpgsql security invoker set search_path = ''
as $$
declare
  hh uuid := public.ep_active_household();
  a public.ep_meal_plan;
  b public.ep_meal_plan;
begin
  if hh is null then raise exception 'Bitte melde dich an'; end if;
  if p_from_date < public.ep_today() then raise exception 'Vergangene Mahlzeiten lassen sich nicht mehr ändern.'; end if;
  if p_to_date < public.ep_today() then raise exception 'In die Vergangenheit lässt sich nichts verschieben.'; end if;
  if p_from_date = p_to_date and p_from_meal = p_to_meal then raise exception 'Das Gericht steht schon dort.'; end if;

  select * into a from public.ep_meal_plan where household_id = hh and date = p_from_date and meal = p_from_meal for update;
  if a.id is null or (a.recipe_id is null and a.leftover_of is null) then raise exception 'Dort ist nichts geplant.'; end if;

  insert into public.ep_meal_plan (household_id, date, meal) values (hh, p_to_date, p_to_meal)
  on conflict (household_id, date, meal) do nothing;
  select * into b from public.ep_meal_plan where household_id = hh and date = p_to_date and meal = p_to_meal for update;

  if a.leftover_of = b.id or b.leftover_of = a.id then
    raise exception 'Ein Gericht und seine Reste lassen sich nicht tauschen.';
  end if;

  update public.ep_meal_plan set recipe_id = b.recipe_id, leftover_of = b.leftover_of, servings_override = null, status = 'geplant' where id = a.id;
  update public.ep_meal_plan set recipe_id = a.recipe_id, leftover_of = a.leftover_of, servings_override = null, status = 'geplant' where id = b.id;

  update public.ep_meal_plan
     set leftover_of = case when leftover_of = a.id then b.id else a.id end
   where household_id = hh and leftover_of in (a.id, b.id) and id not in (a.id, b.id);

  update public.ep_purchases
     set meal_plan_id = case when meal_plan_id = a.id then b.id else a.id end
   where household_id = hh and meal_plan_id in (a.id, b.id);
end $$;

revoke execute on function public.ep_plan_move(date, text, date, text) from public, anon;
grant execute on function public.ep_plan_move(date, text, date, text) to authenticated;
