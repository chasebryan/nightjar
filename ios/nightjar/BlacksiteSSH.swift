import Foundation
import Network
import CryptoKit

/// SSH — the house client, built the house way: the wire
/// protocol by hand over NWConnection, every primitive from
/// CryptoKit. curve25519-sha256 key exchange (both its names),
/// ssh-ed25519 and ecdsa-sha2-nistp256 host keys, AES-GCM on
/// the wire (RFC 5647), password / keyboard-interactive /
/// ed25519-identity authentication, exec channels and an
/// interactive shell. The design was proven end-to-end against
/// an independent implementation (paramiko) before a line of
/// this was written; the XCTest pins carry the same vectors.
///
/// Doctrine (netadmin): credentials come from the operator —
/// a kept word from the Keychain, or one asked for in secret
/// at the moment of use. Nothing is ever guessed, nothing is
/// ever logged. Host keys are trust-on-first-use: an unknown
/// key is the operator's decision, a CHANGED key is a refusal.

enum SSHFailure: Error, CustomStringConvertible {
    case connect(String)
    case timeout(String)
    case closed
    case noMutual(String)
    case badHostSignature
    case hostKeyChanged(fingerprint: String)
    case hostKeyRefused(fingerprint: String)
    case authFailed(String)
    case channelRefused(String)
    case protocolFault(String)

    var description: String {
        switch self {
        case .connect(let why):
            return String(format: L("the connection failed: %@"), String(describing: why))
        case .timeout(let where_):
            return String(format: L("the host stopped answering (%@)"), String(describing: where_))
        case .closed:
            return L("the host closed the connection")
        case .noMutual(let what):
            return String(format: L("no shared %@ — this client speaks curve25519, AES-GCM, ed25519 / ecdsa host keys, nothing older"), String(describing: what))
        case .badHostSignature:
            return L("the host key signature does not verify — this is not the host it claims to be")
        case .hostKeyChanged(let fp):
            return String(format: L("the host key CHANGED (now %@) — refused. If the gear was replaced on purpose, forget the old key with 'sshhosts forget' and connect again"), String(describing: fp))
        case .hostKeyRefused(let fp):
            return String(format: L("unknown host key %@ — not trusted, not used"), String(describing: fp))
        case .authFailed(let why):
            return String(format: L("authentication failed: %@"), String(describing: why))
        case .channelRefused(let why):
            return String(format: L("the host refused the channel: %@"), String(describing: why))
        case .protocolFault(let why):
            return String(format: L("the host spoke out of turn: %@"), String(describing: why))
        }
    }
}

// MARK: - Wire plumbing

struct SSHReader {
    let data: Data
    var index = 0

    mutating func byte() -> UInt8? {
        guard index < data.count else { return nil }
        let value = data[data.startIndex + index]
        index += 1
        return value
    }

    mutating func uint32() -> Int? {
        guard index + 4 <= data.count else { return nil }
        var value = 0
        for k in 0..<4 {
            value = value << 8
            value |= Int(data[data.startIndex + index + k])
        }
        index += 4
        return value
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, index + count <= data.count
        else { return nil }
        let start = data.startIndex + index
        let out = Data(data[start..<start + count])
        index += count
        return out
    }

    mutating func string() -> Data? {
        guard let length = uint32() else { return nil }
        return bytes(length)
    }

    mutating func text() -> String? {
        guard let raw = string() else { return nil }
        return String(data: raw, encoding: .utf8)
    }
}

enum SSHWire {
    static func uint32(_ value: Int) -> Data {
        var out = Data()
        out.append(UInt8((value >> 24) & 0xff))
        out.append(UInt8((value >> 16) & 0xff))
        out.append(UInt8((value >> 8) & 0xff))
        out.append(UInt8(value & 0xff))
        return out
    }

    static func string(_ data: Data) -> Data {
        uint32(data.count) + data
    }

    static func string(_ text: String) -> Data {
        string(Data(text.utf8))
    }

    static func nameList(_ items: [String]) -> Data {
        string(items.joined(separator: ","))
    }

    /// Parse a name list. Callers hand over
    /// either the framed field (as nameList
    /// writes it) or the bare payload (as
    /// SSHReader.string returns it); a
    /// leading length that accounts for
    /// exactly the remaining bytes marks
    /// the framed form and comes off. (The
    /// Gauntlet's round-trip caught the two
    /// forms being conflated, 2026-10-22.)
    static func parseNameList(_ data: Data) -> [String] {
        var body = data
        if body.count > 4 {
            let framed = (Int(body[body.startIndex]) << 24)
                | (Int(body[body.startIndex + 1]) << 16)
                | (Int(body[body.startIndex + 2]) << 8)
                | Int(body[body.startIndex + 3])
            if framed == body.count - 4 {
                body = Data(body.dropFirst(4))
            }
        }
        guard let text = String(data: body,
                                encoding: .utf8),
              !text.isEmpty
        else { return [] }
        return text.split(separator: ",")
            .map { String($0) }
    }

