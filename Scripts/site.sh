#!/usr/bin/env bash
# The landing page (site/design) — https://macknix.github.io/note-bubble/
#
#   ./Scripts/site.sh          copy the app's assets in, then serve at
#                              http://localhost:8080/design/
#   ./Scripts/site.sh assets   only copy the assets (the Pages workflow does this)
#
# The pop sounds and the icon are the app's own files, copied in rather than
# checked in twice, so the page can never play a different pop from the app.
# site/design/assets/ is ignored by git for that reason.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$ROOT/site/design"

mkdir -p "$SITE/assets/sounds"
cp "$ROOT"/Resources/Sounds/pop-*.mp3 "$SITE/assets/sounds/"
cp "$ROOT/docs/images/app-icon.png" "$SITE/assets/"

[[ "${1:-}" == "assets" ]] && exit 0

echo "http://localhost:${PORT:-8080}/design/"
cd "$ROOT/site" && exec python3 -m http.server "${PORT:-8080}"
