-- A new cookbook and the recipe pointing to it must be saved together.
create function public.ep_save_recipe_with_cookbook(
  p_id uuid,
  p_household uuid,
  p_expected_updated_at timestamptz,
  p_recipe jsonb,
  p_ingredients jsonb,
  p_book_title text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  title_key text := lower(trim(p_book_title));
  book_id uuid;
begin
  if p_id is null or p_household is null or coalesce(title_key, '') = '' then
    raise exception 'Rezept, Familie oder Kochbuchtitel fehlt' using errcode = '22023';
  end if;

  -- Concurrent imports of the same title in one household share a book.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_household::text || '/' || title_key, 0));

  if p_expected_updated_at is null and exists (
    select 1 from public.ep_recipes where id = p_id and household_id = p_household
  ) then
    return p_id;
  end if;

  select id into book_id from public.ep_cookbooks
  where household_id = p_household and lower(trim(title)) = title_key
  order by id limit 1;

  if book_id is null then
    insert into public.ep_cookbooks (household_id, title, notes)
    values (p_household, trim(p_book_title), 'Beim Import angelegt – zu bestätigen')
    returning id into book_id;
  end if;

  return public.ep_save_recipe(p_id, p_household, p_expected_updated_at,
    pg_catalog.jsonb_set(p_recipe, '{cookbook_id}', pg_catalog.to_jsonb(book_id)), p_ingredients);
end;
$$;

revoke execute on function public.ep_save_recipe_with_cookbook(uuid, uuid, timestamptz, jsonb, jsonb, text) from public, anon;
grant execute on function public.ep_save_recipe_with_cookbook(uuid, uuid, timestamptz, jsonb, jsonb, text) to authenticated;
