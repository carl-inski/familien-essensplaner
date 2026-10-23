# Build-Briefing: Familien-Essensplaner

> An: KI-Coding-Agent. Auftraggeber: Carl Dobmeier. Stand: 23.10.2026 (v2: Rezeptsammlung, Kochbücher, KI-Funktionen, Kochhistorie).
> Beigefügt als Seed-Daten: `rezeptsammlung.md` (19 Rezepte, Format siehe Abschnitt 8). Kochbuch-Seed siehe Abschnitt 4.6.
> Bitte zuerst die offenen Fragen (Abschnitt 12) mit Carl klären, wo sie den MVP betreffen. Sonst gelten die hier genannten Annahmen.

---

## 1. Ziel

Eine mobile-first Web-App (PWA), mit der eine fünfköpfige Familie ihr Essen für die Woche plant:

- wer an welchem Tag zu welcher Mahlzeit zuhause ist,
- welches Gericht gekocht wird (aus der Rezeptsammlung, aus den eigenen Kochbüchern oder als neuer Vorschlag),
- wer kocht,
- was wann zuletzt gekocht wurde und was lange nicht auf dem Tisch war,
- und der komplette Wocheneinkauf, auf die anwesenden Personen skaliert, per Knopfdruck in die **Bring!**-App.

## 2. Nutzer

Ein Haushalt mit 5 Mitgliedern: **Paul, Anton, Carl, Vroni, Christian**.

- Carl ist Hauptnutzer und Admin (Architekturstudent, sportlich). Er erholt sich von einer Stressfraktur, darum sind Kalzium, Vitamin D und Protein relevant (Nährstoff-Fokus in Vorschlägen und Nährwerten).
- Vorlieben im Haushalt: One-Pot-Gerichte (Jamie Oliver „ONE“), Hähnchen, Pasta, Asiatisch, Wraps, Lachs. Regel für Vorschläge: **höchstens 1 Fleischgericht pro 3 Gerichte** (Fisch zählt nicht als Fleisch).
- Sprache der UI: Deutsch. Zeitzone: Europe/Berlin. Woche: Montag bis Sonntag, ISO-Kalenderwoche.

## 3. Tech-Stack

- **Next.js** (App Router, TypeScript), Deployment auf **Vercel** (Carl hat einen Account).
- **Supabase**: Postgres, Auth (Magic Link per E-Mail), Realtime (Änderungen an Plan/Anwesenheit sofort bei allen sichtbar), Storage für Rezeptfotos, Kochbuch-Cover und hochgeladene Kochbuchseiten. Carl hat einen Account.
- Row Level Security: Jeder Nutzer sieht und ändert nur Daten seines Haushalts.
- Mobile-first, installierbar als **PWA** (Manifest, Icons, Homescreen). Kein natives App-Projekt.
- **KI**: anbieterunabhängig, nur serverseitig (Details Abschnitt 6).
- **ISBN-Abfrage**: Open Library (`https://openlibrary.org/isbn/<isbn>.json`) mit Fallback Google Books API (`https://www.googleapis.com/books/v1/volumes?q=isbn:<isbn>`).
- Styling frei wählbar (z. B. Tailwind). Ziel: schnell, gut am Handy mit dem Daumen bedienbar.

## 4. MVP-Umfang mit Abnahmekriterien

### 4.1 Login & Haushalt
- Magic-Link-Login. Carl legt den Haushalt an und lädt die anderen per E-Mail ein; die 5 Mitglieder sind vorab als `members` angelegt und werden beim ersten Login verknüpft.
- **Abnahme:** Ein eingeladenes Mitglied kann sich einloggen und sieht ausschließlich den eigenen Haushalt. Ohne Login sind nur die öffentlichen Rezept-/Einkaufsseiten (Abschnitt 5) erreichbar.

