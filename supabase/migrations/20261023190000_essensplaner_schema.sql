-- Familien-Essensplaner: Schema
-- Alle Objekte tragen das Präfix ep_, weil sie sich ein Supabase-Projekt mit anderen Apps teilen.

create extension if not exists pg_trgm with schema extensions;

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table public.ep_households (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  budget_week numeric,
  ai_monthly_budget_eur numeric
);

create table public.ep_members (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  name text not null,
  email text,
  user_id uuid references auth.users(id) on delete set null,
  role text not null default 'member' check (role in ('admin', 'member')),
  default_week jsonb not null default '{}'::jsonb,
  position int not null default 0
);
create unique index ep_members_user_household on public.ep_members (household_id, user_id) where user_id is not null;
create index ep_members_user on public.ep_members (user_id);
create index ep_members_email on public.ep_members (lower(email));

create table public.ep_cookbooks (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  title text not null,
  authors text[] not null default '{}',
  publisher text,
  year int,
  isbn text,
  cover_url text,
  notes text,
  unique (household_id, isbn)
);
create index ep_cookbooks_household on public.ep_cookbooks (household_id);

create table public.ep_recipes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  title text not null,
  subtitle text,
  source text,
  categories text[] not null default '{}',
  diet text check (diet in ('fleisch', 'fisch', 'vegetarisch')),
  time_text text,
  time_min int,
  servings int,
  servings_text text,
  steps text[] not null default '{}',
  tip text,
  nutrition jsonb,
  nutrition_estimated boolean not null default false,
  cookbook_id uuid references public.ep_cookbooks(id) on delete set null,
  cookbook_page int,
  cookbook_link_confirmed boolean not null default true,
  tags text[] not null default '{}',
  image_url text,
  variant_of uuid references public.ep_recipes(id) on delete set null,
  extra_meta jsonb not null default '{}'::jsonb,
  search tsvector,
  public_slug text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)
);
create index ep_recipes_household on public.ep_recipes (household_id);
create index ep_recipes_search on public.ep_recipes using gin (search);
create index ep_recipes_tags on public.ep_recipes using gin (tags);
create index ep_recipes_categories on public.ep_recipes using gin (categories);
create index ep_recipes_title_trgm on public.ep_recipes using gin (title extensions.gin_trgm_ops);
create index ep_recipes_cookbook on public.ep_recipes (cookbook_id);

create table public.ep_recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  recipe_id uuid not null references public.ep_recipes(id) on delete cascade,
  position int not null default 0,
  group_name text,
  name text not null,
  amount numeric,
  unit text,
  amount_text text,
  aisle text
);
create index ep_recipe_ingredients_recipe on public.ep_recipe_ingredients (recipe_id, position);

create table public.ep_attendance (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  member_id uuid not null references public.ep_members(id) on delete cascade,
  date date not null,
  meal text not null default 'abend' check (meal in ('fruehstueck', 'mittag', 'abend')),
  status text not null default 'da' check (status in ('da', 'weg')),
  guests int not null default 0 check (guests >= 0),
  unique (member_id, date, meal)
);
create index ep_attendance_date on public.ep_attendance (date);

create table public.ep_meal_plan (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  date date not null,
  meal text not null default 'abend' check (meal in ('fruehstueck', 'mittag', 'abend')),
  recipe_id uuid references public.ep_recipes(id) on delete set null,
  leftover_of uuid references public.ep_meal_plan(id) on delete set null,
  cook_id uuid references public.ep_members(id) on delete set null,
  cook2_id uuid references public.ep_members(id) on delete set null,
  servings_override int,
  status text not null default 'geplant' check (status in ('geplant', 'gekocht', 'ausgefallen')),
  note text,
  unique (household_id, date, meal)
);
create index ep_meal_plan_recipe on public.ep_meal_plan (recipe_id);
create index ep_meal_plan_leftover on public.ep_meal_plan (leftover_of);
create index ep_meal_plan_cook on public.ep_meal_plan (cook_id);
create index ep_meal_plan_cook2 on public.ep_meal_plan (cook2_id);

