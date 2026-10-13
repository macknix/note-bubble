import AppKit
import Carbon.HIToolbox

/// A process-wide hotkey via Carbon's RegisterEventHotKey. Chosen over an
/// NSEvent global monitor because it needs no Accessibility permission.
///
/// The handler is installed once; the key it listens for can be changed as often
/// as you like with `register(_:)`.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// The C callback cannot capture context, so it reaches the instance this way.
    private static var active: HotKey?

    init(action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                MainActor.assumeIsolated { HotKey.active?.action() }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handler
        )
        if status == noErr { HotKey.active = self }
    }

    /// Listens for `combo` instead of whatever was registered before. Returns false
    /// if macOS refused it — most often because another app already has it.
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        guard handler != nil else { return false }
        let id = EventHotKeyID(signature: OSType(0x4E42_4231), id: 1) // 'NBB1'
        return RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
