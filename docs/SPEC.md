# CleverSwitch — Verhaltens-Spezifikation

> Dies ist eine **Clean-Room-Anforderungsspezifikation**: Sie beschreibt das *Verhalten*,
> das CleverSwitch liefern soll, abgeleitet aus beobachtetem Funktionsumfang und öffentlichen
> API-Fakten. CleverSwitch ist eine **eigenständige Neuimplementierung** — es wird kein
> fremder Quellcode übernommen. Implementiert wird ausschließlich gegen diese Spec.

## Zweck

CleverSwitch ist ein macOS-Menüleisten-Tool, das mehrere Accounts derselben KI-Coding-CLI
verwaltet (Claude Code, Codex CLI) und die *aktive* Sitzung per Klick zwischen ihnen umschaltet.
Zielgruppe: Entwickler mit mehreren Abos, die an Rate-Limits stoßen.

## Kernkonzept

Jede CLI liest ihre Anmeldedaten aus genau einem Ort (Claude: macOS-Keychain-Eintrag
`Claude Code-credentials`; Codex: Datei `~/.codex/auth.json`). CleverSwitch hält von jedem
verwalteten Account eine Kopie der Credentials in einem eigenen, klar benannten Speicher und
*tauscht* beim Umschalten die Kopie des Ziel-Accounts in den Live-Slot ein.

## Funktionale Anforderungen

### F1 — Account-Verwaltung
- Mehrere Accounts pro Anbieter speichern (Hinzufügen via offiziellem CLI-Login-Flow, Entfernen).
- Genau ein Account pro Anbieter ist „aktiv" (= dessen Credentials liegen im Live-Slot).
- Account-Liste + App-Einstellungen werden lokal als JSON persistiert (keine Secrets in der Liste).
- Beim Hinzufügen eines Accounts darf der zuvor aktive Account **nicht serverseitig abgemeldet**
  werden (nur lokaler Live-Slot wird aufgeräumt) — sonst wird dessen gespeicherte Sitzung ungültig.
- Der CLI-Login läuft **unsichtbar im Hintergrund** (kein Terminal-Fenster): der Login-Prozess wird
  als normaler Subprozess ohne TTY gestartet (`stdin = /dev/null` — die CLI pollt dann, statt auf
  Eingabe zu blockieren), der Browser öffnet sich von selbst, der Prozess schließt den
  Flow ohne weitere Eingabe ab. Nach erfolgreichem Login wird der neue Account **automatisch
  importiert und aktiv gesetzt** (kein manueller Folgeschritt).
- Beim App-Start wird der Live-Slot mit der Account-Liste **abgeglichen** (Reconcile): ist im
  Live-Slot eine Identität eingeloggt, die nicht (oder nicht als aktiv) in der Liste steht, wird
  sie importiert bzw. aktiv markiert — externe `auth login`-Aufrufe gehen so nicht verloren.

### F2 — Umschalten
- Per Menüklick die aktive Sitzung auf einen gespeicherten Account wechseln.
- Vor dem Aktivieren wird ein abgelaufener Token des Ziels erneuert (siehe F4); nur ein
  gültiger Token landet im Live-Slot. Schlägt die Erneuerung endgültig fehl, klare Meldung
  „Sitzung abgelaufen, bitte neu anmelden" statt eines kaputten Logins.

### F3 — Usage-Anzeige
- Pro Account zwei Auslastungs-Fenster anzeigen: `session` (rollendes 5-Stunden-Limit, das
  bindende Session-Limit) und `weekly` (7-Tage-Limit), jeweils in Prozent + „resets in".
- Auslastung wird über den jeweiligen Anbieter-Usage-Endpoint pro Account-Token abgefragt.
- Inaktive Accounts liefern volle Usage (über ihren gespeicherten Token), nicht nur der aktive.

### F4 — Token-Erneuerung (OAuth)
- Abgelaufene Access-Tokens werden via Refresh-Token am OAuth-Token-Endpoint erneuert und
  der erneuerte Blob zurückgespeichert.
- Erneuerung wird ausgelöst (a) proaktiv bei abgelaufenem Zeitstempel und (b) reaktiv bei
  einer 401-Antwort (Token vor Ablauf widerrufen).
- Transiente Fehler (z.B. 429 Rate-Limit) gelten NICHT als „abgelaufen" — nur als
  vorübergehend; nur ein endgültig ungültiger Refresh-Token gilt als tot.

### F5 — Auto-Switch (Policy)
Pro Anbieter drei Modi:
- **off** — kein automatisches Umschalten.
- **failover** — schaltet *rechtzeitig vor* dem Limit (Standard: Session ≥ 85 % oder
  Weekly ≥ 92 %) auf einen gesunden Account, sofern einer existiert.
