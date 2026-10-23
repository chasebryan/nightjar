import Foundation

/// The expansion batch — formats verified against
/// public specifications (vendor protocol repos,
/// the Bluetooth SIG's BAS 1.1, Theengs Decoder's
/// byte-exact definitions) and admitted under the
/// same discipline as the house's other decoders:
/// a strict structural gate before any byte is
/// trusted, possibility language where a format is
/// a family's rather than a product's, and every
/// battery field taken only where the
/// specification puts it. Batteries live here and
/// in the engine together: this file classifies,
/// and `batteryReadings` feeds DecoderEngine, so
/// one sighting is read by every decoder the
/// house owns.
enum ExpansionDecoders {

    static let estimoteService: UInt16 = 0xFE9A
    static let environmentalService: UInt16 = 0x181A
    static let qingpingService: UInt16 = 0xFDCD
    static let bthomeV1Service: UInt16 = 0x181C
    static let bthomeV1EncryptedService: UInt16 = 0x181E
    static let basService: UInt16 = 0x180F

    /// BTHome v1's encryption carries no replay
    /// counter — a captured advertisement can be
    /// replayed verbatim and accepted. The house
    /// therefore decodes v1 only when the operator
    /// has switched it on, knowing that.
    static var bthomeV1Enabled: Bool {
        UserDefaults.standard.bool(forKey: "listen.bthomeV1")
    }

    private static func serviceData(
        _ sighting: Sighting, _ id: UInt16
    ) -> [UInt8]? {
        for (uuid, payload) in sighting.serviceData
        where Services.short(uuid) == id {
            return payload
        }
        return nil
    }

    // MARK: - Classification

    struct Identification {
        let kind: String
        let details: [String]
        let specificity: Int  // 1 family, 2 sub-family, 3 product
    }

    static func identify(
        _ sighting: Sighting
    ) -> Identification? {
        if let candidate = switchBotDetailed(sighting) {
            return candidate
        }
        if let candidate = estimote(sighting) {
            return candidate
        }
        if let candidate = xiaomiThermo(sighting) {
            return candidate
        }
        if let candidate = qingping(sighting) {
            return candidate
        }
        if bthomeV1Enabled,
           let candidate = bthomeV1(sighting) {
            return candidate
        }
        if let candidate = basBroadcast(sighting) {
            return candidate
        }
        if let candidate = victron(sighting) {
            return candidate
        }
        if let candidate = mopeka(sighting) {
            return candidate
        }
        if let candidate = tpmsClone(sighting) {
            return candidate
        }
        if let candidate = inkbird(sighting) {
            return candidate
        }
        if let candidate = thermoPro(sighting) {
            return candidate
        }
        if let candidate = aranet(sighting) {
            return candidate
        }
        if let candidate = sensorPushHT(sighting) {
            return candidate
        }
        if let candidate = sensorPushHTP(sighting) {
            return candidate
        }
        if let candidate = oralB(sighting) {
            return candidate
        }
        if let candidate = msCDP(sighting) {
            return candidate
        }
        return nil
    }

    // MARK: SwitchBot — the detailed frames

    /// Device type by the vendor's own rule: the
    /// type byte, never layout similarity.
    static let switchBotTypes: [UInt8: String] = [
        0x48: L("Bot"), 0x54: L("Meter"), 0x69: L("Meter Plus"),
        0x49: L("Meter Plus"), 0x35: L("Meter Pro CO2"),
        0x15: L("Meter Pro CO2"), 0x77: L("Outdoor Meter"),
        0x57: L("Outdoor Meter"), 0x65: L("Humidifier"),
        0x63: L("Curtain"), 0x43: L("Curtain"),
        0x7B: L("Curtain 3"), 0x5B: L("Curtain 3"),
        0x73: L("Motion sensor"), 0x64: L("Contact sensor"),
        0x75: L("Color Bulb"), 0x72: L("LED Strip"),
        0x71: L("Ceiling Light"), 0x51: L("Ceiling Light"),
        0x6E: L("Ceiling Light Pro"),
        0x4E: L("Ceiling Light Pro"), 0x6F: L("Lock"),
        0x67: L("Plug Mini"), 0x47: L("Plug Mini"),
        0x6A: L("Plug Mini"), 0x4A: L("Plug Mini"),
    ]

