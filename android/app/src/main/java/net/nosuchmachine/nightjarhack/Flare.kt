package net.nosuchmachine.nightjarhack

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/// Flare — the Kotlin mirror of the iOS Flare: recognition
/// without identity. A phone with flare up advertises, in
/// the FFF0 service-data slot, a short token only holders
/// of the pairing key can compute — an HMAC of the current
/// five-minute window. A paired phone listening sees the
/// token match and knows: one of ours is in radio range.
/// To everyone else on earth the token is eight random
/// bytes that change five minutes later, attached to a
/// rotating Bluetooth address — it names nobody, and
/// yesterday's token proves nothing about today.
///
/// What a flare does NOT do: locate, identify, or
/// authenticate a person. It is a lantern only key-holders
/// can see, carried by an address that itself rotates. The
/// match is checked against the neighboring windows too,
/// so two phones whose clocks disagree by a few minutes
/// still recognize each other.
object Flare {
    const val WINDOW_SECONDS = 300L

    fun window(nowMs: Long = System.currentTimeMillis()): Long =
        (nowMs / 1000) / WINDOW_SECONDS

    fun token(key: ByteArray, window: Long): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        mac.update("nightjar-flare".toByteArray(Charsets.UTF_8))
        val w = ByteArray(8)
        var value = window
        for (i in 7 downTo 0) {
            w[i] = (value and 0xFF).toByte()
            value = value shr 8
        }
        mac.update(w)
        return mac.doFinal().copyOf(8)
    }

    fun tokenNow(key: ByteArray): ByteArray = token(key, window())

    /** Does this FFF0 service-data payload carry a live
     * flare from a holder of the key? */
    fun matches(data: ByteArray, key: ByteArray): Boolean {
        val w = window()
        return listOf(-1L, 0L, 1L).any {
            token(key, w + it).contentEquals(data)
        }
    }
}
