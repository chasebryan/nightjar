import Foundation
import Network

// BlacksiteBenchPlant — the bench,
// wave twelve: the plant floor. Five
// engines that do not add a single
// new protocol to the bench — the
// ICS wave's generic identification
// reads already knock on every door
// here — but read their answers
// together, as a facility. A Modbus
// identification ledger, an S7 plate,
// an EtherNet/IP identity, a BACnet
// device object, the DNP3 device
// attributes, the 61850 door, a
// SunSpec nameplate: each alone
// names a device. Together, in the
// device's own words only, they may
// name the plant the device serves —
// a generating station and its kind,
// a water works, a substation — and
// the claim is graded exactly as
// hard as the words allow: two words
// or a word and a corroborating door
// make a claim, one word makes a
// lean, and a vendor's name alone
// makes nothing at all. The doctrine
// is the plant floor's own, and it
// is the hardest on this bench:
// identification and posture grading
// ONLY. No control or write function
// codes, ever: no Modbus writes, no
// DNP3 control or restart function
// codes (device attributes are
// group-0 READS only), no IEC 104
// general interrogation, no IEC
// 61850 control services. And
// nothing here is ever addressed to
// a reactor protection or safety
// system: if a generic read returns
// a nameplate that classifies as
// safety or protection equipment,
// the board REPORTS the
// classification and the exposure —
// the bench does not direct further
// probes at it, at any scale.

extension BlacksiteBench {

    // MARK: the classifier — a pure
    // reading of the device's own
    // words, and nothing else

    /// Which lens a battery claims
    /// through: the marquee takes
    /// every class; the weighted
    /// verbs claim only in their
    /// own field, and report the
    /// rest as words that rode along.
    enum PlantFocus {
        case any, generation, water, grid
    }

    /// The board's verdict: the
    /// facility claimed (or the
    /// honest unproven), whether it
    /// stands as a claim or a lean,
    /// the words that carried it,
    /// the words outside the lens,
    /// and the safety reading.
    struct PlantVerdict {
        var facility: String
        var named: Bool
        var leaning: Bool
        var words: [String]
        var also: [String]
        var safety: Bool
        var safetyWords: [String]
    }

    /// Words that name a process.
    /// Only these may carry a class,
    /// and only when the device
    /// itself printed them — a
    /// vendor's name is in none of
    /// these tables, by design.
    static let plantClasses: [(
        key: String, display: String,
        words: [String])] = [
        ("coal", "generation — coal", [
            "coal", "pulverizer",
            "fly ash", "sootblower",
            "ash pond", "coal-fired",
            "coal fired",
        ]),
        ("gas", "generation — gas", [
            "gas turbine",
            "combustion turbine",
            "combined cycle", "hrsg",
            "heat recovery steam",
            "gas-fired", "natural gas",
        ]),
        ("oil", "generation — oil / diesel", [
            "oil-fired", "fuel oil",
            "diesel generator",
            "diesel genset", "crude oil",
            "oil burner",
        ]),
        ("hydro", "generation — hydro", [
            "hydroelectric", "penstock",
            "wicket gate", "spillway",
            "hydro plant", "hydro unit",
            "francis turbine",
            "kaplan turbine",
        ]),
        ("solar", "generation — solar", [
            "solar", "photovoltaic",
            "pv inverter", "pv array",
        ]),
        ("wind", "generation — wind", [
            "wind turbine", "wind farm",
            "wind plant", "nacelle",
            "yaw drive",
        ]),
        ("geothermal",
         "generation — geothermal", [
            "geothermal",
        ]),
        ("biomass", "generation — biomass", [
            "biomass", "bagasse",
            "wood-fired", "grate furnace",
        ]),
        ("storage", "battery storage", [
            "battery storage",
            "energy storage", "bess",
            "battery inverter",
            "grid battery",
        ]),
        ("water", "water treatment", [
            "water treatment",
            "clarifier", "chlorination",
            "chlorine contact", "potable",
            "drinking water", "filtration",
            "reverse osmosis",
            "coagulation",
            "uv disinfection",
            "sedimentation",
        ]),
        ("wastewater", "wastewater", [
            "wastewater", "sewage",
            "lift station", "aeration",
            "sludge", "digester",
            "influent", "effluent",
            "grit chamber",
            "trickling filter",
            "membrane bioreactor",
            "clarifier",
        ]),
        ("substation",
         "substation / distribution", [
            "substation", "switchgear",
            "busbar", "switchyard",
            "circuit breaker",
            "feeder breaker",
            "power transformer",
            "transformer", "recloser",
            "capacitor bank",
            "voltage regulator",
            "distribution feeder",
            "feeder",
        ]),
    ]

