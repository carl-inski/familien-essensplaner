-- Realtime für viele Familien: Änderungen gehen als Broadcast an genau eine Familie.
--
-- Bisher hörten Web und iPhone mit `postgres_changes` ohne Filter auf ganze Tabellen.
-- Supabase prüft dann jede Änderung gegen die RLS jedes verbundenen Geräts – bei
-- 10.000 Nutzern wächst das quadratisch und DELETE-Ereignisse gehen sogar an alle.
-- Jetzt schickt ein Trigger pro Anweisung (nicht pro Zeile) eine kleine Nachricht
-- {table, op} an das private Thema `ep:household:<id>`. Die Geräte laden daraufhin
-- wie bisher selbst über die REST-API nach, Inhalte stehen nicht in der Nachricht.
--
-- Nur additiv: die Tabellen bleiben in der Publikation `supabase_realtime`, damit
-- ältere App-Versionen weiterlaufen, bis alle aktualisiert sind.

create or replace function public.ep_broadcast_household_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  hh uuid;
  q text;
begin
  q := case tg_argv[0]
    when 'member' then 'select distinct m.household_id from %I r join public.ep_members m on m.id = r.member_id'
    when 'session' then 'select distinct s.household_id from %I r join public.ep_decide_sessions s on s.id = r.session_id'
    else 'select distinct r.household_id from %I r'
  end;
  for hh in execute format(q, case when tg_op = 'DELETE' then 'old_rows' else 'new_rows' end) loop
    if hh is not null then
      perform realtime.send(
        jsonb_build_object('table', tg_table_name, 'op', tg_op),
        'change',
        'ep:household:' || hh::text,
        true
      );
    end if;
  end loop;
  return null;
exception when others then
  -- Realtime darf nie ein Speichern verhindern; die Geräte holen beim nächsten Fokus nach.
  raise warning 'ep_broadcast_household_change(%): %', tg_table_name, sqlerrm;
  return null;
end $$;

revoke execute on function public.ep_broadcast_household_change() from public, anon, authenticated;

do $$
declare
  t record;
begin
  for t in
    select * from (values
      ('ep_meal_plan', 'household_id'),
      ('ep_pantry', 'household_id'),
      ('ep_purchases', 'household_id'),
      ('ep_shopping_extra', 'household_id'),
      ('ep_cooking_history', 'household_id'),
      ('ep_decide_sessions', 'household_id'),
      ('ep_attendance', 'member'),
      ('ep_decide_players', 'session')
    ) as v(tbl, mode)
  loop
    execute format('drop trigger if exists ep_rt_ins on public.%I', t.tbl);
    execute format('drop trigger if exists ep_rt_upd on public.%I', t.tbl);
    execute format('drop trigger if exists ep_rt_del on public.%I', t.tbl);
    execute format('create trigger ep_rt_ins after insert on public.%I referencing new table as new_rows
                    for each statement execute function public.ep_broadcast_household_change(%L)', t.tbl, t.mode);
    execute format('create trigger ep_rt_upd after update on public.%I referencing new table as new_rows
                    for each statement execute function public.ep_broadcast_household_change(%L)', t.tbl, t.mode);
    execute format('create trigger ep_rt_del after delete on public.%I referencing old table as old_rows
                    for each statement execute function public.ep_broadcast_household_change(%L)', t.tbl, t.mode);
  end loop;
end $$;

-- Lesen darf ein Gerät nur das Thema seiner aktiven Familie. Die Richtlinie betrifft nur
-- Themen mit Präfix `ep:` und ändert nichts für andere Apps im selben Projekt.
drop policy if exists "ep household broadcast lesen" on realtime.messages;
create policy "ep household broadcast lesen" on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and (select realtime.topic()) like 'ep:household:%'
    and (select realtime.topic()) in (select 'ep:household:' || h::text from public.ep_my_household_ids() h)
  );
