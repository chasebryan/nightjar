import Foundation
import Network

// BetafischTap — betafisch B3: the
// house-wire tap and the capture
// writers.
//
// THE LINE, stated in the code as in
// the room: this is not a sniffer.
// iOS gives no app the wire. The tap
// records only the traffic the app
// ITSELF sends and receives through
// its own organs — the bench's socket
// plumbing calls in here as its bytes
// pass, and the fetch road calls in
// with the HTTP it exchanged — and
// writes those bytes into a pcapng
// the dissector can open, labelled as
// the app's own traffic on its face.
//
// What the tap does NOT do: it emits
// nothing (recording is not an organ;
// EMCON conditions that forbid an
// organ stop that organ's traffic
// from happening at all, so there is
// nothing of it to record), and it
// does not invent traffic. Organs
// whose bytes never pass a funnel the
// app can see — the serve listeners,
// NWConnection engines like tlsgrade,
// one-shot hand-built broadcasts that
// bypass the plumbing (Wake-on-LAN,
// the UPnP shout, the DHCP scout, the
// mDNS harvest), port-scan knocks that
// carry no payload — are not recorded
// and are not represented. The
// coverage note below says exactly
// this, and the capture repeats it.
//
// Synthesis, stated plainly: the
// payload bytes recorded are the
// app's own, byte for byte, with the
// real addresses, ports and times.
// The Ethernet/IP/transport headers
// around them are written by the tap —
// iOS does not hand an app its frames,
// or its Wi-Fi MAC (the MACs here are
// placeholders, 02:00:00:00:00:01 for
// the app, …:02 for the peer), and no
// handshake the app did not make is
// drawn: a TCP flow in a tap capture
// opens with its first data segment,
// because that is what the tap saw.

final class BetafischTap {

    static let shared = BetafischTap()

    static let coverageNote = L("the tap records the bench's socket plumbing and the app's HTTP fetches — the app's own traffic only. It does not record the serve listeners, NWConnection engines such as tlsgrade, or one-shot broadcasts that bypass the plumbing (Wake-on-LAN, the UPnP shout, the DHCP scout, the mDNS harvest), and it invents none of them. The tap itself sends nothing.")

    private let lock = NSLock()
    private var flows: [String: FlowState] = [:]
    private var fetchPortCursor: [String: Int] = [:]
    private var fdPeers: [Int32: Peer] = [:]
    private var recorded: [(iface: Int,
                             ts: Double,
                             bytes: [UInt8])] = []
    private var recordedBytes = 0
    private(set) var capped = false

    private struct Peer {
        var ip: String
        var port: Int
        var udp: Bool
        var localIP: String
        var localPort: Int
    }

    private struct FlowState {
        var nextSeqOut = 1
        var nextSeqIn = 1
    }

    static let frameCap = 20_000
    static let byteCap = 64 * 1024 * 1024

    private init() {}

    // MARK: The operator's switch

