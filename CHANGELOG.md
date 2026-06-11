# Changelog

Alle nennenswerten Änderungen an CleverSwitch.

## [0.1.3] – 2026-06-11

- **Farbige Usage-Zahlen** statt Emoji: die Prozent-Werte sind je nach Auslastung grün (< 60 %), orange (< 85 %) oder rot eingefärbt.
- **„Account hinzufügen" zusammengelegt** mit „Account entfernen": ein Eintrag mit Anbieter-Auswahl (Claude Code / Codex CLI) statt je Sektion ein eigener Button.
- **Auto-Switch** nur noch sichtbar, wenn ein Anbieter mind. 2 Accounts hat (bei einem ist „wechseln" sinnlos).
- **Einheitliche Häkchen-Icons** über Accounts, Auto-Switch und Einstellungen.
- **Benachrichtigungs-Häkchen spiegelt jetzt die echte macOS-Berechtigung**: wird sie in den Systemeinstellungen entzogen, zeigt das Menü das korrekt an; beim Wieder-Aktivieren öffnet sich der passende Einstellungs-Bereich, falls macOS nicht mehr nachfragt.

## [0.1.2] – 2026-06-11

- **Login funktioniert jetzt wirklich** (Theos Bug): Claudes Login braucht das Einfügen eines Codes aus dem Browser — das geht nur sichtbar. „Account hinzufügen" öffnet jetzt einen sauberen, gebrandeten Sign-in-Tab; den Abschluss erkennt die App automatisch und importiert den Account.
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