    static func switchBotType(
        _ payload: [UInt8]
    ) -> String? {
        guard payload.count >= 3 else { return nil }
        return switchBotTypes[payload[0] & 0x7F]
    }

    private static func switchBotDetailed(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = serviceData(
                sighting, MoreDecoders.switchBotService),
              let type = switchBotType(payload)
        else { return nil }
        var details = [String(format: L("battery %@%% (SwitchBot)"), String(describing: payload[2] & 0x7F))]
        switch payload[0] & 0x7F {
        case 0x54, 0x69, 0x49:
            // Meter / Meter Plus: temperature and
            // humidity ride along.
            if payload.count >= 6 {
                let fraction = Double(payload[3] & 0x0F)
                    / 10
                let whole = Double(payload[4] & 0x7F)
                let temp = (payload[4] & 0x80) != 0
                    ? whole + fraction
                    : -(whole + fraction)
                details.append(String(
                    format: L("temperature %.1f °C"), temp))
                details.append(String(format: L("humidity %@%%"), String(describing: payload[5] & 0x7F)))
            }
        case 0x64:
            // Contact: the HAL state says open or
            // closed, in the sensor's own words.
            if payload.count >= 4 {
                let hal = (payload[3] >> 1) & 0x03
                details.append(hal == 0 ? L("door closed")
                    : hal == 1 ? L("door open")
                    : hal == 2 ? L("door open too long")
                    : L("door state unknown"))
                details.append((payload[3] & 0x01) != 0
                    ? L("light present") : "dark")
            }
        case 0x73:
            if payload.count >= 2 {
                details.append((payload[1] & 0x40) != 0
                    ? L("motion detected") : L("no motion"))
            }
        default:
            break
        }
        return Identification(kind: L("SwitchBot ") + type, details: details, specificity: 2)
    }

    // MARK: Estimote Telemetry

    private static func estimote(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = serviceData(
                sighting, estimoteService),
              payload.count >= 20,
              (payload[0] & 0x0F) == 2
        else { return nil }
        let subframe = (payload[9] >> 0) & 0x03
        var details = [L("Estimote telemetry, subframe ")
            + (subframe == 0 ? "A" : "B")]
        if let reading = estimoteBattery(payload) {
            details.append(reading.summary)
        }
        return Identification(kind: L("Estimote beacon"), details: details, specificity: 2)
    }

    /// Subframe B carries the richest passive
    /// battery in this batch: a 14-bit voltage and
    /// a percentage, each with a not-measured
    /// sentinel the spec defines.
    static func estimoteBattery(
        _ payload: [UInt8]
    ) -> BatteryReading? {
        guard payload.count >= 20,
              (payload[0] & 0x0F) == 2,
              ((payload[9] >> 0) & 0x03) == 1
        else { return nil }
        let version = (payload[0] >> 4) & 0x0F
        let millivolts = (Int(payload[18]) << 6)
            | ((Int(payload[17]) & 0xFC) >> 2)
        let percent: Int? = (version >= 1
            && payload[19] != 0xFF)
            ? Int(payload[19]) : nil
        let volts: Int? = millivolts != 0x3FFF
            ? millivolts : nil
        guard percent != nil || volts != nil else {
            return nil
        }
        return BatteryReading(
            component: "device", percent: percent,
            millivolts: volts, state: nil,
            source: "Estimote", observedAt: 0)
    }

    // MARK: Xiaomi thermometers, aftermarket firmware

