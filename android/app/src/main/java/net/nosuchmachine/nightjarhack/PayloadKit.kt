package net.nosuchmachine.nightjarhack

import java.io.ByteArrayOutputStream
import java.util.Base64
import java.util.zip.GZIPOutputStream

/// Byte-work for the mouth: payload building, framing, display —
/// a port of PayloadKit in the iOS app (which mirrors send.py).
object PayloadKit {

    class PayloadError(message: String) : Exception(message)

    fun decodeHex(raw: String): ByteArray {
        val compact = raw.replace(":", "").replace(" ", "")
            .replace("-", "").replace("\n", "")
        if (compact.length % 2 != 0) {
            throw PayloadError("could not decode hex payload: odd number of digits")
        }
        val out = ByteArray(compact.length / 2)
        var i = 0
        while (i < compact.length) {
            val byte = compact.substring(i, i + 2).toIntOrNull(16)
                ?: throw PayloadError("could not decode hex payload: bad digits")
            out[i / 2] = byte.toByte()
            i += 2
        }
        return out
    }

    fun encodeHex(data: ByteArray): String =
        data.joinToString("") { "%02x".format(it) }

    /// Mirrors send.py's _xor_key: hex when the spec parses as
    /// hex, else its UTF-8 bytes.
    fun xorKey(spec: String): ByteArray {
        var text = spec.trim()
        if (text.lowercase().startsWith("0x")) text = text.substring(2)
        val compact = text.replace(":", "").replace(" ", "")
        val hexDigits = "0123456789abcdefABCDEF".toSet()
        if (compact.isNotEmpty() && compact.length % 2 == 0 &&
            compact.all { it in hexDigits }
        ) {
            try {
                return decodeHex(compact)
            } catch (_: PayloadError) {
            }
        }
        return spec.toByteArray(Charsets.UTF_8)
    }

    fun xor(data: ByteArray, key: ByteArray): ByteArray {
        if (key.isEmpty()) return data
        return ByteArray(data.size) { i -> (data[i].toInt() xor key[i % key.size].toInt()).toByte() }
    }

    fun build(
        source: String, text: String, hex: String, b64: String,
        xorSpec: String, useGzip: Boolean
    ): ByteArray {
        var data: ByteArray = when (source) {
            "hex" -> decodeHex(hex)
            "base64" -> try {
                Base64.getMimeDecoder().decode(b64)
            } catch (_: IllegalArgumentException) {
                throw PayloadError("could not decode base64 payload")
            }
            else -> text.toByteArray(Charsets.UTF_8)
        }
        if (xorSpec.isNotEmpty()) data = xor(data, xorKey(xorSpec))
        if (useGzip) data = gzipCompress(data)
        return data
    }

    fun gzipCompress(data: ByteArray): ByteArray {
        val out = ByteArrayOutputStream()
        GZIPOutputStream(out).use { it.write(data) }
        return out.toByteArray()
    }

    // MARK: Templating — single pass, text source only, mirroring
    // the iOS substitutions against the parsed target.

    fun substitute(raw: String, target: SendTarget?, ownIP: String?): String {
        if (target == null) return raw
        val host: String
        val port: Int
        val scheme: String
        when (target) {
            is SendTarget.Tcp -> {
                host = target.host; port = target.port
                scheme = if (target.tls) "tcp+tls" else "tcp"
            }
            is SendTarget.Udp -> {
                host = target.host; port = target.port; scheme = "udp"
            }
            is SendTarget.Http -> {
                host = target.url.host ?: ""; port =
                    if (target.url.port >= 0) target.url.port
                    else if (target.https) 443 else 80
                scheme = target.url.protocol
            }
            else -> return raw
        }
        return raw.replace("{{host}}", host)
            .replace("{{port}}", port.toString())
            .replace("{{ip}}", ownIP ?: "")
            .replace("{{target}}", target.raw)
            .replace("{{scheme}}", scheme)
    }

    // MARK: Framing

