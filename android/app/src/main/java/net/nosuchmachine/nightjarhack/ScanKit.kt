package net.nosuchmachine.nightjarhack

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey
import java.util.Date
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager

/// Scan tables — verbatim from the iOS ScanModel.
object ScanKit {
    val topPorts: List<Pair<Int, String>> = listOf(
        21 to "FTP", 22 to "SSH", 23 to "Telnet", 25 to "SMTP",
        53 to "DNS", 80 to "HTTP", 110 to "POP3", 143 to "IMAP",
        443 to "HTTPS", 445 to "SMB", 993 to "IMAPS", 995 to "POP3S",
        1723 to "PPTP", 1883 to "MQTT", 3306 to "MySQL", 3389 to "RDP",
        5060 to "SIP", 5432 to "Postgres", 5900 to "VNC",
        6379 to "Redis", 8080 to "HTTP alt", 8443 to "HTTPS alt",
        9100 to "Printer", 9200 to "Elasticsearch",
        11211 to "memcached", 27017 to "MongoDB", 161 to "SNMP",
        2049 to "NFS"
    )

    val serviceNames: Map<Int, String> = topPorts.toMap()

    val payloadByPort: Map<Int, String> = mapOf(
        25 to "SMTP EHLO",
        53 to "DNS query — example.com (UDP 53)",
        80 to "HTTP GET / (raw)",
        502 to "Modbus read coils (TCP 502)",
        161 to "SNMP get sysDescr (UDP 161)",
        1883 to "MQTT CONNECT (client: nightjar)",
        5060 to "SIP OPTIONS (UDP/TCP 5060)",
        5432 to "Postgres SSLRequest (TCP 5432)",
        6379 to "Redis PING (RESP)",
        9100 to "Printer test page (TCP 9100)",
        11211 to "memcached stats"
    )

    val httpPorts: Set<Int> = setOf(80, 8000, 8080, 8888, 9200)

    val bonjourTypes: List<Pair<String, String>> = listOf(
        "_http._tcp" to "Web (HTTP)",
        "_https._tcp" to "Web (HTTPS)",
        "_ssh._tcp" to "SSH",
        "_smb._tcp" to "SMB file sharing",
        "_airplay._tcp" to "AirPlay",
        "_googlecast._tcp" to "Google Cast",
        "_ipp._tcp" to "IPP printing",
        "_printer._tcp" to "Printer",
        "_mqtt._tcp" to "MQTT",
        "_nightjar._tcp" to "nightjar phones"
    )

    /** Parse a ports field: "22,80,8000-8100" → sorted unique. */
    fun parsePorts(text: String, defaultToTop: Boolean): List<Int> {
        val out = sortedSetOf<Int>()
        for (piece in text.split(',')) {
            val part = piece.trim()
            if (part.isEmpty()) continue
            if (part.contains('-')) {
                val a = part.substringBefore('-').trim().toIntOrNull()
                val b = part.substringAfter('-').trim().toIntOrNull()
                if (a != null && b != null && a in 1..65535 && b in a..65535 &&
                    b - a <= 4096
                ) {
                    for (p in a..b) out.add(p)
                }
            } else {
                part.toIntOrNull()?.let { if (it in 1..65535) out.add(it) }
            }
        }
        val capped = out.take(2048)
        return if (capped.isEmpty() && defaultToTop) topPorts.map { it.first }
        else capped
    }
}

data class PortResult(
    val host: String,
    val port: Int,
    val service: String,
    val banner: String?
)

/// TCP connect scanner with banner grab — the iOS Scan tab's
/// engine, on a 48-way bounded pool.
class PortScanner {
    @Volatile
    private var generation = 0

    fun stop() {
        generation += 1
    }

