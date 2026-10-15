package net.nosuchmachine.nightjarhack

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.Base64
import java.util.Collections
import javax.net.ssl.SSLSocketFactory

data class LastReply(val label: String, val data: ByteArray, val atMs: Long)

data class Arrival(
    val atMs: Long,
    val via: String,          // tcp / udp / http / ble
    val from: String,
    val data: ByteArray
) {
    val text: String? get() = PayloadKit.printableText(data)
}

/// The mouth: every send path, the reply channel, and the
/// persistent exchanges history. A port of the iOS Mouth's
/// network core (Serve listeners live in Serve.kt, BLE in
/// BleMouth.kt, the crawl in Crawl.kt). One hard invariant,
/// carried over from an iOS bug: a reply is always NOTED
/// before the send's completion fires, so a caller reacting
/// to completion already sees it.
class Mouth(private val context: Context) {

    val scope = CoroutineScope(Dispatchers.IO)

    private val _sendLines = MutableStateFlow<List<String>>(emptyList())
    val sendLines: StateFlow<List<String>> = _sendLines
    private val _lastReply = MutableStateFlow<LastReply?>(null)
    val lastReply: StateFlow<LastReply?> = _lastReply
    private val _toasts = MutableStateFlow<Pair<String, Boolean>?>(null)
    val toasts: StateFlow<Pair<String, Boolean>?> = _toasts

    fun toast(message: String, error: Boolean = false) {
        _toasts.value = message to error
    }

    fun clearToast() {
        _toasts.value = null
    }

    fun line(text: String) {
        _sendLines.value = (_sendLines.value + text).takeLast(400)
    }

    /// BLE arrivals (GATT writes to the hosted characteristic)
    /// are routed to the Serve inbox by the app wiring.
    var bleArrivalHandler: ((String, ByteArray) -> Unit)? = null

    fun noteBleArrival(from: String, data: ByteArray) {
        logExchange("ble-gatt", from, 0, data)
        bleArrivalHandler?.invoke(from, data)
    }

    fun clearSendLog() {
        _sendLines.value = emptyList()
    }

    // MARK: Reply channel (synchronous mirror under a lock,
    // exactly as the fixed iOS build does it)

    private val replyLock = Any()
    private var lastReplySync: LastReply? = null

    fun noteReply(label: String, data: ByteArray) {
        if (data.isEmpty()) return
        val noted = LastReply(label, data, System.currentTimeMillis())
        synchronized(replyLock) { lastReplySync = noted }
        _lastReply.value = noted
    }

    /// The freshest noted reply at or after `sinceMs`, read
    /// synchronously — the centipede's per-hop answer channel.
    fun replyData(sinceMs: Long): ByteArray? {
        synchronized(replyLock) {
            val noted = lastReplySync ?: return null
            return if (noted.atMs >= sinceMs) noted.data else null
        }
    }

    // MARK: History (exchanges.jsonl, same spirit as iOS)

    private val historyFile: File
        get() = File(context.filesDir, "exchanges.jsonl")

    fun logExchange(kind: String, label: String, sent: Int, reply: ByteArray?) {
        val entry = JSONObject()
        entry.put("type", "exchange")
        entry.put("ts", System.currentTimeMillis() / 1000.0)
        entry.put("kind", kind)
        entry.put("label", label)
        entry.put("sent", sent)
        if (reply != null) {
            entry.put("reply_b64", Base64.getEncoder().encodeToString(reply))
            PayloadKit.printableText(reply)?.let { entry.put("reply_text", it) }
        }
        scope.launch {
            synchronized(historyFile) {
                try {
                    historyFile.appendText(entry.toString() + "\n")
                } catch (_: Exception) {
                }
            }
        }
    }

    fun logRecon(kind: String, label: String, lines: List<String>) {
        logExchange(kind, label, 0, lines.joinToString("\n").toByteArray(Charsets.UTF_8))
    }

    fun readHistory(): List<JSONObject> {
        if (!historyFile.exists()) return emptyList()
        return historyFile.readLines().mapNotNull { line ->
            try {
                JSONObject(line)
            } catch (_: Exception) {
                null
            }
        }.reversed()
    }

    fun clearHistory() {
        try {
            historyFile.delete()
        } catch (_: Exception) {
        }
    }

    // MARK: This phone

