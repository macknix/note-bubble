# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Note Bubble is a macOS to-do widget living in the menu bar and as a floating
overlay. Notes are rounded tiles packed by masonry: drag to rearrange, click to
open a tile's sub-tasks, hold to pop one when it's done. Tiles grow to fit their
text and redden with age as a triage signal.

## Commands

```bash
swift build                      # compile check, all targets
swift run NoteBubbleTests        # run the test suite
./Scripts/build-app.sh           # release build + assemble build/Note Bubble.app
./Scripts/build-app.sh debug     # same, debug configuration
open "build/Note Bubble.app"     # launch
pkill -f "Note Bubble.app"       # quit (there is no Dock icon to right-click)

swift Scripts/make-icon.swift        # regenerate Resources/AppIcon.icns
python3 Scripts/make-pop-sounds.py   # regenerate synthesised .wav pop fallbacks

python3 Scripts/demo-data.py install # load the demo board (backs up your notes)
python3 Scripts/demo-data.py restore # put your own notes back
```

`Scripts/demo-data.py` is the standing test board: 31 notes, 15 at the top level,
three levels deep, an even spread across the traffic lights, and text lengths from
one word to a paragraph that hits the height cap. Ages are stored as *days ago* and
dated at generation time, so it never goes stale; IDs derive from each note's path,
so repeated installs produce byte-identical files. Reach for it whenever a change
touches layout, ageing or nesting — it covers the cases that have broken before.

## Where to change things

| To change… | Go to |
|---|---|
| Colours / ageing thresholds | `Model/Aging.swift` |
| Any animation or delay | `Support/Motion.swift` — all of them live here |
| Tile sizing, column count, packing | `Layout/GridLayout.swift` |
| Label font, tile padding | `Layout/TileText.swift` (measurement depends on these) |
| Tile corner shape | `Views/TileStyle.swift` |
| Panel size, fade, hover open/close timing | `Window/PanelController.swift` |
| Keyboard shortcuts | `Window/OverlayPanel.swift` (⌘…) and `Window/HotKey.swift` (⌥Space) |
| Menu bar icon and its menu | `Window/MenuBarItem.swift` |
| What a tile looks like | `Views/BubbleTile.swift` |
| Tap / hold / drag behaviour | `Views/BubbleGrid.swift`, `gesture(for:)` |
| Note data, undo, persistence | `Model/BubbleStore.swift` |
| App icon artwork | `Scripts/make-icon.swift` |

## Invariants worth knowing before editing

1. **A tile never exceeds `maximumHeight`, and clips its own content.** See
   "Tiles are rectangles, packed by masonry" below.
2. **Hover never takes keyboard focus.** See "The pill is the resting state".
3. **Text is saved on every keystroke.** There is no save step to add.
4. **Popping searches the whole tree,** not the current level.
5. **The confirmation is drawn in-panel,** never as an `NSAlert`.

Each is load-bearing and each has a comment at its site explaining why.

Notes persist to `~/Library/Application Support/NoteBubble/bubbles.json`. Delete
that file to reset, or use the demo board above rather than hand-editing dates.
The app holds the tree in memory and writes on change, so quit it before replacing
that file or it will overwrite you on its next save — `demo-data.py` refuses to
install while it is running for exactly that reason.

## Build Constraints

**There is no Xcode on this machine — only Command Line Tools.** Three consequences
that will bite if forgotten:

1. `xcodebuild` does not work and there is no `.xcodeproj`. The app is a Swift
   Package plus `Scripts/build-app.sh`, which copies the SPM binary and
   `Resources/Info.plist` into a hand-assembled `.app` and ad-hoc signs it.
2. **`swift test` cannot work here.** XCTest and swift-testing both ship with
   Xcode. The suite is therefore an ordinary executable target (`NoteBubbleTests`)
   over a small assertion harness in `Sources/NoteBubbleTests/Harness.swift`, run
   with `swift run NoteBubbleTests` and exiting non-zero on failure. Do not
   convert it to a `.testTarget`; it will stop building.
3. The test target uses `@testable`, which needs the debug-only `-enable-testing`,
   so `build-app.sh` passes `--product NoteBubble` to keep it out of release
   builds. Dropping that flag breaks `./Scripts/build-app.sh`.

`Package.swift` pins `swiftLanguageMode(.v5)` deliberately. The toolchain is
Swift 6.2, whose default strict-concurrency mode rejects most of the AppKit
plumbing here.

## Structure

