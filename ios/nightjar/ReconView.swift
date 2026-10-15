import Foundation
import Network
import NetworkExtension
import Security
import SwiftUI

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

    private static let httpPorts: Set<Int> = [80, 8000, 8080, 8443, 8888, 9200]

    private let queue = DispatchQueue(label: "nightjar-scan",
                                      attributes: .concurrent)
    private let lock = NSLock()
    private var browsers: [NWBrowser] = []

    func scan(host: String, ports: [Int]) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !scanning, !ports.isEmpty else { return }
        scanning = true
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
        }
    }

    private func probe(host: String, port: Int,
                       done: @escaping (PortResult?) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port))
        else { done(nil); return }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let finishLock = NSLock()
        var finished = false
        let finish: (PortResult?) -> Void = { result in
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            done(result)
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                let service = ScanModel.serviceNames[port] ?? ""
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
                    // Answers that say nothing still count as open.
                    self.queue.asyncAfter(deadline: .now() + 1.2) {
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
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2.5) { finish(nil) }
    }

    // MARK: Subnet sweep

    /// Host discovery: knock on one port across the phone's whole
    /// Wi-Fi /24 and list whoever answers. Connect-only, like the
    /// port scan — a host with that port closed or firewalled to
    /// drops stays invisible, and the UI says so.
    func sweep(port: Int) {
        guard !sweeping, !scanning,
              let own = Mouth.localIPAddress() else { return }
        let parts = own.split(separator: ".")
        guard parts.count == 4 else { return }
        let prefix = parts.dropLast().joined(separator: ".") + "."
        sweeping = true
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
            self?.sweepHosts = found.sorted { $0.octet < $1.octet }
            self?.sweeping = false
        }
    }

    private func sweepProbe(host: String, port: Int,
                            done: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port))
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
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1.0) { finish(false) }
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
        completionHandler(.useCredential, URLCredential(trust: trust))
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
        return "\(from.formatted(date: .abbreviated, time: .omitted)) → "
            + to.formatted(date: .abbreviated, time: .omitted)
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
        var data = Data()
        let id = UInt16.random(in: 0...UInt16.max)
        data.append(UInt8(id >> 8))
        data.append(UInt8(id & 0xff))
        data.append(contentsOf: [0x01, 0x00])              // RD
        data.append(contentsOf: [0x00, 0x01])              // QDCOUNT 1
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        for label in name.split(separator: ".") where !label.isEmpty {
            data.append(UInt8(clamping: label.count))
            data.append(contentsOf: label.utf8)
        }
        data.append(0)
        data.append(UInt8(type >> 8))
        data.append(UInt8(type & 0xff))
        data.append(contentsOf: [0x00, 0x01])              // IN
        return data
    }

    static func readName(_ data: Data, _ offset: inout Int) -> String {
        var labels: [String] = []
        var pos = offset
        var next = offset
        var jumped = false
        var steps = 0
        while pos < data.count, steps < 128 {
            steps += 1
            let len = Int(data[pos])
            if len == 0 {
                if !jumped { next = pos + 1 }
                break
            }
            if len & 0xC0 == 0xC0, pos + 1 < data.count {
                if !jumped { next = pos + 2 }
                jumped = true
                pos = ((len & 0x3F) << 8) | Int(data[pos + 1])
                continue
            }
            let end = pos + 1 + len
            guard end <= data.count else { break }
            labels.append(String(decoding: data[(pos + 1)..<end],
                                 as: UTF8.self))
            pos = end
            if !jumped { next = end }
        }
        offset = next
        return labels.joined(separator: ".")
    }

    static func parseAnswers(_ data: Data) -> [String] {
        func u16(_ i: Int) -> Int { (Int(data[i]) << 8) | Int(data[i + 1]) }
        func u32(_ i: Int) -> Int { (u16(i) << 16) | u16(i + 2) }
        guard data.count >= 12 else { return ["short response"] }
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
            return readName(data, &off)
        case 15:
            guard bytes.count > 2 else { return "?" }
            let pref = (Int(bytes[0]) << 8) | Int(bytes[1])
            var off = start + 2
            return "\(pref) \(readName(data, &off))"
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

    private static func ipv6(_ bytes: [UInt8]) -> String {
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
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: DNSKit.buildQuery(name: trimmed, type: code),
                    completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 12,
                                           maximumLength: 4096) {
                            data, _, _, error in
                            if let data = data, data.count >= 12 {
                                finish(DNSKit.parseAnswers(data))
                            } else {
                                finish(["no answer ("
                                        + (error?.localizedDescription
                                           ?? "empty reply") + ")"])
                            }
                        }
                    })
            case .failed(let error):
                finish(["query failed: \(error.localizedDescription)"])
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "nightjar-dns"))
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            finish(["timed out — no answer from 1.1.1.1"])
        }
    }
}

// MARK: - Scan tab

struct ScanView: View {
    @Binding var tab: Int
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var mouth: Mouth
    @StateObject private var model = ScanModel()
    @StateObject private var tls = TLSInspector()
    @StateObject private var dns = DNSModel()
    @State private var host = ""
    @State private var customPorts = ""
    @State private var tlsPort = "443"
    @State private var dnsName = ""
    @State private var dnsType = "A"
    @State private var sweepPort = "80"
    @State private var ssid: String?

    private var lanPrefix: String? {
        guard let ip = Mouth.localIPAddress() else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts.dropLast().joined(separator: ".")
    }

