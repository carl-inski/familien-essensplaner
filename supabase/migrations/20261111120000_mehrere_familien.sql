-- Mehrere Familien: selbst registrieren, Familie anlegen, per Code beitreten, wechseln.
--
-- Grundidee: Ein Konto kann zu mehreren Familien gehören, sieht aber immer nur die
-- AKTIVE. ep_my_household_ids() liefert darum genau eine ID – so bleiben alle
-- bestehenden RLS-Policies und Abfragen (die ohne Haushalts-Filter arbeiten) richtig.

-- ---------------------------------------------------------------------------
-- Einladungscode je Familie
-- ---------------------------------------------------------------------------

-- 8 Zeichen ohne verwechselbare (0/O, 1/I/L): 31^8 ≈ 8,5 · 10^11 Möglichkeiten
create or replace function public.ep_new_invite_code()
returns text
language sql volatile set search_path = ''
as $$
  select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', 1 + floor(random() * 31)::int, 1), '')
  from generate_series(1, 8)
$$;

alter table public.ep_households add column if not exists invite_code text;
update public.ep_households set invite_code = public.ep_new_invite_code() where invite_code is null;
alter table public.ep_households alter column invite_code set default public.ep_new_invite_code();
alter table public.ep_households alter column invite_code set not null;
create unique index if not exists ep_households_invite_code on public.ep_households (invite_code);

-- ---------------------------------------------------------------------------
-- Aktive Familie je Konto
-- ---------------------------------------------------------------------------

create table if not exists public.ep_user_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active_household_id uuid references public.ep_households(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.ep_user_state enable row level security;
-- kein Client-Zugriff: gelesen und geschrieben wird nur über die RPCs unten

create or replace function public.ep_active_household()
returns uuid
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select s.active_household_id
       from public.ep_user_state s
       join public.ep_members m on m.household_id = s.active_household_id and m.user_id = s.user_id
      where s.user_id = (select auth.uid())),
    (select m.household_id from public.ep_members m
      where m.user_id = (select auth.uid())
      order by m.created_at, m.id limit 1)
  )
$$;

create or replace function public.ep_my_household_ids()
returns setof uuid
language sql stable security definer set search_path = ''
as $$
  select h from public.ep_active_household() h where h is not null
$$;

-- ---------------------------------------------------------------------------
-- Verknüpfen per E-Mail entfällt
-- ---------------------------------------------------------------------------
-- Bisher wurde ein neuer Login automatisch mit dem Mitglied gleicher E-Mail verknüpft.
-- Mit offener Registrierung könnte sich damit jeder mit einer fremden Adresse anmelden
-- und in deren Familie landen. Der Weg in eine Familie führt jetzt nur noch über den
-- Einladungscode (oder ein Konto, das ein Admin der Familie selbst angelegt hat).
create or replace function public.ep_link_member()
returns setof public.ep_members
language sql stable security definer set search_path = ''
as $$
  select * from public.ep_members
  where user_id = (select auth.uid()) and household_id = public.ep_active_household()
$$;