```
Sources/NoteBubble/        main.swift only — calls NoteBubbleApp.launch()
Sources/NoteBubbleCore/    everything real, so the tests can import it
  App/                     NoteBubbleApp (public entry point), AppDelegate
  Audio/                   PopSounds
  Model/                   BubbleNode, BubbleStore, Aging
  Layout/                  GridLayout, TileText, TileSizeCache
  Support/                 Motion
  Views/                   RootView, GlassBar, BarStyle, BarButtons, StatusHandle,
                           BubbleGrid, BubbleTile, TileStyle, PopBurst,
                           ConfirmPopSheet, UndoToast, MinimisedPill, WindowDragArea
  Window/                  OverlayPanel, PanelController, PanelState, PanelDrag,
                           MenuBarItem, HotKey
Sources/NoteBubbleTests/   executable test suite + Harness
Scripts/                   build-app.sh, make-icon.swift, make-pop-sounds.py,
                           demo-data.py
Resources/                 Info.plist, AppIcon.icns, Sounds/
```

The executable/library split exists solely so the test target has something to
import — an executable target cannot be imported. `NoteBubbleApp.launch()` is the
only `public` symbol; everything else is internal and reached via `@testable`.

Dependencies run one way: `Model` knows nothing of layout or views, `Layout` knows
the model but no views, `Views` know both, and `Window` owns the views. Nothing in
`Model` or `Layout` imports SwiftUI (`TileText` imports AppKit only for text
metrics), which is what keeps them testable without a running app.

## Architecture

### Bar controls need an explicit `contentShape`

Every button in the bar draws its glyph inside a `.frame`, over a circle that is
`.allowsHitTesting(false)` so drags pass through the bar chrome. Neither of those
contributes hit area — a `.frame` is only a layout container — so without an
explicit `.contentShape(Circle())` the *only* clickable region is the glyph's own
strokes. `chevron.left` at 12pt is about 7×12pt of thin lines, which took several
attempts to hit; chunky glyphs like `xmark` masked the problem.

If you add a control here, give it a `contentShape`.

### The bar must never overflow its width

The panel is 432pt, leaving ~398pt inside the bar. Controls have hard minimum
widths, so anything flexible has to yield to them — `controls` carries
`.layoutPriority(1)` and the breadcrumb `.layoutPriority(-1)`.

This is a fixed bug, not a precaution. With the back button and breadcrumb inline
the bar wanted ~502pt once you drilled into a bubble, and the overflow pushed the
rightmost controls (close, and the new-bubble orb) outside the panel's
`clipShape` — where they rendered but could not be clicked. It only showed up when
nested, which made it look intermittent.

The breadcrumb now has its own full-width row, shown only when nested;
`PanelController` adds `trailRowHeight` to the panel when `!store.isAtRoot`. If you
add a control to the top row, check the budget still balances.

### The top bar's visual language

`BarStyle` holds it: a deferential frosted **glass** substrate, and one saturated
**candy** gradient spent on the single primary action. That asymmetry is the whole
design — eight equally-weighted controls read as noise, so everything except "new
bubble" recedes into faint glass chips.

The iridescent rim (`filmCyan`/`filmViolet`/`filmPeach`, swept as an
`AngularGradient`) is a soap film's spectrum — the app's own material, and what
keeps the glass from reading as generic frosted chrome. Ageing hues are reserved
for *meaning* and never used decoratively, which is why the candy accent is a pink
that cannot be mistaken for a traffic light.

`StatusHandle` is the signature: the drag handle is also the fresh / ageing /
overdue readout. It shows **only stages that have notes** — always drawing three
dots meant a board of seven fresh notes displayed a green 7 beside two blank
circles that looked decorative and explained nothing. A grip glyph says "drag me"
so the counts don't have to do both jobs, and the tooltip spells the stages out in
words. Only the overdue badge pulses, and only when non-zero.

`CandyPress` uses a low `dampingFraction` on purpose: the overshoot on release is
what makes a control feel satisfying rather than merely responsive.

### Tiles are rectangles, packed by masonry

Two decisions, both arrived at from a screenshot of the layout failing:

1. **Tiles are rectangles, not squares.** A note wants a width and needs whatever
   height follows. While tiles were square the text overflowed its frame — the
   layout reserved a square and the tile rendered taller, so nothing lined up.
   `BubbleTile` now clips to its own shape so this cannot silently return.
2. **Placement is masonry, not rows.** Rows of variable-height tiles leave a gap
   under every short one. `GridLayout.frames(for:)` drops each tile into the
   currently shortest column, so short tiles fill in beside tall ones.

