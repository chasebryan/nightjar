import CryptoKit
import Foundation

/// Time capsule: a Knocktalk message under a time-lock, in the
/// Magic Box manner — Rivest–Shamir–Wagner repeated squaring.
///
/// The lock is a 1024-bit RSA modulus n whose factors the
/// sealer forges, uses once (to compute the opened state
/// instantly, through φ(n)), and discards. Inside, a random
/// one-time key K seals the message with the usual Knocktalk
/// suites; K is masked by the hash of b = a^(2^t) mod n. The
/// sealer reaches b through the φ shortcut. Anyone else must
/// square a, t times, one after another — the squarings are
/// inherently sequential, so t is calibrated against a
/// measured rate on this phone to mean a real delay.
///
/// Honest limits, stated in the UI too: a time-lock DELAYS, it
/// does not schedule. Anyone holding the capsule may grind it,
/// faster hardware finishes sooner, and nothing stops a
/// grind started early. The capsule is a small JSON blob —
/// carry it by any means; the lock travels with it.
///
/// The bignum core is a fixed-limb Montgomery multiplier —
/// no division anywhere — verified limb-for-limb against a
/// reference implementation before it was ported here.

// MARK: - limb arithmetic ([UInt64], little-endian)

enum Limbs {
    static func cmp(_ a: [UInt64], _ b: [UInt64]) -> Int {
        var i = a.count - 1
        while i >= 0 {
            if a[i] != b[i] { return a[i] < b[i] ? -1 : 1 }
            i -= 1
        }
        return 0
    }

    /// a − b, requiring a ≥ b.
    static func sub(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var out = a
        var borrow = false
        for i in 0..<a.count {
            let (d1, o1) = out[i].subtractingReportingOverflow(b[i])
            let (d2, o2) = d1.subtractingReportingOverflow(
                borrow ? 1 : 0)
            out[i] = d2
            borrow = o1 || o2
        }
        return out
    }

    static func subSmall(_ a: [UInt64], _ v: UInt64) -> [UInt64] {
        var out = a
        var borrow = v
        for i in 0..<out.count where borrow > 0 {
            let (d, o) = out[i].subtractingReportingOverflow(borrow)
            out[i] = d
            borrow = o ? 1 : 0
        }
        return out
    }

    static func addSmall(_ a: [UInt64], _ v: UInt64) -> [UInt64] {
        var out = a
        var carry = v
        for i in 0..<out.count where carry > 0 {
            let (s, o) = out[i].addingReportingOverflow(carry)
            out[i] = s
            carry = o ? 1 : 0
        }
        return out
    }

    static func shr1(_ a: [UInt64]) -> [UInt64] {
        var out = a
        var carry: UInt64 = 0
        var i = a.count - 1
        while i >= 0 {
            let next = out[i] << 63
            out[i] = (out[i] >> 1) | carry
            carry = next
            i -= 1
        }
        return out
    }

    static func modSmall(_ a: [UInt64], _ p: UInt64) -> UInt64 {
        var rem: UInt64 = 0
        var i = a.count - 1
        while i >= 0 {
            // rem < p, so the full-width division is exact.
            rem = p.dividingFullWidth((high: rem, low: a[i]))
                .remainder
            i -= 1
        }
        return rem
    }

    /// Big-endian canonical bytes, exactly limbs*8 of them.
    static func dataBE(_ a: [UInt64]) -> Data {
        var out = Data()
        out.reserveCapacity(a.count * 8)
        for limb in a.reversed() {
            var be = limb.bigEndian
            withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        }
        return out
    }

    static func fromDataBE(_ data: Data, count: Int) -> [UInt64]? {
        guard data.count == count * 8 else { return nil }
        let bytes = [UInt8](data)
        var out = [UInt64](repeating: 0, count: count)
        for i in 0..<count {
            var v: UInt64 = 0
            for k in 0..<8 {
                v = (v << 8) | UInt64(bytes[(count - 1 - i) * 8 + k])
            }
            out[i] = v
        }
        return out
    }
}

// MARK: - Montgomery context

struct MontCtx {
    let n: [UInt64]
    let nPrime: UInt64
    let r2: [UInt64]
    var s: Int { n.count }

