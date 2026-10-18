import SwiftUI

/// Duel Mode: two phones, one wire, scored rounds.
///
/// One phone is the ground; the other comes at it. The host
/// defends with whatever it truly runs — Serve, the canary,
/// the tripwire's watched ports — and the guest strikes three
/// ports a round from an arena dealt off the defender's real
/// surface, padded with decoys. The referee is the defender's
/// own testimony: its event log says what it heard, the
/// guest's Recon says what answered, and the points fall out
/// of the two accounts —
///
///   an answered strike:        attacker +2
///   answered but never heard:  attacker +1 more (it slipped)
///   a heard strike:            defender +2
///
/// Control rides Knocktalk like everything else in this
/// house: invites, arenas, strikes, and tallies are sealed
/// messages with a duel header, intercepted before the
/// thread. The fighting itself is LAN-only and honest about
/// it — a duel is fought on one wire, against an address,
/// between two phones the operator owns.
enum DuelCodec {
    static let prefix = "NJ-DUEL/1:"

    struct Msg: Codable {
        var v = 1
        var kind: String   // invite|accept|refuse|round|strikes|tally
        var id: String
        var n: Int?
        var arena: [Int]?
        var seconds: Int?
        var ip: String?
        var ports: [Int]?
        var open: [Int]?
        var heard: [Int]?
        var def: Int?
        var atk: Int?
    }

    static func encode(_ msg: Msg) -> String? {
        guard let data = try? JSONEncoder().encode(msg)
        else { return nil }
        return prefix + data.base64EncodedString()
    }

    static func decode(_ text: String) -> Msg? {
        guard text.hasPrefix(prefix),
              let data = Data(base64Encoded: String(
                  text.dropFirst(prefix.count))),
              let msg = try? JSONDecoder().decode(Msg.self,
                                                  from: data),
              msg.v == 1
        else { return nil }
        return msg
    }

    static func id(of text: String) -> String? {
        decode(text)?.id
    }

    static func displayText(_ text: String) -> String {
        guard let msg = decode(text) else { return text }
        switch msg.kind {
        case "invite": return "⚔️ a duel was offered"
        case "accept": return "⚔️ the duel was accepted"
        case "refuse": return "⚔️ the duel was refused"
        case "round": return "⚔️ round \(msg.n ?? 0) — the "
            + "arena is dealt"
        case "strikes": return "⚔️ strikes: "
            + (msg.ports ?? []).map(String.init)
                .joined(separator: ", ")
        case "tally": return "⚔️ tally — defense "
            + "\(msg.def ?? 0), attack \(msg.atk ?? 0)"
        default: return "⚔️ duel business"
        }
    }
}

final class DuelCenter: ObservableObject {
    // idle | inviting | invited | round | between | done
    @Published private(set) var phase = "idle"
    @Published private(set) var isHost = false
    @Published private(set) var lines: [String] = []
    @Published var picked: Set<Int> = []

    private(set) var peer = ""
    private(set) var duelID = ""
    private(set) var guestIP = ""
    private(set) var hostIP = ""
    @Published private(set) var roundNumber = 0
    @Published private(set) var arena: [Int] = []
    @Published private(set) var defScore = 0
    @Published private(set) var atkScore = 0

    let recon = Recon()
    private var roundStart = Date.distantPast
    private var strikesSent = false

    static let roundsTotal = 3
    static let strikesPerRound = 3
    private static let decoys = [22, 25, 80, 443, 1883, 5060,
                                 5900, 8080, 9100, 53, 3306, 8443]

    private func say(_ line: String) {
        lines.insert(line, at: 0)
        if lines.count > 30 { lines.removeLast(lines.count - 30) }
    }

    private func send(_ msg: DuelCodec.Msg, chat: KnockChat) {
        guard let key = KnockKeyStore.key,
              let text = DuelCodec.encode(msg) else { return }
        chat.send(text: text, to: peer, key: key)
    }

    // MARK: - hosting and joining

