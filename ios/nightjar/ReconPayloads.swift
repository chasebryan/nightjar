import Foundation

/// Wire-exact protocol first words.
///
/// The first thing a client says to a service: the bytes that make a
/// stranger introduce itself. `Recon.knock` speaks the right one at every
/// open port; `ReconBenchView` hands one to the Send tab in a tap.
///
/// Server-first protocols (ssh, mysql) carry an empty probe: the knocker
/// just listens. Every length, offset and BER/BSON/TLV envelope is
/// computed rather than remembered.

enum ReconError: Error, CustomStringConvertible {
    case unknownProbe(String, [String])

    var description: String {
        switch self {
        case .unknownProbe(let name, let near):
            let hint = near.isEmpty ? "" : " (did you mean \(near.joined(separator: ", "))?)"
            return "no preset '\(name)'\(hint)"
        }
    }
}

struct ReconProbe {
    let name: String
    let port: Int
    let udp: Bool
    let tls: Bool
    let family: String
    /// Bytes that mean "that really was the service" — empty means
    /// any reply confirms.
    let hint: Data
    let summary: String
    let build: () -> Data
}

enum ReconPayloads {

    // MARK: - encoders

    static func u16(_ value: Int) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    static func le16(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    static func u32be(_ value: Int) -> Data {
        Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    static func u64be(_ value: Int) -> Data {
        u32be(value >> 32) + u32be(value & 0xFFFF_FFFF)
    }

    static func le32(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    static func u64le(_ value: Int) -> Data {
        le32(value & 0xFFFF_FFFF) + le32(value >> 32)
    }

    static func hx(_ text: String) -> Data {
        var out = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex)
                ?? text.endIndex
            if let byte = UInt8(text[index..<next], radix: 16) { out.append(byte) }
            index = next
        }
        return out
    }

    static func berLen(_ size: Int) -> Data {
        if size < 0x80 { return Data([UInt8(size)]) }
        var out = Data()
        var value = size
        while value > 0 { out.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(out.count)]) + out
    }

    static func ber(_ tag: UInt8, _ payload: Data) -> Data {
        Data([tag]) + berLen(payload.count) + payload
    }

    static func berInt(_ value: Int) -> Data {
        if value == 0 { return ber(0x02, Data([0x00])) }
        var out = Data()
        var v = value
        while v > 0 { out.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        if out[0] & 0x80 != 0 { out.insert(0x00, at: 0) }
        return ber(0x02, out)
    }

    static func berBase128(_ value: Int) -> Data {
        var chunks: [UInt8] = [UInt8(value & 0x7F)]
        var v = value >> 7
        while v > 0 { chunks.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        return Data(chunks.reversed())
    }

    static func berOID(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return ber(0x06, Data()) }
        var body = Data([UInt8(40 * parts[0] + parts[1])])
        for part in parts.dropFirst(2) { body += berBase128(part) }
        return ber(0x06, body)
    }

    static func resp(_ parts: [String]) -> Data {
        var out = Data("*\(parts.count)\r\n".utf8)
        for part in parts { out += Data("$\(part.utf8.count)\r\n\(part)\r\n".utf8) }
        return out
    }

    static func mqttStr(_ text: String) -> Data { u16(text.utf8.count) + Data(text.utf8) }

    static func mqttRemaining(_ size: Int) -> Data {
        var out = Data()
        var value = size
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            out.append(byte)
        } while value > 0
        return out
    }

    static func dnsName(_ name: String) -> Data {
        var out = Data()
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        for label in trimmed.split(separator: ".") {
            let raw = Data(String(label).utf8)
            out.append(UInt8(raw.count))
            out += raw
        }
        out.append(0)
        return out
    }

    /// NetBIOS first-level encoding: 16 characters, each split into two
    /// nibbles offset by 'A'. "*" pads with spaces, which is 0x2A.
    static func nbtName(_ name: String = "*") -> Data {
        var padded: [UInt8]
        if name == "*" {
            padded = [0x2A] + Array(repeating: 0x20, count: 15)
        } else {
            var bytes = Array(name.uppercased().utf8).prefix(16)
            while bytes.count < 16 { bytes.append(0x20) }
            padded = Array(bytes)
        }
        var out = Data([0x20])
        for char in padded {
            out.append(UInt8(0x41 + (char >> 4)))
            out.append(UInt8(0x41 + (char & 0x0F)))
        }
        out.append(0)
        return out
    }

    static func http(_ method: String, _ path: String, host: String = "localhost",
                     headers: [(String, String)] = [], body: Data = Data()) -> Data {
        var lines = ["\(method) \(path) HTTP/1.1", "Host: \(host)",
                     "User-Agent: nightjar", "Accept: */*"]
        if !body.isEmpty { lines.append("Content-Length: \(body.count)") }
        for (key, value) in headers { lines.append("\(key): \(value)") }
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }

