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
    static let maxCharacters = 40

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
                    SecItemAdd(query as CFDictionary, nil)
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
        case message(KnockMessage)
        case pattern(KnockPattern)
        case vaultUnlock(source: String)
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
        if port == Knocktalk.syncPort {
            sessions[source] = Session(lastKnock: when)
            scheduleFinalize(source: source)
            return
        }
        guard let nibble = Knocktalk.nibble(of: port) else { return }
        if sessions[source] != nil {
            sessions[source]?.nibbles.append(nibble)
            sessions[source]?.lastKnock = when
            scheduleFinalize(source: source)
        } else {
            gradeStructure(source: source, when: when)
        }
    }

    private func scheduleFinalize(source: String) {
        finalizeWork[source]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finalize(source: source)
        }
        finalizeWork[source] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Knocktalk.gap, execute: work)
    }

    private func finalize(source: String) {
        guard let session = sessions.removeValue(forKey: source),
              !session.nibbles.isEmpty else { return }
        finalizeWork[source] = nil
        if let key = KnockKeyStore.key,
           let text = Knocktalk.decode(nibbles: session.nibbles,
                                        key: key) {
            onOutput?(.message(KnockMessage(
                id: UUID().uuidString, when: Date(), source: source,
                text: text)))
        } else {
            onOutput?(.pattern(KnockPattern(
                when: Date(), source: source,
                knocks: session.nibbles.count + 1,
                note: "Knocktalk-framed but sealed — wrong key, "
                    + "no key, or knocks lost in transit")))
        }
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
        if verdict.hasPrefix("nightjar-hack probe:") {
            let rest = verdict.dropFirst("nightjar-hack probe: ".count)
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

/// The composer end: knocks a sequence at a target, one connect
/// at a time, in order — a connect, a breath, a close, and
/// nothing else. No bytes are ever sent.
final class KnockSender: ObservableObject {
    @Published private(set) var sending = false
    @Published private(set) var sent = 0
    @Published private(set) var total = 0

    private var ports: [Int] = []
    private var host = ""
    private var cancelled = false
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "nightjar.knocktalk.send")

    func send(host: String, ports: [Int]) {
        guard !sending, !ports.isEmpty,
              !host.trimmingCharacters(in: .whitespaces).isEmpty
        else { return }
        self.host = host.trimmingCharacters(in: .whitespaces)
        self.ports = ports
        cancelled = false
        DispatchQueue.main.async {
            self.total = ports.count
            self.sent = 0
            self.sending = true
        }
        queue.async { self.step() }
    }

    func cancel() {
        cancelled = true
        connection?.cancel()
        DispatchQueue.main.async { self.sending = false }
    }

    private func step() {
        guard !cancelled else { return }
        let index = DispatchQueue.main.sync { self.sent }
        guard index < ports.count else {
            DispatchQueue.main.async { self.sending = false }
            return
        }
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(ports[index])) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        self.connection = connection
        var advanced = false
        let advance = { [weak self] in
            guard let self = self, !advanced else { return }
            advanced = true
            connection.cancel()
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
