import Foundation

/// A named board of notes. Every bubble belongs to exactly one, and the grid only
/// ever shows one at a time — switching is a swipe, not a filter.
///
/// Workspaces are deliberately *not* another level of the bubble tree. Nesting is
/// for tasks that belong to a task; a workspace is a separate context you move
/// between wholesale, so it has no age, no colour, and never appears as a tile.
struct Workspace: Identifiable, Codable, Hashable {
    /// What the single workspace is called when there has never been another one —
    /// including the one an upgrade from a pre-workspace file lands in.
    static let defaultName = "Notes"

    var id: UUID
    var name: String
    var notes: [BubbleNode]

    init(id: UUID = UUID(), name: String = Workspace.defaultName, notes: [BubbleNode] = []) {
        self.id = id
        self.name = name
        self.notes = notes
    }

    /// Same contract as `BubbleNode.displayName`: a workspace can legitimately be
    /// nameless while it is being named, and everywhere that shows it needs the
    /// same fallback.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Nothing written in it and nothing called — a workspace made by a stray click.
    var isUnused: Bool {
        notes.isEmpty && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var overdueCount: Int {
        notes.flattened.filter { Aging.stage(forDays: $0.ageInDays) == .overdue }.count
    }

    /// The worst state anything in this workspace has reached, or nil when it is
    /// empty. This is what colours its dot in the bar: a board gone red while you
    /// are looking at another one is exactly what the traffic lights exist to say.
    var worstStage: Aging.Stage? {
        var worst: Aging.Stage?
        for note in notes.flattened {
            let stage = Aging.stage(forDays: note.ageInDays)
            switch stage {
            case .overdue: return .overdue
            case .aging: worst = .aging
            case .fresh: if worst == nil { worst = .fresh }
            }
        }
        return worst
    }
}

/// What `bubbles.json` holds.
///
/// The file used to be a bare array of notes. It is read back through
/// `init(from:)` below, which recognises that shape and lifts it into a single
/// workspace — so an existing board survives the upgrade untouched and lands
/// under `Workspace.defaultName`. The next save writes the current shape.
struct BubbleDocument: Codable {
    /// 1 was the bare array; 2 added workspaces. Nothing *reads* this — each shape
    /// is recognised structurally — but a file that says what it is costs nothing
    /// and makes the next migration easier to reason about.
    static let currentVersion = 2

    var version: Int
    var workspaces: [Workspace]
    /// Which workspace was on screen. Stored by id rather than index so reordering
    /// or removing one elsewhere cannot silently change which board opens.
    var currentID: UUID?

    init(workspaces: [Workspace], currentID: UUID?) {
        self.version = Self.currentVersion
        self.workspaces = workspaces
        self.currentID = currentID
    }

    init(from decoder: Decoder) throws {
        // Version 1: the whole file was `[BubbleNode]`. Nothing else decodes as a
        // top-level array, so this is unambiguous.
        if let notes = try? [BubbleNode](from: decoder) {
            self.init(workspaces: [Workspace(notes: notes)], currentID: nil)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workspaces: try container.decode([Workspace].self, forKey: .workspaces),
            currentID: try? container.decode(UUID.self, forKey: .currentID)
        )
        version = (try? container.decode(Int.self, forKey: .version)) ?? Self.currentVersion
    }

    /// The store's invariant, applied once on the way in: there is always at least
    /// one workspace, and the current one always exists. Every other method can
    /// then assume both rather than re-checking.
    var normalised: BubbleDocument {
        var copy = self
        if copy.workspaces.isEmpty { copy.workspaces = [Workspace()] }
        if copy.currentID == nil || !copy.workspaces.contains(where: { $0.id == copy.currentID }) {
            copy.currentID = copy.workspaces[0].id
        }
        return copy
    }
}
