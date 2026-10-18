import CryptoKit
import Foundation

/// The Vault's engine: a complete, self-contained
/// cryptography and cryptology suite — hashes,
/// MACs, key derivation, authenticated sealing,
/// public-key envelopes, encodings and secure
/// randomness — built only on CryptoKit and the
/// standard library, every construction modern
/// and self-describing. It serves the Vault tab
/// directly and Skelli's hands by extension: one
/// engine, two operators, no second truth.
enum CryptoSuite {

    // MARK: - Encodings

    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hexDecode(_ string: String) -> Data? {
        let clean = string.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var out = Data()
        out.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(
                clean[index..<next], radix: 16)
            else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    /// RFC 4648 base32, padded; decoding tolerates
    /// lowercase and missing padding.
    static func base32Encode(_ data: Data) -> String {
        let alphabet = Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var out = ""
        var buffer: UInt32 = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(alphabet[Int(
                    (buffer >> UInt32(bits)) & 0x1F)])
            }
        }
        if bits > 0 {
            out.append(alphabet[Int(
                (buffer << UInt32(5 - bits)) & 0x1F)])
        }
        while out.count % 8 != 0 { out.append("=") }
        return out
    }

    static func base32Decode(_ string: String) -> Data? {
        let clean = string.uppercased()
            .filter { !$0.isWhitespace && $0 != "=" }
        var out = Data()
        var buffer: UInt32 = 0
        var bits = 0
        for char in clean {
            let value: UInt32
            // Values come from the matched range itself,
            // never from force-unwrapped ASCII: a pasted
            // decomposed character (a letter plus a
            // combining mark) can satisfy a range match
            // while its asciiValue is nil.
            switch char {
            case "A": value = 0
            case "B": value = 1
            case "C": value = 2
            case "D": value = 3
            case "E": value = 4
            case "F": value = 5
            case "G": value = 6
            case "H": value = 7
            case "I": value = 8
            case "J": value = 9
            case "K": value = 10
            case "L": value = 11
            case "M": value = 12
            case "N": value = 13
            case "O": value = 14
            case "P": value = 15
            case "Q": value = 16
            case "R": value = 17
            case "S": value = 18
            case "T": value = 19
            case "U": value = 20
            case "V": value = 21
            case "W": value = 22
            case "X": value = 23
            case "Y": value = 24
            case "Z": value = 25
            case "2": value = 26
            case "3": value = 27
            case "4": value = 28
            case "5": value = 29
            case "6": value = 30
            case "7": value = 31
            default:
                return nil
            }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(
                    (buffer >> UInt32(bits)) & 0xFF))
            }
        }
        return out
    }

    // MARK: - Hashes and MACs

    enum HashKind: String, CaseIterable {
        case sha256 = "SHA-256"
        case sha384 = "SHA-384"
        case sha512 = "SHA-512"
        case sha1 = "SHA-1 (legacy)"
        case md5 = "MD5 (legacy)"
    }

    static func hash(_ kind: HashKind,
                     _ data: Data) -> Data {
        switch kind {
        case .sha256:
            return Data(SHA256.hash(data: data))
        case .sha384:
            return Data(SHA384.hash(data: data))
        case .sha512:
            return Data(SHA512.hash(data: data))
        case .sha1:
            return Data(Insecure.SHA1.hash(data: data))
        case .md5:
            return Data(Insecure.MD5.hash(data: data))
        }
    }

    static func hmacSHA256(key: Data,
                           data: Data) -> Data {
        let code = HMAC<SHA256>.authenticationCode(
            for: data, using: SymmetricKey(data: key))
        return Data(code)
    }

    /// A fingerprint a human can read back:
    /// the SHA-256 of the data, grouped.
    static func fingerprint(_ data: Data) -> String {
        let hex = hexEncode(hash(.sha256, data))
            .uppercased()
        var groups: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(
                index, offsetBy: 4,
                limitedBy: hex.endIndex) ?? hex.endIndex
            groups.append(String(hex[index..<next]))
            index = next
        }
        return groups.joined(separator: " ")
    }

    // MARK: - Key derivation

    /// PBKDF2-HMAC-SHA256, hand-rolled over
    /// CryptoKit's HMAC so the suite owes
    /// nothing to CommonCrypto.
    static func pbkdf2(password: String, salt: Data,
                       iterations: Int,
                       bytes: Int) -> Data {
        let key = SymmetricKey(
            data: Data(password.utf8))
        var derived = Data()
        var blockIndex: UInt32 = 1
        while derived.count < bytes {
            var block = salt
            block.append(UInt8(truncatingIfNeeded:
                blockIndex >> 24))
            block.append(UInt8(truncatingIfNeeded:
                blockIndex >> 16))
            block.append(UInt8(truncatingIfNeeded:
                blockIndex >> 8))
            block.append(UInt8(truncatingIfNeeded:
                blockIndex))
            var u = Data(HMAC<SHA256>
                .authenticationCode(
                    for: block, using: key))
            var t = u
            for _ in 1..<max(iterations, 1) {
                u = Data(HMAC<SHA256>
                    .authenticationCode(
                        for: u, using: key))
                for i in t.indices {
                    t[i] ^= u[i]
                }
            }
            derived.append(contentsOf: t)
            blockIndex += 1
        }
        return Data(derived.prefix(bytes))
    }

    static func hkdf(inputKey: Data, salt: Data,
                     info: String, bytes: Int) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: inputKey),
            salt: salt,
            info: Data(info.utf8),
            outputByteCount: bytes)
        return key.withUnsafeBytes { Data($0) }
    }

    // MARK: - Authenticated sealing

    enum Cipher: String, Codable, CaseIterable {
        case chacha = "ChaCha20-Poly1305"
        case aes = "AES-256-GCM"
    }

    static func seal(_ cipher: Cipher,
                     key: SymmetricKey,
                     data: Data) -> Data? {
        switch cipher {
        case .chacha:
            return try? ChaChaPoly.seal(
                data, using: key).combined
        case .aes:
            return try? AES.GCM.seal(
                data, using: key).combined
        }
    }

    static func open(_ cipher: Cipher,
                     key: SymmetricKey,
                     sealed: Data) -> Data? {
        switch cipher {
        case .chacha:
            guard let box = try? ChaChaPoly.SealedBox(
                combined: sealed) else { return nil }
            return try? ChaChaPoly.open(box, using: key)
        case .aes:
            guard let box = try? AES.GCM.SealedBox(
                combined: sealed) else { return nil }
            return try? AES.GCM.open(box, using: key)
        }
    }

    // MARK: - The password envelope
    //
    // Self-describing, so anything sealed can be
    // opened by any copy of the suite:
    //   "NJCS" | version 1 | cipher byte |
    //   iterations (UInt32, big-endian) |
    //   salt (16 bytes) | the sealed box.
    // The key is PBKDF2-HMAC-SHA256 over the
    // password; the box carries its own nonce
    // and tag.

    static func sealWithPassword(
        _ data: Data, password: String,
        cipher: Cipher, iterations: Int) -> Data? {
        let salt = randomBytes(16)
        let keyData = pbkdf2(password: password,
                             salt: salt,
                             iterations: iterations,
                             bytes: 32)
        guard let sealed = seal(
            cipher, key: SymmetricKey(data: keyData),
            data: data) else { return nil }
        var out = Data("NJCS".utf8)
        out.append(0x01)
        out.append(cipher == .chacha ? 0x01 : 0x02)
        var it = UInt32(iterations).bigEndian
        withUnsafeBytes(of: &it) { out.append(contentsOf: $0) }
        out.append(contentsOf: salt)
        out.append(contentsOf: sealed)
        return out
    }

    static func openWithPassword(
        _ envelope: Data, password: String) -> Data? {
        guard envelope.count > 26,
              envelope.prefix(4) == Data("NJCS".utf8),
              envelope[4] == 0x01
        else { return nil }
        let cipher: Cipher = envelope[5] == 0x02
            ? .aes : .chacha
        let iterations = Int(
            UInt32(bigEndian: envelope
                .subdata(in: 6..<10)
                .withUnsafeBytes {
                    $0.load(as: UInt32.self)
                }))
        let salt = envelope.subdata(in: 10..<26)
        let sealed = envelope.subdata(
            in: 26..<envelope.count)
        let keyData = pbkdf2(password: password,
                             salt: salt,
                             iterations: iterations,
                             bytes: 32)
        return open(cipher,
                    key: SymmetricKey(data: keyData),
                    sealed: sealed)
    }

    // MARK: - Keys and randomness

    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress
            else { return }
            SecRandomCopyBytes(kSecRandomDefault,
                               count, base)
        }
        return data
    }

    static func randomHex(_ bytes: Int) -> String {
        hexEncode(randomBytes(bytes))
    }

    /// A password from the unambiguous alphabet —
    /// no 0/O, no 1/l — fit to read aloud.
    static func randomPassword(length: Int = 20)
        -> String {
        let alphabet = Array(
            "abcdefghjkmnpqrstuvwxyz"
            + "ABCDEFGHJKMNPQRSTUVWXYZ"
            + "23456789")
        let raw = randomBytes(length)
        return String(raw.map {
            alphabet[Int($0) % alphabet.count]
        })
    }

    /// The house's kept keys live in the Keychain
    /// under this service — never in defaults,
    /// never in a file.
    private static let keyService = "nightjar.crypto"

    static func keptKeyData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String:
                kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(
                query as CFDictionary, &item)
                == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return data
    }

    static func keepKeyData(_ data: Data,
                            account: String) {
        let base: [String: Any] = [
            kSecClass as String:
                kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data]
                as CFDictionary)
        if status == errSecItemNotFound {
            var query = base
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    /// The Vault's own AES-256 key, made on
    /// first use and kept in the Keychain.
    static func vaultKey() -> SymmetricKey {
        if let data = keptKeyData(
            account: "vault-aes-key"), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        keepKeyData(data, account: "vault-aes-key")
        return key
    }

    /// The house identity for dead-drop
    /// envelopes: a P-256 key pair whose private
    /// half never leaves the Keychain.
    static func identity()
        -> P256.KeyAgreement.PrivateKey {
        if let data = keptKeyData(
            account: "identity-p256"),
           let key = try? P256.KeyAgreement
            .PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = P256.KeyAgreement.PrivateKey()
        keepKeyData(key.rawRepresentation,
                    account: "identity-p256")
        return key
    }

    /// Seal for a recipient's public key: an
    /// ephemeral ECDH exchange, HKDF, AES-GCM.
    /// Output: ephemeral public key (65) |
    /// the sealed box.
    static func envelopeSeal(
        _ data: Data,
        for recipient: P256.KeyAgreement.PublicKey)
        -> Data? {
        let ephemeral = P256.KeyAgreement.PrivateKey()
        guard let secret = try? ephemeral
            .sharedSecretFromKeyAgreement(
                with: recipient)
        else { return nil }
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("nightjar-vault".utf8),
            sharedInfo: Data("dead-drop".utf8),
            outputByteCount: 32)
        guard let sealed = seal(.aes, key: key,
                                data: data)
        else { return nil }
        var out = Data(ephemeral.publicKey
            .rawRepresentation)
        out.append(contentsOf: sealed)
        return out
    }

    static func envelopeOpen(_ envelope: Data) -> Data? {
        guard envelope.count > 65 else { return nil }
        let mine = identity()
        let ephemeralData = envelope.subdata(in: 0..<65)
        guard let ephemeral = try? P256.KeyAgreement
                .PublicKey(rawRepresentation:
                            ephemeralData),
              let secret = try? mine
                .sharedSecretFromKeyAgreement(
                    with: ephemeral)
        else { return nil }
        let key = secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("nightjar-vault".utf8),
            sharedInfo: Data("dead-drop".utf8),
            outputByteCount: 32)
        return open(.aes, key: key,
                    sealed: envelope.subdata(
                        in: 65..<envelope.count))
    }
}


