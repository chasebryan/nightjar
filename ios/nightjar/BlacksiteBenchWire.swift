import Foundation

// MARK: - Bench wave 7: the wire & intel
//
// The local link read at the protocol level, and the public
// ledgers read in the open. One knock, read, grade — plus
// ledger reads from PUBLIC sources only.
//
// INCUMBENT AUDIT (the Wave 3 discipline). `upnp` already ran
// an SSDP M-SEARCH census and `bonjour` a fixed-list Bonjour
// browser. Both are deepened here, not duplicated: the console
// verbs `upnp` and `bonjour` are RE-ROUTED to this file's
// engines (ssdpdeep / mdnsdeep — the same engines under their
// new names), and the old engines in BlacksitePentest.swift
// stand unreachable. ssdpdeep fetches EVERY description
// document (the incumbent read six, three fields deep) and
// censuses the full device + service ledger; mdnsdeep runs
// the DNS-SD enumeration itself (_services._dns-sd._udp), so
// it finds service types no fixed list knows. The SSDP
// engine keeps the incumbent's one side effect: the names it
// reads are filed to the NeighborhoodStore exactly as before.
//
// KEYED INTEL IS NEVER ASKED FOR A KEY. Shodan, Censys, HIBP,
// AbuseIPDB and the full passive-DNS archives (Farsight
// DNSDB, RiskIQ, SecurityTrails) appear only in limits lines.
// Geolocation and every ledger's claim are INFERENCE or a
// source's own record: graded for agreement, never printed
// as ground truth.
//
// Every wire frame was byte-verified in Python against its
// spec before it was written in Swift: the SSDP M-SEARCH
// (byte-identical to the incumbent's proven string), the
// mDNS enumeration + SRV/TXT reads (RFC 6762 wire shape,
// compression walked on fixtures), the DHCP DISCOVER
// (RFC 2131; an OFFER is read, a REQUEST is never built),
// the WS-Discovery Probe (the 2005/04 envelope), the NTP
// read (RFC 5905; offset arithmetic checked on fixtures),
// the DNSBL/Cymru query names, and the NBNS node-status
// frame (the incumbent nbstat's own construction).
// What could not be verified is degraded and says so:
// passivedns rides the one keyless passive-DNS-shaped ledger
// that verifies (HackerTarget's host search) and names the
// keyed archives in its limits; ripeprobe's blocklist
// element parses RIPEstat's blocklist answer defensively and
// says when the shape is not one it can read; bgprobe's AS
// paths are read from RIPEstat's looking-glass defensively
// for the same reason; dhcpprobe binds the client port 68
// when the system allows it and states the limit when it
// cannot; v6probe reads the console's own interfaces and
// says plainly that address rotation cannot be proven from
// an address list.

extension BlacksiteBench {

    // MARK: dispatch

    static func benchWire(
        _ name: String,
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        switch name {
        case "ssdpdeep", "upnp":
            wireSSDPDeep(emit: emit, done: done)
        case "mdnsdeep", "bonjour":
            wireMDNSDeep(emit: emit, done: done)
        case "dhcpprobe":
            wireDHCPProbe(emit: emit, done: done)
        case "wsdprobe":
            wireWSDProbe(emit: emit, done: done)
        case "ntpprobe":
            wireNTPProbe(target, emit: emit, done: done)
        case "smallsvc":
            wireSmallSvc(target, emit: emit, done: done)
        case "v6probe":
            wireV6Probe(emit: emit, done: done)
        case "bgprobe":
            wireBGProbe(target, emit: emit, done: done)
        case "ripeprobe":
            wireRIPEProbe(target, emit: emit, done: done)
        case "torprobe":
            wireTORProbe(target, emit: emit, done: done)
        case "rblprobe":
            wireRBLProbe(target, emit: emit, done: done)
        case "geoprobe":
            wireGEOProbe(target, emit: emit, done: done)
        case "cveprobe":
            wireCVEProbe(target, emit: emit, done: done)
        case "kevprobe":
            wireKEVProbe(target, emit: emit, done: done)
        case "ghprobe":
            wireGHProbe(target, emit: emit, done: done)
        case "gleifprobe":
            wireGLEIFProbe(target, emit: emit, done: done)
        case "urlscanprobe":
            wireURLScanProbe(target, emit: emit, done: done)
        case "passivedns":
            wirePassiveDNS(target, emit: emit, done: done)
        case "macprobe":
            wireMACProbe(target, emit: emit, done: done)
        case "wirecensus":
            wireCensus(target, emit: emit, done: done)
        default:
            done()
        }
    }

    // MARK: plumbing (wire-prefixed; reuses the house engines)

