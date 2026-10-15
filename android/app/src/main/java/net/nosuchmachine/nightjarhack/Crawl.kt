package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/// Route expansion — the same grammar as the iOS crawl:
/// ordinary targets, last-octet ranges (10.0.0.10-25),
/// host:80,443 port trains, bare hosts as trains across the
/// usual scan ports, phone:NAME and http(s) lines untouched.
object Crawl {

    fun expandRange(line: String): List<String>? {
        val text = line.trim()
        val dash = text.lastIndexOf('-')
        if (dash < 0) return null
        val tail = text.substring(dash + 1)
        val endOctet = tail.toIntOrNull() ?: return null
        val head = text.substring(0, dash)
        val lastDot = head.lastIndexOf('.')
        if (lastDot < 0) return null
        val startOctet = head.substring(lastDot + 1).toIntOrNull() ?: return null
        val base = head.substring(0, lastDot + 1)
        val prefixOctets = base.split('.').filter { it.isNotEmpty() }
        if (prefixOctets.size != 3) return null
        if (prefixOctets.any { (it.toIntOrNull() ?: -1) !in 0..255 }) return null
        if (startOctet !in 0..255 || endOctet !in 0..255 || endOctet < startOctet) {
            return null
        }
        if (endOctet - startOctet > 512) return null
        return (startOctet..endOctet).map { "$base$it" }
    }

    fun looksLikeRange(line: String): Boolean {
        val text = line.trim()
        if (!text.contains('-')) return false
        return text.matches(Regex("""[\d.]+-\d+.*"""))
    }

    /// (stops, invalid) — stops are NOT deduplicated: a walk
    /// may visit the same door twice on purpose.
    fun expandRoute(lines: List<String>): Pair<List<String>, List<String>> {
        val stops = mutableListOf<String>()
        val invalid = mutableListOf<String>()
        for (entry in lines) {
            val text = entry.trim()
            if (text.isEmpty() || text.startsWith("#")) continue
            val range = expandRange(text)
            if (range != null) {
                stops += range
                continue
            }
            if (looksLikeRange(text)) {
                invalid.add(text)
                continue
            }
            if (text.startsWith("phone:") || text.startsWith("http://") ||
                text.startsWith("https://")
            ) {
                stops.add(text)
                continue
            }
            var scheme = "tcp"
            var rest = text
            val split = text.indexOf("://")
            if (split >= 0) {
                scheme = text.substring(0, split)
                rest = text.substring(split + 3)
            }
            val colon = rest.lastIndexOf(':')
            if (colon < 0) {
                // Bare host: a train across the usual ports.
                for ((port, _) in ScanKit.topPorts) {
                    stops.add("$scheme://$rest:$port")
                }
                continue
            }
            val host = rest.substring(0, colon)
            val portsField = rest.substring(colon + 1)
            if (portsField.contains(',')) {
                for (piece in portsField.split(',')) {
                    val port = piece.trim().toIntOrNull()
                    if (port != null) stops.add("$scheme://$host:$port")
                }
            } else {
                stops.add(text)
            }
        }
        return stops to invalid
    }

    /// The full journey: route expansion, the return leg
    /// mirrored, and (in per-device mode) block boundaries the
    /// engine resets the chain at. Represented as hop texts +
    /// the set of indices that start a fresh block.
    fun expandJourney(
        route: List<String>, perDevice: Boolean, returnLeg: Boolean
    ): Pair<List<String>, Set<Int>> {
        val (stops, _) = expandRoute(route)
        if (!perDevice) {
            val out = stops.toMutableList()
            val fresh = mutableSetOf(0)
            if (returnLeg) {
                out += stops.reversed()
            }
            return out to fresh
        }
        // Per-device: each route LINE is one device; its own
        // expansion is its walk; blocks run back to back.
        val journey = mutableListOf<String>()
        val fresh = mutableSetOf<Int>()
        for (line in route) {
            val (deviceStops, _) = expandRoute(listOf(line))
            if (deviceStops.isEmpty()) continue
            fresh.add(journey.size)
            journey += deviceStops
            if (returnLeg) journey += deviceStops.reversed()
        }
        return journey to fresh
    }
}

/// The crawl engine: the centipede walk and Crosstalk, on the
/// mouth's reply channel. A port of Crawl.swift; the state is
/// published as flows for the Compose UI.
class CrawlEngine(private val mouth: Mouth, private val serve: Serve) {

    private val _crawlBusy = MutableStateFlow(false)
    val crawlBusy: StateFlow<Boolean> = _crawlBusy
    private val _crawlLines = MutableStateFlow<List<String>>(emptyList())
    val crawlLines: StateFlow<List<String>> = _crawlLines
    private val _crawlHomecoming = MutableStateFlow<ByteArray?>(null)
    val crawlHomecoming: StateFlow<ByteArray?> = _crawlHomecoming
    private val _crawlFindings = MutableStateFlow<List<String>>(emptyList())
    val crawlFindings: StateFlow<List<String>> = _crawlFindings

