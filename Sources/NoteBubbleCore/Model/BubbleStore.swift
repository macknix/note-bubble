import Foundation
import Combine

/// Owns the workspaces, the note tree inside the current one, the drill-in path,
/// and persistence.
///
/// Everything the UI edits goes through here so there is exactly one place that
/// knows how to walk the tree and one place that writes to disk.
@MainActor
final class BubbleStore: ObservableObject {
    /// Every board, in the order they are swiped through. **Never empty** — see
    /// `BubbleDocument.normalised`, which is the only way one gets in here.
    @Published private(set) var workspaces: [Workspace] {
        didSet { tallies.removeAll(keepingCapacity: true) }
    }
    /// Which of them is on screen.
    @Published private(set) var currentIndex: Int = 0
    /// IDs from the root down to the level currently on screen. Empty means top level.
    @Published private(set) var path: [UUID] = []
    /// Bubble currently being typed into, if any. Moving focus away from a bubble
    /// that was never written in cleans it up, so a stray double-click leaves no litter.
    @Published var editingID: UUID? {
        didSet {
            guard let previous = oldValue, previous != editingID else { return }
            discardIfEmpty(previous)
        }
    }

    /// Workspace whose name is being typed into, if any. The exact counterpart of
    /// `editingID`, down to the cleanup: a board created and then left unnamed and
    /// empty is a stray click, not a board.
    @Published var renamingWorkspaceID: UUID? {
        didSet {
            guard let previous = oldValue, previous != renamingWorkspaceID else { return }
            discardWorkspaceIfUnused(previous)
        }
    }

    /// Whether the user is mid-keystroke anywhere — a note or a workspace name.
    /// The panel must not fold away underneath either.
    var isEditing: Bool { editingID != nil || renamingWorkspaceID != nil }

    /// Which way the last workspace change went: +1 forwards, -1 back. Presentation
    /// state, kept here because the grid has to know *before* it renders the new
    /// board which edge to slide it in from, and `onChange` fires too late for that.
    /// Deliberately not `@Published`: it is read during the render that the index
    /// change already caused.
    private(set) var switchDirection = 1

    /// Top-level bubbles of the workspace on screen.
    var root: [BubbleNode] { currentNotes }

    /// The same array, writable. Everything that edits the tree goes through this
    /// rather than reaching into `workspaces`, so "which board am I editing" is
    /// answered in exactly one place.
    private var currentNotes: [BubbleNode] {
        get { workspaces.indices.contains(currentIndex) ? workspaces[currentIndex].notes : [] }
        set {
            guard workspaces.indices.contains(currentIndex) else { return }
            workspaces[currentIndex].notes = newValue
        }
    }

    private let file: BubbleFile
    private var saveTask: Task<Void, Never>?

    /// False when the file on disk must not be written over: it belongs to a newer
    /// build, or it could not be read and could not be moved out of the way either.
    /// Edits still work for the session; they just are not saved.
    private var canSave = true
    /// Whether this session has written yet. The first write backs the file up.
    private var hasSaved = false

    /// Something the user needs to know about their notes file — it could not be
    /// read, or will not be saved to. Shown in the panel until dismissed.
    @Published private(set) var fileNotice: String?

    func dismissFileNotice() { fileNotice = nil }

    // MARK: - Undo

    /// What it takes to reverse one destructive action **against the state as it is
    /// now** — not a copy of the whole app as it was.
    ///
    /// Undo used to be snapshots of every workspace, restored wholesale. That made it
    /// impossible to get wrong in one direction and silently destructive in the
    /// other: popping a note and then writing for ten minutes meant ⌘Z brought the
    /// note back and threw the ten minutes away. Each case below therefore carries
    /// only what the action took, and is put back into whatever is there today —
    /// with every lookup by id, so later edits, additions and reorders survive.
    private enum UndoAction {
        /// A note and its subtree, and where it sat.
        case pop(BubbleNode, from: NodeLocation)
        /// The order a level had before it was jumbled.
        case shuffle(workspace: UUID, parentPath: [UUID], order: [UUID])
        /// A note filed onto another board, and where it came from.
        case file(UUID, from: NodeLocation, to: UUID)
        /// A whole board, and where it sat on the shelf.
        case removeWorkspace(Workspace, index: Int)
    }

