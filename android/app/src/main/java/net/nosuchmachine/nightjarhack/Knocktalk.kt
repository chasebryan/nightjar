package net.nosuchmachine.nightjarhack

import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/// Knocktalk: encrypted messages carried by knock ORDER
/// alone — the Kotlin mirror of the iOS Knocktalk.
///
/// No connection is ever established and no payload byte is
/// ever sent. The sender knocks a sync port, then knocks
/// sixteen alphabet ports in an order that spells nibbles;
/// the receiver's tripwire refuses every knock, replies to
/// nothing — and its log spells a sealed box.
///
/// The nibbles carry an AEAD sealed box (nonce ‖ ciphertext
/// ‖ tag), sealed under a 256-bit pairing key. The tag is
/// the integrity check — a mangled sequence, or one sealed
/// under a different key, fails authentication and decodes
/// to nothing but a "sealed traffic" pattern note, which is
/// also exactly what an unpaired stranger's Knocktalk looks
/// like from the outside.
///
/// Honest limit: a pre-shared key has no forward secrecy.
/// The handshake that would fix that needs a reply channel,
/// and the tripwire never replies — that is rather the point.
object Knocktalk {
    /** Sixteen watched registry ports = one hex nibble each. */
    val alphabet: List<Int> = listOf(
        7, 9, 13, 19, 21, 22, 23, 25,
        43, 53, 70, 79, 80, 110, 111, 143)

    /** Knocked once to open a message window. */
    const val SYNC_PORT = 443

    /** Silence longer than this closes the window. */
    const val GAP_MS = 3500L
    const val MAX_CHARACTERS = 160

    // Protocol v2 — fragmentation + repair. v1 framed a whole
    // message as one knock stream: a single lost knock failed
    // the AEAD open and the message died silently. v2 seals
    // once, then fragments the sealed box. Each fragment frame
    // is [sync] [suite] [index] [total] [payload nibbles]
    // [checksum nibble] — the checksum (sum mod 16) exists so
    // a mangled fragment can be dropped and NACKed rather than
    // poisoning the reassembly; the AEAD tag remains the real
    // integrity, checked once, at the end. The receiver
    // answers in kind: an ACK frame ([sync] 15 15 + four hash
    // nibbles) on success, or a NACK frame ([sync] 14 14 +
    // the missing indices).
    const val FRAGMENT_PAYLOAD_BYTES = 12
    const val MAX_FRAGMENTS = 16

    /** Sealed bytes a message may occupy (16 × 12). */
    val maxSealedBytes: Int get() = MAX_FRAGMENTS * FRAGMENT_PAYLOAD_BYTES

    // Suites — cryptographic agility. Each operator configures
    // the suite THEY send with. The choice is not negotiated
    // and never has to match: a suite nibble rides at the head
    // of every fragment frame, and the receiver opens the
    // reassembled box with whatever suite the frames name.
    const val SUITE_CHACHA = 0
    const val SUITE_AESGCM = 1
    val suiteNames = listOf("ChaCha20-Poly1305", "AES-256-GCM")

    private const val NONCE_BYTES = 12
    private const val TAG_BITS = 128

    /** Seal into the combined form both suites share:
     * nonce(12) ‖ ciphertext ‖ tag(16). Throws when the
     * platform cannot speak the suite. */
    fun seal(plaintext: String, key: ByteArray, suite: Int): ByteArray {
        val data = plaintext.toByteArray(Charsets.UTF_8)
        val nonce = ByteArray(NONCE_BYTES)
        SecureRandom().nextBytes(nonce)
        val cipher = cipherFor(suite)
        cipher.init(
            Cipher.ENCRYPT_MODE,
            keySpec(suite, key),
            paramsFor(suite, nonce))
        return nonce + cipher.doFinal(data)
    }

