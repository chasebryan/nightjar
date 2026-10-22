import Foundation

// MARK: - Bench wave 5: remote satellite systems
//
// The sky, read from the ground segment. Spacecraft buses that ride
// IP on the bench and test networks (CSP, CCSDS streams), the ground
// station's own doors (APRS-IS, KISS and AGW TNCs, hamlib rotator and
// rig control, YAMCS mission operations), navigation feeds (gpsd,
// raw NMEA, u-blox, NTRIP correction casters), modem and RF plumbing
// M&C (Comtech, BUC amplifiers, an Iridium gateway's AT door), user
// terminals (the Starlink dish's local door, SAT>IP tuners), and the
// public ledgers (Celestrak, SatNOGS) — every one read in the open
// and graded in the open.
//
// THE HARDEST LINE ON THE BENCH: this wave never transmits a
// telecommand to a spacecraft, never sends a SET or control command
// of any kind (no rotctld/rigctld position or frequency sets, no CSP
// reboot or control services, no Iridium message origination, no BUC
// transmit or mute controls), and never originates RF. Where a read
// proves that an unauthenticated control door exists, that proof IS
// the grade — the bench reports the open door; it does not walk
// through it. Every frame below was byte-verified in Python against
// its public spec before it was written in Swift; what could not be
// verified (the dish's gRPC framing, the BUC vendors' binary M&C) is
// degraded to an honest door census and says so.

extension BlacksiteBench {

    // MARK: dispatch

    static func benchSat(
        _ name: String,
        _ target: String?,
        extra: String? = nil,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        switch name {
        case "cspprobe":
            satCSPProbe(target, emit: emit, done: done)
        case "ccsdsprobe":
            satCCSDSProbe(target, emit: emit, done: done)
        case "aprsprobe":
            satAPRSProbe(target, emit: emit, done: done)
        case "kissprobe":
            satKISSProbe(target, emit: emit, done: done)
        case "agwprobe":
            satAGWProbe(target, emit: emit, done: done)
        case "rotprobe":
            satRotProbe(target, emit: emit, done: done)
        case "rigprobe":
            satRigProbe(target, emit: emit, done: done)
        case "gpsdprobe":
            satGPSDProbe(target, emit: emit, done: done)
        case "nmeaprobe":
            satNMEAProbe(target, emit: emit, done: done)
        case "ubxprobe":
            satUBXProbe(target, emit: emit, done: done)
        case "ntripprobe":
            satNTRIPProbe(target, emit: emit, done: done)
        case "comtechprobe":
            satComtechProbe(target, emit: emit, done: done)
        case "bucprobe":
            satBUCProbe(target, emit: emit, done: done)
        case "iridiumprobe":
            satIridiumProbe(target, emit: emit, done: done)
        case "starlinkprobe":
            satStarlinkProbe(target, emit: emit, done: done)
        case "satipprobe":
            satIPProbe(target, emit: emit, done: done)
        case "yamcsprobe":
            satYamcsProbe(target, emit: emit, done: done)
        case "satintel":
            satIntel(target, emit: emit, done: done)
        case "satnogsprobe":
            satNogsProbe(target, emit: emit, done: done)
        case "satcensus":
            satCensus(target, emit: emit, done: done)
        default:
            done()
        }
    }

    // MARK: plumbing (mirrors the ICS bench helpers, sat-prefixed)