    /// Where a note sat, by ids rather than by indices into a particular tree.
    private struct NodeLocation {
        let workspace: UUID
        let parentPath: [UUID]
        let index: Int
    }

    private struct UndoRecord {
        let id = UUID()
        let action: UndoAction
        let label: String
        /// Where the user was standing when it happened, so undoing returns them
        /// there and the note reappears in front of them.
        let workspace: UUID
        let path: [UUID]
    }

    private var undoStack: [UndoRecord] = []
    private static let undoLimit = 30

    /// Describes what ⌘Z would put back, for the toast and the menu hint.
    @Published private(set) var undoLabel: String?

    var canUndo: Bool { !undoStack.isEmpty }

    /// Identifies what ⌘Z would undo right now. Whatever offers an undo for one
    /// particular action — the toast — holds on to this, so it can tell when
    /// something newer has been recorded on top and its offer no longer applies.
    var lastUndoID: UUID? { undoStack.last?.id }

    /// Undoes the action `id` names, and only if it is still the most recent one.
    /// Returns whether it did.
    @discardableResult
    func undo(ifLatest id: UUID) -> Bool {
        guard lastUndoID == id else { return false }
        undo()
        return true
    }

    private func recordUndo(_ action: UndoAction, label: String) {
        undoStack.append(
            UndoRecord(action: action, label: label, workspace: currentWorkspaceID, path: path)
        )
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        undoLabel = label
    }

    /// Reverses the most recent destructive action, then returns to the board and
    /// level it happened on so what came back is in front of you.
    ///
    /// Nothing done since is touched. Where the place something came from has itself
    /// gone — its parent popped in the meantime — it lands at the nearest surviving
    /// ancestor rather than nowhere.
    func undo() {
        guard let record = undoStack.popLast() else { return }
        editingID = nil
        renamingWorkspaceID = nil

        switch record.action {
        case let .pop(node, from):
            insert(node, at: from)

        case let .shuffle(workspace, parentPath, order):
            guard let index = workspaceIndex(workspace) else { break }
            let resolved = workspaces[index].notes.resolvedPrefix(of: parentPath)
            guard resolved == parentPath else { break }
            workspaces[index].notes.mutateChildren(at: parentPath[...]) { children in
                let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
                // Notes the shuffle never saw — added since — keep their places at the end.
                let known = children.filter { rank[$0.id] != nil }
                    .sorted { rank[$0.id]! < rank[$1.id]! }
                children = known + children.filter { rank[$0.id] == nil }
            }

        case let .file(id, from, destination):
            // The note as it is *now*, edits made on the other board included.
            guard let target = workspaceIndex(destination),
                  let node = workspaces[target].notes.node(withID: id)
            else { break }
            workspaces[target].notes.removeNode(withID: id)
            insert(node, at: from)

        case let .removeWorkspace(workspace, index):
            guard workspaceIndex(workspace.id) == nil else { break }
            let current = currentWorkspaceID
            workspaces.insert(workspace, at: min(index, workspaces.count))
            currentIndex = workspaceIndex(current) ?? currentIndex
        }

        returnTo(workspace: record.workspace, path: record.path)
        undoLabel = undoStack.last?.label
        scheduleSave()
    }

    private func workspaceIndex(_ id: UUID) -> Int? {
        workspaces.firstIndex { $0.id == id }
    }

    /// Puts a note back where it was, or as near as the tree now allows. Never
    /// duplicates one that is somehow already back.
    private func insert(_ node: BubbleNode, at location: NodeLocation) {
        guard let index = workspaceIndex(location.workspace) ?? workspaces.indices.first,
              workspaces[index].notes.node(withID: node.id) == nil
        else { return }
        let parent = workspaces[index].notes.resolvedPrefix(of: location.parentPath)
        // If the parent has gone, the old index means nothing at its ancestor; append.
        let slot = parent == location.parentPath ? location.index : Int.max
        workspaces[index].notes.mutateChildren(at: parent[...]) { children in
            children.insert(node, at: min(slot, children.count))
        }
    }

    private func returnTo(workspace: UUID, path target: [UUID]) {
        if let index = workspaceIndex(workspace), index != currentIndex {
            switchDirection = index > currentIndex ? 1 : -1
            currentIndex = index
        }
        path = currentNotes.resolvedPrefix(of: target)
    }

