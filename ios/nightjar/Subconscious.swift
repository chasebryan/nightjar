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

        insights = found.sorted { $0.when > $1.when }
        brief = Self.composeBrief(events: events,
                                  neighbors: neighbors,
                                  insights: insights,
                                  now: now)
        persist()
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
        if let top = insights.first {
            lines.append("First among findings: \(top.title). "
                         + top.body)
        } else {
            lines.append("Nothing in the house broke its "
                         + "pattern. The pattern held.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: questions over your own house

    /// Honest shapes only — each maps to a real filter over
    /// the sealed log or the Neighborhood, and anything else
    /// is a keyword search the operator can audit line by
    /// line.
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
    @State private var showMind = false

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
        .sheet(isPresented: $showMind) {
            SubconsciousView()
        }
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
                                Text("\(Int(insight.confidence "
                                            * 100))%")
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
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section(header: Text("Ask the house"),
                        footer: Text("Shapes it can truly "
                            + "answer: who was about after "
                            + "midnight · what is new · foreign "
                            + "hands · what drifted — or any "
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
