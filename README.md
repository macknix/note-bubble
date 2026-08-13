# Note Bubble

A floating to-do widget for macOS. Notes are bubbles that sit over whatever you're
working on — they grow to fit what you write, pack themselves together, redden as
they get old, and pop when the task is done.

- **Triage by colour.** Every note is dated and shifts green → amber → red over a
  week, so what's gone stale is obvious without reading anything.
- **Bubbles inside bubbles.** Any note can hold sub-notes, arbitrarily deep.
- **Separate boards.** Keep work, home and someday apart, and two-finger swipe
  between them. Drag a bubble onto another board to file it there.
- **Out of the way.** It rests in the menu bar and as a small pill; hover to open,
  move away and it folds back. No Dock icon, nothing in ⌘-Tab.
- **Popping is the reward.** Hold a bubble, watch it swell, and it bursts with a
  sound. ⌘Z if you were wrong.

Requires **macOS 14 or later**. Apple silicon or Intel.

## Install

Note Bubble isn't code-signed with an Apple Developer certificate, so building it
yourself is the path of least resistance — it takes one command and needs no Xcode,
only the Command Line Tools that `git` already pulled in.

```bash
git clone https://github.com/macknix/note-bubble.git
cd note-bubble
./Scripts/build-app.sh
open "build/Note Bubble.app"
```

If `swift` isn't found, run `xcode-select --install` first.

To keep it: drag `build/Note Bubble.app` into `/Applications`, then add it to
**System Settings → General → Login Items** so it's there every morning.

> **Downloading a prebuilt copy instead?** macOS quarantines apps from the internet
> that aren't notarised, and will say Note Bubble is damaged. It isn't — that's
> Gatekeeper refusing an unsigned app. Either right-click the app and choose
> **Open**, or clear the flag:
> `xattr -dr com.apple.quarantine "/Applications/Note Bubble.app"`.
> Building from source avoids this entirely, because locally built apps are never
> quarantined.

Nothing leaves your machine: no accounts, no network, no telemetry. Notes are a
plain JSON file in your own Application Support folder.

## Using it

| Action | How |
|---|---|
| **Open a bubble** | Single click |
| **Pop a bubble** (done) | Press and hold — it swells, then bursts |
| **Undo a pop** | **⌘Z**, the toast that appears, or ↩ in the bar |
| **Rearrange** | Drag a tile; the others shuffle around it |
| **Switch workspace** | **Two-finger swipe** across the panel, ⌘← / ⌘→, or click a dot |
| **Move a bubble to another workspace** | Drag it onto that workspace's dot, and let go |
| New workspace | ⌘⇧N, or *New workspace* in the workspace menu |
| Shuffle everything | The 🔀 button — undoable with ⌘Z |
| **Finish writing** | **⏎** — or click anywhere off the tile |
| Discard an edit | **Esc** — puts back what it said before |
| Second line in a note | ⇧⏎ |
| New bubble | The pink **+**, double-click empty space, or ⌘N |
| Rename | The ✏️ on hover, or right-click → Rename |
| Go back up | `‹` in the bar, a breadcrumb crumb, or Escape |
| Move the widget | Drag **anywhere on the top bar** that isn't a button |
| Close it | `✕` — stays in the menu bar, click the icon to reopen |
| Minimise | Move the pointer away, Escape at the top level, or ⌘M |
| Show / hide | **⌥Space** from anywhere, or click the menu bar icon |
| Quit for real | ⌘Q, or the menu bar menu |

Right-click a tile for open, rename, **reset age to today**, and pop.

Popping a tile that still contains unpopped bubbles asks first, since the whole
subtree goes with it. Everything else pops immediately — and is undoable anyway.

### In the menu bar

Note Bubble sits in the macOS menu bar. **Click the icon** to open or close the
grid — it appears just below the icon. When anything has gone red the icon shows
the count beside it, so the thing the traffic lights exist to tell you is visible
without opening anything.

