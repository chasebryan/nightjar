import Compression
import CoreBluetooth
import Foundation
import Network
import UIKit
import UserNotifications

/// The mouth: everything in nightjar-hack that transmits. A port of
/// `nightjar/send.py`'s semantics to what iOS allows an app to do.
///
/// The listening post (ListeningPost.swift) is untouched by this file:
/// separate managers, separate state, no shared radio. Transmitting
/// happens only from explicit button presses in the Send/Serve tabs,
/// and only while the app is in the foreground — iOS does not let a
/// sideloaded app hold advertisements or listeners open in the
/// background, and this file does not pretend otherwise.

// MARK: - Payload construction (mirrors build_payload / frame in send.py)

enum MouthError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let text): return text }
    }
}

enum PayloadKit {
    static func decodeHex(_ raw: String) throws -> Data {
        let compact = raw.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\n", with: "")
        guard compact.count % 2 == 0 else {
            throw MouthError.message("could not decode hex payload: odd number of digits")
        }
        var bytes: [UInt8] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw MouthError.message("could not decode hex payload: bad digits")
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// Mirrors send.py's _xor_key: hex (optionally 0x-prefixed, colon or
    /// space separated) when the spec parses as hex, else its UTF-8 bytes.
    static func xorKey(_ spec: String) -> Data {
        var text = spec.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("0x") { text.removeFirst(2) }
        let compact = text.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        let hexDigits = Set("0123456789abcdefABCDEF")
        if !compact.isEmpty, compact.count % 2 == 0,
           compact.allSatisfy({ hexDigits.contains($0) }),
           let data = try? decodeHex(compact) {
            return data
        }
        return Data(spec.utf8)
    }

    static func xor(_ data: Data, key: Data) -> Data {
        if key.isEmpty { return data }
        var out = Data(count: data.count)
        for i in 0..<data.count {
            out[i] = data[i] ^ key[i % key.count]
        }
        return out
    }

    static func build(source: String, text: String, hex: String, b64: String,
                      xorSpec: String, useGzip: Bool) throws -> Data {
        var data: Data
        switch source {
        case "hex":
            data = try decodeHex(hex)
        case "base64":
            guard let decoded = Data(base64Encoded: b64) else {
                throw MouthError.message("could not decode base64 payload")
            }
            data = decoded
        default:
            data = Data(text.utf8)
        }
        if !xorSpec.isEmpty {
            data = xor(data, key: xorKey(xorSpec))
        }
        if useGzip {
            guard let zipped = gzipCompress(data) else {
                throw MouthError.message("gzip failed")
            }
            data = zipped
        }
        return data
    }

    // MARK: gzip (Compression gives a zlib stream; gzip is a wrapper
    // around the same deflate body, so: strip zlib's 2-byte header and
    // 4-byte Adler-32, add gzip's 10-byte header, CRC-32 and size.)

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    static func gzipCompress(_ data: Data) -> Data? {
        if data.isEmpty {
            // gzip of nothing: header + empty final deflate block + crc + size
            var out = Data([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0x03, 0x03, 0x00])
            out.append(le32(0)); out.append(le32(0))
            return out
        }
        let capacity = data.count + data.count / 2 + 4096
        var dst = Data(count: capacity)
        let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
            data.withUnsafeBytes { srcPtr -> Int in
                compression_encode_buffer(
                    dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), capacity,
                    srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 6 else { return nil }
        let zlib = dst.prefix(written)
        let rawDeflate = zlib.dropFirst(2).dropLast(4)
        var out = Data([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0x03])
        out.append(rawDeflate)
        out.append(le32(crc32(data)))
        out.append(le32(UInt32(data.count)))
        return out
    }

    static func gzipDecompress(_ data: Data) -> Data? {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else {
            return nil
        }
        let size = Int(le32Value(data.suffix(4)))
        let body = data.dropFirst(10).dropLast(8)
        // Rebuild a zlib stream: 0x78 0x9C header + raw deflate + dummy
        // Adler-32 (the Compression decoder does not verify it).
        var zlib = Data([0x78, 0x9C])
        zlib.append(body)
        zlib.append(Data([0, 0, 0, 0]))
        var dst = Data(count: max(size, 1))
        let written = dst.withUnsafeMutableBytes { dstPtr -> Int in
            zlib.withUnsafeBytes { srcPtr -> Int in
                compression_decode_buffer(
                    dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), max(size, 1),
                    srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), zlib.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { return nil }
        return dst.prefix(written)
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    private static func le32Value(_ data: Data) -> UInt32 {
        let b = [UInt8](data)
        guard b.count == 4 else { return 0 }
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    // MARK: Framing (mirrors frame/unframe in send.py)

    /// Payload templating: {{target}}, {{host}}, {{port}}, {{ip}}
    /// and {{scheme}} are replaced per destination, so one payload
    /// can address each target it is sent to — callbacks, Host
    /// headers, self-referential probes. Runs on the raw source
    /// text before hex/base64 decoding, so templates work in every
    /// source mode.
    static func substitute(_ raw: String, targetText: String) -> String {
        var host = "", port = "", scheme = ""
        if targetText.hasPrefix("phone:") {
            host = String(targetText.dropFirst(6))
            scheme = "phone"
        } else if let parsed = try? SendTarget.parse(targetText) {
            switch parsed {
            case .tcp(let h, let p, let tls):
                host = h; port = "\(p)"; scheme = tls ? "tcp+tls" : "tcp"
            case .udp(let h, let p):
                host = h; port = "\(p)"; scheme = "udp"
            case .http(let url, let https):
                host = url.host ?? ""
                port = url.port.map(String.init) ?? (https ? "443" : "80")
                scheme = https ? "https" : "http"
            default:
                break
            }
        }
        // Single pass over the ORIGINAL string: values are written
        // straight into the output and never rescanned, so a host or
        // target that itself contains "{{port}}" cannot chain-expand.
        let values: [String: String] = [
            "{{target}}": targetText, "{{host}}": host, "{{ip}}": host,
            "{{port}}": port, "{{scheme}}": scheme,
        ]
        var out = ""
        var rest = raw[...]
        while let open = rest.range(of: "{{") {
            out += String(rest[..<open.lowerBound])
            let tail = rest[open.lowerBound...]
            guard let close = tail.range(of: "}}") else {
                out += String(tail)
                rest = rest[rest.endIndex...]
                break
            }
            let token = String(tail[..<close.upperBound])
            out += values[token] ?? token
            rest = tail[close.upperBound...]
        }
        out += String(rest)
        return out
    }

    /// Source-aware substitution: templating applies ONLY to text
    /// payloads. Hex/base64 sources are literal bytes — a "{{host}}"
    /// byte pattern in them is data, not a template — so they pass
    /// through untouched.
    static func substitute(_ raw: String, targetText: String,
                           source: String) -> String {
        guard source == "text" else { return raw }
        return substitute(raw, targetText: targetText)
    }

    // MARK: PayPlant builders — payloads a target service stores

    private static func mqttRemainingLength(_ value: Int) -> Data {
        var data = Data()
        var n = value
        repeat {
            var byte = UInt8(n % 128)
            n /= 128
            if n > 0 { byte |= 0x80 }
            data.append(byte)
        } while n > 0
        return data
    }

    static func mqttConnect(clientID: String) -> Data {
        // The length prefix is 2-byte big-endian: a value >= 65536
        // would trap in UInt8(>>8). Fail the build (empty packet)
        // instead of crashing.
        guard clientID.utf8.count < 65536 else { return Data() }
        var body = Data()
        body.append(contentsOf: [0x00, 0x04])
        body.append(contentsOf: "MQTT".utf8)
        body.append(contentsOf: [0x04, 0x02, 0x00, 0x3C])
        body.append(UInt8((clientID.utf8.count >> 8) & 0xff))
        body.append(UInt8(clientID.utf8.count & 0xff))
        body.append(contentsOf: clientID.utf8)
        var packet = Data([0x10])
        packet += mqttRemainingLength(body.count)
        packet += body
        return packet
    }

    /// A QoS 0 PUBLISH. With retain set, the broker keeps the
    /// message and hands it to every future subscriber — the plant.
    static func mqttPublish(topic: String, payload: Data,
                            retain: Bool) -> Data {
        guard topic.utf8.count < 65536 else { return Data() }
        var body = Data()
        body.append(UInt8((topic.utf8.count >> 8) & 0xff))
        body.append(UInt8(topic.utf8.count & 0xff))
        body.append(contentsOf: topic.utf8)
        body += payload
        var packet = Data([retain ? 0x31 : 0x30])
        packet += mqttRemainingLength(body.count)
        packet += body
        return packet
    }

    static func redisCommand(_ parts: [String]) -> Data {
        var out = "*\(parts.count)\r\n"
        for part in parts {
            out += "$\(part.utf8.count)\r\n\(part)\r\n"
        }
        return Data(out.utf8)
    }

    static func memcachedSet(key: String, value: String) -> Data {
        Data("set \(key) 0 0 \(value.utf8.count)\r\n\(value)\r\n".utf8)
    }

    static func frame(_ data: Data, framing: String) -> Data {
        switch framing {
        case "len":
            var out = Data()
            let n = UInt32(data.count)
            out.append(contentsOf: [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF),
                                    UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
            out.append(data)
            return out
        case "json":
            let envelope: [String: Any] = [
                "ts": Date().timeIntervalSince1970,
                "tool": "nightjar-send",
                "encoding": "base64",
                "payload": data.base64EncodedString(),
            ]
            return (try? JSONSerialization.data(withJSONObject: envelope)) ?? data
        default:
            return data
        }
    }

    static func unframe(_ data: Data, framing: String) -> Data {
        if framing == "len", data.count >= 4 {
            let size = Int(data[0]) << 24 | Int(data[1]) << 16 | Int(data[2]) << 8 | Int(data[3])
            return data.subdata(in: 4..<min(data.count, 4 + size))
        }
        if framing == "json",
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let payload = object["payload"] as? String,
           let decoded = Data(base64Encoded: payload) {
            return decoded
        }
        return data
    }

    /// The data as displayable text, when it decodes as UTF-8 and holds
    /// nothing but printable characters, whitespace and newlines —
    /// else nil (callers show the hexdump instead).
    static func printableText(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        let bad = CharacterSet.controlCharacters
            .subtracting(CharacterSet.newlines)
            .subtracting(CharacterSet(charactersIn: "\t"))
        if text.unicodeScalars.contains(where: { bad.contains($0) }) {
            return nil
        }
        return text
    }

    /// Same layout as send.py's hexdump: offset, spaced hex, glyphs.
    static func hexdump(_ data: Data, width: Int = 16) -> String {
        if data.isEmpty { return "    (empty)" }
        let bytes = [UInt8](data)
        var lines: [String] = []
        var offset = 0
        while offset < bytes.count {
            let chunk = Array(bytes[offset..<min(offset + width, bytes.count)])
            let hexes = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let glyphs = chunk.map { (32 <= $0 && $0 < 127) ? String(UnicodeScalar($0)) : "." }
                .joined()
            let padded = hexes.padding(toLength: width * 3, withPad: " ", startingAt: 0)
            lines.append(String(format: "    %08x  %@  %@", offset, padded, glyphs))
            offset += width
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Targets (mirrors parse_target in send.py, reduced to iOS's reach)

enum SendTarget {
    case tcp(host: String, port: Int, tls: Bool)
    case udp(host: String, port: Int)
    case http(url: URL, https: Bool)
    case bleBeacon
    case bleGatt
    case bleWrite(address: String)  // a MAC or "name:DEVICE"; resolved in the UI list

    var raw: String {
        switch self {
        case .tcp(let host, let port, let tls): return "\(tls ? "tcp+tls" : "tcp")://\(host):\(port)"
        case .udp(let host, let port): return "udp://\(host):\(port)"
        case .http(let url, _): return url.absoluteString
        case .bleBeacon: return "ble://"
        case .bleGatt: return "ble-gatt://"
        case .bleWrite(let address): return "ble-write://\(address)"
        }
    }

    static func parse(_ raw: String) throws -> SendTarget {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("name:") {
            return .bleWrite(address: text)
        }
        if !text.contains("://") {
            if looksLikeMAC(text) { return .bleWrite(address: text.uppercased()) }
            throw MouthError.message("target needs a scheme: tcp://, udp://, tcp+tls://, "
                                     + "http(s)://, ble://, ble-gatt://, ble-write://, a MAC, or name:DEVICE")
        }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        let scheme = parts[0].lowercased()
        let rest = text.dropFirst(parts[0].count + 3)
        switch scheme {
        case "http", "https":
            guard let url = URL(string: text) else {
                throw MouthError.message("bad URL in \(text)")
            }
            return .http(url: url, https: scheme == "https")
        case "ble", "adv", "advertise":
            return .bleBeacon
        case "ble-gatt", "gatt", "peripheral":
            return .bleGatt
        case "ble-write", "gatt-write", "write":
            if rest.isEmpty { throw MouthError.message("\(scheme):// needs an address or name:DEVICE") }
            return .bleWrite(address: String(rest))
        case "tcp", "udp", "tls", "tcp+tls", "ssl":
            guard let colon = rest.lastIndex(of: ":") else {
                throw MouthError.message("\(scheme):// target needs host:port, got \(rest)")
            }
            let host = String(rest[..<colon])
            guard let port = Int(rest[rest.index(after: colon)...]) else {
                throw MouthError.message("bad port in \(text)")
            }
            if scheme == "udp" { return .udp(host: host, port: port) }
            return .tcp(host: host, port: port, tls: scheme != "tcp")
        default:
            throw MouthError.message("unknown target scheme \(scheme) in \(text)")
        }
    }

    static func looksLikeMAC(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        let hex = Set("0123456789abcdefABCDEF")
        return parts.count == 6 && parts.allSatisfy {
            $0.count == 2 && $0.allSatisfy { hex.contains($0) }
        }
    }
}

/// One payload that arrived at a listener (or as a GATT write).
struct ReceivedPayload: Identifiable {
    let id = UUID()
    let at: Date
    let transport: String
    let peer: String
    let data: Data

    var jsonLine: String {
        let fields: [(String, String)] = [
            ("ts", JSONL.seconds(at.timeIntervalSince1970)),
            ("transport", JSONL.string(transport)),
            ("peer", JSONL.string(peer)),
            ("bytes", String(data.count)),
            ("payload_hex", JSONL.string(JSONL.hex([UInt8](data)))),
            ("payload_b64", JSONL.string(data.base64EncodedString())),
        ]
        return JSONL.object(fields)
    }
}

// MARK: - The engine

final class Mouth: NSObject, ObservableObject {
    @Published private(set) var sendLines: [String] = []
    @Published private(set) var inbox: [ReceivedPayload] = []
    @Published private(set) var beaconOn = false
    @Published private(set) var gattHostOn = false
    @Published private(set) var serveRunning = false
    @Published var serveError: String?
    @Published private(set) var writeTargets: [WriteTarget] = []
    @Published private(set) var writeScanning = false
    @Published var pendingWriteID: UUID?
    @Published var pendingWriteLabel: String?
    @Published private(set) var nearbyPhones: [String] = []
    private var browser: NWBrowser?

    /// Scan → Send handoff: an open port tapped in the Scan tab,
    /// consumed by the Send tab when it appears.
    @Published var scanHandoffTarget: String?
    @Published var scanHandoffPayload: String?

    /// The most recent reply a send collected, for the Send tab's
    /// inline readout (the full trail still lives in the log).
    struct LastReply: Identifiable {
        let id = UUID()
        let label: String
        let data: Data
        let at: Date
    }

    @Published private(set) var lastReply: LastReply?

    private func noteReply(label: String, data: Data) {
        guard !data.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastReply = LastReply(label: label, data: data, at: Date())
        }
    }

    /// This phone's LAN IPv4 (en0), for "reachable at tcp://…" lines.
    static func localIPAddress() -> String? {
        var result: String?
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ptr.pointee.ifa_name) == "en0"
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                        socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            result = String(cString: host)
        }
        return result
    }

    /// The live instance, so App Intents (Shortcuts/Siri) can send.
    static weak var shared: Mouth?

    /// Set by the app: where in-app popup narration goes.
    weak var toasts: ToastCenter?

    /// Narrate an event as a fading in-app popup (+ a buzz).
    func ui(_ message: String, error: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.toasts?.show(message, error: error)
            if error { Haptics.error() }
        }
    }

    /// Narrate a success (popup + the success buzz).
    func uiSuccess(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.toasts?.show(message)
            Haptics.success()
        }
    }

    // MARK: Exchange history (persistent, exportable)

    static var exchangesURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exchanges.jsonl")
    }

    private let exchangeQueue = DispatchQueue(label: "nightjar-exchanges")

    /// One JSON line per exchange: what went where, how much came
    /// back. The working record a scan or a send leaves behind.
    func logExchange(_ kind: String, _ label: String, sent: Int,
                     reply: Data?) {
        var record: [String: Any] = [
            "ts": Date().timeIntervalSince1970,
            "kind": kind, "target": label, "sent": sent,
        ]
        if let reply = reply {
            record["replyBytes"] = reply.count
            if kind == "snatch" {
                // A snatch haul is the point of the operation: history
                // keeps ALL of it — the full printable text when it is
                // text, otherwise the full hex — never a prefix.
                if let text = PayloadKit.printableText(reply) {
                    record["replyText"] = text
                }
                record["replyHex"] = reply
                    .map { String(format: "%02x", $0) }.joined()
            } else {
                record["replyHex"] = reply.prefix(48)
                    .map { String(format: "%02x", $0) }.joined()
            }
        }
        guard let data = try? JSONSerialization.data(
                withJSONObject: record),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        exchangeQueue.async {
            let url = Mouth.exchangesURL
            if FileManager.default.fileExists(atPath: url.path) {
                // FileHandle.write raises an NSException on failure;
                // the throwing contentsOf variant surfaces an Error
                // instead. If the existing file cannot be opened the
                // line is dropped — the atomic whole-file fallback
                // must never truncate real history down to one line.
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    handle.seekToEndOfFile()
                    try handle.write(contentsOf: Data(line.utf8))
                    try? handle.close()
                } catch {
                    // Drop the line; history stays as it was.
                }
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    override init() {
        super.init()
        Mouth.shared = self
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "gattArm.on") {
            // A GATT host was left armed: recreating the manager (with
            // its restore identifier) is what lets the saved arm —
            // and any iOS relaunch-for-Bluetooth — take effect.
            _ = ensurePeripheral()
        }
    }

    struct WriteTarget: Identifiable {
        let id: UUID  // the peripheral's CoreBluetooth identifier
        let peripheral: CBPeripheral
        var name: String?
        var rssi: Int?
    }

    private let queue = DispatchQueue(label: "net.nosuchmachine.nightjarhack.mouth")
    private var peripheralManager: CBPeripheralManager?
    private var wantBeacon = false  // intent, survives radio state changes
    private var beaconPayload: Data = Data()
    private var beaconName = "nightjar"
    private var gattPayload: Data = Data()
    private var gattCharacteristic: CBMutableCharacteristic?
    /// Set by willRestoreState when iOS hands back a service with our
    /// UUID: it already exists, so startGattHost must not re-add it.
    private var gattServiceRestored = false
    private var centralManager: CBCentralManager?
    private var writePeripherals: [UUID: CBPeripheral] = [:]
    private var pendingWrite: (peripheral: CBPeripheral, payload: Data)?
    private var writeToken = 0
    private var listeners: [NWListener] = []
    /// Stamped on every startServe/stopServe. Listener state handlers
    /// and arrival sinks capture the generation they were created
    /// under and act only while it is still current — a stale
    /// listener failing, or a pre-Stop peer's bytes landing late, can
    /// no longer flip state or reach the inbox for a dead serve.
    private var serveGeneration = 0
    /// Accepted connections still in flight, so stopServe can cancel
    /// them all instead of leaving half-open peers behind.
    private var serveConnections: [NWConnection] = []
    private var serveReply: Data = Data()
    private var serveEcho = false
    private var serveFraming = "raw"

    static let serviceUUID = CBUUID(string: "FFF0")
    static let charUUID = CBUUID(string: "FFF1")
    static let bonjourType = "_nightjar._tcp"

    func line(_ text: String) {
        DispatchQueue.main.async {
            self.sendLines.append(text)
            if self.sendLines.count > 300 { self.sendLines.removeFirst(self.sendLines.count - 300) }
        }
    }

    /// Stealth: full function, no announcement. Listeners stop
    /// advertising on Bonjour (reachable by address only, like the
    /// CLI), and arrivals join the inbox silently — nothing banners,
    /// pings, or pops without the user's explicit say-so. Persisted
    /// in UserDefaults so the views and the engine share one switch.
    var stealth: Bool {
        get { UserDefaults.standard.bool(forKey: "stealthMode") }
        set { UserDefaults.standard.set(newValue, forKey: "stealthMode") }
    }

    /// Flip stealth, restarting the listeners if they are running so
    /// the Bonjour advertisement (or its absence) takes effect now.
    func setStealth(_ on: Bool) {
        stealth = on
        ui(on ? "Stealth on — unlisted, silent arrivals" : "Stealth off")
        line(on ? "stealth on: no Bonjour listing, silent arrivals"
                : "stealth off")
        if serveRunning, let params = lastServeParams {
            startServe(tcpPort: params.tcp, udpPort: params.udp,
                       httpPort: params.http, reply: params.reply,
                       framing: params.framing, echo: params.echo)
        }
    }

    private var lastServeParams: (tcp: Int?, udp: Int?, http: Int?,
                                  reply: String, framing: String,
                                  echo: Bool)?

    private func receive(transport: String, peer: String, data: Data) {
        DispatchQueue.main.async {
            self.inbox.insert(ReceivedPayload(at: Date(), transport: transport,
                                              peer: peer, data: data), at: 0)
            if self.inbox.count > 200 { self.inbox.removeLast(self.inbox.count - 200) }
            // Stealth check stays FIRST: in stealth nothing banners.
            if !self.stealth {
                // Make it pop: a banner with the message itself when it
                // is printable; binary arrivals banner their size and
                // first bytes as hex instead of staying silent.
                let content = UNMutableNotificationContent()
                content.title = "nightjar-hack · \(transport) from \(peer)"
                if let text = PayloadKit.printableText(data) {
                    content.body = text
                } else {
                    let head = data.prefix(8)
                        .map { String(format: "%02x", $0) }.joined(separator: " ")
                    content.body = "\(data.count) bytes · \(head)"
                }
                content.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: UUID().uuidString,
                                          content: content, trigger: nil))
            }
        }
    }

    static func exchangeHistoryDescription() -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(
                atPath: exchangesURL.path),
              let size = attrs[.size] as? Int else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size),
                                         countStyle: .file)
    }