    /// The generation words that
    /// name the craft but not the
    /// fuel: they corroborate a
    /// nuclear plate, and they carry
    /// the generic claim when no
    /// kind subclass spoke.
    static let plantGenShared: [String] = [
        "turbine", "generator", "boiler",
        "exciter", "governor",
        "powerhouse", "steam header",
        "generating unit", "feedwater",
        "condensate",
    ]

    /// The protection words. A plate
    /// carrying any of these is
    /// classified, reported — and
    /// never probed further. Bare
    /// "protection" is NOT in this
    /// table: an S7 ledger's
    /// protection LEVEL is a posture
    /// word, not a safety system.
    static let plantSafetyWords: [String] = [
        "protection relay",
        "protective relay",
        "reactor protection",
        "protection system",
        "safety instrumented",
        "breaker failure",
        "distance relay",
        "feeder protection",
        "schweitzer", "sel-",
    ]

    /// Claim the facility from the
    /// evidence: the concatenated
    /// words of every identification
    /// read that answered, the doors
    /// that corroborate, and the
    /// battery's lens. Pure — the
    /// same plate always grades the
    /// same, on the bench or in the
    /// Gauntlet.
    static func plantClassify(
        evidence: String,
        doors: Set<String>,
        focus: PlantFocus) -> PlantVerdict {
        let text = evidence.lowercased()
        func hits(
            _ words: [String]) -> [String] {
            words.filter {
                text.contains($0)
            }
        }
        var byKey: [String: [String]] = [:]
        var display: [String: String] = [:]
        for entry in plantClasses {
            byKey[entry.key] = hits(
                entry.words)
            display[entry.key] = entry.display
        }
        // The nuclear claim: the word
        // itself, plus every shared
        // generation word the plate
        // carried — balance-of-plant
        // words, read as such. The
        // reactor's own systems are
        // not words here; they are
        // the safety reading below.
        let shared = hits(plantGenShared)
        if text.contains("nuclear") {
            byKey["nuclear"] = ["nuclear"]
                + shared
        } else {
            byKey["nuclear"] = []
        }
        display["nuclear"] =
            "generation — nuclear balance-of-plant"
        // The SunSpec door is solar or
        // storage gear by kind — the
        // nameplate standard exists
        // for those two families — so
        // its answer is a word in
        // both ledgers, and the plate
        // itself must separate them.
        if doors.contains("sunspec") {
            for key in ["solar", "storage"] {
                var words = byKey[key] ?? []
                if !words.contains(
                    "sunspec nameplate") {
                    words.append(
                        "sunspec nameplate")
                }
                byKey[key] = words
            }
        }
        // Generic generation competes
        // only when no kind subclass
        // spoke at all.
        let subclasses = [
            "nuclear", "coal", "gas",
            "oil", "hydro", "solar",
            "wind", "geothermal",
            "biomass", "storage",
        ]
        let subclassSpoke = subclasses
            .contains {
                !(byKey[$0] ?? []).isEmpty
            }
        byKey["generation"] = subclassSpoke
            ? [] : shared
        display["generation"] =
            "generation — fuel unproven"
        // The lens: which classes may
        // carry the claim.
        let competing: [String]
        switch focus {
        case .any:
            competing = [
                "nuclear", "solar", "wind",
                "hydro", "geothermal",
                "biomass", "storage",
                "coal", "gas", "oil",
                "water", "wastewater",
                "substation", "generation",
            ]
        case .generation:
            competing = subclasses
                + ["generation"]
        case .water:
            competing = [
                "water", "wastewater",
            ]
        case .grid:
            competing = ["substation"]
        }
        // The winner: most words
        // carries it; the competing
        // list's order breaks ties,
        // most specific first.
        var winner: String? = nil
        var winnerWords: [String] = []
        for key in competing {
            let words = byKey[key] ?? []
            if words.count
                > winnerWords.count {
                winner = key
                winnerWords = words
            }
        }
        // The words outside the lens,
        // labelled with their class.
        var also: [String] = []
        for entry in plantClasses
        where !competing.contains(
            entry.key) {
            for word in byKey[entry.key]
                ?? [] {
                also.append(word + " ("
                    + entry.display + ")")
            }
        }
        // The safety reading: the
        // protection words, plus the
        // SEL door itself — a
        // Schweitzer relay's terminal
        // answered with its ID report
        // is protection equipment by
        // kind, whatever words rode
        // on the plate.
        var safetyWords = hits(
            plantSafetyWords)
        if doors.contains("sel") {
            safetyWords.append(
                "sel relay terminal")
        }
        let safety = !safetyWords.isEmpty
        guard let won = winner,
              !winnerWords.isEmpty else {
            return PlantVerdict(
                facility: "plant equipment, class unproven",
                named: false, leaning: false,
                words: [], also: also,
                safety: safety,
                safetyWords: safetyWords)
        }
        // A door corroborates: the
        // grid doors for the
        // substation, the SunSpec
        // door for its two families.
        let doorSupport: Bool
        switch won {
        case "substation":
            doorSupport = !doors
                .intersection([
                    "dnp3", "iec61850",
                    "iec104", "sel",
                ]).isEmpty
        case "solar", "storage":
            doorSupport = doors.contains(
                "sunspec")
        default:
            doorSupport = false
        }
        let named = winnerWords.count >= 2
            || doorSupport
        var facility = display[won]
            ?? won
        // The one honest merge: a
        // SunSpec plate that says
        // nothing more separates
        // neither solar from storage.
        if won == "solar",
           winnerWords
            == ["sunspec nameplate"],
           (byKey["storage"] ?? [])
            == ["sunspec nameplate"] {
            facility = "generation — solar / battery storage"
        }
        return PlantVerdict(
            facility: facility,
            named: named,
            leaning: !named,
            words: winnerWords,
            also: also,
            safety: safety,
            safetyWords: safetyWords)
    }

