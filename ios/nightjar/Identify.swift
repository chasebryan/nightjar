import Foundation

/// What kind of thing a sighting is — a port of `classify()` in
/// `nightjar/identify.py`, same channels in the same order: Apple's
/// Continuity chain, then service UUIDs and service data, then other
/// makers' manufacturer data, then the bare name.
struct Classification {
    static let rankUnknown = 0
    static let rankFamily = 10
    static let rankFamilyHint = 15
    static let rankSubfamily = 20
    static let rankProduct = 30

    var kind: String = "Unknown device"
    var details: [String] = []
    var rank: Int = Classification.rankUnknown
    var trackerShaped: Bool = false
    var rotatingPhone: Bool = false
    /// A name the broadcast itself supplies (a drone's Remote ID serial),
    /// shown when the advertisement carries no local name.
    var preferredLabel: String? = nil

    private static func rankFor(specificity: Int) -> Int {
        switch specificity {
        case 3: return rankProduct
        case 2: return rankSubfamily
        default: return rankFamily
        }
    }

    static func classify(_ sighting: Sighting) -> Classification {
        // Every channel testifies; the rank ladder
        // arbitrates. The old waterfall returned at
        // the first match — an Apple Continuity hit
        // meant the service UUIDs that might name
        // the PRODUCT were never consulted, and
        // evidence from the other channels was
        // thrown away. Now all candidates are
        // gathered, the highest rank wins the kind
        // (ties go to the earliest channel, as the
        // waterfall had it), and the details of
        // every candidate within one rung of the
        // winner are merged in — one device, all
        // its evidence.
        var candidates: [Classification] = []

        if let apple = sighting.manufacturerData[Continuity.appleCompanyID], !apple.isEmpty {
            let ident = Continuity.identifyApple(apple)
            var rankValue = rankFor(specificity: ident.specificity)
            if ident.kind == "Apple device (Nearby Info)" {
                rankValue = rankFamilyHint
            }
            let tracker = ident.findMy?.separated ?? false
            candidates.append(Classification(kind: ident.kind, details: ident.details, rank: rankValue,
                                  trackerShaped: tracker, rotatingPhone: false))
        }

        if let more = MoreDecoders.identify(sighting) {
            candidates.append(Classification(kind: more.kind, details: more.details,
                                  rank: rankFor(specificity: more.specificity),
                                  trackerShaped: more.trackerShaped,
                                  rotatingPhone: more.rotatingPhone,
                                  preferredLabel: more.preferredLabel))
        }

        // Services speaks once, at the rank its
        // specificity earns — full standing at
        // subfamily or better; below that, the
        // family-rank leftover the waterfall fell
        // back to (which never carried the tracker
        // or rotation flags, and still does not).
        let service = Services.identify(serviceUUIDs: sighting.serviceUUIDs,
                                        serviceData: sighting.serviceData)
        if let service = service {
            if service.specificity >= 2 {
                candidates.append(Classification(kind: service.kind, details: service.details,
                                      rank: rankFor(specificity: service.specificity),
                                      trackerShaped: service.trackerShaped,
                                      rotatingPhone: service.rotatingPhone,
                                      preferredLabel: service.preferredLabel))
            } else {
                candidates.append(Classification(kind: service.kind, details: service.details,
                                      rank: rankFamily, trackerShaped: false, rotatingPhone: false,
                                      preferredLabel: service.preferredLabel))
            }
        }

        if let vendor = Vendors.identify(sighting.manufacturerData) {
            candidates.append(Classification(kind: vendor.kind, details: vendor.details,
                                  rank: rankFor(specificity: vendor.specificity),
                                  trackerShaped: false, rotatingPhone: false))
        }

        // Round 2's recognition floor, still behind
        // its own hook on purpose: inside the early
        // MoreDecoders step it would answer at family
        // rank before Services' decoders and Vendors
        // ever ran (a DJI drone would lose its Remote
        // ID label to "DJI device"). Under arbitration
        // its rank is capped below subfamily, so it
        // can still only ever beat the family floor,
        // the bare name, and "unknown" — never a real
        // decoder's product or subfamily reading.
        if let late = MoreDecoders.lateIdentify(sighting) {
            candidates.append(Classification(kind: late.kind, details: late.details,
                                  rank: min(rankFor(specificity: late.specificity),
                                             rankFamilyHint),
                                  trackerShaped: late.trackerShaped,
                                  rotatingPhone: late.rotatingPhone,
                                  preferredLabel: late.preferredLabel))
        }

        if sighting.name != nil {
            candidates.append(Classification(kind: "Named device"))
        }
        guard let winnerIndex = candidates.indices.max(
            by: { candidates[$0].rank < candidates[$1].rank })
        else { return Classification() }
        let winner = candidates[winnerIndex]
        // Merge the evidence: the winner's details,
        // then any detail from a candidate at the
        // winning rank or one rung below it, in
        // channel order, without repeats.
        let rungs = [rankUnknown, rankFamily,
                     rankFamilyHint, rankSubfamily,
                     rankProduct]
        let mergeFloor = rungs.filter { $0 < winner.rank }
            .max() ?? winner.rank
        var merged = winner.details
        for (index, candidate) in candidates.enumerated()
        where index != winnerIndex
            && candidate.rank >= mergeFloor {
            for line in candidate.details
            where !merged.contains(line) {
                merged.append(line)
            }
        }
        var result = winner
        result.details = merged
        if result.preferredLabel == nil {
            result.preferredLabel = candidates
                .compactMap { $0.preferredLabel }.first
        }
        return result
    }
}

