import SwiftUI

/// Traffic-light ageing. A note starts green and slides continuously through amber
/// to red over a week, so the buckets below read as smooth decay rather than three
/// discrete jumps. `Stage` exists only for things that need a hard answer, like the
/// overdue badge on the minimised pill.
enum Aging {
    /// Days at which a note is fully red. 0–2 reads green, 3–6 amber, 7+ red.
    static let redAfterDays: Double = 7

    enum Stage {
        case fresh   // 0–2 days
        case aging   // 3–6 days
        case overdue // 7 days and beyond
    }

    static func stage(forDays days: Double) -> Stage {
        switch days {
        case ..<3: .fresh
        case ..<redAfterDays: .aging
        default: .overdue
        }
    }

    /// Position through the ageing window, 0 (fresh) to 1 (red), clamped so a note
    /// months old looks exactly like one a week old rather than wrapping back
    /// through the hue circle to green.
    private static func progress(forDays days: Double) -> Double {
        let t = min(max(days / redAfterDays, 0), 1)
        return pow(t, 0.85) // spend slightly longer looking urgent than fresh
    }

    /// Hue sweeps 0.33 (green) → 0.0 (red). Halfway through the week lands on amber.
    static func color(forDays days: Double) -> Color {
        Color(hue: 0.33 * (1 - progress(forDays: days)), saturation: 0.72, brightness: 0.92)
    }

    /// Deeper shade of the same hue, for the gradient's far corner and for text
    /// that sits on a white chip over the tile.
    static func shadeColor(forDays days: Double) -> Color {
        Color(hue: 0.33 * (1 - progress(forDays: days)), saturation: 0.88, brightness: 0.66)
    }

    static func relativeAge(from date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<7: return "\(days)d"
        case ..<28: return "\(days / 7)w"
        default: return "\(days / 30)mo"
        }
    }
}
