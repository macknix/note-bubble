import Foundation
@testable import NoteBubbleCore

enum TileGestureTests {
    private static let tile = UUID()
    private static let other = UUID()

    /// A press that has begun but not yet decided what it is.
    private static func pressed(_ id: UUID = tile) -> TileGesture {
        var gesture = TileGesture()
        _ = gesture.handle(.changed(id: id, translation: .zero))
        return gesture
    }

    private static func nudge(_ points: CGFloat) -> CGSize {
        CGSize(width: points, height: 0)
    }

    static func run() {
        beginning()
        tapping()
        holding()
        dragging()
        races()
    }

    private static func beginning() {
        Check.suite("Tile gesture — starting a press") {
            var gesture = TileGesture()
            Check.nil_(gesture.activeID, "nothing is pressed to begin with")

            // `minimumDistance: 0` reports on mouse-down, with no movement at all.
            let effects = gesture.handle(.changed(id: tile, translation: .zero))
            Check.equal(effects, [.beginHold], "the first report starts the pop countdown")
            Check.equal(gesture.activeID, tile, "and claims the tile")
            Check.isFalse(gesture.isDragging, "without being a drag yet")
            Check.isTrue(gesture.isPressed(tile), "the tile knows to draw its swell")
            Check.isFalse(gesture.isPressed(other), "and its neighbours know not to")

            // A second tile pressed mid-press is ignored rather than stealing it.
            var busy = pressed()
            Check.equal(busy.handle(.changed(id: other, translation: nudge(40))), [], "a second tile is ignored")
            Check.equal(busy.activeID, tile, "the first press keeps the gesture")
            Check.equal(busy.handle(.ended(id: other)), [], "and so is its release")
        }
    }

    private static func tapping() {
        Check.suite("Tile gesture — a tap") {
            var gesture = pressed()
            Check.equal(
                gesture.handle(.ended(id: tile)),
                [.cancelHold, .enter, .finish],
                "releasing before either deadline opens the tile"
            )
            Check.nil_(gesture.activeID, "and lets the tile go")

            // Below the slop is still a tap: a mouse always wobbles a little.
            var wobbled = pressed()
            _ = wobbled.handle(.changed(id: tile, translation: nudge(TileGesture.dragSlop - 1)))
            Check.isFalse(wobbled.isDragging, "a wobble under the slop is not a drag")
            Check.equal(
                wobbled.handle(.ended(id: tile)),
                [.cancelHold, .enter, .finish],
                "so it still opens the tile"
            )
        }
    }

    private static func holding() {
        Check.suite("Tile gesture — a hold") {
            var gesture = pressed()
            Check.equal(gesture.handle(.holdElapsed(id: tile)), [.pop], "holding still to the deadline pops")

            // The invariant that took the longest to get right: a hold consumes its
            // own release, or the tile pops *and* opens.
            Check.equal(
                gesture.handle(.ended(id: tile)),
                [.cancelHold, .finish],
                "and the release that follows does not also open it"
            )
            Check.nil_(gesture.activeID, "the press is over")

            // The same guarantee for a pop that came from the context menu while a
            // press happened to be open underneath it.
            var external = pressed()
            external.consume()
            Check.equal(
                external.handle(.ended(id: tile)),
                [.cancelHold, .finish],
                "a pop from elsewhere consumes the press too"
            )
        }
    }

    private static func dragging() {
        Check.suite("Tile gesture — a drag") {
            var gesture = pressed()
            let past = nudge(TileGesture.dragSlop + 1)

            Check.equal(
                gesture.handle(.changed(id: tile, translation: past)),
                [.cancelHold, .beginDrag, .track(past)],
                "moving past the slop lifts the tile and calls off the countdown"
            )
            Check.isTrue(gesture.isDragging, "and it is now a rearrange")
            Check.isTrue(gesture.isDragging(tile), "on the tile that was pressed")
            Check.isFalse(gesture.isDragging(other), "and no other")

            let further = nudge(80)
            Check.equal(
                gesture.handle(.changed(id: tile, translation: further)),
                [.track(further)],
                "later movement only tracks — the lift happens once"
            )

            Check.equal(
                gesture.handle(.ended(id: tile)),
                [.cancelHold, .drop, .finish],
                "releasing a drag commits the new order rather than opening the tile"
            )
            Check.isFalse(gesture.isDragging, "and the drag is over")
        }
    }

