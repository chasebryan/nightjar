import Foundation

/// One battery, as a broadcast reported it — a
/// percentage, a voltage, or a word ("low"), with
/// the component it belongs to and the format that
/// said it. Nothing here is ever inferred into a
/// number the broadcast did not carry: estimates
/// live in the forecaster and are labelled there.
struct BatteryReading: Equatable {
    var component: String       // "device", "left", "right", "case"
    var percent: Int?
    var millivolts: Int?
    var state: String?          // "charging", "full", "low"…
    var source: String          // "AirPods", "BTHome v2"…
    var observedAt: TimeInterval

    var summary: String {
        var head = component == "device"
            ? "battery" : "\(component) battery"
        if let percent = percent {
            head += " \(percent)%"
        } else if let millivolts = millivolts {
            head += " \(millivolts) mV"
        }
        if let state = state {
            head += percent == nil && millivolts == nil
                ? " \(state)" : ", \(state)"
        }
        return head + " (\(source))"
    }
}

/// What repeated battery samples can honestly say:
/// a drain rate, and — only when the trend is
/// steady enough — a time-to-empty RANGE. Least
/// squares over the samples; the range widens
/// with the scatter, and when the scatter swallows
/// the slope the forecaster stays silent rather
/// than print a confident lie.
enum BatteryForecaster {
    struct Forecast {
        var ratePerHour: Double     // negative = draining
        var etaLowHours: Double?
        var etaHighHours: Double?
        var text: String
    }

    private struct Fit {
        var slopePerHour: Double
        var slopeError: Double
        var spanHours: Double
    }

    private static func fit(
        _ samples: [(at: TimeInterval, value: Double)]
    ) -> Fit? {
        let sorted = samples.sorted { $0.at < $1.at }
        guard sorted.count >= 3,
              let first = sorted.first,
              let last = sorted.last,
              last.at - first.at >= 900 else { return nil }
        let n = Double(sorted.count)
        let meanT = sorted.map { $0.at }.reduce(0, +) / n
        let meanV = sorted.map { $0.value }.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0
        for sample in sorted {
            let dt = sample.at - meanT
            sxx += dt * dt
            sxy += dt * (sample.value - meanV)
        }
        guard sxx > 0 else { return nil }
        let slopePerSecond = sxy / sxx
        var residuals = 0.0
        for sample in sorted {
            let predicted = meanV
                + slopePerSecond * (sample.at - meanT)
            let error = sample.value - predicted
            residuals += error * error
        }
        let variance = residuals / max(1, n - 2)
        let errorPerSecond = (variance / sxx).squareRoot()
        return Fit(slopePerHour: slopePerSecond * 3600,
                   slopeError: errorPerSecond * 3600,
                   spanHours: (last.at - first.at) / 3600)
    }

    private static func hoursText(_ hours: Double) -> String {
        if hours < 2 {
            return "\(Int((hours * 60).rounded())) min"
        }
        if hours < 48 {
            return String(format: "%.1f h", hours)
        }
        return "\(Int((hours / 24).rounded())) d"
    }

    static func percentForecast(
        samples: [(at: TimeInterval, percent: Int)]
    ) -> Forecast? {
        let values = samples.map {
            (at: $0.at, value: Double($0.percent)) }
        guard let fit = fit(values),
              let last = samples.sorted(by: { $0.at < $1.at }).last
        else { return nil }
        if fit.slopePerHour >= -0.25 {
            guard fit.spanHours >= 1 else { return nil }
            return Forecast(
                ratePerHour: fit.slopePerHour, etaLowHours: nil,
                etaHighHours: nil,
                text: "battery holding — no drain "
                    + "measurable over "
                    + hoursText(fit.spanHours))
        }
        // Noise swallows the slope: no ETA.
        guard fit.slopeError < abs(fit.slopePerHour) * 0.9
        else { return nil }
        let rate = abs(fit.slopePerHour)
        let low = Double(last.percent) / (rate + fit.slopeError)
        let high = Double(last.percent)
            / max(0.05, rate - fit.slopeError)
        return Forecast(
            ratePerHour: fit.slopePerHour,
            etaLowHours: low, etaHighHours: high,
            text: String(format: "draining ≈%.1f %%/h — ",
                         rate)
                + "empty in roughly \(hoursText(low))"
                + "–\(hoursText(high)) at this rate")
    }

