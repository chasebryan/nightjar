import SwiftUI

/// The steward: the watch officer above the conductor.
///
/// The conductor fires one reflex per event, faithfully and
/// without judgment. The steward holds the whole night in
/// view at once — posture, pattern, files, sense — and
/// thinks in SITUATIONS: a foreign nightjar-grade probe from
/// a new source is not three events, it is one visitor of a
/// recognizable kind, and it deserves one composed answer.
///
/// It works under a charter the operator writes: a master
/// switch and a latitude. At OBSERVE it watches, assesses,
/// and files proposals. At ACT it may run its plans on the
/// perimeter. At FULL it may also approve its own conductor
/// rules. Nothing it does leaves the sealed log — every
/// assessment, plan, and enactment is a journal line with
/// its reasoning attached, and the morning brief carries
/// its shift report. An autonomy you cannot audit would be
/// a second operator; this one is a subordinate.
///
/// iOS still owns the body: the steward thinks while the
/// app is open. Its design center is the shift change —
/// every opening, it catches up on the sealed log, acts on
/// what its charter covers, and leaves the perimeter in the
/// best posture it can justify in writing.
final class Steward: ObservableObject {
    struct Proposal: Codable, Identifiable {
        var id: String
        var when: Date
        /// "plan" — a held response, enactable in one tap.
        /// "rule" — a suggested conductor reflex.
        /// "note" — information only (a cadence reminder).
        var kind: String
        var title: String
        var detail: String
        /// Action ids for a plan: tighten / answer / pivot.
        var plan: [String] = []
        var host: String? = nil
        var port: Int? = nil
        var verdict: String? = nil
        /// For a rule proposal: the conductor trigger/action.
        var ruleTrigger: String? = nil
        var ruleAction: String? = nil
    }

    @Published private(set) var assessment =
        "The steward has not taken a shift yet."
    @Published private(set) var proposals: [Proposal] = []

    private var filesCache: [ProberFile] = []
    private var filesCacheAt = Date.distantPast

