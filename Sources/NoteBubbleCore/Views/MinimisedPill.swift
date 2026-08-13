import SwiftUI

/// Collapsed state: a small pill showing what's gone red, click to expand.
struct MinimisedPill: View {
    /// The pill's window, exactly — the view below fills it rather than sizing
    /// itself, since this rectangle is what snaps against a screen edge.
    ///
    /// It is the badge and the chevron and nothing else: 3pt outer padding, 11pt
    /// inside the capsule, a 24pt badge, an 8pt gap, a 13pt chevron, and the same
    /// again on the right. It used to carry two lines of text as well and was 132pt
    /// wide for them; at rest the number *is* the information, and the words beside
    /// it only made the widget harder to ignore.
    static let size = NSSize(width: 76, height: 46)

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

    /// Everything the pill no longer says out loud. The badge is a number and a
    /// colour; this is where it is spelled out in words, including the scope — which
    /// matters most for the count, since it covers boards you cannot see.
    private var tooltip: String {
        let scope = store.hasMultipleWorkspaces ? " across every workspace" : ""
        let summary = overdue > 0
            ? "\(overdue) overdue\(scope)"
            : "\(total) \(total == 1 ? "bubble" : "bubbles")\(scope), all fresh"
        let opens = store.hasMultipleWorkspaces
            ? " on \(store.currentWorkspace.displayName)"
            : ""
        return "Note Bubble — \(summary) · click to open\(opens), drag to move"
    }

    var body: some View {
        HStack(spacing: 8) {
            badge

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