-- Der Guard erlaubte die Selbst-Verknüpfung per E-Mail – ebenfalls entfernt.
create or replace function public.ep_members_guard()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Service-/Migrationskontext und die RPCs unten (Anlegen, Beitreten, Verlassen)
  if (select auth.uid()) is null or coalesce(current_setting('ep.linking', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    -- Admins legen Plätze an, aber hängen kein fremdes Konto daran: das geht nur über Beitreten.
    new.user_id := null;
    return new;
  end if;
  if new.household_id is distinct from old.household_id then
    raise exception 'Mitglieder können nicht in eine andere Familie verschoben werden';
  end if;
  if (new.role is distinct from old.role or new.email is distinct from old.email or new.user_id is distinct from old.user_id)
     and not public.ep_is_admin(old.household_id) then
    raise exception 'Nur Admins dürfen Rolle, E-Mail oder Login eines Mitglieds ändern';
  end if;
  if new.user_id is distinct from old.user_id and new.user_id is not null then
    raise exception 'Ein Login wird über den Einladungscode verknüpft';
  end if;
  return new;
end $$;
drop trigger if exists ep_members_guard on public.ep_members;
create trigger ep_members_guard before insert or update on public.ep_members
  for each row execute function public.ep_members_guard();

-- ---------------------------------------------------------------------------
-- Admin setzt Passwort: nur für Konten, die die Familie selbst verwaltet
-- ---------------------------------------------------------------------------
-- Sonst könnte jeder, der eine Familie anlegt (und damit Admin ist), das Passwort
-- eines beliebigen fremden Kontos überschreiben.
-- Verwaltet = von dieser Funktion angelegt (app_metadata.ep_managed) und in keiner
-- anderen Familie Mitglied.

update auth.users u
   set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb) || '{"ep_managed": true}'::jsonb
 where exists (select 1 from public.ep_members m where m.user_id = u.id)
   and not coalesce((u.raw_app_meta_data ->> 'ep_managed')::boolean, false);

create or replace function public.ep_admin_set_password(p_member uuid, p_password text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.ep_members;
  uid uuid;
  mail text;
  managed boolean;
begin
  select * into m from public.ep_members where id = p_member;
  if m.id is null then
    raise exception 'Mitglied nicht gefunden';
  end if;
  if (select auth.uid()) is not null and not public.ep_is_admin(m.household_id) then
    raise exception 'Nur Admins dürfen Passwörter setzen';
  end if;
  if m.email is null or m.email = '' then
    raise exception 'Bitte zuerst eine E-Mail-Adresse eintragen';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'Das Passwort braucht mindestens 8 Zeichen';
  end if;
  mail := lower(m.email);

  uid := m.user_id;
  if uid is null then
    select id into uid from auth.users where lower(email) = mail limit 1;
    if uid is not null then
      raise exception 'Zu dieser E-Mail gibt es schon ein Konto. Gib der Person den Einladungscode – sie tritt damit selbst bei.';
    end if;
  else
    select coalesce((raw_app_meta_data ->> 'ep_managed')::boolean, false) into managed from auth.users where id = uid;
    if (select auth.uid()) is not null and (
         not coalesce(managed, false)
         or exists (select 1 from public.ep_members o where o.user_id = uid and o.household_id <> m.household_id)
       ) then
      raise exception 'Dieses Konto gehört der Person selbst. Sie ändert ihr Passwort unter „Mein Konto“.';
    end if;
  end if;

  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token
    ) values (
      '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', mail,
      extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"],"ep_managed":true}'::jsonb, jsonb_build_object('name', m.name), now(), now(),
      '', '', '', '', '', '', '', ''
    );
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, 'email',
            jsonb_build_object('sub', uid::text, 'email', mail, 'email_verified', true, 'phone_verified', false),
            now(), now(), now());
  else
    update auth.users
       set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = uid;
  end if;

  perform set_config('ep.linking', 'on', true);
  update public.ep_members set user_id = uid where id = m.id and user_id is distinct from uid;
  perform set_config('ep.linking', '', true);
end $$;

-- ---------------------------------------------------------------------------
-- RPCs: Familien anlegen, beitreten, wechseln, verlassen
-- ---------------------------------------------------------------------------

create or replace function public.ep_set_active(p_user uuid, p_household uuid)
returns void
language sql security definer set search_path = ''
as $$
  insert into public.ep_user_state (user_id, active_household_id) values (p_user, p_household)
  on conflict (user_id) do update set active_household_id = excluded.active_household_id, updated_at = now()
$$;

create or replace function public.ep_my_memberships()
returns table (member_id uuid, household_id uuid, household_name text, role text, member_count int, active boolean)
language sql stable security definer set search_path = ''
as $$
  select m.id, h.id, h.name, m.role,
         (select count(*)::int from public.ep_members x where x.household_id = h.id),
         h.id = public.ep_active_household()
  from public.ep_members m
  join public.ep_households h on h.id = m.household_id
  where m.user_id = (select auth.uid())
  order by m.created_at, m.id
$$;