// MARK: - Presets

/// A named, one-tap configuration — the suite's
/// valued starting points. A preset chooses the
/// construction and its parameters whole; the
/// operator brings only the material.
struct CryptoPreset: Identifiable {
    enum Operation {
        case sealPassword, openPassword
        case sealVaultKey, openVaultKey
        case envelopeSeal, envelopeOpen
        case hashDigest, fingerprintCard
        case oneTimePad
    }

    let id: String
    let name: String
    let detail: String
    let operation: Operation
    var cipher: CryptoSuite.Cipher = .chacha
    var iterations: Int = 600_000

    static let all: [CryptoPreset] = [
        CryptoPreset(
            id: "sealed-note", name: "Sealed note",
            detail: "ChaCha20-Poly1305 under a "
                + "password, PBKDF2-HMAC-SHA256 "
                + "at 600,000 rounds. The envelope "
                + "describes itself; any copy of "
                + "the suite opens it.",
            operation: .sealPassword),
        CryptoPreset(
            id: "open-note", name: "Open a sealed note",
            detail: "The other side of the sealed "
                + "note — the envelope says which "
                + "cipher and how many rounds; "
                + "bring the password.",
            operation: .openPassword),
        CryptoPreset(
            id: "vault-seal", name: "Vault seal",
            detail: "AES-256-GCM under the Vault's "
                + "own key, kept in the Keychain "
                + "and never shown. For material "
                + "that stays on this device.",
            operation: .sealVaultKey, cipher: .aes),
        CryptoPreset(
            id: "vault-open", name: "Open a vault seal",
            detail: "Opens what the vault seal "
                + "closed, with the same kept key.",
            operation: .openVaultKey, cipher: .aes),
        CryptoPreset(
            id: "dead-drop", name: "Dead-drop envelope",
            detail: "For the house identity: an "
                + "ephemeral P-256 exchange, HKDF, "
                + "AES-GCM. Sealed to a public key; "
                + "only its private half opens it.",
            operation: .envelopeSeal, cipher: .aes),
        CryptoPreset(
            id: "dead-open", name: "Open a dead-drop",
            detail: "Opens an envelope sealed to "
                + "this house's identity key.",
            operation: .envelopeOpen, cipher: .aes),
        CryptoPreset(
            id: "hash-card", name: "Hash card",
            detail: "SHA-256 and SHA-512 side by "
                + "side, with the grouped "
                + "fingerprint — the identity of a "
                + "text or file, fit to compare "
                + "aloud.",
            operation: .hashDigest),
        CryptoPreset(
            id: "fingerprint", name: "Fingerprint",
            detail: "The grouped SHA-256 alone — "
                + "sixteen groups of four, made to "
                + "be read over a voice channel.",
            operation: .fingerprintCard),
        CryptoPreset(
            id: "otp", name: "One-time pad",
            detail: "A true pad: fresh random "
                + "bytes as long as the message, "
                + "XORed. Two halves come out — "
                + "cipher and pad; separated, "
                + "either alone is noise.",
            operation: .oneTimePad),
    ]
}

