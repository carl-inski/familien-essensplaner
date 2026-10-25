# Familien-Essensplaner

Web-App (PWA) für die Familie (Paul, Anton, Carl, Vroni, Christian): Wochenübersicht, wer zuhause ist, Essensplan, Kochdienst, Rezeptsammlung, Kochbücher, Kochhistorie und Wocheneinkauf mit Übergabe an Bring!.

Der vollständige Bau-Auftrag steht in [`docs/BRIEFING.md`](docs/BRIEFING.md), die Startdaten in [`data/rezeptsammlung.md`](data/rezeptsammlung.md).

## Stack

- **Next.js 16** (App Router, TypeScript, Tailwind v4) auf **Vercel**
- **Supabase**: Postgres mit RLS, Auth per E-Mail + Passwort, Realtime (Anwesenheit, Plan, Historie), Storage (`ep-images`)
- **Motion** für federnde, unterbrechbare Sheets (Apple-Interaktionsprinzipien: Feedback beim Antippen, 1:1-Ziehen, Momentum-Projektion, Reduce Motion/Transparency)
- **Vitest** für Parser, Skalierung, Vorschlagsregeln und Kochhistorie

## Funktionen (MVP)

| Bereich | Was geht |
| --- | --- |
| Woche | Tag × Mittag + Abend, Anwesenheit pro Mahlzeit mit einem Tipp, Gäste, Standardwoche (je Mahlzeit), Esserzahl, Rezept einplanen (2 Tipps), „Vorschlag“ (regelbasiert), Reste-Slots, Kochdienst (nur Anwesende, sonst „Koch fehlt“), gekocht ✓ / Rückgängig, Realtime |
| Rezepte | Karten, Suche (deutscher Volltext + Trigramm + Zutaten), kombinierbare Filter und Sortierung, Detail mit Portionswähler, Bring!-Export, Historie, Anlegen/Bearbeiten mit Foto, Markdown-Import mit Duplikat-Erkennung und Export |
| Lange nicht gegessen | sortiert nach Tagen seit dem letzten Kochen, darunter „Noch nie gekocht“, direkt einplanbar |
| Regal | Kochbücher als Cover-Raster, ISBN-Abfrage (Open Library → Google Books), Rezept-Verknüpfungen mit Seite, „zu bestätigen“, reine Verweis-Rezepte |
| Einkauf | Alle kommenden Gerichte ab heute, über Wochengrenzen hinweg, skaliert und summiert, in Gang-Reihenfolge; wählbar „bis Tag X“ oder pro Gericht. „Einkauf erledigt“ merkt pro Gericht `shopped_at` – beim nächsten Einkauf fehlen diese Zutaten, im Wochenplan steht „eingekauft ✓“; wird ein Gericht getauscht, kommt es von selbst zurück. Nicht Abgehaktes kann unter „Noch offen“ bleiben, dort lässt sich auch frei dazuschreiben (`ep_shopping_extra`). „Immer zu Hause“ blendet Vorrat wie Salz und Pfeffer aus (`ep_pantry`); US-Maße werden fest umgerechnet – alles ohne KI. „In Bring übernehmen“, als Text kopieren |
| Haushalt | Mitglieder und Einladungen per E-Mail, Standardwoche, Kochdienst-Zähler (4 Wochen) |
| Öffentlich | `/r/<slug>` und `/einkauf/<slug>` mit schema.org/Recipe-JSON-LD für den Bring!-Import, `noindex` |

KI-Funktionen (Briefing Abschnitt 6) entstehen in Stufen, siehe „KI“ unten. Ohne API-Schlüssel zeigt die App „KI noch nicht eingerichtet“.

## Lokales Setup

```bash
npm install
cp .env.example .env.local   # Supabase-URL und Publishable Key eintragen
npm run dev                  # http://localhost:3000
npm test                     # Unit-Tests
```

## Datenbank

Alle Tabellen tragen das Präfix `ep_`, weil die App sich ein Supabase-Projekt mit anderen Apps teilt.

