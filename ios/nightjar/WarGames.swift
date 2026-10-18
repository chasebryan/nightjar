import SwiftUI

// MARK: - War Games
//
// Two of the operator's own phones spar. The defender serves —
// listeners up, decoys flying, inbox watching. The attacker
// traces and knocks. The match protocol rides the app's own
// wire: control lines and match cards travel as payloads into
// the peer's Serve inbox (stealth Serve still records arrivals
// silently, which is exactly what a defender wants), and the
// scoring reconciliation diffs what the attacker found
// against what the defender actually ran and caught.
//
// Both phones foreground during a round. No third party is
// involved, ever: this is a sparring ring for your own gear.

/// One door, as either card states it.
struct WarDoor: Codable, Hashable {
    var port: Int
    var proto: String          // "tcp" | "udp"
    var service: String
    var confirmed: Bool        // answered as the service (★)

    var key: String { "\(port)/\(proto)" }
}

/// One arrival the defender caught during the round window.
struct WarCatch: Codable {
    var at: Date
    var transport: String
    var peer: String
}

/// What one side states about the round, signed with nothing
/// but the match ID: the attacker's findings, or the
/// defender's truth (what it served, what it flew as decoys,
/// what it caught). The two cards meeting on one phone is
/// the whole reconciliation.
struct WarCard: Codable {
    var matchID: String
    var round: Int
    var role: String           // "attacker" | "defender"
    var deviceLabel: String
    var ip: String
    var foundDoors: [WarDoor]  // attacker: doors it found
    var bleNamesHeard: [String]
    var servedDoors: [WarDoor] // defender: doors it ran
    var decoys: [String]       // defender: names it flew
    var caught: [WarCatch]     // defender: arrivals caught
}

/// The scored round, and the file the match leaves behind.
struct WarMatchReport: Codable {
    var schema: String
    var schemaVersion: Int
    var matchID: String
    var round: Int
    var scoredAt: Date
    var attackerLabel: String
    var defenderLabel: String
    var found: [WarDoor]
    var missed: [WarDoor]
    var caughtCount: Int
    var decoysSeen: [String]
    var decoysUnseen: [String]
    var attackerPoints: Int
    var defenderPoints: Int
    var verdict: String
    var limitations: [String]

    static let limitations = [
        "Both phones foreground for the round; iOS suspends "
            + "the engines in the background.",
        "Control rides the Serve inbox: a phone not serving "
            + "cannot be challenged, and a stealth defender "
            + "still records arrivals silently.",
        "Caught counts payload-bearing arrivals in the "
            + "defender's inbox during the window. A silent "
            + "connect that sends nothing may leave no trace "
            + "there, and is not counted.",
        "The trace is TCP-only: a UDP listener is found only "
            + "if the attacker's knock pass covered its port.",
        "Decoys are scored by name against what the "
            + "attacker's Listen heard — Listen must be "
            + "running on the attacking phone for the air "
            + "game to count.",
    ]

    /// The diff, with the arithmetic in the open: found doors
    /// are the attacker's craft, missed doors and caught
    /// knocks are the defender's, decoys cut both ways.
    static func score(attacker: WarCard,
                      defender: WarCard) -> WarMatchReport {
        let served = Dictionary(
            defender.servedDoors.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first })
        let found = Dictionary(
            attacker.foundDoors.map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first })
        var foundList: [WarDoor] = []
        var missedList: [WarDoor] = []
        for (key, door) in served {
            if let hit = found[key] {
                foundList.append(WarDoor(
                    port: door.port, proto: door.proto,
                    service: door.service,
                    confirmed: hit.confirmed))
            } else {
                missedList.append(door)
            }
        }
        let order: (WarDoor, WarDoor) -> Bool = {
            $0.port != $1.port ? $0.port < $1.port
                               : $0.proto < $1.proto
        }
        foundList.sort(by: order)
        missedList.sort(by: order)

        let caught = defender.caught.filter {
            warIP(fromPeer: $0.peer) == attacker.ip
        }.count

        let heard = Set(attacker.bleNamesHeard
            .map { $0.lowercased() })
        var seen: [String] = []
        var unseen: [String] = []
        for decoy in defender.decoys {
            if heard.contains(decoy.lowercased()) {
                seen.append(decoy)
            } else {
                unseen.append(decoy)
            }
        }

        let attackerPoints = foundList.count * 10
            + foundList.filter { $0.confirmed }.count * 5
            + seen.count * 5
        let defenderPoints = missedList.count * 10
            + min(caught, 10) * 2
            + unseen.count * 5
        let verdict: String
        if attackerPoints > defenderPoints {
            verdict = "The attacker takes the round — "
                + "\(attackerPoints) to \(defenderPoints). "
                + "The wire was read better than it was held."
        } else if defenderPoints > attackerPoints {
            verdict = "The defender takes the round — "
                + "\(defenderPoints) to \(attackerPoints). "
                + "The house saw more than it showed."
        } else {
            verdict = "Honours even — \(attackerPoints) apiece. "
                + "Run it back."
        }
        return WarMatchReport(
            schema: "net.nosuchmachine.nightjar.wargames",
            schemaVersion: 1,
            matchID: attacker.matchID,
            round: attacker.round,
            scoredAt: Date(),
            attackerLabel: attacker.deviceLabel,
            defenderLabel: defender.deviceLabel,
            found: foundList,
            missed: missedList,
            caughtCount: caught,
            decoysSeen: seen,
            decoysUnseen: unseen,
            attackerPoints: attackerPoints,
            defenderPoints: defenderPoints,
            verdict: verdict,
            limitations: limitations)
    }
}