Widths snap to whole columns — one, or two for a note that would otherwise tower —
which is what keeps masonry reading as a grid rather than a scrapbook. A tile
taller than `wideThreshold` in one column is re-measured across two.

Positions are therefore **no longer derivable from an index alone**. `BubbleGrid`
builds a `LayoutPlan` once per render holding sizes, resting frames, and the
reflowed centres under a live drag. Anything positional goes through it.

Drop targets are hit-tested against the **resting** frames, never the reflowed
ones: testing against tiles that are themselves moving makes the target oscillate
under the cursor. A drop below all content appends rather than picking the nearest
centre, which would otherwise grab whichever tile sat furthest right.

### Tiles are measured to fit their text; the maximum is the cap

`GridLayout.spec(for:)` measures the label with real font metrics
(`NSString.boundingRect` via `TileText`), not a character-count heuristic, and
snaps the result to `heightStep`. `maximumHeight` is what makes "always fit the
text" and "sensible maximum" coexist: past it, text truncates instead of the tile
growing.

`TileText.fontSize` is **fixed**, deliberately. Scaling type with the tile is
self-defeating: a bigger tile would render bigger text and so hold barely more of
it, and no size would ever be enough. `TileText` also owns the insets the
measurement assumes — change the padding in `BubbleTile` and you must change
`horizontalInset`/`verticalChrome` with it or tiles will be measured wrong.

### The panel is only as tall as its contents

`PanelController.expandedSize` derives height from `GridLayout.contentHeight` for
the current level, clamped between `minimumBodyHeight` and `maximumBodyHeight`
(past which the grid scrolls). It subscribes to `store.objectWillChange` — which
fires *before* the mutation lands, hence the hop to the next run-loop turn in
`fitToContent` to read post-change state. Resizing anchors top-left like every
other resize here.

### Text editing finishes on Return

Text is written through to the store on every keystroke, so "finishing" only ever
means dropping focus — there is never an unsaved draft. `BubbleTile` handles
Return via `.onKeyPress` (⇧Return falls through to insert a newline, which is why
the field keeps `axis: .vertical`), Escape restores the `original` captured on
appear, and a single click on the grid background clears `editingID`. Do not add a
"save" step; there is nothing to save.

### Grid position is array order

There is no separate layout model. A tile's slot is its index in the parent's
`children` array, so rearranging *is* `BubbleStore.move(_:to:)` and persistence
comes free. `GridLayout` (`Layout/GridLayout.swift`) is pure geometry — index →
point, point → insertion index — with no SwiftUI and no model types, which is why
it is the most heavily tested piece. Its column count solves `100n + 20 ≤ width`
for the default metrics; the panel is 420pt wide precisely to give four columns.

### Two performance constraints in the grid

Both were real regressions, both are easy to reintroduce:

- **Sizing a tile lays out its text**, so it must not happen more than once per
  tile per render. Views go through `TileSizeCache.size(for:in:)`, never
  `GridLayout.tileSize` directly. Calling it inline in an `.animation(value:)`
  silently triples the cost.
- **The layout is computed once per render** in `layoutPlan(for:layout:)` and
  passed down. Deriving frames or the reflow order per tile makes a drag O(n²) per
  frame.

### One gesture does tap, hold and drag

`BubbleGrid.gesture(for:index:count:layout:)` is a single `DragGesture` with
`minimumDistance: 0`, and discriminates by hand: movement past `dragSlop` means
rearrange (which cancels the pop countdown), holding still until `popHold` means
pop, releasing before either means enter. **Do not split this into
`.onTapGesture` + `.onLongPressGesture` + `.gesture`** — SwiftUI cannot arbitrate
three overlapping gestures on one view reliably, and that is the whole reason the
state machine is written out longhand.

While a tile is being dragged, `visualIndex(of:at:in:)` computes where every
*other* tile should sit by asking `reordered(moving:to:)` for the hypothetical
order. The model is untouched until the drag ends. The dragged tile's position
animation is deliberately disabled so it tracks the cursor without lag.

### Two things the grid must not do

- The tile itself (`BubbleTile`) is render-only; it takes `pressProgress` and
  draws the swell, but owns no gestures. Keep gesture logic in the grid.
- `store.editingID` suppresses the gesture entirely via `ConditionalGesture`, or
  the text field cannot be clicked into.

### Tree edits funnel through one recursive helper

`Array<BubbleNode>.mutateChildren(at:_:)` walks a `[UUID]` path and hands the
matching child array to a closure. An empty path mutates the receiver, so the
root level is not a special case — every store mutation is
`root.mutateChildren(at: path[...]) { ... }`.

