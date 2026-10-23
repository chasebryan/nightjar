import AVFoundation
import CryptoKit
import Foundation
import SwiftUI

/// MAWKBOX — the sound modem, friendly edition.
///
/// A port of the lab's own mawkbox (nightwarelabz/mawkbox)
/// to the phone, wire-compatible with the original: the
/// same MWK1 frame, the same scrypt + ChaCha20-Poly1305
/// seal, the same four tones at 200 baud. A laptop running
/// mawkbox and this phone can sing to each other.
///
/// The format (mawkbox FORMAT.md, version 1):
///   frame  = "MWK1" · version(1) · flags(1: 0 plain,
///            1 encrypted) · payload length (4, BE) ·
///            payload · CRC32 (IEEE, of header + payload)
///   sealed payload = salt(16) · nonce(12) ·
///            ChaCha20-Poly1305 ciphertext + tag, the key
///            scrypt(passphrase, salt, N=16384, r=8, p=1),
///            the 10-byte header as associated data.
///   audio  = 48 kHz mono; each symbol is 240 samples
///            carrying one dibit (MSB first): 1200 / 1600 /
///            2000 / 2400 Hz for 00 / 01 / 10 / 11, every
///            tone starting at phase zero at amplitude
///            0.65; a transmission is 100 ms of silence,
///            the 8-byte stem, the frame, 100 ms of
///            silence. Plaintext caps at 4096 UTF-8 bytes.
///   There is error DETECTION (the CRC, and the AEAD tag
///   on sealed messages) but no error correction — a
///   damaged signal is refused, never guessed at.
///
/// Doctrine: playing is a transmission, so EMCON refuses
/// it at Bravo and above; listening is receive-only, so
/// EMCON refuses it at Alpha alone (the wardrive rule).
/// The passphrase lives in the sheet's field and the
/// frame it seals — it is never logged, never stored,
/// and the console's mawk verb speaks plain only, the
/// App Lock rule for secrets.

// MARK: - Errors

enum MawkError: Error {
    case tooLong
    case emptyPassphrase
    case truncated
    case unsupported
    case badLength
    case checksum
    case needsPassphrase
    case authFailed
    case badText
    case tooShort
    case noSignal
    case badAudioFile

    var line: String {
        switch self {
        case .tooLong:
            return L("That message is over the 4096-byte cap.")
        case .emptyPassphrase:
            return L("Enter a passphrase, or choose plain.")
        case .truncated:
            return L("That frame is truncated.")
        case .unsupported:
            return L("That frame is not a mawkbox frame this house reads.")
        case .badLength:
            return L("That frame's length does not add up.")
        case .checksum:
            return L("Signal is damaged: checksum failed.")
        case .needsPassphrase:
            return L("This transmission requires a passphrase.")
        case .authFailed:
            return L("Authentication failed: wrong passphrase or altered message.")
        case .badText:
            return L("That payload is not readable text.")
        case .tooShort:
            return L("That audio is too short for a mawkbox transmission.")
        case .noSignal:
            return L("No intact mawkbox signal found.")
        case .badAudioFile:
            return L("That file is not WAV audio this house can read.")
        }
    }
}

// MARK: - The codec

enum Mawk {
    static let rate = 48000
    static let samplesPerSymbol = 240
    static let tones: [Double] = [1200, 1600, 2000, 2400]
    static let maxText = 4096
    static let maxFrame = maxText + 64
    static let headerSize = 10
    static let stem: [UInt8] = [0x1b, 0xe4, 0x93, 0x6c,
                                0x27, 0xd8, 0xb1, 0x4e]
    private static let magic: [UInt8] = [0x4d, 0x57, 0x4b, 0x31]

    // MARK: CRC32 (IEEE, the zlib polynomial)

    private static let crcTable: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
                ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: scrypt (RFC 7914)

    /// PBKDF2-HMAC-SHA256, the scrypt wrapper's shape:
    /// a single iteration at both ends.
    private static func pbkdf2SHA256(
        passphrase: [UInt8], salt: [UInt8], length: Int
    ) -> [UInt8] {
        let key = SymmetricKey(data: passphrase)
        var out: [UInt8] = []
        var block: UInt32 = 1
        while out.count < length {
            var msg = salt
            msg.append(UInt8((block >> 24) & 0xFF))
            msg.append(UInt8((block >> 16) & 0xFF))
            msg.append(UInt8((block >> 8) & 0xFF))
            msg.append(UInt8(block & 0xFF))
            let mac = HMAC<SHA256>.authenticationCode(
                for: msg, using: key)
            out += [UInt8](mac)
            block += 1
        }
        return Array(out.prefix(length))
    }