    suspend fun scan(
        host: String, ports: List<Int>,
        onResult: (PortResult) -> Unit,
        onProgress: (Int, Int) -> Unit
    ) = withContext(Dispatchers.IO) {
        val gen = generation
        val pool = Executors.newFixedThreadPool(48)
        val gate = Semaphore(48)
        val lock = Any()
        var done = 0
        val jobs = ports.map { port ->
            pool.submit {
                gate.acquire()
                try {
                    if (generation == gen) {
                        probe(host, port)?.let { result ->
                            synchronized(lock) { onResult(result) }
                        }
                    }
                } finally {
                    gate.release()
                    synchronized(lock) {
                        done += 1
                        onProgress(done, ports.size)
                    }
                }
            }
        }
        for (job in jobs) {
            try {
                job.get()
            } catch (_: Exception) {
            }
        }
        pool.shutdown()
        pool.awaitTermination(5, TimeUnit.SECONDS)
    }

    private fun probe(host: String, port: Int): PortResult? {
        return try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), 1000)
                socket.soTimeout = 700
                var banner: String? = null
                try {
                    val input = socket.getInputStream()
                    val buf = ByteArray(512)
                    val n = input.read(buf)
                    if (n > 0) {
                        banner = bannerText(buf.copyOf(n))
                    }
                } catch (_: Exception) {
                }
                if (banner == null && port in ScanKit.httpPorts) {
                    try {
                        socket.getOutputStream().write(
                            "HEAD / HTTP/1.0\r\n\r\n".toByteArray(Charsets.UTF_8)
                        )
                        socket.getOutputStream().flush()
                        socket.soTimeout = 700
                        val buf = ByteArray(512)
                        val n = socket.getInputStream().read(buf)
                        if (n > 0) banner = bannerText(buf.copyOf(n))
                    } catch (_: Exception) {
                    }
                }
                PortResult(
                    host, port,
                    ScanKit.serviceNames[port] ?: "port $port", banner
                )
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun bannerText(data: ByteArray): String? {
        val text = PayloadKit.printableText(data) ?: return null
        val first = text.lineSequence().firstOrNull()?.trim() ?: return null
        return first.take(90).ifEmpty { null }
    }
}

/// TLS certificate inspector: handshake (verification off —
/// the point is to LOOK at the certificate), then the same
/// facts the iOS inspector shows.
object TlsInspector {
    fun inspect(host: String, port: Int): List<String> {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf(trustAll), java.security.SecureRandom())
        val socket = sslContext.socketFactory.createSocket() as SSLSocket
        return try {
            socket.connect(InetSocketAddress(host, port), 4000)
            socket.soTimeout = 4000
            socket.startHandshake()
            val session = socket.session
            val certs = session.peerCertificates
                .filterIsInstance<X509Certificate>()
            val lines = mutableListOf<String>()
            lines.add("Protocol: ${session.protocol}")
            lines.add("Cipher: ${session.cipherSuite}")
            lines.add("Chain: ${certs.size} certificate(s)")
            val format = java.text.SimpleDateFormat(
                "yyyy-MM-dd HH:mm 'UTC'", java.util.Locale.US
            )
            format.timeZone = java.util.TimeZone.getTimeZone("UTC")
            certs.forEachIndexed { index, cert ->
                lines.add("— Certificate ${index + 1} —")
                lines.add("Subject: ${cert.subjectX500Principal.name}")
                lines.add("Issuer: ${cert.issuerX500Principal.name}")
                if (cert.subjectX500Principal == cert.issuerX500Principal) {
                    lines.add("Self-signed: yes (subject == issuer)")
                }
                lines.add("Serial: ${cert.serialNumber.toString(16)}")
                lines.add("Valid: ${format.format(cert.notBefore)} → ${format.format(cert.notAfter)}")
                val now = Date()
                lines.add(
                    "Status now: " + when {
                        now.before(cert.notBefore) -> "not yet valid"
                        now.after(cert.notAfter) -> "EXPIRED"
                        else -> "valid"
                    }
                )
                lines.add("Signature: ${cert.sigAlgName}")
                val keyInfo = when (val key = cert.publicKey) {
                    is RSAPublicKey -> "RSA ${key.modulus.bitLength()}-bit"
                    else -> "${cert.publicKey.algorithm} ${cert.publicKey.format ?: ""}".trim()
                }
                lines.add("Key: $keyInfo")
                val sans = try {
                    cert.subjectAlternativeNames?.mapNotNull { entry ->
                        val value = entry.getOrNull(1)?.toString()
                        val type = entry.getOrNull(0)?.toString()
                        if (value != null) "$type:$value" else null
                    } ?: emptyList()
                } catch (_: Exception) {
                    emptyList()
                }
                if (sans.isNotEmpty()) {
                    lines.add("SANs: ${sans.joinToString(", ")}")
                }
                val digest = MessageDigest.getInstance("SHA-256")
                    .digest(cert.encoded)
                lines.add(
                    "SHA-256: " + digest.joinToString(":") { "%02x".format(it) }
                        .uppercase()
                )
            }
            lines
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }
}

