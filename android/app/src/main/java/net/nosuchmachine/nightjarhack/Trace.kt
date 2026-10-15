package net.nosuchmachine.nightjarhack

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

/// Network Trace support: adaptive rules, reply analysis, the
/// persistent crawl logbook, and the tracer itself.
///
/// A trace is an operator-started, foreground, stoppable run
/// that maps ONE IPv4 /24: every address knocked on the
/// discovery ports, every answering host profiled, every open
/// door spoken to in its library protocol, and every in-scope
/// endpoint a reply names followed (three hops deep) — until
/// the frontier is exhausted. References outside the scope are
/// written down, never contacted. Connect/banner/protocol
/// recon only: no exploitation, no credentials, nothing runs
/// in the background.

// MARK: Adaptive rules

/// One operator rule, from a line of the rules field:
///   contains TEXT => followup PAYLOAD NAME
///   contains TEXT => tag LABEL
///   contains TEXT => stop
///   port N => … (same three actions)
/// Blank lines and # comments are ignored. `contains` is a
/// case-insensitive substring test over banner + reply text.
data class TraceRule(
    val matchPort: Int?,
    val matchText: String?,
    val action: Action,
    val actionValue: String
) {
    enum class Action { FOLLOWUP, TAG, STOP }

    fun matches(port: Int, haystackLower: String): Boolean {
        return if (matchPort != null) {
            port == matchPort
        } else {
            matchText != null && haystackLower.contains(matchText)
        }
    }

    companion object {
        fun parse(text: String): List<TraceRule> {
            val out = mutableListOf<TraceRule>()
            for (rawLine in text.split("\n")) {
                val line = rawLine.trim()
                if (line.isEmpty() || line.startsWith("#")) continue
                val arrow = line.indexOf("=>")
                if (arrow < 0) continue
                val lhs = line.substring(0, arrow).trim()
                val rhs = line.substring(arrow + 2).trim()
                var matchPort: Int? = null
                var matchText: String? = null
                val lhsLower = lhs.lowercase()
                when {
                    lhsLower.startsWith("contains") -> {
                        val needle = lhs.substring("contains".length)
                            .trim().lowercase()
                        if (needle.isEmpty()) continue
                        matchText = needle
                    }
                    lhsLower.startsWith("port") -> {
                        matchPort = lhs.substring("port".length)
                            .trim().toIntOrNull() ?: continue
                    }
                    else -> continue
                }
                val rhsLower = rhs.lowercase()
                val action: Action
                val actionValue: String
                when {
                    rhsLower == "stop" || rhsLower.startsWith("stop") -> {
                        action = Action.STOP
                        actionValue = ""
                    }
                    rhsLower.startsWith("followup") -> {
                        action = Action.FOLLOWUP
                        actionValue = rhs.substring("followup".length).trim()
                    }
                    rhsLower.startsWith("tag") -> {
                        action = Action.TAG
                        actionValue = rhs.substring("tag".length).trim()
                    }
                    else -> continue
                }
                if (action != Action.STOP && actionValue.isEmpty()) continue
                out.add(TraceRule(matchPort, matchText, action, actionValue))
            }
            return out
        }
    }
}

// MARK: Reply analysis

/// What one banner/reply says, reduced to facts: a first line,
/// a preview, a content signature (for change detection), a
/// service hint, tags, and the endpoints the text itself names.
object TraceAnalyzer {

    data class Ref(val host: String, val port: Int?, val raw: String)

    data class Analysis(
        val firstLine: String,
        val preview: String,
        val signature: String,
        val serviceHint: String?,
        val tags: List<String>,
        val references: List<Ref>
    )

    private val ipRegex =
        Regex("""\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?::(\d{1,5}))?\b""")
    private val urlRegex = Regex("""(?i)https?://[^\s"'<>\\)\]]+""")
    private val httpStatusRegex = Regex("""(?m)^HTTP/\d(?:\.\d)?\s+(\d{3})""")
    private val titleRegex = Regex("""(?is)<title[^>]*>(.*?)</title>""")