    /// Two firmwares share the Environmental
    /// Sensing service: PVVX custom (15 bytes,
    /// little-endian) and ATC1441 (13 bytes,
    /// big-endian where it counts) — told apart
    /// by length, exactly as their authors
    /// specify.
    private static func xiaomiThermo(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = serviceData(
            sighting, environmentalService)
        else { return nil }
        if payload.count == 15 {
            let rawTemp = Int16(bitPattern:
                UInt16(payload[6])
                    | UInt16(payload[7]) << 8)
            let temp = Double(rawTemp) / 100
            let humidity = Double(
                UInt16(payload[8])
                    | UInt16(payload[9]) << 8) / 100
            guard temp > -60, temp < 120,
                  humidity <= 100 else { return nil }
            return Identification(kind: L("Mi thermometer (PVVX firmware)"), details: [
                    String(format: L("temperature %.2f °C"),
                           temp),
                    String(format: L("humidity %.1f %%"),
                           humidity),
                ], specificity: 3)
        }
        if payload.count == 13 {
            let rawTemp = Int16(bitPattern:
                UInt16(payload[6]) << 8
                    | UInt16(payload[7]))
            let temp = Double(rawTemp) / 10
            let humidity = Double(payload[8])
            guard temp > -60, temp < 120,
                  humidity <= 100 else { return nil }
            return Identification(kind: L("Mi thermometer (ATC firmware)"), details: [
                    String(format: L("temperature %.1f °C"),
                           temp),
                    String(format: L("humidity %@%%"), String(describing: Int(humidity))),
                ], specificity: 2)
        }
        return nil
    }

    /// The same two frames' batteries: PVVX
    /// reports both voltage and level; ATC
    /// reports both as well, big-endian.
    static func xiaomiThermoBattery(
        _ sighting: Sighting
    ) -> BatteryReading? {
        guard let payload = serviceData(
            sighting, environmentalService)
        else { return nil }
        if payload.count == 15 {
            let millivolts = Int(payload[10])
                | Int(payload[11]) << 8
            return BatteryReading(
                component: "device",
                percent: Int(payload[12]),
                millivolts: millivolts, state: nil,
                source: "PVVX", observedAt: 0)
        }
        if payload.count == 13 {
            let millivolts = Int(payload[10]) << 8
                | Int(payload[11])
            return BatteryReading(
                component: "device",
                percent: Int(payload[9]),
                millivolts: millivolts, state: nil,
                source: "ATC", observedAt: 0)
        }
        return nil
    }

    // MARK: Qingping / ClearGrass

    private static func qingping(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = serviceData(
                sighting, qingpingService),
              payload.count >= 10
        else { return nil }
        if payload.count >= 21, payload[1] == 0x09 {
            let rawTemp = Int16(bitPattern:
                UInt16(payload[10])
                    | UInt16(payload[11]) << 8)
            let humidity = Double(
                UInt16(payload[12])
                    | UInt16(payload[13]) << 8) / 10
            return Identification(kind: L("Qingping weather station"), details: [
                    String(format: L("temperature %.1f °C"),
                           Double(rawTemp) / 10),
                    String(format: L("humidity %.0f %%"),
                           humidity),
                    String(format: L("battery %@%% (Qingping)"), String(describing: payload[20] & 0x7F)),
                ], specificity: 3)
        }
        return Identification(kind: L("Qingping / ClearGrass sensor"), details: [], specificity: 1)
    }

    // MARK: BTHome v1 — opt-in, replay caveat

    /// The v1 object walk: control byte (length
    /// including the id, format in the high bits),
    /// id, little-endian value. Plaintext only —
    /// the house holds no BTHome keys.
    static func bthomeV1Objects(
        _ payload: [UInt8]
    ) -> [UInt8: Int]? {
        var objects: [UInt8: Int] = [:]
        var index = 0
        while index < payload.count {
            let control = payload[index]
            let length = Int(control & 0x1F)
            let format = (control >> 5) & 0x07
            guard length >= 1,
                  index + 1 + length <= payload.count
            else { return nil }
            let objectID = payload[index + 1]
            let valueBytes = length - 1
            if format == 0, valueBytes >= 1,
               valueBytes <= 4 {
                var value = 0
                for offset in 0..<valueBytes {
                    value |= Int(payload[
                        index + 2 + offset]) << (8 * offset)
                }
                objects[objectID] = value
            }
            index += 1 + length
        }
        return objects
    }

