import Foundation
@testable import NoteBubbleCore

enum AgingTests {
    static func run() {
        Check.suite("Ageing") {
            Check.equal(Aging.stage(forDays: 0), .fresh, "a new note is fresh")
            Check.equal(Aging.stage(forDays: 2.9), .fresh, "still fresh just under three days")
            Check.equal(Aging.stage(forDays: 3), .aging, "three days is amber")
            Check.equal(Aging.stage(forDays: 6.9), .aging, "still amber just under a week")
            Check.equal(Aging.stage(forDays: 7), .overdue, "a week is overdue")
            Check.equal(Aging.stage(forDays: 400), .overdue, "ancient notes stay overdue")

            // No hue wraparound back towards green once past the window.
            Check.equal(Aging.color(forDays: 7), Aging.color(forDays: 900), "colour clamps at the red end")
            Check.equal(Aging.color(forDays: 0), Aging.color(forDays: -5), "colour clamps at the green end")

            let samples = [0.0, 2.0, 4.0, 6.0, 7.0].map { Aging.color(forDays: $0) }
            var allDistinct = true
            for (a, b) in zip(samples, samples.dropFirst()) where a == b { allDistinct = false }
            Check.isTrue(allDistinct, "colour keeps changing across the week")

            // A fixed instant: ages are measured against a clock that is passed in.
            let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
            Check.equal(Aging.relativeAge(from: now, now: now), "today", "today reads as today")
            Check.equal(Aging.relativeAge(from: now.addingTimeInterval(-86_400), now: now), "yesterday", "one day reads as yesterday")
            Check.equal(Aging.relativeAge(from: now.addingTimeInterval(-3 * 86_400), now: now), "3d", "days are abbreviated")
            Check.equal(Aging.relativeAge(from: now.addingTimeInterval(-14 * 86_400), now: now), "2w", "two weeks reads as 2w")
            Check.equal(Aging.relativeAge(from: now.addingTimeInterval(-60 * 86_400), now: now), "2mo", "two months reads as 2mo")

            let node = BubbleNode(text: "x", createdAt: now.addingTimeInterval(-5 * 86_400))
            Check.close(node.ageInDays(at: now), 5, "ageInDays matches the creation date", tolerance: 0.000_1)
            Check.close(node.ageInDays(at: now.addingTimeInterval(2 * 86_400)), 7,
                        "and moves on with the clock it is given", tolerance: 0.000_1)
        }
    }
}
