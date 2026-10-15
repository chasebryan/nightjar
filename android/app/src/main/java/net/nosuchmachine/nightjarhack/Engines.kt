package net.nosuchmachine.nightjarhack

import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.ByteArrayOutputStream
import java.net.InetSocketAddress
import java.net.Socket

/// SnatchSteal + PayPlant + timed delivery — the Send tab's
/// specialist engines, on the mouth's sockets.
class Engines(private val mouth: Mouth) {

    // MARK: SnatchSteal — knock, then take everything

    private val _snatchBusy = MutableStateFlow(false)
    val snatchBusy: StateFlow<Boolean> = _snatchBusy
    private val _snatchBytes = MutableStateFlow(0)
    val snatchBytes: StateFlow<Int> = _snatchBytes
    private val _snatchResult = MutableStateFlow<Pair<String, ByteArray>?>(null)
    val snatchResult: StateFlow<Pair<String, ByteArray>?> = _snatchResult

    fun snatch(target: SendTarget, knock: ByteArray?) {
        val tcp = target as? SendTarget.Tcp
        if (tcp == null || tcp.tls) {
            mouth.toast("SnatchSteal needs a plain TCP target", error = true)
            return
        }
        if (_snatchBusy.value) return
        _snatchBusy.value = true
        _snatchBytes.value = 0
        mouth.scope.launch {
            val haul = ByteArrayOutputStream()
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress(tcp.host, tcp.port), 4000)
                    socket.soTimeout = 3000
                    if (knock != null && knock.isNotEmpty()) {
                        socket.getOutputStream().write(knock)
                        socket.getOutputStream().flush()
                        mouth.line("snatch: knocked with ${knock.size} bytes")
                    }
                    val buf = ByteArray(65536)
                    val input = socket.getInputStream()
                    while (true) {
                        val n = try {
                            input.read(buf)
                        } catch (_: Exception) {
                            break  // idle 3 s or reset: the haul stands
                        }
                        if (n < 0) break
                        haul.write(buf, 0, n)
                        _snatchBytes.value = haul.size()
                        if (haul.size() > 4_000_000) break
                    }
                }
                val data = haul.toByteArray()
                _snatchResult.value = target.raw to data
                mouth.logExchange("snatch", target.raw, knock?.size ?: 0, data)
                mouth.line("snatch: took ${data.size} bytes from ${target.raw}")
                mouth.noteReply(target.raw, data)
                mouth.toast("Snatched ${data.size} bytes")
            } catch (e: Exception) {
                mouth.toast("Snatch failed: ${e.message}", error = true)
                mouth.line("snatch failed: ${e.message}")
            } finally {
                _snatchBusy.value = false
            }
        }
    }

    // MARK: PayPlant — store a payload in a service that keeps it

    data class PlantRecord(
        val service: String, val key: String, val target: SendTarget.Tcp,
        val value: String
    )

    private val _lastPlant = MutableStateFlow<PlantRecord?>(null)
    val lastPlant: StateFlow<PlantRecord?> = _lastPlant

    fun plant(
        service: String, target: SendTarget, key: String, value: String
    ) {
        val tcp = target as? SendTarget.Tcp
        if (tcp == null) {
            mouth.toast("PayPlant needs a TCP target", error = true)
            return
        }
        mouth.scope.launch {
            val ok = when (service) {
                "mqtt" -> plantMQTT(tcp, key, value)
                "redis" -> plantRedis(tcp, key, value)
                "memcached" -> plantMemcached(tcp, key, value)
                else -> false
            }
            if (ok) {
                _lastPlant.value = PlantRecord(service, key, tcp, value)
                mouth.toast("Planted in $service at $key")
                mouth.logRecon("payplant", "${tcp.raw} $service",
                    listOf("planted key=$key (${value.length} chars)"))
            } else {
                mouth.toast("Plant failed — the service didn't confirm", error = true)
            }
        }
    }

    private fun plantMQTT(tcp: SendTarget.Tcp, topic: String, value: String): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(tcp.host, tcp.port), 4000)
                socket.soTimeout = 3000
                val out = socket.getOutputStream()
                val input = socket.getInputStream()
                out.write(PayloadKit.mqttConnect("nightjar"))
                out.flush()
                val connack = ByteArray(4)
                var read = 0
                while (read < 4) {
                    val n = input.read(connack, read, 4 - read)
                    if (n < 0) break
                    read += n
                }
                if (read < 4 || connack[0] != 0x20.toByte() || connack[3] != 0.toByte()) {
                    return false
                }
                out.write(
                    PayloadKit.mqttPublish(
                        topic, value.toByteArray(Charsets.UTF_8), retain = true
                    )
                )
                out.flush()
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun plantRedis(tcp: SendTarget.Tcp, key: String, value: String): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(tcp.host, tcp.port), 4000)
                socket.soTimeout = 3000
                socket.getOutputStream().write(
                    PayloadKit.redisCommand(listOf("SET", key, value))
                )
                socket.getOutputStream().flush()
                val reply = readLine(socket)
                reply.startsWith("+OK")
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun plantMemcached(tcp: SendTarget.Tcp, key: String, value: String): Boolean {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(tcp.host, tcp.port), 4000)
                socket.soTimeout = 3000
                socket.getOutputStream().write(PayloadKit.memcachedSet(key, value))
                socket.getOutputStream().flush()
                readLine(socket).startsWith("STORED")
            }
        } catch (_: Exception) {
            false
        }
    }

    fun verifyPlant() {
        val plant = _lastPlant.value
        if (plant == null) {
            mouth.toast("Nothing planted yet this session", error = true)
            return
        }
        mouth.scope.launch {
            val found: String? = when (plant.service) {
                "redis" -> tcpExchange(
                    plant.target,
                    PayloadKit.redisCommand(listOf("GET", plant.key))
                )?.let { parseRedisBulk(it) }
                "memcached" -> tcpExchange(
                    plant.target,
                    "get ${plant.key}\r\n".toByteArray(Charsets.UTF_8)
                )?.let { parseMemcachedValue(it, plant.key) }
                else -> null
            }
            when {
                plant.service == "mqtt" ->
                    mouth.toast("MQTT plants can't be read back — retained is fire-and-trust")
                found == null ->
                    mouth.toast("Verify: nothing came back", error = true)
                found == plant.value ->
                    mouth.toast("Verified — the plant is still there, byte for byte")
                else ->
                    mouth.toast("Verify: the stored value differs", error = true)
            }
        }
    }

    private fun tcpExchange(target: SendTarget.Tcp, payload: ByteArray): ByteArray? {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(target.host, target.port), 4000)
                socket.soTimeout = 3000
                socket.getOutputStream().write(payload)
                socket.getOutputStream().flush()
                val out = ByteArrayOutputStream()
                val buf = ByteArray(65536)
                try {
                    while (true) {
                        val n = socket.getInputStream().read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        if (out.size() > 1_000_000) break
                        socket.soTimeout = 400
                    }
                } catch (_: Exception) {
                }
                out.toByteArray()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readLine(socket: Socket): String {
        val out = ByteArrayOutputStream()
        val input = socket.getInputStream()
        var b: Int
        while (true) {
            b = input.read()
            if (b < 0) break
            out.write(b)
            if (b == '\n'.code) break
            if (out.size() > 8192) break
        }
        return String(out.toByteArray(), Charsets.UTF_8)
    }

    private fun parseRedisBulk(data: ByteArray): String? {
        val text = String(data, Charsets.UTF_8)
        if (!text.startsWith("$")) return null
        val firstBreak = text.indexOf("\r\n")
        if (firstBreak < 0) return null
        val length = text.substring(1, firstBreak).toIntOrNull() ?: return null
        if (length < 0) return null
        val start = firstBreak + 2
        if (start + length > text.length) return null
        return text.substring(start, start + length)
    }

    private fun parseMemcachedValue(data: ByteArray, key: String): String? {
        val text = String(data, Charsets.UTF_8)
        val header = "VALUE $key "
        val at = text.indexOf(header)
        if (at < 0) return null
        val lineEnd = text.indexOf("\r\n", at)
        if (lineEnd < 0) return null
        val fields = text.substring(at, lineEnd).split(" ")
        val length = fields.getOrNull(3)?.toIntOrNull() ?: return null
        val start = lineEnd + 2
        if (start + length > text.length) return null
        return text.substring(start, start + length)
    }

    // MARK: Timed delivery

    private val _scheduleRunning = MutableStateFlow(false)
    val scheduleRunning: StateFlow<Boolean> = _scheduleRunning
    private var scheduleJob: Job? = null
    private var scheduleToken = 0

    fun startSchedule(
        delaySeconds: Int, intervalSeconds: Int, count: Int,
        send: suspend () -> Boolean
    ) {
        stopSchedule()
        scheduleToken += 1
        val token = scheduleToken
        _scheduleRunning.value = true
        scheduleJob = mouth.scope.launch {
            if (delaySeconds > 0) delay(delaySeconds * 1000L)
            var sent = 0
            while (scheduleToken == token && sent < count) {
                val ok = send()
                if (scheduleToken != token) break
                sent += 1
                mouth.line("timed delivery: $sent/$count ${if (ok) "sent" else "failed"}")
                if (sent < count && intervalSeconds > 0) {
                    delay(intervalSeconds * 1000L)
                }
            }
            if (scheduleToken == token) {
                _scheduleRunning.value = false
                mouth.toast("Timed delivery finished ($sent/$count)")
            }
        }
    }

    fun stopSchedule() {
        scheduleToken += 1
        scheduleJob?.cancel()
        scheduleJob = null
        _scheduleRunning.value = false
    }
}
