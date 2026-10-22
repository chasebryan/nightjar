import Foundation
import Network
import Security

// BlacksiteBenchNames — the bench,
// wave five (fix-wave: names and
// mail). Twenty-five more engines in
// the bench's manner, this time for
// the name system and the mail roads
// that hang off it: each asks the
// public questions the protocols
// themselves publish — the records a
// zone hands any resolver, the
// greeting a mail door gives any
// stranger, the policy documents a
// domain posts for other servers —
// reads what answers, and grades it
// in the open. One knock per
// question. Nothing is sent, claimed,
// registered, or authenticated here:
// the zone transfer is asked for
// exactly once and a refusal is a
// passing grade; the dangling name is
// graded as a risk and never touched;
// the mail doors are read at the
// greeting and the capability list,
// and left before any business.

extension BlacksiteBench {

    // MARK: shared plumbing

    /// Wave five speaks through the
    /// house emit; a kindless call
    /// reads .out.
    private static func nameSay(
        _ emit: BlacksiteEmit,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    /// A connected BSD stream socket,
    /// or nil. The caller closes it.
    private static func nameSocket(
        ip: String, port: UInt16,
        timeout: Double) -> Int32? {
        let fd = socket(AF_INET, SOCK_STREAM,
                        IPPROTO_TCP)
        guard fd >= 0 else { return nil }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: timeout)
        var dest = BlacksiteNet.sockaddrIn(
            ip: ip, port: port)
        let rc = withUnsafeMutablePointer(
            to: &dest) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                connect(fd, sa, socklen_t(
                    MemoryLayout<
                        sockaddr_in>.size))
            }
        }
        guard rc == 0 else {
            close(fd)
            return nil
        }
        BetafischTap.shared.noteConnect(
            fd: fd, ip: ip, port: Int(port),
            udp: false)
        return fd
    }

    /// Read exactly n bytes, or nil.
    private static func nameReadExact(
        _ fd: Int32, _ n: Int) -> [UInt8]? {
        var out: [UInt8] = []
        out.reserveCapacity(n)
        while out.count < n {
            var chunk = [UInt8](
                repeating: 0,
                count: n - out.count)
            let got = recv(fd, &chunk,
                           chunk.count, 0)
            guard got > 0 else { return nil }
            out.append(contentsOf:
                chunk[0..<got])
        }
        BetafischTap.shared.record(
            fd: fd, outbound: false, bytes: out)
        return out
    }

    /// Send all bytes; false on
    /// failure.
    private static func nameSendAll(
        _ fd: Int32, _ bytes: [UInt8])
        -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes
                .withUnsafeBufferPointer {
                    buf in
                    send(fd,
                         buf.baseAddress!
                            + sent,
                         bytes.count - sent,
                         0)
                }
            guard n > 0 else { return false }
            sent += n
        }
        BetafischTap.shared.record(
            fd: fd, outbound: true, bytes: bytes)
        return true
    }

    /// One HTTPS fetch through the
    /// house web session — the same
    /// road the web wave rides.
    private static func nameFetch(
        _ url: URL, follow: Bool = true)
        -> (Data, HTTPURLResponse)? {
        let (session, _) = BlacksitePentest
            .webSession(follow: follow)
        defer {
            session.invalidateAndCancel()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(
            "blacksite/11.0 (nightjar)",
            forHTTPHeaderField: "User-Agent")
        guard let (data, http) =
            BlacksitePentest.syncFetch(
                session, request),
              let http = http else {
            return nil
        }
        return (data, http)
    }

    /// A fetched body as JSON, or nil.
    private static func nameJSON(
        _ data: Data) -> Any? {
        try? JSONSerialization
            .jsonObject(with: data)
    }

    /// A string field out of a JSON
    /// dictionary, numbers rendered
    /// plainly.
    private static func nameField(
        _ dict: [String: Any],
        _ key: String) -> String? {
        if let text = dict[key] as? String {
            return text
        }
        if let number = dict[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    /// A bare domain out of whatever
    /// the operator typed: scheme,
    /// path, port and trailing dot all
    /// come off; the name is lowered.
    private static func nameDomain(
        _ raw: String) -> String {
        var text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
            .lowercased()
        if let range = text.range(
            of: "://") {
            text = String(
                text[range.upperBound...])
        }
        if let slash = text.firstIndex(
            of: "/") {
            text = String(text[..<slash])
        }
        if let colon = text.lastIndex(
            of: ":"),
           Int(text[text.index(
                after: colon)...]) != nil {
            text = String(text[..<colon])
        }
        if text.hasSuffix(".") {
            text = String(text.dropLast())
        }
        return text
    }

    /// host[:port] for the mail doors:
    /// the name resolved, the port
    /// defaulted.
    private static func nameMailTarget(
        _ target: String,
        _ defaultPort: Int)
        -> (host: String, ip: String,
            port: Int)? {
        var host = target.trimmingCharacters(
            in: .whitespacesAndNewlines)
        var port = defaultPort
        if let colon = host.lastIndex(
            of: ":"),
           let p = Int(host[host.index(
                after: colon)...]),
           (1...65535).contains(p) {
            host = String(host[..<colon])
            port = p
        }
        guard !host.isEmpty,
              let resolved = BlacksiteNet
                .resolve4(host) else {
            return nil
        }
        return (host, resolved.ip, port)
    }

    /// A short random label — the
    /// name that cannot exist, for
    /// wildcard and denial questions.
    private static func nameRandomLabel()
        -> String {
        let alphabet = Array(
            "abcdefghijklmnopqrstuvwxyz0123456789")
        var out = ""
        for _ in 0..<14 {
            if let pick = alphabet.randomElement() {
                out.append(pick)
            }
        }
        return out
    }

    /// A UTC day stamp for wire times.
    private static func nameDay(
        _ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(
            identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(
            secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

/// The mail conversation, line by
/// line: a small buffered reader over
/// a stream socket, with the SMTP
/// reply shape (a three-digit word,
/// dash for "more follows", space
/// for "that is all") understood.
private final class NameTalk {
    let fd: Int32
    private var buffer: [UInt8] = []

    init(fd: Int32) {
        self.fd = fd
    }

    func sendLine(_ line: String) {
        let bytes = Array(line.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes
                .withUnsafeBufferPointer {
                    buf in
                    send(fd,
                         buf.baseAddress!
                            + sent,
                         bytes.count - sent,
                         0)
                }
            guard n > 0 else { return }
            sent += n
        }
    }

    /// One CRLF-ended line, or nil
    /// when the far end has gone.
    func nextLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(
                of: 0x0A) {
                let raw = Array(
                    buffer[0..<nl])
                buffer.removeFirst(nl + 1)
                var line = String(
                    bytes: raw,
                    encoding: .utf8) ?? ""
                if line.hasSuffix("\r") {
                    line = String(
                        line.dropLast())
                }
                return line
            }
            var chunk = [UInt8](
                repeating: 0, count: 4096)
            let got = recv(fd, &chunk,
                           chunk.count, 0)
            guard got > 0 else {
                if buffer.isEmpty {
                    return nil
                }
                let rest = String(
                    bytes: buffer,
                    encoding: .utf8) ?? ""
                buffer = []
                return rest
            }
            buffer.append(contentsOf:
                chunk[0..<got])
            if buffer.count > 65536 {
                return String(
                    bytes: buffer,
                    encoding: .utf8)
            }
        }
    }

    /// One SMTP reply: the code, and
    /// every line of it.
    func smtpReply()
        -> (code: Int, lines: [String]) {
        var lines: [String] = []
        var code = 0
        while let line = nextLine() {
            lines.append(line)
            guard line.count >= 4 else {
                break
            }
            let head = String(
                line.prefix(3))
            if let value = Int(head) {
                code = value
            }
            let mark = line[
                line.index(
                    line.startIndex,
                    offsetBy: 3)]
            if mark == " " { break }
            if mark != "-" { break }
            if lines.count > 60 { break }
        }
        return (code, lines)
    }
}

extension BlacksiteBench {

    // MARK: the DNS core

    /// One resource record, kept raw:
    /// the message rides along in the
    /// reply so names inside rdata can
    /// still be read through their
    /// compression pointers.
    struct NameRR {
        var name: String
        var type: UInt16
        var ttl: UInt32
        var rdataAt: Int
        var raw: [UInt8]
    }

    /// A whole answer: the header's
    /// word, and all three sections.
    struct NameReply {
        var msg: [UInt8]
        var rcode: Int
        var authoritative: Bool
        var truncated: Bool
        var authenticated: Bool
        var answers: [NameRR]
        var authority: [NameRR]
        var additional: [NameRR]
        var elapsed: Double
    }

    struct NameSOA {
        var mname: String
        var rname: String
        var serial: UInt32
        var refresh: UInt32
        var retry: UInt32
        var expire: UInt32
        var minimum: UInt32
    }

    static let nameTypeNames: [UInt16: String] = [
        1: "A", 2: "NS", 5: "CNAME",
        6: "SOA", 12: "PTR", 15: "MX",
        16: "TXT", 28: "AAAA",
        33: "SRV", 41: "OPT",
        43: "DS", 46: "RRSIG",
        47: "NSEC", 48: "DNSKEY",
        50: "NSEC3", 65: "HTTPS",
        252: "AXFR", 255: "ANY",
        257: "CAA",
    ]

    static let nameTypeNumbers: [String: UInt16] = [
        "A": 1, "NS": 2, "CNAME": 5,
        "SOA": 6, "PTR": 12, "MX": 15,
        "TXT": 16, "AAAA": 28,
        "SRV": 33, "DS": 43,
        "RRSIG": 46, "NSEC": 47,
        "DNSKEY": 48, "NSEC3": 50,
        "HTTPS": 65, "CAA": 257,
    ]

    private static func nameU16(
        _ msg: [UInt8], _ at: Int) -> Int {
        Int(msg[at]) << 8 | Int(msg[at + 1])
    }

    private static func nameU32(
        _ msg: [UInt8], _ at: Int)
        -> UInt32 {
        UInt32(msg[at]) << 24
            | UInt32(msg[at + 1]) << 16
            | UInt32(msg[at + 2]) << 8
            | UInt32(msg[at + 3])
    }

    /// The house resolver: the
    /// router's own ear first (derived
    /// live from the route table), a
    /// public witness when the road
    /// names none.
    private static func nameHome()
        -> (label: String, ip: String) {
        if let gateway = BlacksiteNet
            .defaultGatewayIP() {
            return (L("your router"), gateway)
        }
        return ("Cloudflare", "1.1.1.1")
    }

    /// A server's address: names are
    /// resolved on the system road;
    /// addresses pass through.
    private static func nameServerIP(
        _ server: String) -> String? {
        if BlacksiteNet.resolve4(server)
            != nil,
           server.first?.isNumber == true {
            return server
        }
        return BlacksiteNet.resolve4(
            server)?.ip
    }

    /// One question, wire-shaped:
    /// recursion desired, and — when
    /// the caller asks — an OPT
    /// record carrying the DNSSEC-OK
    /// bit, so signatures ride back.
    private static func nameBuildQuery(
        name: String, type: UInt16,
        dnssecOK: Bool) -> [UInt8] {
        var packet: [UInt8] = []
        let id = UInt16.random(
            in: 1...UInt16.max)
        packet.append(UInt8(id >> 8))
        packet.append(UInt8(id & 0xFF))
        packet.append(contentsOf:
            [0x01, 0x00,
             0x00, 0x01,
             0x00, 0x00,
             0x00, 0x00,
             0x00, dnssecOK ? 0x01 : 0x00])
        packet.append(contentsOf:
            BlacksiteDNS.encodeName(name))
        packet.append(UInt8(type >> 8))
        packet.append(UInt8(type & 0xFF))
        packet.append(contentsOf: [0, 1])
        if dnssecOK {
            // OPT: root name, type 41,
            // class 1232, TTL whose low
            // flag half carries DO.
            packet.append(contentsOf:
                [0x00, 0x00, 0x29,
                 0x04, 0xD0,
                 0x00, 0x00, 0x80, 0x00,
                 0x00, 0x00])
        }
        return packet
    }

    /// Read a whole message: header
    /// word, questions stepped over,
    /// every section parsed. The
    /// OPT pseudo-record is not a
    /// record and never joins the
    /// census.
    private static func nameParse(
        _ msg: [UInt8], elapsed: Double)
        -> NameReply? {
        guard msg.count >= 12 else {
            return nil
        }
        let byte2 = msg[2]
        let byte3 = msg[3]
        var reply = NameReply(
            msg: msg,
            rcode: Int(byte3 & 0x0F),
            authoritative: byte2 & 0x04 != 0,
            truncated: byte2 & 0x02 != 0,
            authenticated: byte3 & 0x20 != 0,
            answers: [], authority: [],
            additional: [],
            elapsed: elapsed)
        let counts = [
            nameU16(msg, 4), nameU16(msg, 6),
            nameU16(msg, 8), nameU16(msg, 10),
        ]
        var offset = 12
        for _ in 0..<counts[0] {
            let (_, next) = BlacksiteDNS
                .readName(msg, at: offset)
            offset = next + 4
        }
        func section(_ count: Int)
            -> [NameRR] {
            var out: [NameRR] = []
            for _ in 0..<count {
                let (owner, afterName) =
                    BlacksiteDNS.readName(
                        msg, at: offset)
                offset = afterName
                guard offset + 10 <= msg.count
                else { return out }
                let rtype = UInt16(
                    nameU16(msg, offset))
                let ttl = nameU32(
                    msg, offset + 4)
                let rdlen = nameU16(
                    msg, offset + 8)
                let rdata = offset + 10
                guard rdata + rdlen
                        <= msg.count
                else { return out }
                let raw = Array(
                    msg[rdata..<(rdata + rdlen)])
                if rtype != 41 {
                    out.append(NameRR(
                        name: owner,
                        type: rtype, ttl: ttl,
                        rdataAt: rdata,
                        raw: raw))
                }
                offset = rdata + rdlen
            }
            return out
        }
        reply.answers = section(counts[1])
        reply.authority = section(counts[2])
        reply.additional = section(counts[3])
        return reply
    }

    /// One question over UDP to the
    /// server named. A truncated
    /// answer is reported as it
    /// stands — the flag is part of
    /// the reading.
    static func nameQuery(
        server: String, name: String,
        type: UInt16,
        dnssecOK: Bool = false,
        timeout: Double = 3.5)
        -> NameReply? {
        guard let ip = nameServerIP(server)
        else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let packet = nameBuildQuery(
            name: name, type: type,
            dnssecOK: dnssecOK)
        var dest = BlacksiteNet.sockaddrIn(
            ip: ip, port: 53)
        let started = Date()
        let sent = withUnsafeMutablePointer(
            to: &dest) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                sendto(fd, packet,
                       packet.count, 0, sa,
                       socklen_t(MemoryLayout<
                            sockaddr_in>.size))
            }
        }
        guard sent > 0 else { return nil }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: timeout)
        var buffer = [UInt8](
            repeating: 0, count: 65536)
        let got = recv(fd, &buffer,
                       buffer.count, 0)
        let elapsed = Date()
            .timeIntervalSince(started)
        guard got >= 12 else { return nil }
        return nameParse(
            Array(buffer[0..<got]),
            elapsed: elapsed)
    }

    /// One question over TCP, and the
    /// whole conversation that
    /// follows it home: each message
    /// rides behind a two-byte length
    /// (RFC 1035 §4.2.2), and a
    /// transfer ends when the zone's
    /// SOA has closed the ring, or
    /// the message cap is reached.
    static func nameQueryTCP(
        server: String, name: String,
        type: UInt16,
        timeout: Double = 5)
        -> [NameReply] {
        guard let ip = nameServerIP(server),
              let fd = nameSocket(
                ip: ip, port: 53,
                timeout: timeout) else {
            return []
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: timeout)
        let packet = nameBuildQuery(
            name: name, type: type,
            dnssecOK: false)
        var frame: [UInt8] = [
            UInt8(packet.count >> 8),
            UInt8(packet.count & 0xFF),
        ]
        frame.append(contentsOf: packet)
        guard nameSendAll(fd, frame) else {
            return []
        }
        var replies: [NameReply] = []
        var soaSeen = 0
        while replies.count < 40 {
            guard let head = nameReadExact(
                    fd, 2) else { break }
            let length = Int(head[0]) << 8
                | Int(head[1])
            guard length >= 12,
                  let body = nameReadExact(
                    fd, length) else {
                break
            }
            guard let reply = nameParse(
                body, elapsed: 0) else {
                break
            }
            replies.append(reply)
            if reply.rcode != 0 { break }
            for record in reply.answers {
                if record.type == 6 {
                    soaSeen += 1
                }
            }
            if type != 252 || soaSeen >= 2 {
                break
            }
        }
        return replies
    }

    /// The rcode, in words.
    static func nameRcodeWord(
        _ rcode: Int) -> String {
        switch rcode {
        case 0: return "NOERROR"
        case 1: return "FORMERR"
        case 2: return "SERVFAIL"
        case 3: return "NXDOMAIN"
        case 4: return "NOTIMP"
        case 5: return "REFUSED"
        case 9: return "NOTAUTH"
        default: return "rcode \(rcode)"
        }
    }

    /// The type bitmap of an NSEC or
    /// NSEC3 record, read window by
    /// window (RFC 4034 §4.1.2).
    static func nameBitmapTypes(
        _ bytes: [UInt8]) -> [Int] {
        var types: [Int] = []
        var index = 0
        while index + 2 <= bytes.count {
            let window = Int(bytes[index])
            let length = Int(bytes[index + 1])
            let bits = Array(
                bytes[(index + 2)..<min(
                    bytes.count,
                    index + 2 + length)])
            for (byteIndex, byte)
                in bits.enumerated() {
                for bit in 0..<8
                where byte
                        & UInt8(0x80 >> bit)
                        != 0 {
                    types.append(
                        window * 256
                        + byteIndex * 8 + bit)
                }
            }
            index += 2 + length
        }
        return types
    }

    /// A DNSSEC algorithm number,
    /// named (RFC 8624's table).
    static func nameAlgName(
        _ alg: Int) -> String {
        switch alg {
        case 1: return "RSAMD5 (dead)"
        case 3: return "DSA (dead)"
        case 5: return "RSASHA1 (legacy)"
        case 7: return "RSASHA1-NSEC3 (legacy)"
        case 8: return "RSASHA256"
        case 10: return "RSASHA512"
        case 12: return "ECC-GOST (rare)"
        case 13: return "ECDSAP256SHA256"
        case 14: return "ECDSAP384SHA384"
        case 15: return "ED25519"
        case 16: return "ED448"
        default: return "algorithm \(alg)"
        }
    }

    /// A record's data, read whole:
    /// names followed through their
    /// pointers, numbers in the
    /// order the wire keeps them.
    static func nameRender(
        _ msg: [UInt8], _ rr: NameRR)
        -> String {
        let raw = rr.raw
        switch rr.type {
        case 1 where raw.count == 4:
            return raw.map(String.init)
                .joined(separator: ".")
        case 28 where raw.count == 16:
            var addr = in6_addr()
            withUnsafeMutableBytes(
                of: &addr) { ptr in
                for i in 0..<16 {
                    ptr[i] = raw[i]
                }
            }
            var buffer = [CChar](
                repeating: 0, count: 128)
            inet_ntop(AF_INET6, &addr,
                      &buffer,
                      socklen_t(buffer.count))
            return String(cString: buffer)
        case 2, 5, 12:
            return BlacksiteDNS.readName(
                msg, at: rr.rdataAt).0
        case 15 where raw.count >= 3:
            let pref = Int(raw[0]) << 8
                | Int(raw[1])
            let host = BlacksiteDNS
                .readName(
                    msg, at: rr.rdataAt + 2).0
            return "\(pref) \(host)"
        case 6:
            guard let soa = nameSOA(
                msg, rr) else {
                return "<SOA>"
            }
            return "\(soa.mname) "
                + "\(soa.rname) "
                + "\(soa.serial) "
                + "\(soa.refresh) "
                + "\(soa.retry) "
                + "\(soa.expire) "
                + "\(soa.minimum)"
        case 16:
            return nameTXTString(rr)
        case 33 where raw.count >= 7:
            let prio = Int(raw[0]) << 8
                | Int(raw[1])
            let weight = Int(raw[2]) << 8
                | Int(raw[3])
            let port = Int(raw[4]) << 8
                | Int(raw[5])
            let host = BlacksiteDNS
                .readName(
                    msg, at: rr.rdataAt + 6).0
            return "\(prio) \(weight) "
                + "\(port) \(host)"
        case 257 where raw.count >= 2:
            let flags = raw[0]
            let tagLen = Int(raw[1])
            guard raw.count >= 2 + tagLen
            else { return "<CAA>" }
            let tag = String(
                bytes: Array(
                    raw[2..<(2 + tagLen)]),
                encoding: .utf8) ?? "?"
            let value = String(
                bytes: Array(
                    raw[(2 + tagLen)...]),
                encoding: .utf8) ?? "?"
            return "\(flags) \(tag) "
                + "\"\(value)\""
        case 43 where raw.count >= 4:
            let keyTag = Int(raw[0]) << 8
                | Int(raw[1])
            let digest = raw[4...]
                .map { String(
                    format: "%02X", $0) }
                .joined()
            return "\(keyTag) \(raw[2]) "
                + "\(raw[3]) \(digest)"
        case 48 where raw.count >= 4:
            let flags = Int(raw[0]) << 8
                | Int(raw[1])
            let key = Data(
                Array(raw[4...]))
                .base64EncodedString()
            let shown = key.count > 44
                ? String(key.prefix(44))
                    + "…"
                : key
            return "\(flags) \(raw[2]) "
                + "\(raw[3]) \(shown)"
        case 46 where raw.count >= 18:
            let coveredNum = (Int(raw[0]) << 8) | Int(raw[1])
            let covered = nameTypeNames[
                    UInt16(coveredNum)]
                ?? "\(coveredNum)"
            let expiry = nameSigTime(
                nameU32(raw, 8))
            let inception = nameSigTime(
                nameU32(raw, 12))
            let keyTag = Int(raw[16]) << 8
                | Int(raw[17])
            let signer = BlacksiteDNS
                .readName(
                    msg, at: rr.rdataAt + 18).0
            let origTTL = nameU32(raw, 4)
            return "\(covered) \(raw[2]) "
                + "\(raw[3]) \(origTTL) "
                + "\(expiry) \(inception) "
                + "\(keyTag) \(signer)"
        case 47 where raw.count >= 1:
            let (next, after) = BlacksiteDNS
                .readName(msg, at: rr.rdataAt)
            let rest = Array(
                raw[(after - rr.rdataAt)...])
            let types = nameBitmapTypes(rest)
                .map { nameTypeNames[
                    UInt16($0)] ?? "\($0)" }
                .joined(separator: " ")
            return "\(next) \(types)"
        case 50 where raw.count >= 5:
            let saltLen = Int(raw[4])
            var index = 5
            let saltEnd = index + saltLen
            let salt = saltLen == 0
                ? "-"
                : Array(
                    raw[index..<saltEnd])
                    .map { String(
                        format: "%02X", $0) }
                    .joined()
            index = saltEnd
            guard index < raw.count else {
                return "<NSEC3>"
            }
            let hashLen = Int(raw[index])
            index += 1
            let hashEnd = index + hashLen
            guard hashEnd <= raw.count
            else { return "<NSEC3>" }
            let hash = Array(
                raw[index..<hashEnd])
                .map { String(
                    format: "%02X", $0) }
                .joined()
            let types = nameBitmapTypes(
                Array(raw[hashEnd...]))
                .map { nameTypeNames[
                    UInt16($0)] ?? "\($0)" }
                .joined(separator: " ")
            let head = hash.count > 24
                ? String(hash.prefix(24))
                    + "…"
                : hash
            let iterations = Int(raw[2])
                << 8 | Int(raw[3])
            return "\(raw[0]) \(raw[1]) "
                + "\(iterations) "
                + "\(salt) \(head) \(types)"
        default:
            return "<\(raw.count) bytes>"
        }
    }

    /// An RRSIG date field: seconds
    /// when it counts seconds, the
    /// YYYYMMDDHHMMSS figure when it
    /// counts digits (RFC 4034 §3.1.5).
    static func nameSigTime(
        _ value: UInt32) -> String {
        if value <= 2_000_000_000 {
            return nameDay(Date(
                timeIntervalSince1970:
                    Double(value)))
        }
        let text = String(value)
        guard text.count == 10 else {
            return text
        }
        let year = text.prefix(4)
        let rest = text.dropFirst(4)
        let month = rest.prefix(2)
        let day = rest.dropFirst(2)
            .prefix(2)
        return "\(year)-\(month)-\(day)"
    }

    /// A TXT record's one string:
    /// its character-strings are a
    /// single value split for length,
    /// and are joined back without a
    /// seam.
    static func nameTXTString(
        _ rr: NameRR) -> String {
        var out = ""
        var index = 0
        let raw = rr.raw
        while index < raw.count {
            let length = Int(raw[index])
            let from = index + 1
            let to = min(raw.count,
                         from + length)
            if from < to {
                out += String(
                    bytes: Array(
                        raw[from..<to]),
                    encoding: .utf8) ?? ""
            }
            index = max(to, index + 1)
        }
        return out
    }

    /// The SOA, field by field.
    static func nameSOA(
        _ msg: [UInt8], _ rr: NameRR)
        -> NameSOA? {
        guard rr.type == 6 else {
            return nil
        }
        let (mname, afterM) = BlacksiteDNS
            .readName(msg, at: rr.rdataAt)
        let (rname, afterR) = BlacksiteDNS
            .readName(msg, at: afterM)
        guard afterR + 20 <= msg.count
        else { return nil }
        return NameSOA(
            mname: mname, rname: rname,
            serial: nameU32(msg, afterR),
            refresh: nameU32(msg, afterR + 4),
            retry: nameU32(msg, afterR + 8),
            expire: nameU32(msg, afterR + 12),
            minimum: nameU32(msg, afterR + 16))
    }

    /// The zone a name lives in: ask
    /// for the SOA and climb one
    /// label at a time until a server
    /// answers with it. Bounded
    /// climbing — four labels at most.
    static func nameZone(
        server: String, name: String)
        -> String? {
        var candidate = name
        for _ in 0..<5 {
            if let reply = nameQuery(
                server: server,
                name: candidate, type: 6),
               reply.rcode == 0,
               reply.answers.contains(
                    where: { $0.type == 6 })
                || reply.authority.contains(
                    where: { $0.type == 6 }) {
                return candidate
            }
            guard let dot = candidate
                .firstIndex(of: ".")
            else { return nil }
            candidate = String(
                candidate[candidate.index(
                    after: dot)...])
            if candidate.isEmpty {
                return nil
            }
        }
        return nil
    }

    /// The zone's own nameservers,
    /// asked at the home resolver.
    static func nameZoneServers(
        zone: String) -> [String] {
        let home = nameHome()
        guard let reply = nameQuery(
            server: home.ip, name: zone,
            type: 2) else {
            return []
        }
        var out: [String] = []
        for record in reply.answers
        where record.type == 2 {
            let host = nameRender(
                reply.msg, record)
            if !out.contains(host) {
                out.append(host)
            }
        }
        return out
    }
}

extension BlacksiteBench {

    // MARK: dnsdeep — the whole census of one name

    /// Seven questions — A, AAAA, MX,
    /// NS, TXT, SOA, CAA — asked once
    /// each at the home resolver, and
    /// every answer read aloud. What a
    /// zone publishes about a name is
    /// the name's whole public face.
    static func dnsdeep(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let name = nameDomain(target)
            guard !name.isEmpty,
                  name.contains(".") else {
                nameSay(emit, L("dnsdeep: give a name — dnsdeep example.com"), .err)
                return
            }
            let home = nameHome()
            nameSay(emit, String(format: L("dnsdeep: the full census of %@, asked of %@ (%@)."), name, home.label, home.ip), .sys)
            let wanted: [(String, UInt16)] = [
                ("A", 1), ("AAAA", 28),
                ("MX", 15), ("NS", 2),
                ("TXT", 16), ("SOA", 6),
                ("CAA", 257),
            ]
            var answered = 0
            var refused: String? = nil
            for (label, type) in wanted {
                guard let reply = nameQuery(
                    server: home.ip, name: name,
                    type: type) else {
                    nameSay(emit, String(format: L("dnsdeep: %@ — the resolver stayed silent."), label), .out)
                    continue
                }
                if reply.rcode == 3 {
                    refused = "NXDOMAIN"
                    break
                }
                if reply.rcode != 0 {
                    nameSay(emit, String(format: L("dnsdeep: %@ — %@."), label, nameRcodeWord(reply.rcode)), .out)
                    continue
                }
                if reply.answers.isEmpty {
                    nameSay(emit, String(format: L("dnsdeep: %@ — the name is real; it keeps no %@."), label, label), .out)
                    continue
                }
                answered += 1
                for record in reply.answers {
                    nameSay(emit, String(format: L("%@. %lld IN %@ %@"), record.name, Int(record.ttl), label, nameRender(reply.msg, record)), .out)
                }
            }
            if let refused = refused {
                nameSay(emit, String(format: L("dnsdeep: verdict — %@ does not exist (%@). The census ends at the door."), name, refused), .err)
            } else if answered == 0 {
                nameSay(emit, String(format: L("dnsdeep: verdict — %@ answers none of the seven questions. A name with no face at all."), name), .err)
            } else {
                nameSay(emit, String(format: L("dnsdeep: verdict — %lld of the seven families answer for %@. What is missing above is missing for everyone, not just this probe."), answered, name), .ok)
            }
        }
    }

    // MARK: zonetransfer — ask for the whole zone, once

    /// One AXFR over TCP 53 to the
    /// zone's first nameserver — the
    /// protocol's own bulk question,
    /// asked exactly once. Handed
    /// over: the map of the house,
    /// critical. Refused: the correct
    /// posture, and a passing grade.
    static func zonetransfer(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let words = target.split(
                separator: " ").map(String.init)
            guard let first = words.first
            else {
                nameSay(emit, L("zonetransfer: give a domain — zonetransfer example.com [server]"), .err)
                return
            }
            let domain = nameDomain(first)
            var server = words.count > 1
                ? words[1] : nil
            if server == nil {
                server = nameZoneServers(
                    zone: domain).first
            }
            guard let asked = server else {
                nameSay(emit, String(format: L("zonetransfer: no nameserver answers for %@, so there is no door to knock on."), domain), .err)
                return
            }
            nameSay(emit, String(format: L("zonetransfer: asking %@ for the whole of %@, once…"), asked, domain), .sys)
            let replies = nameQueryTCP(
                server: asked, name: domain,
                type: 252)
            guard let head = replies.first
            else {
                nameSay(emit, String(format: L("zonetransfer: no TCP answer from %@ — transfers ride TCP 53 and the door stayed shut."), asked), .err)
                return
            }
            if head.rcode != 0 {
                nameSay(emit, String(format: L("zonetransfer: held — %@ answered %@. The zone stays home; that is the correct posture."), asked, nameRcodeWord(head.rcode)), .ok)
                return
            }
            // Rendered per message,
            // never across one: a
            // compression pointer means
            // nothing outside its own
            // message's bytes.
            var lines: [String] = []
            var total = 0
            for reply in replies {
                for record in reply.answers {
                    total += 1
                    if lines.count < 80 {
                        let label = nameTypeNames[
                            record.type]
                            ?? "\(record.type)"
                        lines.append(
                            String(format: L("%@. %lld IN %@ %@"), record.name, Int(record.ttl), label, nameRender(reply.msg, record)))
                    }
                }
            }
            if total == 0 {
                nameSay(emit, L("zonetransfer: the conversation ended with nothing handed over."), .out)
                return
            }
            for line in lines {
                nameSay(emit, line, .out)
            }
            if total > 80 {
                nameSay(emit, String(format: L("… and %lld more records."), total - 80), .out)
            }
            nameSay(emit, String(format: L("zonetransfer: the zone walked out — %lld record(s) for %@, handed to anyone who asks. Critical: a full map of the house."), total, domain), .err)
        }
    }

    // MARK: reverseprobe — the names behind the numbers

    /// PTR questions, one per address:
    /// a single address, or a small
    /// CIDR street (a /28 at most —
    /// sixteen doors), read as a
    /// summary of who on the street
    /// carries a name at all.
    static func reverseprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let text = target.trimmingCharacters(
                in: .whitespacesAndNewlines)
            var addresses: [String] = []
            if let slash = text.firstIndex(
                of: "/"),
               let prefix = Int(text[
                    text.index(
                        after: slash)...]) {
                let base = String(text[..<slash])
                let octets = base.split(
                    separator: ".")
                    .compactMap { Int($0) }
                guard octets.count == 4,
                      (28...32).contains(prefix)
                else {
                    nameSay(emit, L("reverseprobe: a range walk is a /28 street at most — reverseprobe 192.168.1.0/28"), .err)
                    return
                }
                let hostBits = 32 - prefix
                let count = 1 << hostBits
                var baseValue: UInt32 = 0
                for octet in octets {
                    baseValue = baseValue << 8
                        | UInt32(octet)
                }
                let mask: UInt32 = hostBits == 0
                    ? 0xFFFF_FFFF
                    : ~(UInt32(0xFFFF_FFFF)
                        >> UInt32(32 - hostBits))
                let network = baseValue & mask
                for i in 0..<count {
                    let value = network
                        + UInt32(i)
                    addresses.append(
                        "\(value >> 24)."
                        + "\((value >> 16) & 0xFF)."
                        + "\((value >> 8) & 0xFF)."
                        + "\(value & 0xFF)")
                }
            } else if !text.isEmpty {
                if text.contains(":") {
                    nameSay(emit, L("reverseprobe: this walk reads the IPv4 street — give a dotted address."), .err)
                    return
                }
                addresses = [text]
            }
            guard !addresses.isEmpty else {
                nameSay(emit, L("reverseprobe: give an address — reverseprobe 192.168.1.10"), .err)
                return
            }
            let home = nameHome()
            var named = 0
            for ip in addresses {
                let rev = ip.split(
                    separator: ".")
                    .reversed()
                    .joined(separator: ".")
                    + ".in-addr.arpa"
                guard let reply = nameQuery(
                    server: home.ip, name: rev,
                    type: 12) else {
                    continue
                }
                let ptrs = reply.answers
                    .filter { $0.type == 12 }
                if ptrs.isEmpty {
                    if addresses.count == 1 {
                        nameSay(emit, String(format: L("reverseprobe: %@ carries no name — the number answers to nothing."), ip), .out)
                    }
                    continue
                }
                named += 1
                for record in ptrs {
                    nameSay(emit, String(format: L("%@ is %@"), ip, nameRender(reply.msg, record)), .out)
                }
            }
            if addresses.count > 1 {
                nameSay(emit, String(format: L("reverseprobe: %lld of %lld numbers on the street carry a name."), named, addresses.count), named > 0 ? .ok : .out)
            }
        }
    }

    // MARK: dnscensus — do the witnesses agree

    /// The same two questions — where
    /// does the name live, in both
    /// families — put to the home
    /// resolver and three public
    /// witnesses. Who answers, how
    /// fast, and whether the stories
    /// match: disagreement is the
    /// finding.
    static func dnscensus(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let name = nameDomain(target)
            guard !name.isEmpty,
                  name.contains(".") else {
                nameSay(emit, L("dnscensus: give a name — dnscensus example.com"), .err)
                return
            }
            var witnesses: [(String, String)] = []
            let home = nameHome()
            witnesses.append(
                (home.label, home.ip))
            for extra in [("Cloudflare", "1.1.1.1"),
                          ("Google", "8.8.8.8"),
                          ("Quad9", "9.9.9.9")]
            where extra.1 != home.ip {
                witnesses.append(extra)
            }
            nameSay(emit, String(format: L("dnscensus: asking %lld witnesses where %@ lives."), witnesses.count, name), .sys)
            var stories: [String] = []
            var answeredCount = 0
            for (label, server) in witnesses {
                guard let reply = nameQuery(
                    server: server, name: name,
                    type: 1, timeout: 3)
                else {
                    nameSay(emit, String(format: L("dnscensus: %@ (%@) — no answer."), label, server), .err)
                    continue
                }
                answeredCount += 1
                let set = Array(Set(
                    reply.answers.map {
                        nameRender(
                            reply.msg, $0)
                    })).sorted()
                let ms = Int(
                    reply.elapsed * 1000)
                if reply.rcode != 0 {
                    nameSay(emit, String(format: L("dnscensus: %@ (%@) — %@ in %lld ms."), label, server, nameRcodeWord(reply.rcode), ms), .out)
                    stories.append(
                        "rcode:\(reply.rcode)")
                } else if set.isEmpty {
                    nameSay(emit, String(format: L("dnscensus: %@ (%@) — no A answers in %lld ms."), label, server, ms), .out)
                    stories.append("empty")
                } else {
                    nameSay(emit, String(format: L("dnscensus: %@ (%@) — %@ (%lld ms)."), label, server, set.joined(separator: ", "), ms), .out)
                    stories.append(
                        set.joined(separator: ","))
                }
            }
            let distinct = Set(stories)
            if answeredCount == 0 {
                nameSay(emit, L("dnscensus: verdict — nobody answered. Nothing to compare."), .err)
            } else if distinct.count == 1 {
                nameSay(emit, L("dnscensus: verdict — every witness tells the same story. The name points one way, everywhere."), .ok)
            } else {
                nameSay(emit, L("dnscensus: verdict — the witnesses disagree. Split answers, a stale cache, or a hand in the middle — worth knowing which."), .err)
            }
        }
    }

    // MARK: wildcardprobe — does the zone answer everything

    /// A name that cannot exist — a
    /// random label under the domain —
    /// asked once. If it answers, the
    /// zone answers everything, and
    /// every "does this subdomain
    /// exist" question ever asked of
    /// it is meaningless.
    static func wildcardprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("wildcardprobe: give a domain — wildcardprobe example.com"), .err)
                return
            }
            let home = nameHome()
            let ghost = nameRandomLabel()
                + "." + domain
            guard let reply = nameQuery(
                server: home.ip, name: ghost,
                type: 1) else {
                nameSay(emit, L("wildcardprobe: the resolver stayed silent — the question went unanswered, which is not the same as a no."), .err)
                return
            }
            if reply.rcode == 3 {
                nameSay(emit, String(format: L("wildcardprobe: %@ was refused by name (NXDOMAIN) — the zone admits what does not exist. No wildcard."), ghost), .ok)
                return
            }
            let answers = reply.answers
                .filter { $0.type == 1
                    || $0.type == 5 }
            if answers.isEmpty {
                nameSay(emit, String(format: L("wildcardprobe: %@ came back empty — the zone does not invent answers. No wildcard in evidence."), ghost), .ok)
            } else {
                for record in answers {
                    nameSay(emit, String(format: L("wildcardprobe: the impossible name answered — %@. %lld IN %@ %@"), ghost, Int(record.ttl), nameTypeNames[record.type] ?? "\(record.type)", nameRender(reply.msg, record)), .out)
                }
                nameSay(emit, String(format: L("wildcardprobe: verdict — %@ is a wildcard zone. Any label answers, so no subdomain census of it can be trusted, and typos land somewhere real."), domain), .err)
            }
        }
    }

    // MARK: caacheck — who may sign for the house

    /// The CAA record: which
    /// certificate authorities may
    /// issue for the name, whether
    /// wildcard issuance is separately
    /// ruled, and whether a reporting
    /// address (iodef) stands watch.
    /// No record at the name: the
    /// parent is asked once, the way
    /// issuers themselves climb.
    static func caacheck(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("caacheck: give a domain — caacheck example.com"), .err)
                return
            }
            let home = nameHome()
            var asked = domain
            var reply = nameQuery(
                server: home.ip, name: asked,
                type: 257)
            var records = reply?.answers
                .filter { $0.type == 257 }
                ?? []
            if records.isEmpty,
               let dot = domain.firstIndex(
                    of: ".") {
                let parent = String(domain[
                    domain.index(
                        after: dot)...])
                if parent.contains(".") {
                    asked = parent
                    reply = nameQuery(
                        server: home.ip,
                        name: asked, type: 257)
                    records = reply?.answers
                        .filter { $0.type == 257 }
                        ?? []
                    if !records.isEmpty {
                        nameSay(emit, String(format: L("caacheck: nothing at %@ itself — the parent %@ rules it."), domain, parent), .sys)
                    }
                }
            }
            guard let answer = reply,
                  !records.isEmpty else {
                nameSay(emit, String(format: L("caacheck: no CAA stands for %@. Any authority on earth may issue for this name, and nothing will report the asking."), domain), .err)
                return
            }
            var issuers: [String] = []
            var wildIssuers: [String] = []
            var iodef: String? = nil
            var criticalUnknown = false
            for record in records {
                nameSay(emit, String(format: L("%@. %lld IN CAA %@"), record.name, Int(record.ttl), nameRender(answer.msg, record)), .out)
                let raw = record.raw
                guard raw.count >= 2 else {
                    continue
                }
                let flags = raw[0]
                let tagLen = Int(raw[1])
                guard raw.count >= 2 + tagLen
                else { continue }
                let tag = String(
                    bytes: Array(
                        raw[2..<(2 + tagLen)]),
                    encoding: .utf8) ?? ""
                let value = String(
                    bytes: Array(
                        raw[(2 + tagLen)...]),
                    encoding: .utf8) ?? ""
                switch tag {
                case "issue":
                    issuers.append(value)
                case "issuewild":
                    wildIssuers.append(value)
                case "iodef":
                    iodef = value
                default:
                    if flags & 0x80 != 0 {
                        criticalUnknown = true
                    }
                }
            }
            if issuers.contains(";") {
                nameSay(emit, L("caacheck: verdict — the record forbids issuance outright (';' names no one). No certificate may be minted for this name."), .ok)
            } else if !issuers.isEmpty {
                nameSay(emit, String(format: L("caacheck: verdict — issuance is fenced to: %@."), issuers.joined(separator: ", ")), .ok)
            }
            if !wildIssuers.isEmpty {
                nameSay(emit, String(format: L("caacheck: wildcards are ruled separately: %@."), wildIssuers.joined(separator: ", ")), .out)
            } else if !issuers.isEmpty {
                nameSay(emit, L("caacheck: no separate wildcard rule — the issue line governs wildcards too."), .out)
            }
            if let iodef = iodef {
                nameSay(emit, String(format: L("caacheck: a watch stands — issuance requests are reported to %@."), iodef), .ok)
            } else if !issuers.isEmpty {
                nameSay(emit, L("caacheck: no iodef — nobody is told when an authority is asked."), .out)
            }
            if criticalUnknown {
                nameSay(emit, L("caacheck: an unknown tag carries the critical flag — a careful issuer must refuse this name entirely."), .out)
            }
        }
    }

    // MARK: ttlprobe — how long the answers live

    /// The TTL census: how long each
    /// family's answer is allowed to
    /// be remembered. Minutes mean a
    /// house that can move fast — or
    /// one flapping; weeks mean a
    /// change will take weeks to
    /// arrive everywhere.
    static func ttlprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("ttlprobe: give a domain — ttlprobe example.com"), .err)
                return
            }
            let home = nameHome()
            let wanted: [(String, UInt16)] = [
                ("A", 1), ("AAAA", 28),
                ("MX", 15), ("NS", 2),
                ("TXT", 16), ("SOA", 6),
                ("CAA", 257),
            ]
            var lowest: Int? = nil
            var highest: Int = 0
            var families = 0
            for (label, type) in wanted {
                guard let reply = nameQuery(
                    server: home.ip,
                    name: domain, type: type),
                      reply.rcode == 0,
                      !reply.answers.isEmpty
                else { continue }
                families += 1
                let ttls = reply.answers
                    .map { Int($0.ttl) }
                let low = ttls.min() ?? 0
                let high = ttls.max() ?? 0
                lowest = min(
                    lowest ?? high, low)
                highest = max(highest, high)
                nameSay(emit, String(format: L("ttlprobe: %@ lives %lld s (spread %lld–%lld s across %lld record(s))."), label, low, low, high, ttls.count), .out)
            }
            guard families > 0 else {
                nameSay(emit, String(format: L("ttlprobe: nothing answers for %@ — no lifetimes to read."), domain), .err)
                return
            }
            if let low = lowest, low < 60 {
                nameSay(emit, String(format: L("ttlprobe: verdict — answers as short as %lld s. The house can move in a breath — and pays a query for every breath, and a fast-flux road looks exactly like this from outside."), low), .err)
            } else if highest > 604800 {
                nameSay(emit, String(format: L("ttlprobe: verdict — answers live as long as %lld s. A change here takes over a week to reach every cache; a mistake lives just as long."), highest), .err)
            } else if let low = lowest {
                nameSay(emit, String(format: L("ttlprobe: verdict — lifetimes run %lld–%lld s across %lld families. An ordinary posture: remembered long enough to be fast, short enough to move."), low, highest, families), .ok)
            }
        }
    }

    // MARK: soacheck — the zone's own ledger

    /// The SOA read as a ledger: the
    /// serial's convention, the
    /// refresh/retry/expire rhythm the
    /// secondaries live by, and the
    /// negative lifetime — how long a
    /// "no such name" is remembered.
    static func soacheck(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("soacheck: give a domain — soacheck example.com"), .err)
                return
            }
            let home = nameHome()
            guard let zone = nameZone(
                server: home.ip, name: domain)
            else {
                nameSay(emit, String(format: L("soacheck: no zone answers for %@ — there is no ledger to read."), domain), .err)
                return
            }
            guard let reply = nameQuery(
                server: home.ip, name: zone,
                type: 6),
                  let record = (reply.answers
                    + reply.authority)
                    .first(where: {
                        $0.type == 6
                    }),
                  let soa = nameSOA(
                    reply.msg, record) else {
                nameSay(emit, String(format: L("soacheck: the zone %@ would not show its ledger."), zone), .err)
                return
            }
            let serialText = String(soa.serial)
            let kind: String
            if serialText.count == 10,
               let year = Int(
                    serialText.prefix(4)),
               (1990...2099).contains(year),
               let month = Int(serialText
                    .dropFirst(4).prefix(2)),
               (1...12).contains(month),
               let day = Int(serialText
                    .dropFirst(6).prefix(2)),
               (1...31).contains(day) {
                kind = L("date-stamped (YYYYMMDDNN) — the convention that reads itself")
            } else if soa.serial >= 1_000_000_000,
                      soa.serial < 2_147_483_648 {
                kind = L("epoch seconds — the counter that is a clock")
            } else {
                kind = L("a plain counter — incremented by hand or by signer")
            }
            nameSay(emit, String(format: L("soacheck: %@ — primary %@, keeper %@."), zone, soa.mname, soa.rname.replacingOccurrences(of: ".", with: "@", options: [], range: soa.rname.range(of: "."))), .sys)
            nameSay(emit, String(format: L("soacheck: serial %lld — %@."), Int(soa.serial), kind), .out)
            nameSay(emit, String(format: L("soacheck: refresh %lld s · retry %lld s · expire %lld s."), Int(soa.refresh), Int(soa.retry), Int(soa.expire)), .out)
            let negative = min(
                soa.minimum, record.ttl)
            nameSay(emit, String(format: L("soacheck: a 'no such name' is remembered %lld s."), Int(negative)), .out)
            var faults: [String] = []
            if soa.retry >= soa.refresh {
                faults.append(L("retry is not shorter than refresh — a sick secondary waits too long between knocks"))
            }
            if soa.expire < soa.refresh
                + soa.retry {
                faults.append(L("expire is shorter than refresh + retry — secondaries may drop the zone while it still lives"))
            }
            if soa.expire < 604800 {
                faults.append(L("expire is under a week — a long silence from the primary starves the secondaries early"))
            }
            if negative > 3600 {
                faults.append(L("the negative lifetime runs over an hour — a name fixed now stays 'gone' long after"))
            }
            if faults.isEmpty {
                nameSay(emit, L("soacheck: verdict — the ledger is sane: the rhythm holds, the negative memory is short. RFC 1912 would nod."), .ok)
            } else {
                for fault in faults {
                    nameSay(emit, String(format: L("soacheck: %@."), fault), .err)
                }
                nameSay(emit, L("soacheck: verdict — the rhythm limps. The zone still answers; its secondaries live by these numbers, and these numbers argue with each other."), .err)
            }
        }
    }

    // MARK: nsecprobe — can the zone be walked

    /// A name that cannot exist is
    /// asked of the zone, and the
    /// denial is read: NSEC proves a
    /// negative by naming the
    /// neighbours — and a chain of
    /// neighbours is the whole zone,
    /// walkable. NSEC3 hashes the
    /// names first. Neither: the zone
    /// signs its denials some other
    /// way, or does not sign at all.
    static func nsecprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("nsecprobe: give a domain — nsecprobe example.com"), .err)
                return
            }
            let home = nameHome()
            guard let zone = nameZone(
                server: home.ip, name: domain)
            else {
                nameSay(emit, String(format: L("nsecprobe: no zone answers for %@."), domain), .err)
                return
            }
            let ghost = nameRandomLabel()
                + "." + zone
            guard let reply = nameQuery(
                server: home.ip, name: ghost,
                type: 1, dnssecOK: true)
            else {
                nameSay(emit, L("nsecprobe: the resolver stayed silent."), .err)
                return
            }
            let denials = reply.authority
            let nsec = denials.filter {
                $0.type == 47
            }
            let nsec3 = denials.filter {
                $0.type == 50
            }
            for record in denials
            where record.type == 47
                || record.type == 50 {
                nameSay(emit, String(format: L("%@. %lld IN %@ %@"), record.name, Int(record.ttl), nameTypeNames[record.type] ?? "\(record.type)", nameRender(reply.msg, record)), .out)
            }
            if !nsec.isEmpty {
                nameSay(emit, String(format: L("nsecprobe: verdict — %@ proves its negatives with NSEC. Each denial names the next real name in line: the chain can be walked end to end, and the whole zone enumerated from its own answers. Signed — and legible."), zone), .err)
            } else if !nsec3.isEmpty {
                var iterations = 0
                if let first = nsec3.first,
                   first.raw.count >= 4 {
                    iterations = Int(
                        first.raw[2]) << 8
                        | Int(first.raw[3])
                }
                if iterations > 100 {
                    nameSay(emit, String(format: L("nsecprobe: verdict — NSEC3 with %lld iterations. The names are hashed, but the iteration count is a 2010 answer to a cheap-hash world: current guidance says zero extra rounds. Walking costs the attacker little more than it costs the signer."), iterations), .err)
                } else {
                    nameSay(emit, String(format: L("nsecprobe: verdict — %@ proves its negatives with NSEC3 (%lld iterations). The names are hashed before they are chained: the zone can be mapped only by guessing, not by walking."), zone, iterations), .ok)
                }
            } else if reply.rcode == 3 {
                nameSay(emit, String(format: L("nsecprobe: verdict — the denial for %@ arrived with no NSEC or NSEC3 beside it. Either the zone is unsigned, or it signs its denials online (black lies) — from the wire alone, those two read the same, and this probe claims no more than that."), ghost), .out)
            } else {
                nameSay(emit, L("nsecprobe: verdict — no denial was provoked. The ghost name answered, or the road bent; the walking question stays open."), .out)
            }
        }
    }
}

