# Launch-Checkliste (Ziel: 10.000+ Nutzer)

Annahme: 10.000 Konten ≈ 3.500 Familien, abends bis ~1.000 gleichzeitig online.
Zahlen zu Tarifen und Limits vor dem Start in den Dashboards prüfen – sie ändern sich.

## Im Code erledigt (Branch `launch-vorbereitung`)

| Was | Wo | Warum |
| --- | --- | --- |
| Realtime als Broadcast je Familie | Migration `20261119100000_realtime_haushalt.sql`, `components/use-household-changes.ts`, `ios/Gnocchi/Services/SupabaseClient.swift` | Vorher hörten alle Geräte ungefiltert auf ganze Tabellen: jede Änderung wurde gegen die RLS jedes Geräts geprüft, Löschungen gingen an alle. Jetzt ein privater Kanal `ep:household:<id>`, ein Trigger pro Anweisung, Nachladen gebündelt (250 ms). Fällt automatisch auf gefilterte `postgres_changes` zurück, solange die Migration fehlt. |
| Fehlende Fremdschlüssel-Indizes | `20261119101000_launch_indizes.sql` | Vom Supabase-Advisor gemeldet. |
| Konto löschen (Web + iPhone) | `20261119102000_konto_loeschen.sql`, Haushalt-Seite, `AccountView.swift` | DSGVO Art. 17, App-Store-Regel 5.1.1. **Menschliche Prüfung nötig** (betrifft Familien). |
| `/api/recipe-source` nur angemeldet | Route, `proxy.ts`, `RecipeImport.swift` | War ein offener Abrufdienst für beliebige Links. |
| Impressum, Datenschutz | `/impressum`, `/datenschutz`, `lib/legal.ts` | Angaben kommen aus `NEXT_PUBLIC_LEGAL_*`; ohne sie steht „[bitte ergänzen]“. Datenschutztext ist ein Entwurf. |
| Sicherheits-Header | `next.config.ts` | HSTS, nosniff, Frame-Verbot, Referrer- und Permissions-Policy. |
| Health-Check | `GET /api/health` | Für Uptime-Monitor; 503, wenn Supabase nicht antwortet. |
| Lasttest | `scripts/loadtest.k6.js` | bis 1.500 virtuelle Nutzer, nur lesend. |

**Stand 20.11.2026:** Realtime- und Index-Migration sind in Produktion eingespielt und live geprüft: Änderung in der Datenbank → private Nachricht an genau eine Familie → Einkaufsliste lädt einmal nach; ein Konto einer anderen Familie kann das Thema nicht lesen (RLS). Die Konto-Löschen-Migration ist nur in einer zurückgerollten Transaktion getestet und **noch nicht eingespielt**.

## Reihenfolge beim Ausrollen

1. ~~Next.js auf 16.4.6 heben~~ erledigt (16.4.3 hatte GHSA-mfr8-8qww-v76h und GHSA-vc7v-qv4w-wrv8; `npm audit` jetzt 0).
2. Konto-Löschen-Migration von einem Menschen prüfen lassen.
3. ~~Realtime- und Index-Migration einspielen~~ erledigt. Nach Prüfung `20261119102000_konto_loeschen.sql` einspielen – vorher zeigt „Konto löschen“ einen Fehler.
4. Web deployen, in zwei Browsern prüfen: Haken im Einkauf erscheint beim anderen.
5. iPhone-Build mit neuer Realtime- und Login-Pflicht für den Linkabruf verteilen (alte Builds bekommen beim Linkimport 401 und werden nicht mehr live aktualisiert, laden aber weiter per Fokus/8-s-Abfrage).
6. Nach einigen Wochen, wenn keine alten App-Versionen mehr laufen: Tabellen aus der Publikation `supabase_realtime` nehmen (eigene Migration).

## Offen – nur im Dashboard oder durch dich

### Supabase (wichtigster Punkt)
- [ ] **Eigenes Projekt für Gnocchi.** Das jetzige teilt sich Datenbank, Verbindungen, Realtime-Kontingent und Advisor mit `kuo_*`, `zela_*`, Wiesnfinder usw. Ein Lastspitze dort trifft Gnocchi und umgekehrt. Danach `ep_`-Schema per Migrationen neu aufsetzen, Daten mit `pg_dump --table='public.ep_*'` übernehmen, URL/Key in Vercel und `ios/Gnocchi/Services/SupabaseClient.swift` tauschen.
- [ ] Pro-Plan, Compute mindestens **Small**, besser Medium; Spend Cap bewusst setzen.
- [ ] Realtime-Limits prüfen: gleichzeitige Verbindungen (Pro-Standard 500) für ~1.000 Geräte anheben lassen bzw. Spend Cap aus.
- [ ] **Eigenes SMTP** (z. B. Resend, Postmark). Der eingebaute Mailversand schafft nur wenige Mails pro Stunde – bei einem Launch scheitern Registrierung und „Passwort vergessen“ sofort.
- [ ] Auth: „Leaked Password Protection“ an (Advisor-Warnung), CAPTCHA (Turnstile/hCaptcha) für Registrierung und Login, Rate Limits unter Auth → Rate Limits prüfen.
- [ ] URL Configuration: Produktionsdomain und `gnocchi://auth/confirm`, `gnocchi://auth/recovery`.
- [ ] Point-in-Time-Recovery (PITR) an, Wiederherstellung einmal üben.
- [ ] Storage: Bilder gelöschter Familien (`ep-images/<haushalt>/…`) regelmäßig aufräumen (Job mit Service-Key außerhalb des Clients, z. B. Edge Function per Cron).

### Vercel
- [ ] Pro-Plan (Hobby ist nicht für kommerzielle Nutzung).
- [ ] Eigene Domain, `NEXT_PUBLIC_SITE_URL` darauf setzen (auch in der iOS-App `Backend.site`).
- [ ] `NEXT_PUBLIC_LEGAL_NAME`, `NEXT_PUBLIC_LEGAL_ADDRESS`, `NEXT_PUBLIC_LEGAL_EMAIL` setzen.
- [ ] Firewall: Rate-Limit-Regel für `/api/*` (z. B. 60/min je IP) und `/login`; Attack Challenge Mode kennen.
- [ ] Spend Management mit Benachrichtigung.
- [ ] Log Drain oder Observability und Fehler-Tracking (z. B. Sentry), Uptime-Monitor auf `/api/health`.

### KI-Kosten
- [ ] Budget-Grenze pro Familie ist 5 €/Monat. Schlimmster Fall bei 3.500 Familien: ~17.500 €/Monat. Darum im Anbieter-Konto (Anthropic/OpenRouter) ein hartes Monatslimit setzen und `AI_MONTHLY_BUDGET_EUR` für kostenlose Familien senken (z. B. 1 €).
- [ ] Gemini-Schlüssel ebenfalls mit Kontingent.

### Recht
- [ ] Datenschutzerklärung juristisch prüfen, AVV mit Vercel, Supabase, KI-Anbieter abschließen.
- [ ] Verzeichnis der Verarbeitungstätigkeiten.

### Vor dem Start testen
- [ ] Lasttest gegen Preview + eigenes Supabase-Projekt (`scripts/loadtest.k6.js`), Ziel: Fehler < 1 %, p95 Seiten < 1,2 s, REST < 400 ms.
- [ ] Zwei Familien parallel: Realtime erreicht nur die eigene (Kanal einer fremden Familie wird abgelehnt).
- [ ] Konto löschen mit drei Fällen: einziges Mitglied, einziger Admin mit weiteren Mitgliedern, normales Mitglied.