    /// Delete the persistent exchange history file outright. The
    /// next exchange starts a fresh one.
    func deleteExchangeHistory() {
        exchangeQueue.sync {
            try? FileManager.default.removeItem(at: Mouth.exchangesURL)
        }
        line("exchange history deleted")
    }

    /// Recon results join the same exportable history as payload
    /// exchanges — one file tells the whole session.
    func logRecon(_ kind: String, _ label: String, lines: [String]) {
        logExchange(kind, label, sent: 0,
                    reply: Data(lines.joined(separator: "\n").utf8))
    }

    func clearSendLog() { sendLines = [] }
    func clearInbox() { inbox = [] }

    var inboxJSONL: String {
        inbox.reversed().map { $0.jsonLine }.joined(separator: "\n")
    }

    // MARK: Network send (tcp / udp / tls)

    func sendNetwork(target: SendTarget, payload: Data, framing: String,
                     read: Bool, timeout: TimeInterval,
                     completion: ((Bool) -> Void)? = nil) {
        let framed = PayloadKit.frame(payload, framing: framing)
        let params: NWParameters
        let host: String
        let port: Int
        switch target {
        case .tcp(let h, let p, let tls):
            host = h; port = p
            params = tls ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        case .udp(let h, let p):
            host = h; port = p
            params = .udp
        default:
            completion?(false)
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            line("nightjar: bad port \(port)")
            completion?(false)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: params)
        run(connection, label: target.raw, framed: framed, read: read,
            timeout: timeout, completion: completion)
    }

