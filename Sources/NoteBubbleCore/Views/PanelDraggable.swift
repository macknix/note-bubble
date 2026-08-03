import SwiftUI

/// Makes a view a handle for moving the panel.
///
/// Applied both to the bar's background — so any empty part of the bar drags it —
/// and to the status handle, which keeps its own grip affordance. Controls layered
/// above the background get their clicks first, so buttons still work.
struct PanelDraggable: ViewModifier {
    let drag: PanelDrag
    /// Reported back so a handle can show it is being held.
    @Binding var isDragging: Bool

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        drag.began()
                    }
                    // The gesture's own translation is deliberately ignored; the
                    // controller reads screen coordinates instead. See `PanelDrag`.
                    drag.changed()
                }
                .onEnded { _ in
                    isDragging = false
                    drag.ended()
                }
        )
    }
}

extension View {
    func panelDraggable(_ drag: PanelDrag, isDragging: Binding<Bool>) -> some View {
        modifier(PanelDraggable(drag: drag, isDragging: isDragging))
    }
}
