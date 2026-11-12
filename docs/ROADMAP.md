# Roadmap

Reihenfolge nach [gnocchi-startup-bericht.md](gnocchi-startup-bericht.md): erst der Kernablauf „Plan ändert sich → Liste stimmt für alle“, dann Pilot mit echten Haushalten, dann genau eine Erweiterung nach Beleg.

| Punkt | Stand | Einordnung |
| --- | --- | --- |
| Wer isst mit, Familie intern, Standardwoche | vorhanden | behalten |
| Mehrere Familien, Einladungscode | gebaut | behalten |
| Rezepte, Ordner, Tags, Import Link/Foto | vorhanden | behalten |
| Abstimmspiele | gebaut | behalten, kein fünftes Spiel |
| Einkauf passt sich an Planänderung an | **Schritt 1** | Käufe je Gericht und Zutat (`ep_purchases`, `lib/shopping.ts`) |
| Gemeinsames Abhaken, Rückgängig, Offline-Status | **Schritt 1** | |
| „Heute auswärts“, Verschieben mit Vorschau | Schritt 2 | eine Karte „Was ändert sich?“ für Mensch und KI |
| KI: Plan per Text ändern | Schritt 2 | nutzt dieselbe Vorschau, Server prüft neu |
| Vorrat | Schritt 3 | „Ist noch da“ sichtbar; Scanner, Ablaufdaten später |
| Launch-Fundament | Schritt 4 | eigenes Supabase-Projekt, Landingpage, Messung, Rechtliches |
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