    /// Send to a nearby phone by name — Bonjour resolves the address,
    /// so nobody has to go digging through Settings for an IP.
    func sendToPhone(name: String, payload: Data, framing: String,
                     read: Bool, timeout: TimeInterval,
                     completion: ((Bool) -> Void)? = nil) {
        let framed = PayloadKit.frame(payload, framing: framing)
        let endpoint = NWEndpoint.service(name: name, type: Mouth.bonjourType,
                                          domain: "local.", interface: nil)
        run(NWConnection(to: endpoint, using: .tcp),
            label: "phone \(name)", framed: framed, read: read,
            timeout: timeout, completion: completion)
    }

    /// One stream connection: send `framed`, optionally collect a
    /// reply until the peer closes or the deadline passes.
    private func run(_ connection: NWConnection, label: String, framed: Data,
                     read: Bool, timeout: TimeInterval,
                     completion: ((Bool) -> Void)? = nil) {
        var replied = Data()
        var finished = false
        var didSend = false
        func finish() {
            guard !finished else { return }
            finished = true
            connection.cancel()
            if didSend {
                logExchange("send", label, sent: framed.count,
                            reply: read ? replied : nil)
            }
            completion?(didSend)
            if read {
                if replied.isEmpty {
                    line("  (no reply)")
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.toasts?.show("Reply received — \(replied.count) bytes")
                    }
                    noteReply(label: label, data: replied)
                    line("  <- \(replied.count) byte reply")
                    for l in PayloadKit.hexdump(replied).components(separatedBy: "\n") {
                        line(l)
                    }
                    if let text = PayloadKit.printableText(replied) {
                        line("  text: \(text)")
                    }
                }
            }
        }
        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty { replied += data }
                if isComplete || error != nil {
                    finish()
                } else {
                    receiveMore()
                }
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.line("sent \(framed.count) bytes over \(label)")
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error = error {
                        self?.line("nightjar: send failed: \(error.localizedDescription)")
                        self?.ui("Send failed: \(error.localizedDescription)", error: true)
                        finish()
                        return
                    }
                    didSend = true
                    if read {
                        receiveMore()
                    } else {
                        self?.uiSuccess("Sent \(framed.count) bytes to \(label)")
                        finish()
                    }
                })
            case .failed(let error):
                self?.line("nightjar: \(error.localizedDescription)")
                self?.ui(error.localizedDescription, error: true)
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout + 2) { finish() }
    }

    // MARK: Fan-out (one payload, many targets)

    @Published var fanoutBusy = false
    @Published var fanoutLines: [String] = []
    /// Target strings ("tcp://host:port") from the most recent Scan
    /// tab scan or sweep, offered in the Send tab's fan-out section.
    @Published var lastScanTargets: [String] = []

    /// Expand a last-octet range entry — "192.168.1.10-40:6379" or
    /// "tcp://192.168.1.10-40:6379" — into individual targets.
    static func expandRange(_ text: String) -> [String]? {
        let split = text.components(separatedBy: "://")
        let scheme = split.count == 2 ? split[0] + "://" : "tcp://"
        let rest = split.count == 2 ? split[1] : text
        guard let colon = rest.lastIndex(of: ":") else { return nil }
        let hostPart = rest[..<colon]
        guard let port = Int(String(rest[rest.index(after: colon)...])),
              (1...65535).contains(port) else { return nil }
        let octets = hostPart.split(separator: ".")
        guard octets.count == 4 else { return nil }
        // All four octets must be real octets: a "999.168.1.10-40"
        // entry is not a range, it is a typo.
        for i in 0..<3 {
            guard let value = Int(String(octets[i])),
                  (0...255).contains(value) else { return nil }
        }
        let ends = octets[3].split(separator: "-")
        guard ends.count == 2, let lo = Int(String(ends[0])),
              let hi = Int(String(ends[1])),
              (0...255).contains(lo), (0...255).contains(hi),
              lo < hi, hi - lo <= 255 else { return nil }
        let base = octets[0...2].joined(separator: ".") + "."
        return (lo...hi).map { "\(scheme)\(base)\($0):\(port)" }
    }

    /// Shape test for the UI: does this line LOOK like a last-octet
    /// range ("192.168.1.10-40", optionally with a scheme prefix and/or
    /// a :port suffix)? Shape only — expandRange does the real
    /// validation (octets 0...255, lo < hi) when a send expands it.
    static func looksLikeRange(_ line: String) -> Bool {
        var rest = line.trimmingCharacters(in: .whitespaces)
        if let schemeRange = rest.range(of: "://") {
            rest = String(rest[schemeRange.upperBound...])
        }
        if let colon = rest.lastIndex(of: ":") {
            let portText = rest[rest.index(after: colon)...]
            if !portText.isEmpty, portText.allSatisfy({ $0.isNumber }) {
                rest = String(rest[..<colon])
            }
        }
        let octets = rest.split(separator: ".")
        guard octets.count == 4 else { return false }
        for i in 0..<3 {
            if octets[i].isEmpty || !octets[i].allSatisfy({ $0.isNumber }) {
                return false
            }
        }
        let ends = octets[3].split(separator: "-")
        guard ends.count == 2 else { return false }
        return ends.allSatisfy {
            !$0.isEmpty && $0.allSatisfy { $0.isNumber }
        }
    }

    /// Send one payload to every target in the list, one at a time.
    /// Entries use the Send tab's syntax — tcp://, udp://,
    /// tcp+tls://, http(s):// — or phone:NAME for a nearby phone,
    /// or a last-octet range. Targets can come from anywhere:
    /// typed, pasted, imported from a file, or straight off the
    /// network via the Scan tab. The payload is built per target,
    /// so templates ({{host}} and friends) resolve per destination.
    func sendToMany(targets rawTargets: [String],
                    payloadFor: @escaping (String) -> Data?,
                    framing: String, method: String, readReply: Bool) {
        var expanded: [String] = []
        var invalid: [String] = []
        for entry in rawTargets {
            // One expansion call never materialises more than 5000
            // targets, however wide the ranges in the list are.
            if expanded.count >= 5000 { break }
            let text = entry.trimmingCharacters(in: .whitespaces)
            if let range = Mouth.expandRange(text) {
                expanded += range.prefix(5000 - expanded.count)
            } else if Mouth.looksLikeRange(text) {
                // Range-shaped but invalid (bad octet, reversed):
                // report it — never aim a send at the literal text.
                invalid.append(text)
            } else {
                expanded.append(text)
            }
        }
        var seen = Set<String>()
        let targets = expanded
            .filter { !$0.isEmpty && !$0.hasPrefix("#")
                      && seen.insert($0).inserted }
            .prefix(300)
        guard !fanoutBusy else { return }
        if targets.isEmpty {
            if !invalid.isEmpty {
                fanoutLines = invalid.map { "✗ \($0) — invalid range" }
            }
            return
        }
        fanoutBusy = true
        fanoutLines = ["Fanning out to \(targets.count) target(s)…"]
        for text in invalid {
            fanoutLines.append("✗ \(text) — invalid range")
        }
        line("fan-out: one payload to \(targets.count) targets")
        var index = 0
        var sentCount = 0
        func step() {
            if index >= targets.count {
                let total = targets.count
                let sent = sentCount
                DispatchQueue.main.async { [weak self] in
                    self?.fanoutBusy = false
                    self?.fanoutLines.append(
                        "Done — \(sent)/\(total) sent")
                    self?.toasts?.show(
                        "Fan-out done: \(sent)/\(total) sent",
                        error: sent == 0)
                }
                return
            }
            let text = targets[index]
            index += 1
            let report: (Bool) -> Void = { [weak self] ok in
                if ok { sentCount += 1 }
                DispatchQueue.main.async {
                    self?.fanoutLines.append(
                        "\(ok ? "✓" : "✗") \(text)")
                }
                // Async hop: synchronously-failing targets (bad
                // parse, unbuildable payload) report inside step()
                // itself — recursing directly would grow the stack
                // once per dead target.
                DispatchQueue.main.async { step() }
            }
            guard let payload = payloadFor(text) else {
                line("fan-out: payload failed to build for \(text)")
                report(false)
                return
            }
            if text.hasPrefix("phone:") {
                sendToPhone(name: String(text.dropFirst(6)),
                            payload: payload, framing: framing,
                            read: readReply, timeout: 3,
                            completion: report)
                return
            }
            guard let parsed = try? SendTarget.parse(text) else {
                line("fan-out: cannot parse target \(text)")
                report(false)
                return
            }
            switch parsed {
            case .http:
                sendHTTP(target: parsed, payload: payload,
                         framing: framing, method: method, timeout: 5,
                         completion: report)
            case .tcp, .udp:
                sendNetwork(target: parsed, payload: payload,
                            framing: framing, read: readReply,
                            timeout: 3, completion: report)
            default:
                line("fan-out: \(text) is not a network target — skipped")
                report(false)
            }
        }
        step()
    }

    // MARK: Centipede

    @Published var crawlBusy = false
    @Published var crawlLines: [String] = []
    @Published var crawlHomecoming: Data?
    var crawlGeneration = 0

    // The crawl engine — route expansion, the walk
    // itself, chain/seed modes, the return leg, home
    // delivery — lives in Crawl.swift, an extension
    // on Mouth, so this file stays navigable.

    // MARK: Centipede subnet sweep

    @Published var crawlSweepBusy = false
    @Published var crawlSweepStatus: String?
    let probeQueue = DispatchQueue(
        label: "net.nosuchmachine.nightjarhack.probes",
        attributes: .concurrent)

    // The discovery sweep (sweepBase, discoverSubnet,
    // probe) lives in Crawl.swift alongside the crawl.

    // MARK: Timed delivery

    @Published var scheduleStatus: String?
    private var scheduleItems: [DispatchWorkItem] = []
    /// Identity of the current schedule (an Int token; "UUID Int" in
    /// the audit's words). Bumped on every schedule() and every
    /// cancelSchedule(), so a work item fired late — or re-arming
    /// after a cancel — can tell it no longer belongs.
    private var scheduleIdentity = 0
    private var scheduleTimer: Timer?
    private var schedDeadline: Date?
    private var schedInterval: TimeInterval?
    private var schedRounds = 1
    private var schedFired = 0
    private var schedLabel = ""

    /// Fire an action after a delay, or repeatedly on an interval
    /// for a set number of rounds. Runs while the app is open —
    /// iOS suspends background apps, and the UI says so.
    func schedule(after delay: TimeInterval, every interval: TimeInterval?,
                  rounds: Int, label: String, action: @escaping () -> Void) {
        cancelSchedule()
        scheduleIdentity += 1
        let identity = scheduleIdentity
        schedLabel = label
        schedInterval = interval
        schedRounds = interval == nil ? 1 : max(1, rounds)
        schedFired = 0
        line("timed: \(label) — first fire in \(Int(delay))s"
             + (interval != nil
                ? ", then every \(Int(interval!))s × \(schedRounds)" : ""))
        func arm(after wait: TimeInterval) {
            schedDeadline = Date().addingTimeInterval(wait)
            refreshScheduleStatus()
            let item = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self,
                          self.scheduleIdentity == identity else { return }
                    // The identity check above is the initiation guard:
                    // a stale or cancelled item never runs and never
                    // consumes a round — the count moves only once the
                    // send is actually about to initiate.
                    self.schedFired += 1
                    self.line("timed: firing \(label) — round "
                              + "\(self.schedFired)/\(self.schedRounds)")
                    action()
                    guard self.scheduleIdentity == identity else { return }
                    if self.schedFired < self.schedRounds,
                       let interval = self.schedInterval {
                        arm(after: interval)
                    } else {
                        let doneLabel = label
                        self.cancelSchedule()
                        self.toasts?.show(
                            "Timed delivery finished — \(doneLabel)")
                    }
                }
            }
            scheduleItems.append(item)
            DispatchQueue.global().asyncAfter(deadline: .now() + wait,
                                              execute: item)
        }
        scheduleTimer = Timer.scheduledTimer(
            withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.refreshScheduleStatus()
            }
        arm(after: delay)
    }

    func cancelSchedule() {
        scheduleIdentity += 1
        scheduleItems.forEach { $0.cancel() }
        scheduleItems = []
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        schedDeadline = nil
        if Thread.isMainThread {
            scheduleStatus = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.scheduleStatus = nil
            }
        }
    }

    private func refreshScheduleStatus() {
        guard let deadline = schedDeadline else { return }
        let secs = max(0, Int(deadline.timeIntervalSinceNow.rounded()))
        scheduleStatus = "Timed · \(schedLabel) · round "
            + "\(schedFired + 1)/\(schedRounds) in \(secs)s"
    }

    // MARK: SnatchSteal

    @Published var snatchBusy = false
    @Published var snatchBytes = 0
    @Published var snatchResult: (label: String, data: Data)?

    /// The receive-side weapon: knock (optionally, with a probe
    /// payload), then take everything the target sends back until
    /// it closes, goes quiet past the cap, or 64 KB is in the bag.
    /// The haul is kept on the result card and written to history.
    func snatch(target: SendTarget, probe: Data?, framing: String) {
        switch target {
        case .tcp(let host, let port, let tls):
            guard let nwPort = NWEndpoint.Port(
                    rawValue: UInt16(clamping: port)) else { return }
            let params = tls ? NWParameters(tls: NWProtocolTLS.Options())
                             : .tcp
            snatchRun(NWConnection(host: NWEndpoint.Host(host),
                                   port: nwPort, using: params),
                      label: target.raw, probe: probe, framing: framing)
        case .udp(let host, let port):
            guard let nwPort = NWEndpoint.Port(
                    rawValue: UInt16(clamping: port)) else { return }
            snatchRun(NWConnection(host: NWEndpoint.Host(host),
                                   port: nwPort, using: .udp),
                      label: target.raw, probe: probe, framing: framing)
        case .http(let url, let https):
            let host = url.host ?? ""
            let port = url.port ?? (https ? 443 : 80)
            snatch(target: .tcp(host: host, port: port, tls: https),
                   probe: probe, framing: framing)
        default:
            toasts?.show("SnatchSteal needs a network target",
                         error: true)
        }
    }

    func snatchPhone(name: String, probe: Data?, framing: String) {
        let endpoint = NWEndpoint.service(name: name,
                                          type: Mouth.bonjourType,
                                          domain: "local.", interface: nil)
        snatchRun(NWConnection(to: endpoint, using: .tcp),
                  label: "phone \(name)", probe: probe, framing: framing)
    }

    private func snatchRun(_ connection: NWConnection, label: String,
                           probe: Data?, framing: String) {
        guard !snatchBusy else { return }
        DispatchQueue.main.async { [weak self] in
            self?.snatchBusy = true
            self?.snatchBytes = 0
            self?.snatchResult = nil
        }
        var loot = Data()
        var finished = false
        var idleGeneration = 0
        let finishLock = NSLock()
        func finish() {
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            let captured = loot
            DispatchQueue.main.async { [weak self] in
                self?.snatchBusy = false
                self?.snatchResult = (label: label, data: captured)
                self?.logExchange("snatch", label,
                                  sent: probe?.count ?? 0, reply: captured)
                self?.toasts?.show(
                    captured.isEmpty ? "Snatch came back empty"
                                     : "Snatched \(captured.count) bytes",
                    error: captured.isEmpty)
            }
        }
        func armIdleTimer() {
            // 3s of quiet ends the snatch (the 15s wall below still
            // bounds the whole operation). Each chunk bumps the
            // generation, which retires the previous timer.
            let seen = idleGeneration
            queue.asyncAfter(deadline: .now() + 3) {
                if idleGeneration == seen { finish() }
            }
        }
        func drain() {
            armIdleTimer()
            connection.receive(minimumIncompleteLength: 1,
                               maximumLength: 65536) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    // Hard 64 KB cap: keep only what still fits and
                    // finish the moment the bag is full.
                    let remaining = 65536 - loot.count
                    if remaining > 0 {
                        loot += data.prefix(remaining)
                    }
                    idleGeneration += 1
                    let count = loot.count
                    DispatchQueue.main.async { [weak self] in
                        self?.snatchBytes = count
                    }
                    if count >= 65536 { finish(); return }
                }
                if isComplete || error != nil {
                    finish()
                } else {
                    drain()
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let probe = probe {
                    let framed = PayloadKit.frame(probe, framing: framing)
                    connection.send(content: framed,
                                    completion: .contentProcessed { _ in
                                        drain()
                                    })
                } else {
                    drain()
                }
            case .failed:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { finish() }
    }

    // MARK: Bonjour discovery of other phones

    /// Watch for other phones serving nightjar-hack on the local
    /// network. Their TCP listener advertises `_nightjar._tcp`; the
    /// names listed here are what the Send tab offers as one-tap
    /// targets.
    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjour(type: Mouth.bonjourType, domain: nil),
            using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let mine = UIDevice.current.name
            let names = results.compactMap { result -> String? in
                if case .service(let name, _, _, _) = result.endpoint {
                    // A phone that serves and browses sees itself;
                    // you cannot send to yourself from the list.
                    return name == mine ? nil : name
                }
                return nil
            }
            DispatchQueue.main.async {
                self?.nearbyPhones = names.sorted()
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    // MARK: HTTP send

    func sendHTTP(target: SendTarget, payload: Data, framing: String, method: String,
                  timeout: TimeInterval,
                  completion: ((Bool) -> Void)? = nil) {
        guard case .http(let url, _) = target else {
            completion?(false)
            return
        }
        var finalURL = url
        var body: Data? = nil
        if method == "GET" || method == "HEAD" {
            if !payload.isEmpty {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = components?.queryItems ?? []
                items.append(URLQueryItem(name: "payload", value: payload.base64EncodedString()))
                components?.queryItems = items
                if let resolved = components?.url { finalURL = resolved }
            }
        } else {
            body = PayloadKit.frame(payload, framing: framing)
        }
        var request = URLRequest(url: finalURL, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("nightjar-send", forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue(framing == "json" ? "application/json" : "application/octet-stream",
                             forHTTPHeaderField: "Content-Type")
        }
        line("sending \(payload.count) bytes over http to \(url.absoluteString) (\(method))")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.line("nightjar: \(error.localizedDescription)")
                self?.ui("HTTP send failed: \(error.localizedDescription)", error: true)
                completion?(false)
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reply = data ?? Data()
            let ok = (200..<400).contains(status)
            // State first, callback last: lastReply and the history
            // entry are updated BEFORE completion fires, so a caller
            // reacting to completion already sees the final state.
            self?.logExchange("http", request.url?.absoluteString ?? "http",
                              sent: body?.count ?? payload.count, reply: reply)
            self?.noteReply(label: "http", data: reply)
            if ok {
                self?.uiSuccess("HTTP \(status) — \(reply.count) bytes back")
            } else {
                self?.ui("HTTP \(status)", error: true)
            }
            self?.line("  HTTP \(status), \(reply.count) byte reply")
            if !reply.isEmpty {
                for l in PayloadKit.hexdump(reply).components(separatedBy: "\n") {
                    self?.line(l)
                }
            }
            completion?(ok)
        }.resume()
    }

    // MARK: MQTT plant

    /// Plant a retained MQTT message properly: its own connection,
    /// a real CONNECT/CONNACK handshake, then the PUBLISH. Completes
    /// true only when CONNACK accepts (byte 0 == 0x20, return code 0)
    /// and the publish has been handed to the socket; every failure
    /// path completes false, exactly once. (UI calls this signature.)
    func plantMQTT(host: String, port: Int, topic: String, payload: Data,
                   completion: @escaping (Bool) -> Void) {
        let connectPacket = PayloadKit.mqttConnect(clientID: "nightjar-hack")
        let publishPacket = PayloadKit.mqttPublish(topic: topic, payload: payload,
                                                   retain: true)
        guard !connectPacket.isEmpty, !publishPacket.isEmpty,
              let endpointPort = NWEndpoint.Port(
                rawValue: UInt16(clamping: port)) else {
            completion(false)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: endpointPort, using: .tcp)
        var finished = false
        func finish(_ ok: Bool) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            completion(ok)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: connectPacket,
                                completion: .contentProcessed { error in
                    if error != nil { finish(false); return }
                    connection.receive(minimumIncompleteLength: 1,
                                       maximumLength: 1024) {
                        data, _, _, error in
                        // CONNACK: 0x20, remaining length, flags, rc.
                        guard error == nil, let data = data, data.count >= 4,
                              data[0] == 0x20, data[3] == 0 else {
                            finish(false)
                            return
                        }
                        connection.send(content: publishPacket,
                                        completion: .contentProcessed { error in
                            finish(error == nil)
                        })
                    }
                })
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        // 3s for the CONNACK (and the whole plant) to land.
        queue.asyncAfter(deadline: .now() + 3) { finish(false) }
    }

    // MARK: BLE beacon + GATT host (one peripheral manager)

    private func ensurePeripheral() -> CBPeripheralManager {
        if let manager = peripheralManager { return manager }
        // The restore identifier is what lets iOS relaunch the app for
        // a Bluetooth event after the system has killed it.
        let manager = CBPeripheralManager(
            delegate: self, queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey:
                        "net.nosuchmachine.nightjarhack.peripheral"])
        peripheralManager = manager
        return manager
    }

    // The GATT host, unlike the socket listeners, is allowed to live
    // in the background — so it can be *armed once* and left. The arm
    // (and the payload it hosts) persists; the host re-arms itself on
    // radio power-on, on state restoration, and on foregrounding.
    private var gattArmOn: Bool {
        get { UserDefaults.standard.bool(forKey: "gattArm.on") }
        set { UserDefaults.standard.set(newValue, forKey: "gattArm.on") }
    }

    private func rearmGattHostIfNeeded() {
        guard !gattHostOn, gattArmOn else { return }
        let payload = UserDefaults.standard.data(forKey: "gattArm.payload")
            ?? Data()
        let name = UserDefaults.standard.string(forKey: "gattArm.name")
            ?? "nightjar-post"
        line("re-arming the GATT host (it was left on)")
        startGattHost(payload: payload, name: name)
    }

    /// Called when the app comes to the foreground.
    func appBecameActive() {
        guard gattArmOn, !gattHostOn else { return }
        let manager = ensurePeripheral()
        if manager.state == .poweredOn {
            rearmGattHostIfNeeded()
        }
        // Otherwise didUpdateState re-arms when the radio reports in.
    }

    // The beacon/host functions are called from the views (main queue)
    // and the manager's delegate queue is the main queue too, so the
    // @Published flags are set directly here — intent first, then the
    // radio work, which refreshAdvertising replays whenever the radio
    // reports powered on.

    func startBeacon(payload: Data, name: String) {
        if gattHostOn {
            line("nightjar: stop the GATT host before starting a beacon")
            return
        }
        beaconPayload = payload
        beaconName = name
        wantBeacon = true
        beaconOn = true
        _ = ensurePeripheral()
        refreshAdvertising()
        ui("Beacon on — the payload is on the air")
    }

    func stopBeacon() {
        wantBeacon = false
        beaconOn = false
        ui("Beacon off")
        if gattHostOn {
            refreshAdvertising()
        } else {
            peripheralManager?.stopAdvertising()
        }
    }

    func startGattHost(payload: Data, name: String) {
        gattPayload = payload
        beaconName = name
        gattHostOn = true
        gattArmOn = true
        UserDefaults.standard.set(payload, forKey: "gattArm.payload")
        UserDefaults.standard.set(name, forKey: "gattArm.name")
        let manager = ensurePeripheral()
        ui("GATT host armed — writes land in the Serve inbox")
        if gattCharacteristic == nil && !gattServiceRestored {
            let characteristic = CBMutableCharacteristic(
                type: Mouth.charUUID, properties: [.read, .write, .notify],
                value: nil, permissions: [.readable, .writeable])
            let service = CBMutableService(type: Mouth.serviceUUID, primary: true)
            service.characteristics = [characteristic]
            gattCharacteristic = characteristic
            manager.add(service)  // advertising refresh happens in didAdd
        } else {
            refreshAdvertising()
        }
    }

    func stopGattHost() {
        gattArmOn = false
        // The armed payload goes too: a stopped host must not leave a
        // payload behind in UserDefaults for a later relaunch to serve.
        UserDefaults.standard.removeObject(forKey: "gattArm.payload")
        UserDefaults.standard.removeObject(forKey: "gattArm.name")
        gattServiceRestored = false
        gattHostOn = false
        ui("GATT host off")
        peripheralManager?.removeAllServices()
        gattCharacteristic = nil
        if wantBeacon {
            beaconOn = true
            refreshAdvertising()
        } else {
            peripheralManager?.stopAdvertising()
        }
    }

    private func refreshAdvertising() {
        guard let manager = peripheralManager, manager.state == .poweredOn else { return }
        var advertisement: [String: Any] = [
            CBAdvertisementDataLocalNameKey: beaconName,
        ]
        if gattHostOn {
            advertisement[CBAdvertisementDataServiceUUIDsKey] = [Mouth.serviceUUID]
            beaconOn = false
        } else if wantBeacon {
            // ble:// : the payload rides in service data, the one payload
            // slot iOS lets an app set. (Python stamps manufacturer data
            // too; iOS offers no API for that.)
            advertisement[CBAdvertisementDataServiceUUIDsKey] = [Mouth.serviceUUID]
            advertisement[CBAdvertisementDataServiceDataKey] = [Mouth.serviceUUID: beaconPayload]
            beaconOn = true
        } else {
            manager.stopAdvertising()
            return
        }
        manager.stopAdvertising()
        manager.startAdvertising(advertisement)
    }

    // MARK: BLE write (central role)

    func scanForWriteTargets() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        guard centralManager?.state == .poweredOn else {
            line("nightjar: Bluetooth is not ready for the write scan")
            ui("Bluetooth is not ready for the write scan", error: true)
            return
        }
        writeTargets = []
        writePeripherals = [:]
        centralManager?.scanForPeripherals(withServices: nil, options: nil)
        writeScanning = true
        line("scanning for peripherals to write to…")
        queue.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.centralManager?.stopScan()
            DispatchQueue.main.async { self?.writeScanning = false }
        }
    }

    func write(to target: WriteTarget, payload: Data) {
        guard let manager = centralManager, manager.state == .poweredOn else {
            line("nightjar: Bluetooth is not ready")
            ui("Bluetooth is not ready — give it a second", error: true)
            return
        }
        manager.stopScan()
        writeScanning = false
        pendingWrite = (target.peripheral, payload)
        writeToken += 1
        let token = writeToken
        let peripheral = target.peripheral
        line("connecting to \(target.name ?? target.id.uuidString)…")
        ui("Writing to \(target.name ?? "device")…")
        manager.connect(target.peripheral, options: nil)
        // 15s timeout: a write that never lands fails and clears the
        // pending state instead of hanging the next write forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.writeToken == token,
                  self.pendingWrite?.peripheral === peripheral else { return }
            self.pendingWrite = nil
            self.centralManager?.cancelPeripheralConnection(peripheral)
            self.line("nightjar: BLE write timed out")
            self.ui("BLE write timed out", error: true)
        }
    }

    // MARK: Listen -> Send handoff

    func requestWrite(to id: UUID, label: String) {
        pendingWriteID = id
        pendingWriteLabel = label
    }

    func clearPendingWrite() {
        pendingWriteID = nil
        pendingWriteLabel = nil
    }

    /// Write to a device handed over from the Listen tab. CoreBluetooth
    /// identifiers are stable per app on a phone, so the ear's peripheral
    /// can be re-fetched here by identifier — the two halves share the
    /// identifier, never any radio state.
    func writeHandoff(payload: Data) {
        guard let id = pendingWriteID else { return }
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        guard let manager = centralManager, manager.state == .poweredOn else {
            line("nightjar: Bluetooth is not ready yet — give it a second and tap Write again")
            return
        }
        guard let peripheral = manager.retrievePeripherals(
            withIdentifiers: [id]).first else {
            line("nightjar: that device is no longer in this phone's Bluetooth cache")
            return
        }
        write(to: WriteTarget(id: id, peripheral: peripheral,
                              name: pendingWriteLabel, rssi: nil),
              payload: payload)
        clearPendingWrite()
    }

    // MARK: Shortcuts

    enum ShortcutError: Error, LocalizedError {
        case appNotRunning
        case needsTheApp
        var errorDescription: String? {
            switch self {
            case .appNotRunning:
                return "nightjar-hack is not running; open it once first."
            case .needsTheApp:
                return "That target needs the app: use the Send tab instead."
            }
        }
    }

    static func sendFromShortcut(targetText: String, payloadText: String) throws {
        guard let mouth = shared else { throw ShortcutError.appNotRunning }
        let target = try SendTarget.parse(targetText)
        let data = Data(payloadText.utf8)
        switch target {
        case .http(_, _):
            mouth.sendHTTP(target: target, payload: data, framing: "raw",
                           method: "POST", timeout: 10)
        case .tcp(_, _, _), .udp(_, _):
            mouth.sendNetwork(target: target, payload: data, framing: "raw",
                              read: false, timeout: 5)
        default:
            throw ShortcutError.needsTheApp
        }
    }
}