    /// mpint: a length-prefixed big-endian integer — a zero
    /// byte rides in front when the top bit would read as a
    /// sign (RFC 4251 §5). Redundant leading zeros come
    /// off, but only while the byte behind them keeps the
    /// value positive.
    static func mpint(_ raw: Data) -> Data {
        var body = raw
        while body.count > 1, body.first == 0 {
            let second = body[body.startIndex + 1]
            if second & 0x80 != 0 { break }
            body = Data(body.dropFirst())
        }
        if let first = body.first, first & 0x80 != 0 {
            body = Data([0]) + body
        }
        return string(body)
    }

    static func readUint32(_ data: Data) -> Int {
        var value = 0
        for k in 0..<min(4, data.count) {
            value = value << 8
            value |= Int(data[data.startIndex + k])
        }
        return value
    }
}

// MARK: - The client

final class SSHClient {

    let host: String
    let port: Int
    let user: String
    var timeout: TimeInterval = 20

    /// The host key blob already on file for this host.
    var knownKey: Data?
    /// Asked when no key is on file: the fingerprint and the
    /// algorithm. True trusts (the caller files it after a
    /// successful session). The default refuses.
    var trustAsk: (_ fingerprint: String,
                   _ algorithm: String) -> Bool = { _, _ in
        false
    }
    /// Asked for a secret at the moment of need — the account
    /// word, or a keyboard-interactive prompt's answer.
    var secretAsk: (_ prompt: String) -> String? = { _ in
        nil
    }
    /// A kept word for this host+user, tried before asking.
    var keptWord: String?
    /// The house ed25519 identity, when one exists.
    var identity: Curve25519.Signing.PrivateKey?
    /// Test seam: a fixed ephemeral key for vector replay.
    var testEphemeral: Curve25519.KeyAgreement.PrivateKey?

    private(set) var fingerprint = ""
    private(set) var hostAlgorithm = ""
    private(set) var negotiatedCipher = ""
    private(set) var hostKeyBlob = Data()

    private var connection: NWConnection?
    private let ioQueue = DispatchQueue(label: "nightjar.ssh")
    private var inbound = Data()
    private var inboundClosed = false
    private let inboundGate = NSCondition()
    private var sendSide: (key: SymmetricKey, fixed: Data,
                           counter: UInt64)?
    private var recvSide: (key: SymmetricKey, fixed: Data,
                           counter: UInt64)?
    private let sendLock = NSLock()
    var sessionID = Data()
    private var word: String?

    init(host: String, port: Int, user: String) {
        self.host = host
        self.port = port
        self.user = user
    }

    // MARK: Transport

