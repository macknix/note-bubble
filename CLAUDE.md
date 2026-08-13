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
./Scripts/build-app.sh           # release build + assemble build/Note Bubble.app
./Scripts/build-app.sh debug     # same, debug configuration
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
| Colours / ageing thresholds | `Model/Aging.swift` |
| Any animation or delay | `Support/Motion.swift` — all of them live here |
| Tile sizing, column count, packing | `Layout/GridLayout.swift` |
| Where every tile sits for one render | `Layout/LayoutPlan.swift` |
| Label font, tile padding | `Layout/TileText.swift` (measurement depends on these) |
| Tile corner shape | `Views/TileStyle.swift` |
| Panel size, fade, hover open/close timing | `Window/PanelController.swift` |
| Where the panel sits: snapping, which way it opens | `Window/PanelParking.swift`, rules in `Window/PanelPlacement.swift` |
| The pill's size | `Views/MinimisedPill.swift` |
| Keyboard shortcuts | `Window/OverlayPanel.swift` (⌘…) and `Window/HotKey.swift` (⌥Space) |
| Workspaces: the boards themselves | `Model/Workspace.swift` (and the file's shape), `Model/BubbleStore.swift` |
| What counts as a swipe | `Support/WorkspaceSwipe.swift` decides; `Window/PanelController.swift` feeds it |
| Where a dragged tile is, and which dot it is over | `Support/TileFlight.swift` decides; `Views/BubbleGrid.swift` draws it |
| How long you must rest on a dot before its board slides in | `Motion.workspacePreview` |
| The workspace name and its menu | `Views/WorkspaceChip.swift` |
| The workspace dots — the swipe's affordance, and the drop targets | `Views/WorkspaceDots.swift` |
| What another board looks like mid-drag | `Views/WorkspacePreview.swift` |
| Menu bar icon and its menu | `Window/MenuBarItem.swift` |
| What a tile looks like | `Views/BubbleTile.swift` |
| Tap / hold / drag behaviour | `Support/TileGesture.swift` decides; `Views/BubbleGrid.swift` carries it out |
| Note data, undo, persistence | `Model/BubbleStore.swift` |
| Asking before something destructive | `Views/ConfirmSheet.swift` |
| App icon artwork | `Scripts/make-icon.swift` |

## Invariants worth knowing before editing

1. **A tile never exceeds `maximumHeight`, and clips its own content.** See
   "Tiles are rectangles, packed by masonry" below.
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

Each is load-bearing and each has a comment at its site explaining why.

Notes persist to `~/Library/Application Support/NoteBubble/bubbles.json`, as
`{ version, workspaces, currentID }`. A file from before workspaces existed is a
bare `[BubbleNode]` array; it is recognised by shape, lifted into a single board
named "Notes", and rewritten in the current form on the next save — so there is no
migration step to run, but **an old build will not read a new file**. Delete that
file to reset, or use the demo board above rather than hand-editing dates.
The app holds the tree in memory and writes on change, so quit it before replacing
that file or it will overwrite you on its next save — `demo-data.py` refuses to
install while it is running for exactly that reason.

Where the panel sits is remembered separately, in `UserDefaults`:
`defaults delete com.macknixon.notebubble PanelPlacement` puts it back in the
top-right corner.

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
  Model/                   BubbleNode, BubbleStore, Workspace, Aging
  Layout/                  GridLayout, LayoutPlan, TileText, TileSizeCache
  Support/                 Motion, TileGesture, TileFlight, WorkspaceSwipe
  Views/                   RootView, GlassBar, BarStyle, BarButtons, StatusHandle,
                           WorkspaceChip, WorkspaceDots, WorkspacePreview,
                           BubbleGrid, BubbleTile, TileStyle, PopBurst,
                           ConfirmSheet, ConfirmPopSheet, UndoToast, MinimisedPill,
                           WindowDragArea
  Window/                  OverlayPanel, PanelController, PanelParking,
                           PanelPlacement, PanelState, PanelDrag, MenuBarItem,
                           HotKey
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

The breadcrumb now has its own full-width row — the **place row**, which also
carries the workspace chip and the workspace dots. `PanelController` adds
`placeRowHeight` to the panel whenever `store.showsPlaceRow`. If you add a control
to the top row, check the budget still balances; if you add one to the place row,
remember the chip truncates at 120pt and the dots grow with the number of boards.

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

### Workspaces are separate boards, not another level of nesting

A `Workspace` is a name and a `[BubbleNode]`. The store holds them all and an index
into them; `root` is *the current workspace's* notes, and every existing mutation
goes through `currentNotes` — one private computed property that answers "which
board am I editing" so nothing else has to.

Why not model a workspace as a bubble at the top of the tree? Because nesting means
"this task belongs to that task", and a workspace means "this is a different
context". Making them the same thing would give boards an age, a colour, a tile and
a pop-hold, and would put "Work" one click away from bursting. They are deliberately
not in the tree, which is also why swapping boards clears `path`: a path is a list
of note ids, and those ids mean nothing on another board.

Two consequences worth knowing:

- **Counts are scoped by where they are read, not by what is convenient.** Inside
  the panel — the status handle — a count describes the board in front of you,
  because that is the one you can act on, and what the *other* boards are up to is
  said by the colour of their **dots**. Outside the panel — the resting pill and the
  menu bar icon — there is no board in front of you, so both count **everything**
  (`BubbleStore.everywhere`): a widget at rest that stayed quiet about a note rotting
  on the board you last opened a fortnight ago would be failing at its one job. The
  menu bar's Workspaces submenu breaks that total back down, board by board.
- **The undo snapshot holds every workspace,** not just the current one, because
  deleting a whole board is undoable and there would otherwise be nowhere to put it
  back. Deleting a board with notes on it asks first (`ConfirmSheet`, in-panel, for
  the same reason a pop confirmation is); an empty one just goes.

A board created and then abandoned — never named, nothing written on it — is
discarded when the rename field loses focus. That is `discardWorkspaceIfUnused`,
and it is deliberately the same rule, in the same shape, as `discardIfEmpty` for a
blank note: `renamingWorkspaceID` is the exact counterpart of `editingID`, down to
the `didSet`.

### A tile can be dragged onto another board

Picking a tile up makes the **workspace dots grow into drop targets**. Rest the tile
on one and that board slides into view behind it; let go and the note lands there.
The dots are the target rather than a set of chips raised for the purpose: the row
already means "the other boards", so making it the thing you aim at keeps one idea
in one place instead of replacing it with a second one mid-drag.

**The board you see mid-drag is a picture, not a move.** `panelState.previewWorkspace`
puts another board's top level on screen (`WorkspacePreview`) while `BubbleStore`
stays exactly where it was, for the whole drag. That is not a detail — it is what
makes "nothing happens until you let go" possible at all:

> Switching for real takes the dragged tile's own view off screen along with the
> level it belongs to, and SwiftUI stops delivering drag events to a view that is
> being removed. The tile stops following the cursor, and its release is never
> reported. An earlier version committed the move the instant the dwell elapsed for
> exactly this reason, and a version before that left a bubble frozen in mid-air.

So the real board is held aside (`boardOffset`) and hidden, the previewed board is
drawn in its place, and everything the drag depends on stays mounted underneath.
Because the store never moved, the drop is an ordinary `move(_:toWorkspace:)` from
the current board, and the undo it records returns to the level the note was dragged
from. The switch that follows the move is deliberately **not** animated: the boards
already slid past each other when the preview opened, and animating again would
slide the same board in twice.

The bar reads `previewWorkspace` too, so the chip and the dots name the board that
is actually on screen. A chip reading "Home" over another board's notes is a worse
answer than showing no preview at all.

Where the tile *is* lives in **`Support/TileFlight.swift`**, and it is the other half
of `TileGesture`: one decides what kind of press this is, the other knows where the
tile has got to once that press turns out to be a drag. Neither imports SwiftUI, so
both can be checked without a mouse — which matters, because every symptom this code
has produced (a bubble drawn in the wrong place, a dot that would not light up on a
scrolled board, a tile frozen in a corner) looked identical from the outside.

Three things make it work, and all three are easy to undo by accident:

- **The dragged tile is drawn outside the `ScrollView`** (`BubbleGrid.liftedTile`).
  A scroll view clips its content, so a tile carried up towards the bar is sliced
  off at the grid's top edge and disappears while the pointer goes on without it.
  Drawn as an overlay it is clipped only by the panel, and since the grid is laid
  out *after* the bar in the `VStack` it passes over the bar rather than under it.
  The tile still in the grid keeps its slot and turns invisible — and until the
  flight has its measurements, that one moves and stays visible instead, because
  rearranging is the oldest thing the grid does and must not depend on the newest.
- **`PanelSpace` is the one coordinate space the bar and the grid share.** They are
  siblings: the grid knows where the tile is, the bar knows where the dots are, and
  neither is inside the other. The dots publish their frames in that space through a
  preference; `PanelState` carries them back down.
- **Three coordinate spaces, and mixing them up is silent.** A tile's slot is in the
  grid's scrollable *content*; the copy in the air is drawn in the *viewport*; the
  dots are in the *panel*. `TileFlight` holds both conversions (`GridOffsets`) as
  they were **when the tile was picked up**, measured from the press rather than
  from the drag — a preference published on the render it is read on is a render too
  late. Get them backwards and the dots are unreachable on a scrolled board with
  nothing on screen to say why; hence a flight with no cargo hitting nothing at all
  rather than guessing.

While the tile is over a dot it condenses to half size, so it stops hiding the thing
it is aimed at. Hovering the dot of the board you are already showing takes the
preview away again, which is how a drag is called off without leaving the bar.
`PanelController` holds off `fitToContent` for the duration of a drag and refits when
it ends: boards differ wildly in height, and resizing mid-drag would move the window
— and with it the dots being aimed at — out from under the pointer.

### A swipe is a scroll, intercepted before the grid sees it

Two-finger swipes arrive as `scrollWheel` events, and the grid is a `ScrollView`
that would eat them. `PanelController` therefore installs an
`NSEvent.addLocalMonitorForEvents` monitor: it sees the event first, returns it
untouched when it isn't a swipe (so vertical scrolling still scrolls the grid), and
swallows only the one event that completes a horizontal swipe. A SwiftUI gesture
cannot be layered above a scroll view for this; a *global* monitor would need
Accessibility permission, which this app deliberately never asks for (see `HotKey`).

**The decision lives in `Support/WorkspaceSwipe.swift`, not in the monitor** — the
same split as `TileGesture`, and for the same reason: it is sign-dependent logic
that would otherwise only be testable with a trackpad and a pair of hands. It owns
no clock; the caller passes `NSEvent.timestamp` in. Three rules, each fixing a
specific misfire:

1. **One switch per gesture.** Committing latches until the next gesture begins, so
   the momentum that keeps arriving for a second after your fingers lift cannot
   flick you three boards along.
2. **Horizontal must beat vertical outright** (`axisRatio`). Scrolling a long board
   is mostly vertical with a wobble of horizontal in it.
3. **It follows the fingers, not the content.** `scrollingDeltaX` flips sign with
   the "natural scrolling" setting; `isDirectionInvertedFromDevice` is used to
   normalise it, so swipe-left is the next board on either setting — like Safari's
   back and forward, which are gestures rather than scrolls.

The monitor also refuses while `panelState.blocksAutoCollapse` is set, i.e. mid-drag
or with a confirmation open — the same flag, for the same reason, as the
auto-collapse. `BubbleGrid` keys the tile layer by `store.currentWorkspaceID` and
slides it, reading `store.switchDirection` to know which edge to come from;
`onChange` cannot serve that, because the transition is decided during the very
render the switch causes.

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

Positions are therefore **no longer derivable from an index alone**. `LayoutPlan`
(`Layout/LayoutPlan.swift`) is built once per render and holds sizes, resting
frames, and the reflowed centres under a live drag. Anything positional goes
through it.

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
`fitToContent` to read post-change state. Resizing anchors the panel's parked
corner like every other resize here — see "The panel remembers its corner".

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
- **The layout is computed once per render** — one `LayoutPlan`, built at the top
  of `body` and passed down. Deriving frames or the reflow order per tile makes a
  drag O(n²) per frame: every tile asking for the hypothetical order that every
  other tile has just asked for.

### One gesture does tap, hold and drag

`BubbleGrid.gesture(for:index:plan:layout:)` is a single `DragGesture` with
`minimumDistance: 0`, and discriminates by hand: movement past `dragSlop` means
rearrange (which cancels the pop countdown), holding still until `popHold` means
pop, releasing before either means enter. **Do not split this into
`.onTapGesture` + `.onLongPressGesture` + `.gesture`** — SwiftUI cannot arbitrate
three overlapping gestures on one view reliably, and that is the whole reason the
state machine is written out longhand.

**The decisions live in `Support/TileGesture.swift`, not in the view.** It is a
plain value — no SwiftUI, no store, no layout, and deliberately no clock: the view
runs the countdown and reports `.holdElapsed` when it fires, because a machine that
owned a clock could not be tested without waiting for one. Its counterpart is
`TileFlight`, which knows *where* the tile has got to once the press turns out to be
a drag; between them the view is left holding almost nothing. `BubbleGrid` feeds it
`.changed` / `.holdElapsed` / `.ended` and carries out the `Effect`s it returns.
Two rules are worth knowing before touching it:

- **A hold consumes its release.** Cancelling the countdown cannot stop a task that
  has already begun, so the decision is recorded (`.consumed`) rather than raced.
  For the same reason `.holdElapsed` arriving *after* a drag has started is
  ignored, which is what stops a rearrange bursting the tile it is rearranging.
- **Ending a press and clearing the screen are two different things**, because half
  of what ends a drag happens *mid-press, with the button still down*. `endPress`
  resets the machine and is for a tile that has gone: a popped tile is removed, and
  SwiftUI does not reliably deliver `onEnded` for a view that no longer exists, so
  without the reset the machine sits holding a tile that isn't there and refuses
  every later press. `cancelDrag` **consumes** instead, and is for a tile that is
  still around to send events — one filed onto another board, or a pop waiting on
  its confirmation.

  Getting that the wrong way round is what froze a bubble on screen. A version that
  filed a note the moment the dwell elapsed reset the press while the button was
  still down; the board's slide-out kept the tile's view alive for another third of
  a second; the next twitch of that unreleased button arrived at an `.idle` machine,
  which read it as a **new** press, dragged it past the slop, and lifted a second
  tile out of a layout that had already been replaced. That one never got a release
  — its view was on its way out — so it hung in the air at the old tile's slot,
  which for the first tile is the top-left corner. Carrying a tile to another board
  no longer switches the store mid-drag at all (see "A tile can be dragged onto
  another board"), so that particular version is gone — but the rule stands for
  everything else that decides a press early: a consumed press ignores everything
  until it is genuinely let go.

  The other half of that bargain: a consumed press **yields to a press on a
  different tile**, because its release usually never arrives at all, and without
  yielding it would be a stuck key.

This split is also the one piece of porting groundwork that is already done: touch
has no hover, a fatter slop and system gestures competing for the same events, so
an iOS version can retune `dragSlop`, feed the same events from a
`UIGestureRecognizer`, and still run logic that is known-good.

While a tile is being dragged, `visualIndex(of:at:in:)` computes where every
*other* tile should sit by asking `reordered(moving:to:)` for the hypothetical
order. The model is untouched until the drag ends. The dragged tile's position
animation is deliberately disabled so it tracks the cursor without lag.

### Two things the grid must not do

- The tile itself (`BubbleTile`) is render-only; it takes `pressProgress` and
  draws the swell, but owns no gestures. Keep gesture handling in the grid, and the
  decisions it makes in `TileGesture`.
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
standard shortcuts, so `keyDown` manually routes ⌘W/⌘M/⌘Q/⌘N, ⌘⇧N (new workspace),
⌘←/⌘→ (previous/next workspace) and Escape. It is the end of the responder chain,
so a focused text field has already had its go — ⌘← inside a note still means
"start of line" and never reaches here.

`PanelController` swaps the panel's `NSHostingView` between `RootView` and
`MinimisedPill`, resizing about the corner the panel is parked in so collapsing
doesn't fling the widget across the screen.

### The panel remembers its corner

Position is deliberately not the controller's business. It is three files, in
layers, and a change to any one of them should not need the others:

| | |
|---|---|
| `PanelPlacement.swift` | the rules, as plain geometry over rectangles — no AppKit, no windows, so this is where they are tested |
| `PanelParking.swift` | the wiring: `NSScreen` in, `UserDefaults` out. Owns the parked corner and answers "what frame should a panel this size take?" |
| `PanelController` | *when* the panel changes size. It asks `parking.frame(sized:)` and never computes a position itself |

`MinimisedPill.size` is the pill's window, declared next to the view that fills it.

The rules layer is three ideas:

1. **`PanelAnchor`** is which corner holds still when the panel changes size. The
   pill and the expanded grid are wildly different sizes, so something has to. It
   is resolved by comparing *gaps* to each screen edge, not the panel's centre
   against the screen's, so the answer doesn't change with the panel's width — an
   expanded panel flush right must still read as right-anchored.
2. **`PanelGeometry.snapped`** pulls the panel flush when a drag brings it within
   `snapDistance` of a screen edge. Each axis snaps independently, which is what
   makes corners fall out of two edges. Edges shared with a second display are
   excluded (`openEdges(of:among:)` probes just beyond each edge, at three points
   along it since displays are rarely aligned neatly): snapping there would cement
   the panel to the boundary with no way to drag it onto the next screen.
3. **`PanelPlacement`** — the corner plus which corner it is — is persisted to
   `UserDefaults`. It is specifically where the **pill** rests: the pill is the
   resting state, so it is the thing that must never appear to move.

Together these are why a widget parked top-right opens leftwards and downwards and
folds back into that corner, and bottom-left does the mirror image.

Two rules keep it from wandering, and both are fixes rather than precautions:

- **Every size is measured from the parked corner, never from the current frame.**
  `PanelParking.frame(sized:)` hangs the new size off that corner and clamps the
  result for display only — the clamp deliberately does not feed back into the
  placement. Re-reading the corner off a clamped frame — an expanded panel too tall
  for the room below it gets pushed up the screen to fit — made the pill creep a
  little further each time it opened and closed.
- **A panel dragged by its bar parks by its top edge** (`init(draggedPanel:in:)`),
  whatever half of the screen it lands in, because the bar is the handle and the
  panel has to fold up towards the thing under your cursor. Resolving the nearest
  corner here instead put the pill on the panel's *bottom* edge, hundreds of points
  below the bar. It looked fine in the top half of the screen, where the nearest
  corner is the top one — which is exactly why it read as "the bottom half is
  broken". Dragging the **pill** still resolves both axes by nearest edge; that is
  what parks it in a corner in the first place.

The placement is re-read only when the panel is deliberately moved, and there is
one method per way that can happen: `park(pill:)`, `park(draggedPanel:)` and
`park(settledPill:)` — the last for the one case where a clamp is allowed to win,
a corner that no longer fits on any screen.

### Resize the window, then install the view

`PanelController.show(_:sized:)` does both, in that order, and the order is why it
exists as one method. Installing the view first lays it out at the size the panel
*was*: opening from the pill, `BubbleGrid` measured 132pt of width, concluded that
was one column, and stacked every tile vertically — then the window jumped to 432pt
and the tiles animated out of that column into their real slots. A visible cascade
on every single open.

It read as an edge-specific bug, and was reported as one. Opening from the right of
the screen the window's *origin* moves as well as its size, so the tiles started
300pt right of where they belonged and travelled the whole way back; opening from
the left the origin holds still and only the fan-out shows. Same bug, twice as
obvious on one side. An empty board hides it completely, which is worth knowing
when checking this by hand — use `Scripts/demo-data.py install`.

**`FirstMouseHostingView` sets `sizingOptions = []`,** and that is load-bearing.
A hosting view otherwise pushes its content's fitting size onto the window as
`contentMinSize`/`contentMaxSize`, and AppKit clamps the frame to it about the
top-left — which quietly shrank the pill window to its content whatever
`MinimisedPill.size` said. A pill snapped flush right then sat 60pt inside the edge
and crept further left on every cycle. `MinimisedPill` correspondingly fills its
window rather than sizing itself, so "flush to the edge" means the pill is flush
and not merely its transparent window.

### Dragging the panel, and first clicks generally

Moving the panel goes through the `panelDraggable` modifier, applied to the glass
bar's **background** and to `StatusHandle`. Putting it on the background is what
makes the whole bar a handle: controls layered above it take their own clicks,
everything else falls through to the drag.

It reports phases to `PanelController` via `PanelDrag`, which moves the window
using `NSEvent.mouseLocation`, snapping to screen edges as it goes and adopting the
corner it was dropped in.

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

`performDrag` moves the window from inside its own tracking loop, so there is no
way to apply edge magnetism *during* a pill drag without fighting it. It is
synchronous — it returns on mouse-up — so `DragView.mouseDown` calls
`windowDragEnded()` afterwards and the pill snaps on release, animated. The bar
snaps live; the pill snaps as it lands.

### Undo is snapshot-based, and only real destruction records

`BubbleStore` keeps a stack of snapshots (every workspace + `currentIndex` + `path`
+ a label). Snapshots rather than inverse operations because the tree is small and
destroying writing is rare — an inverse-op undo can drift out of sync with the
model, a snapshot cannot. Restoring puts the board and `path` back too, so an
undone pop reappears on the level *and the workspace* it happened at.

Four things call `recordUndo`: `pop`, `shuffle`, `removeWorkspace`, and
`move(_:toWorkspace:)` — nothing is destroyed by the last, but a note filed onto
another board is just as hard to find again by hand. Filing records while the store
is still on the board the note is leaving, which is what makes the snapshot return
you to that board *and* that level rather than to wherever the note went.

The two cleanup paths — `discardIfEmpty` for a never-written note and
`discardWorkspaceIfUnused` for a never-named board — deliberately delete directly
rather than going through them, or every stray double-click would bury a real pop
in the stack.

### Popping is depth-independent, and a hold consumes its release

`BubbleStore.pop` searches the **whole tree** via `removeNode(withID:)`, not just
the current level, and trims `path` if the user was standing inside what just
popped. Tying removal to `path` was a real bug: a confirmation can be answered
after the view has navigated elsewhere, and the pop then silently did nothing.

The navigation that caused it was itself a race — `cancelHold()` cannot stop a
hold task that has already begun executing, so the release after a hold-to-pop
also ran `drillInto`. `consumedByHold` records the decision instead of racing it;
`performPop` sets it, and `.onEnded` refuses to act when it is set.

### Anything that destroys writing asks first

`BubbleGrid.performPop` is the gate: tiles with children divert into `pendingPop`
and render `confirmSheet`; everything else falls through to `commitPop`, which is
what actually bursts, plays a sound, records undo and shows the toast. The
confirmation is drawn **inside the panel, not as an `NSAlert`** — a system modal
would activate the app and pull focus off whatever the user was doing, which is
the one thing this widget must never do.

That rule is why `ConfirmSheet` is a view rather than a call into AppKit. Deleting a
workspace with notes on it raises the same sheet, from `RootView` — the only other
action that can destroy writing in a single click.

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
would make left-click open the menu too, losing the click-to-toggle. The menu is
rebuilt on every click, which is why its Workspaces submenu can carry indices in
`NSMenuItem.tag` without going stale. Picking a board there *opens* the panel on
it: switching a board you cannot see would be a no-op you'd never notice.

Opening from the menu bar reopens the panel **where it was last left**, across a
quit as well as a close — a widget you have parked in a particular corner should
stay there, and being relocated on every open is the more surprising behaviour by
far. `moveBelow` is only the fallback for when that spot has gone (a display
unplugged since, so `parking.isOnScreen` is false), which would otherwise strand
the panel somewhere unreachable. It parks the **pill** under the icon and lets
`PanelParking` work out which way the panel should then open.

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
