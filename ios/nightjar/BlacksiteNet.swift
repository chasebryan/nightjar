import Foundation
import Network

// BlacksiteNet — the console's wire kit.
//
// The classic network commands, built by
// hand because iOS gives an app no /bin to
// borrow: ICMP echo over a datagram ping
// socket (the door Apple's own SimplePing
// walks through), a DNS client speaking
// the wire format itself, NWConnection for
// streams, getifaddrs for the phone's own
// interfaces. Every engine reports through
// two closures and calls done() exactly
// once; the shell owns busy and the gates.

typealias BlacksiteEmit =
    (String, BlacksiteShell.Line.Kind) -> Void

enum BlacksiteNet {

    // MARK: The default gateway

    /// This phone's default gateway, read
    /// from the kernel's route table: the
    /// one identification on the wire that
    /// is not an inference — the device the
    /// default route names IS the router,
    /// by definition. The classic route-
    /// socket read: sysctl NET_RT_DUMP for
    /// AF_INET, walk rt_msghdr entries, and
    /// the default destination (0.0.0.0)
    /// with RTF_GATEWAY carries its gateway
    /// in the RTA_GATEWAY slot.
    static func defaultGatewayIP() -> String? {
        var mib: [Int32] = [
            CTL_NET, PF_ROUTE, 0, AF_INET,
            NET_RT_DUMP, 0,
        ]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed,
                     nil, 0) == 0,
              needed > 0
        else { return nil }
        var buffer = [UInt8](
            repeating: 0, count: needed)
        guard sysctl(&mib, 6, &buffer,
                     &needed, nil, 0) == 0
        else { return nil }
        let headerSize =
            MemoryLayout<rt_msghdr>.size
        var offset = 0
        while offset + headerSize <= needed {
            let base = buffer.withUnsafeBytes {
                $0.baseAddress!
            } + offset
            let hdr = base.assumingMemoryBound(
                to: rt_msghdr.self).pointee
            let length = Int(hdr.rtm_msglen)
            if length <= 0 { break }
            defer { offset += length }
            guard Int32(hdr.rtm_version)
                == RTM_VERSION else { continue }
            // RTA_DST is the first sockaddr
            // after the header when its bit
            // is set, RTA_GATEWAY the next.
            var addrPtr = base + headerSize
            let addrs = hdr.rtm_addrs
            if (addrs & RTA_DST) != 0 {
                let dst = addrPtr
                    .assumingMemoryBound(
                        to: sockaddr.self).pointee
                let dstLen = max(
                    Int(dst.sa_len),
                    MemoryLayout<sockaddr>.size)
                if dst.sa_family == AF_INET {
                    let sin = addrPtr
                        .assumingMemoryBound(
                            to: sockaddr_in.self)
                        .pointee
                    if sin.sin_addr.s_addr == 0,
                       (addrs & RTA_GATEWAY) != 0,
                       (hdr.rtm_flags & RTF_GATEWAY) != 0 {
                        let gwPtr = addrPtr + dstLen
                        let gw = gwPtr
                            .assumingMemoryBound(
                                to: sockaddr_in.self)
                            .pointee
                        if gw.sin_family == AF_INET {
                            return ipv4String(
                                gw.sin_addr)
                        }
                    }
                }
                addrPtr += dstLen
            }
        }
        return nil
    }

    /// inet_ntoa, spelled out: the in_addr
    /// is already the wire's byte order.
    static func ipv4String(
        _ addr: in_addr) -> String {
        let raw = addr.s_addr
        return "\(raw & 0xff)."
            + "\((raw >> 8) & 0xff)."
            + "\((raw >> 16) & 0xff)."
            + "\((raw >> 24) & 0xff)"
    }

    // MARK: Shared plumbing

    private static let queue =
        DispatchQueue(
            label: "blacksite.net",
            attributes: .concurrent)

    static func run(
        _ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    /// Resolve a host to an IPv4
    /// sockaddr_in, or say why not.
    static func resolve4(
        _ host: String)
        -> (ip: String,
            addr: sockaddr_in)? {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0, ai_addrlen: 0,
            ai_canonname: nil, ai_addr: nil,
            ai_next: nil)
        var result: UnsafeMutablePointer<
            addrinfo>?
        guard getaddrinfo(host, nil, &hints,
                          &result) == 0,
              let first = result else {
            return nil
        }
        defer { freeaddrinfo(result) }
        guard let sa = first.pointee.ai_addr
        else { return nil }
        let sin = sa.withMemoryRebound(
            to: sockaddr_in.self, capacity: 1) {
            $0.pointee
        }
        var buffer = [CChar](
            repeating: 0, count: 64)
        var addr = sin.sin_addr
        let text = inet_ntop(
            AF_INET, &addr, &buffer,
            socklen_t(buffer.count))
        guard text != nil else { return nil }
        return (String(cString: buffer), sin)
    }

    static func sockaddrIn(
        ip: String, port: UInt16)
        -> sockaddr_in {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(
            MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = port.bigEndian
        sin.sin_addr = in_addr(
            s_addr: inet_addr(ip))
        return sin
    }

    static func setRecvTimeout(
        _ fd: Int32, seconds: Double) {
        var tv = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32(
                (seconds - Double(Int(seconds)))
                * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO,
                   &tv, socklen_t(
                    MemoryLayout<timeval>
                        .size))
    }

    /// The Internet checksum (RFC 1071).
    static func checksum(_ data: [UInt8])
        -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < data.count {
            sum += UInt32(data[index]) << 8
                | UInt32(data[index + 1])
            index += 2
        }
        if index < data.count {
            sum += UInt32(data[index]) << 8
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF)
                + (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    static func ms(_ seconds: Double)
        -> String {
        String(format: "%.1f", seconds * 1000)
    }

    // MARK: Ping + traceroute (ICMP)

    /// One echo's answer, parsed off the
    /// wire.
    struct EchoReply {
        var fromIP: String
        var ttl: Int
        var type: UInt8
        var seq: UInt16
        var embeddedSeq: UInt16?
    }

    /// Open the ping socket. iOS lets an
    /// app hold a datagram ICMP socket —
    /// replies arrive with their IP header
    /// still on.
    static func icmpSocket() -> Int32 {
        socket(AF_INET, SOCK_DGRAM,
               IPPROTO_ICMP)
    }

    static func echoPacket(
        id: UInt16, seq: UInt16) -> [UInt8] {
        var packet = [UInt8](
            repeating: 0, count: 8 + 32)
        packet[0] = 8
        packet[1] = 0
        packet[4] = UInt8(id >> 8)
        packet[5] = UInt8(id & 0xFF)
        packet[6] = UInt8(seq >> 8)
        packet[7] = UInt8(seq & 0xFF)
        for i in 0..<32 {
            packet[8 + i] =
                UInt8(0x61 + (i % 26))
        }
        let sum = checksum(packet)
        packet[2] = UInt8(sum >> 8)
        packet[3] = UInt8(sum & 0xFF)
        return packet
    }

    /// Read one ICMP message within the
    /// window. Returns nil on timeout.
    static func readICMP(
        _ fd: Int32, window: Double)
        -> (reply: EchoReply,
            after: Date)? {
        setRecvTimeout(fd, seconds: window)
        var buffer = [UInt8](
            repeating: 0, count: 2048)
        var from = sockaddr_in()
        var fromLen = socklen_t(
            MemoryLayout<sockaddr_in>.size)
        let started = Date()
        while Date().timeIntervalSince(
            started) < window {
            let got = withUnsafeMutablePointer(
                to: &from) { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1) { sa in
                    recvfrom(
                        fd, &buffer,
                        buffer.count, 0, sa,
                        &fromLen)
                }
            }
            if got <= 0 {
                if errno == EAGAIN
                    || errno == EWOULDBLOCK {
                    return nil
                }
                continue
            }
            let bytes = Array(buffer[0..<got])
            guard bytes.count >= 20 else {
                continue
            }
            let ihl = Int(bytes[0] & 0x0F) * 4
            guard bytes.count >= ihl + 8
            else { continue }
            let ttl = Int(bytes[8])
            var addr = from.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &addr, &text,
                      socklen_t(text.count))
            let icmp = Array(bytes[ihl...])
            let type = icmp[0]
            let seq = UInt16(icmp[6]) << 8
                | UInt16(icmp[7])
            var embedded: UInt16?
            if type == 11
                && icmp.count >= 8 + 20 + 8 {
                let inner = Array(
                    icmp[8...])
                let innerIHL = Int(
                    inner[0] & 0x0F) * 4
                if inner.count
                    >= innerIHL + 8 {
                    embedded =
                        UInt16(inner[innerIHL
                                       + 6]) << 8
                        | UInt16(
                            inner[innerIHL
                                  + 7])
                }
            }
            return (EchoReply(
                        fromIP: String(
                            cString: text),
                        ttl: ttl, type: type,
                        seq: seq,
                        embeddedSeq: embedded),
                    Date())
        }
        return nil
    }

    static func sendEcho(
        _ fd: Int32, to target: sockaddr_in,
        packet: [UInt8]) {
        var dest = target
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
    }

    static func ping(host: String,
                     count: Int,
                     emit: @escaping
                        BlacksiteEmit,
                     done: @escaping ()
                        -> Void) {
        run {
            guard let resolved = resolve4(
                host) else {
                emit(String(format: L("ping: %@ does not resolve."), String(describing: host)), .err)
                done()
                return
            }
            let fd = icmpSocket()
            guard fd >= 0 else {
                emit(String(format: L("ping: the ICMP door is shut on this system (errno %@)."), String(describing: errno)), .err)
                done()
                return
            }
            defer { close(fd) }
            emit(String(format: L("PING %@ (%@) — %@ echoes, by hand"), String(describing: host), String(describing: resolved.ip), String(describing: count)),
                 .sys)
            let id = UInt16.random(
                in: 1...UInt16.max)
            var sent = 0
            var received = 0
            var times: [Double] = []
            for seq in 0..<count {
                var target = resolved.addr
                target.sin_port = 0
                let packet = echoPacket(
                    id: id, seq: UInt16(seq))
                let sentAt = Date()
                sendEcho(fd, to: target,
                         packet: packet)
                sent += 1
                var answered = false
                while !answered {
                    let remain = 1.0 - Date()
                        .timeIntervalSince(
                            sentAt)
                    if remain <= 0 { break }
                    guard let (reply, at) =
                        readICMP(
                            fd, window: remain)
                    else { break }
                    if reply.type == 0
                        && reply.seq
                            == UInt16(seq) {
                        let rtt = at
                            .timeIntervalSince(
                                sentAt)
                        times.append(rtt)
                        received += 1
                        answered = true
                        emit(String(format: L("reply from %@: seq %@, %@ ms, ttl %@"), String(describing: reply.fromIP), String(describing: seq), String(describing: ms(rtt)), String(describing: reply.ttl)),
                             .out)
                    }
                }
                if !answered {
                    emit(String(format: L("seq %@: no answer in a second."), String(describing: seq)), .err)
                }
                if seq + 1 < count {
                    Thread.sleep(
                        forTimeInterval: 0.2)
                }
            }
            if received > 0 {
                let avg = times.reduce(
                    0, +) / Double(
                        times.count)
                emit(String(format: L("%@ sent, %@ back — min %@ · avg %@ · max %@ ms"), String(describing: sent), String(describing: received), String(describing: ms(times.min()!)), String(describing: ms(avg)), String(describing: ms(times.max()!))),
                     received == sent
                        ? .ok : .out)
            } else {
                emit(String(format: L("%@ sent, none came back."), String(describing: sent)), .err)
            }
            done()
        }
    }

    static func traceroute(
        host: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        run {
            guard let resolved = resolve4(
                host) else {
                emit(String(format: L("traceroute: %@ does not resolve."), String(describing: host)),
                     .err)
                done()
                return
            }
            let fd = icmpSocket()
            guard fd >= 0 else {
                emit(String(format: L("traceroute: the ICMP door is shut (errno %@)."), String(describing: errno)),
                     .err)
                done()
                return
            }
            defer { close(fd) }
            emit(String(format: L("the road to %@ (%@), 30 hops at most"), String(describing: host), String(describing: resolved.ip)), .sys)
            let id = UInt16.random(
                in: 1...UInt16.max)
            var seq: UInt16 = 0
            var reached = false
            for hop in 1...30 {
                var ttl = Int32(hop)
                setsockopt(
                    fd, IPPROTO_IP, IP_TTL,
                    &ttl, socklen_t(
                        MemoryLayout<Int32>
                            .size))
                var target = resolved.addr
                target.sin_port = 0
                seq += 1
                let packet = echoPacket(
                    id: id, seq: seq)
                let sentAt = Date()
                sendEcho(fd, to: target,
                         packet: packet)
                var line: String?
                var probing = true
                while probing {
                    let remain = 1.5 - Date()
                        .timeIntervalSince(
                            sentAt)
                    if remain <= 0 { break }
                    guard let (reply, at) =
                        readICMP(
                            fd, window: remain)
                    else { break }
                    if reply.type == 0
                        && reply.seq == seq {
                        let rtt = at
                            .timeIntervalSince(
                                sentAt)
                        line = "\(hop)  "
                            + "\(reply.fromIP)  "
                            + "\(ms(rtt)) ms"
                        reached = true
                        probing = false
                    } else if reply.type == 11
                        && (reply
                            .embeddedSeq == seq
                            || reply
                            .embeddedSeq
                            == nil) {
                        let rtt = at
                            .timeIntervalSince(
                                sentAt)
                        line = "\(hop)  "
                            + "\(reply.fromIP)  "
                            + "\(ms(rtt)) ms"
                        probing = false
                    }
                }
                emit(line ?? "\(hop)  *",
                     reached ? .ok : .out)
                if reached { break }
            }
            emit(reached
                 ? "there. the road ends "
                   + "at the door."
                 : "30 hops and no door — "
                   + "the road goes on "
                   + "past where I can see.",
                 reached ? .ok : .err)
            done()
        }
    }
}