// MARK: - Peripheral manager delegate (beacon / GATT host)

extension Mouth: CBPeripheralManagerDelegate {
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           willRestoreState dict: [String: Any]) {
        // iOS relaunched the app for a Bluetooth event; the saved arm
        // replays in peripheralManagerDidUpdateState, which follows.
        line("bluetooth state restored — re-arming what was left on")
        // If a service with our UUID is among the restored services it
        // already exists on the manager — adopt it instead of letting
        // startGattHost add a duplicate.
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey]
                as? [CBService],
           let service = services.first(where: { $0.uuid == Mouth.serviceUUID }) {
            gattServiceRestored = true
            if let chars = service.characteristics,
               let characteristic = chars.first(
                   where: { $0.uuid == Mouth.charUUID })
                   as? CBMutableCharacteristic {
                gattCharacteristic = characteristic
            }
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            rearmGattHostIfNeeded()
            if wantBeacon || gattHostOn {
                refreshAdvertising()
            }
        } else {
            // The radio is gone; the intent stays, so a later power-on
            // restarts advertising — but nothing is on the air now.
            beaconOn = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService,
                           error: Error?) {
        if let error = error {
            line("nightjar: GATT service failed: \(error.localizedDescription)")
            // No service, no host: clear the optimistic host state.
            gattHostOn = false
            gattCharacteristic = nil
            return
        }
        refreshAdvertising()
    }

    func peripheralManagerDidStartAdvertising(
        _ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            // Advertising never started: clear the optimistic on-air
            // state set by startBeacon/startGattHost and say so.
            line("nightjar: advertising failed: \(error.localizedDescription)")
            beaconOn = false
            gattHostOn = false
            return
        }
        // Confirmed on the air: reflect the live intent.
        if gattHostOn {
            gattHostOn = true
        } else if wantBeacon {
            beaconOn = true
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveRead request: CBATTRequest) {
        // Honor the offset: a long read asks for the slice from there,
        // and an offset past the value is an error, not a full reply.
        guard request.offset >= 0, request.offset <= gattPayload.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = request.offset == 0
            ? gattPayload
            : gattPayload.subdata(in: request.offset..<gattPayload.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        // A long write arrives as a batch: coalesce the chunks at
        // their offsets into ONE payload, land it in the inbox once,
        // and respond ONCE (to the first request), per ATT.
        guard let first = requests.first else { return }
        let ours = requests.filter { $0.characteristic.uuid == Mouth.charUUID }
        guard !ours.isEmpty else {
            peripheral.respond(to: first, withResult: .success)
            return
        }
        var assembled = Data()
        for request in ours {
            guard let value = request.value else { continue }
            let offset = request.offset
            guard offset >= 0, offset <= assembled.count else {
                peripheral.respond(to: first, withResult: .invalidOffset)
                return
            }
            if offset < assembled.count {
                assembled.replaceSubrange(
                    offset..<min(assembled.count, offset + value.count),
                    with: value.prefix(assembled.count - offset))
                if offset + value.count > assembled.count {
                    assembled.append(value.suffix(
                        offset + value.count - assembled.count))
                }
            } else {
                assembled.append(value)
            }
        }
        gattPayload = assembled
        receive(transport: "ble-gatt", peer: "central", data: assembled)
        peripheral.respond(to: first, withResult: .success)
    }
}