    private static func salsa208(_ block: inout [UInt8]) {
        // 64 bytes as 16 little-endian words, 8 rounds,
        // the input added back at the end.
        var x = [UInt32](repeating: 0, count: 16)
        var original = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let o = i * 4
            let v = UInt32(block[o])
                | (UInt32(block[o + 1]) << 8)
                | (UInt32(block[o + 2]) << 16)
                | (UInt32(block[o + 3]) << 24)
            x[i] = v
            original[i] = v
        }
        func rot(_ v: UInt32, _ n: UInt32) -> UInt32 {
            (v << n) | (v >> (32 - n))
        }
        for _ in stride(from: 0, to: 8, by: 2) {
            // column round
            x[4] ^= rot(x[0] &+ x[12], 7)
            x[8] ^= rot(x[4] &+ x[0], 9)
            x[12] ^= rot(x[8] &+ x[4], 13)
            x[0] ^= rot(x[12] &+ x[8], 18)
            x[9] ^= rot(x[5] &+ x[1], 7)
            x[13] ^= rot(x[9] &+ x[5], 9)
            x[1] ^= rot(x[13] &+ x[9], 13)
            x[5] ^= rot(x[1] &+ x[13], 18)
            x[14] ^= rot(x[10] &+ x[6], 7)
            x[2] ^= rot(x[14] &+ x[10], 9)
            x[6] ^= rot(x[2] &+ x[14], 13)
            x[10] ^= rot(x[6] &+ x[2], 18)
            x[3] ^= rot(x[15] &+ x[11], 7)
            x[7] ^= rot(x[3] &+ x[15], 9)
            x[11] ^= rot(x[7] &+ x[3], 13)
            x[15] ^= rot(x[11] &+ x[7], 18)
            // row round
            x[1] ^= rot(x[0] &+ x[3], 7)
            x[2] ^= rot(x[1] &+ x[0], 9)
            x[3] ^= rot(x[2] &+ x[1], 13)
            x[0] ^= rot(x[3] &+ x[2], 18)
            x[6] ^= rot(x[5] &+ x[4], 7)
            x[7] ^= rot(x[6] &+ x[5], 9)
            x[4] ^= rot(x[7] &+ x[6], 13)
            x[5] ^= rot(x[4] &+ x[7], 18)
            x[11] ^= rot(x[10] &+ x[9], 7)
            x[8] ^= rot(x[11] &+ x[10], 9)
            x[9] ^= rot(x[8] &+ x[11], 13)
            x[10] ^= rot(x[9] &+ x[8], 18)
            x[12] ^= rot(x[15] &+ x[14], 7)
            x[13] ^= rot(x[12] &+ x[15], 9)
            x[14] ^= rot(x[13] &+ x[12], 13)
            x[15] ^= rot(x[14] &+ x[13], 18)
        }
        for i in 0..<16 {
            let v = x[i] &+ original[i]
            let o = i * 4
            block[o] = UInt8(v & 0xFF)
            block[o + 1] = UInt8((v >> 8) & 0xFF)
            block[o + 2] = UInt8((v >> 16) & 0xFF)
            block[o + 3] = UInt8((v >> 24) & 0xFF)
        }
    }

    private static func blockMix(_ input: [UInt8], r: Int) -> [UInt8] {
        var x = Array(input.suffix(64))
        var y = [[UInt8]]()
        y.reserveCapacity(2 * r)
        for i in 0..<(2 * r) {
            for j in 0..<64 {
                x[j] ^= input[i * 64 + j]
            }
            salsa208(&x)
            y.append(x)
        }
        var out = [UInt8](repeating: 0, count: 128 * r)
        for i in 0..<r {
            out.replaceSubrange(
                (i * 64)..<((i + 1) * 64), with: y[2 * i])
            out.replaceSubrange(
                ((r + i) * 64)..<((r + i + 1) * 64),
                with: y[2 * i + 1])
        }
        return out
    }

    private static func roMix(_ input: [UInt8], n: Int, r: Int) -> [UInt8] {
        var x = input
        var v = [[UInt8]]()
        v.reserveCapacity(n)
        for _ in 0..<n {
            v.append(x)
            x = blockMix(x, r: r)
        }
        for _ in 0..<n {
            // Integerify: the first 8 bytes of the last
            // block, little-endian; n is a power of two,
            // so the low word's mask is the whole mod.
            let base = (2 * r - 1) * 64
            let low = UInt32(x[base])
                | (UInt32(x[base + 1]) << 8)
                | (UInt32(x[base + 2]) << 16)
                | (UInt32(x[base + 3]) << 24)
            let j = Int(low & UInt32(n - 1))
            for k in 0..<(128 * r) {
                x[k] ^= v[j][k]
            }
            x = blockMix(x, r: r)
        }
        return x
    }

    /// scrypt with caller-chosen parameters (the Gauntlet
    /// pins the RFC 7914 vectors through this door); the
    /// format itself always uses key() below.
    static func scrypt(
        passphrase: [UInt8], salt: [UInt8],
        n: Int, r: Int, p: Int, length: Int
    ) -> [UInt8] {
        var b = pbkdf2SHA256(
            passphrase: passphrase, salt: salt,
            length: p * 128 * r)
        for i in 0..<p {
            let slice = Array(b[(i * 128 * r)..<((i + 1) * 128 * r)])
            let mixed = roMix(slice, n: n, r: r)
            b.replaceSubrange(
                (i * 128 * r)..<((i + 1) * 128 * r), with: mixed)
        }
        return pbkdf2SHA256(
            passphrase: passphrase, salt: b, length: length)
    }

    /// The format's key: scrypt N=16384, r=8, p=1, 32 bytes.
    static func key(passphrase: String, salt: [UInt8]) -> [UInt8] {
        scrypt(passphrase: [UInt8](passphrase.utf8),
               salt: salt, n: 16384, r: 8, p: 1, length: 32)
    }

    // MARK: Frames

    /// Pack text into an MWK1 frame. A nil passphrase is a
    /// plain frame; an empty one is refused, exactly as the
    /// original refuses it — plain is a choice, not an
    /// accident of an untouched field.
    static func pack(
        text: String, passphrase: String?
    ) throws -> Data {
        let payload = [UInt8](text.utf8)
        guard payload.count <= maxText else {
            throw MawkError.tooLong
        }
        if let passphrase, passphrase.isEmpty {
            throw MawkError.emptyPassphrase
        }
        let flags: UInt8 = passphrase == nil ? 0 : 1
        var body = payload
        if let passphrase {
            let salt = (0..<16).map { _ in UInt8.random(in: 0...255) }
            let nonce = (0..<12).map { _ in UInt8.random(in: 0...255) }
            body = salt + nonce
                + (try seal(payload: payload, passphrase: passphrase,
                            salt: salt, nonce: nonce,
                            size: payload.count + 44))
        }
        let size = body.count
        var frame = magic + [1, flags]
        frame.append(UInt8((size >> 24) & 0xFF))
        frame.append(UInt8((size >> 16) & 0xFF))
        frame.append(UInt8((size >> 8) & 0xFF))
        frame.append(UInt8(size & 0xFF))
        // The header written here is byte-identical to the
        // one seal() rebuilt from `size` for its associated
        // data — the seal authenticates this exact header.
        frame += body
        let crc = crc32(frame)
        frame.append(UInt8((crc >> 24) & 0xFF))
        frame.append(UInt8((crc >> 16) & 0xFF))
        frame.append(UInt8((crc >> 8) & 0xFF))
        frame.append(UInt8(crc & 0xFF))
        return Data(frame)
    }

    /// The ChaCha20-Poly1305 seal over a payload, returning
    /// ciphertext + tag (the caller prefixes salt + nonce).
    /// `size` is the frame's final payload size, needed to
    /// rebuild the header that serves as associated data.
    private static func seal(
        payload: [UInt8], passphrase: String,
        salt: [UInt8], nonce: [UInt8], size: Int
    ) throws -> [UInt8] {
        var header = magic + [1, 1]
        header.append(UInt8((size >> 24) & 0xFF))
        header.append(UInt8((size >> 16) & 0xFF))
        header.append(UInt8((size >> 8) & 0xFF))
        header.append(UInt8(size & 0xFF))
        let key = SymmetricKey(
            data: Mawk.key(passphrase: passphrase, salt: salt))
        do {
            let box = try ChaChaPoly.seal(
                Data(payload), using: key,
                nonce: try ChaChaPoly.Nonce(data: Data(nonce)),
                authenticating: Data(header))
            return [UInt8](box.ciphertext) + [UInt8](box.tag)
        } catch {
            throw MawkError.authFailed
        }
    }

    /// Whether a frame is a sealed one (its flags byte),
    /// for the listener's "this one needs a passphrase".
    static func isSealed(frame: Data) -> Bool {
        frame.count >= headerSize && frame[5] == 1
    }

    /// Open a frame back into text. Every check the
    /// original makes, in its order: shape, then the CRC,
    /// then (for sealed frames) authentication — text is
    /// returned only after authentication succeeds.
    static func unpack(
        frame: Data, passphrase: String?
    ) throws -> String {
        let bytes = [UInt8](frame)
        guard bytes.count >= headerSize + 4 else {
            throw MawkError.truncated
        }
        guard Array(bytes[0..<4]) == magic,
              bytes[4] == 1,
              bytes[5] == 0 || bytes[5] == 1
        else { throw MawkError.unsupported }
        let flags = bytes[5]
        let size = (Int(bytes[6]) << 24) | (Int(bytes[7]) << 16)
            | (Int(bytes[8]) << 8) | Int(bytes[9])
        guard size <= maxText + (flags == 1 ? 44 : 0) else {
            throw MawkError.unsupported
        }
        guard bytes.count == headerSize + size + 4 else {
            throw MawkError.badLength
        }
        let carried = (UInt32(bytes[bytes.count - 4]) << 24)
            | (UInt32(bytes[bytes.count - 3]) << 16)
            | (UInt32(bytes[bytes.count - 2]) << 8)
            | UInt32(bytes[bytes.count - 1])
        guard crc32(Array(bytes.dropLast(4))) == carried else {
            throw MawkError.checksum
        }
        var payload = Array(bytes[headerSize..<(headerSize + size)])
        if flags == 1 {
            guard payload.count >= 44 else {
                throw MawkError.truncated
            }
            guard let passphrase, !passphrase.isEmpty else {
                throw MawkError.needsPassphrase
            }
            let salt = Array(payload[0..<16])
            let nonce = Array(payload[16..<28])
            let sealed = Array(payload[28...])
            let key = SymmetricKey(
                data: Mawk.key(passphrase: passphrase, salt: salt))
            do {
                let box = try ChaChaPoly.SealedBox(
                    nonce: try ChaChaPoly.Nonce(data: Data(nonce)),
                    ciphertext: Data(sealed.dropLast(16)),
                    tag: Data(sealed.suffix(16)))
                let opened = try ChaChaPoly.open(
                    box, using: key,
                    authenticating: Data(bytes[0..<headerSize]))
                payload = [UInt8](opened)
            } catch {
                throw MawkError.authFailed
            }
        }
        guard let text = String(bytes: payload, encoding: .utf8)
        else { throw MawkError.badText }
        return text
    }

    // MARK: The modem

    /// Dibits of a byte string, most significant first —
    /// the original's symbol order.
    static func dibits(of bytes: [UInt8]) -> [Int] {
        var out: [Int] = []
        out.reserveCapacity(bytes.count * 4)
        for byte in bytes {
            out.append(Int(byte >> 6) & 3)
            out.append(Int(byte >> 4) & 3)
            out.append(Int(byte >> 2) & 3)
            out.append(Int(byte) & 3)
        }
        return out
    }

    /// One symbol's worth of samples: a pure tone starting
    /// at phase zero (the original's table, exactly).
    private static func toneSamples(dibit: Int) -> [Float] {
        let f = tones[dibit]
        return (0..<samplesPerSymbol).map { i in
            Float(sin(2 * Double.pi * f * Double(i)
                        / Double(rate)) * 0.65)
        }
    }

    private static let toneTable: [[Float]] =
        (0..<4).map { toneSamples(dibit: $0) }

    /// A whole transmission: 100 ms of silence, the stem,
    /// the frame, 100 ms of silence.
    static func modulate(frame: Data) -> [Float] {
        let silence = [Float](repeating: 0, count: rate / 10)
        var out = silence
        for dibit in dibits(of: stem + [UInt8](frame)) {
            out += toneTable[dibit]
        }
        out += silence
        return out
    }

    /// A radix-2 FFT over doubles (forward or inverse),
    /// here for the stem correlation — the same FFT
    /// cross-correlation the original demodulates with.
    private static func fft(
        re: inout [Double], im: inout [Double], inverse: Bool
    ) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var length = 2
        while length <= n {
            let sweep = inverse ? 1.0 : -1.0
            let angle = 2 * Double.pi / Double(length) * sweep
            let wr = cos(angle), wi = sin(angle)
            for i in stride(from: 0, to: n, by: length) {
                var cwr = 1.0, cwi = 0.0
                for k in 0..<(length / 2) {
                    let a = i + k, b = i + k + length / 2
                    let vr = re[b] * cwr - im[b] * cwi
                    let vi = re[b] * cwi + im[b] * cwr
                    re[b] = re[a] - vr
                    im[b] = im[a] - vi
                    re[a] += vr
                    im[a] += vi
                    let next = cwr * wr - cwi * wi
                    cwi = cwr * wi + cwi * wr
                    cwr = next
                }
            }
            length <<= 1
        }
        if inverse {
            for i in 0..<n {
                re[i] /= Double(n)
                im[i] /= Double(n)
            }
        }
    }

    /// The four tone magnitudes of one symbol window —
    /// a Goertzel reading at exactly the DFT bins the
    /// original's FFT picks (each window holds whole
    /// cycles of every tone, so the two agree).
    private static func toneMagnitudes(
        samples: [Float], at start: Int
    ) -> [Double] {
        tones.map { f in
            let k = f * Double(samplesPerSymbol) / Double(rate)
            let coeff = 2 * cos(2 * Double.pi * k
                                / Double(samplesPerSymbol))
            var s1 = 0.0, s2 = 0.0
            for i in 0..<samplesPerSymbol {
                let s = Double(samples[start + i])
                    + coeff * s1 - s2
                s2 = s1
                s1 = s
            }
            return (s1 * s1 + s2 * s2 - coeff * s1 * s2)
                .squareRoot()
        }
    }

    /// Find a frame in raw 48 kHz samples. Mirrors the
    /// original: FFT cross-correlation locates the stem
    /// among the twelve strongest candidate starts in the
    /// first two seconds; each candidate's symbols are
    /// read by strongest tone; a candidate is accepted
    /// only when the frame parses and its CRC holds.
    static func demodulate(samples: [Float]) throws -> Data {
        let minimum = (stem.count + headerSize + 4) * 4 * samplesPerSymbol
        guard samples.count >= minimum else {
            throw MawkError.tooShort
        }
        var template: [Float] = []
        for dibit in dibits(of: stem) {
            template += toneTable[dibit]
        }
        let searchCount = min(
            samples.count, 2 * rate + template.count)
        var size = 1
        while size < searchCount + template.count - 1 {
            size <<= 1
        }
        var fre = [Double](repeating: 0, count: size)
        var fim = [Double](repeating: 0, count: size)
        for i in 0..<searchCount {
            fre[i] = Double(samples[i])
        }
        fft(re: &fre, im: &fim, inverse: false)
        var gre = [Double](repeating: 0, count: size)
        var gim = [Double](repeating: 0, count: size)
        for i in 0..<template.count {
            gre[i] = Double(template[template.count - 1 - i])
        }
        fft(re: &gre, im: &gim, inverse: false)
        for i in 0..<size {
            let pr = fre[i] * gre[i] - fim[i] * gim[i]
            let pi = fre[i] * gim[i] + fim[i] * gre[i]
            fre[i] = pr
            fim[i] = pi
        }
        fft(re: &fre, im: &fim, inverse: true)
        // fre[s] now scores a stem starting at sample s.
        var scores = [Double](repeating: -Double.infinity,
                              count: searchCount)
        for s in 0..<searchCount {
            scores[s] = fre[s + template.count - 1]
        }
        var candidates: [Int] = []
        for _ in 0..<12 {
            var best = -Double.infinity
            var bestAt = -1
            for s in 0..<searchCount where scores[s] > best {
                best = scores[s]
                bestAt = s
            }
            if bestAt < 0 { break }
            candidates.append(bestAt)
            let lo = max(0, bestAt - samplesPerSymbol / 2)
            let hi = min(searchCount - 1,
                         bestAt + samplesPerSymbol / 2)
            for s in lo...hi { scores[s] = -Double.infinity }
        }
        let maxSymbols = (stem.count + maxFrame
            + headerSize + 4) * 4
        for start in candidates {
            let available = (samples.count - start)
                / samplesPerSymbol
            let count = min(available, maxSymbols)
            guard count >= (stem.count + headerSize) * 4
            else { continue }
            var dibits: [Int] = []
            dibits.reserveCapacity(count)
            for s in 0..<count {
                let at = start + s * samplesPerSymbol
                let mags = toneMagnitudes(
                    samples: samples, at: at)
                var best = 0
                for t in 1..<4 where mags[t] > mags[best] {
                    best = t
                }
                dibits.append(best)
            }
            var raw: [UInt8] = []
            let whole = count / 4 * 4
            for i in stride(from: 0, to: whole, by: 4) {
                raw.append(UInt8((dibits[i] << 6)
                    | (dibits[i + 1] << 4)
                    | (dibits[i + 2] << 2)
                    | dibits[i + 3]))
            }
            guard raw.count >= stem.count + headerSize,
                  Array(raw[0..<stem.count]) == stem,
                  Array(raw[stem.count..<(stem.count + 4)])
                    == magic
            else { continue }
            let frame = Array(raw[stem.count...])
            let fsize = (Int(frame[6]) << 24)
                | (Int(frame[7]) << 16)
                | (Int(frame[8]) << 8) | Int(frame[9])
            guard frame[4] == 1,
                  frame[5] == 0 || frame[5] == 1,
                  fsize <= maxFrame,
                  frame.count >= headerSize + fsize + 4
            else { continue }
            let whole2 = Array(
                frame[0..<(headerSize + fsize + 4)])
            let carried = (UInt32(whole2[whole2.count - 4]) << 24)
                | (UInt32(whole2[whole2.count - 3]) << 16)
                | (UInt32(whole2[whole2.count - 2]) << 8)
                | UInt32(whole2[whole2.count - 1])
            if crc32(Array(whole2.dropLast(4))) == carried {
                return Data(whole2)
            }
        }
        throw MawkError.noSignal
    }

    // MARK: WAV

    /// The original's export shape: 48 kHz mono 16-bit
    /// PCM WAV, samples clipped and scaled by 32767.
    static func wavData(samples: [Float]) -> Data {
        var out = Data()
        let pcmCount = samples.count * 2
        func tag(_ s: String) { out += Data(s.utf8) }
        func u32(_ v: UInt32) {
            out += Data([UInt8(v & 0xFF),
                         UInt8((v >> 8) & 0xFF),
                         UInt8((v >> 16) & 0xFF),
                         UInt8((v >> 24) & 0xFF)])
        }
        func u16(_ v: UInt16) {
            out += Data([UInt8(v & 0xFF),
                         UInt8((v >> 8) & 0xFF)])
        }
        tag("RIFF")
        u32(UInt32(36 + pcmCount))
        tag("WAVE")
        tag("fmt ")
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(rate))
        u32(UInt32(rate * 2))
        u16(2)
        u16(16)
        tag("data")
        u32(UInt32(pcmCount))
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            let v = Int16(clipped * 32767)
            out += Data([UInt8(truncatingIfNeeded: v),
                         UInt8(truncatingIfNeeded: v >> 8)])
        }
        return out
    }

    /// Read a WAV file's samples, resampled to 48 kHz.
    /// PCM16 only (the original's exports and every WAV
    /// the house writes); stereo folds to mono.
    static func samples(fromWAV data: Data) throws -> [Float] {
        let bytes = [UInt8](data)
        guard bytes.count >= 44,
              Array(bytes[0..<4]) == [UInt8]("RIFF".utf8),
              Array(bytes[8..<12]) == [UInt8]("WAVE".utf8)
        else { throw MawkError.badAudioFile }
        func u32at(_ o: Int) -> Int {
            Int(bytes[o]) | (Int(bytes[o + 1]) << 8)
                | (Int(bytes[o + 2]) << 16)
                | (Int(bytes[o + 3]) << 24)
        }
        func u16at(_ o: Int) -> Int {
            Int(bytes[o]) | (Int(bytes[o + 1]) << 8)
        }
        var channels = 1, fileRate = rate, bits = 16
        var pcm: [Float] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let kind = Array(bytes[offset..<(offset + 4)])
            let size = u32at(offset + 4)
            let body = offset + 8
            guard body + size <= bytes.count + 1
            else { break }
            if kind == [UInt8]("fmt ".utf8) {
                guard u16at(body) == 1 else {
                    throw MawkError.badAudioFile
                }
                channels = u16at(body + 2)
                fileRate = u32at(body + 4)
                bits = u16at(body + 14)
                guard bits == 16, channels == 1 || channels == 2
                else { throw MawkError.badAudioFile }
            } else if kind == [UInt8]("data".utf8) {
                let frames = size / (2 * channels)
                pcm.reserveCapacity(frames)
                for f in 0..<frames {
                    var sum = 0.0
                    for c in 0..<channels {
                        let o = body + (f * channels + c) * 2
                        let v = Int16(bitPattern:
                            UInt16(bytes[o])
                            | (UInt16(bytes[o + 1]) << 8))
                        sum += Double(v) / 32768.0
                    }
                    pcm.append(Float(sum / Double(channels)))
                }
            }
            offset = body + size + (size % 2)
        }
        guard !pcm.isEmpty else { throw MawkError.badAudioFile }
        if fileRate == rate { return pcm }
        // Linear resample to the modem's rate.
        let ratio = Double(fileRate) / Double(rate)
        let count = Int(Double(pcm.count) / ratio)
        return (0..<count).map { i in
            let at = Double(i) * ratio
            let lo = Int(at)
            let hi = min(lo + 1, pcm.count - 1)
            let frac = Float(at - Double(lo))
            return pcm[lo] * (1 - frac) + pcm[hi] * frac
        }
    }
}