    static func voltageForecast(
        samples: [(at: TimeInterval, millivolts: Int)]
    ) -> Forecast? {
        let values = samples.map {
            (at: $0.at, value: Double($0.millivolts)) }
        guard let fit = fit(values) else { return nil }
        if fit.slopePerHour <= -5 {
            return Forecast(
                ratePerHour: fit.slopePerHour,
                etaLowHours: nil, etaHighHours: nil,
                text: String(format: "voltage falling "
                             + "≈%.0f mV/h", abs(fit.slopePerHour)))
        }
        if fit.slopePerHour >= 5 {
            return Forecast(
                ratePerHour: fit.slopePerHour,
                etaLowHours: nil, etaHighHours: nil,
                text: "voltage rising — charging, or a "
                    + "fresh battery")
        }
        guard fit.spanHours >= 1 else { return nil }
        return Forecast(
            ratePerHour: fit.slopePerHour,
            etaLowHours: nil, etaHighHours: nil,
            text: "voltage steady over "
                + hoursText(fit.spanHours))
    }
}

/// The intelligence layer over every decoder the
/// house owns. Classification picks ONE kind per
/// sighting; this layer reads the same sighting
/// whole — every channel testifying at once — and
/// returns what classification's winner-takes-all
/// shape would drop: batteries from every format
/// present, the capabilities the service list
/// implies, the broadcast-only flag, and an honest
/// reading of an unknown payload's shape. DeviceRow
/// merges it into the record, so Listen, the
/// dossier, Skelli and the SIGINT registry all see
/// the same enriched evidence.
enum DecoderEngine {

    struct Analysis {
        var batteries: [BatteryReading] = []
        var evidence: [String] = []
        /// Readings of an unknown payload's shape —
        /// the row surfaces these only when no real
        /// decoder named the device.
        var shape: [String] = []
    }

    static func analyze(_ sighting: Sighting) -> Analysis {
        var out = Analysis()
        out.batteries = batteryReadings(sighting)
        out.evidence = capabilities(sighting)
        // Eddystone-TLM's counters are the air's
        // own bookkeeping: advertisements since
        // power-up, and the uptime they span.
        if let frame = Services.decodeEddystone(
            serviceData(sighting, Services.eddystone)
                ?? []),
           frame.frameType == 0x20,
           let count = frame.advCount,
           let uptime = frame.uptimeS {
            let hours = uptime / 3600
            out.evidence.append(hours >= 1
                ? "beacon bookkeeping: \(count) "
                    + "advertisements over \(hours) h "
                    + "of uptime"
                : "beacon bookkeeping: \(count) "
                    + "advertisements since power-up")
        }
        if sighting.isConnectable == false {
            out.evidence.append(
                "broadcast only — does not accept "
                + "connections")
        }
        out.shape = payloadShape(sighting)
        return out
    }

    // MARK: - Batteries, from every format present