    static func bsonInt32(_ doc: [(String, Int)]) -> Data {
        var body = Data()
        for (key, value) in doc {
            body.append(0x10)
            body += Data(key.utf8)
            body.append(0)
            body += le32(value)
        }
        let size = 4 + body.count + 1
        return le32(size) + body + Data([0])
    }

    // MARK: - builders

    static let qtypes: [String: Int] = ["A": 1, "NS": 2, "CNAME": 5, "SOA": 6,
                                        "PTR": 12, "MX": 15, "TXT": 16,
                                        "AAAA": 28, "SRV": 33, "ANY": 255]
    static let qclasses: [String: Int] = ["IN": 1, "CH": 3, "HS": 4]

    static func dnsQuery(_ name: String, _ qtype: String = "A",
                         _ qclass: String = "IN", rd: Bool = true,
                         edns: Bool = true) -> Data {
        var out = u16(0x1234)
        out += u16(rd ? 0x0100 : 0x0000)
        out += u16(1); out += u16(0); out += u16(0); out += u16(edns ? 1 : 0)
        out += dnsName(name)
        out += u16(qtypes[qtype] ?? 1)
        out += u16(qclasses[qclass] ?? 1)
        if edns {
            out.append(0)             // root name
            out += u16(41)            // OPT
            out += u16(4096)          // UDP payload size
            out += u32be(0)           // extended rcode + flags
            out += u16(0)             // RDLEN
        }
        return out
    }

    static func nbnsQuery() -> Data {
        var out = Data([0x12, 0x34, 0x00, 0x00, 0x00, 0x01,
                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        out += nbtName()
        out += u16(0x0021)
        out += u16(0x0001)
        return out
    }

    static func ntpRequest() -> Data { Data([0x1B]) + Data(repeating: 0, count: 47) }

    static func snmpSysdescr() -> Data {
        let varbind = ber(0x30, berOID("1.3.6.1.2.1.1.1.0") + ber(0x05, Data()))
        let pdu = ber(0xA0, berInt(0x0A0B0C0D) + berInt(0) + berInt(0)
                      + ber(0x30, varbind))
        return ber(0x30, berInt(0) + ber(0x04, Data("public".utf8)) + pdu)
    }

    static func ssdpMsearch() -> Data {
        Data("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
             .utf8)
        + Data("MAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n".utf8)
    }

    static func dhcpDiscover() -> Data {
        var out = Data([0x01, 0x01, 0x06, 0x00])
        out += Data([0x12, 0x34, 0x56, 0x78])
        out += Data(repeating: 0, count: 4)
        out += Data(repeating: 0, count: 16)
        out += Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01])
        out += Data(repeating: 0, count: 10)
        out += Data(repeating: 0, count: 64)
        out += Data(repeating: 0, count: 128)
        out += Data([0x63, 0x82, 0x53, 0x63])
        out += Data([53, 1, 1])
        out += Data([55, 4, 1, 3, 6, 15])
        out += Data([255])
        return out
    }

    static func tftpRead() -> Data {
        Data([0x00, 0x01]) + Data("nightjar".utf8) + Data([0])
            + Data("octet".utf8) + Data([0])
    }

    static func stunBinding() -> Data {
        Data([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])
            + Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    }

    static func syslogLine() -> Data { Data("<14>nightjar speaking syslog\r\n".utf8) }

    static func wireguardInit() -> Data {
        // Accumulated statement by statement: the one-expression
        // Data + Data chain defeats the type checker.
        var data = Data([0x01, 0x00, 0x00, 0x00])
        data += Data(repeating: 0x11, count: 4)
        data += Data(repeating: 0x22, count: 32)
        data += Data(repeating: 0x33, count: 48)
        data += Data(repeating: 0x44, count: 28)
        data += Data(repeating: 0x55, count: 16)
        data += Data(repeating: 0x00, count: 16)
        return data
    }

    static func mqttConnect(_ clientID: String = "nightjar") -> Data {
        let body = mqttStr("MQTT") + Data([0x04, 0x02]) + u16(60) + mqttStr(clientID)
        return Data([0x10]) + mqttRemaining(body.count) + body
    }

    static func mqttPublish(_ topic: String = "nightjar",
                            _ payload: Data = Data("alive".utf8),
                            retain: Bool = true) -> Data {
        let body = mqttStr(topic) + payload
        return Data([retain ? 0x31 : 0x30]) + mqttRemaining(body.count) + body
    }

    /// CONNECT then a retained PUBLISH, one shot: a payload that stays living.
    static func mqttPlant() -> Data { mqttConnect() + mqttPublish() }