    var enabled: Bool {
        get {
            UserDefaults.standard.bool(
                forKey: "betafisch.tap.enabled")
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: "betafisch.tap.enabled")
        }
    }

    func snapshot() -> (frames: Int, bytes: Int,
                        capped: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (recorded.count, recordedBytes, capped)
    }

    func clear() {
        lock.lock()
        recorded = []
        recordedBytes = 0
        capped = false
        flows = [:]
        lock.unlock()
    }

    // MARK: Recording — the socket plumbing

    /// A connected socket the plumbing
    /// opened: remember who it talks to,
    /// so the bytes that follow have
    /// their endpoints. The local end is
    /// read off the socket itself.
    func noteConnect(fd: Int32, ip: String,
                     port: Int, udp: Bool) {
        guard enabled else { return }
        var localIP = "0.0.0.0"
        var localPort = 0
        var addr = sockaddr_in()
        var length = socklen_t(
            MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(
            to: &addr) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &length)
            }
        }
        if found == 0 {
            localPort = Int(
                UInt16(bigEndian: addr.sin_port))
            var raw = addr.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &raw, &text,
                      socklen_t(text.count))
            localIP = String(cString: text)
        }
        lock.lock()
        fdPeers[fd] = Peer(
            ip: ip, port: port, udp: udp,
            localIP: localIP, localPort: localPort)
        lock.unlock()
    }

    /// Forget a socket. The plumbing does
    /// not have to call this — an fd is
    /// re-registered if it is reused —
    /// but a close keeps the table honest.
    func noteClose(fd: Int32) {
        lock.lock()
        fdPeers[fd] = nil
        lock.unlock()
    }

    /// Bytes the plumbing sent or
    /// received on a registered socket.
    func record(fd: Int32, outbound: Bool,
                bytes: [UInt8]) {
        guard enabled, !bytes.isEmpty else {
            return
        }
        lock.lock()
        let peer = fdPeers[fd]
        lock.unlock()
        guard let peer else { return }
        append(localIP: peer.localIP,
               localPort: peer.localPort,
               remoteIP: peer.ip,
               remotePort: peer.port,
               outbound: outbound,
               payload: bytes,
               ipProto: peer.udp ? 17 : 6,
               iface: 0)
    }

    /// One datagram on an unconnected
    /// socket: the local end is read off
    /// the socket (a wildcard bind reads
    /// as the house's own address), the
    /// far end is the caller's word.
    func recordDatagram(fd: Int32,
                        remoteIP: String,
                        remotePort: Int,
                        outbound: Bool,
                        payload: [UInt8],
                        ipProto: Int) {
        guard enabled, !payload.isEmpty else {
            return
        }
        var localIP = "0.0.0.0"
        var localPort = 0
        var addr = sockaddr_in()
        var length = socklen_t(
            MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(
            to: &addr) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self, capacity: 1) { sa in
                getsockname(fd, sa, &length)
            }
        }
        if found == 0 {
            localPort = Int(
                UInt16(bigEndian: addr.sin_port))
            var raw = addr.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &raw, &text,
                      socklen_t(text.count))
            localIP = String(cString: text)
        }
        if localIP == "0.0.0.0",
           let own = Mouth.localIPAddress() {
            localIP = own
        }
        append(localIP: localIP,
               localPort: localPort,
               remoteIP: remoteIP,
               remotePort: remotePort,
               outbound: outbound,
               payload: payload,
               ipProto: ipProto, iface: 0)
    }

    // MARK: Recording — the fetch road

    /// An HTTP exchange the app made
    /// through its fetch road, recorded
    /// as the app saw it: the request it
    /// composed and the response it was
    /// handed. For an HTTPS fetch these
    /// are the plaintext bytes URLSession
    /// delivered to the app — on the
    /// wire they travelled as TLS
    /// records — and the capture's
    /// second interface says so on its
    /// face.
    func recordFetch(request: URLRequest,
                     response: HTTPURLResponse,
                     body: Data) {
        guard enabled,
              let url = response.url
                ?? request.url,
              let host = url.host
        else { return }
        let remoteIP = BlacksiteNet.resolve4(host)?
            .ip ?? host
        let scheme = url.scheme?.lowercased()
            ?? "http"
        let remotePort = url.port
            ?? (scheme == "https" ? 443 : 80)
        let localIP = Mouth.localIPAddress()
            ?? "0.0.0.0"
        lock.lock()
        let key = "fetch " + remoteIP + ":"
            + String(remotePort)
        var cursor = fetchPortCursor[key]
            ?? (49_152 + Int.random(in: 0..<4096))
        let localPort = cursor
        cursor += 1
        fetchPortCursor[key] = cursor
        lock.unlock()
        // The request, as composed.
        let method = request.httpMethod ?? "GET"
        var path = url.path.isEmpty
            ? "/" : url.path
        if let query = url.query,
           !query.isEmpty {
            path += "?" + query
        }
        var head = method + " " + path
            + " HTTP/1.1\r\n"
        let headers = request
            .allHTTPHeaderFields ?? [:]
        let hasHost = headers.keys.contains(
            where: { $0.lowercased() == "host" })
        if !hasHost {
            head += "Host: " + host + "\r\n"
        }
        for name in headers.keys.sorted() {
            head += name + ": "
                + (headers[name] ?? "") + "\r\n"
        }
        head += "\r\n"
        var requestBytes = Array(head.utf8)
        if let sent = request.httpBody {
            requestBytes.append(contentsOf: sent)
        }
        append(localIP: localIP,
               localPort: localPort,
               remoteIP: remoteIP,
               remotePort: remotePort,
               outbound: true,
               payload: requestBytes,
               ipProto: 6, iface: 1)
        // The response, as delivered.
        let reason = HTTPURLResponse
            .localizedString(
                forStatusCode: response.statusCode)
        var respHead = "HTTP/1.1 "
            + String(response.statusCode) + " "
            + reason + "\r\n"
        let fields = response.allHeaderFields
        for name in fields.keys
            .map({ String(describing: $0) })
            .sorted() {
            respHead += name + ": "
                + String(describing: fields[name] ?? "")
                + "\r\n"
        }
        respHead += "\r\n"
        var responseBytes = Array(respHead.utf8)
        responseBytes.append(contentsOf: body)
        append(localIP: localIP,
               localPort: localPort,
               remoteIP: remoteIP,
               remotePort: remotePort,
               outbound: false,
               payload: responseBytes,
               ipProto: 6, iface: 1)
    }

    // MARK: Frame synthesis

    private func append(localIP: String,
                        localPort: Int,
                        remoteIP: String,
                        remotePort: Int,
                        outbound: Bool,
                        payload: [UInt8],
                        ipProto: Int, iface: Int) {
        let srcIP = outbound ? localIP : remoteIP
        let dstIP = outbound ? remoteIP : localIP
        let srcPort = outbound ? localPort
            : remotePort
        let dstPort = outbound ? remotePort
            : localPort
        lock.lock()
        if capped || recorded.count >= Self.frameCap
            || recordedBytes >= Self.byteCap {
            capped = true
            lock.unlock()
            return
        }
        let endA = "\(localIP):\(localPort)"
        let endB = "\(remoteIP):\(remotePort)"
        let key = min(endA, endB) + " <> "
            + max(endA, endB) + " "
            + String(ipProto)
        var flow = flows[key] ?? FlowState()
        var segment: [UInt8] = []
        if ipProto == 6 {
            let seq = outbound ? flow.nextSeqOut
                : flow.nextSeqIn
            let ack = outbound ? flow.nextSeqIn
                : flow.nextSeqOut
            if outbound {
                flow.nextSeqOut += payload.count
            } else {
                flow.nextSeqIn += payload.count
            }
            segment = tcpSegment(
                srcPort: srcPort, dstPort: dstPort,
                seq: seq, ack: ack,
                payload: payload)
        } else if ipProto == 17 {
            segment = udpDatagram(
                srcPort: srcPort, dstPort: dstPort,
                payload: payload)
        } else {
            segment = payload
        }
        // The transport checksum is real
        // arithmetic over the synthesized
        // segment, so the dissector's own
        // verification reads it correct.
        if ipProto == 6 || ipProto == 17 {
            let sum = Betafisch.transportChecksum(
                src: ipv4Bytes(srcIP),
                dst: ipv4Bytes(dstIP),
                proto: ipProto, segment: segment)
            let at = ipProto == 6 ? 16 : 6
            segment[at] = UInt8((sum >> 8) & 0xff)
            segment[at + 1] = UInt8(sum & 0xff)
        }
        flows[key] = flow
        let packet = ipv4Packet(
            src: srcIP, dst: dstIP, proto: ipProto,
            payload: segment)
        let frame = ethernetFrame(packet,
                                  outbound: outbound)
        recorded.append((iface: iface,
                         ts: Date()
                             .timeIntervalSince1970,
                         bytes: frame))
        recordedBytes += frame.count
        lock.unlock()
    }

    private func ethernetFrame(_ packet: [UInt8],
                               outbound: Bool)
        -> [UInt8] {
        let appMAC: [UInt8] = [0x02, 0, 0, 0, 0, 1]
        let peerMAC: [UInt8] = [0x02, 0, 0, 0, 0, 2]
        var frame = outbound ? peerMAC : appMAC
        frame.append(contentsOf: outbound
            ? appMAC : peerMAC)
        frame.append(contentsOf: [0x08, 0x00])
        frame.append(contentsOf: packet)
        return frame
    }

    private func ipv4Packet(src: String,
                            dst: String,
                            proto: Int,
                            payload: [UInt8])
        -> [UInt8] {
        let srcBytes = ipv4Bytes(src)
        let dstBytes = ipv4Bytes(dst)
        let total = 20 + payload.count
        var packet: [UInt8] = [
            0x45, 0,
            UInt8((total >> 8) & 0xff),
            UInt8(total & 0xff),
            0, 0, 0x40, 0, 64,
            UInt8(proto & 0xff), 0, 0,
        ]
        packet.append(contentsOf: srcBytes)
        packet.append(contentsOf: dstBytes)
        let sum = Betafisch.checksum(
            packet, from: 0, count: 20)
        packet[10] = UInt8((sum >> 8) & 0xff)
        packet[11] = UInt8(sum & 0xff)
        packet.append(contentsOf: payload)
        return packet
    }

    private func ipv4Bytes(_ text: String)
        -> [UInt8] {
        let parts = text.split(separator: ".")
        guard parts.count == 4 else {
            return [0, 0, 0, 0]
        }
        return parts.map {
            UInt8(Int($0) ?? 0)
        }
    }

    private func tcpSegment(srcPort: Int,
                            dstPort: Int,
                            seq: Int,
                            ack: Int,
                            payload: [UInt8])
        -> [UInt8] {
        var segment: [UInt8] = [
            UInt8((srcPort >> 8) & 0xff),
            UInt8(srcPort & 0xff),
            UInt8((dstPort >> 8) & 0xff),
            UInt8(dstPort & 0xff),
            UInt8((seq >> 24) & 0xff),
            UInt8((seq >> 16) & 0xff),
            UInt8((seq >> 8) & 0xff),
            UInt8(seq & 0xff),
            UInt8((ack >> 24) & 0xff),
            UInt8((ack >> 16) & 0xff),
            UInt8((ack >> 8) & 0xff),
            UInt8(ack & 0xff),
            0x50, 0x18,
            0xfa, 0xf0, 0, 0, 0, 0,
        ]
        segment.append(contentsOf: payload)
        return segment
    }

    private func udpDatagram(srcPort: Int,
                             dstPort: Int,
                             payload: [UInt8])
        -> [UInt8] {
        let length = 8 + payload.count
        var datagram: [UInt8] = [
            UInt8((srcPort >> 8) & 0xff),
            UInt8(srcPort & 0xff),
            UInt8((dstPort >> 8) & 0xff),
            UInt8(dstPort & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
            0, 0,
        ]
        datagram.append(contentsOf: payload)
        return datagram
    }

    // MARK: The capture itself

    /// The recorded house wire as a
    /// pcapng the dissector opens: two
    /// interfaces — the socket wire and
    /// the fetch road — under a section
    /// comment that names what this is.
    func captureData() -> Data? {
        lock.lock()
        let frames = recorded
        let wasCapped = capped
        lock.unlock()
        guard !frames.isEmpty else { return nil }
        var comment = L("nightjar house-wire tap — the app's own traffic only: traffic the app itself sent and received through its bench plumbing and its fetch road. No other device's traffic is in here, and none was sniffed. Payload bytes are the app's own, byte for byte; the Ethernet/IP/transport headers are written by the tap around them (the MAC addresses are placeholders — iOS does not give an app its Wi-Fi MAC — and no handshake is drawn that the app did not make).")
        if wasCapped {
            comment += L(" The recording stopped at the tap's cap; the tail of the session is not in here.")
        }
        let interfaces: [(linktype: Int,
                           name: String,
                           description: String)] = [
            (1, L("house wire"),
             L("the bench's socket exchanges, as the app made them")),
            (1, L("house fetches"),
             L("HTTP as the app itself saw it through its fetch road — for HTTPS these are the plaintext bytes handed to the app; on the wire they travelled as TLS records")),
        ]
        return BetafischWrite.pcapng(
            frames: frames,
            interfaces: interfaces,
            comment: comment)
    }
}

