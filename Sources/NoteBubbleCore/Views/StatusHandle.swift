import SwiftUI

/// Where you grab the panel to move it, and how many notes are in each state.
///
/// Only stages that actually have notes are shown. An earlier version always drew
/// three dots, which meant a board of seven fresh notes displayed a green 7 beside
/// two blank grey circles that looked like decoration and explained nothing. A
/// count you don't have isn't information — it's noise.
///
/// The grip glyph is what says "drag me"; the counts are what say "here's the
/// state". Neither has to do both jobs.
struct StatusHandle: View {
    let counts: (fresh: Int, aging: Int, overdue: Int)
    let drag: PanelDrag

    @State private var isDragging = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary.opacity(isDragging ? 0.7 : 0.35))

            if isEmpty {
                Text("No notes")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.4))
            } else {
                if counts.fresh > 0 { badge(counts.fresh, days: 0, urgent: false) }
                if counts.aging > 0 { badge(counts.aging, days: 4, urgent: false) }
                if counts.overdue > 0 { badge(counts.overdue, days: 30, urgent: true) }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(minWidth: 74, alignment: .leading)
        .background {
            Capsule()
                .fill(.white.opacity(isDragging ? 0.18 : 0.07))
                .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                .allowsHitTesting(false)
        }
        .contentShape(Capsule())
        .scaleEffect(isDragging ? 1.05 : 1)
        .animation(Motion.lift, value: isDragging)
        .panelDraggable(drag, isDragging: $isDragging)
        .help(summary)
        .onAppear { pulse = true }
    }

    private var isEmpty: Bool {
        counts.fresh + counts.aging + counts.overdue == 0
    }

    /// Spelled out in words, since the colours alone can't say what they mean.
    private var summary: String {
        guard !isEmpty else { return "No notes yet — drag to move Note Bubble" }
        var parts: [String] = []
        if counts.fresh > 0 { parts.append("\(counts.fresh) fresh") }
        if counts.aging > 0 { parts.append("\(counts.aging) ageing") }
        if counts.overdue > 0 { parts.append("\(counts.overdue) overdue") }
        return parts.joined(separator: " · ") + " — drag to move Note Bubble"
    }

    private func badge(_ count: Int, days: Double, urgent: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Aging.color(forDays: days), Aging.shadeColor(forDays: days)],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 0,
                        endRadius: 11
                    )
                )
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 0.5))
                // Only overdue earns attention, and only when there is some.
                .scaleEffect(urgent && pulse ? 1.1 : 1)
                .animation(
                    urgent ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default,
                    value: pulse
                )

            Text("\(count)")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1)
        }
        .frame(width: 17, height: 17)
        .transition(.scale.combined(with: .opacity))
    }
}
