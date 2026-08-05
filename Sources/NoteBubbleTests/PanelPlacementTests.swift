import Foundation
@testable import NoteBubbleCore

enum PanelPlacementTests {
    /// A 1440×900 display with the menu bar taken off the top, in AppKit's y-up
    /// coordinates: the origin is the bottom-left.
    private static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private static let pill = CGSize(width: 178, height: 46)
    private static let expanded = CGSize(width: 432, height: 400)

    static func run() {
        anchoring()
        snapping()
        resizing()
        placements()
    }

    private static func anchoring() {
        Check.suite("Panel anchoring") {
            let topRight = CGRect(x: 1262, y: 829, width: 178, height: 46)
            Check.equal(PanelAnchor.resolve(for: topRight, in: screen), .topRight, "top-right corner reads as top-right")

            let bottomLeft = CGRect(x: 0, y: 0, width: 178, height: 46)
            Check.equal(
                PanelAnchor.resolve(for: bottomLeft, in: screen),
                PanelAnchor(horizontal: .left, vertical: .bottom),
                "bottom-left corner reads as bottom-left"
            )

            // The gap-based rule must not care how wide the panel is: an expanded
            // panel flush right still reads right, even though its centre has moved
            // a long way towards the middle of the screen.
            let wideRight = CGRect(x: 1008, y: 475, width: 432, height: 400)
            Check.equal(
                PanelAnchor.resolve(for: wideRight, in: screen).horizontal,
                .right,
                "a wide panel flush right is still right-anchored"
            )

            // Round trip: corner and frame are inverses of each other.
            for anchor in [
                PanelAnchor(horizontal: .left, vertical: .top),
                PanelAnchor(horizontal: .left, vertical: .bottom),
                PanelAnchor(horizontal: .right, vertical: .top),
                PanelAnchor(horizontal: .right, vertical: .bottom)
            ] {
                let frame = CGRect(x: 300, y: 200, width: 178, height: 46)
                Check.equal(
                    anchor.frame(size: frame.size, at: anchor.corner(of: frame)),
                    frame,
                    "\(anchor.horizontal)/\(anchor.vertical) corner round-trips"
                )
            }
        }
    }

    private static func snapping() {
        Check.suite("Panel snapping") {
            let near = CGRect(x: 12, y: 838, width: 178, height: 46) // 12pt off left, 9pt off top
            let snapped = PanelGeometry.snapped(near, in: screen)
            Check.close(snapped.minX, screen.minX, "a near miss snaps flush left")
            Check.close(snapped.maxY, screen.maxY, "and flush to the top, in the same move")

            let right = CGRect(x: 1252, y: 400, width: 178, height: 46) // 10pt off right
            Check.close(
                PanelGeometry.snapped(right, in: screen).maxX,
                screen.maxX,
                "a near miss on the right snaps to the right edge"
            )

            let free = CGRect(x: 600, y: 400, width: 178, height: 46)
            Check.equal(PanelGeometry.snapped(free, in: screen), free, "the middle of the screen is left alone")

            let justOutside = CGRect(x: 40, y: 400, width: 178, height: 46)
            Check.equal(
                PanelGeometry.snapped(justOutside, in: screen),
                justOutside,
                "past the snap distance nothing sticks"
            )

            // The edge a second display sits behind must stay open, or the panel
            // cements itself to the boundary and can never be dragged across.
            let shared = PanelGeometry.snapped(right, in: screen, edges: [.left, .top, .bottom])
            Check.equal(shared, right, "a shared edge does not snap")

            // Which edges those are, given the displays actually attached.
            let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
            Check.equal(PanelGeometry.openEdges(of: laptop, among: []), .all, "one display: every edge snaps")

            let toTheRight = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
            let withNeighbour = PanelGeometry.openEdges(of: laptop, among: [toTheRight])
            Check.isFalse(withNeighbour.contains(.right), "the edge a second display sits behind stays open")
            Check.isTrue(withNeighbour.contains(.left), "the far edge still snaps")
            Check.isTrue(withNeighbour.contains(.top) && withNeighbour.contains(.bottom), "as do top and bottom")

            // Displays are rarely aligned neatly, so a neighbour overlapping only
            // part of the edge still has to count.
            let offset = CGRect(x: 1512, y: 700, width: 2560, height: 1440)
            Check.isFalse(
                PanelGeometry.openEdges(of: laptop, among: [offset]).contains(.right),
                "a partly-overlapping neighbour counts too"
            )

            // A display that touches no edge changes nothing.
            let far = CGRect(x: 4000, y: 0, width: 1000, height: 1000)
            Check.equal(PanelGeometry.openEdges(of: laptop, among: [far]), .all, "a distant display leaves all edges snapping")
        }
    }

    /// Every size the panel takes hangs off the parked corner — the same way
    /// `PanelController.resize(to:)` derives it.
    private static func frame(_ size: CGSize, of placement: PanelPlacement) -> CGRect {
        placement.anchor.frame(size: size, at: placement.corner)
    }

