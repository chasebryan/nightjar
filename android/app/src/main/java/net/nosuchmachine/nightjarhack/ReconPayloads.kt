package net.nosuchmachine.nightjarhack

/// Wire-exact protocol first words — the Kotlin mirror of the
/// iOS ReconPayloads. The first thing a client says to a
/// service: the bytes that make a stranger introduce itself.
/// `Recon.knock` speaks the right one at every open port;
/// the bench hands one to the Send tab in a tap.
///
/// Server-first protocols (ssh, mysql) carry an empty probe:
/// the knocker just listens. Every length, offset and
/// BER/BSON/TLV envelope is computed rather than remembered.

class ReconException(message: String) : Exception(message)

data class ReconProbe(
    val name: String,
    val port: Int,
    val udp: Boolean,
    val tls: Boolean,
    val family: String,
    /// Bytes that mean "that really was the service" — empty
    /// means any reply confirms.
    val hint: ByteArray,
    val summary: String,
    val build: () -> ByteArray
)

object ReconPayloads {

    // MARK: - encoders

    private fun bytes(vararg values: Int): ByteArray =
        ByteArray(values.size) { values[it].toByte() }

    private fun rep(value: Int, count: Int): ByteArray =
        ByteArray(count) { value.toByte() }

    fun u16(value: Int): ByteArray =
        bytes((value shr 8) and 0xFF, value and 0xFF)

    fun le16(value: Int): ByteArray =
        bytes(value and 0xFF, (value shr 8) and 0xFF)

    fun u32be(value: Int): ByteArray = bytes(
        (value shr 24) and 0xFF, (value shr 16) and 0xFF,
        (value shr 8) and 0xFF, value and 0xFF
    )

    fun u64be(value: Long): ByteArray =
        u32be((value shr 32).toInt()) + u32be(value.toInt())

    fun le32(value: Int): ByteArray = bytes(
        value and 0xFF, (value shr 8) and 0xFF,
        (value shr 16) and 0xFF, (value shr 24) and 0xFF
    )

    fun u64le(value: Long): ByteArray =
        le32(value.toInt()) + le32((value shr 32).toInt())

    fun hx(text: String): ByteArray {
        val out = mutableListOf<Byte>()
        var i = 0
        while (i < text.length) {
            val end = minOf(i + 2, text.length)
            val byte = text.substring(i, end).toIntOrNull(16)
            if (byte != null) out.add(byte.toByte())
            i = end
        }
        return ByteArray(out.size) { out[it] }
    }

    private fun utf8(text: String): ByteArray = text.toByteArray(Charsets.UTF_8)

    fun berLen(size: Int): ByteArray {
        if (size < 0x80) return bytes(size)
        val tmp = mutableListOf<Int>()
        var value = size
        while (value > 0) {
            tmp.add(0, value and 0xFF)
            value = value shr 8
        }
        return bytes(0x80 or tmp.size) +
            ByteArray(tmp.size) { tmp[it].toByte() }
    }

    fun ber(tag: Int, payload: ByteArray): ByteArray =
        bytes(tag) + berLen(payload.size) + payload

    fun berInt(value: Int): ByteArray {
        if (value == 0) return ber(0x02, bytes(0x00))
        val tmp = mutableListOf<Int>()
        var v = value
        while (v > 0) {
            tmp.add(0, v and 0xFF)
            v = v shr 8
        }
        if (tmp[0] and 0x80 != 0) tmp.add(0, 0x00)
        return ber(0x02, ByteArray(tmp.size) { tmp[it].toByte() })
    }

    fun berBase128(value: Int): ByteArray {
        val chunks = mutableListOf<Int>()
        chunks.add(value and 0x7F)
        var v = value shr 7
        while (v > 0) {
            chunks.add((v and 0x7F) or 0x80)
            v = v shr 7
        }
        chunks.reverse()
        return ByteArray(chunks.size) { chunks[it].toByte() }
    }

    fun berOID(dotted: String): ByteArray {
        val parts = dotted.split(".").mapNotNull { it.toIntOrNull() }
        if (parts.size < 2) return ber(0x06, ByteArray(0))
        var body = bytes(40 * parts[0] + parts[1])
        for (part in parts.drop(2)) body += berBase128(part)
        return ber(0x06, body)
    }

    fun resp(parts: List<String>): ByteArray {
        var out = utf8("*${parts.size}\r\n")
        for (part in parts) {
            out += utf8("\$${part.toByteArray(Charsets.UTF_8).size}\r\n$part\r\n")
        }
        return out
    }

    fun mqttStr(text: String): ByteArray =
        u16(text.toByteArray(Charsets.UTF_8).size) + utf8(text)

    fun mqttRemaining(size: Int): ByteArray {
        val out = mutableListOf<Byte>()
        var value = size
        do {
            var byte = value % 128
            value /= 128
            if (value > 0) byte = byte or 0x80
            out.add(byte.toByte())
        } while (value > 0)
        return ByteArray(out.size) { out[it] }
    }

