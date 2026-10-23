import Combine
import CryptoKit
import Foundation
import Network

/// Knocktalk: encrypted messages carried by knock ORDER alone.
///
/// No connection is ever established and no payload byte is ever
/// sent. The sender knocks a sync port, then knocks sixteen
/// alphabet ports in an order that spells nibbles; the receiver's
/// tripwire refuses every knock, replies to nothing — and its
/// log spells a sealed box.
///
/// The encryption is not decoration: the nibbles carry a
/// ChaCha20-Poly1305 sealed box (nonce ‖ ciphertext ‖ tag),
/// sealed under a 256-bit pairing key kept in the Keychain. The
/// Poly1305 tag is the integrity check — a mangled sequence, or
/// one sealed under a different key, fails authentication and
/// decodes to nothing but a "sealed traffic" pattern note, which
/// is also exactly what an unpaired stranger's Knocktalk looks
/// like from the outside. Detection and decryption are the same
/// event.
///
/// Honest limit: a pre-shared key has no forward secrecy. The
/// handshake that would fix that needs a reply channel, and the
/// tripwire never replies — that is rather the point.
enum Knocktalk {
    /// Sixteen watched registry ports = one hex nibble each.
    static let alphabet: [Int] = [7, 9, 13, 19, 21, 22, 23, 25,
                                  43, 53, 70, 79, 80, 110, 111, 143]
    /// Knocked once to open a message window.
    static let syncPort = 443
    /// Silence longer than this closes the window.
    static let gap: TimeInterval = 3.5
    static let maxCharacters = 160

    // MARK: protocol v2 — fragmentation + repair
    //
    // v1 framed a whole message as one knock stream: a single
    // lost knock failed the AEAD open and the message died
    // silently. v2 seals once, then fragments the sealed box.
    // Each fragment frame is [sync] [index] [total] [payload
    // nibbles] [checksum nibble] — the checksum (sum mod 16)
    // exists so a mangled fragment can be dropped and NACKed
    // rather than poisoning the reassembly; the Poly1305 tag
    // remains the real integrity, checked once, at the end.
    // The receiver answers in kind: an ACK frame ([sync] 15 15
    // + four hash nibbles of the sealed box) on success, or a
    // NACK frame ([sync] 14 14 + the missing indices) so the
    // sender re-knocks only what was lost. Two devices running
    // this app are both always listening — the channel is
    // two-way because the tripwire never closes.

    static let fragmentPayloadBytes = 12
    static let maxFragments = 16
    /// Sealed bytes a message may occupy (16 × 12).
    static var maxSealedBytes: Int {
        maxFragments * fragmentPayloadBytes
    }

    // MARK: suites — cryptographic agility
    //
    // Each operator configures the suite THEY send with. The
    // choice is not negotiated and never has to match: a suite
    // nibble rides at the head of every fragment frame, and the
    // receiver opens the reassembled box with whatever suite
    // the frames name. A suite this build doesn't speak still
    // reassembles — and lands as a plainly-labeled note, not
    // garbage. Both suites are AEAD with the same 28-byte
    // overhead, so the framing budget is suite-independent.

    static let suiteChaCha = 0
    static let suiteAESGCM = 1
    static let suiteNames = ["ChaCha20-Poly1305", "AES-256-GCM"]

    enum SealError: Error { case noCombined }

    static func seal(_ plaintext: String, key: SymmetricKey,
                     suite: Int) throws -> Data {
        let data = Data(plaintext.utf8)
        switch suite {
        case suiteAESGCM:
            // A freshly sealed box always has a combined form;
            // the Optional exists for boxes built from parts.
            guard let combined = try AES.GCM.seal(
                data, using: key).combined
            else { throw SealError.noCombined }
            return combined
        default:
            return try ChaChaPoly.seal(data, using: key).combined
        }
    }

