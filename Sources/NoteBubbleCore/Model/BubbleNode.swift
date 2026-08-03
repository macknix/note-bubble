import Foundation

/// A single note. Bubbles nest arbitrarily deep — a bubble's `children` are the
/// sub-tasks you see after drilling into it, which is the whole directory structure.
struct BubbleNode: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var createdAt: Date
    var children: [BubbleNode]

    init(text: String, createdAt: Date = Date(), children: [BubbleNode] = []) {
        self.id = UUID()
        self.text = text
        self.createdAt = createdAt
        self.children = children
    }

    /// What to show wherever a note is named — tiles, breadcrumbs, confirmations,
    /// undo labels. A note can legitimately be blank while it is being written, and
    /// every one of those places needs the same fallback.
    var displayName: String {
        text.isEmpty ? "Untitled" : text
    }

    /// Whole days since the note was written. Drives the traffic-light colour.
    var ageInDays: Double {
        Date().timeIntervalSince(createdAt) / 86_400
    }

    /// Total notes contained below this one, at any depth.
    var descendantCount: Int {
        children.reduce(children.count) { $0 + $1.descendantCount }
    }
}

// MARK: - Tree editing

extension Array where Element == BubbleNode {
    /// Walks `path` and hands the matching child array to `body` for mutation.
    /// An empty path mutates the receiver, so the root level is not a special case.
    mutating func mutateChildren(at path: ArraySlice<UUID>, _ body: (inout [BubbleNode]) -> Void) {
        guard let next = path.first else {
            body(&self)
            return
        }
        guard let index = firstIndex(where: { $0.id == next }) else { return }
        self[index].children.mutateChildren(at: path.dropFirst(), body)
    }

    /// The child array reached by following `path` from the receiver.
    func children(at path: ArraySlice<UUID>) -> [BubbleNode] {
        guard let next = path.first else { return self }
        guard let node = first(where: { $0.id == next }) else { return [] }
        return node.children.children(at: path.dropFirst())
    }

    /// Removes a node from anywhere in the tree, returning whether it was found.
    /// Depth-independent on purpose: popping must not care what level the user
    /// happens to be standing on when it happens.
    @discardableResult
    mutating func removeNode(withID id: UUID) -> Bool {
        if let index = firstIndex(where: { $0.id == id }) {
            remove(at: index)
            return true
        }
        for index in indices where self[index].children.removeNode(withID: id) {
            return true
        }
        return false
    }

    func node(withID id: UUID) -> BubbleNode? {
        for node in self {
            if node.id == id { return node }
            if let found = node.children.node(withID: id) { return found }
        }
        return nil
    }

    /// Every note in the tree, flattened — used for the overdue count on the pill.
    var flattened: [BubbleNode] {
        flatMap { [$0] + $0.children.flattened }
    }
}