/// The peer address out of an inbox peer string
/// ("192.168.4.20:54321" → "192.168.4.20").
func warIP(fromPeer peer: String) -> String {
    let parts = peer.split(separator: ":")
    if parts.count == 2,
       parts[0].split(separator: ".").count == 4 {
        return String(parts[0])
    }
    return peer
}

// MARK: - The match controller

final class WarGamesCenter: ObservableObject {
    static let shared = WarGamesCenter()

    @Published var matchID: String = WarGamesCenter.newMatchID()
    @Published var round: Int = 1
    @Published var role: String = "defender"
    @Published var phase: String = "No match running."
    @Published var log: [String] = []
    @Published var myCard: WarCard?
    @Published var theirCard: WarCard?
    @Published var report: WarMatchReport?
    @Published var reportURL: URL?
    @Published var defenderReady = false

    weak var mouth: Mouth?
    weak var post: ListeningPost?
    let recon = Recon()

    private var timer: Timer?
    private var processedInbox: Set<UUID> = []
    private var peerIP: String = ""
    private var peerLabel: String = ""
    private var matchPort: Int = 9000

    // Attack bookkeeping
    private var awaiting: String?     // "READY" | "ARMED"
    private var awaitDeadline: Date?
    private var attacking = false
    private var sawTraceBusy = false
    private var attackStart = Date()
    private var knockPlan: [(host: String, ports: [Int], udp: Bool)] = []
    private var knockIndex = 0
    private var knockInFlight = false
    private var attackConfig: WarConfig?
    private var reconPorts: [Int] = []
    private var reconUDP: Bool = false

    // Defense bookkeeping
    private var windowOpen = false
    private var windowBaseline: Set<UUID> = []

    private init() {}

    /// The peer a challenge is out to — Skelli's hands
    /// begin an attack against the challenged defender,
    /// never at a name spoken loosely.
    var challengedPeer: String { peerIP }

    static func newMatchID() -> String {
        "WG-" + String(UUID().uuidString.prefix(4)).uppercased()
    }

    // MARK: lifecycle

    // The 1-second tick runs only while someone holds
    // the center: the room while it is on screen, or
    // Skelli's hands while a voice-run match is live.
    // It used to start on the first attach and run for
    // the rest of the process, match or no match.
    private var viewHeld = false
    private var handsHeld = false

    func attach(mouth: Mouth, post: ListeningPost) {
        self.mouth = mouth
        self.post = post
        recon.mouth = mouth
        viewHeld = true
        startTimerIfNeeded()
    }

    func attachForHands(mouth: Mouth, post: ListeningPost) {
        self.mouth = mouth
        self.post = post
        recon.mouth = mouth
        handsHeld = true
        startTimerIfNeeded()
    }

    /// The room is off screen: drop its hold.
    func detach() {
        viewHeld = false
        stopTimerIfUnheld()
    }

