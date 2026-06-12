#!/bin/zsh
# Baut CleverSwitch im Release-Modus und packt die SPM-Binary in ein .app-Bundle
# (Menüleisten-App via LSUIElement). Ohne Xcode-Projekt -> auch in CI nutzbar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CleverSwitch.app"
# Version aus Version.swift lesen (Single Source of Truth), überschreibbar per Argument.
DEFAULT_VERSION="$(sed -n 's/.*cleverSwitchVersion = "\(.*\)"/\1/p' "$ROOT/Sources/CleverSwitchKit/Version.swift")"
VERSION="${1:-$DEFAULT_VERSION}"

echo "==> swift build -c release"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/CleverSwitch"

echo "==> .app zusammenbauen"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CleverSwitch"

# Icon (im Repo unter packaging/ — damit der Build auch in CI ohne externe Pfade läuft).
ICON="$ROOT/packaging/AppIcon.icns"
if [ -f "$ICON" ]; then
  cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>CleverSwitch</string>
  <key>CFBundleDisplayName</key><string>CleverSwitch</string>
  <key>CFBundleIdentifier</key><string>com.clevermation.cleverswitch</string>
  <key>CFBundleExecutable</key><string>CleverSwitch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Jonne Schwegmann / Clevermation</string>
</dict>
</plist>
PLIST

# iCloud-/Finder-xattrs entfernen (lokal hängt der Desktop-Sync Metadaten an,
# die codesign --strict als "detritus" ablehnt)
xattr -cr "$APP" 2>/dev/null || true

echo "==> ad-hoc signieren"
codesign --force --deep -s - "$APP"

echo "==> fertig: $APP"
