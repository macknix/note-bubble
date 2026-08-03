import SwiftUI

/// Shared geometry for a tile's shape, so the tile and the burst that replaces it
/// cannot drift apart.
enum TileStyle {
    /// Corner radius as a fraction of the tile's *shorter* side — an iOS-ish
    /// squircle proportion. Taken from the shorter side so a tall tile keeps the
    /// same corner as a small one instead of turning into a lozenge.
    static let cornerRatio: CGFloat = 0.26
    static let maximumCorner: CGFloat = 26

    static func cornerRadius(for size: CGSize) -> CGFloat {
        min(min(size.width, size.height) * cornerRatio, maximumCorner)
    }

    static func shape(for size: CGSize) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius(for: size), style: .continuous)
    }
}
