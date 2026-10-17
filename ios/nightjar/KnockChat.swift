import Combine
import CryptoKit
import Foundation

/// KnockChat: Knocktalk as an actual conversation.
///
/// Two devices running this app are both always listening (the
/// tripwire never closes), so the channel is two-way by nature:
/// a message is a knock stream one way, its ACK a knock stream
/// back. This model owns the threads and the delivery protocol:
///
///  - send: seal once, fragment, knock the frames. State:
///    sending → awaiting.
///  - The receiver reassembles and knocks an ACK naming the
///    message's hash → state: delivered.
///  - Holes in a reassembly make the receiver knock a NACK
///    listing the missing fragments; the sender re-knocks only
///    those (two repair rounds, then an honest `failed`).
///  - No answer inside the airtime-plus-margin window →
///    `failed`, with a manual resend.
///
/// Threads persist as JSON in Documents. Decoded texts live
/// here and nowhere else — the night log records that messages
/// moved, never what they said.
final class KnockChat: ObservableObject {
    struct ChatMessage: Identifiable, Codable {
        var id: String
        var peer: String
        var outgoing: Bool
        var text: String
        var when: Date
        /// sending | awaiting | delivered | failed | received
        var state: String
        /// ACK-matching hash nibbles (outgoing only).
        var hash: [Int]?
        /// The suite this message was sealed under (outgoing
        /// only) — repairs must re-knock fragments of the
        /// ORIGINAL sealing, in its own suite.
        var suite: Int?
    }

    /// The suite this operator sends with — their choice, set
    /// in the Knocktalk tab. Receiving needs no matching setting:
    /// every fragment names its suite and the open follows it.
    @Published private(set) var sendSuite: Int =
        UserDefaults.standard.object(forKey: "knocktalkSuite")
            as? Int ?? Knocktalk.suiteChaCha

    func setSendSuite(_ suite: Int) {
        sendSuite = suite
        UserDefaults.standard.set(suite, forKey: "knocktalkSuite")
    }

    @Published private(set) var threads: [String: [ChatMessage]] = [:]

    let sender = KnockSender()

    /// The burn timer, moved here from EMCON with the messages:
    /// hours, 0 = never, default 24.
    @Published var retentionHours: Double =
        UserDefaults.standard.object(forKey: "knocktalkRetentionHours")
            as? Double ?? 24

    private var outbox: [(peer: String, frames: [[Int]],
                          messageID: String?)] = []
    private var sealedStore: [String: Data] = [:]
    private var repairRounds: [String: Int] = [:]
    private var ackTimers: [String: Timer] = [:]
    private var sendStarted: [String: Date] = [:]
    private var sendKnocks: [String: Int] = [:]

    // MARK: - the delivery ledger

    /// What deliveries to each peer actually cost —
    /// the airtime per knock and the fragment loss
    /// rate, learned from every send this center
    /// settles or repairs. The deadline and the
    /// repair budget used to be computed from a
    /// fiction (0.55 s per knock for every peer,
    /// two repair rounds for every message); they
    /// are read off this ledger now, with the old
    /// constants standing as floors.
    private static let ledgerKey = "knockDeliveryLedger"

    private struct PeerDelivery {
        var perKnock: Double = 0.55
        var lossRate: Double = 0
        var samples: Int = 0
    }

    private func peerDelivery(_ peer: String) -> PeerDelivery {
        let all = UserDefaults.standard.dictionary(
            forKey: Self.ledgerKey)
            as? [String: [String: Double]] ?? [:]
        guard let entry = all[peer] else {
            return PeerDelivery() }
        return PeerDelivery(
            perKnock: entry["perKnock"] ?? 0.55,
            lossRate: entry["lossRate"] ?? 0,
            samples: Int(entry["samples"] ?? 0))
    }

    private func savePeerDelivery(_ peer: String,
                                  _ stats: PeerDelivery) {
        var all = UserDefaults.standard.dictionary(
            forKey: Self.ledgerKey)
            as? [String: [String: Double]] ?? [:]
        all[peer] = ["perKnock": stats.perKnock,
                     "lossRate": stats.lossRate,
                     "samples": Double(stats.samples)]
        UserDefaults.standard.set(all, forKey: Self.ledgerKey)
    }

