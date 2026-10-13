import AppKit

/// Moves the panel while it is dragged, snapping it to screen edges, and parks it
/// where it is dropped.
///
/// The *when* — holds on the auto-collapse, cancelling a pending fold — stays with
/// `PanelController`; this is only where the window goes.
@MainActor
final class PanelMover {
    private weak var panel: NSPanel?
    private let parking: PanelParking

    init(panel: NSPanel, parking: PanelParking) {
        self.panel = panel
        self.parking = parking
    }

    /// Where the panel and the pointer were when the current drag started, both in
    /// screen coordinates.
    private var dragAnchor: (window: NSPoint, mouse: NSPoint)?

    /// Dragging is driven by a SwiftUI `DragGesture` on the status handle, but the
    /// movement is computed here from `NSEvent.mouseLocation`.
    ///
    /// **Do not use the gesture's `translation`.** It is measured in the window's
    /// own coordinate space, and this gesture moves that window: the pointer keeps
    /// roughly the same window-relative position, translation collapses towards
    /// zero, and the panel never moves. Screen coordinates are unaffected by the
    /// window moving underneath them.
    ///
    /// AppKit's `performDrag` was tried twice before this and is not the answer
    /// either — it needs the mouse-down to reach an `NSView` buried behind SwiftUI
    /// content, which kept breaking on layering and first-mouse.
    func begin() {
        guard let panel else { return }
        dragAnchor = (window: panel.frame.origin, mouse: NSEvent.mouseLocation)
    }

    /// Snapping is applied live rather than on release, so the panel visibly jumps
    /// flush and you can see it has taken. The position is recomputed from the
    /// drag's start each time, so a snap never accumulates into a drift.
    func follow() {
        guard let panel, let start = dragAnchor else { return }
        let mouse = NSEvent.mouseLocation
        var frame = panel.frame
        frame.origin = NSPoint(
            x: start.window.x + (mouse.x - start.mouse.x),
            y: start.window.y + (mouse.y - start.mouse.y)
        )
        panel.setFrameOrigin(parking.snapping(frame).origin)
    }

    func end(isMinimised: Bool) {
        guard let panel else { return }
        dragAnchor = nil
        // Where it was dropped decides where the pill now rests and which way the
        // panel opens from it. This handle is the bar, so an expanded panel parks by
        // its top edge — see `PanelPlacement.init(draggedPanel:in:)`.
        if isMinimised {
            parking.park(pill: panel.frame)
        } else {
            parking.park(draggedPanel: panel.frame)
        }
    }

    /// The end of a `performDrag` on the minimised pill.
    ///
    /// That path is AppKit's, not SwiftUI's — it moves the window from inside its
    /// own tracking loop, so there is nowhere to apply magnetism *during* the drag
    /// without fighting it. Snapping on release instead, animated, still reads as
    /// the edge pulling the pill in.
    ///
    /// A plain click arrives here too, so a move has to be proved before the anchor
    /// is re-read. That click may well have *expanded* the panel, and resolving an
    /// anchor from the expanded frame flips which corner the panel is parked in:
    /// a pill near the middle reads as right-anchored, the panel it opens into
    /// reaches further left and so reads as left-anchored, and minimising would
    /// then fling the pill several hundred points across the screen.
    func pillDragEnded(from start: NSRect, isMinimised: Bool) {
        guard let panel, isMinimised, panel.frame.size == start.size, panel.frame.origin != start.origin
        else { return }

        let snapped = parking.snapping(panel.frame)
        if snapped != panel.frame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.pillSnap
                panel.animator().setFrame(snapped, display: true)
            }
        }
        // Read from `snapped`, not `panel.frame`: the animator above hasn't landed.
        parking.park(pill: snapped)
    }
}
