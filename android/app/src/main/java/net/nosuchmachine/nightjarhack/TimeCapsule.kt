package net.nosuchmachine.nightjarhack

import android.util.Base64
import org.json.JSONObject
import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom

/// Time capsule — the Kotlin mirror of the iOS TimeCapsule:
/// a Knocktalk message under a time-lock, in the Magic Box
/// manner — Rivest–Shamir–Wagner repeated squaring.
///
/// The lock is a 1024-bit RSA modulus n whose factors the
/// sealer forges, uses once (to compute the opened state
/// instantly, through φ(n)), and discards. Inside, a random
/// one-time key K seals the message with the usual
/// Knocktalk suites; K is masked by the hash of
/// b = a^(2^t) mod n. The sealer reaches b through the φ
/// shortcut. Anyone else must square a, t times, one after
/// another — the squarings are inherently sequential, so t
/// is calibrated against a measured rate on this phone to
/// mean a real delay.
///
/// Honest limits, stated in the UI too: a time-lock DELAYS,
/// it does not schedule. Anyone holding the capsule may
/// grind it, faster hardware finishes sooner, and nothing
/// stops a grind started early. The capsule is a small
/// JSON blob — carry it by any means; the lock travels
/// with it.
///
/// Where the iOS build hand-rolls Montgomery limb
/// arithmetic (Swift has no bignum), this port uses
/// java.math.BigInteger — the modular arithmetic is the
/// same arithmetic, so a capsule sealed on one platform
/// opens on the other.
object TimeCapsule {
    private const val MODULUS_BYTES = 128  // 1024-bit

    /** Cancellation handle for a grind in flight. */
    class GrindControl {
        @Volatile var cancelled = false
    }

    private fun toFixedBytes(value: BigInteger): ByteArray {
        val raw = value.toByteArray()
        val out = ByteArray(MODULUS_BYTES)
        val count = minOf(raw.size, MODULUS_BYTES)
        System.arraycopy(
            raw, raw.size - count, out, MODULUS_BYTES - count,
            count)
        return out
    }

    private fun randomBelow(n: BigInteger, random: SecureRandom): BigInteger {
        while (true) {
            val candidate = BigInteger(1024, random)
            if (candidate > BigInteger.ZERO &&
                candidate < n - BigInteger.ONE) {
                return candidate
            }
        }
    }

    /** Seal `message` under a time-lock of about `seconds`
     * (calibrated on this device). Heavy — call off the
     * main thread. Returns the capsule blob, or null. */
    fun seal(
        message: String, seconds: Double, suite: Int,
        status: (String) -> Unit
    ): String? {
        val random = SecureRandom()
        status("Forging the lock — two 512-bit primes…")
        val p = BigInteger.probablePrime(512, random)
        val q = BigInteger.probablePrime(512, random)
        if (p == q) return null
        val n = p.multiply(q)
        // φ(n) = n − p − q + 1 (the factors die with this scope)
        val phi = n - p - q + BigInteger.ONE
        val a = randomBelow(n, random)

        status("Calibrating the grind on this phone…")
        var spin = a
        val start = System.nanoTime()
        repeat(300) { spin = spin.multiply(spin).mod(n) }
        val elapsed = maxOf(
            (System.nanoTime() - start) / 1e9, 0.001)
        val rate = 300.0 / elapsed
        val t = maxOf(1000, (rate * seconds).toInt())

        // b by the φ shortcut: b = a^(2^t mod φ) mod n.
        val e = BigInteger.TWO.modPow(
            BigInteger.valueOf(t.toLong()), phi)
        val b = a.modPow(e, n)

        val mask = MessageDigest.getInstance("SHA-256")
            .digest(toFixedBytes(b))
        val keyBytes = ByteArray(32)
        random.nextBytes(keyBytes)
        val masked = ByteArray(32) {
            (keyBytes[it].toInt() xor mask[it].toInt()).toByte()
        }
        val sealed = try {
            Knocktalk.seal(
                message, keyBytes, suite)
        } catch (_: Exception) {
            return null
        }
        val blob = JSONObject()
        blob.put("nj-capsule", 1)
        blob.put("n", Base64.encodeToString(
            toFixedBytes(n), Base64.NO_WRAP))
        blob.put("a", Base64.encodeToString(
            toFixedBytes(a), Base64.NO_WRAP))
        blob.put("t", t)
        blob.put("masked", Base64.encodeToString(
            masked, Base64.NO_WRAP))
        blob.put("suite", suite)
        blob.put("box", Base64.encodeToString(
            sealed, Base64.NO_WRAP))
        val json = blob.toString().toByteArray(Charsets.UTF_8)
        return Base64.encodeToString(json, Base64.NO_WRAP)
    }

    /** Grind a capsule open. Runs wherever it is called —
     * call off the main thread. Progress is 0…1 across the
     * squarings. Returns the message, or null. */
    fun grind(
        blob: String, control: GrindControl,
        progress: (Double) -> Unit
    ): String? {
        val raw = try {
            Base64.decode(blob.trim(), Base64.DEFAULT)
        } catch (_: Exception) {
            return null
        }
        val obj = try {
            JSONObject(String(raw, Charsets.UTF_8))
        } catch (_: Exception) {
            return null
        }
        if (obj.optInt("nj-capsule", 0) != 1) return null
        val nData = decodeField(obj, "n") ?: return null
        val aData = decodeField(obj, "a") ?: return null
        if (nData.size != MODULUS_BYTES ||
            aData.size != MODULUS_BYTES) {
            return null
        }
        val n = BigInteger(1, nData)
        var x = BigInteger(1, aData)
        val t = obj.optInt("t", -1)
        if (t < 0) return null
        val masked = decodeField(obj, "masked") ?: return null
        if (masked.size != 32) return null
        val suite = obj.optInt("suite", -1)
        if (suite < 0) return null
        val box = decodeField(obj, "box") ?: return null

        val stride = 2048
        var done = 0
        while (done < t) {
            if (control.cancelled) return null
            val step = minOf(stride, t - done)
            repeat(step) { x = x.multiply(x).mod(n) }
            done += step
            progress(done.toDouble() / t)
        }
        val mask = MessageDigest.getInstance("SHA-256")
            .digest(toFixedBytes(x))
        val keyBytes = ByteArray(32) {
            (masked[it].toInt() xor mask[it].toInt()).toByte()
        }
        return Knocktalk.open(box, keyBytes, suite)
    }

    private fun decodeField(
        obj: JSONObject, name: String
    ): ByteArray? {
        val value = obj.optString(name, "")
        if (value.isEmpty()) return null
        return try {
            Base64.decode(value, Base64.DEFAULT)
        } catch (_: Exception) {
            null
        }
    }
}