// MARK: - The DNS client

/// A small DNS client speaking the wire
/// format itself (RFC 1035) — the console
/// asks any resolver it is told to, and
/// reads compression pointers honestly.
enum BlacksiteDNS {

    struct Answer {
        var name: String
        var type: UInt16
        var ttl: UInt32
        var data: String
    }

    struct Reply {
        var rcode: Int
        var answers: [Answer]
        var elapsed: Double
    }

    static let typeNames: [UInt16: String] = [
        1: "A", 2: "NS", 5: "CNAME",
        6: "SOA", 12: "PTR", 15: "MX",
        16: "TXT", 28: "AAAA", 33: "SRV",
        65: "HTTPS", 257: "CAA",
    ]

    static func typeNumber(_ name: String)
        -> UInt16? {
        typeNames.first {
            $0.value == name.uppercased()
        }?.key
    }

    static func encodeName(_ name: String)
        -> [UInt8] {
        var out: [UInt8] = []
        for label in name
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "."))
            .split(separator: ".") {
            out.append(UInt8(label.count))
            out.append(contentsOf:
                        Array(label.utf8))
        }
        out.append(0)
        return out
    }

    /// Read a possibly-compressed name at
    /// an offset. Returns the name and the
    /// offset just past it (past the
    /// pointer, when one was followed).
    static func readName(
        _ msg: [UInt8], at start: Int)
        -> (String, Int) {
        var labels: [String] = []
        var index = start
        var end: Int?
        var jumps = 0
        while index < msg.count {
            let len = Int(msg[index])
            if len == 0 {
                if end == nil {
                    end = index + 1
                }
                break
            }
            if len & 0xC0 == 0xC0 {
                guard index + 1 < msg.count
                else { break }
                let pointer =
                    (len & 0x3F) << 8
                    | Int(msg[index + 1])
                if end == nil {
                    end = index + 2
                }
                index = pointer
                jumps += 1
                if jumps > 12 { break }
                continue
            }
            let from = index + 1
            let to = min(msg.count,
                         from + len)
            guard from < to else { break }
            labels.append(String(
                bytes: msg[from..<to],
                encoding: .utf8) ?? "?")
            index = to
        }
        return (labels.joined(separator: "."),
                end ?? msg.count)
    }

    static func query(server: String,
                      name: String,
                      type: UInt16,
                      timeout: Double = 3.5)
        -> Reply? {
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
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
             0x00, 0x00])
        packet.append(contentsOf:
            encodeName(name))
        packet.append(UInt8(type >> 8))
        packet.append(UInt8(type & 0xFF))
        packet.append(contentsOf: [0, 1])
        var dest = BlacksiteNet.sockaddrIn(
            ip: server, port: 53)
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
            repeating: 0, count: 4096)
        let got = recv(fd, &buffer,
                       buffer.count, 0)
        let elapsed = Date()
            .timeIntervalSince(started)
        guard got >= 12 else { return nil }
        let msg = Array(buffer[0..<got])
        let rcode = Int(msg[3] & 0x0F)
        let qd = Int(msg[4]) << 8
            | Int(msg[5])
        let an = Int(msg[6]) << 8
            | Int(msg[7])
        var offset = 12
        for _ in 0..<qd {
            let (_, next) = readName(
                msg, at: offset)
            offset = next + 4
        }
        var answers: [Answer] = []
        for _ in 0..<an {
            let (owner, afterName) = readName(
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
            answers.append(Answer(
                name: owner, type: rtype,
                ttl: ttl,
                data: renderRdata(
                    msg, type: rtype,
                    at: rdata, raw: raw)))
            offset = rdata + rdlen
        }
        return Reply(rcode: rcode,
                     answers: answers,
                     elapsed: elapsed)
    }

    static func renderRdata(
        _ msg: [UInt8], type: UInt16,
        at offset: Int, raw: [UInt8])
        -> String {
        switch type {
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
            return readName(msg, at: offset).0
        case 15 where raw.count >= 3:
            let pref = Int(raw[0]) << 8
                | Int(raw[1])
            let host = readName(
                msg, at: offset + 2).0
            return "\(pref) \(host)"
        case 6:
            let (mname, afterM) = readName(
                msg, at: offset)
            let (rname, _) = readName(
                msg, at: afterM)
            return "\(mname) \(rname)"
        case 16:
            var parts: [String] = []
            var index = 0
            while index < raw.count {
                let len = Int(raw[index])
                let from = index + 1
                let to = min(raw.count,
                             from + len)
                if from < to {
                    parts.append(String(
                        bytes: raw[from..<to],
                        encoding: .utf8)
                        ?? "")
                }
                index = to
            }
            return parts.joined(
                separator: " ")
        default:
            return "<\(raw.count) bytes>"
        }
    }
}

