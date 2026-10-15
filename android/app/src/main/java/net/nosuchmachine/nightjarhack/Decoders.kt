package net.nosuchmachine.nightjarhack

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

// BLE advertisement decoders, ported branch for branch from the iOS app's
// Swift sources (Sighting.swift, Identify.swift, Continuity.swift,
// Services.swift, Vendors.swift, Drones.swift), which are themselves ports
// of the Python nightjar package. Every kind string and detail string here
// matches the Swift (and Python) side character for character, so a device
// looks the same on the phone and in the Mac's reports.
//
// Pure Kotlin/JVM: no Android imports, so this file is unit-testable as-is.
// Swift [UInt8] becomes ByteArray throughout, and company ids / message
// types / other UInt8- and UInt16-sized values are carried as Int (always
// read unsigned via the helpers below).

/** The Bluetooth SIG base UUID suffix, the way nightjar's logs spell UUIDs. */
const val sigBaseSuffix = "-0000-1000-8000-00805f9b34fb"

/** Unsigned value of a byte (Swift's UInt8). */
private fun Byte.u(): Int = toInt() and 0xFF

/** Unsigned value of the byte at [index]. */
private fun ByteArray.u(index: Int): Int = this[index].toInt() and 0xFF

/** Lowercase hex, one zero-padded byte at a time (Swift's JSONL.hex). */
private fun ByteArray.hexString(): String =
    joinToString("") { "%02x".format(it.u()) }

/**
 * Strict UTF-8 decode: null on malformed input, matching Swift's
 * failable String(bytes:encoding:.utf8) (the JVM's lenient decode would
 * silently substitute U+FFFD instead).
 */
private fun decodeUtf8Strict(bytes: ByteArray): String? = try {
    Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes)).toString()
} catch (e: CharacterCodingException) {
    null
}

// MARK: - Sighting

/**
 * One received BLE advertisement, as nightjar understands it.
 *
 * Mirrors the Swift Sighting struct's data model (the CoreBluetooth
 * construction lives in the listener, not here). Times are epoch seconds.
 * [manufacturerData] is keyed by company id with the payload after the
 * two company-id bytes; [serviceUUIDs] and the keys of [serviceData] are
 * lowercase 128-bit UUID strings.
 */
class Sighting(
    val seenAt: Double,
    val address: String,
    val name: String? = null,
    val rssi: Int? = null,
    val manufacturerData: Map<Int, ByteArray> = emptyMap(),
    val serviceUUIDs: List<String> = emptyList(),
    val txPower: Int? = null,
    val serviceData: Map<String, ByteArray> = emptyMap(),
)

// MARK: - Classification

/**
 * What kind of thing a sighting is — follows Identify.swift's classify(),
 * same channels in the same order: Apple's Continuity chain, then service
 * UUIDs and service data, then other makers' manufacturer data, then the
 * bare name.
 */
data class Classification(
    val kind: String = "Unknown device",
    val details: List<String> = emptyList(),
    val rank: Int = rankUnknown,
    val trackerShaped: Boolean = false,
    val rotatingPhone: Boolean = false,
    /**
     * A name the broadcast itself supplies (a drone's Remote ID serial),
     * shown when the advertisement carries no local name.
     */
    val preferredLabel: String? = null,
) {
    companion object {
        const val rankUnknown = 0
        const val rankFamily = 10
        const val rankFamilyHint = 15
        const val rankSubfamily = 20
        const val rankProduct = 30

        private fun rankFor(specificity: Int): Int = when (specificity) {
            3 -> rankProduct
            2 -> rankSubfamily
            else -> rankFamily
        }

        fun classify(s: Sighting): Classification {
            val apple = s.manufacturerData[Continuity.appleCompanyID]
            if (apple != null && apple.isNotEmpty()) {
                val ident = Continuity.identifyApple(apple)
                var rankValue = rankFor(ident.specificity)
                if (ident.kind == "Apple device (Nearby Info)") {
                    rankValue = rankFamilyHint
                }
                val tracker = ident.findMy?.separated ?: false
                return Classification(
                    kind = ident.kind, details = ident.details,
                    rank = rankValue,
                    trackerShaped = tracker, rotatingPhone = false,
                )
            }

            val service = Services.identify(
                serviceUUIDs = s.serviceUUIDs,
                serviceData = s.serviceData,
            )
            if (service != null && service.specificity >= 2) {
                return Classification(
                    kind = service.kind, details = service.details,
                    rank = rankFor(service.specificity),
                    trackerShaped = service.trackerShaped,
                    rotatingPhone = service.rotatingPhone,
                    preferredLabel = service.preferredLabel,
                )
            }

            val vendor = Vendors.identify(s.manufacturerData)
            if (vendor != null) {
                return Classification(
                    kind = vendor.kind, details = vendor.details,
                    rank = rankFor(vendor.specificity),
                    trackerShaped = false, rotatingPhone = false,
                )
            }

            if (service != null) {
                return Classification(
                    kind = service.kind, details = service.details,
                    rank = rankFamily, trackerShaped = false,
                    rotatingPhone = false,
                    preferredLabel = service.preferredLabel,
                )
            }
            if (s.name != null) {
                return Classification(kind = "Named device")
            }
            return Classification()
        }
    }
}

// MARK: - Continuity (Apple)

/**
 * Reading what an Apple broadcast says — a port of Continuity.swift.
 *
 * Apple devices pack their manufacturer payload (company 0x004C) as a
 * chain of small messages framed [type][length][value]. Find My
 * accessory broadcasts are the exception: one fixed-format record,
 * recognized before the chain is walked.
 */
object Continuity {
    const val appleCompanyID: Int = 0x004C

    class Message(val type: Int, val value: ByteArray) {
        val typeName: String
            get() = Continuity.messageTypes[type]
                ?: "Unknown 0x%02X".format(type)
    }

    val messageTypes: Map<Int, String> = mapOf(
        0x02 to "iBeacon",
        0x03 to "AirPrint",
        0x05 to "AirDrop",
        0x06 to "HomeKit",
        0x07 to "Proximity Pairing",
        0x08 to "Hey Siri",
        0x09 to "AirPlay Target",
        0x0A to "AirPlay Source",
        0x0B to "Magic Switch",
        0x0C to "Handoff",
        0x0D to "Tethering Target",
        0x0E to "Tethering Source",
        0x0F to "Nearby Action",
        0x10 to "Nearby Info",
        0x12 to "Find My",
    )

    /** Split an Apple manufacturer payload into its TLV messages. */
    fun parse(payload: ByteArray): List<Message> {
        val messages = mutableListOf<Message>()
        var index = 0
        while (index + 2 <= payload.size) {
            val type = payload.u(index)
            val length = payload.u(index + 1)
            val start = index + 2
            if (start + length > payload.size) {
                break // truncated tail; keep what parsed cleanly
            }
            messages.add(
                Message(type, payload.copyOfRange(start, start + length))
            )
            index = start + length
        }
        return messages
    }

