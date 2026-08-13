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

    var body: some View {
        let specs = workspace.notes.map { TileSizeCache.spec(for: $0, in: layout) }
        let frames = layout.frames(for: specs)

        ZStack(alignment: .topLeading) {
            ForEach(Array(workspace.notes.enumerated()), id: \.element.id) { index, node in
                BubbleTile(
                    node: node,
                    size: specs[index].size,
                    isEditing: false,
                    isDragging: false,
                    pressProgress: 0,
                    onCommit: { _ in },
                    onFinish: {},
                    onRename: {}
                )
                .position(x: frames[index].midX, y: frames[index].midY)
            }
        }
        .allowsHitTesting(false)
    }
}