// MARK: - One heard message

struct MawkHeard: Identifiable {
    let id = UUID()
    let frame: Data
    var text: String? = nil
    var note: String? = nil
    let at: Date

    var sealed: Bool { Mawk.isSealed(frame: frame) }
}

// MARK: - The live center

/// Plays frames through the speaker and listens on the
/// microphone for them. One shared center, so the sheet,
/// and the console's mawk verb read the same state.
final class MawkCenter: ObservableObject {
    static let shared = MawkCenter()

    @Published var playing = false
    @Published var progress = 0.0
    @Published var listening = false
    @Published var status = L("Idle.")
    @Published var heard: [MawkHeard] = []

    /// The sheet's passphrase field, mirrored here so a
    /// sealed frame heard live can be opened on arrival
    /// and retried later. Never stored, never logged.
    var passphrase: String?

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playTimer: Timer?
    private var playStarted = Date()
    private var playDuration = 0.0

    private var listenEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let sampleLock = NSLock()
    private var pending: [Float] = []
    private var lastAttemptCount = 0
    private var decoding = false
    private var listenTimer: Timer?

    // MARK: Playing

    /// EMCON's word on singing: refused at Bravo and
    /// above — a transmission is a transmission.
    static var playRefusal: String? {
        EmconCondition.current < .bravo
            ? nil
            : String(format: L("EMCON %@ refuses: the mawk is a transmission."),
                     EmconCondition.current.name)
    }

