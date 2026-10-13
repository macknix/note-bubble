import SwiftUI

// Showing another board while a tile is held over its dot. It is only ever a
// picture: the store stays on the board the tile came from for the whole drag —
// see `BubbleGrid.previewWorkspace` for why that matters.

extension BubbleGrid {
    // MARK: - Showing another board mid-drag

    /// The board whose tiles are on screen: the one being previewed, if any, or the
    /// one the store is actually on.
    var shownWorkspace: Workspace {
        previewWorkspace.flatMap { id in store.workspaces.first { $0.id == id } }
            ?? store.currentWorkspace
    }

    /// What is drawn right now — used for the empty state, which would otherwise
    /// describe the board hiding behind the preview.
    var shownNodes: [BubbleNode] {
        previewWorkspace == nil ? store.visible : shownWorkspace.notes
    }

    /// How far the real board is pushed aside to make room for the preview.
    func boardOffset(width: CGFloat) -> CGFloat {
        previewWorkspace == nil ? 0 : -previewDirection * width
    }

    @ViewBuilder
    func previewLayer(layout: GridLayout) -> some View {
        if previewWorkspace != nil {
            WorkspacePreview(workspace: shownWorkspace, layout: layout, now: store.now)
                .id(shownWorkspace.id)
                // It arrives from the side it lives on and leaves the same way, which
                // is what makes previewing feel like moving along the shelf of boards
                // rather than dealing cards onto it.
                .transition(.move(edge: previewDirection > 0 ? .trailing : .leading))
        }
    }

    /// Which way a workspace change travels. `switchDirection` is read here rather
    /// than tracked with `onChange` because the transition is decided during the
    /// very render the switch causes, and `onChange` fires after it.
    var slide: AnyTransition {
        let forwards = store.switchDirection > 0
        return .asymmetric(
            insertion: .move(edge: forwards ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forwards ? .leading : .trailing).combined(with: .opacity)
        )
    }
}
