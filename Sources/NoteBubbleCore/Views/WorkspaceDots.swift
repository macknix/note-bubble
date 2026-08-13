import SwiftUI

/// One dot per workspace, coloured by the worst thing on that board.
///
/// This is the whole reason the swipe is discoverable: without it a second board is
/// invisible. It doubles as the answer to "is anything rotting on the boards I'm
/// not looking at" — the bar's counts are deliberately scoped to the board on
/// screen, so the dots are where the others get to speak up.
///
/// They are also where a tile is dropped to send it to another board. Rather than
/// raise a separate set of targets for that, the dots **grow** while a tile is in
/// hand: the thing that already means "the other boards" becomes the thing you aim
/// at, and the row keeps its meaning instead of being replaced by another one.
struct WorkspaceDots: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject var panelState: PanelState

    private var isDropping: Bool { panelState.isDraggingTile }

    /// The board on screen — the previewed one while a tile is being carried to it,
    /// otherwise the one the store is on.
    private var shownWorkspaceID: UUID {
        panelState.previewWorkspace ?? store.currentWorkspaceID
    }

    var body: some View {
        HStack(spacing: isDropping ? 5 : 3) {
            ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                let isCurrent = workspace.id == shownWorkspaceID
                Button {
                    withAnimation(Motion.reflow) { store.selectWorkspace(at: index) }
                } label: {
                    dot(for: workspace, isCurrent: isCurrent)
                }
                .buttonStyle(.plain)
                .help(tooltip(for: workspace))
                // The board you are already on is not a destination, so its dot
                // neither grows a ring nor accepts a tile.
                .background { if isDropping && !isCurrent { targetReporter(for: workspace) } }
            }
        }
        .animation(Motion.lift, value: shownWorkspaceID)
        .animation(Motion.lift, value: isDropping)
    }

    private func dot(for workspace: Workspace, isCurrent: Bool) -> some View {
        let isTarget = isDropping && !isCurrent
        let isHovered = panelState.hoveredWorkspace == workspace.id
        // Growing is what turns a 6pt readout into something you can hit with a
        // tile in hand; the ring is what says it is expecting one.
        let width: CGFloat = isCurrent ? 15 : (isTarget ? 11 : 6)

        return Capsule()
            .fill(colour(for: workspace, isCurrent: isCurrent))
            .frame(width: width, height: isTarget ? 11 : 6)
            .overlay {
                if isTarget {
                    Capsule()
                        .strokeBorder(
                            isHovered ? BarStyle.candyPink : .white.opacity(0.35),
                            lineWidth: isHovered ? 2 : 1
                        )
                        .padding(-3)
                }
            }
            .scaleEffect(isHovered ? 1.45 : 1)
            .frame(width: isCurrent ? 21 : (isTarget ? 24 : 12), height: 20)
            .contentShape(Rectangle())
            .animation(Motion.lift, value: isHovered)
    }

    /// Publishes this dot's frame in the panel's coordinate space, so the grid can
    /// hit-test a dragged tile against it. Only while a drag is on: the frames are
    /// meaningless otherwise, and measuring them costs nothing when nobody asks.
    private func targetReporter(for workspace: Workspace) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WorkspaceDropTargets.self,
                value: [
                    WorkspaceDropTarget(
                        id: workspace.id,
                        frame: proxy.frame(in: .named(PanelSpace.name))
                    )
                ]
            )
        }
    }

    /// Empty boards stay grey: a dot with no notes behind it has nothing to warn
    /// about, and colouring it green would claim otherwise.
    private func colour(for workspace: Workspace, isCurrent: Bool) -> Color {
        guard let stage = workspace.worstStage else {
            return .white.opacity(isCurrent ? 0.5 : 0.2)
        }
        let days: Double = switch stage {
        case .fresh: 0
        case .aging: 4
        case .overdue: 30
        }
        return Aging.color(forDays: days).opacity(isCurrent ? 1 : 0.45)
    }

    private func tooltip(for workspace: Workspace) -> String {
        let dropHint = isDropping && !(panelState.hoveredWorkspace == workspace.id)
            ? " — drop to move the bubble here"
            : ""
        return summary(for: workspace) + dropHint
    }

    private func summary(for workspace: Workspace) -> String {
        let count = workspace.notes.flattened.count
        let notes = count == 1 ? "1 bubble" : "\(count) bubbles"
        let overdue = workspace.overdueCount
        return overdue > 0
            ? "\(workspace.displayName) — \(notes), \(overdue) overdue"
            : "\(workspace.displayName) — \(notes)"
    }
}

/// The dots' catchments, gathered as they lay themselves out. What to do with them
/// is `WorkspaceDrop`'s business, in Support, where it can be tested.
struct WorkspaceDropTargets: PreferenceKey {
    static var defaultValue: [WorkspaceDropTarget] { [] }

    static func reduce(value: inout [WorkspaceDropTarget], nextValue: () -> [WorkspaceDropTarget]) {
        value.append(contentsOf: nextValue())
    }
}
