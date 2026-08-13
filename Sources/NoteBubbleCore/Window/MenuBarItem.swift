import AppKit
import Combine

/// Note Bubble's presence in the system menu bar.
///
/// Left-click toggles the panel; right-click opens a menu. The icon carries the
/// overdue count as its title, so the thing the traffic lights exist to tell you
/// is legible without opening anything.
@MainActor
final class MenuBarItem {
    private let item: NSStatusItem
    private let store: BubbleStore
    private let onToggle: () -> Void
    private let onTogglePill: () -> Void
    private let showsPill: () -> Bool
    private let onSelectWorkspace: (Int) -> Void
    private let onNewWorkspace: () -> Void
    private var observer: AnyCancellable?

    init(
        store: BubbleStore,
        onToggle: @escaping () -> Void,
        showsPill: @escaping () -> Bool,
        onTogglePill: @escaping () -> Void,
        onSelectWorkspace: @escaping (Int) -> Void,
        onNewWorkspace: @escaping () -> Void
    ) {
        self.store = store
        self.onToggle = onToggle
        self.showsPill = showsPill
        self.onTogglePill = onTogglePill
        self.onSelectWorkspace = onSelectWorkspace
        self.onNewWorkspace = onNewWorkspace
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "circle.grid.2x2.fill",
                accessibilityDescription: "Note Bubble"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked)
            // Both buttons route here so right-click can raise the menu without
            // the status item claiming it permanently — assigning `item.menu`
            // would swallow left-clicks too.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshBadge()
        observer = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refreshBadge() }
        }
    }

    deinit {
        // `item` must outlive nothing; removing it here keeps the menu bar clean
        // if the controller is ever torn down.
        NSStatusBar.system.removeStatusItem(item)
    }

    /// Screen rect of the icon, so the panel can be positioned beneath it.
    var screenFrame: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func refreshBadge() {
        let overdue = store.overdueCount
        item.button?.title = overdue > 0 ? " \(overdue)" : ""
        item.button?.toolTip = overdue > 0
            ? "Note Bubble — \(overdue) overdue"
            : "Note Bubble"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onToggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Open Note Bubble", action: #selector(open), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())
        menu.addItem(workspacesItem)
        menu.addItem(.separator())

        let pill = NSMenuItem(
            title: "Show floating pill",
            action: #selector(togglePill),
            keyEquivalent: ""
        )
        pill.state = showsPill() ? .on : .off
        pill.target = self
        menu.addItem(pill)

        let mute = NSMenuItem(title: "Mute pop sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.state = PopSounds.shared.isMuted ? .on : .off
        mute.target = self
        menu.addItem(mute)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Note Bubble", action: #selector(quit), keyEquivalent: "q")
            .target = self

        // Attaching the menu only for this click keeps left-click as a toggle.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    /// The workspaces, as a submenu. This is the only way to reach another board
    /// without opening the panel first, and — with the floating pill turned off —
    /// the only way to find out one exists at all.
    private var workspacesItem: NSMenuItem {
        let submenu = NSMenu()
        for (index, workspace) in store.workspaces.enumerated() {
            let entry = NSMenuItem(
                title: title(for: workspace),
                action: #selector(selectWorkspace(_:)),
                keyEquivalent: ""
            )
            entry.state = index == store.currentIndex ? .on : .off
            // The index, not the id: `NSMenuItem.tag` is an `Int`, and the menu is
            // rebuilt for every click so it cannot go stale.
            entry.tag = index
            entry.target = self
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "New workspace", action: #selector(newWorkspace), keyEquivalent: "")
            .target = self

        let item = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// Overdue is called out here because the badge above only counts the board
    /// that is open — this is where the others get to say they are rotting.
    private func title(for workspace: Workspace) -> String {
        let overdue = workspace.overdueCount
        return overdue > 0 ? "\(workspace.displayName) — \(overdue) overdue" : workspace.displayName
    }

    @objc private func selectWorkspace(_ sender: NSMenuItem) { onSelectWorkspace(sender.tag) }
    @objc private func newWorkspace() { onNewWorkspace() }
    @objc private func open() { onToggle() }
    @objc private func togglePill() { onTogglePill() }
    @objc private func toggleMute() { PopSounds.shared.isMuted.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
