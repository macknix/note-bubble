import CoreGraphics

/// Memoises `GridLayout.spec(for:)`.
///
/// Sizing a tile means laying out its text — twice, when a wide tile has to be
/// re-measured at the wider column — which is far too costly to redo for every
/// tile on every frame of a drag. The result depends only on the label and the
/// column width, so it caches cleanly.
///
/// `GridLayout.spec` itself stays pure and uncached; that is the version the tests
/// exercise. This is the view layer's fast path over it.
@MainActor
enum TileSizeCache {
    private struct Key: Hashable {
        let label: String
        let columnWidth: CGFloat
    }

    private static var memo: [Key: GridLayout.TileSpec] = [:]
    /// Bounded so a long session of edits cannot grow this without limit. Notes are
    /// few and short-lived enough that a wholesale clear beats tracking recency.
    private static let capacity = 400

    static func spec(for node: BubbleNode, in layout: GridLayout) -> GridLayout.TileSpec {
        let key = Key(label: node.displayName, columnWidth: layout.columnWidth)
        if let cached = memo[key] { return cached }

        let spec = layout.spec(for: node)
        if memo.count >= capacity { memo.removeAll(keepingCapacity: true) }
        memo[key] = spec
        return spec
    }
}
