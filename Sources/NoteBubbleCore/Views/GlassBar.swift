import SwiftUI

/// The panel's top bar: status and controls, with the trail of nested bubbles on
/// its own row underneath when you're inside one.
///
/// The second row is not decoration. With the breadcrumb and back button inline,
/// the bar wanted ~500pt of a 398pt budget once you drilled in, and the overflow
/// pushed the rightmost controls outside the panel's clip bounds where they could
/// not be clicked at all. Giving the trail its own full-width row removes the
/// competition entirely — and makes the breadcrumb readable instead of a stub.
struct GlassBar: View {
    @ObservedObject var store: BubbleStore
    @ObservedObject private var sounds = PopSounds.shared

    let isPinned: Bool
    let onTogglePin: () -> Void
    let onClose: () -> Void
    let drag: PanelDrag

    @State private var isDragging = false
    @State private var shuffleSpin: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            controlRow
            if !store.isAtRoot { trailRow }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(Motion.lift, value: store.isAtRoot)
    }

    // MARK: - Rows

    private var controlRow: some View {
        HStack(spacing: 8) {
            StatusHandle(counts: store.stageCounts, drag: drag)
            Spacer(minLength: 6)
            controls
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        // The gesture rides on the *background*, so every empty part of the bar
        // moves the panel while the controls above it still get their own clicks.
        .background {
            BarStyle.glass(cornerRadius: 23)
                .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                .panelDraggable(drag, isDragging: $isDragging)
        }
    }

    private var trailRow: some View {
        HStack(spacing: 6) {
            GlassIconButton(systemImage: "chevron.left", help: "Back", action: store.goUp)
            breadcrumb
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            BarStyle.glass(cornerRadius: 17)
                .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .panelDraggable(drag, isDragging: $isDragging)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var controls: some View {
        HStack(spacing: 6) {
            // Undo appears only when there is something to undo — a permanently
            // greyed-out control is clutter that never earns its place.
            if store.canUndo {
                GlassIconButton(
                    systemImage: "arrow.uturn.backward",
                    help: store.undoLabel.map { "Undo “\($0)” (⌘Z)" } ?? "Undo (⌘Z)",
                    action: store.undo
                )
                .transition(.scale.combined(with: .opacity))
            }

            // Only worth offering when there is more than one bubble to jumble.
            if store.visible.count > 1 {
                GlassIconButton(systemImage: "shuffle", help: "Shuffle the bubbles", action: shuffle)
                    .rotationEffect(.degrees(shuffleSpin))
                    .transition(.scale.combined(with: .opacity))
            }

            GlassIconButton(
                systemImage: sounds.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: sounds.isMuted ? "Pop sounds off" : "Pop sounds on"
            ) { sounds.isMuted.toggle() }

            GlassIconButton(
                systemImage: isPinned ? "pin.fill" : "pin",
                help: isPinned ? "Unpin — fold away when the pointer leaves" : "Pin — stay open",
                tint: isPinned ? BarStyle.candyPink : nil,
                action: onTogglePin
            )

            GlassIconButton(
                systemImage: "xmark",
                help: "Close — reopen from the menu bar",
                action: onClose
            )

            CandyOrb(systemImage: "plus", help: "New bubble (⌘N)") { store.addBubble() }
        }
        // Controls hold their size; anything flexible yields to them. This is what
        // stops a long note title ever squeezing a button out of reach again.
        .layoutPriority(1)
        .animation(Motion.lift, value: store.canUndo)
        .animation(Motion.lift, value: store.visible.count > 1)
    }

    private var breadcrumb: some View {
        HStack(spacing: 3) {
            ForEach(Array(store.breadcrumb.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .black))
                        .opacity(0.35)
                }
                Button { store.goToDepth(index + 1) } label: {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .buttonStyle(.plain)
                .disabled(index == store.breadcrumb.count - 1)
            }
        }
        // SF Rounded throughout the bar: the native face that matches round tiles
        // and a soap-bubble subject, rather than the default system face.
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.primary.opacity(0.75))
        .layoutPriority(-1)
    }

    /// Jumbles the board and spins the icon with it. The tiles re-pack under
    /// `Motion.reflow`, so the rearrangement plays out rather than snapping.
    private func shuffle() {
        withAnimation(Motion.reflow) { store.shuffle() }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { shuffleSpin += 360 }
    }
}
