# gnocchi (Familien-Essensplaner)

Lies zuerst [AGENTS.md](AGENTS.md) (Next.js-Hinweise) und [README.md](README.md) (Stack, Datenbank, Konten).

- **Kernablauf:** Wer mitisst → Wochenplan → Einkaufsliste. Ändert sich der Plan, zeigt die Liste nur, was noch fehlt, und alle sehen denselben Stand.
- **Wohin es geht:** [docs/ROADMAP.md](docs/ROADMAP.md), Begründung in [docs/gnocchi-startup-bericht.md](docs/gnocchi-startup-bericht.md).
- **Regeln als reine Funktionen** mit Tests: Einkauf in `lib/planning.ts` und `lib/shopping.ts`, Vorschläge in `lib/suggest.ts`, Spiele in `lib/decide.ts`.
- **Vor jedem Commit:** `npm run lint`, `npm test`, `npx next build`.
- **Datenbank:** Das Supabase-Projekt ist produktiv und mit anderen Apps geteilt. Migrationen nur additiv, erst in einer zurückgerollten Transaktion durchspielen. Alle Objekte tragen das Präfix `ep_`.
- Änderungen an Familien, Käufen oder Bezahlung prüft ein Mensch, bevor sie live gehen.
