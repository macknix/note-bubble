import AppKit

/// Watches for two-finger swipes over one window and turns them into
/// previous/next decisions, swallowing only the event that completes a swipe.
///
/// Two-finger swipes arrive as scroll events, and they have to be intercepted
/// *before* the grid's `ScrollView` sees them — hence a local monitor rather than
/// a SwiftUI gesture, which would be layered underneath it. A local monitor is
/// also the only way to be selective: returning the event passes it through
/// untouched, so vertical scrolling still scrolls the grid. A *global* monitor
/// would need Accessibility permission, which this app never asks for.
///
/// What counts as a swipe is `WorkspaceSwipe`'s decision; this is only the wiring.
@MainActor
final class SwipeMonitor {
    private weak var window: NSWindow?
    private var monitor: Any?
    private var swipe = WorkspaceSwipe()

    /// - Parameters:
    ///   - isEnabled: asked per event. While false, scrolls pass straight through
    ///     and are not counted towards a swipe.
    ///   - onSwipe: carries a decision out, returning whether anything happened —
    ///     only then is the event swallowed.
    init(
        window: NSWindow,
        isEnabled: @escaping () -> Bool,
        onSwipe: @escaping (WorkspaceSwipe.Decision) -> Bool
    ) {
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Reduced to plain values before crossing onto the main actor: the event
            // itself is not `Sendable`.
            let source = event.window.map(ObjectIdentifier.init)
            let scroll = WorkspaceSwipe.Scroll(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY,
                isGestureStart: event.phase == .began,
                isInverted: event.isDirectionInvertedFromDevice,
                time: event.timestamp
            )
            // Monitors are delivered on the main thread; this is the same bridge
            // `main.swift` uses to say so.
            let consumed = MainActor.assumeIsolated {
                self?.consume(scroll, from: source, isEnabled: isEnabled, onSwipe: onSwipe) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func consume(
        _ scroll: WorkspaceSwipe.Scroll,
        from source: ObjectIdentifier?,
        isEnabled: () -> Bool,
        onSwipe: (WorkspaceSwipe.Decision) -> Bool
    ) -> Bool {
        guard let window, source == ObjectIdentifier(window), isEnabled() else { return false }
        let decision = swipe.handle(scroll)
        return decision != .none && onSwipe(decision)
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// Forgets a half-finished swipe, so one the panel folded away under is not
    /// picked up by the next.
    func reset() {
        swipe.reset()
    }
}
