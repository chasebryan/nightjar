package net.nosuchmachine.nightjarhack

// More advertisement decoders, added after the first port to cut down
// "Unknown device" rows: AltBeacon, Xiaomi MiBeacon, BTHome v2 and
// Govee thermo-hygrometers. Same rules as Decoders.kt — pure
// Kotlin/JVM (no Android imports), strict gates (exact company ids,
// lengths and magic bytes), and nothing encrypted is ever decrypted:
// an encrypted frame is recognised and labelled as encrypted, no more.
//
// Detection notes per format live with each decoder. Where a public
// spec was ambiguous in my sources, the decoder takes the narrower
// reading and the gap is called out in the commit message.

/** Unsigned value of the byte at [index] (MoreDecoders-local helper). */
private fun ByteArray.mu(index: Int): Int = this[index].toInt() and 0xFF

/** Little-endian unsigned 16-bit value at [at]. */
private fun ByteArray.u16le(at: Int): Int = mu(at) or (mu(at + 1) shl 8)

/** Little-endian signed 16-bit value at [at]. */
private fun ByteArray.s16le(at: Int): Int = u16le(at).toShort().toInt()

/** Little-endian unsigned 24-bit value at [at]. */
private fun ByteArray.u24le(at: Int): Int =
    mu(at) or (mu(at + 1) shl 8) or (mu(at + 2) shl 16)

/** Lowercase hex of the whole array. */
private fun ByteArray.mhex(): String =
    joinToString("") { "%02x".format(it.toInt() and 0xFF) }

// MARK: - AltBeacon

/**
 * AltBeacon — the open beacon format from the AltBeacon spec
 * (altbeacon.org), maintained by Radius Networks. The manufacturer
 * payload after the company-id bytes is fixed: a 20-byte beacon id,
 * one signed reference-RSSI byte, one manufacturer-reserved byte.
 *
 * The spec names the identifier 0xBEAC; because BLE company ids are
 * transmitted little-endian, an Android-parsed key can also surface
 * as 0xACBE. Vendors.identify tries both keys — the 22-byte fixed
 * layout makes a false hit on either implausible.
 */
object AltBeacon {
    const val company: Int = 0xBEAC
    const val companyWireOrder: Int = 0xACBE

    fun decode(payload: ByteArray): Vendors.Identification? {
        if (payload.size < 22) return null
        val id = payload.copyOfRange(0, 20).mhex()
        val refRssi = payload[20].toInt()
        return Vendors.Identification(
            kind = "AltBeacon",
            details = listOf(
                "beacon id $id",
                "reference RSSI $refRssi dBm",
            ),
            specificity = 3,
        )
    }
}

// MARK: - Xiaomi MiBeacon

/**
 * Xiaomi MiBeacon — service data on UUID 0xFE95, the format stock
 * Mijia sensors broadcast (documented in the "Mijia BLE MiBeacon
 * protocol" write-ups and the public xiaomi-ble parsers).
 *
 * Layout (all integers little-endian):
 *   [0..1] frame control: bit 3 encrypted, bit 4 MAC included,
 *          bit 5 capability included, bit 6 object included,
 *          bit 7 mesh, bits 12–15 frame version
 *   [2..3] device (product) id
 *   [4]    frame counter
 *   [5..]  6-byte MAC if bit 4, 1 capability byte if bit 5, then
 *          objects as [type u16][length u8][value] when bit 6
 *
 * Encrypted frames (AES-CCM with a per-device bindkey) are labelled
 * as encrypted and never touched further. Mesh frames are recognised
 * but their objects are not walked — the mesh payload layout differs.
 */
object MiBeacon {
    const val service: Int = 0xFE95

