import ServiceManagement
import os

/// "Open at login", through `SMAppService` — no helper app, no launch agent plist.
///
/// macOS can hold the request for the user's approval (`requiresApproval`), in
/// which case the only way forward is System Settings, so that is where asking
/// sends you. The registration is tied to the app's signature: an ad-hoc signed
/// build that is replaced by a newer one may need turning on again.
@MainActor
enum LoginItem {
    private static let logger = Logger(subsystem: "com.macknixon.notebubble", category: "login-item")

    enum State {
        case off
        case on
        /// Asked for, but waiting on the user in System Settings → Login Items.
        case awaitingApproval
        /// Not running from an app bundle (`swift run`), where there is nothing
        /// to register.
        case unavailable
    }

    static var state: State {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .awaitingApproval
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }

    /// Turns it on or off. Turning it on may leave it awaiting approval, in which
    /// case System Settings is opened at the right page.
    static func toggle() {
        do {
            switch state {
            case .on, .awaitingApproval:
                try SMAppService.mainApp.unregister()
            case .off:
                try SMAppService.mainApp.register()
            case .unavailable:
                return
            }
        } catch {
            logger.error("Could not change the login item: \(error)")
        }
        if state == .awaitingApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
