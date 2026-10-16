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
        "The steward has not taken a shift yet."
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
                ? "EMCON is up, away from home turf."
                : "EMCON is up on home turf.")
            : "EMCON is standing down.")
        if emcon.senseActive {
            parts.append("The second sense is raised.")
        }
        if let until = companyUntil, until > Date() {
            parts.append("Company: a paired operator's flare "
                + "was in range recently.")
        }
        if emcon.hometurfReady {
            let n = emcon.hometurfNotes.count
            parts.append(n == 0
                ? "The home pattern holds — nothing off it."
                : "\(n) deviation(s) off the home pattern "
                  + "tonight.")
        } else if emcon.homeSubnet != nil {
            parts.append("The home pattern is still learning "
                + "(\(emcon.hometurf.nights) of 3 nights).")
        }
        let changed = files(emcon: emcon)
            .filter { ProberFiles.changed($0) }.count
        if changed > 0 {
            parts.append("\(changed) prober file(s) have "
                + "unreviewed changes.")
        }
        let openCases = cases.filter { $0.open }.count
        if openCases > 0 {
            parts.append("\(openCases) case file(s) open.")
        }
        if proposals.count > 0 {
            parts.append("\(proposals.count) proposal(s) await "
                + "your judgment.")
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
            ? "EMCON is up and the tripwire is listening"
            : "EMCON is down")
        let doors = Set(emcon.events.map { $0.port }).count
        if doors > 0 {
            parts.append("\(doors) door(s) have been tried "
                + "from the wire")
        }
        if let top = CanaryLessons.all().first {
            parts.append("probers ask your doors for "
                + "\(top.value) most")
        }
        if let persona = emcon.mouth?.canary.runningPersona {
            parts.append("the canary is answering as "
                + persona.uppercased())
        }
        return "From the wire: " + parts.joined(separator: "; ")
            + "."
    }

    // MARK: - judgment

    /// Confidence, scored from the evidence itself — every
    /// factor named, so the reasoning can be audited like
    /// everything else the steward writes.
    private func confidence(nightjarGrade: Bool,
                            file: ProberFile?,
                            newSource: Bool, offPattern: Bool,
                            emcon: Emcon)
        -> (points: Int, band: String, factors: [String]) {
        var points = 0
        var factors: [String] = []
        if nightjarGrade {
            points += 40
            factors.append("a nightjar-grade first word")
        }
        if let file = file, file.drops > 0 {
            points += 35
            factors.append("has taken \(file.drops) "
                + "honeydrop(s) before")
        }
        if newSource {
            points += 15
            factors.append("no file history")
        }
        if offPattern {
            points += 15
            factors.append("off the learned pattern")
        }
        if let file = file,
           file.ports.values.reduce(0, +) >= 5 {
            points += 10
            factors.append("a repeat visitor "
                + "(\(file.ports.values.reduce(0, +)) knocks "
                + "on file)")
        }
        if emcon.senseActive {
            points += 10
            factors.append("the sense is already up")
        }
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
        resolveWatches(host: host, outcome: "returned within "
            + "the day — still interested")

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
                situation: "watch order: \(order.name)",
                evidence: "\(host) on port \(port) spoke "
                    + "\u{201C}\(verdict)\u{201D} — the "
                    + "operator's own order covers this",
                plan: [order.action],
                confidence: (100, "high",
                             ["the operator wrote this order"]),
                emcon: emcon, host: host, port: port,
                verdict: verdict, file: file)
        }

        let nightjarGrade = verdict.hasPrefix(
            "nightjar-hack probe:")
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
            emcon: emcon)

        // The taker returns: a source with drops in its
        // file is knocking again. Whatever it wants this
        // time, it has already shown its hands.
        if let file = file, file.drops > 0,
           !resting("taker") {
            markFired("taker")
            respond(
                situation: "the taker returns",
                evidence: "\(host) has taken \(file.drops) "
                    + "honeydrop(s) before and is knocking "
                    + "again on port \(port)",
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
                situation: "a colleague-grade prober",
                evidence: "\(host) spoke \(verdict) on port "
                    + "\(port) — nightjar-grade tooling, "
                    + (newSource ? "a source never seen before"
                                  : "at an off-pattern door"),
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
                situation: "a pattern-break cluster",
                evidence: "\(emcon.hometurfNotes.count) "
                    + "deviations off the learned home "
                    + "pattern tonight",
                plan: ["tighten"],
                confidence: (35 + extra * 10,
                             extra >= 3 ? "high" : "medium",
                             ["\(emcon.hometurfNotes.count) "
                                + "deviations tonight"]),
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
        let evidence = "\(host)'s own sequence — "
            + sequence.map(String.init)
                .joined(separator: " → ")
            + " — says port \(next) comes after "
            + "\(knockedPort)"
        if mayAct {
            emcon.prestageCanary(port: next, persona: persona,
                                 source: host)
            Journal.log("steward", "plan",
                        "ANTICIPATION: \(evidence). The "
                        + "\(persona) canary is pre-staged on "
                        + "port \(next) under latitude "
                        + "\(Self.latitude).")
            fileCase(situation: "anticipation", host: host,
                     evidence: evidence, file: file)
        } else {
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "plan",
                title: "Anticipation: \(host)",
                detail: evidence + ". Proposed: pre-stage "
                    + "the \(persona) canary on port \(next). "
                    + "Held under latitude observe.",
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
        let scoreText = "confidence \(confidence.band) "
            + "(\(confidence.points)): "
            + (confidence.factors.isEmpty
                ? "no strong factors"
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
                    + ". Proposed: " + planText
                    + ". Held under latitude observe.",
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
                title: "Drafted reflex: the taker rule",
                detail: "Colleague-grade probing has begun "
                    + "and no reflex loads the bench when a "
                    + "honeydrop is taken. Approving adds it "
                    + "to the conductor.",
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
        case "tighten": return "raise the second sense"
        case "answer": return "answer in character"
        case "pivot": return "load the bench on them"
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
            emcon.raiseSense(reason: "the steward's plan")
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
        let entry = "\(stamp) — \(situation): \(evidence)"
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
                    } ?? "a watched address"
                let title = "Dossier drift: \(host)"
                guard !self.proposals.contains(
                    where: { $0.title == title }) else { return }
                self.proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "note", title: title,
                    detail: event.text + " Filed from the "
                        + "journal the moment it was written — "
                        + "re-baseline it in the dossier if "
                        + "the change is explained, or load "
                        + "the bench on it if it is not."),
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
                        outcome: "confirmed — the visitor "
                            + "bit the canary too")
                    if let idx = self.cases.firstIndex(
                        where: { $0.open
                            && $0.hosts.contains(host) }) {
                        self.cases[idx].entries.append(
                            "took the canary's drop — "
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
            if knocks > 0 { parts.append("\(knocks) knock(s)") }
            let drops = count("canary", "honeydrop")
            if drops > 0 {
                parts.append("\(drops) honeydrop(s) TAKEN")
            }
            let deviations = count("emcon", "hometurf")
            if deviations > 0 {
                parts.append("\(deviations) deviation(s)")
            }
            let plans = count("steward", "plan")
            if plans > 0 {
                parts.append("\(plans) steward action(s)")
            }
            if !parts.isEmpty {
                let line = "While you were gone: "
                    + parts.joined(separator: ", ") + "."
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
            if stale, !proposals.contains(
                where: { $0.kind == "note"
                    && $0.title.hasPrefix("Night maneuvers") }) {
                proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "note", title: "Night maneuvers "
                        + "are stale",
                    detail: "The last graded self-test is "
                        + "over a day old (or never ran). The "
                        + "maneuvers live in the EMCON tab "
                        + "when you want them."), at: 0)
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
            var enacted: [String: Int] = [:]
            var dismissed: [String: Int] = [:]
            for event in all where event.module == "steward" {
                if event.text.hasPrefix(
                    "The operator enacted a held plan — ") {
                    let title = event.text
                        .replacingOccurrences(
                            of: "The operator enacted a held "
                                + "plan — ", with: "")
                        .components(separatedBy: ":").first
                        ?? ""
                    if !title.isEmpty {
                        enacted[title, default: 0] += 1
                    }
                }
                if event.text.hasPrefix(
                    "The operator dismissed a proposal: ") {
                    let title = event.text
                        .replacingOccurrences(
                            of: "The operator dismissed a "
                                + "proposal: ", with: "")
                        .components(separatedBy: ".").first
                        ?? ""
                    if !title.isEmpty {
                        dismissed[title, default: 0] += 1
                    }
                }
            }
            for (situation, count) in enacted
            where count >= 3 && (dismissed[situation] ?? 0) == 0 {
                let title = "Charter amendment: trust the "
                    + "\(situation) call"
                guard !proposals.contains(
                    where: { $0.title == title }) else { continue }
                proposals.insert(Proposal(
                    id: UUID().uuidString, when: Date(),
                    kind: "charter", title: title,
                    detail: "You have enacted the steward's "
                        + "held plan for \u{201C}\(situation)"
                        + "\u{201D} \(count) times and never "
                        + "dismissed one. Amending the charter "
                        + "to Act lets it run that judgment "
                        + "without waiting on you — every act "
                        + "still journaled, still graded."),
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
                kind: "posture", title: "Your usual hour: "
                    + "raise EMCON",
                detail: "EMCON has risen at \(modal):00 "
                    + "more than any other hour "
                    + "(\(risings.count) risings on record) "
                    + "and it is down now. Enacting raises "
                    + "it."), at: 0)
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
        Section(header: Text("The steward"),
                footer: Text("A watch officer under a charter "
                    + "you write. OBSERVE: it assesses and "
                    + "files proposals, and touches nothing. "
                    + "ACT: it runs plans in proportion to "
                    + "confidence — high runs the whole plan, "
                    + "medium its first step, low is journaled "
                    + "and left to you. FULL: it may also "
                    + "approve its own drafted reflexes and "
                    + "raise EMCON at your usual hour. Every "
                    + "judgment is a sealed journal line with "
                    + "its score and its factors; you audit "
                    + "it, you amend the charter. It thinks "
                    + "while the app is open — every opening "
                    + "is a shift change.")) {
            Toggle("The steward", isOn: $stewardOn)
            if stewardOn {
                Picker("Latitude", selection: $latitude) {
                    Text("Observe").tag("observe")
                    Text("Act").tag("act")
                    Text("Full").tag("full")
                }
                .pickerStyle(.segmented)
                .onChange(of: latitude) { _ in
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
                    Button("Restore \(Steward.dismissalCount) "
                           + "dismissed deviation(s)") {
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
                        Button("Enact the plan") {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "rule" {
                        Button("Approve the reflex") {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "charter" {
                        Button("Amend the charter") {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    } else if proposal.kind == "posture" {
                        Button("Raise EMCON") {
                            steward.enact(proposal,
                                          emcon: emcon,
                                          mouth: mouth)
                        }
                    }
                    Button("Dismiss", role: .destructive) {
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
                    Button("Dismiss") {
                        emcon.hometurfDismiss(note)
                    }
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var watchOrdersEditor: some View {
        Text("Watch orders — your own situations")
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
                Toggle("", isOn: $order.enabled)
                    .labelsHidden()
                    .onChange(of: order.enabled) { _ in
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
        TextField("Order name (e.g. the landlord's box)",
                  text: $orderName)
            .font(.callout)
        TextField("Host contains (blank = any)",
                  text: $orderHost)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        TextField("Port (blank = any)", text: $orderPort)
            .font(.callout.monospaced())
            .keyboardType(.numberPad)
        TextField("First word contains (blank = any)",
                  text: $orderVerdict)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        Picker("Then", selection: $orderAction) {
            Text("Raise the second sense").tag("tighten")
            Text("Answer in character").tag("answer")
            Text("Load the bench on them").tag("pivot")
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
            Label("Post the watch order",
                  systemImage: "plus.circle")
        }
        .font(.callout)
    }

    private func orderSummary(_ order: Steward.WatchOrder)
        -> String {
        var parts: [String] = []
        parts.append(order.host.isEmpty
            ? "any host" : "host ∋ \(order.host)")
        parts.append(order.port.isEmpty
            ? "any port" : "port \(order.port)")
        parts.append(order.verdict.isEmpty
            ? "any first word" : "speaks ∋ \(order.verdict)")
        return parts.joined(separator: " · ")
            + " → " + order.action
    }

    @ViewBuilder
    private var casesList: some View {
        let open = steward.cases.filter { $0.open }
        if !open.isEmpty {
            Text("Case files")
                .font(.callout.weight(.medium))
            ForEach(open) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.hosts.joined(separator: ", "))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Close") {
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
