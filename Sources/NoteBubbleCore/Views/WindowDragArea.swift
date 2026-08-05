import SwiftUI
import AppKit

/// Lets a borderless panel be dragged by its background without swallowing clicks
/// on the SwiftUI controls layered above it.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let before = window.frame
            window.performDrag(with: event)
            // `performDrag` runs its own tracking loop and returns on mouse-up,
            // having moved the window itself — so this is the only moment the
            // controller gets to snap the pill to an edge and re-read its corner.
            // The frame it started from goes too, since a click that opened the
            // panel comes through here as well and is not a move.
            (window.delegate as? PanelController)?.windowDragEnded(from: before)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only claim the click if no sibling control wanted it.
            super.hitTest(point) === self ? self : nil
        }

        /// Without this the panel cannot be dragged in one motion.
        ///
        /// Hover-expansion deliberately does not make the panel key, and AppKit
        /// spends the first click on an inactive window activating it rather than
        /// delivering it. `mouseDown` never ran, so `performDrag` never started and
        /// the panel appeared stuck until something else had focused it.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Hosting view that passes the first click through to its content.
///
/// Same reason as `DragView.acceptsFirstMouse`: this panel is routinely visible
/// but not key, and every button, tile and gesture inside it should respond to the
/// first click rather than quietly spending it on focus.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor @preconcurrency required dynamic init(rootView: Content) {
        super.init(rootView: rootView)
        // `PanelController` is the only thing allowed to size this window.
        //
        // By default a hosting view pushes its content's fitting size onto the
        // window as `contentMinSize`/`contentMaxSize`, and AppKit then clamps the
        // frame — keeping the *top-left* corner. That silently shrank the pill
        // window to 118×40 whatever `MinimisedPill.size` said, so a pill parked
        // flush against the right edge sat 60pt inside it and crept further left on
        // every expand/minimise cycle. The panel's geometry is computed deliberately
        // (see `expandedSize`); nothing else may second-guess it.
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
