package net.nosuchmachine.nightjarhack

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

/// EMCON — emissions control, the Kotlin mirror of the iOS
/// Emcon. The defensive half of nightjar-hack: turn the app's
/// own instruments inward so the operator can see (and shut
/// down) what this device announces to the network, and hear
/// anyone who comes probing with the same techniques.
///
///  - Exposure score: a single number for how visible this
///    device is right now, plus the weights that produced it.
///  - Self-recon: knock this device with Recon's own probe
///    registry and itemize what answers.
///  - Announcement audit: browse the LAN with NSD the way the
///    Scan tab does and flag every announcement that is this
///    device — mDNS speaks the device's name.
///  - Silence: one switch forces Serve stealth, disarms the
///    BLE GATT host and stops the BLE beacon. EMCON never
///    re-opens an emission on its own.
///  - Tripwire: quiet listeners on the probe ports, TCP and
///    UDP. The probes are wire-exact, which makes them
///    fingerprintable. The tripwire never replies.
///  - The drill: scan, go dark, scan again, show the delta.
///
/// Honest limit, also stated in the UI: nothing at the app
/// layer can hide the device from the access point it is
/// associated with. EMCON strips what identifies the device
/// and turns probing into an announcement by the prober.
class Emcon(
    private val context: Context,
    private val mouth: Mouth,
    private val serve: Serve,
    private val ble: BleMouth
) {
    data class Exposure(
        val host: String, val port: Int, val service: String,
        val banner: String, val confirmed: Boolean
    ) {
        val id: String get() = "$host:$port"
    }

    data class Announcer(
        val type: String, val label: String, val name: String,
        val why: String
    ) {
        val id: String get() = "$type|$name"
    }

    data class TripEvent(
        val id: String, val whenMs: Long, val source: String,
        val port: Int, val proto: String, val verdict: String,
        val byteCount: Int, val repeatCount: Int = 1,
        val bytesHex: String? = null
    )

    /// Exposure score with the weights that produced it.
    data class Score(val value: Int, val band: String,
                     val parts: List<Part>) {
        data class Part(val label: String, val points: Int) {
            val id: String get() = label
        }
        val raw: Int get() = parts.sumOf { it.points }
        val capped: Boolean get() = raw > value
    }

    data class Snapshot(
        val exposures: List<Exposure> = emptyList(),
        val announcers: List<Announcer> = emptyList()
    )

    data class Escalation(val persona: String, val port: Int,
                          val untilMs: Long)

    /// What a normal night at home sounds like, learned from
    /// the tripwire's own log.
    data class Hometurf(
        var nights: Int = 0,
        var sources: Set<String> = emptySet(),
        var ports: Set<Int> = emptySet(),
        var verdicts: Set<String> = emptySet(),
        var stagingDay: String = "",
        var stagedSources: Set<String> = emptySet(),
        var stagedPorts: Set<Int> = emptySet(),
        var stagedVerdicts: Set<String> = emptySet()
    )

    /// The canary, when the Serve side grows one: escalation
    /// hands a knocked port to the matching persona through
    /// this hook. Until then the hand-off simply has nowhere
    /// to land and the wire keeps the port.
    interface CanaryHook {
        val runningPersona: String?
        fun start(persona: String, port: Int,
                  honeydrop: Boolean, drop: String)
        fun stop()
    }

    var canary: CanaryHook? = null

    /// Every knock the funnel logs is also offered here —
    /// the Knocktalk sequence engine hangs off this hook.
    var knockSink: ((source: String, port: Int, proto: String,
                    verdict: String) -> Unit)? = null

    /// The dead hand's burn, once Knocktalk exists to burn.
    var burnHook: (() -> Unit)? = null

    /// Loading the bench on a knocked source: the conductor's
    /// pivotRecon. Loading is an action; firing stays a
    /// human press.
    var pivotSink: ((host: String, port: Int) -> Unit)? = null

    /// Fired when the knock vault opens — the conductor
    /// listens here, as on iOS.
    var vaultHook: ((Emcon) -> Unit)? = null

    /// The judgment layer's ears (conductor, steward), fed
    /// every knock after the sense checks, as on iOS.
    var conductorHook: ((emcon: Emcon, source: String, port: Int,
                         proto: String, verdict: String,
                         mine: Boolean) -> Unit)? = null
    var stewardHook: ((emcon: Emcon, source: String, port: Int,
                       proto: String, verdict: String,
                       mine: Boolean) -> Unit)? = null

    private val prefs = Prefs(context.applicationContext)
    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _active = MutableStateFlow(false)
    val active: StateFlow<Boolean> = _active
    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning
    private val _exposures = MutableStateFlow<List<Exposure>>(emptyList())
    val exposures: StateFlow<List<Exposure>> = _exposures
    private val _lastScanAt = MutableStateFlow<Long?>(null)
    val lastScanAt: StateFlow<Long?> = _lastScanAt
    private val _auditing = MutableStateFlow(false)
    val auditing: StateFlow<Boolean> = _auditing
    private val _announcers =
        MutableStateFlow<List<Announcer>>(emptyList())
    val announcers: StateFlow<List<Announcer>> = _announcers
    private val _heardCount = MutableStateFlow(0)
    val heardCount: StateFlow<Int> = _heardCount
    private val _lastAuditAt = MutableStateFlow<Long?>(null)
    val lastAuditAt: StateFlow<Long?> = _lastAuditAt
    private val _drilling = MutableStateFlow(false)
    val drilling: StateFlow<Boolean> = _drilling
    private val _drillBefore = MutableStateFlow<Snapshot?>(null)
    val drillBefore: StateFlow<Snapshot?> = _drillBefore
    private val _drillAfter = MutableStateFlow<Snapshot?>(null)
    val drillAfter: StateFlow<Snapshot?> = _drillAfter
    private val _tripwireOn = MutableStateFlow(false)
    val tripwireOn: StateFlow<Boolean> = _tripwireOn
    private val _watched = MutableStateFlow<List<Int>>(emptyList())
    val watched: StateFlow<List<Int>> = _watched
    private val _watchedUDP = MutableStateFlow<List<Int>>(emptyList())
    val watchedUDP: StateFlow<List<Int>> = _watchedUDP
    private val _unwatched = MutableStateFlow<List<Int>>(emptyList())
    val unwatched: StateFlow<List<Int>> = _unwatched
    private val _events = MutableStateFlow<List<TripEvent>>(emptyList())
    val events: StateFlow<List<TripEvent>> = _events

    /// Knock patterns the engine graded but could not open —
    /// the EMCON tab's knock-traffic section reads these.
    private val _knockPatterns =
        MutableStateFlow<List<KnockPattern>>(emptyList())
    val knockPatterns: StateFlow<List<KnockPattern>> = _knockPatterns

    fun noteKnockPattern(pattern: KnockPattern) {
        _knockPatterns.value =
            (listOf(pattern) + _knockPatterns.value).take(50)
    }

    /// Keeps the knock engine's vault combination in step
    /// with the operator's setting.
    var comboSink: ((List<String>) -> Unit)? = null
    private val _hometurf = MutableStateFlow(Hometurf())
    val hometurf: StateFlow<Hometurf> = _hometurf
    private val _hometurfNotes = MutableStateFlow<List<String>>(emptyList())
    val hometurfNotes: StateFlow<List<String>> = _hometurfNotes
    private val _senseUntil = MutableStateFlow<Long?>(null)
    val senseUntil: StateFlow<Long?> = _senseUntil
    private val _senseReason = MutableStateFlow("")
    val senseReason: StateFlow<String> = _senseReason
    private val _deadHandDown = MutableStateFlow(false)
    val deadHandDown: StateFlow<Boolean> = _deadHandDown
    private val _escalation = MutableStateFlow<Escalation?>(null)
    val escalation: StateFlow<Escalation?> = _escalation
    private val _vaultOpenUntil = MutableStateFlow<Long?>(null)
    val vaultOpenUntil: StateFlow<Long?> = _vaultOpenUntil
    private val _vaultCombo =
        MutableStateFlow(listOf("ssh", "tls", "mqtt"))
    val vaultCombo: StateFlow<List<String>> = _vaultCombo
    private val _vaultAction = MutableStateFlow("serve")
    val vaultAction: StateFlow<String> = _vaultAction

    private val tcpServers = mutableMapOf<Int, ServerSocket>()
    private val udpSockets = mutableMapOf<Int, DatagramSocket>()
    private var escalationJob: Job? = null
    private var escalationCooldown = mutableMapOf<Int, Long>()
    private var vaultJob: Job? = null
    private var vaultStartedServe = false
    private var vaultStartedCanary = false

    val deviceName: String
        get() = try {
            Settings.Global.getString(
                context.contentResolver, Settings.Global.DEVICE_NAME)
                ?: Build.MODEL ?: "Android"
        } catch (_: Exception) {
            Build.MODEL ?: "Android"
        }

    val ownIP: String? get() = mouth.localIPAddress()

    val homeSubnet: String?
        get() = prefs.string(HOME_KEY, "").ifBlank { null }

    init {
        _active.value = prefs.bool(ACTIVE_KEY, false)
        _events.value = loadEvents()
        _hometurf.value = loadHometurf()
        reloadVaultCombination()
        if (_events.value.isNotEmpty()) {
            writeReport(_events.value)
        }
    }

    companion object {
        private const val ACTIVE_KEY = "emconActive"
        private const val HOME_KEY = "emconHomeSubnet"
        private const val VAULT_COMBO_KEY = "emconVaultCombo"
        private const val VAULT_ACTION_KEY = "emconVaultAction"

        const val BURST_WINDOW_MS = 30_000L
        const val EVENT_CAP = 200

        /** 0 = ghost, 100 = a lighthouse. Computed from what
         * is true right now, not from intentions. */
        fun score(
            gattHostOn: Boolean, beaconOn: Boolean,
            serveRunning: Boolean, stealth: Boolean,
            deviceName: String, exposureCount: Int,
            announcerCount: Int
        ): Score {
            val parts = mutableListOf<Score.Part>()
            fun weigh(label: String, points: Int) {
                if (points > 0) parts.add(Score.Part(label, points))
            }
            if (gattHostOn) weigh("GATT host", 25)
            if (beaconOn) weigh("BLE beacon", 20)
            if (serveRunning) {
                weigh(
                    if (stealth) "Serve, stealth" else "Serve, listed",
                    if (stealth) 4 else 20
                )
            }
            if (deviceName.contains("'s ") ||
                deviceName.contains("’s ")) {
                weigh("Personal name", 12)
            } else if (deviceName != "Android" &&
                deviceName != Build.MODEL) {
                weigh("Broadcast name", 6)
            }
            if (exposureCount > 0) {
                val rawPoints = exposureCount * 4
                weigh(
                    "Recon hits ×$exposureCount" +
                        if (rawPoints > 20) ", capped" else "",
                    minOf(20, rawPoints)
                )
            }
            if (announcerCount > 0) {
                val rawPoints = announcerCount * 6
                weigh(
                    "Announcements ×$announcerCount" +
                        if (rawPoints > 18) ", capped" else "",
                    minOf(18, rawPoints)
                )
            }
            val rawTotal = parts.sumOf { it.points }
            val value = minOf(100, rawTotal)
            val band = when {
                value == 0 -> "GHOST"
                value <= 15 -> "DARK"
                value <= 40 -> "LIT"
                value <= 70 -> "LOUD"
                else -> "BEACONING"
            }
            return Score(value, band, parts)
        }

        /** First three octets of an IPv4 address. */
        fun subnet(of: String): String? {
            val parts = of.split(".")
            if (parts.size != 4) return null
            return parts.subList(0, 3).joinToString(".")
        }

        /** Away only when both sides are known and differ. */
        fun away(home: String?, here: String?): Boolean {
            if (home == null || here == null) return false
            return home != here
        }

        fun exposureLine(hit: Exposure): String =
            "${hit.host}:${hit.port} ${hit.service}"

        fun announcerLine(ad: Announcer): String =
            "${ad.label}: ${ad.name}"

        /** In the first snapshot, gone from the second. */
        fun silenced(before: Snapshot, after: Snapshot): List<String> {
            val afterPorts = after.exposures.map { it.id }.toSet()
            val afterAds = after.announcers.map { it.id }.toSet()
            return before.exposures
                .filter { it.id !in afterPorts }
                .map { exposureLine(it) } +
                before.announcers
                    .filter { it.id !in afterAds }
                    .map { announcerLine(it) }
        }

        /** Everything the second snapshot still shows. */
        fun stillShowing(after: Snapshot): List<String> =
            after.exposures.map { exposureLine(it) } +
                after.announcers.map { announcerLine(it) }

        /** Insert a knock, or fold it into a recent identical
         * row. Identical means same source, port, protocol,
         * and verdict; the window slides with the latest hit. */
        fun record(
            events: MutableList<TripEvent>, source: String,
            port: Int, proto: String, verdict: String,
            byteCount: Int, bytesHex: String? = null,
            nowMs: Long = System.currentTimeMillis()
        ) {
            val index = events.indexOfFirst { event ->
                event.source == source && event.port == port &&
                    event.proto == proto &&
                    event.verdict == verdict &&
                    nowMs - event.whenMs >= 0 &&
                    nowMs - event.whenMs < BURST_WINDOW_MS
            }
            if (index >= 0) {
                val hit = events.removeAt(index)
                events.add(
                    0, hit.copy(
                        repeatCount = hit.repeatCount + 1,
                        whenMs = nowMs, byteCount = byteCount,
                        bytesHex = bytesHex ?: hit.bytesHex
                    )
                )
                return
            }
            events.add(
                0, TripEvent(
                    id = java.util.UUID.randomUUID().toString(),
                    whenMs = nowMs, source = source, port = port,
                    proto = proto, verdict = verdict,
                    byteCount = byteCount, bytesHex = bytesHex
                )
            )
            while (events.size > EVENT_CAP) {
                events.removeAt(events.size - 1)
            }
        }

        /** Readable export. One block per row; a burst ×N. */
        fun tripwireReport(events: List<TripEvent>): String {
            val stamp = SimpleDateFormat(
                "yyyy-MM-dd HH:mm:ss", Locale.US)
            val lines = mutableListOf(
                "EMCON tripwire", "The tripwire never replies.", "")
            if (events.isEmpty()) {
                lines.add("Nobody has knocked.")
                return lines.joinToString("\n")
            }
            for (event in events) {
                val times = if (event.repeatCount > 1) {
                    " ×${event.repeatCount}"
                } else {
                    ""
                }
                lines.add(
                    "${stamp.format(Date(event.whenMs))}  " +
                        "${event.source} → ${event.proto}/" +
                        "${event.port}$times"
                )
                lines.add("  ${event.verdict}")
            }
            return lines.joinToString("\n")
        }

        // MARK: - fingerprinting

        private data class Signature(
            val name: String, val port: Int, val udp: Boolean,
            val bytes: ByteArray
        )

        private val signatures: List<Signature> by lazy {
            ReconPayloads.all.values.map {
                Signature(it.name, it.port, it.udp, it.build())
            }
        }

        private fun fits(sig: Signature, port: Int, udp: Boolean) =
            sig.port == port && sig.udp == udp

        private fun ByteArray.startsWith(prefix: ByteArray): Boolean {
            if (prefix.size > size) return false
            for (i in prefix.indices) if (this[i] != prefix[i]) {
                return false
            }
            return true
        }

        /** Best library probe for these bytes: a full signature
         * inside the payload, or a partial send that is a
         * prefix of one. A full match beats an equal-length
         * partial; the probe aimed at this port wins ties,
         * then the name. */
        private fun bestSignature(
            data: ByteArray, port: Int, udp: Boolean
        ): Signature? {
            if (data.size < 3) return null
            var best: Signature? = null
            var bestOverlap = -1
            var bestFull = false
            for (sig in signatures) {
                if (sig.bytes.size < 3) continue
                val full = data.startsWith(sig.bytes)
                val partial = sig.bytes.startsWith(data)
                if (!full && !partial) continue
                val overlap = if (full) sig.bytes.size else data.size
                val take = when {
                    best == null -> true
                    overlap != bestOverlap -> overlap > bestOverlap
                    full != bestFull -> full
                    fits(sig, port, udp) !=
                        fits(best!!, port, udp) ->
                        fits(sig, port, udp)
                    else -> sig.name < best!!.name
                }
                if (take) {
                    best = sig
                    bestOverlap = overlap
                    bestFull = full
                }
            }
            return best
        }

        private fun verdict(
            forSig: Signature, port: Int, udp: Boolean
        ): String {
            var text = "nightjar-hack probe: ${forSig.name}"
            if (forSig.port != port) {
                text += " (on the wrong port)"
            } else if (forSig.udp != udp) {
                text += " (a ${if (forSig.udp) "UDP" else "TCP"}" +
                    " probe over ${if (udp) "UDP" else "TCP"})"
            }
            return text
        }

        /** Empty bytes are a silent knock. Anything else is
         * fingerprinted. */
        fun tripVerdict(bytes: ByteArray, port: Int, udp: Boolean): String {
            if (bytes.isEmpty()) return "silent knock (no bytes sent)"
            return fingerprint(bytes, port, udp)
        }

        fun fingerprint(data: ByteArray, port: Int, udp: Boolean): String {
            if (data.isEmpty()) return "empty connection"
            bestSignature(data, port, udp)?.let {
                return verdict(it, port, udp)
            }
            if (data.size >= 2 && data[0] == 0x16.toByte() &&
                data[1] == 0x03.toByte()) {
                return "TLS ClientHello — a TLS scanner or client knocked"
            }
            if (data.startsWith("SSH-2.0-".toByteArray())) {
                return "SSH client banner: " +
                    ReconPayloads.firstLine(data, 60)
            }
            for (verb in listOf(
                "GET ", "POST ", "HEAD ", "PUT ", "DELETE ",
                "OPTIONS ", "CONNECT ")) {
                if (data.startsWith(verb.toByteArray())) {
                    return "HTTP request: " +
                        ReconPayloads.firstLine(data, 60)
                }
            }
            val text = String(data, Charsets.UTF_8)
            val printable = text.split("\n", "\r").any { line ->
                val trimmed = line.trim()
                trimmed.isNotEmpty() && trimmed.none {
                    it.code < 0x20 || it.code in 0x7F..0x9F
                }
            }
            val line = ReconPayloads.firstLine(data, 60)
            return if (printable) {
                "unrecognized probe: $line"
            } else {
                "unrecognized bytes (${data.size}): $line"
            }
        }

        fun persona(forVerdict: String): String? {
            val text = forVerdict.lowercase()
            if (text.contains("ssh")) return "ssh"
            if (text.contains("mqtt")) return "mqtt"
            if (text.contains("smtp")) return "smtp"
            if (text.contains("http")) return "http"
            return null
        }

        val auditTypes: List<Pair<String, String>> =
            ScanKit.bonjourTypes + listOf(
                "_raop._tcp" to "AirPlay audio",
                "_companion-link._tcp" to "Companion Link",
                "_rdlink._tcp" to "Rapport",
                "_sleep-proxy._udp" to "Sleep proxy",
                "_airdrop._tcp" to "AirDrop"
            )

        // MARK: - the vault's shape

        val vaultActions = listOf("serve", "emcon", "burn", "canary")

        fun vaultActionLabel(action: String): String = when (action) {
            "emcon" -> "Raise EMCON"
            "burn" -> "Burn Knocktalk threads now"
            "canary" -> "Raise the canary (60 s)"
            else -> "Open hidden Serve (60 s)"
        }

        val deadHandHoursOptions = listOf(12, 24, 72, 168)
    }

    // MARK: - home turf

    val currentSubnet: String?
        get() = ownIP?.let { subnet(it) }

    val isAway: Boolean get() = away(homeSubnet, currentSubnet)

    val hometurfReady: Boolean get() = _hometurf.value.nights >= 3

    fun markHome() {
        val here = currentSubnet ?: return
        prefs.put(HOME_KEY, here)
    }

    fun unmarkHome() {
        prefs.put(HOME_KEY, "")
    }

    // MARK: - posture

    /** Serve's settings, as the Serve tab stores them. */
    private fun startServeFromSettings(stealth: Boolean) {
        serve.start(
            prefs.string("serveTcpPort", "9000").toIntOrNull() ?: 0,
            prefs.string("serveUdpPort", "9001").toIntOrNull() ?: 0,
            prefs.string("serveHttpPort", "8080").toIntOrNull() ?: 0,
            prefs.string("serveReplyMode", "static"),
            prefs.string("serveReplyText", "ack"),
            stealth
        )
    }

    private var serveJob: Job? = null

    /** The conductor's raiseServe reflex: Serve up for sixty
     * seconds, then back down — only if the reflex raised
     * it. Returns the journal detail line. */
    fun raiseServeTimed(): String {
        if (serve.running.value) return "Serve was already up"
        startServeFromSettings(prefs.bool("serveStealth", false))
        if (!serve.running.value) {
            return "Serve would not rise — the line alone"
        }
        serveJob?.cancel()
        serveJob = scope.launch {
            delay(60_000)
            if (serve.running.value) serve.stop()
        }
        return "Serve raised for sixty seconds"
    }

    /** Force Serve stealth: the pref, the live flag, and —
     * if Serve is running — a restart so the NSD listing
     * follows the posture, the way the iOS mouth restarts
     * its listeners on the toggle. */
    fun setStealth(on: Boolean) {
        prefs.put("serveStealth", on)
        serve.stealthNow = on
        if (serve.running.value) startServeFromSettings(on)
    }

    /** Go dark: silence every emission the app controls and
     * arm the tripwire. */
    fun activate() {
        _active.value = true
        prefs.put(ACTIVE_KEY, true)
        setStealth(true)
        if (ble.hosting.value) ble.stopHosting()
        if (ble.beaconOn.value) ble.stopBeacon()
        startTripwire()
        Journal.log(
            "emcon", "posture",
            "EMCON active — emissions silenced, tripwire armed")
    }

    /** Stand down the tripwire. Stealth, the GATT host and
     * the beacon are left exactly as they are. */
    fun deactivate() {
        _active.value = false
        prefs.put(ACTIVE_KEY, false)
        stopTripwire()
        Journal.log("emcon", "posture", "EMCON stood down")
    }

    /** On tab appearance after a relaunch: reconcile with the
     * persisted flag in BOTH directions, and re-arm the
     * tripwire so the posture survives restarts. */
    fun restoreIfNeeded() {
        reloadVaultCombination()
        val persisted = prefs.bool(ACTIVE_KEY, false)
        if (persisted && !_active.value) _active.value = true
        if (!persisted && _active.value) {
            _active.value = false
            stopTripwire()
            return
        }
        if (_active.value && !_tripwireOn.value) startTripwire()
    }

    // MARK: - self-recon

    /// Knock this device on every port in Recon's registry,
    /// over loopback and the LAN address, speaking each port's
    /// own probe. The tripwire stands down for the duration —
    /// armed, it would answer on every probed port and the
    /// scan would report the tripwire itself (the iOS field
    /// saga: 141 phantom hits) — and waits for the released
    /// sockets to really die before knocking.
    fun runSelfScan(completion: (() -> Unit)? = null) {
        if (_scanning.value) {
            completion?.invoke()
            return
        }
        val resumeTripwire = _tripwireOn.value
        val releasedPorts = _watched.value
        if (resumeTripwire) stopTripwire()
        scope.launch {
            if (resumeTripwire && releasedPorts.isNotEmpty()) {
                awaitRelease(releasedPorts)
            }
            performSelfScan(resumeTripwire, completion)
        }
    }

    /// Poll-bind a canary — the last watched port — until the
    /// old listener's socket is really gone, with a 0.3 s
    /// floor. A scan fired immediately re-measures the dying
    /// listeners; the first semaphore wave would report as
    /// open on loopback, where connects complete instantly.
    private fun awaitRelease(ports: List<Int>) {
        val canary = ports.lastOrNull() ?: return
        val entered = System.currentTimeMillis()
        var attempts = 40
        while (attempts > 0) {
            try {
                ServerSocket(canary).close()
                break
            } catch (_: Exception) {
                attempts -= 1
                Thread.sleep(60)
            }
        }
        val waited = System.currentTimeMillis() - entered
        if (waited < 300) Thread.sleep(300 - waited)
    }

    private suspend fun performSelfScan(
        resumeTripwire: Boolean, completion: (() -> Unit)?
    ) {
        _scanning.value = true
        _exposures.value = emptyList()
        val hosts = mutableListOf("127.0.0.1")
        ownIP?.let { if (it != "127.0.0.1") hosts.add(it) }
        val ports = ReconPayloads.defaultPorts
        val semaphore = Semaphore(24)
        val found = hosts.flatMap { host ->
            ports.map { port ->
                scope.async {
                    semaphore.withPermit {
                        probeSelf(host, port)
                    }
                }
            }
        }.awaitAll().filterNotNull()
        _exposures.value = found.sortedWith(
            compareBy({ it.host }, { it.port }))
        _lastScanAt.value = System.currentTimeMillis()
        _scanning.value = false
        if (resumeTripwire) startTripwire()
        completion?.invoke()
    }

    /// One connect + probe + banner read at a shorter fuse.
    private fun probeSelf(host: String, port: Int): Exposure? {
        val probe = ReconPayloads.probe(port, udp = false)
        val socket = Socket()
        try {
            socket.connect(InetSocketAddress(host, port), 900)
        } catch (_: Exception) {
            try { socket.close() } catch (_: Exception) {}
            return null
        }
        try {
            if (probe == null) {
                return Exposure(host, port, "open", "", false)
            }
            val payload = probe.build()
            if (payload.isNotEmpty()) {
                socket.getOutputStream().write(payload)
                socket.getOutputStream().flush()
            }
            socket.soTimeout = 1200
            val reply = ByteArrayOutputStream()
            val buffer = ByteArray(4096)
            try {
                while (reply.size() < 4096) {
                    val read = socket.getInputStream().read(buffer)
                    if (read < 0) break
                    reply.write(buffer, 0, read)
                }
            } catch (_: Exception) {
                // The read fuse: whatever arrived stands.
            }
            val bytes = reply.toByteArray()
            val confirmed = if (probe.hint.isEmpty()) {
                bytes.isNotEmpty()
            } else {
                containsBytes(bytes, probe.hint)
            }
            return Exposure(
                host, port, probe.name,
                ReconPayloads.firstLine(bytes, 80), confirmed)
        } catch (_: Exception) {
            return Exposure(host, port, probe?.name ?: "open", "", false)
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun containsBytes(
        haystack: ByteArray, needle: ByteArray
    ): Boolean {
        if (needle.isEmpty() || needle.size > haystack.size) {
            return false
        }
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

    // MARK: - announcement audit

    private data class Heard(
        val type: String, val label: String, val name: String,
        val info: NsdServiceInfo
    )

    /// Browse the LAN for three seconds, then decide which of
    /// the announcers is this device: the announcement carries
    /// the device's name, or the service resolves to this
    /// phone's address.
    fun runBonjourAudit(completion: (() -> Unit)? = null) {
        if (_auditing.value) {
            completion?.invoke()
            return
        }
        _auditing.value = true
        _announcers.value = emptyList()
        scope.launch {
            val heard = sweepAnnouncements(3000)
            _heardCount.value = heard.size
            val name = deviceName.lowercase()
            val mine = mutableListOf<Announcer>()
            for (item in heard.take(40)) {
                val lowered = item.name.lowercase()
                val nameHit = lowered == name || lowered.contains(name)
                val ip = resolveIP(item.info)
                val ipHit = ip != null && ip == ownIP
                if (nameHit || ipHit) {
                    mine.add(
                        Announcer(
                            item.type, item.label, item.name,
                            if (nameHit) {
                                "announced under this device's name"
                            } else {
                                "resolves to this phone's address"
                            }))
                }
            }
            _announcers.value = mine.sortedWith(
                compareBy({ it.label }, { it.name }))
            _lastAuditAt.value = System.currentTimeMillis()
            _auditing.value = false
            completion?.invoke()
        }
    }

    private suspend fun sweepAnnouncements(
        millis: Long
    ): List<Heard> {
        val nsd = context.getSystemService(Context.NSD_SERVICE)
            as NsdManager
        val heard = mutableListOf<Heard>()
        val lock = Any()
        val listeners = mutableListOf<NsdManager.DiscoveryListener>()
        for ((type, label) in auditTypes) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onServiceFound(info: NsdServiceInfo) {
                    synchronized(lock) {
                        heard.removeAll {
                            it.type == type &&
                                it.name == info.serviceName
                        }
                        heard.add(
                            Heard(type, label,
                                info.serviceName ?: "", info))
                    }
                }
                override fun onServiceLost(info: NsdServiceInfo) {
                    synchronized(lock) {
                        heard.removeAll {
                            it.type == type &&
                                it.name == info.serviceName
                        }
                    }
                }
                override fun onDiscoveryStarted(t: String) {}
                override fun onDiscoveryStopped(t: String) {}
                override fun onStartDiscoveryFailed(
                    t: String, code: Int) {}
                override fun onStopDiscoveryFailed(
                    t: String, code: Int) {}
            }
            try {
                nsd.discoverServices(
                    type, NsdManager.PROTOCOL_DNS_SD, listener)
                listeners.add(listener)
            } catch (_: Exception) {
                // One type failing must not sink the audit.
            }
        }
        delay(millis)
        for (listener in listeners) {
            try { nsd.stopServiceDiscovery(listener) }
            catch (_: Exception) {}
        }
        return synchronized(lock) { heard.toList() }
    }

    private suspend fun resolveIP(info: NsdServiceInfo): String? =
        suspendCancellableCoroutine { continuation ->
            val nsd = context.getSystemService(Context.NSD_SERVICE)
                as NsdManager
            val done = AtomicBoolean(false)
            val listener = object : NsdManager.ResolveListener {
                override fun onServiceResolved(
                    resolved: NsdServiceInfo) {
                    if (done.compareAndSet(false, true)) {
                        continuation.resume(
                            resolved.host?.hostAddress)
                    }
                }
                override fun onResolveFailed(
                    failed: NsdServiceInfo, code: Int) {
                    if (done.compareAndSet(false, true)) {
                        continuation.resume(null)
                    }
                }
            }
            try {
                @Suppress("DEPRECATION")
                nsd.resolveService(info, listener)
            } catch (_: Exception) {
                if (done.compareAndSet(false, true)) {
                    continuation.resume(null)
                }
            }
            scope.launch {
                delay(1000)
                if (done.compareAndSet(false, true)) {
                    continuation.resume(null)
                }
            }
        }

    // MARK: - the drill

    /** Scan and audit, go dark, scan and audit again. */
    fun runDrill() {
        if (_drilling.value || _scanning.value || _auditing.value) {
            return
        }
        _drilling.value = true
        _drillBefore.value = null
        _drillAfter.value = null
        runSelfScan {
            runBonjourAudit {
                _drillBefore.value = Snapshot(
                    _exposures.value, _announcers.value)
                activate()
                scope.launch {
                    delay(800)
                    runSelfScan {
                        runBonjourAudit {
                            _drillAfter.value = Snapshot(
                                _exposures.value, _announcers.value)
                            _drilling.value = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - tripwire

    /** First caller logs the knock. The receive path and the
     * silent-knock timer both try; the second is dropped. */
    class TripOnce {
        private val settled = AtomicBoolean(false)
        val isSettled: Boolean get() = settled.get()
        fun claim(): Boolean = settled.compareAndSet(false, true)
    }

    /** Bind silent listeners on the probe registry's ports —
     * TCP and UDP. Ports already in use (Serve, the OS) are
     * reported as unwatched rather than fought over. */
    fun startTripwire() {
        if (_tripwireOn.value) return
        val bound = mutableListOf<Int>()
        val boundUDP = mutableListOf<Int>()
        val failed = mutableListOf<Int>()
        for (port in ReconPayloads.defaultPorts) {
            if (bindTcp(port)) bound.add(port) else failed.add(port)
        }
        for (port in ReconPayloads.udpPortMap.keys.sorted()) {
            if (bindUdp(port)) boundUDP.add(port) else failed.add(port)
        }
        _watched.value = bound
        _watchedUDP.value = boundUDP
        _unwatched.value = failed
        _tripwireOn.value = true
    }

    private fun bindTcp(port: Int): Boolean {
        val server = try {
            ServerSocket(port)
        } catch (_: Exception) {
            return false
        }
        tcpServers[port] = server
        scope.launch {
            while (!server.isClosed) {
                val socket = try {
                    server.accept()
                } catch (_: Exception) {
                    break
                }
                handleTcpKnock(socket, port)
            }
        }
        return true
    }

    private fun bindUdp(port: Int): Boolean {
        val socket = try {
            DatagramSocket(port)
        } catch (_: Exception) {
            return false
        }
        udpSockets[port] = socket
        scope.launch {
            val buffer = ByteArray(1024)
            while (!socket.isClosed) {
                val packet = DatagramPacket(buffer, buffer.size)
                try {
                    socket.receive(packet)
                } catch (_: Exception) {
                    break
                }
                val source = packet.address?.hostAddress ?: "unknown"
                val bytes = packet.data.copyOf(packet.length)
                val once = TripOnce()
                finishTrip(once, source, port, udp = true, bytes)
            }
        }
        return true
    }

    private fun handleTcpKnock(socket: Socket, port: Int) {
        val source = socket.inetAddress?.hostAddress ?: "unknown"
        val once = TripOnce()
        scope.launch {
            var bytes = ByteArray(0)
            try {
                socket.soTimeout = 3000
                val buffer = ByteArray(1024)
                val read = socket.getInputStream().read(buffer)
                if (read > 0) bytes = buffer.copyOf(read)
            } catch (_: Exception) {
                // The grace timer ran out with nothing said —
                // a silent knock (or a reset peer). Bytes that
                // did arrive were already claimed above.
            } finally {
                try { socket.close() } catch (_: Exception) {}
            }
            finishTrip(once, source, port, udp = false, bytes)
        }
    }

    fun stopTripwire() {
        for ((_, server) in tcpServers) {
            try { server.close() } catch (_: Exception) {}
        }
        tcpServers.clear()
        for ((_, socket) in udpSockets) {
            try { socket.close() } catch (_: Exception) {}
        }
        udpSockets.clear()
        _watched.value = emptyList()
        _watchedUDP.value = emptyList()
        _unwatched.value = emptyList()
        _tripwireOn.value = false
    }

    /** Give one TCP port up (the canary is taking it), or
     * take it back (the escalation ended). */
    private fun releasePort(port: Int) {
        tcpServers.remove(port)?.let {
            try { it.close() } catch (_: Exception) {}
        }
        _watched.value = _watched.value - port
    }

    private fun rebindPort(port: Int) {
        if (!_tripwireOn.value || port in _watched.value) return
        if (bindTcp(port)) {
            _watched.value = (_watched.value + port).sorted()
        }
    }

    fun clearEvents() {
        _events.value = emptyList()
        saveEvents()
    }

    private fun finishTrip(
        once: TripOnce, source: String, port: Int,
        udp: Boolean, bytes: ByteArray
    ) {
        if (!once.claim()) return
        val verdict = tripVerdict(bytes, port, udp)
        logEvent(
            source, port, if (udp) "UDP" else "TCP",
            verdict, bytes.size, bytes)
    }

    /** The one funnel every knock passes through: the log,
     * the journal, and every sense the perimeter keeps. */
    private fun logEvent(
        source: String, port: Int, proto: String,
        verdict: String, byteCount: Int, bytes: ByteArray?
    ) {
        val mine = ownIP != null && source.contains(ownIP!!)
        val labeled = if (mine) "$source (this device)" else source
        val current = _events.value.toMutableList()
        record(
            current, labeled, port, proto, verdict, byteCount,
            bytes?.let { hexOf(it) })
        _events.value = current
        saveEvents()
        Journal.log(
            "emcon", "knock", "$labeled → $proto/$port — $verdict")
        knockSink?.invoke(labeled, port, proto, verdict)
        maybeEscalate(labeled, port, proto, verdict, mine)
        hometurfObserve(labeled, port, verdict, mine)
        senseObserve(labeled, port, proto, verdict, mine)
        conductorHook?.invoke(this, labeled, port, proto, verdict, mine)
        stewardHook?.invoke(this, labeled, port, proto, verdict, mine)
    }

    private fun hexOf(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    // MARK: - home-turf memory

    private fun hometurfObserve(
        source: String, port: Int, verdict: String, mine: Boolean
    ) {
        if (!_active.value || mine || homeSubnet == null || isAway) {
            return
        }
        val turf = _hometurf.value
        val host = source.split(" ").firstOrNull() ?: source
        val today = dayString(System.currentTimeMillis())
        var nights = turf.nights
        var sources = turf.sources
        var ports = turf.ports
        var verdicts = turf.verdicts
        var stagedSources = turf.stagedSources
        var stagedPorts = turf.stagedPorts
        var stagedVerdicts = turf.stagedVerdicts
        if (turf.stagingDay != today) {
            if (turf.stagingDay.isNotEmpty() &&
                (stagedSources.isNotEmpty() ||
                    stagedPorts.isNotEmpty())) {
                sources = sources + stagedSources
                ports = ports + stagedPorts
                verdicts = verdicts + stagedVerdicts
                nights += 1
                Journal.log(
                    "emcon", "hometurf",
                    "night $nights banked into the home pattern")
            }
            stagedSources = emptySet()
            stagedPorts = emptySet()
            stagedVerdicts = emptySet()
        }
        val ready = nights >= 3
        if (ready) {
            val notes = mutableListOf<String>()
            if (host !in sources && host !in stagedSources) {
                notes.add("a new source knocked: $host")
            }
            if (port !in ports && port !in stagedPorts) {
                notes.add("a new door tried: port $port")
            }
            if (verdict !in verdicts && verdict !in stagedVerdicts) {
                notes.add("a new first word: $verdict")
            }
            for (note in notes) {
                if (Dismissals.isDismissed(prefs, note)) continue
                val list = _hometurfNotes.value + note
                _hometurfNotes.value = if (list.size > 20) {
                    list.takeLast(20)
                } else {
                    list
                }
                Journal.log(
                    "emcon", "hometurf",
                    "off the learned pattern — $note")
            }
        }
        stagedSources = stagedSources + host
        stagedPorts = stagedPorts + port
        stagedVerdicts = stagedVerdicts + verdict
        _hometurf.value = Hometurf(
            nights, sources, ports, verdicts, today,
            stagedSources, stagedPorts, stagedVerdicts)
        saveHometurf()
    }

    /** The operator dismisses a deviation: it leaves tonight's
     * list, and the dismissal is recorded so the pattern
     * stops flagging this exact novelty. */
    fun hometurfDismiss(note: String) {
        _hometurfNotes.value = _hometurfNotes.value - note
        Dismissals.add(prefs, note)
    }

    fun hometurfReset() {
        _hometurf.value = Hometurf()
        _hometurfNotes.value = emptyList()
        saveHometurf()
        Journal.log(
            "emcon", "hometurf",
            "the home pattern was forgotten — learning starts over")
    }

    private fun dayString(whenMs: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(whenMs))

    // MARK: - second sense

    val senseActive: Boolean
        get() = _senseUntil.value?.let {
            it > System.currentTimeMillis()
        } ?: false

    fun raiseSense(reason: String) {
        val wasActive = senseActive
        _senseUntil.value =
            System.currentTimeMillis() + 30 * 60 * 1000
        _senseReason.value = reason
        if (!wasActive) {
            Journal.log(
                "emcon", "sense",
                "second sense raised for 30 minutes — " + reason +
                    ". Answer in character is armed while it lasts.")
        }
    }

    fun senseStandDown() {
        if (!senseActive) return
        _senseUntil.value = null
        _senseReason.value = ""
        Journal.log(
            "emcon", "sense",
            "second sense stood down by the operator")
    }

    private fun senseObserve(
        source: String, port: Int, proto: String,
        verdict: String, mine: Boolean
    ) {
        if (mine || proto != "TCP") return
        if (!verdict.startsWith("nightjar-hack probe:")) return
        raiseSense(
            "a foreign nightjar-grade probe ($verdict) from $source")
    }

    // MARK: - escalation (answer in character)

    val escalationArmed: Boolean
        get() = prefs.bool("emconEscalation", false)

    /** The steward's anticipation and the conductor's road
     * into the same hand-off an answer uses. */
    fun prestageCanary(port: Int, persona: String, source: String) {
        val hook = canary ?: return
        if (!_tripwireOn.value || _escalation.value != null ||
            hook.runningPersona != null) {
            return
        }
        escalationCooldown[port]?.let {
            if (it > System.currentTimeMillis()) return
        }
        handOff(
            port, persona,
            "the steward pre-staged the $persona canary on " +
                "$port — $source's own sequence points there; " +
                "it answers for 10 minutes",
            "the pre-stage hand-off failed — port $port " +
                "stays on the wire")
    }

    fun escalateNow(source: String, port: Int, verdict: String) {
        maybeEscalate(source, port, "TCP", verdict, mine = false,
            forced = true)
    }

    private fun maybeEscalate(
        source: String, port: Int, proto: String,
        verdict: String, mine: Boolean, forced: Boolean = false
    ) {
        val hook = canary ?: return
        if (!(escalationArmed || senseActive || forced)) return
        if (proto != "TCP" || mine || !_tripwireOn.value) return
        if (_escalation.value != null) return
        if (hook.runningPersona != null) return
        val persona = persona(forVerdict = verdict) ?: return
        escalationCooldown[port]?.let {
            if (it > System.currentTimeMillis()) return
        }
        handOff(
            port, persona,
            "$persona knock from $source on $port — answered " +
                "in character for 10 minutes",
            "the hand-off to the canary failed — port $port " +
                "stays on the wire")
    }

    /** Release the port, raise the canary, hold ten minutes.
     * Listener teardown is asynchronous (the self-scan saga
     * taught that): check the bind landed, retry once, and
     * if the port still won't take, give it back rather than
     * leave it unwatched under a false flag. */
    private fun handOff(
        port: Int, persona: String, logLine: String, failLine: String
    ) {
        val hook = canary ?: return
        releasePort(port)
        fun raiseCanary() {
            hook.start(
                persona, port,
                honeydrop = prefs.bool("canaryHoneydrop", false),
                drop = prefs.string("canaryDrop", ""))
        }
        raiseCanary()
        _escalation.value = Escalation(
            persona, port, System.currentTimeMillis() + 600_000)
        escalationJob?.cancel()
        escalationJob = scope.launch {
            delay(600_000)
            endEscalation()
        }
        Journal.log("emcon", "escalation", logLine)
        scope.launch {
            delay(1200)
            if (_escalation.value == null ||
                hook.runningPersona != null) {
                return@launch
            }
            raiseCanary()
            delay(1200)
            if (_escalation.value == null ||
                hook.runningPersona != null) {
                return@launch
            }
            Journal.log("emcon", "escalation", failLine)
            endEscalation()
        }
    }

    fun endEscalation() {
        escalationJob?.cancel()
        escalationJob = null
        val current = _escalation.value ?: return
        _escalation.value = null
        escalationCooldown[current.port] =
            System.currentTimeMillis() + 1_800_000
        canary?.let {
            if (it.runningPersona == current.persona) it.stop()
        }
        rebindPort(current.port)
        Journal.log(
            "emcon", "escalation",
            "escalation over — tripwire re-armed on ${current.port}")
    }

    // MARK: - the knock vault

    fun reloadVaultCombination() {
        val stored = prefs.string(VAULT_COMBO_KEY, "")
            .split(",").map { it.trim() }.filter { it.isNotEmpty() }
        _vaultCombo.value = if (stored.size == 3) {
            stored
        } else {
            listOf("ssh", "tls", "mqtt")
        }
        comboSink?.invoke(_vaultCombo.value)
        reloadVaultAction()
    }

    fun setVaultDigit(index: Int, digit: String) {
        val combo = _vaultCombo.value.toMutableList()
        if (index !in combo.indices) return
        combo[index] = digit
        prefs.put(VAULT_COMBO_KEY, combo.joinToString(","))
        reloadVaultCombination()
    }

    fun reloadVaultAction() {
        val stored = prefs.string(VAULT_ACTION_KEY, "serve")
        _vaultAction.value = if (stored in vaultActions) {
            stored
        } else {
            "serve"
        }
    }

    fun setVaultAction(action: String) {
        prefs.put(VAULT_ACTION_KEY, action)
        reloadVaultAction()
    }

    /** The combination was spoken: fire the chosen macro.
     * Timed macros ride the vault's sixty seconds and are
     * stood back down at the seal — and only if the vault
     * itself raised them. */
    fun openVault(source: String) {
        if (_vaultOpenUntil.value != null) return
        _vaultOpenUntil.value = System.currentTimeMillis() + 60_000
        vaultJob?.cancel()
        vaultJob = scope.launch {
            delay(60_000)
            sealVault()
        }
        var detail = ""
        when (_vaultAction.value) {
            "emcon" -> {
                if (!_active.value) {
                    activate()
                    detail = " — EMCON raised"
                } else {
                    detail = " — EMCON already up"
                }
            }
            "burn" -> {
                burnHook?.invoke()
                detail = " — Knocktalk threads burned"
            }
            "canary" -> {
                val hook = canary
                if (hook != null && hook.runningPersona == null) {
                    val persona = prefs.string("canaryPersona", "ssh")
                    val port = prefs.string("canaryPort", "")
                        .toIntOrNull() ?: 0
                    hook.start(
                        persona, port,
                        honeydrop = prefs.bool("canaryHoneydrop", false),
                        drop = prefs.string("canaryDrop", ""))
                    vaultStartedCanary = true
                    detail = " — canary raised for the window"
                } else {
                    detail = " — canary already up"
                }
            }
            else -> {
                if (!serve.running.value) {
                    startServeFromSettings(
                        prefs.bool("serveStealth", false))
                    vaultStartedServe = serve.running.value
                    detail = if (vaultStartedServe) {
                        " — hidden Serve raised"
                    } else {
                        ""
                    }
                }
            }
        }
        Journal.log(
            "emcon", "vault",
            "combination spoken by $source — macro: " +
                vaultActionLabel(_vaultAction.value) + detail)
        vaultHook?.invoke(this)
    }

    fun sealVault() {
        vaultJob?.cancel()
        vaultJob = null
        if (_vaultOpenUntil.value == null) return
        _vaultOpenUntil.value = null
        if (vaultStartedServe && serve.running.value) serve.stop()
        vaultStartedServe = false
        if (vaultStartedCanary) canary?.stop()
        vaultStartedCanary = false
        Journal.log("emcon", "vault", "vault sealed")
    }

    // MARK: - dead hand

    /** The dead hand. Arm it, then check in deliberately
     * before the interval runs out. If the app is next
     * opened with the check-in overdue, the hand falls: the
     * Knocktalk threads burn and EMCON rises. Android gives
     * a third-party app no background timer it can fully
     * trust either, so the hand falls at the next OPENING,
     * not at the deadline itself — two reminder alarms are
     * scheduled as courtesies. Only the deliberate check-in
     * resets the clock. */
    private val deadHandOn: Boolean
        get() = prefs.bool("deadHand.on", false)

    private val deadHandIntervalMs: Long
        get() {
            val hours = prefs.int("deadHand.hours", 24)
            return (if (hours > 0) hours else 24) * 3600_000L
        }

    private val deadHandLastMs: Long?
        get() = prefs.string("deadHand.last", "0")
            .toLongOrNull()?.takeIf { it > 0 }

    val deadHandDeadlineMs: Long?
        get() = deadHandLastMs?.plus(deadHandIntervalMs)

    val deadHandOverdue: Boolean
        get() {
            if (!deadHandOn) return false
            val deadline = deadHandDeadlineMs ?: return false
            return System.currentTimeMillis() > deadline
        }

    val deadHandHasFallen: Boolean
        get() = _deadHandDown.value ||
            (prefs.string("deadHand.firedAt", "0")
                .toLongOrNull() ?: 0) > 0

    /** Arming counts as the first check-in. */
    fun deadHandArm() {
        prefs.put(
            "deadHand.last",
            System.currentTimeMillis().toString())
        prefs.put("deadHand.firedAt", "0")
        _deadHandDown.value = false
        deadHandScheduleReminders()
        Journal.log(
            "emcon", "deadhand",
            "dead hand armed — check in within " +
                "${deadHandIntervalMs / 3600_000} h, or the " +
                "next opening burns and goes dark")
    }

    fun deadHandDisarm() {
        deadHandCancelReminders()
    }

    /** The deliberate check-in: the ONLY thing that resets
     * the clock. */
    fun deadHandCheckIn() {
        prefs.put(
            "deadHand.last",
            System.currentTimeMillis().toString())
        prefs.put("deadHand.firedAt", "0")
        _deadHandDown.value = false
        deadHandScheduleReminders()
    }

    /** Changing the interval re-times the reminders; the
     * clock itself is untouched. */
    fun deadHandReschedule() {
        deadHandScheduleReminders()
    }

    /** Launch and every foreground. Fires once per overdue
     * period; a check-in re-arms the trigger. */
    fun deadHandEvaluate() {
        if (!deadHandOn || _deadHandDown.value) return
        if ((prefs.string("deadHand.firedAt", "0")
                .toLongOrNull() ?: 0) > 0) return
        if (!deadHandOverdue) return
        val deadline = deadHandDeadlineMs ?: return
        prefs.put(
            "deadHand.firedAt",
            System.currentTimeMillis().toString())
        _deadHandDown.value = true
        burnHook?.invoke()
        activate()
        val overdueH = (System.currentTimeMillis() - deadline) /
            3600_000
        Journal.log(
            "emcon", "deadhand",
            "DEAD HAND FELL — check-in overdue " +
                "($overdueH h past the deadline). Knocktalk " +
                "threads burned; EMCON raised.")
    }

    private fun deadHandScheduleReminders() {
        val manager = context.getSystemService(
            Context.ALARM_SERVICE) as AlarmManager
        deadHandCancelReminders()
        val deadline = deadHandDeadlineMs ?: return
        fun schedule(id: Int, atMs: Long, body: String) {
            if (atMs - System.currentTimeMillis() <= 60_000) return
            val intent = Intent(context, DeadHandReceiver::class.java)
                .putExtra(DeadHandReceiver.EXTRA_BODY, body)
            val pending = PendingIntent.getBroadcast(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE)
            manager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, atMs, pending)
        }
        schedule(
            4101, deadline - 2 * 3600_000,
            "Check-in due in about two hours. Miss it, and " +
                "the next opening burns the Knocktalk threads " +
                "and raises EMCON.")
        schedule(
            4102, deadline,
            "Check-in overdue. The hand falls at the next opening.")
    }

    private fun deadHandCancelReminders() {
        val manager = context.getSystemService(
            Context.ALARM_SERVICE) as AlarmManager
        for (id in listOf(4101, 4102)) {
            val intent = Intent(context, DeadHandReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE)
            manager.cancel(pending)
        }
    }

    // MARK: - persistence

    private val eventsFile: File
        get() = File(context.filesDir, "emcon-tripwire.json")
    private val reportFile: File
        get() = File(context.filesDir, "emcon-tripwire.txt")
    private val hometurfFile: File
        get() = File(context.filesDir, "emcon-hometurf.json")

    private fun loadEvents(): List<TripEvent> {
        return try {
            val array = JSONArray(eventsFile.readText())
            val out = mutableListOf<TripEvent>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                out.add(
                    TripEvent(
                        id = obj.optString(
                            "id",
                            java.util.UUID.randomUUID().toString()),
                        whenMs = obj.getLong("when"),
                        source = obj.getString("source"),
                        port = obj.getInt("port"),
                        proto = obj.getString("proto"),
                        verdict = obj.getString("verdict"),
                        byteCount = obj.getInt("byteCount"),
                        repeatCount = obj.optInt("repeatCount", 1),
                        bytesHex = obj.optString("bytesHex")
                            .ifBlank { null }))
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun saveEvents() {
        val snapshot = _events.value
        writeReport(snapshot)
        scope.launch {
            try {
                val array = JSONArray()
                for (event in snapshot) {
                    val obj = JSONObject()
                    obj.put("id", event.id)
                    obj.put("when", event.whenMs)
                    obj.put("source", event.source)
                    obj.put("port", event.port)
                    obj.put("proto", event.proto)
                    obj.put("verdict", event.verdict)
                    obj.put("byteCount", event.byteCount)
                    obj.put("repeatCount", event.repeatCount)
                    event.bytesHex?.let { obj.put("bytesHex", it) }
                    array.put(obj)
                }
                eventsFile.writeText(array.toString())
            } catch (_: Exception) {
            }
        }
    }

    private fun writeReport(events: List<TripEvent>) {
        try {
            reportFile.writeText(tripwireReport(events))
        } catch (_: Exception) {
        }
    }

    /** The readable log, for the share sheet. */
    val tripwireReportFile: File get() = reportFile

    private fun loadHometurf(): Hometurf {
        return try {
            val obj = JSONObject(hometurfFile.readText())
            fun strings(key: String): Set<String> {
                val array = obj.optJSONArray(key) ?: return emptySet()
                return (0 until array.length())
                    .map { array.getString(it) }.toSet()
            }
            fun ints(key: String): Set<Int> {
                val array = obj.optJSONArray(key) ?: return emptySet()
                return (0 until array.length())
                    .map { array.getInt(it) }.toSet()
            }
            Hometurf(
                nights = obj.optInt("nights", 0),
                sources = strings("sources"),
                ports = ints("ports"),
                verdicts = strings("verdicts"),
                stagingDay = obj.optString("stagingDay", ""),
                stagedSources = strings("stagedSources"),
                stagedPorts = ints("stagedPorts"),
                stagedVerdicts = strings("stagedVerdicts"))
        } catch (_: Exception) {
            Hometurf()
        }
    }

    private fun saveHometurf() {
        val turf = _hometurf.value
        scope.launch {
            try {
                val obj = JSONObject()
                obj.put("nights", turf.nights)
                obj.put("sources", JSONArray(turf.sources.toList()))
                obj.put("ports", JSONArray(turf.ports.toList()))
                obj.put("verdicts", JSONArray(turf.verdicts.toList()))
                obj.put("stagingDay", turf.stagingDay)
                obj.put("stagedSources",
                    JSONArray(turf.stagedSources.toList()))
                obj.put("stagedPorts",
                    JSONArray(turf.stagedPorts.toList()))
                obj.put("stagedVerdicts",
                    JSONArray(turf.stagedVerdicts.toList()))
                hometurfFile.writeText(obj.toString())
            } catch (_: Exception) {
            }
        }
    }
}

/// Novelty dismissals, recorded so a pattern stops flagging
/// what the operator has already waved through. The steward
/// shares this store when it lands.
object Dismissals {
    private const val KEY = "stewardDismissed"

    private fun load(prefs: Prefs): MutableSet<String> =
        prefs.string(KEY, "").split("\n")
            .filter { it.isNotEmpty() }.toMutableSet()

    fun isDismissed(prefs: Prefs, note: String): Boolean =
        note in load(prefs)

    fun add(prefs: Prefs, note: String) {
        val set = load(prefs)
        if (!set.add(note)) return
        prefs.put(KEY, set.joinToString("\n"))
        Journal.log(
            "steward", "dismissal",
            "the operator dismissed a deviation and the " +
                "pattern learned it: $note")
    }

    fun count(prefs: Prefs): Int = load(prefs).size

    fun clear(prefs: Prefs) {
        prefs.put(KEY, "")
        Journal.log(
            "steward", "dismissal",
            "all dismissals restored — the pattern flags " +
                "everything again")
    }
}

/// The dead hand's courtesy bells. The hand itself falls at
/// the next opening (see Emcon.deadHandEvaluate); these are
/// only reminders, posted when an alarm the engine scheduled
/// comes due.
class DeadHandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val body = intent.getStringExtra(EXTRA_BODY) ?: return
        val manager = context.getSystemService(
            Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID, "Dead hand",
                NotificationManager.IMPORTANCE_DEFAULT))
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("Dead hand")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(
                System.currentTimeMillis().toInt(), notification)
        } catch (_: SecurityException) {
            // Notifications denied: the courtesy is silent,
            // the hand itself is unaffected.
        }
    }

    companion object {
        const val EXTRA_BODY = "body"
        const val CHANNEL_ID = "nightjar-deadhand"
    }
}