    fun dnsName(name: String): ByteArray {
        var out = ByteArray(0)
        val trimmed = if (name.endsWith(".")) name.dropLast(1) else name
        for (label in trimmed.split(".")) {
            val raw = utf8(label)
            out += bytes(raw.size) + raw
        }
        out += bytes(0)
        return out
    }

    /// NetBIOS first-level encoding: 16 characters, each split
    /// into two nibbles offset by 'A'. "*" pads with spaces.
    fun nbtName(name: String = "*"): ByteArray {
        val padded: List<Int>
        if (name == "*") {
            padded = listOf(0x2A) + List(15) { 0x20 }
        } else {
            val upper = name.uppercase().toByteArray(Charsets.UTF_8)
                .map { it.toInt() and 0xFF }.take(16).toMutableList()
            while (upper.size < 16) upper.add(0x20)
            padded = upper
        }
        var out = bytes(0x20)
        for (ch in padded) {
            out += bytes(0x41 + (ch shr 4), 0x41 + (ch and 0x0F))
        }
        out += bytes(0)
        return out
    }

    fun http(
        method: String, path: String, host: String = "localhost",
        headers: List<Pair<String, String>> = emptyList(),
        body: ByteArray = ByteArray(0)
    ): ByteArray {
        val lines = mutableListOf(
            "$method $path HTTP/1.1", "Host: $host",
            "User-Agent: nightjar", "Accept: */*"
        )
        if (body.isNotEmpty()) lines.add("Content-Length: ${body.size}")
        for ((key, value) in headers) lines.add("$key: $value")
        lines.add("Connection: close")
        return utf8(lines.joinToString("\r\n") + "\r\n\r\n") + body
    }

    fun bsonInt32(doc: List<Pair<String, Int>>): ByteArray {
        var body = ByteArray(0)
        for ((key, value) in doc) {
            body += bytes(0x10) + utf8(key) + bytes(0) + le32(value)
        }
        val size = 4 + body.size + 1
        return le32(size) + body + bytes(0)
    }

    // MARK: - builders

    val qtypes: Map<String, Int> = mapOf(
        "A" to 1, "NS" to 2, "CNAME" to 5, "SOA" to 6, "PTR" to 12,
        "MX" to 15, "TXT" to 16, "AAAA" to 28, "SRV" to 33, "ANY" to 255
    )
    val qclasses: Map<String, Int> = mapOf("IN" to 1, "CH" to 3, "HS" to 4)

    fun dnsQuery(
        name: String, qtype: String = "A", qclass: String = "IN",
        rd: Boolean = true, edns: Boolean = true
    ): ByteArray {
        var out = u16(0x1234)
        out += u16(if (rd) 0x0100 else 0x0000)
        out += u16(1) + u16(0) + u16(0) + u16(if (edns) 1 else 0)
        out += dnsName(name)
        out += u16(qtypes[qtype] ?: 1)
        out += u16(qclasses[qclass] ?: 1)
        if (edns) {
            out += bytes(0)
            out += u16(41)
            out += u16(4096)
            out += u32be(0)
            out += u16(0)
        }
        return out
    }

    fun nbnsQuery(): ByteArray {
        var out = bytes(
            0x12, 0x34, 0x00, 0x00, 0x00, 0x01,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        )
        out += nbtName()
        out += u16(0x0021)
        out += u16(0x0001)
        return out
    }

    fun ntpRequest(): ByteArray = bytes(0x1B) + rep(0, 47)

    fun snmpSysdescr(): ByteArray {
        val varbind = ber(0x30, berOID("1.3.6.1.2.1.1.1.0") + ber(0x05, ByteArray(0)))
        val pdu = ber(
            0xA0,
            berInt(0x0A0B0C0D) + berInt(0) + berInt(0) + ber(0x30, varbind)
        )
        return ber(0x30, berInt(0) + ber(0x04, utf8("public")) + pdu)
    }

    fun ssdpMsearch(): ByteArray = utf8(
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n" +
            "MAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n"
    )

    fun dhcpDiscover(): ByteArray {
        var out = bytes(0x01, 0x01, 0x06, 0x00)
        out += bytes(0x12, 0x34, 0x56, 0x78)
        out += rep(0, 4)
        out += rep(0, 16)
        out += bytes(0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01)
        out += rep(0, 10)
        out += rep(0, 64)
        out += rep(0, 128)
        out += bytes(0x63, 0x82, 0x53, 0x63)
        out += bytes(53, 1, 1)
        out += bytes(55, 4, 1, 3, 6, 15)
        out += bytes(255)
        return out
    }

    fun tftpRead(): ByteArray =
        bytes(0x00, 0x01) + utf8("nightjar") + bytes(0) +
            utf8("octet") + bytes(0)

    fun stunBinding(): ByteArray =
        bytes(0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42) +
            bytes(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11)

    fun syslogLine(): ByteArray = utf8("<14>nightjar speaking syslog\r\n")