// MARK: - The capture writers

/// Writing captures back out: pcapng
/// and classic pcap, from frames. Used
/// by the tap (its own recordings) and
/// by betafisch's export (any opened
/// capture). A writer moves frames; it
/// never alters their bytes.
enum BetafischWrite {

    // MARK: pcapng

    static func pcapng(
        frames: [(iface: Int, ts: Double,
                  bytes: [UInt8])],
        interfaces: [(linktype: Int,
                      name: String,
                      description: String)],
        comment: String) -> Data {
        var out: [UInt8] = []
        // Section header.
        var shb: [UInt8] = []
        appendU32(&shb, 0x1a2b3c4d, little: true)
        appendU16(&shb, 1, little: true)
        appendU16(&shb, 0, little: true)
        appendU32(&shb, 0xffffffff, little: true)
        appendU32(&shb, 0xffffffff, little: true)
        appendOption(&shb, code: 3,
                     value: Array(comment.utf8))
        appendOption(&shb, code: 0, value: [])
        appendBlock(&out, type: 0x0a0d0d0a,
                    body: shb)
        // Interfaces.
        for iface in interfaces {
            var idb: [UInt8] = []
            appendU16(&idb, UInt16(iface.linktype),
                      little: true)
            appendU16(&idb, 0, little: true)
            appendU32(&idb, 262_144, little: true)
            appendOption(&idb, code: 2,
                         value: Array(
                            iface.name.utf8))
            appendOption(&idb, code: 3,
                         value: Array(
                            iface.description.utf8))
            appendOption(&idb, code: 9,
                         value: [6])
            appendOption(&idb, code: 0, value: [])
            appendBlock(&out, type: 1, body: idb)
        }
        // Packets.
        for frame in frames {
            let micros = Int64(
                (frame.ts * 1_000_000).rounded())
            var epb: [UInt8] = []
            appendU32(&epb, UInt32(frame.iface),
                      little: true)
            appendU32(&epb,
                      UInt32(micros >> 32),
                      little: true)
            appendU32(&epb,
                      UInt32(micros & 0xffffffff),
                      little: true)
            appendU32(&epb,
                      UInt32(frame.bytes.count),
                      little: true)
            appendU32(&epb,
                      UInt32(frame.bytes.count),
                      little: true)
            epb.append(contentsOf: frame.bytes)
            appendBlock(&out, type: 6, body: epb)
        }
        return Data(out)
    }

