import SwiftUI

/// Sparring Season: a week of being hunted by your own ghost.
///
/// Self-sparring is a drill; a season is a campaign. Begin
/// one and, across seven days, a ghost comes at this phone
/// the way the world would — sometimes loud, spelling its
/// knocks where the grader can hear them; sometimes quiet,
/// under the threshold, betting the steward is asleep; and
/// twice, politely, with the vault combination printed in
/// the manual, to see whether you ever changed it. Every
/// visit runs through the real defenses — tripwire, engine,
/// prober files, steward, vault — because the ghost knocks
/// through the same door everyone else does.
///
/// The ghost plays when the instrument is awake: iOS gives a
/// closed app no ears, and the season does not pretend
/// otherwise. Visits fall due at their hours and play on the
/// next waking, and the night log records them as season
/// business, at the time they truly knocked.
///
/// The week closes with a grade, sealed into the night log.
final class Season: ObservableObject {
    struct Visit: Codable, Identifiable {
        var id: String
        var due: Date
        var kind: String   // loud | quiet | vault
        var played = false
        var caught: Bool?
        var line = ""
    }

    struct State: Codable {
        var started: Date
        var visits: [Visit]
        var defense = 0
        var ghost = 0
        var closed = false
        var grade = ""
    }

    @Published private(set) var state: State?
    @Published private(set) var playing = false

    static let ghostSource = "ghost (season)"
    static let spanDays = 7
    private static let storeKey = "season.state"

    init() { load() }

    // MARK: - persistence

    private func load() {
        guard let data = UserDefaults.standard.data(
                forKey: Self.storeKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        state = try? decoder.decode(State.self, from: data)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: - lifecycle

    var running: Bool { state != nil && state?.closed == false }

    func begin() {
        let kinds = ["loud", "quiet", "loud", "vault", "quiet",
                     "loud", "quiet", "vault", "loud"]
        let span = Double(Self.spanDays) * 86_400
        var visits: [Visit] = []
        for (index, kind) in kinds.enumerated() {
            // The first visit comes quickly, so the operator
            // sees the ghost work; the rest scatter by chance
            // across the week, one to a stretch.
            let due = index == 0
                ? Date().addingTimeInterval(90)
                : Date().addingTimeInterval(
                    3_600 + span * Double(index) / Double(kinds.count)
                    + Double.random(in: 0...(span / 9)))
            visits.append(Visit(id: UUID().uuidString, due: due,
                                kind: kind))
        }
        state = State(started: Date(), visits: visits)
        save()
        Journal.log("season", "begun",
                    "a sparring season began — nine visits over "
                    + "seven days; the ghost is already "
                    + "choosing its hours")
    }

    func abandon() {
        guard state != nil else { return }
        state = nil
        save()
        Journal.log("season", "abandoned",
                    "the season was called off by the operator")
    }

    private func closeIfFinished() {
        guard var current = state, !current.closed else { return }
        let weekOver = Date() > current.started.addingTimeInterval(
            Double(Self.spanDays) * 86_400)
        let allPlayed = current.visits.allSatisfy { $0.played }
        guard weekOver && allPlayed else { return }
        current.closed = true
        let d = current.defense, g = current.ghost
        current.grade = d > g
            ? "the house held — \(d) to \(g). The ghost went home hungry."
            : (d == g
               ? "an even week — \(d) to \(g). The ghost respects the house, and checks its locks twice now."
               : "the ghost ate well — \(g) to \(d). Read its visits; every one is a lesson with the answer attached.")
        state = current
        save()
        Journal.log("season", "verdict",
                    "season closed: defense \(d), ghost \(g) — "
                    + current.grade)
    }

    // MARK: - the ghost plays

    /// Called whenever the instrument wakes (and on a slow
    /// timer while EMCON is on screen): a due visit plays.
    func tick(emcon: Emcon) {
        guard var current = state, !current.closed, !playing
        else { return }
        closeIfFinished()
        guard state?.closed == false else { return }
        current = state!
        guard let index = current.visits.firstIndex(
            where: { !$0.played && $0.due <= Date() })
        else { return }
        play(index: index, emcon: emcon)
    }

    private func play(index: Int, emcon: Emcon) {
        guard let kind = state?.visits[index].kind else { return }
        playing = true
        let proposalsBefore = Set(emcon.steward.proposals.map(\.id))
        let casesBefore = Set(emcon.steward.cases.map(\.id))
        Journal.log("season", "visit",
                    "visit \(index + 1) — the ghost comes "
                    + "\(kind == "vault" ? "politely, with a combination" : kind == "loud" ? "loudly" : "quietly")")
        switch kind {
        case "loud":
            let ports = Array(Knocktalk.alphabet.shuffled()
                .prefix(8))
            for (step, port) in ports.enumerated() {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Double(step) * 0.22) {
                    emcon.ghostKnock(
                        source: Self.ghostSource, port: port,
                        verdict: "silent knock (no bytes sent)")
                }
            }
            resolve(after: Double(ports.count) * 0.22 + 5,
                    index: index, emcon: emcon,
                    proposalsBefore: proposalsBefore,
                    casesBefore: casesBefore)
        case "quiet":
            let ports = Array(Knocktalk.alphabet.shuffled()
                .prefix(5))
            for (step, port) in ports.enumerated() {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Double(step) * 3.5) {
                    emcon.ghostKnock(
                        source: Self.ghostSource, port: port,
                        verdict: "silent knock (no bytes sent)")
                }
            }
            resolve(after: Double(ports.count) * 3.5 + 6,
                    index: index, emcon: emcon,
                    proposalsBefore: proposalsBefore,
                    casesBefore: casesBefore)
        default: // vault
            let words: [(Int, String)] = [
                (22, "SSH client banner (the season ghost)"),
                (443, "TLS ClientHello (the season ghost)"),
                (1883, "nightjar-hack probe: mqtt-connect "
                       + "(the season ghost)"),
            ]
            for (step, word) in words.enumerated() {
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + Double(step) * 1.4) {
                    emcon.ghostKnock(source: Self.ghostSource,
                                     port: word.0,
                                     verdict: word.1)
                }
            }
            resolve(after: Double(words.count) * 1.4 + 3,
                    index: index, emcon: emcon,
                    proposalsBefore: proposalsBefore,
                    casesBefore: casesBefore)
        }
    }

    private func resolve(after delay: Double, index: Int,
                         emcon: Emcon,
                         proposalsBefore: Set<String>,
                         casesBefore: Set<String>) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            [weak self] in
            guard let self = self, var current = self.state,
                  current.visits.indices.contains(index)
            else { self?.playing = false; return }
            let kind = current.visits[index].kind
            var caught = false
            var line = ""
            switch kind {
            case "loud":
                caught = Journal.events(limit: 80).contains {
                    $0.module == "emcon" && $0.kind == "knocktalk"
                        && $0.text.contains(
                            "pattern from \(Self.ghostSource)")
                }
                line = caught
                    ? "came loudly — the grader heard it spell"
                    : "came loudly and the grader missed it"
                if caught { current.defense += 2 }
                else { current.ghost += 2 }
            case "quiet":
                let newProposals = emcon.steward.proposals
                    .filter {
                        !proposalsBefore.contains($0.id)
                            && ($0.title.contains("ghost")
                                || $0.detail.contains("ghost")
                                || ($0.host ?? "")
                                    .contains("ghost"))
                    }
                let newCases = emcon.steward.cases.filter {
                    !casesBefore.contains($0.id)
                        && $0.hosts.contains { $0.contains("ghost") }
                }
                caught = !newProposals.isEmpty || !newCases.isEmpty
                line = caught
                    ? "came quietly — but the steward stirred"
                    : "came quietly, and slipped the house"
                if caught { current.defense += 2 }
                else { current.ghost += 2 }
            default: // vault
                let opened = (emcon.vaultOpenUntil ?? .distantPast)
                    > Date()
                caught = !opened
                line = opened
                    ? "spoke the PRINTED combination — and the "
                      + "vault opened. Change the combination."
                    : "tried the printed combination; the "
                      + "vault held"
                if opened { current.ghost += 3 }
                else { current.defense += 1 }
            }
            current.visits[index].played = true
            current.visits[index].caught = caught
            current.visits[index].line = line
            self.state = current
            self.save()
            self.playing = false
            Journal.log("season", "visit",
                        "visit \(index + 1) (\(kind)): \(line) — "
                        + "defense \(current.defense), ghost "
                        + "\(current.ghost)")
            self.closeIfFinished()
        }
    }

    // MARK: - lines for the card

    var dayLine: String {
        guard let state = state else { return "" }
        let day = Int(Date().timeIntervalSince(state.started)
                      / 86_400) + 1
        return state.closed
            ? "closed — \(state.grade)"
            : "day \(min(day, Self.spanDays)) of \(Self.spanDays)"
                + " · defense \(state.defense) — ghost \(state.ghost)"
    }

    var nextLine: String {
        guard let state = state, !state.closed,
              let next = state.visits.first(where: { !$0.played })
        else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "next visit " + fmt.localizedString(
            for: next.due, relativeTo: Date())
    }
}

