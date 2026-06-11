# Changelog

Alle nennenswerten Änderungen an CleverSwitch.

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