**Right-click the icon** for Open, a **Workspaces** submenu, *Show floating pill*,
*Mute pop sounds*, and Quit. Picking a workspace there opens the panel on it, and
any board with overdue notes says so beside its name — so a board you haven't
looked at in a fortnight can still get your attention.

### Staying out of the way

As well as the menu bar, Note Bubble rests on screen as a small pill. Hover it for
a moment and it opens into the full grid; move the pointer away and it folds back
after about half a second. The resting pill dims when unattended and brightens as
you approach, so it reads as a hint rather than a window.

If the pill on screen is one affordance too many, turn off **Show floating pill**
in the menu bar menu — Note Bubble then hides completely when closed and the menu
bar icon becomes the only way in.

When open there's **no panel background** — the tiles float directly over your work,
with a single bar of frosted glass carrying the controls. Its edge catches an
iridescent rim like the film on a soap bubble. The tiles themselves stay fully
solid, so notes are always easy to read whatever is behind them.

Nothing is lost to an accidental fold: it will not collapse while you're typing a
note, mid-drag, or with a confirmation open. If you want it to stay open, the 📌
pin button holds it until you unpin, and ⌥Space opens it outright.

Hovering deliberately does **not** give the panel keyboard focus — only clicking it
or pressing ⌥Space does — so passing over it never diverts your typing from the app
you're actually working in.

### Writing a note

Your text is saved on every keystroke, so **⏎ isn't a save — it just finishes**.
Clicking off the tile does the same thing, and **Esc** puts back what the note said
before you started. A small `⏎ done` hint sits under the cursor while you type.

### Tiles grow to fit what's on them

Each tile is measured against its actual text and takes whatever height that needs.
Text is left-aligned at a fixed size, so a bigger tile genuinely holds more words
rather than just bigger ones. A note that would tower in one column widens to two
instead; one longer than fits even then truncates rather than growing forever.

Tiles are **packed by masonry**: each one drops into whichever column is currently
shortest, so small notes tuck in beside tall ones instead of leaving a gap under
every short tile. Widths snap to whole columns, which keeps the result reading as a
grid rather than a scrapbook.

The panel itself is only as tall as it needs to be, growing as you add bubbles and
scrolling once it would get taller than about 560pt.

### Nesting

Bubbles inside bubbles are the whole directory structure. A tile with a number
badge has that many sub-bubbles in it; click to go in, and the breadcrumb along
the top takes you back out. Popping a bubble pops everything inside it, so a
parent is done when its contents are.

### Workspaces

One board is often enough, and if you only ever have one you will never see any of
this: the second row of the bar appears when there is something to say. Make another
with **⌘⇧N** and it opens straight into naming it — leave the name blank and never
write anything on it and it quietly goes away again, exactly like an empty bubble.

**Two-finger swipe** across the panel to move between boards, the way you would
between pages. ⌘← and ⌘→ do the same thing from the keyboard. The dots at the right
of the bar are the affordance and the map: one per board, in order, with the one
you're on drawn wider.

Each dot is coloured by the **worst thing on that board**, so a board going red
while you're looking at another one still says so. The counts *in the bar* describe
only the board in front of you, because that's the one you can do something about —
which is exactly why the dots speak for the rest.

The pill and the menu bar icon are the other way round: they're what you see when
the panel is closed and there's no board in front of you, so they count **every
bubble on every board**. Minimised with three boards on the go, the pill reads
*12 overdue, all told*.

**To file a bubble somewhere else, drag it onto that board's dot.** Rest it there
for a moment and that board slides into view behind the bubble still in your hand,
so you can see where it's about to go. Nothing has happened yet: move to a different
dot to change your mind, or back to the dot of the board you started on to call it
off. Let go and the note lands there. ⌘Z brings it back.

Click the workspace name for the full list, plus rename and delete. Deleting a board
with notes on it asks first, and is undoable. Hover the resting pill to be told which
board it will open on.

### The traffic lights

