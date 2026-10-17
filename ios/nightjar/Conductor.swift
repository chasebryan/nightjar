import Foundation

/// The conductor: reflexes the operator arms once, fired
/// without them. Everything in the instrument already knows
/// how to act — the canary can rise, Serve can open, the
/// bench can load, threads can burn — but until now each
/// waited for a tap. A rule is a trigger on the wire paired
/// with one of those actions; the conductor evaluates rules
/// where the events already flow: the tripwire funnel, the
/// knock vault, and the honeydrop choke.
///
/// Discipline: a master switch, a rest between
/// firings that lengthens per rule and per host,
/// and every firing journaled —
/// a reflex that acts in the dark and leaves no line in the
/// sealed log would be a second operator, and there is only
/// one operator. Actions that need what the moment doesn't
/// have (a mouth, a target) degrade to the journal line
/// alone. And no reflex ever fires the bench: loading Recon
/// is an action, pulling its trigger stays a human press.
enum Conductor {
    struct Rule: Codable, Identifiable {
        var id: String
        var name: String
        var trigger: String
        var action: String
        var enabled: Bool
    }

    struct Fire {
        var host: String? = nil
        var port: Int? = nil
        var verdict: String? = nil
    }

    static let triggers: [(id: String, label: String)] = [
        ("fingerprinted", "A fingerprinted knock"),
        ("honeydrop", "A honeydrop is taken"),
        ("vault", "The knock vault opens"),
        ("newSource", "A new source knocks"),
        ("anyKnock", "Any knock"),
        ("foreignHands", "Foreign hands, repeatedly"),
    ]

    static let actions: [(id: String, label: String)] = [
        ("answerInCharacter", "Answer in character"),
        ("pivotRecon", "Load the bench on them"),
        ("raiseServe", "Raise Serve for a minute"),
        ("tighten", "Raise the second sense"),
        ("burnThreads", "Burn the Knocktalk threads"),
        ("journalMark", "Mark it in the journal"),
    ]

    static func triggerLabel(_ id: String) -> String {
        triggers.first { $0.id == id }?.label ?? id
    }

    static func actionLabel(_ id: String) -> String {
        actions.first { $0.id == id }?.label ?? id
    }

    // MARK: - store

    private static let rulesKey = "conductorRules"
    private static let restUntilKey = "conductorRestUntil"
    private static let countKey = "conductorFiredCounts"

    static func loadRules() -> [Rule] {
        guard let data = UserDefaults.standard.data(
                forKey: rulesKey),
              let rules = try? JSONDecoder().decode(
                [Rule].self, from: data)
        else { return [] }
        return rules
    }

    static func saveRules(_ rules: [Rule]) {
        guard let data = try? JSONEncoder().encode(rules)
        else { return }
        UserDefaults.standard.set(data, forKey: rulesKey)
    }

    /// Two starter reflexes the first time the section is
    /// opened — present but inert until the master switch.
    static func seedIfNeeded() {
        guard UserDefaults.standard.data(forKey: rulesKey) == nil
        else { return }
        saveRules([
            Rule(id: UUID().uuidString,
                 name: "A honeydrop is taken → "
                    + "Load the bench on them",
                 trigger: "honeydrop", action: "pivotRecon",
                 enabled: true),
            Rule(id: UUID().uuidString,
                 name: "A new source knocks → "
                    + "Mark it in the journal",
                 trigger: "newSource", action: "journalMark",
                 enabled: true),
        ])
    }

    /// The rest base, by trigger class: the vault is
    /// the operator's own hand (short), anyKnock on
    /// a busy wire is weather (long).
    private static func baseRest(for trigger: String)
        -> TimeInterval {
        switch trigger {
        case "vault": return 60
        case "honeydrop", "fingerprinted": return 180
        case "anyKnock": return 600
        default: return 300
        }
    }

    private static func fireKey(_ rule: Rule,
                                _ fire: Fire) -> String {
        rule.id + "|" + (fire.host ?? "*")
    }

    private static func resting(_ rule: Rule,
                                _ fire: Fire) -> Bool {
        let until = UserDefaults.standard.dictionary(
            forKey: restUntilKey) as? [String: Double] ?? [:]
        guard let deadline = until[fireKey(rule, fire)]
        else { return false }
        return Date().timeIntervalSince1970 < deadline
    }

    /// Firings are counted per rule AND host, and
    /// the rest doubles per count, jittered ±25% —
    /// the old flat five minutes, identical for
    /// every rule and every host, was a metronome
    /// an observer could set a watch by, and the
    /// tenth honeydrop take from one host answered
    /// exactly like the first. Returns the count.
    @discardableResult
    private static func markFired(_ rule: Rule,
                                  _ fire: Fire) -> Int {
        let key = fireKey(rule, fire)
        var counts = UserDefaults.standard.dictionary(
            forKey: countKey) as? [String: Int] ?? [:]
        let count = (counts[key] ?? 0) + 1
        counts[key] = count
        UserDefaults.standard.set(counts, forKey: countKey)
        let doublings = min(count - 1, 4)
        let base = baseRest(for: rule.trigger)
            * Double(1 << doublings)
        let jitter = base * Double.random(in: -0.25...0.25)
        var until = UserDefaults.standard.dictionary(
            forKey: restUntilKey) as? [String: Double] ?? [:]
        until[key] = Date().timeIntervalSince1970
            + min(3600, base + jitter)
        UserDefaults.standard.set(until, forKey: restUntilKey)
        return count
    }

