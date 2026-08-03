import AppKit

/// The one public entry point into the core library.
///
/// The executable target is deliberately nothing but a call to this, so every
/// piece of real logic sits in a library the test target can import.
public enum NoteBubbleApp {
    /// Configures and runs the application. Never returns.
    @MainActor
    public static func launch() -> Never {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Set before any window exists, otherwise the app flashes a Dock icon.
        app.setActivationPolicy(.accessory)
        app.run()
        // `NSApplication.run()` only returns after `terminate`, which exits the
        // process itself; this satisfies the compiler's `Never` requirement.
        exit(0)
    }
}
