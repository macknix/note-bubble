import AppKit

/// Borderless, transparent, always-on-top panel that rides along to every Space
/// and over full-screen apps, without stealing focus from whatever you're doing.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Moved by `panelDraggable` on the bar, and by `WindowDragArea` on the pill.
        isMovableByWindowBackground = false

        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    /// Required so the text fields inside bubbles can take keystrokes. Paired with
    /// `.nonactivatingPanel`, this gives keyboard focus without activating the app.
    /// Who carries out the shortcuts below.
    weak var commands: PanelCommands?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Borderless windows swallow ⌘-shortcuts by default; wire up the essentials.
    ///
    /// This is the end of the responder chain, so a focused text field has already
    /// had its go — ⌘← inside a note still means "start of line" and never reaches
    /// here.
    override func keyDown(with event: NSEvent) {
        let shortcut = PanelShortcut.match(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift)
        )
        guard let shortcut else {
            super.keyDown(with: event)
            return
        }
        switch shortcut {
        case .minimise: commands?.minimise()
        case .quit: NSApp.terminate(nil)
        case .newBubble: commands?.newBubble()
        case .newWorkspace: commands?.newWorkspace()
        case .undo: commands?.undo()
        case .previousWorkspace: commands?.previousWorkspace()
        case .nextWorkspace: commands?.nextWorkspace()
        case .escape: commands?.escape()
        }
    }
}

/// Which panel command a key press means, decided without AppKit so it can be tested.
enum PanelShortcut: Equatable {
    case minimise, quit, newBubble, newWorkspace, undo
    case previousWorkspace, nextWorkspace
    case escape

    private static let escapeKey: UInt16 = 53
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124

    /// Letters are matched case-insensitively and Shift is read from the modifier
    /// flags, never from the letter's case. Telling ⌘N from ⌘⇧N by whether the
    /// character came out as "N" made Caps Lock turn every new note into a new
    /// workspace.
    static func match(characters: String?, keyCode: UInt16, command: Bool, shift: Bool) -> PanelShortcut? {
        if keyCode == escapeKey { return .escape }
        guard command else { return nil }

        switch keyCode {
        case leftArrow: return .previousWorkspace
        case rightArrow: return .nextWorkspace
        default: break
        }

        switch (characters?.lowercased(), shift) {
        case ("w", false), ("m", false): return .minimise
        case ("q", false): return .quit
        case ("n", false): return .newBubble
        case ("n", true): return .newWorkspace
        case ("z", false): return .undo
        default: return nil
        }
    }
}