    fun localIPAddress(): String? {
        try {
            for (iface in Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in Collections.list(iface.inetAddresses)) {
                    if (!addr.isLoopbackAddress && addr is java.net.Inet4Address) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (_: Exception) {
        }
        return null
    }

    // MARK: Network send (tcp / udp / tls)

    fun sendNetwork(
        target: SendTarget, payload: ByteArray, framing: String,
        read: Boolean, timeoutMs: Int = 3000,
        completion: (Boolean) -> Unit
    ) {
        scope.launch {
            val framed = PayloadKit.frame(payload, framing)
            var ok = false
            var reply = ByteArray(0)
            try {
                when (target) {
                    is SendTarget.Tcp -> {
                        val socket = if (target.tls) {
                            SSLSocketFactory.getDefault()
                                .createSocket(target.host, target.port) as Socket
                        } else {
                            Socket()
                        }
                        socket.use { s ->
                            if (!target.tls) {
                                s.connect(
                                    InetSocketAddress(target.host, target.port),
                                    timeoutMs
                                )
                            }
                            s.soTimeout = timeoutMs
                            s.getOutputStream().write(framed)
                            s.getOutputStream().flush()
                            ok = true
                            if (read) reply = readToClose(s, timeoutMs)
                        }
                    }
                    is SendTarget.Udp -> {
                        DatagramSocket().use { s ->
                            s.soTimeout = timeoutMs
                            val address = InetAddress.getByName(target.host)
                            s.send(DatagramPacket(framed, framed.size, address, target.port))
                            ok = true
                            if (read) {
                                val buf = ByteArray(65536)
                                val packet = DatagramPacket(buf, buf.size)
                                try {
                                    s.receive(packet)
                                    reply = packet.data.copyOf(packet.length)
                                } catch (_: Exception) {
                                }
                            }
                        }
                    }
                    else -> completion(false).also { return@launch }
                }
            } catch (e: Exception) {
                line("nightjar: ${e.message ?: "send failed"}")
            }
            if (ok) {
                logExchange("send", target.raw, framed.size, if (read) reply else null)
            }
            // Note BEFORE completion — the invariant.
            if (read && reply.isNotEmpty()) {
                noteReply(target.raw, reply)
                line("  <- ${reply.size} byte reply")
                for (l in PayloadKit.hexdump(reply).split("\n")) line(l)
                PayloadKit.printableText(reply)?.let { line("  text: $it") }
            } else if (read && ok) {
                line("  (no reply)")
            }
            withContext(Dispatchers.Main) { completion(ok) }
        }
    }

    private fun readToClose(socket: Socket, timeoutMs: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(65536)
        val deadline = System.currentTimeMillis() + timeoutMs
        try {
            val input = socket.getInputStream()
            while (System.currentTimeMillis() < deadline) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                // A peer that answered and went quiet has said
                // its piece: shorten the remaining wait.
                socket.soTimeout = 400
            }
        } catch (_: Exception) {
            // Timeout or reset after data: what arrived stands.
        }
        return out.toByteArray()
    }

    // MARK: HTTP send (mirrors the iOS semantics exactly)

    fun sendHTTP(
        target: SendTarget, payload: ByteArray, framing: String,
        method: String, timeoutMs: Int = 5000,
        completion: (Boolean) -> Unit
    ) {
        val http = target as? SendTarget.Http
        if (http == null) {
            completion(false)
            return
        }
        scope.launch {
            var ok = false
            var reply = ByteArray(0)
            var status = 0
            try {
                val base = http.url
                var path = base.path.ifEmpty { "/" }
                var body: ByteArray? = null
                if (method == "GET" || method == "HEAD") {
                    if (payload.isNotEmpty()) {
                        val b64 = Base64.getUrlEncoder().withoutPadding()
                            .encodeToString(payload)
                        val existing = base.query
                        path += if (existing != null) "?$existing&payload=$b64"
                        else "?payload=$b64"
                    } else if (base.query != null) {
                        path += "?${base.query}"
                    }
                } else {
                    body = PayloadKit.frame(payload, framing)
                    if (base.query != null) path += "?${base.query}"
                }
                val port = if (base.port >= 0) base.port
                else if (http.https) 443 else 80
                val socket = if (http.https) {
                    SSLSocketFactory.getDefault().createSocket(base.host, port) as Socket
                } else {
                    Socket().also {
                        it.connect(InetSocketAddress(base.host, port), timeoutMs)
                    }
                }
                socket.use { s ->
                    s.soTimeout = timeoutMs
                    val head = StringBuilder()
                    head.append("$method $path HTTP/1.1\r\n")
                    head.append("Host: ${base.host}\r\n")
                    head.append("User-Agent: nightjar-send\r\n")
                    if (body != null) {
                        head.append(
                            "Content-Type: " +
                                (if (framing == "json") "application/json"
                                else "application/octet-stream") + "\r\n"
                        )
                        head.append("Content-Length: ${body.size}\r\n")
                    }
                    head.append("Connection: close\r\n\r\n")
                    val out = s.getOutputStream()
                    out.write(head.toString().toByteArray(Charsets.UTF_8))
                    if (body != null) out.write(body)
                    out.flush()
                    val raw = readRawHttp(s, timeoutMs)
                    val split = findHeaderEnd(raw)
                    status = parseStatus(raw)
                    reply = if (split >= 0) raw.copyOfRange(split, raw.size)
                    else raw
                    ok = status in 200 until 400
                }
            } catch (e: Exception) {
                line("nightjar: ${e.message ?: "http failed"}")
            }
            line("sending ${payload.size} bytes over http to ${http.raw} ($method)")
            logExchange(
                "http", http.raw,
                sent = payload.size, reply = reply
            )
            // State first, callback last (the iOS invariant).
            noteReply("http", reply)
            line("  HTTP $status, ${reply.size} byte reply")
            if (reply.isNotEmpty()) {
                for (l in PayloadKit.hexdump(reply).split("\n")) line(l)
            }
            withContext(Dispatchers.Main) { completion(ok) }
        }
    }

    private fun readRawHttp(socket: Socket, timeoutMs: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(65536)
        val deadline = System.currentTimeMillis() + timeoutMs
        try {
            val input = socket.getInputStream()
            while (System.currentTimeMillis() < deadline) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                socket.soTimeout = 400
            }
        } catch (_: Exception) {
        }
        return out.toByteArray()
    }