// MARK: - Central manager delegate (BLE write)

extension Mouth: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if writePeripherals[peripheral.identifier] == nil {
            writePeripherals[peripheral.identifier] = peripheral
        }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
        DispatchQueue.main.async {
            if let index = self.writeTargets.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.writeTargets[index].name = name
                self.writeTargets[index].rssi = RSSI.intValue
            } else {
                self.writeTargets.append(WriteTarget(id: peripheral.identifier,
                                                       peripheral: peripheral,
                                                       name: name, rssi: RSSI.intValue))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        line("nightjar: connect failed: \(error?.localizedDescription ?? "unknown")")
        if pendingWrite?.peripheral.identifier == peripheral.identifier {
            pendingWrite = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        // Only the pending target's own disconnect clears the pending
        // write — some other peripheral dropping must not eat it.
        if pendingWrite?.peripheral.identifier == peripheral.identifier {
            pendingWrite = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let pending = pendingWrite, pending.peripheral === peripheral else { return }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let pending = pendingWrite, pending.peripheral === peripheral else { return }
        let candidates = (service.characteristics ?? []).filter {
            $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)
        }
        guard let characteristic = candidates.first(where: { $0.uuid == Mouth.charUUID })
            ?? candidates.first else {
            return  // keep looking in other services; didDiscover fires per service
        }
        let withResponse = characteristic.properties.contains(.write)
        peripheral.writeValue(pending.payload, for: characteristic,
                              type: withResponse ? .withResponse : .withoutResponse)
        line("wrote \(pending.payload.count) bytes to \(characteristic.uuid.uuidString) "
             + "on \(peripheral.name ?? peripheral.identifier.uuidString)")
        logExchange("ble-write",
                    peripheral.name ?? peripheral.identifier.uuidString,
                    sent: pending.payload.count, reply: nil)
        uiSuccess("Payload written (\(pending.payload.count) bytes)")
        pendingWrite = nil
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            line("nightjar: write failed: \(error.localizedDescription)")
            ui("Write failed: \(error.localizedDescription)", error: true)
        }
    }
}

