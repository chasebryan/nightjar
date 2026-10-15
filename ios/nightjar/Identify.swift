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
        if let apple = sighting.manufacturerData[Continuity.appleCompanyID], !apple.isEmpty {
            let ident = Continuity.identifyApple(apple)
            var rankValue = rankFor(specificity: ident.specificity)
            if ident.kind == "Apple device (Nearby Info)" {
                rankValue = rankFamilyHint
            }
            let tracker = ident.findMy?.separated ?? false
            return Classification(kind: ident.kind, details: ident.details, rank: rankValue,
                                  trackerShaped: tracker, rotatingPhone: false)
        }

        let service = Services.identify(serviceUUIDs: sighting.serviceUUIDs,
                                        serviceData: sighting.serviceData)
        if let service = service, service.specificity >= 2 {
            return Classification(kind: service.kind, details: service.details,
                                  rank: rankFor(specificity: service.specificity),
                                  trackerShaped: service.trackerShaped,
                                  rotatingPhone: service.rotatingPhone,
                                  preferredLabel: service.preferredLabel)
        }

        if let vendor = Vendors.identify(sighting.manufacturerData) {
            return Classification(kind: vendor.kind, details: vendor.details,
                                  rank: rankFor(specificity: vendor.specificity),
                                  trackerShaped: false, rotatingPhone: false)
        }

        if let service = service {
            return Classification(kind: service.kind, details: service.details,
                                  rank: rankFamily, trackerShaped: false, rotatingPhone: false,
                                  preferredLabel: service.preferredLabel)
        }
        if sighting.name != nil {
            return Classification(kind: "Named device")
        }
        return Classification()
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

    static let historyCap = 24

    init(sighting: Sighting) {
        id = sighting.address
        firstSeen = sighting.seenAt
        lastSeen = sighting.seenAt
        observe(sighting)
    }

    mutating func observe(_ sighting: Sighting) {
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
        let classification = Classification.classify(sighting)
        if classification.rank >= rank || rank == Classification.rankUnknown {
            kind = classification.kind
            rank = classification.rank
        }
        if let label = classification.preferredLabel {
            preferredLabel = label
        }
        if !classification.details.isEmpty {
            details = classification.details
        }
        trackerShaped = trackerShaped || classification.trackerShaped
        rotatingAddress = rotatingAddress
            || classification.rotatingPhone
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

    /// How long the device has been in earshot this session.
    var dwell: TimeInterval { return max(0, lastSeen - firstSeen) }

    var sightingsPerMinute: Double {
        guard dwell >= 10 else { return 0 }
        return Double(sightings) / (dwell / 60)
    }

    func age(now: TimeInterval) -> TimeInterval { return max(0, now - lastSeen) }
}
