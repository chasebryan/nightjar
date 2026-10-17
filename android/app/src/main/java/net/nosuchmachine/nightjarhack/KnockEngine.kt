package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/// The sequence engine — the Kotlin mirror of the iOS
/// KnockEngine. Fed every raw TCP knock (before the display
/// log folds repeats — folding would eat doubled letters),
/// it runs three readers at once: the Knocktalk decoder, the
/// structure grader (scan vs. speech), and the vault
/// combination.
class KnockEngine {
    sealed class Output {
        /** A decoded message. `ackHash` is set for v2-framed
         * messages; null for legacy v1 frames. */
        data class Message(
            val message: KnockMessage, val ackHash: List<Int>?
        ) : Output()
        data class Pattern(val pattern: KnockPattern) : Output()
        data class VaultUnlock(val source: String) : Output()
        /** The peer confirms a message ours named by hash. */
        data class Ack(val source: String, val hash: List<Int>) : Output()
        /** The peer lists fragments of our message it is missing. */
        data class Nack(
            val source: String, val missing: List<Int>
        ) : Output()
        /** Our reassembly of the peer's message has holes —
         * the chat layer should knock a NACK back. */
        data class NackNeeded(
            val source: String, val missing: List<Int>
        ) : Output()
    }

    var onOutput: ((Output) -> Unit)? = null

    /** Suspends vault matching while the vault stands open. */
    @Volatile
    var vaultCoolingUntilMs = 0L

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private data class Session(
        val nibbles: MutableList<Int> = mutableListOf(),
        var lastKnockMs: Long = 0
    )

    private data class Partial(
        val total: Int, var suite: Int = Knocktalk.SUITE_CHACHA,
        val fragments: MutableMap<Int, ByteArray> = mutableMapOf()
    )

    private val sessions = mutableMapOf<String, Session>()
    private val finalizeJobs = mutableMapOf<String, Job>()
    private val alphabetTrail = mutableMapOf<String, List<Long>>()
    private val gradedAt = mutableMapOf<String, Long>()
    private val vaultTrail =
        mutableMapOf<String, List<Pair<String, Long>>>()
    private val partials = mutableMapOf<String, Partial>()
    private val partialJobs = mutableMapOf<String, Job>()
    private val lock = Any()

    /// The vault combination: three protocol digits spoken in
    /// order, from one source, inside twenty seconds. The
    /// DEFAULT is printed in the app and in this source — it
    /// is a placeholder, not a secret. The operator chooses
    /// their own; a combination everyone can read opens for
    /// everyone.
    @Volatile
    var vaultCombination: List<String> =
        listOf("ssh", "tls", "mqtt")

    fun note(source: String, port: Int, proto: String,
             verdict: String, whenMs: Long = System.currentTimeMillis()) {
        if (proto != "TCP") return
        synchronized(lock) {
            noteVault(source, verdict, whenMs)
            if (port == Knocktalk.SYNC_PORT) {
                // A sync delimits frames: flush whatever the
                // previous frame accumulated before opening
                // the next one.
                val old = sessions[source]
                if (old != null && old.nibbles.isNotEmpty()) {
                    finalizeJobs.remove(source)?.cancel()
                    finalize(source)
                }
                sessions[source] = Session(lastKnockMs = whenMs)
                scheduleFinalize(source)
                return
            }
            val nibble = Knocktalk.nibble(port) ?: return
            val session = sessions[source]
            if (session != null) {
                session.nibbles.add(nibble)
                session.lastKnockMs = whenMs
                scheduleFinalize(source)
            } else {
                gradeStructure(source, whenMs)
            }
        }
    }

    private fun scheduleFinalize(source: String) {
        finalizeJobs.remove(source)?.cancel()
        finalizeJobs[source] = scope.launch {
            delay(Knocktalk.GAP_MS)
            synchronized(lock) { finalize(source) }
        }
    }

    private fun finalize(source: String) {
        val session = sessions.remove(source) ?: return
        if (session.nibbles.isEmpty()) return
        finalizeJobs.remove(source)
        val n = session.nibbles.toList()
        // ACK frame: [15 15] + four hash nibbles.
        if (n.size == 6 && n[0] == 15 && n[1] == 15) {
            onOutput?.invoke(Output.Ack(source, n.subList(2, 6)))
            return
        }
        // Suite fragment frame: even length, suite nibble first.
        if (n.size in 6..40 && n.size % 2 == 0 &&
            handleFragment(source, n, suiteLayout = true)) {
            return
        }
        // Legacy fragment frame: odd length, checksum-tailed.
        if (n.size >= 5 && n.size % 2 == 1 &&
            handleFragment(source, n, suiteLayout = false)) {
            return
        }
        // NACK frame: [14 14] + the missing indices.
        if (n.size in 3..10 && n[0] == 14 && n[1] == 14) {
            onOutput?.invoke(
                Output.Nack(source, n.subList(2, n.size)))
            return
        }
        // v1 whole-message frame.
        val key = KnockKeyStore.key
        val text = if (key != null) {
            Knocktalk.decode(n, key)
        } else {
            null
        }
        if (text != null && key != null) {
            onOutput?.invoke(
                Output.Message(
                    KnockMessage(
                        id = java.util.UUID.randomUUID().toString(),
                        whenMs = System.currentTimeMillis(),
                        source = source, text = text),
                    ackHash = null))
        } else {
            onOutput?.invoke(
                Output.Pattern(
                    KnockPattern(
                        whenMs = System.currentTimeMillis(),
                        source = source, knocks = n.size + 1,
                        note = "Knocktalk-framed but sealed — " +
                            "wrong key, no key, or knocks lost " +
                            "in transit")))
        }
    }

