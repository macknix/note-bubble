import AppKit

/// What the panel's keyboard shortcuts ask for. `OverlayPanel` holds one weakly
/// and knows nothing else about who carries them out.
///
/// It used to downcast `delegate as? PanelController` for every shortcut, which tied
/// the window to one concrete controller and meant a new shortcut touched three files.
@MainActor
protocol PanelCommands: AnyObject {
    func minimise()
    func newBubble()
    func newWorkspace()
    func undo()
    func previousWorkspace()
    func nextWorkspace()
    func escape()
}

/// What the menu bar item can ask the app to do, and the one thing it needs to read.
@MainActor
protocol MenuBarActions: AnyObject {
    /// Left-click, and "Open Note Bubble".
    func toggleFromMenuBar()
    var showsFloatingPill: Bool { get }
    func toggleFloatingPill()
    /// Picking a board from the Workspaces submenu.
    func showWorkspace(at index: Int)
    func newWorkspace()
    /// The shortcut that opens the panel from anywhere.
    var shortcut: GlobalShortcut { get }
    /// Opens the panel with the shortcut recorder over it.
    func recordShortcut()
}