// MARK: - Serve (listeners)

extension Mouth {
    /// Start any combination of TCP / UDP / HTTP listeners. Mirrors
    /// `nightjar serve`: each arrival is unframed (with the chosen
    /// framing), recorded in the inbox, and answered with the reply
    /// when one is set. Foreground only — iOS suspends listeners when
    /// the app leaves the screen.
    func startServe(tcpPort: Int?, udpPort: Int?, httpPort: Int?,
                    reply: String, framing: String, echo: Bool = false) {
        stopServe()
        // Port hygiene: parse + clamp each enabled port ONCE, here;
        // the bind, the announce text and lastServeParams all use
        // these sanitized values and nothing else.
        let cleanTCP = tcpPort.map { min(65535, max(1, $0)) }
        let cleanUDP = udpPort.map { min(65535, max(1, $0)) }
        let cleanHTTP = httpPort.map { min(65535, max(1, $0)) }
        serveGeneration += 1
        let generation = serveGeneration
        lastServeParams = (cleanTCP, cleanUDP, cleanHTTP, reply, framing, echo)
        // Reply text/mode/framing are a SNAPSHOT from this moment:
        // the arrival sink answers with these, never with whatever
        // the live values happen to be when a peer shows up.
        let snapReply = Data(reply.utf8)
        let snapEcho = echo
        let snapFraming = framing
        serveReply = snapReply
        serveEcho = echo
        serveFraming = framing
        serveError = nil
        // Arrivals banner as notifications; ask while the user is
        // already in "receive things" mode. In stealth, no dialogs:
        // the ask waits for a non-stealth start.
        if !stealth {
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]) { _, _ in }
        }
        var started: [String] = []
        do {
            if let port = cleanTCP {
                listeners.append(try makeListener(port: port, params: .tcp, bonjour: !stealth, generation: generation) { [weak self] conn in
                    self?.handleStreamConnection(conn, transport: "tcp", http: false,
                                                  generation: generation,
                                                  snapReply: snapReply, snapEcho: snapEcho,
                                                  snapFraming: snapFraming)
                })
                started.append("tcp://0.0.0.0:\(port)")
            }
            if let port = cleanUDP {
                listeners.append(try makeListener(port: port, params: .udp, generation: generation) { [weak self] conn in
                    self?.handleDatagramConnection(conn, generation: generation,
                                                    snapReply: snapReply, snapEcho: snapEcho,
                                                    snapFraming: snapFraming)
                })
                started.append("udp://0.0.0.0:\(port)")
            }
            if let port = cleanHTTP {
                listeners.append(try makeListener(port: port, params: .tcp, generation: generation) { [weak self] conn in
                    self?.handleStreamConnection(conn, transport: "http", http: true,
                                                  generation: generation,
                                                  snapReply: snapReply, snapEcho: snapEcho,
                                                  snapFraming: snapFraming)
                })
                started.append("http://0.0.0.0:\(port)/")
            }
        } catch {
            stopServe()
            DispatchQueue.main.async {
                self.serveError = "nightjar: \(error.localizedDescription)"
                self.ui("Serving failed: \(error.localizedDescription)", error: true)
            }
            return
        }
        if started.isEmpty {
            DispatchQueue.main.async {
                self.serveError = "nightjar: no listener selected"
                self.ui("No listener selected", error: true)
            }
            return
        }
        DispatchQueue.main.async { self.serveRunning = true }
        ui("Serving: \(started.joined(separator: ", "))")
        line("serve: \(started.joined(separator: ", ")) — foreground only")
    }

    func stopServe() {
        let wasRunning = serveRunning
        serveGeneration += 1
        for listener in listeners { listener.cancel() }
        listeners = []
        for connection in serveConnections { connection.cancel() }
        serveConnections = []
        DispatchQueue.main.async { self.serveRunning = false }
        if wasRunning { ui("Stopped serving") }
    }

    private func trackServeConnection(_ connection: NWConnection) {
        serveConnections.append(connection)
    }

    private func untrackServeConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        serveConnections.removeAll { ObjectIdentifier($0) == id }
    }

    private func makeListener(port: Int, params: NWParameters, bonjour: Bool = false,
                              generation: Int,
                              onConnection: @escaping (NWConnection) -> Void) throws -> NWListener {
        guard let endpoint = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw MouthError.message("bad port \(port)")
        }
        let listener = try NWListener(using: params, on: endpoint)
        if bonjour {
            // Other phones find this one by name — no IP addresses.
            listener.service = NWListener.Service(
                name: nil, type: Mouth.bonjourType, domain: nil)
        }
        listener.newConnectionHandler = onConnection
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                DispatchQueue.main.async {
                    // A stale listener's failure must not clear the
                    // state of the serve that replaced it.
                    guard let self = self,
                          self.serveGeneration == generation else { return }
                    self.serveError = "nightjar: listener failed: \(error.localizedDescription)"
                    self.serveRunning = false
                }
            }
        }
        listener.start(queue: queue)
        return listener
    }

    /// TCP (raw) and HTTP share an accumulate-then-sink shape, like
    /// send.py's `_tcp_conn`: sink when the peer half-closes, or after a
    /// short idle pause once bytes have arrived.
    private func handleStreamConnection(_ connection: NWConnection, transport: String,
                                        http: Bool, generation: Int,
                                        snapReply: Data, snapEcho: Bool,
                                        snapFraming: String) {
        trackServeConnection(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.untrackServeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        var buffer = Data()
        var sunk = false
        var chunkGeneration = 0
        let peer = "\(connection.endpoint)"
        func sinkAndAnswer() {
            guard !sunk else {
                connection.cancel()
                return
            }
            // Arrivals from a stale generation (a peer accepted before
            // Stop, landing late) are dropped, never inboxed.
            guard generation == serveGeneration else {
                sunk = true
                connection.cancel()
                return
            }
            guard !buffer.isEmpty else {
                connection.cancel()
                return
            }
            sunk = true
            if http {
                // Framing applies to HTTP arrivals too: the body goes
                // through the same unframe step as TCP/UDP payloads
                // before it reaches the inbox or any echo reply.
                let body = PayloadKit.unframe(Self.httpBody(buffer),
                                              framing: snapFraming)
                receive(transport: "http", peer: peer, data: body)
                let payload = snapEcho ? body
                    : (snapReply.isEmpty ? Data("ok\n".utf8) : snapReply)
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                    + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                // HEAD: same headers (Content-Length included), no body.
                let response = Self.httpMethod(buffer) == "HEAD"
                    ? Data(head.utf8) : Data(head.utf8) + payload
                connection.send(content: response,
                                completion: .contentProcessed { _ in connection.cancel() })
            } else {
                let data = PayloadKit.unframe(buffer, framing: snapFraming)
                receive(transport: transport, peer: peer, data: data)
                let answer = snapEcho ? data : snapReply
                if !answer.isEmpty {
                    connection.send(content: answer,
                                    completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    connection.cancel()
                }
            }
        }
        if http {
            // 30s idle deadline: a peer that never completes a request
            // does not hold the connection (or a tracking slot) forever.
            queue.asyncAfter(deadline: .now() + 30) {
                if !sunk {
                    sunk = true
                    connection.cancel()
                }
            }
        }
        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer += data
                    chunkGeneration += 1
                    if http, Self.httpComplete(buffer) {
                        sinkAndAnswer()
                        return
                    }
                }
                if isComplete || error != nil {
                    sinkAndAnswer()
                } else {
                    // Idle pause (no new chunk for 1.2s): treat as end of
                    // payload, the way send.py's read timeout does. The
                    // generation check keeps a slow sender's later chunks
                    // from being cut off by an earlier chunk's timer.
                    let seen = chunkGeneration
                    self.queue.asyncAfter(deadline: .now() + 1.2) {
                        if chunkGeneration == seen, !buffer.isEmpty { sinkAndAnswer() }
                    }
                    pump()
                }
            }
        }
        pump()
    }

    private func handleDatagramConnection(_ connection: NWConnection,
                                          generation: Int,
                                          snapReply: Data, snapEcho: Bool,
                                          snapFraming: String) {
        trackServeConnection(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.untrackServeConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        func pump() {
            connection.receiveMessage { [weak self] data, _, _, error in
                guard let self = self else { return }
                // A terminal error (including stopServe's cancel) is
                // the only thing that stops the pump.
                if error != nil {
                    self.untrackServeConnection(connection)
                    return
                }
                if let data = data, !data.isEmpty,
                   generation == self.serveGeneration {
                    let unframed = PayloadKit.unframe(data, framing: snapFraming)
                    self.receive(transport: "udp", peer: "\(connection.endpoint)", data: unframed)
                    let answer = snapEcho ? unframed : snapReply
                    if !answer.isEmpty {
                        connection.send(content: answer,
                                        completion: .contentProcessed { _ in })
                    }
                }
                // Always re-arm: the old `!isComplete` condition could
                // retire the pump after one datagram and silently drop
                // every later datagram from the peer.
                pump()
            }
        }
        pump()
    }

    // Minimal HTTP request reading: headers up to CRLFCRLF, then
    // Content-Length bytes of body. Enough for senders like send.py.
    private static func httpHeaderEnd(_ buffer: Data) -> Int? {
        let marker: [UInt8] = [13, 10, 13, 10]
        let bytes = [UInt8](buffer)
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4) where Array(bytes[i..<(i + 4)]) == marker {
            return i + 4
        }
        return nil
    }

    private static func httpContentLength(_ buffer: Data) -> Int {
        guard let end = httpHeaderEnd(buffer),
              let head = String(data: buffer.prefix(end), encoding: .utf8) else { return 0 }
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    /// The request-line method ("GET", "HEAD", …), uppercased.
    private static func httpMethod(_ buffer: Data) -> String {
        let bytes = [UInt8](buffer)
        var lineEnd = bytes.count
        for i in 0..<max(0, bytes.count - 1) where bytes[i] == 13 && bytes[i + 1] == 10 {
            lineEnd = i
            break
        }
        guard let line = String(data: buffer.prefix(lineEnd), encoding: .utf8) else {
            return ""
        }
        return line.split(separator: " ").first
            .map { String($0).uppercased() } ?? ""
    }

    private static func httpIsChunked(_ buffer: Data) -> Bool {
        guard let end = httpHeaderEnd(buffer),
              let head = String(data: buffer.prefix(end), encoding: .utf8) else {
            return false
        }
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased()
                   == "transfer-encoding",
               parts[1].lowercased().contains("chunked") {
                return true
            }
        }
        return false
    }

    private static func httpComplete(_ buffer: Data) -> Bool {
        guard let end = httpHeaderEnd(buffer) else { return false }
        if httpIsChunked(buffer) {
            // Complete only once the terminating 0-chunk has arrived
            // (optionally followed by trailers and the final CRLF).
            let body = buffer.subdata(in: end..<buffer.count)
            let tail: [UInt8] = [48, 13, 10, 13, 10]  // "0\r\n\r\n"
            let bytes = [UInt8](body)
            if bytes.count >= tail.count,
               Array(bytes.suffix(tail.count)) == tail { return true }
            if let text = String(data: body, encoding: .utf8),
               text.contains("\r\n0\r\n"), text.hasSuffix("\r\n\r\n") {
                return true
            }
            return false
        }
        return buffer.count >= end + httpContentLength(buffer)
    }

    private static func httpBody(_ buffer: Data) -> Data {
        guard let end = httpHeaderEnd(buffer) else { return buffer }
        guard buffer.count > end else { return Data() }
        if httpIsChunked(buffer) {
            return httpDechunk(buffer.subdata(in: end..<buffer.count))
        }
        let length = httpContentLength(buffer)
        return buffer.subdata(in: end..<min(buffer.count, end + length))
    }

    /// Reassemble a chunked body: <hex size>CRLF<data>CRLF … 0-chunk.
    private static func httpDechunk(_ body: Data) -> Data {
        var out = Data()
        var pos = 0
        let bytes = [UInt8](body)
        while pos < bytes.count {
            var crlf: Int?
            var i = pos
            while i + 1 < bytes.count {
                if bytes[i] == 13, bytes[i + 1] == 10 { crlf = i; break }
                i += 1
            }
            guard let sizeEnd = crlf,
                  let sizeText = String(data: body.subdata(in: pos..<sizeEnd),
                                        encoding: .utf8),
                  let size = Int(sizeText.trimmingCharacters(in: .whitespaces),
                                 radix: 16) else { break }
            if size == 0 { break }
            let dataStart = sizeEnd + 2
            guard dataStart + size <= bytes.count else { break }
            out.append(body.subdata(in: dataStart..<(dataStart + size)))
            pos = dataStart + size + 2  // skip the trailing CRLF
        }
        return out
    }
}

