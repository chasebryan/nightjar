import Compression
import CoreBluetooth
import Foundation
import Network

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
    private var centralManager: CBCentralManager?
    private var writePeripherals: [UUID: CBPeripheral] = [:]
    private var pendingWrite: (peripheral: CBPeripheral, payload: Data)?
    private var listeners: [NWListener] = []
    private var serveReply: Data = Data()
    private var serveFraming = "raw"

    static let serviceUUID = CBUUID(string: "FFF0")
    static let charUUID = CBUUID(string: "FFF1")

    private func line(_ text: String) {
        DispatchQueue.main.async {
            self.sendLines.append(text)
            if self.sendLines.count > 300 { self.sendLines.removeFirst(self.sendLines.count - 300) }
        }
    }

    private func receive(transport: String, peer: String, data: Data) {
        DispatchQueue.main.async {
            self.inbox.insert(ReceivedPayload(at: Date(), transport: transport,
                                              peer: peer, data: data), at: 0)
            if self.inbox.count > 200 { self.inbox.removeLast(self.inbox.count - 200) }
        }
    }

    func clearSendLog() { sendLines = [] }
    func clearInbox() { inbox = [] }

    var inboxJSONL: String {
        inbox.reversed().map { $0.jsonLine }.joined(separator: "\n")
    }

    // MARK: Network send (tcp / udp / tls)

    func sendNetwork(target: SendTarget, payload: Data, framing: String,
                     read: Bool, timeout: TimeInterval) {
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
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            line("nightjar: bad port \(port)")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: params)
        var replied = Data()
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            connection.cancel()
            if read {
                if replied.isEmpty {
                    line("  (no reply)")
                } else {
                    line("  <- \(replied.count) byte reply")
                    for l in PayloadKit.hexdump(replied).components(separatedBy: "\n") {
                        line(l)
                    }
                    if let text = String(data: replied, encoding: .utf8),
                       !text.isEmpty, text.allSatisfy({ $0.isPrint || $0.isNewline }) {
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
                self?.line("sent \(framed.count) bytes over \(target.raw)")
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error = error {
                        self?.line("nightjar: send failed: \(error.localizedDescription)")
                        finish()
                        return
                    }
                    if read {
                        receiveMore()
                    } else {
                        finish()
                    }
                })
            case .failed(let error):
                self?.line("nightjar: \(error.localizedDescription)")
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout + 2) { finish() }
    }

    // MARK: HTTP send

    func sendHTTP(target: SendTarget, payload: Data, framing: String, method: String,
                  timeout: TimeInterval) {
        guard case .http(let url, _) = target else { return }
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
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reply = data ?? Data()
            self?.line("  HTTP \(status), \(reply.count) byte reply")
            if !reply.isEmpty {
                for l in PayloadKit.hexdump(reply).components(separatedBy: "\n") {
                    self?.line(l)
                }
            }
        }.resume()
    }

    // MARK: BLE beacon + GATT host (one peripheral manager)

    private func ensurePeripheral() -> CBPeripheralManager {
        if let manager = peripheralManager { return manager }
        let manager = CBPeripheralManager(delegate: self, queue: nil)
        peripheralManager = manager
        return manager
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
    }

    func stopBeacon() {
        wantBeacon = false
        beaconOn = false
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
        let manager = ensurePeripheral()
        if gattCharacteristic == nil {
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
        gattHostOn = false
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
            return
        }
        manager.stopScan()
        writeScanning = false
        pendingWrite = (target.peripheral, payload)
        line("connecting to \(target.name ?? target.id.uuidString)…")
        manager.connect(target.peripheral, options: nil)
    }
}

// MARK: - Peripheral manager delegate (beacon / GATT host)

