import Foundation
import Network
import Security
#if os(macOS)
import CoreWLAN
#endif

// BlacksiteBench — the offensive bench
// (fix278). Website testing and wire
// probes the platform can honestly
// perform. Every engine is a single
// operator-fired run at an address the
// operator named, and each grades what
// it found in the open, in the manner
// of the audits beside them. Nothing
// here floods, guesses credentials, or
// fires autonomously.

enum BlacksiteBench {

    // MARK: shared plumbing

    /// A connected BSD stream socket, or
    /// nil. The caller closes it.
    private static func streamSocket(
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
        return fd
    }

    /// Read exactly n bytes, or nil.
    private static func readExact(
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
        return out
    }

    /// Send all bytes; false on failure.
    private static func sendAll(
        _ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer { buf in
                send(fd,
                     buf.baseAddress! + sent,
                     bytes.count - sent, 0)
            }
            guard n > 0 else { return false }
            sent += n
        }
        return true
    }

    // MARK: robots — the map the site posts

    static func robots(
        urlText: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            guard let url = BlacksitePentest
                .normalizedURL(urlText) else {
                emit(L("robots: that is not a URL."), .err)
                done()
                return
            }
            let (session, _) = BlacksitePentest
                .webSession(follow: false)
            defer {
                session.invalidateAndCancel()
            }
            func fetch(_ path: String)
                -> (Data, HTTPURLResponse)? {
                var comps = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false)
                comps?.path = path
                comps?.query = nil
                guard let target = comps?.url
                else { return nil }
                var request = URLRequest(
                    url: target)
                request.timeoutInterval = 6
                guard let (data, http) =
                    BlacksitePentest.syncFetch(
                        session, request),
                      let http = http else {
                    return nil
                }
                return (data, http)
            }
            guard let (data, http) =
                fetch("/robots.txt") else {
                emit(L("robots: the door never answered."), .err)
                done()
                return
            }
            guard http.statusCode == 200 else {
                emit(String(format: L("no robots.txt at %@ (status %@) — the site posts no map of itself."), String(describing: url.host ?? urlText), String(describing: http.statusCode)), .out)
                done()
                return
            }
            let text = String(
                data: data, encoding: .utf8) ?? ""
            var disallowed: [String] = []
            var sitemaps: [String] = []
            for raw in text.split(
                separator: "\n") {
                let line = raw.trimmingCharacters(
                    in: .whitespaces)
                let lower = line.lowercased()
                if lower.hasPrefix("disallow:") {
                    let path = line.dropFirst(
                        "disallow:".count)
                        .trimmingCharacters(
                            in: .whitespaces)
                    if !path.isEmpty {
                        disallowed.append(path)
                    }
                } else if lower.hasPrefix(
                    "sitemap:") {
                    let path = line.dropFirst(
                        "sitemap:".count)
                        .trimmingCharacters(
                            in: .whitespaces)
                    if !path.isEmpty {
                        sitemaps.append(path)
                    }
                }
            }
            emit(String(format: L("robots.txt at %@ — %@ disallowed path(s), %@ sitemap(s) named."), String(describing: url.host ?? urlText), String(describing: disallowed.count), String(describing: sitemaps.count)), .sys)
            for path in disallowed.prefix(30) {
                emit(String(format: L("kept back: %@"), String(describing: path)), .out)
            }
            if disallowed.count > 30 {
                emit(String(format: L("… and %@ more disallowed paths."), String(describing: disallowed.count - 30)), .out)
            }
            if let (mapData, mapHTTP) =
                fetch("/sitemap.xml"),
               mapHTTP.statusCode == 200 {
                let mapText = String(
                    data: mapData,
                    encoding: .utf8) ?? ""
                var locs: [String] = []
                var rest = Substring(mapText)
                while let open = rest.range(
                    of: "<loc>"),
                      let close = rest.range(
                        of: "</loc>",
                        range: open.upperBound..<rest.endIndex) {
                    let span = open.upperBound..<close.lowerBound
                    let value = rest[span]
                    locs.append(String(value))
                    rest = rest[
                        close.upperBound...]
                    if locs.count >= 30 { break }
                }
                if !locs.isEmpty {
                    emit(String(format: L("the sitemap names %@ address(es):"), String(describing: locs.count)), .sys)
                    for loc in locs {
                        emit(loc, .out)
                    }
                }
            }
            done()
        }
    }

    // MARK: vhost — who else lives at this address

    private static let vhostWords: [String] = [
        "www", "mail", "webmail", "ftp",
        "admin", "portal", "vpn", "remote",
        "api", "dev", "staging", "test",
        "beta", "old", "new", "app",
        "blog", "shop", "store", "support",
        "help", "secure", "intranet",
        "internal", "backup", "git",
        "jenkins", "cloud",
    ]

    /// One raw HTTP answer over the plain
    /// door: (status, byte count).
    private static func rawAnswer(
        ip: String, port: Int,
        hostHeader: String) -> (Int, Int)? {
        let sem = DispatchSemaphore(value: 0)
        var answer: (Int, Int)? = nil
        let request = "GET / HTTP/1.1\r\n"
            + "Host: " + hostHeader + "\r\n"
            + "User-Agent: blacksite/10.0 "
            + "(nightjar)\r\n"
            + "Connection: close\r\n\r\n"
        BlacksiteNet.tcpExchange(
            host: ip, port: port, udp: false,
            payload: request, telnet: false,
            idleSeconds: 4) { text, _ in
            defer { sem.signal() }
            guard let text = text,
                  !text.isEmpty else { return }
            let firstLine = text
                .split(separator: "\n")
                .first.map(String.init) ?? ""
            let parts = firstLine
                .split(separator: " ")
            var status = 0
            if parts.count >= 2 {
                status = Int(parts[1]) ?? 0
            }
            answer = (status,
                      text.utf8.count)
        }
        _ = sem.wait(
            timeout: .now() + 8)
        return answer
    }

    static func vhost(
        target: String, domain: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            var host = target
            var port = 80
            if let colon = target
                .lastIndex(of: ":"),
               let p = Int(target[
                    target.index(after: colon)...]),
               (1...65535).contains(p) {
                let head = target[..<colon]
                host = String(head)
                port = p
            }
            guard let resolved = BlacksiteNet
                .resolve4(host) else {
                emit(String(format: L("vhost: %@ does not resolve."), String(describing: host)), .err)
                done()
                return
            }
            let ip = resolved.ip
            emit(String(format: L("asking %@:%@ who lives there — a bogus name first, for the baseline."), String(describing: ip), String(describing: port)), .sys)
            guard let baseline = rawAnswer(
                ip: ip, port: port,
                hostHeader: "nonexistent.invalid")
            else {
                emit(L("vhost: the door never answered."), .err)
                done()
                return
            }
            emit(String(format: L("baseline — status %@, %@ bytes."), String(describing: baseline.0), String(describing: baseline.1)), .out)
            var found = 0
            for word in vhostWords {
                let name = domain.map {
                    word + "." + $0
                } ?? word
                guard let answer = rawAnswer(
                    ip: ip, port: port,
                    hostHeader: name) else {
                    continue
                }
                if answer != baseline {
                    emit(String(format: L("%@ — status %@, %@ bytes."), String(describing: name), String(describing: answer.0), String(describing: answer.1)), .ok)
                    found += 1
                }
            }
            if found == 0 {
                emit(L("every name got the baseline answer — one tenant at this address, or a door that treats all names alike."), .out)
            } else {
                emit(String(format: L("%@ name(s) answer differently — other tenants live at this address."), String(describing: found)), .sys)
            }
            done()
        }
    }
}

// MARK: - wire engines (appended section)

extension BlacksiteBench {

    // MARK: axfr — ask for the whole zone