    static func open(sealed: Data, key: SymmetricKey,
                     suite: Int) -> String? {
        let plain: Data?
        switch suite {
        case suiteChaCha:
            guard let box = try? ChaChaPoly.SealedBox(
                combined: sealed) else { return nil }
            plain = try? ChaChaPoly.open(box, using: key)
        case suiteAESGCM:
            guard let box = try? AES.GCM.SealedBox(
                combined: sealed) else { return nil }
            plain = try? AES.GCM.open(box, using: key)
        default:
            return nil
        }
        guard let plain = plain else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// Fragment frames in the suite layout:
    /// [sync] [suite] [index] [total−1] [payload] [checksum] —
    /// an even nibble count, which also keeps them distinct
    /// from legacy odd-count frames and from v1 streams.
    /// The total rides as total−1: a nibble tops at fifteen,
    /// and sixteen fragments are lawful (the full 192-byte
    /// budget) — writing the raw total indexed one past the
    /// alphabet's end and trapped on exactly the longest
    /// lawful messages (fix368; the receiver adds the one
    /// back).
    static func fragmentFrames(sealed: Data, suite: Int) -> [[Int]] {
        var chunks: [[UInt8]] = []
        var start = 0
        while start < sealed.count {
            let end = min(start + fragmentPayloadBytes, sealed.count)
            chunks.append(Array(sealed[start..<end]))
            start = end
        }
        if chunks.isEmpty { chunks = [[]] }
        let total = chunks.count
        return chunks.enumerated().map { index, chunk in
            var nibbles = [suite, index, total - 1]
            for byte in chunk {
                nibbles.append(Int(byte >> 4))
                nibbles.append(Int(byte & 0x0F))
            }
            let check = nibbles.reduce(0, +) % 16
            return [syncPort]
                + nibbles.map { alphabet[$0] }
                + [alphabet[check]]
        }
    }

    /// The first two bytes of the sealed box's SHA-256, as four
    /// nibbles — enough for the sender to match an ACK to the
    /// message it names, far too little to learn anything from.
    static func hashNibbles(of sealed: Data) -> [Int] {
        let digest = SHA256.hash(data: sealed)
        let bytes = Array(digest.prefix(2))
        return [Int(bytes[0] >> 4), Int(bytes[0] & 0x0F),
                Int(bytes[1] >> 4), Int(bytes[1] & 0x0F)]
    }

    static func ackFrame(hash: [Int]) -> [Int] {
        [syncPort] + [15, 15].map { alphabet[$0] }
            + hash.map { alphabet[$0] }
    }

    static func nackFrame(missing: [Int]) -> [Int] {
        [syncPort] + [14, 14].map { alphabet[$0] }
            + missing.sorted().map { alphabet[$0] }
    }

    static func nibble(of port: Int) -> Int? {
        alphabet.firstIndex(of: port)
    }

    /// Seal the message and spell the sealed box as a knock
    /// sequence: [sync] + one knock per nibble.
    static func encode(_ plaintext: String,
                       key: SymmetricKey) throws -> [Int] {
        let data = Data(plaintext.utf8)
        let sealed = try ChaChaPoly.seal(data, using: key)
        var ports = [syncPort]
        for byte in sealed.combined {
            ports.append(alphabet[Int(byte >> 4)])
            ports.append(alphabet[Int(byte & 0x0F)])
        }
        return ports
    }

    /// Reassemble nibbles and open the box. Any failure — wrong
    /// length, wrong key, one knock lost or doubled — returns nil.
    static func decode(nibbles: [Int], key: SymmetricKey) -> String? {
        guard nibbles.count >= 56, nibbles.count % 2 == 0 else {
            return nil
        }
        var bytes = Data()
        bytes.reserveCapacity(nibbles.count / 2)
        var index = 0
        while index < nibbles.count {
            bytes.append(UInt8(nibbles[index] << 4 | nibbles[index + 1]))
            index += 2
        }
        guard let box = try? ChaChaPoly.SealedBox(combined: bytes),
              let plain = try? ChaChaPoly.open(box, using: key) else {
            return nil
        }
        return String(data: plain, encoding: .utf8)
    }

    /// Rough airtime of a sequence — the channel is a trickle by
    /// design; the composer shows this before sending.
    static func etaSeconds(knocks: Int) -> Int {
        Int((Double(knocks) * 0.55).rounded())
    }
}

/// The pairing key, in the Keychain — never in UserDefaults,
/// never in a log.
enum KnockKeyStore {
    private static let service = "nightjar.knocktalk"
    private static let account = "pairing-key"

