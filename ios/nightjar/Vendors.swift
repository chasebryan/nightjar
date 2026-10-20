import Foundation

/// Other makers' manufacturer data, and the company-id table — ports of
/// `nightjar/vendors.py` and `nightjar/companies.py`.
enum Vendors {
    static let microsoft: UInt16 = 0x0006
    static let ruuvi: UInt16 = 0x0499

    static let companyNames: [UInt16: String] = [
        0x0000: "Ericsson", 0x0001: "Nokia", 0x0002: "Intel", 0x0003: "IBM",
        0x0004: "Toshiba", 0x0006: "Microsoft", 0x0008: "Motorola", 0x0009: "Infineon",
        0x000A: L("Cambridge Silicon Radio"), 0x000D: L("Texas Instruments"), 0x000F: "Broadcom",
        0x0013: "Atmel", 0x001D: "Qualcomm", 0x0022: "NEC", 0x0025: L("NXP Semiconductors"),
        0x0029: "Hitachi", 0x0030: L("ST Microelectronics"), 0x0036: "Renesas",
        0x003A: "Panasonic", 0x003C: "BlackBerry", 0x0040: L("Seiko Epson"),
        0x0044: L("Socket Mobile"), 0x0046: "MediaTek", 0x0047: "Bluegiga", 0x0048: "Marvell",
        0x004C: "Apple", 0x0055: "Plantronics", 0x0056: L("Sony Ericsson"), 0x0057: "Harman",
        0x0058: "Vizio", 0x0059: L("Nordic Semiconductor"), 0x005C: "Belkin", 0x005D: "Realtek",
        0x0065: "HP", 0x0067: L("GN Audio (Jabra)"), 0x0068: L("General Motors"), 0x006B: "Polar",
        0x0075: "Samsung", 0x0076: "Creative", 0x0078: "Nike", 0x0082: "Sennheiser",
        0x0087: "Garmin", 0x0089: L("GN Hearing"), 0x008A: "Jawbone", 0x008C: "Gimbal",
        0x009E: "Bose", 0x009F: "Suunto", 0x00A0: "Kensington", 0x00B9: L("Johnson Controls"),
        0x00BA: L("Starkey Hearing"), 0x00C4: L("LG Electronics"), 0x00CC: "Beats",
        0x00CD: "Microchip", 0x00CE: "Elgato", 0x00D0: "Dexcom", 0x00D2: L("Dialog Semiconductor"),
        0x00D6: "Timex", 0x00D7: L("Qualcomm Technologies"), 0x00D9: L("Turtle Beach"),
        0x00E0: "Google", 0x00E8: "Lenovo", 0x0118: L("Radius Networks"), 0x012D: "Sony",
        0x0131: L("Cypress Semiconductor"), 0x0157: L("Huami (Zepp / Mi Band)"), 0x0171: "Amazon",
        0x01AB: L("Meta (Facebook)"), 0x01DA: "Logitech", 0x027D: "Huawei",
        0x02E1: L("Victron Energy"), 0x02E5: "Espressif", 0x02FF: L("Silicon Labs"),
        0x038F: "Xiaomi", 0x0499: "Ruuvi", 0x0553: "Nintendo", 0x05A7: "Sonos",
        0x0969: L("SwitchBot (Woan)"), 0xFFFF: L("(reserved / test)"),
    ]

    static func companyName(_ id: UInt16) -> String {
        // The house's curated short names first,
        // then the SIG's entire registry
        // (CompanyRegistry), then the honest hex.
        return companyNames[id]
            ?? CompanyRegistry.names[id]
            ?? String(format: "0x%04X", id)
    }

    /// MS-CDP beacon device types.
    static let cdpDeviceTypes: [UInt8: String] = [
        1: L("Xbox One"), 6: L("iPhone (CDP)"), 7: "iPad (CDP)", 8: L("Android device (CDP)"),
        9: L("Windows desktop"), 11: L("Windows phone"), 12: L("Linux device (CDP)"),
        13: L("Windows IoT device"), 14: L("Surface Hub"), 15: L("Windows laptop"), 16: L("Windows tablet"),
    ]

    static let familyByCompany: [UInt16: String] = [
        0x0059: L("Nordic-chip device"), 0x0075: L("Samsung device"), 0x0087: L("Garmin device"),
        0x009E: L("Bose device"), 0x00E0: L("Google device"), 0x012D: L("Sony device"),
        0x0157: L("Huami wearable (Mi Band / Amazfit)"), 0x0171: L("Amazon device"),
        0x01DA: L("Logitech device"), 0x027D: L("Huawei device"), 0x02E5: L("ESP32 device"),
        0x038F: L("Xiaomi device"), 0x0553: L("Nintendo controller"), 0x05A7: L("Sonos speaker"),
        0x0969: L("SwitchBot device"),
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
            var details = [L("in pairing mode (Swift Pair)")]
            let nameBytes = Array(payload[3...])
            if let name = String(bytes: nameBytes, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces)),
               !name.isEmpty {
                details.append(String(format: L("announces itself as '%@'"), String(describing: name)))
            }
            return Identification(kind: L("Windows device (Swift Pair)"), details: details,
                                  specificity: 2)
        }
        if first == 0x01 && payload.count >= 2 {
            let deviceType = payload[1] & 0x1F
            let kind = cdpDeviceTypes[deviceType] ?? String(format: L("CDP device type %@"), String(describing: deviceType))
            return Identification(kind: kind, details: [L("Microsoft CDP beacon")], specificity: 2)
        }
        return Identification(kind: L("Microsoft device"), details: [], specificity: 1)
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
        if (power >> 5) != 2047 { parts.append(String(format: L("battery %@ mV"), String(describing: (power >> 5) + 1600))) }
        return parts.isEmpty ? "RuuviTag" : L("RuuviTag: ") + parts.joined(separator: ", ")
    }

    // MARK: - Dispatch

    static func identify(_ manufacturerData: [UInt16: [UInt8]]) -> Identification? {
        if let payload = manufacturerData[microsoft], let ident = decodeMicrosoft(payload) {
            return ident
        }
        if let payload = manufacturerData[ruuvi] {
            if let reading = decodeRuuvi(payload) {
                return Identification(kind: L("RuuviTag sensor"), details: [reading], specificity: 3)
            }
            return Identification(kind: L("Ruuvi device"), details: [], specificity: 2)
        }
        for company in manufacturerData.keys.sorted() {
            if let family = familyByCompany[company] {
                return Identification(kind: family, details: [], specificity: 1)
            }
        }
        for company in manufacturerData.keys.sorted() {
            let name = companyName(company)
            if !name.hasPrefix("0x") {
                return Identification(kind: String(format: L("%@ device"), String(describing: name)), details: [], specificity: 1)
            }
        }
        return nil
    }
}
