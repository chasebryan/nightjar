import Foundation

// BetafischDeep — betafisch B2: the deep
// dissectors, the follow-stream reader
// and the statistics. The dissectors read
// the protocols a house wire actually
// carries — DHCP, mDNS, SSDP, NTP, TFTP,
// NBNS, TLS, HTTP/2, SMB — on top of the
// B1 core, and every one of them is
// shape-gated: a payload is only claimed
// when its own bytes verify the shape
// (a magic cookie, a record header, a
// preface), never on the port's say-so
// alone. What a dissector prints is what
// the bytes say; an identification is an
// interpretation, stated as one.
//
// Follow-stream lays a conversation's
// two directions out in order — TCP on
// driftnet's reassembly, UDP as the
// datagrams arrived — and statistics
// counts the capture exactly. Nothing
// here executes or renders content, and
// nothing is transmitted.

extension Betafisch {

    // MARK: Payload dispatch (B2)

    /// What rides in a UDP datagram,
    /// claimed by shape first and port
    /// second; nil when nothing claims
    /// it and the payload stays data.
    static func udpPayload(_ b: [UInt8], at: Int,
                           end: Int, sport: Int,
                           dport: Int,
                           _ acc: Accum) -> BFNode? {
        if sport == 53 || dport == 53 {
            return dns(b, at: at, end: end, acc,
                       spanFrom: at)
        }
        if sport == 5353 || dport == 5353 {
            return dns(b, at: at, end: end, acc,
                       spanFrom: at, flavor: "mdns")
        }
        if sport == 137 || dport == 137 {
            return dns(b, at: at, end: end, acc,
                       spanFrom: at, flavor: "nbns")
        }
        if let node = dhcp(b, at: at, end: end, acc) {
            return node
        }
        if let node = ssdp(b, at: at, end: end,
                           sport: sport, dport: dport,
                           acc) {
            return node
        }
        if let node = ntp(b, at: at, end: end,
                          sport: sport, dport: dport,
                          acc) {
            return node
        }
        if let node = tftp(b, at: at, end: end,
                           sport: sport, dport: dport,
                           acc) {
            return node
        }
        return nil
    }

    /// What rides in a TCP segment, in
    /// the order the shapes are checked;
    /// nil leaves the payload as data.
    static func tcpPayload(_ b: [UInt8], at: Int,
                           end: Int, sport: Int,
                           dport: Int,
                           _ acc: Accum) -> BFNode? {
        let length = end - at
        if (sport == 53 || dport == 53)
            && length >= 2 {
            return dns(b, at: at + 2, end: end, acc,
                       spanFrom: at)
        }
        if let node = tls(b, at: at, end: end, acc) {
            return node
        }
        if let node = http2(b, at: at, end: end,
                            acc) {
            return node
        }
        if let node = smb(b, at: at, end: end,
                          sport: sport, dport: dport,
                          acc) {
            return node
        }
        if let node = httpSniff(b, at: at, end: end,
                                acc) {
            return node
        }
        return nil
    }

    // MARK: Checksum verification

