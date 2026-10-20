import Foundation

/// Extra broadcast formats for the identification chain — the third-party
/// beacons and sensors the older chain could only call "unknown":
/// Microsoft Swift Pair (strict form), AltBeacon, RuuviTag, Govee,
/// Xiaomi MiBeacon and BTHome v2, plus recognition for Tile trackers,
/// Galaxy SmartTag and SwitchBot. Batch 1 of the decoders arc
/// (2026-10-20) adds MikroTik's TG-BT5 tag — the one networking
/// vendor format published in full, test vectors included.
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
/// Round 2 (signature recognition for the nameless remainder):
/// - In `identify`: Huami services (0xFEE0/0xFEE1) and the ASHA hearing
///   aid service (0xFDF0), both verified against the SIG assigned
///   numbers and Google's published ASHA specification.
/// - In `lateIdentify` — a second hook the chain consults only after
///   Vendors and the Services decoders have passed, so it can never
///   shadow a real decode (a DJI drone's Remote ID answer included):
///   a company-ID floor for SIG-verified makers Vendors' table lacks,
///   plus member-service names in exactly the form Services' own
///   fallback produces.
/// - Deliberately NOT claimed, after verification: Google 0xFE2C is
///   shared by Fast Pair and Nearby Share with no published byte that
///   separates them, so Services' Fast Pair answer stands; Samsung
///   0x0075 and Sony 0x012D advertisement layouts are not publicly
///   documented well enough to gate on (their battery/state data is
///   connection-oriented), so the Vendors family labels stand; and
///   Fitbit has no SIG company identifier at all.
///
/// Sample advertisements for every decoder live in
/// `nightjarTests/MoreDecodersTests.swift`.
enum MoreDecoders {
    static let microsoftCompany: UInt16 = 0x0006
    static let ruuviCompany: UInt16 = 0x0499
    static let goveeCompany: UInt16 = 0xEC88
    static let mikrotikCompany: UInt16 = 0x094F