    fun sha256Hex(data: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(data)
            .joinToString("") { "%02x".format(it) }

    private fun header(text: String, name: String): String? {
        val regex = Regex("""(?im)^$name:\s*(.+)$""")
        return regex.find(text)?.groupValues?.get(1)?.trim()
    }

    fun analyze(data: ByteArray, host: String, port: Int): Analysis {
        val text = PayloadKit.printableText(data) ?: ""
        val firstLine = text.lineSequence()
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?.take(120)
            ?: if (data.isEmpty()) "" else CrawlEngine.replySummary(data)
        val preview = when {
            text.isNotEmpty() -> text.take(400)
            data.isEmpty() -> ""
            else -> "hex: " + data.take(48)
                .joinToString(" ") { "%02x".format(it) }
        }

        // Service hints + tags — deliberately modest: the
        // shapes a banner actually announces, not a fingerprint
        // database.
        var hint: String? = null
        val tags = mutableListOf<String>()
        val status = httpStatusRegex.find(text)
        if (status != null) {
            hint = "HTTP"
            tags += "http-${status.groupValues[1]}"
        }
        header(text, "Server")?.let { tags += "server:" + it.take(40) }
        header(text, "WWW-Authenticate")?.let {
            tags += "auth:" + it.take(30)
        }
        if (header(text, "Location") != null) tags += "redirect"
        titleRegex.find(text)?.let { match ->
            val title = match.groupValues[1].trim()
                .replace(Regex("""\s+"""), " ")
            if (title.isNotEmpty()) tags += "title:" + title.take(48)
            if (hint == null) hint = "HTTP"
        }
        if (firstLine.startsWith("SSH-")) {
            if (hint == null) hint = "SSH"
            tags += "ssh:" + firstLine.removePrefix("SSH-").take(28)
        }
        if (firstLine.startsWith("220")) {
            val lower = text.lowercase()
            when {
                "ftp" in lower -> if (hint == null) hint = "FTP"
                "smtp" in lower || "esmtp" in lower || "mail" in lower ->
                    if (hint == null) hint = "SMTP"
            }
            tags += "greeting-220"
        }
        if ("+PONG" in text) {
            if (hint == null) hint = "Redis"
            tags += "redis"
        }
        if ("-NOAUTH" in text) {
            if (hint == null) hint = "Redis"
            tags += "auth-required"
        }
        if ("-ERR" in text && port == 6379 && hint == null) hint = "Redis"
        if ("RFB " in text) {
            if (hint == null) hint = "VNC"
            tags += "rfb"
        }
        if (firstLine.startsWith("+OK") && (port == 110 || port == 995)) {
            if (hint == null) hint = "POP3"
        }
        if ("mysql" in text.lowercase() && hint == null) hint = "MySQL"
        if ("PostgreSQL" in text && hint == null) hint = "PostgreSQL"
        if (hint == null) hint = ScanKit.serviceNames[port]

        // Endpoint references the text names: URLs first (they
        // carry ports and context), then bare IPv4 literals.
        val refsByKey = linkedMapOf<String, Ref>()
        fun addRef(refHost: String, refPort: Int?, raw: String) {
            val key = if (refPort != null) "$refHost:$refPort" else refHost
            val existing = refsByKey[key]
            if (existing == null ||
                (existing.port == null && refPort != null)
            ) {
                refsByKey[key] = Ref(refHost, refPort, raw)
            }
        }
        for (match in urlRegex.findAll(text)) {
            val raw = match.value.trimEnd('.', ',', ';')
            try {
                val url = java.net.URL(raw)
                val refHost = url.host ?: continue
                addRef(refHost, if (url.port >= 0) url.port else null, raw)
            } catch (_: Exception) {
            }
        }
        for (match in ipRegex.findAll(text)) {
            val octets = (1..4).map {
                match.groupValues[it].toIntOrNull() ?: -1
            }
            if (octets.any { it !in 0..255 }) continue
            val ip = octets.joinToString(".")
            if (ip == "0.0.0.0" || ip == "255.255.255.255") continue
            val refPort = match.groupValues[5].toIntOrNull()
                ?.takeIf { it in 1..65535 }
            addRef(ip, refPort, match.value)
        }

        return Analysis(
            firstLine = firstLine,
            preview = preview,
            signature = sha256Hex(data),
            serviceHint = hint,
            tags = tags.distinct(),
            references = refsByKey.values.toList()
        )
    }
}

// MARK: The logbook

/// The persistent crawl logbook: every door the centipede or
/// a trace has ever heard from, keyed by address, merged
/// across runs. One JSON file in filesDir; all access is
/// synchronized, loads are forgiving (a corrupt book starts
/// fresh in memory, the file is left alone until a save).
class TraceBookStore(context: Context) {

    val file: File = File(context.filesDir, "network-trace-logbook.json")

    private val lock = Any()
    private var root: JSONObject = load()

    private fun freshRoot(): JSONObject {
        val fresh = JSONObject()
        fresh.put("version", 1)
        fresh.put("hosts", JSONObject())
        return fresh
    }

    private fun load(): JSONObject {
        val parsed = try {
            if (file.exists()) JSONObject(file.readText()) else freshRoot()
        } catch (_: Exception) {
            freshRoot()
        }
        if (parsed.optJSONObject("hosts") == null) {
            parsed.put("hosts", JSONObject())
        }
        return parsed
    }

    private fun saveLocked() {
        root.put("updatedAt", System.currentTimeMillis() / 1000.0)
        try {
            file.writeText(root.toString())
        } catch (_: Exception) {
        }
    }

    fun clear() {
        synchronized(lock) {
            root = freshRoot()
            saveLocked()
        }
    }

    /// A deep copy of the book, for before/after diffing.
    fun snapshot(): JSONObject = synchronized(lock) {
        JSONObject(root.toString())
    }

    /// (host, port) out of a target text, for the network
    /// targets; null for BLE/phone lines.
    private fun hostPortOf(targetText: String): Pair<String, Int>? {
        val parsed = try {
            SendTarget.parse(targetText)
        } catch (_: Exception) {
            return null
        }
        return when (parsed) {
            is SendTarget.Tcp -> parsed.host to parsed.port
            is SendTarget.Udp -> parsed.host to parsed.port
            is SendTarget.Http -> {
                val host = parsed.url.host ?: return null
                val port = if (parsed.url.port >= 0) parsed.url.port
                else if (parsed.https) 443 else 80
                host to port
            }
            else -> null
        }
    }

