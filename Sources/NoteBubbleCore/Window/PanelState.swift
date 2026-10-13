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
    /// Something on screen that must not be interrupted by the panel folding away.
    enum Hold: Hashable {
        case tileDrag
        case panelDrag
        case popConfirmation
        case workspaceDeletion

        /// Holds that belong to the view, and so go when the view does.
        static let viewOwned: Set<Hold> = [.tileDrag, .popConfirmation, .workspaceDeletion]
    }

    /// Pinned means "stay open" — for when you are actually working in the panel
    /// rather than glancing at it.
    ///
    /// Published state rather than a value handed to the view, because toggling a
    /// value handed in meant rebuilding the whole view to show it — which threw away
    /// the undo toast, any open confirmation and the scroll position with it.
    @Published var isPinned = false

    // MARK: - The undo toast

    /// A brief "Popped “Milk” · Undo", tied to the one action it describes.
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let message: String
        /// The undo record it offers to reverse — see `BubbleStore.lastUndoID`.
        let undoID: UUID
    }

    /// Lives here rather than in the grid so anything that does something undoable
    /// can raise one: the grid for a pop or a filing, `RootView` for deleting a board.
    @Published private(set) var toast: Toast?
    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String, undoing undoID: UUID) {
        toastTask?.cancel()
        let toast = Toast(message: message, undoID: undoID)
        self.toast = toast
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.toastLifetime)
            guard !Task.isCancelled, self?.toast == toast else { return }
            self?.dismissToast()
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    /// Everything currently holding the panel open.
    ///
    /// A set of named reasons rather than one flag, because there are four owners
    /// and they overlap. As a single `Bool` each owner assumed it was the only one:
    /// letting go of a panel drag while a pop confirmation was open set it to false,
    /// the pointer leaving then folded the panel away, and the question being asked
    /// vanished with the view. Each owner now adds and removes only its own reason.
    @Published private(set) var holds: Set<Hold> = []

    /// The panel refuses to auto-collapse while anything holds it, otherwise
    /// brushing the pointer off the edge would cancel the interaction.
    var blocksAutoCollapse: Bool { !holds.isEmpty }

    func setHold(_ hold: Hold, _ isHeld: Bool) {
        if isHeld {
            holds.insert(hold)
        } else {
            holds.remove(hold)
        }
    }

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

    /// Forgets everything the outgoing view owned.
    ///
    /// The grid clears its own state when a drag ends or a confirmation is answered,
    /// but that state does not outlive the view — and `PanelController` throws the
    /// whole view away whenever it swaps what the panel shows. Left behind, a drag
    /// would keep the dots swollen and the panel refusing to resize, and a hold for
    /// a confirmation nobody can see any more would stop it ever folding away.
    func forgetView() {
        holds.subtract(Hold.viewOwned)
        dismissToast()
        isDraggingTile = false
        hoveredWorkspace = nil
        previewWorkspace = nil
        workspaceDropTargets = []
    }
}
