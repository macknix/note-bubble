import SwiftUI

/// The panel's top bar: one glass slab carrying status, place, and controls.
///
/// Replaces a stacked grip-strip-plus-header, which spent 72pt of vertical space
/// and gave the drag handle nothing to say. One row reads as a single object,
/// which is what the glass wants to be.
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
        HStack(spacing: 8) {
            StatusHandle(counts: store.stageCounts, drag: drag)

            if !store.isAtRoot {
                GlassIconButton(systemImage: "chevron.left", help: "Back", action: store.goUp)
            }

            breadcrumb

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
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            // Undo appears only when there is something to undo — a permanently
            // greyed-out control is clutter that never earns its place.
            if store.canUndo {
                GlassIconButton(
                    systemImage: "arrow.uturn.backward",
                    help: store.undoLabel.map { "Undo popping “\($0)” (⌘Z)" } ?? "Undo (⌘Z)",
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
        .animation(Motion.lift, value: store.canUndo)
        .animation(Motion.lift, value: store.visible.count > 1)
    }

    /// Jumbles the board and spins the icon with it. The tiles re-pack under
    /// `Motion.reflow`, so the rearrangement plays out rather than snapping.
    private func shuffle() {
        withAnimation(Motion.reflow) { store.shuffle() }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { shuffleSpin += 360 }
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
        .frame(maxWidth: 150, alignment: .leading)
    }
}
