#!/usr/bin/env bash
# Builds NoteBubble and assembles the .app bundle by hand — there is no Xcode
# project here, only Swift Package Manager plus this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Note Bubble.app"

cd "$ROOT"

# The version comes from git, never from editing Info.plist: the latest `vX.Y.Z`
# tag, or $VERSION when CI passes the tag it is building. The build number counts
# commits, so it only ever goes up. The commit goes in too, so a build made between
# tags can still be told apart from the release before it.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo 0.0.0)}"
VERSION="${VERSION#v}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
git diff --quiet HEAD 2>/dev/null || COMMIT="$COMMIT-dirty"
# Only the app product: the test executable uses @testable, which needs the
# debug-only -enable-testing and so cannot be part of a release build.
swift build -c "$CONFIG" --product NoteBubble
BIN="$(swift build -c "$CONFIG" --show-bin-path)/NoteBubble"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NoteBubble"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Stamped on the copy, so the plist in the repo never changes from build to build.
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NBGitCommit string $COMMIT" "$PLIST"

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

echo "Built: $APP ($VERSION, build $BUILD_NUMBER, $COMMIT)"
