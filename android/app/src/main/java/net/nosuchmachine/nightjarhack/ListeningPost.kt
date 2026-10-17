package net.nosuchmachine.nightjarhack

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import kotlin.math.max
import kotlin.math.pow

/// One address as the live list shows it — a port of DeviceRow
/// in the iOS app, with the same fields, smoothing and helpers.
data class DeviceRow(
    val id: String,  // the address (a real MAC on Android)
    var name: String? = null,
    var preferredLabel: String? = null,
    var kind: String = "Unknown device",
    var details: List<String> = emptyList(),
    var rank: Int = 0,
    var trackerShaped: Boolean = false,
    var rssiLast: Int? = null,
    var rssiClosest: Int? = null,
    var rssiHistory: List<Int> = emptyList(),
    var firstSeen: Double = 0.0,
    var lastSeen: Double = 0.0,
    var sightings: Int = 0,
    var makers: Set<String> = emptySet(),
    var rssiSmooth: Double? = null,
    var txPowerLast: Int? = null,
    var serviceUUIDs: List<String> = emptyList(),
    var rotatingAddress: Boolean = false,
    var flare: Boolean = false,
    var flareLastSeen: Double? = null
) {
    fun observe(s: Sighting) {
        sightings += 1
        firstSeen = if (firstSeen == 0.0) s.seenAt else minOf(firstSeen, s.seenAt)
        lastSeen = maxOf(lastSeen, s.seenAt)
        if (s.name != null) name = s.name
        if (s.rssi != null) {
            rssiLast = s.rssi
            rssiClosest = max(rssiClosest ?: s.rssi, s.rssi)
            rssiSmooth = rssiSmooth?.let { it + 0.35 * (s.rssi - it) }
                ?: s.rssi.toDouble()
            rssiHistory = (rssiHistory + s.rssi).takeLast(HISTORY_CAP)
        }
        for (company in s.manufacturerData.keys) {
            makers = makers + Vendors.companyName(company)
        }
        val classification = Classification.classify(s)
        if (classification.rank >= rank || rank == Classification.rankUnknown) {
            kind = classification.kind
            rank = classification.rank
        }
        if (classification.preferredLabel != null) {
            preferredLabel = classification.preferredLabel
        }
        if (classification.details.isNotEmpty()) details = classification.details
        trackerShaped = trackerShaped || classification.trackerShaped
        if (s.txPower != null) txPowerLast = s.txPower
        for (uuid in s.serviceUUIDs) {
            if (uuid !in serviceUUIDs && serviceUUIDs.size < 16) {
                serviceUUIDs = serviceUUIDs + uuid
            }
        }
        rotatingAddress = rotatingAddress || classification.rotatingPhone
        // Flare recognition: only checked when a pairing key
        // exists, and only against FFF0 service data — three
        // HMACs against the neighboring windows.
        val flareKey = KnockKeyStore.key
        if (flareKey != null) {
            for ((uuid, bytes) in s.serviceData) {
                if (uuid.startsWith("0000fff0") &&
                    Flare.matches(bytes, flareKey)) {
                    if (!flare) {
                        Journal.log(
                            "listen", "flare",
                            "a flare answered — a holder of the " +
                                "pairing key is in radio range " +
                                "(address $id)")
                    }
                    flare = true
                    flareLastSeen = s.seenAt
                }
            }
        }
    }

    val label: String get() = name ?: preferredLabel ?: kind

    val trend: String?
        get() {
            if (rssiHistory.size < 6) return null
            val mid = rssiHistory.size / 2
            val older = rssiHistory.subList(0, mid).average()
            val younger = rssiHistory.subList(mid, rssiHistory.size).average()
            val delta = younger - older
            return when {
                delta > 3 -> "approaching"
                delta < -3 -> "receding"
                else -> "steady"
            }
        }

    val trendArrow: String
        get() = when (trend) {
            "approaching" -> "▲"
            "receding" -> "▼"
            "steady" -> "●"
            else -> ""
        }

    val rangeBand: String
        get() {
            val rssi = rssiLast ?: return "?"
            return when {
                rssi >= -55 -> "immediate"
                rssi >= -70 -> "near"
                rssi >= -85 -> "far"
                else -> "faint"
            }
        }

    /// Rough range from the smoothed RSSI and the advertised
    /// transmit power (free-space falloff) — a guide, not a
    /// measurement.
    val distanceMeters: Double?
        get() {
            val smooth = rssiSmooth ?: return null
            val tx = (txPowerLast ?: -59).toDouble()
            return 10.0.pow((tx - smooth) / 20)
        }

    val dwell: Double get() = max(0.0, lastSeen - firstSeen)

    val sightingsPerMinute: Double
        get() = if (dwell < 10) 0.0 else sightings / (dwell / 60)

    fun age(now: Double): Double = max(0.0, now - lastSeen)

    companion object {
        const val HISTORY_CAP = 24
    }
}

