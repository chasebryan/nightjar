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
    static func seconds(_ value: TimeInterval) -> String {
        return String(format: "%.3f", value)
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
        return bytes.map { String(format: "%02x", $0) }.joined()
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

    init(url: URL) {
        self.url = url
    }

    func open() throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        self.handle = handle
    }

    func append(_ line: String) {
        buffer += line
        buffer += "\n"
        linesWritten += 1
        if buffer.utf8.count > 16_384 {
            flush()
        }
    }

    func flush() {
        guard let handle = handle, !buffer.isEmpty else { return }
        if let data = buffer.data(using: .utf8) {
            handle.write(data)
        }
        buffer = ""
    }

    func close() {
        flush()
        if let handle = handle {
            handle.synchronizeFile()
            handle.closeFile()
        }
        handle = nil
    }
}
