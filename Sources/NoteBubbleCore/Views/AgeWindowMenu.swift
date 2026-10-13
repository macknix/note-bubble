import SwiftUI

/// "Overdue after: 3 days / 1 week / … " for one board. Offered from the workspace
/// chip, and from the status handle — the traffic light the setting changes, and
/// the one place it can be reached with only a single board, when the chip is not
/// on screen.
struct AgeWindowMenu: View {
    @ObservedObject var store: BubbleStore
    let workspace: Workspace

    var body: some View {
        Menu("Overdue after") {
            ForEach(AgeWindow.presets, id: \.self) { window in
                Button {
                    withAnimation(Motion.resize) { store.setAgeWindow(window, for: workspace.id) }
                } label: {
                    // SwiftUI menus have no checked state; the marker does its job.
                    let title = window == .standard ? "\(window.label) (standard)" : window.label
                    Text(window == workspace.window ? "● \(title)" : title)
                }
            }
        }
    }
}
