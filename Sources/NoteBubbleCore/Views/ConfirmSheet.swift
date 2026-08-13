import SwiftUI

/// A yes/no question, drawn inside the panel.
///
/// Never an `NSAlert`: a system modal would activate the app and pull focus off
/// whatever the user was working in, which is the one thing an always-on-top widget
/// must never do. That rule is why this exists as a view at all, so anything else
/// that needs to ask uses it rather than reaching for AppKit.
struct ConfirmSheet: View {
    let icon: String
    let title: String
    let message: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle, action: onConfirm)
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
}