    static func mssqlPrelogin() -> Data {
        let options: [(UInt8, Int)] = [(0x00, 6), (0x01, 1), (0x02, 1),
                                       (0x03, 4), (0x04, 1)]
        var offset = options.count * 5 + 1
        var head = Data()
        for (token, length) in options {
            head.append(token)
            head += u16(offset)
            head += u16(length)
            offset += length
        }
        head.append(0xFF)
        let data = Data(repeating: 0, count: 6) + Data([0x00, 0x00])
            + u32be(0x1234) + Data([0x00])
        let payload = head + data
        return Data([0x12, 0x01]) + u16(8 + payload.count)
            + Data([0x00, 0x00, 0x01, 0x00]) + payload
    }

    static func smb1Negotiate() -> Data {
        var dialects = Data()
        for dialect in ["NT LM 0.12", "SMB 2.002", "SMB 2.???"] {
            dialects.append(0x02)
            dialects += Data(dialect.utf8)
            dialects.append(0)
        }
        var smb = Data([0xFF]) + Data("SMB".utf8) + Data([0x72])
        smb += Data([0x00, 0x00, 0x00, 0x00])   // status
        smb.append(0x18)                        // flags
        smb += Data([0x53, 0xC8])               // flags2
        smb += Data([0x00, 0x00])               // pid high
        smb += Data(repeating: 0, count: 8)     // signature
        smb += Data([0x00, 0x00])               // reserved
        smb += Data([0xFF, 0xFE])               // tid
        smb += Data([0x00, 0x00])               // pid
        smb += Data([0x00, 0x00])               // uid
        smb += Data([0x00, 0x00])               // mid
        smb.append(0x00)                        // word count
        smb += u16(dialects.count)
        smb += dialects
        let length = smb.count
        return Data([0x00, UInt8((length >> 16) & 0xFF),
                     UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]) + smb
    }

    static func smb2Negotiate() -> Data {
        var header = Data([0xFE]) + Data("SMB".utf8)
        header += le16(64)                       // StructureSize
        header += le16(0)                        // CreditCharge
        header += le32(0)                        // Status
        header += le16(0)                        // Command = NEGOTIATE
        header += le16(1)                        // CreditRequest
        header += le32(0)                        // Flags
        header += le32(0)                        // NextCommand
        header += u64le(0)                       // First request uses MessageId 0
        header += le32(0)                        // Reserved
        header += le32(0)                        // TreeId
        header += u64le(0)                       // SessionId
        header += Data(repeating: 0, count: 16) // Signature
        // SMB 3.1.1 requires negotiate contexts; offer dialects through 3.0.2.
        let dialects = [0x0202, 0x0210, 0x0300, 0x0302]
        var request = le16(36) + le16(dialects.count) + le16(1) + le16(0) + le32(0)
        request += Data((0..<16).map { UInt8($0) }) // ClientGuid
        request += u64le(0)                      // ClientStartTime
        for dialect in dialects { request += le16(dialect) }
        let message = header + request
        let length = message.count
        return Data([0x00, UInt8((length >> 16) & 0xFF),
                     UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]) + message
    }

