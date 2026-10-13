import Foundation

/// What resting a carried tile on a workspace dot should show, once the dwell
/// (`Motion.workspacePreview`) has elapsed.
///
/// The third of the grid's deciders, beside `TileGesture` (what kind of press) and
/// `TileFlight` (where the tile is). Like them it has no SwiftUI and no clock: the
/// grid runs the dwell and asks here what it means.
enum PreviewDwell {
    enum Outcome: Equatable {
        /// Slide `workspace` into view from the side it lives on: +1 from the
        /// trailing edge (it is further along the shelf), -1 from the leading edge.
        case show(UUID, direction: Int)
        /// Take any preview away again — the tile is over the dot of the board it
        /// came from, which is how a drag is called off without leaving the bar.
        case clear
    }

    /// - Parameters:
    ///   - dot: the dot the dwell started on.
    ///   - stillOver: the dot the tile is over now. If it has moved on, the dwell
    ///     no longer means anything and nil is returned: crossing one dot on the way
    ///     to another must not flick through every board in between.
    ///   - current: the board the store is actually on.
    ///   - boards: every board's id, in shelf order.
    static func outcome(dwelledOn dot: UUID, stillOver: UUID?, current: UUID, boards: [UUID]) -> Outcome? {
        guard stillOver == dot else { return nil }
        guard dot != current else { return .clear }
        guard let target = boards.firstIndex(of: dot),
              let here = boards.firstIndex(of: current)
        else { return .show(dot, direction: 1) }
        return .show(dot, direction: target > here ? 1 : -1)
    }
}