/// EMCON's season card.
struct SeasonSectionView: View {
    @ObservedObject var season: Season
    let emcon: Emcon
    private let pulse = Timer.publish(every: 20, on: .main,
                                      in: .common).autoconnect()

    var body: some View {
        Section(header: Text("Sparring season — a week of ghost"),
                footer: Text("One drill tests a wall; a season "
                    + "tests the watch. The ghost visits while "
                    + "the instrument is awake — a closed app "
                    + "has no ears, and the season does not "
                    + "pretend otherwise.")) {
            if let state = season.state {
                Text(season.dayLine).font(.callout)
                if !state.closed {
                    Text(season.nextLine)
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(state.visits.filter { $0.played }) { visit in
                    HStack(spacing: 6) {
                        Image(systemName: visit.caught == true
                              ? "shield.fill"
                              : "shield.slash")
                            .foregroundStyle(visit.caught == true
                                              ? Color.green
                                              : Color.orange)
                        Text(visit.line).font(.caption)
                    }
                }
                if season.playing {
                    HStack {
                        ProgressView()
                        Text("The ghost is at the door…")
                            .font(.callout)
                    }
                }
                if !state.closed {
                    Button("Call off the season",
                           role: .destructive) {
                        season.abandon()
                    }
                }
            } else {
                Text("For seven days, a ghost of your own "
                     + "raising comes at this phone — loud, "
                     + "quiet, and once or twice with the vault "
                     + "combination printed in the manual. Your "
                     + "defenses answer as they truly are, and "
                     + "the night log keeps the score.")
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    season.begin()
                    season.tick(emcon: emcon)
                } label: {
                    Label("Begin the season",
                          systemImage: "moon.stars")
                }
            }
        }
        .onAppear { season.tick(emcon: emcon) }
        .onReceive(pulse) { _ in season.tick(emcon: emcon) }
    }
}