    private static func bthomeV1(
        _ sighting: Sighting
    ) -> Identification? {
        if serviceData(sighting,
                       bthomeV1EncryptedService) != nil {
            return Identification(kind: L("BTHome v1 sensor (encrypted)"), details: [L("encrypted — contents not ")
                    + L("readable; v1 encryption has no ")
                    + L("replay protection")], specificity: 1)
        }
        guard let payload = serviceData(
                sighting, bthomeV1Service),
              let objects = bthomeV1Objects(payload),
              !objects.isEmpty
        else { return nil }
        var details: [String] = []
        if let raw = objects[0x02] {
            let signed = raw > 0x7FFF ? raw - 0x10000 : raw
            details.append(String(
                format: L("temperature %.2f °C"),
                Double(signed) / 100))
        }
        if let raw = objects[0x03] {
            details.append(String(
                format: L("humidity %.1f %%"),
                Double(raw) / 100))
        }
        if let percent = objects[0x01] {
            details.append(String(format: L("battery %@%% (BTHome v1)"), String(describing: percent)))
        }
        return Identification(kind: L("BTHome v1 sensor"), details: details, specificity: 2)
    }

    // MARK: BAS 1.1 — the standard's broadcast form

    /// Battery Level Status broadcast in a 0x180F
    /// service-data structure: flags, the 16-bit
    /// power state, then the optional identifier,
    /// level and additional status — the total
    /// length must match the flags exactly, which
    /// is what makes the parse trustworthy.
    static func basBroadcastReading(
        _ payload: [UInt8]
    ) -> (percent: Int?, state: String?)? {
        // The level-only form (the audit,
        // 2026-10-18): a single byte that IS
        // the level — the shape a large share
        // of battery beacons actually send,
        // which the strict flags form below
        // never sees. A byte over 100 is not
        // a level, and the gate stays shut.
        if payload.count == 1 {
            return payload[0] <= 100
                ? (percent: Int(payload[0]),
                   state: nil)
                : nil
        }
        guard payload.count >= 3 else { return nil }
        let flags = payload[0]
        let hasID = (flags & 0x01) != 0
        let hasLevel = (flags & 0x02) != 0
        let hasAdditional = (flags & 0x04) != 0
        var expected = 3
        if hasID { expected += 2 }
        if hasLevel { expected += 1 }
        if hasAdditional { expected += 1 }
        guard payload.count == expected else {
            return nil
        }
        let powerState = Int(payload[1])
            | Int(payload[2]) << 8
        let chargeState = (powerState >> 5) & 0x07
        let chargeLevel = (powerState >> 8) & 0x07
        var state: String?
        if chargeState == 1 {
            state = "charging"
        } else if chargeLevel == 2 {
            state = "low"
        } else if chargeLevel == 3 {
            state = "critical"
        }
        var percent: Int?
        if hasLevel {
            let index = 3 + (hasID ? 2 : 0)
            let value = payload[index]
            if value <= 100 { percent = Int(value) }
        }
        if percent == nil && state == nil { return nil }
        return (percent, state)
    }

    // MARK: Victron Energy — identity by design

    /// Victron's product advertisement (record
    /// 0x10, the vendor's published layout):
    /// model id, readout type, device class —
    /// and readings AES-encrypted under the
    /// device's own key, so the honest decode
    /// is identity: the device, its model and
    /// its class, never invented numbers.
    private static func victron(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting
                .manufacturerData[0x02E1],
              payload.count >= 8,
              payload[0] == 0x10
        else { return nil }
        let model = Int(payload[1])
            | Int(payload[2]) << 8
        let deviceClass = payload[4]
        let kind = deviceClass == 0x01
            ? L("Victron solar charger")
            : L("Victron Energy device")
        var details = [String(
            format: L("model 0x%04X, device class ")
                + "0x%02X", model, deviceClass)]
        details.append(L("readings are encrypted ")
            + L("under the device's own key — ")
            + L("identity only"))
        return Identification(kind: kind,
                              details: details,
                              specificity: 2)
    }

