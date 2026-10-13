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

        /// The stage in words, for anything that cannot rely on colour.
        var name: String {
            switch self {
            case .fresh: "fresh"
            case .aging: "ageing"
            case .overdue: "overdue"
            }
        }
    }

    /// On the standard one-week window. Boards can set their own — see `AgeWindow`.
    static func stage(forDays days: Double) -> Stage {
        AgeWindow.standard.stage(forDays: days)
    }

    static func progress(forDays days: Double) -> Double {
        AgeWindow.standard.progress(forDays: days)
    }

    /// The age read aloud — what VoiceOver says where a tile shows "3d".
    static func spokenAge(from date: Date, now: Date) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s") old" }
        switch days {
        case ..<1: return "written today"
        case 1: return "written yesterday"
        case ..<7: return plural(days, "day")
        case ..<30: return plural(days / 7, "week")
        case ..<365: return plural(days / 30, "month")
        default: return plural(days / 365, "year")
        }
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

/// How long the notes on one board take to go from fresh to overdue.
///
/// A week suits most boards, and a board of slow-burning projects would be red
/// end to end by Wednesday. Each workspace can set its own; the whole traffic
/// light stretches to fit, keeping the standard week's proportions — fresh for the
/// first three-sevenths, ageing until the end, overdue after.
struct AgeWindow: Codable, Hashable {
    var overdueAfterDays: Double

    static let standard = AgeWindow(overdueAfterDays: Aging.redAfterDays)

    /// What the workspace menu offers.
    static let presets: [AgeWindow] = [3, 7, 14, 30, 90].map { AgeWindow(overdueAfterDays: $0) }

    /// When a note on this board stops being fresh.
    var agingAfterDays: Double {
        overdueAfterDays * Aging.agingAfterDays / Aging.redAfterDays
    }

    func stage(forDays days: Double) -> Aging.Stage {
        switch days {
        case ..<agingAfterDays: .fresh
        case ..<overdueAfterDays: .aging
        default: .overdue
        }
    }

    /// Position through the window, 0 (fresh) to 1 (red), clamped so a note long
    /// past it looks exactly like one just past it rather than wrapping back
    /// through the hue circle to green.
    func progress(forDays days: Double) -> Double {
        let t = min(max(days / overdueAfterDays, 0), 1)
        return pow(t, 0.85) // spend slightly longer looking urgent than fresh
    }

    /// "1 week", "3 months" — for the menu.
    var label: String {
        let days = Int(overdueAfterDays)
        switch days {
        case 7: return "1 week"
        case let d where d % 30 == 0: return d == 30 ? "1 month" : "\(d / 30) months"
        case let d where d % 7 == 0: return "\(d / 7) weeks"
        default: return days == 1 ? "1 day" : "\(days) days"
        }
    }
}

