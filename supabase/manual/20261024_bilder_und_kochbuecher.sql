-- NICHT automatisch ausführen. Keine Migration.
-- Im Supabase-SQL-Editor manuell ausführen, nachdem das Schema schon steht
-- und die 19 Rezepte sowie 15 Kochbücher vorhanden sind.
--
-- Setzt Beispielbilder und geprüfte Buchangaben. Vorhandene eigene Fotos,
-- ISBN und Notizen bleiben erhalten. Schema, Policies und Grants bleiben unberührt.
-- Werte entsprechen lib/medien.ts.

begin;

-- Beispielbilder (nur wo noch kein Foto hinterlegt ist)
update public.ep_recipes set image_url = '/images/rezepte/spinatquiche.jpg' where title = 'Spinatquiche mit Feta' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/pasta-raeucherlachs.jpg' where title = 'Pasta Räucherlachs' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/teriyaki-haehnchen.jpg' where title = 'Teriyaki Hähnchen' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/pizza-rucola-schinken.jpg' where title = 'Pizza (Rucola & Schinken)' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/sommernudeln.jpg' where title = 'Sommernudeln (Caprese-Style)' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/cajun-chicken-pasta.jpg' where title = 'Cajun Chicken Pasta' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/buffalo-chicken-wraps.jpg' where title = 'Buffalo Chicken Wraps mit Ranch-Sauce' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/one-pot-raeucherlachs.jpg' where title = 'One-Pot Räucherlachs-Pasta (Jamie Oliver)' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/reisbandnudel-suppe.jpg' where title = 'Asiatische Reisbandnudel-Suppe' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/sommerrollen.jpg' where title = 'Sommerrollen (Vietnamesisch)' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/wraps-louisa.jpg' where title = 'Wraps Louisa' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/tomaten-gnocchi.jpg' where title = 'Tomaten-Gnocchi' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/chili-con-carne.jpg' where title = 'Chili con Carne' and image_url is null;
update public.ep_recipes set image_url = '/images/rezepte/honighaehnchen.jpg' where title = 'Honighähnchen' and image_url is null;

-- Kochbücher. Leere Felder werden gefüllt, gesetzte Werte nicht überschrieben.
-- Die Platzhalter-Notiz aus dem ersten Seed wird ersetzt, eigene Notizen bleiben.

update public.ep_cookbooks set
  authors = case when cardinality(authors) = 0 then array['Franco Benussi', 'Reinhardt Hess', 'Sabine Sälzer']::text[] else authors end,
  publisher = case when publisher is null or publisher = 'GU' then 'Gräfe und Unzer' else publisher end,
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Mehrere Ausgaben (unter anderem 2012 und 2025). ISBN deshalb leer gelassen.' else notes end
where title = 'Die echte italienische Küche';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-8310-2333-2'),
  publisher = coalesce(publisher, 'Dorling Kindersley'),
  year = coalesce(year, 2013),
  cover_url = coalesce(cover_url, 'https://covers.openlibrary.org/b/isbn/9783831023332-L.jpg'),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Jerusalem';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-86528-608-6'),
  authors = case when cardinality(authors) = 0 then array['Sigrid Krekel', 'Angela Francisca Endress']::text[] else authors end,
  publisher = coalesce(publisher, 'Umschau'),
  year = coalesce(year, 2009),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Schlau kochen';

update public.ep_cookbooks set
  authors = case when cardinality(authors) = 0 then array['Alfons Schuhbeck']::text[] else authors end,
  publisher = coalesce(publisher, 'Zabert Sandmann'),
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Mehrere Auflagen (unter anderem 1989, 1995, 2001). ISBN deshalb leer gelassen.' else notes end
where title = 'Das neue bayrische Kochbuch';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-8321-9476-5'),
  authors = case when cardinality(authors) = 0 or authors = array['Leon']::text[] then array['Jane Baxter', 'Henry Dimbleby']::text[] else authors end,
  publisher = coalesce(publisher, 'DuMont'),
  year = coalesce(year, 2014),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Leon Fast Food Vegetarisch';

update public.ep_cookbooks set
  authors = case when cardinality(authors) = 0 then array['Ruth Kreider-Stempfle', 'Bettina Frensemeier']::text[] else authors end,
  publisher = coalesce(publisher, 'Gerstenberg'),
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Zwei Ausgaben (2013 und 2022). ISBN deshalb leer gelassen.' else notes end
where title = 'Das große Buch vom Backen und Bauen';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-89910-010-5'),
  publisher = coalesce(publisher, 'Collection Rolf Heyne'),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Harry''s Bar Kochbuch';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-8338-2126-4'),
  publisher = coalesce(publisher, 'Gräfe und Unzer'),
  year = coalesce(year, 2010),
  cover_url = coalesce(cover_url, 'https://covers.openlibrary.org/b/isbn/9783833821264-L.jpg'),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Meine Klassiker';

update public.ep_cookbooks set
  authors = case when cardinality(authors) = 0 then array['Maria Hofmann', 'Helmut Lydtin']::text[] else authors end,
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Das Bayerische Kochbuch hat viele Auflagen mit eigenen ISBN. Deshalb leer gelassen.' else notes end
where title = 'Bayrisches Kochbuch';

update public.ep_cookbooks set
  authors = case when cardinality(authors) = 0 then array['Sam Stern', 'Susan Stern']::text[] else authors end,
  publisher = coalesce(publisher, 'Oetinger'),
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Zwei Ausgaben (2007 und 2014). ISBN deshalb leer gelassen.' else notes end
where title = 'Licence to Cook';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-8310-1965-6'),
  authors = case when cardinality(authors) = 0 then array['Annik Wecker']::text[] else authors end,
  publisher = coalesce(publisher, 'Dorling Kindersley'),
  year = coalesce(year, 2011),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Anniks göttliche Desserts';

update public.ep_cookbooks set
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Zwei verschiedene Bände (Shelf Love und Extra Good Things). ISBN deshalb leer gelassen.' else notes end
where title = 'Ottolenghi Test Kitchen';

update public.ep_cookbooks set
  notes = case when notes is null or notes = 'Autor/Verlag per ISBN ergänzen' then 'Englische Ausgabe und deutsche Ausgabe „Simple“ haben verschiedene ISBN. Deshalb leer gelassen.' else notes end
where title = 'Ottolenghi Simple';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-8310-4579-2'),
  publisher = coalesce(publisher, 'Dorling Kindersley'),
  year = coalesce(year, 2022),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'ONE';

update public.ep_cookbooks set
  isbn = coalesce(isbn, '978-3-95726-080-2'),
  publisher = coalesce(publisher, 'Covadonga'),
  year = coalesce(year, 2023),
  notes = case when notes = 'Autor/Verlag per ISBN ergänzen' then null else notes end
where title = 'Das neue Grand Tour Kochbuch';

commit;
