import SwiftUI

/// The Subconscious — the mind underneath.
///
/// One on-device intelligence that reads across every organ
/// the app has — the sealed night log, the Neighborhood, the
/// Map, the cadence profiles, the season, the dead hand —
/// and keeps a living sense of what is normal in this house,
/// so it can name what is not. It never acts and never
/// touches the network. It advises: its findings carry the
/// journal citations they stand on, its confidence is printed
/// on its sleeve, and the Steward still asks the operator
/// before anything in this app moves.

// MARK: - A finding

struct Insight: Identifiable {
    /// The rule family this finding belongs to — the
    /// granularity the operator's verdicts teach at.
    var kind: String {
        id.hasPrefix("drift-") ? "drift"
            : id.hasPrefix("absent-") ? "absence"
            : id.hasPrefix("due-") ? "forecast"
            : id.hasPrefix("pattern-") ? "pattern"
            : id
    }
    /// "85%" — computed here, so no view ever has to do
    /// arithmetic inside a string interpolation.
    var percent: String { "\(Int(confidence * 100))%" }
    var id: String
    var when: Date
    var title: String
    var body: String
    /// The journal lines this finding stands on, quoted.
    var citations: [String]
    /// 0…1 — printed, never hidden.
    var confidence: Double
}

// MARK: - The center

final class SubconsciousCenter: ObservableObject {
    static let shared = SubconsciousCenter()

    @Published var insights: [Insight] = []
    @Published var brief: String = ""
    /// Enough sealed history to have a sense of normal.
    @Published var awake = false
    @Published var eventCount = 0

    private struct State: Codable {
        var seenDrift: [String: Int] = [:]
        /// The operator's verdicts, per finding kind:
        /// [right, wrong]. The mind's one memory of its own
        /// mistakes — confidence bends toward the record.
        var verdicts: [String: [Int]]? = nil
    }

    /// How far a kind's verdicts bend its confidence:
    /// called right, it sharpens a little; called wrong,
    /// it learns humility faster than pride.
    private func weight(forKind kind: String) -> Double {
        let v = state.verdicts?[kind] ?? [0, 0]
        let right = Double(v.first ?? 0)
        let wrong = Double(v.count > 1 ? v[1] : 0)
        return min(1.2, max(0.35, 1 + 0.06 * right
                                  - 0.12 * wrong))
    }

    /// The operator grades a finding. The grade is kept,
    /// the confidence bends, and the mind re-reads the
    /// house with its lesson applied.
    func judge(insightID: String, right: Bool) {
        let kind = Insight(id: insightID, when: Date(),
                           title: "", body: "",
                           citations: [], confidence: 0).kind
        var all = state.verdicts ?? [:]
        var v = all[kind] ?? [0, 0]
        if v.count < 2 { v += [0, 0] }
        if right { v[0] += 1 } else { v[1] += 1 }
        all[kind] = v
        state.verdicts = all
        persist()
        refresh()
    }

    /// What the record says about a kind, for display.
    func verdictLine(for insight: Insight) -> String? {
        let v = state.verdicts?[insight.kind] ?? [0, 0]
        let right = v.first ?? 0
        let wrong = v.count > 1 ? v[1] : 0
        guard right + wrong > 0 else { return nil }
        return "Your verdicts on findings like this: "
            + "\(right) right, \(wrong) wrong — its "
            + "confidence is bent accordingly."
    }

