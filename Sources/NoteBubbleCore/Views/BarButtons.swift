import SwiftUI

/// A secondary control in the top bar: a glyph on a faint glass chip.
///
/// Deliberately quiet. These are chrome — undo, mute, pin, close — and they should
/// recede so the one primary action reads instantly.
struct GlassIconButton: View {
    let systemImage: String
    let help: String
    var tint: Color?
    var isEnabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint ?? .primary.opacity(0.72))
                .frame(width: 26, height: 26)
                .background {
                    Circle()
                        .fill(.white.opacity(hovering ? 0.20 : 0.08))
                        .overlay(Circle().strokeBorder(.white.opacity(hovering ? 0.3 : 0.12), lineWidth: 0.5))
                        .allowsHitTesting(false)
                }
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(CandyPress())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .onHover { hovering = $0 && isEnabled }
        .animation(Motion.hover, value: hovering)
        .help(help)
    }
}

/// The primary action, and the only saturated thing in the bar.
///
/// Making a new note is the one creative act here; everything else is
/// housekeeping. Candy Crush's core trick is a single obviously-rewarding target,
/// so this is bigger, brighter and springier than its neighbours, and it blooms a
/// ring on release rather than just changing state.
struct CandyOrb: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @State private var bloom = false

    var body: some View {
        Button {
            action()
            bloom = true
            withAnimation(.easeOut(duration: 0.45)) { bloom = false }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: BarStyle.candyViolet.opacity(0.5), radius: 1, y: 0.5)
                .frame(width: 32, height: 32)
                .background {
                    ZStack {
                        Circle().fill(BarStyle.candy)
                        // Gloss: a bright cap in the upper third reads as a curved
                        // sweet rather than a flat disc.
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.04), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                        Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.75)
                    }
                    .allowsHitTesting(false)
                }
                .overlay {
                    Circle()
                        .strokeBorder(BarStyle.candyPink.opacity(bloom ? 0 : 0.8), lineWidth: bloom ? 0.5 : 2)
                        .scaleEffect(bloom ? 1.9 : 1)
                        .opacity(bloom ? 0 : 1)
                        .allowsHitTesting(false)
                }
                .shadow(color: BarStyle.candyPink.opacity(hovering ? 0.55 : 0.35),
                        radius: hovering ? 10 : 6, y: 2)
                .scaleEffect(hovering ? 1.09 : 1)
        }
        .buttonStyle(CandyPress(scale: 0.82))
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .help(help)
    }
}
