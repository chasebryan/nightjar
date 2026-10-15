import Foundation

/// Extra broadcast formats for the identification chain — the third-party
/// beacons and sensors the older chain could only call "unknown":
/// Microsoft Swift Pair (strict form), AltBeacon, RuuviTag, Govee,
/// Xiaomi MiBeacon and BTHome v2, plus recognition for Tile trackers,
/// Galaxy SmartTag and SwitchBot.
///
/// Detection is deliberately strict — exact company IDs, service UUIDs,
/// magic bytes and length gates — because a wrong label is worse than
/// "unknown". Everything returns the shared `Services.Identification`
/// fragment, so results surface through `Classification.classify`
/// exactly like the existing decoders, with no UI changes.
///
/// Two formats from the original wish-list intentionally live elsewhere:
/// - iBeacon (Apple 0x004C, type 0x02) is already decoded by Continuity
///   (kind "iBeacon", specificity 3), which the chain consults first.
/// - Exposure Notification (0xFD6F) is already identified by Services as
///   "Phone (Exposure Notification)" — a phone, not a beacon — so it is
///   not relabelled here.
///
/// Sample advertisements for every decoder live in
/// `nightjarTests/MoreDecodersTests.swift`.
enum MoreDecoders {
    static let microsoftCompany: UInt16 = 0x0006
    static let ruuviCompany: UInt16 = 0x0499
    static let goveeCompany: UInt16 = 0xEC88

    static let xiaomiService: UInt16 = 0xFE95
    static let btHomeService: UInt16 = 0xFCD2
    static let tileServices: [UInt16] = [0xFEED, 0xFEEC]
    static let smartTagService: UInt16 = 0xFD5A
    static let switchBotService: UInt16 = 0xFD3D

    /// The chain hook: tried after Continuity (Apple always wins its own
    /// company ID) and before Services' specificity-2 answers, so these
    /// decoders can outrank generic service guesses while still losing
    /// to nothing they should not touch — every gate below is strict.
    static func identify(_ sighting: Sighting) -> Services.Identification? {
        if let payload = sighting.manufacturerData[microsoftCompany],
           let hit = decodeSwiftPair(payload) {
            return hit
        }
        // AltBeacon's magic is in the payload, not the company ID: the
        // block sits under the beacon maker's own company ID, so every
        // manufacturer payload gets a look.
        for payload in sighting.manufacturerData.values {
            if let hit = decodeAltBeacon(payload) { return hit }
        }
        if let payload = sighting.manufacturerData[ruuviCompany],
           let hit = decodeRuuvi(payload) {
            return hit
        }
        if let payload = sighting.manufacturerData[goveeCompany],
           let hit = decodeGovee(payload) {
            return hit
        }
        if let payload = serviceData(sighting, xiaomiService),
           let hit = decodeMiBeacon(payload) {
            return hit
        }
        if let payload = serviceData(sighting, btHomeService),
           let hit = decodeBTHome(payload) {
            return hit
        }
        for uuid in tileServices where advertises(sighting, uuid) {
            return Services.Identification(kind: "Tile tracker", details: [],
                                           trackerShaped: true, rotatingPhone: false,
                                           specificity: 3)
        }
        if advertises(sighting, smartTagService) {
            return Services.Identification(kind: "SmartThings Find device (Samsung tag or Galaxy)", details: [],
                                           trackerShaped: true, rotatingPhone: false,
                                           specificity: 2)
        }
        // SwitchBot needs its service DATA: a bare FD3D UUID in the scan
        // response is left for Services' family-level name.
        if let payload = serviceData(sighting, switchBotService), !payload.isEmpty {
            return Services.Identification(kind: "SwitchBot", details: [],
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 2)
        }
        return nil
    }

    // MARK: - Lookup helpers

    private static func serviceData(_ sighting: Sighting, _ id: UInt16) -> [UInt8]? {
        for (uuid, payload) in sighting.serviceData where Services.short(uuid) == id {
            return payload
        }
        return nil
    }

