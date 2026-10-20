import Foundation

/// THE EMCON STANDARD — the regulations of this house's
/// emissions control, stated once and enforced everywhere.
///
/// Doctrine, after the naval practice it is named for:
/// emissions control is not a mood, it is a CONDITION — a
/// graded, declared state that says exactly which emitters
/// may stand and which must be dark, enforced at the moment
/// anything tries to transmit, not remembered afterwards.
///
/// The conditions, most restrictive last:
///
///  - OPEN: no restriction. The operator's house, run loud
///    or quiet by hand.
///  - CHARLIE (guarded): the house may serve, but only
///    unlisted (stealth). Nothing advertises: no GATT host,
///    no beacon or flare, no listed Serve, no persona. No
///    campaigns: no Net-Assault, no probing, no War Room
///    run, no Banshee. No update checks — a check is an
///    emission to the world. Listening and the tripwire
///    stand; the relay mailbox may be polled.
///  - BRAVO (receive only): CHARLIE, and Serve itself
///    stands down — listeners that answer are emissions
///    too. The relay poll stops. The house only hears:
///    the listening post, the sweeps and audits it runs
///    by hand, and the tripwire.
///  - ALPHA (total silence): BRAVO, and the active sweeps
///    stop too. Nothing the app controls transmits at all.
///    The tripwire and the passive post remain — hearing
///    is not an emission.
///
/// One boundary, stated plainly: EMCON governs STANDING
/// emissions and CAMPAIGNS — the organs that announce,
/// advertise, serve, probe or poll on their own. A single
/// deliberate transmission the operator fires by hand (one
/// knock, one payload) is the operator speaking, the same
/// way a ship under EMCON may still be ordered to transmit;
/// the order is the act, and it is journaled like any other.
/// What EMCON forbids can never stand open behind the
/// operator's back.
///
/// The score is decimal and exact by construction: every
/// emitter carries a fixed weight in the inventory below,
/// the weights of a fully-lit house sum to exactly 100.0,
/// and nothing is capped, clamped or rounded away. Evidence
/// (what recon and the Bonjour audit last measured) enters
/// through a stated saturating formula — each finding adds
/// less than the last, bounded by its line's maximum, the
/// way real evidence behaves. Bands are the Standard's own:
/// 0.0 GHOST · under 10 DARK · under 30 LIT · under 60
/// LOUD · beyond, BEACONING.
///
/// Efficiency under EMCON is part of the standard, not a
/// side effect: enforcement is event-driven at the emission
/// funnels (no polling, no timers of its own), the relay
/// poll and the update checker stand down by condition, and
/// the audit reads live organ state on demand only.
enum EmconCondition: Int, CaseIterable, Comparable {
    case open = 0
    case charlie = 1
    case bravo = 2
    case alpha = 3

    static func < (a: EmconCondition, b: EmconCondition) -> Bool {
        a.rawValue < b.rawValue
    }

    var name: String {
        switch self {
        case .open: return L("Open")
        case .charlie: return L("Charlie")
        case .bravo: return L("Bravo")
        case .alpha: return L("Alpha")
        }
    }

    /// The declared form: "EMCON ALPHA".
    var declared: String {
        self == .open ? L("EMCON off") : "EMCON \(name.uppercased())"
    }

    var summary: String {
        switch self {
        case .open:
            return L("No restriction — the house runs as the operator sets it, organ by organ.")
        case .charlie:
            return L("Guarded. Serve may stand, unlisted only. Nothing advertises, no campaigns, no update checks. Listening, the tripwire and the relay poll stand.")
        case .bravo:
            return L("Receive only. Serve stands down too, and the relay poll stops. The house only hears.")
        case .alpha:
            return L("Total silence. Even the active sweeps stop; nothing the app controls transmits. The tripwire and the passive post remain.")
        }
    }

    // MARK: - persistence

    private static let key = "emcon.condition"
    private static let legacyKey = "emconActive"

