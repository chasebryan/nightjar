import Foundation
import CoreBluetooth

// MARK: - Bench wave 6: the street
//
// Traffic signals, message signs, road-weather stations, roadside
// radios, cameras and the ledgers that map them — the watched city,
// read in the open and graded in the open.
//
// TWO LINES HARDER THAN ANYWHERE ELSE ON THE BENCH.
// (1) TRAFFIC IS LIFE-SAFETY. The traffic reads are SNMP GETs of
// identification objects only — the system group and the NTCIP
// 1201 module table, plus each standard's own identification
// branch. No Set request is built anywhere in this file, no phase,
// timing or pattern object is read or written in any protocol, no
// camera is ever steered, and no siren is ever sounded. The grade
// is the door's exposure: a controller that answers the read-only
// community 'public' to a stranger has published its identity to
// the wire, and that is proven by a read that changes nothing.
// (2) THE BENCH NEVER TOUCHES CAPTURED DATA. No camera cloud, no
// plate database, no hotlist, no archive, no face anything.
// Surveillance coverage comes from PUBLIC LEDGERS (OpenStreetMap
// and the DeFlock mapping convention, state DOT publications, the
// FCC's tower registry as the map mirrors it, USGS and OpenAQ) and
// from the nameplates of devices the operator can already reach.
// A camera is identified by what it publishes about itself, never
// by what it has seen.
//
// Every frame was byte-verified in Python against its published
// spec or MIB before it was written in Swift (the NTCIP object
// tree from NTCIP 1201 v04 and the 1202/1203/1204 identification
// branches; the ONVIF envelopes against the official ver10 device
// and ver20 PTZ WSDLs; GTFS-realtime field numbers against
// google/transit's proto; Remote ID against the house decoder in
// Drones.swift). What could not be verified is degraded and says
// so: the USDOT roadside-unit MIB's own description branch (its
// numeric root is not publicly verifiable, so it is not probed),
// TALQ streetlight gateways (an authenticated, vendor-run
// protocol with no public nameplate read), siren controllers (no
// public IP identification protocol exists for the class), and
// OpenAQ (the ledger now demands an API key this bench does not
// carry). Identifications are reported as what the device SAYS it
// is: a nameplate is a claim, read aloud.

extension BlacksiteBench {

    // MARK: dispatch

    static func benchStreet(
        _ name: String,
        _ target: String?,
        stopped: @escaping () -> Bool,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = { text, kind in
            if !stopped() { emit(text, kind) }
        }
        switch name {
        case "signalprobe":
            streetSignalProbe(target, emit: live, done: done)
        case "ascprobe":
            streetASCProbe(target, emit: live, done: done)
        case "dmsprobe":
            streetDMSProbe(target, emit: live, done: done)
        case "rwisprobe":
            streetRWISProbe(target, emit: live, done: done)
        case "rsuprobe":
            streetRSUProbe(target, emit: live, done: done)
        case "spatprobe":
            streetSPaTProbe(target, emit: live, done: done)
        case "flockcensus":
            streetFlockCensus(target, emit: live, done: done)
        case "dotprobe":
            streetDOTProbe(target, emit: live, done: done)
        case "onvifprobe":
            streetONVIFProbe(target, emit: live, done: done)
        case "camdeep":
            streetCamDeep(target, emit: live, done: done)
        case "ptzprobe":
            streetPTZProbe(target, emit: live, done: done)
        case "ridprobe":
            streetRIDProbe(emit: live, done: done)
        case "streetlightprobe":
            streetLightProbe(target, emit: live, done: done)
        case "sirenprobe":
            streetSirenProbe(target, emit: live, done: done)
        case "transitprobe":
            streetTransitProbe(target, emit: live, done: done)
        case "gaugeprobe":
            streetGaugeProbe(target, emit: live, done: done)
        case "airprobe":
            streetAirProbe(target, emit: live, done: done)
        case "gbfsprobe":
            streetGBFSProbe(target, emit: live, done: done)
        case "towerprobe":
            streetTowerProbe(target, emit: live, done: done)
        case "streetcensus":
            streetCensus(target, emit: live, done: done)
        default:
            done()
        }
    }

    // MARK: plumbing (street-prefixed; reuses the house engines)

    /// host[:port] split + resolve for the
    /// SNMP doors, whose port is the
    /// standard's own (UDP 161) — a port
    /// tail is accepted and set aside.
    static func streetHost(
        _ target: String?)
        -> (host: String, ip: String)? {
        guard var host = target, !host.isEmpty
        else { return nil }
        if let colon = host.lastIndex(of: ":") {
            let tail = host[host.index(after: colon)...]
            if let p = Int(tail), p > 0, p < 65536 {
                host = String(host[..<colon])
            }
        }
        guard let resolved = BlacksiteNet
            .resolve4(host) else { return nil }
        return (host, resolved.ip)
    }