    init(fileURL: URL? = nil) {
        self.file = BubbleFile(url: fileURL ?? Self.defaultFileURL())
        // Replaced wholesale by `load()`; declared here because `workspaces` has no
        // meaningful empty state — the invariant is that there is always one.
        self.workspaces = [Workspace()]
        load()
    }

    // MARK: - Current level

    /// The bubbles to draw right now, i.e. the children at `path`.
    var visible: [BubbleNode] {
        root.children(at: path[...])
    }

    /// Names of the bubbles from the root to here, for the breadcrumb.
    var breadcrumb: [String] {
        var names: [String] = []
        var level = root
        for id in path {
            guard let node = level.first(where: { $0.id == id }) else { break }
            names.append(node.displayName)
            level = node.children
        }
        return names
    }

    var isAtRoot: Bool { path.isEmpty }

    /// Whether the bar shows its second row — the one saying where you are. It lives
    /// here rather than in the view because `PanelController` has to add the row's
    /// height to the panel, and the two must never disagree about whether it's there.
    var showsPlaceRow: Bool { !isAtRoot || hasMultipleWorkspaces }

    /// The time every age in the app is measured against.
    ///
    /// Held here rather than read from the system clock at render time, because a
    /// render only happens when something changes — and on a widget left alone for
    /// days, nothing does. Ages read straight off `Date()` froze at whatever the last
    /// edit was: a note could go overdue overnight and the pill still say green.
    /// `AgeClock` advances this as time passes; being `@Published`, that re-renders
    /// every tile and count and refreshes the menu bar badge.
    @Published private(set) var now = Date() {
        didSet { tallies.removeAll(keepingCapacity: true) }
    }

    /// Each board's `StageTally`, worked out at most once per change.
    ///
    /// Counts are read on every render, and from several places at once: the status
    /// handle, every workspace dot, the pill, the menu bar. Walking each tree for
    /// each of them, on every keystroke, was most of the cost of typing. Any change
    /// to the boards or the clock forgets the lot; the next read refills it.
    private var tallies: [UUID: StageTally] = [:]

    /// How a board's notes, at any depth, are spread across the stages — cached.
    func tally(of workspace: Workspace) -> StageTally {
        if let cached = tallies[workspace.id] { return cached }
        let tally = workspace.tally(at: now)
        tallies[workspace.id] = tally
        return tally
    }

    /// Moves `now` on. Called by `AgeClock`, and by anything that stamps a note with
    /// the real time, so that note never reads as written in the future.
    func advanceClock(to date: Date = Date()) {
        guard date > now else { return }
        now = date
    }

    /// How the whole tree is distributed across the traffic lights. Drives the
    /// status handle in the top bar, which is the only place all three are shown.
    var stageCounts: StageTally {
        tally(of: currentWorkspace)
    }

    /// Every unpopped bubble in the app, and how many of them have gone red.
    ///
    /// The opposite scoping to `stageCounts`, deliberately, and the two are used in
    /// opposite places. **Inside the panel** a count describes the board in front of
    /// you, because that is the one you can act on. **Outside it** — the resting
    /// pill and the menu bar icon — there is no board in front of you, so a count
    /// that only described one would be quietly ignoring the rest of your notes.
    var everywhere: StageTally {
        workspaces.reduce(StageTally()) { $0 + tally(of: $1) }
    }

    // MARK: - Workspaces

    /// The board on screen. `workspaces` is never empty and every method that moves
    /// `currentIndex` keeps it in range, so the fallback is never reached — it is
    /// there so a broken invariant shows an empty board rather than crashing.
    var currentWorkspace: Workspace {
        workspaces.indices.contains(currentIndex) ? workspaces[currentIndex] : Workspace()
    }

    var currentWorkspaceID: UUID { currentWorkspace.id }

    /// Whether there is anywhere to swipe to. Below two, workspaces stay entirely
    /// out of the way: no row in the bar, no dots, no swiping.
    var hasMultipleWorkspaces: Bool { workspaces.count > 1 }