    static var keyHex: String? {
        get {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item)
                    == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            if let newValue = newValue {
                let data = Data(newValue.utf8)
                let status = SecItemUpdate(
                    baseQuery as CFDictionary,
                    [kSecValueData as String: data] as CFDictionary)
                if status == errSecItemNotFound {
                    var query = baseQuery
                    query[kSecValueData as String] = data
                    query[kSecAttrAccessible as String] =
                        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                    let addStatus = SecItemAdd(
                        query as CFDictionary, nil)
                    if addStatus != errSecSuccess {
                        Journal.log("knocktalk", "keychain",
                            "The pairing key could not be "
                            + "saved (OSStatus "
                            + "\(addStatus)) — it will not "
                            + "survive a relaunch.")
                    }
                } else if status != errSecSuccess {
                    Journal.log("knocktalk", "keychain",
                        "The pairing key could not be "
                        + "updated (OSStatus \(status)) — "
                        + "the change may not survive a "
                        + "relaunch.")
                }
            } else {
                SecItemDelete(baseQuery as CFDictionary)
            }
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var key: SymmetricKey? {
        guard let hex = keyHex,
              let data = try? PayloadKit.decodeHex(hex),
              data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// A fresh 256-bit key, as the hex string two devices share.
    static func generate() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes {
            Data($0).map { String(format: "%02x", $0) }.joined()
        }
    }

    /// A display-safe fingerprint of a key (never the key itself).
    static func fingerprint(ofHex hex: String) -> String {
        let digest = SHA256.hash(data: Data(hex.utf8))
        return digest.prefix(4)
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct KnockMessage: Identifiable, Codable {
    var id: String
    var when: Date
    var source: String
    var text: String
}

struct KnockPattern: Identifiable {
    let id = UUID()
    var when: Date
    var source: String
    var knocks: Int
    var note: String
}

/// The sequence engine. Fed every raw TCP knock (before the
/// display log folds repeats — folding would eat doubled letters),
/// it runs three readers at once: the Knocktalk decoder, the
/// structure grader (scan vs. speech), and the vault combination.
final class KnockEngine {
    enum Output {
        /// A decoded message. `ackHash` is set for v2-framed
        /// messages (the chat layer ACKs them); nil for legacy
        /// v1 frames, whose senders never listen for one.
        case message(KnockMessage, ackHash: [Int]?)
        case pattern(KnockPattern)
        case vaultUnlock(source: String)
        /// The peer confirms a message ours named by hash.
        case ack(source: String, hash: [Int])
        /// The peer lists fragments of our message it is missing.
        case nack(source: String, missing: [Int])
        /// Our reassembly of the peer's message has holes —
        /// the chat layer should knock a NACK back.
        case nackNeeded(source: String, missing: [Int])
    }

    var onOutput: ((Output) -> Void)?
    /// Suspends vault matching while the vault stands open.
    var vaultCoolingUntil = Date.distantPast

    private struct Session {
        var nibbles: [Int] = []
        var lastKnock = Date.distantPast
    }
    private var sessions: [String: Session] = [:]
    private var finalizeWork: [String: DispatchWorkItem] = [:]
    private var alphabetTrail: [String: [Date]] = [:]
    private var gradedAt: [String: Date] = [:]
    private var vaultTrail: [String: [(String, Date)]] = [:]

    // Cadence Seal state: every knock's time, per source, and
    // how far into that train the last completed message ran —
    // so a finished message's rhythm can be cut out and graded.
    private var knockTimes: [String: [Date]] = [:]
    private var cadenceMarks: [String: Int] = [:]
    private(set) var lastCadence: [String: CadenceSample] = [:]

    private func recordKnockTime(_ source: String, _ when: Date) {
        var times = knockTimes[source] ?? []
        times.append(when)
        if times.count > 2000 {
            let drop = times.count - 2000
            times.removeFirst(drop)
            cadenceMarks[source] = max(
                0, (cadenceMarks[source] ?? 0) - drop)
        }
        knockTimes[source] = times
    }

    /// Cut the just-finished message's knock train out of the
    /// record and grade its rhythm. Called immediately before a
    /// message is emitted, so the reader of the output can grade
    /// the same message's cadence from `lastCadence`.
    private func sealCadence(source: String) {
        let times = knockTimes[source] ?? []
        let start = min(cadenceMarks[source] ?? 0, times.count)
        let segment = Array(times[start...])
        cadenceMarks[source] = times.count
        if let sample = CadenceMath.sample(times: segment) {
            lastCadence[source] = sample
        }
    }

    /// The vault combination: three protocol digits spoken in
    /// order, from one source, inside twenty seconds. The DEFAULT
    /// is printed in the app and in this source — it is a
    /// placeholder, not a secret. The operator chooses their own
    /// (Emcon.reloadVaultCombination reads the setting); a
    /// combination everyone can read opens for everyone.
    var vaultCombination = ["ssh", "tls", "mqtt"]
    static let vaultWindow: TimeInterval = 20

    func note(source: String, port: Int, proto: String,
              verdict: String, when: Date = Date()) {
        guard proto == "TCP" else { return }
        noteVault(source: source, verdict: verdict, when: when)
        recordKnockTime(source, when)
        if port == Knocktalk.syncPort {
            // A sync delimits frames: flush whatever the previous
            // frame accumulated before opening the next one. The
            // sender's inter-frame pause is far shorter than the
            // close gap, so without the flush, consecutive
            // fragments would smear into one session.
            if let old = sessions[source], !old.nibbles.isEmpty {
                finalizeWork[source]?.cancel()
                finalize(source: source)
            }
            sessions[source] = Session(lastKnock: when)
            scheduleFinalize(source: source)
            return
        }
        guard let nibble = Knocktalk.nibble(of: port) else { return }
        recordKnockTime(source, when)
        if sessions[source] != nil {
            sessions[source]?.nibbles.append(nibble)
            sessions[source]?.lastKnock = when
            scheduleFinalize(source: source)
        } else {
            gradeStructure(source: source, when: when)
        }
    }

    /// This source's session gap, taken from its
    /// own rhythm: four times the median interval
    /// between its recent knocks, clamped to
    /// [1.2 s, 8 s] — the flat constant until
    /// enough knocks have landed to know better.
    /// The engine already recorded every knock's
    /// time for the Cadence Seal; until now the
    /// sessionizer never looked at them, so a fast
    /// sender's message waited out a flat 3.5 s
    /// after its last knock, and a slow sender —
    /// congested relay, deliberate pacing — could
    /// be chopped mid-frame into a NACK repair.
    private func finalizeGap(for source: String)
        -> TimeInterval {
        let times = knockTimes[source] ?? []
        let deltas = zip(times, times.dropFirst())
            .map { $0.1.timeIntervalSince($0.0) }
            .filter { $0 > 0.05 }
        guard deltas.count >= 4 else { return Knocktalk.gap }
        let recent = Array(deltas.suffix(40)).sorted()
        let median = recent[recent.count / 2]
        return min(8, max(1.2, 4 * median))
    }

    private func scheduleFinalize(source: String) {
        finalizeWork[source]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finalize(source: source)
        }
        finalizeWork[source] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + finalizeGap(for: source),
            execute: work)
    }

    private struct Partial {
        var total: Int
        var suite: Int = Knocktalk.suiteChaCha
        var fragments: [Int: Data] = [:]
    }
    private var partials: [String: Partial] = [:]
    private var partialWork: [String: DispatchWorkItem] = [:]

    private func finalize(source: String) {
        guard let session = sessions.removeValue(forKey: source),
              !session.nibbles.isEmpty else { return }
        finalizeWork[source] = nil
        let n = session.nibbles
        // ACK frame: [15 15] + four hash nibbles.
        if n.count == 6, n[0] == 15, n[1] == 15 {
            onOutput?(.ack(source: source, hash: Array(n[2..<6])))
            return
        }
        // Suite fragment frame: even length, suite nibble first.
        if n.count >= 6, n.count <= 40, n.count % 2 == 0,
           handleFragment(source: source, nibbles: n,
                          suiteLayout: true) {
            return
        }
        // Legacy fragment frame: odd length, checksum-tailed.
        if n.count >= 5, n.count % 2 == 1,
           handleFragment(source: source, nibbles: n,
                          suiteLayout: false) {
            return
        }
        // NACK frame: [14 14] + the missing indices.
        if n.count >= 3, n.count <= 10, n[0] == 14, n[1] == 14 {
            onOutput?(.nack(source: source, missing: Array(n[2...])))
            return
        }
        // v1 whole-message frame.
        if let key = KnockKeyStore.key,
           let text = Knocktalk.decode(nibbles: n, key: key) {
            sealCadence(source: source)
            onOutput?(.message(KnockMessage(
                id: UUID().uuidString, when: Date(), source: source,
                text: text), ackHash: nil))
        } else {
            onOutput?(.pattern(KnockPattern(
                when: Date(), source: source,
                knocks: n.count + 1,
                note: "Knocktalk-framed but sealed — wrong key, "
                    + "no key, or knocks lost in transit")))
        }
    }

    /// Parse one fragment frame. True means the stream was
    /// fragment-shaped and has been consumed (stored, completed,
    /// or dropped as corrupt); false means not a fragment.
    private func handleFragment(source: String, nibbles n: [Int],
                                suiteLayout: Bool) -> Bool {
        let suite = suiteLayout ? n[0] : Knocktalk.suiteChaCha
        let index = suiteLayout ? n[1] : n[0]
        // The suite layout carries total−1 (see
        // fragmentFrames); the legacy layout
        // predates the encoding and reads raw.
        let total = suiteLayout ? n[2] + 1 : n[1]
        guard (1...Knocktalk.maxFragments).contains(total),
              index < total else { return false }
        let header = suiteLayout ? 3 : 2
        let payload = Array(n[header..<(n.count - 1)])
        guard payload.count >= 2, payload.count % 2 == 0
        else { return false }
        guard n.dropLast().reduce(0, +) % 16 == n.last else {
            // Fragment-shaped but mangled: register the hole so
            // the NACK asks for this index again.
            registerPartial(source: source, total: total, suite: suite,
                            index: nil, data: nil)
            return true
        }
        var bytes = Data()
        var i = 0
        while i < payload.count {
            bytes.append(UInt8(payload[i] << 4 | payload[i + 1]))
            i += 2
        }
        registerPartial(source: source, total: total, suite: suite,
                        index: index, data: bytes)
        return true
    }

    private func registerPartial(source: String, total: Int,
                                 suite: Int, index: Int?,
                                 data: Data?) {
        var partial = partials[source]
        if partial == nil || partial!.total != total {
            partial = Partial(total: total)
        }
        // A fresh fragment 0 that disagrees with the stored one
        // is a NEW message superseding the stale partial.
        if index == 0, let data = data,
           let existing = partial!.fragments[0], existing != data {
            partial = Partial(total: total)
        }
        if index == 0 || partial!.fragments[0] == nil {
            partial!.suite = suite
        }
        if let index = index, let data = data {
            partial!.fragments[index] = data
        }
        partials[source] = partial
        guard partial!.fragments.count == total else {
            schedulePartialCheck(source: source)
            return
        }
        partials[source] = nil
        partialWork[source]?.cancel()
        let sealed = (0..<total)
            .map { partial!.fragments[$0]! }
            .reduce(Data()) { $0 + $1 }
        let finalSuite = partial!.suite
        if !Knocktalk.suiteNames.indices.contains(finalSuite) {
            onOutput?(.pattern(KnockPattern(
                when: Date(), source: source, knocks: total,
                note: "a complete message in suite \(finalSuite), "
                    + "which this build does not speak")))
        } else if let key = KnockKeyStore.key,
           let text = Knocktalk.open(sealed: sealed, key: key,
                                     suite: finalSuite) {
            sealCadence(source: source)
            onOutput?(.message(KnockMessage(
                id: UUID().uuidString, when: Date(), source: source,
                text: text),
                ackHash: Knocktalk.hashNibbles(of: sealed)))
        } else {
            onOutput?(.pattern(KnockPattern(
                when: Date(), source: source, knocks: total,
                note: "a complete Knocktalk message that would "
                    + "not open — wrong key")))
        }
    }

    /// When a partial goes quiet with holes in it, ask — once —
    /// for exactly the missing fragments.
    private func schedulePartialCheck(source: String) {
        partialWork[source]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  let partial = self.partials[source] else { return }
            self.partials[source] = nil
            let missing = (0..<partial.total)
                .filter { partial.fragments[$0] == nil }
            if !missing.isEmpty {
                self.onOutput?(.nackNeeded(source: source,
                                           missing: missing))
            }
        }
        partialWork[source] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + finalizeGap(for: source) + 2.0,
            execute: work)
    }

