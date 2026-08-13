import CoreGraphics
import Foundation

/// Decides when a two-finger scroll is a swipe between workspaces.
///
/// Same split as `TileGesture`, for the same reason: this is fiddly, sign-dependent
/// logic that would otherwise be buried in an `NSEvent` monitor where it could only
/// be tested with a trackpad and a pair of hands. It is a plain value — no AppKit,
/// no store, and no clock; the caller passes the event's own timestamp in.
///
/// Three rules, each of which is what stops a specific misfire:
///
/// 1. **One switch per gesture.** Committing latches until the next gesture starts,
///    so the momentum that keeps arriving for a second after your fingers lift
///    cannot flick you three boards along.
/// 2. **Horizontal has to win outright.** Scrolling a long board is mostly vertical
///    with a wobble of horizontal in it, and that wobble must never page sideways.
/// 3. **Fingers, not content.** `deltaX`'s sign flips with the "natural scrolling"
///    setting; a swipe is a gesture rather than a scroll, so it follows the fingers
///    either way — swipe left for the next board, exactly like Safari's back and
///    forward.
struct WorkspaceSwipe {
    /// Points of horizontal travel that count as a deliberate swipe. Roughly a
    /// third of the panel's width, so it takes a real flick rather than a drift.
    static let threshold: CGFloat = 42
    /// How much horizontal must beat vertical by before the gesture is a swipe.
    static let axisRatio: CGFloat = 1.5
    /// A quiet spell this long ends a gesture, for devices that don't report phases
    /// (an old wheel mouse) and so never say when one began.
    static let idleGap: TimeInterval = 0.3

    /// One scroll event, reduced to what the decision actually depends on.
    struct Scroll {
        var deltaX: CGFloat
        var deltaY: CGFloat
        /// The event's phase was `.began` — a new gesture, whatever came before.
        var isGestureStart: Bool
        /// `NSEvent.isDirectionInvertedFromDevice`: true under natural scrolling,
        /// where the deltas already follow the fingers.
        var isInverted: Bool
        /// `NSEvent.timestamp`, seconds since boot.
        var time: TimeInterval

        init(
            deltaX: CGFloat,
            deltaY: CGFloat,
            isGestureStart: Bool = false,
            isInverted: Bool = true,
            time: TimeInterval = 0
        ) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.isGestureStart = isGestureStart
            self.isInverted = isInverted
            self.time = time
        }
    }

    enum Decision: Equatable {
        case none
        case previous
        case next
    }

    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    /// This gesture has already had its switch; everything else it reports is the
    /// tail of the same flick.
    private var committed = false
    private var lastTime: TimeInterval?

    mutating func handle(_ scroll: Scroll) -> Decision {
        let isNewGesture = scroll.isGestureStart
            || lastTime.map { scroll.time - $0 > Self.idleGap } ?? true
        if isNewGesture { reset() }
        lastTime = scroll.time

        guard !committed else { return .none }

        // Normalised to finger direction: negative is fingers travelling left.
        travelX += scroll.isInverted ? scroll.deltaX : -scroll.deltaX
        travelY += scroll.deltaY

        guard abs(travelX) >= Self.threshold,
              abs(travelX) > abs(travelY) * Self.axisRatio
        else { return .none }

        committed = true
        return travelX < 0 ? .next : .previous
    }

    /// Forgets the gesture in progress. The caller uses this when the panel closes
    /// under a half-finished swipe, so the next one starts from nothing.
    mutating func reset() {
        travelX = 0
        travelY = 0
        committed = false
    }
}