    // MARK: Mopeka — the tank sensors (OEM guide)

    /// Mopeka Pro tank sensors transmit under
    /// Nordic's company id (the OEM's own
    /// integration guide says so) — the gate
    /// is therefore triple: company 0x0059,
    /// the guide's exact length, and a
    /// hardware id in the documented set.
    /// Level height converts only for the
    /// bottom-up types, with the guide's
    /// per-medium coefficients; top-down
    /// types report the raw time-of-flight,
    /// since a height would need the tank.
    private static func mopeka(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting
                .manufacturerData[0x0059],
              payload.count == 10
        else { return nil }
        let hw = payload[0]
        let sensorType = hw & 0x7F
        let levelExtended = (hw & 0x80) != 0
        let names: [UInt8: String] = [
            0x03: L("Mopeka tank sensor (propane)"),
            0x04: L("Mopeka tank sensor (top-down)"),
            0x05: L("Mopeka tank sensor (water)"),
            0x08: L("Mopeka Pro+ tank sensor"),
            0x09: L("Mopeka Pro+ tank sensor"),
            0x0A: L("Mopeka TD-40 tank sensor"),
            0x0B: L("Mopeka TD-40 tank sensor"),
        ]
        guard let kind = names[sensorType]
        else { return nil }
        let volts = Double(payload[1] & 0x7F) / 32
        let battery = max(0, min(100, Int(
            (volts - 2.2) / 0.65 * 100)))
        let tempRaw = Int(payload[2] & 0x7F)
        let tempC = tempRaw - 40
        let levelField = Int(payload[3])
            | Int(payload[4]) << 8
        var levelUS = levelField & 0x3FFF
        if levelExtended { levelUS |= 0x4000 }
        let quality = (levelField >> 14) & 0x3
        var details: [String] = []
        let coeffs: [UInt8: (Double, Double, Double)] = [
            0x03: (0.573045, -0.002822, -0.00000535),
            0x08: (0.573045, -0.002822, -0.00000535),
            0x09: (0.573045, -0.002822, -0.00000535),
            0x05: (0.600592, -0.003124, -0.00001368),
        ]
        if let c = coeffs[sensorType] {
            let tt = Double(tempRaw)
            let mm = Double(levelUS)
                * (c.0 + c.1 * tt + c.2 * tt * tt)
            details.append(String(
                format: L("tank level ≈ %.0f mm"), mm))
        } else {
            details.append(String(format: L("level %@ µs (top-down)"), String(describing: levelUS)))
        }
        details.append(String(
            format: L("battery %.2f V (%d%%), ")
                + L("%d °C, reading quality %d of 3"),
            volts, battery, tempC, quality))
        return Identification(kind: kind,
                              details: details,
                              specificity: 3)
    }

    // MARK: TPMS — the clone wheel sensors

    /// The TPMS clone family squats on company
    /// 0x0001 with a fixed signature (EA CA at
    /// [1..2], a wheel byte 0x80–0x83, exact
    /// length). Identification, wheel, battery
    /// and the alarm flag are doubly
    /// documented; the pressure scaling is
    /// single-sourced, so pressures are NOT
    /// printed — a guessed number on a tire
    /// is worse than none.
    private static func tpmsClone(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting
                .manufacturerData[0x0001],
              payload.count == 16,
              payload[0] >= 0x80, payload[0] <= 0x83,
              payload[1] == 0xEA, payload[2] == 0xCA
        else { return nil }
        let wheel = Int(payload[0]) - 0x80 + 1
        var details = [String(format: L("wheel %@ sensor"), String(describing: wheel)),
                       String(format: L("battery %@%%"), String(describing: payload[14]))]
        if payload[15] == 1 {
            details.append(L("alarm: no pressure"))
        }
        return Identification(
            kind: L("TPMS wheel sensor"),
            details: details, specificity: 2)
    }

    private static func basBroadcast(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = serviceData(
                sighting, basService),
              let reading = basBroadcastReading(payload)
        else { return nil }
        var details: [String] = []
        if let percent = reading.percent {
            details.append("battery \(percent)% "
                + L("(Battery Service broadcast)"))
        }
        if let state = reading.state {
            details.append(L("battery ") + state)
        }
        return Identification(kind: L("Battery Service broadcaster"), details: details, specificity: 1)
    }