    private func openTransport() throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(
                rawValue: UInt16(clamping: port))!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn
        let gate = DispatchSemaphore(value: 0)
        var fault: String?
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                gate.signal()
            case .failed(let error):
                fault = "\(error)"
                gate.signal()
            case .waiting(let error):
                fault = "\(error)"
                gate.signal()
            default:
                break
            }
        }
        conn.start(queue: ioQueue)
        if gate.wait(timeout: .now() + timeout)
            == .timedOut {
            conn.cancel()
            throw SSHFailure.timeout("connecting")
        }
        if let fault {
            conn.cancel()
            throw SSHFailure.connect(fault)
        }
        pump()
    }

    private func pump() {
        connection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.inboundGate.lock()
            if let data, !data.isEmpty {
                self.inbound.append(data)
            }
            if isComplete || error != nil {
                self.inboundClosed = true
            }
            self.inboundGate.broadcast()
            self.inboundGate.unlock()
            if !isComplete, error == nil {
                self.pump()
            }
        }
    }

    private func readExact(_ count: Int) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        inboundGate.lock()
        while inbound.count < count {
            if inboundClosed {
                inboundGate.unlock()
                throw SSHFailure.closed
            }
            if !inboundGate.wait(until: deadline) {
                inboundGate.unlock()
                throw SSHFailure.timeout("reading")
            }
        }
        let out = Data(inbound.prefix(count))
        inbound.removeFirst(count)
        inboundGate.unlock()
        return out
    }

    private func readBannerLine() throws -> String {
        var line = Data()
        while line.count < 8192 {
            let one = try readExact(1)
            line.append(one)
            if one == Data([0x0a]) {
                break
            }
        }
        var text = String(data: line, encoding: .utf8) ?? ""
        while text.hasSuffix("\n") || text.hasSuffix("\r") {
            text.removeLast()
        }
        return text
    }

    private func sendRaw(_ data: Data) throws {
        guard let connection else {
            throw SSHFailure.closed
        }
        let gate = DispatchSemaphore(value: 0)
        var fault: String?
        connection.send(
            content: data,
            completion: .contentProcessed { error in
                if let error {
                    fault = "\(error)"
                }
                gate.signal()
            })
        if gate.wait(timeout: .now() + timeout)
            == .timedOut {
            throw SSHFailure.timeout("writing")
        }
        if let fault {
            throw SSHFailure.connect(fault)
        }
    }

    // MARK: Packets

    private func sendPacket(_ payload: Data) throws {
        sendLock.lock()
        defer { sendLock.unlock() }
        let block = sendSide == nil ? 8 : 16
        var padLength = block - ((payload.count + 5) % block)
        if padLength < 4 { padLength += block }
        let packetLength = payload.count + padLength + 1
        let head = SSHWire.uint32(packetLength)
        var body = Data()
        body.append(UInt8(padLength))
        body.append(payload)
        body.append(CryptoSuite.randomBytes(padLength))
        if let side = sendSide {
            let sealed = try Self.gcmSeal(
                key: side.key, fixed: side.fixed,
                counter: side.counter, body: body,
                head: head)
            sendSide = (side.key, side.fixed,
                        side.counter + 1)
            try sendRaw(head + sealed)
        } else {
            try sendRaw(head + body)
        }
    }

    /// One AES-GCM sealing, SSH-style (RFC 5647): the
    /// length field rides in the clear as the additional
    /// data; the nonce is the fixed four bytes with the
    /// invocation counter — which STARTS at the derived
    /// IV's last eight bytes — behind them. Internal so
    /// the XCTest pins can replay recorded wire bytes.
    static func gcmSeal(key: SymmetricKey, fixed: Data,
                        counter: UInt64, body: Data,
                        head: Data) throws -> Data {
        var nonceData = fixed
        var count = counter.bigEndian
        withUnsafeBytes(of: &count) {
            nonceData.append(contentsOf: $0)
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealed = try AES.GCM.seal(
            body, using: key, nonce: nonce,
            authenticating: head)
        return sealed.ciphertext + sealed.tag
    }

    static func gcmOpen(key: SymmetricKey, fixed: Data,
                        counter: UInt64, head: Data,
                        sealed: Data) throws -> Data {
        var nonceData = fixed
        var count = counter.bigEndian
        withUnsafeBytes(of: &count) {
            nonceData.append(contentsOf: $0)
        }
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let box = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: Data(sealed.prefix(
                sealed.count - 16)),
            tag: Data(sealed.suffix(16)))
        return try AES.GCM.open(
            box, using: key, authenticating: head)
    }

    private func readPacket() throws -> Data {
        let head = try readExact(4)
        let length = SSHWire.readUint32(head)
        guard length >= 1, length <= 1_048_576 else {
            throw SSHFailure.protocolFault(
                "a packet of impossible size")
        }
        if let side = recvSide {
            let sealed = try readExact(length + 16)
            let body = try Self.gcmOpen(
                key: side.key, fixed: side.fixed,
                counter: side.counter, head: head,
                sealed: sealed)
            recvSide = (side.key, side.fixed,
                        side.counter + 1)
            guard let first = body.first else {
                throw SSHFailure.protocolFault(
                    "an empty packet")
            }
            let padLength = Int(first)
            guard body.count - 1 - padLength >= 0 else {
                throw SSHFailure.protocolFault(
                    "padding longer than the packet")
            }
            return Data(body.dropFirst(1)
                .dropLast(padLength))
        }
        let rest = try readExact(length)
        guard let first = rest.first else {
            throw SSHFailure.protocolFault("an empty packet")
        }
        let padLength = Int(first)
        guard rest.count - 1 - padLength >= 0 else {
            throw SSHFailure.protocolFault(
                "padding longer than the packet")
        }
        return Data(rest.dropFirst(1).dropLast(padLength))
    }

    // MARK: Key exchange

    private static let clientVersion = "SSH-2.0-nightjar_1.0"
    private static let kexNames = [
        "curve25519-sha256", "curve25519-sha256@libssh.org",
    ]
    private static let hostKeyNames = [
        "ssh-ed25519", "ecdsa-sha2-nistp256",
    ]
    private static let cipherNames = [
        "aes256-gcm@openssh.com", "aes128-gcm@openssh.com",
    ]

    func buildKexInit() -> Data {
        var payload = Data([20])
        payload.append(CryptoSuite.randomBytes(16))
        payload.append(SSHWire.nameList(
            Self.kexNames
            + ["kex-strict-c-v00@openssh.com"]))
        payload.append(SSHWire.nameList(Self.hostKeyNames))
        payload.append(SSHWire.nameList(Self.cipherNames))
        payload.append(SSHWire.nameList(Self.cipherNames))
        // MACs are negotiated but unused under an AEAD
        // cipher (RFC 5647); offering "none" makes some
        // peers refuse the connection outright.
        payload.append(SSHWire.nameList(["hmac-sha2-256"]))
        payload.append(SSHWire.nameList(["hmac-sha2-256"]))
        payload.append(SSHWire.nameList(["none"]))
        payload.append(SSHWire.nameList(["none"]))
        payload.append(SSHWire.string(Data()))
        payload.append(SSHWire.string(Data()))
        payload.append(0)
        payload.append(SSHWire.uint32(0))
        return payload
    }

    func parseKexInit(_ payload: Data)
        -> (kex: [String], hostKeys: [String],
            ciphersToServer: [String])? {
        var reader = SSHReader(data: payload)
        guard reader.byte() == 20 else { return nil }
        guard reader.bytes(16) != nil else { return nil }
        guard let kex = reader.string(),
              let hostKeys = reader.string(),
              let ciphers = reader.string()
        else { return nil }
        return (SSHWire.parseNameList(kex),
                SSHWire.parseNameList(hostKeys),
                SSHWire.parseNameList(ciphers))
    }

    static func fingerprint(of keyBlob: Data) -> String {
        let digest = SHA256.hash(data: keyBlob)
        var text = Data(digest).base64EncodedString()
        while text.hasSuffix("=") { text.removeLast() }
        return "SHA256:" + text
    }

    func derive(letter: UInt8, count: Int,
                        shared: Data, hash: Data) -> Data {
        var material = Data()
        let seed = SSHWire.mpint(shared) + hash
            + Data([letter]) + sessionID
        material.append(Data(SHA256.hash(data: seed)))
        while material.count < count {
            let next = SSHWire.mpint(shared) + hash + material
            material.append(Data(SHA256.hash(data: next)))
        }
        return Data(material.prefix(count))
    }

    func verifyHostSignature(algorithm: String,
                                     keyBlob: Data,
                                     sigBlob: Data,
                                     hash: Data) throws {
        var keyReader = SSHReader(data: keyBlob)
        var sigReader = SSHReader(data: sigBlob)
        guard let keyAlgo = keyReader.text(),
              let sigAlgo = sigReader.text(),
              let signature = sigReader.string(),
              keyAlgo == algorithm, sigAlgo == algorithm
        else {
            throw SSHFailure.badHostSignature
        }
        if algorithm == "ssh-ed25519" {
            guard let raw = keyReader.string(),
                  let pub = try? Curve25519.Signing
                    .PublicKey(rawRepresentation: raw),
                  pub.isValidSignature(signature, for: hash)
            else {
                throw SSHFailure.badHostSignature
            }
            return
        }
        // ecdsa-sha2-nistp256: key is curve name + the
        // 65-byte point; the signature is two mpints.
        guard let curve = keyReader.text(),
              curve == "nistp256",
              let point = keyReader.string(),
              let pub = try? P256.Signing.PublicKey(
                x963Representation: point)
        else {
            throw SSHFailure.badHostSignature
        }
        var inner = SSHReader(data: signature)
        guard let rBytes = inner.string(),
              let sBytes = inner.string()
        else {
            throw SSHFailure.badHostSignature
        }
        func padded(_ value: Data) -> Data {
            let trimmed = Data(value.suffix(32))
            if trimmed.count >= 32 { return trimmed }
            return Data(repeating: 0,
                        count: 32 - trimmed.count) + trimmed
        }
        let rawSig = padded(rBytes) + padded(sBytes)
        guard let sig = try? P256.Signing.ECDSASignature(
                rawRepresentation: rawSig),
              pub.isValidSignature(sig, for: hash)
        else {
            throw SSHFailure.badHostSignature
        }
    }

    /// Connect, exchange keys, prove the host, authenticate.
    /// The caller disconnects.
    func handshake() throws {
        try openTransport()
        // The server speaks first; tolerate banner chatter.
        var serverVersion = ""
        for _ in 0..<20 {
            let line = try readBannerLine()
            if line.hasPrefix("SSH-") {
                serverVersion = line
                break
            }
        }
        guard !serverVersion.isEmpty else {
            throw SSHFailure.protocolFault(
                "no SSH banner arrived")
        }
        try sendRaw(Data(Self.clientVersion.utf8)
                    + Data("\r\n".utf8))

        let myInit = buildKexInit()
        try sendPacket(myInit)
        let theirInit = try readPacket()
        guard let parsed = parseKexInit(theirInit) else {
            throw SSHFailure.protocolFault(
                "an unreadable key-exchange opening")
        }
        guard Self.kexNames.contains(where: {
            parsed.kex.contains($0)
        }) else {
            throw SSHFailure.noMutual("key exchange")
        }
        guard let chosenHostKey = Self.hostKeyNames.first(
            where: { parsed.hostKeys.contains($0) })
        else {
            throw SSHFailure.noMutual("host key algorithm")
        }
        guard let chosenCipher = Self.cipherNames.first(
            where: { parsed.ciphersToServer.contains($0) })
        else {
            throw SSHFailure.noMutual("cipher")
        }
        negotiatedCipher = chosenCipher
        hostAlgorithm = chosenHostKey
        let keyLength = chosenCipher.hasPrefix("aes256")
            ? 32 : 16

        let ephemeral = testEphemeral
            ?? Curve25519.KeyAgreement.PrivateKey()
        let myPublic = ephemeral.publicKey
            .rawRepresentation
        var initPacket = Data([30])
        initPacket.append(SSHWire.string(myPublic))
        try sendPacket(initPacket)
        let reply = try readPacket()
        var replyReader = SSHReader(data: reply)
        guard replyReader.byte() == 31,
              let keyBlob = replyReader.string(),
              let theirPublic = replyReader.string(),
              let sigBlob = replyReader.string()
        else {
            throw SSHFailure.protocolFault(
                "an unreadable key-exchange reply")
        }
        hostKeyBlob = keyBlob
        guard let peer = try? Curve25519.KeyAgreement
                .PublicKey(rawRepresentation: theirPublic),
              let sharedSecret = try? ephemeral
                .sharedSecretFromKeyAgreement(with: peer)
        else {
            throw SSHFailure.protocolFault(
                "the shared secret would not form")
        }
        let shared = sharedSecret.withUnsafeBytes {
            Data($0)
        }
        var hashInput = Data()
        hashInput.append(SSHWire.string(
            Data(Self.clientVersion.utf8)))
        hashInput.append(SSHWire.string(
            Data(serverVersion.utf8)))
        hashInput.append(SSHWire.string(myInit))
        hashInput.append(SSHWire.string(theirInit))
        hashInput.append(SSHWire.string(keyBlob))
        hashInput.append(SSHWire.string(myPublic))
        hashInput.append(SSHWire.string(theirPublic))
        hashInput.append(SSHWire.mpint(shared))
        let hash = Data(SHA256.hash(data: hashInput))
        sessionID = hash

        try verifyHostSignature(algorithm: chosenHostKey,
                                keyBlob: keyBlob,
                                sigBlob: sigBlob,
                                hash: hash)
        fingerprint = Self.fingerprint(of: keyBlob)
        if let knownKey {
            guard knownKey == keyBlob else {
                throw SSHFailure.hostKeyChanged(
                    fingerprint: fingerprint)
            }
        } else {
            guard trustAsk(fingerprint, chosenHostKey) else {
                throw SSHFailure.hostKeyRefused(
                    fingerprint: fingerprint)
            }
        }

        let ivToServer = derive(letter: 65, count: 12,
                                shared: shared, hash: hash)
        let ivToClient = derive(letter: 66, count: 12,
                                shared: shared, hash: hash)
        let keyToServer = derive(letter: 67,
                                 count: keyLength,
                                 shared: shared, hash: hash)
        let keyToClient = derive(letter: 68,
                                 count: keyLength,
                                 shared: shared, hash: hash)
        try sendPacket(Data([21]))
        let newKeys = try readPacket()
        guard newKeys.first == 21 else {
            throw SSHFailure.protocolFault(
                "the host would not take the new keys")
        }
        sendSide = (SymmetricKey(data: keyToServer),
                    Data(ivToServer.prefix(4)),
                    Self.counterStart(ivToServer))
        recvSide = (SymmetricKey(data: keyToClient),
                    Data(ivToClient.prefix(4)),
                    Self.counterStart(ivToClient))
        try authenticate()
    }

    private static func counterStart(_ iv: Data) -> UInt64 {
        var value: UInt64 = 0
        for byte in iv.suffix(8) {
            value = value << 8 | UInt64(byte)
        }
        return value
    }

    // MARK: Authentication

    private func userauthPacket(method: String) -> Data {
        var packet = Data([50])
        packet.append(SSHWire.string(user))
        packet.append(SSHWire.string("ssh-connection"))
        packet.append(SSHWire.string(method))
        return packet
    }

    private func theWord() -> String? {
        if let word { return word }
        word = keptWord ?? secretAsk(
            "the SSH word for " + user + "@" + host)
        return word
    }

    private func authenticate() throws {
        var service = Data([5])
        service.append(SSHWire.string("ssh-userauth"))
        try sendPacket(service)
        let accept = try readPacket()
        guard accept.first == 6 else {
            throw SSHFailure.protocolFault(
                "the userauth service would not open")
        }
        // "none" — mostly to learn the offered methods.
        try sendPacket(userauthPacket(method: "none"))
        var reply = try readPacket()
        if reply.first == 52 { return }
        guard reply.first == 51 else {
            throw SSHFailure.protocolFault(
                "an unreadable authentication answer")
        }
        var methods: [String] = []
        var methodReader = SSHReader(data: reply)
        _ = methodReader.byte()
        if let list = methodReader.string() {
            methods = SSHWire.parseNameList(list)
        }
        var failures: [String] = []

        if let identity,
           methods.contains("publickey") {
            if try tryPublicKey(identity) { return }
            failures.append("the house identity key")
        }
        if methods.contains("password"),
           let word = theWord() {
            var packet = userauthPacket(method: "password")
            packet.append(0)
            packet.append(SSHWire.string(word))
            try sendPacket(packet)
            reply = try readPacket()
            if reply.first == 52 { return }
            failures.append("the word")
        }
        if methods.contains("keyboard-interactive") {
            if try tryKeyboardInteractive() { return }
            failures.append("keyboard-interactive")
        }
        let tried = failures.isEmpty
            ? "nothing the host offers"
            : failures.joined(separator: ", ")
        throw SSHFailure.authFailed(
            "the host would not take " + tried
            + " (it offers: "
            + methods.joined(separator: ", ") + ")")
    }

    private func tryPublicKey(
        _ identity: Curve25519.Signing.PrivateKey
    ) throws -> Bool {
        let keyBlob = SSHWire.string("ssh-ed25519")
            + SSHWire.string(identity.publicKey
                .rawRepresentation)
        var query = userauthPacket(method: "publickey")
        query.append(0)
        query.append(SSHWire.string("ssh-ed25519"))
        query.append(SSHWire.string(keyBlob))
        try sendPacket(query)
        var reply = try readPacket()
        if reply.first == 52 { return true }
        guard reply.first == 60 else { return false }
        // Sign: session id, the request, the claim.
        var blob = SSHWire.string(sessionID)
        blob.append(50)
        blob.append(SSHWire.string(user))
        blob.append(SSHWire.string("ssh-connection"))
        blob.append(SSHWire.string("publickey"))
        blob.append(1)
        blob.append(SSHWire.string("ssh-ed25519"))
        blob.append(SSHWire.string(keyBlob))
        guard let signature = try? identity.signature(
            for: blob)
        else { return false }
        let sigBlob = SSHWire.string("ssh-ed25519")
            + SSHWire.string(signature)
        var full = userauthPacket(method: "publickey")
        full.append(1)
        full.append(SSHWire.string("ssh-ed25519"))
        full.append(SSHWire.string(keyBlob))
        full.append(SSHWire.string(sigBlob))
        try sendPacket(full)
        reply = try readPacket()
        return reply.first == 52
    }

    private func tryKeyboardInteractive() throws -> Bool {
        var packet = userauthPacket(
            method: "keyboard-interactive")
        packet.append(SSHWire.string(Data()))
        packet.append(SSHWire.string(Data()))
        try sendPacket(packet)
        var rounds = 0
        while rounds < 4 {
            rounds += 1
            let reply = try readPacket()
            if reply.first == 52 { return true }
            guard reply.first == 60 else { return false }
            var reader = SSHReader(data: reply)
            _ = reader.byte()
            _ = reader.string()   // name
            _ = reader.string()   // instruction
            _ = reader.string()   // language
            guard let count = reader.uint32(),
                  count <= 8
            else { return false }
            var answers: [String] = []
            for _ in 0..<count {
                guard let prompt = reader.text(),
                      let echo = reader.byte()
                else { return false }
                if echo == 0 {
                    guard let word = theWord() else {
                        return false
                    }
                    answers.append(word)
                } else {
                    let answer = secretAsk(
                        prompt.isEmpty
                        ? "the host asks a question"
                        : prompt)
                    answers.append(answer ?? "")
                }
            }
            var response = Data([61])
            response.append(SSHWire.uint32(answers.count))
            for answer in answers {
                response.append(SSHWire.string(answer))
            }
            try sendPacket(response)
        }
        return false
    }

    func disconnect() {
        if connection != nil {
            var packet = Data([1])
            packet.append(SSHWire.uint32(11))
            packet.append(SSHWire.string(
                "leaving by the front door"))
            packet.append(SSHWire.string(Data()))
            try? sendPacket(packet)
        }
        connection?.cancel()
        connection = nil
    }

    // MARK: Channels

    private var serverChannel = 0
    private var windowLeft = 0
    private var channelClosed = false

    private func openChannel() throws {
        var packet = Data([90])
        packet.append(SSHWire.string("session"))
        packet.append(SSHWire.uint32(0))
        packet.append(SSHWire.uint32(1_048_576))
        packet.append(SSHWire.uint32(32768))
        try sendPacket(packet)
        let reply = try readPacket()
        var reader = SSHReader(data: reply)
        guard let type = reader.byte() else {
            throw SSHFailure.protocolFault(
                "no answer to the channel opening")
        }
        if type == 92 {
            throw SSHFailure.channelRefused(
                "the host said no")
        }
        guard type == 91,
              reader.uint32() != nil,
              let recipient = reader.uint32()
        else {
            throw SSHFailure.protocolFault(
                "an unreadable channel opening")
        }
        serverChannel = recipient
        windowLeft = 1_048_576
        channelClosed = false
    }

    private func sendChannelData(_ data: Data) throws {
        var packet = Data([94])
        packet.append(SSHWire.uint32(serverChannel))
        packet.append(SSHWire.string(data))
        try sendPacket(packet)
    }

    private func sendWindowAdjust() throws {
        var packet = Data([93])
        packet.append(SSHWire.uint32(serverChannel))
        packet.append(SSHWire.uint32(1_048_576))
        try sendPacket(packet)
        windowLeft += 1_048_576
    }

    private func noteWindowUse(_ count: Int) throws {
        windowLeft -= count
        if windowLeft < 524_288 {
            try sendWindowAdjust()
        }
    }

    private func closeChannel() throws {
        if !channelClosed {
            var eof = Data([96])
            eof.append(SSHWire.uint32(serverChannel))
            try sendPacket(eof)
            var close = Data([97])
            close.append(SSHWire.uint32(serverChannel))
            try sendPacket(close)
            channelClosed = true
        }
    }

    /// What one channel packet carried.
    private enum ChannelEvent {
        case data(Data)
        case stderr(Data)
        case exitStatus(Int)
        case requestAnswered(Bool)
        case ended
        case other
    }

    private func readChannelEvent() throws -> ChannelEvent {
        let packet = try readPacket()
        var reader = SSHReader(data: packet)
        guard let type = reader.byte() else {
            return .other
        }
        switch type {
        case 80:
            // A global request (host-key proof offers and
            // the like): politely declined.
            try sendPacket(Data([82]))
            return .other
        case 94:
            _ = reader.uint32()
            guard let data = reader.string() else {
                return .other
            }
            try noteWindowUse(data.count)
            return .data(data)
        case 95:
            _ = reader.uint32()
            _ = reader.uint32()
            guard let data = reader.string() else {
                return .other
            }
            try noteWindowUse(data.count)
            return .stderr(data)
        case 98:
            _ = reader.uint32()
            guard let name = reader.text() else {
                return .other
            }
            if name == "exit-status" {
                _ = reader.byte()
                let status = reader.uint32() ?? -1
                return .exitStatus(status)
            }
            return .other
        case 99:
            return .requestAnswered(true)
        case 100:
            return .requestAnswered(false)
        case 96:
            return .other
        case 97:
            channelClosed = true
            return .ended
        default:
            return .other
        }
    }

    /// Run one command on the host; returns what it said
    /// and how it ended. The caller handshakes first and
    /// disconnects after.
    func exec(_ command: String) throws
        -> (stdout: String, stderr: String, status: Int) {
        try openChannel()
        var request = Data([98])
        request.append(SSHWire.uint32(serverChannel))
        request.append(SSHWire.string("exec"))
        request.append(1)
        request.append(SSHWire.string(command))
        try sendPacket(request)
        var out = Data()
        var err = Data()
        var status = -1
        var answered = false
        while true {
            let event = try readChannelEvent()
            switch event {
            case .requestAnswered(let ok):
                if !answered {
                    answered = true
                    guard ok else {
                        throw SSHFailure.channelRefused(
                            "the exec request itself")
                    }
                }
            case .data(let data):
                out.append(data)
            case .stderr(let data):
                err.append(data)
            case .exitStatus(let value):
                status = value
            case .ended:
                return (String(data: out,
                               encoding: .utf8) ?? "",
                        String(data: err,
                               encoding: .utf8) ?? "",
                        status)
            case .other:
                continue
            }
        }
    }

    /// An interactive shell: the host's output streams to
    /// `output` as it comes; lines from `nextLine` go to
    /// the host until it returns nil (the operator's ~.) or
    /// the host ends the session.
    func shell(nextLine: () -> String?,
               output: @escaping (String) -> Void) throws {
        try openChannel()
        var pty = Data([98])
        pty.append(SSHWire.uint32(serverChannel))
        pty.append(SSHWire.string("pty-req"))
        pty.append(0)
        pty.append(SSHWire.string("vt100"))
        pty.append(SSHWire.uint32(80))
        pty.append(SSHWire.uint32(24))
        pty.append(SSHWire.uint32(0))
        pty.append(SSHWire.uint32(0))
        pty.append(SSHWire.string(Data()))
        try sendPacket(pty)
        var shellReq = Data([98])
        shellReq.append(SSHWire.uint32(serverChannel))
        shellReq.append(SSHWire.string("shell"))
        shellReq.append(1)
        try sendPacket(shellReq)

        let done = NSCondition()
        var ended = false
        let readerThread = Thread { [weak self] in
            guard let self else { return }
            var answered = false
            while true {
                do {
                    let event = try self.readChannelEvent()
                    switch event {
                    case .requestAnswered(let ok):
                        if !answered {
                            answered = true
                            if !ok {
                                output("[the host refused "
                                       + "the shell]\n")
                            }
                        }
                    case .data(let data):
                        output(String(
                            data: data,
                            encoding: .utf8) ?? "")
                    case .stderr(let data):
                        output(String(
                            data: data,
                            encoding: .utf8) ?? "")
                    case .ended:
                        done.lock()
                        ended = true
                        done.broadcast()
                        done.unlock()
                        return
                    default:
                        continue
                    }
                } catch {
                    done.lock()
                    ended = true
                    done.broadcast()
                    done.unlock()
                    return
                }
            }
        }
        readerThread.start()
        while true {
            done.lock()
            let over = ended
            done.unlock()
            if over { break }
            guard let line = nextLine() else { break }
            if line == "~." { break }
            do {
                try sendChannelData(
                    Data((line + "\n").utf8))
            } catch {
                break
            }
        }
        try? closeChannel()
        // Give the reader a moment to see the close.
        done.lock()
        if !ended {
            _ = done.wait(until: Date()
                .addingTimeInterval(2))
        }
        done.unlock()
    }
}

