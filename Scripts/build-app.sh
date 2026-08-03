#!/usr/bin/env bash
# Builds NoteBubble and assembles the .app bundle by hand — there is no Xcode
# project here, only Swift Package Manager plus this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Note Bubble.app"

cd "$ROOT"
# Only the app product: the test executable uses @testable, which needs the
# debug-only -enable-testing and so cannot be part of a release build.
swift build -c "$CONFIG" --product NoteBubble
BIN="$(swift build -c "$CONFIG" --show-bin-path)/NoteBubble"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NoteBubble"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Pop sounds are looked up via Bundle.main as Sounds/pop-N.<ext>.
if [ -d "$ROOT/Resources/Sounds" ]; then
  cp -R "$ROOT/Resources/Sounds" "$APP/Contents/Resources/Sounds"
else
  echo "warning: Resources/Sounds missing — run Scripts/make-pop-sounds.py"
fi

# Referenced by CFBundleIconFile. Shows in Finder, Spotlight and Login Items —
# not the Dock, since this is an accessory app.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
  echo "warning: Resources/AppIcon.icns missing — run swift Scripts/make-icon.swift"
fi

# Ad-hoc signature: enough for the app to launch locally on this machine.
codesign --force --sign - "$APP" >/dev/null 2>&1 || \
  echo "warning: ad-hoc codesign failed; the app may still run"

echo "Built: $APP"
