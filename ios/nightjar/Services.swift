import Foundation

/// Service UUIDs and service data — a port of `nightjar/services.py`.
enum Services {
    static let serviceNames: [UInt16: String] = [
        0x1800: "Generic Access",
        0x1801: "Generic Attribute",
        0x1802: "Immediate Alert",
        0x1803: "Link Loss",
        0x1804: "Tx Power",
        0x1805: "Current Time",
        0x1808: "Glucose",
        0x1809: "Health Thermometer",
        0x180A: "Device Information",
        0x180D: "Heart Rate",
        0x180F: "Battery",
        0x1810: "Blood Pressure",
        0x1811: "Alert Notification",
        0x1812: "Human Interface Device",
        0x1814: "Running Speed and Cadence",
        0x1816: "Cycling Speed and Cadence",
        0x1818: "Cycling Power",
        0x1819: "Location and Navigation",
        0x181A: "Environmental Sensing",
        0x181B: "Body Composition",
        0x181C: "User Data",
        0x181D: "Weight Scale",
        0x181F: "Continuous Glucose Monitoring",
        0x1822: "Pulse Oximeter",
        0x1826: "Fitness Machine",
        0x1827: "Mesh Provisioning",
        0x1828: "Mesh Proxy",
        0x184E: "Audio Stream Control (LE Audio)",
        0x1850: "Published Audio Capabilities (LE Audio)",
        0x1852: "Broadcast Audio Announcement (LE Audio)",
        0x1853: "Common Audio (LE Audio)",
        0x1854: "Hearing Access (LE Audio)",
        0xFD3D: "SwitchBot",
        0xFD43: "Apple",
        0xFD44: "Apple (Find My accessory)",
        0xFD5A: "Samsung SmartThings Find",
        0xFD6F: "Exposure Notification",
        0xFE03: "Amazon",
        0xFE07: "Sonos",
        0xFE0F: "Signify (Philips Hue)",
        0xFE2C: "Google Fast Pair",
        0xFE59: "Nordic DFU",
        0xFE61: "Logitech",
        0xFE95: "Xiaomi",
        0xFE9F: "Google",
        0xFEAA: "Eddystone",
        0xFEBE: "Bose",
        0xFECA: "Apple", 0xFECB: "Apple", 0xFECC: "Apple", 0xFECD: "Apple",
        0xFECE: "Apple", 0xFECF: "Apple", 0xFED0: "Apple", 0xFED1: "Apple",
        0xFED2: "Apple", 0xFED3: "Apple", 0xFED4: "Apple",
        0xFEE0: "Huami",
        0xFEE7: "Tencent (WeChat)",
        0xFEEC: "Tile",
        0xFEED: "Tile",
        0xFEF3: "Google",
        0xFEF4: "Google",
    ]

    static let fastPair: UInt16 = 0xFE2C
    static let eddystone: UInt16 = 0xFEAA
    static let exposureNotification: UInt16 = 0xFD6F
    static let smartThingsFind: UInt16 = 0xFD5A
    static let tile: [UInt16] = [0xFEED, 0xFEEC]

    /// Full lowercase form of a short or long UUID string.
    static func normalize(_ uuid: String) -> String {
        var text = uuid.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("0x") { text.removeFirst(2) }
        let hex = Set("0123456789abcdef")
        if (text.count == 4 || text.count == 8) && text.allSatisfy({ hex.contains($0) }) {
            let padded = String(repeating: "0", count: 8 - text.count) + text
            return padded + sigBaseSuffix
        }
        return text
    }

    /// The 16-bit value of a SIG-base UUID, else nil.
    static func short(_ uuid: String) -> UInt16? {
        let text = normalize(uuid)
        guard text.count == 36, text.hasSuffix(sigBaseSuffix), text.hasPrefix("0000") else {
            return nil
        }
        let start = text.index(text.startIndex, offsetBy: 4)
        let end = text.index(text.startIndex, offsetBy: 8)
        return UInt16(text[start..<end], radix: 16)
    }