/// The STARTTLS rise, carried by
/// hand: SecureTransport reads and
/// writes through the mail door's own
/// socket, so the handshake happens
/// on the very connection that was
/// greeted in the clear. The context
/// is the connection's whole memory.
private final class NameTLSBox {
    let fd: Int32
    var strikes = 0

    init(fd: Int32) {
        self.fd = fd
    }
}

// errSSLWouldBlock (-9803),
// errSSLClosedAbort (-9804),
// errSSLClosedGraceful (-9806),
// errSSLServerAuthCompleted
// (-9841): the numbers ride as
// literals so nothing here leans on
// a spelling the importer may keep.
private func blacksiteNameTLSRead(
    _ connection: SSLConnectionRef,
    _ data: UnsafeMutableRawPointer,
    _ length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<NameTLSBox>
        .fromOpaque(connection)
        .takeUnretainedValue()
    let wanted = length.pointee
    let got = recv(box.fd, data,
                   wanted, 0)
    if got > 0 {
        length.pointee = got
        box.strikes = 0
        return got == wanted ? 0 : -9803
    }
    if got == 0 {
        length.pointee = 0
        return -9806
    }
    box.strikes += 1
    length.pointee = 0
    if box.strikes > 10 {
        return -9804
    }
    return -9803
}

private func blacksiteNameTLSWrite(
    _ connection: SSLConnectionRef,
    _ data: UnsafeRawPointer,
    _ length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<NameTLSBox>
        .fromOpaque(connection)
        .takeUnretainedValue()
    let total = length.pointee
    var sent = 0
    while sent < total {
        let n = send(box.fd,
                     data.advanced(
                        by: sent),
                     total - sent, 0)
        if n <= 0 {
            length.pointee = sent
            return -9803
        }
        sent += n
    }
    length.pointee = sent
    return 0
}

