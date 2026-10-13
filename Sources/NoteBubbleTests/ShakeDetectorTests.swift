import CoreGraphics
import Foundation
@testable import NoteBubbleCore

enum ShakeDetectorTests {
    /// Feeds a path of x positions, one every `step` seconds, and reports the index
    /// of the point at which a shake fired, if any.
    private static func shake(_ xs: [CGFloat], step: TimeInterval = 0.05, y: Bool = false) -> Int? {
        var detector = ShakeDetector()
        var fired: Int?
        for (index, value) in xs.enumerated() {
            let point = y ? CGPoint(x: 0, y: value) : CGPoint(x: value, y: 0)
            if detector.track(point, at: Double(index) * step) {
                if fired == nil { fired = index } else { return -1 } // fired twice
            }
        }
        return fired
    }

    static func run() {
        Check.suite("Shaking a tile") {
            let waggle: [CGFloat] = [0, 20, 40, 20, 0, 20, 40, 20, 0, 20, 40]
            Check.isTrue(shake(waggle) != nil, "four quick swings back and forth is a shake")
            Check.isTrue(shake(waggle, y: true) != nil, "up and down counts too")
            Check.isTrue((shake(waggle) ?? 0) > 0, "and it fires once, on the last reversal")

            let longer: [CGFloat] = waggle + waggle.dropFirst() + waggle.dropFirst()
            Check.isTrue(shake(longer) != -1, "a long waggle is still one shake")

            let rearrange: [CGFloat] = stride(from: 0, through: 200, by: 10).map { CGFloat($0) }
            Check.nil_(shake(rearrange), "carrying a tile somewhere is not a shake")

            let settle: [CGFloat] = [0, 40, 80, 120, 100, 80, 90, 100]
            Check.nil_(shake(settle), "nor is overshooting a slot and coming back to it")

            let jitter: [CGFloat] = [0, 6, 0, 6, 0, 6, 0, 6, 0, 6, 0]
            Check.nil_(shake(jitter), "a hand's tremor is too small to count")

            Check.nil_(shake(waggle, step: 0.3), "and swings too slow to be a shake are a wander")
        }
    }
}
