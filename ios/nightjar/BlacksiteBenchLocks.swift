import Foundation
import CryptoKit
import Security

/// Wave eight: locks & ciphers — a
/// workbench, not a wire. The verbs
/// work over material the operator
/// brings: key files, certificates,
/// captured blobs, strings on the
/// clipboard of the argument. Nothing
/// here cracks anything: no password
/// guessing against a live door, no
/// oracle games, no padding attacks —
/// the math is the bench's own, run
/// in the open on the operator's own
/// material, and every number is
/// computed exactly or the verb says
/// why it cannot be. The operator's
/// secrets (a passphrase typed into
/// passprobe, a TOTP seed) are used
/// in place and never printed back,
/// never logged, never stored.
///
/// Incumbent audit (before a line was
/// written): `certprobe` (Wave 1) reads
/// a LIVE host's papers — x509probe is
/// its file twin and shares the house
/// DER walkers. `jwtdeep` stays the JWT
/// string reader; nothing in this wave
/// duplicates it. `sshkey` is the house
/// SSH identity hand (make/forget/show
/// the operator's own identity) — not
/// a census, so sshkeydeep stands as
/// the host/file key census beside it.
/// `tlsgrade` sweeps TLS versions on a
/// live host; tlscensus is the deeper
/// cut of the same cloth — cipher
/// families by representative suite,
/// the negotiated 1.3 suite, and the
/// papers chained in.
///
/// Verification (before the Swift
/// existed, a Python mirror of every
/// algorithm ran 176 checks green):
/// digests against FIPS 180 / RFC 1321
/// literals; base32 RFC 4648; base58
/// the Bitcoin-wiki vectors; HOTP
/// RFC 4226, TOTP RFC 6238; PBKDF2
/// RFC 6070 (SHA-1) and the published
/// SHA-256 / SHA-512 vectors; AES
/// FIPS-197 App. B/C (128/192/256,
/// encrypt and decrypt), the App. A
/// key schedule, SP 800-38A ECB/CBC/
/// CTR; the S-box itself derived from
/// GF(2^8) arithmetic, not copied;
/// the bignum fuzzed 360 rounds
/// against Python integers; RSA checks
/// against sympy-built close-prime and
/// shared-factor moduli; ECC expansion
/// against openssl-issued points; the
/// DER walk against openssl fixtures
/// (subject, issuer, serial, validity,
/// SANs all matched); the PGP walk
/// against `gpg --list-packets` and
/// its fingerprint; SSH blob parsing
/// and SHA256 fingerprints against
/// ssh-keygen's own; the cipher-suite
/// table against its name parser for
/// every row.

/// The connection box the TLS knocks
/// hand to SecureTransport's C
/// callbacks (the Wave 3 pattern,
/// literals and all: errSSLWouldBlock
/// -9803, errSSLClosedAbort -9804,
/// errSSLClosedGraceful -9806,
/// errSSLServerAuthCompleted -9841 —
/// the numbers ride as literals so
/// nothing leans on a spelling the
/// importer may keep).
final class LockTLSBox {
    let fd: Int32
    var strikes = 0
    init(fd: Int32) { self.fd = fd }
}

func blacksiteLockTLSRead(
    connection: SSLConnectionRef,
    data: UnsafeMutableRawPointer,
    length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<LockTLSBox>
        .fromOpaque(connection)
        .takeUnretainedValue()
    let wanted = length.pointee
    let got = recv(box.fd, data,
                   wanted, 0)
    if got > 0 {
        length.pointee = got
        box.strikes = 0
        return got == wanted ? 0 : -9803
    }
    if got == 0 {
        length.pointee = 0
        return -9806
    }
    box.strikes += 1
    length.pointee = 0
    if box.strikes > 10 {
        return -9804
    }
    return -9803
}

func blacksiteLockTLSWrite(
    connection: SSLConnectionRef,
    data: UnsafeRawPointer,
    length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<LockTLSBox>
        .fromOpaque(connection)
        .takeUnretainedValue()
    let total = length.pointee
    var sent = 0
    while sent < total {
        let n = send(box.fd,
                     data.advanced(
                        by: sent),
                     total - sent, 0)
        if n <= 0 {
            length.pointee = sent
            return -9804
        }
        sent += n
    }
    length.pointee = sent
    return 0
}

// MARK: - LockBig: exact bignum

/// A small exact bignum — 32-bit
/// limbs, little-endian, normalised
/// (zero is the empty list). Only the
/// operations the RSA and ECC readers
/// need: add, subtract, multiply,
/// Knuth-D division, gcd, integer
/// square root, modular power, and a
/// fast small-modulus pass for trial
/// division. Fuzz-verified against
/// Python integers before it shipped.
struct LockBig: Comparable {
    private(set) var limbs: [UInt32]

    init() { limbs = [] }

    init(raw: [UInt32]) {
        limbs = LockBig.normalised(raw)
    }

    init(_ small: UInt32) {
        limbs = small == 0 ? [] : [small]
    }

    static func normalised(
        _ raw: [UInt32]) -> [UInt32] {
        var a = raw
        while a.last == 0 { a.removeLast() }
        return a
    }

    /// Big-endian bytes to limbs:
    /// walk from the end in 4-byte
    /// groups (the last group may be
    /// short), appending the least
    /// significant limb first.
    static func fromBytes(_ bytes: [UInt8])
        -> LockBig {
        var limbs: [UInt32] = []
        var i = bytes.count
        while i > 0 {
            let lo = max(0, i - 4)
            var limb: UInt32 = 0
            for k in lo..<i {
                limb = (limb << 8)
                    | UInt32(bytes[k])
            }
            limbs.append(limb)
            i = lo
        }
        return LockBig(raw: limbs)
    }

    func toBytes() -> [UInt8] {
        var out: [UInt8] = []
        for limb in limbs.reversed() {
            out.append(UInt8(
                (limb >> 24) & 0xFF))
            out.append(UInt8(
                (limb >> 16) & 0xFF))
            out.append(UInt8(
                (limb >> 8) & 0xFF))
            out.append(UInt8(limb & 0xFF))
        }
        while out.first == 0, out.count > 1 {
            out.removeFirst()
        }
        return limbs.isEmpty ? [] : out
    }

    var isZero: Bool { limbs.isEmpty }

    var bitLength: Int {
        guard let top = limbs.last
        else { return 0 }
        return (limbs.count - 1) * 32
            + (32 - top.leadingZeroBitCount)
    }

    static func == (a: LockBig, b: LockBig)
        -> Bool {
        a.limbs == b.limbs
    }

    static func < (a: LockBig, b: LockBig)
        -> Bool {
        if a.limbs.count != b.limbs.count {
            return a.limbs.count
                < b.limbs.count
        }
        var i = a.limbs.count - 1
        while i >= 0 {
            if a.limbs[i] != b.limbs[i] {
                return a.limbs[i] < b.limbs[i]
            }
            i -= 1
        }
        return false
    }

    static func + (a: LockBig, b: LockBig)
        -> LockBig {
        var out: [UInt32] = []
        var carry: UInt64 = 0
        let n = max(a.limbs.count,
                    b.limbs.count)
        for i in 0..<n {
            var s = carry
            if i < a.limbs.count {
                s += UInt64(a.limbs[i])
            }
            if i < b.limbs.count {
                s += UInt64(b.limbs[i])
            }
            out.append(UInt32(
                s & 0xFFFF_FFFF))
            carry = s >> 32
        }
        if carry > 0 {
            out.append(UInt32(carry))
        }
        return LockBig(raw: out)
    }

    /// Subtract; the caller owes a >= b
    /// (an underflow reads as zero —
    /// every call site in this file is
    /// ordered by construction, and the
    /// arithmetic was fuzz-proven in
    /// that form).
    static func - (a: LockBig, b: LockBig)
        -> LockBig {
        if a < b { return LockBig() }
        var out: [UInt32] = []
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            var d = Int64(a.limbs[i])
                - borrow
            if i < b.limbs.count {
                d -= Int64(b.limbs[i])
            }
            if d < 0 {
                d += 1 << 32
                borrow = 1
            } else {
                borrow = 0
            }
            out.append(UInt32(d))
        }
        return LockBig(raw: out)
    }

    static func * (a: LockBig, b: LockBig)
        -> LockBig {
        if a.isZero || b.isZero {
            return LockBig()
        }
        var out = [UInt32](
            repeating: 0,
            count: a.limbs.count
                + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            let x = UInt64(a.limbs[i])
            for j in 0..<b.limbs.count {
                let t = UInt64(out[i + j])
                    + x * UInt64(b.limbs[j])
                    + carry
                out[i + j] = UInt32(
                    t & 0xFFFF_FFFF)
                carry = t >> 32
            }
            var k = i + b.limbs.count
            while carry > 0 {
                let t = UInt64(out[k])
                    + carry
                out[k] = UInt32(
                    t & 0xFFFF_FFFF)
                carry = t >> 32
                k += 1
            }
        }
        return LockBig(raw: out)
    }

    func shlBits(_ s: Int) -> LockBig {
        if isZero || s == 0 { return self }
        let words = s / 32
        let bits = s % 32
        var out = [UInt32](
            repeating: 0, count: words)
        if bits == 0 {
            return LockBig(
                raw: out + limbs)
        }
        var carry: UInt32 = 0
        for limb in limbs {
            out.append((limb << bits)
                | carry)
            carry = limb >> (32 - bits)
        }
        if carry > 0 { out.append(carry) }
        return LockBig(raw: out)
    }

    func shrBits(_ s: Int) -> LockBig {
        let words = s / 32
        let bits = s % 32
        if words >= limbs.count {
            return LockBig()
        }
        let src = Array(
            limbs.dropFirst(words))
        if bits == 0 {
            return LockBig(raw: src)
        }
        var out: [UInt32] = []
        for i in 0..<src.count {
            let next: UInt32 =
                i + 1 < src.count
                ? src[i + 1] : 0
            out.append((src[i] >> bits)
                | (next << (32 - bits)))
        }
        return LockBig(raw: out)
    }

    /// Knuth's Algorithm D (TAOCP
    /// 4.3.1) — the same shape the
    /// Python mirror fuzzed.
    func divmod(_ d: LockBig)
        -> (q: LockBig, r: LockBig) {
        if d.isZero { return (self, LockBig()) }
        if self < d { return (LockBig(), self) }
        if d.limbs.count == 1 {
            let div = UInt64(d.limbs[0])
            var rem: UInt64 = 0
            var q = [UInt32](
                repeating: 0,
                count: limbs.count)
            var i = limbs.count - 1
            while i >= 0 {
                let cur = (rem << 32)
                    | UInt64(limbs[i])
                q[i] = UInt32(cur / div)
                rem = cur % div
                i -= 1
            }
            return (LockBig(raw: q),
                    LockBig(UInt32(rem)))
        }
        let n = d.limbs.count
        let m = limbs.count - n
        let shift = d.limbs[n - 1]
            .leadingZeroBitCount
        let vn = d.shlBits(shift)
        var un = shlBits(shift).limbs
        while un.count < limbs.count + 1 {
            un.append(0)
        }
        var q = [UInt32](
            repeating: 0, count: m + 1)
        let vtop = UInt64(vn.limbs[n - 1])
        let vnext = UInt64(vn.limbs[n - 2])
        var j = m
        while j >= 0 {
            let num = (UInt64(un[j + n])
                << 32)
                | UInt64(un[j + n - 1])
            var qhat = num / vtop
            var rhat = num % vtop
            while qhat > 0xFFFF_FFFF
                    || qhat * vnext
                        > ((rhat << 32)
                            | UInt64(
                                un[j + n - 2])) {
                qhat -= 1
                rhat += vtop
                if rhat > 0xFFFF_FFFF {
                    break
                }
            }
            var borrow: Int64 = 0
            var carry: UInt64 = 0
            for i in 0..<n {
                let p = qhat *
                    UInt64(vn.limbs[i])
                    + carry
                carry = p >> 32
                let plo = Int64(
                    p & 0xFFFF_FFFF)
                var diff = Int64(un[i + j])
                    - borrow - plo
                if diff < 0 {
                    diff += 1 << 32
                    borrow = 1
                } else {
                    borrow = 0
                }
                un[i + j] = UInt32(diff)
            }
            var top = Int64(un[j + n])
                - borrow - Int64(carry)
            if top < 0 {
                un[j + n] = UInt32(
                    top + (1 << 32))
                qhat -= 1
                var c: UInt64 = 0
                for i in 0..<n {
                    let s = UInt64(un[i + j])
                        + UInt64(vn.limbs[i])
                        + c
                    un[i + j] = UInt32(
                        s & 0xFFFF_FFFF)
                    c = s >> 32
                }
                un[j + n] = UInt32(
                    (UInt64(un[j + n]) + c)
                        & 0xFFFF_FFFF)
            } else {
                un[j + n] = UInt32(top)
            }
            q[j] = UInt32(qhat)
            j -= 1
        }
        let r = LockBig(raw: Array(
            un.prefix(n))).shrBits(shift)
        return (LockBig(raw: q), r)
    }

    func mod(_ d: LockBig) -> LockBig {
        divmod(d).r
    }

    static func gcd(_ a0: LockBig,
                    _ b0: LockBig) -> LockBig {
        var a = a0
        var b = b0
        while !b.isZero {
            let r = a.mod(b)
            a = b
            b = r
        }
        return a
    }

    func isqrt() -> LockBig {
        if isZero { return LockBig() }
        var x = LockBig(1).shlBits(
            (bitLength + 1) / 2)
        while true {
            let quot = divmod(x).q
            let y = (x + quot).shrBits(1)
            if y >= x { break }
            x = y
        }
        while x * x > self {
            x = x - LockBig(1)
        }
        while (x + LockBig(1))
                * (x + LockBig(1)) <= self {
            x = x + LockBig(1)
        }
        return x
    }

    func modpow(_ e: LockBig,
                _ m: LockBig) -> LockBig {
        var result = LockBig(1)
        var base = mod(m)
        let bits = e.bitLength
        for i in 0..<bits {
            let limb = e.limbs[i / 32]
            if (limb >> (i % 32)) & 1 == 1 {
                result = (result * base)
                    .mod(m)
            }
            base = (base * base).mod(m)
        }
        return result
    }

    func modSmall(_ d: UInt32) -> UInt32 {
        var rem: UInt64 = 0
        let div = UInt64(d)
        var i = limbs.count - 1
        while i >= 0 {
            rem = ((rem << 32)
                | UInt64(limbs[i])) % div
            i -= 1
        }
        return UInt32(rem)
    }
}

extension BlacksiteBench {

    // MARK: the wave-8 dispatch

    /// One case in netCommand routes
    /// the whole locks & ciphers bench
    /// here; the verb name picks the
    /// hand. File and string verbs are
    /// pure workbench — they run on the
    /// bench queue like every verb's
    /// engine room and touch no wire.
    static func benchLocks(
        name: String, arg: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = { text, kind in
            if !stopped() { emit(text, kind) }
        }
        switch name {
        case "keyprobe":
            keyprobe(target: arg,
                     emit: live, done: done)
        case "hashprobe":
            hashprobe(target: arg,
                      emit: live, done: done)
        case "entropyprobe":
            entropyprobe(target: arg,
                         emit: live, done: done)
        case "b64deep":
            b64deep(target: arg,
                    emit: live, done: done)
        case "x509probe":
            x509probe(target: arg,
                      emit: live, done: done)
        case "pgpprobe":
            pgpprobe(target: arg,
                     emit: live, done: done)
        case "sshkeydeep":
            sshkeydeep(target: arg,
                       emit: live, done: done)
        case "tlscensus":
            tlscensus(target: arg,
                      stopped: stopped,
                      emit: live, done: done)
        case "cipherprobe":
            cipherprobe(target: arg,
                        emit: live, done: done)
        case "randprobe":
            randprobe(target: arg,
                      emit: live, done: done)
        case "kdfprobe":
            kdfprobe(spec: arg,
                     emit: live, done: done)
        case "aesprobe":
            aesprobe(spec: arg,
                     emit: live, done: done)
        case "xorprobe":
            xorprobe(target: arg,
                     emit: live, done: done)
        case "rsaprobe":
            rsaprobe(target: arg,
                     emit: live, done: done)
        case "eccprobe":
            eccprobe(target: arg,
                     emit: live, done: done)
        case "enccensus":
            enccensus(target: arg,
                      emit: live, done: done)
        case "sigprobe":
            sigprobe(spec: arg,
                     emit: live, done: done)
        case "totpprobe":
            totpprobe(spec: arg,
                      emit: live, done: done)
        case "passprobe":
            passprobe(spec: arg,
                      emit: live, done: done)
        case "lockcensus":
            lockcensus(target: arg,
                       emit: live, done: done)
        default:
            done()
        }
    }

    // MARK: shared plumbing

    /// Read a file the operator
    /// names: the path as typed first,
    /// then under the bench home. The
    /// path that answered is returned
    /// with the bytes, so the report
    /// can name what was actually read.
    static func lockReadFile(
        _ typed: String)
        -> (data: Data, path: String)? {
        let trimmed = typed
            .trimmingCharacters(
                in: .whitespaces)
        if trimmed.isEmpty { return nil }
        var candidates = [trimmed]
        if !trimmed.hasPrefix("/") {
            candidates.append(
                "/home/" + trimmed)
        }
        for path in candidates {
            if let data = BlacksiteFS
                .readData(path) {
                return (data, path)
            }
        }
        return nil
    }

    /// PEM blocks out of a text: the
    /// label and the decoded bytes of
    /// every -----BEGIN----- span.
    static func lockPEMBlocks(
        _ text: String)
        -> [(label: String, der: [UInt8])] {
        var out: [(label: String,
                    der: [UInt8])] = []
        let lines = text.components(
            separatedBy: .newlines)
        var label: String?
        var body = ""
        for raw in lines {
            let line = raw
                .trimmingCharacters(
                    in: .whitespaces)
            if line.hasPrefix(
                "-----BEGIN "),
               line.hasSuffix("-----") {
                label = String(line
                    .dropFirst(11)
                    .dropLast(5))
                body = ""
            } else if line ==
                        "-----END "
                        + (label ?? "")
                        + "-----",
                      let found = label {
                if let data = Data(
                    base64Encoded: body) {
                    out.append((
                        label: found,
                        der: [UInt8](data)))
                }
                label = nil
            } else if label != nil,
                      !line.contains(":") {
                body += line
            }
        }
        return out
    }

    /// A DER reader on absolute
    /// offsets (the Wave 3 shape):
    /// one TLV is (tag, content start,
    /// content end) in the one buffer.
    static func lockTLV(
        _ b: [UInt8], _ at: Int)
        -> (tag: Int, cs: Int, ce: Int)? {
        guard at + 2 <= b.count
        else { return nil }
        let tag = Int(b[at])
        var index = at + 1
        let first = Int(b[index])
        index += 1
        var length = 0
        if first < 0x80 {
            length = first
        } else {
            let digits = first & 0x7F
            guard digits >= 1,
                  digits <= 4,
                  index + digits <= b.count
            else { return nil }
            for _ in 0..<digits {
                length = length << 8
                    | Int(b[index])
                index += 1
            }
        }
        guard index + length <= b.count
        else { return nil }
        return (tag, index, index + length)
    }

    /// The children of a constructed
    /// TLV whose content spans
    /// [cs, ce).
    static func lockChildren(
        _ b: [UInt8], _ cs: Int,
        _ ce: Int)
        -> [(tag: Int, cs: Int, ce: Int)] {
        var out: [(tag: Int, cs: Int,
                   ce: Int)] = []
        var at = cs
        while at < ce {
            guard let t = lockTLV(b, at),
                  t.ce <= ce
            else { break }
            out.append(t)
            at = t.ce
        }
        return out
    }

