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
    private weak var actions: MenuBarActions?
    private var observer: AnyCancellable?

    init(store: BubbleStore, actions: MenuBarActions) {
        self.store = store
        self.actions = actions
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
        // Debounced: the badge only changes when a note comes, goes or ages, but the
        // store also changes on every keystroke, and recounting every board per
        // character bought nothing. Delivered after the change has landed, which
        // `objectWillChange` on its own does not promise.
        observer = store.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshBadge() }
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

    /// The count is across **every** board, like the pill's — the icon is on screen
    /// whether or not the panel is, so a number describing only the selected board
    /// would go quiet about notes rotting on the others. The Workspaces submenu is
    /// where that total gets broken down again, board by board.
    private func refreshBadge() {
        let overdue = store.everywhere.overdue
        let title = overdue > 0 ? " \(overdue)" : ""
        // Setting the same title still re-lays-out the status item.
        guard item.button?.title != title else { return }
        item.button?.title = title
        item.button?.toolTip = overdue > 0
            ? "Note Bubble — \(overdue) overdue"
            : "Note Bubble"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            actions?.toggleFromMenuBar()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        // Which build this is, for bug reports — not clickable.
        let version = NSMenuItem(title: AppVersion.summary, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())

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
        pill.state = actions?.showsFloatingPill ?? true ? .on : .off
        pill.target = self
        menu.addItem(pill)

        menu.addItem(loginItem)

        let mute = NSMenuItem(title: "Mute pop sounds", action: #selector(toggleMute), keyEquivalent: "")
        mute.state = PopSounds.shared.isMuted ? .on : .off
        mute.target = self
        menu.addItem(mute)

        menu.addItem(.separator())
        menu.addItem(withTitle: "About Note Bubble", action: #selector(about), keyEquivalent: "")
            .target = self
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

    /// The icon's badge is one total across every board; this is where it is
    /// broken back down, so you can see which board is rotting.
    private func title(for workspace: Workspace) -> String {
        let overdue = store.tally(of: workspace).overdue
        return overdue > 0 ? "\(workspace.displayName) — \(overdue) overdue" : workspace.displayName
    }

    @objc private func selectWorkspace(_ sender: NSMenuItem) { actions?.showWorkspace(at: sender.tag) }
    @objc private func newWorkspace() { actions?.newWorkspace() }
    @objc private func open() { actions?.toggleFromMenuBar() }
    @objc private func togglePill() { actions?.toggleFloatingPill() }
    @objc private func toggleLoginItem() { LoginItem.toggle() }

    /// Ticked when on; a dash while macOS waits for you to approve it in System
    /// Settings, where choosing it again takes you.
    private var loginItem: NSMenuItem {
        let item = NSMenuItem(title: "Open at login", action: #selector(toggleLoginItem), keyEquivalent: "")
        item.target = self
        switch LoginItem.state {
        case .on:
            item.state = .on
        case .awaitingApproval:
            item.state = .mixed
            item.toolTip = "Waiting for approval in System Settings → General → Login Items"
        case .off:
            item.state = .off
        case .unavailable:
            // No action rather than `isEnabled = false`: the menu auto-enables
            // any item whose target answers its action, and would re-enable it.
            item.action = nil
            item.toolTip = "Only available in the built app"
        }
        return item
    }

    @objc private func toggleMute() { PopSounds.shared.isMuted.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// The standard panel, with the stamped version and copyright. Asking for it
    /// is the one time activating the app is what the user wants.
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