    // MARK: Proximity Pairing (AirPods, Beats)

    val airPodsModels: Map<String, String> = mapOf(
        "0220" to "AirPods (1st gen)",
        "0f20" to "AirPods (2nd gen)",
        "1320" to "AirPods (3rd gen)",
        "1b20" to "AirPods 4",
        "1920" to "AirPods 4 (ANC)",
        "0e20" to "AirPods Pro",
        "1420" to "AirPods Pro (2nd gen)",
        "2420" to "AirPods Pro (2nd gen, USB-C)",
        "0a20" to "AirPods Max",
        "1f20" to "AirPods Max (USB-C)",
        "0320" to "Powerbeats3",
        "0b20" to "Powerbeats Pro",
        "2b20" to "Powerbeats Pro 2",
        "0c20" to "Beats Solo Pro",
        "0520" to "BeatsX",
        "0620" to "Beats Solo3",
        "2720" to "Beats Solo 4",
        "2520" to "Beats Solo Buds",
        "0920" to "Beats Studio3",
        "1020" to "Beats Flex",
        "1120" to "Beats Studio Buds",
        "1620" to "Beats Studio Buds+",
        "1720" to "Beats Studio Pro",
        "1220" to "Beats Fit Pro",
    )

    val airPodsColours: Map<Int, String> = mapOf(
        0x00 to "white", 0x01 to "black", 0x02 to "red", 0x03 to "blue",
        0x04 to "pink", 0x05 to "gray", 0x06 to "silver", 0x07 to "gold",
        0x08 to "rose gold", 0x09 to "space gray", 0x0A to "dark blue",
        0x0B to "light blue", 0x0C to "yellow",
    )

    /** Battery nibbles run 0..10 (x10 %); 15 means unknown/absent. */
    private fun batteryLevel(nibble: Int): Int? =
        if (nibble <= 10) nibble * 10 else null

    data class AirPodsState(
        val model: String,
        val modelCode: String,
        val leftBattery: Int?,
        val rightBattery: Int?,
        val caseBattery: Int?,
        val leftInEar: Boolean,
        val rightInEar: Boolean,
        val leftCharging: Boolean,
        val rightCharging: Boolean,
        val caseCharging: Boolean,
        val lidOpen: Boolean,
        val colour: String?,
    ) {
        val describe: String
            get() {
                fun batt(value: Int?, charging: Boolean): String {
                    val text = value?.let { "$it%" } ?: "?"
                    return text + if (charging) " charging" else ""
                }
                val left = "L ${batt(leftBattery, leftCharging)}" +
                    if (leftInEar) " (in ear)" else ""
                val right = "R ${batt(rightBattery, rightCharging)}" +
                    if (rightInEar) " (in ear)" else ""
                var text = "$model: $left, $right, " +
                    "case ${batt(caseBattery, caseCharging)}, " +
                    "lid ${if (lidOpen) "open" else "closed"}"
                if (colour != null) {
                    text += ", $colour"
                }
                return text
            }
    }

    /**
     * Decode a Proximity Pairing message, following the OpenPods layout:
     * when the 0x20 bit of the status byte is clear, left and right swap.
     */
    fun decodeAirPods(message: Message): AirPodsState? {
        val v = message.value
        if (message.type != 0x07 || v.size < 8) return null
        val modelCode = byteArrayOf(v[1], v[2]).hexString()
        val status = v.u(3)
        val flipped = (status and 0x20) == 0
        val high = (v.u(4) shr 4) and 0xF
        val low = v.u(4) and 0xF
        val rightNibble = if (flipped) low else high
        val leftNibble = if (flipped) high else low
        val charge = (v.u(5) shr 4) and 0xF
        val leftBit: Int = if (flipped) 0x02 else 0x01
        val rightBit: Int = if (flipped) 0x01 else 0x02
        val ear = status and 0x0F
        val leftEarBit: Int = if (flipped) 0x08 else 0x02
        val rightEarBit: Int = if (flipped) 0x02 else 0x08
        val colourByte: Int? = if (v.size > 7) v.u(7) else null
        return AirPodsState(
            model = airPodsModels[modelCode]
                ?: "AirPods-class (model $modelCode)",
            modelCode = modelCode,
            leftBattery = batteryLevel(leftNibble),
            rightBattery = batteryLevel(rightNibble),
            caseBattery = batteryLevel(v.u(5) and 0xF),
            leftInEar = (ear and leftEarBit) != 0,
            rightInEar = (ear and rightEarBit) != 0,
            leftCharging = (charge and leftBit) != 0,
            rightCharging = (charge and rightBit) != 0,
            caseCharging = (charge and 0x04) != 0,
            lidOpen = (v.u(6) and 0x08) != 0,
            colour = colourByte?.let { airPodsColours[it] },
        )
    }

    // MARK: iBeacon

    data class IBeaconState(
        val proximityUUID: String,
        val major: Int,
        val minor: Int,
        val measuredPower: Int?,
    ) {
        val describe: String
            get() {
                var text = "iBeacon $proximityUUID major $major minor $minor"
                if (measuredPower != null) {
                    text += ", $measuredPower dBm @ 1 m"
                }
                return text
            }
    }

    fun decodeIBeacon(message: Message): IBeaconState? {
        val v = message.value
        if (message.type != 0x02 || v.size < 20) return null
        val hex = v.copyOfRange(0, 16).hexString()
        val uuid = hex.substring(0, 8) + "-" + hex.substring(8, 12) + "-" +
            hex.substring(12, 16) + "-" + hex.substring(16, 20) + "-" +
            hex.substring(20, 32)
        val power: Int? = if (v.size >= 21) v[20].toInt() else null
        return IBeaconState(
            proximityUUID = uuid,
            major = (v.u(16) shl 8) or v.u(17),
            minor = (v.u(18) shl 8) or v.u(19),
            measuredPower = power,
        )
    }

    // MARK: Find My

    val findMyBattery: List<String> =
        listOf("full", "medium", "low", "very low")

    data class FindMyState(
        val status: Int,
        /** The 0x19 "offline finding" format. */
        val separated: Boolean,
    ) {
        val battery: String
            get() = Continuity.findMyBattery[(status shr 6) and 0x3]

        val describe: String
            get() = if (separated) {
                "Find My network broadcast (separated from owner), " +
                    "battery $battery"
            } else {
                "Find My network broadcast (nearby its owner)"
            }
    }