    static func lockOID(
        _ b: [UInt8], _ cs: Int,
        _ ce: Int) -> String {
        guard cs < ce else { return "?" }
        var parts = [Int(b[cs]) / 40,
                     Int(b[cs]) % 40]
        var value = 0
        for byte in b[(cs + 1)..<ce] {
            value = value << 7
                | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                parts.append(value)
                value = 0
            }
        }
        return parts.map(String.init)
            .joined(separator: ".")
    }

    /// An X.501 name read as RDN
    /// pairs, in the order the paper
    /// carries them.
    static func lockName(
        _ b: [UInt8], _ cs: Int,
        _ ce: Int)
        -> [(oid: String, value: String)] {
        var out: [(oid: String,
                   value: String)] = []
        for set in lockChildren(b, cs, ce) {
            for ava in lockChildren(
                b, set.cs, set.ce) {
                let parts = lockChildren(
                    b, ava.cs, ava.ce)
                guard parts.count == 2
                else { continue }
                let oid = lockOID(
                    b, parts[0].cs,
                    parts[0].ce)
                let raw = Array(
                    b[parts[1].cs..<parts[1].ce])
                let value: String
                switch parts[1].tag {
                case 0x1E:
                    value = String(
                        bytes: raw,
                        encoding: .utf16) ?? ""
                case 0x14:
                    value = String(
                        bytes: raw,
                        encoding: .isoLatin1)
                        ?? ""
                default:
                    value = String(
                        bytes: raw,
                        encoding: .utf8) ?? ""
                }
                out.append((oid: oid,
                            value: value))
            }
        }
        return out
    }

    /// Days from civil (Hinnant's
    /// algorithm) — the epoch math
    /// behind certificate times,
    /// verified against known dates
    /// before it shipped.
    static func lockDaysFromCivil(
        _ y0: Int, _ m: Int, _ d: Int)
        -> Int {
        var y = y0
        if m <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399)
            / 400
        let yoe = y - era * 400
        let mp = m > 2 ? m - 3 : m + 9
        let doy = (153 * mp + 2) / 5
            + d - 1
        let doe = yoe * 365 + yoe / 4
            - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// UTCTime / GeneralizedTime to a
    /// Date, honouring the RFC 5280
    /// 1950/2049 UTCTime pivot and an
    /// explicit ±hhmm offset.
    static func lockCertTime(
        tag: Int, _ raw: [UInt8])
        -> Date? {
        guard let s = String(
            bytes: raw, encoding: .ascii)
        else { return nil }
        let ch = Array(s)
        func num(_ from: Int, _ len: Int)
            -> Int? {
            guard from + len <= ch.count
            else { return nil }
            var v = 0
            for i in from..<(from + len) {
                guard ch[i].isNumber,
                      let d = ch[i]
                        .wholeNumberValue
                else { return nil }
                v = v * 10 + d
            }
            return v
        }
        var year: Int
        var at: Int
        if tag == 0x17 {
            guard let yy = num(0, 2)
            else { return nil }
            year = yy < 50
                ? 2000 + yy : 1900 + yy
            at = 2
        } else {
            guard let yyyy = num(0, 4)
            else { return nil }
            year = yyyy
            at = 4
        }
        guard let mo = num(at, 2),
              let dy = num(at + 2, 2),
              let hh = num(at + 4, 2),
              let mm = num(at + 6, 2),
              let ss = num(at + 8, 2)
        else { return nil }
        at += 10
        var offset = 0
        if at < ch.count,
           ch[at] == "+"
            || ch[at] == "-" {
            guard let oh = num(at + 1, 2),
                  let om = num(at + 3, 2)
            else { return nil }
            offset = oh * 3600 + om * 60
            if ch[at] == "-" {
                offset = -offset
            }
        }
        let days = lockDaysFromCivil(
            year, mo, dy)
        let epoch = days * 86400
            + hh * 3600 + mm * 60 + ss
            - offset
        return Date(timeIntervalSince1970:
                        Double(epoch))
    }

    static func lockDateString(
        _ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(
            identifier: "en_US_POSIX")
        f.timeZone = TimeZone(
            secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension BlacksiteBench {

    // MARK: key material parsing

    /// One TLV with its element start
    /// kept, so a nested structure can
    /// be re-sliced whole (an SPKI
    /// inside a certificate, an
    /// extension inside its wrapper).
    static func lockChildrenFull(
        _ b: [UInt8], _ cs: Int,
        _ ce: Int)
        -> [(tag: Int, es: Int,
             cs: Int, ce: Int)] {
        var out: [(tag: Int, es: Int,
                   cs: Int, ce: Int)] = []
        var at = cs
        while at < ce {
            guard let t = lockTLV(b, at),
                  t.ce <= ce
            else { break }
            out.append((tag: t.tag, es: at,
                        cs: t.cs, ce: t.ce))
            at = t.ce
        }
        return out
    }

    /// What a parsed public key says
    /// about itself: family, the size
    /// or curve, and enough structure
    /// for fingerprints and grading.
    struct LockKeyInfo {
        var family: String
        var detail: String
        var strengthNote: String?
        var strengthBad: Bool = false
        var sshBlob: [UInt8]?
        var rsaModulus: LockBig?
        var rsaExponent: LockBig?
        var ecCurveOID: String?
        var ecPoint: [UInt8]?
    }

    static func lockSSHString(
        _ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        let n = bytes.count
        out.append(UInt8((n >> 24) & 0xFF))
        out.append(UInt8((n >> 16) & 0xFF))
        out.append(UInt8((n >> 8) & 0xFF))
        out.append(UInt8(n & 0xFF))
        out += bytes
        return out
    }

    static func lockMPInt(
        _ value: LockBig) -> [UInt8] {
        var bytes = value.toBytes()
        if let top = bytes.first,
           top & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return lockSSHString(bytes)
    }

    static let lockCurveNames: [String: String] = [
        "1.2.840.10045.3.1.7": "nistp256",
        "1.3.132.0.34": "nistp384",
        "1.3.132.0.35": "nistp521",
        "1.3.132.0.10": "secp256k1",
        "1.3.132.0.31": "nistp192",
        "1.3.132.0.32": "nistp224",
        "1.3.132.0.33": "nistp256",
        "1.2.840.10045.3.1.1": "nistp192",
        "1.2.840.10045.3.1.2": "nistp224",
        "1.2.840.10045.3.1.3": "nistp256",
        "1.2.840.10045.3.1.4": "nistp384",
        "1.2.840.10045.3.1.5": "nistp521",
    ]

    static let lockCurveLabels: [String: String] = [
        "1.2.840.10045.3.1.7": "NIST P-256",
        "1.3.132.0.34": "NIST P-384",
        "1.3.132.0.35": "NIST P-521",
        "1.3.132.0.10": "secp256k1 (the Bitcoin curve)",
        "1.3.132.0.31": "NIST P-192",
        "1.3.132.0.32": "NIST P-224",
    ]

    /// Parse an SPKI (RFC 5280
    /// SubjectPublicKeyInfo) held in
    /// der[range] — or a bare PKCS#1
    /// RSAPublicKey, or a bare SEC 1
    /// EC point.
    static func lockParseSPKI(
        _ der: [UInt8]) -> LockKeyInfo? {
        guard let top = lockTLV(der, 0),
              top.tag == 0x30,
              top.ce <= der.count
        else { return nil }
        let kids = lockChildrenFull(
            der, top.cs, top.ce)
        // PKCS#1 RSAPublicKey: a bare
        // SEQUENCE of two INTEGERs.
        if kids.count == 2,
           kids[0].tag == 0x02,
           kids[1].tag == 0x02 {
            let n = LockBig.fromBytes(
                Array(der[kids[0].cs..<kids[0].ce]))
            let e = LockBig.fromBytes(
                Array(der[kids[1].cs..<kids[1].ce]))
            return lockRSAInfo(n: n, e: e)
        }
        guard kids.count == 2,
              kids[0].tag == 0x30,
              kids[1].tag == 0x03
        else { return nil }
        let algKids = lockChildrenFull(
            der, kids[0].cs, kids[0].ce)
        guard let algFirst = algKids.first,
              algFirst.tag == 0x06
        else { return nil }
        let algOID = lockOID(
            der, algFirst.cs, algFirst.ce)
        let bitContent = Array(
            der[kids[1].cs..<kids[1].ce])
        guard bitContent.first == 0
        else { return nil }
        let payload = Array(bitContent.dropFirst())
        switch algOID {
        case "1.2.840.113549.1.1.1":
            guard let inner = lockTLV(
                payload, 0), inner.tag == 0x30
            else { return nil }
            let parts = lockChildrenFull(
                payload, inner.cs, inner.ce)
            guard parts.count == 2
            else { return nil }
            let n = LockBig.fromBytes(
                Array(payload[parts[0].cs..<parts[0].ce]))
            let e = LockBig.fromBytes(
                Array(payload[parts[1].cs..<parts[1].ce]))
            return lockRSAInfo(n: n, e: e)
        case "1.2.840.10045.2.1":
            var curveOID = ""
            if algKids.count > 1,
               algKids[1].tag == 0x06 {
                curveOID = lockOID(
                    der, algKids[1].cs,
                    algKids[1].ce)
            }
            let label = lockCurveLabels[
                curveOID] ?? curveOID
            var info = LockKeyInfo(
                family: "EC",
                detail: String(format: L("elliptic curve %@"), label),
                strengthNote: nil,
                ecCurveOID: curveOID,
                ecPoint: payload)
            if let sshName = lockCurveNames[
                curveOID] {
                let full = "ecdsa-sha2-"
                    + sshName
                info.sshBlob =
                    lockSSHString(
                        Array(full.utf8))
                    + lockSSHString(
                        Array(sshName.utf8))
                    + lockSSHString(payload)
            }
            if curveOID ==
                "1.3.132.0.31"
                || curveOID ==
                "1.2.840.10045.3.1.1" {
                info.strengthNote = L("a 192-bit curve — below the modern floor; this key should be retired")
                info.strengthBad = true
            }
            return info
        case "1.3.101.112":
            return LockKeyInfo(
                family: "Ed25519",
                detail: L("Ed25519 — a 32-byte raw public key"),
                strengthNote: nil,
                sshBlob: lockSSHString(
                    Array("ssh-ed25519".utf8))
                    + lockSSHString(payload))
        case "1.3.101.113":
            return LockKeyInfo(
                family: "Ed448",
                detail: L("Ed448 — a 57-byte raw public key"),
                strengthNote: nil)
        case "1.3.101.110":
            return LockKeyInfo(
                family: "X25519",
                detail: L("X25519 — key agreement only, never a signature"),
                strengthNote: nil)
        case "1.3.101.111":
            return LockKeyInfo(
                family: "X448",
                detail: L("X448 — key agreement only, never a signature"),
                strengthNote: nil)
        case "1.2.840.10040.4.1":
            var bits = 0
            if algKids.count > 1 {
                let params = lockChildrenFull(
                    der, algKids[1].cs,
                    algKids[1].ce)
                if let p = params.first {
                    bits = LockBig.fromBytes(
                        Array(der[p.cs..<p.ce]))
                        .bitLength
                }
            }
            return LockKeyInfo(
                family: "DSA",
                detail: String(format: L("DSA over a %lld-bit prime field"), Int64(bits)),
                strengthNote: L("DSA is a legacy signature family — OpenSSH dropped it by default; treat this key as dated"),
                strengthBad: false)
        default:
            return LockKeyInfo(
                family: L("another family"),
                detail: String(format: L("algorithm OID %@ — recognised as a public key wrapper, not a family this bench grades"), algOID),
                strengthNote: nil)
        }
    }

    static func lockRSAInfo(
        n: LockBig, e: LockBig)
        -> LockKeyInfo {
        let bits = n.bitLength
        var info = LockKeyInfo(
            family: "RSA",
            detail: String(format: L("a %lld-bit modulus, public exponent %@"), Int64(bits), e.toBytes().map {
                String(format: "%02x", $0)
            }.joined()),
            strengthNote: nil,
            sshBlob: lockSSHString(
                Array("ssh-rsa".utf8))
                + lockMPInt(e)
                + lockMPInt(n),
            rsaModulus: n,
            rsaExponent: e)
        if bits < 2048 {
            info.strengthNote = L("under 2048 bits — factorable with patience and money; this lock is a lock in name only")
            info.strengthBad = true
        } else if bits == 2048 {
            info.strengthNote = L("2048 bits — the accepted floor today")
        }
        if e == LockBig(3) {
            info.strengthNote = L("public exponent 3 — lawful, but it has bitten careless verifiers for decades; 65537 is the house standard")
            info.strengthBad = true
        }
        return info
    }

    /// Describe parsed key material
    /// in the bench's voice, with its
    /// fingerprints.
    static func lockDescribeKey(
        _ info: LockKeyInfo,
        der: [UInt8]?,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("family: %@"), info.family), .sys)
        icsSay(emit, info.detail)
        if let note = info.strengthNote {
            icsSay(emit, note,
                   info.strengthBad
                    ? .err : .out)
        }
        if let blob = info.sshBlob {
            let digest = SHA256.hash(
                data: Data(blob))
            let b64 = Data(digest)
                .base64EncodedString()
                .replacingOccurrences(
                    of: "=", with: "")
            icsSay(emit, String(format: L("OpenSSH SHA256 fingerprint: %@"), b64))
        }
        if let der = der {
            let digest = SHA256.hash(
                data: Data(der))
            let hex = digest.map {
                String(format: "%02x", $0)
            }.joined()
            icsSay(emit, String(format: L("SHA-256 over the DER as read: %@"), hex))
        }
    }

    /// An OpenSSH public-key blob
    /// (the binary inside the base64
    /// of a .pub line) read field by
    /// field.
    static func lockParseSSHBlob(
        _ blob: [UInt8])
        -> (type: String,
            fields: [[UInt8]])? {
        var fields: [[UInt8]] = []
        var pos = 0
        while pos + 4 <= blob.count,
              fields.count < 6 {
            let n = Int(blob[pos]) << 24
                | Int(blob[pos + 1]) << 16
                | Int(blob[pos + 2]) << 8
                | Int(blob[pos + 3])
            pos += 4
            guard n >= 0,
                  pos + n <= blob.count
            else { return nil }
            fields.append(Array(
                blob[pos..<(pos + n)]))
            pos += n
        }
        guard let first = fields.first,
              let type = String(
                bytes: first, encoding: .ascii),
              type.hasPrefix("ssh-")
                || type.hasPrefix("ecdsa-")
                || type.hasPrefix("sk-")
        else { return nil }
        return (type, fields)
    }

    static func lockDescribeSSHBlob(
        _ parsed: (type: String,
                   fields: [[UInt8]]),
        blob: [UInt8],
        emit: @escaping BlacksiteEmit) {
        let fields = parsed.fields
        icsSay(emit, String(format: L("OpenSSH key type: %@"), parsed.type), .sys)
        switch parsed.type {
        case "ssh-rsa":
            if fields.count >= 3 {
                let e = LockBig.fromBytes(
                    fields[1])
                let n = LockBig.fromBytes(
                    fields[2])
                let info = lockRSAInfo(
                    n: n, e: e)
                icsSay(emit, info.detail)
                if let note =
                    info.strengthNote {
                    icsSay(emit, note,
                           info.strengthBad
                            ? .err : .out)
                }
            }
        case "ssh-ed25519":
            if fields.count >= 2 {
                icsSay(emit, String(format: L("a %lld-byte Ed25519 public key"), Int64(fields[1].count)))
            }
        case "ssh-dss":
            icsSay(emit, L("DSA — a legacy family OpenSSH no longer offers by default"))
        default:
            if parsed.type.hasPrefix(
                "ecdsa-sha2-"),
               fields.count >= 3 {
                let curve = String(
                    bytes: fields[1],
                    encoding: .ascii) ?? ""
                icsSay(emit, String(format: L("elliptic curve %@, a %lld-byte point"), curve, Int64(fields[2].count)))
            }
        }
        let digest = SHA256.hash(
            data: Data(blob))
        let b64 = Data(digest)
            .base64EncodedString()
            .replacingOccurrences(
                of: "=", with: "")
        icsSay(emit, String(format: L("OpenSSH SHA256 fingerprint: %@"), b64))
    }

    // MARK: keyprobe

    /// keyprobe <file|string> — what
    /// key is this, how strong, what
    /// are its fingerprints. PEM,
    /// bare DER and OpenSSH forms are
    /// all read; a private key is
    /// named by its wrapper only —
    /// the bench never decodes the
    /// secret inside one.
    static func keyprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("keyprobe: give a key file or an OpenSSH public line — keyprobe /home/id_ed25519.pub"), .err)
                return
            }
            // An OpenSSH public line
            // typed straight in.
            let tokens = arg.components(
                separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            if tokens.count >= 2,
               let blob64 = tokens.dropFirst().first,
               let blobData = Data(
                base64Encoded: blob64),
               let parsed = lockParseSSHBlob(
                [UInt8](blobData)) {
                lockDescribeSSHBlob(
                    parsed,
                    blob: [UInt8](blobData),
                    emit: emit)
                return
            }
            guard let file = lockReadFile(
                arg) else {
                icsSay(emit, L("no key material at that path, and the argument itself is not an OpenSSH public line"), .err)
                return
            }
            icsSay(emit, String(format: L("reading %@"), file.path), .sys)
            let der = [UInt8](file.data)
            let text = String(
                bytes: der, encoding: .utf8)
            if let text = text,
               text.contains("-----BEGIN ") {
                let blocks = lockPEMBlocks(
                    text)
                if blocks.isEmpty {
                    icsSay(emit, L("PEM armour is present but no block decodes"), .err)
                    return
                }
                for (index, block)
                    in blocks.enumerated() {
                    if blocks.count > 1 {
                        icsSay(emit, String(format: L("— block %lld: %@ —"), Int64(index + 1), block.label), .sys)
                    } else {
                        icsSay(emit, String(format: L("PEM block: %@"), block.label), .sys)
                    }
                    lockDescribePEMBlock(
                        label: block.label,
                        der: block.der,
                        emit: emit)
                }
                return
            }
            // authorized_keys style:
            // one OpenSSH line in a file.
            if let text = text {
                for line in text.components(
                    separatedBy: .newlines) {
                    let t = line
                        .trimmingCharacters(
                            in: .whitespaces)
                    if t.hasPrefix("ssh-")
                        || t.hasPrefix(
                            "ecdsa-") {
                        let parts = t
                            .components(
                                separatedBy:
                                    .whitespaces)
                            .filter {
                                !$0.isEmpty
                            }
                        if parts.count >= 2,
                           let blobData = Data(
                            base64Encoded:
                                parts[1]),
                           let parsed =
                            lockParseSSHBlob(
                                [UInt8](blobData)) {
                            lockDescribeSSHBlob(
                                parsed,
                                blob: [UInt8](
                                    blobData),
                                emit: emit)
                            return
                        }
                    }
                }
            }
            if let info = lockParseSPKI(der) {
                lockDescribeKey(
                    info, der: der,
                    emit: emit)
                return
            }
            if let parsed = lockParseSSHBlob(
                der) {
                lockDescribeSSHBlob(
                    parsed, blob: der,
                    emit: emit)
                return
            }
            icsSay(emit, L("the bytes do not parse as PEM, DER key material or an OpenSSH blob — hashprobe will at least fingerprint them"), .err)
        }
    }

    static func lockDescribePEMBlock(
        label: String, der: [UInt8],
        emit: @escaping BlacksiteEmit) {
        switch label {
        case "PUBLIC KEY":
            if let info = lockParseSPKI(
                der) {
                lockDescribeKey(
                    info, der: der,
                    emit: emit)
            } else {
                icsSay(emit, L("an SPKI wrapper that does not parse"), .err)
            }
        case "RSA PUBLIC KEY":
            if let info = lockParseSPKI(
                der) {
                lockDescribeKey(
                    info, der: der,
                    emit: emit)
            } else {
                icsSay(emit, L("a PKCS#1 public key that does not parse"), .err)
            }
        case "EC PUBLIC KEY":
            if let info = lockParseSPKI(
                der) {
                lockDescribeKey(
                    info, der: der,
                    emit: emit)
            } else {
                icsSay(emit, L("an EC public key that does not parse"), .err)
            }
        case "CERTIFICATE":
            icsSay(emit, L("a certificate — x509probe reads these papers in full"))
            if let cert = lockCertParse(
                der) {
                icsSay(emit, String(format: L("subject: %@"), cert.subjectLine))
            }
        case "PRIVATE KEY":
            icsSay(emit, L("a PKCS#8 private key — the bench reads the wrapper's algorithm label only; the secret inside is never decoded or graded"))
            if let top = lockTLV(der, 0) {
                let kids = lockChildrenFull(
                    der, top.cs, top.ce)
                if kids.count >= 2 {
                    let alg = lockChildrenFull(
                        der, kids[1].cs,
                        kids[1].ce)
                    if let first = alg.first {
                        let oid = lockOID(
                            der, first.cs,
                            first.ce)
                        icsSay(emit, String(format: L("wrapped algorithm OID: %@"), oid))
                    }
                }
            }
        case "RSA PRIVATE KEY",
             "EC PRIVATE KEY",
             "OPENSSH PRIVATE KEY",
             "ENCRYPTED PRIVATE KEY",
             "DSA PRIVATE KEY":
            icsSay(emit, String(format: L("a private key (%@) — named and respected; the bench does not decode private material"), label))
        default:
            icsSay(emit, String(format: L("a %@ block — not key material this bench reads"), label))
        }
    }
}

extension BlacksiteBench {

    // MARK: the papers — x509probe

    struct LockCert {
        var serialHex: String
        var sigOID: String
        var issuerLine: String
        var subjectLine: String
        var issuerRaw: [UInt8]
        var subjectRaw: [UInt8]
        var notBefore: Date?
        var notAfter: Date?
        var keyInfo: LockKeyInfo?
        var sans: [(kind: String,
                    value: String)]
        var isCA: Bool?
        var keyUsage: [String]
        var extKeyUsage: [String]
    }

    static let lockShortOIDs: [String: String] = [
        "2.5.4.3": "CN",
        "2.5.4.5": "serialNumber",
        "2.5.4.6": "C",
        "2.5.4.7": "L",
        "2.5.4.8": "ST",
        "2.5.4.9": "street",
        "2.5.4.10": "O",
        "2.5.4.11": "OU",
        "2.5.4.17": "postalCode",
        "1.2.840.113549.1.9.1": "emailAddress",
        "0.9.2342.19200300.100.1.25": "DC",
        "0.9.2342.19200300.100.1.1": "UID",
    ]

    static func lockNameLine(
        _ pairs: [(oid: String,
                   value: String)])
        -> String {
        pairs.map {
            (lockShortOIDs[$0.oid] ?? $0.oid)
                + "=" + $0.value
        }.joined(separator: ", ")
    }

    /// A trust's certificate chain, whole
    /// (fix369): SecTrustCopyCertificateChain
    /// is the standing API — the per-index
    /// getter the bench used at ten sites was
    /// deprecated in iOS 15 / macOS 12. One
    /// door for the chain; sites take .first
    /// for the leaf or walk the array.
    static func certChain(
        _ trust: SecTrust) -> [SecCertificate] {
        (SecTrustCopyCertificateChain(trust)
            as? [SecCertificate]) ?? []
    }

    /// Parse one DER certificate.
    /// The walk is the house DER walk
    /// (verified against openssl's own
    /// reading of the same papers).
    static func lockCertParse(
        _ der: [UInt8]) -> LockCert? {
        guard let top = lockTLV(der, 0),
              top.tag == 0x30
        else { return nil }
        let kids = lockChildrenFull(
            der, top.cs, top.ce)
        guard kids.count >= 3
        else { return nil }
        let tbs = lockChildrenFull(
            der, kids[0].cs, kids[0].ce)
        let base = tbs.first?.tag == 0xA0
            ? 1 : 0
        guard tbs.count > base + 5
        else { return nil }
        let serialBytes = Array(
            der[tbs[base].cs..<tbs[base].ce])
        let serialHex = serialBytes.map {
            String(format: "%02x", $0)
        }.joined(separator: ":")
        var sigOID = ""
        let sigKids = lockChildrenFull(
            der, tbs[base + 1].cs,
            tbs[base + 1].ce)
        if let first = sigKids.first {
            sigOID = lockOID(
                der, first.cs, first.ce)
        }
        let issuerPairs = lockName(
            der, tbs[base + 2].cs,
            tbs[base + 2].ce)
        let issuerRaw = Array(
            der[tbs[base + 2].cs..<tbs[base + 2].ce])
        var notBefore: Date?
        var notAfter: Date?
        let validity = lockChildrenFull(
            der, tbs[base + 3].cs,
            tbs[base + 3].ce)
        if validity.count == 2 {
            notBefore = lockCertTime(
                tag: validity[0].tag,
                Array(der[validity[0].cs..<validity[0].ce]))
            notAfter = lockCertTime(
                tag: validity[1].tag,
                Array(der[validity[1].cs..<validity[1].ce]))
        }
        let subjectPairs = lockName(
            der, tbs[base + 4].cs,
            tbs[base + 4].ce)
        let subjectRaw = Array(
            der[tbs[base + 4].cs..<tbs[base + 4].ce])
        var keyInfo: LockKeyInfo?
        let spkiElement = tbs[base + 5]
        keyInfo = lockParseSPKI(Array(
            der[spkiElement.es..<spkiElement.ce]))
        var sans: [(kind: String,
                    value: String)] = []
        var isCA: Bool?
        var keyUsage: [String] = []
        var extKeyUsage: [String] = []
        for extra in tbs.dropFirst(
            base + 6) {
            guard extra.tag == 0xA3
            else { continue }
            let wrapped = lockChildrenFull(
                der, extra.cs, extra.ce)
            guard let seq = wrapped.first
            else { continue }
            for ext in lockChildrenFull(
                der, seq.cs, seq.ce) {
                let parts = lockChildrenFull(
                    der, ext.cs, ext.ce)
                guard parts.count >= 2,
                      let oidPart = parts.first
                else { continue }
                let oid = lockOID(
                    der, oidPart.cs,
                    oidPart.ce)
                let valuePart = parts.last!
                let value = Array(
                    der[valuePart.cs..<valuePart.ce])
                switch oid {
                case "2.5.29.17":
                    guard let names = lockTLV(
                        value, 0),
                          names.tag == 0x30
                    else { break }
                    for gn in lockChildrenFull(
                        value, names.cs,
                        names.ce) {
                        let raw = Array(
                            value[gn.cs..<gn.ce])
                        switch gn.tag {
                        case 0x82:
                            sans.append((
                                kind: "DNS",
                                value: String(
                                    bytes: raw,
                                    encoding: .ascii)
                                    ?? ""))
                        case 0x81:
                            sans.append((
                                kind: "email",
                                value: String(
                                    bytes: raw,
                                    encoding: .ascii)
                                    ?? ""))
                        case 0x86:
                            sans.append((
                                kind: "URI",
                                value: String(
                                    bytes: raw,
                                    encoding: .ascii)
                                    ?? ""))
                        case 0x87:
                            if raw.count == 4 {
                                sans.append((
                                    kind: "IP",
                                    value: raw
                                        .map(
                                            String
                                                .init)
                                        .joined(
                                            separator: ".")))
                            } else {
                                sans.append((
                                    kind: "IP",
                                    value: raw.map {
                                        String(
                                            format: "%02x",
                                            $0)
                                    }.joined(
                                        separator: ":")))
                            }
                        default:
                            sans.append((
                                kind: String(
                                    format: "type %lld",
                                    Int64(gn.tag & 0x1F)),
                                value: ""))
                        }
                    }
                case "2.5.29.19":
                    guard let bc = lockTLV(
                        value, 0)
                    else { break }
                    let fields =
                        lockChildrenFull(
                            value, bc.cs,
                            bc.ce)
                    if let first = fields.first,
                       first.tag == 0x01 {
                        isCA = value[first.cs]
                            != 0
                    } else {
                        isCA = false
                    }
                case "2.5.29.15":
                    guard let bits = lockTLV(
                        value, 0),
                          bits.tag == 0x03,
                          bits.cs < bits.ce
                    else { break }
                    let raw = Array(
                        value[bits.cs..<bits.ce])
                    guard raw.count >= 2
                    else { break }
                    let names = [
                        "digitalSignature",
                        "nonRepudiation",
                        "keyEncipherment",
                        "dataEncipherment",
                        "keyAgreement",
                        "keyCertSign",
                        "cRLSign",
                        "encipherOnly",
                        "decipherOnly",
                    ]
                    for (i, name)
                        in names.enumerated() {
                        let byteIndex = 1
                            + i / 8
                        guard byteIndex
                                < raw.count
                        else { break }
                        if raw[byteIndex]
                            & UInt8(
                                0x80 >> (i % 8))
                            != 0 {
                            keyUsage.append(
                                name)
                        }
                    }
                case "2.5.29.37":
                    guard let seq = lockTLV(
                        value, 0)
                    else { break }
                    let known: [String: String] = [
                        "1.3.6.1.5.5.7.3.1": "serverAuth",
                        "1.3.6.1.5.5.7.3.2": "clientAuth",
                        "1.3.6.1.5.5.7.3.3": "codeSigning",
                        "1.3.6.1.5.5.7.3.4": "emailProtection",
                        "1.3.6.1.5.5.7.3.8": "timeStamping",
                        "1.3.6.1.5.5.7.3.9": "OCSPSigning",
                    ]
                    for item in lockChildrenFull(
                        value, seq.cs, seq.ce) {
                        let o = lockOID(
                            value, item.cs,
                            item.ce)
                        extKeyUsage.append(
                            known[o] ?? o)
                    }
                default:
                    break
                }
            }
        }
        return LockCert(
            serialHex: serialHex,
            sigOID: sigOID,
            issuerLine: lockNameLine(
                issuerPairs),
            subjectLine: lockNameLine(
                subjectPairs),
            issuerRaw: issuerRaw,
            subjectRaw: subjectRaw,
            notBefore: notBefore,
            notAfter: notAfter,
            keyInfo: keyInfo,
            sans: sans,
            isCA: isCA,
            keyUsage: keyUsage,
            extKeyUsage: extKeyUsage)
    }