    fun wireguardInit(): ByteArray {
        var data = bytes(0x01, 0x00, 0x00, 0x00)
        data += rep(0x11, 4)
        data += rep(0x22, 32)
        data += rep(0x33, 48)
        data += rep(0x44, 28)
        data += rep(0x55, 16)
        data += rep(0x00, 16)
        return data
    }

    fun mqttConnect(clientID: String = "nightjar"): ByteArray {
        val body = mqttStr("MQTT") + bytes(0x04, 0x02) + u16(60) +
            mqttStr(clientID)
        return bytes(0x10) + mqttRemaining(body.size) + body
    }

    fun mqttPublish(
        topic: String = "nightjar",
        payload: ByteArray = utf8("alive"),
        retain: Boolean = true
    ): ByteArray {
        val body = mqttStr(topic) + payload
        return bytes(if (retain) 0x31 else 0x30) +
            mqttRemaining(body.size) + body
    }

    /// CONNECT then a retained PUBLISH, one shot: a payload
    /// that stays living.
    fun mqttPlant(): ByteArray = mqttConnect() + mqttPublish()

    fun mssqlPrelogin(): ByteArray {
        val options = listOf(
            0x00 to 6, 0x01 to 1, 0x02 to 1, 0x03 to 4, 0x04 to 1
        )
        var offset = options.size * 5 + 1
        var head = ByteArray(0)
        for ((token, length) in options) {
            head += bytes(token)
            head += u16(offset)
            head += u16(length)
            offset += length
        }
        head += bytes(0xFF)
        val data = rep(0, 6) + bytes(0x00, 0x00) + u32be(0x1234) + bytes(0x00)
        val payload = head + data
        return bytes(0x12, 0x01) + u16(8 + payload.size) +
            bytes(0x00, 0x00, 0x01, 0x00) + payload
    }

    fun smb1Negotiate(): ByteArray {
        var dialects = ByteArray(0)
        for (dialect in listOf("NT LM 0.12", "SMB 2.002", "SMB 2.???")) {
            dialects += bytes(0x02)
            dialects += utf8(dialect)
            dialects += bytes(0)
        }
        var smb = bytes(0xFF) + utf8("SMB") + bytes(0x72)
        smb += bytes(0x00, 0x00, 0x00, 0x00)
        smb += bytes(0x18)
        smb += bytes(0x53, 0xC8)
        smb += bytes(0x00, 0x00)
        smb += rep(0, 8)
        smb += bytes(0x00, 0x00)
        smb += bytes(0xFF, 0xFE)
        smb += bytes(0x00, 0x00)
        smb += bytes(0x00, 0x00)
        smb += bytes(0x00, 0x00)
        smb += bytes(0x00)
        smb += u16(dialects.size)
        smb += dialects
        val length = smb.size
        return bytes(
            0x00, (length shr 16) and 0xFF,
            (length shr 8) and 0xFF, length and 0xFF
        ) + smb
    }

    fun smb2Negotiate(): ByteArray {
        var header = bytes(0xFE) + utf8("SMB")
        header += le16(64)
        header += le16(0)
        header += le32(0)
        header += le16(0)
        header += le16(1)
        header += le32(0)
        header += le32(0)
        header += u64le(0)
        header += le32(0)
        header += le32(0)
        header += u64le(0)
        header += rep(0, 16)
        val dialects = listOf(0x0202, 0x0210, 0x0300, 0x0302)
        var request = le16(36) + le16(dialects.size) + le16(1) +
            le16(0) + le32(0)
        request += ByteArray(16) { it.toByte() }
        request += u64le(0)
        for (dialect in dialects) request += le16(dialect)
        val message = header + request
        val length = message.size
        return bytes(
            0x00, (length shr 16) and 0xFF,
            (length shr 8) and 0xFF, length and 0xFF
        ) + message
    }

    fun rpcNull(): ByteArray {
        var packet = u32be(0x12345678)
        packet += u32be(0)
        packet += u32be(2)
        packet += u32be(100000)
        packet += u32be(2)
        packet += u32be(0)
        packet += u32be(0)
        packet += u32be(0)
        packet += u32be(0)
        packet += u32be(0)
        return packet
    }

    fun mongodbIsmaster(database: String = "admin"): ByteArray {
        val query = bsonInt32(listOf("ismaster" to 1, "helloOk" to 1))
        var body = le32(0)
        body += utf8(database) + utf8(".\$cmd") + bytes(0)
        body += le32(0) + le32(-1)
        body += query
        return le32(16 + body.size) + le32(1) + le32(0) + le32(2004) + body
    }

    fun zookeeperMntr(): ByteArray = bytes(0, 0, 0, 4) + utf8("mntr")

    fun cassandraOptions(): ByteArray =
        bytes(0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00)

    fun coapGet(path: String = "nightjar"): ByteArray {
        var out = bytes(0x40, 0x01, 0x30, 0x39)
        val segments = path.split("/")
        for ((index, segment) in segments.withIndex()) {
            val delta = if (index == 0) 11 else 0
            val raw = utf8(segment)
            out += bytes((delta shl 4) or raw.size) + raw
        }
        return out
    }

    fun modbusRead(): ByteArray = bytes(
        0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01,
        0x03, 0x00, 0x00, 0x00, 0x01
    )

