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
    @Published private(set) var workspaces: [Workspace]
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

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    // MARK: - Undo

    /// A snapshot of every board plus where the user was standing when it was taken.
    /// Snapshots rather than inverse operations: the tree is small, destroying
    /// writing is rare, and restoring a snapshot cannot drift out of sync with the
    /// model the way a hand-written inverse can.
    ///
    /// It holds *all* the workspaces, not just the current one, because deleting a
    /// whole board is undoable and there would otherwise be nowhere to put it back.
    private struct Snapshot {
        let workspaces: [Workspace]
        let currentIndex: Int
        let path: [UUID]
        let label: String
    }

    private var undoStack: [Snapshot] = []
    private static let undoLimit = 30

    /// Describes what ⌘Z would put back, for the toast and the menu hint.
    @Published private(set) var undoLabel: String?

    var canUndo: Bool { !undoStack.isEmpty }

    private func recordUndo(_ label: String) {
        undoStack.append(
            Snapshot(workspaces: workspaces, currentIndex: currentIndex, path: path, label: label)
        )
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        undoLabel = label
    }

    /// Restores the last snapshot, returning to the board and the level it was taken
    /// at so an undone pop reappears where the user can see it.
    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        editingID = nil
        renamingWorkspaceID = nil
        // Boards, index and path are restored together, so both are valid by
        // construction — there is no moment at which the path points into a board
        // that isn't there.
        workspaces = snapshot.workspaces
        currentIndex = snapshot.currentIndex
        path = snapshot.path
        undoLabel = undoStack.last?.label
        scheduleSave()
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
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

    /// How the whole tree is distributed across the traffic lights. Drives the
    /// status handle in the top bar, which is the only place all three are shown.
    var stageCounts: (fresh: Int, aging: Int, overdue: Int) {
        var counts = (fresh: 0, aging: 0, overdue: 0)
        for note in root.flattened {
            switch Aging.stage(forDays: note.ageInDays) {
            case .fresh: counts.fresh += 1
            case .aging: counts.aging += 1
            case .overdue: counts.overdue += 1
            }
        }
        return counts
    }

    /// Notes anywhere in the tree that have gone red. Scoped to the board on screen,
    /// like every other count in the bar — a number that includes boards you can't
    /// see is a number you can't act on. What another board is up to is said by the
    /// colour of its dot instead.
    var overdueCount: Int { stageCounts.overdue }

    // MARK: - Workspaces

    /// The board on screen. Safe to force because `workspaces` is never empty and
    /// `currentIndex` is clamped by every method that can move it.
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
              let node = root.node(withID: id)
        else { return false }

        recordUndo(node.displayName)
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

        recordUndo(workspaces[index].displayName)
        workspaces.remove(at: index)

        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            editingID = nil
            currentIndex = min(index, workspaces.count - 1)
            path = []
        }
        scheduleSave()
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

    /// Adds an empty bubble at the current level and puts it straight into edit mode.
    @discardableResult
    func addBubble(text: String = "") -> UUID {
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
    func pop(_ id: UUID) {
        guard let node = root.node(withID: id) else { return }
        recordUndo(node.displayName)
        currentNotes.removeNode(withID: id)
        if editingID == id { editingID = nil }
        // Standing inside the bubble that just went means backing out to its parent.
        if let depth = path.firstIndex(of: id) {
            path.removeSubrange(depth...)
        }
        scheduleSave()
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
        recordUndo("shuffle")
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
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(BubbleDocument.self, from: data) else { return }
        adopt(document.normalised)
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
        let snapshot = document
        saveTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Forces a synchronous write — used on quit, where the debounce would never fire.
    func saveNow() {
        saveTask?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(document) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
