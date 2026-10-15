import Foundation

/// Other makers' manufacturer data, and the company-id table — ports of
/// `nightjar/vendors.py` and `nightjar/companies.py`.
enum Vendors {
    static let microsoft: UInt16 = 0x0006
    static let ruuvi: UInt16 = 0x0499

    static let companyNames: [UInt16: String] = [
        0x0000: "Ericsson", 0x0001: "Nokia", 0x0002: "Intel", 0x0003: "IBM",
        0x0004: "Toshiba", 0x0006: "Microsoft", 0x0008: "Motorola", 0x0009: "Infineon",
        0x000A: "Cambridge Silicon Radio", 0x000D: "Texas Instruments", 0x000F: "Broadcom",
        0x0013: "Atmel", 0x001D: "Qualcomm", 0x0022: "NEC", 0x0025: "NXP Semiconductors",
        0x0029: "Hitachi", 0x0030: "ST Microelectronics", 0x0036: "Renesas",
        0x003A: "Panasonic", 0x003C: "BlackBerry", 0x0040: "Seiko Epson",
        0x0044: "Socket Mobile", 0x0046: "MediaTek", 0x0047: "Bluegiga", 0x0048: "Marvell",
        0x004C: "Apple", 0x0055: "Plantronics", 0x0056: "Sony Ericsson", 0x0057: "Harman",
        0x0058: "Vizio", 0x0059: "Nordic Semiconductor", 0x005C: "Belkin", 0x005D: "Realtek",
        0x0065: "HP", 0x0067: "GN Audio (Jabra)", 0x0068: "General Motors", 0x006B: "Polar",
        0x0075: "Samsung", 0x0076: "Creative", 0x0078: "Nike", 0x0082: "Sennheiser",
        0x0087: "Garmin", 0x0089: "GN Hearing", 0x008A: "Jawbone", 0x008C: "Gimbal",
        0x009E: "Bose", 0x009F: "Suunto", 0x00A0: "Kensington", 0x00B9: "Johnson Controls",
        0x00BA: "Starkey Hearing", 0x00C4: "LG Electronics", 0x00CC: "Beats",
        0x00CD: "Microchip", 0x00CE: "Elgato", 0x00D0: "Dexcom", 0x00D2: "Dialog Semiconductor",
        0x00D6: "Timex", 0x00D7: "Qualcomm Technologies", 0x00D9: "Turtle Beach",
        0x00E0: "Google", 0x00E8: "Lenovo", 0x0118: "Radius Networks", 0x012D: "Sony",
        0x0131: "Cypress Semiconductor", 0x0157: "Huami (Zepp / Mi Band)", 0x0171: "Amazon",
        0x01AB: "Meta (Facebook)", 0x01DA: "Logitech", 0x027D: "Huawei",
        0x02E1: "Victron Energy", 0x02E5: "Espressif", 0x02FF: "Silicon Labs",
        0x038F: "Xiaomi", 0x0499: "Ruuvi", 0x0553: "Nintendo", 0x05A7: "Sonos",
        0x0969: "SwitchBot (Woan)", 0xFFFF: "(reserved / test)",
    ]

    static func companyName(_ id: UInt16) -> String {
        return companyNames[id] ?? String(format: "0x%04X", id)
    }

    /// MS-CDP beacon device types.
    static let cdpDeviceTypes: [UInt8: String] = [
        1: "Xbox One", 6: "iPhone (CDP)", 7: "iPad (CDP)", 8: "Android device (CDP)",
        9: "Windows desktop", 11: "Windows phone", 12: "Linux device (CDP)",
        13: "Windows IoT device", 14: "Surface Hub", 15: "Windows laptop", 16: "Windows tablet",
    ]

    static let familyByCompany: [UInt16: String] = [
        0x0059: "Nordic-chip device", 0x0075: "Samsung device", 0x0087: "Garmin device",
        0x009E: "Bose device", 0x00E0: "Google device", 0x012D: "Sony device",
        0x0157: "Huami wearable (Mi Band / Amazfit)", 0x0171: "Amazon device",
        0x01DA: "Logitech device", 0x027D: "Huawei device", 0x02E5: "ESP32 device",
        0x038F: "Xiaomi device", 0x0553: "Nintendo controller", 0x05A7: "Sonos speaker",
        0x0969: "SwitchBot device",
    ]

    struct Identification {
        let kind: String
        let details: [String]
        let specificity: Int
    }

    // MARK: - Microsoft

    static func decodeMicrosoft(_ payload: [UInt8]) -> Identification? {
        guard let first = payload.first else { return nil }
        if first == 0x03 && payload.count >= 3 {
            var details = ["in pairing mode (Swift Pair)"]
            let nameBytes = Array(payload[3...])
            if let name = String(bytes: nameBytes, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces)),
               !name.isEmpty {
                details.append("announces itself as '\(name)'")
            }
            return Identification(kind: "Windows device (Swift Pair)", details: details,
                                  specificity: 2)
        }
        if first == 0x01 && payload.count >= 2 {
            let deviceType = payload[1] & 0x1F
            let kind = cdpDeviceTypes[deviceType] ?? "CDP device type \(deviceType)"
            return Identification(kind: kind, details: ["Microsoft CDP beacon"], specificity: 2)
        }
        return Identification(kind: "Microsoft device", details: [], specificity: 1)
    }

    // MARK: - Ruuvi RAWv2

    static func decodeRuuvi(_ payload: [UInt8]) -> String? {
        guard payload.count >= 24, payload[0] == 0x05 else { return nil }
        let tempRaw = Int16(bitPattern: UInt16(payload[1]) << 8 | UInt16(payload[2]))
        let humRaw = Int(payload[3]) << 8 | Int(payload[4])
        let presRaw = Int(payload[5]) << 8 | Int(payload[6])
        let power = Int(payload[13]) << 8 | Int(payload[14])
        var parts: [String] = []
        if tempRaw != -32768 { parts.append(String(format: "%.2f °C", Double(tempRaw) * 0.005)) }
        if humRaw != 0xFFFF { parts.append(String(format: "%.1f%% RH", Double(humRaw) * 0.0025)) }
        if presRaw != 0xFFFF { parts.append(String(format: "%.1f hPa", Double(presRaw + 50000) / 100.0)) }
        if (power >> 5) != 2047 { parts.append("battery \((power >> 5) + 1600) mV") }
        return parts.isEmpty ? "RuuviTag" : "RuuviTag: " + parts.joined(separator: ", ")
    }

    // MARK: - Dispatch

    static func identify(_ manufacturerData: [UInt16: [UInt8]]) -> Identification? {
        if let payload = manufacturerData[microsoft], let ident = decodeMicrosoft(payload) {
            return ident
        }
        if let payload = manufacturerData[ruuvi] {
            if let reading = decodeRuuvi(payload) {
                return Identification(kind: "RuuviTag sensor", details: [reading], specificity: 3)
            }
            return Identification(kind: "Ruuvi device", details: [], specificity: 2)
        }
        for company in manufacturerData.keys.sorted() {
            if let family = familyByCompany[company] {
                return Identification(kind: family, details: [], specificity: 1)
            }
        }
        for company in manufacturerData.keys.sorted() {
            let name = companyName(company)
            if !name.hasPrefix("0x") {
                return Identification(kind: "\(name) device", details: [], specificity: 1)
            }
        }
        return nil
    }
}
