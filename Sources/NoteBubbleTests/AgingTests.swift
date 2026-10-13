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
            Check.equal(AgingPalette.color(forDays: 7), AgingPalette.color(forDays: 900), "colour clamps at the red end")
            Check.equal(AgingPalette.color(forDays: 0), AgingPalette.color(forDays: -5), "colour clamps at the green end")

            Check.equal(AgingPalette.color(for: .overdue), AgingPalette.color(forDays: 30),
                        "a stage's colour is the colour of a note in it")
            Check.equal(AgingPalette.color(for: .fresh), AgingPalette.color(forDays: 0), "fresh is the starting green")
            Check.equal(Aging.stage(forDays: 5), .aging, "and ageing's colour comes from inside its own window")

            let samples = [0.0, 2.0, 4.0, 6.0, 7.0].map { AgingPalette.color(forDays: $0) }
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

            let table: [(Double, String)] = [
                (0, "today"), (0.9, "today"), (1, "yesterday"), (2, "2d"), (6, "6d"),
                (7, "1w"), (13, "1w"), (27, "3w"), (28, "4w"), (29, "4w"),
                (30, "1mo"), (59, "1mo"), (60, "2mo"), (364, "12mo"), (365, "1y"), (800, "2y")
            ]
            for (days, expected) in table {
                Check.equal(Aging.relativeAge(from: now.addingTimeInterval(-days * 86_400), now: now),
                            expected, "\(days) days reads as \(expected)")
            }

            Check.close(Motion.popHold.seconds, 0.55, "a Duration converts to seconds for the animation APIs")

            let spoken: [(Double, String)] = [
                (0, "written today"), (1, "written yesterday"), (2, "2 days old"), (7, "1 week old"),
                (14, "2 weeks old"), (30, "1 month old"), (90, "3 months old"), (365, "1 year old"), (800, "2 years old")
            ]
            for (days, expected) in spoken {
                Check.equal(Aging.spokenAge(from: now.addingTimeInterval(-days * 86_400), now: now),
                            expected, "VoiceOver reads \(days) days as “\(expected)”")
            }
            Check.equal([Aging.Stage.fresh, .aging, .overdue].map(\.name), ["fresh", "ageing", "overdue"],
                        "each stage has a name, for anything that cannot rely on colour")

            let node = BubbleNode(text: "x", createdAt: now.addingTimeInterval(-5 * 86_400))
            Check.close(node.ageInDays(at: now), 5, "ageInDays matches the creation date", tolerance: 0.000_1)
            Check.close(node.ageInDays(at: now.addingTimeInterval(2 * 86_400)), 7,
                        "and moves on with the clock it is given", tolerance: 0.000_1)
        }
    }
}