/// The listening post: receive-only BLE scanning, the device
/// registry, and JSONL session files in upstream nightjar's
/// format (the same lines `nightjar report` reads). The one
/// platform gift: Android reports real MAC addresses, where
/// iOS shows per-host UUIDs.
class ListeningPost(private val context: Context) {

    data class ActiveSession(
        val id: String,
        val label: String?,
        val startedAt: Double,
        val file: File
    )

    private val scope = CoroutineScope(Dispatchers.Default)
    private var ticker: Job? = null
    private var writer: java.io.BufferedWriter? = null
    private var dirty = false
    private var sightingsSeen = 0

    private val devices = mutableMapOf<String, DeviceRow>()
    private var rankOrder: List<String> = emptyList()
    private var lastRankAt: Double = 0.0

    private val _rows = MutableStateFlow<List<DeviceRow>>(emptyList())
    val rows: StateFlow<List<DeviceRow>> = _rows
    private val _session = MutableStateFlow<ActiveSession?>(null)
    val session: StateFlow<ActiveSession?> = _session
    private val _isListening = MutableStateFlow(false)
    val isListening: StateFlow<Boolean> = _isListening
    private val _bluetoothOn = MutableStateFlow(false)
    val bluetoothOn: StateFlow<Boolean> = _bluetoothOn
    private val _deviceCount = MutableStateFlow(0)
    val deviceCount: StateFlow<Int> = _deviceCount
    private val _sightingCount = MutableStateFlow(0)
    val sightingCount: StateFlow<Int> = _sightingCount
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            record(result)
        }

        override fun onBatchScanResults(results: MutableList<ScanResult>) {
            for (result in results) record(result)
        }

        override fun onScanFailed(errorCode: Int) {
            _lastError.value = "Scan failed (error $errorCode)"
        }
    }

    fun refreshBluetoothState() {
        _bluetoothOn.value = bluetoothManager.adapter?.isEnabled == true
    }

    @SuppressLint("MissingPermission")
    fun start(label: String) {
        if (_isListening.value) return
        refreshBluetoothState()
        val adapter = bluetoothManager.adapter
        if (adapter == null || !adapter.isEnabled) {
            _lastError.value = "Bluetooth is off or unavailable"
            return
        }
        devices.clear()
        rankOrder = emptyList()
        sightingsSeen = 0
        val stamp = java.text.SimpleDateFormat(
            "yyyy-MM-dd'T'HHmmss", java.util.Locale.US
        ).format(java.util.Date())
        val dir = sessionsDir(context)
        dir.mkdirs()
        val file = File(dir, "nightjar-$stamp.jsonl")
        writer = file.bufferedWriter()
        val session = ActiveSession(
            id = file.name, label = label.ifEmpty { null },
            startedAt = nowSeconds(), file = file
        )
        _session.value = session
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            adapter.bluetoothLeScanner?.startScan(null, settings, scanCallback)
        } catch (e: SecurityException) {
            _lastError.value = "Bluetooth permission denied"
            stop()
            return
        }
        _isListening.value = true
        _lastError.value = null
        Journal.log(
            "listen", "session",
            "listening started — ${session.label ?: "unlabeled"}"
        )
        startTicker()
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        try {
            bluetoothManager.adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (_: SecurityException) {
        } catch (_: IllegalStateException) {
        }
        ticker?.cancel()
        ticker = null
        try {
            writer?.flush()
            writer?.close()
        } catch (_: Exception) {
        }
        writer = null
        val wasListening = _isListening.value
        _isListening.value = false
        _session.value = null
        if (wasListening) {
            Journal.log("listen", "session", "listening stopped")
        }
    }

    private fun record(result: ScanResult) {
        val record = result.scanRecord ?: return
        val seenAt = nowSeconds()
        val manufacturer = mutableMapOf<Int, ByteArray>()
        val sparse = record.manufacturerSpecificData
        if (sparse != null) {
            for (i in 0 until sparse.size()) {
                manufacturer[sparse.keyAt(i)] = sparse.valueAt(i)
            }
        }
        val serviceData = mutableMapOf<String, ByteArray>()
        record.serviceData?.forEach { (uuid, data) ->
            serviceData[uuid.toString().lowercase()] = data
        }
        val sighting = Sighting(
            seenAt = seenAt,
            address = result.device.address ?: return,
            name = record.deviceName,
            rssi = if (result.rssi == 127) null else result.rssi,
            manufacturerData = manufacturer,
            serviceUUIDs = record.serviceUuids?.map {
                it.toString().lowercase()
            } ?: emptyList(),
            txPower = if (record.txPowerLevel == Int.MIN_VALUE) null
            else record.txPowerLevel,
            serviceData = serviceData
        )
        synchronized(devices) {
            val row = devices[sighting.address]
            if (row != null) {
                row.observe(sighting)
            } else {
                devices[sighting.address] =
                    DeviceRow(id = sighting.address).also { it.observe(sighting) }
            }
            sightingsSeen += 1
            dirty = true
        }
        try {
            writer?.write(sightingJsonLine(sighting))
            writer?.newLine()
        } catch (_: Exception) {
        }
    }

    private fun startTicker() {
        ticker?.cancel()
        ticker = scope.launch {
            while (isActive) {
                delay(1000)
                try {
                    writer?.flush()
                } catch (_: Exception) {
                }
                if (dirty) publishRows()
            }
        }
    }

    /// Contents refresh every tick; the ORDER re-ranks at
    /// most every 5 s, with hysteresis — the same calm as the
    /// iOS list.
    private fun publishRows() {
        val now = nowSeconds()
        synchronized(devices) {
            if (now - lastRankAt >= 5 || rankOrder.isEmpty()) {
                lastRankAt = now
                rankOrder = ranked(devices, rankOrder, now)
            }
            val ordered = rankOrder.mapNotNull { devices[it] }.toMutableList()
            val rankedIDs = rankOrder.toSet()
            ordered += devices.values
                .filter { it.id !in rankedIDs }
                .sortedByDescending { it.rssiSmooth ?: -200.0 }
            _rows.value = ordered.map { it.copy() }
            _deviceCount.value = devices.size
            _sightingCount.value = sightingsSeen
            dirty = false
        }
    }

    companion object {
        fun nowSeconds(): Double = System.currentTimeMillis() / 1000.0

        fun sessionsDir(context: Context): File =
            File(context.getExternalFilesDir(null) ?: context.filesDir, "sessions")

        fun ranked(
            devices: Map<String, DeviceRow>, previous: List<String>,
            now: Double
        ): List<String> {
            var order = previous.filter { devices.containsKey(it) }
            val known = order.toSet()
            val newcomers = devices.values
                .filter { it.id !in known }
                .sortedByDescending { it.rssiSmooth ?: -200.0 }
            order = order + newcomers.map { it.id }
            fun isQuiet(id: String): Boolean =
                (devices[id]?.age(now) ?: 0.0) > 20
            fun smooth(id: String): Double =
                devices[id]?.rssiSmooth ?: -200.0
            order = order.filter { !isQuiet(it) } + order.filter { isQuiet(it) }
            val margin = 3.0
            if (order.size > 1) {
                val mutable = order.toMutableList()
                repeat(3) {
                    var swapped = false
                    for (i in 0 until mutable.size - 1) {
                        val a = mutable[i]
                        val b = mutable[i + 1]
                        if (isQuiet(a) == isQuiet(b) &&
                            smooth(b) > smooth(a) + margin
                        ) {
                            mutable[i] = b
                            mutable[i + 1] = a
                            swapped = true
                        }
                    }
                    if (!swapped) return@repeat
                }
                order = mutable
            }
            return order
        }

        /// The log record: field order and spelling match the
        /// Python side, exactly as Sighting.swift writes it.
        fun sightingJsonLine(s: Sighting): String {
            fun str(v: String?): String =
                if (v == null) "null"
                else "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
            fun intOrNull(v: Int?): String = v?.toString() ?: "null"
            fun hex(data: ByteArray): String =
                data.joinToString("") { "%02x".format(it) }
            val manufacturer = s.manufacturerData.keys.sorted().joinToString(",") {
                "\"$it\":${str(hex(s.manufacturerData[it] ?: ByteArray(0)))}"
            }
            val fields = mutableListOf(
                "\"type\":\"sighting\"",
                "\"seen_at\":${s.seenAt}",
                "\"address\":${str(s.address)}",
                "\"name\":${str(s.name)}",
                "\"rssi\":${intOrNull(s.rssi)}",
                "\"manufacturer_data\":{$manufacturer}",
                "\"service_uuids\":[${s.serviceUUIDs.joinToString(",") { str(it) }}]",
                "\"tx_power\":${intOrNull(s.txPower)}"
            )
            if (s.serviceData.isNotEmpty()) {
                val entries = s.serviceData.keys.sorted().joinToString(",") {
                    "${str(it)}:${str(hex(s.serviceData[it] ?: ByteArray(0)))}"
                }
                fields.add("\"service_data\":{$entries}")
            }
            return "{" + fields.joinToString(",") + "}"
        }
    }
}
