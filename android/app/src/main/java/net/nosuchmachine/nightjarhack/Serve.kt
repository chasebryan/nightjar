package net.nosuchmachine.nightjarhack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

data class PhoneService(val name: String, val host: String, val port: Int)

/// The serve half: TCP/UDP/HTTP listeners with static, echo,
/// or file replies; an inbox of arrivals; NSD (Bonjour)
/// advertisement + discovery of other phones. A port of the
/// iOS Serve, generation-stamped the same way so a stale
/// listener can never flip the running state or speak into a
/// newer session.
class Serve(private val context: Context, private val mouth: Mouth) {

    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running
    private val _inbox = MutableStateFlow<List<Arrival>>(emptyList())
    val inbox: StateFlow<List<Arrival>> = _inbox
    private val _status = MutableStateFlow("")
    val status: StateFlow<String> = _status
    private val _nearbyPhones = MutableStateFlow<List<PhoneService>>(emptyList())
    val nearbyPhones: StateFlow<List<PhoneService>> = _nearbyPhones

    private val generation = AtomicInteger(0)
    private val pool = Executors.newCachedThreadPool()
    private var tcpServer: ServerSocket? = null
    private var httpServer: ServerSocket? = null
    private var udpSocket: DatagramSocket? = null

    private val nsdManager =
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var ownServiceName: String? = null

    var fileReplyBytes: ByteArray = ByteArray(0)

    fun start(
        tcpPort: Int, udpPort: Int, httpPort: Int,
        replyMode: String, staticReply: String,
        stealth: Boolean
    ) {
        stop()
        val gen = generation.incrementAndGet()
        val replyText = staticReply.toByteArray(Charsets.UTF_8)
        var bound = 0
        val errors = mutableListOf<String>()

        if (tcpPort > 0) {
            try {
                val server = ServerSocket(tcpPort)
                tcpServer = server
                bound += 1
                pool.execute { tcpLoop(server, gen, replyMode, replyText) }
            } catch (e: Exception) {
                errors.add("tcp $tcpPort: ${e.message}")
            }
        }
        if (httpPort > 0) {
            try {
                val server = ServerSocket(httpPort)
                httpServer = server
                bound += 1
                pool.execute { httpLoop(server, gen, replyMode, replyText) }
            } catch (e: Exception) {
                errors.add("http $httpPort: ${e.message}")
            }
        }
        if (udpPort > 0) {
            try {
                val socket = DatagramSocket(udpPort)
                udpSocket = socket
                bound += 1
                pool.execute { udpLoop(socket, gen, replyMode, replyText) }
            } catch (e: Exception) {
                errors.add("udp $udpPort: ${e.message}")
            }
        }
        _running.value = bound > 0
        _status.value = when {
            bound == 0 -> "Nothing bound. " + errors.joinToString("; ")
            errors.isEmpty() -> "Serving — reachable at " +
                (mouth.localIPAddress() ?: "?") +
                (if (stealth) " (stealth: unlisted)" else "")
            else -> "Serving ($bound listener(s)); " + errors.joinToString("; ")
        }
        if (bound > 0 && !stealth && tcpPort > 0) {
            advertise(tcpPort)
        }
        if (bound > 0) startDiscovery()
    }

    fun stop() {
        generation.incrementAndGet()
        try {
            tcpServer?.close()
        } catch (_: Exception) {
        }
        try {
            httpServer?.close()
        } catch (_: Exception) {
        }
        try {
            udpSocket?.close()
        } catch (_: Exception) {
        }
        tcpServer = null
        httpServer = null
        udpSocket = null
        unadvertise()
        stopDiscovery()
        _running.value = false
        if (_status.value.isNotEmpty()) _status.value = "Stopped"
    }

    private fun replyFor(mode: String, staticReply: ByteArray, received: ByteArray): ByteArray {
        return when (mode) {
            "echo" -> received
            "file" -> fileReplyBytes
            else -> staticReply
        }
    }

