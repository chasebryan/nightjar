import Foundation
import Network
import Security

// BlacksiteBenchDoors — the bench, wave
// four (fix-wave: doors and services).
// Twenty-five more engines in the
// bench's manner: each knocks once on
// a service door the operator named,
// reads only what the service itself
// offers a stranger — a greeting, a
// negotiate answer, a published
// directory, a status document — and
// grades it in the open. This wave
// attempts NO authentication anywhere:
// not a default word, not an anonymous
// one. Where a protocol's next step
// would be a login or a write, the
// engine stops one step before it and
// grades what was already shown.

extension BlacksiteBench {

    // MARK: shared plumbing

    /// Wave four speaks through the
    /// house emit; a kindless call
    /// reads .out.
    private static func doorSay(
        _ emit: BlacksiteEmit,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    /// A connected BSD stream socket, or
    /// nil. The caller closes it. Rides the
    /// shared road (BlacksiteNet.streamConnect)
    /// — the Onion's wrap gate stands there.
    private static func doorSocket(
        ip: String, port: UInt16,
        timeout: Double) -> Int32? {
        BlacksiteNet.streamConnect(
            ip: ip, port: port, timeout: timeout)
    }

    /// Read exactly n bytes, or nil.
    private static func doorRead(
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

    /// Send all bytes; false on failure.
    private static func doorSend(
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
        BetafischTap.shared.record(
            fd: fd, outbound: true, bytes: bytes)
        return true
    }

    /// Read whatever arrives within the
    /// window, up to the cap — the shape
    /// of a greeting read, where the far
    /// end speaks first and then waits.
    private static func doorAvailable(
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

    /// host[:port] split for the wire
    /// engines: resolves the name.
    private static func doorResolve(
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

    /// host[:port] split for the HTTP
    /// engines: the name itself rides in
    /// the URL, unresolved, so virtual
    /// hosts still hear their own name.
    private static func doorSplit(
        _ target: String,
        _ defaultPort: Int)
        -> (host: String, port: Int)? {
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
        guard !host.isEmpty else {
            return nil
        }
        return (host, port)
    }

    /// A buffered line talker for the
    /// banner protocols (SMTP, IMAP,
    /// POP3, memcached), buffered across
    /// calls so a reply read in pieces
    /// never loses the seam.
    private final class DoorTalk {
        let fd: Int32
        private var buffer: [UInt8] = []
        private var drained = false
        init(fd: Int32) { self.fd = fd }

        func sendLine(_ line: String) {
            _ = doorSend(fd,
                         Array(line.utf8))
        }

        /// The next line, without its
        /// ending; nil when the far end
        /// has gone quiet for good.
        func nextLine() -> String? {
            while true {
                if let nl = buffer
                    .firstIndex(of: 0x0A) {
                    let line = Array(
                        buffer[0..<nl])
                    buffer.removeFirst(
                        nl + 1)
                    var text = String(
                        bytes: line,
                        encoding: .utf8) ?? ""
                    if text.hasSuffix("\r") {
                        text = String(
                            text.dropLast())
                    }
                    return text
                }
                if drained {
                    if buffer.isEmpty {
                        return nil
                    }
                    let text = String(
                        bytes: buffer,
                        encoding: .utf8) ?? ""
                    buffer.removeAll()
                    return text
                }
                var chunk = [UInt8](
                    repeating: 0,
                    count: 4096)
                let got = recv(fd, &chunk,
                               chunk.count, 0)
                if got > 0 {
                    buffer.append(
                        contentsOf:
                            chunk[0..<got])
                } else {
                    drained = true
                }
            }
        }

        /// Lines until the target line
        /// stands alone (memcached's END,
        /// POP3's lone dot), inclusive.
        func linesUntil(
            _ target: String,
            limit: Int = 400) -> [String] {
            var lines: [String] = []
            while lines.count < limit {
                guard let line = nextLine()
                else { break }
                lines.append(line)
                if line == target {
                    break
                }
            }
            return lines
        }

        /// An SMTP-shaped reply: lines
        /// until one opens with the code
        /// and a space instead of a dash.
        func smtpReply()
            -> (code: Int,
                lines: [String]) {
            var lines: [String] = []
            var code = 0
            while lines.count < 40 {
                guard let line = nextLine()
                else { break }
                lines.append(line)
                if line.count >= 3 {
                    let head = line.prefix(3)
                    if let value = Int(head) {
                        code = value
                        if line.count == 3
                            || line[ line.index(
                                line.startIndex,
                                offsetBy: 3)
                            ] == " " {
                            break
                        }
                    } else {
                        break
                    }
                } else {
                    break
                }
            }
            return (code, lines)
        }

        /// An IMAP reply: lines until the
        /// tagged completion line.
        func imapReply(
            tag: String) -> [String] {
            var lines: [String] = []
            while lines.count < 60 {
                guard let line = nextLine()
                else { break }
                lines.append(line)
                if line.hasPrefix(
                    tag + " ") {
                    break
                }
            }
            return lines
        }
    }

    // MARK: the HTTP census plumbing

    /// One fetch through the house web
    /// session, the wave's whole wire
    /// budget for the HTTP doors.
    private static func doorFetch(
        _ request: URLRequest)
        -> (Data, HTTPURLResponse)? {
        let (session, _) = BlacksitePentest
            .webSession(follow: false)
        defer {
            session.invalidateAndCancel()
        }
        guard let (data, http) =
            BlacksitePentest.syncFetch(
                session, request),
              let http = http else {
            return nil
        }
        return (data, http)
    }

    private static func doorGET(
        _ url: URL)
        -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            BlacksiteNet.userAgent,
            forHTTPHeaderField: "User-Agent")
        return doorFetch(request)
    }

    private static func doorPOST(
        _ url: URL, contentType: String,
        body: [UInt8])
        -> (Data, HTTPURLResponse)? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue(
            BlacksiteNet.userAgent,
            forHTTPHeaderField: "User-Agent")
        request.setValue(
            contentType,
            forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body)
        return doorFetch(request)
    }

    private static func doorJSON(
        _ data: Data) -> [String: Any]? {
        guard let obj = try?
            JSONSerialization.jsonObject(
                with: data),
              let dict = obj
                as? [String: Any] else {
            return nil
        }
        return dict
    }

    /// A JSON string field, read plainly.
    private static func doorField(
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

    // MARK: a TLS fetch that reads any papers

    /// The collecting box for the TLS
    /// read — a reference type, because
    /// receive callbacks outlive the call.
    private final class DoorTLSBox {
        var data: [UInt8] = []
        var settled = false
    }

    /// One HTTPS GET over NWConnection
    /// with the bench's census trust
    /// (tlsgrade's posture: any papers
    /// are accepted for the read; the
    /// papers themselves are graded by
    /// certprobe, elsewhere). Returns
    /// the status, the lowercased header
    /// map, and the body bytes.
    private static func doorTLSGet(
        host: String, port: UInt16,
        path: String)
        -> (Int, [String: String],
            [UInt8])? {
        guard let nwPort = NWEndpoint.Port(
            rawValue: port) else {
            return nil
        }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, _, completion in
                completion(true)
            },
            DispatchQueue(label:
                "nightjar.benchdoors.verify"))
        let params = NWParameters(
            tls: options)
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort, using: params)
        let box = DoorTLSBox()
        let sem = DispatchSemaphore(
            value: 0)
        func settle() {
            if !box.settled {
                box.settled = true
                sem.signal()
            }
        }
        connection.stateUpdateHandler = {
            state in
            switch state {
            case .ready:
                let request =
                    "GET \(path) HTTP/1.1\r\n"
                    + "Host: \(host)\r\n"
                    + "User-Agent: "
                    + "\(BlacksiteNet.userAgent)\r\n"
                    + "Accept: */*\r\n"
                    + "Connection: close\r\n"
                    + "\r\n"
                connection.send(
                    content: Data(
                        Array(request.utf8)),
                    completion: .contentProcessed { _ in
                    })
                func receiveMore() {
                    connection.receive(
                        minimumIncompleteLength: 1,
                        maximumLength: 65536) {
                        content, _, isComplete,
                        error in
                        if let content =
                            content,
                           !content.isEmpty {
                            box.data.append(
                                contentsOf:
                                    content)
                        }
                        if isComplete
                            || error != nil {
                            settle()
                        } else {
                            receiveMore()
                        }
                    }
                }
                receiveMore()
            case .failed, .cancelled:
                settle()
            default:
                break
            }
        }
        connection.start(queue:
            DispatchQueue(label:
                "nightjar.benchdoors.tls"))
        _ = sem.wait(timeout: .now() + 9)
        connection.cancel()
        guard !box.data.isEmpty else {
            return nil
        }
        return doorParseHTTP(box.data)
    }

    /// A raw HTTP/1.1 answer, taken
    /// apart: status, headers, body —
    /// dechunked when the answer came
    /// in pieces.
    private static func doorParseHTTP(
        _ bytes: [UInt8])
        -> (Int, [String: String],
            [UInt8])? {
        var seam: Int? = nil
        if bytes.count >= 4 {
            for i in 0...(bytes.count - 4) {
                if bytes[i] == 0x0D,
                   bytes[i + 1] == 0x0A,
                   bytes[i + 2] == 0x0D,
                   bytes[i + 3] == 0x0A {
                    seam = i
                    break
                }
            }
        }
        guard let headEnd = seam else {
            return nil
        }
        let head = String(
            bytes: bytes[0..<headEnd],
            encoding: .isoLatin1) ?? ""
        var body = [UInt8](
            bytes[(headEnd + 4)...])
        let headLines = head.split(
            separator: "\r\n",
            omittingEmptySubsequences: false)
        guard let first = headLines.first
        else { return nil }
        let firstParts = first.split(
            separator: " ")
        guard firstParts.count >= 2,
              let status = Int(
                firstParts[1]) else {
            return nil
        }
        var headers: [String: String] = [:]
        for line in headLines.dropFirst() {
            guard let colon = line.firstIndex(
                of: ":") else { continue }
            let name = String(
                line[..<colon])
                .lowercased()
            let value = String(
                line[line.index(
                    after: colon)...])
                .trimmingCharacters(
                    in: .whitespaces)
            headers[name] = value
        }
        if let encoding =
            headers["transfer-encoding"],
           encoding.lowercased()
            .contains("chunked") {
            body = doorDechunk(body)
        } else if let lengthText =
            headers["content-length"],
                  let length = Int(
                    lengthText),
                  body.count > length {
            body = Array(body[0..<length])
        }
        return (status, headers, body)
    }

    /// HTTP chunked transfer coding,
    /// undone (RFC 9112 §7.1).
    private static func doorDechunk(
        _ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var pos = 0
        while pos < body.count {
            var lineEnd = pos
            while lineEnd + 1 < body.count,
                  !(body[lineEnd] == 0x0D
                    && body[lineEnd + 1]
                        == 0x0A) {
                lineEnd += 1
            }
            guard lineEnd + 1 < body.count
            else { break }
            let sizeText = String(
                bytes: body[pos..<lineEnd],
                encoding: .utf8) ?? ""
            let sizeField = sizeText
                .split(separator: ";")
                .first.map(String.init)
                ?? sizeText
            guard let size = Int(
                sizeField
                    .trimmingCharacters(
                        in: .whitespaces),
                radix: 16) else {
                break
            }
            let dataStart = lineEnd + 2
            if size == 0 { break }
            guard dataStart + size
                <= body.count else {
                break
            }
            out.append(contentsOf:
                body[dataStart..<(dataStart
                                    + size)])
            pos = dataStart + size + 2
        }
        return out
    }

    // MARK: ONC RPC — the Sun wire (RFC 5531)

    /// A walking reader over XDR bytes
    /// (RFC 4506): every value is
    /// big-endian and padded to four.
    private struct DoorXDR {
        var bytes: [UInt8]
        var pos = 0

        mutating func u32() -> UInt32? {
            guard pos + 4 <= bytes.count
            else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 {
                value = (value << 8)
                    | UInt32(bytes[pos + i])
            }
            pos += 4
            return value
        }

        mutating func boolean() -> Bool? {
            guard let value = u32()
            else { return nil }
            return value != 0
        }

        mutating func skip(_ n: Int) {
            pos = min(bytes.count,
                      pos + max(0, n))
        }

        mutating func paddedString()
            -> String? {
            guard let length = u32()
            else { return nil }
            let count = Int(length)
            guard count >= 0,
                  count <= 1_000_000,
                  pos + count <= bytes.count
            else { return nil }
            let text = String(
                bytes: bytes[pos..<(pos
                                       + count)],
                encoding: .utf8)
            skip(count)
            let pad = (4 - (count % 4)) % 4
            skip(pad)
            return text
        }
    }

    private static func doorU32(
        _ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF),
         UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF),
         UInt8(value & 0xFF)]
    }

    /// One RPC call over TCP: the call
    /// rides in a record-marked frame
    /// (RFC 5531 §11), the reply is
    /// gathered fragment by fragment,
    /// and the reader comes back
    /// standing on the results — with
    /// the accept status beside it.
    /// Authentication is AUTH_NONE on
    /// both flanks: the anonymous null
    /// credential the protocols publish
    /// for exactly these public reads,
    /// never a name or a word.
    private static func doorRPC(
        ip: String, port: UInt16,
        prog: UInt32, vers: UInt32,
        procedure: UInt32, args: [UInt8])
        -> (accept: Int, reader: DoorXDR)? {
        var call: [UInt8] = []
        call += doorU32(0x4E4A5243)
        call += doorU32(0)
        call += doorU32(2)
        call += doorU32(prog)
        call += doorU32(vers)
        call += doorU32(procedure)
        call += doorU32(0)
        call += doorU32(0)
        call += doorU32(0)
        call += doorU32(0)
        call += args
        var frame = doorU32(
            0x80000000
                | UInt32(call.count))
        frame += call
        guard let fd = doorSocket(
            ip: ip, port: port,
            timeout: 4) else {
            return nil
        }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 3)
        guard doorSend(fd, frame) else {
            return nil
        }
        var message: [UInt8] = []
        var lastFragment = false
        while !lastFragment {
            guard let mark = doorRead(fd, 4)
            else { return nil }
            let word = (UInt32(mark[0]) << 24)
                | (UInt32(mark[1]) << 16)
                | (UInt32(mark[2]) << 8)
                | UInt32(mark[3])
            lastFragment = word
                & 0x80000000 != 0
            let length = Int(
                word & 0x7FFFFFFF)
            guard length >= 0,
                  length <= 4_000_000,
                  let piece = doorRead(
                    fd, length) else {
                return nil
            }
            message.append(contentsOf:
                            piece)
        }
        var reader = DoorXDR(
            bytes: message)
        guard let _ = reader.u32(),
              let msgType = reader.u32(),
              msgType == 1,
              let replyStat = reader.u32(),
              replyStat == 0,
              let _ = reader.u32(),
              let verfLength = reader.u32()
        else { return nil }
        let pad = (4 - (Int(verfLength)
                        % 4)) % 4
        reader.skip(Int(verfLength) + pad)
        guard let accept = reader.u32()
        else { return nil }
        return (Int(accept), reader)
    }

    /// A portmapper GETPORT (RFC 1833:
    /// program 100000, version 2,
    /// procedure 3) over TCP — asks the
    /// directory where a program lives.
    private static func doorGetPort(
        ip: String, prog: UInt32,
        vers: UInt32) -> UInt16? {
        var args: [UInt8] = []
        args += doorU32(prog)
        args += doorU32(vers)
        args += doorU32(6)
        args += doorU32(0)
        guard let reply = doorRPC(
            ip: ip, port: 111,
            prog: 100000, vers: 2,
            procedure: 3, args: args),
              reply.accept == 0 else {
            return nil
        }
        var reader = reply.reader
        guard let port = reader.u32()
        else { return nil }
        return UInt16(clamping: Int(port))
    }

    // MARK: BSON — the Mongo wire's paper

    private static func doorBSONCString(
        _ key: String) -> [UInt8] {
        Array(key.utf8) + [0]
    }

    private static func doorBSONInt32(
        _ value: Int32) -> [UInt8] {
        let bits = UInt32(bitPattern: value)
        return [UInt8(bits & 0xFF),
                UInt8((bits >> 8) & 0xFF),
                UInt8((bits >> 16) & 0xFF),
                UInt8((bits >> 24) & 0xFF)]
    }

    /// A whole BSON document from its
    /// elements (BSON spec: an int32
    /// total length, the elements, a
    /// zero terminator).
    private static func doorBSONDoc(
        _ elements: [UInt8]) -> [UInt8] {
        doorBSONInt32(
            Int32(elements.count + 5))
            + elements + [0]
    }

    /// One BSON document read into a
    /// plain map: strings, bools,
    /// numbers, and nested documents as
    /// rendered text. Unknown shapes are
    /// skipped by their own lengths.
    private static func doorBSONParse(
        _ bytes: [UInt8], from start: Int)
        -> [String: Any]? {
        guard start + 4 <= bytes.count
        else { return nil }
        func int32At(_ pos: Int) -> Int {
            Int(bytes[pos])
                | (Int(bytes[pos + 1]) << 8)
                | (Int(bytes[pos + 2]) << 16)
                | (Int(bytes[pos + 3]) << 24)
        }
        let total = int32At(start)
        guard total >= 5,
              start + total <= bytes.count
        else { return nil }
        let end = start + total - 1
        var pos = start + 4
        var out: [String: Any] = [:]
        while pos < end {
            let type = bytes[pos]
            pos += 1
            if type == 0 { break }
            var keyEnd = pos
            while keyEnd < end,
                  bytes[keyEnd] != 0 {
                keyEnd += 1
            }
            guard keyEnd < end else {
                return out
            }
            let key = String(
                bytes: bytes[pos..<keyEnd],
                encoding: .utf8) ?? ""
            pos = keyEnd + 1
            switch type {
            case 0x01:
                guard pos + 8 <= end + 1
                else { return out }
                let bits = (0..<8).reduce(
                    UInt64(0)) { acc, i in
                    acc | (UInt64(
                        bytes[pos + i])
                        << (8 * i))
                }
                out[key] = Double(
                    bitPattern: bits)
                pos += 8
            case 0x02, 0x0D, 0x0E:
                guard pos + 4 <= end + 1
                else { return out }
                let length = int32At(pos)
                guard length >= 1,
                      pos + 4 + length
                        <= end + 1 else {
                    return out
                }
                out[key] = String(
                    bytes: bytes[(pos
                        + 4)..<(pos + 4
                            + length - 1)],
                    encoding: .utf8) ?? ""
                pos += 4 + length
            case 0x03, 0x04:
                guard pos + 4 <= end + 1
                else { return out }
                let length = int32At(pos)
                guard length >= 5,
                      pos + length <= end + 1
                else { return out }
                if type == 0x03 {
                    out[key] = doorBSONParse(
                        bytes, from: pos)
                        ?? [:]
                } else {
                    out[key] = "<array>"
                }
                pos += length
            case 0x05:
                guard pos + 4 <= end + 1
                else { return out }
                let length = int32At(pos)
                guard length >= 0,
                      pos + 5 + length
                        <= end + 1 else {
                    return out
                }
                pos += 5 + length
            case 0x07:
                pos += 12
            case 0x08:
                guard pos < end + 1
                else { return out }
                out[key] = bytes[pos] != 0
                pos += 1
            case 0x09, 0x11:
                pos += 8
            case 0x0A:
                break
            case 0x0B:
                while pos < end,
                      bytes[pos] != 0 {
                    pos += 1
                }
                pos += 1
                while pos < end,
                      bytes[pos] != 0 {
                    pos += 1
                }
                pos += 1
            case 0x0F:
                guard pos + 4 <= end + 1
                else { return out }
                pos += int32At(pos)
            case 0x10:
                guard pos + 4 <= end + 1
                else { return out }
                out[key] = int32At(pos)
                pos += 4
            case 0x12:
                guard pos + 8 <= end + 1
                else { return out }
                let low = UInt64(int32At(
                    pos)) & 0xFFFFFFFF
                let high = UInt64(int32At(
                    pos + 4)) & 0xFFFFFFFF
                out[key] = Int(
                    bitPattern:
                        UInt(truncatingIfNeeded:
                            low | (high << 32)))
                pos += 8
            case 0x13:
                pos += 16
            case 0xFF, 0x7F:
                break
            default:
                return out
            }
            if pos > end { break }
        }
        return out
    }
}