create table public.ep_cooking_history (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  recipe_id uuid not null references public.ep_recipes(id) on delete cascade,
  cooked_on date not null,
  meal_plan_id uuid unique references public.ep_meal_plan(id) on delete set null,
  cook_id uuid references public.ep_members(id) on delete set null,
  servings int,
  source text not null default 'manuell' check (source in ('plan', 'manuell', 'nachgetragen'))
);
create index ep_cooking_history_recipe on public.ep_cooking_history (recipe_id, cooked_on desc);
create index ep_cooking_history_household on public.ep_cooking_history (household_id, cooked_on desc);
create index ep_cooking_history_cook on public.ep_cooking_history (cook_id);

create table public.ep_suggestions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  iso_week text not null,
  recipe_id uuid references public.ep_recipes(id) on delete cascade,
  draft jsonb,
  origin text not null check (origin in ('sammlung', 'regal', 'neu')),
  generated_by text not null check (generated_by in ('regel', 'ki', 'samstag')),
  reason_shown text,
  status text not null default 'offen' check (status in ('offen', 'angenommen', 'abgelehnt')),
  reject_reason text
);
create index ep_suggestions_household on public.ep_suggestions (household_id, iso_week);
create index ep_suggestions_recipe on public.ep_suggestions (recipe_id);

create table public.ep_shopping_lists (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  iso_week text not null,
  public_slug text not null unique default substr(replace(gen_random_uuid()::text, '-', ''), 1, 16),
  items jsonb not null default '[]'::jsonb,
  exported_at timestamptz,
  unique (household_id, iso_week)
);

create table public.ep_ai_usage (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  member_id uuid references public.ep_members(id) on delete set null,
  feature text not null,
  model text,
  tokens_in int,
  tokens_out int,
  cost_eur numeric,
  cache_hit boolean not null default false
);
create index ep_ai_usage_household on public.ep_ai_usage (household_id, created_at desc);
create index ep_ai_usage_member on public.ep_ai_usage (member_id);

create table public.ep_ai_cache (
  key text primary key,
  created_at timestamptz not null default now(),
  result jsonb not null,
  expires_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen für RLS
-- ---------------------------------------------------------------------------

create or replace function public.ep_my_household_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select household_id from public.ep_members where user_id = (select auth.uid())
$$;

create or replace function public.ep_is_admin(hh uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.ep_members
    where household_id = hh and user_id = (select auth.uid()) and role = 'admin'
  )
$$;

-- Effektiver Anwesenheitsstatus: Eintrag > Standardwoche > 'da'
create or replace function public.ep_member_status(p_member uuid, p_date date, p_meal text)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select a.status from public.ep_attendance a
      where a.member_id = p_member and a.date = p_date and a.meal = p_meal),
    (select m.default_week -> (array['mon','tue','wed','thu','fri','sat','sun'])[extract(isodow from p_date)::int] ->> p_meal
      from public.ep_members m where m.id = p_member),
    'da'
  )
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.ep_households enable row level security;
alter table public.ep_members enable row level security;
alter table public.ep_cookbooks enable row level security;
alter table public.ep_recipes enable row level security;
alter table public.ep_recipe_ingredients enable row level security;
alter table public.ep_attendance enable row level security;
alter table public.ep_meal_plan enable row level security;
alter table public.ep_cooking_history enable row level security;
alter table public.ep_suggestions enable row level security;
alter table public.ep_shopping_lists enable row level security;
alter table public.ep_ai_usage enable row level security;
alter table public.ep_ai_cache enable row level security;

create policy ep_households_select on public.ep_households for select to authenticated
  using (id in (select public.ep_my_household_ids()));