    init() {
        proposals = Self.loadProposals()
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
    private static let firedKey = "stewardFired"
    private static let shiftKey = "stewardLastShift"
    private static let dismissalsKey = "stewardDismissals"
    private static let rest: TimeInterval = 3600

    private static func loadProposals() -> [Proposal] {
        guard let data = UserDefaults.standard.data(
                forKey: proposalsKey),
              let decoded = try? JSONDecoder().decode(
                [Proposal].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveProposals() {
        guard let data = try? JSONEncoder().encode(proposals)
        else { return }
        UserDefaults.standard.set(data, forKey: Self.proposalsKey)
    }

    private func resting(_ situation: String) -> Bool {
        let fired = UserDefaults.standard.dictionary(
            forKey: Self.firedKey) as? [String: Double] ?? [:]
        guard let last = fired[situation] else { return false }
        return Date().timeIntervalSince1970 - last < Self.rest
    }

    private func markFired(_ situation: String) {
        var fired = UserDefaults.standard.dictionary(
            forKey: Self.firedKey) as? [String: Double] ?? [:]
        fired[situation] = Date().timeIntervalSince1970
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

    /// The current read of the night, in one or two sentences
    /// an operator can hold. Refreshed on shift changes, on
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
        if proposals.count > 0 {
            parts.append("\(proposals.count) proposal(s) await "
                + "your judgment.")
        }
        assessment = parts.joined(separator: " ")
    }

    // MARK: - situations

    /// Fed every knock the funnel sees, after the conductor.
    /// Reads the knock against the whole situation — the
    /// file on its source, the state of the pattern, the
    /// sense — and answers situations, not events.
    func onKnock(emcon: Emcon, source: String, port: Int,
                 proto: String, verdict: String, mine: Bool) {
        guard Self.on, !mine else { return }
        let host = source.components(separatedBy: " ").first
            ?? source
        let file = files(emcon: emcon)
            .first { $0.host == host }
        if let file = file, file.isSelf { return }
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

        // The taker returns: a source with drops in its file
        // is knocking again. Whatever it wants this time, it
        // has already shown its hands.
        if let file = file, file.drops > 0,
           !resting("taker") {
            markFired("taker")
            respond(
                situation: "the taker returns",
                evidence: "\(host) has taken \(file.drops) "
                    + "honeydrop(s) before and is knocking "
                    + "again on port \(port)",
                plan: ["pivot"], emcon: emcon, host: host,
                port: port, verdict: verdict)
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
                emcon: emcon, host: host, port: port,
                verdict: verdict)
            suggestTakerRule(emcon: emcon)
        }

        // A pattern-break cluster: three deviations in one
        // night is not three facts, it is one changed house.
        if emcon.hometurfNotes.count >= 3,
           !resting("cluster") {
            markFired("cluster")
            respond(
                situation: "a pattern-break cluster",
                evidence: "\(emcon.hometurfNotes.count) "
                    + "deviations off the learned home "
                    + "pattern tonight",
                plan: ["tighten"], emcon: emcon, host: nil,
                port: nil, verdict: nil)
        }
        refresh(emcon: emcon)
    }

    /// A situation, answered: executed under an acting
    /// charter, or held as a proposal under an observing
    /// one. Either way the reasoning enters the sealed log.
    private func respond(situation: String, evidence: String,
                         plan: [String], emcon: Emcon,
                         host: String?, port: Int?,
                         verdict: String?) {
        let planText = plan.map(Self.actionLabel)
            .joined(separator: " + ")
        if mayAct {
            var done: [String] = []
            for action in plan {
                if perform(action: action, emcon: emcon,
                           host: host, port: port,
                           verdict: verdict) {
                    done.append(Self.actionLabel(action))
                }
            }
            Journal.log("steward", "plan",
                        "SITUATION \(situation): \(evidence). "
                        + "Plan: \(planText). Executed under "
                        + "latitude \(Self.latitude): "
                        + (done.isEmpty ? "nothing could be "
                            + "carried out" : done.joined(
                                separator: ", ")) + ".")
        } else {
            proposals.insert(Proposal(
                id: UUID().uuidString, when: Date(),
                kind: "plan", title: situation,
                detail: evidence + " Proposed: " + planText
                    + ". Held under latitude observe.",
                plan: plan, host: host, port: port,
                verdict: verdict), at: 0)
            saveProposals()
            Journal.log("steward", "observe",
                        "SITUATION \(situation): \(evidence). "
                        + "Plan proposed (\(planText)) and held "
                        + "for the operator — latitude is "
                        + "observe.")
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
                host: host, port: port, nonce: "steward")
            return true
        default:
            return false
        }
    }

    // MARK: - proposals, in the operator's hands

    func enact(_ proposal: Proposal, emcon: Emcon,
               mouth: Mouth) {
        if proposal.kind == "rule",
           let trigger = proposal.ruleTrigger,
           let action = proposal.ruleAction {
            var rules = Conductor.loadRules()
            rules.append(Conductor.Rule(
                id: UUID().uuidString,
                name: Conductor.triggerLabel(trigger) + " → "
                    + Conductor.actionLabel(action),
                trigger: trigger, action: action, enabled: true))
            Conductor.saveRules(rules)
            Journal.log("steward", "plan",
                        "The operator approved the steward's "
                        + "drafted reflex: \(proposal.title).")
        } else if proposal.kind == "plan" {
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
                        "The operator enacted a held plan — "
                        + "\(proposal.title): "
                        + (done.isEmpty ? "nothing could be "
                            + "carried out" : done.joined(
                                separator: ", ")) + ".")
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
    /// since the last shift is counted and reported; a stale
    /// maneuvers grade files its reminder.
    func shiftChange(emcon: Emcon) {
        guard Self.on else { return }
        let defaults = UserDefaults.standard
        let last = defaults.double(forKey: Self.shiftKey)
        defaults.set(Date().timeIntervalSince1970,
                     forKey: Self.shiftKey)
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
            let lastManeuvers = Journal.events(limit: 1000)
                .filter { $0.module == "emcon"
                    && $0.kind == "maneuvers" }
                .map { $0.when }.max()
            let stale = lastManeuvers.map {
                Date().timeIntervalSince($0) > 24 * 3600
            } ?? true
            let alreadyFiled = proposals.contains {
                $0.kind == "note"
            }
            if stale, !alreadyFiled {
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
        }
        refresh(emcon: emcon)
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

    var body: some View {
        Section(header: Text("The steward"),
                footer: Text("A watch officer under a charter "
                    + "you write. OBSERVE: it assesses and "
                    + "files proposals, and touches nothing. "
                    + "ACT: it may run its plans on the "
                    + "perimeter. FULL: it may also approve "
                    + "its own drafted reflexes. Everything it "
                    + "does is a sealed journal line with its "
                    + "reasoning — you don't supervise it "
                    + "live, you audit it and amend the "
                    + "charter. It thinks while the app is "
                    + "open; every opening is a shift change, "
                    + "and it catches up first.")) {
            Toggle("The steward", isOn: $stewardOn)
            if stewardOn {
                Picker("Latitude", selection: $latitude) {
                    Text("Observe").tag("observe")
                    Text("Act").tag("act")
                    Text("Full").tag("full")
                }
                .pickerStyle(.segmented)
                Text(steward.assessment)
                    .font(.callout)
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
                            }
                            Button("Dismiss", role: .destructive) {
                                steward.dismissProposal(proposal)
                            }
                        }
                        .font(.callout)
                    }
                }
                if !emcon.hometurfNotes.isEmpty {
                    ForEach(emcon.hometurfNotes, id: \.self) {
                        note in
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
}
