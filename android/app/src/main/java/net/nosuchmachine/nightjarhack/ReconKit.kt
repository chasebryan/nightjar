package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLSocketFactory

/// The recon bench engine: knock, connect, fuzz — the
/// Kotlin mirror of the iOS Recon. A concurrent knock gated
/// by a semaphore; sockets on the IO dispatcher; published
/// state as flows, the way the rest of the Android app works.
class Recon(private val mouth: Mouth?) {

    data class Hit(
        val port: Int,
        val udp: Boolean,
        val state: String,
        val service: String,
        val banner: String,
        val confirmed: Boolean,
        val reply: ByteArray
    ) {
        val label: String get() = "$port/${if (udp) "udp" else "tcp"}"
        val isOpen: Boolean get() = state == "open"
    }

    private val _hits = MutableStateFlow<List<Hit>>(emptyList())
    val hits: StateFlow<List<Hit>> = _hits
    private val _knocking = MutableStateFlow(false)
    val knocking: StateFlow<Boolean> = _knocking
    private val _probed = MutableStateFlow(0)
    val probed: StateFlow<Int> = _probed
    private val _total = MutableStateFlow(0)
    val total: StateFlow<Int> = _total

    private val _console = MutableStateFlow<List<String>>(emptyList())
    val consoleLines: StateFlow<List<String>> = _console
    private val _connected = MutableStateFlow(false)
    val connected: StateFlow<Boolean> = _connected
    var connectTarget: String = ""

    private val _fuzzing = MutableStateFlow(false)
    val fuzzing: StateFlow<Boolean> = _fuzzing
    private val _fuzzLines = MutableStateFlow<List<String>>(emptyList())
    val fuzzLines: StateFlow<List<String>> = _fuzzLines
    private val _fuzzDead = MutableStateFlow(0)
    val fuzzDead: StateFlow<Int> = _fuzzDead

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var generation = 0
    @Volatile private var fuzzToken = 0
    private var knockJob: Job? = null
    private var consoleSocket: Socket? = null
    private var consoleUdp: DatagramSocket? = null
    private var consoleJob: Job? = null

    companion object {
        /// UDP readiness is not proof a remote port is open.
        /// Without a response, the strongest supported result
        /// is open|filtered.
        fun probeState(state: String, udp: Boolean, replyBytes: Int): String =
            if (udp && state == "open" && replyBytes == 0) {
                "open|filtered"
            } else {
                state
            }
    }

    // MARK: - knock

    fun knock(
        host: String, ports: List<Int>, udp: Boolean,
        timeoutMs: Int = 1500, jobs: Int = 24, speak: Boolean = true,
        append: Boolean = false
    ) {
        val target = host.trim()
        if (target.isEmpty() || ports.isEmpty() || _knocking.value) return
        _knocking.value = true
        if (!append) _hits.value = emptyList()
        _probed.value = 0
        _total.value = ports.size
        generation += 1
        val gen = generation
        knockJob = scope.launch {
            val semaphore = Semaphore(maxOf(1, minOf(jobs, 64)))
            val found = ports.map { port ->
                async {
                    semaphore.withPermit {
                        val hit = probe(target, port, udp, timeoutMs, speak)
                        _probed.value += 1
                        hit
                    }
                }
            }.awaitAll().filterNotNull()
            if (generation != gen) return@launch
            val merged = (_hits.value + found).sortedWith(
                compareBy({ it.port }, { if (it.udp) 1 else 0 })
            )
            _hits.value = merged
            _knocking.value = false
            if (!append) {
                val open = merged.filter { it.isOpen }
                appendConsole(
                    "knock $target: ${open.size} open of ${ports.size}"
                )
                Journal.log(
                    "recon", "knock",
                    "$target — ${open.size} open of ${ports.size}: " +
                        open.joinToString(", ") {
                            "${it.label} ${it.service}"
                        }
                )
                mouth?.toast("Knock: ${open.size} open of ${ports.size}")
            }
        }
    }

    fun cancelKnock() {
        generation += 1
        knockJob?.cancel()
        _knocking.value = false
    }

