import SwiftUI

/// The steward: the watch officer above the conductor.
///
/// The conductor fires one reflex per event, faithfully and
/// without judgment. The steward holds the whole night in
/// view at once — posture, pattern, files, sense, the
/// journal's other senses — and thinks in SITUATIONS,
/// graded by confidence: a foreign nightjar-grade probe
/// from a new source is not three events, it is one visitor
/// of a recognizable kind, and how sure the steward is
/// decides how hard it answers.
///
/// It works under a charter the operator writes: a master
/// switch and a latitude. At OBSERVE it watches, assesses,
/// and files proposals. At ACT it may run its plans on the
/// perimeter, proportioned to confidence. At FULL it may
/// also approve its own drafted reflexes. It studies the
/// operator's own rulings and proposes charter amendments
/// to match; it keeps case files on the visitors who
/// matter; it watches the outcomes of its own plans and
/// grades itself in the same sealed log that grades
/// everything else. An autonomy you cannot audit would be
/// a second operator; this one is a subordinate with a
/// memory and a scorecard.
///
/// iOS still owns the body: the steward thinks while the
/// app is open. Its design center is the shift change —
/// every opening, it catches up on the sealed log, reads
/// the mirror, and leaves the perimeter in the best
/// posture it can justify in writing.
final class Steward: ObservableObject {
    struct Proposal: Codable, Identifiable {
        var id: String
        var when: Date
        /// "plan" — a held response, enactable in one tap.
        /// "rule" — a suggested conductor reflex.
        /// "charter" — a proposed latitude amendment.
        /// "posture" — a proposed raising of EMCON.
        /// "note" — information only (drift, cadence).
        var kind: String
        var title: String
        var detail: String
        /// Action ids for a plan: tighten / answer / pivot.
        var plan: [String] = []
        var host: String? = nil
        var port: Int? = nil
        var verdict: String? = nil
        var ruleTrigger: String? = nil
        var ruleAction: String? = nil
        /// For an anticipation proposal: the persona whose
        /// canary should be pre-staged on `port`.
        var prestagePersona: String? = nil
    }

    struct WatchOrder: Codable, Identifiable {
        var id: String
        var name: String
        var host: String = ""
        var port: String = ""
        var verdict: String = ""
        var action: String = "tighten"
        var enabled: Bool = true
    }

    struct Watch: Codable {
        var host: String
        var situation: String
        var when: Date
        var resolved: Bool = false
    }

    struct Case: Codable, Identifiable {
        var id: String
        var hosts: [String]
        var opened: Date
        var lastActivity: Date
        var entries: [String] = []
        var open: Bool = true
    }

    @Published private(set) var assessment =
        L("The steward has not taken a shift yet.")
    @Published private(set) var mirrorLine = ""
    @Published private(set) var proposals: [Proposal] = []
    /// The one collection the section edits in place
    /// (bindings, append, removeAll) — hence a public setter,
    /// where its siblings are written only through methods.
    @Published var orders: [WatchOrder] = []
    @Published private(set) var cases: [Case] = []

    private var watches: [Watch] = []
    private var filesCache: [ProberFile] = []
    private var filesCacheAt = Date.distantPast
    private var companyUntil: Date?

    init() {
        proposals = Self.loadJSON(Proposal.self,
                                  key: Self.proposalsKey) ?? []
        orders = Self.loadJSON(WatchOrder.self,
                               key: Self.ordersKey) ?? []
        watches = Self.loadJSON(Watch.self,
                                key: Self.watchesKey) ?? []
        cases = Self.loadJSON(Case.self,
                              key: Self.casesKey) ?? []
    }

    // MARK: - charter

    static var on: Bool {
        UserDefaults.standard.bool(forKey: "stewardOn")
    }

    /// "observe" | "act" | "full" — what the charter allows.
    static var latitude: String {
        UserDefaults.standard.string(forKey: "stewardLatitude")
            ?? "observe"
    }

    private var mayAct: Bool {
        Self.latitude == "act" || Self.latitude == "full"
    }

    // MARK: - persistence

    private static let proposalsKey = "stewardProposals"
    private static let ordersKey = "stewardOrders"
    private static let watchesKey = "stewardWatches"
    private static let casesKey = "stewardCases"
    private static let firedKey = "stewardFired"
    private static let shiftKey = "stewardLastShift"
    private static let dismissalsKey = "stewardDismissals"
    private static let rest: TimeInterval = 3600

