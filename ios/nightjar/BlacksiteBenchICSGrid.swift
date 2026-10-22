import Foundation
import Network

// BlacksiteBenchICSGrid — the bench,
// wave six continued: the grid
// expansion. Eighteen more engines
// carrying the ICS bench into every
// sector the plant touches —
// Schweitzer relays on the
// protection side, ROC flow
// computers in the oil field, Fanuc
// and MTConnect on the machine
// floor, Schneider's UMAS, metering
// buses, semiconductor HSMS, the
// SunSpec nameplate, smart-grid
// discovery, and the gateway doors.
// The doctrine is the same and it is
// strict: published identification
// reads only, each verified
// byte-for-byte in Python before it
// was written here — and where a
// frame could not be verified, the
// engine degrades to presence and
// SAYS SO, in its output and in the
// manual. Nothing writes, nothing
// controls, nothing reserves,
// nothing starts or stops. The one
// sanctioned exception to the
// Modbus FC-43-only rule lives here:
// sunspecprobe reads exactly the
// published Common Model nameplate
// block — the block the SunSpec
// standard exists to publish — and
// no other register, anywhere.

extension BlacksiteBench {

    // MARK: SEL — the ID report

    /// Ask a Schweitzer relay's own
    /// terminal for its ID report —
    /// the one page it shows at its
    /// lowest access level. No other
    /// command is sent; if a password
    /// is demanded first, the
    /// conversation ends there.
    static func icsSELCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("selprobe: nothing answers on the terminal door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        var heard = icsAvailable(
            fd, seconds: light ? 1.0 : 2.0,
            cap: 8192)
        _ = icsSendAll(fd,
                       Array("\r\n".utf8))
        heard.append(contentsOf:
            icsAvailable(
                fd, seconds: light
                    ? 1.0 : 2.0,
                cap: 8192))
        let greeting = String(
            bytes: heard,
            encoding: .utf8) ?? ""
        if greeting.lowercased()
            .contains("password") {
            return [
                (String(format: L("selprobe: the relay at %@ asks for a password before anything else — this bench carries none, and the conversation ends at the asking."), host), .out),
            ]
        }
        guard icsSendAll(fd,
                         Array("ID\r\n".utf8))
        else {
            return light ? [] : [
                (String(format: L("selprobe: the ID request at %@ never left."), host), .out),
            ]
        }
        let report = icsAvailable(
            fd, seconds: light ? 1.5 : 3.5,
            cap: 16384)
        let text = String(
            bytes: report,
            encoding: .utf8) ?? ""
        func field(_ key: String)
            -> String? {
            guard let hit = text.range(
                of: key + "=") else {
                return nil
            }
            var value = ""
            for ch in text[
                hit.upperBound...] {
                if ch == "\"" || ch == " "
                    || ch == "\r"
                    || ch == "\n"
                    || ch == "," {
                    break
                }
                value.append(ch)
            }
            return value.isEmpty
                ? nil : value
        }
        var facts: [String] = []
        if let v = field("FID") {
            facts.append(String(
                format: L("FID %@"), v))
        }
        if let v = field("SER") {
            facts.append(String(
                format: L("serial %@"), v))
        }
        if let v = field("PARTNO") {
            facts.append(String(
                format: L("part %@"), v))
        }
        if let v = field("CONFIG") {
            facts.append(String(
                format: L("configuration %@"), v))
        }
        if facts.isEmpty {
            if !report.isEmpty {
                let runs = icsRuns(report)
                return [
                    (String(format: L("selprobe: the terminal at %@ answered in its own words: %@"), host, runs.isEmpty ? icsHex(report.prefix(24)) : runs.joined(separator: " · ")), .out),
                ]
            }
            return light ? [] : [
                (String(format: L("selprobe: the terminal door at %@ answers, but no ID report came — the relay may want a different first word, and none is guessed here."), host), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("selprobe: the relay at %@ shows its ID report — %@."), host, facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("selprobe: the ID report is the one page a SEL relay shows the world at its lowest access level — identification by the maker's own design. The settings behind it were never asked for."),
                .out))
        }
        return lines
    }

    static func selprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 23)
            else {
                icsSay(emit, L("selprobe: give host[:port] — selprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsSELCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: Emerson ROC — opcode 17,
    // the system parameters read

    static func icsROCCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("rocprobe: nothing answers on the ROC door at %@ — or the flow computer speaks serial behind a gateway."), host), .out),
            ]
        }
        defer { close(fd) }
        // Unit 1, group 0, opcode 17 —
        // Read System Parameters —
        // behind the protocol's
        // Modbus-grade checksum.
        var ask: [UInt8] = [0x01, 0x00, 0x11]
        let crc = icsCRCModbus(ask)
        ask.append(UInt8(crc & 0xFF))
        ask.append(UInt8(crc >> 8))
        guard icsSendAll(fd, ask) else {
            return light ? [] : [
                (String(format: L("rocprobe: the knock at %@ never left."), host), .out),
            ]
        }
        let heard = icsAvailable(
            fd, seconds: light ? 1.2 : 3,
            cap: 4096)
        guard heard.count >= 6,
              heard[2] == 0x11 else {
            return light ? [] : [
                (String(format: L("rocprobe: no system-parameters answer from %@ — silence, or a door that is not ROC."), host), .out),
            ]
        }
        // Verify the trailing checksum
        // before believing a byte.
        let body = Array(
            heard.dropLast(2))
        let carried = icsU16LE(
            heard, heard.count - 2)
        guard icsCRCModbus(body)
                == UInt16(carried) else {
            return [
                (String(format: L("rocprobe: an answer came from %@, but its checksum does not hold — reported as noise, not identity."), host), .out),
            ]
        }
        let data = Array(body.dropFirst(3))
        var facts: [String] = []
        if !data.isEmpty {
            facts.append(String(
                format: L("ROC type code %lld"),
                Int64(data[0])))
        }
        let runs = icsRuns(data, minLen: 3)
        if !runs.isEmpty {
            facts.append(contentsOf: runs)
        }
        var lines: [ICSLine] = [
            (String(format: L("rocprobe: the flow computer at %@ answers opcode 17 — %@."), host, facts.isEmpty ? L("a bare answer, its fields unread") : facts.joined(separator: " · ")), .sys),
        ]
        if !light {
            lines.append((
                L("rocprobe: the ROC protocol's system read is published for host software, and base ROC carries no authentication story beyond optional access codes — none was offered, and none stands proven from here either way."),
                .out))
        }
        return lines
    }

    static func rocprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 2000)
            else {
                icsSay(emit, L("rocprobe: give host[:port] — rocprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsROCCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: MTConnect — the agent's
    // own published census

    static func icsXMLAttr(
        _ text: String, key: String)
        -> String? {
        guard let hit = text.range(
            of: key + "=\"") else {
            return nil
        }
        var value = ""
        for ch in text[hit.upperBound...] {
            if ch == "\"" { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value
    }

    static func icsMTConnectCore(
        host: String, port: UInt16,
        light: Bool) -> [ICSLine] {
        guard let url = URL(
            string: "http://\(host):\(port)/probe"),
              let (data, _) = icsFetch(
                url, accept: "application/xml")
        else {
            return light ? [] : [
                (String(format: L("mtconnectprobe: no agent answers at %@ — nothing publishes a /probe there."), host), .out),
            ]
        }
        let xml = String(data: data,
                         encoding: .utf8)
            ?? ""
        guard xml.contains("MTConnect")
                || xml.contains("<Device")
        else {
            return [
                (String(format: L("mtconnectprobe: something at %@ answered HTTP, but its page is not an MTConnect census."), host), .out),
            ]
        }
        var lines: [ICSLine] = []
        if let v = icsXMLAttr(
            xml, key: "MTConnectVersion") {
            lines.append((
                String(format: L("mtconnectprobe: an MTConnect %@ agent answers at %@."), v, host),
                .sys))
        } else {
            lines.append((
                String(format: L("mtconnectprobe: an MTConnect agent answers at %@."), host),
                .sys))
        }
        let segments = xml.components(
            separatedBy: "<Device ")
        var devices = 0
        for segment in segments.dropFirst() {
            devices += 1
            let head = String(
                segment.prefix(4000))
            var facts: [String] = []
            if let v = icsXMLAttr(
                head, key: "name") {
                facts.append(v)
            }
            if let v = icsXMLAttr(
                head, key: "manufacturer") {
                facts.append(String(
                    format: L("maker %@"), v))
            }
            if let v = icsXMLAttr(
                head, key: "model") {
                facts.append(String(
                    format: L("model %@"), v))
            }
            if let v = icsXMLAttr(
                head, key: "serialNumber") {
                facts.append(String(
                    format: L("serial %@"), v))
            }
            if !facts.isEmpty {
                lines.append((
                    String(format: L("mtconnectprobe: device — %@."), facts.joined(separator: ", ")),
                    .out))
            }
            if devices >= 8 {
                lines.append((
                    L("mtconnectprobe: and more devices behind those — the census is the agent's to publish."),
                    .out))
                break
            }
        }
        if !light,
           let url2 = URL(
            string: "http://\(host):\(port)/current"),
           let (data2, _) = icsFetch(
            url2, accept: "application/xml") {
            let xml2 = String(
                data: data2,
                encoding: .utf8) ?? ""
            let streams = xml2.components(
                separatedBy: "<DeviceStream")
                .count - 1
            if streams > 0 {
                lines.append((
                    String(format: L("mtconnectprobe: the agent is streaming %lld device(s) live on /current."), Int64(streams)),
                    .out))
            }
        }
        if !light {
            lines.append((
                L("mtconnectprobe: MTConnect is read-only by the standard's own design — this census is published for any reader, machine serials included, and there is nothing on this door to change."),
                .out))
        }
        return lines
    }

    static func mtconnectprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, _, port) =
                icsResolve(target, 5000)
            else {
                icsSay(emit, L("mtconnectprobe: give host[:port] — mtconnectprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsMTConnectCore(
                    host: host, port: port,
                    light: false))
        }
    }

    // MARK: Fanuc FOCAS — degraded

    static func focasprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 8193)
            else {
                icsSay(emit, L("focasprobe: give host[:port] — focasprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "focasprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("focasprobe: the FOCAS identification frames could not be verified byte-for-byte against the published layout, so no sysinfo read is claimed — only the door's own state, exactly as observed.")))
        }
    }

    // MARK: CODESYS — degraded, three
    // doors (V2 handler, V3 gateway,
    // V3 runtime)

    static func codesysprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 2455)
            else {
                icsSay(emit, L("codesysprobe: give a host — codesysprobe 192.168.1.10"), .err)
                return
            }
            let doors: [(UInt16, String)] = [
                (2455, L("the V2 PLC Handler door")),
                (1217, L("the V3 gateway door")),
                (11740, L("the V3 runtime door")),
            ]
            for (port, label) in doors {
                guard let fd = icsSocket(
                    ip: ip, port: port,
                    timeout: 1.5,
                    name: host) else {
                    continue
                }
                let heard = icsAvailable(
                    fd, seconds: 1.2,
                    cap: 2048)
                close(fd)
                let lines: [ICSLine] = [
                    (String(format: L("codesysprobe: %@ at %@ stands open%@."), label, host, heard.isEmpty ? "" : String(format: L(" and volunteers %lld bytes"), Int64(heard.count))), .sys),
                    (L("codesysprobe: the runtime's device-identification frames could not be verified byte-for-byte against the published layouts, so no identity read is claimed — presence only, stated plainly."), .out),
                ]
                icsPrint(emit, lines)
                return
            }
            icsSay(emit, String(format: L("codesysprobe: no CODESYS door answers at %@ — 2455, 1217 and 11740 all stayed shut."), host))
        }
    }

    // MARK: Schneider UMAS — the
    // identification subfunctions
    // only, riding the Modbus door

    /// One UMAS (FC 0x5A) exchange.
    /// Returns the answer PDU.
    static func icsUMASExchange(
        _ fd: Int32, sub: UInt8)
        -> [UInt8]? {
        let ask = icsMBAP(length: 3)
            + [0x5A, sub]
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 7) else {
            return nil
        }
        let pduLen = icsU16BE(head, 4) - 1
        guard pduLen > 0,
              let pdu = icsReadExact(
                fd, pduLen) else {
            return nil
        }
        return pdu
    }

    static func icsUMASCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("umasprobe: nothing answers on the Modbus door at %@ — UMAS rides it, and it stayed shut."), host), .out),
            ]
        }
        defer { close(fd) }
        // Subfunction 0x01 — the
        // session greeting, published
        // for exactly this.
        guard let hello = icsUMASExchange(
            fd, sub: 0x01) else {
            return light ? [] : [
                (String(format: L("umasprobe: the door at %@ took the UMAS greeting and gave nothing back."), host), .out),
            ]
        }
        if hello.first == 0xDA {
            let code = hello.count > 1
                ? Int64(hello[1]) : -1
            return [
                (String(format: L("umasprobe: %@ refuses the UMAS function outright (exception %lld) — no UMAS stands on this door."), host, code), .ok),
            ]
        }
        guard hello.first == 0x5A else {
            return [
                (String(format: L("umasprobe: whatever answered at %@ is not speaking UMAS: %@"), host, icsHex(hello.prefix(12))), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("umasprobe: UMAS greets on the Modbus door at %@ — the session subfunction answered."), host), .sys),
        ]
        // Subfunction 0x02 — the
        // project information read.
        // The reservation, configuration
        // and start/stop subfunctions
        // are never sent from here.
        if let info = icsUMASExchange(
            fd, sub: 0x02),
           info.first == 0x5A {
            let runs = icsRuns(
                Array(info.dropFirst(2)),
                minLen: 3)
            if !runs.isEmpty {
                lines.append((
                    String(format: L("umasprobe: the project ledger offers — %@."), runs.joined(separator: " · ")),
                    .sys))
            } else {
                lines.append((
                    L("umasprobe: the project read answered with no legible ledger — its bytes are the PLC's own, unread here."),
                    .out))
            }
        }
        if !light {
            lines.append((
                L("umasprobe: UMAS carries the keys to the PLC in the field — project transfers and start/stop ride this same door. This bench sent the two identification subfunctions (0x01, 0x02) and nothing else that exists in the protocol."),
                .err))
        }
        return lines
    }

    static func umasprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("umasprobe: give host[:port] — umasprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsUMASCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: SunSpec — the published
    // nameplate block, and only it

    /// The wave's ONE sanctioned
    /// register read: FC 03 over the
    /// SunSpec Common Model block at
    /// the standard base — maker,
    /// model, options, version,
    /// serial. Seventy registers,
    /// exactly the nameplate, nothing
    /// past it.
    static func icsSunSpecCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("sunspecprobe: nothing answers on the Modbus door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        let ask = icsMBAP(length: 6)
            + [0x03, 0x9C, 0x40,
               0x00, 0x46]
        guard icsSendAll(fd, ask),
              let head = icsReadExact(
                fd, 7) else {
            return light ? [] : [
                (String(format: L("sunspecprobe: the door at %@ took the knock and gave nothing back."), host), .out),
            ]
        }
        let pduLen = icsU16BE(head, 4) - 1
        guard pduLen > 2,
              let pdu = icsReadExact(
                fd, pduLen),
              pdu.first == 0x03 else {
            return light ? [] : [
                (String(format: L("sunspecprobe: the answer from %@ was not a register block — no nameplate read is claimed."), host), .out),
            ]
        }
        let byteCount = Int(pdu[1])
        guard byteCount >= 140,
              pdu.count >= 2 + 140 else {
            return [
                (String(format: L("sunspecprobe: the block from %@ arrived short (%lld bytes) — no nameplate read is claimed."), host, Int64(byteCount)), .out),
            ]
        }
        var regs: [Int] = []
        var at = 2
        while at + 1 < 2 + 140 {
            regs.append(icsU16BE(pdu, at))
            at += 2
        }
        guard regs.count >= 70,
              regs[0] == 0x5375,
              regs[1] == 0x6E53 else {
            return [
                (String(format: L("sunspecprobe: no SunSpec nameplate stands at the standard base (40001) behind %@ — the 'SunS' mark is absent, and the bench does not go hunting other bases."), host), .out),
            ]
        }
        guard regs[2] == 1 else {
            return [
                (String(format: L("sunspecprobe: the SunSpec mark stands at %@, but the first block names model %lld, not the Common Model — its nameplate is not read here."), host, Int64(regs[2])), .out),
            ]
        }
        func text(_ range: Range<Int>)
            -> String {
            var bytes: [UInt8] = []
            for value in regs[range] {
                bytes.append(UInt8(
                    value >> 8))
                bytes.append(UInt8(
                    value & 0xFF))
            }
            return icsClean(bytes[...])
        }
        var facts: [String] = []
        let maker = text(4..<20)
        if !maker.isEmpty {
            facts.append(String(
                format: L("maker %@"), maker))
        }
        let model = text(20..<36)
        if !model.isEmpty {
            facts.append(String(
                format: L("model %@"), model))
        }
        let options = text(36..<44)
        if !options.isEmpty {
            facts.append(String(
                format: L("options %@"),
                options))
        }
        let version = text(44..<52)
        if !version.isEmpty {
            facts.append(String(
                format: L("version %@"),
                version))
        }
        let serial = text(52..<68)
        if !serial.isEmpty {
            facts.append(String(
                format: L("serial %@"), serial))
        }
        var lines: [ICSLine] = [
            (String(format: L("sunspecprobe: the SunSpec nameplate at %@ reads — %@."), host, facts.isEmpty ? L("a plate with nothing legible on it") : facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("sunspecprobe: this block is the one register read the whole wave allows itself, bounded to the nameplate the SunSpec standard exists to publish — seventy registers at the standard base, and not one register past them."),
                .out))
        }
        return lines
    }

    static func sunspecprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 502)
            else {
                icsSay(emit, L("sunspecprobe: give host[:port] — sunspecprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsSunSpecCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: M-Bus — wake one meter,
    // read its nameplate, take no
    // readings

    static func icsMBUSCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("mbusprobe: nothing answers on the gateway door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // SND_NKE to primary address 0
        // — the bus's own wake word.
        guard icsSendAll(fd, [
            0x10, 0x40, 0x00, 0x40, 0x16])
        else {
            return light ? [] : [
                (String(format: L("mbusprobe: the wake word at %@ never left."), host), .out),
            ]
        }
        let ack = icsAvailable(
            fd, seconds: light ? 1.2 : 2.2,
            cap: 64)
        guard ack.first == 0xE5 else {
            return light ? [] : [
                (String(format: L("mbusprobe: no meter acknowledges at primary address 0 behind %@ — other addresses are not swept: that would be a harvest, not a knock."), host), .out),
            ]
        }
        // REQ_UD2 — one request for the
        // answering meter's frame,
        // whose FIXED header is the
        // nameplate. The variable
        // records behind it — the
        // actual readings — are not
        // decoded and not wanted.
        guard icsSendAll(fd, [
            0x10, 0x5B, 0x00, 0x5B, 0x16]),
              let head = icsReadExact(
                fd, 4),
              head[0] == 0x68,
              head[1] == head[2],
              head[3] == 0x68 else {
            return [
                (String(format: L("mbusprobe: a meter woke behind %@, but its frame did not follow — the nameplate stays unread."), host), .out),
            ]
        }
        let len = Int(head[1])
        guard len >= 11,
              let rest = icsReadExact(
                fd, len + 2) else {
            return [
                (String(format: L("mbusprobe: the frame from %@ broke off mid-way."), host), .out),
            ]
        }
        let frame = head + rest
        // Checksum: the sum of the
        // payload bytes (C through the
        // last data byte), mod 256,
        // carried just before the stop.
        var sum = 0
        for byte in frame[4..<(4 + len)] {
            sum += Int(byte)
        }
        guard sum & 0xFF
                == Int(frame[4 + len]),
              frame[4 + len + 1] == 0x16
        else {
            return [
                (String(format: L("mbusprobe: the frame from %@ fails its own checksum — reported as noise, not identity."), host), .out),
            ]
        }
        let ci = frame[6]
        guard ci == 0x72 else {
            return [
                (String(format: L("mbusprobe: the meter behind %@ answered with CI 0x%02llX — not the fixed-header shape, so its nameplate is not read here."), host, Int64(ci)), .out),
            ]
        }
        var serial = ""
        for idx in [10, 9, 8, 7] {
            serial += String(
                format: "%02llX",
                Int64(frame[idx]))
        }
        let word = icsU16LE(frame, 11)
        var maker = ""
        for shift in [10, 5, 0] {
            let code = (word >> shift)
                & 0x1F
            if code >= 1, code <= 26,
               let scalar = UnicodeScalar(
                64 + code) {
                maker.append(
                    Character(scalar))
            }
        }
        let version = Int64(frame[13])
        let mediumCode = Int(frame[14])
        let mediums: [Int: String] = [
            0: L("an unlisted medium"),
            1: L("oil"), 2: L("electricity"),
            3: L("gas"), 4: L("heat"),
            5: L("steam"),
            6: L("hot water"),
            7: L("water"),
            8: L("a heat-cost allocator"),
        ]
        let medium = mediums[mediumCode]
            ?? String(format: L("medium %lld"), Int64(mediumCode))
        var lines: [ICSLine] = [
            (String(format: L("mbusprobe: behind %@, the meter at address 0 names itself — serial %@, maker %@, version %lld, metering %@."), host, serial, maker.isEmpty ? L("unread") : maker, version, medium), .sys),
        ]
        if !light {
            lines.append((
                L("mbusprobe: the nameplate only — the meter's readings were not decoded, and no other address was woken. Identification is a knock; a harvest would be a different tool."),
                .out))
        }
        return lines
    }

    static func mbusprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 10001)
            else {
                icsSay(emit, L("mbusprobe: give host[:port] — mbusprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsMBUSCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: HSMS / SECS — Select, then
    // S1F1 / S1F13, the are-you-there
    // handshake and nothing else

    /// Read one length-prefixed HSMS
    /// message (4 length bytes + body).
    static func icsSECSRead(
        _ fd: Int32) -> [UInt8]? {
        guard let head = icsReadExact(
            fd, 4) else {
            return nil
        }
        let count = icsU32BE(head, 0)
        guard count >= 10,
              count <= 1_000_000,
              let body = icsReadExact(
                fd, count) else {
            return nil
        }
        return head + body
    }

    /// Walk ONE SECS-II item starting
    /// at `start`; returns the ASCII
    /// texts found inside it and the
    /// index just past it. Lists
    /// recurse by their item count;
    /// anything that does not parse
    /// ends the walk honestly.
    static func icsSECSWalk(
        _ body: [UInt8], _ start: Int)
        -> ([String], Int) {
        guard start < body.count else {
            return ([], start)
        }
        let head = body[start]
        let format = head >> 2
        let lol = Int(head & 0x03)
        guard lol >= 1,
              start + 1 + lol <= body.count
        else {
            return ([], body.count)
        }
        var length = 0
        for k in 0..<lol {
            length = length * 256
                + Int(body[start + 1 + k])
        }
        var at = start + 1 + lol
        if format == 0 {
            var found: [String] = []
            for _ in 0..<length {
                let (texts, next) =
                    icsSECSWalk(body, at)
                found.append(
                    contentsOf: texts)
                at = next
                if at >= body.count {
                    break
                }
            }
            return (found, at)
        }
        guard at + length <= body.count
        else {
            return ([], body.count)
        }
        if format == 0x10 {
            let text = icsClean(
                body[at..<(at + length)])
            return (text.isEmpty
                ? [] : [text],
                    at + length)
        }
        return ([], at + length)
    }

    static func icsSECSStrings(
        _ body: [UInt8]) -> [String] {
        icsSECSWalk(body, 0).0
    }

    static func icsSECSCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 4, name: host)
        else {
            return light ? [] : [
                (String(format: L("secsprobe: nothing answers on the HSMS door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        // Select.req — the session's
        // published opening word:
        // session 0, SType 1 at header
        // byte nine, system bytes 1.
        let select: [UInt8] = [
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x01, 0x00, 0x00,
            0x00, 0x01,
        ]
        guard icsSendAll(fd, select),
              let hello = icsSECSRead(fd),
              hello.count == 14,
              hello[9] == 0x02 else {
            return light ? [] : [
                (String(format: L("secsprobe: the door at %@ is open, but no Select answer came — HSMS is not spoken here, or the equipment waits as the passive side."), host), .out),
            ]
        }
        // Select.rsp carries its status
        // in the third header byte.
        let selectCode = Int64(hello[7])
        guard selectCode == 0 else {
            return [
                (String(format: L("secsprobe: %@ refused the HSMS session at the door (select status %lld) — the conversation ends at the refusal, as it should."), host, selectCode), .out),
            ]
        }
        // S1F1 — Are You There. The
        // reply is the equipment's
        // name and revision, published
        // by the standard for exactly
        // this exchange.
        let s1f1: [UInt8] = [
            0x00, 0x00, 0x00, 0x0A,
            0x00, 0x00, 0x81, 0x01,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x01,
        ]
        var identity: [String] = []
        if icsSendAll(fd, s1f1),
           let answer = icsSECSRead(fd),
           answer.count > 14,
           answer[6] == 0x01,
           answer[7] == 0x02 {
            identity = icsSECSStrings(
                Array(answer.dropFirst(14)))
        }
        if identity.isEmpty, !light {
            // S1F13 — Establish
            // Communications. By the
            // standard's own table the
            // REQUEST carries the
            // requester's model and
            // revision (this bench names
            // itself, plainly); the S1F14
            // answer carries the
            // equipment's.
            let s1f13: [UInt8] = [
                0x00, 0x00, 0x00, 0x1B,
                0x00, 0x00, 0x81, 0x0D,
                0x00, 0x00, 0x00, 0x00,
                0x00, 0x02, 0x01, 0x02,
                0x41, 0x08, 0x6E, 0x69,
                0x67, 0x68, 0x74, 0x6A,
                0x61, 0x72, 0x41, 0x03,
                0x31, 0x2E, 0x30,
            ]
            if icsSendAll(fd, s1f13),
               let answer = icsSECSRead(fd),
               answer.count > 14,
               answer[6] == 0x01,
               answer[7] == 0x0E {
                identity = icsSECSStrings(
                    Array(answer.dropFirst(14)))
            }
        }
        var lines: [ICSLine] = []
        if identity.isEmpty {
            lines.append((
                String(format: L("secsprobe: the equipment at %@ selected and answered — but offered no legible name or revision in the handshake."), host),
                .sys))
        } else {
            lines.append((
                String(format: L("secsprobe: the equipment at %@ names itself in the handshake — %@."), host, identity.joined(separator: " · ")),
                .sys))
        }
        if !light {
            lines.append((
                L("secsprobe: HSMS carries no authentication on this door — the Select and the are-you-there are the whole conversation here. No other stream or function was sent; the fab's recipes were never approached."),
                .out))
        }
        return lines
    }

    static func secsprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 5000)
            else {
                icsSay(emit, L("secsprobe: give host[:port] — secsprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsSECSCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: PTP — a management GET of
    // the clock's own description

    static func icsPTPCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        // The management GET, laid out
        // field by field: 34-byte
        // header (management type,
        // version 2, length 53, source
        // identity ...1 port 1), the
        // all-clocks target, hops and
        // action GET, then the
        // MANAGEMENT TLV naming
        // CLOCK_DESCRIPTION.
        let question: [UInt8] =
            [0x0D, 0x02, 0x00, 0x35]
            + [UInt8](repeating: 0,
                      count: 16)
            + [0x00, 0x00, 0x00, 0x00,
               0x00, 0x00, 0x00, 0x01,
               0x00, 0x01]
            + [UInt8](repeating: 0,
                      count: 4)
            + [UInt8](repeating: 0xFF,
                      count: 8)
            + [0xFF, 0xFF]
            + [0x00, 0x00, 0x00]
            + [0x00, 0x01, 0x00, 0x02,
               0x00, 0x02]
        guard let heard = icsUDPExchange(
            ip: ip, port: port,
            packet: question,
            wait: light ? 1.0 : 2.0,
            cap: 2048),
              heard.count >= 55,
              heard[0] & 0x0F == 0x0D,
              icsU16BE(heard, 47) == 0x0001,
              icsU16BE(heard, 51) == 0x0002
        else {
            return light ? [] : [
                (String(format: L("ptpprobe: no clock at %@ answered the management question — PTP's management plane is off, elsewhere, or the clock answers only its grandmaster."), host), .out),
            ]
        }
        // Walk the CLOCK_DESCRIPTION
        // value: clock type, then the
        // length-prefixed texts and
        // addresses, bounds-checked at
        // every step.
        var at = 53
        func take(_ count: Int) -> [UInt8]? {
            guard count >= 0,
                  at + count <= heard.count
            else {
                return nil
            }
            let slice = Array(
                heard[at..<(at + count)])
            at += count
            return slice
        }
        func takeText() -> String? {
            guard let head = take(1) else {
                return nil
            }
            guard let body = take(
                Int(head[0])) else {
                return nil
            }
            let text = icsClean(body[...])
            return text.isEmpty ? nil : text
        }
        func takeAddress() -> Bool {
            guard take(2) != nil,
                  let lenBytes = take(2)
            else {
                return false
            }
            let count = icsU16BE(
                [0, 0] + lenBytes, 2)
            return take(count) != nil
        }
        _ = take(1)                    // clock type
        _ = takeText()                 // physical layer
        var ok = takeAddress()
        var oui = ""
        var product = ""
        var revision = ""
        if ok {
            ok = takeAddress()
        }
        if ok, let bytes = take(3) {
            oui = bytes.map {
                String(format: "%02llX",
                       Int64($0))
            }.joined(separator: ":")
            product = takeText() ?? ""
            revision = takeText() ?? ""
        }
        var facts: [String] = []
        if !product.isEmpty {
            facts.append(product)
        }
        if !revision.isEmpty {
            facts.append(String(
                format: L("revision %@"),
                revision))
        }
        if !oui.isEmpty {
            facts.append(String(
                format: L("maker OUI %@"), oui))
        }
        var lines: [ICSLine] = [
            (String(format: L("ptpprobe: the clock at %@ describes itself — %@."), host, facts.isEmpty ? L("a description with nothing legible in it") : facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("ptpprobe: one management GET of the published description dataset — the clock's time was never set, stepped, or asked to move; a plant's clock is read here the way its own management station reads it."),
                .out))
        }
        return lines
    }

    static func ptpprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 320)
            else {
                icsSay(emit, L("ptpprobe: give host[:port] — ptpprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsPTPCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: SEP2 — IEEE 2030.5
    // discovery, the DER front door

    static func icsXMLElement(
        _ xml: String, tag: String)
        -> String? {
        guard let open = xml.range(
            of: "<" + tag + ">") else {
            return nil
        }
        let tail = open.upperBound..<xml.endIndex
        guard let close = xml.range(
            of: "</" + tag + ">",
            range: tail) else {
            return nil
        }
        let value = String(xml[
            open.upperBound..<close.lowerBound])
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func icsSEP2Core(
        host: String, port: UInt16,
        light: Bool) -> [ICSLine] {
        guard let url = URL(
            string: "https://\(host):\(port)/dcap"),
              let (data, _) = icsFetch(
                url,
                accept: "application/sep+xml")
        else {
            return light ? [] : [
                (String(format: L("sep2probe: no capability document answers at %@ — the door stayed shut, or its certificate story stopped the fetch: this bench's TLS cannot pin the utility certificate the standard wants, and from here the two look the same."), host), .out),
            ]
        }
        let xml = String(data: data,
                         encoding: .utf8)
            ?? ""
        guard xml.contains(
            "DeviceCapability") else {
            return [
                (String(format: L("sep2probe: something at %@ answered TLS, but its page is not a SEP2 capability document."), host), .out),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("sep2probe: a SEP2 server answers at %@ and publishes its capability document."), host), .sys),
        ]
        if !light,
           let marker = xml.range(
            of: "EndDeviceListLink"),
           let href = icsXMLAttr(
            String(xml[marker.lowerBound...]
                .prefix(300)),
            key: "href"),
           let listURL = URL(
            string: "https://\(host):\(port)"
                + href),
           let (data2, _) = icsFetch(
            listURL,
            accept: "application/sep+xml") {
            let xml2 = String(
                data: data2,
                encoding: .utf8) ?? ""
            let segments = xml2.components(
                separatedBy: "<EndDevice>")
            var shown = 0
            for segment in segments
                .dropFirst() {
                let head = String(
                    segment.prefix(4000))
                var facts: [String] = []
                if let v = icsXMLElement(
                    head, tag: "manufacturer") {
                    facts.append(String(
                        format: L("maker %@"),
                        v))
                }
                if let v = icsXMLElement(
                    head,
                    tag: "modelNumber") {
                    facts.append(String(
                        format: L("model %@"), v))
                }
                if let v = icsXMLElement(
                    head,
                    tag: "serialNumber") {
                    facts.append(String(
                        format: L("serial %@"),
                        v))
                }
                if let v = icsXMLElement(
                    head, tag: "swVersion") {
                    facts.append(String(
                        format: L("firmware %@"),
                        v))
                }
                if !facts.isEmpty {
                    lines.append((
                        String(format: L("sep2probe: end device — %@."), facts.joined(separator: ", ")),
                        .out))
                    shown += 1
                    if shown >= 3 { break }
                }
            }
        }
        if !light {
            lines.append((
                L("sep2probe: IEEE 2030.5 publishes these nameplates by design — discovery is the standard's open front door. The control and curtailment functions behind it were never approached."),
                .out))
        }
        return lines
    }

    static func sep2probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, _, port) =
                icsResolve(target, 443)
            else {
                icsSay(emit, L("sep2probe: give host[:port] — sep2probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, icsSEP2Core(
                host: host, port: port,
                light: false))
        }
    }

    // MARK: Lantronix — the published
    // discovery knock

    static func icsLantronixCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let heard = icsUDPExchange(
            ip: ip, port: port,
            packet: [0x00, 0x00, 0x00,
                     0xF6],
            wait: light ? 1.0 : 2.0,
            cap: 2048),
              heard.count >= 44,
              heard[4] == 0xF7 else {
            return light ? [] : [
                (String(format: L("lantronixprobe: no gateway answers the discovery knock at %@."), host), .out),
            ]
        }
        let mac = heard[8..<14].map {
            String(format: "%02llX",
                   Int64($0))
        }.joined(separator: ":")
        let typeCode = icsU16BE(heard, 24)
        let version = icsU16BE(heard, 40)
        let model = icsRuns(
            Array(heard.dropFirst(44)),
            minLen: 3).first ?? ""
        var facts: [String] = [
            String(format: L("MAC %@"), mac),
            String(format: L("hardware type 0x%04llX"), Int64(typeCode)),
            String(format: L("firmware %lld.%lld"), Int64(version >> 8), Int64(version & 0xFF)),
        ]
        if !model.isEmpty {
            facts.append(String(
                format: L("calling itself %@"),
                model))
        }
        var lines: [ICSLine] = [
            (String(format: L("lantronixprobe: a serial gateway answers at %@ — %@."), host, facts.joined(separator: ", ")), .sys),
        ]
        if !light {
            lines.append((
                L("lantronixprobe: the discovery answer rides in the clear by the maker's design — the serial plant behind this door inherits its reach, which is the finding worth carrying home."),
                .out))
        }
        return lines
    }

    static func lantronixprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 30718)
            else {
                icsSay(emit, L("lantronixprobe: give host[:port] — lantronixprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsLantronixCore(
                    host: host, ip: ip,
                    port: port, light: false))
        }
    }

    // MARK: DirectLOGIC HAP — degraded
    // (UDP 28784)

    static func happrobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 28784)
            else {
                icsSay(emit, L("happrobe: give host[:port] — happrobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsUDPEmptyCore(
                    verb: "happrobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("happrobe: the ECOM/HAP identification frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — an empty knock and whatever the PLC volunteers, exactly as observed.")))
        }
    }

    // MARK: Unitronics PCOM — degraded

    static func pcomprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 20256)
            else {
                icsSay(emit, L("pcomprobe: give host[:port] — pcomprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "pcomprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("pcomprobe: the PCOM identification frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — only the door's own state, exactly as observed.")))
        }
    }

    // MARK: Phoenix PC Worx — degraded

    static func pcworxprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 1962)
            else {
                icsSay(emit, L("pcworxprobe: give host[:port] — pcworxprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "pcworxprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("pcworxprobe: the PC Worx identification service's frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — only the door's own state, exactly as observed.")))
        }
    }

    // MARK: LonWorks/IP — degraded
    // (UDP 1628)

    static func lonprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 1628)
            else {
                icsSay(emit, L("lonprobe: give host[:port] — lonprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsUDPEmptyCore(
                    verb: "lonprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("lonprobe: the EIA-852 channel-identification frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — an empty knock and whatever the router volunteers, exactly as observed.")))
        }
    }

    // MARK: FOUNDATION Fieldbus HSE —
    // degraded (UDP 10805)

    static func ffprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 10805)
            else {
                icsSay(emit, L("ffprobe: give host[:port] — ffprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsUDPEmptyCore(
                    verb: "ffprobe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("ffprobe: the HSE announcement frame could not be verified byte-for-byte against the published layout, so no identification read is claimed — an empty knock and whatever the linking device volunteers, exactly as observed.")))
        }
    }

    // MARK: ANSI C12.22 — degraded

    static func c1222probe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 1153)
            else {
                icsSay(emit, L("c1222probe: give host[:port] — c1222probe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                icsConnectOnlyCore(
                    verb: "c1222probe",
                    host: host, ip: ip,
                    port: port, light: false,
                    note: L("c1222probe: the C12.22 identification read could not be verified byte-for-byte against the published APDU layout, so no identification read is claimed — only the door's own state, exactly as observed.")))
        }
    }
}