extension BlacksiteBench {

    // MARK: the rise and the papers

    /// Rise on a socket that has
    /// already agreed to STARTTLS,
    /// and stop at the moment the
    /// server shows its papers: the
    /// trust is copied there, which
    /// is all a grader needs — the
    /// certificate is read, never
    /// trusted onward.
    private static func nameTLSUpgrade(
        fd: Int32, host: String)
        -> SecTrust? {
        let box = NameTLSBox(fd: fd)
        let retained = Unmanaged
            .passRetained(box)
        defer { retained.release() }
        guard let ctx = SSLCreateContext(
            nil, .clientSide, .streamType)
        else { return nil }
        defer { _ = SSLClose(ctx) }
        _ = SSLSetIOFuncs(
            ctx, blacksiteNameTLSRead,
            blacksiteNameTLSWrite)
        _ = SSLSetConnection(
            ctx, retained.toOpaque())
        _ = host.withCString {
            SSLSetPeerDomainName(
                ctx, $0, host.utf8.count)
        }
        _ = SSLSetSessionOption(
            ctx, .breakOnServerAuth, true)
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 2)
        let status = SSLHandshake(ctx)
        guard status == -9841
                || status == 0 else {
            return nil
        }
        var trust: SecTrust?
        let rc = SSLCopyPeerTrust(
            ctx, &trust)
        guard rc == 0,
              let found = trust else {
            return nil
        }
        return found
    }

    // MARK: the DER reader

    /// One TLV's shape: tag, content
    /// start, content end. All
    /// offsets absolute in the one
    /// buffer — the walk never slices
    /// a slice, so no offset can
    /// drift its base.
    private static func nameDERTLV(
        _ b: [UInt8], _ at: Int)
        -> (tag: Int, cs: Int, ce: Int)? {
        guard at + 2 <= b.count else {
            return nil
        }
        let tag = Int(b[at])
        var index = at + 1
        let first = Int(b[index])
        index += 1
        var length = 0
        if first < 0x80 {
            length = first
        } else {
            let digits = first & 0x7F
            guard digits >= 1, digits <= 4,
                  index + digits <= b.count
            else { return nil }
            for _ in 0..<digits {
                length = length << 8
                    | Int(b[index])
                index += 1
            }
        }
        guard index + length <= b.count
        else { return nil }
        return (tag, index, index + length)
    }

    private static func nameDERChildren(
        _ b: [UInt8], _ from: Int,
        _ to: Int)
        -> [(tag: Int, cs: Int, ce: Int,
             start: Int)] {
        var out: [(tag: Int, cs: Int,
                   ce: Int, start: Int)] = []
        var index = from
        while index < to {
            guard let tlv = nameDERTLV(
                b, index) else {
                break
            }
            out.append((tag: tlv.tag,
                        cs: tlv.cs,
                        ce: tlv.ce,
                        start: index))
            index = tlv.ce
        }
        return out
    }

    private static func nameDEROID(
        _ b: [UInt8], _ from: Int,
        _ to: Int) -> String {
        guard from < to else { return "" }
        var parts = [Int(b[from]) / 40,
                     Int(b[from]) % 40]
        var value = 0
        for index in (from + 1)..<to {
            value = value << 7
                | Int(b[index] & 0x7F)
            if b[index] & 0x80 == 0 {
                parts.append(value)
                value = 0
            }
        }
        return parts.map(String.init)
            .joined(separator: ".")
    }

    /// A name's common name, if it
    /// carries one.
    private static func nameDERCN(
        _ b: [UInt8], _ from: Int,
        _ to: Int) -> String? {
        for rdn in nameDERChildren(
            b, from, to) {
            for pair in nameDERChildren(
                b, rdn.cs, rdn.ce) {
                let parts = nameDERChildren(
                    b, pair.cs, pair.ce)
                guard parts.count == 2,
                      nameDEROID(
                        b, parts[0].cs,
                        parts[0].ce)
                        == "2.5.4.3" else {
                    continue
                }
                return String(
                    bytes: Array(
                        b[parts[1].cs..<parts[1].ce]),
                    encoding: .utf8)
            }
        }
        return nil
    }

    /// A validity date, UTCTime or
    /// GeneralizedTime, read digit by
    /// digit (RFC 5280 §4.1.2.5).
    private static func nameDERTime(
        _ tag: Int, _ b: [UInt8],
        _ from: Int, _ to: Int) -> Date? {
        let text = String(
            bytes: Array(b[from..<to]),
            encoding: .ascii) ?? ""
        let digits = text.filter {
            $0.isNumber
        }
        var parts: [Int] = []
        var index = digits.startIndex
        func take(_ n: Int) -> Int? {
            guard let end = digits.index(
                index, offsetBy: n,
                limitedBy: digits.endIndex)
            else { return nil }
            let value = Int(
                digits[index..<end])
            index = end
            return value
        }
        if tag == 0x17 {
            guard let yy = take(2) else {
                return nil
            }
            parts.append(
                yy < 50 ? 2000 + yy
                    : 1900 + yy)
        } else {
            guard let yyyy = take(4) else {
                return nil
            }
            parts.append(yyyy)
        }
        for _ in 0..<5 {
            guard let piece = take(2)
            else { return nil }
            parts.append(piece)
        }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = parts[3]
        comps.minute = parts[4]
        comps.second = parts[5]
        comps.timeZone = TimeZone(
            secondsFromGMT: 0)
        return Calendar(identifier:
            .gregorian).date(from: comps)
    }

    /// An RSA modulus's bit length
    /// from its INTEGER content.
    private static func nameDERModulusBits(
        _ b: [UInt8], _ from: Int,
        _ to: Int) -> Int {
        var bytes = Array(b[from..<to])
        while bytes.count > 1,
              bytes[0] == 0 {
            bytes.removeFirst()
        }
        guard let top = bytes.first
        else { return 0 }
        return (bytes.count - 1) * 8
            + (8 - top.leadingZeroBitCount)
    }

    /// The key a subject-public-key
    /// block names, in words and
    /// weight.
    private static func nameSPKIDesc(
        _ b: [UInt8],
        _ spki: (tag: Int, cs: Int,
                 ce: Int, start: Int))
        -> String {
        let kids = nameDERChildren(
            b, spki.cs, spki.ce)
        guard kids.count == 2 else {
            return L("an unread key")
        }
        let algKids = nameDERChildren(
            b, kids[0].cs, kids[0].ce)
        guard let algFirst = algKids.first
        else { return L("an unread key") }
        let oid = nameDEROID(
            b, algFirst.cs, algFirst.ce)
        switch oid {
        case "1.2.840.113549.1.1.1":
            let bits = kids[1]
            guard bits.cs + 1 < bits.ce,
                  let seq = nameDERTLV(
                    b, bits.cs + 1) else {
                return L("an unread RSA key")
            }
            let ints = nameDERChildren(
                b, seq.cs, seq.ce)
            guard let modulus = ints.first
            else {
                return L("an unread RSA key")
            }
            let size = nameDERModulusBits(
                b, modulus.cs, modulus.ce)
            return String(
                format: L("RSA %lld"), size)
        case "1.2.840.10045.2.1":
            var curve = ""
            if algKids.count > 1 {
                curve = nameDEROID(
                    b, algKids[1].cs,
                    algKids[1].ce)
            }
            switch curve {
            case "1.2.840.10045.3.1.7":
                return L("EC P-256")
            case "1.3.132.0.34":
                return L("EC P-384")
            case "1.3.132.0.35":
                return L("EC P-521")
            default:
                return L("EC (an unnamed curve)")
            }
        case "1.3.101.112":
            return "Ed25519"
        case "1.3.101.113":
            return "Ed448"
        case "1.2.840.113549.1.1.10":
            return "RSA-PSS"
        default:
            return String(
                format: L("key algorithm %@"),
                oid)
        }
    }

    struct NameCert {
        var subjectCN: String?
        var issuerCN: String?
        var selfSigned: Bool
        var sigName: String
        var keyDesc: String
        var sans: [String]
        var notAfter: Date?
    }

    /// A certificate read off its DER:
    /// who it names, who signed it,
    /// with what, until when, and the
    /// other names it carries.
    static func nameCertSummary(
        _ der: [UInt8]) -> NameCert? {
        guard let top = nameDERTLV(der, 0)
        else { return nil }
        let topKids = nameDERChildren(
            der, top.cs, top.ce)
        guard topKids.count >= 3 else {
            return nil
        }
        let sigKids = nameDERChildren(
            der, topKids[1].cs,
            topKids[1].ce)
        var sigName = ""
        if let first = sigKids.first {
            let oid = nameDEROID(
                der, first.cs, first.ce)
            let names: [String: String] = [
                "1.2.840.113549.1.1.11":
                    "sha256WithRSAEncryption",
                "1.2.840.113549.1.1.12":
                    "sha384WithRSAEncryption",
                "1.2.840.113549.1.1.13":
                    "sha512WithRSAEncryption",
                "1.2.840.113549.1.1.5":
                    "sha1WithRSAEncryption",
                "1.2.840.113549.1.1.14":
                    "sha224WithRSAEncryption",
                "1.2.840.113549.1.1.10":
                    "RSASSA-PSS",
                "1.2.840.10045.4.3.2":
                    "ecdsa-with-SHA256",
                "1.2.840.10045.4.3.3":
                    "ecdsa-with-SHA384",
                "1.2.840.10045.4.3.4":
                    "ecdsa-with-SHA512",
                "1.3.101.112": "Ed25519",
            ]
            sigName = names[oid] ?? oid
        }
        let kids = nameDERChildren(
            der, topKids[0].cs,
            topKids[0].ce)
        var idx = 0
        if kids.first?.tag == 0xA0 {
            idx = 1
        }
        guard kids.count >= idx + 6 else {
            return nil
        }
        let issuer = kids[idx + 2]
        let validity = kids[idx + 3]
        let subject = kids[idx + 4]
        let spki = kids[idx + 5]
        let vKids = nameDERChildren(
            der, validity.cs, validity.ce)
        var notAfter: Date? = nil
        if vKids.count == 2 {
            notAfter = nameDERTime(
                vKids[1].tag, der,
                vKids[1].cs, vKids[1].ce)
        }
        var sans: [String] = []
        if kids.count > idx + 6 {
            for extra in kids[(idx + 6)...]
            where extra.tag == 0xA3 {
                let wrapped = nameDERChildren(
                    der, extra.cs, extra.ce)
                guard let seq = wrapped.first
                else { continue }
                for ext in nameDERChildren(
                    der, seq.cs, seq.ce) {
                    let parts = nameDERChildren(
                        der, ext.cs, ext.ce)
                    guard parts.count >= 2,
                          nameDEROID(
                            der, parts[0].cs,
                            parts[0].ce)
                            == "2.5.29.17",
                          let value = parts.last
                    else { continue }
                    guard let names = nameDERTLV(
                        der, value.cs) else {
                        continue
                    }
                    for general in nameDERChildren(
                        der, names.cs, names.ce)
                    where general.tag == 0x82 {
                        if let host = String(
                            bytes: Array(
                                der[general.cs..<general.ce]),
                            encoding: .ascii) {
                            sans.append(host)
                        }
                    }
                }
            }
        }
        return NameCert(
            subjectCN: nameDERCN(
                der, subject.cs, subject.ce),
            issuerCN: nameDERCN(
                der, issuer.cs, issuer.ce),
            selfSigned: Array(
                der[issuer.start..<issuer.ce])
                == Array(
                    der[subject.start..<subject.ce]),
            sigName: sigName,
            keyDesc: nameSPKIDesc(der, spki),
            sans: sans,
            notAfter: notAfter)
    }

    /// Does the paper cover the name
    /// knocked on? A SAN list rules
    /// when it stands; the CN is the
    /// old road, read only in its
    /// absence.
    private static func nameCertCovers(
        _ cert: NameCert, _ host: String)
        -> Bool {
        let lowered = host.lowercased()
        func matches(_ pattern: String)
            -> Bool {
            let p = pattern.lowercased()
            if p == lowered { return true }
            if p.hasPrefix("*.") {
                let suffix = String(
                    p.dropFirst(1))
                guard lowered.hasSuffix(
                    suffix) else {
                    return false
                }
                let head = lowered.dropLast(
                    suffix.count)
                return !head.isEmpty
                    && !head.contains(".")
            }
            return false
        }
        if !cert.sans.isEmpty {
            return cert.sans.contains(
                where: matches)
        }
        if let cn = cert.subjectCN {
            return matches(cn)
        }
        return false
    }

    // MARK: the mail greeting, shared

    /// Open a mail door and read its
    /// greeting. The caller owns the
    /// socket.
    private static func nameSMTPOpen(
        host: String, ip: String,
        port: Int)
        -> (fd: Int32, talk: NameTalk,
            greeting: (code: Int,
                       lines: [String]))? {
        guard let fd = nameSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else {
            return nil
        }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 4)
        let talk = NameTalk(fd: fd)
        let greeting = talk.smtpReply()
        guard greeting.code == 220 else {
            close(fd)
            return nil
        }
        return (fd, talk, greeting)
    }

    /// Say EHLO and read the
    /// capability census: each line's
    /// first word is a capability,
    /// the rest of the line its terms.
    private static func nameEHLOCaps(
        _ talk: NameTalk)
        -> (code: Int,
            caps: [(String, String)]) {
        talk.sendLine(
            "EHLO nightjar.probe\r\n")
        let reply = talk.smtpReply()
        var caps: [(String, String)] = []
        for (index, line)
            in reply.lines.enumerated() {
            guard line.count > 4 else {
                continue
            }
            var text = String(
                line.dropFirst(4))
            if index == 0 {
                // The first line greets
                // by name; its capability,
                // if any rides there,
                // stands after the name.
                if let space = text
                    .firstIndex(of: " ") {
                    text = String(text[
                        text.index(
                            after: space)...])
                } else {
                    continue
                }
            }
            let word = text.split(
                separator: " ", maxSplits: 1)
            guard let key = word.first
            else { continue }
            caps.append((
                String(key).uppercased(),
                word.count > 1
                    ? String(word[1]) : ""))
        }
        return (reply.code, caps)
    }

    // MARK: smtpdeep — the mail door's manners, read whole

    /// The greeting and the EHLO
    /// census at the mail doors (25
    /// and 587, or the one door
    /// named): every capability the
    /// door publishes to a stranger.
    /// No mail is offered, no AUTH is
    /// ever answered — the mechanisms
    /// are read off the sign, never
    /// tried.
    static func smtpdeep(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let words = target.split(
                separator: " ").map(String.init)
            guard let first = words.first
            else {
                nameSay(emit, L("smtpdeep: give a host — smtpdeep mail.example.com"), .err)
                return
            }
            let explicit = first.contains(":")
            guard let resolved = nameMailTarget(
                first, 25) else {
                nameSay(emit, String(format: L("smtpdeep: %@ does not resolve."), first), .err)
                return
            }
            let ports = explicit
                ? [resolved.port] : [25, 587]
            var answered = 0
            for port in ports {
                guard let opened = nameSMTPOpen(
                    host: resolved.host,
                    ip: resolved.ip, port: port)
                else { continue }
                answered += 1
                let (fd, talk, greeting) =
                    opened
                defer { close(fd) }
                nameSay(emit, String(format: L("smtpdeep: %@ door %lld — %@"), resolved.host, port, greeting.lines.first ?? ""), .sys)
                let (code, caps) = nameEHLOCaps(
                    talk)
                if code != 250 {
                    nameSay(emit, String(format: L("smtpdeep: EHLO was refused (%lld) — the door greets but will not introduce itself."), code), .out)
                    talk.sendLine("QUIT\r\n")
                    continue
                }
                for (key, rest) in caps {
                    nameSay(emit, rest.isEmpty
                        ? String(format: L("smtpdeep:   %@"), key)
                        : String(format: L("smtpdeep:   %@ %@"), key, rest), .out)
                }
                if let auth = caps.first(
                    where: { $0.0 == "AUTH" }) {
                    nameSay(emit, String(format: L("smtpdeep: AUTH is advertised here (%@) — mechanisms read off the sign only; whether they are demanded before or after the sealed road is smtptls's question, and no word was offered."), auth.1), .out)
                }
                if caps.contains(where: {
                    $0.0 == "STARTTLS"
                }) {
                    nameSay(emit, L("smtpdeep: the sealed road is offered (STARTTLS stands on the sign)."), .ok)
                } else {
                    nameSay(emit, L("smtpdeep: no STARTTLS on the sign — this door's conversation is in the clear unless the sealed road is demanded unlisted."), .err)
                }
                talk.sendLine("QUIT\r\n")
            }
            if answered == 0 {
                nameSay(emit, String(format: L("smtpdeep: no mail door answers at %@."), resolved.host), .err)
            }
        }
    }

    // MARK: smtptls — rise, and read the papers

    /// One mail door (25, or the door
    /// named) taken up the sealed
    /// road: EHLO, the STARTTLS word,
    /// the rise itself on the same
    /// socket, and the certificate
    /// read at the moment it is
    /// shown — graded, never trusted
    /// onward.
    static func smtptls(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let resolved = nameMailTarget(
                target, 25) else {
                nameSay(emit, L("smtptls: give a host — smtptls mail.example.com[:port]"), .err)
                return
            }
            guard let opened = nameSMTPOpen(
                host: resolved.host,
                ip: resolved.ip,
                port: resolved.port) else {
                nameSay(emit, String(format: L("smtptls: no mail door answers at %@ door %lld."), resolved.host, resolved.port), .err)
                return
            }
            let (fd, talk, _) = opened
            defer { close(fd) }
            let (_, caps) = nameEHLOCaps(talk)
            guard caps.contains(where: {
                $0.0 == "STARTTLS"
            }) else {
                nameSay(emit, String(format: L("smtptls: %@ offers no STARTTLS — the road stays bare, and every word this door hears crosses in the clear."), resolved.host), .err)
                return
            }
            talk.sendLine("STARTTLS\r\n")
            let answer = talk.smtpReply()
            guard answer.code == 220 else {
                nameSay(emit, String(format: L("smtptls: STARTTLS is on the sign but the word was refused (%lld). A promise the door will not keep."), answer.code), .err)
                return
            }
            guard let trust = nameTLSUpgrade(
                fd: fd, host: resolved.host)
            else {
                nameSay(emit, L("smtptls: the door agreed to rise and the rise itself failed — the sealed road is promised but not passable from here."), .err)
                return
            }
            guard SecTrustGetCertificateCount(
                trust) > 0,
                  let leaf = SecTrustGetCertificateAtIndex(
                    trust, 0) else {
                nameSay(emit, L("smtptls: the rise completed but no papers were shown."), .err)
                return
            }
            let der = SecCertificateCopyData(
                leaf) as Data
            guard let cert = nameCertSummary(
                Array(der)) else {
                nameSay(emit, L("smtptls: the papers were shown but would not read."), .err)
                return
            }
            nameSay(emit, String(format: L("smtptls: the road rose at %@ — the papers, read at the handshake:"), resolved.host), .sys)
            nameSay(emit, String(format: L("smtptls: names %@%@"), cert.subjectCN ?? L("(no common name)"), cert.sans.isEmpty ? "" : " + " + cert.sans.joined(separator: ", ")), .out)
            nameSay(emit, String(format: L("smtptls: signed by %@ with %@; the key is %@."), cert.issuerCN ?? L("(an unnamed issuer)"), cert.sigName, cert.keyDesc), .out)
            var faults: [String] = []
            if let expiry = cert.notAfter {
                let days = Int(expiry
                    .timeIntervalSinceNow
                    / 86400)
                nameSay(emit, String(format: L("smtptls: the papers run to %@ (%lld days)."), nameDay(expiry), days), .out)
                if days < 0 {
                    faults.append(L("the certificate has EXPIRED — the seal is a photograph of a seal"))
                } else if days < 30 {
                    faults.append(L("the certificate dies within a month — the renewal had better be a machine, not a memory"))
                }
            }
            if cert.selfSigned {
                faults.append(L("the certificate signs ITSELF — any stranger can mint its twin, and no third party vouches for the name"))
            }
            if !nameCertCovers(
                cert, resolved.host) {
                faults.append(L("the papers do not name this door — they were written for another name, and a careful client refuses them"))
            }
            if cert.sigName.contains("sha1")
                || cert.sigName.contains(
                    "Sha1")
                || cert.sigName.contains(
                    "SHA1") {
                faults.append(L("the signature is SHA-1 — a hash the world has retired for papers like these"))
            }
            if cert.keyDesc.hasPrefix("RSA ") {
                let bits = Int(cert.keyDesc
                    .dropFirst(4)) ?? 0
                if bits > 0, bits < 2048 {
                    faults.append(L("the RSA key is short of 2048 bits — a lock a patient stranger can pick"))
                }
            }
            if faults.isEmpty {
                nameSay(emit, L("smtptls: verdict — the road seals, and the papers are in order: named for this door, vouched for, and alive."), .ok)
            } else {
                for fault in faults {
                    nameSay(emit, String(format: L("smtptls: %@."), fault), .err)
                }
                nameSay(emit, L("smtptls: verdict — the road seals, but the papers argue. A client that reads carefully will refuse this door even though it rises."), .err)
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: dnssecgrade — the chain, as far as it shows

    /// Three readings: the keys at
    /// the apex (asked with the
    /// DNSSEC-OK bit, so the
    /// signatures ride along), the
    /// parent's DS beside them, and a
    /// signed A answer with the
    /// resolver's own AD word. The
    /// grade is the chain exactly as
    /// far as the wire shows it — no
    /// local validation is claimed,
    /// because none is performed.
    static func dnssecgrade(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("dnssecgrade: give a domain — dnssecgrade example.com"), .err)
                return
            }
            let home = nameHome()
            guard let zone = nameZone(
                server: home.ip, name: domain)
            else {
                nameSay(emit, String(format: L("dnssecgrade: no zone answers for %@."), domain), .err)
                return
            }
            let keyReply = nameQuery(
                server: home.ip, name: zone,
                type: 48, dnssecOK: true)
            let dsPeek = nameQuery(
                server: home.ip, name: zone,
                type: 43, dnssecOK: true)
            if keyReply == nil, dsPeek == nil {
                nameSay(emit, L("dnssecgrade: the resolver stayed silent — a silence is not a grade."), .err)
                return
            }
            let keys = keyReply?.answers
                .filter { $0.type == 48 } ?? []
            let keySigs = keyReply?.answers
                .filter { $0.type == 46 } ?? []
            var algs = Set<Int>()
            var ksk = 0
            var zsk = 0
            if let reply = keyReply {
                for key in keys {
                    nameSay(emit, String(format: L("%@. %lld IN DNSKEY %@"), key.name, Int(key.ttl), nameRender(reply.msg, key)), .out)
                    guard key.raw.count >= 4
                    else { continue }
                    let flags = Int(key.raw[0])
                        << 8 | Int(key.raw[1])
                    algs.insert(Int(key.raw[3]))
                    if flags == 257 {
                        ksk += 1
                    } else {
                        zsk += 1
                    }
                }
            }
            let dsReply = dsPeek
            let dsRecords = dsReply?.answers
                .filter { $0.type == 43 } ?? []
            if let reply = dsReply {
                for ds in dsRecords {
                    nameSay(emit, String(format: L("%@. %lld IN DS %@"), ds.name, Int(ds.ttl), nameRender(reply.msg, ds)), .out)
                }
            }
            let aReply = nameQuery(
                server: home.ip, name: zone,
                type: 1, dnssecOK: true)
            let aSigned = aReply?.answers
                .contains(where: {
                    $0.type == 46
                }) ?? false
            let ad = aReply?.authenticated
                ?? false
            let algWords = algs.sorted().map {
                nameAlgName($0)
            }
            if keys.isEmpty, dsRecords.isEmpty {
                nameSay(emit, String(format: L("dnssecgrade: verdict — %@ is UNSIGNED. No keys, no parent record: the answers can be forged by anyone standing in the road, and nothing would show it."), zone), .err)
                return
            }
            if keys.isEmpty {
                nameSay(emit, String(format: L("dnssecgrade: verdict — the parent vouches (DS stands) but the zone shows no keys. A broken chain: validators must treat %@ as bogus, not merely unsigned."), zone), .err)
                return
            }
            if dsRecords.isEmpty {
                nameSay(emit, String(format: L("dnssecgrade: verdict — %@ signs (%lld key(s): %lld KSK, %lld ZSK; %@) but the parent holds no DS. An island of trust: honest answers, unanchored — resolvers will not validate what the parent never vouched for."), zone, keys.count, ksk, zsk, algWords.joined(separator: ", ")), .err)
                return
            }
            var troubles: [String] = []
            if keySigs.isEmpty {
                troubles.append(L("the keys themselves ride unsigned — no RRSIG over the DNSKEY set"))
            }
            if !aSigned {
                troubles.append(L("the A answer carries no signature"))
            }
            if algs.contains(where: {
                $0 == 1 || $0 == 3
                    || $0 == 5 || $0 == 7
            }) {
                troubles.append(L("a legacy algorithm stands among the keys — its signatures are worth little"))
            }
            let weakDS = dsRecords.contains(
                where: {
                    $0.raw.count >= 4
                        && $0.raw[3] == 1
                })
            if weakDS {
                troubles.append(L("a DS digest is SHA-1 — the parent's vouch is written in the old, crackable ink"))
            }
            if troubles.isEmpty {
                nameSay(emit, String(format: L("dnssecgrade: verdict — the chain stands as far as the wire shows it: DS at the parent, %lld key(s) at the apex (%@), signatures over keys and answers%@. The cryptography itself is the resolver's to verify — and the AD flag is its word, reported, not re-proven."), keys.count, algWords.joined(separator: ", "), ad ? L(", and the resolver's AD flag set") : ""), .ok)
            } else {
                for trouble in troubles {
                    nameSay(emit, String(format: L("dnssecgrade: %@."), trouble), .err)
                }
                nameSay(emit, L("dnssecgrade: verdict — the chain is forged in the right shape and limps in the links above. A validating resolver will fail what is broken, not merely distrust it."), .err)
            }
        }
    }

    // MARK: mxprobe — where the mail goes

    /// The MX census: the exchangers
    /// in their order, the null MX
    /// that says "no mail, ever", and
    /// — one question per exchanger —
    /// whether each door also stands
    /// on the IPv6 road.
    static func mxprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("mxprobe: give a domain — mxprobe example.com"), .err)
                return
            }
            let home = nameHome()
            guard let reply = nameQuery(
                server: home.ip, name: domain,
                type: 15) else {
                nameSay(emit, L("mxprobe: the resolver stayed silent."), .err)
                return
            }
            let records = reply.answers
                .filter { $0.type == 15 }
            if records.isEmpty {
                if reply.rcode == 3 {
                    nameSay(emit, String(format: L("mxprobe: %@ does not exist — no mail road leads to a name that is not there."), domain), .err)
                    return
                }
                // The implicit road:
                // with no MX, senders fall
                // back to the name itself.
                let a = nameQuery(
                    server: home.ip,
                    name: domain, type: 1)
                let hasA = a?.answers
                    .contains(where: {
                        $0.type == 1
                    }) ?? false
                if hasA {
                    nameSay(emit, String(format: L("mxprobe: no MX stands for %@. By the old rule (RFC 5321) senders fall back to the name's own A — mail rides to %@ itself, an arrangement few houses mean on purpose."), domain, domain), .err)
                } else {
                    nameSay(emit, String(format: L("mxprobe: no MX, and no A to fall back to — %@ takes no mail the public road can find."), domain), .out)
                }
                return
            }
            var exchangers: [(Int, String)] = []
            for record in records {
                let text = nameRender(
                    reply.msg, record)
                let parts = text.split(
                    separator: " ",
                    maxSplits: 1)
                let pref = parts.first
                    .flatMap { Int($0) } ?? 0
                let host = parts.count > 1
                    ? String(parts[1]) : ""
                exchangers.append(
                    (pref, host))
            }
            if exchangers.count == 1,
               exchangers[0].0 == 0,
               exchangers[0].1 == "."
                || exchangers[0].1 == "" {
                nameSay(emit, String(format: L("mxprobe: %@ posts a NULL MX — 'this house takes no mail, and means it' (RFC 7505). Senders are told plainly instead of being left to knock."), domain), .ok)
                return
            }
            exchangers.sort { $0.0 < $1.0 }
            var v6Ready = 0
            for (pref, host) in exchangers {
                var roads: [String] = []
                if let a = nameQuery(
                    server: home.ip,
                    name: host, type: 1),
                   a.answers.contains(
                        where: { $0.type == 1 }) {
                    roads.append("IPv4")
                }
                if let aaaa = nameQuery(
                    server: home.ip,
                    name: host, type: 28),
                   aaaa.answers.contains(
                        where: { $0.type == 28 }) {
                    roads.append("IPv6")
                    v6Ready += 1
                }
                nameSay(emit, String(format: L("mxprobe: %lld %@ — %@."), pref, host, roads.isEmpty ? L("no address answers for it: a dead exchanger, kept on the sign") : roads.joined(separator: " + ")), roads.isEmpty ? .err : .out)
            }
            if exchangers.count == 1 {
                nameSay(emit, String(format: L("mxprobe: verdict — one exchanger carries all of %@'s mail. When it sleeps, the world's letters queue or bounce; there is no second door."), domain), .err)
            } else {
                nameSay(emit, String(format: L("mxprobe: verdict — %lld exchangers stand for %@, %lld of them on both roads."), exchangers.count, domain, v6Ready), .ok)
            }
        }
    }

    // MARK: spfprobe — who may sign a letter with this name

    /// The SPF record read as its
    /// evaluators read it: the
    /// mechanism walk, the DNS-lookup
    /// budget of RFC 7208 (ten, no
    /// more — includes followed, each
    /// one a question), and the
    /// terminal word that decides
    /// what a forgery is worth.
    static func spfprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("spfprobe: give a domain — spfprobe example.com"), .err)
                return
            }
            let home = nameHome()
            var count = 0
            var problems: [String] = []
            var terminal: String? = nil
            var sawPTR = false
            var seen = Set<String>()

            func record(of name: String)
                -> String? {
                guard let reply = nameQuery(
                    server: home.ip,
                    name: name, type: 16)
                else { return nil }
                let found = reply.answers
                    .filter { $0.type == 16 }
                    .map { nameTXTString($0) }
                    .filter {
                        let low = $0
                            .lowercased()
                        return low == "v=spf1"
                            || low.hasPrefix(
                                "v=spf1 ")
                    }
                if found.count > 1 {
                    problems.append(
                        String(format: L("%@ posts %lld SPF records — evaluators must refuse them all (PermError)"), name, found.count))
                }
                return found.first
            }

            func mechName(_ token: String)
                -> (name: String,
                    target: String?) {
                var body = token
                if let first = body.first,
                   "+-~?".contains(first) {
                    body = String(
                        body.dropFirst())
                }
                var cut = body.endIndex
                for mark in [":", "/", "="]
                where body.contains(mark) {
                    if let at = body
                        .firstIndex(of:
                            Character(mark)) {
                        cut = min(cut, at)
                    }
                }
                let name = String(
                    body[..<cut]).lowercased()
                var target: String? = nil
                if cut < body.endIndex {
                    let rest = body[body.index(
                        after: cut)...]
                    target = rest.split(
                        separator: "/")
                        .first.map(String.init)
                }
                return (name, target)
            }

            func walk(_ name: String,
                      _ depth: Int) {
                guard depth <= 5,
                      seen.insert(
                        name.lowercased())
                        .inserted else {
                    return
                }
                guard let text = record(
                    of: name) else {
                    if depth == 0 {
                        problems.append(
                            L("no SPF record stands here"))
                    }
                    return
                }
                if depth == 0 {
                    nameSay(emit, String(format: L("spfprobe: %@"), text), .sys)
                }
                let tokens = text.split(
                    separator: " ")
                    .map(String.init)
                for token in tokens.dropFirst() {
                    let (mech, tgt) = mechName(
                        token)
                    switch mech {
                    case "all":
                        if depth == 0 {
                            terminal = token
                        }
                    case "include":
                        count += 1
                        if let tgt = tgt {
                            walk(tgt, depth + 1)
                        }
                    case "redirect":
                        count += 1
                        if let tgt = tgt {
                            walk(tgt, depth + 1)
                        }
                    case "a", "mx", "ptr",
                         "exists":
                        count += 1
                        if mech == "ptr" {
                            sawPTR = true
                        }
                    default:
                        break
                    }
                    if count > 12 { return }
                }
            }

            walk(domain, 0)
            if problems.contains(
                L("no SPF record stands here")) {
                nameSay(emit, String(format: L("spfprobe: verdict — %@ posts no SPF. Any server on earth may sign letters with this name, and receivers have no published word to judge them by."), domain), .err)
                return
            }
            for problem in problems {
                nameSay(emit, String(format: L("spfprobe: %@."), problem), .err)
            }
            nameSay(emit, String(format: L("spfprobe: the walk spends %lld of the 10 DNS lookups RFC 7208 allows (include, a, mx, ptr, exists and redirect terms counted, includes followed)."), count), .out)
            if sawPTR {
                nameSay(emit, L("spfprobe: a ptr mechanism stands in the walk — the RFC tells evaluators not to trust it and houses not to publish it."), .err)
            }
            guard let terminal = terminal
            else {
                nameSay(emit, L("spfprobe: no terminal 'all' — a letter that matches nothing falls to a neutral shrug by default (RFC 7208's implicit ?all)."), .out)
                return
            }
            switch terminal {
            case "-all":
                nameSay(emit, L("spfprobe: verdict — the walk ends at -all: what did not match is FORGED, in the house's own word. Hardfail — the strongest sentence SPF can say."), problems.isEmpty && count <= 10 ? .ok : .err)
            case "~all":
                nameSay(emit, L("spfprobe: verdict — the walk ends at ~all (softfail): what did not match is 'probably not authorized' — a hedge most receivers treat as a shrug."), .out)
            case "?all":
                nameSay(emit, L("spfprobe: verdict — the walk ends at ?all: the house publishes a map and declines to judge. Neutral — SPF as decoration."), .err)
            case "+all":
                nameSay(emit, L("spfprobe: verdict — the walk ends at +all: ANY server may sign with this name. The record exists and protects nothing. Critical."), .err)
            default:
                nameSay(emit, String(format: L("spfprobe: verdict — the walk ends at %@."), terminal), .out)
            }
            if count > 10 {
                nameSay(emit, L("spfprobe: and the budget is blown — past ten lookups an evaluator must stop and call the whole record PermError, so the house's own policy refuses itself."), .err)
            }
        }
    }

    // MARK: dkimprobe — the keys under the common selectors

    /// Twelve selectors the world
    /// actually uses, read at
    /// <selector>._domainkey.<domain>
    /// — published keys, read the way
    /// every receiver reads them.
    /// Which answer, how heavy their
    /// keys are, and which stand
    /// revoked. A silent selector
    /// proves nothing but silence:
    /// houses pick their own names.
    static func dkimprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("dkimprobe: give a domain — dkimprobe example.com"), .err)
                return
            }
            let home = nameHome()
            let selectors = [
                "google", "default", "s1",
                "s2", "k1", "mail", "dkim",
                "selector1", "selector2",
                "smtp", "mx", "sig1",
            ]
            var answered = 0
            var revoked = 0
            for selector in selectors {
                let name = selector
                    + "._domainkey." + domain
                guard let reply = nameQuery(
                    server: home.ip,
                    name: name, type: 16)
                else { continue }
                let texts = reply.answers
                    .filter { $0.type == 16 }
                    .map { nameTXTString($0) }
                guard let record = texts
                    .first(where: {
                        $0.lowercased()
                            .contains("p=")
                    }) else {
                    continue
                }
                answered += 1
                var tags: [String: String] = [:]
                for piece in record.split(
                    separator: ";") {
                    let pair = piece.split(
                        separator: "=",
                        maxSplits: 1)
                    guard pair.count == 2
                    else { continue }
                    tags[String(pair[0])
                        .trimmingCharacters(
                            in: .whitespaces)
                        .lowercased()] =
                        String(pair[1])
                        .trimmingCharacters(
                            in: .whitespaces)
                }
                let kind = tags["k"] ?? "rsa"
                let p = tags["p"] ?? ""
                if p.isEmpty {
                    revoked += 1
                    nameSay(emit, String(format: L("dkimprobe: %@ — REVOKED. The key was withdrawn in public (an empty p=), the correct way to retire one."), selector), .ok)
                    continue
                }
                var desc = kind
                if kind == "ed25519" {
                    desc = "Ed25519"
                } else if let data = Data(
                    base64Encoded: p,
                    options:
                        .ignoreUnknownCharacters),
                          !data.isEmpty {
                    desc = nameDKIMKeyDesc(
                        Array(data), kind: kind)
                }
                let testing = tags["t"]?
                    .contains("y") ?? false
                nameSay(emit, String(format: L("dkimprobe: %@ — a %@ key stands%@."), selector, desc, testing ? L(", still flying the testing flag (t=y): receivers are told not to hold it against the house") : ""), .out)
            }
            if answered == 0 {
                nameSay(emit, String(format: L("dkimprobe: verdict — none of the twelve common selectors answers for %@. The house may sign under a name of its own choosing, or not sign at all; silence under these twelve doors proves neither."), domain), .out)
            } else {
                nameSay(emit, String(format: L("dkimprobe: verdict — %lld selector(s) answer for %@, %lld of them revoked. The signing keys are where the world expects keys to be."), answered, domain, revoked), .ok)
            }
        }
    }

    /// A DKIM key's weight: the p=
    /// body is the key itself — an
    /// RSAPublicKey under DER for
    /// k=rsa (some houses wrap it in
    /// a full SPKI; both shapes are
    /// read), a bare 32 bytes for
    /// Ed25519.
    private static func nameDKIMKeyDesc(
        _ der: [UInt8], kind: String)
        -> String {
        if kind == "ed25519" {
            return "Ed25519"
        }
        guard let top = nameDERTLV(der, 0),
              top.tag == 0x30 else {
            return kind
        }
        let kids = nameDERChildren(
            der, top.cs, top.ce)
        if let first = kids.first,
           first.tag == 0x30,
           kids.count == 2 {
            return nameSPKIDesc(der, (
                tag: top.tag, cs: top.cs,
                ce: top.ce, start: 0))
        }
        if let modulus = kids.first,
           modulus.tag == 0x02 {
            let bits = nameDERModulusBits(
                der, modulus.cs, modulus.ce)
            return String(
                format: L("RSA %lld"), bits)
        }
        return kind
    }

    // MARK: dmarcprobe — what a forgery costs

    /// The _dmarc record: the policy
    /// a forgery meets (none,
    /// quarantine, reject), the share
    /// of mail it is enforced on,
    /// where the reports go, and how
    /// strictly the From name must
    /// align.
    static func dmarcprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("dmarcprobe: give a domain — dmarcprobe example.com"), .err)
                return
            }
            let home = nameHome()
            let reply = nameQuery(
                server: home.ip,
                name: "_dmarc." + domain,
                type: 16)
            let record = reply?.answers
                .filter { $0.type == 16 }
                .map { nameTXTString($0) }
                .first(where: {
                    $0.lowercased()
                        .hasPrefix("v=dmarc1")
                })
            guard let record = record else {
                nameSay(emit, String(format: L("dmarcprobe: no DMARC stands at _dmarc.%@. Forgeries of this name meet no published policy at all — every receiver improvises. (A record at the organizational domain, if one stands, still rules subdomains; this probe reads the name it was given.)"), domain), .err)
                return
            }
            nameSay(emit, String(format: L("dmarcprobe: %@"), record), .sys)
            var tags: [String: String] = [:]
            for piece in record.split(
                separator: ";") {
                let pair = piece.split(
                    separator: "=",
                    maxSplits: 1)
                guard pair.count == 2
                else { continue }
                tags[String(pair[0])
                    .trimmingCharacters(
                        in: .whitespaces)
                    .lowercased()] =
                    String(pair[1])
                    .trimmingCharacters(
                        in: .whitespaces)
            }
            let policy = tags["p"] ?? "none"
            let pct = tags["pct"]
                .flatMap(Int.init) ?? 100
            if let rua = tags["rua"] {
                let doors = rua.split(
                    separator: ",").count
                nameSay(emit, String(format: L("dmarcprobe: aggregate reports flow to %lld address(es): %@."), doors, rua), .out)
            } else {
                nameSay(emit, L("dmarcprobe: no rua — nobody receives the aggregate reports. The house flies without instruments."), .err)
            }
            if tags["ruf"] != nil {
                nameSay(emit, L("dmarcprobe: forensic reports are asked for too (ruf) — a rarer, heavier watch."), .out)
            }
            let strict = tags["adkim"] == "s"
                || tags["aspf"] == "s"
            switch policy {
            case "reject":
                if pct >= 100 {
                    nameSay(emit, String(format: L("dmarcprobe: verdict — p=reject at %lld%%. A forgery of %@ is refused at the door, in the house's own standing order%@."), pct, domain, strict ? L(", with strict alignment demanded") : ""), .ok)
                } else {
                    nameSay(emit, String(format: L("dmarcprobe: verdict — p=reject, but only %lld%% of mail meets it. The rest is sampled through — a policy still being rolled out, or one that lost its nerve."), pct), .err)
                }
            case "quarantine":
                nameSay(emit, String(format: L("dmarcprobe: verdict — p=quarantine at %lld%%. Forgeries are filed to the spam folder — doubted, not refused."), pct), .out)
            default:
                nameSay(emit, L("dmarcprobe: verdict — p=none. The house watches its name being forged and files reports, but orders nothing done. Monitoring is a beginning, not a posture."), .err)
            }
        }
    }

    // MARK: mtasts — the mail road's seal, published

    /// MTA-STS, both halves: the DNS
    /// record that says a policy
    /// stands, and the policy itself,
    /// fetched from the house's own
    /// .well-known door. Mode, the MX
    /// patterns the seal covers, and
    /// how long the word holds.
    static func mtasts(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("mtasts: give a domain — mtasts example.com"), .err)
                return
            }
            let home = nameHome()
            let dnsReply = nameQuery(
                server: home.ip,
                name: "_mta-sts." + domain,
                type: 16)
            let dnsRecord = dnsReply?.answers
                .filter { $0.type == 16 }
                .map { nameTXTString($0) }
                .first(where: {
                    $0.lowercased()
                        .hasPrefix("v=stsv1")
                })
            if let dnsRecord = dnsRecord {
                nameSay(emit, String(format: L("mtasts: the DNS half stands — %@."), dnsRecord), .out)
            }
            var policy: [String: [String]] = [:]
            var fetched = false
            if let url = URL(string:
                "https://mta-sts." + domain
                + "/.well-known/mta-sts.txt"),
               let (data, http) = nameFetch(url),
               http.statusCode == 200,
               let text = String(
                    data: data,
                    encoding: .utf8) {
                fetched = true
                for line in text.split(
                    separator: "\n") {
                    let pair = line.split(
                        separator: ":",
                        maxSplits: 1)
                    guard pair.count == 2
                    else { continue }
                    let key = String(pair[0])
                        .trimmingCharacters(
                            in: .whitespaces)
                        .lowercased()
                    let value = String(pair[1])
                        .trimmingCharacters(
                            in: .whitespaces)
                    policy[key, default: []]
                        .append(value)
                }
            }
            if fetched {
                let mode = policy["mode"]?
                    .first ?? "?"
                let maxAge = policy["max_age"]?
                    .first.flatMap(Int.init) ?? 0
                let mx = policy["mx"] ?? []
                nameSay(emit, String(format: L("mtasts: the policy reads mode %@, max_age %lld s, covering %lld MX pattern(s): %@."), mode, maxAge, mx.count, mx.joined(separator: ", ")), .out)
                if dnsRecord == nil {
                    nameSay(emit, L("mtasts: verdict — a policy hangs with no DNS record pointing at it. Senders never learn it stands: the two halves must both be posted, and only one is."), .err)
                } else if mode == "enforce",
                          maxAge >= 604800 {
                    nameSay(emit, L("mtasts: verdict — enforce, held for a week or more. A sender that cannot seal the road MUST NOT deliver: downgrade attacks on this house's mail are answered in advance."), .ok)
                } else if mode == "enforce" {
                    nameSay(emit, String(format: L("mtasts: verdict — enforce, but max_age is only %lld s. The seal is real and short-lived: an attacker need only outwait a brief cache."), maxAge), .err)
                } else if mode == "testing" {
                    nameSay(emit, L("mtasts: verdict — testing. The house watches the sealed road and files the reports, but a failed seal still delivers. A rehearsal, honestly labeled."), .out)
                } else {
                    nameSay(emit, String(format: L("mtasts: verdict — mode %@. The policy stands but does not seal: senders may fall back to the bare road."), mode), .err)
                }
            } else if dnsRecord != nil {
                nameSay(emit, L("mtasts: verdict — the DNS record promises a policy the .well-known door does not serve. A broken pair: senders are told to look, and find nothing."), .err)
            } else {
                nameSay(emit, String(format: L("mtasts: verdict — %@ posts no MTA-STS. Its mail may still ride TLS by habit (opportunistic), but nothing published forbids the downgrade: a hand in the road can strip the seal and the letters still deliver."), domain), .out)
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: tlsrpt — where the failures are reported

    /// The TLS-RPT record at
    /// _smtp._tls.<domain>: whether
    /// broken seals anywhere on the
    /// road are reported at all, and
    /// to whom.
    static func tlsrpt(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("tlsrpt: give a domain — tlsrpt example.com"), .err)
                return
            }
            let home = nameHome()
            let reply = nameQuery(
                server: home.ip,
                name: "_smtp._tls." + domain,
                type: 16)
            let record = reply?.answers
                .filter { $0.type == 16 }
                .map { nameTXTString($0) }
                .first(where: {
                    $0.lowercased()
                        .hasPrefix("v=tlsrptv1")
                })
            guard let record = record else {
                nameSay(emit, String(format: L("tlsrpt: %@ posts no TLS-RPT. When a sender's sealed road fails — a bad certificate, a stripped handshake — nobody anywhere is told. Failures on this house's mail road are invisible by default."), domain), .err)
                return
            }
            nameSay(emit, String(format: L("tlsrpt: %@"), record), .sys)
            var rua: String? = nil
            for piece in record.split(
                separator: ";") {
                let pair = piece.split(
                    separator: "=",
                    maxSplits: 1)
                guard pair.count == 2 else {
                    continue
                }
                if String(pair[0])
                    .trimmingCharacters(
                        in: .whitespaces)
                    .lowercased() == "rua" {
                    rua = String(pair[1])
                        .trimmingCharacters(
                            in: .whitespaces)
                }
            }
            if let rua = rua {
                let doors = rua.split(
                    separator: ",")
                nameSay(emit, String(format: L("tlsrpt: verdict — failures are reported to %lld door(s): %@. The house hears about its broken seals from the senders who met them."), doors.count, rua), .ok)
            } else {
                nameSay(emit, L("tlsrpt: verdict — the record stands with no rua. A sign that names no listener: reports have nowhere to go."), .err)
            }
        }
    }

    // MARK: bimi — the face beside the letter

    /// The BIMI record at
    /// default._bimi.<domain>: the
    /// brand mark a supporting inbox
    /// paints beside the house's
    /// letters, and the verified
    /// certificate (a=) that the
    /// stricter inboxes demand before
    /// they paint anything.
    static func bimi(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("bimi: give a domain — bimi example.com"), .err)
                return
            }
            let home = nameHome()
            let reply = nameQuery(
                server: home.ip,
                name: "default._bimi."
                    + domain,
                type: 16)
            let record = reply?.answers
                .filter { $0.type == 16 }
                .map { nameTXTString($0) }
                .first(where: {
                    $0.lowercased()
                        .hasPrefix("v=bimi1")
                })
            guard let record = record else {
                nameSay(emit, String(format: L("bimi: %@ posts no BIMI. Its letters arrive faceless in every inbox — no mark, verified or otherwise. (The mark only paints where DMARC already stands enforced; bimi without dmarcprobe's verdict behind it is a portrait in a locked room.)"), domain), .out)
                return
            }
            nameSay(emit, String(format: L("bimi: %@"), record), .sys)
            var logo: String? = nil
            var vmc: String? = nil
            for piece in record.split(
                separator: ";") {
                let pair = piece.split(
                    separator: "=",
                    maxSplits: 1)
                guard pair.count == 2
                else { continue }
                let key = String(pair[0])
                    .trimmingCharacters(
                        in: .whitespaces)
                    .lowercased()
                let value = String(pair[1])
                    .trimmingCharacters(
                        in: .whitespaces)
                if key == "l" { logo = value }
                if key == "a" { vmc = value }
            }
            if let logo = logo,
               !logo.isEmpty {
                nameSay(emit, String(format: L("bimi: the mark hangs at %@."), logo), .out)
            } else {
                nameSay(emit, L("bimi: the record names no logo (an empty l=) — a deliberate blank where the mark would hang."), .out)
            }
            if let vmc = vmc, !vmc.isEmpty {
                nameSay(emit, String(format: L("bimi: verdict — the mark is VERIFIED: a certificate stands at %@. The strict inboxes (Gmail among them) will paint it; the house has proven the face is its own."), vmc), .ok)
            } else {
                nameSay(emit, L("bimi: verdict — a mark without a verified certificate. Lenient inboxes may paint it; the strict ones will not, and a painted-but-unproven face is exactly what BIMI exists to prevent."), .err)
            }
        }
    }

    // MARK: the CT roads, shared

    /// The public certificate logs,
    /// read through crt.sh: every
    /// certificate the logs remember
    /// for the name, as one JSON
    /// census.
    private static func nameCRT(
        _ domain: String)
        -> [[String: Any]]? {
        var comps = URLComponents(
            string: "https://crt.sh/")
        comps?.queryItems = [
            URLQueryItem(name: "q",
                         value: "%." + domain),
            URLQueryItem(
                name: "output",
                value: "json"),
        ]
        guard let url = comps?.url,
              let (data, http) = nameFetch(
                url, follow: false),
              http.statusCode == 200,
              let list = nameJSON(data)
                as? [[String: Any]] else {
            return nil
        }
        return list
    }

    // MARK: certtrans — the logs remember every paper

    /// Certificate Transparency, read
    /// as a census: how many papers
    /// the public logs hold for the
    /// name, who issued them, what
    /// names they cover, and when the
    /// mint last worked. A house that
    /// has ever taken a public
    /// certificate is written here —
    /// including the names it never
    /// meant to advertise.
    static func certtrans(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("certtrans: give a domain — certtrans example.com"), .err)
                return
            }
            guard let list = nameCRT(domain)
            else {
                nameSay(emit, L("certtrans: the public log (crt.sh) did not answer — that is the log's silence, not the name's innocence."), .err)
                return
            }
            if list.isEmpty {
                nameSay(emit, String(format: L("certtrans: the logs hold nothing for %@. Either the house has never taken a public certificate, or its papers are minted where the logs do not look."), domain), .out)
                return
            }
            var seen = Set<String>()
            var issuers: [String: Int] = [:]
            var names = Set<String>()
            var wildcards = 0
            var newest: (String, String)?
            for entry in list {
                let id = nameField(
                    entry, "id") ?? ""
                if !id.isEmpty,
                   !seen.insert(id)
                    .inserted {
                    continue
                }
                var issuer = nameField(
                    entry, "issuer_name")
                    ?? "?"
                if let cn = issuer.range(
                    of: "CN=") {
                    let tail = issuer[
                        cn.upperBound...]
                    issuer = String(tail
                        .split(separator: ",")
                        .first ?? "")
                }
                issuers[issuer, default: 0] += 1
                if let value = nameField(
                    entry, "name_value") {
                    for line in value.split(
                        separator: "\n") {
                        names.insert(
                            String(line)
                                .lowercased())
                    }
                }
                if let common = nameField(
                    entry, "common_name") {
                    names.insert(
                        common.lowercased())
                }
                if let from = nameField(
                    entry, "not_before") {
                    if newest == nil
                        || from > newest!.1 {
                        newest = (
                            nameField(
                                entry,
                                "common_name")
                                ?? domain,
                            from)
                    }
                }
            }
            wildcards = names.filter {
                $0.hasPrefix("*.")
            }.count
            nameSay(emit, String(format: L("certtrans: the logs hold %lld certificate(s) for %@, covering %lld distinct name(s), %lld of them wildcards."), seen.count, domain, names.count, wildcards), .sys)
            let top = issuers.sorted {
                $0.value > $1.value
            }.prefix(3)
            for (issuer, tally) in top {
                nameSay(emit, String(format: L("certtrans: %@ — %lld paper(s)."), issuer, tally), .out)
            }
            if let newest = newest {
                nameSay(emit, String(format: L("certtrans: the mint last worked %@ — a paper for %@."), String(newest.1.prefix(10)), newest.0), .out)
            }
            nameSay(emit, L("certtrans: verdict — every name above was published by the act of certifying it. The logs are the house's involuntary guest book: subdomains minted once, for one test, are remembered forever."), .out)
        }
    }

    // MARK: subdomains — the names the logs confess

    /// Subdomain enumeration from the
    /// public certificate logs alone —
    /// the names a house confessed by
    /// certifying them. No dictionary,
    /// no brute force, no knock on any
    /// door but the log's: what the
    /// logs never saw is not claimed.
    static func subdomainsCT(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("subdomains: give a domain — subdomains example.com"), .err)
                return
            }
            guard let list = nameCRT(domain)
            else {
                nameSay(emit, L("subdomains: the public log (crt.sh) did not answer."), .err)
                return
            }
            var hosts = Set<String>()
            var wildcardCount = 0
            for entry in list {
                var raw: [String] = []
                if let value = nameField(
                    entry, "name_value") {
                    raw.append(contentsOf:
                        value.split(
                            separator: "\n")
                            .map(String.init))
                }
                if let common = nameField(
                    entry, "common_name") {
                    raw.append(common)
                }
                for name in raw {
                    let lowered = name
                        .trimmingCharacters(
                            in: .whitespaces)
                        .lowercased()
                    if lowered.hasPrefix(
                        "*.") {
                        wildcardCount += 1
                        continue
                    }
                    if lowered == domain {
                        continue
                    }
                    if lowered.hasSuffix(
                        "." + domain) {
                        hosts.insert(lowered)
                    }
                }
            }
            if hosts.isEmpty {
                nameSay(emit, String(format: L("subdomains: the logs confess no subdomain of %@. The house certifies at its apex, or under wildcards (%lld in the logs), or not at all — silence here is the log's coverage, not proof of an empty house."), domain, wildcardCount), .out)
                return
            }
            let sorted = hosts.sorted()
            for host in sorted.prefix(120) {
                nameSay(emit, host, .out)
            }
            if sorted.count > 120 {
                nameSay(emit, String(format: L("… and %lld more."), sorted.count - 120), .out)
            }
            nameSay(emit, String(format: L("subdomains: %lld name(s) the logs confess for %@ — every one published by the house itself, in a certificate. Names never certified are not here, and are not claimed."), sorted.count, domain), .ok)
        }
    }

    // MARK: whoisdeep — the registry's ledger, parsed

    /// One whois conversation, its
    /// referral followed once the way
    /// the house whois follows it, and
    /// the ledger read for its fields:
    /// whose name the domain is kept
    /// in, who sold it, when it was
    /// born, when it lapses, and what
    /// locks stand on it.
    static func whoisdeep(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let domain = nameDomain(target)
            guard !domain.isEmpty,
                  domain.contains(".") else {
                nameSay(emit, L("whoisdeep: give a domain — whoisdeep example.com"), .err)
                return
            }
            func ask(_ server: String)
                -> String? {
                guard let ip = nameServerIP(
                    server),
                      let fd = nameSocket(
                        ip: ip, port: 43,
                        timeout: 5) else {
                    return nil
                }
                defer { close(fd) }
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 5)
                guard nameSendAll(
                    fd, Array(
                        (domain + "\r\n")
                            .utf8)) else {
                    return nil
                }
                var bytes: [UInt8] = []
                let deadline = Date()
                    .addingTimeInterval(12)
                while bytes.count < 262144,
                      Date() < deadline {
                    var chunk = [UInt8](
                        repeating: 0,
                        count: 8192)
                    let got = recv(
                        fd, &chunk,
                        chunk.count, 0)
                    if got <= 0 { break }
                    bytes.append(contentsOf:
                        chunk[0..<got])
                }
                return String(
                    bytes: bytes,
                    encoding: .utf8)
            }
            var server = BlacksiteNet
                .whoisServer(for: domain)
            guard var body = ask(server)
            else {
                nameSay(emit, String(format: L("whoisdeep: %@ did not answer for %@."), server, domain), .err)
                return
            }
            if let referral = BlacksiteNet
                .referral(in: body),
               referral.lowercased()
                != server.lowercased() {
                nameSay(emit, String(format: L("whoisdeep: referred to %@ — following, once."), referral), .sys)
                server = referral
                if let second = ask(referral) {
                    body = second
                }
            }
            var fields: [(String, String)] = []
            for row in body.split(
                separator: "\n") {
                let line = row
                    .trimmingCharacters(
                        in: .whitespaces)
                if line.hasPrefix("%")
                    || line.hasPrefix("#")
                    || line.isEmpty {
                    continue
                }
                let pair = line.split(
                    separator: ":",
                    maxSplits: 1)
                guard pair.count == 2
                else { continue }
                fields.append((
                    String(pair[0])
                        .trimmingCharacters(
                            in: .whitespaces)
                        .lowercased(),
                    String(pair[1])
                        .trimmingCharacters(
                            in: .whitespaces)))
            }
            func first(_ keys: [String])
                -> String? {
                for (key, value) in fields
                where keys.contains(key) {
                    return value
                }
                return nil
            }
            func all(_ keys: [String])
                -> [String] {
                var out: [String] = []
                for (key, value) in fields
                where keys.contains(key)
                    && !out.contains(value) {
                    out.append(value)
                }
                return out
            }
            nameSay(emit, String(format: L("whoisdeep: the ledger of %@, as %@ keeps it:"), domain, server), .sys)
            if let registrar = first(
                ["registrar",
                 "registrar name",
                 "sponsoring registrar"]) {
                nameSay(emit, String(format: L("whoisdeep: kept by %@."), registrar), .out)
            }
            if let created = first(
                ["creation date", "created",
                 "created on",
                 "registered on",
                 "registration date"]) {
                nameSay(emit, String(format: L("whoisdeep: born %@."), created), .out)
            }
            if let updated = first(
                ["updated date",
                 "last updated",
                 "last update",
                 "modified"]) {
                nameSay(emit, String(format: L("whoisdeep: last touched %@."), updated), .out)
            }
            var expiryText: String? = nil
            if let expiry = first(
                ["registry expiry date",
                 "expiry date",
                 "expiration date",
                 "expires on",
                 "renewal date",
                 "paid-till"]) {
                expiryText = expiry
                nameSay(emit, String(format: L("whoisdeep: lapses %@."), expiry), .out)
            }
            let statuses = all(
                ["domain status", "status"])
            if !statuses.isEmpty {
                nameSay(emit, String(format: L("whoisdeep: standing words: %@."), statuses.joined(separator: ", ")), .out)
            }
            let servers = all(
                ["name server", "nserver",
                 "nameserver"])
            if !servers.isEmpty {
                nameSay(emit, String(format: L("whoisdeep: served by %lld nameserver(s): %@."), servers.count, servers.prefix(6).joined(separator: ", ")), .out)
            }
            if let org = first(
                ["registrant organization",
                 "registrant name",
                 "org", "organisation"]) {
                nameSay(emit, String(format: L("whoisdeep: the name on the deed: %@."), org), .out)
            }
            if let dnssec = first(
                ["dnssec", "signed"]) {
                nameSay(emit, String(format: L("whoisdeep: the registry's DNSSEC word: %@."), dnssec), .out)
            }
            if fields.isEmpty {
                nameSay(emit, L("whoisdeep: the registry answered, but in no shape this reader can parse — a thin registry, or a ledger behind a wall."), .err)
                return
            }
            if let expiryText = expiryText,
               let date = nameWhoisDate(
                    expiryText) {
                let days = Int(date
                    .timeIntervalSinceNow
                    / 86400)
                if days < 0 {
                    nameSay(emit, String(format: L("whoisdeep: verdict — the name LAPSED %lld day(s) ago and still resolves in ledgers. A lapsed name is a door anyone may buy."), -days), .err)
                } else if days < 30 {
                    nameSay(emit, String(format: L("whoisdeep: verdict — %lld day(s) of term remain. The name is a candle near its end; whoever keeps this house should already be renewing."), days), .err)
                } else if days < 90 {
                    nameSay(emit, String(format: L("whoisdeep: verdict — %lld day(s) of term remain. Comfortable, not distant."), days), .out)
                } else {
                    nameSay(emit, String(format: L("whoisdeep: verdict — %lld day(s) of term remain. The deed is in good standing."), days), .ok)
                }
            } else {
                nameSay(emit, L("whoisdeep: verdict — the ledger read, and no expiry stood in a shape that could be dated. The fields above are the registry's own words."), .out)
            }
        }
    }

    /// A registry date, in whichever
    /// of its dialects it was written.
    private static func nameWhoisDate(
        _ text: String) -> Date? {
        let trimmed = text
            .trimmingCharacters(
                in: .whitespaces)
        let iso = ISO8601DateFormatter()
        if let date = iso.date(
            from: trimmed) {
            return date
        }
        let patterns = [
            "yyyy-MM-dd", "dd-MMM-yyyy",
            "yyyy.MM.dd", "yyyy/MM/dd",
            "MMMM d, yyyy",
            "yyyy-MM-dd HH:mm:ss",
            "dd.MM.yyyy",
        ]
        let candidates = [
            trimmed,
            trimmed.split(separator: " ")
                .first.map(String.init)
                ?? trimmed,
        ]
        for pattern in patterns {
            let fmt = DateFormatter()
            fmt.locale = Locale(
                identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(
                secondsFromGMT: 0)
            fmt.dateFormat = pattern
            for candidate in candidates {
                if let date = fmt.date(
                    from: candidate) {
                    return date
                }
            }
        }
        return nil
    }

    // MARK: rdap — the registry's modern ledger

    /// The RDAP reading — whois's
    /// structured heir — for a domain
    /// or an address: the registrar,
    /// the lifecycle's dates, the
    /// standing words, the servers.
    /// One HTTPS knock on the
    /// bootstrap door, which refers
    /// onward to the registry itself.
    static func rdap(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let text = target.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let octets = text.split(
                separator: ".")
            let isIP = octets.count == 4
                && octets.allSatisfy {
                    Int($0) != nil
                }
            let isV6 = text.contains(":")
            let path: String
            let shown: String
            if isIP || isV6 {
                path = "ip/" + text
                shown = text
            } else {
                let domain = nameDomain(text)
                guard !domain.isEmpty,
                      domain.contains(".")
                else {
                    nameSay(emit, L("rdap: give a domain or an address — rdap example.com"), .err)
                    return
                }
                path = "domain/" + domain
                shown = domain
            }
            guard let url = URL(string:
                "https://rdap.org/" + path),
                  let (data, http) = nameFetch(
                    url, follow: true),
                  http.statusCode == 200,
                  let dict = nameJSON(data)
                    as? [String: Any] else {
                nameSay(emit, String(format: L("rdap: no ledger answered for %@ — the registry may keep no RDAP door, or the bootstrap could not refer."), shown), .err)
                return
            }
            if isIP || isV6 {
                let label = dict["name"]
                    as? String ?? "?"
                let start = dict["startAddress"]
                    as? String ?? "?"
                let end = dict["endAddress"]
                    as? String ?? "?"
                let country = dict["country"]
                    as? String ?? "?"
                let kind = dict["type"]
                    as? String ?? "?"
                nameSay(emit, String(format: L("rdap: %@ — the block %@ to %@, kept as %@ (%@)."), label, start, end, kind, country), .sys)
                nameSay(emit, L("rdap: verdict — the allocation reads as the registry keeps it. An address's ledger names its keeper, not its current tenant's business."), .out)
                return
            }
            nameSay(emit, String(format: L("rdap: %@ — the modern ledger:"), shown), .sys)
            if let status = dict["status"]
                as? [String] {
                nameSay(emit, String(format: L("rdap: standing words: %@."), status.joined(separator: ", ")), .out)
                if status.contains(
                    where: {
                        $0.contains("hold")
                    }) {
                    nameSay(emit, L("rdap: a HOLD stands on the name — the registry itself has frozen it. That is never scenery; something is being disputed or unpaid."), .err)
                }
            }
            var expiry: Date? = nil
            if let events = dict["events"]
                as? [[String: Any]] {
                for event in events {
                    let action = event[
                        "eventAction"]
                        as? String ?? ""
                    let date = event[
                        "eventDate"]
                        as? String ?? ""
                    switch action {
                    case "registration":
                        nameSay(emit, String(format: L("rdap: born %@."), String(date.prefix(10))), .out)
                    case "expiration":
                        nameSay(emit, String(format: L("rdap: lapses %@."), String(date.prefix(10))), .out)
                        expiry = ISO8601DateFormatter()
                            .date(from: date)
                    case "last changed":
                        nameSay(emit, String(format: L("rdap: last changed %@."), String(date.prefix(10))), .out)
                    default:
                        break
                    }
                }
            }
            if let entities = dict["entities"]
                as? [[String: Any]] {
                for entity in entities {
                    let roles = entity["roles"]
                        as? [String] ?? []
                    guard roles.contains(
                        "registrar") else {
                        continue
                    }
                    var found: String? = nil
                    if let vcard = entity[
                        "vcardArray"]
                        as? [Any],
                       vcard.count == 2,
                       let rows = vcard[1]
                        as? [[Any]] {
                        for row in rows
                        where row.count >= 4 {
                            if (row[0] as? String)
                                == "fn" {
                                found = row[3]
                                    as? String
                            }
                        }
                    }
                    if let found = found {
                        nameSay(emit, String(format: L("rdap: kept by %@."), found), .out)
                    }
                }
            }
            if let servers = dict["nameservers"]
                as? [[String: Any]] {
                let names = servers.compactMap {
                    $0["ldhName"] as? String
                }
                if !names.isEmpty {
                    nameSay(emit, String(format: L("rdap: served by %lld nameserver(s): %@."), names.count, names.prefix(6).joined(separator: ", ")), .out)
                }
            }
            if let expiry = expiry {
                let days = Int(expiry
                    .timeIntervalSinceNow
                    / 86400)
                if days < 0 {
                    nameSay(emit, String(format: L("rdap: verdict — the name lapsed %lld day(s) ago. A lapsed name is a door anyone may buy."), -days), .err)
                } else if days < 30 {
                    nameSay(emit, String(format: L("rdap: verdict — %lld day(s) of term remain. Renewal should already be a machine's habit, not a person's memory."), days), .err)
                } else {
                    nameSay(emit, String(format: L("rdap: verdict — the deed is in good standing, %lld day(s) of term in hand."), days), .ok)
                }
            } else {
                nameSay(emit, L("rdap: verdict — the ledger read; no expiry stood in it to judge the term by."), .out)
            }
        }
    }

    // MARK: asnprobe — whose road the number runs on

    /// The Cymru map, read by the
    /// protocol's own trick: the
    /// reversed name asked as TXT.
    /// Which autonomous system
    /// announces the number, what
    /// prefix covers it, and under
    /// which flag the block was
    /// allocated. Read-only intel,
    /// read as the map prints it.
    static func asnprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let text = target.trimmingCharacters(
                in: .whitespacesAndNewlines)
            let home = nameHome()
            let queryName: String
            if text.contains(":") {
                var addr = in6_addr()
                let ok = text.withCString {
                    inet_pton(AF_INET6, $0,
                              &addr) == 1
                }
                guard ok else {
                    nameSay(emit, L("asnprobe: that is not an address this map can read."), .err)
                    return
                }
                let bytes = withUnsafeBytes(
                    of: &addr) { Array($0) }
                let nibbles = bytes.flatMap {
                    [Int($0 >> 4), Int($0 & 0xF)]
                }
                queryName = nibbles.reversed()
                    .map(String.init)
                    .joined(separator: ".")
                    + ".origin6.asn.cymru.com"
            } else {
                let octets = text.split(
                    separator: ".")
                let dotted = octets.count == 4
                    && octets.allSatisfy {
                        Int($0) != nil
                    }
                guard dotted else {
                    nameSay(emit, L("asnprobe: give an address — asnprobe 192.168.1.10"), .err)
                    return
                }
                queryName = octets.reversed()
                    .joined(separator: ".")
                    + ".origin.asn.cymru.com"
            }
            guard let reply = nameQuery(
                server: home.ip,
                name: queryName, type: 16),
                  let record = reply.answers
                    .first(where: {
                        $0.type == 16
                    }) else {
                nameSay(emit, String(format: L("asnprobe: the map holds no route for %@ — a number no network announces, or one the map has not caught up with."), text), .out)
                return
            }
            let parts = nameTXTString(record)
                .split(separator: "|")
                .map {
                    $0.trimmingCharacters(
                        in: .whitespaces)
                }
            guard parts.count >= 2 else {
                nameSay(emit, L("asnprobe: the map answered in a shape this reader cannot parse."), .err)
                return
            }
            let asn = parts[0]
            let prefix = parts[1]
            let country = parts.count > 2
                ? parts[2] : "?"
            let registry = parts.count > 3
                ? parts[3] : "?"
            nameSay(emit, String(format: L("asnprobe: %@ rides AS%@ — announced inside %@, allocated by %@ under %@."), text, asn, prefix, registry, country), .sys)
            if let nameReply = nameQuery(
                server: home.ip,
                name: "AS" + asn
                    + ".asn.cymru.com",
                type: 16),
               let nameRecord = nameReply
                .answers.first(where: {
                    $0.type == 16
                }) {
                let nameParts = nameTXTString(
                    nameRecord)
                    .split(separator: "|")
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespaces)
                    }
                if let asName = nameParts.last,
                   nameParts.count >= 5 {
                    nameSay(emit, String(format: L("asnprobe: the road's name: %@."), asName), .out)
                }
            }
            nameSay(emit, L("asnprobe: verdict — read off the public map (Team Cymru), exactly as it is printed there. The map lags the road by hours, sometimes more; it is a witness, not the deed."), .ok)
        }
    }

    // MARK: danglingprobe — the name that points at a ghost

    /// A CNAME is a promise: the name
    /// says "I live over there". This
    /// probe reads the promise and
    /// asks whether "over there"
    /// still exists — and, when the
    /// target is one of the great
    /// re-lettable service doors,
    /// grades the risk that a
    /// stranger could take the room
    /// over. Graded, reported, NEVER
    /// claimed: the probe registers
    /// nothing, anywhere, ever.
    static func danglingprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let name = nameDomain(target)
            guard !name.isEmpty,
                  name.contains(".") else {
                nameSay(emit, L("danglingprobe: give a name — danglingprobe app.example.com"), .err)
                return
            }
            let home = nameHome()
            let claimable = [
                "github.io", "herokuapp.com",
                "herokudns.com",
                "azurewebsites.net",
                "cloudapp.net",
                "trafficmanager.net",
                "blob.core.windows.net",
                "cloudfront.net",
                "s3.amazonaws.com",
                "elasticbeanstalk.com",
                "netlify.app", "netlify.com",
                "vercel.app",
                "wordpress.com", "ghost.io",
                "bitbucket.io", "surge.sh",
                "pantheonsite.io",
                "webflow.io", "fastly.net",
                "statuspage.io",
                "myshopify.com",
                "gitbook.io",
                "helpscoutdocs.com",
                "unbouncepages.com",
            ]
            guard let reply = nameQuery(
                server: home.ip, name: name,
                type: 5) else {
                nameSay(emit, L("danglingprobe: the resolver stayed silent."), .err)
                return
            }
            if reply.rcode == 3 {
                nameSay(emit, String(format: L("danglingprobe: %@ does not exist. Nothing stands, so nothing dangles."), name), .out)
                return
            }
            guard let cname = reply.answers
                .first(where: {
                    $0.type == 5
                }) else {
                nameSay(emit, String(format: L("danglingprobe: %@ makes no promise — no CNAME stands at it. A name that answers for itself cannot dangle."), name), .ok)
                return
            }
            let host = nameRender(
                reply.msg, cname)
            nameSay(emit, String(format: L("danglingprobe: %@ promises: 'I live at %@'."), name, host), .sys)
            // Follow the chain at most
            // two hops to the address,
            // the way a resolver would.
            var current = host
            var dead = false
            var hops = 0
            var landed: String? = nil
            while hops < 3 {
                hops += 1
                guard let step = nameQuery(
                    server: home.ip,
                    name: current, type: 1)
                else { break }
                if step.rcode == 3 {
                    dead = true
                    break
                }
                if step.answers.contains(
                    where: { $0.type == 1 }) {
                    landed = current
                    break
                }
                if let next = step.answers
                    .first(where: {
                        $0.type == 5
                    }) {
                    current = nameRender(
                        step.msg, next)
                    continue
                }
                if let auth = step.authority
                    .first(where: {
                        $0.type == 5
                    }) {
                    current = nameRender(
                        step.msg, auth)
                    continue
                }
                dead = step.answers.isEmpty
                break
            }
            let service = claimable.first(
                where: {
                    host == $0
                        || host.hasSuffix(
                            "." + $0)
                        || host.contains(
                            "s3-website")
                })
            if dead {
                if let service = service {
                    nameSay(emit, String(format: L("danglingprobe: verdict — HIGH RISK. %@ no longer exists, and it is a %@ door: a service that re-lets abandoned names to whoever asks. Anyone could take the room, and %@'s visitors would follow them into it. This probe reports the risk and claims NOTHING — the fix is the house's: strike the CNAME, or re-let the name itself."), host, service, name), .err)
                } else {
                    nameSay(emit, String(format: L("danglingprobe: verdict — DANGLING. %@ promises a house at %@, and %@ is gone (NXDOMAIN). Whether the room can be re-let depends on the far landlord, which DNS alone cannot say — but the promise should be struck either way."), name, host, host), .err)
                }
                return
            }
            if let landed = landed {
                if let service = service {
                    nameSay(emit, String(format: L("danglingprobe: %@ answers today (a %@ door). DNS alone cannot prove the tenant still lives behind it — a service can serve its own 'nothing here' page from a live address — so this probe reports the shape and stops: %@ → %@, alive on the wire."), landed, service, name, host), .out)
                } else {
                    nameSay(emit, String(format: L("danglingprobe: verdict — the promise is kept. %@ lives at %@, and %@ answers. Nothing dangles."), name, host, landed), .ok)
                }
            } else {
                nameSay(emit, String(format: L("danglingprobe: verdict — the chain from %@ could not be walked to an address from here. The promise exists; its keeping is unproven either way, and unproven is all this probe claims."), host), .out)
            }
        }
    }

    // MARK: the switchboard

    /// Wave five's dispatch — the
    /// netCommand case in Blacksite
    /// hands the verb and its target
    /// here, the way the web and
    /// doors waves ride benchWeb and
    /// benchDoors.
    static func benchNames(
        _ name: String, _ target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        switch name {
        case "dnsdeep":
            dnsdeep(target: target, emit: emit, done: done)
        case "zonetransfer":
            zonetransfer(target: target, emit: emit, done: done)
        case "reverseprobe":
            reverseprobe(target: target, emit: emit, done: done)
        case "dnscensus":
            dnscensus(target: target, emit: emit, done: done)
        case "wildcardprobe":
            wildcardprobe(target: target, emit: emit, done: done)
        case "caacheck":
            caacheck(target: target, emit: emit, done: done)
        case "ttlprobe":
            ttlprobe(target: target, emit: emit, done: done)
        case "soacheck":
            soacheck(target: target, emit: emit, done: done)
        case "nsecprobe":
            nsecprobe(target: target, emit: emit, done: done)
        case "dnssecgrade":
            dnssecgrade(target: target, emit: emit, done: done)
        case "mxprobe":
            mxprobe(target: target, emit: emit, done: done)
        case "smtpdeep":
            smtpdeep(target: target, emit: emit, done: done)
        case "smtptls":
            smtptls(target: target, emit: emit, done: done)
        case "spfprobe":
            spfprobe(target: target, emit: emit, done: done)
        case "dkimprobe":
            dkimprobe(target: target, emit: emit, done: done)
        case "dmarcprobe":
            dmarcprobe(target: target, emit: emit, done: done)
        case "mtasts":
            mtasts(target: target, emit: emit, done: done)
        case "tlsrpt":
            tlsrpt(target: target, emit: emit, done: done)
        case "bimi":
            bimi(target: target, emit: emit, done: done)
        case "certtrans":
            certtrans(target: target, emit: emit, done: done)
        case "subdomains":
            subdomainsCT(target: target, emit: emit, done: done)
        case "whoisdeep":
            whoisdeep(target: target, emit: emit, done: done)
        case "rdap":
            rdap(target: target, emit: emit, done: done)
        case "asnprobe":
            asnprobe(target: target, emit: emit, done: done)
        case "danglingprobe":
            danglingprobe(target: target, emit: emit, done: done)
        default:
            done()
        }
    }
}
