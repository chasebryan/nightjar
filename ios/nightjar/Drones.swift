import Foundation

/// Drones — reading the digital licence plate, a port of
/// `nightjar/remoteid.py` (which is verified against opendroneid-core-c).
///
/// Under the FAA's Remote ID rule (ASTM F3411 / Open Drone ID), nearly
/// every camera drone must broadcast what it is, where it is, and where
/// its operator is standing — and one of the mandated transports is a
/// plain BLE advertisement, the stream this app already listens to. The
/// broadcasts are public by design: any receiver is an intended audience.
///
/// A legacy advertisement carries service data for UUID 0xFFFA:
/// `[0x0D][counter][one 25-byte message]`. Each advertisement carries one
/// message; a drone cycles through its set over seconds.
enum Drones {
    static let remoteIDService: UInt16 = 0xFFFA
    static let appCode: UInt8 = 0x0D
    static let messageSize = 25
    /// System timestamps are seconds since 2019-01-01T00:00:00Z.
    static let epoch2019: TimeInterval = 1_546_300_800

    static let idTypes: [Int: String] = [
        0: "none", 1: "serial number", 2: "CAA registration",
        3: "UTM UUID", 4: "specific session ID",
    ]
    static let uaTypes: [Int: String] = [
        0: "none", 1: "aeroplane", 2: "helicopter/multirotor", 3: "gyroplane",
        4: "hybrid lift (VTOL)", 5: "ornithopter", 6: "glider", 7: "kite",
        8: "free balloon", 9: "captive balloon", 10: "airship",
        11: "free fall / parachute", 12: "rocket",
        13: "tethered powered aircraft", 14: "ground obstacle", 15: "other",
    ]
    static let operationalStatus: [Int: String] = [
        0: "undeclared", 1: "ground", 2: "airborne", 3: "emergency",
        4: "RID system failure",
    ]
    static let operatorLocationTypes: [Int: String] = [
        0: "takeoff point", 1: "live GPS", 2: "fixed",
    ]

    // MARK: - Messages

    struct BasicID {
        var idType: Int
        var uaType: Int
        var uasID: String
        var idTypeName: String { Drones.idTypes[idType] ?? "type \(idType)" }
        var uaTypeName: String { Drones.uaTypes[uaType] ?? "type \(uaType)" }
        /// Serial number or CAA registration: stable, device-identifying.
        var isSerial: Bool { (idType == 1 || idType == 2) && !uasID.isEmpty }
    }

    struct Location {
        var status: Int
        var direction: Double?
        var speedH: Double?
        var speedV: Double?
        var latitude: Double?
        var longitude: Double?
        var altitudeBaro: Double?
        var altitudeGeo: Double?
        var height: Double?
        var heightType: Int
        var timestampTenths: Int?
        var statusName: String { Drones.operationalStatus[status] ?? "status \(status)" }
        var airborne: Bool { status == 2 }
        var heightRef: String { heightType == 1 ? "AGL" : "above takeoff" }
    }

    struct SystemInfo {
        var operatorLatitude: Double?
        var operatorLongitude: Double?
        var operatorLocationType: Int
        var areaCount: Int
        var areaRadiusM: Int
        var areaCeiling: Double?
        var areaFloor: Double?
        var category: Int
        var uaClass: Int
        var operatorAltitude: Double?
        var timestampUnix: TimeInterval?
        var operatorLocationName: String {
            Drones.operatorLocationTypes[operatorLocationType] ?? "type \(operatorLocationType)"
        }
    }

    struct Message {
        var typeID: Int
        var protoVersion: Int
        var basicID: BasicID?
        var location: Location?
        var system: SystemInfo?
        var selfIDText: String?
        var operatorID: String?
    }

    // MARK: - Byte helpers (little-endian, like the Python)

    private static func u16(_ b: [UInt8], _ off: Int) -> Int {
        Int(b[off]) | Int(b[off + 1]) << 8
    }

