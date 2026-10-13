import AppKit

/// A main menu nobody sees, so that text editing has its usual shortcuts.
///
/// Note Bubble is an accessory app (`LSUIElement`), so it never shows a menu bar —
/// but AppKit still delivers ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z to a text field as *menu key
/// equivalents*: the Edit menu's items send `copy:`, `paste:`, `undo:` and so on
/// down the responder chain. With no main menu at all those shortcuts went nowhere
/// inside a note, and ⌘Z fell through to `OverlayPanel.keyDown`, which undid a pop
/// instead of the typing.
///
/// Undo is routed by hand rather than left to the responder chain, because ⌘Z
/// means two different things here: inside a note it undoes typing, and anywhere
/// else it undoes the last pop, shuffle or filing on the board. Left to the chain,
/// whichever responder answered `undo:` first would win — and if that was the
/// window's own (empty) undo manager, board undo would silently stop working.
@MainActor
enum MainMenu {
    /// Kept alive for the life of the app; menu item targets are weak.
    private static var router: UndoRouter?

    static func install(boardUndo: @escaping () -> Void) {
        let router = UndoRouter(boardUndo: boardUndo)
        Self.router = router

        let menu = NSMenu()
        menu.addItem(submenu(titled: "Note Bubble", [
            NSMenuItem(title: "Quit Note Bubble", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        ]))
        menu.addItem(submenu(titled: "Edit", [
            router.item(title: "Undo", action: #selector(UndoRouter.undo(_:)), shift: false),
            router.item(title: "Redo", action: #selector(UndoRouter.redo(_:)), shift: true),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        ]))
        NSApp.mainMenu = menu
    }

    private static func submenu(titled title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}

/// Sends ⌘Z to the text being edited if there is any, and to the board if not.
@MainActor
private final class UndoRouter: NSObject, NSMenuItemValidation {
    private let boardUndo: () -> Void

    init(boardUndo: @escaping () -> Void) {
        self.boardUndo = boardUndo
    }

    func item(title: String, action: Selector, shift: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "z")
        item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
        item.target = self
        return item
    }

    /// The field editor a note or a workspace name is being typed into, if any.
    private var editor: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    @objc func undo(_ sender: Any?) {
        if let editor {
            editor.undoManager?.undo()
        } else {
            boardUndo()
        }
    }

    @objc func redo(_ sender: Any?) {
        editor?.undoManager?.redo()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Redo exists only for typing; the board's undo has no redo.
        item.action == #selector(redo(_:)) ? editor?.undoManager?.canRedo == true : true
    }
}