- Schema, RLS, Trigger, View und RPCs: `supabase/migrations/*.sql` (in Reihenfolge ausführen)
- Startdaten: `npx tsx scripts/seed.ts > supabase/seed.sql`, dann `supabase/seed.sql` im SQL-Editor ausführen und die Admin-E-Mail setzen:
  `update ep_members set email = '<mail>' where name = 'Carl';`

Zugang: Login mit E-Mail und Passwort, ohne Mailversand. Admins legen unter „Haushalt“ für jedes Mitglied E-Mail und Passwort fest (RPC `ep_admin_set_password`), jede Person kann ihr Passwort danach selbst ändern. Wer nicht eingetragen ist, sieht nichts.

Den ersten Admin richtet man im SQL-Editor ein:
`select ep_admin_set_password((select id from ep_members where name = 'Carl'), '<passwort>');`

Optional (Phase 2): Magic Link über `/auth/confirm` – dafür in Supabase unter Authentication → URL Configuration die Domain als Redirect-URL eintragen.

## Deployment (Vercel)

Live: https://familien-essensplaner-umber.vercel.app (Vercel-Projekt `familien-essensplaner`, Region fra1).

Projekt mit dem GitHub-Repo verbinden, Env-Variablen `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` und `NEXT_PUBLIC_SITE_URL` setzen. Die Bring!-Seiten müssen ohne Vercel-Login erreichbar sein; die Produktions-Domain ist das bei Standard-Schutz.

## Schnittstelle für Assistenten

Externe Assistenten (z. B. der „Küchenchef“-Bot) tragen Rezepte ohne Browser-Login ein – im Format von `data/rezeptsammlung.md` oder als JSON. Logik in `lib/api/recipes.ts` (reine Funktionen, Tests in `tests/api-recipes.test.ts`), Routen in `app/api/rezepte/`.

| Endpunkt | Zweck |
|---|---|
| `POST /api/rezepte?modus=neu\|ueberspringen\|ueberschreiben&dry_run=1` | Ein oder mehrere Rezepte anlegen. Body `text/markdown` (`## Titel`-Blöcke, getrennt durch `---`, Inhaltsverzeichnis wird ignoriert) oder `application/json` `{ "rezepte": [ … ] }`. Max. 50 Rezepte bzw. 1 MB. |
| `GET /api/rezepte` | `[{ id, title, updated_at, servings, cookbook_title }]` zum Abgleich |
| `GET /api/rezepte/export` | Ganze Sammlung als Markdown (wie der Export-Button) |

- **Modi:** `neu` (Standard) schreibt bei einem Duplikat nichts und meldet `duplikat` mit der vorhandenen `id` (409, wenn sonst nichts geschrieben wurde); `ueberspringen` lässt Duplikate still aus; `ueberschreiben` aktualisiert das vorhandene Rezept und ersetzt die Zutaten – `id`, `public_slug`, Historie, Notizen, Plan und ein eigenes Foto bleiben. `dry_run=1` parst nur und zeigt die Entwürfe.
- **Duplikate** über `normalizeTitle()` (klein, `&` = „und“, ohne Satzzeichen; Klammerzusätze zählen mit) – dieselbe Funktion nutzt die Import-Seite.
- **Kochbuch:** `**Kochbuch:** Titel, S. 12` wird gegen das Regal abgeglichen (Treffer = bestätigt); unbekannte Bücher werden mit „Über API angelegt – zu bestätigen“ angelegt und unbestätigt verknüpft. Ohne Angabe gibt es höchstens einen unbestätigten Vorschlag.
- **Antwort:** `{ "ergebnisse": [{ "titel", "status": "angelegt|aktualisiert|uebersprungen|duplikat|fehler", "id", "url", "fehler"? }] }` – ein fehlerhaftes Rezept bricht den Stapel nicht ab. Status 201 (etwas angelegt), 200, 409 (nur Duplikate), 422 (nur Fehler), 401/503 bei Auth.
- **Sicherheit:** `Authorization: Bearer <RECIPES_API_TOKEN>`, Vergleich in konstanter Zeit. Geschrieben wird ausschließlich über die security-definer-RPCs `ep_api_snapshot` / `ep_api_save_recipe` (Migration `20261024190000_recipes_api.sql`): Sie prüfen den sha256-Hash des Tokens gegen `ep_api_tokens` und arbeiten nur im Haushalt dieses Tokens; `household_id` aus dem Body wird verworfen. Rezept und Zutaten werden in einer Transaktion geschrieben. Bewusst kein `sb_secret`-Key: Das Supabase-Projekt ist geteilt, ein Secret Key würde RLS für alle Tabellen umgehen. Nur Rezepte und Kochbücher – kein Plan, keine Anwesenheit, kein Löschen.
- **Neuen Token anlegen:** `openssl rand -hex 32`, den Wert als `RECIPES_API_TOKEN` in Vercel setzen und den Hash eintragen: `insert into ep_api_tokens (household_id, label, token_hash) values ('<haushalt>', 'Küchenchef', encode(extensions.digest('<token>', 'sha256'), 'hex'));`