    /// The condition in force, read from storage — the
    /// funnels consult this directly, so the regulation
    /// holds from the first launch moment, before any
    /// EMCON object exists. The legacy on/off flag migrates:
    /// EMCON on, in the old binary sense, was CHARLIE's
    /// shape (dark air, unlisted serve).
    static var current: EmconCondition {
        let defaults = UserDefaults.standard
        if let raw = defaults.object(forKey: key) as? Int,
           let saved = EmconCondition(rawValue: raw) {
            return saved
        }
        return defaults.bool(forKey: legacyKey) ? .charlie : .open
    }

    static func store(_ condition: EmconCondition) {
        let defaults = UserDefaults.standard
        defaults.set(condition.rawValue, forKey: key)
        defaults.set(condition != .open, forKey: legacyKey)
    }

    // MARK: - the regulations

    /// May this organ stand under this condition?
    func permits(_ organ: EmconOrgan) -> Bool {
        switch self {
        case .open:
            return true
        case .charlie:
            switch organ {
            case .serveStealth, .relayPoll, .sweep:
                return true
            case .serveListed, .gattHost, .beacon, .persona,
                 .netAssault, .probing, .warRun, .banshee,
                 .updateCheck:
                return false
            }
        case .bravo:
            // Receive only: the hand-run diagnostics stand
            // (they are how a dark house checks its own
            // shadow); nothing standing, nothing polling.
            return organ == .sweep
        case .alpha:
            return false
        }
    }
}

/// The standing emitters and campaigns the Standard
/// governs. (Listening, the tripwire and one deliberate
/// transmission by hand are not organs — see the doctrine.)
enum EmconOrgan: String {
    case serveListed, serveStealth, gattHost, beacon, persona
    case netAssault, probing, warRun, banshee
    case relayPoll, updateCheck, sweep

    var label: String {
        switch self {
        case .serveListed: return L("a listed Serve")
        case .serveStealth: return L("Serve")
        case .gattHost: return L("the GATT host")
        case .beacon: return L("the beacon")
        case .persona: return L("a persona")
        case .netAssault: return L("Net-Assault")
        case .probing: return L("active probing")
        case .warRun: return L("a War Room run")
        case .banshee: return L("the Banshee")
        case .relayPoll: return L("the relay poll")
        case .updateCheck: return L("an update check")
        case .sweep: return L("an active sweep")
        }
    }
}

/// Everything the score reads, gathered once from the live
/// organs by Emcon's audit — the ONLY way a score is made.
/// Surfaces never assemble inputs by hand again.
struct EmconSnapshot {
    var onLan = false
    var deviceName = "iPhone"
    var hostName = ""
    var serveRunning = false
    var stealth = false
    var serveListeners = 1
    var gattHostOn = false
    var beaconOn = false
    var flareOn = false
    var personaOn = false
    var assaultOn = false
    var probingOn = false
    var warKnocking = false
    var warTracing = false
    var bansheeOn = false
    var relayPolling = false
    var writeScanning = false
    var exposureCount = 0
    var announcerCount = 0
}

/// One line of the standing board: a governed
/// organ, whether it stands, what it costs
/// while it stands, and the condition's
/// ruling on it.
struct EmconBoardRow: Identifiable {
    let organ: EmconOrgan
    let label: String
    let standing: Bool
    let weight: Double
    let ruling: String
    var id: String { organ.rawValue + "|" + label }
    /// Standing where the condition forbids:
    /// named, never assumed away.
    var violation: Bool {
        standing && ruling == "Forbidden"
    }
}

enum EmconStandard {

    // MARK: - the inventory (weights, exact)

    static let wPresence = 5.0
    static let wNamePersonal = 8.0
    static let wNameHost = 5.0
    static let wNameDevice = 3.0
    static let wServeListed = 12.0
    static let wServeListedExtra = 1.0   // per extra, max 3
    static let wServeStealth = 4.0
    static let wServeStealthExtra = 0.5  // per extra, max 3
    static let wGattHost = 13.0
    static let wBeacon = 9.0
    static let wPersona = 5.0
    static let wAssault = 14.0
    static let wProbing = 5.0
    static let wWarKnocking = 5.0
    static let wWarTracing = 1.5
    static let wBanshee = 3.0
    static let wRelayPoll = 1.0
    static let wWriteScan = 2.0
    static let wReconMax = 9.0
    static let wBonjourMax = 6.0

