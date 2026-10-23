import Foundation
import Network

// BlacksiteBenchBuild — the bench,
// wave eleven: the building's own
// systems. Ten engines for the gear
// that heats, guards, and watches
// over a building: its temperature
// sensors and thermostats, its alarm
// and access panels, its cameras'
// discovery, and — behind the
// hardest line on this bench — its
// fire panels. The doctrine is the
// house's own, held tighter here
// than anywhere but the plant
// floor: one knock, read, grade.
// The reads are the published ones
// and no others — a BACnet ReadProperty
// or Who-Is, an SNMP GET, an HTTP GET
// of a documented read page, a banner
// a door volunteers, a WS-Discovery
// Probe. Nothing here writes a
// setpoint, arms or disarms a panel,
// or tries a password or a default
// code: posture is graded from
// exposure and banners ONLY. And
// for fire the line is absolute —
// the fire engines read a device's
// NAMEPLATE and nothing else. They
// never read alarm or zone state,
// and they send nothing that can
// test, acknowledge, silence, or
// reset. A nameplate is a claim the
// device makes about itself, read
// aloud; an answer that will not
// parse grades down, never up.

extension BlacksiteBench {

    // MARK: BACnet — raw values, kept
    // unpainted so numbers stay numbers

    /// One application-tagged value
    /// out of a BACnet reply: the tag
    /// number and its bytes, raw.
    struct BuildBACValue {
        var tag: Int
        var bytes: [UInt8]
    }

    /// Signed read of four big-endian
    /// bytes — the OWServer ledger and
    /// the BACnet walks both want it.
    static func buildI32(
        _ b: [UInt8], _ o: Int) -> Int {
        let n = icsU32BE(b, o)
        return n > 0x7FFFFFFF
            ? n - 0x100000000 : n
    }

    /// The canned Who-Is, and the
    /// device object id out of the
    /// I-Am that answers — the ICS
    /// wave's knock, shared.
    static func buildBACWhoIs(
        ip: String, port: UInt16,
        wait: Double) -> Int? {
        let whois: [UInt8] = [
            0x81, 0x0A, 0x00, 0x08,
            0x01, 0x00, 0x10, 0x08,
        ]
        guard let iam = icsUDPExchange(
            ip: ip, port: port,
            packet: whois, wait: wait,
            cap: 4096) else {
            return nil
        }
        var scan = 4
        while scan + 4 < iam.count {
            if iam[scan] == 0xC4 {
                return icsU32BE(iam, scan + 1)
            }
            scan += 1
        }
        return nil
    }