    private func noteDelivered(_ message: ChatMessage) {
        guard let started = sendStarted[message.id],
              let knocks = sendKnocks[message.id],
              knocks > 0 else { return }
        sendStarted[message.id] = nil
        sendKnocks[message.id] = nil
        let sample = Date().timeIntervalSince(started)
            / Double(knocks)
        var stats = peerDelivery(message.peer)
        stats.perKnock = stats.samples == 0 ? sample
            : stats.perKnock * 0.6 + sample * 0.4
        stats.samples += 1
        savePeerDelivery(message.peer, stats)
    }

    private func noteLoss(peer: String, missing: Int,
                          total: Int) {
        guard total > 0 else { return }
        var stats = peerDelivery(peer)
        stats.lossRate = stats.lossRate * 0.6
            + (Double(missing) / Double(total)) * 0.4
        savePeerDelivery(peer, stats)
    }

    /// Every road to "delivered" runs through here,
    /// so the ledger hears about each arrival.
    private func settleDelivered(_ message: ChatMessage) {
        ackTimers[message.id]?.invalidate()
        ackTimers[message.id] = nil
        update(message.id) { $0.state = "delivered" }
        noteDelivered(message)
    }
    private let saveQueue = DispatchQueue(label: "nightjar.knockchat.save")
    private var senderForwarding: AnyCancellable?

    /// Sequences that arrive through the operator's relay are
    /// replayed into the knock engine through this hook (wired
    /// by Emcon at launch: source "relay:<mailbox>", ports in
    /// order, the silent-knock verdict).
    var onRelayFrame: ((_ from: String, _ ports: [Int]) -> Void)?
    private var relayTimer: Timer?
    private var relayDeclaring = false
    @Published private(set) var relayStatus = ""

    /// Cadence Seal verdicts by peer, set by the EMCON routing
    /// as messages land. Display only — the seal never blocks.
    @Published private(set) var cadenceNotes: [String: String] = [:]

    /// Burn everything: every thread, every cadence
    /// note. The pairing key is NOT touched — the house
    /// forgets the conversations, not how to have them.
    func clearAllThreads() {
        threads = [:]
        cadenceNotes = [:]
        save()
    }

    func setCadenceNote(peer: String, note: String) {
        cadenceNotes[peer] = note
    }