    static func rpcNull() -> Data {
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

    static func mongodbIsmaster(_ database: String = "admin") -> Data {
        let query = bsonInt32([("ismaster", 1), ("helloOk", 1)])
        var body = le32(0)
        body += Data(database.utf8) + Data(".$cmd".utf8) + Data([0])
        body += le32(0) + le32(-1)
        body += query
        return le32(16 + body.count) + le32(1) + le32(0) + le32(2004) + body
    }

    static func zookeeperMntr() -> Data { Data([0, 0, 0, 4]) + Data("mntr".utf8) }

    static func cassandraOptions() -> Data {
        Data([0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00])
    }

    static func coapGet(_ path: String = "nightjar") -> Data {
        var out = Data([0x40, 0x01, 0x30, 0x39])
        for (index, segment) in path.split(separator: "/").enumerated() {
            let delta = index == 0 ? 11 : 0
            out.append(UInt8((delta << 4) | segment.utf8.count))
            out += Data(String(segment).utf8)
        }
        return out
    }

    static func modbusRead() -> Data {
        Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01,
              0x03, 0x00, 0x00, 0x00, 0x01])
    }

    static func ldapAnonBind() -> Data {
        ber(0x30, berInt(1) + ber(0x60, berInt(3) + ber(0x04, Data())
                                 + ber(0x80, Data())))
    }

    static func adbVersion() -> Data { Data([0, 0, 0, 12]) + Data("host:version".utf8) }

    static func wolMagic(_ mac: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]) -> Data {
        var out = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { out += Data(mac) }
        return out
    }

    static func zabbixVersion() -> Data {
        let body = Data("{\"request\":\"agent.version\"}".utf8)
        return Data("ZBXD".utf8) + Data([0x01]) + u64le(body.count) + body
    }

    static func graphqlIntrospection() -> Data {
        let body = Data("{\"query\":\"{__schema{queryType{name} types{name kind}}}\"}".utf8)
        return http("POST", "/graphql",
                    headers: [("Content-Type", "application/json")], body: body)
    }

    static func httpGet(_ path: String = "/") -> Data { http("GET", path) }
    static func httpOptions() -> Data { http("OPTIONS", "/") }
    static func httpHead() -> Data { http("HEAD", "/") }
    static func httpTrace() -> Data { http("TRACE", "/") }
    static func httpProxyGet() -> Data { http("GET", "http://example.com/", host: "example.com") }
    static func httpConnect() -> Data {
        Data("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n".utf8)
    }
    static func influxPing() -> Data {
        Data("GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".utf8)
    }

    static func sipOptions(_ user: String = "nightjar",
                           _ host: String = "127.0.0.1") -> Data {
        // Appended line by line: the one-expression concatenation
        // defeats the type checker.
        var text = "OPTIONS sip:\(user)@\(host) SIP/2.0\r\n"
        text += "Via: SIP/2.0/UDP \(host):5060;branch=z9hG4bKnj\r\n"
        text += "Max-Forwards: 70\r\n"
        text += "From: <sip:\(user)@\(host)>;tag=nj\r\n"
        text += "To: <sip:\(user)@\(host)>\r\n"
        text += "Call-ID: nightjar@\(host)\r\n"
        text += "CSeq: 1 OPTIONS\r\n"
        text += "Contact: <sip:\(user)@\(host)>\r\n"
        text += "Content-Length: 0\r\n\r\n"
        return Data(text.utf8)
    }

    static func rtspOptions() -> Data {
        Data("OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n".utf8)
    }

    static func socks5Greeting() -> Data { Data([0x05, 0x01, 0x00]) }

    static func socks4Connect() -> Data {
        Data([0x04, 0x01, 0x00, 0x50, 0x7F, 0x00, 0x00, 0x01])
            + Data("nightjar".utf8) + Data([0])
    }

    static func telnetNegotiate() -> Data {
        Data([0xFF, 0xFD, 0x03, 0xFF, 0xFB, 0x18, 0xFF, 0xFB, 0x1F])
    }

    static func vncClient() -> Data { Data("RFB 003.008\n".utf8) }

    static func rdpNegotiate() -> Data {
        Data([0x03, 0x00, 0x00, 0x13, 0x0E, 0xE0, 0x00, 0x00, 0x00, 0x00,
              0x00, 0x01, 0x00, 0x08, 0x00, 0x03, 0x00, 0x00, 0x00])
    }

    static func x11Setup() -> Data {
        Data([0x6C, 0x00, 0x0B, 0x00]) + Data(repeating: 0, count: 8)
    }

    static func postgresSSLRequest() -> Data {
        Data([0x00, 0x00, 0x00, 0x08, 0x04, 0xD2, 0x16, 0x2F])
    }

    static func postgresStartup() -> Data {
        let params = Data("user\u{0}nightjar\u{0}database\u{0}nightjar\u{0}\u{0}".utf8)
        return u32be(8 + params.count) + Data([0x00, 0x03, 0x00, 0x00]) + params
    }

    static func mysqlPing() -> Data { Data([0x01, 0x00, 0x00, 0x00, 0x0E]) }
    static func mysqlQuery() -> Data {
        Data([0x01, 0x00, 0x00, 0x00, 0x03]) + Data("SELECT 1".utf8)
    }

    // MARK: - the registry

    static let all: [String: ReconProbe] = makeAll()

    private static func makeAll() -> [String: ReconProbe] {
        var out: [String: ReconProbe] = [:]
        func add(_ name: String, _ port: Int, _ family: String,
                 udp: Bool = false, tls: Bool = false, hint: Data = Data(),
                 summary: String, _ build: @escaping () -> Data) {
            out[name] = ReconProbe(name: name, port: port, udp: udp, tls: tls,
                                   family: family, hint: hint,
                                   summary: summary, build: build)
        }

        // name resolution
        add("dns-a", 53, "dns", udp: true, hint: hx("8180"), summary: "A query") { dnsQuery("example.com", "A") }
        add("dns-aaaa", 53, "dns", udp: true, hint: hx("8180"), summary: "AAAA query") { dnsQuery("example.com", "AAAA") }
        add("dns-mx", 53, "dns", udp: true, hint: hx("8180"), summary: "MX query") { dnsQuery("example.com", "MX") }
        add("dns-txt", 53, "dns", udp: true, hint: hx("8180"), summary: "TXT query") { dnsQuery("example.com", "TXT") }
        add("dns-any", 53, "dns", udp: true, hint: hx("8180"), summary: "ANY query") { dnsQuery("example.com", "ANY") }
        add("dns-version", 53, "dns", udp: true, hint: hx("8180"),
            summary: "CHAOS version.bind - names the resolver") { dnsQuery("version.bind", "TXT", "CH") }
        add("dns-sd", 5353, "mdns", udp: true, hint: hx("8400"),
            summary: "mDNS service enumeration") { dnsQuery("_services._dns-sd._udp.local", "PTR", rd: false, edns: false) }
        add("llmnr", 5355, "llmnr", udp: true, hint: hx("8000"),
            summary: "LLMNR hostname query") { dnsQuery("nightjar", "A", rd: false, edns: false) }
        add("nbns", 137, "netbios-ns", udp: true, hint: hx("8400"),
            summary: "NBNS node-status request") { nbnsQuery() }

        // time, discovery, infrastructure
        add("ntp", 123, "ntp", udp: true, hint: hx("1c"), summary: "NTP client request") { ntpRequest() }
        add("snmp-sysdescr", 161, "snmp", udp: true, hint: hx("a2"),
            summary: "SNMP v1 sysDescr - names the device") { snmpSysdescr() }
        add("ssdp", 1900, "ssdp", udp: true, hint: Data("HTTP/1.1".utf8),
            summary: "SSDP M-SEARCH - UPnP discovery") { ssdpMsearch() }
        add("dhcp-discover", 67, "dhcp", udp: true, hint: hx("020106"),
            summary: "DHCP DISCOVER - ask the LAN to name itself") { dhcpDiscover() }
        add("tftp", 69, "tftp", udp: true, hint: hx("0003"), summary: "TFTP read request") { tftpRead() }
        add("stun", 3478, "stun", udp: true, hint: hx("0101"),
            summary: "STUN binding request - reveals the public address") { stunBinding() }
        add("syslog", 514, "syslog", udp: true, summary: "Syslog datagram") { syslogLine() }
        add("wireguard", 51820, "wireguard", udp: true, hint: hx("02"),
            summary: "WireGuard handshake initiation") { wireguardInit() }

        // data stores
        add("redis-ping", 6379, "redis", hint: Data("+PONG".utf8), summary: "PING") { resp(["PING"]) }
        add("redis-info", 6379, "redis", hint: Data("# Server".utf8), summary: "INFO") { resp(["INFO"]) }
        add("redis-keys", 6379, "redis", hint: Data("*".utf8), summary: "KEYS * - the whole keyspace") { resp(["KEYS", "*"]) }
        add("redis-set", 6379, "redis", hint: Data("+OK".utf8),
            summary: "SET nightjar was-here - a payload that stays living") { resp(["SET", "nightjar", "was-here"]) }
        add("memcached-stats", 11211, "memcached", hint: Data("STAT".utf8), summary: "stats") { Data("stats\r\n".utf8) }
        add("memcached-version", 11211, "memcached", hint: Data("VERSION".utf8), summary: "version") { Data("version\r\n".utf8) }
        add("memcached-get", 11211, "memcached", hint: Data("VALUE".utf8), summary: "get nightjar") { Data("get nightjar\r\n".utf8) }
        add("mongodb-ismaster", 27017, "mongodb", hint: Data("ismaster".utf8),
            summary: "legacy OP_QUERY ismaster") { mongodbIsmaster() }
        add("cassandra-options", 9042, "cassandra", hint: hx("84"), summary: "CQL native OPTIONS") { cassandraOptions() }
        add("couchdb-root", 5984, "couchdb", hint: Data("CouchDB".utf8), summary: "GET /") { httpGet() }
        add("elasticsearch-root", 9200, "elasticsearch", hint: Data("cluster_name".utf8), summary: "GET /") { httpGet() }
        add("zookeeper-mntr", 2181, "zookeeper", hint: Data("zk_".utf8), summary: "mntr four-letter word") { zookeeperMntr() }
        add("etcd-version", 2379, "etcd", hint: Data("etcdserver".utf8), summary: "GET /version") { httpGet("/version") }
        add("consul-leader", 8500, "consul", hint: Data("\"".utf8), summary: "GET /v1/status/leader") { httpGet("/v1/status/leader") }
        add("vault-health", 8200, "vault", hint: Data("initialized".utf8), summary: "GET /v1/sys/health") { httpGet("/v1/sys/health") }

        // messaging
        add("mqtt-connect", 1883, "mqtt", hint: hx("200200"), summary: "CONNECT - clean session") { mqttConnect() }
        add("mqtt-plant", 1883, "mqtt", hint: hx("200200"),
            summary: "CONNECT + retained PUBLISH - the broker keeps it") { mqttPlant() }
        add("amqp-header", 5672, "amqp", hint: Data("AMQP".utf8), summary: "protocol header 0-9-1") { Data([0x41, 0x4D, 0x51, 0x50, 0x00, 0x00, 0x09, 0x01]) }
        add("stomp-connect", 61613, "stomp", hint: Data("CONNECTED".utf8), summary: "STOMP CONNECT") { Data("CONNECT\naccept-version:1.2\nhost:nightjar\n\n\u{0}".utf8) }
        add("rabbitmq-overview", 15672, "rabbitmq", hint: Data("rabbitmq_version".utf8), summary: "management overview") { httpGet("/api/overview") }

        // mail and real-time
        add("smtp-ehlo", 25, "smtp", hint: Data("250".utf8), summary: "EHLO - capabilities") { Data("EHLO nightjar.local\r\n".utf8) }
        add("smtp-vrfy", 25, "smtp", hint: Data("250".utf8), summary: "VRFY root") { Data("VRFY root\r\n".utf8) }
        add("smtp-quit", 25, "smtp", hint: Data("221".utf8), summary: "QUIT") { Data("QUIT\r\n".utf8) }
        add("pop3-capa", 110, "pop3", hint: Data("+OK".utf8), summary: "CAPA") { Data("CAPA\r\n".utf8) }
        add("pop3-capa-tls", 995, "pop3s", tls: true, hint: Data("+OK".utf8), summary: "CAPA over TLS") { Data("CAPA\r\n".utf8) }
        add("imap-capa", 143, "imap", hint: Data("CAPABILITY".utf8), summary: "CAPABILITY") { Data("a1 CAPABILITY\r\n".utf8) }
        add("imap-capa-tls", 993, "imaps", tls: true, hint: Data("CAPABILITY".utf8), summary: "CAPABILITY over TLS") { Data("a1 CAPABILITY\r\n".utf8) }
        add("irc-register", 6667, "irc", hint: Data("001".utf8), summary: "NICK/USER registration") { Data("NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n".utf8) }
        add("sip-options", 5060, "sip", hint: Data("SIP/2.0".utf8), summary: "OPTIONS - what the PBX will tell you") { sipOptions() }
        add("sip-options-tls", 5061, "sips", tls: true, hint: Data("SIP/2.0".utf8), summary: "OPTIONS over TLS") { sipOptions() }
        add("rtsp-options", 554, "rtsp", hint: Data("RTSP/1.0".utf8), summary: "RTSP OPTIONS") { rtspOptions() }

        // databases
        add("postgres-sslrequest", 5432, "postgres", hint: Data("S".utf8),
            summary: "SSLRequest - 'S' means TLS is offered") { postgresSSLRequest() }
        add("postgres-startup", 5432, "postgres", hint: Data("R".utf8),
            summary: "startup message - proves the service") { postgresStartup() }
        add("mysql-ping", 3306, "mysql", summary: "COM_PING") { mysqlPing() }
        add("mysql-query", 3306, "mysql", summary: "COM_QUERY SELECT 1") { mysqlQuery() }
        add("mssql-prelogin", 1433, "mssql", hint: hx("04"),
            summary: "TDS PRELOGIN - the SQL Server opener") { mssqlPrelogin() }

        // file, directory, remote access
        add("smb1-negotiate", 139, "smb1", hint: Data([0xFF]) + Data("SMB".utf8),
            summary: "SMB1 NEGOTIATE") { smb1Negotiate() }
        add("smb2-negotiate", 445, "smb2", hint: Data([0xFE]) + Data("SMB".utf8),
            summary: "SMB2 NEGOTIATE - dialect list") { smb2Negotiate() }
        add("rpc-null", 111, "portmapper", hint: hx("00000001"),
            summary: "ONC RPC NULL call to the portmapper") { rpcNull() }
        add("rsync-modules", 873, "rsync", hint: Data("@RSYNCD".utf8),
            summary: "version handshake - lists modules") { Data("@RSYNCD: 31.0\n".utf8) }
        add("ftp-user", 21, "ftp", hint: Data("331".utf8), summary: "USER anonymous") { Data("USER anonymous\r\n".utf8) }
        add("ssh-banner", 22, "ssh", hint: Data("SSH-".utf8), summary: "nothing - the server speaks first") { Data() }
        add("telnet-negotiate", 23, "telnet", hint: hx("ff"), summary: "DO/WILL option negotiation") { telnetNegotiate() }
        add("vnc-client", 5900, "vnc", hint: Data("RFB".utf8), summary: "client version handshake") { vncClient() }
        add("rdp-negotiate", 3389, "rdp", hint: hx("0300"), summary: "TPKT + X.224 connection request") { rdpNegotiate() }
        add("x11-setup", 6000, "x11", hint: hx("01"), summary: "X11 connection setup") { x11Setup() }
        add("socks5-greeting", 1080, "socks5", hint: hx("05"), summary: "no-auth greeting") { socks5Greeting() }
        add("socks4-connect", 1080, "socks4", hint: hx("005a"), summary: "SOCKS4 CONNECT to 127.0.0.1:80") { socks4Connect() }
        add("adb-version", 5555, "adb", hint: Data("OKAY".utf8), summary: "host:version") { adbVersion() }
        add("ldap-anon-bind", 389, "ldap", hint: hx("61"), summary: "anonymous simple bind") { ldapAnonBind() }
        add("ldap-anon-bind-tls", 636, "ldaps", tls: true, hint: hx("61"), summary: "anonymous bind over TLS") { ldapAnonBind() }
        add("wol", 9, "wake-on-lan", udp: true, summary: "magic packet - wakes a sleeping NIC") { wolMagic() }
        add("coap-get", 5683, "coap", udp: true, hint: hx("60"), summary: "GET /nightjar (CON)") { coapGet() }
        add("modbus-read", 502, "modbus", hint: hx("0001"), summary: "read holding registers") { modbusRead() }
        add("zabbix-agent", 10050, "zabbix", hint: Data("ZBXD".utf8), summary: "agent.version request") { zabbixVersion() }

        // web, proxies, orchestration
        add("http-get", 80, "http", hint: Data("HTTP/1.".utf8), summary: "GET /") { httpGet() }
        add("http-options", 80, "http", hint: Data("HTTP/1.".utf8), summary: "OPTIONS - the Allow header") { httpOptions() }
        add("http-head", 80, "http", hint: Data("HTTP/1.".utf8), summary: "HEAD / - headers, no body") { httpHead() }
        add("http-trace", 80, "http", hint: Data("HTTP/1.".utf8), summary: "TRACE - echoes the request back") { httpTrace() }
        add("https-get", 443, "https", tls: true, hint: Data("HTTP/1.".utf8), summary: "GET / over TLS") { httpGet() }
        add("graphql-introspection", 80, "graphql", hint: Data("__schema".utf8),
            summary: "POST /graphql - dump the whole schema") { graphqlIntrospection() }
        add("http-proxy-get", 3128, "http-proxy", hint: Data("HTTP/1.".utf8),
            summary: "absolute-URI GET - is it an open proxy?") { httpProxyGet() }
        add("http-connect", 3128, "http-proxy", hint: Data("HTTP/1.".utf8), summary: "CONNECT tunnel request") { httpConnect() }
        add("docker-version", 2375, "docker", hint: Data("ApiVersion".utf8),
            summary: "GET /version - unauthenticated?") { httpGet("/version") }
        add("docker-version-tls", 2376, "docker", tls: true, hint: Data("ApiVersion".utf8),
            summary: "GET /version over TLS") { httpGet("/version") }
        add("docker-registry", 5000, "docker-registry", hint: Data("200".utf8), summary: "GET /v2/") { httpGet("/v2/") }
        add("kubernetes-version", 6443, "kubernetes", tls: true, hint: Data("gitVersion".utf8),
            summary: "GET /version (TLS)") { httpGet("/version") }
        add("kubelet-health", 10250, "kubelet", tls: true, hint: Data("ok".utf8),
            summary: "GET /healthz (TLS)") { httpGet("/healthz") }
        add("jenkins-api", 8080, "jenkins", hint: Data("Jenkins".utf8), summary: "GET /api/json") { httpGet("/api/json") }
        add("prometheus-metrics", 9090, "prometheus", hint: Data("HELP".utf8), summary: "GET /metrics") { httpGet("/metrics") }
        add("grafana-health", 3000, "grafana", hint: Data("database".utf8), summary: "GET /api/health") { httpGet("/api/health") }
        add("kibana-status", 5601, "kibana", hint: Data("version".utf8), summary: "GET /api/status") { httpGet("/api/status") }
        add("solr-admin", 8983, "solr", hint: Data("lucene".utf8), summary: "admin info/system") { httpGet("/solr/admin/info/system") }
        add("influxdb-ping", 8086, "influxdb", hint: Data("204".utf8), summary: "GET /ping") { influxPing() }
        add("minio-health", 9000, "minio", hint: Data("200".utf8), summary: "health/live") { httpGet("/minio/health/live") }
        add("neo4j-root", 7474, "neo4j", hint: Data("neo4j".utf8), summary: "GET /") { httpGet() }
        add("gitea-version", 3000, "gitea", hint: Data("version".utf8), summary: "GET /api/v1/version") { httpGet("/api/v1/version") }
        add("gitlab-readiness", 80, "gitlab", hint: Data("GitLab".utf8), summary: "GET /-/readiness") { httpGet("/-/readiness") }

        // small talk
        add("echo", 7, "echo", summary: "nothing - echo") { Data() }
        add("daytime", 13, "daytime", summary: "nothing") { Data() }
        add("chargen", 19, "chargen", summary: "nothing") { Data() }
        add("discard", 9, "discard", summary: "throw it away") { Data("nightjar\r\n".utf8) }
        add("whois", 43, "whois", summary: "query a whois server") { Data("example.com\r\n".utf8) }
        add("finger", 79, "finger", summary: "finger a user") { Data("nightjar\r\n".utf8) }
        add("gopher", 70, "gopher", summary: "gopher selector") { Data("nightjar\r\n".utf8) }
        add("gemini", 1965, "gemini", hint: Data("20 ".utf8), summary: "Gemini request") { Data("gemini://nightjar/\r\n".utf8) }

        return out
    }

    /// One probe per port for the knocker; the rest stay available by name.
    static let portMap: [Int: String] = [
        7: "echo", 9: "discard", 13: "daytime", 19: "chargen", 21: "ftp-user",
        22: "ssh-banner", 23: "telnet-negotiate", 25: "smtp-ehlo", 43: "whois",
        53: "dns-version", 67: "dhcp-discover", 69: "tftp", 70: "gopher",
        79: "finger", 80: "http-get", 110: "pop3-capa", 111: "rpc-null",
        123: "ntp", 137: "nbns", 139: "smb1-negotiate", 143: "imap-capa",
        161: "snmp-sysdescr", 389: "ldap-anon-bind", 443: "https-get",
        445: "smb2-negotiate", 502: "modbus-read", 554: "rtsp-options",
        587: "smtp-ehlo", 636: "ldap-anon-bind-tls", 873: "rsync-modules",
        993: "imap-capa-tls", 995: "pop3-capa-tls", 1080: "socks5-greeting",
        1433: "mssql-prelogin", 1883: "mqtt-connect", 1965: "gemini",
        2181: "zookeeper-mntr", 2375: "docker-version",
        2376: "docker-version-tls", 2379: "etcd-version", 3000: "grafana-health",
        3128: "http-proxy-get", 3306: "mysql-ping", 3389: "rdp-negotiate",
        5000: "docker-registry", 5060: "sip-options", 5061: "sip-options-tls",
        5432: "postgres-sslrequest", 5555: "adb-version", 5601: "kibana-status",
        5672: "amqp-header", 5900: "vnc-client", 5984: "couchdb-root",
        6000: "x11-setup", 61613: "stomp-connect", 6379: "redis-ping",
        6443: "kubernetes-version", 7474: "neo4j-root", 8000: "http-get",
        8080: "jenkins-api", 8086: "influxdb-ping", 8200: "vault-health",
        8443: "https-get", 8500: "consul-leader", 8983: "solr-admin",
        9000: "minio-health", 9042: "cassandra-options", 9090: "prometheus-metrics",
        9200: "elasticsearch-root", 10050: "zabbix-agent",
        10250: "kubelet-health", 11211: "memcached-stats",
        15672: "rabbitmq-overview", 27017: "mongodb-ismaster",
    ]

    static let udpPortMap: [Int: String] = [
        9: "wol", 53: "dns-a", 67: "dhcp-discover", 69: "tftp", 123: "ntp",
        137: "nbns", 161: "snmp-sysdescr", 514: "syslog", 1900: "ssdp",
        3478: "stun", 5353: "dns-sd", 5355: "llmnr", 5683: "coap-get",
        51820: "wireguard",
    ]

    /// The knocker's default sweep: every port the library can name.
    static let defaultPorts: [Int] = portMap.keys.sorted()

    static var names: [String] { all.keys.sorted() }

    static func probe(forPort port: Int, udp: Bool) -> ReconProbe? {
        let table = udp ? udpPortMap : portMap
        guard let name = table[port] else { return nil }
        return all[name]
    }

    static func build(_ name: String) throws -> Data {
        guard let probe = all[name] else {
            let query = name.lowercased()
            let prefix = String(query.dropLast())
            let near = all.keys.filter {
                let candidate = $0.lowercased()
                return candidate.contains(query)
                    || (!prefix.isEmpty && candidate.hasPrefix(prefix))
            }.sorted().prefix(5)
            throw ReconError.unknownProbe(name, Array(near))
        }
        return probe.build()
    }

    static func firstLine(_ data: Data, limit: Int = 160) -> String {
        guard !data.isEmpty else { return "" }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty,
               !trimmed.unicodeScalars.contains(where: {
                   CharacterSet.controlCharacters.contains($0)
               }) {
                return String(trimmed.prefix(limit))
            }
        }
        return data.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func libraryText() -> String {
        let header = "\(all.count) protocol first words "
            + "(\(portMap.count) tcp ports, \(udpPortMap.count) udp)"
        let rows = names.map { name -> String in
            let probe = all[name]!
            return "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) "
                + "\(probe.udp ? "udp" : "tcp")/\(probe.port)  \(probe.summary)"
        }
        return ([header, ""] + rows).joined(separator: "\n")
    }
}