    /// The fully-lit house: every maximum at once. The
    /// inventory is constructed to make this exactly 100.0;
    /// a test pins it, so no future weight can drift the
    /// scale silently.
    static var maximumTotal: Double {
        wPresence + wNamePersonal
            + (wServeListed + 3 * wServeListedExtra)
            + wGattHost + wBeacon + wPersona + wAssault
            + wProbing + wWarKnocking + wBanshee + wRelayPoll
            + wWriteScan + wReconMax + wBonjourMax
    }

    // MARK: - the score

    /// Decimal, exact, uncapped: the sum of the inventory
    /// lines that are true right now, evidence folded by its
    /// formula, the total rounded to one decimal — the
    /// tenth is the Standard's precision, and it is real.
    static func score(_ s: EmconSnapshot) -> Emcon.Score {
        var parts: [Emcon.Score.Part] = []
        func weigh(_ label: String, _ points: Double) {
            let rounded = (points * 10).rounded() / 10
            guard rounded > 0 else { return }
            parts.append(Emcon.Score.Part(label: label,
                                          points: rounded))
        }
        if s.onLan { weigh(L("On the wire"), wPresence) }
        if s.assaultOn { weigh(L("Net-Assault running"), wAssault) }
        if s.gattHostOn { weigh(L("GATT host"), wGattHost) }
        if s.beaconOn || s.flareOn {
            weigh(s.flareOn && !s.beaconOn
                    ? L("Flare") : L("BLE beacon"), wBeacon)
        }
        if s.personaOn { weigh(L("Persona worn"), wPersona) }
        if s.probingOn { weigh(L("Active probing"), wProbing) }
        if s.warKnocking {
            weigh(L("War Room, knocking"), wWarKnocking)
        } else if s.warTracing {
            weigh(L("War Room, tracing"), wWarTracing)
        }
        if s.bansheeOn { weigh(L("Banshee shouts"), wBanshee) }
        if s.writeScanning {
            weigh(L("BLE write scan"), wWriteScan)
        }
        if s.serveRunning {
            let extra = min(3, max(0, s.serveListeners - 1))
            if s.stealth {
                weigh(s.serveListeners > 1
                    ? String(format: L("Serve, stealth ×%lld"),
                             s.serveListeners)
                    : L("Serve, stealth"),
                      wServeStealth
                        + Double(extra) * wServeStealthExtra)
            } else {
                weigh(s.serveListeners > 1
                    ? String(format: L("Serve, listed ×%lld"),
                             s.serveListeners)
                    : L("Serve, listed"),
                      wServeListed
                        + Double(extra) * wServeListedExtra)
            }
        }
        if s.relayPolling { weigh(L("Relay polling"), wRelayPoll) }
        if s.deviceName.contains("\u{2019}s ")
            || s.deviceName.contains("'s ") {
            weigh(L("Personal name"), wNamePersonal)
        } else if !s.hostName.isEmpty
                    && s.hostName.lowercased() != "iphone" {
            weigh(String(format: L("Answers as %@"), s.hostName), wNameHost)
        } else if s.deviceName != "iPhone" {
            weigh(L("Broadcast name"), wNameDevice)
        }
        if s.exposureCount > 0 {
            // Evidence saturates: the first findings say
            // the most; the line's maximum is its budget.
            let evidence = wReconMax
                * (1 - exp(-Double(s.exposureCount) / 6))
            weigh(String(format: L("Recon hits ×%lld"), s.exposureCount), evidence)
        }
        if s.announcerCount > 0 {
            let evidence = wBonjourMax
                * (1 - exp(-Double(s.announcerCount) / 4))
            weigh(String(format: L("Bonjour ×%lld"), s.announcerCount), evidence)
        }
        let raw = parts.reduce(0) { $0 + $1.points }
        let value = (raw * 10).rounded() / 10
        let band: String
        switch value {
        case 0: band = "GHOST"
        case ..<10: band = "DARK"
        case ..<30: band = "LIT"
        case ..<60: band = "LOUD"
        default: band = "BEACONING"
        }
        return Emcon.Score(value: value, band: band, parts: parts)
    }

    // MARK: - the standing board