    /** Recognize a Find My accessory broadcast (not a TLV message). */
    fun parseFindMy(payload: ByteArray): FindMyState? {
        if (payload.size >= 27 && payload.u(0) == 0x12 &&
            payload.u(1) == 0x19
        ) {
            return FindMyState(status = payload.u(2), separated = true)
        }
        if (payload.size == 4 && payload.u(0) == 0x12 &&
            payload.u(1) == 0x02
        ) {
            return FindMyState(status = payload.u(2), separated = false)
        }
        return null
    }

    // MARK: Nearby Info

    /** Only the verified code is labelled; the rest are shown numerically. */
    val nearbyActionLabels: Map<Int, String> = mapOf(
        0x0A to "watch worn & unlocked",
    )

    data class NearbyInfoState(
        val actionCode: Int,
        val statusFlags: Int,
        val dataFlags: Int?,
    ) {
        val actionLabel: String?
            get() = Continuity.nearbyActionLabels[actionCode]

        val isWatch: Boolean get() = actionCode == 0x0A

        val describe: String
            get() {
                val code = "nearby state 0x%02X".format(actionCode)
                val label = actionLabel
                return if (label != null) "$code ($label)" else code
            }
    }

    fun decodeNearbyInfo(message: Message): NearbyInfoState? {
        if (message.type != 0x10 || message.value.isEmpty()) return null
        val first = message.value.u(0)
        return NearbyInfoState(
            actionCode = first and 0x0F,
            statusFlags = (first shr 4) and 0x0F,
            dataFlags = if (message.value.size > 1) {
                message.value.u(1)
            } else {
                null
            },
        )
    }

    // MARK: Nearby Action

    val nearbyActionTypes: Map<Int, String> = mapOf(
        0x01 to "Apple TV setup",
        0x04 to "mobile backup",
        0x05 to "watch setup",
        0x06 to "Apple TV pair",
        0x07 to "internet relay",
        0x08 to "Wi-Fi password share",
        0x09 to "iOS setup",
        0x0A to "repair",
        0x0B to "speaker setup",
        0x0C to "Apple Pay",
        0x0D to "whole-home audio setup",
        0x0E to "developer tools pairing",
        0x0F to "answered call",
        0x10 to "ended call",
        0x11 to "DD ping",
        0x12 to "DD pong",
        0x13 to "remote AutoFill",
        0x14 to "companion link proximity",
        0x15 to "remote management",
        0x16 to "remote AutoFill pong",
        0x17 to "remote display",
    )

    data class NearbyActionState(val flags: Int, val actionType: Int) {
        val describe: String
            get() {
                val label = Continuity.nearbyActionTypes[actionType]
                    ?: "type 0x%02X".format(actionType)
                return "nearby action: $label"
            }
    }

    fun decodeNearbyAction(message: Message): NearbyActionState? {
        if (message.type != 0x0F || message.value.size < 2) return null
        return NearbyActionState(
            flags = message.value.u(0),
            actionType = message.value.u(1),
        )
    }

    // MARK: Tethering Source (Instant Hotspot)

    data class TetheringSourceState(val battery: Int?, val cellBars: Int?) {
        val describe: String
            get() {
                val parts = mutableListOf("hotspot-capable")
                if (battery != null) parts.add("battery $battery%")
                if (cellBars != null) parts.add("cell $cellBars bars")
                return parts.joinToString(", ")
            }
    }

    fun decodeTetheringSource(message: Message): TetheringSourceState? {
        val v = message.value
        if (message.type != 0x0E || v.size < 3) return null
        val battery: Int? = if (v.u(2) <= 100) v.u(2) else null
        val bars: Int? = if (v.size > 4 && v.u(4) <= 5) v.u(4) else null
        return TetheringSourceState(battery = battery, cellBars = bars)
    }

    // MARK: Putting it together

    data class Identification(
        val kind: String,
        val details: List<String>,
        val messages: List<String>,
        val findMy: FindMyState?,
        /** 1 family, 2 sub-family, 3 product. */
        val specificity: Int,
    ) {
        val describe: String
            get() = if (details.isEmpty()) {
                kind
            } else {
                "$kind — ${details.joinToString("; ")}"
            }
    }

    /** Identify an Apple device from its Continuity payload. */
    fun identifyApple(payload: ByteArray): Identification {
        val findMy = parseFindMy(payload)
        if (findMy != null) {
            val kind = if (findMy.separated) {
                "Find My device (AirTag-class)"
            } else {
                "Find My accessory (with owner)"
            }
            return Identification(
                kind = kind, details = listOf(findMy.describe),
                messages = listOf("Find My"), findMy = findMy,
                specificity = 3,
            )
        }
        val messages = parse(payload)
        val names = messages.map { it.typeName }
        val details = mutableListOf<String>()
        var kind = "Apple device"
        var specificity = 1
        for (message in messages) {
            when (message.type) {
                0x07 -> {
                    val state = decodeAirPods(message)
                    if (state != null) {
                        kind = state.model
                        specificity = 3
                        details.add(state.describe)
                    }
                }
                0x02 -> {
                    val beacon = decodeIBeacon(message)
                    if (beacon != null) {
                        kind = "iBeacon"
                        specificity = 3
                        details.add(beacon.describe)
                    }
                }
                0x10 -> {
                    val nearby = decodeNearbyInfo(message)
                    if (nearby != null) {
                        details.add(nearby.describe)
                        if (nearby.isWatch && specificity < 3) {
                            kind = "Apple Watch"
                            specificity = 2
                        }
                    }
                }
                0x0F -> {
                    val action = decodeNearbyAction(message)
                    if (action != null) {
                        details.add(action.describe)
                    }
                }
                0x0E -> {
                    val source = decodeTetheringSource(message)
                    if (source != null) {
                        details.add(source.describe)
                        if (specificity < 2) {
                            kind = "iPhone (Instant Hotspot source)"
                            specificity = 2
                        }
                    }
                }
                else -> Unit
            }
        }
        if (kind == "Apple device" && names.contains("Nearby Info")) {
            kind = "Apple device (Nearby Info)"
        }
        return Identification(
            kind = kind, details = details, messages = names,
            findMy = null, specificity = specificity,
        )
    }
}

// MARK: - Services (service UUIDs and service data)

