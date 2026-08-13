import CoreGraphics
import Foundation

/// Decides whether a press on a tile is a tap, a hold or a drag.
///
/// This is the state machine that `BubbleGrid` used to keep in `@State` and spell
/// out inline. It is a plain value here — no SwiftUI, no store, no layout, no
/// clock — for two reasons:
///
/// 1. **It is the most delicate logic in the app and had no tests.** One
///    `DragGesture` serves three intents, because SwiftUI cannot arbitrate three
///    overlapping gestures on one view reliably. Every rule below was arrived at
///    from a bug, and each is now a check in `TileGestureTests`.
/// 2. **It is the part least likely to survive contact with a touchscreen.** Touch
///    has no hover, a fatter slop, and system gestures competing for the same
///    events. Keeping the decisions separate from the SwiftUI plumbing means a port
///    can retune `dragSlop`, feed the same events from a `UIGestureRecognizer`, and
///    still be running logic that is known-good.
///
/// Time is deliberately *not* modelled: the caller runs the countdown (its duration
/// is `Motion.popHold`) and reports `.holdElapsed` when it fires. A machine that
/// owned a clock could not be tested without waiting for one.
struct TileGesture {
    /// Movement past this many points is a rearrange, not a press.
    static let dragSlop: CGFloat = 6

    /// What the view has seen happen.
    enum Event: Equatable {
        /// The gesture reported movement — including the very first report, which a
        /// `minimumDistance: 0` drag delivers on mouse-down with no movement at all.
        /// That first one is what starts the press.
        case changed(id: UUID, translation: CGSize)
        /// The pop countdown reached its deadline.
        case holdElapsed(id: UUID)
        /// The press was released.
        case ended(id: UUID)
    }

    /// What the view must do about it. Ordered; apply them in sequence.
    enum Effect: Equatable {
        /// Start the pop countdown, and the swell that shows it filling up.
        case beginHold
        /// Stop the countdown and unwind the swell, leaving the press itself alone.
        case cancelHold
        /// This is a rearrange: lift the tile.
        case beginDrag
        /// Move the lifted tile, and re-test where it would drop.
        case track(CGSize)
        /// The hold won: burst the tile.
        case pop
        /// A click: open the tile.
        case enter
        /// A completed rearrange: commit the new order.
        case drop
        /// Clear whatever the press owned.
        case finish
    }

    private enum Phase {
        case idle
        /// Held, but not yet moved far enough to be a drag or long enough to pop.
        case pressing
        case dragging
        /// A pop has claimed this press. Its release must not also open the tile.
        case consumed
    }

    private var phase: Phase = .idle
    private(set) var activeID: UUID?

    /// Whether a rearrange is in progress — the grid stops scrolling during one.
    var isDragging: Bool { phase == .dragging }

    func isDragging(_ id: UUID) -> Bool { isDragging && activeID == id }

    /// Whether this tile is the one being pressed, for the swell it draws.
    func isPressed(_ id: UUID) -> Bool { activeID == id }

    /// Feeds an event in and returns what the view should do about it.
    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case let .changed(id, translation):
            return changed(id: id, translation: translation)
        case let .holdElapsed(id):
            return holdElapsed(id: id)
        case let .ended(id):
            return ended(id: id)
        }
    }

    /// Lets the tile go, silently.
    ///
    /// For the view to call once it has finished with a press, however that press
    /// ended. It matters most where there is no release to wait for: a tile popped
    /// mid-hold is *removed*, and SwiftUI does not reliably deliver `onEnded` for a
    /// view that no longer exists. Without this the machine would sit holding a
    /// tile that had gone, refusing every later press — the gesture equivalent of a
    /// stuck key.
    mutating func reset() {
        phase = .idle
        activeID = nil
    }

    /// Marks the press in progress as spoken for, without ending it.
    ///
    /// Two callers, one rule. A pop that arrives from somewhere other than a hold —
    /// the context menu — so that a press open underneath doesn't also *open* the
    /// tile when it is let go. And a tile filed onto another workspace, where the
    /// decision is taken mid-press and the button is very often still down.
    ///
    /// **Consuming, not resetting, is the whole point.** `reset()` puts the machine
    /// back to idle, and the next movement of a mouse button that was never released
    /// then reads as a *new* press — one that goes on to lift a second tile out of a
    /// layout that has already been replaced, and is never released because the view
    /// it belongs to has gone. That is a bubble frozen on screen. A consumed press
    /// ignores everything until it is genuinely let go.
    mutating func consume() {
        if phase != .idle { phase = .consumed }
    }

    // MARK: - Transitions

    private mutating func changed(id: UUID, translation: CGSize) -> [Effect] {
        var effects: [Effect] = []

        // A press whose fate is already decided has no claim on a *different* tile.
        // It may not even have a tile left: the one it belonged to has usually been
        // removed, which is why no release is coming to clear it. Yielding here is
        // what stops a consumed press becoming a stuck key.
        if phase == .consumed, activeID != id { reset() }

        if phase == .idle {
            phase = .pressing
            activeID = id
            effects.append(.beginHold)
        }

        // A second tile pressed while one is already held is ignored outright,
        // rather than stealing the press half way through it.
        guard activeID == id else { return [] }

        if phase == .pressing, hypot(translation.width, translation.height) > Self.dragSlop {
            // It turned out to be a rearrange, so the pop countdown is off.
            phase = .dragging
            effects.append(.cancelHold)
            effects.append(.beginDrag)
        }

        if phase == .dragging { effects.append(.track(translation)) }
        return effects
    }

    /// The countdown reaching its deadline only pops if the press is *still* just a
    /// press.
    ///
    /// Cancelling the countdown cannot stop a task that has already begun running,
    /// so a hold that started before the drag did will report in anyway. Checking
    /// the phase here is what makes that harmless; racing the cancellation is what
    /// used to make a rearrange occasionally burst the tile it was rearranging.
    private mutating func holdElapsed(id: UUID) -> [Effect] {
        guard activeID == id, phase == .pressing else { return [] }
        phase = .consumed
        return [.pop]
    }

    private mutating func ended(id: UUID) -> [Effect] {
        guard activeID == id else { return [] }

        var effects: [Effect] = [.cancelHold]
        switch phase {
        case .dragging: effects.append(.drop)
        case .pressing: effects.append(.enter)
        // A hold already decided this tile's fate; releasing must not also open it.
        case .consumed, .idle: break
        }
        effects.append(.finish)

        phase = .idle
        activeID = nil
        return effects
    }
}
