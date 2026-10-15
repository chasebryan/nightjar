import Foundation

/// A recorded session, as read back from its log file's header and footer.
struct SessionSummary: Identifiable, Equatable {
    let id: String             // session id from the header
    let url: URL
    let label: String?
    let startedAt: TimeInterval
    let endedAt: TimeInterval?
    let sightings: Int?
    let fileSize: Int

    var isUnfinished: Bool { return endedAt == nil }

    var duration: TimeInterval? {
        guard let endedAt = endedAt else { return nil }
        return max(0, endedAt - startedAt)
    }
}

/// Where sessions live and how they are listed, deleted and read back.
///
/// Logs go in the app's Documents directory, which — with the file
/// sharing keys in Info.plist — shows up in the Files app under
/// "On My iPhone › nightjar" and in Finder when the phone is plugged in,
/// so there are three roads to the Mac: the share sheet, Files, and a
/// cable.
enum SessionStore {
    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("sessions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    static func newFileURL(sessionID: String, startedAt: TimeInterval) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date(timeIntervalSince1970: startedAt))
        return directory.appendingPathComponent("nightjar-\(stamp)-\(sessionID).jsonl")
    }

    static func newSessionID() -> String {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(hex.prefix(12))
    }

    static func list() -> [SessionSummary] {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        let summaries = urls.filter { $0.pathExtension == "jsonl" }.compactMap { summary(for: $0) }
        return summaries.sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ session: SessionSummary) {
        try? FileManager.default.removeItem(at: session.url)
    }

    /// Delete every stored session except the one still
    /// recording. Returns how many files went.
    static func deleteAll(exceptLiveID liveID: String?) -> Int {
        var deleted = 0
        for session in list() where session.id != liveID {
            delete(session)
            deleted += 1
        }
        return deleted
    }

    /// Parse the header (first line) and the footer (last line, if any).
    static func summary(for url: URL) -> SessionSummary? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        let head = handle.readData(ofLength: 4096)
        guard let headText = String(data: head, encoding: .utf8),
              let firstLine = headText.split(separator: "\n", maxSplits: 1,
                                             omittingEmptySubsequences: true).first,
              let header = parse(line: String(firstLine)),
              header["type"] as? String == "session",
              let sessionID = header["session_id"] as? String,
              let startedAt = header["started_at"] as? Double else {
            return nil
        }

        var endedAt: TimeInterval?
        var sightings: Int?
        if size > 0 {
            let tailLength = min(size, 4096)
            handle.seek(toFileOffset: UInt64(size - tailLength))
            let tail = handle.readData(ofLength: tailLength)
            if let tailText = String(data: tail, encoding: .utf8) {
                let lines = tailText.split(separator: "\n", omittingEmptySubsequences: true)
                if let last = lines.last, let footer = parse(line: String(last)),
                   footer["type"] as? String == "session_end" {
                    endedAt = footer["ended_at"] as? Double
                    sightings = footer["sightings"] as? Int
                }
            }
        }
        return SessionSummary(id: sessionID, url: url, label: header["label"] as? String,
                              startedAt: startedAt, endedAt: endedAt, sightings: sightings,
                              fileSize: size)
    }

    private static func parse(line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// Count sighting lines in an unfinished log (one that has no footer).
    static func countSightings(in url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var count = 0
        text.enumerateLines { line, _ in
            if line.hasPrefix("{\"type\": \"sighting\"") { count += 1 }
        }
        return count
    }
}