    private static func loadJSON<T: Codable>(_ type: T.Type,
                                             key: String)
        -> [T]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                [T].self, from: data)
        else { return nil }
        return decoded
    }

    private static func saveJSON<T: Codable>(_ value: [T],
                                             key: String) {
        guard let data = try? JSONEncoder().encode(value)
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func saveProposals() {
        Self.saveJSON(proposals, key: Self.proposalsKey)
    }

    func saveOrders() {
        Self.saveJSON(orders, key: Self.ordersKey)
    }

    private func saveWatches() {
        Self.saveJSON(watches, key: Self.watchesKey)
    }

    private func saveCases() {
        Self.saveJSON(cases, key: Self.casesKey)
    }

    private func resting(_ key: String,
                         rest: TimeInterval = Steward.rest)
        -> Bool {
        let fired = UserDefaults.standard.dictionary(
            forKey: Self.firedKey) as? [String: Double] ?? [:]
        guard let last = fired[key] else { return false }
        return Date().timeIntervalSince1970 - last < rest
    }

    private func markFired(_ key: String) {
        var fired = UserDefaults.standard.dictionary(
            forKey: Self.firedKey) as? [String: Double] ?? [:]
        fired[key] = Date().timeIntervalSince1970
        UserDefaults.standard.set(fired, forKey: Self.firedKey)
    }

    // MARK: - dismissal learning

    /// Deviation notes the operator has dismissed, by their
    /// exact text. Home-turf consults this before flagging —
    /// a correction, recorded, is how the pattern learns the
    /// operator's judgment as well as the wire's habits.
    static func isDismissed(note: String) -> Bool {
        let dismissed = UserDefaults.standard.stringArray(
            forKey: dismissalsKey) ?? []
        return dismissed.contains(note)
    }

    static func addDismissal(note: String) {
        var dismissed = UserDefaults.standard.stringArray(
            forKey: dismissalsKey) ?? []
        guard !dismissed.contains(note) else { return }
        dismissed.append(note)
        UserDefaults.standard.set(dismissed, forKey: dismissalsKey)
        Journal.log("steward", "dismissal",
                    "the operator dismissed a deviation and "
                    + "the pattern learned it: " + note)
    }

    static var dismissalCount: Int {
        (UserDefaults.standard.stringArray(forKey: dismissalsKey)
            ?? []).count
    }

    static func clearDismissals() {
        UserDefaults.standard.removeObject(forKey: dismissalsKey)
        Journal.log("steward", "dismissal",
                    "all dismissals restored — the pattern "
                    + "flags everything again")
    }

    // MARK: - the world in one view

    private func files(emcon: Emcon) -> [ProberFile] {
        if Date().timeIntervalSince(filesCacheAt) > 60 {
            filesCache = ProberFiles.build(events: emcon.events)
            filesCacheAt = Date()
        }
        return filesCache
    }

    /// The current read of the night, in sentences an
    /// operator can hold. Refreshed on shift changes, on
    /// situations, and whenever the section is opened.
    func refresh(emcon: Emcon) {
        var parts: [String] = []
        parts.append(emcon.active
            ? (emcon.isAway
                ? L("EMCON is up, away from home turf.")
                : L("EMCON is up on home turf."))
            : L("EMCON is standing down."))
        if emcon.senseActive {
            parts.append(L("The second sense is raised."))
        }
        if let until = companyUntil, until > Date() {
            parts.append(L("Company: a paired operator's flare was in range recently."))
        }
        if emcon.hometurfReady {
            let n = emcon.hometurfNotes.count
            parts.append(n == 0
                ? L("The home pattern holds — nothing off it.")
                : String(format: L("%lld deviation(s) off the home pattern tonight."),
                         n))
        } else if emcon.homeSubnet != nil {
            parts.append(String(format: L("The home pattern is still learning (%lld of 3 nights)."),
                                emcon.hometurf.nights))
        }
        let changed = files(emcon: emcon)
            .filter { ProberFiles.changed($0) }.count
        if changed > 0 {
            parts.append(String(format: L("%lld prober file(s) have unreviewed changes."),
                                changed))
        }
        let openCases = cases.filter { $0.open }.count
        if openCases > 0 {
            parts.append(String(format: L("%lld case file(s) open."),
                                openCases))
        }
        if proposals.count > 0 {
            parts.append(String(format: L("%lld proposal(s) await your judgment."),
                                proposals.count))
        }
        assessment = parts.joined(separator: " ")
        mirrorLine = Self.composeMirror(emcon: emcon)
    }

    /// The wire's-eye view: how the house presents to
    /// whoever is looking at it, composed from what the
    /// wire itself has said back.
    private static func composeMirror(emcon: Emcon) -> String {
        var parts: [String] = []
        parts.append(emcon.active
            ? L("EMCON is up and the tripwire is listening")
            : L("EMCON is down"))
        let doors = Set(emcon.events.map { $0.port }).count
        if doors > 0 {
            parts.append(String(format: L("%lld door(s) have been tried from the wire"),
                                doors))
        }
        if let top = CanaryLessons.all().first {
            parts.append(String(format: L("probers ask your doors for %@ most"),
                                top.value))
        }
        if let persona = emcon.mouth?.canary.runningPersona {
            parts.append(String(format: L("the canary is answering as %@"),
                                persona.uppercased()))
        }
        return String(format: L("From the wire: %@."),
                      parts.joined(separator: "; "))
    }

    // MARK: - judgment

    /// Confidence, scored from the evidence itself — every
    /// factor named, so the reasoning can be audited like
    /// everything else the steward writes.
    private func confidence(nightjarGrade: Bool,
                            file: ProberFile?,
                            newSource: Bool, offPattern: Bool,
                            host: String,
                            emcon: Emcon)
        -> (points: Int, band: String, factors: [String]) {
        var points = 0
        var factors: [String] = []
        if nightjarGrade {
            points += 40
            factors.append(L("a nightjar-grade first word"))
        }
        if let file = file, file.drops > 0 {
            points += 35
            factors.append(String(format: L("has taken %lld honeydrop(s) before"),
                                  file.drops))
        }
        if newSource {
            points += 15
            factors.append(L("no file history"))
        }
        if offPattern {
            points += 15
            factors.append(L("off the learned pattern"))
        }
        if let file = file,
           file.ports.values.reduce(0, +) >= 5 {
            points += 10
            factors.append(String(format: L("a repeat visitor (%lld knocks on file)"),
                                  file.ports.values.reduce(0, +)))
        }
        if emcon.senseActive {
            points += 10
            factors.append(L("the sense is already up"))
        }
        // Its own graded past bends the price — the
        // track record, read back at last.
        let track = Self.trackRecord(for: host)
        let proved = track["confirmed"] ?? 0
        let quiet = track["quiet"] ?? 0
        if proved > 0 {
            points += min(15, 5 * proved)
            factors.append(String(format: L("plans against it proved out ×%lld"),
                                  proved))
        }
        if quiet >= 2 {
            points -= min(15, 5 * quiet)
            factors.append(String(format: L("plans against it graded quiet ×%lld — cried wolf here"),
                                  quiet))
        }
        points = max(0, points)
        let band = points >= 65 ? "high"
            : (points >= 35 ? "medium" : "low")
        return (points, band, factors)
    }

    // MARK: - situations

    /// Fed every knock the funnel sees, after the conductor.
    /// The operator's own watch orders evaluate first —
    /// their brief outranks the steward's ideas — then the
    /// built-in situations, each read against the whole
    /// night: the file on its source, the state of the
    /// pattern, the sense, and what is already predicted.
    func onKnock(emcon: Emcon, source: String, port: Int,
                 proto: String, verdict: String, mine: Bool) {
        guard Self.on, !mine else { return }
        let host = source.components(separatedBy: " ").first
            ?? source
        let file = files(emcon: emcon)
            .first { $0.host == host }
        if let file = file, file.isSelf { return }

        // Outcome watch: a visitor a plan was executed
        // against has come back inside the day.
        resolveWatches(host: host,
            outcome: L("returned within the day — still interested"))

        // The operator's watch orders.
        for order in orders where order.enabled {
            let hostMatch = order.host.isEmpty
                || host.contains(order.host)
            let portMatch = order.port.isEmpty
                || Int(order.port) == port
            let verdictMatch = order.verdict.isEmpty
                || verdict.lowercased().contains(
                    order.verdict.lowercased())
            guard hostMatch, portMatch, verdictMatch,
                  !resting("order:\(order.id)", rest: 1800)
            else { continue }
            markFired("order:\(order.id)")
            respond(
                situation: String(format: L("watch order: %@"),
                                  order.name),
                evidence: String(format: L("%@ on port %lld spoke “%@” — the operator's own order covers this"),
                                  host, port, verdict),
                plan: [order.action],
                confidence: (100, "high",
                             [L("the operator wrote this order")]),
                emcon: emcon, host: host, port: port,
                verdict: verdict, file: file)
        }

        let nightjarGrade = verdict.hasPrefix(
            "nightjar probe:")
        let rows = emcon.events.filter {
            ($0.source.components(separatedBy: " ").first
                ?? $0.source) == host
        }
        let newSource = rows.count <= 1
        let offPattern = emcon.hometurfNotes.contains {
            $0.contains(host) || $0.contains("port \(port)")
        }
        let score = confidence(
            nightjarGrade: nightjarGrade, file: file,
            newSource: newSource, offPattern: offPattern,
            host: host,
            emcon: emcon)

        // The taker returns: a source with drops in its
        // file is knocking again. Whatever it wants this
        // time, it has already shown its hands.
        if let file = file, file.drops > 0,
           !resting("taker") {
            markFired("taker")
            respond(
                situation: L("the taker returns"),
                evidence: String(format: L("%@ has taken %lld honeydrop(s) before and is knocking again on port %lld"),
                                  host, file.drops, port),
                plan: ["pivot"], confidence: score,
                emcon: emcon, host: host, port: port,
                verdict: verdict, file: file)
        }

        // A colleague-grade prober: this instrument's own
        // signature in a stranger's hand, from a new source
        // or at an off-pattern door.
        if nightjarGrade, proto == "TCP",
           newSource || offPattern, !resting("colleague") {
            markFired("colleague")
            respond(
                situation: L("a colleague-grade prober"),
                evidence: String(format: L("%@ spoke %@ on port %lld — nightjar-grade tooling, %@"),
                                  host, verdict, port,
                                  newSource ? L("a source never seen before")
                                            : L("at an off-pattern door")),
                plan: ["tighten", "answer", "pivot"],
                confidence: score, emcon: emcon, host: host,
                port: port, verdict: verdict, file: file)
            suggestTakerRule(emcon: emcon)
        }

        // A pattern-break cluster: three deviations in one
        // night is not three facts, it is one changed house.
        if emcon.hometurfNotes.count >= 3,
           !resting("cluster") {
            markFired("cluster")
            let extra = min(emcon.hometurfNotes.count - 3, 3)
            respond(
                situation: L("a pattern-break cluster"),
                evidence: String(format: L("%lld deviations off the learned home pattern tonight"),
                                  emcon.hometurfNotes.count),
                plan: ["tighten"],
                confidence: (35 + extra * 10,
                             extra >= 3 ? "high" : "medium",
                             [String(format: L("%lld deviations tonight"),
                                      emcon.hometurfNotes.count)]),
                emcon: emcon, host: nil, port: nil,
                verdict: nil, file: nil)
        }

        anticipate(emcon: emcon, file: file, host: host,
                   knockedPort: port)
        refresh(emcon: emcon)
    }

    /// Anticipation: a filed visitor's own history is a
    /// sequence — doors tried in an order, weighted by how
    /// often. When they knock the door before a door they
    /// favor, the steward reads the sequence forward and
    /// pre-stages the canary at the predicted door, through
    /// the same hand-off machinery an answer uses.
    private func anticipate(emcon: Emcon, file: ProberFile?,
                            host: String, knockedPort: Int) {
        guard let file = file,
              file.drops > 0
                || file.ports.values.reduce(0, +) >= 3,
              !resting("anticipation:\(host)", rest: 1800)
        else { return }
        let sequence = file.portsByTraffic.map { $0.port }
        guard let idx = sequence.firstIndex(of: knockedPort),
              idx + 1 < sequence.count else { return }
        let next = sequence[idx + 1]
        guard let persona = Self.persona(forPort: next)
        else { return }
        markFired("anticipation:\(host)")
        let evidence = String(format: L("%@'s own sequence — %@ — says port %lld comes after %lld"),
            host,
            sequence.map(String.init)
                .joined(separator: " → "),
            next, knockedPort)
        if mayAct {
            emcon.prestageCanary(port: next, persona: persona,
                                 source: host)
            Journal.log("steward", "plan",
                        "ANTICIPATION: \(evidence). The "
                        + "\(persona) canary is pre-staged on "
                        + "port \(next) under latitude "
                        + "\(Self.latitude).")
            fileCase(situation: L("anticipation"), host: host,
                     evidence: evidence, file: file)
        } else {
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "plan",
                title: String(format: L("Anticipation: %@"),
                              host),
                detail: evidence + String(format: L(". Proposed: pre-stage the %@ canary on port %lld. Held under latitude observe."),
                                          persona, next),
                host: host, port: next,
                prestagePersona: persona), at: 0)
            saveProposals()
            Journal.log("steward", "observe",
                        "ANTICIPATION: \(evidence). "
                        + "Pre-staging the \(persona) canary "
                        + "on port \(next) proposed and held "
                        + "for the operator.")
        }
    }

    private static func persona(forPort port: Int)
        -> String? {
        switch port {
        case 22: return "ssh"
        case 80, 8080: return "http"
        case 1883: return "mqtt"
        case 25: return "smtp"
        default: return nil
        }
    }

    // MARK: - answering a situation

    /// A situation, answered in proportion to confidence:
    /// at an acting latitude a high-confidence situation
    /// runs its whole plan, a medium one its first step,
    /// and a low one is journaled and left to the operator —
    /// force is earned by evidence. Under observe, every
    /// plan is held as a proposal. Either way the reasoning,
    /// the score, and its factors enter the sealed log, and
    /// an executed plan leaves an outcome watch behind.
    private func respond(situation: String, evidence: String,
                         plan: [String],
                         confidence: (points: Int, band: String,
                                      factors: [String]),
                         emcon: Emcon, host: String?,
                         port: Int?, verdict: String?,
                         file: ProberFile?) {
        let scoreText = String(format: L("confidence %@ (%lld): %@"),
            L(confidence.band), confidence.points,
            confidence.factors.isEmpty
                ? L("no strong factors")
                : confidence.factors.joined(separator: ", "))
        let planText = plan.map(Self.actionLabel)
            .joined(separator: " + ")
        if let host = host {
            fileCase(situation: situation, host: host,
                     evidence: evidence + " [" + scoreText + "]",
                     file: file)
        }
        if mayAct {
            let effective: [String]
            switch confidence.band {
            case "high": effective = plan
            case "medium": effective = Array(plan.prefix(1))
            default: effective = []
            }
            if effective.isEmpty {
                Journal.log("steward", "observe",
                            "SITUATION \(situation): "
                            + "\(evidence). \(scoreText). "
                            + "Held from acting on confidence "
                            + "alone — the plan would have been "
                            + "\(planText).")
                return
            }
            var done: [String] = []
            for action in effective {
                if perform(action: action, emcon: emcon,
                           host: host, port: port,
                           verdict: verdict) {
                    done.append(Self.actionLabel(action))
                }
            }
            Journal.log("steward", "plan",
                        "SITUATION \(situation): \(evidence). "
                        + "\(scoreText). Plan: \(planText). "
                        + "Executed under latitude "
                        + "\(Self.latitude) at this confidence: "
                        + (done.isEmpty ? "nothing could be "
                            + "carried out" : done.joined(
                                separator: ", ")) + ".")
            if let host = host {
                watches.append(Watch(host: host,
                                     situation: situation,
                                     when: Date()))
                saveWatches()
            }
        } else {
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "plan", title: situation,
                detail: evidence + " " + scoreText
                    + String(format: L(". Proposed: %@. Held under latitude observe."),
                             planText),
                plan: plan, host: host, port: port,
                verdict: verdict), at: 0)
            saveProposals()
            Journal.log("steward", "observe",
                        "SITUATION \(situation): \(evidence). "
                        + "\(scoreText). Plan proposed "
                        + "(\(planText)) and held for the "
                        + "operator — latitude is observe.")
        }
        refresh(emcon: emcon)
    }

    /// When a colleague-grade prober appears and no reflex
    /// yet loads the bench on a taken drop, the steward
    /// drafts one. At FULL latitude it approves its own
    /// draft — and journals that it did.
    private func suggestTakerRule(emcon: Emcon) {
        let covered = Conductor.loadRules().contains {
            $0.trigger == "honeydrop" && $0.action == "pivotRecon"
        }
        let alreadyFiled = proposals.contains {
            $0.kind == "rule" && $0.ruleTrigger == "honeydrop"
        }
        guard !covered, !alreadyFiled else { return }
        let rule = Conductor.Rule(
            id: UUID().uuidString,
            name: "A honeydrop is taken → "
                + "Load the bench on them",
            trigger: "honeydrop", action: "pivotRecon",
            enabled: true)
        if Self.latitude == "full" {
            var rules = Conductor.loadRules()
            rules.append(rule)
            Conductor.saveRules(rules)
            Journal.log("steward", "plan",
                        "The steward approved its own drafted "
                        + "reflex under latitude full: "
                        + "honeydrop → load the bench.")
        } else {
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "rule",
                title: L("Drafted reflex: the taker rule"),
                detail: L("Colleague-grade probing has begun and no reflex loads the bench when a honeydrop is taken. Approving adds it to the conductor."),
                ruleTrigger: "honeydrop",
                ruleAction: "pivotRecon"), at: 0)
            saveProposals()
            Journal.log("steward", "observe",
                        "The steward drafted a reflex "
                        + "(honeydrop → load the bench) and "
                        + "filed it for approval.")
        }
        refresh(emcon: emcon)
    }

    private static func actionLabel(_ action: String) -> String {
        switch action {
        case "tighten": return L("raise the second sense")
        case "answer": return L("answer in character")
        case "pivot": return L("load the bench on them")
        default: return action
        }
    }

    /// Carry out one plan action through the organs. False
    /// when the action had nothing to act on.
    @discardableResult
    private func perform(action: String, emcon: Emcon,
                         host: String?, port: Int?,
                         verdict: String?) -> Bool {
        switch action {
        case "tighten":
            emcon.raiseSense(reason: L("the steward's plan"))
            return true
        case "answer":
            guard let host = host, let port = port,
                  let verdict = verdict else { return false }
            emcon.escalateNow(source: host, port: port,
                              verdict: verdict)
            return true
        case "pivot":
            guard let mouth = emcon.mouth, let host = host,
                  let port = port else { return false }
            mouth.reconHandoff = Mouth.ReconHandoff(
                host: host, port: port, nonce: UUID())
            return true
        default:
            return false
        }
    }

    // MARK: - case files

    /// Situations accumulate into cases: one file per
    /// visitor — merged across addresses the same-hands
    /// correlation links — holding every situation, plan,
    /// and outcome in the order they happened. Alerts are
    /// weather; a case is a climate record on one visitor.
    private func fileCase(situation: String, host: String,
                          evidence: String, file: ProberFile?) {
        var hosts: Set<String> = [host]
        if let file = file {
            hosts.formUnion(file.links.map { $0.host })
        }
        let stamp = Date().formatted(date: .omitted,
                                     time: .shortened)
        let entry = String(format: L("%@ — %@: %@"),
                           stamp, situation, evidence)
        if let idx = cases.firstIndex(where: {
            $0.open && !Set($0.hosts).isDisjoint(with: hosts)
        }) {
            cases[idx].hosts = Array(
                Set(cases[idx].hosts).union(hosts)).sorted()
            cases[idx].entries.append(entry)
            if cases[idx].entries.count > 50 {
                cases[idx].entries.removeFirst(
                    cases[idx].entries.count - 50)
            }
            cases[idx].lastActivity = Date()
        } else {
            cases.insert(Case(id: UUID().uuidString,
                              hosts: Array(hosts).sorted(),
                              opened: Date(),
                              lastActivity: Date(),
                              entries: [entry]), at: 0)
            Journal.log("steward", "case",
                        "case opened on \(host) — \(situation)")
            if cases.count > 20 {
                cases = Array(cases.prefix(20))
            }
        }
        saveCases()
    }

    func closeCase(_ entry: Case) {
        guard let idx = cases.firstIndex(
            where: { $0.id == entry.id }) else { return }
        cases[idx].open = false
        saveCases()
        Journal.log("steward", "case",
                    "case closed on "
                    + (entry.hosts.first ?? "unknown")
                    + " by the operator")
    }

    // MARK: - self-grading

    /// Resolve every open outcome watch on a host: a plan
    /// was executed against them, and now something is
    /// known about whether it mattered.
    private func resolveWatches(host: String, outcome: String) {
        var changed = false
        for i in watches.indices
        where !watches[i].resolved && watches[i].host == host {
            watches[i].resolved = true
            changed = true
            Self.recordOutcome(host: host, outcome: outcome)
            Journal.log("steward", "grade",
                        "plan record — \(watches[i].situation) "
                        + "on \(host): \(outcome).")
        }
        if changed { saveWatches() }
    }

    // MARK: - all its senses

    /// The journal's event feed: everything the instrument
    /// writes, the steward also hears — drift on a watched
    /// address, a paired operator's flare in the air, a
    /// drop taken while a plan's outcome was still open.
    func consume(_ event: NightEvent) {
        guard Self.on else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch (event.module, event.kind) {
            case ("dossier", "drift"):
                let host = event.text
                    .components(separatedBy: " ")
                    .first { token in
                        token.contains(".") && token.allSatisfy {
                            $0.isNumber || $0 == "."
                        }
                    } ?? L("a watched address")
                let title = String(format: L("Dossier drift: %@"),
                                   host)
                guard !self.proposals.contains(
                    where: { $0.title == title }) else { return }
                self.proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "note", title: title,
                    detail: event.text + L(" Filed from the journal the moment it was written — re-baseline it in the dossier if the change is explained, or load the bench on it if it is not.")),
                    at: 0)
                self.saveProposals()
                Journal.log("steward", "observe",
                            "The steward noted dossier drift "
                            + "on \(host) and filed it.")
            case ("listen", "flare"):
                self.companyUntil = Date()
                    .addingTimeInterval(600)
            case ("canary", "honeydrop"):
                // "drop taken by host:port — note"
                let peer = event.text
                    .replacingOccurrences(
                        of: "drop taken by ", with: "")
                    .components(separatedBy: " ").first ?? ""
                let host = peer.lastIndex(of: ":").map {
                    String(peer[..<$0]) } ?? peer
                if !host.isEmpty {
                    self.resolveWatches(
                        host: host,
                        outcome: L("confirmed — the visitor bit the canary too"))
                    if let idx = self.cases.firstIndex(
                        where: { $0.open
                            && $0.hosts.contains(host) }) {
                        self.cases[idx].entries.append(
                            L("took the canary's drop — ")
                            + event.text)
                        self.cases[idx].lastActivity = Date()
                        self.saveCases()
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - proposals, in the operator's hands

    // MARK: - the rulings tally

    /// The operator's rulings, counted where they
    /// happen and kept. The study below used to
    /// re-derive them by parsing journal prose over
    /// the last 1000 events — a window a busy house
    /// outgrows, so the history silently reset —
    /// and anticipation enactments, which log a
    /// different sentence, were never counted at
    /// all. The tally forgets nothing.
    private static let tallyKey = "stewardRulings"

    static func rulings() -> [String: [String: Int]] {
        UserDefaults.standard.dictionary(forKey: tallyKey)
            as? [String: [String: Int]] ?? [:]
    }

    private static func recordRuling(_ title: String,
                                     enacted: Bool) {
        guard !title.isEmpty else { return }
        var all = rulings()
        var entry = all[title] ?? [:]
        entry[enacted ? "enacted" : "dismissed",
              default: 0] += 1
        all[title] = entry
        UserDefaults.standard.set(all, forKey: tallyKey)
    }

    // MARK: - the track record

    /// What its own graded plans came to, per host.
    /// The outcome watches always resolved into
    /// journal lines — a scorecard nobody read.
    /// Now they resolve into this tally, and
    /// confidence() reads it back: a host whose
    /// plans proved out earns belief, and a host
    /// whose plans keep grading quiet has cried
    /// wolf here before.
    private static let trackKey = "stewardTrack"

    static func trackRecord(for host: String)
        -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: trackKey)
            as? [String: [String: Int]])?[host] ?? [:]
    }

    static func recordGrade(host: String, kind: String) {
        var all = UserDefaults.standard.dictionary(
            forKey: trackKey) as? [String: [String: Int]]
            ?? [:]
        var entry = all[host] ?? [:]
        entry[kind, default: 0] += 1
        all[host] = entry
        UserDefaults.standard.set(all, forKey: trackKey)
    }

    private static func recordOutcome(host: String,
                                      outcome: String) {
        if outcome.hasPrefix("confirmed") {
            recordGrade(host: host, kind: "confirmed")
        } else if outcome.hasPrefix("returned") {
            recordGrade(host: host, kind: "returned")
        } else if outcome.contains("quiet") {
            recordGrade(host: host, kind: "quiet")
        }
    }

    func enact(_ proposal: Proposal, emcon: Emcon,
               mouth: Mouth) {
        switch proposal.kind {
        case "rule":
            if let trigger = proposal.ruleTrigger,
               let action = proposal.ruleAction {
                var rules = Conductor.loadRules()
                rules.append(Conductor.Rule(
                    id: UUID().uuidString,
                    name: Conductor.triggerLabel(trigger)
                        + " → " + Conductor.actionLabel(action),
                    trigger: trigger, action: action,
                    enabled: true))
                Conductor.saveRules(rules)
                Journal.log("steward", "plan",
                            "The operator approved the "
                            + "steward's drafted reflex: "
                            + "\(proposal.title).")
            }
        case "charter":
            UserDefaults.standard.set("act",
                                      forKey: "stewardLatitude")
            Journal.log("steward", "plan",
                        "The operator amended the charter: "
                        + "\(proposal.title). Latitude is now "
                        + "act.")
        case "posture":
            if !emcon.active {
                emcon.activate(mouth: mouth)
            }
            Journal.log("steward", "plan",
                        "The operator enacted a held posture "
                        + "proposal: \(proposal.title).")
        case "plan":
            if let persona = proposal.prestagePersona,
               let port = proposal.port,
               let host = proposal.host {
                emcon.prestageCanary(port: port,
                                     persona: persona,
                                     source: host)
                Journal.log("steward", "plan",
                            "The operator enacted an "
                            + "anticipation — the \(persona) "
                            + "canary is pre-staged on port "
                            + "\(port) for \(host).")
                Self.recordRuling(proposal.title,
                                  enacted: true)
            } else {
                var done: [String] = []
                for action in proposal.plan {
                    if perform(action: action, emcon: emcon,
                               host: proposal.host,
                               port: proposal.port,
                               verdict: proposal.verdict) {
                        done.append(Self.actionLabel(action))
                    }
                }
                Journal.log("steward", "plan",
                            "The operator enacted a held plan "
                            + "— \(proposal.title): "
                            + (done.isEmpty ? "nothing could "
                                + "be carried out" : done.joined(
                                    separator: ", ")) + ".")
                Self.recordRuling(proposal.title,
                                  enacted: true)
                if let host = proposal.host {
                    watches.append(Watch(host: host,
                                         situation: proposal.title,
                                         when: Date()))
                    saveWatches()
                }
            }
        default:
            break
        }
        proposals.removeAll { $0.id == proposal.id }
        saveProposals()
        refresh(emcon: emcon)
    }

    func dismissProposal(_ proposal: Proposal) {
        proposals.removeAll { $0.id == proposal.id }
        saveProposals()
        Journal.log("steward", "observe",
                    "The operator dismissed a proposal: "
                    + proposal.title + ".")
        Self.recordRuling(proposal.title, enacted: false)
    }

    // MARK: - the shift change

    /// Called at launch and at every return to the
    /// foreground (beside the dead hand's own evaluation):
    /// the catch-up. What accumulated in the sealed log
    /// since the last shift is counted and reported; open
    /// outcome watches past their day are graded quiet; the
    /// operator's own patterns — their usual posture hour,
    /// the rulings they keep making the same way — are
    /// studied and returned as charter proposals; the last
    /// maneuvers grade is checked for staleness; and the
    /// mirror is read aloud into the log.
    func shiftChange(emcon: Emcon) {
        guard Self.on else { return }
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: Self.shiftKey)
        defaults.set(Date().timeIntervalSince1970,
                     forKey: Self.shiftKey)
        // Grade the watches whose day has run out.
        var gradedQuiet = false
        for i in watches.indices
        where !watches[i].resolved
            && Date().timeIntervalSince(watches[i].when)
                > 24 * 3600 {
            watches[i].resolved = true
            gradedQuiet = true
            Self.recordGrade(host: watches[i].host,
                             kind: "quiet")
            Journal.log("steward", "grade",
                        "plan record — \(watches[i].situation) "
                        + "on \(watches[i].host): no return in "
                        + "a day — quiet since the plan.")
        }
        if gradedQuiet { saveWatches() }
        if last > 0 {
            let since = Date(timeIntervalSince1970: last)
            let events = Journal.events(limit: 1000)
                .filter { $0.when > since }
            func count(_ module: String, _ kind: String) -> Int {
                events.filter {
                    $0.module == module && $0.kind == kind
                }.count
            }
            var parts: [String] = []
            let knocks = count("emcon", "knock")
            if knocks > 0 {
                parts.append(String(format: L("%lld knock(s)"),
                                    knocks))
            }
            let drops = count("canary", "honeydrop")
            if drops > 0 {
                parts.append(String(format: L("%lld honeydrop(s) TAKEN"),
                                    drops))
            }
            let deviations = count("emcon", "hometurf")
            if deviations > 0 {
                parts.append(String(format: L("%lld deviation(s)"),
                                    deviations))
            }
            let plans = count("steward", "plan")
            if plans > 0 {
                parts.append(String(format: L("%lld steward action(s)"),
                                    plans))
            }
            if !parts.isEmpty {
                let line = String(format: L("While you were gone: %@."),
                                  parts.joined(separator: ", "))
                assessment = line
                Journal.log("steward", "shift", line)
            }
            let mirror = Self.composeMirror(emcon: emcon)
            Journal.log("steward", "mirror", mirror)
            // Maneuvers cadence.
            let all = Journal.events(limit: 1000)
            let lastManeuvers = all
                .filter { $0.module == "emcon"
                    && $0.kind == "maneuvers" }
                .map { $0.when }.max()
            let stale = lastManeuvers.map {
                Date().timeIntervalSince($0) > 24 * 3600
            } ?? true
            let staleTitle = L("Night maneuvers are stale")
            if stale, !proposals.contains(
                where: { $0.kind == "note"
                    && $0.title == staleTitle }) {
                proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "note", title: staleTitle,
                    detail: L("The last graded self-test is over a day old (or never ran). The maneuvers live in the EMCON tab when you want them.")), at: 0)
                saveProposals()
            }
            studyOperator(emcon: emcon, all: all)
        }
        refresh(emcon: emcon)
    }

    /// The operator is evidence too. Two studies, both
    /// returned as proposals and never imposed:
    /// (1) rulings — a situation whose held plans the
    /// operator has enacted three times and never dismissed
    /// earns a charter amendment: trust that call at Act;
    /// (2) rhythm — the hour EMCON usually rises, learned
    /// from the posture lines themselves; when that hour
    /// arrives with EMCON down, the steward proposes the
    /// raising (at FULL, it simply raises it and writes
    /// down that it did).
    private func studyOperator(emcon: Emcon,
                               all: [NightEvent]) {
        if Self.latitude == "observe" {
            // The rulings tally — counted where the
            // rulings happen, kept without a window.
            var enacted: [String: Int] = [:]
            var dismissed: [String: Int] = [:]
            for (title, entry) in Self.rulings() {
                if let n = entry["enacted"], n > 0 {
                    enacted[title] = n
                }
                if let n = entry["dismissed"], n > 0 {
                    dismissed[title] = n
                }
            }
            for (situation, count) in enacted
            where count >= 3 && (dismissed[situation] ?? 0) == 0 {
                let title = String(format: L("Charter amendment: trust the %@ call"),
                                   situation)
                guard !proposals.contains(
                    where: { $0.title == title }) else { continue }
                proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "charter", title: title,
                    detail: String(format: L("You have enacted the steward's held plan for “%@” %lld times and never dismissed one. Amending the charter to Act lets it run that judgment without waiting on you — every act still journaled, still graded."),
                                   situation, count)),
                    at: 0)
                saveProposals()
                Journal.log("steward", "observe",
                            "The steward studied the rulings "
                            + "and proposed a charter "
                            + "amendment: trust the \(situation) "
                            + "call.")
            }
        }
        // Rhythm: the usual posture hour.
        let risings = all.filter {
            $0.module == "emcon" && $0.kind == "posture"
                && $0.text.hasPrefix("EMCON active")
        }
        guard risings.count >= 3, !emcon.active else { return }
        var hours: [Int: Int] = [:]
        for event in risings {
            let hour = Calendar.current.component(.hour,
                                                  from: event.when)
            hours[hour, default: 0] += 1
        }
        guard let modal = hours.max(by: {
            $0.value < $1.value
        })?.key else { return }
        let nowHour = Calendar.current.component(.hour,
                                                 from: Date())
        guard nowHour == modal,
              !proposals.contains(where: {
                  $0.kind == "posture"
              }) else { return }
        if Self.latitude == "full", let mouth = emcon.mouth {
            emcon.activate(mouth: mouth)
            Journal.log("steward", "plan",
                        "The steward raised EMCON at the "
                        + "operator's usual hour (\(modal):00) "
                        + "under latitude full — learned from "
                        + "\(risings.count) risings on record.")
        } else if !resting("postureHour", rest: 12 * 3600) {
            markFired("postureHour")
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "posture",
                title: L("Your usual hour: raise EMCON"),
                detail: String(format: L("EMCON has risen at %lld:00 more than any other hour (%lld risings on record) and it is down now. Enacting raises it."),
                               modal, risings.count)), at: 0)
            saveProposals()
            Journal.log("steward", "observe",
                        "The steward noticed the operator's "
                        + "usual posture hour (\(modal):00) "
                        + "and proposed raising EMCON.")
        }
    }
}

