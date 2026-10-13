import SwiftUI

// Carrying a tile: the one gesture that serves tap, hold and drag, the tile in the
// air, and letting it go — onto a slot on this board or onto another board's dot.
// What kind of press it is is `TileGesture`'s decision; where the tile has got to
// is `TileFlight`'s; what a dwell on a dot shows is `PreviewDwell`'s. This is the
// plumbing that feeds them and carries out what they say.

extension BubbleGrid {
    /// Reports where the scrolled content sits, but only while it matters — see
    /// `offsets`. One reader, two spaces: the same origin is needed in both.
    ///
    /// Tracked from the moment a tile is *pressed*, not from the moment a drag is
    /// recognised, so the answer has already arrived by the time it is needed. A
    /// drag begins several points into a press, and a preference published on the
    /// same render it is read on is a render too late.
    var contentOriginReader: some View {
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
    var liftedTile: some View {
        // Both conditions, deliberately. The tile in the air is drawn outside the
        // grid's own layout, so nothing else would ever remove it from the screen —
        // if `lifted` were somehow left behind, it would simply hang there. Tying it
        // to the machine's own answer means a bubble can only be in the air while a
        // drag is genuinely in progress.
        if let cargo = flight.cargo, let centre = flight.centreInViewport, tileGesture.isDragging {
            TileFace(node: cargo.node, size: cargo.size, now: store.now, isDragging: true)
            // Over a dot the tile condenses, so the dot it is about to land on isn't
            // hidden underneath it — and so that "this is leaving" is visible before
            // it goes.
            .scaleEffect(isOverWorkspaceDot ? 0.5 : 1)
            .animation(Motion.lift, value: isOverWorkspaceDot)
            .position(x: centre.x, y: centre.y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - The one gesture

    /// Feeds the drag into `TileGesture` and carries out whatever it decides.
    ///
    /// There is deliberately no logic in here beyond translating between SwiftUI's
    /// callbacks and the machine's events — the rules about slop, holds and what a
    /// release means live in `TileGesture`, where they can be tested.
    func gesture(
        for node: BubbleNode,
        index: Int,
        plan: LayoutPlan,
        layout: GridLayout
    ) -> some Gesture {
        let context = Context(node: node, index: index, plan: plan, layout: layout)
        return DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                apply(tileGesture.handle(.changed(id: node.id, translation: value.translation)), context)
                watchForShake(value, context)
            }
            .onEnded { _ in
                apply(tileGesture.handle(.ended(id: node.id)), context)
            }
    }

    /// Shaking a tile while carrying it resets its age to today, and it settles back
    /// into its slot. Only while it is genuinely being dragged, and not while it is
    /// over a workspace dot, where the same waggle means aiming at a board.
    func watchForShake(_ value: DragGesture.Value, _ context: Context) {
        guard tileGesture.isDragging(context.node.id), flight.hoveredWorkspace == nil else { return }
        let time = value.time.timeIntervalSinceReferenceDate
        guard shake.track(CGPoint(x: value.translation.width, y: value.translation.height), at: time)
        else { return }

        withAnimation(Motion.resize) { store.touch(context.node.id) }
        // A felt click on a Force Touch trackpad, so you know it took.
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        // Consumed, not reset: the button is still down, and its next twitch must
        // not lift the tile again. See `cancelDrag`.
        withAnimation(Motion.reflow) { cancelDrag() }
    }

    /// What an effect needs to know to be carried out: which tile, and where
    /// everything is this render.
    struct Context {
        let node: BubbleNode
        let index: Int
        let plan: LayoutPlan
        let layout: GridLayout
    }

    func apply(_ effects: [TileGesture.Effect], _ context: Context) {
        for effect in effects {
            switch effect {
            case .beginHold:
                beginHold(context)
            case .cancelHold:
                cancelHold()
            case .beginDrag:
                // A drag can wander past the panel edge; don't let that fold the
                // panel away mid-rearrange.
                panelState.setHold(.tileDrag, true)
                // The dots up in the bar grow into drop targets for as long as the
                // tile is in hand.
                withAnimation(Motion.lift) { panelState.isDraggingTile = true }
                lift(context)
            case let .track(translation):
                track(translation, context)
            case .pop:
                performPop(context.node, at: context.index, plan: context.plan, layout: context.layout)
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
    func beginHold(_ context: Context) {
        withAnimation(.easeIn(duration: Motion.popHold.seconds)) { pressProgress = 1 }
        popTask = Task {
            try? await Task.sleep(for: Motion.popHold)
            guard !Task.isCancelled else { return }
            apply(tileGesture.handle(.holdElapsed(id: context.node.id)), context)
        }
    }

    /// Stops the countdown and unwinds the swell, leaving the press itself intact.
    func cancelHold() {
        popTask?.cancel()
        popTask = nil
        withAnimation(Motion.overlay) { pressProgress = 0 }
    }

    // MARK: - Carrying a tile to another board

    /// Copies everything the tile in the air needs, so that nothing it depends on
    /// can change underneath it for the rest of the drag.
    func lift(_ context: Context) {
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

    func track(_ translation: CGSize, _ context: Context) {
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
        let resting = context.plan.restingCentre(at: context.index)
        let centre = flight.centreInContent
            ?? CGPoint(x: resting.x + translation.width, y: resting.y + translation.height)
        dropIndex = flight.hoveredWorkspace == nil
            ? context.layout.index(at: centre, frames: context.plan.restingFrames)
            : nil
    }

    /// Whether the tile is poised over a dot at all — the moment it stops being a
    /// rearrange and becomes a question about which board it belongs on.
    var isOverWorkspaceDot: Bool {
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
    func schedulePreview(of workspace: UUID?) {
        previewTask?.cancel()
        guard let workspace else { return }
        previewTask = Task {
            try? await Task.sleep(for: Motion.workspacePreview)
            guard !Task.isCancelled,
                  let outcome = PreviewDwell.outcome(
                      dwelledOn: workspace,
                      stillOver: flight.hoveredWorkspace,
                      current: store.currentWorkspaceID,
                      boards: store.workspaces.map(\.id)
                  )
            else { return }
            switch outcome {
            case let .show(destination, direction):
                previewDirection = CGFloat(direction)
                withAnimation(Motion.reflow) { panelState.previewWorkspace = destination }
            case .clear:
                withAnimation(Motion.reflow) { panelState.previewWorkspace = nil }
            }
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
    func file(to workspace: UUID) {
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
    func clearDragState() {
        shake.reset()
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
        panelState.setHold(.tileDrag, false)
    }

    /// Clears the press and the machine with it. Safe to call whether or not one is
    /// active.
    ///
    /// `reset()` rather than waiting for the release, because a pop *removes* the
    /// tile: there may be no `onEnded` coming for a view that no longer exists.
    func endPress() {
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
    func cancelDrag() {
        tileGesture.consume()
        clearDragState()
    }

    /// Lets a tile go.
    ///
    /// The destination is **the board you can see** — the one you slid into view by
    /// resting the tile on its dot. Letting go straight onto a dot without waiting
    /// out the dwell counts as choosing it too, so an impatient drop is not a dead
    /// one.
    func drop(_ context: Context) {
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
}