/// DNS toolkit: one A query to 1.1.1.1, TXID + QR validated,
/// RCODE surfaced — the iOS rules.
object DnsKit {
    fun lookup(name: String): List<String> {
        val id = (0..0xFFFF).random()
        val query = buildQuery(id, name)
        val socket = DatagramSocket()
        socket.soTimeout = 3000
        return try {
            socket.send(
                DatagramPacket(query, query.size, InetAddress.getByName("1.1.1.1"), 53)
            )
            val buf = ByteArray(2048)
            val packet = DatagramPacket(buf, buf.size)
            socket.receive(packet)
            val data = packet.data.copyOf(packet.length)
            parseResponse(data, id, name)
        } catch (e: Exception) {
            listOf("lookup failed: ${e.message}")
        } finally {
            socket.close()
        }
    }

    private fun buildQuery(id: Int, name: String): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        out.write((id shr 8) and 0xFF)
        out.write(id and 0xFF)
        out.write(byteArrayOf(0x01, 0x00))  // RD, QDCOUNT below
        out.write(byteArrayOf(0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
        for (label in name.trimEnd('.').split('.')) {
            val bytes = label.toByteArray(Charsets.UTF_8)
            out.write(bytes.size)
            out.write(bytes)
        }
        out.write(0)
        out.write(byteArrayOf(0x00, 0x01, 0x00, 0x01))  // A, IN
        return out.toByteArray()
    }

    private fun parseResponse(data: ByteArray, expectedId: Int, name: String): List<String> {
        if (data.size < 12) return listOf("short response")
        val id = ((data[0].toInt() and 0xFF) shl 8) or (data[1].toInt() and 0xFF)
        if (id != expectedId) return listOf("response TXID mismatch — ignored")
        val flags = ((data[2].toInt() and 0xFF) shl 8) or (data[3].toInt() and 0xFF)
        if (flags and 0x8000 == 0) return listOf("response was not a response (QR=0)")
        val rcode = flags and 0x000F
        val anCount = ((data[6].toInt() and 0xFF) shl 8) or (data[7].toInt() and 0xFF)
        val qdCount = ((data[4].toInt() and 0xFF) shl 8) or (data[5].toInt() and 0xFF)
        val lines = mutableListOf<String>()
        when (rcode) {
            0 -> {}
            3 -> {
                lines.add("NXDOMAIN — $name does not exist")
                return lines
            }
            else -> {
                lines.add("server returned RCODE $rcode")
                return lines
            }
        }
        var offset = 12
        repeat(qdCount) {
            offset = skipName(data, offset)
            offset += 4
        }
        var answers = 0
        var i = 0
        while (i < anCount && offset < data.size) {
            offset = skipName(data, offset)
            if (offset + 10 > data.size) break
            val type = ((data[offset].toInt() and 0xFF) shl 8) or
                (data[offset + 1].toInt() and 0xFF)
            val rdLength = ((data[offset + 8].toInt() and 0xFF) shl 8) or
                (data[offset + 9].toInt() and 0xFF)
            val rdataStart = offset + 10
            if (rdataStart + rdLength > data.size) break
            when (type) {
                1 -> if (rdLength == 4) {
                    lines.add(
                        "A  " + (rdataStart until rdataStart + 4).joinToString(".") {
                            (data[it].toInt() and 0xFF).toString()
                        }
                    )
                    answers += 1
                }
                28 -> if (rdLength == 16) {
                    val groups = (0 until 8).map { g ->
                        val at = rdataStart + g * 2
                        ((data[at].toInt() and 0xFF) shl 8 or
                            (data[at + 1].toInt() and 0xFF)).toString(16)
                    }
                    lines.add("AAAA  " + groups.joinToString(":"))
                    answers += 1
                }
                5 -> {
                    val target = readName(data, rdataStart)
                    lines.add("CNAME  $target")
                    answers += 1
                }
            }
            offset = rdataStart + rdLength
            i += 1
        }
        if (answers == 0) lines.add("no A/AAAA/CNAME answers for $name")
        return lines
    }

    private fun skipName(data: ByteArray, start: Int): Int {
        var offset = start
        var guard = 0
        while (offset < data.size && guard < 128) {
            val len = data[offset].toInt() and 0xFF
            if (len == 0) return offset + 1
            if (len and 0xC0 == 0xC0) return offset + 2
            offset += 1 + len
            guard += 1
        }
        return offset
    }

    private fun readName(data: ByteArray, start: Int): String {
        val parts = mutableListOf<String>()
        var offset = start
        var guard = 0
        while (offset < data.size && guard < 128) {
            val len = data[offset].toInt() and 0xFF
            if (len == 0) break
            if (len and 0xC0 == 0xC0) {
                if (offset + 1 >= data.size) break
                val pointer = ((len and 0x3F) shl 8) or (data[offset + 1].toInt() and 0xFF)
                parts.add(readName(data, pointer))
                break
            }
            if (offset + 1 + len > data.size) break
            parts.add(String(data.copyOfRange(offset + 1, offset + 1 + len), Charsets.UTF_8))
            offset += 1 + len
            guard += 1
        }
        return parts.joinToString(".")
    }
}

/// Bonjour sweep over the ten service types, via NSD.
class BonjourSweeper(context: Context) {
    data class Found(val type: String, val label: String, val name: String, val host: String?, val port: Int?)