    static func lockSigName(
        _ oid: String) -> (name: String,
                           weak: Bool) {
        switch oid {
        case "1.2.840.113549.1.1.11":
            return ("sha256WithRSAEncryption", false)
        case "1.2.840.113549.1.1.12":
            return ("sha384WithRSAEncryption", false)
        case "1.2.840.113549.1.1.13":
            return ("sha512WithRSAEncryption", false)
        case "1.2.840.113549.1.1.14":
            return ("sha224WithRSAEncryption", false)
        case "1.2.840.113549.1.1.10":
            return ("RSASSA-PSS", false)
        case "1.2.840.113549.1.1.5":
            return ("sha1WithRSAEncryption", true)
        case "1.2.840.113549.1.1.4":
            return ("md5WithRSAEncryption", true)
        case "1.2.840.113549.1.1.2":
            return ("md2WithRSAEncryption", true)
        case "1.2.840.10045.4.3.2":
            return ("ecdsa-with-SHA256", false)
        case "1.2.840.10045.4.3.3":
            return ("ecdsa-with-SHA384", false)
        case "1.2.840.10045.4.3.4":
            return ("ecdsa-with-SHA512", false)
        case "1.2.840.10045.4.1":
            return ("ecdsa-with-SHA1", true)
        case "1.3.101.112":
            return ("Ed25519", false)
        case "1.3.101.113":
            return ("Ed448", false)
        case "1.2.840.10040.4.3":
            return ("dsa-with-SHA1", true)
        case "2.16.840.1.101.3.4.3.2":
            return ("dsa-with-SHA256", false)
        default:
            return (oid, false)
        }
    }

    static func lockDescribeCert(
        _ cert: LockCert,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("subject: %@"), cert.subjectLine), .sys)
        icsSay(emit, String(format: L("issuer: %@"), cert.issuerLine))
        if cert.issuerRaw == cert.subjectRaw {
            icsSay(emit, L("issuer and subject are the same name — this paper is self-signed"), .err)
        }
        icsSay(emit, String(format: L("serial: %@"), cert.serialHex))
        let sig = lockSigName(cert.sigOID)
        if sig.weak {
            icsSay(emit, String(format: L("signed %@ — a broken or dying hash; browsers distrust these papers"), sig.name), .err)
        } else {
            icsSay(emit, String(format: L("signed %@"), sig.name))
        }
        if let nb = cert.notBefore,
           let na = cert.notAfter {
            let now = Date()
            let days = Int(
                na.timeIntervalSince(now)
                    / 86400)
            icsSay(emit, String(format: L("valid %@ to %@"), lockDateString(nb), lockDateString(na)))
            if now < nb {
                icsSay(emit, L("not yet valid — the paper's clock starts in the future"), .err)
            } else if days < 0 {
                icsSay(emit, L("the paper has EXPIRED"), .err)
            } else if days < 30 {
                icsSay(emit, String(format: L("%lld days left — renewal is overdue to be scheduled"), Int64(days)), .err)
            } else {
                icsSay(emit, String(format: L("%lld days of validity left"), Int64(days)))
            }
        }
        if cert.sans.isEmpty {
            icsSay(emit, L("no subjectAltName at all — modern browsers refuse a cert without one"), .err)
        } else {
            icsSay(emit, String(format: L("%lld names on the paper:"), Int64(cert.sans.count)))
            for san in cert.sans.prefix(12) {
                if san.value.isEmpty {
                    icsSay(emit, "  " + san.kind)
                } else {
                    icsSay(emit, "  " + san.kind
                           + ": " + san.value)
                }
            }
            if cert.sans.count > 12 {
                icsSay(emit, String(format: L("  … and %lld more"), Int64(cert.sans.count - 12)))
            }
        }
        if let info = cert.keyInfo {
            icsSay(emit, String(format: L("key: %@ — %@"), info.family, info.detail))
            if let note = info.strengthNote {
                icsSay(emit, note,
                       info.strengthBad
                        ? .err : .out)
            }
        }
        if let isCA = cert.isCA {
            icsSay(emit, isCA
                   ? L("carries the CA mark — this paper may sign other papers")
                   : L("no CA mark — an end-entity paper"))
        }
        if !cert.keyUsage.isEmpty {
            icsSay(emit, String(format: L("key usage: %@"), cert.keyUsage.joined(separator: ", ")))
        }
        if !cert.extKeyUsage.isEmpty {
            icsSay(emit, String(format: L("extended usage: %@"), cert.extKeyUsage.joined(separator: ", ")))
        }
    }

    /// x509probe <file> — a
    /// certificate (or a whole PEM
    /// bundle) read from paper the
    /// operator brings: names,
    /// validity, key, usages, graded
    /// the way certprobe grades the
    /// live ones.
    static func x509probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("x509probe: give a certificate file — x509probe /home/bundle.pem"), .err)
                return
            }
            guard let file = lockReadFile(
                arg) else {
                icsSay(emit, L("nothing readable at that path"), .err)
                return
            }
            icsSay(emit, String(format: L("reading %@"), file.path), .sys)
            var ders: [[UInt8]] = []
            if let text = String(
                bytes: [UInt8](file.data),
                encoding: .utf8),
               text.contains("-----BEGIN ") {
                for block in lockPEMBlocks(
                    text) where
                    block.label ==
                        "CERTIFICATE"
                        || block.label ==
                        "TRUSTED CERTIFICATE" {
                    ders.append(block.der)
                }
            } else {
                // Bare DER, possibly
                // several back to back.
                let bytes = [UInt8](file.data)
                var at = 0
                while at < bytes.count,
                      let t = lockTLV(
                        bytes, at),
                      t.tag == 0x30 {
                    ders.append(Array(
                        bytes[at..<t.ce]))
                    at = t.ce
                }
            }
            guard !ders.isEmpty else {
                icsSay(emit, L("no certificate parses out of that file"), .err)
                return
            }
            var certs: [LockCert] = []
            for (index, der)
                in ders.enumerated() {
                guard let cert =
                    lockCertParse(der)
                else {
                    icsSay(emit, String(format: L("paper %lld does not parse as a certificate"), Int64(index + 1)), .err)
                    continue
                }
                if ders.count > 1 {
                    icsSay(emit, String(format: L("— paper %lld of %lld —"), Int64(index + 1), Int64(ders.count)), .sys)
                }
                lockDescribeCert(
                    cert, emit: emit)
                certs.append(cert)
            }
            if certs.count > 1 {
                var chained = true
                for i in 0..<(certs.count - 1) {
                    if certs[i].issuerRaw
                        != certs[i + 1]
                            .subjectRaw {
                        chained = false
                    }
                }
                if chained {
                    icsSay(emit, L("the bundle chains: each paper's issuer is the next paper's subject, leaf to root"), .ok)
                } else {
                    icsSay(emit, L("the bundle does not chain in file order — an issuer here is not the next paper's subject"), .err)
                }
            }
        }
    }

    // MARK: hashprobe

    static func lockHexDigest<D>(
        _ digest: D) -> String
        where D: Sequence, D.Element == UInt8 {
        digest.map {
            String(format: "%02x", $0)
        }.joined()
    }

    static func lockDigests(
        of data: Data,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("MD5 (legacy): %@"), lockHexDigest(Insecure.MD5.hash(data: data))))
        icsSay(emit, String(format: L("SHA-1 (legacy): %@"), lockHexDigest(Insecure.SHA1.hash(data: data))))
        icsSay(emit, String(format: L("SHA-256: %@"), lockHexDigest(SHA256.hash(data: data))), .sys)
        icsSay(emit, String(format: L("SHA-384: %@"), lockHexDigest(SHA384.hash(data: data))))
        icsSay(emit, String(format: L("SHA-512: %@"), lockHexDigest(SHA512.hash(data: data))))
    }

    /// hashprobe <file|digest|string>
    /// — hash a file, identify a
    /// digest by its shape, or hash a
    /// literal string and say that is
    /// what happened.
    static func hashprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("hashprobe: give a file, a hex digest, or a string — hashprobe /home/file.bin"), .err)
                return
            }
            if let file = lockReadFile(arg) {
                icsSay(emit, String(format: L("hashing %@ (%lld bytes)"), file.path, Int64(file.data.count)), .sys)
                lockDigests(of: file.data,
                            emit: emit)
                return
            }
            // Digest-shaped? strip the
            // dressing and test for hex.
            var cleaned = arg
                .replacingOccurrences(
                    of: " ", with: "")
                .replacingOccurrences(
                    of: ":", with: "")
            if cleaned.hasPrefix("0x")
                || cleaned.hasPrefix("0X") {
                cleaned = String(
                    cleaned.dropFirst(2))
            }
            let hex = cleaned.count >= 16
                && cleaned.count % 2 == 0
                && cleaned.allSatisfy {
                    $0.isHexDigit
                }
            if hex {
                let bytes = cleaned.count / 2
                let candidates: [Int: String] = [
                    16: "MD5 — also MD4, MD2 and any 128-bit fingerprint",
                    20: "SHA-1 — also RIPEMD-160",
                    28: "SHA-224",
                    32: "SHA-256 — also SHA-512/256, SM3 and BLAKE2s; size alone cannot swear which",
                    48: "SHA-384",
                    64: "SHA-512 — also BLAKE2b-512 and SHA3-512",
                ]
                icsSay(emit, String(format: L("a %lld-byte hex digest"), Int64(bytes)), .sys)
                if let name = candidates[
                    bytes] {
                    icsSay(emit, String(format: L("the size says: %@"), name))
                } else {
                    icsSay(emit, L("no common digest wears this size — it may be truncated, or a fingerprint of another kind (a key ID, a truncated MAC)"))
                }
                icsSay(emit, L("a digest's size names the family; only the algorithm that made it can swear to the member"))
                return
            }
            icsSay(emit, String(format: L("no file by that name — hashing the literal string (%lld bytes of UTF-8):"), Int64(arg.utf8.count)), .sys)
            lockDigests(
                of: Data(arg.utf8),
                emit: emit)
        }
    }

    // MARK: the statistics pair

    struct LockStats {
        var count: Int
        var entropy: Double
        var chiSquare: Double
        var minEntropy: Double
        var distinct: Int
        var topByte: Int
        var topCount: Int
        var runs: Int
        var runsZ: Double?
    }

    static func lockStats(
        _ data: [UInt8]) -> LockStats {
        var counts = [Int](
            repeating: 0, count: 256)
        for byte in data {
            counts[Int(byte)] += 1
        }
        let n = data.count
        var entropy = 0.0
        var topByte = 0
        var topCount = 0
        var distinct = 0
        for (value, c) in counts.enumerated()
            where c > 0 {
            distinct += 1
            let p = Double(c) / Double(n)
            entropy -= p * log2(p)
            if c > topCount {
                topCount = c
                topByte = value
            }
        }
        let expected = Double(n) / 256.0
        var chi = 0.0
        if n > 0 {
            for c in counts {
                let d = Double(c) - expected
                chi += d * d / expected
            }
        }
        let minEnt = topCount > 0
            ? -log2(Double(topCount)
                / Double(n)) : 0
        // Runs over the bit stream,
        // most significant bit first.
        var n1 = 0
        var runs = 0
        var previous = -1
        for byte in data {
            for shift in stride(
                from: 7, through: 0,
                by: -1) {
                let bit = Int(
                    (byte >> shift) & 1)
                n1 += bit
                if bit != previous {
                    runs += 1
                    previous = bit
                }
            }
        }
        let n0 = n * 8 - n1
        var z: Double?
        if n1 > 0, n0 > 0 {
            let mu = 2.0 * Double(n1) *
                Double(n0) /
                Double(n1 + n0) + 1
            let varNum = 2.0 *
                Double(n1) * Double(n0) *
                (2.0 * Double(n1) *
                    Double(n0) -
                    Double(n1 + n0))
            let varDen = Double(n1 + n0) *
                Double(n1 + n0) *
                Double(n1 + n0 - 1)
            let variance = varNum / varDen
            if variance > 0 {
                z = (Double(runs) - mu)
                    / sqrt(variance)
            }
        }
        return LockStats(
            count: n, entropy: entropy,
            chiSquare: chi,
            minEntropy: minEnt,
            distinct: distinct,
            topByte: topByte,
            topCount: topCount,
            runs: runs, runsZ: z)
    }

    static func lockDescribeStats(
        _ stats: LockStats,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(format: L("%lld bytes counted"), Int64(stats.count)), .sys)
        icsSay(emit, String(format: L("shannon entropy %.3f bits per byte (8.000 is a perfect spread)"), stats.entropy))
        icsSay(emit, String(format: L("min-entropy %.3f bits per byte — the busiest byte (0x%02x) carries %lld of the sample"), stats.minEntropy, Int64(stats.topByte), Int64(stats.topCount)))
        icsSay(emit, String(format: L("%lld of 256 byte values appear"), Int64(stats.distinct)))
        icsSay(emit, String(format: L("chi-square %.1f on 255 degrees of freedom — uniform bytes hover near 255; far above means some bytes crowd, far below means the spread is too even to be chance"), stats.chiSquare))
        if let z = stats.runsZ {
            let reading: String
            if abs(z) < 2 {
                reading = L("unremarkable")
            } else if z > 0 {
                reading = L("the bits alternate more than chance allows")
            } else {
                reading = L("the bits clump more than chance allows")
            }
            icsSay(emit, String(format: L("runs: %lld runs of bits, z = %.2f — %@"), Int64(stats.runs), z, reading))
        } else {
            icsSay(emit, L("the sample is all one bit value — the runs test has nothing to say"))
        }
    }

    /// entropyprobe <file> — the
    /// shape of a blob's bytes:
    /// entropy, chi-square, min-entropy
    /// and a runs pass, with the
    /// honest limits of what a sample
    /// can prove.
    static func entropyprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let file = lockReadFile(
                    arg) else {
                icsSay(emit, L("entropyprobe: give a file — entropyprobe /home/blob.bin"), .err)
                return
            }
            icsSay(emit, String(format: L("reading %@"), file.path), .sys)
            lockDescribeStats(
                lockStats([UInt8](file.data)),
                emit: emit)
            icsSay(emit, L("these are statistics of the sample, not a proof about whatever made it — a stream can score perfectly and still be predictable"))
        }
    }

    /// randprobe [file] [bytes] —
    /// the same statistics aimed at a
    /// would-be random sample; with
    /// no file, the sample is drawn
    /// from the OS generator so the
    /// bench's own yardstick can be
    /// seen working.
    static func randprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = target
                .components(
                    separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            var sample: [UInt8]?
            var source = ""
            var cap = 1 << 20
            if let first = tokens.first,
               let file = lockReadFile(
                first) {
                if tokens.count > 1,
                   let want = Int(tokens[1]) {
                    cap = want
                }
                sample = [UInt8](
                    file.data.prefix(cap))
                source = file.path
            } else {
                var want = 65536
                if let first = tokens.first,
                   let parsed = Int(first) {
                    want = parsed
                }
                want = min(max(want, 256),
                           1 << 20)
                var bytes = [UInt8](
                    repeating: 0,
                    count: want)
                let rc = SecRandomCopyBytes(
                    kSecRandomDefault,
                    want, &bytes)
                if rc == errSecSuccess {
                    sample = bytes
                    source = L("the OS generator (SecRandomCopyBytes)")
                }
            }
            guard let sample = sample else {
                icsSay(emit, L("randprobe: no sample could be drawn — give a file of would-be random bytes, or a byte count for the OS generator"), .err)
                return
            }
            icsSay(emit, String(format: L("sample: %@"), source), .sys)
            lockDescribeStats(
                lockStats(sample),
                emit: emit)
            icsSay(emit, L("a sample cannot prove a generator — these numbers describe these bytes, and a broken generator can still hand over a handsome sample"))
        }
    }

    // MARK: b64deep

    static func lockB64Decode(
        _ text: String, urlSafe: Bool)
        -> [UInt8]? {
        var t = text
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if urlSafe {
            t = t.replacingOccurrences(
                of: "-", with: "+")
                .replacingOccurrences(
                    of: "_", with: "/")
        }
        let alphabet = urlSafe
            ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
            : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        guard t.allSatisfy({
            alphabet.contains($0)
                || $0 == "="
        }) else { return nil }
        while t.count % 4 != 0 {
            t += "="
        }
        guard let data = Data(
            base64Encoded: t)
        else { return nil }
        return [UInt8](data)
    }

    static func lockB32Decode(
        _ text: String) -> [UInt8]? {
        let alphabet =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var acc = 0
        var out: [UInt8] = []
        for ch in text.uppercased() {
            if ch == "=" { break }
            guard let value = alphabet
                .firstIndex(of: ch)
            else { return nil }
            acc = (acc << 5)
                | alphabet.distance(
                    from: alphabet.startIndex,
                    to: value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(
                    (acc >> bits) & 0xFF))
            }
        }
        return out.isEmpty ? nil : out
    }

    static func lockHexDecode(
        _ text: String) -> [UInt8]? {
        let t = text
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        guard t.count >= 2,
              t.count % 2 == 0,
              t.allSatisfy({ $0.isHexDigit })
        else { return nil }
        var out: [UInt8] = []
        var i = t.startIndex
        while i < t.endIndex {
            let j = t.index(i, offsetBy: 2)
            guard let byte = UInt8(
                t[i..<j], radix: 16)
            else { return nil }
            out.append(byte)
            i = j
        }
        return out
    }

    static func lockPrintable(
        _ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty,
              let s = String(
                bytes: bytes, encoding: .utf8)
        else { return nil }
        let printable = s.unicodeScalars
            .filter {
                $0 == "\n" || $0 == "\t"
                    || ($0.value >= 0x20
                        && $0.value < 0x7F)
            }.count
        guard Double(printable)
                / Double(
                    s.unicodeScalars.count)
                > 0.92
        else { return nil }
        return s
    }

    /// Base58 (the Bitcoin alphabet)
    /// decoded on LockBig: each digit
    /// folds in as n = n × 58 + d, and
    /// leading '1's are zero bytes.
    /// The encoder exists so a decode
    /// can be proven by its roundtrip
    /// before the layer is believed.
    static func lockB58Decode(
        _ text: String) -> [UInt8]? {
        let alphabet =
            "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var value = LockBig()
        for ch in text {
            guard let index = alphabet
                .firstIndex(of: ch)
            else { return nil }
            let digit = alphabet.distance(
                from: alphabet.startIndex,
                to: index)
            value = value * LockBig(58)
                + LockBig(UInt32(digit))
        }
        var zeros = 0
        for ch in text {
            if ch == "1" {
                zeros += 1
            } else {
                break
            }
        }
        return [UInt8](
            repeating: 0, count: zeros)
            + value.toBytes()
    }

    static func lockB58Encode(
        _ bytes: [UInt8]) -> String {
        let alphabet = Array(
            "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        var zeros = 0
        for byte in bytes {
            if byte == 0 {
                zeros += 1
            } else {
                break
            }
        }
        var value = LockBig.fromBytes(
            bytes)
        var out = ""
        while !value.isZero {
            let digit = value.modSmall(58)
            out = String(alphabet[
                Int(digit)]) + out
            value = value.divmod(
                LockBig(58)).q
        }
        return String(repeating: "1",
                      count: zeros) + out
    }

    /// b64deep <string> — peel an
    /// encoded onion layer by layer
    /// (base64, base64url, base32,
    /// hex, base58), labelling each
    /// skin, until the payload shows
    /// itself or the skins run out.
    static func b64deep(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var current = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard current.count >= 4 else {
                icsSay(emit, L("b64deep: give an encoded string — b64deep aGVsbG8="), .err)
                return
            }
            var layer = 0
            while layer < 8 {
                layer += 1
                var b58: [UInt8]?
                if current.count >= 8,
                   let decoded =
                    lockB58Decode(current),
                   lockB58Encode(decoded)
                    == current {
                    b58 = decoded
                }
                let attempts: [(String,
                                [UInt8]?)] = [
                    (L("hex"), lockHexDecode(current)),
                    (L("base64"), lockB64Decode(current, urlSafe: false)),
                    (L("base64url"), lockB64Decode(current, urlSafe: true)),
                    (L("base32"), lockB32Decode(current)),
                    (L("base58"), b58),
                ]
                var decoded: (String, [UInt8])?
                for (name, result)
                    in attempts {
                    if let result = result,
                       result.count >= 1,
                       !(name == attempts[0].0
                         && result.count * 2
                            != current.count) {
                        decoded = (name, result)
                        break
                    }
                }
                guard let (name, bytes) =
                    decoded else {
                    if layer == 1 {
                        icsSay(emit, L("the string decodes as none of hex, base64, base64url, base32 or base58"), .err)
                    } else {
                        icsSay(emit, L("the onion ends — the last layer decodes no further"))
                    }
                    return
                }
                icsSay(emit, String(format: L("layer %lld: %@ → %lld bytes"), Int64(layer), name, Int64(bytes.count)), .sys)
                if let text = lockPrintable(
                    bytes) {
                    let shown = text.count
                        > 600
                        ? String(text.prefix(600))
                            + "…"
                        : text
                    icsSay(emit, String(format: L("payload, printable text: %@"), shown), .ok)
                    return
                }
                if let next = String(
                    bytes: bytes,
                    encoding: .ascii),
                   next.count >= 4 {
                    current = next
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    continue
                }
                let head = bytes.prefix(32)
                    .map {
                        String(format: "%02x", $0)
                    }.joined(separator: " ")
                icsSay(emit, String(format: L("binary — the onion ends in bytes: %@"), head))
                return
            }
            icsSay(emit, L("eight layers down and still peeling — the bench stops there; whatever this is, it was wrapped to be tedious"), .err)
        }
    }
}