    fun frame(data: ByteArray, framing: String): ByteArray {
        return when (framing) {
            "len" -> {
                val n = data.size
                byteArrayOf(
                    ((n shr 24) and 0xFF).toByte(), ((n shr 16) and 0xFF).toByte(),
                    ((n shr 8) and 0xFF).toByte(), (n and 0xFF).toByte()
                ) + data
            }
            "json" -> {
                val envelope = org.json.JSONObject()
                envelope.put("ts", System.currentTimeMillis() / 1000.0)
                envelope.put("tool", "nightjar-send")
                envelope.put("encoding", "base64")
                envelope.put("payload", Base64.getEncoder().encodeToString(data))
                envelope.toString().toByteArray(Charsets.UTF_8)
            }
            else -> data
        }
    }

    fun unframe(data: ByteArray, framing: String): ByteArray {
        if (framing == "len" && data.size >= 4) {
            val size = ((data[0].toInt() and 0xFF) shl 24) or
                ((data[1].toInt() and 0xFF) shl 16) or
                ((data[2].toInt() and 0xFF) shl 8) or (data[3].toInt() and 0xFF)
            val end = minOf(data.size, 4 + size)
            return data.copyOfRange(4, end)
        }
        if (framing == "json") {
            try {
                val obj = org.json.JSONObject(String(data, Charsets.UTF_8))
                val payload = obj.optString("payload", "")
                if (payload.isNotEmpty()) {
                    return Base64.getMimeDecoder().decode(payload)
                }
            } catch (_: Exception) {
            }
        }
        return data
    }

    // MARK: Display

    /// The data as displayable text, when it decodes as UTF-8
    /// and holds nothing but printable characters, whitespace
    /// and newlines — else null (callers show the hexdump).
    fun printableText(data: ByteArray): String? {
        if (data.isEmpty()) return null
        val text = try {
            String(data, Charsets.UTF_8)
        } catch (_: Exception) {
            return null
        }
        if (text.isEmpty()) return null
        for (ch in text) {
            if (ch.isISOControl() && ch != '\n' && ch != '\r' && ch != '\t') {
                return null
            }
        }
        return text
    }

    /// Same layout as send.py's hexdump: offset, spaced hex, glyphs.
    fun hexdump(data: ByteArray, width: Int = 16): String {
        if (data.isEmpty()) return "    (empty)"
        val lines = mutableListOf<String>()
        var offset = 0
        while (offset < data.size) {
            val chunk = data.copyOfRange(offset, minOf(offset + width, data.size))
            val hexes = chunk.joinToString(" ") { "%02x".format(it) }
            val glyphs = chunk.joinToString("") {
                val v = it.toInt() and 0xFF
                if (v in 32 until 127) v.toChar().toString() else "."
            }
            lines.add("    %08x  %-48s  %s".format(offset, hexes, glyphs))
            offset += width
        }
        return lines.joinToString("\n")
    }

    // MARK: PayPlant builders — payloads a target service stores

    private fun mqttRemainingLength(value: Int): ByteArray {
        val out = mutableListOf<Byte>()
        var n = value
        do {
            var byte = n % 128
            n /= 128
            if (n > 0) byte = byte or 0x80
            out.add(byte.toByte())
        } while (n > 0)
        return out.toByteArray()
    }

    fun mqttConnect(clientID: String): ByteArray {
        if (clientID.toByteArray(Charsets.UTF_8).size >= 65536) return ByteArray(0)
        val body = ByteArrayOutputStream()
        body.write(byteArrayOf(0x00, 0x04))
        body.write("MQTT".toByteArray(Charsets.UTF_8))
        body.write(byteArrayOf(0x04, 0x02, 0x00, 0x3C))
        val idBytes = clientID.toByteArray(Charsets.UTF_8)
        body.write((idBytes.size shr 8) and 0xFF)
        body.write(idBytes.size and 0xFF)
        body.write(idBytes)
        val packet = ByteArrayOutputStream()
        packet.write(0x10)
        packet.write(mqttRemainingLength(body.size()))
        packet.write(body.toByteArray())
        return packet.toByteArray()
    }