    private static func resizing() {
        Check.suite("Panel resizing") {
            // The user's ask: parked top-right, expanding must grow left and down,
            // and minimising must fold back into the same corner.
            let pillFrame = CGRect(origin: CGPoint(x: 1262, y: 829), size: pill)
            let parked = PanelPlacement(pill: pillFrame, in: screen)

            let grown = frame(expanded, of: parked)
            Check.close(grown.maxX, pillFrame.maxX, "expanding right-anchored keeps the right edge")
            Check.close(grown.maxY, pillFrame.maxY, "and the top edge")
            Check.isTrue(grown.minX < pillFrame.minX, "so it opens leftwards, into the screen")
            Check.isTrue(grown.minY < pillFrame.minY, "and downwards")
            Check.equal(PanelGeometry.clamped(grown, in: screen), grown, "and stays on screen unclamped")

            Check.equal(frame(pill, of: parked), pillFrame, "minimising returns the pill to exactly where it was")

            // Mirror image on the left: bottom-left opens up and to the right.
            let leftPill = CGRect(origin: .zero, size: pill)
            let bottomLeft = PanelPlacement(pill: leftPill, in: screen)
            let leftGrown = frame(expanded, of: bottomLeft)
            Check.close(leftGrown.minX, 0, "expanding left-anchored keeps the left edge")
            Check.close(leftGrown.minY, 0, "bottom-anchored keeps the bottom edge")
            Check.equal(frame(pill, of: bottomLeft), leftPill, "and folds back to the bottom-left")

            // The regression: a panel too tall for the room below it is clamped on
            // screen, and the pill must still come back to its corner rather than
            // creeping down a little further on every cycle.
            let low = PanelPlacement(pill: CGRect(x: 40, y: 300, width: pill.width, height: pill.height), in: screen)
            Check.equal(low.anchor.vertical, .bottom, "a pill low on the screen is bottom-anchored")
            let tall = CGSize(width: 432, height: 700)
            let clamped = PanelGeometry.clamped(frame(tall, of: low), in: screen)
            Check.close(clamped.minY, 175, "a panel taller than the space above it is pushed down to fit")
            Check.equal(frame(pill, of: low).minY, 300, "and the pill still folds back to 300, not to the clamped edge")
        }
    }

    private static func placements() {
        Check.suite("Panel placement") {
            let pillFrame = CGRect(x: 1262, y: 829, width: 178, height: 46)
            let placement = PanelPlacement(pill: pillFrame, in: screen)
            Check.equal(placement.anchor, .topRight, "a placement reads its own anchor")
            Check.equal(placement.corner, CGPoint(x: 1440, y: 875), "and records the anchored corner")

            // What restoring across a launch actually does: the pill comes back on
            // the same corner, whatever size the app was quit at.
            let restored = placement.anchor.frame(size: pillFrame.size, at: placement.corner)
            Check.equal(restored, pillFrame, "restoring puts the pill back where it was")

            // Dragging the expanded panel parks it by the bar, which is its top
            // edge — in the bottom half of the screen, anchoring to the nearest
            // corner instead dropped the pill hundreds of points below the bar the
            // user was holding.
            let low = CGRect(x: 900, y: 40, width: 432, height: 500)
            let dragged = PanelPlacement(draggedPanel: low, in: screen)
            Check.equal(dragged.anchor.vertical, .top, "a dragged panel parks by its top edge, low or high")
            Check.equal(dragged.anchor.horizontal, .right, "and by whichever side it is nearer")
            Check.equal(dragged.corner, CGPoint(x: 1332, y: 540), "so the pill lands on the bar's right end")
            Check.close(
                dragged.anchor.frame(size: CGSize(width: 132, height: 46), at: dragged.corner).maxY,
                low.maxY,
                "the pill's top edge is the panel's top edge — the bar does not move"
            )

            let high = CGRect(x: 900, y: 400, width: 432, height: 500)
            Check.equal(
                PanelPlacement(draggedPanel: high, in: screen).anchor,
                PanelPlacement(pill: CGRect(x: 1200, y: 854, width: 132, height: 46), in: screen).anchor,
                "high up, that agrees with the nearest corner — which is why the bug only showed at the bottom"
            )

            let data = try? JSONEncoder().encode(placement)
            let decoded = data.flatMap { try? JSONDecoder().decode(PanelPlacement.self, from: $0) }
            Check.equal(decoded, placement, "placements survive a round trip through defaults")

            // Clamping is a last resort, not the usual path: only a frame that would
            // hang off the screen moves.
            let offscreen = CGRect(x: 1400, y: -20, width: 432, height: 400)
            let clamped = PanelGeometry.clamped(offscreen, in: screen)
            Check.close(clamped.maxX, screen.maxX, "an overhanging panel is pulled back on screen")
            Check.close(clamped.minY, screen.minY, "from the bottom too")

            let tall = CGRect(x: 100, y: -200, width: 432, height: 1200)
            let clampedTall = PanelGeometry.clamped(tall, in: screen)
            Check.close(clampedTall.minY, screen.minY, "a panel taller than the screen pins to the bottom")
        }
    }
}
