import SwiftUI

/// Another board, drawn in place of this one while a tile is held over its dot.
///
/// Purely a picture. It takes no clicks, nothing in it can be edited, popped or
/// rearranged, and the store is not on this board — see `BubbleGrid.previewWorkspace`
/// for why that matters. Only the **top level** is shown, because that is where a
/// dropped note would land.
struct WorkspacePreview: View {
    let workspace: Workspace
    let layout: GridLayout
    let now: Date

    var body: some View {
        // The same plan the grid builds, so a previewed board packs exactly as it
        // will once you are on it.
        let plan = LayoutPlan(nodes: workspace.notes, layout: layout)

        ZStack(alignment: .topLeading) {
            ForEach(Array(workspace.notes.enumerated()), id: \.element.id) { index, node in
                TileFace(node: node, size: plan.size(at: index), now: now)
                    .position(plan.restingCentre(at: index))
            }
        }
        .allowsHitTesting(false)
    }
}