### 4.2 Wochenübersicht & Anwesenheit
- Raster Tag × Mahlzeit. MVP: nur Slot `abend` sichtbar; Datenmodell unterstützt `fruehstueck`, `mittag`, `abend`.
- Pro Person und Slot: `da` / `weg` / `da + Gäste (n)`. Standard ist `da`.
- Optionale Standardwoche pro Person (z. B. „Carl dienstags weg“), wird beim Öffnen einer neuen Woche vorbefüllt.
- Navigation: vorige / nächste Woche.
- **Abnahme:** Jeder kann seine eigene Anwesenheit mit max. 1 Tipp pro Slot ändern; Änderungen erscheinen ohne Reload bei allen (Realtime). Pro Slot ist die Zahl der Esser sichtbar.

### 4.3 Essensplan
- In jeden Slot ein Rezept einplanen (Suche in der Sammlung, Liste „Lange nicht gegessen“, Kochbuch-Ansicht) oder als „Reste von <Slot>“ markieren.
- Button „Vorschlag“ füllt einen freien Slot regelbasiert (MVP ohne KI): nicht in den letzten 14 Tagen gekocht, Fleischregel aus Abschnitt 2, bevorzugt lange nicht oder nie gekochte Rezepte und Rezepte aus eigenen Kochbüchern.
- Jeder Slot hat einen Status `geplant` → `gekocht` / `ausgefallen` (siehe 4.7).
- **Abnahme:** Ein Rezept lässt sich in < 3 Tipps einplanen und wieder entfernen. Die Fleischregel wird bei Vorschlägen nie verletzt; beim manuellen Einplanen erscheint nur ein Hinweis. Vorgeschlagene Rezepte aus eigenen Büchern tragen das Label „aus deinem Regal“.

### 4.4 Kochdienst
- Pro Slot eine kochende Person (optional eine zweite). Auswählbar sind nur Personen, die in diesem Slot `da` sind.
- Zähler: wie oft jede Person in den letzten 4 Wochen gekocht hat (aus `cooking_history`).
- **Abnahme:** Eine abwesende Person kann nicht eingeteilt werden. Wenn eine eingeteilte Person sich abmeldet, wird der Slot als „Koch fehlt“ markiert.

### 4.5 Rezeptsammlung (eigener Hauptbereich)
Eigener Menüpunkt, gleichwertig zum Wochenplan.
- **Stöbern:** Kartenansicht (Foto bzw. Platzhalter, Titel, Zeit, Portionen, Diät-Icon, Kochbuch + Seite, „zuletzt gekocht“).
- **Suche:** Volltext über Titel, Untertitel, Zutaten, Tags (Postgres `tsvector`, Konfiguration `german`, plus Trigram-Index für Tippfehler).
- **Filter (kombinierbar):** Kategorie, Tags (z. B. `one-pot`, `meal-prep`, `kalzium`), Zeit (≤ 20 / ≤ 30 / ≤ 60 Min. / egal), `diet` (Fleisch / Fisch / vegetarisch), Kochbuch, „nie gekocht“, „nicht in den letzten X Wochen“. Sortierung: A–Z, zuletzt gekocht, am längsten nicht gekocht, am häufigsten gekocht, neu hinzugefügt.
- **Detailseite:** alle Felder, Portionswähler (skaliert Zutaten live), Buttons „Einplanen“, „In Bring übernehmen“, „Bearbeiten“, Historie (Abschnitt 4.7).
- **Anlegen/Bearbeiten:** Formular mit allen Feldern aus Abschnitt 8, Zutaten als sortierbare Zeilen mit optionaler Gruppe, Schritte als sortierbare Liste, Foto-Upload, Kochbuch + Seite.
- **Import/Export:** Markdown-Import (Datei-Upload, Format Abschnitt 8) mit Vorschau und Duplikat-Erkennung (gleicher Titel → überspringen / überschreiben / als Kopie). Export der gesamten Sammlung oder eines Rezepts als Markdown im selben Format.
- **Abnahme:**
  - Alle 19 Rezepte werden ohne Datenverlust importiert (Titel, Metadaten, Zutaten inkl. Gruppen, Schritte, Tipp, Nährwerte).
  - Import → Export → Import ergibt identische Daten (Round-Trip-Test).
  - Suche „Feta“ findet alle Rezepte mit Feta in Zutaten oder Titel; Filter „vegetarisch + ≤ 30 Min.“ liefert nur passende Rezepte.
  - Ein neues Rezept ist nach dem Speichern sofort in Suche und Filtern auffindbar.

