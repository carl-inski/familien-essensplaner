-- Rezept-Schnittstelle für externe Assistenten (POST/GET /api/rezepte).
--
-- Entscheidung: security-definer-RPCs mit gehashtem Token statt eines
-- sb_secret-Schlüssels in Vercel. Die Datenbank teilt sich das Projekt mit
-- anderen Apps; ein Secret Key würde RLS für alle Tabellen umgehen. Diese
-- Funktionen lesen und schreiben dagegen nur Rezepte, Zutaten und Kochbücher
-- des Haushalts, dem der Token gehört – der Haushalt kommt nie vom Aufrufer.

create table public.ep_api_tokens (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  household_id uuid not null references public.ep_households(id) on delete cascade,
  label text not null,
  -- sha256 des Tokens als Hex; der Klartext wird nirgends gespeichert
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  last_used_at timestamptz
);
create index ep_api_tokens_household on public.ep_api_tokens (household_id);

-- Keine Policies: Zugriff nur über die Funktionen unten
alter table public.ep_api_tokens enable row level security;
revoke all on public.ep_api_tokens from anon, authenticated;

-- Token → Haushalt (oder null). Intern, nicht direkt aufrufbar.
create or replace function public.ep_api_household(p_token text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  hh uuid;
begin
  if p_token is null or length(p_token) < 32 then
    return null;
  end if;
  update public.ep_api_tokens
     set last_used_at = now()
   where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  returning household_id into hh;
  return hh;
end
$$;
revoke execute on function public.ep_api_household(text) from public, anon, authenticated;

-- Lesen: alle Rezepte (mit Zutaten) und Kochbücher des Token-Haushalts
create or replace function public.ep_api_snapshot(p_token text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  hh uuid := public.ep_api_household(p_token);
begin
  if hh is null then
    raise exception 'ungültiger Token' using errcode = '28000';
  end if;
  return jsonb_build_object(
    'recipes', coalesce((
      select jsonb_agg(
        (to_jsonb(r) - 'search') || jsonb_build_object('ep_recipe_ingredients', coalesce((
          select jsonb_agg(to_jsonb(i) order by i.position)
          from public.ep_recipe_ingredients i where i.recipe_id = r.id
        ), '[]'::jsonb))
        order by r.title)
      from public.ep_recipes r where r.household_id = hh
    ), '[]'::jsonb),
    'cookbooks', coalesce((
      select jsonb_agg(to_jsonb(c) order by c.title)
      from public.ep_cookbooks c where c.household_id = hh
    ), '[]'::jsonb)
  );
end
$$;

-- Schreiben: ein Rezept samt Zutaten atomar anlegen oder aktualisieren.
-- p_existing: id eines vorhandenen Rezepts (Modus „ueberschreiben“), sonst null.
-- p_cookbook_title: Buch, das (falls noch nicht vorhanden) angelegt wird.
create or replace function public.ep_api_save_recipe(
  p_token text,
  p_recipe jsonb,
  p_ingredients jsonb,
  p_existing uuid default null,
  p_cookbook_title text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  hh uuid := public.ep_api_household(p_token);
  cb uuid := nullif(p_recipe->>'cookbook_id', '')::uuid;
  rid uuid;
  arr_categories text[] := array(select jsonb_array_elements_text(coalesce(p_recipe->'categories', '[]'::jsonb)));
  arr_tags text[] := array(select jsonb_array_elements_text(coalesce(p_recipe->'tags', '[]'::jsonb)));
  arr_steps text[] := array(select jsonb_array_elements_text(coalesce(p_recipe->'steps', '[]'::jsonb)));
begin
  if hh is null then
    raise exception 'ungültiger Token' using errcode = '28000';
  end if;
  if coalesce(trim(p_recipe->>'title'), '') = '' then
    raise exception 'Titel fehlt' using errcode = '22023';
  end if;
  if cb is not null and not exists (select 1 from public.ep_cookbooks where id = cb and household_id = hh) then
    raise exception 'Kochbuch gehört nicht zum Haushalt' using errcode = '42501';
  end if;
  if p_cookbook_title is not null and trim(p_cookbook_title) <> '' then
    select id into cb from public.ep_cookbooks
     where household_id = hh and lower(title) = lower(trim(p_cookbook_title)) limit 1;
    if cb is null then
      insert into public.ep_cookbooks (household_id, title, notes)
      values (hh, trim(p_cookbook_title), 'Über API angelegt – zu bestätigen')
      returning id into cb;
    end if;
  end if;

  if p_existing is not null then
    update public.ep_recipes set
      title = p_recipe->>'title',
      subtitle = p_recipe->>'subtitle',
      source = p_recipe->>'source',
      categories = arr_categories,
      tags = arr_tags,
      diet = p_recipe->>'diet',
      time_text = p_recipe->>'time_text',
      time_min = (p_recipe->>'time_min')::int,
      servings = (p_recipe->>'servings')::int,
      servings_text = p_recipe->>'servings_text',
      steps = arr_steps,
      tip = p_recipe->>'tip',
      nutrition = nullif(p_recipe->'nutrition', 'null'::jsonb),
      extra_meta = nullif(p_recipe->'extra_meta', 'null'::jsonb),
      cookbook_id = cb,
      cookbook_page = case when cb is null then null else (p_recipe->>'cookbook_page')::int end,
      cookbook_link_confirmed = coalesce((p_recipe->>'cookbook_link_confirmed')::boolean, true),
      -- ein eigenes Foto bleibt, solange kein neues mitkommt
      image_url = coalesce(nullif(p_recipe->>'image_url', ''), image_url)
    where id = p_existing and household_id = hh
    returning id into rid;
    if rid is null then
      raise exception 'Rezept nicht gefunden' using errcode = 'P0002';
    end if;
  else
    insert into public.ep_recipes (
      household_id, title, subtitle, source, categories, tags, diet, time_text, time_min,
      servings, servings_text, steps, tip, nutrition, extra_meta,
      cookbook_id, cookbook_page, cookbook_link_confirmed, image_url
    ) values (
      hh, p_recipe->>'title', p_recipe->>'subtitle', p_recipe->>'source', arr_categories, arr_tags,
      p_recipe->>'diet', p_recipe->>'time_text', (p_recipe->>'time_min')::int,
      (p_recipe->>'servings')::int, p_recipe->>'servings_text', arr_steps, p_recipe->>'tip',
      nullif(p_recipe->'nutrition', 'null'::jsonb), nullif(p_recipe->'extra_meta', 'null'::jsonb),
      cb, case when cb is null then null else (p_recipe->>'cookbook_page')::int end,
      coalesce((p_recipe->>'cookbook_link_confirmed')::boolean, true),
      nullif(p_recipe->>'image_url', '')
    )
    returning id into rid;
  end if;

  -- Zutaten ersetzen (läuft in derselben Transaktion wie das Rezept)
  delete from public.ep_recipe_ingredients where recipe_id = rid;
  insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text)
  select rid,
         coalesce((x->>'position')::int, (ord - 1)::int),
         nullif(x->>'group_name', ''),
         x->>'name',
         nullif(x->>'amount', '')::numeric,
         nullif(x->>'unit', ''),
         nullif(x->>'amount_text', '')
    from jsonb_array_elements(coalesce(p_ingredients, '[]'::jsonb)) with ordinality as t(x, ord)
   where coalesce(trim(x->>'name'), '') <> '';

  return rid;
end
$$;

-- Aufrufbar mit dem öffentlichen Schlüssel; die Funktionen prüfen den Token selbst
revoke execute on function public.ep_api_snapshot(text) from public;
revoke execute on function public.ep_api_save_recipe(text, jsonb, jsonb, uuid, text) from public;
grant execute on function public.ep_api_snapshot(text) to anon, authenticated;
grant execute on function public.ep_api_save_recipe(text, jsonb, jsonb, uuid, text) to anon, authenticated;