// MARK: - the EMCON section

struct StewardSectionView: View {
    @ObservedObject var steward: Steward
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var mouth: Mouth
    @AppStorage("stewardOn") private var stewardOn = false
    @AppStorage("stewardLatitude") private var latitude =
        "observe"
    @State private var orderName = ""
    @State private var orderHost = ""
    @State private var orderPort = ""
    @State private var orderVerdict = ""
    @State private var orderAction = "tighten"

    var body: some View {
        Section(header: Text(L("The steward")),
                footer: Text(L("A watch officer under a charter you write. OBSERVE: it assesses and files proposals, and touches nothing. ACT: it runs plans in proportion to confidence — high runs the whole plan, medium its first step, low is journaled and left to you. FULL: it may also approve its own drafted reflexes and raise EMCON at your usual hour. Every judgment is a sealed journal line with its score and its factors; you audit it, you amend the charter. It thinks while the app is open — every opening is a shift change."))) {
            Toggle(L("The steward"), isOn: $stewardOn)
            if stewardOn {
                Picker(L("Latitude"), selection: $latitude) {
                    Text(L("Observe")).tag("observe")
                    Text(L("Act")).tag("act")
                    Text(L("Full")).tag("full")
                }
                .pickerStyle(.segmented)
                .onChange(of: latitude) {
                    steward.refresh(emcon: emcon)
                }
                Text(steward.assessment)
                    .font(.callout)
                if !steward.mirrorLine.isEmpty {
                    Text(steward.mirrorLine)
                        .font(.caption).italic()
                        .foregroundStyle(.secondary)
                }
                proposalsList
                deviationsList
                watchOrdersEditor
                casesList
                if Steward.dismissalCount > 0 {
                    Button(String(format: L("Restore %lld dismissed deviation(s)"), Steward.dismissalCount)) {
                        Steward.clearDismissals()
                    }
                    .font(.callout)
                }
            }
        }
        .onAppear { steward.refresh(emcon: emcon) }
    }

