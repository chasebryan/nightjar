import Foundation

// Betafisch — the packet dissector
// (B1 core; B2 deepens it in
// BetafischDeep.swift, and B3's house
// wire tap lives in BetafischTap.swift).
// A Wireshark-shaped reader for
// captures the operator brings to the
// house: classic libpcap and pcapng,
// Ethernet / BSD loopback / Linux cooked
// / raw IP frames, taken apart field by
// field — Ethernet, ARP, IPv4, IPv6,
// ICMP, ICMPv6, UDP, TCP and a full DNS
// read with compressed names. Read-only
// analysis of files: nothing here is
// transmitted, and iOS gives no app the
// wire itself, so betafisch reads what
// it is handed and says so plainly.

/// One branch of a frame's dissection:
/// a titled field or layer, the bytes it
/// stands on (for the hex highlight), and
/// its children.
struct BFNode: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var range: Range<Int>
    var children: [BFNode] = []

    init(_ title: String, _ detail: String,
         _ range: Range<Int>,
         children: [BFNode] = []) {
        self.title = title
        self.detail = detail
        self.range = range
        self.children = children
    }
}

/// One frame of a capture, dissected:
/// the wire facts, the one-line summary
/// the packet list shows, the dissection
/// tree, and the facts the display
/// filter reads.
struct BFFrame: Identifiable {
    let id = UUID()
    var number: Int
    var timestamp: Double
    var bytes: [UInt8]
    var origLen: Int
    var linktype: Int
    var proto: String
    var src: String
    var dst: String
    var info: String
    var tree: [BFNode]
    var protocols: Set<String> = []
    var ipSrc: String? = nil
    var ipDst: String? = nil
    var srcPort: Int? = nil
    var dstPort: Int? = nil
    var isTCP = false
    var isUDP = false
    /// The TCP stream facts — sequence
    /// number, the nine flag bits (NS in
    /// bit 8, then CWR down to FIN), and
    /// where the payload sits in the
    /// frame's bytes. Driftnet's stream
    /// reassembly is built from these.
    var tcpSeq: Int? = nil
    var tcpAck: Int? = nil
    var tcpFlags: Int = 0
    var tcpPayloadRange: Range<Int>? = nil
    /// Where a UDP payload sits in the
    /// frame's bytes — the follow-stream
    /// reader's raw material.
    var udpPayloadRange: Range<Int>? = nil
    /// Lowercased info line plus the
    /// payload rendered as text — what a
    /// `contains` filter searches.
    var searchText: String = ""
}

/// A whole capture file, read.
struct BFCapture {
    var name: String
    var format: String
    var linktype: Int
    var frames: [BFFrame] = []
}

enum Betafisch {

    // MARK: Byte reading (bounds-checked)

    static func u8(_ b: [UInt8], _ i: Int) -> Int? {
        guard i >= 0, i < b.count else { return nil }
        return Int(b[i])
    }

    static func u16be(_ b: [UInt8], _ i: Int) -> Int? {
        guard let hi = u8(b, i),
              let lo = u8(b, i + 1) else { return nil }
        return (hi << 8) | lo
    }

    static func u32be(_ b: [UInt8], _ i: Int) -> Int? {
        guard let a = u16be(b, i),
              let c = u16be(b, i + 2) else { return nil }
        return (a << 16) | c
    }

    static func u16(_ b: [UInt8], _ i: Int,
                    little: Bool) -> Int? {
        guard let x = u8(b, i),
              let y = u8(b, i + 1) else { return nil }
        if little { return (y << 8) | x }
        return (x << 8) | y
    }

    static func u32(_ b: [UInt8], _ i: Int,
                    little: Bool) -> Int? {
        guard let x = u16(b, i, little: little),
              let y = u16(b, i + 2,
                          little: little)
        else { return nil }
        if little { return (y << 16) | x }
        return (x << 16) | y
    }

    static func hexByte(_ v: Int) -> String {
        let digits = Array("0123456789abcdef")
        let hi = digits[(v >> 4) & 0xf]
        let lo = digits[v & 0xf]
        return String([hi, lo])
    }

    static func hexDumpWord(_ v: Int, _ width: Int)
        -> String {
        var value = v
        var out = ""
        for _ in 0..<width {
            out = String(
                Array("0123456789abcdef")[value & 0xf])
                + out
            value >>= 4
        }
        return out
    }

    // MARK: Address rendering

    static func macString(_ b: [UInt8],
                          _ at: Int) -> String {
        var parts: [String] = []
        for k in 0..<6 {
            parts.append(hexByte(u8(b, at + k) ?? 0))
        }
        return parts.joined(separator: ":")
    }

    static func ipv4String(_ b: [UInt8],
                           _ at: Int) -> String {
        var parts: [String] = []
        for k in 0..<4 {
            parts.append(String(u8(b, at + k) ?? 0))
        }
        return parts.joined(separator: ".")
    }

    static func ipv4String(bytes: ArraySlice<UInt8>)
        -> String {
        return bytes.map { String($0) }
            .joined(separator: ".")
    }

    /// RFC 5952 rendering: the longest run
    /// of two or more zero groups becomes
    /// "::"; hex groups carry no leading
    /// zeros.
    static func ipv6String(_ b: [UInt8],
                           _ at: Int) -> String {
        var groups: [Int] = []
        for k in 0..<8 {
            groups.append(u16be(b, at + k * 2) ?? 0)
        }
        var bestStart = -1
        var bestLen = 0
        var runStart = -1
        var runLen = 0
        for k in 0..<8 {
            if groups[k] == 0 {
                if runStart < 0 {
                    runStart = k
                    runLen = 1
                } else {
                    runLen += 1
                }
                if runLen > bestLen {
                    bestLen = runLen
                    bestStart = runStart
                }
            } else {
                runStart = -1
                runLen = 0
            }
        }
        if bestLen < 2 {
            bestStart = -1
        }
        var out = ""
        var needColon = false
        var k = 0
        while k < 8 {
            if k == bestStart {
                out += "::"
                needColon = false
                k += bestLen
                continue
            }
            if needColon { out += ":" }
            out += String(groups[k], radix: 16)
            needColon = true
            k += 1
        }
        return out
    }

    /// The frame's bytes as a reader sees
    /// them: printable ASCII stands, the
    /// rest falls to dots.
    static func textRender(_ b: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(b.count)
        for byte in b {
            if byte >= 0x20 && byte < 0x7f {
                out.append(
                    Character(UnicodeScalar(byte)))
            } else {
                out.append(".")
            }
        }
        return out
    }

    // MARK: Checksums (the sample builder's)