    /// Whether a TCP or UDP checksum
    /// verifies against the pseudo-header
    /// the frame's own addresses build:
    /// "correct", "incorrect", or nil
    /// when the frame does not carry
    /// enough to judge (a UDP checksum of
    /// zero on IPv4, a truncated tail).
    /// The verdict is arithmetic on the
    /// captured bytes, nothing more.
    static func transportVerdict(
        _ b: [UInt8], at: Int, end: Int,
        proto: Int, _ acc: Accum) -> String? {
        guard let src = acc.ipSrcRaw,
              let dst = acc.ipDstRaw,
              end - at >= 8 else { return nil }
        if proto == 17 {
            let carried = u16be(b, at + 6) ?? 0
            if carried == 0 && acc.ipVersion == 4 {
                return nil
            }
        }
        var pseudo: [UInt8] = []
        if acc.ipVersion == 6 {
            pseudo = src + dst
            let length = end - at
            pseudo.append(UInt8((length >> 24) & 0xff))
            pseudo.append(UInt8((length >> 16) & 0xff))
            pseudo.append(UInt8((length >> 8) & 0xff))
            pseudo.append(UInt8(length & 0xff))
            pseudo.append(contentsOf: [0, 0, 0])
            pseudo.append(UInt8(proto & 0xff))
        } else {
            pseudo = src + dst
            pseudo.append(0)
            pseudo.append(UInt8(proto & 0xff))
            let length = end - at
            pseudo.append(UInt8((length >> 8) & 0xff))
            pseudo.append(UInt8(length & 0xff))
        }
        let segment = Array(b[at..<end])
        var sum = foldedSum(pseudo, from: 0,
                            count: pseudo.count)
        sum += foldedSum(segment, from: 0,
                         count: segment.count)
        while sum > 0xffff {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        return sum == 0xffff ? L("correct")
            : L("does not verify — as captured")
    }

    // MARK: DHCP

    static func dhcpTypeName(_ type: Int) -> String {
        switch type {
        case 1: return L("Discover")
        case 2: return L("Offer")
        case 3: return L("Request")
        case 4: return L("Decline")
        case 5: return L("ACK")
        case 6: return L("NAK")
        case 7: return L("Release")
        case 8: return L("Inform")
        default:
            return String(format: L("type %lld"), type)
        }
    }

    /// BOOTP/DHCP. The claim is the magic
    /// cookie at offset 236; without it
    /// the packet is read as BOOTP,
    /// DHCP's ancestor, and says so.
    static func dhcp(_ b: [UInt8], at: Int,
                     end: Int, _ acc: Accum)
        -> BFNode? {
        guard end - at >= 240 else { return nil }
        let op = u8(b, at) ?? 0
        guard op == 1 || op == 2 else { return nil }
        let htype = u8(b, at + 1) ?? 0
        let hlen = u8(b, at + 2) ?? 0
        let xid = u32be(b, at + 4) ?? 0
        let flags = u16be(b, at + 10) ?? 0
        let cookieOK = end - at >= 240
            && u8(b, at + 236) == 0x63
            && u8(b, at + 237) == 0x82
            && u8(b, at + 238) == 0x53
            && u8(b, at + 239) == 0x63
        acc.proto = "DHCP"
        acc.protocols.insert("dhcp")
        var node = BFNode(
            L("Dynamic Host Configuration Protocol"),
            op == 1 ? L("request") : L("reply"),
            at..<end)
        node.children.append(BFNode(
            L("Message type"),
            String(format: "%lld — %@", op,
                   op == 1 ? L("request")
                       : L("reply")),
            at..<(at + 1)))
        node.children.append(BFNode(
            L("Transaction ID"),
            String(format: "0x%@",
                   hexDumpWord(xid, 8)),
            (at + 4)..<(at + 8)))
        node.children.append(BFNode(
            L("Broadcast flag"),
            flags & 0x8000 != 0 ? L("set")
                : L("not set"),
            (at + 10)..<(at + 12)))
        let addrRows: [(String, Int)] = [
            (L("Client address"), at + 12),
            (L("Your address"), at + 16),
            (L("Server address"), at + 20),
            (L("Gateway address"), at + 24),
        ]
        for row in addrRows {
            node.children.append(BFNode(
                row.0, ipv4String(b, row.1),
                row.1..<(row.1 + 4)))
        }
        if htype == 1 && hlen == 6 {
            node.children.append(BFNode(
                L("Client MAC address"),
                macString(b, at + 28),
                (at + 28)..<(at + 34)))
        }
        if !cookieOK {
            node.children.append(BFNode(
                L("Magic cookie"),
                L("absent — this reads as BOOTP, the ancestor protocol, not DHCP"),
                (at + 236)..<min(end, at + 240)))
            acc.info = String(
                format: L("BOOTP %@, xid 0x%@"),
                op == 1 ? L("request") : L("reply"),
                hexDumpWord(xid, 8))
            return node
        }
        // The options walk.
        var options = BFNode(L("Options"), "",
                             (at + 240)..<end)
        var cursor = at + 240
        var msgType: Int? = nil
        var hostname: String? = nil
        var requested: String? = nil
        var steps = 0
        while cursor < end && steps < 64 {
            steps += 1
            let code = u8(b, cursor) ?? 0
            if code == 0 {
                cursor += 1
                continue
            }
            if code == 255 {
                options.children.append(BFNode(
                    L("End"), "",
                    cursor..<(cursor + 1)))
                break
            }
            guard cursor + 1 < end,
                  let olen = u8(b, cursor + 1),
                  cursor + 2 + olen <= end
            else {
                options.children.append(BFNode(
                    String(format: L("option %lld"),
                           code),
                    L("its length runs past the packet"),
                    cursor..<end))
                cursor = end
                break
            }
            let valueAt = cursor + 2
            let valueEnd = valueAt + olen
            var title = String(
                format: L("option %lld"), code)
            var detail = String(
                format: L("%lld bytes"), olen)
            switch code {
            case 53 where olen >= 1:
                let type = u8(b, valueAt) ?? 0
                msgType = type
                title = L("Message type")
                detail = dhcpTypeName(type)
            case 1 where olen == 4:
                title = L("Subnet mask")
                detail = ipv4String(b, valueAt)
            case 3 where olen >= 4:
                title = L("Routers")
                var parts: [String] = []
                var walk = valueAt
                while walk + 4 <= valueEnd {
                    parts.append(ipv4String(b, walk))
                    walk += 4
                }
                detail = parts.joined(separator: ", ")
            case 6 where olen >= 4:
                title = L("DNS servers")
                var parts: [String] = []
                var walk = valueAt
                while walk + 4 <= valueEnd {
                    parts.append(ipv4String(b, walk))
                    walk += 4
                }
                detail = parts.joined(separator: ", ")
            case 12:
                title = L("Hostname")
                detail = textRender(
                    Array(b[valueAt..<valueEnd]))
                hostname = detail
            case 15:
                title = L("Domain name")
                detail = textRender(
                    Array(b[valueAt..<valueEnd]))
            case 50 where olen == 4:
                title = L("Requested address")
                detail = ipv4String(b, valueAt)
                requested = detail
            case 51 where olen == 4:
                title = L("Lease time")
                let seconds = u32be(b, valueAt) ?? 0
                detail = String(
                    format: L("%lld seconds"),
                    seconds)
            case 54 where olen == 4:
                title = L("Server identifier")
                detail = ipv4String(b, valueAt)
            case 55:
                title = L("Parameter request list")
                var parts: [String] = []
                for k in 0..<olen {
                    parts.append(String(
                        u8(b, valueAt + k) ?? 0))
                }
                detail = parts.joined(separator: ", ")
            case 61:
                title = L("Client identifier")
                if olen == 7 {
                    detail = macString(b, valueAt + 1)
                } else {
                    detail = textRender(
                        Array(b[valueAt..<valueEnd]))
                }
            default:
                break
            }
            options.children.append(BFNode(
                title, detail, cursor..<valueEnd))
            cursor = valueEnd
        }
        options.range = (at + 240)..<cursor
        node.children.append(options)
        var info = L("DHCP")
        if let msgType {
            info += " " + dhcpTypeName(msgType)
        }
        info += String(format: ", xid 0x%@",
                       hexDumpWord(xid, 8))
        if let requested {
            info += String(format: L(" — asks for %@"),
                           requested)
        } else if let hostname {
            info += String(format: L(" — %@"),
                           hostname)
        }
        acc.info = info
        return node
    }

    // MARK: SSDP

    /// The discovery chatter UPnP rides:
    /// HTTP-shaped lines over UDP 1900.
    /// Claimed only when the port agrees
    /// and the first line is one of
    /// SSDP's own shapes.
    static func ssdp(_ b: [UInt8], at: Int, end: Int,
                     sport: Int, dport: Int,
                     _ acc: Accum) -> BFNode? {
        guard sport == 1900 || dport == 1900
        else { return nil }
        let text = textRender(Array(b[at..<end]))
        let heads = ["NOTIFY ", "M-SEARCH ",
                     "HTTP/1.1 200", "HTTP/1.0 200"]
        let claimed = heads.contains(
            where: { text.hasPrefix($0) })
        guard claimed else { return nil }
        acc.proto = "SSDP"
        acc.protocols.insert("ssdp")
        var node = BFNode(
            L("Simple Service Discovery Protocol"),
            "", at..<end)
        var lines: [(String, Range<Int>)] = []
        var start = at
        var cursor = at
        while cursor < end && lines.count < 24 {
            if b[cursor] == 0x0a {
                var lineEnd = cursor
                if lineEnd > start
                    && b[lineEnd - 1] == 0x0d {
                    lineEnd -= 1
                }
                let line = textRender(
                    Array(b[start..<lineEnd]))
                lines.append(
                    (line, start..<(cursor + 1)))
                start = cursor + 1
                if line.isEmpty { break }
            }
            cursor += 1
        }
        for (index, pair) in lines.enumerated() {
            if index == 0 {
                node.children.append(BFNode(
                    L("First line"), pair.0, pair.1))
                continue
            }
            if let colon = pair.0.firstIndex(
                of: ":") {
                let name = String(
                    pair.0[..<colon])
                let value = String(
                    pair.0[pair.0.index(
                        after: colon)...])
                    .trimmingCharacters(
                        in: .whitespaces)
                node.children.append(BFNode(
                    name, value, pair.1))
            } else {
                node.children.append(BFNode(
                    L("Header"), pair.0, pair.1))
            }
        }
        node.detail = lines.first?.0 ?? ""
        acc.info = lines.first?.0 ?? acc.info
        return node
    }

    // MARK: NTP

    static func ntpModeName(_ mode: Int) -> String {
        switch mode {
        case 1: return L("symmetric active")
        case 2: return L("symmetric passive")
        case 3: return L("client")
        case 4: return L("server")
        case 5: return L("broadcast")
        default:
            return String(format: L("mode %lld"),
                          mode)
        }
    }

    /// One NTP timestamp as it reads:
    /// the raw seconds word against the
    /// 1900 epoch, and the Unix reading
    /// when the value lands in range.
    static func ntpStamp(_ b: [UInt8], _ at: Int)
        -> String {
        let seconds = u32be(b, at) ?? 0
        let fraction = u32be(b, at + 4) ?? 0
        if seconds > 2_208_988_800 {
            let unix = seconds - 2_208_988_800
            return String(
                format: L("unix %lld.%@"),
                unix, hexDumpWord(fraction, 8))
        }
        return String(
            format: L("%lld.%@ since 1900"),
            seconds, hexDumpWord(fraction, 8))
    }

    static func ntp(_ b: [UInt8], at: Int,
                    end: Int, sport: Int,
                    dport: Int, _ acc: Accum)
        -> BFNode? {
        guard sport == 123 || dport == 123
        else { return nil }
        guard end - at >= 48 else { return nil }
        let first = u8(b, at) ?? 0
        let version = (first >> 3) & 0x07
        let mode = first & 0x07
        guard version >= 1 && version <= 4
                && mode >= 1 && mode <= 5
        else { return nil }
        acc.proto = "NTP"
        acc.protocols.insert("ntp")
        let stratum = u8(b, at + 1) ?? 0
        let poll = u8(b, at + 2) ?? 0
        let precision = Int8(
            bitPattern: UInt8(u8(b, at + 3) ?? 0))
        var node = BFNode(
            L("Network Time Protocol"),
            String(format: L("v%lld, %@"),
                   version, ntpModeName(mode)),
            at..<end)
        node.children.append(BFNode(
            L("Version"),
            String(format: "%lld", version),
            at..<(at + 1)))
        node.children.append(BFNode(
            L("Mode"), ntpModeName(mode),
            at..<(at + 1)))
        var stratumDetail = String(
            format: "%lld", stratum)
        if stratum == 0 {
            stratumDetail += " — " + L("unspecified; the reference ID below is a kiss code")
        } else if stratum == 1 {
            stratumDetail += " — " + L("a primary server, speaking for a reference clock")
        } else if stratum >= 16 {
            stratumDetail += " — " + L("unsynchronised, by its own word")
        }
        node.children.append(BFNode(
            L("Stratum"), stratumDetail,
            (at + 1)..<(at + 2)))
        node.children.append(BFNode(
            L("Poll interval"),
            String(format: L("2^%lld seconds"),
                   poll),
            (at + 2)..<(at + 3)))
        node.children.append(BFNode(
            L("Precision"),
            String(format: L("2^%lld seconds"),
                   Int(precision)),
            (at + 3)..<(at + 4)))
        let refAt = at + 12
        if stratum <= 1 {
            node.children.append(BFNode(
                L("Reference ID"),
                textRender(Array(b[refAt..<(refAt + 4)])),
                refAt..<(refAt + 4)))
        } else {
            node.children.append(BFNode(
                L("Reference ID"),
                ipv4String(b, refAt),
                refAt..<(refAt + 4)))
        }
        let stamps: [(String, Int)] = [
            (L("Reference timestamp"), at + 16),
            (L("Origin timestamp"), at + 24),
            (L("Receive timestamp"), at + 32),
            (L("Transmit timestamp"), at + 40),
        ]
        for stamp in stamps {
            node.children.append(BFNode(
                stamp.0, ntpStamp(b, stamp.1),
                stamp.1..<(stamp.1 + 8)))
        }
        acc.info = String(
            format: L("NTP v%lld %@, stratum %lld"),
            version, ntpModeName(mode), stratum)
        return node
    }

    // MARK: TFTP

    static func tftp(_ b: [UInt8], at: Int,
                     end: Int, sport: Int,
                     dport: Int, _ acc: Accum)
        -> BFNode? {
        guard sport == 69 || dport == 69
        else { return nil }
        guard end - at >= 2,
              let opcode = u16be(b, at),
              opcode >= 1 && opcode <= 5
        else { return nil }
        acc.proto = "TFTP"
        acc.protocols.insert("tftp")
        let names: [Int: String] = [
            1: L("Read request"), 2: L("Write request"),
            3: L("Data"), 4: L("Acknowledgment"),
            5: L("Error"),
        ]
        var node = BFNode(
            L("Trivial File Transfer Protocol"),
            names[opcode] ?? "", at..<end)
        node.children.append(BFNode(
            L("Opcode"),
            String(format: "%lld — %@",
                   opcode, names[opcode] ?? ""),
            at..<(at + 2)))
        var info = String(format: L("TFTP %@"),
                          names[opcode] ?? "")
        switch opcode {
        case 1, 2:
            let rest = Array(b[(at + 2)..<end])
            let parts = rest.split(
                separator: 0,
                omittingEmptySubsequences: false)
            if parts.count >= 1 {
                let file = String(
                    decoding: parts[0], as: UTF8.self)
                node.children.append(BFNode(
                    L("Filename"), file,
                    (at + 2)..<end))
                info += " " + file
            }
            if parts.count >= 2 {
                node.children.append(BFNode(
                    L("Mode"),
                    String(decoding: parts[1],
                           as: UTF8.self),
                    (at + 2)..<end))
            }
        case 3:
            guard end - at >= 4,
                  let block = u16be(b, at + 2)
            else { break }
            node.children.append(BFNode(
                L("Block"),
                String(format: "%lld", block),
                (at + 2)..<(at + 4)))
            node.children.append(BFNode(
                L("Data"),
                String(format: L("%lld bytes"),
                       end - at - 4),
                (at + 4)..<end))
            info += String(format: L(" block %lld"),
                           block)
        case 4:
            guard end - at >= 4,
                  let block = u16be(b, at + 2)
            else { break }
            node.children.append(BFNode(
                L("Block"),
                String(format: "%lld", block),
                (at + 2)..<(at + 4)))
            info += String(format: L(" block %lld"),
                           block)
        case 5:
            guard end - at >= 4,
                  let codeErr = u16be(b, at + 2)
            else { break }
            let rawMessage = textRender(
                Array(b[(at + 4)..<end]))
            let message = rawMessage
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "\0"))
            node.children.append(BFNode(
                L("Error code"),
                String(format: "%lld", codeErr),
                (at + 2)..<(at + 4)))
            node.children.append(BFNode(
                L("Error message"), message,
                (at + 4)..<end))
            info += String(format: L(" — %@"),
                           message)
        default:
            break
        }
        acc.info = info
        return node
    }
}

