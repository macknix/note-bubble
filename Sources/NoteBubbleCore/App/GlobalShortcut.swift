import Foundation

/// The shortcut that opens Note Bubble from anywhere: which one it is, whether
/// macOS actually gave it to us, and changing it.
///
/// It used to be ⌥Space, fixed — a combination the ChatGPT app, Raycast and Alfred
/// set-ups and some input-source switchers also claim. When registering failed the
/// shortcut silently did nothing. Now the combination is remembered, the menu bar
/// says when it is taken, and it can be recorded afresh.
@MainActor
final class GlobalShortcut: ObservableObject {
    @Published private(set) var combo: KeyCombo
    /// False when macOS refused the combination — another app has it.
    @Published private(set) var isRegistered = false

    private let hotKey: HotKey
    private let defaults: UserDefaults
    private static let defaultsKey = "GlobalShortcut"

    init(defaults: UserDefaults = .standard, action: @escaping () -> Void) {
        self.defaults = defaults
        self.hotKey = HotKey(action: action)
        self.combo = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .standard
        isRegistered = hotKey.register(combo)
    }

    /// Switches to `new`, keeping it only if macOS accepts it. On refusal the
    /// previous shortcut goes back, and false says why the change did not stick.
    @discardableResult
    func change(to new: KeyCombo) -> Bool {
        guard hotKey.register(new) else {
            isRegistered = hotKey.register(combo)
            return false
        }
        combo = new
        isRegistered = true
        if let data = try? JSONEncoder().encode(new) { defaults.set(data, forKey: Self.defaultsKey) }
        return true
    }

    /// Stops listening while a new shortcut is being recorded, so pressing the
    /// current one to re-record it does not fold the panel away mid-recording.
    func pause() {
        hotKey.unregister()
    }

    func resume() {
        isRegistered = hotKey.register(combo)
    }
}
