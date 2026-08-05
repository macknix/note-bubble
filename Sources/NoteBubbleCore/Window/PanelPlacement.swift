import CoreGraphics
import Foundation

/// Which corner of the panel holds still when it changes size.
///
/// The pill and the expanded grid are wildly different sizes, so *something* has
/// to stay put across the transition. Anchoring the corner nearest the screen
/// edge is what makes a widget parked top-right expand leftwards and downwards,
/// into the screen, rather than sliding off it.
///
/// Coordinates are AppKit's: y grows upwards, so `.top` pins `maxY`.
struct PanelAnchor: Equatable, Codable {
    enum Horizontal: String, Codable { case left, right }
    enum Vertical: String, Codable { case top, bottom }

    var horizontal: Horizontal
    var vertical: Vertical

    /// Where the widget starts life, matching `defaultOrigin`.
    static let topRight = PanelAnchor(horizontal: .right, vertical: .top)

    /// The fixed point: the corner every resize is measured from.
    func corner(of frame: CGRect) -> CGPoint {
        CGPoint(
            x: horizontal == .left ? frame.minX : frame.maxX,
            y: vertical == .bottom ? frame.minY : frame.maxY
        )
    }

    /// The inverse: rebuild a frame of `size` hanging off that corner.
    func frame(size: CGSize, at corner: CGPoint) -> CGRect {
        CGRect(
            x: horizontal == .left ? corner.x : corner.x - size.width,
            y: vertical == .bottom ? corner.y : corner.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Which corner a frame is sitting in, by whichever edge it is nearer.
    ///
    /// Compares *gaps* rather than the frame's centre against the screen's, so the
    /// answer doesn't depend on how wide the panel currently happens to be — an
    /// expanded panel flush to the right edge must still read as right-anchored.
    static func resolve(for frame: CGRect, in visible: CGRect) -> PanelAnchor {
        PanelAnchor(
            horizontal: (visible.maxX - frame.maxX) < (frame.minX - visible.minX) ? .right : .left,
            vertical: (frame.minY - visible.minY) < (visible.maxY - frame.maxY) ? .bottom : .top
        )
    }
}

/// Where the panel is parked: the corner the **pill** rests on, and which corner
/// that is. Everything else is derived from it.
///
/// A corner rather than a plain origin because an origin can't survive a resize —
/// the app quits expanded and reopens as a pill, and only the anchored corner means
/// the same thing in both. It is deliberately the *pill's* corner: the pill is the
/// resting state, so it is the thing that must never appear to move.
struct PanelPlacement: Equatable, Codable {
    var corner: CGPoint
    var anchor: PanelAnchor

    init(corner: CGPoint, anchor: PanelAnchor) {
        self.corner = corner
        self.anchor = anchor
    }

    /// Parking the pill where it was dropped: nearest corner wins on both axes.
    init(pill frame: CGRect, in visible: CGRect) {
        let anchor = PanelAnchor.resolve(for: frame, in: visible)
        self.init(corner: anchor.corner(of: frame), anchor: anchor)
    }

    /// Parking the *expanded* panel, which is dragged by its bar.
    ///
    /// Vertically this is always the top, whatever half of the screen it lands in.
    /// The bar is the handle, and the panel folds up towards it: resolving `.bottom`
    /// here instead put the pill on the panel's bottom edge — as much as 600pt below
    /// the bar the user was holding a moment earlier. In the top half of the screen
    /// the bug was invisible, because there the nearest corner *is* the top one.
    ///
    /// Horizontally the nearest edge still wins, which is what makes a panel dragged
    /// to the right of the screen fold rightwards and open leftwards again.
    init(draggedPanel frame: CGRect, in visible: CGRect) {
        let anchor = PanelAnchor(
            horizontal: PanelAnchor.resolve(for: frame, in: visible).horizontal,
            vertical: .top
        )
        self.init(corner: anchor.corner(of: frame), anchor: anchor)
    }
}

/// Pure window geometry: which edges may snap, snapping to them, and clamping.
///
/// No AppKit and no windows, so the awkward cases — a panel wider than its
/// screen, a corner on a display that has since been unplugged — are testable
/// without one.
enum PanelGeometry {
    /// How close an edge has to come before it sticks. Generous enough to catch a
    /// flick towards the edge, small enough that you can still park deliberately
    /// just shy of one.
    static let snapDistance: CGFloat = 28

    /// Screen edges a panel is allowed to stick to.
    ///
    /// Not always all four: an edge shared with another display must stay open, or
    /// the panel cements itself to the boundary and can never be dragged across.
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1 << 0)
        static let right = Edges(rawValue: 1 << 1)
        static let top = Edges(rawValue: 1 << 2)
        static let bottom = Edges(rawValue: 1 << 3)
        static let all: Edges = [.left, .right, .top, .bottom]
    }

    /// Pulls a frame flush to any screen edge it is within `distance` of.
    ///
    /// The axes are decided independently, which is what makes corners fall out for
    /// free: approach a corner and both edges catch.
    static func snapped(
        _ frame: CGRect,
        in visible: CGRect,
        edges: Edges = .all,
        distance: CGFloat = snapDistance
    ) -> CGRect {
        var frame = frame

        if edges.contains(.left), abs(frame.minX - visible.minX) <= distance {
            frame.origin.x = visible.minX
        } else if edges.contains(.right), abs(frame.maxX - visible.maxX) <= distance {
            frame.origin.x = visible.maxX - frame.width
        }

        if edges.contains(.top), abs(frame.maxY - visible.maxY) <= distance {
            frame.origin.y = visible.maxY - frame.height
        } else if edges.contains(.bottom), abs(frame.minY - visible.minY) <= distance {
            frame.origin.y = visible.minY
        }

        return frame
    }

    /// The edges of `screen` with nothing beyond them.
    ///
    /// An edge shared with another display must not snap: the panel would cement
    /// itself to the boundary and could never be dragged onto the next screen.
    /// Probed at three points along each edge, since displays are rarely aligned
    /// neatly enough for the midpoint alone to find a neighbour.
    static func openEdges(of screen: CGRect, among others: [CGRect]) -> Edges {
        guard !others.isEmpty else { return .all }

        let fractions: [CGFloat] = [0.25, 0.5, 0.75]
        let sides: [(Edges, (CGFloat) -> CGPoint)] = [
            (.left, { CGPoint(x: screen.minX - 2, y: screen.minY + screen.height * $0) }),
            (.right, { CGPoint(x: screen.maxX + 2, y: screen.minY + screen.height * $0) }),
            (.top, { CGPoint(x: screen.minX + screen.width * $0, y: screen.maxY + 2) }),
            (.bottom, { CGPoint(x: screen.minX + screen.width * $0, y: screen.minY - 2) })
        ]

        var edges: Edges = []
        for (edge, probe) in sides {
            let neighboured = fractions.contains { fraction in
                others.contains { $0.contains(probe(fraction)) }
            }
            if !neighboured { edges.insert(edge) }
        }
        return edges
    }

    /// Keeps a frame inside the screen. A frame too big for the screen is pinned to
    /// the top-left corner rather than being pushed off the opposite edge.
    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
        return frame
    }

}