### 4.6 Kochbücher
- Haushalt erfasst Kochbücher, die er besitzt: Titel, Autor(en), Verlag, Erscheinungsjahr, ISBN, Cover.
- **ISBN-Abfrage:** ISBN eintippen (MVP) oder Barcode scannen (Phase 2, Kamera via `BarcodeDetector`/Fallback-Library) → Felder und Cover werden aus Open Library / Google Books vorbefüllt, Nutzer bestätigt.
- Rezepte mit Kochbuch + Seitenzahl verknüpfen. Ein Rezept kann auch nur als Verweis existieren (Titel + Buch + Seite, ohne abgetippte Zutaten); solche Rezepte sind planbar, aber nicht skalier-/exportierbar nach Bring, bis Zutaten ergänzt sind (z. B. per Foto-Import, Abschnitt 6).
- **Regal-Ansicht:** alle Bücher als Cover-Raster; Buch-Detail zeigt verknüpfte Rezepte mit Seitenzahl und „zuletzt gekocht“.
- Vorschläge zeigen „aus deinem Regal: <Buch>, S. <n>“.
- **Seed (15 Bücher):** Autor/Verlag, wo unten „offen“, per ISBN-Abfrage ergänzen und Carl bestätigen lassen.

| Titel | Autor / Verlag |
|---|---|
| Die echte italienische Küche | Verlag: GU |
| Jerusalem | Yotam Ottolenghi, Sami Tamimi |
| Schlau kochen | offen |
| Das neue bayrische Kochbuch | offen |
| Leon Fast Food Vegetarisch | Leon (Autor offen) |
| Das große Buch vom Backen und Bauen | offen |
| Harry's Bar Kochbuch | Arrigo Cipriani |
| Meine Klassiker | Alfons Schuhbeck |
| Bayrisches Kochbuch | offen |
| Licence to Cook | offen |
| Anniks göttliche Desserts | offen |
| Ottolenghi Test Kitchen | Yotam Ottolenghi, Noor Murad |
| Ottolenghi Simple | Yotam Ottolenghi |
| ONE | Jamie Oliver |
| Das neue Grand Tour Kochbuch | Hannah Grant |

- **Seed-Verknüpfungen** (Seitenzahlen offen, `page = null`):
  - „One-Pot Räucherlachs-Pasta (Jamie Oliver)“ → ONE
  - „Ananascurry (nach Leon: Fast Vegetarian)“ → Leon Fast Food Vegetarisch
  - „Honighähnchen“ → ONE, `link_confirmed = false` (stammt von einem Foto einer Kochbuchseite, vermutlich ONE)
  - „Brathähnchen mit Miso“ → ONE, `link_confirmed = false` (dito)
  - Unbestätigte Verknüpfungen im UI mit „zu bestätigen“ markieren.
- **Abnahme:** Alle 15 Bücher sind nach dem Seed im Regal. Eine gültige ISBN füllt mindestens Titel und Autor vor. Buch-Detail von ONE zeigt die 3 verknüpften Rezepte (2 davon „zu bestätigen“). Filter „Kochbuch = ONE“ in der Sammlung liefert dieselben Rezepte.

