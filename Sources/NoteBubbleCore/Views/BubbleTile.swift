import SwiftUI

/// A live tile on the board: `TileFace`, plus what only a tile you can touch needs —
/// a rename button on hover, and the text field while it is being written.
///
/// It still renders only; every gesture lives in `BubbleGrid`.
struct BubbleTile: View {
    let node: BubbleNode
    let size: CGSize
    /// What time it is, for the age — `BubbleStore.now`, never `Date()`.
    let now: Date
    let window: AgeWindow
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

    private var shade: Color { AgingPalette.shadeColor(forDays: node.ageInDays(at: now), in: window) }

    var body: some View {
        TileFace(node: node, size: size, now: now, window: window, isDragging: isDragging, pressProgress: pressProgress) {
            if isEditing {
                editor
            } else {
                TileLabel(node: node, now: now, window: window)
            }
            if hovering && !isEditing && !isDragging { renameButton }
        }
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
        // One element for VoiceOver, read as the note and then its state. While
        // editing, the text field has to be reachable on its own, so it is left be.
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityLabel(node.displayName)
        .accessibilityValue(spokenState)
        .accessibilityHint("Actions open, rename, move or pop it")
    }

    /// "3 days old, ageing, 2 sub-bubbles" — colour and the little "3d" in words.
    private var spokenState: String {
        let stage = window.stage(forDays: node.ageInDays(at: now))
        var parts = [Aging.spokenAge(from: node.createdAt, now: now), stage.name]
        let inside = node.children.count
        if inside > 0 { parts.append(inside == 1 ? "1 sub-bubble" : "\(inside) sub-bubbles") }
        return parts.joined(separator: ", ")
    }

    private var editor: some View {
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
                // As many lines as the tallest tile shows. Past that the field
                // scrolls, keeping the caret in view; a fixed 5 left most of a
                // tall tile empty while the text scrolled inside it.
                .lineLimit(TileText.editorLineLimit)
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