    private fun probe(
        host: String, port: Int, udp: Boolean,
        timeoutMs: Int, speak: Boolean
    ): Hit? {
        if (port !in 1..65535) return null
        val spec = if (speak) ReconPayloads.probe(port, udp) else null
        val reply = ByteArrayOutputStream()
        var state = "closed"
        try {
            if (udp) {
                DatagramSocket().use { socket ->
                    socket.soTimeout = timeoutMs
                    socket.connect(InetSocketAddress(host, port))
                    val payload = spec?.build?.invoke()
                    if (payload != null && payload.isNotEmpty()) {
                        socket.send(
                            DatagramPacket(
                                payload, payload.size,
                                InetSocketAddress(host, port)
                            )
                        )
                    }
                    val buffer = ByteArray(8192)
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        reply.write(packet.data, 0, packet.length)
                    } catch (_: Exception) {
                        // Silence on UDP is open|filtered,
                        // decided below.
                    }
                    state = "open"
                }
            } else {
                val plain = Socket()
                plain.connect(InetSocketAddress(host, port), timeoutMs)
                val socket = if (spec?.tls == true) {
                    val factory = SSLSocketFactory.getDefault()
                        as SSLSocketFactory
                    val tls = factory.createSocket(
                        plain, host, port, true
                    ) as javax.net.ssl.SSLSocket
                    tls.soTimeout = timeoutMs
                    tls.startHandshake()
                    tls
                } else {
                    plain.soTimeout = timeoutMs
                    plain
                }
                socket.use { open ->
                    state = "open"
                    val payload = spec?.build?.invoke()
                    if (payload != null && payload.isNotEmpty()) {
                        open.getOutputStream().write(payload)
                        open.getOutputStream().flush()
                    }
                    val buffer = ByteArray(8192)
                    val deadline = System.currentTimeMillis() + timeoutMs
                    try {
                        while (System.currentTimeMillis() < deadline) {
                            val read = open.getInputStream().read(buffer)
                            if (read < 0) break
                            reply.write(buffer, 0, read)
                            if (reply.size() > 65536) break
                        }
                    } catch (_: Exception) {
                        // A read timeout after connecting still
                        // means the port is open.
                    }
                }
            }
        } catch (_: Exception) {
            if (!udp) state = "closed" else state = "open"
        }
        val replyBytes = reply.toByteArray()
        val hint = spec?.hint
        val confirmed = when {
            spec == null -> false
            hint == null || hint.isEmpty() -> replyBytes.isNotEmpty()
            else -> containsBytes(replyBytes, hint)
        }
        val observed = probeState(state, udp, replyBytes.size)
        return Hit(
            port = port, udp = udp, state = observed,
            service = spec?.family ?: "?", banner = ReconPayloads
                .firstLine(replyBytes),
            confirmed = confirmed, reply = replyBytes
        )
    }

    private fun containsBytes(haystack: ByteArray, needle: ByteArray): Boolean {
        if (needle.isEmpty() || needle.size > haystack.size) return false
        for (start in 0..haystack.size - needle.size) {
            var match = true
            for (offset in needle.indices) {
                if (haystack[start + offset] != needle[offset]) {
                    match = false
                    break
                }
            }
            if (match) return true
        }
        return false
    }

    // MARK: - connect (a console, not a terminal)

    fun open(rawTarget: String) {
        val text = rawTarget.trim()
        if (text.isEmpty()) return
        val target = try {
            SendTarget.parse(text)
        } catch (_: Exception) {
            appendConsole("nightjar: cannot parse $text")
            return
        }
        close()
        when (target) {
            is SendTarget.Tcp -> connectTcp(target.host, target.port,
                target.tls, target.raw)
            is SendTarget.Udp -> connectUdp(target.host, target.port,
                target.raw)
            is SendTarget.Http -> connectTcp(
                target.url.host ?: "", target.url.port.takeIf { it > 0 }
                    ?: if (target.https) 443 else 80,
                target.https, target.raw
            )
            else -> appendConsole(
                "nightjar: ${target.raw} is not a network target"
            )
        }
    }

    private fun connectTcp(host: String, port: Int, tls: Boolean, label: String) {
        appendConsole("— connecting to $label —")
        consoleJob = scope.launch {
            try {
                val plain = Socket()
                plain.connect(InetSocketAddress(host, port), 5000)
                val socket = if (tls) {
                    val factory = SSLSocketFactory.getDefault()
                        as SSLSocketFactory
                    val wrapped = factory.createSocket(
                        plain, host, port, true
                    ) as javax.net.ssl.SSLSocket
                    wrapped.startHandshake()
                    wrapped
                } else {
                    plain
                }
                consoleSocket = socket
                _connected.value = true
                appendConsole("— connected —")
                val buffer = ByteArray(8192)
                try {
                    while (true) {
                        val read = socket.getInputStream().read(buffer)
                        if (read < 0) break
                        appendBytes(buffer.copyOf(read))
                    }
                } catch (_: Exception) {
                }
                appendConsole("— remote closed —")
                _connected.value = false
            } catch (error: Exception) {
                _connected.value = false
                appendConsole("nightjar: ${error.message ?: "failed"}")
            }
        }
    }

    private fun connectUdp(host: String, port: Int, label: String) {
        appendConsole("— connecting to $label —")
        consoleJob = scope.launch {
            try {
                val socket = DatagramSocket()
                socket.connect(InetSocketAddress(host, port))
                consoleUdp = socket
                _connected.value = true
                appendConsole("— connected —")
                val buffer = ByteArray(8192)
                try {
                    while (true) {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket.receive(packet)
                        appendBytes(packet.data.copyOf(packet.length))
                    }
                } catch (_: Exception) {
                }
                appendConsole("— remote closed —")
                _connected.value = false
            } catch (error: Exception) {
                _connected.value = false
                appendConsole("nightjar: ${error.message ?: "failed"}")
            }
        }
    }

    fun sendLine(text: String, crlf: Boolean = true) {
        val payload = (if (crlf) "$text\r\n" else text)
            .toByteArray(Charsets.UTF_8)
        appendConsole("» $text")
        writeConsole(payload)
    }

    fun sendBytes(data: ByteArray, label: String) {
        appendConsole("» $label (${data.size} bytes)")
        writeConsole(data)
    }

    private fun writeConsole(data: ByteArray) {
        scope.launch {
            try {
                consoleSocket?.getOutputStream()?.let { out ->
                    out.write(data)
                    out.flush()
                    return@launch
                }
                consoleUdp?.let { socket ->
                    socket.send(DatagramPacket(data, data.size))
                }
            } catch (_: Exception) {
            }
        }
    }

    fun close() {
        consoleJob?.cancel()
        try {
            consoleSocket?.close()
        } catch (_: Exception) {
        }
        consoleSocket = null
        try {
            consoleUdp?.close()
        } catch (_: Exception) {
        }
        consoleUdp = null
        _connected.value = false
    }

    private fun appendBytes(data: ByteArray) {
        val text = String(data, Charsets.UTF_8)
        val hasControl = text.any {
            it.code < 0x20 && it != '\n' && it != '\r' && it != '\t' ||
                it.code in 0x7F..0x9F
        }
        if (hasControl) {
            for (line in PayloadKit.hexdump(data).split("\n")) {
                appendConsole(line)
            }
        } else {
            for (line in text.split("\n")) {
                val trimmed = line.trim()
                if (trimmed.isNotEmpty()) appendConsole("  $trimmed")
            }
        }
    }

    private fun appendConsole(line: String) {
        _console.value = (_console.value + line).takeLast(400)
    }

    fun clearConsole() {
        _console.value = emptyList()
    }

    // MARK: - fuzz

    fun startFuzz(
        rawTarget: String, seed: ByteArray?, count: Int,
        length: Int, mutations: Int, seedValue: ULong?,
        read: Boolean, timeoutMs: Int
    ) {
        if (_fuzzing.value || count <= 0) return
        val target = try {
            SendTarget.parse(rawTarget.trim())
        } catch (_: Exception) {
            _fuzzLines.value = listOf("nightjar: cannot parse $rawTarget")
            return
        }
        _fuzzing.value = true
        _fuzzDead.value = 0
        _fuzzLines.value = listOf("fuzz ${target.raw} — $count mutation(s)")
        fuzzToken += 1
        val token = fuzzToken
        scope.launch {
            var rng = SplitMix64(seedValue ?: 0x9E3779B97F4A7C15uL)
            var base = seed ?: ByteArray(0)
            if (base.isEmpty()) {
                base = ByteArray(maxOf(1, length)) {
                    (rng.next() and 0xFFuL).toByte()
                }
            }
            var index = 1
            while (index <= count && token == fuzzToken) {
                val blob = base.toMutableList()
                repeat(maxOf(1, mutations)) { rng = mutate(blob, rng) }
                val payload = ByteArray(blob.size) { blob[it] }
                val (reply, failed) = exchange(target, payload, read,
                    timeoutMs)
                if (token != fuzzToken) break
                if (failed) _fuzzDead.value += 1
                val head = if (failed) {
                    "DEAD"
                } else {
                    ReconPayloads.firstLine(reply, 60)
                }
                val line = "  %5d  len=%d  reply=%d  %s".format(
                    index, payload.size, reply.size, head
                )
                _fuzzLines.value = (_fuzzLines.value + line).takeLast(400)
                index += 1
            }
            if (token == fuzzToken) {
                _fuzzing.value = false
                _fuzzLines.value = _fuzzLines.value +
                    "done — ${_fuzzDead.value} dead connection(s)"
            }
        }
    }

    fun stopFuzz() {
        fuzzToken += 1
        _fuzzing.value = false
    }

    private fun mutate(
        data: MutableList<Byte>, rngIn: SplitMix64
    ): SplitMix64 {
        var rng = rngIn
        if (data.isEmpty()) {
            data.add((rng.next() and 0xFFuL).toByte())
            return rng
        }
        when ((rng.next() % 7uL).toInt()) {
            0 -> {
                val i = (rng.next() % data.size.toULong()).toInt()
                val bit = (rng.next() % 8uL).toInt()
                data[i] = (data[i].toInt() xor (1 shl bit)).toByte()
            }
            1 -> {
                val i = (rng.next() % data.size.toULong()).toInt()
                data[i] = (rng.next() and 0xFFuL).toByte()
            }
            2 -> {
                val at = (rng.next() % (data.size + 1).toULong()).toInt()
                data.add(at, (rng.next() and 0xFFuL).toByte())
            }
            3 -> {
                if (data.size > 1) {
                    data.removeAt(
                        (rng.next() % data.size.toULong()).toInt()
                    )
                } else {
                    truncate(data, rng)
                }
            }
            4 -> {
                val start = (rng.next() % data.size.toULong()).toInt()
                val end = minOf(
                    data.size, start + 1 + (rng.next() % 16uL).toInt()
                )
                val slice = data.subList(start, end).toList()
                data.addAll(start, slice)
            }
            5 -> {
                val start = (rng.next() % data.size.toULong()).toInt()
                val end = minOf(
                    data.size, start + 1 + (rng.next() % 8uL).toInt()
                )
                for (i in start until end) {
                    data[i] = (rng.next() and 0xFFuL).toByte()
                }
            }
            else -> truncate(data, rng)
        }
        return rng
    }

    private fun truncate(data: MutableList<Byte>, rng: SplitMix64) {
        if (data.isEmpty()) return
        val at = (rng.next() % data.size.toULong()).toInt()
        while (data.size > at) data.removeAt(data.size - 1)
    }

    /// One fuzz exchange. A deadline is not a success unless
    /// the payload was actually sent; a completed send without
    /// a reply is not by itself a dead connection.
    private fun exchange(
        target: SendTarget, payload: ByteArray,
        read: Boolean, timeoutMs: Int
    ): Pair<ByteArray, Boolean> {
        val host: String
        val port: Int
        val tls: Boolean
        val udp: Boolean
        when (target) {
            is SendTarget.Tcp -> {
                host = target.host; port = target.port
                tls = target.tls; udp = false
            }
            is SendTarget.Udp -> {
                host = target.host; port = target.port
                tls = false; udp = true
            }
            is SendTarget.Http -> {
                host = target.url.host ?: ""
                port = target.url.port.takeIf { it > 0 }
                    ?: if (target.https) 443 else 80
                tls = target.https; udp = false
            }
            else -> return ByteArray(0) to true
        }
        var didSend = false
        val reply = ByteArrayOutputStream()
        try {
            if (udp) {
                DatagramSocket().use { socket ->
                    socket.soTimeout = timeoutMs + 1000
                    socket.connect(InetSocketAddress(host, port))
                    socket.send(
                        DatagramPacket(
                            payload, payload.size,
                            InetSocketAddress(host, port)
                        )
                    )
                    didSend = true
                    if (read) {
                        val buffer = ByteArray(8192)
                        val packet = DatagramPacket(buffer, buffer.size)
                        try {
                            socket.receive(packet)
                            reply.write(packet.data, 0, packet.length)
                        } catch (_: Exception) {
                        }
                    }
                }
                return reply.toByteArray() to false
            }
            val plain = Socket()
            plain.connect(InetSocketAddress(host, port), timeoutMs + 1000)
            val socket = if (tls) {
                val factory = SSLSocketFactory.getDefault()
                    as SSLSocketFactory
                val wrapped = factory.createSocket(
                    plain, host, port, true
                ) as javax.net.ssl.SSLSocket
                wrapped.soTimeout = timeoutMs + 1000
                wrapped.startHandshake()
                wrapped
            } else {
                plain.soTimeout = timeoutMs + 1000
                plain
            }
            socket.use { open ->
                open.getOutputStream().write(payload)
                open.getOutputStream().flush()
                didSend = true
                if (read) {
                    val buffer = ByteArray(8192)
                    try {
                        while (true) {
                            val count = open.getInputStream().read(buffer)
                            if (count < 0) break
                            reply.write(buffer, 0, count)
                            if (reply.size() > 65536) break
                        }
                    } catch (_: Exception) {
                        // Read deadline after a completed send is
                        // not a dead connection (didSend rules).
                    }
                }
            }
            return reply.toByteArray() to false
        } catch (_: Exception) {
            return reply.toByteArray() to !didSend
        }
    }

    // MARK: - library handoff

    fun payload(forPreset: String): ByteArray? =
        try {
            ReconPayloads.build(forPreset)
        } catch (_: Exception) {
            null
        }
}

/// A tiny deterministic RNG, so a fuzz run reproduces from
/// a seed — the same SplitMix64 the iOS bench uses.
class SplitMix64(seed: ULong) {
    private var state: ULong = seed

    fun next(): ULong {
        state += 0x9E3779B97F4A7C15uL
        var z = state
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        return z xor (z shr 31)
    }
}
