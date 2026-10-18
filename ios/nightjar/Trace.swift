//
//  Trace.swift
//  nightjar-hack
//
//  The Network Trace: an operator-started, foreground,
//  stoppable run that maps ONE IPv4 /24 — every address
//  knocked, every answering host profiled, every open door
//  probed with the library probe that speaks its language,
//  and every in-scope endpoint a banner or reply mentions
//  queued and explored in turn (three hops deep at most)
//  until the frontier is exhausted and the run stops itself
//  and says so. References that point outside the /24 are
//  written into the report, never contacted.
//
//  Recon only, the same discipline as the Scan tab: connect,
//  read the banner, send the protocol probe the app already
//  ships. No exploitation, no credential attempts, nothing
//  installed or left running anywhere, nothing that starts
//  itself — the operator presses Start, the operator can
//  press Stop, and the app must stay in the foreground.
//
//  This file also holds the pieces the Centipede borrows:
//  the adaptive rules (TraceRule), the reply analyzer
//  (TraceAnalyzer), and the persistent crawl logbook
//  (TraceBookStore) that both engines file their findings in.
//

import Foundation
import Network
import CryptoKit

// MARK: - Adaptive rules

/// One operator-written rule for the trace and the crawl:
/// when a door's banner+reply matches, do something with it.
///
///   contains TEXT => followup PAYLOAD NAME
///   contains TEXT => tag LABEL
///   contains TEXT => stop
///   port 6379     => tag redis
///
/// "followup" sends the named library payload to the same
/// door before moving on; "tag" files a label on the door's
/// dossier; "stop" marks the reply as a dead end — in the
/// crawl it is not carried forward, in the trace its
/// references are not followed. Matching `contains` is
/// case-insensitive against the banner+reply text.
struct TraceRule {
    /// The sample rules text every surface shows before the
    /// operator writes their own — one text, one default,
    /// so the Send tab, the War Room and War Games can
    /// never drift apart on what an untouched box means.
    /// (Comment-only: it parses to no rules at all.)
    static let sampleText = """
        # Rules — one per line. They steer the trace and
        # the centipede: followup sends the named library
        # payload to the same door, tag files a label,
        # stop leaves the reply where it lies.
        # contains nginx => tag web
        # contains Redis => followup Redis PING (RESP)
        # port 22 => tag ssh
        """

    enum Matcher {
        case contains(String)   // stored lowercased
        case port(Int)
    }
    enum Action {
        case followup(payloadName: String)
        case tag(String)
        case stop
    }
    let matcher: Matcher
    let action: Action
    let sourceLine: String

    func matches(text: String, port: Int) -> Bool {
        switch matcher {
        case .contains(let needle):
            return text.lowercased().contains(needle)
        case .port(let wanted):
            return port == wanted
        }
    }

