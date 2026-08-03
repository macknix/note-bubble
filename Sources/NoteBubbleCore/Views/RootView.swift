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

    var body: some View {
        VStack(spacing: 0) {
            GlassBar(
                store: store,
                isPinned: isPinned,
                onTogglePin: onTogglePin,
                onClose: onClose,
                drag: drag
            )
            BubbleGrid(store: store, panelState: panelState)
        }
        // No background behind the grid: the tiles float directly over whatever you
        // are working on. Only the bar is a surface.
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering || store.editingID != nil)
        }
        // Starting or finishing a note re-evaluates the panel's state so it cannot
        // dim mid-sentence with the pointer parked elsewhere.
        //
        // It reports `isHovering`, not `false`. Reporting a bare `false` when
        // editing ended told the panel the pointer had left, which scheduled a
        // collapse — so pressing Return to finish a note minimised the window a
        // moment later even though the pointer was sitting right on it.
        .onChange(of: store.editingID) { _, editing in
            onHoverChange(isHovering || editing != nil)
        }
    }
}
