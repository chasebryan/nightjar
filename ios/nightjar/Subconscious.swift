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
            : id.hasPrefix("operator-") ? "operator"
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

/// A durable conclusion — the consolidation's product.
/// Not a count but a belief, kept with its evidence and
/// its birthday, contradicted in the open when the
/// house breaks it, and forgettable by the operator,
/// whose forgetting is also kept (a buried fact is not
/// re-derived behind his back).
struct HouseFact: Codable, Identifiable {
    var id: String
    var text: String
    var evidence: String
    var learnedAt: Date
    /// Structured memory, for the contradiction watch.
    var ip: String? = nil
    var windowStart: Int? = nil
    var windowEnd: Int? = nil
}

// MARK: - The center

final class SubconsciousCenter: ObservableObject {
    static let shared = SubconsciousCenter()

    @Published var insights: [Insight] = []
    @Published var brief: String = ""
    /// Enough sealed history to have a sense of normal.
    @Published var awake = false
    @Published var eventCount = 0
    /// The consolidation's conclusions, published.
    @Published var facts: [HouseFact] = []

    private struct State: Codable {
        var seenDrift: [String: Int] = [:]
        /// The operator's verdicts, per finding kind:
        /// [right, wrong]. The mind's one memory of its own
        /// mistakes — confidence bends toward the record.
        var verdicts: [String: [Int]]? = nil
        /// What the consolidation has concluded.
        var facts: [HouseFact]? = nil
        /// Facts the operator has forgotten on purpose.
        var buriedFacts: [String]? = nil
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

