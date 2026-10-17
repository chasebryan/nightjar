package net.nosuchmachine.nightjarhack

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.Executors

/// The night log: one timeline for the whole instrument —
/// the Kotlin mirror of the iOS Journal. Modules append one
/// line per event worth remembering (a Serve arrival, a
/// listening session's bounds, later a tripwire knock or a
/// posture change) and the Sessions tab reads them back as a
/// single chronological record. The file is JSONL with the
/// same fields as the iOS ledger, and the seal is the same
/// chain: every line carries `p`, the previous sealed line's
/// hash, and `h`, its own SHA-256 over the line carrying
/// `p` but not `h`. Alter, reorder, or remove a sealed line
/// and verification breaks at exactly that line. (Cutting
/// lines off the END leaves nothing pointing forward to
/// miss them — no chain can prove a negative about its own
/// tail, and this one doesn't claim to.)
data class NightEvent(
    val id: String,
    val `when`: String,
    val module: String,
    val kind: String,
    val text: String,
    val p: String? = null,
    val h: String? = null
)

object Journal {
    private val executor = Executors.newSingleThreadExecutor()

    @Volatile
    private var file: File? = null

    @Volatile
    private var lastHash: String? = null

    @Volatile
    private var chainLoaded = false

    /// A feed of everything written, for the one listener
    /// whose job is the whole picture — on iOS, the steward.
    /// Called on the journal's own thread.
    @Volatile
    var onEvent: ((NightEvent) -> Unit)? = null

    fun init(context: Context) {
        file = File(context.filesDir, "nightjar-nightlog.jsonl")
    }

    fun log(module: String, kind: String, text: String) {
        val target = file ?: return
        executor.execute {
            if (!chainLoaded) loadChainTail(target)
            val base = NightEvent(
                id = UUID.randomUUID().toString(),
                `when` = DateTimeFormatter.ISO_INSTANT.format(Instant.now()),
                module = module, kind = kind, text = text,
                p = lastHash
            )
            val sealed = base.copy(
                h = sha256Hex(encode(base).toByteArray(Charsets.UTF_8))
            )
            lastHash = sealed.h
            try {
                target.appendText(encode(sealed) + "\n", Charsets.UTF_8)
            } catch (_: Exception) {
            }
            onEvent?.invoke(sealed)
        }
    }

    data class ChainReport(
        val sealed: Int,
        val legacy: Int,
        val brokenLine: Int?
    )

    fun verifyChain(): ChainReport {
        val target = file ?: return ChainReport(0, 0, null)
        val text = try {
            target.readText(Charsets.UTF_8)
        } catch (_: Exception) {
            return ChainReport(0, 0, null)
        }
        var prev: String? = null
        var sealed = 0
        var legacy = 0
        var lineNo = 0
        for (raw in text.split("\n")) {
            lineNo += 1
            if (raw.isEmpty()) continue
            val event = parse(raw)
                ?: return ChainReport(sealed, legacy, lineNo)
            val h = event.h
            if (h == null) {
                legacy += 1
                continue
            }
            val body = encode(event.copy(h = null))
            if (sha256Hex(body.toByteArray(Charsets.UTF_8)) != h ||
                event.p != prev
            ) {
                return ChainReport(sealed, legacy, lineNo)
            }
            sealed += 1
            prev = h
        }
        return ChainReport(sealed, legacy, null)
    }

    /// Newest first, capped — the view's working set.
    fun events(limit: Int = 300): List<NightEvent> {
        val target = file ?: return emptyList()
        val text = try {
            target.readText(Charsets.UTF_8)
        } catch (_: Exception) {
            return emptyList()
        }
        val parsed = mutableListOf<NightEvent>()
        for (line in text.split("\n")) {
            if (line.isEmpty()) continue
            parse(line)?.let { parsed.add(it) }
        }
        return parsed.takeLast(limit).reversed()
    }

    // MARK: - the chain's mechanics

    private fun loadChainTail(target: File) {
        chainLoaded = true
        val text = try {
            target.readText(Charsets.UTF_8)
        } catch (_: Exception) {
            return
        }
        for (line in text.split("\n").reversed()) {
            if (line.isEmpty()) continue
            val event = parse(line) ?: continue
            if (event.h != null) {
                lastHash = event.h
                return
            }
        }
    }

    private fun parse(line: String): NightEvent? {
        return try {
            val obj = JSONObject(line)
            NightEvent(
                id = obj.getString("id"),
                `when` = obj.getString("when"),
                module = obj.getString("module"),
                kind = obj.getString("kind"),
                text = obj.getString("text"),
                p = if (obj.has("p") && !obj.isNull("p")) {
                    obj.getString("p")
                } else {
                    null
                },
                h = if (obj.has("h") && !obj.isNull("h")) {
                    obj.getString("h")
                } else {
                    null
                }
            )
        } catch (_: Exception) {
            null
        }
    }

    /// Canonical encoding: keys sorted, absent fields
    /// omitted — the same shape the iOS encoder writes, so
    /// a line means the same thing on either platform.
    private fun encode(event: NightEvent): String {
        val sb = StringBuilder("{")
        var first = true
        fun field(name: String, value: String?) {
            if (value == null) return
            if (!first) sb.append(',')
            first = false
            sb.append('"').append(name).append("\":\"")
            sb.append(escape(value)).append('"')
        }
        field("h", event.h)
        field("id", event.id)
        field("kind", event.kind)
        field("module", event.module)
        field("p", event.p)
        field("text", event.text)
        field("when", event.`when`)
        return sb.append('}').toString()
    }

    private fun escape(value: String): String {
        val sb = StringBuilder()
        for (ch in value) {
            when (ch) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '/' -> sb.append("\\/")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                '\b' -> sb.append("\\b")
                '' -> sb.append("\\f")
                else -> {
                    if (ch.code < 0x20) {
                        sb.append(String.format("\\u%04x", ch.code))
                    } else {
                        sb.append(ch)
                    }
                }
            }
        }
        return sb.toString()
    }

    private fun sha256Hex(data: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(data)
        return digest.joinToString("") { "%02x".format(it) }
    }
}