    private val _talkBusy = MutableStateFlow(false)
    val talkBusy: StateFlow<Boolean> = _talkBusy
    private val _talkLines = MutableStateFlow<List<String>>(emptyList())
    val talkLines: StateFlow<List<String>> = _talkLines
    private val _talkHomecoming = MutableStateFlow<ByteArray?>(null)
    val talkHomecoming: StateFlow<ByteArray?> = _talkHomecoming

    private val _sweepStatus = MutableStateFlow("")
    val sweepStatus: StateFlow<String> = _sweepStatus

    @Volatile
    private var crawlGeneration = 0
    @Volatile
    private var talkGeneration = 0
    private var crawlJob: Job? = null
    private var talkJob: Job? = null

    private fun trail(line: String) {
        _crawlLines.value = (_crawlLines.value + line).takeLast(500)
    }

    // MARK: One hop

    private suspend fun hopSend(
        text: String, payload: ByteArray, framing: String, method: String
    ): Boolean = suspendCancellableCoroutine { cont ->
        if (text.startsWith("phone:")) {
            val name = text.removePrefix("phone:")
            val phone = serve.resolvePhone(name)
            if (phone == null) {
                cont.resume(false)
                return@suspendCancellableCoroutine
            }
            mouth.sendNetwork(
                SendTarget.Tcp(phone.host, phone.port, false),
                payload, framing, read = true
            ) { ok -> cont.resume(ok) }
            return@suspendCancellableCoroutine
        }
        val parsed = try {
            SendTarget.parse(text)
        } catch (_: Exception) {
            cont.resume(false)
            return@suspendCancellableCoroutine
        }
        when (parsed) {
            is SendTarget.Http -> mouth.sendHTTP(parsed, payload, framing, method) { ok ->
                cont.resume(ok)
            }
            is SendTarget.Tcp, is SendTarget.Udp ->
                mouth.sendNetwork(parsed, payload, framing, read = true) { ok ->
                    cont.resume(ok)
                }
            else -> cont.resume(false)
        }
    }

    // MARK: Centipede

    fun crawl(
        route: List<String>, mode: String, returnLeg: Boolean,
        perDevice: Boolean, homeTarget: String, smartSeed: Boolean,
        probeFor: (String) -> Pair<ByteArray, String>?,
        payloadFor: (String) -> ByteArray?,
        framing: String, method: String
    ) {
        if (_crawlBusy.value || _talkBusy.value) return
        val (journeyAll, freshStarts) = Crawl.expandJourney(route, perDevice, returnLeg)
        if (journeyAll.isEmpty()) {
            _crawlLines.value = listOf("✗ The route expands to nothing")
            return
        }
        val journey = journeyAll.take(300)
        crawlGeneration += 1
        val gen = crawlGeneration
        _crawlBusy.value = true
        _crawlHomecoming.value = null
        _crawlFindings.value = emptyList()
        _crawlLines.value = listOf(
            "Centipede released — ${journey.size} hop(s)" +
                (if (returnLeg) ", out and back" else "")
        )
        mouth.line("centipede: released, ${journey.size} hop(s)")
        crawlJob = mouth.scope.launch {
            var carried: ByteArray? = null
            val findings = mutableListOf<String>()
            val outCount = if (perDevice) journey.size else Crawl.expandRoute(route).first.size
            var index = 0
            while (index < journey.size) {
                if (crawlGeneration != gen) break
                val text = journey[index]
                val hopNumber = index + 1
                val leg = if (perDevice || !returnLeg || index < outCount) "out" else "back"
                val fresh = index in freshStarts || mode == "seed" ||
                    (index == 0)
                var payload: ByteArray? = null
                var probeName: String? = null
                if (!fresh && carried != null) {
                    payload = carried
                } else if (smartSeed) {
                    val probe = probeFor(text)
                    if (probe != null) {
                        payload = probe.first
                        probeName = probe.second
                    }
                }
                if (payload == null) payload = payloadFor(text) ?: ByteArray(0)
                val hopStart = System.currentTimeMillis()
                val ok = hopSend(text, payload, framing, method)
                if (crawlGeneration != gen) break
                val reply = if (ok) mouth.replyData(hopStart) else null
                val elapsed = (System.currentTimeMillis() - hopStart) / 1000.0
                if (reply != null) {
                    carried = reply
                    val summary = replySummary(reply)
                    val finding = "$text ($leg) — $summary"
                    findings.add(finding)
                    withContext(Dispatchers.Main) {
                        _crawlFindings.value = findings.toList()
                    }
                }
                withContext(Dispatchers.Main) {
                    trail(
                        "${if (ok) "✓" else "✗"} hop $hopNumber/${journey.size} " +
                            "($leg) $text · ${payload.size} B out" +
                            (probeName?.let { " · spoke $it" } ?: "") +
                            (reply?.let { " · ${it.size} B back" } ?: " · no reply") +
                            " · %.2fs".format(elapsed)
                    )
                }
                index += 1
            }
            withContext(Dispatchers.Main) {
                if (crawlGeneration == gen) {
                    _crawlBusy.value = false
                    _crawlHomecoming.value = carried
                    trail("Home — carrying ${carried?.size ?: 0} byte(s)")
                    mouth.logRecon(
                        "centipede",
                        "route: ${route.joinToString(", ")}",
                        _crawlLines.value +
                            listOf("Harvest — ${findings.size} replies kept:") +
                            findings
                    )
                    if (homeTarget.isNotBlank() && carried != null) {
                        val homePayload = carried!!
                        launch(Dispatchers.Main) {
                            hopSend(homeTarget, homePayload, framing, method)
                            trail("Homecoming delivered to $homeTarget")
                        }
                    }
                }
            }
        }
    }

