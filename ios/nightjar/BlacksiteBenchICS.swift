import Foundation
import Network

// BlacksiteBenchICS — the bench, wave
// six (fix-wave: the industrial grid).
// Thirty-eight engines for the plant
// floor: power and substations, oil
// and gas, water, machine tools,
// process plants, buildings, meters,
// and the serial gateways that stitch
// them together. The doctrine here is
// STRICTER than anywhere else on the
// bench, because this gear turns
// physical processes: every byte
// these engines send is a published
// identification or read function of
// its protocol — a nameplate read, a
// device-identification function, a
// discovery handshake. Nothing here
// writes a coil or a register, starts
// or stops a PLC, operates a breaker,
// or changes any state beyond the
// session handshakes the standards
// themselves publish for readers.
// Where a family's identification
// frame could not be verified
// byte-for-byte against its standard,
// the engine degrades honestly — it
// connects, listens, and SAYS that
// its read is not claimed — rather
// than shipping hand-waved bytes.
// Identifications are reported as
// what the device SAYS it is: a
// nameplate is a claim, read aloud.

/// One line of bench output: the text
/// and the colour of its saying.
typealias ICSLine = (
    text: String,
    kind: BlacksiteShell.Line.Kind)

extension BlacksiteBench {

    // MARK: shared plumbing

    /// Wave six speaks through the
    /// house emit; a kindless call
    /// reads .out.
    static func icsSay(
        _ emit: BlacksiteEmit,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    /// Print a core's whole ledger.
    static func icsPrint(
        _ emit: BlacksiteEmit,
        _ lines: [ICSLine]) {
        for line in lines {
            icsSay(emit, line.text,
                   line.kind)
        }
    }

    /// host[:port] split for the wire
    /// engines: resolves the name.
    static func icsResolve(
        _ target: String,
        _ defaultPort: Int)
        -> (host: String, ip: String,
            port: UInt16)? {
        var host = target
        var port = defaultPort
        if let colon = target
            .lastIndex(of: ":"),
           let p = Int(target[
                target.index(
                    after: colon)...]),
           (1...65535).contains(p) {
            host = String(target[..<colon])
            port = p
        }
        guard !host.isEmpty,
              let resolved = BlacksiteNet
                .resolve4(host) else {
            return nil
        }
        return (host, resolved.ip,
                UInt16(clamping: port))
    }

    /// A connected BSD stream socket,
    /// or nil. The caller closes it.
    static func icsSocket(
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
    static func icsReadExact(
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
    static func icsSendAll(
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

    /// Read whatever arrives within the
    /// window, up to the cap — the
    /// shape of a greeting read, where
    /// the far end speaks first and
    /// then waits.
    static func icsAvailable(
        _ fd: Int32, seconds: Double,
        cap: Int) -> [UInt8] {
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 1.0)
        var out: [UInt8] = []
        let deadline = Date()
            .addingTimeInterval(seconds)
        while out.count < cap,
              Date() < deadline {
            var chunk = [UInt8](
                repeating: 0,
                count: min(8192,
                           cap - out.count))
            let got = recv(fd, &chunk,
                           chunk.count, 0)
            if got > 0 {
                out.append(contentsOf:
                    chunk[0..<got])
            } else if !out.isEmpty {
                break
            }
        }
        BetafischTap.shared.record(
            fd: fd, outbound: false, bytes: out)
        return out
    }

    /// One UDP question and whatever
    /// answer comes home inside the
    /// window. A zero-length packet is
    /// legal: it carries no invented
    /// protocol bytes at all.
    static func icsUDPExchange(
        ip: String, port: UInt16,
        packet: [UInt8],
        wait: Double, cap: Int)
        -> [UInt8]? {
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: wait)
        var dest = BlacksiteNet.sockaddrIn(
            ip: ip, port: port)
        var dummy: UInt8 = 0
        let sent = withUnsafeMutablePointer(
            to: &dest) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                packet.isEmpty
                    ? sendto(fd, &dummy, 0,
                             0, sa,
                             socklen_t(
                                MemoryLayout<
                                    sockaddr_in>
                                    .size))
                    : packet
                        .withUnsafeBufferPointer {
                            buf in
                            sendto(
                                fd,
                                buf.baseAddress,
                                packet.count,
                                0, sa,
                                socklen_t(
                                    MemoryLayout<
                                        sockaddr_in>
                                        .size))
                        }
            }
        }
        guard sent >= 0 else { return nil }
        BetafischTap.shared.recordDatagram(
            fd: fd, remoteIP: ip,
            remotePort: Int(port),
            outbound: true, payload: packet,
            ipProto: 17)
        var buffer = [UInt8](
            repeating: 0, count: cap)
        let got = recv(fd, &buffer,
                       buffer.count, 0)
        guard got > 0 else { return nil }
        let answer = Array(buffer[0..<got])
        BetafischTap.shared.recordDatagram(
            fd: fd, remoteIP: ip,
            remotePort: Int(port),
            outbound: false, payload: answer,
            ipProto: 17)
        return answer
    }