    static func satSay(
        _ emit: (String, BlacksiteShell.Line.Kind) -> Void,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    static func satPrint(
        _ emit: (String, BlacksiteShell.Line.Kind) -> Void,
        _ lines: [ICSLine]) {
        for line in lines { emit(line.text, line.kind) }
    }

    static func satResolve(
        _ target: String?,
        _ defaultPort: Int)
        -> (host: String, ip: String, port: Int)? {
        guard var host = target, !host.isEmpty else { return nil }
        var port = defaultPort
        if let colon = host.lastIndex(of: ":") {
            let tail = host[host.index(after: colon)...]
            if let p = Int(tail), p > 0, p < 65536 {
                port = p
                host = String(host[..<colon])
            }
        }
        guard let resolved = BlacksiteNet.resolve4(host) else { return nil }
        return (host, resolved.ip, port)
    }

    static func satSocket(_ ip: String, _ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var addr = BlacksiteNet.sockaddrIn(
            ip: ip, port: UInt16(clamping: port))
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 { close(fd); return -1 }
        BetafischTap.shared.noteConnect(
            fd: fd, ip: ip, port: port, udp: false)
        return fd
    }

    static func satSendAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer { buffer in
                send(fd, buffer.baseAddress! + sent,
                     bytes.count - sent, 0)
            }
            if n <= 0 { return false }
            sent += n
        }
        BetafischTap.shared.record(
            fd: fd, outbound: true, bytes: bytes)
        return true
    }

    /// Read whatever arrives inside the window; the socket is left
    /// open. Returns the raw bytes (possibly empty).
    static func satReadWindow(
        _ fd: Int32, seconds: Double, cap: Int = 262144) -> [UInt8] {
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 0.25)
        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && out.count < cap {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 { out.append(contentsOf: buf[0..<n]) }
            else if n == 0 { break }
        }
        BetafischTap.shared.record(
            fd: fd, outbound: false, bytes: out)
        return out
    }

    static func satText(_ bytes: [UInt8]) -> String {
        icsClean(bytes[...])
    }

    static func satLines(_ bytes: [UInt8]) -> [String] {
        satText(bytes)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func satUDPSocket(_ ip: String, _ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return -1 }
        var addr = BlacksiteNet.sockaddrIn(
            ip: ip, port: UInt16(clamping: port))
        let rc = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 { close(fd); return -1 }
        BetafischTap.shared.noteConnect(
            fd: fd, ip: ip, port: port, udp: true)
        return fd
    }

    static func satUDPSend(_ fd: Int32, _ bytes: [UInt8]) {
        _ = bytes.withUnsafeBufferPointer { buffer in
            send(fd, buffer.baseAddress!, bytes.count, 0)
        }
        BetafischTap.shared.record(
            fd: fd, outbound: true, bytes: bytes)
    }

    /// Collect datagrams until the deadline; sends nothing itself.
    static func satUDPReadAll(
        _ fd: Int32, seconds: Double, cap: Int = 256) -> [[UInt8]] {
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 0.25)
        var out: [[UInt8]] = []
        var buf = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && out.count < cap {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 { out.append(Array(buf[0..<n])) }
        }
        for datagram in out {
            BetafischTap.shared.record(
                fd: fd, outbound: false,
                bytes: datagram)
        }
        return out
    }

    static func satFetch(
        _ url: URL, accept: String? = nil)
        -> (status: Int, body: String, headers: [String: String])? {
        guard let (data, response) = icsFetch(url, accept: accept)
        else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            headers[String(describing: key).lowercased()] =
                String(describing: value)
        }
        return (response.statusCode,
                String(decoding: data, as: UTF8.self), headers)
    }

    static func satJSON(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func satU32LE(_ b: [UInt8], _ at: Int) -> Int {
        guard at + 3 < b.count else { return 0 }
        return Int(b[at]) | (Int(b[at + 1]) << 8)
            | (Int(b[at + 2]) << 16) | (Int(b[at + 3]) << 24)
    }

    /// One shifted AX.25 address field (7 bytes) as CALL-SSID text.
    static func satAXCall(_ b: [UInt8], _ at: Int) -> String {
        guard at + 6 < b.count else { return "" }
        var call = ""
        for i in 0..<6 {
            let c = b[at + i] >> 1
            if c > 32 && c < 127 {
                call += String(UnicodeScalar(c))
            }
        }
        let ssid = (b[at + 6] >> 1) & 0x0F
        let trimmed = call.trimmingCharacters(in: .whitespaces)
        return ssid > 0 ? "\(trimmed)-\(ssid)" : trimmed
    }

    // MARK: - spacecraft buses

    /// libcsp over UDP: the CMP IDENT request and a ping. libCSP v1
    /// header word (big-endian): pri 31-30, source 29-25, dest 24-20,
    /// dest port 19-14, source port 13-8, flags 7-0. CMP lives on
    /// port 0, command 1 is IDENT; ping is port 1; uptime port 6 and
    /// buffer-free port 5 are reads. Port 4 (reboot) does not exist
    /// as far as this bench is concerned.
    static func satCSPCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        func header(_ dport: UInt32) -> [UInt8] {
            let w: UInt32 = (20 << 25) | (dport << 14) | (17 << 8)
            return [UInt8((w >> 24) & 0xFF), UInt8((w >> 16) & 0xFF),
                    UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF)]
        }
        func sport(of packet: [UInt8]) -> Int {
            guard packet.count >= 4 else { return -1 }
            let w = icsU32BE(packet, 0)
            return Int((w >> 8) & 0x3F)
        }
        let fd = satUDPSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("cspprobe — no route to %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        var identPacket = header(0)
        identPacket.append(1)
        satUDPSend(fd, identPacket)
        let first = satUDPReadAll(fd, seconds: 1.4, cap: 8)
        satUDPSend(fd, header(6))
        satUDPSend(fd, header(5))
        satUDPSend(fd, header(1))
        let second = satUDPReadAll(fd, seconds: 1.4, cap: 8)
        let replies = first + second
        if replies.isEmpty {
            return light ? [] : [(
                String(format: L("cspprobe — nothing answered on UDP %lld at %@ — no CSP node here, or the bus is not IP-carried on this network"),
                       Int64(port), ip), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("cspprobe — %@:%lld speaks CSP"),
                   ip, Int64(port)), .sys)]
        var named = false
        for packet in replies where sport(of: packet) == 0 {
            let body = Array(packet.dropFirst(4))
            guard body.count >= 64 else { continue }
            let host = icsClean(body[0..<32])
                .trimmingCharacters(in: .whitespaces)
            let model = icsClean(body[32..<64])
                .trimmingCharacters(in: .whitespaces)
            var tail: [String] = []
            for field in body[64...].split(separator: 0) {
                let s = icsClean(field)
                    .trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { tail.append(s) }
            }
            lines.append((
                String(format: L("hostname %@ · model %@"),
                       host.isEmpty ? "—" : host,
                       model.isEmpty ? "—" : model), .out))
            if tail.count > 0 {
                lines.append((
                    String(format: L("revision %@"),
                           tail[0]), .out))
            }
            if tail.count > 1 {
                lines.append((
                    String(format: L("built %@ %@"),
                           tail[1],
                           tail.count > 2 ? tail[2] : ""), .out))
            }
            named = true
        }
        for packet in replies where sport(of: packet) == 6 {
            let body = Array(packet.dropFirst(4))
            if body.count >= 4 {
                lines.append((
                    String(format: L("uptime %lld s"),
                           Int64(icsU32BE(body, 0))), .out))
            }
        }
        for packet in replies where sport(of: packet) == 5 {
            let body = Array(packet.dropFirst(4))
            if body.count >= 4 {
                lines.append((
                    String(format: L("buffer free %lld bytes"),
                           Int64(icsU32BE(body, 0))), .out))
            }
        }
        let pinged = replies.contains { sport(of: $0) == 1 }
        if pinged {
            lines.append((L("the node answers a CSP ping"), .out))
        }
        lines.append((named
            ? L("grade: a spacecraft bus that introduces itself to any caller. CSP v1 has no built-in authentication — fly the mission network like it is hostile, because at this door it is")
            : L("grade: something on this door answers CSP-shaped packets but would not identify — noted, not named"), .err))
        lines.append((L("read: CMP IDENT + uptime + buffer-free + ping. The reboot and control services were not touched — this bench never sends a telecommand"), .out))
        return lines
    }

    static func satCSPProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 9999) else {
                satSay(emit, L("cspprobe: give host[:port] — cspprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satCSPCore(ip, port, light: false))
        }
    }

    /// A CCSDS stream tap: the bench sends NOTHING and counts the
    /// space packets going by on a monitor feed — APIDs, telemetry
    /// vs telecommand, sequence gaps. Space Packet primary header:
    /// version(3) type(1) secondary(1) APID(11), grouping(2)
    /// count(14), length(16, data zone minus one).
    static func satCCSDSCore(
        _ ip: String, _ port: Int, udp: Bool,
        light: Bool) -> [ICSLine] {
        var packets: [[UInt8]] = []
        if udp {
            let fd = satUDPSocket(ip, port)
            guard fd >= 0 else { return [] }
            defer { close(fd) }
            packets = satUDPReadAll(fd, seconds: 2.5, cap: 400)
        } else {
            let fd = satSocket(ip, port)
            guard fd >= 0 else { return [] }
            defer { close(fd) }
            let raw = satReadWindow(fd, seconds: 2.5, cap: 1048576)
            var i = 0
            while i + 6 <= raw.count {
                let length = Int(icsU16BE(raw, i + 4)) + 1
                if length <= 0 || i + 6 + length > raw.count { break }
                packets.append(Array(raw[i..<(i + 6 + length)]))
                i += 6 + length
            }
        }
        if packets.isEmpty {
            return light ? [] : [(
                String(format: L("ccsdsprobe — silence on %@:%lld for the whole window — no stream here, or the feed runs elsewhere"),
                       ip, Int64(port)), .out)]
        }
        var tm = 0, tc = 0, other = 0
        var perAPID: [Int: Int] = [:]
        var lastSeq: [Int: Int] = [:]
        var gaps = 0
        for packet in packets where packet.count >= 6 {
            let w0 = icsU16BE(packet, 0)
            let w1 = icsU16BE(packet, 2)
            if (w0 >> 13) != 0 { other += 1; continue }
            let isTC = (w0 >> 11) & 1 == 0
            let apid = w0 & 0x7FF
            if isTC { tc += 1 } else { tm += 1 }
            perAPID[apid, default: 0] += 1
            let flags = (w1 >> 14) & 3
            let seq = w1 & 0x3FFF
            if flags == 3, let last = lastSeq[apid],
               seq != (last + 1) & 0x3FFF {
                gaps += 1
            }
            if flags == 3 || flags == 1 { lastSeq[apid] = seq }
        }
        var lines: [ICSLine] = [(
            String(format: L("ccsdsprobe — %lld space packets on %@:%lld"),
                   Int64(packets.count), ip, Int64(port)), .sys),
            (String(format: L("telemetry %lld · telecommand-shaped %lld · non-CCSDS %lld"),
                     Int64(tm), Int64(tc), Int64(other)), .out)]
        let top = perAPID.sorted { $0.value > $1.value }.prefix(6)
        if !top.isEmpty {
            let named = top.map {
                String(format: L("APID %lld × %lld"),
                       Int64($0.key), Int64($0.value))
            }.joined(separator: " · ")
            lines.append((
                String(format: L("busiest: %@"), named), .out))
        }
        if gaps > 0 {
            lines.append((
                String(format: L("sequence gaps on %lld packet(s) — loss on the feed, or a second source on the same APID"),
                       Int64(gaps)), .out))
        }
        lines.append((L("grade: the mission stream readable in the clear to anyone on this wire. CCSDS space packets are unauthenticated by design — the encryption belongs on the link (SDLS), and nothing here shows it"), .err))
        lines.append((L("listen-only: nothing was transmitted. This is a census of a monitor feed, never a command path"), .out))
        return lines
    }

    static func satCCSDSProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 9998) else {
                satSay(emit, L("ccsdsprobe: give host[:port] — ccsdsprobe 192.168.1.60"), .err)
                return
            }
            var lines = satCCSDSCore(ip, port, udp: true, light: true)
            if lines.isEmpty {
                lines = satCCSDSCore(ip, port, udp: false, light: false)
            }
            satPrint(emit, lines)
        }
    }

    // MARK: - ground station doors

    /// APRS-IS, entered the only way this bench ever enters: the
    /// read-only login (passcode -1). The feed can be heard worldwide
    /// and never spoken into. A local feed address works the same
    /// way; a dumb monitor stream simply ignores the login line.
    static func satAPRSCore(
        _ ip: String, _ port: Int, host: String,
        light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("aprsprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        let greeting = satLines(satReadWindow(fd, seconds: 1.2,
                                              cap: 65536))
        _ = satSendAll(fd, Array(
            "user N0CALL pass -1 vers nightjar 11.0 filter b/*\r\n"
                .utf8))
        let heard = satLines(satReadWindow(
            fd, seconds: light ? 2.0 : 6.0, cap: 1048576))
        var packets: [(src: String, path: String, info: String)] = []
        for line in heard {
            guard let gt = line.firstIndex(of: ">"),
                  let colon = line.firstIndex(of: ":"),
                  gt < colon else { continue }
            packets.append((
                String(line[..<gt]),
                String(line[line.index(after: gt)..<colon]),
                String(line[line.index(after: colon)...])))
        }
        if packets.isEmpty {
            return light ? [] : [(
                String(format: L("aprsprobe — connected to %@:%lld but no APRS traffic crossed in the window — a quiet feed, or a door that is not APRS"),
                       ip, Int64(port)), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("aprsprobe — %@:%lld"),
                   ip, Int64(port)), .sys)]
        if let g = greeting.first(where: { $0.hasPrefix("#") }) {
            lines.append((
                String(format: L("server says: %@"),
                       String(g.prefix(90))), .out))
        }
        var tally: [String: Int] = [:]
        for p in packets { tally[p.src, default: 0] += 1 }
        let top = tally.sorted { $0.value > $1.value }.prefix(5)
        lines.append((
            String(format: L("%lld packet(s) heard from %lld station(s)"),
                   Int64(packets.count), Int64(tally.count)), .out))
        if !top.isEmpty {
            lines.append((
                String(format: L("loudest: %@"),
                       top.map { "\($0.key) × \($0.value)" }
                           .joined(separator: " · ")), .out))
        }
        if let p = packets.first {
            lines.append((
                String(format: L("sample: %@>%@:%@"),
                       p.src, p.path,
                       String(p.info.prefix(48))), .out))
        }
        lines.append((L("grade: heard through the read-only login (passcode -1) — this door can listen to the worldwide APRS stream and can never speak into it from here. That asymmetry is the design working"), .ok))
        lines.append((L("read-only: no packet was originated, digipeated or gated — the bench listens at this door, nothing more"), .out))
        return lines
    }

    static func satAPRSProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let goal = target ?? "rotate.aprs.net"
            guard let (host, ip, port) = satResolve(goal, 14580) else {
                satSay(emit, L("aprsprobe: give host[:port] — aprsprobe rotate.aprs.net"), .err)
                return
            }
            _ = host
            satPrint(emit, satAPRSCore(ip, port, host: host,
                                       light: false))
        }
    }

    /// A KISS TNC, heard only. The bench connects and listens to the
    /// frame stream — it sends no frame of any kind, and in
    /// particular never a parameter frame (TX delay, persistence,
    /// slot time, full-duplex, set-hardware): those are writes to the
    /// radio's behavior. KISS framing: FEND-delimited, command byte
    /// low nibble 0x0 is a data frame carrying raw AX.25.
    static func satKISSCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("kissprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        let raw = satReadWindow(fd, seconds: light ? 1.5 : 5.0,
                                cap: 1048576)
        var dataFrames = 0, paramFrames = 0
        var heard: [String] = []
        var current: [UInt8] = []
        var escaped = false
        var frames: [[UInt8]] = []
        for byte in raw {
            if escaped {
                current.append(byte == 0xDC ? 0xC0 : 0xDB)
                escaped = false
            } else if byte == 0xDB {
                escaped = true
            } else if byte == 0xC0 {
                if !current.isEmpty { frames.append(current) }
                current = []
            } else {
                current.append(byte)
            }
        }
        for frame in frames {
            guard let cmd = frame.first else { continue }
            let kind = cmd & 0x0F
            if kind == 0x00 {
                dataFrames += 1
                let ax = Array(frame.dropFirst())
                if ax.count >= 15, heard.count < 5 {
                    let dst = satAXCall(ax, 0)
                    let src = satAXCall(ax, 7)
                    if !src.isEmpty {
                        heard.append("\(src)>\(dst)")
                    }
                }
            } else if kind != 0x0F {
                paramFrames += 1
            }
        }
        if dataFrames == 0 && paramFrames == 0 {
            return light ? [] : [(
                String(format: L("kissprobe — connected to %@:%lld; silence in the window — a listening TNC, or a quiet band"),
                       ip, Int64(port)), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("kissprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("%lld AX.25 data frame(s) carried past"),
                     Int64(dataFrames)), .out)]
        if !heard.isEmpty {
            lines.append((
                String(format: L("heard: %@"),
                       heard.joined(separator: " · ")), .out))
        }
        if paramFrames > 0 {
            lines.append((
                String(format: L("%lld parameter frame(s) seen — someone configures this TNC over the wire"),
                       Int64(paramFrames)), .out))
        }
        lines.append((L("grade: KISS carries raw AX.25 with no authentication — any host that can reach this port can put packets on the air through that radio. The bench only listened; that reachability is the finding"), .err))
        lines.append((L("listen-only: no frame was sent — no data, and no parameter writes of any kind"), .out))
        return lines
    }

    static func satKISSProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 8001) else {
                satSay(emit, L("kissprobe: give host[:port] — kissprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satKISSCore(ip, port, light: false))
        }
    }

    /// An AGW packet engine (AGWPE / Dire Wolf), read with its own
    /// housekeeping frames: 'R' asks the version, 'G' asks the port
    /// list, 'm' turns on the monitor feed. The 36-byte header is
    /// laid out port(1) reserved(3) kind(1) reserved(2) PID(1)
    /// callfrom(10) callto(10) data-length LE(4) user(4) — the size
    /// Dire Wolf's own source insists on. Transmit frames ('t', 'T',
    /// 'X' registration for sending) are never built.
    static func satAGWFrame(
        _ kind: UInt8, _ data: [UInt8] = []) -> [UInt8] {
        var frame = [UInt8](repeating: 0, count: 36)
        frame[4] = kind
        frame[7] = 0xF0
        frame[28] = UInt8(data.count & 0xFF)
        frame[29] = UInt8((data.count >> 8) & 0xFF)
        frame[30] = UInt8((data.count >> 16) & 0xFF)
        frame[31] = UInt8((data.count >> 24) & 0xFF)
        frame.append(contentsOf: data)
        return frame
    }

    static func satAGWRead(
        _ fd: Int32, seconds: Double)
        -> (kind: UInt8, data: [UInt8])? {
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 0.25)
        var buf: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if buf.count >= 36 {
                let length = satU32LE(buf, 28)
                if length >= 0 && length < 1048576
                    && buf.count >= 36 + length {
                    return (buf[4], Array(buf[36..<(36 + length)]))
                }
            }
            let n = recv(fd, &chunk, chunk.count, 0)
            if n > 0 { buf.append(contentsOf: chunk[0..<n]) }
            else if n == 0 { return nil }
        }
        return nil
    }

    static func satAGWCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("agwprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        guard satSendAll(fd, satAGWFrame(0x52)) else {  // 'R'
            return light ? [] : [(
                String(format: L("agwprobe — %@:%lld took the connection and dropped it"),
                       ip, Int64(port)), .err)]
        }
        guard let version = satAGWRead(fd, seconds: 2.5),
              version.kind == 0x52, version.data.count >= 8 else {
            let banner = satText(satReadWindow(fd, seconds: 0.8,
                                               cap: 8192))
            if light { return [] }
            var lines: [ICSLine] = [(
                String(format: L("agwprobe — %@:%lld answers TCP but not AGW — noted, not named"),
                       ip, Int64(port)), .sys)]
            if !banner.isEmpty {
                lines.append((
                    String(format: L("banner: %@"),
                           String(banner.prefix(90))), .out))
            }
            return lines
        }
        var lines: [ICSLine] = [(
            String(format: L("agwprobe — %@:%lld runs an AGW engine"),
                   ip, Int64(port)), .sys),
            (String(format: L("engine version %lld.%lld"),
                     Int64(satU32LE(version.data, 0)),
                     Int64(satU32LE(version.data, 4))), .out)]
        if satSendAll(fd, satAGWFrame(0x47)) {  // 'G'
            if let ports = satAGWRead(fd, seconds: 2.0),
               ports.kind == 0x47 {
                let text = satText(ports.data)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    lines.append((
                        String(format: L("ports: %@"),
                               String(text.prefix(140))), .out))
                }
            }
        }
        if !light, satSendAll(fd, satAGWFrame(0x6D)) {  // 'm'
            var heard = 0
            var stations = Set<String>()
            let deadline = Date().addingTimeInterval(2.5)
            while Date() < deadline && heard < 40 {
                guard let frame = satAGWRead(fd, seconds: 0.6)
                else { break }
                if frame.kind == 0x55 {  // 'U' — a heard UI frame
                    heard += 1
                    if frame.data.count >= 15 {
                        let src = satAXCall(frame.data, 7)
                        if !src.isEmpty { stations.insert(src) }
                    }
                }
            }
            if heard > 0 {
                lines.append((
                    String(format: L("monitor heard %lld frame(s) from %lld station(s)"),
                           Int64(heard), Int64(stations.count)), .out))
            }
        }
        lines.append((L("grade: an AGW engine hands the radio to any TCP caller — version and ports are housekeeping anyone may read, and the same door carries transmit frames for whoever asks. Reachable here, unauthenticated"), .err))
        lines.append((L("read: version + ports + the monitor feed. No transmit frame was built and no callsign was registered"), .out))
        return lines
    }

    static func satAGWProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 8000) else {
                satSay(emit, L("agwprobe: give host[:port] — agwprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satAGWCore(ip, port, light: false))
        }
    }

    /// hamlib's rotctld, read with the two questions that move
    /// nothing: `p` (where is it pointing?) and `\dump_state` (what
    /// is it?). The set commands (`P`, and the long `\set_position`)
    /// are never sent — a rotator that takes orders from any caller
    /// is graded on that door, not used through it.
    static func satRotCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("rotprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        guard satSendAll(fd, Array("p\n".utf8)) else {
            return light ? [] : []
        }
        let posLines = satLines(satReadWindow(fd, seconds: 1.6,
                                              cap: 65536))
        var numbers: [Double] = []
        for line in posLines {
            let cleaned = line
                .replacingOccurrences(of: "Azimuth:", with: "")
                .replacingOccurrences(of: "Elevation:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let v = Double(cleaned) { numbers.append(v) }
            if numbers.count >= 2 { break }
        }
        guard numbers.count >= 2 else {
            return light ? [] : [(
                String(format: L("rotprobe — %@:%lld answers but not like rotctld — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("rotprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("pointing at azimuth %.1f° · elevation %.1f°"),
                     numbers[0], numbers[1]), .out)]
        if satSendAll(fd, Array("\\dump_state\n".utf8)) {
            let state = satLines(satReadWindow(fd, seconds: 1.6,
                                               cap: 65536))
            if state.count >= 3 {
                let az = state[1].split(separator: " ")
                    .compactMap { Double($0) }
                let el = state[2].split(separator: " ")
                    .compactMap { Double($0) }
                if az.count == 2 && el.count == 2 {
                    lines.append((
                        String(format: L("rotator range: azimuth %.0f° to %.0f° · elevation %.0f° to %.0f°"),
                               az[0], az[1], el[0], el[1]), .out))
                }
                lines.append((
                    String(format: L("rotctld protocol version %@"),
                           state[0]), .out))
            }
        }
        lines.append((L("grade: this rotator reports its pointing to any caller — and the same door takes positioning orders with no login. The reads prove the door; the bench never sends a position"), .err))
        lines.append((L("read: get_pos + dump_state only. set_pos was not sent and never is"), .out))
        return lines
    }

    static func satRotProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 4533) else {
                satSay(emit, L("rotprobe: give host[:port] — rotprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satRotCore(ip, port, light: false))
        }
    }

    /// hamlib's rigctld, the rotator's sibling: `f` reads the
    /// frequency, `m` the mode and passband, `\dump_state` the
    /// capabilities. `F` and `M` — the sets — are never sent.
    static func satRigCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("rigprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        guard satSendAll(fd, Array("f\n".utf8)) else {
            return light ? [] : []
        }
        let freqLines = satLines(satReadWindow(fd, seconds: 1.6,
                                               cap: 65536))
        guard let first = freqLines.first,
              let hz = Int(first.trimmingCharacters(in: .whitespaces)),
              hz > 0 else {
            return light ? [] : [(
                String(format: L("rigprobe — %@:%lld answers but not like rigctld — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("rigprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("tuned to %lld Hz — %.4f MHz"),
                     Int64(hz), Double(hz) / 1_000_000.0), .out)]
        if satSendAll(fd, Array("m\n".utf8)) {
            let mode = satLines(satReadWindow(fd, seconds: 1.6,
                                              cap: 65536))
            if let name = mode.first {
                var text = String(format: L("mode %@"), name)
                if mode.count > 1, let pb = Int(mode[1]) {
                    text += String(format: L(" · passband %lld Hz"),
                                   Int64(pb))
                }
                lines.append((text, .out))
            }
        }
        if satSendAll(fd, Array("\\dump_state\n".utf8)) {
            let state = satLines(satReadWindow(fd, seconds: 1.6,
                                               cap: 65536))
            if let v = state.first {
                lines.append((
                    String(format: L("rigctld protocol version %@"),
                           v), .out))
            }
        }
        lines.append((L("grade: this rig reports its tuning to any caller — and the same door takes tuning orders with no login. The reads prove the door; the bench never sends a frequency or a mode"), .err))
        lines.append((L("read: get_freq + get_mode + dump_state only. Nothing was set, and no transmission was keyed"), .out))
        return lines
    }

    static func satRigProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 4532) else {
                satSay(emit, L("rigprobe: give host[:port] — rigprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satRigCore(ip, port, light: false))
        }
    }

    /// gpsd, asked its two housekeeping questions: ?VERSION and
    /// ?DEVICES. The bench never sends ?WATCH — it does not ask the
    /// daemon to stream fixes, and a position is never collected or
    /// printed by anything in this wave.
    static func satGPSDCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("gpsdprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        guard satSendAll(fd, Array("?VERSION\n".utf8)) else {
            return light ? [] : []
        }
        let vText = satText(satReadWindow(fd, seconds: 1.8,
                                          cap: 65536))
        guard let parsed = satJSON(vText),
              let version = parsed as? [String: Any],
              (version["class"] as? String) == "VERSION" else {
            return light ? [] : [(
                String(format: L("gpsdprobe — %@:%lld answers but not like gpsd — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("gpsdprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("gpsd release %@ · protocol %lld.%lld"),
                     version["release"] as? String ?? "—",
                     Int64((version["proto_major"] as? NSNumber)?
                        .intValue ?? 0),
                     Int64((version["proto_minor"] as? NSNumber)?
                        .intValue ?? 0)), .out)]
        if satSendAll(fd, Array("?DEVICES\n".utf8)) {
            let dText = satText(satReadWindow(fd, seconds: 1.8,
                                              cap: 65536))
            if let parsed = satJSON(dText),
               let root = parsed as? [String: Any],
               let devices = root["devices"] as? [[String: Any]] {
                for device in devices.prefix(6) {
                    let path = device["path"] as? String ?? "—"
                    let driver = device["driver"] as? String ?? "—"
                    lines.append((
                        String(format: L("device %@ · driver %@"),
                               path, driver), .out))
                }
                if devices.isEmpty {
                    lines.append((L("no receiver is attached right now"), .out))
                }
            }
        }
        lines.append((L("grade: gpsd serves the sky to any local caller by design — the posture question is whether this door faces the LAN or only the host. Reachable here; whether it should be is the operator's call"), .err))
        lines.append((L("read: ?VERSION + ?DEVICES. No ?WATCH was sent — no fix was streamed, collected or printed"), .out))
        return lines
    }

    static func satGPSDProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 2947) else {
                satSay(emit, L("gpsdprobe: give host[:port] — gpsdprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satGPSDCore(ip, port, light: false))
        }
    }

    /// A raw NMEA 0183 stream, censused: sentence shapes counted,
    /// checksums verified, the sky view (GSV) tallied. Positions
    /// are never printed — fix quality and satellite counts are the
    /// grade, not coordinates.
    static func satNMEACore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        var bytes: [UInt8] = []
        let fd = satSocket(ip, port)
        if fd >= 0 {
            bytes = satReadWindow(fd, seconds: light ? 1.5 : 5.0,
                                  cap: 1048576)
            close(fd)
        }
        if bytes.isEmpty {
            let ufd = satUDPSocket(ip, port)
            if ufd >= 0 {
                for packet in satUDPReadAll(
                    ufd, seconds: light ? 1.5 : 4.0, cap: 200) {
                    bytes.append(contentsOf: packet)
                }
                close(ufd)
            }
        }
        let text = satText(bytes)
        var counts: [String: Int] = [:]
        var badChecksum = 0, sentences = 0
        var skySats = 0, ggaSats = -1, fixQuality = -1
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard line.hasPrefix("$"), line.count >= 6 else { continue }
            sentences += 1
            let body = String(line.dropFirst())
            let type = String(body.dropFirst(2).prefix(3))
            counts[type, default: 0] += 1
            if let star = line.lastIndex(of: "*") {
                let hexPart = line[line.index(after: star)...]
                if hexPart.count >= 2,
                   let want = Int(hexPart.prefix(2), radix: 16) {
                    var sum: UInt8 = 0
                    for byte in line.dropFirst()
                        .prefix(while: { $0 != "*" }).utf8 {
                        sum ^= byte
                    }
                    if Int(sum) != want { badChecksum += 1 }
                }
            }
            let fields = body.components(separatedBy: ",")
            if type == "GSV", fields.count > 3,
               let total = Int(fields[3]) {
                skySats = max(skySats, total)
            }
            if type == "GGA", fields.count > 7 {
                fixQuality = Int(fields[6]) ?? fixQuality
                ggaSats = Int(fields[7]) ?? ggaSats
            }
        }
        if sentences == 0 {
            return light ? [] : [(
                String(format: L("nmeaprobe — no NMEA sentences on %@:%lld in the window — silence, or a feed that is not NMEA"),
                       ip, Int64(port)), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("nmeaprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("%lld sentence(s): %@"),
                    Int64(sentences),
                    counts.sorted { $0.value > $1.value }
                        .map { "\($0.key) × \($0.value)" }
                        .joined(separator: " · ")), .out)]
        if skySats > 0 {
            lines.append((
                String(format: L("sky view: %lld satellite(s) in view"),
                       Int64(skySats)), .out))
        }
        if fixQuality >= 0 {
            let fixName = fixQuality == 0
                ? L("no fix") : L("a live fix")
            var text2 = String(format: L("receiver reports %@"),
                               fixName)
            if ggaSats >= 0 {
                text2 += String(format: L(" using %lld satellite(s)"),
                                Int64(ggaSats))
            }
            lines.append((text2, .out))
        }
        if badChecksum > 0 {
            lines.append((
                String(format: L("%lld sentence(s) failed their checksum — corruption on the wire; check the cabling and the baud"),
                       Int64(badChecksum)), .out))
        }
        lines.append((L("grade: NMEA is a broadcast confession — anything on this wire hears the receiver's whole sky. Positions were counted past, never printed"), .err))
        return lines
    }

    static func satNMEAProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 10110) else {
                satSay(emit, L("nmeaprobe: give host[:port] — nmeaprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satNMEACore(ip, port, light: false))
        }
    }

    /// A u-blox receiver, polled for its nameplate and nothing
    /// else: UBX MON-VER (class 0x0A, id 0x04) — the one poll whose
    /// request bytes carry their own verified checksum, 0E 34. The
    /// CFG class is configuration, and configuration is a write:
    /// it is never sent.
    static func satUBXCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let request: [UInt8] = [0xB5, 0x62, 0x0A, 0x04,
                                0x00, 0x00, 0x0E, 0x34]
        var reply: [UInt8] = []
        let ufd = satUDPSocket(ip, port)
        if ufd >= 0 {
            satUDPSend(ufd, request)
            for packet in satUDPReadAll(ufd, seconds: 2.0, cap: 8) {
                reply.append(contentsOf: packet)
            }
            close(ufd)
        }
        if reply.isEmpty {
            let fd = satSocket(ip, port)
            if fd >= 0 {
                _ = satSendAll(fd, request)
                reply = satReadWindow(fd, seconds: 2.0, cap: 65536)
                close(fd)
            }
        }
        guard let start = (0..<max(0, reply.count - 1)).first(
            where: { reply[$0] == 0xB5 && reply[$0 + 1] == 0x62 }),
              start + 6 <= reply.count else {
            return light ? [] : [(
                String(format: L("ubxprobe — no UBX answer from %@:%lld — the receiver may speak only NMEA here, or speak on another door"),
                       ip, Int64(port)), .out)]
        }
        let frame = Array(reply[start...])
        guard frame.count >= 8, frame[2] == 0x0A, frame[3] == 0x04
        else {
            return light ? [] : [(
                String(format: L("ubxprobe — %@:%lld answered in UBX but not to MON-VER — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        let length = Int(frame[4]) | (Int(frame[5]) << 8)
        guard frame.count >= 6 + length + 2 else {
            return light ? [] : []
        }
        var ckA: UInt8 = 0, ckB: UInt8 = 0
        for i in 2..<(6 + length) {
            ckA = ckA &+ frame[i]
            ckB = ckB &+ ckA
        }
        guard frame[6 + length] == ckA, frame[6 + length + 1] == ckB
        else {
            return light ? [] : [(
                L("ubxprobe — a MON-VER-shaped reply arrived with a bad checksum — not trusted, not printed"), .err)]
        }
        let payload = Array(frame[6..<(6 + length)])
        func field(_ range: Range<Int>) -> String {
            guard range.upperBound <= payload.count else { return "" }
            return icsClean(payload[range])
                .trimmingCharacters(in: .whitespaces)
        }
        var lines: [ICSLine] = [(
            String(format: L("ubxprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("software %@ · hardware %@"),
                     field(0..<30), field(30..<40)), .out)]
        var at = 40
        var extensions: [String] = []
        while at + 30 <= payload.count {
            let ext = field(at..<(at + 30))
            if !ext.isEmpty { extensions.append(ext) }
            at += 30
        }
        if !extensions.isEmpty {
            lines.append((
                String(format: L("extensions: %@"),
                       extensions.joined(separator: " · ")), .out))
        }
        lines.append((L("grade: the receiver names itself to a single poll — expected on a bench receiver, worth knowing on a deployed one"), .out))
        lines.append((L("read: MON-VER only. The CFG class — configuration, a write — was not sent and never is"), .out))
        return lines
    }

    static func satUBXProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 12321) else {
                satSay(emit, L("ubxprobe: give host[:port] — ubxprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satUBXCore(ip, port, light: false))
        }
    }

    /// An NTRIP caster's table of contents: a plain HTTP GET asks
    /// for the sourcetable, and the mountpoints are listed with
    /// their formats. The correction streams themselves are not
    /// opened — a table of contents is the read.
    static func satNTRIPCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("ntripprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        let request = "GET / HTTP/1.0\r\n"
            + "User-Agent: NTRIP blacksite/11.0 (nightjar)\r\n"
            + "Accept: */*\r\n\r\n"
        guard satSendAll(fd, Array(request.utf8)) else {
            return light ? [] : []
        }
        let text = satText(satReadWindow(fd, seconds: 3.0,
                                         cap: 1048576))
        if text.hasPrefix("ICY") {
            return [(
                String(format: L("ntripprobe — %@:%lld is a legacy caster: it starts streaming corrections on a bare GET, with no table offered"),
                       ip, Int64(port)), .sys),
                (L("grade: NTRIP 1.0 behavior — the stream itself was not decoded and no mountpoint was joined"), .out)]
        }
        var mounts: [(name: String, format: String)] = []
        var casters = 0
        for line in text.components(separatedBy: "\r\n") {
            if line.hasPrefix("STR;") {
                let fields = line.components(separatedBy: ";")
                if fields.count > 3 {
                    mounts.append((fields[1], fields[3]))
                }
            } else if line.hasPrefix("CAS;") {
                casters += 1
            }
        }
        guard text.contains("SOURCETABLE") || !mounts.isEmpty else {
            return light ? [] : [(
                String(format: L("ntripprobe — %@:%lld answered but offered no sourcetable — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("ntripprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("%lld mountpoint(s) on the table"),
                     Int64(mounts.count)), .out)]
        for mount in mounts.prefix(6) {
            lines.append((
                String(format: L("mount %@ · %@"),
                       mount.name,
                       mount.format.isEmpty ? "—" : mount.format),
                .out))
        }
        if casters > 0 {
            lines.append((
                String(format: L("the caster names %lld network(s) behind it"),
                       Int64(casters)), .out))
        }
        lines.append((L("grade: a sourcetable is public by design — the menu is not the meal. Correction streams themselves may ask for credentials; this bench read the menu and joined nothing"), .out))
        return lines
    }

    static func satNTRIPProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 2101) else {
                satSay(emit, L("ntripprobe: give host[:port] — ntripprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satNTRIPCore(ip, port, light: false))
        }
    }

    // MARK: - modems & RF plumbing

    /// A Comtech EF Data modem, asked its name with the protocol's
    /// own packet: '<' + address + '/' + code + '?' + CR. Two queries
    /// — SWR (software revision) and SNO (serial number) — both
    /// query-only codes from the manual's table. The '=' qualifier
    /// is the command form, and it is never sent: on this protocol
    /// the same door that answers questions takes orders.
    static func satComtechCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("comtechprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        func query(_ code: String) -> String? {
            let packet = "<0001/\(code)?\r"
            guard satSendAll(fd, Array(packet.utf8)) else { return nil }
            let text = satText(satReadWindow(fd, seconds: 2.0,
                                             cap: 65536))
            guard let marker = text.range(of: "/\(code)=") else {
                return nil
            }
            let rest = text[marker.upperBound...]
            let end = rest.firstIndex(of: "\r") ?? rest.endIndex
            let value = String(rest[..<end])
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        let greeting = satText(satReadWindow(fd, seconds: 0.8,
                                             cap: 8192))
        let swr = query("SWR")
        let sno = query("SNO")
        guard swr != nil || sno != nil else {
            if light { return [] }
            var lines: [ICSLine] = [(
                String(format: L("comtechprobe — %@:%lld took the connection but answered neither query — noted, not named"),
                       ip, Int64(port)), .sys)]
            if !greeting.isEmpty {
                lines.append((
                    String(format: L("banner: %@"),
                           String(greeting.prefix(90))), .out))
            }
            return lines
        }
        var lines: [ICSLine] = [(
            String(format: L("comtechprobe — %@:%lld"),
                   ip, Int64(port)), .sys)]
        if let swr = swr {
            lines.append((
                String(format: L("software %@"), swr), .out))
        }
        if let sno = sno {
            lines.append((
                String(format: L("serial %@"), sno), .out))
        }
        lines.append((L("grade: the modem identifies itself, firmware and all, to two query packets from any caller — and this protocol's command form rides the same door. Identification is meant to be easy; the door is meant to be gated"), .err))
        lines.append((L("read: SWR + SNO queries only. The '=' command qualifier was never sent"), .out))
        return lines
    }

    static func satComtechProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 23) else {
                satSay(emit, L("comtechprobe: give host[:port] — comtechprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satComtechCore(ip, port, light: false))
        }
    }

    /// A BUC / SSPA amplifier, read at the door that is safe to
    /// read: its web nameplate. The amplifiers' own M&C command
    /// sets (Paradise IP-Net, Terrasat's protocol) are vendor
    /// binary protocols with no public byte spec, and they carry
    /// transmit and mute controls — the bench does not guess
    /// command bytes at a transmitter. What the web door offers —
    /// status line, server banner, page title — is the read.
    static func satBUCCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        guard let url = URL(string: "http://\(ip):\(port)/"),
              let fetched = satFetch(url) else {
            if light { return [] }
            let fd = satSocket(ip, port)
            guard fd >= 0 else {
                return [(
                    String(format: L("bucprobe — no answer at %@:%lld"),
                           ip, Int64(port)), .err)]
            }
            let banner = satText(satReadWindow(fd, seconds: 1.2,
                                               cap: 8192))
            close(fd)
            var lines: [ICSLine] = [(
                String(format: L("bucprobe — %@:%lld answers TCP but serves no web nameplate"),
                       ip, Int64(port)), .sys)]
            if !banner.isEmpty {
                lines.append((
                    String(format: L("banner: %@"),
                           String(banner.prefix(90))), .out))
            }
            lines.append((L("the amplifier's M&C command bytes are a vendor protocol without a public spec — not guessed at, here or anywhere on this bench"), .out))
            return lines
        }
        var lines: [ICSLine] = [(
            String(format: L("bucprobe — %@:%lld answers on its web door (HTTP %lld)"),
                   ip, Int64(port), Int64(fetched.status)), .sys)]
        if let server = fetched.headers["server"], !server.isEmpty {
            lines.append((
                String(format: L("server %@"), server), .out))
        }
        if let titleRange = fetched.body.range(
            of: "<title>", options: .caseInsensitive),
           let endRange = fetched.body.range(
            of: "</title>", options: .caseInsensitive,
            range: titleRange.upperBound..<fetched.body.endIndex) {
            let title = String(
                fetched.body[titleRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                lines.append((
                    String(format: L("nameplate: %@"),
                           String(title.prefix(90))), .out))
            }
        }
        lines.append((L("grade: read at the web door only. This amplifier's real M&C — transmit, mute, gain — rides a vendor binary protocol; the bench reads nameplates and never speaks it"), .err))
        return lines
    }

    static func satBUCProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 80) else {
                satSay(emit, L("bucprobe: give host[:port] — bucprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satBUCCore(ip, port, light: false))
        }
    }

    /// An Iridium modem behind its network gateway door, asked the
    /// identification questions of the AT set: ATI, +CGMI, +CGMM,
    /// +CGMR, +GSN. Message origination — the entire +SBD family —
    /// does not exist in this verb: the modem is identified, never
    /// used, and nothing is ever originated through it.
    static func satIridiumCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("iridiumprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        func ask(_ command: String) -> [String] {
            guard satSendAll(fd, Array((command + "\r").utf8)) else {
                return []
            }
            let lines = satLines(satReadWindow(fd, seconds: 1.8,
                                               cap: 65536))
            return lines.filter {
                $0 != command && $0 != "OK" && !$0.hasPrefix("AT")
            }
        }
        let at = ask("AT")
        _ = at
        let info = ask("ATI")
        let maker = ask("AT+CGMI")
        let model = ask("AT+CGMM")
        let revision = ask("AT+CGMR")
        let serial = ask("AT+GSN")
        let answered = !info.isEmpty || !maker.isEmpty
            || !model.isEmpty || !revision.isEmpty || !serial.isEmpty
        guard answered else {
            return light ? [] : [(
                String(format: L("iridiumprobe — %@:%lld took the connection but the AT door stayed silent — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("iridiumprobe — %@:%lld"),
                   ip, Int64(port)), .sys)]
        if let v = maker.first {
            lines.append((String(format: L("maker %@"), v), .out))
        }
        if let v = model.first ?? info.first {
            lines.append((String(format: L("model %@"), v), .out))
        }
        if let v = revision.first {
            lines.append((String(format: L("firmware %@"), v), .out))
        }
        if let v = serial.first(where: {
            $0.count == 15 && $0.allSatisfy({ $0.isNumber })
        }) {
            lines.append((String(format: L("IMEI %@"), v), .out))
        }
        lines.append((L("grade: the modem introduces itself to any caller at this door — and a live AT door can originate messages, which is exactly why the bench stops at identification. Gate this door like it can talk to orbit, because it can"), .err))
        lines.append((L("read: ATI + CGMI + CGMM + CGMR + GSN — identification only. No message was originated; the +SBD family was never touched"), .out))
        return lines
    }

    static func satIridiumProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 8765) else {
                satSay(emit, L("iridiumprobe: give host[:port] — iridiumprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satIridiumCore(ip, port, light: false))
        }
    }

    // MARK: - terminals

    /// The Starlink dish's local doors, knocked and counted. The
    /// dish's real API is gRPC over HTTP/2 with HPACK header
    /// compression — framing this bench does not reproduce, and
    /// faking it would be lying in the direction of a satellite
    /// terminal. So: the doors are censused, the open API door is
    /// the finding, and the limit is stated out loud.
    static func satStarlinkCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let doors = [9200, 9000, 80, 443]
        var open: [Int] = []
        for door in doors {
            let fd = satSocket(ip, door)
            if fd >= 0 { open.append(door); close(fd) }
        }
        if open.isEmpty {
            return light ? [] : [(
                String(format: L("starlinkprobe — no dish door answered at %@ — the terminal may be on another address (the dish lives at 192.168.100.1 by design) or in bypass mode"),
                       ip), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("starlinkprobe — %@"),
                   ip), .sys),
            (String(format: L("doors answering: %@"),
                    open.map { "\($0)" }.joined(separator: " · ")),
             .out)]
        if open.contains(9200) {
            lines.append((L("the dish's local API door (9200) is open — device information and the terminal's whole posture live behind it"), .out))
        }
        lines.append((L("limit, stated plainly: the dish speaks gRPC over HTTP/2 with HPACK framing, which this bench does not reproduce — so the census above is the whole read, and nothing was transmitted to the terminal beyond these knocks"), .out))
        lines.append((L("grade: a satellite terminal whose management door faces the whole LAN is a posture, not a bug — know it is there"), .err))
        return lines
    }

    static func satStarlinkProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let goal = target ?? "192.168.100.1"
            guard let (_, ip, port) = satResolve(goal, 9200) else {
                satSay(emit, L("starlinkprobe: give the dish address — starlinkprobe 192.168.100.1"), .err)
                return
            }
            satPrint(emit, satStarlinkCore(ip, port, light: false))
        }
    }

    /// A SAT>IP tuner server, censused by RTSP: OPTIONS asks what
    /// the server allows, DESCRIBE reads its session description.
    /// SETUP and PLAY — the verbs that would actually tune it —
    /// are never sent.
    static func satIPCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        let fd = satSocket(ip, port)
        guard fd >= 0 else {
            return light ? [] : [(
                String(format: L("satipprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        defer { close(fd) }
        func rtsp(_ request: String) -> String {
            guard satSendAll(fd, Array(request.utf8)) else { return "" }
            return satText(satReadWindow(fd, seconds: 2.0,
                                         cap: 262144))
        }
        let options = rtsp("OPTIONS rtsp://\(ip)/ RTSP/1.0\r\n"
            + "CSeq: 1\r\n"
            + "User-Agent: blacksite/11.0 (nightjar)\r\n\r\n")
        guard options.contains("RTSP/1.0") else {
            return light ? [] : [(
                String(format: L("satipprobe — %@:%lld answers but not RTSP — noted, not named"),
                       ip, Int64(port)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("satipprobe — %@:%lld"),
                   ip, Int64(port)), .sys)]
        for line in options.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("public:") {
                lines.append((
                    String(format: L("verbs offered: %@"),
                           String(line.dropFirst(7))
                            .trimmingCharacters(in: .whitespaces)),
                    .out))
            }
            if line.lowercased().hasPrefix("server:") {
                lines.append((
                    String(format: L("server %@"),
                           String(line.dropFirst(7))
                            .trimmingCharacters(in: .whitespaces)),
                    .out))
            }
        }
        let describe = rtsp("DESCRIBE rtsp://\(ip)/ RTSP/1.0\r\n"
            + "CSeq: 2\r\nAccept: application/sdp\r\n"
            + "User-Agent: blacksite/11.0 (nightjar)\r\n\r\n")
        if describe.contains("RTSP/1.0 200") {
            var streams = 0
            for line in describe.components(separatedBy: "\r\n") {
                if line.hasPrefix("s=") {
                    lines.append((
                        String(format: L("session: %@"),
                               String(line.dropFirst(2))), .out))
                }
                if line.hasPrefix("m=") { streams += 1 }
            }
            if streams > 0 {
                lines.append((
                    String(format: L("%lld stream description(s) offered"),
                           Int64(streams)), .out))
            }
        }
        lines.append((L("grade: an open SAT>IP door lets any caller on the LAN tune this server — DESCRIBE is the census; the bench never sends SETUP or PLAY, so nothing was tuned"), .err))
        lines.append((L("read: OPTIONS + DESCRIBE only"), .out))
        return lines
    }

    static func satIPProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 554) else {
                satSay(emit, L("satipprobe: give host[:port] — satipprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satIPCore(ip, port, light: false))
        }
    }

    /// A YAMCS mission-operations server, read at its REST door:
    /// the instance list is the nameplate of a mission. Yamcs
    /// supports users and roles — if the list answers without a
    /// login, that is the grade.
    static func satYamcsCore(
        _ ip: String, _ port: Int, light: Bool) -> [ICSLine] {
        guard let url = URL(string: "http://\(ip):\(port)/api/instances"),
              let fetched = satFetch(url, accept: "application/json")
        else {
            return light ? [] : [(
                String(format: L("yamcsprobe — no answer at %@:%lld"),
                       ip, Int64(port)), .err)]
        }
        guard fetched.status == 200,
              let parsed = satJSON(fetched.body),
              let root = parsed as? [String: Any] else {
            return light ? [] : [(
                String(format: L("yamcsprobe — %@:%lld answered HTTP %lld but not a YAMCS instance list — a login wall is a posture too"),
                       ip, Int64(port), Int64(fetched.status)), .sys)]
        }
        let list = (root["instance"] as? [[String: Any]])
            ?? (root["instances"] as? [[String: Any]]) ?? []
        var lines: [ICSLine] = [(
            String(format: L("yamcsprobe — %@:%lld"),
                   ip, Int64(port)), .sys),
            (String(format: L("%lld mission instance(s) listed without a login"),
                    Int64(list.count)), .out)]
        for instance in list.prefix(8) {
            let name = instance["name"] as? String ?? "—"
            var text = String(format: L("instance %@"), name)
            if let mdb = instance["missionDatabase"]
                as? [String: Any],
               let count = (mdb["parameterCount"] as? NSNumber)?
                .intValue {
                text += String(
                    format: L(" · %lld parameters in its database"),
                    Int64(count))
            }
            lines.append((text, .out))
        }
        lines.append((L("grade: mission operations data readable without a login at this door. YAMCS has users and roles for a reason — an open instance list is the posture to fix before the mission does"), .err))
        lines.append((L("read: the instance list only. No command, processor or parameter was touched — this bench does not operate missions"), .out))
        return lines
    }

    static func satYamcsProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip, port) = satResolve(target, 8090) else {
                satSay(emit, L("yamcsprobe: give host[:port] — yamcsprobe 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satYamcsCore(ip, port, light: false))
        }
    }

    // MARK: - public ledgers

    /// One TLE line's check digit: digits at face value, a minus
    /// counts one, everything else zero, mod 10, against column 69.
    static func satTLEChecks(_ line: String) -> Bool {
        let chars = Array(line)
        guard chars.count == 69, let want = chars[68].wholeNumberValue
        else { return false }
        var sum = 0
        for ch in chars[0..<68] {
            if let digit = ch.wholeNumberValue { sum += digit }
            else if ch == "-" { sum += 1 }
        }
        return sum % 10 == want
    }

    /// Celestrak, the public ledger of everything in orbit: one
    /// satellite by NORAD number or name — identity, epoch, the
    /// orbit's shape, and (for a number) the two-line element set
    /// with its checksum actually verified.
    static func satIntelCore(norad: Int?, name: String?) -> [ICSLine] {
        var urlText: String
        if let norad = norad {
            urlText = "https://celestrak.org/NORAD/elements/gp.php"
                + "?CATNR=\(norad)&FORMAT=JSON"
        } else {
            let encoded = (name ?? "").uppercased()
                .addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlText = "https://celestrak.org/NORAD/elements/gp.php"
                + "?NAME=\(encoded)&FORMAT=JSON"
        }
        guard let url = URL(string: urlText),
              let fetched = satFetch(url, accept: "application/json"),
              fetched.status == 200,
              let parsed = satJSON(fetched.body),
              let list = parsed as? [[String: Any]],
              let sat = list.first else { return [] }
        let objName = sat["OBJECT_NAME"] as? String ?? "—"
        let objID = sat["OBJECT_ID"] as? String ?? "—"
        let epoch = sat["EPOCH"] as? String ?? "—"
        let catID = (sat["NORAD_CAT_ID"] as? NSNumber)?.intValue ?? 0
        var lines: [ICSLine] = [(
            String(format: L("satintel — %@"), objName), .sys),
            (String(format: L("NORAD %lld · international designator %@ · epoch %@"),
                    Int64(catID), objID, epoch), .out)]
        if let kind = sat["OBJECT_TYPE"] as? String {
            var text = String(format: L("object type %@"), kind)
            if let rcs = sat["RCS_SIZE"] as? String {
                text += String(format: L(" · radar cross-section %@"),
                               rcs)
            }
            lines.append((text, .out))
        }
        let mm = (sat["MEAN_MOTION"] as? NSNumber)?.doubleValue ?? 0
        let ecc = (sat["ECCENTRICITY"] as? NSNumber)?.doubleValue ?? 0
        let inc = (sat["INCLINATION"] as? NSNumber)?.doubleValue ?? 0
        if mm > 0 {
            let n = 2.0 * Double.pi * mm / 86400.0
            let a = pow(3.986004418e14 / (n * n), 1.0 / 3.0) / 1000.0
            let perigee = a * (1.0 - ecc) - 6378.137
            let apogee = a * (1.0 + ecc) - 6378.137
            lines.append((
                String(format: L("orbit: period %.1f min · perigee %.0f km · apogee %.0f km · inclination %.2f° · eccentricity %.4f"),
                       1440.0 / mm, perigee, apogee, inc, ecc), .out))
        }
        if let norad = norad,
           let tleURL = URL(string: "https://celestrak.org/NORAD/"
                + "elements/gp.php?CATNR=\(norad)&FORMAT=TLE"),
           let tle = satFetch(tleURL), tle.status == 200 {
            let tleLines = tle.body
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(
                    in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let l1 = tleLines.first(where: { $0.hasPrefix("1 ") }),
               let l2 = tleLines.first(where: { $0.hasPrefix("2 ") }) {
                lines.append((l1, .out))
                lines.append((l2, .out))
                if satTLEChecks(l1) && satTLEChecks(l2) {
                    lines.append((L("element set checksums verify — this set is internally sound"), .ok))
                } else {
                    lines.append((L("element set checksum does NOT verify — the set is stale or damaged. Do not fly it"), .err))
                }
            }
        }
        lines.append((L("source: Celestrak's public catalog — the same element sets the whole world tracks with"), .out))
        return lines
    }

    static func satIntel(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let query = (target ?? "25544")
                .trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else {
                satSay(emit, L("satintel: give a NORAD number or a name — satintel 25544"), .err)
                return
            }
            let lines: [ICSLine]
            if let norad = Int(query) {
                lines = satIntelCore(norad: norad, name: nil)
            } else {
                lines = satIntelCore(norad: nil, name: query)
            }
            if lines.isEmpty {
                satSay(emit, L("satintel — Celestrak did not answer that — no match, or the ledger needs the internet from here"), .err)
                return
            }
            satPrint(emit, lines)
        }
    }

    /// The SatNOGS network's ground stations, from its public API:
    /// who is listening to the sky, where, and whether they are up.
    /// A target filters by station name or number.
    static func satNogsCore(filter: String?) -> [ICSLine] {
        guard let url = URL(string: "https://network.satnogs.org"
                + "/api/stations/"),
              let fetched = satFetch(url, accept: "application/json"),
              fetched.status == 200,
              let parsed = satJSON(fetched.body) else { return [] }
        var stations: [[String: Any]] = []
        if let array = parsed as? [[String: Any]] {
            stations = array
        } else if let root = parsed as? [String: Any],
                  let results = root["results"] as? [[String: Any]] {
            stations = results
        }
        guard !stations.isEmpty else { return [] }
        var shown = stations
        if let filter = filter, !filter.isEmpty {
            let needle = filter.lowercased()
            shown = stations.filter { station in
                let name = (station["name"] as? String ?? "")
                    .lowercased()
                let id = (station["id"] as? NSNumber)?.intValue ?? -1
                return name.contains(needle)
                    || String(id) == filter
            }
        }
        let online = stations.filter {
            ($0["status"] as? String) == "Online"
        }.count
        var lines: [ICSLine] = [(
            String(format: L("satnogsprobe — %lld station(s) on the network · %lld online"),
                   Int64(stations.count), Int64(online)), .sys)]
        if shown.isEmpty {
            lines.append((
                String(format: L("no station matches %@"),
                       filter ?? ""), .out))
        }
        for station in shown.prefix(8) {
            let name = station["name"] as? String ?? "—"
            let id = (station["id"] as? NSNumber)?.intValue ?? 0
            let status = station["status"] as? String ?? "—"
            let lat = (station["lat"] as? NSNumber)?.doubleValue
            let lng = (station["lng"] as? NSNumber)?.doubleValue
            var text = String(format: L("%@ (#%lld) · %@"),
                              name, Int64(id), status)
            if let lat = lat, let lng = lng {
                text += String(format: L(" · %.2f, %.2f"), lat, lng)
            }
            if let count = (station["observations"] as? NSNumber)?
                .intValue {
                text += String(format: L(" · %lld observation(s)"),
                               Int64(count))
            }
            lines.append((text, .out))
        }
        lines.append((L("source: the SatNOGS network's public API — a volunteer sky-watch, read in the open"), .out))
        return lines
    }

    static func satNogsProbe(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let lines = satNogsCore(filter: target)
            if lines.isEmpty {
                satSay(emit, L("satnogsprobe — the SatNOGS API did not answer — it is a public ledger, but it needs the internet from here"), .err)
                return
            }
            satPrint(emit, lines)
        }
    }

    // MARK: - census

    /// One light knock on every satellite door at an address, then
    /// the honest limits said out loud: the RF link is radio, and
    /// this application has no transmitter.
    static func satCensusCore(_ ip: String) -> [ICSLine] {
        var hits: [(String, [ICSLine])] = []
        func probe(_ label: String, _ lines: [ICSLine]) {
            if !lines.isEmpty { hits.append((label, lines)) }
        }
        probe("CSP bus", satCSPCore(ip, 9999, light: true))
        probe("CCSDS stream", satCCSDSCore(
            ip, 9998, udp: true, light: true))
        probe("u-blox", satUBXCore(ip, 12321, light: true))
        probe("APRS-IS", satAPRSCore(
            ip, 14580, host: ip, light: true))
        probe("KISS TNC", satKISSCore(ip, 8001, light: true))
        probe("AGW engine", satAGWCore(ip, 8000, light: true))
        probe("rotctld", satRotCore(ip, 4533, light: true))
        probe("rigctld", satRigCore(ip, 4532, light: true))
        probe("gpsd", satGPSDCore(ip, 2947, light: true))
        probe("NMEA feed", satNMEACore(ip, 10110, light: true))
        probe("NTRIP caster", satNTRIPCore(ip, 2101, light: true))
        probe("Comtech M&C", satComtechCore(ip, 23, light: true))
        probe("BUC web door", satBUCCore(ip, 80, light: true))
        probe("Iridium gateway", satIridiumCore(
            ip, 8765, light: true))
        probe("Starlink dish", satStarlinkCore(
            ip, 9200, light: true))
        probe("SAT>IP", satIPCore(ip, 554, light: true))
        probe("YAMCS", satYamcsCore(ip, 8090, light: true))
        var lines: [ICSLine] = [(
            String(format: L("satcensus — %@"), ip), .sys)]
        if hits.isEmpty {
            lines.append((L("no satellite door answered at this address — the ground segment lives elsewhere, or keeps its doors shut"), .out))
        }
        for (label, hitLines) in hits {
            lines.append((
                String(format: L("door: %@"), label), .sys))
            lines.append(contentsOf: hitLines.prefix(3))
        }
        lines.append((L("limits, stated plainly: this census knocks on network doors only. The RF link itself is radio — there is no transmitter in an iOS app, so nothing here was, or could be, sent to a spacecraft. SLE and CFDP ride managed mission links and are named here, not faked"), .out))
        return lines
    }

    static func satCensus(
        _ target: String?,
        emit: @escaping (String, BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var goal = target
            if goal == nil { goal = BlacksiteNet.defaultGatewayIP() }
            guard let goal = goal,
                  let (_, ip, _) = satResolve(goal, 0) else {
                satSay(emit, L("satcensus: give the ground-station host — satcensus 192.168.1.60"), .err)
                return
            }
            satPrint(emit, satCensusCore(ip))
        }
    }
}