    /// Six alphabet knocks inside ten seconds, unframed: not a
    /// scan's shape. Scanners sweep; speakers spell.
    private func gradeStructure(source: String, when: Date) {
        var trail = alphabetTrail[source] ?? []
        trail.append(when)
        trail.removeAll { when.timeIntervalSince($0) > 10 }
        alphabetTrail[source] = trail
        guard trail.count >= 6 else { return }
        if let last = gradedAt[source],
           when.timeIntervalSince(last) < 30 { return }
        gradedAt[source] = when
        alphabetTrail[source] = []
        onOutput?(.pattern(KnockPattern(
            when: when, source: source, knocks: trail.count,
            note: "structured knock pattern — a scan sweeps; "
                + "this is spelling")))
    }

    private func noteVault(source: String, verdict: String,
                           when: Date) {
        // This device knocking itself never opens the vault —
        // the operator's own Recon demos speak protocols in
        // registry order all day. The combination is for OTHER
        // devices he controls: a second phone, his Mac.
        guard when > vaultCoolingUntil,
              !source.contains("(this device)"),
              source != "127.0.0.1",
              let category = Self.category(of: verdict) else { return }
        var trail = vaultTrail[source] ?? []
        trail.append((category, when))
        trail.removeAll {
            when.timeIntervalSince($0.1) > Self.vaultWindow
        }
        if Array(trail.suffix(3).map { $0.0 }) == vaultCombination {
            vaultTrail[source] = []
            vaultCoolingUntil = when.addingTimeInterval(90)
            onOutput?(.vaultUnlock(source: source))
        } else {
            vaultTrail[source] = trail
        }
    }

