import Carbon.HIToolbox
import Foundation
@testable import NoteBubbleCore

enum KeyComboTests {
    private static func combo(_ keyCode: Int, command: Bool = false, option: Bool = false,
                              control: Bool = false, shift: Bool = false, _ characters: String? = nil) -> KeyCombo {
        KeyCombo(keyCode: UInt16(keyCode), command: command, option: option, control: control,
                 shift: shift, characters: characters)
    }

    static func run() {
        Check.suite("Global shortcut combinations") {
            Check.equal(KeyCombo.standard.display, "⌥Space", "the default reads ⌥Space")
            Check.equal(combo(kVK_Space, option: true), .standard, "and is what ⌥ and the space bar make")

            Check.equal(combo(kVK_ANSI_K, command: true, option: true, control: true, shift: true, "k").display,
                        "⌃⌥⇧⌘K", "modifiers read in the order macOS menus use, the letter capitalised")
            Check.equal(combo(kVK_F5).display, "F5", "function keys by name")
            Check.equal(combo(kVK_LeftArrow, control: true).display, "⌃←", "arrows as arrows")

            Check.isTrue(combo(kVK_ANSI_K, command: true, "k").isAcceptable, "⌘K can be global")
            Check.isTrue(combo(kVK_ANSI_K, control: true, "k").isAcceptable, "so can ⌃K")
            Check.isFalse(combo(kVK_ANSI_K, "k").isAcceptable, "a bare letter cannot — it would fire whenever typed")
            Check.isFalse(combo(kVK_ANSI_K, shift: true, "K").isAcceptable, "nor can one with only ⇧")
            Check.isTrue(combo(kVK_F5).isAcceptable, "a function key on its own can")

            let encoded = try? JSONEncoder().encode(combo(kVK_ANSI_J, command: true, "j"))
            Check.equal(encoded.flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) },
                        combo(kVK_ANSI_J, command: true, "j"), "a recorded shortcut survives being saved")
        }
    }
}
