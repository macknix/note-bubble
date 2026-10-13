import Foundation

/// How many notes are at each stage of ageing — one walk of a tree, no copies.
///
/// Every count in the app is one of these: the status handle's three badges (this
/// board), the pill and menu bar (every board), a workspace dot's colour and
/// tooltip, the menu bar's per-board breakdown. They used to be four separate
/// functions, each flattening the tree into a fresh array, and the all-boards total
/// flattened every board twice.
struct StageTally: Equatable {
    var fresh = 0
    var aging = 0
    var overdue = 0

    var total: Int { fresh + aging + overdue }

    /// The worst state anything here has reached, or nil when there is nothing.
    var worst: Aging.Stage? {
        if overdue > 0 { return .overdue }
        if aging > 0 { return .aging }
        if fresh > 0 { return .fresh }
        return nil
    }

    init(fresh: Int = 0, aging: Int = 0, overdue: Int = 0) {
        self.fresh = fresh
        self.aging = aging
        self.overdue = overdue
    }

    init(of notes: [BubbleNode], at now: Date) {
        notes.forEachNode { add(Aging.stage(forDays: $0.ageInDays(at: now))) }
    }

    mutating func add(_ stage: Aging.Stage) {
        switch stage {
        case .fresh: fresh += 1
        case .aging: aging += 1
        case .overdue: overdue += 1
        }
    }

    static func + (lhs: StageTally, rhs: StageTally) -> StageTally {
        var sum = lhs
        sum.fresh += rhs.fresh
        sum.aging += rhs.aging
        sum.overdue += rhs.overdue
        return sum
    }
}
