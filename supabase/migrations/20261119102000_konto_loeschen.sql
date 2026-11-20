-- Konto löschen (DSGVO Art. 17, App-Store-Regel 5.1.1).
-- MENSCHLICHE PRÜFUNG NÖTIG: betrifft Familien (siehe CLAUDE.md).
--
-- Für jede Familie des Kontos:
--   * Gibt es dort noch andere Mitglieder mit Login, bleibt die Familie bestehen.
--     Der eigene Platz verliert Login und E-Mail (Name und Kochhistorie bleiben für die
--     Familie sichtbar, wie beim Verlassen). War man einziger Admin, wird das am längsten
--     dabei gewesene Mitglied mit Login Admin.
--   * Ist man das letzte Mitglied mit Login, wird die Familie mit allen Daten gelöscht.
-- Danach werden der Konto-Zustand und das Supabase-Konto selbst gelöscht.
-- Bilder im Storage (`ep-images/<haushalt>/…`) gelöschter Familien räumt ein Admin-Job
-- auf (siehe docs/LAUNCH.md); SQL soll storage.objects nicht direkt löschen.

create or replace function public.ep_delete_my_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  me public.ep_members;
  heir uuid;
begin
  if uid is null then raise exception 'Bitte melde dich an.'; end if;

  perform set_config('ep.linking', 'on', true);
  for me in select * from public.ep_members where user_id = uid loop
    if exists (select 1 from public.ep_members where household_id = me.household_id and user_id is not null and id <> me.id) then
      if me.role = 'admin' and not exists (
        select 1 from public.ep_members
        where household_id = me.household_id and role = 'admin' and user_id is not null and id <> me.id
      ) then
        select id into heir from public.ep_members
        where household_id = me.household_id and user_id is not null and id <> me.id
        order by created_at, id limit 1;
        update public.ep_members set role = 'admin' where id = heir;
      end if;
      update public.ep_members set user_id = null, role = 'member', email = null where id = me.id;
    else
      delete from public.ep_households where id = me.household_id;
    end if;
  end loop;
  perform set_config('ep.linking', '', true);

  delete from public.ep_user_state where user_id = uid;
  delete from auth.users where id = uid;
end $$;

revoke execute on function public.ep_delete_my_account() from public, anon;
grant execute on function public.ep_delete_my_account() to authenticated;