### 4.7 Kochhistorie
- Nach dem Essen markiert man den Slot als **„gekocht ✓“** (Koch oder jedes Mitglied). Das setzt `meal_plan.status = 'gekocht'` und legt einen Eintrag in `cooking_history` an (Rezept, Datum, Koch, Portionen). „Rückgängig“ löscht den Eintrag wieder.
- Zusätzlich: „Heute außerhalb des Plans gekocht“ auf der Rezeptseite legt einen Eintrag ohne `meal_plan_id` an; „Früher schon mal gekocht (ca. Datum)“ zum Nachtragen.
- Reste-Slots erzeugen keinen eigenen Historien-Eintrag.
- Rezeptkarte und -detail zeigen **„zuletzt gekocht am TT.MM.JJJJ · n×“**, bzw. „noch nie gekocht“.
- Ansicht **„Lange nicht gegessen“**: alle Rezepte mit mind. einem Eintrag, sortiert nach Tagen seit dem letzten Kochen (absteigend), mit Spalten Zuletzt gekocht, Tage seitdem, Anzahl. Darunter getrennt: **„Noch nie gekocht“**. Filter nach `diet` und Kochbuch, direkt einplanbar.
- Vorschläge (regelbasiert und KI) nutzen die Historie: < 14 Tage gesperrt, je länger her desto höher gewichtet, nie gekochte leicht bevorzugt.
- Umsetzung: Tabelle `cooking_history` plus View `recipe_cook_stats` (`recipe_id`, `last_cooked_on`, `times_cooked`, `days_since`).
- **Abnahme:** „gekocht ✓“ erhöht `times_cooked` um 1 und aktualisiert „zuletzt gekocht“ sofort; Rückgängig stellt den alten Stand her. Ein in den letzten 14 Tagen gekochtes Rezept wird nie vorgeschlagen. „Lange nicht gegessen“ ist korrekt sortiert und enthält keine nie gekochten Rezepte.