extension SSHClient {

    /// The installable authorized_keys line
    /// for the house identity.
    static func identityLine(
        _ key: Curve25519.Signing.PrivateKey
    ) -> String {
        let blob = SSHWire.string("ssh-ed25519")
            + SSHWire.string(key.publicKey
                .rawRepresentation)
        return "ssh-ed25519 "
            + blob.base64EncodedString()
            + " nightjar-house"
    }

    /// Seal a captured configuration into
    /// the Vault's file format and file it
    /// in Deliveries, under the vault key.
    /// Returns the filed name.
    static func sealBackup(_ text: String,
                           host: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let stamp = formatter.string(from: Date())
        var safeHost = ""
        for character in host {
            safeHost.append(
                character == "/" ? "-" : character)
        }
        let directory = FileManager.default
            .temporaryDirectory
        let plain = directory
            .appendingPathComponent(
                "sshcfg-" + safeHost + "-"
                + stamp + ".txt")
        let sealed = plain
            .appendingPathExtension("njcf")
        do {
            try text.write(to: plain,
                           atomically: true,
                           encoding: .utf8)
            try CryptoFiles.encrypt(
                input: plain, output: sealed,
                protection: .vaultKey,
                password: nil, recipient: nil)
            let name = sealed.lastPathComponent
            if DeliveriesCenter.shared.addFile(
                at: sealed, displayName: name)
                != nil {
                return name
            }
        } catch {
            return nil
        }
        return nil
    }
}