    /// Parse the rules text, one rule per line. Blank lines
    /// and #-comments are ignored, and so is any line that
    /// doesn't parse — a typo'd rule must never crash a run,
    /// it just never fires.
    static func parse(_ text: String) -> [TraceRule] {
        var rules: [TraceRule] = []
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let arrow = line.range(of: "=>") else { continue }
            let lhs = String(line[..<arrow.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = String(line[arrow.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lhsLower = lhs.lowercased()
            let matcher: Matcher
            if lhsLower.hasPrefix("contains ") {
                let needle = String(lhs.dropFirst("contains ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !needle.isEmpty else { continue }
                matcher = .contains(needle.lowercased())
            } else if lhsLower.hasPrefix("port ") {
                let digits = String(lhs.dropFirst("port ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let n = Int(digits), (1...65535).contains(n)
                else { continue }
                matcher = .port(n)
            } else {
                continue
            }
            let rhsLower = rhs.lowercased()
            let action: Action
            if rhsLower == "stop" {
                action = .stop
            } else if rhsLower.hasPrefix("followup ") {
                let name = String(rhs.dropFirst("followup ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                action = .followup(payloadName: name)
            } else if rhsLower.hasPrefix("tag ") {
                let label = String(rhs.dropFirst("tag ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                action = .tag(label)
            } else {
                continue
            }
            rules.append(TraceRule(matcher: matcher, action: action,
                                   sourceLine: line))
        }
        return rules
    }
}

// MARK: - Reply analysis

/// An endpoint a banner or reply pointed at: a host, maybe a
/// port, and the exact text it was read from (the evidence).
struct TraceReference: Equatable {
    let host: String
    let port: Int?
    let source: String
}

/// What the analyzer made of one door's answer.
struct TraceAnalysis {
    var firstLine: String
    var preview: String
    var signature: String
    var serviceHint: String?
    var notes: [String]
    var references: [TraceReference]
}

enum TraceAnalyzer {

    /// The lossy text of a reply — banners are not always
    /// valid UTF-8, and the analyzer works on what a human
    /// reading the hexdump would see.
    static func text(of data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    static func analyze(data: Data, host: String, port: Int)
        -> TraceAnalysis
    {
        let text = text(of: data)
        let signature = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()

        let firstRaw = text.components(separatedBy: "\n").first ?? ""
        var firstLine = firstRaw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if firstLine.isEmpty {
            firstLine = "(no banner) " + data.prefix(16)
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
        }

        let preview: String
        if let printable = PayloadKit.printableText(data) {
            preview = String(printable.prefix(400))
        } else {
            preview = data.prefix(48)
                .map { String(format: "%02x", $0) }
                .joined(separator: " ")
                + " — \(data.count) bytes"
        }

        var hint: String? = nil
        var notes: [String] = []
        let bytes = [UInt8](data)

        if text.hasPrefix("HTTP/") {
            hint = "HTTP"
            notes += httpNotes(text)
        } else if text.hasPrefix("SSH-") {
            hint = "SSH"
        } else if text.hasPrefix("SIP/2.0") {
            hint = "SIP"
        } else if text.hasPrefix("RTSP/") {
            hint = "RTSP"
        } else if text.hasPrefix("+PONG") {
            hint = "Redis"
        } else if text.hasPrefix("-NOAUTH") {
            hint = "Redis"
            notes.append("authentication required")
        } else if text.hasPrefix("+OK") {
            hint = "POP3"
            notes.append("+OK greeting (POP3, or Redis answering PING)")
        } else if text.hasPrefix("220 ") || text.hasPrefix("220-") {
            if firstLine.localizedCaseInsensitiveContains("smtp")
                || firstLine.localizedCaseInsensitiveContains("esmtp") {
                hint = "SMTP"
            } else if firstLine
                .localizedCaseInsensitiveContains("ftp") {
                hint = "FTP"
            } else {
                hint = "SMTP/FTP"
            }
        } else if text.hasPrefix("VERSION ") || text.hasPrefix("STAT ") {
            hint = "memcached"
        } else if bytes.count >= 2, bytes[0] == 0x20, bytes[1] == 0x02 {
            hint = "MQTT"   // a CONNACK, answering the CONNECT probe
        } else if bytes.count == 1, bytes[0] == 0x53 {
            hint = "PostgreSQL"
            notes.append("answered the SSLRequest with 'S' — SSL offered")
        } else if bytes.count == 1, bytes[0] == 0x4E {
            hint = "PostgreSQL"
            notes.append("answered the SSLRequest with 'N' — no SSL")
        } else if bytes.count >= 3, bytes[0] == 0xFF,
                  bytes[1] == 0xFB || bytes[1] == 0xFD
                    || bytes[1] == 0xFE {
            hint = "Telnet"   // IAC negotiation bytes
        }

        return TraceAnalysis(firstLine: firstLine, preview: preview,
                             signature: signature, serviceHint: hint,
                             notes: notes,
                             references: references(in: text))
    }

    /// The interesting headers of an HTTP answer, plus the
    /// page title when there is one — the facts another
    /// component would want without re-reading the reply.
    private static func httpNotes(_ text: String) -> [String] {
        var notes: [String] = []
        let lines = text.components(separatedBy: "\n")
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if line.isEmpty { break }   // end of the header block
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
                .trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if key == "server" {
                notes.append("Server: \(value)")
            } else if key == "location" {
                notes.append("Location: \(value)")
            } else if key == "www-authenticate" {
                notes.append("WWW-Authenticate: \(value)")
            }
        }
        if let regex = try? NSRegularExpression(
            pattern: "<title[^>]*>(.*?)</title>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            let title = String(text[range])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                notes.append("Title: \(String(title.prefix(120)))")
            }
        }
        return notes
    }

    /// Every endpoint a text points at: bare IPv4 addresses
    /// with optional ports, and http(s) URLs (whose host may
    /// be a name — the caller decides what can be probed;
    /// names and foreign addresses are recorded, not chased).
    static func references(in text: String) -> [TraceReference] {
        var found: [TraceReference] = []
        var seen = Set<String>()
        func add(host: String, port: Int?, source: String) {
            let key = "\(host)|\(port.map(String.init) ?? "")"
            guard seen.insert(key).inserted else { return }
            found.append(TraceReference(host: host, port: port,
                                        source: source))
        }
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let urlRegex = try? NSRegularExpression(
            pattern: #"https?://[^\s"'<>\]]+"#) {
            for match in urlRegex.matches(in: text, range: whole) {
                let raw = ns.substring(with: match.range)
                if let components = URLComponents(string: raw),
                   let host = components.host, !host.isEmpty {
                    add(host: host, port: components.port, source: raw)
                }
            }
        }
        if let ipRegex = try? NSRegularExpression(
            pattern: #"\b(?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?\b"#) {
            for match in ipRegex.matches(in: text, range: whole) {
                let raw = ns.substring(with: match.range)
                let parts = raw.split(separator: ":")
                let ip = String(parts[0])
                let octets = ip.split(separator: ".")
                    .compactMap { Int($0) }
                guard octets.count == 4,
                      octets.allSatisfy({ (0...255).contains($0) })
                else { continue }
                var port: Int? = nil
                if parts.count == 2, let p = Int(parts[1]),
                   (1...65535).contains(p) {
                    port = p
                }
                add(host: ip, port: port, source: raw)
            }
        }
        return found
    }
}

// MARK: - BLE sightings (the Listen registry, borrowed)

/// One Bluetooth device as the trace files it: a passive
/// sighting from the Listen tab's registry — heard by this
/// phone, never probed, never connected to. The trace
/// borrows the ear's picture of the room so one map holds
/// the wires and the air.
struct TraceBLEDevice: Codable, Equatable {
    var id: String
    var name: String?
    var kind: String
    var vendor: String?
    var serviceUUIDs: [String]
    var rotatingAddress: Bool
    var firstHeard: Date
    var lastHeard: Date
    var sightings: Int
    var closestRSSI: Int?
    var smoothedRSSI: Double?

    /// Two tellings of the same device, combined: the
    /// earliest first-hearing and the latest last-hearing
    /// stand, counts and closest approach take the max,
    /// services union, and name/vendor/kind/smoothed
    /// strength come from whichever telling heard it last.
    static func merged(_ old: TraceBLEDevice,
                       _ new: TraceBLEDevice) -> TraceBLEDevice {
        var result = old
        result.firstHeard = min(old.firstHeard, new.firstHeard)
        result.lastHeard = max(old.lastHeard, new.lastHeard)
        result.sightings = max(old.sightings, new.sightings)
        if let a = old.closestRSSI, let b = new.closestRSSI {
            result.closestRSSI = max(a, b)
        } else {
            result.closestRSSI = new.closestRSSI ?? old.closestRSSI
        }
        result.rotatingAddress = old.rotatingAddress
            || new.rotatingAddress
        for uuid in new.serviceUUIDs
        where !result.serviceUUIDs.contains(uuid) {
            if result.serviceUUIDs.count < 16 {
                result.serviceUUIDs.append(uuid)
            }
        }
        if new.lastHeard >= old.lastHeard {
            if let name = new.name { result.name = name }
            if let vendor = new.vendor { result.vendor = vendor }
            if let smooth = new.smoothedRSSI {
                result.smoothedRSSI = smooth
            }
            result.kind = new.kind
        }
        return result
    }
}

/// The hand-off point between the ear and the trace: the
/// listening post notes its current registry here every
/// time it publishes rows, and a trace reads the latest
/// picture when its run finishes. A lock and value types —
/// the two sides never share mutable state.
enum BLESightings {
    private static var latest: [TraceBLEDevice] = []
    private static let lock = NSLock()

    static func note(_ devices: [TraceBLEDevice]) {
        lock.lock()
        latest = devices
        lock.unlock()
    }

    static func snapshot() -> [TraceBLEDevice] {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

// MARK: - The logbook

/// One door's dossier in the logbook: what it is, what it
/// said, the fingerprint of what it said, and how often it
/// has been seen saying it.
struct TraceServiceDossier: Codable, Equatable {
    var port: Int
    var proto: String
    var serviceName: String
    var bannerFirstLine: String
    var replyPreview: String
    var signature: String
    var notes: [String]
    var probesUsed: [String]
    var tags: [String]
    var firstSeen: Date
    var lastSeen: Date
    var timesSeen: Int
}

/// One host's dossier: identity, provenance (how it was
/// found), labels, and every door filed under it.
struct TraceHostDossier: Codable, Equatable {
    var ip: String
    var names: [String]
    var sources: [String]
    var tags: [String]
    var firstSeen: Date
    var lastSeen: Date
    var timesSeen: Int
    var services: [TraceServiceDossier]
}

/// The persistent crawl logbook: every host and door the
/// trace or the centipede has ever filed, merged by IP and
/// by host:port/proto, kept at
/// Documents/network-trace-logbook.json. One serial queue
/// owns the in-memory copy and the file; every record is
/// merged and saved before the call returns, so the book
/// survives the app being closed mid-walk.
final class TraceBookStore {
    static let shared = TraceBookStore()

    static var logbookURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("network-trace-logbook.json")
    }
    var logbookURL: URL { TraceBookStore.logbookURL }

    private let queue = DispatchQueue(
        label: "net.nosuchmachine.nightjarhack.tracebook")
    private var hosts: [String: TraceHostDossier] = [:]
    private var bleDevices: [String: TraceBLEDevice] = [:]
    private var loaded = false

    private struct BookFile: Codable {
        var hosts: [TraceHostDossier]
        var bleDevices: [TraceBLEDevice] = []

        enum CodingKeys: String, CodingKey {
            case hosts, bleDevices
        }

        init(hosts: [TraceHostDossier],
             bleDevices: [TraceBLEDevice] = []) {
            self.hosts = hosts
            self.bleDevices = bleDevices
        }

        /// Books written before BLE joined the logbook have
        /// no bleDevices key; they must still open.
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            hosts = try box.decode([TraceHostDossier].self,
                                   forKey: .hosts)
            bleDevices = try box.decodeIfPresent(
                [TraceBLEDevice].self, forKey: .bleDevices) ?? []
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Numeric IPv4 ordering — 192.168.2.9 before 192.168.2.10,
    /// which string order gets wrong.
    static func ipLess(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<min(pa.count, pb.count) where pa[i] != pb[i] {
            return pa[i] < pb[i]
        }
        return pa.count < pb.count
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: TraceBookStore.logbookURL),
              let decoded = try? TraceBookStore.decoder
                .decode(BookFile.self, from: data) else { return }
        for host in decoded.hosts { hosts[host.ip] = host }
        for device in decoded.bleDevices {
            bleDevices[device.id] = device
        }
    }

    private func save() {
        let book = BookFile(
            hosts: hosts.values.sorted {
                TraceBookStore.ipLess($0.ip, $1.ip)
            },
            bleDevices: bleDevices.values.sorted {
                $0.id < $1.id
            })
        guard let data = try? TraceBookStore.encoder.encode(book)
        else { return }
        try? data.write(to: TraceBookStore.logbookURL,
                       options: .atomic)
    }

    /// The simple door, used by the centipede's harvest: a
    /// reply arrived from a target — analyze it and file it.
    /// Non-network targets (phones, BLE) file nothing.
    func record(targetText: String, reply: Data, source: String,
                extraTags: [String] = []) {
        guard let parsed = try? SendTarget.parse(targetText)
        else { return }
        switch parsed {
        case .tcp(let host, let port, _):
            record(host: host, port: port, proto: "tcp",
                   analysis: reply.isEmpty ? nil
                     : TraceAnalyzer.analyze(data: reply, host: host,
                                             port: port),
                   probes: [], extraTags: extraTags, source: source,
                   bonjourName: nil)
        case .udp(let host, let port):
            record(host: host, port: port, proto: "udp",
                   analysis: reply.isEmpty ? nil
                     : TraceAnalyzer.analyze(data: reply, host: host,
                                             port: port),
                   probes: [], extraTags: extraTags, source: source,
                   bonjourName: nil)
        case .http(let url, let https):
            guard let host = url.host else { return }
            record(host: host, port: url.port ?? (https ? 443 : 80),
                   proto: "tcp",
                   analysis: reply.isEmpty ? nil
                     : TraceAnalyzer.analyze(data: reply, host: host,
                                             port: url.port
                                               ?? (https ? 443 : 80)),
                   probes: [], extraTags: extraTags, source: source,
                   bonjourName: nil)
        default:
            return
        }
    }

    /// The full record: merge one observation into the book.
    /// `port` nil files the host alone (discovery, Bonjour);
    /// with a port, the door's dossier is created or refreshed
    /// — freshest non-empty facts win, lists are unioned.
    func record(host: String, port: Int?, proto: String = "tcp",
                analysis: TraceAnalysis?, probes: [String] = [],
                extraTags: [String] = [], source: String,
                bonjourName: String? = nil) {
        queue.sync {
            loadIfNeeded()
            let now = Date()
            var dossier = hosts[host] ?? TraceHostDossier(
                ip: host, names: [], sources: [], tags: [],
                firstSeen: now, lastSeen: now, timesSeen: 0,
                services: [])
            dossier.lastSeen = now
            dossier.timesSeen += 1
            if !dossier.sources.contains(source) {
                dossier.sources.append(source)
            }
            for tag in extraTags where !dossier.tags.contains(tag) {
                dossier.tags.append(tag)
            }
            if let name = bonjourName, !name.isEmpty,
               !dossier.names.contains(name) {
                dossier.names.append(name)
            }
            if let port = port {
                if let index = dossier.services.firstIndex(where: {
                    $0.port == port && $0.proto == proto
                }) {
                    var service = dossier.services[index]
                    service.lastSeen = now
                    service.timesSeen += 1
                    if let analysis = analysis {
                        if !analysis.firstLine.isEmpty {
                            service.bannerFirstLine = analysis.firstLine
                        }
                        if !analysis.preview.isEmpty {
                            service.replyPreview = analysis.preview
                        }
                        if !analysis.signature.isEmpty {
                            service.signature = analysis.signature
                        }
                        if let hint = analysis.serviceHint {
                            service.serviceName = hint
                        }
                        for note in analysis.notes
                        where !service.notes.contains(note) {
                            service.notes.append(note)
                        }
                    }
                    for probe in probes
                    where !service.probesUsed.contains(probe) {
                        service.probesUsed.append(probe)
                    }
                    for tag in extraTags
                    where !service.tags.contains(tag) {
                        service.tags.append(tag)
                    }
                    dossier.services[index] = service
                } else {
                    dossier.services.append(TraceServiceDossier(
                        port: port, proto: proto,
                        serviceName: analysis?.serviceHint
                            ?? ScanModel.serviceNames[port] ?? "",
                        bannerFirstLine: analysis?.firstLine ?? "",
                        replyPreview: analysis?.preview ?? "",
                        signature: analysis?.signature ?? "",
                        notes: analysis?.notes ?? [],
                        probesUsed: probes, tags: extraTags,
                        firstSeen: now, lastSeen: now, timesSeen: 1))
                }
                dossier.services.sort { $0.port < $1.port }
            }
            hosts[host] = dossier
            save()
        }
    }

    /// Every dossier in the book, in numeric IP order.
    func allDossiers() -> [TraceHostDossier] {
        queue.sync {
            loadIfNeeded()
            return hosts.values.sorted {
                TraceBookStore.ipLess($0.ip, $1.ip)
            }
        }
    }

    /// The dossiers inside one /24 (the trace's scope).
    func scopeDossiers(base: String) -> [TraceHostDossier] {
        allDossiers().filter { $0.ip.hasPrefix(base + ".") }
    }

    /// File a batch of BLE sightings — the trace finish
    /// hands over the Listen registry's latest picture —
    /// merged by device id, the same discipline as hosts.
    func mergeBLE(_ devices: [TraceBLEDevice]) {
        guard !devices.isEmpty else { return }
        queue.sync {
            loadIfNeeded()
            for device in devices {
                if let old = bleDevices[device.id] {
                    bleDevices[device.id] =
                        TraceBLEDevice.merged(old, device)
                } else {
                    bleDevices[device.id] = device
                }
            }
            save()
        }
    }

    /// Forget everything: the in-memory book and the file.
    func clear() {
        queue.sync {
            hosts = [:]
            bleDevices = [:]
            loaded = true
            try? FileManager.default
                .removeItem(at: TraceBookStore.logbookURL)
        }
    }
}

// MARK: - Trace export

struct TraceRunInfo: Codable {
    var id: String
    var scope: String
    var base: String
    var startedAt: Date
    var finishedAt: Date
    var stopReason: String
    var settings: Settings
    struct Settings: Codable {
        var discoveryPorts: [Int]
        var profilePorts: [Int]
        var includeBonjour: Bool
        var adaptive: Bool
        var ruleCount: Int
    }
}

/// One vertex of the run's map: this phone, a host, or a
/// door on a host.
struct TraceNode: Codable {
    var id: String
    var kind: String
    var label: String
    var ip: String?
    var port: Int?
}

/// One traced relationship, with the evidence for it.
struct TraceEdge: Codable {
    var from: String
    var to: String
    var kind: String
    var evidence: String
}

struct TraceBonjourEntry: Codable {
    var name: String
    var type: String
    var label: String
    var host: String?
    var port: Int?
}

/// A reference that points outside the traced /24: written
/// down, never contacted.
struct TraceExternalReference: Codable {
    var host: String
    var port: Int?
    var foundIn: String
    var sourceText: String
}

struct TraceDiff: Codable {
    var newHosts: [String] = []
    var missingHosts: [String] = []
    var newServices: [String] = []
    var changedServices: [String] = []
    var missingServices: [String] = []
}

/// One trace run, whole: the document another component
/// consumes. Written with sorted keys and ISO-8601 dates so
/// diffs between runs read cleanly too.
struct TraceExport: Codable {
    var schema: String
    var schemaVersion: Int
    var kind: String
    var generatedAt: Date
    var run: TraceRunInfo
    var summary: [String: Int]
    var hosts: [TraceHostDossier]
    var nodes: [TraceNode]
    var edges: [TraceEdge]
    var bonjour: [TraceBonjourEntry]
    var bleDevices: [TraceBLEDevice]
    var externalReferences: [TraceExternalReference]
    var diff: TraceDiff
    var limitations: [String]

    /// What a trace cannot see, said in the file itself so
    /// nobody downstream mistakes the map for the territory.
    static let limitations = [
        "TCP connect only: no ICMP ping, no ARP scan, no UDP "
            + "discovery — a host that answers nothing on the "
            + "knocked TCP ports is invisible to a trace.",
        "Hosts behind a firewall that drops (rather than "
            + "refuses) probes can be missed.",
        "BLE devices on the map are passive sightings from "
            + "the Listen registry — heard by this phone, "
            + "never probed or connected to. If Listen was "
            + "not running, the air is simply absent.",
        "References are followed at most 3 hops from a "
            + "discovered host, and only inside the traced /24.",
    ]
}

enum TraceDiffer {
    /// This run against the logbook as it stood BEFORE the
    /// run merged into it: what's new on the scope, what the
    /// book knew that this run did not see, and which doors
    /// answered differently (a changed reply signature).
    static func diff(before: [TraceHostDossier],
                     after: [TraceHostDossier],
                     seenHosts: Set<String>,
                     seenServices: Set<String>) -> TraceDiff {
        let beforeHosts = Set(before.map { $0.ip })
        let beforeServices = Set(before.flatMap { host in
            host.services.map { "\(host.ip):\($0.port)" }
        })
        var beforeSignatures: [String: String] = [:]
        for host in before {
            for service in host.services {
                beforeSignatures["\(host.ip):\(service.port)"]
                    = service.signature
            }
        }
        var afterSignatures: [String: String] = [:]
        for host in after {
            for service in host.services {
                afterSignatures["\(host.ip):\(service.port)"]
                    = service.signature
            }
        }
        var result = TraceDiff()
        result.newHosts = seenHosts.subtracting(beforeHosts)
            .sorted(by: TraceBookStore.ipLess)
        result.missingHosts = beforeHosts.subtracting(seenHosts)
            .sorted(by: TraceBookStore.ipLess)
        result.newServices = seenServices
            .subtracting(beforeServices).sorted()
        result.missingServices = beforeServices
            .subtracting(seenServices).sorted()
        result.changedServices = seenServices
            .intersection(beforeServices).filter { key in
                guard let now = afterSignatures[key], !now.isEmpty,
                      let then = beforeSignatures[key]
                else { return false }
                return now != then
            }.sorted()
        return result
    }
}

enum TraceExportWriter {
    /// Write one run's export to Documents/Traces/ and hand
    /// back where it landed (nil when the write failed).
    static func write(_ export: TraceExport) -> URL? {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Traces", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent(
            "nightjar-trace-"
            + formatter.string(from: export.generatedAt) + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else {
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - The trace engine

extension Mouth {

    /// Append a line to the trace's trail (and mirror it into
    /// the status line), from any queue. The trail is capped
    /// at ~300 lines: a /24 trace narrates a lot, and the
    /// export file — not the screen — is the full record.
    func traceNote(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.traceLines.append(text)
            if self.traceLines.count > 300 {
                self.traceLines.removeFirst(
                    self.traceLines.count - 300)
            }
            self.traceStatus = text
        }
    }

    /// One connect knock with a 1 s deadline — the discovery
    /// stage's only question is whether anything answered.
    private func traceKnock(host: String, port: Int,
                            completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else { completion(false); return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let lock = NSLock()
        var finished = false
        func finish(_ open: Bool) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            completion(open)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled: finish(false)
            default: break
            }
        }
        connection.start(queue: self.probeQueue)
        self.probeQueue.asyncAfter(deadline: .now() + 1.0) {
            finish(false)
        }
    }

    /// A banner probe with the Scan tab's latch-on-ready
    /// semantics: a 2.5 s connect deadline that applies only
    /// until the connection is up — once ready, the port IS
    /// open and nothing afterwards un-opens it. HTTP-shaped
    /// ports are asked HEAD first; everyone gets a 1.2 s
    /// banner window and at most 4096 bytes. The completion
    /// receives nil for closed/filtered, empty Data for
    /// open-but-silent, or the banner bytes.
    private func traceProbe(host: String, port: Int,
                            completion: @escaping (Data?) -> Void) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else { completion(nil); return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let lock = NSLock()
        var finished = false
        var wasReady = false
        var collected = Data()
        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return collected
        }
        func ready() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return wasReady
        }
        func finish(_ result: Data?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            completion(result)
        }
        self.probeQueue.asyncAfter(deadline: .now() + 2.5) {
            if !ready() { finish(nil) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                lock.lock()
                wasReady = true
                lock.unlock()
                func grab() {
                    func receiveMore() {
                        connection.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: 4096) {
                            data, _, isComplete, error in
                            if let data = data, !data.isEmpty {
                                lock.lock()
                                collected += data
                                let count = collected.count
                                lock.unlock()
                                if count >= 4096 {
                                    finish(snapshot())
                                    return
                                }
                            }
                            if isComplete || error != nil {
                                finish(snapshot())
                            } else {
                                receiveMore()
                            }
                        }
                    }
                    receiveMore()
                    self.probeQueue.asyncAfter(deadline: .now() + 1.2) {
                        finish(snapshot())
                    }
                }
                if [80, 8000, 8080, 8888, 9200].contains(port) {
                    connection.send(
                        content: Data("HEAD / HTTP/1.0\r\n\r\n".utf8),
                        completion: .contentProcessed { _ in grab() })
                } else {
                    grab()
                }
            case .failed, .cancelled:
                if ready() { finish(snapshot()) } else { finish(nil) }
            default:
                break
            }
        }
        connection.start(queue: self.probeQueue)
    }

    /// Resolve a Bonjour endpoint to its host and port by
    /// opening one connection and reading where it landed —
    /// the same trick the Scan tab uses.
    private func traceResolve(
        endpoint: NWEndpoint,
        completion: @escaping ((String, Int)?) -> Void
    ) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let lock = NSLock()
        var finished = false
        func finish(_ value: (String, Int)?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            completion(value)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   case .hostPort(let host, let port)
                     = path.remoteEndpoint {
                    finish(("\(host)", Int(port.rawValue)))
                } else {
                    finish(nil)
                }
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: self.probeQueue)
        self.probeQueue.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }

    /// One active-probe send, the centipede's talkSend shape:
    /// the reply is read back through the reply mirror by the
    /// caller, exactly as the crawl reads its hops.
    private func traceSend(text: String, payload: Data,
                           completion: @escaping (Bool) -> Void) {
        guard let parsed = try? SendTarget.parse(text) else {
            completion(false)
            return
        }
        switch parsed {
        case .http:
            sendHTTP(target: parsed, payload: payload,
                     framing: "raw", method: "POST", timeout: 5,
                     completion: completion)
        case .tcp, .udp:
            sendNetwork(target: parsed, payload: payload,
                        framing: "raw", read: true, timeout: 3,
                        completion: completion)
        default:
            completion(false)
        }
    }
}

extension Mouth {

    /// Run a Network Trace over one /24: Bonjour listening
    /// and the discovery knock together, then a worklist —
    /// profile every found host, probe every open door with
    /// its library probe, apply the adaptive rules, and chase
    /// every in-scope reference (three hops deep at most)
    /// until nothing new is left. Then the run files its
    /// export, diffs itself against the logbook, and stops.
    func startNetworkTrace(
        scopeText: String, discoveryPorts: [Int],
        profilePorts: [Int], includeBonjour: Bool,
        adaptive: Bool, rules: [TraceRule],
        probeFor: @escaping (String) -> (data: Data, name: String)?,
        payloadNamed: @escaping (String) -> Data?
    ) {
        // The trace answers to the Standard as a sweep —
        // whoever asks for it (a hand, a macro, a game),
        // the funnel refuses it under BRAVO and ALPHA.
        if EmconStandard.refused(.sweep) {
            traceStatus = "The trace stays holstered — "
                + EmconCondition.current.declared
            ui("The trace stays holstered — "
               + EmconCondition.current.declared, error: true)
            return
        }
        guard !traceBusy, !crawlBusy, !talkBusy else { return }
        let ownIP = Mouth.localIPAddress()
        guard let base = Mouth.sweepBase(scopeText, ownIP: ownIP)
        else {
            traceStatus = "Couldn't read that scope"
            traceLines = ["✗ Couldn't read that scope — blank "
                + "means this phone's /24; otherwise an address "
                + "in the /24 (192.168.2.15) or its base "
                + "(192.168.2)."]
            ui("Couldn't read that scope", error: true)
            return
        }
        let discovery = Array(Set(discoveryPorts.filter {
            (1...65535).contains($0)
        })).sorted()
        guard !discovery.isEmpty else {
            traceStatus = "No discovery ports"
            traceLines = ["✗ Give at least one discovery port — "
                + "discovery is how the trace finds its hosts."]
            ui("No discovery ports", error: true)
            return
        }
        let profile = profilePorts.isEmpty
            ? ScanModel.topPorts.map { $0.0 }
            : Array(Set(profilePorts.filter {
                (1...65535).contains($0)
            })).sorted()

        traceGeneration += 1
        let gen = traceGeneration
        let startedAt = Date()
        let stampFormatter = DateFormatter()
        stampFormatter.locale = Locale(identifier: "en_US_POSIX")
        stampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let runID = "trace-" + stampFormatter.string(from: startedAt)
        // The book as it stands BEFORE this run files anything:
        // the diff at the end is measured against this.
        let before = TraceBookStore.shared.scopeDossiers(base: base)

        traceBusy = true
        ProcessBoard.shared.beginKeyed(
            "mouth.trace", label: "Network trace",
            organ: "Trace", detail: "on \(base).0/24",
            stop: { [weak self] in
                self?.stopNetworkTrace() })
        traceLatestExport = nil
        traceLines = [
            "Network trace — \(base).0/24",
            "Foreground, stop anytime. Endpoints outside the "
                + "/24 are recorded, never contacted.",
        ]
        traceStatus = "Tracing \(base).0/24…"
        line("network-trace: \(base).0/24")

        // All run state below lives on this serial queue;
        // every stage's callbacks hop back onto it before
        // touching anything.
        let work = DispatchQueue(label: "nightjar-trace-work")
        let probeGate = DispatchSemaphore(value: 1)
        let probeDispatch = DispatchQueue(
            label: "nightjar-trace-probes", attributes: .concurrent)
        let phoneNodeID = "device:this-phone"

        enum TraceWork {
            case host(String, Int, String)
            case door(String, Int, Int)
        }

        var nodes: [TraceNode] = []
        var nodeIDs = Set<String>()
        var edges: [TraceEdge] = []
        var edgeKeys = Set<String>()
        var bonjourEntries: [TraceBonjourEntry] = []
        var bonjourSeen: [String: (name: String, type: String,
                                   label: String,
                                   endpoint: NWEndpoint)] = [:]
        var bonjourBrowsers: [NWBrowser] = []
        var externalRefs: [TraceExternalReference] = []
        var externalKeys = Set<String>()
        var worklist: [TraceWork] = []
        var queuedHosts = Set<String>()
        var seenHosts = Set<String>()
        var queuedDoors = Set<String>()
        var doneDoors = Set<String>()
        var seenDoorKeys = Set<String>()
        var discoveredHosts = Set<String>()
        var answeredPorts: [String: [Int]] = [:]
        var doorCount = 0
        var probeCount = 0
        var followupCount = 0
        var profiledCount = 0
        var discoveryDone = false
        var bonjourDone = !includeBonjour
        var worklistStarted = false
        var finishedFlag = false

        func inScope(_ host: String) -> Bool {
            guard host.hasPrefix(base + ".") else { return false }
            let last = host.dropFirst(base.count + 1)
            guard !last.contains("."), let n = Int(last),
                  (0...255).contains(n) else { return false }
            return true
        }

        func addNode(_ node: TraceNode) {
            if nodeIDs.insert(node.id).inserted {
                nodes.append(node)
            }
        }
        func addHostNode(_ host: String) {
            addNode(TraceNode(id: "host:\(host)", kind: "host",
                              label: host, ip: host, port: nil))
        }
        func addEdge(from: String, to: String, kind: String,
                     evidence: String) {
            let key = "\(from)|\(to)|\(kind)"
            if edgeKeys.insert(key).inserted {
                edges.append(TraceEdge(from: from, to: to,
                                       kind: kind,
                                       evidence: evidence))
            }
        }
        addNode(TraceNode(id: phoneNodeID, kind: "device",
                          label: "This phone", ip: ownIP, port: nil))

        func queueHost(_ host: String, depth: Int, source: String) {
            guard host != ownIP, inScope(host), depth <= 3,
                  !queuedHosts.contains(host),
                  !seenHosts.contains(host) else { return }
            queuedHosts.insert(host)
            worklist.append(.host(host, depth, source))
        }
        func queueDoor(_ host: String, _ port: Int, depth: Int) {
            let key = "\(host):\(port)"
            guard host != ownIP, inScope(host), depth <= 3,
                  !doneDoors.contains(key),
                  !queuedDoors.contains(key),
                  doneDoors.count + queuedDoors.count < 2048
            else { return }
            queuedDoors.insert(key)
            worklist.append(.door(host, port, depth))
        }

        /// References a reply coughed up: in-scope ones join
        /// the frontier (their host for a full profile, the
        /// named door for a direct probe); out-of-scope ones
        /// are written down and never touched.
        func enqueueReferences(_ refs: [TraceReference],
                               fromHost: String, fromPort: Int,
                               depth: Int) {
            for ref in refs {
                if inScope(ref.host) {
                    addEdge(from: "svc:\(fromHost):\(fromPort)",
                            to: "host:\(ref.host)",
                            kind: "references",
                            evidence: ref.source)
                    if let port = ref.port {
                        queueDoor(ref.host, port, depth: depth + 1)
                    }
                    queueHost(ref.host, depth: depth + 1,
                              source: "trace-reference")
                } else {
                    let key = "\(ref.host)|\(ref.port ?? 0)"
                        + "|\(fromHost):\(fromPort)"
                    if externalKeys.insert(key).inserted {
                        externalRefs.append(TraceExternalReference(
                            host: ref.host, port: ref.port,
                            foundIn: "\(fromHost):\(fromPort)",
                            sourceText: ref.source))
                    }
                }
            }
        }

        /// Active probes go one at a time through the gate:
        /// the mouth's reply mirror is a single shared
        /// channel, and two probes in flight would read each
        /// other's answers — the same discipline the
        /// centipede walks with. The completion lands back
        /// on the work queue.
        func serializedSend(text: String, payload: Data,
                            completion: @escaping (Data?) -> Void) {
            probeDispatch.async { [weak self] in
                guard let self = self else {
                    work.async { completion(nil) }
                    return
                }
                probeGate.wait()
                let started = Date()
                self.traceSend(text: text, payload: payload) { _ in
                    let reply = self.replyData(since: started)
                    probeGate.signal()
                    work.async { completion(reply) }
                }
            }
        }

        /// The follow-up rules a door earned, sent in rule
        /// order: each answer is analyzed, filed, and its own
        /// references followed (unless a stop rule marks it
        /// a dead end) — but follow-ups never chain into
        /// further follow-ups.
        func runFollowups(names: [String], host: String,
                          port: Int, depth: Int,
                          done: @escaping () -> Void) {
            guard let name = names.first else { done(); return }
            let rest = Array(names.dropFirst())
            guard let payload = payloadNamed(name) else {
                runFollowups(names: rest, host: host, port: port,
                              depth: depth, done: done)
                return
            }
            followupCount += 1
            serializedSend(text: "tcp://\(host):\(port)",
                           payload: payload) { reply in
                if let reply = reply, !reply.isEmpty {
                    let analysis = TraceAnalyzer.analyze(
                        data: reply, host: host, port: port)
                    var tags: [String] = []
                    var stop = false
                    if adaptive {
                        let replyText = TraceAnalyzer.text(of: reply)
                        for rule in rules
                        where rule.matches(text: replyText,
                                           port: port) {
                            switch rule.action {
                            case .tag(let label): tags.append(label)
                            case .stop: stop = true
                            case .followup: break
                            }
                        }
                    }
                    TraceBookStore.shared.record(
                        host: host, port: port, proto: "tcp",
                        analysis: analysis, probes: [name],
                        extraTags: tags, source: "trace-followup",
                        bonjourName: nil)
                    self.traceNote("  ↳ follow-up \(name) → "
                        + "\(host):\(port) · \(reply.count) B back")
                    if !stop {
                        enqueueReferences(analysis.references,
                                          fromHost: host,
                                          fromPort: port,
                                          depth: depth)
                    }
                } else {
                    self.traceNote("  ↳ follow-up \(name) → "
                        + "\(host):\(port) · silence")
                }
                runFollowups(names: rest, host: host, port: port,
                              depth: depth, done: done)
            }
        }

        /// One open door, fully processed: graph first, then
        /// the library probe (when the port has one), the
        /// rules over banner+reply, the logbook, the
        /// references, and finally the follow-ups.
        func processDoor(host: String, port: Int, banner: Data,
                         depth: Int, done: @escaping () -> Void) {
            let doorKey = "\(host):\(port)"
            queuedDoors.remove(doorKey)
            doneDoors.insert(doorKey)
            seenDoorKeys.insert(doorKey)
            seenHosts.insert(host)
            doorCount += 1
            addHostNode(host)
            addNode(TraceNode(id: "svc:\(host):\(port)",
                              kind: "service",
                              label: "\(host):\(port)",
                              ip: host, port: port))
            addEdge(from: "host:\(host)", to: "svc:\(host):\(port)",
                    kind: "open",
                    evidence: banner.isEmpty
                        ? "connect — no banner"
                        : TraceAnalyzer.analyze(data: banner,
                                                host: host,
                                                port: port).firstLine)
            let targetText = "tcp://\(host):\(port)"

            func analyzeAndFinish(reply: Data?, probeName: String?) {
                let replyData = reply ?? Data()
                let primary = !replyData.isEmpty ? replyData : banner
                let analysis = primary.isEmpty ? nil
                    : TraceAnalyzer.analyze(data: primary,
                                            host: host, port: port)
                let combinedText = TraceAnalyzer.text(
                    of: banner + replyData)
                var tags: [String] = []
                var stop = false
                var followNames: [String] = []
                if adaptive {
                    for rule in rules
                    where rule.matches(text: combinedText,
                                       port: port) {
                        switch rule.action {
                        case .tag(let label):
                            if !tags.contains(label) {
                                tags.append(label)
                            }
                        case .stop:
                            stop = true
                        case .followup(let name):
                            if !followNames.contains(name) {
                                followNames.append(name)
                            }
                        }
                    }
                }
                TraceBookStore.shared.record(
                    host: host, port: port, proto: "tcp",
                    analysis: analysis,
                    probes: probeName.map { [$0] } ?? [],
                    extraTags: tags, source: "trace",
                    bonjourName: nil)
                self.traceNote("  \(host):\(port) — "
                    + (analysis?.serviceHint
                       ?? ScanModel.serviceNames[port] ?? "open")
                    + (tags.isEmpty ? ""
                       : " · tagged \(tags.joined(separator: ", "))"))
                if !stop {
                    enqueueReferences(
                        TraceAnalyzer.references(in: combinedText),
                        fromHost: host, fromPort: port, depth: depth)
                }
                runFollowups(names: Array(followNames.prefix(4)),
                             host: host, port: port, depth: depth,
                             done: done)
            }

            if let probe = probeFor(targetText), probeCount < 1024 {
                probeCount += 1
                serializedSend(text: targetText,
                               payload: probe.data) { reply in
                    analyzeAndFinish(reply: reply,
                                     probeName: probe.name)
                }
            } else {
                analyzeAndFinish(reply: nil, probeName: nil)
            }
        }

        /// Profile one host: a banner probe on every profile
        /// port, each open door fully processed, then done.
        func profileHost(host: String, depth: Int, source: String,
                         done: @escaping () -> Void) {
            seenHosts.insert(host)
            profiledCount += 1
            addHostNode(host)
            TraceBookStore.shared.record(
                host: host, port: nil, analysis: nil,
                source: source, bonjourName: nil)
            var remaining = profile.count
            var doneFired = false
            func stepDown() {
                remaining -= 1
                if remaining == 0 && !doneFired {
                    doneFired = true
                    done()
                }
            }
            if remaining == 0 { done(); return }
            for port in profile {
                let key = "\(host):\(port)"
                if doneDoors.contains(key)
                    || queuedDoors.contains(key)
                    || doneDoors.count + queuedDoors.count >= 2048 {
                    stepDown()
                    continue
                }
                queuedDoors.insert(key)
                self.traceProbe(host: host, port: port) { data in
                    work.async {
                        guard gen == self.traceGeneration else { return }
                        if let data = data {
                            processDoor(host: host, port: port,
                                        banner: data, depth: depth) {
                                stepDown()
                            }
                        } else {
                            stepDown()
                        }
                    }
                }
            }
        }

        /// The frontier loop: one work item at a time, each
        /// item's internals as parallel as they safely are.
        /// An empty worklist is the definition of done.
        func pump() {
            work.async {
                guard gen == self.traceGeneration else { return }
                guard !worklist.isEmpty else {
                    finishTrace()
                    return
                }
                let item = worklist.removeFirst()
                switch item {
                case .host(let host, let depth, let source):
                    profileHost(host: host, depth: depth,
                                source: source) { pump() }
                case .door(let host, let port, let depth):
                    let key = "\(host):\(port)"
                    if doneDoors.contains(key) {
                        pump()
                        return
                    }
                    queuedDoors.insert(key)
                    self.traceProbe(host: host, port: port) { data in
                        work.async {
                            guard gen == self.traceGeneration
                            else { return }
                            if let data = data {
                                processDoor(host: host, port: port,
                                            banner: data,
                                            depth: depth) { pump() }
                            } else {
                                pump()
                            }
                        }
                    }
                }
            }
        }

        /// Discovery: one port's knock at a time across the
        /// whole /24, 32 knocks in flight, 1 s each — the
        /// crawl sweep's discipline.
        func runDiscovery(done: @escaping () -> Void) {
            var round = 0
            func nextRound() {
                guard gen == self.traceGeneration else { return }
                if round >= discovery.count {
                    for host in discoveredHosts
                        .sorted(by: TraceBookStore.ipLess) {
                        addHostNode(host)
                        let portsText = (answeredPorts[host] ?? [])
                            .sorted().map(String.init)
                            .joined(separator: ", ")
                        addEdge(from: phoneNodeID,
                                to: "host:\(host)",
                                kind: "discovered",
                                evidence: "answered on \(portsText)")
                        queueHost(host, depth: 0, source: "trace")
                    }
                    self.traceNote("Discovery done — "
                        + "\(discoveredHosts.count) host(s) answered")
                    done()
                    return
                }
                let port = discovery[round]
                round += 1
                self.traceNote("Discovery — knocking port \(port) "
                    + "across \(base).0/24 "
                    + "(round \(round)/\(discovery.count))…")
                let group = DispatchGroup()
                let gate = DispatchSemaphore(value: 32)
                let foundLock = NSLock()
                var found: [String] = []
                DispatchQueue.global().async { [weak self] in
                    guard let self = self else { return }
                    for octet in 1...254 {
                        let host = "\(base).\(octet)"
                        if host == ownIP { continue }
                        gate.wait()
                        group.enter()
                        self.traceKnock(host: host, port: port) {
                            open in
                            if open {
                                foundLock.lock()
                                found.append(host)
                                foundLock.unlock()
                            }
                            gate.signal()
                            group.leave()
                        }
                    }
                    group.notify(queue: work) {
                        for host in found {
                            discoveredHosts.insert(host)
                            answeredPorts[host, default: []]
                                .append(port)
                        }
                        nextRound()
                    }
                }
            }
            nextRound()
        }

        /// Bonjour: listen on the Scan tab's service types for
        /// the first ~5 s of the run, then resolve whatever
        /// announced itself. Resolved in-scope endpoints join
        /// the frontier; the announcements themselves are
        /// reported either way.
        func startBonjour() {
            guard includeBonjour else { return }
            for (type, label) in ScanModel.serviceTypes {
                let browser = NWBrowser(
                    for: .bonjour(type: type, domain: nil),
                    using: .tcp)
                browser.browseResultsChangedHandler = {
                    results, _ in
                    var found: [(name: String, type: String,
                                 label: String,
                                 endpoint: NWEndpoint)] = []
                    for result in results {
                        if case .service(let name, _, _, _)
                            = result.endpoint {
                            found.append((name: name, type: type,
                                          label: label,
                                          endpoint: result.endpoint))
                        }
                    }
                    if !found.isEmpty {
                        work.async {
                            for item in found {
                                bonjourSeen["\(item.type)|\(item.name)"]
                                    = item
                            }
                        }
                    }
                }
                browser.start(queue: self.probeQueue)
                bonjourBrowsers.append(browser)
            }
            work.asyncAfter(deadline: .now() + 5) {
                resolveBonjour()
            }
        }

        func resolveBonjour() {
            guard gen == self.traceGeneration else { return }
            bonjourBrowsers.forEach { $0.cancel() }
            bonjourBrowsers = []
            let items = Array(bonjourSeen.values)
            guard !items.isEmpty else {
                bonjourDone = true
                maybeStartWorklist()
                return
            }
            self.traceNote("Bonjour — resolving \(items.count) "
                + "service(s)…")
            let group = DispatchGroup()
            let gate = DispatchSemaphore(value: 8)
            for item in items {
                group.enter()
                DispatchQueue.global().async { [weak self] in
                    guard let self = self else {
                        group.leave()
                        return
                    }
                    gate.wait()
                    self.traceResolve(endpoint: item.endpoint) {
                        resolved in
                        if let (host, port) = resolved {
                            work.async {
                                guard gen == self.traceGeneration
                                else { return }
                                bonjourEntries.append(
                                    TraceBonjourEntry(
                                        name: item.name,
                                        type: item.type,
                                        label: item.label,
                                        host: host, port: port))
                                if inScope(host) {
                                    addHostNode(host)
                                    addEdge(
                                        from: phoneNodeID,
                                        to: "host:\(host)",
                                        kind: "bonjour",
                                        evidence: "\(item.label) — "
                                            + item.name)
                                    TraceBookStore.shared.record(
                                        host: host, port: nil,
                                        analysis: nil,
                                        source: "bonjour",
                                        bonjourName: item.name)
                                    queueHost(host, depth: 0,
                                              source: "bonjour")
                                    queueDoor(host, port, depth: 0)
                                }
                            }
                        } else {
                            work.async {
                                bonjourEntries.append(
                                    TraceBonjourEntry(
                                        name: item.name,
                                        type: item.type,
                                        label: item.label,
                                        host: nil, port: nil))
                            }
                        }
                        gate.signal()
                        group.leave()
                    }
                }
            }
            group.notify(queue: work) {
                bonjourDone = true
                maybeStartWorklist()
            }
        }

        func maybeStartWorklist() {
            guard discoveryDone, bonjourDone, !worklistStarted
            else { return }
            worklistStarted = true
            self.traceNote("Profiling — \(queuedHosts.count) host(s) "
                + "on the frontier")
            pump()
        }

        /// File the export, measure the diff, and say how the
        /// run ended. Runs once, on the work queue, when the
        /// frontier runs dry.
        func finishTrace() {
            guard gen == self.traceGeneration, !finishedFlag
            else { return }
            finishedFlag = true
            bonjourBrowsers.forEach { $0.cancel() }
            let after = TraceBookStore.shared
                .scopeDossiers(base: base)
                .filter { seenHosts.contains($0.ip) }
            let diff = TraceDiffer.diff(before: before,
                                        after: after,
                                        seenHosts: seenHosts,
                                        seenServices: seenDoorKeys)
            // The air joins the map: whatever the Listen
            // registry currently holds is filed as passive
            // sightings — a node per device, an edge from
            // this phone saying how loud it heard it — and
            // merged into the logbook's BLE pages.
            let bleSnapshot = BLESightings.snapshot()
            for device in bleSnapshot {
                let nodeID = "ble:\(device.id)"
                addNode(TraceNode(
                    id: nodeID, kind: "ble",
                    label: device.name
                        ?? String(device.id.prefix(8)),
                    ip: nil, port: nil))
                var evidence = "BLE"
                if let smooth = device.smoothedRSSI {
                    evidence += " · \(Int(smooth.rounded())) dBm smoothed"
                } else if let closest = device.closestRSSI {
                    evidence += " · closest \(closest) dBm"
                }
                evidence += " · ×\(device.sightings) sightings"
                addEdge(from: phoneNodeID, to: nodeID,
                        kind: "heard", evidence: evidence)
            }
            TraceBookStore.shared.mergeBLE(bleSnapshot)
            let export = TraceExport(
                schema: "net.nosuchmachine.nightjar.network-trace",
                schemaVersion: 2,
                kind: "trace-run",
                generatedAt: Date(),
                run: TraceRunInfo(
                    id: runID, scope: "\(base).0/24", base: base,
                    startedAt: startedAt, finishedAt: Date(),
                    stopReason: "frontier exhausted",
                    settings: TraceRunInfo.Settings(
                        discoveryPorts: discovery,
                        profilePorts: profile,
                        includeBonjour: includeBonjour,
                        adaptive: adaptive,
                        ruleCount: rules.count)),
                summary: [
                    "hostsSeen": seenHosts.count,
                    "hostsProfiled": profiledCount,
                    "doorsOpen": doorCount,
                    "activeProbes": probeCount,
                    "followups": followupCount,
                    "bonjourServices": bonjourEntries.count,
                    "bleDevices": bleSnapshot.count,
                    "externalReferences": externalRefs.count,
                    "newHosts": diff.newHosts.count,
                    "newServices": diff.newServices.count,
                    "changedServices": diff.changedServices.count,
                ],
                hosts: after,
                nodes: nodes,
                edges: edges,
                bonjour: bonjourEntries,
                bleDevices: bleSnapshot,
                externalReferences: externalRefs,
                diff: diff,
                limitations: TraceExport.limitations)
            let url = TraceExportWriter.write(export)
            // Armed from the Send tab: turn the map into a
            // Centipede route — one port train per host,
            // capped where a journey caps (300 doors).
            var centipedeArmed = false
            var centipedeRoute: String? = nil
            var loadedDoors = 0
            var loadedHosts = 0
            if self.traceAutoCentipede {
                centipedeArmed = true
                self.traceAutoCentipede = false
                var lines: [String] = []
                let sortedHosts = after.sorted { a, b in
                    (Int(a.ip.split(separator: ".").last ?? "") ?? 0)
                        < (Int(b.ip.split(separator: ".").last ?? "") ?? 0)
                }
                for host in sortedHosts {
                    let ports = Array(Set(host.services.map(\.port)))
                        .filter { $0 > 0 }.sorted()
                    if ports.isEmpty { continue }
                    let room = 300 - loadedDoors
                    if room <= 0 { break }
                    let take = Array(ports.prefix(room))
                    lines.append(host.ip + ":"
                        + take.map(String.init).joined(separator: ","))
                    loadedDoors += take.count
                    loadedHosts += 1
                }
                if !lines.isEmpty {
                    centipedeRoute = lines.joined(separator: "\n")
                }
            }
            let statusText = "Frontier exhausted — "
                + "\(seenHosts.count) host(s), \(doorCount) door(s), "
                + "\(probeCount) probe(s)"
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.traceBusy = false
                ProcessBoard.shared.endKeyed(
                    "mouth.trace", .done(statusText))
                self.traceLatestExport = url
                self.traceStatus = statusText
                self.traceLines.append(statusText)
                if !diff.newHosts.isEmpty {
                    self.traceLines.append("New since last time: "
                        + diff.newHosts.joined(separator: ", "))
                }
                if let url = url {
                    self.traceLines.append("Trace written — "
                        + url.lastPathComponent)
                }
                if centipedeArmed {
                    if let route = centipedeRoute {
                        self.traceCentipedeRoute = route
                        self.traceLines.append(
                            "Centipede configured — \(loadedDoors) door(s) "
                            + "on \(loadedHosts) host(s) loaded as its route")
                    } else {
                        self.traceLines.append(
                            "Centipede setup — the trace found no "
                            + "open doors to load")
                    }
                }
                self.logRecon("network-trace", "\(base).0/24",
                              lines: self.traceLines)
                self.toasts?.show(String(format: L("Trace complete — %lld host(s) mapped"), seenHosts.count))
            }
        }

        startBonjour()
        runDiscovery {
            work.async {
                discoveryDone = true
                maybeStartWorklist()
            }
        }
    }

    /// Stop a trace between stages; whatever is in flight
    /// lands on its own timeout and is ignored by generation.
    func stopNetworkTrace() {
        traceGeneration += 1
        if traceBusy {
            traceBusy = false
            ProcessBoard.shared.endKeyed(
                "mouth.trace", .stopped)
            traceStatus = "Stopped — trace halted by hand"
            traceLines.append("Stopped — trace halted by hand")
            line("network-trace: stopped by hand")
        }
    }
}