/// One address as the live list shows it.
struct DeviceRow: Identifiable {
    let id: String  // the address
    var name: String?
    var preferredLabel: String?
    var kind: String = "Unknown device"
    var details: [String] = []
    var rank: Int = Classification.rankUnknown
    var trackerShaped: Bool = false
    var rssiLast: Int?
    var rssiClosest: Int?
    var rssiHistory: [Int] = []
    var firstSeen: TimeInterval
    var lastSeen: TimeInterval
    var sightings: Int = 0
    var makers: Set<String> = []
    /// Exponentially smoothed RSSI — the stable strength the
    /// list orders by, so positions reflect the perimeter
    /// instead of per-packet jitter.
    var rssiSmooth: Double?
    var txPowerLast: Int?
    var serviceUUIDs: [String] = []
    var rotatingAddress: Bool = false
    /// Flare: this advertiser's FFF0 service data matched the
    /// keyed rotating token — a holder of the pairing key is
    /// (or was, this session) in radio range. Recognition, not
    /// identity: the address rotates and the token expires.
    var flare = false
    var flareLastSeen: TimeInterval?
    /// The decoder engine's readings, merged from
    /// every sighting: batteries by component,
    /// capability and shape evidence, and the
    /// samples the battery forecaster works from.
    private(set) var batteries: [BatteryReading] = []
    private(set) var analysisEvidence: [String] = []
    private(set) var payloadChanges = 0
    var batteryPercentSamples:
        [(at: TimeInterval, percent: Int)] = []
    var batteryVoltageSamples:
        [(at: TimeInterval, millivolts: Int)] = []
    private var lastPayloadSignature: UInt64 = 0
    private var sightingIntervals: [TimeInterval] = []
    private(set) var connectable: Bool?

    static let historyCap = 24

    init(sighting: Sighting) {
        id = sighting.address
        firstSeen = sighting.seenAt
        lastSeen = sighting.seenAt
        observe(sighting)
    }