    @ViewBuilder
    private var proposalsList: some View {
        ForEach(steward.proposals) { proposal in
            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title)
                    .font(.callout.weight(.medium))
                Text(proposal.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    if proposal.kind == "plan" {
                        Button(L("Enact the plan")) {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "rule" {
                        Button(L("Approve the reflex")) {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "charter" {
                        Button(L("Amend the charter")) {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "posture" {
                        Button(L("Raise EMCON")) {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    }
                    Button(L("Dismiss"), role: .destructive) {
                        steward.dismissProposal(proposal)
                    }
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var deviationsList: some View {
        if !emcon.hometurfNotes.isEmpty {
            ForEach(emcon.hometurfNotes, id: \.self) { note in
                HStack {
                    Text(note).font(.caption)
                    Spacer()
                    Button(L("Dismiss")) {
                        emcon.hometurfDismiss(note)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var watchOrdersEditor: some View {
        Text(L("Watch orders — your own situations"))
            .font(.callout.weight(.medium))
        ForEach($steward.orders) { $order in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.name).font(.callout)
                    Text(orderSummary(order))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L(""), isOn: $order.enabled)
                    .labelsHidden()
                    .onChange(of: order.enabled) {
                        steward.saveOrders()
                    }
                Button(role: .destructive) {
                    steward.orders.removeAll {
                        $0.id == order.id
                    }
                    steward.saveOrders()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        TextField(L("Order name (e.g. the landlord's box)"),
                  text: $orderName)
            .font(.callout)
        TextField(L("Host contains (blank = any)"),
                  text: $orderHost)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        TextField(L("Port (blank = any)"), text: $orderPort)
            .font(.callout.monospaced())
            .keyboardType(.numberPad)
        TextField(L("First word contains (blank = any)"),
                  text: $orderVerdict)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        Picker(L("Then"), selection: $orderAction) {
            Text(L("Raise the second sense")).tag("tighten")
            Text(L("Answer in character")).tag("answer")
            Text(L("Load the bench on them")).tag("pivot")
        }
        .font(.callout)
        Button {
            guard !orderName.isEmpty else { return }
            steward.orders.append(Steward.WatchOrder(
                id: UUID().uuidString, name: orderName,
                host: orderHost, port: orderPort,
                verdict: orderVerdict, action: orderAction,
                enabled: true))
            steward.saveOrders()
            orderName = ""; orderHost = ""
            orderPort = ""; orderVerdict = ""
        } label: {
            Label(L("Post the watch order"),
                  systemImage: "plus.circle")
        }
        .font(.callout)
    }

    private func orderSummary(_ order: Steward.WatchOrder)
        -> String {
        var parts: [String] = []
        parts.append(order.host.isEmpty
            ? L("any host")
            : String(format: L("host ∋ %@"), order.host))
        parts.append(order.port.isEmpty
            ? L("any port")
            : String(format: L("port %@"), order.port))
        parts.append(order.verdict.isEmpty
            ? L("any first word")
            : String(format: L("speaks ∋ %@"), order.verdict))
        return parts.joined(separator: " · ")
            + " → " + order.action
    }

    @ViewBuilder
    private var casesList: some View {
        let open = steward.cases.filter { $0.open }
        if !open.isEmpty {
            Text(L("Case files"))
                .font(.callout.weight(.medium))
            ForEach(open) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.hosts.joined(separator: ", "))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button(L("Close")) {
                            steward.closeCase(entry)
                        }
                        .font(.caption)
                    }
                    ForEach(entry.entries.suffix(4),
                            id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