    fun ldapAnonBind(): ByteArray = ber(
        0x30,
        berInt(1) + ber(0x60, berInt(3) + ber(0x04, ByteArray(0)) +
            ber(0x80, ByteArray(0)))
    )

    fun adbVersion(): ByteArray = bytes(0, 0, 0, 12) + utf8("host:version")

    fun wolMagic(
        mac: List<Int> = listOf(0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF)
    ): ByteArray {
        var out = rep(0xFF, 6)
        val macBytes = ByteArray(mac.size) { mac[it].toByte() }
        repeat(16) { out += macBytes }
        return out
    }

    fun zabbixVersion(): ByteArray {
        val body = utf8("{\"request\":\"agent.version\"}")
        return utf8("ZBXD") + bytes(0x01) + u64le(body.size.toLong()) + body
    }

    fun graphqlIntrospection(): ByteArray {
        val body = utf8(
            "{\"query\":\"{__schema{queryType{name} types{name kind}}}\"}"
        )
        return http(
            "POST", "/graphql",
            headers = listOf("Content-Type" to "application/json"),
            body = body
        )
    }

    fun httpGet(path: String = "/"): ByteArray = http("GET", path)
    fun httpOptions(): ByteArray = http("OPTIONS", "/")
    fun httpHead(): ByteArray = http("HEAD", "/")
    fun httpTrace(): ByteArray = http("TRACE", "/")
    fun httpProxyGet(): ByteArray =
        http("GET", "http://example.com/", host = "example.com")

    fun httpConnect(): ByteArray = utf8(
        "CONNECT example.com:443 HTTP/1.1\r\n" +
            "Host: example.com:443\r\n\r\n"
    )

    fun influxPing(): ByteArray = utf8(
        "GET /ping HTTP/1.1\r\nHost: localhost\r\n" +
            "Connection: close\r\n\r\n"
    )

    fun sipOptions(
        user: String = "nightjar", host: String = "127.0.0.1"
    ): ByteArray {
        var text = "OPTIONS sip:$user@$host SIP/2.0\r\n"
        text += "Via: SIP/2.0/UDP $host:5060;branch=z9hG4bKnj\r\n"
        text += "Max-Forwards: 70\r\n"
        text += "From: <sip:$user@$host>;tag=nj\r\n"
        text += "To: <sip:$user@$host>\r\n"
        text += "Call-ID: nightjar@$host\r\n"
        text += "CSeq: 1 OPTIONS\r\n"
        text += "Contact: <sip:$user@$host>\r\n"
        text += "Content-Length: 0\r\n\r\n"
        return utf8(text)
    }

    fun rtspOptions(): ByteArray =
        utf8("OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n")

    fun socks5Greeting(): ByteArray = bytes(0x05, 0x01, 0x00)

    fun socks4Connect(): ByteArray =
        bytes(0x04, 0x01, 0x00, 0x50, 0x7F, 0x00, 0x00, 0x01) +
            utf8("nightjar") + bytes(0)

    fun telnetNegotiate(): ByteArray =
        bytes(0xFF, 0xFD, 0x03, 0xFF, 0xFB, 0x18, 0xFF, 0xFB, 0x1F)

    fun vncClient(): ByteArray = utf8("RFB 003.008\n")

    fun rdpNegotiate(): ByteArray = bytes(
        0x03, 0x00, 0x00, 0x13, 0x0E, 0xE0, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x08, 0x00, 0x03, 0x00, 0x00, 0x00
    )

    fun x11Setup(): ByteArray = bytes(0x6C, 0x00, 0x0B, 0x00) + rep(0, 8)

    fun postgresSSLRequest(): ByteArray =
        bytes(0x00, 0x00, 0x00, 0x08, 0x04, 0xD2, 0x16, 0x2F)

    fun postgresStartup(): ByteArray {
        val params = utf8("user\u0000nightjar\u0000database\u0000nightjar\u0000\u0000")
        return u32be(8 + params.size) + bytes(0x00, 0x03, 0x00, 0x00) + params
    }

    fun mysqlPing(): ByteArray = bytes(0x01, 0x00, 0x00, 0x00, 0x0E)

    fun mysqlQuery(): ByteArray =
        bytes(0x01, 0x00, 0x00, 0x00, 0x03) + utf8("SELECT 1")

    // MARK: - the registry

    private fun probe(
        name: String, port: Int, family: String,
        udp: Boolean = false, tls: Boolean = false,
        hint: ByteArray = ByteArray(0), summary: String,
        build: () -> ByteArray
    ): ReconProbe = ReconProbe(name, port, udp, tls, family, hint, summary, build)

    private fun textHint(text: String): ByteArray = utf8(text)