    /// Which vault digit a verdict speaks, if any. A digit counts
    /// only when the knock's bytes were RECOGNIZED as that
    /// protocol — by signature, or by the generic fingerprints.
    static func category(of verdict: String) -> String? {
        if verdict.hasPrefix("SSH client banner") { return "ssh" }
        if verdict.hasPrefix("TLS ClientHello") { return "tls" }
        if verdict.hasPrefix("HTTP request") { return "http" }
        if verdict.hasPrefix("nightjar probe:") {
            let rest = verdict.dropFirst("nightjar probe: ".count)
            let name = rest.split(separator: "(").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if name.contains("ssh") { return "ssh" }
            if name.contains("tls") { return "tls" }
            if name == "mqtt-connect" { return "mqtt" }
            if name == "http-get" || name == "https-get" {
                return "http"
            }
            if name == "smtp-ehlo" { return "smtp" }
            if name == "ftp-user" { return "ftp" }
        }
        return nil
    }
}

/// The composer end: knocks sequences at a target, one connect
/// at a time, in order — a connect, a breath, a close, and
/// nothing else. No bytes are ever sent. Frames queue: a
/// message's fragments go out back to back with a short pause
/// between frames, and `onQueueEmpty` reports the drain.
final class KnockSender: ObservableObject {
    @Published private(set) var sending = false
    @Published private(set) var sent = 0
    @Published private(set) var total = 0
    var onQueueEmpty: (() -> Void)?

