import Foundation

/// Reading what an Apple broadcast says — a port of `nightjar/continuity.py`.
///
/// Apple devices pack their manufacturer payload (company 0x004C) as a
/// chain of small messages framed [type][length][value]. Find My
/// accessory broadcasts are the exception: one fixed-format record,
/// recognized before the chain is walked. Every string produced here
/// matches the Python side character for character, so a device looks
/// the same on the phone and in the Mac's reports.
enum Continuity {
    static let appleCompanyID: UInt16 = 0x004C

    struct Message {
        let type: UInt8
        let value: [UInt8]

        var typeName: String {
            return Continuity.messageTypes[type] ?? String(format: "Unknown 0x%02X", type)
        }
    }

    static let messageTypes: [UInt8: String] = [
        0x02: "iBeacon",
        0x03: "AirPrint",
        0x05: "AirDrop",
        0x06: "HomeKit",
        0x07: "Proximity Pairing",
        0x08: "Hey Siri",
        0x09: "AirPlay Target",
        0x0A: "AirPlay Source",
        0x0B: "Magic Switch",
        0x0C: "Handoff",
        0x0D: "Tethering Target",
        0x0E: "Tethering Source",
        0x0F: "Nearby Action",
        0x10: "Nearby Info",
        0x12: "Find My",
    ]

    /// Split an Apple manufacturer payload into its TLV messages.
    static func parse(_ payload: [UInt8]) -> [Message] {
        var messages: [Message] = []
        var index = 0
        while index + 2 <= payload.count {
            let type = payload[index]
            let length = Int(payload[index + 1])
            let start = index + 2
            if start + length > payload.count {
                break  // truncated tail; keep what parsed cleanly
            }
            messages.append(Message(type: type, value: Array(payload[start..<(start + length)])))
            index = start + length
        }
        return messages
    }

    // MARK: - Proximity Pairing (AirPods, Beats)

    static let airPodsModels: [String: String] = [
        "0220": "AirPods (1st gen)",
        "0f20": "AirPods (2nd gen)",
        "1320": "AirPods (3rd gen)",
        "1b20": "AirPods 4",
        "1920": "AirPods 4 (ANC)",
        "0e20": "AirPods Pro",
        "1420": "AirPods Pro (2nd gen)",
        "2420": "AirPods Pro (2nd gen, USB-C)",
        "0a20": "AirPods Max",
        "1f20": "AirPods Max (USB-C)",
        "0320": "Powerbeats3",
        "0b20": "Powerbeats Pro",
        "2b20": "Powerbeats Pro 2",
        "0c20": "Beats Solo Pro",
        "0520": "BeatsX",
        "0620": "Beats Solo3",
        "2720": "Beats Solo 4",
        "2520": "Beats Solo Buds",
        "0920": "Beats Studio3",
        "1020": "Beats Flex",
        "1120": "Beats Studio Buds",
        "1620": "Beats Studio Buds+",
        "1720": "Beats Studio Pro",
        "1220": "Beats Fit Pro",
    ]

    static let airPodsColours: [UInt8: String] = [
        0x00: "white", 0x01: "black", 0x02: "red", 0x03: "blue", 0x04: "pink",
        0x05: "gray", 0x06: "silver", 0x07: "gold", 0x08: "rose gold",
        0x09: "space gray", 0x0A: "dark blue", 0x0B: "light blue", 0x0C: "yellow",
    ]

    /// Battery nibbles run 0..10 (x10 %); 15 means unknown/absent.
    private static func batteryLevel(_ nibble: UInt8) -> Int? {
        return nibble <= 10 ? Int(nibble) * 10 : nil
    }

    struct AirPodsState {
        let model: String
        let modelCode: String
        let leftBattery: Int?
        let rightBattery: Int?
        let caseBattery: Int?
        let leftInEar: Bool
        let rightInEar: Bool
        let leftCharging: Bool
        let rightCharging: Bool
        let caseCharging: Bool
        let lidOpen: Bool
        let colour: String?

        var describe: String {
            func batt(_ value: Int?, _ charging: Bool) -> String {
                let text = value.map { "\($0)%" } ?? "?"
                return text + (charging ? " charging" : "")
            }
            let left = "L \(batt(leftBattery, leftCharging))\(leftInEar ? " (in ear)" : "")"
            let right = "R \(batt(rightBattery, rightCharging))\(rightInEar ? " (in ear)" : "")"
            var text = "\(model): \(left), \(right), case \(batt(caseBattery, caseCharging)), "
                + "lid \(lidOpen ? "open" : "closed")"
            if let colour = colour {
                text += ", \(colour)"
            }
            return text
        }
    }