    init() {
        threads = Self.loadThreads()
        purge()
        sender.onQueueEmpty = { [weak self] in
            self?.pumpOutbox()
        }
        // The conversation view reads the sender's progress
        // through the chat — forward its pulses.
        senderForwarding = sender.objectWillChange.sink {
            [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - peers + keys

    /// Thread keys are bare addresses — the tripwire's source
    /// labels (" (this device)") are display text, and an ACK
    /// must find the thread the operator opened by address.
    static func peerKey(_ raw: String) -> String {
        raw.components(separatedBy: " ").first ?? raw
    }

    var peersByRecency: [String] {
        threads.keys.sorted {
            (threads[$0]?.last?.when ?? .distantPast)
                > (threads[$1]?.last?.when ?? .distantPast)
        }
    }

    var totalMessages: Int {
        threads.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - sending

    /// Seal, fragment, and queue a message. Returns false when
    /// the sealed form exceeds the fragment budget — better an
    /// honest refusal than a silent truncation.
    @discardableResult
    func send(text: String, to rawPeer: String,
              key: SymmetricKey) -> Bool {
        let peer = Self.peerKey(rawPeer)
        guard !peer.isEmpty,
              let sealed = try? Knocktalk.seal(text, key: key,
                                               suite: sendSuite),
              sealed.count <= Knocktalk.maxSealedBytes
        else { return false }
        let message = ChatMessage(
            id: UUID().uuidString, peer: peer, outgoing: true,
            text: text, when: Date(), state: "sending",
            hash: Knocktalk.hashNibbles(of: sealed), suite: sendSuite)
        append(message)
        sealedStore[message.id] = sealed
        repairRounds[message.id] = 0
        outbox.append((peer: peer,
                       frames: Knocktalk.fragmentFrames(
                        sealed: sealed, suite: sendSuite),
                       messageID: message.id))
        pumpOutbox()
        return true
    }

    /// Manual resend of a failed message: the whole message,
    /// fresh rounds.
    func resend(messageID: String, key: SymmetricKey) {
        guard let message = find(messageID),
              let sealed = try? Knocktalk.seal(message.text, key: key,
                                               suite: sendSuite)
        else { return }
        sealedStore[messageID] = sealed
        repairRounds[messageID] = 0
        update(messageID) {
            $0.state = "sending"
            $0.suite = sendSuite
            $0.hash = Knocktalk.hashNibbles(of: sealed)
        }
        outbox.append((peer: message.peer,
                       frames: Knocktalk.fragmentFrames(
                        sealed: sealed, suite: sendSuite),
                       messageID: messageID))
        pumpOutbox()
    }

    private func pumpOutbox() {
        guard !sender.busy, !relayDeclaring, !outbox.isEmpty
        else { return }
        let next = outbox.removeFirst()
        if let box = KnockRelay.mailbox(ofPeer: next.peer) {
            // A mailbox peer: declare the destination at the
            // operator's relay, then knock the sequence at the
            // relay host — from the wire's point of view the
            // relay IS the other phone's perimeter.
            guard KnockRelay.configured,
                  let relayHost = KnockRelay.host else {
                if let id = next.messageID {
                    update(id) { $0.state = "failed" }
                }
                pumpOutbox()
                return
            }
            relayDeclaring = true
            KnockRelay.declare(to: box) { [weak self] ok in
                guard let self = self else { return }
                self.relayDeclaring = false
                guard ok else {
                    if let id = next.messageID {
                        self.update(id) { $0.state = "failed" }
                    }
                    self.pumpOutbox()
                    return
                }
                self.sender.sendFrames(host: relayHost,
                                       frames: next.frames)
                self.trackDelivery(of: next)
            }
            return
        }
        sender.sendFrames(host: next.peer, frames: next.frames)
        trackDelivery(of: next)
    }

    private func trackDelivery(of next: (peer: String,
                                         frames: [[Int]],
                                         messageID: String?)) {
        guard let id = next.messageID else {
            // ACK/NACK frames: nothing to track; the sender's
            // drain callback pumps the next item.
            return
        }
        // When THIS send drains, mark awaiting and arm the
        // delivery deadline. The sender's callback is one-shot
        // per drain, so chain through a wrapper: poll on the
        // sender's published state instead — simpler and honest.
        let knocks = next.frames.reduce(0) { $0 + $1.count }
        sendStarted[id] = Date()
        sendKnocks[id] = knocks
        // The deadline is read off this peer's
        // ledger entry — never tighter than the
        // old fiction's deadline, looser when the
        // peer has proven slower than 0.55 s a
        // knock.
        let stats = peerDelivery(next.peer)
        let deadline = max(
            TimeInterval(Knocktalk.etaSeconds(knocks: knocks)) + 90,
            Double(knocks) * stats.perKnock * 1.6 + 30)
        ackTimers[id]?.invalidate()
        ackTimers[id] = Timer.scheduledTimer(
            withTimeInterval: deadline, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.find(id)?.state == "awaiting" {
                self.update(id) { $0.state = "failed" }
            }
        }
        // Flip sending → awaiting as soon as the frames drain:
        // observe via a short repeating check on the sender.
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if !self.sender.busy {
                timer.invalidate()
                if self.find(id)?.state == "sending" {
                    self.update(id) { $0.state = "awaiting" }
                }
                self.pumpOutbox()
            }
        }
    }

    // MARK: - receiving (called by Emcon from engine outputs)

    func receive(text: String, from rawSource: String,
                 ackHash: [Int]?) {
        let peer = Self.peerKey(rawSource)
        append(ChatMessage(id: UUID().uuidString, peer: peer,
                             outgoing: false, text: text,
                             when: Date(), state: "received",
                             hash: nil, suite: nil))
        purge()
        if let ackHash = ackHash {
            outbox.append((peer: peer,
                           frames: [Knocktalk.ackFrame(hash: ackHash)],
                           messageID: nil))
            pumpOutbox()
        }
    }

    /// A voice-throw receipt settles the throw's delivery:
    /// the receipt IS the confirmation, spoken in sentences
    /// where an ACK is four nibbles.
    func settleThrow(instructionID: String, peer rawPeer: String) {
        let peer = Self.peerKey(rawPeer)
        guard let messages = threads[peer],
              let message = messages.last(where: {
                  $0.outgoing
                      && VoiceThrowCodec.instructionID(of: $0.text)
                          == instructionID
              }) else { return }
        settleDelivered(message)
    }

    /// A duel message in reply settles the outgoing duel
    /// message it answers — the herald's traffic confirms
    /// itself the same way the ventriloquist's does.
    func settleDuel(duelID: String, peer rawPeer: String) {
        let peer = Self.peerKey(rawPeer)
        guard let messages = threads[peer],
              let message = messages.last(where: {
                  $0.outgoing
                      && DuelCodec.id(of: $0.text) == duelID
              }) else { return }
        settleDelivered(message)
    }

    func handleAck(from rawSource: String, hash: [Int]) {
        let peer = Self.peerKey(rawSource)
        guard let message = threads[peer]?.last(where: {
            $0.outgoing && $0.hash == hash
                && ($0.state == "awaiting" || $0.state == "sending")
        }) else { return }
        ackTimers[message.id]?.invalidate()
        update(message.id) { $0.state = "delivered" }
    }

    func handleNack(from rawSource: String, missing: [Int]) {
        let peer = Self.peerKey(rawSource)
        guard let message = threads[peer]?.last(where: {
            $0.outgoing
                && ($0.state == "awaiting" || $0.state == "sending")
        }), let sealed = sealedStore[message.id] else { return }
        let all = Knocktalk.fragmentFrames(
            sealed: sealed, suite: message.suite ?? Knocktalk.suiteChaCha)
        noteLoss(peer: peer, missing: missing.count,
                 total: all.count)
        let rounds = repairRounds[message.id] ?? 0
        // The repair budget scales with the
        // message and the peer's proven loss —
        // two rounds at base, more for long
        // messages and lossy peers. A
        // sixteen-fragment message through a
        // lossy relay was being failed by the
        // same budget as a two-fragment note on
        // a quiet wire.
        let budget = 2 + min(3, all.count / 6)
            + (peerDelivery(peer).lossRate > 0.25 ? 1 : 0)
        guard rounds < budget else {
            update(message.id) { $0.state = "failed" }
            return
        }
        repairRounds[message.id] = rounds + 1
        let wanted = missing.filter { $0 >= 0 && $0 < all.count }
        guard !wanted.isEmpty else { return }
        update(message.id) { $0.state = "sending" }
        outbox.append((peer: peer,
                       frames: wanted.map { all[$0] },
                       messageID: message.id))
        pumpOutbox()
    }

    /// Our reassembly of the peer's message has holes: knock
    /// the list back.
    func requestRepair(to rawSource: String, missing: [Int]) {
        let peer = Self.peerKey(rawSource)
        outbox.append((peer: peer,
                       frames: [Knocktalk.nackFrame(missing: missing)],
                       messageID: nil))
        pumpOutbox()
    }

    // MARK: - relay

    /// (Re)arm the mailbox poll. Called at launch and whenever
    /// the operator edits the relay settings. The poll runs
    /// only while a relay is fully configured; five seconds
    /// between checks is nothing on a channel whose unit of
    /// time is a five-second knock frame.
    func refreshRelayPolling() {
        relayTimer?.invalidate()
        relayTimer = nil
        guard KnockRelay.configured else {
            relayStatus = ""
            return
        }
        relayStatus = "relay: \(KnockRelay.host ?? "") · "
            + "mailbox \(KnockRelay.mailbox)"
        pollRelay()
        relayTimer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.pollRelay()
        }
    }

    private func pollRelay() {
        guard KnockRelay.configured else {
            // Settings were cleared under a running timer (a
            // defaults reset): stand down quietly.
            relayTimer?.invalidate()
            relayTimer = nil
            relayStatus = ""
            return
        }
        KnockRelay.fetchInbox { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.relayStatus = "relay unreachable: "
                    + error.localizedDescription
            case .success(let frames):
                self.relayStatus =
                    "relay: \(KnockRelay.host ?? "") · "
                    + "mailbox \(KnockRelay.mailbox)"
                for frame in frames {
                    self.onRelayFrame?(frame.from, frame.ports)
                }
            }
        }
    }

    /// A message picked up by brush pass (proximity BLE).
    /// Like a chirp, the medium has no acknowledgement — the
    /// host never learns its drop was taken.
    func receiveBrush(text: String) {
        append(ChatMessage(id: UUID().uuidString, peer: "brush",
                           outgoing: false, text: text,
                           when: Date(), state: "received",
                           hash: nil, suite: nil))
        purge()
    }

    /// A message that arrived by light (Blink). Like sound
    /// and proximity, the medium is one-way — no ACK rides a
    /// QR frame back.
    /// A time capsule, ground open. It arrives whenever the
    /// grinding finished — the lock set the schedule, so the
    /// thread simply keeps what the past sent forward.
    func receiveCapsule(text: String) {
        append(ChatMessage(id: UUID().uuidString, peer: "capsule",
                           outgoing: false, text: text,
                           when: Date(), state: "received",
                           hash: nil, suite: nil))
        purge()
        Journal.log("knocktalk", "capsule",
                    "a time capsule opened and was filed")
    }

    func receiveBlink(text: String) {
        append(ChatMessage(id: UUID().uuidString, peer: "blink",
                           outgoing: false, text: text,
                           when: Date(), state: "received",
                           hash: nil, suite: nil))
        purge()
    }

    /// A message that arrived by sound (Chirp). That medium
    /// has no way to knock an ACK back — the sender watches a
    /// progress bar, not a delivery state — so chirps file as
    /// plain received messages in their own thread.
    func receiveChirp(text: String) {
        append(ChatMessage(id: UUID().uuidString, peer: "chirp",
                           outgoing: false, text: text,
                           when: Date(), state: "received",
                           hash: nil, suite: nil))
        purge()
    }

    // MARK: - retention + persistence

    func setRetention(hours: Double) {
        retentionHours = hours
        UserDefaults.standard.set(hours,
                                  forKey: "knocktalkRetentionHours")
        purge()
    }

    /// Burn every message past the retention line, both
    /// directions — a conversation is two copies of a secret.
    func purge() {
        guard retentionHours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-retentionHours * 3600)
        var changed = false
        for peer in Array(threads.keys) {
            let kept = threads[peer]?.filter { $0.when >= cutoff } ?? []
            if kept.count != threads[peer]?.count {
                threads[peer] = kept.isEmpty ? nil : kept
                changed = true
            }
        }
        if changed { save() }
    }