    private fun findHeaderEnd(raw: ByteArray): Int {
        for (i in 0 until raw.size - 3) {
            if (raw[i] == '\r'.code.toByte() && raw[i + 1] == '\n'.code.toByte() &&
                raw[i + 2] == '\r'.code.toByte() && raw[i + 3] == '\n'.code.toByte()
            ) {
                return i + 4
            }
        }
        return -1
    }

    private fun parseStatus(raw: ByteArray): Int {
        val head = String(raw.copyOf(minOf(raw.size, 64)), Charsets.UTF_8)
        val parts = head.split(" ")
        return if (parts.size >= 2) parts[1].toIntOrNull() ?: 0 else 0
    }

    // MARK: Fan-out (Send to many)

    fun sendToMany(
        lines: List<String>, payloadFor: (String) -> ByteArray?,
        framing: String, read: Boolean
    ) {
        scope.launch(Dispatchers.Main) {
            var sent = 0
            var failed = 0
            for (rawLine in lines) {
                val text = rawLine.trim()
                if (text.isEmpty() || text.startsWith("#")) continue
                val payload = payloadFor(text)
                if (payload == null) {
                    line("✗ $text — could not build payload")
                    failed += 1
                    continue
                }
                val target = try {
                    SendTarget.parse(text)
                } catch (_: Exception) {
                    // Range-shaped lines expand like the crawl's.
                    null
                }
                if (target == null) {
                    val expanded = Crawl.expandRoute(listOf(text)).first
                    if (expanded.isEmpty()) {
                        line("✗ $text — invalid target")
                        failed += 1
                    } else {
                        for (stop in expanded) {
                            val t = try {
                                SendTarget.parse(stop)
                            } catch (_: Exception) {
                                null
                            }
                            if (t == null) {
                                line("✗ $stop — invalid target")
                                failed += 1
                            } else {
                                val done = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                                    sendNetwork(t, payload, framing, read) { ok ->
                                        cont.resume(ok) {}
                                    }
                                }
                                line("${if (done) "✓" else "✗"} $stop")
                                if (done) sent += 1 else failed += 1
                            }
                        }
                    }
                    continue
                }
                when (target) {
                    is SendTarget.Http -> {
                        val done = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                            sendHTTP(target, payload, framing, "POST") { ok ->
                                cont.resume(ok) {}
                            }
                        }
                        line("${if (done) "✓" else "✗"} $text")
                        if (done) sent += 1 else failed += 1
                    }
                    is SendTarget.Tcp, is SendTarget.Udp -> {
                        val done = kotlinx.coroutines.suspendCancellableCoroutine<Boolean> { cont ->
                            sendNetwork(target, payload, framing, read) { ok ->
                                cont.resume(ok) {}
                            }
                        }
                        line("${if (done) "✓" else "✗"} $text")
                        if (done) sent += 1 else failed += 1
                    }
                    else -> {
                        line("✗ $text — not a network target")
                        failed += 1
                    }
                }
            }
            line("fan-out done — $sent sent, $failed failed")
            toast("Sent to $sent, $failed failed", error = failed > 0 && sent == 0)
        }
    }
}