/** Service UUIDs and service data — a port of Services.swift. */
object Services {
    val serviceNames: Map<Int, String> = mapOf(
        0x1800 to "Generic Access",
        0x1801 to "Generic Attribute",
        0x1802 to "Immediate Alert",
        0x1803 to "Link Loss",
        0x1804 to "Tx Power",
        0x1805 to "Current Time",
        0x1808 to "Glucose",
        0x1809 to "Health Thermometer",
        0x180A to "Device Information",
        0x180D to "Heart Rate",
        0x180F to "Battery",
        0x1810 to "Blood Pressure",
        0x1811 to "Alert Notification",
        0x1812 to "Human Interface Device",
        0x1814 to "Running Speed and Cadence",
        0x1816 to "Cycling Speed and Cadence",
        0x1818 to "Cycling Power",
        0x1819 to "Location and Navigation",
        0x181A to "Environmental Sensing",
        0x181B to "Body Composition",
        0x181C to "User Data",
        0x181D to "Weight Scale",
        0x181F to "Continuous Glucose Monitoring",
        0x1822 to "Pulse Oximeter",
        0x1826 to "Fitness Machine",
        0x1827 to "Mesh Provisioning",
        0x1828 to "Mesh Proxy",
        0x184E to "Audio Stream Control (LE Audio)",
        0x1850 to "Published Audio Capabilities (LE Audio)",
        0x1852 to "Broadcast Audio Announcement (LE Audio)",
        0x1853 to "Common Audio (LE Audio)",
        0x1854 to "Hearing Access (LE Audio)",
        0xFD3D to "SwitchBot",
        0xFFFA to "UAS Remote ID",
        0xFD43 to "Apple",
        0xFD44 to "Apple (Find My accessory)",
        0xFD5A to "Samsung SmartThings Find",
        0xFD6F to "Exposure Notification",
        0xFE03 to "Amazon",
        0xFE07 to "Sonos",
        0xFE0F to "Signify (Philips Hue)",
        0xFE2C to "Google Fast Pair",
        0xFE59 to "Nordic DFU",
        0xFE61 to "Logitech",
        0xFE95 to "Xiaomi",
        0xFE9F to "Google",
        0xFEAA to "Eddystone",
        0xFEBE to "Bose",
        0xFECA to "Apple", 0xFECB to "Apple", 0xFECC to "Apple",
        0xFECD to "Apple", 0xFECE to "Apple", 0xFECF to "Apple",
        0xFED0 to "Apple", 0xFED1 to "Apple", 0xFED2 to "Apple",
        0xFED3 to "Apple", 0xFED4 to "Apple",
        0xFEE0 to "Huami",
        0xFEE7 to "Tencent (WeChat)",
        0xFEEC to "Tile",
        0xFEED to "Tile",
        0xFEF3 to "Google",
        0xFEF4 to "Google",
    )

    const val fastPair: Int = 0xFE2C
    const val eddystone: Int = 0xFEAA
    const val exposureNotification: Int = 0xFD6F
    const val smartThingsFind: Int = 0xFD5A
    val tile: List<Int> = listOf(0xFEED, 0xFEEC)

    /** Full lowercase form of a short or long UUID string. */
    fun normalize(uuid: String): String {
        var text = uuid.trim().lowercase()
        if (text.startsWith("0x")) {
            text = text.substring(2)
        }
        val hex = "0123456789abcdef".toSet()
        if ((text.length == 4 || text.length == 8) &&
            text.all { it in hex }
        ) {
            val padded = "0".repeat(8 - text.length) + text
            return padded + sigBaseSuffix
        }
        return text
    }

    /** The 16-bit value of a SIG-base UUID, else null. */
    fun short(uuid: String): Int? {
        val text = normalize(uuid)
        if (text.length != 36 || !text.endsWith(sigBaseSuffix) ||
            !text.startsWith("0000")
        ) {
            return null
        }
        return text.substring(4, 8).toIntOrNull(16)
    }

    fun name(uuid: String): String? {
        val value = short(uuid) ?: return null
        return serviceNames[value]
    }

    // MARK: Eddystone (and Google's Find My Device network)

    val urlSchemes: Map<Int, String> = mapOf(
        0x00 to "http://www.", 0x01 to "https://www.",
        0x02 to "http://", 0x03 to "https://",
    )
    val urlExpansions: Map<Int, String> = mapOf(
        0x00 to ".com/", 0x01 to ".org/", 0x02 to ".edu/", 0x03 to ".net/",
        0x04 to ".info/", 0x05 to ".biz/", 0x06 to ".gov/",
        0x07 to ".com", 0x08 to ".org", 0x09 to ".edu", 0x0A to ".net",
        0x0B to ".info", 0x0C to ".biz", 0x0D to ".gov",
    )
    val frameNames: Map<Int, String> = mapOf(
        0x00 to "UID", 0x10 to "URL", 0x20 to "TLM", 0x30 to "EID",
        0x40 to "Find My Device network (20-byte EID)",
        0x41 to "Find My Device network (32-byte EID)",
    )

    data class EddystoneFrame(
        val frameType: Int,
        var txPower: Int? = null,
        var namespace: String? = null,
        var instance: String? = null,
        var url: String? = null,
        var batteryMv: Int? = null,
        var temperatureC: Double? = null,
        var advCount: Long? = null,
        var uptimeS: Double? = null,
        var eid: String? = null,
    ) {
        val frameName: String
            get() = Services.frameNames[frameType]
                ?: "frame 0x%02X".format(frameType)

        val isFMDN: Boolean get() = frameType == 0x40 || frameType == 0x41

        val describe: String
            get() {
                if (isFMDN) return "Find My Device network beacon (Google)"
                return when (frameType) {
                    0x00 -> "Eddystone-UID " +
                        "${namespace ?: ""}/${instance ?: ""}"
                    0x10 -> "Eddystone-URL ${url ?: ""}"
                    0x20 -> {
                        val parts = mutableListOf<String>()
                        val mv = batteryMv
                        if (mv != null && mv > 0) {
                            parts.add("battery $mv mV")
                        }
                        val temp = temperatureC
                        if (temp != null) {
                            parts.add("%.1f °C".format(temp))
                        }
                        val up = uptimeS
                        if (up != null) {
                            parts.add("up %.1f h".format(up / 3600))
                        }
                        "Eddystone-TLM" + if (parts.isEmpty()) {
                            ""
                        } else {
                            ": " + parts.joinToString(", ")
                        }
                    }
                    0x30 -> "Eddystone-EID ${eid ?: ""}"
                    else -> "Eddystone $frameName"
                }
            }
    }