    // MARK: Inkbird & ThermoPro — name-gated families

    private static func inkbird(
        _ sighting: Sighting
    ) -> Identification? {
        guard let name = sighting.name?.lowercased(),
              name.hasPrefix("sps") || name.hasPrefix("tps"),
              let payload = sighting.manufacturerData
                .values.first(where: { $0.count == 9 })
        else { return nil }
        let rawTemp = Int16(bitPattern:
            UInt16(payload[0]) | UInt16(payload[1]) << 8)
        let temp = Double(rawTemp) / 100
        guard temp > -60, temp < 150 else { return nil }
        var details = [String(
            format: L("temperature %.2f °C"), temp)]
        let rawHumidity = UInt16(payload[2])
            | UInt16(payload[3]) << 8
        if rawHumidity != 0xFFFF, rawHumidity != 0 {
            details.append(String(
                format: L("humidity %.1f %%"),
                Double(rawHumidity) / 100))
        }
        if payload[7] <= 100 {
            details.append(String(format: L("battery %@%% (Inkbird)"), String(describing: payload[7])))
        }
        return Identification(kind: L("Inkbird thermo-hygrometer"), details: details, specificity: 3)
    }

    private static func thermoPro(
        _ sighting: Sighting
    ) -> Identification? {
        guard let name = sighting.name,
              ["TP350", "TP357", "TP358", "TP359",
               "TP393"].contains(
                where: { name.hasPrefix($0) }),
              let payload = sighting.manufacturerData
                .values.first(where: {
                    $0.count >= 6 && $0[0] == 0xC2 })
        else { return nil }
        let rawTemp = Int16(bitPattern:
            UInt16(payload[1]) | UInt16(payload[2]) << 8)
        var details = [String(
            format: L("temperature %.1f °C"),
            Double(rawTemp) / 10),
            String(format: L("humidity %@%%"), String(describing: payload[3]))]
        // The flag reads backwards: bit set means
        // the battery is fine.
        if (payload[4] & 0x02) == 0 {
            details.append(L("battery low (ThermoPro)"))
        }
        return Identification(kind: L("ThermoPro sensor"), details: details, specificity: 3)
    }

    // MARK: Aranet, SensorPush, Oral-B — appliances

    /// Aranet4 (company 0x0702, the maker's own
    /// frame): CO₂, temperature, pressure and
    /// humidity as fixed-point fields in the
    /// payload's second half, and the battery
    /// under a flag bit that is masked off, never
    /// read as part of the percentage.
    private static func aranet(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting.manufacturerData[
                0x0702],
              payload.count >= 16
        else { return nil }
        let co2 = Int(UInt16(payload[8])
            | UInt16(payload[9]) << 8)
        let rawTemp = Int16(bitPattern:
            UInt16(payload[10])
                | UInt16(payload[11]) << 8)
        let temp = Double(rawTemp) / 20.0
        let pressure = Double(
            UInt16(payload[12])
                | UInt16(payload[13]) << 8) / 10.0
        let humidity = Int(payload[14])
        let battery = Int(payload[15] & 0x7F)
        guard co2 >= 300, co2 <= 10000,
              temp >= -20, temp <= 60,
              pressure >= 300, pressure <= 1300,
              humidity <= 100, battery <= 100
        else { return nil }
        let details = [
            String(format: L("CO₂ %@ ppm"),
                   String(describing: co2)),
            String(format: L("temperature %.1f °C"),
                   temp),
            String(format: L("pressure %.1f hPa"),
                   pressure),
            String(format: L("humidity %.1f %%"),
                   Double(humidity)),
            String(format: L("battery %@%% (Aranet4)"),
                   String(describing: battery)),
        ]
        return Identification(kind: L("Aranet4 CO₂ monitor"), details: details, specificity: 3)
    }