    /// Parse one DNS message's answers
    /// with the house reader.
    private static func parseAnswers(
        _ msg: [UInt8])
        -> (rcode: Int,
            answers: [BlacksiteDNS.Answer]) {
        guard msg.count >= 12 else {
            return (0, [])
        }
        let rcode = Int(msg[3] & 0x0F)
        let qd = Int(msg[4]) << 8
            | Int(msg[5])
        let an = Int(msg[6]) << 8
            | Int(msg[7])
        var offset = 12
        for _ in 0..<qd {
            let (_, next) = BlacksiteDNS
                .readName(msg, at: offset)
            offset = next + 4
        }
        var answers: [BlacksiteDNS.Answer] = []
        for _ in 0..<an {
            let (owner, afterName) =
                BlacksiteDNS.readName(
                    msg, at: offset)
            offset = afterName
            guard offset + 10 <= msg.count
            else { break }
            let rtype = UInt16(msg[offset])
                << 8 | UInt16(msg[offset + 1])
            let ttl = UInt32(msg[offset + 4])
                << 24
                | UInt32(msg[offset + 5]) << 16
                | UInt32(msg[offset + 6]) << 8
                | UInt32(msg[offset + 7])
            let rdlen = Int(msg[offset + 8])
                << 8 | Int(msg[offset + 9])
            let rdata = offset + 10
            guard rdata + rdlen <= msg.count
            else { break }
            let raw = Array(
                msg[rdata..<(rdata + rdlen)])
            answers.append(BlacksiteDNS.Answer(
                name: owner, type: rtype,
                ttl: ttl,
                data: BlacksiteDNS.renderRdata(
                    msg, type: rtype,
                    at: rdata, raw: raw)))
            offset = rdata + rdlen
        }
        return (rcode, answers)
    }