    /// A QoS 0 PUBLISH. With retain set, the broker keeps the
    /// message and hands it to every future subscriber — the plant.
    fun mqttPublish(topic: String, payload: ByteArray, retain: Boolean): ByteArray {
        if (topic.toByteArray(Charsets.UTF_8).size >= 65536) return ByteArray(0)
        val body = ByteArrayOutputStream()
        val topicBytes = topic.toByteArray(Charsets.UTF_8)
        body.write((topicBytes.size shr 8) and 0xFF)
        body.write(topicBytes.size and 0xFF)
        body.write(topicBytes)
        body.write(payload)
        val packet = ByteArrayOutputStream()
        packet.write(if (retain) 0x31 else 0x30)
        packet.write(mqttRemainingLength(body.size()))
        packet.write(body.toByteArray())
        return packet.toByteArray()
    }

    fun redisCommand(parts: List<String>): ByteArray {
        val out = StringBuilder()
        out.append("*${parts.size}\r\n")
        for (part in parts) {
            out.append("\$${part.toByteArray(Charsets.UTF_8).size}\r\n$part\r\n")
        }
        return out.toString().toByteArray(Charsets.UTF_8)
    }

    fun memcachedSet(key: String, value: String): ByteArray =
        "set $key 0 0 ${value.toByteArray(Charsets.UTF_8).size}\r\n$value\r\n"
            .toByteArray(Charsets.UTF_8)
}

/// Targets — mirrors parse_target in send.py, reduced the same
/// way the iOS app reduces it (plus Android's reach: a BLE write
/// names a MAC directly, because Android shows real addresses).
sealed class SendTarget {
    abstract val raw: String

    data class Tcp(val host: String, val port: Int, val tls: Boolean) : SendTarget() {
        override val raw: String get() = "${if (tls) "tcp+tls" else "tcp"}://$host:$port"
    }

    data class Udp(val host: String, val port: Int) : SendTarget() {
        override val raw: String get() = "udp://$host:$port"
    }

    data class Http(val url: java.net.URL, val https: Boolean) : SendTarget() {
        override val raw: String get() = url.toString()
    }

    object BleBeacon : SendTarget() {
        override val raw: String get() = "ble://"
    }

    object BleGatt : SendTarget() {
        override val raw: String get() = "ble-gatt://"
    }

    data class BleWrite(val address: String) : SendTarget() {
        override val raw: String get() = "ble-write://$address"
    }

    companion object {
        fun parse(rawText: String): SendTarget {
            val text = rawText.trim()
            fun bad(): Nothing =
                throw PayloadKit.PayloadError("could not parse target: $text")
            if (text == "ble://") return BleBeacon
            if (text == "ble-gatt://") return BleGatt
            if (text.startsWith("ble-write://")) {
                val address = text.removePrefix("ble-write://")
                if (address.isEmpty()) bad()
                return BleWrite(address)
            }
            if (text.startsWith("http://") || text.startsWith("https://")) {
                val url = try {
                    java.net.URL(text)
                } catch (_: Exception) {
                    bad()
                }
                return Http(url, text.startsWith("https://"))
            }
            val schemeEnd = text.indexOf("://")
            if (schemeEnd < 0) bad()
            val scheme = text.substring(0, schemeEnd)
            val rest = text.substring(schemeEnd + 3)
            val colon = rest.lastIndexOf(':')
            if (colon < 0) bad()
            val host = rest.substring(0, colon)
            val port = rest.substring(colon + 1).toIntOrNull() ?: bad()
            if (host.isEmpty() || port !in 0..65535) bad()
            return when (scheme) {
                "tcp" -> Tcp(host, port, false)
                "tcp+tls", "tls" -> Tcp(host, port, true)
                "udp" -> Udp(host, port)
                else -> bad()
            }
        }
    }
}