extension BlacksiteBench {

    // MARK: pgpprobe

    static let lockPGPTags: [Int: String] = [
        1: "public-key-encrypted session key",
        2: "signature",
        3: "symmetric-key-encrypted session key",
        4: "one-pass signature",
        5: "secret key",
        6: "public key",
        7: "secret subkey",
        8: "compressed data",
        9: "symmetrically encrypted data",
        10: "marker",
        11: "literal data",
        12: "trust",
        13: "user ID",
        14: "public subkey",
        17: "user attribute",
        18: "encrypted data (integrity protected)",
        19: "modification detection code",
    ]

    static let lockPGPAlgos: [Int: String] = [
        1: "RSA", 2: "RSA (encrypt only)",
        3: "RSA (sign only)", 16: "Elgamal",
        17: "DSA", 18: "ECDH", 19: "ECDSA",
        21: "diffie-hellman (X9.42)",
        22: "EdDSA", 23: "AEDH", 24: "AEDSA",
    ]

    /// Walk RFC 4880 packets. A
    /// partial or indeterminate
    /// length stops the walk where it
    /// stands and says so — the census
    /// never guesses past a length it
    /// cannot read.
    static func pgpprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("pgpprobe: give a PGP file (binary or armoured) — pgpprobe /home/pubkey.asc"), .err)
                return
            }
            var bytes: [UInt8]?
            if arg.hasPrefix(
                "-----BEGIN PGP") {
                bytes = lockPEMBlocks(arg)
                    .first?.der
            } else if let file =
                lockReadFile(arg) {
                let raw = [UInt8](file.data)
                if let text = String(
                    bytes: raw,
                    encoding: .utf8),
                   text.contains(
                    "-----BEGIN PGP") {
                    bytes = lockPEMBlocks(
                        text).first?.der
                } else {
                    bytes = raw
                }
                if bytes != nil {
                    icsSay(emit, String(format: L("reading %@"), file.path), .sys)
                }
            }
            guard let data = bytes,
                  !data.isEmpty else {
                icsSay(emit, L("nothing readable at that path, and the argument is not PGP armour"), .err)
                return
            }
            var pos = 0
            var count = 0
            var stopped: String?
            while pos < data.count {
                let head = data[pos]
                guard head & 0x80 != 0 else {
                    stopped = L("a byte that is not a packet header — the walk stops there")
                    break
                }
                pos += 1
                let tag: Int
                var length = 0
                if head & 0x40 != 0 {
                    tag = Int(head & 0x3F)
                    guard pos < data.count
                    else { break }
                    let lb = Int(data[pos])
                    pos += 1
                    if lb < 192 {
                        length = lb
                    } else if lb < 224 {
                        guard pos < data.count
                        else { break }
                        length = (lb - 192)
                            << 8
                            | Int(data[pos])
                            + 192
                        pos += 1
                    } else if lb == 255 {
                        guard pos + 4
                                <= data.count
                        else { break }
                        for k in 0..<4 {
                            length = length
                                << 8
                                | Int(data[
                                    pos + k])
                        }
                        pos += 4
                    } else {
                        stopped = String(format: L("packet %lld uses partial lengths — the walk stops there rather than guess"), Int64(count + 1))
                        break
                    }
                } else {
                    tag = Int(head >> 2) & 0x0F
                    switch head & 3 {
                    case 0:
                        guard pos < data.count
                        else { break }
                        length = Int(data[pos])
                        pos += 1
                    case 1:
                        guard pos + 2
                                <= data.count
                        else { break }
                        length = Int(data[pos])
                            << 8
                            | Int(data[pos + 1])
                        pos += 2
                    case 2:
                        guard pos + 4
                                <= data.count
                        else { break }
                        for k in 0..<4 {
                            length = length
                                << 8
                                | Int(data[
                                    pos + k])
                        }
                        pos += 4
                    default:
                        stopped = String(format: L("packet %lld carries an indeterminate length — the walk stops there"), Int64(count + 1))
                    }
                    if stopped != nil {
                        break
                    }
                }
                guard pos + length
                        <= data.count else {
                    stopped = L("a packet claims more bytes than the file holds — the walk stops there")
                    break
                }
                let body = Array(
                    data[pos..<(pos + length)])
                pos += length
                count += 1
                let name = lockPGPTags[tag]
                    ?? String(format: L("tag %lld (unassigned or private)"), Int64(tag))
                icsSay(emit, String(format: L("packet %lld: %@ (%lld bytes)"), Int64(count), name, Int64(length)), count == 1 ? .sys : .out)
                if tag == 6 || tag == 14
                    || tag == 5 || tag == 7 {
                    lockDescribePGPKey(
                        body: body,
                        subkey: tag == 14
                            || tag == 7,
                        emit: emit)
                } else if tag == 13 {
                    let uid = String(
                        bytes: body,
                        encoding: .utf8) ?? ""
                    icsSay(emit, String(format: L("  user ID: %@"), uid))
                } else if tag == 2,
                          body.count >= 4 {
                    let version = Int(body[0])
                    let kind = Int(body[1])
                    let pk = lockPGPAlgos[
                        Int(body[2])]
                        ?? "?"
                    icsSay(emit, String(format: L("  signature v%lld, type 0x%02x, %@ over hash algorithm %lld"), Int64(version), Int64(kind), pk, Int64(body[3])))
                }
            }
            if let stopped = stopped {
                icsSay(emit, stopped, .err)
            }
            if count > 0 {
                icsSay(emit, String(format: L("%lld packets walked"), Int64(count)), .sys)
            } else {
                icsSay(emit, L("no PGP packet parses out of these bytes"), .err)
            }
        }
    }

    static func lockDescribePGPKey(
        body: [UInt8], subkey: Bool,
        emit: @escaping BlacksiteEmit) {
        guard body.count >= 6 else {
            return
        }
        let version = Int(body[0])
        let created = UInt32(body[1]) << 24
            | UInt32(body[2]) << 16
            | UInt32(body[3]) << 8
            | UInt32(body[4])
        let algo = Int(body[5])
        let when = lockDateString(
            Date(timeIntervalSince1970:
                    Double(created)))
        icsSay(emit, String(format: L("  key v%lld, made %@, algorithm %@"), Int64(version), when, lockPGPAlgos[algo] ?? String(format: L("algorithm %lld"), Int64(algo))))
        if version == 4 {
            var material = [UInt8(0x99)]
            material.append(UInt8(
                (body.count >> 8) & 0xFF))
            material.append(UInt8(
                body.count & 0xFF))
            material += body
            let fpr = Insecure.SHA1.hash(
                data: Data(material))
                .map {
                    String(format: "%02X", $0)
                }.joined()
            icsSay(emit, String(format: L("  fingerprint: %@"), fpr))
            icsSay(emit, String(format: L("  key ID: %@"), String(fpr.suffix(16))))
        }
        if algo == 1 || algo == 2
            || algo == 3 {
            // RSA: the first MPI is the
            // modulus.
            var at = 6
            if at + 2 <= body.count {
                let bits = Int(body[at])
                    << 8 | Int(body[at + 1])
                icsSay(emit, String(format: L("  RSA modulus: %lld bits"), Int64(bits)))
                if bits < 2048 {
                    icsSay(emit, L("  under 2048 bits — below the modern floor"), .err)
                }
            }
        }
        if subkey {
            icsSay(emit, L("  (a subkey — it works under the primary above)"))
        }
    }

    // MARK: sshkeydeep

    /// Read one line off a socket,
    /// byte at a time, for the SSH
    /// banner exchange.
    static func lockReadLine(
        fd: Int32, cap: Int) -> String? {
        var bytes: [UInt8] = []
        while bytes.count < cap {
            guard let one = icsReadExact(
                fd, 1) else {
                return bytes.isEmpty
                    ? nil
                    : String(bytes: bytes,
                             encoding: .ascii)
            }
            bytes.append(one[0])
            if one[0] == 0x0A {
                break
            }
        }
        return String(bytes: bytes,
                      encoding: .ascii)
    }

    static func lockSSHReadString(
        _ bytes: [UInt8], _ pos: inout Int)
        -> [UInt8]? {
        guard pos + 4 <= bytes.count
        else { return nil }
        let n = Int(bytes[pos]) << 24
            | Int(bytes[pos + 1]) << 16
            | Int(bytes[pos + 2]) << 8
            | Int(bytes[pos + 3])
        pos += 4
        guard n >= 0,
              pos + n <= bytes.count
        else { return nil }
        defer { pos += n }
        return Array(bytes[pos..<(pos + n)])
    }

    /// sshkeydeep <host|file> — for a
    /// host: the offered algorithm
    /// lists off its KEXINIT and the
    /// host key it presents, captured
    /// by the house SSH client and
    /// pinned to nothing. For a file:
    /// every key in an authorized_keys
    /// or .pub file, fingerprinted.
    static func sshkeydeep(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("sshkeydeep: give a host or a key file — sshkeydeep github.com"), .err)
                return
            }
            if let file = lockReadFile(arg) {
                icsSay(emit, String(format: L("reading %@"), file.path), .sys)
                lockSSHFileCensus(
                    file.data, emit: emit)
                return
            }
            guard let resolved = icsResolve(
                arg, 22) else {
                icsSay(emit, L("sshkeydeep: give a host or a key file — sshkeydeep github.com"), .err)
                return
            }
            let host = resolved.host
            let port = resolved.port
            let ip = resolved.ip
            icsSay(emit, String(format: L("%@ — the SSH door at %@:%lld"), host, ip, Int64(port)), .sys)
            // The KEXINIT census: one
            // knock, the offered lists
            // read, nothing agreed.
            if let fd = icsSocket(
                ip: ip, port: UInt16(clamping: port),
                timeout: 6) {
                defer { close(fd) }
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 3)
                if let banner =
                    lockReadLine(fd: fd,
                                 cap: 512) {
                    icsSay(emit, String(format: L("banner: %@"), banner.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                var cookie = [UInt8](
                    repeating: 0,
                    count: 16)
                _ = SecRandomCopyBytes(
                    kSecRandomDefault, 16,
                    &cookie)
                var mine = Data([0x14])
                mine.append(contentsOf: cookie)
                let lists: [[String]] = [
                    ["curve25519-sha256",
                     "curve25519-sha256@libssh.org",
                     "ecdh-sha2-nistp256",
                     "diffie-hellman-group14-sha256"],
                    ["ssh-ed25519",
                     "ecdsa-sha2-nistp256"],
                    ["aes256-gcm@openssh.com",
                     "aes128-gcm@openssh.com",
                     "aes256-ctr", "aes128-ctr"],
                    ["aes256-gcm@openssh.com",
                     "aes128-gcm@openssh.com",
                     "aes256-ctr", "aes128-ctr"],
                    ["hmac-sha2-512",
                     "hmac-sha2-256"],
                    ["hmac-sha2-512",
                     "hmac-sha2-256"],
                    ["none"], ["none"],
                ]
                for list in lists {
                    let joined = list.joined(
                        separator: ",")
                    mine.append(
                        contentsOf: lockSSHString(
                            Array(joined.utf8)))
                }
                mine.append(
                    contentsOf: lockSSHString([]))
                mine.append(
                    contentsOf: lockSSHString([]))
                mine.append(0)
                mine.append(contentsOf: [
                    0, 0, 0, 0])
                var pad = 8
                    - ((mine.count + 5) % 8)
                if pad < 4 { pad += 8 }
                var packet = Data()
                let total = mine.count
                    + pad + 1
                packet.append(UInt8(
                    (total >> 24) & 0xFF))
                packet.append(UInt8(
                    (total >> 16) & 0xFF))
                packet.append(UInt8(
                    (total >> 8) & 0xFF))
                packet.append(UInt8(
                    total & 0xFF))
                packet.append(UInt8(pad))
                packet.append(mine)
                packet.append(Data(
                    repeating: 0,
                    count: pad))
                _ = [UInt8](packet)
                    .withUnsafeBytes {
                        send(fd, $0.baseAddress,
                             packet.count, 0)
                    }
                if let head = icsReadExact(
                    fd, 4) {
                    let plen = Int(head[0])
                        << 24
                        | Int(head[1]) << 16
                        | Int(head[2]) << 8
                        | Int(head[3])
                    if plen > 0,
                       plen <= 35000,
                       let rest =
                        icsReadExact(
                            fd, plen),
                       rest.count >= 1 {
                        let padlen = Int(
                            rest[0])
                        let payload = Array(
                            rest.dropFirst()
                                .prefix(
                                    plen - 1
                                        - padlen))
                        if payload.first
                            == 0x14 {
                            lockDescribeKEXINIT(
                                payload,
                                emit: emit)
                        }
                    }
                }
            } else {
                icsSay(emit, L("the door did not answer a plain knock"), .err)
            }
            // The presented host key,
            // captured by the house
            // client; its trust gate
            // refuses unknown keys, which
            // is exactly what a census
            // wants — the key is read
            // before the refusal, and
            // nothing is pinned.
            let client = SSHClient(
                host: host, port: Int(port),
                user: "bench")
            client.timeout = 8
            do {
                try client.handshake()
            } catch {
                // The refusal is the
                // expected road for an
                // unpinned host.
            }
            let blob = client.hostKeyBlob
            if !blob.isEmpty {
                let bytes = [UInt8](blob)
                icsSay(emit, String(format: L("the host presents a %@ key:"), client.hostAlgorithm), .sys)
                if let parsed =
                    lockParseSSHBlob(bytes) {
                    lockDescribeSSHBlob(
                        parsed, blob: bytes,
                        emit: emit)
                } else {
                    let digest = SHA256.hash(
                        data: blob)
                    let b64 = Data(digest)
                        .base64EncodedString()
                        .replacingOccurrences(
                            of: "=", with: "")
                    icsSay(emit, String(format: L("OpenSSH SHA256 fingerprint: %@"), b64))
                }
                if let known = CryptoSuite
                    .NetCred.knownKey(
                        host: host,
                        port: Int(port)) {
                    if Data(bytes) == known {
                        icsSay(emit, L("the presented key MATCHES the copy pinned in the house book"), .ok)
                    } else {
                        icsSay(emit, L("the presented key does NOT match the pinned copy — treat this door as a stranger wearing a familiar number"), .err)
                    }
                } else {
                    icsSay(emit, L("this host is not pinned in the house book — the key above was read, not trusted, and nothing was saved"))
                }
            } else {
                icsSay(emit, L("the handshake never reached a host key — the door may want another greeting, or speak no SSH at all"), .err)
            }
            client.disconnect()
        }
    }

    static func lockDescribeKEXINIT(
        _ payload: [UInt8],
        emit: @escaping BlacksiteEmit) {
        var pos = 17
        var lists: [[String]] = []
        for _ in 0..<10 {
            guard let raw =
                lockSSHReadString(
                    payload, &pos)
            else { return }
            let text = String(
                bytes: raw, encoding: .ascii)
                ?? ""
            lists.append(text.isEmpty
                         ? []
                         : text.components(
                            separatedBy: ","))
        }
        let labels = [
            L("key exchange"), L("host keys"),
            L("ciphers out"), L("ciphers in"),
            L("MACs out"), L("MACs in"),
            L("compression out"),
            L("compression in"),
            L("languages out"),
            L("languages in"),
        ]
        for (i, list) in lists.enumerated()
            where !list.isEmpty {
            icsSay(emit, String(format: L("%@: %@"), labels[i], list.joined(separator: " ")))
        }
        if let hostKeys = lists.dropFirst()
            .first,
           hostKeys.allSatisfy({
               $0 == "ssh-rsa"
           }) {
            icsSay(emit, L("the door offers only SHA-1-era RSA host keys (ssh-rsa) — modern clients refuse those signatures"), .err)
        }
    }

    static func lockSSHFileCensus(
        _ data: Data,
        emit: @escaping BlacksiteEmit) {
        guard let text = String(
            bytes: [UInt8](data),
            encoding: .utf8) else {
            icsSay(emit, L("not a text key file — keyprobe reads bare DER and PEM"), .err)
            return
        }
        var found = 0
        for raw in text.components(
            separatedBy: .newlines) {
            let line = raw
                .trimmingCharacters(
                    in: .whitespaces)
            if line.isEmpty
                || line.hasPrefix("#") {
                continue
            }
            let parts = line.components(
                separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 2 else {
                continue
            }
            // authorized_keys lines may
            // carry an options field
            // first; find the type token.
            var typeIndex: Int?
            for (i, part) in parts
                .enumerated() {
                if part.hasPrefix("ssh-")
                    || part.hasPrefix(
                        "ecdsa-")
                    || part.hasPrefix(
                        "sk-") {
                    typeIndex = i
                    break
                }
            }
            guard let ti = typeIndex,
                  ti + 1 < parts.count,
                  let blobData = Data(
                    base64Encoded:
                        parts[ti + 1]),
                  let parsed =
                    lockParseSSHBlob(
                        [UInt8](blobData))
            else { continue }
            found += 1
            let comment = parts
                .dropFirst(ti + 2)
                .joined(separator: " ")
            if !comment.isEmpty {
                icsSay(emit, String(format: L("— %@ —"), comment), .sys)
            }
            lockDescribeSSHBlob(
                parsed, blob: [UInt8](blobData),
                emit: emit)
        }
        if found == 0 {
            if let first = lockPEMBlocks(
                text).first,
               let info = lockParseSPKI(
                first.der) {
                icsSay(emit, L("a PEM public key rather than an OpenSSH file — read as DER:"))
                lockDescribeKey(
                    info, der: first.der,
                    emit: emit)
                return
            }
            icsSay(emit, L("no OpenSSH public keys stand in that file"), .err)
        } else {
            icsSay(emit, String(format: L("%lld keys in the file"), Int64(found)), .sys)
        }
    }
}

extension BlacksiteBench {

    // MARK: tlscensus

    struct LockKnock {
        var answered: Bool
        var trust: SecTrust?
        var cipher: UInt32
    }

