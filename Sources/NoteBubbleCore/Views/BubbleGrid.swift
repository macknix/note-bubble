import SwiftUI

/// The tile grid. Tiles sit on fixed slots derived from their order in the model,
/// and dragging one reflows the rest around it exactly like rearranging apps.
///
/// Tap, long-press and drag are all served by a *single* `DragGesture` with
/// `minimumDistance: 0`. SwiftUI cannot reliably arbitrate three overlapping
/// gestures on one view, so the discrimination is done by hand — but *not* here.
/// `TileGesture` decides which of the three a press turned out to be; this view
/// only feeds it events and carries out what it says.
struct BubbleGrid: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject var panelState: PanelState

    static let coordinateSpace = "bubble-grid"
    /// The grid's *viewport*, as distinct from its scrollable content. Drop targets
    /// live here: they sit still while the content behind them can be scrolled.
    static let viewportSpace = "bubble-grid-viewport"

    // MARK: - Interaction state
    //
    // Internal rather than private only so the extensions beside this file —
    // `+Drag`, `+Preview`, `+Pop` — can reach them. Nothing outside the grid should.

    @State var tileGesture = TileGesture()
    @State var pressProgress: CGFloat = 0
    @State var dropIndex: Int?
    @State var popTask: Task<Void, Never>?

    @State var bursts: [PopBurst] = []
    @State var pendingPop: PendingPop?

    // MARK: - Dropping onto another workspace

    /// Where the scrollable content sits — in the viewport, for drawing the tile
    /// that has been picked up, and in the panel, for hit-testing it against the
    /// workspace dots up in the bar.
    ///
    /// Measured only while a tile is under the finger, so it settles once per press
    /// rather than once per scrolled frame. `nil` means "not being tracked", and
    /// nothing can be hit until it is.
    @State var offsets: GridOffsets?

    /// The tile in the air — what it is, where it has been carried to, and which
    /// dot it is over. All of it lives in `TileFlight`, where it can be tested.
    @State var flight = TileFlight()

    /// Watching the tile in hand for a shake, which resets its age.
    @State var shake = ShakeDetector()

    /// Waiting out the dwell before resting on a dot slides that board into view.
    @State var previewTask: Task<Void, Never>?
    /// Which side the previewed board came in from, remembered so that calling the
    /// preview off sends it back the way it arrived rather than always rightwards.
    @State var previewDirection: CGFloat = 1

    /// The board being shown *instead of* this one while a tile is held over its
    /// dot — and, when the tile is let go, where it goes.
    ///
    /// It is only ever a picture. The store stays on the board the tile came from
    /// for the whole drag, and that is the point: switching for real would take the
    /// dragged tile's own view off screen with the level it belongs to, and SwiftUI
    /// stops delivering drag events to a view that is being removed. The tile would
    /// stop following the cursor and its release would never be reported. Showing
    /// the destination rather than going to it keeps the drag intact, and lets the
    /// note land when you let go rather than the moment you arrive.
    ///
    /// Kept in `panelState` rather than here because the bar has to show the same
    /// board the grid is showing.
    var previewWorkspace: UUID? { panelState.previewWorkspace }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let nodes = store.visible
            let layout = GridLayout(availableWidth: geometry.size.width)
            // All of this is computed once per render rather than per tile. During a
            // drag every tile needs the hypothetical order and the frames that fall
            // out of it; deriving them inside the loop made reflow O(n²) per frame.
            let plan = LayoutPlan(
                nodes: nodes,
                layout: layout,
                dragged: tileGesture.isDragging ? tileGesture.activeID : nil,
                dropIndex: dropIndex
            )

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    background

                    // Keyed by workspace so switching boards is a slide rather than
                    // a substitution: the outgoing tiles leave the way your fingers
                    // went and the incoming ones follow from the far edge. Without
                    // the `.id` SwiftUI would treat it as one set of tiles being
                    // replaced by another and cross-fade them in place.
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                            tile(node, index: index, plan: plan, layout: layout)
                        }
                    }
                    .id(store.currentWorkspaceID)
                    .transition(slide)
                    // Held aside while another board is being shown in its place. It
                    // is still mounted — the tile being dragged lives in here, and it
                    // has to keep receiving the drag.
                    .offset(x: boardOffset(width: geometry.size.width))
                    .opacity(previewWorkspace == nil ? 1 : 0)

                    previewLayer(layout: layout)

                    ForEach(bursts) { $0 }
                }
                .frame(
                    width: geometry.size.width,
                    height: max(plan.contentHeight, geometry.size.height),
                    alignment: .topLeading
                )
                .coordinateSpace(name: Self.coordinateSpace)
                .background { contentOriginReader }
            }
            .scrollDisabled(tileGesture.isDragging)
            .overlay { if shownNodes.isEmpty && pendingPop == nil { emptyState } }
            // The tile in hand is drawn *here*, outside the scroll view, so it can
            // be carried up over the bar — see `liftedTile`.
            .overlay(alignment: .topLeading) { liftedTile }
            .overlay { confirmation }
            .coordinateSpace(name: Self.viewportSpace)
            .onPreferenceChange(GridOffsetsKey.self) { offsets = $0 }
            // An open confirmation must survive the pointer leaving the panel.
            .onChange(of: pendingPop != nil) { _, isOpen in
                panelState.setHold(.popConfirmation, isOpen)
            }
            // Nothing should change the board *for real* under a drag — previewing
            // deliberately does not — so if something does, the drag is over. Filing
            // has finished and cleaned up before this can run; this is for ⌘←, the
            // menu bar, or a swipe that slipped through, any of which would otherwise
            // leave a tile in the air over a board it does not belong to, with no
            // view left to report the release.
            .onChange(of: store.currentWorkspaceID) { _, _ in
                if tileGesture.isDragging { cancelDrag() }
                dismissPendingPop()
            }
            // A confirmation asks about a tile on the level in front of you. Going
            // somewhere else — a breadcrumb, ⌘←, the menu bar — leaves it asking about
            // something you can no longer see, so it goes.
            .onChange(of: store.path) { _, _ in dismissPendingPop() }
        }
    }

    var background: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.addBubble() }
            // A single click on open space finishes whatever is being typed — the
            // other half of "click away to finish".
            .onTapGesture { store.editingID = nil }
    }

    /// An empty level says what's missing and how to fix it, and nothing else.
    ///
    /// It used to also list "click to open · hold to pop · drag to rearrange",
    /// which describes things you do *to* bubbles — useless advice on a screen
    /// with no bubbles on it.
    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 26, weight: .light))

            Text(store.isAtRoot ? "No bubbles yet" : "No sub-bubbles yet")
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            Text("Click + or press ⌘N to add one")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.75)
        }
        .foregroundStyle(.secondary.opacity(0.65))
        .allowsHitTesting(false)
    }

    // MARK: - Tiles

    func tile(
        _ node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some View {
        let isDragging = tileGesture.isDragging(node.id)
        let isEditing = store.editingID == node.id
        let size = plan.specs[index].size

        // The tile being dragged holds its resting slot and turns invisible: the
        // copy you are actually moving is drawn outside the scroll view, by
        // `liftedTile`, where it can be carried past the grid's edges. Everything
        // else sits wherever the reflow has landed it.
        //
        // If that copy hasn't been made — the measurements it needs arrive a render
        // after the press — this one moves and stays visible instead. Rearranging is
        // the oldest thing the grid does and must not depend on the newest.
        let isLifted = isDragging && flight.isCarrying
        let anchor = isDragging ? plan.restingCentre(at: index) : plan.centre(of: node.id, at: index)
        let position = isDragging && !isLifted
            ? CGPoint(x: anchor.x + flight.translation.width, y: anchor.y + flight.translation.height)
            : anchor

        return BubbleTile(
            node: node,
            size: size,
            now: store.now,
            isEditing: isEditing,
            isDragging: isDragging,
            pressProgress: tileGesture.isPressed(node.id) ? pressProgress : 0,
            onCommit: { store.updateText($0, for: node.id) },
            onFinish: { store.editingID = nil },
            onRename: { store.editingID = node.id }
        )
        .opacity(isLifted ? 0 : 1)
        .position(position)
        .zIndex(isDragging && !isLifted ? 10 : (isEditing ? 5 : 0))
        .animation(Motion.resize, value: size)
        // Only the settling of *other* tiles is animated; the dragged tile must
        // track the cursor with no lag.
        .animation(isDragging ? nil : Motion.reflow, value: position)
        .contextMenu { contextMenu(node, index: index, plan: plan, layout: layout) }
        // VoiceOver cannot hold, drag or aim at a dot, so everything those do is
        // offered as an action instead — the same actions as the context menu, and
        // the same paths, so a parent still asks before it pops.
        .accessibilityActions { contextMenu(node, index: index, plan: plan, layout: layout) }
        .accessibilityAction { store.drillInto(node.id) }
        // While editing, the gesture is masked off so the text field owns the mouse.
        .gesture(
            gesture(for: node, index: index, plan: plan, layout: layout),
            including: isEditing ? .subviews : .all
        )
    }

    @ViewBuilder
    func contextMenu(
        _ node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some View {
        Button("Open") { store.drillInto(node.id) }
        Button("Rename") { store.editingID = node.id }
        Button("Reset age to today") { store.touch(node.id) }
        if store.hasMultipleWorkspaces {
            Menu("Move to") {
                ForEach(store.workspaces.filter { $0.id != store.currentWorkspaceID }) { workspace in
                    Button(workspace.displayName) { move(node, to: workspace) }
                }
            }
        }
        Divider()
        Button("Pop", role: .destructive) { performPop(node, at: index, plan: plan, layout: layout) }
    }

    /// Files a note onto another board without dragging it there — from the context
    /// menu, or VoiceOver. You stay where you are; the toast offers it back.
    func move(_ node: BubbleNode, to workspace: Workspace) {
        guard withAnimation(Motion.reflow, { store.move(node.id, toWorkspace: workspace.id) }) else { return }
        showToast("Moved “\(node.displayName)” to \(workspace.displayName)")
    }

}

/// Carries `GridOffsets` up from inside the scrolled content. `nil` while no tile
/// is under the finger, which is what keeps it from firing on every scrolled frame.
struct GridOffsetsKey: PreferenceKey {
    static var defaultValue: GridOffsets? { nil }

    static func reduce(value: inout GridOffsets?, nextValue: () -> GridOffsets?) {
        value = nextValue() ?? value
    }
}