    private fun ensureHost(host: String, now: Double): JSONObject {
        val hosts = root.getJSONObject("hosts")
        var entry = hosts.optJSONObject(host)
        if (entry == null) {
            entry = JSONObject()
            entry.put("ip", host)
            entry.put("firstSeen", now)
            entry.put("timesSeen", 0)
            entry.put("sources", JSONArray())
            entry.put("services", JSONObject())
            hosts.put(host, entry)
        }
        return entry
    }

    private fun ensureService(
        hostEntry: JSONObject, host: String, port: Int, now: Double
    ): JSONObject {
        val services = hostEntry.getJSONObject("services")
        val key = "$host:$port"
        var entry = services.optJSONObject(key)
        if (entry == null) {
            entry = JSONObject()
            entry.put("host", host)
            entry.put("port", port)
            entry.put("firstSeen", now)
            entry.put("timesSeen", 0)
            entry.put("tags", JSONArray())
            entry.put("probes", JSONArray())
            services.put(key, entry)
        }
        return entry
    }

    private fun addUnique(array: JSONArray, value: String) {
        for (i in 0 until array.length()) {
            if (array.optString(i) == value) return
        }
        array.put(value)
    }

    /// Remember a door and (when there is one) what it said.
    /// Called for centipede hops, trace banners and trace probe
    /// replies alike; `source` says who heard it.
    fun record(targetText: String, reply: ByteArray?, source: String) {
        val (host, port) = hostPortOf(targetText) ?: return
        synchronized(lock) {
            val now = System.currentTimeMillis() / 1000.0
            val hostEntry = ensureHost(host, now)
            hostEntry.put("lastSeen", now)
            hostEntry.put("timesSeen", hostEntry.optInt("timesSeen") + 1)
            addUnique(hostEntry.getJSONArray("sources"), source)
            val service = ensureService(hostEntry, host, port, now)
            service.put("lastSeen", now)
            service.put("timesSeen", service.optInt("timesSeen") + 1)
            if (reply != null && reply.isNotEmpty()) {
                val analysis = TraceAnalyzer.analyze(reply, host, port)
                service.put("banner", analysis.firstLine)
                service.put("preview", analysis.preview)
                service.put("signature", analysis.signature)
                analysis.serviceHint?.let {
                    service.put("serviceHint", it)
                }
                val tags = service.getJSONArray("tags")
                for (tag in analysis.tags) addUnique(tags, tag)
            }
            saveLocked()
        }
    }

    /// Note one protocol probe a door was sent (and its reply,
    /// when it answered) in the door's probe history.
    fun recordProbe(targetText: String, name: String, reply: ByteArray?) {
        val (host, port) = hostPortOf(targetText) ?: return
        synchronized(lock) {
            val now = System.currentTimeMillis() / 1000.0
            val hostEntry = ensureHost(host, now)
            val service = ensureService(hostEntry, host, port, now)
            service.put("lastSeen", now)
            val probe = JSONObject()
            probe.put("name", name)
            probe.put("at", now)
            probe.put("bytes", reply?.size ?: 0)
            probe.put("answered", reply != null)
            if (reply != null) {
                probe.put("signature", TraceAnalyzer.sha256Hex(reply))
            }
            service.getJSONArray("probes").put(probe)
            saveLocked()
        }
    }

    fun addTag(host: String, port: Int, tag: String) {
        synchronized(lock) {
            val now = System.currentTimeMillis() / 1000.0
            val hostEntry = ensureHost(host, now)
            val service = ensureService(hostEntry, host, port, now)
            addUnique(service.getJSONArray("tags"), tag)
            saveLocked()
        }
    }