    static let xiaomiService: UInt16 = 0xFE95
    static let btHomeService: UInt16 = 0xFCD2
    static let huamiService: UInt16 = 0xFEE0
    static let huamiAltService: UInt16 = 0xFEE1
    static let ashaService: UInt16 = 0xFDF0
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
        if let payload = sighting
            .manufacturerData[mikrotikCompany],
           let hit = decodeMikrotikTag(payload) {
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
        // Huami's two member services (SIG assigned numbers): 0xFEE0 is
        // the Mi Band service, 0xFEE1 its companion. This sits after the
        // MiBeacon attempt above, so a band whose FE95 frame decodes
        // still gets its product name; the bare services earn the
        // family label instead of Services' "Device advertising Huami".
        if advertises(sighting, huamiService) || advertises(sighting, huamiAltService) {
            return Services.Identification(kind: "Mi Band / Amazfit", details: [],
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 2)
        }
        // ASHA — Google's Audio Streaming for Hearing Aids service
        // (0xFDF0, Google's published ASHA specification). Only hearing
        // aids advertise it.
        if advertises(sighting, ashaService) {
            return Services.Identification(kind: "Hearing aid (ASHA)",
                                           details: ["Audio Streaming for Hearing Aids (Google ASHA)"],
                                           trackerShaped: false, rotatingPhone: false,
                                           specificity: 2)
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

    // MARK: - MikroTik TG-BT5 tag

    /// MikroTik TG-BT5 Bluetooth tag, company
    /// 0x094F — MikroTik's own published format
    /// (help.mikrotik.com, Bluetooth tag docs),
    /// the one networking-gear layout in the
    /// decoders arc's survey published in full,
    /// test vectors included. Exactly 18 bytes
    /// after the company ID, all little-endian:
    /// version (1) · user-data byte (bit 0 =
    /// the readings block is AES-ECB encrypted
    /// under the tag's key) · salt · accel
    /// X/Y/Z (s16, 8.8 fixed point — motion
    /// noise for a listener's purposes, not
    /// reported) · temperature (s16, 8.8 fixed
    /// point, °C) · uptime (u32, seconds) ·
    /// trigger flags (reed, tilt, free-fall,
    /// impact X/Y/Z) · battery %.
    static func decodeMikrotikTag(
        _ payload: [UInt8])
        -> Services.Identification? {
        guard payload.count == 18,
              payload[0] == 1
        else { return nil }
        if payload[1] & 0x01 != 0 {
            return Services.Identification(
                kind: "MikroTik Bluetooth tag",
                details: ["a TG-BT5 tag — its "
                          + "readings travel "
                          + "encrypted under the "
                          + "tag's own key; "
                          + "identity only"],
                trackerShaped: false,
                rotatingPhone: false,
                specificity: 3)
        }
        var parts: [String] = []
        let temp = Double(leS16(payload, 10))
            / 256.0
        parts.append(String(
            format: "%.1f °C", temp))
        let uptime = le16(payload, 12)
            + le16(payload, 14) * 65536
        let days = uptime / 86400
        let hours = (uptime % 86400) / 3600
        let mins = (uptime % 3600) / 60
        if days > 0 {
            parts.append("uptime \(days)d "
                         + "\(hours)h")
        } else if hours > 0 {
            parts.append("uptime \(hours)h "
                         + "\(mins)m")
        } else {
            parts.append("uptime \(mins)m")
        }
        let flags = payload[16]
        var triggers: [String] = []
        if flags & 0x01 != 0 {
            triggers.append("reed switch")
        }
        if flags & 0x02 != 0 {
            triggers.append("tilt")
        }
        if flags & 0x04 != 0 {
            triggers.append("free-fall")
        }
        if flags & 0x08 != 0 {
            triggers.append("impact X")
        }
        if flags & 0x10 != 0 {
            triggers.append("impact Y")
        }
        if flags & 0x20 != 0 {
            triggers.append("impact Z")
        }
        if !triggers.isEmpty {
            parts.append("triggered: " + triggers
                .joined(separator: ", "))
        }
        if payload[17] <= 100 {
            parts.append("battery "
                         + "\(payload[17])%")
        }
        return Services.Identification(
            kind: "MikroTik Bluetooth tag",
            details: [parts.joined(
                separator: ", ")],
            trackerShaped: false,
            rotatingPhone: false,
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
        // The direct frame (H5074 / H5051 and
        // family, decoder expansion 2026-10-18):
        // plain little-endian values, verified
        // against captured packets — temp and
        // humidity as LE16 hundredths, battery
        // a plain percent. Gate on the two
        // documented lengths only.
        if (payload.count == 7 || payload.count == 9)
            && payload[0] == 0x00 {
            let tempRaw = Int16(bitPattern:
                UInt16(payload[1])
                | UInt16(payload[2]) << 8)
            let humRaw = UInt16(payload[3])
                | UInt16(payload[4]) << 8
            let temp = Double(tempRaw) / 100
            let hum = Double(humRaw) / 100
            let battery = Int(payload[5])
            if temp >= -40, temp <= 85,
               hum <= 100, battery <= 100 {
                return Services.Identification(
                    kind: "Govee thermometer",
                    details: [String(
                        format: "%.2f °C, %.2f%% RH, "
                            + "battery %d%%",
                        temp, hum, battery)],
                    trackerShaped: false,
                    rotatingPhone: false,
                    specificity: 3)
            }
            return nil
        }
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

    // MARK: - Round 2: the late recognition floor

    /// Company IDs verified against the Bluetooth SIG assigned-numbers
    /// list that Vendors' company table does not carry (Vendors is a
    /// protected upstream file, so the additions live here). SIG
    /// assignees, checked 2026-10: 0x03FF Withings, 0x0600 iRobot
    /// Corporation, 0x08AA SZ DJI Technology, 0x08C3 Chipolo,
    /// 0x067C Tile Inc., 0x01D1 August Home, 0x018E Google LLC,
    /// 0x0111 Steelseries, 0x065A Marshall Group, 0x068E Razer,
    /// 0x07C9 Skullcandy, 0x0CC2 Anker Innovations, 0x0CE9 JLab Audio,
    /// 0x0CCB Nothing Technology, 0x079A Oppo, 0x0837 vivo,
    /// 0x08A4 Realme, 0x09C6 Honor Device. Kinds follow Vendors' own
    /// fallback shape, "<maker> device".
    static let floorCompanies: [UInt16: String] = [
        0x03FF: "Withings", 0x0600: "iRobot", 0x08AA: "DJI",
        0x08C3: "Chipolo", 0x067C: "Tile", 0x01D1: "August Home",
        0x018E: "Google", 0x0111: "SteelSeries", 0x065A: "Marshall",
        0x068E: "Razer", 0x07C9: "Skullcandy", 0x0CC2: "Anker",
        0x0CE9: "JLab", 0x0CCB: "Nothing", 0x079A: "Oppo",
        0x0837: "vivo", 0x08A4: "Realme", 0x09C6: "Honor",
    ]

    /// Member-service names in the exact form Services' own table
    /// would produce ("Device advertising <name>"), for services the
    /// protected Services table lacks: August Home's 0xFE24 (SIG
    /// member list), the LE Audio services 0x184F and 0x1856 (SIG
    /// GATT list), and the Withings (0xFD77–0xFD7A) and Chipolo
    /// (0xFE33, 0xFE65) member ranges.
    static let lateServiceNames: [UInt16: String] = [
        0xFE24: "August Home",
        0x184F: "Broadcast Audio Scan (LE Audio)",
        0x1856: "Public Broadcast Announcement (LE Audio)",
        0xFD77: "Withings", 0xFD78: "Withings",
        0xFD79: "Withings", 0xFD7A: "Withings",
        0xFE33: "Chipolo", 0xFE65: "Chipolo",
    ]

    /// The chain's last resort before "unknown": consulted only after
    /// Continuity, `identify`, Services and Vendors have all passed,
    /// so nothing here can shadow a better answer. Maker first (the
    /// chain's Vendors-before-Services-names precedence), then any
    /// late service names, mirroring Services' sorted-and-joined form.
    static func lateIdentify(_ sighting: Sighting) -> Services.Identification? {
        for company in sighting.manufacturerData.keys.sorted() {
            if let maker = floorCompanies[company] {
                let tracker = company == 0x08C3 || company == 0x067C
                return Services.Identification(kind: maker + " device", details: [],
                                               trackerShaped: tracker,
                                               rotatingPhone: false, specificity: 1)
            }
        }
        var shorts = Set<UInt16>()
        for uuid in sighting.serviceUUIDs + Array(sighting.serviceData.keys) {
            if let value = Services.short(uuid) { shorts.insert(value) }
        }
        let named = Set(shorts.compactMap { lateServiceNames[$0] }).sorted()
        if !named.isEmpty {
            return Services.Identification(
                kind: "Device advertising " + named.joined(separator: ", "),
                details: [], trackerShaped: false, rotatingPhone: false,
                specificity: 1)
        }
        return nil
    }
}