    static func axfr(
        domain: String, server: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            guard let resolved = BlacksiteNet
                .resolve4(server) else {
                emit(String(format: L("axfr: %@ does not resolve."), String(describing: server)), .err)
                done()
                return
            }
            guard let fd = streamSocket(
                ip: resolved.ip, port: 53,
                timeout: 4) else {
                emit(String(format: L("axfr: no TCP answer from %@ — transfers ride TCP 53 and the door stayed shut."), String(describing: server)), .err)
                done()
                return
            }
            defer { close(fd) }
            emit(String(format: L("asking %@ for the whole of %@…"), String(describing: server), String(describing: domain)), .sys)
            var packet: [UInt8] = [0x4E, 0x4A,
                                    0x00, 0x00,
                                    0x00, 0x01,
                                    0x00, 0x00,
                                    0x00, 0x00,
                                    0x00, 0x00]
            packet.append(contentsOf:
                BlacksiteDNS.encodeName(domain))
            packet.append(contentsOf:
                [0x00, 0xFC, 0x00, 0x01])
            var frame: [UInt8] = [
                UInt8(packet.count >> 8),
                UInt8(packet.count & 0xFF)]
            frame.append(contentsOf: packet)
            guard sendAll(fd, frame) else {
                emit(L("axfr: the question never left."), .err)
                done()
                return
            }
            var records: [BlacksiteDNS.Answer] = []
            var soaSeen = 0
            var refusedCode: Int? = nil
            var messages = 0
            while messages < 40 {
                guard let head = readExact(
                    fd, 2) else { break }
                let length = Int(head[0]) << 8
                    | Int(head[1])
                guard length >= 12,
                      let body = readExact(
                        fd, length) else {
                    break
                }
                messages += 1
                let parsed = parseAnswers(body)
                if parsed.rcode != 0 {
                    refusedCode = parsed.rcode
                    break
                }
                for answer in parsed.answers {
                    records.append(answer)
                    if answer.type == 6 {
                        soaSeen += 1
                    }
                }
                if soaSeen >= 2 { break }
            }
            if let code = refusedCode {
                let word: String
                switch code {
                case 5: word = "REFUSED"
                case 9: word = "NOTAUTH"
                case 4: word = "NOTIMP"
                case 2: word = "SERVFAIL"
                default: word = "rcode \(code)"
                }
                emit(String(format: L("held — %@ answered %@. The zone stays home; that is the correct posture."), String(describing: server), String(describing: word)), .ok)
                done()
                return
            }
            if records.isEmpty {
                emit(L("axfr: the conversation ended with nothing handed over."), .out)
                done()
                return
            }
            for record in records.prefix(80) {
                let label = BlacksiteDNS
                    .typeNames[record.type]
                    ?? "\(record.type)"
                emit(String(format: L("%@. %@ IN %@ %@"), String(describing: record.name), String(describing: record.ttl), String(describing: label), String(describing: record.data)), .out)
            }
            if records.count > 80 {
                emit(String(format: L("… and %@ more records."), String(describing: records.count - 80)), .out)
            }
            emit(String(format: L("the zone walked out: %@ record(s) for %@, handed to anyone who asks. Critical — a full map of the house."), String(describing: records.count), String(describing: domain)), .err)
            done()
        }
    }

    // MARK: tlsgrade — which old locks still turn

    static func tlsgrade(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            var host = target
            var port = 443
            if target.contains("://") {
                if let url = BlacksitePentest
                    .normalizedURL(target),
                   let h = url.host {
                    host = h
                    if let p = url.port {
                        port = p
                    }
                }
            } else if let colon = target
                .lastIndex(of: ":"),
                      let p = Int(target[
                        target.index(
                            after: colon)...]),
                      (1...65535).contains(p) {
                host = String(target[..<colon])
                port = p
            }
            guard BlacksiteNet.resolve4(host)
                != nil else {
                emit(String(format: L("tlsgrade: %@ does not resolve."), String(describing: host)), .err)
                done()
                return
            }
            guard let nwPort = NWEndpoint.Port(
                rawValue: UInt16(port)) else {
                done()
                return
            }
            emit(String(format: L("trying each lock on %@:%@ — a version that still turns is a finding."), String(describing: host), String(describing: port)), .sys)
            let versions: [(String,
                tls_protocol_version_t)] = [
                ("TLS 1.0", .TLSv10),
                ("TLS 1.1", .TLSv11),
                ("TLS 1.2", .TLSv12),
                ("TLS 1.3", .TLSv13),
            ]
            var accepted: [String] = []
            var untestable = false
            for (label, version) in versions {
                let options = NWProtocolTLS.Options()
                sec_protocol_options_set_min_tls_protocol_version(
                    options.securityProtocolOptions,
                    version)
                sec_protocol_options_set_max_tls_protocol_version(
                    options.securityProtocolOptions,
                    version)
                sec_protocol_options_set_verify_block(
                    options.securityProtocolOptions,
                    { _, _, completion in
                        completion(true)
                    },
                    DispatchQueue(label:
                        "nightjar.tlsgrade.verify"))
                let params = NWParameters(
                    tls: options)
                let connection = NWConnection(
                    host: NWEndpoint.Host(host),
                    port: nwPort, using: params)
                let sem = DispatchSemaphore(
                    value: 0)
                var ready = false
                var negotiated: tls_protocol_version_t? = nil
                connection.stateUpdateHandler = {
                    state in
                    switch state {
                    case .ready:
                        if let meta = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata {
                            negotiated = sec_protocol_metadata_get_negotiated_tls_protocol_version(meta.securityProtocolMetadata)
                        }
                        ready = true
                        sem.signal()
                    case .failed, .cancelled:
                        sem.signal()
                    default:
                        break
                    }
                }
                connection.start(queue:
                    DispatchQueue(label:
                        "nightjar.tlsgrade"))
                _ = sem.wait(
                    timeout: .now() + 5)
                connection.cancel()
                if ready, let got = negotiated, got != version {
                    untestable = true
                    let gotLabel = versions.first(where: { $0.1 == got })?.0 ?? "?"
                    emit(String(format: L("%@ — cannot be tested from this device: its own stack negotiated %@ instead."), String(describing: label), String(describing: gotLabel)), .out)
                } else if ready {
                    accepted.append(label)
                    let old = version == .TLSv10
                        || version == .TLSv11
                    emit(String(format: L("%@ — accepted."), String(describing: label)), old ? .err : .ok)
                } else {
                    emit(String(format: L("%@ — refused."), String(describing: label)), .out)
                }
            }
            if accepted.contains("TLS 1.0")
                || accepted.contains("TLS 1.1") {
                emit(L("verdict: locks that should have been retired still turn — anything older than TLS 1.2 is a finding."), .err)
            } else if accepted.isEmpty && !untestable {
                emit(L("verdict: no TLS answered at all on that door."), .err)
            } else if !accepted.isEmpty {
                emit(String(format: L("verdict: modern locks only — %@."), String(describing: accepted.joined(separator: ", "))), .ok)
            }
            if untestable {
                emit(L("tlsgrade: this device's own TLS stack will not offer the old versions — a server's legacy locks cannot be proven from here."), .out)
            }
            done()
        }
    }

    // MARK: reflect — the amplification audit

    static func reflect(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            guard let resolved = BlacksiteNet
                .resolve4(target) else {
                emit(String(format: L("reflect: %@ does not resolve."), String(describing: target)), .err)
                done()
                return
            }
            let ip = resolved.ip
            emit(String(format: L("one packet at each old door of %@ — whatever answers loudly is a lever for strangers."), String(describing: ip)), .sys)
            var loud: [String] = []
            func probe(_ label: String,
                       port: UInt16,
                       payload: [UInt8]) -> [UInt8]? {
                let reply = BlacksitePentest
                    .udpExchange(ip: ip,
                                 port: port,
                                 payload: payload,
                                 window: 2.0)
                if let reply = reply {
                    emit(String(format: L("%@ — answers: %@ bytes back for %@ sent."), String(describing: label), String(describing: reply.count), String(describing: payload.count)), .err)
                    loud.append(label)
                } else {
                    emit(String(format: L("%@ — silent."), String(describing: label)), .out)
                }
                return reply
            }
            _ = probe("echo (7)", port: 7,
                      payload: Array(
                        "nightjar".utf8))
            _ = probe("chargen (19)", port: 19,
                      payload: [0x0A])
            _ = probe("daytime (13)", port: 13,
                      payload: [0x0A])
            var ntp: [UInt8] = [0x17, 0x00,
                                 0x03, 0x2A]
            ntp.append(contentsOf: [UInt8](
                repeating: 0, count: 44))
            _ = probe("ntp monlist (123)",
                      port: 123, payload: ntp)
            if let reply = BlacksiteDNS.query(
                server: ip, name: "example.com",
                type: 1, timeout: 2.5),
               !reply.answers.isEmpty {
                emit(L("dns (53) — answers for names it does not own: an open resolver, the loudest lever of all."), .err)
                loud.append("dns")
            } else {
                emit(L("dns (53) — no foreign answers."), .out)
            }
            if loud.isEmpty {
                emit(L("verdict: nothing at this address shouts. Quiet doors, correctly kept."), .ok)
            } else {
                emit(String(format: L("verdict: %@ door(s) answer strangers — each is reflector fuel and should be shut."), String(describing: loud.count)), .err)
            }
            done()
        }
    }

    // MARK: mqttprobe — does the broker know your name

    static func mqttprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            var host = target
            var port: UInt16 = 1883
            if let colon = target
                .lastIndex(of: ":"),
               let p = Int(target[
                    target.index(after: colon)...]),
               (1...65535).contains(p) {
                host = String(target[..<colon])
                port = UInt16(p)
            }
            guard let resolved = BlacksiteNet
                .resolve4(host) else {
                emit(String(format: L("mqttprobe: %@ does not resolve."), String(describing: host)), .err)
                done()
                return
            }
            guard let fd = streamSocket(
                ip: resolved.ip, port: port,
                timeout: 3) else {
                emit(String(format: L("mqttprobe: no answer at %@:%@."), String(describing: host), String(describing: port)), .err)
                done()
                return
            }
            defer { close(fd) }
            let built = ForgeKit.mqtt(
                clientID: "nightjar-probe")
            guard let connect = try?
                PayloadKit.build(
                    source: built.source,
                    text: built.text,
                    hex: built.text, b64: "",
                    xorSpec: "", useGzip: false),
                  !connect.isEmpty else {
                emit(L("mqttprobe: the greeting never built."), .err)
                done()
                return
            }
            guard sendAll(fd,
                          [UInt8](connect)) else {
                emit(L("mqttprobe: the greeting never left."), .err)
                done()
                return
            }
            guard let head = readExact(fd, 4),
                  head[0] == 0x20 else {
                emit(L("mqttprobe: whatever answered is not speaking MQTT."), .err)
                done()
                return
            }
            let code = Int(head[3])
            let meanings = [
                "accepted",
                "refused — protocol version",
                "refused — identifier rejected",
                "refused — server unavailable",
                "refused — bad username or password",
                "refused — not authorized",
            ]
            let meaning = (0..<meanings.count)
                .contains(code)
                ? meanings[code] : "refused"
            guard code == 0 else {
                emit(String(format: L("the broker demands a name: %@."), String(describing: meaning)), .ok)
                done()
                return
            }
            emit(L("the broker let us in unnamed — anonymous access is open."), .err)
            let subscribe: [UInt8] = [0x82, 0x06,
                                      0x00, 0x01,
                                      0x00, 0x01,
                                      0x23, 0x00]
            _ = sendAll(fd, subscribe)
            BlacksiteNet.setRecvTimeout(
                fd, seconds: 1)
            var buffer: [UInt8] = []
            var topics: [String] = []
            let deadline = Date()
                .addingTimeInterval(3.5)
            while Date() < deadline
                && topics.count < 20 {
                var chunk = [UInt8](
                    repeating: 0, count: 4096)
                let got = recv(fd, &chunk,
                               chunk.count, 0)
                if got <= 0 { continue }
                buffer.append(contentsOf:
                    chunk[0..<got])
                var cursor = 0
                while cursor + 2
                    <= buffer.count {
                    let kind = buffer[cursor]
                        & 0xF0
                    var idx = cursor + 1
                    var remaining = 0
                    var multiplier = 1
                    var lengthDone = false
                    while idx < buffer.count {
                        let byte = buffer[idx]
                        let piece = Int(byte & 0x7F)
                        remaining += piece * multiplier
                        idx += 1
                        if byte & 0x80 == 0 {
                            lengthDone = true
                            break
                        }
                        multiplier *= 128
                    }
                    guard lengthDone else {
                        break
                    }
                    let packetEnd = idx
                        + remaining
                    guard buffer.count
                        >= packetEnd else {
                        break
                    }
                    if kind == 0x30,
                       idx + 2 <= packetEnd {
                        let topicLen = Int(
                            buffer[idx]) << 8
                            | Int(buffer[idx + 1])
                        let topicStart = idx + 2
                        if topicStart + topicLen
                            <= packetEnd {
                            let span = topicStart..<(topicStart + topicLen)
                            let topic = String(
                                bytes: buffer[span],
                                encoding: .utf8)
                                ?? "?"
                            if !topics.contains(
                                topic) {
                                topics.append(
                                    topic)
                            }
                        }
                    }
                    cursor = packetEnd
                }
                if cursor > 0 {
                    buffer.removeFirst(cursor)
                }
            }
            _ = sendAll(fd, [0xE0, 0x00])
            if topics.isEmpty {
                emit(L("no topics heard in the window — the broker is open but quiet, or publishes nothing to the wildcard."), .out)
            } else {
                emit(String(format: L("%@ topic(s) heard by an unnamed guest:"), String(describing: topics.count)), .sys)
                for topic in topics {
                    emit(topic, .out)
                }
                emit(L("verdict: an open broker that talks to strangers — anything it carries, it carries publicly."), .err)
            }
            done()
        }
    }

    // MARK: dnsaudit — do the resolvers agree

    static func dnsaudit(
        domain: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            var servers: [(String, String)] = []
            if let gateway = BlacksiteNet
                .defaultGatewayIP() {
                servers.append(
                    (L("your router"), gateway))
            }
            servers.append(("Cloudflare",
                            "1.1.1.1"))
            servers.append(("Google", "8.8.8.8"))
            servers.append(("Quad9", "9.9.9.9"))
            emit(String(format: L("asking %@ resolvers where %@ lives — disagreement is the story."), String(describing: servers.count), String(describing: domain)), .sys)
            var stories: [String: [String]] = [:]
            for (label, server) in servers {
                guard let reply = BlacksiteDNS
                    .query(server: server,
                           name: domain, type: 1,
                           timeout: 3) else {
                    emit(String(format: L("%@ (%@) — no answer."), String(describing: label), String(describing: server)), .err)
                    continue
                }
                let set = Array(Set(
                    reply.answers.map {
                        $0.data
                    })).sorted()
                stories[label] = set
                if set.isEmpty {
                    emit(String(format: L("%@ (%@) — no A answers (rcode %@)."), String(describing: label), String(describing: server), String(describing: reply.rcode)), .out)
                } else {
                    emit(String(format: L("%@ (%@) — %@"), String(describing: label), String(describing: server), String(describing: set.joined(separator: ", "))), .out)
                }
            }
            let distinct = Set(stories.values
                .filter { !$0.isEmpty })
            if stories.isEmpty
                || distinct.isEmpty {
                emit(L("verdict: nobody answered — nothing to compare."), .err)
            } else if distinct.count == 1 {
                emit(L("verdict: every resolver tells the same story. The name points one way, everywhere."), .ok)
            } else {
                emit(L("verdict: the resolvers disagree — split answers, a stale cache, or a hand in the middle. Worth knowing which."), .err)
            }
            done()
        }
    }
}