    /// One ledger GET through the house
    /// web session; status, body and
    /// headers come back (satFetch's
    /// sibling, kept in this file so the
    /// ledger verbs read uniformly).
    static func wireFetch(
        _ url: URL)
        -> (status: Int, body: String,
            headers: [String: String])? {
        guard let (data, http) = icsFetch(url)
        else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)
                .lowercased()] =
                String(describing: value)
        }
        return (http.statusCode,
                String(decoding: data,
                       as: UTF8.self), headers)
    }

    /// A URL with a query built the
    /// encoding-safe way.
    static func wireURL(
        _ base: String,
        _ query: [(String, String)])
        -> URL? {
        var parts = URLComponents(string: base)
        if !query.isEmpty {
            parts?.queryItems = query.map {
                URLQueryItem(name: $0.0, value: $0.1)
            }
        }
        return parts?.url
    }

    static func wireDict(
        _ value: Any?) -> [String: Any]? {
        return value as? [String: Any]
    }

    static func wireArr(
        _ value: Any?) -> [Any]? {
        return value as? [Any]
    }

    /// A string out of a JSON value:
    /// strings pass through, numbers are
    /// rendered plainly.
    static func wireStr(
        _ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func wireInt(
        _ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String {
            return Int(text)
        }
        return nil
    }

    static func wireBool(
        _ value: Any?) -> Bool? {
        return value as? Bool
    }

    /// One multicast (or broadcast)
    /// shout and every answer that comes
    /// home inside the window — the SSDP
    /// incumbent's socket shape, shared.
    static func wireCollect(
        destIP: String, port: UInt16,
        payload: [UInt8], window: Double,
        maxPackets: Int = 128)
        -> [(from: String, data: [UInt8])] {
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var dest = BlacksiteNet.sockaddrIn(
            ip: destIP, port: port)
        _ = withUnsafeMutablePointer(
            to: &dest) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                sendto(fd, payload,
                       payload.count, 0, sa,
                       socklen_t(MemoryLayout<
                            sockaddr_in>.size))
            }
        }
        BetafischTap.shared.recordDatagram(
            fd: fd, remoteIP: destIP,
            remotePort: Int(port),
            outbound: true, payload: payload,
            ipProto: 17)
        var out: [(from: String,
                     data: [UInt8])] = []
        let deadline = Date()
            .addingTimeInterval(window)
        while Date() < deadline
            && out.count < maxPackets {
            BlacksiteNet.setRecvTimeout(
                fd, seconds: min(0.4, max(
                    0.1, deadline
                        .timeIntervalSinceNow)))
            var buffer = [UInt8](
                repeating: 0, count: 65536)
            var from = sockaddr_in()
            var fromLen = socklen_t(
                MemoryLayout<sockaddr_in>
                    .size)
            let got = withUnsafeMutablePointer(
                to: &from) { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1) { sa in
                    recvfrom(fd, &buffer,
                             buffer.count, 0,
                             sa, &fromLen)
                }
            }
            if got <= 0 { continue }
            var addr = from.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &addr,
                      &text, socklen_t(
                        text.count))
            let sender = String(cString: text)
            let answer = Array(buffer[0..<got])
            BetafischTap.shared.recordDatagram(
                fd: fd, remoteIP: sender,
                remotePort: Int(
                    UInt16(bigEndian:
                            from.sin_port)),
                outbound: false, payload: answer,
                ipProto: 17)
            out.append((from: sender,
                        data: answer))
        }
        return out
    }

    /// A DNS name in wire labels.
    static func wireEncodeName(
        _ name: String) -> [UInt8] {
        var out: [UInt8] = []
        for part in name.split(
            separator: ".") {
            let bytes = Array(part.utf8)
            out.append(UInt8(
                clamping: bytes.count))
            out.append(contentsOf: bytes)
        }
        out.append(0)
        return out
    }

    /// Read a (possibly compressed) DNS
    /// name at an offset; returns the
    /// name and the offset just past it
    /// in the original stream. Mirrors
    /// the Python-verified walker.
    static func wireDNSName(
        _ msg: [UInt8], _ off: Int)
        -> (name: String, next: Int)? {
        var labels: [String] = []
        var at = off
        var next: Int? = nil
        var jumps = 0
        while at < msg.count {
            let len = Int(msg[at])
            if len == 0 {
                return (labels.joined(
                            separator: "."),
                        next ?? (at + 1))
            }
            if len & 0xC0 == 0xC0 {
                guard at + 1 < msg.count
                else { return nil }
                let ptr = (len & 0x3F) << 8
                    | Int(msg[at + 1])
                if next == nil {
                    next = at + 2
                }
                at = ptr
                jumps += 1
                if jumps > 128 { return nil }
                continue
            }
            guard at + 1 + len <= msg.count
            else { return nil }
            labels.append(String(
                bytes: Array(
                    msg[(at + 1)..<(at + 1 + len)]),
                encoding: .utf8) ?? "?")
            at += 1 + len
        }
        return nil
    }

    struct WireRR {
        var name: String
        var type: UInt16
        var ttl: UInt32
        var rdataAt: Int
        var rdlen: Int
    }

    /// Walk a whole DNS message into its
    /// three record sections.
    static func wireParseMessage(
        _ msg: [UInt8])
        -> (answers: [WireRR],
            authority: [WireRR],
            additional: [WireRR])? {
        guard msg.count >= 12 else {
            return nil
        }
        func u16(_ at: Int) -> Int {
            return Int(msg[at]) << 8
                | Int(msg[at + 1])
        }
        let qd = u16(4), an = u16(6)
        let ns = u16(8), ar = u16(10)
        var at = 12
        for _ in 0..<qd {
            guard let (_, next) = wireDNSName(
                msg, at) else { return nil }
            at = next + 4
            guard at <= msg.count else {
                return nil
            }
        }
        func section(_ count: Int)
            -> [WireRR]? {
            var out: [WireRR] = []
            for _ in 0..<count {
                guard let (name, next) =
                    wireDNSName(msg, at)
                else { return nil }
                at = next
                guard at + 10 <= msg.count
                else { return nil }
                let type = UInt16(u16(at))
                let ttl = UInt32(u16(at + 4)) << 16
                    | UInt32(u16(at + 6))
                let rdlen = u16(at + 8)
                let rdataAt = at + 10
                guard rdataAt + rdlen
                    <= msg.count
                else { return nil }
                out.append(WireRR(
                    name: name, type: type,
                    ttl: ttl, rdataAt: rdataAt,
                    rdlen: rdlen))
                at = rdataAt + rdlen
            }
            return out
        }
        guard let answers = section(an),
              let authority = section(ns),
              let additional = section(ar)
        else { return nil }
        return (answers, authority, additional)
    }

    /// The TXT strings inside one record
    /// of the Names core (rdata rides in
    /// NameRR.raw, length-prefixed
    /// chunks, exactly as on the wire).
    static func wireTXTStrings(
        _ rr: NameRR) -> [String] {
        var out: [String] = []
        var at = 0
        let raw = rr.raw
        while at < raw.count {
            let len = Int(raw[at])
            guard at + 1 + len <= raw.count
            else { break }
            out.append(String(
                bytes: Array(
                    raw[(at + 1)..<(at + 1 + len)]),
                encoding: .utf8) ?? "")
            at += 1 + len
        }
        return out
    }

    /// The resolver the DNS-shaped
    /// ledger reads go through: the
    /// house's own (its gateway), with
    /// Cloudflare as the stated fallback
    /// — the Names core's home rule.
    static func wireResolver()
        -> (label: String, ip: String) {
        if let gateway = BlacksiteNet
            .defaultGatewayIP() {
            return (L("your router"), gateway)
        }
        return ("Cloudflare", "1.1.1.1")
    }

    /// An IPv4 literal, validated octet
    /// by octet — or nil.
    static func wireIPv4(
        _ text: String) -> String? {
        let parts = text.split(
            separator: ".")
        guard parts.count == 4 else {
            return nil
        }
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({
                      $0.isNumber }),
                  let value = Int(part),
                  (0...255).contains(value),
                  part.count == 1
                    || !part.hasPrefix("0")
            else { return nil }
        }
        return text
    }

    /// A dotted quad reversed for the
    /// DNS ledger names (DNSBL, Cymru).
    static func wireReversed(
        _ ip: String) -> String {
        return ip.split(separator: ".")
            .reversed()
            .map(String.init)
            .joined(separator: ".")
    }

    // MARK: SSDP — the deep census
    // (upnp, re-routed and deepened)

    /// The M-SEARCH census: every
    /// answer's headers, then every
    /// description document read whole —
    /// devices, embedded devices and the
    /// service ledger — where the
    /// incumbent read six documents and
    /// three fields. The incumbent's
    /// NeighborhoodStore filing is kept.
    static func wireSSDPCore(
        light: Bool) -> [ICSLine] {
        let query = "M-SEARCH * "
            + "HTTP/1.1\r\n"
            + "HOST: 239.255.255.250:"
            + "1900\r\n"
            + "MAN: \"ssdp:discover\""
            + "\r\nMX: 2\r\n"
            + "ST: ssdp:all\r\n\r\n"
        let packets = wireCollect(
            destIP: "239.255.255.250",
            port: 1900,
            payload: Array(query.utf8),
            window: light ? 2.5 : 3.5,
            maxPackets: 256)
        struct Device {
            var st: String
            var server: String
            var location: String
            var usn: String
            var from: String
        }
        var devices: [String: Device] = [:]
        for packet in packets {
            let text = String(
                bytes: packet.data,
                encoding: .utf8) ?? ""
            var fields: [String: String] = [:]
            for row in text.split(
                separator: "\r\n") {
                if let colon = row
                    .firstIndex(of: ":") {
                    let key = row[..<colon]
                        .uppercased()
                    fields[key] = row[
                        row.index(
                            after: colon)...]
                        .trimmingCharacters(
                            in: .whitespaces)
                }
            }
            guard let st = fields["ST"]
            else { continue }
            let device = Device(
                st: st,
                server: fields["SERVER"] ?? "",
                location: fields["LOCATION"] ?? "",
                usn: fields["USN"] ?? "",
                from: packet.from)
            let key = device.location.isEmpty
                ? device.from + device.st
                : device.location
            devices[key] = device
        }
        if devices.isEmpty {
            return [(L("ssdpdeep: silence — nothing on this wire answers M-SEARCH, or SSDP is switched off."), .err)]
        }
        var lines: [ICSLine] = [(
            String(format: L("ssdpdeep — %lld answer(s) on this wire"), Int64(devices.count)), .sys)]
        var serviceTally: [String: Int] = [:]
        var described = 0
        let docCap = light ? 4 : 12
        for device in devices.values.sorted(
            by: { $0.from < $1.from }) {
            var line = "\(device.from) — \(device.st)"
            var named = false
            if described < docCap,
               !device.location.isEmpty,
               let url = URL(string: device.location),
               let fetched = wireFetch(url) {
                described += 1
                let xml = fetched.body
                let friendly = streetTag(xml, "friendlyName")
                let maker = streetTag(xml, "manufacturer")
                let model = streetTag(xml, "modelName")
                let number = streetTag(xml, "modelNumber")
                let serial = streetTag(xml, "serialNumber")
                let deviceTypes = streetTags(xml, "deviceType")
                let services = streetTags(xml, "serviceType")
                for service in services {
                    serviceTally[service, default: 0] += 1
                }
                if let friendly = friendly {
                    line = "\(device.from) — \(friendly)"
                    named = true
                }
                var bits: [String] = []
                if let maker = maker { bits.append(maker) }
                if let model = model { bits.append(model) }
                if let number = number { bits.append(number) }
                if !bits.isEmpty {
                    line += " (" + bits.joined(separator: " ") + ")"
                }
                if let serial = serial {
                    line += String(format: L(" · serial %@"), serial)
                }
                if deviceTypes.count > 1 {
                    line += String(format: L(" · %lld device(s) in the document"), Int64(deviceTypes.count))
                }
                if !services.isEmpty {
                    line += String(format: L(" · %lld service(s) offered"), Int64(services.count))
                }
                if !light {
                    var facts: [String] = []
                    if let friendly = friendly { facts.append(friendly) }
                    if let maker = maker { facts.append("made by " + maker) }
                    if let model = model, model != friendly { facts.append("model " + model) }
                    if !facts.isEmpty {
                        NeighborhoodStore.shared
                            .recordBonjourFacts(
                                ip: device.from,
                                label: "UPnP",
                                facts: facts)
                    }
                }
            }
            if !named && !device.server.isEmpty {
                line += " — " + device.server
            }
            lines.append((line, .ok))
            if !light,
               device.server.contains("FRITZ!Box") {
                NeighborhoodStore.shared
                    .recordBonjourFacts(
                        ip: device.from,
                        label: "UPnP",
                        facts: [device.server])
            }
        }
        if !serviceTally.isEmpty {
            let top = serviceTally
                .sorted(by: { $0.key < $1.key })
                .prefix(8)
                .map { "\($0.key) × \($0.value)" }
            lines.append((
                String(format: L("services on this wire: %@"), top.joined(separator: " · ")), .out))
        }
        lines.append((L("grade: an SSDP description document is a published nameplate — maker, model and serial are handed to any caller that asks, and the same multicast door is a known amplifier when it faces the internet. On the house wire it is how devices introduce themselves; the posture is that the introduction is complete."), .out))
        return lines
    }

    static func wireSSDPDeep(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("shouting M-SEARCH at the multicast door — the deep census reads every description document"), .sys)
            icsPrint(emit, wireSSDPCore(light: false))
        }
    }

    // MARK: mDNS — the enumeration census
    // (bonjour, re-routed and deepened)

    /// One DNS message's records, sorted
    /// into the census's four questions.
    struct WireMDNSBook {
        var types: [String] = []
        var instances: [String: String] = [:]
        var srv: [String: (port: Int, host: String)] = [:]
        var txt: [String: [String]] = [:]
        var addr: [String: String] = [:]
    }

    static func wireMDNSHarvest(
        _ packets: [(from: String, data: [UInt8])],
        into book: inout WireMDNSBook) {
        for packet in packets {
            guard let parsed = wireParseMessage(
                packet.data) else { continue }
            let all = parsed.answers
                + parsed.authority
                + parsed.additional
            for rr in all {
                let msg = packet.data
                switch rr.type {
                case 12:
                    guard let (target, _) =
                        wireDNSName(msg, rr.rdataAt)
                    else { continue }
                    if rr.name == "_services._dns-sd._udp.local" {
                        if !book.types.contains(target) {
                            book.types.append(target)
                        }
                    } else {
                        book.instances[target] = rr.name
                    }
                case 33:
                    guard rr.rdlen >= 7
                    else { continue }
                    let port = Int(msg[rr.rdataAt + 4]) << 8
                        | Int(msg[rr.rdataAt + 5])
                    let host = wireDNSName(
                        msg, rr.rdataAt + 6)?.name ?? ""
                    book.srv[rr.name] = (port: port, host: host)
                case 16:
                    var strings: [String] = []
                    var at = rr.rdataAt
                    let end = rr.rdataAt + rr.rdlen
                    while at < end {
                        let len = Int(msg[at])
                        guard at + 1 + len <= end
                        else { break }
                        strings.append(String(
                            bytes: Array(msg[(at + 1)..<(at + 1 + len)]),
                            encoding: .utf8) ?? "")
                        at += 1 + len
                    }
                    if !strings.isEmpty {
                        book.txt[rr.name] = strings
                    }
                case 1:
                    guard rr.rdlen == 4
                    else { continue }
                    book.addr[rr.name] =
                        Array(msg[rr.rdataAt..<(rr.rdataAt + 4)])
                            .map(String.init)
                            .joined(separator: ".")
                default:
                    continue
                }
            }
        }
    }

    static func wireMDNSQuery(
        _ name: String, _ type: UInt16)
        -> [UInt8] {
        var out: [UInt8] = [0, 0, 0, 0,
                            0, 1, 0, 0,
                            0, 0, 0, 0]
        out.append(contentsOf: wireEncodeName(name))
        // QU bit set (0x8000) over class IN:
        // the answer comes back unicast.
        out.append(UInt8(type >> 8))
        out.append(UInt8(type & 0xFF))
        out.append(0x80)
        out.append(0x01)
        return out
    }

    /// The enumeration census: ask the
    /// wire which service types exist
    /// (the meta-query), then ask each
    /// type for its instances, then read
    /// the SRV/TXT/A papers the answers
    /// carry — the census the incumbent's
    /// fixed type list could not take.
    static func wireMDNSCore(
        light: Bool) -> [ICSLine] {
        var book = WireMDNSBook()
        let enumeration = wireCollect(
            destIP: "224.0.0.251", port: 5353,
            payload: wireMDNSQuery(
                "_services._dns-sd._udp.local", 12),
            window: light ? 1.8 : 2.5,
            maxPackets: 256)
        wireMDNSHarvest(enumeration, into: &book)
        if book.types.isEmpty && !light {
            // Some responders answer the
            // enumeration only when it is
            // asked again after the room
            // wakes; one more knock, once.
            let again = wireCollect(
                destIP: "224.0.0.251", port: 5353,
                payload: wireMDNSQuery(
                    "_services._dns-sd._udp.local", 12),
                window: 1.5, maxPackets: 256)
            wireMDNSHarvest(again, into: &book)
        }
        // One PTR question per type, sent
        // together; one listening window
        // gathers them all.
        let types = Array(book.types.prefix(24))
        if !types.isEmpty {
            let fd = socket(AF_INET, SOCK_DGRAM,
                            IPPROTO_UDP)
            if fd >= 0 {
                defer { close(fd) }
                var dest = BlacksiteNet.sockaddrIn(
                    ip: "224.0.0.251", port: 5353)
                for type in types {
                    let query = wireMDNSQuery(type, 12)
                    _ = withUnsafeMutablePointer(
                        to: &dest) { ptr in
                        ptr.withMemoryRebound(
                            to: sockaddr.self,
                            capacity: 1) { sa in
                            sendto(fd, query,
                                   query.count, 0, sa,
                                   socklen_t(MemoryLayout<
                                    sockaddr_in>.size))
                        }
                    }
                }
                var gathered: [(from: String, data: [UInt8])] = []
                let deadline = Date()
                    .addingTimeInterval(light ? 2.0 : 3.0)
                while Date() < deadline
                    && gathered.count < 512 {
                    BlacksiteNet.setRecvTimeout(
                        fd, seconds: min(0.4, max(
                            0.1, deadline
                                .timeIntervalSinceNow)))
                    var buffer = [UInt8](
                        repeating: 0, count: 65536)
                    var from = sockaddr_in()
                    var fromLen = socklen_t(
                        MemoryLayout<sockaddr_in>.size)
                    let got = withUnsafeMutablePointer(
                        to: &from) { ptr in
                        ptr.withMemoryRebound(
                            to: sockaddr.self,
                            capacity: 1) { sa in
                            recvfrom(fd, &buffer,
                                     buffer.count, 0,
                                     sa, &fromLen)
                        }
                    }
                    if got <= 0 { continue }
                    var addr = from.sin_addr
                    var text = [CChar](
                        repeating: 0, count: 64)
                    inet_ntop(AF_INET, &addr,
                              &text, socklen_t(
                                text.count))
                    gathered.append((
                        from: String(cString: text),
                        data: Array(buffer[0..<got])))
                }
                wireMDNSHarvest(gathered, into: &book)
            }
        }
        // Instances whose papers did not
        // ride along get one SRV+TXT ask.
        if !light {
            let bare = book.instances.keys
                .filter { book.srv[$0] == nil }
                .prefix(24)
            for instance in bare {
                for type in [UInt16(33), UInt16(16)] {
                    let packets = wireCollect(
                        destIP: "224.0.0.251",
                        port: 5353,
                        payload: wireMDNSQuery(
                            instance, type),
                        window: 0.7,
                        maxPackets: 32)
                    wireMDNSHarvest(packets, into: &book)
                }
            }
        }
        if book.types.isEmpty
            && book.instances.isEmpty {
            return [(L("mdnsdeep: the room stayed quiet — nothing is announcing itself on this wire."), .err)]
        }
        var byType: [String: [String]] = [:]
        for (instance, type) in book.instances {
            byType[type, default: []].append(instance)
        }
        let listedTypes = Set(book.types)
            .union(byType.keys).sorted()
        var lines: [ICSLine] = [(
            String(format: L("mdnsdeep — %lld service type(s), %lld instance(s) announcing"), Int64(listedTypes.count), Int64(book.instances.count)), .sys)]
        for type in listedTypes {
            let names = (byType[type] ?? [])
                .sorted()
            lines.append((
                String(format: L("%@ — %lld instance(s)"), type, Int64(names.count)), .sys))
            if light { continue }
            for instance in names {
                var line = "  \(instance)"
                if let srv = book.srv[instance] {
                    let ip = book.addr[srv.host] ?? srv.host
                    line += " · \(ip):\(srv.port)"
                }
                if let txt = book.txt[instance] {
                    let bits = txt.filter {
                        $0.hasPrefix("model=")
                            || $0.hasPrefix("md=")
                            || $0.hasPrefix("deviceid=")
                            || $0.hasPrefix("ty=")
                            || $0.hasPrefix("fn=")
                            || $0.hasPrefix("am=")
                    }
                    if !bits.isEmpty {
                        line += " · " + bits.joined(
                            separator: " ")
                    }
                }
                lines.append((line, .out))
            }
        }
        let stray = listedTypes.count - book.types.count
        if stray > 0 {
            lines.append((
                String(format: L("%lld service type(s) answered instances without appearing in the enumeration — the room is larger than its own index"), Int64(stray)), .out))
        }
        lines.append((L("grade: everything above was published to the room at large — names, models and TXT papers are announced to any listener, which is how the house finds its own devices and how a stranger maps it. The census proves the publication, nothing more."), .out))
        return lines
    }

    static func wireMDNSDeep(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("listening for introductions — the enumeration census asks the wire what it announces"), .sys)
            icsPrint(emit, wireMDNSCore(light: false))
        }
    }

    // MARK: DHCP — one DISCOVER, read-only

    /// Shout one DISCOVER and gather the
    /// OFFERs. The client port (68) is
    /// bound when the system allows it;
    /// the returned flag says whether it
    /// was. No REQUEST is ever built, no
    /// lease is ever taken — the offer is
    /// read and let go.
    static func wireDHCPKnock()
        -> (offers: [[UInt8]], bound68: Bool,
            xid: UInt32, chaddr: [UInt8]) {
        let xid = UInt32.random(
            in: 1...UInt32.max)
        var chaddr: [UInt8] = (0..<6).map {
            _ in UInt8.random(in: 0...255)
        }
        chaddr[0] = (chaddr[0] & 0xFE) | 0x02
        var packet: [UInt8] = []
        packet.append(contentsOf: [1, 1, 6, 0])
        packet.append(UInt8((xid >> 24) & 0xFF))
        packet.append(UInt8((xid >> 16) & 0xFF))
        packet.append(UInt8((xid >> 8) & 0xFF))
        packet.append(UInt8(xid & 0xFF))
        packet.append(contentsOf: [0, 0, 0x80, 0x00])
        packet.append(contentsOf: [UInt8](
            repeating: 0, count: 16))
        packet.append(contentsOf: chaddr)
        packet.append(contentsOf: [UInt8](
            repeating: 0, count: 10))
        packet.append(contentsOf: [UInt8](
            repeating: 0, count: 64))
        packet.append(contentsOf: [UInt8](
            repeating: 0, count: 128))
        packet.append(contentsOf: [0x63, 0x82,
                                   0x53, 0x63])
        packet.append(contentsOf: [53, 1, 1])
        packet.append(contentsOf: [55, 6, 1, 3,
                                   6, 15, 51, 54])
        packet.append(255)
        while packet.count < 300 {
            packet.append(0)
        }
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else {
            return ([], false, xid, chaddr)
        }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET,
                   SO_REUSEADDR, &one,
                   socklen_t(MemoryLayout<
                    Int32>.size))
        setsockopt(fd, SOL_SOCKET,
                   SO_BROADCAST, &one,
                   socklen_t(MemoryLayout<
                    Int32>.size))
        var local = BlacksiteNet.sockaddrIn(
            ip: "0.0.0.0", port: 68)
        let bindResult = withUnsafeMutablePointer(
            to: &local) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                bind(fd, sa, socklen_t(
                    MemoryLayout<
                        sockaddr_in>.size))
            }
        }
        let bound68 = bindResult == 0
        var dest = BlacksiteNet.sockaddrIn(
            ip: "255.255.255.255", port: 67)
        _ = withUnsafeMutablePointer(
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
        var offers: [[UInt8]] = []
        let deadline = Date()
            .addingTimeInterval(3.5)
        while Date() < deadline
            && offers.count < 16 {
            BlacksiteNet.setRecvTimeout(
                fd, seconds: min(0.4, max(
                    0.1, deadline
                        .timeIntervalSinceNow)))
            var buffer = [UInt8](
                repeating: 0, count: 2048)
            let got = recv(fd, &buffer,
                           buffer.count, 0)
            if got <= 0 { continue }
            let reply = Array(buffer[0..<got])
            guard reply.count >= 240,
                  reply[0] == 2 else {
                continue
            }
            let replyXID = UInt32(reply[4]) << 24
                | UInt32(reply[5]) << 16
                | UInt32(reply[6]) << 8
                | UInt32(reply[7])
            guard replyXID == xid else {
                continue
            }
            offers.append(reply)
        }
        return (offers, bound68, xid, chaddr)
    }

    /// Read the offers the knock gathered
    /// into a ledger: who offers, what
    /// they hand out, and whether more
    /// than one authority answered.
    static func wireDHCPCore()
        -> (lines: [ICSLine],
            authorities: Int) {
        let knock = wireDHCPKnock()
        let macText = knock.chaddr.map {
            String(format: "%02X", $0)
        }.joined(separator: ":")
        var lines: [ICSLine] = [(
            String(format: L("dhcpprobe — one DISCOVER shouted for a phantom client (%@, a random locally-administered address); no REQUEST follows, no lease is taken"), macText), .sys)]
        if !knock.bound68 {
            lines.append((L("limit: the client port 68 could not be bound here, so offers addressed strictly to it may pass unheard — what follows is what this socket could hear."), .out))
        }
        if knock.offers.isEmpty {
            lines.append((L("dhcpprobe: no OFFER came back — no DHCP authority answers on this wire, or its offers do not reach this socket."), .err))
            return (lines, 0)
        }
        func option(_ packet: [UInt8],
                    _ code: UInt8) -> [UInt8]? {
            var at = 240
            while at + 1 < packet.count {
                let found = packet[at]
                if found == 255 { return nil }
                if found == 0 { at += 1; continue }
                let len = Int(packet[at + 1])
                guard at + 2 + len
                    <= packet.count
                else { return nil }
                if found == code {
                    return Array(packet[
                        (at + 2)..<(at + 2 + len)])
                }
                at += 2 + len
            }
            return nil
        }
        var servers = Set<String>()
        for offer in knock.offers {
            let yiaddr = Array(offer[16..<20])
                .map(String.init)
                .joined(separator: ".")
            var server = "?"
            if let sid = option(offer, 54),
               sid.count == 4 {
                server = sid.map(String.init)
                    .joined(separator: ".")
            }
            servers.insert(server)
            var bits: [String] = []
            bits.append(String(
                format: L("offers %@"), yiaddr))
            if let router = option(offer, 3),
               router.count >= 4 {
                bits.append(String(
                    format: L("router %@"),
                    Array(router[0..<4])
                        .map(String.init)
                        .joined(separator: ".")))
            }
            if let dns = option(offer, 6),
               !dns.isEmpty,
               dns.count % 4 == 0 {
                var servers4: [String] = []
                var at = 0
                while at + 4 <= dns.count {
                    servers4.append(
                        Array(dns[at..<(at + 4)])
                            .map(String.init)
                            .joined(separator: "."))
                    at += 4
                }
                bits.append(String(
                    format: L("DNS %@"),
                    servers4.joined(
                        separator: ", ")))
            }
            if let lease = option(offer, 51),
               lease.count == 4 {
                let seconds = Int(lease[0]) << 24
                    | Int(lease[1]) << 16
                    | Int(lease[2]) << 8
                    | Int(lease[3])
                bits.append(String(
                    format: L("lease %lld s"),
                    Int64(seconds)))
            }
            if let domain = option(offer, 15),
               !domain.isEmpty {
                bits.append(String(
                    format: L("domain %@"),
                    String(bytes: domain,
                           encoding: .utf8)
                        ?? "?"))
            }
            lines.append((
                String(format: L("%@ — %@"),
                       server,
                       bits.joined(
                        separator: " · ")), .ok))
        }
        if servers.count > 1 {
            lines.append((
                String(format: L("grade: %lld distinct DHCP authorities answered one DISCOVER. A wire is meant to have one voice handing out addresses — if the house runs a single server, every other answer is a rogue-authority finding, and its offers are the ones a stranger's client would take."), Int64(servers.count)), .out))
        } else {
            lines.append((L("grade: one authority answered, and its offer is the wire's address policy in miniature — router, DNS and lease as published above. The bench took nothing: the offer expires unclaimed, as designed."), .out))
        }
        return (lines, servers.count)
    }

    static func wireDHCPProbe(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsPrint(emit,
                     wireDHCPCore().lines)
        }
    }

    // MARK: WS-Discovery — the Probe census

    /// The blocks of one element in an
    /// XML body, tags and all — streetTag
    /// reads text; a census needs the
    /// whole match block first. The close
    /// is the element's OWN: nested tags
    /// are walked with a depth count, so
    /// a ProbeMatch is never cut short at
    /// its first child's close.
    static func wireBlocks(
        _ xml: String, _ name: String)
        -> [String] {
        func tagHead(
            _ from: String.Index)
            -> (local: String, closing: Bool,
                selfClosing: Bool,
                end: String.Index)? {
            guard let close = xml.range(
                of: ">", range:
                    from..<xml.endIndex)
            else { return nil }
            let raw = xml[from..<close.lowerBound]
                .trimmingCharacters(
                    in: .whitespaces)
            let closing = raw.hasPrefix("/")
            let body = closing
                ? String(raw.dropFirst()) : raw
            let head = body.split(
                separator: " ").first
                .map(String.init) ?? ""
            let local = head.split(
                separator: ":").last
                .map(String.init) ?? ""
            return (local, closing,
                    raw.hasSuffix("/"),
                    close.upperBound)
        }
        var out: [String] = []
        var cursor = xml.startIndex
        while let open = xml.range(
            of: "<", range: cursor..<xml.endIndex),
              let tag = tagHead(
                xml.index(after: open.lowerBound)) {
            if tag.closing
                || tag.local != name
                || tag.selfClosing {
                cursor = tag.end
                continue
            }
            var depth = 1
            var scan = tag.end
            var blockEnd: String.Index? = nil
            while let inner = xml.range(
                of: "<", range: scan..<xml.endIndex),
                  let innerTag = tagHead(
                    xml.index(
                        after: inner.lowerBound)) {
                if innerTag.local == name {
                    if innerTag.closing {
                        depth -= 1
                        if depth == 0 {
                            blockEnd = innerTag.end
                            break
                        }
                    } else if !innerTag.selfClosing {
                        depth += 1
                    }
                }
                scan = innerTag.end
            }
            guard let found = blockEnd
            else { break }
            let blockRange =
                open.lowerBound..<found
            out.append(String(xml[blockRange]))
            cursor = found
            if out.count >= 64 { break }
        }
        return out
    }

    static func wireWSDCore(
        light: Bool) -> [ICSLine] {
        let uuid = UUID().uuidString
        let probe = "<?xml version=\"1.0\" "
            + "encoding=\"utf-8\"?>"
            + "<soap:Envelope "
            + "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
            + "xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
            + "xmlns:wsd=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\">"
            + "<soap:Header>"
            + "<wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>"
            + "<wsa:MessageID>urn:uuid:"
            + uuid + "</wsa:MessageID>"
            + "<wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>"
            + "</soap:Header>"
            + "<soap:Body><wsd:Probe>"
            + "<wsd:Types>wsdp:Device</wsd:Types>"
            + "</wsd:Probe></soap:Body>"
            + "</soap:Envelope>"
        let packets = wireCollect(
            destIP: "239.255.255.252",
            port: 3702,
            payload: Array(probe.utf8),
            window: light ? 2.5 : 4.0,
            maxPackets: 128)
        struct Endpoint {
            var address: String
            var types: String
            var scopes: String
            var xaddrs: String
            var from: String
        }
        var endpoints: [String: Endpoint] = [:]
        for packet in packets {
            let xml = String(
                bytes: packet.data,
                encoding: .utf8) ?? ""
            for block in wireBlocks(
                xml, "ProbeMatch") {
                let address = streetTag(
                    block, "Address") ?? ""
                let key = address.isEmpty
                    ? packet.from
                    : address
                endpoints[key] = Endpoint(
                    address: address,
                    types: streetTag(
                        block, "Types") ?? "",
                    scopes: streetTag(
                        block, "Scopes") ?? "",
                    xaddrs: streetTag(
                        block, "XAddrs") ?? "",
                    from: packet.from)
            }
        }
        if endpoints.isEmpty {
            return [(L("wsdprobe: no ProbeMatches — nothing on this wire speaks WS-Discovery, or it keeps quiet."), .err)]
        }
        var lines: [ICSLine] = [(
            String(format: L("wsdprobe — %lld endpoint(s) answered the Probe"), Int64(endpoints.count)), .sys)]
        for endpoint in endpoints.values
            .sorted(by: { $0.from < $1.from }) {
            var line = "\(endpoint.from)"
            if !endpoint.types.isEmpty {
                line += " — " + endpoint.types
            }
            if !endpoint.xaddrs.isEmpty {
                line += " · " + endpoint.xaddrs
            }
            lines.append((line, .ok))
            if !light,
               !endpoint.scopes.isEmpty {
                lines.append((
                    String(format: L("  scopes: %@"),
                           endpoint.scopes), .out))
            }
        }
        lines.append((L("grade: WS-Discovery introduces the room's cameras and printers to any multicast ask — endpoint, types and scopes in one answer. That is the discovery working as designed, and the design publishes the inventory."), .out))
        return lines
    }

    static func wireWSDProbe(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsPrint(emit,
                     wireWSDCore(light: false))
        }
    }

    // MARK: NTP — the time plane, read

    /// One NTP read: the 48-byte client
    /// request, and the offset arithmetic
    /// of RFC 5905 §8 — theta from the
    /// four timestamps, nothing estimated.
    static func wireNTPRead(
        _ ip: String)
        -> (lines: [ICSLine], offset: Double?)? {
        var request = [UInt8](
            repeating: 0, count: 48)
        request[0] = 0x23
        let t1 = Date()
            .timeIntervalSince1970
        func stamp(_ unix: Double)
            -> (UInt32, UInt32) {
            let whole = floor(unix)
            let seconds = UInt32(whole)
                &+ 2_208_988_800
            let fraction = UInt32(
                (unix - whole) * 4_294_967_296.0)
            return (seconds, fraction)
        }
        let (s1, f1) = stamp(t1)
        for (index, byte) in
            [UInt8(s1 >> 24), UInt8((s1 >> 16) & 0xFF),
             UInt8((s1 >> 8) & 0xFF), UInt8(s1 & 0xFF),
             UInt8(f1 >> 24), UInt8((f1 >> 16) & 0xFF),
             UInt8((f1 >> 8) & 0xFF), UInt8(f1 & 0xFF)]
            .enumerated() {
            request[40 + index] = byte
        }
        guard let reply = BlacksitePentest
            .udpExchange(ip: ip, port: 123,
                         payload: request,
                         window: 3.0),
              reply.count >= 48
        else { return nil }
        let t4 = Date()
            .timeIntervalSince1970
        func readStamp(_ at: Int) -> Double {
            let seconds = UInt32(reply[at]) << 24
                | UInt32(reply[at + 1]) << 16
                | UInt32(reply[at + 2]) << 8
                | UInt32(reply[at + 3])
            let fraction = UInt32(reply[at + 4]) << 24
                | UInt32(reply[at + 5]) << 16
                | UInt32(reply[at + 6]) << 8
                | UInt32(reply[at + 7])
            return Double(seconds)
                - 2_208_988_800.0
                + Double(fraction) / 4_294_967_296.0
        }
        let t2 = readStamp(32)
        let t3 = readStamp(40)
        let offset = ((t2 - t1) + (t3 - t4)) / 2
        let delay = (t4 - t1) - (t3 - t2)
        // Root delay and dispersion ride
        // at bytes 4 and 8, signed 16.16
        // fixed point (RFC 5905 §7.3).
        func fixed16(_ at: Int) -> Double {
            var whole = Int(reply[at]) << 8
                | Int(reply[at + 1])
            if whole >= 0x8000 {
                whole -= 0x1_0000
            }
            let fraction = Int(reply[at + 2]) << 8
                | Int(reply[at + 3])
            return Double(whole)
                + Double(fraction) / 65_536.0
        }
        let rootDelay = fixed16(4)
        let rootDispersion = fixed16(8)
        let stratum = Int(reply[1])
        let leap = Int(reply[0] >> 6)
        let refid = String(
            bytes: reply[12..<16].filter {
                $0 >= 32 && $0 < 127
            }, encoding: .ascii) ?? ""
        var lines: [ICSLine] = []
        if stratum == 0 {
            lines.append((
                String(format: L("ntpprobe: %@ answered with a Kiss-o'-Death (%@) — the time plane refuses this caller, and the refusal is the reading."), ip, refid.isEmpty ? "?" : refid), .err))
            return (lines, nil)
        }
        let stratumWord: String
        switch stratum {
        case 1:
            stratumWord = L("a primary reference")
        case 2...15:
            stratumWord = L("a secondary server")
        default:
            stratumWord = L("unsynchronised")
        }
        lines.append((
            String(format: L("ntpprobe: %@ — stratum %lld (%@), reference %@"), ip, Int64(stratum), stratumWord, refid.isEmpty ? "—" : refid), .ok))
        lines.append((
            String(format: L("  offset %@: the server's clock stands %@ this console's by the four-timestamp arithmetic · round-trip %@"), ip, offset >= 0 ? String(format: L("%.1f ms ahead of"), abs(offset) * 1000) : String(format: L("%.1f ms behind"), abs(offset) * 1000), String(format: L("%.1f ms"), delay * 1000)), .out))
        lines.append((
            String(format: L("  root delay %@ · root dispersion %@ — the accumulated distance and doubt between this server and its own reference"), String(format: L("%.1f ms"), rootDelay * 1000), String(format: L("%.1f ms"), rootDispersion * 1000)), .out))
        if leap == 3 {
            lines.append((L("  its leap indicator says UNSYNCHRONISED — it serves a clock it does not itself trust."), .out))
        }
        if stratum >= 5 && stratum <= 15 {
            lines.append((L("  a stratum this deep is a long chain of hearsay — the time is only as good as every link above it."), .out))
        }
        return (lines, offset)
    }

    static func wireNTPProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var servers: [(label: String,
                            ip: String)] = []
            let gateway = BlacksiteNet
                .defaultGatewayIP()
            if let target = target,
               !target.isEmpty {
                if let resolved = BlacksiteNet
                    .resolve4(target) {
                    servers.append((
                        label: target,
                        ip: resolved.ip))
                } else {
                    icsSay(emit, String(
                        format: L("ntpprobe: %@ does not resolve."), target), .err)
                    return
                }
                if let gateway = gateway,
                   gateway != servers.first?.ip {
                    servers.append((
                        label: L("your router"),
                        ip: gateway))
                }
            } else if let gateway = gateway {
                servers.append((
                    label: L("your router"),
                    ip: gateway))
            }
            guard !servers.isEmpty else {
                icsSay(emit, L("ntpprobe: no server to read — name one, and no gateway could be found either."), .err)
                return
            }
            var offsets: [Double] = []
            for server in servers {
                if let read = wireNTPRead(
                    server.ip) {
                    icsPrint(emit, read.lines)
                    if let offset = read.offset {
                        offsets.append(offset)
                    }
                } else {
                    icsSay(emit, String(
                        format: L("ntpprobe: %@ did not answer on udp/123."), server.label), .err)
                }
            }
            if offsets.count == 2 {
                let apart = abs(
                    offsets[0] - offsets[1]) * 1000
                icsSay(emit, String(
                    format: L("grade: the two clocks disagree by %.1f ms — small change for logs, and the disagreement itself is the posture reading."), apart))
            } else if offsets.count == 1 {
                icsSay(emit, L("grade: one clock read. Everything on the wire timestamps by clocks like this one — logs, certificates and leases all lean on the time plane being honest."))
            }
        }
    }

    // MARK: the small services — retired, still answering

    /// Echo, discard, daytime, chargen
    /// and qotd: the RFC 862–866 parlour
    /// of 1983. One connect each, a capped
    /// read, and a grade — a chargen that
    /// answers in this century is an
    /// amplification finding.
    static func wireSmallSvc(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty,
                  let resolved = BlacksiteNet
                    .resolve4(target)
            else {
                icsSay(emit, L("smallsvc: give a host — smallsvc 192.168.1.1"), .err)
                return
            }
            let host = resolved.ip
            let services: [(port: UInt16,
                            name: String,
                            speak: [UInt8]?)] = [
                (7, L("echo"), Array(
                    "nightjar\r\n".utf8)),
                (9, L("discard"), nil),
                (13, L("daytime"), nil),
                (17, L("qotd"), nil),
                (19, L("chargen"), nil),
            ]
            var answered: [String] = []
            var chargen = false
            for service in services {
                guard let fd = icsSocket(
                    ip: host,
                    port: service.port,
                    timeout: 1.2) else {
                    continue
                }
                if let speak = service.speak {
                    _ = icsSendAll(fd, speak)
                }
                let heard = icsAvailable(
                    fd, seconds: 0.9,
                    cap: 512)
                close(fd)
                answered.append(service.name)
                var line = String(
                    format: L("smallsvc: %@ answers at %@:%lld"),
                    service.name, target,
                    Int64(service.port))
                if !heard.isEmpty {
                    let text = String(
                        bytes: heard,
                        encoding: .utf8)?
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        ?? ""
                    if service.port == 19 {
                        chargen = true
                        line += String(
                            format: L(" — and streams: %lld bytes read before the cap, and it would have kept coming"), Int64(heard.count))
                    } else if !text.isEmpty {
                        line += " — \""
                            + String(text.prefix(60))
                            + "\""
                    } else {
                        line += String(
                            format: L(" — %lld bytes, not words"), Int64(heard.count))
                    }
                } else {
                    line += L(" — the door opens and says nothing")
                }
                icsSay(emit, line, .ok)
            }
            if answered.isEmpty {
                icsSay(emit, String(
                    format: L("smallsvc: none of the five small services answers at %@ — the retired parlour is shut, as it should be."), target), .err)
                return
            }
            if chargen {
                icsSay(emit, L("grade: chargen answers. A service that streams endlessly to any caller is half of the classic UDP/TCP amplification pairs — on a modern wire its only remaining use is as a mirror for someone else's flood. Shut it."))
            } else {
                icsSay(emit, String(
                    format: L("grade: %lld of the five small services answer at %@. These were debugging parlours from 1983, retired by every baseline since — each one that answers is a door nobody remembered to close."), Int64(answered.count), target))
            }
        }
    }



    // MARK: blocklists — the DNSBL census

    /// The DNSBL answer codes, read per
    /// RFC 5782: a listing answers inside
    /// 127.0.0.0/8, and 127.255.255.254
    /// means the list itself refused the
    /// question — never a listing.
    static func wireDNSBLRead(
        _ reply: NameReply?)
        -> (listed: Bool, blocked: Bool,
            codes: [String]) {
        guard let reply = reply else {
            return (false, false, [])
        }
        var codes: [String] = []
        var blocked = false
        for answer in reply.answers
            where answer.type == 1
            && answer.raw.count == 4 {
            let text = answer.raw
                .map(String.init)
                .joined(separator: ".")
            if text == "127.255.255.254" {
                blocked = true
            } else if text.hasPrefix("127.") {
                codes.append(text)
            }
        }
        return (!codes.isEmpty, blocked, codes)
    }

    static func wireRBLProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("rblprobe: give a mail host or an IP — rblprobe mail.example.com"), .err)
                return
            }
            let ip: String
            var label = target
            if let literal = wireIPv4(target) {
                ip = literal
            } else if let resolved =
                BlacksiteNet.resolve4(target) {
                ip = resolved.ip
                label = target + " (" + ip + ")"
            } else {
                icsSay(emit, String(
                    format: L("rblprobe: %@ does not resolve."), target), .err)
                return
            }
            let reversed = wireReversed(ip)
            let resolver = wireResolver()
            // Sanity first: the RFC's own
            // test point must come back
            // listed, or this resolver's
            // answers mean nothing today.
            let sane = wireDNSBLRead(
                nameQuery(
                    server: resolver.ip,
                    name: "2.0.0.127.zen.spamhaus.org",
                    type: 1))
            guard sane.listed else {
                icsSay(emit, L("rblprobe: the sanity check failed — 2.0.0.127 is listed by definition, and the resolver that answered did not say so. Its answers cannot be trusted today, and no verdict follows."), .err)
                return
            }
            icsSay(emit, String(
                format: L("rblprobe — %@ against five lists, by way of %@"), label, resolver.label), .sys)
            let zones: [(zone: String,
                         house: String)] = [
                ("zen.spamhaus.org", L("Spamhaus ZEN — the combined Spamhaus ledger")),
                ("bl.spamcop.net", L("SpamCop — reports from receivers, expiring fast")),
                ("b.barracudacentral.org", L("Barracuda — the appliance vendor's ledger")),
                ("dnsbl.sorbs.net", L("SORBS — the long memory of mail abuse")),
                ("psbl.surriel.com", L("PSBL — passive, receiver-fed")),
            ]
            var listings = 0
            var blockedAny = false
            for (zone, house) in zones {
                let read = wireDNSBLRead(
                    nameQuery(
                        server: resolver.ip,
                        name: reversed + "." + zone,
                        type: 1))
                if read.blocked {
                    blockedAny = true
                    icsSay(emit, String(
                        format: L("  %@: refused to say (the list blocks this class of query — it never means the host is listed)"), house), .out)
                } else if read.listed {
                    listings += 1
                    icsSay(emit, String(
                        format: L("  %@: LISTED (%@)"), house, read.codes.joined(separator: ", ")), .err)
                } else {
                    icsSay(emit, String(
                        format: L("  %@: not listed"), house), .ok)
                }
            }
            if listings > 0 {
                icsSay(emit, String(
                    format: L("grade: %@ stands on %lld of the lists. Mail from it will bounce at receivers who consult them — the listing, the reason code and the delisting door live with each list, not here."), label, Int64(listings)))
            } else if blockedAny {
                icsSay(emit, L("grade: no list that answered names this host — a partial verdict, spoken as one: the lists that refused leave their column blank, not clean."))
            } else {
                icsSay(emit, String(
                    format: L("grade: %@ stands on none of the five ledgers — its mail should be judged on its content, not its name."), label))
            }
        }
    }

    // MARK: RIPEstat — the prefix ledger

    static func wireRIPEProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("ripeprobe: give a host, an IP, a prefix or an AS number — ripeprobe 193.0.0.0/21, ripeprobe AS3333"), .err)
                return
            }
            let cleaned = target
                .trimmingCharacters(
                    in: .whitespaces)
            // An AS number: the registry's
            // own overview of the holder.
            if cleaned.uppercased()
                .hasPrefix("AS") {
                let digits = cleaned.dropFirst(2)
                if !digits.isEmpty,
                   digits.allSatisfy({
                       $0.isNumber }) {
                    let asn = String(digits)
                    guard let url = wireURL(
                        "https://stat.ripe.net/data/as-overview/data.json",
                        [("resource", "AS" + asn)]),
                          let fetched = wireFetch(url),
                          let data = wireDict(
                            fetched.body),
                          let inner = wireDict(
                            data["data"])
                    else {
                        icsSay(emit, L("ripeprobe: RIPEstat did not answer — the ledger is unreachable from here, and no reading is invented in its place."), .err)
                        return
                    }
                    icsSay(emit, String(
                        format: L("ripeprobe — AS%@"), asn), .sys)
                    if let holder = wireStr(
                        inner["holder"]) {
                        icsSay(emit, String(
                            format: L("  holder: %@"), holder), .ok)
                    }
                    if let announced = wireBool(
                        inner["announced"]) {
                        icsSay(emit, String(
                            format: L("  announced on the public internet: %@"), announced ? L("yes") : L("no")), .out)
                    }
                    if let block = wireDict(
                        inner["block"]) {
                        let blockName = wireStr(
                            block["name"]) ?? ""
                        let blockDesc = wireStr(
                            block["desc"]) ?? ""
                        if !blockName.isEmpty
                            || !blockDesc.isEmpty {
                            icsSay(emit, String(
                                format: L("  registry block: %@ %@"), blockName, blockDesc), .out)
                        }
                    }
                    icsSay(emit, L("grade: the registry's papers for this routing identity — holder, block and whether it announces at all. bgprobe reads what it announces; this is who the registry says it is."))
                    return
                }
            }
            var prefix: String? = nil
            var subject = cleaned
            if cleaned.contains("/") {
                if let slash = cleaned.firstIndex(
                    of: "/"),
                   let base = wireIPv4(String(
                    cleaned[..<slash])) {
                    prefix = base + String(
                        cleaned[slash...])
                }
            }
            if prefix == nil {
                if let literal = wireIPv4(cleaned) {
                    prefix = literal + "/32"
                    subject = literal
                } else if let resolved =
                    BlacksiteNet.resolve4(cleaned) {
                    prefix = resolved.ip + "/32"
                    subject = cleaned + " ("
                        + resolved.ip + ")"
                }
            }
            guard let prefix = prefix,
                  let url = wireURL(
                    "https://stat.ripe.net/data/network-info/data.json",
                    [("resource", prefix)]),
                  let overview = wireFetch(url),
                  let data = wireDict(overview.body),
                  let inner = wireDict(data["data"]),
                  let asnList = wireArr(inner["asns"]),
                  let exact = wireStr(inner["prefix"])
            else {
                icsSay(emit, L("ripeprobe: RIPEstat did not answer — the ledger is unreachable from here, and no reading is invented in its place."), .err)
                return
            }
            let asns = asnList.compactMap {
                wireDict($0)
            }.compactMap { wireStr($0["asn"]) }
            icsSay(emit, String(
                format: L("ripeprobe — %@ rides inside %@, announced by AS%@"), subject, exact, asns.isEmpty ? "?" : asns.joined(separator: ", AS")), .sys)
            if let blockURL = wireURL(
                "https://stat.ripe.net/data/blocklist/data.json",
                [("resource", prefix)]),
               let blockFetch = wireFetch(blockURL),
               let blockData = wireDict(
                blockFetch.body),
               let blockInner = wireDict(
                blockData["data"]),
               let entries = wireArr(
                blockInner["blocklist"]),
               !entries.isEmpty {
                // The blocklist element's
                // shape is read defensively:
                // entries this bench cannot
                // parse are counted, not
                // dramatised.
                var shown = 0
                var unreadable = 0
                for entry in entries {
                    guard let entryDict =
                        wireDict(entry),
                          let covered = wireStr(
                            entryDict["prefix"])
                    else {
                        unreadable += 1
                        continue
                    }
                    let sources = wireArr(
                        entryDict["sources"])?
                        .compactMap { wireStr($0) }
                        ?? []
                    let details = wireStr(
                        entryDict["details"]) ?? ""
                    var line = String(
                        format: L("  blocklist: %@ named by %@"), covered, sources.joined(separator: ", "))
                    if !details.isEmpty {
                        line += " — " + details
                    }
                    icsSay(emit, line, .err)
                    shown += 1
                    if shown >= 4 { break }
                }
                if shown > 0 {
                    icsSay(emit, L("grade: the containing space carries a blocklist entry — networks neighbouring a listed prefix inherit its weather at strict receivers, whether or not their own hands are clean."))
                    return
                }
                if unreadable > 0 {
                    icsSay(emit, L("grade: RIPEstat's blocklist answer arrived in a shape this bench cannot read entry by entry — reported as unread, not as clean."))
                    return
                }
            }
            icsSay(emit, L("grade: RIPEstat names no blocklist entry over this space — the prefix's papers are in order as far as this ledger reads."))
        }
    }

    // MARK: BGP — the looking glass, read

    static func wireBGProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("bgprobe: give an AS number or a prefix — bgprobe AS3333, bgprobe 193.0.0.0/21"), .err)
                return
            }
            var asn: String? = nil
            var prefix: String? = nil
            let cleaned = target
                .trimmingCharacters(
                    in: .whitespaces)
            if cleaned.uppercased()
                .hasPrefix("AS") {
                let digits = cleaned.dropFirst(2)
                if !digits.isEmpty,
                   digits.allSatisfy({
                       $0.isNumber }) {
                    asn = String(digits)
                }
            }
            if asn == nil {
                if cleaned.contains("/") {
                    prefix = cleaned
                } else if let literal =
                    wireIPv4(cleaned) {
                    prefix = literal + "/32"
                } else if let resolved =
                    BlacksiteNet.resolve4(cleaned) {
                    prefix = resolved.ip + "/32"
                }
            }
            if let asn = asn {
                if let url = wireURL(
                    "https://stat.ripe.net/data/as-overview/data.json",
                    [("resource", "AS" + asn)]),
                   let fetched = wireFetch(url),
                   let data = wireDict(fetched.body),
                   let inner = wireDict(data["data"]),
                   let holder = wireStr(
                    inner["holder"]) {
                    icsSay(emit, String(
                        format: L("bgprobe — AS%@, held by %@"), asn, holder), .sys)
                } else {
                    icsSay(emit, String(
                        format: L("bgprobe — AS%@"), asn), .sys)
                }
                guard let url = wireURL(
                    "https://stat.ripe.net/data/announced-prefixes/data.json",
                    [("resource", "AS" + asn)]),
                      let fetched = wireFetch(url),
                      let data = wireDict(fetched.body),
                      let inner = wireDict(
                        data["data"]),
                      let list = wireArr(
                        inner["prefixes"])
                else {
                    icsSay(emit, L("bgprobe: RIPEstat did not answer — no census follows."), .err)
                    return
                }
                let prefixes = list.compactMap {
                    wireDict($0)
                }.compactMap {
                    wireStr($0["prefix"])
                }
                icsSay(emit, String(
                    format: L("  announces %lld prefix(es)"), Int64(prefixes.count)), .ok)
                for name in prefixes.prefix(16) {
                    icsSay(emit, "  " + name, .out)
                }
                if prefixes.count > 16 {
                    icsSay(emit, String(
                        format: L("  … and %lld more in the full ledger"), Int64(prefixes.count - 16)), .out)
                }
                icsSay(emit, L("grade: that is the whole of what the network claims under this number — every prefix here is believed by the world's routers until a better story arrives, which is the entire fragility of BGP in one list."))
                return
            }
            guard let prefix = prefix,
                  let url = wireURL(
                    "https://stat.ripe.net/data/looking-glass/data.json",
                    [("resource", prefix)]),
                  let fetched = wireFetch(url),
                  let data = wireDict(fetched.body),
                  let inner = wireDict(data["data"]),
                  let rrcs = wireArr(inner["rrcs"])
            else {
                icsSay(emit, L("bgprobe: the looking glass did not answer — no reading follows."), .err)
                return
            }
            var origins = Set<String>()
            var pathsSeen = 0
            var vantage = 0
            for rrc in rrcs {
                guard let rrcDict = wireDict(rrc),
                      let peers = wireArr(
                        rrcDict["peers"])
                else { continue }
                for peer in peers {
                    guard let peerDict =
                        wireDict(peer)
                    else { continue }
                    vantage += 1
                    if let origin = wireStr(
                        peerDict["origin"]) {
                        origins.insert(origin)
                    }
                    if let path = wireArr(
                        peerDict["as_path"]),
                       !path.isEmpty {
                        pathsSeen += 1
                        if pathsSeen <= 3 {
                            let hops = path
                                .compactMap {
                                    wireInt($0)
                                        .map(String.init)
                                }
                            icsSay(emit, String(
                                format: L("bgprobe — a path to %@: %@"), prefix, hops.joined(separator: " → ")), .out)
                        }
                    }
                }
            }
            icsSay(emit, String(
                format: L("bgprobe — %@ seen from %lld collector peer(s); origin AS%@"), prefix, Int64(vantage), origins.sorted().joined(separator: ", AS")), .sys)
            if origins.count > 1 {
                icsSay(emit, L("grade: more than one origin claims this prefix. Sometimes that is anycast or a legitimate transfer; sometimes it is a hijack in progress — the reading names the fact, and the fact deserves a second look either way."))
            } else {
                icsSay(emit, L("grade: one origin, seen consistently — the routing story for this prefix is the same story everywhere the collectors stand, which is all the trust BGP ever offers."))
            }
        }
    }







    // MARK: passive DNS — the remembered names

    static func wirePassiveDNS(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("passivedns: give a domain — passivedns example.com"), .err)
                return
            }
            var host = target
                .trimmingCharacters(
                    in: .whitespaces)
                .lowercased()
            if host.hasPrefix("www.") {
                host = String(host.dropFirst(4))
            }
            guard host.contains(".") else {
                icsSay(emit, L("passivedns: that is not a domain this bench reads."), .err)
                return
            }
            icsSay(emit, String(
                format: L("passivedns — the names %@ has worn, from the public ledgers"), host), .sys)
            var found = 0
            // HackerTarget hostsearch: the
            // subdomain ledger, plain text,
            // one line per remembered name.
            if let url = wireURL(
                "https://api.hackertarget.com/hostsearch/",
                [("q", host)]),
               let fetched = wireFetch(url) {
                let text = fetched.body
                if !text.lowercased().contains(
                    "error")
                    && !text.lowercased()
                        .contains("no dns") {
                    for row in text.split(
                        separator: "\n") {
                        let parts = row.split(
                            separator: ",")
                        guard let name =
                            parts.first
                        else { continue }
                        let ip = parts.count > 1
                            ? String(parts[1])
                            : ""
                        var line = "  "
                            + String(name)
                        if !ip.isEmpty {
                            line += " → " + ip
                        }
                        icsSay(emit, line, .ok)
                        found += 1
                        if found >= 24 { break }
                    }
                }
            }
            // The DNS history ledger proper.
            if let url = wireURL(
                "https://api.hackertarget.com/dnshistory/",
                [("q", host)]),
               let history = wireFetch(url) {
                let text = history.body
                if !text.lowercased().contains(
                    "error") {
                    var shown = 0
                    for row in text.split(
                        separator: "\n") {
                        let line = row
                            .trimmingCharacters(
                                in: .whitespaces)
                        if line.isEmpty
                            || line.hasPrefix("#") {
                            continue
                        }
                        icsSay(emit, "  " + line,
                               .out)
                        shown += 1
                        if shown >= 10 { break }
                    }
                    if shown > 0 {
                        found += shown
                    }
                }
            }
            if found == 0 {
                icsSay(emit, L("  the public ledgers remember nothing under this name — either it is young, quiet, or kept off the record."))
            }
            icsSay(emit, L("limits: the deep archives (SecurityTrails, DNSDB, VirusTotal's history) keep their ledgers behind keys, and the bench never asks for credentials — what is shown is the public record, and the public record is partial."))
            icsSay(emit, L("grade: a domain's past addresses are its biography — names it has shed, hosts it has left, infrastructure it shares with strangers. Renaming does not erase the record; it appends to it."))
        }
    }

    // MARK: CISA KEV — the exploited list, read whole

    /// The KEV catalog, fetched once and
    /// held for the rest of the run in a
    /// static — three thousand entries is
    /// a page, not a conversation.
    static var wireKEVCache: [[String: Any]]? = nil

    static func wireKEVLoad() -> [[String: Any]]? {
        if let cached = wireKEVCache {
            return cached
        }
        guard let url = wireURL(
            "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json",
            []),
              let fetched = wireFetch(url),
              let data = wireDict(fetched.body),
              let list = wireArr(
                data["vulnerabilities"])
        else { return nil }
        let entries = list.compactMap(wireDict)
        wireKEVCache = entries
        return entries
    }

    static func wireKEVProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("kevprobe: give a CVE or a product — kevprobe CVE-2021-44228, kevprobe log4j"), .err)
                return
            }
            guard let entries = wireKEVLoad()
            else {
                icsSay(emit, L("kevprobe: the KEV catalog could not be fetched — no verdict follows."), .err)
                return
            }
            let needle = target.lowercased()
            var hits: [[String: Any]] = []
            for entry in entries {
                let cve = wireStr(entry["cveID"])?
                    .lowercased() ?? ""
                let vendor = wireStr(
                    entry["vendorProject"])?
                    .lowercased() ?? ""
                let product = wireStr(
                    entry["product"])?
                    .lowercased() ?? ""
                if cve == needle
                    || vendor.contains(needle)
                    || product.contains(needle) {
                    hits.append(entry)
                }
            }
            icsSay(emit, String(
                format: L("kevprobe — %lld match(es) in the catalog of %lld known-exploited vulnerabilities"), Int64(hits.count), Int64(entries.count)), .sys)
            for hit in hits.prefix(8) {
                let cve = wireStr(hit["cveID"]) ?? "?"
                let name = wireStr(
                    hit["vulnerabilityName"]) ?? ""
                let due = wireStr(
                    hit["dueDate"]) ?? "?"
                let ransomware = wireStr(
                    hit["knownRansomwareCampaignUse"])
                    ?? "Unknown"
                icsSay(emit, String(
                    format: L("  %@: %@ — remediation was due %@; ransomware use: %@"), cve, name, due, ransomware), .err)
            }
            if hits.isEmpty {
                icsSay(emit, L("grade: no match in the catalog — CISA has no report of this being exploited in the wild. Absence here is not safety; it is the absence of a confirmed report."))
            } else {
                icsSay(emit, L("grade: a KEV entry is not a score or a suspicion — it is the federal ledger of vulnerabilities CONFIRMED exploited in the wild, each with a remediation deadline federal agencies were ordered to meet. Presence here outranks any CVSS number."))
            }
        }
    }

    // MARK: NVD — the CVE ledger

    /// One CVE out of an NVD answer: its
    /// id, its best severity line and its
    /// first English sentence. Shared by
    /// the id read and the product census.
    static func wireCVERead(
        _ cve: [String: Any])
        -> (id: String, severity: String,
            score: Double?, text: String) {
        let id = wireStr(cve["id"]) ?? "?"
        var text = ""
        if let descriptions = wireArr(
            cve["descriptions"]) {
            for entry in descriptions {
                guard let dict = wireDict(entry),
                      wireStr(dict["lang"]) == "en",
                      let value = wireStr(
                        dict["value"])
                else { continue }
                text = value
                break
            }
        }
        var severity = ""
        var score: Double? = nil
        if let metrics = wireDict(cve["metrics"]) {
            for key in ["cvssMetricV40",
                        "cvssMetricV31",
                        "cvssMetricV30",
                        "cvssMetricV2"] {
                guard score == nil,
                      let list = wireArr(
                        metrics[key]),
                      let firstMetric = list.first
                        .flatMap(wireDict),
                      let cvss = wireDict(
                        firstMetric["cvssData"]),
                      let number = cvss["baseScore"]
                        as? NSNumber
                else { continue }
                score = number.doubleValue
                severity = wireStr(
                    cvss["baseSeverity"])
                    ?? wireStr(firstMetric[
                        "baseSeverity"])
                    ?? ""
            }
        }
        return (id, severity, score, text)
    }

    static func wireCVEProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("cveprobe: give a product or a CVE id — cveprobe log4j, cveprobe CVE-2021-44228"), .err)
                return
            }
            let cleaned = target
                .trimmingCharacters(
                    in: .whitespaces)
            let kev = wireKEVLoad()
            // A CVE id: the single-entry read.
            if cleaned.uppercased()
                .hasPrefix("CVE-") {
                let cveID = cleaned.uppercased()
                guard let url = wireURL(
                    "https://services.nvd.nist.gov/rest/json/cves/2.0",
                    [("cveId", cveID)]),
                      let fetched = wireFetch(url),
                      let data = wireDict(
                        fetched.body),
                      let list = wireArr(
                        data["vulnerabilities"]),
                      let first = list.first,
                      let wrapper = wireDict(first),
                      let cve = wireDict(
                        wrapper["cve"])
                else {
                    icsSay(emit, String(
                        format: L("cveprobe: NVD has no readable entry for %@ — unknown id, or the ledger is unreachable."), cveID), .err)
                    return
                }
                let read = wireCVERead(cve)
                icsSay(emit, String(
                    format: L("cveprobe — %@"), read.id), .sys)
                if let score = read.score {
                    icsSay(emit, String(
                        format: L("  CVSS %.1f (%@)"), score, read.severity), .err)
                }
                if !read.text.isEmpty {
                    icsSay(emit, "  "
                        + String(read.text.prefix(400)),
                        .out)
                }
                if let kev = kev,
                   let mine = kev.first(where: {
                    wireStr($0["cveID"]) == read.id
                   }) {
                    icsSay(emit, String(
                        format: L("  KEV: LISTED — exploited in the wild; remediation was due %@."), wireStr(mine["dueDate"]) ?? "?"), .err)
                    icsSay(emit, L("grade: the catalogue entry says what it is; the KEV line says it is being used. Patch order follows the second sentence, not the first."))
                } else {
                    icsSay(emit, L("grade: the catalogue entry, as NVD keeps it — and no KEV listing: a score is an opinion about a flaw in the abstract, exploitation is a separate fact, and kevprobe keeps that ledger."))
                }
                return
            }
            // A product: the severity census
            // of everything NVD has published
            // under its name.
            guard let url = wireURL(
                "https://services.nvd.nist.gov/rest/json/cves/2.0",
                [("keywordSearch", cleaned),
                 ("resultsPerPage", "50")]),
                  let fetched = wireFetch(url),
                  let data = wireDict(fetched.body),
                  let list = wireArr(
                    data["vulnerabilities"])
            else {
                icsSay(emit, L("cveprobe: NVD did not answer — no census follows."), .err)
                return
            }
            let total = wireInt(
                data["totalResults"]) ?? list.count
            var reads: [(id: String,
                         severity: String,
                         score: Double?,
                         text: String)] = []
            var census: [String: Int] = [:]
            for item in list {
                guard let wrapper = wireDict(item),
                      let cve = wireDict(
                        wrapper["cve"])
                else { continue }
                let read = wireCVERead(cve)
                reads.append(read)
                let band = read.severity.isEmpty
                    ? L("unscored") : read.severity
                census[band, default: 0] += 1
            }
            icsSay(emit, String(
                format: L("cveprobe — %@ : %lld published CVE(s) in NVD (the first %lld read here)"), cleaned, Int64(total), Int64(reads.count)), .sys)
            let censusLine = census
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key) × \($0.value)" }
                .joined(separator: " · ")
            if !censusLine.isEmpty {
                icsSay(emit, String(
                    format: L("  severity census: %@"), censusLine), .out)
            }
            let ranked = reads.sorted {
                ($0.score ?? -1) > ($1.score ?? -1)
            }
            var kevHits: [String] = []
            for read in ranked.prefix(8) {
                var line = "  " + read.id
                if let score = read.score {
                    line += String(
                        format: L(" — CVSS %.1f (%@)"), score, read.severity)
                }
                icsSay(emit, line, .err)
                if let kev = kev,
                   kev.contains(where: {
                    wireStr($0["cveID"]) == read.id
                   }) {
                    kevHits.append(read.id)
                }
            }
            if !kevHits.isEmpty {
                icsSay(emit, String(
                    format: L("  of these, KEV lists %@ — exploited in the wild, not merely scored."), kevHits.joined(separator: ", ")), .err)
            }
            icsSay(emit, L("grade: a product's CVE census is its published wound history — the count matters less than the top of the list, and a KEV name anywhere in it outranks every score beside it."))
        }
    }







    // MARK: geo — the address's claimed home

    static func wireGEOProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("geoprobe: give a host or an IP — geoprobe example.com"), .err)
                return
            }
            let ip: String
            var label = target
            if let literal = wireIPv4(target) {
                ip = literal
            } else if let resolved =
                BlacksiteNet.resolve4(target) {
                ip = resolved.ip
                label = target + " (" + ip + ")"
            } else {
                icsSay(emit, String(
                    format: L("geoprobe: %@ does not resolve."), target), .err)
                return
            }
            icsSay(emit, String(
                format: L("geoprobe — %@"), label), .sys)
            var countries: [String] = []
            // ip-api: the coarse ledger.
            if let url = wireURL(
                "http://ip-api.com/json/" + ip,
                [("fields", "status,message,country,regionName,city,lat,lon,timezone,isp,org,as")]),
               let fetched = wireFetch(url),
               let data = wireDict(fetched.body),
               wireStr(data["status"]) == "success" {
                let place = [wireStr(data["city"]),
                             wireStr(data["regionName"]),
                             wireStr(data["country"])]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                icsSay(emit, String(
                    format: L("  ip-api places it: %@"), place.isEmpty ? "?" : place), .ok)
                if let country = wireStr(
                    data["country"]) {
                    countries.append(country)
                }
                if let lat = data["lat"]
                    as? NSNumber,
                   let lon = data["lon"]
                    as? NSNumber {
                    icsSay(emit, String(
                        format: L("  coordinates claimed: %.4f, %.4f · timezone %@"), lat.doubleValue, lon.doubleValue, wireStr(data["timezone"]) ?? "?"), .out)
                }
                if let isp = wireStr(data["isp"]) {
                    icsSay(emit, String(
                        format: L("  ISP: %@ · %@"), isp, wireStr(data["as"]) ?? ""), .out)
                }
            } else if let url = wireURL(
                "https://ipwho.is/" + ip, []),
               let fetched = wireFetch(url),
               let data = wireDict(fetched.body),
               wireBool(data["success"]) == true {
                // ipwho.is: the second voice,
                // asked when the first is mute.
                let place = [wireStr(data["city"]),
                             wireStr(data["region"]),
                             wireStr(data["country"])]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                icsSay(emit, String(
                    format: L("  ipwho.is places it: %@"), place.isEmpty ? "?" : place), .ok)
                if let country = wireStr(
                    data["country"]) {
                    countries.append(country)
                }
                if let connection = wireDict(
                    data["connection"]) {
                    icsSay(emit, String(
                        format: L("  connection: %@ (AS%lld)"), wireStr(connection["isp"]) ?? "?", Int64(wireInt(connection["asn"]) ?? 0)), .out)
                }
            }
            // ipinfo: the anycast-aware
            // ledger, keyless tier.
            if let url = wireURL(
                "https://ipinfo.io/" + ip + "/json",
                []),
               let fetched = wireFetch(url),
               let data = wireDict(fetched.body),
               wireStr(data["ip"]) != nil {
                var bits: [String] = []
                if let city = wireStr(data["city"]) {
                    bits.append(city)
                }
                if let country = wireStr(
                    data["country"]) {
                    bits.append(country)
                    countries.append(country)
                }
                if let org = wireStr(data["org"]) {
                    bits.append(org)
                }
                if !bits.isEmpty {
                    icsSay(emit, String(
                        format: L("  ipinfo places it: %@"), bits.joined(separator: " · ")), .out)
                }
                if wireBool(data["anycast"]) == true {
                    icsSay(emit, L("  anycast: this address is served from many places at once — the 'place' above is a fiction of the nearest door."))
                }
            }
            if countries.count >= 2 {
                let agreed = Set(countries).count == 1
                icsSay(emit, agreed
                    ? L("agreement: the ledgers concur on the country — as far as inference goes, that is agreement, not proof.")
                    : L("agreement: the ledgers DISAGREE on the country — treat every placement above as a guess with a source, not a fact."))
            }
            icsSay(emit, L("grade: geolocation is inference, labelled as such — a database's best guess from registrations and measurements, city-accurate on a good day and merely country-true on a bad one. The ledgers disagreeing IS the accuracy reading."))
        }
    }

    // MARK: MAC — the vendor in the address

    /// The bounded house OUI table: the
    /// prefixes a house wire actually
    /// meets. Unknown prefixes are
    /// reported as unknown — a bounded
    /// table that says so beats a
    /// fabricated vendor.
    static let wireOUITable: [(String, String)] = [
        ("00:0C:29", "VMware"), ("00:50:56", "VMware"),
        ("00:1C:42", "Parallels"), ("08:00:27", "VirtualBox"),
        ("52:54:00", "QEMU / KVM"), ("00:16:3E", "Xen"),
        ("00:15:5D", "Microsoft Hyper-V"), ("00:03:FF", "Microsoft (virtual)"),
        ("B8:27:EB", "Raspberry Pi Foundation"), ("DC:A6:32", "Raspberry Pi Foundation"),
        ("E4:5F:01", "Raspberry Pi Foundation"), ("D8:3A:DD", "Raspberry Pi Trading"),
        ("2C:CF:67", "Raspberry Pi Trading"), ("00:25:90", "Super Micro"),
        ("00:1B:21", "Intel"), ("00:1A:11", "Google"),
        ("3C:5A:B4", "Google"), ("94:EB:2C", "Google"),
        ("F4:F5:D8", "Google"), ("00:17:88", "Philips Lighting (Signify)"),
        ("EC:B5:FA", "Philips Lighting (Signify)"), ("00:04:20", "Slim Devices (Logitech)"),
        ("5C:3C:27", "Samsung"), ("F0:25:B7", "Samsung"),
        ("18:67:B0", "Apple"), ("3C:15:C2", "Apple"),
        ("A4:83:E7", "Apple"), ("F0:DB:E2", "Apple"),
        ("AC:DE:48", "Apple"), ("00:0A:27", "Apple"),
        ("D0:23:DB", "Apple"), ("7C:6D:62", "Apple"),
        ("28:CF:DA", "Apple"), ("C8:2A:14", "Apple"),
        ("00:1A:2B", "Cisco"), ("00:25:9C", "Cisco-Linksys"),
        ("20:AA:4B", "Cisco-Linksys"), ("C8:D7:19", "Cisco-Linksys"),
        ("00:04:5A", "Linksys"), ("00:06:25", "Linksys"),
        ("00:0C:41", "Linksys"), ("00:0F:66", "Linksys"),
        ("00:12:17", "Cisco-Linksys"), ("00:13:10", "Linksys"),
        ("00:14:BF", "Linksys"), ("00:16:B6", "Linksys"),
        ("00:18:39", "Cisco-Linksys"), ("00:18:F8", "Cisco-Linksys"),
        ("00:1A:70", "Cisco-Linksys"), ("00:1D:7E", "Cisco-Linksys"),
        ("00:1E:8C", "ASUSTek"), ("04:D4:C4", "ASUSTek"),
        ("2C:4D:54", "ASUSTek"), ("60:45:CB", "ASUSTek"),
        ("00:09:5B", "NETGEAR"), ("00:0F:B5", "NETGEAR"),
        ("00:14:6C", "NETGEAR"), ("00:18:4D", "NETGEAR"),
        ("00:1B:2F", "NETGEAR"), ("00:1E:2A", "NETGEAR"),
        ("00:22:3F", "NETGEAR"), ("00:24:B2", "NETGEAR"),
        ("00:26:F2", "NETGEAR"), ("20:4E:7F", "NETGEAR"),
        ("9C:3D:CF", "NETGEAR"), ("A0:21:B7", "NETGEAR"),
        ("00:19:E0", "TP-Link"), ("14:CC:20", "TP-Link"),
        ("1C:3B:AD", "TP-Link"), ("50:C7:BF", "TP-Link"),
        ("54:C8:0F", "TP-Link"), ("64:66:B3", "TP-Link"),
        ("A0:F3:C1", "TP-Link"), ("EC:08:6B", "TP-Link"),
        ("00:05:5D", "D-Link"), ("00:0D:88", "D-Link"),
        ("00:0F:3D", "D-Link"), ("00:13:46", "D-Link"),
        ("00:15:E9", "D-Link"), ("00:17:9A", "D-Link"),
        ("00:19:5B", "D-Link"), ("00:1B:11", "D-Link"),
        ("00:1C:F0", "D-Link"), ("00:1E:58", "D-Link"),
        ("00:21:91", "D-Link"), ("00:22:B0", "D-Link"),
        ("00:24:01", "D-Link"), ("00:26:5A", "D-Link"),
        ("1C:7E:E5", "D-Link"), ("00:27:22", "Ubiquiti"),
        ("04:18:D6", "Ubiquiti"), ("18:E8:29", "Ubiquiti"),
        ("24:A4:3C", "Ubiquiti"), ("44:D9:E7", "Ubiquiti"),
        ("68:D7:9A", "Ubiquiti"), ("74:83:C2", "Ubiquiti"),
        ("78:8A:20", "Ubiquiti"), ("80:2A:A8", "Ubiquiti"),
        ("B4:FB:E4", "Ubiquiti"), ("DC:9F:DB", "Ubiquiti"),
        ("F0:9F:C2", "Ubiquiti"), ("FC:EC:DA", "Ubiquiti"),
        ("00:11:32", "Synology"), ("90:09:D0", "Synology"),
        ("00:08:9B", "QNAP"), ("24:5E:BE", "QNAP"),
        ("5C:CF:7F", "Espressif"), ("18:FE:34", "Espressif"),
        ("24:0A:C4", "Espressif"), ("24:62:AB", "Espressif"),
        ("30:AE:A4", "Espressif"), ("84:CC:A8", "Espressif"),
        ("8C:AA:B5", "Espressif"), ("A4:CF:12", "Espressif"),
        ("CC:50:E3", "Espressif"), ("EC:FA:BC", "Espressif"),
        ("2C:3A:E8", "Espressif"), ("B4:E6:2D", "Espressif"),
        ("7C:DF:A1", "Espressif"), ("00:0E:58", "Sonos"),
        ("48:A6:B8", "Sonos"), ("5C:AA:FD", "Sonos"),
        ("78:28:CA", "Sonos"), ("94:9F:3E", "Sonos"),
        ("B8:E9:37", "Sonos"), ("F0:F6:C1", "Sonos"),
        ("54:2A:1B", "Sonos"), ("DC:EF:CA", "eero (Amazon)"),
        ("14:91:82", "eero (Amazon)"), ("34:D2:70", "Amazon Technologies"),
        ("40:B4:CD", "Amazon Technologies"), ("44:65:0D", "Amazon Technologies"),
        ("68:54:FD", "Amazon Technologies"), ("6C:56:97", "Amazon Technologies"),
        ("74:75:48", "Amazon Technologies"), ("84:D6:D0", "Amazon Technologies"),
        ("AC:63:BE", "Amazon Technologies"), ("00:BB:3A", "Amazon Technologies"),
        ("F0:F0:A4", "Amazon Technologies"), ("FC:A1:83", "Amazon Technologies")
    ]

    static func wireMACProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("macprobe: give a MAC address — macprobe B8:27:EB:12:34:56"), .err)
                return
            }
            let hexDigits = target.uppercased()
                .filter { $0.isHexDigit }
            guard hexDigits.count == 12 else {
                icsSay(emit, L("macprobe: that is not a MAC address — six octets of hex are the shape."), .err)
                return
            }
            let digits = Array(hexDigits)
            var octets: [String] = []
            for index in stride(from: 0, to: 12,
                                by: 2) {
                octets.append(
                    String(digits[index])
                    + String(digits[index + 1]))
            }
            let pretty = octets.joined(
                separator: ":")
            guard let firstByte = UInt8(
                octets[0], radix: 16)
            else {
                icsSay(emit, L("macprobe: that is not a MAC address — six octets of hex are the shape."), .err)
                return
            }
            let locallyAdministered =
                (firstByte & 0x02) != 0
            let multicast = (firstByte & 0x01) != 0
            let prefix = octets.prefix(3)
                .joined(separator: ":")
            let vendor = wireOUITable.first {
                $0.0 == prefix
            }?.1
            icsSay(emit, String(
                format: L("macprobe — %@"), pretty), .sys)
            if let vendor = vendor {
                icsSay(emit, String(
                    format: L("  OUI %@: %@"), prefix, vendor), .ok)
            } else {
                icsSay(emit, String(
                    format: L("  OUI %@: not in this bench's bounded house table — reported unknown rather than guessed"), prefix), .out)
            }
            if locallyAdministered {
                icsSay(emit, L("  the locally-administered bit is SET — this address was assigned by software, not burned in by a maker: the modern phone behaviour (per-network randomised MACs), a virtual machine, or a hand-set address. Vendor attribution from the OUI is void for such addresses."))
            } else {
                icsSay(emit, L("  the locally-administered bit is clear — a universally administered address, the OUI means what it says."))
            }
            icsSay(emit, multicast
                ? L("  the multicast bit is SET — a group address, not a single device's name.")
                : L("  the multicast bit is clear — a unicast address, one device's name."))
            if vendor == nil
                && !locallyAdministered {
                icsSay(emit, L("grade: an unknown OUI in the bounded table is a limit of the table, not a mystery about the device — the IEEE registry holds the rest, and the bench does not invent vendors."))
            } else {
                icsSay(emit, L("grade: the first three octets are a maker's mark, assigned by the IEEE; the last three are the device's own serial in that maker's space. A MAC address is a nameplate that cannot lie about its maker — unless the second bit says software wrote it."))
            }
        }
    }

    // MARK: Tor — the Onionoo ledger

    static func wireTORProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("torprobe: give a host or an IP — torprobe 203.0.113.9"), .err)
                return
            }
            let ip: String
            var label = target
            if let literal = wireIPv4(target) {
                ip = literal
            } else if let resolved =
                BlacksiteNet.resolve4(target) {
                ip = resolved.ip
                label = target + " (" + ip + ")"
            } else {
                icsSay(emit, String(
                    format: L("torprobe: %@ does not resolve."), target), .err)
                return
            }
            guard let url = wireURL(
                "https://onionoo.torproject.org/details",
                [("search", ip)]),
                  let fetched = wireFetch(url),
                  let data = wireDict(fetched.body)
            else {
                icsSay(emit, L("torprobe: Onionoo did not answer — the ledger is unreachable from here."), .err)
                return
            }
            let relays = wireArr(
                data["relays"]) ?? []
            let bridges = wireArr(
                data["bridges"]) ?? []
            if relays.isEmpty && bridges.isEmpty {
                icsSay(emit, String(
                    format: L("torprobe — %@: no published Tor relay or bridge wears this address"), label), .sys)
                icsSay(emit, L("grade: Onionoo is the Tor network's own published census — an address absent from it is not carrying public Tor traffic under this name. Private bridges and pluggable transports are unpublished by design, and the ledger says nothing about them either way."))
                return
            }
            icsSay(emit, String(
                format: L("torprobe — %@ in the Tor ledger: %lld relay(s), %lld bridge(s)"), label, Int64(relays.count), Int64(bridges.count)), .sys)
            for relay in relays.prefix(6) {
                guard let dict = wireDict(relay)
                else { continue }
                let nickname = wireStr(
                    dict["nickname"]) ?? "?"
                let running = wireBool(
                    dict["running"]) ?? false
                let flags = wireArr(dict["flags"])?
                    .compactMap { wireStr($0) }
                    ?? []
                icsSay(emit, String(
                    format: L("  relay %@: %@ · flags %@"), nickname, running ? L("running now") : L("not running in the latest consensus"), flags.joined(separator: ", ")), .ok)
                if let policy = wireDict(
                    dict["exit_policy_summary"]) {
                    let accept = wireArr(
                        policy["accept"])?
                        .compactMap { wireStr($0) }
                        ?? []
                    let reject = wireArr(
                        policy["reject"])?
                        .compactMap { wireStr($0) }
                        ?? []
                    if !accept.isEmpty {
                        icsSay(emit, String(
                            format: L("    exit policy accepts: %@"), accept.joined(separator: ", ")), .out)
                    }
                    if !reject.isEmpty {
                        icsSay(emit, String(
                            format: L("    exit policy rejects: %@"), reject.joined(separator: ", ")), .out)
                    }
                }
                if let first = wireStr(
                    dict["first_seen"]),
                   let last = wireStr(
                    dict["last_seen"]) {
                    icsSay(emit, String(
                        format: L("    on the record since %@ · last seen %@"), first, last), .out)
                }
            }
            icsSay(emit, L("grade: a published relay is a public service with a public record — the reading proves the address carries Tor traffic openly, which is the opposite of a secret. What rides through it is Tor's own business, and no ledger here reads it."))
        }
    }

    // MARK: GitHub — the published footprint

    static func wireGHProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("ghprobe: give a GitHub user or organisation — ghprobe torvalds"), .err)
                return
            }
            let name = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard let url = wireURL(
                "https://api.github.com/users/"
                + name, []),
                  let fetched = wireFetch(url)
            else {
                icsSay(emit, L("ghprobe: GitHub did not answer — no census follows."), .err)
                return
            }
            guard fetched.status == 200,
                  let account = wireDict(
                    fetched.body)
            else {
                icsSay(emit, String(
                    format: L("ghprobe: no public GitHub account answers to %@."), name), .err)
                return
            }
            let kind = wireStr(
                account["type"]) ?? "User"
            let display = wireStr(
                account["name"]) ?? name
            icsSay(emit, String(
                format: L("ghprobe — %@ (%@, a %@ account)"), display, name, kind), .sys)
            var bits: [String] = []
            if let repos = wireInt(
                account["public_repos"]) {
                bits.append(String(
                    format: L("%lld public repo(s)"), Int64(repos)))
            }
            if let followers = wireInt(
                account["followers"]) {
                bits.append(String(
                    format: L("%lld follower(s)"), Int64(followers)))
            }
            if let created = wireStr(
                account["created_at"]) {
                bits.append(String(
                    format: L("on GitHub since %@"), String(created.prefix(10))))
            }
            if !bits.isEmpty {
                icsSay(emit, "  "
                    + bits.joined(separator: " · "),
                    .ok)
            }
            if let place = wireStr(
                account["location"]) {
                icsSay(emit, String(
                    format: L("  publishes its place as: %@"), place), .out)
            }
            if let reposURL = wireURL(
                "https://api.github.com/users/"
                + name + "/repos",
                [("per_page", "100"),
                 ("sort", "pushed")]),
               let reposFetch = wireFetch(reposURL),
               let repos = wireArr(
                reposFetch.body) {
                var languages: [String: Int] = [:]
                var stars = 0
                var forks = 0
                var topName = ""
                var topStars = -1
                var freshest = ""
                for repo in repos {
                    guard let dict = wireDict(repo)
                    else { continue }
                    if let language = wireStr(
                        dict["language"]) {
                        languages[language,
                                  default: 0] += 1
                    }
                    let starCount = wireInt(
                        dict["stargazers_count"]) ?? 0
                    stars += starCount
                    forks += wireInt(
                        dict["forks_count"]) ?? 0
                    if starCount > topStars {
                        topStars = starCount
                        topName = wireStr(
                            dict["name"]) ?? ""
                    }
                    if let pushed = wireStr(
                        dict["pushed_at"]),
                       pushed > freshest {
                        freshest = pushed
                    }
                }
                let languageLine = languages
                    .sorted(by: { $0.value > $1.value })
                    .prefix(5)
                    .map { "\($0.key) × \($0.value)" }
                    .joined(separator: " · ")
                if !languageLine.isEmpty {
                    icsSay(emit, String(
                        format: L("  languages across the public repos: %@"), languageLine), .out)
                }
                icsSay(emit, String(
                    format: L("  %lld star(s), %lld fork(s) across the page read"), Int64(stars), Int64(forks)), .out)
                if !topName.isEmpty {
                    icsSay(emit, String(
                        format: L("  brightest repo: %@ (%lld star(s)) · freshest push %@"), topName, Int64(topStars), String(freshest.prefix(10))), .out)
                }
            }
            if let remaining = fetched.headers[
                "x-ratelimit-remaining"] {
                icsSay(emit, String(
                    format: L("  the keyless public allowance has %@ call(s) left in this hour — the ledger rations strangers, and the bench reads within the ration"), remaining), .out)
            }
            icsSay(emit, L("grade: a GitHub account is a published body of work — this census reads only what the account itself made public, which is the whole of what any stranger may read."))
        }
    }

    // MARK: GLEIF — the legal-entity ledger

    static func wireGLEIFProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("gleifprobe: give a company name or an LEI — gleifprobe Citibank"), .err)
                return
            }
            let cleaned = target
                .trimmingCharacters(
                    in: .whitespaces)
            var records: [[String: Any]] = []
            // An LEI is twenty characters of
            // letters and digits: the direct
            // record read. Anything else is a
            // name, and the ledger is
            // searched by it.
            let squashed = cleaned
                .replacingOccurrences(
                    of: " ", with: "")
            if squashed.count == 20,
               squashed.allSatisfy({
                   $0.isLetter || $0.isNumber
               }) {
                if let url = wireURL(
                    "https://api.gleif.org/api/v1/lei-records/"
                    + squashed.uppercased(), []),
                   let fetched = wireFetch(url),
                   fetched.status == 200,
                   let data = wireDict(
                    fetched.body),
                   let record = wireDict(
                    data["data"]) {
                    records = [record]
                }
            }
            if records.isEmpty {
                guard let url = wireURL(
                    "https://api.gleif.org/api/v1/lei-records",
                    [("filter[entity.legalName]",
                      cleaned),
                     ("page[size]", "5")]),
                      let fetched = wireFetch(url),
                      let data = wireDict(
                        fetched.body),
                      let list = wireArr(
                        data["data"])
                else {
                    icsSay(emit, L("gleifprobe: the GLEIF ledger did not answer — no reading follows."), .err)
                    return
                }
                records = list.compactMap(wireDict)
            }
            if records.isEmpty {
                icsSay(emit, String(
                    format: L("gleifprobe: no legal entity in the GLEIF ledger matches %@."), cleaned), .err)
                return
            }
            icsSay(emit, String(
                format: L("gleifprobe — the legal entities answering to %@"), cleaned), .sys)
            for record in records {
                guard let attributes = wireDict(
                    record["attributes"]),
                      let entity = wireDict(
                        attributes["entity"]),
                      let legalName = wireDict(
                        entity["legalName"]),
                      let name = wireStr(
                        legalName["name"])
                else { continue }
                let lei = wireStr(
                    record["id"]) ?? ""
                var jurisdiction = ""
                if let address = wireDict(
                    entity["legalAddress"]) {
                    jurisdiction = wireStr(
                        address["country"]) ?? ""
                }
                var status = ""
                if let registration = wireDict(
                    attributes["registration"]) {
                    status = wireStr(registration[
                        "registrationStatus"]) ?? ""
                }
                var line = "  " + name
                if !jurisdiction.isEmpty {
                    line += " (" + jurisdiction + ")"
                }
                icsSay(emit, line, .ok)
                var bits: [String] = []
                if !lei.isEmpty {
                    bits.append("LEI " + lei)
                }
                if !status.isEmpty {
                    bits.append(status)
                }
                if !bits.isEmpty {
                    icsSay(emit, "    "
                        + bits.joined(
                            separator: " · "), .out)
                }
            }
            icsSay(emit, L("grade: the LEI ledger is the financial system's answer to 'who is that, legally' — a registered name, a jurisdiction and a twenty-character identity that outlives rebrands."))
        }
    }

    // MARK: urlscan — the published scans

    static func wireURLScanProbe(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty
            else {
                icsSay(emit, L("urlscanprobe: give a domain or an IP — urlscanprobe example.com"), .err)
                return
            }
            let cleaned = target
                .trimmingCharacters(
                    in: .whitespaces)
                .lowercased()
            let query: String
            if let ip = wireIPv4(cleaned) {
                query = "ip:\"" + ip + "\""
            } else {
                var domain = cleaned
                if domain.hasPrefix("https://") {
                    domain = String(
                        domain.dropFirst(8))
                }
                if domain.hasPrefix("http://") {
                    domain = String(
                        domain.dropFirst(7))
                }
                if let slash = domain.firstIndex(
                    of: "/") {
                    domain = String(
                        domain[..<slash])
                }
                if domain.hasPrefix("www.") {
                    domain = String(
                        domain.dropFirst(4))
                }
                query = "domain:\"" + domain + "\""
            }
            guard let url = wireURL(
                "https://urlscan.io/search/",
                [("q", query)]),
                  let fetched = wireFetch(url),
                  let data = wireDict(fetched.body)
            else {
                icsSay(emit, L("urlscanprobe: urlscan did not answer — no census follows."), .err)
                return
            }
            let total = wireInt(data["total"]) ?? 0
            let results = wireArr(
                data["results"]) ?? []
            icsSay(emit, String(
                format: L("urlscanprobe — %lld published scan(s) touch %@"), Int64(total), cleaned), .sys)
            var malicious = 0
            for result in results.prefix(8) {
                guard let dict = wireDict(result),
                      let task = wireDict(
                        dict["task"])
                else { continue }
                let when = wireStr(
                    task["time"]) ?? ""
                let scanned = wireStr(
                    task["url"]) ?? ""
                var line = "  "
                    + String(when.prefix(10))
                    + " — " + scanned
                if let page = wireDict(
                    dict["page"]) {
                    var bits: [String] = []
                    if let pageIP = wireStr(
                        page["ip"]) {
                        bits.append(pageIP)
                    }
                    if let status = wireInt(
                        page["status"]) {
                        bits.append(String(
                            format: L("HTTP %lld"),
                            Int64(status)))
                    }
                    if !bits.isEmpty {
                        line += " · "
                            + bits.joined(
                                separator: " · ")
                    }
                }
                if let verdicts = wireDict(
                    dict["verdicts"]),
                   let overall = wireDict(
                    verdicts["overall"]),
                   wireBool(overall["malicious"])
                    == true {
                    malicious += 1
                    line += L(" · a verdict calls it malicious")
                }
                icsSay(emit, line, .ok)
            }
            if malicious > 0 {
                icsSay(emit, String(
                    format: L("grade: %lld of the scans read here carry a malicious verdict. urlscan's verdicts are its own engines' judgement over pages strangers submitted — evidence about the page at scan time, not a court's word about the domain today."), Int64(malicious)))
            } else {
                icsSay(emit, L("grade: urlscan is a public microscope — every scan above was submitted by somebody and published for everybody. Presence here means the address interested a stranger; the verdicts say what the microscope's engines thought of the page that day."))
            }
        }
    }

    // MARK: IPv6 — the house's second stack

    /// The class of one IPv6 address, by
    /// its text prefix — link-local,
    /// unique-local, global, loopback.
    /// Anything unrecognised is reported
    /// as other, never dressed up.
    static func wireV6Class(
        _ address: String) -> String {
        let lower = address.lowercased()
        if lower == "::1"
            || lower.hasPrefix("::1/") {
            return L("loopback")
        }
        if lower.hasPrefix("fe8")
            || lower.hasPrefix("fe9")
            || lower.hasPrefix("fea")
            || lower.hasPrefix("feb") {
            return L("link-local")
        }
        if lower.hasPrefix("fc")
            || lower.hasPrefix("fd") {
            return L("unique-local")
        }
        if lower.hasPrefix("2") {
            return L("global")
        }
        if lower.hasPrefix("ff") {
            return L("multicast")
        }
        return L("other")
    }

    static func wireV6Probe(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("v6probe — this console's own IPv6 papers, and the house resolver's two-stack answers"), .sys)
            var globalSeen: [String] = []
            var linkLocal = 0
            var uniqueLocal = 0
            for iface in BlacksiteNet
                .interfaces() {
                if iface.name == "lo0"
                    || iface.v6.isEmpty {
                    continue
                }
                for address in iface.v6 {
                    let kind = wireV6Class(address)
                    if kind == L("global") {
                        globalSeen.append(
                            iface.name + " " + address)
                    } else if kind
                        == L("link-local") {
                        linkLocal += 1
                    } else if kind
                        == L("unique-local") {
                        uniqueLocal += 1
                    }
                }
            }
            if globalSeen.isEmpty {
                icsSay(emit, L("  no global IPv6 address rides this console's interfaces — the second stack is not addressed to the world from here."))
            } else {
                for line in globalSeen.prefix(6) {
                    icsSay(emit, String(
                        format: L("  global: %@"), line), .ok)
                }
            }
            icsSay(emit, String(
                format: L("  link-local addresses: %lld · unique-local: %lld"), Int64(linkLocal), Int64(uniqueLocal)), .out)
            // The two-stack DNS read: does
            // the house resolver hand back
            // AAAA answers at all.
            let resolver = wireResolver()
            let v4 = nameQuery(
                server: resolver.ip,
                name: "example.com", type: 1)
            let v6 = nameQuery(
                server: resolver.ip,
                name: "example.com", type: 28)
            let v4Answers = v4?.answers ?? []
            let v6Answers = v6?.answers ?? []
            let aCount = v4Answers.filter {
                $0.type == 1
            }.count
            let aaaa = v6Answers.filter {
                $0.type == 28
            }
            icsSay(emit, String(
                format: L("  by way of %@: example.com draws %lld A answer(s) and %lld AAAA answer(s)"), resolver.label, Int64(aCount), Int64(aaaa.count)), .out)
            if let first = aaaa.first,
               first.raw.count == 16 {
                icsSay(emit, String(
                    format: L("  the AAAA road is open — the first answer's address ends …%@ (the full address is the resolver's answer, read from its wire bytes)"), first.raw.suffix(4).map {
                        String(format: "%02x", $0)
                    }.joined(separator: ":")), .out)
            }
            if !globalSeen.isEmpty
                && !aaaa.isEmpty {
                icsSay(emit, L("grade: the house is dual-stack in fact — a global v6 address here and AAAA answers from its resolver. IPv6 privacy extensions rotate the interface identifier on modern systems; whether THIS address rotates cannot be proven from an address list, and the bench does not claim it."))
            } else if !aaaa.isEmpty {
                icsSay(emit, L("grade: the resolver speaks both stacks but this console holds no global v6 address — the house's v6 life, if any, lives on other devices or behind the router's own delegation."))
            } else {
                icsSay(emit, L("grade: no AAAA answers came back — either the resolver filters the second stack, or this wire's DNS is v4-only today. The addresses above are the whole of the local evidence."))
            }
        }
    }

    // MARK: the census board

    /// One NBNS node-status read against
    /// one host — the incumbent nbstat's
    /// own frame (the wildcard name, type
    /// 0x0021), read down to its name
    /// table. Returns the names it wears.
    static func wireNBNSRead(
        _ ip: String) -> [String]? {
        var packet: [UInt8] = []
        let tid = UInt16.random(
            in: 1...UInt16.max)
        packet.append(UInt8(tid >> 8))
        packet.append(UInt8(tid & 0xFF))
        packet.append(contentsOf:
            [0, 0, 0, 1, 0, 0, 0, 0,
             0, 0])
        packet.append(contentsOf:
            BlacksitePentest.encodeNBName(
                "*", suffix: 0))
        packet.append(contentsOf:
            [0, 0x21, 0, 1])
        guard let reply = BlacksitePentest
            .udpExchange(ip: ip, port: 137,
                         payload: packet,
                         window: 2.5),
              reply.count > 12
        else { return nil }
        // The incumbent's walk to the
        // rdata: header, question name,
        // question fields, answer name,
        // answer fixed fields.
        var offset = 12
        func skipName() {
            guard offset < reply.count
            else { return }
            if reply[offset] & 0xC0 == 0xC0 {
                offset += 2
            } else {
                while offset < reply.count
                    && reply[offset] != 0 {
                    offset += Int(
                        reply[offset]) + 1
                }
                offset += 1
            }
        }
        skipName()
        offset += 4
        skipName()
        offset += 10
        guard offset < reply.count
        else { return nil }
        let count = Int(reply[offset])
        offset += 1
        var names: [String] = []
        for _ in 0..<count {
            guard offset + 18 <= reply.count
            else { break }
            let raw = Array(
                reply[offset..<(offset + 15)])
            let suffix = reply[offset + 15]
            offset += 18
            let name = String(
                bytes: raw, encoding: .ascii)?
                .trimmingCharacters(
                    in: .whitespaces)
                .trimmingCharacters(
                    in: .controlCharacters)
                ?? ""
            let clean = name.filter {
                !$0.unicodeScalars.contains {
                    $0.value < 32
                }
            }
            if !clean.isEmpty {
                let entry = clean + String(
                    format: "<%02X>", suffix)
                if !names.contains(entry) {
                    names.append(entry)
                }
            }
        }
        return names
    }

    /// The board: every local-link knock
    /// on one page — the deep engines at
    /// light depth, DHCP's offer read,
    /// and one host's NetBIOS papers —
    /// then the limits line the doctrine
    /// requires.
    static func wireCensus(
        _ target: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("wirecensus — the board: what this wire says about itself, in one pass"), .sys)
            icsPrint(emit,
                     wireSSDPCore(light: true))
            icsPrint(emit,
                     wireMDNSCore(light: true))
            icsPrint(emit,
                     wireWSDCore(light: true))
            icsPrint(emit,
                     wireDHCPCore().lines)
            var hostIP: String? = nil
            var hostLabel = ""
            if let target = target,
               !target.isEmpty {
                if let literal = wireIPv4(target) {
                    hostIP = literal
                    hostLabel = literal
                } else if let resolved =
                    BlacksiteNet.resolve4(target) {
                    hostIP = resolved.ip
                    hostLabel = target
                }
            }
            if hostIP == nil {
                hostIP = BlacksiteNet
                    .defaultGatewayIP()
                hostLabel = L("your router")
            }
            if let hostIP = hostIP {
                if let names = wireNBNSRead(
                    hostIP) {
                    if names.isEmpty {
                        icsSay(emit, String(
                            format: L("nbns (%@): the node-status answer carried no names"), hostLabel), .out)
                    } else {
                        icsSay(emit, String(
                            format: L("nbns (%@): %@"), hostLabel, names.joined(separator: " · ")), .ok)
                    }
                } else {
                    icsSay(emit, String(
                        format: L("nbns (%@): nothing answered on udp/137 — no NetBIOS ears there"), hostLabel), .out)
                }
            }
            icsSay(emit, L("limits: LLDP and CDP ride Layer 2, which iOS does not give an app — their testimony is unreachable from here and is not simulated. Shodan, Censys and the keyed intel clouds are never asked for credentials; their absence from this board is doctrine, not oversight."))
            icsSay(emit, L("grade: the board is the wire's own testimony about itself — who announces, who offers addresses, who keeps time's neighbours. Each deep verb reads one witness whole; the census is the room at a glance."))
        }
    }
}
