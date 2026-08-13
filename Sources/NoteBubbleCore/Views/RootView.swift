import SwiftUI

/// The expanded panel: the glass bar, then the tile grid.
struct RootView: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject var panelState: PanelState
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
    let isPinned: Bool
    let onTogglePin: () -> Void
    let drag: PanelDrag

    /// Whether the pointer is actually over the panel, as distinct from whether a
    /// note is being edited. Conflating the two is what made Return minimise it.
    @State private var isHovering = false

    /// A workspace deletion waiting to be confirmed. It lives here rather than in
    /// the chip that raised it because the sheet covers the whole panel — the same
    /// arrangement as a tile's pop confirmation, which `BubbleGrid` owns.
    @State private var pendingDeletion: Workspace?

    var body: some View {
        VStack(spacing: 0) {
            GlassBar(
                store: store,
                panelState: panelState,
                isPinned: isPinned,
                onTogglePin: onTogglePin,
                onClose: onClose,
                onDeleteWorkspace: requestDeletion,
                drag: drag
            )
            BubbleGrid(store: store, panelState: panelState)
        }
        // No background behind the grid: the tiles float directly over whatever you
        // are working on. Only the bar is a surface.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // The one space the bar and the grid share, so a tile dragged out of the
        // grid can be measured against the dots up in the bar.
        .coordinateSpace(name: PanelSpace.name)
        .onPreferenceChange(WorkspaceDropTargets.self) { panelState.workspaceDropTargets = $0 }
        .overlay { deletionConfirmation }
        // An open confirmation must survive the pointer leaving the panel.
        .onChange(of: pendingDeletion != nil) { _, isOpen in
            panelState.blocksAutoCollapse = isOpen
        }
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering || store.isEditing)
        }
        // Starting or finishing a note re-evaluates the panel's state so it cannot
        // dim mid-sentence with the pointer parked elsewhere.
        //
        // It reports `isHovering`, not `false`. Reporting a bare `false` when
        // editing ended told the panel the pointer had left, which scheduled a
        // collapse — so pressing Return to finish a note minimised the window a
        // moment later even though the pointer was sitting right on it.
        .onChange(of: store.editingID) { _, editing in
            onHoverChange(isHovering || editing != nil || store.renamingWorkspaceID != nil)
        }
        // Naming a workspace is typing too, and holds the panel open the same way.
        .onChange(of: store.renamingWorkspaceID) { _, renaming in
            onHoverChange(isHovering || renaming != nil || store.editingID != nil)
        }
    }

    /// An empty board goes without ceremony; one with notes on it asks, because
    /// this destroys more writing in a click than anything else in the app.
    private func requestDeletion(_ workspace: Workspace) {
        guard !workspace.notes.isEmpty else {
            withAnimation(Motion.reflow) { store.removeWorkspace(workspace.id) }
            return
        }
        withAnimation(Motion.overlay) { pendingDeletion = workspace }
    }

    @ViewBuilder
    private var deletionConfirmation: some View {
        if let pendingDeletion {
            ConfirmSheet(
                icon: "trash.fill",
                title: "Delete “\(pendingDeletion.displayName)”?",
                message: deletionMessage(for: pendingDeletion),
                confirmTitle: "Delete",
                onCancel: { withAnimation(Motion.overlay) { self.pendingDeletion = nil } },
                onConfirm: {
                    self.pendingDeletion = nil
                    withAnimation(Motion.reflow) { store.removeWorkspace(pendingDeletion.id) }
                }
            )
        }
    }

    private func deletionMessage(for workspace: Workspace) -> String {
        let count = workspace.notes.flattened.count
        let bubbles = count == 1 ? "1 bubble" : "\(count) bubbles"
        return "\(bubbles) go with it. ⌘Z puts the whole workspace back."
    }
}
