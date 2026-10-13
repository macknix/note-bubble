import AppKit

/// Type metrics for a tile's label, and the measurement that decides how big a
/// tile has to be to show its note in full.
///
/// The font is a **fixed** size rather than scaling with the tile. Scaling type
/// with the tile is self-defeating: a bigger tile would show bigger text and so
/// fit barely more of it, and no size would ever be "enough".
enum TileText {
    static let fontSize: CGFloat = 11
    static var font: NSFont { .systemFont(ofSize: fontSize, weight: .semibold) }

    /// Padding inside a tile, left and right of the label.
    static let horizontalInset: CGFloat = 9
    /// Everything vertical that is not label: top and bottom padding, the footer
    /// row carrying the age and the sub-bubble count, and the gap above it.
    static let verticalChrome: CGFloat = 34

    /// How many lines the note editor shows before it scrolls: as many as fit in
    /// the tallest tile, so editing a long note uses the room the tile has.
    static let editorLineLimit: Int = {
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return max(1, Int((GridLayout.maximumHeight - verticalChrome) / lineHeight))
    }()

    /// Rendered height of `text` wrapped to `width`.
    static func height(of text: String, boundedBy width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        // Rounded up, plus a point of slack: SwiftUI's layout of the same string
        // can differ from AppKit's by a hair, and under-measuring truncates.
        return ceil(rect.height) + 1
    }
}