    private val nsdManager =
        context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val listeners = mutableListOf<NsdManager.DiscoveryListener>()

    suspend fun sweep(seconds: Long = 6): List<Found> = withContext(Dispatchers.Default) {
        val found = MutableStateFlow<List<Found>>(emptyList())
        val lock = Any()
        for ((type, label) in ScanKit.bonjourTypes) {
            val listener = object : NsdManager.DiscoveryListener {
                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    try {
                        nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                            override fun onServiceResolved(resolved: NsdServiceInfo) {
                                synchronized(lock) {
                                    val entry = Found(
                                        type, label, resolved.serviceName,
                                        resolved.host?.hostAddress, resolved.port
                                    )
                                    val current = found.value
                                    if (current.none { it.type == entry.type && it.name == entry.name }) {
                                        found.value = current + entry
                                    }
                                }
                            }
                            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                        })
                    } catch (_: Exception) {
                    }
                }
                override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
                override fun onDiscoveryStarted(serviceType: String) {}
                override fun onDiscoveryStopped(serviceType: String) {}
                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            }
            listeners.add(listener)
            try {
                nsdManager.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener)
            } catch (_: Exception) {
            }
        }
        Thread.sleep(seconds * 1000)
        stop()
        found.value.sortedWith(compareBy({ it.label }, { it.name }))
    }

    fun stop() {
        for (listener in listeners) {
            try {
                nsdManager.stopServiceDiscovery(listener)
            } catch (_: Exception) {
            }
        }
        listeners.clear()
    }
}