    static func name(_ uuid: String) -> String? {
        guard let value = short(uuid) else { return nil }
        return serviceNames[value]
    }

    // MARK: - Eddystone (and Google's Find My Device network)

    static let urlSchemes: [UInt8: String] = [
        0x00: "http://www.", 0x01: "https://www.", 0x02: "http://", 0x03: "https://",
    ]
    static let urlExpansions: [UInt8: String] = [
        0x00: ".com/", 0x01: ".org/", 0x02: ".edu/", 0x03: ".net/",
        0x04: ".info/", 0x05: ".biz/", 0x06: ".gov/",
        0x07: ".com", 0x08: ".org", 0x09: ".edu", 0x0A: ".net",
        0x0B: ".info", 0x0C: ".biz", 0x0D: ".gov",
    ]
    static let frameNames: [UInt8: String] = [
        0x00: "UID", 0x10: "URL", 0x20: "TLM", 0x30: "EID",
        0x40: "Find My Device network (20-byte EID)",
        0x41: "Find My Device network (32-byte EID)",
    ]

    struct EddystoneFrame {
        let frameType: UInt8
        var txPower: Int?
        var namespace: String?
        var instance: String?
        var url: String?
        var batteryMv: Int?
        var temperatureC: Double?
        var advCount: Int?
        var uptimeS: Double?
        var eid: String?

        var frameName: String {
            return Services.frameNames[frameType] ?? String(format: "frame 0x%02X", frameType)
        }

        var isFMDN: Bool { return frameType == 0x40 || frameType == 0x41 }

