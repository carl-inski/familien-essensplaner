# Gnocchi für iPhone (SwiftUI)

Native App zur Web-App im übergeordneten Ordner. Gleiche Datenbank (Supabase), gleiche Regeln.

## Aufbau
- `Packages/GnocchiCore/` – Regeln ohne Oberfläche (Spiele, Einkauf, Planänderungen). Gegenstück zu `../lib/*.ts`.
- `Gnocchi/` – die App: `App/` (Einstieg), `Features/<Bereich>/` (Bildschirme), `Services/` (Supabase, Sitzung).
- `project.yml` – das Xcode-Projekt als Text. `Gnocchi.xcodeproj` ist erzeugt und nicht im Repo.

## Regeln
- **Logik gehört nach GnocchiCore**, nie in Views. Jede Funktion dort hat ein TypeScript-Gegenstück in `../lib/`; Namen und Verhalten gleich halten.
- **Gleichlauf mit der Web-App ist Pflicht** für alles, was auf mehreren Geräten zusammen gerechnet wird (Zufall mit Seed, Spielregeln, Takt). Erwartungswerte dafür direkt aus dem TypeScript-Code erzeugen (`npx tsx`), nicht von Hand ausrechnen. Beispiel: `Tests/GnocchiCoreTests/ParityTests.swift`.
- **Änderung an einer Regel:** zuerst in `../lib/*.ts` mit Test, dann hier nachziehen, dann beide Testläufe.
- SwiftUI mit Observation (`@Observable`), keine Combine-Neuentwicklung. Swift 6, strikte Nebenläufigkeit. Ab iOS 17; iOS-26-APIs (Liquid Glass) nur hinter `if #available(iOS 26, *)`.
- Texte auf Deutsch, Ton wie in der Web-App. Gestaltung nach dem Skill `apple-design`.
- Datenbank nie aus der App heraus verändern (kein DDL). Neue Tabellen/Funktionen als Migration in `../supabase/migrations/`, wie in `../CLAUDE.md` beschrieben.
- Kein Supabase Secret Key in der App. Der Publishable Key in `Services/SupabaseClient.swift` ist öffentlich.

## Bauen und prüfen
- Nach Änderungen an `project.yml`: `scripts/bootstrap.sh`.
- Logik testen (geht auch ohne Xcode): `scripts/test-core.sh`. Web-Seite: `npm test` im Hauptordner.
- App bauen, testen, im Simulator starten: über die MCP-Werkzeuge von **MobileBuildMCP** (Sentry), nicht mit rohem `xcodebuild`.
- SwiftUI-Previews ansehen, Fehler lesen, Apple-Doku suchen: über den **xcode**-MCP (`xcrun mcpbridge`, Xcode muss offen sein).
- Ansehen und antippen in der Claude-Desktop-App: iOS-Simulator-Werkzeug (`attach`, dann `screenshot`, `tap`).
- Jede sichtbare Änderung endet mit einem Screenshot aus dem Simulator.

## Vor dem App Store
- Bundle-ID `app.gnocchi.ios` durch eine eigene ersetzen, Entwicklerteam in `project.yml` eintragen.
- App-Icon (1024×1024) in `Gnocchi/Resources/Assets.xcassets/AppIcon.appiconset`.
- Konto in der App löschen können (Apple-Regel 5.1.1), Datenschutzerklärung, Testkonto für die Prüfer.
