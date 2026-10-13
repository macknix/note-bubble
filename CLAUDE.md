# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Note Bubble is a macOS to-do widget living in the menu bar and as a floating
overlay. Notes are rounded tiles packed by masonry: drag to rearrange, click to
open a tile's sub-tasks, hold to pop one when it's done. Tiles grow to fit their
text and redden with age as a triage signal. Notes live on named **workspaces** —
separate boards you two-finger swipe between.

## Commands

```bash
swift build                      # compile check, all targets
swift run NoteBubbleTests        # run the test suite
./Scripts/build-app.sh           # release build (universal arm64 + x86_64) + assemble build/Note Bubble.app
./Scripts/build-app.sh debug     # same, debug configuration
VERSION=v1.2.0 ./Scripts/build-app.sh  # stamp an explicit version (CI does this from the tag)
./Scripts/package.sh             # release build → dist/: .dmg, .zip, SHA256SUMS.txt
git tag v1.2.0 && git push origin v1.2.0   # publish a GitHub Release (.github/workflows/release.yml)
open "build/Note Bubble.app"     # launch
pkill -f "Note Bubble.app"       # quit (there is no Dock icon to right-click)

swift Scripts/make-icon.swift        # regenerate Resources/AppIcon.icns
python3 Scripts/make-pop-sounds.py   # regenerate synthesised .wav pop fallbacks

python3 Scripts/demo-data.py install # load the demo board (backs up your notes)
python3 Scripts/demo-data.py restore # put your own notes back
```

`Scripts/demo-data.py` is the standing test board: 37 notes over three workspaces —
a full one (15 at the top level, three levels deep), a small one, and an empty one,
so the swipe, the dots and the empty state all have something to exercise. An even
spread across the traffic lights, and text lengths from one word to a paragraph
that hits the height cap. Ages are stored as *days ago* and
dated at generation time, so it never goes stale; IDs derive from each note's path,
so repeated installs produce byte-identical files. Reach for it whenever a change
touches layout, ageing or nesting — it covers the cases that have broken before.

## Where to change things