        var describe: String {
            if isFMDN { return "Find My Device network beacon (Google)" }
            switch frameType {
            case 0x00:
                return "Eddystone-UID \(namespace ?? "")/\(instance ?? "")"
            case 0x10:
                return "Eddystone-URL \(url ?? "")"
            case 0x20:
                var parts: [String] = []
                if let mv = batteryMv, mv > 0 { parts.append("battery \(mv) mV") }
                if let temp = temperatureC { parts.append(String(format: "%.1f °C", temp)) }
                if let up = uptimeS { parts.append(String(format: "up %.1f h", up / 3600)) }
                return "Eddystone-TLM" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))
            case 0x30:
                return "Eddystone-EID \(eid ?? "")"
            default:
                return "Eddystone \(frameName)"
            }
        }
    }

    static func decodeEddystone(_ payload: [UInt8]) -> EddystoneFrame? {
        guard let frameType = payload.first else { return nil }
        var frame = EddystoneFrame(frameType: frameType)
        switch frameType {
        case 0x00 where payload.count >= 18:
            frame.txPower = Int(Int8(bitPattern: payload[1]))
            frame.namespace = JSONL.hex(Array(payload[2..<12]))
            frame.instance = JSONL.hex(Array(payload[12..<18]))
        case 0x10 where payload.count >= 3:
            frame.txPower = Int(Int8(bitPattern: payload[1]))
            var url = urlSchemes[payload[2]] ?? ""
            for byte in payload[3...] {
                if let expansion = urlExpansions[byte] {
                    url += expansion
                } else if byte > 0x20 && byte < 0x7F {
                    url += String(UnicodeScalar(byte))
                }
            }
            frame.url = url
        case 0x20 where payload.count >= 14 && payload[1] == 0x00:
            let battery = Int(payload[2]) << 8 | Int(payload[3])
            frame.batteryMv = battery == 0 ? nil : battery
            let rawTemp = Int16(bitPattern: UInt16(payload[4]) << 8 | UInt16(payload[5]))
            frame.temperatureC = (payload[4] == 0x80 && payload[5] == 0x00) ? nil
                                                                            : Double(rawTemp) / 256.0
            frame.advCount = Int(payload[6]) << 24 | Int(payload[7]) << 16
                | Int(payload[8]) << 8 | Int(payload[9])
            let ticks = Int(payload[10]) << 24 | Int(payload[11]) << 16
                | Int(payload[12]) << 8 | Int(payload[13])
            frame.uptimeS = Double(ticks) / 10.0
        case 0x30 where payload.count >= 10:
            frame.txPower = Int(Int8(bitPattern: payload[1]))
            frame.eid = JSONL.hex(Array(payload[2..<10]))
        case 0x40, 0x41:
            frame.eid = JSONL.hex(Array(payload[1...]))
        default:
            break
        }
        return frame
    }

    // MARK: - Fast Pair

    struct FastPairState {
        let modelID: Int?
        let discoverable: Bool

        var describe: String {
            if discoverable, let model = modelID {
                return String(format: "Fast Pair, discoverable (model 0x%06X)", model)
            }
            return "Fast Pair device (paired, not discoverable)"
        }
    }

    static func decodeFastPair(_ payload: [UInt8]) -> FastPairState? {
        guard !payload.isEmpty else { return nil }
        if payload.count == 3 {
            let model = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
            return FastPairState(modelID: model, discoverable: true)
        }
        return FastPairState(modelID: nil, discoverable: false)
    }

    // MARK: - Putting it together

    struct Identification {
        let kind: String
        let details: [String]
        let trackerShaped: Bool
        let rotatingPhone: Bool
        let specificity: Int
    }

    static func identify(serviceUUIDs: [String], serviceData: [String: [UInt8]]) -> Identification? {
        var shorts: [UInt16: String] = [:]
        for uuid in serviceUUIDs + Array(serviceData.keys) {
            if let value = short(uuid) { shorts[value] = normalize(uuid) }
        }
        var data: [UInt16: [UInt8]] = [:]
        for (uuid, payload) in serviceData {
            if let value = short(uuid) { data[value] = payload }
        }

        if shorts[eddystone] != nil {
            if let frame = decodeEddystone(data[eddystone] ?? []) {
                if frame.isFMDN {
                    return Identification(kind: "Find My Device network tag (Google)",
                                          details: [frame.describe], trackerShaped: true,
                                          rotatingPhone: false, specificity: 3)
                }
                return Identification(kind: "Eddystone beacon (\(frame.frameName))",
                                      details: [frame.describe], trackerShaped: false,
                                      rotatingPhone: false, specificity: 3)
            }
            return Identification(kind: "Eddystone beacon", details: [], trackerShaped: false,
                                  rotatingPhone: false, specificity: 2)
        }
        if shorts[fastPair] != nil {
            let state = decodeFastPair(data[fastPair] ?? [])
            return Identification(kind: "Fast Pair device (Google)",
                                  details: state.map { [$0.describe] } ?? [],
                                  trackerShaped: false, rotatingPhone: false, specificity: 2)
        }
        if shorts[exposureNotification] != nil {
            return Identification(kind: "Phone (Exposure Notification)",
                                  details: ["contact-tracing beacon; rotates every ~15 min"],
                                  trackerShaped: false, rotatingPhone: true, specificity: 2)
        }
        if tile.contains(where: { shorts[$0] != nil }) {
            return Identification(kind: "Tile tracker", details: [], trackerShaped: true,
                                  rotatingPhone: false, specificity: 3)
        }
        if shorts[smartThingsFind] != nil {
            return Identification(kind: "SmartThings Find device (Samsung tag or Galaxy)",
                                  details: [], trackerShaped: true, rotatingPhone: false,
                                  specificity: 2)
        }
        let named = Set(shorts.keys.compactMap { serviceNames[$0] }).sorted()
        if !named.isEmpty {
            return Identification(kind: "Device advertising " + named.joined(separator: ", "),
                                  details: [], trackerShaped: false, rotatingPhone: false,
                                  specificity: 1)
        }
        return nil
    }
}