    func hostDuel(peer rawPeer: String, chat: KnockChat) {
        guard phase == "idle" else { return }
        peer = KnockChat.peerKey(rawPeer)
        duelID = String(UUID().uuidString.prefix(8)).lowercased()
        isHost = true
        hostIP = Mouth.localIPAddress() ?? ""
        phase = "inviting"
        send(.init(kind: "invite", id: duelID, ip: hostIP),
             chat: chat)
        say("You offered \(peer) a duel on this wire. Your "
            + "phone is the ground.")
        Journal.log("duel", "invite",
                    "a duel was offered to \(peer)")
    }

    func accept(chat: KnockChat) {
        guard phase == "invited" else { return }
        guestIP = Mouth.localIPAddress() ?? ""
        send(.init(kind: "accept", id: duelID, ip: guestIP),
             chat: chat)
        phase = "between"
        say("Duel accepted. The arena is being dealt…")
    }

    func refuse(chat: KnockChat) {
        guard phase == "invited" else { return }
        send(.init(kind: "refuse", id: duelID), chat: chat)
        reset()
        say("You refused the duel.")
    }

    func reset() {
        phase = "idle"
        isHost = false
        peer = ""
        duelID = ""
        roundNumber = 0
        arena = []
        picked = []
        defScore = 0
        atkScore = 0
        strikesSent = false
    }

    // MARK: - rounds

    private func buildArena(emcon: Emcon) -> [Int] {
        var live: [Int] = []
        let defaults = UserDefaults.standard
        if emcon.mouth?.serveRunning == true {
            if let tcp = defaults.string(forKey: "serveTcpPort")
                .flatMap(Int.init) { live.append(tcp) }
            if let http = defaults.string(forKey: "serveHttpPort")
                .flatMap(Int.init) { live.append(http) }
        }
        if let canary = emcon.mouth?.canary.runningPort {
            live.append(canary)
        }
        live += emcon.watched
        var pool = Array(Set(live)).filter { $0 > 0 }
        pool.shuffle()
        var arena = Array(pool.prefix(3))
        for decoy in Self.decoys.shuffled()
        where arena.count < 6 && !arena.contains(decoy) {
            arena.append(decoy)
        }
        return arena.shuffled()
    }

    func startRound(chat: KnockChat, emcon: Emcon) {
        guard isHost, phase == "between" || phase == "inviting"
                || phase == "round" else { return }
        roundNumber += 1
        arena = buildArena(emcon: emcon)
        picked = []
        roundStart = Date()
        phase = "round"
        send(.init(kind: "round", id: duelID, n: roundNumber,
                   arena: arena, seconds: 60), chat: chat)
        say("Round \(roundNumber) dealt: "
            + arena.map(String.init).joined(separator: ", ")
            + " — three of these are yours to lose.")
        Journal.log("duel", "round",
                    "round \(roundNumber) dealt against \(peer)")
    }

    func strike(chat: KnockChat) {
        guard !isHost, phase == "round",
              picked.count == Self.strikesPerRound,
              !hostIP.isEmpty else { return }
        strikesSent = false
        say("Striking \(picked.sorted().map(String.init).joined(separator: ", ")) "
            + "at \(hostIP)…")
        recon.knock(host: hostIP, ports: picked.sorted(),
                    udp: false)
    }

    /// Called by the view when the strike's knock resolves.
    func strikesLanded(chat: KnockChat) {
        guard !isHost, phase == "round", !strikesSent else {
            return
        }
        strikesSent = true
        let opened = recon.hits.filter { $0.isOpen }
            .map { $0.port }
        send(.init(kind: "strikes", id: duelID, n: roundNumber,
                   ports: picked.sorted(), open: opened),
             chat: chat)
        phase = "between"
        say("Struck. Open: "
            + (opened.isEmpty ? "nothing answered"
               : opened.map(String.init).joined(separator: ", "))
            + ". Waiting for the tally…")
    }

    // MARK: - the wire

