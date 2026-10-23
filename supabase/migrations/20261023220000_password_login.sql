-- Login per E-Mail + Passwort, ohne E-Mail-Versand:
-- Admins legen für Mitglieder ein Konto mit Passwort an (oder setzen es neu).
-- Ohne JWT (SQL-Editor/Migration) ist der Aufruf zum Einrichten des ersten Admins erlaubt.

create or replace function public.ep_admin_set_password(p_member uuid, p_password text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.ep_members;
  uid uuid;
  mail text;
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
      '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name', m.name), now(), now(),
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

  update public.ep_members set user_id = uid where id = m.id and user_id is distinct from uid;
end $$;

revoke execute on function public.ep_admin_set_password(uuid, text) from public, anon;
grant execute on function public.ep_admin_set_password(uuid, text) to authenticated;