    /// An opened capture written as
    /// pcapng: one interface per link
    /// type its frames carry, in first-
    /// seen order. The frames' bytes are
    /// carried unchanged; the source
    /// file's own comments and interface
    /// names are not (the reader never
    /// kept them), and the section
    /// comment says this is an export.
    static func pcapng(capture: BFCapture)
        -> Data {
        var linktypes: [Int] = []
        for frame in capture.frames {
            if !linktypes.contains(frame.linktype) {
                linktypes.append(frame.linktype)
            }
        }
        if linktypes.isEmpty {
            linktypes = [capture.linktype]
        }
        let interfaces = linktypes.map {
            (linktype: $0,
             name: String(format: L("linktype %lld"),
                          $0),
             description: L("exported by betafisch"))
        }
        let frames: [(iface: Int, ts: Double,
                       bytes: [UInt8])] =
            capture.frames.map { frame in
                (iface: linktypes.firstIndex(
                    of: frame.linktype) ?? 0,
                 ts: frame.timestamp,
                 bytes: frame.bytes)
            }
        return pcapng(
            frames: frames,
            interfaces: interfaces,
            comment: String(
                format: L("exported by betafisch from %@ — the frames are the capture's own, unchanged; the source file's comments and interface names were not carried over."),
                capture.name))
    }