    /**
     * Common product ids, from the public xiaomi-ble device table.
     * Best-effort: the ids confirmed against multiple public sources
     * are the thermometers, the toothbrushes (0x0806/0x1790) and the
     * S400 scale (0x3BD5); the rest are widely-listed but less certain.
     * Anything unlisted falls back to "Xiaomi MiBeacon device 0x…".
     */
    val productNames: Map<Int, String> = mapOf(
        0x01AA to "Xiaomi Mi Temperature & Humidity Monitor (LYWSDCGQ)",
        0x045B to "Xiaomi Mi Temperature & Humidity Monitor Clock (LYWSD02)",
        0x055B to "Xiaomi Mi Temperature & Humidity Monitor 2 (LYWSD03MMC)",
        0x0387 to "Xiaomi Mijia E-ink Thermometer (MHO-C401)",
        0x0B47 to "Xiaomi thermometer (MJWSD05MMC)",
        0x045D to "Qingping Temperature & Humidity Monitor (CGG1)",
        0x03BC to "Xiaomi Plant Monitor (HHCCJCY01)",
        0x098C to "Xiaomi Door/Window Sensor 2 (MCCGQ02HL)",
        0x0861 to "Xiaomi Water Leak Sensor (SJWS01LM)",
        0x07F6 to "Xiaomi Motion Sensor 2 (RTCGQ14LM)",
        0x0806 to "Xiaomi T700 toothbrush (K0918)",
        0x1790 to "Xiaomi T700i toothbrush (K0918)",
        0x3BD5 to "Xiaomi Smart Scale S400",
        0x0A83 to "Xiaomi Mi Smart Kettle (YM-K1501)",
    )

    fun decode(payload: ByteArray): Services.Identification? {
        if (payload.size < 5) return null
        val frameCtrl = payload.u16le(0)
        val version = frameCtrl shr 12
        if (version < 2) return null
        val encrypted = frameCtrl and 0x0008 != 0
        val mesh = frameCtrl and 0x0080 != 0
        val deviceID = payload.u16le(2)
        val product = productNames[deviceID]
        val kind = product
            ?: "Xiaomi MiBeacon device 0x%04X".format(deviceID)
        val details = mutableListOf<String>()
        var readings = 0
        if (encrypted) {
            details.add(
                "encrypted MiBeacon frame (bindkey required; not decoded)"
            )
        } else if (!mesh && frameCtrl and 0x0040 != 0) {
            var offset = 5
            if (frameCtrl and 0x0010 != 0) offset += 6
            if (frameCtrl and 0x0020 != 0) offset += 1
            while (offset + 3 <= payload.size) {
                val type = payload.u16le(offset)
                val length = payload.mu(offset + 2)
                val value = offset + 3
                if (value + length > payload.size) break
                when (type) {
                    0x1004 -> if (length == 2) {
                        details.add(
                            "%.1f °C".format(payload.s16le(value) / 10.0)
                        )
                        readings++
                    }
                    0x1006 -> if (length == 2) {
                        details.add(
                            "%.1f%% RH".format(payload.u16le(value) / 10.0)
                        )
                        readings++
                    }
                    0x1007 -> if (length == 3) {
                        details.add(
                            "illuminance ${payload.u24le(value)} lx"
                        )
                        readings++
                    }
                    0x100A -> if (length == 1) {
                        details.add("battery ${payload.mu(value)}%")
                        readings++
                    }
                    0x100D -> if (length == 4) {
                        details.add(
                            "%.1f °C".format(payload.s16le(value) / 10.0)
                        )
                        details.add(
                            "%.1f%% RH".format(
                                payload.u16le(value + 2) / 10.0
                            )
                        )
                        readings++
                    }
                }
                offset = value + length
            }
        }
        return Services.Identification(
            kind = kind, details = details,
            trackerShaped = false, rotatingPhone = false,
            specificity = if (product != null || readings > 0) 3 else 2,
        )
    }
}

// MARK: - BTHome v2

/**
 * BTHome v2 — the open sensor format (bthome.io) on service UUID
 * 0xFCD2. First byte is the device-info byte: bit 0 encryption,
 * bit 1 MAC included (the next 6 bytes are the MAC, reversed),
 * bit 2 trigger-based, bits 5–7 the BTHome version (2). Objects
 * follow as [id u8][little-endian value] with per-id fixed lengths
 * from the spec's measurement table; an unknown id ends the walk
 * (its length is unknowable) but readings already gathered stand.
 *
 * Encrypted advertisements (AES-CCM, bindkey) are recognised only.
 */
object BtHome {
    const val service: Int = 0xFCD2

    /** Fixed value lengths for the object ids decoded here. */
    private val lengths: Map<Int, Int> = mapOf(
        0x00 to 1, 0x01 to 1, 0x02 to 2, 0x03 to 2, 0x04 to 3,
        0x05 to 3, 0x0A to 3, 0x0B to 3, 0x0C to 2, 0x0D to 2,
        0x0E to 2, 0x12 to 2, 0x13 to 2,
    )

