import Foundation
import Security

/// Wave nine: the shield — the bench
/// turned homeward. Every prior wave
/// knocks on doors as a stranger; this
/// one points the same reads at the
/// operator's OWN gear and renders a
/// defender's ledger: what answers,
/// what it volunteers, what should not
/// face the wire at all. Nothing here
/// changes a setting on any device —
/// no SET, no config write, no
/// remediation performed. The bench
/// reports; the operator acts. A quiet
/// wire or an empty ledger is graded
/// as exactly that, never as "safe".
///
/// Incumbent audit (before a line was
/// written): `snmpaudit` (BlacksitePentest)
/// already grades an SNMP agent against
/// the NSA's six mitigations — snmposture
/// RIDES it whole and adds the owner's
/// framing plus the location/contact
/// overshare read; snmpaudit itself is
/// untouched and still stands alone.
/// `tlsgrade` grades one live door's TLS
/// versions; certwatch is a census of
/// expiry across a host's TLS doors —
/// a different question, standing beside
/// it. BackupShield (Journal.swift) is
/// the app's OWN store hygiene — it marks
/// this app's files out of device
/// backups; it reads no wire and is no
/// kin to backupprobe, which grades
/// backup DOORS on the operator's gear.
/// EmconStandard's audit scores this
/// phone's own emissions — the app
/// auditing itself, not a wire read of
/// a host — so it stands apart, and
/// NetCred is a credential vault for the
/// admin hand, not a read at all. The
/// anonymous posture set in anonprobe is
/// exactly the bench's sanctioned four —
/// SNMP 'public', FTP anonymous, MQTT
/// unnamed, LDAP anonymous bind — never
/// more, never a guessed credential.
///
/// Verification (before the Swift
/// existed, a Python mirror ran 52
/// checks green): the SMB1 and SMB2
/// negotiate frames built byte-exact
/// (the SMB2 body mirrors Wave 2's
/// shipped smbprobe appends) and their
/// replies parsed against fixtures; the
/// SSH service-request and 'none'
/// userauth packets framed and a
/// FAILURE name-list parsed; the LDAP
/// anonymous BindRequest bytes and its
/// result walk; the MQTT CONNECT and
/// CONNACK codes; the CoAP GET for
/// /.well-known/core and its codes; a
/// DNS renderer over a compression-
/// pointed fixture (TXT/A/AAAA/MX) plus
/// the CHAOS-class version.bind query;
/// the rsync greeting and module-list
/// walk; the UPnP SOAP envelope, the
/// mapping-entry fields and fault 713;
/// the RFB security-type walk; the
/// version-claim parser and the bounded
/// EOL/known-bad table's verdicts; the
/// watch-ledger key diff; the HTTP
/// header and Set-Cookie parse; and
/// the 28-byte Darwin sockaddr_in6
/// layout. Where a read rides a house
/// core (the TLS knock, the SNMP probe,
/// the NTP read, the KEV ledger, the
/// ONVIF cores), the core's own wave
/// carries its verification.

extension BlacksiteBench {

    // MARK: the wave-9 dispatch

    /// One case in netCommand routes
    /// the whole shield bench here;
    /// the verb name picks the hand.
    /// Every verb is a read of the
    /// operator's own gear, graded
    /// for its owner.
    static func benchShield(
        name: String, arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        switch name {
        case "shieldcensus":
            shieldcensus(target: arg,
                         emit: emit, done: done)
        case "mgmtprobe":
            mgmtprobe(target: arg,
                      emit: emit, done: done)
        case "anonprobe":
            anonprobe(target: arg,
                      emit: emit, done: done)
        case "certwatch":
            certwatch(target: arg,
                      emit: emit, done: done)
        case "smbposture":
            smbposture(target: arg,
                       emit: emit, done: done)
        case "sshposture":
            sshposture(target: arg,
                       emit: emit, done: done)
        case "snmposture":
            snmposture(target: arg,
                       emit: emit, done: done)
        case "backupprobe":
            backupprobe(target: arg,
                        emit: emit, done: done)
        case "upnpgrade":
            upnpgrade(target: arg,
                      emit: emit, done: done)
        case "dnsposture":
            dnsposture(target: arg,
                       emit: emit, done: done)
        case "mailposture":
            mailposture(target: arg,
                        emit: emit, done: done)
        case "patchprobe":
            patchprobe(target: arg,
                       emit: emit, done: done)
        case "kevcheck":
            kevcheck(target: arg,
                     emit: emit, done: done)
        case "iotposture":
            iotposture(target: arg,
                       emit: emit, done: done)
        case "guestprobe":
            guestprobe(target: arg,
                       emit: emit, done: done)
        case "timeprobe":
            timeprobe(target: arg,
                      emit: emit, done: done)
        case "v6posture":
            v6posture(target: arg,
                      emit: emit, done: done)
        case "headerposture":
            headerposture(target: arg,
                          emit: emit, done: done)
        case "cookieposture":
            cookieposture(target: arg,
                          emit: emit, done: done)
        case "dirposture":
            dirposture(target: arg,
                       emit: emit, done: done)
        case "metadataprobe":
            metadataprobe(emit: emit,
                          done: done)
        case "printposture":
            printposture(target: arg,
                         emit: emit, done: done)
        case "nasposture":
            nasposture(target: arg,
                       emit: emit, done: done)
        case "cameraposture":
            cameraposture(target: arg,
                          emit: emit, done: done)
        case "watchprobe":
            watchprobe(target: arg,
                       emit: emit, done: done)
        default:
            done()
        }
    }

    // MARK: shared plumbing

    /// A finding on the owner's
    /// ledger: a stable key (the diff
    /// currency of watchprobe), the
    /// line as printed, and its kind.
    struct ShieldFinding {
        var key: String
        var text: String
        var kind: BlacksiteShell.Line.Kind
    }