// MARK: - TLS (B2)

extension Betafisch {

    static func tlsVersionName(_ v: Int) -> String {
        switch v {
        case 0x0300: return "SSL 3.0"
        case 0x0301: return "TLS 1.0"
        case 0x0302: return "TLS 1.1"
        case 0x0303: return "TLS 1.2"
        case 0x0304: return "TLS 1.3"
        default:
            return String(format: "0x%@",
                          hexDumpWord(v, 4))
        }
    }

    static func tlsCipherName(_ suite: Int) -> String {
        let known: [Int: String] = [
            0x1301: "TLS_AES_128_GCM_SHA256",
            0x1302: "TLS_AES_256_GCM_SHA384",
            0x1303: "TLS_CHACHA20_POLY1305_SHA256",
            0xC02B: "ECDHE-ECDSA-AES128-GCM-SHA256",
            0xC02C: "ECDHE-ECDSA-AES256-GCM-SHA384",
            0xC02F: "ECDHE-RSA-AES128-GCM-SHA256",
            0xC030: "ECDHE-RSA-AES256-GCM-SHA384",
            0xCCA8: "ECDHE-RSA-CHACHA20-POLY1305",
            0xCCA9: "ECDHE-ECDSA-CHACHA20-POLY1305",
            0x009C: "RSA-AES128-GCM-SHA256",
            0x009D: "RSA-AES256-GCM-SHA384",
            0x002F: "RSA-AES128-SHA",
            0x0035: "RSA-AES256-SHA",
            0x000A: "RSA-3DES-SHA",
        ]
        return known[suite]
            ?? String(format: "0x%@",
                      hexDumpWord(suite, 4))
    }

    static func tlsGroupName(_ group: Int) -> String {
        let known: [Int: String] = [
            23: "secp256r1", 24: "secp384r1",
            25: "secp521r1", 29: "x25519",
            30: "x448", 256: "ffdhe2048",
            257: "ffdhe3072", 258: "ffdhe4096",
        ]
        return known[group]
            ?? String(format: "%lld", group)
    }

    /// The record layer, and the handshake
    /// claims a plaintext stretch carries:
    /// ClientHello and ServerHello fields,
    /// the certificate as DER read by the
    /// house parser. Sealed stretches are
    /// named sealed — their plaintext is
    /// not in the capture and is not
    /// guessed at.
    static func tls(_ b: [UInt8], at: Int,
                    end: Int, _ acc: Accum)
        -> BFNode? {
        guard end - at >= 5 else { return nil }
        let firstType = u8(b, at) ?? 0
        let firstVersion = u16be(b, at + 1) ?? 0
        let recordTypes: Set<Int> = [20, 21, 22, 23]
        guard recordTypes.contains(firstType),
              firstVersion >= 0x0300,
              firstVersion <= 0x0304
        else { return nil }
        acc.proto = "TLS"
        acc.protocols.insert("tls")
        var node = BFNode(
            L("Transport Layer Security"), "",
            at..<end)
        var cursor = at
        var records = 0
        var info = ""
        while cursor + 5 <= end && records < 8 {
            records += 1
            let type = u8(b, cursor) ?? 0
            let version = u16be(b, cursor + 1) ?? 0
            let length = u16be(b, cursor + 3) ?? 0
            let bodyAt = cursor + 5
            let have = min(length, end - bodyAt)
            var record = BFNode(
                tlsRecordName(type),
                String(format: L("%@ — %lld bytes claimed, %lld in this segment"),
                       tlsVersionName(version),
                       length, max(0, have)),
                cursor..<min(end, bodyAt + max(0, have)))
            switch type {
            case 22:
                let said = tlsHandshake(
                    b, at: bodyAt,
                    end: bodyAt + max(0, have),
                    into: &record)
                if info.isEmpty, let said {
                    info = said
                }
            case 20:
                record.children.append(BFNode(
                    L("ChangeCipherSpec"),
                    L("the cipher changes here — what follows is sealed under keys the capture does not hold"),
                    bodyAt..<min(end, bodyAt + max(0, have))))
            case 21:
                if have >= 2,
                   let level = u8(b, bodyAt),
                   let desc = u8(b, bodyAt + 1) {
                    record.children.append(BFNode(
                        L("Alert"),
                        String(format: "%@ — %@",
                               level == 2
                                   ? L("fatal")
                                   : L("warning"),
                               tlsAlertName(desc)),
                        bodyAt..<(bodyAt + 2)))
                    if info.isEmpty {
                        info = String(
                            format: L("TLS alert — %@"),
                            tlsAlertName(desc))
                    }
                }
            case 23:
                record.children.append(BFNode(
                    L("Application data"),
                    String(format: L("%lld bytes, sealed — the plaintext is not in the capture"),
                           length),
                    bodyAt..<min(end, bodyAt + max(0, have))))
            default:
                break
            }
            node.children.append(record)
            if length > have { break }
            cursor = bodyAt + length
        }
        if info.isEmpty {
            info = String(
                format: L("TLS — %lld record(s) in this segment"),
                records)
        }
        node.detail = info
        acc.info = info
        return node
    }

    static func tlsRecordName(_ type: Int) -> String {
        switch type {
        case 20: return L("ChangeCipherSpec")
        case 21: return L("Alert")
        case 22: return L("Handshake")
        case 23: return L("Application data")
        case 24: return L("Heartbeat")
        default:
            return String(format: L("record type %lld"),
                          type)
        }
    }

    static func tlsAlertName(_ code: Int) -> String {
        let known: [Int: String] = [
            0: L("close_notify"),
            10: L("unexpected_message"),
            20: L("bad_record_mac"),
            40: L("handshake_failure"),
            42: L("bad_certificate"),
            43: L("unsupported_certificate"),
            45: L("certificate_expired"),
            47: L("illegal_parameter"),
            48: L("unknown_ca"),
            50: L("decode_error"),
            70: L("protocol_version"),
            71: L("insufficient_security"),
            80: L("internal_error"),
            90: L("user_canceled"),
            109: L("missing_extension"),
            110: L("unsupported_extension"),
            112: L("unrecognized_name"),
            116: L("certificate_required"),
            120: L("no_application_protocol"),
        ]
        return known[code]
            ?? String(format: L("alert %lld"), code)
    }