extension BlacksiteBench {

    /// Wave two speaks through the house emit; a kindless call reads .out.
    private static func say(_ emit: BlacksiteEmit, _ text: String, _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }


    /// A buffered line talker for the banner protocols (FTP, SMTP).
    private final class LineTalk {
        let fd: Int32
        private var buffer: [UInt8] = []
        init(fd: Int32) { self.fd = fd }
        /// Read until a newline lands (or the peer goes quiet) and return
        /// everything read, so multi-line greetings ride whole.
        func readReply() -> String {
            var out: [UInt8] = []
            var quietRounds = 0
            while quietRounds < 2 {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let n = recv(fd, &chunk, chunk.count, 0)
                if n > 0 {
                    out.append(contentsOf: chunk[0..<n])
                    if out.contains(0x0A) { break }
                    quietRounds = 0
                } else {
                    quietRounds += 1
                }
            }
            return String(bytes: out, encoding: .utf8) ?? ""
        }
        func say(_ line: String) {
            _ = sendAll(fd, Array(line.utf8))
        }
        func code(_ reply: String) -> Int {
            let digits = reply.prefix(3)
            return Int(digits) ?? 0
        }
    }

    // MARK: corsprobe — cross-origin policy, graded

    static func corsprobe(url: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let norm = BlacksitePentest.normalizedURL(url) else {
                say(emit, L("corsprobe: give a URL — corsprobe https://example.com"), .err)
                return
            }
            let (session, _) = BlacksitePentest.webSession(follow: false)
            defer { session.invalidateAndCancel() }
            for origin in ["https://nightjar-probe.invalid", "null"] {
                var req = URLRequest(url: norm)
                req.timeoutInterval = 8
                req.setValue(origin, forHTTPHeaderField: "Origin")
                req.setValue("GET", forHTTPHeaderField: "Access-Control-Request-Method")
                guard let r = BlacksitePentest.syncFetch(session, req), let http = r.1 else {
                    say(emit, String(format: L("corsprobe: %@ — no answer."), origin))
                    continue
                }
                let acao = http.value(forHTTPHeaderField: "Access-Control-Allow-Origin") ?? ""
                let creds = (http.value(forHTTPHeaderField: "Access-Control-Allow-Credentials") ?? "").lowercased() == "true"
                if acao == origin {
                    if creds {
                        say(emit, String(format: L("corsprobe: %@ is REFLECTED and credentials are allowed — any site can read this with the visitor's session. The dangerous combination."), origin), .err)
                    } else {
                        say(emit, String(format: L("corsprobe: %@ is reflected in Access-Control-Allow-Origin — cross-origin reads are allowed for that origin."), origin), .err)
                    }
                } else if acao == "*" {
                    if creds {
                        say(emit, String(format: L("corsprobe: %@ got a wildcard WITH credentials — browsers reject the pairing, but permissive clients and tools will not."), origin), .err)
                    } else {
                        say(emit, String(format: L("corsprobe: %@ got the wildcard — the endpoint is world-readable by design or by accident."), origin))
                    }
                } else if acao.isEmpty {
                    say(emit, String(format: L("corsprobe: %@ — no Access-Control-Allow-Origin. Cross-origin reads are refused."), origin), .ok)
                } else {
                    say(emit, String(format: L("corsprobe: %@ — answered for a fixed origin: %@"), origin, acao))
                }
            }
        }
    }

    // MARK: openredirect — do the exits leave the site?

    static func openredirect(url: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let norm = BlacksitePentest.normalizedURL(url), var comps = URLComponents(url: norm, resolvingAgainstBaseURL: false) else {
                say(emit, L("openredirect: give a URL — openredirect https://example.com/login?next=/home"), .err)
                return
            }
            let marker = "https://example.org/nightjar-open"
            let (session, _) = BlacksitePentest.webSession(follow: false)
            defer { session.invalidateAndCancel() }
            var candidates: [(String, URL)] = []
            let items = comps.queryItems ?? []
            for (i, item) in items.enumerated() {
                var copy = items
                copy[i] = URLQueryItem(name: item.name, value: marker)
                comps.queryItems = copy
                if let u = comps.url { candidates.append((item.name, u)) }
            }
            if candidates.isEmpty {
                for name in ["next", "redirect", "url", "return", "returnUrl", "continue", "dest"] {
                    comps.queryItems = [URLQueryItem(name: name, value: marker)]
                    if let u = comps.url { candidates.append((name, u)) }
                }
            }
            say(emit, String(format: L("openredirect: trying %lld doors on %@"), candidates.count, norm.host ?? norm.absoluteString))
            var hits = 0
            for (name, u) in candidates.prefix(12) {
                var req = URLRequest(url: u)
                req.timeoutInterval = 8
                guard let r = BlacksitePentest.syncFetch(session, req), let http = r.1, [301, 302, 303, 307, 308].contains(http.statusCode) else { continue }
                let loc = http.value(forHTTPHeaderField: "Location") ?? ""
                if loc.hasPrefix("https://example.org") {
                    say(emit, String(format: L("openredirect: the %@ parameter walks off the site → %@ — an attacker supplies that link and the site's name vouches for it."), name, loc), .err)
                    hits += 1
                }
            }
            if hits == 0 {
                say(emit, L("openredirect: no tested parameter leaves the site."), .ok)
            }
        }
    }

    // MARK: graphqlprobe — is the schema on the door?

    static func graphqlprobe(url: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let norm = BlacksitePentest.normalizedURL(url) else {
                say(emit, L("graphqlprobe: give a URL — graphqlprobe https://example.com/graphql"), .err)
                return
            }
            var targets: [URL] = [norm]
            if norm.path.isEmpty || norm.path == "/" {
                for path in ["/graphql", "/api/graphql", "/query"] {
                    var c = URLComponents(url: norm, resolvingAgainstBaseURL: false)
                    c?.path = path
                    if let u = c?.url { targets.append(u) }
                }
            }
            let (session, _) = BlacksitePentest.webSession(follow: false)
            defer { session.invalidateAndCancel() }
            var found = false
            for target in targets {
                var req = URLRequest(url: target)
                req.httpMethod = "POST"
                req.timeoutInterval = 8
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = Data(#"{"query":"{__schema{types{name}}}"}"#.utf8)
                guard let r = BlacksitePentest.syncFetch(session, req), let http = r.1 else { continue }
                let body = String(data: r.0, encoding: .utf8) ?? ""
                if http.statusCode == 200 && (body.contains("__schema") || body.contains("\"types\"")) {
                    let count = body.components(separatedBy: "\"name\"").count - 1
                    say(emit, String(format: L("graphqlprobe: %@ hands its whole schema to strangers — introspection is ON (%lld type names counted). The API's map is public."), target.absoluteString, count), .err)
                    found = true
                    break
                }
                if body.contains("errors") || http.statusCode == 400 {
                    say(emit, String(format: L("graphqlprobe: %@ answers like a GraphQL endpoint but refused the introspection — the door exists, the map is not posted."), target.absoluteString))
                    found = true
                    break
                }
            }
            if !found { say(emit, L("graphqlprobe: no GraphQL endpoint answered at the expected doors."), .ok) }
        }
    }

    // MARK: jwtcheck — the token, read and graded (no wire)

    static func jwtcheck(token: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else {
            say(emit, L("jwtcheck: a JWT has three dotted parts — header.payload.signature."))
            return
        }
        func decode(_ s: String) -> [String: Any]? {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            guard let d = Data(base64Encoded: b),
                  let obj = try? JSONSerialization.jsonObject(with: d),
                  let dict = obj as? [String: Any] else { return nil }
            return dict
        }
        func pretty(_ dict: [String: Any]) -> String {
            let keys = dict.keys.sorted()
            return keys.map { "\($0): \(String(describing: dict[$0]!))" }.joined(separator: "  ")
        }
        guard let header = decode(parts[0]), let payload = decode(parts[1]) else {
            say(emit, L("jwtcheck: the header and payload do not decode as base64url JSON."))
            return
        }
        let alg = (header["alg"] as? String) ?? "?"
        say(emit, String(format: L("jwtcheck: alg %@ · header: %@"), alg, pretty(header)))
        say(emit, String(format: L("jwtcheck: claims: %@"), pretty(payload)))
        if alg.lowercased() == "none" {
            say(emit, L("jwtcheck: alg=none — the token is UNSIGNED by design. Any hand can rewrite its claims."), .err)
        } else if parts[2].isEmpty {
            say(emit, L("jwtcheck: the signature is EMPTY under a signing algorithm — forged on sight."), .err)
        } else if alg.hasPrefix("HS") {
            say(emit, L("jwtcheck: an HMAC algorithm — the whole strength rests on one shared secret, and anyone who can verify can also mint."), .out)
        } else {
            say(emit, String(format: L("jwtcheck: asymmetric %@ — minting needs the private key; verification is public."), alg), .ok)
        }
        let now = Int(Date().timeIntervalSince1970)
        if let exp = payload["exp"] as? NSNumber {
            let e = exp.intValue
            if e < now { say(emit, L("jwtcheck: EXPIRED — a reader that still honors it is the finding."), .err) }
            else { say(emit, String(format: L("jwtcheck: expires in %lld minutes."), (e - now) / 60)) }
        } else {
            say(emit, L("jwtcheck: no exp claim — the token never expires."), .err)
        }
        let sensitive = ["password", "secret", "ssn", "credit", "card", "cvv", "api_key", "apikey"]
        let hits = payload.keys.filter { k in sensitive.contains { k.lowercased().contains($0) } }
        if !hits.isEmpty {
            say(emit, String(format: L("jwtcheck: sensitive claims ride in cleartext for anyone holding the token: %@"), hits.joined(separator: ", ")), .err)
        }
    
        }
    }

    // MARK: proxyprobe — will it fetch for strangers?

    static func proxyprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        let halves = target.split(separator: ":").map(String.init)
        guard let hostArg = halves.first, !hostArg.isEmpty else {
            say(emit, L("proxyprobe: give host[:port] — proxyprobe 203.0.113.7:3128"))
            return
        }
        let port = halves.count > 1 ? (Int(halves[1]) ?? 8080) : 8080
        let ip = BlacksiteNet.resolve4(hostArg)?.ip ?? hostArg
        let request = "GET http://example.com/ HTTP/1.1\r\nHost: example.com\r\nUser-Agent: nightjar\r\nConnection: close\r\n\r\n"
        var reply = ""
        let sem = DispatchSemaphore(value: 0)
        BlacksiteNet.tcpExchange(host: ip, port: port, udp: false, payload: request, telnet: false, idleSeconds: 5) { text, _ in
            reply = text ?? ""
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 8)
        if reply.contains("Example Domain") {
            say(emit, L("proxyprobe: it fetched example.com for a stranger — an OPEN PROXY. The world can wear this address."), .err)
        } else if reply.hasPrefix("HTTP/") {
            let first = reply.split(separator: "\n").first.map(String.init) ?? ""
            say(emit, String(format: L("proxyprobe: it answered (%@) but did not hand back the outside page — not an open proxy for this ask."), first.trimmingCharacters(in: .whitespaces)), .ok)
        } else {
            say(emit, L("proxyprobe: nothing answered in proxy form."))
        }
    
        }
    }
}