    private fun render(id: Int, payload: ByteArray, at: Int): String =
        when (id) {
            0x00 -> "" // packet id: consumed, not displayed
            0x01 -> "battery ${payload.mu(at)}%"
            0x0A -> "%.3f kWh".format(payload.u24le(at) * 0.001)
            0x0B -> "%.2f W".format(payload.u24le(at) * 0.01)
            0x02 -> "%.2f °C".format(payload.s16le(at) / 100.0)
            0x03 -> "%.2f%% RH".format(payload.u16le(at) / 100.0)
            0x04 -> "%.2f hPa".format(payload.u24le(at) / 100.0)
            0x05 -> "illuminance %.2f lx".format(payload.u24le(at) / 100.0)
            0x0C -> "voltage ${payload.u16le(at)} mV"
            0x0D -> "PM2.5 ${payload.u16le(at)} µg/m³"
            0x0E -> "PM10 ${payload.u16le(at)} µg/m³"
            0x12 -> "CO2 ${payload.u16le(at)} ppm"
            0x13 -> "VOC ${payload.u16le(at)} µg/m³"
            else -> ""
        }

    fun decode(payload: ByteArray): Services.Identification? {
        if (payload.isEmpty()) return null
        val info = payload.mu(0)
        if (info shr 5 != 2) return null
        if (info and 0x01 != 0) {
            return Services.Identification(
                kind = "BTHome sensor",
                details = listOf(
                    "encrypted BTHome v2 advertisement (not decoded)"
                ),
                trackerShaped = false, rotatingPhone = false,
                specificity = 2,
            )
        }
        var offset = 1
        if (info and 0x02 != 0) offset += 6
        val details = mutableListOf<String>()
        while (offset < payload.size) {
            val id = payload.mu(offset)
            val length = lengths[id] ?: break
            if (offset + 1 + length > payload.size) break
            val rendered = render(id, payload, offset + 1)
            if (rendered.isNotEmpty()) details.add(rendered)
            offset += 1 + length
        }
        return Services.Identification(
            kind = "BTHome sensor", details = details,
            trackerShaped = false, rotatingPhone = false,
            specificity = if (details.isEmpty()) 2 else 3,
        )
    }
}

// MARK: - Govee

/**
 * Govee thermo-hygrometers (H5075 family) — manufacturer data under
 * company id 0xEC88. The documented H5075 frame is exactly 6 bytes:
 * a 0x00 lead byte, a 24-bit big-endian packed temperature/humidity,
 * a battery byte and a trailing 0x00 (the payload this app sees,
 * company bytes already stripped). In the packed value the top bit
 * is the temperature sign, temperature is (magnitude / 1000) / 10 °C
 * and humidity is (magnitude % 1000) / 10 %; the battery byte's top
 * bit is a sensor-error flag and its low 7 bits the percentage.
 * Anything that does not match that shape — or whose readings fall
 * outside sane ranges — is recognised as a Govee thermometer with
 * no readings claimed.
 */
object Govee {
    const val company: Int = 0xEC88

    fun decode(payload: ByteArray): Vendors.Identification {
        if (payload.size == 6 && payload.mu(0) == 0x00) {
            val packed = (payload.mu(1) shl 16) or
                (payload.mu(2) shl 8) or payload.mu(3)
            val batteryByte = payload.mu(4)
            val battery = batteryByte and 0x7F
            val fault = batteryByte and 0x80 != 0 || packed == 0xFFFFFF
            if (!fault) {
                val negative = packed and 0x800000 != 0
                val magnitude = packed and 0x7FFFFF
                var temp = (magnitude / 1000) / 10.0
                if (negative) temp = -temp
                val humidity = (magnitude % 1000) / 10.0
                if (temp in -40.0..85.0 && humidity <= 100.0) {
                    return Vendors.Identification(
                        kind = "Govee thermometer",
                        details = listOf(
                            "%.1f °C".format(temp),
                            "%.1f%% RH".format(humidity),
                            "battery $battery%",
                        ),
                        specificity = 3,
                    )
                }
            }
            return Vendors.Identification(
                kind = "Govee thermometer",
                details = listOf("battery $battery%"),
                specificity = 2,
            )
        }
        return Vendors.Identification(
            kind = "Govee thermometer", details = emptyList(),
            specificity = 2,
        )
    }
}