/// The operator's own saved configurations —
/// cipher, derivation, rounds, output dress —
/// kept as a JSON string in the settings, so
/// they ride the house's setup mirror like
/// every other configuration.
struct CryptoUserPreset: Codable, Identifiable {
    var id: String
    var name: String
    var cipher: String
    var iterations: Int
    var encoding: String

    static let key = "crypto.userPresets"

    static func load() -> [CryptoUserPreset] {
        guard let raw = UserDefaults.standard
                .string(forKey: key),
              let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode(
                [CryptoUserPreset].self, from: data)
        else { return [] }
        return list
    }

    static func save(_ list: [CryptoUserPreset]) {
        guard let data = try? JSONEncoder().encode(
                list),
              let raw = String(data: data,
                               encoding: .utf8)
        else { return }
        UserDefaults.standard.set(raw, forKey: key)
    }
}

// MARK: - Skelli's hands on the suite

extension SkelliCenter {
    /// Her quiet crypto hand: works the suite
    /// and returns the words, or nil when the
    /// sentence is not the suite's business.
    /// Instant operations only — hashing,
    /// fingerprints, encodings, fresh keys and
    /// passwords. Sealing under a password
    /// belongs to the Vault, where passwords
    /// are typed into proper fields.
    func cryptoAct(_ raw: String) -> String? {
        let q = raw.lowercased()
        func subject(after marker: String)
            -> String? {
            guard let range = raw.range(
                of: marker,
                options: .caseInsensitive)
            else { return nil }
            let tail = raw[range.upperBound...]
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            return tail.isEmpty ? nil : tail
        }
        if q.hasPrefix("hash ")
            || q.contains("sha256 of")
            || q.contains("sha-256 of") {
            guard let text = subject(after: "hash ")
                ?? subject(after: "of ")
            else { return "Hash what? Say: hash, "
                + "then the words." }
            let digest = CryptoSuite.hash(
                .sha256, Data(text.utf8))
            return "SHA-256 of that: "
                + CryptoSuite.hexEncode(digest)
        }
        if q.hasPrefix("fingerprint ") {
            guard let text = subject(
                after: "fingerprint ")
            else { return "Fingerprint what?" }
            return "Fingerprint: "
                + CryptoSuite.fingerprint(
                    Data(text.utf8))
        }
        if q.contains("base64 encode") {
            guard let text = subject(
                after: "encode ")
            else { return "Encode what?" }
            return Data(text.utf8)
                .base64EncodedString()
        }
        if q.contains("base64 decode") {
            guard let text = subject(
                after: "decode "),
                  let data = Data(
                    base64Encoded: text),
                  let words = String(
                    data: data, encoding: .utf8)
            else { return "That would not decode "
                + "— check the base64." }
            return words
        }
        if q.contains("hex encode") {
            guard let text = subject(
                after: "encode ")
            else { return "Encode what?" }
            return CryptoSuite.hexEncode(
                Data(text.utf8))
        }
        if q.contains("hex decode") {
            guard let text = subject(
                after: "decode "),
                  let data = CryptoSuite
                    .hexDecode(text),
                  let words = String(
                    data: data, encoding: .utf8)
            else { return "That would not decode "
                + "— hex wants pairs of digits." }
            return words
        }
        if q.contains("generate a key")
            || q.contains("new key")
            || q.contains("fresh key") {
            let key = CryptoSuite.randomHex(32)
            return "A fresh 256-bit key, shown "
                + "once — I keep no copy: " + key
        }
        if q.contains("generate a password")
            || q.contains("new password") {
            return "A fresh password, shown once: "
                + CryptoSuite.randomPassword()
        }
        if q.contains("random bytes")
            || q.contains("random hex") {
            return CryptoSuite.randomHex(32)
        }
        return nil
    }

    /// The spoken door to the same hand, in the
    /// respond chain's shape.
    func cryptoAsk(_ q: String, raw: String) -> Bool {
        let triggers = ["hash ", "fingerprint ",
                        "base64 encode",
                        "base64 decode",
                        "hex encode", "hex decode",
                        "generate a key", "new key",
                        "fresh key",
                        "generate a password",
                        "new password",
                        "random bytes", "random hex",
                        "sha256 of", "sha-256 of"]
        guard triggers.contains(where: {
            q.contains($0) || q.hasPrefix($0)
        }) else { return false }
        guard let answer = cryptoAct(raw)
        else { return false }
        say(answer)
        return true
    }
}