// MARK: - Dig, host, whois, fetch, streams

extension BlacksiteNet {

    static func dig(name: String,
                    typeName: String,
                    server: String,
                    emit: @escaping
                        BlacksiteEmit,
                    done: @escaping ()
                        -> Void) {
        run {
            let type = BlacksiteDNS
                .typeNumber(typeName) ?? 1
            guard let reply = BlacksiteDNS
                .query(server: server,
                       name: name, type: type)
            else {
                emit(String(format: L("dig: no answer from %@ — the wire stayed quiet."), String(describing: server)),
                     .err)
                done()
                return
            }
            let status: String
            switch reply.rcode {
            case 0: status = "NOERROR"
            case 2: status = "SERVFAIL"
            case 3: status = "NXDOMAIN"
            case 5: status = "REFUSED"
            default:
                status = "rcode "
                    + "\(reply.rcode)"
            }
            emit(String(format: L("; dig %@ %@ @%@ — %@, %@ answer(s), %@ ms"), String(describing: name), String(describing: typeName.uppercased()), String(describing: server), String(describing: status), String(describing: reply.answers.count), String(describing: ms(reply.elapsed))),
                 reply.rcode == 0
                    ? .sys : .err)
            if reply.rcode == 3 {
                emit(L("the name does not exist. that is the whole answer."), .err)
            }
            for answer in reply.answers {
                let label = BlacksiteDNS
                    .typeNames[answer.type]
                    ?? "\(answer.type)"
                emit(String(format: L("%@. %@ IN %@ %@"), String(describing: answer.name), String(describing: answer.ttl), String(describing: label), String(describing: answer.data)), .out)
            }
            done()
        }
    }

