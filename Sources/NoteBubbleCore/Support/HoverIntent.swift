import Foundation

/// Decides when the pill opens under the pointer and when the panel folds back.
///
/// The whole interaction model of the widget, and the same split as `TileGesture`
/// and `WorkspaceSwipe`: the rules here, the clock and the window in
/// `PanelController`. It owns no timers — the caller schedules the delays it asks
/// for and reports back when they elapse — so every rule can be checked without
/// waiting or a pointer.
///
/// The rules, each one a fix:
///
/// - **Expanding waits for a dwell** (`Motion.expandDelay`), so sweeping the pointer
///   past the pill on the way somewhere else doesn't throw the grid open.
/// - **Collapsing waits for a grace period** (`Motion.collapseDelay`), so
///   overshooting an edge doesn't close it.
/// - **Each cancels the other.** Coming back within the grace keeps the panel open.
/// - **Collapse re-checks its vetoes when it fires, not when it is scheduled.**
///   Pinning, starting to type or opening a confirmation during the grace period
///   must all still hold the panel open.
/// - **Hover never takes focus** — that is `PanelController.expand(takeFocus:)`'s
///   business, but it is why `.expand` here carries no focus.
enum HoverIntent {
    enum Event: Equatable {
        case entered
        case left
        case expandDelayElapsed
        case collapseDelayElapsed
    }

    /// What the controller knows at the moment an event arrives.
    struct Situation: Equatable {
        var isMinimised: Bool
        var isPinned = false
        /// A note or a workspace name is being typed into.
        var isEditing = false
        /// `PanelState.blocksAutoCollapse`: a drag or a confirmation is in progress.
        var isHeld = false
    }

    enum Effect: Equatable {
        case scheduleExpand
        case cancelExpand
        case scheduleCollapse
        case cancelCollapse
        /// Open the panel, without taking keyboard focus.
        case expand
        case minimise
    }

    static func effects(for event: Event, in situation: Situation) -> [Effect] {
        switch event {
        case .entered:
            return situation.isMinimised ? [.cancelCollapse, .scheduleExpand] : [.cancelCollapse]

        case .left:
            // Only an open, unpinned panel has anything to fold away.
            guard !situation.isMinimised, !situation.isPinned else { return [.cancelExpand] }
            return [.cancelExpand, .scheduleCollapse]

        case .expandDelayElapsed:
            return situation.isMinimised ? [.expand] : []

        case .collapseDelayElapsed:
            guard !situation.isMinimised,
                  !situation.isPinned,
                  !situation.isEditing,
                  !situation.isHeld
            else { return [] }
            return [.minimise]
        }
    }
}