    /// Moves to another board.
    ///
    /// The path is dropped rather than remembered per board. A path is a list of
    /// note ids, and those ids mean nothing in another workspace — carrying one
    /// across would leave the grid pointing at a level that does not exist. Landing
    /// at the top of the board you swiped to is also what the gesture implies.
    func selectWorkspace(at index: Int) {
        guard workspaces.indices.contains(index), index != currentIndex else { return }
        let target = workspaces[index].id

        // Focus goes first, for the same reason as in `drillInto`: the cleanup it
        // triggers has to resolve against the level still on screen.
        editingID = nil
        renamingWorkspaceID = nil

        // Clearing the rename can discard a board that was never named, which moves
        // everything after it — so where we were headed is re-resolved by id rather
        // than trusting the index we came in with.
        guard let destination = workspaces.firstIndex(where: { $0.id == target }),
              destination != currentIndex
        else { return }

        switchDirection = destination > currentIndex ? 1 : -1
        currentIndex = destination
        path = []
        scheduleSave()
    }

    func selectWorkspace(_ id: UUID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        selectWorkspace(at: index)
    }

    /// The ends are hard stops rather than wrapping around, like pages and Spaces:
    /// swiping past the last board should feel like the end of the shelf, not
    /// teleport you back to the first.
    @discardableResult
    func goToNextWorkspace() -> Bool {
        guard currentIndex + 1 < workspaces.count else { return false }
        selectWorkspace(at: currentIndex + 1)
        return true
    }

    @discardableResult
    func goToPreviousWorkspace() -> Bool {
        guard currentIndex > 0 else { return false }
        selectWorkspace(at: currentIndex - 1)
        return true
    }

    /// Adds a board after the current one and opens it, ready to be named — the
    /// exact shape of `addBubble`, which also creates a blank thing and puts the
    /// cursor in it.
    @discardableResult
    func addWorkspace(named name: String = "") -> UUID {
        editingID = nil
        let workspace = Workspace(name: name, notes: [])
        switchDirection = 1
        workspaces.append(workspace)
        currentIndex = workspaces.count - 1
        path = []
        renamingWorkspaceID = workspace.id
        scheduleSave()
        return workspace.id
    }

    /// Sends a note, and everything inside it, to another board.
    ///
    /// It lands at the **top level** of the target: the note is being filed
    /// somewhere else, and a drag has no way to say which bubble inside that board
    /// it belongs in.
    ///
    /// Called while still standing on the board the note is leaving — filing commits
    /// first and the panel swipes to the destination after, so that the note is
    /// already there when the new board arrives. The note is found by id anywhere in
    /// the current tree, exactly like `pop`, so it works from any level.
    ///
    /// Recorded for undo, which restores the level *and* the board it was on:
    /// nothing is destroyed, but a note that has left for another board is just as
    /// hard to find again by hand.
    @discardableResult
    func move(_ id: UUID, toWorkspace target: UUID) -> Bool {
        guard target != currentWorkspaceID,
              let destination = workspaces.firstIndex(where: { $0.id == target }),
              let node = root.node(withID: id),
              let (parentPath, index) = root.location(of: id)
        else { return false }

        recordUndo(
            .file(id, from: NodeLocation(workspace: currentWorkspaceID, parentPath: parentPath, index: index),
                  to: target),
            label: node.displayName
        )
        if editingID == id { editingID = nil }
        currentNotes.removeNode(withID: id)
        workspaces[destination].notes.append(node)
        scheduleSave()
        return true
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        scheduleSave()
    }

    /// Deletes a board and everything on it. Recorded for undo — this destroys more
    /// writing in one action than anything else in the app.
    ///
    /// The last board cannot go: there would be nowhere for the next note to live,
    /// and "no workspaces" is not a state the rest of the app is written to handle.
    func removeWorkspace(_ id: UUID) {
        guard workspaces.count > 1 else { return }
        // Dropping the rename first can itself discard this board, if it was never
        // named or written in — in which case there is nothing left to delete, and
        // nothing that was worth an undo step.
        if renamingWorkspaceID == id { renamingWorkspaceID = nil }
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        // Focus first, while the board it is on is still there to clean up against.
        if index == currentIndex { editingID = nil }
        recordUndo(.removeWorkspace(workspaces[index], index: index), label: workspaces[index].displayName)
        deleteWorkspace(at: index)
    }