    /// SensorPush HT.w: the whole reading is one
    /// packed 32-bit value behind a 0x04 head
    /// byte, fanned out by two moduli — the
    /// maker's company keying is ambiguous in the
    /// wild, so the frame is matched by shape
    /// across every manufacturer payload, the
    /// way AltBeacon is.
    private static func sensorPushHT(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting.manufacturerData
            .values.first(where: {
                $0.count == 5 && $0[0] == 0x04 })
        else { return nil }
        let v = UInt64(payload[1])
            | UInt64(payload[2]) << 8
            | UInt64(payload[3]) << 16
            | UInt64(payload[4]) << 24
        let temp = Double(v % 66001) * 0.0025 - 40
        let humidity = Double(v % 2640106001)
            / 66001.0 * 0.0025
        guard temp >= -40, temp <= 85,
              humidity >= 0, humidity <= 100
        else { return nil }
        let details = [
            String(format: L("temperature %.1f °C"),
                   temp),
            String(format: L("humidity %.1f %%"),
                   humidity),
        ]
        return Identification(kind: L("SensorPush HT.w sensor"), details: details, specificity: 3)
    }

    /// SensorPush HTP.xw: the same packing idea
    /// at 48 bits behind a 0x00 head byte — three
    /// moduli fan the one value out to
    /// temperature, humidity and pressure.
    private static func sensorPushHTP(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting.manufacturerData
            .values.first(where: {
                $0.count == 7 && $0[0] == 0x00 })
        else { return nil }
        let v = UInt64(payload[1])
            | UInt64(payload[2]) << 8
            | UInt64(payload[3]) << 16
            | UInt64(payload[4]) << 24
            | UInt64(payload[5]) << 32
            | UInt64(payload[6]) << 40
        let temp = Double(v % 72001) * 0.0025 - 40
        let humidity = Double(v % 2880112001)
            / 72001.0 * 0.0025
        let pressure = (Double(v % 273613520207001)
            / 2880112001.0 + 30000.0) / 100.0
        guard temp >= -40, temp <= 85,
              humidity >= 0, humidity <= 100,
              pressure >= 300, pressure <= 1250
        else { return nil }
        let details = [
            String(format: L("temperature %.1f °C"),
                   temp),
            String(format: L("humidity %.1f %%"),
                   humidity),
            String(format: L("pressure %.1f hPa"),
                   pressure),
        ]
        return Identification(kind: L("SensorPush HTP.xw sensor"), details: details, specificity: 3)
    }

    /// Oral-B toothbrush (company 0x00DC): the
    /// brush state byte is the identification —
    /// a payload whose state byte speaks none of
    /// the known states is not claimed as a
    /// toothbrush at all. Mode and sector words
    /// are carried only when known; the session
    /// duration rides only when it is running.
    private static func oralB(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting.manufacturerData[
                0x00DC],
              payload.count >= 9
        else { return nil }
        let states: [UInt8: String] = [
            0x01: L("initialising"), 0x02: L("idle"),
            0x03: L("running"), 0x04: L("charging"),
            0x73: L("sleeping"),
        ]
        guard let state = states[payload[3]]
        else { return nil }
        var details = [
            String(format: L("state %@"), state),
            String(format: L("pressure %@"),
                   String(describing: Int(payload[4]))),
        ]
        let seconds = Int(payload[5]) * 60
            + Int(payload[6])
        if seconds > 0 {
            details.append(String(
                format: L("duration %@ s"),
                String(describing: seconds)))
        }
        let modes: [UInt8: String] = [
            0x00: L("off"), 0x01: L("daily clean"),
            0x02: L("sensitive"), 0x03: L("massage"),
            0x04: L("whitening"), 0x05: L("deep clean"),
            0x06: L("tongue cleaning"),
            0x07: L("turbo"),
        ]
        if let mode = modes[payload[7]] {
            details.append(String(
                format: L("mode %@"), mode))
        }
        if payload[8] >= 1, payload[8] <= 8 {
            details.append(String(
                format: L("sector %@"),
                String(describing: Int(payload[8]))))
        }
        return Identification(kind: L("Oral-B toothbrush"), details: details, specificity: 3)
    }

