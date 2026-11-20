-- Der Suchtrigger deckt nur einen Teil der Rezeptspalten ab. Auch Änderungen am Foto,
-- an der Buchseite oder am Suchvektor nach einer Zutatenänderung brauchen eine Revision.
create function public.ep_recipes_touch_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := greatest(pg_catalog.clock_timestamp(), old.updated_at + interval '1 microsecond');
  return new;
end;
$$;

-- BEFORE-Trigger laufen alphabetisch. Diese Revision folgt auf ep_recipes_search.
create trigger ep_recipes_touch_revision before update on public.ep_recipes
  for each row execute function public.ep_recipes_touch_revision();

revoke execute on function public.ep_recipes_touch_revision() from public, anon, authenticated;

-- Rezept und Zutaten bilden einen Schreibvorgang. Alle Zugriffe laufen unter RLS.
create function public.ep_save_recipe(
  p_id uuid,
  p_household uuid,
  p_expected_updated_at timestamptz,
  p_recipe jsonb,
  p_ingredients jsonb default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  draft public.ep_recipes;
  saved_id uuid;
begin
  if p_id is null or p_household is null then
    raise exception 'Rezept oder Familie fehlt' using errcode = '22023';
  end if;
  select * into draft from pg_catalog.jsonb_populate_record(null::public.ep_recipes, p_recipe);
  if coalesce(trim(draft.title), '') = '' then
    raise exception 'Titel fehlt' using errcode = '22023';
  end if;
  if draft.cookbook_id is not null and not exists (
    select 1 from public.ep_cookbooks where id = draft.cookbook_id and household_id = p_household
  ) then
    raise exception 'Kochbuch gehört nicht zur Familie' using errcode = '42501';
  end if;

  if p_expected_updated_at is null then
    insert into public.ep_recipes (
      id, household_id, title, subtitle, source, categories, tags, folder_id, diet, time_text, time_min,
      servings, servings_text, steps, tip, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url,
      nutrition, nutrition_estimated, extra_meta
    ) values (
      p_id, p_household, draft.title, draft.subtitle, draft.source, draft.categories, draft.tags,
      draft.folder_id, draft.diet, draft.time_text, draft.time_min, draft.servings, draft.servings_text,
      draft.steps, draft.tip, draft.cookbook_id, draft.cookbook_page, draft.cookbook_link_confirmed, draft.image_url,
      draft.nutrition, coalesce(draft.nutrition_estimated, false), coalesce(draft.extra_meta, '{}'::jsonb)
    )
    on conflict (id) do nothing
    returning id into saved_id;
    if saved_id is null then
      if exists (select 1 from public.ep_recipes where id = p_id and household_id = p_household) then
        return p_id;
      end if;
      raise exception 'Rezept konnte nicht angelegt werden' using errcode = '42501';
    end if;
  else
    update public.ep_recipes set
      title = draft.title,
      subtitle = draft.subtitle,
      source = draft.source,
      categories = draft.categories,
      tags = draft.tags,
      folder_id = draft.folder_id,
      diet = draft.diet,
      time_text = draft.time_text,
      time_min = draft.time_min,
      servings = draft.servings,
      servings_text = draft.servings_text,
      steps = draft.steps,
      tip = draft.tip,
      cookbook_id = draft.cookbook_id,
      cookbook_page = draft.cookbook_page,
      cookbook_link_confirmed = draft.cookbook_link_confirmed,
      image_url = draft.image_url,
      nutrition = case when p_recipe ? 'nutrition' then draft.nutrition else ep_recipes.nutrition end,
      nutrition_estimated = case when p_recipe ? 'nutrition_estimated' then draft.nutrition_estimated else ep_recipes.nutrition_estimated end,
      extra_meta = case when p_recipe ? 'extra_meta' then coalesce(draft.extra_meta, '{}'::jsonb) else ep_recipes.extra_meta end
    where id = p_id and household_id = p_household and updated_at = p_expected_updated_at
    returning id into saved_id;
    if saved_id is null then
      raise exception 'Rezept wurde inzwischen geändert oder ist nicht mehr verfügbar' using errcode = '40001';
    end if;
  end if;

  if p_ingredients is not null and p_ingredients <> 'null'::jsonb then
    delete from public.ep_recipe_ingredients where recipe_id = saved_id;
    insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text, aisle)
    select saved_id, (item.ordinality - 1)::int, nullif(item.value->>'group_name', ''), trim(item.value->>'name'),
           (item.value->>'amount')::numeric, nullif(item.value->>'unit', ''),
           nullif(item.value->>'amount_text', ''), nullif(item.value->>'aisle', '')
    from jsonb_array_elements(p_ingredients) with ordinality as item(value, ordinality);
  end if;
  return saved_id;
end;
$$;

revoke execute on function public.ep_save_recipe(uuid, uuid, timestamptz, jsonb, jsonb) from public, anon;
grant execute on function public.ep_save_recipe(uuid, uuid, timestamptz, jsonb, jsonb) to authenticated;
