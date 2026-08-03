import AppKit
import Carbon.HIToolbox

/// A process-wide hotkey via Carbon's RegisterEventHotKey. Chosen over an
/// NSEvent global monitor because it needs no Accessibility permission.
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    private static var active: HotKey?

    /// Registers ⌥Space by default.
    init?(keyCode: UInt32 = UInt32(kVK_Space),
          modifiers: UInt32 = UInt32(optionKey),
          action: @escaping () -> Void) {
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
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4E42_4231), id: 1) // 'NBB1'
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
        else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }

        HotKey.active = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