    /// The handshake messages inside one
    /// record's stretch. Returns the
    /// list-line summary the first hello
    /// earns, if any.
    static func tlsHandshake(_ b: [UInt8], at: Int,
                             end: Int,
                             into record: inout BFNode)
        -> String? {
        var cursor = at
        var summary: String? = nil
        var messages = 0
        while cursor + 4 <= end && messages < 4 {
            messages += 1
            let hsType = u8(b, cursor) ?? 0
            let hsLength = ((u8(b, cursor + 1) ?? 0) << 16)
                | ((u8(b, cursor + 2) ?? 0) << 8)
                | (u8(b, cursor + 3) ?? 0)
            let bodyAt = cursor + 4
            let have = min(hsLength, end - bodyAt)
            var message = BFNode(
                tlsHandshakeName(hsType),
                String(format: L("%lld bytes claimed, %lld in this segment"),
                       hsLength, max(0, have)),
                cursor..<min(end, bodyAt + max(0, have)))
            switch hsType {
            case 1:
                if let said = tlsClientHello(
                    b, at: bodyAt,
                    end: bodyAt + max(0, have),
                    into: &message) {
                    summary = said
                }
            case 2:
                if let said = tlsServerHello(
                    b, at: bodyAt,
                    end: bodyAt + max(0, have),
                    into: &message) {
                    summary = said
                }
            case 11:
                tlsCertificate(
                    b, at: bodyAt,
                    end: bodyAt + max(0, have),
                    into: &message)
            default:
                break
            }
            if hsLength > have {
                message.children.append(BFNode(
                    L("Continuation"),
                    L("the message runs past this segment — its tail rides in a later one"),
                    bodyAt..<end))
            }
            record.children.append(message)
            if hsLength > have { break }
            cursor = bodyAt + hsLength
        }
        return summary
    }

    static func tlsHandshakeName(_ type: Int)
        -> String {
        switch type {
        case 0: return L("HelloRequest")
        case 1: return L("ClientHello")
        case 2: return L("ServerHello")
        case 4: return L("NewSessionTicket")
        case 8: return L("EncryptedExtensions")
        case 11: return L("Certificate")
        case 12: return L("ServerKeyExchange")
        case 13: return L("CertificateRequest")
        case 14: return L("ServerHelloDone")
        case 15: return L("CertificateVerify")
        case 16: return L("ClientKeyExchange")
        case 20: return L("Finished")
        default:
            return String(format: L("handshake type %lld"),
                          type)
        }
    }

    /// The extension walk both hellos
    /// share. Returns the interesting
    /// claims (SNI, ALPN, versions, key
    /// shares) as read, for the summary.
    static func tlsExtensions(
        _ b: [UInt8], at: Int, end: Int,
        server: Bool, into node: inout BFNode)
        -> (sni: String?, alpn: [String],
            version: Int?, groups: [String]) {
        var sni: String? = nil
        var alpn: [String] = []
        var version: Int? = nil
        var groups: [String] = []
        var cursor = at
        var steps = 0
        while cursor + 4 <= end && steps < 32 {
            steps += 1
            guard let extType = u16be(b, cursor),
                  let extLen = u16be(b, cursor + 2),
                  cursor + 4 + extLen <= end
            else {
                node.children.append(BFNode(
                    L("extension"),
                    L("its length runs past the message"),
                    cursor..<end))
                break
            }
            let valueAt = cursor + 4
            let valueEnd = valueAt + extLen
            var title = String(
                format: L("extension %lld"), extType)
            var detail = String(
                format: L("%lld bytes"), extLen)
            switch extType {
            case 0:
                title = L("server_name (SNI)")
                if extLen >= 5,
                   let nameLen = u16be(b, valueAt + 3),
                   valueAt + 5 + nameLen <= valueEnd {
                    let name = String(
                        decoding: b[(valueAt + 5)..<(valueAt + 5 + nameLen)],
                        as: UTF8.self)
                    sni = name
                    detail = name
                }
            case 16:
                title = L("ALPN")
                if extLen >= 2,
                   let listLen = u16be(b, valueAt) {
                    var walk = valueAt + 2
                    let listEnd = min(valueEnd,
                                      walk + listLen)
                    while walk < listEnd,
                          let n = u8(b, walk),
                          walk + 1 + n <= listEnd {
                        alpn.append(String(
                            decoding: b[(walk + 1)..<(walk + 1 + n)],
                            as: UTF8.self))
                        walk += 1 + n
                    }
                    detail = alpn.joined(separator: ", ")
                }
            case 43:
                title = L("supported_versions")
                if server {
                    if let v = u16be(b, valueAt) {
                        version = v
                        detail = tlsVersionName(v)
                    }
                } else {
                    var names: [String] = []
                    if extLen >= 1,
                       let count = u8(b, valueAt) {
                        var walk = valueAt + 1
                        let listEnd = min(
                            valueEnd, walk + count)
                        while walk + 2 <= listEnd,
                              let v = u16be(b, walk) {
                            names.append(
                                tlsVersionName(v))
                            if version == nil {
                                version = v
                            }
                            walk += 2
                        }
                    }
                    detail = names.joined(
                        separator: ", ")
                }
            case 51:
                title = L("key_share")
                var names: [String] = []
                if server {
                    if let g = u16be(b, valueAt) {
                        names.append(tlsGroupName(g))
                        groups = names
                    }
                } else if extLen >= 2,
                          let listLen = u16be(b, valueAt) {
                    var walk = valueAt + 2
                    let listEnd = min(valueEnd,
                                      walk + listLen)
                    while walk + 4 <= listEnd,
                          let g = u16be(b, walk),
                          let klen = u16be(b, walk + 2) {
                        names.append(String(
                            format: L("%@ (%lld key bytes)"),
                            tlsGroupName(g), klen))
                        groups.append(tlsGroupName(g))
                        walk += 4 + klen
                    }
                }
                detail = names.joined(separator: ", ")
            case 10:
                title = L("supported_groups")
                var names: [String] = []
                if extLen >= 2,
                   let listLen = u16be(b, valueAt) {
                    var walk = valueAt + 2
                    let listEnd = min(valueEnd,
                                      walk + listLen)
                    while walk + 2 <= listEnd,
                          let g = u16be(b, walk) {
                        names.append(tlsGroupName(g))
                        walk += 2
                    }
                }
                detail = names.joined(separator: ", ")
            case 13:
                title = L("signature_algorithms")
                detail = String(
                    format: L("%lld offered"),
                    max(0, (extLen - 2) / 2))
            default:
                break
            }
            node.children.append(BFNode(
                title, detail, cursor..<valueEnd))
            cursor = valueEnd
        }
        return (sni, alpn, version, groups)
    }

    static func tlsClientHello(
        _ b: [UInt8], at: Int, end: Int,
        into node: inout BFNode) -> String? {
        guard end - at >= 35,
              let legacy = u16be(b, at)
        else { return nil }
        node.children.append(BFNode(
            L("Version (as claimed)"),
            tlsVersionName(legacy),
            at..<(at + 2)))
        var cursor = at + 2 + 32
        guard cursor < end,
              let sidLen = u8(b, cursor)
        else { return nil }
        cursor += 1 + sidLen
        guard cursor + 2 <= end,
              let suitesLen = u16be(b, cursor)
        else { return nil }
        cursor += 2
        var suites: [String] = []
        var walk = cursor
        while walk + 2 <= min(end, cursor + suitesLen),
              let suite = u16be(b, walk) {
            suites.append(tlsCipherName(suite))
            walk += 2
        }
        node.children.append(BFNode(
            L("Cipher suites offered"),
            suites.joined(separator: ", "),
            cursor..<min(end, cursor + suitesLen)))
        cursor += suitesLen
        guard cursor < end,
              let compLen = u8(b, cursor)
        else { return nil }
        cursor += 1 + compLen
        var summary = L("ClientHello")
        guard cursor + 2 <= end,
              let extTotal = u16be(b, cursor)
        else { return summary }
        cursor += 2
        var extNode = BFNode(
            L("Extensions"), "",
            cursor..<min(end, cursor + extTotal))
        let found = tlsExtensions(
            b, at: cursor,
            end: min(end, cursor + extTotal),
            server: false, into: &extNode)
        extNode.range = cursor..<min(
            end, cursor + extTotal)
        node.children.append(extNode)
        if let sni = found.sni {
            summary += String(format: L(" — SNI %@"),
                              sni)
        }
        if !found.alpn.isEmpty {
            summary += String(
                format: L(" — ALPN %@"),
                found.alpn.joined(separator: ", "))
        }
        if let version = found.version {
            summary += String(
                format: L(" — offers up to %@"),
                tlsVersionName(version))
        }
        return summary
    }

