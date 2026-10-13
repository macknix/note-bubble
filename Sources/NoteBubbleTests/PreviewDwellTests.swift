import Foundation
@testable import NoteBubbleCore

enum PreviewDwellTests {
    static func run() {
        Check.suite("Previewing a board mid-drag") {
            let (a, b, c) = (UUID(), UUID(), UUID())
            let boards = [a, b, c]

            Check.equal(PreviewDwell.outcome(dwelledOn: c, stillOver: c, current: a, boards: boards),
                        .show(c, direction: 1), "a board further along slides in from the trailing edge")
            Check.equal(PreviewDwell.outcome(dwelledOn: a, stillOver: a, current: c, boards: boards),
                        .show(a, direction: -1), "an earlier one from the leading edge")
            Check.equal(PreviewDwell.outcome(dwelledOn: a, stillOver: a, current: a, boards: boards),
                        .clear, "resting on your own board's dot calls the preview off")
            Check.nil_(PreviewDwell.outcome(dwelledOn: b, stillOver: c, current: a, boards: boards),
                       "a dwell on a dot the tile has since left means nothing")
            Check.nil_(PreviewDwell.outcome(dwelledOn: b, stillOver: nil, current: a, boards: boards),
                       "nor one on a dot it has left altogether")
        }
    }
}