create or replace function public.ep_create_household(p_name text, p_member_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  hh uuid;
  hname text := nullif(trim(p_name), '');
  mname text := nullif(trim(p_member_name), '');
begin
  if uid is null then raise exception 'Bitte melde dich an'; end if;
  if hname is null or length(hname) > 60 then raise exception 'Bitte einen Namen für die Familie eingeben (höchstens 60 Zeichen)'; end if;
  if mname is null or length(mname) > 40 then raise exception 'Bitte deinen Namen eingeben (höchstens 40 Zeichen)'; end if;
  if (select count(*) from public.ep_members where user_id = uid) >= 8 then
    raise exception 'Du bist schon in 8 Familien – mehr geht nicht';
  end if;
  insert into public.ep_households (name) values (hname) returning id into hh;
  perform set_config('ep.linking', 'on', true);
  insert into public.ep_members (household_id, name, email, user_id, role, position)
  values (hh, mname, lower((select auth.jwt()) ->> 'email'), uid, 'admin', 0);
  perform set_config('ep.linking', '', true);
  perform public.ep_set_active(uid, hh);
  return hh;
end $$;

-- Vorschau vor dem Beitreten: nur Name und Größe, nur mit gültigem Code
create or replace function public.ep_invite_preview(p_code text)
returns table (household_name text, member_count int, already_member boolean)
language sql stable security definer set search_path = ''
as $$
  select h.name,
         (select count(*)::int from public.ep_members x where x.household_id = h.id),
         exists (select 1 from public.ep_members x where x.household_id = h.id and x.user_id = (select auth.uid()))
  from public.ep_households h
  where (select auth.uid()) is not null
    and h.invite_code = upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$$;

create or replace function public.ep_join_household(p_code text, p_member_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  mail text := lower((select auth.jwt()) ->> 'email');
  code text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  hh uuid;
  existing uuid;
  mname text := nullif(trim(p_member_name), '');
begin
  if uid is null then raise exception 'Bitte melde dich an'; end if;
  select id into hh from public.ep_households where invite_code = code;
  if hh is null then
    perform pg_sleep(0.4); -- Ausprobieren von Codes bremsen
    raise exception 'Diesen Einladungscode gibt es nicht';
  end if;

  if exists (select 1 from public.ep_members where household_id = hh and user_id = uid) then
    perform public.ep_set_active(uid, hh);
    return hh;
  end if;
  if (select count(*) from public.ep_members where user_id = uid) >= 8 then
    raise exception 'Du bist schon in 8 Familien – mehr geht nicht';
  end if;

  perform set_config('ep.linking', 'on', true);
  -- Hat ein Admin die Person schon mit dieser E-Mail eingetragen, übernimmt sie diesen Platz
  select id into existing from public.ep_members
   where household_id = hh and user_id is null and mail is not null and lower(email) = mail
   order by created_at limit 1;
  if existing is not null then
    update public.ep_members set user_id = uid where id = existing;
  else
    if mname is null or length(mname) > 40 then raise exception 'Bitte deinen Namen eingeben (höchstens 40 Zeichen)'; end if;
    insert into public.ep_members (household_id, name, email, user_id, role, position)
    values (hh, mname, mail, uid, 'member', (select coalesce(max(x."position"), -1) + 1 from public.ep_members x where x.household_id = hh));
  end if;
  perform set_config('ep.linking', '', true);
  perform public.ep_set_active(uid, hh);
  return hh;
end $$;

create or replace function public.ep_switch_household(p_household uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null or not exists (select 1 from public.ep_members where household_id = p_household and user_id = uid) then
    raise exception 'Du gehörst nicht zu dieser Familie';
  end if;
  perform public.ep_set_active(uid, p_household);
end $$;

-- Verlassen: der Platz bleibt (Kochhistorie, Kochdienst), nur der Login wird gelöst.
create or replace function public.ep_leave_household(p_household uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  me public.ep_members;
begin
  select * into me from public.ep_members where household_id = p_household and user_id = uid;
  if me.id is null then raise exception 'Du gehörst nicht zu dieser Familie'; end if;
  if me.role = 'admin'
     and not exists (select 1 from public.ep_members where household_id = p_household and role = 'admin' and user_id is not null and id <> me.id)
     and exists (select 1 from public.ep_members where household_id = p_household and user_id is not null and id <> me.id) then
    raise exception 'Du bist der einzige Admin. Mach zuerst jemand anderen zum Admin.';
  end if;
  perform set_config('ep.linking', 'on', true);
  update public.ep_members set user_id = null, role = 'member' where id = me.id;
  perform set_config('ep.linking', '', true);
  update public.ep_user_state set active_household_id = null where user_id = uid and active_household_id = p_household;
end $$;

create or replace function public.ep_regenerate_invite(p_household uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare code text;
begin
  if not public.ep_is_admin(p_household) then raise exception 'Nur Admins dürfen den Code erneuern'; end if;
  update public.ep_households set invite_code = public.ep_new_invite_code() where id = p_household returning invite_code into code;
  return code;
end $$;

revoke execute on function public.ep_new_invite_code() from public, anon, authenticated;
revoke execute on function public.ep_set_active(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.ep_active_household() from public, anon;
grant execute on function public.ep_active_household() to authenticated;
revoke execute on function public.ep_my_household_ids() from public, anon;
grant execute on function public.ep_my_household_ids() to authenticated;
revoke execute on function public.ep_members_guard() from public, anon, authenticated;
revoke execute on function public.ep_link_member() from public, anon;
grant execute on function public.ep_link_member() to authenticated;
revoke execute on function public.ep_admin_set_password(uuid, text) from public, anon;
grant execute on function public.ep_admin_set_password(uuid, text) to authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'ep_my_memberships()', 'ep_create_household(text, text)', 'ep_invite_preview(text)',
    'ep_join_household(text, text)', 'ep_switch_household(uuid)', 'ep_leave_household(uuid)',
    'ep_regenerate_invite(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
