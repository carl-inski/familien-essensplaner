-- Vorrat Stufe 1: „Ist noch da“. Ein Eintrag in ep_purchases kann auch heißen
-- „haben wir zu Hause“, ohne dass gekauft wurde – von der Liste aus bestätigt oder
-- unter Haushalt von Hand eingetragen. Für die Rechnung (lib/shopping.ts) zählt beides
-- gleich; die Quelle ist für die Anzeige und spätere Auswertungen da.

alter table public.ep_purchases add column if not exists source text not null default 'kauf'
  check (source in ('kauf', 'vorrat'));