```bash
curl -X POST "$SITE/api/rezepte?modus=neu" \
  -H "Authorization: Bearer $RECIPES_API_TOKEN" \
  -H "Content-Type: text/markdown" \
  --data-binary @rezept.md
```

## Bring!

Kein inoffizieller Client: Die App öffnet `https://api.getbring.com/rest/bringrecipes/deeplink?url=<öffentliche Seite>&source=web`. Bring! liest dort das JSON-LD (`recipeIngredient` mit bereits skalierten Mengen, beim Wocheneinkauf `recipeYield = "1"`).

## KI

Alle Aufrufe laufen serverseitig in `/api/ai/*` über das Vercel AI SDK (`lib/ai/`), mit der Session des Nutzers (RLS gilt).

- **Anbieter wechseln:** `LLM_PROVIDER` = `anthropic` (Standard, Modell `claude-haiku-5-5`), `openrouter` (braucht `LLM_API_KEY` von openrouter.ai und `LLM_MODEL`, z. B. ein Anthropic- oder Open-Source-Modell; `AI_PRICE_*` auf dessen Preise setzen), `openai-compatible` (Groq …, braucht `LLM_BASE_URL` und `LLM_MODEL`), `mock` (feste Antworten für Tests, kostenlos) oder `off`. Bild- und Stark-Modell über `LLM_VISION_MODEL` / `LLM_MODEL_STRONG`.
- **Limits:** `AI_DAILY_CALL_LIMIT` Anfragen pro Person und Tag, `AI_MONTHLY_BUDGET_EUR` pro Haushalt und Monat (Berliner Zeit). Jeder Aufruf landet mit Tokens und geschätzten Kosten in `ep_ai_usage`; Preise über `AI_PRICE_*`.
- **Cache:** `ep_ai_cache` pro Haushalt und Eingabe-Hash – gleiche URL oder gleiches Bild kostet nichts.
- **Anzeige und Test:** Haushalt → „KI“ zeigt Modell, Verbrauch im Monat und einen Verbindungstest.
- Inhalte von Webseiten und Fotos gehen nur als markierte Daten an das Modell (`lib/ai/prompts.ts`).
- **Rezept aus Link/Foto** (`/rezepte/neu`): Links zuerst über schema.org-JSON-LD ohne KI, fremdsprachige Rezepte übersetzt die KI; Fotos (1–3) liest die KI ab. Immer als Entwurf zum Prüfen.
- **KI-Tab** (`/assistent`, Route `/api/ai/chat`): liest Rezepte, Woche, Regal und Einkaufsliste selbst; Einplanen, Anwesenheit, Notizen und neue Rezepte schlägt sie als Karte vor – geschrieben wird erst nach „Übernehmen“ im Browser (`components/assistant/confirm-card.tsx`). Haushalt liegt jetzt hinter dem Avatar oben rechts.
- **Wochenvorschläge und „Was koche ich damit?“ nur im Chat:** `vorschlaege_finden` liefert pro offener Mahlzeit Kandidaten aus der Regel-Engine (Fleischregel, 14-Tage-Sperre, abends keine Snacks, kürzlich Abgelehntes raus); die KI wählt aus und schlägt alles auf einer Karte vor (`mehrere_einplanen`), die den Stapel noch einmal gegen die Regeln prüft. `rezepte_mit_zutaten` bewertet die Sammlung nach vorhandenen Zutaten (`lib/leftovers.ts`).