    fun decodeEddystone(payload: ByteArray): EddystoneFrame? {
        if (payload.isEmpty()) return null
        val frameType = payload.u(0)
        val frame = EddystoneFrame(frameType = frameType)
        when {
            frameType == 0x00 && payload.size >= 18 -> {
                frame.txPower = payload[1].toInt()
                frame.namespace = payload.copyOfRange(2, 12).hexString()
                frame.instance = payload.copyOfRange(12, 18).hexString()
            }
            frameType == 0x10 && payload.size >= 3 -> {
                frame.txPower = payload[1].toInt()
                val url = StringBuilder(urlSchemes[payload.u(2)] ?: "")
                for (i in 3 until payload.size) {
                    val byte = payload.u(i)
                    val expansion = urlExpansions[byte]
                    if (expansion != null) {
                        url.append(expansion)
                    } else if (byte > 0x20 && byte < 0x7F) {
                        url.append(byte.toChar())
                    }
                }
                frame.url = url.toString()
            }
            frameType == 0x20 && payload.size >= 14 &&
                payload.u(1) == 0x00 -> {
                val battery = (payload.u(2) shl 8) or payload.u(3)
                frame.batteryMv = if (battery == 0) null else battery
                val rawTemp = ((payload.u(4) shl 8) or payload.u(5))
                    .toShort().toInt()
                frame.temperatureC =
                    if (payload.u(4) == 0x80 && payload.u(5) == 0x00) {
                        null
                    } else {
                        rawTemp / 256.0
                    }
                frame.advCount = (payload.u(6).toLong() shl 24) or
                    (payload.u(7).toLong() shl 16) or
                    (payload.u(8).toLong() shl 8) or
                    payload.u(9).toLong()
                val ticks = (payload.u(10).toLong() shl 24) or
                    (payload.u(11).toLong() shl 16) or
                    (payload.u(12).toLong() shl 8) or
                    payload.u(13).toLong()
                frame.uptimeS = ticks / 10.0
            }
            frameType == 0x30 && payload.size >= 10 -> {
                frame.txPower = payload[1].toInt()
                frame.eid = payload.copyOfRange(2, 10).hexString()
            }
            frameType == 0x40 || frameType == 0x41 -> {
                frame.eid = payload.copyOfRange(1, payload.size).hexString()
            }
            else -> Unit
        }
        return frame
    }

    // MARK: Fast Pair

    data class FastPairState(val modelID: Int?, val discoverable: Boolean) {
        val describe: String
            get() {
                val model = modelID
                if (discoverable && model != null) {
                    return "Fast Pair, discoverable (model 0x%06X)"
                        .format(model)
                }
                return "Fast Pair device (paired, not discoverable)"
            }
    }

    fun decodeFastPair(payload: ByteArray): FastPairState? {
        if (payload.isEmpty()) return null
        if (payload.size == 3) {
            val model = (payload.u(0) shl 16) or (payload.u(1) shl 8) or
                payload.u(2)
            return FastPairState(modelID = model, discoverable = true)
        }
        return FastPairState(modelID = null, discoverable = false)
    }

    // MARK: Putting it together

    data class Identification(
        val kind: String,
        val details: List<String>,
        val trackerShaped: Boolean,
        val rotatingPhone: Boolean,
        val specificity: Int,
        val preferredLabel: String? = null,
    )

    fun identify(
        serviceUUIDs: List<String>,
        serviceData: Map<String, ByteArray>,
    ): Identification? {
        val shorts = mutableMapOf<Int, String>()
        for (uuid in serviceUUIDs + serviceData.keys) {
            val value = short(uuid)
            if (value != null) {
                shorts[value] = normalize(uuid)
            }
        }
        val data = mutableMapOf<Int, ByteArray>()
        for ((uuid, payload) in serviceData) {
            val value = short(uuid)
            if (value != null) {
                data[value] = payload
            }
        }

        // Drones first: a Remote ID broadcast is unambiguous, and nothing
        // else uses 0xFFFA. Same order as the Python classify().
        val rid = data[Drones.remoteIDService]
        if (rid != null) {
            val report = Drones.report(rid)
            if (report != null) {
                return Identification(
                    kind = "Drone (Remote ID)",
                    details = listOf(Drones.describe(report)),
                    trackerShaped = false, rotatingPhone = false,
                    specificity = 3,
                    preferredLabel = report.serial?.let { "Drone $it" },
                )
            }
        }
        if (shorts.containsKey(eddystone)) {
            val frame = decodeEddystone(data[eddystone] ?: ByteArray(0))
            if (frame != null) {
                if (frame.isFMDN) {
                    return Identification(
                        kind = "Find My Device network tag (Google)",
                        details = listOf(frame.describe),
                        trackerShaped = true, rotatingPhone = false,
                        specificity = 3,
                    )
                }
                return Identification(
                    kind = "Eddystone beacon (${frame.frameName})",
                    details = listOf(frame.describe),
                    trackerShaped = false, rotatingPhone = false,
                    specificity = 3,
                )
            }
            return Identification(
                kind = "Eddystone beacon", details = emptyList(),
                trackerShaped = false, rotatingPhone = false,
                specificity = 2,
            )
        }
        if (shorts.containsKey(fastPair)) {
            val state = decodeFastPair(data[fastPair] ?: ByteArray(0))
            return Identification(
                kind = "Fast Pair device (Google)",
                details = state?.let { listOf(it.describe) }
                    ?: emptyList(),
                trackerShaped = false, rotatingPhone = false,
                specificity = 2,
            )
        }
        if (shorts.containsKey(exposureNotification)) {
            return Identification(
                kind = "Phone (Exposure Notification)",
                details = listOf(
                    "contact-tracing beacon; rotates every ~15 min"
                ),
                trackerShaped = false, rotatingPhone = true,
                specificity = 2,
            )
        }
        if (tile.any { shorts.containsKey(it) }) {
            return Identification(
                kind = "Tile tracker", details = emptyList(),
                trackerShaped = true, rotatingPhone = false,
                specificity = 3,
            )
        }
        if (shorts.containsKey(smartThingsFind)) {
            return Identification(
                kind = "SmartThings Find device (Samsung tag or Galaxy)",
                details = emptyList(),
                trackerShaped = true, rotatingPhone = false,
                specificity = 2,
            )
        }
        val named = shorts.keys.mapNotNull { serviceNames[it] }
            .toSet().sorted()
        if (named.isNotEmpty()) {
            return Identification(
                kind = "Device advertising " + named.joinToString(", "),
                details = emptyList(),
                trackerShaped = false, rotatingPhone = false,
                specificity = 1,
            )
        }
        return null
    }
}

// MARK: - Vendors (other makers' manufacturer data)

/**
 * Other makers' manufacturer data, and the company-id table — a port of
 * Vendors.swift.
 */
object Vendors {
    const val microsoft: Int = 0x0006
    const val ruuvi: Int = 0x0499