    /// One TLS knock on a fresh
    /// socket: pin the version range
    /// (and optionally a single
    /// enabled suite), break on
    /// server auth, and report what
    /// the moment of the papers
    /// showed. The Wave 3 road.
    ///
    /// DELIBERATE HOLDOUT (v12 audit,
    /// adjudicated): the version and
    /// suite pinning below rides the
    /// deprecated SecureTransport stack
    /// on purpose — grading retired
    /// TLS versions is this verb's job,
    /// and the standing Network stack
    /// will not offer them. Known and
    /// accepted warnings, not drift.
    static func lockTLSKnock(
        ip: String, port: Int,
        host: String,
        minV: SSLProtocol,
        maxV: SSLProtocol,
        onlySuite: UInt32?)
        -> LockKnock {
        var result = LockKnock(
            answered: false, trust: nil,
            cipher: 0)
        guard let fd = icsSocket(
            ip: ip, port: UInt16(clamping: port),
            timeout: 5) else {
            return result
        }
        defer { close(fd) }
        let box = LockTLSBox(fd: fd)
        let retained = Unmanaged
            .passRetained(box)
        defer { retained.release() }
        guard let ctx = SSLCreateContext(
            nil, .clientSide, .streamType)
        else { return result }
        defer { _ = SSLClose(ctx) }
        _ = SSLSetIOFuncs(
            ctx, blacksiteLockTLSRead,
            blacksiteLockTLSWrite)
        _ = SSLSetConnection(
            ctx, retained.toOpaque())
        _ = host.withCString {
            SSLSetPeerDomainName(
                ctx, $0, host.utf8.count)
        }
        _ = SSLSetSessionOption(
            ctx, .breakOnServerAuth, true)
        _ = SSLSetProtocolVersionMin(
            ctx, minV)
        _ = SSLSetProtocolVersionMax(
            ctx, maxV)
        if let suite = onlySuite {
            var suites: [SSLCipherSuite] =
                [SSLCipherSuite(suite)]
            _ = SSLSetEnabledCiphers(
                ctx, &suites, suites.count)
        }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 2)
        let status = SSLHandshake(ctx)
        guard status == -9841
                || status == 0 else {
            return result
        }
        result.answered = true
        var trust: SecTrust?
        if SSLCopyPeerTrust(ctx, &trust)
            == errSecSuccess {
            result.trust = trust
        }
        var cipher: SSLCipherSuite = 0
        if SSLGetNegotiatedCipher(
            ctx, &cipher) == errSecSuccess {
            result.cipher = UInt32(cipher)
        }
        return result
    }

    /// tlscensus <host> — which TLS
    /// versions answer, which cipher
    /// families the door still shares
    /// (one representative suite per
    /// family — a census, not a sweep
    /// of every suite), the suite a
    /// modern handshake lands on, and
    /// the papers chained in.
    static func tlscensus(
        target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("tlscensus: give a host — tlscensus example.com"), .err)
                return
            }
            guard let resolved = icsResolve(
                arg, 443) else {
                icsSay(emit, L("tlscensus: give a host — tlscensus example.com"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            let port = resolved.port
            icsSay(emit, String(format: L("%@ — the TLS door at %@:%lld"), host, ip, Int64(port)), .sys)
            let versions: [(String,
                            SSLProtocol)] = [
                ("TLS 1.3", .tlsProtocol13),
                ("TLS 1.2", .tlsProtocol12),
                ("TLS 1.1", .tlsProtocol11),
            ]
            var answered: [String] = []
            var firstTrust: SecTrust?
            var sawModern = false
            for (name, proto) in versions {
                if stopped() { break }
                let knock = lockTLSKnock(
                    ip: ip, port: Int(port),
                    host: host, minV: proto,
                    maxV: proto,
                    onlySuite: nil)
                if knock.answered {
                    answered.append(name)
                    if firstTrust == nil {
                        firstTrust =
                            knock.trust
                    }
                    if name == "TLS 1.3"
                        || name == "TLS 1.2" {
                        sawModern = true
                        if let suite =
                            lockSuiteLine(
                                code: knock
                                    .cipher) {
                            icsSay(emit, String(format: L("%@ answers — a modern handshake lands on %@"), name, suite))
                        } else {
                            icsSay(emit, String(format: L("%@ answers"), name))
                        }
                    } else {
                        icsSay(emit, String(format: L("%@ answers — a version the modern web has retired"), name), .err)
                    }
                }
            }
            guard !answered.isEmpty else {
                icsSay(emit, L("no TLS version answered — the door is shut, or what stands there speaks no TLS"), .err)
                return
            }
            if !sawModern {
                icsSay(emit, L("nothing modern answers: TLS 1.2 and 1.3 both stayed silent"), .err)
            }
            // Cipher families on TLS 1.2
            // — one representative
            // suite each.
            let families: [(String,
                            UInt32, Bool)] = [
                ("ECDHE + AES-GCM", 0xC02F, false),
                ("ECDHE + ChaCha20", 0xCCA8, false),
                ("ECDHE + CBC/SHA-256", 0xC027, false),
                ("ECDHE + CBC/SHA-1", 0xC013, true),
                ("DHE + AES-GCM", 0x009E, false),
                ("DHE + CBC/SHA-1", 0x0033, true),
                ("RSA transport + AES-GCM", 0x009C, true),
                ("RSA transport + CBC/SHA-1", 0x002F, true),
                ("RSA + 3DES", 0x000A, true),
                ("RSA + RC4", 0x0005, true),
            ]
            var oldShared: [String] = []
            for (family, suite, dated)
                in families {
                if stopped() { break }
                let knock = lockTLSKnock(
                    ip: ip, port: Int(port),
                    host: host,
                    minV: .tlsProtocol12,
                    maxV: .tlsProtocol12,
                    onlySuite: suite)
                if knock.answered {
                    icsSay(emit, String(format: L("TLS 1.2 still shares: %@"), family), dated ? .err : .out)
                    if dated {
                        oldShared.append(
                            family)
                    }
                }
            }
            if oldShared.isEmpty {
                icsSay(emit, L("none of the dated families answered — the door keeps a modern shelf"), .ok)
            } else {
                icsSay(emit, String(format: L("dated families still shared: %@ — a client that asks for yesterday can still be served it"), oldShared.joined(separator: ", ")), .err)
            }
            if let trust = firstTrust,
               let leaf = certChain(trust)
                .first,
               let data =
                SecCertificateCopyData(leaf)
                as Data? {
                if let cert = lockCertParse(
                    [UInt8](data)) {
                    icsSay(emit, String(format: L("the leaf paper: %@ — issued by %@"), cert.subjectLine, cert.issuerLine), .sys)
                    let sig = lockSigName(
                        cert.sigOID)
                    icsSay(emit, String(format: L("signed %@%@"), sig.name, sig.weak ? L(" — a dying hash") : ""))
                    if let na = cert.notAfter {
                        let days = Int(
                            na.timeIntervalSinceNow
                                / 86400)
                        icsSay(emit, String(format: L("%lld days of validity left"), Int64(days)))
                    }
                }
                let count =
                    SecTrustGetCertificateCount(
                        trust)
                icsSay(emit, String(format: L("the handshake showed %lld papers"), Int64(count)))
            }
        }
    }

    // MARK: cipherprobe

    struct LockSuite {
        var name: String
        var kex: String
        var auth: String
        var enc: String
        var mac: String
    }

    /// The bench's shelf of named
    /// suites (IANA registry values).
    /// Every row round-trips through
    /// the name parser beside it —
    /// that round-trip was the
    /// verification, run before the
    /// Swift existed.
    static let lockSuites: [UInt32: LockSuite] = [
        0x1301: LockSuite(name: "TLS_AES_128_GCM_SHA256", kex: "TLS1.3", auth: "TLS1.3", enc: "AES-128-GCM", mac: "AEAD"),
        0x1302: LockSuite(name: "TLS_AES_256_GCM_SHA384", kex: "TLS1.3", auth: "TLS1.3", enc: "AES-256-GCM", mac: "AEAD"),
        0x1303: LockSuite(name: "TLS_CHACHA20_POLY1305_SHA256", kex: "TLS1.3", auth: "TLS1.3", enc: "CHACHA20-POLY1305", mac: "AEAD"),
        0x1304: LockSuite(name: "TLS_AES_128_CCM_SHA256", kex: "TLS1.3", auth: "TLS1.3", enc: "AES-128-CCM", mac: "AEAD"),
        0x1305: LockSuite(name: "TLS_AES_128_CCM_8_SHA256", kex: "TLS1.3", auth: "TLS1.3", enc: "AES-128-CCM-8", mac: "AEAD"),
        0xC02B: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256", kex: "ECDHE", auth: "ECDSA", enc: "AES-128-GCM", mac: "AEAD"),
        0xC02C: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384", kex: "ECDHE", auth: "ECDSA", enc: "AES-256-GCM", mac: "AEAD"),
        0xC02F: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", kex: "ECDHE", auth: "RSA", enc: "AES-128-GCM", mac: "AEAD"),
        0xC030: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384", kex: "ECDHE", auth: "RSA", enc: "AES-256-GCM", mac: "AEAD"),
        0xCCA8: LockSuite(name: "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256", kex: "ECDHE", auth: "RSA", enc: "CHACHA20-POLY1305", mac: "AEAD"),
        0xCCA9: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256", kex: "ECDHE", auth: "ECDSA", enc: "CHACHA20-POLY1305", mac: "AEAD"),
        0xCCAA: LockSuite(name: "TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256", kex: "DHE", auth: "RSA", enc: "CHACHA20-POLY1305", mac: "AEAD"),
        0x009E: LockSuite(name: "TLS_DHE_RSA_WITH_AES_128_GCM_SHA256", kex: "DHE", auth: "RSA", enc: "AES-128-GCM", mac: "AEAD"),
        0x009F: LockSuite(name: "TLS_DHE_RSA_WITH_AES_256_GCM_SHA384", kex: "DHE", auth: "RSA", enc: "AES-256-GCM", mac: "AEAD"),
        0xC023: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256", kex: "ECDHE", auth: "ECDSA", enc: "AES-128-CBC", mac: "SHA256"),
        0xC024: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384", kex: "ECDHE", auth: "ECDSA", enc: "AES-256-CBC", mac: "SHA384"),
        0xC027: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256", kex: "ECDHE", auth: "RSA", enc: "AES-128-CBC", mac: "SHA256"),
        0xC028: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384", kex: "ECDHE", auth: "RSA", enc: "AES-256-CBC", mac: "SHA384"),
        0xC009: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA", kex: "ECDHE", auth: "ECDSA", enc: "AES-128-CBC", mac: "SHA1"),
        0xC00A: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA", kex: "ECDHE", auth: "ECDSA", enc: "AES-256-CBC", mac: "SHA1"),
        0xC013: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA", kex: "ECDHE", auth: "RSA", enc: "AES-128-CBC", mac: "SHA1"),
        0xC014: LockSuite(name: "TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA", kex: "ECDHE", auth: "RSA", enc: "AES-256-CBC", mac: "SHA1"),
        0xC012: LockSuite(name: "TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA", kex: "ECDHE", auth: "RSA", enc: "3DES-CBC", mac: "SHA1"),
        0xC008: LockSuite(name: "TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA", kex: "ECDHE", auth: "ECDSA", enc: "3DES-CBC", mac: "SHA1"),
        0xC017: LockSuite(name: "TLS_ECDH_anon_WITH_AES_128_CBC_SHA", kex: "ECDH-anon", auth: "none", enc: "AES-128-CBC", mac: "SHA1"),
        0xC015: LockSuite(name: "TLS_ECDH_anon_WITH_RC4_128_SHA", kex: "ECDH-anon", auth: "none", enc: "RC4", mac: "SHA1"),
        0x009C: LockSuite(name: "TLS_RSA_WITH_AES_128_GCM_SHA256", kex: "RSA", auth: "RSA", enc: "AES-128-GCM", mac: "AEAD"),
        0x009D: LockSuite(name: "TLS_RSA_WITH_AES_256_GCM_SHA384", kex: "RSA", auth: "RSA", enc: "AES-256-GCM", mac: "AEAD"),
        0x003C: LockSuite(name: "TLS_RSA_WITH_AES_128_CBC_SHA256", kex: "RSA", auth: "RSA", enc: "AES-128-CBC", mac: "SHA256"),
        0x003D: LockSuite(name: "TLS_RSA_WITH_AES_256_CBC_SHA384", kex: "RSA", auth: "RSA", enc: "AES-256-CBC", mac: "SHA384"),
        0x002F: LockSuite(name: "TLS_RSA_WITH_AES_128_CBC_SHA", kex: "RSA", auth: "RSA", enc: "AES-128-CBC", mac: "SHA1"),
        0x0035: LockSuite(name: "TLS_RSA_WITH_AES_256_CBC_SHA", kex: "RSA", auth: "RSA", enc: "AES-256-CBC", mac: "SHA1"),
        0x000A: LockSuite(name: "TLS_RSA_WITH_3DES_EDE_CBC_SHA", kex: "RSA", auth: "RSA", enc: "3DES-CBC", mac: "SHA1"),
        0x0005: LockSuite(name: "TLS_RSA_WITH_RC4_128_SHA", kex: "RSA", auth: "RSA", enc: "RC4", mac: "SHA1"),
        0x0004: LockSuite(name: "TLS_RSA_WITH_RC4_128_MD5", kex: "RSA", auth: "RSA", enc: "RC4", mac: "MD5"),
        0x0001: LockSuite(name: "TLS_RSA_WITH_NULL_MD5", kex: "RSA", auth: "RSA", enc: "NULL", mac: "MD5"),
        0x0002: LockSuite(name: "TLS_RSA_WITH_NULL_SHA", kex: "RSA", auth: "RSA", enc: "NULL", mac: "SHA1"),
        0x0016: LockSuite(name: "TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA", kex: "DHE", auth: "RSA", enc: "3DES-CBC", mac: "SHA1"),
        0x0033: LockSuite(name: "TLS_DHE_RSA_WITH_AES_128_CBC_SHA", kex: "DHE", auth: "RSA", enc: "AES-128-CBC", mac: "SHA1"),
        0x0039: LockSuite(name: "TLS_DHE_RSA_WITH_AES_256_CBC_SHA", kex: "DHE", auth: "RSA", enc: "AES-256-CBC", mac: "SHA1"),
        0x0067: LockSuite(name: "TLS_DHE_RSA_WITH_AES_128_CBC_SHA256", kex: "DHE", auth: "RSA", enc: "AES-128-CBC", mac: "SHA256"),
        0x006B: LockSuite(name: "TLS_DHE_RSA_WITH_AES_256_CBC_SHA256", kex: "DHE", auth: "RSA", enc: "AES-256-CBC", mac: "SHA256"),
        0x0084: LockSuite(name: "TLS_RSA_WITH_CAMELLIA_128_CBC_SHA", kex: "RSA", auth: "RSA", enc: "CAMELLIA-128-CBC", mac: "SHA1"),
        0x0088: LockSuite(name: "TLS_DHE_RSA_WITH_CAMELLIA_256_CBC_SHA", kex: "DHE", auth: "RSA", enc: "CAMELLIA-256-CBC", mac: "SHA1"),
        0xC01A: LockSuite(name: "TLS_SRP_SHA_RSA_WITH_AES_128_CBC_SHA", kex: "SRP", auth: "RSA", enc: "AES-128-CBC", mac: "SHA1"),
        0x008C: LockSuite(name: "TLS_PSK_WITH_AES_128_CBC_SHA", kex: "PSK", auth: "PSK", enc: "AES-128-CBC", mac: "SHA1"),
        0x00A8: LockSuite(name: "TLS_PSK_WITH_AES_128_GCM_SHA256", kex: "PSK", auth: "PSK", enc: "AES-128-GCM", mac: "AEAD"),
    ]

    static func lockSuiteGrade(
        _ suite: LockSuite) -> (text: String,
                                 bad: Bool,
                                 dated: Bool) {
        if suite.enc == "NULL" {
            return (L("broken — this suite encrypts nothing at all"), true, false)
        }
        if suite.enc == "RC4" {
            return (L("broken — RC4's biases are public knowledge; no modern client offers it"), true, false)
        }
        if suite.auth == "none"
            || suite.kex.hasSuffix("-anon") {
            return (L("broken — anonymous key exchange: no one is authenticated, anyone can stand in the middle"), true, false)
        }
        if suite.enc.hasPrefix("3DES") {
            return (L("dated — 3DES is a legacy cipher; Sweet32 made its 64-bit block a liability"), false, true)
        }
        if suite.kex == "RSA" {
            return (L("dated — RSA key transport has no forward secrecy: record today, decrypt the day the key leaks"), false, true)
        }
        if suite.mac == "SHA1"
            || suite.mac == "MD5" {
            return (L("dated — a SHA-1-era MAC under CBC; serviceable once, retired now"), false, true)
        }
        return (L("current — forward secrecy and modern primitives"), false, false)
    }

    static func lockDescribeSuite(
        _ suite: LockSuite,
        code: UInt32?,
        emit: @escaping BlacksiteEmit) {
        if let code = code {
            icsSay(emit, String(format: L("%@ (0x%04x)"), suite.name, Int64(code)), .sys)
        } else {
            icsSay(emit, suite.name, .sys)
        }
        icsSay(emit, String(format: L("key exchange %@ · authentication %@ · cipher %@ · integrity %@"), suite.kex, suite.auth, suite.enc, suite.mac))
        let grade = lockSuiteGrade(suite)
        icsSay(emit, grade.text,
               grade.bad ? .err : .out)
    }

    /// One line naming a suite by
    /// code, for the census verbs.
    static func lockSuiteLine(
        code: UInt32) -> String? {
        guard let suite = lockSuites[code]
        else { return nil }
        return suite.name
            + " (" + suite.enc + ")"
    }

    /// The name parser: an IANA name
    /// (TLS_ECDHE_RSA_WITH_AES_128_
    /// GCM_SHA256) or an OpenSSL
    /// spelling (ECDHE-RSA-AES128-
    /// GCM-SHA256, AES128-SHA) read
    /// into its components. Parsed,
    /// not tabulated — the output
    /// says which road it took.
    static func lockParseSuiteName(
        _ raw: String) -> LockSuite? {
        let upper = raw.uppercased()
        if upper.contains("-"),
           !upper.hasPrefix("TLS_") {
            return lockParseOpenSSLName(
                upper)
        }
        var s = upper.replacingOccurrences(
            of: "-", with: "_")
        if s.hasPrefix("TLS_") {
            s = String(s.dropFirst(4))
        }
        let parts = s.components(
            separatedBy: "_WITH_")
        let head = parts[0]
        var core = head
        for suffix in ["_SHA256",
                       "_SHA384"] {
            if core.hasSuffix(suffix) {
                core = String(core
                    .dropLast(suffix.count))
            }
        }
        let tls13: [String: String] = [
            "AES_128_GCM": "AES-128-GCM",
            "AES_256_GCM": "AES-256-GCM",
            "CHACHA20_POLY1305":
                "CHACHA20-POLY1305",
            "AES_128_CCM": "AES-128-CCM",
            "AES_128_CCM_8": "AES-128-CCM-8",
        ]
        if parts.count == 1,
           let enc = tls13[core] {
            return LockSuite(
                name: raw, kex: "TLS1.3",
                auth: "TLS1.3", enc: enc,
                mac: "AEAD")
        }
        guard parts.count == 2 else {
            return nil
        }
        let tail = parts[1]
        let toks = head.components(
            separatedBy: "_")
        var kex = toks[0]
        var auth = "none"
        if toks[0] == "ECDHE",
           toks.count > 1 {
            auth = toks[1]
        } else if toks[0] == "DHE"
                    || toks[0] == "DH" {
            if toks.count > 1 {
                auth = toks[1]
            }
        } else if toks[0] == "ECDH" {
            if toks.count > 1,
               toks[1] == "ANON" {
                kex = "ECDH-anon"
                auth = "none"
            } else {
                kex = "ECDH"
                if toks.count > 1 {
                    auth = toks[1]
                }
            }
        } else if toks[0] == "RSA" {
            kex = "RSA"
            auth = "RSA"
        } else if toks[0] == "SRP" {
            kex = "SRP"
            auth = toks.count > 2
                ? toks[2] : "SRP"
        } else if toks[0] == "PSK" {
            kex = "PSK"
            auth = "PSK"
        }
        var mac = tail.components(
            separatedBy: "_").last ?? ""
        if mac == "SHA" { mac = "SHA1" }
        var enc = tail
        if tail.hasPrefix("AES_128_GCM") {
            enc = "AES-128-GCM"
            mac = "AEAD"
        } else if tail.hasPrefix(
            "AES_256_GCM") {
            enc = "AES-256-GCM"
            mac = "AEAD"
        } else if tail.hasPrefix(
            "CHACHA20") {
            enc = "CHACHA20-POLY1305"
            mac = "AEAD"
        } else if tail.hasPrefix(
            "AES_128_CCM") {
            enc = "AES-128-CCM"
            mac = "AEAD"
        } else if tail.hasPrefix(
            "AES_128") {
            enc = "AES-128-CBC"
        } else if tail.hasPrefix(
            "AES_256") {
            enc = "AES-256-CBC"
        } else if tail.hasPrefix("3DES") {
            enc = "3DES-CBC"
        } else if tail.hasPrefix("RC4") {
            enc = "RC4"
        } else if tail.hasPrefix("NULL") {
            enc = "NULL"
        } else if tail.hasPrefix(
            "CAMELLIA_128") {
            enc = "CAMELLIA-128-CBC"
        } else if tail.hasPrefix(
            "CAMELLIA_256") {
            enc = "CAMELLIA-256-CBC"
        } else if tail.hasPrefix(
            "DES_CBC") {
            enc = "DES-CBC"
        }
        return LockSuite(
            name: raw, kex: kex, auth: auth,
            enc: enc, mac: mac)
    }

    static func lockParseOpenSSLName(
        _ name: String) -> LockSuite? {
        let toks = name.components(
            separatedBy: "-")
        guard toks.count >= 2 else {
            return nil
        }
        func encFrom(_ t: [String])
            -> (enc: String, mac: String)? {
            guard let last = t.last
            else { return nil }
            var mac = last
            if mac == "SHA" { mac = "SHA1" }
            let joined = t.dropLast()
                .joined(separator: "-")
            switch joined {
            case "AES128-GCM":
                return ("AES-128-GCM", "AEAD")
            case "AES256-GCM":
                return ("AES-256-GCM", "AEAD")
            case "CHACHA20-POLY1305",
                 "CHACHA20":
                return ("CHACHA20-POLY1305",
                        "AEAD")
            case "AES128", "AES128-CBC":
                return ("AES-128-CBC", mac)
            case "AES256", "AES256-CBC":
                return ("AES-256-CBC", mac)
            case "DES-CBC3", "3DES":
                return ("3DES-CBC", mac)
            case "RC4":
                return ("RC4", mac)
            case "NULL":
                return ("NULL", mac)
            default:
                return (joined, mac)
            }
        }
        if toks[0] == "ECDHE"
            || toks[0] == "DHE" {
            guard toks.count >= 4,
                  let (enc, mac) = encFrom(
                    Array(toks.dropFirst(2)))
            else { return nil }
            return LockSuite(
                name: name, kex: toks[0],
                auth: toks[1], enc: enc,
                mac: mac)
        }
        if toks[0] == "ADH" {
            guard let (enc, mac) = encFrom(
                Array(toks.dropFirst()))
            else { return nil }
            return LockSuite(
                name: name, kex: "DH-anon",
                auth: "none", enc: enc,
                mac: mac)
        }
        if toks[0] == "PSK" {
            guard let (enc, mac) = encFrom(
                Array(toks.dropFirst()))
            else { return nil }
            return LockSuite(
                name: name, kex: "PSK",
                auth: "PSK", enc: enc,
                mac: mac)
        }
        guard let (enc, mac) = encFrom(toks)
        else { return nil }
        return LockSuite(
            name: name, kex: "RSA",
            auth: "RSA", enc: enc, mac: mac)
    }

    /// cipherprobe <hex|name> — a
    /// cipher suite read from its
    /// IANA code or either of its
    /// common names, components and
    /// posture in the open.
    static func cipherprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("cipherprobe: give a suite code or name — cipherprobe 0xC02F"), .err)
                return
            }
            var code: UInt32?
            var readAs = ""
            if arg.hasPrefix("0x")
                || arg.hasPrefix("0X") {
                code = UInt32(
                    arg.dropFirst(2),
                    radix: 16)
                readAs = L("hex")
            } else if arg.allSatisfy({
                $0.isHexDigit
            }), arg.contains(where: {
                "ABCDEFabcdef"
                    .contains($0)
            }), arg.count <= 6 {
                code = UInt32(arg, radix: 16)
                readAs = L("hex")
            } else if arg.allSatisfy({
                $0.isNumber
            }), let decimal = UInt32(arg),
                      decimal <= 0xFFFF {
                code = decimal
                readAs = L("decimal")
            }
            if let code = code {
                if let suite =
                    lockSuites[code] {
                    icsSay(emit, String(format: L("read as a %@ code:"), readAs), .sys)
                    lockDescribeSuite(
                        suite, code: code,
                        emit: emit)
                } else {
                    icsSay(emit, String(format: L("code 0x%04x is not on the bench's shelf of %lld named suites — the registry holds hundreds; give the suite's name and the parser will read it"), Int64(code), Int64(lockSuites.count)), .err)
                }
                return
            }
            if let suite =
                lockParseSuiteName(arg) {
                icsSay(emit, L("read from the name — parsed into components, not looked up:"), .sys)
                lockDescribeSuite(
                    suite, code: nil,
                    emit: emit)
                // If the parsed suite is
                // also on the shelf, name
                // its code.
                for (known, row)
                    in lockSuites
                    where row.kex == suite.kex
                    && row.auth == suite.auth
                    && row.enc == suite.enc
                    && row.mac == suite.mac {
                    icsSay(emit, String(format: L("on the shelf as 0x%04x — %@"), Int64(known), row.name))
                    break
                }
                return
            }
            icsSay(emit, L("neither a suite code nor a name the parser can read — try 0xC02F or TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"), .err)
        }
    }
}

extension BlacksiteBench {

    // MARK: the AES hand (FIPS-197)

    /// The substitution tables —
    /// derived from GF(2^8)
    /// arithmetic in the verification
    /// pass, then proven again by
    /// every FIPS-197 vector.
    static let aesSBox: [UInt8] = [
        0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
        0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
        0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
        0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
        0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
        0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
        0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
        0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
        0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
        0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
        0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
        0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
        0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
        0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
        0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
        0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
    ]
    static let aesInvSBox: [UInt8] = [
        0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
        0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
        0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
        0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
        0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
        0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
        0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
        0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
        0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
        0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
        0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
        0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
        0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
        0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
        0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
        0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D,
    ]

    static func lockGFMul(
        _ a0: UInt8, _ b0: UInt8)
        -> UInt8 {
        var a = a0
        var b = b0
        var r: UInt8 = 0
        while b != 0 {
            if b & 1 != 0 { r ^= a }
            a = (a << 1)
                ^ ((a & 0x80) != 0
                    ? 0x1B : 0)
            b >>= 1
        }
        return r
    }

    static func lockAESExpand(
        _ key: [UInt8])
        -> (roundKeys: [UInt8], rounds: Int) {
        let nk = key.count / 4
        let nr = nk + 6
        var w: [[UInt8]] = []
        for i in 0..<nk {
            w.append(Array(
                key[(4 * i)..<(4 * i + 4)]))
        }
        var rcon: UInt8 = 1
        for i in nk..<(4 * (nr + 1)) {
            var t = w[i - 1]
            if i % nk == 0 {
                t = [aesSBox[Int(t[1])]
                        ^ rcon,
                     aesSBox[Int(t[2])],
                     aesSBox[Int(t[3])],
                     aesSBox[Int(t[0])]]
                rcon = lockGFMul(rcon, 2)
            } else if nk > 6, i % nk == 4 {
                t = t.map {
                    aesSBox[Int($0)]
                }
            }
            var word: [UInt8] = []
            for j in 0..<4 {
                word.append(w[i - nk][j]
                    ^ t[j])
            }
            w.append(word)
        }
        var flat: [UInt8] = []
        for word in w { flat += word }
        return (flat, nr)
    }

    static func lockAESRoundKey(
        _ flat: [UInt8], _ round: Int)
        -> [UInt8] {
        var out: [UInt8] = []
        for c in 0..<4 {
            let start = 16 * round + 4 * c
            out += flat[
                start..<(start + 4)]
        }
        return out
    }

    static func lockAESShiftRows(
        _ s: [UInt8],
        inverse: Bool) -> [UInt8] {
        var out = [UInt8](
            repeating: 0, count: 16)
        for r in 0..<4 {
            for c in 0..<4 {
                let src = inverse
                    ? (c - r + 4) % 4
                    : (c + r) % 4
                out[r + 4 * c] =
                    s[r + 4 * src]
            }
        }
        return out
    }