    static func tlsServerHello(
        _ b: [UInt8], at: Int, end: Int,
        into node: inout BFNode) -> String? {
        guard end - at >= 38,
              let legacy = u16be(b, at)
        else { return nil }
        var cursor = at + 2 + 32
        guard cursor < end,
              let sidLen = u8(b, cursor)
        else { return nil }
        cursor += 1 + sidLen
        guard cursor + 2 <= end,
              let cipher = u16be(b, cursor)
        else { return nil }
        node.children.append(BFNode(
            L("Cipher chosen"),
            tlsCipherName(cipher),
            cursor..<(cursor + 2)))
        cursor += 2
        guard cursor < end else { return nil }
        cursor += 1
        var effective = legacy
        if cursor + 2 <= end,
           let extTotal = u16be(b, cursor) {
            cursor += 2
            var extNode = BFNode(
                L("Extensions"), "",
                cursor..<min(end, cursor + extTotal))
            let found = tlsExtensions(
                b, at: cursor,
                end: min(end, cursor + extTotal),
                server: true, into: &extNode)
            node.children.append(extNode)
            if let v = found.version {
                effective = v
            }
        }
        return String(
            format: L("ServerHello — %@, %@"),
            tlsVersionName(effective),
            tlsCipherName(cipher))
    }

    /// The certificate chain, read with
    /// the house DER parser the bench
    /// already trusts. Both wire shapes:
    /// TLS 1.2's bare list and 1.3's
    /// context word in front of it.
    static func tlsCertificate(
        _ b: [UInt8], at: Int, end: Int,
        into node: inout BFNode) {
        var cursor = at
        var listLen: Int? = nil
        var tls13Shape = false
        // The two shapes are told apart by
        // which length word accounts for
        // the body exactly: TLS 1.2's bare
        // list, or 1.3's context word in
        // front of the list. Exact fit
        // wins; a loose fit falls back to
        // the bare reading.
        let bare = u24be(b, at)
        let bareExact = bare != nil
            && bare == end - at - 3
        var contextLen = 0
        var wrapped: Int? = nil
        if end - at >= 5,
           let ctx = u8(b, at), ctx <= 32,
           end - at >= 4 + ctx {
            contextLen = ctx
            wrapped = u24be(b, at + 1 + ctx)
        }
        let wrappedExact = wrapped != nil
            && wrapped == end - at - 4 - contextLen
        if wrappedExact && !bareExact {
            listLen = wrapped
            tls13Shape = true
            cursor = at + 1 + contextLen + 3
        } else if let bare,
                  bare <= end - at - 3 {
            listLen = bare
            cursor = at + 3
        } else if let wrapped,
                  wrapped <= end - at - 4 - contextLen {
            listLen = wrapped
            tls13Shape = true
            cursor = at + 1 + contextLen + 3
        }
        guard let total = listLen else {
            node.children.append(BFNode(
                L("Certificates"),
                L("the chain's length word does not parse — the bytes are left unread"),
                at..<end))
            return
        }
        let listEnd = min(end, cursor + total)
        var index = 0
        while cursor + 3 <= listEnd && index < 8 {
            guard let certLen = u24be(b, cursor),
                  cursor + 3 + certLen <= end
            else { break }
            index += 1
            let der = Array(
                b[(cursor + 3)..<(cursor + 3 + certLen)])
            var detail = String(
                format: L("%lld DER bytes"), certLen)
            if let cert = BlacksiteBench
                .lockCertParse(der) {
                detail = String(
                    format: L("subject %@ — issued by %@"),
                    cert.subjectLine, cert.issuerLine)
            }
            node.children.append(BFNode(
                String(format: L("certificate %lld"),
                       index),
                detail, cursor..<(cursor + 3 + certLen)))
            cursor += 3 + certLen
            // A TLS 1.3 entry carries an
            // extension block behind the
            // certificate; step over it so
            // the next entry lines up.
            if tls13Shape, cursor + 2 <= listEnd,
               let extLen = u16be(b, cursor),
               cursor + 2 + extLen <= listEnd {
                cursor += 2 + extLen
            }
        }
        if index == 0 {
            node.children.append(BFNode(
                L("Certificates"),
                L("the chain is empty, as the bytes read"),
                at..<end))
        }
    }

    static func u24be(_ b: [UInt8], _ i: Int)
        -> Int? {
        guard let hi = u8(b, i),
              let mid = u8(b, i + 1),
              let lo = u8(b, i + 2)
        else { return nil }
        return (hi << 16) | (mid << 8) | lo
    }
}

// MARK: - HTTP/2 (B2)

extension Betafisch {

    static let http2Preface: [UInt8] = Array(
        "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".utf8)

    static func http2(_ b: [UInt8], at: Int,
                      end: Int, _ acc: Accum)
        -> BFNode? {
        var cursor = at
        var prefaceSeen = false
        if end - at >= http2Preface.count {
            let head = Array(
                b[at..<(at + http2Preface.count)])
            if head == http2Preface {
                prefaceSeen = true
                cursor = at + http2Preface.count
            }
        }
        if !prefaceSeen {
            // A server's first flight opens
            // with SETTINGS: a nine-byte
            // header whose length is a
            // multiple of six, stream zero.
            guard end - at >= 9,
                  let length = u24be(b, at),
                  u8(b, at + 3) == 4,
                  u32be(b, at + 5) != nil,
                  (u32be(b, at + 5) ?? 0)
                    & 0x7fffffff == 0,
                  length % 6 == 0,
                  length <= end - at - 9
            else { return nil }
        }
        acc.proto = "HTTP/2"
        acc.protocols.insert("http2")
        var node = BFNode(
            L("HTTP/2"), "", at..<end)
        if prefaceSeen {
            node.children.append(BFNode(
                L("Client preface"),
                "PRI * HTTP/2.0",
                at..<(at + http2Preface.count)))
        }
        var names: [String] = []
        var frames = 0
        while cursor + 9 <= end && frames < 16 {
            frames += 1
            let length = u24be(b, cursor) ?? 0
            let type = u8(b, cursor + 3) ?? 0
            let flags = u8(b, cursor + 4) ?? 0
            let stream = (u32be(b, cursor + 5) ?? 0)
                & 0x7fffffff
            let bodyAt = cursor + 9
            let have = min(length, end - bodyAt)
            var frame = BFNode(
                http2FrameName(type),
                String(format: L("stream %lld — %lld bytes"),
                       stream, length),
                cursor..<min(end, bodyAt
                             + max(0, have)))
            if names.count < 4 {
                names.append(http2FrameName(type))
            }
            switch type {
            case 4:
                if flags & 0x1 != 0 {
                    frame.detail += " — " + L("acknowledgment")
                } else {
                    var walk = bodyAt
                    let stop = bodyAt + max(0, have)
                    while walk + 6 <= stop,
                          let sid = u16be(b, walk),
                          let value = u32be(b, walk + 2) {
                        frame.children.append(BFNode(
                            http2SettingName(sid),
                            String(format: "%lld", value),
                            walk..<(walk + 6)))
                        walk += 6
                    }
                }
            case 1, 9:
                frame.children.append(BFNode(
                    L("Header block"),
                    L("HPACK-coded — betafisch reads the frame, not the coded headers"),
                    bodyAt..<min(end, bodyAt + max(0, have))))
            case 0:
                frame.children.append(BFNode(
                    L("Data"),
                    String(format: L("%lld bytes ride in the frame — read as data, never rendered"),
                           length),
                    bodyAt..<min(end, bodyAt + max(0, have))))
            case 6:
                frame.detail += flags & 0x1 != 0
                    ? " — " + L("acknowledgment")
                    : " — " + L("ping")
            case 7:
                if have >= 8,
                   let lastID = u32be(b, bodyAt),
                   let codeErr = u32be(b, bodyAt + 4) {
                    frame.children.append(BFNode(
                        L("Last stream"),
                        String(format: "%lld",
                               lastID & 0x7fffffff),
                        bodyAt..<(bodyAt + 4)))
                    frame.children.append(BFNode(
                        L("Error"),
                        http2ErrorName(codeErr),
                        (bodyAt + 4)..<(bodyAt + 8)))
                }
            case 8:
                if have >= 4,
                   let jump = u32be(b, bodyAt) {
                    frame.children.append(BFNode(
                        L("Window grows by"),
                        String(format: "%lld",
                               jump & 0x7fffffff),
                        bodyAt..<(bodyAt + 4)))
                }
            case 3:
                if have >= 4,
                   let codeErr = u32be(b, bodyAt) {
                    frame.children.append(BFNode(
                        L("Error"),
                        http2ErrorName(codeErr),
                        bodyAt..<(bodyAt + 4)))
                }
            default:
                break
            }
            node.children.append(frame)
            if length > have { break }
            cursor = bodyAt + length
        }
        let summary = names.isEmpty
            ? L("HTTP/2")
            : "HTTP/2 — " + names.joined(
                separator: ", ")
        node.detail = summary
        acc.info = summary
        return node
    }