    /// Forget everything the mind has learned about
    /// itself: the drift baselines it has already
    /// reckoned, and every verdict the operator has
    /// handed down. The reading itself is untouched —
    /// it re-derives from the log and the wire, and
    /// starts reckoning fresh.
    func reset() {
        state = State()
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
        // When the Instrument learns the night's sleep,
        // the night readings are entitled to it.
        NotificationCenter.default.addObserver(
            forName: InstrumentCenter.sleepUpdated,
            object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        NotificationCenter.default.addObserver(
            forName: InstrumentCenter.baselinesUpdated,
            object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        facts = state.facts ?? []
    }

    /// Forget one learned fact — and remember the
    /// forgetting, so the consolidation does not simply
    /// teach it again tomorrow.
    func forgetFact(_ id: String) {
        state.facts = (state.facts ?? []).filter { $0.id != id }
        var buried = state.buriedFacts ?? []
        if !buried.contains(id) { buried.append(id) }
        state.buriedFacts = buried
        facts = state.facts ?? []
        persist()
        refresh()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    // MARK: the reading

    /// The consolidation: read the fortnight and write
    /// down what it concludes — durable facts, kept with
    /// their evidence and their birthdays. A fact keeps
    /// its first birthday across re-derivations; a fact
    /// the operator buried stays buried.
    /// Every event in a set whose text names this
    /// address — the one way appearances are
    /// counted, shared by the consolidation that
    /// learns the facts and the watch that tests
    /// them.
    func mentions(of ip: String,
                  in events: [NightEvent]) -> [NightEvent] {
        events.filter { $0.text.contains(ip) }
    }

    private func consolidate(events: [NightEvent],
                             neighbors: [Neighbor],
                             now: Date) {
        let buried = Set(state.buriedFacts ?? [])
        let fortnightAgo = now.addingTimeInterval(
            -14 * 24 * 3600)
        let fortnight = events.filter { $0.when > fortnightAgo }
        var derived: [HouseFact] = []
        let cal = Calendar.current

        // The house's quiet hours.
        let days = Set(fortnight.map {
            cal.startOfDay(for: $0.when) }).count
        if days >= 8 {
            var profile = [Int](repeating: 0, count: 24)
            for e in fortnight {
                profile[cal.component(.hour, from: e.when)] += 1
            }
            let mean = Double(fortnight.count) / 24.0
            let quiet = profile.map { Double($0) < mean * 0.25 }
            var bestStart = 0, bestLen = 0
            var runStart = 0, runLen = 0
            for i in 0..<48 {
                if quiet[i % 24] {
                    if runLen == 0 { runStart = i }
                    runLen += 1
                    if runLen > bestLen {
                        bestLen = runLen
                        bestStart = runStart
                    }
                } else { runLen = 0 }
            }
            if bestLen >= 4 {
                derived.append(HouseFact(
                    id: "fact-quiet",
                    text: "The house is quiet between "
                        + "\(bestStart % 24):00 and "
                        + "\((bestStart + bestLen) % 24):00.",
                    evidence: "\(days) days of record",
                    learnedAt: now,
                    windowStart: bestStart % 24,
                    windowEnd: (bestStart + bestLen) % 24))
            }
        }

        // A regular's rhythm. (Appearances are
        // counted by the center's shared mentions(),
        // so the consolidation and the contradiction
        // watch count them the same way.)
        var rhythms = 0
        for neighbor in neighbors.sorted(by: {
            $0.sightings > $1.sightings }).prefix(3)
        where neighbor.sightings >= 15 && rhythms < 2 {
            let seen = mentions(of: neighbor.ip,
                                in: fortnight)
            guard seen.count >= 12 else { continue }
            var hist = [Int](repeating: 0, count: 24)
            for e in seen {
                hist[cal.component(.hour, from: e.when)] += 1
            }
            var bestW = 0, bestSum = -1
            for w in 0..<24 {
                let sum = (0..<6).reduce(0) {
                    $0 + hist[(w + $1) % 24] }
                if sum > bestSum { bestSum = sum; bestW = w }
            }
            let share = Double(bestSum) / Double(seen.count)
            if share >= 0.65 {
                rhythms += 1
                derived.append(HouseFact(
                    id: "fact-rhythm-\(neighbor.ip)",
                    text: "\(neighbor.displayName) keeps "
                        + "the hours \(bestW):00–"
                        + "\((bestW + 6) % 24):00 — "
                        + "\(Int(share * 100))% of its "
                        + "appearances fall there.",
                    evidence: "\(seen.count) appearances "
                        + "in the log",
                    learnedAt: now, ip: neighbor.ip,
                    windowStart: bestW,
                    windowEnd: (bestW + 6) % 24))
            }
        }

        // Two who stir together.
        let talkative = neighbors
            .map { ($0, mentions(of: $0.ip,
                                  in: fortnight)) }
            .filter { $0.1.count >= 8 }
            .sorted { $0.1.count > $1.1.count }
            .prefix(8)
        pairSearch: for i in talkative.indices {
            for j in talkative.indices where j > i {
                let a = talkative[i], b = talkative[j]
                var coDays = Set<Date>()
                for ea in a.1 where b.1.contains(where: {
                    abs($0.when.timeIntervalSince(ea.when))
                        < 45 * 60
                }) {
                    coDays.insert(cal.startOfDay(for: ea.when))
                }
                let daysA = Set(a.1.map {
                    cal.startOfDay(for: $0.when) }).count
                let daysB = Set(b.1.map {
                    cal.startOfDay(for: $0.when) }).count
                if coDays.count >= 4,
                   Double(coDays.count)
                       >= 0.6 * Double(min(daysA, daysB)) {
                    derived.append(HouseFact(
                        id: "fact-pair-\(a.0.ip)-\(b.0.ip)",
                        text: "\(a.0.displayName) and "
                            + "\(b.0.displayName) stir "
                            + "together — on \(coDays.count) "
                            + "days of record they were never "
                            + "far apart. One wakes the "
                            + "other, or both answer the "
                            + "same master.",
                        evidence: "\(coDays.count) shared days",
                        learnedAt: now))
                    break pairSearch
                }
            }
        }

        // The foreign hands' habits.
        let cadence = fortnight.filter {
            $0.module == "emcon" && $0.kind == "cadence" }
        if cadence.count >= 3 {
            if cadence.allSatisfy({
                (2...6).contains(
                    cal.component(.weekday, from: $0.when)) }) {
                derived.append(HouseFact(
                    id: "fact-foreign",
                    text: "Foreign hands have only ever "
                        + "come on weekdays.",
                    evidence: "\(cadence.count) cadence flags",
                    learnedAt: now))
            } else if cadence.allSatisfy({
                cal.component(.hour, from: $0.when) < 5 }) {
                derived.append(HouseFact(
                    id: "fact-foreign",
                    text: "Foreign hands have only ever "
                        + "come in the small hours.",
                    evidence: "\(cadence.count) cadence flags",
                    learnedAt: now,
                    windowStart: 0, windowEnd: 5))
            }
        }

        // Merge: keep birthdays, respect burials,
        // cap it — and RETAIN. A fact the fortnight
        // no longer re-derives is not silently
        // dropped: it was a durable conclusion, and
        // its evidence aging out of the window is
        // not a refutation (the contradiction watch
        // is what catches a fact the house broke).
        // When the cap bites, the un-re-derived go
        // first, oldest first; derivation order no
        // longer starves whole families.
        let existing = Dictionary(uniqueKeysWithValues:
            (state.facts ?? []).map { ($0.id, $0) })
        var merged: [HouseFact] = []
        var derivedIDs = Set<String>()
        for fact in derived where !buried.contains(fact.id) {
            var f = fact
            if let old = existing[fact.id] {
                f.learnedAt = old.learnedAt
            }
            merged.append(f)
            derivedIDs.insert(f.id)
        }
        merged.append(contentsOf: (state.facts ?? [])
            .filter {
                !derivedIDs.contains($0.id)
                    && !buried.contains($0.id)
            })
        if merged.count > 12 {
            let evictable = merged.sorted { a, b in
                let aDerived = derivedIDs.contains(a.id)
                let bDerived = derivedIDs.contains(b.id)
                if aDerived != bDerived { return !aDerived }
                return a.learnedAt < b.learnedAt
            }
            let doomed = Set(evictable
                .prefix(merged.count - 12).map { $0.id })
            merged.removeAll { doomed.contains($0.id) }
        }
        state.facts = merged
        facts = state.facts ?? []
    }

    func refresh() {
        // Keep the sleep window fresh; when it changes,
        // the notification above rebuilds this reading
        // with it. Silent and empty when the Instrument
        // has nothing — privacy means exactly that.
        InstrumentCenter.shared.fetchSleep()
        InstrumentCenter.shared.fetchBaselines()
        let events = Journal.events(limit: 4000)
            .sorted { $0.when < $1.when }
        eventCount = events.count
        awake = events.count >= 40
        let now = Date()
        let dayAgo = now.addingTimeInterval(-24 * 3600)
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        var found: [Insight] = []

        let neighbors = NeighborhoodStore.shared.neighbors
        consolidate(events: events, neighbors: neighbors,
                    now: now)

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
            // The Instrument's testimony, when it has any:
            // asleep for it, still up for it, or no word.
            var sleepClause = ""
            if let window = InstrumentCenter.shared.lastSleep {
                let span = window.start.formatted(
                        date: .omitted, time: .shortened)
                    + "–" + window.end.formatted(
                        date: .omitted, time: .shortened)
                if nightEvents.contains(where: {
                    $0.when >= window.start && $0.when <= window.end
                }) {
                    sleepClause = " The instrument says you "
                        + "were asleep for it (" + span
                        + ") — so it was not you."
                } else if let last = nightEvents.last?.when,
                          window.start > last {
                    sleepClause = " The instrument says you "
                        + "were still up for it — you slept "
                        + span + "."
                }
            }
            found.append(Insight(
                id: "night-hours",
                when: nightEvents.last?.when ?? now,
                title: "The house was awake after midnight",
                body: "\(nightEvents.count) sealed events "
                    + "between midnight and five — \(modules). "
                    + "If that was you, it is a rhythm. If it "
                    + "was not, it is a question." + sleepClause,
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
        // The habit's denominator is the record's
        // real span, not an assumed fortnight: a
        // young house's normal is reckoned from
        // the days it actually has behind it.
        let priorSpan = priorDays.first.map {
            max(1.0, min(13.0, dayAgo.timeIntervalSince(
                $0.when) / 86400))
        } ?? 13.0
        let priorMean = Double(priorDays.count) / priorSpan
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

        // The contradiction watch: facts the house has
        // broken since they were learned.
        let dayEvents = events.filter { $0.when > dayAgo }
        for fact in state.facts ?? [] {
            if fact.id == "fact-quiet",
               let start = fact.windowStart,
               let end = fact.windowEnd {
                let inside = dayEvents.filter { e in
                    let h = Calendar.current.component(
                        .hour, from: e.when)
                    return start < end
                        ? (h >= start && h < end)
                        : (h >= start || h < end)
                }
                if inside.count >= 3 {
                    found.append(Insight(
                        id: "against-fact-quiet",
                        when: inside.last?.when ?? now,
                        title: "Against its own record",
                        body: "The house knows itself quiet "
                            + "between \(start):00 and "
                            + "\(end):00 — but "
                            + "\(inside.count) events landed "
                            + "inside those hours in the "
                            + "last day. Either the rhythm "
                            + "is changing, or something new "
                            + "is keeping the hours.",
                        citations: inside.suffix(3)
                            .map(Self.cite),
                        confidence: 0.6))
                }
            }
            if fact.id.hasPrefix("fact-rhythm"),
               let ip = fact.ip,
               let start = fact.windowStart,
               let end = fact.windowEnd,
               let neighbor = neighbors.first(
                   where: { $0.ip == ip }),
               now.timeIntervalSince(neighbor.lastSeen)
                   < 24 * 3600 {
                let h = Calendar.current.component(
                    .hour, from: neighbor.lastSeen)
                let inWindow = start < end
                    ? (h >= start && h < end)
                    : (h >= start || h < end)
                if !inWindow {
                    found.append(Insight(
                        id: "against-" + fact.id,
                        when: neighbor.lastSeen,
                        title: "Against its own record",
                        body: "\(neighbor.displayName) was "
                            + "seen at "
                            + neighbor.lastSeen.formatted(
                                date: .omitted,
                                time: .shortened)
                            + " — outside the hours the "
                            + "house knows it by (\(start)"
                            + ":00–\(end):00).",
                        citations: [],
                        confidence: 0.55))
                }
            }
            if fact.id.hasPrefix("fact-pair-") {
                // The pairings are watched too: both
                // members about these last four days,
                // on separate days, yet never together
                // — the stirring-together the house
                // knows has stopped.
                let parts = fact.id.split(separator: "-")
                if parts.count == 4 {
                    let ipA = String(parts[2])
                    let ipB = String(parts[3])
                    let recent = events.filter {
                        $0.when > now.addingTimeInterval(
                            -4 * 24 * 3600)
                    }
                    let aSeen = mentions(of: ipA, in: recent)
                    let bSeen = mentions(of: ipB, in: recent)
                    let daysA = Set(aSeen.map {
                        Calendar.current.startOfDay(
                            for: $0.when) }).count
                    let daysB = Set(bSeen.map {
                        Calendar.current.startOfDay(
                            for: $0.when) }).count
                    let together = aSeen.contains { ea in
                        bSeen.contains {
                            abs($0.when.timeIntervalSince(
                                ea.when)) < 45 * 60
                        }
                    }
                    if daysA >= 2, daysB >= 2, !together {
                        let nameA = neighbors.first(
                            where: { $0.ip == ipA })?
                            .displayName ?? ipA
                        let nameB = neighbors.first(
                            where: { $0.ip == ipB })?
                            .displayName ?? ipB
                        found.append(Insight(
                            id: "against-" + fact.id,
                            when: now,
                            title: "Against its own record",
                            body: "\(nameA) and \(nameB) "
                                + "were never far apart — "
                                + "but these last four days "
                                + "both have been about, on "
                                + "their own days, and never "
                                + "together once. Whatever "
                                + "woke the one no longer "
                                + "wakes the other.",
                            citations: [],
                            confidence: 0.5))
                    }
                }
            }
            if fact.id == "fact-foreign" {
                // The foreign habits are watched
                // too: cadence flags are the foreign
                // hands' own events, and a flag
                // outside the known hours — or on a
                // weekend, against the weekday
                // claim — breaks the fact.
                let cadenceDay = dayEvents.filter {
                    $0.module == "emcon" && $0.kind == "cadence"
                }
                if let start = fact.windowStart,
                   let end = fact.windowEnd {
                    let outside = cadenceDay.filter { e in
                        let h = Calendar.current.component(
                            .hour, from: e.when)
                        return !(start < end
                            ? (h >= start && h < end)
                            : (h >= start || h < end))
                    }
                    if let rogue = outside.first {
                        found.append(Insight(
                            id: "against-fact-foreign",
                            when: rogue.when,
                            title: "Against its own record",
                            body: "Foreign hands were only "
                                + "ever known in the small "
                                + "hours (\(start):00–"
                                + "\(end):00) — but a cadence "
                                + "flag landed at "
                                + rogue.when.formatted(
                                    date: .omitted,
                                    time: .shortened)
                                + ". The habit is broken, "
                                + "or new hands have arrived.",
                            citations: [Self.cite(rogue)],
                            confidence: 0.55))
                    }
                } else if !fact.text.contains("small hours") {
                    // The weekday claim. (A small-hours
                    // fact learned before the watch
                    // recorded its hours carries no
                    // window — it is not tested
                    // against the wrong claim.)
                    let weekend = cadenceDay.filter { e in
                        let wd = Calendar.current.component(
                            .weekday, from: e.when)
                        return wd == 1 || wd == 7
                    }
                    if let rogue = weekend.first {
                        found.append(Insight(
                            id: "against-fact-foreign",
                            when: rogue.when,
                            title: "Against its own record",
                            body: "Foreign hands were only "
                                + "ever known on weekdays — "
                                + "but a cadence flag landed "
                                + "on a weekend, at "
                                + rogue.when.formatted(
                                    date: .abbreviated,
                                    time: .shortened)
                                + ". The habit is broken, "
                                + "or new hands have arrived.",
                            citations: [Self.cite(rogue)],
                            confidence: 0.55))
                    }
                }
            }
        }

        // The operator, read against himself.
        let instrument = InstrumentCenter.shared
        if let base = instrument.restingBaseline,
           let latest = instrument.restingLatest,
           latest - base >= 5 {
            found.append(Insight(
                id: "operator-body",
                when: now,
                title: "The operator ran hot",
                body: "Your resting heart read "
                    + "\(Int(latest.rounded())) against "
                    + "your own fortnight baseline of "
                    + "\(Int(base.rounded()))"
                    + (nightEvents.count >= 3
                       ? ", on a night the house was "
                         + "awake after midnight" : "")
                    + ". A correlation, printed as one — "
                    + "not a cause.",
                citations: [],
                confidence: 0.55))
        } else if let baseHours = instrument.sleepBaselineHours,
                  let window = instrument.lastSleep {
            let slept = window.end.timeIntervalSince(
                window.start) / 3600
            if baseHours - slept >= 1.5 {
                found.append(Insight(
                    id: "operator-sleep",
                    when: window.end,
                    title: "A short night",
                    body: "You slept "
                        + InstrumentCenter.durationLine(window)
                        + " against your usual "
                        + String(format: "%.1f", baseHours)
                        + " hours"
                        + (nightEvents.count >= 3
                           ? ", and the house was awake "
                             + "for much of it" : "")
                        + ". Noted because tired operators "
                        + "and busy houses so often arrive "
                        + "together.",
                    citations: [],
                    confidence: 0.5))
            }
        }
        // Variability and temperature, against
        // themselves — the two streams the
        // Instrument always collected and never
        // thought with, now baselined like the rest.
        if let base = instrument.hrvBaseline,
           let latest = instrument.hrvLatest,
           base - latest >= 8 {
            found.append(Insight(
                id: "operator-hrv",
                when: now,
                title: "The operator's variability dipped",
                body: "Heart-rate variability read "
                    + "\(Int(latest.rounded())) ms "
                    + "against your own fortnight "
                    + "baseline of \(Int(base.rounded())) "
                    + "ms — the nervous system's ledger, "
                    + "read against itself. Strain, "
                    + "short sleep, and coming illness "
                    + "all write in it. A correlation, "
                    + "printed as one — not a cause.",
                citations: [],
                confidence: 0.5))
        }
        if let base = instrument.tempBaseline,
           let latest = instrument.tempLatest,
           latest - base >= 0.4 {
            found.append(Insight(
                id: "operator-temp",
                when: now,
                title: "The operator ran warm in the night",
                body: "Sleeping wrist temperature read "
                    + String(format: "%.1f", latest - base)
                    + "° above your own fortnight "
                    + "baseline — the deviation the "
                    + "watch itself treats as worth a "
                    + "second look. A correlation, "
                    + "printed as one — not a cause.",
                citations: [],
                confidence: 0.5))
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
        // Learned priority: confidence, bent by the
        // verdicts' precision for its kind — the kinds
        // the operator confirms rise; the kinds he
        // dismisses sink. Stories keep their boost.
        func priority(_ insight: Insight) -> Double {
            let v = state.verdicts?[insight.kind] ?? [0, 0]
            let right = Double(v.first ?? 0)
            let wrong = Double(v.count > 1 ? v[1] : 0)
            let total = right + wrong
            let taught = total == 0 ? 1.0
                : 0.6 + 0.7 * (right / total)
            let story = insight.id.hasPrefix("pattern-")
                ? 1.15 : 1.0
            return insight.confidence * taught * story
        }
        insights = found.sorted {
            let pa = priority($0), pb = priority($1)
            if pa != pb { return pa > pb }
            return $0.when > $1.when
        }
        brief = Self.composeBrief(events: events,
                                  neighbors: neighbors,
                                  insights: insights,
                                  now: now)
        // What the operator has taught it to trust,
        // when a taught kind stands among the findings.
        for insight in insights {
            let v = state.verdicts?[insight.kind] ?? [0, 0]
            let right = v.first ?? 0
            let wrong = v.count > 1 ? v[1] : 0
            if right + wrong >= 3,
               Double(right) / Double(right + wrong) >= 0.75 {
                brief += " It leads with the kind of "
                    + "finding you have confirmed "
                    + "\(right) of \(right + wrong) times."
                break
            }
        }
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
        // While you slept: the record, windowed by the
        // Instrument's own testimony.
        if q.contains("asleep") || q.contains("while i slept")
            || q.contains("while you slept") {
            if let w = InstrumentCenter.shared.lastSleep {
                return events.filter {
                    $0.when >= w.start && $0.when <= w.end }
            }
            return []
        }
        // The Instrument answers for itself.
        if q.contains("sleep") || q.contains("heart")
            || q.contains("resting") || q.contains("oxygen") {
            let inst = InstrumentCenter.shared
            var parts: [String] = []
            if let w = inst.lastSleep {
                parts.append("Last night you slept "
                    + InstrumentCenter.durationLine(w)
                    + " (asleep "
                    + w.start.formatted(date: .omitted,
                                         time: .shortened)
                    + " → "
                    + w.end.formatted(date: .omitted,
                                       time: .shortened)
                    + ")"
                    + (inst.sleepBaselineHours.map {
                        ", against your usual "
                            + String(format: "%.1f", $0)
                            + " hours" } ?? ""))
            }
            if let hr = inst.restingHeartRate {
                parts.append("resting heart \(hr.value)"
                    + (inst.restingBaseline.map {
                        ", baseline "
                        + "\(Int($0.rounded()))" } ?? ""))
            }
            if let o2 = inst.oxygen {
                parts.append("blood oxygen \(o2.value)")
            }
            let text = parts.isEmpty
                ? "The Instrument has no readings yet — "
                  + "it reads from EMCON, once you let "
                  + "the house read it."
                : "The Instrument says: "
                  + parts.joined(separator: "; ") + "."
            return [NightEvent(id: UUID().uuidString,
                               when: Date(), module: "instrument",
                               kind: "reading", text: text)]
        }
        // First appearance of a device.
        if q.contains("first") {
            if let neighbor = neighborsForAsk().first(where: {
                q.contains($0.ip)
                    || q.contains($0.displayName.lowercased())
                    || ($0.name.map {
                        q.contains($0.lowercased()) } ?? false)
            }) {
                let mine = events.filter {
                    $0.text.contains(neighbor.ip) }
                if let oldest = mine.last { return [oldest] }
            }
        }
        // Who is on the wire at all.
        if q.contains("who is on") || q.contains("on my wire")
            || q.contains("on my network")
            || q.contains("on the wire") {
            let all = neighborsForAsk()
            let names = all.sorted {
                $0.lastSeen > $1.lastSeen }.prefix(6).map {
                "\($0.displayName) (\($0.ip))" }
            let text = all.isEmpty
                ? "The wire knows nobody yet."
                : "The wire knows \(all.count) device"
                  + (all.count == 1 ? "" : "s")
                  + ": " + names.joined(separator: ", ")
                  + (all.count > 6 ? "\u{2026}" : "") + "."
            return [NightEvent(id: UUID().uuidString,
                               when: Date(),
                               module: "neighborhood",
                               kind: "answer", text: text)]
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
    @State private var confirmReset = false
    @State private var results: [NightEvent]?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("The night, understood")) {
                    Text(mind.brief)
                        .font(.callout)
                }
                Section(header: Text("What the house has learned"),
                        footer: Text("Durable conclusions "
                            + "from the consolidation — each "
                            + "kept with its evidence and its "
                            + "birthday. Forget one and the "
                            + "mind remembers the forgetting: "
                            + "it will not quietly re-teach "
                            + "it tomorrow.")) {
                    if mind.facts.isEmpty {
                        Text("Nothing yet. As the record "
                             + "deepens, the mind writes "
                             + "down what it concludes — "
                             + "quiet hours, a regular's "
                             + "rhythm, two who stir "
                             + "together — and keeps it here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mind.facts) { fact in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text(fact.text)
                                    .font(.callout)
                                Text(fact.evidence
                                     + " · learned "
                                     + fact.learnedAt.formatted(
                                        date: .abbreviated,
                                        time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                mind.forgetFact(fact.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Forget this fact")
                        }
                    }
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
                Section(header: Text("Housekeeping"),
                        footer: Text("The mind's only memory "
                            + "of itself: which drift it has "
                            + "already reckoned, your verdicts "
                            + "on its findings, and the facts "
                            + "it has learned.")) {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Label("Reset the mind's memory",
                              systemImage: "trash")
                    }
                }
            }
            .navigationTitle("The Subconscious")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Reset the mind's memory?",
                isPresented: $confirmReset,
                titleVisibility: .visible) {
                Button("Forget baselines and verdicts",
                       role: .destructive) {
                    mind.reset()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Drift it has already reckoned will be "
                     + "reported once more, confidences go "
                     + "back to their unbent values, and every "
                     + "learned fact is forgotten.")
            }
            .onAppear { mind.refresh() }
        }
    }
}
