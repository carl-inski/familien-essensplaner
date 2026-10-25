-- 1) Profilbilder: Bild liegt im Bucket ep-images unter <household_id>/avatars/…
alter table public.ep_members add column if not exists avatar_url text;

-- 2) Kein „gekocht?“ mehr: Gerichte im Plan gelten als gekocht, sobald der Tag vorbei ist.
--    „Ausgefallen“ bleibt die Ausnahme. Datum nach deutscher Zeit.
create or replace function public.ep_today()
returns date
language sql stable set search_path = ''
as $$ select (now() at time zone 'Europe/Berlin')::date $$;

-- Neue oder geänderte Einträge in der Vergangenheit (z. B. nachgetragen) sofort als gekocht
create or replace function public.ep_meal_plan_auto_cooked()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.status = 'geplant' and new.recipe_id is not null and new.leftover_of is null
     and new.date < public.ep_today() then
    new.status := 'gekocht';
  end if;
  return new;
end $$;
create or replace trigger ep_meal_plan_auto_cooked before insert or update on public.ep_meal_plan
  for each row execute function public.ep_meal_plan_auto_cooked();

-- Kochhistorie folgt dem Plan: auch wenn Rezept, Datum oder Koch eines gekochten Eintrags geändert werden
create or replace function public.ep_meal_plan_history()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'gekocht' and new.recipe_id is not null and new.leftover_of is null then
    insert into public.ep_cooking_history (household_id, recipe_id, cooked_on, meal_plan_id, cook_id, servings, source)
    values (new.household_id, new.recipe_id, new.date, new.id, new.cook_id, new.servings_override, 'plan')
    on conflict (meal_plan_id) do update
      set recipe_id = excluded.recipe_id, cooked_on = excluded.cooked_on,
          cook_id = excluded.cook_id, servings = excluded.servings;
  elsif tg_op = 'UPDATE' and old.status = 'gekocht' then
    delete from public.ep_cooking_history where meal_plan_id = new.id;
  end if;
  return null;
end $$;
create or replace trigger ep_meal_plan_history after insert or update of status, recipe_id, leftover_of, date, cook_id, servings_override
  on public.ep_meal_plan for each row execute function public.ep_meal_plan_history();

-- Beim Öffnen der App: was seit gestern vorbei ist, als gekocht verbuchen (nur eigener Haushalt)
create or replace function public.ep_mark_past_cooked()
returns int
language sql security invoker set search_path = ''
as $$
  with done as (
    update public.ep_meal_plan set status = 'gekocht'
    where status = 'geplant' and recipe_id is not null and leftover_of is null
      and date < public.ep_today()
      and household_id in (select public.ep_my_household_ids())
    returning 1
  )
  select count(*)::int from done;
$$;
revoke all on function public.ep_mark_past_cooked() from public, anon;
grant execute on function public.ep_mark_past_cooked() to authenticated;

-- Einmalig: alles bisher Vergangene nachziehen
update public.ep_meal_plan set status = 'gekocht'
where status = 'geplant' and recipe_id is not null and leftover_of is null and date < public.ep_today();

-- 3) Storage: Löschen (altes Profilbild) braucht auch Lesezugriff – nur im eigenen Haushaltsordner
create policy ep_images_select on storage.objects for select to authenticated
  using (bucket_id = 'ep-images' and (storage.foldername(name))[1] in (select h::text from public.ep_my_household_ids() h));
