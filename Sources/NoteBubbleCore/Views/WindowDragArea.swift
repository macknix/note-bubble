import SwiftUI
import AppKit

/// Lets a borderless panel be dragged by its background without swallowing clicks
/// on the SwiftUI controls layered above it.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