Setting `editingID` away from a blank, childless note discards it (the `didSet`),
which is why `BubbleStore`'s navigation methods clear focus *before* changing
`path` — the cleanup has to resolve against the level still on screen. `drillInto`
re-checks the note still exists afterwards for the same reason.

### The panel is nonactivating but key-capable

`OverlayPanel` combines `.nonactivatingPanel` with an overridden
`canBecomeKey: true`. That pairing is what lets you type into a tile without macOS
activating Note Bubble and pulling focus off the app you were working in — change
either half and text editing or focus behaviour breaks. `collectionBehavior`
carries `.canJoinAllSpaces` and `.fullScreenAuxiliary` so the panel follows you
across Spaces and sits over full-screen apps. Being borderless it also swallows
standard shortcuts, so `keyDown` manually routes ⌘W/⌘M/⌘Q/⌘N and Escape.

`PanelController` swaps the panel's `NSHostingView` between `RootView` and
`MinimisedPill`, resizing about the **top-left** corner (AppKit frames are
bottom-left origin, hence the y adjustment in `resize(to:)`) so collapsing doesn't
fling the widget across the screen.

### Dragging the panel, and first clicks generally

Moving the panel goes through the `panelDraggable` modifier, applied to the glass
bar's **background** and to `StatusHandle`. Putting it on the background is what
makes the whole bar a handle: controls layered above it take their own clicks,
everything else falls through to the drag.

It reports phases to `PanelController` via `PanelDrag`, which moves the window
using `NSEvent.mouseLocation`.

This deliberately does *not* use AppKit's `performDrag`. Two successive attempts
with `WindowDragArea` failed, because that route needs the mouse-down to reach an
`NSView` buried behind SwiftUI content — which depends on layering and first-mouse
in ways that kept silently breaking. Tiles already drag correctly through SwiftUI's
gesture system, so the panel uses the same path. **Don't reintroduce `performDrag`
for the panel.**

`WindowDragArea` survives for the minimised pill. Two things it depends on, both of
which have broken before:

1. **`acceptsFirstMouse` must be true.** Hover-expansion deliberately leaves the
   panel non-key, and AppKit spends the first click on an inactive window
   activating it rather than delivering it — so `mouseDown` never ran and the panel
   could not be dragged in one motion. `FirstMouseHostingView` extends the same fix
   to every control inside the panel, which is why buttons respond on first click.
2. **Nothing hit-testable may sit in front of it.** The header's capsule, border
   and shadow are decorative and carry `.allowsHitTesting(false)`; adding a plain
   `.background(.regularMaterial)` above the drag area silently swallows the drag.
   Same applies to `MinimisedPill`.

### Undo is snapshot-based, and only `pop` records

`BubbleStore` keeps a stack of whole-tree snapshots (`root` + `path` + a label).
Snapshots rather than inverse operations because the tree is small and popping is
the only action that destroys writing — an inverse-op undo can drift out of sync
with the model, a snapshot cannot. Restoring puts `path` back too, so an undone
pop reappears on the level it happened at.

Only `pop` calls `recordUndo`. `discardIfEmpty` deliberately deletes directly
rather than going through `pop`, or every stray double-click would bury the real
pop in the stack.

### Popping is depth-independent, and a hold consumes its release

`BubbleStore.pop` searches the **whole tree** via `removeNode(withID:)`, not just
the current level, and trims `path` if the user was standing inside what just
popped. Tying removal to `path` was a real bug: a confirmation can be answered
after the view has navigated elsewhere, and the pop then silently did nothing.

The navigation that caused it was itself a race — `cancelHold()` cannot stop a
hold task that has already begun executing, so the release after a hold-to-pop
also ran `drillInto`. `consumedByHold` records the decision instead of racing it;
`performPop` sets it, and `.onEnded` refuses to act when it is set.

### Popping with children asks first

`BubbleGrid.performPop` is the gate: tiles with children divert into `pendingPop`
and render `confirmSheet`; everything else falls through to `commitPop`, which is
what actually bursts, plays a sound, records undo and shows the toast. The
confirmation is drawn **inside the panel, not as an `NSAlert`** — a system modal
would activate the app and pull focus off whatever the user was doing, which is
the one thing this widget must never do.

### Sound

`PopSounds` loads `Sounds/pop-1…5` from **`Bundle.main`**, not `Bundle.module`:
the `.app` is assembled by hand, so `build-app.sh` copies `Resources/Sounds`
straight to `Contents/Resources/Sounds` rather than going through an SPM resource
bundle. Declaring SPM `resources:` would break that lookup. The loader tries
several extensions per name so real recordings can be dropped in over the
synthesised `.wav` stand-ins without code changes.