extension BlacksiteBench {

    private static func hostPort(_ target: String, _ defaultPort: Int) -> (String, UInt16)? {
        let halves = target.split(separator: ":").map(String.init)
        guard let h = halves.first, !h.isEmpty else { return nil }
        let ip = BlacksiteNet.resolve4(h)?.ip ?? h
        let p = halves.count > 1 ? (Int(halves[1]) ?? defaultPort) : defaultPort
        return (ip, UInt16(clamping: p))
    }

    // MARK: vncprobe — the framebuffer's front door

    static func vncprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 5900) else {
            say(emit, L("vncprobe: give host[:port] — vncprobe 192.168.1.10"))
            return
        }
        guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else {
            say(emit, L("vncprobe: nothing answers on the VNC door."))
            return
        }
        defer { close(fd) }
        guard let version = readExact(fd, 12), version.count == 12 else {
            say(emit, L("vncprobe: it answered but not in RFB."))
            return
        }
        say(emit, String(format: L("vncprobe: %@"), String(bytes: version, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "RFB"))
        _ = sendAll(fd, version)
        BlacksiteNet.setRecvTimeout(fd, seconds: 3)
        var countByte = [UInt8](repeating: 0, count: 1)
        guard recv(fd, &countByte, 1, 0) == 1 else {
            say(emit, L("vncprobe: the handshake stopped after the greeting."))
            return
        }
        let n = Int(countByte[0])
        if n == 0 {
            var lenBytes = [UInt8](repeating: 0, count: 4)
            var got = 0
            while got < 4 { let r = recv(fd, &lenBytes + got, 4 - got, 0); if r <= 0 { break }; got += r }
            let len = lenBytes.reduce(0) { ($0 << 8) | Int($1) }
            var reason = ""
            if len > 0 && len < 512, let rb = readExact(fd, len) { reason = String(bytes: rb, encoding: .utf8) ?? "" }
            say(emit, String(format: L("vncprobe: the server refused the handshake — %@"), reason.isEmpty ? L("no reason given") : reason), .ok)
            return
        }
        guard let types = readExact(fd, n) else {
            say(emit, L("vncprobe: the security list never arrived."))
            return
        }
        let names: [UInt8: String] = [1: "None", 2: "VNC password", 5: "RA2", 6: "RA2ne", 16: "Tight", 19: "VeNCrypt", 18: "TLS", 17: "SASL"]
        say(emit, String(format: L("vncprobe: security types on offer: %@"), types.map { names[$0] ?? String(format: L("type %lld"), Int($0)) }.joined(separator: ", ")))
        if types.contains(1) {
            say(emit, L("vncprobe: 'None' is on the list — the framebuffer opens for anyone who asks. Critical."), .err)
        } else {
            say(emit, L("vncprobe: no empty-handed entry — every road in asks for proof."), .ok)
        }
    
        }
    }

    // MARK: rdpprobe — which dialect of RDP will it speak?

    static func rdpprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 3389) else {
            say(emit, L("rdpprobe: give host[:port] — rdpprobe 192.168.1.10"))
            return
        }
        func ask(_ protocols: UInt32) -> (Int, UInt32)? {
            guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else { return nil }
            defer { close(fd) }
            var req: [UInt8] = [0x03, 0x00, 0x00, 0x13, 0x0E, 0xE0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x08, 0x00]
            req.append(UInt8(protocols & 0xFF))
            req.append(UInt8((protocols >> 8) & 0xFF))
            req.append(UInt8((protocols >> 16) & 0xFF))
            req.append(UInt8((protocols >> 24) & 0xFF))
            guard sendAll(fd, req) else { return nil }
            guard let resp = readExact(fd, 19), resp.count == 19, resp[11] == 0x02 || resp[11] == 0x03 else { return nil }
            let b0 = UInt32(resp[15])
            let b1 = UInt32(resp[16])
            let b2 = UInt32(resp[17])
            let b3 = UInt32(resp[18])
            let value = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
            return (Int(resp[11]), value)
        }
        guard let legacy = ask(0x00000000) else {
            say(emit, L("rdpprobe: no RDP negotiation answered."))
            return
        }
        if legacy.0 == 0x02 && legacy.1 == 0 {
            say(emit, L("rdpprobe: plain legacy RDP security is ACCEPTED — the session can start with no TLS and no Network Level Authentication."), .err)
        } else if legacy.0 == 0x03 {
            say(emit, String(format: L("rdpprobe: plain RDP refused (failure %lld) — the server demands a stronger dialect."), legacy.1), .ok)
        }
        if let modern = ask(0x00000003) {
            if modern.0 == 0x02 {
                let picked = modern.1 == 1 ? "TLS" : (modern.1 == 2 ? "CredSSP (NLA)" : String(format: "protocol %lld", modern.1))
                say(emit, String(format: L("rdpprobe: offered TLS+NLA, it chose %@."), picked))
            } else if modern.0 == 0x03 && modern.1 == 5 {
                say(emit, L("rdpprobe: CredSSP is REQUIRED — Network Level Authentication stands at the door."), .ok)
            } else if modern.0 == 0x03 {
                say(emit, String(format: L("rdpprobe: the modern offer was refused (failure %lld)."), modern.1))
            }
        }
    
        }
    }

    // MARK: ftpprobe — banner, and the conventional anonymous word

    static func ftpprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 21) else {
            say(emit, L("ftpprobe: give host[:port] — ftpprobe 192.168.1.10"))
            return
        }
        guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else {
            say(emit, L("ftpprobe: nothing answers on the FTP door."))
            return
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(fd, seconds: 3)
        let talk = LineTalk(fd: fd)
        let greeting = talk.readReply()
        say(emit, String(format: L("ftpprobe: %@"), greeting.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""))
        talk.say("USER anonymous\r\n")
        let r1 = talk.readReply()
        let c1 = talk.code(r1)
        if c1 == 230 {
            say(emit, L("ftpprobe: anonymous walks straight in — no password was even asked. The archive is public."), .err)
            return
        }
        guard c1 == 331 else {
            say(emit, String(format: L("ftpprobe: the anonymous word was refused at the first step (%lld)."), c1), .ok)
            return
        }
        talk.say("PASS nightjar@probe.invalid\r\n")
        let r2 = talk.readReply()
        if talk.code(r2) == 230 {
            say(emit, L("ftpprobe: anonymous + any password OPENS the archive. Whoever keeps files here has published them."), .err)
        } else {
            say(emit, String(format: L("ftpprobe: the password step refused (%lld) — anonymous is not simply let in."), talk.code(r2)), .ok)
        }
        talk.say("QUIT\r\n")
    
        }
    }

    // MARK: smtpprobe — the mail door's manners (never sends mail)

    static func smtpprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 25) else {
            say(emit, L("smtpprobe: give host[:port] — smtpprobe 192.168.1.10"))
            return
        }
        guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else {
            say(emit, L("smtpprobe: nothing answers on the mail door."))
            return
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(fd, seconds: 3)
        let talk = LineTalk(fd: fd)
        let greeting = talk.readReply()
        say(emit, String(format: L("smtpprobe: %@"), greeting.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""))
        talk.say("EHLO nightjar.probe\r\n")
        let ehlo = talk.readReply()
        let upper = ehlo.uppercased()
        say(emit, String(format: L("smtpprobe: STARTTLS %@ · AUTH %@"), upper.contains("STARTTLS") ? L("offered") : L("absent"), upper.contains("AUTH") ? L("offered") : L("absent")))
        talk.say("VRFY root\r\n")
        let vrfy = talk.code(talk.readReply())
        if vrfy == 250 || vrfy == 252 {
            say(emit, L("smtpprobe: VRFY confirms addresses for strangers — the directory leaks who has mail here."), .err)
        } else {
            say(emit, String(format: L("smtpprobe: VRFY refused (%lld)."), vrfy), .ok)
        }
        talk.say("MAIL FROM: <probe@nightjar.invalid>\r\n")
        let mail = talk.code(talk.readReply())
        if mail == 250 {
            talk.say("RCPT TO: <relaytest@example.com>\r\n")
            let rcpt = talk.code(talk.readReply())
            if rcpt == 250 || rcpt == 251 {
                say(emit, L("smtpprobe: it ACCEPTED an outside recipient from an outside sender — an open relay posture. (Stopped before DATA; no mail was sent.)"), .err)
            } else {
                say(emit, String(format: L("smtpprobe: the outside recipient was refused (%lld) — not a relay. (No mail was sent.)"), rcpt), .ok)
            }
        } else {
            say(emit, String(format: L("smtpprobe: the outside sender was refused at MAIL FROM (%lld) — not a relay."), mail), .ok)
        }
        talk.say("QUIT\r\n")
    
        }
    }
}