    fun stopCrawl() {
        crawlGeneration += 1
        crawlJob?.cancel()
        if (_crawlBusy.value) {
            _crawlBusy.value = false
            trail("Stopped — called home early")
            mouth.line("centipede: stopped by hand")
        }
    }

    // MARK: Subnet discovery for the route

    fun discoverSubnet(
        targetText: String, portsText: String,
        onRoute: (List<String>) -> Unit
    ) {
        mouth.scope.launch(Dispatchers.Default) {
            val ports = portsText.split(',')
                .mapNotNull { it.trim().toIntOrNull() }
                .filter { it in 1..65535 }
                .take(16)
            if (ports.isEmpty()) {
                withContext(Dispatchers.Main) {
                    _sweepStatus.value = "Discovery needs at least one valid port"
                }
                return@launch
            }
            val base = sweepBase(targetText)
            if (base == null) {
                withContext(Dispatchers.Main) {
                    _sweepStatus.value =
                        "Can't read \"$targetText\" as a subnet — try 192.168.1 or 192.168.1.0/24"
                }
                return@launch
            }
            val ownIP = mouth.localIPAddress()
            val pool = Executors.newFixedThreadPool(32)
            val gate = Semaphore(32)
            val found = sortedMapOf<String, MutableList<Int>>()
            val lock = Any()
            var probed = 0
            val jobs = mutableListOf<java.util.concurrent.Future<*>>()
            for (port in ports) {
                for (host in 1..254) {
                    val ip = "$base.$host"
                    if (ip == ownIP) continue
                    jobs.add(pool.submit {
                        gate.acquire()
                        try {
                            if (probe(ip, port, 1000)) {
                                synchronized(lock) {
                                    found.getOrPut(ip) { mutableListOf() }.add(port)
                                }
                            }
                        } finally {
                            gate.release()
                        }
                        synchronized(lock) {
                            probed += 1
                            if (probed % 254 == 0) {
                                val round = probed / 254
                                _sweepStatus.value =
                                    "Discovering $base.0/24 — round $round/${ports.size} (port ${ports.getOrNull(round - 1) ?: ""}), ${found.size} host(s) so far…"
                            }
                        }
                    })
                }
            }
            for (job in jobs) {
                try {
                    job.get()
                } catch (_: Exception) {
                }
            }
            pool.shutdown()
            pool.awaitTermination(5, TimeUnit.SECONDS)
            val lines = found.map { (ip, answeredPorts) ->
                "tcp://$ip:${answeredPorts.joinToString(",")}"
            }
            withContext(Dispatchers.Main) {
                _sweepStatus.value = if (lines.isEmpty()) {
                    "Discovery done — nothing answered on $base.0/24"
                } else {
                    "Discovery found ${lines.size} host(s) — added as port trains"
                }
                if (lines.isNotEmpty()) onRoute(lines)
            }
        }
    }

    private fun sweepBase(text: String): String? {
        var candidate = text.trim()
        if (candidate.isEmpty()) {
            val own = mouth.localIPAddress() ?: return null
            candidate = own
        }
        if (candidate.contains('/')) {
            candidate = candidate.substringBefore('/')
        }
        if (candidate.contains("://")) {
            candidate = candidate.substringAfter("://")
        }
        val parts = candidate.split('.')
        val octets = mutableListOf<Int>()
        for (part in parts) {
            val value = part.toIntOrNull() ?: return null
            if (value !in 0..255) return null
            octets.add(value)
        }
        return when (octets.size) {
            3 -> octets.joinToString(".")
            4 -> octets.take(3).joinToString(".")
            else -> null
        }
    }