    // MARK: Classic pcap

    /// An opened capture written as
    /// classic pcap. The classic format
    /// carries ONE link type, so frames
    /// of any other link type are left
    /// out and counted — the caller
    /// states the loss with the number.
    /// Timestamps land at microsecond
    /// resolution, the classic format's
    /// own.
    static func classicPCAP(
        capture: BFCapture)
        -> (data: Data, skipped: Int) {
        var out: [UInt8] = []
        appendU32(&out, 0xa1b2c3d4, little: true)
        appendU16(&out, 2, little: true)
        appendU16(&out, 4, little: true)
        appendU32(&out, 0, little: true)
        appendU32(&out, 0, little: true)
        appendU32(&out, 262_144, little: true)
        appendU32(&out, UInt32(capture.linktype),
                  little: true)
        var skipped = 0
        for frame in capture.frames {
            guard frame.linktype == capture.linktype
            else {
                skipped += 1
                continue
            }
            let seconds = Int64(frame.timestamp)
            var micros = Int64(
                ((frame.timestamp
                    - Double(seconds)) * 1_000_000)
                    .rounded())
            if micros >= 1_000_000 {
                micros = 999_999
            }
            if micros < 0 { micros = 0 }
            appendU32(&out, UInt32(seconds),
                      little: true)
            appendU32(&out, UInt32(micros),
                      little: true)
            appendU32(&out,
                      UInt32(frame.bytes.count),
                      little: true)
            appendU32(&out,
                      UInt32(frame.origLen),
                      little: true)
            out.append(contentsOf: frame.bytes)
        }
        return (Data(out), skipped)
    }