    /// Decode a Proximity Pairing message, following the OpenPods layout:
    /// when the 0x20 bit of the status byte is clear, left and right swap.
    static func decodeAirPods(_ message: Message) -> AirPodsState? {
        let v = message.value
        guard message.type == 0x07, v.count >= 8 else { return nil }
        let modelCode = JSONL.hex([v[1], v[2]])
        let status = v[3]
        let flipped = (status & 0x20) == 0
        let high = (v[4] >> 4) & 0xF
        let low = v[4] & 0xF
        let rightNibble = flipped ? low : high
        let leftNibble = flipped ? high : low
        let charge = (v[5] >> 4) & 0xF
        let leftBit: UInt8 = flipped ? 0x02 : 0x01
        let rightBit: UInt8 = flipped ? 0x01 : 0x02
        let ear = status & 0x0F
        let leftEarBit: UInt8 = flipped ? 0x08 : 0x02
        let rightEarBit: UInt8 = flipped ? 0x02 : 0x08
        let colourByte: UInt8? = v.count > 7 ? v[7] : nil
        return AirPodsState(
            model: airPodsModels[modelCode] ?? "AirPods-class (model \(modelCode))",
            modelCode: modelCode,
            leftBattery: batteryLevel(leftNibble),
            rightBattery: batteryLevel(rightNibble),
            caseBattery: batteryLevel(v[5] & 0xF),
            leftInEar: (ear & leftEarBit) != 0,
            rightInEar: (ear & rightEarBit) != 0,
            leftCharging: (charge & leftBit) != 0,
            rightCharging: (charge & rightBit) != 0,
            caseCharging: (charge & 0x04) != 0,
            lidOpen: (v[6] & 0x08) != 0,
            colour: colourByte.flatMap { airPodsColours[$0] }
        )
    }

    // MARK: - iBeacon

    struct IBeaconState {
        let proximityUUID: String
        let major: Int
        let minor: Int
        let measuredPower: Int?

        var describe: String {
            var text = "iBeacon \(proximityUUID) major \(major) minor \(minor)"
            if let power = measuredPower {
                text += ", \(power) dBm @ 1 m"
            }
            return text
        }
    }

