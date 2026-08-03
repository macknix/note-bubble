import SwiftUI

/// The top bar's visual language.
///
/// Two materials, deliberately unequal. The **glass** is deferential — it is a
/// widget floating over your work and should mostly get out of the way. The
/// **candy** is spent in exactly one place, the primary action, so there is one
/// obviously irresistible target rather than eight competing ones.
///
/// The iridescent rim is the app's own material: a soap film's oil-slick spectrum,
/// which is what a bubble's edge actually looks like. It is what stops the glass
/// reading as generic frosted chrome.
enum BarStyle {
    // MARK: Palette

    static let filmCyan = Color(red: 0.50, green: 0.85, blue: 1.00)   // #7FD8FF
    static let filmViolet = Color(red: 0.75, green: 0.55, blue: 1.00) // #C08CFF
    static let filmPeach = Color(red: 1.00, green: 0.77, blue: 0.55)  // #FFC48C

    static let candyPink = Color(red: 1.00, green: 0.30, blue: 0.55)  // #FF4D8D
    static let candyViolet = Color(red: 0.69, green: 0.29, blue: 1.00) // #B14BFF

    /// Soap-film spectrum, swept around the edge rather than across it — the
    /// hue shift should read as a curved surface catching light.
    static var iridescentRim: AngularGradient {
        AngularGradient(
            colors: [
                filmCyan.opacity(0.75), filmViolet.opacity(0.55), filmPeach.opacity(0.65),
                filmCyan.opacity(0.45), filmViolet.opacity(0.7), filmCyan.opacity(0.75)
            ],
            center: .center
        )
    }

    static var candy: LinearGradient {
        LinearGradient(
            colors: [candyPink, candyViolet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Materials

    /// The bar's substrate: frosted, with a bright top edge and an iridescent rim.
    static func glass(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                // Light falling from above, brightest along the top edge.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.02), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay { shape.strokeBorder(iridescentRim, lineWidth: 1) }
            .overlay {
                // A second, tighter white rim inside the colour keeps the edge crisp
                // at small sizes where the spectrum alone reads muddy.
                shape.inset(by: 1).strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
            .shadow(color: filmViolet.opacity(0.12), radius: 20, y: 2)
    }
}

// MARK: - Press behaviour

/// Squash-and-overshoot. The low damping is the point: a control that springs past
/// its resting size on release is the difference between "registered" and
/// "satisfying", and it costs nothing.
struct CandyPress: ButtonStyle {
    var scale: CGFloat = 0.86

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.45), value: configuration.isPressed)
    }
}
