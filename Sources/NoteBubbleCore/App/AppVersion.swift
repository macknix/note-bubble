import Foundation

/// Which build this is, as `Scripts/build-app.sh` stamped it into the bundle.
enum AppVersion {
    /// "1.2.0", or nil when running outside an assembled bundle (`swift run`).
    static var marketing: String? { info("CFBundleShortVersionString") }
    static var build: String? { info("CFBundleVersion") }
    static var commit: String? { info("NBGitCommit") }

    /// One line for the menu: "Note Bubble 1.2.0 (42 · a1b2c3d)".
    static var summary: String {
        guard let marketing else { return "Note Bubble — development build" }
        let detail = [build, commit].compactMap { $0 }.joined(separator: " · ")
        return detail.isEmpty ? "Note Bubble \(marketing)" : "Note Bubble \(marketing) (\(detail))"
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