    private static func advertises(_ sighting: Sighting, _ id: UInt16) -> Bool {
        if serviceData(sighting, id) != nil { return true }
        return sighting.serviceUUIDs.contains { Services.short($0) == id }
    }

    private static func be16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 8 | Int(b[i + 1])
    }

    private static func beS16(_ b: [UInt8], _ i: Int) -> Int {
        Int(Int16(bitPattern: UInt16(be16(b, i))))
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8
    }

    private static func leS16(_ b: [UInt8], _ i: Int) -> Int {
        Int(Int16(bitPattern: UInt16(le16(b, i))))
    }

    private static func le24(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16
    }

    // MARK: - Microsoft Swift Pair

    /// Swift Pair's documented beacon: company 0x0006, payload opening
    /// 0x03 0x00 0x80 (scenario type, pairing mode, the 0x80 reserved
    /// byte), then the announced name. The strict prefix is the whole
    /// claim — looser 0x0006 payloads (CDP beacons, the 0x03 0x06 …
    /// variant) stay with Vendors.
    static func decodeSwiftPair(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count >= 3,
              payload[0] == 0x03, payload[1] == 0x00, payload[2] == 0x80
        else { return nil }
        var details = ["in pairing mode (Swift Pair)"]
        let nameBytes = Array(payload.dropFirst(3))
        let name = String(bytes: nameBytes, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
        if let name = name, !name.isEmpty {
            details.append("announces itself as '\(name)'")
        }
        return Services.Identification(kind: "Microsoft Swift Pair", details: details,
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 2)
    }

    // MARK: - AltBeacon

    /// AltBeacon (the AltBeacon spec): beacon code 0xBEAC big-endian
    /// opens the payload, followed by the 20-byte beacon ID, a signed
    /// reference RSSI and one reserved byte — 24 payload bytes exactly
    /// (26 counting the company ID the sighting already split off).
    /// Note 0xBEAC is the beacon CODE, not a company ID: the block rides
    /// under the beacon manufacturer's own assigned company ID.
    static func decodeAltBeacon(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count == 24, payload[0] == 0xBE, payload[1] == 0xAC
        else { return nil }
        let idHead = JSONL.hex(Array(payload[2..<10]))
        let rssi = Int(Int8(bitPattern: payload[22]))
        let detail = "beacon id \(idHead)..., \(rssi) dBm @ 1 m"
        return Services.Identification(kind: "AltBeacon", details: [detail],
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 3)
    }

    // MARK: - RuuviTag

    /// Ruuvi manufacturer data (company 0x0499) opens with a format
    /// byte: 0x05 is RAWv2, 0x03 is RAWv1. Anything else is left for
    /// Vendors' family-level "Ruuvi device".
    static func decodeRuuvi(_ payload: [UInt8]) -> Services.Identification? {
        guard let format = payload.first else { return nil }
        if format == 0x05 { return decodeRuuviV5(payload) }
        if format == 0x03 { return decodeRuuviV3(payload) }
        return nil
    }

    /// Format 5 / RAWv2: temperature s16 BE x0.005 C, humidity u16 BE
    /// x0.0025 %, pressure u16 BE (+50000 Pa), acceleration s16 BE mG
    /// x3, then a packed power field — battery (bits 15...5, +1600 mV)
    /// and TX power. 0x8000 / 0xFFFF mark "not available" per field.
    static func decodeRuuviV5(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count >= 24, payload[0] == 0x05 else { return nil }
        var parts: [String] = []
        let tempRaw = beS16(payload, 1)
        if tempRaw != -32768 {
            parts.append(String(format: "%.2f °C", Double(tempRaw) * 0.005))
        }
        let humRaw = be16(payload, 3)
        if humRaw != 0xFFFF {
            parts.append(String(format: "%.1f%% RH", Double(humRaw) * 0.0025))
        }
        let presRaw = be16(payload, 5)
        if presRaw != 0xFFFF {
            parts.append(String(format: "%.1f hPa", Double(presRaw + 50000) / 100.0))
        }
        let accX = beS16(payload, 7)
        let accY = beS16(payload, 9)
        let accZ = beS16(payload, 11)
        if accX != -32768 || accY != -32768 || accZ != -32768 {
            parts.append("accel \(accX)/\(accY)/\(accZ) mG")
        }
        let power = be16(payload, 13)
        if (power >> 5) != 2047 {
            parts.append("battery \((power >> 5) + 1600) mV")
        }
        guard !parts.isEmpty else { return nil }
        return Services.Identification(kind: "RuuviTag sensor",
                                       details: [parts.joined(separator: ", ")],
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 3)
    }

    /// Format 3 / RAWv1: humidity u8 x0.5 %, temperature as a
    /// sign-magnitude byte plus a hundredths byte, pressure u16 BE
    /// (+50000 Pa), acceleration s16 BE mG x3, battery u16 BE mV.
    /// Humidity raw values above 200 (100 %) are a fault indication
    /// and are dropped.
    static func decodeRuuviV3(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count >= 14, payload[0] == 0x03 else { return nil }
        var parts: [String] = []
        var temp = Double(payload[2] & 0x7F) + Double(payload[3]) / 100.0
        if (payload[2] & 0x80) != 0 { temp = -temp }
        parts.append(String(format: "%.2f °C", temp))
        let humRaw = Int(payload[1])
        if humRaw <= 200 {
            parts.append(String(format: "%.1f%% RH", Double(humRaw) * 0.5))
        }
        let presRaw = be16(payload, 4)
        parts.append(String(format: "%.1f hPa", Double(presRaw + 50000) / 100.0))
        let accel = "accel \(beS16(payload, 6))/\(beS16(payload, 8))/\(beS16(payload, 10)) mG"
        parts.append(accel)
        parts.append("battery \(be16(payload, 12)) mV")
        return Services.Identification(kind: "RuuviTag sensor",
                                       details: [parts.joined(separator: ", ")],
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 3)
    }

    // MARK: - Govee thermometer

    /// Govee H5072/H5075-style frame under company 0xEC88 (an empirical
    /// ID, not SIG-assigned): exactly six payload bytes — a 0x00 flag,
    /// a 24-bit big-endian packed reading, a battery byte and a 0x00
    /// trailer. The packed value's top bit is the temperature sign;
    /// the rest packs temperature and humidity in tenths:
    /// temp = (value / 1000) / 10 C, humidity = (value % 1000) / 10 %.
    /// The battery byte's top bit is a sensor-error flag; its low
    /// seven bits are the percentage. The length/flag/trailer gate
    /// plus the range check keep lookalike frames out.
    static func decodeGovee(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count == 6, payload[0] == 0x00, payload[5] == 0x00
        else { return nil }
        let packed = Int(payload[1]) << 16 | Int(payload[2]) << 8 | Int(payload[3])
        let negative = (packed & 0x800000) != 0
        let value = packed & 0x7FFFFF
        var temp = Double(value / 1000) / 10.0
        if negative { temp = -temp }
        let hum = Double(value % 1000) / 10.0
        let batteryByte = payload[4]
        let battery = Int(batteryByte & 0x7F)
        let sensorError = (batteryByte & 0x80) != 0
        guard temp >= -40, temp <= 80, hum <= 100, battery <= 100 else { return nil }
        var parts: [String] = []
        if sensorError {
            parts.append("sensor error")
        } else {
            parts.append(String(format: "%.1f °C", temp))
            parts.append(String(format: "%.1f%% RH", hum))
        }
        parts.append("battery \(battery)%")
        return Services.Identification(kind: "Govee thermometer",
                                       details: [parts.joined(separator: ", ")],
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 3)
    }

    // MARK: - Xiaomi MiBeacon

    /// MiBeacon product IDs with names solid enough to print. Anything
    /// else falls back to "Xiaomi MiBeacon device 0xXXXX" — a made-up
    /// product name would be worse than the bare ID.
    static let miProducts: [UInt16: String] = [
        0x01AA: "Mijia temperature/humidity sensor",
        0x055B: "Mijia temperature/humidity sensor 2",
        0x05BC: "Mijia temperature/humidity clock (MJWSD05MMC)",
        0x0098: "HHCC flower care plant sensor",
        0x0387: "Mijia e-ink temperature/humidity sensor (MHO-C401)",
        0x03DD: "Mijia alarm clock (MHO-C303)",
        0x0A8D: "Mijia motion sensor 2 (RTCGQ02LM)",
        0x0113: "Mijia door/window sensor 2 (MCCGQ02HL)",
        0x040A: "Yeelight remote control (YLYK01YL)",
        0x04E9: "Yeelight smart button (YLAI003)",
        0x07F5: "Linptech switch, 1-button (K9B)",
        0x08B4: "Linptech switch, 2-button (K9B)",
    ]

    /// MiBeacon (service data 0xFE95): frame control u16 LE (version
    /// in bits 12...15, object-include bit 6, capability-include bit 5,
    /// MAC-include bit 4, encrypted bit 3), product ID u16 LE, frame
    /// counter u8, then the optional MAC (6 bytes) and capability byte
    /// (plus a 2-byte I/O capability when its bit 5 is set), then
    /// objects. Encrypted frames are labelled, never decrypted.
    static func decodeMiBeacon(_ payload: [UInt8]) -> Services.Identification? {
        guard payload.count >= 5 else { return nil }
        let frameControl = le16(payload, 0)
        let encrypted = (frameControl & 0x0008) != 0
        let macIncluded = (frameControl & 0x0010) != 0
        let capabilityIncluded = (frameControl & 0x0020) != 0
        let objectIncluded = (frameControl & 0x0040) != 0
        let product = UInt16(le16(payload, 2))
        var index = 5
        var details: [String] = []
        if macIncluded {
            guard payload.count >= index + 6 else { return nil }
            let macBytes = Array(payload[index..<(index + 6)])
            let mac = macBytes.map { String(format: "%02x", Int($0)) }
                .joined(separator: ":")
            details.append("device MAC \(mac)")
            index += 6
        }
        if capabilityIncluded {
            guard payload.count >= index + 1 else { return nil }
            let capability = payload[index]
            index += 1
            if (capability & 0x20) != 0 { index += 2 }
            guard payload.count >= index else { return nil }
        }
        if encrypted {
            details.append("encrypted, readings not decoded (bindkey required)")
        } else if objectIncluded, index <= payload.count {
            let readings = miReadings(Array(payload[index...]))
            if !readings.isEmpty {
                details.append(readings.joined(separator: ", "))
            }
        }
        if let name = miProducts[product] {
            return Services.Identification(kind: "Xiaomi " + name, details: details,
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 3)
        }
        let fallback = String(format: "Xiaomi MiBeacon device 0x%04X", Int(product))
        return Services.Identification(kind: fallback, details: details,
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 2)
    }

    /// MiBeacon objects: ID u16 LE, length u8, value. Only the common
    /// environmental objects are decoded, and only at their exact
    /// documented lengths; unknown objects are skipped by length.
    static func miReadings(_ bytes: [UInt8]) -> [String] {
        var parts: [String] = []
        var index = 0
        while index + 3 <= bytes.count {
            let objectID = UInt16(le16(bytes, index))
            let length = Int(bytes[index + 2])
            let valueStart = index + 3
            guard valueStart + length <= bytes.count else { break }
            let v = Array(bytes[valueStart..<(valueStart + length)])
            switch objectID {
            case 0x1004 where length == 2:
                let raw = leS16(v, 0)
                parts.append(String(format: "%.1f °C", Double(raw) / 10.0))
            case 0x1006 where length == 2:
                let raw = le16(v, 0)
                parts.append(String(format: "%.1f%% RH", Double(raw) / 10.0))
            case 0x100D where length == 4:
                let tempRaw = leS16(v, 0)
                let humRaw = le16(v, 2)
                parts.append(String(format: "%.1f °C", Double(tempRaw) / 10.0))
                parts.append(String(format: "%.1f%% RH", Double(humRaw) / 10.0))
            case 0x1007 where length == 3:
                parts.append("\(le24(v, 0)) lx")
            case 0x100A where length == 1:
                parts.append("battery \(Int(v[0]))%")
            default:
                break
            }
            index = valueStart + length
        }
        return parts
    }

    // MARK: - BTHome v2

    /// BTHome v2 object lengths (service data 0xFCD2). Objects not in
    /// this table end the walk — their length is unknowable — but the
    /// readings already collected still count.
    static let btHomeObjectLengths: [UInt8: Int] = [
        0x00: 1, 0x01: 1, 0x02: 2, 0x03: 2, 0x04: 3, 0x05: 3,
        0x06: 2, 0x07: 2, 0x08: 2, 0x09: 1, 0x0A: 3, 0x0B: 3,
        0x0C: 2, 0x0D: 2, 0x0E: 2, 0x0F: 1, 0x10: 1, 0x11: 1,
        0x12: 2, 0x13: 2,
    ]

    /// BTHome v2 plaintext framing: a device-info byte (version 2 in
    /// bits 5...7, encryption bit 0, MAC-included bit 1), an optional
    /// 6-byte MAC, then self-describing objects. Encrypted frames are
    /// labelled, never decrypted.
    static func decodeBTHome(_ payload: [UInt8]) -> Services.Identification? {
        guard let info = payload.first, (info & 0xE0) == 0x40 else { return nil }
        let encrypted = (info & 0x01) != 0
        var index = 1
        if (info & 0x02) != 0 { index += 6 }
        guard payload.count >= index else { return nil }
        if encrypted {
            let note = "encrypted, readings not decoded (bindkey required)"
            return Services.Identification(kind: "BTHome sensor", details: [note],
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 2)
        }
        var parts: [String] = []
        while index < payload.count {
            let objectID = payload[index]
            guard let length = btHomeObjectLengths[objectID],
                  index + 1 + length <= payload.count else { break }
            let v = Array(payload[(index + 1)..<(index + 1 + length)])
            switch objectID {
            case 0x01:
                parts.append("battery \(Int(v[0]))%")
            case 0x02:
                let raw = leS16(v, 0)
                parts.append(String(format: "%.2f °C", Double(raw) * 0.01))
            case 0x03:
                let raw = le16(v, 0)
                parts.append(String(format: "%.2f%% RH", Double(raw) * 0.01))
            case 0x04:
                let raw = le24(v, 0)
                parts.append(String(format: "%.1f hPa", Double(raw) * 0.01))
            case 0x05:
                let raw = le24(v, 0)
                parts.append(luxText(Double(raw) * 0.01))
            case 0x0A:
                let raw = le24(v, 0)
                parts.append(String(format: "%.3f kWh", Double(raw) * 0.001))
            case 0x0B:
                let raw = le24(v, 0)
                parts.append(String(format: "%.2f W", Double(raw) * 0.01))
            case 0x0C:
                let raw = le16(v, 0)
                parts.append(String(format: "%.3f V", Double(raw) * 0.001))
            case 0x0D:
                parts.append("pm2.5 \(le16(v, 0)) µg/m³")
            case 0x0E:
                parts.append("pm10 \(le16(v, 0)) µg/m³")
            case 0x12:
                parts.append("CO2 \(le16(v, 0)) ppm")
            case 0x13:
                parts.append("VOC \(le16(v, 0)) µg/m³")
            default:
                break  // known length, not displayed (packet id, weight, switches...)
            }
            index += 1 + length
        }
        if parts.isEmpty {
            return Services.Identification(kind: "BTHome sensor", details: [],
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 2)
        }
        return Services.Identification(kind: "BTHome sensor",
                                       details: [parts.joined(separator: ", ")],
                                       trackerShaped: false, rotatingPhone: false,
                                       specificity: 3)
    }

    private static func luxText(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f lx", value) }
        return String(format: "%.2f lx", value)
    }
}