/// Classic-pcap dissector — the iOS PcapKit's scope: both
/// endians + nanosecond magics, linktypes 0/1/101/113,
/// Ethernet/IP/ARP/TCP/UDP summaries.
object PcapKit {
    fun dissect(bytes: ByteArray): List<String> {
        if (bytes.size < 24) return listOf("not a pcap file (too small)")
        fun u32(offset: Int, little: Boolean): Long {
            val b = bytes
            return if (little) {
                (b[offset].toLong() and 0xFF) or
                    ((b[offset + 1].toLong() and 0xFF) shl 8) or
                    ((b[offset + 2].toLong() and 0xFF) shl 16) or
                    ((b[offset + 3].toLong() and 0xFF) shl 24)
            } else {
                ((b[offset].toLong() and 0xFF) shl 24) or
                    ((b[offset + 1].toLong() and 0xFF) shl 16) or
                    ((b[offset + 2].toLong() and 0xFF) shl 8) or
                    (b[offset + 3].toLong() and 0xFF)
            }
        }
        fun u16(offset: Int, little: Boolean): Int {
            return if (little) {
                (bytes[offset].toInt() and 0xFF) or
                    ((bytes[offset + 1].toInt() and 0xFF) shl 8)
            } else {
                ((bytes[offset].toInt() and 0xFF) shl 8) or
                    (bytes[offset + 1].toInt() and 0xFF)
            }
        }
        val magic = bytes.copyOf(4)
        val little: Boolean
        val nano: Boolean
        when {
            magic.contentEquals(byteArrayOf(0xd4.toByte(), 0xc3.toByte(), 0xb2.toByte(), 0xa1.toByte())) -> {
                little = true; nano = false
            }
            magic.contentEquals(byteArrayOf(0xa1.toByte(), 0xb2.toByte(), 0xc3.toByte(), 0xd4.toByte())) -> {
                little = false; nano = false
            }
            magic.contentEquals(byteArrayOf(0x4d.toByte(), 0x3c.toByte(), 0xb2.toByte(), 0xa1.toByte())) -> {
                little = true; nano = true
            }
            magic.contentEquals(byteArrayOf(0xa1.toByte(), 0xb2.toByte(), 0x3c.toByte(), 0x4d.toByte())) -> {
                little = false; nano = true
            }
            else -> return listOf("not a classic pcap file (bad magic — pcapng is not supported)")
        }
        val linkType = u32(20, little).toInt()
        val lines = mutableListOf<String>()
        lines.add(
            "pcap ${if (little) "little" else "big"}-endian" +
                (if (nano) ", nanosecond" else "") +
                ", linktype $linkType, snaplen ${u32(16, little)}"
        )
        var offset = 24
        var index = 0
        var tcp = 0
        var udp = 0
        var arp = 0
        var other = 0
        while (offset + 16 <= bytes.size && index < 200) {
            val tsSec = u32(offset, little)
            val inclLen = u32(offset + 8, little).toInt()
            val frameStart = offset + 16
            if (inclLen < 0 || frameStart + inclLen > bytes.size) break
            val frame = bytes.copyOfRange(frameStart, frameStart + inclLen)
            val summary = summarizeFrame(frame, linkType)
            when {
                summary.contains(" TCP ") -> tcp += 1
                summary.contains(" UDP ") -> udp += 1
                summary.contains("ARP") -> arp += 1
                else -> other += 1
            }
            if (index < 60) {
                lines.add("#${index + 1} t+$tsSec $summary")
            }
            offset = frameStart + inclLen
            index += 1
        }
        lines.add(
            "packets: $index (tcp $tcp · udp $udp · arp $arp · other $other)" +
                if (index >= 200) " — display capped" else ""
        )
        if (index == 0) {
            lines.add("0 packets — empty or truncated capture")
        }
        return lines
    }