    /// EMCON's word on listening: refused at Alpha alone
    /// — the ear is receive-only (the wardrive rule).
    static var listenRefusal: String? {
        EmconCondition.current != .alpha
            ? nil
            : String(format: L("EMCON %@ refuses: total silence."),
                     EmconCondition.current.name)
    }

    @discardableResult
    func play(frame: Data) -> String? {
        if let refusal = Self.playRefusal { return refusal }
        stopListening()
        stopPlaying()
        let samples = Mawk.modulate(frame: frame)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(Mawk.rate),
            channels: 1)!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count))
        else { return L("The sound would not build.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(
                from: src.baseAddress!, count: samples.count)
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode,
                           format: format)
            try engine.start()
            self.engine = engine
            self.player = player
            playDuration = Double(samples.count)
                / Double(Mawk.rate)
            playStarted = Date()
            playing = true
            progress = 0
            status = L("Singing…")
            player.scheduleBuffer(
                buffer, at: nil, options: [],
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.finishPlaying()
                }
            }
            player.play()
            playTimer = Timer.scheduledTimer(
                withTimeInterval: 0.1, repeats: true
            ) { [weak self] _ in
                guard let self, self.playing else { return }
                self.progress = min(1, Date().timeIntervalSince(
                    self.playStarted) / self.playDuration)
            }
            Journal.log("mawk", "play",
                        "\(frame.count) bytes on the air")
            return nil
        } catch {
            return L("The speaker would not open.")
        }
    }

    func stopPlaying() {
        playTimer?.invalidate()
        playTimer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        if playing {
            playing = false
            progress = 0
            status = L("Stopped.")
        }
    }

    private func finishPlaying() {
        playTimer?.invalidate()
        playTimer = nil
        player = nil
        engine = nil
        playing = false
        progress = 0
        status = L("Sung. The room heard it, if a room was listening.")
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Listening

    @discardableResult
    func startListening() -> String? {
        if let refusal = Self.listenRefusal { return refusal }
        if listening { return nil }
        stopPlaying()
        AVAudioSession.sharedInstance()
            .requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.beginCapture()
                    } else {
                        self?.status = L("The microphone is not permitted — iOS Settings holds the switch.")
                    }
                }
            }
        status = L("Asking for the microphone…")
        return nil
    }

    private func beginCapture() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let native = input.outputFormat(forBus: 0)
            let target = AVAudioFormat(
                standardFormatWithSampleRate: Double(Mawk.rate),
                channels: 1)!
            converter = AVAudioConverter(from: native, to: target)
            input.installTap(
                onBus: 0, bufferSize: 4096,
                format: native
            ) { [weak self] buffer, _ in
                self?.absorb(buffer)
            }
            try engine.start()
            listenEngine = engine
            sampleLock.lock()
            pending = []
            sampleLock.unlock()
            lastAttemptCount = 0
            listening = true
            status = L("Listening — hold the sound near the phone.")
            listenTimer = Timer.scheduledTimer(
                withTimeInterval: 0.5, repeats: true
            ) { [weak self] _ in
                self?.attemptDecode()
            }
            Journal.log("mawk", "listen", "the ear is open")
        } catch {
            status = L("The microphone would not open.")
        }
    }

    private func absorb(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let target = AVAudioFormat(
            standardFormatWithSampleRate: Double(Mawk.rate),
            channels: 1)!
        let ratio = Double(Mawk.rate) / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(
            pcmFormat: target, frameCapacity: capacity)
        else { return }
        var consumed = false
        var failure: NSError?
        converter.convert(to: out, error: &failure) { _, flag in
            if consumed {
                flag.pointee = .noDataNow
                return nil
            }
            consumed = true
            flag.pointee = .haveData
            return buffer
        }
        guard failure == nil,
              let channel = out.floatChannelData?[0]
        else { return }
        let frames = Int(out.frameLength)
        sampleLock.lock()
        pending += [Float](UnsafeBufferPointer(
            start: channel, count: frames))
        // A mailbox, not a vault: keep the newest ~100 s.
        let cap = 100 * Mawk.rate
        if pending.count > cap {
            pending.removeFirst(pending.count - cap)
        }
        sampleLock.unlock()
    }

    private func attemptDecode() {
        sampleLock.lock()
        let count = pending.count
        sampleLock.unlock()
        guard listening, !decoding,
              count >= 24000,
              count - lastAttemptCount >= 4800
        else { return }
        lastAttemptCount = count
        sampleLock.lock()
        var window = pending
        sampleLock.unlock()
        // The demodulator searches a transmission's first
        // two seconds: feed it the newest stretch so a
        // fresh stem is inside its window.
        let keep = 6 * Mawk.rate
        if window.count > keep {
            window = Array(window.suffix(keep))
        }
        decoding = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let frame = try? Mawk.demodulate(samples: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.decoding = false
                if let frame {
                    self.sampleLock.lock()
                    self.pending = []
                    self.sampleLock.unlock()
                    self.lastAttemptCount = 0
                    self.receive(frame: frame)
                }
            }
        }
    }

    private func receive(frame: Data) {
        var entry = MawkHeard(frame: frame, at: Date())
        do {
            entry.text = try Mawk.unpack(
                frame: frame,
                passphrase: Mawk.isSealed(frame: frame)
                    ? passphrase : nil)
            status = L("Heard — a mawk, whole.")
        } catch let error as MawkError {
            entry.note = error.line
            status = error == .needsPassphrase
                || error == .authFailed
                ? L("Heard — a sealed mawk. It waits for its passphrase.")
                : error.line
        } catch {
            entry.note = L("Heard — but it would not open.")
            status = entry.note!
        }
        heard.insert(entry, at: 0)
        Haptics.success()
        Journal.log("mawk", "heard",
                    "\(frame.count) bytes off the air")
    }

    /// Re-try a heard sealed frame with the current
    /// passphrase (the sheet calls this after typing).
    func retry(_ entry: MawkHeard) {
        guard let at = heard.firstIndex(where: {
            $0.id == entry.id
        }) else { return }
        do {
            heard[at].text = try Mawk.unpack(
                frame: entry.frame, passphrase: passphrase)
            heard[at].note = nil
            status = L("Opened.")
        } catch let error as MawkError {
            heard[at].note = error.line
            status = error.line
        } catch {
            heard[at].note = L("It would not open.")
        }
    }

    func forgetHeard() {
        heard = []
        status = L("The mailbox is empty.")
    }

    func stopListening() {
        listenTimer?.invalidate()
        listenTimer = nil
        listenEngine?.inputNode.removeTap(onBus: 0)
        listenEngine?.stop()
        listenEngine = nil
        converter = nil
        if listening {
            listening = false
            status = L("The ear is shut.")
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }
}