Tiles are dated from when you wrote them and shift colour continuously:

- **Green** — 0–2 days old
- **Amber** — 3–6 days
- **Red** — a week or more

Red means it's been sitting there long enough to deserve a decision. If a note is
still legitimately live, right-click → *Reset age to today* puts it back to green
without retyping it.

The badges at the top left of the bar count how many notes are in each state across
the current board's whole tree. Only states you actually have are shown, and the overdue badge
pulses when it isn't zero. The menu bar icon and the minimised pill show an overdue
count too — theirs covers every board, since when the panel is shut there's no board
in front of you.

## Pop sounds

Five bubble pops by Universfield from Pixabay live in `Resources/Sounds/`, one
chosen at random per burst (never the same one twice running). See
[`Resources/Sounds/CREDITS.md`](Resources/Sounds/CREDITS.md) for which original
file is which. The speaker button in the bar mutes them, and that's remembered.

To swap one, keep the `pop-N` name — `PopSounds` looks up `mp3`, `m4a`, `aiff`,
`caf`, then `wav`, and re-run `./Scripts/build-app.sh`.

`python3 Scripts/make-pop-sounds.py` synthesises `.wav` fallbacks if the real files
are ever missing. `wav` is last in the lookup order specifically so those
fallbacks can never shadow a real recording.

## Where notes live

`~/Library/Application Support/NoteBubble/bubbles.json` — plain JSON, safe to
back up, sync, or edit by hand. Delete it to start over.

It holds every workspace and which one was open. A file written before workspaces
existed is read as it always was and lifted into a single board called *Notes*, so
upgrading takes nothing on your part — but once it has been saved in the new shape,
an older build will not read it.

## Development

```bash
swift build                # compile check
swift run NoteBubbleTests  # test suite (341 checks)
./Scripts/build-app.sh     # assemble build/Note Bubble.app
```

`swift test` is **not** used: XCTest and swift-testing both ship with Xcode, and
this project builds with Command Line Tools alone. The suite is a plain
executable over a small assertion harness instead, and exits non-zero on failure.

[`CLAUDE.md`](CLAUDE.md) is the architecture guide — module map, a "where to
change things" table, and the handful of invariants the design rests on. Read it
before making structural changes.

### Demo data

```bash
python3 Scripts/demo-data.py install   # 37 notes, 3 workspaces, 3 levels deep
python3 Scripts/demo-data.py restore   # put your own notes back
```

Three boards: a full one, a small one, and an empty one, so swiping, the dots and
the empty state all have something to exercise. Your own notes are backed up first,
and the ages are recalculated each time it runs so the traffic lights are always
properly spread. Quit Note Bubble before
installing — it keeps notes in memory and would overwrite the file on its next save.

### Regenerating assets

```bash
swift Scripts/make-icon.swift        # Resources/AppIcon.icns
python3 Scripts/make-pop-sounds.py   # synthesised .wav pop fallbacks
```

The app icon is **drawn in code** rather than stored as a binary asset, so it
stays editable without an image editor and stays visually in step with the tiles
it depicts. Edit `drawIcon(size:)` in `Scripts/make-icon.swift`, re-run it, and
rebuild. `iconutil` does the packing; no Xcode involved.

Because Note Bubble is an accessory app it has no Dock icon — the icon appears in
Finder, Spotlight, and System Settings → Login Items.

## Credits

Pop sounds are five *Bubble Pop* effects by **Universfield**, from
[Pixabay](https://pixabay.com/sound-effects/), used under the Pixabay Content
License. See [`Resources/Sounds/CREDITS.md`](Resources/Sounds/CREDITS.md) for which
is which.

Everything else — code, app icon, and the synthesised fallback sounds — is original
to this project. The icon and fallbacks are generated by scripts rather than
checked in as opaque binaries, so both stay editable.

## License

MIT — see [LICENSE](LICENSE). The bundled Pixabay sounds are covered by their own
license, noted above.
