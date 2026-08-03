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
        .onHover(perform: onHoverChange)
        // Starting or finishing a note re-evaluates the fade, so the panel cannot
        // dim while you are mid-sentence with the pointer parked elsewhere.
        .onChange(of: store.editingID) { _, _ in onHoverChange(store.editingID != nil) }
    }
}
