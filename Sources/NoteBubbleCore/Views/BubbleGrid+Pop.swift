import SwiftUI

// Popping a tile: the confirmation for one with notes inside it, the burst, the
// sound, and the toast that offers it back.

extension BubbleGrid {
    /// A pop held back pending confirmation, because the tile has notes inside it.
    ///
    /// Only the note and the grid's geometry: where the tile is gets worked out
    /// again when the answer comes, since the board can be shuffled or added to
    /// while the question is open.
    struct PendingPop {
        let node: BubbleNode
        let layout: GridLayout
    }

    @ViewBuilder
    var confirmation: some View {
        if let pendingPop {
            ConfirmPopSheet(
                node: pendingPop.node,
                onCancel: { withAnimation(Motion.overlay) { self.pendingPop = nil } },
                onConfirm: {
                    self.pendingPop = nil
                    commitPop(pendingPop.node, layout: pendingPop.layout)
                }
            )
        }
    }


    // MARK: - Popping

    /// Entry point for every pop, from a hold or from the context menu. Tiles
    /// holding unpopped bubbles divert to a confirmation instead of bursting.
    func performPop(_ node: BubbleNode, at index: Int, plan: LayoutPlan, layout: GridLayout) {
        tileGesture.consume()

        guard node.children.isEmpty else {
            // `clearDragState`, not `endPress`: the tile is still there, waiting on an
            // answer, and the button that raised the question may still be down.
            // Resetting the press here would let the next twitch of it start another,
            // which would sit under the sheet counting down to pop the same tile
            // again.
            clearDragState()
            withAnimation(Motion.overlay) {
                pendingPop = PendingPop(node: node, layout: layout)
            }
            return
        }
        commitPop(node, at: index, plan: plan)
    }

    /// Actually bursts a tile: particles, sound, removal, and the undo offer.
    ///
    /// The burst, the sound and the toast all wait on the store saying the note
    /// really went. A pop that finds nothing to remove — the note was already gone,
    /// or is on a board no longer in front of you — used to celebrate anyway, and
    /// the toast's Undo then undid something else entirely.
    func commitPop(_ node: BubbleNode, at index: Int, plan: LayoutPlan) {
        let size = plan.specs[index].size
        let burst = PopBurst(
            centre: plan.restingCentre(at: index),
            size: size,
            cornerRadius: TileStyle.cornerRadius(for: size),
            color: AgingPalette.color(forDays: node.ageInDays(at: store.now), in: store.currentWorkspace.window)
        )

        guard store.pop(node.id) else {
            endPress()
            return
        }
        bursts.append(burst)
        PopSounds.shared.play()
        endPress()
        showToast("Popped “\(node.displayName)”")

        Task {
            try? await Task.sleep(for: Motion.burstLifetime)
            bursts.removeAll { $0.id == burst.id }
        }
    }

    /// Commits a confirmed pop, measuring the tile where it is *now*.
    func commitPop(_ node: BubbleNode, layout: GridLayout) {
        let nodes = store.visible
        guard let index = nodes.firstIndex(where: { $0.id == node.id }) else {
            // Not on the level in front of you, so there is nothing to burst from.
            // Going elsewhere dismisses the question, so this should not happen.
            endPress()
            return
        }
        commitPop(node, at: index, plan: LayoutPlan(nodes: nodes, layout: layout))
    }

    func dismissPendingPop() {
        guard pendingPop != nil else { return }
        withAnimation(Motion.overlay) { pendingPop = nil }
    }

    // MARK: - Toast

    /// Offers to undo the action just recorded — and only that one. See
    /// `PanelState.Toast`.
    func showToast(_ message: String) {
        guard let undoID = store.lastUndoID else { return }
        panelState.showToast(message, undoing: undoID)
    }
}