    // MARK: the battery — the ICS
    // wave's reads, composed; the
    // board at the end

    /// Run the reads the lens calls
    /// for against one host, print
    /// each ledger as it comes, and
    /// close with the classification
    /// board. Every read is the ICS
    /// core's own, unmodified — this
    /// wave composes, it does not
    /// re-implement. One pool rule:
    /// the 61850 core's words are the
    /// BENCH's (its line calls the
    /// door "the substation dialect"),
    /// so they never enter the
    /// evidence pool — the door
    /// corroborates, it does not
    /// testify.
    static func plantBattery(
        host: String, ip: String,
        verb: String,
        focus: PlantFocus) -> [ICSLine] {
        var out: [ICSLine] = [(
            String(format: L("%@ — the facility battery at %@, one board"), verb, host),
            .sys)]
        out.append((
            String(format: L("%@: identification and posture grading ONLY. No control or write function codes, ever: no Modbus writes, no DNP3 control or restart function codes (device attributes are group-0 READS only), no IEC 104 general interrogation, no IEC 61850 control services."), verb),
            .out))
        out.append((
            String(format: L("%@: nothing here is addressed to a reactor protection or safety system — if a plate classifies as one, the board reports it, and the bench directs nothing further at it."), verb),
            .out))
        var evidence: [String] = []
        var doors: Set<String> = []
        var answered = 0
        func section(
            _ label: String, door: String,
            pool: Bool,
            _ body: [ICSLine]) {
            out.append((
                String(format: L("battery: %@"), label),
                .sys))
            out += body
            if body.contains(where: {
                $0.kind == .sys
            }) {
                doors.insert(door)
                answered += 1
            }
            if pool {
                evidence += body.map {
                    $0.text
                }
            }
        }
        switch focus {
        case .any, .generation, .water:
            section(L("modbus — the identification ledger"),
                    door: "modbus", pool: true,
                    icsModbusCore(
                        host: host, ip: ip,
                        port: 502, light: false))
            section(L("s7 — the cpu's own plate"),
                    door: "s7", pool: true,
                    icsS7Core(
                        host: host, ip: ip,
                        port: 102, light: false))
            section(L("etherNet/ip — list identity"),
                    door: "enip", pool: true,
                    icsENIPCore(
                        host: host, ip: ip,
                        port: 44818,
                        light: false))
            section(L("bacnet — the device object"),
                    door: "bacnet", pool: true,
                    icsBACnetCore(
                        host: host, ip: ip,
                        port: 47808,
                        light: false))
            section(L("dnp3 — the device attributes, group 0"),
                    door: "dnp3", pool: true,
                    icsDNP3Core(
                        host: host, ip: ip,
                        port: 20000,
                        light: false))
            section(L("iec 61850 — the mms door"),
                    door: "iec61850",
                    pool: false,
                    icsIEC61850Core(
                        host: host, ip: ip,
                        port: 102, light: false))
            if focus == .generation {
                section(L("sunspec — the inverter nameplate"),
                        door: "sunspec",
                        pool: true,
                        icsSunSpecCore(
                            host: host, ip: ip,
                            port: 502,
                            light: false))
            }
        case .grid:
            section(L("iec 61850 — the mms door"),
                    door: "iec61850",
                    pool: false,
                    icsIEC61850Core(
                        host: host, ip: ip,
                        port: 102, light: false))
            section(L("dnp3 — the device attributes, group 0"),
                    door: "dnp3", pool: true,
                    icsDNP3Core(
                        host: host, ip: ip,
                        port: 20000,
                        light: false))
            section(L("iec 60870-5-104 — the posture, knocked not interrogated"),
                    door: "iec104", pool: true,
                    icsIEC104Core(
                        host: host, ip: ip,
                        port: 2404,
                        light: false))
            out.append((
                L("gridprobe: the 104 posture above was taken with STARTDT and TESTFR only — no general interrogation was sent; a general interrogation floods the outstation with its whole database, and this bench never sends one, here or anywhere."),
                .out))
            section(L("sel — the relay's id report, last and lightly"),
                    door: "sel", pool: true,
                    icsSELCore(
                        host: host, ip: ip,
                        port: 23, light: false))
        }
        // The board.
        if answered == 0 {
            out.append((
                String(format: L("%@: no plant door answered at %@ — silence, graded as silence; nothing is classified."), verb, host),
                .out))
            return out
        }
        let verdict = plantClassify(
            evidence: evidence.joined(
                separator: "\n"),
            doors: doors, focus: focus)
        if verdict.named {
            out.append((
                String(format: L("%@: the plate claims — %@."), verb, verdict.facility),
                .ok))
            out.append((
                String(format: L("%@: its own words: %@."), verb, verdict.words.joined(separator: ", ")),
                .out))
        } else if verdict.leaning {
            out.append((
                String(format: L("%@: the plate leans — %@, on one word: %@. A lean, graded as a lean."), verb, verdict.facility, verdict.words.joined(separator: ", ")),
                .out))
        } else {
            out.append((
                String(format: L("%@: plant equipment, class unproven — the plates named gear, not a process. A vendor's name alone proves no facility, and none is claimed."), verb),
                .out))
        }
        if !verdict.also.isEmpty {
            out.append((
                String(format: L("%@: words outside this battery's lens rode along: %@."), verb, verdict.also.joined(separator: ", ")),
                .out))
        }
        if verdict.safety {
            out.append((
                String(format: L("%@: SAFETY CLASS — the plate carries protection words (%@). Reported as exposure, exactly as the doctrine holds: nothing further was directed at it, and nothing will be — a safety system's nameplate may be read aloud by a generic knock; it is never spoken to."), verb, verdict.safetyWords.joined(separator: ", ")),
                .err))
        }
        out.append((
            String(format: L("%@: identification and posture grading only — every byte above is a published identification read. No control or write function code exists in this verb, in any protocol it speaks."), verb),
            .out))
        return out
    }