    static func batteryReadings(
        _ sighting: Sighting
    ) -> [BatteryReading] {
        var readings: [BatteryReading] = []
        let at = sighting.seenAt

        // Apple: AirPods component batteries and
        // the Find My word, straight from the
        // Continuity state structs.
        if let apple = sighting.manufacturerData[
            Continuity.appleCompanyID] {
            for message in Continuity.parse(apple)
            where message.type == 0x07 {
                if let pods = Continuity
                    .decodeAirPods(message) {
                    func add(_ component: String,
                             _ percent: Int?,
                             _ charging: Bool) {
                        guard percent != nil || charging
                        else { return }
                        readings.append(BatteryReading(
                            component: component,
                            percent: percent,
                            millivolts: nil,
                            state: charging
                                ? "charging" : nil,
                            source: "AirPods",
                            observedAt: at))
                    }
                    add("left", pods.leftBattery,
                        pods.leftCharging)
                    add("right", pods.rightBattery,
                        pods.rightCharging)
                    add("case", pods.caseBattery,
                        pods.caseCharging)
                }
            }
            if let findMy = Continuity.parseFindMy(apple) {
                readings.append(BatteryReading(
                    component: "device", percent: nil,
                    millivolts: nil, state: findMy.battery,
                    source: "Find My", observedAt: at))
            }
            // Instant Hotspot reports the phone's
            // own battery as a plain percentage.
            for message in Continuity.parse(apple)
            where message.type == 0x0E {
                if let source = Continuity
                    .decodeTetheringSource(message),
                   let percent = source.battery {
                    readings.append(BatteryReading(
                        component: "device",
                        percent: percent, millivolts: nil,
                        state: nil, source: "Instant Hotspot",
                        observedAt: at))
                }
            }
        }

        // Eddystone-TLM carries the beacon's voltage.
        if let frame = Services.decodeEddystone(
            serviceData(sighting, Services.eddystone)
                ?? []),
           frame.frameType == 0x20,
           let millivolts = frame.batteryMv {
            readings.append(BatteryReading(
                component: "device", percent: nil,
                millivolts: millivolts, state: nil,
                source: "Eddystone-TLM", observedAt: at))
        }

        // RuuviTag: both formats carry millivolts.
        if let payload = sighting.manufacturerData[
            MoreDecoders.ruuviCompany],
           MoreDecoders.decodeRuuvi(payload) != nil {
            if payload[0] == 0x05, payload.count >= 15 {
                let power = Int(payload[13]) << 8
                    | Int(payload[14])
                if (power >> 5) != 2047 {
                    readings.append(BatteryReading(
                        component: "device", percent: nil,
                        millivolts: (power >> 5) + 1600,
                        state: nil, source: "RuuviTag",
                        observedAt: at))
                }
            } else if payload[0] == 0x03,
                      payload.count >= 14 {
                readings.append(BatteryReading(
                    component: "device", percent: nil,
                    millivolts: Int(payload[12]) << 8
                        | Int(payload[13]),
                    state: nil, source: "RuuviTag",
                    observedAt: at))
            }
        }

        // Govee: a percentage, gated by its decoder.
        if let payload = sighting.manufacturerData[
            MoreDecoders.goveeCompany],
           MoreDecoders.decodeGovee(payload) != nil {
            readings.append(BatteryReading(
                component: "device",
                percent: Int(payload[4] & 0x7F),
                millivolts: nil,
                state: (payload[4] & 0x80) != 0
                    ? "sensor error" : nil,
                source: "Govee", observedAt: at))
        }

        // Xiaomi MiBeacon: the battery object,
        // walked out of the plaintext frame.
        if let payload = serviceData(
            sighting, MoreDecoders.xiaomiService),
           let percent = miBeaconBattery(payload) {
            readings.append(BatteryReading(
                component: "device", percent: percent,
                millivolts: nil, state: nil,
                source: "MiBeacon", observedAt: at))
        }

        // BTHome v2: object 0x01, plaintext only.
        if let payload = serviceData(
            sighting, MoreDecoders.btHomeService),
           let percent = btHomeBattery(payload) {
            readings.append(BatteryReading(
                component: "device", percent: percent,
                millivolts: nil, state: nil,
                source: "BTHome v2", observedAt: at))
        }
        // The expansion batch's formats, read the
        // same way.
        readings += ExpansionDecoders
            .batteryReadings(sighting)
        return readings
    }

    /// MiBeacon's battery object (0x100A), reached
    /// by the same frame walk its decoder uses:
    /// frame control, optional MAC, optional
    /// capability, then length-prefixed objects.
    /// Encrypted frames yield nothing.
    private static func miBeaconBattery(
        _ payload: [UInt8]
    ) -> Int? {
        guard payload.count >= 5 else { return nil }
        let frameControl = Int(payload[0])
            | Int(payload[1]) << 8
        if (frameControl & 0x0008) != 0 { return nil }
        var index = 5
        if (frameControl & 0x0010) != 0 { index += 6 }
        if (frameControl & 0x0020) != 0 {
            guard payload.count > index else { return nil }
            let capability = payload[index]
            index += 1
            if (capability & 0x20) != 0 { index += 2 }
        }
        guard (frameControl & 0x0040) != 0 else {
            return nil
        }
        while index + 3 <= payload.count {
            let objectID = Int(payload[index])
                | Int(payload[index + 1]) << 8
            let length = Int(payload[index + 2])
            let start = index + 3
            guard start + length <= payload.count
            else { return nil }
            if objectID == 0x100A, length == 1 {
                return Int(payload[start])
            }
            index = start + length
        }
        return nil
    }

    /// BTHome v2's battery object (0x01).
    private static func btHomeBattery(
        _ payload: [UInt8]
    ) -> Int? {
        guard let info = payload.first,
              (info & 0xE0) == 0x40,
              (info & 0x01) == 0 else { return nil }
        var index = 1
        if (info & 0x02) != 0 { index += 6 }
        while index < payload.count {
            let objectID = payload[index]
            guard let length = MoreDecoders
                .btHomeObjectLengths[objectID],
                  index + 1 + length <= payload.count
            else { return nil }
            if objectID == 0x01 {
                return Int(payload[index + 1])
            }
            index += 1 + length
        }
        return nil
    }

    // MARK: - Capabilities the service list implies