    private fun noteArrival(gen: Int, via: String, from: String, data: ByteArray, stealth: Boolean) {
        if (generation.get() != gen) return
        val arrival = Arrival(System.currentTimeMillis(), via, from, data)
        _inbox.value = (_inbox.value + arrival).takeLast(200)
        Journal.log(
            "serve", "arrival",
            "$via from $from — ${data.size} bytes"
        )
        mouth.logExchange("serve-$via", from, 0, data)
        if (!stealth) notifyArrival(arrival)
    }

    private fun tcpLoop(server: ServerSocket, gen: Int, mode: String, staticReply: ByteArray) {
        while (generation.get() == gen && !server.isClosed) {
            val client = try {
                server.accept()
            } catch (_: Exception) {
                break
            }
            pool.execute {
                client.use { s ->
                    try {
                        s.soTimeout = 30_000
                        val data = readStream(s)
                        val from = "tcp://${s.inetAddress.hostAddress}:${s.port}"
                        noteArrival(gen, "tcp", from, data, stealthNow)
                        val reply = replyFor(mode, staticReply, data)
                        if (reply.isNotEmpty()) {
                            s.getOutputStream().write(reply)
                            s.getOutputStream().flush()
                        }
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun udpLoop(socket: DatagramSocket, gen: Int, mode: String, staticReply: ByteArray) {
        val buf = ByteArray(65536)
        while (generation.get() == gen && !socket.isClosed) {
            val packet = DatagramPacket(buf, buf.size)
            try {
                socket.receive(packet)
            } catch (_: Exception) {
                break
            }
            val data = packet.data.copyOf(packet.length)
            val from = "udp://${packet.address.hostAddress}:${packet.port}"
            noteArrival(gen, "udp", from, data, stealthNow)
            val reply = replyFor(mode, staticReply, data)
            if (reply.isNotEmpty()) {
                try {
                    socket.send(
                        DatagramPacket(reply, reply.size, packet.address, packet.port)
                    )
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun httpLoop(server: ServerSocket, gen: Int, mode: String, staticReply: ByteArray) {
        while (generation.get() == gen && !server.isClosed) {
            val client = try {
                server.accept()
            } catch (_: Exception) {
                break
            }
            pool.execute {
                client.use { s ->
                    try {
                        s.soTimeout = 30_000
                        val raw = readHttpRequest(s)
                        val from = "http://${s.inetAddress.hostAddress}:${s.port}"
                        noteArrival(gen, "http", from, raw, stealthNow)
                        val requestLine = String(raw, Charsets.UTF_8)
                            .lineSequence().firstOrNull() ?: ""
                        val isHead = requestLine.startsWith("HEAD ")
                        val body = replyFor(mode, staticReply, raw)
                        val head = "HTTP/1.1 200 OK\r\n" +
                            "Content-Type: application/octet-stream\r\n" +
                            "Content-Length: ${body.size}\r\n" +
                            "Connection: close\r\n\r\n"
                        val out = s.getOutputStream()
                        out.write(head.toByteArray(Charsets.UTF_8))
                        if (!isHead && body.isNotEmpty()) out.write(body)
                        out.flush()
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }

    private fun readStream(socket: Socket): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(65536)
        val input = socket.getInputStream()
        val softDeadline = System.currentTimeMillis() + 1500
        try {
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                if (out.size() > 1_000_000) break
                if (System.currentTimeMillis() > softDeadline && input.available() == 0) {
                    socket.soTimeout = 300
                }
            }
        } catch (_: Exception) {
            // Idle timeout after data: what arrived stands.
        }
        return out.toByteArray()
    }

    private fun readHttpRequest(socket: Socket): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(65536)
        val input = socket.getInputStream()
        var headerEnd = -1
        var contentLength = 0
        try {
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                out.write(buf, 0, n)
                if (headerEnd < 0) {
                    val bytes = out.toByteArray()
                    headerEnd = findHeaderEnd(bytes)
                    if (headerEnd >= 0) {
                        val headers = String(bytes.copyOf(headerEnd), Charsets.UTF_8)
                        for (line in headers.lineSequence()) {
                            if (line.lowercase().startsWith("content-length:")) {
                                contentLength = line.substringAfter(':')
                                    .trim().toIntOrNull() ?: 0
                            }
                        }
                    }
                }
                if (headerEnd >= 0 && out.size() >= headerEnd + contentLength) break
                if (out.size() > 1_000_000) break
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

    // Stealth is read live so toggling it mid-serve applies to
    // arrivals immediately, as on iOS.
    @Volatile
    var stealthNow: Boolean = false

    // MARK: NSD advertisement + phone discovery

    private fun advertise(tcpPort: Int) {
        unadvertise()
        val info = NsdServiceInfo().apply {
            serviceName = "nightjar-" + (Build.MODEL ?: "android")
            serviceType = "_nightjar._tcp"
            port = tcpPort
        }
        ownServiceName = info.serviceName
        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                ownServiceName = serviceInfo.serviceName
            }
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        try {
            nsdManager.registerService(info, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        } catch (_: Exception) {
        }
    }

    private fun unadvertise() {
        val listener = registrationListener ?: return
        try {
            nsdManager.unregisterService(listener)
        } catch (_: Exception) {
        }
        registrationListener = null
    }

    private fun startDiscovery() {
        if (discoveryListener != null) return
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceName == ownServiceName) return
                try {
                    nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                        override fun onServiceResolved(resolved: NsdServiceInfo) {
                            val host = resolved.host?.hostAddress ?: return
                            val phone = PhoneService(resolved.serviceName, host, resolved.port)
                            val current = _nearbyPhones.value
                            if (current.none { it.name == phone.name }) {
                                _nearbyPhones.value = current + phone
                            }
                        }
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                    })
                } catch (_: Exception) {
                }
            }
            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                _nearbyPhones.value = _nearbyPhones.value
                    .filter { it.name != serviceInfo.serviceName }
            }
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        try {
            nsdManager.discoverServices(
                "_nightjar._tcp", NsdManager.PROTOCOL_DNS_SD, discoveryListener
            )
        } catch (_: Exception) {
            discoveryListener = null
        }
    }

    private fun stopDiscovery() {
        val listener = discoveryListener ?: return
        try {
            nsdManager.stopServiceDiscovery(listener)
        } catch (_: Exception) {
        }
        discoveryListener = null
        _nearbyPhones.value = emptyList()
    }

    /** Resolve a phone:NAME target to its TCP endpoint, from
     *  the discovery table (the Android read of Bonjour). */
    fun resolvePhone(name: String): PhoneService? =
        _nearbyPhones.value.firstOrNull { it.name == name }

    // MARK: Arrival notifications (suppressed in stealth)

    private fun notifyArrival(arrival: Arrival) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        val channelId = "arrivals"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Serve arrivals",
                    NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val text = arrival.text?.take(80) ?: "${arrival.data.size} bytes"
        val notification = android.app.Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("nightjar-hack — ${arrival.via} arrival")
            .setContentText("from ${arrival.from}: $text")
            .build()
        try {
            manager.notify((arrival.atMs % 100000).toInt(), notification)
        } catch (_: SecurityException) {
        }
    }

    fun clearInbox() {
        _inbox.value = emptyList()
    }

    /** A GATT write to the hosted characteristic lands in the
     *  same inbox as network arrivals. */
    fun injectBleArrival(from: String, data: ByteArray) {
        noteArrival(generation.get(), "ble", "ble://$from", data, stealthNow)
    }

    val inboxJsonl: String
        get() = _inbox.value.joinToString("\n") { arrival ->
            val entry = org.json.JSONObject()
            entry.put("type", "arrival")
            entry.put("ts", arrival.atMs / 1000.0)
            entry.put("via", arrival.via)
            entry.put("from", arrival.from)
            entry.put(
                "data_b64",
                java.util.Base64.getEncoder().encodeToString(arrival.data)
            )
            arrival.text?.let { entry.put("text", it) }
            entry.toString()
        }
}