    func intercept(text: String, source: String, chat: KnockChat,
                   emcon: Emcon) -> Bool {
        guard let msg = DuelCodec.decode(text) else { return false }
        if !duelID.isEmpty, msg.id != duelID {
            return true   // another duel's business: swallow it
        }
        switch msg.kind {
        case "invite":
            guard phase == "idle" else {
                return true
            }
            duelID = msg.id
            peer = KnockChat.peerKey(source)
            hostIP = msg.ip ?? ""
            isHost = false
            phase = "invited"
            say("\(source) offers a duel — their phone is the "
                + "ground, yours the blade.")
            Journal.log("duel", "invite",
                        "a duel was offered by \(source)")
        case "accept":
            guard isHost, phase == "inviting" else { return true }
            guestIP = msg.ip ?? ""
            phase = "between"
            say("\(source) accepted. Deal the first round when "
                + "ready.")
            startRound(chat: chat, emcon: emcon)
        case "refuse":
            say("The duel was refused.")
            Journal.log("duel", "refused",
                        "the duel with \(peer) was refused")
            reset()
        case "round":
            guard !isHost else { return true }
            roundNumber = msg.n ?? roundNumber
            arena = msg.arena ?? []
            picked = []
            roundStart = Date()
            phase = "round"
            say("Round \(roundNumber). The arena: "
                + arena.map(String.init).joined(separator: ", ")
                + " — pick \(Self.strikesPerRound) and strike.")
        case "strikes":
            guard isHost, msg.n == roundNumber else { return true }
            tally(msg, chat: chat, emcon: emcon)
        case "tally":
            guard !isHost else { return true }
            defScore = msg.def ?? defScore
            atkScore = msg.atk ?? atkScore
            let heard = (msg.heard ?? []).map(String.init)
                .joined(separator: ", ")
            say("Tally for round \(msg.n ?? 0): they heard "
                + (heard.isEmpty ? "nothing" : heard)
                + ". Defense \(defScore) — attack \(atkScore).")
            if (msg.n ?? 0) >= Self.roundsTotal {
                finish()
            } else {
                phase = "between"
            }
        default:
            break
        }
        chat.settleDuel(duelID: msg.id, peer: source)
        return true
    }

    private func tally(_ msg: DuelCodec.Msg, chat: KnockChat,
                       emcon: Emcon) {
        let struck = msg.ports ?? []
        let opened = msg.open ?? []
        let heardSet = Set(emcon.events
            .filter { event in
                event.when >= roundStart.addingTimeInterval(-2)
                    && event.source.contains(guestIP)
            }
            .map { $0.port })
        let heard = struck.filter { heardSet.contains($0) }
        let atkRound = opened.count * 2
            + opened.filter { !heardSet.contains($0) }.count
        let defRound = heard.count * 2
        atkScore += atkRound
        defScore += defRound
        send(.init(kind: "tally", id: duelID, n: roundNumber,
                   heard: heard, def: defScore, atk: atkScore),
             chat: chat)
        say("Round \(roundNumber): struck "
            + struck.map(String.init).joined(separator: ", ")
            + "; answered "
            + (opened.isEmpty ? "none"
               : opened.map(String.init).joined(separator: ", "))
            + "; heard "
            + (heard.isEmpty ? "none"
               : heard.map(String.init).joined(separator: ", "))
            + ". Attack +\(atkRound), defense +\(defRound).")
        Journal.log("duel", "round",
                    "round \(roundNumber) tallied — defense "
                    + "\(defScore), attack \(atkScore)")
        if roundNumber >= Self.roundsTotal {
            finish()
        } else {
            phase = "between"
        }
    }

    private func finish() {
        phase = "done"
        let verdict = defScore > atkScore
            ? "The ground held — defense \(defScore), attack "
              + "\(atkScore). The house wins."
            : (defScore == atkScore
               ? "An even duel — \(defScore) apiece. Both "
                 + "phones leave with respect."
               : "The blade got in — attack \(atkScore), "
                 + "defense \(defScore). The ground has homework.")
        say(verdict)
        Journal.log("duel", "verdict",
                    "duel with \(peer) closed — \(verdict)")
    }
}

/// EMCON's duel card: opens the arena.
struct DuelSectionView: View {
    let emcon: Emcon
    @Binding var showing: Bool

    var body: some View {
        Section(header: Text("Duel — two phones, one wire"),
                footer: Text("One phone is the ground, the "
                    + "other the blade: three rounds of strikes "
                    + "against its real surface, refereed by "
                    + "its own event log.")) {
            Button {
                showing = true
            } label: {
                Label("Enter the arena",
                      systemImage: "figure.fencing")
            }
        }
    }
}