    /// host — the system resolver's answer,
    /// both families, plus a reverse lookup
    /// when handed an address.
    static func hostLookup(
        _ target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        run {
            if resolve4(target) != nil
                && target.first?.isNumber
                    == true {
                var hints = addrinfo(
                    ai_flags: NI_NAMEREQD,
                    ai_family: AF_INET,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: 0,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil)
                var result:
                    UnsafeMutablePointer<
                        addrinfo>?
                if getaddrinfo(target, nil,
                               &hints,
                               &result) == 0,
                   let first = result,
                   let canon = first.pointee
                    .ai_canonname {
                    emit(String(format: L("%@ is %@"), String(describing: target), String(describing: String(cString:
                                    canon))),
                         .out)
                    freeaddrinfo(result)
                    done()
                    return
                }
                if let result = result {
                    freeaddrinfo(result)
                }
                emit(String(format: L("%@ has no name the resolver knows."), String(describing: target)), .err)
                done()
                return
            }
            var hints = addrinfo(
                ai_flags: 0, ai_family: 0,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0, ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<
                addrinfo>?
            guard getaddrinfo(target, nil,
                              &hints,
                              &result) == 0,
                  let first = result else {
                emit(String(format: L("host: %@ does not resolve."), String(describing: target)), .err)
                done()
                return
            }
            var cursor: UnsafeMutablePointer<
                addrinfo>? = first
            var found = false
            var printed = Set<String>()
            while let node = cursor {
                cursor = node.pointee.ai_next
                guard let sa = node.pointee
                    .ai_addr else { continue }
                let family = sa.pointee
                    .sa_family
                var buffer = [CChar](
                    repeating: 0, count: 128)
                if family == sa_family_t(
                    AF_INET) {
                    let sin = sa
                        .withMemoryRebound(
                            to: sockaddr_in
                                .self,
                            capacity: 1) {
                            $0.pointee
                        }
                    var addr = sin.sin_addr
                    inet_ntop(
                        AF_INET, &addr,
                        &buffer,
                        socklen_t(
                            buffer.count))
                    let ip = String(
                        cString: buffer)
                    if printed.insert(ip)
                        .inserted {
                        emit(String(format: L("%@ has address %@"), String(describing: target), String(describing: ip)), .out)
                        found = true
                    }
                } else if family
                    == sa_family_t(AF_INET6) {
                    let sin = sa
                        .withMemoryRebound(
                            to: sockaddr_in6
                                .self,
                            capacity: 1) {
                            $0.pointee
                        }
                    var addr = sin.sin6_addr
                    inet_ntop(
                        AF_INET6, &addr,
                        &buffer,
                        socklen_t(
                            buffer.count))
                    let ip = String(
                        cString: buffer)
                    if printed.insert(ip)
                        .inserted {
                        emit(String(format: L("%@ has IPv6 address %@"), String(describing: target), String(describing: ip)), .out)
                        found = true
                    }
                }
            }
            freeaddrinfo(result)
            if !found {
                emit(String(format: L("host: nothing came back for %@."), String(describing: target)),
                     .err)
            }
            done()
        }
    }

    // MARK: Whois

    static func whoisServer(for domain: String)
        -> String {
        let tld = domain.split(
            separator: ".").last
            .map(String.init)?
            .lowercased() ?? ""
        switch tld {
        case "com", "net":
            return "whois.verisign-grs.com"
        case "org": return "whois.pir.org"
        case "io": return "whois.nic.io"
        case "co": return "whois.nic.co"
        case "dev", "app", "page", "new":
            return "whois.nic.google"
        case "xyz": return "whois.nic.xyz"
        case "info": return "whois.iana.org"
        default: return "whois.iana.org"
        }
    }

    static func whois(domain: String,
                      emit: @escaping
                        BlacksiteEmit,
                      done: @escaping ()
                        -> Void) {
        var server = whoisServer(
            for: domain)
        var followed = false
        func ask(_ serverName: String) {
            tcpExchange(
                host: serverName, port: 43,
                udp: false,
                payload: domain + "\r\n",
                telnet: false,
                idleSeconds: 12
            ) { text, problem in
                if let problem = problem {
                    emit(String(format: L("whois: %@"), String(describing: problem)),
                         .err)
                    done()
                    return
                }
                let body = text ?? ""
                if !followed,
                   let referral =
                    referral(in: body) {
                    followed = true
                    server = referral
                    emit(String(format: L("; referred to %@"), String(describing: referral)), .sys)
                    ask(referral)
                    return
                }
                emit(String(format: L("; whois %@ via %@"), String(describing: domain), String(describing: serverName)),
                     .sys)
                var lines = 0
                for row in body.split(
                    separator: "\n") {
                    let trimmed = row
                        .trimmingCharacters(
                            in: .whitespaces)
                    if trimmed.hasPrefix("%")
                        || trimmed.hasPrefix(
                            "#")
                        || trimmed.isEmpty {
                        continue
                    }
                    emit(trimmed, .out)
                    lines += 1
                    if lines >= 110 {
                        emit(L("; … the rest is boilerplate."),
                             .sys)
                        break
                    }
                }
                if lines == 0 {
                    emit(L("the registry answered with nothing readable."),
                         .err)
                }
                done()
            }
        }
        ask(server)
    }

    static func referral(in body: String)
        -> String? {
        for row in body.split(
            separator: "\n") {
            let line = row
                .trimmingCharacters(
                    in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("refer:")
                || lower.contains(
                    "registrar whois server:") {
                if let tail = line.split(
                    separator: ":").last {
                    let host = tail
                        .trimmingCharacters(
                            in: .whitespaces)
                    if host.contains(".") {
                        return host
                    }
                }
            }
        }
        return nil
    }

    // MARK: Streams — nc / telnet / whois

    /// The stream's collecting box — a
    /// reference type, because receive
    /// callbacks outlive any single call.
    final class StreamBox {
        var data = Data()
        var finished = false
    }

    /// One TCP conversation: connect, send
    /// the payload if any, read until the
    /// far end closes or the idle cap hits.
    /// Completion fires exactly once.
    static func tcpExchange(
        host: String, port: Int, udp: Bool,
        payload: String?, telnet: Bool,
        idleSeconds: Double = 6,
        completion: @escaping
            (String?, String?) -> Void) {
        guard port > 0, port <= 65535,
              let nwPort = NWEndpoint.Port(
                rawValue: UInt16(port))
        else {
            completion(nil, "that is not "
                       + "a port.")
            return
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: udp ? .udp : .tcp)
        let box = StreamBox()
        var watchdog: DispatchWorkItem?
        let finish: (String?) -> Void = {
            problem in
            guard !box.finished else {
                return
            }
            box.finished = true
            watchdog?.cancel()
            connection.cancel()
            if let problem = problem,
               box.data.isEmpty {
                completion(nil, problem)
            } else if box.data.isEmpty {
                completion("", problem)
            } else {
                let cleaned = telnet
                    ? stripTelnet(box.data)
                    : box.data
                completion(
                    renderStreamData(cleaned),
                    nil)
            }
        }
        watchdog = DispatchWorkItem {
            finish(nil)
        }
        connection.stateUpdateHandler = {
            state in
            switch state {
            case .ready:
                if let payload = payload,
                   !payload.isEmpty {
                    connection.send(
                        content: Data(
                            payload.utf8),
                        completion:
                            .contentProcessed(
                                { _ in }))
                }
                if let watchdog = watchdog {
                    DispatchQueue.global()
                        .asyncAfter(
                            deadline: .now()
                                + idleSeconds,
                            execute: watchdog)
                }
                receiveMore(connection,
                            box: box,
                            finish: finish)
            case .failed(let error):
                finish(describe(error))
            case .waiting(let error):
                finish(describe(error))
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    private static func receiveMore(
        _ connection: NWConnection,
        box: StreamBox,
        finish: @escaping (String?) -> Void) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { data, _, isComplete, error in
            if let data = data,
               !data.isEmpty {
                box.data.append(data)
                if box.data.count
                    > 262_144 {
                    finish(nil)
                    return
                }
            }
            if isComplete {
                finish(nil)
            } else if let error = error {
                finish(
                    box.data.isEmpty
                        ? describe(error)
                        : nil)
            } else if !box.finished {
                receiveMore(connection,
                            box: box,
                            finish: finish)
            }
        }
    }

    static func describe(_ error: NWError)
        -> String {
        switch error {
        case .posix(let code):
            if code == .ECONNREFUSED {
                return "connection refused "
                    + "— the door is shut."
            }
            if code == .ETIMEDOUT {
                return "timed out."
            }
            if code == .EHOSTUNREACH {
                return "no route to that "
                    + "host."
            }
            return "the wire said "
                + "\(code)."
        case .dns(let code):
            return "the name does not "
                + "resolve (dns \(code))."
        default:
            return "the connection "
                + "failed: \(error)"
        }
    }

    /// Strip telnet negotiation, answer
    /// every offer with a refusal.
    static func stripTelnet(_ data: Data)
        -> Data {
        var out = Data()
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            if byte == 255 {
                let next = data.index(
                    after: index)
                guard next < data.endIndex
                else { break }
                let command = data[next]
                if command == 255 {
                    out.append(255)
                    index = data.index(
                        after: next)
                } else if command >= 251
                    && command <= 254 {
                    index = data.index(
                        next, offsetBy: 2,
                        limitedBy:
                            data.endIndex)
                        ?? data.endIndex
                } else {
                    index = data.index(
                        after: next)
                }
            } else {
                out.append(byte)
                index = data.index(
                    after: index)
            }
        }
        return out
    }

    static func renderStreamData(_ data: Data)
        -> String {
        if data.contains(0) {
            let hex = data.prefix(64)
                .map {
                    String(format: "%02x",
                           $0)
                }
                .joined(separator: " ")
            return "<\(data.count) bytes "
                + "of binary — first: "
                + hex + ">"
        }
        let text = String(
            decoding: data, as: UTF8.self)
        if text.count > 6000 {
            return String(text.prefix(6000))
                + "\n… (\(data.count) "
                + "bytes in all)"
        }
        return text
    }
}


// MARK: - Fetch (curl / wget) and the
// local readers

extension BlacksiteNet {

    static func fetch(
        urlString: String, headOnly: Bool,
        headers: [(String, String)],
        savePath: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        var text = urlString
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text)
        else {
            emit(L("curl: that is not a URL."), .err)
            done()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod =
            headOnly ? "HEAD" : "GET"
        request.timeoutInterval = 20
        request.setValue(
            "blacksite/9.0 (nightjar-hack)",
            forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(
                value, forHTTPHeaderField: key)
        }
        let started = Date()
        let task = URLSession.shared
            .dataTask(with: request) {
                data, response, error in
                let elapsed = Date()
                    .timeIntervalSince(started)
                if let error = error {
                    emit(String(format: L("curl: %@"), String(describing: fetchProblem(error))),
                         .err)
                    done()
                    return
                }
                guard let http = response
                    as? HTTPURLResponse else {
                    emit(L("curl: the answer was not HTTP."),
                         .err)
                    done()
                    return
                }
                let body = data ?? Data()
                let reason = HTTPURLResponse
                    .localizedString(
                        forStatusCode:
                            http.statusCode)
                emit("HTTP \(http.statusCode) "
                     + "\(reason) — "
                     + "\(body.count) bytes "
                     + "in "
                     + String(format: "%.2f",
                              elapsed)
                     + " s", http.statusCode
                        < 400 ? .ok : .err)
                if let final = http.url,
                   final.absoluteString
                    != url.absoluteString {
                    emit(String(format: L("followed to %@"), String(describing: final.absoluteString)),
                         .sys)
                }
                let fields = http
                    .allHeaderFields
                let orderedKeys = fields.keys
                    .sorted {
                        String(describing: $0)
                            .lowercased()
                            < String(
                                describing: $1)
                                .lowercased()
                    }
                for key in orderedKeys
                    .prefix(30) {
                    let name = String(
                        describing: key)
                    let value = String(
                        describing:
                            fields[key] ?? "")
                    emit("\(name): \(value)",
                         .sys)
                }
                if let savePath = savePath {
                    if BlacksiteFS.writeData(
                        savePath, data: body) {
                        emit(String(format: L("saved %@ bytes to %@"), String(describing: body.count), String(describing: savePath)), .ok)
                    } else {
                        emit(L("curl: the files would not take it."),
                             .err)
                    }
                    done()
                    return
                }
                if headOnly || body.isEmpty {
                    done()
                    return
                }
                emit(renderStreamData(body),
                     .out)
                done()
            }
        task.resume()
    }

    static func fetchProblem(
        _ error: Error) -> String {
        let urlError = error as? URLError
        switch urlError?.code {
        case .cannotFindHost,
             .dnsLookupFailed:
            return "the name does not "
                + "resolve."
        case .timedOut:
            return "timed out — the far "
                + "end never answered."
        case .notConnectedToInternet,
             .cannotConnectToHost:
            return "no route out from "
                + "here."
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid:
            return "the TLS handshake "
                + "failed — the far end's "
                + "papers are not in order."
        case .cancelled:
            return "called off."
        default:
            return error.localizedDescription
        }
    }

    // MARK: Interfaces (ifconfig)

    struct InterfaceInfo {
        var name: String
        var flags: UInt32
        var v4: String?
        var v4Prefix: Int?
        var v6: [String] = []
        var mac: String?
    }

    static func interfaces()
        -> [InterfaceInfo] {
        var head: UnsafeMutablePointer<
            ifaddrs>?
        guard getifaddrs(&head) == 0,
              let first = head else {
            return []
        }
        defer { freeifaddrs(head) }
        var order: [String] = []
        var byName: [String: InterfaceInfo] =
            [:]
        var cursor: UnsafeMutablePointer<
            ifaddrs>? = first
        while let node = cursor {
            cursor = node.pointee.ifa_next
            let name = String(cString:
                node.pointee.ifa_name)
            guard let sa = node.pointee
                .ifa_addr else { continue }
            if byName[name] == nil {
                byName[name] = InterfaceInfo(
                    name: name,
                    flags: node.pointee
                        .ifa_flags)
                order.append(name)
            }
            let family = sa.pointee.sa_family
            if family == sa_family_t(AF_INET) {
                let sin = sa
                    .withMemoryRebound(
                        to: sockaddr_in.self,
                        capacity: 1) {
                        $0.pointee
                    }
                var addr = sin.sin_addr
                var buffer = [CChar](
                    repeating: 0, count: 64)
                inet_ntop(AF_INET, &addr,
                          &buffer,
                          socklen_t(
                            buffer.count))
                byName[name]?.v4 = String(
                    cString: buffer)
                if let maskAddr = node.pointee
                    .ifa_netmask {
                    let mask = maskAddr
                        .withMemoryRebound(
                            to: sockaddr_in
                                .self,
                            capacity: 1) {
                            $0.pointee
                        }
                    var bits = mask.sin_addr
                        .s_addr.bigEndian
                    var count = 0
                    while bits != 0 {
                        count += Int(
                            bits & 1)
                        bits >>= 1
                    }
                    byName[name]?.v4Prefix =
                        count
                }
            } else if family
                == sa_family_t(AF_INET6) {
                let sin = sa
                    .withMemoryRebound(
                        to: sockaddr_in6.self,
                        capacity: 1) {
                        $0.pointee
                    }
                var addr = sin.sin6_addr
                var buffer = [CChar](
                    repeating: 0, count: 128)
                inet_ntop(AF_INET6, &addr,
                          &buffer,
                          socklen_t(
                            buffer.count))
                let text = String(
                    cString: buffer)
                if byName[name]?.v6
                    .contains(text) != true {
                    byName[name]?.v6
                        .append(text)
                }
            } else if family
                == sa_family_t(AF_LINK) {
                let raw = UnsafeRawPointer(sa)
                let nlen = Int(
                    raw.load(fromByteOffset: 5,
                             as: UInt8.self))
                let alen = Int(
                    raw.load(fromByteOffset: 6,
                             as: UInt8.self))
                if alen == 6 {
                    var bytes: [UInt8] = []
                    for i in 0..<6 {
                        bytes.append(
                            raw.load(
                                fromByteOffset:
                                    8 + nlen + i,
                                as: UInt8
                                    .self))
                    }
                    byName[name]?.mac =
                        bytes.map {
                            String(format:
                                "%02x", $0)
                        }.joined(
                            separator: ":")
                }
            }
        }
        return order.compactMap {
            byName[$0]
        }.filter {
            $0.v4 != nil || !$0.v6.isEmpty
        }
    }

    static func ifconfig(
        emit: @escaping BlacksiteEmit) {
        let infos = interfaces()
        if infos.isEmpty {
            emit(L("no interfaces with addresses."), .err)
            return
        }
        for info in infos {
            var words: [String] = []
            if info.flags & UInt32(IFF_UP)
                != 0 { words.append("up") }
            if info.flags & UInt32(
                IFF_RUNNING) != 0 {
                words.append("running")
            }
            if info.flags & UInt32(
                IFF_LOOPBACK) != 0 {
                words.append("loopback")
            }
            emit("\(info.name) — "
                 + words.joined(
                    separator: " · "), .ok)
            if let v4 = info.v4 {
                emit("  inet \(v4)"
                     + (info.v4Prefix.map {
                        "/\($0)" } ?? ""),
                     .out)
            }
            for v6 in info.v6 {
                emit(String(format: L("  inet6 %@"), String(describing: v6)), .out)
            }
            if let mac = info.mac {
                emit("  ether \(mac)"
                     + (mac
                        == "02:00:00:00:00:00"
                        ? " (the real one is "
                          + "withheld by iOS)"
                        : ""), .sys)
            }
        }
    }

    /// The primary outward IPv4, for
    /// hostname and friends.
    static func primaryIPv4() -> String? {
        let infos = interfaces()
        if let en0 = infos.first(where: {
            $0.name == "en0" }), let v4 =
            en0.v4 {
            return v4
        }
        return infos.first {
            $0.v4 != nil
                && $0.name != "lo0"
        }?.v4
    }

    // MARK: arp / netstat / hostname

    static func arp(
        emit: @escaping BlacksiteEmit) {
        emit(L("the neighborhood board is this house's arp table — iOS keeps the system's own from apps."), .sys)
        let neighbors = NeighborhoodStore
            .shared.neighbors.sorted {
                ipSortKey($0.ip)
                    .lexicographicallyPrecedes(
                        ipSortKey($1.ip))
            }
        if neighbors.isEmpty {
            emit(L("the board is empty — nothing has been seen yet."), .err)
            return
        }
        for neighbor in neighbors {
            var line = "\(neighbor.ip) — "
                + neighbor.displayName
            if !neighbor.ports.isEmpty {
                line += " · answered on "
                    + neighbor.ports.map(
                        String.init).joined(
                        separator: ", ")
            }
            emit(line, .out)
            emit("  "
                 + neighbor.lastSeenLine,
                 .sys)
        }
    }

    static func ipSortKey(_ ip: String)
        -> [Int] {
        ip.split(separator: ".").map {
            Int($0) ?? 0
        }
    }

    static func netstat(
        emit: @escaping BlacksiteEmit) {
        emit(L("iOS shows no app the system's socket table — here is this house's own."),
             .sys)
        let defaults =
            UserDefaults.standard
        let tcp = defaults.string(
            forKey: "serveTcpPort")
            ?? "9000"
        let udp = defaults.string(
            forKey: "serveUdpPort")
            ?? "9001"
        let http = defaults.string(
            forKey: "serveHttpPort")
            ?? "8080"
        let running = SkelliCenter.shared
            .mouth?.serveRunning ?? false
        let state = running
            ? "standing" : "dark"
        emit(String(format: L("tcp %@ — serve door, %@"), String(describing: tcp), String(describing: state)), running ? .ok : .out)
        emit(String(format: L("udp %@ — serve door, %@"), String(describing: udp), String(describing: state)), running ? .ok : .out)
        emit(String(format: L("http %@ — serve door, %@"), String(describing: http), String(describing: state)), running ? .ok : .out)
        let board = ProcessBoard.shared
        if board.active.isEmpty {
            emit(L("no live wires in the house right now."), .sys)
        }
        for entry in board.active {
            emit("● \(entry.label) — "
                 + entry.detail, .out)
        }
        if let ip = primaryIPv4() {
            emit(String(format: L("this phone: %@ (see ifconfig)"), String(describing: ip)), .sys)
        }
    }

    static func hostname(
        emit: @escaping BlacksiteEmit) {
        emit(ProcessInfo.processInfo
            .hostName, .out)
        if let ip = primaryIPv4() {
            emit(String(format: L("answering at %@ on the local wire."), String(describing: ip)), .sys)
        }
    }
}
