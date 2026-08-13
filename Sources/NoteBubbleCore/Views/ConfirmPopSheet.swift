import SwiftUI

/// Asks before popping a tile that still holds unpopped bubbles, since the whole
/// subtree goes with it.
///
/// The sheet itself is `ConfirmSheet`, which is also what a workspace deletion
/// uses — and which carries the rule about never being an `NSAlert`.
struct ConfirmPopSheet: View {
    let node: BubbleNode
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ConfirmSheet(
            icon: "exclamationmark.triangle.fill",
            title: "Pop “\(node.displayName)”?",
            message: contentsDescription,
            confirmTitle: "Pop",
            onCancel: onCancel,
            onConfirm: onConfirm
        )
    }

    private var contentsDescription: String {
        let count = node.descendantCount
        return count == 1
            ? "It still holds 1 unpopped bubble, which goes with it."
            : "It still holds \(count) unpopped bubbles, which go with it."
    }
}
