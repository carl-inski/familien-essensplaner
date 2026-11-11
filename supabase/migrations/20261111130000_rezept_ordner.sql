-- Rezepte in Ordnern: flache Ordner je Familie, ein Rezept liegt in höchstens einem.
-- Tags gibt es schon (ep_recipes.tags) – sie bleiben frei kombinierbar.

create table if not exists public.ep_recipe_folders (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 40),
  emoji text check (emoji is null or length(emoji) <= 8),
  position int not null default 0
);
create index if not exists ep_recipe_folders_household on public.ep_recipe_folders (household_id, position);
create unique index if not exists ep_recipe_folders_name on public.ep_recipe_folders (household_id, lower(name));

alter table public.ep_recipe_folders enable row level security;
create policy ep_recipe_folders_all on public.ep_recipe_folders for all to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));

alter table public.ep_recipes add column if not exists folder_id uuid references public.ep_recipe_folders(id) on delete set null;
create index if not exists ep_recipes_folder on public.ep_recipes (folder_id);

-- Ein Rezept liegt nur in einem Ordner der eigenen Familie
create or replace function public.ep_recipes_folder_check()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.folder_id is not null and not exists (
    select 1 from public.ep_recipe_folders f where f.id = new.folder_id and f.household_id = new.household_id
  ) then
    raise exception 'Der Ordner gehört nicht zu dieser Familie';
  end if;
  return new;
end $$;
create or replace trigger ep_recipes_folder_check before insert or update of folder_id, household_id on public.ep_recipes
  for each row execute function public.ep_recipes_folder_check();
revoke execute on function public.ep_recipes_folder_check() from public, anon, authenticated;
