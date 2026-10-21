import Foundation
import Network
import Security

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
                connection.stateUpdateHandler = {
                    state in
                    switch state {
                    case .ready:
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
                if ready {
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
            } else if accepted.isEmpty {
                emit(L("verdict: no TLS answered at all on that door."), .err)
            } else {
                emit(String(format: L("verdict: modern locks only — %@."), String(describing: accepted.joined(separator: ", "))), .ok)
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