// MARK: - Saved payloads

struct SavedPayload: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var source: String  // text | hex | base64
    var text: String    // the contents of that source's field
    var xorKey: String
    var useGzip: Bool
    var framing: String
    var builtIn: Bool = false

    init(id: UUID = UUID(), name: String, source: String, text: String,
         xorKey: String, useGzip: Bool, framing: String,
         builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.text = text
        self.xorKey = xorKey
        self.useGzip = useGzip
        self.framing = framing
        self.builtIn = builtIn
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source, text, xorKey, useGzip, framing, builtIn
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        name = try box.decode(String.self, forKey: .name)
        source = try box.decode(String.self, forKey: .source)
        text = try box.decode(String.self, forKey: .text)
        xorKey = try box.decode(String.self, forKey: .xorKey)
        useGzip = try box.decode(Bool.self, forKey: .useGzip)
        framing = try box.decode(String.self, forKey: .framing)
        // Older saves predate the flag; absence means "custom".
        builtIn = try box.decodeIfPresent(Bool.self, forKey: .builtIn)
            ?? false
    }
}

/// The Send tab's payload library: named payloads kept in UserDefaults.
/// Ships with a starter set of built-ins; anything the user saves is a
/// custom entry next to them, and built-ins can be restored if deleted.
final class PayloadBook: ObservableObject {
    @Published private(set) var items: [SavedPayload] = []
    private let key = "payloadBook.v1"