    static func http2FrameName(_ type: Int) -> String {
        switch type {
        case 0: return "DATA"
        case 1: return "HEADERS"
        case 2: return "PRIORITY"
        case 3: return "RST_STREAM"
        case 4: return "SETTINGS"
        case 5: return "PUSH_PROMISE"
        case 6: return "PING"
        case 7: return "GOAWAY"
        case 8: return "WINDOW_UPDATE"
        case 9: return "CONTINUATION"
        default:
            return String(format: L("frame type %lld"),
                          type)
        }
    }

    static func http2SettingName(_ id: Int) -> String {
        switch id {
        case 1: return "HEADER_TABLE_SIZE"
        case 2: return "ENABLE_PUSH"
        case 3: return "MAX_CONCURRENT_STREAMS"
        case 4: return "INITIAL_WINDOW_SIZE"
        case 5: return "MAX_FRAME_SIZE"
        case 6: return "MAX_HEADER_LIST_SIZE"
        default:
            return String(format: L("setting %lld"), id)
        }
    }

    static func http2ErrorName(_ code: Int) -> String {
        let known: [Int: String] = [
            0: "NO_ERROR", 1: "PROTOCOL_ERROR",
            2: "INTERNAL_ERROR",
            3: "FLOW_CONTROL_ERROR",
            4: "SETTINGS_TIMEOUT",
            5: "STREAM_CLOSED",
            6: "FRAME_SIZE_ERROR",
            7: "REFUSED_STREAM", 8: "CANCEL",
            9: "COMPRESSION_ERROR",
            10: "CONNECT_ERROR",
            11: "ENHANCE_YOUR_CALM",
            12: "INADEQUATE_SECURITY",
            13: "HTTP_1_1_REQUIRED",
        ]
        return known[code]
            ?? String(format: L("error %lld"), code)
    }
}

// MARK: - SMB (B2)

extension Betafisch {

    /// Server Message Block, both
    /// generations, read at the header:
    /// the command, the direction, the
    /// status, and — for an SMB2
    /// negotiate answer — the dialect
    /// the server claims. The deep read
    /// stops at the header; the dialect
    /// jungles below it are not walked.
    static func smb(_ b: [UInt8], at: Int,
                    end: Int, sport: Int,
                    dport: Int, _ acc: Accum)
        -> BFNode? {
        var base = at
        // A NetBIOS session header may
        // ride in front: type byte zero
        // and a length that exactly
        // covers what follows.
        if end - at >= 8,
           u8(b, at) == 0,
           let wrapped = u24be(b, at + 1),
           wrapped == end - at - 4 {
            base = at + 4
        }
        guard end - base >= 4 else { return nil }
        let magic0 = u8(b, base) ?? 0
        let magicOK = (magic0 == 0xff || magic0 == 0xfe)
            && u8(b, base + 1) == 0x53
            && u8(b, base + 2) == 0x4d
            && u8(b, base + 3) == 0x42
        let portOK = sport == 445 || dport == 445
            || sport == 139 || dport == 139
        guard magicOK && (portOK || base > at)
        else { return nil }
        acc.proto = "SMB"
        acc.protocols.insert("smb")
        if magic0 == 0xff {
            return smb1(b, at: base, end: end, acc,
                        wrapped: base > at)
        }
        return smb2(b, at: base, end: end, acc,
                    wrapped: base > at)
    }

    static func smb1(_ b: [UInt8], at: Int,
                     end: Int, _ acc: Accum,
                     wrapped: Bool) -> BFNode {
        var node = BFNode(
            L("Server Message Block (SMB1)"),
            "", at..<end)
        if wrapped {
            node.children.append(BFNode(
                L("NetBIOS session service"),
                L("a four-byte header rides in front"),
                (at - 4)..<at))
        }
        guard end - at >= 32 else {
            node.detail = L("the header is truncated")
            acc.info = L("SMB1 — truncated header")
            return node
        }
        let command = u8(b, at + 8) ?? 0
        let status = u32(b, at + 5, little: true) ?? 0
        let commands: [Int: String] = [
            0x72: "NEGOTIATE", 0x73: "SESSION_SETUP",
            0x74: "LOGOFF", 0x75: "TREE_CONNECT",
            0x25: "TRANSACT", 0x2d: "OPEN_ANDX",
            0x2e: "READ_ANDX", 0x2f: "WRITE_ANDX",
            0x32: "TRANSACT2", 0xa2: "NT_CREATE_ANDX",
            0xff: "LOCKING_ANDX",
        ]
        let name = commands[command]
            ?? String(format: "0x%@",
                      hexDumpWord(command, 2))
        node.children.append(BFNode(
            L("Command"),
            String(format: "%@ (0x%@)", name,
                   hexDumpWord(command, 2)),
            (at + 8)..<(at + 9)))
        node.children.append(BFNode(
            L("Status"),
            String(format: "0x%@",
                   hexDumpWord(status, 8)),
            (at + 5)..<(at + 9)))
        node.detail = String(format: L("SMB1 %@"),
                             name)
        node.children.append(BFNode(
            L("Depth"),
            L("the read stops at the header — SMB1's dialect jungles are not walked"),
            at..<min(end, at + 32)))
        acc.info = node.detail
        return node
    }

    static func smb2(_ b: [UInt8], at: Int,
                     end: Int, _ acc: Accum,
                     wrapped: Bool) -> BFNode {
        var node = BFNode(
            L("Server Message Block (SMB2)"),
            "", at..<end)
        if wrapped {
            node.children.append(BFNode(
                L("NetBIOS session service"),
                L("a four-byte header rides in front"),
                (at - 4)..<at))
        }
        guard end - at >= 64 else {
            node.detail = L("the header is truncated")
            acc.info = L("SMB2 — truncated header")
            return node
        }
        let status = u32(b, at + 8, little: true) ?? 0
        let command = u16(b, at + 12,
                          little: true) ?? 0
        let flags = u32(b, at + 16,
                        little: true) ?? 0
        let isResponse = flags & 0x1 != 0
        let commands: [Int: String] = [
            0: "NEGOTIATE", 1: "SESSION_SETUP",
            2: "LOGOFF", 3: "TREE_CONNECT",
            4: "TREE_DISCONNECT", 5: "CREATE",
            6: "CLOSE", 7: "FLUSH", 8: "READ",
            9: "WRITE", 10: "LOCK", 11: "IOCTL",
            12: "CANCEL", 13: "ECHO",
            14: "QUERY_DIRECTORY",
            15: "CHANGE_NOTIFY", 16: "QUERY_INFO",
            17: "SET_INFO", 18: "OPLOCK_BREAK",
        ]
        let name = commands[command]
            ?? String(format: L("command %lld"),
                      command)
        node.children.append(BFNode(
            L("Command"), name,
            (at + 12)..<(at + 14)))
        node.children.append(BFNode(
            L("Direction"),
            isResponse ? L("a response — server to client")
                : L("a request — client to server"),
            (at + 16)..<(at + 20)))
        node.children.append(BFNode(
            L("Status"),
            String(format: "0x%@%@",
                   hexDumpWord(status, 8),
                   status == 0
                       ? " — " + L("success, as the server claims") : ""),
            (at + 8)..<(at + 12)))
        if flags & 0x8 != 0 {
            node.children.append(BFNode(
                L("Signed"),
                L("the header carries a signature"),
                (at + 16)..<(at + 20)))
        }
        var summary = String(
            format: L("SMB2 %@%@"), name,
            isResponse ? L(" response") : "")
        // A negotiate answer names the
        // dialect the server settled on.
        if command == 0 && isResponse
            && end - at >= 72,
           let dialect = u16(b, at + 68,
                             little: true) {
            let dialects: [Int: String] = [
                0x0202: "SMB 2.0.2", 0x0210: "SMB 2.1",
                0x0300: "SMB 3.0", 0x0302: "SMB 3.0.2",
                0x0311: "SMB 3.1.1",
            ]
            let word = dialects[dialect]
                ?? String(format: "0x%@",
                          hexDumpWord(dialect, 4))
            node.children.append(BFNode(
                L("Dialect"),
                String(format: L("%@ — the server's claim"),
                       word),
                (at + 68)..<(at + 70)))
            summary += String(format: L(" — %@"),
                              word)
        }
        node.detail = summary
        acc.info = summary
        return node
    }

    // MARK: The quoted packet in an ICMP error

