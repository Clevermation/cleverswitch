<!-- markdownlint-disable MD033 MD041 -->
<div align="center">

# CleverSwitch

**macOS-Menüleisten-Switcher für mehrere KI-CLI-Accounts** — Claude Code & Codex, mit Live-Usage und smartem Auto-Switch.

</div>

> ⚠️ **Status:** in aktiver Entwicklung (Phase 1 — Kernlogik). Noch nicht installierbar.

CleverSwitch hält mehrere Logins derselben Coding-CLI bereit und schaltet die *aktive* Sitzung
per Klick um — inklusive Anzeige, wie weit jeder Account am Limit ist (5-Stunden-Session und
7-Tage-Fenster), und automatischem Umschalten **bevor** du gegen die Limit-Wand läufst.

## Features

- 🔀 **Ein-Klick-Switch** zwischen mehreren Claude-Code- und Codex-Accounts
- 📊 **Live-Usage** pro Account (Session-Limit + Wochenlimit in %, inkl. „resets in")
- 🤖 **Auto-Switch** in drei Modi: `off` · `failover` (rechtzeitig vor dem Limit) · `balance` (Verbrauch gleichmäßig verteilen)
- 🔑 **Token-Refresh** automatisch — kein „bitte neu einloggen" nach dem Switch
- 🔒 Credentials bleiben im **macOS-Keychain** bzw. der CLI-eigenen Datei; die Account-Liste enthält keine Secrets

## Installation

> Kommt mit dem ersten Release (geplant: eigener Homebrew-Tap):
>
> ```bash
> brew install --cask clevermation/tap/cleverswitch
> ```

## Stack & Entwicklung

Native **Swift / SwiftUI** (`MenuBarExtra`), gebaut mit dem **Swift Package Manager** — keine
Drittanbieter-Laufzeit-Abhängigkeiten.

```bash
swift build        # bauen
swift test         # Tests (CleverSwitchKit)
```

Die App-Logik liegt in `CleverSwitchKit` (Policy, Store, OAuth, Usage) und ist vom SwiftUI-UI
(`CleverSwitch`) getrennt — also ohne GUI testbar. Architektur und Verhalten: siehe
[`docs/SPEC.md`](docs/SPEC.md).

## Sicherheit & Nutzung

CleverSwitch speichert OAuth-Credentials ausschließlich lokal (macOS-Keychain bzw.
`~/.codex/auth.json`). Es werden keine Daten an Dritte gesendet außer den offiziellen
Auth-/Usage-Endpoints des jeweiligen Anbieters. Prüfe die Nutzungsbedingungen deines
Anbieters bezüglich Mehrfach-Account-Nutzung.

## Lizenz

[MIT](LICENSE) · eigenständige Implementierung, siehe [`NOTICE`](NOTICE).