    // MARK: the four target verbs

    static func plantprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("plantprobe: give a host — plantprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, plantBattery(
                host: host, ip: ip,
                verb: "plantprobe",
                focus: .any))
        }
    }

    static func genprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("genprobe: give a host — genprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, plantBattery(
                host: host, ip: ip,
                verb: "genprobe",
                focus: .generation))
        }
    }

    static func waterprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("waterprobe: give a host — waterprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, plantBattery(
                host: host, ip: ip,
                verb: "waterprobe",
                focus: .water))
        }
    }

    static func gridprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("gridprobe: give a host — gridprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, plantBattery(
                host: host, ip: ip,
                verb: "gridprobe",
                focus: .grid))
        }
    }

    // MARK: plantcensus — the light
    // sweep, claimed per address

    /// One address, lightly: the
    /// four plant doors in their
    /// census weight, the evidence
    /// they raised, and the claim
    /// the classifier grades from
    /// it. Light answers carry fewer
    /// words, so census claims grade
    /// one step humbler by the same
    /// rules.
    static func plantCensusHost(
        ip: String)
        -> (doors: [String],
            verdict: PlantVerdict) {
        var doors: [String] = []
        var doorSet: Set<String> = []
        var evidence: [String] = []
        func knock(
            _ label: String, door: String,
            _ body: [ICSLine]) {
            if body.contains(where: {
                $0.kind == .sys
            }) {
                doors.append(label)
                doorSet.insert(door)
            }
            evidence += body.map {
                $0.text
            }
        }
        knock(L("Modbus"), door: "modbus",
              icsModbusCore(
                host: ip, ip: ip,
                port: 502, light: true))
        knock(L("EtherNet/IP"), door: "enip",
              icsENIPCore(
                host: ip, ip: ip,
                port: 44818, light: true))
        knock(L("DNP3"), door: "dnp3",
              icsDNP3Core(
                host: ip, ip: ip,
                port: 20000, light: true))
        knock(L("BACnet"), door: "bacnet",
              icsBACnetCore(
                host: ip, ip: ip,
                port: 47808, light: true))
        let verdict = plantClassify(
            evidence: evidence.joined(
                separator: "\n"),
            doors: doorSet, focus: .any)
        return (doors, verdict)
    }

    static func plantcensus(
        target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let prefix = buildPrefix(
                target) else {
                icsSay(emit, L("plantcensus: give a prefix — plantcensus 192.168.1 — or nothing for this wire"), .err)
                return
            }
            icsSay(emit, String(format: L("plantcensus — one light knock per plant door across %@.0/24, each claim graded from the device's own words"), prefix), .sys)
            let lock = NSLock()
            var hits: [(octet: Int,
                        doors: [String],
                        verdict: PlantVerdict)] = []
            let group = DispatchGroup()
            let sem = DispatchSemaphore(
                value: 24)
            for octet in 1...254 {
                if stopped() { break }
                let ip = "\(prefix).\(octet)"
                group.enter()
                DispatchQueue.global()
                    .async {
                        sem.wait()
                        let found =
                            plantCensusHost(
                                ip: ip)
                        if !found.doors
                            .isEmpty {
                            lock.lock()
                            hits.append((
                                octet,
                                found.doors,
                                found.verdict))
                            lock.unlock()
                        }
                        sem.signal()
                        group.leave()
                    }
            }
            group.wait()
            hits.sort { $0.octet < $1.octet }
            for hit in hits {
                var line = String(
                    format: L("plantcensus: %@.%lld — %@ — %@"),
                    prefix, Int64(hit.octet),
                    hit.doors.joined(
                        separator: ", "),
                    hit.verdict.facility)
                if hit.verdict.safety {
                    line += String(
                        format: L(" — SAFETY CLASS (%@)"),
                        hit.verdict.safetyWords
                            .joined(
                                separator: ", "))
                }
                icsSay(emit, line,
                       hit.verdict.safety
                        ? .err : .ok)
            }
            icsSay(emit, String(format: L("plantcensus: %lld address(es) keep plant doors on %@.0/24."), Int64(hits.count), prefix), hits.isEmpty ? .out : .ok)
            icsSay(emit, L("plantcensus: light knocks only — identification reads, the same ones the verbs make; no control or write function was sent anywhere in the sweep, and safety-classified plates were reported, never probed further."), .out)
        }
    }

    // MARK: the wave's one dispatch

    static func benchPlant(
        _ name: String, _ target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = {
            text, kind in
            if !stopped() {
                emit(text, kind)
            }
        }
        switch name {
        case "plantprobe":
            plantprobe(target: target,
                       emit: live, done: done)
        case "genprobe":
            genprobe(target: target,
                     emit: live, done: done)
        case "waterprobe":
            waterprobe(target: target,
                       emit: live, done: done)
        case "gridprobe":
            gridprobe(target: target,
                      emit: live, done: done)
        case "plantcensus":
            plantcensus(
                target: target,
                stopped: stopped,
                emit: live, done: done)
        default:
            done()
        }
    }
}