    val all: Map<String, ReconProbe> = listOf(
        // name resolution
        probe("dns-a", 53, "dns", udp = true, hint = hx("8180"), summary = "A query") { dnsQuery("example.com", "A") },
        probe("dns-aaaa", 53, "dns", udp = true, hint = hx("8180"), summary = "AAAA query") { dnsQuery("example.com", "AAAA") },
        probe("dns-mx", 53, "dns", udp = true, hint = hx("8180"), summary = "MX query") { dnsQuery("example.com", "MX") },
        probe("dns-txt", 53, "dns", udp = true, hint = hx("8180"), summary = "TXT query") { dnsQuery("example.com", "TXT") },
        probe("dns-any", 53, "dns", udp = true, hint = hx("8180"), summary = "ANY query") { dnsQuery("example.com", "ANY") },
        probe("dns-version", 53, "dns", udp = true, hint = hx("8180"),
            summary = "CHAOS version.bind - names the resolver") { dnsQuery("version.bind", "TXT", "CH") },
        probe("dns-sd", 5353, "mdns", udp = true, hint = hx("8400"),
            summary = "mDNS service enumeration") { dnsQuery("_services._dns-sd._udp.local", "PTR", rd = false, edns = false) },
        probe("llmnr", 5355, "llmnr", udp = true, hint = hx("8000"),
            summary = "LLMNR hostname query") { dnsQuery("nightjar", "A", rd = false, edns = false) },
        probe("nbns", 137, "netbios-ns", udp = true, hint = hx("8400"),
            summary = "NBNS node-status request") { nbnsQuery() },

        // time, discovery, infrastructure
        probe("ntp", 123, "ntp", udp = true, hint = hx("1c"), summary = "NTP client request") { ntpRequest() },
        probe("snmp-sysdescr", 161, "snmp", udp = true, hint = hx("a2"),
            summary = "SNMP v1 sysDescr - names the device") { snmpSysdescr() },
        probe("ssdp", 1900, "ssdp", udp = true, hint = textHint("HTTP/1.1"),
            summary = "SSDP M-SEARCH - UPnP discovery") { ssdpMsearch() },
        probe("dhcp-discover", 67, "dhcp", udp = true, hint = hx("020106"),
            summary = "DHCP DISCOVER - ask the LAN to name itself") { dhcpDiscover() },
        probe("tftp", 69, "tftp", udp = true, hint = hx("0003"), summary = "TFTP read request") { tftpRead() },
        probe("stun", 3478, "stun", udp = true, hint = hx("0101"),
            summary = "STUN binding request - reveals the public address") { stunBinding() },
        probe("syslog", 514, "syslog", udp = true, summary = "Syslog datagram") { syslogLine() },
        probe("wireguard", 51820, "wireguard", udp = true, hint = hx("02"),
            summary = "WireGuard handshake initiation") { wireguardInit() },

        // data stores
        probe("redis-ping", 6379, "redis", hint = textHint("+PONG"), summary = "PING") { resp(listOf("PING")) },
        probe("redis-info", 6379, "redis", hint = textHint("# Server"), summary = "INFO") { resp(listOf("INFO")) },
        probe("redis-keys", 6379, "redis", hint = textHint("*"), summary = "KEYS * - the whole keyspace") { resp(listOf("KEYS", "*")) },
        probe("redis-set", 6379, "redis", hint = textHint("+OK"),
            summary = "SET nightjar was-here - a payload that stays living") { resp(listOf("SET", "nightjar", "was-here")) },
        probe("memcached-stats", 11211, "memcached", hint = textHint("STAT"), summary = "stats") { utf8("stats\r\n") },
        probe("memcached-version", 11211, "memcached", hint = textHint("VERSION"), summary = "version") { utf8("version\r\n") },
        probe("memcached-get", 11211, "memcached", hint = textHint("VALUE"), summary = "get nightjar") { utf8("get nightjar\r\n") },
        probe("mongodb-ismaster", 27017, "mongodb", hint = textHint("ismaster"),
            summary = "legacy OP_QUERY ismaster") { mongodbIsmaster() },
        probe("cassandra-options", 9042, "cassandra", hint = hx("84"), summary = "CQL native OPTIONS") { cassandraOptions() },
        probe("couchdb-root", 5984, "couchdb", hint = textHint("CouchDB"), summary = "GET /") { httpGet() },
        probe("elasticsearch-root", 9200, "elasticsearch", hint = textHint("cluster_name"), summary = "GET /") { httpGet() },
        probe("zookeeper-mntr", 2181, "zookeeper", hint = textHint("zk_"), summary = "mntr four-letter word") { zookeeperMntr() },
        probe("etcd-version", 2379, "etcd", hint = textHint("etcdserver"), summary = "GET /version") { httpGet("/version") },
        probe("consul-leader", 8500, "consul", hint = textHint("\""), summary = "GET /v1/status/leader") { httpGet("/v1/status/leader") },
        probe("vault-health", 8200, "vault", hint = textHint("initialized"), summary = "GET /v1/sys/health") { httpGet("/v1/sys/health") },

        // messaging
        probe("mqtt-connect", 1883, "mqtt", hint = hx("200200"), summary = "CONNECT - clean session") { mqttConnect() },
        probe("mqtt-plant", 1883, "mqtt", hint = hx("200200"),
            summary = "CONNECT + retained PUBLISH - the broker keeps it") { mqttPlant() },
        probe("amqp-header", 5672, "amqp", hint = textHint("AMQP"), summary = "protocol header 0-9-1") { bytes(0x41, 0x4D, 0x51, 0x50, 0x00, 0x00, 0x09, 0x01) },
        probe("stomp-connect", 61613, "stomp", hint = textHint("CONNECTED"), summary = "STOMP CONNECT") { utf8("CONNECT\naccept-version:1.2\nhost:nightjar\n\n\u0000") },
        probe("rabbitmq-overview", 15672, "rabbitmq", hint = textHint("rabbitmq_version"), summary = "management overview") { httpGet("/api/overview") },

        // mail and real-time
        probe("smtp-ehlo", 25, "smtp", hint = textHint("250"), summary = "EHLO - capabilities") { utf8("EHLO nightjar.local\r\n") },
        probe("smtp-vrfy", 25, "smtp", hint = textHint("250"), summary = "VRFY root") { utf8("VRFY root\r\n") },
        probe("smtp-quit", 25, "smtp", hint = textHint("221"), summary = "QUIT") { utf8("QUIT\r\n") },
        probe("pop3-capa", 110, "pop3", hint = textHint("+OK"), summary = "CAPA") { utf8("CAPA\r\n") },
        probe("pop3-capa-tls", 995, "pop3s", tls = true, hint = textHint("+OK"), summary = "CAPA over TLS") { utf8("CAPA\r\n") },
        probe("imap-capa", 143, "imap", hint = textHint("CAPABILITY"), summary = "CAPABILITY") { utf8("a1 CAPABILITY\r\n") },
        probe("imap-capa-tls", 993, "imaps", tls = true, hint = textHint("CAPABILITY"), summary = "CAPABILITY over TLS") { utf8("a1 CAPABILITY\r\n") },
        probe("irc-register", 6667, "irc", hint = textHint("001"), summary = "NICK/USER registration") { utf8("NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n") },
        probe("sip-options", 5060, "sip", hint = textHint("SIP/2.0"), summary = "OPTIONS - what the PBX will tell you") { sipOptions() },
        probe("sip-options-tls", 5061, "sips", tls = true, hint = textHint("SIP/2.0"), summary = "OPTIONS over TLS") { sipOptions() },
        probe("rtsp-options", 554, "rtsp", hint = textHint("RTSP/1.0"), summary = "RTSP OPTIONS") { rtspOptions() },

        // databases
        probe("postgres-sslrequest", 5432, "postgres", hint = textHint("S"),
            summary = "SSLRequest - 'S' means TLS is offered") { postgresSSLRequest() },
        probe("postgres-startup", 5432, "postgres", hint = textHint("R"),
            summary = "startup message - proves the service") { postgresStartup() },
        probe("mysql-ping", 3306, "mysql", summary = "COM_PING") { mysqlPing() },
        probe("mysql-query", 3306, "mysql", summary = "COM_QUERY SELECT 1") { mysqlQuery() },
        probe("mssql-prelogin", 1433, "mssql", hint = hx("04"),
            summary = "TDS PRELOGIN - the SQL Server opener") { mssqlPrelogin() },

        // file, directory, remote access
        probe("smb1-negotiate", 139, "smb1", hint = bytes(0xFF) + utf8("SMB"),
            summary = "SMB1 NEGOTIATE") { smb1Negotiate() },
        probe("smb2-negotiate", 445, "smb2", hint = bytes(0xFE) + utf8("SMB"),
            summary = "SMB2 NEGOTIATE - dialect list") { smb2Negotiate() },
        probe("rpc-null", 111, "portmapper", hint = hx("00000001"),
            summary = "ONC RPC NULL call to the portmapper") { rpcNull() },
        probe("rsync-modules", 873, "rsync", hint = textHint("@RSYNCD"),
            summary = "version handshake - lists modules") { utf8("@RSYNCD: 31.0\n") },
        probe("ftp-user", 21, "ftp", hint = textHint("331"), summary = "USER anonymous") { utf8("USER anonymous\r\n") },
        probe("ssh-banner", 22, "ssh", hint = textHint("SSH-"), summary = "nothing - the server speaks first") { ByteArray(0) },
        probe("telnet-negotiate", 23, "telnet", hint = hx("ff"), summary = "DO/WILL option negotiation") { telnetNegotiate() },
        probe("vnc-client", 5900, "vnc", hint = textHint("RFB"), summary = "client version handshake") { vncClient() },
        probe("rdp-negotiate", 3389, "rdp", hint = hx("0300"), summary = "TPKT + X.224 connection request") { rdpNegotiate() },
        probe("x11-setup", 6000, "x11", hint = hx("01"), summary = "X11 connection setup") { x11Setup() },
        probe("socks5-greeting", 1080, "socks5", hint = hx("05"), summary = "no-auth greeting") { socks5Greeting() },
        probe("socks4-connect", 1080, "socks4", hint = hx("005a"), summary = "SOCKS4 CONNECT to 127.0.0.1:80") { socks4Connect() },
        probe("adb-version", 5555, "adb", hint = textHint("OKAY"), summary = "host:version") { adbVersion() },
        probe("ldap-anon-bind", 389, "ldap", hint = hx("61"), summary = "anonymous simple bind") { ldapAnonBind() },
        probe("ldap-anon-bind-tls", 636, "ldaps", tls = true, hint = hx("61"), summary = "anonymous bind over TLS") { ldapAnonBind() },
        probe("wol", 9, "wake-on-lan", udp = true, summary = "magic packet - wakes a sleeping NIC") { wolMagic() },
        probe("coap-get", 5683, "coap", udp = true, hint = hx("60"), summary = "GET /nightjar (CON)") { coapGet() },
        probe("modbus-read", 502, "modbus", hint = hx("0001"), summary = "read holding registers") { modbusRead() },
        probe("zabbix-agent", 10050, "zabbix", hint = textHint("ZBXD"), summary = "agent.version request") { zabbixVersion() },

        // web, proxies, orchestration
        probe("http-get", 80, "http", hint = textHint("HTTP/1."), summary = "GET /") { httpGet() },
        probe("http-options", 80, "http", hint = textHint("HTTP/1."), summary = "OPTIONS - the Allow header") { httpOptions() },
        probe("http-head", 80, "http", hint = textHint("HTTP/1."), summary = "HEAD / - headers, no body") { httpHead() },
        probe("http-trace", 80, "http", hint = textHint("HTTP/1."), summary = "TRACE - echoes the request back") { httpTrace() },
        probe("https-get", 443, "https", tls = true, hint = textHint("HTTP/1."), summary = "GET / over TLS") { httpGet() },
        probe("graphql-introspection", 80, "graphql", hint = textHint("__schema"),
            summary = "POST /graphql - dump the whole schema") { graphqlIntrospection() },
        probe("http-proxy-get", 3128, "http-proxy", hint = textHint("HTTP/1."),
            summary = "absolute-URI GET - is it an open proxy?") { httpProxyGet() },
        probe("http-connect", 3128, "http-proxy", hint = textHint("HTTP/1."), summary = "CONNECT tunnel request") { httpConnect() },
        probe("docker-version", 2375, "docker", hint = textHint("ApiVersion"),
            summary = "GET /version - unauthenticated?") { httpGet("/version") },
        probe("docker-version-tls", 2376, "docker", tls = true, hint = textHint("ApiVersion"),
            summary = "GET /version over TLS") { httpGet("/version") },
        probe("docker-registry", 5000, "docker-registry", hint = textHint("200"), summary = "GET /v2/") { httpGet("/v2/") },
        probe("kubernetes-version", 6443, "kubernetes", tls = true, hint = textHint("gitVersion"),
            summary = "GET /version (TLS)") { httpGet("/version") },
        probe("kubelet-health", 10250, "kubelet", tls = true, hint = textHint("ok"),
            summary = "GET /healthz (TLS)") { httpGet("/healthz") },
        probe("jenkins-api", 8080, "jenkins", hint = textHint("Jenkins"), summary = "GET /api/json") { httpGet("/api/json") },
        probe("prometheus-metrics", 9090, "prometheus", hint = textHint("HELP"), summary = "GET /metrics") { httpGet("/metrics") },
        probe("grafana-health", 3000, "grafana", hint = textHint("database"), summary = "GET /api/health") { httpGet("/api/health") },
        probe("kibana-status", 5601, "kibana", hint = textHint("version"), summary = "GET /api/status") { httpGet("/api/status") },
        probe("solr-admin", 8983, "solr", hint = textHint("lucene"), summary = "admin info/system") { httpGet("/solr/admin/info/system") },
        probe("influxdb-ping", 8086, "influxdb", hint = textHint("204"), summary = "GET /ping") { influxPing() },
        probe("minio-health", 9000, "minio", hint = textHint("200"), summary = "health/live") { httpGet("/minio/health/live") },
        probe("neo4j-root", 7474, "neo4j", hint = textHint("neo4j"), summary = "GET /") { httpGet() },
        probe("gitea-version", 3000, "gitea", hint = textHint("version"), summary = "GET /api/v1/version") { httpGet("/api/v1/version") },
        probe("gitlab-readiness", 80, "gitlab", hint = textHint("GitLab"), summary = "GET /-/readiness") { httpGet("/-/readiness") },

        // small talk
        probe("echo", 7, "echo", summary = "nothing - echo") { ByteArray(0) },
        probe("daytime", 13, "daytime", summary = "nothing") { ByteArray(0) },
        probe("chargen", 19, "chargen", summary = "nothing") { ByteArray(0) },
        probe("discard", 9, "discard", summary = "throw it away") { utf8("nightjar\r\n") },
        probe("whois", 43, "whois", summary = "query a whois server") { utf8("example.com\r\n") },
        probe("finger", 79, "finger", summary = "finger a user") { utf8("nightjar\r\n") },
        probe("gopher", 70, "gopher", summary = "gopher selector") { utf8("nightjar\r\n") },
        probe("gemini", 1965, "gemini", hint = textHint("20 "), summary = "Gemini request") { utf8("gemini://nightjar/\r\n") }
    ).associateBy { it.name }