    val companyNames: Map<Int, String> = mapOf(
        0x0000 to "Ericsson", 0x0001 to "Nokia", 0x0002 to "Intel",
        0x0003 to "IBM", 0x0004 to "Toshiba", 0x0006 to "Microsoft",
        0x0008 to "Motorola", 0x0009 to "Infineon",
        0x000A to "Cambridge Silicon Radio", 0x000D to "Texas Instruments",
        0x000F to "Broadcom", 0x0013 to "Atmel", 0x001D to "Qualcomm",
        0x0022 to "NEC", 0x0025 to "NXP Semiconductors", 0x0029 to "Hitachi",
        0x0030 to "ST Microelectronics", 0x0036 to "Renesas",
        0x003A to "Panasonic", 0x003C to "BlackBerry", 0x0040 to "Seiko Epson",
        0x0044 to "Socket Mobile", 0x0046 to "MediaTek", 0x0047 to "Bluegiga",
        0x0048 to "Marvell", 0x004C to "Apple", 0x0055 to "Plantronics",
        0x0056 to "Sony Ericsson", 0x0057 to "Harman", 0x0058 to "Vizio",
        0x0059 to "Nordic Semiconductor", 0x005C to "Belkin",
        0x005D to "Realtek", 0x0065 to "HP", 0x0067 to "GN Audio (Jabra)",
        0x0068 to "General Motors", 0x006B to "Polar", 0x0075 to "Samsung",
        0x0076 to "Creative", 0x0078 to "Nike", 0x0082 to "Sennheiser",
        0x0087 to "Garmin", 0x0089 to "GN Hearing", 0x008A to "Jawbone",
        0x008C to "Gimbal", 0x009E to "Bose", 0x009F to "Suunto",
        0x00A0 to "Kensington", 0x00B9 to "Johnson Controls",
        0x00BA to "Starkey Hearing", 0x00C4 to "LG Electronics",
        0x00CC to "Beats", 0x00CD to "Microchip", 0x00CE to "Elgato",
        0x00D0 to "Dexcom", 0x00D2 to "Dialog Semiconductor", 0x00D6 to "Timex",
        0x00D7 to "Qualcomm Technologies", 0x00D9 to "Turtle Beach",
        0x00E0 to "Google", 0x00E8 to "Lenovo", 0x0118 to "Radius Networks",
        0x012D to "Sony", 0x0131 to "Cypress Semiconductor",
        0x0157 to "Huami (Zepp / Mi Band)", 0x0171 to "Amazon",
        0x01AB to "Meta (Facebook)", 0x01DA to "Logitech", 0x027D to "Huawei",
        0x02E1 to "Victron Energy", 0x02E5 to "Espressif",
        0x02FF to "Silicon Labs", 0x038F to "Xiaomi", 0x0499 to "Ruuvi",
        0x0553 to "Nintendo", 0x05A7 to "Sonos", 0x0969 to "SwitchBot (Woan)",
        0xFFFF to "(reserved / test)",
    )

    fun companyName(id: Int): String =
        companyNames[id] ?: "0x%04X".format(id)

    /** MS-CDP beacon device types. */
    val cdpDeviceTypes: Map<Int, String> = mapOf(
        1 to "Xbox One", 6 to "iPhone (CDP)", 7 to "iPad (CDP)",
        8 to "Android device (CDP)", 9 to "Windows desktop",
        11 to "Windows phone", 12 to "Linux device (CDP)",
        13 to "Windows IoT device", 14 to "Surface Hub",
        15 to "Windows laptop", 16 to "Windows tablet",
    )

    val familyByCompany: Map<Int, String> = mapOf(
        0x0059 to "Nordic-chip device", 0x0075 to "Samsung device",
        0x0087 to "Garmin device", 0x009E to "Bose device",
        0x00E0 to "Google device", 0x012D to "Sony device",
        0x0157 to "Huami wearable (Mi Band / Amazfit)",
        0x0171 to "Amazon device", 0x01DA to "Logitech device",
        0x027D to "Huawei device", 0x02E5 to "ESP32 device",
        0x038F to "Xiaomi device", 0x0553 to "Nintendo controller",
        0x05A7 to "Sonos speaker", 0x0969 to "SwitchBot device",
    )

    data class Identification(
        val kind: String,
        val details: List<String>,
        val specificity: Int,
    )

    // MARK: Microsoft

    fun decodeMicrosoft(payload: ByteArray): Identification? {
        if (payload.isEmpty()) return null
        val first = payload.u(0)
        if (first == 0x03 && payload.size >= 3) {
            val details = mutableListOf("in pairing mode (Swift Pair)")
            val nameBytes = payload.copyOfRange(3, payload.size)
            val name = decodeUtf8Strict(nameBytes)
                ?.trim { it == '\u0000' || it.isWhitespace() }
            if (!name.isNullOrEmpty()) {
                details.add("announces itself as '$name'")
            }
            return Identification(
                kind = "Windows device (Swift Pair)", details = details,
                specificity = 2,
            )
        }
        if (first == 0x01 && payload.size >= 2) {
            val deviceType = payload.u(1) and 0x1F
            val kind = cdpDeviceTypes[deviceType]
                ?: "CDP device type $deviceType"
            return Identification(
                kind = kind, details = listOf("Microsoft CDP beacon"),
                specificity = 2,
            )
        }
        return Identification(
            kind = "Microsoft device", details = emptyList(),
            specificity = 1,
        )
    }

    // MARK: Ruuvi RAWv2

    fun decodeRuuvi(payload: ByteArray): String? {
        if (payload.size < 24 || payload.u(0) != 0x05) return null
        val tempRaw = ((payload.u(1) shl 8) or payload.u(2))
            .toShort().toInt()
        val humRaw = (payload.u(3) shl 8) or payload.u(4)
        val presRaw = (payload.u(5) shl 8) or payload.u(6)
        val power = (payload.u(13) shl 8) or payload.u(14)
        val parts = mutableListOf<String>()
        if (tempRaw != -32768) {
            parts.add("%.2f °C".format(tempRaw * 0.005))
        }
        if (humRaw != 0xFFFF) {
            parts.add("%.1f%% RH".format(humRaw * 0.0025))
        }
        if (presRaw != 0xFFFF) {
            parts.add("%.1f hPa".format((presRaw + 50000) / 100.0))
        }
        if ((power shr 5) != 2047) {
            parts.add("battery ${(power shr 5) + 1600} mV")
        }
        return if (parts.isEmpty()) {
            "RuuviTag"
        } else {
            "RuuviTag: " + parts.joinToString(", ")
        }
    }

    // MARK: Dispatch