    /// Does a TCP door answer?
    static func shieldDoorOpen(
        ip: String, port: Int,
        timeout: Double = 1.4) -> Bool {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(clamping: port),
            timeout: timeout) else {
            return false
        }
        close(fd)
        return true
    }

    /// The first line a door speaks
    /// when it speaks first — SSH,
    /// FTP, SMTP greetings — trimmed
    /// and capped, or nil.
    static func shieldGreeting(
        ip: String, port: Int,
        cap: Int = 300) -> String? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(clamping: port),
            timeout: 3) else { return nil }
        defer { close(fd) }
        let bytes = icsAvailable(
            fd, seconds: 1.8, cap: cap)
        guard !bytes.isEmpty else {
            return nil }
        let text = String(
            bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes,
                      encoding: .ascii)
            ?? ""
        let first = text
            .split(separator: "\n",
                   omittingEmptySubsequences: false)
            .first.map { String($0) } ?? text
        let trimmed = first
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One plain-HTTP exchange over a
    /// raw socket — the answer whole:
    /// status line, headers in order
    /// (Set-Cookie lines survive as
    /// separate entries, which the
    /// session libraries will not
    /// promise), and the body bytes.
    struct ShieldHTTPReply {
        var statusLine: String
        var status: Int
        var headers: [(name: String,
                       value: String)]
        var body: [UInt8]

        func header(_ name: String)
            -> String? {
            let wanted = name.lowercased()
            for pair in headers
            where pair.name.lowercased()
                    == wanted {
                return pair.value
            }
            return nil
        }

        func cookies() -> [String] {
            headers.filter {
                $0.name.lowercased()
                    == "set-cookie"
            }.map { $0.value }
        }

        var bodyText: String {
            String(bytes: body,
                   encoding: .utf8)
                ?? String(bytes: body,
                          encoding: .ascii)
                ?? ""
        }
    }

    static func shieldHTTP(
        ip: String, host: String,
        port: Int, path: String,
        method: String = "GET",
        extraHeaders: [(String, String)] = [],
        body: [UInt8]? = nil,
        timeout: Double = 5)
        -> ShieldHTTPReply? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(clamping: port),
            timeout: timeout) else {
            return nil
        }
        defer { close(fd) }
        var request = "\(method) \(path)"
            + " HTTP/1.1\r\n"
            + "Host: \(host)\r\n"
            + "User-Agent: nightjar-shield\r\n"
            + "Accept: */*\r\n"
        for (name, value) in extraHeaders {
            request += "\(name): \(value)\r\n"
        }
        if let payloadBody = body {
            request += "Content-Length: "
                + "\(payloadBody.count)\r\n"
        }
        request += "Connection: close\r\n\r\n"
        var bytes = Array(request.utf8)
        if let payloadBody = body {
            bytes += payloadBody
        }
        guard icsSendAll(fd, bytes) else {
            return nil
        }
        let raw = icsAvailable(
            fd, seconds: timeout, cap: 131072)
        guard raw.count >= 12 else {
            return nil
        }
        // Split head from body at the
        // blank line.
        var splitAt: Int? = nil
        if raw.count >= 4 {
            for i in 0..<(raw.count - 3) {
                if raw[i] == 0x0D,
                   raw[i + 1] == 0x0A,
                   raw[i + 2] == 0x0D,
                   raw[i + 3] == 0x0A {
                    splitAt = i
                    break
                }
            }
        }
        guard let headEnd = splitAt else {
            return nil
        }
        let headText = String(
            bytes: Array(raw[0..<headEnd]),
            encoding: .utf8)
            ?? String(bytes: Array(
                        raw[0..<headEnd]),
                      encoding: .ascii)
            ?? ""
        let lines = headText.components(
            separatedBy: "\r\n")
        guard let statusLine = lines.first,
              !statusLine.isEmpty else {
            return nil
        }
        var status = 0
        let parts = statusLine.components(
            separatedBy: " ")
        if parts.count >= 2,
           let code = Int(parts[1]) {
            status = code
        }
        var headers: [(name: String,
                       value: String)] = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(
                of: ":") else { continue }
            let name = String(line[..<colon])
                .trimmingCharacters(
                    in: .whitespaces)
            let value = String(
                line[line.index(
                    after: colon)...])
                .trimmingCharacters(
                    in: .whitespaces)
            headers.append((name, value))
        }
        return ShieldHTTPReply(
            statusLine: statusLine,
            status: status,
            headers: headers,
            body: Array(raw[(headEnd + 4)...]))
    }

    /// One UDP question, one answer —
    /// through the house exchange.
    static func shieldUDP(
        ip: String, port: UInt16,
        payload: [UInt8],
        window: Double = 2.5) -> [UInt8]? {
        BlacksitePentest.udpExchange(
            ip: ip, port: port,
            payload: payload, window: window)
    }

    // MARK: SMB — the negotiate, read whole

    struct ShieldSMB {
        var answered = false
        /// nil: the SMB1 question
        /// itself went unanswered.
        var smb1Offered: Bool? = nil
        var smb1Dialect: String? = nil
        var dialect: String? = nil
        var signing = ""
        var encryptionCap = false
        var oldDialect = false
    }

    /// The SMB2 negotiate, appending
    /// exactly what Wave 2's shipped
    /// smbprobe appends (verified
    /// byte-for-byte in Python).
    static func shieldSMB2Frame() -> [UInt8] {
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
        return packet
    }

    /// The SMB1 negotiate (MS-CIFS):
    /// the retired dialect asked
    /// after by name — PC NETWORK
    /// PROGRAM 1.0 and NT LM 0.12.
    static func shieldSMB1Frame() -> [UInt8] {
        var packet: [UInt8] = []
        packet += [0xFF, 0x53, 0x4D, 0x42]
        packet.append(0x72)
        packet += [0x00, 0x00]
        packet += [0x00, 0x00]
        packet.append(0x18)
        packet += [0x53, 0xC8]
        packet += [0x00, 0x00]
        packet += [UInt8](repeating: 0,
                          count: 8)
        packet += [0x00, 0x00]
        packet += [0x00, 0x00]
        packet += [0x00, 0x00]
        packet += [0x00, 0x00]
        packet += [0x00, 0x00]
        packet.append(0x00)
        var body: [UInt8] = []
        for dialect in ["PC NETWORK PROGRAM 1.0",
                        "NT LM 0.12"] {
            body.append(0x02)
            body += Array(dialect.utf8)
            body.append(0x00)
        }
        packet.append(UInt8(
            body.count & 0xFF))
        packet.append(UInt8(
            (body.count >> 8) & 0xFF))
        packet += body
        return packet
    }

    /// Frame a payload in a NetBIOS
    /// session packet (type 0, the
    /// length on three bytes).
    static func shieldNBSS(
        _ payload: [UInt8]) -> [UInt8] {
        var framed: [UInt8] = [0x00]
        framed.append(UInt8(
            (payload.count >> 16) & 0xFF))
        framed.append(UInt8(
            (payload.count >> 8) & 0xFF))
        framed.append(UInt8(
            payload.count & 0xFF))
        framed += payload
        return framed
    }

    static func shieldSMBRead(
        ip: String, port: Int) -> ShieldSMB {
        var out = ShieldSMB()
        let dialectNames: [Int: String] = [
            0x0202: "SMB 2.0.2",
            0x0210: "SMB 2.1",
            0x0300: "SMB 3.0",
            0x0302: "SMB 3.0.2",
            0x0311: "SMB 3.1.1",
            0x02FF: "SMB2 wildcard",
        ]
        // The SMB2 question.
        if let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) {
            defer { close(fd) }
            if icsSendAll(fd, shieldNBSS(
                shieldSMB2Frame())) {
                let reply = icsAvailable(
                    fd, seconds: 3, cap: 2048)
                var base = 0
                if reply.count >= 5,
                   reply[0] == 0x00,
                   reply[4] == 0xFF
                    || reply[4] == 0xFE {
                    base = 4
                }
                if reply.count > base,
                   reply[base] == 0xFF {
                    out.answered = true
                    out.smb1Offered = true
                    out.smb1Dialect =
                        "SMB1 (the answer itself wore the old signature)"
                } else if reply.count
                            >= base + 104,
                          reply[base] == 0xFE {
                    func u16(_ at: Int) -> Int {
                        Int(reply[base + at])
                            | (Int(reply[
                                base + at + 1])
                                << 8)
                    }
                    func u32(_ at: Int) -> Int {
                        u16(at)
                            | (u16(at + 2) << 16)
                    }
                    if u32(8) == 0 {
                        out.answered = true
                        let securityMode = u16(66)
                        let dialect = u16(68)
                        let capabilities = u32(88)
                        out.dialect =
                            dialectNames[dialect]
                            ?? String(format: "dialect 0x%llx", Int64(dialect))
                        out.oldDialect =
                            dialect <= 0x0210
                        if securityMode & 0x0002
                            != 0 {
                            out.signing = "required"
                        } else if securityMode
                                    & 0x0001 != 0 {
                            out.signing =
                                "on but not required"
                        } else {
                            out.signing =
                                "not offered"
                        }
                        out.encryptionCap =
                            capabilities & 0x40
                                != 0
                    } else {
                        out.answered = true
                        out.signing = "refused"
                    }
                }
            }
        }
        // The SMB1 question, on its
        // own connection.
        if let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) {
            defer { close(fd) }
            if icsSendAll(fd, shieldNBSS(
                shieldSMB1Frame())) {
                let reply = icsAvailable(
                    fd, seconds: 3, cap: 2048)
                var base = 0
                if reply.count >= 5,
                   reply[0] == 0x00,
                   reply[4] == 0xFF {
                    base = 4
                }
                if reply.count >= base + 35,
                   reply[base] == 0xFF,
                   reply[base + 4] == 0x72,
                   reply[base + 32] == 17 {
                    let index = Int(reply[
                        base + 33])
                        | (Int(reply[
                            base + 34]) << 8)
                    out.answered = true
                    if index == 0xFFFF {
                        out.smb1Offered = false
                    } else {
                        out.smb1Offered = true
                        out.smb1Dialect =
                            index == 1
                            ? "NT LM 0.12"
                            : "PC NETWORK PROGRAM 1.0"
                    }
                }
            }
        }
        return out
    }

    // MARK: SSH — banner, lists, methods

    struct ShieldSSH {
        var banner: String? = nil
        var kex: [String] = []
        var hostKeys: [String] = []
        var ciphers: [String] = []
        var macs: [String] = []
        /// nil: the methods question
        /// itself went unanswered.
        var methods: [String]? = nil
        var noneAccepted = false
    }

    /// Frame one SSH packet (RFC
    /// 4253 §6): the length, the
    /// padding to a block of 8 with
    /// at least 4, the payload.
    static func shieldSSHPacket(
        _ payload: [UInt8]) -> [UInt8] {
        var pad = 8 - ((payload.count + 1) % 8)
        if pad < 4 { pad += 8 }
        let total = payload.count + pad + 1
        var packet: [UInt8] = []
        packet.append(UInt8(
            (total >> 24) & 0xFF))
        packet.append(UInt8(
            (total >> 16) & 0xFF))
        packet.append(UInt8(
            (total >> 8) & 0xFF))
        packet.append(UInt8(total & 0xFF))
        packet.append(UInt8(pad))
        packet += payload
        packet += [UInt8](repeating: 0,
                          count: pad)
        return packet
    }

    static func shieldSSHString(
        _ text: String) -> [UInt8] {
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.append(UInt8(
            (bytes.count >> 24) & 0xFF))
        out.append(UInt8(
            (bytes.count >> 16) & 0xFF))
        out.append(UInt8(
            (bytes.count >> 8) & 0xFF))
        out.append(UInt8(
            bytes.count & 0xFF))
        out += bytes
        return out
    }

    /// Read one SSH packet's payload,
    /// or nil.
    static func shieldSSHPayload(
        _ fd: Int32) -> [UInt8]? {
        guard let head = icsReadExact(
            fd, 4) else { return nil }
        let length = Int(head[0]) << 24
            | Int(head[1]) << 16
            | Int(head[2]) << 8
            | Int(head[3])
        guard length > 0,
              length <= 35000,
              let rest = icsReadExact(
                fd, length),
              !rest.isEmpty else {
            return nil
        }
        let pad = Int(rest[0])
        guard length - 1 - pad >= 0 else {
            return nil
        }
        return Array(rest[1..<(1
            + (length - 1 - pad))])
    }

    static func shieldSSHRead(
        ip: String, port: Int)
        -> ShieldSSH? {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 6) else { return nil }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 3)
        var out = ShieldSSH()
        out.banner = lockReadLine(
            fd: fd, cap: 512)?
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        // Our KEXINIT — the same
        // greeting Wave 8's census
        // offers: names only, nothing
        // agreed beyond the read.
        var cookie = [UInt8](
            repeating: 0, count: 16)
        _ = SecRandomCopyBytes(
            kSecRandomDefault, 16,
            &cookie)
        var mine: [UInt8] = [0x14]
        mine += cookie
        let lists: [[String]] = [
            ["curve25519-sha256",
             "curve25519-sha256@libssh.org",
             "ecdh-sha2-nistp256",
             "diffie-hellman-group14-sha256"],
            ["ssh-ed25519",
             "ecdsa-sha2-nistp256"],
            ["aes256-gcm@openssh.com",
             "aes128-gcm@openssh.com",
             "aes256-ctr", "aes128-ctr"],
            ["aes256-gcm@openssh.com",
             "aes128-gcm@openssh.com",
             "aes256-ctr", "aes128-ctr"],
            ["hmac-sha2-512",
             "hmac-sha2-256"],
            ["hmac-sha2-512",
             "hmac-sha2-256"],
            ["none"], ["none"],
        ]
        for list in lists {
            mine += shieldSSHString(
                list.joined(separator: ","))
        }
        mine += shieldSSHString("")
        mine += shieldSSHString("")
        mine.append(0)
        mine += [0, 0, 0, 0]
        guard icsSendAll(
            fd, shieldSSHPacket(mine))
        else { return out }
        // Their KEXINIT.
        var payload = shieldSSHPayload(fd)
        var hops = 0
        while payload != nil,
              payload?.first != 0x14,
              hops < 4 {
            payload = shieldSSHPayload(fd)
            hops += 1
        }
        guard let kex = payload,
              kex.first == 0x14 else {
            return out
        }
        var pos = 17
        var parsed: [[String]] = []
        for _ in 0..<10 {
            guard let raw =
                lockSSHReadString(
                    kex, &pos) else {
                return out
            }
            let text = String(
                bytes: raw, encoding: .ascii)
                ?? ""
            parsed.append(text.isEmpty
                ? []
                : text.components(
                    separatedBy: ","))
        }
        if parsed.count == 10 {
            out.kex = parsed[0]
            out.hostKeys = parsed[1]
            out.ciphers = parsed[2]
            out.macs = parsed[4]
        }
        // The methods question: ask
        // for the userauth service,
        // then present NO credential
        // under a probe name and read
        // the refusal's own list — the
        // protocol's method census. A
        // SUCCESS here means the door
        // opened with nothing at all;
        // no channel is ever requested.
        let service = shieldSSHPacket(
            [0x05] + shieldSSHString(
                "ssh-userauth"))
        guard icsSendAll(fd, service) else {
            return out
        }
        var reply = shieldSSHPayload(fd)
        hops = 0
        while reply != nil,
              reply?.first != 0x06,
              reply?.first != 0x01,
              hops < 4 {
            reply = shieldSSHPayload(fd)
            hops += 1
        }
        guard reply?.first == 0x06 else {
            return out
        }
        var auth: [UInt8] = [0x32]
        auth += shieldSSHString("posture")
        auth += shieldSSHString(
            "ssh-connection")
        auth += shieldSSHString("none")
        guard icsSendAll(
            fd, shieldSSHPacket(auth))
        else { return out }
        var verdict = shieldSSHPayload(fd)
        hops = 0
        while verdict != nil,
              verdict?.first != 0x33,
              verdict?.first != 0x34,
              hops < 4 {
            verdict = shieldSSHPayload(fd)
            hops += 1
        }
        if verdict?.first == 0x34 {
            out.noneAccepted = true
            out.methods = []
        } else if let failure = verdict,
                  failure.first == 0x33 {
            var at = 1
            if let raw = lockSSHReadString(
                failure, &at) {
                let text = String(
                    bytes: raw,
                    encoding: .ascii) ?? ""
                out.methods = text.isEmpty
                    ? []
                    : text.components(
                        separatedBy: ",")
            }
        }
        return out
    }

    // MARK: SNMP — the house probe, graded for the owner

    struct ShieldSNMP {
        var descr: String? = nil
        var v2c = false
        var v1 = false
        var privateReads = false
        var v3 = false
    }

    /// A probe answered if any bind
    /// carries a real value (the
    /// snmpAudit test, word for word).
    static func shieldSNMPAnswered(
        _ probe: (error: Int,
                  binds: [(oid: String,
                           tag: UInt8,
                           body: [UInt8])])?)
        -> Bool {
        guard let probe = probe else {
            return false
        }
        return probe.binds.contains {
            $0.tag != 0x05 && $0.tag != 0x80
                && $0.tag != 0x81
                && $0.tag != 0x82
        }
    }

    static func shieldSNMPRead(
        ip: String) -> ShieldSNMP {
        var out = ShieldSNMP()
        let sysDescr = [1, 3, 6, 1, 2, 1,
                        1, 1, 0]
        let v2 = BlacksitePentest.snmpProbe(
            ip: ip, version: 1,
            community: "public",
            oids: [sysDescr])
        let v1 = BlacksitePentest.snmpProbe(
            ip: ip, version: 0,
            community: "public",
            oids: [sysDescr])
        out.v2c = shieldSNMPAnswered(v2)
        out.v1 = shieldSNMPAnswered(v1)
        if out.v2c, let v2 = v2 {
            for bind in v2.binds
            where bind.tag == 0x04 {
                out.descr = BlacksitePentest
                    .snmpRender(bind.tag,
                                bind.body)
                break
            }
        } else if out.v1, let v1 = v1 {
            for bind in v1.binds
            where bind.tag == 0x04 {
                out.descr = BlacksitePentest
                    .snmpRender(bind.tag,
                                bind.body)
                break
            }
        }
        let priv = BlacksitePentest.snmpProbe(
            ip: ip, version: 1,
            community: "private",
            oids: [sysDescr])
        out.privateReads =
            shieldSNMPAnswered(priv)
        out.v3 = BlacksitePentest
            .snmpV3Discover(ip: ip) != nil
        return out
    }

    // MARK: TLS papers — the house knock

    /// The leaf certificate a door
    /// presents, parsed by Wave 8's
    /// house DER walk; nil when no
    /// TLS version answers.
    static func shieldCertRead(
        ip: String, host: String,
        port: Int) -> LockCert? {
        let knock = lockTLSKnock(
            ip: ip, port: port, host: host,
            minV: .tlsProtocol11,
            maxV: .tlsProtocol13,
            onlySuite: nil)
        guard knock.answered,
              let trust = knock.trust,
              SecTrustGetCertificateCount(
                trust) > 0,
              let leaf =
                SecTrustGetCertificateAtIndex(
                    trust, 0),
              let data =
                SecCertificateCopyData(
                    leaf) as Data?
        else { return nil }
        return lockCertParse([UInt8](data))
    }

    /// Whole days of validity left
    /// (negative once expired).
    static func shieldCertDays(
        _ cert: LockCert) -> Int? {
        guard let notAfter = cert.notAfter
        else { return nil }
        return Int(notAfter
            .timeIntervalSinceNow / 86400)
    }

    // MARK: version claims and the bounded table

    struct ShieldClaim {
        var source: String
        var text: String
    }

    /// What a host volunteers about
    /// its own versions: the SSH,
    /// FTP and SMTP greetings, the
    /// MySQL greeting's version
    /// string, the HTTP Server
    /// header, the SNMP description.
    /// Each leg knocks only if its
    /// door answers at all.
    static func shieldClaims(
        ip: String, host: String,
        includeSNMP: Bool = true)
        -> [ShieldClaim] {
        var claims: [ShieldClaim] = []
        if shieldDoorOpen(ip: ip, port: 22),
           let greeting = shieldGreeting(
            ip: ip, port: 22) {
            claims.append(ShieldClaim(
                source: L("SSH banner"),
                text: greeting))
        }
        if shieldDoorOpen(ip: ip, port: 21),
           let greeting = shieldGreeting(
            ip: ip, port: 21) {
            claims.append(ShieldClaim(
                source: L("FTP greeting"),
                text: greeting))
        }
        if shieldDoorOpen(ip: ip, port: 25),
           let greeting = shieldGreeting(
            ip: ip, port: 25) {
            claims.append(ShieldClaim(
                source: L("SMTP greeting"),
                text: greeting))
        }
        if shieldDoorOpen(ip: ip, port: 3306),
           let fd = icsSocket(
            ip: ip, port: 3306,
            timeout: 3) {
            let bytes = icsAvailable(
                fd, seconds: 1.8, cap: 128)
            close(fd)
            if bytes.count > 6,
               bytes[4] == 0x0A {
                var version: [UInt8] = []
                var at = 5
                while at < bytes.count,
                      bytes[at] != 0 {
                    version.append(bytes[at])
                    at += 1
                }
                if let text = String(
                    bytes: version,
                    encoding: .ascii),
                   !text.isEmpty {
                    claims.append(ShieldClaim(
                        source: L("MySQL greeting"),
                        text: "MySQL " + text))
                }
            }
        }
        for webPort in [80, 8080] {
            if shieldDoorOpen(
                ip: ip, port: webPort),
               let reply = shieldHTTP(
                ip: ip, host: host,
                port: webPort, path: "/"),
               let server = reply.header(
                "Server") {
                claims.append(ShieldClaim(
                    source: String(format: L("HTTP Server (%lld)"), Int64(webPort)),
                    text: server))
            }
        }
        if includeSNMP {
            let snmp = shieldSNMPRead(
                ip: ip)
            if let descr = snmp.descr {
                claims.append(ShieldClaim(
                    source: L("SNMP sysDescr"),
                    text: descr))
            }
        }
        return claims
    }

    /// The version digits standing
    /// right after a product token
    /// (one '/' or space may intervene)
    /// — the Python-verified walk.
    static func shieldVersionParse(
        _ claim: String, token: String)
        -> [Int]? {
        let hay = claim.lowercased()
        let needle = token.lowercased()
        guard let range = hay.range(
            of: needle) else { return nil }
        var rest = hay[range.upperBound...]
        if rest.hasPrefix("/")
            || rest.hasPrefix(" ") {
            rest = rest.dropFirst()
        }
        var parts: [Int] = []
        var current = ""
        var sawDigit = false
        for character in rest {
            if character.isNumber {
                current.append(character)
                sawDigit = true
            } else if character == ".",
                      sawDigit {
                parts.append(
                    Int(current) ?? 0)
                current = ""
                sawDigit = false
            } else {
                break
            }
        }
        if sawDigit {
            parts.append(Int(current) ?? 0)
        }
        return parts.isEmpty ? nil : parts
    }

    static func shieldVersionLess(
        _ a: [Int], _ b: [Int]) -> Bool {
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// The bounded table: only lines
    /// with published end-of-life
    /// dates, and two releases that
    /// were shipped backdoored. Built
    /// 2026-10; the staleness is the
    /// operator's to weigh — the verb
    /// that renders these says so.
    static func shieldEOLVerdicts(
        _ claim: String)
        -> [(level: String, text: String)] {
        var out: [(level: String,
                   text: String)] = []
        func versionText(_ parts: [Int])
            -> String {
            parts.map { String($0) }
                .joined(separator: ".")
        }
        if let v = shieldVersionParse(
            claim, token: "OpenSSL"),
           shieldVersionLess(v, [3, 0]) {
            out.append(("EOL", String(
                format: L("OpenSSL %@ — the 1.x line is end-of-life (1.1.1 support ended in September 2023); nothing patches it now"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "Apache"),
           v.count >= 2, v[0] == 2,
           v[1] == 0 || v[1] == 2 {
            out.append(("EOL", String(
                format: L("Apache %@ — the 2.0/2.2 lines are end-of-life (2.2 closed in 2017)"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "PHP"),
           shieldVersionLess(v, [8, 2]) {
            out.append(("EOL", String(
                format: L("PHP %@ — lines below 8.2 are end-of-life"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "MySQL"),
           !v.isEmpty, v[0] < 8 {
            out.append(("EOL", String(
                format: L("MySQL %@ — the 5.x line is end-of-life (5.7 closed in October 2023)"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "Microsoft-IIS"),
           shieldVersionLess(v, [10, 0]) {
            out.append(("EOL", String(
                format: L("Microsoft-IIS %@ — below 10 it rides a Windows Server that is itself out of support"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "BIND"),
           v.count >= 2, v[0] == 9,
           v[1] == 11 || v[1] == 16 {
            out.append(("EOL", String(
                format: L("BIND %@ — the 9.11 and 9.16 lines are end-of-life"),
                versionText(v))))
        }
        if let v = shieldVersionParse(
            claim, token: "vsftpd"),
           v == [2, 3, 4] {
            out.append(("KNOWN-BAD",
                L("vsftpd 2.3.4 — the backdoored release (CVE-2011-2523): this exact build was shipped with a door inside it")))
        }
        if let v = shieldVersionParse(
            claim, token: "ProFTPD"),
           v.count >= 3,
           Array(v[0..<3]) == [1, 3, 3] {
            out.append(("KNOWN-BAD",
                L("ProFTPD 1.3.3c — the backdoored release (CVE-2010-4221): this exact build was shipped with a door inside it")))
        }
        return out
    }

    /// Products the bench knows by
    /// name in a claim, for the KEV
    /// ledger match.
    static let shieldProductTokens = [
        "OpenSSH", "OpenSSL", "Apache",
        "nginx", "Microsoft-IIS", "PHP",
        "MySQL", "MariaDB", "PostgreSQL",
        "vsftpd", "ProFTPD", "BIND",
        "Exim", "Postfix", "Dovecot",
        "Samba", "CUPS", "lighttpd",
        "Tomcat", "Jetty", "WordPress",
        "Dropbear", "libssh", "OpenVPN",
    ]

    /// Wave 7's ledger, matched the
    /// Wave 7 way: a presented product
    /// standing in the federal catalog
    /// of vulnerabilities confirmed
    /// exploited in the wild.
    static func shieldKEVHits(
        claims: [ShieldClaim])
        -> [[String: Any]] {
        guard let entries = wireKEVLoad()
        else { return [] }
        var needles = Set<String>()
        for claim in claims {
            for token in shieldProductTokens
            where claim.text.lowercased()
                .contains(
                    token.lowercased()) {
                needles.insert(
                    token.lowercased())
            }
        }
        guard !needles.isEmpty else {
            return []
        }
        var hits: [[String: Any]] = []
        var seen = Set<String>()
        for entry in entries {
            let vendor = wireStr(
                entry["vendorProject"])?
                .lowercased() ?? ""
            let product = wireStr(
                entry["product"])?
                .lowercased() ?? ""
            for needle in needles {
                if vendor.contains(needle)
                    || product.contains(
                        needle) {
                    let cve = wireStr(
                        entry["cveID"]) ?? ""
                    if !seen.contains(cve) {
                        seen.insert(cve)
                        hits.append(entry)
                    }
                    break
                }
            }
        }
        return hits
    }

    // MARK: DNS — one question, the whole answer

    /// A DNS question with full flag
    /// control (the CHAOS class among
    /// them), through the house UDP
    /// exchange; the raw message back.
    static func shieldDNS(
        serverIP: String, name: String,
        type: UInt16, qclass: UInt16 = 1,
        dnssec: Bool = false,
        timeout: Double = 3.5) -> [UInt8]? {
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
             0x00, dnssec ? 0x01 : 0x00])
        packet.append(contentsOf:
            BlacksiteDNS.encodeName(name))
        packet.append(UInt8(type >> 8))
        packet.append(UInt8(type & 0xFF))
        packet.append(UInt8(
            (qclass >> 8) & 0xFF))
        packet.append(UInt8(qclass & 0xFF))
        if dnssec {
            packet.append(contentsOf:
                [0x00, 0x00, 0x29,
                 0x04, 0xD0,
                 0x00, 0x00, 0x80, 0x00,
                 0x00, 0x00])
        }
        return shieldUDP(
            ip: serverIP, port: 53,
            payload: packet, window: timeout)
    }

    /// A name in a message, walked
    /// through compression pointers
    /// (the Python-verified walk);
    /// the name and the offset just
    /// past it in the original stream.
    static func shieldDNSName(
        _ msg: [UInt8], _ at: Int)
        -> (String, Int) {
        var labels: [String] = []
        var pos = at
        var end = at
        var jumped = false
        var hops = 0
        while pos < msg.count, hops < 64 {
            hops += 1
            let length = Int(msg[pos])
            if length == 0 {
                if !jumped { end = pos + 1 }
                break
            }
            if length & 0xC0 == 0xC0 {
                guard pos + 1 < msg.count
                else { break }
                let pointer = (length & 0x3F)
                    << 8 | Int(msg[pos + 1])
                if !jumped { end = pos + 2 }
                pos = pointer
                jumped = true
                continue
            }
            guard pos + 1 + length
                    <= msg.count else {
                break
            }
            labels.append(String(
                bytes: Array(msg[
                    (pos + 1)..<(pos + 1
                        + length)]),
                encoding: .ascii) ?? "")
            pos += 1 + length
        }
        return (labels.joined(
                    separator: "."), end)
    }

    /// The answer section rendered:
    /// TXT concatenated, A and AAAA
    /// as addresses, MX as preference
    /// and exchange, the rest named
    /// by type alone.
    static func shieldDNSAnswers(
        _ msg: [UInt8])
        -> [(name: String, type: UInt16,
             text: String)] {
        guard msg.count >= 12 else {
            return []
        }
        let qd = Int(msg[4]) << 8
            | Int(msg[5])
        let an = Int(msg[6]) << 8
            | Int(msg[7])
        var offset = 12
        for _ in 0..<qd {
            let (_, next) = shieldDNSName(
                msg, offset)
            offset = next + 4
        }
        var out: [(name: String,
                   type: UInt16,
                   text: String)] = []
        for _ in 0..<an {
            let (name, after) =
                shieldDNSName(msg, offset)
            offset = after
            guard offset + 10 <= msg.count
            else { break }
            let type = UInt16(msg[offset])
                << 8 | UInt16(msg[offset + 1])
            let rdlen = Int(msg[offset + 8])
                << 8 | Int(msg[offset + 9])
            let rdataAt = offset + 10
            offset = rdataAt
            guard rdataAt + rdlen
                    <= msg.count else {
                break
            }
            let rdata = Array(
                msg[rdataAt..<(rdataAt
                    + rdlen)])
            offset = rdataAt + rdlen
            var text = ""
            switch type {
            case 16:
                var i = 0
                while i < rdata.count {
                    let len = Int(rdata[i])
                    let end = min(
                        i + 1 + len,
                        rdata.count)
                    text += String(
                        bytes: Array(
                            rdata[(i + 1)..<end]),
                        encoding: .utf8) ?? ""
                    i += 1 + len
                }
            case 1:
                if rdata.count == 4 {
                    text = rdata.map {
                        String($0)
                    }.joined(separator: ".")
                }
            case 28:
                if rdata.count == 16 {
                    var groups: [String] = []
                    for i in stride(
                        from: 0, to: 16,
                        by: 2) {
                        let value = Int(
                            rdata[i]) << 8
                            | Int(rdata[i + 1])
                        groups.append(
                            String(value,
                                   radix: 16))
                    }
                    text = groups.joined(
                        separator: ":")
                }
            case 15:
                if rdata.count >= 3 {
                    let pref = Int(rdata[0])
                        << 8 | Int(rdata[1])
                    let (exchange, _) =
                        shieldDNSName(
                            msg, rdataAt + 2)
                    text = "\(pref) \(exchange)"
                }
            case 5:
                let (target, _) =
                    shieldDNSName(
                        msg, rdataAt)
                text = target
            default:
                text = ""
            }
            out.append((name: name,
                        type: type,
                        text: text))
        }
        return out
    }

    /// The flags a defender reads:
    /// recursion available, the
    /// authenticated-data bit, rcode.
    static func shieldDNSFlags(
        _ msg: [UInt8])
        -> (ra: Bool, ad: Bool,
            rcode: Int) {
        guard msg.count >= 4 else {
            return (false, false, 0)
        }
        return (msg[3] & 0x80 != 0,
                msg[3] & 0x20 != 0,
                Int(msg[3] & 0x0F))
    }

    // MARK: the small legs

    /// MQTT: one CONNECT with no
    /// name and no secret (protocol
    /// 3.1.1); the CONNACK code back
    /// — 0 means the broker took an
    /// unnamed guest in. A polite
    /// DISCONNECT follows an accepted
    /// knock, and nothing is ever
    /// published or subscribed.
    static func shieldMQTTRead(
        ip: String, port: Int) -> Int? {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else { return nil }
        defer { close(fd) }
        var packet: [UInt8] = []
        var variable: [UInt8] = []
        variable += [0x00, 0x04]
        variable += Array("MQTT".utf8)
        variable += [0x04, 0x02, 0x00, 0x3C]
        let client = Array(
            "nightjar-posture".utf8)
        variable.append(UInt8(
            (client.count >> 8) & 0xFF))
        variable.append(UInt8(
            client.count & 0xFF))
        variable += client
        packet.append(0x10)
        packet.append(UInt8(
            variable.count))
        packet += variable
        guard icsSendAll(fd, packet) else {
            return nil
        }
        let reply = icsAvailable(
            fd, seconds: 2.5, cap: 64)
        guard reply.count >= 4,
              reply[0] == 0x20 else {
            return nil
        }
        let code = Int(reply[3])
        if code == 0 {
            _ = icsSendAll(fd, [0xE0, 0x00])
        }
        return code
    }

    /// LDAP: one anonymous
    /// BindRequest (empty name, empty
    /// simple password); the result
    /// code back — 0 means the
    /// directory let a nameless
    /// stranger bind.
    static func shieldLDAPAnon(
        ip: String, port: Int) -> Int? {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else { return nil }
        defer { close(fd) }
        let bind: [UInt8] = [
            0x30, 0x0C, 0x02, 0x01, 0x01,
            0x60, 0x07, 0x02, 0x01, 0x03,
            0x04, 0x00, 0x80, 0x00,
        ]
        guard icsSendAll(fd, bind) else {
            return nil
        }
        let reply = icsAvailable(
            fd, seconds: 2.5, cap: 256)
        guard reply.count >= 10 else {
            return nil
        }
        for i in 0..<(reply.count - 4) {
            if reply[i] == 0x61,
               reply[i + 2] == 0x0A,
               reply[i + 3] == 0x01 {
                return Int(reply[i + 4])
            }
        }
        return nil
    }

    /// FTP: the anonymous knock —
    /// USER anonymous, a guest
    /// password, and the door's
    /// verdict. Admitted or not,
    /// the session ends at QUIT:
    /// nothing is listed, nothing
    /// is fetched.
    static func shieldFTPAnon(
        ip: String, port: Int)
        -> (answered: Bool,
            admitted: Bool) {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else {
            return (false, false)
        }
        defer { close(fd) }
        func code() -> Int? {
            let bytes = icsAvailable(
                fd, seconds: 2, cap: 1024)
            guard bytes.count >= 3 else {
                return nil
            }
            let text = String(
                bytes: bytes[0..<3],
                encoding: .ascii) ?? ""
            return Int(text)
        }
        guard code() != nil else {
            return (false, false)
        }
        guard icsSendAll(
            fd, Array("USER anonymous\r\n"
                        .utf8)) else {
            return (true, false)
        }
        var reply = code()
        if reply == 331 {
            guard icsSendAll(
                fd, Array("PASS guest@\r\n"
                            .utf8)) else {
                return (true, false)
            }
            reply = code()
        }
        let admitted = reply == 230
        _ = icsSendAll(
            fd, Array("QUIT\r\n".utf8))
        return (true, admitted)
    }

    /// CoAP: one GET of the public
    /// resource directory
    /// (/.well-known/core, RFC 6690);
    /// the response code back —
    /// 2.05 means the directory was
    /// served to a tokenless stranger.
    static func shieldCoAPRead(
        ip: String) -> Int? {
        var packet: [UInt8] = [
            0x40, 0x01, 0xB0, 0x7A, 0xBA]
        packet += Array(".well-known".utf8)
        packet.append(0x04)
        packet += Array("core".utf8)
        guard let reply = shieldUDP(
            ip: ip, port: 5688,
            payload: packet, window: 2.5),
              reply.count >= 2,
              reply[0] & 0xC0 == 0x40
        else { return nil }
        return Int(reply[1])
    }

    /// RTSP: OPTIONS, then DESCRIBE
    /// of the root — the two answers
    /// a camera gives before any
    /// credential is discussed.
    static func shieldRTSPRead(
        ip: String, host: String,
        port: Int)
        -> (options: Int?,
            describe: Int?,
            authHeader: Bool) {
        func ask(_ method: String,
                 cseq: Int) -> (Int, Bool)? {
            var extra: [(String, String)] =
                []
            if method == "DESCRIBE" {
                extra.append(("Accept",
                              "application/sdp"))
            }
            guard let fd = icsSocket(
                ip: ip,
                port: UInt16(clamping: port),
                timeout: 4) else {
                return nil
            }
            defer { close(fd) }
            var request = "\(method) "
                + "rtsp://\(host):\(port)/"
                + " RTSP/1.0\r\n"
                + "CSeq: \(cseq)\r\n"
            for (name, value) in extra {
                request += "\(name): "
                    + "\(value)\r\n"
            }
            request += "\r\n"
            guard icsSendAll(
                fd, Array(request.utf8))
            else { return nil }
            let bytes = icsAvailable(
                fd, seconds: 2.5, cap: 8192)
            guard bytes.count >= 12 else {
                return nil
            }
            let text = String(
                bytes: bytes, encoding: .utf8)
                ?? String(bytes: bytes,
                          encoding: .ascii)
                ?? ""
            let firstLine = text
                .components(
                    separatedBy: "\r\n")
                .first ?? ""
            let parts = firstLine
                .components(
                    separatedBy: " ")
            var status: Int? = nil
            if parts.count >= 2 {
                status = Int(parts[1])
            }
            let auth = text.lowercased()
                .contains("www-authenticate")
            guard let code = status else {
                return nil
            }
            return (code, auth)
        }
        let options = ask("OPTIONS", cseq: 1)
        let describe = ask("DESCRIBE",
                           cseq: 2)
        return (options?.0, describe?.0,
                (options?.1 ?? false)
                    || (describe?.1 ?? false))
    }

    /// RFB (VNC): the version
    /// greeting, then the security
    /// types the door offers — type 1
    /// is None: no password at all.
    static func shieldRFBRead(
        ip: String, port: Int)
        -> [Int]? {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else { return nil }
        defer { close(fd) }
        guard let version = icsReadExact(
            fd, 12),
              version.count == 12,
              Array(version[0..<4])
                == Array("RFB ".utf8)
        else { return nil }
        guard icsSendAll(fd, version)
        else { return nil }
        guard let count = icsReadExact(
            fd, 1) else { return nil }
        if count[0] == 0 { return [] }
        guard let types = icsReadExact(
            fd, Int(count[0])) else {
            return nil
        }
        return types.map { Int($0) }
    }

    /// Rsync: the greeting and the
    /// module LIST — names only. A
    /// module's contents are never
    /// asked for; the list itself,
    /// served without a name, is the
    /// posture evidence.
    static func shieldRsyncRead(
        ip: String, port: Int)
        -> (greeting: String,
            modules: [String],
            authWall: Bool)? {
        guard let fd = icsSocket(
            ip: ip,
            port: UInt16(clamping: port),
            timeout: 4) else { return nil }
        defer { close(fd) }
        guard icsSendAll(
            fd, Array("@RSYNCD: 31.0\n"
                        .utf8)) else {
            return nil
        }
        let bytes = icsAvailable(
            fd, seconds: 2.5, cap: 8192)
        guard !bytes.isEmpty else {
            return nil
        }
        let text = String(
            bytes: bytes, encoding: .utf8)
            ?? ""
        var greeting: String? = nil
        var modules: [String] = []
        var authWall = false
        for rawLine in text.components(
            separatedBy: "\n") {
            let line = rawLine
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            if line.hasPrefix("@RSYNCD:") {
                let tag = String(
                    line.dropFirst(8))
                    .trimmingCharacters(
                        in: .whitespaces)
                if greeting == nil,
                   tag.first?.isNumber
                    == true {
                    greeting = tag
                } else if tag == "EXIT" {
                    break
                } else if tag.hasPrefix(
                    "AUTHREQD") {
                    authWall = true
                }
                continue
            }
            if line.hasPrefix("@ERROR:") {
                continue
            }
            if !line.isEmpty {
                let name = line.components(
                    separatedBy: "\t").first
                    ?? line
                modules.append(name
                    .components(
                        separatedBy: " ")
                    .first ?? name)
            }
        }
        guard let heard = greeting else {
            return nil
        }
        return (heard, modules, authWall)
    }

    // MARK: UPnP IGD — the gateway's own ledger

    /// One field out of an XML body,
    /// by literal tags (the Python-
    /// verified walk).
    static func shieldXMLField(
        _ body: String, _ tag: String)
        -> String? {
        let open = "<" + tag + ">"
        let close = "</" + tag + ">"
        guard let start = body.range(
            of: open),
              let end = body.range(
                of: close,
                range: start.upperBound ..<
                    body.endIndex)
        else { return nil }
        return String(body[
            start.upperBound..<end.lowerBound])
    }

    /// The SSDP shout for gateways,
    /// and every LOCATION that
    /// answers, through Wave 7's
    /// multicast collect.
    static func shieldIGDLocations()
        -> [String] {
        let query = "M-SEARCH * "
            + "HTTP/1.1\r\n"
            + "HOST: 239.255.255.250:"
            + "1900\r\n"
            + "MAN: \"ssdp:discover\""
            + "\r\nMX: 2\r\n"
            + "ST: urn:schemas-upnp-org:"
            + "device:InternetGateway"
            + "Device:1\r\n\r\n"
        let packets = wireCollect(
            destIP: "239.255.255.250",
            port: 1900,
            payload: Array(query.utf8),
            window: 3.0, maxPackets: 64)
        var locations: [String] = []
        for packet in packets {
            let text = String(
                bytes: packet.data,
                encoding: .utf8) ?? ""
            for line in text.components(
                separatedBy: "\r\n") {
                if line.lowercased()
                    .hasPrefix("location:") {
                    let value = String(
                        line.dropFirst(9))
                        .trimmingCharacters(
                            in: .whitespaces)
                    if !value.isEmpty,
                       !locations.contains(
                        value) {
                        locations.append(
                            value)
                    }
                }
            }
        }
        return locations
    }

    /// One web fetch through the
    /// house session (the UPnP
    /// description and the MTA-STS
    /// policy both ride it).
    static func shieldWebFetch(
        _ request: URLRequest)
        -> (Data, HTTPURLResponse?)? {
        let (session, _) = BlacksitePentest
            .webSession(follow: true)
        defer {
            session.invalidateAndCancel()
        }
        return BlacksitePentest.syncFetch(
            session, request)
    }

    // MARK: shieldcensus — the board

    /// The census core, shared by
    /// shieldcensus and watchprobe:
    /// prints the board and returns
    /// the findings (keyed, for the
    /// diff). One host, every
    /// defensive grade the shield
    /// renders, in one ledger.
    static func shieldCensusCore(
        host: String, ip: String,
        emit: @escaping BlacksiteEmit)
        -> [ShieldFinding] {
        var findings: [ShieldFinding] = []
        func find(_ key: String,
                  _ text: String,
                  _ kind:
                    BlacksiteShell.Line.Kind) {
            findings.append(ShieldFinding(
                key: key, text: text,
                kind: kind))
            icsSay(emit, text, kind)
        }
        icsSay(emit, String(format: L("%@ (%@) — the shield board"), host, ip), .sys)
        // The doors.
        let board: [(Int, String)] = [
            (22, "SSH"), (23, "Telnet"),
            (80, "HTTP"), (443, "HTTPS"),
            (445, "SMB"), (548, "AFP"),
            (631, "IPP"), (3306, "MySQL"),
            (5900, "VNC"), (8080, "HTTP-alt"),
            (8443, "HTTPS-alt"),
        ]
        var open = Set<Int>()
        var doorNames: [String] = []
        for (port, name) in board
        where shieldDoorOpen(
            ip: ip, port: port) {
            open.insert(port)
            doorNames.append("\(name) \(port)")
        }
        if open.isEmpty {
            icsSay(emit, L("doors: none of the board's doors answer — from here this host is dark"))
        } else {
            icsSay(emit, String(format: L("doors answering: %@"), doorNames.joined(separator: " · ")))
        }
        if open.contains(23) {
            find("door:23",
                 L("Telnet answers — a cleartext shell facing the wire; everything it carries can be read on the road"),
                 .err)
        }
        // The claims, and what the
        // bounded table says of them.
        // (The census reads SNMP once,
        // itself, below, and folds the
        // description in as a claim.)
        var claims = shieldClaims(
            ip: ip, host: host,
            includeSNMP: false)
        let snmp = shieldSNMPRead(ip: ip)
        if let descr = snmp.descr {
            claims.append(ShieldClaim(
                source: L("SNMP sysDescr"),
                text: descr))
        }
        for claim in claims {
            icsSay(emit, String(format: L("%@: %@"), claim.source, claim.text))
            for hit in shieldEOLVerdicts(
                claim.text) {
                find("eol:" + hit.level
                        + ":" + claim.source,
                     hit.text, .err)
            }
        }
        // SSH, compactly.
        if open.contains(22),
           let ssh = shieldSSHRead(
            ip: ip, port: 22) {
            if ssh.noneAccepted {
                find("ssh:none",
                     L("SSH opened with NO credential at all — anyone on the wire is already in"),
                     .err)
            } else if let methods =
                        ssh.methods {
                if methods.contains(
                    "password") {
                    find("ssh:password",
                         L("SSH offers password authentication — the door takes a guessable secret"),
                         .err)
                } else if !methods.isEmpty {
                    icsSay(emit, String(format: L("SSH methods: %@"), methods.joined(separator: ", ")), .ok)
                }
            }
            if !ssh.hostKeys.isEmpty,
               ssh.hostKeys.allSatisfy({
                   $0 == "ssh-rsa"
               }) {
                find("ssh:rsaonly",
                     L("SSH offers only SHA-1-era RSA host keys (ssh-rsa)"),
                     .err)
            }
        }
        // SMB, compactly.
        if open.contains(445) {
            let smb = shieldSMBRead(
                ip: ip, port: 445)
            if let dialect = smb.dialect {
                icsSay(emit, String(format: L("SMB: %@, signing %@"), dialect, smb.signing))
            }
            if smb.smb1Offered == true {
                find("smb:smb1",
                     L("SMB1 is offered — the retired dialect still holds a chair at the file door"),
                     .err)
            }
            if smb.signing
                == "on but not required" {
                find("smb:signing",
                     L("SMB signing is on but not required — the classic relay posture"),
                     .err)
            } else if smb.signing
                        == "not offered" {
                find("smb:nosigning",
                     L("SMB signing is not offered at all"),
                     .err)
            }
        }
        // The papers on the first TLS
        // door that answers.
        for tlsPort in [443, 8443]
        where open.contains(tlsPort) {
            if let cert = shieldCertRead(
                ip: ip, host: host,
                port: tlsPort) {
                if let days =
                    shieldCertDays(cert) {
                    if days < 0 {
                        find("tls:expired",
                             String(format: L("the certificate on %lld EXPIRED %lld days ago (%@)"), Int64(tlsPort), Int64(-days), cert.subjectLine),
                             .err)
                    } else if days <= 30 {
                        find("tls:expiring",
                             String(format: L("the certificate on %lld has %lld days left (%@)"), Int64(tlsPort), Int64(days), cert.subjectLine),
                             .err)
                    } else {
                        icsSay(emit, String(format: L("papers on %lld: %@ — %lld days left"), Int64(tlsPort), cert.subjectLine, Int64(days)))
                    }
                }
            }
            break
        }
        // SNMP, compactly (the read
        // taken above, with the claims).
        if snmp.v1 || snmp.v2c {
            find("snmp:legacy",
                 L("SNMP answers a cleartext community ('public') — the agent's papers are readable by the wire"),
                 .err)
        }
        if snmp.privateReads {
            find("snmp:private",
                 L("SNMP: the factory 'private' community also reads — the pair the device was born with is still live"),
                 .err)
        }
        if !snmp.v1, !snmp.v2c, snmp.v3 {
            icsSay(emit, L("SNMP: v3 only — no legacy community answers"), .ok)
        }
        // The clock.
        if let ntp = wireNTPRead(ip),
           let offset = ntp.offset {
            if abs(offset) >= 1.0 {
                find("ntp:drift",
                     String(format: L("the clock is off by %.2f s — logs and TLS feel drift first"), offset),
                     .err)
            } else {
                icsSay(emit, String(format: L("clock: %.3f s from true — tight"), offset), .ok)
            }
        }
        // The federal ledger over the
        // presented products.
        let kev = shieldKEVHits(
            claims: claims)
        if !kev.isEmpty {
            find("kev:match",
                 String(format: L("%lld presented product(s) stand in the CISA KEV ledger — confirmed exploited in the wild; kevcheck names them"), Int64(kev.count)),
                 .err)
        }
        return findings
    }

    static func shieldcensus(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 443) else {
                icsSay(emit, L("shieldcensus: give a host on your own wire — shieldcensus 192.168.1.1"), .err)
                return
            }
            let findings =
                shieldCensusCore(
                    host: resolved.host,
                    ip: resolved.ip,
                    emit: emit)
            if findings.isEmpty {
                icsSay(emit, L("grade: nothing on this board rose to a finding — that is this pass, from this vantage, and not a bill of health"), .ok)
            } else {
                icsSay(emit, String(format: L("grade: %lld finding(s) on this host — each is a line above, with the evidence that earned it"), Int64(findings.count)), .err)
            }
        }
    }

    // MARK: mgmtprobe — who holds the keys to the house

    static func mgmtprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 22) else {
                icsSay(emit, L("mgmtprobe: give a host on your own wire — mgmtprobe 192.168.1.1"), .err)
                return
            }
            let ip = resolved.ip
            icsSay(emit, String(format: L("mgmtprobe — %@ (%@): the management plane, door by door"), resolved.host, ip), .sys)
            let doors: [(port: Int,
                         name: String,
                         note: String,
                         loud: Bool)] = [
                (22, "SSH",
                 L("the one remote shell that should face a LAN — when keys, not passwords, rule it"),
                 false),
                (23, "Telnet",
                 L("a cleartext shell: the password and the session cross the wire readable by anyone on it"),
                 true),
                (80, "HTTP admin",
                 L("the panel speaks in the clear — its password does too"),
                 false),
                (443, "HTTPS admin",
                 L("the panel, encrypted — the expected face for admin work"),
                 false),
                (512, "exec (r-service)",
                 L("the r-services: trust-based shells from another age — no wire should still carry them"),
                 true),
                (513, "login (r-service)",
                 L("the r-services: trust-based shells from another age — no wire should still carry them"),
                 true),
                (514, "shell (r-service)",
                 L("the r-services: trust-based shells from another age — no wire should still carry them"),
                 true),
                (5900, "VNC",
                 L("the desktop itself, on the wire"),
                 false),
                (3389, "RDP",
                 L("the desktop, Microsoft's way — know that it faces the LAN"),
                 false),
                (8080, "HTTP admin (alt)",
                 L("a second web panel, in the clear"),
                 false),
                (8443, "HTTPS admin (alt)",
                 L("a second web panel, encrypted"),
                 false),
                (9090, "admin panel",
                 L("the Cockpit-shaped door — a full admin console when it is one"),
                 false),
                (10000, "Webmin",
                 L("a whole server's worth of admin behind one web door"),
                 false),
                (16992, "Intel AMT",
                 L("a second computer inside the first, answering on the wire whether the OS is up or not"),
                 true),
            ]
            var answered = 0
            var loud = 0
            for door in doors
            where shieldDoorOpen(
                ip: ip, port: door.port) {
                answered += 1
                if door.loud { loud += 1 }
                icsSay(emit, String(format: L("%lld %@ — %@"), Int64(door.port), door.name, door.note), door.loud ? .err : .out)
                if door.port == 22
                    || door.port == 23,
                   let greeting =
                    shieldGreeting(
                        ip: ip,
                        port: door.port) {
                    icsSay(emit, String(format: L("   it introduces itself as: %@"), greeting))
                }
                if door.port == 5900,
                   let types =
                    shieldRFBRead(
                        ip: ip, port: 5900) {
                    if types.contains(1) {
                        loud += 1
                        icsSay(emit, L("   and the desktop opens with NO password — security type 'none' is on its own list"), .err)
                    } else if !types.isEmpty {
                        icsSay(emit, String(format: L("   a password stands at the door (security types %@)"), types.map { String($0) }.joined(separator: ", ")), .ok)
                    }
                }
            }
            if answered == 0 {
                icsSay(emit, L("grade: no management door answers from here — the plane is dark to the wire, which is the posture to want"), .ok)
            } else {
                icsSay(emit, String(format: L("grade: %lld management door(s) answer on this host, %lld of them loudly — every one is a way to own the device, and each should be a door you chose"), Int64(answered), Int64(loud)), loud > 0 ? .err : .out)
            }
        }
    }

    // MARK: anonprobe — the sanctioned four

    static func anonprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 21) else {
                icsSay(emit, L("anonprobe: give a host on your own wire — anonprobe 192.168.1.1"), .err)
                return
            }
            let ip = resolved.ip
            icsSay(emit, String(format: L("anonprobe — %@ (%@): the four anonymous knocks, exactly once each"), resolved.host, ip), .sys)
            // SNMP 'public'.
            let sysDescr = [1, 3, 6, 1, 2, 1,
                            1, 1, 0]
            let pub = BlacksitePentest
                .snmpProbe(
                    ip: ip, version: 1,
                    community: "public",
                    oids: [sysDescr])
            if shieldSNMPAnswered(pub) {
                icsSay(emit, L("SNMP: 'public' reads this agent — its papers are open to anyone on the wire"), .err)
            } else {
                icsSay(emit, L("SNMP: the 'public' knock went unanswered"), .ok)
            }
            // FTP anonymous.
            if shieldDoorOpen(
                ip: ip, port: 21) {
                let ftp = shieldFTPAnon(
                    ip: ip, port: 21)
                if ftp.admitted {
                    icsSay(emit, L("FTP: anonymous is ADMITTED — the file door takes a nameless guest in (the session ended at QUIT; nothing was listed or fetched)"), .err)
                } else if ftp.answered {
                    icsSay(emit, L("FTP: anonymous was refused at the door"), .ok)
                } else {
                    icsSay(emit, L("FTP: the door answers TCP but speaks no greeting"))
                }
            } else {
                icsSay(emit, L("FTP: no file door answers"))
            }
            // MQTT unnamed.
            if shieldDoorOpen(
                ip: ip, port: 1883) {
                if let code =
                    shieldMQTTRead(
                        ip: ip, port: 1883) {
                    if code == 0 {
                        icsSay(emit, L("MQTT: the broker took an UNNAMED guest in (CONNACK 0) — its topics are open to the wire until it learns to ask a name"), .err)
                    } else {
                        icsSay(emit, String(format: L("MQTT: the broker demands better than a stranger (CONNACK %lld)"), Int64(code)), .ok)
                    }
                } else {
                    icsSay(emit, L("MQTT: the door answers TCP but speaks no MQTT"))
                }
            } else {
                icsSay(emit, L("MQTT: no broker answers"))
            }
            // LDAP anonymous bind.
            if shieldDoorOpen(
                ip: ip, port: 389) {
                if let code =
                    shieldLDAPAnon(
                        ip: ip, port: 389) {
                    if code == 0 {
                        icsSay(emit, L("LDAP: the directory bound a NAMELESS stranger (result 0) — its tree may be readable with no credential at all"), .err)
                    } else {
                        icsSay(emit, String(format: L("LDAP: the anonymous bind was refused (result %lld)"), Int64(code)), .ok)
                    }
                } else {
                    icsSay(emit, L("LDAP: the door answers TCP but speaks no LDAP"))
                }
            } else {
                icsSay(emit, L("LDAP: no directory answers"))
            }
            icsSay(emit, L("exactly these four, exactly once — the bench's conventional anonymous checks. No other door was tried, no credential was guessed."))
        }
    }

    // MARK: certwatch — the expiry ledger

    static func certwatch(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 443) else {
                icsSay(emit, L("certwatch: give a host on your own wire — certwatch 192.168.1.1"), .err)
                return
            }
            let ip = resolved.ip
            let host = resolved.host
            icsSay(emit, String(format: L("certwatch — %@ (%@): every TLS door's papers, by days left"), host, ip), .sys)
            let doors = [443, 8443, 465,
                         993, 995, 636, 9443]
            var read = 0
            var worst: (port: Int,
                        days: Int)? = nil
            for port in doors
            where shieldDoorOpen(
                ip: ip, port: port) {
                guard let cert =
                    shieldCertRead(
                        ip: ip, host: host,
                        port: port) else {
                    icsSay(emit, String(format: L("%lld: answers TCP but presents no TLS papers"), Int64(port)))
                    continue
                }
                read += 1
                let days = shieldCertDays(
                    cert)
                var line = String(format: L("%lld: %@ — issued by %@"), Int64(port), cert.subjectLine, cert.issuerLine)
                var kind: BlacksiteShell
                    .Line.Kind = .out
                if let days = days {
                    line += String(format: L(", %lld days left"), Int64(days))
                    if days < 0 {
                        kind = .err
                        line += L(" — EXPIRED")
                    } else if days <= 30 {
                        kind = .err
                    } else if days > 90 {
                        kind = .ok
                    }
                    if worst == nil
                        || days < worst!.days {
                        worst = (port, days)
                    }
                }
                icsSay(emit, line, kind)
            }
            if read == 0 {
                icsSay(emit, L("grade: no TLS papers were read on this host — no implicit-TLS door answered"))
            } else if let worst = worst {
                icsSay(emit, String(format: L("grade: %lld certificate(s) read; the first expiry is door %lld at %lld days — an expired certificate trains everyone who uses this gear to click through warnings"), Int64(read), Int64(worst.port), Int64(worst.days)), worst.days <= 30 ? .err : .out)
            }
            icsSay(emit, L("implicit-TLS doors only — the STARTTLS doors (25, 587, 143, 110) keep their papers behind a greeting, and starttlscensus reads those"))
        }
    }

    // MARK: smbposture

    static func smbposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 445) else {
                icsSay(emit, L("smbposture: give a host on your own wire — smbposture 192.168.1.10"), .err)
                return
            }
            let smb = shieldSMBRead(
                ip: resolved.ip,
                port: Int(resolved.port))
            guard smb.answered else {
                icsSay(emit, String(format: L("smbposture: nothing answers on the file door at %@."), resolved.host))
                return
            }
            icsSay(emit, String(format: L("smbposture — %@ (%@): the file door, graded for its owner"), resolved.host, resolved.ip), .sys)
            var findings = 0
            if let dialect = smb.dialect {
                icsSay(emit, String(format: L("it would speak %@ to a stranger"), dialect))
                if smb.signing == "required" {
                    icsSay(emit, L("signing is REQUIRED — a relay cannot wear this house's answers"), .ok)
                } else if smb.signing
                            == "on but not required" {
                    findings += 1
                    icsSay(emit, L("signing is on but NOT required — the classic relay posture: answers can be borrowed and worn elsewhere"), .err)
                } else if smb.signing
                            == "not offered" {
                    findings += 1
                    icsSay(emit, L("signing is not even offered — sessions here can be read and bent on the road"), .err)
                }
                if smb.encryptionCap {
                    icsSay(emit, L("it carries the encryption capability — SMB 3's sealed sessions are possible here"))
                }
                if smb.oldDialect {
                    findings += 1
                    icsSay(emit, L("the chosen dialect is old — the 2.x line predates SMB encryption entirely"), .err)
                }
            } else if smb.signing
                        == "refused" {
                icsSay(emit, L("the negotiate was refused — the door is shut to strangers"), .ok)
            }
            if smb.smb1Offered == true {
                findings += 1
                icsSay(emit, String(format: L("SMB1 is OFFERED — %@ answered the negotiate by name. The retired dialect is the one WannaCry rode; anything that still speaks it should be made to stop"), smb.smb1Dialect ?? "NT LM 0.12"), .err)
            } else if smb.smb1Offered == false {
                icsSay(emit, L("SMB1 was asked after by name and refused — the retired dialect holds no chair here"), .ok)
            } else if smb.dialect != nil {
                icsSay(emit, L("the SMB1 question itself went unanswered — no verdict on the old dialect follows"))
            }
            icsSay(emit, L("guest access itself is not tested: the bench reads the negotiate and stops — it offers no name and opens no session"))
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the file door's posture is the modern one")
                                    : String(format: L("%lld finding(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: sshposture

    static func sshposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 22) else {
                icsSay(emit, L("sshposture: give a host on your own wire — sshposture 192.168.1.10"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            let port = Int(resolved.port)
            guard let ssh = shieldSSHRead(
                ip: ip, port: port) else {
                icsSay(emit, String(format: L("sshposture: nothing answers on the SSH door at %@."), host))
                return
            }
            icsSay(emit, String(format: L("sshposture — %@ (%@): the shell door, graded for its owner"), host, ip), .sys)
            var findings = 0
            if let banner = ssh.banner {
                icsSay(emit, String(format: L("banner: %@"), banner))
            }
            if !ssh.hostKeys.isEmpty {
                icsSay(emit, String(format: L("host keys offered: %@"), ssh.hostKeys.joined(separator: ", ")))
                if ssh.hostKeys.allSatisfy({
                    $0 == "ssh-rsa"
                }) {
                    findings += 1
                    icsSay(emit, L("only SHA-1-era RSA host keys (ssh-rsa) — modern clients refuse those signatures outright"), .err)
                } else if ssh.hostKeys
                    .contains("ssh-rsa") {
                    icsSay(emit, L("ssh-rsa still stands on the list beside modern keys — the SHA-1 signature is offered to anyone who asks for it"))
                }
            }
            let modernKex = ssh.kex.contains {
                $0.contains("curve25519")
                    || $0.contains("ecdh-sha2")
                    || $0.contains(
                        "group14-sha256")
                    || $0.contains(
                        "group16-sha512")
                    || $0.contains(
                        "group18-sha512")
                    || $0.contains("sntrup")
            }
            if !ssh.kex.isEmpty, !modernKex {
                findings += 1
                icsSay(emit, String(format: L("key exchange is SHA-1-era only: %@"), ssh.kex.joined(separator: ", ")), .err)
            }
            let cbc = ssh.ciphers.filter {
                $0.contains("cbc")
                    || $0.contains("arcfour")
                    || $0.contains("blowfish")
                    || $0.contains("cast128")
            }
            if !cbc.isEmpty {
                icsSay(emit, String(format: L("the cipher list still carries CBC-era and retired entries: %@"), cbc.joined(separator: ", ")))
            }
            if ssh.noneAccepted {
                findings += 1
                icsSay(emit, L("the 'none' question was answered with SUCCESS — this door opens with NO credential at all. Anyone on the wire is already in. No channel was opened and nothing was touched, but the door itself is wide"), .err)
            } else if let methods =
                        ssh.methods {
                icsSay(emit, String(format: L("auth methods offered: %@"), methods.isEmpty ? L("(none named)") : methods.joined(separator: ", ")))
                if methods.contains(
                    "password") {
                    findings += 1
                    icsSay(emit, L("password authentication is offered — the door takes a guessable secret, and the wire is patient"), .err)
                }
                if methods.contains(
                    "keyboard-interactive") {
                    icsSay(emit, L("keyboard-interactive is offered — the challenge-response road, password-shaped underneath"))
                }
                if methods == ["publickey"] {
                    icsSay(emit, L("public keys only — the door takes no password at all"), .ok)
                }
            } else {
                icsSay(emit, L("the methods question went unanswered — the door refused the census itself"))
            }
            // The pin, by the full
            // house handshake.
            let client = SSHClient(
                host: host, port: port,
                user: "bench")
            client.timeout = 8
            do {
                try client.handshake()
            } catch {
                // The refusal is a road
                // too; the key census
                // above already spoke.
            }
            if !client.hostKeyBlob
                .isEmpty {
                if let known = CryptoSuite
                    .NetCred.knownKey(
                        host: host,
                        port: port) {
                    if client.hostKeyBlob
                        == known {
                        icsSay(emit, L("the presented host key MATCHES the copy pinned in the house book"), .ok)
                    } else {
                        findings += 1
                        icsSay(emit, L("the presented host key does NOT match the house pin — the door wears a different face than the one on record"), .err)
                    }
                } else {
                    icsSay(emit, L("no pin stands in the house book for this host — the key was read, not trusted, and nothing was saved"))
                }
            }
            client.disconnect()
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the shell door's posture is the modern one")
                                    : String(format: L("%lld finding(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: snmposture — the audit, owned

    static func snmposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let arg = target
            .trimmingCharacters(
                in: .whitespaces)
        guard !arg.isEmpty else {
            icsSay(emit, L("snmposture: give a host on your own wire — snmposture 192.168.1.1"), .err)
            done()
            return
        }
        var captured: [ICSLine] = []
        let capture: BlacksiteEmit = {
            text, kind in
            captured.append((text: text,
                             kind: kind))
        }
        BlacksitePentest.snmpAudit(
            host: arg, emit: capture,
            done: {
                BlacksitePentest.run {
                    defer { done() }
                    icsSay(emit, String(format: L("snmposture — %@: the NSA's six mitigations, read as the owner of the gear"), arg), .sys)
                    icsPrint(emit, captured)
                    // What it volunteers
                    // beyond the audit's
                    // six: where it lives
                    // and who to call —
                    // the classic
                    // overshare.
                    if let resolved =
                        icsResolve(arg, 161) {
                        let extra =
                            BlacksitePentest
                            .snmpProbe(
                                ip: resolved.ip,
                                version: 1,
                                community:
                                    "public",
                                oids: [
                                    [1, 3, 6, 1,
                                     2, 1, 1,
                                     6, 0],
                                    [1, 3, 6, 1,
                                     2, 1, 1,
                                     4, 0],
                                ])
                        if shieldSNMPAnswered(
                            extra),
                           let extra = extra {
                            for bind in
                                extra.binds
                            where bind.tag
                                    == 0x04 {
                                let label =
                                    bind.oid
                                    == "1.3.6.1.2.1.1.6.0"
                                    ? L("location")
                                    : L("contact")
                                icsSay(emit, String(format: L("it also volunteers its %@: %@"), label, BlacksitePentest.snmpRender(bind.tag, bind.body)))
                            }
                        }
                    }
                    let loud = captured
                        .contains {
                            $0.text.contains(
                                "'private' reads")
                        }
                    if loud {
                        icsSay(emit, L("owner's grade: the write-shaped factory community answers on YOUR gear — of everything the audit read, that is the line to close first"), .err)
                    } else {
                        icsSay(emit, L("owner's grade: the audit above is the whole of it — each mitigation stands as read"))
                    }
                }
            })
    }

    // MARK: backupprobe — what guards the copies

    static func backupprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 548) else {
                icsSay(emit, L("backupprobe: give a host on your own wire — backupprobe 192.168.1.10"), .err)
                return
            }
            let ip = resolved.ip
            icsSay(emit, String(format: L("backupprobe — %@ (%@): the doors your backups ride, and what guards them"), resolved.host, ip), .sys)
            var answered = 0
            if shieldDoorOpen(
                ip: ip, port: 548) {
                answered += 1
                icsSay(emit, L("AFP answers (548) — Time Machine and the classic shares ride it. Whether it demands a password is not probed: the bench does not offer one"))
            }
            if shieldDoorOpen(
                ip: ip, port: 445) {
                icsSay(emit, L("SMB answers (445) — modern Time Machine rides SMB too; smbposture grades that door whole"))
            }
            if shieldDoorOpen(
                ip: ip, port: 873) {
                answered += 1
                if let rsync =
                    shieldRsyncRead(
                        ip: ip, port: 873) {
                    icsSay(emit, String(format: L("rsync answers (873), protocol %@"), rsync.greeting))
                    if rsync.authWall {
                        icsSay(emit, L("   its module list stands behind a name (AUTHREQD) — the map is not public"), .ok)
                    } else if !rsync.modules
                        .isEmpty {
                        icsSay(emit, String(format: L("   and its module list is served to a stranger: %@ — a map of what there is to take. Contents were not listed, and no module was entered"), rsync.modules.joined(separator: ", ")), .err)
                    } else {
                        icsSay(emit, L("   it greeted and listed nothing"))
                    }
                } else {
                    icsSay(emit, L("rsync answers TCP (873) but speaks no rsync greeting"))
                }
            }
            if shieldDoorOpen(
                ip: ip, port: 5009) {
                answered += 1
                icsSay(emit, L("the AirPort/Time Capsule admin door answers (5009) — the capsule keeps its own keys"))
            }
            if answered == 0 {
                icsSay(emit, L("grade: no backup door answers on this host — the copies, wherever they live, do not ride these roads"), .ok)
            } else {
                icsSay(emit, L("grade: backup CONTENTS were never read and never will be from this bench — the doors and their guards are the whole report"))
            }
        }
    }

    // MARK: upnpgrade — the gateway's standing forwards

    static func upnpgrade(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("upnpgrade — your gateway's UPnP forwarding ledger, read as its owner"), .sys)
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            var location: String? = nil
            if arg.hasPrefix("http") {
                location = arg
            } else {
                location =
                    shieldIGDLocations()
                    .first
            }
            guard let descURL = location,
                  let url = URL(
                    string: descURL) else {
                icsSay(emit, L("no InternetGatewayDevice answered the SSDP shout — UPnP may be off on the gateway (the posture to want), or it does not speak the protocol"), .ok)
                return
            }
            icsSay(emit, String(format: L("the gateway describes itself at %@"), descURL))
            var request = URLRequest(
                url: url)
            request.timeoutInterval = 8
            guard let (data, _) =
                    shieldWebFetch(request),
                  let desc = String(
                    bytes: [UInt8](data),
                    encoding: .utf8)
            else {
                icsSay(emit, L("the description would not come — the gateway announced papers it will not show"), .err)
                return
            }
            var serviceURN: String? = nil
            var control: String? = nil
            for urn in [
                "urn:schemas-upnp-org:service:WANIPConnection:1",
                "urn:schemas-upnp-org:service:WANPPPConnection:1",
            ] {
                if let hit = desc.range(
                    of: urn) {
                    serviceURN = urn
                    let segment = String(
                        desc[hit.lowerBound...])
                    control =
                        shieldXMLField(
                            segment,
                            "controlURL")
                    break
                }
            }
            guard let urn = serviceURN,
                  let controlPath = control
            else {
                icsSay(emit, L("the description carries no WAN connection service — nothing here forwards ports by UPnP"), .ok)
                return
            }
            var controlURL = controlPath
            if !controlPath
                .hasPrefix("http") {
                var origin = descURL
                if let schemeEnd =
                    descURL.range(
                        of: "://") {
                    let after = descURL[
                        schemeEnd.upperBound...]
                    if let slash =
                        after.firstIndex(
                            of: "/") {
                        origin = String(
                            descURL[..<slash])
                    }
                }
                controlURL =
                    controlPath.hasPrefix("/")
                    ? origin + controlPath
                    : origin + "/"
                        + controlPath
            }
            guard let soapURL = URL(
                string: controlURL) else {
                icsSay(emit, L("the control URL would not parse — the ledger stays unread"), .err)
                return
            }
            // The ledger itself: entry
            // after entry until the
            // gateway says there are no
            // more (fault 713).
            var mappings = 0
            var index = 0
            while index < 64 {
                let body = "<?xml "
                    + "version=\"1.0\"?>"
                    + "\r\n<s:Envelope "
                    + "xmlns:s=\"http://"
                    + "schemas.xmlsoap.org"
                    + "/soap/envelope/\" "
                    + "s:encodingStyle="
                    + "\"http://schemas"
                    + ".xmlsoap.org/soap"
                    + "/encoding/\">"
                    + "<s:Body>"
                    + "<u:GetGenericPort"
                    + "MappingEntry "
                    + "xmlns:u=\"" + urn
                    + "\">"
                    + "<NewPortMapping"
                    + "Index>\(index)"
                    + "</NewPortMapping"
                    + "Index>"
                    + "</u:GetGenericPort"
                    + "MappingEntry>"
                    + "</s:Body>"
                    + "</s:Envelope>"
                var soap = URLRequest(
                    url: soapURL)
                soap.httpMethod = "POST"
                soap.timeoutInterval = 8
                soap.setValue(
                    "text/xml; charset=\"utf-8\"",
                    forHTTPHeaderField:
                        "Content-Type")
                soap.setValue(
                    "\"" + urn
                        + "#GetGenericPort"
                        + "MappingEntry\"",
                    forHTTPHeaderField:
                        "SOAPACTION")
                soap.httpBody = Data(
                    Array(body.utf8))
                guard let (respData,
                           http) =
                        shieldWebFetch(soap),
                      let text = String(
                        bytes: [UInt8](
                            respData),
                        encoding: .utf8)
                else { break }
                if http?.statusCode != 200
                    || shieldXMLField(
                        text, "errorCode")
                        == "713" {
                    break
                }
                let ext = shieldXMLField(
                    text, "NewExternalPort")
                    ?? "?"
                let proto = shieldXMLField(
                    text, "NewProtocol")
                    ?? "?"
                let intPort =
                    shieldXMLField(
                        text, "NewInternalPort")
                    ?? "?"
                let client =
                    shieldXMLField(
                        text,
                        "NewInternalClient")
                    ?? "?"
                let enabled =
                    shieldXMLField(
                        text, "NewEnabled")
                    ?? "?"
                let label =
                    shieldXMLField(
                        text,
                        "NewPortMappingDescription")
                    ?? ""
                let lease =
                    shieldXMLField(
                        text,
                        "NewLeaseDuration")
                    ?? "?"
                mappings += 1
                icsSay(emit, String(format: L("  %@/%@ → %@:%@ — '%@' (enabled %@, lease %@)"), ext, proto, client, intPort, label, enabled, lease), enabled == "1" ? .err : .out)
                index += 1
            }
            if mappings == 0 {
                icsSay(emit, L("grade: the mapping table stands empty — nothing inside this house currently holds a forwarded door"), .ok)
            } else {
                icsSay(emit, String(format: L("grade: %lld standing mapping(s). Every one was asked for by something INSIDE the house — a mapping you did not make, or do not recognize, is the finding, and it stands until the lease dies or the gateway forgets it"), Int64(mappings)), .err)
            }
            icsSay(emit, L("reads only — GetGenericPortMappingEntry is a question. AddPortMapping does not exist on this bench"))
        }
    }

    // MARK: dnsposture — your resolver, graded

    static func dnsposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved =
                    BlacksiteNet.resolve4(
                        arg) else {
                icsSay(emit, L("dnsposture: give your resolver — dnsposture 192.168.1.1"), .err)
                return
            }
            let ip = resolved.ip
            icsSay(emit, String(format: L("dnsposture — %@ (%@): the house resolver, graded"), arg, ip), .sys)
            var findings = 0
            // Recursion: an outside
            // name, fetched for a
            // client-shaped asker.
            if let reply = nameQuery(
                server: ip,
                name: "example.com",
                type: 1) {
                let flags = shieldDNSFlags(
                    reply.msg)
                if flags.ra,
                   !reply.answers.isEmpty {
                    icsSay(emit, L("recursion: offered and performed — it fetched an outside name for this client. Right and proper for a house resolver; the same generosity beyond the LAN would be an open resolver, which from here cannot be tested and is not claimed"))
                } else if flags.ra {
                    icsSay(emit, L("recursion: the RA flag is set, but the fetch came back empty — offered in name, withheld in fact"))
                } else {
                    icsSay(emit, L("recursion: not offered (no RA) — it answers for its own zones and sends the rest away"), .ok)
                }
            } else {
                icsSay(emit, L("the resolver did not answer an ordinary A question at all"))
            }
            // DNSSEC: signatures asked
            // for by name; the AD bit
            // is the resolver vouching.
            if let reply = nameQuery(
                server: ip,
                name: "cloudflare.com",
                type: 1, dnssecOK: true) {
                let signed = reply.answers
                    .contains { $0.type == 46 }
                if reply.authenticated {
                    icsSay(emit, L("validation: the AD bit is asserted — this resolver checks DNSSEC signatures and vouches for what passes"), .ok)
                } else if signed {
                    icsSay(emit, L("DNSSEC data is served when asked (RRSIGs ride along), but validation is not asserted — the answers are carried, not checked"))
                } else {
                    findings += 1
                    icsSay(emit, L("no DNSSEC evidence: signatures were asked for and none came back — a forged answer would sail through this resolver unchecked"), .err)
                }
            }
            // The version confession.
            if let msg = shieldDNS(
                serverIP: ip,
                name: "version.bind",
                type: 16, qclass: 3) {
                let answers =
                    shieldDNSAnswers(msg)
                if let version = answers
                    .first(where: {
                        $0.type == 16
                            && !$0.text
                                .isEmpty
                    }) {
                    icsSay(emit, String(format: L("it introduces itself to any asker: %@"), version.text))
                    for hit in
                        shieldEOLVerdicts(
                            version.text) {
                        icsSay(emit, hit.text,
                               .err)
                    }
                } else {
                    icsSay(emit, L("version: not disclosed — the CHAOS question was refused or answered empty, which is the quiet posture"), .ok)
                }
            } else {
                icsSay(emit, L("the CHAOS version question went unanswered entirely"))
            }
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the resolver's posture is the careful one")
                                    : String(format: L("%lld finding(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: mailposture — the domain's defences

    /// TXT records at a name, via
    /// the house resolver.
    static func shieldTXT(
        server: String, name: String)
        -> [String] {
        guard let reply = nameQuery(
            server: server, name: name,
            type: 16) else { return [] }
        return shieldDNSAnswers(reply.msg)
            .filter { $0.type == 16 }
            .map { $0.text }
    }

    static func mailposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var domain = target
                .trimmingCharacters(
                    in: .whitespaces)
            if let at = domain.lastIndex(
                of: "@") {
                domain = String(domain[
                    domain.index(
                        after: at)...])
            }
            for prefix in ["https://",
                           "http://"] {
                if domain.hasPrefix(
                    prefix) {
                    domain = String(domain
                        .dropFirst(
                            prefix.count))
                }
            }
            if let slash = domain.firstIndex(
                of: "/") {
                domain = String(
                    domain[..<slash])
            }
            guard !domain.isEmpty,
                  domain.contains(".")
            else {
                icsSay(emit, L("mailposture: give your domain — mailposture example.com"), .err)
                return
            }
            let server = wireResolver().ip
            icsSay(emit, String(format: L("mailposture — %@: the domain's defences, rung by rung"), domain), .sys)
            var findings = 0
            // The mail doors.
            if let mx = nameQuery(
                server: server, name: domain,
                type: 15) {
                let routes =
                    shieldDNSAnswers(mx.msg)
                    .filter { $0.type == 15 }
                    .map { $0.text }
                if routes.isEmpty {
                    icsSay(emit, L("MX: no mail route is published — the domain takes no mail"))
                } else {
                    icsSay(emit, String(format: L("MX: %@"), routes.joined(separator: " · ")))
                }
            }
            // SPF.
            let apex = shieldTXT(
                server: server, name: domain)
            let spfs = apex.filter {
                $0.hasPrefix("v=spf1")
            }
            if spfs.count > 1 {
                findings += 1
                icsSay(emit, L("SPF: MORE THAN ONE v=spf1 record — the standard voids both; receivers may treat every verdict as none"), .err)
            } else if let spf = spfs.first {
                icsSay(emit, String(format: L("SPF: %@"), spf))
                if spf.contains("-all") {
                    icsSay(emit, L("   and it ends -all — the hard fail: anyone else sending as this domain is denounced"), .ok)
                } else if spf.contains(
                    "~all") {
                    icsSay(emit, L("   and it ends ~all — the soft fail: strangers are marked, not denounced"))
                } else {
                    findings += 1
                    icsSay(emit, L("   and it never reaches a hard -all — the record names friends but denounces no one"), .err)
                }
            } else {
                findings += 1
                icsSay(emit, L("SPF: no record at all — the domain publishes no list of who may send as it"), .err)
            }
            // DMARC.
            let dmarc = shieldTXT(
                server: server,
                name: "_dmarc." + domain)
                .first { $0.hasPrefix(
                    "v=DMARC1") }
            if let dmarc = dmarc {
                var policy: String? = nil
                var pct: String? = nil
                var rua: String? = nil
                for tag in dmarc.components(
                    separatedBy: ";") {
                    let trimmed = tag
                        .trimmingCharacters(
                            in: .whitespaces)
                    if trimmed.hasPrefix(
                        "p=") {
                        policy = String(
                            trimmed
                                .dropFirst(2))
                    } else if trimmed
                        .hasPrefix("pct=") {
                        pct = String(trimmed
                            .dropFirst(4))
                    } else if trimmed
                        .hasPrefix("rua=") {
                        rua = String(trimmed
                            .dropFirst(4))
                    }
                }
                switch policy {
                case "reject":
                    icsSay(emit, L("DMARC: p=reject — the top of the ladder: failed mail wearing this domain is to be refused"), .ok)
                case "quarantine":
                    icsSay(emit, L("DMARC: p=quarantine — failed mail is filed as suspect, not refused; reject is the rung above"))
                default:
                    findings += 1
                    icsSay(emit, L("DMARC: p=none (or no policy at all) — the domain watches its impersonators and stops none of them"), .err)
                }
                if let pct = pct,
                   pct != "100" {
                    icsSay(emit, String(format: L("   and it applies to only %@%% of mail — a policy at partial strength"), pct))
                }
                if rua != nil {
                    icsSay(emit, L("   aggregate reports are collected (rua) — someone is watching the impersonation weather"))
                }
            } else {
                findings += 1
                icsSay(emit, L("DMARC: no record — anyone can wear this domain, and no receiver has been told to mind"), .err)
            }
            // MTA-STS.
            let sts = shieldTXT(
                server: server,
                name: "_mta-sts." + domain)
                .first { $0.hasPrefix(
                    "v=STSv1") }
            if sts != nil {
                icsSay(emit, L("MTA-STS: the domain announces a transport policy"))
                let policyURL = "https://"
                    + "mta-sts." + domain
                    + "/.well-known/"
                    + "mta-sts.txt"
                if let url = URL(
                    string: policyURL) {
                    var request =
                        URLRequest(url: url)
                    request.timeoutInterval
                        = 8
                    if let (data, _) =
                        shieldWebFetch(
                            request),
                       let text = String(
                        bytes: [UInt8](data),
                        encoding: .utf8) {
                        for line in text
                            .components(
                                separatedBy: "\n")
                        where line.hasPrefix(
                            "mode:") {
                            let mode = String(
                                line.dropFirst(
                                    5))
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines)
                            if mode
                                == "enforce" {
                                icsSay(emit, L("   and its mode is enforce — sending servers must use TLS and must check the papers, or refuse the road"), .ok)
                            } else {
                                icsSay(emit, String(format: L("   and its mode is %@ — testing watches the road but does not yet hold it"), mode))
                            }
                        }
                    }
                }
            } else {
                icsSay(emit, L("MTA-STS: none — transport encryption for this domain's mail is offered, never required"))
            }
            icsSay(emit, L("DKIM stands outside this board: it needs a selector to read, and dkimprobe tries the known ones"))
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the domain's published defences stand at the top of their ladders")
                                    : String(format: L("%lld open rung(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: patchprobe + kevcheck — the presented versions

    static func patchprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 22) else {
                icsSay(emit, L("patchprobe: give a host on your own wire — patchprobe 192.168.1.10"), .err)
                return
            }
            icsSay(emit, String(format: L("patchprobe — %@ (%@): what it presents, against the bench's bounded table"), resolved.host, resolved.ip), .sys)
            let claims = shieldClaims(
                ip: resolved.ip,
                host: resolved.host)
            if claims.isEmpty {
                icsSay(emit, L("the host presents no version claims on the doors the bench knocks — nothing to grade, which is itself a quiet posture"))
            }
            var hits = 0
            for claim in claims {
                icsSay(emit, String(format: L("%@: %@"), claim.source, claim.text))
                for hit in shieldEOLVerdicts(
                    claim.text) {
                    hits += 1
                    icsSay(emit, "   "
                        + hit.level + " — "
                        + hit.text, .err)
                }
            }
            if hits == 0,
               !claims.isEmpty {
                icsSay(emit, L("grade: no presented version stands in the table — the table is bounded on purpose, so this is a narrow statement, not a patch bill of health"), .ok)
            } else if hits > 0 {
                icsSay(emit, String(format: L("grade: %lld table verdict(s) above"), Int64(hits)), .err)
            }
            icsSay(emit, L("the bench's own table, written 2026-10 and aging from that day; a version is the device's CLAIM about itself — devices lie, are proxied, and wear other names — and the grade rides on the claim, as labelled"))
        }
    }

    static func kevcheck(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 22) else {
                icsSay(emit, L("kevcheck: give a host on your own wire — kevcheck 192.168.1.10"), .err)
                return
            }
            guard wireKEVLoad() != nil
            else {
                icsSay(emit, L("kevcheck: the KEV catalog could not be fetched — no verdict follows"), .err)
                return
            }
            icsSay(emit, String(format: L("kevcheck — %@ (%@): the presented products against the federal ledger"), resolved.host, resolved.ip), .sys)
            let claims = shieldClaims(
                ip: resolved.ip,
                host: resolved.host)
            for claim in claims {
                icsSay(emit, String(format: L("%@: %@"), claim.source, claim.text))
            }
            let hits = shieldKEVHits(
                claims: claims)
            if hits.isEmpty {
                icsSay(emit, L("grade: no presented product stands in the catalog — CISA has no confirmed in-the-wild exploitation for what this host presents. Absence here is not safety; it is the absence of a confirmed report"), .ok)
            } else {
                for hit in hits.prefix(10) {
                    let cve = wireStr(
                        hit["cveID"]) ?? "?"
                    let name = wireStr(
                        hit["vulnerabilityName"])
                        ?? ""
                    let due = wireStr(
                        hit["dueDate"]) ?? "?"
                    let ransomware = wireStr(
                        hit["knownRansomwareCampaignUse"])
                        ?? "Unknown"
                    icsSay(emit, String(format: L("  %@: %@ — remediation was due %@; ransomware use: %@"), cve, name, due, ransomware), .err)
                }
                if hits.count > 10 {
                    icsSay(emit, String(format: L("  … and %lld more in the ledger for these products"), Int64(hits.count - 10)))
                }
                icsSay(emit, L("grade: a KEV entry is not a score — it is a vulnerability CONFIRMED exploited in the wild, with a deadline federal agencies were ordered to meet. Presence here outranks any CVSS number. The ledger names product families, not exact builds: whether your build is the affected one is the operator's to confirm"), .err)
            }
        }
    }

    // MARK: iotposture — the small doors

    static func iotposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 1883) else {
                icsSay(emit, L("iotposture: give a host on your own wire — iotposture 192.168.1.50"), .err)
                return
            }
            let ip = resolved.ip
            let host = resolved.host
            icsSay(emit, String(format: L("iotposture — %@ (%@): the small-machine doors, graded"), host, ip), .sys)
            var findings = 0
            if shieldDoorOpen(
                ip: ip, port: 1883) {
                if let code =
                    shieldMQTTRead(
                        ip: ip, port: 1883) {
                    if code == 0 {
                        findings += 1
                        icsSay(emit, L("MQTT: the broker took an UNNAMED guest in — the device's chatter (and anything it hears) is open to the wire"), .err)
                    } else {
                        icsSay(emit, String(format: L("MQTT: the broker demands a name (CONNACK %lld)"), Int64(code)), .ok)
                    }
                } else {
                    icsSay(emit, L("MQTT: the door answers TCP but speaks no MQTT"))
                }
            } else {
                icsSay(emit, L("MQTT: no broker on the plain door"))
            }
            if shieldDoorOpen(
                ip: ip, port: 8883) {
                icsSay(emit, L("the sealed broker door answers too (8883) — TLS MQTT lives here; its papers ride the TLS knocks"))
            }
            if let code = shieldCoAPRead(
                ip: ip) {
                let rendered = String(
                    format: "%lld.%02lld",
                    Int64(code >> 5),
                    Int64(code & 31))
                if code == 69 {
                    findings += 1
                    icsSay(emit, L("CoAP: the resource directory (/.well-known/core) was served to a TOKENLESS stranger (2.05) — the device's whole map is public"), .err)
                } else if code == 129 {
                    icsSay(emit, L("CoAP: the directory demands a token (4.01)"), .ok)
                } else if code == 132 {
                    icsSay(emit, L("CoAP: it answers, but keeps no public directory (4.04)"))
                } else {
                    icsSay(emit, String(format: L("CoAP: it answered %@"), rendered))
                }
            } else {
                icsSay(emit, L("CoAP: silent on UDP 5688"))
            }
            if shieldDoorOpen(
                ip: ip, port: 554) {
                let rtsp = shieldRTSPRead(
                    ip: ip, host: host,
                    port: 554)
                if rtsp.describe == 200,
                   !rtsp.authHeader {
                    findings += 1
                    icsSay(emit, L("RTSP: DESCRIBE answered 200 with no credential demanded — the stream describes itself to any stranger who asks"), .err)
                } else if rtsp.describe
                            == 401
                            || rtsp.options
                                == 401 {
                    icsSay(emit, L("RTSP: the stream demands a name (401)"), .ok)
                } else if let status =
                            rtsp.options {
                    icsSay(emit, String(format: L("RTSP: OPTIONS answered %lld; DESCRIBE did not settle the question"), Int64(status)))
                } else {
                    icsSay(emit, L("RTSP: the door answers TCP but speaks no RTSP"))
                }
            } else {
                icsSay(emit, L("RTSP: no stream door answers"))
            }
            if shieldDoorOpen(
                ip: ip, port: 8554) {
                icsSay(emit, L("an alternate RTSP door answers too (8554) — check it with the same questions"))
            }
            if shieldDoorOpen(
                ip: ip, port: 1935) {
                icsSay(emit, L("an RTMP door answers (1935) — publish-side streaming gear lives here, and it rarely asks who is publishing"))
            }
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the small doors ask names and keep their maps")
                                    : String(format: L("%lld finding(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: guestprobe — from where you stand

    static func guestprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("guestprobe — the house as a guest meets it: one vantage, labelled inference"), .sys)
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            var gateway: String? = nil
            if !arg.isEmpty {
                gateway = BlacksiteNet
                    .resolve4(arg)?.ip
            }
            if gateway == nil {
                gateway = BlacksiteNet
                    .defaultGatewayIP()
            }
            guard let gw = gateway else {
                icsSay(emit, L("guestprobe: no gateway could be read from this wire — the vantage itself is missing"), .err)
                return
            }
            if let own = BlacksiteNet
                .primaryIPv4() {
                icsSay(emit, String(format: L("you stand at %@; the gateway is %@"), own, gw))
            } else {
                icsSay(emit, String(format: L("the gateway is %@"), gw))
            }
            let doors: [(Int, String)] = [
                (53, "DNS"), (80, "HTTP"),
                (443, "HTTPS"), (22, "SSH"),
                (23, "Telnet"),
                (8080, "HTTP-alt"),
                (8443, "HTTPS-alt"),
            ]
            var answering: [String] = []
            for (port, name) in doors
            where shieldDoorOpen(
                ip: gw, port: port,
                timeout: 1.2) {
                answering.append(
                    "\(name) \(port)")
            }
            if answering.isEmpty {
                icsSay(emit, L("the gateway shows a guest NO doors at all — a silent face"), .ok)
            } else {
                icsSay(emit, String(format: L("the gateway shows any guest these doors: %@"), answering.joined(separator: " · ")))
                if answering.contains(
                    "Telnet 23") {
                    icsSay(emit, L("and one of them is Telnet — a cleartext shell, offered to every device that joins this wire"), .err)
                }
            }
            if let reply = nameQuery(
                server: gw,
                name: "example.com",
                type: 1),
               !reply.answers.isEmpty {
                icsSay(emit, L("the house resolver fetches outside names for this guest — as it should for guests, and as it would for anything at all that joins this wire"))
            }
            // Who else announces?
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
                window: 2.5, maxPackets: 128)
            let voices = Set(
                packets.map { $0.from })
            if voices.isEmpty {
                icsSay(emit, L("SSDP: the wire is quiet — nothing announces itself to a guest's ear"))
            } else {
                icsSay(emit, String(format: L("SSDP: %lld device(s) announce themselves to any ear on this wire — a guest hears the house introduce itself, by address: %@"), Int64(voices.count), voices.sorted().joined(separator: ", ")))
            }
            icsSay(emit, L("limits: one vantage, one moment — this phone, on this network, now. What answers a guest here answers anything that joins this wire; what sleeps, or hides behind a second network, is not reported. Inference, labelled as such"))
        }
    }

    // MARK: timeprobe — the clock, graded

    static func timeprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 123) else {
                icsSay(emit, L("timeprobe: give a host on your own wire — timeprobe 192.168.1.1"), .err)
                return
            }
            guard let ntp = wireNTPRead(
                resolved.ip) else {
                icsSay(emit, String(format: L("timeprobe: no NTP answer from %@ — its clock keeps its own counsel (UDP 123 silent or filtered)"), resolved.host))
                return
            }
            icsSay(emit, String(format: L("timeprobe — %@ (%@)"), resolved.host, resolved.ip), .sys)
            icsPrint(emit, ntp.lines)
            if let offset = ntp.offset {
                let magnitude = abs(offset)
                if magnitude < 0.05 {
                    icsSay(emit, L("grade: tight — this clock and true time agree to a breath"), .ok)
                } else if magnitude < 0.5 {
                    icsSay(emit, L("grade: honest drift, well inside what logs and TLS forgive"))
                } else if magnitude < 5 {
                    icsSay(emit, L("grade: drift worth minding — distributed logs stop agreeing with each other first"))
                } else {
                    icsSay(emit, String(format: L("grade: the clock is off by %.1f s — Kerberos refuses, certificates mistime, and every log this box writes is a small fiction"), offset), .err)
                }
            }
        }
    }

    // MARK: v6posture — the second stack

    /// A connect on the second
    /// stack: the 28-byte Darwin
    /// sockaddr_in6, laid out by
    /// hand (the Python-verified
    /// layout), the address itself
    /// placed by inet_pton.
    static func shieldV6Open(
        ip: String, port: Int,
        timeout: Double = 1.6) -> Bool {
        var address = in6_addr()
        let parsed = ip.withCString {
            inet_pton(AF_INET6, $0,
                      &address)
        }
        guard parsed == 1 else {
            return false
        }
        let fd = socket(AF_INET6,
                        SOCK_STREAM,
                        IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: timeout)
        var bytes = [UInt8](
            repeating: 0, count: 28)
        bytes[0] = 28
        bytes[1] = 30
        bytes[2] = UInt8(
            (port >> 8) & 0xFF)
        bytes[3] = UInt8(port & 0xFF)
        withUnsafeBytes(of: &address) {
            raw in
            bytes.replaceSubrange(
                8..<24, with: Array(raw))
        }
        let rc = bytes.withUnsafeBytes {
            buffer -> Int32 in
            guard let base =
                buffer.baseAddress else {
                return -1
            }
            return connect(
                fd, base.assumingMemoryBound(
                    to: sockaddr.self),
                socklen_t(28))
        }
        return rc == 0
    }

    static func v6posture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty else {
                icsSay(emit, L("v6posture: give a host on your own wire — v6posture example.com"), .err)
                return
            }
            icsSay(emit, String(format: L("v6posture — %@: the doors the second stack forgot to close"), arg), .sys)
            let server = wireResolver().ip
            var v4: String? = nil
            var v6: [String] = []
            if arg.contains(":") {
                v6 = [arg]
            } else {
                if let reply = nameQuery(
                    server: server,
                    name: arg, type: 1) {
                    v4 = shieldDNSAnswers(
                        reply.msg)
                        .first {
                            $0.type == 1
                                && !$0.text
                                    .isEmpty
                        }?.text
                }
                if let reply = nameQuery(
                    server: server,
                    name: arg, type: 28) {
                    v6 = shieldDNSAnswers(
                        reply.msg)
                        .filter {
                            $0.type == 28
                                && !$0.text
                                    .isEmpty
                        }
                        .map { $0.text }
                }
            }
            guard !v6.isEmpty else {
                icsSay(emit, L("the name carries no IPv6 answer — this host is known to the wire in one stack only, and there is no second-stack gap in its name"), .ok)
                return
            }
            let doors = [22, 80, 443, 445]
            var gaps = 0
            for address in v6.prefix(3) {
                icsSay(emit, String(format: L("IPv6: %@"), address))
                for port in doors {
                    let onV6 =
                        shieldV6Open(
                            ip: address,
                            port: port)
                    let onV4 = v4.map {
                        shieldDoorOpen(
                            ip: $0, port: port)
                    } ?? false
                    if onV6, !onV4 {
                        gaps += 1
                        icsSay(emit, String(format: L("  door %lld answers on IPv6 but NOT on IPv4 — the posture was written for one stack, and the other moved in"), Int64(port)), .err)
                    } else if onV6 {
                        icsSay(emit, String(format: L("  door %lld answers on both stacks"), Int64(port)))
                    }
                }
            }
            icsSay(emit, String(format: L("grade: %@"), gaps == 0
                                    ? L("no door was found answering on the second stack alone")
                                    : String(format: L("%lld dual-stack gap(s) above"), Int64(gaps))), gaps == 0 ? .ok : .err)
            icsSay(emit, L("limits: the name's global answers only — link-local and ULA addresses are not probed, and a firewall in front of the host may still refuse what its stack accepted"))
        }
    }

    // MARK: headerposture — the five shields, owner side

    static func headerposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let arg = target
            .trimmingCharacters(
                in: .whitespaces)
        guard !arg.isEmpty else {
            icsSay(emit, L("headerposture: give one of yours — headerposture https://example.com or 192.168.1.1"), .err)
            done()
            return
        }
        var captured: [ICSLine] = []
        let capture: BlacksiteEmit = {
            text, kind in
            captured.append((text: text,
                             kind: kind))
        }
        headersdeep(
            url: arg, emit: capture,
            done: {
                BlacksitePentest.run {
                    defer { done() }
                    icsSay(emit, String(format: L("headerposture — %@: the deep read, then the owner's roll-up"), arg), .sys)
                    icsPrint(emit, captured)
                    let all = captured
                        .map { $0.text }
                        .joined(separator: "\n")
                        .lowercased()
                    let shields: [(String,
                                   String)] = [
                        ("strict-transport-security",
                         "Strict-Transport-Security"),
                        ("content-security-policy",
                         "Content-Security-Policy"),
                        ("x-content-type-options",
                         "X-Content-Type-Options"),
                        ("x-frame-options",
                         "X-Frame-Options"),
                        ("referrer-policy",
                         "Referrer-Policy"),
                    ]
                    var present = 0
                    for (needle, name)
                    in shields {
                        if all.contains(
                            needle) {
                            present += 1
                            icsSay(emit, String(format: L("  %@ — raised"), name), .ok)
                        } else {
                            icsSay(emit, String(format: L("  %@ — NOT RAISED"), name), .err)
                        }
                    }
                    icsSay(emit, String(format: L("grade: of the five defensive headers, %lld answer"), Int64(present)), present == 5 ? .ok : .err)
                }
            })
    }

    // MARK: cookieposture — the jars, read plainly

    static func cookieposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var hostPart = target
                .trimmingCharacters(
                    in: .whitespaces)
            var port = 80
            if let colon = hostPart
                .lastIndex(of: ":"),
               let parsed = Int(hostPart[
                    hostPart.index(
                        after: colon)...]) {
                port = parsed
                hostPart = String(
                    hostPart[..<colon])
            }
            guard !hostPart.isEmpty,
                  let resolved = icsResolve(
                    hostPart, port) else {
                icsSay(emit, L("cookieposture: give one of yours — cookieposture 192.168.1.1 or 192.168.1.1:8080"), .err)
                return
            }
            icsSay(emit, String(format: L("cookieposture — %@ (%@:%lld): the jars the root page hands out"), resolved.host, resolved.ip, Int64(port)), .sys)
            guard let reply = shieldHTTP(
                ip: resolved.ip,
                host: port == 80
                    ? resolved.host
                    : "\(resolved.host):\(port)",
                port: port, path: "/") else {
                icsSay(emit, L("the door did not answer plain HTTP — if it speaks TLS, cookieaudit reads the wrapped answer; the shield does not fake a grade from a refused read"), .err)
                return
            }
            icsSay(emit, reply.statusLine)
            let cookies = reply.cookies()
            if cookies.isEmpty {
                icsSay(emit, L("the root page sets no cookies — nothing to grade here; a login page deeper in may set them, and only the page that sets them can be graded"))
                return
            }
            var flagged = 0
            for cookie in cookies {
                let segments = cookie
                    .components(
                        separatedBy: ";")
                    .map {
                        $0.trimmingCharacters(
                            in: .whitespaces)
                    }
                let first = segments.first
                    ?? cookie
                let name = first.components(
                    separatedBy: "=").first
                    ?? first
                let lowered = cookie
                    .lowercased()
                var missing: [String] = []
                if !lowered.contains(
                    "secure") {
                    missing.append("Secure")
                }
                if !lowered.contains(
                    "httponly") {
                    missing.append("HttpOnly")
                }
                if !lowered.contains(
                    "samesite") {
                    missing.append("SameSite")
                }
                if missing.isEmpty {
                    icsSay(emit, String(format: L("  %@: Secure, HttpOnly and SameSite all set"), name), .ok)
                } else {
                    flagged += 1
                    icsSay(emit, String(format: L("  %@: missing %@"), name, missing.joined(separator: ", ")), .err)
                }
            }
            icsSay(emit, String(format: L("grade: %lld cookie(s), %lld carrying a missing flag"), Int64(cookies.count), Int64(flagged)), flagged == 0 ? .ok : .err)
            icsSay(emit, L("the flags are the whole grade: Secure keeps the cookie off cleartext, HttpOnly keeps it out of scripts' reach, SameSite keeps it home"))
        }
    }

    // MARK: dirposture — the doors the page holds open

    static func dirposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var trimmed = target
                .trimmingCharacters(
                    in: .whitespaces)
            for prefix in ["https://",
                           "http://"] {
                if trimmed.hasPrefix(
                    prefix) {
                    trimmed = String(trimmed
                        .dropFirst(
                            prefix.count))
                }
            }
            var hostPart = trimmed
            var root = "/"
            if let slash = trimmed
                .firstIndex(of: "/") {
                hostPart = String(
                    trimmed[..<slash])
                root = String(trimmed[
                    slash...])
            }
            var port = 80
            if let colon = hostPart
                .lastIndex(of: ":"),
               let parsed = Int(hostPart[
                    hostPart.index(
                        after: colon)...]) {
                port = parsed
                hostPart = String(
                    hostPart[..<colon])
            }
            guard !hostPart.isEmpty,
                  let resolved = icsResolve(
                    hostPart, port) else {
                icsSay(emit, L("dirposture: give one of yours — dirposture 192.168.1.1 or 192.168.1.1:8080/files/"), .err)
                return
            }
            let hostHeader = port == 80
                ? resolved.host
                : "\(resolved.host):\(port)"
            func isListing(
                _ body: String) -> Bool {
                body.contains("Index of /")
                    || body.contains(
                        "Parent Directory")
            }
            icsSay(emit, String(format: L("dirposture — %@ (%@:%lld)%@: only the doors this page itself holds open"), resolved.host, resolved.ip, Int64(port), root), .sys)
            guard let reply = shieldHTTP(
                ip: resolved.ip,
                host: hostHeader,
                port: port, path: root) else {
                icsSay(emit, L("the door did not answer plain HTTP — a sealed door cannot be graded for openness here"), .err)
                return
            }
            guard reply.status == 200,
                  isListing(reply.bodyText)
            else {
                icsSay(emit, String(format: L("the root page is no open directory (%@) — the server serves pages, not its own map"), reply.statusLine), .ok)
                return
            }
            var open = 0
            icsSay(emit, L("the root itself stands open as a directory listing — the whole tree below it is a map anyone may read"), .err)
            open += 1
            // The links the page itself
            // volunteers: relative,
            // downward, ending in '/'.
            var hrefs: [String] = []
            var scan = reply.bodyText[...]
            while let hit = scan.range(
                of: "href=\"") {
                let rest = scan[
                    hit.upperBound...]
                guard let closeQuote =
                    rest.firstIndex(of: "\"")
                else { break }
                let value = String(
                    rest[..<closeQuote])
                scan = rest[closeQuote...]
                if value.hasSuffix("/"),
                   !value.contains("://"),
                   !value.hasPrefix("/"),
                   !value.hasPrefix("?"),
                   !value.hasPrefix("#"),
                   !value.contains(".."),
                   !hrefs.contains(value) {
                    hrefs.append(value)
                }
            }
            for href in hrefs.prefix(8) {
                let path = root + href
                if let sub = shieldHTTP(
                    ip: resolved.ip,
                    host: hostHeader,
                    port: port, path: path),
                   sub.status == 200,
                   isListing(sub.bodyText) {
                    open += 1
                    icsSay(emit, String(format: L("  open: %@ — the listing continues downward"), path), .err)
                }
            }
            if hrefs.count > 8 {
                icsSay(emit, String(format: L("  (the page volunteers %lld sub-doors; the bench walked the first eight)"), Int64(hrefs.count)))
            }
            icsSay(emit, String(format: L("grade: %lld open listing(s)"), Int64(open)), .err)
            icsSay(emit, L("no wordlist exists on this bench and nothing was guessed — only the doors this page itself holds open were walked through"))
        }
    }

    // MARK: metadataprobe — the link-local door

    static func metadataprobe(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            icsSay(emit, L("metadataprobe — the cloud's link-local door (169.254.169.254), knocked on once"), .sys)
            guard shieldDoorOpen(
                ip: "169.254.169.254",
                port: 80, timeout: 2.0)
            else {
                icsSay(emit, L("the door is silent from this vantage — no cloud metadata service lives on this wire's link-local, or it is filtered. On an ordinary house wire, silence is the expected answer"), .ok)
                return
            }
            if let reply = shieldHTTP(
                ip: "169.254.169.254",
                host: "169.254.169.254",
                port: 80,
                path: "/latest/meta-data/") {
                icsSay(emit, String(format: L("it answered: %@"), reply.statusLine))
                if reply.status == 200 {
                    icsSay(emit, L("grade: the metadata door answers a bare knock with 200 — in cloud country that door is the instance's papers drawer, and a tokenless 200 is the posture cloud breaches are made of. On THIS wire it says the network is woven into someone's cloud — or something is imitating one"), .err)
                } else if reply.status == 401
                            || reply.status
                                == 403 {
                    icsSay(emit, L("grade: it answers but demands a token first — the hardened pattern"), .ok)
                } else {
                    icsSay(emit, L("grade: it answers, and not with papers — noted, no more"))
                }
            } else {
                icsSay(emit, L("the door opened to TCP and then would not speak HTTP — noted, no more"))
            }
            icsSay(emit, L("the bench knocked and read the status line only; the body was discarded unread. A census of the door, never a harvest"))
        }
    }

    // MARK: printposture — the print doors

    static func printposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let arg = target
            .trimmingCharacters(
                in: .whitespaces)
        guard !arg.isEmpty else {
            icsSay(emit, L("printposture: give your printer — printposture 192.168.1.40"), .err)
            done()
            return
        }
        icsSay(emit, String(format: L("printposture — %@: the deep read, then the raw doors"), arg), .sys)
        printerprobe(
            target: arg, emit: emit,
            done: {
                BlacksitePentest.run {
                    defer { done() }
                    guard let resolved =
                        icsResolve(arg, 9100)
                    else { return }
                    let ip = resolved.ip
                    if shieldDoorOpen(
                        ip: ip, port: 9100) {
                        icsSay(emit, L("the raw print door (9100) stands open — anything on this wire can put ink on this machine's paper, no name asked, no log kept"), .err)
                    }
                    if shieldDoorOpen(
                        ip: ip, port: 515) {
                        icsSay(emit, L("the old line-printer door (515, LPD) answers too — a protocol from the trusting years"))
                    }
                    icsSay(emit, L("grade: a printer's doors are its posture — the ones above that answer without asking are the whole story"))
                }
            })
    }

    // MARK: nasposture — the file box, one board

    static func nasposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let arg = target
                .trimmingCharacters(
                    in: .whitespaces)
            guard !arg.isEmpty,
                  let resolved = icsResolve(
                    arg, 445) else {
                icsSay(emit, L("nasposture: give your file box — nasposture 192.168.1.30"), .err)
                return
            }
            let ip = resolved.ip
            let host = resolved.host
            icsSay(emit, String(format: L("nasposture — %@ (%@): the file box's whole face on one board"), host, ip), .sys)
            var findings = 0
            // SMB, compactly.
            if shieldDoorOpen(
                ip: ip, port: 445) {
                let smb = shieldSMBRead(
                    ip: ip, port: 445)
                if smb.answered {
                    if smb.smb1Offered == true {
                        findings += 1
                        icsSay(emit, L("SMB1 still speaks on the share door — the 1992 dialect, kept alive by something old or something careless"), .err)
                    }
                    switch smb.signing {
                    case "required":
                        icsSay(emit, L("SMB signing is required — the shares' traffic cannot be quietly rewritten in flight"), .ok)
                    case "on but not required",
                         "not offered":
                        findings += 1
                        icsSay(emit, L("SMB signing is NOT required — share traffic on this wire can be relayed and rewritten"), .err)
                    case "refused":
                        icsSay(emit, L("SMB refused the question outright"))
                    default:
                        icsSay(emit, L("SMB answers, in a posture the questions did not settle"))
                    }
                } else {
                    icsSay(emit, L("SMB: the share door opened, then spoke nothing the bench recognizes"))
                }
            } else {
                icsSay(emit, L("SMB: the share door (445) does not answer"))
            }
            // NFS + AFP doors.
            if shieldDoorOpen(
                ip: ip, port: 2049) {
                icsSay(emit, L("the NFS door (2049) answers — its export list is nfsprobe's deeper read; this board notes the door"))
            }
            if shieldDoorOpen(
                ip: ip, port: 111) {
                icsSay(emit, L("the RPC portmapper (111) answers — it will name the box's services to any asker"))
            }
            if shieldDoorOpen(
                ip: ip, port: 548) {
                icsSay(emit, L("the AFP door (548) answers — the Mac-flavoured share; whether it wants a password is backupprobe's question"))
            }
            // WebDAV doors.
            for port in [5005, 5006]
            where shieldDoorOpen(
                ip: ip, port: port) {
                icsSay(emit, String(format: L("a WebDAV door answers (%lld)"), Int64(port)))
            }
            // The consoles.
            var consoles = 0
            for port in [5000, 8000, 8080]
            where shieldDoorOpen(
                ip: ip, port: port) {
                consoles += 1
                if let reply = shieldHTTP(
                    ip: ip,
                    host: "\(host):\(port)",
                    port: port, path: "/") {
                    let serverNote = reply
                        .header("Server").map {
                            " — " + $0
                        } ?? ""
                    icsSay(emit, String(format: L("console %lld: %@%@"), Int64(port), reply.statusLine, serverNote))
                }
            }
            if shieldDoorOpen(
                ip: ip, port: 5001) {
                consoles += 1
                icsSay(emit, L("console 5001: the sealed console answers (TLS) — its papers ride certwatch"))
            }
            if consoles == 0 {
                icsSay(emit, L("no web console answers on the usual doors"))
            }
            icsSay(emit, String(format: L("grade: %@"), findings == 0
                                    ? L("the box's share doors carry no finding on this board")
                                    : String(format: L("%lld finding(s) above"), Int64(findings))), findings == 0 ? .ok : .err)
        }
    }

    // MARK: cameraposture — the eye, graded

    static func cameraposture(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var hostPart = target
                .trimmingCharacters(
                    in: .whitespaces)
            var port = 80
            var explicitPort = false
            if let colon = hostPart
                .lastIndex(of: ":"),
               let parsed = Int(hostPart[
                    hostPart.index(
                        after: colon)...]) {
                port = parsed
                explicitPort = true
                hostPart = String(
                    hostPart[..<colon])
            }
            guard !hostPart.isEmpty,
                  let resolved = icsResolve(
                    hostPart, port) else {
                icsSay(emit, L("cameraposture: give your camera — cameraposture 192.168.1.60"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            icsSay(emit, String(format: L("cameraposture — %@ (%@:%lld): the eye's papers and its stream"), host, ip, Int64(port)), .sys)
            let onvif = streetONVIFCore(
                host, port, light: true)
            let deep = streetCamDeepCore(
                host, port, light: true)
            icsPrint(emit, onvif)
            icsPrint(emit, deep)
            let named = !onvif.isEmpty
                || !deep.isEmpty
            if named {
                icsSay(emit, L("the camera names itself to a stranger's knock — manufacturer, model and firmware version are the device's CLAIM, printed above as claims; a named firmware is a searchable thing"))
            } else {
                icsSay(emit, L("the camera would not name itself on the ONVIF or vendor doors the bench knocks"), .ok)
            }
            let rtspPort = explicitPort
                ? port : 554
            if shieldDoorOpen(
                ip: ip, port: rtspPort) {
                let rtsp = shieldRTSPRead(
                    ip: ip, host: host,
                    port: rtspPort)
                if rtsp.describe == 200,
                   !rtsp.authHeader {
                    icsSay(emit, L("and its stream DESCRIBEs itself with no credential demanded (200) — the eye shows its papers, and its shape, to anyone on the wire"), .err)
                } else if rtsp.describe == 401
                            || rtsp.options
                                == 401 {
                    icsSay(emit, L("its stream demands a name before it describes itself (401)"), .ok)
                }
            }
            icsSay(emit, L("no PTZ move is sent, ever — the street wave's line holds here: nodes are counted, never aimed"))
        }
    }

    // MARK: watchprobe — the drift ledger

    static func watchprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let words = target
                .split(separator: " ")
                .map { String($0) }
            let saveMode = words.first
                == "save"
            let host = saveMode
                ? (words.count > 1
                    ? words[1] : "")
                : (words.first ?? "")
            guard !host.isEmpty,
                  let resolved = icsResolve(
                    host, 22) else {
                icsSay(emit, L("watchprobe: give a host on your own wire — watchprobe 192.168.1.1, or watchprobe save 192.168.1.1 to lay the baseline"), .err)
                return
            }
            let sanitized = host.map {
                ch -> Character in
                if ch.isLetter
                    || ch.isNumber
                    || ch == "."
                    || ch == "-" {
                    return ch
                }
                return "_"
            }
            let path = "shield/"
                + String(sanitized)
                + ".ledger"
            icsSay(emit, String(format: L("watchprobe — %@ (%@): the census board, then the drift"), resolved.host, resolved.ip), .sys)
            var baseline: [String: String]?
                = nil
            if let raw = BlacksiteFS
                .readText(path) {
                var parsed: [String: String]
                    = [:]
                for line in raw.components(
                    separatedBy: "\n")
                where !line.isEmpty {
                    let parts = line.split(
                        separator: "\t",
                        maxSplits: 1)
                    if parts.count == 2 {
                        parsed[String(parts[0])]
                            = String(parts[1])
                    }
                }
                baseline = parsed
            }
            let findings = shieldCensusCore(
                host: resolved.host,
                ip: resolved.ip, emit: emit)
            let now: [String: String] =
                Dictionary(
                    findings.map {
                        ($0.key, $0.text)
                    },
                    uniquingKeysWith: {
                        first, _ in first
                    })
            if let old = baseline {
                var events = 0
                for finding in findings
                where old[finding.key] == nil {
                    events += 1
                    icsSay(emit, String(format: L("NEW since the baseline: %@"), finding.text), .err)
                }
                for finding in findings
                where old[finding.key] != nil
                        && old[finding.key]
                            != finding.text {
                    events += 1
                    icsSay(emit, String(format: L("CHANGED: %@ — now: %@"), old[finding.key] ?? "", finding.text), .err)
                }
                for (key, text) in old
                    .sorted(by: {
                        $0.key < $1.key
                    })
                where now[key] == nil {
                    events += 1
                    icsSay(emit, String(format: L("GONE since the baseline: %@"), text), .ok)
                }
                if events == 0 {
                    icsSay(emit, L("drift: the board matches the baseline line for line — the wire kept its posture"), .ok)
                } else {
                    icsSay(emit, String(format: L("drift: %lld change(s) since the baseline"), Int64(events)), .err)
                }
            } else if saveMode {
                icsSay(emit, String(format: L("the first baseline is laid down: %lld finding(s) on file under %@ — nothing to compare against yet"), Int64(findings.count), path), .ok)
            } else {
                icsSay(emit, String(format: L("no baseline was on file — this run becomes the first, under %@. Run watchprobe again to see what changes"), path), .ok)
            }
            let ledger = findings.map {
                $0.key + "\t" + $0.text
            }.joined(separator: "\n")
            BlacksiteFS.writeText(
                path, text: ledger)
            icsSay(emit, L("the baseline on file now reads exactly as this run does — the ledger lives in the console's own files, and nowhere else"))
        }
    }
}
