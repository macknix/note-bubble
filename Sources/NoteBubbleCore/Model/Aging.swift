import Foundation

/// Traffic-light ageing. A note starts green and slides continuously through amber
/// to red over a week, so the buckets below read as smooth decay rather than three
/// discrete jumps. `Stage` exists only for things that need a hard answer, like the
/// overdue badge on the minimised pill.
///
/// The *rules* only. What the stages look like is `AgingPalette`, in Views: the
/// model knows nothing of colour, which is what keeps it testable without SwiftUI.
enum Aging {
    /// Days at which a note stops being fresh and starts to amber.
    static let agingAfterDays: Double = 3
    /// Days at which a note is fully red. 0–2 reads green, 3–6 amber, 7+ red.
    static let redAfterDays: Double = 7

    enum Stage {
        case fresh   // 0–2 days
        case aging   // 3–6 days
        case overdue // 7 days and beyond
    }

    static func stage(forDays days: Double) -> Stage {
        switch days {
        case ..<agingAfterDays: .fresh
        case ..<redAfterDays: .aging
        default: .overdue
        }
    }

    /// Position through the ageing window, 0 (fresh) to 1 (red), clamped so a note
    /// months old looks exactly like one a week old rather than wrapping back
    /// through the hue circle to green.
    static func progress(forDays days: Double) -> Double {
        let t = min(max(days / redAfterDays, 0), 1)
        return pow(t, 0.85) // spend slightly longer looking urgent than fresh
    }

    static func relativeAge(from date: Date, now: Date) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case ..<7: return "\(days)d"
        // Weeks run to 30 days so the month count never starts at zero: 28 and 29
        // days used to read "0mo".
        case ..<30: return "\(days / 7)w"
        case ..<365: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }
}