    /// The original packet an ICMP error
    /// quotes back — header fields only,
    /// read inside a throwaway walk that
    /// never touches the frame's own
    /// line. Nil when the quote is too
    /// short to read.
    static func quotedIPNode(_ b: [UInt8], at: Int,
                             end: Int) -> BFNode? {
        guard end - at >= 8 else { return nil }
        let version = (u8(b, at) ?? 0) >> 4
        var node = BFNode(
            L("The packet that provoked it"),
            String(format: L("%lld bytes quoted back"),
                   end - at),
            at..<end)
        if version == 4 {
            guard end - at >= 20 else { return nil }
            let ihl = ((u8(b, at) ?? 0) & 0x0f) * 4
            let proto = u8(b, at + 9) ?? 0
            node.children.append(BFNode(
                L("Protocol"),
                String(format: "%lld — %@",
                       proto, ipProtocolName(proto)),
                (at + 9)..<(at + 10)))
            node.children.append(BFNode(
                L("Source"), ipv4String(b, at + 12),
                (at + 12)..<(at + 16)))
            node.children.append(BFNode(
                L("Destination"),
                ipv4String(b, at + 16),
                (at + 16)..<(at + 20)))
            let innerAt = at + max(20, ihl)
            if (proto == 6 || proto == 17)
                && end - innerAt >= 4,
               let sp = u16be(b, innerAt),
               let dp = u16be(b, innerAt + 2) {
                node.children.append(BFNode(
                    L("Ports"),
                    String(format: L("%lld → %lld"),
                           sp, dp),
                    innerAt..<(innerAt + 4)))
            }
            return node
        }
        if version == 6 {
            guard end - at >= 40 else { return nil }
            let next = u8(b, at + 6) ?? 0
            node.children.append(BFNode(
                L("Next header"),
                String(format: "%lld — %@",
                       next, ipProtocolName(next)),
                (at + 6)..<(at + 7)))
            node.children.append(BFNode(
                L("Source"), ipv6String(b, at + 8),
                (at + 8)..<(at + 24)))
            node.children.append(BFNode(
                L("Destination"),
                ipv6String(b, at + 24),
                (at + 24)..<(at + 40)))
            return node
        }
        return nil
    }
}

// MARK: - Follow-stream and statistics (B2)

/// One conversation, laid out to read:
/// both directions in order. TCP bytes
/// come from driftnet's reassembly —
/// the same layout the gallery carves —
/// with the holes named rather than
/// papered over. UDP bytes are the
/// datagrams in the order they arrived,
/// boundaries kept.
struct BFStream: Identifiable {
    let id = UUID()
    enum Transport {
        case tcp, udp
    }
    var transport: Transport
    var label: String
    var aLabel: String
    var bLabel: String
    var aToB: [UInt8] = []
    var bToA: [UInt8] = []
    /// UDP: each datagram's size, in
    /// arrival order, per direction.
    var aDatagrams: [Int] = []
    var bDatagrams: [Int] = []
    /// TCP: holes in each direction —
    /// stretches the capture never held.
    var aHoles = 0
    var bHoles = 0
    var torn = false
    var capped = false
    /// TCP: segments whose bytes had
    /// already arrived whole — the
    /// retransmissions, counted exactly.
    var retransmissions = 0
    var frameCount = 0
    var firstFrame = 0
    var lastFrame = 0
}

enum BFStreams {

    static func all(of capture: BFCapture)
        -> [BFStream] {
        var streams = tcpStreams(of: capture)
        streams.append(
            contentsOf: udpStreams(of: capture))
        return streams
    }

    /// Count segments that arrived whole
    /// a second time — the coverage walk
    /// mirrors driftnet's placement rules.
    static func retransmissionCount(
        _ segments: [(seq: Int, flags: Int,
                      length: Int)]) -> Int {
        var base: Int? = nil
        for segment in segments
        where (segment.flags & 0x02) != 0 {
            base = segment.seq
            break
        }
        if base == nil {
            for segment in segments
            where segment.length > 0 {
                base = segment.seq
                break
            }
        }
        guard let origin = base else { return 0 }
        var placed: [(Int, Int)] = []
        var count = 0
        for segment in segments
        where segment.length > 0 {
            var offset = BetafischDrift.seqDelta(
                origin, segment.seq)
            if (segment.flags & 0x02) != 0 {
                offset -= 1
            }
            var length = segment.length
            if offset < 0 {
                length += offset
                offset = 0
            }
            guard length > 0 else { continue }
            var covered = 0
            for span in placed {
                let lo = max(span.0, offset)
                let hi = min(span.1,
                             offset + length)
                if hi > lo { covered += hi - lo }
            }
            if covered >= length { count += 1 }
            placed.append((offset, offset + length))
            placed.sort { $0.0 < $1.0 }
            var merged: [(Int, Int)] = []
            for span in placed {
                if let last = merged.last,
                   span.0 <= last.1 {
                    merged[merged.count - 1] = (
                        last.0, max(last.1, span.1))
                } else {
                    merged.append(span)
                }
            }
            placed = merged
            if placed.count > 8192 { break }
        }
        return count
    }

    static func tcpStreams(of capture: BFCapture)
        -> [BFStream] {
        let flows = BetafischDrift.flows(
            of: capture)
        // Frame bookkeeping per flow, in
        // the same key shape drift uses.
        var books: [String: (count: Int,
                             first: Int, last: Int,
                             segments: [[(seq: Int,
                                          flags: Int,
                                          length: Int)]])] = [:]
        for frame in capture.frames {
            guard frame.isTCP,
                  let src = frame.ipSrc,
                  let dst = frame.ipDst,
                  let sport = frame.srcPort,
                  let dport = frame.dstPort,
                  let seq = frame.tcpSeq
            else { continue }
            let aLabel = "\(src):\(sport)"
            let bLabel = "\(dst):\(dport)"
            let low = min(aLabel, bLabel)
            let high = max(aLabel, bLabel)
            let key = low + " <> " + high
            let direction = aLabel == low ? 0 : 1
            var book = books[key] ?? (
                count: 0, first: frame.number,
                last: frame.number,
                segments: [[], []])
            book.count += 1
            book.first = min(book.first, frame.number)
            book.last = max(book.last, frame.number)
            let length = frame.tcpPayloadRange?
                .count ?? 0
            book.segments[direction].append((
                seq: seq, flags: frame.tcpFlags,
                length: length))
            books[key] = book
        }
        var streams: [BFStream] = []
        for flow in flows {
            let key = flow.aLabel + " <> "
                + flow.bLabel
            let book = books[key]
            var stream = BFStream(
                transport: .tcp, label: flow.label,
                aLabel: flow.aLabel,
                bLabel: flow.bLabel)
            stream.aToB = flow.aToB.runs.flatMap {
                $0.bytes
            }
            stream.bToA = flow.bToA.runs.flatMap {
                $0.bytes
            }
            stream.aHoles = max(0,
                                flow.aToB.runs.count - 1)
            stream.bHoles = max(0,
                                flow.bToA.runs.count - 1)
            stream.torn = flow.aToB.torn
                || flow.bToA.torn
            stream.capped = flow.aToB.capped
                || flow.bToA.capped
            if let book {
                stream.frameCount = book.count
                stream.firstFrame = book.first
                stream.lastFrame = book.last
                stream.retransmissions =
                    retransmissionCount(
                        book.segments[0])
                    + retransmissionCount(
                        book.segments[1])
            }
            streams.append(stream)
        }
        return streams
    }

    static func udpStreams(of capture: BFCapture)
        -> [BFStream] {
        struct Accumulating {
            var stream: BFStream
            var frames: [Int] = []
        }
        var order: [String] = []
        var byKey: [String: Accumulating] = [:]
        for frame in capture.frames {
            guard frame.isUDP,
                  let src = frame.ipSrc,
                  let dst = frame.ipDst,
                  let sport = frame.srcPort,
                  let dport = frame.dstPort,
                  let range = frame.udpPayloadRange
            else { continue }
            let aLabel = "\(src):\(sport)"
            let bLabel = "\(dst):\(dport)"
            let low = min(aLabel, bLabel)
            let high = max(aLabel, bLabel)
            let key = low + " <> " + high
            if byKey[key] == nil {
                byKey[key] = Accumulating(
                    stream: BFStream(
                        transport: .udp,
                        label: low + " ↔ " + high,
                        aLabel: low, bLabel: high))
                order.append(key)
            }
            guard var entry = byKey[key]
            else { continue }
            let lo = max(0, min(range.lowerBound,
                                frame.bytes.count))
            let hi = max(lo, min(range.upperBound,
                                  frame.bytes.count))
            let payload = Array(frame.bytes[lo..<hi])
            if aLabel == low {
                entry.stream.aToB.append(
                    contentsOf: payload)
                entry.stream.aDatagrams.append(
                    payload.count)
            } else {
                entry.stream.bToA.append(
                    contentsOf: payload)
                entry.stream.bDatagrams.append(
                    payload.count)
            }
            entry.frames.append(frame.number)
            byKey[key] = entry
        }
        var streams: [BFStream] = []
        for key in order {
            guard var entry = byKey[key]
            else { continue }
            entry.stream.frameCount =
                entry.frames.count
            entry.stream.firstFrame =
                entry.frames.first ?? 0
            entry.stream.lastFrame =
                entry.frames.last ?? 0
            streams.append(entry.stream)
        }
        return streams
    }
}