    static func lockAESMix(
        _ s: [UInt8],
        inverse: Bool) -> [UInt8] {
        var out = [UInt8](
            repeating: 0, count: 16)
        for c in 0..<4 {
            let col = Array(
                s[(4 * c)..<(4 * c + 4)])
            if inverse {
                out[4 * c] =
                    lockGFMul(col[0], 14)
                    ^ lockGFMul(col[1], 11)
                    ^ lockGFMul(col[2], 13)
                    ^ lockGFMul(col[3], 9)
                out[4 * c + 1] =
                    lockGFMul(col[0], 9)
                    ^ lockGFMul(col[1], 14)
                    ^ lockGFMul(col[2], 11)
                    ^ lockGFMul(col[3], 13)
                out[4 * c + 2] =
                    lockGFMul(col[0], 13)
                    ^ lockGFMul(col[1], 9)
                    ^ lockGFMul(col[2], 14)
                    ^ lockGFMul(col[3], 11)
                out[4 * c + 3] =
                    lockGFMul(col[0], 11)
                    ^ lockGFMul(col[1], 13)
                    ^ lockGFMul(col[2], 9)
                    ^ lockGFMul(col[3], 14)
            } else {
                out[4 * c] =
                    lockGFMul(col[0], 2)
                    ^ lockGFMul(col[1], 3)
                    ^ col[2] ^ col[3]
                out[4 * c + 1] = col[0]
                    ^ lockGFMul(col[1], 2)
                    ^ lockGFMul(col[2], 3)
                    ^ col[3]
                out[4 * c + 2] = col[0]
                    ^ col[1]
                    ^ lockGFMul(col[2], 2)
                    ^ lockGFMul(col[3], 3)
                out[4 * c + 3] =
                    lockGFMul(col[0], 3)
                    ^ col[1] ^ col[2]
                    ^ lockGFMul(col[3], 2)
            }
        }
        return out
    }

    static func lockAESBlock(
        _ block: [UInt8], key: [UInt8],
        encrypt: Bool) -> [UInt8] {
        let (flat, nr) = lockAESExpand(
            key)
        func addKey(_ s: [UInt8],
                    _ round: Int)
            -> [UInt8] {
            let rk = lockAESRoundKey(
                flat, round)
            return zip(s, rk).map(^)
        }
        if encrypt {
            var s = addKey(block, 0)
            for round in 1..<nr {
                s = s.map {
                    aesSBox[Int($0)]
                }
                s = lockAESShiftRows(
                    s, inverse: false)
                s = lockAESMix(
                    s, inverse: false)
                s = addKey(s, round)
            }
            s = s.map {
                aesSBox[Int($0)]
            }
            s = lockAESShiftRows(
                s, inverse: false)
            return addKey(s, nr)
        }
        var s = addKey(block, nr)
        var round = nr - 1
        while round >= 1 {
            s = lockAESShiftRows(
                s, inverse: true)
            s = s.map {
                aesInvSBox[Int($0)]
            }
            s = addKey(s, round)
            s = lockAESMix(
                s, inverse: true)
            round -= 1
        }
        s = lockAESShiftRows(
            s, inverse: true)
        s = s.map {
            aesInvSBox[Int($0)]
        }
        return addKey(s, 0)
    }

    static func lockAESRun(
        data: [UInt8], key: [UInt8],
        mode: String, iv: [UInt8]?,
        encrypt: Bool,
        padding: String)
        -> [UInt8]? {
        var input = data
        if mode == "ecb" || mode == "cbc" {
            if encrypt {
                switch padding {
                case "pkcs7":
                    let pad = 16
                        - (input.count % 16)
                    input += [UInt8](
                        repeating: UInt8(pad),
                        count: pad)
                case "zero":
                    while input.count % 16
                            != 0 {
                        input.append(0)
                    }
                default:
                    guard input.count % 16
                            == 0 else {
                        return nil
                    }
                }
            } else {
                guard input.count % 16 == 0,
                      !input.isEmpty else {
                    return nil
                }
            }
        }
        var out: [UInt8] = []
        if mode == "ecb" {
            var at = 0
            while at < input.count {
                out += lockAESBlock(
                    Array(input[at..<(at + 16)]),
                    key: key,
                    encrypt: encrypt)
                at += 16
            }
        } else if mode == "cbc" {
            guard let iv = iv,
                  iv.count == 16 else {
                return nil
            }
            var prev = iv
            var at = 0
            while at < input.count {
                let block = Array(
                    input[at..<(at + 16)])
                if encrypt {
                    let mixed = zip(
                        block, prev).map(^)
                    let done = lockAESBlock(
                        mixed, key: key,
                        encrypt: true)
                    out += done
                    prev = done
                } else {
                    let done = lockAESBlock(
                        block, key: key,
                        encrypt: false)
                    out += zip(done, prev)
                        .map(^)
                    prev = block
                }
                at += 16
            }
        } else if mode == "ctr" {
            guard let iv = iv,
                  iv.count == 16 else {
                return nil
            }
            var counter = LockBig.fromBytes(
                iv)
            var at = 0
            while at < input.count {
                var counterBytes =
                    counter.toBytes()
                while counterBytes.count
                        < 16 {
                    counterBytes.insert(
                        0, at: 0)
                }
                let stream = lockAESBlock(
                    counterBytes, key: key,
                    encrypt: true)
                let take = min(
                    16, input.count - at)
                for k in 0..<take {
                    out.append(
                        input[at + k]
                            ^ stream[k])
                }
                counter = counter
                    + LockBig(1)
                at += 16
            }
        } else {
            return nil
        }
        if !encrypt,
           mode == "ecb" || mode == "cbc" {
            if padding == "pkcs7" {
                guard let last = out.last,
                      last >= 1, last <= 16,
                      out.count >= last
                else { return nil }
                let pad = Int(last)
                let tail = out.suffix(pad)
                guard tail.allSatisfy({
                    $0 == last
                }) else { return nil }
                out = Array(
                    out.dropLast(pad))
            } else if padding == "zero" {
                while out.last == 0 {
                    out.removeLast()
                }
            }
        }
        return out
    }

    // MARK: kdfprobe

    static func lockPBKDF2(
        hmac: (Data, Data) -> [UInt8],
        hashLength: Int,
        word: Data, salt: [UInt8],
        iterations: Int, dkLength: Int)
        -> [UInt8] {
        var derived: [UInt8] = []
        var blockIndex: UInt32 = 1
        while derived.count < dkLength {
            var first = Data(salt)
            first.append(UInt8(
                (blockIndex >> 24) & 0xFF))
            first.append(UInt8(
                (blockIndex >> 16) & 0xFF))
            first.append(UInt8(
                (blockIndex >> 8) & 0xFF))
            first.append(UInt8(
                blockIndex & 0xFF))
            var u = hmac(word, first)
            var t = u
            if iterations > 1 {
                for _ in 2...iterations {
                    u = hmac(word, Data(u))
                    for i in 0..<hashLength {
                        t[i] ^= u[i]
                    }
                }
            }
            derived += t
            blockIndex += 1
        }
        return Array(derived.prefix(
            dkLength))
    }

    /// kdfprobe <alg> <word>
    /// <salt:salt|salt-hex> <iters>
    /// [bytes] — derive a key with
    /// PBKDF2 on the bench and read
    /// the answer. The word is used
    /// in place and never printed.
    static func kdfprobe(
        spec: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = spec.components(
                separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard tokens.count >= 4 else {
                icsSay(emit, L("kdfprobe: kdfprobe pbkdf2-sha256 <word> salt:<text> <iterations> [bytes] — the word is never printed back"), .err)
                return
            }
            let alg = tokens[0]
                .lowercased()
            if alg == "scrypt"
                || alg == "argon2"
                || alg == "argon2id" {
                icsSay(emit, String(format: L("%@ is not carried by the house books — the bench offers PBKDF2 over SHA-1, SHA-256 and SHA-512, and says so rather than improvise a memory-hard derivation it cannot verify"), alg), .err)
                return
            }
            let hmac: (Data, Data)
                -> [UInt8]
            let hashLength: Int
            switch alg {
            case "pbkdf2-sha1", "sha1":
                hashLength = 20
                hmac = { key, data in
                    [UInt8](HMAC<Insecure.SHA1>
                        .authenticationCode(
                            for: data,
                            using: SymmetricKey(
                                data: key)))
                }
            case "pbkdf2-sha256",
                 "pbkdf2", "sha256":
                hashLength = 32
                hmac = { key, data in
                    [UInt8](HMAC<SHA256>
                        .authenticationCode(
                            for: data,
                            using: SymmetricKey(
                                data: key)))
                }
            case "pbkdf2-sha512", "sha512":
                hashLength = 64
                hmac = { key, data in
                    [UInt8](HMAC<SHA512>
                        .authenticationCode(
                            for: data,
                            using: SymmetricKey(
                                data: key)))
                }
            default:
                icsSay(emit, L("kdfprobe: the bench carries pbkdf2-sha1, pbkdf2-sha256 and pbkdf2-sha512"), .err)
                return
            }
            let word = tokens[1]
            var salt: [UInt8]?
            if tokens[2].hasPrefix(
                "salt:") {
                salt = [UInt8](String(
                    tokens[2].dropFirst(5))
                    .utf8)
            } else if tokens[2].hasPrefix(
                "salthex:") {
                salt = lockHexDecode(
                    String(tokens[2]
                        .dropFirst(8)))
            }
            guard let salt = salt,
                  let iterations = Int(
                    tokens[3]),
                  iterations >= 1,
                  iterations <= 10_000_000
            else {
                icsSay(emit, L("kdfprobe: the salt rides as salt:<text> or salthex:<hex>, and iterations run 1 to 10,000,000"), .err)
                return
            }
            var dkLength = hashLength
            if tokens.count > 4,
               let want = Int(tokens[4]) {
                dkLength = min(
                    max(want, 1), 128)
            }
            let derived = lockPBKDF2(
                hmac: hmac,
                hashLength: hashLength,
                word: Data(word.utf8),
                salt: salt,
                iterations: iterations,
                dkLength: dkLength)
            icsSay(emit, String(format: L("%@ · %lld iterations · %lld salt bytes · word of %lld bytes (never printed)"), alg, Int64(iterations), Int64(salt.count), Int64(word.utf8.count)), .sys)
            icsSay(emit, String(format: L("derived key (%lld bytes): %@"), Int64(derived.count), derived.map {
                String(format: "%02x", $0)
            }.joined()), .ok)
        }
    }

    // MARK: aesprobe

    /// aesprobe mode=cbc key=<hex>
    /// iv=<hex> [pad=pkcs7|zero|none]
    /// data=<hex> | file=<path>
    /// [enc|dec] — raw AES worked by
    /// hand on the bench (the cipher
    /// itself is FIPS-197, verified
    /// against the published vectors).
    /// Raw AES is a primitive, not a
    /// protocol: no MAC rides with it,
    /// and the bench says so.
    static func aesprobe(
        spec: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = spec.components(
                separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            var mode = "cbc"
            var pad = "pkcs7"
            var encrypt = true
            var keyHex: String?
            var ivHex: String?
            var dataHex: String?
            var filePath: String?
            for token in tokens {
                if token == "enc" {
                    encrypt = true
                } else if token == "dec" {
                    encrypt = false
                } else if token.hasPrefix(
                    "mode=") {
                    mode = String(token
                        .dropFirst(5))
                        .lowercased()
                } else if token.hasPrefix(
                    "pad=") {
                    pad = String(token
                        .dropFirst(4))
                        .lowercased()
                } else if token.hasPrefix(
                    "key=") {
                    keyHex = String(token
                        .dropFirst(4))
                } else if token.hasPrefix(
                    "iv=") {
                    ivHex = String(token
                        .dropFirst(3))
                } else if token.hasPrefix(
                    "ctr=") {
                    ivHex = String(token
                        .dropFirst(4))
                } else if token.hasPrefix(
                    "data=") {
                    dataHex = String(token
                        .dropFirst(5))
                } else if token.hasPrefix(
                    "file=") {
                    filePath = String(token
                        .dropFirst(5))
                } else if filePath == nil {
                    filePath = token
                }
            }
            guard let keyHex = keyHex,
                  let key = lockHexDecode(
                    keyHex),
                  key.count == 16
                    || key.count == 24
                    || key.count == 32
            else {
                icsSay(emit, L("aesprobe: key=<hex> must carry 16, 24 or 32 bytes — aesprobe mode=cbc key=… iv=… data=…"), .err)
                return
            }
            var iv: [UInt8]?
            if mode == "cbc"
                || mode == "ctr" {
                guard let ivHex = ivHex,
                      let parsed =
                        lockHexDecode(ivHex),
                      parsed.count == 16
                else {
                    icsSay(emit, L("aesprobe: cbc and ctr want iv=<16 bytes of hex>"), .err)
                    return
                }
                iv = parsed
            }
            var data: [UInt8]?
            if let dataHex = dataHex {
                data = lockHexDecode(
                    dataHex)
            } else if let filePath =
                        filePath,
                      let file = lockReadFile(
                        filePath) {
                data = [UInt8](file.data)
            }
            guard let data = data else {
                icsSay(emit, L("aesprobe: give data=<hex> or a file"), .err)
                return
            }
            if mode == "ctr" {
                pad = "none"
            }
            guard let out = lockAESRun(
                data: data, key: key,
                mode: mode, iv: iv,
                encrypt: encrypt,
                padding: pad) else {
                icsSay(emit, L("the block arithmetic refused: the data does not fit the mode and padding as given (a bad pad on decrypt usually means the wrong key — the bench reports it, it does not paper over it)"), .err)
                return
            }
            icsSay(emit, String(format: L("AES-%lld %@ %@ · in %lld bytes, out %lld bytes"), Int64(key.count * 8), mode.uppercased(), encrypt ? L("encrypt") : L("decrypt"), Int64(data.count), Int64(out.count)), .sys)
            let hex = out.map {
                String(format: "%02x", $0)
            }.joined()
            if hex.count > 2048 {
                icsSay(emit, String(format: L("%@… (the full %lld bytes stand in the file statistic above; the bench prints the first 1024)"), String(hex.prefix(2048)), Int64(out.count)))
            } else {
                icsSay(emit, hex, .ok)
            }
            if let text = lockPrintable(
                out), !encrypt {
                let shown = text.count > 400
                    ? String(text.prefix(400))
                        + "…"
                    : text
                icsSay(emit, String(format: L("as text: %@"), shown))
            }
            icsSay(emit, L("raw AES carries no MAC — a clean decrypt proves the padding, not the sender"))
        }
    }

    // MARK: xorprobe

    static let lockLetterFreq: [(UInt8, Double)] = [
        (101, 12.7), (116, 9.1), (97, 8.2),
        (111, 7.5), (105, 7.0), (110, 6.7),
        (115, 6.3), (104, 6.1), (114, 6.0),
        (100, 4.3), (108, 4.0), (117, 2.8),
        (99, 2.8), (109, 2.4), (119, 2.4),
        (102, 2.2), (103, 2.0), (121, 2.0),
        (112, 1.9), (98, 1.5), (118, 1.0),
        (107, 0.8), (106, 0.15), (120, 0.15),
        (113, 0.10), (122, 0.07),
    ]

    static func lockColumnIoC(
        _ col: [UInt8]) -> Double {
        var counts = [Int](
            repeating: 0, count: 256)
        for byte in col {
            counts[Int(byte)] += 1
        }
        let n = col.count
        guard n >= 2 else { return 0 }
        var sum = 0
        for c in counts {
            sum += c * (c - 1)
        }
        return Double(sum)
            / Double(n * (n - 1))
    }

    static func lockSolveColumn(
        _ col: [UInt8]) -> UInt8 {
        var best: (score: Double,
                   key: UInt8) =
            (Double.greatestFiniteMagnitude,
             0)
        for candidate in 0..<256 {
            var letters = [UInt8: Int]()
            var total = 0
            for byte in col {
                let plain = byte
                    ^ UInt8(candidate)
                let lower = plain >= 65
                    && plain <= 90
                    ? plain + 32 : plain
                if lower >= 97,
                   lower <= 122 {
                    letters[lower, default: 0] += 1
                    total += 1
                }
            }
            guard total > 0 else {
                continue
            }
            var score = 0.0
            for (letter, freq)
                in lockLetterFreq {
                let observed = Double(
                    letters[letter] ?? 0) /
                    Double(total) * 100
                let d = observed - freq
                score += d * d / freq
            }
            if score < best.score {
                best = (score,
                        UInt8(candidate))
            }
        }
        return best.key
    }

