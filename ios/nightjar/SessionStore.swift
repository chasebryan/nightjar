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

    @discardableResult
    static func delete(_ session: SessionSummary) -> Bool {
        do {
            try FileManager.default.removeItem(at: session.url)
            return true
        } catch {
            return false
        }
    }

    /// Delete every stored session except the one still
    /// recording. Returns how many files went.
    static func deleteAll(exceptLiveID liveID: String?) -> Int {
        var deleted = 0
        for session in list() where session.id != liveID {
            if delete(session) {
                deleted += 1
            }
        }
        return deleted
    }

    /// A log whose header won't parse still gets listed, so the
    /// user can see (and delete or share) a file we cannot read.
    private static func fallbackSummary(for url: URL, fileSize size: Int) -> SessionSummary {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return SessionSummary(id: "file:\(url.lastPathComponent)", url: url,
                              label: "(unreadable log)", startedAt: modified,
                              endedAt: nil, sightings: nil, fileSize: size)
    }

    /// Parse the header (first line) and the footer (last line, if any).
    static func summary(for url: URL) -> SessionSummary? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return fallbackSummary(for: url, fileSize: size)
        }
        defer { handle.closeFile() }

        let head = handle.readData(ofLength: 4096)
        guard let headText = String(data: head, encoding: .utf8),
              let firstLine = headText.split(separator: "\n", maxSplits: 1,
                                             omittingEmptySubsequences: true).first,
              let header = parse(line: String(firstLine)),
              header["type"] as? String == "session",
              let sessionID = header["session_id"] as? String,
              let startedAt = header["started_at"] as? Double else {
            return fallbackSummary(for: url, fileSize: size)
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
    /// Streamed in 64 KB chunks — a long session's log is never
    /// loaded whole — carrying the incomplete tail of each chunk
    /// into the next, so a line (or its prefix) split across a
    /// chunk boundary still counts exactly once.
    static func countSightings(in url: URL) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        let prefix = Data("{\"type\": \"sighting\"".utf8)
        var count = 0
        var pending = Data()
        while true {
            let chunk = handle.readData(ofLength: 65_536)
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: UInt8(0x0A)) {
                let line = pending[pending.startIndex..<newline]
                if line.starts(with: prefix) { count += 1 }
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
        if pending.starts(with: prefix) { count += 1 }
        return count
    }
}