    /// One probe per port for the knocker; the rest stay
    /// available by name.
    val portMap: Map<Int, String> = mapOf(
        7 to "echo", 9 to "discard", 13 to "daytime", 19 to "chargen",
        21 to "ftp-user", 22 to "ssh-banner", 23 to "telnet-negotiate",
        25 to "smtp-ehlo", 43 to "whois", 53 to "dns-version",
        67 to "dhcp-discover", 69 to "tftp", 70 to "gopher",
        79 to "finger", 80 to "http-get", 110 to "pop3-capa",
        111 to "rpc-null", 123 to "ntp", 137 to "nbns",
        139 to "smb1-negotiate", 143 to "imap-capa", 161 to "snmp-sysdescr",
        389 to "ldap-anon-bind", 443 to "https-get", 445 to "smb2-negotiate",
        502 to "modbus-read", 554 to "rtsp-options", 587 to "smtp-ehlo",
        636 to "ldap-anon-bind-tls", 873 to "rsync-modules",
        993 to "imap-capa-tls", 995 to "pop3-capa-tls",
        1080 to "socks5-greeting", 1433 to "mssql-prelogin",
        1883 to "mqtt-connect", 1965 to "gemini", 2181 to "zookeeper-mntr",
        2375 to "docker-version", 2376 to "docker-version-tls",
        2379 to "etcd-version", 3000 to "grafana-health",
        3128 to "http-proxy-get", 3306 to "mysql-ping",
        3389 to "rdp-negotiate", 5000 to "docker-registry",
        5060 to "sip-options", 5061 to "sip-options-tls",
        5432 to "postgres-sslrequest", 5555 to "adb-version",
        5601 to "kibana-status", 5672 to "amqp-header",
        5900 to "vnc-client", 5984 to "couchdb-root", 6000 to "x11-setup",
        61613 to "stomp-connect", 6379 to "redis-ping",
        6443 to "kubernetes-version", 7474 to "neo4j-root",
        8000 to "http-get", 8080 to "jenkins-api", 8086 to "influxdb-ping",
        8200 to "vault-health", 8443 to "https-get", 8500 to "consul-leader",
        8983 to "solr-admin", 9000 to "minio-health",
        9042 to "cassandra-options", 9090 to "prometheus-metrics",
        9200 to "elasticsearch-root", 10050 to "zabbix-agent",
        10250 to "kubelet-health", 11211 to "memcached-stats",
        15672 to "rabbitmq-overview", 27017 to "mongodb-ismaster"
    )

