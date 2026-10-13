import Foundation
@testable import NoteBubbleCore

@MainActor
enum PanelStateTests {
    static func run() {
        Check.suite("PanelState — holds on auto-collapse") {
            let state = PanelState()
            Check.isFalse(state.blocksAutoCollapse, "nothing holds a fresh panel open")

            // The bug: a pop confirmation is open, the panel is dragged by its bar and
            // let go. Releasing the drag must not release the confirmation's hold.
            state.setHold(.popConfirmation, true)
            state.setHold(.panelDrag, true)
            state.setHold(.panelDrag, false)
            Check.isTrue(state.blocksAutoCollapse, "ending a panel drag leaves an open confirmation holding")

            // Nor may finishing a tile drag.
            state.setHold(.tileDrag, true)
            state.setHold(.tileDrag, false)
            Check.isTrue(state.blocksAutoCollapse, "and so does ending a tile drag")

            state.setHold(.popConfirmation, false)
            Check.isFalse(state.blocksAutoCollapse, "the last hold to go lets the panel fold again")

            state.setHold(.workspaceDeletion, false)
            Check.isFalse(state.blocksAutoCollapse, "releasing a hold that was never taken is harmless")

            // Swapping the view throws away what the view owned, but not a drag of the
            // window itself, which belongs to the controller.
            state.setHold(.panelDrag, true)
            state.setHold(.popConfirmation, true)
            state.setHold(.tileDrag, true)
            state.isDraggingTile = true
            state.forgetView()
            Check.equal(state.holds, [.panelDrag], "a replaced view's holds go with it")
            Check.isFalse(state.isDraggingTile, "as does its drag")

            // Pinning belongs to the panel, not the view, so a view swap keeps it.
            state.isPinned = true
            state.forgetView()
            Check.isTrue(state.isPinned, "pinning survives the view being replaced")
        }
    }
}
