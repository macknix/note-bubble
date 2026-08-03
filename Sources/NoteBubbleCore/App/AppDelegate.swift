import AppKit

/// Note Bubble runs as an accessory app: no Dock icon, no menu bar, just the
/// floating panel.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: BubbleStore!
    private var controller: PanelController!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = BubbleStore()
        controller = PanelController(store: store)
        hotKey = HotKey { [weak self] in self?.controller.toggleVisible() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }
}
