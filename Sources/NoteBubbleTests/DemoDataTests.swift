import Foundation
@testable import NoteBubbleCore

/// `Scripts/demo-data.py` is the standing test board, and CLAUDE.md promises things
/// about it. This holds it to them — through the app's own loader, so a change to
/// the file format that the script was not updated for fails here.
@MainActor
enum DemoDataTests {
    private static func generate() -> Data? {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/demo-data.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "print"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    /// Ids, names, text and nesting — everything but the dates, which are stamped
    /// at generation time on purpose.
    private static func shape(of store: BubbleStore) -> [String] {
        var lines: [String] = []
        func walk(_ notes: [BubbleNode], depth: Int) {
            for note in notes {
                lines.append("\(depth) \(note.id) \(note.text)")
                walk(note.children, depth: depth + 1)
            }
        }
        for workspace in store.workspaces {
            lines.append("board \(workspace.id) \(workspace.name)")
            walk(workspace.notes, depth: 0)
        }
        return lines
    }

    private static func load(_ data: Data) -> BubbleStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notebubble-demo-\(UUID().uuidString).json")
        try? data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return BubbleStore(fileURL: url)
    }

    static func run() {
        Check.suite("Demo board — Scripts/demo-data.py") {
            guard let first = generate(), let second = generate() else {
                Check.isTrue(false, "the demo script runs (needs python3 on the PATH)")
                return
            }
            let store = load(first)
            Check.nil_(store.fileNotice, "it is a file the app reads without complaint")
            Check.equal(store.workspaces.map(\.name), ["Home", "Errands", "Someday"],
                        "three boards: a full one, a small one and an empty one")
            Check.equal(store.everywhere.total, 37, "37 notes in all")
            let tally = store.everywhere
            Check.isTrue(tally.fresh > 0 && tally.aging > 0 && tally.overdue > 0,
                         "spread across all three traffic lights")
            Check.equal(shape(of: load(second)), shape(of: store),
                        "and generating it twice gives the same ids, text and nesting")
        }
    }
}