    /// One HTTP(S) fetch through the
    /// house web session — the road
    /// the other waves ride.
    static func icsFetch(
        _ url: URL,
        accept: String? = nil)
        -> (Data, HTTPURLResponse)? {
        let (session, _) = BlacksitePentest
            .webSession(follow: true)
        defer {
            session.invalidateAndCancel()
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(
            "blacksite/11.0 (nightjar)",
            forHTTPHeaderField: "User-Agent")
        if let accept = accept {
            request.setValue(
                accept,
                forHTTPHeaderField: "Accept")
        }
        guard let (data, http) =
            BlacksitePentest.syncFetch(
                session, request),
              let http = http else {
            return nil
        }
        return (data, http)
    }

    // MARK: byte readers

    static func icsU16BE(
        _ b: [UInt8], _ o: Int) -> Int {
        guard o + 1 < b.count else {
            return 0
        }
        return Int(b[o]) << 8 | Int(b[o + 1])
    }

    static func icsU16LE(
        _ b: [UInt8], _ o: Int) -> Int {
        guard o + 1 < b.count else {
            return 0
        }
        return Int(b[o]) | Int(b[o + 1]) << 8
    }

    static func icsU32BE(
        _ b: [UInt8], _ o: Int) -> Int {
        guard o + 3 < b.count else {
            return 0
        }
        return Int(b[o]) << 24
            | Int(b[o + 1]) << 16
            | Int(b[o + 2]) << 8
            | Int(b[o + 3])
    }

    static func icsU32LE(
        _ b: [UInt8], _ o: Int) -> Int {
        guard o + 3 < b.count else {
            return 0
        }
        return Int(b[o])
            | Int(b[o + 1]) << 8
            | Int(b[o + 2]) << 16
            | Int(b[o + 3]) << 24
    }

    /// Bytes as the device printed
    /// them: the printable stretches,
    /// cleaned of their padding.
    static func icsClean(
        _ b: ArraySlice<UInt8>) -> String {
        var bytes = Array(b)
        while bytes.last == 0
                || bytes.last == 0x20 {
            bytes.removeLast()
        }
        while bytes.first == 0x20 {
            bytes.removeFirst()
        }
        return String(bytes: bytes,
                      encoding: .utf8)
            ?? String(bytes: bytes,
                      encoding: .ascii)
            ?? ""
    }

    /// Every printable run of at
    /// least minLen characters.
    static func icsRuns(
        _ b: [UInt8],
        minLen: Int = 4) -> [String] {
        var out: [String] = []
        var cur: [UInt8] = []
        func flush() {
            if cur.count >= minLen {
                out.append(String(
                    bytes: cur,
                    encoding: .ascii) ?? "")
            }
            cur = []
        }
        for byte in b {
            if byte >= 0x20 && byte < 0x7F {
                cur.append(byte)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    static func icsHex(
        _ b: ArraySlice<UInt8>) -> String {
        b.map {
            String(format: "%02x", $0)
        }.joined(separator: " ")
    }

    // MARK: checksums (each verified
    // against its catalogue check
    // value before this file shipped)

    /// CRC-16/DNP (IEEE 1815): poly
    /// 0x3D65 reflected, seeded 0, the
    /// result inverted for the wire.
    /// Check value: "123456789" ->
    /// 0xEA82.
    static func icsCRCDNP(
        _ b: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in b {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA6BC
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF
    }

    /// CRC-16/MODBUS: poly 0x8005
    /// reflected, seeded all-ones.
    /// Check value: 0x4B37.
    static func icsCRCModbus(
        _ b: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in b {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    /// CRC-CCITT (C37.118): poly
    /// 0x1021, seeded all-ones, no
    /// final inversion. Check value:
    /// 0x29B1.
    static func icsCRCCCITT(
        _ b: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in b {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    /// The shared MBAP head of the
    /// Modbus/TCP family.
    static func icsMBAP(
        length: Int, unit: UInt8 = 1)
        -> [UInt8] {
        [0x00, 0x01, 0x00, 0x00,
         UInt8((length >> 8) & 0xFF),
         UInt8(length & 0xFF), unit]
    }

    /// The degraded knock, shared by
    /// every family whose identity
    /// frame could not be verified
    /// byte-for-byte: connect, listen
    /// for whatever the device
    /// volunteers, and say plainly
    /// that no identification read is
    /// claimed. No invented bytes are
    /// ever sent.
    static func icsConnectOnlyCore(
        verb: String, host: String,
        ip: String, port: UInt16,
        light: Bool,
        note: String) -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 3.5)
        else {
            return light ? [] : [
                (String(format: L("%@: nothing answers on its door at %@."), verb, host), .out),
            ]
        }
        defer { close(fd) }
        let heard = icsAvailable(
            fd, seconds: light ? 0.8 : 1.6,
            cap: 4096)
        var lines: [ICSLine] = []
        if heard.isEmpty {
            lines.append((
                String(format: L("%@: the door at %@ opens to a connection and volunteers nothing."), verb, host),
                .sys))
        } else {
            let runs = icsRuns(heard)
            if runs.isEmpty {
                lines.append((
                    String(format: L("%@: the door at %@ opens and speaks %lld bytes no reader here can print: %@"), verb, host, Int64(heard.count), icsHex(heard.prefix(24))),
                    .sys))
            } else {
                lines.append((
                    String(format: L("%@: the door at %@ volunteers this before any question: %@"), verb, host, runs.joined(separator: " · ")),
                    .sys))
            }
        }
        if !note.isEmpty {
            lines.append((note, .out))
        }
        return lines
    }

    /// The UDP shape of the same
    /// honesty: an empty datagram —
    /// zero protocol bytes, nothing
    /// invented — and whatever the
    /// wire says back. Light mode is
    /// the census's shape: silence
    /// yields nothing, an answer
    /// yields its one presence line.
    static func icsUDPEmptyCore(
        verb: String, host: String,
        ip: String, port: UInt16,
        light: Bool,
        note: String) -> [ICSLine] {
        let reply = icsUDPExchange(
            ip: ip, port: port,
            packet: [], wait: light
                ? 1.0 : 1.6,
            cap: 2048)
        var lines: [ICSLine] = []
        if let reply = reply,
           !reply.isEmpty {
            let runs = icsRuns(reply)
            lines.append((
                String(format: L("%@: an empty knock at %@ drew %lld bytes back: %@"), verb, host, Int64(reply.count), runs.isEmpty ? icsHex(reply.prefix(24)) : runs.joined(separator: " · ")),
                .sys))
        } else if !light {
            lines.append((
                String(format: L("%@: an empty knock at %@ drew nothing back — silence proves neither presence nor absence on UDP."), verb, host),
                .out))
        }
        if !light {
            lines.append((note, .out))
        }
        return lines
    }

    // MARK: Modbus — the identification
    // function, and nothing past it

    /// FC 43 / MEI 0x0E, Read Device
    /// Identification — the one read
    /// this wave takes from a Modbus
    /// door. No coil or register read
    /// exists anywhere in this file.
    static func icsModbusCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("modbusprobe: nothing answers on the Modbus door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        let ask = icsMBAP(length: 5)
            + [0x2B, 0x0E, 0x01, 0x00]
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 7) else {
            return light ? [] : [
                (String(format: L("modbusprobe: the door at %@ took the knock and gave nothing back."), host), .out),
            ]
        }
        let pduLen = icsU16BE(head, 4) - 1
        guard pduLen > 0,
              let pdu = icsReadExact(
                fd, pduLen) else {
            return light ? [] : [
                (String(format: L("modbusprobe: the answer from %@ broke off mid-frame."), host), .out),
            ]
        }
        if pdu.first == 0xAB {
            let code = pdu.count > 1
                ? Int64(pdu[1]) : -1
            return [
                (String(format: L("modbusprobe: %@ refuses the identification read itself (exception %lld) — a door that will not even give its name."), host, code), .ok),
            ]
        }
        guard pdu.first == 0x2B,
              pdu.count > 6 else {
            return [
                (String(format: L("modbusprobe: whatever answered at %@ is not speaking Modbus identification: %@"), host, icsHex(pdu.prefix(12))), .out),
            ]
        }
        let names: [Int: String] = [
            0: L("vendor"), 1: L("product"),
            2: L("revision"),
            3: L("vendor's door"),
            4: L("product name"),
            5: L("model name"),
            6: L("application name"),
        ]
        var facts: [String] = []
        var idx = 7
        let count = Int(pdu[6])
        var seen = 0
        while seen < count,
              idx + 1 < pdu.count {
            let oid = Int(pdu[idx])
            let len = Int(pdu[idx + 1])
            guard idx + 2 + len
                    <= pdu.count else {
                break
            }
            let value = icsClean(
                pdu[(idx + 2)..<(idx + 2 + len)])
            if !value.isEmpty {
                facts.append(String(
                    format: L("%@ %@"),
                    names[oid]
                        ?? String(format: L("object %lld"), Int64(oid)),
                    value))
            }
            idx += 2 + len
            seen += 1
        }
        if facts.isEmpty {
            return [
                (String(format: L("modbusprobe: %@ answers the identification function with an empty ledger."), host), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("modbusprobe: %@ names itself — %@."), host, facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("modbusprobe: the Modbus plane authenticates no one by design — the nameplate is had for the asking, and every control function in the protocol sits behind this same open door. The asking is all this bench does here."),
                .err))
        }
        return lines
    }

    static func modbusprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("modbusprobe: give host[:port] — modbusprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsModbusCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Siemens S7 — SZL ledgers

    /// One SZL partial-list read over
    /// an established S7 session.
    /// Returns the first element's
    /// bytes, or nil.
    static func icsS7SZL(
        _ fd: Int32, id: Int,
        index: Int, ref: Int) -> [UInt8]? {
        var ask: [UInt8] = [
            0x03, 0x00, 0x00, 0x21,
            0x02, 0xF0, 0x80,
            0x32, 0x07, 0x00, 0x00,
            UInt8((ref >> 8) & 0xFF),
            UInt8(ref & 0xFF),
            0x00, 0x08, 0x00, 0x08,
            0x00, 0x01, 0x12, 0x04,
            0x11, 0x44, 0x01, 0x00,
            0xFF, 0x09, 0x00, 0x04,
            UInt8((id >> 8) & 0xFF),
            UInt8(id & 0xFF),
            UInt8((index >> 8) & 0xFF),
            UInt8(index & 0xFF),
        ]
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 4) else {
            return nil
        }
        let total = icsU16BE(head, 2)
        guard total > 4,
              let rest = icsReadExact(
                fd, total - 4) else {
            return nil
        }
        ask = head + rest
        guard ask.count >= 19 else {
            return nil
        }
        let paramLen = icsU16BE(ask, 13)
        let dataOff = 19 + paramLen
        guard dataOff + 12 <= ask.count,
              ask[dataOff] == 0xFF else {
            return nil
        }
        let elemLen = icsU16BE(
            ask, dataOff + 8)
        let start = dataOff + 12
        guard elemLen > 0,
              start + elemLen <= ask.count
        else {
            return nil
        }
        return Array(ask[start..<(start
            + elemLen)])
    }

    static func icsS7Core(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("s7probe: nothing answers on the ISO-on-TCP door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // COTP connection request,
        // PG TSAP to rack 0, slot 2.
        let cr: [UInt8] = [
            0x03, 0x00, 0x00, 0x16,
            0x11, 0xE0, 0x00, 0x00,
            0x00, 0x01, 0x00, 0xC0,
            0x01, 0x0A, 0xC1, 0x02,
            0x01, 0x00, 0xC2, 0x02,
            0x01, 0x02,
        ]
        guard icsSendAll(fd, cr),
              let chead = icsReadExact(
                fd, 4),
              let crest = icsReadExact(
                fd, max(0, icsU16BE(
                    chead, 2) - 4))
        else {
            return light ? [] : [
                (String(format: L("s7probe: the door at %@ would not complete the COTP handshake."), host), .out),
            ]
        }
        let cfull = chead + crest
        guard cfull.count > 5,
              cfull[5] == 0xD0 else {
            return light ? [] : [
                (String(format: L("s7probe: COTP refused the knock at %@ — the door is not an S7 front, or it is shut to this TSAP."), host), .out),
            ]
        }
        // S7 communication setup.
        let setup: [UInt8] = [
            0x03, 0x00, 0x00, 0x19,
            0x02, 0xF0, 0x80,
            0x32, 0x01, 0x00, 0x00,
            0x00, 0x01, 0x00, 0x08,
            0x00, 0x00, 0xF0, 0x00,
            0x00, 0x01, 0x00, 0x01,
            0x03, 0xC0,
        ]
        guard icsSendAll(fd, setup),
              let shead = icsReadExact(
                fd, 4),
              let srest = icsReadExact(
                fd, max(0, icsU16BE(
                    shead, 2) - 4))
        else {
            return [
                (String(format: L("s7probe: %@ confirms the transport but not the S7 session — an RFC 1006 door, not proven to be a CPU."), host), .out),
            ]
        }
        let sfull = shead + srest
        guard sfull.count > 8,
              sfull[7] == 0x32 else {
            return [
                (String(format: L("s7probe: %@ answers the transport and something else above it — not the S7 session shape."), host), .out),
            ]
        }
        var lines: [ICSLine] = []
        if let elem = icsS7SZL(
            fd, id: 0x0011, index: 1,
            ref: 2), elem.count >= 22 {
            let mlfb = icsClean(
                elem[2..<22])
            var runs = icsRuns(
                Array(elem.dropFirst(22)))
            runs = runs.filter {
                $0 != mlfb
            }
            var text = String(
                format: L("s7probe: the CPU at %@ gives its module as %@."), host, mlfb.isEmpty ? L("an unread plate") : mlfb)
            if !runs.isEmpty {
                text += " " + String(
                    format: L("Also on the plate: %@."), runs.joined(separator: " · "))
            }
            lines.append((text, .sys))
        }
        if let elem = icsS7SZL(
            fd, id: 0x0011, index: 6,
            ref: 3), elem.count >= 5 {
            let a = Int64(elem[2])
            let b = Int64(elem[3])
            let c = Int64(elem[4])
            if a > 0, a < 100, b < 100,
               c < 100 {
                lines.append((
                    String(format: L("s7probe: firmware V%lld.%lld.%lld stands on the module, as its ledger prints it."), a, b, c),
                    .out))
            } else {
                let runs = icsRuns(elem)
                if !runs.isEmpty {
                    lines.append((
                        String(format: L("s7probe: the firmware line on the plate reads: %@."), runs.joined(separator: " · ")),
                        .out))
                }
            }
        }
        if let elem = icsS7SZL(
            fd, id: 0x0232, index: 1,
            ref: 4), elem.count >= 4 {
            let level = icsU16BE(elem, 2)
            let word: String
            let kind: BlacksiteShell
                .Line.Kind
            switch level {
            case 1:
                word = L("no protection stands — program and data lie open to any S7 caller")
                kind = .err
            case 2:
                word = L("write protection — the program may be read by any caller, changed by few")
                kind = .out
            case 3:
                word = L("read and write protection — the strongest word this ledger carries")
                kind = .ok
            default:
                word = String(format: L("a protection word this reader cannot grade (%lld)"), Int64(level))
                kind = .out
            }
            lines.append((
                String(format: L("s7probe: protection level %lld stands in its ledger — %@."), Int64(level), word),
                kind))
        }
        if lines.isEmpty {
            return [
                (String(format: L("s7probe: the S7 session stands at %@, but its ledgers would not open to this knock."), host), .out),
            ]
        }
        if !light {
            lines.append((
                L("s7probe: classic S7Comm asks no name and no password for these reads — the identification of every CPU on the wire rides this same unsealed road."),
                .out))
        }
        return lines
    }

    static func s7probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 102)
            else {
                icsSay(emit, L("s7probe: give host[:port] — s7probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsS7Core(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: IEC 61850 — the honest knock

    /// The MMS Identify read rides an
    /// OSI presentation negotiation
    /// whose bytes this bench could
    /// not verify frame-for-frame
    /// against ISO 9506 — so it is not
    /// shipped. What IS verified, and
    /// sent, is the RFC 1006 knock on
    /// the MMS TSAP: the substation
    /// door's own front step.
    static func icsIEC61850Core(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("iec61850probe: nothing answers on the RFC 1006 door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        let cr: [UInt8] = [
            0x03, 0x00, 0x00, 0x16,
            0x11, 0xE0, 0x00, 0x00,
            0x00, 0x01, 0x00, 0xC0,
            0x01, 0x0A, 0xC1, 0x02,
            0x00, 0x01, 0xC2, 0x02,
            0x00, 0x01,
        ]
        guard icsSendAll(fd, cr),
              let head = icsReadExact(
                fd, 4),
              let rest = icsReadExact(
                fd, max(0, icsU16BE(
                    head, 2) - 4))
        else {
            return light ? [] : [
                (String(format: L("iec61850probe: the door at %@ would not complete the COTP handshake."), host), .out),
            ]
        }
        let full = head + rest
        guard full.count > 5,
              full[5] == 0xD0 else {
            return light ? [] : [
                (String(format: L("iec61850probe: COTP refused the MMS TSAP at %@ — no MMS front stands here, or it is shut."), host), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("iec61850probe: an RFC 1006 door at %@ accepts the MMS TSAP (00 01) — the substation dialect's front step stands open."), host), .sys),
        ]
        if !light {
            lines.append((
                L("iec61850probe: the full MMS Identify read is NOT shipped — its presentation-negotiation bytes could not be verified frame-for-frame, and this bench does not hand-wave bytes. Proven: the open door, on the MMS address. Unproven, and unclaimed: everything past it."),
                .out))
        }
        return lines
    }

    static func iec61850probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 102)
            else {
                icsSay(emit, L("iec61850probe: give host[:port] — iec61850probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsIEC61850Core(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: EtherNet/IP — List Identity

    static func icsENIPCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("enipprobe: nothing answers on the EtherNet/IP door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        var ask = [UInt8](
            repeating: 0, count: 24)
        ask[0] = 0x63
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 24) else {
            return light ? [] : [
                (String(format: L("enipprobe: the door at %@ took the knock and gave nothing back."), host), .out),
            ]
        }
        let len = icsU16LE(head, 2)
        guard len >= 6,
              let body = icsReadExact(
                fd, len) else {
            return light ? [] : [
                (String(format: L("enipprobe: the answer from %@ broke off mid-frame."), host), .out),
            ]
        }
        // body: item count, then the
        // identity item (type 0x000C).
        guard body.count >= 6,
              icsU16LE(body, 2) == 0x000C
        else {
            return [
                (String(format: L("enipprobe: whatever answered at %@ did not return an identity item: %@"), host, icsHex(body.prefix(16))), .out),
            ]
        }
        let data = Array(body.dropFirst(6))
        guard data.count >= 33 else {
            return [
                (String(format: L("enipprobe: the identity item from %@ arrived short — %lld bytes of nameplate."), host, Int64(data.count)), .out),
            ]
        }
        let vendor = icsU16LE(data, 18)
        let dtype = icsU16LE(data, 20)
        let prod = icsU16LE(data, 22)
        let revA = Int64(data[24])
        let revB = Int64(data[25])
        let serial = icsU32LE(data, 28)
        let nameLen = Int(data[32])
        let name = data.count >= 33 + nameLen
            ? icsClean(
                data[33..<(33 + nameLen)])
            : ""
        let typeWord: String
        switch dtype {
        case 0:
            typeWord = L("a generic device")
        case 2:
            typeWord = L("an AC drive")
        case 12:
            typeWord = L("a communications adapter")
        case 14:
            typeWord = L("a programmable logic controller")
        default:
            typeWord = String(
                format: L("device type %lld"),
                Int64(dtype))
        }
        var lines: [ICSLine] = [
            (String(format: L("enipprobe: %@ answers List Identity — %@, vendor %lld, product %lld, revision %lld.%lld, serial %lld%@."), host, typeWord, Int64(vendor), Int64(prod), revA, revB, Int64(serial), name.isEmpty ? "" : String(format: L(", named %@"), name)), .sys),
        ]
        if !light {
            lines.append((
                L("enipprobe: EtherNet/IP publishes this nameplate to any caller by design — the same answer rides the wire for whoever asks, no name given in return."),
                .out))
        }
        return lines
    }

    static func enipprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 44818)
            else {
                icsSay(emit, L("enipprobe: give host[:port] — enipprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsENIPCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Allen-Bradley CSP — degraded

    static func pcccprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 2222)
            else {
                icsSay(emit, L("pcccprobe: give host[:port] — pcccprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "pcccprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("pcccprobe: the legacy CSP diagnostic-status frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — only the door's own state, exactly as observed.")))
        }
    }

    // MARK: DNP3 — link status, then
    // the attribute ledger

    static func icsDNP3Frame(
        ctrl: UInt8,
        user: [UInt8]) -> [UInt8] {
        var hdr: [UInt8] = [
            0x05, 0x64,
            UInt8(5 + user.count), ctrl,
            0x01, 0x00, 0x64, 0x00,
        ]
        let hcrc = icsCRCDNP(hdr)
        hdr.append(UInt8(hcrc & 0xFF))
        hdr.append(UInt8(hcrc >> 8))
        var frame = hdr
        var rest = user
        while !rest.isEmpty {
            let chunk = Array(
                rest.prefix(16))
            rest = Array(
                rest.dropFirst(16))
            let c = icsCRCDNP(chunk)
            frame.append(contentsOf: chunk)
            frame.append(UInt8(c & 0xFF))
            frame.append(UInt8(c >> 8))
        }
        return frame
    }

    /// Strip a received frame back to
    /// its user bytes, block by block.
    static func icsDNP3User(
        _ frame: [UInt8]) -> [UInt8] {
        guard frame.count > 10,
              frame[0] == 0x05,
              frame[1] == 0x64 else {
            return []
        }
        var user: [UInt8] = []
        var pos = 10
        while pos < frame.count {
            let remaining = frame.count
                - pos
            let take = min(16,
                           remaining - 2)
            guard take > 0 else { break }
            user.append(contentsOf:
                frame[pos..<(pos + take)])
            pos += take + 2
        }
        return user
    }

    static func icsDNP3Core(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("dnp3probe: nothing answers on the DNP3 door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // Request Link Status (FC 9),
        // asked of link address 1.
        let ls = icsDNP3Frame(
            ctrl: 0xC9, user: [])
        guard icsSendAll(fd, ls) else {
            return light ? [] : [
                (String(format: L("dnp3probe: the knock at %@ never left."), host), .out),
            ]
        }
        let heard = icsAvailable(
            fd, seconds: light ? 1.2 : 2.2,
            cap: 1024)
        guard heard.count >= 10,
              heard[0] == 0x05,
              heard[1] == 0x64 else {
            return light ? [] : [
                (String(format: L("dnp3probe: no link answer from %@ at link address 1 — the outstation may live at another link address, and addresses are not swept."), host), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("dnp3probe: the link at %@ answers at address 1 — a live outstation front."), host), .sys),
        ]
        if light { return lines }
        // One attribute read: group 0,
        // variation 254 (the device
        // attribute ledger), qualifier
        // 0x06 — all objects.
        let read = icsDNP3Frame(
            ctrl: 0xD3,
            user: [0xC0, 0xC0, 0x01,
                   0x00, 0xFE, 0x06])
        guard icsSendAll(fd, read) else {
            return lines
        }
        let answer = icsAvailable(
            fd, seconds: 3, cap: 8192)
        let user = icsDNP3User(answer)
        guard user.count >= 5 else {
            lines.append((
                L("dnp3probe: the attribute ledger would not open to the same knock — link proven, attributes unclaimed."),
                .out))
            return lines
        }
        // user: transport, app control,
        // function 0x81, then the IIN.
        let iin1 = user[3]
        let iin2 = user[4]
        var words: [String] = []
        let bits1: [(UInt8, String)] = [
            (0x01, L("a broadcast was received")),
            (0x02, L("class 1 events wait")),
            (0x04, L("class 2 events wait")),
            (0x08, L("class 3 events wait")),
            (0x10, L("it asks for time sync")),
            (0x20, L("local control stands")),
            (0x40, L("device trouble is flagged")),
            (0x80, L("it has restarted")),
        ]
        for (bit, word) in bits1
        where iin1 & bit != 0 {
            words.append(word)
        }
        let bits2: [(UInt8, String)] = [
            (0x01, L("a function went unsupported")),
            (0x02, L("an object went unknown")),
            (0x04, L("a parameter erred")),
            (0x08, L("an event buffer overflowed")),
            (0x10, L("an operation was already running")),
            (0x20, L("the configuration reads corrupt")),
        ]
        for (bit, word) in bits2
        where iin2 & bit != 0 {
            words.append(word)
        }
        if words.isEmpty {
            lines.append((
                L("dnp3probe: the IIN stands clean — no events wait, no trouble is flagged."),
                .out))
        } else {
            lines.append((
                String(format: L("dnp3probe: its IIN says — %@."), words.joined(separator: ", ")),
                .out))
        }
        let attrs = icsRuns(
            Array(user.dropFirst(5)),
            minLen: 3)
        if !attrs.isEmpty {
            lines.append((
                String(format: L("dnp3probe: the attribute ledger offers — %@."), attrs.joined(separator: " · ")),
                .sys))
        }
        lines.append((
            L("dnp3probe: classic DNP3 authenticates no one — this ledger is published to any master that asks. Secure Authentication, where a plant runs it, is a further conversation this knock does not begin."),
            .err))
        return lines
    }

    static func dnp3probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 20000)
            else {
                icsSay(emit, L("dnp3probe: give host[:port] — dnp3probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsDNP3Core(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: BACnet/IP — Who-Is, then
    // the device object, read
    // property by property

    /// Walk one BACnet tag header at
    /// pos; returns (tag number,
    /// value start) or nil.
    static func icsBACTag(
        _ b: [UInt8], _ pos: inout Int)
        -> (num: Int, len: Int)? {
        guard pos < b.count else {
            return nil
        }
        let head = b[pos]
        pos += 1
        let num = Int(head >> 4)
        var len = Int(head & 0x07)
        if len == 0x07 {
            guard pos < b.count else {
                return nil
            }
            len = Int(b[pos])
            pos += 1
            if len == 0xFE {
                guard pos + 1 < b.count
                else { return nil }
                len = icsU16BE(b, pos)
                pos += 2
            } else if len == 0xFF {
                guard pos + 3 < b.count
                else { return nil }
                len = icsU32BE(b, pos)
                pos += 4
            }
        }
        return (num, len)
    }

    /// Read one device-object property
    /// and render its value plainly.
    static func icsBACReadProp(
        ip: String, port: UInt16,
        objid: Int, invoke: UInt8,
        prop: UInt8) -> String? {
        var body: [UInt8] = [
            0x01, 0x00, 0x00, 0x05,
            invoke, 0x0C, 0x0C,
        ]
        body.append(UInt8(
            (objid >> 24) & 0xFF))
        body.append(UInt8(
            (objid >> 16) & 0xFF))
        body.append(UInt8(
            (objid >> 8) & 0xFF))
        body.append(UInt8(objid & 0xFF))
        body.append(0x19)
        body.append(prop)
        var packet: [UInt8] = [
            0x81, 0x0A,
            UInt8(((body.count + 4) >> 8)
                    & 0xFF),
            UInt8((body.count + 4) & 0xFF),
        ]
        packet.append(contentsOf: body)
        guard let reply = icsUDPExchange(
            ip: ip, port: port,
            packet: packet, wait: 1.6,
            cap: 4096),
              reply.count > 6 else {
            return nil
        }
        // BVLL + NPDU walk.
        var pos = 4
        guard reply[pos] == 0x01 else {
            return nil
        }
        let ctrl = reply[pos + 1]
        pos += 2
        if ctrl & 0x20 != 0 {
            guard pos + 2 < reply.count
            else { return nil }
            pos += 3 + Int(reply[pos + 2])
        }
        if ctrl & 0x08 != 0 {
            guard pos + 2 < reply.count
            else { return nil }
            pos += 3 + Int(reply[pos + 2])
        }
        // APDU: ComplexACK (0x30),
        // invoke, service 0x0C.
        guard pos + 2 < reply.count,
              reply[pos] & 0xF0 == 0x30,
              reply[pos + 2] == 0x0C
        else { return nil }
        pos += 3
        // [0] object id, [1] property.
        guard let t0 = icsBACTag(
                reply, &pos) else {
            return nil
        }
        pos += t0.len
        guard let t1 = icsBACTag(
                reply, &pos) else {
            return nil
        }
        pos += t1.len
        // Opening tag [3], then the
        // application-tagged value.
        guard pos < reply.count,
              reply[pos] == 0x3E else {
            return nil
        }
        pos += 1
        guard let tv = icsBACTag(
                reply, &pos),
              pos + tv.len <= reply.count
        else { return nil }
        let value = Array(
            reply[pos..<(pos + tv.len)])
        if tv.num == 7, tv.len >= 1 {
            // Character string: the
            // first byte names the
            // encoding (0 = ANSI).
            return icsClean(
                value.dropFirst())
        }
        if tv.num == 2 || tv.num == 9 {
            var n = 0
            for byte in value {
                n = n << 8 | Int(byte)
            }
            return String(n)
        }
        if tv.num == 4 {
            return icsClean(value[...])
        }
        return nil
    }

    static func icsBACnetCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        let whois: [UInt8] = [
            0x81, 0x0A, 0x00, 0x08,
            0x01, 0x00, 0x10, 0x08,
        ]
        guard let iam = icsUDPExchange(
            ip: ip, port: port,
            packet: whois, wait: light
                ? 1.4 : 2.4,
            cap: 4096) else {
            return light ? [] : [
                (String(format: L("bacnetprobe: no I-Am came back from %@ — no BACnet device owns this knock, or it keeps its name to the broadcast road."), host), .out),
            ]
        }
        // Find the device object id:
        // the C4 application tag in
        // the I-Am APDU.
        var objid: Int?
        var scan = 4
        while scan + 4 < iam.count {
            if iam[scan] == 0xC4 {
                objid = icsU32BE(iam, scan + 1)
                break
            }
            scan += 1
        }
        guard let oid = objid else {
            return [
                (String(format: L("bacnetprobe: something at %@ answered in BACnet's shape but named no device object: %@"), host, icsHex(iam.prefix(24))), .out),
            ]
        }
        let instance = oid & 0x3FFFFF
        var lines: [ICSLine] = [
            (String(format: L("bacnetprobe: device %lld at %@ raises its hand to a Who-Is."), Int64(instance), host), .sys),
        ]
        if light { return lines }
        var facts: [String] = []
        let props: [(UInt8, String)] = [
            (77, L("names itself")),
            (121, L("vendor")),
            (70, L("model")),
            (44, L("firmware")),
        ]
        var invoke: UInt8 = 1
        for (prop, label) in props {
            if let value = icsBACReadProp(
                ip: ip, port: port,
                objid: oid, invoke: invoke,
                prop: prop),
               !value.isEmpty {
                facts.append(String(
                    format: L("%@ %@"),
                    label, value))
            }
            invoke += 1
        }
        if !facts.isEmpty {
            lines.append((
                String(format: L("bacnetprobe: its device object reads — %@."), facts.joined(separator: ", ")),
                .sys))
        }
        lines.append((
            L("bacnetprobe: classic BACnet/IP authenticates no one — Who-Is is answered and the device object is read by any caller on the wire. (BACnet/SC seals this road; nothing here spoke it.)"),
            .err))
        return lines
    }

    static func bacnetprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 47808)
            else {
                icsSay(emit, L("bacnetprobe: give host[:port] — bacnetprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsBACnetCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: OPC UA — HEL, an open
    // channel, and the endpoints ledger

    /// Read one whole UA binary
    /// message (header + body).
    static func icsUARead(
        _ fd: Int32) -> [UInt8]? {
        guard let head = icsReadExact(
            fd, 8) else { return nil }
        let size = icsU32LE(head, 4)
        guard size >= 8, size <= 1 << 20
        else { return nil }
        if size == 8 { return head }
        guard let rest = icsReadExact(
            fd, size - 8) else {
            return nil
        }
        return head + rest
    }

    static func icsUAString(
        _ s: String?) -> [UInt8] {
        guard let s = s else {
            return [0xFF, 0xFF, 0xFF, 0xFF]
        }
        let bytes = Array(s.utf8)
        var out: [UInt8] = [
            UInt8(bytes.count & 0xFF),
            UInt8((bytes.count >> 8)
                    & 0xFF),
            0x00, 0x00,
        ]
        out.append(contentsOf: bytes)
        return out
    }

    static func icsUAHeader() -> [UInt8] {
        // Null token, zero time and
        // handle, no diagnostics, no
        // audit entry, 10 s hint, empty
        // additional header.
        var out: [UInt8] = [0x00, 0x00]
        out.append(contentsOf: [UInt8](
            repeating: 0, count: 8))
        out.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        out.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        out.append(contentsOf:
            [0xFF, 0xFF, 0xFF, 0xFF])
        out.append(contentsOf:
            [0x10, 0x27, 0x00, 0x00])
        out.append(contentsOf: [0x00, 0x00])
        return out
    }

    static func icsOPCUACore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 5)
        else {
            return light ? [] : [
                (String(format: L("opcuaprobe: nothing answers on the OPC UA door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        let url = "opc.tcp://\(host):\(port)"
        var hel: [UInt8] = Array("HELF".utf8)
        hel.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        hel.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        hel.append(contentsOf:
            [0xFF, 0xFF, 0x00, 0x00])
        hel.append(contentsOf:
            [0xFF, 0xFF, 0x00, 0x00])
        hel.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        hel.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        hel.append(contentsOf:
            icsUAString(url))
        let helSize = hel.count
        hel[4] = UInt8(helSize & 0xFF)
        hel[5] = UInt8((helSize >> 8)
                        & 0xFF)
        guard icsSendAll(fd, hel),
              let ack = icsUARead(fd)
        else {
            return light ? [] : [
                (String(format: L("opcuaprobe: the door at %@ took the HEL and gave nothing back."), host), .out),
            ]
        }
        let kind = String(
            bytes: ack.prefix(3),
            encoding: .ascii) ?? ""
        if kind == "ERR" {
            var reason = ""
            if ack.count > 12 {
                let len = icsU32LE(ack, 12)
                if len > 0,
                   ack.count >= 16 + len {
                    reason = icsClean(
                        ack[16..<(16 + len)])
                }
            }
            return [
                (String(format: L("opcuaprobe: %@ refuses the HEL%@ — the door is shut to plain discovery from here."), host, reason.isEmpty ? "" : String(format: L(": %@"), reason)), .out),
            ]
        }
        guard kind == "ACK" else {
            return [
                (String(format: L("opcuaprobe: whatever answered at %@ is not speaking OPC UA binary: %@"), host, icsHex(ack.prefix(16))), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("opcuaprobe: %@ answers the OPC UA HEL — an acknowledged discovery door."), host), .sys),
        ]
        if light { return lines }
        // OpenSecureChannel, policy
        // None — the discovery channel,
        // no credentials of any kind.
        var osc: [UInt8] = Array(
            "OPNF".utf8)
        osc.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        osc.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        osc.append(contentsOf: icsUAString(
            "http://opcfoundation.org/UA/SecurityPolicy#None"))
        osc.append(contentsOf: icsUAString(nil))
        osc.append(contentsOf: icsUAString(nil))
        osc.append(contentsOf:
            [0x01, 0x00, 0x00, 0x00,
             0x01, 0x00, 0x00, 0x00])
        osc.append(contentsOf:
            [0x01, 0x00, 0xBE, 0x01])
        osc.append(contentsOf:
            icsUAHeader())
        osc.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00,
             0x01, 0x00, 0x00, 0x00])
        osc.append(contentsOf:
            [0x20, 0x00, 0x00, 0x00])
        osc.append(contentsOf: [UInt8](
            repeating: 0, count: 32))
        osc.append(contentsOf:
            [0xC0, 0x27, 0x09, 0x00])
        let oscSize = osc.count
        osc[4] = UInt8(oscSize & 0xFF)
        osc[5] = UInt8((oscSize >> 8)
                        & 0xFF)
        guard icsSendAll(fd, osc),
              let open = icsUARead(fd),
              open.count >= 20,
              String(bytes: open.prefix(3),
                     encoding: .ascii)
                == "OPN"
        else {
            lines.append((
                L("opcuaprobe: the channel would not open on the None policy — the endpoint ledger stays unclaimed from here."),
                .out))
            return lines
        }
        // Walk the asymmetric header to
        // the security token.
        var p = 12
        func skipString() -> Bool {
            guard p + 4 <= open.count
            else { return false }
            let len = icsU32LE(open, p)
            p += 4
            if len != 0xFFFFFFFF {
                p += len
            }
            return p <= open.count
        }
        guard skipString(), skipString(),
              skipString() else {
            lines.append((
                L("opcuaprobe: the channel answer from this server broke its own shape — the ledger stays unclaimed."),
                .out))
            return lines
        }
        p += 8  // sequence header
        p += 4  // type id
        p += 4  // server protocol version
        guard p + 8 <= open.count else {
            lines.append((
                L("opcuaprobe: the channel answer from this server broke its own shape — the ledger stays unclaimed."),
                .out))
            return lines
        }
        let channel = icsU32LE(open, p)
        let token = icsU32LE(open, p + 4)
        // GetEndpoints on the open
        // channel — discovery only, no
        // session is ever made.
        var gep: [UInt8] = Array(
            "MSGF".utf8)
        gep.append(contentsOf:
            [0x00, 0x00, 0x00, 0x00])
        gep.append(contentsOf: [
            UInt8(channel & 0xFF),
            UInt8((channel >> 8) & 0xFF),
            0x00, 0x00,
            UInt8(token & 0xFF),
            UInt8((token >> 8) & 0xFF),
            0x00, 0x00,
        ])
        gep.append(contentsOf:
            [0x02, 0x00, 0x00, 0x00,
             0x02, 0x00, 0x00, 0x00])
        gep.append(contentsOf:
            [0x01, 0x00, 0xAC, 0x01])
        gep.append(contentsOf:
            icsUAHeader())
        gep.append(contentsOf:
            icsUAString(url))
        gep.append(contentsOf:
            [0xFF, 0xFF, 0xFF, 0xFF])
        gep.append(contentsOf:
            [0xFF, 0xFF, 0xFF, 0xFF])
        let gepSize = gep.count
        gep[4] = UInt8(gepSize & 0xFF)
        gep[5] = UInt8((gepSize >> 8)
                        & 0xFF)
        guard icsSendAll(fd, gep) else {
            lines.append((
                L("opcuaprobe: the endpoints question never left."),
                .out))
            return lines
        }
        var raw: [UInt8] = []
        var finals = false
        while !finals,
              raw.count <= 1 << 17,
              let msg = icsUARead(fd) {
            raw.append(contentsOf: msg)
            if msg.count > 3,
               msg[3] == 0x46 {
                finals = true
            }
        }
        guard !raw.isEmpty else {
            lines.append((
                L("opcuaprobe: the channel opened, but the endpoints ledger never came — unclaimed."),
                .out))
            return lines
        }
        // Read the ledger as printed:
        // the policy addresses and the
        // endpoint addresses it names.
        let text = String(
            bytes: raw, encoding: .ascii)
            ?? ""
        var policies = Set<String>()
        var endpoints = 0
        var cursor = text.startIndex
        while let hit = text.range(
            of: "SecurityPolicy#",
            range: cursor..<text.endIndex) {
            let tail = text[hit.upperBound...]
            let name = tail.prefix {
                $0.isLetter || $0.isNumber
                    || $0 == "_"
            }
            if !name.isEmpty {
                policies.insert(
                    String(name))
            }
            cursor = hit.upperBound
        }
        cursor = text.startIndex
        while let hit = text.range(
            of: "opc.tcp://",
            range: cursor..<text.endIndex) {
            endpoints += 1
            cursor = hit.upperBound
        }
        if policies.isEmpty {
            lines.append((
                L("opcuaprobe: the ledger came home, but no security policy address stands printed in it — the offer stays ungraded."),
                .out))
            return lines
        }
        let list = policies.sorted()
            .joined(separator: ", ")
        if policies == ["None"] {
            lines.append((
                L("opcuaprobe: every endpoint offered rides SecurityPolicy#None — no signing, no encryption, for any caller. That is the critical word on this door."),
                .err))
        } else if policies.contains(
            "None") {
            lines.append((
                String(format: L("opcuaprobe: the endpoints offer %@ — and #None still stands among them, an unsealed road beside the sealed ones."), list),
                .err))
        } else {
            lines.append((
                String(format: L("opcuaprobe: the endpoints offer %@ — no bare road among them."), list),
                .ok))
        }
        if endpoints > 0 {
            lines.append((
                String(format: L("opcuaprobe: %lld endpoint address(es) stand printed in the ledger."), Int64(endpoints)),
                .out))
        }
        lines.append((
            L("opcuaprobe: discovery is the published front of OPC UA — but a server that offers #None offers its whole process to the wire, and this bench graded the offer, not the taking."),
            .out))
        return lines
    }

    static func opcuaprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 4840)
            else {
                icsSay(emit, L("opcuaprobe: give host[:port] — opcuaprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsOPCUACore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Omron FINS — data and
    // status reads only

    /// One FINS/TCP exchange: send a
    /// command frame, read the whole
    /// framed answer.
    static func icsFINSExchange(
        _ fd: Int32, frame: [UInt8])
        -> [UInt8]? {
        guard icsSendAll(fd, frame),
              let head = icsReadExact(
                fd, 8) else {
            return nil
        }
        let len = icsU32BE(head, 4)
        guard len >= 8, len <= 1 << 16,
              let rest = icsReadExact(
                fd, len) else {
            return nil
        }
        return head + rest
    }

    static func icsFINSFrame(
        clientNode: UInt8,
        serverNode: UInt8,
        command: [UInt8]) -> [UInt8] {
        var fins: [UInt8] = [
            0x80, 0x00, 0x02, 0x00,
            serverNode, 0x00, 0x00,
            clientNode, 0x00, 0x00,
        ]
        fins.append(contentsOf: command)
        var frame = Array("FINS".utf8)
        let total = 8 + fins.count
        frame.append(contentsOf: [
            UInt8((total >> 24) & 0xFF),
            UInt8((total >> 16) & 0xFF),
            UInt8((total >> 8) & 0xFF),
            UInt8(total & 0xFF),
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x00,
        ])
        frame.append(contentsOf: fins)
        return frame
    }

    static func icsFINSCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("finsprobe: nothing answers on the FINS door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // Node address request — the
        // published front step.
        var nodeAsk = Array("FINS".utf8)
        nodeAsk.append(contentsOf: [
            0x00, 0x00, 0x00, 0x0C,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ])
        guard let node = icsFINSExchange(
            fd, frame: nodeAsk),
              node.count >= 24 else {
            return light ? [] : [
                (String(format: L("finsprobe: the door at %@ would not trade node addresses — not a FINS front, or shut."), host), .out),
            ]
        }
        let clientNode = node[19]
        let serverNode = node[23]
        // Controller data read (0501).
        let dataAsk = icsFINSFrame(
            clientNode: clientNode,
            serverNode: serverNode,
            command: [0x05, 0x01])
        guard let data = icsFINSExchange(
            fd, frame: dataAsk),
              data.count >= 30 else {
            return [
                (String(format: L("finsprobe: the nodes trade addresses at %@, but the controller data read would not answer."), host), .out),
            ]
        }
        let end = icsU16BE(data, 28)
        guard end == 0 else {
            return [
                (String(format: L("finsprobe: the controller at %@ answered the data read with end code %04X — noted, and no further question asked."), host, Int64(end)), .out),
            ]
        }
        let model = data.count >= 50
            ? icsClean(data[30..<50]) : ""
        let version = data.count >= 70
            ? icsClean(data[50..<70]) : ""
        var lines: [ICSLine] = [
            (String(format: L("finsprobe: the controller at %@ reads — model %@, version %@."), host, model.isEmpty ? L("an unread plate") : model, version.isEmpty ? L("unread") : version), .sys),
        ]
        if light { return lines }
        // Controller status read
        // (0601) — state is READ here,
        // never set.
        let statusAsk = icsFINSFrame(
            clientNode: clientNode,
            serverNode: serverNode,
            command: [0x06, 0x01])
        if let status = icsFINSExchange(
            fd, frame: statusAsk),
           status.count >= 31,
           icsU16BE(status, 28) == 0 {
            let byte = status[30]
            let word: String
            switch byte {
            case 0x00:
                word = L("stopped, in program mode")
            case 0x01:
                word = L("running")
            default:
                word = String(
                    format: L("status byte 0x%02llX, as the controller prints it"), Int64(byte))
            }
            lines.append((
                String(format: L("finsprobe: its state reads %@ — read, and only read."), word),
                .out))
        }
        lines.append((
            L("finsprobe: FINS asks no name and no password for these reads — the same door that reports the run state carries the commands that change it, and those this bench never sends."),
            .err))
        return lines
    }

    static func finsprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 9600)
            else {
                icsSay(emit, L("finsprobe: give host[:port] — finsprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsFINSCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Mitsubishi MELSEC — the
    // SLMP type-name read

    static func icsMELSECCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("melsecprobe: nothing answers on the MELSEC door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // 3E frame, command 0101 —
        // the type-name read.
        let ask: [UInt8] = [
            0x50, 0x00, 0x00, 0xFF,
            0xFF, 0x03, 0x00, 0x06,
            0x00, 0x10, 0x00, 0x01,
            0x01, 0x00, 0x00,
        ]
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 9) else {
            return light ? [] : [
                (String(format: L("melsecprobe: the door at %@ took the knock and gave nothing back."), host), .out),
            ]
        }
        let len = icsU16LE(head, 7)
        guard len >= 2,
              let rest = icsReadExact(
                fd, len) else {
            return light ? [] : [
                (String(format: L("melsecprobe: the answer from %@ broke off mid-frame."), host), .out),
            ]
        }
        let full = head + rest
        let end = icsU16LE(full, 9)
        guard end == 0 else {
            return [
                (String(format: L("melsecprobe: %@ answered the type-name read with end code %04X — noted, nothing further asked."), host, Int64(end)), .out),
            ]
        }
        let model = full.count >= 27
            ? icsClean(full[11..<27])
            : ""
        let code = full.count >= 29
            ? icsU16LE(full, 27) : 0
        var lines: [ICSLine] = [
            (String(format: L("melsecprobe: the PLC at %@ gives its type name as %@ (model code %04X)."), host, model.isEmpty ? L("an unread plate") : model, Int64(code)), .sys),
        ]
        if !light {
            lines.append((
                L("melsecprobe: SLMP asks no name and no password for this read — the type name rides the same open door as every command the protocol carries, and the commands are never sent from here."),
                .err))
        }
        return lines
    }

    static func melsecprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 5007)
            else {
                icsSay(emit, L("melsecprobe: give host[:port] — melsecprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsMELSECCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: IEC 60870-5-104 — the
    // handshake, and nothing past it

    static func icsIEC104Core(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("iec104probe: nothing answers on the 104 door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // STARTDT act — the standard's
        // own doorbell. No interrogation
        // and no control ASDU ever
        // follows it from this bench.
        guard icsSendAll(fd, [
            0x68, 0x04, 0x07, 0x00,
            0x00, 0x00]) else {
            return light ? [] : [
                (String(format: L("iec104probe: the knock at %@ never left."), host), .out),
            ]
        }
        let first = icsAvailable(
            fd, seconds: light ? 1.2 : 2,
            cap: 1024)
        let started = first.count >= 3
            && first[0] == 0x68
            && first[2] == 0x0B
        var lines: [ICSLine] = []
        if started {
            lines.append((
                String(format: L("iec104probe: %@ confirms STARTDT — the data-transfer state stands open to this connection."), host),
                .sys))
        } else if !first.isEmpty {
            lines.append((
                String(format: L("iec104probe: %@ answered the doorbell in its own dialect: %@"), host, icsHex(first.prefix(12))),
                .sys))
        } else {
            return light ? [] : [
                (String(format: L("iec104probe: the door at %@ took the connection and confirmed nothing — no STARTDT con came home."), host), .out),
            ]
        }
        if !light {
            guard icsSendAll(fd, [
                0x68, 0x04, 0x43, 0x00,
                0x00, 0x00]) else {
                return lines
            }
            let second = icsAvailable(
                fd, seconds: 2, cap: 1024)
            if second.count >= 3,
               second[0] == 0x68,
               second[2] == 0x83 {
                lines.append((
                    L("iec104probe: TESTFR is confirmed too — the link keeps its own heartbeat, answered to a stranger."),
                    .out))
            }
            lines.append((
                L("iec104probe: base 104 authenticates no one — whoever connects may interrogate and, in the field, control. (The TLS profile of IEC 62351 exists precisely because of this; nothing here asked for papers.) No interrogation was sent."),
                .err))
        }
        return lines
    }

    static func iec104probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 2404)
            else {
                icsSay(emit, L("iec104probe: give host[:port] — iec104probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsIEC104Core(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: KNXnet/IP — the
    // description request

    static func icsKNXCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        let ask: [UInt8] = [
            0x06, 0x10, 0x02, 0x03,
            0x00, 0x0E, 0x08, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x0E, 0x57,
        ]
        guard let reply = icsUDPExchange(
            ip: ip, port: port,
            packet: ask, wait: light
                ? 1.4 : 2.4,
            cap: 4096),
              reply.count >= 6,
              icsU16BE(reply, 2) == 0x0204
        else {
            return light ? [] : [
                (String(format: L("knxprobe: no description came back from %@ — no KNXnet/IP device owns this knock, or it describes itself only to its own tool."), host), .out),
            ]
        }
        var pos = 6
        var name = ""
        var serial = ""
        var mac = ""
        var medium = -1
        var families: [String] = []
        let familyNames: [Int: String] = [
            2: L("core"), 3: L("tunneling"),
            4: L("routing"),
            5: L("remote logging"),
            6: L("remote diagnosis"),
            7: L("object server"),
        ]
        while pos + 2 <= reply.count {
            let dibType = Int(reply[pos])
            let dibLen = Int(reply[pos + 1])
            guard dibLen >= 2,
                  pos + dibLen <= reply.count
            else { break }
            if dibType == 1,
               dibLen >= 54 {
                medium = Int(reply[pos + 2])
                serial = icsHex(
                    reply[(pos + 8)..<(pos + 14)])
                mac = reply[
                    (pos + 18)..<(pos + 24)]
                    .map {
                        String(format: "%02x", $0)
                    }.joined(separator: ":")
                name = icsClean(
                    reply[(pos + 24)..<(pos + 54)])
            } else if dibType == 2 {
                var q = pos + 2
                while q + 1 < pos + dibLen {
                    let fam = Int(reply[q])
                    families.append(
                        familyNames[fam]
                            ?? String(format: L("family %lld"), Int64(fam)))
                    q += 2
                }
            }
            pos += dibLen
        }
        var lines: [ICSLine] = [
            (String(format: L("knxprobe: the device at %@ describes itself — name %@, serial %@, MAC %@%@."), host, name.isEmpty ? L("unread") : name, serial, mac, families.isEmpty ? "" : String(format: L(", speaking %@"), families.joined(separator: ", "))), .sys),
        ]
        _ = medium
        if !light {
            lines.append((
                L("knxprobe: KNXnet/IP describes its devices to any caller — in classic KNX the telegrams behind this door carry no authentication either, and tunneling stands in the family list above when it is offered."),
                .err))
        }
        return lines
    }

    static func knxprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 3671)
            else {
                icsSay(emit, L("knxprobe: give host[:port] — knxprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsKNXCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Niagara Fox — the hello

    static func icsFOXCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("foxprobe: nothing answers on the Fox door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        var hello = "fox hello\n{\n"
        let fields: [(String, String)] = [
            ("fox:id", "i:1"),
            ("fox:version", "s:1.0"),
            ("fox:hostName", "s:nightjar"),
            ("fox:hostAddress", "s:\(host)"),
            ("fox:appName", "s:nightjar"),
            ("fox:appVersion", "s:1.0"),
            ("fox:vmName", "s:nightjar"),
            ("fox:vmVersion", "s:1.0"),
            ("fox:osName", "s:nightjar"),
            ("fox:osVersion", "s:1.0"),
            ("fox:stationName", "s:nightjar"),
            ("fox:lang", "s:en"),
            ("fox:timeZone", "s:UTC"),
            ("fox:hostId", "s:nightjar"),
            ("fox:vmUuid", "s:nightjar"),
            ("fox:brandId", "s:default"),
        ]
        for (key, value) in fields {
            hello += "\(key):\(value)\n"
        }
        hello += "};;\n"
        guard icsSendAll(
            fd, Array(hello.utf8)) else {
            return light ? [] : [
                (String(format: L("foxprobe: the hello at %@ never left."), host), .out),
            ]
        }
        let heard = icsAvailable(
            fd, seconds: light ? 1.2 : 3,
            cap: 16384)
        guard !heard.isEmpty,
              let text = String(
                bytes: heard,
                encoding: .utf8) else {
            return light ? [] : [
                (String(format: L("foxprobe: the station at %@ took the hello and answered nothing — Fox may not be spoken here, or the hello's shape was refused."), host), .out),
            ]
        }
        var props: [String: String] = [:]
        for raw in text.split(
            separator: "\n") {
            let parts = raw.split(
                separator: ":",
                maxSplits: 2)
            guard parts.count == 3 else {
                continue
            }
            let key = String(parts[0])
                .replacingOccurrences(
                    of: "fox:", with: "")
            props[key] = String(parts[2])
        }
        var facts: [String] = []
        if let v = props["stationName"] {
            facts.append(String(
                format: L("station %@"), v))
        }
        if let v = props["version"] {
            facts.append(String(
                format: L("fox %@"), v))
        }
        if let v = props["appVersion"] {
            facts.append(String(
                format: L("app %@"), v))
        }
        if let v = props["vmVersion"] {
            facts.append(String(
                format: L("VM %@"), v))
        }
        if let v = props["osName"] {
            facts.append(String(
                format: L("OS %@"), v))
        }
        if let v = props["brandId"] {
            facts.append(String(
                format: L("brand %@"), v))
        }
        if facts.isEmpty {
            let runs = icsRuns(heard)
            return [
                (String(format: L("foxprobe: something at %@ answered the hello in words this reader cannot sort: %@"), host, runs.isEmpty ? icsHex(heard.prefix(24)) : runs.joined(separator: " · ")), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("foxprobe: the station at %@ returns the hello — %@."), host, facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("foxprobe: the Fox hello is a full introduction handed to any caller before any login is asked — station, versions, and host, for the asking. The session that follows is where Fox keeps its gate; the introduction is the disclosure."),
                .err))
        }
        return lines
    }

    static func foxprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 1911)
            else {
                icsSay(emit, L("foxprobe: give host[:port] — foxprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsFOXCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: HART-IP — session, then
    // universal command 0

    static func icsHARTRead(
        _ fd: Int32) -> [UInt8]? {
        guard let head = icsReadExact(
            fd, 8) else { return nil }
        let total = icsU16BE(head, 6)
        guard total >= 8,
              total <= 1 << 16 else {
            return nil
        }
        if total == 8 { return head }
        guard let rest = icsReadExact(
            fd, total - 8) else {
            return nil
        }
        return head + rest
    }

    static func icsHARTCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("hartprobe: nothing answers on the HART-IP door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // Session initiate: primary
        // master, a minute's lease.
        let initiate: [UInt8] = [
            0x01, 0x00, 0x00, 0x00,
            0x00, 0x01, 0x00, 0x0D,
            0x01, 0x00, 0x00, 0xEA,
            0x60,
        ]
        guard icsSendAll(fd, initiate),
              let open = icsHARTRead(fd),
              open.count >= 8,
              open[1] == 0x01,
              open[2] == 0x00 else {
            return light ? [] : [
                (String(format: L("hartprobe: the door at %@ would not open a session — no HART-IP front stands here, or it is shut."), host), .out),
            ]
        }
        // Universal command 0 — Read
        // Unique Identifier — in a
        // short frame to polling
        // address 0, checksum carried.
        var hframe: [UInt8] = [
            0x02, 0x80, 0x00, 0x00,
        ]
        var chk: UInt8 = 0
        for byte in hframe { chk ^= byte }
        hframe.append(chk)
        var cmd: [UInt8] = [
            0x01, 0x00, 0x01, 0x00,
            0x00, 0x02,
        ]
        let total = 8 + hframe.count
        cmd.append(UInt8(
            (total >> 8) & 0xFF))
        cmd.append(UInt8(total & 0xFF))
        cmd.append(contentsOf: hframe)
        guard icsSendAll(fd, cmd),
              let answer = icsHARTRead(fd),
              answer.count > 8 else {
            return [
                (String(format: L("hartprobe: a session opened at %@, but command 0 drew no answer — the field device behind the door stayed silent."), host), .out),
            ]
        }
        let body = Array(answer.dropFirst(8))
        guard body.count >= 4,
              body[0] == 0x06
                || body[0] == 0x86 else {
            return [
                (String(format: L("hartprobe: the answer from %@ is not a HART frame this reader knows: %@"), host, icsHex(body.prefix(16))), .out),
            ]
        }
        let addrLen = body[0] == 0x06
            ? 1 : 5
        let bcAt = 2 + addrLen
        guard body.count > bcAt else {
            return [
                (String(format: L("hartprobe: the frame from %@ arrived short."), host), .out),
            ]
        }
        let dataAt = bcAt + 1 + 2
        guard body.count >= dataAt + 14
        else {
            return [
                (String(format: L("hartprobe: command 0 was answered at %@, but the identity block arrived short — unclaimed."), host), .out),
            ]
        }
        let data = Array(
            body[dataAt...])
        let maker = icsU16BE(data, 1)
        let dtype = icsU16BE(data, 3)
        let univ = Int64(data[6])
        let devRev = Int64(data[7])
        let swRev = Int64(data[8])
        let serial = icsHex(
            data[11..<14])
        var lines: [ICSLine] = [
            (String(format: L("hartprobe: the field device at %@ answers command 0 — maker number %lld, device type %lld, universal revision %lld, device revision %lld, software %lld, serial bytes %@."), host, Int64(maker), Int64(dtype), univ, devRev, swRev, serial), .sys),
        ]
        if !light {
            lines.append((
                L("hartprobe: the maker's number is the device's own claim, printed here as printed there — HART-IP opened the session on a knock, with no name asked in return."),
                .out))
        }
        return lines
    }

    static func hartprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 5094)
            else {
                icsSay(emit, L("hartprobe: give host[:port] — hartprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsHARTCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: GE SRTP — degraded

    static func srtpprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 18245)
            else {
                icsSay(emit, L("srtpprobe: give host[:port] — srtpprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "srtpprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("srtpprobe: the SRTP service-request frame could not be verified byte-for-byte against GE's published layout, so no identification read is claimed — only the door's own state, exactly as observed.")))
        }
    }

    // MARK: Beckhoff ADS — device
    // info and state, read over AMS

    static func icsADSRead(
        _ fd: Int32) -> [UInt8]? {
        guard let head = icsReadExact(
            fd, 6) else { return nil }
        let len = icsU32LE(head, 2)
        guard len >= 32, len <= 1 << 16,
              let rest = icsReadExact(
                fd, len) else {
            return nil
        }
        return head + rest
    }

    static func icsADSFrame(
        ip: String, command: UInt16,
        invoke: UInt32) -> [UInt8] {
        let octets = ip.split(
            separator: ".").compactMap {
            UInt8($0)
        }
        let target: [UInt8] = octets
            .count == 4
            ? octets + [0x01, 0x01]
            : [0x00, 0x00, 0x00, 0x00,
               0x01, 0x01]
        let source: [UInt8] = [
            192, 168, 1, 100, 0x01, 0x01,
        ]
        var ams: [UInt8] = []
        ams.append(contentsOf: target)
        ams.append(contentsOf:
            [0x10, 0x27])  // port 10000
        ams.append(contentsOf: source)
        ams.append(contentsOf:
            [0x81, 0x80])  // port 32905
        ams.append(contentsOf: [
            UInt8(command & 0xFF),
            UInt8((command >> 8) & 0xFF),
            0x04, 0x00,              // command flags
            0x00, 0x00, 0x00, 0x00,  // data length
            0x00, 0x00, 0x00, 0x00,  // error code
            UInt8(invoke & 0xFF),
            UInt8((invoke >> 8) & 0xFF),
            0x00, 0x00,
        ])
        var frame: [UInt8] = [0x00, 0x00]
        frame.append(contentsOf: [
            UInt8(ams.count & 0xFF),
            UInt8((ams.count >> 8)
                    & 0xFF),
            0x00, 0x00,
        ])
        frame.append(contentsOf: ams)
        return frame
    }

    static func icsADSCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("adsprobe: nothing answers on the ADS door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // ReadDeviceInfo (command 9),
        // addressed by the TwinCAT
        // convention: the target's own
        // address with .1.1 behind it.
        let ask = icsADSFrame(
            ip: ip, command: 9, invoke: 1)
        guard icsSendAll(fd, ask),
              let info = icsADSRead(fd),
              info.count >= 62 else {
            return light ? [] : [
                (String(format: L("adsprobe: the door at %@ took the AMS knock and gave nothing readable back — the device may answer only to its true AMS NetId, which a knock cannot know."), host), .out),
            ]
        }
        let adsErr = icsU32LE(info, 38)
        guard adsErr == 0 else {
            return [
                (String(format: L("adsprobe: %@ answered ReadDeviceInfo with ADS error %lld — noted, nothing further asked."), host, Int64(adsErr)), .out),
            ]
        }
        let major = Int64(info[42])
        let minor = Int64(info[43])
        let build = icsU16LE(info, 44)
        let name = icsClean(
            info[46..<62])
        var lines: [ICSLine] = [
            (String(format: L("adsprobe: the device at %@ gives its info — name %@, TwinCAT version %lld.%lld, build %lld."), host, name.isEmpty ? L("unread") : name, major, minor, Int64(build)), .sys),
        ]
        if light { return lines }
        // ReadState (command 4).
        let stateAsk = icsADSFrame(
            ip: ip, command: 4, invoke: 2)
        if icsSendAll(fd, stateAsk),
           let state = icsADSRead(fd),
           state.count >= 46,
           icsU32LE(state, 38) == 0 {
            let ads = icsU16LE(state, 42)
            let stateNames: [Int: String] = [
                0: L("invalid"), 1: L("idle"),
                2: L("reset"), 3: L("init"),
                4: L("start"), 5: L("run"),
                6: L("stop"),
                7: L("save config"),
                8: L("load config"),
                9: L("power failure"),
                10: L("power good"),
                11: L("error"),
                12: L("shutdown"),
                13: L("suspend"),
                14: L("resume"),
                15: L("config"),
                16: L("reconfig"),
                17: L("stopping"),
            ]
            let word = stateNames[ads]
                ?? String(format: L("state %lld"), Int64(ads))
            lines.append((
                String(format: L("adsprobe: its ADS state reads %@ — read, and only read."), word),
                .out))
        }
        lines.append((
            L("adsprobe: ADS answers identity and state to any AMS caller — the router's door is a trusting one by design, and the writes that share it are never sent from here."),
            .err))
        return lines
    }

    static func adsprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 48898)
            else {
                icsSay(emit, L("adsprobe: give host[:port] — adsprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsADSCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: DLMS/COSEM — the
    // association posture

    static func icsDLMSCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("dlmsprobe: nothing answers on the DLMS door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // The AARQ, assembled field by
        // field from IEC 62056-5-3:
        // logical-name referencing, the
        // LOWEST security mechanism,
        // and the canonical
        // initiate-request block. No
        // password is offered — that is
        // the question being asked.
        let aarq: [UInt8] = [
            0x60, 0x2A,
            0xA1, 0x09, 0x06, 0x07,
            0x60, 0x85, 0x74, 0x05,
            0x08, 0x01, 0x01,
            0x8A, 0x02, 0x07, 0x80,
            0x8B, 0x07, 0x60, 0x85,
            0x74, 0x05, 0x08, 0x02,
            0x01,
            0xBE, 0x10, 0x04, 0x0E,
            0x01, 0x00, 0x00, 0x00,
            0x06, 0x5F, 0x1F, 0x04,
            0x00, 0x00, 0x1E, 0x5D,
            0xFF, 0xFF,
        ]
        var packet: [UInt8] = [
            0x00, 0x01, 0x00, 0x10,
            0x00, 0x01, 0x00, 0x2C,
        ]
        packet.append(contentsOf: aarq)
        guard icsSendAll(fd, packet)
        else {
            return light ? [] : [
                (String(format: L("dlmsprobe: the knock at %@ never left."), host), .out),
            ]
        }
        let answer = icsAvailable(
            fd, seconds: light ? 1.5 : 3,
            cap: 4096)
        guard answer.count >= 10 else {
            return light ? [] : [
                (String(format: L("dlmsprobe: the meter at %@ took the association request and answered nothing — silence, the wrapper's shape refused, or a door that is not DLMS at all."), host), .out),
            ]
        }
        guard answer[0] == 0x00,
              answer[1] == 0x01,
              answer.count > 8 else {
            return [
                (String(format: L("dlmsprobe: whatever answered at %@ is not speaking the DLMS wrapper: %@"), host, icsHex(answer.prefix(16))), .out),
            ]
        }
        let apdu = Array(answer.dropFirst(8))
        if apdu.first == 0x61 {
            // AARE: find the
            // association-result
            // (A2 03 02 01 xx).
            var result: Int?
            var scan = 0
            while scan + 4 < apdu.count {
                if apdu[scan] == 0xA2,
                   apdu[scan + 1] == 0x03,
                   apdu[scan + 2] == 0x02,
                   apdu[scan + 3] == 0x01 {
                    result = Int(
                        apdu[scan + 4])
                    break
                }
                scan += 1
            }
            if result == 0 {
                return [
                    (String(format: L("dlmsprobe: the meter at %@ ACCEPTED the association — on the lowest security mechanism, with no password offered and none demanded."), host), .sys),
                    (L("dlmsprobe: that acceptance is the grade: the ledger of a meter that opens to an unauthenticated knock can be read — and in the field, more than read — by anyone who reaches this door. Nothing here read past the handshake."), .err),
                ]
            }
            if let result = result {
                return [
                    (String(format: L("dlmsprobe: the meter at %@ refused the bare association (result %lld) — some authentication stands demanded, and none is offered from here."), host, Int64(result)), .ok),
                ]
            }
            return [
                (String(format: L("dlmsprobe: %@ returned an AARE this reader cannot grade: %@"), host, icsHex(apdu.prefix(20))), .out),
            ]
        }
        if apdu.first == 0xD8 {
            return [
                (String(format: L("dlmsprobe: the meter at %@ answered with a DLMS exception — the association did not open."), host), .out),
            ]
        }
        return [
            (String(format: L("dlmsprobe: the answer from %@ began with a byte this reader cannot grade (0x%02llX) — reported, not interpreted."), host, Int64(apdu.first ?? 0)), .out),
        ]
    }

    static func dlmsprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 4059)
            else {
                icsSay(emit, L("dlmsprobe: give host[:port] — dlmsprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsDLMSCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Moxa NPort — degraded (UDP)

    static func moxaprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 4800)
            else {
                icsSay(emit, L("moxaprobe: give host[:port] — moxaprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsUDPEmptyCore(
                verb: "moxaprobe",
                host: host, ip: ip,
                port: port, light: false,
                note: L("moxaprobe: the identification read for this serial-gateway family rides frames this bench could not verify byte-for-byte, so none is sent — an empty knock only, and no identification is claimed.")))
        }
    }

    // MARK: IEEE C37.118 — the CFG
    // request, and only that

    static func icsPMUCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4)
        else {
            return light ? [] : [
                (String(format: L("pmuprobe: nothing answers on the synchrophasor door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // A command frame carrying ONE
        // word: send CFG-2 (0x0005).
        // The data start and stop words
        // are never sent from here.
        let soc = Int(
            Date().timeIntervalSince1970)
        var frame: [UInt8] = [
            0xAA, 0x41, 0x00, 0x12,
            0x00, 0x01,
            UInt8((soc >> 24) & 0xFF),
            UInt8((soc >> 16) & 0xFF),
            UInt8((soc >> 8) & 0xFF),
            UInt8(soc & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x05,
        ]
        let chk = icsCRCCCITT(frame)
        frame.append(UInt8(chk >> 8))
        frame.append(UInt8(chk & 0xFF))
        guard icsSendAll(fd, frame),
              let head = icsReadExact(
                fd, 4) else {
            return light ? [] : [
                (String(format: L("pmuprobe: the unit at %@ took the CFG request and gave nothing back."), host), .out),
            ]
        }
        let size = icsU16BE(head, 2)
        guard size > 4, size <= 1 << 16,
              let rest = icsReadExact(
                fd, size - 4) else {
            return light ? [] : [
                (String(format: L("pmuprobe: the answer from %@ broke off mid-frame."), host), .out),
            ]
        }
        let full = head + rest
        let ftype = Int(full[1] >> 4)
        if ftype == 0 {
            return [
                (String(format: L("pmuprobe: %@ is already streaming phasor data to whoever connects — the frames run unasked, and this bench asked for nothing but the configuration."), host), .err),
            ]
        }
        guard ftype == 2 || ftype == 3,
              full.count >= 46 else {
            return [
                (String(format: L("pmuprobe: the answer from %@ is a frame of type %lld — noted, not graded."), host, Int64(ftype)), .out),
            ]
        }
        let stn = icsClean(full[20..<36])
        let ph = icsU16BE(full, 40)
        let an = icsU16BE(full, 42)
        let dg = icsU16BE(full, 44)
        let o = 46 + (ph + an + 16 * dg) * 16 + (ph + an + dg) * 4
        var tail = ""
        if o + 4 <= full.count - 2 {
            let fnom = icsU16BE(full, o)
            var rate = icsU16BE(
                full, o + 2)
            if rate >= 0x8000 {
                rate -= 0x10000
            }
            tail = String(
                format: L(", nominal-frequency word %lld, data rate %lld frames a second"), Int64(fnom), Int64(rate))
        }
        var lines: [ICSLine] = [
            (String(format: L("pmuprobe: the PMU at %@ hands over its configuration — station %@, %lld phasor(s), %lld analog(s), %lld digital word(s)%@."), host, stn.isEmpty ? L("unread") : stn, Int64(ph), Int64(an), Int64(dg), tail), .sys),
        ]
        if !light {
            lines.append((
                L("pmuprobe: base C37.118 authenticates no one — the configuration, and behind it the stream itself, are had by connecting. Only the CFG request was sent; the stream was never started from here."),
                .err))
        }
        return lines
    }

    static func pmuprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 4712)
            else {
                icsSay(emit, L("pmuprobe: give host[:port] — pmuprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsPMUCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: plcensus — the whole
    // board, one light knock per door

    static func plcensus(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("plcensus: give a host — plcensus 192.168.1.10"), .err)
                return
            }
            icsSay(emit, String(format: L("plcensus: one light knock on every plant door at %@ — identification reads only, the same ones the verbs make."), host), .sys)
            let doors: [(
                label: String, port: Int,
                probe: (String, String,
                        UInt16) -> [ICSLine]
            )] = [
                ("SEL relay terminal", 23,
                 { icsSELCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Emerson ROC", 2000,
                 { icsROCCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Allen-Bradley CSP/PCCC (legacy)", 2222,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("DLMS/COSEM meter", 4059,
                 { icsDLMSCore(host: $0, ip: $1, port: $2, light: true) }),
                ("MTConnect agent", 5000,
                 { icsMTConnectCore(host: $0, port: $2, light: true) }),
                ("MELSEC SLMP", 5007,
                 { icsMELSECCore(host: $0, ip: $1, port: $2, light: true) }),
                ("HART-IP", 5094,
                 { icsHARTCore(host: $0, ip: $1, port: $2, light: true) }),
                ("HSMS / SECS-GEM", 5000,
                 { icsSECSCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Fanuc FOCAS", 8193,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("Omron FINS", 9600,
                 { icsFINSCore(host: $0, ip: $1, port: $2, light: true) }),
                ("M-Bus gateway", 10001,
                 { icsMBUSCore(host: $0, ip: $1, port: $2, light: true) }),
                ("ANSI C12.22 meter", 1153,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("Phoenix PC Worx", 1962,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("IEC 60870-5-104", 2404,
                 { icsIEC104Core(host: $0, ip: $1, port: $2, light: true) }),
                ("CODESYS gateway", 1217,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("OPC UA", 4840,
                 { icsOPCUACore(host: $0, ip: $1, port: $2, light: true) }),
                ("C37.118 PMU", 4712,
                 { icsPMUCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Modbus door (UMAS and SunSpec share it — their verbs ask deeper)", 502,
                 { icsModbusCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Siemens S7 / IEC 61850 (RFC 1006)", 102,
                 { icsS7Core(host: $0, ip: $1, port: $2, light: true) }),
                ("Niagara Fox", 1911,
                 { icsFOXCore(host: $0, ip: $1, port: $2, light: true) }),
                ("DNP3", 20000,
                 { icsDNP3Core(host: $0, ip: $1, port: $2, light: true) }),
                ("Unitronics PCOM", 20256,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("GE SRTP", 18245,
                 { icsConnectOnlyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
                ("EtherNet/IP", 44818,
                 { icsENIPCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Beckhoff ADS", 48898,
                 { icsADSCore(host: $0, ip: $1, port: $2, light: true) }),
                ("IEEE 2030.5 (SEP2)", 443,
                 { icsSEP2Core(host: $0, port: $2, light: true) }),
                ("BACnet/IP", 47808,
                 { icsBACnetCore(host: $0, ip: $1, port: $2, light: true) }),
                ("KNXnet/IP", 3671,
                 { icsKNXCore(host: $0, ip: $1, port: $2, light: true) }),
                ("IEEE 1588 PTP", 320,
                 { icsPTPCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Lantronix discovery", 30718,
                 { icsLantronixCore(host: $0, ip: $1, port: $2, light: true) }),
                ("Moxa NPort gateway", 4800,
                 { icsUDPEmptyCore(verb: "plcensus", host: $0, ip: $1, port: $2, light: true, note: "") }),
            ]
            var found = 0
            for door in doors {
                let lines = door.probe(
                    host, ip,
                    UInt16(door.port))
                guard !lines.isEmpty else {
                    continue
                }
                found += 1
                icsSay(emit, String(format: L("door %lld — %@"), Int64(door.port), door.label), .sys)
                for line in lines.prefix(2) {
                    icsSay(emit, "  "
                        + line.text,
                           line.kind)
                }
            }
            icsSay(emit, String(format: L("plcensus: %lld of %lld doors answered at %@."), Int64(found), Int64(doors.count), host), found > 0 ? .ok : .out)
            icsSay(emit, L("plcensus: the honest edges of the board — whole families cannot be knocked from this phone at all: the layer-2 Ethernets (PROFINET DCP, EtherCAT, POWERLINK, IEC 61850 GOOSE) ride raw frames no iOS app may send or hear."), .out)
            icsSay(emit, L("plcensus: and the serial and vehicle buses (CANopen, DeviceNet, J1939, ISOBUS, PROFIBUS DP, Modbus RTU, DF1 serial, SDI-12) reach the network only through gateway doors — which is why the gateways carry verbs of their own (moxaprobe, lantronixprobe)."), .out)
        }
    }

    // MARK: the wave's one dispatch

    static func benchICS(
        _ name: String, _ target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        switch name {
        case "modbusprobe":
            modbusprobe(target: target, emit: emit, done: done)
        case "s7probe":
            s7probe(target: target, emit: emit, done: done)
        case "iec61850probe":
            iec61850probe(target: target, emit: emit, done: done)
        case "enipprobe":
            enipprobe(target: target, emit: emit, done: done)
        case "pcccprobe":
            pcccprobe(target: target, emit: emit, done: done)
        case "dnp3probe":
            dnp3probe(target: target, emit: emit, done: done)
        case "bacnetprobe":
            bacnetprobe(target: target, emit: emit, done: done)
        case "opcuaprobe":
            opcuaprobe(target: target, emit: emit, done: done)
        case "finsprobe":
            finsprobe(target: target, emit: emit, done: done)
        case "melsecprobe":
            melsecprobe(target: target, emit: emit, done: done)
        case "iec104probe":
            iec104probe(target: target, emit: emit, done: done)
        case "knxprobe":
            knxprobe(target: target, emit: emit, done: done)
        case "foxprobe":
            foxprobe(target: target, emit: emit, done: done)
        case "hartprobe":
            hartprobe(target: target, emit: emit, done: done)
        case "srtpprobe":
            srtpprobe(target: target, emit: emit, done: done)
        case "adsprobe":
            adsprobe(target: target, emit: emit, done: done)
        case "dlmsprobe":
            dlmsprobe(target: target, emit: emit, done: done)
        case "moxaprobe":
            moxaprobe(target: target, emit: emit, done: done)
        case "pmuprobe":
            pmuprobe(target: target, emit: emit, done: done)
        case "plcensus":
            plcensus(target: target, emit: emit, done: done)
        case "selprobe":
            selprobe(target: target, emit: emit, done: done)
        case "rocprobe":
            rocprobe(target: target, emit: emit, done: done)
        case "mtconnectprobe":
            mtconnectprobe(target: target, emit: emit, done: done)
        case "focasprobe":
            focasprobe(target: target, emit: emit, done: done)
        case "codesysprobe":
            codesysprobe(target: target, emit: emit, done: done)
        case "umasprobe":
            umasprobe(target: target, emit: emit, done: done)
        case "happrobe":
            happrobe(target: target, emit: emit, done: done)
        case "pcomprobe":
            pcomprobe(target: target, emit: emit, done: done)
        case "pcworxprobe":
            pcworxprobe(target: target, emit: emit, done: done)
        case "lonprobe":
            lonprobe(target: target, emit: emit, done: done)
        case "mbusprobe":
            mbusprobe(target: target, emit: emit, done: done)
        case "secsprobe":
            secsprobe(target: target, emit: emit, done: done)
        case "ffprobe":
            ffprobe(target: target, emit: emit, done: done)
        case "ptpprobe":
            ptpprobe(target: target, emit: emit, done: done)
        case "sep2probe":
            sep2probe(target: target, emit: emit, done: done)
        case "sunspecprobe":
            sunspecprobe(target: target, emit: emit, done: done)
        case "lantronixprobe":
            lantronixprobe(target: target, emit: emit, done: done)
        case "c1222probe":
            c1222probe(target: target, emit: emit, done: done)
        default:
            done()
        }
    }
}