    init(modulus: [UInt64]) {
        n = modulus
        // n' = −n⁻¹ mod 2^64, by Hensel lifting.
        var inv: UInt64 = 1
        for _ in 0..<6 {
            inv = inv &* (2 &- modulus[0] &* inv)
        }
        nPrime = 0 &- inv
        // R² mod n by 2·s·64 doublings with conditional subtract.
        var x = [UInt64](repeating: 0, count: modulus.count + 1)
        x[0] = 1
        let nExt = modulus + [0]
        for _ in 0..<(2 * 64 * modulus.count) {
            var carry: UInt64 = 0
            for j in 0..<(modulus.count + 1) {
                let (v, o) = x[j].addingReportingOverflow(x[j])
                let (v2, o2) = v.addingReportingOverflow(carry)
                x[j] = v2
                carry = (o ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            if Limbs.cmp(x, nExt) >= 0 { x = Limbs.sub(x, nExt) }
        }
        r2 = Array(x[0..<modulus.count])
    }

    /// Montgomery product: a·b·R⁻¹ mod n, for a, b < n.
    /// CIOS form — the exact loop the reference test exercised.
    func montMul(_ a: [UInt64], _ b: [UInt64]) -> [UInt64] {
        var t = [UInt64](repeating: 0, count: s + 2)
        for i in 0..<s {
            var carry: UInt64 = 0
            for j in 0..<s {
                let (hi, lo) = a[j].multipliedFullWidth(by: b[i])
                let (s1, o1) = t[j].addingReportingOverflow(lo)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                t[j] = s2
                carry = hi &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (sv, ov) = t[s].addingReportingOverflow(carry)
            t[s] = sv
            t[s + 1] = ov ? 1 : 0
            let m = t[0] &* nPrime
            carry = 0
            for j in 0..<s {
                let (hi, lo) = n[j].multipliedFullWidth(by: m)
                let (s1, o1) = t[j].addingReportingOverflow(lo)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                t[j] = s2
                carry = hi &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            let (sv2, ov2) = t[s].addingReportingOverflow(carry)
            t[s] = sv2
            t[s + 1] &+= ov2 ? 1 : 0
            for j in 0..<(s + 1) { t[j] = t[j + 1] }
            t[s + 1] = 0
        }
        var r = Array(t[0..<(s + 1)])
        let nExt = n + [0]
        for _ in 0..<4 where Limbs.cmp(r, nExt) >= 0 {
            r = Limbs.sub(r, nExt)
        }
        return Array(r[0..<s])
    }

    func toMont(_ a: [UInt64]) -> [UInt64] { montMul(a, r2) }

    func fromMont(_ a: [UInt64]) -> [UInt64] {
        montMul(a, [1] + [UInt64](repeating: 0, count: s - 1))
    }

    /// base^exp in Montgomery form (base given in normal form).
    func powMont(_ base: [UInt64], _ exp: [UInt64]) -> [UInt64] {
        var result = toMont([1] + [UInt64](repeating: 0,
                                              count: s - 1))
        let b = toMont(base)
        var li = exp.count - 1
        while li >= 0 {
            var bit = 63
            while bit >= 0 {
                result = montMul(result, result)
                if (exp[li] >> bit) & 1 == 1 {
                    result = montMul(result, b)
                }
                bit -= 1
            }
            li -= 1
        }
        return result
    }
}

// MARK: - prime forging

enum PrimeForge {
    private static let smallPrimes: [UInt64] = [
        2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47,
        53, 59, 61, 67, 71, 73, 79, 83, 89, 97,
    ]

    /// A probable prime of `limbs` 64-bit limbs (Miller–Rabin,
    /// eight bases — the error bound is far below the chance
    /// the phone is struck by a meteor mid-forge).
    static func prime(limbs: Int) -> [UInt64] {
        while true {
            var cand = (0..<limbs).map { _ in
                UInt64.random(in: UInt64.min...UInt64.max)
            }
            cand[limbs - 1] |= (1 << 63) | (1 << 62)  // size + margin
            cand[0] |= 1                              // odd
            if smallPrimes.contains(where: {
                Limbs.modSmall(cand, $0) == 0
            }) { continue }
            if millerRabin(cand) { return cand }
        }
    }

    private static func millerRabin(_ n: [UInt64]) -> Bool {
        let ctx = MontCtx(modulus: n)
        let nMinus1 = Limbs.subSmall(n, 1)
        var d = nMinus1
        var twos = 0
        while d[0] & 1 == 0 {
            d = Limbs.shr1(d)
            twos += 1
        }
        let oneMont = ctx.toMont(
            [1] + [UInt64](repeating: 0, count: n.count - 1))
        let nm1Mont = ctx.toMont(nMinus1)
        for base in smallPrimes.prefix(8) {
            var b = [UInt64](repeating: 0, count: n.count)
            b[0] = base
            var x = ctx.powMont(b, d)
            if x == oneMont || x == nm1Mont { continue }
            var passed = false
            for _ in 0..<max(0, twos - 1) {
                x = ctx.montMul(x, x)
                if x == nm1Mont { passed = true; break }
            }
            if !passed { return false }
        }
        return true
    }
}

/// Cancellation handle for a grind in flight.
final class GrindControl {
    var cancelled = false
}

// MARK: - the capsule

enum TimeCapsule {
    static let modulusLimbs = 16   // 1024-bit
    static let halfLimbs = 8       // two 512-bit factors

    /// Schoolbook product for the modulus.
    private static func multiply(_ a: [UInt64],
                                 _ b: [UInt64]) -> [UInt64] {
        var out = [UInt64](repeating: 0,
                            count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            for j in 0..<b.count {
                let (hi, lo) = a[i].multipliedFullWidth(by: b[j])
                let (s1, o1) = out[i + j]
                    .addingReportingOverflow(lo)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                out[i + j] = s2
                carry = hi &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            out[i + b.count] &+= carry
        }
        return out
    }

    private static func randomBelow(_ n: [UInt64]) -> [UInt64] {
        while true {
            let cand = (0..<n.count).map { _ in
                UInt64.random(in: UInt64.min...UInt64.max)
            }
            if Limbs.cmp(cand, [UInt64](repeating: 0,
                                        count: n.count)) > 0,
               Limbs.cmp(cand, Limbs.subSmall(n, 1)) < 0 {
                return cand
            }
        }
    }

    /// Seal `message` under a time-lock of about `seconds`
    /// (calibrated on this device). Heavy — call off the main
    /// queue. Returns the capsule blob, or nil on failure.
    static func seal(message: String, seconds: Double, suite: Int,
                     status: @escaping (String) -> Void) -> String? {
        status("Forging the lock — two 512-bit primes…")
        let p = PrimeForge.prime(limbs: halfLimbs)
        let q = PrimeForge.prime(limbs: halfLimbs)
        guard p != q else { return nil }
        let n = multiply(p, q)
        // φ(n) = n − p − q + 1 (the factors die with this scope)
        var phi = Limbs.sub(n, p + [UInt64](repeating: 0,
                                           count: halfLimbs))
        phi = Limbs.sub(phi, q + [UInt64](repeating: 0,
                                          count: halfLimbs))
        phi = Limbs.addSmall(phi, 1)

        let ctx = MontCtx(modulus: n)
        let a = randomBelow(n)

        status("Calibrating the grind on this phone…")
        let probe = ctx.toMont(a)
        let start = Date()
        var spin = probe
        for _ in 0..<300 { spin = ctx.montMul(spin, spin) }
        _ = spin
        let elapsed = max(Date().timeIntervalSince(start), 0.001)
        let rate = 300.0 / elapsed
        let t = max(1000, Int(rate * seconds))

        // b by the φ shortcut: b = a^(2^t mod φ) mod n.
        let phiCtx = MontCtx(modulus: phi)
        var exp = [UInt64](repeating: 0, count: modulusLimbs)
        exp[0] = UInt64(t)
        let e = phiCtx.fromMont(phiCtx.powMont(
            [2] + [UInt64](repeating: 0, count: modulusLimbs - 1),
            exp))
        let b = ctx.fromMont(ctx.powMont(a, e))

        let mask = SHA256.hash(data: Limbs.dataBE(b))
        var keyBytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            keyBytes[i] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        let maskBytes = [UInt8](mask)
        let masked = Data(zip(keyBytes, maskBytes).map { $0 ^ $1 })
        guard let sealed = try? Knocktalk.seal(
            message,
            key: SymmetricKey(data: Data(keyBytes)),
            suite: suite) else { return nil }

        let blob: [String: Any] = [
            "nj-capsule": 1,
            "n": Limbs.dataBE(n).base64EncodedString(),
            "a": Limbs.dataBE(a).base64EncodedString(),
            "t": t,
            "masked": masked.base64EncodedString(),
            "suite": suite,
            "box": sealed.base64EncodedString(),
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: blob) else { return nil }
        return data.base64EncodedString()
    }

    /// Grind a capsule open. Runs wherever it is called —
    /// call off the main queue. Progress is 0…1 across the
    /// squarings. Completion receives the message, or nil.
    static func grind(blob: String, control: GrindControl,
                      progress: @escaping (Double) -> Void,
                      completion: @escaping (String?) -> Void) {
        guard let raw = Data(base64Encoded: blob
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              let obj = try? JSONSerialization.jsonObject(
                with: raw) as? [String: Any],
              obj["nj-capsule"] as? Int == 1,
              let nData = (obj["n"] as? String).flatMap({
                  Data(base64Encoded: $0) }),
              let aData = (obj["a"] as? String).flatMap({
                  Data(base64Encoded: $0) }),
              let n = Limbs.fromDataBE(nData, count: modulusLimbs),
              let a = Limbs.fromDataBE(aData, count: modulusLimbs),
              let t = obj["t"] as? Int,
              let masked = (obj["masked"] as? String).flatMap({
                  Data(base64Encoded: $0) }), masked.count == 32,
              let suite = obj["suite"] as? Int,
              let box = (obj["box"] as? String).flatMap({
                  Data(base64Encoded: $0) })
        else { completion(nil); return }

        let ctx = MontCtx(modulus: n)
        var x = ctx.toMont(a)
        let stride = 2048
        var done = 0
        while done < t {
            if control.cancelled { completion(nil); return }
            let step = min(stride, t - done)
            for _ in 0..<step { x = ctx.montMul(x, x) }
            done += step
            progress(Double(done) / Double(t))
        }
        let b = ctx.fromMont(x)
        let mask = [UInt8](SHA256.hash(data: Limbs.dataBE(b)))
        let keyBytes = zip([UInt8](masked), mask).map { $0 ^ $1 }
        let text = Knocktalk.open(
            sealed: box, key: SymmetricKey(data: Data(keyBytes)),
            suite: suite)
        completion(text)
    }
}
