#!/usr/bin/env bash
# Prints the Homebrew cask for a release, with its version and checksum filled in.
#
#   Scripts/render-cask.sh 1.2.0 dist/NoteBubble-1.2.0.zip > Casks/note-bubble.rb
#
# The release workflow runs this and pushes the result to macknix/homebrew-tap,
# so `brew upgrade` picks up each release without anyone editing the cask.
set -euo pipefail

VERSION="${1:?usage: render-cask.sh <version> <zip>}"
VERSION="${VERSION#v}"
ZIP="${2:?usage: render-cask.sh <version> <zip>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
sed -e "s/@VERSION@/$VERSION/" -e "s/@SHA256@/$SHA/" "$ROOT/Packaging/homebrew/note-bubble.rb.template"
