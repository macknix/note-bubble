import Foundation
@testable import NoteBubbleCore

enum PanelShortcutTests {
    private static func key(_ characters: String, keyCode: UInt16 = 0, command: Bool = true, shift: Bool = false) -> PanelShortcut? {
        PanelShortcut.match(characters: characters, keyCode: keyCode, command: command, shift: shift)
    }

    static func run() {
        Check.suite("Panel shortcuts") {
            Check.equal(key("n"), .newBubble, "⌘N is a new bubble")
            Check.equal(key("N", shift: true), .newWorkspace, "⌘⇧N is a new workspace")
            Check.equal(key("N"), .newBubble, "with Caps Lock on, ⌘N is still a new bubble")
            Check.equal(key("n", shift: true), .newWorkspace, "Shift is read from the flags, not the letter")
            Check.equal(key("Z"), .undo, "⌘Z undoes, Caps Lock or not")
            Check.nil_(key("z", shift: true), "⌘⇧Z is not undo — there is no board redo")
            Check.equal(key("w"), .minimise, "⌘W minimises")
            Check.equal(key("m"), .minimise, "⌘M minimises")
            Check.equal(key("q"), .quit, "⌘Q quits")
            Check.nil_(key("n", command: false), "a plain N is typing, not a command")
            Check.equal(key("", keyCode: 123), .previousWorkspace, "⌘← pages back")
            Check.equal(key("", keyCode: 124), .nextWorkspace, "⌘→ pages forward")
            Check.equal(key("", keyCode: 53, command: false), .escape, "Escape needs no modifier")
            Check.nil_(key("x"), "anything else falls through")
        }

        Check.suite("App version") {
            // The test runner is not an assembled bundle, so nothing was stamped.
            Check.nil_(AppVersion.marketing, "outside a bundle there is no version")
            Check.equal(AppVersion.summary, "Note Bubble — development build", "and the menu says so")
            Check.isTrue(LoginItem.state == .unavailable, "nor anything to register as a login item")
        }
    }
}
