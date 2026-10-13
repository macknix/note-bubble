import AppKit

/// Tells the store when time has passed, so ages keep moving on a widget nobody is
/// touching.
///
/// Ageing is measured against `BubbleStore.now`, and nothing else re-renders a
/// board left alone — so without this, a note would sit green on the pill all night
/// and still be green in the morning. Ages are whole days and stages flip at day
/// boundaries, so a coarse tick is plenty; the notifications catch the two moments
/// a tick could otherwise lag by a whole interval: waking from sleep, and midnight.
@MainActor
final class AgeClock {
    /// Often enough that a note turns colour within minutes of crossing a
    /// boundary, rarely enough to cost nothing.
    static let interval: TimeInterval = 10 * 60

    private let tick: () -> Void
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(tick: @escaping () -> Void) {
        self.tick = tick

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Precision is irrelevant here; letting the system coalesce saves power.
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observe(NSWorkspace.didWakeNotification, on: NSWorkspace.shared.notificationCenter)
        observe(.NSCalendarDayChanged, on: .default)
        observe(.NSSystemClockDidChange, on: .default)
    }

    deinit {
        timer?.invalidate()
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        observers.append((center, token))
    }
}
