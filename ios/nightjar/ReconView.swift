import Foundation
import Network
import NetworkExtension
import Security
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Connect scanner + Bonjour sweep

struct PortResult: Identifiable {
    var id: Int { port }
    let port: Int
    let service: String
    var banner: String?
}

struct SweepHost: Identifiable {
    var id: String { "\(ip):\(port)" }
    let ip: String
    let octet: Int
    let port: Int
}

struct DiscoveredService: Identifiable {
    let id = UUID()
    let type: String
    let label: String
    let name: String
    // Module-qualified: importing NetworkExtension alongside
    // Network makes the bare NWEndpoint ambiguous to the compiler.
    let endpoint: Network.NWEndpoint
}

/// Recon within what iOS allows an app: TCP connect scans (no raw
/// sockets, so no SYN or UDP scans), banner grabs from whatever
/// answers, and a Bonjour sweep of the local network.
final class ScanModel: ObservableObject {
    @Published private(set) var results: [PortResult] = []
    @Published private(set) var lastScannedHost = ""
    @Published private(set) var scanning = false
    @Published private(set) var probedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var discovered: [DiscoveredService] = []
    @Published private(set) var sweepHosts: [SweepHost] = []
    @Published private(set) var sweeping = false
    @Published private(set) var sweptCount = 0

    static let topPorts: [(Int, String)] = [
        (21, "FTP"), (22, "SSH"), (23, "Telnet"), (25, "SMTP"),
        (53, "DNS"), (80, "HTTP"), (110, "POP3"), (143, "IMAP"),
        (443, "HTTPS"), (445, "SMB"), (993, "IMAPS"), (995, "POP3S"),
        (1723, "PPTP"), (1883, "MQTT"), (3306, "MySQL"), (3389, "RDP"),
        (5060, "SIP"), (5432, "Postgres"), (5900, "VNC"),
        (6379, "Redis"), (8080, "HTTP alt"), (8443, "HTTPS alt"),
        (9100, "Printer"), (9200, "Elasticsearch"),
        (11211, "memcached"), (27017, "MongoDB"), (161, "SNMP"),
        (2049, "NFS"),
    ]

    static let serviceNames: [Int: String] =
        Dictionary(uniqueKeysWithValues: topPorts)

    /// Open port -> the library probe that speaks its language,
    /// for the Scan -> Send handoff.
    static let payloadByPort: [Int: String] = [
        25: "SMTP EHLO",
        53: "DNS query — example.com (UDP 53)",
        80: "HTTP GET / (raw)",
        502: "Modbus read coils (TCP 502)",
        161: "SNMP get sysDescr (UDP 161)",
        1883: "MQTT CONNECT (client: nightjar)",
        5060: "SIP OPTIONS (UDP/TCP 5060)",
        5432: "Postgres SSLRequest (TCP 5432)",
        6379: "Redis PING (RESP)",
        9100: "Printer test page (TCP 9100)",
        11211: "memcached stats",
    ]

    private static let httpPorts: Set<Int> = [80, 8000, 8080, 8888, 9200]

    private let queue = DispatchQueue(label: "nightjar-scan",
                                      attributes: .concurrent)
    /// NWConnection starts and their deadline timers live here,
    /// NOT on `queue`: the scan/sweep workers block `queue` on
    /// their semaphores, so a connection started there could be
    /// starved behind its own gating.
    private let connectionQueue = DispatchQueue(
        label: "nightjar-scan-connections")
    private let lock = NSLock()
    private var browsers: [NWBrowser] = []