    private static func i32(_ b: [UInt8], _ off: Int) -> Int32 {
        Int32(bitPattern: UInt32(b[off]) | UInt32(b[off + 1]) << 8
              | UInt32(b[off + 2]) << 16 | UInt32(b[off + 3]) << 24)
    }

    private static func u32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | UInt32(b[off + 1]) << 8
            | UInt32(b[off + 2]) << 16 | UInt32(b[off + 3]) << 24
    }

    /// uint16 → metres = raw × 0.5 − 1000; raw 0 is the invalid marker.
    private static func altitude(_ raw: Int) -> Double? {
        raw == 0 ? nil : Double(raw) * 0.5 - 1000.0
    }

    /// int32 × 1e-7 degrees; 0 means no fix.
    private static func latlon(_ raw: Int32) -> Double? {
        raw == 0 ? nil : Double(raw) / 1e7
    }

    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        var out: [UInt8] = []
        for byte in bytes {
            if byte == 0 { break }
            out.append(byte)
        }
        return String(bytes: out, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    // MARK: - Decoding

    static func decodeMessage(_ msg: [UInt8]) -> Message? {
        guard msg.count >= messageSize else { return nil }
        let typeID = Int(msg[0] >> 4)
        var message = Message(typeID: typeID, protoVersion: Int(msg[0] & 0x0F))
        switch typeID {
        case 0x0:  // Basic ID
            message.basicID = BasicID(idType: Int(msg[1] >> 4),
                                      uaType: Int(msg[1] & 0x0F),
                                      uasID: ascii(msg[2..<22]))
        case 0x1:  // Location
            let flags = msg[1]
            let eastWest = (flags >> 1) & 1
            let directionRaw = Int(msg[2])
            let speedMult = flags & 1
            let speedRaw = Double(msg[3])
            let tsRaw = u16(msg, 21)
            message.location = Location(
                status: Int((flags >> 4) & 0x0F),
                direction: directionRaw == 0xFF ? nil
                    : (eastWest == 1 ? Double(directionRaw) + 180.0 : Double(directionRaw)),
                speedH: speedMult == 0 ? speedRaw * 0.25 : speedRaw * 0.75 + 63.75,
                speedV: Double(Int8(bitPattern: msg[4])) * 0.5,
                latitude: latlon(i32(msg, 5)),
                longitude: latlon(i32(msg, 9)),
                altitudeBaro: altitude(u16(msg, 13)),
                altitudeGeo: altitude(u16(msg, 15)),
                height: altitude(u16(msg, 17)),
                heightType: Int((flags >> 2) & 1),
                timestampTenths: tsRaw == 0xFFFF ? nil : tsRaw)
        case 0x4:  // System
            let flags = msg[1]
            let tsRaw = u32(msg, 20)
            message.system = SystemInfo(
                operatorLatitude: latlon(i32(msg, 2)),
                operatorLongitude: latlon(i32(msg, 6)),
                operatorLocationType: Int(flags & 0x3),
                areaCount: u16(msg, 10),
                areaRadiusM: Int(msg[12]) * 10,
                areaCeiling: altitude(u16(msg, 13)),
                areaFloor: altitude(u16(msg, 15)),
                category: Int(msg[17] >> 4),
                uaClass: Int(msg[17] & 0x0F),
                operatorAltitude: altitude(u16(msg, 18)),
                timestampUnix: tsRaw == 0 ? nil : TimeInterval(tsRaw) + epoch2019)
        case 0x3:  // Self ID
            message.selfIDText = ascii(msg[2..<25])
        case 0x5:  // Operator ID
            message.operatorID = ascii(msg[2..<22])
        default:  // Authentication and anything else: recognized, not decoded.
            break
        }
        return message
    }

    /// Decode a 0xFFFA service-data value into its message(s): one for a
    /// legacy advertisement, several for a Message Pack.
    static func parseServiceData(_ value: [UInt8]) -> [Message] {
        guard value.count >= 2, value[0] == appCode else { return [] }
        let body = Array(value[2...])
        guard !body.isEmpty else { return [] }
        if body[0] >> 4 == 0xF {
            return parsePack(body)
        }
        if let message = decodeMessage(Array(body.prefix(messageSize))) {
            return [message]
        }
        return []
    }

    private static func parsePack(_ body: [UInt8]) -> [Message] {
        guard body.count >= 3 else { return [] }
        let single = body[1] == 0 ? messageSize : Int(body[1])
        let count = Int(body[2])
        var messages: [Message] = []
        for i in 0..<count {
            let start = 3 + i * single
            // The stride is attacker-controlled (a byte in the
            // advertisement): never slice past the body, and a
            // stride smaller than one message cannot hold one.
            guard single >= messageSize,
                  start + single <= body.count else { break }
            if let message = decodeMessage(
                Array(body[start..<(start + messageSize)])) {
                messages.append(message)
            }
        }
        return messages
    }

    // MARK: - A drone, assembled from one value

    struct Report {
        var serial: String?
        var uaType: Int?
        var idType: Int?
        var location: Location?
        var system: SystemInfo?
        var selfIDText: String?
        var operatorID: String?
        var authPages = 0

        mutating func ingest(_ message: Message) {
            if let basic = message.basicID {
                if basic.isSerial { serial = basic.uasID }
                uaType = basic.uaType
                idType = basic.idType
            }
            if let location = message.location { self.location = location }
            if let system = message.system { self.system = system }
            if let text = message.selfIDText, !text.isEmpty { selfIDText = text }
            if let op = message.operatorID, !op.isEmpty { operatorID = op }
            if message.typeID == 0x2 { authPages += 1 }
        }

        var uaTypeName: String {
            uaType.flatMap { Drones.uaTypes[$0] } ?? "aircraft"
        }
        var airborne: Bool { location?.airborne ?? false }
    }

    static func report(fromServiceData value: [UInt8]) -> Report? {
        let messages = parseServiceData(value)
        guard !messages.isEmpty else { return nil }
        var report = Report()
        for message in messages { report.ingest(message) }
        return report
    }

    // MARK: - Describing (mirrors remoteid.describe, without a home point:
    // the phone app does not ask for the listener's own GPS position)

    private static let compassPoints = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func compass(_ bearing: Double) -> String {
        let idx = Int((bearing.truncatingRemainder(dividingBy: 360)) / 45 + 0.5) % 8
        return compassPoints[(idx + 8) % 8]
    }

    static func describe(_ report: Report) -> String {
        var parts: [String] = []
        if let serial = report.serial { parts.append("serial \(serial)") }
        if let ua = report.uaType, ua != 0 { parts.append(report.uaTypeName) }
        if let loc = report.location {
            parts.append(loc.statusName)
            if let alt = loc.altitudeGeo {
                parts.append(String(format: "alt %.0f m", alt))
            } else if let alt = loc.altitudeBaro {
                parts.append(String(format: "baro alt %.0f m", alt))
            }
            if let speed = loc.speedH, let dir = loc.direction {
                parts.append(String(format: "%.1f m/s %@", speed, compass(dir)))
            } else if let speed = loc.speedH {
                parts.append(String(format: "%.1f m/s", speed))
            }
            if let height = loc.height {
                parts.append(String(format: "height %.0f m %@", height, loc.heightRef))
            }
        }
        if let sys = report.system, let lat = sys.operatorLatitude, let lon = sys.operatorLongitude {
            parts.append(String(format: "operator %.5f,%.5f (%@)", lat, lon, sys.operatorLocationName))
        }
        if let text = report.selfIDText {
            parts.append("\u{201C}\(text)\u{201D}")
        }
        return parts.isEmpty ? "Drone (Remote ID)" : "Drone (Remote ID): " + parts.joined(separator: ", ")
    }
}
