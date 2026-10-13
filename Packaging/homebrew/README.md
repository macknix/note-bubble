# Homebrew

`note-bubble.rb.template` is the cask. `Scripts/render-cask.sh <version> <zip>`
fills in the version and checksum, and the release workflow pushes the result to a
personal tap on every `v*` tag, so that this works and stays current:

```bash
brew install --cask macknix/tap/note-bubble
brew upgrade --cask note-bubble
```

## Turning it on (once)

1. Create the tap: a public repository named **`macknix/homebrew-tap`** — the
   `homebrew-` prefix is what lets `brew` find it as `macknix/tap`. An empty repo
   with a README is enough; the workflow creates `Casks/` itself.
2. Create a fine-grained personal access token with **Contents: read and write**
   on that one repository.
3. Save it in this repository as the Actions secret **`HOMEBREW_TAP_TOKEN`**
   (Settings → Secrets and variables → Actions).

Until the secret exists, the tap step is skipped and releases are unaffected.

## Checking the cask by hand

```bash
mkdir -p /tmp/tap/Casks
Scripts/render-cask.sh 1.2.0 dist/NoteBubble-1.2.0.zip > /tmp/tap/Casks/note-bubble.rb
brew style /tmp/tap/Casks/note-bubble.rb
```

The cask installs the zip rather than the DMG: Homebrew handles both, and the zip
is smaller. Until the app is notarised (#30) the cask's caveats explain the
first-launch "Open Anyway" step; it deliberately does not strip the quarantine
flag on the user's behalf.