    /// Skelli's errand is done: drop her hold.
    func detachHands() {
        handsHeld = false
        stopTimerIfUnheld()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                     repeats: true) {
            [weak self] _ in self?.tick()
        }
    }

    private func stopTimerIfUnheld() {
        guard !viewHeld, !handsHeld else { return }
        timer?.invalidate()
        timer = nil
    }

    func newMatch() {
        matchID = Self.newMatchID()
        round = 1
        resetRound()
        phase = "New match \(matchID). "
            + (role == "attacker"
                ? "Challenge the defender when ready."
                : "Waiting for a challenge.")
        note("match \(matchID) created")
    }

    func nextRound() {
        round += 1
        resetRound()
        phase = "Round \(round) — fresh cards."
    }

    func setRole(_ newRole: String) {
        guard newRole != role else { return }
        role = newRole
        resetRound()
        phase = newRole == "attacker"
            ? "Attacker — challenge a serving defender."
            : "Defender — keep Serve up and this room open."
    }

    private func resetRound() {
        myCard = nil
        theirCard = nil
        report = nil
        reportURL = nil
        awaiting = nil
        attacking = false
        defenderReady = false
        knockPlan = []
        knockIndex = 0
        knockInFlight = false
        windowOpen = false
    }

    // MARK: wire

    private func sendControl(_ text: String, to ip: String) {
        guard let mouth = mouth, !ip.isEmpty else { return }
        mouth.sendNetwork(
            target: .tcp(host: ip, port: matchPort, tls: false),
            payload: Data(text.utf8),
            framing: "raw", read: false, timeout: 3)
        note("→ \(ip): \(text.prefix(60))")
    }

    private func note(_ text: String) {
        log.append(text)
        if log.count > 120 { log.removeFirst(log.count - 120) }
    }

    // MARK: attacker flow

    func challenge(defenderIP: String, port: Int,
                   myControlPort: Int, myLabel: String) {
        peerIP = defenderIP
        matchPort = port
        resetRound()
        sendControl("NJWG/1 HELLO \(matchID) \(round) "
                    + "\(myControlPort) \(myLabel)",
                    to: defenderIP)
        awaiting = "READY"
        awaitDeadline = Date().addingTimeInterval(20)
        phase = "Challenge sent — waiting for the defender "
            + "to answer READY."
    }

    func beginAttack(config: WarConfig, knockPorts: [Int],
                     knockUDP: Bool) {
        attackConfig = config
        reconPorts = knockPorts
        reconUDP = knockUDP
        sendControl("NJWG/1 START \(matchID) \(round)", to: peerIP)
        awaiting = "ARMED"
        awaitDeadline = Date().addingTimeInterval(10)
        phase = "START sent — waiting for ARMED."
    }

    private func runAttack() {
        guard let mouth = mouth, let config = attackConfig
        else { return }
        attacking = true
        sawTraceBusy = false
        collectedHits = []
        attackStart = Date()
        phase = "Attacking — tracing \(peerIP)'s wire."
        mouth.startNetworkTrace(
            scopeText: peerIP,
            discoveryPorts: config.discoveryPorts,
            profilePorts: config.profilePorts,
            includeBonjour: config.includeBonjour,
            adaptive: config.adaptive,
            rules: TraceRule.parse(config.rulesText),
            probeFor: { _ in nil },
            payloadNamed: { _ in nil })
    }

    private func finishTracePhase() {
        // Doors the trace filed on the defender this attack.
        let grace = attackStart.addingTimeInterval(-5)
        var tcpPorts = Set(reconPorts)
        var udpPorts = Set<Int>()
        if let host = TraceBookStore.shared.allDossiers()
            .first(where: { $0.ip == peerIP }) {
            for service in host.services
            where service.lastSeen >= grace {
                if service.proto == "udp" {
                    udpPorts.insert(service.port)
                } else {
                    tcpPorts.insert(service.port)
                }
            }
        }
        if reconUDP { udpPorts.formUnion(reconPorts) }
        knockPlan = []
        if !tcpPorts.isEmpty {
            knockPlan.append((peerIP, tcpPorts.sorted(), false))
        }
        if !udpPorts.isEmpty {
            knockPlan.append((peerIP, udpPorts.sorted(), true))
        }
        knockIndex = 0
        knockInFlight = false
        phase = knockPlan.isEmpty
            ? "No doors to knock — filing the card."
            : "Knocking the defender's doors."
        if knockPlan.isEmpty { buildAttackerCard() }
    }

    private func tickKnocks() {
        if knockInFlight {
            guard !recon.knocking else { return }
            knockInFlight = false
            collectedHits += recon.hits
            knockIndex += 1
        }
        guard knockIndex < knockPlan.count else {
            buildAttackerCard()
            return
        }
        let step = knockPlan[knockIndex]
        recon.knock(host: step.host, ports: step.ports,
                    udp: step.udp,
                    timeout: attackConfig?.knockTimeout ?? 1.5,
                    jobs: attackConfig?.knockJobs ?? 24)
        knockInFlight = true
    }

    private func buildAttackerCard() {
        let grace = attackStart.addingTimeInterval(-5)
        var doors: [String: WarDoor] = [:]
        if let host = TraceBookStore.shared.allDossiers()
            .first(where: { $0.ip == peerIP }) {
            for service in host.services
            where service.lastSeen >= grace {
                let door = WarDoor(port: service.port,
                                   proto: service.proto,
                                   service: service.serviceName,
                                   confirmed: false)
                doors[door.key] = door
            }
        }
        for hit in collectedHits where hit.isOpen {
            let door = WarDoor(port: hit.port,
                               proto: hit.udp ? "udp" : "tcp",
                               service: hit.service,
                               confirmed: hit.confirmed)
            if let existing = doors[door.key] {
                doors[door.key] = WarDoor(
                    port: door.port, proto: door.proto,
                    service: door.service,
                    confirmed: existing.confirmed || door.confirmed)
            } else {
                doors[door.key] = door
            }
        }
        var names: Set<String> = []
        if let post = post, post.session != nil {
            for row in post.rows {
                if let name = row.name { names.insert(name) }
                if let label = row.preferredLabel {
                    names.insert(label)
                }
            }
        }
        let card = WarCard(
            matchID: matchID, round: round, role: "attacker",
            deviceLabel: deviceLabel(), ip: myIP(),
            foundDoors: doors.values.sorted {
                $0.port != $1.port ? $0.port < $1.port
                                   : $0.proto < $1.proto
            },
            bleNamesHeard: names.sorted(),
            servedDoors: [], decoys: [], caught: [])
        myCard = card
        attacking = false
        phase = "Attack complete — \(card.foundDoors.count) "
            + "door(s) found. Sending the card."
        sendControl("NJWG/1 DONE \(matchID) \(round)", to: peerIP)
        sendCard(card, to: peerIP)
        tryScore()
    }

    private var collectedHits: [Recon.Hit] = []

    // MARK: defender flow

    private func onHello(from peer: String, label: String,
                         port: Int,
                         match: String, round incoming: Int) {
        guard role == "defender" else { return }
        if myCard == nil, !windowOpen {
            matchID = match
            round = incoming
            peerIP = peer
            matchPort = port
            peerLabel = label
            phase = "Paired with \(label.isEmpty ? peer : label) "
                + "— match \(match), round \(incoming). "
                + "Serve proud; the attack comes when it comes."
            note("paired: \(peer) as \(label)")
            sendControl("NJWG/1 READY \(matchID) \(round)",
                        to: peer)
        }
    }

    private func onStart(from peer: String) {
        guard role == "defender", peer == peerIP else { return }
        windowBaseline = Set((mouth?.inbox ?? []).map { $0.id })
        windowOpen = true
        phase = "The attack is live — the inbox is the catch "
            + "log. Hold the wire."
        note("catch window opened")
        sendControl("NJWG/1 ARMED \(matchID) \(round)", to: peer)
    }

    private func onDone(from peer: String,
                        serveDoors: [WarDoor],
                        decoys: [String]) {
        guard role == "defender", peer == peerIP else { return }
        windowOpen = false
        let caught = (mouth?.inbox ?? [])
            .filter { item in
                !windowBaseline.contains(item.id)
                    && warIP(fromPeer: item.peer) == peerIP
                    && !(String(data: item.data,
                                encoding: .utf8) ?? "")
                        .hasPrefix("NJWG/1")
            }
            .map { WarCatch(at: $0.at, transport: $0.transport,
                            peer: $0.peer) }
        let card = WarCard(
            matchID: matchID, round: round, role: "defender",
            deviceLabel: deviceLabel(), ip: myIP(),
            foundDoors: [], bleNamesHeard: [],
            servedDoors: serveDoors, decoys: decoys,
            caught: caught)
        defenderServeDoors = serveDoors
        defenderDecoys = decoys
        myCard = card
        phase = "Round over — caught \(caught.count) "
            + "arrival(s). Card sent."
        note("defense card built: \(caught.count) caught")
        sendCard(card, to: peerIP)
        tryScore()
    }

    // The defender's truth is supplied by the view at DONE
    // time (Serve settings + declared decoys ride along with
    // the tick's inbox scan — see tick()).
    private var defenderServeDoors: [WarDoor] = []
    private var defenderDecoys: [String] = []
    func setDefense(serveDoors: [WarDoor], decoys: [String]) {
        defenderServeDoors = serveDoors
        defenderDecoys = decoys
    }

    // MARK: cards + scoring

    private func sendCard(_ card: WarCard, to ip: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(card) else { return }
        let b64 = data.base64EncodedString()
        sendControl("NJWG/1 CARD \(matchID) \(round) \(b64)",
                    to: ip)
    }

    func importCard(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let card = try? decoder.decode(WarCard.self,
                                             from: data)
        else {
            note("imported file is not a match card")
            return
        }
        receiveCard(card)
    }

    private func receiveCard(_ card: WarCard) {
        guard card.matchID == matchID, card.round == round
        else {
            note("card for \(card.matchID) r\(card.round) "
                    + "ignored — not this match")
            return
        }
        theirCard = card
        note("their card received (\(card.role))")
        phase = "Both cards in — the round can be scored."
        tryScore()
    }

    func tryScore() {
        guard let mine = myCard, let theirs = theirCard,
              report == nil else { return }
        let attacker = mine.role == "attacker" ? mine : theirs
        let defender = mine.role == "defender" ? mine : theirs
        guard attacker.role == "attacker",
              defender.role == "defender" else { return }
        let scored = WarMatchReport.score(attacker: attacker,
                                          defender: defender)
        report = scored
        reportURL = writeReport(scored)
        phase = "Round \(round) scored."
        Journal.log("war-games", "score",
                    "match \(matchID) round \(round): "
                    + "attacker \(scored.attackerPoints), "
                    + "defender \(scored.defenderPoints)")
        // A scored round is terminal for the voice
        // hold — her tick can stand down.
        detachHands()
    }

    private func writeReport(_ report: WarMatchReport) -> URL? {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WarGames", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "nightjar-wargames-\(matchID)-r\(round).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else {
            return nil
        }
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// My card as a shareable file, for the import road.
    func myCardURL() -> URL? {
        guard let card = myCard else { return nil }
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WarGames", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "nightjar-card-\(matchID)-r\(round)-\(card.role).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(card) else {
            return nil
        }
        try? data.write(to: url, options: .atomic)
        return url
    }

    // MARK: identity helpers

    private func myIP() -> String {
        Mouth.localIPAddress() ?? ""
    }

    private func deviceLabel() -> String {
        let name = Mouth.wireHostName()
        return name.isEmpty ? "this phone" : name
    }

    // MARK: the tick

    private func tick() {
        scanInbox()
        if let awaiting = awaiting,
           let deadline = awaitDeadline, Date() > deadline {
            self.awaiting = nil
            if awaiting == "READY" {
                phase = "No READY heard. The defender must be "
                    + "serving (Serve tab) with the War Games "
                    + "room open, on the match port."
            } else if awaiting == "ARMED" {
                note("no ARMED — attacking unsynchronised")
                phase = "No ARMED heard — attacking anyway, "
                    + "unsynchronised."
                runAttack()
            }
        }
        if attacking, let mouth = mouth {
            if mouth.traceBusy { sawTraceBusy = true }
            if sawTraceBusy, !mouth.traceBusy {
                sawTraceBusy = false
                finishTracePhase()
            } else if !knockPlan.isEmpty || knockInFlight {
                tickKnocks()
            }
        }
    }

    private func scanInbox() {
        guard let mouth = mouth else { return }
        if processedInbox.count > 5000 {
            processedInbox = Set(mouth.inbox.map { $0.id })
        }
        for item in mouth.inbox
        where !processedInbox.contains(item.id) {
            processedInbox.insert(item.id)
            guard let text = String(data: item.data,
                                    encoding: .utf8),
                  text.hasPrefix("NJWG/1 ")
            else { continue }
            let peer = warIP(fromPeer: item.peer)
            let fields = text.split(separator: " ",
                                    maxSplits: 5)
            guard fields.count >= 4 else { continue }
            let verb = String(fields[1])
            let match = String(fields[2])
            let roundNo = Int(fields[3]) ?? -1
            switch verb {
            case "HELLO":
                let port = fields.count > 4
                    ? (Int(fields[4]) ?? 9000) : 9000
                let label = fields.count > 5
                    ? String(fields[5]) : ""
                onHello(from: peer, label: label, port: port,
                        match: match, round: roundNo)
            case "READY":
                if role == "attacker", match == matchID,
                   roundNo == round, awaiting == "READY" {
                    awaiting = nil
                    defenderReady = true
                    phase = "The defender is READY. Begin the "
                        + "attack when you are."
                    note("defender ready")
                }
            case "START":
                if match == matchID, roundNo == round {
                    onStart(from: peer)
                }
            case "ARMED":
                if role == "attacker", match == matchID,
                   roundNo == round, awaiting == "ARMED" {
                    awaiting = nil
                    phase = "ARMED — the catch window is open. "
                        + "Attacking."
                    runAttack()
                }
            case "DONE":
                if match == matchID, roundNo == round {
                    onDone(from: peer,
                           serveDoors: defenderServeDoors,
                           decoys: defenderDecoys)
                }
            case "CARD":
                if fields.count > 4,
                   let data = Data(base64Encoded: String(fields[4])) {
                    importCard(data: data)
                }
            default:
                break
            }
        }
    }
}

