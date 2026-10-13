import SwiftUI

/// Every animation and delay in the app, in one place.
///
/// These were previously inline literals repeated across the views, which made
/// the interface feel subtly inconsistent — two springs that should have matched
/// had drifted apart. Tune the feel here, not at the call sites.
enum Motion {
    // MARK: Animations

    /// Tiles settling into new slots during a rearrange.
    static let reflow = Animation.spring(response: 0.34, dampingFraction: 0.74)
    /// A tile changing size as its note is written.
    static let resize = Animation.spring(response: 0.3, dampingFraction: 0.78)
    /// Picking a tile up and putting it down.
    static let lift = Animation.spring(response: 0.3, dampingFraction: 0.7)
    /// Hover highlights and other small reveals.
    static let hover = Animation.easeOut(duration: 0.14)
    /// Overlays arriving and leaving.
    static let overlay = Animation.easeOut(duration: 0.16)
    /// The toast sliding up from the bottom edge.
    static let toast = Animation.spring(response: 0.32, dampingFraction: 0.8)

    // MARK: Durations

    /// How long a tile must be held before it bursts.
    static let popHold: Duration = .milliseconds(550)
    /// How long the burst particles live. Slightly longer than the burst's own
    /// animation so nothing is culled mid-flight.
    static let burstLifetime: Duration = .milliseconds(500)
    /// How long the undo toast stays up.
    static let toastLifetime: Duration = .seconds(4)
    /// How long a dragged tile must rest on a workspace dot before that board slides
    /// into view behind it. Short enough to feel like a consequence of stopping,
    /// long enough that crossing one dot on the way to another doesn't flick through
    /// every board in between.
    static let workspacePreview: Duration = .milliseconds(260)

    // MARK: The window

    /// Dwell before the pill opens under the pointer — see `HoverIntent`.
    static let expandDelay: Duration = .milliseconds(180)
    /// Grace before an unhovered panel folds back to the pill.
    static let collapseDelay: Duration = .milliseconds(450)
    /// Window alpha changes, toward the pointer and away from it. AppKit
    /// animations, so plain seconds.
    static let windowFadeIn: TimeInterval = 0.12
    static let windowFadeOut: TimeInterval = 0.3
    /// The panel growing or shrinking to fit what is on it.
    static let windowResize: TimeInterval = 0.22
    /// The pill sliding flush against an edge after it is dropped.
    static let pillSnap: TimeInterval = 0.12
}

extension Duration {
    /// For the animation APIs, which still count in `Double` seconds — so a delay
    /// and the animation that runs alongside it are written once, as a `Duration`.
    var seconds: Double {
        let (whole, fraction) = components
        return Double(whole) + Double(fraction) / 1e18
    }
}
