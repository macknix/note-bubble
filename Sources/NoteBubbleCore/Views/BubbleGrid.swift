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

    private static let coordinateSpace = "bubble-grid"
    /// The grid's *viewport*, as distinct from its scrollable content. Drop targets
    /// live here: they sit still while the content behind them can be scrolled.
    static let viewportSpace = "bubble-grid-viewport"

    // MARK: - Interaction state

    /// A pop held back pending confirmation, because the tile has notes inside it.
    private struct PendingPop {
        let node: BubbleNode
        let index: Int
        let plan: LayoutPlan
    }

    @State private var tileGesture = TileGesture()
    @State private var pressProgress: CGFloat = 0
    @State private var dropIndex: Int?
    @State private var popTask: Task<Void, Never>?

    @State private var bursts: [PopBurst] = []
    @State private var pendingPop: PendingPop?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    // MARK: - Dropping onto another workspace

    /// Where the scrollable content sits — in the viewport, for drawing the tile
    /// that has been picked up, and in the panel, for hit-testing it against the
    /// workspace dots up in the bar.
    ///
    /// Measured only while a tile is under the finger, so it settles once per press
    /// rather than once per scrolled frame. `nil` means "not being tracked", and
    /// nothing can be hit until it is.
    @State private var offsets: GridOffsets?

    /// The tile in the air — what it is, where it has been carried to, and which
    /// dot it is over. All of it lives in `TileFlight`, where it can be tested.
    @State private var flight = TileFlight()

    /// Waiting out the dwell before resting on a dot slides that board into view.
    @State private var previewTask: Task<Void, Never>?
    /// Which side the previewed board came in from, remembered so that calling the
    /// preview off sends it back the way it arrived rather than always rightwards.
    @State private var previewDirection: CGFloat = 1

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
    private var previewWorkspace: UUID? { panelState.previewWorkspace }

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
            .overlay(alignment: .bottom) { if let toast { UndoToast(message: toast, onUndo: undo) } }
            .overlay { confirmation }
            .coordinateSpace(name: Self.viewportSpace)
            .onPreferenceChange(GridOffsetsKey.self) { offsets = $0 }
            // An open confirmation must survive the pointer leaving the panel.
            .onChange(of: pendingPop != nil) { _, isOpen in
                panelState.blocksAutoCollapse = isOpen
            }
            // Nothing should change the board *for real* under a drag — previewing
            // deliberately does not — so if something does, the drag is over. Filing
            // has finished and cleaned up before this can run; this is for ⌘←, the
            // menu bar, or a swipe that slipped through, any of which would otherwise
            // leave a tile in the air over a board it does not belong to, with no
            // view left to report the release.
            .onChange(of: store.currentWorkspaceID) { _, _ in
                if tileGesture.isDragging { cancelDrag() }
            }
        }
    }

    /// Reports where the scrolled content sits, but only while it matters — see
    /// `offsets`. One reader, two spaces: the same origin is needed in both.
    ///
    /// Tracked from the moment a tile is *pressed*, not from the moment a drag is
    /// recognised, so the answer has already arrived by the time it is needed. A
    /// drag begins several points into a press, and a preference published on the
    /// same render it is read on is a render too late.
    private var contentOriginReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: GridOffsetsKey.self,
                value: tileGesture.activeID != nil
                    ? GridOffsets(
                        inViewport: proxy.frame(in: .named(Self.viewportSpace)).origin,
                        inPanel: proxy.frame(in: .named(PanelSpace.name)).origin
                    )
                    : nil
            )
        }
    }

    /// The tile that has been picked up, drawn outside the `ScrollView`.
    ///
    /// This is what lets a tile be carried up to the workspace dots at all. A scroll
    /// view clips its content, so the tile that is still *in* the grid gets sliced
    /// off at the top edge and disappears while the pointer carries on into the bar.
    /// Drawn here it is clipped only by the panel itself, and since the grid is laid
    /// out after the bar it passes over it rather than under.
    ///
    /// The one in the grid stays put and turns invisible, so the layout underneath
    /// is undisturbed and every drop-index calculation still has a tile to measure.
    @ViewBuilder
    private var liftedTile: some View {
        // Both conditions, deliberately. The tile in the air is drawn outside the
        // grid's own layout, so nothing else would ever remove it from the screen —
        // if `lifted` were somehow left behind, it would simply hang there. Tying it
        // to the machine's own answer means a bubble can only be in the air while a
        // drag is genuinely in progress.
        if let cargo = flight.cargo, let centre = flight.centreInViewport, tileGesture.isDragging {
            BubbleTile(
                node: cargo.node,
                size: cargo.size,
                isEditing: false,
                isDragging: true,
                pressProgress: 0,
                onCommit: { _ in },
                onFinish: {},
                onRename: {}
            )
            // Over a dot the tile condenses, so the dot it is about to land on isn't
            // hidden underneath it — and so that "this is leaving" is visible before
            // it goes.
            .scaleEffect(isOverWorkspaceDot ? 0.5 : 1)
            .animation(Motion.lift, value: isOverWorkspaceDot)
            .position(x: centre.x, y: centre.y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Showing another board mid-drag

    /// The board whose tiles are on screen: the one being previewed, if any, or the
    /// one the store is actually on.
    private var shownWorkspace: Workspace {
        previewWorkspace.flatMap { id in store.workspaces.first { $0.id == id } }
            ?? store.currentWorkspace
    }

    /// What is drawn right now — used for the empty state, which would otherwise
    /// describe the board hiding behind the preview.
    private var shownNodes: [BubbleNode] {
        previewWorkspace == nil ? store.visible : shownWorkspace.notes
    }

    /// How far the real board is pushed aside to make room for the preview.
    private func boardOffset(width: CGFloat) -> CGFloat {
        previewWorkspace == nil ? 0 : -previewDirection * width
    }

    /// Which side of this board another one lives on, so it can arrive from there.
    private func direction(towards workspace: UUID) -> CGFloat {
        guard let target = store.workspaces.firstIndex(where: { $0.id == workspace }) else { return 1 }
        return target > store.currentIndex ? 1 : -1
    }

    @ViewBuilder
    private func previewLayer(layout: GridLayout) -> some View {
        if previewWorkspace != nil {
            WorkspacePreview(workspace: shownWorkspace, layout: layout)
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
    private var slide: AnyTransition {
        let forwards = store.switchDirection > 0
        return .asymmetric(
            insertion: .move(edge: forwards ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forwards ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var background: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { store.addBubble() }
            // A single click on open space finishes whatever is being typed — the
            // other half of "click away to finish".
            .onTapGesture { store.editingID = nil }
    }

    @ViewBuilder
    private var confirmation: some View {
        if let pendingPop {
            ConfirmPopSheet(
                node: pendingPop.node,
                onCancel: { withAnimation(Motion.overlay) { self.pendingPop = nil } },
                onConfirm: {
                    self.pendingPop = nil
                    commitPop(pendingPop.node, at: pendingPop.index, plan: pendingPop.plan)
                }
            )
        }
    }

    /// An empty level says what's missing and how to fix it, and nothing else.
    ///
    /// It used to also list "click to open · hold to pop · drag to rearrange",
    /// which describes things you do *to* bubbles — useless advice on a screen
    /// with no bubbles on it.
    private var emptyState: some View {
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

    private func tile(
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
        // While editing, the gesture is masked off so the text field owns the mouse.
        .gesture(
            gesture(for: node, index: index, plan: plan, layout: layout),
            including: isEditing ? .subviews : .all
        )
    }

    @ViewBuilder
    private func contextMenu(
        _ node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some View {
        Button("Open") { store.drillInto(node.id) }
        Button("Rename") { store.editingID = node.id }
        Button("Reset age to today") { store.touch(node.id) }
        Divider()
        Button("Pop", role: .destructive) { performPop(node, at: index, plan: plan) }
    }

    // MARK: - The one gesture

    /// Feeds the drag into `TileGesture` and carries out whatever it decides.
    ///
    /// There is deliberately no logic in here beyond translating between SwiftUI's
    /// callbacks and the machine's events — the rules about slop, holds and what a
    /// release means live in `TileGesture`, where they can be tested.
    private func gesture(
        for node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some Gesture {
        let context = Context(node: node, index: index, plan: plan, layout: layout)
        return DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                apply(tileGesture.handle(.changed(id: node.id, translation: value.translation)), context)
            }
            .onEnded { _ in
                apply(tileGesture.handle(.ended(id: node.id)), context)
            }
    }

    /// What an effect needs to know to be carried out: which tile, and where
    /// everything is this render.
    private struct Context {
        let node: BubbleNode
        let index: Int
        let plan: LayoutPlan
        let layout: GridLayout
    }

    private func apply(_ effects: [TileGesture.Effect], _ context: Context) {
        for effect in effects {
            switch effect {
            case .beginHold:
                beginHold(context)
            case .cancelHold:
                cancelHold()
            case .beginDrag:
                // A drag can wander past the panel edge; don't let that fold the
                // panel away mid-rearrange.
                panelState.blocksAutoCollapse = true
                // The dots up in the bar grow into drop targets for as long as the
                // tile is in hand.
                withAnimation(Motion.lift) { panelState.isDraggingTile = true }
                lift(context)
            case let .track(translation):
                track(translation, context)
            case .pop:
                performPop(context.node, at: context.index, plan: context.plan)
            case .enter:
                store.drillInto(context.node.id)
            case .drop:
                drop(context)
            case .finish:
                endPress()
            }
        }
    }

    /// Starts the pop countdown, and the swell that shows it filling up.
    private func beginHold(_ context: Context) {
        withAnimation(.easeIn(duration: Motion.popHoldSeconds)) { pressProgress = 1 }
        popTask = Task {
            try? await Task.sleep(for: Motion.popHold)
            guard !Task.isCancelled else { return }
            apply(tileGesture.handle(.holdElapsed(id: context.node.id)), context)
        }
    }

    /// Stops the countdown and unwinds the swell, leaving the press itself intact.
    private func cancelHold() {
        popTask?.cancel()
        popTask = nil
        withAnimation(Motion.overlay) { pressProgress = 0 }
    }

    // MARK: - Carrying a tile to another board

    /// Copies everything the tile in the air needs, so that nothing it depends on
    /// can change underneath it for the rest of the drag.
    private func lift(_ context: Context) {
        guard let offsets else { return }
        flight.lift(
            TileFlight.Cargo(
                node: context.node,
                size: context.plan.size(at: context.index),
                centre: context.plan.restingCentre(at: context.index),
                offsets: offsets
            )
        )
    }

    private func track(_ translation: CGSize, _ context: Context) {
        // Late arrival: the measurements the flight needs weren't in yet when the
        // drag began.
        if !flight.isCarrying { lift(context) }

        // `carry` answers whether the dot under the tile *changed*. The bar redraws
        // on that answer, so it must not be written once a frame.
        let targets = store.hasMultipleWorkspaces ? panelState.workspaceDropTargets : []
        if flight.carry(to: translation, over: targets) {
            withAnimation(Motion.hover) { panelState.hoveredWorkspace = flight.hoveredWorkspace }
            schedulePreview(of: flight.hoveredWorkspace)
        }

        // A tile on its way to another board is not being rearranged on this one:
        // clearing the drop index sends the other tiles back to their resting
        // places, which is the honest answer to "what happens if I let go here".
        //
        // The centre is measured from where the tile was picked up, not from where
        // its slot is now — the two differ the moment the board underneath reflows.
        let centre = flight.centreInContent
            ?? CGPoint(x: context.plan.restingCentre(at: context.index).x + translation.width,
                       y: context.plan.restingCentre(at: context.index).y + translation.height)
        dropIndex = flight.hoveredWorkspace == nil
            ? context.layout.index(at: centre, frames: context.plan.restingFrames)
            : nil
    }

    /// Whether the tile is poised over a dot at all — the moment it stops being a
    /// rearrange and becomes a question about which board it belongs on.
    private var isOverWorkspaceDot: Bool {
        flight.hoveredWorkspace != nil
    }

    /// Resting a tile on a workspace dot slides that board into view behind it.
    ///
    /// Nothing is committed by this — the note goes when you let go, and until then
    /// the preview can be changed for another board or abandoned altogether. The
    /// dwell is what makes it usable: without it, crossing one dot on the way to
    /// another would flick through every board in between.
    ///
    /// Hovering the dot of the board you are actually on takes the preview away
    /// again, which is how a drag is called off without leaving the bar.
    private func schedulePreview(of workspace: UUID?) {
        previewTask?.cancel()
        guard let workspace else { return }
        previewTask = Task {
            try? await Task.sleep(for: Motion.workspacePreview)
            guard !Task.isCancelled, flight.hoveredWorkspace == workspace else { return }
            let destination = workspace == store.currentWorkspaceID ? nil : workspace
            if let destination { previewDirection = direction(towards: destination) }
            withAnimation(Motion.reflow) { panelState.previewWorkspace = destination }
        }
    }

    /// Files the tile in hand onto the board being previewed.
    ///
    /// The store has been on the board the note came from all along — the preview is
    /// only a picture — so this is an ordinary move from the current board, and the
    /// undo it records returns to the level it was dragged from.
    ///
    /// The switch that follows is deliberately **not** animated: the boards already
    /// slid past each other when the preview opened, and the destination is already
    /// what is on screen. Animating here would slide the same board in a second time.
    private func file(to workspace: UUID) {
        guard let node = flight.node,
              let name = store.workspaces.first(where: { $0.id == workspace })?.displayName,
              store.move(node.id, toWorkspace: workspace)
        else { return }

        store.selectWorkspace(workspace)
        panelState.previewWorkspace = nil
        // No pop sound: nothing burst. You watched it land, so the toast is really
        // there to carry the undo.
        showToast("Moved “\(node.displayName)” to \(name)")
    }

    // MARK: - Letting go

    /// Clears everything a press owns **on screen** — the tile in the air, the drop
    /// target, the countdown, the bar's drag state — and leaves the gesture machine
    /// to say when the press itself is over.
    ///
    /// The split matters. Half of what ends a drag happens mid-press, with the mouse
    /// button still down: see `cancelDrag`.
    private func clearDragState() {
        cancelHold()
        previewTask?.cancel()
        previewTask = nil
        panelState.previewWorkspace = nil
        dropIndex = nil
        flight.land()
        offsets = nil
        withAnimation(Motion.lift) {
            panelState.isDraggingTile = false
            panelState.hoveredWorkspace = nil
        }
        panelState.blocksAutoCollapse = pendingPop != nil
    }

    /// Clears the press and the machine with it. Safe to call whether or not one is
    /// active.
    ///
    /// `reset()` rather than waiting for the release, because a pop *removes* the
    /// tile: there may be no `onEnded` coming for a view that no longer exists.
    private func endPress() {
        clearDragState()
        tileGesture.reset()
    }

    /// Takes the drag off the screen while leaving the press **consumed** rather
    /// than reset.
    ///
    /// For the two ways a drag can be decided while the button is still down: the
    /// tile is filed onto another board, or the board changes under it from
    /// somewhere else entirely. Resetting here instead is what froze a bubble on
    /// screen — the still-held button's next movement read as a fresh press, lifted
    /// a second tile out of a layout that had already been replaced, and never got a
    /// release because that view was on its way out. See `TileGesture.consume`.
    private func cancelDrag() {
        tileGesture.consume()
        clearDragState()
    }

    /// Lets a tile go.
    ///
    /// The destination is simply **the board you are looking at**. Hovering a dot
    /// has already swiped the panel there, so by the time you release, the board
    /// under the tile is the one it is going to — which is the whole point of
    /// swiping rather than captioning it. Releasing straight onto a dot without
    /// waiting for the swipe counts too, so an impatient drop isn't a dead one.
    /// Lets a tile go.
    ///
    /// The destination is **the board you can see** — the one you slid into view by
    /// resting the tile on its dot. Letting go straight onto a dot without waiting
    /// out the dwell counts as choosing it too, so an impatient drop is not a dead
    /// one.
    private func drop(_ context: Context) {
        previewTask?.cancel()
        let destination = flight.hoveredWorkspace ?? previewWorkspace

        if let destination, destination != store.currentWorkspaceID {
            file(to: destination)
        } else if previewWorkspace != nil {
            // Called off over the board it came from: put it back the way it came.
            withAnimation(Motion.reflow) { panelState.previewWorkspace = nil }
        } else if let dropIndex {
            store.move(context.node.id, to: dropIndex)
        }
    }

    // MARK: - Popping

    /// Entry point for every pop, from a hold or from the context menu. Tiles
    /// holding unpopped bubbles divert to a confirmation instead of bursting.
    private func performPop(_ node: BubbleNode, at index: Int, plan: LayoutPlan) {
        tileGesture.consume()

        guard node.children.isEmpty else {
            // `clearDragState`, not `endPress`: the tile is still there, waiting on an
            // answer, and the button that raised the question may still be down.
            // Resetting the press here would let the next twitch of it start another,
            // which would sit under the sheet counting down to pop the same tile
            // again.
            clearDragState()
            withAnimation(Motion.overlay) {
                pendingPop = PendingPop(node: node, index: index, plan: plan)
            }
            return
        }
        commitPop(node, at: index, plan: plan)
    }

    /// Actually bursts a tile: particles, sound, removal, and the undo offer.
    private func commitPop(_ node: BubbleNode, at index: Int, plan: LayoutPlan) {
        let size = plan.specs[index].size
        let burst = PopBurst(
            centre: plan.restingCentre(at: index),
            size: size,
            cornerRadius: TileStyle.cornerRadius(for: size),
            color: Aging.color(forDays: node.ageInDays)
        )

        bursts.append(burst)
        PopSounds.shared.play()
        store.pop(node.id)
        endPress()
        showToast("Popped “\(node.displayName)”")

        Task {
            try? await Task.sleep(for: Motion.burstLifetime)
            bursts.removeAll { $0.id == burst.id }
        }
    }

    // MARK: - Toast

    private func undo() {
        store.undo()
        dismissToast()
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(Motion.toast) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: Motion.toastLifetime)
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        withAnimation(Motion.overlay) { toast = nil }
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