    fun identify(manufacturerData: Map<Int, ByteArray>): Identification? {
        val msPayload = manufacturerData[microsoft]
        if (msPayload != null) {
            val ident = decodeMicrosoft(msPayload)
            if (ident != null) {
                return ident
            }
        }
        val ruuviPayload = manufacturerData[ruuvi]
        if (ruuviPayload != null) {
            val reading = decodeRuuvi(ruuviPayload)
            if (reading != null) {
                return Identification(
                    kind = "RuuviTag sensor", details = listOf(reading),
                    specificity = 3,
                )
            }
            return Identification(
                kind = "Ruuvi device", details = emptyList(),
                specificity = 2,
            )
        }
        for (company in manufacturerData.keys.sorted()) {
            val family = familyByCompany[company]
            if (family != null) {
                return Identification(
                    kind = family, details = emptyList(), specificity = 1,
                )
            }
        }
        for (company in manufacturerData.keys.sorted()) {
            val name = companyName(company)
            if (!name.startsWith("0x")) {
                return Identification(
                    kind = "$name device", details = emptyList(),
                    specificity = 1,
                )
            }
        }
        return null
    }
}

// MARK: - Drones (FAA Remote ID / Open Drone ID)

/**
 * Drones — reading the digital licence plate, a port of Drones.swift.
 *
 * Under the FAA's Remote ID rule (ASTM F3411 / Open Drone ID), nearly
 * every camera drone must broadcast what it is, where it is, and where
 * its operator is standing — and one of the mandated transports is a
 * plain BLE advertisement, the stream this app already listens to. The
 * broadcasts are public by design: any receiver is an intended audience.
 *
 * A legacy advertisement carries service data for UUID 0xFFFA:
 * `[0x0D][counter][one 25-byte message]`. Each advertisement carries one
 * message; a drone cycles through its set over seconds.
 */
object Drones {
    const val remoteIDService: Int = 0xFFFA
    const val appCode: Int = 0x0D
    const val messageSize: Int = 25

    /** System timestamps are seconds since 2019-01-01T00:00:00Z. */
    const val epoch2019: Double = 1_546_300_800.0

    val idTypes: Map<Int, String> = mapOf(
        0 to "none", 1 to "serial number", 2 to "CAA registration",
        3 to "UTM UUID", 4 to "specific session ID",
    )
    val uaTypes: Map<Int, String> = mapOf(
        0 to "none", 1 to "aeroplane", 2 to "helicopter/multirotor",
        3 to "gyroplane", 4 to "hybrid lift (VTOL)", 5 to "ornithopter",
        6 to "glider", 7 to "kite", 8 to "free balloon",
        9 to "captive balloon", 10 to "airship",
        11 to "free fall / parachute", 12 to "rocket",
        13 to "tethered powered aircraft", 14 to "ground obstacle",
        15 to "other",
    )
    val operationalStatus: Map<Int, String> = mapOf(
        0 to "undeclared", 1 to "ground", 2 to "airborne", 3 to "emergency",
        4 to "RID system failure",
    )
    val operatorLocationTypes: Map<Int, String> = mapOf(
        0 to "takeoff point", 1 to "live GPS", 2 to "fixed",
    )

    // MARK: Messages

    data class BasicID(
        val idType: Int,
        val uaType: Int,
        val uasID: String,
    ) {
        val idTypeName: String
            get() = Drones.idTypes[idType] ?: "type $idType"
        val uaTypeName: String
            get() = Drones.uaTypes[uaType] ?: "type $uaType"

        /** Serial number or CAA registration: stable, device-identifying. */
        val isSerial: Boolean
            get() = (idType == 1 || idType == 2) && uasID.isNotEmpty()
    }

    data class Location(
        val status: Int,
        val direction: Double?,
        val speedH: Double?,
        val speedV: Double?,
        val latitude: Double?,
        val longitude: Double?,
        val altitudeBaro: Double?,
        val altitudeGeo: Double?,
        val height: Double?,
        val heightType: Int,
        val timestampTenths: Int?,
    ) {
        val statusName: String
            get() = Drones.operationalStatus[status] ?: "status $status"
        val airborne: Boolean get() = status == 2
        val heightRef: String
            get() = if (heightType == 1) "AGL" else "above takeoff"
    }

    data class SystemInfo(
        val operatorLatitude: Double?,
        val operatorLongitude: Double?,
        val operatorLocationType: Int,
        val areaCount: Int,
        val areaRadiusM: Int,
        val areaCeiling: Double?,
        val areaFloor: Double?,
        val category: Int,
        val uaClass: Int,
        val operatorAltitude: Double?,
        val timestampUnix: Double?,
    ) {
        val operatorLocationName: String
            get() = Drones.operatorLocationTypes[operatorLocationType]
                ?: "type $operatorLocationType"
    }

    data class Message(
        val typeID: Int,
        val protoVersion: Int,
        var basicID: BasicID? = null,
        var location: Location? = null,
        var system: SystemInfo? = null,
        var selfIDText: String? = null,
        var operatorID: String? = null,
    )

    // MARK: Byte helpers (little-endian, like the Python)

    private fun u16(b: ByteArray, off: Int): Int =
        b.u(off) or (b.u(off + 1) shl 8)

    private fun i32(b: ByteArray, off: Int): Int =
        b.u(off) or (b.u(off + 1) shl 8) or (b.u(off + 2) shl 16) or
            (b.u(off + 3) shl 24)

    private fun u32(b: ByteArray, off: Int): Long =
        b.u(off).toLong() or (b.u(off + 1).toLong() shl 8) or
            (b.u(off + 2).toLong() shl 16) or
            (b.u(off + 3).toLong() shl 24)

    /** uint16 → metres = raw × 0.5 − 1000; raw 0 is the invalid marker. */
    private fun altitude(raw: Int): Double? =
        if (raw == 0) null else raw * 0.5 - 1000.0

    /** int32 × 1e-7 degrees; 0 means no fix. */
    private fun latlon(raw: Int): Double? =
        if (raw == 0) null else raw / 1e7

    /**
     * The Swift ASCII decode: bytes up to the first NUL; a byte outside
     * ASCII fails the whole decode (yielding ""), and the result is
     * whitespace-trimmed.
     */
    private fun ascii(bytes: ByteArray): String {
        val out = StringBuilder()
        for (byte in bytes) {
            if (byte == 0.toByte()) break
            if (byte.u() > 0x7F) return ""
            out.append(byte.u().toChar())
        }
        return out.toString().trim { it.isWhitespace() }
    }

    // MARK: Decoding

