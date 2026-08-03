import Foundation

/// Transient panel-level UI state that the window needs to know about but the
/// note model has no business holding.
@MainActor
final class PanelState: ObservableObject {
    /// Set while something on screen must not be interrupted: a confirmation
    /// sheet, or a tile mid-drag. The panel refuses to auto-collapse while true,
    /// otherwise brushing the pointer off the edge would cancel the interaction.
    @Published var blocksAutoCollapse = false
}