    /// One POST through the house web
    /// session; status, body and headers
    /// come back, redirects are not
    /// followed (satFetch's POST sibling).
    static func streetPOST(
        _ url: URL, contentType: String,
        body: [UInt8])
        -> (status: Int, body: String,
            headers: [String: String])? {
        let (session, _) = BlacksitePentest
            .webSession(follow: false)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue(
            "blacksite/11.0 (nightjar)",
            forHTTPHeaderField: "User-Agent")
        request.setValue(
            contentType,
            forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body)
        guard let (data, http) =
            BlacksitePentest.syncFetch(
                session, request),
              let http = http else {
            return nil
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)
                .lowercased()] =
                String(describing: value)
        }
        return (http.statusCode,
                String(decoding: data,
                       as: UTF8.self), headers)
    }

    /// The inner text of the first element
    /// whose local name matches, namespaces
    /// aside — the ONVIF and ISAPI replies
    /// are read this way, never parsed into
    /// a tree the bench would have to trust.
    static func streetTag(
        _ xml: String, _ name: String)
        -> String? {
        var cursor = xml.startIndex
        while let open = xml.range(
            of: "<", range: cursor..<xml.endIndex) {
            guard let close = xml.range(
                of: ">",
                range: open.upperBound..<xml.endIndex)
            else { return nil }
            let raw = xml[
                open.upperBound..<close.lowerBound]
            let head = raw.split(
                separator: " ").first
                .map(String.init) ?? ""
            let local = head.split(
                separator: ":").last
                .map(String.init) ?? ""
            if local == name,
               !raw.hasSuffix("/") {
                let rest = close.upperBound..<xml.endIndex
                guard let end = xml.range(
                    of: "<", range: rest)
                else { return nil }
                let text = xml[
                    close.upperBound..<end.lowerBound]
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            cursor = close.upperBound
        }
        return nil
    }

    /// Every match of streetTag, in order.
    static func streetTags(
        _ xml: String, _ name: String)
        -> [String] {
        var out: [String] = []
        var cursor = xml.startIndex
        while let open = xml.range(
            of: "<", range: cursor..<xml.endIndex) {
            guard let close = xml.range(
                of: ">",
                range: open.upperBound..<xml.endIndex)
            else { break }
            let raw = xml[
                open.upperBound..<close.lowerBound]
            let head = raw.split(
                separator: " ").first
                .map(String.init) ?? ""
            let local = head.split(
                separator: ":").last
                .map(String.init) ?? ""
            let rest = close.upperBound..<xml.endIndex
            if local == name,
               !raw.hasSuffix("/"),
               let end = xml.range(
                of: "<", range: rest) {
                let text = xml[
                    close.upperBound..<end.lowerBound]
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    out.append(text)
                }
                if out.count >= 64 { break }
            }
            cursor = close.upperBound
        }
        return out
    }

    /// Count of elements with this local
    /// name (open tags only).
    static func streetTagCount(
        _ xml: String, _ name: String) -> Int {
        var count = 0
        var cursor = xml.startIndex
        while let open = xml.range(
            of: "<", range: cursor..<xml.endIndex) {
            guard let close = xml.range(
                of: ">",
                range: open.upperBound..<xml.endIndex)
            else { break }
            let raw = xml[
                open.upperBound..<close.lowerBound]
            let head = raw.split(
                separator: " ").first
                .map(String.init) ?? ""
            let local = head.split(
                separator: ":").last
                .map(String.init) ?? ""
            if local == name { count += 1 }
            cursor = close.upperBound
        }
        return count
    }

    /// A JSON number, whichever shape the
    /// serializer gave it.
    static func streetNum(
        _ value: Any?) -> Double? {
        if let n = value as? NSNumber {
            return n.doubleValue
        }
        if let s = value as? String {
            return Double(s)
        }
        return nil
    }

    static func streetInt(
        _ value: Any?) -> Int? {
        streetNum(value).map { Int($0) }
    }

    /// A feed argument made into a URL:
    /// scheme-less text is read as https.
    static func streetFeedURL(
        _ target: String?) -> URL? {
        guard var text = target,
              !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "https://" + text
        }
        return URL(string: text)
    }

    /// A place name made into coordinates
    /// by the map's own geocoder
    /// (OpenStreetMap Nominatim, read in
    /// the open like everything else here).
    static func streetGeocode(
        _ place: String)
        -> (lat: Double, lon: Double,
            name: String)? {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                + "abcdefghijklmnopqrstuvwxyz"
                + "0123456789-._~")
        let query = place.addingPercentEncoding(
            withAllowedCharacters: allowed) ?? place
        guard let url = URL(string:
                "https://nominatim.openstreetmap.org"
                + "/search?q=" + query
                + "&format=jsonv2&limit=1"),
              let got = satFetch(url),
              got.status == 200,
              let list = satJSON(got.body)
                as? [[String: Any]],
              let first = list.first,
              let lat = streetNum(first["lat"]),
              let lon = streetNum(first["lon"])
        else { return nil }
        return (lat, lon,
                first["display_name"] as? String
                    ?? place)
    }

    /// One Overpass QL read against the
    /// public interpreter; the elements
    /// array comes back, or nil.
    static func streetOverpass(
        _ ql: String) -> [[String: Any]]? {
        guard let url = URL(string:
                "https://overpass-api.de"
                + "/api/interpreter")
        else { return nil }
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                + "abcdefghijklmnopqrstuvwxyz"
                + "0123456789-._~")
        let encoded = ql.addingPercentEncoding(
            withAllowedCharacters: allowed) ?? ql
        guard let got = streetPOST(
                url,
                contentType:
                    "application/x-www-form-urlencoded",
                body: Array(
                    ("data=" + encoded).utf8)),
              got.status == 200,
              let doc = satJSON(got.body)
                as? [String: Any],
              let elements = doc["elements"]
                as? [[String: Any]]
        else { return nil }
        return elements
    }

    /// The element's tag dictionary.
    static func streetTagsOf(
        _ element: [String: Any])
        -> [String: String] {
        element["tags"] as? [String: String] ?? [:]
    }

    // MARK: - the NTCIP identification core (SNMP GET, never Set)

    /// One identification GET set against
    /// an agent: SNMPv2c first, then v1 —
    /// both under the community 'public',
    /// the bench's one conventional
    /// anonymous posture check. Returns
    /// the binds and the answering dialect.
    static func streetSNMPGet(
        _ ip: String, _ oids: [[Int]])
        -> (binds: [(oid: String, tag: UInt8,
                     body: [UInt8])],
            dialect: String)? {
        if let answer = BlacksitePentest.snmpProbe(
            ip: ip, version: 1,
            community: "public", oids: oids) {
            return (answer.binds, "SNMPv2c")
        }
        if let answer = BlacksitePentest.snmpProbe(
            ip: ip, version: 0,
            community: "public", oids: oids) {
            return (answer.binds, "SNMPv1")
        }
        return nil
    }

    /// A bind rendered the console's way.
    static func streetBind(
        _ binds: [(oid: String, tag: UInt8,
                   body: [UInt8])],
        _ oid: String) -> String? {
        for bind in binds where bind.oid == oid {
            return BlacksitePentest.snmpRender(
                bind.tag, bind.body)
        }
        return nil
    }

    /// The device class a module table's
    /// device node names, where the 1201
    /// tree names it; nil where the branch
    /// is one this bench does not name.
    static func streetDeviceClass(
        _ node: String) -> String? {
        switch node {
        case "1.3.6.1.4.1.1206.4.2.1":
            return L("an actuated signal controller (NTCIP 1202)")
        case "1.3.6.1.4.1.1206.4.2.3":
            return L("a dynamic message sign (NTCIP 1203)")
        case "1.3.6.1.4.1.1206.4.2.5":
            return L("an environmental sensor station (NTCIP 1204)")
        case "1.3.6.1.4.1.1206.4.2.6":
            return L("the global configuration branch itself (NTCIP 1201)")
        default:
            return nil
        }
    }

    /// The shared traffic read: the MIB-II
    /// system group plus the NTCIP 1201
    /// module table's first row — who the
    /// box says it is, and nothing else.
    /// Object ids verified against NTCIP
    /// 1201 v04 and the published 1201 MIB.
    static func streetNTCIPCore(
        _ ip: String, light: Bool) -> [ICSLine] {
        let sysOIDs: [[Int]] = [
            [1, 3, 6, 1, 2, 1, 1, 1, 0],
            [1, 3, 6, 1, 2, 1, 1, 2, 0],
            [1, 3, 6, 1, 2, 1, 1, 5, 0],
        ]
        let moduleBase = [1, 3, 6, 1, 4, 1, 1206,
                          4, 2, 6, 1, 3, 1]
        let idOIDs = sysOIDs + [
            [1, 3, 6, 1, 4, 1, 1206, 4, 2, 6, 1, 2, 0],
            moduleBase + [2, 1],
            moduleBase + [3, 1],
            moduleBase + [4, 1],
            moduleBase + [5, 1],
        ]
        guard let got = streetSNMPGet(ip, idOIDs)
        else {
            return light ? [] : [(
                String(format: L("no SNMP answer at %@ — the door is shut, filtered, or not a traffic box at all"),
                       ip), .err)]
        }
        var binds = got.binds
        if binds.isEmpty {
            // Agents of the v1 school fail the
            // whole PDU over one unknown
            // object; ask the system group
            // alone before concluding.
            binds = streetSNMPGet(
                ip, sysOIDs)?.binds ?? []
        }
        guard !binds.isEmpty else {
            return light ? [] : [(
                String(format: L("%@ answers SNMP but its nameplate reads empty — noted, not named"),
                       ip), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("nameplate — %@ (UDP 161, %@, community 'public')"),
                   ip, got.dialect), .sys)]
        if let descr = streetBind(
            binds, "1.3.6.1.2.1.1.1.0") {
            lines.append((
                String(format: L("it describes itself as: %@"),
                       descr), .out))
        }
        if let name = streetBind(
            binds, "1.3.6.1.2.1.1.5.0") {
            lines.append((
                String(format: L("its configured name: %@"),
                       name), .out))
        }
        if let oid = streetBind(
            binds, "1.3.6.1.2.1.1.2.0") {
            lines.append((
                String(format: L("its object id: %@"),
                       oid), .out))
        }
        var moduleParts: [String] = []
        if let make = streetBind(
            binds, "1.3.6.1.4.1.1206.4.2.6.1.3.1.3.1") {
            moduleParts.append(make)
        }
        if let model = streetBind(
            binds, "1.3.6.1.4.1.1206.4.2.6.1.3.1.4.1") {
            moduleParts.append(model)
        }
        if !moduleParts.isEmpty {
            var text = String(
                format: L("module 1: %@"),
                moduleParts.joined(separator: " "))
            if let version = streetBind(
                binds,
                "1.3.6.1.4.1.1206.4.2.6.1.3.1.5.1") {
                text += String(
                    format: L(" · firmware %@"),
                    version)
            }
            lines.append((text, .out))
        }
        if let node = streetBind(
            binds, "1.3.6.1.4.1.1206.4.2.6.1.3.1.2.1") {
            if let named = streetDeviceClass(node) {
                lines.append((
                    String(format: L("its module table files it as %@"),
                           named), .out))
            } else {
                lines.append((
                    String(format: L("its module table points at device branch %@ — a branch this bench does not name"),
                           node), .out))
            }
        }
        if let maxModules = streetBind(
            binds, "1.3.6.1.4.1.1206.4.2.6.1.2.0"),
           let count = Int(maxModules) {
            lines.append((
                String(format: L("its module table seats %lld module(s)"),
                       Int64(count)), .out))
        }
        lines.append((L("grade: CRITICAL — the read-only community 'public' answered a stranger's first knock, so this box's identity, firmware and filing are public to anyone who can reach its wire"), .err))
        lines.append((L("read: SNMP GET of identification objects only — the system group and the 1201 module table. No Set request exists in this wave, and no phase, timing or pattern object was read or written"), .out))
        return lines
    }

    static func streetSignalProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip) = streetHost(target)
            else {
                icsSay(emit, L("signalprobe: give the controller's host — signalprobe 192.168.1.50"), .err)
                return
            }
            icsPrint(emit, streetNTCIPCore(
                ip, light: false))
        }
    }

    /// NTCIP 1202's own sizing objects:
    /// how many phases the controller
    /// carries. Counts, never states — the
    /// phase-state branch is not read.
    static func streetASCCore(
        _ ip: String, light: Bool) -> [ICSLine] {
        var lines = streetNTCIPCore(ip, light: light)
        guard !lines.isEmpty else { return lines }
        let ascOIDs: [[Int]] = [
            [1, 3, 6, 1, 4, 1, 1206, 4, 2, 1, 1, 1, 0],
            [1, 3, 6, 1, 4, 1, 1206, 4, 2, 1, 1, 3, 0],
        ]
        if let got = streetSNMPGet(ip, ascOIDs),
           !got.binds.isEmpty {
            let phases = streetBind(
                got.binds,
                "1.3.6.1.4.1.1206.4.2.1.1.1.0")
            let groups = streetBind(
                got.binds,
                "1.3.6.1.4.1.1206.4.2.1.1.3.0")
            if let phases = phases,
               let p = Int(phases) {
                var text = String(
                    format: L("the 1202 branch sizes it at %lld phase(s)"),
                    Int64(p))
                if let groups = groups,
                   let g = Int(groups) {
                    text += String(
                        format: L(" in %lld phase group(s)"),
                        Int64(g))
                }
                lines.append((text, .out))
            } else if !light {
                lines.append((L("the 1202 sizing objects answered without numbers — the nameplate above is the identification that stands"), .out))
            }
        } else if !light {
            lines.append((L("the 1202 sizing branch stayed silent — whatever this door is, it does not size itself as an ASC in the open"), .out))
        }
        return lines
    }

    static func streetASCProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip) = streetHost(target)
            else {
                icsSay(emit, L("ascprobe: give the controller's host — ascprobe 192.168.1.50"), .err)
                return
            }
            icsPrint(emit, streetASCCore(
                ip, light: false))
        }
    }

    /// NTCIP 1203's sign configuration
    /// branch: what the sign says it is
    /// made of. The message it currently
    /// shows is content, not identity —
    /// and is never read.
    static func streetDMSCore(
        _ ip: String, light: Bool) -> [ICSLine] {
        var lines = streetNTCIPCore(ip, light: light)
        guard !lines.isEmpty else { return lines }
        var dmsOIDs: [[Int]] = []
        for n in 1...9 {
            dmsOIDs.append(
                [1, 3, 6, 1, 4, 1, 1206, 4, 2, 3, 1, n, 0])
        }
        guard let got = streetSNMPGet(ip, dmsOIDs),
              !got.binds.isEmpty else {
            if !light {
                lines.append((L("the 1203 sign branch stayed silent — the nameplate above is what this door publishes"), .out))
            }
            return lines
        }
        let labels = [
            L("sign access"), L("sign type"),
            L("sign height"), L("sign width"),
            L("horizontal border"),
            L("vertical border"), L("legend"),
            L("beacon type"), L("sign technology"),
        ]
        var shown = 0
        for n in 1...9 {
            let oid = "1.3.6.1.4.1.1206.4.2.3.1."
                + String(n) + ".0"
            if let value = streetBind(got.binds, oid) {
                lines.append((
                    String(format: L("%@: %@"),
                           labels[n - 1], value),
                    .out))
                shown += 1
            }
        }
        if shown > 0 {
            lines.append((L("the numbers are the sign's own, in the standard's own units — read as published, not converted"), .out))
        }
        return lines
    }

    static func streetDMSProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip) = streetHost(target)
            else {
                icsSay(emit, L("dmsprobe: give the sign's host — dmsprobe 192.168.1.51"), .err)
                return
            }
            icsPrint(emit, streetDMSCore(
                ip, light: false))
        }
    }

    /// NTCIP 1204's identification branch:
    /// the station's category and the
    /// site description it publishes.
    static func streetRWISCore(
        _ ip: String, light: Bool) -> [ICSLine] {
        var lines = streetNTCIPCore(ip, light: light)
        guard !lines.isEmpty else { return lines }
        let essOIDs: [[Int]] = [
            [1, 3, 6, 1, 4, 1, 1206, 4, 2, 5, 2, 1, 1, 0],
            [1, 3, 6, 1, 4, 1, 1206, 4, 2, 5, 2, 1, 2, 0],
        ]
        guard let got = streetSNMPGet(ip, essOIDs),
              !got.binds.isEmpty else {
            if !light {
                lines.append((L("the 1204 identification branch stayed silent — the nameplate above is what this door publishes"), .out))
            }
            return lines
        }
        if let category = streetBind(
            got.binds,
            "1.3.6.1.4.1.1206.4.2.5.2.1.1.0") {
            lines.append((
                String(format: L("station category, in the standard's numbering: %@"),
                       category), .out))
        }
        if let site = streetBind(
            got.binds,
            "1.3.6.1.4.1.1206.4.2.5.2.1.2.0") {
            lines.append((
                String(format: L("it names its site: %@"),
                       site), .out))
        }
        return lines
    }

    static func streetRWISProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip) = streetHost(target)
            else {
                icsSay(emit, L("rwisprobe: give the station's host — rwisprobe 192.168.1.52"), .err)
                return
            }
            icsPrint(emit, streetRWISCore(
                ip, light: false))
        }
    }

    /// A roadside unit's network nameplate:
    /// the same NTCIP identification every
    /// roadside box carries. Its own MIB
    /// branch and its radios are handled
    /// honestly in the lines themselves.
    static func streetRSUCore(
        _ ip: String, light: Bool) -> [ICSLine] {
        var lines = streetNTCIPCore(ip, light: light)
        guard !lines.isEmpty else { return lines }
        lines.append((L("the unit's radios — DSRC and C-V2X on 5.9 GHz — are not IP and not reachable from an iOS app; nothing here was transmitted to them, and no vehicle message was read"), .out))
        if !light {
            lines.append((L("note: the roadside-unit MIB grows a description branch of its own, but its numeric root is not published in a form this bench could verify — so the branch is named here and never probed. An invented object id is how benches lie"), .out))
        }
        return lines
    }

    static func streetRSUProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let (_, ip) = streetHost(target)
            else {
                icsSay(emit, L("rsuprobe: give the roadside unit's host — rsuprobe 192.168.1.53"), .err)
                return
            }
            icsPrint(emit, streetRSUCore(
                ip, light: false))
        }
    }

    // MARK: - published feeds: SPaT, the ALPR map, DOT ledgers

    /// Unwrap an ODE-shaped SPaT document
    /// down to the object that carries the
    /// intersections array, whichever
    /// envelope the publisher wrapped it in.
    static func streetSPaTRoot(
        _ node: Any?) -> [String: Any]? {
        guard let dict = node as? [String: Any]
        else { return nil }
        if dict["intersections"]
            is [[String: Any]] {
            return dict
        }
        for key in ["payload", "data", "value",
                    "SPAT", "SpatMessage"] {
            if let inner = streetSPaTRoot(
                dict[key]) {
                return inner
            }
        }
        return nil
    }

    /// A published SPaT feed, read as
    /// published: the intersections and the
    /// phase states the agency itself
    /// broadcasts. A feed read — no
    /// controller is knocked. Field names
    /// follow SAE J2735 as the USDOT ODE
    /// serializes them.
    static func streetSPaTProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let url = streetFeedURL(target)
            else {
                icsSay(emit, L("spatprobe: name the published feed — spatprobe https://agency.example/spat.json"), .err)
                return
            }
            guard let got = satFetch(url) else {
                icsSay(emit, L("spatprobe: the feed did not answer"), .err)
                return
            }
            guard got.status == 200,
                  let root = streetSPaTRoot(
                    satJSON(got.body)),
                  let intersections =
                    root["intersections"]
                        as? [[String: Any]]
            else {
                icsSay(emit, String(format: L("spatprobe: the feed answered (HTTP %lld) but carries no SPaT intersections this verb can read — reported, not guessed"),
                                     Int64(got.status)), .err)
                return
            }
            icsSay(emit, String(format: L("spatprobe — %@"), url.absoluteString), .sys)
            icsSay(emit, String(format: L("%lld intersection(s) in the published snapshot"),
                                Int64(intersections.count)), .out)
            for intersection in intersections.prefix(6) {
                var head = ""
                if let idDict = intersection["id"]
                    as? [String: Any],
                   let id = streetInt(idDict["id"]) {
                    head = String(
                        format: L("intersection %lld"),
                        Int64(id))
                } else if let id = streetInt(
                    intersection["id"]) {
                    head = String(
                        format: L("intersection %lld"),
                        Int64(id))
                }
                if let name = intersection["name"]
                    as? String, !name.isEmpty {
                    head = head.isEmpty ? name
                        : head + " — " + name
                }
                if !head.isEmpty {
                    icsSay(emit, head, .sys)
                }
                let states = intersection["states"]
                    as? [[String: Any]] ?? []
                for state in states.prefix(10) {
                    let group = streetInt(
                        state["signalGroup"]) ?? 0
                    let events = state[
                        "state-time-speed"]
                        as? [[String: Any]] ?? []
                    guard let event = events.first,
                          let eventState =
                            event["eventState"]
                                as? String
                    else { continue }
                    var text = String(
                        format: L("group %lld: %@"),
                        Int64(group), eventState)
                    if let timing =
                        event["timing"]
                            as? [String: Any],
                       let minEnd = streetInt(
                        timing["minEndTime"]) {
                        text += String(
                            format: L(" · earliest end at time-mark %lld (tenths of a second into the hour, as J2735 publishes it)"),
                            Int64(minEnd))
                    }
                    icsSay(emit, text, .out)
                }
            }
            icsSay(emit, L("read: the agency's published snapshot only — phase states as the feed states them, at the moment it was fetched. No controller was knocked and nothing was asked of the street"), .out)
        }
    }

    /// The ALPR census from the PUBLIC
    /// map: OpenStreetMap points tagged in
    /// the DeFlock convention, read through
    /// the Overpass API. The map is the
    /// read; no camera is ever touched.
    static func streetFlockCensus(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let place = target,
                  !place.isEmpty else {
                icsSay(emit, L("flockcensus: name a place — flockcensus Boulder, Colorado"), .err)
                return
            }
            guard let geo = streetGeocode(place)
            else {
                icsSay(emit, L("flockcensus: the map's geocoder does not know that place"), .err)
                return
            }
            let coords = String(
                format: "%.5f,%.5f", geo.lat, geo.lon)
            let ql = "[out:json][timeout:25];("
                + "node[\"man_made\"=\"surveillance\"]"
                + "(around:3000," + coords + ");"
                + "way[\"man_made\"=\"surveillance\"]"
                + "(around:3000," + coords + ");"
                + ");out body 120;"
            guard let elements =
                streetOverpass(ql) else {
                icsSay(emit, L("flockcensus: the public map (Overpass) did not answer"), .err)
                return
            }
            var alpr: [[String: String]] = []
            var typeTally: [String: Int] = [:]
            var operatorTally: [String: Int] = [:]
            for element in elements {
                let tags = streetTagsOf(element)
                let kind = tags["surveillance:type"]
                    ?? L("type not published")
                typeTally[kind, default: 0] += 1
                if tags["surveillance:type"]
                    == "ALPR" {
                    alpr.append(tags)
                    let op = tags["operator"]
                        ?? L("operator not published")
                    operatorTally[op,
                                  default: 0] += 1
                }
            }
            icsSay(emit, String(format: L("flockcensus — %@"), geo.name), .sys)
            icsSay(emit, String(format: L("%lld surveillance point(s) on the public map within 3 km — %lld of them tagged ALPR"),
                                Int64(elements.count),
                                Int64(alpr.count)), .out)
            let types = typeTally.sorted {
                $0.value != $1.value
                    ? $0.value > $1.value
                    : $0.key < $1.key
            }
            for entry in types.prefix(5) {
                icsSay(emit, String(format: L("  %@: %lld"),
                                    entry.key,
                                    Int64(entry.value)), .out)
            }
            if !operatorTally.isEmpty {
                icsSay(emit, L("ALPR operators, as the map tags them:"), .out)
                let ops = operatorTally.sorted {
                    $0.value != $1.value
                        ? $0.value > $1.value
                        : $0.key < $1.key
                }
                for entry in ops.prefix(5) {
                    icsSay(emit, String(format: L("  %@: %lld"),
                                        entry.key,
                                        Int64(entry.value)), .out)
                }
            }
            for tags in alpr.prefix(5) {
                let brand = tags["brand"]
                    ?? tags["manufacturer"]
                    ?? L("make not published")
                let op = tags["operator"]
                    ?? L("operator not published")
                icsSay(emit, String(format: L("  ALPR: %@ — %@ (as the map tags it)"),
                                    brand, op), .out)
            }
            icsSay(emit, L("source: OpenStreetMap read through the Overpass API — the same public ledger the DeFlock map draws from"), .out)
            icsSay(emit, L("map data is crowdsourced and lags the street: a camera can stand unmapped, and a mapped one can be gone. Absence here proves nothing"), .out)
            icsSay(emit, L("this read touches the map only — no camera, plate list, hotlist or capture was requested or received"), .out)
        }
    }

    /// A state DOT / 511 published camera
    /// ledger, censused as the agency
    /// itself publishes it. The Caltrans
    /// CCTV shape is read natively; other
    /// JSON ledgers fall back to the
    /// largest object array they carry.
    static func streetDOTProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let url = streetFeedURL(target)
            else {
                icsSay(emit, L("dotprobe: name the agency's published feed — dotprobe https://agency.example/cameras.json"), .err)
                return
            }
            guard let got = satFetch(url) else {
                icsSay(emit, L("dotprobe: the feed did not answer"), .err)
                return
            }
            guard got.status == 200 else {
                icsSay(emit, String(format: L("dotprobe: the feed answered HTTP %lld — no ledger read"),
                                     Int64(got.status)), .err)
                return
            }
            icsSay(emit, String(format: L("dotprobe — %@"), url.absoluteString), .sys)
            let doc = satJSON(got.body)
            if let dict = doc as? [String: Any],
               let data = dict["data"]
                as? [[String: Any]],
               let first = data.first,
               first["cctv"] != nil {
                icsSay(emit, String(format: L("%lld camera(s) in the published ledger"),
                                    Int64(data.count)), .out)
                for entry in data.prefix(6) {
                    guard let cctv = entry["cctv"]
                        as? [String: Any],
                          let location =
                            cctv["location"]
                                as? [String: Any],
                          let name =
                            location["locationName"]
                                as? String
                    else { continue }
                    var text = "  " + name
                    if let place =
                        location["nearbyPlace"]
                            as? String,
                       !place.isEmpty {
                        text += " · " + place
                    }
                    icsSay(emit, text, .out)
                }
                icsSay(emit, L("read: the agency's published camera ledger (the Caltrans shape) — names and places as the state itself lists them. No camera was opened and no image was fetched"), .out)
                return
            }
            if let dict = doc as? [String: Any],
               let features = dict["features"]
                as? [[String: Any]] {
                icsSay(emit, String(format: L("%lld feature(s) in the published GeoJSON ledger"),
                                    Int64(features.count)), .out)
                for feature in features.prefix(6) {
                    if let props =
                        feature["properties"]
                            as? [String: Any],
                       let name = (props["name"]
                        ?? props["title"])
                            as? String {
                        icsSay(emit, "  " + name, .out)
                    }
                }
                icsSay(emit, L("read: the agency's published GeoJSON ledger — features as published. No camera was opened and no image was fetched"), .out)
                return
            }
            if let dict = doc as? [String: Any] {
                var largest: [[String: Any]] = []
                for value in dict.values {
                    if let array = value
                        as? [[String: Any]],
                       array.count > largest.count {
                        largest = array
                    }
                }
                if !largest.isEmpty {
                    icsSay(emit, String(format: L("%lld record(s) in the feed's largest table"),
                                        Int64(largest.count)), .out)
                    icsSay(emit, L("read: a published JSON ledger in a shape this verb counts but does not name — the count is the feed's own; no field was guessed at"), .out)
                    return
                }
            }
            icsSay(emit, String(format: L("the feed answered %lld bytes, but in no published camera-ledger shape this verb can census — that is reported, and nothing is counted"),
                                Int64(got.body.utf8.count)), .err)
        }
    }

    // MARK: - camera nameplates: ONVIF and the vendor doors

    /// One ONVIF SOAP read. The envelopes
    /// are the standard's own, verified
    /// against the official WSDLs; the
    /// only operations this wave ever
    /// builds are identification reads.
    static func streetSOAP(
        _ host: String, _ port: Int,
        _ path: String, _ inner: String)
        -> (status: Int, body: String)? {
        guard let url = URL(string:
                "http://" + host + ":"
                + String(port) + path)
        else { return nil }
        let envelope =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<s:Envelope xmlns:s="
            + "\"http://schemas.xmlsoap.org/soap/envelope/\">"
            + "<s:Body>" + inner
            + "</s:Body></s:Envelope>"
        guard let got = streetPOST(
            url,
            contentType:
                "application/soap+xml; charset=utf-8",
            body: Array(envelope.utf8))
        else { return nil }
        return (got.status, got.body)
    }

    static let streetDeviceNS =
        "http://www.onvif.org/ver10/device/wsdl"
    static let streetPTZNS =
        "http://www.onvif.org/ver20/ptz/wsdl"

    /// The camera nameplate standard:
    /// GetDeviceInformation, then the
    /// scopes it publishes about itself.
    static func streetONVIFCore(
        _ host: String, _ port: Int,
        light: Bool) -> [ICSLine] {
        let inner = "<tds:GetDeviceInformation"
            + " xmlns:tds=\"" + streetDeviceNS
            + "\"/>"
        guard let resp = streetSOAP(
            host, port, "/onvif/device_service",
            inner) else {
            return light ? [] : [(
                String(format: L("onvifprobe — no answer at %@:%lld"),
                       host, Int64(port)), .err)]
        }
        if resp.status == 401
            || resp.status == 403 {
            return [(
                String(format: L("the ONVIF door at %@:%lld demands a login (HTTP %lld) — the nameplate stays shut, which is the posture a camera should keep"),
                       host, Int64(port),
                       Int64(resp.status)), .out)]
        }
        guard resp.status == 200,
              streetTag(resp.body,
                        "Manufacturer") != nil
        else {
            return light ? [] : [(
                String(format: L("%@:%lld answered HTTP %lld but not like an ONVIF camera — noted, not named"),
                       host, Int64(port),
                       Int64(resp.status)), .sys)]
        }
        var lines: [ICSLine] = [(
            String(format: L("onvif nameplate — %@:%lld"),
                   host, Int64(port)), .sys)]
        let fields: [(String, String)] = [
            (L("maker"), "Manufacturer"),
            (L("model"), "Model"),
            (L("firmware"), "FirmwareVersion"),
            (L("serial"), "SerialNumber"),
            (L("hardware id"), "HardwareId"),
        ]
        for (label, tag) in fields {
            if let value = streetTag(
                resp.body, tag) {
                lines.append((
                    String(format: L("%@: %@"),
                           label, value), .out))
            }
        }
        let scopesInner = "<tds:GetScopes"
            + " xmlns:tds=\"" + streetDeviceNS
            + "\"/>"
        if let scopes = streetSOAP(
            host, port, "/onvif/device_service",
            scopesInner), scopes.status == 200 {
            let items = streetTags(
                scopes.body, "ScopeItem")
            for item in items.prefix(6) {
                let short = item
                    .replacingOccurrences(
                        of: "onvif://www.onvif.org/",
                        with: "")
                lines.append((
                    String(format: L("scope: %@"),
                           short), .out))
            }
        }
        lines.append((L("grade: the nameplate is public — maker, model, firmware and serial answered with no login at all, so anyone on this wire can inventory this camera to the unit"), .err))
        lines.append((L("read: ONVIF GetDeviceInformation + GetScopes — the identification reads, and nothing else"), .out))
        return lines
    }

    static func streetONVIFProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("onvifprobe: give the camera's host — onvifprobe 192.168.1.64"), .err)
                return
            }
            icsPrint(emit, streetONVIFCore(
                resolved.host, Int(resolved.port),
                light: false))
        }
    }

    /// The vendor nameplate doors, knocked
    /// in turn: Axis VAPIX properties,
    /// Hikvision ISAPI deviceInfo, Dahua's
    /// system-info CGI. Whichever answers
    /// without a login names the camera.
    static func streetCamDeepCore(
        _ host: String, _ port: Int,
        light: Bool) -> [ICSLine] {
        var lines: [ICSLine] = []
        var refused = 0
        func kvLines(_ body: String)
            -> [String: String] {
            var out: [String: String] = [:]
            for raw in body.components(
                separatedBy: "\n") {
                let line = raw
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                guard let eq = line.firstIndex(
                    of: "=") else { continue }
                let key = String(
                    line[..<eq])
                let value = String(
                    line[line.index(
                        after: eq)...])
                    .trimmingCharacters(
                        in: .whitespaces)
                if !value.isEmpty {
                    out[key] = value
                }
            }
            return out
        }
        func suffixValue(
            _ table: [String: String],
            _ suffix: String) -> String? {
            for (key, value) in table
                where key.hasSuffix(suffix) {
                return value
            }
            return nil
        }
        // Axis — two property groups.
        var axisParts: [String] = []
        var axisAnswered = false
        for group in ["Properties.System",
                      "Brand"] {
            guard let url = URL(string:
                    "http://" + host + ":"
                    + String(port)
                    + "/axis-cgi/param.cgi"
                    + "?action=list&group="
                    + group)
            else { continue }
            guard let got = satFetch(url)
            else { continue }
            if got.status == 401
                || got.status == 403 {
                refused += 1
                continue
            }
            guard got.status == 200,
                  got.body.contains("root.")
            else { continue }
            axisAnswered = true
            let table = kvLines(got.body)
            if let full = suffixValue(
                table, "ProdFullName") {
                axisParts.append(full)
            } else if let nbr = suffixValue(
                table, "ProdNbr") {
                axisParts.append(nbr)
            }
            if let serial = suffixValue(
                table, "SerialNumber") {
                axisParts.append(
                    String(format: L("serial %@"),
                           serial))
            }
            if let firmware = suffixValue(
                table, "FirmwareVersion") {
                axisParts.append(
                    String(format: L("firmware %@"),
                           firmware))
            }
        }
        if axisAnswered {
            lines.append((
                String(format: L("Axis nameplate: %@"),
                       axisParts.isEmpty
                        ? L("answered, fields unnamed")
                        : axisParts.joined(
                            separator: " · ")),
                .out))
        }
        // Hikvision — ISAPI deviceInfo.
        if let url = URL(string:
                "http://" + host + ":"
                + String(port)
                + "/ISAPI/System/deviceInfo"),
           let got = satFetch(url) {
            if got.status == 401
                || got.status == 403 {
                refused += 1
            } else if got.status == 200,
                      let model = streetTag(
                        got.body, "model") {
                var text = String(
                    format: L("Hikvision nameplate: %@"),
                    model)
                if let serial = streetTag(
                    got.body, "serialNumber") {
                    text += String(
                        format: L(" · serial %@"),
                        serial)
                }
                if let firmware = streetTag(
                    got.body, "firmwareVersion") {
                    text += String(
                        format: L(" · firmware %@"),
                        firmware)
                }
                lines.append((text, .out))
            }
        }
        // Dahua — the system-info CGI.
        if let url = URL(string:
                "http://" + host + ":"
                + String(port)
                + "/cgi-bin/magicBox.cgi"
                + "?action=getSystemInfo"),
           let got = satFetch(url) {
            if got.status == 401
                || got.status == 403 {
                refused += 1
            } else if got.status == 200 {
                let table = kvLines(got.body)
                var lower: [String: String] = [:]
                for (key, value) in table {
                    lower[key.lowercased()] = value
                }
                if let type = lower["devicetype"] {
                    var text = String(
                        format: L("Dahua nameplate: %@"),
                        type)
                    if let serial =
                        lower["serialnumber"] {
                        text += String(
                            format: L(" · serial %@"),
                            serial)
                    }
                    if let version =
                        lower["version"] {
                        text += String(
                            format: L(" · firmware %@"),
                            version)
                    }
                    lines.append((text, .out))
                }
            }
        }
        if lines.isEmpty {
            if refused > 0 {
                return [(
                    String(format: L("every vendor door at %@:%lld demanded a login — the nameplates stay shut, which is the posture a camera should keep"),
                           host, Int64(port)), .out)]
            }
            return light ? [] : [(
                String(format: L("camdeep — no vendor nameplate door answers at %@:%lld"),
                       host, Int64(port)), .err)]
        }
        var all: [ICSLine] = [(
            String(format: L("camdeep — %@:%lld"),
                   host, Int64(port)), .sys)]
        all.append(contentsOf: lines)
        all.append((L("grade: a vendor nameplate answered with no login — this camera introduces itself, down to its serial number, to anyone who asks"), .err))
        all.append((L("read: the vendors' own published device-info reads (Axis VAPIX properties, Hikvision ISAPI, Dahua system info) — identification only; no image, stream or recording was requested"), .out))
        return all
    }

    static func streetCamDeep(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("camdeep: give the camera's host — camdeep 192.168.1.64"), .err)
                return
            }
            icsPrint(emit, streetCamDeepCore(
                resolved.host, Int(resolved.port),
                light: false))
        }
    }

    /// The PTZ census: the ONVIF service
    /// list, then the PTZ service's own
    /// node and configuration lists. These
    /// reads prove a steerable camera and
    /// an open door — no movement operation
    /// is constructed anywhere in this
    /// wave, in this verb least of all.
    static func streetPTZCore(
        _ host: String, _ port: Int,
        light: Bool) -> [ICSLine] {
        let servicesInner = "<tds:GetServices"
            + " xmlns:tds=\"" + streetDeviceNS
            + "\"><tds:IncludeCapability>"
            + "false</tds:IncludeCapability>"
            + "</tds:GetServices>"
        guard let services = streetSOAP(
            host, port, "/onvif/device_service",
            servicesInner) else {
            return light ? [] : [(
                String(format: L("ptzprobe — no answer at %@:%lld"),
                       host, Int64(port)), .err)]
        }
        if services.status == 401
            || services.status == 403 {
            return [(
                String(format: L("the ONVIF door at %@:%lld demands a login (HTTP %lld) — its service list, and its steering, stay shut"),
                       host, Int64(port),
                       Int64(services.status)), .out)]
        }
        guard services.status == 200 else {
            return light ? [] : [(
                String(format: L("%@:%lld answered HTTP %lld but not like an ONVIF camera — noted, not named"),
                       host, Int64(port),
                       Int64(services.status)), .sys)]
        }
        let namespaces = streetTags(
            services.body, "Namespace")
        let xaddrs = streetTags(
            services.body, "XAddr")
        var ptzPath: String? = nil
        for (index, ns) in namespaces.enumerated()
            where ns == streetPTZNS {
            if index < xaddrs.count,
               let parsed = URL(
                string: xaddrs[index]) {
                ptzPath = parsed.path
            }
        }
        guard let path = ptzPath else {
            return [(
                L("ONVIF answers, but its service list publishes no PTZ service — a fixed camera, by its own account"), .out),
                (L("read: ONVIF GetServices only"), .out)]
        }
        var lines: [ICSLine] = [(
            String(format: L("ptz census — %@:%lld"),
                   host, Int64(port)), .sys)]
        let nodesInner = "<tptz:GetNodes"
            + " xmlns:tptz=\"" + streetPTZNS
            + "\"/>"
        if let nodes = streetSOAP(
            host, port, path, nodesInner),
           nodes.status == 200 {
            let count = streetTagCount(
                nodes.body, "PTZNode")
            lines.append((
                String(format: L("%lld PTZ node(s) published"),
                       Int64(count)), .out))
            for name in streetTags(
                nodes.body, "Name").prefix(5) {
                lines.append((
                    String(format: L("  node: %@"),
                           name), .out))
            }
        }
        let confsInner =
            "<tptz:GetConfigurations"
            + " xmlns:tptz=\"" + streetPTZNS
            + "\"/>"
        if let confs = streetSOAP(
            host, port, path, confsInner),
           confs.status == 200 {
            let count = streetTagCount(
                confs.body, "PTZConfiguration")
            lines.append((
                String(format: L("%lld saved PTZ configuration(s)"),
                       Int64(count)), .out))
            for name in streetTags(
                confs.body, "Name").prefix(5) {
                lines.append((
                    String(format: L("  configuration: %@"),
                           name), .out))
            }
        }
        lines.append((L("grade: this camera publishes its steering nodes to a stranger — the service that lists them is the service that moves them, behind the same absent login. The reads prove the door; no movement order was sent, and none exists in this verb"), .err))
        lines.append((L("read: ONVIF GetServices + GetNodes + GetConfigurations — census reads only"), .out))
        return lines
    }

    static func streetPTZProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("ptzprobe: give the camera's host — ptzprobe 192.168.1.64"), .err)
                return
            }
            icsPrint(emit, streetPTZCore(
                resolved.host, Int(resolved.port),
                light: false))
        }
    }

    // MARK: - drones, heard and never hailed

    /// Remote ID, listened to: six seconds
    /// of the Bluetooth air for ASTM F3411
    /// broadcasts, decoded by the house
    /// decoder in Drones.swift. IDs are
    /// printed exactly as broadcast — the
    /// drone names itself; the bench only
    /// listens, and transmits nothing.
    static func streetRIDProbe(
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let scanner = StreetRIDScanner()
            scanner.begin()
            _ = scanner.gate.wait(
                timeout: .now() + 9.0)
            scanner.stop()
            switch scanner.finalState {
            case .poweredOff:
                icsSay(emit, L("ridprobe: Bluetooth is off — the ear is closed"), .err)
                return
            case .unauthorized:
                icsSay(emit, L("ridprobe: Bluetooth is not permitted for this app — the ear is closed"), .err)
                return
            case .unsupported:
                icsSay(emit, L("ridprobe: this device has no Bluetooth LE ear to listen with"), .err)
                return
            default:
                break
            }
            let reports = scanner.collected()
            icsSay(emit, L("ridprobe — six seconds of the Bluetooth air, listened to only"), .sys)
            if reports.isEmpty {
                icsSay(emit, L("no Remote ID broadcast heard — no drone is announcing itself within Bluetooth reach right now"), .out)
            }
            for report in reports {
                icsSay(emit, Drones.describe(
                    report), .out)
            }
            if reports.count > 1 {
                icsSay(emit, String(format: L("%lld drone(s) heard, each named as it names itself"),
                                    Int64(reports.count)), .out)
            }
            icsSay(emit, L("listen-only: nothing was transmitted, paired or connected. iOS shows apps the Bluetooth half of Remote ID; the Wi-Fi broadcasts are not exposed to apps at all"), .out)
        }
    }

    // MARK: - streetlights and sirens: the degraded two

    /// A networked streetlight gateway.
    /// The control protocol is TALQ — a
    /// secured, vendor-operated standard
    /// with no public unauthenticated
    /// identification read — so this verb
    /// reads the gateway's web door and
    /// says exactly that.
    static func streetLightCore(
        _ host: String, _ port: Int,
        light: Bool) -> [ICSLine] {
        guard let url = URL(string:
                "http://" + host + ":"
                + String(port) + "/"),
              let got = satFetch(url) else {
            return light ? [] : [(
                String(format: L("streetlightprobe — no web door answers at %@:%lld"),
                       host, Int64(port)), .err)]
        }
        var lines: [ICSLine] = [(
            String(format: L("streetlightprobe — %@:%lld"),
                   host, Int64(port)), .sys)]
        var named = false
        if let server = got.headers["server"] {
            lines.append((
                String(format: L("web door: %@"),
                       server), .out))
            named = true
        }
        if let title = streetTag(
            got.body, "title") {
            lines.append((
                String(format: L("page title: %@"),
                       title), .out))
            named = true
        }
        if got.body.lowercased()
            .contains("talq") {
            lines.append((L("its own page speaks of TALQ — noted as the door's claim, nothing more"), .out))
            named = true
        }
        if got.status != 200 {
            lines.append((
                String(format: L("the web door answered HTTP %lld"),
                       Int64(got.status)), .out))
        }
        if named {
            lines.append((L("grade: the gateway's web door introduces itself to strangers — the lighting network behind it is another matter, and is not claimed here"), .err))
        }
        lines.append((L("streetlight networks are run over TALQ — a secured, vendor-operated protocol with no public nameplate read. What answers here is the gateway's web door, and that is all this verb claims"), .out))
        return lines
    }

    static func streetLightProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("streetlightprobe: give the gateway's host — streetlightprobe 192.168.1.70"), .err)
                return
            }
            icsPrint(emit, streetLightCore(
                resolved.host, Int(resolved.port),
                light: false))
        }
    }

    /// An outdoor warning siren controller.
    /// There is no public IP identification
    /// protocol for this class — activation
    /// and management ride radio tones and
    /// vendor paths — so the read is the
    /// management doors' census and the
    /// web nameplate, and nothing else
    /// exists to send.
    static func streetSirenCore(
        _ host: String, _ ip: String,
        light: Bool) -> [ICSLine] {
        var open: [Int] = []
        for port in [80, 443, 22, 23] {
            if let fd = icsSocket(
                ip: ip, port: UInt16(port),
                timeout: 1.2) {
                close(fd)
                open.append(port)
            }
        }
        guard !open.isEmpty else {
            return light ? [] : [(
                String(format: L("sirenprobe — no management door answers at %@"),
                       host), .err)]
        }
        var lines: [ICSLine] = [(
            String(format: L("sirenprobe — %@"),
                   host), .sys)]
        lines.append((
            String(format: L("management doors answering: %@"),
                   open.map(String.init)
                    .joined(separator: ", ")),
            .out))
        if open.contains(80),
           let url = URL(string:
                "http://" + host + "/"),
           let got = satFetch(url),
           got.status == 200 {
            let vendors = ["Federal Signal",
                           "ATI Systems", "Whelen",
                           "American Signal",
                           "Modulator", "Eclipse",
                           "Sentry"]
            for vendor in vendors
                where got.body.contains(vendor) {
                lines.append((
                    String(format: L("its web door names: %@ — the maker's own word on its own page"),
                           vendor), .out))
                break
            }
            if let server = got.headers["server"] {
                lines.append((
                    String(format: L("web door: %@"),
                           server), .out))
            }
        }
        lines.append((L("grade: a warning siren's controller keeps management doors on the wire — identified here, and that is the whole interaction"), .err))
        if !light {
            lines.append((L("read: door knocks and the web nameplate only. No activation frame exists in this bench — sounding a siren rides radio tones and vendor paths, and none of it was touched"), .out))
        }
        return lines
    }

    static func streetSirenProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let pair = streetHost(target)
            else {
                icsSay(emit, L("sirenprobe: give the controller's host — sirenprobe 192.168.1.71"), .err)
                return
            }
            icsPrint(emit, streetSirenCore(
                pair.host, pair.ip, light: false))
        }
    }

    // MARK: - the sensed city: transit, water, air, bikes, towers

    /// A protobuf field walk — the slice
    /// of the wire format GTFS-realtime
    /// needs: varints, length-delimited
    /// and 32-bit fields, bounds-checked
    /// throughout. Field numbers verified
    /// against google/transit's proto.
    static func streetPBFields(
        _ bytes: [UInt8])
        -> [(num: Int, wt: Int,
             payload: [UInt8], value: Int)] {
        var out: [(num: Int, wt: Int,
                   payload: [UInt8],
                   value: Int)] = []
        var index = 0
        func readVarint() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 {
                    return result
                }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while index < bytes.count {
            guard let key = readVarint()
            else { return out }
            let num = key >> 3
            let wt = key & 7
            switch wt {
            case 0:
                guard let value = readVarint()
                else { return out }
                out.append((num, wt, [], value))
            case 2:
                guard let length = readVarint(),
                      index + length <= bytes.count
                else { return out }
                out.append((num, wt,
                            Array(bytes[
                                index..<(index
                                    + length)]), 0))
                index += length
            case 5:
                guard index + 4 <= bytes.count
                else { return out }
                out.append((num, wt,
                            Array(bytes[
                                index..<(index + 4)]),
                            0))
                index += 4
            case 1:
                guard index + 8 <= bytes.count
                else { return out }
                out.append((num, wt,
                            Array(bytes[
                                index..<(index + 8)]),
                            0))
                index += 8
            default:
                return out
            }
        }
        return out
    }

    static func streetPBFloat(
        _ payload: [UInt8]) -> Double? {
        guard payload.count == 4 else {
            return nil
        }
        let bits = UInt32(payload[0])
            | UInt32(payload[1]) << 8
            | UInt32(payload[2]) << 16
            | UInt32(payload[3]) << 24
        return Double(Float32(bitPattern: bits))
    }

    /// A published GTFS-realtime feed:
    /// the agency's own vehicle census,
    /// parsed off the wire format (or the
    /// JSON serialization where a feed
    /// publishes that instead).
    static func streetTransitProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let url = streetFeedURL(target)
            else {
                icsSay(emit, L("transitprobe: name the published feed — transitprobe https://agency.example/gtfsrt/vehicles"), .err)
                return
            }
            guard let (data, http) = icsFetch(url),
                  http.statusCode == 200 else {
                icsSay(emit, L("transitprobe: the feed did not answer"), .err)
                return
            }
            icsSay(emit, String(format: L("transitprobe — %@"), url.absoluteString), .sys)
            let bytes = [UInt8](data)
            if bytes.first == 0x7B {
                guard let doc = satJSON(
                        String(decoding: data,
                               as: UTF8.self))
                        as? [String: Any],
                      let entities = doc["entity"]
                        as? [[String: Any]]
                else {
                    icsSay(emit, L("transitprobe: the feed answered JSON, but not in the GTFS-realtime shape — reported, not guessed"), .err)
                    return
                }
                var vehicles = 0
                var samples: [String] = []
                for entity in entities {
                    guard let vehicle =
                        entity["vehicle"]
                            as? [String: Any]
                    else { continue }
                    vehicles += 1
                    if samples.count < 6,
                       let descriptor =
                        vehicle["vehicle"]
                            as? [String: Any],
                       let id = descriptor["id"]
                        as? String {
                        samples.append(id)
                    }
                }
                icsSay(emit, String(format: L("%lld vehicle(s) reporting in the published feed"),
                                    Int64(vehicles)), .out)
                for sample in samples {
                    icsSay(emit, "  " + sample, .out)
                }
                icsSay(emit, L("read: the agency's published realtime feed, in its JSON serialization — vehicles as the feed itself reports them"), .out)
                return
            }
            var version = ""
            var vehicles: [(id: String,
                             label: String?,
                             lat: Double?,
                             lon: Double?)] = []
            var tripUpdates = 0
            var alerts = 0
            for field in streetPBFields(bytes) {
                if field.num == 1 {
                    for head in streetPBFields(
                        field.payload)
                        where head.num == 1 {
                        version = String(
                            decoding: head.payload,
                            as: UTF8.self)
                    }
                }
                if field.num == 2 {
                    for entity in streetPBFields(
                        field.payload) {
                        if entity.num == 3 {
                            tripUpdates += 1
                        }
                        if entity.num == 5 {
                            alerts += 1
                        }
                        if entity.num == 4 {
                            var id = ""
                            var label: String? = nil
                            var lat: Double? = nil
                            var lon: Double? = nil
                            for part in
                                streetPBFields(
                                    entity.payload) {
                                if part.num == 2 {
                                    for p in
                                        streetPBFields(
                                            part.payload) {
                                        if p.num == 1 {
                                            lat =
                                                streetPBFloat(
                                                    p.payload)
                                        }
                                        if p.num == 2 {
                                            lon =
                                                streetPBFloat(
                                                    p.payload)
                                        }
                                    }
                                }
                                if part.num == 8 {
                                    for d in
                                        streetPBFields(
                                            part.payload) {
                                        if d.num == 1 {
                                            id = String(
                                                decoding: d.payload,
                                                as: UTF8.self)
                                        }
                                        if d.num == 2 {
                                            label = String(
                                                decoding: d.payload,
                                                as: UTF8.self)
                                        }
                                    }
                                }
                            }
                            vehicles.append((
                                id, label, lat, lon))
                        }
                    }
                }
            }
            icsSay(emit, String(format: L("GTFS-realtime %@ — %lld vehicle(s) reporting, %lld trip update(s), %lld alert(s)"),
                                version.isEmpty
                                    ? "2.0" : version,
                                Int64(vehicles.count),
                                Int64(tripUpdates),
                                Int64(alerts)), .out)
            for vehicle in vehicles.prefix(6) {
                var text = "  "
                    + (vehicle.id.isEmpty
                        ? L("vehicle id not published")
                        : vehicle.id)
                if let label = vehicle.label,
                   !label.isEmpty {
                    text += " — " + label
                }
                if let lat = vehicle.lat,
                   let lon = vehicle.lon {
                    text += String(
                        format: " · %.4f, %.4f",
                        lat, lon)
                }
                icsSay(emit, text, .out)
            }
            icsSay(emit, L("read: the agency's published realtime feed — vehicle positions as the feed itself broadcasts them, parsed off the GTFS-realtime wire format"), .out)
        }
    }

    /// The USGS gauge ledger: stream and
    /// flood gauges around a place (or one
    /// named by its site number), with the
    /// latest published levels. Source is
    /// the National Water Information
    /// System, read as published.
    static func streetGaugeProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = target,
                  !target.isEmpty else {
                icsSay(emit, L("gaugeprobe: name a place or a USGS site number — gaugeprobe Boulder, Colorado"), .err)
                return
            }
            var query: String? = nil
            var heading = target
            if target.allSatisfy(
                { $0.isNumber }),
               target.count >= 8 {
                query = "sites=" + target
            } else if let geo = streetGeocode(
                target) {
                query = String(
                    format: "bBox=%.4f,%.4f,%.4f,%.4f",
                    geo.lon - 0.2, geo.lat - 0.15,
                    geo.lon + 0.2, geo.lat + 0.15)
                heading = geo.name
            }
            guard let query = query,
                  let url = URL(string:
                    "https://waterservices.usgs.gov"
                    + "/nwis/iv/?format=json"
                    + "&parameterCd=00065,00060"
                    + "&siteStatus=active&"
                    + query),
                  let got = satFetch(url),
                  got.status == 200,
                  let doc = satJSON(got.body)
                    as? [String: Any],
                  let value = doc["value"]
                    as? [String: Any],
                  let series = value["timeSeries"]
                    as? [[String: Any]]
            else {
                icsSay(emit, L("gaugeprobe: the USGS ledger did not answer for that place"), .err)
                return
            }
            icsSay(emit, String(format: L("gaugeprobe — %@"), heading), .sys)
            var sites = Set<String>()
            var shown = 0
            for entry in series {
                guard let source =
                    entry["sourceInfo"]
                        as? [String: Any],
                      let siteName =
                        source["siteName"]
                            as? String
                else { continue }
                if let codes =
                    source["siteCode"]
                        as? [[String: Any]],
                   let code = codes.first?["value"]
                    as? String {
                    sites.insert(code)
                }
                guard shown < 12 else { continue }
                let variable =
                    entry["variable"]
                        as? [String: Any] ?? [:]
                let varName =
                    variable["variableName"]
                        as? String ?? ""
                var reading = ""
                if let values =
                    entry["values"]
                        as? [[String: Any]],
                   let first = values.first,
                   let points = first["value"]
                    as? [[String: Any]],
                   let latest = points.last,
                   let raw = latest["value"]
                    as? String {
                    reading = raw
                    if let unit =
                        variable["unit"]
                            as? [String: Any],
                       let code = unit["unitCode"]
                        as? String {
                        reading += " " + code
                    }
                }
                var text = "  " + siteName
                if !varName.isEmpty {
                    text += " — " + varName
                }
                if !reading.isEmpty {
                    text += ": " + reading
                }
                icsSay(emit, text, .out)
                shown += 1
            }
            icsSay(emit, String(format: L("%lld published gauge series from %lld site(s)"),
                                Int64(series.count),
                                Int64(sites.count)), .out)
            icsSay(emit, L("source: the USGS National Water Information System — the public ledger of the nation's gauges, read as published; provisional values are the survey's own and are revised"), .out)
        }
    }

    /// OpenAQ's station census around a
    /// place. The ledger itself changed
    /// the terms: it now opens only with
    /// an API key — which this bench does
    /// not carry and will not be given —
    /// so the verb reports the ledger's
    /// own answer, plainly.
    static func streetAirProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let place = target,
                  !place.isEmpty else {
                icsSay(emit, L("airprobe: name a place — airprobe Denver, Colorado"), .err)
                return
            }
            guard let geo = streetGeocode(place)
            else {
                icsSay(emit, L("airprobe: the map's geocoder does not know that place"), .err)
                return
            }
            let urlText = String(
                format: "https://api.openaq.org"
                    + "/v3/locations"
                    + "?coordinates=%.5f,%.5f"
                    + "&radius=10000&limit=25",
                geo.lat, geo.lon)
            guard let url = URL(string: urlText),
                  let got = satFetch(url) else {
                icsSay(emit, L("airprobe: the OpenAQ ledger did not answer"), .err)
                return
            }
            icsSay(emit, String(format: L("airprobe — %@"), geo.name), .sys)
            if got.status == 200,
               let doc = satJSON(got.body)
                as? [String: Any],
               let results = doc["results"]
                as? [[String: Any]] {
                icsSay(emit, String(format: L("%lld air-quality station(s) in the public ledger within 10 km"),
                                    Int64(results.count)), .out)
                for station in results.prefix(6) {
                    if let name = station["name"]
                        as? String {
                        icsSay(emit, "  " + name,
                               .out)
                    }
                }
                icsSay(emit, L("source: OpenAQ — the public ledger of the world's air monitors, read as published"), .out)
                return
            }
            if got.status == 401
                || got.status == 403 {
                icsSay(emit, String(format: L("the ledger answered HTTP %lld: OpenAQ now opens only with an API key"),
                                    Int64(got.status)), .out)
                icsSay(emit, L("this bench carries no credentials and asks for none, so the air ledger stays shut to it — that is reported, not worked around"), .out)
                return
            }
            icsSay(emit, String(format: L("the ledger answered HTTP %lld in no shape this verb can census — reported, not guessed"),
                                Int64(got.status)), .err)
        }
    }

    /// One JSON document from a named
    /// feed, through the house session.
    static func streetFetchJSON(
        _ urlText: String) -> Any? {
        guard let url = URL(string: urlText),
              let got = satFetch(url),
              got.status == 200
        else { return nil }
        return satJSON(got.body)
    }

    /// A bike-share system's published
    /// GBFS feeds: the discovery document,
    /// then station information joined
    /// with station status — the standard
    /// census of docks and bikes.
    static func streetGBFSProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let url = streetFeedURL(target)
            else {
                icsSay(emit, L("gbfsprobe: name the system's GBFS address — gbfsprobe https://operator.example/gbfs.json"), .err)
                return
            }
            guard let doc = streetFetchJSON(
                url.absoluteString)
                    as? [String: Any]
            else {
                icsSay(emit, L("gbfsprobe: the feed did not answer"), .err)
                return
            }
            icsSay(emit, String(format: L("gbfsprobe — %@"), url.absoluteString), .sys)
            var feeds: [String: String] = [:]
            if let data = doc["data"]
                as? [String: Any] {
                let lang = (data["en"]
                    as? [String: Any])
                    ?? data.values.compactMap {
                        $0 as? [String: Any]
                    }.first
                if let list = lang?["feeds"]
                    as? [[String: Any]] {
                    for feed in list {
                        if let name = feed["name"]
                            as? String,
                           let feedURL = feed["url"]
                            as? String {
                            feeds[name] = feedURL
                        }
                    }
                }
            }
            func stations(
                _ doc: Any?) -> [[String: Any]] {
                guard let dict = doc
                    as? [String: Any],
                      let data = dict["data"]
                        as? [String: Any],
                      let list = data["stations"]
                        as? [[String: Any]]
                else { return [] }
                return list
            }
            var info: [[String: Any]] = []
            var statusByID: [String: [String: Any]]
                = [:]
            if let infoURL =
                feeds["station_information"] {
                info = stations(streetFetchJSON(
                    infoURL))
            }
            if info.isEmpty {
                info = stations(doc)
            }
            if let statusURL =
                feeds["station_status"] {
                for entry in stations(
                    streetFetchJSON(statusURL)) {
                    if let id = entry["station_id"]
                        as? String {
                        statusByID[id] = entry
                    }
                }
            }
            if !info.isEmpty {
                var bikes = 0
                var docks = 0
                for entry in info {
                    guard let id =
                        entry["station_id"]
                            as? String,
                          let status = statusByID[id]
                    else { continue }
                    bikes += streetInt(
                        status[
                            "num_bikes_available"])
                        ?? 0
                    docks += streetInt(
                        status[
                            "num_docks_available"])
                        ?? 0
                }
                icsSay(emit, String(format: L("%lld station(s) · %lld bike(s) available · %lld dock(s) free — as the feed publishes them"),
                                    Int64(info.count),
                                    Int64(bikes),
                                    Int64(docks)), .out)
                for entry in info.prefix(5) {
                    if let name = entry["name"]
                        as? String {
                        icsSay(emit, "  " + name,
                               .out)
                    }
                }
                icsSay(emit, L("read: the system's published GBFS discovery, station and status documents — the census the standard itself defines"), .out)
                return
            }
            if let data = doc["data"]
                as? [String: Any],
               let bikes = data["bikes"]
                as? [[String: Any]] {
                icsSay(emit, String(format: L("%lld free bike(s) in the published feed"),
                                    Int64(bikes.count)), .out)
                icsSay(emit, L("read: the system's published GBFS free-bike document, as published"), .out)
                return
            }
            icsSay(emit, L("gbfsprobe: the feed answered, but in no GBFS shape this verb can census — reported, not guessed"), .err)
        }
    }

    /// The tower census around a place:
    /// the public map's masts and towers,
    /// with the FCC's registry named for
    /// what it is — the official ledger
    /// this map mirrors, published in a
    /// shape no bench query can open.
    static func streetTowerProbe(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let place = target,
                  !place.isEmpty else {
                icsSay(emit, L("towerprobe: name a place — towerprobe Boulder, Colorado"), .err)
                return
            }
            guard let geo = streetGeocode(place)
            else {
                icsSay(emit, L("towerprobe: the map's geocoder does not know that place"), .err)
                return
            }
            let coords = String(
                format: "%.5f,%.5f", geo.lat, geo.lon)
            let ql = "[out:json][timeout:25];("
                + "node[\"man_made\"~\"^(mast|tower)$\"]"
                + "(around:5000," + coords + ");"
                + "way[\"man_made\"~\"^(mast|tower)$\"]"
                + "(around:5000," + coords + ");"
                + ");out body 80;"
            guard let elements =
                streetOverpass(ql) else {
                icsSay(emit, L("towerprobe: the public map (Overpass) did not answer"), .err)
                return
            }
            icsSay(emit, String(format: L("towerprobe — %@"), geo.name), .sys)
            icsSay(emit, String(format: L("%lld mast(s) and tower(s) on the public map within 5 km"),
                                Int64(elements.count)), .out)
            var operatorTally: [String: Int] = [:]
            for element in elements {
                let tags = streetTagsOf(element)
                if let op = tags["operator"] {
                    operatorTally[op,
                                  default: 0] += 1
                }
            }
            let ops = operatorTally.sorted {
                $0.value != $1.value
                    ? $0.value > $1.value
                    : $0.key < $1.key
            }
            for entry in ops.prefix(4) {
                icsSay(emit, String(format: L("  %@: %lld"),
                                    entry.key,
                                    Int64(entry.value)), .out)
            }
            var samples = 0
            for element in elements {
                guard samples < 5 else { break }
                let tags = streetTagsOf(element)
                guard let height = tags["height"]
                else { continue }
                let label = tags["name"]
                    ?? tags["operator"]
                    ?? L("unnamed structure")
                icsSay(emit, String(format: L("  %@ — height %@, as the map tags it"),
                                    label, height), .out)
                samples += 1
            }
            icsSay(emit, L("the FCC's Antenna Structure Registration is the official ledger behind these masts; it is published as per-state map services and bulk files, with no single open national feed for a bench to query — so this census reads the public map and says so"), .out)
            icsSay(emit, L("map data is crowdsourced and lags the street — absence here proves nothing"), .out)
        }
    }

    // MARK: - the census of one address

    /// One light knock per street door at
    /// an address, then the honest limits.
    static func streetCensusCore(
        _ host: String, _ ip: String)
        -> [ICSLine] {
        var lines: [ICSLine] = [(
            String(format: L("streetcensus — %@"),
                   host), .sys)]
        var sections: [(String, [ICSLine])] = []
        func probe(_ label: String,
                   _ found: [ICSLine]) {
            if !found.isEmpty {
                sections.append((label, found))
            }
        }
        probe(L("traffic nameplate (NTCIP over SNMP)"),
              streetNTCIPCore(ip, light: true))
        probe(L("ONVIF camera nameplate"),
              streetONVIFCore(host, 80,
                              light: true))
        probe(L("vendor camera doors"),
              streetCamDeepCore(host, 80,
                                light: true))
        probe(L("siren controller doors"),
              streetSirenCore(host, ip,
                              light: true))
        probe(L("streetlight gateway door"),
              streetLightCore(host, 80,
                              light: true))
        if sections.isEmpty {
            lines.append((L("no street door answered at this address — the city's iron keeps its nameplates elsewhere, or keeps them shut"), .out))
        }
        for (label, found) in sections {
            lines.append((
                String(format: L("door: %@"),
                       label), .sys))
            lines.append(
                contentsOf: found.prefix(3))
        }
        lines.append((L("limits, stated plainly: one light knock per street door, identification only. The camera clouds — the plate readers' clouds included — were never touched; no plate, image or capture exists here. Signal preemption and the roadside radios are RF, and an iOS app carries no such transmitter"), .out))
        return lines
    }

    static func streetCensus(
        _ target: String?,
        emit: @escaping (String,
                         BlacksiteShell.Line.Kind) -> Void,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var goal = target
            if goal == nil {
                goal = BlacksiteNet
                    .defaultGatewayIP()
            }
            guard let goal = goal,
                  let pair = streetHost(goal)
            else {
                icsSay(emit, L("streetcensus: give the host — streetcensus 192.168.1.50"), .err)
                return
            }
            icsPrint(emit, streetCensusCore(
                pair.host, pair.ip))
        }
    }
}