    /// The board: every governed organ, its
    /// live state, its exact weight while it
    /// stands, and the condition's ruling on
    /// it. The score says what the house costs;
    /// the board says WHY, organ by organ, and
    /// what a condition would do about each —
    /// so a switch is legible even in a quiet
    /// house, where nothing had to fall.
    static func board(_ s: EmconSnapshot,
                      condition: EmconCondition)
        -> [EmconBoardRow] {
        func ruling(for organ: EmconOrgan) -> String {
            condition.permits(organ)
                ? "Permitted" : "Forbidden"
        }
        var rows: [EmconBoardRow] = []
        // Serve is one row; its form follows
        // its state, and its ruling when dark
        // is the condition's shape for it.
        let serveOrgan: EmconOrgan = s.serveRunning
            ? (s.stealth ? .serveStealth : .serveListed)
            : .serveListed
        let serveRuling: String
        if s.serveRunning {
            serveRuling = ruling(for: serveOrgan)
        } else if condition.permits(.serveListed) {
            serveRuling = "Permitted"
        } else if condition.permits(.serveStealth) {
            serveRuling = "Stealth only"
        } else {
            serveRuling = "Forbidden"
        }
        let extra = min(3, max(0, s.serveListeners - 1))
        let serveWeight = s.stealth
            ? wServeStealth
                + Double(extra) * wServeStealthExtra
            : wServeListed
                + Double(extra) * wServeListedExtra
        rows.append(EmconBoardRow(
            organ: serveOrgan, label: L("Serve"),
            standing: s.serveRunning,
            weight: serveWeight, ruling: serveRuling))
        func row(_ organ: EmconOrgan, _ label: String,
                 _ standing: Bool, _ weight: Double) {
            rows.append(EmconBoardRow(
                organ: organ, label: label,
                standing: standing, weight: weight,
                ruling: ruling(for: organ)))
        }
        row(.gattHost, L("GATT host"),
            s.gattHostOn, wGattHost)
        row(.beacon, L("BLE beacon"),
            s.beaconOn || s.flareOn, wBeacon)
        row(.persona, L("Persona"),
            s.personaOn, wPersona)
        row(.netAssault, L("Net-Assault"),
            s.assaultOn, wAssault)
        row(.probing, L("Active probing"),
            s.probingOn, wProbing)
        row(.warRun, L("War Room run"),
            s.warKnocking || s.warTracing,
            s.warKnocking ? wWarKnocking : wWarTracing)
        row(.banshee, L("The Banshee"),
            s.bansheeOn, wBanshee)
        row(.relayPoll, L("Relay poll"),
            s.relayPolling, wRelayPoll)
        row(.sweep, L("BLE write scan"),
            s.writeScanning, wWriteScan)
        return rows
    }

    /// What this condition's gates refuse,
    /// named in the Standard's own words. On a
    /// quiet house nothing falls when a
    /// condition engages — the refusals ARE
    /// the change, and the room states them.
    static func refusedLabels(
        for condition: EmconCondition) -> [String] {
        let organs: [EmconOrgan] = [
            .serveListed, .serveStealth, .gattHost,
            .beacon, .persona, .netAssault, .probing,
            .warRun, .banshee, .relayPoll,
            .updateCheck, .sweep]
        var labels: [String] = []
        var serveNamed = false
        for organ in organs {
            guard !condition.permits(organ) else {
                continue
            }
            if organ == .serveListed
                || organ == .serveStealth {
                if serveNamed { continue }
                serveNamed = true
                labels.append(
                    condition.permits(.serveStealth)
                        ? L("a listed Serve") : L("Serve"))
                continue
            }
            labels.append(organ.label)
        }
        return labels
    }

    // MARK: - the gate

    /// The funnel check every standing emitter passes
    /// before it starts. Returns true when the condition
    /// FORBIDS the organ — and journals the refusal, so a
    /// blocked start is never a silent failure. Cheap by
    /// design: one defaults read, no timers, no polling.
    static func refused(_ organ: EmconOrgan) -> Bool {
        let condition = EmconCondition.current
        guard !condition.permits(organ) else { return false }
        Journal.log("emcon", "regulation",
                    "\(condition.declared) forbids "
                    + "\(organ.label) — it stays dark")
        return true
    }
}