| To change… | Go to |
|---|---|
| Ageing thresholds, and each board's own window (`AgeWindow`) | `Model/Aging.swift`; set from `Views/AgeWindowMenu.swift` |
| Ageing colours, and the colour each stage stands for | `Views/AgingPalette.swift` |
| How often ages refresh on a board left alone | `Support/AgeClock.swift` |
| Any animation or delay, and Reduce Motion | `Support/Motion.swift` — all of them live here |
| Tile sizing, column count, packing | `Layout/GridLayout.swift` |
| Where every tile sits for one render | `Layout/LayoutPlan.swift` |
| Label font, tile padding | `Layout/TileText.swift` (measurement depends on these) |
| Tile corner shape | `Views/TileStyle.swift` |
| Panel size, fade | `Window/PanelController.swift` |
| When hover opens and closes the panel | `Support/HoverIntent.swift` decides; delays in `Motion` |
| Dragging the panel itself | `Window/PanelMover.swift` |
| Two-finger swipe wiring | `Window/SwipeMonitor.swift` (the rules are `Support/WorkspaceSwipe.swift`) |
| Where the panel sits: snapping, which way it opens | `Window/PanelParking.swift`, rules in `Window/PanelPlacement.swift` |
| The pill's size | `Views/MinimisedPill.swift` |
| Keyboard shortcuts | `Window/OverlayPanel.swift` (`PanelShortcut` maps keys, `PanelCommands` carries them out) and `Window/HotKey.swift` |
| The global shortcut: which one, recording it, saying when it is taken | `App/GlobalShortcut.swift`, `Support/KeyCombo.swift`, `Views/ShortcutRecorderSheet.swift` |
| Text-editing shortcuts (⌘C/⌘V/⌘A), and where ⌘Z goes | `App/MainMenu.swift` |
| Workspaces: the boards themselves | `Model/Workspace.swift` (and the file's shape), `Model/BubbleStore.swift` |
| What counts as a swipe | `Support/WorkspaceSwipe.swift` decides; `Window/PanelController.swift` feeds it |
| Where a dragged tile is, and which dot it is over | `Support/TileFlight.swift` decides; `Views/BubbleGrid+Drag.swift` draws it |
| What resting a tile on a dot shows | `Support/PreviewDwell.swift` decides; `Views/BubbleGrid+Preview.swift` draws it |
| Popping: confirmation, burst, toast | `Views/BubbleGrid+Pop.swift` |
| How long you must rest on a dot before its board slides in | `Motion.workspacePreview` |
| The workspace name and its menu | `Views/WorkspaceChip.swift` |
| The workspace dots — the swipe's affordance, and the drop targets | `Views/WorkspaceDots.swift` |
| What another board looks like mid-drag | `Views/WorkspacePreview.swift` |
| Menu bar icon and its menu | `Window/MenuBarItem.swift` |
| What a tile looks like | `Views/TileFace.swift` (`BubbleTile` adds hover, rename and the editor) |
| Tap / hold / drag behaviour | `Support/TileGesture.swift` decides; `Views/BubbleGrid+Drag.swift` carries it out |
| Note data, undo | `Model/BubbleStore.swift` |
| Reading and writing `bubbles.json`, backups | `Model/BubbleFile.swift` |
| Asking before something destructive | `Views/ConfirmSheet.swift` |
| App icon artwork | `Scripts/make-icon.swift` |

## Invariants worth knowing before editing

1. **A tile never exceeds `maximumHeight`, and clips its own content.** See
   "Tiles are rectangles, packed by masonry" in `docs/ARCHITECTURE.md`.
2. **Hover never takes keyboard focus.** See "The pill is the resting state".
3. **Text is saved on every keystroke.** There is no save step to add.
4. **Popping searches the whole tree,** not the current level.
5. **The confirmation is drawn in-panel,** never as an `NSAlert`.
6. **`PanelController` alone sizes the window,** and it resizes *before* swapping
   the view in. See "The panel remembers its corner" and "Resize the window, then
   install the view".
7. **There is always at least one workspace,** and `currentIndex` always points at
   one. `BubbleDocument.normalised` is the only way notes get into the store, and
   it is what guarantees both.
8. **Nothing changes the board on screen while a tile is being dragged.** Carrying
   a tile to another board shows you that board without going to it. See "A tile
   can be dragged onto another board" — this one has been broken twice, and both
   times it stranded a bubble on screen.

Each is load-bearing and each has a comment at its site explaining why. Quoted section names
are in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Notes persist to `~/Library/Application Support/NoteBubble/bubbles.json`, as
`{ version, workspaces, currentID }`. A file from before workspaces existed is a
bare `[BubbleNode]` array; it is recognised by shape, lifted into a single board
named "Notes", and rewritten in the current form on the next save — so there is no
migration step to run, but **an old build will not read a new file** — it refuses it
outright (`BubbleDocument.Failure.tooNew`) and saves nothing for the session.
**A file that cannot be used is never treated as empty**: `BubbleFile` sets an
undecodable one aside as `bubbles.unreadable-<date>.json`, and `BubbleStore` raises
`fileNotice` for the panel. Treating it as empty is what used to let the next
keystroke save an empty board over it. The first save of each launch copies the
file to `bubbles.json.bak` first. Delete `bubbles.json` to reset, or use the demo board above rather than hand-editing dates.
The app holds the tree in memory and writes on change, so quit it before replacing
that file or it will overwrite you on its next save — `demo-data.py` refuses to
install while it is running for exactly that reason.

Where the panel sits is remembered separately, in `UserDefaults`:
`defaults delete com.macknixon.notebubble PanelPlacement` puts it back in the
top-right corner.

## Build Constraints

**There is no Xcode on this machine — only Command Line Tools.** Four consequences
that will bite if forgotten:

1. `xcodebuild` does not work and there is no `.xcodeproj`. The app is a Swift
   Package plus `Scripts/build-app.sh`, which copies the SPM binary and
   `Resources/Info.plist` into a hand-assembled `.app` and ad-hoc signs it.
2. **`swift test` cannot work here.** XCTest and swift-testing both ship with
   Xcode. The suite is therefore an ordinary executable target (`NoteBubbleTests`)
   over a small assertion harness in `Sources/NoteBubbleTests/Harness.swift`, run
   with `swift run NoteBubbleTests` and exiting non-zero on failure. Do not
   convert it to a `.testTarget`; it will stop building.
3. **Release builds are universal, built one slice at a time.** `swift build --arch
   arm64 --arch x86_64` needs Xcode's build system, so `build-app.sh` builds each
   architecture with `--triple <arch>-apple-macosx<LSMinimumSystemVersion>` into its
   own scratch path (`.build/arm64`, `.build/x86_64`) and joins them with `lipo`.
   Debug builds stay native; `UNIVERSAL=0|1` overrides either way.
4. The test target uses `@testable`, which needs the debug-only `-enable-testing`,
   so `build-app.sh` passes `--product NoteBubble` to keep it out of release
   builds. Dropping that flag breaks `./Scripts/build-app.sh`.

**The version lives in git, not in `Info.plist`.** `build-app.sh` stamps the copied
plist: `CFBundleShortVersionString` from the latest `vX.Y.Z` tag (or `$VERSION`),
`CFBundleVersion` from the commit count, and `NBGitCommit` from the short hash
(`-dirty` if uncommitted). The plist in the repo holds placeholders. `AppVersion`
reads them back for the menu bar's version line and the About panel.

`Package.swift` pins `swiftLanguageMode(.v5)` deliberately. The toolchain is
Swift 6.2, whose default strict-concurrency mode rejects most of the AppKit
plumbing here.

## Structure

```
Sources/NoteBubble/        main.swift only — calls NoteBubbleApp.launch()
Sources/NoteBubbleCore/    everything real, so the tests can import it
  App/                     NoteBubbleApp (public entry point), AppDelegate, MainMenu
  Audio/                   PopSounds
  Model/                   BubbleNode, BubbleStore, BubbleFile, Workspace, Aging,
                           StageTally
  Layout/                  GridLayout, LayoutPlan, TileText, TileSizeCache
  Support/                 Motion, TileGesture, TileFlight, WorkspaceSwipe, AgeClock,
                           HoverIntent, PreviewDwell
  Views/                   RootView, GlassBar, BarStyle, BarButtons, StatusHandle,
                           WorkspaceChip, WorkspaceDots, WorkspacePreview,
                           BubbleGrid (+Drag, +Preview, +Pop), BubbleTile, TileFace,
                           TileStyle, PopBurst,
                           ConfirmSheet, ConfirmPopSheet, UndoToast, FileNoticeBanner,
                           AgingPalette,
                           MinimisedPill, WindowDragArea
  Window/                  OverlayPanel, PanelController, PanelParking,
                           PanelPlacement, PanelState, PanelDrag, PanelCommands,
                           PanelMover, SwipeMonitor,
                           MenuBarItem, HotKey
Sources/NoteBubbleTests/   executable test suite + Harness
Scripts/                   build-app.sh, package.sh, render-cask.sh, make-icon.swift,
                           make-pop-sounds.py, demo-data.py
Resources/                 Info.plist, AppIcon.icns, Sounds/
Packaging/homebrew/        the Homebrew cask template, and how the tap is wired
```

The executable/library split exists solely so the test target has something to
import — an executable target cannot be imported. `NoteBubbleApp.launch()` is the
only `public` symbol; everything else is internal and reached via `@testable`.

Dependencies run one way: `Model` knows nothing of layout or views, `Layout` knows
the model but no views, `Views` know both, and `Window` owns the views. Nothing in
`Model` or `Layout` imports SwiftUI (`TileText` imports AppKit only for text
metrics), which is what keeps them testable without a running app.

## Architecture

The reasoning behind each subsystem — and the bugs each rule was written to stop —
lives in **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)**. It is long on purpose;
it is kept out of this file so it is not loaded into every session. **Read the
section for the area you are about to change first** — most of these were learned
the hard way, and several have been broken twice.