    private fun summarizeFrame(frame: ByteArray, linkType: Int): String {
        var ethOffset = 0
        var etherType = -1
        when (linkType) {
            1 -> {
                if (frame.size < 14) return "${frame.size} B (short ethernet)"
                etherType = ((frame[12].toInt() and 0xFF) shl 8) or
                    (frame[13].toInt() and 0xFF)
                ethOffset = 14
            }
            113 -> {
                if (frame.size < 16) return "${frame.size} B (short sll)"
                etherType = ((frame[14].toInt() and 0xFF) shl 8) or
                    (frame[15].toInt() and 0xFF)
                ethOffset = 16
            }
            101 -> etherType = 0x0800
            0 -> {
                if (frame.size < 4) return "${frame.size} B"
                etherType = 0x0800
                ethOffset = 4
            }
            else -> return "${frame.size} B (linktype $linkType not dissected)"
        }
        if (etherType == 0x0806 && frame.size >= ethOffset + 28) {
            val op = ((frame[ethOffset + 6].toInt() and 0xFF) shl 8) or
                (frame[ethOffset + 7].toInt() and 0xFF)
            val senderIP = ipString(frame, ethOffset + 14)
            val senderMac = macString(frame, ethOffset + 8)
            val targetIP = ipString(frame, ethOffset + 24)
            return "ARP " + (if (op == 1) "who-has $targetIP tell $senderIP"
            else "is-at $senderIP $senderMac")
        }
        if (etherType == 0x0800 && frame.size >= ethOffset + 20) {
            val ip = ethOffset
            val ihl = (frame[ip].toInt() and 0x0F) * 4
            if (ihl < 20 || frame.size < ip + ihl) return "IPv4 (short)"
            val totalLength = ((frame[ip + 2].toInt() and 0xFF) shl 8) or
                (frame[ip + 3].toInt() and 0xFF)
            val logicalEnd = minOf(frame.size, ip + maxOf(totalLength, ihl))
            val proto = frame[ip + 9].toInt() and 0xFF
            val src = ipString(frame, ip + 12)
            val dst = ipString(frame, ip + 16)
            val l4 = ip + ihl
            return when (proto) {
                6 -> {
                    if (logicalEnd < l4 + 20) "IPv4 TCP $src → $dst (short)"
                    else {
                        val sport = ((frame[l4].toInt() and 0xFF) shl 8) or
                            (frame[l4 + 1].toInt() and 0xFF)
                        val dport = ((frame[l4 + 2].toInt() and 0xFF) shl 8) or
                            (frame[l4 + 3].toInt() and 0xFF)
                        val flags = frame[l4 + 13].toInt() and 0xFF
                        val flagText = buildString {
                            if (flags and 0x02 != 0) append("S")
                            if (flags and 0x10 != 0) append("A")
                            if (flags and 0x01 != 0) append("F")
                            if (flags and 0x04 != 0) append("R")
                            if (flags and 0x08 != 0) append("P")
                        }
                        "IPv4 TCP $src:$sport → $dst:$dport [$flagText] ${logicalEnd - l4} B"
                    }
                }
                17 -> {
                    if (logicalEnd < l4 + 8) "IPv4 UDP $src → $dst (short)"
                    else {
                        val sport = ((frame[l4].toInt() and 0xFF) shl 8) or
                            (frame[l4 + 1].toInt() and 0xFF)
                        val dport = ((frame[l4 + 2].toInt() and 0xFF) shl 8) or
                            (frame[l4 + 3].toInt() and 0xFF)
                        "IPv4 UDP $src:$sport → $dst:$dport ${logicalEnd - l4} B"
                    }
                }
                1 -> "IPv4 ICMP $src → $dst"
                else -> "IPv4 proto $proto $src → $dst"
            }
        }
        if (etherType == 0x86DD) return "IPv6 ${frame.size} B"
        return "${frame.size} B ethertype 0x${etherType.toString(16)}"
    }

    private fun ipString(frame: ByteArray, at: Int): String =
        (0 until 4).joinToString(".") { (frame[at + it].toInt() and 0xFF).toString() }

    private fun macString(frame: ByteArray, at: Int): String =
        (0 until 6).joinToString(":") { "%02x".format(frame[at + it]) }
}