    fun addTagForTarget(targetText: String, tag: String) {
        val (host, port) = hostPortOf(targetText) ?: return
        addTag(host, port, tag)
    }
}

/// Logbook before/after diff, in the export's shape.
internal fun traceDiff(before: JSONObject, after: JSONObject): JSONObject {
    fun hostsOf(root: JSONObject): JSONObject =
        root.optJSONObject("hosts") ?: JSONObject()

    fun hostKeys(root: JSONObject): Set<String> {
        val out = mutableSetOf<String>()
        val keys = hostsOf(root).keys()
        while (keys.hasNext()) out.add(keys.next())
        return out
    }

    fun serviceSignatures(root: JSONObject): Map<String, String> {
        val out = sortedMapOf<String, String>()
        val hosts = hostsOf(root)
        val hostIter = hosts.keys()
        while (hostIter.hasNext()) {
            val ip = hostIter.next()
            val services = hosts.optJSONObject(ip)
                ?.optJSONObject("services") ?: continue
            val serviceIter = services.keys()
            while (serviceIter.hasNext()) {
                val key = serviceIter.next()
                out[key] = services.optJSONObject(key)
                    ?.optString("signature", "") ?: ""
            }
        }
        return out
    }

    val beforeHosts = hostKeys(before)
    val afterHosts = hostKeys(after)
    val beforeServices = serviceSignatures(before)
    val afterServices = serviceSignatures(after)
    val changed = JSONArray()
    for (key in (afterServices.keys intersect beforeServices.keys).sorted()) {
        if (afterServices[key] != beforeServices[key]) {
            changed.put(
                JSONObject()
                    .put("service", key)
                    .put("before", beforeServices[key])
                    .put("after", afterServices[key])
            )
        }
    }
    return JSONObject()
        .put("newHosts", JSONArray((afterHosts - beforeHosts).sorted()))
        .put("missingHosts", JSONArray((beforeHosts - afterHosts).sorted()))
        .put("newServices", JSONArray((afterServices.keys - beforeServices.keys).sorted()))
        .put("missingServices", JSONArray((beforeServices.keys - afterServices.keys).sorted()))
        .put("changedServices", changed)
}

// MARK: The tracer

class NetworkTracer(
    private val appContext: Context,
    private val mouth: Mouth,
    private val store: TraceBookStore
) {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val scanner = PortScanner()

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy
    private val _lines = MutableStateFlow<List<String>>(emptyList())
    val lines: StateFlow<List<String>> = _lines
    private val _status = MutableStateFlow("")
    val status: StateFlow<String> = _status
    private val _latestExport = MutableStateFlow<File?>(null)
    val latestExport: StateFlow<File?> = _latestExport

    private val _centipedeRoute = MutableStateFlow<String?>(null)
    val centipedeRoute: StateFlow<String?> = _centipedeRoute

    @Volatile
    var autoCentipede = false
        private set

    fun armCentipede() {
        autoCentipede = true
    }

    fun clearCentipedeRoute() {
        _centipedeRoute.value = null
    }

    @Volatile
    private var generation = 0
    @Volatile
    private var stoppedFor = -1
    private var job: Job? = null

    private fun note(text: String) {
        _status.value = text
        _lines.value = (_lines.value + text).takeLast(600)
    }

    fun stop() {
        stoppedFor = generation
        generation += 1
        job?.cancel()
        _busy.value = false
        note("Trace stopped — exporting the partial map")
    }

    fun start(
        scopeText: String,
        discoveryPorts: String,
        profilePorts: String,
        includeBonjour: Boolean,
        adaptive: Boolean,
        rules: List<TraceRule>,
        probeFor: (String) -> Pair<ByteArray, String>?,
        payloadNamed: (String) -> ByteArray?,
        autoCentipede: Boolean = false
    ) {
        if (_busy.value) return
        val base = traceBase(scopeText)
        if (base == null) {
            note(
                "✗ Can't read \"$scopeText\" as a scope — " +
                    "try 192.168.1 or 192.168.1.0/24 (blank = this phone's /24)"
            )
            return
        }
        val discovery = ScanKit.parsePorts(discoveryPorts, defaultToTop = false)
        if (discovery.isEmpty()) {
            note("✗ Discovery needs at least one valid port")
            return
        }
        val profile = ScanKit.parsePorts(profilePorts, defaultToTop = true)
        val ownIP = mouth.localIPAddress()
        generation += 1
        val gen = generation
        stoppedFor = -1
        this.autoCentipede = autoCentipede
        _busy.value = true
        _lines.value = emptyList()
        val run = Run(
            gen, base, ownIP, discovery, profile,
            adaptive, rules, probeFor, payloadNamed
        )
        job = scope.launch {
            val before = store.snapshot()
            var stoppedEarly = false
            var fatal: String? = null
            try {
                val bonjourDeferred = if (includeBonjour) {
                    async { BonjourSweeper(appContext).sweep(5L) }
                } else {
                    null
                }
                note("Network trace — mapping $base.0/24, one scope only")
                mouth.line("network-trace: mapping $base.0/24")
                run.discover()
                if (!run.alive()) throw CancellationException()
                if (bonjourDeferred != null) {
                    val found = bonjourDeferred.await()
                    run.absorbBonjour(found)
                }
                val queue = ArrayDeque<RefWork>()
                for (ip in run.candidateHosts()) {
                    if (!run.alive()) throw CancellationException()
                    run.profileHost(ip, depth = 0, queue)
                }
                run.expand(queue)
                if (!run.alive()) throw CancellationException()
            } catch (e: CancellationException) {
                stoppedEarly = true
            } catch (e: Exception) {
                fatal = e.message ?: "unknown error"
                note("✗ Trace error: $fatal")
            }
            // Finish: plain (non-suspending) work only, so it
            // still runs after a stop() cancellation.
            if (gen == generation || stoppedFor == gen) {
                val after = store.snapshot()
                val finishedAt = System.currentTimeMillis() / 1000.0
                val export = run.buildExport(
                    includeBonjour = includeBonjour,
                    stoppedEarly = stoppedEarly,
                    fatal = fatal,
                    finishedAt = finishedAt,
                    diff = traceDiff(before, after)
                )
                var exportFile: File? = null
                try {
                    val dir = File(appContext.filesDir, "traces")
                    dir.mkdirs()
                    val stamp = SimpleDateFormat(
                        "yyyyMMdd-HHmmss", Locale.US
                    ).format(Date())
                    exportFile = File(dir, "nightjar-trace-$stamp.json")
                    exportFile.writeText(export.toString(2))
                    _latestExport.value = exportFile
                } catch (e: Exception) {
                    note("✗ Export failed: ${e.message}")
                }
                val summaryLine = when {
                    fatal != null ->
                        "Trace ended early (error) — ${run.hosts.size} host(s), " +
                            "${run.doorCount} door(s)"
                    stoppedEarly ->
                        "Frontier reached early (stopped) — ${run.hosts.size} host(s), " +
                            "${run.doorCount} door(s), ${run.probeCount} probe(s)"
                    else ->
                        "Frontier exhausted — ${run.hosts.size} host(s), " +
                            "${run.doorCount} door(s), ${run.probeCount} probe(s)"
                }
                note(
                    summaryLine + (exportFile?.let {
                        " · exported ${it.name}"
                    } ?: "")
                )
                if (this@NetworkTracer.autoCentipede) {
                    this@NetworkTracer.autoCentipede = false
                    val routeLines = mutableListOf<String>()
                    var loaded = 0
                    val sortedHosts = run.hosts.values.sortedBy {
                        it.ip.substringAfterLast('.').toIntOrNull() ?: 0
                    }
                    for (host in sortedHosts) {
                        if (loaded >= 300) break
                        val ports = host.services.keys
                            .filter { it > 0 }.sorted()
                        if (ports.isEmpty()) continue
                        val take = ports.take(300 - loaded)
                        routeLines += host.ip + ":" +
                            take.joinToString(",")
                        loaded += take.size
                    }
                    if (routeLines.isNotEmpty()) {
                        _centipedeRoute.value =
                            routeLines.joinToString("\n")
                        note(
                            "→ Centipede configured — $loaded door(s) " +
                                "on ${routeLines.size} host(s) loaded " +
                                "as its route"
                        )
                    } else {
                        note(
                            "→ Centipede setup — the trace found no " +
                                "open doors to load"
                        )
                    }
                }
                mouth.logRecon("network-trace", "$base.0/24", _lines.value)
                _busy.value = false
            }
        }
    }

    // MARK: One send on the shared reply channel (the
    // CrawlEngine.hopSend shape, minus phone: doors)

    private suspend fun probeSend(text: String, payload: ByteArray): Boolean =
        suspendCancellableCoroutine { cont ->
            val parsed = try {
                SendTarget.parse(text)
            } catch (_: Exception) {
                if (cont.isActive) cont.resume(false)
                return@suspendCancellableCoroutine
            }
            when (parsed) {
                is SendTarget.Http ->
                    mouth.sendHTTP(parsed, payload, "raw", "POST") { ok ->
                        if (cont.isActive) cont.resume(ok)
                    }
                is SendTarget.Tcp, is SendTarget.Udp ->
                    mouth.sendNetwork(parsed, payload, "raw", read = true) { ok ->
                        if (cont.isActive) cont.resume(ok)
                    }
                else -> if (cont.isActive) cont.resume(false)
            }
        }

    /// The sweepBase parser from Crawl.kt, copied (blank = this
    /// phone's own address; accepts a.b.c, a.b.c.d, a.b.c.d/24).
    private fun traceBase(text: String): String? {
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

    private fun knock(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun ipToLong(ip: String): Long =
        ip.split('.').fold(0L) { acc, part ->
            acc * 256 + (part.toIntOrNull() ?: 0)
        }

    private data class RefWork(val host: String, val port: Int?, val depth: Int)

    private data class RefEdge(val from: String, val toHost: String, val toPort: Int?)

    private class RunService(val port: Int) {
        var service: String = ""
        var banner: String? = null
        var signature: String? = null
        var hint: String? = null
        val tags = linkedSetOf<String>()
        val probes = mutableListOf<JSONObject>()
    }

    private class RunHost(val ip: String) {
        val sources = linkedSetOf<String>()
        val services = sortedMapOf<Int, RunService>()
    }

    /// One run's whole world: the map being built, the caps,
    /// and the stage functions. Inner, so the stages share the
    /// tracer's mouth, store and status lines directly.
    private inner class Run(
        val gen: Int,
        val base: String,
        val ownIP: String?,
        val discoveryPorts: List<Int>,
        val profilePorts: List<Int>,
        val adaptive: Boolean,
        val rules: List<TraceRule>,
        val probeFor: (String) -> Pair<ByteArray, String>?,
        val payloadNamed: (String) -> ByteArray?
    ) {
        val hosts = linkedMapOf<String, RunHost>()
        val discoveredDoors = mutableMapOf<String, MutableSet<Int>>()
        val profiledHosts = mutableSetOf<String>()
        val probedDoors = mutableSetOf<String>()
        val externalRefs = linkedSetOf<String>()
        val refEdges = mutableListOf<RefEdge>()
        val limitsHit = mutableListOf<String>()
        var probeCount = 0
        var doorCount = 0
        var refCount = 0
        var bonjour: List<BonjourSweeper.Found> = emptyList()
        val startedAt = System.currentTimeMillis() / 1000.0

        fun alive(): Boolean = generation == gen

        fun inScope(ip: String): Boolean {
            if (!ip.startsWith("$base.")) return false
            val last = ip.substringAfterLast('.').toIntOrNull() ?: return false
            return last in 1..254
        }

        fun host(ip: String, source: String): RunHost {
            val entry = hosts.getOrPut(ip) { RunHost(ip) }
            if (source.isNotEmpty()) entry.sources.add(source)
            return entry
        }

        fun candidateHosts(): List<String> =
            hosts.keys.filter { inScope(it) && it != ownIP }
                .sortedBy { ipToLong(it) }

        private fun limitOnce(name: String) {
            if (name !in limitsHit) {
                limitsHit.add(name)
                note("Limit reached — $name")
            }
        }

        // Stage (c): knock the whole /24 on the discovery ports.
        fun discover() {
            val pool = Executors.newFixedThreadPool(48)
            val gate = Semaphore(48)
            val lock = Any()
            var knocked = 0
            val total = 254 * discoveryPorts.size
            val jobs = mutableListOf<java.util.concurrent.Future<*>>()
            for (port in discoveryPorts) {
                for (hostNumber in 1..254) {
                    val ip = "$base.$hostNumber"
                    if (ip == ownIP) continue
                    jobs.add(pool.submit {
                        gate.acquire()
                        try {
                            if (knock(ip, port, 1000)) {
                                synchronized(lock) {
                                    host(ip, "discovery")
                                    discoveredDoors.getOrPut(ip) {
                                        mutableSetOf()
                                    }.add(port)
                                }
                            }
                        } finally {
                            gate.release()
                        }
                        synchronized(lock) {
                            knocked += 1
                            if (knocked % 508 == 0) {
                                note(
                                    "Discovery — $knocked/$total knocked, " +
                                        "${hosts.size} host(s) answering…"
                                )
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
            note(
                "Discovery done — ${hosts.size} host(s) answered " +
                    "on $base.0/24"
            )
        }

        // Stage (b), merged: Bonjour sightings join the map;
        // in-scope addresses become profile candidates.
        fun absorbBonjour(found: List<BonjourSweeper.Found>) {
            bonjour = found
            var joined = 0
            for (entry in found) {
                val hostAddress = entry.host ?: continue
                if (inScope(hostAddress) && hostAddress != ownIP) {
                    host(hostAddress, "bonjour")
                    joined += 1
                }
            }
            note(
                "Bonjour — ${found.size} service(s) seen, " +
                    "$joined in scope"
            )
        }

        private suspend fun registerService(ip: String, result: PortResult) {
            val hostEntry = host(ip, "")
            if (!hostEntry.services.containsKey(result.port)) {
                if (doorCount >= 2048) {
                    limitOnce("door cap (2048)")
                    return
                }
                doorCount += 1
                hostEntry.services[result.port] = RunService(result.port)
            }
            val service = hostEntry.services.getValue(result.port)
            service.service = result.service
            val banner = result.banner
            if (banner != null) {
                service.banner = banner
                val bannerBytes = banner.toByteArray(Charsets.UTF_8)
                store.record("tcp://$ip:${result.port}", bannerBytes, "trace")
                val analysis = TraceAnalyzer.analyze(bannerBytes, ip, result.port)
                service.hint = analysis.serviceHint
                service.signature = analysis.signature
                service.tags.addAll(analysis.tags)
            }
        }

        // Stages (d)+(e) for one host: scan the profile ports,
        // file the banners, then speak to every open door.
        suspend fun profileHost(ip: String, depth: Int, queue: ArrayDeque<RefWork>) {
            if (!profiledHosts.add(ip)) return
            host(ip, "")
            note("Profiling $ip (${profilePorts.size} ports)…")
            val results = mutableListOf<PortResult>()
            scanner.scan(ip, profilePorts, { result ->
                synchronized(results) { results.add(result) }
            }, { _, _ -> })
            for (result in results.sortedBy { it.port }) {
                registerService(ip, result)
            }
            // Doors discovery found that the profile list lacks
            // still get their banner + probe.
            val extras = discoveredDoors[ip].orEmpty() - profilePorts.toSet()
            for (port in extras.sorted()) {
                var extra: PortResult? = null
                scanner.scan(ip, listOf(port), { extra = it }, { _, _ -> })
                val found = extra ?: continue
                registerService(ip, found)
            }
            val doors = hosts[ip]?.services?.keys?.toList().orEmpty()
            for (port in doors) {
                if (!alive()) throw CancellationException()
                probeOpenDoor(ip, port, depth, queue)
            }
        }

        // A specific referenced door: verify it answers, file
        // its banner, then speak its protocol like any door.
        private suspend fun probeReferencedDoor(
            ip: String, port: Int, depth: Int, queue: ArrayDeque<RefWork>
        ) {
            var result: PortResult? = null
            scanner.scan(ip, listOf(port), { result = it }, { _, _ -> })
            val found = result ?: return
            registerService(ip, found)
            probeOpenDoor(ip, port, depth, queue)
        }

        // Stage (e): send the door its library probe, file the
        // reply, apply the adaptive rules, follow references.
        private suspend fun probeOpenDoor(
            ip: String, port: Int, depth: Int, queue: ArrayDeque<RefWork>
        ) {
            val key = "$ip:$port"
            if (!probedDoors.add(key)) return
            val service = hosts[ip]?.services?.get(port) ?: return
            val targetText = "tcp://$ip:$port"
            val probe = probeFor(targetText) ?: return
            if (probeCount >= 1024) {
                limitOnce("probe cap (1024)")
                return
            }
            probeCount += 1
            val started = System.currentTimeMillis()
            val ok = probeSend(targetText, probe.first)
            val reply = if (ok) mouth.replyData(started) else null
            service.probes.add(probeEntry(probe.second, reply))
            store.recordProbe(targetText, probe.second, reply)
            if (reply == null) return
            processReply(ip, port, reply, depth, queue)
        }

        private suspend fun processReply(
            ip: String, port: Int, reply: ByteArray,
            depth: Int, queue: ArrayDeque<RefWork>
        ) {
            val service = hosts[ip]?.services?.get(port) ?: return
            val targetText = "tcp://$ip:$port"
            val analysis = TraceAnalyzer.analyze(reply, ip, port)
            analysis.serviceHint?.let { service.hint = it }
            service.signature = analysis.signature
            service.tags.addAll(analysis.tags)
            store.record(targetText, reply, "trace")
            var suppressRefs = false
            if (adaptive && rules.isNotEmpty()) {
                val haystack = ((service.banner ?: "") + "\n" +
                    (PayloadKit.printableText(reply) ?: "")).lowercase()
                val fired = mutableSetOf<Int>()
                var followups = 0
                for ((index, rule) in rules.withIndex()) {
                    if (!alive()) throw CancellationException()
                    if (!rule.matches(port, haystack)) continue
                    when (rule.action) {
                        TraceRule.Action.TAG -> {
                            service.tags.add(rule.actionValue)
                            store.addTag(ip, port, rule.actionValue)
                        }
                        TraceRule.Action.STOP -> suppressRefs = true
                        TraceRule.Action.FOLLOWUP -> {
                            if (index in fired || followups >= 4) continue
                            val payload = payloadNamed(rule.actionValue)
                                ?: continue
                            if (probeCount >= 1024) {
                                limitOnce("probe cap (1024)")
                                continue
                            }
                            fired.add(index)
                            followups += 1
                            probeCount += 1
                            val followStarted = System.currentTimeMillis()
                            val followOk = probeSend(targetText, payload)
                            val followReply = if (followOk) {
                                mouth.replyData(followStarted)
                            } else {
                                null
                            }
                            val followName = "followup: ${rule.actionValue}"
                            service.probes.add(probeEntry(followName, followReply))
                            store.recordProbe(targetText, followName, followReply)
                            if (followReply != null) {
                                store.record(targetText, followReply, "trace-followup")
                                val followAnalysis = TraceAnalyzer.analyze(
                                    followReply, ip, port
                                )
                                var followSuppress = false
                                val followHaystack =
                                    ((service.banner ?: "") + "\n" +
                                        (PayloadKit.printableText(followReply)
                                            ?: "")).lowercase()
                                for (followRule in rules) {
                                    if (!followRule.matches(port, followHaystack)) {
                                        continue
                                    }
                                    when (followRule.action) {
                                        TraceRule.Action.TAG -> {
                                            service.tags.add(followRule.actionValue)
                                            store.addTag(
                                                ip, port, followRule.actionValue
                                            )
                                        }
                                        TraceRule.Action.STOP ->
                                            followSuppress = true
                                        TraceRule.Action.FOLLOWUP -> Unit
                                    }
                                }
                                if (!followSuppress) {
                                    enqueueRefs(followAnalysis, ip, port, depth, queue)
                                }
                            }
                        }
                    }
                }
            }
            if (!suppressRefs) {
                enqueueRefs(analysis, ip, port, depth, queue)
            }
        }

        private fun enqueueRefs(
            analysis: TraceAnalyzer.Analysis, fromIp: String, fromPort: Int,
            depth: Int, queue: ArrayDeque<RefWork>
        ) {
            for (ref in analysis.references) {
                refCount += 1
                refEdges.add(RefEdge("$fromIp:$fromPort", ref.host, ref.port))
                if (inScope(ref.host) && ref.host != ownIP) {
                    host(ref.host, "reference")
                    if (depth + 1 <= 3) {
                        queue.addLast(RefWork(ref.host, ref.port, depth + 1))
                    } else {
                        limitOnce("reference depth (3)")
                    }
                } else {
                    externalRefs.add(ref.raw)
                }
            }
        }

        // Stage (f): drain the reference frontier.
        suspend fun expand(queue: ArrayDeque<RefWork>) {
            var followed = 0
            while (queue.isNotEmpty()) {
                if (!alive()) throw CancellationException()
                val item = queue.removeFirst()
                followed += 1
                val itemPort = item.port
                if (itemPort != null) {
                    if ("${item.host}:$itemPort" in probedDoors) continue
                    if (doorCount >= 2048) {
                        limitOnce("door cap (2048)")
                        break
                    }
                    host(item.host, "reference")
                    note("Following reference → ${item.host}:$itemPort (depth ${item.depth})")
                    probeReferencedDoor(item.host, itemPort, item.depth, queue)
                } else {
                    if (item.host in profiledHosts) continue
                    if (hosts.size >= 254) {
                        limitOnce("host cap (254)")
                        break
                    }
                    note("Following reference → ${item.host} (depth ${item.depth})")
                    profileHost(item.host, item.depth, queue)
                }
            }
            if (followed > 0) {
                note("Reference frontier drained — $followed followed")
            }
        }

        private fun probeEntry(name: String, reply: ByteArray?): JSONObject {
            val entry = JSONObject()
            entry.put("name", name)
            entry.put("bytes", reply?.size ?: 0)
            entry.put("answered", reply != null)
            if (reply != null) {
                entry.put("signature", TraceAnalyzer.sha256Hex(reply))
                entry.put(
                    "firstLine",
                    TraceAnalyzer.analyze(reply, "", 0).firstLine
                )
            }
            return entry
        }

        // Stage (g): the export — one JSON document another
        // component can consume without knowing this app.
        fun buildExport(
            includeBonjour: Boolean,
            stoppedEarly: Boolean,
            fatal: String?,
            finishedAt: Double,
            diff: JSONObject
        ): JSONObject {
            val export = JSONObject()
            export.put("schema", "net.nosuchmachine.nightjar.network-trace")
            export.put("schemaVersion", 1)
            export.put("kind", "trace-run")
            export.put("generatedAt", finishedAt)

            val runInfo = JSONObject()
            runInfo.put("scope", "$base.0/24")
            runInfo.put("base", base)
            ownIP?.let { runInfo.put("ownIP", it) }
            runInfo.put("startedAt", startedAt)
            runInfo.put("finishedAt", finishedAt)
            runInfo.put("discoveryPorts", JSONArray(discoveryPorts))
            runInfo.put("profilePorts", JSONArray(profilePorts))
            runInfo.put("bonjour", includeBonjour)
            runInfo.put("adaptive", adaptive)
            runInfo.put("ruleCount", rules.size)
            runInfo.put("stoppedEarly", stoppedEarly)
            fatal?.let { runInfo.put("error", it) }
            runInfo.put("limitsHit", JSONArray(limitsHit))
            export.put("run", runInfo)

            val summary = JSONObject()
            summary.put("hosts", hosts.size)
            summary.put("services", doorCount)
            summary.put("probes", probeCount)
            summary.put("references", refCount)
            summary.put("externalReferences", externalRefs.size)
            summary.put("durationSeconds", finishedAt - startedAt)
            export.put("summary", summary)

            val hostsArray = JSONArray()
            val nodes = JSONArray()
            val edges = JSONArray()
            val sortedHosts = hosts.values.sortedBy { ipToLong(it.ip) }
            for (hostEntry in sortedHosts) {
                val hostJson = JSONObject()
                hostJson.put("ip", hostEntry.ip)
                hostJson.put("sources", JSONArray(hostEntry.sources.toList()))
                val servicesArray = JSONArray()
                for ((port, service) in hostEntry.services) {
                    val serviceJson = JSONObject()
                    serviceJson.put("port", port)
                    serviceJson.put("service", service.service)
                    service.banner?.let { serviceJson.put("banner", it) }
                    service.hint?.let { serviceJson.put("serviceHint", it) }
                    service.signature?.let { serviceJson.put("signature", it) }
                    serviceJson.put("tags", JSONArray(service.tags.toList()))
                    val probesArray = JSONArray()
                    for (probe in service.probes) probesArray.put(probe)
                    serviceJson.put("probes", probesArray)
                    servicesArray.put(serviceJson)

                    val node = JSONObject()
                    node.put("id", "${hostEntry.ip}:$port")
                    node.put("kind", "service")
                    node.put("host", hostEntry.ip)
                    node.put("port", port)
                    service.hint?.let { node.put("service", it) }
                    service.signature?.let { node.put("signature", it) }
                    nodes.put(node)
                    edges.put(
                        JSONObject()
                            .put("from", hostEntry.ip)
                            .put("to", "${hostEntry.ip}:$port")
                            .put("kind", "door")
                    )
                }
                hostJson.put("services", servicesArray)
                hostsArray.put(hostJson)

                val hostNode = JSONObject()
                hostNode.put("id", hostEntry.ip)
                hostNode.put("kind", "host")
                nodes.put(hostNode)
            }
            for (edge in refEdges) {
                val edgeJson = JSONObject()
                edgeJson.put("from", edge.from)
                edgeJson.put("to", edge.toHost)
                edge.toPort?.let { edgeJson.put("port", it) }
                edgeJson.put("kind", "reference")
                edges.put(edgeJson)
            }
            export.put("hosts", hostsArray)
            export.put("nodes", nodes)
            export.put("edges", edges)

            val bonjourArray = JSONArray()
            for (entry in bonjour) {
                val entryJson = JSONObject()
                entryJson.put("type", entry.type)
                entryJson.put("label", entry.label)
                entryJson.put("name", entry.name)
                entry.host?.let { entryJson.put("host", it) }
                entry.port?.let { entryJson.put("port", it) }
                bonjourArray.put(entryJson)
            }
            export.put("bonjour", bonjourArray)
            export.put(
                "externalReferences",
                JSONArray(externalRefs.sorted())
            )
            export.put("diff", diff)
            export.put(
                "limitations",
                JSONArray(
                    listOf(
                        "TCP connect scanning only — UDP services and " +
                            "filtered ports stay invisible.",
                        "Banner grabs are brief peeks; a service that " +
                            "waits to be spoken to shows no banner.",
                        "Protocol probes come from the payload library; " +
                            "a door with no library probe was only " +
                            "banner-grabbed.",
                        "One /24 scope — referenced addresses outside " +
                            "it are recorded, never contacted.",
                        "Foreground only: the trace runs while the app " +
                            "is open, and stops when you stop it."
                    )
                )
            )
            return export
        }
    }
}