- [Bar controls need an explicit `contentShape`](docs/ARCHITECTURE.md#bar-controls-need-an-explicit-contentshape)
- [The bar must never overflow its width](docs/ARCHITECTURE.md#the-bar-must-never-overflow-its-width)
- [The top bar's visual language](docs/ARCHITECTURE.md#the-top-bars-visual-language)
- [Workspaces are separate boards, not another level of nesting](docs/ARCHITECTURE.md#workspaces-are-separate-boards-not-another-level-of-nesting)
- [A tile can be dragged onto another board](docs/ARCHITECTURE.md#a-tile-can-be-dragged-onto-another-board)
- [A swipe is a scroll, intercepted before the grid sees it](docs/ARCHITECTURE.md#a-swipe-is-a-scroll-intercepted-before-the-grid-sees-it)
- [Tiles are rectangles, packed by masonry](docs/ARCHITECTURE.md#tiles-are-rectangles-packed-by-masonry)
- [Tiles are measured to fit their text; the maximum is the cap](docs/ARCHITECTURE.md#tiles-are-measured-to-fit-their-text-the-maximum-is-the-cap)
- [The panel is only as tall as its contents](docs/ARCHITECTURE.md#the-panel-is-only-as-tall-as-its-contents)
- [Text editing finishes on Return](docs/ARCHITECTURE.md#text-editing-finishes-on-return)
- [Grid position is array order](docs/ARCHITECTURE.md#grid-position-is-array-order)
- [Two performance constraints in the grid](docs/ARCHITECTURE.md#two-performance-constraints-in-the-grid)
- [One gesture does tap, hold and drag](docs/ARCHITECTURE.md#one-gesture-does-tap-hold-and-drag)
- [Two things the grid must not do](docs/ARCHITECTURE.md#two-things-the-grid-must-not-do)
- [Tree edits funnel through one recursive helper](docs/ARCHITECTURE.md#tree-edits-funnel-through-one-recursive-helper)
- [The panel is nonactivating but key-capable](docs/ARCHITECTURE.md#the-panel-is-nonactivating-but-key-capable)
- [The panel remembers its corner](docs/ARCHITECTURE.md#the-panel-remembers-its-corner)
- [Resize the window, then install the view](docs/ARCHITECTURE.md#resize-the-window-then-install-the-view)
- [Dragging the panel, and first clicks generally](docs/ARCHITECTURE.md#dragging-the-panel-and-first-clicks-generally)
- [Undo reverses one action, and only real destruction records](docs/ARCHITECTURE.md#undo-reverses-one-action-and-only-real-destruction-records)
- [Popping is depth-independent, and a hold consumes its release](docs/ARCHITECTURE.md#popping-is-depth-independent-and-a-hold-consumes-its-release)
- [Anything that destroys writing asks first](docs/ARCHITECTURE.md#anything-that-destroys-writing-asks-first)
- [Sound](docs/ARCHITECTURE.md#sound)
- [Transparent panel, opaque tiles](docs/ARCHITECTURE.md#transparent-panel-opaque-tiles)
- [The pill is one number](docs/ARCHITECTURE.md#the-pill-is-one-number)
- [Two ways in: the menu bar and the pill](docs/ARCHITECTURE.md#two-ways-in-the-menu-bar-and-the-pill)
- [The pill is the resting state; hover drives everything](docs/ARCHITECTURE.md#the-pill-is-the-resting-state-hover-drives-everything)
- [Ageing is continuous, buckets are only for the badge](docs/ARCHITECTURE.md#ageing-is-continuous-buckets-are-only-for-the-badge)
- [Accessibility](docs/ARCHITECTURE.md#accessibility)
- [App lifecycle](docs/ARCHITECTURE.md#app-lifecycle)
