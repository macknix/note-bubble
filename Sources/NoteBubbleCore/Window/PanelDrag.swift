import Foundation

/// Hooks the panel's drag handle uses to move the window.
///
/// Deliberately carries **no translation value**. SwiftUI reports drag translation
/// in `.global` space, which is the *window's* coordinate space — and moving the
/// window moves that space with it, so the pointer appears to stay put and the
/// translation collapses to nothing. The panel could not be dragged at all.
///
/// The controller reads `NSEvent.mouseLocation` (screen coordinates) instead; the
/// view only has to say when the drag starts, continues and ends.
struct PanelDrag {
    let began: () -> Void
    let changed: () -> Void
    let ended: () -> Void
}
