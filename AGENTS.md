# CleverSwitch — Arbeitsweise für KI-Agents

Eine Wahrheit für Claude Code UND Codex (CLAUDE.md importiert diese Datei).
Verhaltens-Spezifikation: `docs/SPEC.md`. Historie/Begründungen: `CHANGELOG.md`.

## Architektur-Regel Nr. 1

Logik gehört nach **`CleverSwitchKit`** (Library, voll testbar), niemals ins
App-Target. `Sources/CleverSwitch/` (AppModel, MenuContent, Onboarding) ist ein
executableTarget und damit **nicht unit-testbar** — wer dort Logik ansammelt,
macht sie untestbar. Im Zweifel: pure Funktion ins Kit, Test dazu, App ruft auf.

## Heilige Invarianten (nicht anfassen ohne sehr guten Grund)

Der Claude-Live-Slot (Keychain `Claude Code-credentials`) wird **auch von der
CLI selbst beschrieben** und bei Logins dupliziert. Daraus folgen Schutzschichten,
die zwei reale Datenverlust-Bugs beendet haben — beim Ändern Tests lesen:

- Alle App-seitigen Credential-Schreibzugriffe laufen durch den **`KeychainGate`**-Actor.
- `consolidateLive` behält den **zuletzt angelegten** Eintrag (NICHT max expiresAt).
- Snapshots werden nur nach **bestätigter Identität** beschrieben (Switch + Login).
- Token-Refresh bei npm-Installationen immer `@latest` (nie `npm update -g`).
- Secrets nie in argv (`security -i` + stdin), nie ins Log (keine URLs aus Login-Output).

## Arbeitsweise

- Kommentare/Commits deutsch (echte Umlaute), Code-Bezeichner englisch, README englisch.
- Conventional Commits; Messages mit Sonderzeichen **immer via `git commit -F datei`**
  (Inline-Quotes haben hier schon einen kaputten Tag produziert).
- Niemals `open(p,'w')`-artige Self-Read-Write-Einzeiler über Quelldateien.
- L10n (`L10n.swift`): **alle 16 Sprachen haben exakt dieselbe Key-Menge.**
  Neuer Key = 16 Übersetzungen, sonst bricht das Sprach-Versprechen des README.
- `@Observable` trackt nur gespeicherte Properties — UI-relevanter Zustand wird
  gespeichert, nicht berechnet (sonst aktualisiert das Menü nicht).

## Real testen (in dieser Reihenfolge)

```bash
swift build && swift test        # Pflicht vor jedem „fertig"; 0 Warnungen ist der Standard
bash packaging/assemble-app.sh   # baut dist/CleverSwitch.app (Version aus Version.swift)
codesign --verify --deep --strict dist/CleverSwitch.app   # Pflicht (Skript strippt iCloud-xattrs)
```

Lokal installieren (ersetzt die laufende App):

```bash
osascript -e 'tell application "CleverSwitch" to quit'; sleep 1
rm -rf /Applications/CleverSwitch.app && cp -R dist/CleverSwitch.app /Applications/
open /Applications/CleverSwitch.app
```

**GUI-Verifikation macht ein Mensch**: Die App ist LSUIElement (kein Dock-Icon);
Computer-Use-Tools sehen frisch installierte Builds erst nach Session-Neustart.
Logik stattdessen über echte Daten verifizieren:

- Log: `tail -40 ~/Library/Logs/CleverSwitch.log` (Switches, Logins, Anomalien)
- Keychain: `security find-generic-password -s "cleverswitch:claude:<mail>" -w`
- Usage serverseitig gegenprüfen (entlarvt Token-Verwechslung sofort):
  `curl -s https://api.anthropic.com/oauth/usage -H "Authorization: Bearer <token>" -H "anthropic-beta: oauth-2025-04-20" -H "User-Agent: claude-code/2.1.173"`
- Frisch-Installation simulieren (Onboarding): App beenden,
  `rm -rf ~/Library/Application\ Support/CleverSwitch`, App starten.
- Achtung Zähl-Falle: `security dump-keychain | grep -c <service>` liefert
  **2 Zeilen pro Eintrag** (Label + svce) — erst ab 4 sind es echte Duplikate.

## Release

```bash
git tag vX.Y.Z && git push origin vX.Y.Z   # Version.swift VORHER bumpen (Single Source of Truth)
```

CI baut, testet, startet die App 5 s (Smoke), hängt Zip + SHA256SUMS.txt ans Release.
Danach im Tap (`Clevermation/homebrew-tap`) `Casks/cleverswitch.rb` auf neue
Version + SHA256 ziehen und `brew style` laufen lassen. Der In-App-Update-Check
findet das Release dann von selbst.
