import AppKit

/// Note Bubble runs as an accessory app: no Dock icon, no menu bar, just the
/// floating panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: BubbleStore!
    private var controller: PanelController!
    private var shortcut: GlobalShortcut!
    private var ageClock: AgeClock?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = BubbleStore()
        shortcut = GlobalShortcut { [weak self] in self?.controller.toggleVisible() }
        controller = PanelController(store: store, shortcut: shortcut)
        // Never shown, but it is what routes ⌘C/⌘V/⌘Z to a focused text field.
        MainMenu.install { [weak self] in self?.controller.undo() }
        ageClock = AgeClock { [weak self] in self?.store.advanceClock() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }
}
