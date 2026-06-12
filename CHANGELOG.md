# Changelog

Alle nennenswerten Änderungen an CleverSwitch.

## [0.1.3] – 2026-06-12

- **KRITISCH: Token-Vermischung behoben** — nach einem Account-Neulogin konnten beide Accounts denselben Token (und damit identische Usage) zeigen. Ursache: die Keychain-Dedupe wählte nach spätestem Ablaufdatum statt nach dem neuesten Eintrag; ein frisch refreshter Token des anderen Accounts gewann dann fälschlich. Dreifach abgesichert: Dedupe behält den zuletzt angelegten Eintrag · Switch sichert den Live-Slot nur noch, wenn er laut Identität wirklich dem bisherigen Account gehört · spät eintreffende Token-Refreshes werden nach dem aktuellen (nicht dem alten) Aktiv-Zustand geroutet.
- **Update-Check eingebaut**: prüft alle 6 h die GitHub-Releases; „Update X verfügbar – jetzt installieren" oben im Menü installiert per `brew upgrade` und startet die App neu (Fallback: Releases-Seite). Manuell: Einstellungen → „Nach Updates suchen".
- **Geführte Ersteinrichtung im Kino-Stil** (inspiriert von Arcs Onboarding): 5-Schritte-Flow auf animiertem Indigo-Gradient — Hello → CLI-Check mit gestaffelten Häkchen → erster Account (Browser-Login, automatischer Übergang) → Aha-Moment mit hochzählenden Live-Usage-Balken → Berechtigungen (Priming nach dem Aha) → Finale mit Pfeil zur Menüleiste. Überspringen/Esc jederzeit, respektiert „Bewegung reduzieren". Öffnet sich beim ersten Start ohne Accounts; manuell: Einstellungen → „Ersteinrichtung öffnen…". Fehlt eine CLI, zeigt auch das Menü direkt „CLI nicht gefunden – installieren…".
- **Einstellungs-Feinschliff**: Benachrichtigungs-Toggle reagiert beim ersten Klick korrekt (vorher schaltete er bei fehlender System-Erlaubnis nur den internen Wunsch um — „nichts passierte"); „Bei Anmeldung starten" öffnet die Anmeldeobjekte, wenn macOS eine Freigabe verlangt; „Nach Updates suchen" wird nach erfolgloser Suche zu „Du bist auf dem neuesten Stand" (läuft mit dem nächsten 6-h-Fenster ab, keine klebrige Statusmeldung mehr); „Aktualisiert vor X" steht in derselben Zeile wie „Usage aktualisieren".
- **Onboarding startet beim allerersten Start automatisch** (keine state.json = neu), auch wenn bestehende CLI-Logins direkt importiert werden — mit gestaffelter Entrance-Animation im Hello-Schritt.
- **CI-Launch-Smoke-Test**: jedes Release startet die gebaute App 5 s lang — fängt Crash-at-Launch-Fehler, die Unit-Tests nie sehen.
- **Farbige Usage-Zahlen** statt Emoji: die Prozent-Werte sind je nach Auslastung grün (< 60 %), orange (< 85 %) oder rot eingefärbt.
- **Ausgerichtete Usage-Spalten**: Abo · Session · Woche stehen über alle Accounts sauber untereinander (monospaced, dynamische Spaltenbreite).
- **Menüleisten-Zahl wählbar**: Höchste (alle) / nur Claude Code / nur Codex CLI (Einstellungen → „Menüleisten-Zahl"); fällt automatisch auf „alle" zurück, wenn die Quelle leer ist.
- **„Account hinzufügen" zusammengelegt** mit „Account entfernen": ein Eintrag mit Anbieter-Auswahl (Claude Code / Codex CLI) statt je Sektion ein eigener Button.
- **Aktiver Account steht pro Anbieter immer oben**; dezente „Aktualisiert vor X"-Zeile unter „Usage aktualisieren".
- **Auto-Switch** nur noch sichtbar, wenn ein Anbieter mind. 2 Accounts hat (bei einem ist „wechseln" sinnlos).
- **Einheitliche Häkchen-Icons** über Accounts, Auto-Switch und Einstellungen.
- **Benachrichtigungs-Häkchen spiegelt jetzt die echte macOS-Berechtigung**: wird sie in den Systemeinstellungen entzogen, zeigt das Menü das korrekt an; beim Wieder-Aktivieren öffnet sich der passende Einstellungs-Bereich, falls macOS nicht mehr nachfragt.
- **Review-Härtung** (Multi-Agent-Audit): Codex-403 löst keinen sinnlosen Token-Refresh mehr aus (Rate-Limit-Schoner) · Login-Abbruch beendet wieder den kompletten Prozessbaum · keine OAuth-URLs mehr im Log · Log-Datei wird ohne Race-Window mit 0600 angelegt · robusteres Keychain-Account-Parsing · Subprozess-Deadlock-Schutz (stderr) · korrekter Systemeinstellungs-Link für Benachrichtigungen (macOS 13+).
- **Alle 16 Sprachen vollständig übersetzt** (vorher waren 14 nur teilweise gepflegt); 12 verwaiste Übersetzungs-Keys entfernt.

## [0.1.2] – 2026-06-11

- **Login funktioniert jetzt wirklich** (Theos Bug): „Account hinzufügen" startet die Login-CLI unsichtbar als Subprozess ohne TTY — die CLI öffnet selbst den Browser und schließt den Flow per Hintergrund-Poll ab. Kein Terminal, kein Fenster; den Abschluss erkennt die App automatisch und importiert den Account.
- **CLI-Erkennung robuster**: findet `claude`/`codex` auch über die Login-Shell (bun/mise/npm/nvm), nicht nur in festen Pfaden.
- **Benachrichtigungs-Berechtigung** wird beim ersten Start angefragt (vorher kam die Nachfrage nie).
- README: „Made in Germany" + Link zu Clevermation.

## [0.1.1] – 2026-06-11

- Login lässt sich jetzt **abbrechen** (Menü-Eintrag), statt bis zum 5-Minuten-Timeout „Login läuft" anzuzeigen.
- Bricht man ab oder läuft es in den Timeout, wird der komplette Prozessbaum beendet — keine verwaisten Hintergrundprozesse mehr.
- README mit Showcase, Troubleshooting, Uninstall.

## [0.1.0] – 2026-06-11

Erste Version.

- Menüleisten-App (SwiftUI `MenuBarExtra`) für mehrere Claude-Code- und Codex-CLI-Accounts.
- Ein-Klick-Switch der aktiven CLI-Sitzung; OAuth-Token-Refresh (kein Re-Login nach dem Switch).
- Live-Usage pro Account (Session- + Wochenlimit in %, „resets in"-Countdown).
- Auto-Switch in drei Modi: `off` / `failover` (vor dem Limit) / `balance` (gleichmäßig verteilen).
- Headless-Login (kein Terminal-Fenster), automatischer Import des neuen Accounts.
- Menüleisten-Titel zeigt die höchste Session-Auslastung aktiver Accounts.
- Einstellungen: bei Anmeldung starten, Benachrichtigungen, E-Mail-Adressen anzeigen/maskieren.
- 16 Sprachen, automatisch nach Systemsprache.
- Logging nach `~/Library/Logs/CleverSwitch.log`.
