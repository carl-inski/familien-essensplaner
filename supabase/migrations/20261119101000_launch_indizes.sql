-- Fehlende Indizes auf Fremdschlüsseln. Ohne sie wird jedes Löschen eines Rezepts,
-- Mitglieds oder einer Familie zum Full Table Scan der abhängigen Tabelle – mit
-- 10.000 Nutzern spürbar. Nur additiv.

create index if not exists ep_recipes_variant_of on public.ep_recipes (variant_of) where variant_of is not null;
create index if not exists ep_decide_sessions_created_by on public.ep_decide_sessions (created_by);
create index if not exists ep_decide_sessions_winner on public.ep_decide_sessions (winner_recipe_id) where winner_recipe_id is not null;
create index if not exists ep_user_state_active on public.ep_user_state (active_household_id);

-- ep_knuspr_links existiert in Produktion, aber in keiner Migration hier (vom Supabase-Advisor gemeldet)
do $$
begin
  if to_regclass('public.ep_knuspr_links') is not null then
    create index if not exists ep_knuspr_links_member on public.ep_knuspr_links (member_id);
  end if;
end $$;

-- Einkauf und Woche lesen Gerichte einer Familie über einen Datumsbereich; der
-- Unique-Index (household_id, date, meal) deckt das bereits ab. Anwesenheit wird über
-- member_id + Datum gelesen: ebenfalls durch unique (member_id, date, meal) abgedeckt.