    /// Parse one fragment frame. True means the stream was
    /// fragment-shaped and has been consumed; false means
    /// not a fragment.
    private fun handleFragment(
        source: String, n: List<Int>, suiteLayout: Boolean
    ): Boolean {
        val suite = if (suiteLayout) n[0] else Knocktalk.SUITE_CHACHA
        val index = if (suiteLayout) n[1] else n[0]
        val total = if (suiteLayout) n[2] else n[1]
        if (total !in 1..Knocktalk.MAX_FRAGMENTS || index >= total) {
            return false
        }
        val header = if (suiteLayout) 3 else 2
        val payload = n.subList(header, n.size - 1)
        if (payload.size < 2 || payload.size % 2 != 0) return false
        if (n.dropLast(1).sum() % 16 != n.last()) {
            // Fragment-shaped but mangled: register the hole so
            // the NACK asks for this index again.
            registerPartial(source, total, suite, null, null)
            return true
        }
        val bytes = ByteArray(payload.size / 2)
        var i = 0
        while (i < payload.size) {
            bytes[i / 2] =
                ((payload[i] shl 4) or payload[i + 1]).toByte()
            i += 2
        }
        registerPartial(source, total, suite, index, bytes)
        return true
    }

    private fun registerPartial(
        source: String, total: Int, suite: Int,
        index: Int?, data: ByteArray?
    ) {
        var partial = partials[source]
        if (partial == null || partial.total != total) {
            partial = Partial(total)
        }
        // A fresh fragment 0 that disagrees with the stored
        // one is a NEW message superseding the stale partial.
        if (index == 0 && data != null) {
            val existing = partial.fragments[0]
            if (existing != null && !existing.contentEquals(data)) {
                partial = Partial(total)
            }
        }
        if (index == 0 || partial.fragments[0] == null) {
            partial.suite = suite
        }
        if (index != null && data != null) {
            partial.fragments[index] = data
        }
        partials[source] = partial
        if (partial.fragments.size != total) {
            schedulePartialCheck(source)
            return
        }
        partials.remove(source)
        partialJobs.remove(source)?.cancel()
        val sealed = (0 until total)
            .map { partial.fragments.getValue(it) }
            .reduce { acc, bytes -> acc + bytes }
        val finalSuite = partial.suite
        if (finalSuite !in Knocktalk.suiteNames.indices) {
            onOutput?.invoke(
                Output.Pattern(
                    KnockPattern(
                        whenMs = System.currentTimeMillis(),
                        source = source, knocks = total,
                        note = "a complete message in suite " +
                            "$finalSuite, which this build does " +
                            "not speak")))
        } else {
            val key = KnockKeyStore.key
            val text = if (key != null) {
                Knocktalk.open(sealed, key, finalSuite)
            } else {
                null
            }
            if (text != null) {
                onOutput?.invoke(
                    Output.Message(
                        KnockMessage(
                            id = java.util.UUID.randomUUID()
                                .toString(),
                            whenMs = System.currentTimeMillis(),
                            source = source, text = text),
                        ackHash = Knocktalk.hashNibbles(sealed)))
            } else {
                onOutput?.invoke(
                    Output.Pattern(
                        KnockPattern(
                            whenMs = System.currentTimeMillis(),
                            source = source, knocks = total,
                            note = "a complete Knocktalk message " +
                                "that would not open — wrong key")))
            }
        }
    }

    /// When a partial goes quiet with holes in it, ask —
    /// once — for exactly the missing fragments.
    private fun schedulePartialCheck(source: String) {
        partialJobs.remove(source)?.cancel()
        partialJobs[source] = scope.launch {
            delay(Knocktalk.GAP_MS + 2000)
            synchronized(lock) {
                val partial = partials.remove(source)
                    ?: return@synchronized
                val missing = (0 until partial.total).filter {
                    partial.fragments[it] == null
                }
                if (missing.isNotEmpty()) {
                    onOutput?.invoke(
                        Output.NackNeeded(source, missing))
                }
            }
        }
    }