extension BlacksiteBench {

    // MARK: smbprobe — the file door's negotiate

    /// One SMB2 NEGOTIATE (MS-SMB2
    /// §2.2.3) and nothing after it: no
    /// session setup, no tree connect,
    /// and no authentication attempt of
    /// any kind. The answer names the
    /// dialect the house would speak,
    /// whether signing is merely on or
    /// truly required, and the
    /// capabilities it advertises.
    static func smbprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 445) else {
                doorSay(emit, L("smbprobe: give host[:port] — smbprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("smbprobe: nothing answers on the file door at %@."), host))
                return
            }
            defer { close(fd) }
            var packet: [UInt8] = []
            packet += [0xFE, 0x53, 0x4D, 0x42]
            packet += [0x40, 0x00]
            packet += [0x00, 0x00]
            packet += [0x00, 0x00, 0x00, 0x00]
            packet += [0x00, 0x00]
            packet += [0x01, 0x00]
            packet += [UInt8](repeating: 0,
                              count: 4)
            packet += [UInt8](repeating: 0,
                              count: 4)
            packet += [UInt8](repeating: 0,
                              count: 8)
            packet += [UInt8](repeating: 0,
                              count: 4)
            packet += [UInt8](repeating: 0,
                              count: 4)
            packet += [UInt8](repeating: 0,
                              count: 8)
            packet += [UInt8](repeating: 0,
                              count: 16)
            packet += [0x24, 0x00]
            packet += [0x04, 0x00]
            packet += [0x01, 0x00]
            packet += [0x00, 0x00]
            packet += [0x00, 0x00, 0x00, 0x00]
            let guidText = "nightjar-probe!"
            var guid = Array(guidText.utf8)
            while guid.count < 16 {
                guid.append(0)
            }
            packet += guid
            packet += [UInt8](repeating: 0,
                              count: 8)
            packet += [0x02, 0x02, 0x10, 0x02,
                       0x00, 0x03, 0x02, 0x03]
            // On the direct door (445) the
            // message rides inside a NetBIOS
            // session frame (MS-SMB2 §2.1):
            // a zero type byte, then the
            // length on three bytes.
            var framed: [UInt8] = [0x00]
            framed.append(UInt8(
                (packet.count >> 16) & 0xFF))
            framed.append(UInt8(
                (packet.count >> 8) & 0xFF))
            framed.append(UInt8(
                packet.count & 0xFF))
            framed += packet
            guard doorSend(fd, framed) else {
                doorSay(emit, L("smbprobe: the negotiate never left."))
                return
            }
            let reply = doorAvailable(fd, seconds: 3, cap: 2048)
            guard reply.count >= 4 else {
                doorSay(emit, L("smbprobe: the door stayed silent — not SMB, or not awake."))
                return
            }
            // The answer wears the same
            // NetBIOS frame; a bare answer
            // is read where it stands.
            var base = 0
            if reply.count >= 5,
               reply[0] == 0x00,
               reply[4] == 0xFE
                || reply[4] == 0xFF {
                base = 4
            }
            if reply[base] == 0xFF {
                doorSay(emit, L("smbprobe: it answered in SMB1 — the retired dialect, kept alive. Anything that still speaks it should be made to stop."), .err)
                return
            }
            guard reply[base] == 0xFE,
                  reply.count >= base + 104
            else {
                doorSay(emit, L("smbprobe: whatever answered is not speaking SMB2."))
                return
            }
            func u16(_ at: Int) -> Int {
                Int(reply[base + at])
                    | (Int(reply[base + at + 1])
                        << 8)
            }
            func u32(_ at: Int) -> Int {
                Int(reply[base + at])
                    | (Int(reply[base + at + 1])
                        << 8)
                    | (Int(reply[base + at + 2])
                        << 16)
                    | (Int(reply[base + at + 3])
                        << 24)
            }
            let status = u32(8)
            if status != 0 {
                doorSay(emit, String(format: L("smbprobe: the negotiate was refused (status %lld) — the door is shut to strangers."), status), .ok)
                return
            }
            let securityMode = u16(66)
            let dialect = u16(68)
            let capabilities = u32(88)
            let dialectNames: [Int: String] = [
                0x0202: "SMB 2.0.2",
                0x0210: "SMB 2.1",
                0x0300: "SMB 3.0",
                0x0302: "SMB 3.0.2",
                0x0311: "SMB 3.1.1",
                0x02FF: "SMB2 wildcard",
            ]
            let dialectName = dialectNames[dialect]
                ?? String(format: L("dialect %lld"), dialect)
            doorSay(emit, String(format: L("smbprobe: %@ would speak %@ to a stranger."), host, dialectName), .sys)
            let signingOn = securityMode & 0x0001 != 0
            let signingRequired = securityMode & 0x0002 != 0
            if signingRequired {
                doorSay(emit, L("smbprobe: signing is REQUIRED — a relay cannot wear this house's answers."), .ok)
            } else if signingOn {
                doorSay(emit, L("smbprobe: signing is on but NOT required — the classic relay posture: answers can be borrowed and worn elsewhere."), .err)
            } else {
                doorSay(emit, L("smbprobe: signing is not even offered — sessions here can be read and bent on the road."), .err)
            }
            var caps: [String] = []
            if capabilities & 0x01 != 0 { caps.append("DFS") }
            if capabilities & 0x02 != 0 { caps.append(L("leasing")) }
            if capabilities & 0x04 != 0 { caps.append(L("large MTU")) }
            if capabilities & 0x08 != 0 { caps.append(L("multi-channel")) }
            if capabilities & 0x10 != 0 { caps.append(L("persistent handles")) }
            if capabilities & 0x20 != 0 { caps.append(L("directory leasing")) }
            if capabilities & 0x40 != 0 { caps.append(L("encryption")) }
            if !caps.isEmpty {
                doorSay(emit, String(format: L("smbprobe: capabilities on the table: %@"), caps.joined(separator: ", ")))
            }
            if dialect <= 0x0210 {
                doorSay(emit, L("smbprobe: the chosen dialect is old — the 2.x line predates SMB encryption entirely."), .err)
            }
            doorSay(emit, L("smbprobe: stopped at the negotiate — no session, no tree, no name was offered."))
        }
    }

    // MARK: nfsprobe — the export list, published

    /// The NFS house read the way the
    /// protocol itself offers it
    /// (RFC 1813 for NFSv3, RFC 1833 for
    /// the portmapper): a NULL call to
    /// prove the program lives, the
    /// directory asked where mountd
    /// lives, and mountd's EXPORT list —
    /// the protocol's own public
    /// listing of what is shared and
    /// with whom. No mount is attempted
    /// and no file is touched.
    static func nfsprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 2049) else {
                doorSay(emit, L("nfsprobe: give host[:port] — nfsprobe 192.168.1.10"), .err)
                return
            }
            let nfsPort = doorGetPort(ip: ip, prog: 100003, vers: 3) ?? port
            guard let nullReply = doorRPC(
                ip: ip, port: nfsPort,
                prog: 100003, vers: 3,
                procedure: 0, args: []),
                  nullReply.accept == 0 else {
                doorSay(emit, String(format: L("nfsprobe: no NFS program answers at %@ — its NULL call went unreturned."), host))
                return
            }
            doorSay(emit, String(format: L("nfsprobe: NFSv3 lives at %@ (door %lld), and answers a stranger's knock."), host, Int(nfsPort)), .sys)
            guard let mountPort = doorGetPort(ip: ip, prog: 100005, vers: 3) else {
                doorSay(emit, L("nfsprobe: the directory names no mountd — the export list cannot be read from here."))
                return
            }
            guard let exportReply = doorRPC(
                ip: ip, port: mountPort,
                prog: 100005, vers: 3,
                procedure: 5, args: []),
                  exportReply.accept == 0 else {
                doorSay(emit, L("nfsprobe: mountd refused its export list to a stranger — the list is kept indoors."), .ok)
                return
            }
            var reader = exportReply.reader
            var exports: [(path: String,
                           groups: [String])] = []
            while let more = reader.boolean(),
                  more,
                  exports.count < 40 {
                guard let path = reader
                    .paddedString() else {
                    break
                }
                var groups: [String] = []
                while let hasGroup = reader
                    .boolean(), hasGroup,
                      groups.count < 12 {
                    guard let group = reader
                        .paddedString() else {
                        break
                    }
                    groups.append(group)
                }
                exports.append((path, groups))
            }
            if exports.isEmpty {
                doorSay(emit, L("nfsprobe: the export list is EMPTY — nothing is shared from this house."), .ok)
                return
            }
            doorSay(emit, String(format: L("nfsprobe: %lld export(s) published to anyone who asks:"), exports.count), .err)
            for entry in exports {
                if entry.groups.isEmpty {
                    doorSay(emit, String(format: L("  %@ — to the whole world, no list of names at all"), entry.path), .err)
                } else {
                    doorSay(emit, String(format: L("  %@ — to %@"), entry.path, entry.groups.joined(separator: ", ")))
                }
            }
            doorSay(emit, L("nfsprobe: an export list is a map of the house's papers — publishing it tells a stranger exactly where to knock, and how the door is hung."))
        }
    }

    // MARK: rpcprobe — the directory itself

    /// The RPC directory read whole:
    /// the portmapper's own DUMP
    /// (RFC 1833, procedure 4) — every
    /// program, version, protocol and
    /// door the house has registered,
    /// published by the service itself.
    /// Where DUMP is refused, the
    /// census falls back to asking the
    /// directory about the well-known
    /// programs one at a time.
    static func rpcprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) = doorResolve(target, 111) else {
                doorSay(emit, L("rpcprobe: give host[:port] — rpcprobe 192.168.1.10"), .err)
                return
            }
            let names: [UInt32: String] = [
                100000: "portmapper",
                100001: "rstatd",
                100002: "rusersd",
                100003: "nfs",
                100004: "ypserv",
                100005: "mountd",
                100007: "ypbind",
                100011: "rquotad",
                100012: "sprayd",
                100021: "nlockmgr",
                100024: "status",
                100068: "cmsd",
                100083: "tooltalk",
                100227: "nfs_acl",
            ]
            var rows: [(prog: UInt32,
                        vers: UInt32,
                        proto: UInt32,
                        port: UInt32)] = []
            if let dump = doorRPC(
                ip: ip, port: 111,
                prog: 100000, vers: 2,
                procedure: 4, args: []),
               dump.accept == 0 {
                var reader = dump.reader
                while let more = reader
                    .boolean(), more,
                      rows.count < 200 {
                    guard let prog = reader.u32(),
                          let vers = reader.u32(),
                          let proto = reader.u32(),
                          let door = reader.u32()
                    else { break }
                    rows.append((prog, vers,
                                 proto, door))
                }
            }
            if rows.isEmpty {
                doorSay(emit, L("rpcprobe: the directory would not read its whole book aloud — asking after the known programs one by one."))
                let known: [UInt32] = [
                    100003, 100005, 100021,
                    100024, 100001, 100002,
                ]
                for prog in known {
                    if let found = doorGetPort(
                        ip: ip, prog: prog,
                        vers: 0) {
                        rows.append((prog, 0, 6,
                                     UInt32(found)))
                    }
                }
            }
            guard !rows.isEmpty else {
                doorSay(emit, String(format: L("rpcprobe: no RPC directory answers at %@ — the portmapper is silent or shut."), host))
                return
            }
            doorSay(emit, String(format: L("rpcprobe: the directory at %@ publishes %lld registration(s):"), host, rows.count), .sys)
            var flagged: [String] = []
            for row in rows {
                let name = names[row.prog]
                    ?? String(format: L("program %lld"), Int(row.prog))
                let protoName = row.proto == 6
                    ? "tcp" : (row.proto == 17
                        ? "udp" : String(
                            format: L("proto %lld"),
                            Int(row.proto)))
                if row.vers > 0 {
                    doorSay(emit, String(format: L("  %@ v%lld — %@ door %lld"), name, Int(row.vers), protoName, Int(row.port)))
                } else {
                    doorSay(emit, String(format: L("  %@ — %@ door %lld"), name, protoName, Int(row.port)))
                }
                if row.prog == 100003
                    || row.prog == 100005 {
                    flagged.append(name)
                }
            }
            if !flagged.isEmpty {
                doorSay(emit, String(format: L("rpcprobe: file service lives here (%@) — nfsprobe reads what it publishes."), flagged.joined(separator: ", ")), .err)
            } else {
                doorSay(emit, L("rpcprobe: a published directory is itself the leak — it maps the house's whole RPC household for any stranger."), .out)
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: mysqlprobe — the greeting, read

    /// MySQL speaks first (the Initial
    /// Handshake Packet of the client/
    /// server protocol): version,
    /// connection id, capability flags,
    /// and the name of the authentication
    /// plugin it will demand. The probe
    /// reads the greeting and leaves —
    /// no auth response is ever built,
    /// let alone sent.
    static func mysqlprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 3306) else {
                doorSay(emit, L("mysqlprobe: give host[:port] — mysqlprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("mysqlprobe: nothing answers on the database door at %@."), host))
                return
            }
            defer { close(fd) }
            guard let head = doorRead(fd, 4),
                  head.count == 4 else {
                doorSay(emit, L("mysqlprobe: the door answered with silence."))
                return
            }
            let length = Int(head[0])
                | (Int(head[1]) << 8)
                | (Int(head[2]) << 16)
            guard length > 0, length < 4096,
                  let payload = doorRead(fd, length),
                  payload.count == length,
                  !payload.isEmpty else {
                doorSay(emit, L("mysqlprobe: the greeting was cut short."))
                return
            }
            if payload[0] == 0xFF {
                let code = payload.count > 2
                    ? Int(payload[1])
                        | (Int(payload[2]) << 8)
                    : 0
                var message = ""
                if payload.count > 3 {
                    let start = payload[3] == 0x23
                        && payload.count > 9
                        ? 9 : 3
                    message = String(
                        bytes: payload[start...],
                        encoding: .utf8) ?? ""
                }
                doorSay(emit, String(format: L("mysqlprobe: the greeting is a refusal (error %lld) — %@. The host list stands at the door, and this address is not on it."), code, message), .ok)
                return
            }
            guard payload[0] == 0x0A else {
                doorSay(emit, L("mysqlprobe: whatever answered is not speaking MySQL's greeting."))
                return
            }
            var pos = 1
            var versionEnd = pos
            while versionEnd < payload.count,
                  payload[versionEnd] != 0 {
                versionEnd += 1
            }
            let version = String(
                bytes: payload[pos..<versionEnd],
                encoding: .utf8) ?? "?"
            pos = versionEnd + 1
            doorSay(emit, String(format: L("mysqlprobe: %@ greets strangers as MySQL %@."), host, version), .sys)
            guard pos + 15 <= payload.count
            else {
                doorSay(emit, L("mysqlprobe: the greeting ended before its flags — read what was shown, no further."))
                return
            }
            pos += 4
            pos += 8
            pos += 1
            let lowCaps = Int(payload[pos])
                | (Int(payload[pos + 1]) << 8)
            pos += 2
            guard pos + 1 + 2 + 2 <= payload.count
            else { return }
            pos += 1
            pos += 2
            let highCaps = Int(payload[pos])
                | (Int(payload[pos + 1]) << 8)
            pos += 2
            let caps = lowCaps | (highCaps << 16)
            if pos + 1 + 10 + 13
                <= payload.count {
                pos += 1
                pos += 10
                pos += 13
                if pos < payload.count {
                    var nameEnd = pos
                    while nameEnd < payload.count,
                          payload[nameEnd] != 0 {
                        nameEnd += 1
                    }
                    let plugin = String(
                        bytes: payload[pos..<nameEnd],
                        encoding: .utf8) ?? ""
                    if !plugin.isEmpty {
                        doorSay(emit, String(format: L("mysqlprobe: the password door is '%@' — the greeting names it before any name is given."), plugin))
                        if plugin == "mysql_native_password" {
                            doorSay(emit, L("mysqlprobe: the native plugin is the old SHA1 scramble — retired in spirit, and refused by current servers' defaults."), .err)
                        }
                    }
                }
            }
            if caps & 0x0800 != 0 {
                doorSay(emit, L("mysqlprobe: TLS is among its capabilities — the road in can be sealed."))
            } else {
                doorSay(emit, L("mysqlprobe: no TLS capability in the greeting — logins here cross in the clear unless the client brings its own tunnel."), .err)
            }
            doorSay(emit, L("mysqlprobe: a database that introduces itself to the whole wire — version, terms and all — gives a hunter the exact map of which doors to try."))
        }
    }

    // MARK: pgprobe — will it seal the road?

    /// PostgreSQL's first question,
    /// asked two ways (libpq's sslmode
    /// dance): an SSLRequest, and a
    /// GSSENCRequest. The one-byte
    /// answers — S, N, E — grade
    /// whether encryption is on the
    /// table at all. No startup packet
    /// follows; no login is attempted.
    static func pgprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 5432) else {
                doorSay(emit, L("pgprobe: give host[:port] — pgprobe 192.168.1.10"), .err)
                return
            }
            func ask(_ code: UInt32) -> UInt8? {
                guard let fd = doorSocket(
                    ip: ip, port: port,
                    timeout: 4) else {
                    return nil
                }
                defer { close(fd) }
                var packet: [UInt8] = []
                packet += doorU32(8)
                packet += doorU32(code)
                guard doorSend(fd, packet)
                else { return nil }
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 3)
                guard let byte = doorRead(fd, 1),
                      byte.count == 1 else {
                    return nil
                }
                return byte[0]
            }
            guard let ssl = ask(80877103) else {
                doorSay(emit, String(format: L("pgprobe: nothing answers on the database door at %@."), host))
                return
            }
            switch ssl {
            case 0x53:
                doorSay(emit, String(format: L("pgprobe: %@ will speak TLS — the S came back. Whether it is demanded of logins, only a login would tell, and none was tried."), host), .sys)
            case 0x4E:
                doorSay(emit, String(format: L("pgprobe: %@ answered N — no TLS on this door at all. Every login and every row crosses in the clear."), host), .err)
            case 0x45:
                doorSay(emit, String(format: L("pgprobe: %@ answered E — it does not know the question, which dates it or shuts it."), host), .err)
            default:
                doorSay(emit, String(format: L("pgprobe: %@ answered a byte that is neither S, N nor E — not PostgreSQL's manners."), host))
                return
            }
            if let gss = ask(80877104) {
                switch gss {
                case 0x47:
                    doorSay(emit, L("pgprobe: GSS encryption is offered too (the G came back) — Kerberos country."))
                case 0x4E:
                    doorSay(emit, L("pgprobe: no GSS encryption (N) — TLS is the only sealed road here."))
                default:
                    break
                }
            }
            doorSay(emit, L("pgprobe: stopped before the startup packet — the encryption posture is what was read, nothing more."))
        }
    }

    // MARK: mssqlprobe — the prelogin census

    /// TDS opens with PRELOGIN (MS-TDS
    /// §2.2.6.5): a token table naming
    /// offsets into the message, where
    /// the server plants its version and
    /// its encryption word — OFF, ON,
    /// NOT_SUP, REQ. The probe reads
    /// that one exchange and stops; no
    /// LOGIN7 ever follows.
    static func mssqlprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 1433) else {
                doorSay(emit, L("mssqlprobe: give host[:port] — mssqlprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("mssqlprobe: nothing answers on the database door at %@."), host))
                return
            }
            defer { close(fd) }
            var body: [UInt8] = []
            body += [0x00, 0x00, 0x0B, 0x00, 0x06]
            body += [0x01, 0x00, 0x11, 0x00, 0x01]
            body += [0xFF]
            body += [0x0A, 0x00, 0x00, 0x00,
                     0x00, 0x00]
            body += [0x00]
            let total = 8 + body.count
            var packet: [UInt8] = []
            packet.append(0x12)
            packet.append(0x01)
            packet.append(UInt8(
                (total >> 8) & 0xFF))
            packet.append(UInt8(total & 0xFF))
            packet += [0x00, 0x00, 0x01, 0x00]
            packet += body
            guard doorSend(fd, packet) else {
                doorSay(emit, L("mssqlprobe: the prelogin never left."))
                return
            }
            let reply = doorAvailable(fd, seconds: 3, cap: 4096)
            guard reply.count >= 8 else {
                doorSay(emit, L("mssqlprobe: the door stayed silent — not TDS, or not awake."))
                return
            }
            guard reply[0] == 0x12 else {
                if reply[0] == 0x04 {
                    doorSay(emit, L("mssqlprobe: the answer was a TDS error, not a prelogin — the server talks, but not to this knock."), .out)
                } else {
                    doorSay(emit, L("mssqlprobe: whatever answered is not speaking TDS."))
                }
                return
            }
            let replyBody = [UInt8](reply[8...])
            func token(_ wanted: UInt8)
                -> [UInt8]? {
                var pos = 0
                while pos < replyBody.count {
                    let kind = replyBody[pos]
                    if kind == 0xFF {
                        return nil
                    }
                    guard pos + 5
                        <= replyBody.count
                    else { return nil }
                    let offset = Int(
                        replyBody[pos + 1]) << 8
                        | Int(replyBody[pos + 2])
                    let span = Int(
                        replyBody[pos + 3]) << 8
                        | Int(replyBody[pos + 4])
                    if kind == wanted {
                        guard offset + span
                            <= replyBody.count
                        else { return nil }
                        return [UInt8](
                            replyBody[
                                offset..<(offset
                                            + span)])
                    }
                    pos += 5
                }
                return nil
            }
            var facts: [String] = []
            if let version = token(0x00),
               version.count >= 4 {
                let build = Int(version[2]) << 8
                    | Int(version[3])
                facts.append(String(
                    format: L("version %lld.%lld.%lld"),
                    Int(version[0]),
                    Int(version[1]), build))
            }
            if let instance = token(0x02),
               !instance.isEmpty {
                let name = (String(
                    bytes: instance,
                    encoding: .utf8) ?? "")
                    .replacingOccurrences(
                        of: "\0", with: "")
                if !name.isEmpty {
                    facts.append(String(
                        format: L("instance '%@'"),
                        name))
                }
            }
            if !facts.isEmpty {
                doorSay(emit, String(format: L("mssqlprobe: %@ introduces itself — %@."), host, facts.joined(separator: ", ")), .sys)
            } else {
                doorSay(emit, String(format: L("mssqlprobe: %@ answered the prelogin but planted nothing to read."), host), .sys)
            }
            if let encryption = token(0x01),
               let word = encryption.first {
                switch word {
                case 0:
                    doorSay(emit, L("mssqlprobe: encryption word OFF — the server does not require TLS; the login road can run in the clear."), .err)
                case 1:
                    doorSay(emit, L("mssqlprobe: encryption word ON — the server will seal the session. Whether its papers verify is certprobe's question."), .ok)
                case 2:
                    doorSay(emit, L("mssqlprobe: encryption word NOT_SUP — this server cannot encrypt at all. Every login crosses bare."), .err)
                case 3:
                    doorSay(emit, L("mssqlprobe: encryption word REQ — required and supported; the clear road is refused."), .ok)
                default:
                    doorSay(emit, String(format: L("mssqlprobe: an encryption word outside the book (%lld)."), Int(word)))
                }
            }
            doorSay(emit, L("mssqlprobe: stopped at the prelogin — no login packet was built or sent."))
        }
    }

    // MARK: mongoprobe — the hello, unauthenticated

    /// MongoDB's hello is the one
    /// command the wire answers before
    /// any name is given (OP_MSG, opcode
    /// 2013, per the MongoDB wire
    /// protocol): wire-version range,
    /// size limits, read-only posture.
    /// The probe sends hello with the
    /// null credential — no user, no
    /// auth attempt — and reads the
    /// document that answers. No other
    /// command follows it.
    static func mongoprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 27017) else {
                doorSay(emit, L("mongoprobe: give host[:port] — mongoprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("mongoprobe: nothing answers on the database door at %@."), host))
                return
            }
            defer { close(fd) }
            var elements: [UInt8] = []
            elements.append(0x10)
            elements += doorBSONCString("hello")
            elements += doorBSONInt32(1)
            elements.append(0x02)
            elements += doorBSONCString("$db")
            elements += doorBSONInt32(6)
            elements += Array("admin".utf8)
            elements.append(0)
            let doc = doorBSONDoc(elements)
            var payload: [UInt8] = []
            payload += doorBSONInt32(0)
            payload.append(0)
            payload += doc
            var message: [UInt8] = []
            message += doorBSONInt32(
                Int32(16 + payload.count))
            message += doorBSONInt32(0x4E4A)
            message += doorBSONInt32(0)
            message += doorBSONInt32(2013)
            message += payload
            guard doorSend(fd, message) else {
                doorSay(emit, L("mongoprobe: the hello never left."))
                return
            }
            guard let head = doorRead(fd, 16),
                  head.count == 16 else {
                doorSay(emit, L("mongoprobe: the hello went unanswered — current servers speak OP_MSG; this one kept silent."))
                return
            }
            func int32LE(_ bytes: [UInt8],
                         _ at: Int) -> Int {
                Int(bytes[at])
                    | (Int(bytes[at + 1]) << 8)
                    | (Int(bytes[at + 2]) << 16)
                    | (Int(bytes[at + 3]) << 24)
            }
            let total = int32LE(head, 0)
            let opcode = int32LE(head, 12)
            guard total > 16, total < 1_000_000,
                  let rest = doorRead(
                    fd, total - 16) else {
                doorSay(emit, L("mongoprobe: the answer was cut short."))
                return
            }
            let wire = head + rest
            var docStart: Int? = nil
            if opcode == 2013 {
                var pos = 16
                guard wire.count > pos + 4
                else {
                    doorSay(emit, L("mongoprobe: the answer carried no body."))
                    return
                }
                pos += 4
                while pos < wire.count {
                    let kind = wire[pos]
                    pos += 1
                    if kind == 0 {
                        docStart = pos
                        break
                    } else if kind == 1 {
                        guard pos + 4
                            <= wire.count else {
                            break
                        }
                        let sectionSize =
                            int32LE(wire, pos)
                        guard sectionSize >= 4
                        else { break }
                        pos += sectionSize
                    } else {
                        break
                    }
                }
            } else if opcode == 2004 {
                if wire.count > 36 {
                    docStart = 36
                }
            }
            guard let start = docStart,
                  let reply = doorBSONParse(
                    wire, from: start) else {
                doorSay(emit, L("mongoprobe: the answer was not a document this probe could read."))
                return
            }
            if let ok = reply["ok"]
                as? Double, ok == 0 {
                let reason = reply["errmsg"]
                    as? String ?? ""
                doorSay(emit, String(format: L("mongoprobe: hello refused — %@. The door wants a name first after all."), reason), .ok)
                return
            }
            var facts: [String] = []
            if let maxWire = reply["maxWireVersion"] as? Int {
                facts.append(String(
                    format: L("wire version up to %lld"), maxWire))
            }
            if let minWire = reply["minWireVersion"] as? Int {
                facts.append(String(
                    format: L("down to %lld"), minWire))
            }
            if let readOnly = reply["readOnly"] as? Bool {
                facts.append(readOnly
                    ? L("read-only posture")
                    : L("a writer's posture"))
            }
            if let primary = (reply["isWritablePrimary"] as? Bool)
                ?? (reply["ismaster"] as? Bool) {
                facts.append(primary
                    ? L("the primary itself")
                    : L("a secondary"))
            }
            if let limit = reply["maxMessageSizeBytes"] as? Int {
                facts.append(String(
                    format: L("messages to %lld bytes"), limit))
            }
            doorSay(emit, String(format: L("mongoprobe: %@ answers hello to a stranger — %@."), host, facts.isEmpty ? L("the document held no census to read") : facts.joined(separator: ", ")), facts.isEmpty ? .out : .sys)
            doorSay(emit, L("mongoprobe: hello is the protocol's own introduction, answered by design before any name — the census is what it publishes: versions a hunter can match against every known hole."))
            doorSay(emit, L("mongoprobe: nothing followed the hello — no databases were listed, nothing was read."))
        }
    }
}