    fun decodeMessage(msg: ByteArray): Message? {
        if (msg.size < messageSize) return null
        val typeID = msg.u(0) shr 4
        val message = Message(
            typeID = typeID, protoVersion = msg.u(0) and 0x0F,
        )
        when (typeID) {
            0x0 -> { // Basic ID
                message.basicID = BasicID(
                    idType = msg.u(1) shr 4,
                    uaType = msg.u(1) and 0x0F,
                    uasID = ascii(msg.copyOfRange(2, 22)),
                )
            }
            0x1 -> { // Location
                val flags = msg.u(1)
                val eastWest = (flags shr 1) and 1
                val directionRaw = msg.u(2)
                val speedMult = flags and 1
                val speedRaw = msg.u(3).toDouble()
                val tsRaw = u16(msg, 21)
                message.location = Location(
                    status = (flags shr 4) and 0x0F,
                    direction = if (directionRaw == 0xFF) {
                        null
                    } else if (eastWest == 1) {
                        directionRaw + 180.0
                    } else {
                        directionRaw.toDouble()
                    },
                    speedH = if (speedMult == 0) {
                        speedRaw * 0.25
                    } else {
                        speedRaw * 0.75 + 63.75
                    },
                    speedV = msg[4].toInt() * 0.5,
                    latitude = latlon(i32(msg, 5)),
                    longitude = latlon(i32(msg, 9)),
                    altitudeBaro = altitude(u16(msg, 13)),
                    altitudeGeo = altitude(u16(msg, 15)),
                    height = altitude(u16(msg, 17)),
                    heightType = (flags shr 2) and 1,
                    timestampTenths = if (tsRaw == 0xFFFF) null else tsRaw,
                )
            }
            0x4 -> { // System
                val flags = msg.u(1)
                val tsRaw = u32(msg, 20)
                message.system = SystemInfo(
                    operatorLatitude = latlon(i32(msg, 2)),
                    operatorLongitude = latlon(i32(msg, 6)),
                    operatorLocationType = flags and 0x3,
                    areaCount = u16(msg, 10),
                    areaRadiusM = msg.u(12) * 10,
                    areaCeiling = altitude(u16(msg, 13)),
                    areaFloor = altitude(u16(msg, 15)),
                    category = msg.u(17) shr 4,
                    uaClass = msg.u(17) and 0x0F,
                    operatorAltitude = altitude(u16(msg, 18)),
                    timestampUnix = if (tsRaw == 0L) {
                        null
                    } else {
                        tsRaw.toDouble() + epoch2019
                    },
                )
            }
            0x3 -> { // Self ID
                message.selfIDText = ascii(msg.copyOfRange(2, 25))
            }
            0x5 -> { // Operator ID
                message.operatorID = ascii(msg.copyOfRange(2, 22))
            }
            else -> Unit // Authentication and anything else: recognized, not decoded.
        }
        return message
    }

    /**
     * Decode a 0xFFFA service-data value into its message(s): one for a
     * legacy advertisement, several for a Message Pack.
     */
    fun parseServiceData(value: ByteArray): List<Message> {
        if (value.size < 2 || value.u(0) != appCode) return emptyList()
        val body = value.copyOfRange(2, value.size)
        if (body.isEmpty()) return emptyList()
        if (body.u(0) shr 4 == 0xF) {
            return parsePack(body)
        }
        val message = decodeMessage(
            body.copyOfRange(0, minOf(messageSize, body.size))
        )
        return if (message != null) listOf(message) else emptyList()
    }

    private fun parsePack(body: ByteArray): List<Message> {
        if (body.size < 3) return emptyList()
        val single = if (body.u(1) == 0) messageSize else body.u(1)
        val count = body.u(2)
        val messages = mutableListOf<Message>()
        for (i in 0 until count) {
            val start = 3 + i * single
            // The stride is attacker-controlled (a byte in the
            // advertisement): never slice past the body, and a
            // stride smaller than one message cannot hold one.
            if (single < messageSize || start + single > body.size) break
            val message = decodeMessage(
                body.copyOfRange(start, start + messageSize)
            )
            if (message != null) {
                messages.add(message)
            }
        }
        return messages
    }

    // MARK: A drone, assembled from one value

    data class Report(
        var serial: String? = null,
        var uaType: Int? = null,
        var idType: Int? = null,
        var location: Location? = null,
        var system: SystemInfo? = null,
        var selfIDText: String? = null,
        var operatorID: String? = null,
        var authPages: Int = 0,
    ) {
        fun ingest(message: Message) {
            val basic = message.basicID
            if (basic != null) {
                if (basic.isSerial) serial = basic.uasID
                uaType = basic.uaType
                idType = basic.idType
            }
            if (message.location != null) location = message.location
            if (message.system != null) system = message.system
            val text = message.selfIDText
            if (text != null && text.isNotEmpty()) selfIDText = text
            val op = message.operatorID
            if (op != null && op.isNotEmpty()) operatorID = op
            if (message.typeID == 0x2) authPages += 1
        }

        val uaTypeName: String
            get() = uaType?.let { Drones.uaTypes[it] } ?: "aircraft"
        val airborne: Boolean get() = location?.airborne ?: false
    }

    /** The Remote ID report for one service-data value, as Services calls it. */
    fun report(fromServiceData: ByteArray): Report? {
        val messages = parseServiceData(fromServiceData)
        if (messages.isEmpty()) return null
        val report = Report()
        for (message in messages) {
            report.ingest(message)
        }
        return report
    }

    // MARK: Describing (mirrors Drones.describe in the Swift app)

    private val compassPoints: List<String> =
        listOf("N", "NE", "E", "SE", "S", "SW", "W", "NW")

    fun compass(bearing: Double): String {
        val idx = ((bearing % 360) / 45 + 0.5).toInt() % 8
        return compassPoints[(idx + 8) % 8]
    }

    fun describe(report: Report): String {
        val parts = mutableListOf<String>()
        val serial = report.serial
        if (serial != null) parts.add("serial $serial")
        val ua = report.uaType
        if (ua != null && ua != 0) parts.add(report.uaTypeName)
        val loc = report.location
        if (loc != null) {
            parts.add(loc.statusName)
            val altGeo = loc.altitudeGeo
            val altBaro = loc.altitudeBaro
            if (altGeo != null) {
                parts.add("alt %.0f m".format(altGeo))
            } else if (altBaro != null) {
                parts.add("baro alt %.0f m".format(altBaro))
            }
            val speed = loc.speedH
            val dir = loc.direction
            if (speed != null && dir != null) {
                parts.add("%.1f m/s %s".format(speed, compass(dir)))
            } else if (speed != null) {
                parts.add("%.1f m/s".format(speed))
            }
            val height = loc.height
            if (height != null) {
                parts.add("height %.0f m %s".format(height, loc.heightRef))
            }
        }
        val sys = report.system
        if (sys != null && sys.operatorLatitude != null &&
            sys.operatorLongitude != null
        ) {
            parts.add(
                "operator %.5f,%.5f (%s)".format(
                    sys.operatorLatitude, sys.operatorLongitude,
                    sys.operatorLocationName,
                )
            )
        }
        val text = report.selfIDText
        if (text != null) {
            parts.add("“$text”")
        }
        return if (parts.isEmpty()) {
            "Drone (Remote ID)"
        } else {
            "Drone (Remote ID): " + parts.joinToString(", ")
        }
    }
}
