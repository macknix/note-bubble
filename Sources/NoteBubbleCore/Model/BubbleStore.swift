import Foundation
import Combine

/// Owns the note tree, the drill-in path, and persistence.
///
/// Everything the UI edits goes through here so there is exactly one place that
/// knows how to walk the tree and one place that writes to disk.
@MainActor
final class BubbleStore: ObservableObject {
    /// Top-level bubbles.
    @Published private(set) var root: [BubbleNode] = []
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

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    // MARK: - Undo

    /// A whole-tree snapshot plus where the user was standing when it was taken.
    /// Snapshots rather than inverse operations: the tree is small, popping is the
    /// only destructive action, and restoring a snapshot cannot drift out of sync
    /// with the model the way a hand-written inverse can.
    private struct Snapshot {
        let root: [BubbleNode]
        let path: [UUID]
        let label: String
    }

    private var undoStack: [Snapshot] = []
    private static let undoLimit = 30

    /// Describes what ⌘Z would put back, for the toast and the menu hint.
    @Published private(set) var undoLabel: String?

    var canUndo: Bool { !undoStack.isEmpty }

    private func recordUndo(_ label: String) {
        undoStack.append(Snapshot(root: root, path: path, label: label))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        undoLabel = label
    }

    /// Restores the last snapshot, returning to the level it was taken at so an
    /// undone pop reappears where the user can see it.
    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        editingID = nil
        // Root and path are restored together, so the path is valid by construction.
        root = snapshot.root
        path = snapshot.path
        undoLabel = undoStack.last?.label
        scheduleSave()
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
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

    /// Notes anywhere in the tree that have gone red.
    var overdueCount: Int { stageCounts.overdue }

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
        root.mutateChildren(at: path[...]) { $0.append(node) }
        editingID = node.id
        scheduleSave()
        return node.id
    }

    func updateText(_ text: String, for id: UUID) {
        root.mutateChildren(at: path[...]) { children in
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
    /// `path` made that silently do nothing.
    func pop(_ id: UUID) {
        guard let node = root.node(withID: id) else { return }
        recordUndo(node.displayName)
        root.removeNode(withID: id)
        if editingID == id { editingID = nil }
        // Standing inside the bubble that just went means backing out to its parent.
        if let depth = path.firstIndex(of: id) {
            path.removeSubrange(depth...)
        }
        scheduleSave()
    }

    /// Replaces the entire tree and returns to the top level. Used for seeding and
    /// for restoring a known state; ordinary editing goes through the methods above.
    func replaceAll(with nodes: [BubbleNode]) {
        editingID = nil
        path = []
        root = nodes
        scheduleSave()
    }

    /// Reorders within the current level. Grid position *is* array order, so this is
    /// the only thing a drag-to-rearrange needs to persist.
    func move(_ id: UUID, to destination: Int) {
        root.mutateChildren(at: path[...]) { children in
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
        root.mutateChildren(at: path[...]) { $0 = shuffled }
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
        root.mutateChildren(at: path[...]) { $0.removeAll { $0.id == id } }
        if editingID == id { editingID = nil }
        scheduleSave()
    }

    /// Resets a note's clock back to green without losing what it says.
    func touch(_ id: UUID) {
        root.mutateChildren(at: path[...]) { children in
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        root = (try? decoder.decode([BubbleNode].self, from: data)) ?? []
    }

    /// Coalesces the rapid-fire saves that come from typing into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = root
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
        guard let data = try? encoder.encode(root) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
