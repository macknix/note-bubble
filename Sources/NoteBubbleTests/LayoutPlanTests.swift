import Foundation
@testable import NoteBubbleCore

@MainActor
enum LayoutPlanTests {
    static func run() {
        Check.suite("LayoutPlan — the reflow under a drag") {
            let layout = GridLayout(availableWidth: 432)
            let long = String(repeating: "A note long enough to want two columns. ", count: 6)
            let nodes = ["one", long, "three", "four", "five"].map { BubbleNode(text: $0) }
            let ids = nodes.map(\.id)

            let resting = LayoutPlan(nodes: nodes, layout: layout)
            Check.isTrue(resting.reflowedCentres.isEmpty, "nothing reflows without a drag")
            Check.equal(resting.centre(of: ids[2], at: 2), resting.restingCentre(at: 2),
                        "and every tile sits at its resting centre")

            // Carry the first tile to slot 3: everyone else moves to where the packer
            // would put them in that order — the plan must agree with the packer.
            let plan = LayoutPlan(nodes: nodes, layout: layout, dragged: ids[0], dropIndex: 3)
            let order = ids.reordered(moving: ids[0], to: 3)
            let byID = Dictionary(uniqueKeysWithValues: zip(ids, plan.specs))
            let expected = layout.frames(for: order.map { byID[$0]! })
            for (slot, id) in order.enumerated() {
                Check.equal(plan.centre(of: id, at: ids.firstIndex(of: id)!),
                            CGPoint(x: expected[slot].midX, y: expected[slot].midY),
                            "reflowed centre for slot \(slot) matches packing the new order")
            }
            Check.equal(plan.restingFrames, resting.restingFrames,
                        "resting frames — what drops are tested against — never move under a drag")

            let carried = LayoutPlan(nodes: nodes, layout: layout, dragged: ids[0], dropIndex: nil)
            Check.isTrue(carried.reflowedCentres.isEmpty,
                         "a tile carried off towards another board sends the rest back to rest")
        }
    }
}