    private var frames: [[Int]] = []
    private var frameIndex = 0
    private var knockIndex = 0
    private var host = ""
    private var cancelled = false
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "nightjar.knocktalk.send")

    /// Knock one raw sequence (v1-style single frame).
    func send(host: String, ports: [Int]) {
        sendFrames(host: host, frames: [ports])
    }

    func sendFrames(host: String, frames: [[Int]]) {
        let clean = frames.filter { !$0.isEmpty }
        guard !sending, !clean.isEmpty,
              !host.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        self.host = host.trimmingCharacters(in: .whitespaces)
        self.frames = clean
        frameIndex = 0
        knockIndex = 0
        cancelled = false
        let knocks = clean.reduce(0) { $0 + $1.count }
        DispatchQueue.main.async {
            self.total = knocks
            self.sent = 0
            self.sending = true
        }
        queue.async { self.step() }
    }

    var busy: Bool { sending }

    func cancel() {
        cancelled = true
        connection?.cancel()
        DispatchQueue.main.async { self.sending = false }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.sending = false
            self.onQueueEmpty?()
        }
    }

    private func step() {
        guard !cancelled else { return }
        if knockIndex >= frames[frameIndex].count {
            // Frame drained: pause, then the next frame — or out.
            if frameIndex + 1 < frames.count {
                frameIndex += 1
                knockIndex = 0
                queue.asyncAfter(deadline: .now() + 0.8) {
                    self.step()
                }
            } else {
                finish()
            }
            return
        }
        let port = frames[frameIndex][knockIndex]
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(port)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        self.connection = connection
        var advanced = false
        let advance = { [weak self] in
            guard let self = self, !advanced else { return }
            advanced = true
            connection.cancel()
            self.knockIndex += 1
            DispatchQueue.main.async { self.sent += 1 }
            self.queue.asyncAfter(deadline: .now() + 0.30) {
                self.step()
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard self != nil else { return }
            switch state {
            case .ready:
                self?.queue.asyncAfter(deadline: .now() + 0.12) {
                    advance()
                }
            case .failed:
                advance()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1.5) { advance() }
    }
}
