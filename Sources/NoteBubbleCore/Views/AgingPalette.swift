import SwiftUI

/// What ageing looks like: the colour a note is at any age, and the colour that
/// stands for each stage.
///
/// Split from `Aging` so the model holds the rules and nothing else — it never
/// imports SwiftUI. Ageing hues are reserved for *meaning* and never used
/// decoratively; see `BarStyle`.
enum AgingPalette {
    /// Hue sweeps 0.33 (green) → 0.0 (red). Halfway through the week lands on amber.
    static func color(forDays days: Double) -> Color {
        Color(hue: hue(forDays: days), saturation: 0.72, brightness: 0.92)
    }

    /// Deeper shade of the same hue, for the gradient's far corner and for text
    /// that sits on a white chip over the tile.
    static func shadeColor(forDays days: Double) -> Color {
        Color(hue: hue(forDays: days), saturation: 0.88, brightness: 0.66)
    }

    /// The colour that stands for a whole stage — a count badge, a workspace dot.
    static func color(for stage: Aging.Stage) -> Color {
        color(forDays: representativeDays(of: stage))
    }

    static func shadeColor(for stage: Aging.Stage) -> Color {
        shadeColor(forDays: representativeDays(of: stage))
    }

    private static func hue(forDays days: Double) -> Double {
        0.33 * (1 - Aging.progress(forDays: days))
    }

    /// Where in the week each stage's colour is taken from. Fresh is the green a
    /// note starts at, overdue the red it ends at, and ageing a point inside its
    /// window that reads unmistakably amber.
    private static func representativeDays(of stage: Aging.Stage) -> Double {
        switch stage {
        case .fresh: 0
        case .aging: (Aging.agingAfterDays + Aging.redAfterDays) / 2
        case .overdue: Aging.redAfterDays
        }
    }
}