    static func foldedSum(_ b: [UInt8], from: Int,
                          count: Int) -> Int {
        var sum = 0
        var i = 0
        while i + 1 < count {
            sum += ((u8(b, from + i) ?? 0) << 8)
                | (u8(b, from + i + 1) ?? 0)
            i += 2
        }
        if i < count {
            sum += (u8(b, from + i) ?? 0) << 8
        }
        while sum > 0xffff {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        return sum
    }

    static func checksum(_ b: [UInt8], from: Int,
                         count: Int) -> Int {
        let folded = foldedSum(b, from: from,
                               count: count)
        return (~folded) & 0xffff
    }

    static func transportChecksum(
        src: [UInt8], dst: [UInt8], proto: Int,
        segment: [UInt8]) -> Int {
        var pseudo = src + dst
        pseudo.append(0)
        pseudo.append(UInt8(proto & 0xff))
        pseudo.append(UInt8((segment.count >> 8)
                            & 0xff))
        pseudo.append(UInt8(segment.count & 0xff))
        var sum = foldedSum(pseudo, from: 0,
                            count: pseudo.count)
        sum += foldedSum(segment, from: 0,
                         count: segment.count)
        while sum > 0xffff {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        let value = (~sum) & 0xffff
        return value == 0 ? 0xffff : value
    }
}

extension Betafisch {

    /// A read gone wrong, in plain words.
    struct LoadError: Error {
        var message: String
    }

    /// Read a capture file's bytes.
    /// Returns the dissected capture, or
    /// throws a LoadError saying plainly
    /// what the file is not.
    static func load(data: Data, name: String)
        throws -> BFCapture {
        let b = [UInt8](data)
        guard b.count >= 4 else {
            throw LoadError(message: L("that file is too small to be a capture — it does not even hold a header."))
        }
        // pcapng opens with the section
        // header block type, 0x0A0D0D0A,
        // which reads the same both ways.
        if b[0] == 0x0a && b[1] == 0x0d
            && b[2] == 0x0d && b[3] == 0x0a {
            return try loadPcapng(b, name: name)
        }
        return try loadClassic(b, name: name)
    }

    // MARK: Classic libpcap

    static func loadClassic(_ b: [UInt8],
                            name: String)
        throws -> BFCapture {
        guard b.count >= 24 else {
            throw LoadError(message: L("that file is not a libpcap capture — its header is cut short."))
        }
        let little: Bool
        let nanos: Bool
        if b[0] == 0xa1 && b[1] == 0xb2
            && b[2] == 0xc3 && b[3] == 0xd4 {
            little = false
            nanos = false
        } else if b[0] == 0xd4 && b[1] == 0xc3
            && b[2] == 0xb2 && b[3] == 0xa1 {
            little = true
            nanos = false
        } else if b[0] == 0xa1 && b[1] == 0xb2
            && b[2] == 0x3c && b[3] == 0x4d {
            little = false
            nanos = true
        } else if b[0] == 0x4d && b[1] == 0x3c
            && b[2] == 0xb2 && b[3] == 0xa1 {
            little = true
            nanos = true
        } else {
            throw LoadError(message: L("that file is not a capture betafisch knows — neither libpcap nor pcapng magic opens it."))
        }
        guard let major = u16(b, 4, little: little),
              let minor = u16(b, 6, little: little),
              let linktype = u32(b, 20, little: little)
        else {
            throw LoadError(message: L("that file is not a libpcap capture — its header is cut short."))
        }
        var capture = BFCapture(
            name: name,
            format: String(format: L("libpcap %lld.%lld"),
                           major, minor),
            linktype: linktype)
        let divisor: Double = nanos ? 1_000_000_000
            : 1_000_000
        var pos = 24
        var number = 0
        while pos + 16 <= b.count {
            guard let sec = u32(b, pos, little: little),
                  let frac = u32(b, pos + 4,
                                  little: little),
                  let incl = u32(b, pos + 8,
                                  little: little),
                  let orig = u32(b, pos + 12,
                                  little: little)
            else { break }
            pos += 16
            let take = min(incl, b.count - pos)
            guard take >= 0 else { break }
            let bytes = Array(b[pos..<(pos + take)])
            pos += incl
            number += 1
            let stamp = Double(sec)
                + Double(frac) / divisor
            capture.frames.append(
                dissect(bytes: bytes,
                        origLen: orig,
                        linktype: linktype,
                        number: number,
                        timestamp: stamp))
            if incl == 0 { break }
        }
        return capture
    }

    // MARK: pcapng

    private struct NGInterface {
        var linktype: Int
        var snaplen: Int
        var tickSeconds: Double
    }

    static func loadPcapng(_ b: [UInt8],
                           name: String)
        throws -> BFCapture {
        var capture = BFCapture(name: name,
                                format: "pcapng",
                                linktype: 1)
        var interfaces: [NGInterface] = []
        var little = false
        var sawSection = false
        var pos = 0
        var number = 0
        while pos + 12 <= b.count {
            guard let rawType = u32(b, pos,
                                    little: little),
                  let total = u32(b, pos + 4,
                                  little: little)
            else { break }
            var blockType = rawType
            if !sawSection {
                // The first block must be the
                // section header; its type
                // reads 0x0A0D0D0A either way,
                // and the byte-order magic
                // inside settles endianness.
                guard b[pos] == 0x0a && b[pos + 1] == 0x0d
                    && b[pos + 2] == 0x0d
                    && b[pos + 3] == 0x0a
                else {
                    throw LoadError(message: L("that pcapng file does not open with a section header."))
                }
                if b[pos + 8] == 0x1a && b[pos + 9] == 0x2b
                    && b[pos + 10] == 0x3c
                    && b[pos + 11] == 0x4d {
                    little = false
                } else if b[pos + 8] == 0x4d
                    && b[pos + 9] == 0x3c
                    && b[pos + 10] == 0x2b
                    && b[pos + 11] == 0x1a {
                    little = true
                } else {
                    throw LoadError(message: L("that pcapng file's byte-order magic is unreadable."))
                }
                sawSection = true
                blockType = 0x0a0d0d0a
            }
            guard total >= 12, pos + total <= b.count
            else { break }
            let bodyAt = pos + 8
            let bodyLen = total - 12
            switch blockType {
            case 0x0a0d0d0a:
                interfaces = []
            case 0x00000001:
                // Interface Description: the
                // link type, then the options;
                // if_tsresol (9) sets the
                // timestamp grain.
                if let link = u16(b, bodyAt,
                                  little: little),
                   let snap = u32(b, bodyAt + 4,
                                  little: little) {
                    var tick = 1e-6
                    var opt = bodyAt + 8
                    let optEnd = bodyAt + bodyLen
                    while opt + 4 <= optEnd {
                        guard let code = u16(
                                b, opt, little: little),
                              let len = u16(
                                b, opt + 2,
                                little: little)
                        else { break }
                        if code == 0 { break }
                        if code == 9, len >= 1,
                           let raw = u8(b, opt + 4) {
                            if raw & 0x80 != 0 {
                                tick = pow(2.0,
                                    -Double(raw & 0x7f))
                            } else {
                                tick = pow(10.0,
                                    -Double(raw & 0x7f))
                            }
                        }
                        let padded = (len + 3)
                            & ~3
                        opt += 4 + padded
                    }
                    interfaces.append(NGInterface(
                        linktype: link, snaplen: snap,
                        tickSeconds: tick))
                }
            case 0x00000006:
                // Enhanced Packet: interface,
                // the timestamp halves, the
                // captured and original
                // lengths, the bytes padded
                // to four.
                if let iface = u32(b, bodyAt,
                                   little: little),
                   let hi = u32(b, bodyAt + 4,
                                little: little),
                   let lo = u32(b, bodyAt + 8,
                                little: little),
                   let incl = u32(b, bodyAt + 12,
                                  little: little),
                   let orig = u32(b, bodyAt + 16,
                                  little: little),
                   iface < interfaces.count {
                    let spec = interfaces[iface]
                    let dataAt = bodyAt + 20
                    let take = min(incl,
                                   b.count - dataAt)
                    if take >= 0 {
                        let bytes = Array(
                            b[dataAt..<(dataAt + take)])
                        let ticks = (UInt64(hi) << 32)
                            | UInt64(lo)
                        number += 1
                        capture.frames.append(
                            dissect(
                                bytes: bytes,
                                origLen: orig,
                                linktype: spec.linktype,
                                number: number,
                                timestamp: Double(ticks)
                                    * spec.tickSeconds))
                    }
                }
            case 0x00000003:
                // Simple Packet: the original
                // length, then the bytes; the
                // captured length is the
                // smaller of the first
                // interface's snaplen and what
                // the block actually holds.
                if let orig = u32(b, bodyAt,
                                  little: little),
                   let first = interfaces.first {
                    let held = bodyLen - 4
                    let incl = min(orig,
                                   min(first.snaplen,
                                       held))
                    let dataAt = bodyAt + 4
                    if incl >= 0 {
                        let bytes = Array(
                            b[dataAt..<(dataAt + incl)])
                        number += 1
                        capture.frames.append(
                            dissect(
                                bytes: bytes,
                                origLen: orig,
                                linktype: first.linktype,
                                number: number,
                                timestamp: 0))
                    }
                }
            default:
                break
            }
            pos += total
            if let firstLink = interfaces.first?.linktype {
                capture.linktype = firstLink
            }
        }
        guard sawSection else {
            throw LoadError(message: L("that pcapng file does not open with a section header."))
        }
        return capture
    }
}

extension Betafisch {

    /// What a dissection learns as it
    /// walks down the layers — the packet
    /// list's line and the filter's facts.
    final class Accum {
        var proto = ""
        var src = ""
        var dst = ""
        var info = ""
        var protocols = Set<String>()
        var ipSrc: String? = nil
        var ipDst: String? = nil
        var srcPort: Int? = nil
        var dstPort: Int? = nil
        var isTCP = false
        var isUDP = false
        var tcpSeq: Int? = nil
        var tcpAck: Int? = nil
        var tcpFlags: Int = 0
        var tcpPayloadAt: Int? = nil
        var tcpPayloadLen: Int = 0
        var udpPayloadAt: Int? = nil
        var udpPayloadLen: Int = 0
        /// The frame's own addresses as
        /// bytes, for the checksum verdict
        /// the deep read computes.
        var ipVersion = 4
        var ipSrcRaw: [UInt8]? = nil
        var ipDstRaw: [UInt8]? = nil
    }

    static func dissect(bytes: [UInt8], origLen: Int,
                        linktype: Int, number: Int,
                        timestamp: Double) -> BFFrame {
        let acc = Accum()
        var roots: [BFNode] = []
        switch linktype {
        case 1:
            roots = [ethernet(bytes, at: 0, acc)]
        case 0:
            // BSD loopback: a four-byte
            // address family in the host's
            // own order, then the packet.
            var family = -1
            if bytes.count >= 4 {
                let be = (Int(bytes[0]) << 24)
                    | (Int(bytes[1]) << 16)
                    | (Int(bytes[2]) << 8) | Int(bytes[3])
                let le = (Int(bytes[3]) << 24)
                    | (Int(bytes[2]) << 16)
                    | (Int(bytes[1]) << 8) | Int(bytes[0])
                if [2, 24, 28, 30].contains(be) {
                    family = be
                } else if [2, 24, 28, 30].contains(le) {
                    family = le
                }
            }
            roots.append(BFNode(
                L("BSD loopback"),
                family >= 0
                    ? String(format: L("address family %lld"), family)
                    : L("the family word is unreadable"),
                0..<min(4, bytes.count)))
            if bytes.count > 4 {
                roots.append(rawIP(bytes, at: 4, acc))
            }
        case 113:
            // Linux cooked capture v1: a
            // sixteen-byte header, the
            // protocol riding at its tail
            // in Ethernet's numbering.
            if bytes.count >= 16,
               let proto = u16be(bytes, 14) {
                let packetType = u16be(bytes, 0) ?? 0
                var head = BFNode(
                    L("Linux cooked capture"),
                    String(format: L("packet type %lld"), packetType),
                    0..<16)
                head.children.append(BFNode(
                    L("Protocol"),
                    String(format: "0x%@ — %@",
                           hexDumpWord(proto, 4),
                           etherTypeName(proto)),
                    14..<16))
                roots.append(head)
                if let inner = payloadByEtherType(
                    bytes, at: 16, type: proto, acc) {
                    roots.append(inner)
                }
            } else {
                roots.append(truncatedNode(
                    L("Linux cooked capture"),
                    bytes: bytes, at: 0, needed: 16))
            }
        case 101, 12:
            roots = [rawIP(bytes, at: 0, acc)]
        default:
            acc.proto = String(
                format: L("linktype %lld"), linktype)
            roots = [BFNode(
                L("a frame betafisch cannot open"),
                String(format: L("linktype %lld — betafisch reads Ethernet, BSD loopback, Linux cooked and raw IP"), linktype),
                0..<bytes.count)]
        }
        if acc.proto.isEmpty {
            acc.proto = L("unknown")
        }
        var frame = BFFrame(
            number: number, timestamp: timestamp,
            bytes: bytes, origLen: origLen,
            linktype: linktype, proto: acc.proto,
            src: acc.src, dst: acc.dst,
            info: acc.info, tree: roots)
        frame.protocols = acc.protocols
        frame.ipSrc = acc.ipSrc
        frame.ipDst = acc.ipDst
        frame.srcPort = acc.srcPort
        frame.dstPort = acc.dstPort
        frame.isTCP = acc.isTCP
        frame.isUDP = acc.isUDP
        frame.tcpSeq = acc.tcpSeq
        frame.tcpAck = acc.tcpAck
        frame.tcpFlags = acc.tcpFlags
        if let payloadAt = acc.tcpPayloadAt {
            let end = min(bytes.count,
                          payloadAt + acc.tcpPayloadLen)
            frame.tcpPayloadRange =
                payloadAt..<max(payloadAt, end)
        }
        if let payloadAt = acc.udpPayloadAt {
            let end = min(bytes.count,
                          payloadAt + acc.udpPayloadLen)
            frame.udpPayloadRange =
                payloadAt..<max(payloadAt, end)
        }
        frame.searchText = (acc.info + "\n"
            + textRender(bytes)).lowercased()
        return frame
    }

    static func truncatedNode(_ title: String,
                              bytes: [UInt8], at: Int,
                              needed: Int) -> BFNode {
        return BFNode(
            title,
            String(format: L("truncated — %lld of %lld header bytes are here"),
                   max(0, bytes.count - at), needed),
            at..<bytes.count)
    }

    static func etherTypeName(_ type: Int) -> String {
        switch type {
        case 0x0800: return "IPv4"
        case 0x86dd: return "IPv6"
        case 0x0806: return "ARP"
        case 0x8100: return "802.1Q VLAN"
        case 0x88a8: return "802.1ad VLAN"
        case 0x8035: return "RARP"
        case 0x8847: return "MPLS"
        case 0x8863, 0x8864: return "PPPoE"
        case 0x88cc: return "LLDP"
        default:
            return L("unassigned")
        }
    }

    /// The layer an ethertype names,
    /// dissected; nil when there is
    /// nothing left to dissect.
    static func payloadByEtherType(
        _ b: [UInt8], at: Int, type: Int,
        _ acc: Accum) -> BFNode? {
        guard at < b.count else { return nil }
        switch type {
        case 0x0800:
            return ipv4(b, at: at, acc)
        case 0x86dd:
            return ipv6(b, at: at, acc)
        case 0x0806:
            return arp(b, at: at, acc)
        default:
            if type <= 1500 {
                return BFNode(
                    L("802.3 payload"),
                    String(format: L("a length, not a type: %lld bytes follow, and betafisch does not read further"), type),
                    at..<b.count)
            }
            return BFNode(
                L("payload"),
                String(format: L("ethertype 0x%@ — betafisch does not dissect this one"), hexDumpWord(type, 4)),
                at..<b.count)
        }
    }

    static func rawIP(_ b: [UInt8], at: Int,
                      _ acc: Accum) -> BFNode {
        guard at < b.count else {
            return BFNode(L("raw IP"),
                          L("nothing follows the header"),
                          at..<b.count)
        }
        let version = (b[at] >> 4) & 0x0f
        if version == 6 {
            return ipv6(b, at: at, acc)
        }
        return ipv4(b, at: at, acc)
    }

    // MARK: Ethernet II

    static func ethernet(_ b: [UInt8], at: Int,
                         _ acc: Accum) -> BFNode {
        guard b.count - at >= 14 else {
            return truncatedNode(L("Ethernet II"),
                                 bytes: b, at: at,
                                 needed: 14)
        }
        acc.protocols.insert("eth")
        let dst = macString(b, at)
        let src = macString(b, at + 6)
        acc.src = src
        acc.dst = dst
        var node = BFNode(
            L("Ethernet II"),
            String(format: L("%@ → %@"), src, dst),
            at..<(at + 14))
        node.children.append(BFNode(
            L("Destination"), dst, at..<(at + 6)))
        node.children.append(BFNode(
            L("Source"), src, (at + 6)..<(at + 12)))
        var type = u16be(b, at + 12) ?? 0
        var cursor = at + 14
        node.children.append(BFNode(
            L("Type"),
            String(format: "0x%@ — %@",
                   hexDumpWord(type, 4),
                   etherTypeName(type)),
            (at + 12)..<(at + 14)))
        // VLAN tags stack: each is four
        // bytes — two of control, then the
        // next type word.
        var tags = 0
        while (type == 0x8100 || type == 0x88a8)
                && tags < 3
                && b.count - cursor >= 4 {
            let tci = u16be(b, cursor) ?? 0
            let inner = u16be(b, cursor + 2) ?? 0
            var vlan = BFNode(
                L("802.1Q virtual LAN"),
                String(format: L("id %lld"), tci & 0x0fff),
                cursor..<(cursor + 4))
            vlan.children.append(BFNode(
                L("Priority"),
                String(format: "%lld", (tci >> 13) & 0x7),
                cursor..<(cursor + 2)))
            vlan.children.append(BFNode(
                L("Drop eligible"),
                (tci >> 12) & 0x1 == 1 ? L("yes") : L("no"),
                cursor..<(cursor + 2)))
            vlan.children.append(BFNode(
                L("ID"),
                String(format: "%lld", tci & 0x0fff),
                cursor..<(cursor + 2)))
            vlan.children.append(BFNode(
                L("Type"),
                String(format: "0x%@ — %@",
                       hexDumpWord(inner, 4),
                       etherTypeName(inner)),
                (cursor + 2)..<(cursor + 4)))
            node.children.append(vlan)
            cursor += 4
            type = inner
            tags += 1
        }
        node.range = at..<cursor
        if let inner = payloadByEtherType(
            b, at: cursor, type: type, acc) {
            node.children.append(inner)
        }
        if acc.proto.isEmpty {
            acc.proto = etherTypeName(type)
        }
        return node
    }

    // MARK: ARP

    static func arp(_ b: [UInt8], at: Int,
                    _ acc: Accum) -> BFNode {
        guard b.count - at >= 8 else {
            return truncatedNode(L("Address Resolution Protocol"),
                                 bytes: b, at: at,
                                 needed: 8)
        }
        acc.protocols.insert("arp")
        acc.proto = "ARP"
        let htype = u16be(b, at) ?? 0
        let ptype = u16be(b, at + 2) ?? 0
        let hlen = u8(b, at + 4) ?? 0
        let plen = u8(b, at + 5) ?? 0
        let oper = u16be(b, at + 6) ?? 0
        var node = BFNode(
            L("Address Resolution Protocol"),
            oper == 1 ? L("request")
                : (oper == 2 ? L("reply")
                   : String(format: L("opcode %lld"), oper)),
            at..<b.count)
        node.children.append(BFNode(
            L("Hardware type"),
            String(format: "%lld%@", htype,
                   htype == 1 ? " — Ethernet" : ""),
            at..<(at + 2)))
        node.children.append(BFNode(
            L("Protocol type"),
            String(format: "0x%@ — %@",
                   hexDumpWord(ptype, 4),
                   etherTypeName(ptype)),
            (at + 2)..<(at + 4)))
        node.children.append(BFNode(
            L("Hardware size"),
            String(format: "%lld", hlen),
            (at + 4)..<(at + 5)))
        node.children.append(BFNode(
            L("Protocol size"),
            String(format: "%lld", plen),
            (at + 5)..<(at + 6)))
        node.children.append(BFNode(
            L("Opcode"),
            String(format: "%lld — %@", oper,
                   oper == 1 ? L("request")
                    : (oper == 2 ? L("reply")
                       : L("unassigned"))),
            (at + 6)..<(at + 8)))
        let body = at + 8
        let whole = body + 2 * hlen + 2 * plen
        if hlen == 6 && plen == 4 && ptype == 0x0800
            && b.count >= whole {
            let sha = macString(b, body)
            let spa = ipv4String(b, body + 6)
            let tha = macString(b, body + 10)
            let tpa = ipv4String(b, body + 16)
            node.children.append(BFNode(
                L("Sender hardware address"), sha,
                body..<(body + 6)))
            node.children.append(BFNode(
                L("Sender protocol address"), spa,
                (body + 6)..<(body + 10)))
            node.children.append(BFNode(
                L("Target hardware address"), tha,
                (body + 10)..<(body + 16)))
            node.children.append(BFNode(
                L("Target protocol address"), tpa,
                (body + 16)..<(body + 20)))
            node.range = at..<whole
            acc.src = spa
            acc.dst = tpa
            if spa == tpa {
                acc.info = String(
                    format: L("gratuitous ARP — %@ announces itself"), spa)
            } else if oper == 1 {
                acc.info = String(
                    format: L("who has %@? tell %@"), tpa, spa)
            } else if oper == 2 {
                acc.info = String(
                    format: L("%@ is at %@"), spa, sha)
            } else {
                acc.info = String(
                    format: L("opcode %lld — %@ to %@"),
                    oper, spa, tpa)
            }
        } else {
            node.children.append(BFNode(
                L("Addresses"),
                String(format: L("%lld bytes in a shape betafisch does not map"),
                       max(0, b.count - body)),
                body..<b.count))
            node.range = at..<b.count
        }
        return node
    }

    // MARK: IPv4

    static func ipProtocolName(_ proto: Int) -> String {
        switch proto {
        case 1: return "ICMP"
        case 2: return "IGMP"
        case 6: return "TCP"
        case 17: return "UDP"
        case 41: return "IPv6"
        case 47: return "GRE"
        case 50: return "ESP"
        case 51: return "AH"
        case 58: return "ICMPv6"
        case 89: return "OSPF"
        case 132: return "SCTP"
        default:
            return String(format: L("protocol %lld"), proto)
        }
    }

    static func ipv4(_ b: [UInt8], at: Int,
                     _ acc: Accum) -> BFNode {
        guard b.count - at >= 20 else {
            return truncatedNode(L("Internet Protocol version 4"),
                                 bytes: b, at: at,
                                 needed: 20)
        }
        acc.protocols.insert("ip")
        acc.proto = "IPv4"
        let first = u8(b, at) ?? 0
        let ihl = (first & 0x0f) * 4
        let headerLen = max(20, ihl)
        let totalLen = u16be(b, at + 2) ?? 0
        let ident = u16be(b, at + 4) ?? 0
        let flagsFrag = u16be(b, at + 6) ?? 0
        let ttl = u8(b, at + 8) ?? 0
        let proto = u8(b, at + 9) ?? 0
        let csum = u16be(b, at + 10) ?? 0
        let src = ipv4String(b, at + 12)
        let dst = ipv4String(b, at + 16)
        acc.ipSrc = src
        acc.ipDst = dst
        acc.src = src
        acc.dst = dst
        acc.ipVersion = 4
        acc.ipSrcRaw = Array(b[(at + 12)..<(at + 16)])
        acc.ipDstRaw = Array(b[(at + 16)..<(at + 20)])
        let end = totalLen >= headerLen
            ? min(b.count, at + totalLen) : b.count
        var node = BFNode(
            L("Internet Protocol version 4"),
            String(format: L("%@ → %@"), src, dst),
            at..<min(b.count, at + headerLen))
        node.children.append(BFNode(
            L("Version"),
            String(format: "%lld", (first >> 4) & 0x0f),
            at..<(at + 1)))
        node.children.append(BFNode(
            L("Header length"),
            String(format: L("%lld bytes"), headerLen),
            at..<(at + 1)))
        let dscp = u8(b, at + 1) ?? 0
        node.children.append(BFNode(
            L("Differentiated services"),
            String(format: L("DSCP %lld, ECN %lld"),
                   (dscp >> 2) & 0x3f, dscp & 0x3),
            (at + 1)..<(at + 2)))
        node.children.append(BFNode(
            L("Total length"),
            String(format: "%lld", totalLen),
            (at + 2)..<(at + 4)))
        node.children.append(BFNode(
            L("Identification"),
            String(format: "0x%@ (%lld)",
                   hexDumpWord(ident, 4), ident),
            (at + 4)..<(at + 6)))
        let reserved = (flagsFrag >> 15) & 0x1
        let df = (flagsFrag >> 14) & 0x1
        let mf = (flagsFrag >> 13) & 0x1
        var flagWords: [String] = []
        if df == 1 { flagWords.append(L("don't fragment")) }
        if mf == 1 { flagWords.append(L("more fragments")) }
        if flagWords.isEmpty {
            flagWords.append(L("none set"))
        }
        var flagsNode = BFNode(
            L("Flags"),
            flagWords.joined(separator: ", "),
            (at + 6)..<(at + 7))
        flagsNode.children.append(BFNode(
            L("Reserved"),
            reserved == 1 ? L("set") : L("not set"),
            (at + 6)..<(at + 7)))
        flagsNode.children.append(BFNode(
            L("Don't fragment"),
            df == 1 ? L("set") : L("not set"),
            (at + 6)..<(at + 7)))
        flagsNode.children.append(BFNode(
            L("More fragments"),
            mf == 1 ? L("set") : L("not set"),
            (at + 6)..<(at + 7)))
        node.children.append(flagsNode)
        node.children.append(BFNode(
            L("Fragment offset"),
            String(format: "%lld", flagsFrag & 0x1fff),
            (at + 6)..<(at + 8)))
        node.children.append(BFNode(
            L("Time to live"),
            String(format: "%lld", ttl),
            (at + 8)..<(at + 9)))
        node.children.append(BFNode(
            L("Protocol"),
            String(format: "%lld — %@", proto,
                   ipProtocolName(proto)),
            (at + 9)..<(at + 10)))
        node.children.append(BFNode(
            L("Header checksum"),
            String(format: "0x%@%@",
                   hexDumpWord(csum, 4),
                   foldedSum(b, from: at,
                             count: headerLen)
                       == 0xffff
                       ? " — " + L("correct")
                       : " — " + L("does not verify — as captured")),
            (at + 10)..<(at + 12)))
        node.children.append(BFNode(
            L("Source"), src, (at + 12)..<(at + 16)))
        node.children.append(BFNode(
            L("Destination"), dst, (at + 16)..<(at + 20)))
        if ihl > 20 {
            node.children.append(BFNode(
                L("Options"),
                String(format: L("%lld bytes of options ride in the header"),
                       ihl - 20),
                (at + 20)..<min(b.count, at + ihl)))
        }
        let payloadAt = at + headerLen
        if payloadAt < end {
            if let inner = ipPayload(b, at: payloadAt,
                                     end: end,
                                     proto: proto, acc) {
                node.children.append(inner)
            }
        }
        node.range = at..<end
        return node
    }

    static func ipPayload(_ b: [UInt8], at: Int,
                          end: Int, proto: Int,
                          _ acc: Accum) -> BFNode? {
        switch proto {
        case 1:
            return icmp(b, at: at, end: end, acc)
        case 6:
            return tcp(b, at: at, end: end, acc)
        case 17:
            return udp(b, at: at, end: end, acc)
        case 58:
            return icmpv6(b, at: at, end: end, acc)
        default:
            return BFNode(
                L("payload"),
                String(format: L("%@ — betafisch does not dissect this protocol"),
                       ipProtocolName(proto)),
                at..<end)
        }
    }

    // MARK: IPv6

    static func ipv6(_ b: [UInt8], at: Int,
                     _ acc: Accum) -> BFNode {
        guard b.count - at >= 40 else {
            return truncatedNode(L("Internet Protocol version 6"),
                                 bytes: b, at: at,
                                 needed: 40)
        }
        acc.protocols.insert("ipv6")
        acc.proto = "IPv6"
        let word = u32be(b, at) ?? 0
        let payloadLen = u16be(b, at + 4) ?? 0
        var next = u8(b, at + 6) ?? 0
        let hops = u8(b, at + 7) ?? 0
        let src = ipv6String(b, at + 8)
        let dst = ipv6String(b, at + 24)
        acc.ipSrc = src
        acc.ipDst = dst
        acc.src = src
        acc.dst = dst
        acc.ipVersion = 6
        acc.ipSrcRaw = Array(b[(at + 8)..<(at + 24)])
        acc.ipDstRaw = Array(b[(at + 24)..<(at + 40)])
        let end = payloadLen > 0
            ? min(b.count, at + 40 + payloadLen) : b.count
        var node = BFNode(
            L("Internet Protocol version 6"),
            String(format: L("%@ → %@"), src, dst),
            at..<min(b.count, at + 40))
        node.children.append(BFNode(
            L("Version"),
            String(format: "%lld", (word >> 28) & 0x0f),
            at..<(at + 1)))
        node.children.append(BFNode(
            L("Traffic class"),
            String(format: "0x%@",
                   hexDumpWord((word >> 20) & 0xff, 2)),
            at..<(at + 2)))
        node.children.append(BFNode(
            L("Flow label"),
            String(format: "0x%@",
                   hexDumpWord(word & 0xfffff, 5)),
            (at + 2)..<(at + 4)))
        node.children.append(BFNode(
            L("Payload length"),
            String(format: "%lld", payloadLen),
            (at + 4)..<(at + 6)))
        node.children.append(BFNode(
            L("Next header"),
            String(format: "%lld — %@", next,
                   ipProtocolName(next)),
            (at + 6)..<(at + 7)))
        node.children.append(BFNode(
            L("Hop limit"),
            String(format: "%lld", hops),
            (at + 7)..<(at + 8)))
        node.children.append(BFNode(
            L("Source"), src, (at + 8)..<(at + 24)))
        node.children.append(BFNode(
            L("Destination"), dst, (at + 24)..<(at + 40)))
        // Walk the extension chain: each
        // header names the next, and the
        // walk stops at eight or at a
        // header that seals the rest.
        var cursor = at + 40
        var hopsWalked = 0
        var walking = true
        while walking && hopsWalked < 8 {
            switch next {
            case 0, 43, 60:
                guard cursor + 2 <= end,
                      let extLen = u8(b, cursor + 1)
                else {
                    walking = false
                    continue
                }
                let bytes = (extLen + 1) * 8
                let names: [Int: String] = [
                    0: L("Hop-by-hop options"),
                    43: L("Routing"),
                    60: L("Destination options"),
                ]
                var ext = BFNode(
                    names[next] ?? L("extension header"),
                    String(format: L("next is %@"),
                           ipProtocolName(u8(b, cursor) ?? 0)),
                    cursor..<min(end, cursor + bytes))
                ext.children.append(BFNode(
                    L("Length"),
                    String(format: L("%lld bytes"), bytes),
                    (cursor + 1)..<(cursor + 2)))
                node.children.append(ext)
                next = u8(b, cursor) ?? 59
                cursor += bytes
                hopsWalked += 1
            case 44:
                guard cursor + 8 <= end else {
                    walking = false
                    continue
                }
                let fragWord = u16be(b, cursor + 2) ?? 0
                var frag = BFNode(
                    L("Fragment"),
                    String(format: L("offset %lld, %@"),
                           (fragWord >> 3) & 0x1fff,
                           fragWord & 0x1 == 1
                               ? L("more fragments")
                               : L("the last fragment")),
                    cursor..<(cursor + 8))
                frag.children.append(BFNode(
                    L("Identification"),
                    String(format: "0x%@",
                           hexDumpWord(u32be(b, cursor + 4) ?? 0, 8)),
                    (cursor + 4)..<(cursor + 8)))
                node.children.append(frag)
                next = u8(b, cursor) ?? 59
                cursor += 8
                hopsWalked += 1
            case 51:
                guard cursor + 2 <= end,
                      let units = u8(b, cursor + 1)
                else {
                    walking = false
                    continue
                }
                let bytes = (units + 2) * 4
                node.children.append(BFNode(
                    L("Authentication header"),
                    String(format: L("%lld bytes"), bytes),
                    cursor..<min(end, cursor + bytes)))
                next = u8(b, cursor) ?? 59
                cursor += bytes
                hopsWalked += 1
            case 50:
                node.children.append(BFNode(
                    L("Encapsulating security payload"),
                    L("the rest of the packet is sealed"),
                    cursor..<end))
                walking = false
            case 59:
                node.children.append(BFNode(
                    L("No next header"),
                    L("the chain ends here"),
                    cursor..<cursor))
                walking = false
            default:
                walking = false
            }
        }
        if cursor < end {
            if let inner = ipPayload(b, at: cursor,
                                     end: end,
                                     proto: next, acc) {
                node.children.append(inner)
            }
        }
        node.range = at..<end
        return node
    }
}

extension Betafisch {

    // MARK: ICMP

    static func icmpTypeName(_ type: Int) -> String {
        switch type {
        case 0: return L("echo reply")
        case 3: return L("destination unreachable")
        case 4: return L("source quench")
        case 5: return L("redirect")
        case 8: return L("echo request")
        case 9: return L("router advertisement")
        case 10: return L("router solicitation")
        case 11: return L("time exceeded")
        case 12: return L("parameter problem")
        case 13: return L("timestamp request")
        case 14: return L("timestamp reply")
        default:
            return String(format: L("type %lld"), type)
        }
    }

    static func icmp(_ b: [UInt8], at: Int, end: Int,
                     _ acc: Accum) -> BFNode {
        guard end - at >= 4 else {
            return truncatedNode(L("Internet Control Message Protocol"),
                                 bytes: b, at: at,
                                 needed: 4)
        }
        if acc.proto == "IPv4" || acc.proto.isEmpty {
            acc.proto = "ICMP"
        }
        acc.protocols.insert("icmp")
        let type = u8(b, at) ?? 0
        let code = u8(b, at + 1) ?? 0
        let csum = u16be(b, at + 2) ?? 0
        var node = BFNode(
            L("Internet Control Message Protocol"),
            icmpTypeName(type),
            at..<end)
        node.children.append(BFNode(
            L("Type"),
            String(format: "%lld — %@", type,
                   icmpTypeName(type)),
            at..<(at + 1)))
        var codeDetail = String(format: "%lld", code)
        if type == 3 {
            let codeNames: [Int: String] = [
                0: L("network unreachable"),
                1: L("host unreachable"),
                2: L("protocol unreachable"),
                3: L("port unreachable"),
                4: L("fragmentation needed"),
                9: L("network administratively prohibited"),
                10: L("host administratively prohibited"),
                13: L("communication administratively filtered"),
            ]
            if let word = codeNames[code] {
                codeDetail = String(format: "%lld — %@",
                                    code, word)
            }
        } else if type == 11 {
            if code == 0 {
                codeDetail = String(format: "%lld — %@", code,
                                    L("time to live exceeded"))
            } else if code == 1 {
                codeDetail = String(format: "%lld — %@", code,
                                    L("fragment reassembly time exceeded"))
            }
        } else if type == 5 {
            if code == 1 {
                codeDetail = String(format: "%lld — %@", code,
                                    L("redirect for the host"))
            }
        }
        node.children.append(BFNode(
            L("Code"), codeDetail, (at + 1)..<(at + 2)))
        node.children.append(BFNode(
            L("Checksum"),
            String(format: "0x%@", hexDumpWord(csum, 4)),
            (at + 2)..<(at + 4)))
        if (type == 0 || type == 8) && end - at >= 8 {
            let ident = u16be(b, at + 4) ?? 0
            let seq = u16be(b, at + 6) ?? 0
            node.children.append(BFNode(
                L("Identifier"),
                String(format: "0x%@ (%lld)",
                       hexDumpWord(ident, 4), ident),
                (at + 4)..<(at + 6)))
            node.children.append(BFNode(
                L("Sequence"),
                String(format: "%lld", seq),
                (at + 6)..<(at + 8)))
            acc.info = String(
                format: L("echo (%@) id=0x%@, seq=%lld — %lld bytes of data"),
                type == 8 ? L("ping") : L("pong"),
                hexDumpWord(ident, 4), seq,
                max(0, end - at - 8))
            let payload = end - at - 8
            if payload > 0 {
                node.children.append(BFNode(
                    L("Data"),
                    String(format: L("%lld bytes"), payload),
                    (at + 8)..<end))
            }
        } else if type == 3 && code == 4 && end - at >= 8 {
            let mtu = u16be(b, at + 6) ?? 0
            node.children.append(BFNode(
                L("Next-hop MTU"),
                String(format: "%lld", mtu),
                (at + 6)..<(at + 8)))
            acc.info = String(
                format: L("destination unreachable — fragmentation needed, next-hop MTU %lld"), mtu)
            if end - at > 8,
               let quoted = quotedIPNode(
                   b, at: at + 8, end: end) {
                node.children.append(quoted)
            }
        } else {
            acc.info = String(
                format: L("%@ (type %lld, code %lld)"),
                icmpTypeName(type), type, code)
            if end - at > 8 {
                if let quoted = quotedIPNode(
                    b, at: at + 8, end: end) {
                    node.children.append(quoted)
                } else {
                    node.children.append(BFNode(
                        L("The packet that provoked it"),
                        String(format: L("%lld bytes quoted back"),
                               end - at - 8),
                        (at + 8)..<end))
                }
            }
        }
        return node
    }

    // MARK: ICMPv6

    static func icmpv6TypeName(_ type: Int) -> String {
        switch type {
        case 1: return L("destination unreachable")
        case 2: return L("packet too big")
        case 3: return L("time exceeded")
        case 4: return L("parameter problem")
        case 128: return L("echo request")
        case 129: return L("echo reply")
        case 133: return L("router solicitation")
        case 134: return L("router advertisement")
        case 135: return L("neighbor solicitation")
        case 136: return L("neighbor advertisement")
        case 137: return L("redirect")
        default:
            return String(format: L("type %lld"), type)
        }
    }

    static func icmpv6(_ b: [UInt8], at: Int, end: Int,
                       _ acc: Accum) -> BFNode {
        guard end - at >= 4 else {
            return truncatedNode(L("Internet Control Message Protocol version 6"),
                                 bytes: b, at: at,
                                 needed: 4)
        }
        acc.proto = "ICMPv6"
        acc.protocols.insert("icmpv6")
        let type = u8(b, at) ?? 0
        let code = u8(b, at + 1) ?? 0
        let csum = u16be(b, at + 2) ?? 0
        var node = BFNode(
            L("Internet Control Message Protocol version 6"),
            icmpv6TypeName(type),
            at..<end)
        node.children.append(BFNode(
            L("Type"),
            String(format: "%lld — %@", type,
                   icmpv6TypeName(type)),
            at..<(at + 1)))
        node.children.append(BFNode(
            L("Code"),
            String(format: "%lld", code),
            (at + 1)..<(at + 2)))
        node.children.append(BFNode(
            L("Checksum"),
            String(format: "0x%@", hexDumpWord(csum, 4)),
            (at + 2)..<(at + 4)))
        if (type == 128 || type == 129) && end - at >= 8 {
            let ident = u16be(b, at + 4) ?? 0
            let seq = u16be(b, at + 6) ?? 0
            node.children.append(BFNode(
                L("Identifier"),
                String(format: "0x%@ (%lld)",
                       hexDumpWord(ident, 4), ident),
                (at + 4)..<(at + 6)))
            node.children.append(BFNode(
                L("Sequence"),
                String(format: "%lld", seq),
                (at + 6)..<(at + 8)))
            acc.info = String(
                format: L("echo (%@) id=0x%@, seq=%lld"),
                type == 128 ? L("ping") : L("pong"),
                hexDumpWord(ident, 4), seq)
        } else if (type == 135 || type == 136)
                    && end - at >= 24 {
            let target = ipv6String(b, at + 8)
            node.children.append(BFNode(
                L("Target address"), target,
                (at + 8)..<(at + 24)))
            acc.info = String(
                format: L("%@ for %@"),
                icmpv6TypeName(type), target)
        } else if type == 2 && end - at >= 8 {
            let mtu = u32be(b, at + 4) ?? 0
            node.children.append(BFNode(
                L("MTU"),
                String(format: "%lld", mtu),
                (at + 4)..<(at + 8)))
            acc.info = String(
                format: L("packet too big — MTU %lld"), mtu)
            if end - at > 8,
               let quoted = quotedIPNode(
                   b, at: at + 8, end: end) {
                node.children.append(quoted)
            }
        } else {
            acc.info = String(
                format: L("%@ (type %lld, code %lld)"),
                icmpv6TypeName(type), type, code)
            if (type == 1 || type == 3 || type == 4)
                && end - at > 8,
               let quoted = quotedIPNode(
                   b, at: at + 8, end: end) {
                node.children.append(quoted)
            }
        }
        return node
    }

    // MARK: UDP

    static func udp(_ b: [UInt8], at: Int, end: Int,
                    _ acc: Accum) -> BFNode {
        guard end - at >= 8 else {
            return truncatedNode(L("User Datagram Protocol"),
                                 bytes: b, at: at,
                                 needed: 8)
        }
        acc.proto = "UDP"
        acc.protocols.insert("udp")
        acc.isUDP = true
        let sport = u16be(b, at) ?? 0
        let dport = u16be(b, at + 2) ?? 0
        let length = u16be(b, at + 4) ?? 0
        let csum = u16be(b, at + 6) ?? 0
        acc.srcPort = sport
        acc.dstPort = dport
        let dataEnd = length >= 8
            ? min(end, at + length) : end
        var node = BFNode(
            L("User Datagram Protocol"),
            String(format: L("%lld → %lld"), sport, dport),
            at..<dataEnd)
        node.children.append(BFNode(
            L("Source port"),
            String(format: "%lld", sport), at..<(at + 2)))
        node.children.append(BFNode(
            L("Destination port"),
            String(format: "%lld", dport),
            (at + 2)..<(at + 4)))
        node.children.append(BFNode(
            L("Length"),
            String(format: "%lld", length),
            (at + 4)..<(at + 6)))
        var csumSuffix = ""
        if csum == 0 {
            csumSuffix = " — "
                + L("unused, which IPv4 permits")
        } else if let verdict = transportVerdict(
            b, at: at, end: dataEnd, proto: 17, acc) {
            csumSuffix = " — " + verdict
        }
        node.children.append(BFNode(
            L("Checksum"),
            String(format: "0x%@%@",
                   hexDumpWord(csum, 4), csumSuffix),
            (at + 6)..<(at + 8)))
        let payloadAt = at + 8
        let payloadLen = max(0, dataEnd - payloadAt)
        acc.udpPayloadAt = payloadAt
        acc.udpPayloadLen = payloadLen
        acc.info = String(format: L("%lld → %lld Len=%lld"),
                          sport, dport, payloadLen)
        if payloadLen > 0 {
            if let deep = udpPayload(
                b, at: payloadAt, end: dataEnd,
                sport: sport, dport: dport, acc) {
                node.children.append(deep)
            } else {
                node.children.append(BFNode(
                    L("Data"),
                    String(format: L("%lld bytes"), payloadLen),
                    payloadAt..<dataEnd))
            }
        }
        return node
    }

    // MARK: TCP

    static func tcp(_ b: [UInt8], at: Int, end: Int,
                    _ acc: Accum) -> BFNode {
        guard end - at >= 20 else {
            return truncatedNode(L("Transmission Control Protocol"),
                                 bytes: b, at: at,
                                 needed: 20)
        }
        acc.proto = "TCP"
        acc.protocols.insert("tcp")
        acc.isTCP = true
        let sport = u16be(b, at) ?? 0
        let dport = u16be(b, at + 2) ?? 0
        let seq = u32be(b, at + 4) ?? 0
        let ack = u32be(b, at + 8) ?? 0
        let offsetByte = u8(b, at + 12) ?? 0
        let dataOffset = ((offsetByte >> 4) & 0x0f) * 4
        let flagByte = u8(b, at + 13) ?? 0
        let nsBit = offsetByte & 0x01
        let window = u16be(b, at + 14) ?? 0
        let csum = u16be(b, at + 16) ?? 0
        let urgent = u16be(b, at + 18) ?? 0
        acc.srcPort = sport
        acc.dstPort = dport
        acc.tcpSeq = seq
        acc.tcpAck = ack
        acc.tcpFlags = (nsBit << 8) | flagByte
        var flagWords: [String] = []
        if nsBit == 1 { flagWords.append("NS") }
        if flagByte & 0x80 != 0 { flagWords.append("CWR") }
        if flagByte & 0x40 != 0 { flagWords.append("ECE") }
        if flagByte & 0x20 != 0 { flagWords.append("URG") }
        if flagByte & 0x10 != 0 { flagWords.append("ACK") }
        if flagByte & 0x08 != 0 { flagWords.append("PSH") }
        if flagByte & 0x04 != 0 { flagWords.append("RST") }
        if flagByte & 0x02 != 0 { flagWords.append("SYN") }
        if flagByte & 0x01 != 0 { flagWords.append("FIN") }
        let flagText = flagWords.isEmpty
            ? L("none set") : flagWords.joined(separator: ", ")
        let headerLen = max(20, min(dataOffset, end - at))
        var node = BFNode(
            L("Transmission Control Protocol"),
            String(format: L("%lld → %lld [%@]"),
                   sport, dport, flagText),
            at..<end)
        node.children.append(BFNode(
            L("Source port"),
            String(format: "%lld", sport), at..<(at + 2)))
        node.children.append(BFNode(
            L("Destination port"),
            String(format: "%lld", dport),
            (at + 2)..<(at + 4)))
        node.children.append(BFNode(
            L("Sequence number"),
            String(format: "%lld", seq),
            (at + 4)..<(at + 8)))
        node.children.append(BFNode(
            L("Acknowledgment number"),
            String(format: "%lld", ack),
            (at + 8)..<(at + 12)))
        node.children.append(BFNode(
            L("Header length"),
            String(format: L("%lld bytes"), headerLen),
            (at + 12)..<(at + 13)))
        node.children.append(BFNode(
            L("Flags"), flagText, (at + 12)..<(at + 14)))
        node.children.append(BFNode(
            L("Window"),
            String(format: "%lld", window),
            (at + 14)..<(at + 16)))
        node.children.append(BFNode(
            L("Checksum"),
            String(format: "0x%@%@",
                   hexDumpWord(csum, 4),
                   transportVerdict(
                       b, at: at, end: end, proto: 6,
                       acc).map { " — " + $0 } ?? ""),
            (at + 16)..<(at + 18)))
        node.children.append(BFNode(
            L("Urgent pointer"),
            String(format: "%lld", urgent),
            (at + 18)..<(at + 20)))
        if headerLen > 20 {
            node.children.append(
                tcpOptions(b, from: at + 20,
                           to: at + headerLen))
        }
        let payloadAt = at + headerLen
        let payloadLen = max(0, end - payloadAt)
        acc.tcpPayloadAt = payloadAt
        acc.tcpPayloadLen = payloadLen
        acc.info = String(
            format: L("%lld → %lld [%@] Seq=%lld Ack=%lld Win=%lld Len=%lld"),
            sport, dport, flagText, seq, ack, window,
            payloadLen)
        if payloadLen > 0 {
            if let deep = tcpPayload(
                b, at: payloadAt, end: end,
                sport: sport, dport: dport, acc) {
                node.children.append(deep)
            } else {
                node.children.append(BFNode(
                    L("Data"),
                    String(format: L("%lld bytes"), payloadLen),
                    payloadAt..<end))
            }
        }
        return node
    }

    static func tcpOptions(_ b: [UInt8], from: Int,
                           to: Int) -> BFNode {
        var node = BFNode(
            L("Options"),
            String(format: L("%lld bytes"), to - from),
            from..<to)
        var cursor = from
        var steps = 0
        while cursor < to && steps < 40 {
            steps += 1
            let kind = u8(b, cursor) ?? 0
            if kind == 0 {
                node.children.append(BFNode(
                    L("End of option list"), "",
                    cursor..<(cursor + 1)))
                break
            }
            if kind == 1 {
                node.children.append(BFNode(
                    L("No operation"), "",
                    cursor..<(cursor + 1)))
                cursor += 1
                continue
            }
            guard cursor + 1 < to,
                  let len = u8(b, cursor + 1),
                  len >= 2, cursor + len <= to
            else {
                node.children.append(BFNode(
                    String(format: L("option kind %lld"), kind),
                    L("its length word runs past the header"),
                    cursor..<to))
                break
            }
            var title = String(
                format: L("option kind %lld"), kind)
            var detail = String(
                format: L("%lld bytes"), len)
            switch kind {
            case 2:
                title = L("Maximum segment size")
                if len == 4, let v = u16be(b, cursor + 2) {
                    detail = String(format: "%lld", v)
                }
            case 3:
                title = L("Window scale")
                if len == 3, let v = u8(b, cursor + 2) {
                    detail = String(
                        format: L("shift %lld — the window is multiplied by %lld"),
                        v, 1 << min(v, 30))
                }
            case 4:
                title = L("SACK permitted")
                detail = ""
            case 5:
                title = L("SACK")
                let blocks = max(0, (len - 2) / 8)
                detail = String(
                    format: L("%lld block(s) selectively acknowledged"),
                    blocks)
            case 8:
                title = L("Timestamps")
                if len == 10,
                   let tsval = u32be(b, cursor + 2),
                   let tsecr = u32be(b, cursor + 6) {
                    detail = String(
                        format: L("TSval %lld, TSecr %lld"),
                        tsval, tsecr)
                }
            default:
                break
            }
            node.children.append(BFNode(
                title, detail, cursor..<(cursor + len)))
            cursor += len
        }
        return node
    }

    /// HTTP, read off the payload: the
    /// first line, the headers named and
    /// valued, and the body as a byte
    /// count with its opening rendered —
    /// shown, never rendered or run.
    static func httpSniff(_ b: [UInt8], at: Int,
                          end: Int, _ acc: Accum)
        -> BFNode? {
        let heads = ["GET ", "POST ", "HEAD ", "PUT ",
                     "DELETE ", "OPTIONS ", "PATCH ",
                     "HTTP/"]
        let text = textRender(Array(b[at..<end]))
        guard heads.contains(where: { text.hasPrefix($0) })
        else { return nil }
        acc.protocols.insert("http")
        acc.proto = "HTTP"
        var node = BFNode(
            L("Hypertext Transfer Protocol"),
            "",
            at..<end)
        var lines: [(String, Range<Int>)] = []
        var start = at
        var cursor = at
        var bodyAt: Int? = nil
        while cursor < end && lines.count < 24 {
            if b[cursor] == 0x0a {
                var lineEnd = cursor
                if lineEnd > start
                    && b[lineEnd - 1] == 0x0d {
                    lineEnd -= 1
                }
                let line = textRender(
                    Array(b[start..<lineEnd]))
                lines.append((line, start..<(cursor + 1)))
                start = cursor + 1
                if line.isEmpty {
                    bodyAt = start
                    break
                }
            }
            cursor += 1
        }
        if lines.isEmpty {
            let whole = textRender(Array(b[at..<end]))
            lines.append((whole, at..<end))
        }
        node.detail = lines.first?.0 ?? ""
        for (index, pair) in lines.enumerated() {
            if index == 0 {
                node.children.append(BFNode(
                    L("First line"), pair.0, pair.1))
                continue
            }
            if pair.0.isEmpty { continue }
            if let colon = pair.0.firstIndex(
                of: ":") {
                let name = String(pair.0[..<colon])
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
        if let bodyAt, bodyAt < end {
            let bodyCount = end - bodyAt
            let glimpse = textRender(
                Array(b[bodyAt..<min(end,
                                      bodyAt + 96)]))
            node.children.append(BFNode(
                L("Body"),
                String(format: L("%lld bytes — opens: %@"),
                       bodyCount, glimpse),
                bodyAt..<end))
        }
        acc.info = lines.first?.0 ?? acc.info
        return node
    }
}

extension Betafisch {

    // MARK: DNS

    static func dnsTypeName(_ type: Int) -> String {
        switch type {
        case 1: return "A"
        case 2: return "NS"
        case 5: return "CNAME"
        case 6: return "SOA"
        case 12: return "PTR"
        case 15: return "MX"
        case 16: return "TXT"
        case 28: return "AAAA"
        case 33: return "SRV"
        case 41: return "OPT"
        case 43: return "DS"
        case 46: return "RRSIG"
        case 47: return "NSEC"
        case 48: return "DNSKEY"
        case 65: return "HTTPS"
        case 257: return "CAA"
        case 255: return "ANY"
        default:
            return String(format: L("type %lld"), type)
        }
    }

    static func dnsClassName(_ cls: Int) -> String {
        switch cls & 0x7fff {
        case 1: return "IN"
        case 3: return "CH"
        case 4: return "HS"
        default:
            return String(format: L("class %lld"),
                          cls & 0x7fff)
        }
    }

    /// Read a possibly-compressed name.
    /// Pointers are followed at most
    /// twenty times and never to a place
    /// already visited — a looping name
    /// fails instead of spinning.
    static func dnsName(_ b: [UInt8], _ start: Int,
                        msgStart: Int, limit: Int)
        -> (name: String, next: Int)? {
        var labels: [String] = []
        var cursor = start
        var next: Int? = nil
        var jumps = 0
        var visited = Set<Int>()
        var total = 0
        while true {
            guard cursor >= msgStart, cursor < limit,
                  let len = u8(b, cursor) else {
                return nil
            }
            if len == 0 {
                if next == nil { next = cursor + 1 }
                break
            }
            if len & 0xc0 == 0xc0 {
                guard let lo = u8(b, cursor + 1) else {
                    return nil
                }
                let target = msgStart
                    + (((len & 0x3f) << 8) | lo)
                if next == nil { next = cursor + 2 }
                jumps += 1
                guard jumps <= 20,
                      !visited.contains(target),
                      target >= msgStart,
                      target < limit else {
                    return nil
                }
                visited.insert(target)
                cursor = target
                continue
            }
            if len & 0xc0 != 0 {
                return nil
            }
            let labelAt = cursor + 1
            guard labelAt + len <= limit else {
                return nil
            }
            total += len + 1
            guard total <= 255 else { return nil }
            labels.append(String(
                decoding: b[labelAt..<(labelAt + len)],
                as: UTF8.self))
            cursor = labelAt + len
        }
        guard let after = next else { return nil }
        let name = labels.isEmpty ? "."
            : labels.joined(separator: ".")
        return (name, after)
    }

    static func dnsRcodeName(_ rcode: Int) -> String {
        switch rcode {
        case 0: return L("no error")
        case 1: return L("format error")
        case 2: return L("server failure")
        case 3: return L("NXDOMAIN — the name does not exist")
        case 4: return L("not implemented")
        case 5: return L("refused")
        default:
            return String(format: L("rcode %lld"), rcode)
        }
    }

    static func dns(_ b: [UInt8], at: Int, end: Int,
                    _ acc: Accum, spanFrom: Int,
                    flavor: String = "dns")
        -> BFNode {
        let flavorTitle: String
        switch flavor {
        case "mdns": flavorTitle = L("Multicast DNS")
        case "nbns":
            flavorTitle = L("NetBIOS Name Service")
        default: flavorTitle = L("Domain Name System")
        }
        guard end - at >= 12 else {
            return truncatedNode(flavorTitle,
                                 bytes: b, at: at,
                                 needed: 12)
        }
        acc.protocols.insert("dns")
        if flavor == "mdns" {
            acc.protocols.insert("mdns")
            acc.proto = "mDNS"
        } else if flavor == "nbns" {
            acc.protocols.insert("nbns")
            acc.proto = "NBNS"
        } else {
            acc.proto = "DNS"
        }
        let ident = u16be(b, at) ?? 0
        let flagsA = u8(b, at + 2) ?? 0
        let flagsB = u8(b, at + 3) ?? 0
        let isResponse = flagsA & 0x80 != 0
        let opcode = (flagsA >> 3) & 0x0f
        let rcode = flagsB & 0x0f
        let qd = u16be(b, at + 4) ?? 0
        let an = u16be(b, at + 6) ?? 0
        let ns = u16be(b, at + 8) ?? 0
        let ar = u16be(b, at + 10) ?? 0
        var node = BFNode(
            flavorTitle,
            isResponse ? L("response") : L("query"),
            spanFrom..<end)
        node.children.append(BFNode(
            L("Transaction ID"),
            String(format: "0x%@", hexDumpWord(ident, 4)),
            at..<(at + 2)))
        var flagsNode = BFNode(
            L("Flags"),
            String(format: "0x%@%@",
                   hexDumpWord(flagsA, 2),
                   hexDumpWord(flagsB, 2)),
            (at + 2)..<(at + 4))
        let flagRows: [(String, Bool, String)] = [
            (L("Response"), isResponse,
             isResponse ? L("an answer") : L("a question")),
            (L("Authoritative"), flagsA & 0x04 != 0,
             flagsA & 0x04 != 0 ? L("set") : L("not set")),
            (L("Truncated"), flagsA & 0x02 != 0,
             flagsA & 0x02 != 0 ? L("set") : L("not set")),
            (L("Recursion desired"), flagsA & 0x01 != 0,
             flagsA & 0x01 != 0 ? L("set") : L("not set")),
            (L("Recursion available"), flagsB & 0x80 != 0,
             flagsB & 0x80 != 0 ? L("set") : L("not set")),
        ]
        for row in flagRows {
            flagsNode.children.append(BFNode(
                row.0, row.2, (at + 2)..<(at + 4)))
        }
        flagsNode.children.append(BFNode(
            L("Opcode"),
            String(format: "%lld%@",
                   opcode,
                   opcode == 0
                       ? " — " + L("standard query") : ""),
            (at + 2)..<(at + 3)))
        flagsNode.children.append(BFNode(
            L("Reply code"),
            String(format: "%lld — %@", rcode,
                   dnsRcodeName(rcode)),
            (at + 3)..<(at + 4)))
        node.children.append(flagsNode)
        node.children.append(BFNode(
            L("Questions"),
            String(format: "%lld", qd),
            (at + 4)..<(at + 6)))
        node.children.append(BFNode(
            L("Answer RRs"),
            String(format: "%lld", an),
            (at + 6)..<(at + 8)))
        node.children.append(BFNode(
            L("Authority RRs"),
            String(format: "%lld", ns),
            (at + 8)..<(at + 10)))
        node.children.append(BFNode(
            L("Additional RRs"),
            String(format: "%lld", ar),
            (at + 10)..<(at + 12)))

        var cursor = at + 12
        var firstQuestion: (String, Int)? = nil
        if qd > 0 {
            var queries = BFNode(L("Queries"), "",
                                 cursor..<cursor)
            var qStart = cursor
            for _ in 0..<qd {
                guard let got = dnsName(b, cursor,
                                        msgStart: at,
                                        limit: end),
                      got.next + 4 <= end,
                      let qtype = u16be(b, got.next),
                      let qclass = u16be(b, got.next + 2)
                else {
                    queries.children.append(BFNode(
                        L("a question betafisch cannot read"),
                        L("the name or its tail runs past the message"),
                        cursor..<end))
                    cursor = end
                    break
                }
                if firstQuestion == nil {
                    firstQuestion = (got.name, qtype)
                }
                var shownName = got.name
                if flavor == "nbns" {
                    shownName = nbnsDisplayName(
                        got.name) ?? got.name
                }
                var classWord = dnsClassName(qclass)
                var classNote = ""
                if flavor == "mdns"
                    && qclass & 0x8000 != 0 {
                    classWord = dnsClassName(
                        qclass & 0x7fff)
                    classNote = " — "
                        + L("a unicast answer is requested (the QU bit)")
                }
                queries.children.append(BFNode(
                    shownName,
                    String(format: L("%@, class %@"),
                           dnsTypeName(qtype),
                           classWord) + classNote,
                    cursor..<(got.next + 4)))
                cursor = got.next + 4
            }
            queries.range = qStart..<cursor
            node.children.append(queries)
        }

        var firstAnswer = ""
        func recordSection(_ title: String,
                           _ count: Int) {
            guard count > 0, cursor < end else { return }
            var section = BFNode(title, "", cursor..<cursor)
            let sectionStart = cursor
            for _ in 0..<count {
                guard let rr = dnsRecord(b, at: cursor,
                                         end: end,
                                         msgStart: at,
                                         flavor: flavor)
                else {
                    section.children.append(BFNode(
                        L("a record betafisch cannot read"),
                        L("it runs past the message's end"),
                        cursor..<end))
                    cursor = end
                    break
                }
                section.children.append(rr.node)
                if title == L("Answers")
                    && section.children.count == 1 {
                    firstAnswer = rr.summary
                }
                cursor = rr.next
            }
            section.range = sectionStart..<cursor
            node.children.append(section)
        }
        recordSection(L("Answers"), an)
        recordSection(L("Authoritative nameservers"), ns)
        recordSection(L("Additional records"), ar)

        let verb = opcode == 0
            ? (isResponse ? L("standard query response")
                          : L("standard query"))
            : String(format: L("opcode %lld"), opcode)
        var info = String(format: "%@ 0x%@",
                          verb, hexDumpWord(ident, 4))
        if let q = firstQuestion {
            info += " " + dnsTypeName(q.1) + " " + q.0
        }
        if isResponse {
            if rcode != 0 {
                info += " — " + dnsRcodeName(rcode)
            } else if !firstAnswer.isEmpty {
                info += " " + firstAnswer
            }
        }
        if flavor != "dns" {
            info = acc.proto + " " + info
        }
        acc.info = info
        return node
    }

    /// One resource record; nil when it
    /// runs past the message.
    static func dnsRecord(_ b: [UInt8], at: Int,
                          end: Int, msgStart: Int,
                          flavor: String = "dns")
        -> (node: BFNode, next: Int, summary: String)? {
        guard let got = dnsName(b, at, msgStart: msgStart,
                                limit: end),
              got.next + 10 <= end,
              let type = u16be(b, got.next),
              let cls = u16be(b, got.next + 2),
              let ttl = u32be(b, got.next + 4),
              let rdlen = u16be(b, got.next + 8)
        else { return nil }
        let rdataAt = got.next + 10
        let rdataEnd = rdataAt + rdlen
        guard rdataEnd <= end else { return nil }
        var detail = ""
        var summary = ""
        switch type {
        case 1 where rdlen == 4:
            let addr = ipv4String(b, rdataAt)
            detail = addr
            summary = addr
        case 28 where rdlen == 16:
            let addr = ipv6String(b, rdataAt)
            detail = addr
            summary = addr
        case 2, 5, 12:
            if let target = dnsName(b, rdataAt,
                                    msgStart: msgStart,
                                    limit: end) {
                detail = target.name
                summary = target.name
            }
        case 15:
            if rdlen >= 3,
               let pref = u16be(b, rdataAt),
               let target = dnsName(b, rdataAt + 2,
                                    msgStart: msgStart,
                                    limit: end) {
                detail = String(format: L("preference %lld, %@"),
                                pref, target.name)
                summary = target.name
            }
        case 6:
            if let mname = dnsName(b, rdataAt,
                                   msgStart: msgStart,
                                   limit: end),
               let rname = dnsName(b, mname.next,
                                   msgStart: msgStart,
                                   limit: end),
               rname.next + 20 <= end {
                let serial = u32be(b, rname.next) ?? 0
                detail = String(
                    format: L("primary %@, mail %@, serial %lld"),
                    mname.name, rname.name, serial)
                summary = mname.name
            }
        case 16:
            var parts: [String] = []
            var walk = rdataAt
            while walk < rdataEnd,
                  let n = u8(b, walk),
                  walk + 1 + n <= rdataEnd {
                parts.append(String(
                    decoding: b[(walk + 1)..<(walk + 1 + n)],
                    as: UTF8.self))
                walk += 1 + n
            }
            detail = parts.joined(separator: " ")
            summary = detail
        case 33:
            if rdlen >= 7,
               let prio = u16be(b, rdataAt),
               let weight = u16be(b, rdataAt + 2),
               let port = u16be(b, rdataAt + 4),
               let target = dnsName(b, rdataAt + 6,
                                    msgStart: msgStart,
                                    limit: end) {
                detail = String(
                    format: L("priority %lld, weight %lld, port %lld, %@"),
                    prio, weight, port, target.name)
                summary = target.name
            }
        case 41:
            let version = (ttl >> 16) & 0xff
            let dnssecOK = ttl & 0x8000 != 0
            detail = String(
                format: L("EDNS — the requestor's UDP size is %lld"),
                cls)
            detail += String(
                format: L(", version %lld%@"),
                version,
                dnssecOK ? L(", DNSSEC answers accepted") : "")
        case 65:
            // HTTPS / SVCB: priority, the
            // target name, then key=value
            // parameters — the ALPN offer
            // is the claim that matters
            // most on a house wire.
            if rdlen >= 3,
               let priority = u16be(b, rdataAt),
               let target = dnsName(b, rdataAt + 2,
                                    msgStart: msgStart,
                                    limit: end) {
                let shown = target.name.isEmpty
                    ? "." : target.name
                if priority == 0 {
                    detail = String(
                        format: L("an alias for %@"),
                        shown)
                } else {
                    detail = String(
                        format: L("priority %lld, target %@"),
                        priority, shown)
                }
                summary = shown
                var walk = target.next
                var alpnList: [String] = []
                var steps = 0
                while walk + 4 <= rdataEnd
                        && steps < 16 {
                    steps += 1
                    guard let key = u16be(b, walk),
                          let vlen = u16be(
                            b, walk + 2),
                          walk + 4 + vlen <= rdataEnd
                    else { break }
                    if key == 1 {
                        var inner = walk + 4
                        let innerEnd = inner + vlen
                        while inner < innerEnd,
                              let n = u8(b, inner),
                              inner + 1 + n <= innerEnd {
                            alpnList.append(String(
                                decoding: b[(inner + 1)..<(inner + 1 + n)],
                                as: UTF8.self))
                            inner += 1 + n
                        }
                    }
                    walk += 4 + vlen
                }
                if !alpnList.isEmpty {
                    detail += String(
                        format: L(" — ALPN %@"),
                        alpnList.joined(
                            separator: ", "))
                }
            }
        case 257:
            // CAA: a flags byte, a tag,
            // and the value it carries.
            if rdlen >= 2,
               let flags = u8(b, rdataAt),
               let tagLen = u8(b, rdataAt + 1),
               rdataAt + 2 + tagLen <= rdataEnd {
                let tag = String(
                    decoding: b[(rdataAt + 2)..<(rdataAt + 2 + tagLen)],
                    as: UTF8.self)
                let value = String(
                    decoding: b[(rdataAt + 2 + tagLen)..<rdataEnd],
                    as: UTF8.self)
                detail = String(
                    format: L("flags %lld, %@ %@"),
                    flags, tag, value)
                summary = value
            }
        default:
            detail = String(format: L("%lld bytes"),
                            rdlen)
        }
        var shownName = got.name
        if flavor == "nbns" {
            shownName = nbnsDisplayName(got.name)
                ?? got.name
        }
        var classWord = dnsClassName(cls)
        if flavor == "mdns" && cls & 0x8000 != 0 {
            classWord = dnsClassName(cls & 0x7fff)
                + " " + L("(cache flush)")
        }
        var node = BFNode(
            shownName,
            String(format: L("%@ %@ — %@"),
                   dnsTypeName(type),
                   classWord, detail),
            at..<rdataEnd)
        node.children.append(BFNode(
            L("Time to live"),
            String(format: L("%lld seconds"), ttl),
            (got.next + 4)..<(got.next + 8)))
        if !detail.isEmpty {
            node.children.append(BFNode(
                L("Data"), detail, rdataAt..<rdataEnd))
        }
        return (node, rdataEnd, summary)
    }
}

extension Betafisch {

    // MARK: The display filter
    //
    // A small evaluator in Wireshark's
    // shape: protocol words (tcp, dns…),
    // field comparisons (ip.addr == …,
    // tcp.port == …, len > …), contains
    // "text", and / or / not and
    // parentheses. A filter that does
    // not parse says so and matches
    // nothing — it never crashes.

    indirect enum FilterExpr {
        case or(FilterExpr, FilterExpr)
        case and(FilterExpr, FilterExpr)
        case not(FilterExpr)
        case proto(String)
        case field(String, String, String)
        case contains(String)
    }

    enum FilterToken {
        case word(String)
        case string(String)
        case op(String)
        case lparen
        case rparen
    }

    struct FilterFailure: Error {
        var message: String
    }

    static let filterProtocols: Set<String> = [
        "eth", "arp", "ip", "ipv6", "icmp",
        "icmpv6", "udp", "tcp", "dns", "http",
        "dhcp", "mdns", "nbns", "ssdp", "ntp",
        "tftp", "tls", "http2", "smb",
    ]

    static let filterFields: Set<String> = [
        "ip.addr", "ip.src", "ip.dst",
        "tcp.port", "udp.port", "port", "len",
    ]

    static func compileFilter(_ text: String)
        -> (expr: FilterExpr?, error: String?) {
        let trimmed = text.trimmingCharacters(
            in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, nil) }
        do {
            let tokens = try tokenizeFilter(trimmed)
            var parser = FilterParser(tokens: tokens)
            let expr = try parser.parseAll()
            return (expr, nil)
        } catch let failure as FilterFailure {
            return (nil, failure.message)
        } catch {
            return (nil, L("the filter does not parse."))
        }
    }

    static func tokenizeFilter(_ text: String)
        throws -> [FilterToken] {
        var tokens: [FilterToken] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" {
                i += 1
                continue
            }
            if c == "(" {
                tokens.append(.lparen)
                i += 1
                continue
            }
            if c == ")" {
                tokens.append(.rparen)
                i += 1
                continue
            }
            if c == "\"" {
                var value = ""
                var j = i + 1
                var closed = false
                while j < chars.count {
                    if chars[j] == "\"" {
                        closed = true
                        break
                    }
                    value.append(chars[j])
                    j += 1
                }
                guard closed else {
                    throw FilterFailure(message: L("the filter's quote never closes."))
                }
                tokens.append(.string(value))
                i = j + 1
                continue
            }
            if c == "=" {
                if i + 1 < chars.count
                    && chars[i + 1] == "=" {
                    tokens.append(.op("=="))
                    i += 2
                    continue
                }
                throw FilterFailure(message: L("comparisons are written == — a single = names nothing."))
            }
            if c == ">" || c == "<" {
                tokens.append(.op(String(c)))
                i += 1
                continue
            }
            if c == "!" {
                if i + 1 < chars.count
                    && chars[i + 1] == "=" {
                    throw FilterFailure(message: L("this filter has no != — say it with not."))
                }
                tokens.append(.word("!"))
                i += 1
                continue
            }
            if c == "&" {
                if i + 1 < chars.count
                    && chars[i + 1] == "&" {
                    tokens.append(.word("and"))
                    i += 2
                    continue
                }
                throw FilterFailure(message: L("a single & names nothing — and is written 'and' or '&&'."))
            }
            if c == "|" {
                if i + 1 < chars.count
                    && chars[i + 1] == "|" {
                    tokens.append(.word("or"))
                    i += 2
                    continue
                }
                throw FilterFailure(message: L("a single | names nothing — or is written 'or' or '||'."))
            }
            var word = ""
            var j = i
            while j < chars.count {
                let w = chars[j]
                if w.isLetter || w.isNumber
                    || w == "." || w == "_"
                    || w == "-" || w == ":" {
                    word.append(w)
                    j += 1
                } else {
                    break
                }
            }
            guard !word.isEmpty else {
                throw FilterFailure(message: String(
                    format: L("the filter holds a character betafisch cannot read: %@"),
                    String(c)))
            }
            tokens.append(.word(word.lowercased()))
            i = j
        }
        return tokens
    }

    struct FilterParser {
        var tokens: [FilterToken]
        var at = 0

        mutating func parseAll() throws -> FilterExpr {
            let expr = try parseOr()
            guard at >= tokens.count else {
                throw FilterFailure(message: L("the filter has words left over at its end."))
            }
            return expr
        }

        private func peekWord() -> String? {
            guard at < tokens.count,
                  case .word(let w) = tokens[at]
            else { return nil }
            return w
        }

        mutating func parseOr() throws -> FilterExpr {
            var left = try parseAnd()
            while peekWord() == "or" {
                at += 1
                let right = try parseAnd()
                left = .or(left, right)
            }
            return left
        }

        mutating func parseAnd() throws -> FilterExpr {
            var left = try parseUnary()
            while peekWord() == "and" {
                at += 1
                let right = try parseUnary()
                left = .and(left, right)
            }
            return left
        }

        mutating func parseUnary() throws -> FilterExpr {
            if peekWord() == "not" || peekWord() == "!" {
                at += 1
                return .not(try parseUnary())
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> FilterExpr {
            guard at < tokens.count else {
                throw FilterFailure(message: L("the filter ends mid-thought."))
            }
            switch tokens[at] {
            case .lparen:
                at += 1
                let inner = try parseOr()
                guard at < tokens.count,
                      case .rparen = tokens[at] else {
                    throw FilterFailure(message: L("the filter's parenthesis never closes."))
                }
                at += 1
                return inner
            case .word(let word):
                if word == "contains" {
                    at += 1
                    guard at < tokens.count,
                          case .string(let text) = tokens[at]
                    else {
                        throw FilterFailure(message: L("contains wants quoted text — contains \"text\"."))
                    }
                    at += 1
                    return .contains(text)
                }
                if Betafisch.filterFields.contains(word) {
                    return try parseComparison(field: word)
                }
                if Betafisch.filterProtocols.contains(word) {
                    at += 1
                    if at < tokens.count,
                       case .op = tokens[at] {
                        throw FilterFailure(message: String(
                            format: L("' %@' names a protocol, not a field — it stands alone in a filter."),
                            word))
                    }
                    let normalized = word == "ipv4"
                        ? "ip" : word
                    return .proto(normalized)
                }
                throw FilterFailure(message: String(
                    format: L("the filter word '%@' names nothing betafisch knows."),
                    word))
            default:
                throw FilterFailure(message: L("the filter holds a word out of place."))
            }
        }

        mutating func parseComparison(
            field: String) throws -> FilterExpr {
            at += 1
            guard at < tokens.count,
                  case .op(let oper) = tokens[at]
            else {
                throw FilterFailure(message: String(
                    format: L("' %@' wants a comparison — %@ == value."),
                    field, field))
            }
            at += 1
            guard at < tokens.count,
                  case .word(let value) = tokens[at]
            else {
                throw FilterFailure(message: String(
                    format: L("' %@ %@ ' wants a value after it."),
                    field, oper))
            }
            at += 1
            if field == "len" {
                guard ["==", ">", "<"].contains(oper)
                else {
                    throw FilterFailure(message: L("len compares with ==, > or <."))
                }
                guard Int(value) != nil else {
                    throw FilterFailure(message: L("len compares against a number of bytes."))
                }
            } else if field.hasSuffix(".port")
                        || field == "port" {
                guard oper == "==" else {
                    throw FilterFailure(message: L("ports are matched with == — tcp.port == 443."))
                }
                guard Int(value) != nil else {
                    throw FilterFailure(message: L("a port is a number."))
                }
            } else {
                guard oper == "==" else {
                    throw FilterFailure(message: L("addresses are matched with ==."))
                }
            }
            return .field(field, oper, value)
        }
    }

    static func filterMatches(_ expr: FilterExpr,
                              _ frame: BFFrame) -> Bool {
        switch expr {
        case .or(let a, let b):
            return filterMatches(a, frame)
                || filterMatches(b, frame)
        case .and(let a, let b):
            return filterMatches(a, frame)
                && filterMatches(b, frame)
        case .not(let inner):
            return !filterMatches(inner, frame)
        case .proto(let name):
            return frame.protocols.contains(name)
        case .contains(let text):
            return frame.searchText.contains(
                text.lowercased())
        case .field(let field, let oper, let value):
            switch field {
            case "ip.addr":
                let want = value.lowercased()
                return frame.ipSrc?.lowercased() == want
                    || frame.ipDst?.lowercased() == want
            case "ip.src":
                return frame.ipSrc?.lowercased()
                    == value.lowercased()
            case "ip.dst":
                return frame.ipDst?.lowercased()
                    == value.lowercased()
            case "tcp.port":
                guard frame.isTCP,
                      let n = Int(value) else {
                    return false
                }
                return frame.srcPort == n
                    || frame.dstPort == n
            case "udp.port":
                guard frame.isUDP,
                      let n = Int(value) else {
                    return false
                }
                return frame.srcPort == n
                    || frame.dstPort == n
            case "port":
                guard frame.isTCP || frame.isUDP,
                      let n = Int(value) else {
                    return false
                }
                return frame.srcPort == n
                    || frame.dstPort == n
            case "len":
                guard let n = Int(value) else {
                    return false
                }
                if oper == ">" { return frame.origLen > n }
                if oper == "<" { return frame.origLen < n }
                return frame.origLen == n
            default:
                return false
            }
        }
    }

    // MARK: The sample capture
    //
    // Fifteen frames built byte by byte in
    // code — an ARP exchange, a DNS
    // question and its answer, a TCP
    // handshake opening, a ping, an HTTP
    // request, and a second connection
    // that fetches a small PNG picture —
    // so the room can be tried with no
    // file at all. The addresses are the
    // textbook ones: a house at
    // 192.168.1.x asking after
    // example.com.

    static func sampleCapture() -> BFCapture {
        let phoneMAC: [UInt8] = [0x02, 0x11, 0x22,
                                 0x33, 0x44, 0x55]
        let routerMAC: [UInt8] = [0x02, 0xaa, 0xbb,
                                  0xcc, 0xdd, 0x01]
        let zeroMAC: [UInt8] = [0, 0, 0, 0, 0, 0]
        let broadcast: [UInt8] = [0xff, 0xff, 0xff,
                                  0xff, 0xff, 0xff]
        let phoneIP: [UInt8] = [192, 168, 1, 20]
        let routerIP: [UInt8] = [192, 168, 1, 1]
        let serverIP: [UInt8] = [93, 184, 216, 34]

        var raws: [(bytes: [UInt8], at: Double)] = []

        let arpAsk = arpBytes(oper: 1, sha: phoneMAC,
                              spa: phoneIP,
                              tha: zeroMAC,
                              tpa: routerIP)
        raws.append((ethFrame(dst: broadcast,
                              src: phoneMAC,
                              type: 0x0806,
                              payload: arpAsk), 0.000))
        let arpAnswer = arpBytes(oper: 2,
                                 sha: routerMAC,
                                 spa: routerIP,
                                 tha: phoneMAC,
                                 tpa: phoneIP)
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0806,
                              payload: arpAnswer), 0.003))

        let query = dnsQueryBytes(id: 0x1a2b,
                                  name: "example.com")
        let queryPacket = ipv4Bytes(
            src: phoneIP, dst: routerIP, proto: 17,
            ident: 0x1001,
            payload: udpBytes(src: phoneIP,
                              dst: routerIP,
                              sport: 53535, dport: 53,
                              payload: query))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: queryPacket), 0.120))

        let answer = dnsResponseBytes(
            id: 0x1a2b, name: "example.com",
            addr: serverIP)
        let answerPacket = ipv4Bytes(
            src: routerIP, dst: phoneIP, proto: 17,
            ident: 0x2002,
            payload: udpBytes(src: routerIP,
                              dst: phoneIP,
                              sport: 53, dport: 53535,
                              payload: answer))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: answerPacket), 0.148))

        let synOptions: [UInt8] = [
            2, 4, 0x05, 0xb4, 4, 2,
            8, 10, 0, 0, 0, 1, 0, 0, 0, 0,
            1, 3, 3, 7,
        ]
        let syn = ipv4Bytes(
            src: phoneIP, dst: serverIP, proto: 6,
            ident: 0x1003,
            payload: tcpBytes(src: phoneIP,
                              dst: serverIP,
                              sport: 52311, dport: 443,
                              seq: 1000, ack: 0,
                              flags: 0x02, window: 65535,
                              options: synOptions,
                              payload: []))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: syn), 0.300))

        let synAckOptions: [UInt8] = [
            2, 4, 0x05, 0xb4, 4, 2,
            8, 10, 0, 0, 0, 1, 0, 0, 3, 232,
            3, 3, 7, 0,
        ]
        let synAck = ipv4Bytes(
            src: serverIP, dst: phoneIP, proto: 6,
            ident: 0x2004,
            payload: tcpBytes(src: serverIP,
                              dst: phoneIP,
                              sport: 443, dport: 52311,
                              seq: 5000, ack: 1001,
                              flags: 0x12, window: 65160,
                              options: synAckOptions,
                              payload: []))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: synAck), 0.342))

        var icmpEcho: [UInt8] = [8, 0, 0, 0,
                                 0x12, 0x34, 0, 1]
        icmpEcho += Array("betafisch".utf8)
        let icmpSum = checksum(icmpEcho, from: 0,
                               count: icmpEcho.count)
        icmpEcho[2] = UInt8((icmpSum >> 8) & 0xff)
        icmpEcho[3] = UInt8(icmpSum & 0xff)
        let ping = ipv4Bytes(src: phoneIP,
                             dst: routerIP, proto: 1,
                             ident: 0x1005,
                             payload: icmpEcho)
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: ping), 0.500))

        let httpText = "GET / HTTP/1.1\r\n"
            + "Host: example.com\r\n"
            + "User-Agent: betafisch sample\r\n"
            + "Accept: */*\r\n\r\n"
        let get = ipv4Bytes(
            src: phoneIP, dst: serverIP, proto: 6,
            ident: 0x1006,
            payload: tcpBytes(src: phoneIP,
                              dst: serverIP,
                              sport: 52311, dport: 80,
                              seq: 1001, ack: 5001,
                              flags: 0x18, window: 65535,
                              options: [],
                              payload: Array(httpText.utf8)))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: get), 0.900))

        // A second errand, told whole:
        // a fresh connection opens, asks
        // for /moon.png, and the server
        // sends the picture in two pieces
        // before it hangs up — the catch
        // driftnet's sample run lifts.
        let moonPort = 52312
        let moonSYN = ipv4Bytes(
            src: phoneIP, dst: serverIP, proto: 6,
            ident: 0x1007,
            payload: tcpBytes(src: phoneIP,
                              dst: serverIP,
                              sport: moonPort, dport: 80,
                              seq: 2000, ack: 0,
                              flags: 0x02, window: 65535,
                              options: synOptions,
                              payload: []))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: moonSYN), 1.000))
        let moonSYNACK = ipv4Bytes(
            src: serverIP, dst: phoneIP, proto: 6,
            ident: 0x2005,
            payload: tcpBytes(src: serverIP,
                              dst: phoneIP,
                              sport: 80, dport: moonPort,
                              seq: 8000, ack: 2001,
                              flags: 0x12, window: 65160,
                              options: synAckOptions,
                              payload: []))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: moonSYNACK), 1.038))
        let moonACK = ipv4Bytes(
            src: phoneIP, dst: serverIP, proto: 6,
            ident: 0x1008,
            payload: tcpBytes(src: phoneIP,
                              dst: serverIP,
                              sport: moonPort, dport: 80,
                              seq: 2001, ack: 8001,
                              flags: 0x10, window: 65535,
                              options: [],
                              payload: []))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: moonACK), 1.039))
        let moonAskText = "GET /moon.png HTTP/1.1\r\n"
            + "Host: example.com\r\n"
            + "Accept: image/png\r\n\r\n"
        let moonAsk = Array(moonAskText.utf8)
        let moonGET = ipv4Bytes(
            src: phoneIP, dst: serverIP, proto: 6,
            ident: 0x1009,
            payload: tcpBytes(src: phoneIP,
                              dst: serverIP,
                              sport: moonPort, dport: 80,
                              seq: 2001, ack: 8001,
                              flags: 0x18, window: 65535,
                              options: [],
                              payload: moonAsk))
        raws.append((ethFrame(dst: routerMAC,
                              src: phoneMAC,
                              type: 0x0800,
                              payload: moonGET), 1.052))
        let moon = moonPNGBytes()
        let moonHead = "HTTP/1.1 200 OK\r\n"
            + "Content-Type: image/png\r\n"
            + "Content-Length: \(moon.count)\r\n"
            + "Connection: close\r\n\r\n"
        var moonAnswer = Array(moonHead.utf8)
        moonAnswer += moon
        let moonSplit = moonAnswer.count / 2
        let moonPart1 = Array(moonAnswer[..<moonSplit])
        let moonPart2 = Array(moonAnswer[moonSplit...])
        let moonAck = 2001 + moonAsk.count
        let moonReply1 = ipv4Bytes(
            src: serverIP, dst: phoneIP, proto: 6,
            ident: 0x2006,
            payload: tcpBytes(src: serverIP,
                              dst: phoneIP,
                              sport: 80, dport: moonPort,
                              seq: 8001, ack: moonAck,
                              flags: 0x18, window: 65160,
                              options: [],
                              payload: moonPart1))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: moonReply1), 1.118))
        let moonReply2 = ipv4Bytes(
            src: serverIP, dst: phoneIP, proto: 6,
            ident: 0x2007,
            payload: tcpBytes(src: serverIP,
                              dst: phoneIP,
                              sport: 80, dport: moonPort,
                              seq: 8001 + moonSplit,
                              ack: moonAck,
                              flags: 0x18, window: 65160,
                              options: [],
                              payload: moonPart2))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: moonReply2), 1.143))
        let moonFIN = ipv4Bytes(
            src: serverIP, dst: phoneIP, proto: 6,
            ident: 0x2008,
            payload: tcpBytes(src: serverIP,
                              dst: phoneIP,
                              sport: 80, dport: moonPort,
                              seq: 8001 + moonAnswer.count,
                              ack: moonAck,
                              flags: 0x11, window: 65160,
                              options: [],
                              payload: []))
        raws.append((ethFrame(dst: phoneMAC,
                              src: routerMAC,
                              type: 0x0800,
                              payload: moonFIN), 1.158))

        let base = 1_760_000_000.0
        var capture = BFCapture(
            name: L("the sample capture"),
            format: L("built into the room"),
            linktype: 1)
        for (index, raw) in raws.enumerated() {
            capture.frames.append(
                dissect(bytes: raw.bytes,
                        origLen: raw.bytes.count,
                        linktype: 1,
                        number: index + 1,
                        timestamp: base + raw.at))
        }
        return capture
    }

    static func ethFrame(dst: [UInt8], src: [UInt8],
                         type: Int, payload: [UInt8])
        -> [UInt8] {
        var out = dst + src
        out.append(UInt8((type >> 8) & 0xff))
        out.append(UInt8(type & 0xff))
        out += payload
        return out
    }

    static func arpBytes(oper: Int, sha: [UInt8],
                         spa: [UInt8], tha: [UInt8],
                         tpa: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0, 1, 0x08, 0x00, 6, 4,
                            UInt8((oper >> 8) & 0xff),
                            UInt8(oper & 0xff)]
        out += sha
        out += spa
        out += tha
        out += tpa
        return out
    }

    static func ipv4Bytes(src: [UInt8], dst: [UInt8],
                          proto: Int, ident: Int,
                          payload: [UInt8]) -> [UInt8] {
        let total = 20 + payload.count
        var out: [UInt8] = [
            0x45, 0,
            UInt8((total >> 8) & 0xff),
            UInt8(total & 0xff),
            UInt8((ident >> 8) & 0xff),
            UInt8(ident & 0xff),
            0x40, 0, 64, UInt8(proto & 0xff), 0, 0,
        ]
        out += src
        out += dst
        let sum = checksum(out, from: 0, count: 20)
        out[10] = UInt8((sum >> 8) & 0xff)
        out[11] = UInt8(sum & 0xff)
        out += payload
        return out
    }

    static func udpBytes(src: [UInt8], dst: [UInt8],
                         sport: Int, dport: Int,
                         payload: [UInt8]) -> [UInt8] {
        let length = 8 + payload.count
        var out: [UInt8] = [
            UInt8((sport >> 8) & 0xff),
            UInt8(sport & 0xff),
            UInt8((dport >> 8) & 0xff),
            UInt8(dport & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff), 0, 0,
        ]
        out += payload
        let sum = transportChecksum(
            src: src, dst: dst, proto: 17, segment: out)
        out[6] = UInt8((sum >> 8) & 0xff)
        out[7] = UInt8(sum & 0xff)
        return out
    }

    static func tcpBytes(src: [UInt8], dst: [UInt8],
                         sport: Int, dport: Int,
                         seq: Int, ack: Int,
                         flags: Int, window: Int,
                         options: [UInt8],
                         payload: [UInt8]) -> [UInt8] {
        var opts = options
        while opts.count % 4 != 0 { opts.append(0) }
        let headerLen = 20 + opts.count
        var out: [UInt8] = [
            UInt8((sport >> 8) & 0xff),
            UInt8(sport & 0xff),
            UInt8((dport >> 8) & 0xff),
            UInt8(dport & 0xff),
            UInt8((seq >> 24) & 0xff),
            UInt8((seq >> 16) & 0xff),
            UInt8((seq >> 8) & 0xff),
            UInt8(seq & 0xff),
            UInt8((ack >> 24) & 0xff),
            UInt8((ack >> 16) & 0xff),
            UInt8((ack >> 8) & 0xff),
            UInt8(ack & 0xff),
            UInt8((headerLen / 4) << 4),
            UInt8(flags & 0xff),
            UInt8((window >> 8) & 0xff),
            UInt8(window & 0xff), 0, 0, 0, 0,
        ]
        out += opts
        out += payload
        let sum = transportChecksum(
            src: src, dst: dst, proto: 6, segment: out)
        out[16] = UInt8((sum >> 8) & 0xff)
        out[17] = UInt8(sum & 0xff)
        return out
    }

    static func dnsNameBytes(_ name: String) -> [UInt8] {
        var out: [UInt8] = []
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            out.append(UInt8(bytes.count & 0xff))
            out += bytes
        }
        out.append(0)
        return out
    }

    static func dnsQueryBytes(id: Int, name: String)
        -> [UInt8] {
        var out: [UInt8] = [
            UInt8((id >> 8) & 0xff), UInt8(id & 0xff),
            0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0,
        ]
        out += dnsNameBytes(name)
        out += [0, 1, 0, 1]
        return out
    }

    static func dnsResponseBytes(id: Int, name: String,
                                 addr: [UInt8])
        -> [UInt8] {
        var out: [UInt8] = [
            UInt8((id >> 8) & 0xff), UInt8(id & 0xff),
            0x81, 0x80, 0, 1, 0, 1, 0, 0, 0, 0,
        ]
        out += dnsNameBytes(name)
        out += [0, 1, 0, 1]
        out += [0xc0, 0x0c, 0, 1, 0, 1,
                0, 0, 0x01, 0x2c, 0, 4]
        out += addr
        return out
    }

    /// The sample's picture: a sixteen-
    /// pixel moon, built byte by byte —
    /// a dark field, a pale disc with a
    /// bite taken out of it. RGB rows
    /// under a stored (uncompressed)
    /// zlib stream, so every byte can be
    /// accounted for by hand; the chunk
    /// CRCs and the Adler word are
    /// worked out here, in the open.
    static func moonPNGBytes() -> [UInt8] {
        let side = 16
        var raw: [UInt8] = []
        for y in 0..<side {
            raw.append(0)
            for x in 0..<side {
                let dx = Double(x) - 10.0
                let dy = Double(y) - 7.5
                let discD2 = dx * dx + dy * dy
                let inDisc = discD2 <= 20.25
                let bx = Double(x) - 12.5
                let by = Double(y) - 6.0
                let biteD2 = bx * bx + by * by
                let inBite = biteD2 <= 14.44
                if inDisc && !inBite {
                    raw += [232, 230, 210]
                } else {
                    raw += [10, 12, 28]
                }
            }
        }
        // zlib: the no-compression
        // header, one stored block (the
        // raw rows sit far under its
        // 65535-byte limit), and the
        // Adler-32 of the rows, big-end
        // first as the format asks.
        var idat: [UInt8] = [0x78, 0x01, 0x01]
        idat.append(UInt8(raw.count & 0xff))
        idat.append(UInt8((raw.count >> 8) & 0xff))
        let nlen = raw.count ^ 0xffff
        idat.append(UInt8(nlen & 0xff))
        idat.append(UInt8((nlen >> 8) & 0xff))
        idat += raw
        var adlerA: UInt32 = 1
        var adlerB: UInt32 = 0
        for byte in raw {
            adlerA = (adlerA + UInt32(byte)) % 65521
            adlerB = (adlerB + adlerA) % 65521
        }
        let adlerWord = (adlerB << 16) | adlerA
        for shift in [24, 16, 8, 0] {
            idat.append(UInt8(
                (adlerWord >> UInt32(shift)) & 0xff))
        }
        var png: [UInt8] = [0x89, 0x50, 0x4e, 0x47,
                            0x0d, 0x0a, 0x1a, 0x0a]
        var ihdr: [UInt8] = []
        for shift in [24, 16, 8, 0] {
            ihdr.append(UInt8((side >> shift) & 0xff))
        }
        for shift in [24, 16, 8, 0] {
            ihdr.append(UInt8((side >> shift) & 0xff))
        }
        ihdr += [8, 2, 0, 0, 0]
        png += pngChunk("IHDR", ihdr)
        png += pngChunk("IDAT", idat)
        png += pngChunk("IEND", [])
        return png
    }

    /// One PNG chunk: length, type,
    /// data, and the CRC-32 the format
    /// keeps over type and data both.
    static func pngChunk(_ type: String,
                         _ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        for shift in [24, 16, 8, 0] {
            out.append(UInt8(
                (data.count >> shift) & 0xff))
        }
        let typeBytes = Array(type.utf8)
        out += typeBytes
        out += data
        var crc: UInt32 = 0xffff_ffff
        for byte in typeBytes + data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xedb8_8320
                } else {
                    crc = crc >> 1
                }
            }
        }
        crc ^= 0xffff_ffff
        for shift in [24, 16, 8, 0] {
            out.append(UInt8(
                (crc >> UInt32(shift)) & 0xff))
        }
        return out
    }
}
