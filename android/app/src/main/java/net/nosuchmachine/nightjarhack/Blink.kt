package net.nosuchmachine.nightjarhack

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Base64
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/// Blink — the Kotlin mirror of the iOS Blink: messages
/// carried by light.
///
/// The fifth transport. Chirp needs a room where sound is
/// allowed; Blink needs only line of sight: the payload —
/// the same Knocktalk sealed box as ever — is cut into
/// fragments and shown as a looping sequence of QR frames,
/// and the other phone's camera gathers them until the set
/// is whole. Fragment, index, total: the same discipline
/// as the knock fragments, at the speed of sight.
///
/// The loop is the error correction. A frame the camera
/// missed comes around again in a second; there is nothing
/// to acknowledge and no way to acknowledge it — light,
/// like sound, is a one-way confession.
object BlinkFraming {
    const val CHUNK_BYTES = 110

    fun frames(payload: ByteArray, suite: Int): List<String> {
        val chunks = mutableListOf<ByteArray>()
        var start = 0
        if (payload.isEmpty()) chunks.add(ByteArray(0))
        while (start < payload.size) {
            val end = minOf(start + CHUNK_BYTES, payload.size)
            chunks.add(payload.copyOfRange(start, end))
            start = end
        }
        val total = chunks.size
        return chunks.mapIndexed { index, chunk ->
            // Base64url-ish: the standard alphabet's '/'
            // would collide with the field separator.
            val body = Base64.encodeToString(chunk, Base64.NO_WRAP)
                .replace("/", "_")
                .replace("+", "-")
            "NJ1/$suite/$index/$total/$body"
        }
    }

    /** A QR bitmap for one frame, correction level M,
     * scaled up with a quiet zone and no smoothing —
     * cameras read blocky codes best. */
    fun qrBitmap(text: String, sizePx: Int = 720): Bitmap? {
        return try {
            val hints = mapOf(
                EncodeHintType.ERROR_CORRECTION to
                    ErrorCorrectionLevel.M,
                EncodeHintType.MARGIN to 2)
            val matrix = QRCodeWriter().encode(
                text, BarcodeFormat.QR_CODE, sizePx, sizePx, hints)
            val bitmap = Bitmap.createBitmap(
                matrix.width, matrix.height,
                Bitmap.Config.RGB_565)
            for (x in 0 until matrix.width) {
                for (y in 0 until matrix.height) {
                    bitmap.setPixel(
                        x, y,
                        if (matrix[x, y]) Color.BLACK else Color.WHITE)
                }
            }
            bitmap
        } catch (_: Exception) {
            null
        }
    }
}

/// Gathers blink frames until the set is whole.
class BlinkCollector {
    var suite: Int? = null
        private set
    var total: Int? = null
        private set
    private val chunks = mutableMapOf<Int, ByteArray>()

    val received: Int get() = chunks.size

    fun reset() {
        suite = null
        total = null
        chunks.clear()
    }

    /** Feed one decoded QR string. Returns the reassembled
     * payload the moment the final missing frame lands. */
    fun feed(text: String): ByteArray? {
        val parts = text.split("/")
        if (parts.size != 5 || parts[0] != "NJ1") return null
        val frameSuite = parts[1].toIntOrNull() ?: return null
        val index = parts[2].toIntOrNull() ?: return null
        val count = parts[3].toIntOrNull() ?: return null
        val body = parts[4].replace("_", "/").replace("-", "+")
        val data = try {
            Base64.decode(body, Base64.DEFAULT)
        } catch (_: Exception) {
            return null
        }
        if (total != null && total != count) reset()
        total = count
        suite = frameSuite
        chunks[index] = data
        if (chunks.size != count) return null
        var out = ByteArray(0)
        for (i in 0 until count) {
            val chunk = chunks[i] ?: return null
            out += chunk
        }
        return out
    }
}

/// The camera side's brain: the tab's CameraX analyzer
/// feeds decoded strings here; the counts and the verdict
/// live as flows the screen collects.
class BlinkReceiver {
    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running
    private val _status = MutableStateFlow("idle")
    val status: StateFlow<String> = _status
    private val _got = MutableStateFlow(0)
    val got: StateFlow<Int> = _got
    private val _want = MutableStateFlow(0)
    val want: StateFlow<Int> = _want

    /** (payload, suite) — return true when it opened. */
    var onPayload: ((ByteArray, Int) -> Boolean)? = null

    private val collector = BlinkCollector()
    private var finished = false

    fun start() {
        collector.reset()
        finished = false
        _got.value = 0
        _want.value = 0
        _running.value = true
        _status.value = "watching — hold the phones face to face"
    }

    fun stop() {
        if (!_running.value) return
        _running.value = false
        _status.value = "idle"
    }

    /** One decoded QR string from the analyzer. */
    fun onQr(text: String) {
        if (!_running.value || finished) return
        val payload = collector.feed(text)
        if (payload != null) {
            finished = true
            val opened = onPayload?.invoke(
                payload, collector.suite ?: 0) ?: false
            val message = if (opened) {
                "decoded — filed in the Blink thread"
            } else {
                "saw a whole blink that does not open with " +
                    "your pairing key"
            }
            stop()
            _status.value = message
            return
        }
        _got.value = collector.received
        _want.value = collector.total ?: 0
    }
}