extension BlacksiteBench {

    // MARK: ldapprobe — the directory's front hall (tiny BER by hand)

    private static func berLen(_ n: Int) -> [UInt8] {
        if n < 128 { return [UInt8(n)] }
        if n < 256 { return [0x81, UInt8(n)] }
        return [0x82, UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
    }
    private static func berTLV(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        [tag] + berLen(body.count) + body
    }
    private static func readBERLen(_ bytes: [UInt8], _ pos: inout Int) -> Int {
        guard pos < bytes.count else { return 0 }
        let first = bytes[pos]
        pos += 1
        if first < 0x80 { return Int(first) }
        let n = Int(first & 0x7F)
        var value = 0
        for _ in 0..<n {
            guard pos < bytes.count else { return value }
            value = (value << 8) | Int(bytes[pos])
            pos += 1
        }
        return value
    }
    private static func readMessage(_ fd: Int32) -> [UInt8]? {
        guard let tag = readExact(fd, 1), tag.count == 1, tag[0] == 0x30 else { return nil }
        guard let lb = readExact(fd, 1), lb.count == 1 else { return nil }
        var header: [UInt8] = [0x30, lb[0]]
        let len: Int
        if lb[0] < 0x80 {
            len = Int(lb[0])
        } else {
            let n = Int(lb[0] & 0x7F)
            guard n >= 1, n <= 2, let extra = readExact(fd, n), extra.count == n else { return nil }
            header += extra
            len = extra.reduce(0) { ($0 << 8) | Int($1) }
        }
        guard let body = readExact(fd, len) else { return nil }
        return header + body
    }
    private static func ldapAttr(_ entry: [UInt8], _ name: String) -> String? {
        let needle = Array(name.utf8)
        guard needle.count > 2, entry.count > needle.count else { return nil }
        var i = 0
        while i + needle.count < entry.count {
            if Array(entry[i..<(i + needle.count)]) == needle {
                var j = i + needle.count
                // After the type's own TLV comes a SET (0x31) of values.
                while j < entry.count && entry[j] != 0x31 { j += 1 }
                guard j + 2 < entry.count else { return nil }
                j += 1
                var pos = j
                _ = readBERLen(entry, &pos)
                guard pos < entry.count, entry[pos] == 0x04 else { return nil }
                pos += 1
                var vpos = pos
                let vlen = readBERLen(entry, &vpos)
                guard vpos + vlen <= entry.count else { return nil }
                return String(bytes: entry[vpos..<(vpos + vlen)], encoding: .utf8)
            }
            i += 1
        }
        return nil
    }

    static func ldapprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 389) else {
            say(emit, L("ldapprobe: give host[:port] — ldapprobe 192.168.1.10"))
            return
        }
        guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else {
            say(emit, L("ldapprobe: nothing answers on the directory door."))
            return
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(fd, seconds: 3)
        let bind: [UInt8] = [0x30, 0x0C, 0x02, 0x01, 0x01, 0x60, 0x07, 0x02, 0x01, 0x03, 0x04, 0x00, 0x80, 0x00]
        guard sendAll(fd, bind), let resp = readMessage(fd) else {
            say(emit, L("ldapprobe: the bind was never answered."))
            return
        }
        // Walk: SEQUENCE { INTEGER msgid, [APPLICATION 1] { ENUMERATED result } }
        var pos = 0
        _ = resp[pos]; pos += 1
        _ = readBERLen(resp, &pos)
        guard pos < resp.count else { return }
        _ = resp[pos]; pos += 1
        let idLen = readBERLen(resp, &pos)
        pos += idLen
        guard pos + 1 < resp.count, resp[pos] == 0x61 else {
            say(emit, L("ldapprobe: the answer was not a bind response."))
            return
        }
        pos += 1
        _ = readBERLen(resp, &pos)
        guard pos + 2 < resp.count, resp[pos] == 0x0A else { return }
        let result = resp[pos + 2]
        guard result == 0 else {
            say(emit, String(format: L("ldapprobe: anonymous bind REFUSED (result %lld) — the directory wants credentials at its door."), Int(result)), .ok)
            return
        }
        say(emit, L("ldapprobe: anonymous bind ACCEPTED — the directory lets strangers in the front hall."), .err)
        // RootDSE: base-object search, filter (objectClass=*)
        var searchBody: [UInt8] = []
        searchBody += berTLV(0x04, [])
        searchBody += berTLV(0x0A, [0x00])
        searchBody += berTLV(0x0A, [0x00])
        searchBody += berTLV(0x02, [0x00])
        searchBody += berTLV(0x02, [0x00])
        searchBody += berTLV(0x01, [0x00])
        searchBody += berTLV(0x87, Array("objectClass".utf8))
        var attrs: [UInt8] = []
        for a in ["namingContexts", "defaultNamingContext", "vendorName", "vendorVersion"] {
            attrs += berTLV(0x04, Array(a.utf8))
        }
        searchBody += berTLV(0x30, attrs)
        let search = berTLV(0x30, berTLV(0x02, [0x02]) + berTLV(0x63, searchBody))
        guard sendAll(fd, search) else { return }
        var facts: [String] = []
        for _ in 0..<3 {
            guard let msg = readMessage(fd) else { break }
            if let nc = ldapAttr(msg, "namingContexts") { facts.append(String(format: L("naming context %@"), nc)) }
            if let vn = ldapAttr(msg, "vendorName") { facts.append(String(format: L("vendor %@"), vn)) }
            if let vv = ldapAttr(msg, "vendorVersion") { facts.append(String(format: L("version %@"), vv)) }
            // The done marker (0x65 protocol op, after the header and
            // the message-id INTEGER) ends the search.
            if msg.count > 5 && msg[5] == 0x65 { break }
            if msg.count > 6 && msg[6] == 0x65 { break }
        }
        if !facts.isEmpty {
            say(emit, String(format: L("ldapprobe: the RootDSE tells strangers: %@"), facts.joined(separator: " · ")), .err)
        } else {
            say(emit, L("ldapprobe: the RootDSE read gave nothing back."))
        }
    
        }
    }

    // MARK: redisprobe — one PING

    static func redisprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
        guard let (ip, port) = hostPort(target, 6379) else {
            say(emit, L("redisprobe: give host[:port] — redisprobe 192.168.1.10"))
            return
        }
        guard let fd = streamSocket(ip: ip, port: port, timeout: 4) else {
            say(emit, L("redisprobe: nothing answers on the Redis door."))
            return
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(fd, seconds: 3)
        guard sendAll(fd, Array("PING\r\n".utf8)) else { return }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = recv(fd, &buf, buf.count, 0)
        let text = n > 0 ? (String(bytes: buf[0..<n], encoding: .utf8) ?? "") : ""
        if text.hasPrefix("+PONG") {
            say(emit, L("redisprobe: PONG with NO password asked — an unauthenticated Redis. Anyone on this wire can read and write the whole store, and its config. Critical."), .err)
            _ = sendAll(fd, Array("INFO server\r\n".utf8))
            var buf2 = [UInt8](repeating: 0, count: 8192)
            let n2 = recv(fd, &buf2, buf2.count, 0)
            if n2 > 0, let info = String(bytes: buf2[0..<n2], encoding: .utf8) {
                for line in info.split(separator: "\n") {
                    if line.hasPrefix("redis_version:") || line.hasPrefix("os:") {
                        say(emit, String(format: L("redisprobe: %@"), line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        } else if text.contains("NOAUTH") {
            say(emit, L("redisprobe: it demands authentication first — the password stands at the door."), .ok)
        } else if text.hasPrefix("-") {
            say(emit, String(format: L("redisprobe: it answered (%@) — speaking, but not simply open."), text.split(separator: "\r").first.map(String.init) ?? ""))
        } else {
            say(emit, L("redisprobe: silence — not Redis, or not awake."))
        }
    
        }
    }

    // MARK: dockerprobe — the orchestrator's API

    static func dockerprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let halves = target.split(separator: ":").map(String.init)
            guard let hostArg = halves.first, !hostArg.isEmpty else {
                say(emit, L("dockerprobe: give host[:port] — dockerprobe 192.168.1.10"), .err)
                return
            }
            let port = halves.count > 1 ? (Int(halves[1]) ?? 2375) : 2375
            guard let url = URL(string: "http://\(hostArg):\(port)/version") else { return }
            let (session, _) = BlacksitePentest.webSession(follow: false)
            defer { session.invalidateAndCancel() }
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            guard let r = BlacksitePentest.syncFetch(session, req), let http = r.1 else {
                say(emit, L("dockerprobe: nothing answered on the Docker API door."))
                return
            }
            if http.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: r.0), let dict = obj as? [String: Any],
               dict["ApiVersion"] != nil || dict["Version"] != nil {
                let ver = (dict["Version"] as? String) ?? "?"
                let api = (dict["ApiVersion"] as? String) ?? "?"
                let osName = (dict["Os"] as? String) ?? "?"
                say(emit, String(format: L("dockerprobe: the Docker API answered a STRANGER — engine %@, API %@, on %@. Unauthenticated Docker is the host itself: containers, files, everything. Critical."), ver, api, osName), .err)
            } else {
                say(emit, String(format: L("dockerprobe: door answered with %lld but not a Docker version — not an open API here."), http.statusCode), .ok)
            }
        }
    }
}

