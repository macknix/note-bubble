import SwiftUI

/// Collapsed state: a small pill showing what's gone red, click to expand.
struct MinimisedPill: View {
    /// The pill's window, exactly — the view below fills it rather than sizing
    /// itself, since this rectangle is what snaps against a screen edge. Wide enough
    /// for a two-digit badge beside the longest label, and no wider.
    static let size = NSSize(width: 132, height: 46)

    @ObservedObject var store: BubbleStore
    let onExpand: () -> Void
    let onHoverChange: (Bool) -> Void

    @State private var hovering = false

    private var overdue: Int { store.overdueCount }
    private var total: Int { store.root.flattened.count }

    /// The counts on the pill are the current board's, so with more than one board
    /// the second line has to say which — otherwise the resting state of the app
    /// shows a number with no idea what it is counting.
    private var subtitle: String {
        guard !store.hasMultipleWorkspaces else { return store.currentWorkspace.displayName }
        return overdue > 0 ? "\(total) total" : "all fresh"
    }

    var body: some View {
        HStack(spacing: 8) {
            badge

            VStack(alignment: .leading, spacing: 0) {
                Text(overdue > 0 ? "overdue" : "bubbles")
                    .font(.system(size: 10, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.up.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0.45)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        // The capsule fills the window rather than sizing itself, so that "snapped
        // flush to the edge" means the *pill* is flush — a window larger than the
        // thing drawn in it would park with a transparent margin against the edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Decorative only: hits must fall through to the drag area behind.
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 9, y: 3)
                .allowsHitTesting(false)
        )
        // Just enough inset for the hover swell below to have somewhere to go.
        .padding(3)
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0; onHoverChange($0) }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .onTapGesture(perform: onExpand)
        .background(WindowDragArea())
        .contextMenu {
            Button("Open") { onExpand() }
            Divider()
            Button("Quit Note Bubble") { NSApp.terminate(nil) }
        }
        .help("Click to open Note Bubble · drag to move")
    }

    /// Rounded square rather than a circle, matching the tiles it stands in for.
    private var badge: some View {
        let days: Double = overdue > 0 ? 99 : 0
        return ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Aging.color(forDays: days), Aging.shadeColor(forDays: days)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
            Text("\(overdue > 0 ? overdue : total)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