    /// Read one property and return
    /// every application value inside
    /// the reply's [3] frame, raw —
    /// the walk icsBACReadProp makes,
    /// kept unpainted. Scalar reads
    /// find one value; the device
    /// object-list finds a ledger of
    /// object identifiers. nil when
    /// the device refuses or is mute.
    static func buildBACRead(
        ip: String, port: UInt16,
        objid: Int, invoke: UInt8,
        prop: UInt8) -> [BuildBACValue]? {
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
            cap: 8192),
              reply.count > 6 else {
            return nil
        }
        // BVLL + NPDU walk, the ICS
        // reader's own steps.
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
        // invoke, service 0x0C. An
        // Error (0x50) or Reject is a
        // refusal, and reads as nil.
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
        // application-tagged values,
        // gathered until the closing
        // tag or the packet's end.
        guard pos < reply.count,
              reply[pos] == 0x3E else {
            return nil
        }
        pos += 1
        var values: [BuildBACValue] = []
        while pos < reply.count,
              reply[pos] != 0x3F {
            guard let tv = icsBACTag(
                    reply, &pos),
                  pos + tv.len <= reply.count
            else {
                return values.isEmpty
                    ? nil : values
            }
            values.append(BuildBACValue(
                tag: tv.num,
                bytes: Array(
                    reply[pos..<(pos
                        + tv.len)])))
            pos += tv.len
        }
        return values
    }

    /// A BACnet value as a number:
    /// Real, Double, unsigned,
    /// enumerated and signed tags.
    /// Present values arrive as Real;
    /// the units property arrives as
    /// an enumerated code.
    static func buildBACNumber(
        _ value: BuildBACValue) -> Double? {
        switch value.tag {
        case 4:
            guard value.bytes.count == 4
            else { return nil }
            let bits = UInt32(clamping:
                icsU32BE(value.bytes, 0))
            return Double(Float(
                bitPattern: bits))
        case 5:
            guard value.bytes.count == 8
            else { return nil }
            let hi = UInt64(UInt32(
                clamping: icsU32BE(
                    value.bytes, 0)))
            let lo = UInt64(UInt32(
                clamping: icsU32BE(
                    value.bytes, 4)))
            return Double(bitPattern:
                hi << 32 | lo)
        case 2, 9:
            var n = 0
            for byte in value.bytes {
                n = n << 8 | Int(byte)
            }
            return Double(n)
        case 3:
            guard !value.bytes.isEmpty
            else { return nil }
            var n = Int(value.bytes[0])
            if n > 127 { n -= 256 }
            for byte in value.bytes
                .dropFirst() {
                n = n << 8 | Int(byte)
            }
            return Double(n)
        default:
            return nil
        }
    }

    /// The engineering-units word for
    /// a BACnet units code — only the
    /// codes this reader states with
    /// confidence; any other code is
    /// printed as a code, never named
    /// by guesswork.
    static func buildBACUnitsName(
        _ code: Int) -> String {
        switch code {
        case 28:
            return "%"
        case 29:
            return "% relative humidity"
        case 62:
            return "°C"
        case 63:
            return "°F"
        case 64:
            return "K"
        default:
            return String(format: L("units code %lld (the standard names it; this reader prints the code)"), Int64(code))
        }
    }

    /// A number as the device would
    /// print it: integers whole,
    /// fractions to two places with
    /// the tail trimmed.
    static func buildNum(
        _ value: Double) -> String {
        if value == value.rounded(),
           abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(
            format: "%.2f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }

    /// A door, knocked the census
    /// way: connect, and close.
    static func buildDoorOpen(
        ip: String, port: UInt16) -> Bool {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: 0.7, name: nil)
        else { return false }
        close(fd)
        return true
    }

    /// The /24 a census walks: the
    /// target's own prefix when one
    /// is given (an address or a
    /// prefix both read), else this
    /// phone's wire. primecensus'
    /// shape, kept.
    static func buildPrefix(
        _ target: String) -> String? {
        let trimmed = target
            .trimmingCharacters(
                in: .whitespaces)
        if !trimmed.isEmpty {
            let parts = trimmed.split(
                separator: ".")
            guard parts.count >= 3
            else { return nil }
            return parts[0..<3].joined(
                separator: ".")
        }
        guard let own = BlacksiteNet
            .primaryIPv4() else {
            return nil
        }
        let parts = own.split(
            separator: ".")
        guard parts.count >= 3
        else { return nil }
        return parts[0..<3].joined(
            separator: ".")
    }

    // MARK: thermoprobe — the
    // temperatures a building keeps

    /// One analog point, read: its
    // object word, its own name, its
    // present value (or nil when the
    // value would not read), and the
    // units the device itself claims.
    struct BuildThermoReading {
        var object: String
        var name: String
        var value: Double?
        var units: String
    }

    /// The temperature board, built
    /// whole from what was read —
    /// a pure function of the
    /// readings, so the Gauntlet can
    /// grade it without a wire.
    static func buildThermoBoard(
        host: String,
        plate: String?,
        readings: [BuildThermoReading],
        bacnetAnswered: Bool) -> [ICSLine] {
        var lines: [ICSLine] = []
        if let plate = plate {
            lines.append((plate, .sys))
        }
        guard bacnetAnswered else {
            lines.append((
                String(format: L("thermoprobe: no BACnet device at %@ raised its hand to a Who-Is."), host),
                .out))
            return lines
        }
        if readings.isEmpty {
            lines.append((
                String(format: L("thermoprobe: the device at %@ names no analog points this reader may see — its object list is shut, or holds none."), host),
                .out))
            return lines
        }
        var read = 0
        for reading in readings {
            if let value = reading.value {
                read += 1
                lines.append((
                    String(format: L("thermoprobe: %@ '%@' reads %@ %@"), reading.object, reading.name, buildNum(value), reading.units),
                    .out))
            } else {
                lines.append((
                    String(format: L("thermoprobe: %@ '%@' stands on the list, but its present value would not read."), reading.object, reading.name),
                    .out))
            }
        }
        if read > 0 {
            lines.append((
                L("thermoprobe: the headline — live process values off this device were read with no credential of any kind. Classic BACnet/IP authenticates no one; that is the grade, whoever owns the building."),
                .err))
        }
        return lines
    }

    /// The BACnet half of the
    /// battery: Who-Is, the device
    /// nameplate, then up to eight
    /// analog points off the device's
    /// own object list — present
    /// value and claimed units each.
    static func buildThermoBACnet(
        host: String, ip: String,
        port: UInt16) -> [ICSLine] {
        guard let objid = buildBACWhoIs(
            ip: ip, port: port, wait: 2.4)
        else {
            return buildThermoBoard(
                host: host, plate: nil,
                readings: [],
                bacnetAnswered: false)
        }
        var facts: [String] = []
        let props: [(UInt8, String)] = [
            (77, L("names itself")),
            (121, L("vendor")),
            (70, L("model")),
        ]
        var invoke: UInt8 = 11
        for (prop, label) in props {
            if let value = icsBACReadProp(
                ip: ip, port: port,
                objid: objid,
                invoke: invoke, prop: prop),
               !value.isEmpty {
                facts.append(String(
                    format: L("%@ %@"),
                    label, value))
            }
            invoke += 1
        }
        var plate: String? = nil
        if !facts.isEmpty {
            plate = String(
                format: L("thermoprobe: the device at %@ — %@."), host, facts.joined(separator: ", "))
        }
        var readings: [BuildThermoReading] = []
        if let list = buildBACRead(
            ip: ip, port: port,
            objid: objid, invoke: 21,
            prop: 76) {
            var points: [(type: Int,
                           instance: Int,
                           oid: Int)] = []
            for value in list
            where value.tag == 12
                    && value.bytes.count == 4 {
                let oid = icsU32BE(
                    value.bytes, 0)
                let type = oid >> 22
                if type == 0 || type == 2 {
                    points.append((
                        type,
                        oid & 0x3FFFFF, oid))
                }
            }
            for point in points.prefix(8) {
                let kind = point.type == 0
                    ? L("analog-input")
                    : L("analog-value")
                let name = icsBACReadProp(
                    ip: ip, port: port,
                    objid: point.oid,
                    invoke: 22, prop: 77)
                    ?? ""
                var value: Double? = nil
                if let pv = buildBACRead(
                    ip: ip, port: port,
                    objid: point.oid,
                    invoke: 23, prop: 85)?
                    .first {
                    value = buildBACNumber(pv)
                }
                var units = L("no units claimed")
                if let uv = buildBACRead(
                    ip: ip, port: port,
                    objid: point.oid,
                    invoke: 24, prop: 117)?
                    .first,
                   let code = buildBACNumber(
                    uv) {
                    units = buildBACUnitsName(
                        Int(code))
                }
                readings.append(
                    BuildThermoReading(
                        object: "\(kind) "
                            + "\(point.instance)",
                        name: name.isEmpty
                            ? L("unnamed")
                            : name,
                        value: value,
                        units: units))
            }
        }
        return buildThermoBoard(
            host: host, plate: plate,
            readings: readings,
            bacnetAnswered: true)
    }

    /// Sensor readings out of a
    /// sensor page's XML — the HWg
    /// Entry ledger, and any element
    /// whose name speaks of heat or
    /// damp and whose text is a
    /// number (the ControlByWeb
    /// shape). A pure scrape: what
    /// does not parse is not read.
    static func buildScrapeSensors(
        _ xml: String)
        -> [(name: String, value: String,
             units: String?)] {
        var out: [(name: String,
                   value: String,
                   units: String?)] = []
        var seen = Set<String>()
        for block in wireBlocks(
            xml, "Entry") {
            guard let name = streetTag(
                    block, "Name"),
                  let value = streetTag(
                    block, "Value"),
                  Double(value) != nil,
                  !seen.contains(name)
            else { continue }
            seen.insert(name)
            out.append((name, value,
                        streetTag(
                            block, "Units")))
        }
        // The flat shape: walk the
        // elements one by one.
        var cursor = xml.startIndex
        while let open = xml.range(
            of: "<", range:
                cursor..<xml.endIndex),
              let close = xml.range(
                of: ">",
                range: open.upperBound..<xml.endIndex) {
            let raw = xml[open.upperBound..<close.lowerBound]
                .trimmingCharacters(
                    in: .whitespaces)
            cursor = close.upperBound
            if raw.hasPrefix("/")
                || raw.hasPrefix("?")
                || raw.hasPrefix("!") {
                continue
            }
            let name = raw.split(
                separator: " ").first
                .map(String.init) ?? ""
            let lowered = name.lowercased()
            guard lowered.contains("temp")
                    || lowered.contains(
                        "humid")
            else { continue }
            guard let end = xml.range(
                of: "<", range:
                    cursor..<xml.endIndex)
            else { break }
            let text = xml[cursor..<end.lowerBound]
                .trimmingCharacters(
                    in: .whitespaces)
            if Double(text) != nil,
               !seen.contains(name) {
                seen.insert(name)
                out.append((name, text, nil))
            }
            cursor = end.lowerBound
        }
        return out.sorted {
            $0.name < $1.name
        }
    }

    /// The web half of the battery:
    /// the documented sensor pages
    /// (ControlByWeb's /state.xml,
    /// HWg-STE's /values.xml), asked
    /// only when the web door stands
    /// open, and read with no login.
    static func buildThermoHTTP(
        host: String, ip: String)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: 80,
            timeout: 1.2, name: host)
        else { return [] }
        close(fd)
        for path in ["/state.xml",
                     "/values.xml"] {
            guard let url = URL(
                string: "http://"
                    + host + path)
            else { continue }
            guard let (data, http) =
                icsFetch(url),
                  http.statusCode == 200
            else { continue }
            let xml = String(
                data: data,
                encoding: .utf8) ?? ""
            let sensors = buildScrapeSensors(
                xml)
            if sensors.isEmpty {
                continue
            }
            var lines: [ICSLine] = [(
                String(format: L("thermoprobe: the sensor page at %@%@ answers with no login at all:"), host, path),
                .sys)]
            for sensor in sensors
                .prefix(12) {
                var line = String(
                    format: L("thermoprobe: '%@' reads %@"), sensor.name, sensor.value)
                if let units = sensor.units,
                   !units.isEmpty {
                    line += " " + units
                }
                lines.append((line, .out))
            }
            lines.append((
                L("thermoprobe: a building's temperatures on an open web page — the grade writes itself."),
                .err))
            return lines
        }
        return []
    }

    static func thermoprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 47808)
            else {
                icsSay(emit, L("thermoprobe: give host[:port] — thermoprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit,
                     buildThermoBACnet(
                        host: host, ip: ip,
                        port: port)
                     + buildThermoHTTP(
                        host: host, ip: ip))
        }
    }

    // MARK: owprobe — the 1-Wire bus

    /// One owserver header: six
    /// big-endian words — version,
    /// payload length, message type,
    /// flags, data length, offset.
    /// Byte-pinned by the Gauntlet.
    static func buildOWHeader(
        payload: Int, type: Int,
        flags: Int, size: Int,
        offset: Int) -> [UInt8] {
        var out: [UInt8] = []
        for field in [0, payload, type,
                      flags, size, offset] {
            out.append(UInt8(
                (field >> 24) & 0xFF))
            out.append(UInt8(
                (field >> 16) & 0xFF))
            out.append(UInt8(
                (field >> 8) & 0xFF))
            out.append(UInt8(field & 0xFF))
        }
        return out
    }

    /// The whole-directory ask
    /// (DIRALL, type 7) for the root
    /// of the bus: the header and
    /// the path, NUL-closed.
    static func buildOWRequest() -> [UInt8] {
        buildOWHeader(payload: 2,
                      type: 7, flags: 0,
                      size: 0, offset: 0)
            + [0x2F, 0x00]
    }

    /// The ROM ids out of a DIRALL
    /// answer: comma-separated
    /// paths, each naming a device
    /// by its ROM id — family code
    /// first, as the bus prints it
    /// (fourteen hex digits in the
    /// canonical OWFS form, sixteen
    /// where the CRC rides along).
    /// Anything that is not a ROM
    /// id is not a device here.
    static func buildOWParseDirectory(
        _ text: String)
        -> [(family: Int, rom: String)] {
        var out: [(family: Int,
                   rom: String)] = []
        for rawEntry in text.split(
            separator: ",") {
            var entry = String(rawEntry)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            if entry.hasPrefix("/") {
                entry.removeFirst()
            }
            let head = entry.split(
                separator: "/").first
                .map(String.init) ?? ""
            let cleaned = head
                .replacingOccurrences(
                    of: ".", with: "")
            guard cleaned.count == 14
                    || cleaned.count == 16,
                  cleaned.allSatisfy({
                    $0.isHexDigit })
            else { continue }
            let rom = cleaned.uppercased()
            guard let family = Int(
                rom.prefix(2), radix: 16)
            else { continue }
            out.append((family, rom))
        }
        return out
    }

    /// The common 1-Wire families,
    /// named; the rest keep their
    /// code and nothing more.
    static func buildOWFamilyName(
        _ family: Int) -> String {
        switch family {
        case 0x10:
            return L("DS18S20 temperature sensor")
        case 0x22:
            return L("DS1822 temperature sensor")
        case 0x28:
            return L("DS18B20 temperature sensor")
        case 0x26:
            return L("DS2438 — temperature and voltage on one die")
        default:
            return String(format: L("family 0x%02llX — unnamed by this reader"), Int64(family))
        }
    }

    static func buildOWCore(
        host: String, ip: String,
        port: UInt16, light: Bool)
        -> [ICSLine] {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: light ? 1.5 : 3.5,
            name: host) else {
            return light ? [] : [
                (String(format: L("owprobe: nothing answers on the OWServer door at %@."), host), .out),
            ]
        }
        defer { close(fd) }
        guard icsSendAll(fd,
                         buildOWRequest()),
              let head = icsReadExact(
                fd, 24) else {
            return light ? [] : [
                (String(format: L("owprobe: the door at %@ took the knock and gave no directory back."), host), .out),
            ]
        }
        let payload = icsU32BE(head, 4)
        let ret = buildI32(head, 8)
        let size = icsU32BE(head, 16)
        if ret < 0 {
            return [
                (String(format: L("owprobe: the server at %@ answered the directory ask with an error (%lld) — an OWServer-shaped refusal; no bus is claimed from it."), host, Int64(ret)), .out),
            ]
        }
        guard payload > 0,
              payload < 1_000_000,
              let data = icsReadExact(
                fd, payload) else {
            return [
                (String(format: L("owprobe: the server at %@ promised a directory that never arrived whole — graded an OWServer-like service, and no readings are claimed."), host), .out),
            ]
        }
        let slice = size > 0
            && size <= data.count
            ? Array(data[0..<size]) : data
        let text = String(
            bytes: slice,
            encoding: .utf8) ?? ""
        let roms = buildOWParseDirectory(
            text)
        if roms.isEmpty {
            return [
                (String(format: L("owprobe: the service at %@ answered in the OWServer's shape, but its directory named no 1-Wire device this reader can parse — graded OWServer-like; nothing is invented from it."), host), .sys),
            ]
        }
        var lines: [ICSLine] = [
            (String(format: L("owprobe: the 1-Wire bus behind %@ names %lld device(s):"), host, Int64(roms.count)), .sys),
        ]
        for rom in roms.prefix(16) {
            lines.append((
                String(format: L("owprobe: %@ — %@"), rom.rom, buildOWFamilyName(rom.family)),
                .out))
        }
        if !light {
            lines.append((
                L("owprobe: the bus directory is served with no authentication — every sensor on the wire is inventoried for the asking."),
                .err))
        }
        return lines
    }

    static func owprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 4304)
            else {
                icsSay(emit, L("owprobe: give host[:port] — owprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildOWCore(
                host: host, ip: ip,
                port: port, light: false))
        }
    }

    // MARK: envprobe — the SNMP
    // environmental ledger

    /// One battery of documented
    /// environmental objects, asked
    /// the street wave's way — the
    /// bench's one conventional read
    /// (the default community, v2c
    /// then v1). Every value prints
    /// with the MIB that defines it;
    /// an object the agent does not
    /// hold is skipped, never filled.
    static func buildEnvCore(
        host: String, ip: String)
        -> [ICSLine] {
        let battery: [(
            oid: [Int], dotted: String,
            label: String)] = [
            ([1, 3, 6, 1, 2, 1, 1, 1, 0],
             "1.3.6.1.2.1.1.1.0",
             L("the agent names itself")),
            ([1, 3, 6, 1, 4, 1, 318, 1, 1,
              1, 2, 2, 2, 0],
             "1.3.6.1.4.1.318.1.1.1.2.2.2.0",
             L("APC PowerNet — UPS battery temperature, in the MIB's degrees C")),
            ([1, 3, 6, 1, 4, 1, 318, 1, 1,
              10, 3, 13, 1, 1, 3, 1],
             "1.3.6.1.4.1.318.1.1.10.3.13.1.1.3.1",
             L("APC PowerNet — the integrated monitor's probe temperature, in the MIB's degrees C")),
            ([1, 3, 6, 1, 2, 1, 33, 1, 2,
              7, 0],
             "1.3.6.1.2.1.33.1.2.7.0",
             L("UPS-MIB — battery temperature, in the MIB's degrees C")),
        ]
        guard let answer = streetSNMPGet(
            ip, battery.map { $0.oid })
        else {
            return [
                (String(format: L("envprobe: no SNMP agent at %@ answered the house read — silence, graded as silence."), host), .out),
            ]
        }
        let exceptions: [UInt8] = [
            0x80, 0x81, 0x82]
        var lines: [ICSLine] = []
        var temps = 0
        for entry in battery {
            guard let bind = answer.binds
                    .first(where: {
                        $0.oid == entry.dotted
                    }),
                  !exceptions.contains(
                    bind.tag)
            else { continue }
            let rendered = BlacksitePentest
                .snmpRender(bind.tag,
                            bind.body)
            if entry.dotted
                == "1.3.6.1.2.1.1.1.0" {
                lines.append((
                    String(format: L("envprobe: the agent at %@ — %@ (over %@)."), host, rendered, answer.dialect),
                    .sys))
            } else {
                temps += 1
                lines.append((
                    String(format: L("envprobe: %@ reads %@."), entry.label, rendered),
                    .out))
            }
        }
        if temps > 0 {
            lines.append((
                L("envprobe: the building's temperatures were served to the bench's one conventional read, no credential of ours — environmental sensors answer the whole wire, and that is the finding."),
                .err))
        } else if lines.isEmpty {
            lines.append((
                String(format: L("envprobe: the agent at %@ answered, but holds none of the environmental objects this battery asks for."), host),
                .out))
        }
        return lines
    }

    static func envprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 161)
            else {
                icsSay(emit, L("envprobe: give a host — envprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildEnvCore(
                host: host, ip: ip))
        }
    }

    // MARK: panelprobe — the alarm
    // panels' doors, heard only

    /// Open a panel door and listen
    /// — this bench transmits
    /// NOTHING on either of them:
    /// no login, no password, no
    /// frame of any kind. Whatever
    /// the module volunteers in the
    /// window is all that is read.
    static func buildPanelDoor(
        host: String, ip: String,
        port: UInt16, seconds: Double)
        -> [UInt8]? {
        guard let fd = icsSocket(
            ip: ip, port: port,
            timeout: 3, name: host)
        else { return nil }
        defer { close(fd) }
        return icsAvailable(
            fd, seconds: seconds,
            cap: 4096)
    }

    static func buildPanelCore(
        host: String, ip: String,
        light: Bool) -> [ICSLine] {
        var lines: [ICSLine] = []
        var answered = false
        if let heard = buildPanelDoor(
            host: host, ip: ip, port: 4025,
            seconds: light ? 1.2 : 2.2) {
            answered = true
            let text = String(
                bytes: heard,
                encoding: .utf8) ?? ""
            if text.contains("Login") {
                lines.append((
                    String(format: L("panelprobe: the EnvisaLink TPI at %@ (TCP 4025) fronts its panel with a login prompt — heard, and that is all: this bench sent nothing, and no password was tried or will be."), host),
                    .sys))
            } else if heard.isEmpty {
                lines.append((
                    String(format: L("panelprobe: TCP 4025 at %@ opens and volunteers nothing in the window — an EnvisaLink-shaped silence."), host),
                    .out))
            } else {
                let runs = icsRuns(heard)
                lines.append((
                    String(format: L("panelprobe: TCP 4025 at %@ volunteers: %@"), host, runs.isEmpty ? icsHex(heard.prefix(24)) : runs.joined(separator: " · ")),
                    .sys))
            }
        }
        if let heard = buildPanelDoor(
            host: host, ip: ip, port: 6001,
            seconds: light ? 1.2 : 2.2) {
            answered = true
            let text = String(
                bytes: heard,
                encoding: .utf8) ?? ""
            if text.contains("["),
               text.contains("]") {
                lines.append((
                    String(format: L("panelprobe: keypad frames stream off TCP 6001 at %@ — the AlarmDecoder's ser2sock relays the panel bus to any guest who connects; no login stands in front of it."), host),
                    .err))
            } else if heard.isEmpty {
                lines.append((
                    String(format: L("panelprobe: TCP 6001 at %@ opens and volunteers nothing in the window."), host),
                    .out))
            } else {
                let runs = icsRuns(heard)
                lines.append((
                    String(format: L("panelprobe: TCP 6001 at %@ volunteers: %@"), host, runs.isEmpty ? icsHex(heard.prefix(24)) : runs.joined(separator: " · ")),
                    .sys))
            }
        }
        if !answered {
            return light ? [] : [
                (String(format: L("panelprobe: neither panel door (4025, 6001) answers at %@."), host), .out),
            ]
        }
        return lines
    }

    static func panelprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 4025)
            else {
                icsSay(emit, L("panelprobe: give a host — panelprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildPanelCore(
                host: host, ip: ip,
                light: false))
        }
    }

    // MARK: onvifprobe — discovery,
    // directed, then the nameplate

    /// One ProbeMatch, scraped: the
    /// types the device claims, the
    /// addresses of its services,
    /// and the scopes it publishes.
    struct BuildWSDMatch {
        var types: String
        var xaddrs: String
        var scopes: String
    }

    /// The WS-Discovery Probe, as
    /// the wire wave frames it —
    /// sent here to ONE host, not
    /// the multicast room.
    static func buildWSDProbeXML()
        -> String {
        "<?xml version=\"1.0\" "
            + "encoding=\"utf-8\"?>"
            + "<soap:Envelope "
            + "xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
            + "xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
            + "xmlns:wsd=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\">"
            + "<soap:Header>"
            + "<wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>"
            + "<wsa:MessageID>urn:uuid:"
            + UUID().uuidString
            + "</wsa:MessageID>"
            + "<wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>"
            + "</soap:Header>"
            + "<soap:Body><wsd:Probe>"
            + "<wsd:Types>wsdp:Device</wsd:Types>"
            + "</wsd:Probe></soap:Body>"
            + "</soap:Envelope>"
    }

    /// Every ProbeMatch in an
    /// answer, scraped — a pure
    /// function, pinned by the
    /// Gauntlet on canned XML.
    static func buildWSDParse(
        _ xml: String) -> [BuildWSDMatch] {
        wireBlocks(xml, "ProbeMatch")
            .map { block in
                BuildWSDMatch(
                    types: streetTag(
                        block, "Types") ?? "",
                    xaddrs: streetTag(
                        block, "XAddrs") ?? "",
                    scopes: streetTag(
                        block, "Scopes") ?? "")
            }
    }

    static func buildWSDCore(
        host: String, ip: String,
        light: Bool) -> [ICSLine] {
        guard let reply = icsUDPExchange(
            ip: ip, port: 3702,
            packet: Array(
                buildWSDProbeXML().utf8),
            wait: light ? 1.2 : 2.2,
            cap: 16384) else {
            return light ? [] : [
                (String(format: L("onvifprobe: no ProbeMatch answered the directed discovery knock at %@ — the device does not publish itself this way, or discovery is off."), host), .out),
            ]
        }
        let xml = String(
            bytes: reply,
            encoding: .utf8) ?? ""
        let matches = buildWSDParse(xml)
        if matches.isEmpty {
            return [
                (String(format: L("onvifprobe: something at %@ answered on the discovery door, but its answer held no ProbeMatch this reader can parse — noted, not named: %@"), host, icsHex(reply.prefix(24))), .out),
            ]
        }
        var lines: [ICSLine] = []
        for match in matches.prefix(4) {
            var line = String(
                format: L("onvifprobe: %@ publishes itself to any directed ask"), host)
            if !match.types.isEmpty {
                line += " — " + match.types
            }
            if !match.xaddrs.isEmpty {
                line += " · " + match.xaddrs
            }
            lines.append((line, .sys))
            if !match.scopes.isEmpty {
                let short = match.scopes
                    .replacingOccurrences(
                        of: "onvif://www.onvif.org/",
                        with: "")
                lines.append((
                    String(format: L("onvifprobe: scopes — %@"), short),
                    .out))
            }
        }
        lines.append((
            L("onvifprobe: WS-Discovery has no authentication to give — types, service addresses and scopes are the device's public introduction, by design. The design is the grade."),
            .err))
        return lines
    }

    /// The verb: the directed
    /// discovery battery, then the
    /// street wave's ONVIF nameplate
    /// read when the web door stands
    /// open — the same two reads the
    /// name has always made, with
    /// the discovery half now asked
    /// of the one host, by name.
    static func buildONVIFVerb(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, port) =
                icsResolve(target, 80)
            else {
                icsSay(emit, L("onvifprobe: give the host — onvifprobe 192.168.1.64"), .err)
                return
            }
            var lines = buildWSDCore(
                host: host, ip: ip,
                light: false)
            if let fd = icsSocket(
                ip: ip, port: port,
                timeout: 1.2, name: host) {
                close(fd)
                lines += streetONVIFCore(
                    host, Int(port),
                    light: true)
            }
            icsPrint(emit, lines)
        }
    }

    // MARK: accessprobe — the
    // access panels' doors

    /// Presence, conservatively:
    /// the discovery ear (UDP 4077)
    /// gets an empty knock — zero
    /// protocol bytes — and the host
    /// door the Mercury and HID
    /// controllers listen on (TCP
    /// 3001) gets a connection and
    /// a listen. Nothing is sent to
    /// either beyond the knock
    /// itself, and no card data
    /// exists in this verb at all.
    static func buildAccessCore(
        host: String, ip: String,
        light: Bool) -> [ICSLine] {
        var lines: [ICSLine] = []
        lines += icsUDPEmptyCore(
            verb: "accessprobe",
            host: host, ip: ip,
            port: 4077, light: light,
            note: L("accessprobe: UDP 4077 is the discovery ear access panels listen on — an empty knock is all this bench ever sends it."))
        lines += icsConnectOnlyCore(
            verb: "accessprobe",
            host: host, ip: ip,
            port: 3001, light: light,
            note: light ? "" : L("accessprobe: TCP 3001 is the host door Mercury and HID controllers listen on. Presence is all that is graded — no card data exists in this verb, and no credential is held for it."))
        if lines.isEmpty {
            return light ? [] : [
                (String(format: L("accessprobe: no access-panel door answered at %@ — the discovery ear kept quiet, and the host door stayed shut."), host), .out),
            ]
        }
        return lines
    }

    static func accessprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 3001)
            else {
                icsSay(emit, L("accessprobe: give a host — accessprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildAccessCore(
                host: host, ip: ip,
                light: false))
        }
    }

    // MARK: fire — the nameplate,
    // and nothing past it

    /// The fire makers, matched
    /// against nameplate evidence —
    /// a name or a vendor string the
    /// device itself printed. A pure
    /// classifier: no evidence, no
    /// maker, ever.
    static func buildFireClassify(
        _ evidence: String) -> String? {
        let text = evidence.lowercased()
        let table: [(String, String)] = [
            ("notifier", "Notifier"),
            ("silent knight",
             "Silent Knight"),
            ("fire-lite", "Fire-Lite"),
            ("firelite", "Fire-Lite"),
            ("gamewell", "Gamewell-FCI"),
            ("edwards", "EST / Edwards"),
            ("simplex", "Simplex"),
            ("autocall", "Autocall"),
            ("potter", "Potter"),
            ("mircom", "Mircom"),
            ("cerberus",
             "Siemens Cerberus"),
            ("kidde", "Kidde"),
            ("hochiki", "Hochiki"),
        ]
        for (needle, maker) in table
        where text.contains(needle) {
            return maker
        }
        return nil
    }

    /// What the identification reads
    /// raised at one address: the
    /// BACnet plate, the SNMP plate,
    /// and the maker they name
    /// between them, if any.
    struct BuildFirePlate {
        var bacnet: String?
        var snmp: String?
        var maker: String?
        var evidence: String
    }

    /// The nameplate reads, and only
    /// those: BACnet Who-Is and the
    /// device object (name, vendor,
    /// model), and the SNMP ledger's
    /// sysDescr, sysObjectID and
    /// sysName. Quick mode — the
    /// census's shape — asks SNMP
    /// only where BACnet kept mute.
    static func buildFirePlate(
        ip: String, quick: Bool)
        -> BuildFirePlate {
        var bacnet: String? = nil
        var snmp: String? = nil
        if let objid = buildBACWhoIs(
            ip: ip, port: 47808,
            wait: quick ? 1.0 : 2.4) {
            var facts: [String] = []
            var invoke: UInt8 = 31
            for prop: UInt8 in [77, 121, 70] {
                if let value = icsBACReadProp(
                    ip: ip, port: 47808,
                    objid: objid,
                    invoke: invoke,
                    prop: prop),
                   !value.isEmpty {
                    facts.append(value)
                }
                invoke += 1
            }
            if !facts.isEmpty {
                bacnet = facts.joined(
                    separator: ", ")
            }
        }
        if !quick || bacnet == nil {
            let oids: [[Int]] = [
                [1, 3, 6, 1, 2, 1, 1, 1, 0],
                [1, 3, 6, 1, 2, 1, 1, 2, 0],
                [1, 3, 6, 1, 2, 1, 1, 5, 0],
            ]
            let dotted = [
                "1.3.6.1.2.1.1.1.0",
                "1.3.6.1.2.1.1.2.0",
                "1.3.6.1.2.1.1.5.0",
            ]
            let got: (binds: [(
                        oid: String,
                        tag: UInt8,
                        body: [UInt8])],
                      dialect: String)?
            if quick {
                if let probe =
                    BlacksitePentest.snmpProbe(
                        ip: ip, version: 1,
                        community: "public",
                        oids: oids) {
                    got = (binds: probe.binds,
                           dialect: "SNMPv2c")
                } else {
                    got = nil
                }
            } else {
                got = streetSNMPGet(ip, oids)
            }
            if let got = got {
                var facts: [String] = []
                for oid in dotted {
                    guard let bind = got.binds
                            .first(where: {
                                $0.oid == oid
                            }),
                          bind.tag != 0x80,
                          bind.tag != 0x81,
                          bind.tag != 0x82
                    else { continue }
                    let rendered =
                        BlacksitePentest
                        .snmpRender(bind.tag,
                                    bind.body)
                    if !rendered.isEmpty {
                        facts.append(rendered)
                    }
                }
                if !facts.isEmpty {
                    snmp = facts.joined(
                        separator: " · ")
                }
            }
        }
        let evidence = [bacnet, snmp]
            .compactMap { $0 }
            .joined(separator: " · ")
        return BuildFirePlate(
            bacnet: bacnet, snmp: snmp,
            maker: buildFireClassify(
                evidence),
            evidence: evidence)
    }

    /// The fire board: the doctrine
    /// line first, the nameplates as
    /// read, and the maker's name
    /// when — and only when — the
    /// device's own plate carries it.
    static func buildFireCore(
        host: String, ip: String)
        -> [ICSLine] {
        var lines: [ICSLine] = [(
            L("fireprobe: identification only — this probe never reads alarm or zone state and sends nothing that can test, acknowledge, silence, or reset."),
            .sys)]
        let plate = buildFirePlate(
            ip: ip, quick: false)
        if let bacnet = plate.bacnet {
            lines.append((
                String(format: L("fireprobe: the BACnet nameplate at %@ reads — %@."), host, bacnet),
                .sys))
        }
        if let snmp = plate.snmp {
            lines.append((
                String(format: L("fireprobe: the SNMP nameplate at %@ reads — %@."), host, snmp),
                .sys))
        }
        if plate.bacnet == nil,
           plate.snmp == nil {
            lines.append((
                String(format: L("fireprobe: nothing at %@ raised a nameplate to the identification reads."), host),
                .out))
        } else if let maker = plate.maker {
            lines.append((
                String(format: L("fireprobe: the nameplate carries a fire maker's name — %@. The panel's make is public to any caller on this wire; its state was never asked for, and this bench holds no verb that could ask."), maker),
                .err))
        } else {
            lines.append((
                L("fireprobe: a nameplate answered, but no fire maker's name stands on it — noted, and not cleared: a panel is not proven absent by a quiet plate."),
                .out))
        }
        return lines
    }

    static func fireprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 47808)
            else {
                icsSay(emit, L("fireprobe: give a host — fireprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildFireCore(
                host: host, ip: ip))
        }
    }

    /// The sweep: every address on
    /// the /24 gets the nameplate
    /// reads, in parallel and light,
    /// and the fire-shaped plates
    /// are called out. The doctrine
    /// does not relax at census
    /// scale — identification only,
    /// the whole sweep long.
    static func buildFireCensus(
        target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let prefix = buildPrefix(
                target) else {
                icsSay(emit, L("firecensus: give a prefix — firecensus 192.168.1 — or nothing for this wire"), .err)
                return
            }
            icsSay(emit, String(format: L("firecensus — reading nameplates across %@.0/24: the BACnet Who-Is and the SNMP ledger, identification only"), prefix), .sys)
            let lock = NSLock()
            var hits: [(octet: Int,
                        evidence: String,
                        maker: String?)] = []
            let group = DispatchGroup()
            let sem = DispatchSemaphore(
                value: 24)
            for octet in 1...254 {
                if stopped() { break }
                let ip = "\(prefix).\(octet)"
                group.enter()
                DispatchQueue.global()
                    .async {
                        sem.wait()
                        let plate =
                            buildFirePlate(
                                ip: ip,
                                quick: true)
                        if plate.bacnet != nil
                            || plate.snmp
                                != nil {
                            lock.lock()
                            hits.append((
                                octet,
                                plate.evidence,
                                plate.maker))
                            lock.unlock()
                        }
                        sem.signal()
                        group.leave()
                    }
            }
            group.wait()
            hits.sort { $0.octet < $1.octet }
            var fire = 0
            for hit in hits {
                if let maker = hit.maker {
                    fire += 1
                    icsSay(emit, String(format: L("firecensus: %@.%lld — fire nameplate: %@ (%@)"), prefix, Int64(hit.octet), maker, hit.evidence), .err)
                } else {
                    icsSay(emit, String(format: L("firecensus: %@.%lld — a nameplate, no fire maker's name: %@"), prefix, Int64(hit.octet), hit.evidence), .out)
                }
            }
            icsSay(emit, String(format: L("firecensus: %lld address(es) raised a nameplate, %lld of them a fire maker's, across %@.0/24."), Int64(hits.count), Int64(fire), prefix), fire > 0 ? .err : .ok)
            icsSay(emit, L("firecensus: identification only, the whole sweep long — no alarm or zone state was read anywhere, and nothing was sent that can test, acknowledge, silence, or reset."), .out)
        }
    }

    // MARK: buildingprobe — the
    // marquee: four batteries, one
    // graded board

    static func buildBuildingCore(
        host: String, ip: String)
        -> [ICSLine] {
        var lines: [ICSLine] = [(
            String(format: L("buildingprobe — the building's own systems at %@, four batteries on one board"), host),
            .sys)]
        func section(
            _ label: String,
            _ body: [ICSLine]) {
            lines.append((
                String(format: L("battery: %@"), label),
                .sys))
            lines += body
        }
        section(L("thermo — the temperatures the building keeps"),
                buildThermoBACnet(
                    host: host, ip: ip,
                    port: 47808)
                + buildThermoHTTP(
                    host: host, ip: ip))
        section(L("panel — the alarm panels' doors"),
                buildPanelCore(
                    host: host, ip: ip,
                    light: false))
        section(L("onvif — discovery, directed"),
                buildWSDCore(
                    host: host, ip: ip,
                    light: false))
        section(L("fire — the nameplate, and nothing past it"),
                buildFireCore(
                    host: host, ip: ip))
        lines.append((
            L("buildingprobe: one knock per battery, read and grade — nothing above wrote a setpoint, tried a password, or touched an alarm state. The building was introduced, not operated."),
            .out))
        return lines
    }

    static func buildingprobe(
        target: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (host, ip, _) =
                icsResolve(target, 47808)
            else {
                icsSay(emit, L("buildingprobe: give a host — buildingprobe 192.168.1.10"), .err)
                return
            }
            icsPrint(emit, buildBuildingCore(
                host: host, ip: ip))
        }
    }

    // MARK: buildingcensus — the
    // light sweep by family

    /// One address, lightly: which
    /// of the wave's doors answer,
    /// and what family that makes
    /// it. The BACnet knock reads a
    /// vendor name so a fire plate
    /// is known from a heating
    /// controller at census speed.
    static func buildCensusHost(
        ip: String)
        -> (families: [String],
            evidence: [String]) {
        var families: [String] = []
        var evidence: [String] = []
        if let objid = buildBACWhoIs(
            ip: ip, port: 47808,
            wait: 0.9) {
            var vendor = ""
            if let value = icsBACReadProp(
                ip: ip, port: 47808,
                objid: objid, invoke: 41,
                prop: 121) {
                vendor = value
            }
            if let maker = buildFireClassify(
                vendor) {
                families.append(String(
                    format: L("fire (%@)"),
                    maker))
            } else {
                families.append(
                    L("building controls (BACnet)"))
            }
            evidence.append(String(
                format: L("BACnet device %lld"),
                Int64(objid & 0x3FFFFF)))
        }
        if buildDoorOpen(ip: ip,
                         port: 4304) {
            families.append(
                L("temperature (OWServer)"))
            evidence.append(L("TCP 4304 open"))
        }
        if buildDoorOpen(ip: ip,
                         port: 4025) {
            families.append(
                L("security (EnvisaLink TPI door)"))
            evidence.append(L("TCP 4025 open"))
        }
        if buildDoorOpen(ip: ip,
                         port: 6001) {
            families.append(
                L("security (AlarmDecoder door)"))
            evidence.append(L("TCP 6001 open"))
        }
        if let reply = icsUDPExchange(
            ip: ip, port: 3702,
            packet: Array(
                buildWSDProbeXML().utf8),
            wait: 0.9, cap: 8192) {
            let xml = String(
                bytes: reply,
                encoding: .utf8) ?? ""
            if !buildWSDParse(xml)
                .isEmpty {
                families.append(
                    L("security (ONVIF discovery)"))
                evidence.append(
                    L("WS-Discovery answered"))
            }
        }
        return (families, evidence)
    }

    static func buildBuildingCensus(
        target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let prefix = buildPrefix(
                target) else {
                icsSay(emit, L("buildingcensus: give a prefix — buildingcensus 192.168.1 — or nothing for this wire"), .err)
                return
            }
            icsSay(emit, String(format: L("buildingcensus — one light knock per building door across %@.0/24"), prefix), .sys)
            let lock = NSLock()
            var hits: [(octet: Int,
                        families: [String],
                        evidence: [String])] = []
            let group = DispatchGroup()
            let sem = DispatchSemaphore(
                value: 24)
            for octet in 1...254 {
                if stopped() { break }
                let ip = "\(prefix).\(octet)"
                group.enter()
                DispatchQueue.global()
                    .async {
                        sem.wait()
                        let found =
                            buildCensusHost(
                                ip: ip)
                        if !found.families
                            .isEmpty {
                            lock.lock()
                            hits.append((
                                octet,
                                found.families,
                                found.evidence))
                            lock.unlock()
                        }
                        sem.signal()
                        group.leave()
                    }
            }
            group.wait()
            hits.sort { $0.octet < $1.octet }
            for hit in hits {
                icsSay(emit, String(format: L("buildingcensus: %@.%lld — %@ (%@)"), prefix, Int64(hit.octet), hit.families.joined(separator: ", "), hit.evidence.joined(separator: ", ")), .ok)
            }
            icsSay(emit, String(format: L("buildingcensus: %lld address(es) keep building systems on %@.0/24."), Int64(hits.count), prefix), hits.isEmpty ? .out : .ok)
            icsSay(emit, L("buildingcensus: light knocks only — a door held open is a presence, not a reading; the verbs knock deeper, one host at a time, and the fire line holds at every scale."), .out)
        }
    }

    // MARK: the wave's one dispatch

    static func benchBuild(
        _ name: String, _ target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = {
            text, kind in
            if !stopped() {
                emit(text, kind)
            }
        }
        switch name {
        case "thermoprobe":
            thermoprobe(target: target,
                        emit: live, done: done)
        case "owprobe":
            owprobe(target: target,
                    emit: live, done: done)
        case "envprobe":
            envprobe(target: target,
                     emit: live, done: done)
        case "panelprobe":
            panelprobe(target: target,
                       emit: live, done: done)
        case "onvifprobe":
            buildONVIFVerb(target: target,
                           emit: live,
                           done: done)
        case "accessprobe":
            accessprobe(target: target,
                        emit: live, done: done)
        case "fireprobe":
            fireprobe(target: target,
                      emit: live, done: done)
        case "firecensus":
            buildFireCensus(
                target: target,
                stopped: stopped,
                emit: live, done: done)
        case "buildingprobe":
            buildingprobe(target: target,
                          emit: live, done: done)
        case "buildingcensus":
            buildBuildingCensus(
                target: target,
                stopped: stopped,
                emit: live, done: done)
        default:
            done()
        }
    }
}