    /// Drops a board that was made and then abandoned — no name, no notes — when
    /// the rename field loses focus. The counterpart of `discardIfEmpty`.
    private func discardWorkspaceIfUnused(_ id: UUID) {
        guard workspaces.count > 1,
              let index = workspaces.firstIndex(where: { $0.id == id }),
              workspaces[index].isUnused
        else { return }
        // Deliberately not via `removeWorkspace`: there is nothing to undo about a
        // board that was never named or written in, and recording it would bury a
        // real deletion in the stack.
        deleteWorkspace(at: index)
    }

    /// Takes a board off the shelf and keeps `currentIndex` on the board you were
    /// looking at — or, if that was the one that went, on its neighbour, at the top.
    private func deleteWorkspace(at index: Int) {
        workspaces.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            currentIndex = min(index, workspaces.count - 1)
            path = []
        }
        scheduleSave()
    }

    // MARK: - Navigation

    // Focus is always cleared *before* the path moves: the empty-bubble cleanup that
    // `editingID` triggers resolves against the current level, so it has to run while
    // that level is still the one on screen.

    func drillInto(_ id: UUID) {
        guard visible.contains(where: { $0.id == id }) else { return }
        editingID = nil
        // Clearing focus can discard this very bubble if it was still blank, in which
        // case there is nothing left to drill into.
        guard visible.contains(where: { $0.id == id }) else { return }
        path.append(id)
    }

    func goUp() {
        guard !path.isEmpty else { return }
        editingID = nil
        path.removeLast()
    }

    func goToDepth(_ depth: Int) {
        guard depth >= 0, depth < path.count else { return }
        editingID = nil
        path.removeSubrange(depth...)
    }

    // MARK: - Editing

    // `updateText`, `touch` and `discardIfEmpty` act on the level on screen only —
    // they are only ever called for a tile the grid is showing. `pop` and the
    // filing `move` search the whole tree instead, because a confirmation can be
    // answered after the view has moved on.

    /// Adds an empty bubble at the current level and puts it straight into edit mode.
    @discardableResult
    func addBubble(text: String = "") -> UUID {
        advanceClock()
        let node = BubbleNode(text: text)
        currentNotes.mutateChildren(at: path[...]) { $0.append(node) }
        editingID = node.id
        scheduleSave()
        return node.id
    }

    func updateText(_ text: String, for id: UUID) {
        currentNotes.mutateChildren(at: path[...]) { children in
            guard let index = children.firstIndex(where: { $0.id == id }) else { return }
            children[index].text = text
        }
        scheduleSave()
    }

    /// Pops a bubble — the task is done, so it and anything inside it goes.
    /// Recorded for undo, since this is the one action that destroys writing.
    ///
    /// Searches the whole tree rather than just the current level. A pop can be
    /// confirmed after the user has navigated elsewhere, and tying removal to
    /// `path` made that silently do nothing. It is still the *current workspace's*
    /// tree: a note on another board is not something the grid can be showing.
    /// Returns whether anything was popped, so the burst and the sound can be
    /// withheld from a pop that found nothing to remove.
    @discardableResult
    func pop(_ id: UUID) -> Bool {
        guard let node = root.node(withID: id),
              let (parentPath, index) = root.location(of: id)
        else { return false }
        recordUndo(
            .pop(node, from: NodeLocation(workspace: currentWorkspaceID, parentPath: parentPath, index: index)),
            label: node.displayName
        )
        currentNotes.removeNode(withID: id)
        if editingID == id { editingID = nil }
        // Standing inside the bubble that just went means backing out to its parent.
        if let depth = path.firstIndex(of: id) {
            path.removeSubrange(depth...)
        }
        scheduleSave()
        return true
    }

    /// Replaces the current workspace's tree and returns to the top level. Used for
    /// seeding and for restoring a known state; ordinary editing goes through the
    /// methods above.
    func replaceAll(with nodes: [BubbleNode]) {
        editingID = nil
        path = []
        currentNotes = nodes
        scheduleSave()
    }

    /// Reorders within the current level. Grid position *is* array order, so this is
    /// the only thing a drag-to-rearrange needs to persist.
    func move(_ id: UUID, to destination: Int) {
        currentNotes.mutateChildren(at: path[...]) { children in
            guard let from = children.firstIndex(where: { $0.id == id }) else { return }
            let node = children.remove(at: from)
            children.insert(node, at: min(max(destination, 0), children.count))
        }
        scheduleSave()
    }

    /// Jumbles the current level. Recorded for undo, since it throws away an
    /// arrangement that may have taken some care to build.
    ///
    /// Takes a generator so the tests can be deterministic; callers use the default.
    func shuffle(using generator: inout some RandomNumberGenerator) {
        guard visible.count > 1 else { return }
        recordUndo(.shuffle(workspace: currentWorkspaceID, parentPath: path, order: visible.map(\.id)),
                   label: "shuffle")
        var shuffled = visible.shuffled(using: &generator)
        // A shuffle that changes nothing is a wasted click; nudge it.
        if shuffled.map(\.id) == visible.map(\.id) {
            shuffled.swapAt(0, shuffled.count - 1)
        }
        currentNotes.mutateChildren(at: path[...]) { $0 = shuffled }
        scheduleSave()
    }

    func shuffle() {
        var generator = SystemRandomNumberGenerator()
        shuffle(using: &generator)
    }

    /// Drops an empty bubble that was never typed into, so a stray click leaves no litter.
    func discardIfEmpty(_ id: UUID) {
        guard let node = visible.first(where: { $0.id == id }),
              node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              node.children.isEmpty
        else { return }
        // Deliberately not via `pop`: there is nothing to undo about discarding a
        // note that was never written, and it would bury a real pop in the stack.
        currentNotes.mutateChildren(at: path[...]) { $0.removeAll { $0.id == id } }
        if editingID == id { editingID = nil }
        scheduleSave()
    }

    /// Resets a note's clock back to green without losing what it says.
    func touch(_ id: UUID) {
        currentNotes.mutateChildren(at: path[...]) { children in
            guard let index = children.firstIndex(where: { $0.id == id }) else { return }
            children[index].createdAt = Date()
        }
        advanceClock()
        scheduleSave()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoteBubble", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("bubbles.json")
    }

    /// Reads the file, in whatever shape it is in — a pre-workspace file is lifted
    /// into a single board by `BubbleDocument`, and rewritten in the current shape
    /// on the next save.
    ///
    /// A file that cannot be used is never quietly treated as empty: that is what
    /// used to let the next keystroke save an empty board over it. See `BubbleFile`.
    private func load() {
        switch file.load() {
        case .missing:
            break
        case .loaded(let document):
            adopt(document.normalised)
        case .tooNew(let version):
            canSave = false
            fileNotice = "Your notes were saved by a newer version of Note Bubble (format \(version)). "
                + "They are untouched, but nothing you do here will be saved — update the app to get them back."
        case .unreadable(let setAside?):
            fileNotice = "Your notes file couldn't be read, so it was set aside as "
                + "“\(setAside.lastPathComponent)” in the same folder. Nothing in it has been lost."
        case .unreadable(nil):
            canSave = false
            fileNotice = "Your notes file couldn't be read or moved aside, so it has been left alone — "
                + "nothing you do here will be saved over it."
        }
    }

    private func adopt(_ document: BubbleDocument) {
        workspaces = document.workspaces
        currentIndex = document.workspaces.firstIndex { $0.id == document.currentID } ?? 0
    }

    /// Everything that goes to disk. The path is not in here: where you had drilled
    /// to is a within-session thing, and reopening at the top of the board you left
    /// is what the app has always done.
    private var document: BubbleDocument {
        BubbleDocument(workspaces: workspaces, currentID: currentWorkspaceID)
    }

    /// Coalesces the rapid-fire saves that come from typing into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        guard canSave else { return }
        let snapshot = document
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            write(snapshot)
        }
    }

    /// Forces a synchronous write — used on quit, where the debounce would never fire.
    func saveNow() {
        saveTask?.cancel()
        guard canSave else { return }
        write(document)
    }

    private func write(_ snapshot: BubbleDocument) {
        do {
            try file.save(snapshot, backingUp: !hasSaved)
            hasSaved = true
        } catch {
            BubbleFile.logger.error("Could not save notes: \(error)")
        }
    }
}
