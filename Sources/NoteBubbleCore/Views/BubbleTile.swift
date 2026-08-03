import SwiftUI

/// One note as a rounded-square tile, coloured by age.
///
/// It renders only — every gesture lives in `BubbleGrid`, which needs to arbitrate
/// tap vs long-press vs drag centrally. `pressProgress` is how far through a
/// pop-hold this tile is (0…1); the swell it drives is the feedback that tells you
/// the tile is about to burst.
struct BubbleTile: View {
    let node: BubbleNode
    let size: CGSize
    let isEditing: Bool
    let isDragging: Bool
    let pressProgress: CGFloat
    let onCommit: (String) -> Void
    let onFinish: () -> Void
    let onRename: () -> Void

    @State private var hovering = false
    @State private var draft = ""
    /// What the note said when editing began, so Escape can put it back.
    @State private var original = ""
    @FocusState private var focused: Bool

    private var days: Double { node.ageInDays }
    private var tint: Color { Aging.color(forDays: days) }
    private var shade: Color { Aging.shadeColor(forDays: days) }

    var body: some View {
        ZStack {
            face
            content
            if hovering && !isEditing && !isDragging { renameButton }
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
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        .animation(Motion.lift, value: isDragging)
    }

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

    @ViewBuilder
    private var content: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 3) {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    // Matches the display alignment, so text doesn't jump when
                    // editing ends.
                    .multilineTextAlignment(.leading)
                    .font(.system(size: TileText.fontSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($focused)
                    .lineLimit(5)
                    .onAppear {
                        draft = node.text
                        original = node.text
                        focused = true
                    }
                    // Text is written through on every keystroke, so "finishing" is
                    // only ever about dropping focus — nothing is pending a save.
                    //
                    // Explicitly animated: the tile's size is derived from this
                    // text, and a bare store mutation carries no transaction, so
                    // the tile would otherwise jump a step per character.
                    .onChange(of: draft) { _, new in
                        withAnimation(Motion.resize) { onCommit(new) }
                    }
                    // Return finishes. Shift-Return is the escape hatch for a second
                    // line, which is why the field stays vertical-axis.
                    .onKeyPress(keys: [.return]) { press in
                        guard !press.modifiers.contains(.shift) else { return .ignored }
                        onFinish()
                        return .handled
                    }
                    .onKeyPress(keys: [.escape]) { _ in
                        onCommit(original)
                        onFinish()
                        return .handled
                    }

                Text("⏎ done")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, TileText.horizontalInset)
        } else {
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
                    Text(Aging.relativeAge(from: node.createdAt))
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

    private var renameButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: onRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(shade)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white.opacity(0.9)))
                }
                .buttonStyle(.plain)
                .help("Rename")
            }
            Spacer()
        }
        .padding(5)
        .transition(.opacity)
    }
}
