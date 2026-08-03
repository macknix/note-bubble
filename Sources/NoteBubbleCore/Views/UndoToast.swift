import SwiftUI

/// Briefly confirms a pop and offers to take it back, for people who reach for a
/// button rather than ⌘Z.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .lineLimit(1)
            Button("Undo", action: onUndo)
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
