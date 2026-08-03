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
    /// The breadcrumb row, which only appears once you are inside a bubble.
    private static let trailRowHeight: CGFloat = 34
    /// Enough for one row, so a nearly empty panel isn't a sliver.
    private static let minimumBodyHeight: CGFloat = 152
    /// Beyond this the grid scrolls rather than the panel swallowing the screen.
    private static let maximumBodyHeight: CGFloat = 560
    private static let pillSize = NSSize(width: 178, height: 46)

    /// Grace period before an unhovered panel folds back to the pill. Long enough
    /// to cross a gap or overshoot an edge without the panel vanishing.
    private static let collapseDelay: Duration = .milliseconds(450)
    private var collapseTask: Task<Void, Never>?

    /// Dwell required before the pill opens, so merely sweeping the pointer across
    /// it on the way somewhere else doesn't throw the grid open.
    private static let expandDelay: Duration = .milliseconds(180)
    private var expandTask: Task<Void, Never>?

    private var storeObserver: AnyCancellable?
    private var menuBar: MenuBarItem?

    /// Whether the floating on-screen pill is shown when minimised. With a menu bar
    /// icon there are two ways in, so this can be turned off for a tidier screen —
    /// the panel then hides completely instead of leaving the pill behind.
    private static let pillDefaultsKey = "ShowsFloatingPill"
    private var showsFloatingPill: Bool {
        didSet { UserDefaults.standard.set(showsFloatingPill, forKey: Self.pillDefaultsKey) }
    }

    init(store: BubbleStore) {
        self.store = store
        // Defaults to on so nothing disappears for anyone who had no menu bar icon.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.pillDefaultsKey) == nil {
            defaults.set(true, forKey: Self.pillDefaultsKey)
        }
        self.showsFloatingPill = defaults.bool(forKey: Self.pillDefaultsKey)

        // Resting state is the pill, so the widget starts out of the way and the
        // grid appears only when reached for.
        let origin = Self.defaultOrigin(for: Self.pillSize)
        self.panel = OverlayPanel(contentRect: NSRect(origin: origin, size: Self.pillSize))
        super.init()

        panel.delegate = self
        showPill()
        panel.alphaValue = Self.idleAlpha
        if showsFloatingPill { panel.orderFrontRegardless() }

        menuBar = MenuBarItem(
            store: store,
            onToggle: { [weak self] in self?.toggleFromMenuBar() },
            showsPill: { [weak self] in self?.showsFloatingPill ?? true },
            onTogglePill: { [weak self] in self?.toggleFloatingPill() }
        )

        // The panel is only as tall as its contents need, so adding or popping a
        // bubble resizes it. `objectWillChange` fires *before* the mutation lands,
        // hence the hop to the next turn of the run loop to read the new state.
        storeObserver = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.fitToContent() }
        }
    }

    /// Height the expanded panel wants for the notes currently on screen. Tiles are
    /// packed by size, so this has to measure them rather than count rows.
    private var expandedSize: NSSize {
        let layout = GridLayout(availableWidth: Self.panelWidth)
        let specs = store.visible.map { TileSizeCache.spec(for: $0, in: layout) }
        let body = layout.contentHeight(for: specs)
        let clamped = min(max(body, Self.minimumBodyHeight), Self.maximumBodyHeight)
        let chrome = Self.headerHeight + (store.isAtRoot ? 0 : Self.trailRowHeight)
        return NSSize(width: Self.panelWidth, height: chrome + clamped)
    }

    private func fitToContent() {
        guard !isMinimised else { return }
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

    func dragPanel() {
        guard let anchor = dragAnchor else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(
            NSPoint(
                x: anchor.window.x + (mouse.x - anchor.mouse.x),
                y: anchor.window.y + (mouse.y - anchor.mouse.y)
            )
        )
    }

    func endPanelDrag() {
        dragAnchor = nil
        panelState.blocksAutoCollapse = false
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
        showPill()
        resize(to: Self.pillSize)
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

    private func showExpanded() {
        let view = RootView(
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
        panel.contentView = FirstMouseHostingView(rootView: view)
    }

    private func showPill() {
        let view = MinimisedPill(
            store: store,
            onExpand: { [weak self] in self?.expand() },
            onHoverChange: { [weak self] hovering in self?.setHovering(hovering) }
        )
        panel.contentView = FirstMouseHostingView(rootView: view)
    }

    /// The whole interaction model: the pill expands under the pointer and folds
    /// back once it leaves.
    private func setHovering(_ hovering: Bool) {
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
        }

        // Expanded is always fully opaque; only the pill fades when unattended.
        let solid = !isMinimised || hovering || isPinned || store.editingID != nil
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
                  self.store.editingID == nil,
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
        showExpanded()
        fade(to: 1.0, quickly: true)
    }

    func minimise() {
        guard !isMinimised else { return }
        collapseTask?.cancel()
        expandTask?.cancel()
        isMinimised = true
        isPinned = false
        store.editingID = nil
        showPill()
        resize(to: Self.pillSize)
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
        showExpanded()
        resize(to: expandedSize)
        if takeFocus {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Menu bar

    /// Clicking the menu bar icon. Opens beneath the icon when it was fully hidden,
    /// so the panel appears where the user just clicked rather than wherever it was
    /// last left on a possibly different screen.
    private func toggleFromMenuBar() {
        if isMinimised {
            if !panel.isVisible, let anchor = menuBar?.screenFrame {
                moveBelow(anchor)
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
    /// Positioned by its **top** edge, because `expand` grows downward from the
    /// top-left; setting the expanded origin here would leave the panel a full
    /// panel-height too low once it opened.
    private func moveBelow(_ anchor: NSRect) {
        let size = expandedSize
        var top = anchor.minY - 6
        var x = anchor.midX - size.width / 2

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            top = min(top, visible.maxY)
            // Keep the expanded panel on screen if there is room for it at all.
            if top - size.height < visible.minY {
                top = min(visible.minY + size.height, visible.maxY)
            }
        }
        panel.setFrame(
            NSRect(x: x, y: top - Self.pillSize.height, width: Self.pillSize.width, height: Self.pillSize.height),
            display: false
        )
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
        if store.editingID != nil {
            store.editingID = nil
        } else if !store.isAtRoot {
            store.goUp()
        } else {
            minimise()
        }
    }

    /// Resizes about the panel's top-left, so collapsing doesn't make it leap across
    /// the screen. AppKit frames are bottom-left origin, hence the y adjustment.
    private func resize(to size: NSSize, animated: Bool = false) {
        var frame = panel.frame
        frame.origin.y += frame.size.height - size.height
        frame.size = size

        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - size.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - size.height)
        }

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

    private static func defaultOrigin(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 200) }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - size.width - 40, y: visible.maxY - size.height - 40)
    }
}