### 4.8 Einkaufsliste & Bring!
- Einkaufsliste der Woche = Zutaten aller geplanten Slots, skaliert (Abschnitt 7), gleiche Zutaten mit gleicher Einheit summiert, nach Supermarkt-Bereich (`aisle`) gruppiert. MVP: `aisle` per einfacher Schlagwort-Tabelle; Phase 2: KI-Sortierung.
- Button „In Bring übernehmen“ für die ganze Woche und auf jeder Rezeptseite (Spezifikation Abschnitt 5).
- Fallback-Export: Liste als Text kopieren (eine Zutat pro Zeile, z. B. für die Apple-Erinnerungen-Liste „Shopping“).
- **Abnahme:** Der Wochen-Button öffnet auf dem Handy die Bring!-App mit allen Zutaten der Woche. Die öffentliche Einkaufsseite besteht den Bring-Integration-Check (https://getbring.com/en/integration-check).

## 5. Bring!-Integration (verbindlich)

Bring! hat **keine offizielle öffentliche Schreib-API**. Der offizielle Weg ist der **Rezept-Import per Deeplink**: Bring ruft eine öffentliche Seite ab und liest dort schema.org-Recipe-JSON-LD.

**Nicht verwenden:** die inoffizielle `python-bring-api` oder andere inoffizielle Clients. Sie brauchen das Bring-Passwort und nutzen undokumentierte Endpunkte.

### 5.1 Öffentliche Seiten
- `/r/<public_slug>`: ein Rezept.
- `/einkauf/<public_slug>`: Wocheneinkauf, z. B. „Wocheneinkauf KW 45“, als **ein kombiniertes Pseudo-Rezept** mit allen skalierten Zutaten der Woche.
- Ohne Login erreichbar, `public_slug` nicht erratbar (z. B. 12+ zufällige Zeichen), `noindex`. Sichtbares HTML plus JSON-LD.

### 5.2 JSON-LD (serverseitig gerendert)
```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Recipe",
  "name": "Wocheneinkauf KW 45",
  "author": { "@type": "Organization", "name": "Familien-Essensplaner" },
  "image": "https://<domain>/og/einkauf-kw45.png",
  "recipeYield": "1",
  "recipeIngredient": [
    "5 Lachsfilets",
    "940 g Hähnchenschenkel mit Haut",
    "400 g Feta"
  ]
}
</script>
```
- Pflicht: `name`, `author`, `recipeIngredient`. Empfohlen und hier immer zu setzen: `recipeYield`, `image` (Platzhalterbild, falls kein Foto vorhanden).
- `recipeIngredient`: ein String pro Zutat, **Menge + Einheit + Name**, bereits skaliert.
- Bei Einzelrezepten: `recipeYield` = geplante Portionen. Bring lässt den Nutzer die Portionen dann noch anpassen. Beim Wocheneinkauf: `recipeYield` = `"1"`, damit Bring nicht umrechnet.

### 5.3 Deeplink
```
https://api.getbring.com/rest/bringrecipes/deeplink?url=<URL-encodierte öffentliche Seiten-URL>&source=web
```
- URL mit `encodeURIComponent` codieren. Der Link wird als normaler `<a href>` geöffnet (kein `fetch`).
- Seiten müssen öffentlich über HTTPS auf der Vercel-Domain erreichbar sein (Preview-Deployments mit Vercel-Auth funktionieren nicht).

## 6. KI-Funktionen

### 6.1 Architektur (verbindlich)
- **Anbieterunabhängig:** eine Abstraktionsschicht (z. B. Vercel AI SDK `ai` mit Provider-Paketen), Anbieter und Modell per Env: `LLM_PROVIDER`, `LLM_MODEL`, `LLM_VISION_MODEL`, `LLM_API_KEY`. Wechsel des Anbieters ohne Codeänderung.
- **Nur serverseitig:** Aufrufe ausschließlich in Next.js Route Handlers (`/api/ai/*`) auf Vercel; der Key verlässt nie den Server und steht nie im Client-Bundle. Nur eingeloggte Haushaltsmitglieder dürfen aufrufen.
- **Strukturierte Ausgabe:** jede Funktion hat ein Zod-Schema (z. B. `RecipeDraft` = Felder aus Abschnitt 8); Antwort wird validiert, bei Fehler einmal neu versucht.
- **Mensch bestätigt:** KI-Ergebnisse sind immer Entwürfe; gespeichert wird erst nach „Übernehmen“ im UI.
- **Kosten & Limits:** jeder Aufruf wird in `ai_usage` geloggt (Feature, Modell, Tokens, geschätzte Kosten). Limits per Env: `AI_DAILY_CALL_LIMIT` (Default 50 pro Haushalt), `AI_MONTHLY_BUDGET_EUR` (Default 5). Bei Erreichen: verständliche Meldung, Funktion pausiert bis zum nächsten Tag/Monat. Admin sieht Monatsverbrauch. Günstiges Modell als Default, Vision-Modell nur für Foto-Import. Ergebnisse cachen (gleiche URL / gleiches Bild-Hash → kein neuer Aufruf).

### 6.2 Funktionen (Phase 2, Reihenfolge = Priorität)
| Funktion | Input → Output | Abnahme |
|---|---|---|
| Rezept aus Foto/Screenshot | 1–3 Bilder (Kochbuchseite, Screenshot) → `RecipeDraft`; optional Buch + Seite vorauswählen | Foto einer typischen Kochbuchseite ergibt Titel, ≥ 90 % der Zutaten mit Mengen und alle Schritte korrekt; Nutzer kann vor dem Speichern editieren |
| Rezept aus URL | URL → Seite serverseitig laden; vorhandenes JSON-LD bevorzugen, sonst LLM-Extraktion → `RecipeDraft` | Für eine Seite mit schema.org-Recipe wird ohne LLM-Aufruf importiert |
| Schlaue Wochenvorschläge | Anwesenheit der Woche, Fleischregel, `recipe_cook_stats`, Saison (Monat), Budget, Nährstoff-Fokus (Kalzium / Vit. D / Protein), Ablehnungsgründe → 3–7 Vorschläge mit kurzer Begründung, aus Sammlung + „aus deinem Regal“ + max. 2 neue | Regeln (Fleisch, 14 Tage) werden serverseitig nachgeprüft, Verstöße verworfen; jeder Vorschlag hat Begründung |
| „Was koche ich damit?“ | Chat-artiges Eingabefeld mit Resten/Vorrat → 3 Ideen (Sammlung zuerst, dann Bücher, dann neu) | Antwort in < 10 s, Ideen direkt einplanbar |
| Varianten | Rezept + Wunsch („vegetarisch“, „schneller“, „One-Pot“, „Airfryer“) → neuer `RecipeDraft` mit Verweis auf Original | Variante wird als eigenes Rezept mit `variant_of` gespeichert |
| Umrechnen | Portionen/Einheiten (Tasse, oz, lb, Becher → g/ml); deterministische Tabelle zuerst, LLM nur für Unbekanntes | „1 cup flour“ → „125 g Mehl“ |
| Einkauf sortieren | Zutatenliste → `aisle` je Zutat (Obst & Gemüse, Kühlregal, Frischetheke, Trockenware, Gewürze, Tiefkühl, Getränke, Sonstiges); Ergebnis pro Zutatenname cachen | Jede Zutat landet in genau einem Bereich |
| Nährwerte schätzen | Zutaten + Portionen → kcal, Protein, Fett, KH, Kalzium, Vitamin D pro Portion, `nutrition_estimated = true` | Im UI klar als „geschätzt“ markiert; vorhandene Nährwerte aus dem Buch werden nie überschrieben |

## 7. Portionsskalierung

```
esser(slot)    = Anzahl members mit status 'da' + Summe guests
faktor(slot)   = esser(slot) / recipe.servings
menge_zutat    = amount * faktor   (gerundet, s. u.)
```
- Reste: Ist ein späterer Slot als „Reste von X“ markiert, kocht X für `esser(X) + esser(Reste-Slot)` Portionen; der Reste-Slot erzeugt keine eigenen Zutaten.
- Manuelle Überschreibung der Portionszahl pro Slot möglich (`meal_plan.servings_override`).
- Rundung: Stückzutaten (Eier, Zwiebeln, Orangen, Filets) auf ganze Stück **aufrunden**; g/ml auf sinnvolle Schritte (< 100 → 5, sonst 10); EL/TL auf 0,5.
- Zutaten ohne Menge („nach Geschmack“, „etwas“) werden nicht skaliert und nur einmal gelistet.
- Aggregation über die Woche: gleicher normalisierter Name + gleiche Einheit → summieren; sonst getrennt listen.
- Mengen-Parsing: deutsche Dezimalkommas („1,5“), Spannen („1–1,2 l“ → oberer Wert), Einheiten g, kg, ml, l, EL, TL, Stück, Bund, Dose, Pck., Zehen. Nicht parsebare Mengen bleiben als Text erhalten (`amount = null`, `amount_text` gesetzt).
- **Abnahme:** Rezept mit `servings = 4`, 1 kg Hähnchen, 3 Personen da → 750 g. 5 Personen da, 2 Orangen → 3 Orangen (2,5 aufgerundet).

## 8. Markdown-Importformat (`rezeptsammlung.md`)

Datei beigefügt. Aufbau:

```markdown
# Rezeptsammlung
## Inhalt            ← Inhaltsverzeichnis, beim Import ignorieren
---
## <Titel>           ← ein Rezept pro H2, getrennt durch ---

**Untertitel:** …    (optional)
**Quelle:** <URL oder Text, z. B. Kochbuch>   (optional)
**Kochbuch:** <Buchtitel>, S. <n>            (optional, neu ab v2; beim Export schreiben, wenn verknüpft)
**Kategorie:** A / B / C      (Tags, getrennt durch " / ")
**Zeit:** <Freitext>          (optional)
**Portionen:** 4 (Zusatztext optional)   ODER   **Menge:** <Freitext>

### Zutaten
| Zutat | Menge |
|---|---|
| **Gruppenname** | |   ← fette Zeile ohne Menge = Zutatengruppe
| Feta | 200 g |

### Zubereitung
1. …                 ← nummerierte Schritte

**Tipp:** …          (optional)
**Nährwerte pro Portion:** 442 kcal | Fett 23,7 g | Eiweiß 42 g | …   (optional)
```
- Metazeilen enden teils mit zwei Leerzeichen (Markdown-Zeilenumbruch); trimmen.
- `servings` = erste Zahl aus `Portionen`. Bei `Menge` ohne Portionen: `servings = null`, nicht skalierbar.
- `diet` aus `Kategorie` ableiten (z. B. „Geflügel“, „Fisch“, „Vegetarisch“), im UI korrigierbar.
- `**Kochbuch:**` beim Import gegen `cookbooks.title` matchen (unscharf); ohne Treffer Buch anlegen und als „zu bestätigen“ markieren. Fehlt die Zeile, aber `Titel`/`Quelle` nennt ein Seed-Buch (z. B. „Jamie Oliver“, „Leon“), Verknüpfung vorschlagen.
- Export schreibt exakt dieses Format inkl. Inhaltsverzeichnis mit Ankerlinks. Unbekannte Zeilen beim Import in `extra_meta jsonb` aufheben und beim Export wieder ausgeben (verlustfrei).

## 9. Datenmodell (Supabase / Postgres)

Alle Tabellen haben `id uuid pk default gen_random_uuid()` und `created_at timestamptz`. RLS über `household_id` (bei Kindtabellen über die Elterntabelle).

| Tabelle | Spalten | Relationen |
|---|---|---|
| `households` | `name`, `budget_week numeric null`, `ai_monthly_budget_eur numeric null` | – |
| `members` | `household_id`, `name`, `user_id uuid null`, `role text ('admin'\|'member')`, `default_week jsonb` (z. B. `{"tue":{"abend":"weg"}}`) | → households; `user_id` → `auth.users` |
| `cookbooks` | `household_id`, `title`, `authors text[]`, `publisher`, `year int null`, `isbn text null`, `cover_url`, `notes`; unique (`household_id`,`isbn`) | → households |
| `recipes` | `household_id`, `title`, `subtitle`, `source`, `categories text[]`, `diet text ('fleisch'\|'fisch'\|'vegetarisch')`, `time_text`, `time_min int null`, `servings int null`, `servings_text`, `steps text[]`, `tip`, `nutrition jsonb`, `nutrition_estimated bool default false`, `cookbook_id uuid null`, `cookbook_page int null`, `cookbook_link_confirmed bool default true`, `tags text[]`, `image_url`, `variant_of uuid null`, `extra_meta jsonb`, `search tsvector` (generated, `german`), `public_slug unique`, `updated_at` | → households; → cookbooks (on delete set null); `variant_of` → recipes |
| `recipe_ingredients` | `recipe_id`, `position int`, `group_name null`, `name`, `amount numeric null`, `unit null`, `amount_text`, `aisle text null` | → recipes (on delete cascade) |
| `attendance` | `member_id`, `date`, `meal text ('fruehstueck'\|'mittag'\|'abend')`, `status text ('da'\|'weg')`, `guests int default 0`; unique (`member_id`,`date`,`meal`) | → members |
| `meal_plan` | `household_id`, `date`, `meal`, `recipe_id null`, `leftover_of uuid null`, `cook_id null`, `cook2_id null`, `servings_override int null`, `status text ('geplant'\|'gekocht'\|'ausgefallen') default 'geplant'`, `note`; unique (`household_id`,`date`,`meal`) | → recipes, → members (cook), `leftover_of` → meal_plan |
| `cooking_history` | `household_id`, `recipe_id`, `cooked_on date`, `meal_plan_id uuid null unique`, `cook_id uuid null`, `servings int null`, `source text ('plan'\|'manuell'\|'nachgetragen')` | → recipes (on delete cascade), → meal_plan (on delete set null), → members |
| View `recipe_cook_stats` | `recipe_id`, `last_cooked_on = max(cooked_on)`, `times_cooked = count(*)`, `days_since = current_date - max(cooked_on)` | aus `cooking_history` |
| `suggestions` | `household_id`, `iso_week text` (z. B. `2026-W45`), `recipe_id null`, `draft jsonb null` (neues Rezept, noch nicht gespeichert), `origin text ('sammlung'\|'regal'\|'neu')`, `generated_by text ('regel'\|'ki'\|'samstag')`, `reason_shown text`, `status text ('offen'\|'angenommen'\|'abgelehnt')`, `reject_reason text null` | → recipes |
| `shopping_lists` | `household_id`, `iso_week`, `public_slug unique`, `items jsonb` (Snapshot der aggregierten Liste), `exported_at null` | → households |
| `ai_usage` | `household_id`, `member_id`, `feature text`, `model text`, `tokens_in int`, `tokens_out int`, `cost_eur numeric`, `cache_hit bool` | → households, → members |
| `ai_cache` | `key text pk` (Hash aus Feature + Input), `result jsonb`, `expires_at` | – |
| `pantry_items` (Phase 2) | `household_id`, `name`, `amount null`, `unit null` | → households |
| `ratings` (Phase 3) | `recipe_id`, `member_id`, `stars int 1–5`, `comment`; unique (`recipe_id`,`member_id`) | → recipes, → members |

Trigger/Server-Logik: `meal_plan.status` → `'gekocht'` legt `cooking_history` an (nicht für Reste-Slots), zurück auf `'geplant'` löscht den Eintrag mit dieser `meal_plan_id`.
Realtime aktivieren für `attendance`, `meal_plan`, `suggestions`, `cooking_history`.
Indizes: GIN auf `recipes.search`, `recipes.tags`, `recipes.categories`; `pg_trgm` auf `recipes.title`; `cooking_history (recipe_id, cooked_on desc)`.

## 10. Spätere Phasen

**Phase 2 – KI & schlau**
- Alle KI-Funktionen aus Abschnitt 6.2 (Foto-/URL-Import zuerst).
- Samstags-Vorschläge: Carl bekommt jeden Samstag ~10 Uhr 3 Rezeptvorschläge (1 aus der Sammlung, 2 neu). Diese per Endpoint (`POST /api/suggestions`, Token-geschützt via `SUGGESTIONS_TOKEN`) in `suggestions` schreiben (`generated_by = 'samstag'`); im UI annehmen (→ Rezept speichern + einplanen) oder mit Grund ablehnen.
- ISBN-Barcode-Scan mit der Handykamera.
- Vorrat (`pantry_items`): vorhandene Zutaten fallen aus der Einkaufsliste.
- Nährstoff-Fokus: Wochenübersicht Kalzium / Vitamin D / Protein für Carl.
- Meal-Prep: „doppelt kochen“ für Uni-Mittagessen.

**Phase 3 – Komfort**
- Google-Calendar-Sync: Termine befüllen Anwesenheit vor; Kochdienst als Kalendertermin.
- Wochenbudget mit Kostenschätzung pro Gericht.
- Bewertungen/Favoriten pro Person, fließen in Vorschläge ein.
- Saisonkalender für Vorschläge.
- Fairness-Statistik und automatische Kochdienst-Vorschläge.

## 11. Lieferumfang

- Repo mit Next.js-App, Supabase-Migrations (SQL inkl. RLS-Policies, View, Trigger, Indizes), Seed-Skript, das `rezeptsammlung.md` importiert, die 5 Mitglieder und die 15 Kochbücher anlegt und die 4 Verknüpfungen aus 4.6 setzt.
- Unit-Tests für Markdown-Parser (Round-Trip), Portionsskalierung (Beispiele aus Abschnitt 7), Vorschlagsregeln (Fleisch, 14 Tage) und Kochhistorie (gekocht / rückgängig).
- `.env.example` mit allen Variablen (Supabase, `LLM_*`, `AI_*`, `SUGGESTIONS_TOKEN`).
- README: lokales Setup, Env-Variablen, Deployment auf Vercel, Supabase-Projekt verbinden, KI-Anbieter wechseln.

## 12. Offene Fragen an Carl

1. Wer nutzt die App aktiv – alle fünf mit eigenem Login oder nur ein, zwei Personen? (Annahme MVP: alle fünf, Carl ist Admin.)
2. Gibt es eine gemeinsame Bring!-Liste oder hat jeder seine eigene?
3. Welches Wochenbudget soll gelten? (Erst Phase 3 relevant.)
4. Wie viel darf die KI pro Monat kosten, und welchen Anbieter bevorzugst du? (Annahme: 5 €/Monat, Anbieter frei.)
5. Nur Abendessen planen oder auch Mittag/Frühstück? (Annahme MVP: nur Abend.)
6. Gibt es Unverträglichkeiten oder Dinge, die jemand in der Familie nicht isst?
7. An welchem Tag ist der Wocheneinkauf? (Annahme: Samstag, passend zu den Vorschlägen.)
8. Stammen „Honighähnchen“ und „Brathähnchen mit Miso“ wirklich aus Jamie Olivers ONE, und auf welchen Seiten? Seitenzahlen für die anderen verknüpften Rezepte?
9. Fehlende Autoren/Verlage der Kochbücher (oder ISBNs von der Buchrückseite).
10. Wunsch-Domain bzw. Projektname auf Vercel?
