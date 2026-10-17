package net.nosuchmachine.nightjarhack

import android.annotation.SuppressLint
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.security.MessageDigest

/// Brush pass — the Kotlin mirror of the iOS BrushPass:
/// the proximity dead drop.
///
/// The GATT host already serves its armed payload to anyone
/// who reads FFF1 — that read path is the drop. A host phone
/// seals a short message with the pairing key and arms the
/// host with the sealed bytes; the bytes are public to
/// anyone in BLE range and meaningless to all of them,
/// because only the pairing key opens the box.
///
/// The visitor is the missing half and lives here: armed by
/// the operator, it scans for a nightjar GATT host,
/// connects, reads the payload, and hands it up to be
/// opened. One pickup per arming — a drop is an event, not
/// a feed — and an identical payload re-read within the
/// hour is recognized as the same drop, not filed twice.
class BrushVisitor(
    private val context: Context,
    private val prefs: Prefs
) {
    private val _hunting = MutableStateFlow(false)
    val hunting: StateFlow<Boolean> = _hunting
    private val _status = MutableStateFlow("idle")
    val status: StateFlow<String> = _status

    /** Return true when the payload opened as a brush drop. */
    var onPayload: ((ByteArray) -> Boolean)? = null

    private val scope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var deadlineJob: Job? = null
    private var gatt: BluetoothGatt? = null
    @Volatile private var candidateFound = false

    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE)
            as BluetoothManager

    @SuppressLint("MissingPermission")
    fun start() {
        val scanner = bluetoothManager.adapter
            ?.bluetoothLeScanner ?: run {
            _status.value = "Bluetooth is not ready"
            return
        }
        candidateFound = false
        _hunting.value = true
        _status.value = "hunting — walk within BLE range of the host"
        deadlineJob?.cancel()
        deadlineJob = scope.launch {
            delay(120_000)
            if (_hunting.value) {
                stop()
                _status.value =
                    "no drop found in two minutes — stood down"
            }
        }
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(BleMouth.SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        try {
            scanner.startScan(
                listOf(filter), settings, scanCallback)
        } catch (_: SecurityException) {
            _hunting.value = false
            _status.value = "Bluetooth permission denied"
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        deadlineJob?.cancel()
        deadlineJob = null
        try {
            bluetoothManager.adapter?.bluetoothLeScanner
                ?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
        gatt?.close()
        gatt = null
        _hunting.value = false
        if (_status.value.startsWith("hunting")) {
            _status.value = "idle"
        }
    }

    private fun finish(message: String) {
        deadlineJob?.cancel()
        deadlineJob = null
        try {
            bluetoothManager.adapter?.bluetoothLeScanner
                ?.stopScan(scanCallback)
        } catch (_: Exception) {
        }
        gatt?.close()
        gatt = null
        _hunting.value = false
        _status.value = message
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(
            callbackType: Int, result: ScanResult
        ) {
            if (candidateFound) return
            candidateFound = true
            try {
                bluetoothManager.adapter?.bluetoothLeScanner
                    ?.stopScan(this)
            } catch (_: Exception) {
            }
            _status.value = "found a nightjar host — connecting"
            gatt = result.device.connectGatt(
                context, false, gattCallback)
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(
            gatt: BluetoothGatt, status: Int, newState: Int
        ) {
            when {
                newState == BluetoothProfile.STATE_CONNECTED ->
                    gatt.discoverServices()
                newState == BluetoothProfile.STATE_DISCONNECTED &&
                    _hunting.value && candidateFound ->
                    finish("the host dropped the connection")
                status != BluetoothGatt.GATT_SUCCESS &&
                    _hunting.value ->
                    finish("the host would not connect — stood down")
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(
            gatt: BluetoothGatt, status: Int
        ) {
            val service = gatt.getService(BleMouth.SERVICE_UUID)
            if (service == null) {
                finish("that host carries no nightjar service")
                return
            }
            val characteristic =
                service.getCharacteristic(BleMouth.CHARACTERISTIC_UUID)
            if (characteristic == null) {
                finish("that host has no drop slot")
                return
            }
            _status.value = "reading the drop"
            gatt.readCharacteristic(characteristic)
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: android.bluetooth.BluetoothGattCharacteristic,
            value: ByteArray, status: Int
        ) {
            handleValue(value)
        }

        @Deprecated("pre-API-33 callback")
        @SuppressLint("MissingPermission")
        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: android.bluetooth.BluetoothGattCharacteristic,
            status: Int
        ) {
            @Suppress("DEPRECATION")
            handleValue(characteristic.value ?: ByteArray(0))
        }

        private fun handleValue(value: ByteArray) {
            if (value.isEmpty()) {
                finish("the host's drop slot is empty")
                return
            }
            // The same drop, re-read inside the hour, is the
            // same event — not a second delivery.
            val hash = MessageDigest.getInstance("SHA-256")
                .digest(value)
                .joinToString("") { "%02x".format(it) }
            val lastHash = prefs.string("brushLastHash", "")
            val lastAt = prefs.string("brushLastAt", "0")
                .toLongOrNull() ?: 0
            if (lastHash == hash &&
                System.currentTimeMillis() - lastAt < 3600_000) {
                finish("same drop as last time — already filed")
                return
            }
            val opened = onPayload?.invoke(value) ?: false
            if (opened) {
                prefs.put("brushLastHash", hash)
                prefs.put(
                    "brushLastAt",
                    System.currentTimeMillis().toString())
                finish("drop opened — filed in the Brush thread")
            } else {
                finish(
                    "read a payload that does not open with " +
                        "your pairing key — not a drop for you")
            }
        }
    }
}