    /// Six alphabet knocks inside ten seconds, unframed: not
    /// a scan's shape. Scanners sweep; speakers spell.
    private fun gradeStructure(source: String, whenMs: Long) {
        var trail = (alphabetTrail[source] ?: emptyList()) + whenMs
        trail = trail.filter { whenMs - it <= 10_000 }
        alphabetTrail[source] = trail
        if (trail.size < 6) return
        val last = gradedAt[source]
        if (last != null && whenMs - last < 30_000) return
        gradedAt[source] = whenMs
        alphabetTrail[source] = emptyList()
        onOutput?.invoke(
            Output.Pattern(
                KnockPattern(
                    whenMs = whenMs, source = source,
                    knocks = trail.size,
                    note = "structured knock pattern — a scan " +
                        "sweeps; this is spelling")))
    }

    private fun noteVault(
        source: String, verdict: String, whenMs: Long
    ) {
        // This device knocking itself never opens the vault.
        if (whenMs <= vaultCoolingUntilMs) return
        if (source.contains("(this device)")) return
        if (source == "127.0.0.1") return
        val category = category(ofVerdict = verdict) ?: return
        var trail = (vaultTrail[source] ?: emptyList()) +
            (category to whenMs)
        trail = trail.filter { whenMs - it.second <= VAULT_WINDOW_MS }
        if (trail.takeLast(3).map { it.first } == vaultCombination) {
            vaultTrail[source] = emptyList()
            vaultCoolingUntilMs = whenMs + 90_000
            onOutput?.invoke(Output.VaultUnlock(source))
        } else {
            vaultTrail[source] = trail
        }
    }

    companion object {
        const val VAULT_WINDOW_MS = 20_000L

        /// Which vault digit a verdict speaks, if any. A digit
        /// counts only when the knock's bytes were RECOGNIZED
        /// as that protocol.
        fun category(ofVerdict: String): String? {
            if (ofVerdict.startsWith("SSH client banner")) {
                return "ssh"
            }
            if (ofVerdict.startsWith("TLS ClientHello")) {
                return "tls"
            }
            if (ofVerdict.startsWith("HTTP request")) {
                return "http"
            }
            if (ofVerdict.startsWith("nightjar-hack probe:")) {
                val rest = ofVerdict.removePrefix(
                    "nightjar-hack probe: ")
                val name = rest.split("(").firstOrNull()
                    ?.trim() ?: ""
                if (name.contains("ssh")) return "ssh"
                if (name.contains("tls")) return "tls"
                if (name == "mqtt-connect") return "mqtt"
                if (name == "http-get" || name == "https-get") {
                    return "http"
                }
                if (name == "smtp-ehlo") return "smtp"
                if (name == "ftp-user") return "ftp"
            }
            return null
        }
    }
}

/// The composer end: knocks sequences at a target, one
/// connect at a time, in order — a connect, a breath, a
/// close, and nothing else. No bytes are ever sent. Frames
/// queue: a message's fragments go out back to back with a
/// short pause between frames, and `onQueueEmpty` reports
/// the drain.
class KnockSender {
    private val _sending =
        kotlinx.coroutines.flow.MutableStateFlow(false)
    val sending: kotlinx.coroutines.flow.StateFlow<Boolean> = _sending
    private val _sent =
        kotlinx.coroutines.flow.MutableStateFlow(0)
    val sent: kotlinx.coroutines.flow.StateFlow<Int> = _sent
    private val _total =
        kotlinx.coroutines.flow.MutableStateFlow(0)
    val total: kotlinx.coroutines.flow.StateFlow<Int> = _total

    var onQueueEmpty: (() -> Unit)? = null

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var job: Job? = null
    @Volatile private var cancelled = false

    val busy: Boolean get() = _sending.value

    /** Knock one raw sequence (v1-style single frame). */
    fun send(host: String, ports: List<Int>) {
        sendFrames(host, listOf(ports))
    }

    fun sendFrames(host: String, frames: List<List<Int>>) {
        val clean = frames.filter { it.isNotEmpty() }
        val target = host.trim()
        if (busy || clean.isEmpty() || target.isEmpty()) return
        cancelled = false
        _total.value = clean.sumOf { it.size }
        _sent.value = 0
        _sending.value = true
        job = scope.launch {
            for ((frameIndex, frame) in clean.withIndex()) {
                for (port in frame) {
                    if (cancelled) break
                    knock(target, port)
                    if (cancelled) break
                    _sent.value += 1
                    delay(300)
                }
                if (cancelled) break
                if (frameIndex + 1 < clean.size) delay(800)
            }
            _sending.value = false
            if (!cancelled) onQueueEmpty?.invoke()
        }
    }

    fun cancel() {
        cancelled = true
        job?.cancel()
        _sending.value = false
    }

    /// One knock: connect; on ready, a breath, then close.
    /// On failure, advance anyway — a closed port still
    /// heard the knock. Nothing is ever written.
    private suspend fun knock(host: String, port: Int) {
        val socket = java.net.Socket()
        try {
            socket.connect(
                java.net.InetSocketAddress(host, port), 1500)
            delay(120)
        } catch (_: Exception) {
            // The knock landed as a refused connection —
            // that is still a knock.
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }
}


