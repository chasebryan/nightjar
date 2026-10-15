package net.nosuchmachine.nightjarhack

import android.annotation.SuppressLint
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID

/// The BLE mouth: advertisement beacons in the FFF0 service
/// data, a hosted GATT characteristic (FFF0/FFF1), and writes
/// to a picked peripheral. Android's gift over iOS: a write
/// target is a plain MAC address, dialable directly.
class BleMouth(private val context: Context, private val mouth: Mouth) {

    companion object {
        val SERVICE_UUID: UUID =
            UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
        val CHARACTERISTIC_UUID: UUID =
            UUID.fromString("0000fff1-0000-1000-8000-00805f9b34fb")
    }

    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager

    private val _beaconOn = MutableStateFlow(false)
    val beaconOn: StateFlow<Boolean> = _beaconOn
    private val _hosting = MutableStateFlow(false)
    val hosting: StateFlow<Boolean> = _hosting
    private val _writeTarget = MutableStateFlow<Pair<String, String>?>(null)
    val writeTarget: StateFlow<Pair<String, String>?> = _writeTarget

    private var advertiseCallback: AdvertiseCallback? = null
    private var gattServer: BluetoothGattServer? = null

    /** The Listen → Send handoff: write target = (address, label). */
    fun requestWrite(address: String, label: String) {
        _writeTarget.value = address to label
    }

    // MARK: Beacon (FFF0 service data carries the payload)

    @SuppressLint("MissingPermission")
    fun startBeacon(payload: ByteArray): Boolean {
        val advertiser = bluetoothManager.adapter?.bluetoothLeAdvertiser
            ?: return false
        stopBeacon()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(false)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()
        val data = AdvertiseData.Builder()
            .addServiceData(ParcelUuid(SERVICE_UUID), payload)
            .build()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                _beaconOn.value = true
            }
            override fun onStartFailure(errorCode: Int) {
                _beaconOn.value = false
                mouth.toast("Beacon failed (error $errorCode)", error = true)
            }
        }
        advertiseCallback = callback
        return try {
            advertiser.startAdvertising(settings, data, callback)
            true
        } catch (_: SecurityException) {
            mouth.toast("Bluetooth permission denied", error = true)
            false
        }
    }

    @SuppressLint("MissingPermission")
    fun stopBeacon() {
        val advertiser = bluetoothManager.adapter?.bluetoothLeAdvertiser
        val callback = advertiseCallback
        if (advertiser != null && callback != null) {
            try {
                advertiser.stopAdvertising(callback)
            } catch (_: Exception) {
            }
        }
        advertiseCallback = null
        _beaconOn.value = false
    }

    // MARK: GATT host (FFF0 service, FFF1 write characteristic)

    @SuppressLint("MissingPermission")
    fun startHosting(payload: ByteArray) {
        stopHosting()
        val serverCallback = object : BluetoothGattServerCallback() {
            override fun onCharacteristicWriteRequest(
                device: android.bluetooth.BluetoothDevice, requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean, responseNeeded: Boolean,
                offset: Int, value: ByteArray
            ) {
                characteristic.value = value
                mouth.noteBleArrival(device.address ?: "ble", value)
                if (responseNeeded) {
                    try {
                        gattServer?.sendResponse(
                            device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null
                        )
                    } catch (_: Exception) {
                    }
                }
            }
        }
        try {
            gattServer = bluetoothManager.openGattServer(context, serverCallback)
            val characteristic = BluetoothGattCharacteristic(
                CHARACTERISTIC_UUID,
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_READ,
                BluetoothGattCharacteristic.PERMISSION_WRITE or
                    BluetoothGattCharacteristic.PERMISSION_READ
            )
            characteristic.value = payload
            val service = BluetoothGattService(
                SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY
            )
            service.addCharacteristic(characteristic)
            gattServer?.addService(service)
            // Advertise the hosted service so writers can find it.
            val advertiser = bluetoothManager.adapter?.bluetoothLeAdvertiser
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setConnectable(true)
                .build()
            val data = AdvertiseData.Builder()
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .setIncludeDeviceName(false)
                .build()
            advertiseCallback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    _hosting.value = true
                }
                override fun onStartFailure(errorCode: Int) {
                    _hosting.value = false
                }
            }
            advertiser?.startAdvertising(settings, data, advertiseCallback)
            _hosting.value = true
        } catch (_: SecurityException) {
            mouth.toast("Bluetooth permission denied", error = true)
        }
    }

    @SuppressLint("MissingPermission")
    fun stopHosting() {
        try {
            gattServer?.close()
        } catch (_: Exception) {
        }
        gattServer = null
        if (_hosting.value) stopBeacon()
        _hosting.value = false
    }

    // MARK: Write to a peripheral (FFF1 on FFF0, by MAC)

    @SuppressLint("MissingPermission")
    fun writeToDevice(address: String, payload: ByteArray, completion: (Boolean) -> Unit) {
        val adapter = bluetoothManager.adapter
        if (adapter == null) {
            completion(false)
            return
        }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (_: Exception) {
            completion(false)
            return
        }
        var finished = false
        fun finish(ok: Boolean, gatt: BluetoothGatt?) {
            if (finished) return
            finished = true
            try {
                gatt?.close()
            } catch (_: Exception) {
            }
            completion(ok)
        }
        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    try {
                        gatt.discoverServices()
                    } catch (_: Exception) {
                        finish(false, gatt)
                    }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    finish(false, gatt)
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val service = gatt.getService(SERVICE_UUID)
                val characteristic = service?.getCharacteristic(CHARACTERISTIC_UUID)
                if (characteristic == null) {
                    finish(false, gatt)
                    return
                }
                try {
                    characteristic.value = payload
                    characteristic.writeType =
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    val started = gatt.writeCharacteristic(characteristic)
                    if (!started) finish(false, gatt)
                } catch (_: Exception) {
                    finish(false, gatt)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                finish(status == BluetoothGatt.GATT_SUCCESS, gatt)
            }
        }
        try {
            val gatt = device.connectGatt(context, false, callback)
            // 15 s timeout, as on iOS.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!finished) {
                    mouth.toast("BLE write timed out", error = true)
                    finish(false, gatt)
                }
            }, 15_000)
        } catch (_: SecurityException) {
            completion(false)
        }
    }
}
