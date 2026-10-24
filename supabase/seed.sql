-- Generiert von scripts/seed.ts – nicht von Hand bearbeiten.
begin;

insert into public.ep_households (name) values ('Familie Dobmeier');

insert into public.ep_members (household_id, name, role, position) select id, 'Carl', 'admin', 0 from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_members (household_id, name, role, position) select id, 'Paul', 'member', 1 from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_members (household_id, name, role, position) select id, 'Anton', 'member', 2 from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_members (household_id, name, role, position) select id, 'Vroni', 'member', 3 from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_members (household_id, name, role, position) select id, 'Christian', 'member', 4 from public.ep_households where name = 'Familie Dobmeier';

insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Die echte italienische Küche', array['Franco Benussi', 'Reinhardt Hess', 'Sabine Sälzer']::text[], 'Gräfe und Unzer', null, null, '/images/kochbuecher/die-echte-italienische-kueche.jpg', 'Cover: Gräfe und Unzer, Ausgabe 2025. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Jerusalem', array['Yotam Ottolenghi', 'Sami Tamimi']::text[], 'Dorling Kindersley', 2013, '978-3-8310-2333-2', '/images/kochbuecher/jerusalem.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Schlau kochen', array['Sigrid Krekel', 'Angela Francisca Endress']::text[], 'Umschau', 2009, '978-3-86528-608-6', '/images/kochbuecher/schlau-kochen.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Das neue bayrische Kochbuch', array['Alfons Schuhbeck']::text[], 'Zabert Sandmann', null, null, '/images/kochbuecher/das-neue-bayrische-kochbuch.jpg', 'Cover: Zabert Sandmann, jüngste Ausgabe 2001. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Leon Fast Food Vegetarisch', array['Jane Baxter', 'Henry Dimbleby']::text[], 'DuMont', 2014, '978-3-8321-9476-5', '/images/kochbuecher/leon-fast-food-vegetarisch.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Das große Buch vom Backen und Bauen', array['Ruth Kreider-Stempfle', 'Bettina Frensemeier']::text[], 'Gerstenberg', null, null, '/images/kochbuecher/backen-und-bauen.jpg', 'Cover: Gerstenberg, Ausgabe 2022. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Harry''s Bar Kochbuch', array['Arrigo Cipriani']::text[], 'Collection Rolf Heyne', null, '978-3-89910-010-5', '/images/kochbuecher/harrys-bar.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Meine Klassiker', array['Alfons Schuhbeck']::text[], 'Gräfe und Unzer', 2010, '978-3-8338-2126-4', '/images/kochbuecher/meine-klassiker.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Bayrisches Kochbuch', array['Maria Hofmann', 'Helmut Lydtin']::text[], null, null, null, '/images/kochbuecher/bayerisches-kochbuch.jpg', 'Cover der langen Standardausgabe (Verlagsseite). DNB nennt 2026 den Verlag Friedrich Pustet. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Licence to Cook', array['Sam Stern', 'Susan Stern']::text[], 'Oetinger', null, null, '/images/kochbuecher/licence-to-cook.jpg', 'Cover: Oetinger, Ausgabe 2014. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Anniks göttliche Desserts', array['Annik Wecker']::text[], 'Dorling Kindersley', 2011, '978-3-8310-1965-6', '/images/kochbuecher/anniks-goettliche-desserts.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Ottolenghi Test Kitchen', array['Yotam Ottolenghi', 'Noor Murad']::text[], 'Dorling Kindersley', null, null, '/images/kochbuecher/ottolenghi-test-kitchen.jpg', 'Cover: deutsche Ausgabe „OTK – Extra Good Things“, DK 2022, nicht Shelf Love von 2021. ISBN bleibt leer, bis der Band bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Ottolenghi Simple', array['Yotam Ottolenghi']::text[], 'Dorling Kindersley', null, null, '/images/kochbuecher/ottolenghi-simple.jpg', 'Cover: deutsche Ausgabe „Ottolenghi Simple“, DK 2023, nicht „Simple Too“ von 2026. ISBN bleibt leer, bis die Ausgabe bestätigt ist.' from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'ONE', array['Jamie Oliver']::text[], 'Dorling Kindersley', 2022, '978-3-8310-4579-2', '/images/kochbuecher/jamie-oliver-one.jpg', null from public.ep_households where name = 'Familie Dobmeier';
insert into public.ep_cookbooks (household_id, title, authors, publisher, year, isbn, cover_url, notes) select id, 'Das neue Grand Tour Kochbuch', array['Hannah Grant']::text[], 'Covadonga', 2023, '978-3-95726-080-2', '/images/kochbuecher/grand-tour.jpg', null from public.ep_households where name = 'Familie Dobmeier';

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Spinatquiche mit Feta', null, '[https://www.einfachbacken.de/rezepte/spinatquiche-mit-feta-herzhaft-und-lecker](https://www.einfachbacken.de/rezepte/spinatquiche-mit-feta-herzhaft-und-lecker)', array['Herzhaft', 'Vegetarisch']::text[], array['herzhaft', 'vegetarisch']::text[], 'vegetarisch', 'Backzeit: 35–40 Min bei 180°C', 40, 4, '4', array['Backofen auf 180°C vorheizen.', 'Mürbeteig in eine Quicheform legen, mit Gabel einstechen, ggf. 10 Min. vorbacken.', 'Zwiebel und Knoblauch würfeln und in Butter glasig dünsten.', 'Spinat auftauen, gut ausdrücken und mit Zwiebeln/Knoblauch mischen.', 'Feta würfeln und unter die Spinatmasse heben.', 'Eier, Schmand und Sahne verquirlen, mit Salz, Pfeffer und Muskat würzen.', 'Spinat-Feta-Mischung auf dem Teig verteilen, Guss darübergießen, geriebenen Käse bestreuen.', '35–40 Min. auf unterster Schiene backen bis der Guss gestockt ist.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/spinatquiche.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Mürbeteig', 1::numeric, null, '1 (fertig, für Quiche)'),
  (1, null, 'Spinat (TK, gehackt)', 450::numeric, 'g', '450 g'),
  (2, null, 'Feta', 200::numeric, 'g', '200 g'),
  (3, null, 'Eier', 3::numeric, null, '3'),
  (4, null, 'Schmand', 200::numeric, 'g', '200 g'),
  (5, null, 'Sahne', 100::numeric, 'ml', '100 ml'),
  (6, null, 'Zwiebel', 1::numeric, null, '1'),
  (7, null, 'Knoblauch', 2::numeric, 'Zehen', '2 Zehen'),
  (8, null, 'Käse (gerieben)', 50::numeric, 'g', '50 g'),
  (9, null, 'Muskat, Salz, Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Pasta Räucherlachs', null, null, array['Pasta', 'Fisch']::text[], array['pasta', 'fisch']::text[], 'fisch', null, null, 4, '4', array['Nudeln in Salzwasser nach Packungsanleitung kochen, etwas Kochwasser aufheben.', 'Frühlingszwiebeln in Ringe schneiden, Spinat grob hacken, Lachs in Streifen schneiden.', 'Frühlingszwiebeln in Olivenöl 2–3 Min. dünsten, Spinat zugeben und zusammenfallen lassen.', 'Lachs dazugeben, kurz schwenken.', 'Nudeln abgießen und zur Pfanne geben.', 'Frischkäse und Parmesan unterrühren, mit Zitronensaft und -abrieb abschmecken.', 'Mit Salz und Pfeffer würzen, ggf. etwas Kochwasser zugeben.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/pasta-raeucherlachs.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Nudeln', 500::numeric, 'g', '500 g'),
  (1, null, 'Räucherlachs', 240::numeric, 'g', '240 g'),
  (2, null, 'Babyspinat', 320::numeric, 'g', '320 g'),
  (3, null, 'Frühlingszwiebeln', 8::numeric, null, '8'),
  (4, null, 'Zitronen', 2::numeric, null, '2'),
  (5, null, 'Körniger Frischkäse', 4::numeric, 'EL', '4 EL'),
  (6, null, 'Parmesan (gerieben)', 20::numeric, 'g', '20 g'),
  (7, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Teriyaki Hähnchen', null, null, array['Geflügel', 'Asiatisch']::text[], array['geflügel', 'asiatisch']::text[], 'fleisch', null, null, 4, '4', array['Reis nach Packungsanleitung kochen.', 'Sojasauce, Mirin, Sake und Zucker in einer kleinen Schüssel verrühren.', 'Hähnchen in mundgerechte Stücke schneiden.', 'Zwiebeln in halbe Ringe, Knoblauch und Ingwer fein hacken.', 'Hähnchen in heißem Öl rundherum scharf anbraten, herausnehmen.', 'Zwiebeln, Knoblauch und Ingwer im gleichen Öl 2–3 Min. dünsten.', 'Hähnchen zurück in die Pfanne, Teriyaki-Sauce dazugießen.', 'Ca. 5 Min. köcheln, bis die Sauce einreduziert und das Hähnchen glasiert ist.', 'Mit Frühlingszwiebelringen, Sesam und Reis servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/teriyaki-haehnchen.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Hähnchenbrust oder -schenkel', 400::numeric, 'g', '400 g'),
  (1, null, 'Zwiebeln', 2::numeric, null, '2'),
  (2, null, 'Knoblauch', 2::numeric, 'Zehen', '2 Zehen'),
  (3, null, 'Ingwer (frisch)', 20::numeric, 'g', '20 g'),
  (4, null, 'Frühlingszwiebeln', 4::numeric, null, '4'),
  (5, 'Teriyaki-Sauce', 'Sojasauce', 75::numeric, 'ml', '75 ml'),
  (6, 'Teriyaki-Sauce', 'Mirin', 50::numeric, 'ml', '50 ml'),
  (7, 'Teriyaki-Sauce', 'Sake oder trockener Sherry', 2::numeric, 'EL', '2 EL'),
  (8, 'Teriyaki-Sauce', 'Zucker', 1::numeric, 'EL', '1 EL'),
  (9, 'Teriyaki-Sauce', 'Sesamöl', 1::numeric, 'TL', '1 TL'),
  (10, 'Teriyaki-Sauce', 'Sesamsamen zum Garnieren', null::numeric, null, 'nach Belieben'),
  (11, 'Teriyaki-Sauce', 'Basmatireis', 300::numeric, 'g', '300 g')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Shakshuka mit Kichererbsen & Kokosmilch', null, null, array['Vegetarisch', 'Eier']::text[], array['vegetarisch', 'eier']::text[], 'vegetarisch', null, null, 4, '4', array['Cashewkerne in einer trockenen Pfanne kurz rösten, beiseitestellen.', 'Frühlingszwiebeln in Ringe schneiden (etwas Grün aufheben).', 'Olivenöl erhitzen, Frühlingszwiebeln (das Weiße) 2 Min. dünsten.', 'Currypaste zugeben und 1 Min. anrösten.', 'Kichererbsen und Kokosmilch dazugeben, aufkochen und 5 Min. köcheln lassen.', 'Babyspinat unterrühren und zusammenfallen lassen.', '4 Mulden in die Masse drücken, jeweils ein Ei hineingeben.', 'Deckel drauf, 8–10 Min. bei mittlerer Hitze stocken lassen.', 'Mit Joghurt, Cashews und Frühlingszwiebelgrün servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/shakshuka.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Eier', 4::numeric, null, '4'),
  (1, null, 'Kichererbsen (Dose, abgetropft)', 400::numeric, 'g', '400 g'),
  (2, null, 'Kokosmilch', 400::numeric, 'ml', '400 ml'),
  (3, null, 'Babyspinat', 150::numeric, 'g', '150 g'),
  (4, null, 'Rote Currypaste', 3::numeric, 'EL', '2–3 EL'),
  (5, null, 'Frühlingszwiebeln', 4::numeric, null, '4'),
  (6, null, 'Cashewkerne', 30::numeric, 'g', '30 g'),
  (7, null, 'Joghurt', 4::numeric, 'EL', '4 EL'),
  (8, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack'),
  (9, null, 'Olivenöl', 2::numeric, 'EL', '2 EL'),
  (10, null, 'Brot zum Servieren', null::numeric, null, 'nach Belieben')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Pizza (Rucola & Schinken)', null, null, array['Pizza', 'Herzhaft']::text[], array['pizza', 'herzhaft']::text[], 'fleisch', null, null, 4, '4 (2 Pizzen)', array['Hefe im lauwarmen Wasser auflösen. Mehl, Salz, Olivenöl und Hefewasser zu einem glatten Teig verkneten.', 'Teig ca. 1 Std. abgedeckt gehen lassen bis er sich verdoppelt hat.', 'Backofen auf 250°C (Ober-/Unterhitze) vorheizen.', 'Passierte Tomaten mit Olivenöl, Knoblauch und Oregano würzen.', 'Teig halbieren und auf Backpapier dünn ausrollen.', 'Tomatensauce auftragen, Mozzarella zupfen und verteilen, Zwiebel in Ringe und Kirschtomaten halbieren, darauf verteilen.', '10–12 Min. backen bis der Rand goldbraun ist.', 'Frisch aus dem Ofen mit Schinken und Rucola belegen.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/pizza-rucola-schinken.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, 'Teig', 'Mehl (Typ 00 oder 405)', 500::numeric, 'g', '500 g'),
  (1, 'Teig', 'Trockenhefe', 7::numeric, 'g', '7g'),
  (2, 'Teig', 'Wasser (lauwarm)', 300::numeric, 'ml', '300 ml'),
  (3, 'Teig', 'Salz', 10::numeric, 'g', '10 g'),
  (4, 'Teig', 'Olivenöl', 2::numeric, 'EL', '2 EL'),
  (5, 'Belag', 'Mozzarella', 2::numeric, 'Kugeln', '2 Kugeln (à 125 g)'),
  (6, 'Belag', 'Kirschtomaten', 200::numeric, 'g', '200 g'),
  (7, 'Belag', 'Rucola', 80::numeric, 'g', '80 g'),
  (8, 'Belag', 'Schinken (gekocht oder Parmaschinken)', 150::numeric, 'g', '150 g'),
  (9, 'Belag', 'Zwiebel', 1::numeric, null, '1'),
  (10, 'Belag', 'Passierte Tomaten (für Tomatensauce)', 200::numeric, 'ml', '200 ml'),
  (11, 'Belag', 'Knoblauch, Oregano, Olivenöl', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Sommernudeln (Caprese-Style)', null, null, array['Pasta', 'Vegetarisch', 'Schnell']::text[], array['pasta', 'vegetarisch', 'schnell']::text[], 'vegetarisch', null, null, 4, '4', array['Nudeln in Salzwasser al dente kochen, abgießen und lauwarm abkühlen lassen.', 'Tomaten würfeln, Mozzarella in Stücke zupfen, Basilikumblätter grob hacken.', 'Knoblauch sehr fein hacken oder reiben.', 'Tomaten, Mozzarella und Basilikum mit Olivenöl und Balsamico marinieren.', 'Alles mit den Nudeln vermengen, abschmecken und servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/sommernudeln.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Nudeln (z.B. Penne oder Farfalle)', 400::numeric, 'g', '400 g'),
  (1, null, 'Mozzarella', 2::numeric, 'Kugeln', '2 Kugeln (à 125 g)'),
  (2, null, 'Tomaten (reif)', 4::numeric, null, '4 mittelgroße'),
  (3, null, 'Basilikum (frisch)', 1::numeric, 'Bund', '1 Bund'),
  (4, null, 'Olivenöl (extra vergine)', 4::numeric, 'EL', '4 EL'),
  (5, null, 'Balsamico (optional)', 1::numeric, 'EL', '1 EL'),
  (6, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack'),
  (7, null, 'Knoblauch (optional)', 1::numeric, 'Zehen', '1 Zehe')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Cajun Chicken Pasta', null, null, array['Pasta', 'Geflügel', 'Würzig']::text[], array['pasta', 'geflügel', 'würzig']::text[], 'fleisch', null, null, 4, '4', array['Alle Zutaten der Cajun-Gewürzmischung vermengen.', 'Hähnchen mit der Gewürzmischung rundherum einreiben, 15–30 Min. marinieren.', 'Hähnchen in einer heißen Pfanne mit Öl scharf anbraten, herausnehmen und in Scheiben schneiden.', 'Zwiebel und Knoblauch würfeln, im gleichen Fett anschwitzen.', 'Tomaten würfeln, dazugeben und 5 Min. köcheln. Hühnerbrühe und Sahne zugießen.', 'Penne in Salzwasser al dente kochen.', 'Hähnchen-Scheiben zurück in die Sauce, Pasta abgießen und unterheben.', 'Mit Parmesan und frischer Petersilie servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/cajun-chicken-pasta.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, 'Cajun-Gewürzmischung', 'Räucherpaprika', 1.5::numeric, 'EL', '1,5 EL'),
  (1, 'Cajun-Gewürzmischung', 'Zwiebelpulver', 1::numeric, 'TL', '1 TL'),
  (2, 'Cajun-Gewürzmischung', 'Knoblauchpulver', 1::numeric, 'TL', '1 TL'),
  (3, 'Cajun-Gewürzmischung', 'Getrockneter Oregano', 1::numeric, 'TL', '1 TL'),
  (4, 'Cajun-Gewürzmischung', 'Getrockneter Thymian', 1::numeric, 'TL', '1 TL'),
  (5, 'Cajun-Gewürzmischung', 'Rotes Chilipulver', 0.5::numeric, 'TL', '½ TL'),
  (6, 'Hähnchen & Pasta', 'Hähnchenschenkel (ohne Knochen und Haut)', 650::numeric, 'g', '650 g'),
  (7, 'Hähnchen & Pasta', 'Penne', 500::numeric, 'g', '500 g'),
  (8, 'Hähnchen & Pasta', 'Sahne', 165::numeric, 'ml', '165 ml'),
  (9, 'Hähnchen & Pasta', 'Tomaten', 500::numeric, 'g', '500 g'),
  (10, 'Hähnchen & Pasta', 'Hühnerbrühe', 200::numeric, 'ml', '200 ml'),
  (11, 'Hähnchen & Pasta', 'Zwiebel', 1::numeric, null, '1'),
  (12, 'Hähnchen & Pasta', 'Knoblauch', 2::numeric, 'Zehen', '2 Zehen'),
  (13, 'Hähnchen & Pasta', 'Parmesan (gerieben)', null::numeric, null, 'nach Geschmack'),
  (14, 'Hähnchen & Pasta', 'Petersilie (frisch, optional)', null::numeric, null, 'nach Belieben')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Buffalo Chicken Wraps mit Ranch-Sauce', null, '[https://www.youtube.com/watch?v=pWoo0G-CBV4](https://www.youtube.com/watch?v=pWoo0G-CBV4)', array['Wraps', 'Geflügel']::text[], array['wraps', 'geflügel']::text[], 'fleisch', null, null, 4, '4', array['Ranch-Sauce: Ei, Essig und Senf mit dem Stabmixer mixen, langsam Öl einrühren bis eine Mayonnaise entsteht. Saure Sahne, Buttermilch und alle Gewürze einrühren, kalt stellen.', 'Hähnchen: Mit Gewürzen und Öl einreiben. In einer Pfanne oder im Ofen (200°C, 25 Min.) garen.', 'Gegartes Hähnchen mit Hot Sauce schwenken.', 'Tortillas erwärmen, Ranch-Sauce darauf verteilen.', 'Salat, Hähnchen, Avocado-Scheiben und Cheddar darauf verteilen, einrollen.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/buffalo-chicken-wraps.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, 'Hähnchen', 'Hähnchenschenkel (ohne Knochen/Haut)', 480::numeric, 'g', '480 g'),
  (1, 'Hähnchen', 'Olivenöl', 1::numeric, 'TL', '1 TL'),
  (2, 'Hähnchen', 'Zwiebelpulver', 1::numeric, 'TL', '1 TL'),
  (3, 'Hähnchen', 'Knoblauchpulver', 1::numeric, 'TL', '1 TL'),
  (4, 'Hähnchen', 'Paprikapulver', 0.75::numeric, 'TL', '¾ TL'),
  (5, 'Hähnchen', 'Frank''s Hot Sauce', 145::numeric, 'ml', '145 ml'),
  (6, 'Hähnchen', 'Große Tortillas', 4::numeric, null, '4'),
  (7, 'Ranch-Sauce', 'Ei', 1::numeric, null, '1'),
  (8, 'Ranch-Sauce', 'Weißweinessig', 2::numeric, 'TL', '2 TL'),
  (9, 'Ranch-Sauce', 'Amerikanischer Senf', 0.75::numeric, 'TL', '¾ TL'),
  (10, 'Ranch-Sauce', 'Neutrales Öl', 80::numeric, 'ml', '80 ml'),
  (11, 'Ranch-Sauce', 'Saure Sahne', 2::numeric, 'EL', '2 EL'),
  (12, 'Ranch-Sauce', 'Buttermilch', 100::numeric, 'ml', '100 ml'),
  (13, 'Ranch-Sauce', 'Zwiebelpulver', 0.75::numeric, 'TL', '¾ TL'),
  (14, 'Ranch-Sauce', 'Knoblauchpulver', 0.75::numeric, 'TL', '¾ TL'),
  (15, 'Ranch-Sauce', 'Getrockneter Dill', 0.75::numeric, 'TL', '¾ TL'),
  (16, 'Ranch-Sauce', 'Getrocknete Petersilie', 0.75::numeric, 'TL', '¾ TL'),
  (17, 'Ranch-Sauce', 'Getrocknete Schnittlauchröllchen', 1::numeric, 'TL', '1 TL'),
  (18, 'Ranch-Sauce', 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack'),
  (19, 'Füllung', 'Cos- oder Römersalat', 0.5::numeric, 'Kopf', '½ Kopf'),
  (20, 'Füllung', 'Avocado', 1::numeric, null, '1'),
  (21, 'Füllung', 'Cheddar-Käse (gerieben)', 100::numeric, 'g', '100 g')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Kartoffelknödel mit Schweinegeschnetzeltem', null, null, array['Herzhaft', 'Deutsch']::text[], array['herzhaft', 'deutsch']::text[], 'fleisch', null, null, 4, '4', array['Knödel nach Packungsanleitung in Salzwasser garen.', 'Zwiebel würfeln und in Butter glasig dünsten.', 'Champignons in Scheiben schneiden, zugeben und anbraten bis sie Farbe annehmen.', 'Schweinegeschnetzeltes salzen, pfeffern und scharf anbraten.', 'Mit Wasser ablöschen, Sahne dazugeben und alles ca. 10 Min. köcheln lassen.', 'Sauce mit Salz und Pfeffer abschmecken.', 'Mit frischer Petersilie und Knödeln servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/kartoffelknoedel.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Schweinegeschnetzeltes / Schweinerücken', 400::numeric, 'g', '400 g'),
  (1, null, 'Champignons', 800::numeric, 'g', '800 g'),
  (2, null, 'Kloßteig (TK)', 2::numeric, 'Pck.', '2 Packungen'),
  (3, null, 'Sahne', 200::numeric, 'ml', '200 ml'),
  (4, null, 'Wasser', 400::numeric, 'ml', '400 ml'),
  (5, null, 'Zwiebel', 1::numeric, null, '1'),
  (6, null, 'Petersilie (frisch)', null::numeric, null, 'nach Belieben'),
  (7, null, 'TK-Beeren (optional, als Beilage)', null::numeric, null, 'nach Belieben'),
  (8, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'One-Pot Räucherlachs-Pasta (Jamie Oliver)', null, 'Jamie Oliver – ONE: Simple One-Pan Wonders', array['Pasta', 'Fisch', 'One-Pot']::text[], array['pasta', 'fisch', 'one-pot']::text[], 'fisch', 'Kochzeit: ca. 12 Min.', 12, 4, '4', array['Wasserkocher aufkochen.', 'Lasagneblätter der Länge nach halbieren, dann in ca. 2 cm breite Streifen schneiden (ergibt Tagliatelle-Form).', 'Frühlingszwiebeln trimmen und fein hacken. Spinat grob hacken. Die Hälfte des Lachses ebenfalls fein hacken.', 'Zitronenabrieb fein reiben, Parmesan separat reiben.', 'Eine große Pfanne (ca. 30 cm) auf hohe Hitze bringen. Olivenöl, Frühlingszwiebeln, Spinat, gehackten Lachs und Zitronenabrieb hineingeben.', 'Pasta in die Pfanne streuen, mit kochendem Wasser knapp bedecken (ca. 800–900 ml).', '4–5 Min. sprudelnd köcheln lassen bis die Pasta das Wasser aufgesogen hat, regelmäßig rühren. Bei Bedarf etwas mehr Wasser zugeben.', 'Hitze ausschalten. Zitronensaft, Hüttenkäse und Parmesan unterrühren, abschmecken.', 'Restlichen Lachs in Stücken darüberreißen, mit etwas Olivenöl beträufeln.']::text[], null, null, '{"lines":[]}'::jsonb, (select c.id from public.ep_cookbooks c where c.household_id = (select id from public.ep_households where name = 'Familie Dobmeier') and c.title = 'ONE'), null, true, '/images/rezepte/one-pot-raeucherlachs.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Frische Lasagneblätter (oder Penne)', 500::numeric, 'g', '500 g'),
  (1, null, 'Räucherlachs', 240::numeric, 'g', '240 g'),
  (2, null, 'Spinat (frisch)', 320::numeric, 'g', '320 g'),
  (3, null, 'Frühlingszwiebeln', 8::numeric, null, '8'),
  (4, null, 'Zitronen', 2::numeric, null, '2'),
  (5, null, 'Parmesan (gerieben)', 20::numeric, 'g', '20 g'),
  (6, null, 'Hüttenkäse', 4::numeric, 'EL', '4 EL'),
  (7, null, 'Olivenöl', null::numeric, null, 'nach Geschmack'),
  (8, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Ananascurry (nach Leon: Fast Vegetarian)', null, 'Leon – Fast Vegetarian Kochbuch', array['Vegetarisch', 'Curry']::text[], array['vegetarisch', 'curry']::text[], 'vegetarisch', null, null, 4, '4', array['Reis nach Packungsanleitung kochen.', 'Ananas schälen, Kernstreifen entfernen, in mundgerechte Stücke schneiden.', 'Zwiebeln würfeln, Knoblauch und Ingwer fein hacken.', 'Öl in einem Topf erhitzen, Zwiebeln darin goldbraun dünsten (ca. 5 Min.).', 'Knoblauch und Ingwer zugeben, 1 Min. mitdünsten.', 'Currypaste einrühren und 2 Min. anrösten.', 'Kichererbsen, Ananas und Kokosmilch dazugeben. Aufkochen, dann 10–15 Min. köcheln lassen.', 'Babyspinat unterrühren und kurz zusammenfallen lassen.', 'Mit Limettensaft und Salz abschmecken, mit Koriander garnieren.', 'Mit Basmatireis servieren.']::text[], null, null, '{"lines":[]}'::jsonb, (select c.id from public.ep_cookbooks c where c.household_id = (select id from public.ep_households where name = 'Familie Dobmeier') and c.title = 'Leon Fast Food Vegetarisch'), null, true, '/images/rezepte/ananascurry.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Frische Ananas (oder 500 g aus der Dose)', 1::numeric, null, '1 kleine'),
  (1, null, 'Kichererbsen (Dose, abgetropft)', 400::numeric, 'g', '400 g'),
  (2, null, 'Kokosmilch', 400::numeric, 'ml', '400 ml'),
  (3, null, 'Rote Currypaste', 3::numeric, 'EL', '2–3 EL'),
  (4, null, 'Zwiebeln', 2::numeric, null, '2'),
  (5, null, 'Knoblauch', 3::numeric, 'Zehen', '3 Zehen'),
  (6, null, 'Ingwer (frisch, gerieben)', 20::numeric, 'g', '20 g'),
  (7, null, 'Babyspinat', 100::numeric, 'g', '100 g'),
  (8, null, 'Limette', 1::numeric, null, '1'),
  (9, null, 'Frischer Koriander', 1::numeric, 'Bund', '1 Bund'),
  (10, null, 'Basmati-Reis', 300::numeric, 'g', '300 g'),
  (11, null, 'Kokosnussöl oder Olivenöl', 2::numeric, 'EL', '2 EL'),
  (12, null, 'Salz', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Asiatische Reisbandnudel-Suppe', null, null, array['Suppe', 'Asiatisch', 'Schnell']::text[], array['suppe', 'asiatisch', 'schnell']::text[], 'fleisch', null, null, 4, '4', array['Zwiebeln halbieren und zusammen mit dem Ingwer (in Scheiben) in einer trockenen Pfanne oder direkt im Topf scharf anrösten, bis sie Röstaromen entwickeln.', 'Rinderbrühe aufkochen, Zwiebeln, Ingwer und Zimt dazugeben. 15–20 Min. köcheln lassen.', 'Karotten schälen und in dünne Scheiben oder Julienne schneiden. Spitzpaprika in Streifen schneiden.', 'Karotten in der Brühe mitköcheln (ca. 5 Min.), Spitzpaprika die letzten 2–3 Min. dazugeben.', 'Brühe mit Sojasauce und Limettensaft abschmecken. Ingwer und Zwiebeln heraussieben.', 'Reisbandnudeln nach Packungsanleitung in heißem Wasser einweichen oder separat garen.', 'Nudeln in tiefe Schüsseln verteilen, heiße Brühe mit Gemüse darübergießen.', 'Mit Sprossen, Frühlingszwiebelringen, Koriander und Minze garnieren.', 'Mit Limettenspalten servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/reisbandnudel-suppe.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Reisbandnudeln', 400::numeric, 'g', '400 g'),
  (1, null, 'Rinderbrühe', 2.4::numeric, 'l', '2,4 l'),
  (2, null, 'Ingwer (frisch)', 4::numeric, 'cm', '4 cm'),
  (3, null, 'Zwiebel', 2::numeric, null, '2'),
  (4, null, 'Zimt', 2::numeric, 'TL', '2 TL'),
  (5, null, 'Sojasauce', 6::numeric, 'EL', '6 EL'),
  (6, null, 'Limette', 2::numeric, null, '2'),
  (7, null, 'Frühlingszwiebeln', 4::numeric, null, '4'),
  (8, null, 'Karotten', 2::numeric, null, '2'),
  (9, null, 'Spitzpaprika', 1::numeric, null, '1'),
  (10, null, 'Sprossen', 1::numeric, 'Handvoll', '1 Handvoll'),
  (11, null, 'Koriander (frisch)', 0.5::numeric, 'Bund', '½ Bund'),
  (12, null, 'Minze (frisch)', 0.5::numeric, 'Bund', '½ Bund')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Sommerrollen (Vietnamesisch)', null, null, array['Asiatisch', 'Leicht', 'Vegetarisch/Fleisch']::text[], array['asiatisch', 'leicht', 'vegetarischfleisch']::text[], 'fleisch', null, null, 4, '4 (ca. 12 Rollen)', array['Reisnudeln nach Packungsanleitung einweichen, abgießen und abkühlen lassen.', 'Karotten und Gurke in feine Julienne schneiden, Avocado in dünne Scheiben, Salat in Streifen.', 'Garnelen halbieren oder Hähnchen in dünne Streifen schneiden.', 'Für die Sauce alle Zutaten verrühren, abschmecken.', 'Lauwarmes Wasser in eine große flache Schüssel geben. Ein Reispapierblatt ca. 20 Sek. einweichen bis es biegsam ist.', 'Reispapier auf ein feuchtes Brett legen. Salat, Nudeln, Gemüse, Fleisch/Garnelen und Kräuter auf das untere Drittel legen (nicht zu viel!).', 'Unteren Rand einschlagen, Seiten einfalten, dann fest aufrollen.', 'Frisch mit der Dip-Sauce servieren.']::text[], 'Die fertigen Rollen nicht aufeinanderlegen – sie kleben zusammen. Am besten direkt nach dem Rollen servieren oder einzeln auf einem leicht geölten Teller lagern.', null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/sommerrollen.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Reispapierblätter (22 cm Ø)', 12::numeric, null, '12'),
  (1, null, 'Reisbandnudeln (dünn)', 100::numeric, 'g', '100 g'),
  (2, null, 'Garnelen (gekocht) oder Hähnchenbrust', 300::numeric, 'g', '300 g'),
  (3, null, 'Karotten', 2::numeric, null, '2'),
  (4, null, 'Gurke', 1::numeric, null, '1'),
  (5, null, 'Avocado', 1::numeric, null, '1'),
  (6, null, 'Eisbergsalat oder Butterlatich', 0.5::numeric, 'Kopf', '½ Kopf'),
  (7, null, 'Frische Minze', 0.5::numeric, 'Bund', '½ Bund'),
  (8, null, 'Frischer Koriander', 0.5::numeric, 'Bund', '½ Bund'),
  (9, null, 'Sprossen', 1::numeric, 'Handvoll', '1 Handvoll'),
  (10, 'Dip-Sauce', 'Sojasauce', 4::numeric, 'EL', '4 EL'),
  (11, 'Dip-Sauce', 'Limettensaft', 2::numeric, 'EL', '2 EL'),
  (12, 'Dip-Sauce', 'Sesamöl', 1::numeric, 'TL', '1 TL'),
  (13, 'Dip-Sauce', 'Knoblauch (fein gehackt)', 1::numeric, 'Zehen', '1 Zehe'),
  (14, 'Dip-Sauce', 'Zucker', 1::numeric, 'TL', '1 TL'),
  (15, 'Dip-Sauce', 'Chili (optional)', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Wraps Louisa', null, null, array['Wraps', 'Geflügel', 'Schnell']::text[], array['wraps', 'geflügel', 'schnell']::text[], 'fleisch', null, null, 4, '4', array['Hähnchen in Streifen schneiden, mit Paprikapulver, Salz, Pfeffer und etwas Olivenöl marinieren.', 'In einer heißen Pfanne goldbraun braten (ca. 6–8 Min.), beiseitelegen.', 'Gurke in dünne Scheiben hobeln, rote Zwiebeln in feine Ringe schneiden, Kapernäpfel halbieren.', 'Wraps leicht anwärmen (Pfanne oder Mikrowelle).', 'Crème fraîche, Guacamole und Süß-Sauer-Soße auf die Wraps streichen.', 'Rucola, Gurke, rote Zwiebeln und Kapernäpfel darauf verteilen.', 'Hähnchen draufgeben, einrollen und sofort servieren.']::text[], null, null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/wraps-louisa.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Tortilla-Wraps (groß)', 4::numeric, null, '4'),
  (1, null, 'Hähnchenbrust', 500::numeric, 'g', '500 g'),
  (2, null, 'Paprikapulver (zum Würzen)', 2::numeric, 'TL', '2 TL'),
  (3, null, 'Crème fraîche', 4::numeric, 'EL', '4 EL'),
  (4, null, 'Guacamole', 4::numeric, 'EL', '4 EL'),
  (5, null, 'Süß-Sauer-Soße', 4::numeric, 'EL', '4 EL'),
  (6, null, 'Gurke', 1::numeric, null, '1'),
  (7, null, 'Rote Zwiebeln', 2::numeric, null, '1–2'),
  (8, null, 'Rucola', 80::numeric, 'g', '80 g'),
  (9, null, 'Kapernäpfel', 2::numeric, 'EL', '2 EL'),
  (10, null, 'Olivenöl, Salz, Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Tomaten-Gnocchi', null, null, array['Pfanne', 'Vegetarisch', 'Schnell']::text[], array['pfanne', 'vegetarisch', 'schnell']::text[], 'vegetarisch', 'Zubereitungszeit: 18 Min.', 18, 2, '2 (mit einem Rest Pesto)', array['Eine beschichtete Pfanne (30 cm Ø) bei mittlerer bis hoher Temperatur erhitzen. Knoblauch schälen und in feine Scheiben schneiden.', 'Das meiste vom Knoblauch mit einem Schuss Olivenöl und den Gnocchi in die Pfanne geben, 5 Min. anbraten und gelegentlich durchschwenken.', 'Inzwischen restlichen Knoblauch mit den Haselnüssen in einem großen Mörser zerstoßen. Mit dem Stößel den Spinat einarbeiten (portionsweise, falls nötig) und das Pesto mit etwas nativem Olivenöl extra geschmeidig rühren. Den größten Teil des Parmesans dazureiben und das Pesto sorgfältig abschmecken.', 'Die Tomaten mit den Fingern zerdrücken und in die Pfanne geben, die Dose zur Hälfte mit Wasser füllen, ausschwenken und in die Pfanne ausleeren. Das Ganze einige Minuten eindicken lassen und sorgfältig abschmecken.', 'Die holzigen Enden des Spargels abbrechen, die Stangen in zwei Portionen in die Sauce legen und zugedeckt 5 Min. dämpfen; die Pfanne ab und zu schwenken.', 'Die Oliven zerdrücken und entsteinen. Auf jede Spargelportion 1 Klecks Pesto geben und die Oliven daraufzupfen.', 'Das Ganze vor dem Servieren mit dem restlichen geriebenen Parmesan bestreuen.']::text[], null, '{"text":"470 kcal | Fett 8,5 g | Eiweiß 14,7 g | KH 83,1 g | Zucker 11,1 g | Salz 1,6 g","kcal":"470","Fett":"8,5 g","Eiweiß":"14,7 g","KH":"83,1 g","Zucker":"11,1 g","Salz":"1,6 g"}'::jsonb, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/tomaten-gnocchi.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Knoblauchzehen', 2::numeric, null, '2'),
  (1, null, 'Kartoffelgnocchi', 600::numeric, 'g', '600 g'),
  (2, null, 'Blanchierte Haselnusskerne', 20::numeric, 'g', '20 g'),
  (3, null, 'Babyspinat', 100::numeric, 'g', '100 g'),
  (4, null, 'Parmesan', 20::numeric, 'g', '20 g'),
  (5, null, 'Eiertomaten (Dose)', 400::numeric, 'g', '400 g'),
  (6, null, 'Grüner Spargel', 250::numeric, 'g', '250 g'),
  (7, null, 'Schwarze Oliven mit Stein', 4::numeric, null, '4')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Brathähnchen mit Miso', null, null, array['Geflügel', 'Asiatisch', 'Schmortopf']::text[], array['geflügel', 'asiatisch', 'schmortopf']::text[], 'fleisch', 'Vorbereitung: 17 Min. / Garzeit: 48 Min.', 65, 4, '4', array['Backofen auf 180°C vorheizen, Wasserkocher füllen und einschalten. Einen großen, flachen, ofenfesten Schmortopf kräftig erhitzen und gleichzeitig den Sesam darin rösten; auf einen Teller streuen.', 'Die Hähnchenstücke in den Topf geben und 10 Min. von allen Seiten goldbraun anbraten.', 'Inzwischen mit einem Sparschäler die Schale einer Limette in Streifen abschälen, anschließend die Süßkartoffeln schälen und längs halbieren. Die Frühlingszwiebeln putzen und in 3 cm lange Stücke schneiden, einen Teil des Grüns für die Garnitur in feine Röllchen schneiden und beiseitelegen.', 'Limettenschale, Süßkartoffeln und Frühlingszwiebeln zu dem Hähnchen in den Topf geben.', 'In einer kleinen Schüssel die getrockneten Pilze, die Misopaste, die Sojasauce sowie den Rotweinessig und 200 ml heißes Wasser aus dem Kocher verrühren, dann in den Topf gießen (den sandigen Bodensatz nicht verwenden).', 'Die Hähnchenstücke mit der Hautseite nach oben drehen und im Ofen 45 Min. garen, bis sich das Fleisch mühelos vom Knochen löst und die Süßkartoffeln weich sind.', 'Den Topf bei mittlerer bis starker Hitze auf den Herd stellen. Den Saft beider Limetten hineinpressen und sorgfältig unterrühren.', 'Sobald die Mischung zu sieden beginnt, den Topf vom Herd nehmen und den Bratensatz vom Topfboden losrühren.', 'Alles mit dem gerösteten Sesam und dem Frühlingszwiebelgrün bestreuen und servieren.']::text[], 'Klebreis und gedämpftes Blattgemüse passen gut dazu. Bei uns gab''s Reis und Wirsing als Beilage – hat sehr gut gepasst.', '{"text":"509 kcal | Fett 22,2 g | Eiweiß 43,6 g | KH 34,4 g | Zucker 9,2 g | Salz 1,8 g","kcal":"509","Fett":"22,2 g","Eiweiß":"43,6 g","KH":"34,4 g","Zucker":"9,2 g","Salz":"1,8 g"}'::jsonb, '{"lines":[]}'::jsonb, (select c.id from public.ep_cookbooks c where c.household_id = (select id from public.ep_households where name = 'Familie Dobmeier') and c.title = 'ONE'), null, false, '/images/rezepte/brathaehnchen-miso.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Sesam', 2::numeric, 'EL', '2 EL'),
  (1, null, 'Hähnchenober- und -unterschenkel (mit Haut und Knochen)', 1::numeric, 'kg', '1 kg'),
  (2, null, 'Bio-Limetten', 2::numeric, null, '2'),
  (3, null, 'Süßkartoffeln (kleine, à 150 g)', 4::numeric, null, '4'),
  (4, null, 'Frühlingszwiebeln', 1::numeric, 'Bund', '1 Bund'),
  (5, null, 'Getrocknete Pilze (am besten Shiitake)', 1::numeric, 'EL', '1 EL'),
  (6, null, 'Helle Misopaste', 1::numeric, 'EL', '1 EL'),
  (7, null, 'Salzreduzierte Sojasauce', 2::numeric, 'EL', '2 EL'),
  (8, null, 'Rotweinessig', 2::numeric, 'EL', '2 EL')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Chili con Carne', null, null, array['Eintopf', 'Rind', 'Würzig']::text[], array['eintopf', 'rind', 'würzig']::text[], 'fleisch', 'Zubereitungszeit: ca. 15 Min. Vorbereitung + 45 Min. Köcheln', 60, 4, '4', array['Zwiebeln und Knoblauch fein würfeln, Paprika in kleine Stücke schneiden.', 'Olivenöl in einem großen Topf erhitzen, Hackfleisch darin krümelig und kräftig anbraten, bis es Farbe bekommt.', 'Zwiebeln und Knoblauch zugeben und 2–3 Min. mitbraten.', 'Tomatenmark einrühren und 1 Min. mitrösten. Paprikapulver, Kreuzkümmel, Chili und Oregano zugeben und kurz anrösten.', 'Paprika, stückige Tomaten und Brühe zugeben, aufkochen und zugedeckt ca. 30 Min. bei niedriger Hitze köcheln lassen.', 'Kidneybohnen und Mais zugeben und weitere 10–15 Min. köcheln lassen.', 'Mit Salz, Pfeffer und ggf. mehr Chili abschmecken.', 'Mit Reis oder Brot servieren, nach Belieben mit saurer Sahne, Käse und frischen Kräutern garnieren.']::text[], 'Schmeckt am nächsten Tag aufgewärmt noch besser. Für mehr Tiefe 1 Stück dunkle Schokolade oder 1 TL Kakao am Ende unterrühren.', null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/chili-con-carne.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Rinderhack', 500::numeric, 'g', '500 g'),
  (1, null, 'Zwiebeln', 2::numeric, null, '2'),
  (2, null, 'Knoblauch', 3::numeric, 'Zehen', '3 Zehen'),
  (3, null, 'Paprika (rot)', 2::numeric, null, '2'),
  (4, null, 'Tomaten (stückig, Dose)', 800::numeric, 'g', '800 g'),
  (5, null, 'Tomatenmark', 2::numeric, 'EL', '2 EL'),
  (6, null, 'Kidneybohnen (Dose, abgetropft)', 400::numeric, 'g', '400 g'),
  (7, null, 'Mais (Dose, abgetropft)', 200::numeric, 'g', '200 g'),
  (8, null, 'Rinder- oder Gemüsebrühe', 200::numeric, 'ml', '200 ml'),
  (9, null, 'Paprikapulver (edelsüß oder geräuchert)', 2::numeric, 'TL', '2 TL'),
  (10, null, 'Kreuzkümmel (gemahlen)', 2::numeric, 'TL', '2 TL'),
  (11, null, 'Chilipulver oder Chiliflocken', 2::numeric, 'TL', '1–2 TL'),
  (12, null, 'Oregano (getrocknet)', 1::numeric, 'TL', '1 TL'),
  (13, null, 'Olivenöl', 2::numeric, 'EL', '2 EL'),
  (14, null, 'Salz, Pfeffer', null::numeric, null, 'nach Geschmack'),
  (15, null, 'Reis, Brot oder Tortilla-Chips zum Servieren', null::numeric, null, 'nach Belieben'),
  (16, null, 'Saure Sahne oder Schmand, Käse (gerieben), Koriander oder Petersilie', null::numeric, null, 'zum Garnieren')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Fitness-Reisriegel (PB&J & Banane-Schoko)', null, null, array['Snack', 'Fitness', 'Meal Prep', 'Süß']::text[], array['snack', 'fitness', 'meal-prep', 'süß']::text[], 'vegetarisch', 'Kochzeit: ca. 25 Min. + 2–3 Std. Kühlen', 205, null, '2 Dosen (je 1 Geschmacksrichtung), in mundgerechte Riegel geschnitten', array['Reis mit Wasser und Salz in einen Topf geben, aufkochen, dann Hitze herunterdrehen und bei geschlossenem Deckel ca. 25 Min. leicht köcheln lassen. Gelegentlich umrühren. Der Reis sollte das Wasser komplett aufsaugen und weich und klebrig werden.', 'Den noch heißen Reis auf zwei Schüsseln oder Behälter aufteilen.', 'PB&J: Erdnussbutter und Marmelade kräftig unter die heiße Reishälfte rühren.', 'Banane-Schoko: Bananenbrei (und ggf. Zimt/Sirup/Honig) in die andere Hälfte einrühren. Masse kurz abkühlen lassen, bevor die Schokostückchen dazukommen, damit sie nicht komplett zerschmelzen.', 'Zwei flache Tupperdosen mit Frischhaltefolie oder Backpapier auslegen (so lassen sich die Blöcke später am Stück herausheben).', 'Reismassen jeweils in eine Dose geben und mit einem angefeuchteten Löffel oder dem Boden eines Glases extrem fest andrücken. Je kompakter, desto stabiler die Riegel.', 'Mindestens 2–3 Std. in den Kühlschrank stellen, damit die Reisstärke abbindet.', 'An der Folie herausheben, auf ein Brett stürzen und in mundgerechte Riegel schneiden.']::text[], 'Gut für unterwegs, vor oder nach dem Training – im Kühlschrank aufbewahren.', null, '{"lines":[]}'::jsonb, null, null, true, '/images/rezepte/fitness-reisriegel.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, 'Basis', 'Milchreis (Rundkornreis klebt am besten)', 500::numeric, 'g', '500 g'),
  (1, 'Basis', 'Wasser', 1.2::numeric, 'l', '1–1,2 l'),
  (2, 'Basis', 'Salz (wichtig für Geschmack und Elektrolyte)', 1::numeric, 'TL', '1 TL'),
  (3, 'Dose 1: PB&J', 'Erdnussbutter', 3::numeric, 'EL', '2–3 EL'),
  (4, 'Dose 1: PB&J', 'Marmelade (z. B. Erdbeere oder Himbeere)', 3::numeric, 'EL', '2–3 EL'),
  (5, 'Dose 2: Banane-Schoko', 'Sehr reife Bananen (mit der Gabel zu Brei zerdrückt)', 2::numeric, null, '1–2'),
  (6, 'Dose 2: Banane-Schoko', 'Schokostückchen oder gehackte Schokolade', null::numeric, null, 'nach Geschmack'),
  (7, 'Dose 2: Banane-Schoko', 'Ahornsirup oder Honig (optional)', 1::numeric, 'Schuss', '1 Schuss'),
  (8, 'Dose 2: Banane-Schoko', 'Zimt (optional)', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

with r as (insert into public.ep_recipes (household_id, title, subtitle, source, categories, tags, diet, time_text, time_min, servings, servings_text, steps, tip, nutrition, extra_meta, cookbook_id, cookbook_page, cookbook_link_confirmed, image_url)
  select id, 'Honighähnchen', 'Süße rote Zwiebeln, Oregano, Orangen, Feta & Pistazien', 'Kochbuch (Foto, Kapitel Schmortopf)', array['Geflügel', 'Schmortopf']::text[], array['geflügel', 'schmortopf']::text[], 'fleisch', 'Vorbereitung 16 Min. / Garzeit 50 Min.', 66, 4, '4', array['Backofen auf 180 °C vorheizen. Hähnchenstücke in einen großen, flachen, ofenfesten Schmortopf legen und bei starker Hitze auf dem Herd rundherum 10 Min. goldbraun anbraten, dabei regelmäßig wenden.', 'Inzwischen Zwiebeln schälen und grob hacken, Oreganoblätter abzupfen. Mit einem Sparschäler die Schale der Orangen streifenweise in den Topf schälen.', 'Zwiebeln, Oregano und 2 EL Rotweinessig zugeben, mit Meersalz und Pfeffer würzen und alles gründlich vermengen.', 'Hähnchenstücke mit der Hautseite nach oben drehen und im Ofen 45 Min. garen, bis sich das Fleisch mühelos vom Knochen löst.', 'Topf bei mittlerer bis starker Hitze wieder auf den Herd stellen und den Saft der Orangen hineinpressen. Tomaten vierteln, dazugeben und alles aufkochen.', 'Hähnchenstücke mit dem Honig beträufeln. Pistazien fein hacken und in den Topf streuen, Feta hineinkrümeln, servieren.']::text[], 'Dazu passen Couscous oder ein einfacher Salat.', '{"text":"442 kcal | Fett 23,7 g | gesättigte Fettsäuren 6,6 g | Eiweiß 42 g | KH 16,3 g | Zucker 13,6 g | Salz 0,9 g | Ballaststoffe 2,5 g","kcal":"442","Fett":"23,7 g","gesättigte Fettsäuren":"6,6 g","Eiweiß":"42 g","KH":"16,3 g","Zucker":"13,6 g","Salz":"0,9 g","Ballaststoffe":"2,5 g"}'::jsonb, '{"lines":[]}'::jsonb, (select c.id from public.ep_cookbooks c where c.household_id = (select id from public.ep_households where name = 'Familie Dobmeier') and c.title = 'ONE'), null, false, '/images/rezepte/honighaehnchen.jpg' from public.ep_households where name = 'Familie Dobmeier' returning id)
insert into public.ep_recipe_ingredients (recipe_id, position, group_name, name, amount, unit, amount_text) select r.id, v.* from r, (values
  (0, null, 'Hähnchenober- und -unterschenkel mit Haut und Knochen', 1::numeric, 'kg', '1 kg'),
  (1, null, 'Rote Zwiebeln', 2::numeric, null, '2'),
  (2, null, 'Frischer Oregano', 1::numeric, 'Bund', '1 Bund (20 g)'),
  (3, null, 'Bio-Orangen', 2::numeric, null, '2'),
  (4, null, 'Reife Kirschtomaten in verschiedenen Farben', 160::numeric, 'g', '160 g'),
  (5, null, 'Flüssiger Honig', 2::numeric, 'EL', '2 EL'),
  (6, null, 'Ungesalzene Pistazienkerne', 20::numeric, 'g', '20 g'),
  (7, null, 'Feta', 20::numeric, 'g', '20 g'),
  (8, null, 'Rotweinessig', 2::numeric, 'EL', '2 EL'),
  (9, null, 'Meersalz, schwarzer Pfeffer', null::numeric, null, 'nach Geschmack')) as v(position, group_name, name, amount, unit, amount_text);

commit;
