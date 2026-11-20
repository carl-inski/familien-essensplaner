# Rezeptimport

Die native iOS-App und die Web-App bieten Kamera, Fotoauswahl, Web-Link, Social-Link und manuelles Erstellen. Der bestehende Markdown-Import der iOS-App bleibt verfügbar. Alle Importwege erzeugen bearbeitbare Entwürfe; gespeichert wird erst im Rezepteditor.

## Fotos

Bis zu drei Seiten desselben Rezepts in Lesereihenfolge auswählen oder nacheinander aufnehmen. Vorschau und Entfernen sind vor der Übertragung möglich. iOS verwendet den System-Fotopicker ohne vollständigen Bibliothekszugriff und fragt die Kameraberechtigung erst beim Aufnehmen ab. Ohne Kamera wird eine konkrete Alternative angezeigt. Im Web verwendet die Kameraoption den nativen Dateidialog mit `capture="environment"`; die tatsächliche Kameraunterstützung hängt vom Browser/Gerät ab.

Die Clients verkleinern die Fotos zu JPEG. Das Backend begrenzt den gesamten JSON-Request auf 4.300.000 Bytes, prüft Anzahl, Base64 und Bildsignatur und verarbeitet Bilder in Auswahlreihenfolge. Der KI-Dienst muss für Fotoimporte eingerichtet sein.

## Web und Social

`POST /api/ai/recipe-from-url` nimmt `url`, optional `mode: "social"`, `text` und `images: [{ data, mediaType }]` entgegen. Ein einzelner Link darf auch in einem Teilen-Text stehen. Trackingparameter werden entfernt, Inhalts-IDs bleiben erhalten. YouTube-Shorts und youtu.be werden auf die Video-ID normalisiert. Weitergeleitete TikTok-Kurzlinks werden mit der aufgelösten Beitrags-ID ausgewertet.

1. Schema.org/Recipe aus JSON-LD direkt übernehmen. Dafür ist keine KI notwendig.
2. Falls nötig ins Deutsche übersetzen. Schlägt die Übersetzung fehl oder verliert sie Zutaten/Schritte, bleibt das Original erhalten.
3. Bei Instagram, Facebook, TikTok, YouTube und Pinterest öffentliche Beschreibungen und verlinkte Rezeptseiten auswerten. Strukturierte Rezepte auf der Originalseite haben Vorrang. Redaktionelle Rezeptseiten ohne Metadaten werden anhand ihres sichtbaren Inhalts gelesen.
4. Öffentliche Untertitel ergänzen. Ein unvollständiger Entwurf kann zusätzlich aus Ton und Einblendungen vervollständigt werden, wenn der Beitrag einen öffentlich zugänglichen Videoabruf anbietet und `GEMINI_API_KEY` auf dem Server gesetzt ist.
5. Wenn die Quelle zu wenig hergibt, kann der Nutzer optional Text oder Screenshots ergänzen. Bei übernommenen Originalrezepten speichert Gnocchi den Link zur Rezeptseite als Quelle.

Die API liefert bei Erfolg `draft`, `via`, `warnings` und gegebenenfalls `cached`. Fehlende Zutaten, Zubereitung und Mengen werden im Prüfhinweis benannt. Eine unlesbare Quelle liefert HTTP 422 mit `needs_input: true`; die Clients behalten die Eingaben und lassen Ergänzungen zu. Ein reiner Titel oder das fertige Gericht darf keine erfundene Zutatenliste erzeugen. Cache-Schlüssel enthalten die tatsächlichen Texte/Bilder und den optionalen Kochbuchtitel, damit Ergänzungen keinen alten Entwurf wiederverwenden.

## Tatsächliche Grenzen

Im iOS-Demo-Modus liest `POST /api/recipe-source` öffentliche Links ohne Gnocchi-Konto. Der Endpunkt liefert ein strukturiertes Rezept oder Quelltext, öffentliche Untertitel und verfügbare Medien. Er führt keine KI-Anfragen aus. Die App schickt ausgewerteten Inhalt an den ausgewählten Demo-Anbieter, wenn ein Entwurf oder eine Übersetzung nötig ist. Falls Beschreibung und Untertitel nicht ausreichen, kann die App Bildkarten und öffentlich abrufbare Videobilder von Instagram, TikTok und Facebook verwenden.

Der Abruf der Plattformen verwendet öffentliche Adressen. Enthält die Videobeschreibung eine erkennbare Zutatenliste mit Mengen, kann Gnocchi diese als Entwurf mit Hinweis auf die fehlende Zubereitung übernehmen. Bei einem unvollständigen Beitrag kann das Beschreibungsfeld auch einen einzelnen vollständigen Original-Rezeptlink enthalten. Gnocchi speichert in diesem Fall die ergänzte Rezeptseite als Quelle. Als Ergänzung eignen sich auch Rezepttext und Screenshots. Die serverseitige Auswertung von Videoton braucht zusätzlich zum regulären KI-Dienst einen Gemini-API-Schlüssel.