// MARK: - the Remote ID ear (file scope)
//
// ridprobe's own bounded listener: a
// six-second passive scan for the ASTM
// F3411 service (0xFFFA), decoded by the
// house decoder. The ListeningPost's
// registry belongs to a SwiftUI owner and
// is not reachable from the bench, so the
// wave carries its own ear — receive-only
// by construction: it never connects,
// never pairs, and stops on its own.

private final class StreetRIDScanner:
    NSObject, CBCentralManagerDelegate {

    private var manager: CBCentralManager?
    private let queue = DispatchQueue(
        label: "blacksite.street.rid")
    let gate = DispatchSemaphore(value: 0)
    private var finished = false
    private(set) var finalState:
        CBManagerState = .unknown
    private var byPeripheral:
        [String: Drones.Report] = [:]

    func begin() {
        manager = CBCentralManager(
            delegate: self, queue: queue)
        queue.asyncAfter(
            deadline: .now() + 8.5) {
            [weak self] in
            self?.finish()
        }
    }

    func stop() {
        manager?.stopScan()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let manager = manager {
            finalState = manager.state
        }
        manager?.stopScan()
        gate.signal()
    }

    /// The heard drones, deduplicated by
    /// the serial each one broadcasts
    /// (peripherals that never sent a
    /// Basic ID keep their own entry).
    func collected() -> [Drones.Report] {
        queue.sync {
            var seen = Set<String>()
            var out: [Drones.Report] = []
            for report in byPeripheral.values {
                let key = report.serial
                    ?? Drones.describe(report)
                if seen.insert(key).inserted {
                    out.append(report)
                }
            }
            return out.sorted {
                Drones.describe($0)
                    < Drones.describe($1)
            }
        }
    }

    func centralManagerDidUpdateState(
        _ central: CBCentralManager) {
        finalState = central.state
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(
                withServices: [
                    CBUUID(string: "FFFA")],
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey:
                        true])
            queue.asyncAfter(
                deadline: .now() + 6.0) {
                [weak self] in
                self?.finish()
            }
        case .poweredOff, .unauthorized,
             .unsupported:
            finish()
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber) {
        guard let serviceData =
            advertisementData[
                CBAdvertisementDataServiceDataKey]
                as? [CBUUID: Data],
              let data = serviceData[
                CBUUID(string: "FFFA")]
        else { return }
        let messages = Drones.parseServiceData(
            [UInt8](data))
        guard !messages.isEmpty else { return }
        let key = peripheral.identifier
            .uuidString
        var report = byPeripheral[key]
            ?? Drones.Report()
        for message in messages {
            report.ingest(message)
        }
        byPeripheral[key] = report
    }
}
