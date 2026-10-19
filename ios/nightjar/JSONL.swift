import Foundation

/// The log contract, byte for byte.
///
/// nightjar's logs are JSON Lines, and the Mac side reads them with
/// Python's `json` module. Rather than trust `JSONSerialization` to
/// keep key order and number formatting stable across OS releases,
/// each record is assembled by hand from ordered fields, with strings
/// escaped exactly as RFC 8259 asks.
enum JSONL {
    /// A JSON string literal, quotes included.
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
        return out
    }

    /// Epoch seconds with millisecond precision: `1760000001.250`.
    /// The JSON number grammar requires a dot and forbids grouping
    /// separators, irrespective of the device's locale.
    static func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func int(_ value: Int?) -> String {
        guard let value = value else { return "null" }
        return String(value)
    }

    static func optionalString(_ value: String?) -> String {
        guard let value = value else { return "null" }
        return string(value)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        // Table-driven: this runs per
        // advertisement, and String(format:)
        // per byte was real money at rate.
        let digits: [Character] =
            Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }

    /// `{"a": 1, "b": "x"}` from ordered (key, already-encoded value) pairs.
    static func object(_ fields: [(String, String)]) -> String {
        let body = fields.map { "\(string($0.0)): \($0.1)" }.joined(separator: ", ")
        return "{\(body)}"
    }

    static func array(_ values: [String]) -> String {
        return "[\(values.joined(separator: ", "))]"
    }
}

/// Appends lines to a file, buffering in memory and flushing on a
/// timer, on demand, and when closed. A sighting a few times a second
/// per device adds up; the flash doesn't need to see every one.
final class JSONLWriter {
    let url: URL
    private var handle: FileHandle?
    private var buffer = ""
    private(set) var linesWritten = 0

    /// Every touch of the file handle funnels through this serial
    /// queue, so a flush from the ticker can never interleave with
    /// an append-driven flush or a close from another thread.
    private let queue = DispatchQueue(label: "nightjar.jsonl.writer")

    init(url: URL) {
        self.url = url
    }

    func open() throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        queue.sync { self.handle = handle }
    }

    func append(_ line: String) {
        // On the queue too: the buffer is shared state, not just
        // the handle — mutating it here while a flush reads it
        // there would be the same race with extra steps.
        queue.sync {
            buffer += line
            buffer += "\n"
            linesWritten += 1
            if buffer.utf8.count > 16_384 {
                flushLocked()
            }
        }
    }

    /// Write the buffer out. Must already be on `queue` — the
    /// public entry points below are the ones that hop onto it.
    private func flushLocked() {
        guard let handle = handle, !buffer.isEmpty else { return }
        if let data = buffer.data(using: .utf8) {
            do {
                try handle.write(contentsOf: data)
                buffer = ""
            } catch {
                // The buffer keeps its lines: the next
                // flush retries instead of the session
                // log silently losing them.
            }
        }
    }

    func flush() {
        queue.sync { flushLocked() }
    }

    func close() {
        queue.sync {
            flushLocked()
            if let handle = handle {
                try? handle.synchronize()
                try? handle.close()
            }
            handle = nil
        }
    }
}
