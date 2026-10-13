import AppKit
import Combine
import SwiftUI

/// Owns the overlay panel and the expanded ⇄ minimised transition.
@MainActor
final class PanelController: NSObject, NSWindowDelegate, PanelCommands, MenuBarActions {
    private let store: BubbleStore
    private let panelState = PanelState()
    private let panel: OverlayPanel
    private(set) var isMinimised = true

    // 432pt gives four columns at `GridLayout.preferredColumnWidth`, with padding.
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

    /// The two delays `HoverIntent` asks for. Each is cancelled by the other.
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?

    private var storeObserver: AnyCancellable?
    private var dragObserver: AnyCancellable?
    private var menuBar: MenuBarItem?

    /// Whether the floating on-screen pill is shown when minimised. With a menu bar
    /// icon there are two ways in, so this can be turned off for a tidier screen —
    /// the panel then hides completely instead of leaving the pill behind.
    private static let pillDefaultsKey = "ShowsFloatingPill"
    private(set) var showsFloatingPill: Bool {
        didSet { UserDefaults.standard.set(showsFloatingPill, forKey: Self.pillDefaultsKey) }
    }

    /// Where the panel sits and what frame it takes at any size. Everything
    /// positional goes through it — see `PanelParking`.
    private let parking = PanelParking()

    let shortcut: GlobalShortcut