- **balance** — verteilt Verbrauch gleichmäßig: führt stets auf dem am wenigsten ausgelasteten
  gesunden Account, wechselt aber erst ab einer Mindestdifferenz (Hysterese, Standard 12 pp)
  bzw. bei Erreichen einer Obergrenze.
- Ein Account taugt nur als Ziel, wenn er in **beiden** Fenstern genug Luft hat (Standard:
  Session < 70 %, Weekly < 90 %) — sonst kippt er sofort zurück.
- Anti-Flattern: zeitlicher Cooldown zwischen Switches + Hysterese in der Entscheidung.
- Frühwarnung (einmal pro Engpass), wenn das aktive Konto nahe am Limit ist und kein gesunder
  Ziel-Account verfügbar ist.

### F6 — Bedienung
- Menüleisten-Menü mit Accounts (aktiver markiert), Usage je Account, Auto-Switch-Modus pro
  Anbieter, Add/Remove, manuelles Usage-Refresh.
- Periodischer Usage-Refresh (Standard alle 5 Minuten) im Hintergrund.

## Nicht-Ziele
- Kein transparenter Request-Proxy/Router (dafür gibt es dedizierte Lösungen).
- Kein €-Cost-Accounting (Flat-Abos haben keinen marginalen Request-Preis).
- Kein Server, kein Team-Dashboard.

## Plattform / Stack
- macOS 14+, Swift 6, SwiftUI `MenuBarExtra`; Build über SwiftPM (kein Xcode-Projekt),
  Paketierung über `packaging/assemble-app.sh` (LSUIElement-Bundle, ad-hoc signiert).
- HTTP über `URLSession`; Keychain über das macOS-`security`-CLI (Subprozess).
- Keine externen Laufzeit-Abhängigkeiten.

## Provider-Abstraktion
Anbieter-spezifisches Verhalten (wo liegen Credentials, wie sieht der Token-Blob aus, welche
Endpoints, wie wird Usage gemappt) steckt hinter einem `Provider`-Protokoll; die Kernlogik
(Policy, Switch-Orchestrierung, Persistenz) ist anbieter-neutral.

## Anbieter-Fakten (öffentlich beobachtbare API-/Datei-Fakten)

### Claude Code
- Live-Slot: Keychain generic password, Service `Claude Code-credentials`. Blob-JSON:
  `{"claudeAiOauth": {accessToken, refreshToken, expiresAt(ms), subscriptionType, ...}}`.
- Identität der aktiven Sitzung: `~/.claude.json` → `oauthAccount.emailAddress`. Beim Umschalten
  wird `oauthAccount` passend zum aktivierten Account zurückgeschrieben.
- Token-Refresh: POST `https://platform.claude.com/v1/oauth/token` (JSON-Body,
  grant_type=refresh_token, client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`); der Endpoint
  verlangt einen `claude-code/...`-User-Agent (Bot-Schutz). 429 = transient.
- Usage: GET `https://api.anthropic.com/oauth/usage` (Bearer, `anthropic-beta: oauth-2025-04-20`);
  Antwort `five_hour`/`seven_day` mit `utilization` (%) und `resets_at` (ISO).
- Login-Befehl: `claude auth login` (öffnet Browser, schließt ohne Eingabe ab).

### Codex CLI
- Live-Slot: Datei `~/.codex/auth.json` (0600). Blob-JSON:
  `{"tokens": {access_token, refresh_token, id_token, account_id}, "last_refresh", ...}`.
- Identität: `id_token` ist ein JWT; Payload enthält `email` und unter
  `https://api.openai.com/auth` die Felder `chatgpt_plan_type` und `chatgpt_account_id`.
- Token-Refresh: POST `https://auth.openai.com/oauth/token` (form-urlencoded,
  grant_type=refresh_token, client_id `app_EMoamEEZ73f0CkXaXp7hrann`). „invalid_grant"/„already
  been used"/„token_invalidated" = endgültig tot; sonst transient.
- Usage: GET `https://chatgpt.com/backend-api/wham/usage` (Fallback
  `.../backend-api/api/codex/usage`) mit Bearer + Header `ChatGPT-Account-Id`; Antwort
  `rate_limit.primary_window`/`secondary_window` mit `used_percent` und `reset_at` (Unix).
  `{"error":{"code":"login_required"}}` = Sitzung tot.
- Login-Befehl: `codex login -c cli_auth_credentials_store="file"`.

## Keychain-Zugriff
Zugriff auf Keychain-Einträge erfolgt über das Apple-signierte **`security`-CLI** (Subprozess),
nicht über SecItem aus dem eigenen (ad-hoc-signierten) Binary: dem `security`-Binary hat der
User bereits dauerhaft Zugriff gewährt, dadurch entfallen wiederkehrende Erlaubnis-Dialoge
nach jedem Rebuild.
