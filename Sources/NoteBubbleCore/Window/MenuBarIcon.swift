import AppKit

/// The menu bar icon: the app icon's three bubbles, as a template image.
///
/// A template is drawn in one colour that macOS chooses — black on a light menu
/// bar, white on a dark one — so it uses only shape: solid bubbles, with their
/// reflections *cut out* so the bar shows through where the light catches them,
/// and a hairline gap wherever one bubble sits in front of another. Same
/// arrangement as `Scripts/make-icon.swift`; keep the two in step.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    private struct Bubble {
        let centre: CGPoint
        let radius: CGFloat
    }

    /// Back to front, as in the app icon: ageing, overdue, then the big fresh one.
    private static let bubbles = [
        Bubble(centre: CGPoint(x: 13.6, y: 12.6), radius: 3.6),
        Bubble(centre: CGPoint(x: 14.0, y: 4.4), radius: 2.4),
        Bubble(centre: CGPoint(x: 7.0, y: 7.2), radius: 5.6)
    ]

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            for bubble in bubbles { draw(bubble, in: context) }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Note Bubble"
        return image
    }

    private static func draw(_ bubble: Bubble, in context: NSGraphicsContext) {
        let c = bubble.centre, r = bubble.radius

        // Clear a ring round it first, so it stands apart from any bubble behind.
        context.compositingOperation = .clear
        circle(c, r + 0.9).fill()

        context.compositingOperation = .sourceOver
        NSColor.black.setFill()
        circle(c, r).fill()

        // The reflection and its glint, cut out of the bubble.
        context.compositingOperation = .clear
        let streak = NSBezierPath()
        streak.appendArc(withCenter: c, radius: r * 0.62, startAngle: 110, endAngle: 168)
        streak.lineWidth = max(r * 0.2, 0.75)
        streak.lineCapStyle = .round
        streak.stroke()
        let glintAngle = 92 * CGFloat.pi / 180
        circle(CGPoint(x: c.x + cos(glintAngle) * r * 0.62, y: c.y + sin(glintAngle) * r * 0.62),
               max(r * 0.12, 0.45)).fill()
        context.compositingOperation = .sourceOver
    }

    private static func circle(_ centre: CGPoint, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
}
