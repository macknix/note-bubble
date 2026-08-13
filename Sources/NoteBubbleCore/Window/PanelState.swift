import CoreGraphics
import Foundation

/// The panel's own coordinate space, spanning the bar and the grid together.
///
/// It exists because dragging a tile onto a workspace dot is a conversation
/// between two views that are siblings — the grid knows where the tile is, the bar
/// knows where the dots are, and neither is inside the other. A shared space is
/// the only place those two answers can be compared.
enum PanelSpace {
    static let name = "note-bubble-panel"
}

/// Transient panel-level UI state that the window needs to know about but the
/// note model has no business holding — plus the little the bar and the grid have
/// to tell each other.
@MainActor
final class PanelState: ObservableObject {
    /// Set while something on screen must not be interrupted: a confirmation
    /// sheet, or a tile mid-drag. The panel refuses to auto-collapse while true,
    /// otherwise brushing the pointer off the edge would cancel the interaction.
    @Published var blocksAutoCollapse = false

    // MARK: - Dragging a tile onto another workspace

    /// A tile is in hand. The workspace dots grow into targets while it is.
    @Published var isDraggingTile = false

    /// The dot the tile is currently over, if any. Published because the bar draws
    /// the highlight — and it changes a handful of times per drag rather than once
    /// per frame, because the grid only writes when the answer actually changes.
    @Published var hoveredWorkspace: UUID?

    /// The board being *shown* while a tile is held over its dot, which is not the
    /// board the store is on — see `BubbleGrid.previewWorkspace`. It lives here
    /// because the bar has to agree with the grid about what is on screen: a
    /// workspace chip reading "Home" over another board's notes is a worse answer
    /// than showing no preview at all.
    @Published var previewWorkspace: UUID?

    /// Where each dot is, in `PanelSpace`. Written by the bar as it lays itself
    /// out, read by the grid when a drag moves.
    ///
    /// Deliberately **not** `@Published`: it is read at drag time, never during a
    /// render. Publishing it would mean the dots growing at the start of a drag
    /// republished the frames that growing produced, re-rendering the whole panel a
    /// second time for no one's benefit.
    var workspaceDropTargets: [WorkspaceDropTarget] = []

    /// Forgets any drag in progress.
    ///
    /// The grid clears its own state when a drag ends, but the grid's state does not
    /// outlive the grid — and `PanelController` throws the whole view away whenever
    /// it swaps what the panel shows. A drag interrupted that way would otherwise
    /// leave the dots swollen for good, and the panel refusing to resize itself.
    func endTileDrag() {
        isDraggingTile = false
        hoveredWorkspace = nil
        previewWorkspace = nil
        workspaceDropTargets = []
    }
}
