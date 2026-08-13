import CoreGraphics
import Foundation

/// Everything positional for one render of the grid: how big each tile is, where it
/// rests undisturbed, and where it sits under the drag currently in progress.
///
/// It is built **once per render** and passed down. Positions stopped being
/// derivable from an index alone when packing became masonry, and deriving them per
/// tile instead made a drag O(n²) per frame — every tile asking for the hypothetical
/// order that every other tile had just asked for.
struct LayoutPlan {
    let specs: [GridLayout.TileSpec]
    /// Frames in the model's own order — the drag anchor, and what drop targets are
    /// measured against.
    let restingFrames: [CGRect]
    /// Centres under the live reflow, keyed by note. Empty when nothing is being
    /// dragged, in which case the resting frame is the answer.
    let reflowedCentres: [UUID: CGPoint]
    let contentHeight: CGFloat

    /// - Parameters:
    ///   - dragged: the note being rearranged, if any.
    ///   - dropIndex: where it would land. Nil while it is being carried somewhere
    ///     that is not a slot on this board — over a workspace dot, say — which is
    ///     what sends the other tiles back to their resting places.
    /// `@MainActor` because measuring a tile goes through `TileSizeCache`, which is.
    /// The plan is only ever built while rendering, which is main-actor work anyway.
    @MainActor
    init(
        nodes: [BubbleNode],
        layout: GridLayout,
        dragged: UUID? = nil,
        dropIndex: Int? = nil
    ) {
        // Sizing a tile lays out its text, so it must happen once per tile per
        // render and never inline in an `.animation(value:)`.
        specs = nodes.map { TileSizeCache.spec(for: $0, in: layout) }
        restingFrames = layout.frames(for: specs)
        contentHeight = layout.contentHeight(for: specs)

        guard let dragged, let dropIndex else {
            reflowedCentres = [:]
            return
        }

        // The model is untouched until the drag ends: this is only what the board
        // *would* look like if the tile were let go here.
        let ids = nodes.map(\.id)
        let order = ids.reordered(moving: dragged, to: dropIndex)
        let specByID = Dictionary(uniqueKeysWithValues: zip(ids, specs))
        let frames = layout.frames(for: order.compactMap { specByID[$0] })

        var centres: [UUID: CGPoint] = [:]
        for (position, id) in order.enumerated() where position < frames.count {
            centres[id] = CGPoint(x: frames[position].midX, y: frames[position].midY)
        }
        reflowedCentres = centres
    }

    func restingCentre(at index: Int) -> CGPoint {
        let frame = restingFrames[index]
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    func centre(of id: UUID, at index: Int) -> CGPoint {
        reflowedCentres[id] ?? restingCentre(at: index)
    }

    func size(at index: Int) -> CGSize {
        specs[index].size
    }
}
