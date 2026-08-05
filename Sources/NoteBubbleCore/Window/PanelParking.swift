import AppKit

/// Where the panel rests, and therefore what frame it takes at any size.
///
/// Everything about position lives here: the parked corner, the screen it belongs
/// to, edge magnetism, and remembering it all across launches. `PanelController`
/// owns *when* the panel changes size; this owns *where* it ends up. The two are
/// separable because nothing here needs to know whether the panel is showing a pill
/// or a grid — only how big it wants to be.
///
/// The rules it enforces are in `PanelPlacement.swift`, which is plain geometry over
/// rectangles and is where they are tested. This type is the wiring: `NSScreen` in,
/// `UserDefaults` out.
@MainActor
final class PanelParking {
    /// Where the **pill** rests, and which way the panel opens from it.
    ///
    /// The pill is the resting state, so it is the thing that must never appear to
    /// move; every other size is derived from this corner. Deriving it the other way
    /// round — reading the corner back off the panel's current frame — is what let it
    /// drift: an expanded panel too tall for the room around it gets clamped on
    /// screen, and a corner taken from the clamped frame is a corner that has moved.
    private(set) var placement: PanelPlacement

    private let defaults: UserDefaults
    private static let defaultsKey = "PanelPlacement"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.placement = Self.restored(from: defaults) ?? Self.firstRun()
    }

    // MARK: - Frames

    /// The frame a panel of `size` should occupy: hung off the parked corner, and
    /// pulled back on screen if it doesn't fit.
    ///
    /// Clamping here is presentational and deliberately does **not** feed back into
    /// `placement`. A tall panel that had to be nudged up the screen still folds back
    /// to the corner its pill was parked on.
    func frame(sized size: NSSize) -> NSRect {
        clamped(placement.anchor.frame(size: size, at: placement.corner))
    }

    /// Pulls a frame back onto whichever screen it is mostly on.
    func clamped(_ frame: NSRect) -> NSRect {
        guard let visible = Self.screen(for: frame)?.visibleFrame else { return frame }
        return PanelGeometry.clamped(frame, in: visible)
    }

    /// Edge magnetism for a frame mid-drag: screen edges pull it flush once it comes
    /// close, so the panel can be parked exactly in a corner without pixel-hunting.
    func snapping(_ frame: NSRect) -> NSRect {
        guard let screen = Self.screen(for: frame) else { return frame }
        return PanelGeometry.snapped(
            frame,
            in: screen.visibleFrame,
            edges: PanelGeometry.openEdges(of: screen.frame, among: Self.otherScreenFrames(than: screen))
        )
    }

    /// Whether a frame still lands on a display that exists — false after the screen
    /// it was parked on has been unplugged.
    func isOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    // MARK: - Parking

    /// The pill was dropped here. Nearest corner wins on both axes, which is what
    /// puts it in a corner in the first place.
    func park(pill frame: NSRect) {
        park(PanelPlacement(pill: frame, in: visibleFrame(for: frame)))
    }

    /// The expanded panel was dropped here. Parks by its top edge whatever half of
    /// the screen it landed in — the bar is the handle, so the panel has to fold up
    /// towards the thing under the cursor.
    func park(draggedPanel frame: NSRect) {
        park(PanelPlacement(draggedPanel: frame, in: visibleFrame(for: frame)))
    }

    /// The pill came to rest here after a resize, keeping its anchor.
    ///
    /// Normally a no-op: `frame(sized:)` already puts it on the parked corner. It
    /// matters in the one case where the two differ — a corner that no longer fits
    /// on any screen, so the pill had to be clamped back on. Where it actually
    /// landed then becomes where it lives.
    func park(settledPill frame: NSRect) {
        park(PanelPlacement(corner: placement.anchor.corner(of: frame), anchor: placement.anchor))
    }

    private func park(_ placement: PanelPlacement) {
        self.placement = placement
        guard let data = try? JSONEncoder().encode(placement) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: - Screens

    private func visibleFrame(for frame: NSRect) -> NSRect {
        Self.screen(for: frame)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
    }

    /// The screen a frame is mostly on — not necessarily the one it started on, and
    /// not `panel.screen`, which is nil while the panel is hidden.
    private static func screen(for frame: NSRect) -> NSScreen? {
        let overlapping = NSScreen.screens.filter { $0.frame.intersects(frame) }
        let best = overlapping.max { a, b in
            let left = a.frame.intersection(frame), right = b.frame.intersection(frame)
            return left.width * left.height < right.width * right.height
        }
        return best ?? NSScreen.main
    }

    private static func otherScreenFrames(than screen: NSScreen) -> [CGRect] {
        NSScreen.screens.filter { $0 !== screen }.map(\.frame)
    }

    // MARK: - Persistence

    /// Nil if there is no stored placement, or if it points at a display that is no
    /// longer attached — reopening onto a screen that isn't there would strand the
    /// panel somewhere invisible.
    private static func restored(from defaults: UserDefaults) -> PanelPlacement? {
        guard let data = defaults.data(forKey: defaultsKey),
              let placement = try? JSONDecoder().decode(PanelPlacement.self, from: data)
        else { return nil }
        // Insets outwards because an anchored corner sits exactly *on* the screen
        // edge, which `CGRect.contains` counts as outside.
        let onScreen = NSScreen.screens.contains {
            $0.frame.insetBy(dx: -4, dy: -4).contains(placement.corner)
        }
        return onScreen ? placement : nil
    }

    /// First run: top-right, clear of the corner so the shadow reads.
    private static func firstRun() -> PanelPlacement {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return PanelPlacement(
            corner: NSPoint(x: visible.maxX - 40, y: visible.maxY - 40),
            anchor: .topRight
        )
    }
}
