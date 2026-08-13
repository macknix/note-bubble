import CoreGraphics
import Foundation
@testable import NoteBubbleCore

@MainActor
enum WorkspaceSwipeTests {
    /// A trackpad reports a swipe as a stream of small deltas, not one big one, so
    /// the tests feed them the same way.
    private static func swipe(
        _ machine: inout WorkspaceSwipe,
        dx: CGFloat,
        dy: CGFloat = 0,
        steps: Int = 6,
        from time: TimeInterval = 100,
        inverted: Bool = true
    ) -> WorkspaceSwipe.Decision {
        var decision = WorkspaceSwipe.Decision.none
        for step in 0..<steps {
            let result = machine.handle(
                WorkspaceSwipe.Scroll(
                    deltaX: dx / CGFloat(steps),
                    deltaY: dy / CGFloat(steps),
                    isGestureStart: step == 0,
                    isInverted: inverted,
                    time: time + Double(step) * 0.01
                )
            )
            if decision == .none { decision = result }
        }
        return decision
    }

    static func run() {
        Check.suite("WorkspaceSwipe — direction") {
            var machine = WorkspaceSwipe()
            // Natural scrolling: the deltas already follow the fingers.
            Check.equal(swipe(&machine, dx: -90), .next, "fingers left goes to the next board")
            Check.equal(swipe(&machine, dx: 90, from: 200), .previous, "fingers right goes back")

            // Natural scrolling off flips the sign of the deltas but not the meaning
            // of the gesture: a swipe follows the fingers either way.
            var classic = WorkspaceSwipe()
            Check.equal(swipe(&classic, dx: 90, inverted: false), .next,
                        "fingers left is still forwards with natural scrolling off")
            Check.equal(swipe(&classic, dx: -90, from: 200, inverted: false), .previous,
                        "and fingers right still goes back")
        }

        Check.suite("WorkspaceSwipe — what isn't a swipe") {
            var machine = WorkspaceSwipe()
            Check.equal(swipe(&machine, dx: -20), .none, "a nudge is not a swipe")

            // Scrolling a long board is mostly vertical with a wobble in it.
            var scrolling = WorkspaceSwipe()
            Check.equal(swipe(&scrolling, dx: -50, dy: 300), .none,
                        "a vertical scroll never pages sideways, however far it drifts")

            // Diagonal but horizontal-dominant still counts — people are not precise.
            var diagonal = WorkspaceSwipe()
            Check.equal(swipe(&diagonal, dx: -90, dy: 20), .next, "a sloppy swipe still counts")
        }

        Check.suite("WorkspaceSwipe — one switch per gesture") {
            var machine = WorkspaceSwipe()
            Check.equal(swipe(&machine, dx: -60), .next, "the flick lands")

            // Momentum keeps arriving for about a second after the fingers lift,
            // with plenty of travel left in it. It must not page again.
            var again = WorkspaceSwipe.Decision.none
            for step in 0..<10 {
                let result = machine.handle(
                    WorkspaceSwipe.Scroll(
                        deltaX: -40,
                        deltaY: 0,
                        isGestureStart: false,
                        isInverted: true,
                        time: 100.1 + Double(step) * 0.02
                    )
                )
                if again == .none { again = result }
            }
            Check.equal(again, .none, "the momentum that follows it does not page again")

            // A fresh gesture always can, however soon it comes.
            Check.equal(swipe(&machine, dx: -60, from: 100.4), .next,
                        "but the next deliberate swipe does")
        }

        Check.suite("WorkspaceSwipe — gestures that never say they started") {
            // An old wheel mouse reports no phases at all, so a quiet spell is the
            // only thing that separates one gesture from the next.
            var machine = WorkspaceSwipe()
            var decision = WorkspaceSwipe.Decision.none
            for step in 0..<3 {
                let result = machine.handle(
                    WorkspaceSwipe.Scroll(deltaX: -20, deltaY: 0, time: 10 + Double(step) * 0.05)
                )
                if decision == .none { decision = result }
            }
            Check.equal(decision, .next, "three quick ticks in the same direction accumulate")

            var slow = WorkspaceSwipe()
            var never = WorkspaceSwipe.Decision.none
            for step in 0..<5 {
                let result = slow.handle(
                    WorkspaceSwipe.Scroll(deltaX: -20, deltaY: 0, time: 10 + Double(step))
                )
                if never == .none { never = result }
            }
            Check.equal(never, .none, "ticks a second apart are separate gestures, not one swipe")
        }

        Check.suite("WorkspaceSwipe — reset") {
            var machine = WorkspaceSwipe()
            _ = machine.handle(WorkspaceSwipe.Scroll(deltaX: -30, deltaY: 0, isGestureStart: true, time: 5))
            machine.reset()
            // The panel folded away mid-swipe; what was travelled so far is forgotten.
            let decision = machine.handle(WorkspaceSwipe.Scroll(deltaX: -30, deltaY: 0, time: 5.05))
            Check.equal(decision, .none, "a reset forgets the travel so far")
        }
    }
}
