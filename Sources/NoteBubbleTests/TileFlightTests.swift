import CoreGraphics
import Foundation
@testable import NoteBubbleCore

@MainActor
enum TileFlightTests {
    // Two workspace dots as the bar lays them out, in panel coordinates: up in the
    // second row of the bar, towards the right-hand end.
    private static let errands = WorkspaceDropTarget(
        id: UUID(),
        frame: CGRect(x: 340, y: 92, width: 24, height: 20)
    )
    private static let someday = WorkspaceDropTarget(
        id: UUID(),
        frame: CGRect(x: 369, y: 92, width: 24, height: 20)
    )
    private static var dots: [WorkspaceDropTarget] { [errands, someday] }

    /// A tile picked up from the middle of an unscrolled board. The grid's content
    /// starts 130pt down the panel, below the bar — which is the whole reason a tile
    /// has to be carried *up* to reach a dot.
    private static func lifted(
        contentInPanel: CGPoint = CGPoint(x: 0, y: 130),
        contentInViewport: CGPoint = .zero,
        centre: CGPoint = CGPoint(x: 60, y: 100)
    ) -> TileFlight {
        var flight = TileFlight()
        flight.lift(
            TileFlight.Cargo(
                node: BubbleNode(text: "bins"),
                size: CGSize(width: 94, height: 64),
                centre: centre,
                offsets: GridOffsets(inViewport: contentInViewport, inPanel: contentInPanel)
            )
        )
        return flight
    }

    /// What it takes to carry the tile from `centre` onto a dot.
    private static func reach(_ target: WorkspaceDropTarget, from centre: CGPoint,
                              offset: CGPoint) -> CGSize {
        CGSize(
            width: target.frame.midX - offset.x - centre.x,
            height: target.frame.midY - offset.y - centre.y
        )
    }

    static func run() {
        Check.suite("Tile flight — nothing in the air") {
            var idle = TileFlight()
            Check.isFalse(idle.isCarrying, "nothing is being carried to begin with")
            Check.nil_(idle.centreInViewport, "so it is nowhere in particular")
            Check.isFalse(
                idle.carry(to: CGSize(width: 300, height: -300), over: dots),
                "and carrying it over a dot picks nothing up — a guess would file a note on the wrong board"
            )
            Check.nil_(idle.hoveredWorkspace, "leaving nothing hovered")
        }

        Check.suite("Tile flight — reaching a dot") {
            var flight = lifted()
            let centre = CGPoint(x: 60, y: 100)
            let offset = CGPoint(x: 0, y: 130)

            Check.isFalse(
                flight.carry(to: CGSize(width: 10, height: -10), over: dots),
                "a nudge within the grid is over nothing"
            )
            Check.nil_(flight.hoveredWorkspace, "so no dot is lit")

            Check.isTrue(
                flight.carry(to: reach(errands, from: centre, offset: offset), over: dots),
                "carrying it up onto the first dot changes the answer"
            )
            Check.equal(flight.hoveredWorkspace, errands.id, "to that dot")

            Check.isFalse(
                flight.carry(to: reach(errands, from: centre, offset: offset), over: dots),
                "staying on it does not change the answer again — the bar redraws on this"
            )

            Check.isTrue(
                flight.carry(to: reach(someday, from: centre, offset: offset), over: dots),
                "moving to its neighbour does"
            )
            Check.equal(flight.hoveredWorkspace, someday.id, "and picks that one up")
        }

        Check.suite("Tile flight — a scrolled board") {
            // Scrolled 300pt down, the content sits 300pt higher in both spaces. The
            // same dot is now reached from a completely different place in the
            // content — this conversion, done backwards, leaves the dots unreachable
            // on a scrolled board with nothing on screen to say why.
            let offset = CGPoint(x: 0, y: 130 - 300)
            let centre = CGPoint(x: 60, y: 400)
            var flight = lifted(contentInPanel: offset,
                                contentInViewport: CGPoint(x: 0, y: -300),
                                centre: centre)

            Check.isTrue(
                flight.carry(to: reach(errands, from: centre, offset: offset), over: dots),
                "the dot is still reachable once the board has been scrolled"
            )
            Check.equal(flight.hoveredWorkspace, errands.id, "and it is the right one")

            // Drawn where it is aimed: the viewport is what the copy in the air is
            // positioned in, and a tile up at the bar is above the grid's top edge.
            Check.isTrue(flight.centreInViewport!.y < 0, "and it is drawn above the grid, over the bar")
        }

        Check.suite("Tile flight — the slack around a dot") {
            let centre = CGPoint(x: 60, y: 100)
            let offset = CGPoint(x: 0, y: 130)
            let onTarget = reach(errands, from: centre, offset: offset)

            // A dot is small even once it has grown for the drag, and what is being
            // aimed is a whole tile — so the catchment is bigger than the target.
            var near = lifted()
            _ = near.carry(
                to: CGSize(width: onTarget.width - 17, height: onTarget.height - 14),
                over: dots
            )
            Check.equal(near.hoveredWorkspace, errands.id, "a near miss above and left still counts")

            var far = lifted()
            _ = far.carry(to: CGSize(width: onTarget.width, height: onTarget.height - 45), over: dots)
            Check.nil_(far.hoveredWorkspace, "a long way above it does not")

            // The slack is wider than the gap the bar leaves between dots, so
            // neighbours overlap and there is no dead strip to drop into. Where they
            // overlap the first wins, which makes the boundary predictable rather
            // than making it a hole.
            var between = lifted()
            let gap = (errands.frame.maxX + someday.frame.minX) / 2
            _ = between.carry(
                to: CGSize(width: gap - offset.x - centre.x, height: onTarget.height),
                over: dots
            )
            Check.equal(between.hoveredWorkspace, errands.id,
                        "the gap between two dots belongs to the one on the left, not to neither")
        }

        Check.suite("Tile flight — landing") {
            var flight = lifted()
            _ = flight.carry(to: reach(errands, from: CGPoint(x: 60, y: 100), offset: CGPoint(x: 0, y: 130)),
                             over: dots)
            Check.equal(flight.hoveredWorkspace, errands.id, "in the air over a dot")

            flight.land()
            Check.isFalse(flight.isCarrying, "landing puts the tile down")
            Check.nil_(flight.hoveredWorkspace, "and forgets what it was over")
            Check.nil_(flight.centreInViewport, "with nothing left to draw")
            Check.equal(flight.translation, .zero, "and nothing left to carry")
        }

        Check.suite("Tile flight — with one workspace there is nowhere to drop") {
            var flight = lifted()
            Check.isFalse(
                flight.carry(to: CGSize(width: 300, height: -300), over: []),
                "no dots, no destination"
            )
            Check.nil_(flight.hoveredWorkspace, "however far the tile is carried")
        }
    }
}