    static func decodeIBeacon(_ message: Message) -> IBeaconState? {
        let v = message.value
        guard message.type == 0x02, v.count >= 20 else { return nil }
        let uuid = UUID(uuid: (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7],
                               v[8], v[9], v[10], v[11], v[12], v[13], v[14], v[15]))
        var power: Int?
        if v.count >= 21 {
            power = Int(Int8(bitPattern: v[20]))
        }
        return IBeaconState(
            proximityUUID: uuid.uuidString.lowercased(),
            major: Int(v[16]) << 8 | Int(v[17]),
            minor: Int(v[18]) << 8 | Int(v[19]),
            measuredPower: power
        )
    }

    // MARK: - Find My

    static let findMyBattery = ["full", "medium", "low", "very low"]

    struct FindMyState {
        let status: UInt8
        let separated: Bool  // the 0x19 "offline finding" format

        var battery: String {
            return Continuity.findMyBattery[Int((status >> 6) & 0x3)]
        }

        var describe: String {
            if separated {
                return "Find My network broadcast (separated from owner), battery \(battery)"
            }
            return "Find My network broadcast (nearby its owner)"
        }
    }

    /// Recognize a Find My accessory broadcast (not a TLV message).
    static func parseFindMy(_ payload: [UInt8]) -> FindMyState? {
        if payload.count >= 27 && payload[0] == 0x12 && payload[1] == 0x19 {
            return FindMyState(status: payload[2], separated: true)
        }
        if payload.count == 4 && payload[0] == 0x12 && payload[1] == 0x02 {
            return FindMyState(status: payload[2], separated: false)
        }
        return nil
    }

    // MARK: - Nearby Info

    /// Only the verified code is labelled; the rest are shown numerically.
    static let nearbyActionLabels: [UInt8: String] = [
        0x0A: "watch worn & unlocked",
    ]

    struct NearbyInfoState {
        let actionCode: UInt8
        let statusFlags: UInt8
        let dataFlags: UInt8?

        var actionLabel: String? { return Continuity.nearbyActionLabels[actionCode] }
        var isWatch: Bool { return actionCode == 0x0A }

        var describe: String {
            let code = String(format: "nearby state 0x%02X", actionCode)
            if let label = actionLabel {
                return "\(code) (\(label))"
            }
            return code
        }
    }

    static func decodeNearbyInfo(_ message: Message) -> NearbyInfoState? {
        guard message.type == 0x10, let first = message.value.first else { return nil }
        return NearbyInfoState(
            actionCode: first & 0x0F,
            statusFlags: (first >> 4) & 0x0F,
            dataFlags: message.value.count > 1 ? message.value[1] : nil
        )
    }

    // MARK: - Nearby Action

    static let nearbyActionTypes: [UInt8: String] = [
        0x01: "Apple TV setup",
        0x04: "mobile backup",
        0x05: "watch setup",
        0x06: "Apple TV pair",
        0x07: "internet relay",
        0x08: "Wi-Fi password share",
        0x09: "iOS setup",
        0x0A: "repair",
        0x0B: "speaker setup",
        0x0C: "Apple Pay",
        0x0D: "whole-home audio setup",
        0x0E: "developer tools pairing",
        0x0F: "answered call",
        0x10: "ended call",
        0x11: "DD ping",
        0x12: "DD pong",
        0x13: "remote AutoFill",
        0x14: "companion link proximity",
        0x15: "remote management",
        0x16: "remote AutoFill pong",
        0x17: "remote display",
    ]

    struct NearbyActionState {
        let flags: UInt8
        let actionType: UInt8

        var describe: String {
            let label = Continuity.nearbyActionTypes[actionType]
                ?? String(format: "type 0x%02X", actionType)
            return "nearby action: \(label)"
        }
    }

    static func decodeNearbyAction(_ message: Message) -> NearbyActionState? {
        guard message.type == 0x0F, message.value.count >= 2 else { return nil }
        return NearbyActionState(flags: message.value[0], actionType: message.value[1])
    }

    // MARK: - Tethering Source (Instant Hotspot)

    struct TetheringSourceState {
        let battery: Int?
        let cellBars: Int?

        var describe: String {
            var parts = ["hotspot-capable"]
            if let battery = battery { parts.append("battery \(battery)%") }
            if let bars = cellBars { parts.append("cell \(bars) bars") }
            return parts.joined(separator: ", ")
        }
    }

    static func decodeTetheringSource(_ message: Message) -> TetheringSourceState? {
        let v = message.value
        guard message.type == 0x0E, v.count >= 3 else { return nil }
        let battery: Int? = v[2] <= 100 ? Int(v[2]) : nil
        let bars: Int? = (v.count > 4 && v[4] <= 5) ? Int(v[4]) : nil
        return TetheringSourceState(battery: battery, cellBars: bars)
    }

    // MARK: - Putting it together

    struct Identification {
        let kind: String
        let details: [String]
        let messages: [String]
        let findMy: FindMyState?
        let specificity: Int  // 1 family, 2 sub-family, 3 product

        var describe: String {
            return details.isEmpty ? kind : "\(kind) — \(details.joined(separator: "; "))"
        }
    }

    /// Identify an Apple device from its Continuity payload.
    static func identifyApple(_ payload: [UInt8]) -> Identification {
        if let findMy = parseFindMy(payload) {
            let kind = findMy.separated ? "Find My device (AirTag-class)"
                                        : "Find My accessory (with owner)"
            return Identification(kind: kind, details: [findMy.describe],
                                  messages: ["Find My"], findMy: findMy, specificity: 3)
        }
        let messages = parse(payload)
        let names = messages.map { $0.typeName }
        var details: [String] = []
        var kind = "Apple device"
        var specificity = 1
        for message in messages {
            switch message.type {
            case 0x07:
                if let state = decodeAirPods(message) {
                    kind = state.model
                    specificity = 3
                    details.append(state.describe)
                }
            case 0x02:
                if let beacon = decodeIBeacon(message) {
                    kind = "iBeacon"
                    specificity = 3
                    details.append(beacon.describe)
                }
            case 0x10:
                if let nearby = decodeNearbyInfo(message) {
                    details.append(nearby.describe)
                    if nearby.isWatch && specificity < 3 {
                        kind = "Apple Watch"
                        specificity = 2
                    }
                }
            case 0x0F:
                if let action = decodeNearbyAction(message) {
                    details.append(action.describe)
                }
            case 0x0E:
                if let source = decodeTetheringSource(message) {
                    details.append(source.describe)
                    if specificity < 2 {
                        kind = "iPhone (Instant Hotspot source)"
                        specificity = 2
                    }
                }
            default:
                break
            }
        }
        if kind == "Apple device" && names.contains("Nearby Info") {
            kind = "Apple device (Nearby Info)"
        }
        return Identification(kind: kind, details: details, messages: names,
                              findMy: nil, specificity: specificity)
    }
}