    init(store: BubbleStore, shortcut: GlobalShortcut) {
        self.store = store
        self.shortcut = shortcut
        // Defaults to on so nothing disappears for anyone who had no menu bar icon.
        UserDefaults.standard.register(defaults: [Self.pillDefaultsKey: true])
        self.showsFloatingPill = UserDefaults.standard.bool(forKey: Self.pillDefaultsKey)

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

        panel.commands = self
        menuBar = MenuBarItem(store: store, actions: self)

        // The panel is only as tall as its contents need, so adding or popping a
        // bubble resizes it. `objectWillChange` fires *before* the mutation lands,
        // so the fit has to wait for the next turn of the run loop to read the new
        // state. A one-frame debounce does that and also coalesces bursts — typing,
        // undo — into one fit instead of a new `Task` per change.
        storeObserver = store.objectWillChange
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.fitToContent() }
            }

        // A tile landing is the other moment the panel may owe itself a resize: the
        // board may have changed under it while the fitting above was held off.
        dragObserver = panelState.$isDraggingTile
            .removeDuplicates()
            .sink { [weak self] isDragging in
                guard !isDragging else { return }
                Task { @MainActor in self?.fitToContent() }
            }

        swipeMonitor = SwipeMonitor(
            window: panel,
            // Nothing to swipe between or on, or the panel is spoken for mid-drag
            // or mid-confirmation — the same holds the auto-collapse respects.
            isEnabled: { [weak self] in
                guard let self else { return false }
                return !self.isMinimised && self.store.hasMultipleWorkspaces && !self.panelState.blocksAutoCollapse
            },
            onSwipe: { [weak self] decision in self?.carryOut(decision) ?? false }
        )
    }

    // MARK: - Swiping between workspaces

    private var swipeMonitor: SwipeMonitor?

    private func carryOut(_ decision: WorkspaceSwipe.Decision) -> Bool {
        switch decision {
        case .none: false
        case .next: withAnimation(Motion.reflow) { store.goToNextWorkspace() }
        case .previous: withAnimation(Motion.reflow) { store.goToPreviousWorkspace() }
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
    func showWorkspace(at index: Int) {
        withAnimation(Motion.reflow) { store.selectWorkspace(at: index) }
        open()
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

    /// Where the window goes while it is dragged; see `PanelMover`.
    private lazy var mover = PanelMover(panel: panel, parking: parking)

    func beginPanelDrag() {
        mover.begin()
        // A drag can wander anywhere; don't let leaving the panel fold it away.
        panelState.setHold(.panelDrag, true)
        collapseTask?.cancel()
    }

    func dragPanel() {
        mover.follow()
    }

    func endPanelDrag() {
        panelState.setHold(.panelDrag, false)
        mover.end(isMinimised: isMinimised)
    }

    func windowDragEnded(from start: NSRect) {
        mover.pillDragEnded(from: start, isMinimised: isMinimised)
    }

    /// Hides the panel, leaving the menu bar icon behind to bring it back.
    ///
    /// Deliberately *not* `NSApp.terminate`: closing the window should not end the
    /// app, or there is no way back short of relaunching it from Finder.
    func close() {
        fold(hidingPill: true)
    }

    /// ⌘Z. Lives here because the panel routes key events to the controller.
    ///
    /// Never while typing: ⌘Z in a note means "undo my typing", and should be
    /// handled by the field through `MainMenu`. If it ever arrives here instead, it
    /// must not reach back past the sentence being written to undo a pop.
    func undo() {
        guard !isMinimised, !store.isEditing else { return }
        store.undo()
    }

    // MARK: - Presentation

    /// Only the resting pill dims — it is pure chrome. The expanded panel stays at
    /// full alpha because window alpha fades *everything*, and the tiles are
    /// supposed to read as solid objects over your work.
    private static let idleAlpha: CGFloat = 0.55

    private var expandedView: RootView {
        RootView(
            store: store,
            panelState: panelState,
            shortcut: shortcut,
            onClose: { [weak self] in self?.close() },
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) },
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
            onWindowDragEnded: { [weak self] start in self?.windowDragEnded(from: start) },
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
        // The outgoing view takes its @State with it, including any drag in progress
        // and any confirmation it was asking. What survives is `panelState`, so it is
        // cleared here rather than left holding the panel open for a question no one
        // can see any more.
        panelState.forgetView()
        panel.setFrame(parking.frame(sized: size), display: false)
        panel.contentView = FirstMouseHostingView(rootView: view)
        panel.displayIfNeeded()
    }

    /// The pointer arrived or left. What that means is `HoverIntent`'s decision.
    private func setHovering(_ hovering: Bool) {
        // Expanded is always fully opaque; only the pill fades when unattended.
        let solid = !isMinimised || hovering || panelState.isPinned || store.isEditing
        fade(to: solid ? 1.0 : Self.idleAlpha, quickly: hovering)
        handle(hovering ? .entered : .left)
    }

    private var hoverSituation: HoverIntent.Situation {
        HoverIntent.Situation(
            isMinimised: isMinimised,
            isPinned: panelState.isPinned,
            isEditing: store.isEditing,
            isHeld: panelState.blocksAutoCollapse
        )
    }

    private func handle(_ event: HoverIntent.Event) {
        for effect in HoverIntent.effects(for: event, in: hoverSituation) {
            switch effect {
            case .scheduleExpand:
                expandTask?.cancel()
                expandTask = after(Motion.expandDelay) { $0.handle(.expandDelayElapsed) }
            case .cancelExpand:
                expandTask?.cancel()
                expandTask = nil
            case .scheduleCollapse:
                collapseTask?.cancel()
                collapseTask = after(Motion.collapseDelay) { $0.handle(.collapseDelayElapsed) }
            case .cancelCollapse:
                collapseTask?.cancel()
                collapseTask = nil
            case .expand:
                // Hover must not make the panel key — that would divert your typing
                // from whatever app you are actually working in.
                expand(takeFocus: false)
            case .minimise:
                minimise()
            }
        }
    }

    private func after(_ delay: Duration, _ body: @escaping (PanelController) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            body(self)
        }
    }

    /// Fades the whole window rather than tinting the views, so material, tiles
    /// and shadows all fade together.
    private func fade(to target: CGFloat, quickly: Bool) {
        guard abs(panel.alphaValue - target) > 0.001 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = quickly ? Motion.windowFadeIn : Motion.windowFadeOut
            panel.animator().alphaValue = target
        }
    }

    /// Pinned means "stay open". Only the state flips — the bar is watching it, so
    /// nothing has to be rebuilt to show it.
    private func togglePin() {
        panelState.isPinned.toggle()
        collapseTask?.cancel()
        fade(to: 1.0, quickly: true)
    }

    func minimise() {
        guard !isMinimised else { return }
        fold(hidingPill: false)
    }

    /// Folds the panel back to the pill — and, when the pill is turned off or the
    /// panel is being closed, hides that too, leaving the menu bar icon as the way
    /// back in.
    private func fold(hidingPill: Bool) {
        collapseTask?.cancel()
        expandTask?.cancel()
        isMinimised = true
        panelState.isPinned = false
        store.editingID = nil
        store.renamingWorkspaceID = nil
        // A swipe left half-finished when the panel folded away must not be picked
        // up by the next one.
        swipeMonitor?.reset()
        show(pillView, sized: MinimisedPill.size)
        // The resting spot is the one worth remembering across a quit.
        parking.park(settledPill: panel.frame)
        if hidingPill || !showsFloatingPill {
            panel.orderOut(nil)
        } else {
            fade(to: Self.idleAlpha, quickly: false)
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
    func toggleFromMenuBar() {
        if isMinimised {
            if !parking.isOnScreen(panel.frame), let icon = menuBar?.screenFrame {
                moveBelow(icon)
            }
            open()
        } else {
            minimise()
        }
    }

    func toggleFloatingPill() {
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
            open()
        } else {
            minimise()
        }
    }

    func recordShortcut() {
        open()
        withAnimation(Motion.overlay) { panelState.isRecordingShortcut = true }
    }

    /// Opening on purpose — a click, a hotkey, a menu — rather than by hover: focus
    /// and full opacity at once.
    private func open() {
        expand(takeFocus: true)
        fade(to: 1.0, quickly: true)
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
                context.duration = Motion.windowResize
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true, animate: false)
        }
    }
}
