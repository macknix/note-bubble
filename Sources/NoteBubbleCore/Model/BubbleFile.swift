import Foundation
import os

/// `bubbles.json` on disk: reading it, writing it, and — the part that matters —
/// never letting a file that could not be read be replaced by an empty board.
///
/// That used to be exactly what happened. Every step of loading was `try?`, so a
/// typo from a hand-edit, a truncated write or a file from a newer build all
/// decoded to "no notes", and the next keystroke saved that over the original.
struct BubbleFile {
    let url: URL

    /// What was found on disk.
    enum Contents {
        /// Nothing there yet — a first launch.
        case missing
        case loaded(BubbleDocument)
        /// Written by a newer build. Left exactly where it is, because that build
        /// will want it back; the session must not save over it.
        case tooNew(version: Int)
        /// Could not be decoded. Moved to `setAsideURL` so nothing can overwrite
        /// it; nil if even the move failed, in which case nothing may be saved.
        case unreadable(setAsideURL: URL?)
    }

    static let logger = Logger(subsystem: "com.macknixon.notebubble", category: "persistence")

    /// A copy of the file as it was before this session first wrote to it.
    var backupURL: URL { url.appendingPathExtension("bak") }

    func load() -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Present but unreadable — permissions, say. Not something to move.
            Self.logger.error("Could not read \(url.path, privacy: .public): \(error)")
            return .unreadable(setAsideURL: nil)
        }

        do {
            return .loaded(try Self.decoder.decode(BubbleDocument.self, from: data))
        } catch BubbleDocument.Failure.tooNew(let version) {
            Self.logger.error("\(url.path, privacy: .public) is version \(version), newer than this build")
            return .tooNew(version: version)
        } catch {
            Self.logger.error("Could not decode \(url.path, privacy: .public): \(error)")
            return .unreadable(setAsideURL: setAside())
        }
    }

    /// Writes atomically. With `backingUp`, the current file is first copied to
    /// `backupURL` — the store asks for this once per launch, so there is always
    /// one copy of how things stood before this session touched them.
    func save(_ document: BubbleDocument, backingUp: Bool = false) throws {
        let data = try Self.encoder.encode(document)
        if backingUp { backUp() }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Private

    private func backUp() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        do {
            if manager.fileExists(atPath: backupURL.path) {
                try manager.removeItem(at: backupURL)
            }
            try manager.copyItem(at: url, to: backupURL)
        } catch {
            // A missing backup is not worth refusing to save over.
            Self.logger.error("Could not back up \(url.path, privacy: .public): \(error)")
        }
    }

    /// Moves an undecodable file out of the way, beside the original, named for
    /// when it happened. Returns nil if the move failed.
    private func setAside() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).unreadable-\(stamp).\(url.pathExtension)")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            Self.logger.notice("Set unreadable notes aside at \(destination.path, privacy: .public)")
            return destination
        } catch {
            Self.logger.error("Could not set aside \(url.path, privacy: .public): \(error)")
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