extension BlacksiteBench {

    // MARK: elasticprobe — the cluster's introduction

    /// One GET of the root document —
    /// the cluster's own introduction:
    /// name, version, build. When the
    /// security realm stands, the 401
    /// challenge is the census instead.
    /// Either way the answer is graded
    /// on what a stranger learns.
    static func elasticprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 9200) else {
                doorSay(emit, L("elasticprobe: give host[:port] — elasticprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("elasticprobe: nothing answered on the search door at %@."), host))
                return
            }
            if http.statusCode == 401 {
                let challenge = http.value(
                    forHTTPHeaderField: "WWW-Authenticate") ?? ""
                doorSay(emit, String(format: L("elasticprobe: the cluster demands a name first (%@) — its introductions are kept indoors."), challenge.isEmpty ? L("a bare 401") : challenge), .ok)
                return
            }
            guard http.statusCode == 200,
                  let dict = doorJSON(data) else {
                doorSay(emit, String(format: L("elasticprobe: the door answered %lld but not as a cluster — not Elasticsearch's manners."), http.statusCode), .out)
                return
            }
            let cluster = doorField(dict, "cluster_name") ?? "?"
            let node = doorField(dict, "name") ?? "?"
            var version = "?"
            if let v = dict["version"] as? [String: Any] {
                version = doorField(v, "number") ?? "?"
            }
            doorSay(emit, String(format: L("elasticprobe: cluster '%@', node '%@', version %@ — introduced to a complete stranger."), cluster, node, version), .sys)
            doorSay(emit, L("elasticprobe: an unauthenticated root means the whole REST door stands open the same way — indices, documents, and the delete verb behind them. Critical until a realm proves otherwise."), .err)
        }
    }

    // MARK: couchprobe — the welcome mat

    /// One GET of the root document —
    /// CouchDB's welcome mat, public by
    /// design: version, build hash, the
    /// feature list. The grade is
    /// honest about the shape: the mat
    /// is meant to be read; the
    /// databases behind it are the real
    /// door, and this knock never
    /// reaches for them.
    static func couchprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 5984) else {
                doorSay(emit, L("couchprobe: give host[:port] — couchprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("couchprobe: nothing answered on the document door at %@."), host))
                return
            }
            guard http.statusCode == 200,
                  let dict = doorJSON(data),
                  doorField(dict, "couchdb") == "Welcome" else {
                doorSay(emit, String(format: L("couchprobe: the door answered %lld but not with CouchDB's welcome."), http.statusCode), .out)
                return
            }
            let version = doorField(dict, "version") ?? "?"
            var features = ""
            if let list = dict["features"] as? [Any] {
                features = list.compactMap {
                    $0 as? String
                }.joined(separator: ", ")
            }
            doorSay(emit, String(format: L("couchprobe: %@ keeps CouchDB %@ by the door."), host, version), .sys)
            if !features.isEmpty {
                doorSay(emit, String(format: L("couchprobe: features it advertises: %@"), features))
            }
            doorSay(emit, L("couchprobe: the welcome is public by design — version and all. Whether the databases ask a name is the question that matters, and it stands behind a door this knock does not open."))
        }
    }

    // MARK: solrprobe — the admin door

    /// One GET of the system-info
    /// document under /solr/admin — the
    /// answer names Solr and Lucene
    /// versions, the mode, and (in
    /// cloud mode) the ensemble it
    /// answers to. A 401 means the
    /// admin realm stands; a 200 means
    /// it does not.
    static func solrprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 8983) else {
                doorSay(emit, L("solrprobe: give host[:port] — solrprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/solr/admin/info/system?wt=json") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("solrprobe: nothing answered on the search-admin door at %@."), host))
                return
            }
            if http.statusCode == 401
                || http.statusCode == 403 {
                let challenge = http.value(
                    forHTTPHeaderField: "WWW-Authenticate") ?? ""
                doorSay(emit, String(format: L("solrprobe: the admin door demands a name first (%lld%@) — the console is kept indoors."), http.statusCode, challenge.isEmpty ? "" : " — " + challenge), .ok)
                return
            }
            guard http.statusCode == 200,
                  let dict = doorJSON(data) else {
                doorSay(emit, String(format: L("solrprobe: the door answered %lld but not with a system document."), http.statusCode), .out)
                return
            }
            var solrVersion = "?"
            var luceneVersion = "?"
            if let lucene = dict["lucene"] as? [String: Any] {
                solrVersion = doorField(
                    lucene, "solr-spec-version")
                    ?? solrVersion
                luceneVersion = doorField(
                    lucene, "lucene-spec-version")
                    ?? luceneVersion
            }
            let mode = doorField(dict, "mode") ?? "?"
            doorSay(emit, String(format: L("solrprobe: Solr %@ on Lucene %@, mode %@ — the whole system document, handed to a stranger."), solrVersion, luceneVersion, mode), .sys)
            if let zk = doorField(dict, "zkHost") {
                doorSay(emit, String(format: L("solrprobe: it names its ensemble aloud: %@"), zk))
            }
            doorSay(emit, L("solrprobe: an open Solr admin is an open archive — cores can be read, and in careless houses, emptied. This door should ask a name."), .err)
        }
    }

    // MARK: etcdprobe — the store's version door

    /// One GET of /version — the one
    /// document etcd serves the world by
    /// design: its server and cluster
    /// versions. The grade stays honest:
    /// the version door is public on
    /// purpose; whether the store
    /// itself demands a name is a read
    /// this knock does not make.
    static func etcdprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 2379) else {
                doorSay(emit, L("etcdprobe: give host[:port] — etcdprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/version") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("etcdprobe: nothing answered on the store door at %@."), host))
                return
            }
            guard let dict = doorJSON(data) else {
                doorSay(emit, String(format: L("etcdprobe: the door answered %lld but not with a version document."), http.statusCode), .out)
                return
            }
            if let server = doorField(dict, "etcdserver") {
                let cluster = doorField(dict, "etcdcluster") ?? "?"
                doorSay(emit, String(format: L("etcdprobe: etcd server %@, cluster %@ — published to anyone who asks, by design."), server, cluster), .sys)
                doorSay(emit, L("etcdprobe: the version door is a window, not the vault: the store's own answer to 'do you demand a name' stands behind its gRPC door, unknocked here."))
            } else if let error = doorField(dict, "error") {
                doorSay(emit, String(format: L("etcdprobe: the store answered with an error (%@) — it talks, but keeps its papers closer."), error), .ok)
            } else {
                doorSay(emit, String(format: L("etcdprobe: the door answered %lld with a document that holds no version."), http.statusCode), .out)
            }
        }
    }

    // MARK: consulprobe — who leads, asked aloud

    /// One GET of /v1/status/leader —
    /// Consul's agent API answers it
    /// when no ACL stands, and the
    /// agent API is a control plane:
    /// services are registered there,
    /// the key-value store is read
    /// there. A 200 to a stranger is
    /// the finding; a 401 is the door
    /// being kept.
    static func consulprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 8500) else {
                doorSay(emit, L("consulprobe: give host[:port] — consulprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/v1/status/leader") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("consulprobe: nothing answered on the agent door at %@."), host))
                return
            }
            if http.statusCode == 401
                || http.statusCode == 403 {
                doorSay(emit, String(format: L("consulprobe: the agent demands a token first (%lld) — the control plane is kept indoors."), http.statusCode), .ok)
                return
            }
            guard http.statusCode == 200 else {
                doorSay(emit, String(format: L("consulprobe: the door answered %lld — not a leader, not a refusal this probe can grade."), http.statusCode), .out)
                return
            }
            var leader = String(
                data: data, encoding: .utf8)?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
                ?? ""
            if leader.hasPrefix("\"") {
                leader = String(
                    leader.dropFirst())
            }
            if leader.hasSuffix("\"") {
                leader = String(
                    leader.dropLast())
            }
            doorSay(emit, String(format: L("consulprobe: the raft is led from %@ — told to a stranger with no token at all."), leader.isEmpty ? L("an unnamed leader") : leader), .sys)
            doorSay(emit, L("consulprobe: Consul's agent API is a control plane — services, health, the key-value store, all behind this same welcome. Unauthenticated, it is an open window into the house's workings. Critical."), .err)
        }
    }

    // MARK: vaultprobe — is the vault sealed?

    /// One GET of /v1/sys/seal-status —
    /// the document Vault publishes by
    /// design, precisely so a stranger
    /// can ask: type, initialized,
    /// sealed, the threshold counts,
    /// the version. The census is the
    /// publication itself, and whether
    /// the vault stands sealed or open.
    static func vaultprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 8200) else {
                doorSay(emit, L("vaultprobe: give host[:port] — vaultprobe 192.168.1.10"), .err)
                return
            }
            var dict: [String: Any]? = nil
            var plainHTTP = false
            if let (status, _, body) = doorTLSGet(
                host: host, port: UInt16(clamping: port),
                path: "/v1/sys/seal-status"),
               (status == 200 || status == 503) {
                dict = doorJSON(Data(body))
            }
            if dict == nil,
               let url = URL(string: "http://\(host):\(port)/v1/sys/seal-status"),
               let (data, http) = doorGET(url),
               http.statusCode == 200
                || http.statusCode == 503 {
                dict = doorJSON(data)
                plainHTTP = dict != nil
            }
            guard let seal = dict else {
                doorSay(emit, String(format: L("vaultprobe: no seal-status answered at %@ on either the sealed or the plain road."), host))
                return
            }
            let sealed = seal["sealed"] as? Bool
            let initialized = seal["initialized"] as? Bool
            let version = doorField(seal, "version") ?? "?"
            let type = doorField(seal, "type") ?? "?"
            let cluster = doorField(seal, "cluster_name")
            doorSay(emit, String(format: L("vaultprobe: Vault %@ (%@) at %@ — %@, %@."), version, type, host, initialized == true ? L("initialized") : L("not initialized"), sealed == true ? L("SEALED") : L("UNSEALED")), .sys)
            if let cluster = cluster {
                doorSay(emit, String(format: L("vaultprobe: it names its cluster aloud: %@"), cluster))
            }
            if plainHTTP {
                doorSay(emit, L("vaultprobe: it answered on the PLAIN road — a development vault, or one whose TLS was never hung. Secrets should not live behind a clear door."), .err)
            }
            if sealed == true {
                doorSay(emit, L("vaultprobe: sealed — the vault is shut and its keys are scattered as they should be. The status door is public by design; this is the census, not a crack."), .ok)
            } else if sealed == false {
                doorSay(emit, L("vaultprobe: unsealed and working — which is a vault's ordinary day. What strangers should never learn is the version beside it, and they just did: an unsealed vault running old paper is a named target."))
            }
        }
    }
}