    /// xorprobe <file> [keylen=n] —
    /// repeating-key XOR read the
    /// statistical way: key length by
    /// index of coincidence, each key
    /// byte solved on its column's
    /// letter shape. An estimate, and
    /// the preview is printed so the
    /// operator can judge it.
    static func xorprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = target
                .components(
                    separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard let first = tokens.first,
                  let file = lockReadFile(
                    first) else {
                icsSay(emit, L("xorprobe: give a file of captured bytes — xorprobe /home/capture.bin"), .err)
                return
            }
            let data = [UInt8](file.data)
            var forced: Int?
            for token in tokens.dropFirst() {
                if token.hasPrefix(
                    "keylen=") {
                    forced = Int(String(
                        token.dropFirst(7)))
                }
            }
            guard data.count >= 32 else {
                icsSay(emit, L("too little material — a statistical read wants at least a few hundred bytes; under 32, no claim is made"), .err)
                return
            }
            icsSay(emit, String(format: L("reading %@ (%lld bytes)"), file.path, Int64(data.count)), .sys)
            var chosen: Int
            if let forced = forced,
               forced >= 1, forced <= 64 {
                chosen = forced
                icsSay(emit, String(format: L("key length %lld, as given"), Int64(forced)))
            } else {
                var scored: [(ioc: Double,
                               k: Int)] = []
                for k in 1...40 {
                    var total = 0.0
                    for j in 0..<k {
                        let col = stride(
                            from: j, to: data.count, by: k)
                            .map { data[$0] }
                        total +=
                            lockColumnIoC(col)
                    }
                    scored.append((
                        ioc: total
                            / Double(k),
                        k: k))
                }
                scored.sort {
                    $0.ioc > $1.ioc
                }
                let top = scored.prefix(5)
                icsSay(emit, String(format: L("key-length candidates by column coincidence: %@"), top.map {
                    String(format: "%lld (%.3f)", Int64($0.k), $0.ioc)
                }.joined(separator: ", ")))
                chosen = top.first?.k ?? 1
                icsSay(emit, String(format: L("reading with the strongest candidate, %lld"), Int64(chosen)))
            }
            var key: [UInt8] = []
            for j in 0..<chosen {
                let col = stride(
                    from: j, to: data.count,
                    by: chosen).map {
                        data[$0]
                    }
                key.append(
                    lockSolveColumn(col))
            }
            // A repeated key solved at a
            // multiple of its true length
            // reduces to its period.
            var period = chosen
            for p in 1...chosen
                where chosen % p == 0 {
                var repeats = true
                for i in 0..<chosen
                    where key[i] != key[i % p] {
                    repeats = false
                }
                if repeats {
                    period = p
                    break
                }
            }
            if period < chosen {
                icsSay(emit, String(format: L("the solved key repeats every %lld bytes — that is its true period"), Int64(period)))
                key = Array(key.prefix(
                    period))
                chosen = period
            }
            let keyText = String(
                bytes: key, encoding: .ascii)
            let printableKey = keyText
                .map { text in
                    text.unicodeScalars
                        .allSatisfy {
                            $0.value >= 0x20
                                && $0.value
                                    < 0x7F
                        }
                } ?? false
            icsSay(emit, String(format: L("solved key (hex): %@"), key.map {
                String(format: "%02x", $0)
            }.joined(separator: " ")), .sys)
            if printableKey,
               let keyText = keyText {
                icsSay(emit, String(format: L("solved key (text): %@"), keyText), .sys)
            }
            var plain: [UInt8] = []
            for (i, byte) in data.enumerated() {
                plain.append(byte
                    ^ key[i % chosen])
            }
            if let text = lockPrintable(
                plain) {
                let shown = text.count > 400
                    ? String(text.prefix(400))
                        + "…"
                    : text
                icsSay(emit, String(format: L("plaintext preview: %@"), shown), .ok)
            } else {
                let head = plain.prefix(48)
                    .map {
                        String(format: "%02x", $0)
                    }.joined(separator: " ")
                icsSay(emit, String(format: L("the solved stream is not printable text (%@…) — the key length or the assumption may be wrong"), head), .err)
            }
            icsSay(emit, L("a statistical solve is an estimate — the preview above is the evidence; a fluent preview is what a right key looks like"))
        }
    }

    // MARK: rsaprobe

    static let lockPrimes: [UInt32] = {
        let limit = 100_000
        var sieve = [Bool](
            repeating: true,
            count: limit)
        sieve[0] = false
        sieve[1] = false
        var i = 2
        while i * i < limit {
            if sieve[i] {
                var j = i * i
                while j < limit {
                    sieve[j] = false
                    j += i
                }
            }
            i += 1
        }
        return sieve.enumerated()
            .filter { $0.element }
            .map { UInt32($0.offset) }
    }()

    /// Find the modulus (or two) a
    /// rsaprobe argument names: a key
    /// file, an OpenSSH line, or a
    /// bare hex modulus.
    static func lockModulus(
        from arg: String) -> LockBig? {
        if let file = lockReadFile(arg) {
            let bytes = [UInt8](file.data)
            if let text = String(
                bytes: bytes,
                encoding: .utf8) {
                if let block =
                    lockPEMBlocks(text)
                        .first,
                   let info = lockParseSPKI(
                    block.der) {
                    return info.rsaModulus
                }
                let tokens = text
                    .components(
                        separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                if tokens.count >= 2,
                   let blob = Data(
                    base64Encoded: tokens[1]),
                   let parsed =
                    lockParseSSHBlob(
                        [UInt8](blob)),
                   parsed.fields.count >= 3 {
                    return LockBig.fromBytes(
                        parsed.fields[2])
                }
            }
            if let info = lockParseSPKI(
                bytes) {
                return info.rsaModulus
            }
            return nil
        }
        let hex = arg.filter {
            $0.isHexDigit
        }
        if hex.count == arg.count,
           hex.count >= 32,
           hex.count % 2 == 0,
           let bytes = lockHexDecode(
            arg) {
            return LockBig.fromBytes(bytes)
        }
        return nil
    }

    /// The cheap RSA shapes, read
    /// exactly: trial division under
    /// 100,000, and Fermat's walk from
    /// the root, capped where it says.
    static func lockRSAChecks(
        _ n: LockBig,
        emit: @escaping BlacksiteEmit)
        -> Bool {
        var foundIssue = false
        if n.modSmall(2) == 0 {
            icsSay(emit, L("the modulus is EVEN — no honest RSA modulus is; it is composite by inspection"), .err)
            return true
        }
        // Trial division, bounded the
        // exact way: stop when the
        // primes pass the root.
        let root = n.isqrt()
        for prime in lockPrimes {
            if LockBig(prime) > root {
                break
            }
            if n.modSmall(prime) == 0 {
                icsSay(emit, String(format: L("a small factor stands in the open: %lld divides the modulus"), Int64(prime)), .err)
                return true
            }
        }
        let squared = root * root
        if squared == n {
            icsSay(emit, L("the modulus is a perfect square — its root is the factor, twice"), .err)
            return true
        }
        var a = root + LockBig(1)
        let cap = 20_000
        var steps = 0
        var hit = false
        while steps < cap {
            let b2 = a * a - n
            let b = b2.isqrt()
            if b * b == b2 {
                let low = a - b
                icsSay(emit, String(format: L("Fermat's walk found the factors %lld steps from the root — the primes were chosen too close together"), Int64(steps)), .err)
                icsSay(emit, String(format: L("smaller factor: %lld bits"), Int64(low.bitLength)))
                hit = true
                foundIssue = true
                break
            }
            a = a + LockBig(1)
            steps += 1
        }
        if !hit {
            icsSay(emit, String(format: L("no small factor under 100,000, and no factor pair within %lld Fermat steps of the root"), Int64(cap)))
        }
        return foundIssue
    }

    /// rsaprobe <key|hex> [second] —
    /// the cheap weaknesses of an RSA
    /// modulus, checked exactly: small
    /// factors, factors too close
    /// together (Fermat), and a factor
    /// shared with a second modulus
    /// (the gcd that broke a
    /// generation of embedded keys).
    static func rsaprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = target
                .components(
                    separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard let first = tokens.first,
                  let n = lockModulus(
                    from: first) else {
                icsSay(emit, L("rsaprobe: give a key file or a hex modulus — rsaprobe /home/id_rsa.pub"), .err)
                return
            }
            icsSay(emit, String(format: L("modulus: %lld bits"), Int64(n.bitLength)), .sys)
            let issue = lockRSAChecks(
                n, emit: emit)
            if tokens.count > 1 {
                if let other = lockModulus(
                    from: tokens[1]) {
                    let g = LockBig.gcd(
                        n, other)
                    if g > LockBig(1) {
                        if g == n
                            || g == other {
                            icsSay(emit, L("the two moduli are the same key, or one divides the other — the gcd is a whole modulus"), .err)
                        } else {
                            icsSay(emit, String(format: L("the two moduli SHARE a factor of %lld bits (gcd) — each is factored by the other's company; both keys fall"), Int64(g.bitLength)), .err)
                        }
                    } else {
                        icsSay(emit, L("the two moduli share no factor (gcd 1)"))
                    }
                } else {
                    icsSay(emit, L("the second argument did not resolve to a modulus"), .err)
                }
            }
            if !issue {
                icsSay(emit, L("the cheap shapes are absent — small factors, close factors and (where tested) shared factors; that is the whole of what this bench claims, not a proof the key is strong"))
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: eccprobe

    /// The NIST curves this bench
    /// walks, as (field bytes, b).
    /// The prime of P-256 and P-384
    /// rides as its published hex;
    /// P-521's prime is 2^521 − 1 and
    /// is built, not transcribed.
    static func lockCurve(
        _ oidOrSize: String)
        -> (name: String, p: LockBig,
            b: LockBig, field: Int)? {
        func fromHex(_ hex: String)
            -> LockBig {
            LockBig.fromBytes(
                lockHexDecode(hex) ?? [])
        }
        switch oidOrSize {
        case "1.2.840.10045.3.1.7",
             "nistp256", "65", "32":
            return ("NIST P-256",
                    fromHex("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF"),
                    fromHex("5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B"),
                    32)
        case "1.3.132.0.34",
             "nistp384", "97", "48":
            return ("NIST P-384",
                    fromHex("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFFFF0000000000000000FFFFFFFF"),
                    fromHex("B3312FA7E23EE7E4988E056BE3F82D19181D9C6EFE8141120314088F5013875AC656398D8A2ED19D2A85C8EDD3EC2AEF"),
                    48)
        case "1.3.132.0.35",
             "nistp521", "133", "66":
            let p = LockBig(1)
                .shlBits(521) - LockBig(1)
            return ("NIST P-521", p,
                    fromHex("0051953EB9618E1C9A1F929A21A0B68540EEA2DA725B99B315F3B8B489918EF109E156193951EC7E937B1652C0BD3BB1BF073573DF883D2C34F1EF451FD46B503F00"),
                    66)
        case "1.3.132.0.10":
            return nil  // secp256k1: a=0 —
            // named by eccprobe itself.
        default:
            return nil
        }
    }

    /// y² = x³ − 3x + b (mod p),
    /// computed exactly in LockBig.
    static func lockCurveRHS(
        x: LockBig, p: LockBig,
        b: LockBig) -> LockBig {
        let x3 = ((x * x).mod(p) * x)
            .mod(p)
        var rhs = (x3 + b).mod(p)
        let threeX = (LockBig(3) * x)
            .mod(p)
        rhs = (rhs + p - threeX).mod(p)
        return rhs
    }

    /// eccprobe <file|hex point> —
    /// an elliptic curve point
    /// validated exactly: does it
    /// stand on its curve? A
    /// compressed point is expanded
    /// by the (p+1)/4 root — exact
    /// arithmetic for the NIST primes
    /// — and the expansion is itself
    /// the proof. A private scalar is
    /// named and never read.
    static func eccprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("eccprobe: give an EC key file or a hex point — eccprobe /home/ec256-pub.pem"), .err)
                return
            }
            var point: [UInt8]?
            var curveHint: String?
            if let file = lockReadFile(
                arg) {
                let bytes = [UInt8](
                    file.data)
                if let text = String(
                    bytes: bytes,
                    encoding: .utf8) {
                    if text.contains(
                        "EC PRIVATE KEY")
                        || text.contains(
                            "PRIVATE KEY") {
                        // A private key: named,
                        // its scalar unread.
                        for block in
                            lockPEMBlocks(
                                text)
                            where block.label ==
                                "EC PRIVATE KEY" {
                            icsSay(emit, L("a SEC 1 EC private key — the bench names it and does not read the scalar; eccprobe grades public points"), .err)
                            return
                        }
                    }
                    if let block =
                        lockPEMBlocks(text)
                            .first,
                       let info =
                        lockParseSPKI(
                            block.der),
                       let found =
                        info.ecPoint {
                        point = found
                        curveHint =
                            info.ecCurveOID
                    }
                }
                if point == nil,
                   let info = lockParseSPKI(
                    bytes),
                   let found = info.ecPoint {
                    point = found
                    curveHint = info.ecCurveOID
                }
                if point != nil {
                    icsSay(emit, String(format: L("reading %@"), file.path), .sys)
                }
            }
            if point == nil {
                let hex = arg.filter {
                    $0.isHexDigit
                }
                if hex.count == arg.count,
                   let bytes =
                    lockHexDecode(arg) {
                    point = bytes
                }
            }
            guard let point = point,
                  let first = point.first
            else {
                icsSay(emit, L("no EC point stands in that argument — give a public key file or the point in hex"), .err)
                return
            }
            // secp256k1 is a different
            // shape (a = 0); name it and
            // stop rather than grade it
            // with NIST arithmetic.
            if curveHint == "1.3.132.0.10" {
                icsSay(emit, L("secp256k1 — the Bitcoin curve (a = 0, not −3); this bench's exact walk covers the NIST curves, and it will not grade one curve with another's arithmetic"), .err)
                return
            }
            let compressed = first == 0x02
                || first == 0x03
            let uncompressed = first == 0x04
            guard compressed
                    || uncompressed else {
                icsSay(emit, L("the point opens with a byte that is neither 0x04 (uncompressed) nor 0x02/0x03 (compressed) — not a SEC 1 point"), .err)
                return
            }
            let fieldBytes = compressed
                ? point.count - 1
                : (point.count - 1) / 2
            let curve = lockCurve(
                curveHint
                    ?? String(fieldBytes))
            guard let curve = curve else {
                icsSay(emit, L("the curve cannot be named from this point's size or papers"), .err)
                return
            }
            guard fieldBytes ==
                    curve.field else {
                icsSay(emit, L("the point's size does not match its named curve"), .err)
                return
            }
            icsSay(emit, String(format: L("curve: %@"), curve.name), .sys)
            let xBytes = compressed
                ? Array(point.dropFirst())
                : Array(point[1..<(1
                    + curve.field)])
            let x = LockBig.fromBytes(
                xBytes)
            guard x < curve.p else {
                icsSay(emit, L("the x coordinate stands outside the field — not a point on this curve"), .err)
                return
            }
            let rhs = lockCurveRHS(
                x: x, p: curve.p, b: curve.b)
            if compressed {
                let exponent = (curve.p
                    + LockBig(1))
                    .divmod(LockBig(4)).q
                let y = rhs.modpow(
                    exponent, curve.p)
                guard (y * y).mod(curve.p)
                        == rhs else {
                    icsSay(emit, L("no square root exists for this x — no point on the curve carries it"), .err)
                    return
                }
                let odd = first == 0x03
                let chosen = (y.bitLength
                    > 0 && (y.limbs[0]
                        & 1) == 1) == odd
                    ? y : curve.p - y
                icsSay(emit, String(format: L("compressed point (0x%02x) — expanded exactly: y is %lld bits, %@"), Int64(first), Int64(chosen.bitLength), odd ? L("odd, as the prefix swears") : L("even, as the prefix swears")))
                icsSay(emit, L("the expansion is the proof: y² ≡ x³ − 3x + b (mod p), computed in full"), .ok)
                return
            }
            let yBytes = Array(
                point[(1 + curve.field)...])
            let y = LockBig.fromBytes(
                yBytes)
            guard y < curve.p else {
                icsSay(emit, L("the y coordinate stands outside the field — not a point on this curve"), .err)
                return
            }
            let lhs = (y * y).mod(curve.p)
            if lhs == rhs {
                icsSay(emit, String(format: L("the point stands on %@ — y² ≡ x³ − 3x + b (mod p), computed exactly"), curve.name), .ok)
            } else {
                icsSay(emit, L("the point does NOT stand on its curve — the equation fails; a forged or corrupted point proves nothing and signs nothing"), .err)
            }
        }
    }

    // MARK: enccensus

    /// enccensus <file> — whose
    /// papers are these? The container
    /// formats the bench can name from
    /// their headers: the house NJCF,
    /// OpenSSL's salted form, age,
    /// LUKS, OpenPGP, ZIP (with its
    /// per-entry encryption flags),
    /// the archive magics, PDF's
    /// encryption dictionary. A blob
    /// with no papers is called
    /// unidentified — there are
    /// containers (a mawkbox song, a
    /// time-locked Magic Box) that
    /// carry none by design, and a
    /// sealed blob and a random one
    /// look alike from outside.
    static func enccensus(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let file = lockReadFile(
                    arg) else {
                icsSay(emit, L("enccensus: give a file — enccensus /home/vault.njcf"), .err)
                return
            }
            let data = [UInt8](file.data)
            icsSay(emit, String(format: L("reading %@ (%lld bytes)"), file.path, Int64(data.count)), .sys)
            func has(_ prefix: [UInt8])
                -> Bool {
                data.count >= prefix.count
                    && Array(data.prefix(
                        prefix.count))
                        == prefix
            }
            if has(Array("NJCF".utf8)) {
                // The layout is the
                // house reader's own
                // (CryptoFiles.parseHeader):
                // version, protection,
                // then — for protections
                // involving a passphrase —
                // the iteration count and
                // salt; the length-stamped
                // wrapped keys; for a dead
                // drop, a fixed 64-byte
                // ephemeral key and its
                // wrap; the base nonce;
                // the chunk size.
                guard data.count >= 6 else {
                    icsSay(emit, L("an NJCF header, cut short — the file ends inside its own papers"), .err)
                    return
                }
                let version = Int(data[4])
                let protection = Int(
                    data[5])
                let names: [Int: String] = [
                    1: "a passphrase alone",
                    2: "the vault key alone",
                    3: "either the passphrase or the vault key",
                    4: "both the passphrase and the vault key",
                    5: "a dead drop — sealed to a recipient's key",
                ]
                guard let protName = names[
                    protection] else {
                    icsSay(emit, String(format: L("an NJCF header with protection byte %lld — no house writer stamps that"), Int64(protection)), .err)
                    return
                }
                var offset = 6
                var iterations = 0
                var truncated = false
                func u16() -> Int {
                    guard offset + 2
                            <= data.count else {
                        truncated = true
                        return 0
                    }
                    defer { offset += 2 }
                    return Int(data[offset])
                        << 8
                        | Int(data[offset + 1])
                }
                if protection == 1
                    || protection == 3
                    || protection == 4 {
                    guard data.count >= 26
                    else {
                        icsSay(emit, L("an NJCF header, cut short — the file ends inside its own papers"), .err)
                        return
                    }
                    iterations = Int(data[6])
                        << 24
                        | Int(data[7]) << 16
                        | Int(data[8]) << 8
                        | Int(data[9])
                    offset = 26
                }
                let wrapSections =
                    protection == 3 ? 2
                    : (protection == 5 ? 0 : 1)
                var wrappedTotal = 0
                for _ in 0..<wrapSections {
                    let len = u16()
                    wrappedTotal += len
                    offset += len
                }
                if protection == 5 {
                    offset += 64
                    let len = u16()
                    wrappedTotal += len
                    offset += len
                }
                offset += 12
                var chunkSize = 0
                if offset + 4 <= data.count {
                    chunkSize = Int(
                        data[offset]) << 24
                        | Int(data[offset + 1])
                            << 16
                        | Int(data[offset + 2])
                            << 8
                        | Int(data[offset + 3])
                    offset += 4
                } else {
                    truncated = true
                }
                if truncated {
                    icsSay(emit, L("an NJCF header, cut short — the file ends inside its own papers"), .err)
                    return
                }
                icsSay(emit, String(format: L("the house NJCF container, format v%lld"), Int64(version)), .sys)
                icsSay(emit, String(format: L("protection: %@"), protName))
                if iterations > 0 {
                    icsSay(emit, String(format: L("the passphrase stretch runs %lld iterations, its count and a 16-byte salt riding in the clear"), Int64(iterations)))
                }
                icsSay(emit, String(format: L("wrapped key material: %lld bytes%@; the sealed payload begins at byte %lld, in chunks of %lld"), Int64(wrappedTotal), protection == 5 ? L(", behind a 64-byte ephemeral public key riding in the clear") : "", Int64(offset), Int64(chunkSize)))
                return
            }
            if has(Array("Salted__".utf8)) {
                let salt = data.count >= 16
                    ? Array(data[8..<16])
                        .map {
                            String(format: "%02x", $0)
                        }.joined()
                    : ""
                icsSay(emit, L("OpenSSL's salted form (openssl enc / salted PEM-era encryption)"), .sys)
                icsSay(emit, String(format: L("salt: %@ — the KDF and its count do not ride in the file; they live in the command that made it, and a reader must be told them"), salt))
                return
            }
            if has(Array(
                "age-encryption.org/v1".utf8)) {
                let text = String(
                    bytes: data.prefix(4096),
                    encoding: .utf8) ?? ""
                let recipients = text
                    .components(
                        separatedBy: .newlines)
                    .filter {
                        $0.hasPrefix("-> ")
                    }
                icsSay(emit, L("an age file (age-encryption.org)"), .sys)
                for line in recipients {
                    let kind = line
                        .dropFirst(3)
                        .components(
                            separatedBy: " ")
                        .first ?? ""
                    icsSay(emit, String(format: L("recipient stanza: %@"), String(kind)))
                }
                if recipients.isEmpty {
                    icsSay(emit, L("the header names no recipient stanza in its first lines"))
                }
                return
            }
            if has([0x4C, 0x55, 0x4B, 0x53,
                    0xBA, 0xBE]) {
                // "LUKS" + 0xBABE
                let version = data.count
                    >= 8
                    ? Int(data[6]) << 8
                        | Int(data[7]) : 0
                icsSay(emit, String(format: L("a LUKS disk-encryption header, v%lld"), Int64(version)), .sys)
                if version == 1,
                   data.count >= 208 {
                    func field(_ from: Int,
                               _ len: Int)
                        -> String {
                        String(bytes: Array(
                            data[from..<(from + len)]),
                               encoding: .ascii)?
                            .trimmingCharacters(
                                in: CharacterSet(
                                    charactersIn: "\0 "))
                            ?? ""
                    }
                    icsSay(emit, String(format: L("cipher %@ in %@ mode, digests by %@"), field(8, 32), field(40, 32), field(72, 32)))
                    icsSay(emit, String(format: L("volume UUID: %@"), field(168, 40)))
                } else if version == 2 {
                    icsSay(emit, L("LUKS2 keeps its papers in a JSON area — the header is named; the bench does not grade its segments from here"))
                }
                return
            }
            if has(Array("%PDF-".utf8)) {
                let headText = String(
                    bytes: data.prefix(8192),
                    encoding: .ascii) ?? ""
                let tailText = String(
                    bytes: data.suffix(8192),
                    encoding: .ascii) ?? ""
                if headText.contains(
                    "/Encrypt")
                    || tailText.contains(
                        "/Encrypt") {
                    icsSay(emit, L("a PDF carrying an /Encrypt dictionary — the document is encrypted; its strength rides on the handler revision, which the trailer names"), .sys)
                } else {
                    icsSay(emit, L("a PDF with no /Encrypt dictionary in its head or trailer — not an encrypted document"))
                }
                return
            }
            if has([0x50, 0x4B, 0x03, 0x04]) {
                var entries = 0
                var encrypted = 0
                var aes = 0
                var at = 0
                while at + 30 <= data.count,
                      Array(data[at..<(at + 4)])
                        == [0x50, 0x4B,
                            0x03, 0x04] {
                    let flags = Int(
                        data[at + 6])
                        | Int(data[at + 7])
                            << 8
                    let method = Int(
                        data[at + 8])
                        | Int(data[at + 9])
                            << 8
                    let csize = Int(
                        data[at + 18])
                        | Int(data[at + 19])
                            << 8
                        | Int(data[at + 20])
                            << 16
                        | Int(data[at + 21])
                            << 24
                    let nlen = Int(
                        data[at + 26])
                        | Int(data[at + 27])
                            << 8
                    let elen = Int(
                        data[at + 28])
                        | Int(data[at + 29])
                            << 8
                    entries += 1
                    if flags & 1 != 0 {
                        encrypted += 1
                    }
                    let nameFrom = at + 30
                    let extraFrom = nameFrom
                        + nlen
                    if extraFrom + elen
                        <= data.count {
                        let extra = Array(
                            data[extraFrom..<(
                                extraFrom + elen)])
                        var scan = 0
                        while scan + 1
                                < extra.count {
                            if extra[scan]
                                == 0x01,
                               extra[scan + 1]
                                == 0x99 {
                                aes += 1
                                break
                            }
                            scan += 1
                        }
                    }
                    _ = method
                    if flags & 0x08 != 0 {
                        icsSay(emit, L("an entry streams behind a data descriptor — the census counts the entries it can step over and stops the walk there"))
                        break
                    }
                    at += 30 + nlen + elen
                        + csize
                }
                icsSay(emit, String(format: L("a ZIP archive: %lld entries stepped over, %lld flagged encrypted, %lld carrying the AES extra field"), Int64(entries), Int64(encrypted), Int64(aes)), .sys)
                if encrypted == 0 {
                    icsSay(emit, L("no entry is flagged encrypted — a container, not a safe"))
                } else if aes == 0
                            && encrypted > 0 {
                    icsSay(emit, L("encrypted entries without the AES extra field wear legacy ZipCrypto — a lock long since picked; treat it as obfuscation"), .err)
                }
                return
            }
            if let first = data.first,
               first & 0x80 != 0 {
                // A plausible first
                // OpenPGP packet: the
                // header bit stands and
                // the tag is one a real
                // file opens with.
                let tag = first & 0x40 != 0
                    ? Int(first & 0x3F)
                    : Int((first >> 2)
                        & 0x0F)
                if [2, 6, 13, 14]
                    .contains(tag) {
                    icsSay(emit, L("the bytes open as OpenPGP packets — pgpprobe walks them"), .sys)
                    return
                }
            }
            let magics: [([UInt8], String)] = [
                ([0x37, 0x7A, 0xBC, 0xAF,
                  0x27, 0x1C],
                 "a 7-Zip archive — its headers may themselves be encrypted, in which case even the file list is sealed"),
                ([0x52, 0x61, 0x72, 0x21,
                  0x1A, 0x07, 0x01, 0x00],
                 "a RAR5 archive"),
                ([0x52, 0x61, 0x72, 0x21,
                  0x1A, 0x07, 0x00],
                 "a RAR archive (pre-5)"),
                ([0x1F, 0x8B],
                 "gzip — compressed, NOT encrypted; anyone may read it"),
                ([0x42, 0x5A, 0x68],
                 "bzip2 — compressed, NOT encrypted"),
                ([0xFD, 0x37, 0x7A, 0x58,
                  0x5A, 0x00],
                 "xz — compressed, NOT encrypted"),
                ([0x28, 0xB5, 0x2F, 0xFD],
                 "zstd — compressed, NOT encrypted"),
            ]
            for (magic, line) in magics
                where has(magic) {
                icsSay(emit, line, .sys)
                return
            }
            let stats = lockStats(Array(
                data.prefix(65536)))
            icsSay(emit, String(format: L("unidentified — no papers match, and the first %lld bytes run %.3f bits of entropy per byte"), Int64(stats.count), stats.entropy), .err)
            icsSay(emit, L("a well-sealed blob and a random one look alike from outside — that is rather the point of them; some containers (a mawkbox song, a time-locked box) carry no papers by design and will always read this way"))
        }
    }
}

extension BlacksiteBench {

    // MARK: sigprobe

