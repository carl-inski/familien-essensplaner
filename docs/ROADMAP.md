# Roadmap

Reihenfolge nach [gnocchi-startup-bericht.md](gnocchi-startup-bericht.md): erst der Kernablauf „Plan ändert sich → Liste stimmt für alle“, dann Pilot mit echten Haushalten, dann genau eine Erweiterung nach Beleg.

| Punkt | Stand | Einordnung |
| --- | --- | --- |
| Wer isst mit, Familie intern, Standardwoche | vorhanden | behalten |
| Mehrere Familien, Einladungscode | gebaut | behalten |
| Rezepte, Ordner, Tags, Import Link/Foto | vorhanden | behalten |
| Abstimmspiele | gebaut, nach Nutzerfeedback überarbeitet | eine offene Runde je Familie, Zeitpunkt erst nach dem Spiel; dazu Tellerjagd und Tauziehen als echte Reaktionsspiele |
| Einkauf passt sich an Planänderung an | **Schritt 1**, gebaut | Käufe je Gericht und Zutat (`ep_purchases`, `lib/shopping.ts`) |
| Gemeinsames Abhaken, Rückgängig, Offline-Status | **Schritt 1**, gebaut | |
| „Heute auswärts“, Verschieben mit Vorschau | **Schritt 2**, gebaut | eine Karte „Was ändert sich?“ für Mensch und KI (`lib/plan-change.ts`, `ep_plan_move`) |
| KI: Plan per Text ändern | **Schritt 2**, gebaut, mit echtem Modell ungetestet | Werkzeug `plan_aendern`, dieselbe Vorschau; offen: Testset mit 30–50 Fällen, sobald ein KI-Schlüssel eingerichtet ist |
| Vorrat | **Schritt 3**, gebaut | „Noch da“ auf der Liste, Vorrat von Hand unter Haushalt, zählt beim Einkauf mit; Scanner, Ablaufdaten, Bon-Import später |
| Launch-Fundament | Schritt 4, **Landingpage gebaut** | offen: echte Fotos (eigene, nicht die Beispielbilder), Impressum und Datenschutz, Onboarding „drei Gerichte“, Messung, eigenes Supabase-Projekt |
| Wrapped | Schritt 5 | drei belegte Fakten nach vier Wochen |
| Kostentracker | später | Bon-Foto-Test nur bei beobachtetem Bedarf |
| Freunde / Events | später | einzelner Gast-Link |
| Community / Feed | später | in Stufen, kein öffentlicher Feed vor wiederholtem Teilen |
| Eigener MCP | später | nur lesen und Entwürfe |
| Händler (REWE, Picnic) | später | Partnergespräch nach Pilot; Bring! und Knuspr Ende-zu-Ende testen |
| WhatsApp | später | nur als Teilen-Link |
| App Store | später | erst bei belegtem Engpass |
| Preismodell | nach Pilot | Plus-Test 4,99 €/Monat oder 49 €/Jahr pro Haushalt |

Nicht im Code: 15 Gespräche, 12 begleitete Haushalte, Vergleichstest gegen Superkitchen und Greezy (Bericht Abschnitt 7 und 11).