    mutating func observe(_ sighting: Sighting) {
        // Cadence and shape, measured before the
        // bookkeeping below moves the landmarks.
        if sightings > 0, sighting.seenAt > lastSeen {
            sightingIntervals.append(
                sighting.seenAt - lastSeen)
            if sightingIntervals.count > 12 {
                sightingIntervals.removeFirst(
                    sightingIntervals.count - 12)
            }
        }
        if let value = sighting.isConnectable {
            connectable = value
        }
        sightings += 1
        firstSeen = min(firstSeen, sighting.seenAt)
        lastSeen = max(lastSeen, sighting.seenAt)
        if let name = sighting.name { self.name = name }
        if let rssi = sighting.rssi {
            rssiLast = rssi
            rssiClosest = max(rssiClosest ?? rssi, rssi)
            if let smooth = rssiSmooth {
                rssiSmooth = smooth + 0.35 * (Double(rssi) - smooth)
            } else {
                rssiSmooth = Double(rssi)
            }
            rssiHistory.append(rssi)
            if rssiHistory.count > DeviceRow.historyCap {
                rssiHistory.removeFirst(rssiHistory.count - DeviceRow.historyCap)
            }
        }
        for company in sighting.manufacturerData.keys {
            makers.insert(Vendors.companyName(company))
        }
        if let tx = sighting.txPower { txPowerLast = tx }
        for uuid in sighting.serviceUUIDs
        where !serviceUUIDs.contains(uuid) {
            if serviceUUIDs.count < 16 { serviceUUIDs.append(uuid) }
        }
        // The engine reads the whole sighting —
        // batteries and capabilities from every
        // channel at once — before classification
        // picks its one kind.
        let analysis = DecoderEngine.analyze(sighting)
        for reading in analysis.batteries {
            batteries.removeAll {
                $0.component == reading.component
                    && $0.source == reading.source
            }
            batteries.append(reading)
            if reading.component == "device" {
                if let percent = reading.percent,
                   batteryPercentSamples.last?.percent
                       != percent
                    || sighting.seenAt
                        - (batteryPercentSamples.last?.at
                           ?? 0) > 600 {
                    batteryPercentSamples.append((
                        at: sighting.seenAt,
                        percent: percent))
                    if batteryPercentSamples.count > 24 {
                        batteryPercentSamples.removeFirst(
                            batteryPercentSamples.count - 24)
                    }
                }
                if let millivolts = reading.millivolts,
                   batteryVoltageSamples.last?.millivolts
                       != millivolts
                    || sighting.seenAt
                        - (batteryVoltageSamples.last?.at
                           ?? 0) > 600 {
                    batteryVoltageSamples.append((
                        at: sighting.seenAt,
                        millivolts: millivolts))
                    if batteryVoltageSamples.count > 24 {
                        batteryVoltageSamples.removeFirst(
                            batteryVoltageSamples.count - 24)
                    }
                }
            }
        }
        for line in analysis.evidence
        where !analysisEvidence.contains(line) {
            analysisEvidence.append(line)
        }
        if analysisEvidence.count > 8 {
            analysisEvidence = Array(
                analysisEvidence.suffix(8))
        }
        let signature = DecoderEngine
            .payloadSignature(sighting)
        if lastPayloadSignature != 0,
           signature != lastPayloadSignature {
            payloadChanges += 1
        }
        lastPayloadSignature = signature
        let classification = Classification.classify(sighting)
        // One guard for all three: a weaker sighting
        // may not overwrite a stronger reading's
        // kind, its label, or — as it silently
        // could until now — the details behind the
        // kind, leaving a confident name standing
        // on evidence from a worse look.
        let won = classification.rank >= rank
            || rank == Classification.rankUnknown
        if won {
            kind = classification.kind
            rank = classification.rank
        }
        if won, let label = classification.preferredLabel {
            preferredLabel = label
        }
        if won, !classification.details.isEmpty {
            details = classification.details
        }
        trackerShaped = trackerShaped || classification.trackerShaped
        rotatingAddress = rotatingAddress
            || classification.rotatingPhone
        // The engine's evidence is additive truth:
        // it merges whatever the kind contest
        // decided, because a device is everything
        // it said, not only its winning label.
        var extras = analysisEvidence
        extras += batteries.map { $0.summary }
        if classification.rank
            <= Classification.rankFamilyHint {
            extras += analysis.shape
        }
        if payloadChanges > 0 {
            extras.append("advertisement shape "
                + "changed \(payloadChanges)× this "
                + "session")
        }
        for line in extras where !details.contains(line) {
            details.append(line)
        }
        if details.count > 14 {
            details = Array(details.prefix(14))
        }
        // Flare recognition: only checked when a pairing key
        // exists, and only against FFF0 service data — three
        // HMACs against the neighboring windows.
        if let key = KnockKeyStore.key {
            for (uuid, bytes) in sighting.serviceData
            where Services.short(uuid) == 0xFFF0 {
                if Flare.matches(Data(bytes), key: key) {
                    if !flare {
                        Journal.log(
                            "listen", "flare",
                            "a flare answered — a holder of the "
                            + "pairing key is in radio range "
                            + "(address \(id))")
                    }
                    flare = true
                    flareLastSeen = sighting.seenAt
                }
            }
        }
    }