    // MARK: - evaluation

    private static var masterOn: Bool {
        UserDefaults.standard.bool(forKey: "conductorOn")
    }

    private static func evaluate(trigger: String, emcon: Emcon,
                                 fire: Fire) {
        guard masterOn else { return }
        for rule in loadRules()
        where rule.enabled && rule.trigger == trigger
            && !resting(rule, fire) {
            let count = markFired(rule, fire)
            // Escalation: the third firing against
            // the same host promotes a mere journal
            // mark to raising the second sense — a
            // reflex that has fired twice on one
            // host has earned a louder voice.
            var chosen = rule
            if count >= 3, rule.action == "journalMark" {
                chosen.action = "tighten"
                Journal.log("emcon", "conductor",
                            "reflex promoted — \(rule.name) "
                            + "has fired \(count) times on "
                            + "\(fire.host ?? "the wire"); a "
                            + "mark becomes the second sense")
            }
            let firing = chosen
            DispatchQueue.main.async {
                perform(rule: firing, emcon: emcon, fire: fire)
            }
        }
    }

    /// The tripwire funnel: knocks arrive already recorded,
    /// so a source whose only row in the log is this knock
    /// is, by the log's own evidence, new.
    static func onKnock(emcon: Emcon, source: String, port: Int,
                        proto: String, verdict: String,
                        mine: Bool) {
        guard masterOn, !mine else { return }
        let host = source.components(separatedBy: " ").first
            ?? source
        let fire = Fire(host: host, port: port, verdict: verdict)
        evaluate(trigger: "anyKnock", emcon: emcon, fire: fire)
        if proto == "TCP",
           Emcon.persona(forVerdict: verdict) != nil {
            evaluate(trigger: "fingerprinted", emcon: emcon,
                     fire: fire)
        }
        // Seen sources, kept as a set of the
        // conductor's own. "New" used to be
        // inferred from the display event log's
        // row count, so a source could read as new
        // again whenever the log turned over. The
        // set is seeded once from the log's current
        // hosts, so no known source re-fires as
        // new on the first run of the new memory.
        let seenKey = "conductorSeenSources"
        let firstRun = UserDefaults.standard.object(
            forKey: seenKey) == nil
        var seen = Set(UserDefaults.standard.stringArray(
            forKey: seenKey) ?? [])
        if firstRun {
            seen = Set(emcon.events.map {
                $0.source.components(separatedBy: " ").first
                    ?? $0.source })
        }
        if !seen.contains(host) {
            evaluate(trigger: "newSource", emcon: emcon,
                     fire: fire)
        }
        seen.insert(host)
        UserDefaults.standard.set(Array(seen),
                                  forKey: seenKey)
    }

    static func onVault(emcon: Emcon) {
        evaluate(trigger: "vault", emcon: emcon, fire: Fire())
    }

    /// The Cadence Seal's streak escalation calls
    /// here: right key, wrong hands, three verdicts
    /// running — the clone scenario the seal exists
    /// for, offered to any reflex the operator has
    /// armed against it.
    static func onForeignHands(emcon: Emcon, host: String) {
        evaluate(trigger: "foreignHands", emcon: emcon,
                 fire: Fire(host: host))
    }

    static func onHoneydrop(emcon: Emcon, peer: String) {
        // The peer arrives as "host:port" from the canary.
        var host: String? = peer
        var port: Int? = nil
        if let idx = peer.lastIndex(of: ":") {
            host = String(peer[..<idx])
            port = Int(peer[peer.index(after: idx)...])
        }
        evaluate(trigger: "honeydrop", emcon: emcon,
                 fire: Fire(host: host, port: port))
    }

    // MARK: - actions

    private static var serveWork: DispatchWorkItem?

    private static func perform(rule: Rule, emcon: Emcon,
                                fire: Fire) {
        var detail = ""
        switch rule.action {
        case "answerInCharacter":
            if let host = fire.host, let port = fire.port,
               let verdict = fire.verdict {
                emcon.escalateNow(source: host, port: port,
                                  verdict: verdict)
                detail = "the canary takes port \(port) "
                    + "in character"
            } else {
                detail = "no knock to answer — the line alone"
            }
        case "pivotRecon":
            if let mouth = emcon.mouth, let host = fire.host,
               let port = fire.port {
                mouth.reconHandoff = Mouth.ReconHandoff(
                    host: host, port: port, nonce: UUID())
                detail = "the bench is loaded on "
                    + "\(host):\(port) — firing stays yours"
            } else {
                detail = "no target to load — the line alone"
            }
        case "raiseServe":
            if let mouth = emcon.mouth {
                if mouth.serveRunning {
                    detail = "Serve was already up"
                } else {
                    mouth.startServeFromSettings()
                    serveWork?.cancel()
                    let work = DispatchWorkItem {
                        if mouth.serveRunning {
                            mouth.stopServe()
                        }
                    }
                    serveWork = work
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 60, execute: work)
                    detail = "Serve raised for sixty seconds"
                }
            } else {
                detail = "no mouth at hand — the line alone"
            }
        case "tighten":
            emcon.raiseSense(
                reason: "the conductor's rule: \(rule.name)")
            detail = "the second sense is up for 30 minutes"
        case "burnThreads":
            emcon.chat.burnNow()
            detail = "the Knocktalk threads are burned"
        default:
            detail = "marked"
        }
        Journal.log("emcon", "conductor",
                    "reflex fired — \(rule.name): " + detail)
    }
}
