import AppKit
import Combine
import SwiftUI

/// Owns the overlay panel and the expanded ⇄ minimised transition.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: BubbleStore
    private let panelState = PanelState()
    private let panel: OverlayPanel
    private(set) var isMinimised = true

    // 432pt of width is exactly three grid slots plus padding (see GridLayout).
    private static let panelWidth: CGFloat = 432
    /// The glass bar plus its margins.
    private static let headerHeight: CGFloat = 58
    /// The bar's second row — workspace and breadcrumb — which is only there when
    /// there is something for it to say. `BubbleStore.showsPlaceRow` decides.
    private static let placeRowHeight: CGFloat = 34
    /// Enough for one row, so a nearly empty panel isn't a sliver.
    private static let minimumBodyHeight: CGFloat = 152
    /// Beyond this the grid scrolls rather than the panel swallowing the screen.
    private static let maximumBodyHeight: CGFloat = 560

    /// Grace period before an unhovered panel folds back to the pill. Long enough
    /// to cross a gap or overshoot an edge without the panel vanishing.
    private static let collapseDelay: Duration = .milliseconds(450)
    private var collapseTask: Task<Void, Never>?

    /// Dwell required before the pill opens, so merely sweeping the pointer across
    /// it on the way somewhere else doesn't throw the grid open.
    private static let expandDelay: Duration = .milliseconds(180)
    private var expandTask: Task<Void, Never>?

    private var storeObserver: AnyCancellable?
    private var dragObserver: AnyCancellable?
    private var menuBar: MenuBarItem?

    /// Whether the floating on-screen pill is shown when minimised. With a menu bar
    /// icon there are two ways in, so this can be turned off for a tidier screen —
    /// the panel then hides completely instead of leaving the pill behind.
    private static let pillDefaultsKey = "ShowsFloatingPill"
    private var showsFloatingPill: Bool {
        didSet { UserDefaults.standard.set(showsFloatingPill, forKey: Self.pillDefaultsKey) }
    }

    /// Where the panel sits and what frame it takes at any size. Everything
    /// positional goes through it — see `PanelParking`.
    private let parking = PanelParking()

    init(store: BubbleStore) {
        self.store = store
        // Defaults to on so nothing disappears for anyone who had no menu bar icon.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.pillDefaultsKey) == nil {
            defaults.set(true, forKey: Self.pillDefaultsKey)
        }
        self.showsFloatingPill = defaults.bool(forKey: Self.pillDefaultsKey)

        // Resting state is the pill, so the widget starts out of the way and the
        // grid appears only when reached for — back where it was last left, which
        // for a widget you have parked in a particular corner is the whole point.
        self.panel = OverlayPanel(contentRect: parking.frame(sized: MinimisedPill.size))
        super.init()

        // The pill may have been clamped onto a screen that has since changed shape,
        // in which case where it actually landed is now where it lives.
        parking.park(settledPill: panel.frame)

        panel.delegate = self
        show(pillView, sized: MinimisedPill.size)
        panel.alphaValue = Self.idleAlpha
        if showsFloatingPill { panel.orderFrontRegardless() }

        menuBar = MenuBarItem(
            store: store,
            onToggle: { [weak self] in self?.toggleFromMenuBar() },
            showsPill: { [weak self] in self?.showsFloatingPill ?? true },
            onTogglePill: { [weak self] in self?.toggleFloatingPill() },
            onSelectWorkspace: { [weak self] index in self?.showWorkspace(at: index) },
            onNewWorkspace: { [weak self] in self?.newWorkspace() }
        )

        // The panel is only as tall as its contents need, so adding or popping a
        // bubble resizes it. `objectWillChange` fires *before* the mutation lands,
        // hence the hop to the next turn of the run loop to read the new state.
        storeObserver = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.fitToContent() }
        }

        // A tile landing is the other moment the panel may owe itself a resize: the
        // board may have changed under it while the fitting above was held off.
        dragObserver = panelState.$isDraggingTile
            .removeDuplicates()
            .sink { [weak self] isDragging in
                guard !isDragging else { return }
                Task { @MainActor in self?.fitToContent() }
            }

        installSwipeMonitor()
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    // MARK: - Swiping between workspaces

    private var scrollMonitor: Any?
    private var swipe = WorkspaceSwipe()

    /// Two-finger swipes arrive as scroll events, and they have to be intercepted
    /// *before* the grid's `ScrollView` sees them — hence a local monitor rather
    /// than a SwiftUI gesture, which would be layered underneath it.
    ///
    /// A local monitor is also the only way to be selective: returning the event
    /// passes it through untouched, so vertical scrolling still scrolls the grid,
    /// and only the one event that completes a horizontal swipe is swallowed.
    private func installSwipeMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Scrolls anywhere else in the app — there is nowhere else, but a
            // monitor sees everything the app receives — are none of our business.
            guard event.window?.delegate === self else { return event }

            let scroll = WorkspaceSwipe.Scroll(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                isGestureStart: event.phase == .began,
                isInverted: event.isDirectionInvertedFromDevice,
                time: event.timestamp
            )
            // Monitors are delivered on the main thread; this is the same bridge
            // `main.swift` uses to say so. Only the plain values above cross into
            // it, so there is nothing here for concurrency checking to object to.
            let consumed = MainActor.assumeIsolated { self?.consumeSwipe(scroll) ?? false }
            return consumed ? nil : event
        }
    }

    /// Whether this scroll turned out to be a workspace swipe.
    private func consumeSwipe(_ scroll: WorkspaceSwipe.Scroll) -> Bool {
        // Nothing to swipe between, or nothing to swipe on.
        guard !isMinimised, store.hasMultipleWorkspaces else { return false }
        // Mid-drag or mid-confirmation, the panel is spoken for — the same flag the
        // auto-collapse checks, and for the same reason.
        guard !panelState.blocksAutoCollapse else { return false }

        switch swipe.handle(scroll) {
        case .none:
            return false
        case .next:
            return withAnimation(Motion.reflow) { store.goToNextWorkspace() }
        case .previous:
            return withAnimation(Motion.reflow) { store.goToPreviousWorkspace() }
        }
    }

    // MARK: - Workspace commands

    /// ⌘⇧N, and the menu bar's "New workspace".
    func newWorkspace() {
        if isMinimised { expand() }
        withAnimation(Motion.reflow) { _ = store.addWorkspace() }
    }

    /// ⌘→ and ⌘←.
    func nextWorkspace() {
        withAnimation(Motion.reflow) { _ = store.goToNextWorkspace() }
    }

    func previousWorkspace() {
        withAnimation(Motion.reflow) { _ = store.goToPreviousWorkspace() }
    }

    /// Picking a board from the menu bar opens it, rather than switching one you
    /// cannot see.
    private func showWorkspace(at index: Int) {
        withAnimation(Motion.reflow) { store.selectWorkspace(at: index) }
        expand(takeFocus: true)
        fade(to: 1.0, quickly: true)
    }

    /// Height the expanded panel wants for the notes currently on screen. Tiles are
    /// packed by size, so this has to measure them rather than count rows.
    private var expandedSize: NSSize {
        let layout = GridLayout(availableWidth: Self.panelWidth)
        let specs = store.visible.map { TileSizeCache.spec(for: $0, in: layout) }
        let body = layout.contentHeight(for: specs)
        let clamped = min(max(body, Self.minimumBodyHeight), Self.maximumBodyHeight)
        let chrome = Self.headerHeight + (store.showsPlaceRow ? Self.placeRowHeight : 0)
        return NSSize(width: Self.panelWidth, height: chrome + clamped)
    }

    private func fitToContent() {
        guard !isMinimised else { return }
        // Not while a tile is in the air. Hovering a workspace dot swipes to that
        // board mid-drag, and boards differ wildly in height — resizing then would
        // move the window (and with it the dots being aimed at) out from under the
        // drag. It settles as soon as the tile lands; see the subscription below.
        guard !panelState.isDraggingTile else { return }
        let target = expandedSize
        guard abs(panel.frame.height - target.height) > 0.5 else { return }
        resize(to: target, animated: true)
    }

    // MARK: - Moving the panel

    /// Where the panel and the pointer were when the current drag started, both in
    /// screen coordinates.
    private var dragAnchor: (window: NSPoint, mouse: NSPoint)?

    /// Dragging is driven by a SwiftUI `DragGesture` on the status handle, but the
    /// movement is computed here from `NSEvent.mouseLocation`.
    ///
    /// **Do not use the gesture's `translation`.** It is measured in the window's
    /// own coordinate space, and this gesture moves that window: the pointer keeps
    /// roughly the same window-relative position, translation collapses towards
    /// zero, and the panel never moves. Screen coordinates are unaffected by the
    /// window moving underneath them.
    ///
    /// AppKit's `performDrag` was tried twice before this and is not the answer
    /// either — it needs the mouse-down to reach an `NSView` buried behind SwiftUI
    /// content, which kept breaking on layering and first-mouse.
    func beginPanelDrag() {
        dragAnchor = (window: panel.frame.origin, mouse: NSEvent.mouseLocation)
        // A drag can wander anywhere; don't let leaving the panel fold it away.
        panelState.blocksAutoCollapse = true
        collapseTask?.cancel()
    }

    /// Snapping is applied live rather than on release, so the panel visibly jumps
    /// flush and you can see it has taken. The position is recomputed from the
    /// drag's start each time, so a snap never accumulates into a drift.
    func dragPanel() {
        guard let start = dragAnchor else { return }
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin = NSPoint(
            x: start.window.x + (mouse.x - start.mouse.x),
            y: start.window.y + (mouse.y - start.mouse.y)
        )
        panel.setFrameOrigin(parking.snapping(frame).origin)
    }

    func endPanelDrag() {
        dragAnchor = nil
        panelState.blocksAutoCollapse = false
        // Where it was dropped decides where the pill now rests and which way the
        // panel opens from it. This handle is the bar, so an expanded panel parks by
        // its top edge — see `PanelPlacement.init(draggedPanel:in:)`.
        if isMinimised {
            parking.park(pill: panel.frame)
        } else {
            parking.park(draggedPanel: panel.frame)
        }
    }

    /// The end of a `performDrag` on the minimised pill.
    ///
    /// That path is AppKit's, not SwiftUI's — it moves the window from inside its
    /// own tracking loop, so there is nowhere to apply magnetism *during* the drag
    /// without fighting it. Snapping on release instead, animated, still reads as
    /// the edge pulling the pill in.
    ///
    /// A plain click arrives here too, so a move has to be proved before the anchor
    /// is re-read. That click may well have *expanded* the panel, and resolving an
    /// anchor from the expanded frame flips which corner the panel is parked in:
    /// a pill near the middle reads as right-anchored, the panel it opens into
    /// reaches further left and so reads as left-anchored, and minimising would
    /// then fling the pill several hundred points across the screen.
    func windowDragEnded(from start: NSRect) {
        guard isMinimised, panel.frame.size == start.size, panel.frame.origin != start.origin
        else { return }

        let snapped = parking.snapping(panel.frame)
        if snapped != panel.frame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(snapped, display: true)
            }
        }
        // Read from `snapped`, not `panel.frame`: the animator above hasn't landed.
        parking.park(pill: snapped)
    }

    /// Hides the panel, leaving the menu bar icon behind to bring it back.
    ///
    /// Deliberately *not* `NSApp.terminate`: closing the window should not end the
    /// app, or there is no way back short of relaunching it from Finder.
    func close() {
        collapseTask?.cancel()
        expandTask?.cancel()
        isMinimised = true
        isPinned = false
        store.editingID = nil
        store.renamingWorkspaceID = nil
        swipe.reset()
        show(pillView, sized: MinimisedPill.size)
        parking.park(settledPill: panel.frame)
        panel.orderOut(nil)
    }

    /// ⌘Z. Lives here because the panel routes key events to the controller.
    func undo() {
        guard !isMinimised else { return }
        store.undo()
    }

    // MARK: - Presentation

    /// Only the resting pill dims — it is pure chrome. The expanded panel stays at
    /// full alpha because window alpha fades *everything*, and the tiles are
    /// supposed to read as solid objects over your work.
    private static let idleAlpha: CGFloat = 0.55
    private var isPinned = false

    private var expandedView: RootView {
        RootView(
            store: store,
            panelState: panelState,
            onClose: { [weak self] in self?.close() },
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) },
            isPinned: isPinned,
            onTogglePin: { [weak self] in self?.togglePin() },
            drag: PanelDrag(
                began: { [weak self] in self?.beginPanelDrag() },
                changed: { [weak self] in self?.dragPanel() },
                ended: { [weak self] in self?.endPanelDrag() }
            )
        )
    }

    private var pillView: MinimisedPill {
        MinimisedPill(
            store: store,
            onExpand: { [weak self] in self?.expand() },
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) }
        )
    }

    /// Swaps what the panel shows and what size it is, in that order — **resize
    /// first, then install the view.**
    ///
    /// The order is the whole point of this method existing. Installing the view
    /// first laid it out at the size the panel *was*: opening from the pill, the
    /// grid measured 132pt of width, decided that was one column, and stacked every
    /// tile vertically. The window then jumped to 432pt and the tiles animated out
    /// of that column into their real slots — a visible cascade on every open.
    ///
    /// It was worst opening from the right-hand edge of the screen, because there
    /// the window's origin moves too: the tiles started 300pt to the right of where
    /// they belonged and had to travel the whole way back. Opening from the left,
    /// the origin stays put and only the fan-out showed, which is why the same bug
    /// looked like it only happened on one side.
    ///
    /// `display: false` keeps the resized window from drawing its old contents; the
    /// incoming view is laid out once, at its final size, and drawn once.
    private func show(_ view: some View, sized size: NSSize) {
        // The outgoing view takes its @State with it, including anything it knew
        // about a drag in progress. What survives is `panelState`, so it is cleared
        // here rather than left describing a tile that no longer exists.
        panelState.endTileDrag()
        panel.setFrame(parking.frame(sized: size), display: false)
        panel.contentView = FirstMouseHostingView(rootView: view)
        panel.displayIfNeeded()
    }

    /// The whole interaction model: the pill expands under the pointer and folds
    /// back once it leaves.
    private func setHovering(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
        }

        // Expanded is always fully opaque; only the pill fades when unattended.
        let solid = !isMinimised || hovering || isPinned || store.isEditing
        fade(to: solid ? 1.0 : Self.idleAlpha, quickly: hovering)

        if hovering {
            if isMinimised { scheduleExpand() }
        } else {
            expandTask?.cancel()
            expandTask = nil
            scheduleCollapse()
        }
    }

    private func scheduleExpand() {
        expandTask?.cancel()
        expandTask = Task { [weak self] in
            try? await Task.sleep(for: Self.expandDelay)
            guard !Task.isCancelled, let self, self.isMinimised else { return }
            // Hover must not make the panel key — that would divert your typing
            // from whatever app you are actually working in. Only a click or an
            // explicit command takes focus.
            self.expand(takeFocus: false)
        }
    }

    /// Fades the whole window rather than tinting the views, so material, tiles
    /// and shadows all fade together.
    private func fade(to target: CGFloat, quickly: Bool) {
        guard abs(panel.alphaValue - target) > 0.001 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = quickly ? 0.12 : 0.3
            panel.animator().alphaValue = target
        }
    }

    private func scheduleCollapse() {
        guard !isMinimised, !isPinned else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.collapseDelay)
            guard !Task.isCancelled, let self else { return }
            // Re-check at fire time: any of these may have become true while waiting.
            guard !self.isPinned,
                  !self.store.isEditing,
                  !self.panelState.blocksAutoCollapse
            else { return }
            self.minimise()
        }
    }

    /// Pinned means "stay open" — for when you are actually working in the panel
    /// rather than glancing at it.
    private func togglePin() {
        isPinned.toggle()
        collapseTask?.cancel()
        show(expandedView, sized: expandedSize)
        fade(to: 1.0, quickly: true)
    }

    func minimise() {
        guard !isMinimised else { return }
        collapseTask?.cancel()
        expandTask?.cancel()
        isMinimised = true
        isPinned = false
        store.editingID = nil
        store.renamingWorkspaceID = nil
        // A swipe left half-finished when the panel folded away must not be picked
        // up by the next one.
        swipe.reset()
        show(pillView, sized: MinimisedPill.size)
        // The resting spot is the one worth remembering across a quit.
        parking.park(settledPill: panel.frame)
        // With the pill turned off, minimising hides the panel outright — the menu
        // bar icon is then the only way back in, which is the point of the setting.
        if showsFloatingPill {
            fade(to: Self.idleAlpha, quickly: false)
        } else {
            panel.orderOut(nil)
        }
    }

    /// `takeFocus` is false for hover-expansion and true when the user asked for
    /// the panel outright — keyboard focus should follow intent, not the pointer.
    func expand(takeFocus: Bool = true) {
        guard isMinimised else {
            if takeFocus { panel.makeKeyAndOrderFront(nil) }
            return
        }
        collapseTask?.cancel()
        expandTask?.cancel()
        isMinimised = false
        show(expandedView, sized: expandedSize)
        if takeFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Menu bar

    /// Clicking the menu bar icon. Reopens the panel **where it was last left**,
    /// including across a quit — a widget you have parked in a particular corner
    /// should stay there, and being relocated on every open is the more surprising
    /// behaviour by far.
    ///
    /// The icon is only a fallback, for when that spot is gone: a display unplugged
    /// since, which would otherwise strand the panel somewhere unreachable.
    private func toggleFromMenuBar() {
        if isMinimised {
            if !parking.isOnScreen(panel.frame), let icon = menuBar?.screenFrame {
                moveBelow(icon)
            }
            expand(takeFocus: true)
            fade(to: 1.0, quickly: true)
        } else {
            minimise()
        }
    }

    private func toggleFloatingPill() {
        showsFloatingPill.toggle()
        guard isMinimised else { return }
        if showsFloatingPill {
            panel.orderFrontRegardless()
            fade(to: Self.idleAlpha, quickly: false)
        } else {
            panel.orderOut(nil)
        }
    }

    /// Parks the panel just below a menu bar item, ready to be expanded.
    ///
    /// The **pill** is parked here, not the expanded panel: the panel grows from the
    /// pill's corner, and parking resolves that corner from where this lands — under
    /// an icon on the right of the menu bar the panel will open leftwards, on the
    /// left it opens rightwards, and either way downwards from the top edge.
    private func moveBelow(_ icon: NSRect) {
        let frame = parking.clamped(
            NSRect(
                x: icon.midX - MinimisedPill.size.width / 2,
                y: icon.minY - 6 - MinimisedPill.size.height,
                width: MinimisedPill.size.width,
                height: MinimisedPill.size.height
            )
        )
        panel.setFrame(frame, display: false)
        parking.park(pill: frame)
    }

    /// Global-hotkey entry point: open it for real (focus and all), or fold it away.
    func toggleVisible() {
        if isMinimised {
            expand(takeFocus: true)
            fade(to: 1.0, quickly: true)
        } else {
            minimise()
        }
    }

    func newBubble() {
        if isMinimised { expand() }
        store.addBubble()
    }

    /// Escape backs out one level, or minimises when already at the top.
    func escape() {
        if store.renamingWorkspaceID != nil {
            store.renamingWorkspaceID = nil
        } else if store.editingID != nil {
            store.editingID = nil
        } else if !store.isAtRoot {
            store.goUp()
        } else {
            minimise()
        }
    }

    /// Gives the panel a new size. Where that size lands is `PanelParking`'s
    /// business — every frame hangs off the parked corner, so collapsing doesn't
    /// make the panel leap across the screen and expanding grows *into* it.
    private func resize(to size: NSSize, animated: Bool = false) {
        let frame = parking.frame(sized: size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true, animate: false)
        }
    }
}
