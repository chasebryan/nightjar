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
/// Discipline: a master switch, a five-minute rest between
/// firings of the same rule, and every firing journaled —
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
    private static let firedKey = "conductorFired"
    private static let rest: TimeInterval = 300

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

    private static func resting(_ rule: Rule) -> Bool {
        let fired = UserDefaults.standard.dictionary(
            forKey: firedKey) as? [String: Double] ?? [:]
        guard let last = fired[rule.id] else { return false }
        return Date().timeIntervalSince1970 - last < rest
    }

    private static func markFired(_ rule: Rule) {
        var fired = UserDefaults.standard.dictionary(
            forKey: firedKey) as? [String: Double] ?? [:]
        fired[rule.id] = Date().timeIntervalSince1970
        UserDefaults.standard.set(fired, forKey: firedKey)
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
            && !resting(rule) {
            markFired(rule)
            DispatchQueue.main.async {
                perform(rule: rule, emcon: emcon, fire: fire)
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
        let rows = emcon.events.filter {
            ($0.source.components(separatedBy: " ").first
                ?? $0.source) == host
        }
        if rows.count <= 1 {
            evaluate(trigger: "newSource", emcon: emcon,
                     fire: fire)
        }
    }

    static func onVault(emcon: Emcon) {
        evaluate(trigger: "vault", emcon: emcon, fire: Fire())
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
                    host: host, port: port, nonce: "conductor")
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
