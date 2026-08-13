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
        isMovableByWindowBackground = false // handled by WindowDragArea

        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    /// Required so the text fields inside bubbles can take keystrokes. Paired with
    /// `.nonactivatingPanel`, this gives keyboard focus without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Borderless windows swallow ⌘-shortcuts by default; wire up the essentials.
    ///
    /// This is the end of the responder chain, so a focused text field has already
    /// had its go — ⌘← inside a note still means "start of line" and never reaches
    /// here.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "w", "m": (delegate as? PanelController)?.minimise(); return
            case "q": NSApp.terminate(nil); return
            case "n": (delegate as? PanelController)?.newBubble(); return
            // ⇧ makes it a new *workspace*: `charactersIgnoringModifiers` keeps the
            // shift, so the capital is the whole test.
            case "N": (delegate as? PanelController)?.newWorkspace(); return
            case "z": (delegate as? PanelController)?.undo(); return
            default: break
            }

            // Paging between workspaces, in the direction the arrows point.
            switch event.keyCode {
            case 123: (delegate as? PanelController)?.previousWorkspace(); return
            case 124: (delegate as? PanelController)?.nextWorkspace(); return
            default: break
            }
        }
        if event.keyCode == 53 { // Escape
            (delegate as? PanelController)?.escape()
            return
        }
        super.keyDown(with: event)
    }
}