A fresh `AVAudioPlayer` is built per pop from cached `Data` so rapid bursts
overlap rather than cutting each other off, and finished players are held until
they stop — releasing one mid-play silences it.

The shipped clips are Universfield's from Pixabay, added by hand — see
`Resources/Sounds/CREDITS.md`. `Scripts/make-pop-sounds.py` (stdlib only, no
numpy) synthesises `.wav` fallbacks if they ever go missing; `wav` sits last in
the extension order precisely so a regenerated fallback cannot shadow a real
recording. Do not add a scripted download step: Pixabay 403s every non-browser
client and its API has no sound-effects endpoint.

### Transparent panel, opaque tiles

The expanded panel has **no background** — only the header keeps a material, since
its controls need to be legible and it doubles as the drag handle. Tiles are
correspondingly **fully opaque**: with nothing behind them they are the only thing
the label has to sit on, so their glass look comes from highlights and rim light,
not from translucency. They carry a black drop shadow for separation from the
desktop.

Consequently the expanded panel never fades. Window alpha dims *everything*
including tiles, which defeats the point; only the resting pill dims, and
`setHovering` special-cases `!isMinimised` to keep the grid at full alpha.

### Two ways in: the menu bar and the pill

`MenuBarItem` owns an `NSStatusItem` whose title carries the overdue count. Both
mouse buttons route through one action (`sendAction(on:)`) and the menu is
attached only for the duration of a right-click — assigning `item.menu` outright
would make left-click open the menu too, losing the click-to-toggle.

Opening from the menu bar parks the panel under the icon via `moveBelow`, which
positions by the panel's **top** edge because `expand` grows downward from the
top-left. Setting the expanded origin there instead leaves the panel a full
panel-height too low.

The floating pill is optional (`ShowsFloatingPill`, default on). With it off,
`minimise` calls `orderOut` rather than shrinking to the pill.

**Closing is not quitting.** The header's ✕ calls `PanelController.close`, which
hides the window and leaves the status item behind to bring it back. It used to
call `NSApp.terminate`, which took the menu bar icon with it and left no way back
short of relaunching from Finder. Quitting is ⌘Q or the menu bar menu only.

### The pill is the resting state; hover drives everything

`PanelController` starts minimised and treats hover as the primary interaction:
`setHovering(true)` schedules `expand` after `expandDelay` (180ms dwell, so
sweeping past doesn't fling the grid open), `setHovering(false)` schedules
`minimise` after `collapseDelay` (450ms grace, so overshooting an edge doesn't
close it). Both tasks cancel each other and are cancelled by explicit
minimise/expand.

**Hover-expansion passes `takeFocus: false`.** Making the panel key on hover would
divert the user's typing out of whatever app they are actually in — the single
worst thing an always-on-top widget can do. Only a click on the pill, ⌥Space, or
⌘N takes focus.

Auto-collapse re-checks its preconditions *at fire time*, not when scheduled:
pinned, `store.editingID != nil`, or `PanelState.blocksAutoCollapse` all veto it.
`PanelState` exists because the grid knows things the window needs (a confirmation
sheet is open, a tile is mid-drag) that have no business living on the note model.

**`RootView` reports hover as `isHovering || editing`,** tracking real pointer
presence separately from editing state. Reporting a bare `false` when editing ended
told the panel the pointer had left, which scheduled a collapse — so pressing
Return to finish a note minimised the window a moment later, with the pointer
sitting right on it. Never derive hover from an editing change alone.

Alpha is animated on the *window* (1.0 ⇄ `idleAlpha` 0.42), not as a view tint, so
material, tiles and shadows fade as one.

### Ageing is continuous, buckets are only for the badge

`Aging.color(forDays:)` interpolates hue 0.33 → 0.0 across a 7-day window, so a
note decays smoothly rather than jumping between three colours. `Aging.Stage`
(fresh / aging / overdue) exists only where a hard answer is needed — currently
the overdue count on the minimised pill.

### App lifecycle

`main.swift` is top-level code wrapped in `MainActor.assumeIsolated` rather than
`@main`, so `setActivationPolicy(.accessory)` runs before any window exists and
the app never flashes a Dock icon. `LSUIElement` in `Info.plist` keeps it out of
the Dock and menu bar permanently.

`HotKey` uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global
monitor specifically because it needs no Accessibility permission. It holds a
static `active` reference because the C callback cannot capture context.
