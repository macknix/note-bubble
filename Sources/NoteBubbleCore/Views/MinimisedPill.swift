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

    /// **Everything, not just the board that happens to be selected.** Minimised,
    /// there is no board in front of you: this is the app's one at-a-glance number,
    /// and a note rotting on a board you last opened a fortnight ago is exactly the
    /// thing it should be telling you about.
    private var counts: (notes: Int, overdue: Int) { store.everywhere }
    private var overdue: Int { counts.overdue }
    private var total: Int { counts.notes }

    /// With more than one board the second line gives the number above it its scope,
    /// so it cannot be mistaken for one board's worth. Which board will open is left
    /// to the tooltip: it is the less useful of the two, and there is only room for
    /// one of them.
    ///
    /// **There are 43pt for this line** — 132 less the pill's insets, the badge, the
    /// chevron and the gaps between them, which is what "no wider" in `size` above
    /// actually buys. "all fresh" is 35pt and was the longest label the pill was
    /// built around. Two attempts at naming the scope overflowed it before it was
    /// measured rather than guessed: "3 workspaces" became "3 work…", "everywhere"
    /// became "everyw…". "all told" is 30pt, names no noun that would compete with
    /// the workspace chip's, and does not grow with the number of boards.
    private var subtitle: String {
        guard !store.hasMultipleWorkspaces else { return "all told" }
        return overdue > 0 ? "\(total) total" : "all fresh"
    }

    private var tooltip: String {
        store.hasMultipleWorkspaces
            ? "Click to open Note Bubble on \(store.currentWorkspace.displayName) · drag to move"
            : "Click to open Note Bubble · drag to move"
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
        .help(tooltip)
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