extension BlacksiteBench {
    /// Wave two's switchboard — one door in the console, twelve engines.
    static func benchTwo(_ name: String, _ target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        switch name {
        case "corsprobe": corsprobe(url: target, emit: emit, done: done)
        case "openredirect": openredirect(url: target, emit: emit, done: done)
        case "graphqlprobe": graphqlprobe(url: target, emit: emit, done: done)
        case "proxyprobe": proxyprobe(target: target, emit: emit, done: done)
        case "vncprobe": vncprobe(target: target, emit: emit, done: done)
        case "rdpprobe": rdpprobe(target: target, emit: emit, done: done)
        case "ftpprobe": ftpprobe(target: target, emit: emit, done: done)
        case "smtpprobe": smtpprobe(target: target, emit: emit, done: done)
        case "ldapprobe": ldapprobe(target: target, emit: emit, done: done)
        case "redisprobe": redisprobe(target: target, emit: emit, done: done)
        case "dockerprobe": dockerprobe(target: target, emit: emit, done: done)
        default: done()
        }
    }
}

extension BlacksiteBench {

    // MARK: eazy — the full battery behind one word

    private static let eazyDoors = [21, 22, 25, 53, 80, 443, 445, 389, 1883, 2375, 3306, 3389, 5900, 6379, 8080, 8443]

