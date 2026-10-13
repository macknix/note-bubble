import SwiftUI

/// A note as a tile, and nothing else: the glass, the label and the footer, sized,
/// clipped and lifted. It has no state and takes no input.
///
/// This is what the tile in the air (`BubbleGrid+Drag`) and another board's tiles
/// (`WorkspacePreview`) draw. `BubbleTile` puts the same face under the pointer and
/// adds what only a live tile on the board needs: hovering, renaming, editing.
///
/// Gestures live in `BubbleGrid`, which arbitrates tap vs hold vs drag centrally.
/// `pressProgress` is how far through a pop-hold this tile is (0…1); the swell it
/// drives is the feedback that tells you the tile is about to burst.
struct TileFace<Content: View>: View {
    let node: BubbleNode
    let size: CGSize
    /// What time it is, for the age — `BubbleStore.now`, never `Date()`.
    let now: Date
    var isDragging = false
    var pressProgress: CGFloat = 0
    /// What sits on the glass: the label, or the editor while typing.
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            face
            content
        }
        .frame(width: size.width, height: size.height)
        // Measured to fit, but rounding to the height step can leave a hair too
        // little; clipping guarantees a tile can never spill past its own frame the
        // way it did when the text was free to push the height out.
        .clipShape(TileStyle.shape(for: size))
        // The swell during a pop-hold, plus a small lift while dragging.
        .scaleEffect(1 + pressProgress * 0.22 + (isDragging ? 0.08 : 0))
        .rotationEffect(.degrees(Double(pressProgress) * 1.5))
        // A darker drop shadow than before: with no panel background, tiles need
        // their own separation from whatever is on screen behind them.
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0.3),
                radius: isDragging ? 16 : 7,
                y: isDragging ? 8 : 3)
        .animation(Motion.lift, value: isDragging)
    }

    private var days: Double { node.ageInDays(at: now) }
    private var tint: Color { AgingPalette.color(forDays: days) }
    private var shade: Color { AgingPalette.shadeColor(forDays: days) }

    /// Layered to read as coloured glass rather than a flat swatch: a frosted
    /// substrate that picks up the desktop behind the panel, a translucent tint on
    /// top, a bright rim that catches light unevenly, and a specular streak.
    private var face: some View {
        let shape = TileStyle.shape(for: size)

        return shape
            // Fully opaque: the panel behind is transparent, so the tile is the
            // only thing giving the label something to sit on. Glass here comes
            // from the highlights below, not from letting the desktop through.
            .fill(
                LinearGradient(
                    colors: [tint, shade],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                // Rim light: bright top-left, almost gone by the bottom-right, which
                // is what sells a curved glass edge.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.18), .white.opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
            }
            .overlay {
                // Specular highlight, clipped to the top third.
                shape
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask {
                        Ellipse()
                            .frame(width: size.width * 1.35, height: size.height * 0.55)
                            .offset(y: -size.height * 0.32)
                            .blur(radius: 5)
                    }
            }
            .overlay {
                // A thin bright streak near the bottom edge, like light refracting
                // through the far wall of the glass.
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: size.width * 0.44, height: 2.5)
                    .blur(radius: 2)
                    .offset(y: size.height * 0.34)
            }
            .compositingGroup()
    }
}

extension TileFace where Content == TileLabel {
    /// The face as it reads at rest: the note's text and its footer.
    init(node: BubbleNode, size: CGSize, now: Date, isDragging: Bool = false, pressProgress: CGFloat = 0) {
        self.init(node: node, size: size, now: now, isDragging: isDragging, pressProgress: pressProgress) {
            TileLabel(node: node, now: now)
        }
    }
}

/// A note's text, with its age and sub-bubble count in a footer underneath.
struct TileLabel: View {
    let node: BubbleNode
    let now: Date

    private var shade: Color { AgingPalette.shadeColor(forDays: node.ageInDays(at: now)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.displayName)
                .font(.system(size: TileText.fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                // No line limit: the tile was measured to fit this text in
                // full, so clamping here would defeat the sizing.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 0.5)

            Spacer(minLength: 0)

            // Age and sub-bubble count share a footer row. The count used to
            // float in the top-right corner, which collided with left-aligned
            // text on the first line.
            HStack(spacing: 4) {
                // Overdue says so in a shape as well as a colour, for anyone who
                // cannot tell this red from the green it started as.
                if Aging.stage(forDays: node.ageInDays(at: now)) == .overdue {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.trailing, -2)
                }
                Text(Aging.relativeAge(from: node.createdAt, now: now))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                if !node.children.isEmpty {
                    Text("\(node.children.count)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(shade)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 13)
                        .background(Capsule().fill(.white.opacity(0.92)))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 1.5)
        }
        .padding(.horizontal, TileText.horizontalInset)
        .padding(.vertical, 9)
    }
}
