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
| Einkauf | Wochenliste skaliert und summiert, nach Supermarkt-Bereich gruppiert, abhakbar, „In Bring übernehmen“, als Text kopieren |
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

## Bring!

Kein inoffizieller Client: Die App öffnet `https://api.getbring.com/rest/bringrecipes/deeplink?url=<öffentliche Seite>&source=web`. Bring! liest dort das JSON-LD (`recipeIngredient` mit bereits skalierten Mengen, beim Wocheneinkauf `recipeYield = "1"`).

## KI

Alle Aufrufe laufen serverseitig in `/api/ai/*` über das Vercel AI SDK (`lib/ai/`), mit der Session des Nutzers (RLS gilt).

- **Anbieter wechseln:** `LLM_PROVIDER` = `anthropic` (Standard, Modell `claude-haiku-5-5`), `openai-compatible` (Groq, OpenRouter …, braucht `LLM_BASE_URL` und `LLM_MODEL`), `mock` (feste Antworten für Tests, kostenlos) oder `off`. Bild- und Stark-Modell über `LLM_VISION_MODEL` / `LLM_MODEL_STRONG`.
- **Limits:** `AI_DAILY_CALL_LIMIT` Anfragen pro Person und Tag, `AI_MONTHLY_BUDGET_EUR` pro Haushalt und Monat (Berliner Zeit). Jeder Aufruf landet mit Tokens und geschätzten Kosten in `ep_ai_usage`; Preise über `AI_PRICE_*`.
- **Cache:** `ep_ai_cache` pro Haushalt und Eingabe-Hash – gleiche URL oder gleiches Bild kostet nichts.
- **Anzeige und Test:** Haushalt → „KI“ zeigt Modell, Verbrauch im Monat und einen Verbindungstest.
- Inhalte von Webseiten und Fotos gehen nur als markierte Daten an das Modell (`lib/ai/prompts.ts`).