    private static func races() {
        Check.suite("Tile gesture — races") {
            // Cancelling the countdown cannot stop a task that has already begun, so
            // a hold started before the drag reports in regardless. It must do
            // nothing: this is a rearrange bursting the tile it was rearranging.
            var dragging = pressed()
            _ = dragging.handle(.changed(id: tile, translation: nudge(TileGesture.dragSlop + 1)))
            Check.equal(dragging.handle(.holdElapsed(id: tile)), [], "a late hold cannot pop a tile being dragged")
            Check.isTrue(dragging.isDragging, "the drag carries on")
            Check.equal(dragging.handle(.ended(id: tile)), [.cancelHold, .drop, .finish], "and still drops")

            // A hold reported for a tile that is no longer the one being pressed.
            var stale = pressed()
            Check.equal(stale.handle(.holdElapsed(id: other)), [], "a hold for another tile is ignored")

            // Twice is not two pops.
            var twice = pressed()
            _ = twice.handle(.holdElapsed(id: tile))
            Check.equal(twice.handle(.holdElapsed(id: tile)), [], "a second deadline does nothing")

            // A popped tile is removed, so its release may never arrive. The view
            // resets rather than waiting for one — otherwise the machine sits
            // holding a tile that has gone and refuses every later press.
            var popped = pressed()
            _ = popped.handle(.holdElapsed(id: tile))
            popped.reset()
            Check.nil_(popped.activeID, "resetting releases the tile")
            Check.equal(popped.handle(.ended(id: tile)), [], "a release that arrives late does nothing")
            Check.equal(
                popped.handle(.changed(id: other, translation: .zero)),
                [.beginHold],
                "and the next tile can be pressed"
            )

            // Events arriving with nothing pressed.
            var idle = TileGesture()
            Check.equal(idle.handle(.ended(id: tile)), [], "a release with no press does nothing")
            Check.equal(idle.handle(.holdElapsed(id: tile)), [], "nor does a stray deadline")
        }

        Check.suite("Tile gesture — a decision taken mid-press") {
            // Filing a tile onto another workspace decides a drag while the button is
            // very often still down. This is the bug that made a bubble freeze on
            // screen: the press was *reset*, the next movement of that same unreleased
            // button read as a brand-new press, and it lifted a second tile out of a
            // board that had already been swiped away — one that never got a release,
            // because the view it belonged to was leaving.
            var filed = pressed()
            _ = filed.handle(.changed(id: tile, translation: nudge(TileGesture.dragSlop + 1)))
            Check.isTrue(filed.isDragging, "a drag is under way")

            filed.consume()
            Check.isFalse(filed.isDragging, "consuming takes it off the screen")
            Check.equal(
                filed.handle(.changed(id: tile, translation: nudge(200))),
                [],
                "and the rest of that press does nothing at all — no second tile is lifted"
            )
            Check.isFalse(filed.isDragging, "however far the button is dragged afterwards")
            Check.equal(
                filed.handle(.ended(id: tile)),
                [.cancelHold, .finish],
                "the release clears it without also dropping or opening anything"
            )
            Check.nil_(filed.activeID, "leaving nothing held")

            // The other half of the bargain: a consumed press must not become a stuck
            // key if its release never arrives, which is the usual case — the tile it
            // belonged to has gone to another board.
            var stranded = pressed()
            stranded.consume()
            Check.equal(
                stranded.handle(.changed(id: other, translation: .zero)),
                [.beginHold],
                "a consumed press yields to the next tile pressed"
            )
            Check.equal(stranded.activeID, other, "which takes the gesture over")
        }
    }
}