extension BlacksiteBench {

    // MARK: jenkinsprobe — the version in the letterhead

    /// One GET of the front page.
    /// Jenkins signs nearly every
    /// answer with an X-Jenkins header
    /// naming its exact version —
    /// published to strangers by
    /// default — and the page itself
    /// shows whether a login stands or
    /// the dashboard opens unnamed.
    static func jenkinsprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 8080) else {
                doorSay(emit, L("jenkinsprobe: give host[:port] — jenkinsprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("jenkinsprobe: nothing answered on the automation door at %@."), host))
                return
            }
            let version = http.value(
                forHTTPHeaderField: "X-Jenkins")
            guard http.statusCode == 200
                || http.statusCode == 403
                || version != nil else {
                doorSay(emit, String(format: L("jenkinsprobe: the door answered %lld with no Jenkins letterhead."), http.statusCode), .out)
                return
            }
            let body = String(
                data: data, encoding: .utf8) ?? ""
            if let version = version {
                doorSay(emit, String(format: L("jenkinsprobe: Jenkins %@ — signed in the letterhead of its answer to a stranger."), version), .sys)
                doorSay(emit, L("jenkinsprobe: a build server that publishes its exact version hands every hunter the index of its known holes."))
            } else {
                doorSay(emit, String(format: L("jenkinsprobe: something at %@ answers like Jenkins but signs nothing."), host), .sys)
            }
            if body.contains("j_username")
                || body.contains("Sign in") {
                doorSay(emit, L("jenkinsprobe: a login stands at the door — the dashboard is kept indoors."), .ok)
            } else if body.contains("Dashboard")
                && http.statusCode == 200 {
                doorSay(emit, L("jenkinsprobe: the dashboard itself opens to an unnamed guest — jobs, builds, and the script console's road all stand behind this welcome. Critical."), .err)
            } else {
                doorSay(emit, String(format: L("jenkinsprobe: the front page answered %lld without showing either a login or a dashboard this probe can swear to."), http.statusCode), .out)
            }
        }
    }

    // MARK: gitlabprobe — the version door's challenge

    /// One GET of /api/v4/version —
    /// GitLab's version document lives
    /// behind authentication, and the
    /// shape of its refusal is itself
    /// the census: a GitLab 401 proves
    /// the house and its manners; a 200
    /// means the version — and its
    /// index of known holes — is
    /// published to the world.
    static func gitlabprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 443) else {
                doorSay(emit, L("gitlabprobe: give host[:port] — gitlabprobe 192.168.1.10"), .err)
                return
            }
            var status = 0
            var body: [UInt8] = []
            var answered = false
            if port == 443 {
                if let (code, _, bytes) =
                    doorTLSGet(
                        host: host, port: 443,
                        path: "/api/v4/version") {
                    status = code
                    body = bytes
                    answered = true
                }
            } else if let url = URL(
                string: "http://\(host):\(port)/api/v4/version"),
                      let (data, http) =
                        doorGET(url) {
                status = http.statusCode
                body = [UInt8](data)
                answered = true
            }
            guard answered else {
                doorSay(emit, String(format: L("gitlabprobe: nothing answered on the forge door at %@."), host))
                return
            }
            let dict = doorJSON(Data(body))
            if status == 401 {
                doorSay(emit, String(format: L("gitlabprobe: GitLab stands at %@ and its version door demands a name first — the forge keeps its papers indoors."), host), .ok)
                return
            }
            if status == 200, let dict = dict,
               let version = doorField(
                dict, "version") {
                let revision = doorField(
                    dict, "revision") ?? "?"
                doorSay(emit, String(format: L("gitlabprobe: version %@ (revision %@) — published to a stranger at %@."), version, revision, host), .sys)
                doorSay(emit, L("gitlabprobe: a forge's exact version is the index to every hole ever found in it. This door should ask a name."), .err)
                return
            }
            doorSay(emit, String(format: L("gitlabprobe: the door answered %lld — neither the version nor GitLab's refusal this probe can grade."), status), .out)
        }
    }

    // MARK: registryprobe — the image vault's door

    /// One GET of /v2/ — the registry's
    /// threshold. A 200 with the
    /// distribution letterhead means
    /// the API greets strangers; a 401
    /// carries the token challenge —
    /// realm, service, scope — which is
    /// read and graded, never answered.
    static func registryprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 5000) else {
                doorSay(emit, L("registryprobe: give host[:port] — registryprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/v2/") else { return }
            guard let (data, http) = doorGET(url) else {
                doorSay(emit, String(format: L("registryprobe: nothing answered on the registry door at %@."), host))
                return
            }
            let letterhead = http.value(
                forHTTPHeaderField: "Docker-Distribution-Api-Version")
            if http.statusCode == 200 {
                doorSay(emit, String(format: L("registryprobe: the registry at %@ (%@) greets a stranger at its threshold."), host, letterhead ?? L("no letterhead")), .sys)
                doorSay(emit, L("registryprobe: registries that let strangers knock at /v2/ usually let them read the catalog and pull — every image in this house should be treated as published. If any holds a secret, it is already out."), .err)
                return
            }
            if http.statusCode == 401 {
                let challenge = http.value(
                    forHTTPHeaderField: "WWW-Authenticate") ?? ""
                doorSay(emit, String(format: L("registryprobe: a token stands at the door (%@)."), challenge.isEmpty ? L("a bare Bearer challenge") : challenge), .ok)
                doorSay(emit, L("registryprobe: the challenge names where tokens are minted — read, never answered: this probe carries no name to trade."))
                return
            }
            _ = data
            doorSay(emit, String(format: L("registryprobe: the door answered %lld — neither the threshold greeting nor the token challenge."), http.statusCode), .out)
        }
    }

    // MARK: k8sprobe — the orchestrator's papers

    /// One GET of /version on the API
    /// server's sealed road — the
    /// version document Kubernetes
    /// serves, and the challenge it
    /// serves instead when
    /// authentication stands. Only when
    /// /version answers anonymously
    /// does the probe also read /api,
    /// the published list of its API
    /// groups; a gated house is knocked
    /// on exactly once.
    static func k8sprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 6443) else {
                doorSay(emit, L("k8sprobe: give host[:port] — k8sprobe 192.168.1.10"), .err)
                return
            }
            guard let (status, _, body) =
                doorTLSGet(
                    host: host,
                    port: UInt16(clamping: port),
                    path: "/version") else {
                doorSay(emit, String(format: L("k8sprobe: nothing answered on the API door at %@ — no handshake, no papers."), host))
                return
            }
            if status == 401
                || status == 403 {
                var reason = ""
                if let dict = doorJSON(
                    Data(body)),
                   let message = doorField(
                    dict, "message") {
                    reason = message
                }
                doorSay(emit, String(format: L("k8sprobe: the API server demands a name first (%lld%@) — the orchestrator keeps its papers indoors."), status, reason.isEmpty ? "" : " — " + reason), .ok)
                return
            }
            guard status == 200,
                  let dict = doorJSON(Data(body)),
                  let gitVersion = doorField(
                    dict, "gitVersion") else {
                doorSay(emit, String(format: L("k8sprobe: the door answered %lld but not with a version document."), status), .out)
                return
            }
            let platform = doorField(
                dict, "platform") ?? ""
            doorSay(emit, String(format: L("k8sprobe: Kubernetes %@%@ — its version served to an unnamed knock."), gitVersion, platform.isEmpty ? "" : " (" + platform + ")"), .sys)
            if let (_, _, apiBody) = doorTLSGet(
                host: host,
                port: UInt16(clamping: port),
                path: "/api"),
               let api = doorJSON(Data(apiBody)),
               let versions = api["versions"]
                as? [Any] {
                doorSay(emit, String(format: L("k8sprobe: /api answers too — %lld core version(s) published: %@"), versions.count, versions.compactMap { $0 as? String }.joined(separator: ", ")))
            }
            doorSay(emit, L("k8sprobe: an API server that introduces itself to strangers hands out its exact vintage — the index of every hole its age carries. The version door is minor; that it answers unnamed at all is the grade."), .err)
        }
    }
}