    private fun probe(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    // MARK: Crosstalk

    fun startTalk(
        aText: String, bText: String, rounds: Int,
        seed: ByteArray, smartSeed: Boolean,
        probeFor: (String) -> Pair<ByteArray, String>?
    ) {
        if (_talkBusy.value || _crawlBusy.value) return
        val doorA = Crawl.expandRoute(listOf(aText)).first.firstOrNull()
        val doorB = Crawl.expandRoute(listOf(bText)).first.firstOrNull()
        talkGeneration += 1
        val gen = talkGeneration
        _talkLines.value = emptyList()
        _talkHomecoming.value = null
        if (doorA == null || doorB == null) {
            _talkLines.value = listOf(
                "✗ Both doors must be targets the route parser accepts — " +
                    "tcp://, udp://, http(s)://, phone:NAME, a train, a range."
            )
            return
        }
        _talkBusy.value = true
        val doorAName: String = doorA
        val doorBName: String = doorB
        var opener = seed
        var openerNote = ""
        if (smartSeed) {
            val probe = probeFor(doorAName)
            if (probe != null) {
                opener = probe.first
                openerNote = " · spoke ${probe.second}"
            }
        }
        _talkLines.value = listOf(
            "Crosstalk — $doorA ⇄ $doorB, up to $rounds round(s)"
        )
        mouth.line("crosstalk: $doorA ⇄ $doorB")
        talkJob = mouth.scope.launch {
            var legsLeft = maxOf(1, rounds) * 2
            var exchanges = 0
            var carriedBytes = 0
            val lastByDoor = mutableMapOf<String, ByteArray>()
            var message = opener
            var note = openerNote
            var toDoor = doorAName
            var fromDoor = doorBName
            var endWhy: String? = null
            var lastWord: ByteArray? = null
            while (true) {
                if (talkGeneration != gen) return@launch
                if (legsLeft <= 0) {
                    endWhy = "Rounds done — $exchanges exchange(s), " +
                        "$carriedBytes byte(s) carried"
                    lastWord = message
                    break
                }
                legsLeft -= 1
                val started = System.currentTimeMillis()
                val ok = hopSend(toDoor, message, "raw", "POST")
                if (talkGeneration != gen) return@launch
                val reply = if (ok) mouth.replyData(started) else null
                val secs = (System.currentTimeMillis() - started) / 1000.0
                if (reply == null || reply.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        talkLine(
                            "→ $toDoor · ${message.size} B out$note" +
                                " · silence · %.2fs".format(secs)
                        )
                    }
                    endWhy = "$toDoor had nothing to say — conversation " +
                        "over after $exchanges exchange(s)"
                    lastWord = null
                    break
                }
                exchanges += 1
                carriedBytes += reply.size
                val summary = replySummary(reply)
                val doorNow = toDoor
                withContext(Dispatchers.Main) {
                    talkLine(
                        "→ $doorNow · ${message.size} B out$note" +
                            " · ${reply.size} B back · %.2fs".format(secs)
                    )
                    talkLine("   $summary")
                }
                if (reply.contentEquals(message)) {
                    endWhy = "$toDoor echoed the words straight back — " +
                        "loop; conversation over"
                    lastWord = reply
                    break
                }
                if (lastByDoor[toDoor]?.contentEquals(reply) == true) {
                    endWhy = "$toDoor repeated itself — loop; " +
                        "conversation over"
                    lastWord = reply
                    break
                }
                lastByDoor[toDoor] = reply
                message = reply
                note = ""
                val swap = toDoor
                toDoor = fromDoor
                fromDoor = swap
            }
            withContext(Dispatchers.Main) {
                if (talkGeneration == gen) {
                    _talkBusy.value = false
                    _talkHomecoming.value = lastWord
                    val why = endWhy ?: "Conversation over"
                    talkLine(why)
                    mouth.line("crosstalk: $why")
                    mouth.logRecon(
                        "crosstalk", "$doorAName ⇄ $doorBName", _talkLines.value
                    )
                }
            }
        }
    }

    fun stopTalk() {
        talkGeneration += 1
        talkJob?.cancel()
        if (_talkBusy.value) {
            _talkBusy.value = false
            talkLine("Stopped — hung up on them both")
            mouth.line("crosstalk: stopped by hand")
        }
    }

    private fun talkLine(line: String) {
        _talkLines.value = (_talkLines.value + line).takeLast(500)
    }

    companion object {
        /// A short printable summary of a reply: its first
        /// printable line, else a byte count + hex head.
        fun replySummary(data: ByteArray): String {
            val text = PayloadKit.printableText(data)
            if (text != null) {
                val first = text.split("\n").firstOrNull() ?: text
                return first.take(70)
            }
            val hex = data.take(8).joinToString(" ") { "%02x".format(it) }
            return "${data.size} B · $hex"
        }
    }
}