extension Mouth: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
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
            return
        }
        refreshAdvertising()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveRead request: CBATTRequest) {
        request.value = gattPayload
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                if request.characteristic.uuid == Mouth.charUUID {
                    gattPayload = value
                }
                receive(transport: "ble-gatt", peer: "central", data: value)
            }
            peripheral.respond(to: request, withResult: .success)
        }
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
        pendingWrite = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        pendingWrite = nil
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
        pendingWrite = nil
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            line("nightjar: write failed: \(error.localizedDescription)")
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
                    reply: String, framing: String) {
        stopServe()
        serveReply = Data(reply.utf8)
        serveFraming = framing
        serveError = nil
        var started: [String] = []
        do {
            if let port = tcpPort {
                listeners.append(try makeListener(port: port, params: .tcp) { [weak self] conn in
                    self?.handleStreamConnection(conn, transport: "tcp", http: false)
                })
                started.append("tcp://0.0.0.0:\(port)")
            }
            if let port = udpPort {
                listeners.append(try makeListener(port: port, params: .udp) { [weak self] conn in
                    self?.handleDatagramConnection(conn)
                })
                started.append("udp://0.0.0.0:\(port)")
            }
            if let port = httpPort {
                listeners.append(try makeListener(port: port, params: .tcp) { [weak self] conn in
                    self?.handleStreamConnection(conn, transport: "http", http: true)
                })
                started.append("http://0.0.0.0:\(port)/")
            }
        } catch {
            stopServe()
            DispatchQueue.main.async {
                self.serveError = "nightjar: \(error.localizedDescription)"
            }
            return
        }
        if started.isEmpty {
            DispatchQueue.main.async {
                self.serveError = "nightjar: no listener selected"
            }
            return
        }
        DispatchQueue.main.async { self.serveRunning = true }
        line("serve: \(started.joined(separator: ", ")) — foreground only")
    }

    func stopServe() {
        for listener in listeners { listener.cancel() }
        listeners = []
        DispatchQueue.main.async { self.serveRunning = false }
    }

    private func makeListener(port: Int, params: NWParameters,
                              onConnection: @escaping (NWConnection) -> Void) throws -> NWListener {
        guard let endpoint = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            throw MouthError.message("bad port \(port)")
        }
        let listener = try NWListener(using: params, on: endpoint)
        listener.newConnectionHandler = onConnection
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                DispatchQueue.main.async {
                    self?.serveError = "nightjar: listener failed: \(error.localizedDescription)"
                    self?.serveRunning = false
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
                                        http: Bool) {
        connection.start(queue: queue)
        var buffer = Data()
        var sunk = false
        var generation = 0
        let peer = "\(connection.endpoint)"
        func sinkAndAnswer() {
            guard !sunk, !buffer.isEmpty else {
                connection.cancel()
                return
            }
            sunk = true
            if http {
                let body = Self.httpBody(buffer)
                receive(transport: "http", peer: peer, data: body)
                let payload = serveReply.isEmpty ? Data("ok\n".utf8) : serveReply
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n"
                    + "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + payload,
                                completion: .contentProcessed { _ in connection.cancel() })
            } else {
                let data = PayloadKit.unframe(buffer, framing: serveFraming)
                receive(transport: transport, peer: peer, data: data)
                if !serveReply.isEmpty {
                    connection.send(content: serveReply,
                                    completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    connection.cancel()
                }
            }
        }
        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer += data
                    generation += 1
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
                    let seen = generation
                    self.queue.asyncAfter(deadline: .now() + 1.2) {
                        if generation == seen, !buffer.isEmpty { sinkAndAnswer() }
                    }
                    pump()
                }
            }
        }
        pump()
    }

    private func handleDatagramConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        func pump() {
            connection.receiveMessage { [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if let data = data, !data.isEmpty {
                    let unframed = PayloadKit.unframe(data, framing: self.serveFraming)
                    self.receive(transport: "udp", peer: "\(connection.endpoint)", data: unframed)
                    if !self.serveReply.isEmpty {
                        connection.send(content: self.serveReply,
                                        completion: .contentProcessed { _ in })
                    }
                }
                if !isComplete && error == nil {
                    pump()
                }
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

    private static func httpComplete(_ buffer: Data) -> Bool {
        guard let end = httpHeaderEnd(buffer) else { return false }
        return buffer.count >= end + httpContentLength(buffer)
    }

    private static func httpBody(_ buffer: Data) -> Data {
        guard let end = httpHeaderEnd(buffer) else { return buffer }
        let length = httpContentLength(buffer)
        guard buffer.count > end else { return Data() }
        return buffer.subdata(in: end..<min(buffer.count, end + length))
    }
}