create policy ep_households_update on public.ep_households for update to authenticated
  using (public.ep_is_admin(id)) with check (public.ep_is_admin(id));

create policy ep_members_select on public.ep_members for select to authenticated
  using (household_id in (select public.ep_my_household_ids()));
-- Jedes Mitglied darf Mitglieder seines Haushalts bearbeiten (Standardwoche etc.);
-- Rollen und E-Mails schützt der Trigger ep_members_guard.
create policy ep_members_update on public.ep_members for update to authenticated
  using (household_id in (select public.ep_my_household_ids()))
  with check (household_id in (select public.ep_my_household_ids()));
create policy ep_members_insert on public.ep_members for insert to authenticated
  with check (public.ep_is_admin(household_id));
create policy ep_members_delete on public.ep_members for delete to authenticated
  using (public.ep_is_admin(household_id));

do $$
declare t text;
begin
  foreach t in array array['ep_cookbooks','ep_recipes','ep_meal_plan','ep_cooking_history','ep_suggestions','ep_shopping_lists'] loop
    execute format($f$
      create policy %1$s_all on public.%1$s for all to authenticated
        using (household_id in (select public.ep_my_household_ids()))
        with check (household_id in (select public.ep_my_household_ids()))
    $f$, t);
  end loop;
end $$;

create policy ep_ai_usage_select on public.ep_ai_usage for select to authenticated
  using (household_id in (select public.ep_my_household_ids()));
create policy ep_ai_usage_insert on public.ep_ai_usage for insert to authenticated
  with check (household_id in (select public.ep_my_household_ids()));
-- ep_ai_cache: kein Client-Zugriff (nur serverseitig)

create policy ep_recipe_ingredients_all on public.ep_recipe_ingredients for all to authenticated
  using (exists (select 1 from public.ep_recipes r where r.id = recipe_id and r.household_id in (select public.ep_my_household_ids())))
  with check (exists (select 1 from public.ep_recipes r where r.id = recipe_id and r.household_id in (select public.ep_my_household_ids())));

create policy ep_attendance_all on public.ep_attendance for all to authenticated
  using (exists (select 1 from public.ep_members m where m.id = member_id and m.household_id in (select public.ep_my_household_ids())))
  with check (exists (select 1 from public.ep_members m where m.id = member_id and m.household_id in (select public.ep_my_household_ids())));

-- ---------------------------------------------------------------------------
-- Trigger
-- ---------------------------------------------------------------------------

-- Nur Admins ändern Rolle, E-Mail und Verknüpfung eines Mitglieds.
create or replace function public.ep_members_guard()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new; -- Service-/Migrationskontext
  end if;
  if (new.role is distinct from old.role or new.email is distinct from old.email or new.user_id is distinct from old.user_id)
     and not public.ep_is_admin(old.household_id) then
    raise exception 'Nur Admins dürfen Rolle, E-Mail oder Login eines Mitglieds ändern';
  end if;
  return new;
end $$;
create trigger ep_members_guard before update on public.ep_members
  for each row execute function public.ep_members_guard();

-- Suchvektor: Titel, Untertitel, Kategorien, Tags und Zutaten
create or replace function public.ep_refresh_recipe_search(p_recipe uuid)
returns void
language sql security definer set search_path = ''
as $$
  update public.ep_recipes r set search =
    setweight(to_tsvector('german', coalesce(r.title, '')), 'A') ||
    setweight(to_tsvector('german', coalesce(r.subtitle, '')), 'B') ||
    setweight(to_tsvector('german', array_to_string(r.categories || r.tags, ' ')), 'B') ||
    setweight(to_tsvector('german', coalesce((
      select string_agg(i.name, ' ') from public.ep_recipe_ingredients i where i.recipe_id = r.id
    ), '')), 'C')
  where r.id = p_recipe
$$;