    /// Burn everything, right now — every thread, every
    /// message, whatever the retention setting says. The
    /// knock vault's burn macro lands here.
    func burnNow() {
        threads = [:]
        save()
        Journal.log("knocktalk", "burn",
                    "all threads burned on command")
    }

    func clearThread(_ peer: String) {
        threads[peer] = nil
        save()
    }

    private func append(_ message: ChatMessage) {
        threads[message.peer, default: []].append(message)
        save()
    }

    private func find(_ id: String) -> ChatMessage? {
        threads.values.flatMap { $0 }.first { $0.id == id }
    }

    private func update(_ id: String, _ mutate: (inout ChatMessage) -> Void) {
        for peer in Array(threads.keys) {
            guard var list = threads[peer],
                  let index = list.firstIndex(where: { $0.id == id })
            else { continue }
            mutate(&list[index])
            threads[peer] = list
            save()
            return
        }
    }

    private static var threadsURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("knocktalk-threads.json")
    }

    private static func loadThreads() -> [String: [ChatMessage]] {
        guard let data = try? Data(contentsOf: threadsURL),
              let decoded = try? JSONDecoder().decode(
                [String: [ChatMessage]].self, from: data)
        else { return [:] }
        return decoded
    }

    private func save() {
        let snapshot = threads
        saveQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.threadsURL, options: .atomic)
            }
        }
    }

    /// One-time migration: the v1 inbox (whole-message frames,
    /// no threads) becomes received messages in per-source
    /// threads.
    func importLegacy(_ messages: [KnockMessage]) {
        for message in messages {
            let peer = Self.peerKey(message.source)
            append(ChatMessage(id: message.id, peer: peer,
                                 outgoing: false, text: message.text,
                                 when: message.when, state: "received",
                                 hash: nil, suite: nil))
        }
    }
}