/// The capture counted, exactly: the
/// protocol hierarchy, the endpoints,
/// the conversations, and the shape of
/// lengths and time. Every number here
/// is a count of the frames in hand.
struct BFStats {
    struct ProtoRow: Identifiable {
        let id = UUID()
        var name: String
        var frames: Int
        var bytes: Int
    }
    struct EndpointRow: Identifiable {
        let id = UUID()
        var address: String
        var frames: Int
        var bytes: Int
        var sentFrames: Int
        var sentBytes: Int
        var receivedFrames: Int
        var receivedBytes: Int
    }
    struct ConvoRow: Identifiable {
        let id = UUID()
        var label: String
        var transport: String
        var frames: Int
        var bytes: Int
        var aToBFrames: Int
        var bToAFrames: Int
        var aToBBytes: Int
        var bToABytes: Int
        var startOffset: Double
        var duration: Double
    }
    var hierarchy: [ProtoRow] = []
    var endpoints: [EndpointRow] = []
    var conversations: [ConvoRow] = []
    var lengthRows: [(label: String,
                       count: Int)] = []
    var totalFrames = 0
    var totalBytes = 0
    var minLength = 0
    var maxLength = 0
    var meanLength: Double = 0
    var span: Double = 0
    var meanGap: Double = 0
    var framesPerSecond: Double = 0
    var bytesPerSecond: Double = 0
}

enum BFStatistics {

    static func compute(_ capture: BFCapture)
        -> BFStats {
        var stats = BFStats()
        let frames = capture.frames
        stats.totalFrames = frames.count
        guard !frames.isEmpty else { return stats }
        let base = frames.first?.timestamp ?? 0
        var hierarchy: [String: (frames: Int,
                                 bytes: Int)] = [:]
        var endpoints: [String: BFStats
            .EndpointRow] = [:]
        var totalBytes = 0
        var minLength = Int.max
        var maxLength = 0
        var buckets = [Int](repeating: 0, count: 7)
        let edges = [64, 128, 256, 512, 1024, 1518]
        var firstStamp = frames[0].timestamp
        var lastStamp = frames[0].timestamp
        for frame in frames {
            totalBytes += frame.origLen
            minLength = min(minLength,
                            frame.origLen)
            maxLength = max(maxLength,
                            frame.origLen)
            firstStamp = min(firstStamp,
                             frame.timestamp)
            lastStamp = max(lastStamp,
                            frame.timestamp)
            var bucket = 6
            for (index, edge) in edges.enumerated() {
                if frame.origLen < edge {
                    bucket = index
                    break
                }
            }
            buckets[bucket] += 1
            for proto in frame.protocols {
                var row = hierarchy[proto]
                    ?? (frames: 0, bytes: 0)
                row.frames += 1
                row.bytes += frame.origLen
                hierarchy[proto] = row
            }
            if let src = frame.ipSrc {
                var row = endpoints[src]
                    ?? BFStats.EndpointRow(
                        address: src, frames: 0,
                        bytes: 0, sentFrames: 0,
                        sentBytes: 0,
                        receivedFrames: 0,
                        receivedBytes: 0)
                row.frames += 1
                row.bytes += frame.origLen
                row.sentFrames += 1
                row.sentBytes += frame.origLen
                endpoints[src] = row
            }
            if let dst = frame.ipDst {
                var row = endpoints[dst]
                    ?? BFStats.EndpointRow(
                        address: dst, frames: 0,
                        bytes: 0, sentFrames: 0,
                        sentBytes: 0,
                        receivedFrames: 0,
                        receivedBytes: 0)
                row.frames += 1
                row.bytes += frame.origLen
                row.receivedFrames += 1
                row.receivedBytes += frame.origLen
                endpoints[dst] = row
            }
        }
        stats.totalBytes = totalBytes
        stats.minLength = minLength == Int.max
            ? 0 : minLength
        stats.maxLength = maxLength
        stats.meanLength = Double(totalBytes)
            / Double(frames.count)
        stats.span = lastStamp - firstStamp
        if frames.count > 1 && stats.span > 0 {
            stats.meanGap = stats.span
                / Double(frames.count - 1)
            stats.framesPerSecond =
                Double(frames.count) / stats.span
            stats.bytesPerSecond =
                Double(totalBytes) / stats.span
        }
        stats.hierarchy = hierarchy.map {
            BFStats.ProtoRow(name: $0.key,
                             frames: $0.value.frames,
                             bytes: $0.value.bytes)
        }.sorted {
            $0.frames != $1.frames
                ? $0.frames > $1.frames
                : $0.name < $1.name
        }
        stats.endpoints = endpoints.values.sorted {
            $0.bytes != $1.bytes
                ? $0.bytes > $1.bytes
                : $0.address < $1.address
        }
        let labels = ["0–63", "64–127", "128–255",
                      "256–511", "512–1023",
                      "1024–1517", "1518+"]
        stats.lengthRows = zip(labels, buckets).map {
            (label: $0.0, count: $0.1)
        }
        // Conversations: TCP and UDP flows
        // between named endpoints.
        struct Convo {
            var row: BFStats.ConvoRow
            var aLabel: String
            var firstStamp: Double
            var lastStamp: Double
        }
        var convos: [String: Convo] = [:]
        var convoOrder: [String] = []
        for frame in frames {
            guard frame.isTCP || frame.isUDP,
                  let src = frame.ipSrc,
                  let dst = frame.ipDst,
                  let sport = frame.srcPort,
                  let dport = frame.dstPort
            else { continue }
            let transport = frame.isTCP
                ? "TCP" : "UDP"
            let aLabel = "\(src):\(sport)"
            let bLabel = "\(dst):\(dport)"
            let low = min(aLabel, bLabel)
            let high = max(aLabel, bLabel)
            let key = transport + " " + low
                + " <> " + high
            if convos[key] == nil {
                convos[key] = Convo(
                    row: BFStats.ConvoRow(
                        label: low + " ↔ " + high,
                        transport: transport,
                        frames: 0, bytes: 0,
                        aToBFrames: 0, bToAFrames: 0,
                        aToBBytes: 0, bToABytes: 0,
                        startOffset: frame.timestamp
                            - base,
                        duration: 0),
                    aLabel: low,
                    firstStamp: frame.timestamp,
                    lastStamp: frame.timestamp)
                convoOrder.append(key)
            }
            guard var convo = convos[key]
            else { continue }
            convo.row.frames += 1
            convo.row.bytes += frame.origLen
            if aLabel == convo.aLabel {
                convo.row.aToBFrames += 1
                convo.row.aToBBytes += frame.origLen
            } else {
                convo.row.bToAFrames += 1
                convo.row.bToABytes += frame.origLen
            }
            convo.firstStamp = min(convo.firstStamp,
                                   frame.timestamp)
            convo.lastStamp = max(convo.lastStamp,
                                  frame.timestamp)
            convo.row.startOffset =
                convo.firstStamp - base
            convo.row.duration =
                convo.lastStamp - convo.firstStamp
            convos[key] = convo
        }
        stats.conversations = convoOrder.compactMap {
            convos[$0]?.row
        }
        return stats
    }
}

// MARK: - NetBIOS names (B2)

extension Betafisch {

    /// A NetBIOS name as DNS carries it —
    /// thirty-two letters, each a nibble
    /// in disguise — read back into the
    /// sixteen bytes it encodes: fifteen
    /// of name and one suffix byte, shown
    /// the way the house has always
    /// written them, NAME<00>. Nil when
    /// the label is not that shape.
    static func nbnsDisplayName(_ wire: String)
        -> String? {
        var label = wire
        if label.hasSuffix(".") {
            label = String(label.dropLast())
        }
        let chars = Array(label)
        guard chars.count == 32 else { return nil }
        var bytes: [UInt8] = []
        var index = 0
        while index < 32 {
            let hi = chars[index].unicodeScalars
                .first?.value ?? 0
            let lo = chars[index + 1].unicodeScalars
                .first?.value ?? 0
            guard hi >= 65 && hi <= 80
                    && lo >= 65 && lo <= 80
            else { return nil }
            bytes.append(UInt8(
                ((hi - 65) << 4) | (lo - 65)))
            index += 2
        }
        guard bytes.count == 16 else { return nil }
        var name = String(
            decoding: bytes[0..<15], as: UTF8.self)
        while name.hasSuffix(" ") {
            name = String(name.dropLast())
        }
        return name + "<"
            + hexByte(Int(bytes[15])) + ">"
    }
}