    private static let capabilityPhrases:
        [UInt16: String] = [
        0x180F: "carries a battery service — its "
            + "level reads on connection, not "
            + "from the air",
        0x180D: "heart-rate capable",
        0x1808: "glucose capable",
        0x1810: "blood-pressure capable",
        0x1822: "pulse-oximeter capable",
        0x1809: "health-thermometer capable",
        0x181A: "environmental-sensing capable",
        0x181B: "body-composition capable",
        0x181D: "weight-scale capable",
        0x1812: "a human-interface device "
            + "(keyboard, mouse, controller)",
        0x180A: "carries device information",
        0x1805: "carries the current time",
        0x1815: "automation I/O capable",
        0x1816: "cycling speed and cadence",
        0x1814: "running speed and cadence",
        0x1818: "cycling-power capable",
        0x1819: "location and navigation capable",
        0x1826: "fitness-machine capable",
        0x1827: "a Bluetooth Mesh node "
            + "(provisioning)",
        0x1828: "a Bluetooth Mesh proxy",
        0x1811: "alert-notification capable",
        0x181C: "carries user data",
    ]

    private static let leAudioServices: Set<UInt16> = [
        0x184E, 0x184F, 0x1850, 0x1852, 0x1853,
        0x1854, 0x1856,
    ]

    static func capabilities(
        _ sighting: Sighting
    ) -> [String] {
        var shorts = Set<UInt16>()
        for uuid in sighting.serviceUUIDs
            + Array(sighting.serviceData.keys) {
            if let value = Services.short(uuid) {
                shorts.insert(value)
            }
        }
        var lines: [String] = []
        for id in shorts.sorted()
        where capabilityPhrases[id] != nil {
            lines.append(capabilityPhrases[id]!)
        }
        if !shorts.isDisjoint(with: leAudioServices) {
            lines.append("carries LE Audio services")
        }
        return Array(lines.prefix(3))
    }

    // MARK: - An unknown payload's shape

    /// Entropy and printability — the honest
    /// residue when no decoder knows the format:
    /// near-random bytes are CONSISTENT WITH
    /// encrypted or rotating data (never crowned
    /// as either), and a printable payload is
    /// quoted as what it plainly is.
    static func payloadShape(
        _ sighting: Sighting
    ) -> [String] {
        var payloads: [[UInt8]] = Array(
            sighting.manufacturerData.values)
        payloads += Array(sighting.serviceData.values)
        guard let payload = payloads
            .max(by: { $0.count < $1.count }),
              payload.count >= 8 else { return [] }
        let entropy = shannonEntropy(payload)
        if entropy > 7.0 {
            return ["payload \(payload.count) bytes, "
                + "near-random — consistent with "
                + "encrypted or rotating data; the "
                + "contents are not readable from "
                + "the air"]
        }
        if let run = longestPrintableRun(payload),
           run.count >= 4 {
            return ["payload carries the text "
                + "'\(run)'"]
        }
        return ["payload \(payload.count) bytes, "
            + "no known format"]
    }

    static func shannonEntropy(_ bytes: [UInt8]) -> Double {
        guard !bytes.isEmpty else { return 0 }
        var counts: [UInt8: Int] = [:]
        for byte in bytes { counts[byte, default: 0] += 1 }
        let total = Double(bytes.count)
        var entropy = 0.0
        for count in counts.values {
            let p = Double(count) / total
            entropy -= p * log2(p)
        }
        return entropy
    }

    private static func longestPrintableRun(
        _ bytes: [UInt8]
    ) -> String? {
        var best = ""
        var current = ""
        for byte in bytes {
            if byte >= 0x20, byte < 0x7F {
                current.append(Character(
                    UnicodeScalar(byte)))
            } else {
                if current.count > best.count {
                    best = current
                }
                current = ""
            }
        }
        if current.count > best.count { best = current }
        return best.isEmpty ? nil : best
    }

    // MARK: - Helpers

    private static func serviceData(
        _ sighting: Sighting, _ id: UInt16
    ) -> [UInt8]? {
        for (uuid, payload) in sighting.serviceData
        where Services.short(uuid) == id {
            return payload
        }
        return nil
    }

    /// A cheap, stable fingerprint of the
    /// advertisement's SHAPE — which channels are
    /// present and how long each payload runs, not
    /// the values (a sensor's values change every
    /// packet; its shape changes when the device
    /// changes what it IS saying). The row compares
    /// it across sightings to count shape changes
    /// within the session. A fingerprint of form,
    /// never an identity.
    static func payloadSignature(
        _ sighting: Sighting
    ) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ byte: UInt8) {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        for company in sighting.manufacturerData
            .keys.sorted() {
            mix(UInt8(company & 0xFF))
            mix(UInt8(company >> 8))
            mix(UInt8(clamping: sighting
                .manufacturerData[company]?.count ?? 0))
        }
        for uuid in sighting.serviceData.keys.sorted() {
            for byte in uuid.utf8 { mix(byte) }
            mix(UInt8(clamping: sighting
                .serviceData[uuid]?.count ?? 0))
        }
        for uuid in sighting.serviceUUIDs.sorted() {
            for byte in uuid.utf8 { mix(byte) }
        }
        return hash
    }
}