extension BlacksiteBench {

    // MARK: kafkaprobe — the dialect table

    /// One ApiVersions request (Kafka
    /// protocol, api key 18, version 0)
    /// — the call brokers answer before
    /// any name is given, by design. The
    /// reply is the broker's whole
    /// dialect table: every verb it
    /// speaks and the versions of each,
    /// which dates it as surely as a
    /// version string.
    static func kafkaprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 9092) else {
                doorSay(emit, L("kafkaprobe: give host[:port] — kafkaprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("kafkaprobe: nothing answers on the broker door at %@."), host))
                return
            }
            defer { close(fd) }
            var body: [UInt8] = []
            body += [0x00, 0x12]
            body += [0x00, 0x00]
            body += doorU32(7)
            let clientID = Array("nightjar".utf8)
            body.append(UInt8(
                (clientID.count >> 8) & 0xFF))
            body.append(UInt8(
                clientID.count & 0xFF))
            body += clientID
            var frame = doorU32(
                UInt32(body.count))
            frame += body
            guard doorSend(fd, frame) else {
                doorSay(emit, L("kafkaprobe: the question never left."))
                return
            }
            guard let head = doorRead(fd, 4),
                  head.count == 4 else {
                doorSay(emit, L("kafkaprobe: the broker kept silent — SASL-first houses sometimes refuse even this question unnamed."))
                return
            }
            let total = Int(head[0]) << 24
                | (Int(head[1]) << 16)
                | (Int(head[2]) << 8)
                | Int(head[3])
            guard total > 6, total < 1_000_000,
                  let rest = doorRead(fd, total),
                  rest.count == total else {
                doorSay(emit, L("kafkaprobe: the answer was cut short."))
                return
            }
            func i16(_ bytes: [UInt8],
                     _ at: Int) -> Int {
                Int(bytes[at]) << 8
                    | Int(bytes[at + 1])
            }
            func i32(_ bytes: [UInt8],
                     _ at: Int) -> Int {
                Int(bytes[at]) << 24
                    | (Int(bytes[at + 1]) << 16)
                    | (Int(bytes[at + 2]) << 8)
                    | Int(bytes[at + 3])
            }
            let error = i16(rest, 4)
            guard error == 0 else {
                doorSay(emit, String(format: L("kafkaprobe: the broker refused the question (error %lld) — its dialect table is kept indoors."), error), .ok)
                return
            }
            let count = i32(rest, 6)
            guard count >= 0, count < 1000 else {
                doorSay(emit, L("kafkaprobe: the answer's table would not parse."))
                return
            }
            let names: [Int: String] = [
                0: "Produce", 1: "Fetch",
                2: "ListOffsets", 3: "Metadata",
                10: "FindCoordinator",
                11: "JoinGroup",
                18: "ApiVersions",
                19: "CreateTopics",
                20: "DeleteTopics",
                32: "DescribeConfigs",
                42: "DeleteGroups",
                50: "DescribeUserScram",
            ]
            var notable: [String] = []
            var pos = 10
            while pos + 6 <= rest.count {
                let key = i16(rest, pos)
                let maxVersion = i16(
                    rest, pos + 4)
                if let name = names[key] {
                    notable.append(String(
                        format: L("%@ to v%lld"),
                        name, maxVersion))
                }
                pos += 6
            }
            doorSay(emit, String(format: L("kafkaprobe: the broker at %@ publishes %lld verbs to a stranger."), host, count), .sys)
            if !notable.isEmpty {
                doorSay(emit, String(format: L("kafkaprobe: among them: %@"), notable.joined(separator: ", ")))
            }
            doorSay(emit, L("kafkaprobe: ApiVersions is answered before any name by design — but the table is a fingerprint: its newest verbs date the broker within a release or two."))
        }
    }

    // MARK: zkprobe — four letters, read

    /// The four-letter words the
    /// service itself whitelists: stat
    /// first — version, mode, node
    /// count, connections — and envi
    /// only when stat answered. These
    /// are the zookeeper's own public
    /// reads; a house that answers them
    /// publishes its topology.
    static func zkprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 2181) else {
                doorSay(emit, L("zkprobe: give host[:port] — zkprobe 192.168.1.10"), .err)
                return
            }
            func ask(_ word: String) -> String? {
                guard let fd = doorSocket(
                    ip: ip, port: port,
                    timeout: 4) else {
                    return nil
                }
                defer { close(fd) }
                guard doorSend(
                    fd, Array(word.utf8))
                else { return nil }
                let bytes = doorAvailable(
                    fd, seconds: 2.5,
                    cap: 16384)
                guard !bytes.isEmpty else {
                    return nil
                }
                return String(
                    bytes: bytes,
                    encoding: .utf8)
            }
            guard let stat = ask("stat") else {
                doorSay(emit, String(format: L("zkprobe: no four-letter answer at %@ — the words are not whitelisted here, or the service is silent."), host))
                return
            }
            var version = ""
            var mode = ""
            var nodes = ""
            var connections = ""
            for raw in stat.split(
                separator: "\n") {
                let line = raw
                    .trimmingCharacters(
                        in: .whitespaces)
                if line.hasPrefix(
                    "Zookeeper version:") {
                    version = String(
                        line.dropFirst(
                            "Zookeeper version:"
                                .count))
                        .trimmingCharacters(
                            in: .whitespaces)
                } else if line.hasPrefix(
                    "Mode:") {
                    mode = String(
                        line.dropFirst(
                            "Mode:".count))
                        .trimmingCharacters(
                            in: .whitespaces)
                } else if line.hasPrefix(
                    "Node count:") {
                    nodes = String(
                        line.dropFirst(
                            "Node count:"
                                .count))
                        .trimmingCharacters(
                            in: .whitespaces)
                } else if line.hasPrefix(
                    "Connections:") {
                    connections = String(
                        line.dropFirst(
                            "Connections:"
                                .count))
                        .trimmingCharacters(
                            in: .whitespaces)
                }
            }
            var facts: [String] = []
            if !version.isEmpty {
                facts.append(String(
                    format: L("version %@"),
                    version))
            }
            if !mode.isEmpty {
                facts.append(String(
                    format: L("mode %@"), mode))
            }
            if !nodes.isEmpty {
                facts.append(String(
                    format: L("%@ nodes in its tree"),
                    nodes))
            }
            if !connections.isEmpty {
                facts.append(String(
                    format: L("%@ connections standing"),
                    connections))
            }
            doorSay(emit, String(format: L("zkprobe: the zookeeper at %@ answers stat to a stranger — %@."), host, facts.isEmpty ? L("the answer held no census to read") : facts.joined(separator: ", ")), facts.isEmpty ? .out : .sys)
            if let envi = ask("envi") {
                var hostName = ""
                for raw in envi.split(
                    separator: "\n") {
                    let line = raw
                        .trimmingCharacters(
                            in: .whitespaces)
                    if line.hasPrefix(
                        "host.name=") {
                        hostName = String(
                            line.dropFirst(
                                "host.name="
                                    .count))
                    }
                }
                if !hostName.isEmpty {
                    doorSay(emit, String(format: L("zkprobe: envi answers too — it names its own host: %@"), hostName))
                } else {
                    doorSay(emit, L("zkprobe: envi answers too — the environment is as public as the census."))
                }
            }
            doorSay(emit, L("zkprobe: four letters are a small door with a wide view — topology, load, and clientele. Houses that mind being mapped turn the words off."), .err)
        }
    }

    // MARK: memcacheprobe — the ledger, read

    /// Two text reads the daemon
    /// answers in the clear: version,
    /// then stats — uptime, connections
    /// standing, items held, the auth
    /// counters when the build carries
    /// them. Classic memcached has no
    /// name to ask for; if this build
    /// demands one, its refusal is the
    /// grade.
    static func memcacheprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 11211) else {
                doorSay(emit, L("memcacheprobe: give host[:port] — memcacheprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("memcacheprobe: nothing answers on the cache door at %@."), host))
                return
            }
            defer { close(fd) }
            BlacksiteNet.setRecvTimeout(fd, seconds: 3)
            let talk = DoorTalk(fd: fd)
            talk.sendLine("version\r\n")
            guard let versionLine = talk
                .nextLine() else {
                doorSay(emit, L("memcacheprobe: the door answered with silence."))
                return
            }
            if versionLine.hasPrefix("ERROR")
                || versionLine.hasPrefix(
                    "CLIENT_ERROR") {
                doorSay(emit, String(format: L("memcacheprobe: it refuses plain speech (%@) — a name is demanded here, and none was offered."), versionLine), .ok)
                return
            }
            guard versionLine.hasPrefix(
                "VERSION") else {
                doorSay(emit, L("memcacheprobe: whatever answered is not speaking memcached."))
                return
            }
            doorSay(emit, String(format: L("memcacheprobe: %@ keeps memcached %@ by the door."), host, String(versionLine.dropFirst("VERSION ".count))), .sys)
            talk.sendLine("stats\r\n")
            let lines = talk.linesUntil("END")
            var stats: [String: String] = [:]
            for line in lines {
                guard line.hasPrefix("STAT ")
                else { continue }
                let rest = line.dropFirst(
                    "STAT ".count)
                if let space = rest.firstIndex(
                    of: " ") {
                    stats[String(
                        rest[..<space])] =
                        String(rest[
                            rest.index(
                                after: space)...])
                }
            }
            var facts: [String] = []
            if let uptime = stats["uptime"],
               let seconds = Int(uptime) {
                facts.append(String(
                    format: L("up %lld days"),
                    seconds / 86400))
            }
            if let items = stats["curr_items"] {
                facts.append(String(
                    format: L("%@ items held"),
                    items))
            }
            if let conns = stats[
                "curr_connections"] {
                facts.append(String(
                    format: L("%@ connections standing"),
                    conns))
            }
            if let bytes = stats["bytes"],
               let count = Int(bytes) {
                facts.append(String(
                    format: L("%lld bytes of other people's memory"),
                    count))
            }
            if !facts.isEmpty {
                doorSay(emit, String(format: L("memcacheprobe: its whole ledger, to a stranger: %@"), facts.joined(separator: ", ")), .err)
            }
            if stats["auth_cmds"] != nil {
                doorSay(emit, L("memcacheprobe: this build carries the SASL counters — a name CAN be demanded here, whether the house demands it is policy this read cannot see."))
            } else {
                doorSay(emit, L("memcacheprobe: classic memcached keeps no names at all — whoever can reach this door can read and write the cache. On any wire but a private one, that is the finding."), .err)
            }
        }
    }

    // MARK: rabbitprobe — the server's introduction

    /// AMQP opens with the server's own
    /// introduction (AMQP 0-9-1,
    /// connection.start): after the
    /// eight-byte protocol header, the
    /// server sends its dialect, its
    /// properties table, and the names
    /// of the mechanisms it will accept
    /// — before any name of ours is
    /// asked. The probe reads that frame
    /// and leaves; no start-ok, no
    /// credentials, ever. A target on
    /// the management door (15672) is
    /// read there instead: one GET of
    /// /api/overview and its challenge.
    static func rabbitprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 5672) else {
                doorSay(emit, L("rabbitprobe: give host[:port] — rabbitprobe 192.168.1.10"), .err)
                return
            }
            if port == 15672 {
                guard let url = URL(string: "http://\(host):\(port)/api/overview") else { return }
                guard let (data, http) = doorGET(url) else {
                    doorSay(emit, String(format: L("rabbitprobe: nothing answered on the management door at %@."), host))
                    return
                }
                if http.statusCode == 401 {
                    doorSay(emit, L("rabbitprobe: the management door demands a name first — the warren's console is kept indoors."), .ok)
                    return
                }
                if http.statusCode == 200,
                   let dict = doorJSON(data) {
                    let version = doorField(
                        dict, "rabbitmq_version")
                        ?? "?"
                    let cluster = doorField(
                        dict, "cluster_name")
                        ?? "?"
                    doorSay(emit, String(format: L("rabbitprobe: the management console answers a stranger — RabbitMQ %@, cluster '%@'."), version, cluster), .sys)
                    doorSay(emit, L("rabbitprobe: an open management API is the whole warren — queues, messages, users. Critical."), .err)
                    return
                }
                doorSay(emit, String(format: L("rabbitprobe: the management door answered %lld — neither the overview nor its refusal."), http.statusCode), .out)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("rabbitprobe: nothing answers on the broker door at %@."), host))
                return
            }
            defer { close(fd) }
            guard doorSend(fd, [0x41, 0x4D,
                                0x51, 0x50,
                                0x00, 0x00,
                                0x09, 0x01])
            else {
                doorSay(emit, L("rabbitprobe: the protocol header never left."))
                return
            }
            guard let first = doorRead(fd, 1),
                  first.count == 1 else {
                doorSay(emit, L("rabbitprobe: the broker kept silent."))
                return
            }
            if first[0] == 0x41 {
                guard let rest = doorRead(fd, 7),
                      rest.count == 7 else {
                    return
                }
                doorSay(emit, String(format: L("rabbitprobe: it handed back a protocol header instead — it speaks AMQP %lld-%lld-%lld, not 0-9-1, and wants the knock in its own dialect."), Int(rest[4]), Int(rest[5]), Int(rest[6])), .out)
                return
            }
            guard first[0] == 0x01 else {
                doorSay(emit, L("rabbitprobe: whatever answered is not opening an AMQP frame."))
                return
            }
            guard let frameHead = doorRead(fd, 6),
                  frameHead.count == 6 else {
                return
            }
            let size = Int(frameHead[2]) << 24
                | (Int(frameHead[3]) << 16)
                | (Int(frameHead[4]) << 8)
                | Int(frameHead[5])
            guard size > 4, size < 1_000_000,
                  let payload = doorRead(fd, size + 1),
                  payload.count >= 10 else {
                doorSay(emit, L("rabbitprobe: the introduction was cut short."))
                return
            }
            func u16(_ at: Int) -> Int {
                Int(payload[at]) << 8
                    | Int(payload[at + 1])
            }
            func u32(_ at: Int) -> Int {
                Int(payload[at]) << 24
                    | (Int(payload[at + 1]) << 16)
                    | (Int(payload[at + 2]) << 8)
                    | Int(payload[at + 3])
            }
            guard u16(0) == 10, u16(2) == 10
            else {
                doorSay(emit, L("rabbitprobe: the first frame was not connection.start — the introduction is in another dialect."))
                return
            }
            let major = Int(payload[4])
            let minor = Int(payload[5])
            var pos = 6
            guard pos + 4 <= payload.count
            else { return }
            let tableLength = u32(pos)
            pos += 4 + tableLength
            guard pos + 4 <= payload.count
            else { return }
            let mechLength = u32(pos)
            pos += 4
            guard mechLength >= 0,
                  pos + mechLength
                    <= payload.count else {
                return
            }
            let mechanisms = String(
                bytes: payload[pos..<(pos
                                        + mechLength)],
                encoding: .utf8) ?? ""
            doorSay(emit, String(format: L("rabbitprobe: the broker at %@ introduces itself — AMQP %lld-%lld, mechanisms on the table: %@."), host, major, minor, mechanisms.isEmpty ? L("none named") : mechanisms), .sys)
            if mechanisms.contains("PLAIN") {
                doorSay(emit, L("rabbitprobe: PLAIN stands among them — a name and word, sealed only by whatever road carries them. Whether the house demands TLS before it is the grade that matters, and it is set in policy this introduction does not publish."))
            }
            doorSay(emit, L("rabbitprobe: stopped at the introduction — no start-ok followed, and no name was ever offered."))
        }
    }
}