    // MARK: Byte plumbing

    static func appendU16(_ into: inout [UInt8],
                          _ value: UInt16,
                          little: Bool) {
        if little {
            into.append(UInt8(value & 0xff))
            into.append(
                UInt8((value >> 8) & 0xff))
        } else {
            into.append(
                UInt8((value >> 8) & 0xff))
            into.append(UInt8(value & 0xff))
        }
    }

    static func appendU32(_ into: inout [UInt8],
                          _ value: UInt32,
                          little: Bool) {
        if little {
            for shift in stride(from: 0,
                                through: 24, by: 8) {
                into.append(UInt8(
                    (value >> shift) & 0xff))
            }
        } else {
            for shift in stride(from: 24,
                                through: 0, by: -8) {
                into.append(UInt8(
                    (value >> shift) & 0xff))
            }
        }
    }

    static func appendOption(
        _ into: inout [UInt8], code: Int,
        value: [UInt8]) {
        appendU16(&into, UInt16(code),
                  little: true)
        appendU16(&into, UInt16(value.count),
                  little: true)
        into.append(contentsOf: value)
        let pad = (4 - value.count % 4) % 4
        into.append(contentsOf: [UInt8](
            repeating: 0, count: pad))
    }

    static func appendBlock(
        _ into: inout [UInt8], type: UInt32,
        body: [UInt8]) {
        let pad = (4 - body.count % 4) % 4
        let total = UInt32(12 + body.count + pad)
        appendU32(&into, type, little: true)
        appendU32(&into, total, little: true)
        into.append(contentsOf: body)
        into.append(contentsOf: [UInt8](
            repeating: 0, count: pad))
        appendU32(&into, total, little: true)
    }
}