create or replace function public.ep_recipes_search_trigger()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.updated_at := now();
  new.search :=
    setweight(to_tsvector('german', coalesce(new.title, '')), 'A') ||
    setweight(to_tsvector('german', coalesce(new.subtitle, '')), 'B') ||
    setweight(to_tsvector('german', array_to_string(new.categories || new.tags, ' ')), 'B') ||
    setweight(to_tsvector('german', coalesce((
      select string_agg(i.name, ' ') from public.ep_recipe_ingredients i where i.recipe_id = new.id
    ), '')), 'C');
  return new;
end $$;
create trigger ep_recipes_search before insert or update of title, subtitle, categories, tags, steps, tip, servings, cookbook_id
  on public.ep_recipes for each row execute function public.ep_recipes_search_trigger();

create or replace function public.ep_ingredients_search_trigger()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.ep_refresh_recipe_search(old.recipe_id);
  else
    perform public.ep_refresh_recipe_search(new.recipe_id);
  end if;
  return null;
end $$;
create trigger ep_ingredients_search after insert or update or delete
  on public.ep_recipe_ingredients for each row execute function public.ep_ingredients_search_trigger();

-- Kochdienst: nur anwesende Personen
create or replace function public.ep_meal_plan_cook_check()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.cook_id is not null
     and (tg_op = 'INSERT' or new.cook_id is distinct from old.cook_id)
     and public.ep_member_status(new.cook_id, new.date, new.meal) = 'weg' then
    raise exception 'Abwesende Personen können nicht zum Kochen eingeteilt werden';
  end if;
  if new.cook2_id is not null
     and (tg_op = 'INSERT' or new.cook2_id is distinct from old.cook2_id)
     and public.ep_member_status(new.cook2_id, new.date, new.meal) = 'weg' then
    raise exception 'Abwesende Personen können nicht zum Kochen eingeteilt werden';
  end if;
  return new;
end $$;
create trigger ep_meal_plan_cook_check before insert or update on public.ep_meal_plan
  for each row execute function public.ep_meal_plan_cook_check();

-- Kochhistorie: gekocht ✓ legt Eintrag an, zurück auf geplant löscht ihn
create or replace function public.ep_meal_plan_history()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if new.status = 'gekocht' and (tg_op = 'INSERT' or old.status is distinct from 'gekocht')
     and new.recipe_id is not null and new.leftover_of is null then
    insert into public.ep_cooking_history (household_id, recipe_id, cooked_on, meal_plan_id, cook_id, servings, source)
    values (new.household_id, new.recipe_id, new.date, new.id, new.cook_id, new.servings_override, 'plan')
    on conflict (meal_plan_id) do update
      set recipe_id = excluded.recipe_id, cooked_on = excluded.cooked_on,
          cook_id = excluded.cook_id, servings = excluded.servings;
  elsif tg_op = 'UPDATE' and old.status = 'gekocht' and new.status is distinct from 'gekocht' then
    delete from public.ep_cooking_history where meal_plan_id = new.id;
  end if;
  return null;
end $$;
create trigger ep_meal_plan_history after insert or update of status on public.ep_meal_plan
  for each row execute function public.ep_meal_plan_history();

-- ---------------------------------------------------------------------------
-- View
-- ---------------------------------------------------------------------------

create or replace view public.ep_recipe_cook_stats
with (security_invoker = true)
as
  select recipe_id,
         max(cooked_on) as last_cooked_on,
         count(*)::int as times_cooked,
         (current_date - max(cooked_on))::int as days_since
  from public.ep_cooking_history
  group by recipe_id;

-- ---------------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------------

-- Verknüpft den eingeloggten Nutzer über seine E-Mail mit dem vorab angelegten Mitglied.
create or replace function public.ep_link_member()
returns setof public.ep_members
language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
        mail text := lower((select auth.jwt()) ->> 'email');
begin
  if uid is null or mail is null then
    return;
  end if;
  update public.ep_members set user_id = uid
    where user_id is null and lower(email) = mail;
  return query select * from public.ep_members where user_id = uid;
