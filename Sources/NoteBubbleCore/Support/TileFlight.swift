import CoreGraphics
import Foundation

/// Where the grid's scrolled content sits, in the two spaces a tile being carried
/// has to be understood in at once.
///
/// They are two different translations and mixing them up is silent: the tile draws
/// somewhere plausible while the dots it is aimed at are somewhere else entirely.
struct GridOffsets: Equatable {
    /// Content → the grid's viewport, which is where the tile is *drawn*.
    let inViewport: CGPoint
    /// Content → the panel, which is where the workspace dots *are*.
    let inPanel: CGPoint
}

/// One workspace dot's catchment, in `PanelSpace` coordinates. Published by the bar
/// as it lays itself out; see `WorkspaceDots`.
struct WorkspaceDropTarget: Equatable {
    let id: UUID
    let frame: CGRect
}

/// A tile in the air: what was picked up, how far it has been carried, and which
/// workspace dot it is over.
///
/// Split out of `BubbleGrid` for the same reason as `TileGesture`, and it is the
/// other half of the same interaction. `TileGesture` decides *what kind* of press
/// this is; `TileFlight` knows *where the tile is* once that press turns out to be
/// a drag. Neither has any SwiftUI in it, so both can be checked without a mouse —
/// which matters here, because every symptom this code has produced (a bubble drawn
/// in the wrong place, a dot that would not light up on a scrolled board, a tile
/// frozen in a corner) looked identical from the outside.
///
/// What it is carrying is copied once, when the tile leaves the ground:
///
/// - The **node**, because the toast that follows names it, and by then it has been
///   moved.
/// - Its **size and slot**, so the copy in the air is drawn exactly as the tile it
///   replaced, wherever the layout underneath has since got to.
/// - The **offsets**, because the grid can be scrolled and the conversion between
///   what the tile knows and what the bar knows must not change halfway through a
///   drag.
struct TileFlight: Equatable {
    /// How far outside a dot still counts. What is being aimed is a whole tile, not
    /// a pointer, so the dots are given a good deal more room than they draw — they
    /// are small even once they have grown for the drag.
    ///
    /// It is deliberately wider than the gap the bar leaves between them, so
    /// neighbours overlap and there is no dead strip between two targets. Where they
    /// overlap the leftmost wins: a predictable boundary beats a hole.
    static let slack = CGSize(width: 8, height: 10)

    /// The tile that was picked up, as it was at that moment.
    struct Cargo: Equatable {
        let node: BubbleNode
        let size: CGSize
        /// Its slot's centre, in the grid's content space.
        let centre: CGPoint
        let offsets: GridOffsets
    }

    private(set) var cargo: Cargo?
    /// How far the tile has been carried from its slot.
    private(set) var translation: CGSize = .zero
    /// The dot it is currently over, if any.
    private(set) var hoveredWorkspace: UUID?

    /// Whether a tile is actually in the air. Until the offsets have been measured
    /// there is nothing to draw and nothing to aim, and the grid falls back to
    /// moving the tile in place — see `BubbleGrid.tile`.
    var isCarrying: Bool { cargo != nil }

    var node: BubbleNode? { cargo?.node }

    // MARK: - The flight

    mutating func lift(_ cargo: Cargo) {
        self.cargo = cargo
        hoveredWorkspace = nil
    }

    /// Carries the tile, and works out which dot it has come to rest over.
    ///
    /// Returns whether that answer *changed*, because the answer is what the bar
    /// draws: writing it every frame would redraw the bar sixty times a second to
    /// say the same thing.
    @discardableResult
    mutating func carry(to translation: CGSize, over targets: [WorkspaceDropTarget]) -> Bool {
        self.translation = translation
        let next = target(among: targets)
        guard next != hoveredWorkspace else { return false }
        hoveredWorkspace = next
        return true
    }

    mutating func land() {
        cargo = nil
        translation = .zero
        hoveredWorkspace = nil
    }

    // MARK: - Where the tile is

    /// In the grid's own content space — what the drop index is measured against.
    var centreInContent: CGPoint? {
        cargo.map { CGPoint(x: $0.centre.x + translation.width, y: $0.centre.y + translation.height) }
    }

    /// In the grid's viewport, which is where the copy in the air is drawn. The
    /// viewport does not scroll, so a tile carried above the grid's top edge lands
    /// on a negative `y` — which is exactly how it reaches the bar.
    var centreInViewport: CGPoint? {
        guard let cargo, let centre = centreInContent else { return nil }
        return CGPoint(
            x: centre.x + cargo.offsets.inViewport.x,
            y: centre.y + cargo.offsets.inViewport.y
        )
    }

    /// In the panel, which is the one space this and the bar's dots share.
    var centreInPanel: CGPoint? {
        guard let cargo, let centre = centreInContent else { return nil }
        return CGPoint(
            x: centre.x + cargo.offsets.inPanel.x,
            y: centre.y + cargo.offsets.inPanel.y
        )
    }

    /// Which dot the tile is over. Nothing is hit until the tile is genuinely in the
    /// air with its offsets measured: a guess would file a note on the wrong board.
    private func target(among targets: [WorkspaceDropTarget]) -> UUID? {
        guard let point = centreInPanel else { return nil }
        return targets.first {
            $0.frame.insetBy(dx: -Self.slack.width, dy: -Self.slack.height).contains(point)
        }?.id
    }
}