// MARK: - The ring

struct WarGamesView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var post: ListeningPost
    @ObservedObject private var center = WarGamesCenter.shared
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var showAllLog = false

    @AppStorage("serveUseTCP") private var serveUseTCP = true
    @AppStorage("serveTcpPort") private var serveTcpPort = "9000"
    @AppStorage("serveUseUDP") private var serveUseUDP = false
    @AppStorage("serveUdpPort") private var serveUdpPort = "9001"
    @AppStorage("serveUseHTTP") private var serveUseHTTP = false
    @AppStorage("serveHttpPort") private var serveHttpPort = "8080"
    @AppStorage("traceScope") private var traceScope = ""
    @AppStorage("traceDiscoveryPorts")
    private var traceDiscoveryPorts =
        "80,443,22,445,1883,8080,8443,9100"
    @AppStorage("traceProfilePorts") private var traceProfilePorts = ""
    @AppStorage("traceBonjour") private var traceBonjour = true
    @AppStorage("traceAdaptive") private var traceAdaptive = true
    @AppStorage("traceRules") private var traceRules = ""
    @AppStorage("reconPorts")
    private var reconPorts = "22,80,443,445,1883,8080,8443,9100"
    @AppStorage("reconKnockUDP") private var reconKnockUDP = false
    @AppStorage("reconTimeout") private var reconTimeout = 1.5
    @AppStorage("reconJobs") private var reconJobs = 24.0
    @AppStorage("warGamesPeerIP") private var peerIP = ""
    @AppStorage("warGamesMatchPort") private var matchPort = "9000"
    @AppStorage("warGamesDecoys") private var decoysText = ""

    private var myLabel: String {
        let name = Mouth.wireHostName()
        return name.isEmpty ? "this phone" : name
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Match")
                        TextField("WG-XXXX", text: $center.matchID)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                    }
                    HStack {
                        Text("Round")
                        Spacer()
                        Text("\(center.round)")
                            .font(.body.monospaced())
                    }
                    Picker("Role", selection: roleBinding) {
                        Text("Defender").tag("defender")
                        Text("Attacker").tag("attacker")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Button("New match") {
                            Haptics.tap()
                            center.newMatch()
                        }
                        Spacer()
                        Button("Next round") {
                            Haptics.tap()
                            center.nextRound()
                        }
                    }
                    .buttonStyle(.borderless)
                    Text(center.phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Two of your own phones, both "
                        + "foreground. Control rides the Serve "
                        + "inbox — both phones serve during a "
                        + "match.")
                }

                Section("The ring") {
                    if mouth.serveRunning {
                        Label("Serving — this phone can be "
                            + "challenged and can catch",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not serving — the ring is down",
                              systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Button {
                            Haptics.tap()
                            mouth.startServeFromSettings()
                        } label: {
                            Label("Start Serve from settings",
                                  systemImage: "play.circle")
                        }
                    }
                    if post.session == nil {
                        Text("Listen is off — the air game "
                            + "(decoys) needs it running on the "
                            + "attacking phone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if center.role == "attacker" {
                    attackerSection
                } else {
                    defenderSection
                }

                cardsSection

                if let report = center.report {
                    reportSection(report)
                }

                if !center.log.isEmpty {
                    Section("Match log") {
                        ForEach(Array(visibleLog.enumerated()),
                                id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if center.log.count > 30 {
                            Button(showAllLog ? "Fold"
                                   : "Show all \(center.log.count)") {
                                showAllLog.toggle()
                            }
                        }
                    }
                }
            }
            .navigationTitle("War Games")
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                importCard(result)
            }
            .onAppear {
                center.attach(mouth: mouth, post: post)
                pushDefense()
            }
            .onDisappear {
                center.detach()
            }
            .onChange(of: decoysText) { _ in pushDefense() }
            .onChange(of: serveUseTCP) { _ in pushDefense() }
            .onChange(of: serveTcpPort) { _ in pushDefense() }
            .onChange(of: serveUseUDP) { _ in pushDefense() }
            .onChange(of: serveUdpPort) { _ in pushDefense() }
            .onChange(of: serveUseHTTP) { _ in pushDefense() }
            .onChange(of: serveHttpPort) { _ in pushDefense() }
        }
    }

    private var roleBinding: Binding<String> {
        Binding(get: { center.role },
                set: { center.setRole($0) })
    }

    @ViewBuilder private var attackerSection: some View {
        Section("Attack") {
            HStack {
                Text("Defender")
                TextField("192.168.4.31", text: $peerIP)
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            HStack {
                Text("Match port")
                TextField("9000", text: $matchPort)
                    .font(.body.monospaced())
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            Text("The defender's Serve TCP port. Your replies "
                + "come back to this phone's Serve TCP port "
                + "(\(serveTcpPort)) — keep this phone serving "
                + "too.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                center.challenge(
                    defenderIP: peerIP
                        .trimmingCharacters(in: .whitespaces),
                    port: Int(matchPort) ?? 9000,
                    myControlPort: Int(serveTcpPort) ?? 9000,
                    myLabel: myLabel)
            } label: {
                Label("Challenge the defender",
                      systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!mouth.serveRunning
                      || peerIP.trimmingCharacters(
                        in: .whitespaces).isEmpty)
            Button {
                Haptics.tap()
                beginAttack()
            } label: {
                Label("Begin the attack",
                      systemImage: "scope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!center.defenderReady)
            if !center.defenderReady {
                Text("Enabled when the defender answers READY.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var defenderSection: some View {
        Section("Defense") {
            Text("You are serving: "
                + (serveSummary.isEmpty
                   ? "nothing — turn a listener on in Serve"
                   : serveSummary))
                .font(.callout)
            Text("Decoys you're flying — one name per line. "
                + "Fly them from their own tabs (the BLE "
                + "beacon's name in Send, the GATT host in "
                + "Serve); declare them here so the scoring "
                + "knows what to look for in the attacker's "
                + "hearing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $decoysText)
                .font(.body.monospaced())
                .frame(minHeight: 54)
                .scrollContentBackground(.hidden)
            Text("Keep this room open. When the attack lands, "
                + "your catch log is the inbox; when DONE "
                + "arrives, your card builds and sends itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var serveSummary: String {
        var parts: [String] = []
        if serveUseTCP { parts.append("TCP \(serveTcpPort)") }
        if serveUseUDP { parts.append("UDP \(serveUdpPort)") }
        if serveUseHTTP { parts.append("HTTP \(serveHttpPort)") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var cardsSection: some View {
        Section("Cards") {
            HStack {
                Text("My card")
                Spacer()
                Text(center.myCard == nil
                     ? "not filed"
                     : "\(center.myCard!.role) · filed")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Their card")
                Spacer()
                Text(center.theirCard == nil
                     ? "not received"
                     : "\(center.theirCard!.role) · in")
                    .foregroundStyle(.secondary)
            }
            if center.myCard != nil {
                Button {
                    Haptics.select()
                    if let url = center.myCardURL() {
                        shareItem = ShareItem(items: [url])
                    }
                } label: {
                    Label("Share my card",
                          systemImage: "square.and.arrow.up")
                }
            }
            Button {
                Haptics.tap()
                showImporter = true
            } label: {
                Label("Import their card",
                      systemImage: "square.and.arrow.down")
            }
            Text("Cards normally cross on the wire by "
                + "themselves. The file road is the fallback — "
                + "and how a card from anywhere gets scored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func reportSection(_ report: WarMatchReport)
        -> some View {
        Section("Round \(report.round) — scored") {
            Text(report.verdict).font(.headline)
            HStack {
                VStack {
                    Text("\(report.attackerPoints)")
                        .font(.title.weight(.bold))
                    Text(report.attackerLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("attacker").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack {
                    Text("\(report.defenderPoints)")
                        .font(.title.weight(.bold))
                    Text(report.defenderLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("defender").font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !report.found.isEmpty {
                Text("Found: " + report.found.map {
                    "\($0.port)/\($0.proto)"
                        + ($0.confirmed ? " ★" : "")
                }.joined(separator: ", "))
                    .font(.callout)
            }
            if !report.missed.isEmpty {
                Text("Missed: " + report.missed.map {
                    "\($0.port)/\($0.proto)"
                }.joined(separator: ", "))
                    .font(.callout)
            }
            Text("Caught in the act: \(report.caughtCount) "
                + "arrival(s)")
                .font(.callout)
            if !report.decoysSeen.isEmpty {
                Text("Decoys spotted: "
                    + report.decoysSeen.joined(separator: ", "))
                    .font(.callout)
            }
            if !report.decoysUnseen.isEmpty {
                Text("Decoys never seen: "
                    + report.decoysUnseen.joined(separator: ", "))
                    .font(.callout)
            }
            if let url = center.reportURL {
                Button {
                    Haptics.select()
                    shareItem = ShareItem(items: [url])
                } label: {
                    Label("Share the match report",
                          systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var visibleLog: [String] {
        showAllLog ? center.log
                   : Array(center.log.suffix(30))
    }

    private func pushDefense() {
        var doors: [WarDoor] = []
        if serveUseTCP {
            doors.append(WarDoor(
                port: Int(serveTcpPort) ?? 9000, proto: "tcp",
                service: "Serve TCP", confirmed: false))
        }
        if serveUseUDP {
            doors.append(WarDoor(
                port: Int(serveUdpPort) ?? 9001, proto: "udp",
                service: "Serve UDP", confirmed: false))
        }
        if serveUseHTTP {
            doors.append(WarDoor(
                port: Int(serveHttpPort) ?? 8080, proto: "tcp",
                service: "Serve HTTP", confirmed: false))
        }
        let decoys = decoysText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        center.setDefense(serveDoors: doors, decoys: decoys)
    }

    private func beginAttack() {
        let discovery = warGamesParsePorts(traceDiscoveryPorts)
        guard !discovery.isEmpty else {
            toasts.show("The Trace section has no discovery "
                        + "ports set", error: true)
            return
        }
        let profileText = traceProfilePorts
            .trimmingCharacters(in: .whitespaces)
        center.beginAttack(
            config: WarConfig(
                scopeText: traceScope,
                discoveryPorts: discovery,
                profilePorts: profileText.isEmpty
                    ? [] : warGamesParsePorts(traceProfilePorts),
                includeBonjour: traceBonjour,
                adaptive: traceAdaptive,
                rulesText: traceRules,
                includeBLE: post.session != nil,
                knockTimeout: reconTimeout,
                knockJobs: Int(reconJobs)),
            knockPorts: warGamesParsePorts(reconPorts),
            knockUDP: reconKnockUDP)
    }

    private func importCard(_ result:
        Result<URL, Error>) {
        guard case .success(let url) = result
        else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped {
            url.stopAccessingSecurityScopedResource()
        } }
        guard let data = try? Data(contentsOf: url) else {
            toasts.show("That file could not be read",
                        error: true)
            return
        }
        center.importCard(data: data)
        if center.theirCard != nil {
            toasts.show("Card in — scoring follows")
        } else {
            toasts.show("That file is not a card for this "
                        + "match", error: true)
        }
    }
}

/// "80, 443, 22" → [22, 80, 443]: valid ports only,
/// deduplicated, in order.
private func warGamesParsePorts(_ text: String) -> [Int] {
    Array(Set(text.split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        .filter { (1...65535).contains($0) })).sorted()
}