import UniformTypeIdentifiers

// MARK: - The friendly sheet

/// MAWKBOX as a room: type, seal it if you like, play it
/// as sound; listen, and what the room sings back lands
/// in the mailbox below. Raised from the Send tab — the
/// mouth's house — because a song is a send.
struct MawkView: View {
    @ObservedObject private var center = MawkCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sealed = false
    @State private var pass = ""
    @State private var shareItem: ShareItem?
    @State private var importing = false
    @State private var note: String?

    private var draftBytes: Int { draft.utf8.count }
    private var overLimit: Bool { draftBytes > Mawk.maxText }
    private var passphrase: String? {
        sealed ? pass : nil
    }
    private var framedBytes: Int {
        10 + draftBytes + (sealed ? 44 : 0) + 4
    }
    private var airSeconds: Double {
        Double((8 + framedBytes) * 4 * Mawk.samplesPerSymbol) / Double(Mawk.rate) + 0.2
    }

    private func packDraft() -> Data? {
        do {
            return try Mawk.pack(text: draft,
                                 passphrase: passphrase)
        } catch let error as MawkError {
            note = error.line
            return nil
        } catch {
            note = L("That message would not pack.")
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Say it as sound")),
                        footer: Text(L("Four tones at 200 baud — the lab's mawkbox format, sung by the speaker. Hold the phones near each other; a quiet room carries best."))) {
                    TextField(L("Message"), text: $draft,
                              axis: .vertical)
                        .lineLimit(3...8)
                    HStack {
                        Text(String(format: L("%d of 4096 bytes"),
                                    draftBytes))
                            .font(.caption)
                            .foregroundStyle(
                                overLimit ? .red : .secondary)
                        Spacer()
                        Text(String(format: L("about %.1f s on the air"),
                                    airSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle(L("Seal it with a passphrase"),
                           isOn: $sealed)
                    if sealed {
                        SecureField(L("Passphrase"), text: $pass)
                            .textContentType(.password)
                    }
                    if center.playing {
                        ProgressView(value: center.progress)
                        Button(role: .destructive) {
                            Haptics.tap()
                            center.stopPlaying()
                        } label: {
                            Label(L("Stop"), systemImage: "stop.fill")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            if let frame = packDraft() {
                                note = center.play(frame: frame)
                            }
                        } label: {
                            Label(L("Play it as sound"),
                                  systemImage: "waveform")
                        }
                        .disabled(draft.isEmpty || overLimit
                                  || (sealed && pass.isEmpty)
                                  || MawkCenter.playRefusal != nil)
                    }
                    if let refusal = MawkCenter.playRefusal {
                        Text(refusal)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section(header: Text(L("Hear it")),
                        footer: Text(L("A sealed mawk opens with the passphrase above. The mailbox keeps what it hears until you clear it."))) {
                    if center.listening {
                        Button(role: .destructive) {
                            Haptics.tap()
                            center.stopListening()
                        } label: {
                            Label(L("Stop listening"),
                                  systemImage: "mic.slash")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            note = center.startListening()
                        } label: {
                            Label(L("Listen for a mawk"),
                                  systemImage: "mic")
                        }
                        .disabled(MawkCenter.listenRefusal != nil)
                    }
                    if let refusal = MawkCenter.listenRefusal {
                        Text(refusal)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(center.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(center.heard) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            if let text = entry.text {
                                Text(text)
                                HStack(spacing: 16) {
                                    Button(L("Copy")) {
                                        UIPasteboard.general.string = text
                                        Haptics.tap()
                                    }
                                    .font(.caption)
                                    Button(L("Share")) {
                                        shareItem = ShareItem(
                                            items: [text])
                                    }
                                    .font(.caption)
                                }
                            } else {
                                Text(entry.note
                                     ?? L("Sealed — it would not open."))
                                    .foregroundStyle(.secondary)
                                if sealed && !pass.isEmpty {
                                    Button(L("Try the passphrase")) {
                                        center.passphrase = pass
                                        center.retry(entry)
                                    }
                                    .font(.caption)
                                }
                            }
                            Text(entry.at, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    if !center.heard.isEmpty {
                        Button(L("Clear the mailbox"),
                               role: .destructive) {
                            center.forgetHeard()
                        }
                    }
                }

                Section(header: Text(L("Files")),
                        footer: Text(L("The same files the desktop mawkbox reads and writes — a message as a WAV, or the bare frame as a .mawkbox. Import a WAV or a frame and it lands in the mailbox."))) {
                    Button {
                        Haptics.tap()
                        if let frame = packDraft() {
                            let url = FileManager.default
                                .temporaryDirectory
                                .appendingPathComponent(
                                    "mawk.wav")
                            try? Mawk.wavData(
                                samples: Mawk.modulate(frame: frame)
                            ).write(to: url)
                            shareItem = ShareItem(items: [url])
                        }
                    } label: {
                        Label(L("Share this message as a WAV"),
                              systemImage: "waveform.badge.plus")
                    }
                    .disabled(draft.isEmpty || overLimit
                              || (sealed && pass.isEmpty))
                    Button {
                        Haptics.tap()
                        if let frame = packDraft() {
                            let url = FileManager.default
                                .temporaryDirectory
                                .appendingPathComponent(
                                    "message.mawkbox")
                            try? frame.write(to: url)
                            shareItem = ShareItem(items: [url])
                        }
                    } label: {
                        Label(L("Share the frame file"),
                              systemImage: "doc")
                    }
                    .disabled(draft.isEmpty || overLimit
                              || (sealed && pass.isEmpty))
                    Button {
                        Haptics.tap()
                        importing = true
                    } label: {
                        Label(L("Import a WAV or frame file"),
                              systemImage: "square.and.arrow.down")
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L("Mawkbox"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [.wav, .audio, .data]
            ) { result in
                guard case .success(let url) = result,
                      url.startAccessingSecurityScopedResource(),
                      let data = try? Data(contentsOf: url)
                else {
                    note = L("That file would not come.")
                    return
                }
                url.stopAccessingSecurityScopedResource()
                importFile(data)
            }
            .onChange(of: pass) { _, _ in
                center.passphrase = sealed && !pass.isEmpty
                    ? pass : nil
            }
            .onChange(of: sealed) { _, _ in
                center.passphrase = sealed && !pass.isEmpty
                    ? pass : nil
            }
        }
    }

    private func importFile(_ data: Data) {
        do {
            let frame: Data
            if data.count >= 4,
               [UInt8](data.prefix(4)) == [0x4d, 0x57, 0x4b, 0x31] {
                frame = data
            } else {
                frame = try Mawk.demodulate(
                    samples: try Mawk.samples(fromWAV: data))
            }
            let text = try Mawk.unpack(
                frame: frame,
                passphrase: Mawk.isSealed(frame: frame)
                    ? passphrase : nil)
            center.heard.insert(
                MawkHeard(frame: frame, text: text, at: Date()),
                at: 0)
            note = L("Imported — it is in the mailbox.")
            Haptics.success()
        } catch let error as MawkError {
            note = error.line
        } catch {
            note = L("That file held no mawk this house can open.")
        }
    }
}