    static func lockDERLength(
        _ n: Int) -> [UInt8] {
        if n < 0x80 {
            return [UInt8(n)]
        }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF),
                         at: 0)
            v >>= 8
        }
        return [0x80 | UInt8(bytes.count)]
            + bytes
    }

    static func lockDERInteger(
        _ value: LockBig) -> [UInt8] {
        var bytes = value.toBytes()
        if bytes.isEmpty {
            bytes = [0]
        }
        if let top = bytes.first,
           top & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return [0x02]
            + lockDERLength(bytes.count)
            + bytes
    }

    /// sigprobe <keyfile> <msgfile>
    /// <sigfile|sighex:…> — verify a
    /// signature over a file the
    /// operator brings, with the key
    /// the operator brings. The answer
    /// is exactly VALID or NOT VALID;
    /// the bench signs nothing here.
    static func sigprobe(
        spec: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let tokens = spec.components(
                separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard tokens.count >= 3 else {
                icsSay(emit, L("sigprobe: sigprobe <key file> <message file> <signature file | sighex:…>"), .err)
                return
            }
            guard let keyFile = lockReadFile(
                tokens[0]) else {
                icsSay(emit, L("no key file at the first path"), .err)
                return
            }
            guard let msgFile = lockReadFile(
                tokens[1]) else {
                icsSay(emit, L("no message file at the second path"), .err)
                return
            }
            var signature: [UInt8]?
            if tokens[2].hasPrefix(
                "sighex:") {
                signature = lockHexDecode(
                    String(tokens[2]
                        .dropFirst(7)))
            } else if let sigFile =
                lockReadFile(tokens[2]) {
                signature = [UInt8](
                    sigFile.data)
            }
            guard let signature = signature
            else {
                icsSay(emit, L("no signature at the third argument — give a file or sighex:<hex>"), .err)
                return
            }
            let message = msgFile.data
            icsSay(emit, String(format: L("message: %@ (%lld bytes) · signature: %lld bytes"), msgFile.path, Int64(message.count), Int64(signature.count)), .sys)
            // Resolve the key material.
            var spki: LockKeyInfo?
            let keyBytes = [UInt8](
                keyFile.data)
            if let text = String(
                bytes: keyBytes,
                encoding: .utf8) {
                if let block =
                    lockPEMBlocks(text)
                        .first {
                    spki = lockParseSPKI(
                        block.der)
                }
                if spki == nil {
                    let parts = text
                        .components(
                            separatedBy: .whitespaces)
                        .filter {
                            !$0.isEmpty
                        }
                    if parts.count >= 2,
                       let blob = Data(
                        base64Encoded:
                            parts[1]),
                       let parsed =
                        lockParseSSHBlob(
                            [UInt8](blob)) {
                        lockVerifySSHKey(
                            parsed: parsed,
                            message: message,
                            signature: signature,
                            emit: emit)
                        return
                    }
                }
            }
            if spki == nil {
                spki = lockParseSPKI(keyBytes)
            }
            guard let info = spki else {
                icsSay(emit, L("the key file parses as neither a PEM/DER public key nor an OpenSSH line"), .err)
                return
            }
            lockVerifySPKIKey(
                info: info,
                spkiDER: keyBytes,
                message: message,
                signature: signature,
                emit: emit)
        }
    }

    static func lockVerifySPKIKey(
        info: LockKeyInfo,
        spkiDER: [UInt8],
        message: Data,
        signature: [UInt8],
        emit: @escaping BlacksiteEmit) {
        // The raw public payload rides
        // inside the SPKI; re-walk to it.
        switch info.family {
        case "Ed25519":
            guard let top = lockTLV(
                spkiDER, 0) else {
                return
            }
            let kids = lockChildrenFull(
                spkiDER, top.cs, top.ce)
            guard kids.count == 2 else {
                return
            }
            let raw = Array(spkiDER[
                (kids[1].cs + 1)..<kids[1].ce])
            guard raw.count == 32,
                  let key = try? Curve25519
                    .Signing.PublicKey(
                        rawRepresentation: raw)
            else {
                icsSay(emit, L("the Ed25519 key material does not load"), .err)
                return
            }
            let ok = key.isValidSignature(
                signature, for: message)
            icsSay(emit, ok
                   ? L("VALID — the Ed25519 signature verifies over the message")
                   : L("NOT VALID — the signature does not verify over this message with this key"), ok ? .ok : .err)
        case "EC":
            guard let point = info.ecPoint
            else { return }
            lockVerifyECPoint(
                point: point,
                curveOID: info.ecCurveOID,
                message: message,
                signature: signature,
                emit: emit)
        case "RSA":
            guard let n = info.rsaModulus,
                  let e = info.rsaExponent
            else { return }
            lockVerifyRSA(
                n: n, e: e,
                message: message,
                signature: signature,
                emit: emit)
        default:
            icsSay(emit, String(format: L("verification for the %@ family is not carried — the key is named, the signature untested"), info.family), .err)
        }
    }

    static func lockVerifySSHKey(
        parsed: (type: String,
                 fields: [[UInt8]]),
        message: Data,
        signature: [UInt8],
        emit: @escaping BlacksiteEmit) {
        let fields = parsed.fields
        switch parsed.type {
        case "ssh-ed25519":
            guard fields.count >= 2,
                  let key = try? Curve25519
                    .Signing.PublicKey(
                        rawRepresentation:
                            fields[1])
            else {
                icsSay(emit, L("the Ed25519 key material does not load"), .err)
                return
            }
            let ok = key.isValidSignature(
                signature, for: message)
            icsSay(emit, ok
                   ? L("VALID — the Ed25519 signature verifies over the message")
                   : L("NOT VALID — the signature does not verify over this message with this key"), ok ? .ok : .err)
        case "ssh-rsa":
            guard fields.count >= 3 else {
                return
            }
            let e = LockBig.fromBytes(
                fields[1])
            let n = LockBig.fromBytes(
                fields[2])
            lockVerifyRSA(
                n: n, e: e,
                message: message,
                signature: signature,
                emit: emit)
        default:
            if parsed.type.hasPrefix(
                "ecdsa-sha2-"),
               fields.count >= 3 {
                let curveName = String(
                    bytes: fields[1],
                    encoding: .ascii) ?? ""
                let oid: String?
                switch curveName {
                case "nistp256":
                    oid = "1.2.840.10045.3.1.7"
                case "nistp384":
                    oid = "1.3.132.0.34"
                case "nistp521":
                    oid = "1.3.132.0.35"
                default:
                    oid = nil
                }
                lockVerifyECPoint(
                    point: fields[2],
                    curveOID: oid,
                    message: message,
                    signature: signature,
                    emit: emit)
                return
            }
            icsSay(emit, String(format: L("verification for %@ keys is not carried"), parsed.type), .err)
        }
    }

    static func lockVerifyECPoint(
        point: [UInt8], curveOID: String?,
        message: Data,
        signature: [UInt8],
        emit: @escaping BlacksiteEmit) {
        // The signature may arrive as
        // DER (openssl's way) or as the
        // raw r‖s pair (SSH's way).
        func derSig(_ bytes: [UInt8])
            -> [UInt8]? {
            guard let top = lockTLV(
                bytes, 0), top.tag == 0x30
            else { return nil }
            let parts = lockChildrenFull(
                bytes, top.cs, top.ce)
            guard parts.count == 2
            else { return nil }
            return bytes
        }
        switch curveOID {
        case "1.2.840.10045.3.1.7":
            guard let key = try? P256
                .Signing.PublicKey(
                    x963Representation: point)
            else {
                icsSay(emit, L("the P-256 point does not load"), .err)
                return
            }
            var sig: P256.Signing
                .ECDSASignature?
            if let der = derSig(signature) {
                sig = try? P256.Signing
                    .ECDSASignature(
                        derRepresentation:
                            der)
            }
            if sig == nil {
                sig = try? P256.Signing
                    .ECDSASignature(
                        rawRepresentation:
                            signature)
            }
            guard let sig = sig else {
                icsSay(emit, L("the signature is neither DER nor a raw r‖s pair of the right size — no verdict"), .err)
                return
            }
            let ok = key.isValidSignature(
                sig, for: message)
            icsSay(emit, ok
                   ? L("VALID — the ECDSA signature verifies (P-256, over SHA-256)")
                   : L("NOT VALID — the signature does not verify over this message with this key"), ok ? .ok : .err)
        case "1.3.132.0.34":
            guard let key = try? P384
                .Signing.PublicKey(
                    x963Representation: point)
            else {
                icsSay(emit, L("the P-384 point does not load"), .err)
                return
            }
            var sig: P384.Signing
                .ECDSASignature?
            if let der = derSig(signature) {
                sig = try? P384.Signing
                    .ECDSASignature(
                        derRepresentation:
                            der)
            }
            if sig == nil {
                sig = try? P384.Signing
                    .ECDSASignature(
                        rawRepresentation:
                            signature)
            }
            guard let sig = sig else {
                icsSay(emit, L("the signature is neither DER nor a raw r‖s pair of the right size — no verdict"), .err)
                return
            }
            let ok = key.isValidSignature(
                sig, for: message)
            icsSay(emit, ok
                   ? L("VALID — the ECDSA signature verifies (P-384, over SHA-384)")
                   : L("NOT VALID — the signature does not verify over this message with this key"), ok ? .ok : .err)
        default:
            icsSay(emit, L("ECDSA verification is carried for P-256 and P-384 — this point's curve is neither"), .err)
        }
    }

    static func lockVerifyRSA(
        n: LockBig, e: LockBig,
        message: Data,
        signature: [UInt8],
        emit: @escaping BlacksiteEmit) {
        let pkcs1 = lockDERInteger(n)
            + lockDERInteger(e)
        let der = [0x30]
            + lockDERLength(pkcs1.count)
            + pkcs1
        let attributes: [String: Any] = [
            kSecAttrKeyType as String:
                kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String:
                kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(
            Data(der) as CFData,
            attributes as CFDictionary,
            nil) else {
            icsSay(emit, L("the RSA key does not load"), .err)
            return
        }
        let attempts: [(
            SecKeyAlgorithm, String)] = [
            (.rsaSignatureMessagePKCS1v15SHA256,
             "RSA PKCS#1 v1.5 over SHA-256"),
            (.rsaSignatureMessagePKCS1v15SHA384,
             "RSA PKCS#1 v1.5 over SHA-384"),
            (.rsaSignatureMessagePKCS1v15SHA512,
             "RSA PKCS#1 v1.5 over SHA-512"),
            (.rsaSignatureMessagePKCS1v15SHA1,
             "RSA PKCS#1 v1.5 over SHA-1 (a dying hash — the signature verifies, and should still be re-made)"),
            (.rsaSignatureMessagePSSSHA256,
             "RSA-PSS over SHA-256"),
            (.rsaSignatureMessagePSSSHA384,
             "RSA-PSS over SHA-384"),
            (.rsaSignatureMessagePSSSHA512,
             "RSA-PSS over SHA-512"),
        ]
        for (algorithm, label) in attempts {
            guard SecKeyIsAlgorithmSupported(
                key, .verify, algorithm)
            else { continue }
            let ok = SecKeyVerifySignature(
                key, algorithm,
                message as CFData,
                Data(signature) as CFData,
                nil)
            if ok {
                icsSay(emit, String(format: L("VALID — %@"), label), .ok)
                return
            }
        }
        icsSay(emit, L("NOT VALID — no carried RSA scheme (PKCS#1 v1.5 or PSS, SHA-1 through SHA-512) verifies this signature over this message"), .err)
    }

    // MARK: totpprobe

    static func lockHOTP(
        seed: [UInt8], counter: UInt64,
        digits: Int, sha256: Bool,
        sha512: Bool) -> String {
        var counterBytes = Data()
        for shift in stride(
            from: 56, through: 0, by: -8) {
            counterBytes.append(UInt8(
                (counter >> UInt64(shift))
                    & 0xFF))
        }
        let mac: [UInt8]
        if sha512 {
            mac = [UInt8](HMAC<SHA512>
                .authenticationCode(
                    for: counterBytes,
                    using: SymmetricKey(
                        data: Data(seed))))
        } else if sha256 {
            mac = [UInt8](HMAC<SHA256>
                .authenticationCode(
                    for: counterBytes,
                    using: SymmetricKey(
                        data: Data(seed))))
        } else {
            mac = [UInt8](HMAC<Insecure.SHA1>
                .authenticationCode(
                    for: counterBytes,
                    using: SymmetricKey(
                        data: Data(seed))))
        }
        let offset = Int(mac[mac.count - 1]
            & 0x0F)
        let binary = (UInt32(mac[offset])
            & 0x7F) << 24
            | UInt32(mac[offset + 1]) << 16
            | UInt32(mac[offset + 2]) << 8
            | UInt32(mac[offset + 3])
        var modulus: UInt32 = 1
        for _ in 0..<digits {
            modulus *= 10
        }
        let code = binary % modulus
        return String(format: "%0\(digits)d",
                      Int(code))
    }

    /// totpprobe <seed> — the current
    /// time-based code for a seed the
    /// operator owns, with its
    /// neighbours a step either way.
    /// The seed arrives as base32
    /// (the authenticator convention),
    /// hex:…, or a whole otpauth://
    /// line; it is used in place and
    /// never printed back.
    static func totpprobe(
        spec: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var arg = spec
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("totpprobe: give your own seed — totpprobe JBSWY3DPEHPK3PXP"), .err)
                return
            }
            var digits = 6
            var period = 30
            var sha256 = false
            var sha512 = false
            var seedBytes: [UInt8]?
            var form = ""
            if arg.hasPrefix("otpauth://") {
                form = "otpauth"
                if let secretRange = arg
                    .range(of: "secret=") {
                    let rest = arg[
                        secretRange.upperBound...]
                    let secret = rest
                        .components(
                            separatedBy: "&")
                        .first ?? ""
                    seedBytes =
                        lockB32Decode(
                            String(secret))
                }
                if let d = arg.range(
                    of: "digits=") {
                    let rest = arg[d.upperBound...]
                    if let value = Int(
                        rest.components(
                            separatedBy: "&")
                            .first ?? "") {
                        digits = value
                    }
                }
                if let p = arg.range(
                    of: "period=") {
                    let rest = arg[p.upperBound...]
                    if let value = Int(
                        rest.components(
                            separatedBy: "&")
                            .first ?? "") {
                        period = value
                    }
                }
                if arg.contains(
                    "algorithm=SHA256") {
                    sha256 = true
                }
                if arg.contains(
                    "algorithm=SHA512") {
                    sha512 = true
                }
                arg = ""
            } else if arg.hasPrefix(
                "hex:") {
                form = "hex"
                seedBytes = lockHexDecode(
                    String(arg.dropFirst(4)))
            } else if arg.hasPrefix(
                "b32:") {
                form = "base32"
                seedBytes = lockB32Decode(
                    String(arg.dropFirst(4)))
            } else {
                form = "base32"
                seedBytes = lockB32Decode(
                    arg.replacingOccurrences(
                        of: " ", with: ""))
            }
            guard let seed = seedBytes,
                  seed.count >= 8 else {
                icsSay(emit, L("the seed does not decode (base32, hex:… or an otpauth:// line), or it runs under 8 bytes — too short to trust"), .err)
                return
            }
            digits = min(max(digits, 6), 8)
            period = min(max(period, 5), 300)
            let now = UInt64(
                Date().timeIntervalSince1970)
            let counter = now
                / UInt64(period)
            icsSay(emit, String(format: L("seed: %lld bytes, read as %@ — the seed itself is not printed"), Int64(seed.count), form), .sys)
            let marks = [L("previous step"),
                         L("this step"),
                         L("next step")]
            for (i, delta) in [-1, 0, 1]
                .enumerated() {
                let c = delta < 0
                    ? counter - 1
                    : counter
                        + UInt64(delta)
                let code = lockHOTP(
                    seed: seed, counter: c,
                    digits: digits,
                    sha256: sha256,
                    sha512: sha512)
                icsSay(emit, String(format: L("%@: %@"), marks[i], code), delta == 0 ? .ok : .out)
            }
            icsSay(emit, L("the codes ride on this device's clock — a clock minutes adrift makes honest codes look false"))
        }
    }

    // MARK: passprobe

    static let lockCommonWords: [String] = [
        "password", "123456", "123456789",
        "12345", "12345678", "qwerty",
        "1234567", "111111", "1234567890",
        "123123", "abc123", "1234",
        "password1", "iloveyou", "1q2w3e4r",
        "000000", "qwerty123", "zaq12wsx",
        "dragon", "sunshine", "princess",
        "letmein", "654321", "monkey",
        "27653", "1qaz2wsx", "123321",
        "qwertyuiop", "superman", "asdfghjkl",
        "master", "hello", "freedom",
        "whatever", "qazwsx", "trustno1",
        "football", "shadow", "michael",
        "cheese", "computer", "killer",
        "george", "samsung", "charlie",
        "jordan", "thomas", "hunter",
        "ranger", "buster", "soccer",
        "harley", "batman", "andrew",
        "tigger", "jessica", "pepper",
        "joshua", "maggie", "silver",
        "daniel", "hammer", "michelle",
        "welcome", "admin", "login",
        "starwars", "ninja", "mustang",
        "secret", "summer", "winter",
        "orange", "purple", "violet",
        "coffee", "banana", "monkey123",
    ]

    /// passprobe <the word itself> —
    /// a passphrase graded on shape
    /// alone: length, character
    /// classes, a charset-model entropy
    /// estimate, and a pass against
    /// the common lists and the usual
    /// patterns. It is an ESTIMATE,
    /// labelled one; the word is never
    /// printed back, stored or sent.
    static func passprobe(
        spec: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let word = spec
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            guard !word.isEmpty else {
                icsSay(emit, L("passprobe: type the word to grade — it is graded in place and never printed back"), .err)
                return
            }
            var lower = 0
            var upper = 0
            var digit = 0
            var symbol = 0
            var space = 0
            var wide = 0
            for scalar in word
                .unicodeScalars {
                switch scalar.value {
                case 97...122: lower += 1
                case 65...90: upper += 1
                case 48...57: digit += 1
                case 32: space += 1
                case 33...47, 58...64,
                     91...96, 123...126:
                    symbol += 1
                default: wide += 1
                }
            }
            var pool = 0
            if lower > 0 { pool += 26 }
            if upper > 0 { pool += 26 }
            if digit > 0 { pool += 10 }
            if symbol > 0 { pool += 32 }
            if space > 0 { pool += 1 }
            let length = word.count
            icsSay(emit, String(format: L("%lld characters (%lld bytes of UTF-8)"), Int64(length), Int64(word.utf8.count)), .sys)
            var classes: [String] = []
            if lower > 0 {
                classes.append(L("lowercase"))
            }
            if upper > 0 {
                classes.append(L("uppercase"))
            }
            if digit > 0 {
                classes.append(L("digits"))
            }
            if symbol > 0 {
                classes.append(L("symbols"))
            }
            if space > 0 {
                classes.append(L("spaces"))
            }
            if wide > 0 {
                classes.append(L("letters beyond ASCII"))
            }
            icsSay(emit, String(format: L("classes: %@"), classes.joined(separator: ", ")))
            if pool > 0 {
                let estimate = Double(
                    length) * log2(
                        Double(pool))
                icsSay(emit, String(format: L("charset model: a pool of %lld even-drawn symbols makes ≈ %.0f bits — an estimate from shape alone; real words are never drawn evenly, so treat it as a ceiling, not a measure"), Int64(pool), estimate))
            }
            // The common lists + the
            // leetspeak twin.
            let lowered = word.lowercased()
            let leet = lowered
                .replacingOccurrences(
                    of: "0", with: "o")
                .replacingOccurrences(
                    of: "1", with: "l")
                .replacingOccurrences(
                    of: "3", with: "e")
                .replacingOccurrences(
                    of: "4", with: "a")
                .replacingOccurrences(
                    of: "5", with: "s")
                .replacingOccurrences(
                    of: "7", with: "t")
                .replacingOccurrences(
                    of: "@", with: "a")
                .replacingOccurrences(
                    of: "$", with: "s")
            var flagged = false
            if lockCommonWords.contains(
                lowered) {
                icsSay(emit, L("the word stands verbatim on the common lists — it will be among the first tried against any door, and it will fall"), .err)
                flagged = true
            } else if leet != lowered,
                      lockCommonWords.contains(
                        leet) {
                icsSay(emit, L("leetspeak spelling of a word on the common lists — the substitution buys almost nothing; crackers normalise it for free"), .err)
                flagged = true
            } else {
                for common in lockCommonWords
                    where common.count >= 5 {
                    if lowered.contains(
                        common) {
                        icsSay(emit, L("a word from the common lists rides inside it — dictionary cores are tried with every padding around them"), .err)
                        flagged = true
                        break
                    }
                }
            }
            // Shape patterns.
            let chars = Array(lowered)
            if Set(chars).count == 1,
               chars.count > 1 {
                icsSay(emit, L("one character repeated — shape alone gives it away"), .err)
                flagged = true
            }
            let rows = [
                "0123456789",
                "abcdefghijklmnopqrstuvwxyz",
                "qwertyuiop", "asdfghjkl",
                "zxcvbnm",
            ]
            for row in rows {
                let rowChars = Array(row)
                var run = 1
                var bestRun = 1
                if chars.count > 1 {
                    for i in 1..<chars.count {
                        if let a = rowChars
                            .firstIndex(
                                of: chars[i - 1]),
                           let b = rowChars
                            .firstIndex(
                                of: chars[i]),
                           b == a + 1
                            || b == a - 1 {
                            run += 1
                        } else {
                            run = 1
                        }
                        bestRun = max(
                            bestRun, run)
                    }
                }
                if bestRun >= 4 {
                    icsSay(emit, L("a sequential run of four or more (alphabet, digits or keyboard row) — sequences are free guesses"), .err)
                    flagged = true
                    break
                }
            }
            if length >= 4 {
                for unit in 1...(length / 2)
                    where length % unit == 0 {
                    let head = String(
                        chars.prefix(unit))
                    let rebuilt = String(
                        repeating: head,
                        count: length / unit)
                    if rebuilt == lowered,
                       length / unit >= 2 {
                        icsSay(emit, L("the word is one short unit repeated — its true length is the unit's"), .err)
                        flagged = true
                        break
                    }
                }
            }
            if !flagged {
                if length >= 16 {
                    icsSay(emit, L("no common-list or pattern finding — length like this, in several classes, is what a strong passphrase looks like from outside"), .ok)
                } else if length >= 12 {
                    icsSay(emit, L("no common-list or pattern finding — a fair shape; length is the cheapest strength there is, and more of it would help"))
                } else {
                    icsSay(emit, L("no common-list or pattern finding — but short is short: an offline cracker with the hash tries the small spaces first"))
                }
            }
            icsSay(emit, L("the word was graded where it stands and is already forgotten by the bench — nothing was stored or sent"))
        }
    }

    // MARK: lockcensus

    /// lockcensus <host> — the locks
    /// of one host on one board: the
    /// TLS versions and the landed
    /// suite, the papers, and the SSH
    /// host key with its pin state.
    /// Every read here is one the
    /// dedicated verbs make; the board
    /// is their summary, not a new
    /// probe.
    static func lockcensus(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("lockcensus: give a host — lockcensus example.com"), .err)
                return
            }
            guard let resolved = icsResolve(
                arg, 443) else {
                icsSay(emit, L("lockcensus: give a host — lockcensus example.com"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            icsSay(emit, String(format: L("%@ (%@) — one board"), host, ip), .sys)
            // TLS: an unpinned modern
            // knock and the version
            // answers, compactly.
            let versions: [(String,
                            SSLProtocol)] = [
                ("TLS 1.3", .tlsProtocol13),
                ("TLS 1.2", .tlsProtocol12),
                ("TLS 1.1", .tlsProtocol11),
            ]
            var answered: [String] = []
            var leafCert: LockCert?
            var landed = ""
            for (name, proto) in versions {
                let knock = lockTLSKnock(
                    ip: ip, port: Int(resolved.port),
                    host: host, minV: proto,
                    maxV: proto,
                    onlySuite: nil)
                if knock.answered {
                    answered.append(name)
                    if landed.isEmpty,
                       let suite =
                        lockSuiteLine(
                            code: knock.cipher) {
                        landed = suite
                    }
                    if leafCert == nil,
                       let trust = knock.trust,
                       let leaf = certChain(
                        trust).first,
                       let data =
                        SecCertificateCopyData(
                            leaf) as Data? {
                        leafCert =
                            lockCertParse(
                                [UInt8](data))
                    }
                }
            }
            if answered.isEmpty {
                icsSay(emit, L("TLS: no version answered on this door"))
            } else {
                icsSay(emit, String(format: L("TLS: %@ answer%@"), answered.joined(separator: ", "), landed.isEmpty ? "" : String(format: L(" — a modern handshake lands on %@"), landed)), answered.contains("TLS 1.3") || answered.contains("TLS 1.2") ? .out : .err)
            }
            if let cert = leafCert {
                let sig = lockSigName(
                    cert.sigOID)
                var line = String(format: L("papers: %@ — issued by %@, signed %@"), cert.subjectLine, cert.issuerLine, sig.name)
                if let na = cert.notAfter {
                    let days = Int(
                        na.timeIntervalSinceNow
                            / 86400)
                    line += String(format: L(", %lld days left"), Int64(days))
                }
                icsSay(emit, line)
                if let info = cert.keyInfo {
                    icsSay(emit, String(format: L("key: %@ — %@"), info.family, info.detail))
                }
            }
            // SSH: the presented key
            // and its pin state.
            let client = SSHClient(
                host: host, port: 22,
                user: "bench")
            client.timeout = 8
            do {
                try client.handshake()
            } catch {
                // The refusal is the
                // census road, as in
                // sshkeydeep.
            }
            let blob = client.hostKeyBlob
            if !blob.isEmpty {
                let bytes = [UInt8](blob)
                let digest = SHA256.hash(
                    data: blob)
                let b64 = Data(digest)
                    .base64EncodedString()
                    .replacingOccurrences(
                        of: "=", with: "")
                var line = String(format: L("SSH: a %@ host key, SHA256 %@"), client.hostAlgorithm, b64)
                if let known = CryptoSuite
                    .NetCred.knownKey(
                        host: host, port: 22) {
                    line += Data(bytes)
                        == known
                        ? L(" — matches the house pin")
                        : L(" — DOES NOT match the house pin")
                } else {
                    line += L(" — not pinned in the house book")
                }
                icsSay(emit, line)
            } else {
                icsSay(emit, L("SSH: no host key was presented on door 22"))
            }
            client.disconnect()
        }
    }
}
