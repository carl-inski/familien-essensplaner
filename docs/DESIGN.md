# Gnocchi-Gestaltung

## Farbpalette der iPhone-App

| Farbe | Hell | Dunkel | Einsatz |
| --- | --- | --- | --- |
| Schwarz / Tinte | `#141417` | `#F6F6F8` | Texte, Fortschrittsringe, Hauptaktionen |
| Weiß / Karten | `#FFFFFF` | `#1D1D22` | Karten, Gruppen und Formulare |
| Hintergrund | `#F6F6F8` | `#121215` | Bildschirmflächen |
| Nebelgrau | `#EDEDF1` | `#2A2A31` | Felder, Auswahlflächen, leere Ringe |
| Graphit | `#60616B` | `#AAABB5` | Sekundärtext |
| Indigo | `#514DB3` | `#AEAAFF` | Auswahl, Links und Interaktion |
| Grün | `#23735D` | `#76CFAD` | Erledigt und bestätigt |

Die Tab-Leiste ist deckend weiß. Der separate KI-Knopf ist in beiden Modi schwarz mit weißem Symbol. Rezept- und Buchdetails erhalten einen dunklen Farbton aus ihrem Foto. Die aktive App-Palette steht in `ios/Gnocchi/Design/Theme.swift` und `AccentColor.colorset`. Die Website definiert ihre Farben in `app/globals.css`.

## Bausteine

| Baustein | Datei | Zweck |
| --- | --- | --- |
| `Theme` | `Design/Theme.swift` | Farben, Radien, Schrift und Federn |
| `.gnScreen()`, `.gnCard()` | `Design/Theme.swift` | Bildschirmhintergrund und Karten |
| `.ink`, `.soft` | `Design/Components.swift` | Haupt- und Nebenaktionen |
| `ProgressRing` | `Design/Components.swift` | Fortschritt im Wochenplan |
| `PhotoCard` | `Design/PhotoCard.swift` | Foto mit Verlauf und Text für Rezepte, Bücher, Einkauf und Spiele |
| `IngredientIcon` | `Design/IngredientIcon.swift` | Zutatenmotive in Rezept und Einkauf |

## Woche, Rezepte und Regal

- Die Woche zeigt sieben Tagesringe, die Anzahl geplanter Tage und alle Tage untereinander. Ein Tipp auf einen Tagesring scrollt zum passenden Abschnitt. Weitere Mahlzeiten kommen über das Plus des Tages hinzu.
- Rezeptkacheln lassen sich aufeinanderziehen und gestapelt seitlich durchblättern. Oben im Raster steht die Kachel zum Hinzufügen. Ordner geben dem Raster seinen Titel.
- Bücher und Rezepte öffnen mit Foto oder Cover im Vollbild. Die Navigation bleibt über dem Foto sichtbar. Die Tab-Leiste ist dort ausgeblendet.

## Onboarding

Begrüßung → drei Fragen (Haushaltsgröße, was nervt, wie oft gekocht wird) → Zusammenfassung → Konto. Die Antworten bleiben auf dem Gerät und passen nur die Zusammenfassung an. Nach dem Anmelden: Familie anlegen oder beitreten. Ansehen ohne Konto: Startargument `--demo-welcome`.

## Vorbilder (Mobbin)

- Aussehen: Bond (Kacheln), Fuse (Einstellungen), [Cal AI](https://mobbin.com/screens/d2cc8836-9246-4ecd-90eb-00a6b6e7fc40), [Bevel](https://mobbin.com/screens/25b9fe4f-75e9-4341-b9cd-4905f17fda56), [Joi](https://mobbin.com/screens/362e5a69-9886-49b8-be3e-a260377a8681), [Luma](https://mobbin.com/screens/fc225571-3761-4e53-96d8-ae3ad2d5ecd0)
- Onboarding: [Cal AI](https://mobbin.com/flows/05ca2ff4-106a-4fda-a0dd-3cc9b73a83c1), [Duolingo](https://mobbin.com/flows/b0b4f93f-5637-46ec-9d77-49ecda6b991d), [Fuse](https://mobbin.com/screens/58455ad2-5a59-4e5a-92df-2072fd62cdec)
- Besondere Momente: [Duolingo](https://mobbin.com/screens/f6675d16-c6b5-4847-aa9f-fb66a2d61e88), [Phantom](https://mobbin.com/screens/b592f6b4-90d9-4af8-9e06-d7742969a947), [Pool](https://mobbin.com/screens/83cdb043-2963-4653-b498-b38f5c45df92)
- Website: [Graphical](https://mobbin.com/sites/sections/7aca3939-83ed-4d35-b118-778d68f33891), [Popcorn](https://mobbin.com/sites/sections/616177dd-62ad-4006-b06c-35e422727c66), momeo.ai