    // MARK: Microsoft Connected Devices

    private static func msCDP(
        _ sighting: Sighting
    ) -> Identification? {
        guard let payload = sighting.manufacturerData[
                0x0006],
              payload.count >= 10,
              payload[0] == 0x01
        else { return nil }
        return Identification(kind: L("Windows / Android device"), details: [L("Microsoft Connected Devices ")
                + L("presence beacon — a device class ")
                + L("claim, no battery carried")], specificity: 1)
    }

    // MARK: - Batteries for the engine

    static func batteryReadings(
        _ sighting: Sighting
    ) -> [BatteryReading] {
        var readings: [BatteryReading] = []
        func stamp(_ reading: BatteryReading)
            -> BatteryReading {
            var reading = reading
            reading.observedAt = sighting.seenAt
            return reading
        }
        if let payload = serviceData(
            sighting, MoreDecoders.switchBotService),
           switchBotType(payload) != nil {
            readings.append(stamp(BatteryReading(
                component: "device",
                percent: Int(payload[2] & 0x7F),
                millivolts: nil, state: nil,
                source: "SwitchBot", observedAt: 0)))
        }
        if let payload = serviceData(
            sighting, estimoteService),
           let reading = estimoteBattery(payload) {
            readings.append(stamp(reading))
        }
        if let reading = xiaomiThermoBattery(sighting) {
            readings.append(stamp(reading))
        }
        if let payload = serviceData(
            sighting, qingpingService),
           payload.count >= 21, payload[1] == 0x09 {
            readings.append(stamp(BatteryReading(
                component: "device",
                percent: Int(payload[20] & 0x7F),
                millivolts: nil, state: nil,
                source: "Qingping", observedAt: 0)))
        }
        if bthomeV1Enabled,
           let payload = serviceData(
            sighting, bthomeV1Service),
           let objects = bthomeV1Objects(payload) {
            var state: String?
            if objects[0x15] == 1 { state = "low" }
            if objects[0x16] == 1 { state = "charging" }
            if objects[0x01] != nil
                || objects[0x0C] != nil
                || state != nil {
                readings.append(stamp(BatteryReading(
                    component: "device",
                    percent: objects[0x01],
                    millivolts: objects[0x0C],
                    state: state, source: L("BTHome v1"),
                    observedAt: 0)))
            }
        }
        if let payload = serviceData(
            sighting, basService),
           let reading = basBroadcastReading(payload) {
            readings.append(stamp(BatteryReading(
                component: "device",
                percent: reading.percent,
                millivolts: nil, state: reading.state,
                source: L("Battery Service"),
                observedAt: 0)))
        }
        if let name = sighting.name?.lowercased(),
           name.hasPrefix("sps") || name.hasPrefix("tps"),
           let payload = sighting.manufacturerData
            .values.first(where: { $0.count == 9 }),
           payload[7] <= 100 {
            readings.append(stamp(BatteryReading(
                component: "device",
                percent: Int(payload[7]),
                millivolts: nil, state: nil,
                source: "Inkbird", observedAt: 0)))
        }
        if let name = sighting.name,
           ["TP350", "TP357", "TP358", "TP359",
            "TP393"].contains(
            where: { name.hasPrefix($0) }),
           let payload = sighting.manufacturerData
            .values.first(where: {
                $0.count >= 6 && $0[0] == 0xC2 }),
           (payload[4] & 0x02) == 0 {
            readings.append(stamp(BatteryReading(
                component: "device", percent: nil,
                millivolts: nil, state: "low",
                source: "ThermoPro", observedAt: 0)))
        }
        if let payload = sighting.manufacturerData[
            0x0702],
           payload.count >= 16 {
            let battery = Int(payload[15] & 0x7F)
            if battery <= 100 {
                readings.append(stamp(BatteryReading(
                    component: "device",
                    percent: battery,
                    millivolts: nil, state: nil,
                    source: "Aranet4", observedAt: 0)))
            }
        }
        return readings
    }
}