    val udpPortMap: Map<Int, String> = mapOf(
        9 to "wol", 53 to "dns-a", 67 to "dhcp-discover", 69 to "tftp",
        123 to "ntp", 137 to "nbns", 161 to "snmp-sysdescr",
        514 to "syslog", 1900 to "ssdp", 3478 to "stun", 5353 to "dns-sd",
        5355 to "llmnr", 5683 to "coap-get", 51820 to "wireguard"
    )

    /// The knocker's default sweep: every port the library
    /// can name.
    val defaultPorts: List<Int> = portMap.keys.sorted()

    val names: List<String> get() = all.keys.sorted()

    fun probe(forPort: Int, udp: Boolean): ReconProbe? {
        val table = if (udp) udpPortMap else portMap
        val name = table[forPort] ?: return null
        return all[name]
    }

    fun build(name: String): ByteArray {
        val found = all[name]
        if (found != null) return found.build()
        val query = name.lowercase()
        val prefix = query.dropLast(1)
        val near = all.keys.filter { candidate ->
            val lowered = candidate.lowercase()
            lowered.contains(query) ||
                (prefix.isNotEmpty() && lowered.startsWith(prefix))
        }.sorted().take(5)
        val hintText = if (near.isEmpty()) {
            ""
        } else {
            " (did you mean ${near.joinToString(", ")}?)"
        }
        throw ReconException("no preset '$name'$hintText")
    }

    fun firstLine(data: ByteArray, limit: Int = 160): String {
        if (data.isEmpty()) return ""
        val text = String(data, Charsets.UTF_8)
        for (line in text.split("\n", "\r")) {
            val trimmed = line.trim()
            if (trimmed.isNotEmpty() &&
                trimmed.none { it.code < 0x20 || it.code in 0x7F..0x9F }
            ) {
                return trimmed.take(limit)
            }
        }
        return data.take(16).joinToString("") { "%02x".format(it) }
    }

    fun libraryText(): String {
        val header = "${all.size} protocol first words " +
            "(${portMap.size} tcp ports, ${udpPortMap.size} udp)"
        val rows = names.map { name ->
            val found = all.getValue(name)
            "  ${name.padEnd(24)} " +
                "${if (found.udp) "udp" else "tcp"}/${found.port}  " +
                found.summary
        }
        return (listOf(header, "") + rows).joinToString("\n")
    }
}