struct DuelView: View {
    @ObservedObject var center: DuelCenter
    let emcon: Emcon
    let chat: KnockChat
    @Environment(\.dismiss) private var dismiss
    @State private var peerDraft = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(statusLine)
                        .font(.callout.weight(.semibold))
                    if center.phase != "idle"
                        && center.phase != "done" {
                        Text("Defense \(center.defScore) — "
                             + "attack \(center.atkScore) · "
                             + "round \(center.roundNumber)/"
                             + "\(DuelCenter.roundsTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if center.phase == "idle" {
                    Section(header: Text("Host — your phone is the ground")) {
                        TextField("opponent — IP, or relay:name",
                                  text: $peerDraft)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.callout.monospaced())
                        Button("Offer the duel") {
                            Haptics.tap()
                            center.hostDuel(peer: peerDraft,
                                            chat: chat)
                        }
                        .disabled(peerDraft.trimmingCharacters(
                            in: .whitespaces).isEmpty
                            || KnockKeyStore.key == nil)
                        Text("Raise EMCON and stand your ground "
                             + "up first — Serve, the canary, the "
                             + "tripwire. The arena is dealt from "
                             + "what you actually run.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if center.phase == "invited" {
                    Section(header: Text("A duel is offered")) {
                        Button("Accept — take up the blade") {
                            Haptics.tap()
                            center.accept(chat: chat)
                        }
                        Button("Refuse", role: .destructive) {
                            center.refuse(chat: chat)
                        }
                    }
                }
                if center.isHost, center.phase == "between" {
                    Section {
                        Button("Deal the next round") {
                            Haptics.tap()
                            center.startRound(chat: chat,
                                              emcon: emcon)
                        }
                    }
                }
                if !center.isHost, center.phase == "round" {
                    Section(header: Text("Round \(center.roundNumber) — choose \(DuelCenter.strikesPerRound) and strike")) {
                        ForEach(center.arena, id: \.self) { port in
                            Button {
                                toggle(port)
                            } label: {
                                HStack {
                                    Text("\(port) — "
                                         + (ScanModel.serviceNames[port] ?? ""))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if center.picked.contains(port) {
                                        Image(systemName:
                                              "checkmark.circle.fill")
                                    }
                                }
                            }
                        }
                        if center.recon.knocking {
                            HStack {
                                ProgressView()
                                Text("Striking…").font(.callout)
                            }
                        } else {
                            Button("Strike") {
                                Haptics.tap()
                                center.strike(chat: chat)
                            }
                            .disabled(center.picked.count
                                      != DuelCenter.strikesPerRound)
                        }
                    }
                }
                if center.phase == "done" {
                    Section {
                        Button("Leave the arena") {
                            center.reset()
                            dismiss()
                        }
                    }
                }
                if center.phase != "idle" {
                    Section {
                        Button("Abandon the duel",
                               role: .destructive) {
                            center.reset()
                        }
                    }
                }
                if !center.lines.isEmpty {
                    Section(header: Text("The duel, as it happened")) {
                        ForEach(Array(center.lines.enumerated()),
                                id: \.offset) { _, line in
                            Text(line).font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Duel")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: center.recon.knocking) { knocking in
                if !knocking {
                    center.strikesLanded(chat: chat)
                }
            }
        }
    }

    private var statusLine: String {
        switch center.phase {
        case "idle": return "No duel stands."
        case "inviting": return "Offer sent — awaiting an answer."
        case "invited": return "A duel is offered to you."
        case "round": return center.isHost
            ? "Round \(center.roundNumber): your ground is "
              + "being struck."
            : "Round \(center.roundNumber): strike."
        case "between": return "Between rounds."
        case "done": return "The duel is decided."
        default: return center.phase
        }
    }

    private func toggle(_ port: Int) {
        if center.picked.contains(port) {
            center.picked.remove(port)
        } else if center.picked.count < DuelCenter.strikesPerRound {
            center.picked.insert(port)
        }
    }
}
