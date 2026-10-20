import CryptoKit
import Foundation

/// Files, under the Vault's hand — the NJCF
/// envelope. A file too big for a text field is
/// sealed in chunks of a mebibyte, each chunk
/// authenticated on its own, under one random
/// file key; what changes between protections is
/// only how that key is kept:
///
///   password      — the key is wrapped by a
///                   PBKDF2-HMAC-SHA256 key from
///                   the operator's password.
///   vaultKey      — wrapped by the Vault's own
///                   Keychain key: this device
///                   opens it, nothing else does.
///   either        — wrapped twice, once each
///                   way; either opens it.
///   bothRequired  — the file key is one half
///                   (kept by the Vault's key)
///                   XOR the PBKDF2 output: the
///                   password AND this device are
///                   both required, neither alone
///                   suffices.
///   deadDrop      — wrapped for a recipient's
///                   P-256 public key by ephemeral
///                   ECDH, the handshake pass-off:
///                   seal it here, hand the file
///                   over by any road, and only
///                   the holder of that identity
///                   opens it.
///
/// The original filename lives INSIDE the
/// encrypted metadata chunk — the envelope's
/// outside says nothing but its protection.
/// Format: "NJCF" | version | protection |
/// protection material | base nonce | chunk
/// size | length-prefixed sealed chunks.
enum NJCFProtection: Int, CaseIterable {
    case password = 1
    case vaultKey = 2
    case either = 3
    case bothRequired = 4
    case deadDrop = 5

    var label: String {
        switch self {
        case .password: return L("Password")
        case .vaultKey: return L("Vault key")
        case .either: return "Password or vault key"
        case .bothRequired: return "Password and vault key"
        case .deadDrop: return "Dead drop — a recipient's key"
        }
    }

    var involvesPassword: Bool {
        self == .password || self == .either
            || self == .bothRequired
    }
}

enum CryptoFileError: Error, Equatable {
    case notAnEnvelope
    case unsupportedVersion
    case corrupt
    case needsPassword
    case wrongKeyOrPassword
    case truncated
    case truncatedHeader
    case truncatedChunk
    case unreadable
}

struct NJCFInfo {
    var protection: NJCFProtection
    var byteCount: Int
}

enum CryptoFiles {
    static let chunkSize = 1 << 20
    static let iterations = 600_000

    private struct Meta: Codable {
        var name: String
        var size: Int64
    }

    // MARK: - Reading the outside