    /** Open a combined box. Any failure — wrong length,
     * wrong key, one knock lost or doubled — returns null. */
    fun open(sealed: ByteArray, key: ByteArray, suite: Int): String? {
        if (sealed.size <= NONCE_BYTES + TAG_BITS / 8) return null
        if (suite != SUITE_CHACHA && suite != SUITE_AESGCM) {
            return null
        }
        return try {
            val nonce = sealed.copyOfRange(0, NONCE_BYTES)
            val body = sealed.copyOfRange(NONCE_BYTES, sealed.size)
            val cipher = cipherFor(suite)
            cipher.init(
                Cipher.DECRYPT_MODE,
                keySpec(suite, key),
                paramsFor(suite, nonce))
            String(cipher.doFinal(body), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun cipherFor(suite: Int): Cipher =
        if (suite == SUITE_AESGCM) {
            Cipher.getInstance("AES/GCM/NoPadding")
        } else {
            Cipher.getInstance("ChaCha20-Poly1305")
        }

    private fun keySpec(suite: Int, key: ByteArray): SecretKeySpec =
        if (suite == SUITE_AESGCM) {
            SecretKeySpec(key, "AES")
        } else {
            SecretKeySpec(key, "ChaCha20")
        }

    private fun paramsFor(
        suite: Int, nonce: ByteArray
    ): java.security.spec.AlgorithmParameterSpec =
        if (suite == SUITE_AESGCM) {
            GCMParameterSpec(TAG_BITS, nonce)
        } else {
            IvParameterSpec(nonce)
        }

    /** Fragment frames in the suite layout:
     * [sync] [suite] [index] [total] [payload] [checksum] —
     * an even nibble count, which also keeps them distinct
     * from legacy odd-count frames and from v1 streams. */
    fun fragmentFrames(sealed: ByteArray, suite: Int): List<List<Int>> {
        val chunks = mutableListOf<ByteArray>()
        var start = 0
        while (start < sealed.size) {
            val end = minOf(start + FRAGMENT_PAYLOAD_BYTES, sealed.size)
            chunks.add(sealed.copyOfRange(start, end))
            start = end
        }
        if (chunks.isEmpty()) chunks.add(ByteArray(0))
        val total = chunks.size
        return chunks.mapIndexed { index, chunk ->
            val nibbles = mutableListOf(suite, index, total)
            for (byte in chunk) {
                nibbles.add((byte.toInt() shr 4) and 0x0F)
                nibbles.add(byte.toInt() and 0x0F)
            }
            val check = nibbles.sum() % 16
            listOf(SYNC_PORT) + nibbles.map { alphabet[it] } +
                alphabet[check]
        }
    }

    /** The first two bytes of the sealed box's SHA-256, as
     * four nibbles — enough for the sender to match an ACK
     * to the message it names, far too little to learn
     * anything from. */
    fun hashNibbles(of: ByteArray): List<Int> {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(of)
        val b0 = digest[0].toInt()
        val b1 = digest[1].toInt()
        return listOf(
            (b0 shr 4) and 0x0F, b0 and 0x0F,
            (b1 shr 4) and 0x0F, b1 and 0x0F)
    }

    fun ackFrame(hash: List<Int>): List<Int> =
        listOf(SYNC_PORT) + listOf(15, 15).map { alphabet[it] } +
            hash.map { alphabet[it] }

    fun nackFrame(missing: List<Int>): List<Int> =
        listOf(SYNC_PORT) + listOf(14, 14).map { alphabet[it] } +
            missing.sorted().map { alphabet[it] }

    fun nibble(ofPort: Int): Int? {
        val index = alphabet.indexOf(ofPort)
        return if (index >= 0) index else null
    }

    /** Seal the message and spell the sealed box as a knock
     * sequence: [sync] + one knock per nibble (v1 framing). */
    fun encode(plaintext: String, key: ByteArray): List<Int> {
        val sealed = seal(plaintext, key, SUITE_CHACHA)
        val ports = mutableListOf(SYNC_PORT)
        for (byte in sealed) {
            ports.add(alphabet[(byte.toInt() shr 4) and 0x0F])
            ports.add(alphabet[byte.toInt() and 0x0F])
        }
        return ports
    }

    /** Reassemble nibbles and open the box (v1 framing). */
    fun decode(nibbles: List<Int>, key: ByteArray): String? {
        if (nibbles.size < 56 || nibbles.size % 2 != 0) return null
        val bytes = ByteArray(nibbles.size / 2)
        var index = 0
        while (index < nibbles.size) {
            bytes[index / 2] =
                ((nibbles[index] shl 4) or nibbles[index + 1]).toByte()
            index += 2
        }
        return open(bytes, key, SUITE_CHACHA)
    }

    /** Rough airtime of a sequence — the channel is a trickle
     * by design; the composer shows this before sending. */
    fun etaSeconds(knocks: Int): Int =
        Math.round(knocks * 0.55).toInt()
}

/// The pairing key — on iOS it lives in the Keychain; here it
/// lives in the app's private file store, which Android
/// sandboxes to this app alone. Never in preferences, never
/// in a log.
object KnockKeyStore {
    private fun keyFile(filesDir: File): File =
        File(filesDir, "knocktalk-key.txt")

    @Volatile
    private var filesDir: File? = null

    fun init(filesDir: File) {
        this.filesDir = filesDir
    }

    var keyHex: String?
        get() {
            val dir = filesDir ?: return null
            return try {
                keyFile(dir).readText().trim().ifBlank { null }
            } catch (_: Exception) {
                null
            }
        }
        set(value) {
            val dir = filesDir ?: return
            try {
                if (value == null) {
                    keyFile(dir).delete()
                } else {
                    keyFile(dir).writeText(value)
                }
            } catch (_: Exception) {
            }
        }

    val key: ByteArray?
        get() {
            val hex = keyHex ?: return null
            val data = try {
                PayloadKit.decodeHex(hex)
            } catch (_: Exception) {
                return null
            }
            return if (data.size == 32) data else null
        }

    /** A fresh 256-bit key, as the hex string two devices share. */
    fun generate(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    /** A display-safe fingerprint of a key (never the key itself). */
    fun fingerprint(ofHex: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(ofHex.toByteArray(Charsets.UTF_8))
        return digest.take(4).joinToString("") { "%02x".format(it) }
    }
}

data class KnockMessage(
    val id: String, val whenMs: Long, val source: String,
    val text: String
)

data class KnockPattern(
    val id: String = java.util.UUID.randomUUID().toString(),
    val whenMs: Long, val source: String, val knocks: Int,
    val note: String
)