    /// What to call it: the advertised name, else a label the broadcast
    /// supplies (a drone's serial), else the decoded kind.
    var label: String { return name ?? preferredLabel ?? kind }

    /// Approaching / receding / steady, from the last few samples.
    var trend: String? {
        guard rssiHistory.count >= 6 else { return nil }
        let mid = rssiHistory.count / 2
        let older = Double(rssiHistory[..<mid].reduce(0, +)) / Double(mid)
        let younger = Double(rssiHistory[mid...].reduce(0, +)) / Double(rssiHistory.count - mid)
        let delta = younger - older
        if delta > 3 { return "approaching" }
        if delta < -3 { return "receding" }
        return "steady"
    }

    var trendArrow: String {
        switch trend {
        case "approaching": return "▲"
        case "receding": return "▼"
        case "steady": return "●"
        default: return ""
        }
    }

    var rangeBand: String {
        guard let rssi = rssiLast else { return "?" }
        if rssi >= -55 { return "immediate" }
        if rssi >= -70 { return "near" }
        if rssi >= -85 { return "far" }
        return "faint"
    }

    /// Rough range from the smoothed RSSI and the advertised
    /// transmit power (free-space falloff) — a guide for the
    /// eye, not a measurement. Devices that don't advertise
    /// TX power are read against the usual −59 dBm reference.
    var distanceMeters: Double? {
        guard let smooth = rssiSmooth else { return nil }
        let tx = Double(txPowerLast ?? -59)
        return pow(10, (tx - smooth) / 20)
    }

    /// The headline battery, when any format
    /// reported one.
    var batterySummary: String? {
        batteries.first?.summary
    }

    /// The one-line story for lists: the kind,
    /// then the most telling fact — a battery
    /// first, then the strongest detail.
    var subtitleLine: String {
        if let battery = batterySummary {
            return "\(kind) · \(battery)"
        }
        if let first = details.first {
            return "\(kind) · \(first)"
        }
        return kind
    }

    /// The forecaster's word on the device
    /// battery: a drain rate and, when the trend
    /// earns it, a time-to-empty range.
    var batteryForecastText: String? {
        if let forecast = BatteryForecaster
            .percentForecast(
                samples: batteryPercentSamples) {
            return forecast.text
        }
        return BatteryForecaster.voltageForecast(
            samples: batteryVoltageSamples)?.text
    }

    /// The advertising cadence, once enough
    /// intervals exist to read: a steady period,
    /// or an irregular one honestly named.
    var cadenceText: String? {
        guard sightingIntervals.count >= 4 else {
            return nil
        }
        let sorted = sightingIntervals.sorted()
        let median = sorted[sorted.count / 2]
        let low = sorted[sorted.count / 4]
        let high = sorted[(3 * sorted.count) / 4]
        let period = median < 10
            ? String(format: "%.1f s", median)
            : "\(Int(median.rounded())) s"
        if high - low > median * 0.6 {
            return "irregular cadence — about every "
                + period + " between bursts"
        }
        return "advertises about every " + period
    }

    /// How long the device has been in earshot this session.
    var dwell: TimeInterval { return max(0, lastSeen - firstSeen) }

    var sightingsPerMinute: Double {
        guard dwell >= 10 else { return 0 }
        return Double(sightings) / (dwell / 60)
    }

    func age(now: TimeInterval) -> TimeInterval { return max(0, now - lastSeen) }
}
