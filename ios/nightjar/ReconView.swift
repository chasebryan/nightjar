import Foundation
import Network
import Security
import SwiftUI

// MARK: - Connect scanner + Bonjour sweep

struct PortResult: Identifiable {
    var id: Int { port }
    let port: Int
    let service: String
    var banner: String?
}

struct DiscoveredService: Identifiable {
    let id = UUID()
    let type: String
    let label: String
    let name: String
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
                                                 name: name)
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
        let session = URLSession(configuration: .ephemeral,
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

// MARK: - Scan tab

struct ScanView: View {
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var model = ScanModel()
    @StateObject private var tls = TLSInspector()
    @State private var host = ""
    @State private var customPorts = ""
    @State private var tlsPort = "443"

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
                    }
                    if !model.scanning, model.totalCount > 0,
                       model.results.isEmpty {
                        Text("Nothing answered on those ports.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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

                Section(header: Text("On this Wi-Fi · Bonjour")) {
                    if model.discovered.isEmpty {
                        Text("Listening — services appear here as "
                             + "they announce themselves.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.discovered) { service in
                        HStack {
                            Text(service.name).lineLimit(1)
                            Spacer()
                            Text(service.label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
            .navigationTitle("Scan")
            .onAppear { model.startDiscovery() }
            .onDisappear { model.stopDiscovery() }
            .onChange(of: model.scanning) { scanning in
                if !scanning, model.totalCount > 0 {
                    toasts.show("Scan finished — \(model.results.count) "
                                + "open of \(model.totalCount)")
                }
            }
        }
    }
}
