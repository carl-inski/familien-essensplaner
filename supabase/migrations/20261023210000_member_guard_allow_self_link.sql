-- Beim ersten Login verknüpft ep_link_member() den Nutzer mit seinem vorab angelegten Mitglied.
-- Der Guard muss diese Selbst-Verknüpfung (user_id null → eigene uid, passende E-Mail) erlauben.
create or replace function public.ep_members_guard()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then
    return new; -- Service-/Migrationskontext
  end if;
  if old.user_id is null and new.user_id = uid
     and new.role is not distinct from old.role and new.email is not distinct from old.email
     and lower(new.email) = lower((select auth.jwt()) ->> 'email') then
    return new;
  end if;
  if (new.role is distinct from old.role or new.email is distinct from old.email or new.user_id is distinct from old.user_id)
     and not public.ep_is_admin(old.household_id) then
    raise exception 'Nur Admins dürfen Rolle, E-Mail oder Login eines Mitglieds ändern';
  end if;
  return new;
end $$;