    func scan(host: String, ports: [Int]) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !scanning, !sweeping, !ports.isEmpty
        else { return }
        lastScannedHost = host
        scanning = true
        scanBoardID = ProcessBoard.shared.begin(
            label: "Port scan — \(host)", organ: "Scan",
            detail: "\(ports.count) ports")
        results = []
        probedCount = 0
        totalCount = ports.count
        var found: [PortResult] = []
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 24)
        for port in ports {
            group.enter()
            queue.async { [weak self] in
                guard let self = self else { group.leave(); return }
                semaphore.wait()
                self.probe(host: host, port: port) { result in
                    if let result = result {
                        self.lock.lock()
                        found.append(result)
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { self.probedCount += 1 }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.results = found.sorted { $0.port < $1.port }
            self?.scanning = false
            if let id = self?.scanBoardID {
                self?.scanBoardID = nil
                ProcessBoard.shared.end(id, .done(
                    "\(found.count) open port(s)"))
            }
        }
    }

    private func probe(host: String, port: Int,
                       done: @escaping (PortResult?) -> Void) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else { done(nil); return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let service = ScanModel.serviceNames[port] ?? ""
        let finishLock = NSLock()
        var finished = false
        var wasReady = false
        let finish: (PortResult?) -> Void = { result in
            finishLock.lock()
            if finished {
                finishLock.unlock()
                return
            }
            finished = true
            finishLock.unlock()
            connection.cancel()
            done(result)
        }
        func ready() -> Bool {
            finishLock.lock()
            defer { finishLock.unlock() }
            return wasReady
        }
        // Connect deadline — it applies only until the connection
        // is up. Once .ready fires the port IS open, and nothing
        // that happens afterwards (a reset, a close, a slow
        // banner) is allowed to un-open it. The previous shape —
        // an unconditional 2.5s finish(nil) racing a 1.2s banner
        // window — reported slow-connecting silent services
        // (443, 445, 3389, 6379…) closed. That was the bug.
        connectionQueue.asyncAfter(deadline: .now() + 2.5) {
            if !ready() { finish(nil) }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                finishLock.lock()
                wasReady = true
                finishLock.unlock()
                func grab() {
                    connection.receive(minimumIncompleteLength: 1,
                                       maximumLength: 4096) { data, _, _, _ in
                        var banner: String?
                        if let data = data, !data.isEmpty {
                            let text = String(decoding: data, as: UTF8.self)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            banner = text.isEmpty ? nil : text
                        }
                        finish(PortResult(port: port, service: service,
                                          banner: banner))
                    }
                    // Answers that say nothing still count as open:
                    // the banner window ends the probe, successfully.
                    self.connectionQueue.asyncAfter(deadline: .now() + 1.2) {
                        finish(PortResult(port: port, service: service,
                                          banner: nil))
                    }
                }
                if ScanModel.httpPorts.contains(port) {
                    connection.send(
                        content: Data("HEAD / HTTP/1.0\r\n\r\n".utf8),
                        completion: .contentProcessed { _ in grab() })
                } else {
                    grab()
                }
            case .failed, .cancelled:
                // A failure before connect = closed/filtered. A
                // failure after .ready changes nothing: the open
                // result is already owned by the banner paths.
                if !ready() { finish(nil) }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    // MARK: Subnet sweep

    /// Host discovery: knock on one port across the phone's whole
    /// Wi-Fi /24 and list whoever answers. Connect-only, like the
    /// port scan — a host with that port closed or firewalled to
    /// drops stays invisible, and the UI says so.
    func sweep(port: Int) {
        // The Standard: under ALPHA even the hand-run
        // sweeps stop — total silence means total.
        guard !EmconStandard.refused(.sweep) else { return }
        guard !sweeping, !scanning, (1...65535).contains(port),
              let own = Mouth.localIPAddress() else { return }
        let generation = sweepGeneration
        let parts = own.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = parts.dropLast().joined(separator: ".") + "."
        sweeping = true
        if !sweepIsWatch {
            sweepBoardID = ProcessBoard.shared.begin(
                label: "Sweep — port \(port)", organ: "Scan",
                detail: "across the /24",
                stop: { [weak self] in self?.stopSweep() })
        }
        sweepHosts = []
        sweptCount = 0
        var found: [SweepHost] = []
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 32)
        for octet in 1...254 {
            let ip = prefix + "\(octet)"
            group.enter()
            queue.async { [weak self] in
                guard let self = self else { group.leave(); return }
                semaphore.wait()
                self.sweepProbe(host: ip, port: port) { alive in
                    if alive {
                        self.lock.lock()
                        found.append(SweepHost(ip: ip, octet: octet,
                                               port: port))
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { self.sweptCount += 1 }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.sweeping = false
            // A sweep stopWatch() superseded while it was in
            // flight is stale: it publishes nothing and fires no
            // callbacks — it only clears `sweeping`, above.
            guard generation == self.sweepGeneration else {
                self.sweepIsWatch = false
                return
            }
            self.sweepHosts = found.sorted { $0.octet < $1.octet }
            NeighborhoodStore.shared.recordSweep(self.sweepHosts)
            let wasWatch = self.sweepIsWatch
            self.sweepIsWatch = false
            if !wasWatch, let id = self.sweepBoardID {
                self.sweepBoardID = nil
                ProcessBoard.shared.end(id, .done(
                    "\(found.count) host(s) answering"))
            }
            // Only a watch-cycle sweep feeds the observation
            // chain; a manual sweep pressed mid-watch must not
            // diff against the feed baseline or hijack its timer.
            if wasWatch { self.sweepFinished() }
            self.onSweepCompleted?(wasWatch)
        }
    }

    // MARK: Observation feed

    struct FeedEvent: Identifiable {
        let id = UUID()
        let at = Date()
        let text: String
    }

    @Published private(set) var feed: [FeedEvent] = []
    @Published private(set) var watching = false
    /// True while the in-flight sweep belongs to the watch chain.
    private var sweepIsWatch = false
    /// Bumped by stopWatch(); a sweep that started under an older
    /// generation is stale by the time it finishes.
    private var sweepGeneration = 0
    private var sweepBoardID: UUID?
    private var scanBoardID: UUID?
    private var watchBoardID: UUID?
    /// Set by ScanView: called on the main queue after every
    /// sweep, with whether that sweep was a watch cycle (manual
    /// completions toast, feed targets, and log; watch ones don't).
    var onSweepCompleted: ((Bool) -> Void)?
    private var knownHosts: Set<String> = []
    private var knownServices: Set<String> = []
    private var baselineTaken = false
    private var watchWork: DispatchWorkItem?
    private var feedPort = 80

    /// The network, narrated: re-sweep the /24 on a relaxed
    /// interval and stream the changes — hosts answering, hosts
    /// going dark, Bonjour services appearing and vanishing —
    /// into a scrolling feed. Built only from what the phone can
    /// observe itself: connect knocks and announcements.
    func startWatch(port: Int) {
        guard !watching else { return }
        watching = true
        watchBoardID = ProcessBoard.shared.begin(
            label: "Watch — port \(port)", organ: "Scan",
            detail: "narrating the /24", announce: false,
            stop: { [weak self] in self?.stopWatch() })
        feedPort = port
        baselineTaken = false
        knownServices = Set(discovered.map { "\($0.name)|\($0.type)" })
        appendFeed("watch started — sweeping port \(port) "
                   + "across the /24")
        watchCycle()
    }

    /// Stop a plain sweep mid-flight — the
    /// generation bump makes the in-flight
    /// group's completion stale, and the flag
    /// drops now. The emergency stop reaches
    /// the wire through here.
    func stopSweep() {
        sweepGeneration += 1
        sweeping = false
        if let id = sweepBoardID {
            sweepBoardID = nil
            ProcessBoard.shared.end(id, .stopped)
        }
    }

    func stopWatch() {
        sweepGeneration += 1
        guard watching else { return }
        watching = false
        if let id = watchBoardID {
            watchBoardID = nil
            ProcessBoard.shared.end(id, .stopped)
        }
        watchWork?.cancel()
        appendFeed("watch stopped")
    }

    func clearFeed() { feed = [] }

    private func appendFeed(_ text: String) {
        feed.insert(FeedEvent(text: text), at: 0)
        if feed.count > 200 { feed.removeLast(feed.count - 200) }
    }

    private func watchCycle() {
        guard watching else { return }
        let servicesNow = Set(discovered.map { "\($0.name)|\($0.type)" })
        if baselineTaken {
            for service in servicesNow.subtracting(knownServices).sorted() {
                appendFeed("Bonjour up: "
                           + service.components(separatedBy: "|")[0])
            }
            for service in knownServices.subtracting(servicesNow).sorted() {
                appendFeed("Bonjour down: "
                           + service.components(separatedBy: "|")[0])
            }
        }
        knownServices = servicesNow
        sweepIsWatch = true
        sweep(port: feedPort)
        if !sweeping {
            // The sweep refused to start (a manual scan is
            // running, or there is no Wi-Fi address right now).
            // Without this, the chain would end here silently —
            // watching stays true and nothing ever fires again.
            sweepIsWatch = false
            appendFeed("cycle skipped — busy or off Wi-Fi; retrying")
            scheduleNextWatchCycle()
        }
    }

    private func scheduleNextWatchCycle() {
        watchWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.watchCycle() }
        watchWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 20,
                                      execute: item)
    }

    private func sweepFinished() {
        guard watching else { return }
        let now = Set(sweepHosts.map { "\($0.ip):\($0.port)" })
        if baselineTaken {
            for host in now.subtracting(knownHosts).sorted() {
                appendFeed("host answering: \(host)")
            }
            for host in knownHosts.subtracting(now).sorted() {
                appendFeed("host dark: \(host)")
            }
        } else {
            baselineTaken = true
            appendFeed("baseline: \(now.count) host(s) answering "
                       + "on port \(feedPort)")
        }
        knownHosts = now
        scheduleNextWatchCycle()
    }

    private func sweepProbe(host: String, port: Int,
                            done: @escaping (Bool) -> Void) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else { done(false); return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let finishLock = NSLock()
        var finished = false
        let finish: (Bool) -> Void = { alive in
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            done(alive)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        connectionQueue.asyncAfter(deadline: .now() + 1.0) { finish(false) }
    }

    // MARK: Bonjour sweep

    static let serviceTypes: [(String, String)] = [
        ("_ssh._tcp", "SSH"), ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS"), ("_smb._tcp", "SMB file sharing"),
        ("_ipp._tcp", "Printer"), ("_printer._tcp", "Printer"),
        ("_airplay._tcp", "AirPlay"), ("_googlecast._tcp", "Chromecast"),
        ("_mqtt._tcp", "MQTT"), ("_nightjar._tcp", "nightjar-hack phone"),
    ]

    func startDiscovery() {
        guard browsers.isEmpty else { return }
        for (type, label) in ScanModel.serviceTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil),
                                    using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                let mine: [DiscoveredService] = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return DiscoveredService(type: type, label: label,
                                                 name: name,
                                                 endpoint: result.endpoint)
                    }
                    return nil
                }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    var kept = self.discovered.filter { $0.type != type }
                    kept += mine
                    self.discovered = kept.sorted {
                        ($0.label, $0.name) < ($1.label, $1.name)
                    }
                }
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    /// Resolve a discovered Bonjour service to its IP and port by
    /// opening one connection and reading where it landed — the
    /// address the announcement itself never shows.
    func resolve(_ service: DiscoveredService,
                 done: @escaping ((String, Int)?) -> Void) {
        let connection = NWConnection(to: service.endpoint, using: .tcp)
        let finishLock = NSLock()
        var finished = false
        let finish: ((String, Int)?) -> Void = { resolved in
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            if let resolved = resolved {
                NeighborhoodStore.shared.recordBonjour(
                    ip: resolved.0, name: service.name,
                    label: service.label)
            }
            done(resolved)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   case .hostPort(let host, let port) = path.remoteEndpoint {
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
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
    }

    func stopDiscovery() {
        browsers.forEach { $0.cancel() }
        browsers = []
    }
}

// MARK: - TLS certificate inspector

/// Inspects a TLS endpoint the polite way: a real HTTPS handshake
/// through URLSession, with the trust chain read out of the
/// challenge — verdict, subjects, validity windows.
final class TLSInspector: NSObject, ObservableObject, URLSessionTaskDelegate {
    @Published private(set) var lines: [String] = []
    @Published private(set) var inspecting = false
    private var collected: [String] = []
    private var verdict = ""
    private var session: URLSession?

    func inspect(host: String, port: Int) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !inspecting,
              let url = URL(string: "https://\(host):\(port)/") else { return }
        inspecting = true
        lines = []
        collected = []
        verdict = ""
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config,
                                 delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping
                        (URLSession.AuthChallengeDisposition,
                         URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        var cfError: CFError?
        let ok = SecTrustEvaluateWithError(trust, &cfError)
        verdict = ok ? "system trust: VALID"
            : "system trust: NOT trusted — "
              + (cfError?.localizedDescription ?? "unknown reason")
        var out: [String] = []
        let chain = (SecTrustCopyCertificateChain(trust)
                     as? [SecCertificate]) ?? []
        out.append("chain: \(chain.count) certificate(s)")
        for (index, cert) in chain.enumerated() {
            let subject = (SecCertificateCopySubjectSummary(cert)
                           as String?) ?? "?"
            out.append("[\(index)] \(subject)")
            if let window = validity(of: cert) {
                out.append("    valid \(window)")
            }
        }
        collected = out
        // Accept the server credential only if a certificate
        // chain was actually captured to inspect; with no chain
        // there is nothing verified to hand back, so cancel.
        if chain.isEmpty {
            completionHandler(.cancelAuthenticationChallenge, nil)
        } else {
            completionHandler(.useCredential, URLCredential(trust: trust))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var lines = ([self.verdict] + self.collected)
                .filter { !$0.isEmpty }
            if lines.isEmpty {
                lines = ["handshake failed: "
                         + (error?.localizedDescription ?? "no answer")]
            }
            self.lines = lines
            self.inspecting = false
        }
        session.finishTasksAndInvalidate()
    }

    /// Validity window, read straight out of the certificate's
    /// DER: SecCertificateCopyValues and the X.509 OID constants
    /// are macOS-only, so an iOS inspector walks the ASN.1 itself —
    /// certificate → tbsCertificate → [0] version → serial →
    /// signature → issuer → validity { notBefore, notAfter }.
    /// (This walk was verified against openssl's own date output
    /// on a real certificate before it shipped.)
    private func validity(of cert: SecCertificate) -> String? {
        let der = [UInt8](SecCertificateCopyData(cert) as Data)

        func tlv(_ offset: Int) -> (tag: UInt8, start: Int, end: Int)? {
            guard offset + 2 <= der.count else { return nil }
            var length = Int(der[offset + 1])
            var header = 2
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count >= 1, count <= 4,
                      offset + 2 + count <= der.count else { return nil }
                length = 0
                for i in 0..<count {
                    length = (length << 8) | Int(der[offset + 2 + i])
                }
                header = 2 + count
            }
            let start = offset + header
            guard start + length <= der.count else { return nil }
            return (der[offset], start, start + length)
        }

        guard let outer = tlv(0), outer.tag == 0x30,
              let tbs = tlv(outer.start), tbs.tag == 0x30
        else { return nil }
        var pos = tbs.start
        guard let first = tlv(pos) else { return nil }
        if first.tag == 0xA0 { pos = first.end }        // [0] version
        for _ in 0..<3 {                                 // serial, signature, issuer
            guard let element = tlv(pos) else { return nil }
            pos = element.end
        }
        guard let window = tlv(pos), window.tag == 0x30,
              let notBefore = tlv(window.start),
              let notAfter = tlv(notBefore.end),
              let from = derTime(tag: notBefore.tag,
                                 der[notBefore.start..<notBefore.end]),
              let to = derTime(tag: notAfter.tag,
                               der[notAfter.start..<notAfter.end])
        else { return nil }
        // The DER times are GMT (derTime parses them as GMT), so
        // render them in GMT too — Date.formatted would use the
        // phone's local timezone and shift the dates.
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US_POSIX")
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.dateFormat = "MMM d, yyyy"
        return "\(display.string(from: from)) → "
            + display.string(from: to)
    }

    private func derTime(tag: UInt8, _ bytes: ArraySlice<UInt8>) -> Date? {
        guard let text = String(bytes: [UInt8](bytes), encoding: .ascii)
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = tag == 0x17
            ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = tag == 0x17
            ? "yyMMddHHmm'Z'" : "yyyyMMddHHmmss.SSS'Z'"
        return formatter.date(from: text)
    }
}


// MARK: - DNS toolkit

/// Real DNS over UDP: build a query, parse the answer — name
/// compression and all — the structured version of the library's
/// hand-rolled DNS seed.
enum DNSKit {
    static func buildQuery(name: String, type: UInt16) -> Data {
        buildQuery(name: name, type: type,
                   id: UInt16.random(in: 0...UInt16.max))
    }

    /// The caller picks (and keeps) the transaction ID so the
    /// response can be checked against it.
    static func buildQuery(name: String, type: UInt16,
                           id: UInt16) -> Data {
        var data = Data()
        data.append(UInt8(id >> 8))
        data.append(UInt8(id & 0xff))
        data.append(contentsOf: [0x01, 0x00])              // RD
        data.append(contentsOf: [0x00, 0x01])              // QDCOUNT 1
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") where !label.isEmpty {
            // The length prefix counts wire bytes, not Characters.
            data.append(UInt8(clamping: label.utf8.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(0)
        data.append(UInt8(type >> 8))
        data.append(UInt8(type & 0xff))
        data.append(contentsOf: [0x00, 0x01])              // IN
        return data
    }

    static func readName(_ data: Data, _ offset: inout Int) -> String {
        readName(data, &offset, limit: data.count)
    }

    /// Reads a (possibly compressed) name, never stepping past
    /// `limit` — RDATA callers pass the end of their RDLENGTH
    /// window so a name cannot run on into the next record.
    static func readName(_ data: Data, _ offset: inout Int,
                         limit: Int) -> String {
        var labels: [String] = []
        var pos = offset
        var next = offset
        var jumped = false
        var steps = 0
        let bound = min(limit, data.count)
        while pos < bound, steps < 128 {
            steps += 1
            let len = Int(data[pos])
            if len == 0 {
                if !jumped { next = pos + 1 }
                break
            }
            if len & 0xC0 == 0xC0 {
                // A pointer is two bytes; a trailing lone byte is
                // malformed — stop instead of reading past it.
                guard pos + 1 < bound else { break }
                if !jumped { next = pos + 2 }
                jumped = true
                pos = ((len & 0x3F) << 8) | Int(data[pos + 1])
                continue
            }
            // Reserved label types (0x40 / 0x80) end the name.
            if len & 0xC0 != 0 { break }
            let end = pos + 1 + len
            guard end <= bound else { break }
            labels.append(String(decoding: data[(pos + 1)..<end],
                                 as: UTF8.self))
            pos = end
            if !jumped { next = end }
        }
        offset = next
        return labels.joined(separator: ".")
    }

    /// True only for a response (QR=1) to the query with this
    /// transaction ID — anything else on the socket is not ours.
    static func isResponse(_ data: Data, to id: UInt16) -> Bool {
        guard data.count >= 4 else { return false }
        let txid = (UInt16(data[0]) << 8) | UInt16(data[1])
        return txid == id && data[2] & 0x80 != 0
    }

    static func parseAnswers(_ data: Data) -> [String] {
        func u16(_ i: Int) -> Int { (Int(data[i]) << 8) | Int(data[i + 1]) }
        func u32(_ i: Int) -> Int { (u16(i) << 16) | u16(i + 2) }
        guard data.count >= 12 else { return ["short response"] }
        let rcode = Int(data[3]) & 0x0F
        if rcode == 3 { return ["NXDOMAIN — the name does not exist"] }
        if rcode != 0 {
            return ["DNS error — the server answered with RCODE \(rcode)"]
        }
        let qd = u16(4), an = u16(6)
        var pos = 12
        for _ in 0..<qd {
            _ = readName(data, &pos)
            pos += 4
        }
        var lines: [String] = []
        for _ in 0..<an {
            let name = readName(data, &pos)
            guard pos + 10 <= data.count else { break }
            let type = u16(pos), ttl = u32(pos + 4), rdlen = u16(pos + 8)
            let rstart = pos + 10
            guard rstart + rdlen <= data.count else { break }
            lines.append("\(name) · \(typeName(type)) · ttl \(ttl)")
            lines.append("  " + formatRdata(data, type: type,
                                            start: rstart, length: rdlen))
            pos = rstart + rdlen
        }
        return lines.isEmpty ? ["no records in the answer"] : lines
    }

    private static func formatRdata(_ data: Data, type: Int,
                                    start: Int, length: Int) -> String {
        let bytes = [UInt8](data[start..<(start + length)])
        switch type {
        case 1 where bytes.count == 4:
            return bytes.map(String.init).joined(separator: ".")
        case 28 where bytes.count == 16:
            return ipv6(bytes)
        case 2, 5:
            var off = start
            return readName(data, &off, limit: start + length)
        case 15:
            guard bytes.count > 2 else { return "?" }
            let pref = (Int(bytes[0]) << 8) | Int(bytes[1])
            var off = start + 2
            return "\(pref) \(readName(data, &off, limit: start + length))"
        case 16:
            var parts: [String] = []
            var i = 0
            while i < bytes.count {
                let len = Int(bytes[i])
                i += 1
                guard i + len <= bytes.count else { break }
                parts.append(String(decoding: bytes[i..<(i + len)],
                                    as: UTF8.self))
                i += len
            }
            return parts.joined(separator: " ")
        default:
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    static func ipv6(_ bytes: [UInt8]) -> String {
        var groups: [Int] = []
        for i in stride(from: 0, to: 16, by: 2) {
            groups.append((Int(bytes[i]) << 8) | Int(bytes[i + 1]))
        }
        var bestStart = -1, bestLen = 0, runStart = -1, runLen = 0
        for (i, g) in groups.enumerated() {
            if g == 0 {
                if runStart < 0 { runStart = i; runLen = 1 } else { runLen += 1 }
                if runLen > bestLen { bestLen = runLen; bestStart = runStart }
            } else {
                runStart = -1; runLen = 0
            }
        }
        guard bestLen >= 2 else {
            return groups.map { String($0, radix: 16) }.joined(separator: ":")
        }
        let left = groups[..<bestStart]
            .map { String($0, radix: 16) }.joined(separator: ":")
        let right = groups[(bestStart + bestLen)...]
            .map { String($0, radix: 16) }.joined(separator: ":")
        return left + "::" + right
    }

    static func typeName(_ type: Int) -> String {
        [1: "A", 2: "NS", 5: "CNAME", 15: "MX", 16: "TXT", 28: "AAAA"][type]
            ?? "type \(type)"
    }
}

final class DNSModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var querying = false

    func lookup(name: String, typeName: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !querying else { return }
        let code: UInt16 = ["A": 1, "AAAA": 28, "MX": 15, "NS": 2,
                            "CNAME": 5, "TXT": 16][typeName] ?? 1
        querying = true
        lines = []
        let connection = NWConnection(host: "1.1.1.1", port: 53, using: .udp)
        let lock = NSLock()
        var done = false
        let finish: ([String]) -> Void = { [weak self] result in
            lock.lock()
            let already = done
            done = true
            lock.unlock()
            guard !already else { return }
            connection.cancel()
            DispatchQueue.main.async {
                self?.lines = result
                self?.querying = false
            }
        }
        // One transaction ID for the query and its single retry,
        // so a response can be verified against it.
        let queryID = UInt16.random(in: 0...UInt16.max)
        let query = DNSKit.buildQuery(name: trimmed, type: code,
                                      id: queryID)
        var attempts = 0
        let isDone: () -> Bool = {
            lock.lock()
            defer { lock.unlock() }
            return done
        }
        // Closure variables rather than nested functions: each
        // re-invokes itself from inside escaping completions.
        var armReceive: (() -> Void)!
        var sendQuery: (() -> Void)!
        armReceive = {
            connection.receive(minimumIncompleteLength: 12,
                               maximumLength: 4096) {
                data, _, _, error in
                if let data = data, data.count >= 12 {
                    // Stray or spoofed datagrams are not the
                    // answer: only our TXID with QR=1 counts, and
                    // anything else just re-arms the wait.
                    guard DNSKit.isResponse(data, to: queryID) else {
                        if !isDone() { armReceive() }
                        return
                    }
                    finish(DNSKit.parseAnswers(data))
                } else {
                    finish(["no answer ("
                            + (error?.localizedDescription
                               ?? "empty reply") + ")"])
                }
            }
        }
        sendQuery = {
            attempts += 1
            let attempt = attempts
            connection.send(content: query,
                            completion: .contentProcessed { _ in
                                armReceive()
                            })
            // One retry on timeout; the second timeout is final.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                guard !isDone(), attempt == attempts else { return }
                if attempt < 2 {
                    sendQuery()
                } else {
                    finish(["timed out — no answer from 1.1.1.1"])
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sendQuery()
            case .failed(let error):
                finish(["query failed: \(error.localizedDescription)"])
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "nightjar-dns"))
    }
}

// MARK: - Pcap dissector

/// A libpcap reader and protocol dissector: takes apart capture
/// files recorded on your own machines (tcpdump -w) and prints
/// them in plain text — the app's own decoder, on-device.
/// Ethernet, Linux cooked, raw IP and BSD loopback link types;
/// IPv4/IPv6, TCP, UDP, ICMP, ARP. Classic .pcap only (not
/// pcapng).
enum PcapKit {
    private struct Reader {
        let data: Data
        let swap: Bool
        func u16(_ i: Int) -> Int {
            let a = Int(data[i]), b = Int(data[i + 1])
            return swap ? (b << 8) | a : (a << 8) | b
        }
        func u32(_ i: Int) -> Int {
            let v = (0..<4).map { Int(data[i + $0]) }
            return swap ? (v[3] << 24) | (v[2] << 16) | (v[1] << 8) | v[0]
                        : (v[0] << 24) | (v[1] << 16) | (v[2] << 8) | v[3]
        }
    }

    static func dissect(_ data: Data, name: String)
        -> (summary: [String], lines: [String])? {
        guard data.count >= 24 else { return nil }
        let head = [UInt8](data.prefix(4))
        let swap: Bool
        let nano: Bool
        switch head {
        case [0xa1, 0xb2, 0xc3, 0xd4]: swap = false; nano = false
        case [0xd4, 0xc3, 0xb2, 0xa1]: swap = true; nano = false
        case [0xa1, 0xb2, 0x3c, 0x4d]: swap = false; nano = true
        case [0x4d, 0x3c, 0xb2, 0xa1]: swap = true; nano = true
        default: return nil
        }
        let reader = Reader(data: data, swap: swap)
        let linktype = reader.u32(20)
        var pos = 24
        var lines: [String] = []
        var tally: [String: Int] = [:]
        var totalBytes = 0
        var firstTs: Double?
        var lastTs: Double = 0
        var count = 0
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        while pos + 16 <= data.count, count < 500 {
            let sec = reader.u32(pos)
            let frac = reader.u32(pos + 4)
            let incl = reader.u32(pos + 8)
            guard incl >= 0, pos + 16 + incl <= data.count else { break }
            let packet = data[(pos + 16)..<(pos + 16 + incl)]
            pos += 16 + incl
            count += 1
            totalBytes += incl
            let ts = Double(sec) + Double(frac) / (nano ? 1e9 : 1e6)
            if firstTs == nil { firstTs = ts }
            lastTs = ts
            let stamp = formatter.string(
                from: Date(timeIntervalSince1970: ts))
                + String(format: ".%06d", nano ? frac / 1000 : frac)
            let decoded = decodePacket(packet, linktype: linktype)
            tally[decoded.proto, default: 0] += 1
            lines.append("#\(count) \(stamp)  \(decoded.text)")
            if let preview = decoded.preview {
                lines.append("    \(preview)")
            }
        }
        // The global header was valid, so this IS a libpcap
        // capture — one with no complete records in it. Say so
        // instead of falling through to "not a libpcap capture".
        guard count > 0 else {
            let empty = "0 packets — the capture is empty or truncated"
            return (["\(name) — \(empty)"], [empty])
        }
        var summary = ["\(name) — \(count) packet(s), \(totalBytes) bytes"]
        if let first = firstTs {
            summary.append("span "
                + String(format: "%.2f", lastTs - first)
                + "s · linktype \(linktype)")
        }
        summary.append(tally.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: " · "))
        if count == 500 {
            summary.append("showing the first 500 packets")
        }
        return (summary, lines)
    }

    private static func mac(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func ipv4(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map(String.init).joined(separator: ".")
    }

    private static func preview(of payload: Data.SubSequence) -> String? {
        guard !payload.isEmpty else { return nil }
        let slice = Data(payload.prefix(96))
        if let text = PayloadKit.printableText(slice) {
            let oneLine = text.components(separatedBy: .newlines)
                .joined(separator: " ")
            return String(oneLine.prefix(90))
        }
        return "hex " + slice.prefix(24)
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func decodePacket(_ packet: Data.SubSequence,
                                     linktype: Int)
        -> (proto: String, text: String, preview: String?) {
        let bytes = [UInt8](packet)
        switch linktype {
        case 1: // Ethernet
            guard bytes.count >= 14 else {
                return ("short", "truncated ethernet frame", nil)
            }
            var ethertype = (Int(bytes[12]) << 8) | Int(bytes[13])
            var offset = 14
            if ethertype == 0x8100, bytes.count >= 18 {
                ethertype = (Int(bytes[16]) << 8) | Int(bytes[17])
                offset = 18
            }
            switch ethertype {
            case 0x0800:
                return decodeIPv4(bytes, offset)
            case 0x86dd:
                return decodeIPv6(bytes, offset)
            case 0x0806:
                return decodeARP(bytes, offset)
            default:
                return ("eth", "ethertype 0x"
                    + String(format: "%04x", ethertype)
                    + "  \(mac(Array(bytes[6..<12]))) → "
                    + "\(mac(Array(bytes[0..<6])))", nil)
            }
        case 113: // Linux cooked capture
            guard bytes.count >= 16 else {
                return ("short", "truncated cooked frame", nil)
            }
            let proto = (Int(bytes[14]) << 8) | Int(bytes[15])
            switch proto {
            case 0x0800: return decodeIPv4(bytes, 16)
            case 0x86dd: return decodeIPv6(bytes, 16)
            case 0x0806: return decodeARP(bytes, 16)
            default: return ("eth", "cooked ethertype 0x"
                + String(format: "%04x", proto), nil)
            }
        case 101: // raw IP
            guard let first = bytes.first else {
                return ("short", "empty packet", nil)
            }
            return first >> 4 == 6 ? decodeIPv6(bytes, 0)
                                   : decodeIPv4(bytes, 0)
        case 0: // BSD loopback
            guard bytes.count >= 5 else {
                return ("short", "truncated loopback frame", nil)
            }
            return bytes[4] >> 4 == 6 ? decodeIPv6(bytes, 4)
                                      : decodeIPv4(bytes, 4)
        default:
            return ("link \(linktype)",
                    "\(bytes.count) bytes (linktype \(linktype) "
                    + "not decoded)", nil)
        }
    }

    private static func decodeIPv4(_ bytes: [UInt8], _ o: Int)
        -> (proto: String, text: String, preview: String?) {
        guard bytes.count >= o + 20 else {
            return ("IPv4", "truncated IPv4 packet", nil)
        }
        let ihl = Int(bytes[o] & 0x0f) * 4
        guard ihl >= 20, bytes.count >= o + ihl else {
            return ("IPv4", "bad IPv4 header length", nil)
        }
        let total = (Int(bytes[o + 2]) << 8) | Int(bytes[o + 3])
        let protoNum = Int(bytes[o + 9])
        let src = ipv4(bytes[(o + 12)..<(o + 16)])
        let dst = ipv4(bytes[(o + 16)..<(o + 20)])
        // The logical end is the header's total length, not the
        // captured frame: Ethernet padding past it is not data.
        let end = min(bytes.count, o + total)
        return decodeTransport(bytes, protoNum, src, dst,
                               from: o + ihl, to: end, v6: false)
    }

    private static func decodeIPv6(_ bytes: [UInt8], _ o: Int)
        -> (proto: String, text: String, preview: String?) {
        guard bytes.count >= o + 40 else {
            return ("IPv6", "truncated IPv6 packet", nil)
        }
        let payloadLen = (Int(bytes[o + 4]) << 8) | Int(bytes[o + 5])
        let next = Int(bytes[o + 6])
        let src = DNSKit.ipv6(Array(bytes[(o + 8)..<(o + 24)]))
        let dst = DNSKit.ipv6(Array(bytes[(o + 24)..<(o + 40)]))
        // Likewise bounded by the payload length, padding excluded.
        let end = min(bytes.count, o + 40 + payloadLen)
        return decodeTransport(bytes, next, src, dst,
                               from: o + 40, to: end, v6: true)
    }

    private static func decodeTransport(_ bytes: [UInt8], _ protoNum: Int,
                                        _ src: String, _ dst: String,
                                        from: Int, to: Int, v6: Bool)
        -> (proto: String, text: String, preview: String?) {
        let family = v6 ? "IPv6" : "IPv4"
        switch protoNum {
        case 6:
            guard to >= from + 20 else {
                return ("TCP", "\(src) → \(dst) TCP (truncated)", nil)
            }
            let sport = (Int(bytes[from]) << 8) | Int(bytes[from + 1])
            let dport = (Int(bytes[from + 2]) << 8) | Int(bytes[from + 3])
            let headerLen = Int(bytes[from + 12] >> 4) * 4
            let flags = bytes[from + 13]
            var names: [String] = []
            if flags & 0x01 != 0 { names.append("FIN") }
            if flags & 0x02 != 0 { names.append("SYN") }
            if flags & 0x04 != 0 { names.append("RST") }
            if flags & 0x08 != 0 { names.append("PSH") }
            if flags & 0x10 != 0 { names.append("ACK") }
            if flags & 0x20 != 0 { names.append("URG") }
            let payloadStart = from + max(20, headerLen)
            let payload: ArraySlice<UInt8> = payloadStart < to
                ? bytes[payloadStart..<to] : []
            return ("TCP",
                    "\(src):\(sport) → \(dst):\(dport)  TCP "
                    + "[\(names.joined(separator: ","))] "
                    + "len \(payload.count)",
                    preview(of: Data(payload)))
        case 17:
            guard to >= from + 8 else {
                return ("UDP", "\(src) → \(dst) UDP (truncated)", nil)
            }
            let sport = (Int(bytes[from]) << 8) | Int(bytes[from + 1])
            let dport = (Int(bytes[from + 2]) << 8) | Int(bytes[from + 3])
            let payload: ArraySlice<UInt8> = from + 8 < to
                ? bytes[(from + 8)..<to] : []
            return ("UDP",
                    "\(src):\(sport) → \(dst):\(dport)  UDP "
                    + "len \(payload.count)",
                    preview(of: Data(payload)))
        case 1, 58:
            guard to >= from + 2 else {
                return ("ICMP", "\(src) → \(dst) ICMP", nil)
            }
            let type = Int(bytes[from])
            let names = protoNum == 58
                ? [129: "echo reply", 1: "destination unreachable",
                   128: "echo request", 3: "time exceeded"]
                : [0: "echo reply", 3: "destination unreachable",
                   8: "echo request", 11: "time exceeded"]
            return ("ICMP",
                    "\(src) → \(dst)  ICMP "
                    + (names[type] ?? "type \(type)"), nil)
        default:
            return (family,
                    "\(src) → \(dst)  \(family) protocol \(protoNum)",
                    nil)
        }
    }

    private static func decodeARP(_ bytes: [UInt8], _ o: Int)
        -> (proto: String, text: String, preview: String?) {
        guard bytes.count >= o + 8 else {
            return ("ARP", "truncated ARP packet", nil)
        }
        // The fixed offsets below are only the Ethernet/IPv4
        // layout; anything else gets a generic line instead of a
        // confident misdecode.
        let htype = (Int(bytes[o]) << 8) | Int(bytes[o + 1])
        let ptype = (Int(bytes[o + 2]) << 8) | Int(bytes[o + 3])
        guard htype == 1, ptype == 0x0800,
              bytes[o + 4] == 6, bytes[o + 5] == 4 else {
            return ("ARP", "ARP (unusual layout)", nil)
        }
        guard bytes.count >= o + 28 else {
            return ("ARP", "truncated ARP packet", nil)
        }
        let op = (Int(bytes[o + 6]) << 8) | Int(bytes[o + 7])
        let senderIP = ipv4(bytes[(o + 14)..<(o + 18)])
        let senderMAC = mac(Array(bytes[(o + 8)..<(o + 14)]))
        let targetIP = ipv4(bytes[(o + 24)..<(o + 28)])
        if op == 1 {
            return ("ARP", "ARP who-has \(targetIP) tell \(senderIP)", nil)
        }
        if op == 2 {
            return ("ARP", "ARP \(senderIP) is-at \(senderMAC)", nil)
        }
        return ("ARP", "ARP op \(op) \(senderIP) → \(targetIP)", nil)
    }
}

// MARK: - Scan tab

struct ScanView: View {
    static let feedClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @Binding var tab: Int
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var mouth: Mouth
    @StateObject private var model = ScanModel()
    @State private var dossierSheet: DossierPresentation?
    @State private var mapShown = false
    @State private var editingNeighbor: Neighbor?
    @State private var clearNeighborhood = false
    @State private var dossiersOpen = false
    @StateObject private var tls = TLSInspector()
    @StateObject private var dns = DNSModel()
    @State private var host = ""
    @State private var customPorts = ""
    @State private var tlsPort = "443"
    @State private var dnsName = ""
    @State private var dnsType = "A"
    @State private var sweepPort = "80"
    @State private var ssid: String?
    @State private var pcapSummary: [String] = []
    @State private var pcapLines: [String] = []
    @State private var showPcapImporter = false

    private var lanPrefix: String? {
        guard let ip = Mouth.localIPAddress() else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.dropLast().joined(separator: ".")
    }

    /// Unique swept addresses, for the Dossiers section.
    private var sweptIPs: [String] {
        Array(Set(model.sweepHosts.map(\.ip))).sorted()
    }

    /// A swept address presented by its given name when
    /// the Neighborhood knows one — the name follows the
    /// device into every section.
    private func knownName(for ip: String) -> String {
        NeighborhoodStore.shared.neighbors.first {
            $0.ip == ip
        }?.displayName ?? ip
    }

    private func sweptPorts(for ip: String) -> String {
        model.sweepHosts.filter { $0.ip == ip }
            .map { String($0.port) }.joined(separator: ", ")
    }

    private var portsToScan: [Int] {
        // Comma/space separated ports, and ranges: "8000-8010"
        // means the eleven ports, not ports 8000 and 8010.
        var typed: [Int] = []
        for token in customPorts.split(
            whereSeparator: { $0 == "," || $0.isWhitespace }) {
            if token.contains("-") {
                let ends = token.split(separator: "-")
                if ends.count == 2, let lo = Int(ends[0]),
                   let hi = Int(ends[1]), lo >= 1, hi <= 65535,
                   lo <= hi, hi - lo <= 512 {
                    typed.append(contentsOf: lo...hi)
                }
            } else if let port = Int(token) {
                typed.append(port)
            }
        }
        var seen = Set<Int>()
        let unique = typed
            .filter { (1...65535).contains($0) }
            .filter { seen.insert($0).inserted }
        let capped = Array(unique.prefix(1024))
        return capped.isEmpty ? ScanModel.topPorts.map { $0.0 } : capped
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("This network"))) {
                    if let ip = Mouth.localIPAddress(),
                       let prefix = lanPrefix {
                        if let ssid = ssid {
                            HStack {
                                Text(L("Wi-Fi")).foregroundStyle(.secondary)
                                Spacer()
                                Text(ssid)
                            }
                        }
                        HStack {
                            Text(L("Your IP")).foregroundStyle(.secondary)
                            Spacer()
                            Text(ip).font(.body.monospaced())
                        }
                        HStack {
                            Text(L("Subnet")).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(prefix).0/24")
                                .font(.body.monospaced())
                        }
                        Button {
                            Haptics.tap()
                            host = "\(prefix).1"
                            toasts.show(L("Scan target set to the likely gateway"))
                        } label: {
                            HStack {
                                Text(L("Likely gateway"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(prefix).1")
                                    .font(.body.monospaced())
                                Image(systemName: "scope")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(L("Not on Wi-Fi — join a network and the recon tools wake up."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text(L("Target"))) {
                    TextField(L("hostname or IP"), text: $host)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    Text(L("Your own gear, or a network you're engaged to test — the scanner asks politely and reports what answers."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(header: Text(L("Port scan · TCP connect"))) {
                    TextField(L("ports or range (blank = the usual 28)"),
                              text: $customPorts)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    Button {
                        Haptics.tap()
                        model.scan(host: host, ports: portsToScan)
                    } label: {
                        Label(model.scanning
                              ? "Scanning \(model.probedCount)/\(model.totalCount)…"
                              : "Scan \(host.isEmpty ? "target" : host)",
                              systemImage: "scope")
                    }
                    .disabled(model.scanning || model.sweeping
                              || host.isEmpty)
                    ForEach(model.results) { result in
                      Button { handoff(result) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(result.port)")
                                    .font(.body.monospaced().weight(.semibold))
                                Text(result.service)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(L("open"))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                            if let banner = result.banner {
                                Text(String(banner.prefix(160)))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                      }
                      .buttonStyle(.plain)
                    }
                    if !model.results.isEmpty {
                        Text(L("Tap an open port to load it — and the library probe that speaks its language — into the Send tab."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.scanning, model.totalCount > 0,
                       model.results.isEmpty {
                        Text(L("Nothing answered on those ports."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(header: Text(L("Subnet sweep"))) {
                    HStack {
                        Text(L("Port"))
                            .foregroundStyle(.secondary)
                        TextField(L("80"), text: $sweepPort)
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                        Button {
                            Haptics.tap()
                            model.sweep(port: Int(sweepPort) ?? 80)
                        } label: {
                            Label(model.sweeping
                                    ? "Sweeping \(model.sweptCount)/254…"
                                    : "Sweep this /24",
                                  systemImage: "scope")
                        }
                        .disabled(model.sweeping || model.scanning)
                    }
                    ForEach(model.sweepHosts) { found in
                        Button { sweepHandoff(found) } label: {
                            HStack {
                                Text(found.ip)
                                    .font(.body.monospaced())
                                Spacer()
                                Text(String(format: L("%lld open"), found.port))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(L("Knocks on one port across your Wi-Fi's whole /24 (254 addresses, under a minute) and lists who answers. Tap a host to load it into Send; the list also feeds the Send tab's fan-out. Hosts that drop the knock stay invisible — that's connect scanning."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.sweepHosts.isEmpty || !model.discovered.isEmpty {
                    Section(header: Text(L("Dossiers"))) {
                        Button {
                            withAnimation { dossiersOpen.toggle() }
                        } label: {
                            HStack {
                                Label(L("Devices"), systemImage: "folder")
                                Spacer()
                                Text("\(sweptIPs.count + model.discovered.count)")
                                    .foregroundStyle(.secondary)
                                Image(systemName: dossiersOpen
                                      ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                        if dossiersOpen {
                        ForEach(sweptIPs, id: \.self) { ip in
                            Button {
                                dossierSheet = DossierPresentation(
                                    title: knownName(for: ip), ip: ip,
                                    wifiLines: [
                                        "Answered the sweep on port "
                                        + "\(sweptPorts(for: ip))",
                                        "Census: Scan tab subnet sweep",
                                    ])
                            } label: {
                                Label(knownName(for: ip), systemImage: "folder.badge.gearshape")
                            }
                        }
                        ForEach(model.discovered) { service in
                            Button {
                                dossierSheet = DossierPresentation(
                                    title: service.name, ip: nil,
                                    wifiLines: [
                                        "Announces itself via Bonjour: "
                                        + service.label,
                                        "Census: Scan tab discovery sweep",
                                    ])
                            } label: {
                                Label(service.name,
                                      systemImage: "folder.badge.gearshape")
                            }
                        }
                        }
                        Text(L("One page per device, every organ's testimony: what Scan heard, whether Listen has heard the name over Bluetooth, and a Recon knock on demand."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                MapSectionView(model: model, shown: $mapShown)
                NeighborhoodSectionView(
                    store: NeighborhoodStore.shared,
                    editing: $editingNeighbor,
                    dossier: $dossierSheet,
                    clearRequest: $clearNeighborhood)

                Section(header: Text(L("Observation feed"))) {
                    if model.watching {
                        Button(role: .destructive) {
                            Haptics.tap()
                            model.stopWatch()
                            mouth.logRecon(
                                "feed", "watch session",
                                lines: model.feed.reversed()
                                    .map { $0.text })
                        } label: {
                            Label(L("Stop watching"),
                                  systemImage: "eye.slash")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            model.startWatch(port: Int(sweepPort) ?? 80)
                        } label: {
                            Label("Watch this network "
                                  + "(port \(sweepPort))",
                                  systemImage: "eye")
                        }
                        .disabled(model.sweeping || model.scanning)
                    }
                    if !model.feed.isEmpty {
                        Button(L("Clear feed"), role: .destructive) {
                            Haptics.tap()
                            model.clearFeed()
                        }
                        .font(.caption)
                    }
                    ForEach(model.feed) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(Self.feedClock.string(from: event.at))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(event.text)
                                .font(.caption)
                        }
                    }
                    Text(L("While watching, the /24 is re-swept on the sweep port and Bonjour is diffed — joinings, leavings, openings stream in here. Only what this phone can observe itself; nothing is intercepted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(L("TLS certificate"))) {
                    HStack {
                        TextField(L("port"), text: $tlsPort)
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                        Button(L("Inspect")) {
                            Haptics.tap()
                            tls.inspect(host: host,
                                        port: Int(tlsPort) ?? 443)
                        }
                        .disabled(tls.inspecting || host.isEmpty)
                    }
                    ForEach(tls.lines, id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }

                Section(header: Text(L("DNS lookup"))) {
                    HStack {
                        TextField(L("domain"), text: $dnsName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { lookupTapped() }
                        Picker(L("Record"), selection: $dnsType) {
                            ForEach(["A", "AAAA", "MX", "NS", "CNAME",
                                     "TXT"], id: \.self) { type in
                                Text(type).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    Button {
                        lookupTapped()
                    } label: {
                        Label(dns.querying ? "Asking 1.1.1.1…"
                                           : "Look up",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(dns.querying || dnsName.isEmpty)
                    ForEach(dns.lines, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Text(L("A real query over UDP, answers parsed locally — the grown-up version of the library's DNS seed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text(L("On this Wi-Fi · Bonjour"))) {
                    if model.discovered.isEmpty {
                        Text(L("Listening — services appear here as they announce themselves."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.discovered) { service in
                        Button { resolveTapped(service) } label: {
                            HStack {
                                Text(service.name).lineLimit(1)
                                Spacer()
                                Text(service.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "paperplane.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    if !model.discovered.isEmpty {
                        Text(L("Tap a service to resolve it to an address and load it into Send."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text(L("Capture dissector"))) {
                    Text(L("Capture on your own gear — tcpdump -w — then dissect the file here, in plain text, with the app's own decoder. Classic .pcap only, not pcapng."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Haptics.tap()
                        showPcapImporter = true
                    } label: {
                        Label(L("Import a .pcap file"),
                              systemImage: "square.and.arrow.down")
                    }
                    ForEach(pcapSummary, id: \.self) { line in
                        Text(line)
                            .font(.caption.weight(.semibold))
                    }
                    ForEach(Array(pcapLines.enumerated()),
                            id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Text(L("Connect scans only — iOS gives apps no raw sockets, so no SYN scans and no UDP scans. The Send tab is the UDP tool; this tab maps what TCP answers."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle(L("Scan"))
            .onAppear {
                model.startDiscovery()
                NEHotspotNetwork.fetchCurrent { network in
                    DispatchQueue.main.async { ssid = network?.ssid }
                }
            }
            .onDisappear { model.stopDiscovery() }
            .onChange(of: model.scanning) { scanning in
                if !scanning, model.totalCount > 0 {
                    toasts.show(String(format: L("Scan finished — %lld open of %lld"), model.results.count, model.totalCount))
                    // The host the scan actually ran against,
                    // captured at start — not whatever the field
                    // says now.
                    let base = model.lastScannedHost
                    if !model.results.isEmpty {
                        mouth.lastScanTargets = model.results.map {
                            "tcp://\(base):\($0.port)"
                        }
                    }
                    mouth.logRecon("scan", base, lines: model.results.map {
                        "\($0.port) \($0.service)"
                        + ($0.banner.map { " — \($0)" } ?? "")
                    })
                }
            }
            .onAppear {
                // Sweep completion lives in the model now, so a
                // watch-cycle sweep can be told apart from a manual
                // one: only manual sweeps toast, feed the fan-out
                // targets, and write a history entry.
                model.onSweepCompleted = { wasWatch in
                    guard !wasWatch, !model.sweepHosts.isEmpty
                    else { return }
                    toasts.show(String(format: L("Sweep finished — %lld host(s) answer on %lld"), model.sweepHosts.count, sweepPort))
                    mouth.lastScanTargets = model.sweepHosts.map {
                        "tcp://\($0.ip):\($0.port)"
                    }
                    mouth.logRecon("sweep", "port \(sweepPort)",
                                   lines: model.sweepHosts.map {
                                       "\($0.ip):\($0.port) open"
                                   })
                }
            }
            .onChange(of: dns.querying) { querying in
                if !querying, !dns.lines.isEmpty {
                    mouth.logRecon("dns", "\(dnsName) \(dnsType)",
                                   lines: dns.lines)
                }
            }
        }
        .fullScreenCover(isPresented: $mapShown) {
            MapView(model: model)
        }
        .sheet(item: $dossierSheet) { presentation in
            DossierSheetView(presentation: presentation)
        }
        .sheet(item: $editingNeighbor) { neighbor in
            NeighborNameEditor(
                store: NeighborhoodStore.shared,
                neighbor: neighbor)
        }
        .confirmationDialog(
            "Clear the Neighborhood?",
            isPresented: $clearNeighborhood,
            titleVisibility: .visible) {
            Button(L("Forget every neighbor"),
                   role: .destructive) {
                NeighborhoodStore.shared.clear()
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("Every device the house has learned — names, marks, drift and all — is forgotten, and their Map placements with them. The wire will populate its own cast again."))
        }
        .fileImporter(isPresented: $showPcapImporter,
                      allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource()
            else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url),
                  let decoded = PcapKit.dissect(
                    data, name: url.lastPathComponent) else {
                toasts.show(L("That file is not a libpcap capture"),
                            error: true)
                return
            }
            pcapSummary = decoded.summary
            pcapLines = decoded.lines
            mouth.logRecon("pcap", url.lastPathComponent,
                           lines: decoded.summary
                                  + Array(decoded.lines.prefix(100)))
            toasts.show(String(format: L("Dissected %@"), url.lastPathComponent))
        }
    }

    private func handoff(_ result: PortResult) {
        Haptics.select()
        let base = model.lastScannedHost.isEmpty
            ? host.trimmingCharacters(in: .whitespaces)
            : model.lastScannedHost
        mouth.scanHandoffTarget = "tcp://\(base):\(result.port)"
        mouth.scanHandoffPayload = ScanModel.payloadByPort[result.port]
        tab = 1
    }

    private func resolveTapped(_ service: DiscoveredService) {
        Haptics.select()
        model.resolve(service) { resolved in
            DispatchQueue.main.async {
                guard let resolved = resolved else {
                    toasts.show(String(format: L("Could not resolve %@"), service.name),
                                error: true)
                    return
                }
                let ip = resolved.0
                let port = resolved.1
                // A tcp:// URL needs an IPv6 literal bracketed.
                let target = ip.contains(":") && !ip.hasPrefix("[")
                    ? "[\(ip)]" : ip
                mouth.scanHandoffTarget = "tcp://\(target):\(port)"
                mouth.scanHandoffPayload =
                    ScanModel.payloadByPort[port]
                tab = 1
            }
        }
    }

    private func sweepHandoff(_ found: SweepHost) {
        Haptics.select()
        mouth.scanHandoffTarget = "tcp://\(found.ip):\(found.port)"
        mouth.scanHandoffPayload = ScanModel.payloadByPort[found.port]
        tab = 1
    }

    private func lookupTapped() {
        Haptics.tap()
        dns.lookup(name: dnsName, typeName: dnsType)
    }
}
