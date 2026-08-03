import SwiftUI

/// Asks before popping a tile that still holds unpopped bubbles, since the whole
/// subtree goes with it.
///
/// Drawn inside the panel rather than as an `NSAlert`: a system modal would
/// activate the app and pull focus off whatever the user was working in, which is
/// the one thing an always-on-top widget must never do.
struct ConfirmPopSheet: View {
    let node: BubbleNode
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)

                Text("Pop “\(node.displayName)”?")
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(contentsDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Pop", action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.small)
            }
            .padding(18)
            .frame(maxWidth: 250)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        }
        .transition(.opacity)
    }

    private var contentsDescription: String {
        let count = node.descendantCount
        return count == 1
            ? "It still holds 1 unpopped bubble, which goes with it."
            : "It still holds \(count) unpopped bubbles, which go with it."
    }
}
