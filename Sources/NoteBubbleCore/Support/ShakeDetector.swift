import CoreGraphics
import Foundation

/// Decides when a tile being carried has been *shaken* — waggled back and forth —
/// which resets its age to today.
///
/// The fourth of the grid's deciders, beside `TileGesture`, `TileFlight` and
/// `PreviewDwell`, and like them it has no SwiftUI and no clock of its own: the
/// caller passes each position with the time it was reported. A shake is a run of
/// direction reversals, each after a real swing, close together in time, on either
/// axis. The thresholds are what stop an ordinary rearrange — which wanders, and
/// sometimes doubles back once to settle on a slot — from ever counting.
struct ShakeDetector {
    /// How far a swing has to travel before turning back counts as a reversal.
    static let minimumSwing: CGFloat = 14
    /// Reversals needed: there, back, there, back.
    static let reversalsNeeded = 4
    /// …all within this long.
    static let window: TimeInterval = 0.9

    private var horizontal = Axis()
    private var vertical = Axis()
    /// One shake per carry: the rest of a vigorous waggle is the same shake.
    private var hasFired = false

    /// Feeds in where the tile is. Returns true exactly once, when the shake
    /// completes.
    mutating func track(_ position: CGPoint, at time: TimeInterval) -> Bool {
        guard !hasFired else { return false }
        // Both axes are fed every time — `||` would starve the second.
        let acrossShook = horizontal.track(position.x, at: time)
        let upDownShook = vertical.track(position.y, at: time)
        let shook = acrossShook || upDownShook
        if shook { hasFired = true }
        return shook
    }

    mutating func reset() {
        self = ShakeDetector()
    }

    /// Reversals along one axis.
    private struct Axis {
        private var extreme: CGFloat?
        /// +1 or -1 once a swing has started, 0 before.
        private var direction: CGFloat = 0
        private var reversals: [TimeInterval] = []

        mutating func track(_ value: CGFloat, at time: TimeInterval) -> Bool {
            guard let turn = extreme else {
                extreme = value
                return false
            }
            let travel = value - turn
            if direction == 0 {
                // The first swing sets the direction, once it is a real one.
                if abs(travel) >= ShakeDetector.minimumSwing {
                    direction = travel > 0 ? 1 : -1
                    extreme = value
                }
                return false
            }
            if travel * direction > 0 {
                // Still going the same way: the turning point moves with it.
                extreme = value
                return false
            }
            guard abs(travel) >= ShakeDetector.minimumSwing else { return false }

            direction = -direction
            extreme = value
            reversals.append(time)
            reversals.removeAll { time - $0 > ShakeDetector.window }
            return reversals.count >= ShakeDetector.reversalsNeeded
        }
    }
}