Für einen lokalen iOS-Debug-Build kann `GNOCCHI_RECIPE_SOURCE_BASE_URL` auf einen laufenden Next.js-Server auf `localhost` oder `127.0.0.1` zeigen. Der Empfang des API-Schlüssels ist beim Linkabruf weder erforderlich noch vorgesehen.

Abrufe prüfen alle DNS-Adressen und jede Weiterleitung, binden die Verbindung an die geprüfte IP und begrenzen Zeit und entpackte Größe. Fremde Embed-Skripte werden nicht ausgeführt. Die Videoauswertung erhält nur eine URL des konkreten Videos oder einer freigegebenen Plattform-CDN.

## Öffentlicher Abruf der 25 Testlinks

Die Angaben beschreiben, was der Server ohne Plattformkonto beim ursprünglichen Quellenabruf lesen konnte.

| Plattform | Beispiel | Öffentlich abrufbare Daten |
| --- | --- | --- |
| Instagram | Pesto Pasta | Rezeptcaption |
| Instagram | Tomato Pasta | Rezeptcaption |
| Instagram | Parmesan-Honig-Kartoffeln | Rezeptcaption |
| Instagram | Älplermagronen | Gerichtsbeschreibung und Startseite des Veranstalters. Keine Zutatenmengen oder direkte Rezeptseite |
| Instagram | Spätzle | Verlinkte Rezeptseite mit 4 Zutaten und 7 Schritten |
| TikTok | Garlic Butter Ditalini | Zutaten und Schritte in der Caption |
| TikTok | One Pot Lasagna | Rezeptcaption |
| TikTok | Martha Stewart One-Pan Pasta | Caption, abrufbare Untertitel und öffentlich gelistete Videoadresse |
| TikTok | Bratkartoffeln mit Speck | Zutaten in der Caption, abrufbare Untertitel und öffentlich gelistete Videoadresse |
| TikTok | Taktouka | Zutaten und Schritte in der Caption, abrufbare Untertitel |
| YouTube | Feta One-Pot-Pasta | Zutaten in der Beschreibung. Untertitelabruf lieferte keinen Text |
| YouTube | REWE Gefüllter Kürbis | Zusammenfassung der Schritte in der Beschreibung |
| YouTube | Fettuccine Alfredo | Verlinkte Rezeptseite mit 5 Zutaten und 2 Schritten |
| YouTube | Marry Me Chicken | Öffentlicher Videolink. Beschreibung ohne Rezept, Untertitelabruf ohne Text |
| YouTube | Chefkoch Carbonara | Zutaten und Schritte in der Beschreibung |
| Pinterest | Spätzle | Verlinkte Rezeptseite mit 5 Zutaten und 4 Schritten |
| Pinterest | Maultaschen | Verlinkte Rezeptseite mit 21 Zutaten und 7 Schritten |
| Pinterest | Lachsnudeln | BR-Originalartikel mit Zutaten und Anleitung im Seitentext |
| Pinterest | Thunfisch-One-Pot | Verlinkte Rezeptseite mit 6 Zutaten und 2 Schritten |
| Pinterest | Dijon Baked Salmon | Verlinkte Rezeptseite mit 7 Zutaten und 3 Schritten |
| Facebook | Bananenkuchen | Verlinkte Rezeptseite mit 7 Zutaten und 3 Schritten |
| Facebook | Linsen mit Spätzle | Verlinkte Rezeptseite mit 14 Zutaten und 3 Schritten |
| Facebook | Süßes Risotto | Vollständiger Beitragstext mit Zutaten und Anleitung |
| Facebook | Real Simple One-Pot Pasta | Kein lesbarer Beitragstext und keine Videodaten im öffentlichen Abruf |
| Facebook | Creamy Tomato Pasta | Beitragstext, abrufbare Untertitel und öffentlich gelistete Videoadresse. Vollständige Rezeptdaten aus dem Video noch offen |

Prüfen: `npm test`, `npm run lint`, `npx tsc --noEmit`, `npx next build --webpack`; App über MobileBuildMCP bauen und testen. Turbopack scheiterte in dieser Umgebung an Portrechten, der Webpack-Produktionsbuild war erfolgreich.

Aktuelle Plattformreferenzen: [Meta oEmbed](https://developers.facebook.com/docs/graph-api/reference/oembed-post), [Instagram oEmbed](https://developers.facebook.com/docs/graph-api/reference/instagram-oembed/), [TikTok Embed](https://developers.tiktok.com/docs/en/embed-videos), [YouTube Captions](https://developers.google.com/youtube/v3/guides/implementation/captions), [Pinterest Recipe Rich Pins](https://developer.pinterest.com/docs/web-features/recipe-rich-pins/) und [Gemini Video Understanding](https://ai.google.dev/gemini-api/docs/generate-content/video-understanding).