end $$;

-- Volltextsuche (deutsch) + Teilwort + Trigramm-Ähnlichkeit für Tippfehler
create or replace function public.ep_search_recipes(q text)
returns table (id uuid, rank real)
language sql stable security invoker set search_path = ''
as $$
  with term as (select trim(q) as t)
  select r.id,
         greatest(
           ts_rank(r.search, websearch_to_tsquery('german', (select t from term))),
           extensions.similarity(r.title, (select t from term))
         )::real as rank
  from public.ep_recipes r
  where r.household_id in (select public.ep_my_household_ids())
    and (
      r.search @@ websearch_to_tsquery('german', (select t from term))
      or r.title ilike '%' || (select t from term) || '%'
      or coalesce(r.subtitle, '') ilike '%' || (select t from term) || '%'
      or exists (select 1 from public.ep_recipe_ingredients i
                 where i.recipe_id = r.id and i.name ilike '%' || (select t from term) || '%')
      or extensions.word_similarity((select t from term), r.title) > 0.45
    )
  order by rank desc
$$;

-- Öffentliche Seiten (Bring!-Import): nur über den nicht erratbaren Slug
create or replace function public.ep_public_recipe(p_slug text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'title', r.title,
    'subtitle', r.subtitle,
    'servings', r.servings,
    'servings_text', r.servings_text,
    'time_text', r.time_text,
    'image_url', r.image_url,
    'steps', to_jsonb(r.steps),
    'ingredients', coalesce((
      select jsonb_agg(jsonb_build_object(
        'group_name', i.group_name, 'name', i.name, 'amount', i.amount,
        'unit', i.unit, 'amount_text', i.amount_text) order by i.position)
      from public.ep_recipe_ingredients i where i.recipe_id = r.id), '[]'::jsonb)
  )
  from public.ep_recipes r
  where r.public_slug = p_slug and length(p_slug) >= 12
$$;

create or replace function public.ep_public_shopping(p_slug text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('iso_week', s.iso_week, 'items', s.items, 'created_at', s.created_at)
  from public.ep_shopping_lists s
  where s.public_slug = p_slug and length(p_slug) >= 12
$$;

revoke execute on function public.ep_public_recipe(text) from public;
revoke execute on function public.ep_public_shopping(text) from public;
grant execute on function public.ep_public_recipe(text) to anon, authenticated;
grant execute on function public.ep_public_shopping(text) to anon, authenticated;
revoke execute on function public.ep_link_member() from public, anon;
grant execute on function public.ep_link_member() to authenticated;
revoke execute on function public.ep_search_recipes(text) from public, anon;
grant execute on function public.ep_search_recipes(text) to authenticated;
revoke execute on function public.ep_refresh_recipe_search(uuid) from public, anon, authenticated;
revoke execute on function public.ep_member_status(uuid, date, text) from public, anon;
grant execute on function public.ep_member_status(uuid, date, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table public.ep_attendance, public.ep_meal_plan, public.ep_suggestions, public.ep_cooking_history;

-- ---------------------------------------------------------------------------
-- Storage: Rezeptfotos, Kochbuch-Cover
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ep-images', 'ep-images', true, 10485760, array['image/jpeg','image/png','image/webp','image/heic','image/heif'])
on conflict (id) do nothing;

-- Pfad: <household_id>/<datei>
create policy ep_images_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'ep-images' and (storage.foldername(name))[1] in (select h::text from public.ep_my_household_ids() h));
create policy ep_images_update on storage.objects for update to authenticated
  using (bucket_id = 'ep-images' and (storage.foldername(name))[1] in (select h::text from public.ep_my_household_ids() h));
create policy ep_images_delete on storage.objects for delete to authenticated
  using (bucket_id = 'ep-images' and (storage.foldername(name))[1] in (select h::text from public.ep_my_household_ids() h));
