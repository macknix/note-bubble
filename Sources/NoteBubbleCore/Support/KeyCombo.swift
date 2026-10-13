import Carbon.HIToolbox

/// A global keyboard shortcut: a key and its modifiers, in the form Carbon's
/// `RegisterEventHotKey` takes, plus what to call the key on screen.
///
/// No AppKit — what an `NSEvent` turned into is the recorder's business — so the
/// rules about what makes an acceptable shortcut can be tested on their own.
struct KeyCombo: Codable, Equatable {
    /// A virtual key code (`kVK_…`).
    var keyCode: UInt32
    /// Carbon modifier bits: `cmdKey`, `optionKey`, `controlKey`, `shiftKey`.
    var modifiers: UInt32
    /// The key as it should read — "Space", "K", "F5" — captured when recorded,
    /// since a key code alone does not know the keyboard layout.
    var key: String

    /// ⌥Space, which is what Note Bubble has always used.
    static let standard = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space")

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init(keyCode: UInt16, command: Bool, option: Bool, control: Bool, shift: Bool, characters: String?) {
        var bits: UInt32 = 0
        if command { bits |= UInt32(cmdKey) }
        if option { bits |= UInt32(optionKey) }
        if control { bits |= UInt32(controlKey) }
        if shift { bits |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(keyCode), modifiers: bits, key: Self.name(ofKey: keyCode, characters: characters))
    }

    /// "⌃⌥⇧⌘K", in the order macOS menus use.
    var display: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + key
    }

    /// Whether this can be a global shortcut at all. It needs ⌘, ⌥ or ⌃ — a plain
    /// letter, or one with only ⇧, would fire every time you typed it anywhere —
    /// unless it is a function key, which nothing types.
    var isAcceptable: Bool {
        let anchors = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
        return modifiers & anchors != 0 || Self.functionKeys[UInt16(keyCode)] != nil
    }

    // MARK: - Naming keys

    private static let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15", UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]

    private static let namedKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘", UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟"
    ]

    static func name(ofKey keyCode: UInt16, characters: String?) -> String {
        if let name = functionKeys[keyCode] ?? namedKeys[keyCode] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? "Key \(keyCode)" : typed.uppercased()
    }
}