    static let builtIns: [SavedPayload] = [
        SavedPayload(name: "hello", source: "text", text: "hello",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "ping", source: "text", text: "ping",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "JSON hello", source: "text",
                     text: "{\"hello\":\"nightjar\"}",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "Wake-on-LAN (edit the MAC)", source: "hex",
                     text: "ff ff ff ff ff ff "
                         + String(repeating: "00 11 22 33 44 55 ", count: 16),
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "HTTP GET / (raw)", source: "hex",
                     text: "47 45 54 20 2f 20 48 54 54 50 2f 31 2e 30 0d 0a 0d 0a",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "32 x A (length test)", source: "text",
                     text: String(repeating: "A", count: 32),
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "DNS query — example.com (UDP 53)",
                     source: "hex",
                     text: "1a 2b 01 00 00 01 00 00 00 00 00 00 "
                         + "07 65 78 61 6d 70 6c 65 03 63 6f 6d 00 "
                         + "00 01 00 01",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "NTP time request (UDP 123)", source: "hex",
                     text: "1b " + String(repeating: "00 ", count: 47),
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "Redis PING (RESP)", source: "text",
                     text: "*1\r\n$4\r\nPING\r\n",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "memcached stats", source: "text",
                     text: "stats\r\n",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "SMTP EHLO", source: "text",
                     text: "EHLO nightjar\r\n",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "MQTT CONNECT (client: nightjar)",
                     source: "hex",
                     text: "10 14 00 04 4d 51 54 54 04 02 00 3c "
                         + "00 08 6e 69 67 68 74 6a 61 72",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "Modbus read coils (TCP 502)", source: "hex",
                     text: "00 01 00 00 00 06 01 01 00 00 00 08",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "CoAP GET /.well-known/core (UDP 5683)",
                     source: "hex",
                     text: "44 01 be ef 6e 6a 61 72 ba "
                         + "77 65 6c 6c 2d 6b 6e 6f 77 6e 04 63 6f 72 65",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "Printer test page (TCP 9100)", source: "text",
                     text: "nightjar-hack says hello\r\n\u{0C}",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "SNMP get sysDescr (UDP 161)", source: "hex",
                     text: "30 29 02 01 00 04 06 70 75 62 6c 69 63 a0 1c "
                         + "02 04 00 00 04 d2 02 01 00 02 01 00 30 0e 30 0c "
                         + "06 08 2b 06 01 02 01 01 01 00 05 00",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "SIP OPTIONS (UDP/TCP 5060)", source: "text",
                     text: "OPTIONS sip:nightjar@127.0.0.1 SIP/2.0\r\n"
                         + "Via: SIP/2.0/UDP 127.0.0.1;branch=z9hG4bK-nh\r\n"
                         + "From: <sip:nightjar@127.0.0.1>;tag=1\r\n"
                         + "To: <sip:nightjar@127.0.0.1>\r\n"
                         + "Call-ID: 1@127.0.0.1\r\nCSeq: 1 OPTIONS\r\n"
                         + "Content-Length: 0\r\n\r\n",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "Postgres SSLRequest (TCP 5432)", source: "hex",
                     text: "00 00 00 08 04 d2 16 2f",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
        SavedPayload(name: "HTTP OPTIONS (raw)", source: "text",
                     text: "OPTIONS * HTTP/1.0\r\n\r\n",
                     xorKey: "", useGzip: false, framing: "raw",
                     builtIn: true),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode([SavedPayload].self,
                                                       from: data) {
                items = decoded
            } else {
                // The persisted blob is unreadable (older format,
                // corruption): run on the built-ins in memory but do
                // NOT persist over it — storage stays untouched until
                // a later successful mutation replaces it knowingly.
                items = PayloadBook.builtIns
            }
        } else {
            items = PayloadBook.builtIns
            persist()
        }
    }

    var missingBuiltIns: [SavedPayload] {
        // Dedupe by NAME against ALL entries: a custom payload the
        // user named like a built-in already occupies that name, so
        // restoring must not stack a duplicate next to it.
        PayloadBook.builtIns.filter { seed in
            !items.contains { $0.name == seed.name }
        }
    }

    func restoreBuiltIns() {
        items.insert(contentsOf: missingBuiltIns, at: 0)
        persist()
    }

    func add(_ item: SavedPayload) {
        // Same name replaces, never duplicates.
        if let index = items.firstIndex(where: { $0.name == item.name }) {
            items[index] = item
        } else {
            items.append(item)
        }
        persist()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension Mouth: UNUserNotificationCenterDelegate {
    /// Banner + sound even while the app is in the foreground, so an
    /// arriving payload pops instead of silently joining the inbox.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
