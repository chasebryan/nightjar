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
            return Continuity.messageTypes[type] ?? String(format: L("Unknown 0x%02X"), type)
        }
    }

    static let messageTypes: [UInt8: String] = [
        0x02: "iBeacon",
        0x03: "AirPrint",
        0x05: "AirDrop",
        0x06: "HomeKit",
        0x07: L("Proximity Pairing"),
        0x08: L("Hey Siri"),
        0x09: L("AirPlay Target"),
        0x0A: L("AirPlay Source"),
        0x0B: L("Magic Switch"),
        0x0C: "Handoff",
        0x0D: L("Tethering Target"),
        0x0E: L("Tethering Source"),
        0x0F: L("Nearby Action"),
        0x10: L("Nearby Info"),
        0x12: L("Find My"),
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
        "0220": L("AirPods (1st gen)"),
        "0f20": L("AirPods (2nd gen)"),
        "1320": L("AirPods (3rd gen)"),
        "1b20": L("AirPods 4"),
        "1920": L("AirPods 4 (ANC)"),
        "0e20": L("AirPods Pro"),
        "1420": L("AirPods Pro (2nd gen)"),
        "2420": L("AirPods Pro (2nd gen, USB-C)"),
        "0a20": L("AirPods Max"),
        "1f20": L("AirPods Max (USB-C)"),
        "0320": "Powerbeats3",
        "0b20": L("Powerbeats Pro"),
        "2b20": L("Powerbeats Pro 2"),
        "0c20": L("Beats Solo Pro"),
        "0520": "BeatsX",
        "0620": L("Beats Solo3"),
        "2720": L("Beats Solo 4"),
        "2520": L("Beats Solo Buds"),
        "0920": L("Beats Studio3"),
        "1020": L("Beats Flex"),
        "1120": L("Beats Studio Buds"),
        "1620": L("Beats Studio Buds+"),
        "1720": L("Beats Studio Pro"),
        "1220": L("Beats Fit Pro"),
    ]

    static let airPodsColours: [UInt8: String] = [
        0x00: L("white"), 0x01: L("black"), 0x02: L("red"), 0x03: L("blue"), 0x04: L("pink"),
        0x05: L("gray"), 0x06: L("silver"), 0x07: L("gold"), 0x08: L("rose gold"),
        0x09: L("space gray"), 0x0A: L("dark blue"), 0x0B: L("light blue"), 0x0C: L("yellow"),
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
                return text + (charging ? L(" charging") : "")
            }
            let left = String(format: L("L %@%@"), String(describing: batt(leftBattery, leftCharging)), leftInEar ? L(" (in ear)") : "")
            let right = String(format: L("R %@%@"), String(describing: batt(rightBattery, rightCharging)), rightInEar ? L(" (in ear)") : "")
            var text = String(format: L("%@: %@, %@, case %@, lid %@"), String(describing: model), String(describing: left), String(describing: right), String(describing: batt(caseBattery, caseCharging)), lidOpen ? L("open") : L("closed"))
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
            model: airPodsModels[modelCode] ?? String(format: L("AirPods-class (model %@)"), String(describing: modelCode)),
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
            var text = String(format: L("iBeacon %@ major %@ minor %@"), String(describing: proximityUUID), String(describing: major), String(describing: minor))
            if let power = measuredPower {
                text += String(format: L(", %@ dBm @ 1 m"), String(describing: power))
            }
            return text
        }
    }

    /// The Tilt hydrometer rides the iBeacon
    /// frame (decoder expansion, 2026-10-18):
    /// its eight colour UUIDs are the family
    /// A495BB{10..80}-C5B1-4B44-B512-1370F02D74DE,
    /// the major is the beer's temperature in
    /// °F and the minor its specific gravity
    /// (×1000, or ×10000 on the Pro — a minor
    /// past 2000 can only be the Pro's scale).
    static let tiltColors: [String: String] = [
        "10": L("Red"), "20": L("Green"), "30": L("Black"),
        "40": L("Purple"), "50": L("Orange"), "60": L("Blue"),
        "70": L("Yellow"), "80": L("Pink"),
    ]

    static func tiltReading(_ beacon: IBeaconState)
        -> (color: String, describe: String)? {
        let uuid = beacon.proximityUUID
        guard uuid.hasPrefix("a495bb"),
              uuid.hasSuffix(
                "-c5b1-4b44-b512-1370f02d74de")
        else { return nil }
        let code = String(uuid.dropFirst(6).prefix(2))
        guard let color = tiltColors[code]
        else { return nil }
        let pro = beacon.minor > 2000
        let gravity = Double(beacon.minor)
            / (pro ? 10000 : 1000)
        return (color,
                String(format: L("beer %d °F, gravity ")
                       + "%.3f", beacon.major, gravity)
                + (pro ? L(" (Tilt Pro)") : ""))
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

    static let findMyBattery = [L("full"), L("medium"), L("low"), L("very low")]

    struct FindMyState {
        let status: UInt8
        let separated: Bool  // the 0x19 "offline finding" format

        var battery: String {
            return Continuity.findMyBattery[Int((status >> 6) & 0x3)]
        }

        var describe: String {
            if separated {
                return String(format: L("Find My network broadcast (separated from owner), battery %@"), String(describing: battery))
            }
            return L("Find My network broadcast (nearby its owner)")
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
        0x0A: L("watch worn & unlocked"),
    ]

    struct NearbyInfoState {
        let actionCode: UInt8
        let statusFlags: UInt8
        let dataFlags: UInt8?

        var actionLabel: String? { return Continuity.nearbyActionLabels[actionCode] }
        var isWatch: Bool { return actionCode == 0x0A }

        var describe: String {
            let code = String(format: L("nearby state 0x%02X"), actionCode)
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
        0x01: L("Apple TV setup"),
        0x04: L("mobile backup"),
        0x05: L("watch setup"),
        0x06: L("Apple TV pair"),
        0x07: L("internet relay"),
        0x08: L("Wi-Fi password share"),
        0x09: L("iOS setup"),
        0x0A: "repair",
        0x0B: L("speaker setup"),
        0x0C: L("Apple Pay"),
        0x0D: L("whole-home audio setup"),
        0x0E: L("developer tools pairing"),
        0x0F: L("answered call"),
        0x10: L("ended call"),
        0x11: L("DD ping"),
        0x12: L("DD pong"),
        0x13: L("remote AutoFill"),
        0x14: L("companion link proximity"),
        0x15: L("remote management"),
        0x16: L("remote AutoFill pong"),
        0x17: L("remote display"),
    ]

    struct NearbyActionState {
        let flags: UInt8
        let actionType: UInt8

        var describe: String {
            let label = Continuity.nearbyActionTypes[actionType]
                ?? String(format: L("type 0x%02X"), actionType)
            return String(format: L("nearby action: %@"), String(describing: label))
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
            if let battery = battery { parts.append(String(format: L("battery %@%%"), String(describing: battery))) }
            if let bars = cellBars { parts.append(String(format: L("cell %@ bars"), String(describing: bars))) }
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
            return details.isEmpty ? kind : String(format: L("%@ — %@"), String(describing: kind), String(describing: details.joined(separator: "; ")))
        }
    }

    /// Identify an Apple device from its Continuity payload.
    static func identifyApple(_ payload: [UInt8]) -> Identification {
        if let findMy = parseFindMy(payload) {
            let kind = findMy.separated ? L("Find My device (AirTag-class)")
                                        : L("Find My accessory (with owner)")
            return Identification(kind: kind, details: [findMy.describe],
                                  messages: [L("Find My")], findMy: findMy, specificity: 3)
        }
        let messages = parse(payload)
        let names = messages.map { $0.typeName }
        var details: [String] = []
        var kind = L("Apple device")
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
                    if let tilt = tiltReading(beacon) {
                        kind = L("Tilt hydrometer (")
                            + tilt.color + ")"
                        specificity = 3
                        details.append(tilt.describe)
                    } else {
                        kind = "iBeacon"
                        specificity = 3
                        details.append(beacon.describe)
                    }
                }
            case 0x10:
                if let nearby = decodeNearbyInfo(message) {
                    details.append(nearby.describe)
                    if nearby.isWatch && specificity < 3 {
                        kind = L("Apple Watch")
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
                        kind = L("iPhone (Instant Hotspot source)")
                        specificity = 2
                    }
                }
            default:
                break
            }
        }
        if kind == L("Apple device") && names.contains(L("Nearby Info")) {
            kind = L("Apple device (Nearby Info)")
        }
        return Identification(kind: kind, details: details, messages: names,
                              findMy: nil, specificity: specificity)
    }
}