    /// A nonblocking connect with a poll deadline — a filtered door
    /// answers with silence, and silence must not stall the battery.
    private static func doorOpen(ip: String, port: Int, deadline: Double = 0.9) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var dest = BlacksiteNet.sockaddrIn(ip: ip, port: UInt16(clamping: port))
        let rc = withUnsafeMutablePointer(to: &dest) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(deadline * 1000)) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 else { return false }
        return err == 0
    }

    private static func doorScan(ip: String) -> [Int] {
        var open: [Int] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 24)
        for port in eazyDoors {
            group.enter()
            DispatchQueue.global().async {
                sem.wait()
                if doorOpen(ip: ip, port: port) {
                    lock.lock()
                    open.append(port)
                    lock.unlock()
                }
                sem.signal()
                group.leave()
            }
        }
        group.wait()
        return open.sorted()
    }

    private static func chain(_ steps: [(@escaping BlacksiteEmit, @escaping () -> Void) -> Void], _ i: Int, stopped: @escaping () -> Bool, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        if i >= steps.count || stopped() { done(); return }
        steps[i](emit) { chain(steps, i + 1, stopped: stopped, emit: emit, done: done) }
    }

    private static func probeSteps(ip: String, doors: [Int], gateway: Bool) -> [(@escaping BlacksiteEmit, @escaping () -> Void) -> Void] {
        var steps: [(@escaping BlacksiteEmit, @escaping () -> Void) -> Void] = []
        for port in doors {
            switch port {
            case 21: steps.append { e, d in ftpprobe(target: ip, emit: e, done: d) }
            case 25: steps.append { e, d in smtpprobe(target: ip, emit: e, done: d) }
            case 389: steps.append { e, d in ldapprobe(target: ip, emit: e, done: d) }
            case 1883: steps.append { e, d in mqttprobe(target: ip, emit: e, done: d) }
            case 2375: steps.append { e, d in dockerprobe(target: ip, emit: e, done: d) }
            case 3389: steps.append { e, d in rdpprobe(target: ip, emit: e, done: d) }
            case 5900: steps.append { e, d in vncprobe(target: ip, emit: e, done: d) }
            case 6379: steps.append { e, d in redisprobe(target: ip, emit: e, done: d) }
            case 80:
                steps.append { e, d in BlacksiteBench.robots(urlText: "http://\(ip)/", emit: e, done: d) }
                steps.append { e, d in BlacksitePentest.webaudit(urlText: "http://\(ip)/", emit: e, done: d) }
                steps.append { e, d in corsprobe(url: "http://\(ip)/", emit: e, done: d) }
            case 443:
                steps.append { e, d in tlsgrade(target: ip, emit: e, done: d) }
                steps.append { e, d in BlacksitePentest.webaudit(urlText: "https://\(ip)/", emit: e, done: d) }
                steps.append { e, d in corsprobe(url: "https://\(ip)/", emit: e, done: d) }
            case 8080:
                steps.append { e, d in BlacksitePentest.webaudit(urlText: "http://\(ip):8080/", emit: e, done: d) }
                steps.append { e, d in corsprobe(url: "http://\(ip):8080/", emit: e, done: d) }
            case 8443:
                steps.append { e, d in BlacksitePentest.webaudit(urlText: "https://\(ip):8443/", emit: e, done: d) }
            default:
                break
            }
        }
        if gateway {
            steps.append { e, d in BlacksitePentest.snmpAudit(host: ip, emit: e, done: d) }
            steps.append { e, d in reflect(target: ip, emit: e, done: d) }
            steps.append { e, d in dnsaudit(domain: "example.com", emit: e, done: d) }
        }
        return steps
    }

    /// The battery itself: every host gets its doors read, then the
    /// probe that belongs to each open door, in order, one at a time.
    static func eazyRun(hosts: [(ip: String, gateway: Bool)], stopped: @escaping () -> Bool, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            var queue = hosts
            func nextHost() {
                if stopped() {
                    emit(L("eazy: stopped by the operator."), .err)
                    done()
                    return
                }
                guard let host = queue.first else { done(); return }
                queue.removeFirst()
                emit(String(format: L("eazy: %@"), host.ip), .sys)
                let open = doorScan(ip: host.ip)
                if open.isEmpty {
                    say(emit, L("eazy: no doors answered — nothing to test here."))
                    nextHost()
                    return
                }
                say(emit, String(format: L("eazy: doors open: %@"), open.map { String($0) }.joined(separator: ", ")))
                let noted = open.filter { [22, 53, 445, 3306].contains($0) }
                if !noted.isEmpty {
                    say(emit, String(format: L("eazy: noted without a probe of their own: %@"), noted.map { String($0) }.joined(separator: ", ")))
                }
                chain(probeSteps(ip: host.ip, doors: open, gateway: host.gateway), 0, stopped: stopped, emit: emit) {
                    nextHost()
                }
            }
            nextHost()
        }
    }

    // MARK: eazy — an access point, named

    /// Grade a named access point from the air. On the Mac the radio
    /// can be asked (CoreWLAN); on iOS Apple offers no such census, and
    /// eazy says so rather than dressing a guess as a reading.
    static func apGrade(name: String, emit: @escaping BlacksiteEmit, done: @escaping (Bool) -> Void) {
        #if os(macOS)
        BlacksitePentest.run {
            guard let iface = CWWiFiClient.shared().interface() else {
                emit(L("eazy: this Mac shows no Wi-Fi radio."), .err)
                done(false)
                return
            }
            let joined = iface.ssid() == name
            let nets = (try? iface.scanForNetworks(withName: name)) ?? []
            guard let net = nets.first(where: { $0.ssid == name }) else {
                emit(String(format: L("eazy: no access point named '%@' is heard from here."), name), .err)
                if iface.ssid() == nil {
                    say(emit, L("eazy: the Mac may be withholding the air — Location permission governs Wi-Fi names on macOS."))
                }
                done(joined)
                return
            }
            let channel = net.wlanChannel
            let band: String
            switch channel?.channelBand {
            case .band2GHz: band = "2.4 GHz"
            case .band5GHz: band = "5 GHz"
            case .band6GHz: band = "6 GHz"
            default: band = L("band unknown")
            }
            say(emit, String(format: L("eazy: '%@' — channel %lld (%@), signal %lld dBm."), name, channel?.channelNumber ?? 0, band, net.rssiValue))
            if net.supportsSecurity(.wpa3Personal) || net.supportsSecurity(.wpa3Enterprise) || net.supportsSecurity(.wpa3Transition) {
                emit(L("eazy: WPA3 — the current standard, worn properly."), .ok)
            } else if net.supportsSecurity(.wpa2Personal) || net.supportsSecurity(.wpaPersonalMixed) || net.supportsSecurity(.wpa2Enterprise) || net.supportsSecurity(.wpaEnterprise) || net.supportsSecurity(.wpaEnterpriseMixed) {
                emit(L("eazy: WPA2 — sound, provided the password is. The air cannot judge the password."), .ok)
            } else if net.supportsSecurity(.wpaPersonal) {
                emit(L("eazy: WPA (the first) — long superseded; TKIP-era gear should be retired."), .out)
            } else if net.supportsSecurity(.WEP) || net.supportsSecurity(.dynamicWEP) {
                emit(L("eazy: WEP — a lock from another century, opened in minutes by known tools. Critical."), .err)
            } else if net.supportsSecurity(.none) {
                emit(L("eazy: it is OPEN — no password at all. Anyone may join, and everything said on it is plain. Critical."), .err)
            } else {
                emit(L("eazy: a security mode this build does not name — read it in the Wi-Fi menu."), .out)
            }
            if joined {
                say(emit, L("eazy: you are standing on it — running the full battery against its network."))
            } else {
                say(emit, L("eazy: grading from the air is all any honest tool can do from outside — to test THROUGH it, join it and run eazy again."))
            }
            done(joined)
        }
        #else
        emit(L("eazy: iOS gives no app a census of the air — other radios cannot be seen, let alone graded. Join the access point and run eazy to test the network you are standing on, or aim eazy at an address."), .err)
        done(false)
        #endif
    }
}