    private var portsToScan: [Int] {
        let typed = customPorts
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .filter { (1...65535).contains($0) }
        var seen = Set<Int>()
        let unique = typed.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ScanModel.topPorts.map { $0.0 } : unique
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("This network")) {
                    if let ip = Mouth.localIPAddress(),
                       let prefix = lanPrefix {
                        if let ssid = ssid {
                            HStack {
                                Text("Wi-Fi").foregroundStyle(.secondary)
                                Spacer()
                                Text(ssid)
                            }
                        }
                        HStack {
                            Text("Your IP").foregroundStyle(.secondary)
                            Spacer()
                            Text(ip).font(.body.monospaced())
                        }
                        HStack {
                            Text("Subnet").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(prefix).0/24")
                                .font(.body.monospaced())
                        }
                        Button {
                            Haptics.tap()
                            host = "\(prefix).1"
                            toasts.show("Scan target set to the "
                                        + "likely gateway")
                        } label: {
                            HStack {
                                Text("Likely gateway")
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
                        Text("Not on Wi-Fi — join a network and the "
                             + "recon tools wake up.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Target")) {
                    TextField("hostname or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    Text("Your own gear, or a network you're engaged "
                         + "to test — the scanner asks politely and "
                         + "reports what answers.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(header: Text("Port scan · TCP connect")) {
                    TextField("ports (blank = the usual 28)",
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
                    .disabled(model.scanning || host.isEmpty)
                    ForEach(model.results) { result in
                      Button { handoff(result) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(result.port)")
                                    .font(.body.monospaced().weight(.semibold))
                                Text(result.service)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("open")
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
                        Text("Tap an open port to load it — and the "
                             + "library probe that speaks its language — "
                             + "into the Send tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.scanning, model.totalCount > 0,
                       model.results.isEmpty {
                        Text("Nothing answered on those ports.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Subnet sweep")) {
                    HStack {
                        Text("Port")
                            .foregroundStyle(.secondary)
                        TextField("80", text: $sweepPort)
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                        Button {
                            Haptics.tap()
                            model.sweep(port: Int(sweepPort) ?? 80)
                        } label: {
                            Label(model.sweeping
                                    ? "Sweeping \(model.sweptCount)/254…"
                                    : "Sweep this /24",
                                  systemImage: "radar")
                        }
                        .disabled(model.sweeping || model.scanning)
                    }
                    ForEach(model.sweepHosts) { found in
                        Button { sweepHandoff(found) } label: {
                            HStack {
                                Text(found.ip)
                                    .font(.body.monospaced())
                                Spacer()
                                Text("\(found.port) open")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Knocks on one port across your Wi-Fi's whole "
                         + "/24 (254 addresses, under a minute) and "
                         + "lists who answers. Tap a host to load it "
                         + "into Send; the list also feeds the Send "
                         + "tab's fan-out. Hosts that drop the knock "
                         + "stay invisible — that's connect scanning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("TLS certificate")) {
                    HStack {
                        TextField("port", text: $tlsPort)
                            .keyboardType(.numberPad)
                            .font(.body.monospaced())
                        Button("Inspect") {
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

                Section(header: Text("DNS lookup")) {
                    HStack {
                        TextField("domain", text: $dnsName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { lookupTapped() }
                        Picker("Record", selection: $dnsType) {
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
                    Text("A real query over UDP, answers parsed "
                         + "locally — the grown-up version of the "
                         + "library's DNS seed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(header: Text("On this Wi-Fi · Bonjour")) {
                    if model.discovered.isEmpty {
                        Text("Listening — services appear here as "
                             + "they announce themselves.")
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
                        Text("Tap a service to resolve it to an "
                             + "address and load it into Send.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("Connect scans only — iOS gives apps no raw "
                         + "sockets, so no SYN scans and no UDP scans. "
                         + "The Send tab is the UDP tool; this tab "
                         + "maps what TCP answers.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Scan")
            .onAppear {
                model.startDiscovery()
                NEHotspotNetwork.fetchCurrent { network in
                    DispatchQueue.main.async { ssid = network?.ssid }
                }
            }
            .onDisappear { model.stopDiscovery() }
            .onChange(of: model.scanning) { scanning in
                if !scanning, model.totalCount > 0 {
                    toasts.show("Scan finished — \(model.results.count) "
                                + "open of \(model.totalCount)")
                    let base = host.trimmingCharacters(in: .whitespaces)
                    mouth.lastScanTargets = model.results.map {
                        "tcp://\(base):\($0.port)"
                    }
                    mouth.logRecon("scan", base, lines: model.results.map {
                        "\($0.port) \($0.service)"
                        + ($0.banner.map { " — \($0)" } ?? "")
                    })
                }
            }
            .onChange(of: model.sweeping) { sweeping in
                if !sweeping, !model.sweepHosts.isEmpty {
                    toasts.show("Sweep finished — "
                                + "\(model.sweepHosts.count) host(s) "
                                + "answer on \(sweepPort)")
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
    }

    private func handoff(_ result: PortResult) {
        Haptics.select()
        mouth.scanHandoffTarget =
            "tcp://\(host.trimmingCharacters(in: .whitespaces)):"
            + "\(result.port)"
        mouth.scanHandoffPayload = ScanModel.payloadByPort[result.port]
        tab = 1
    }

    private func resolveTapped(_ service: DiscoveredService) {
        Haptics.select()
        model.resolve(service) { resolved in
            DispatchQueue.main.async {
                guard let resolved = resolved else {
                    toasts.show("Could not resolve \(service.name)",
                                error: true)
                    return
                }
                let ip = resolved.0
                let port = resolved.1
                mouth.scanHandoffTarget = "tcp://\(ip):\(port)"
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
