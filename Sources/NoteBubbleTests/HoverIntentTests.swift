import Foundation
@testable import NoteBubbleCore

enum HoverIntentTests {
    private static func effects(_ event: HoverIntent.Event, _ situation: HoverIntent.Situation) -> [HoverIntent.Effect] {
        HoverIntent.effects(for: event, in: situation)
    }

    static func run() {
        let pill = HoverIntent.Situation(isMinimised: true)
        let open = HoverIntent.Situation(isMinimised: false)

        Check.suite("Hover — the pill opens on a dwell") {
            Check.equal(effects(.entered, pill), [.cancelCollapse, .scheduleExpand],
                        "arriving on the pill starts the dwell, not the panel")
            Check.equal(effects(.expandDelayElapsed, pill), [.expand], "the dwell elapsing opens it")
            Check.equal(effects(.left, pill), [.cancelExpand], "sweeping past before the dwell opens nothing")
            Check.equal(effects(.expandDelayElapsed, open), [],
                        "a dwell finishing after the panel opened some other way does nothing")
        }

        Check.suite("Hover — the panel folds back after a grace") {
            Check.equal(effects(.left, open), [.cancelExpand, .scheduleCollapse], "leaving starts the grace")
            Check.equal(effects(.entered, open), [.cancelCollapse], "coming back within it keeps the panel open")
            Check.equal(effects(.collapseDelayElapsed, open), [.minimise], "the grace elapsing folds it")

            var pinned = open
            pinned.isPinned = true
            Check.equal(effects(.left, pinned), [.cancelExpand], "a pinned panel never starts the grace")
        }

        Check.suite("Hover — collapse re-checks its vetoes when it fires") {
            // Each of these can become true *during* the grace period.
            var pinned = open
            pinned.isPinned = true
            Check.equal(effects(.collapseDelayElapsed, pinned), [], "pinned meanwhile: stays open")

            var typing = open
            typing.isEditing = true
            Check.equal(effects(.collapseDelayElapsed, typing), [], "typing meanwhile: stays open")

            var held = open
            held.isHeld = true
            Check.equal(effects(.collapseDelayElapsed, held), [], "a drag or confirmation meanwhile: stays open")

            Check.equal(effects(.collapseDelayElapsed, pill), [], "already folded: nothing to do")
        }
    }
}