    private static var fileURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("subconscious.json")
    }

    private var state = State()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(
               State.self, from: data) {
            state = saved
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    // MARK: the reading

    func refresh() {
        let events = Journal.events(limit: 4000)
            .sorted { $0.when < $1.when }
        eventCount = events.count
        awake = events.count >= 40
        let now = Date()
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        var found: [Insight] = []

        let neighbors = NeighborhoodStore.shared.neighbors

        // New faces on the wire.
        let fresh = neighbors.filter { $0.firstSeen > dayAgo }
        if !fresh.isEmpty {
            found.append(Insight(
                id: "new-faces",
                when: fresh.map(\.firstSeen).max() ?? now,
                title: fresh.count == 1
                    ? "A new face on the wire"
                    : "\(fresh.count) new faces on the wire",
                body: fresh.map {
                    "\($0.displayName) (\($0.ip)) first seen "
                        + $0.firstSeen.formatted(
                            date: .abbreviated, time: .shortened)
                }.joined(separator: ". ") + ".",
                citations: events
                    .filter { $0.module == "neighborhood"
                        && $0.when > dayAgo }
                    .suffix(3).map(Self.cite),
                confidence: 0.9))
        }

        // Drift nobody has reckoned with yet.
        for neighbor in neighbors {
            let seen = state.seenDrift[neighbor.ip] ?? 0
            if neighbor.drift.count > seen {
                let newLines = Array(
                    neighbor.drift.prefix(
                        neighbor.drift.count - seen))
                found.append(Insight(
                    id: "drift-\(neighbor.ip)",
                    when: neighbor.lastSeen,
                    title: "\(neighbor.displayName) has drifted",
                    body: newLines.joined(separator: " "),
                    citations: events
                        .filter { $0.module == "neighborhood"
                            && $0.text.contains(neighbor.ip) }
                        .suffix(2).map(Self.cite),
                    confidence: 0.75))
            }
            state.seenDrift[neighbor.ip] = neighbor.drift.count
        }

        // Foreign hands, from the cadence seal's own journal.
        let cadenceFlags = events.filter {
            $0.module == "emcon" && $0.kind == "cadence"
                && $0.when > weekAgo
        }
        if !cadenceFlags.isEmpty {
            found.append(Insight(
                id: "foreign-hands",
                when: cadenceFlags.last?.when ?? now,
                title: "Hands that were not the usual hands",
                body: "The cadence seal spoke "
                    + "\(cadenceFlags.count) time"
                    + (cadenceFlags.count == 1 ? "" : "s")
                    + " this week. The key was right; the "
                    + "rhythm was not. Worth a look before it "
                    + "is worth a worry.",
                citations: cadenceFlags.suffix(3).map(Self.cite),
                confidence: 0.8))
        }

        // The house after midnight.
        let nightEvents = events.filter {
            $0.when > dayAgo
                && Calendar.current.component(.hour,
                                              from: $0.when) < 5
        }
        if nightEvents.count >= 3 {
            let modules = Set(nightEvents.map(\.module))
                .sorted().joined(separator: ", ")
            found.append(Insight(
                id: "night-hours",
                when: nightEvents.last?.when ?? now,
                title: "The house was awake after midnight",
                body: "\(nightEvents.count) sealed events "
                    + "between midnight and five — \(modules). "
                    + "If that was you, it is a rhythm. If it "
                    + "was not, it is a question.",
                citations: nightEvents.suffix(3).map(Self.cite),
                confidence: 0.6))
        }

        // The season's verdict, when one has landed.
        if let verdict = events.last(where: {
            $0.module == "season" && $0.kind == "verdict"
        }) {
            found.append(Insight(
                id: "season-verdict",
                when: verdict.when,
                title: "The season has a grade",
                body: verdict.text,
                citations: [Self.cite(verdict)],
                confidence: 1.0))
        }

        // The dead hand, aging.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "deadHand.on") {
            let last = defaults.double(forKey: "deadHand.last")
            let hours = defaults.double(forKey: "deadHand.hours")
            if last > 0, hours > 0 {
                let age = now.timeIntervalSince1970 - last
                if age > hours * 3600 * 0.5 {
                    found.append(Insight(
                        id: "dead-hand",
                        when: now,
                        title: "The dead hand is more than "
                            + "halfway down",
                        body: "Armed, and the last check-in is "
                            + "older than half the fuse. A tap "
                            + "of the coin — or a manual check-in "
                            + "— buys the whole window back.",
                        citations: [],
                        confidence: 0.95))
                }
            }
        }

        // MARK: v2 — the deeper readings

        // The house's tempo against its own habit: the
        // trailing fortnight's hourly shape is the baseline
        // the mind now carries.
        let fortnightAgo = now.addingTimeInterval(
            -14 * 24 * 3600)
        let fortnight = events.filter { $0.when > fortnightAgo }
        var profile = [Int](repeating: 0, count: 24)
        for event in fortnight {
            profile[Calendar.current.component(
                .hour, from: event.when)] += 1
        }
        let priorDays = fortnight.filter { $0.when <= dayAgo }
        let priorMean = Double(priorDays.count) / 13.0
        let last24Count = events.filter {
            $0.when > dayAgo }.count
        if priorMean >= 10 {
            let ratio = Double(last24Count) / priorMean
            if ratio >= 1.8 {
                found.append(Insight(
                    id: "tempo", when: now,
                    title: "The house ran loud",
                    body: "\(last24Count) sealed events in "
                        + "the last day against a habit of "
                        + "about \(Int(priorMean)) a day over "
                        + "the fortnight — \(String(format: "%.1f", ratio))× "
                        + "its own normal. Loud days have "
                        + "authors; the log knows them.",
                    citations: events.filter { $0.when > dayAgo }
                        .suffix(3).map(Self.cite),
                    confidence: 0.7))
            } else if ratio <= 0.45 {
                found.append(Insight(
                    id: "tempo", when: now,
                    title: "The house ran quiet",
                    body: "Only \(last24Count) sealed events "
                        + "in the last day against a habit of "
                        + "about \(Int(priorMean)) a day. "
                        + "Quiet is a finding too — a feed "
                        + "down, a device gone, or a house "
                        + "holding its breath.",
                    citations: [],
                    confidence: 0.6))
            }
        }

        // Absence: the regular who has stopped appearing.
        // A device's own history sets the expectation; the
        // silence has to run three times past it to speak.
        for neighbor in neighbors where neighbor.sightings >= 6 {
            let span = neighbor.lastSeen.timeIntervalSince(
                neighbor.firstSeen)
            guard span > 12 * 3600 else { continue }
            let interval = span / Double(neighbor.sightings)
            let silence = now.timeIntervalSince(
                neighbor.lastSeen)
            guard interval > 300, interval < 36 * 3600,
                  silence > max(3 * interval, 12 * 3600)
            else { continue }
            found.append(Insight(
                id: "absent-\(neighbor.ip)", when: now,
                title: "\(neighbor.displayName) has gone quiet",
                body: "A regular — seen "
                    + "\(neighbor.sightings) times, roughly "
                    + "every \(Self.hours(interval)) — has "
                    + "not been seen for "
                    + "\(Self.hours(silence)). Silence from "
                    + "a regular is itself a signal: unplugged, "
                    + "moved, replaced, or gone.",
                citations: events
                    .filter { $0.text.contains(neighbor.ip) }
                    .suffix(2).map(Self.cite),
                confidence: 0.65))
        }

        // The forecast: the next regular due back, named
        // before it knocks.
        let dues: [(Neighbor, Date)] = neighbors.compactMap {
            neighbor in
            guard neighbor.sightings >= 6 else { return nil }
            let span = neighbor.lastSeen.timeIntervalSince(
                neighbor.firstSeen)
            guard span > 12 * 3600 else { return nil }
            let interval = span / Double(neighbor.sightings)
            guard interval > 300, interval < 36 * 3600
            else { return nil }
            let due = neighbor.lastSeen.addingTimeInterval(
                interval)
            guard due > now,
                  due < now.addingTimeInterval(6 * 3600)
            else { return nil }
            return (neighbor, due)
        }
        if let (neighbor, due) = dues.min(
            by: { $0.1 < $1.1 }) {
            found.append(Insight(
                id: "due-\(neighbor.ip)", when: now,
                title: "On its habit, "
                    + "\(neighbor.displayName) is due back",
                body: "Its rhythm says around "
                    + due.formatted(date: .omitted,
                                    time: .shortened)
                    + ". A forecast, printed as one — if it "
                    + "does not come, the absence finding "
                    + "will have something to stand on.",
                citations: [],
                confidence: 0.55))
        }

        // Correlation: findings that share a window may be
        // one story wearing several coats. A fresh face
        // within three hours of night activity, foreign
        // hands, or its own drift is no longer three small
        // things — it is a pattern with a protagonist.
        let freshFaces = neighbors.filter {
            $0.firstSeen > dayAgo }
        for face in freshFaces {
            let window = { (date: Date) in
                abs(date.timeIntervalSince(face.firstSeen))
                    < 3 * 3600
            }
            var threads: [String] = []
            var cites: [String] = []
            if nightEvents.contains(where: {
                window($0.when) }) {
                threads.append("the house was awake after "
                               + "midnight in the same hours")
                cites += nightEvents.filter { window($0.when) }
                    .suffix(2).map(Self.cite)
            }
            if cadenceFlags.contains(where: {
                window($0.when) }) {
                threads.append("the cadence seal felt hands "
                               + "that were not the usual "
                               + "hands nearby in time")
                cites += cadenceFlags.filter { window($0.when) }
                    .suffix(2).map(Self.cite)
            }
            if !face.drift.isEmpty {
                threads.append("the newcomer itself has "
                               + "already drifted: "
                               + (face.drift.first ?? ""))
            }
            guard !threads.isEmpty else { continue }
            found.append(Insight(
                id: "pattern-\(face.ip)",
                when: face.firstSeen,
                title: "Read together: "
                    + "\(face.displayName)'s arrival",
                body: "\(face.displayName) (\(face.ip)) "
                    + "first appeared "
                    + face.firstSeen.formatted(
                        date: .abbreviated, time: .shortened)
                    + ". In the same three hours: "
                    + threads.joined(separator: "; ")
                    + ". Separately, small things. Together, "
                    + "a story worth your eyes.",
                citations: Array(cites.prefix(4)),
                confidence: min(0.95, 0.62
                    + 0.11 * Double(threads.count))))
        }

        // The operator's verdicts bend every confidence,
        // then the ranking: stories first, strength next,
        // recency last.
        found = found.map { insight in
            var bent = insight
            bent.confidence = min(
                0.99, insight.confidence
                    * weight(forKind: insight.kind))
            return bent
        }
        insights = found.sorted {
            let a = $0.id.hasPrefix("pattern-") ? 1 : 0
            let b = $1.id.hasPrefix("pattern-") ? 1 : 0
            if a != b { return a > b }
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.when > $1.when
        }
        brief = Self.composeBrief(events: events,
                                  neighbors: neighbors,
                                  insights: insights,
                                  now: now)
        persist()
    }

    /// "3h" / "26h" / "2d" — durations in the house's units.
    private static func hours(_ interval: TimeInterval)
        -> String {
        let h = Int(interval / 3600)
        if h < 1 { return "\(Int(interval / 60))m" }
        if h < 48 { return "\(h)h" }
        return "\(h / 24)d"
    }

    private static func cite(_ event: NightEvent) -> String {
        let time = event.when.formatted(date: .omitted,
                                        time: .shortened)
        return "\(event.module) · \(event.kind) · \(time) — "
            + event.text
    }

    private static func composeBrief(events: [NightEvent],
                                     neighbors: [Neighbor],
                                     insights: [Insight],
                                     now: Date) -> String {
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        let last24 = events.filter { $0.when > dayAgo }
        let knocks = last24.filter { $0.module == "emcon" }.count
        let placed = neighbors.filter {
            MapStore.shared.placements[$0.ip] != nil
        }
        var lines: [String] = []
        lines.append(
            "The last day held \(last24.count) sealed events, "
            + "\(knocks) of them at the tripwire. The wire "
            + "knows \(neighbors.count) device"
            + (neighbors.count == 1 ? "" : "s")
            + (placed.isEmpty
               ? "."
               : ", \(placed.count) of them placed in "
                 + "their rooms on the Map."))
        if let pattern = insights.first(where: {
            $0.id.hasPrefix("pattern-") }) {
            lines.append("Read together, first: "
                         + pattern.body)
        } else if let top = insights.first {
            lines.append("First among findings: \(top.title). "
                         + top.body)
        } else {
            lines.append("Nothing in the house broke its "
                         + "pattern. The pattern held.")
        }
        if let tempo = insights.first(where: {
            $0.id == "tempo" }) {
            lines.append(tempo.title + " — " + tempo.body)
        }
        if let absent = insights.first(where: {
            $0.id.hasPrefix("absent-") }) {
            lines.append("And a silence: " + absent.body)
        }
        if let due = insights.first(where: {
            $0.id.hasPrefix("due-") }) {
            lines.append("Ahead: " + due.body)
        }
        return lines.joined(separator: " ")
    }

    // MARK: questions over your own house

    /// Honest shapes only — each maps to a real filter over
    /// the sealed log or the Neighborhood, and anything else
    /// is a keyword search the operator can audit line by
    /// line.
    private func neighborsForAsk() -> [Neighbor] {
        NeighborhoodStore.shared.neighbors
    }

    func answer(_ query: String) -> [NightEvent] {
        let q = query.lowercased()
        let events = Journal.events(limit: 4000)
            .sorted { $0.when > $1.when }
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        if q.contains("midnight") || q.contains("night")
            && q.contains("who") {
            return events.filter {
                $0.when > weekAgo
                    && Calendar.current.component(
                        .hour, from: $0.when) < 5
            }
        }
        if q.contains("new") {
            return events.filter { $0.module == "neighborhood" }
        }
        if q.contains("foreign") || q.contains("cadence")
            || q.contains("hands") {
            return events.filter {
                $0.module == "emcon" && $0.kind == "cadence"
            }
        }
        // About a device: named by address or by any of
        // its names — yours included.
        if let neighbor = neighborsForAsk().first(where: {
            q.contains($0.ip)
                || q.contains($0.displayName.lowercased())
                || ($0.name.map { q.contains($0.lowercased()) }
                    ?? false)
        }) {
            return events.filter {
                $0.text.contains(neighbor.ip) }
        }
        if q.contains("quiet") || q.contains("missing")
            || q.contains("gone") || q.contains("absent") {
            let gone = NeighborhoodStore.shared.neighbors
                .filter { $0.sightings >= 6
                    && Date().timeIntervalSince($0.lastSeen)
                        > 12 * 3600 }
            return events.filter { event in
                gone.contains { event.text.contains($0.ip) }
            }
        }
        if q.contains("when") || q.contains("busiest")
            || q.contains("peak") {
            var counts = [Int](repeating: 0, count: 24)
            for event in events where event.when > weekAgo {
                counts[Calendar.current.component(
                    .hour, from: event.when)] += 1
            }
            if let peak = counts.indices.max(
                by: { counts[$0] < counts[$1] }),
               counts[peak] > 0 {
                return events.filter {
                    Calendar.current.component(
                        .hour, from: $0.when) == peak }
            }
            return []
        }
        if q.contains("drift") || q.contains("changed") {
            return events.filter { $0.module == "neighborhood"
                && $0.kind == "drift" }
        }
        let words = q.split(separator: " ")
            .map(String.init).filter { $0.count > 2 }
        guard !words.isEmpty else { return [] }
        return events.filter { event in
            let text = event.text.lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}

// MARK: - The card in EMCON

struct SubconsciousSectionView: View {
    @ObservedObject private var mind = SubconsciousCenter.shared
    @Binding var showMind: Bool

    var body: some View {
        Section(header: Text("The Subconscious — the mind "
                             + "underneath"),
                footer: Text("It reads the whole house — log, "
                    + "wire, map, rhythms — and names what "
                    + "breaks the pattern. It never acts and "
                    + "never phones home; every finding "
                    + "carries the journal lines it stands "
                    + "on.")) {
            if !mind.awake {
                Text("Still learning the house — "
                     + "\(mind.eventCount) sealed events so "
                     + "far. A sense of normal needs history; "
                     + "it is gathering.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if let top = mind.insights.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(top.title)
                        .font(.callout.weight(.semibold))
                    Text(top.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("The pattern held. Nothing in the house "
                     + "broke it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button {
                showMind = true
            } label: {
                Label("Open the mind",
                      systemImage: "brain.head.profile")
            }
        }
        .onAppear { mind.refresh() }
    }
}

// MARK: - The mind, opened

struct SubconsciousView: View {
    @ObservedObject private var mind = SubconsciousCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [NightEvent]?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("The night, understood")) {
                    Text(mind.brief)
                        .font(.callout)
                }
                Section(header: Text("Findings")) {
                    if mind.insights.isEmpty {
                        Text("No findings. Either the house is "
                             + "at peace, or the mind is still "
                             + "learning what peace looks like "
                             + "here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mind.insights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(insight.title)
                                    .font(.callout
                                        .weight(.semibold))
                                Spacer()
                                Text(insight.percent)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(insight.body)
                                .font(.callout)
                            ForEach(insight.citations,
                                    id: \.self) { line in
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(insight.when.formatted(
                                date: .abbreviated,
                                time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            if let line = mind.verdictLine(
                                for: insight) {
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(spacing: 16) {
                                Button("True") {
                                    mind.judge(
                                        insightID: insight.id,
                                        right: true)
                                }
                                .font(.caption.weight(.semibold))
                                Button("Not so") {
                                    mind.judge(
                                        insightID: insight.id,
                                        right: false)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section(header: Text("Ask the house"),
                        footer: Text("Shapes it can truly "
                            + "answer: who was about after "
                            + "midnight · what is new · foreign "
                            + "hands · what drifted · who has "
                            + "gone quiet · when the house is "
                            + "busiest · about <a device> — or "
                            + "any "
                            + "words, matched line by line "
                            + "against the sealed log.")) {
                    HStack {
                        TextField("Ask about your own house",
                                  text: $query)
                            .disableAutocorrection(true)
                        Button("Ask") {
                            results = mind.answer(query)
                        }
                        .disabled(query.isEmpty)
                    }
                    if let results {
                        if results.isEmpty {
                            Text("Nothing in the log answers "
                                 + "that — and it would rather "
                                 + "say so than invent.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(results.prefix(30)) { event in
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text(event.text)
                                    .font(.callout)
                                Text("\(event.module) · "
                                     + "\(event.kind) · "
                                     + event.when.formatted(
                                        date: .abbreviated,
                                        time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("The Subconscious")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { mind.refresh() }
        }
    }
}