    /// Parses only the header — enough to say
    /// how a file is protected before anyone
    /// commits to opening it.
    static func inspect(_ url: URL) throws -> NJCFInfo {
        guard let handle = try? FileHandle(
            forReadingFrom: url) else {
            throw CryptoFileError.unreadable
        }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 8192)
        let parsed = try parseHeader(head)
        let size = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size]
            as? NSNumber)?.intValue ?? head.count
        return NJCFInfo(protection: parsed.protection,
                        byteCount: size)
    }

    private struct Header {
        var protection: NJCFProtection
        var iterations: Int = 0
        var salt = Data()
        var wrapPassword = Data()
        var wrapVault = Data()
        var wrapHalf = Data()
        var ephemeral = Data()
        var wrapDeadDrop = Data()
        var baseNonce = Data()
        var chunkSize: Int = CryptoFiles.chunkSize
        var length: Int = 0
    }

    private static func parseHeader(
        _ data: Data
    ) throws -> Header {
        guard data.count >= 6,
              data.prefix(4) == Data("NJCF".utf8)
        else { throw CryptoFileError.notAnEnvelope }
        guard data[4] == 0x01 else {
            throw CryptoFileError.unsupportedVersion
        }
        guard let protection = NJCFProtection(
            rawValue: Int(data[5])) else {
            throw CryptoFileError.corrupt
        }
        var header = Header(protection: protection)
        var index = 6
        func need(_ count: Int) throws {
            guard data.count >= index + count else {
                throw CryptoFileError
                    .truncatedHeader
            }
        }
        func take(_ count: Int) throws -> Data {
            try need(count)
            defer { index += count }
            return data.subdata(in: index..<(index + count))
        }
        func takeWrapped() throws -> Data {
            try need(2)
            let length = Int(data[index]) << 8
                | Int(data[index + 1])
            index += 2
            return try take(length)
        }
        if protection.involvesPassword {
            try need(4)
            header.iterations = Int(
                UInt32(bigEndian: data
                    .subdata(in: index..<(index + 4))
                    .withUnsafeBytes {
                        $0.load(as: UInt32.self) }))
            index += 4
            header.salt = try take(16)
        }
        switch protection {
        case .password, .either:
            header.wrapPassword = try takeWrapped()
        default:
            break
        }
        switch protection {
        case .vaultKey, .either:
            header.wrapVault = try takeWrapped()
        case .bothRequired:
            header.wrapHalf = try takeWrapped()
        default:
            break
        }
        if protection == .deadDrop {
            // The ephemeral public key is
            // 64 bytes: CryptoKit's key-
            // agreement raw form is the
            // point itself, X then Y, with
            // no 0x04 prefix — not the
            // 65-byte x963 form this parser
            // first assumed. The one-byte
            // lie starved every dead-drop
            // parse (the wrap length was
            // read a byte late, as ~15,000
            // in a ~300-byte file) from the
            // format's birth until Gauntlet
            // run 5's head dump measured
            // the truth (2026-10-20).
            header.ephemeral = try take(64)
            header.wrapDeadDrop = try takeWrapped()
        }
        header.baseNonce = try take(12)
        try need(4)
        header.chunkSize = Int(
            UInt32(bigEndian: data
                .subdata(in: index..<(index + 4))
                .withUnsafeBytes {
                    $0.load(as: UInt32.self) }))
        index += 4
        guard header.chunkSize > 0,
              header.chunkSize <= 16 << 20 else {
            throw CryptoFileError.corrupt
        }
        header.length = index
        return header
    }

    // MARK: - The chunk cipher

    /// One chunk's nonce: the base nonce with
    /// the chunk index folded into its last four
    /// bytes — unique per chunk, derived, never
    /// stored.
    private static func nonce(_ base: Data,
                              index: Int) throws
        -> ChaChaPoly.Nonce {
        var bytes = [UInt8](base)
        let value = UInt32(index)
        bytes[8] ^= UInt8((value >> 24) & 0xFF)
        bytes[9] ^= UInt8((value >> 16) & 0xFF)
        bytes[10] ^= UInt8((value >> 8) & 0xFF)
        bytes[11] ^= UInt8(value & 0xFF)
        return try ChaChaPoly.Nonce(
            data: Data(bytes))
    }

    private static func sealChunk(_ plain: Data,
                                  key: SymmetricKey,
                                  base: Data,
                                  index: Int) -> Data? {
        guard let nonce = try? nonce(base, index: index),
              let box = try? ChaChaPoly.seal(
                plain, using: key, nonce: nonce)
        else { return nil }
        // The nonce is derived, never stored: keep
        // only ciphertext and tag.
        return Data(box.combined.dropFirst(12))
    }

    private static func openChunk(_ sealed: Data,
                                  key: SymmetricKey,
                                  base: Data,
                                  index: Int) -> Data? {
        guard let nonce = try? nonce(base, index: index)
        else { return nil }
        var combined = nonce.withUnsafeBytes {
            Data($0) }
        combined.append(contentsOf: sealed)
        guard let box = try? ChaChaPoly.SealedBox(
            combined: combined) else { return nil }
        return try? ChaChaPoly.open(box, using: key)
    }

    // MARK: - Sealing a file

    static func encrypt(
        input: URL, output: URL,
        protection: NJCFProtection,
        password: String?,
        recipient: P256.KeyAgreement.PublicKey?
    ) throws {
        guard let inHandle = try? FileHandle(
            forReadingFrom: input) else {
            throw CryptoFileError.unreadable
        }
        defer { try? inHandle.close() }
        let fileKey = SymmetricKey(size: .bits256)
        let fileKeyData = fileKey.withUnsafeBytes {
            Data($0) }
        let salt = CryptoSuite.randomBytes(16)
        var header = Data("NJCF".utf8)
        header.append(0x01)
        header.append(UInt8(protection.rawValue))
        func wrapped(_ data: Data) -> Data {
            var out = Data()
            var length = UInt16(data.count).bigEndian
            withUnsafeBytes(of: &length) {
                out.append(contentsOf: $0) }
            out.append(contentsOf: data)
            return out
        }
        func passwordKey() -> SymmetricKey? {
            guard let password, !password.isEmpty
            else { return nil }
            return SymmetricKey(data: CryptoSuite
                .pbkdf2(password: password, salt: salt,
                        iterations: iterations,
                        bytes: 32))
        }
        if protection.involvesPassword {
            var it = UInt32(iterations).bigEndian
            withUnsafeBytes(of: &it) { header.append(contentsOf: $0) }
            header.append(contentsOf: salt)
        }
        switch protection {
        case .password, .either:
            guard let key = passwordKey(),
                  let wrap = CryptoSuite.seal(
                    .chacha, key: key, data: fileKeyData)
            else { throw CryptoFileError.needsPassword }
            header.append(contentsOf: wrapped(wrap))
        default:
            break
        }
        switch protection {
        case .vaultKey, .either:
            guard let wrap = CryptoSuite.seal(
                .chacha, key: CryptoSuite.vaultKey(),
                data: fileKeyData) else {
                throw CryptoFileError.corrupt
            }
            header.append(contentsOf: wrapped(wrap))
        case .bothRequired:
            // The kept half: random bytes the Vault
            // key wraps; the password's half is the
            // PBKDF2 output itself. File key =
            // half XOR derived.
            let half = CryptoSuite.randomBytes(32)
            guard let derived = passwordKey() else {
                throw CryptoFileError.needsPassword
            }
            let derivedData = derived.withUnsafeBytes {
                Data($0) }
            var real = Data(count: 32)
            for i in 0..<32 {
                real[i] = half[i] ^ derivedData[i]
            }
            let realKey = SymmetricKey(data: real)
            guard let wrap = CryptoSuite.seal(
                .chacha, key: CryptoSuite.vaultKey(),
                data: half) else {
                throw CryptoFileError.corrupt
            }
            header.append(contentsOf: wrapped(wrap))
            try sealBody(input: inHandle, output: output,
                         header: header,
                         contentKey: realKey,
                         name: input.lastPathComponent)
            return
        default:
            break
        }
        if protection == .deadDrop {
            guard let recipient else {
                throw CryptoFileError.corrupt
            }
            let ephemeral = P256.KeyAgreement
                .PrivateKey()
            guard let secret = try? ephemeral
                .sharedSecretFromKeyAgreement(
                    with: recipient) else {
                throw CryptoFileError.corrupt
            }
            let wrapKey = secret
                .hkdfDerivedSymmetricKey(
                    using: SHA256.self,
                    salt: Data("nightjar-vault".utf8),
                    sharedInfo: Data("dead-drop-file"
                                        .utf8),
                    outputByteCount: 32)
            guard let wrap = CryptoSuite.seal(
                .aes, key: wrapKey, data: fileKeyData)
            else { throw CryptoFileError.corrupt }
            header.append(contentsOf:
                ephemeral.publicKey.rawRepresentation)
            header.append(contentsOf: wrapped(wrap))
        }
        try sealBody(input: inHandle, output: output,
                     header: header, contentKey: fileKey,
                     name: input.lastPathComponent)
    }

    private static func sealBody(
        input: FileHandle, output: URL,
        header: Data, contentKey: SymmetricKey,
        name: String
    ) throws {
        var header = header
        let baseNonce = CryptoSuite.randomBytes(12)
        header.append(contentsOf: baseNonce)
        var size = UInt32(chunkSize).bigEndian
        withUnsafeBytes(of: &size) { header.append(contentsOf: $0) }
        FileManager.default.createFile(
            atPath: output.path, contents: nil)
        guard let outHandle = try? FileHandle(
            forWritingTo: output) else {
            throw CryptoFileError.unreadable
        }
        defer { try? outHandle.close() }
        outHandle.write(header)
        let total = (try? input.seekToEnd()) ?? 0
        try? input.seek(toOffset: 0)
        let meta = Meta(name: name, size: Int64(total))
        guard let metaData = try? JSONEncoder()
                .encode(meta),
              let sealedMeta = sealChunk(
                metaData, key: contentKey,
                base: baseNonce, index: 0)
        else { throw CryptoFileError.corrupt }
        writeChunk(sealedMeta, to: outHandle)
        var index = 1
        while true {
            let plain = input.readData(
                ofLength: chunkSize)
            if plain.isEmpty { break }
            guard let sealed = sealChunk(
                plain, key: contentKey,
                base: baseNonce, index: index)
            else { throw CryptoFileError.corrupt }
            writeChunk(sealed, to: outHandle)
            index += 1
        }
    }

    private static func writeChunk(_ sealed: Data,
                                   to handle: FileHandle) {
        var length = UInt32(sealed.count).bigEndian
        let lengthData = withUnsafeBytes(of: &length) {
            Data($0) }
        handle.write(lengthData)
        handle.write(sealed)
    }

    // MARK: - Opening a file

    /// Decrypts into `outputDirectory` under the
    /// original filename kept in the metadata,
    /// made unique if the name is taken. Returns
    /// the restored file's URL.
    static func decrypt(
        input: URL, password: String?,
        outputDirectory: URL
    ) throws -> URL {
        guard let inHandle = try? FileHandle(
            forReadingFrom: input) else {
            throw CryptoFileError.unreadable
        }
        defer { try? inHandle.close() }
        let head = inHandle.readData(ofLength: 8192)
        let parsed = try parseHeader(head)
        try inHandle.seek(toOffset:
            UInt64(parsed.length))
        let fileKey = try unlockKey(
            parsed, password: password)
        var index = 0
        func nextChunk() throws -> Data? {
            let lengthData = inHandle.readData(
                ofLength: 4)
            if lengthData.isEmpty { return nil }
            guard lengthData.count == 4 else {
                throw CryptoFileError
                    .truncatedChunk
            }
            let length = Int(UInt32(bigEndian:
                lengthData.withUnsafeBytes {
                    $0.load(as: UInt32.self) }))
            guard length >= 16,
                  length <= parsed.chunkSize + 1024
            else { throw CryptoFileError.corrupt }
            let sealed = inHandle.readData(
                ofLength: length)
            guard sealed.count == length else {
                throw CryptoFileError
                    .truncatedChunk
            }
            guard let plain = openChunk(
                sealed, key: fileKey,
                base: parsed.baseNonce, index: index)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            index += 1
            return plain
        }
        guard let metaData = try nextChunk(),
              let meta = try? JSONDecoder().decode(
                Meta.self, from: metaData)
        else { throw CryptoFileError.corrupt }
        let safeName = (meta.name as NSString)
            .lastPathComponent
        let output = uniqueURL(
            in: outputDirectory,
            name: safeName.isEmpty
                ? "recovered-file" : safeName)
        FileManager.default.createFile(
            atPath: output.path, contents: nil)
        guard let outHandle = try? FileHandle(
            forWritingTo: output) else {
            throw CryptoFileError.unreadable
        }
        var written: Int64 = 0
        while let plain = try nextChunk() {
            outHandle.write(plain)
            written += Int64(plain.count)
        }
        try? outHandle.close()
        guard written == meta.size else {
            try? FileManager.default.removeItem(
                at: output)
            throw CryptoFileError.truncated
        }
        return output
    }

    private static func unlockKey(
        _ header: Header, password: String?
    ) throws -> SymmetricKey {
        switch header.protection {
        case .password:
            guard let key = passwordKey(
                header, password) else {
                throw CryptoFileError.needsPassword
            }
            guard let data = CryptoSuite.open(
                .chacha, key: key,
                sealed: header.wrapPassword)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            return SymmetricKey(data: data)
        case .vaultKey:
            guard let data = CryptoSuite.open(
                .chacha, key: CryptoSuite.vaultKey(),
                sealed: header.wrapVault)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            return SymmetricKey(data: data)
        case .either:
            if let password, !password.isEmpty {
                guard let key = passwordKey(
                    header, password),
                      let data = CryptoSuite.open(
                        .chacha, key: key,
                        sealed: header.wrapPassword)
                else {
                    throw CryptoFileError
                        .wrongKeyOrPassword
                }
                return SymmetricKey(data: data)
            }
            guard let data = CryptoSuite.open(
                .chacha, key: CryptoSuite.vaultKey(),
                sealed: header.wrapVault)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            return SymmetricKey(data: data)
        case .bothRequired:
            guard let derived = passwordKey(
                header, password) else {
                throw CryptoFileError.needsPassword
            }
            guard let half = CryptoSuite.open(
                .chacha, key: CryptoSuite.vaultKey(),
                sealed: header.wrapHalf)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            let derivedData = derived.withUnsafeBytes {
                Data($0) }
            var real = Data(count: 32)
            for i in 0..<32 {
                real[i] = half[i] ^ derivedData[i]
            }
            return SymmetricKey(data: real)
        case .deadDrop:
            let mine = CryptoSuite.identity()
            guard let ephemeral = try? P256
                .KeyAgreement.PublicKey(
                    rawRepresentation: header.ephemeral),
                  let secret = try? mine
                    .sharedSecretFromKeyAgreement(
                        with: ephemeral)
            else { throw CryptoFileError.corrupt }
            let wrapKey = secret
                .hkdfDerivedSymmetricKey(
                    using: SHA256.self,
                    salt: Data("nightjar-vault".utf8),
                    sharedInfo: Data("dead-drop-file"
                                        .utf8),
                    outputByteCount: 32)
            guard let data = CryptoSuite.open(
                .aes, key: wrapKey,
                sealed: header.wrapDeadDrop)
            else {
                throw CryptoFileError.wrongKeyOrPassword
            }
            return SymmetricKey(data: data)
        }
    }

    private static func passwordKey(
        _ header: Header, _ password: String?
    ) -> SymmetricKey? {
        guard let password, !password.isEmpty else {
            return nil
        }
        return SymmetricKey(data: CryptoSuite.pbkdf2(
            password: password, salt: header.salt,
            iterations: header.iterations, bytes: 32))
    }

    private static func uniqueURL(
        in directory: URL, name: String
    ) -> URL {
        var candidate = directory
            .appendingPathComponent(name)
        if !FileManager.default.fileExists(
            atPath: candidate.path) {
            return candidate
        }
        let base = (name as NSString)
            .deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let renamed = ext.isEmpty
                ? "\(base) \(counter)"
                : "\(base) \(counter).\(ext)"
            candidate = directory
                .appendingPathComponent(renamed)
            if !FileManager.default.fileExists(
                atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
