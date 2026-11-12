#!/usr/bin/env bash
# Builds a release Note Bubble and packages it for download:
#
#   dist/NoteBubble-<version>.dmg     drag-to-Applications disk image
#   dist/NoteBubble-<version>.zip     the same app, zipped
#   dist/NoteBubble.dmg               the same disk image under a name that never changes,
#                                     so releases/latest/download/NoteBubble.dmg is
#                                     always the newest — the website links to it
#   dist/SHA256SUMS.txt               checksums for all three
#
# Needs nothing beyond the Command Line Tools. The version comes from git, exactly
# as in build-app.sh — pass VERSION=v1.2.0 to name one explicitly (CI does).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Note Bubble.app"
DIST="$ROOT/dist"
cd "$ROOT"

"$ROOT/Scripts/build-app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="NoteBubble-$VERSION"
rm -rf "$DIST"
mkdir -p "$DIST"

# ditto rather than zip: it keeps extended attributes and the code signature intact,
# which zip silently drops.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

# The disk image: the app beside a link to /Applications, so installing is a drag.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Note Bubble.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Note Bubble" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg"

cp "$DIST/$NAME.dmg" "$DIST/NoteBubble.dmg"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" NoteBubble.dmg > SHA256SUMS.txt)

echo "Packaged $VERSION:"
ls -lh "$DIST" | awk 'NR > 1 { print "  " $NF " (" $5 ")" }'