extension BlacksiteBench {

    // MARK: printerprobe — the printer introduces itself

    /// One IPP Get-Printer-Attributes
    /// (RFC 8011 operation 0x000B) over
    /// the printing door — the request
    /// printers answer for the whole
    /// wire: name, state, make and
    /// model, location, the queue's
    /// length. No job is submitted; the
    /// attributes are the protocol's
    /// own public census.
    static func printerprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, port) = doorSplit(target, 631) else {
                doorSay(emit, L("printerprobe: give host[:port] — printerprobe 192.168.1.10"), .err)
                return
            }
            guard let url = URL(string: "http://\(host):\(port)/ipp/print") else { return }
            var message: [UInt8] = []
            message += [0x01, 0x01]
            message += [0x00, 0x0B]
            message += [0x00, 0x00, 0x00, 0x01]
            message.append(0x01)
            func attribute(_ tag: UInt8,
                           _ name: String,
                           _ value: String) {
                let nameBytes = Array(
                    name.utf8)
                let valueBytes = Array(
                    value.utf8)
                message.append(tag)
                message.append(UInt8(
                    (nameBytes.count >> 8)
                        & 0xFF))
                message.append(UInt8(
                    nameBytes.count & 0xFF))
                message += nameBytes
                message.append(UInt8(
                    (valueBytes.count >> 8)
                        & 0xFF))
                message.append(UInt8(
                    valueBytes.count & 0xFF))
                message += valueBytes
            }
            attribute(0x47,
                      "attributes-charset",
                      "utf-8")
            attribute(0x48,
                      "attributes-natural-language",
                      "en")
            attribute(0x45, "printer-uri",
                      "ipp://\(host):\(port)/ipp/print")
            attribute(0x44,
                      "requested-attributes",
                      "all")
            message.append(0x03)
            guard let (data, http) = doorPOST(
                url,
                contentType: "application/ipp",
                body: message) else {
                doorSay(emit, String(format: L("printerprobe: nothing answered on the printing door at %@."), host))
                return
            }
            guard http.statusCode == 200 else {
                doorSay(emit, String(format: L("printerprobe: the printing door answered HTTP %lld — its IPP face may live at another path on this house."), http.statusCode), .out)
                return
            }
            let bytes = [UInt8](data)
            guard bytes.count >= 8 else {
                doorSay(emit, L("printerprobe: the answer was too short to be IPP."))
                return
            }
            let statusCode = Int(bytes[2]) << 8
                | Int(bytes[3])
            guard statusCode == 0 else {
                doorSay(emit, String(format: L("printerprobe: IPP itself refused the question (status %lld) — the attributes are kept closer here."), statusCode), .ok)
                return
            }
            var pos = 8
            var strings: [String: String] = [:]
            var ints: [String: Int] = [:]
            var lastName = ""
            func u16(_ at: Int) -> Int {
                Int(bytes[at]) << 8
                    | Int(bytes[at + 1])
            }
            while pos < bytes.count {
                let tag = bytes[pos]
                if tag == 0x03 { break }
                if tag < 0x10 {
                    pos += 1
                    lastName = ""
                    continue
                }
                guard pos + 3 <= bytes.count
                else { break }
                let nameLength = u16(pos + 1)
                guard pos + 3 + nameLength
                    <= bytes.count else {
                    break
                }
                let name = String(
                    bytes: bytes[(pos
                        + 3)..<(pos + 3
                                + nameLength)],
                    encoding: .utf8) ?? ""
                let valuePos = pos + 3
                    + nameLength
                guard valuePos + 2
                    <= bytes.count else {
                    break
                }
                let valueLength = u16(
                    valuePos)
                guard valuePos + 2
                    + valueLength
                    <= bytes.count else {
                    break
                }
                let value = [UInt8](
                    bytes[(valuePos
                        + 2)..<(valuePos + 2
                                + valueLength)])
                let attrName = nameLength > 0
                    ? name : lastName
                if nameLength > 0 {
                    lastName = name
                }
                if tag == 0x21
                    && value.count == 4 {
                    ints[attrName] = Int(
                        value[0]) << 24
                        | (Int(value[1]) << 16)
                        | (Int(value[2]) << 8)
                        | Int(value[3])
                } else if tag == 0x23
                    && value.count == 4 {
                    ints[attrName] = Int(
                        value[3])
                } else if tag >= 0x40 {
                    if let text = String(
                        bytes: value,
                        encoding: .utf8),
                       strings[attrName] == nil {
                        strings[attrName] = text
                    }
                }
                pos = valuePos + 2
                    + valueLength
            }
            let name = strings["printer-name"]
                ?? L("an unnamed printer")
            let model = strings[
                "printer-make-and-model"]
            let location = strings[
                "printer-location"]
            let stateNames: [Int: String] = [
                3: "idle", 4: "processing",
                5: "stopped",
            ]
            var facts: [String] = []
            if let model = model {
                facts.append(model)
            }
            if let state = ints[
                "printer-state"],
               let word = stateNames[state] {
                facts.append(word)
            }
            if let jobs = ints[
                "queued-job-count"] {
                facts.append(String(
                    format: L("%lld jobs queued"),
                    jobs))
            }
            doorSay(emit, String(format: L("printerprobe: '%@' at %@ introduces itself — %@."), name, host, facts.isEmpty ? L("it answered, but published nothing readable") : facts.joined(separator: ", ")), .sys)
            if let location = location,
               !location.isEmpty {
                doorSay(emit, String(format: L("printerprobe: it even says where it sits: %@"), location))
            }
            doorSay(emit, L("printerprobe: a printer's attributes are the wire's small talk — name, model, firmware's cousin, and where it sits. Harmless alone; with the queue's job names elsewhere, it is a map of the office's paper."))
        }
    }

    // MARK: rtspprobe — the camera's options

    /// One RTSP OPTIONS with CSeq — the
    /// streaming door's published
    /// manners: which verbs it speaks
    /// (DESCRIBE, SETUP, PLAY), and the
    /// Server letterhead that so often
    /// names the camera and its
    /// firmware. A 401's challenge is
    /// the census when a name stands.
    static func rtspprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 554) else {
                doorSay(emit, L("rtspprobe: give host[:port] — rtspprobe 192.168.1.10"), .err)
                return
            }
            guard let fd = doorSocket(ip: ip, port: port, timeout: 4) else {
                doorSay(emit, String(format: L("rtspprobe: nothing answers on the streaming door at %@."), host))
                return
            }
            defer { close(fd) }
            let request =
                "OPTIONS rtsp://\(host):\(port)/ RTSP/1.0\r\n"
                + "CSeq: 1\r\n"
                + "User-Agent: "
                + "\(BlacksiteNet.userAgent)\r\n"
                + "\r\n"
            guard doorSend(fd,
                           Array(request.utf8))
            else {
                doorSay(emit, L("rtspprobe: the question never left."))
                return
            }
            let bytes = doorAvailable(
                fd, seconds: 3, cap: 8192)
            guard let (status, headers, _) =
                doorParseHTTP(bytes) else {
                doorSay(emit, L("rtspprobe: the door stayed silent — not RTSP, or not awake."))
                return
            }
            if status == 401 {
                let challenge = headers[
                    "www-authenticate"] ?? ""
                doorSay(emit, String(format: L("rtspprobe: the stream demands a name first (%@) — the camera keeps its eye indoors."), challenge.isEmpty ? L("a bare 401") : challenge), .ok)
                return
            }
            if let server = headers["server"] {
                doorSay(emit, String(format: L("rtspprobe: %@ streams under the letterhead '%@'."), host, server), .sys)
            } else {
                doorSay(emit, String(format: L("rtspprobe: the streaming door at %@ answered OPTIONS with %lld and no letterhead."), host, status), .sys)
            }
            if let methods = headers["public"] {
                doorSay(emit, String(format: L("rtspprobe: verbs it publishes: %@"), methods))
                let upper = methods.uppercased()
                if upper.contains("DESCRIBE")
                    && upper.contains("SETUP") {
                    doorSay(emit, L("rtspprobe: DESCRIBE and SETUP stand open — whoever can ask politely can be shown the stream's shape, and usually the stream. Cameras should ask a name first."), .err)
                }
                if upper.contains("ANNOUNCE") {
                    doorSay(emit, L("rtspprobe: ANNOUNCE is published too — this door will also TAKE streams from strangers."))
                }
            }
        }
    }

    // MARK: sipprobe — the telephone's options

    /// One SIP OPTIONS — the telephone
    /// system's published manners: the
    /// Allow list is its whole vocabulary
    /// spoken aloud, and the Server
    /// letterhead so often names the
    /// PBX. UDP first, as the protocol
    /// prefers; TCP once when the wire
    /// stays silent. No call is placed:
    /// OPTIONS is the question a phone
    /// asks instead of ringing.
    static func sipprobe(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) = doorResolve(target, 5060) else {
                doorSay(emit, L("sipprobe: give host[:port] — sipprobe 192.168.1.10"), .err)
                return
            }
            let request =
                "OPTIONS sip:nightjar@\(host) SIP/2.0\r\n"
                + "Via: SIP/2.0/UDP 192.0.2.1:5060;rport;branch=z9hG4bK-njprobe\r\n"
                + "Max-Forwards: 70\r\n"
                + "From: <sip:probe@nightjar.invalid>;tag=njprobe\r\n"
                + "To: <sip:nightjar@\(host)>\r\n"
                + "Call-ID: njprobe@nightjar.invalid\r\n"
                + "CSeq: 1 OPTIONS\r\n"
                + "Accept: application/sdp\r\n"
                + "Content-Length: 0\r\n"
                + "\r\n"
            var reply: [UInt8]? = BlacksitePentest
                .udpExchange(
                    ip: ip, port: port,
                    payload: Array(
                        request.utf8),
                    window: 3.0)
            if reply == nil,
               let fd = doorSocket(
                ip: ip, port: port,
                timeout: 4) {
                defer { close(fd) }
                if doorSend(fd,
                            Array(request.utf8)) {
                    let bytes = doorAvailable(
                        fd, seconds: 3,
                        cap: 8192)
                    if !bytes.isEmpty {
                        reply = bytes
                    }
                }
            }
            guard let bytes = reply,
                  let (status, headers, _) =
                    doorParseHTTP(bytes)
            else {
                doorSay(emit, String(format: L("sipprobe: no telephone answers at %@ — silent on UDP and TCP alike."), host))
                return
            }
            var agent = headers["server"]
                ?? headers["user-agent"]
            if agent == nil {
                agent = L("no letterhead")
            }
            doorSay(emit, String(format: L("sipprobe: the telephone at %@ answered %lld under '%@'."), host, status, agent ?? ""), .sys)
            if status == 401
                || status == 407 {
                let challenge = headers[
                    "www-authenticate"]
                    ?? headers[
                        "proxy-authenticate"]
                    ?? ""
                doorSay(emit, String(format: L("sipprobe: it demands a name before business (%@) — the exchange keeps its doors indoors."), challenge.isEmpty ? L("a bare challenge") : challenge), .ok)
                return
            }
            if let allow = headers["allow"] {
                doorSay(emit, String(format: L("sipprobe: verbs it publishes: %@"), allow))
                if allow.uppercased()
                    .contains("INVITE")
                    && status == 200 {
                    doorSay(emit, L("sipprobe: INVITE stands in the list and OPTIONS was answered unnamed — a PBX that chats with strangers will often ring for them too, and carry calls at someone else's expense. The exchange should demand a name."), .err)
                }
            }
            if let supported = headers[
                "supported"] {
                doorSay(emit, String(format: L("sipprobe: extensions it owns to: %@"), supported))
            }
        }
    }

    // MARK: starttlscensus — the mail doors, graded

    /// The mail family's encryption
    /// census, door by door: SMTP on 25
    /// and 587, IMAP on 143, POP3 on
    /// 110 — or the one door named.
    /// Each is greeted, its capabilities
    /// read, and where STARTTLS is
    /// offered, the word is spoken and
    /// the answer read: agreement,
    /// refusal, or the demand that it
    /// come first. The TLS handshake
    /// itself is never begun from here,
    /// and no authentication of any
    /// kind is attempted on any door —
    /// the census ends exactly where
    /// names would begin.
    static func starttlscensus(target: String, emit: @escaping BlacksiteEmit, done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let words = target.split(
                separator: " ")
                .map(String.init)
            guard let first = words.first,
                  !first.isEmpty else {
                doorSay(emit, L("starttlscensus: give a host — starttlscensus 192.168.1.10"), .err)
                return
            }
            let hint = words.count > 1
                ? words[1].lowercased() : nil
            var host = first
            var explicitPort: Int? = nil
            if let colon = first.lastIndex(
                of: ":"),
               let p = Int(first[
                    first.index(
                        after: colon)...]),
               (1...65535).contains(p) {
                host = String(first[..<colon])
                explicitPort = p
            }
            guard let resolved = BlacksiteNet
                .resolve4(host) else {
                doorSay(emit, String(format: L("starttlscensus: %@ does not resolve."), host), .err)
                return
            }
            let ip = resolved.ip
            enum MailDoor {
                case smtp, imap, pop3
            }
            var doors: [(Int, MailDoor)] = []
            if let port = explicitPort {
                let kind: MailDoor
                switch (hint, port) {
                case ("imap", _):
                    kind = .imap
                case ("pop3", _):
                    kind = .pop3
                case ("smtp", _):
                    kind = .smtp
                case (_, 143):
                    kind = .imap
                case (_, 110):
                    kind = .pop3
                default:
                    kind = .smtp
                }
                doors = [(port, kind)]
            } else {
                switch hint {
                case "smtp":
                    doors = [(25, .smtp),
                             (587, .smtp)]
                case "imap":
                    doors = [(143, .imap)]
                case "pop3":
                    doors = [(110, .pop3)]
                default:
                    doors = [(25, .smtp),
                             (587, .smtp),
                             (143, .imap),
                             (110, .pop3)]
                }
            }
            var sealedDoors: [String] = []
            var bareDoors: [String] = []
            var answeredDoors = 0

            func smtpDoor(_ port: Int) {
                let label = String(
                    format: L("smtp %lld"),
                    port)
                guard let fd = doorSocket(
                    ip: ip,
                    port: UInt16(
                        clamping: port),
                    timeout: 4) else {
                    return
                }
                defer { close(fd) }
                answeredDoors += 1
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 3)
                let talk = DoorTalk(fd: fd)
                let greeting = talk.smtpReply()
                guard greeting.code == 220
                else {
                    if greeting.code != 0 {
                        doorSay(emit, String(format: L("starttlscensus: %@ answered %lld at the greeting — the door is shut or the house is full."), label, greeting.code), .out)
                    }
                    return
                }
                talk.sendLine(
                    "EHLO nightjar.probe\r\n")
                let ehlo = talk.smtpReply()
                let joined = ehlo.lines
                    .joined(separator: "\n")
                    .uppercased()
                if ehlo.code == 530
                    || joined.contains(
                        "STARTTLS FIRST")
                    || joined.contains(
                        "MUST ISSUE A STARTTLS") {
                    doorSay(emit, String(format: L("starttlscensus: %@ — TLS is DEMANDED before business of any kind. The sealed road is the only road."), label), .ok)
                    sealedDoors.append(label)
                    return
                }
                guard ehlo.code == 250 else {
                    doorSay(emit, String(format: L("starttlscensus: %@ refused the EHLO (%lld) — its capabilities stay unread."), label, ehlo.code), .out)
                    return
                }
                if !joined.contains("STARTTLS") {
                    doorSay(emit, String(format: L("starttlscensus: %@ — no STARTTLS offered. Whatever names and words this door hears, it hears in the clear."), label), .err)
                    bareDoors.append(label)
                    return
                }
                talk.sendLine("STARTTLS\r\n")
                let answer = talk.smtpReply()
                if answer.code == 220 {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STARTTLS offered and honored: the door agreed to rise. (Offered and agreed are what this census grades — the upgrade itself is untested here.)"), label), .ok)
                    sealedDoors.append(label)
                } else {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STARTTLS is advertised but the word was refused (%lld). A promise on the banner the door will not keep."), label, answer.code), .err)
                    bareDoors.append(label)
                }
            }

            func imapDoor(_ port: Int) {
                let label = String(
                    format: L("imap %lld"),
                    port)
                guard let fd = doorSocket(
                    ip: ip,
                    port: UInt16(
                        clamping: port),
                    timeout: 4) else {
                    return
                }
                defer { close(fd) }
                answeredDoors += 1
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 3)
                let talk = DoorTalk(fd: fd)
                guard let greeting = talk
                    .nextLine(),
                      greeting.hasPrefix("* OK")
                else {
                    doorSay(emit, String(format: L("starttlscensus: %@ did not greet as IMAP."), label), .out)
                    return
                }
                talk.sendLine(
                    "a1 CAPABILITY\r\n")
                let lines = talk.imapReply(
                    tag: "a1")
                let joined = lines.joined(
                    separator: "\n")
                    .uppercased()
                let loginDisabled = joined
                    .contains("LOGINDISABLED")
                if !joined.contains("STARTTLS") {
                    if loginDisabled {
                        doorSay(emit, String(format: L("starttlscensus: %@ — no STARTTLS, but plain logins are DISABLED in the clear: the sealed road is demanded another way."), label), .ok)
                        sealedDoors.append(label)
                    } else {
                        doorSay(emit, String(format: L("starttlscensus: %@ — no STARTTLS in its capabilities. Names and words here cross bare."), label), .err)
                        bareDoors.append(label)
                    }
                    return
                }
                talk.sendLine(
                    "a2 STARTTLS\r\n")
                let answer = talk.imapReply(
                    tag: "a2")
                let firstLine = answer.first
                    ?? ""
                if firstLine.hasPrefix(
                    "a2 OK") {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STARTTLS offered and honored: the door agreed to rise%@. (The upgrade itself is untested here.)"), label, loginDisabled ? L(", and plain logins were already refused in the clear") : ""), .ok)
                    sealedDoors.append(label)
                } else {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STARTTLS is advertised but refused in the act (%@)."), label, firstLine), .err)
                    bareDoors.append(label)
                }
            }

            func pop3Door(_ port: Int) {
                let label = String(
                    format: L("pop3 %lld"),
                    port)
                guard let fd = doorSocket(
                    ip: ip,
                    port: UInt16(
                        clamping: port),
                    timeout: 4) else {
                    return
                }
                defer { close(fd) }
                answeredDoors += 1
                BlacksiteNet.setRecvTimeout(
                    fd, seconds: 3)
                let talk = DoorTalk(fd: fd)
                guard let greeting = talk
                    .nextLine(),
                      greeting.hasPrefix("+OK")
                else {
                    doorSay(emit, String(format: L("starttlscensus: %@ did not greet as POP3."), label), .out)
                    return
                }
                talk.sendLine("CAPA\r\n")
                let lines = talk.linesUntil(
                    ".", limit: 60)
                let joined = lines.joined(
                    separator: "\n")
                    .uppercased()
                if !joined.contains("STLS") {
                    doorSay(emit, String(format: L("starttlscensus: %@ — no STLS in its capabilities. The word this door hears crosses bare."), label), .err)
                    bareDoors.append(label)
                    return
                }
                talk.sendLine("STLS\r\n")
                let answer = talk.nextLine()
                    ?? ""
                if answer.hasPrefix("+OK") {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STLS offered and honored: the door agreed to rise. (The upgrade itself is untested here.)"), label), .ok)
                    sealedDoors.append(label)
                } else {
                    doorSay(emit, String(format: L("starttlscensus: %@ — STLS is advertised but refused in the act (%@)."), label, answer), .err)
                    bareDoors.append(label)
                }
            }

            for (port, kind) in doors {
                switch kind {
                case .smtp:
                    smtpDoor(port)
                case .imap:
                    imapDoor(port)
                case .pop3:
                    pop3Door(port)
                }
            }
            guard answeredDoors > 0 else {
                doorSay(emit, String(format: L("starttlscensus: no mail door answers at %@ at all."), host))
                return
            }
            if !sealedDoors.isEmpty
                && bareDoors.isEmpty {
                doorSay(emit, String(format: L("starttlscensus: verdict — every mail door at %@ seals its road: %@."), host, sealedDoors.joined(separator: ", ")), .ok)
            } else if !bareDoors.isEmpty {
                doorSay(emit, String(format: L("starttlscensus: verdict — bare doors stand at %@: %@. On those doors the postman reads everything."), host, bareDoors.joined(separator: ", ")), .err)
            }
        }
    }

    // MARK: the switchboard

    /// Wave four's dispatch — the
    /// netCommand case in Blacksite
    /// hands the verb and its target
    /// here, the way wave three's verbs
    /// ride benchWeb.
    static func benchDoors(
        _ name: String, _ target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = { text, kind in
            if !stopped() { emit(text, kind) }
        }
        switch name {
        case "smbprobe":
            smbprobe(target: target, emit: live, done: done)
        case "nfsprobe":
            nfsprobe(target: target, emit: live, done: done)
        case "rpcprobe":
            rpcprobe(target: target, emit: live, done: done)
        case "mysqlprobe":
            mysqlprobe(target: target, emit: live, done: done)
        case "pgprobe":
            pgprobe(target: target, emit: live, done: done)
        case "mssqlprobe":
            mssqlprobe(target: target, emit: live, done: done)
        case "mongoprobe":
            mongoprobe(target: target, emit: live, done: done)
        case "elasticprobe":
            elasticprobe(target: target, emit: live, done: done)
        case "couchprobe":
            couchprobe(target: target, emit: live, done: done)
        case "solrprobe":
            solrprobe(target: target, emit: live, done: done)
        case "etcdprobe":
            etcdprobe(target: target, emit: live, done: done)
        case "consulprobe":
            consulprobe(target: target, emit: live, done: done)
        case "vaultprobe":
            vaultprobe(target: target, emit: live, done: done)
        case "jenkinsprobe":
            jenkinsprobe(target: target, emit: live, done: done)
        case "gitlabprobe":
            gitlabprobe(target: target, emit: live, done: done)
        case "registryprobe":
            registryprobe(target: target, emit: live, done: done)
        case "k8sprobe":
            k8sprobe(target: target, emit: live, done: done)
        case "kafkaprobe":
            kafkaprobe(target: target, emit: live, done: done)
        case "zkprobe":
            zkprobe(target: target, emit: live, done: done)
        case "memcacheprobe":
            memcacheprobe(target: target, emit: live, done: done)
        case "rabbitprobe":
            rabbitprobe(target: target, emit: live, done: done)
        case "printerprobe":
            printerprobe(target: target, emit: live, done: done)
        case "rtspprobe":
            rtspprobe(target: target, emit: live, done: done)
        case "sipprobe":
            sipprobe(target: target, emit: live, done: done)
        case "starttlscensus":
            starttlscensus(target: target, emit: live, done: done)
        default:
            done()
        }
    }
}
