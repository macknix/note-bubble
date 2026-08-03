import SwiftUI

/// The tile grid. Tiles sit on fixed slots derived from their order in the model,
/// and dragging one reflows the rest around it exactly like rearranging apps.
///
/// Tap, long-press and drag are all served by a *single* `DragGesture` with
/// `minimumDistance: 0`. SwiftUI cannot reliably arbitrate three overlapping
/// gestures on one view, so the discrimination is done by hand in `gesture(for:)`:
/// movement past a threshold means rearrange, holding still to the deadline means
/// pop, and releasing before either means enter.
struct BubbleGrid: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject var panelState: PanelState

    /// Movement past this many points is a rearrange, not a press.
    private static let dragSlop: CGFloat = 6
    private static let coordinateSpace = "bubble-grid"

    // MARK: - Interaction state

    /// The press in progress, if any.
    private struct Press {
        let id: UUID
        var isDragging = false
        /// Set the instant a hold decides to pop. The release that follows must not
        /// also be read as a click — cancelling the timer cannot stop a task that
        /// has already begun, so the decision is recorded rather than raced.
        var consumedByHold = false
    }

    /// A pop held back pending confirmation, because the tile has notes inside it.
    private struct PendingPop {
        let node: BubbleNode
        let index: Int
        let plan: LayoutPlan
    }

    @State private var press: Press?
    @State private var pressProgress: CGFloat = 0
    @State private var dragTranslation: CGSize = .zero
    @State private var dropIndex: Int?
    @State private var popTask: Task<Void, Never>?

    @State private var bursts: [PopBurst] = []
    @State private var pendingPop: PendingPop?
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let nodes = store.visible
            let layout = GridLayout(availableWidth: geometry.size.width)
            // All of this is computed once per render rather than per tile. During a
            // drag every tile needs the hypothetical order and the frames that fall
            // out of it; deriving them inside the loop made reflow O(n²) per frame.
            let plan = layoutPlan(for: nodes, layout: layout)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    background

                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        tile(node, index: index, plan: plan, layout: layout)
                    }

                    ForEach(bursts) { $0 }
                }
                .frame(
                    width: geometry.size.width,
                    height: max(plan.contentHeight, geometry.size.height),
                    alignment: .topLeading
                )
                .coordinateSpace(name: Self.coordinateSpace)
            }
            .scrollDisabled(press?.isDragging == true)
            .overlay { if nodes.isEmpty && pendingPop == nil { emptyState } }
            .overlay(alignment: .bottom) { if let toast { UndoToast(message: toast, onUndo: undo) } }
            .overlay { confirmation }
            // An open confirmation must survive the pointer leaving the panel.
            .onChange(of: pendingPop != nil) { _, isOpen in
                panelState.blocksAutoCollapse = isOpen
            }
        }
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
        let isDragging = press?.id == node.id && press?.isDragging == true
        let isEditing = store.editingID == node.id
        let size = plan.specs[index].size

        // The dragged tile hangs off the cursor from where it started; every other
        // tile sits wherever the reflow has landed it.
        let anchor = isDragging ? plan.restingCentre(at: index) : plan.centre(of: node.id, at: index)
        let position = isDragging
            ? CGPoint(x: anchor.x + dragTranslation.width, y: anchor.y + dragTranslation.height)
            : anchor

        return BubbleTile(
            node: node,
            size: size,
            isEditing: isEditing,
            isDragging: isDragging,
            pressProgress: press?.id == node.id ? pressProgress : 0,
            onCommit: { store.updateText($0, for: node.id) },
            onFinish: { store.editingID = nil },
            onRename: { store.editingID = node.id }
        )
        .position(position)
        .zIndex(isDragging ? 10 : (isEditing ? 5 : 0))
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

    /// Everything positional for one render: tile sizes, where each tile rests
    /// undisturbed, and where it sits under the current drag.
    private struct LayoutPlan {
        let specs: [GridLayout.TileSpec]
        /// Frames in the model's own order — the drag anchor, and what drop targets
        /// are measured against.
        let restingFrames: [CGRect]
        /// Centres under the live reflow, keyed by note. Empty when nothing is
        /// being dragged, in which case the resting frame is the answer.
        let reflowedCentres: [UUID: CGPoint]
        let contentHeight: CGFloat

        func restingCentre(at index: Int) -> CGPoint {
            let frame = restingFrames[index]
            return CGPoint(x: frame.midX, y: frame.midY)
        }

        func centre(of id: UUID, at index: Int) -> CGPoint {
            reflowedCentres[id] ?? restingCentre(at: index)
        }
    }

    private func layoutPlan(for nodes: [BubbleNode], layout: GridLayout) -> LayoutPlan {
        let specs = nodes.map { TileSizeCache.spec(for: $0, in: layout) }
        let resting = layout.frames(for: specs)

        var reflowed: [UUID: CGPoint] = [:]
        if let press, press.isDragging, let dropIndex {
            let ids = nodes.map(\.id)
            let order = ids.reordered(moving: press.id, to: dropIndex)
            let specByID = Dictionary(uniqueKeysWithValues: zip(ids, specs))
            let reordered = order.compactMap { specByID[$0] }
            let frames = layout.frames(for: reordered)
            for (position, id) in order.enumerated() where position < frames.count {
                reflowed[id] = CGPoint(x: frames[position].midX, y: frames[position].midY)
            }
        }

        return LayoutPlan(
            specs: specs,
            restingFrames: resting,
            reflowedCentres: reflowed,
            contentHeight: layout.contentHeight(for: specs)
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

    private func gesture(
        for node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if press == nil { beginPress(node, at: index, plan: plan) }
                guard var current = press, current.id == node.id else { return }

                let moved = hypot(value.translation.width, value.translation.height)
                if !current.isDragging && moved > Self.dragSlop {
                    // Turned out to be a rearrange, so the pop countdown is off.
                    cancelHold()
                    current.isDragging = true
                    press = current
                    // A drag can wander past the panel edge; don't let that fold
                    // the panel away mid-rearrange.
                    panelState.blocksAutoCollapse = true
                }

                guard current.isDragging else { return }
                dragTranslation = value.translation
                let anchor = plan.restingCentre(at: index)
                let centre = CGPoint(
                    x: anchor.x + value.translation.width,
                    y: anchor.y + value.translation.height
                )
                dropIndex = layout.index(at: centre, frames: plan.restingFrames)
            }
            .onEnded { _ in
                defer { endPress() }
                cancelHold()
                guard let current = press, current.id == node.id else { return }
                // The hold already decided this tile's fate; releasing must not
                // then also open it.
                guard !current.consumedByHold else { return }

                if current.isDragging {
                    if let dropIndex { store.move(node.id, to: dropIndex) }
                } else {
                    store.drillInto(node.id)
                }
            }
    }

    private func beginPress(_ node: BubbleNode, at index: Int, plan: LayoutPlan) {
        press = Press(id: node.id)
        // The swell that shows the tile filling up towards a burst.
        withAnimation(.easeIn(duration: Motion.popHoldSeconds)) { pressProgress = 1 }
        popTask = Task {
            try? await Task.sleep(for: Motion.popHold)
            guard !Task.isCancelled else { return }
            performPop(node, at: index, plan: plan)
        }
    }

    /// Stops the countdown and unwinds the swell, leaving the press itself intact.
    private func cancelHold() {
        popTask?.cancel()
        popTask = nil
        withAnimation(Motion.overlay) { pressProgress = 0 }
    }

    /// Clears everything a press owns. Safe to call whether or not one is active.
    private func endPress() {
        cancelHold()
        press = nil
        dropIndex = nil
        dragTranslation = .zero
        panelState.blocksAutoCollapse = pendingPop != nil
    }

    // MARK: - Popping

    /// Entry point for every pop, from a hold or from the context menu. Tiles
    /// holding unpopped bubbles divert to a confirmation instead of bursting.
    private func performPop(_ node: BubbleNode, at index: Int, plan: LayoutPlan) {
        press?.consumedByHold = true

        guard node.children.isEmpty else {
            endPress()
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
