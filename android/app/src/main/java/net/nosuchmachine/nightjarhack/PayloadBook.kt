package net.nosuchmachine.nightjarhack

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class SavedPayload(
    val name: String,
    val source: String,   // text | hex | base64
    val text: String,
    val xorKey: String = "",
    val useGzip: Boolean = false,
    val framing: String = "raw",
    val builtIn: Boolean = false
) {
    fun build(ownIP: String?, target: SendTarget?): ByteArray {
        val substituted = if (source == "text" && target != null) {
            PayloadKit.substitute(text, target, ownIP)
        } else {
            text
        }
        return PayloadKit.build(
            source = source,
            text = substituted,
            hex = if (source == "hex") text else "",
            b64 = if (source == "base64") text else "",
            xorSpec = xorKey, useGzip = useGzip
        )
    }
}

/// The payload library — the same 19 built-ins as the iOS app,
/// persisted the same way (UserDefaults there, a JSON file here).
class PayloadBook(context: Context) {
    private val file = File(context.filesDir, "payloadBook.v1.json")

    private val _items = MutableStateFlow<List<SavedPayload>>(emptyList())
    val items: StateFlow<List<SavedPayload>> = _items

    init {
        _items.value = load()
    }

    private fun load(): List<SavedPayload> {
        if (!file.exists()) return builtIns
        return try {
            val array = JSONArray(file.readText())
            val out = mutableListOf<SavedPayload>()
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                out.add(
                    SavedPayload(
                        name = o.getString("name"),
                        source = o.optString("source", "text"),
                        text = o.optString("text", ""),
                        xorKey = o.optString("xorKey", ""),
                        useGzip = o.optBoolean("useGzip", false),
                        framing = o.optString("framing", "raw"),
                        builtIn = o.optBoolean("builtIn", false)
                    )
                )
            }
            if (out.isEmpty()) builtIns else out
        } catch (_: Exception) {
            // An undecodable library must not be persisted over:
            // work from the built-ins in memory, storage untouched.
            builtIns
        }
    }

    private fun save() {
        val array = JSONArray()
        for (item in _items.value) {
            val o = JSONObject()
            o.put("name", item.name)
            o.put("source", item.source)
            o.put("text", item.text)
            o.put("xorKey", item.xorKey)
            o.put("useGzip", item.useGzip)
            o.put("framing", item.framing)
            o.put("builtIn", item.builtIn)
            array.put(o)
        }
        file.writeText(array.toString())
    }

    /// Add or replace by name, in place.
    fun add(item: SavedPayload) {
        val current = _items.value.toMutableList()
        val at = current.indexOfFirst { it.name == item.name }
        if (at >= 0) current[at] = item else current.add(item)
        _items.value = current
        save()
    }

    fun remove(name: String) {
        _items.value = _items.value.filter { it.name != name }
        save()
    }

    fun restoreBuiltIns() {
        val current = _items.value.toMutableList()
        for (builtIn in builtIns) {
            if (current.none { it.name == builtIn.name }) current.add(builtIn)
        }
        _items.value = current
        save()
    }

    companion object {
        val builtIns: List<SavedPayload> = listOf(
            SavedPayload("hello", "text", "hello", builtIn = true),
            SavedPayload("ping", "text", "ping", builtIn = true),
            SavedPayload("JSON hello", "text", "{\"hello\":\"nightjar\"}", builtIn = true),
            SavedPayload(
                "Wake-on-LAN (edit the MAC)", "hex",
                "ff ff ff ff ff ff " + "00 11 22 33 44 55 ".repeat(16),
                builtIn = true
            ),
            SavedPayload(
                "HTTP GET / (raw)", "hex",
                "47 45 54 20 2f 20 48 54 54 50 2f 31 2e 30 0d 0a 0d 0a",
                builtIn = true
            ),
            SavedPayload("32 x A (length test)", "text", "A".repeat(32), builtIn = true),
            SavedPayload(
                "DNS query — example.com (UDP 53)", "hex",
                "1a 2b 01 00 00 01 00 00 00 00 00 00 " +
                    "07 65 78 61 6d 70 6c 65 03 63 6f 6d 00 " +
                    "00 01 00 01",
                builtIn = true
            ),
            SavedPayload(
                "NTP time request (UDP 123)", "hex",
                "1b " + "00 ".repeat(47), builtIn = true
            ),
            SavedPayload("Redis PING (RESP)", "text", "*1\r\n\$4\r\nPING\r\n", builtIn = true),
            SavedPayload("memcached stats", "text", "stats\r\n", builtIn = true),
            SavedPayload("SMTP EHLO", "text", "EHLO nightjar\r\n", builtIn = true),
            SavedPayload(
                "MQTT CONNECT (client: nightjar)", "hex",
                "10 14 00 04 4d 51 54 54 04 02 00 3c " +
                    "00 08 6e 69 67 68 74 6a 61 72",
                builtIn = true
            ),
            SavedPayload(
                "Modbus read coils (TCP 502)", "hex",
                "00 01 00 00 00 06 01 01 00 00 00 08", builtIn = true
            ),
            SavedPayload(
                "CoAP GET /.well-known/core (UDP 5683)", "hex",
                "44 01 be ef 6e 6a 61 72 ba " +
                    "77 65 6c 6c 2d 6b 6e 6f 77 6e 04 63 6f 72 65",
                builtIn = true
            ),
            SavedPayload(
                "Printer test page (TCP 9100)", "text",
                "nightjar-hack says hello\r\n\u000C", builtIn = true
            ),
            SavedPayload(
                "SNMP get sysDescr (UDP 161)", "hex",
                "30 29 02 01 00 04 06 70 75 62 6c 69 63 a0 1c " +
                    "02 04 00 00 04 d2 02 01 00 02 01 00 30 0e 30 0c " +
                    "06 08 2b 06 01 02 01 01 01 00 05 00",
                builtIn = true
            ),
            SavedPayload(
                "SIP OPTIONS (UDP/TCP 5060)", "text",
                "OPTIONS sip:nightjar@127.0.0.1 SIP/2.0\r\n" +
                    "Via: SIP/2.0/UDP 127.0.0.1;branch=z9hG4bK-nh\r\n" +
                    "From: <sip:nightjar@127.0.0.1>;tag=1\r\n" +
                    "To: <sip:nightjar@127.0.0.1>\r\n" +
                    "Call-ID: 1@127.0.0.1\r\nCSeq: 1 OPTIONS\r\n" +
                    "Content-Length: 0\r\n\r\n",
                builtIn = true
            ),
            SavedPayload(
                "Postgres SSLRequest (TCP 5432)", "hex",
                "00 00 00 08 04 d2 16 2f", builtIn = true
            ),
            SavedPayload(
                "HTTP OPTIONS (raw)", "text",
                "OPTIONS * HTTP/1.0\r\n\r\n", builtIn = true
            )
        )
    }
}
