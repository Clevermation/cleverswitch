# Changelog

Alle nennenswerten Änderungen an CleverSwitch.

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
