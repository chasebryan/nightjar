import Combine
import Foundation
import Network
import UIKit

/// EMCON — emissions control. The defensive half of nightjar-hack:
/// turn the app's own instruments inward so the operator can see
/// (and shut down) what this device announces to the network, and
/// hear anyone who comes probing with the same techniques.
///
///  - Exposure score: a single number for how visible this device
///    is right now, computed from live emissions, the broadcast
///    name, the last self-recon and the last Bonjour audit.
///  - Self-recon: knock this device with Recon's own probe registry
///    and itemize what answers — the view another operator gets.
///  - Bonjour audit: browse the LAN the way the Scan tab does and
///    flag every announcement that is this device — mDNS is the
///    loudest identifier on the network and it speaks the device's
///    name.
///  - Silence: one switch forces Serve stealth, disarms the BLE
///    GATT host and stops the BLE beacon. EMCON never re-opens an
///    emission on its own; turning EMCON off leaves stealth as it
///    finds it.
///  - Tripwire: quiet listeners on the probe ports, TCP and UDP.
///    The probes are wire-exact, which makes them fingerprintable —
///    a knock with this app's own first words is recognized and
///    logged with its source, as are the generic scanner shapes
///    (TLS ClientHello, SSH banners, HTTP request lines). The log
///    persists across launches. The tripwire never replies.
///  - The drill: scan, go dark, scan again, and show the delta.
///
/// Honest limit, also stated in the UI: nothing at the app layer can
/// hide the device from the access point it is associated with, and
/// Apple's own radios answer to Settings, not to this app. EMCON
/// strips what identifies the device and turns probing into an
/// announcement by the prober.
final class Emcon: ObservableObject {

    struct Exposure: Identifiable {
        var id: String { "\(host):\(port)" }
        let host: String
        let port: Int
        let service: String
        let banner: String
        let confirmed: Bool
    }

    struct Announcer: Identifiable {
        var id: String { "\(type)|\(name)" }
        let type: String
        let label: String
        let name: String
        let why: String
    }

    struct TripEvent: Identifiable, Codable {
        var id: String = UUID().uuidString
        let when: Date
        let source: String
        let port: Int
        let proto: String
        let verdict: String
        let byteCount: Int
    }

    struct Snapshot {
        var exposures: [Exposure] = []
        var announcers: [Announcer] = []
    }

    @Published private(set) var active: Bool
    @Published private(set) var scanning = false
    @Published private(set) var exposures: [Exposure] = []
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var auditing = false
    @Published private(set) var announcers: [Announcer] = []
    @Published private(set) var heardCount = 0
    @Published private(set) var lastAuditAt: Date?
    @Published private(set) var drilling = false
    @Published private(set) var drillBefore: Snapshot?
    @Published private(set) var drillAfter: Snapshot?
    @Published private(set) var tripwireOn = false
    @Published private(set) var watched: [Int] = []
    @Published private(set) var watchedUDP: [Int] = []
    @Published private(set) var unwatched: [Int] = []
    @Published private(set) var events: [TripEvent] = []

    private var listeners: [NWListener] = []
    private var sweep: BonjourSweep?
    private let tripQueue = DispatchQueue(label: "nightjar.emcon.tripwire")
    private let saveQueue = DispatchQueue(label: "nightjar.emcon.save")
    private static let activeKey = "emconActive"
    private static let homeKey = "emconHomeSubnet"

    init() {
        active = UserDefaults.standard.bool(forKey: Self.activeKey)
        events = Self.loadEvents()
    }

    var deviceName: String { UIDevice.current.name }
    var ownIP: String? { Mouth.localIPAddress() }

    // MARK: - exposure score

    /// 0 = ghost, 100 = a lighthouse. Computed from what is true
    /// right now, not from intentions: live emissions weigh most,
    /// then what the last recon and audit actually found.
    static func score(gattHostOn: Bool, beaconOn: Bool,
                      serveRunning: Bool, stealth: Bool,
                      deviceName: String,
                      exposureCount: Int,
                      announcerCount: Int) -> (value: Int, band: String) {
        var value = 0
        if gattHostOn { value += 25 }
        if beaconOn { value += 20 }
        if serveRunning { value += stealth ? 4 : 20 }
        if deviceName.contains("\u{2019}s ") || deviceName.contains("'s ") {
            value += 12
        } else if deviceName != "iPhone" {
            value += 6
        }
        value += min(20, exposureCount * 4)
        value += min(18, announcerCount * 6)
        let band: String
        switch value {
        case 0: band = "GHOST"
        case 1...15: band = "DARK"
        case 16...40: band = "LIT"
        case 41...70: band = "LOUD"
        default: band = "BEACONING"
        }
        return (min(100, value), band)
    }

    // MARK: - home turf

    var homeSubnet: String? {
        UserDefaults.standard.string(forKey: Self.homeKey)
    }

    var currentSubnet: String? {
        guard let ip = ownIP else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".")
    }

    /// Away = on a network that is not the marked home subnet.
    var isAway: Bool {
        guard let home = homeSubnet, let here = currentSubnet
        else { return false }
        return home != here
    }

    func markHome() {
        if let here = currentSubnet {
            UserDefaults.standard.set(here, forKey: Self.homeKey)
        }
    }

    // MARK: - posture

    /// Go dark: silence every emission the app controls and arm the
    /// tripwire. Serve listeners keep running if they were running,
    /// but under stealth — unlisted, silent arrivals.
    func activate(mouth: Mouth) {
        active = true
        UserDefaults.standard.set(true, forKey: Self.activeKey)
        mouth.setStealth(true)
        if mouth.gattHostOn { mouth.stopGattHost() }
        if mouth.beaconOn { mouth.stopBeacon() }
        startTripwire()
    }

    /// Stand down the tripwire. Stealth, the GATT host and the
    /// beacon are left exactly as they are — re-arming an emission
    /// is always a deliberate act in its own tab.
    func deactivate() {
        active = false
        UserDefaults.standard.set(false, forKey: Self.activeKey)
        stopTripwire()
    }

    /// On tab appearance after a relaunch: if EMCON was left active,
    /// re-arm the tripwire so the posture survives restarts the way
    /// the GATT host arm does.
    func restoreIfNeeded() {
        if active, !tripwireOn { startTripwire() }
    }

    // MARK: - self-recon

    /// Knock this device on every port in Recon's registry, over
    /// both loopback and the LAN address, speaking each port's own
    /// probe. Whatever answers is what another operator sees.
    func runSelfScan(completion: (() -> Void)? = nil) {
        guard !scanning else { completion?(); return }
        scanning = true
        exposures = []
        var hosts = ["127.0.0.1"]
        if let ip = ownIP, ip != "127.0.0.1" { hosts.append(ip) }
        let ports = ReconPayloads.defaultPorts
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 24)
        let lock = NSLock()
        var found: [Exposure] = []
        for host in hosts {
            for port in ports {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    semaphore.wait()
                    Self.probe(host: host, port: port) { exposure in
                        if let exposure = exposure {
                            lock.lock()
                            found.append(exposure)
                            lock.unlock()
                        }
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { completion?(); return }
            self.exposures = found.sorted {
                ($0.host, $0.port) < ($1.host, $1.port)
            }
            self.lastScanAt = Date()
            self.scanning = false
            completion?()
        }
    }

    /// One connect + optional probe + banner read against a single
    /// host:port, Recon's exchange discipline at a shorter fuse.
    private static func probe(host: String, port: Int,
                              done: @escaping (Exposure?) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            done(nil)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "nightjar.emcon.selfscan")
        var finished = false
        let lock = NSLock()
        func finish(_ result: Exposure?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            done(result)
        }
        let probe = ReconPayloads.probe(forPort: port, udp: false)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let probe = probe else {
                    finish(Exposure(host: host, port: port,
                                    service: "open", banner: "",
                                    confirmed: false))
                    return
                }
                connection.send(content: probe.build(),
                                completion: .contentProcessed { _ in
                    connection.receive(minimumIncompleteLength: 1,
                                       maximumLength: 4096) {
                        data, _, _, _ in
                        let reply = data ?? Data()
                        let confirmed = probe.hint.isEmpty
                            ? !reply.isEmpty
                            : reply.range(of: probe.hint) != nil
                        finish(Exposure(
                            host: host, port: port,
                            service: probe.name,
                            banner: ReconPayloads.firstLine(
                                reply, limit: 80),
                            confirmed: confirmed))
                    }
                })
                queue.asyncAfter(deadline: .now() + 1.2) {
                    finish(Exposure(host: host, port: port,
                                    service: probe.name, banner: "",
                                    confirmed: false))
                }
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 0.9) {
            // Still not ready after the connect fuse: nothing there.
            // (If it became ready, the read fuse governs instead.)
            lock.lock()
            let doneAlready = finished
            lock.unlock()
            if !doneAlready, connection.state != .ready { finish(nil) }
        }
    }

    // MARK: - Bonjour audit

    static let auditTypes: [(String, String)] =
        ScanModel.serviceTypes + [
            ("_rair._tcp", "AirPlay audio"),
            ("_companion-link._tcp", "Companion Link"),
            ("_rdlink._tcp", "Rapport"),
            ("_sleep-proxy._udp", "Sleep proxy"),
            ("_airdrop._tcp", "AirDrop"),
        ]

    /// Browse the LAN for three seconds, then decide which of the
    /// announcers is this device: the announcement carries the
    /// device's name, or the service resolves to this phone's
    /// address.
    func runBonjourAudit(completion: (() -> Void)? = nil) {
        guard !auditing else { completion?(); return }
        auditing = true
        announcers = []
        let sweep = BonjourSweep(types: Self.auditTypes)
        self.sweep = sweep
        sweep.run(for: 3) { [weak self] heard in
            guard let self = self else { completion?(); return }
            self.resolveAnnouncers(heard: heard) {
                self.lastAuditAt = Date()
                self.auditing = false
                self.sweep = nil
                completion?()
            }
        }
    }

    private func resolveAnnouncers(
        heard: [(type: String, label: String, name: String,
                 endpoint: NWEndpoint)],
        completion: @escaping () -> Void
    ) {
        let heardTotal = heard.count
        let name = deviceName.lowercased()
        let group = DispatchGroup()
        let lock = NSLock()
        var mine: [Announcer] = []
        for item in heard.prefix(40) {
            let nameHit = item.name.lowercased() == name
                || item.name.lowercased().contains(name)
            group.enter()
            Self.resolveIP(item.endpoint) { [weak self] ip in
                let ipHit = ip != nil && ip == self?.ownIP
                if nameHit || ipHit {
                    lock.lock()
                    mine.append(Announcer(
                        type: item.type, label: item.label,
                        name: item.name,
                        why: nameHit
                            ? "announced under this device's name"
                            : "resolves to this phone's address"))
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.heardCount = heardTotal
            self?.announcers = mine.sorted {
                ($0.label, $0.name) < ($1.label, $1.name)
            }
            completion()
        }
    }

    /// Resolve a Bonjour endpoint to its IP the way ScanModel does:
    /// open one connection and read where it landed.
    private static func resolveIP(_ endpoint: NWEndpoint,
                                  done: @escaping (String?) -> Void) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "nightjar.emcon.resolve")
        var finished = false
        let lock = NSLock()
        func finish(_ ip: String?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            done(ip)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let path = connection.currentPath,
                   case .hostPort(let host, _) = path.remoteEndpoint {
                    finish("\(host)")
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
        queue.asyncAfter(deadline: .now() + 1.2) { finish(nil) }
    }

    // MARK: - the drill

    /// Scan and audit, go dark, scan and audit again. The two
    /// snapshots land in drillBefore / drillAfter for the delta view.
    func runDrill(mouth: Mouth) {
        guard !drilling, !scanning, !auditing else { return }
        drilling = true
        drillBefore = nil
        drillAfter = nil
        runSelfScan { [weak self] in
            guard let self = self else { return }
            self.runBonjourAudit {
                self.drillBefore = Snapshot(exposures: self.exposures,
                                            announcers: self.announcers)
                self.activate(mouth: mouth)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.runSelfScan {
                        self.runBonjourAudit {
                            self.drillAfter = Snapshot(
                                exposures: self.exposures,
                                announcers: self.announcers)
                            self.drilling = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - tripwire

    /// Bind silent listeners on the probe registry's ports — TCP
    /// and UDP. Ports already in use (Serve, the OS) are reported
    /// as unwatched rather than fought over.
    func startTripwire() {
        guard !tripwireOn else { return }
        var bound: [Int] = []
        var boundUDP: [Int] = []
        var failed: [Int] = []
        for port in ReconPayloads.defaultPorts {
            if bind(port: port, udp: false) { bound.append(port) }
            else { failed.append(port) }
        }
        for port in ReconPayloads.udpPortMap.keys.sorted() {
            if bind(port: port, udp: true) { boundUDP.append(port) }
            else { failed.append(port) }
        }
        watched = bound
        watchedUDP = boundUDP
        unwatched = failed
        tripwireOn = true
    }

    private func bind(port: Int, udp: Bool) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
        else { return false }
        do {
            let listener = try NWListener(using: udp ? .udp : .tcp,
                                          on: nwPort)
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleTrip(conn, port: port, udp: udp)
            }
            listener.start(queue: tripQueue)
            listeners.append(listener)
            return true
        } catch {
            return false
        }
    }

    func stopTripwire() {
        for listener in listeners { listener.cancel() }
        listeners = []
        watched = []
        watchedUDP = []
        unwatched = []
        tripwireOn = false
    }

    func clearEvents() {
        events = []
        saveEvents()
    }

    private func handleTrip(_ connection: NWConnection, port: Int,
                            udp: Bool) {
        let source: String
        if case .hostPort(let host, _) = connection.endpoint {
            source = host.debugDescription
        } else {
            source = "unknown"
        }
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: tripQueue)
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: 1024) { [weak self] data, _, _, _ in
            let bytes = data ?? Data()
            let verdict = Self.fingerprint(bytes, port: port, udp: udp)
            connection.cancel()
            self?.logEvent(source: source, port: port,
                           proto: udp ? "UDP" : "TCP",
                           verdict: verdict, byteCount: bytes.count)
        }
        // A connection that sends nothing still counts: someone
        // knocked and waited. Log it after a short grace period if
        // no bytes arrived (the receive above simply never fires).
        tripQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            if connection.state == .ready {
                connection.cancel()
                self.logEvent(source: source, port: port,
                              proto: udp ? "UDP" : "TCP",
                              verdict: "silent knock (no bytes sent)",
                              byteCount: 0)
            }
        }
    }

    private func logEvent(source: String, port: Int, proto: String,
                          verdict: String, byteCount: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let mine = self.ownIP != nil && source.contains(self.ownIP!)
            self.events.insert(
                TripEvent(when: Date(),
                          source: mine ? "\(source) (this device)"
                                       : source,
                          port: port, proto: proto, verdict: verdict,
                          byteCount: byteCount),
                at: 0)
            if self.events.count > 200 {
                self.events.removeLast(self.events.count - 200)
            }
            self.saveEvents()
        }
    }

    // MARK: - tripwire log persistence

    private static var eventsURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("emcon-tripwire.json")
    }

    private static func loadEvents() -> [TripEvent] {
        guard let data = try? Data(contentsOf: eventsURL),
              let decoded = try? JSONDecoder().decode([TripEvent].self,
                                                      from: data)
        else { return [] }
        return decoded
    }

    private func saveEvents() {
        let snapshot = events
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot)
            else { return }
            try? data.write(to: Self.eventsURL, options: .atomic)
        }
    }

    // MARK: - fingerprinting

    /// Probe signatures, built once. The builders are deterministic,
    /// so a byte stream matching a builder's output — in either
    /// direction, to allow for partial sends — is that probe.
    private static let signatures: [(name: String, port: Int,
                                     udp: Bool, bytes: Data)] =
        ReconPayloads.all.values.map {
            (name: $0.name, port: $0.port, udp: $0.udp, bytes: $0.build())
        }

    private static func fingerprint(_ data: Data, port: Int,
                                    udp: Bool) -> String {
        guard !data.isEmpty else { return "empty connection" }
        for sig in signatures where sig.bytes.count >= 3 {
            if data.hasPrefix(sig.bytes) || sig.bytes.hasPrefix(data) {
                var verdict = "nightjar-hack probe: \(sig.name)"
                if sig.port != port {
                    verdict += " (on the wrong port)"
                } else if sig.udp != udp {
                    verdict += " (a \(sig.udp ? "UDP" : "TCP") probe "
                        + "over \(udp ? "UDP" : "TCP"))"
                }
                return verdict
            }
        }
        if data.count >= 2, data[0] == 0x16, data[1] == 0x03 {
            return "TLS ClientHello — a TLS scanner or client knocked"
        }
        if data.hasPrefix(Data("SSH-2.0-".utf8)) {
            let line = ReconPayloads.firstLine(data, limit: 60)
            return "SSH client banner: \(line)"
        }
        for verb in ["GET ", "POST ", "HEAD ", "PUT ", "DELETE ",
                     "OPTIONS ", "CONNECT "] {
            if data.hasPrefix(Data(verb.utf8)) {
                let line = ReconPayloads.firstLine(data, limit: 60)
                return "HTTP request: \(line)"
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        let printable = text.split(whereSeparator: {
            $0 == "\n" || $0 == "\r"
        }).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
        }
        let line = ReconPayloads.firstLine(data, limit: 60)
        return printable
            ? "unrecognized probe: \(line)"
            : "unrecognized bytes (\(data.count)): \(line)"
    }
}

/// A three-second Bonjour sweep over a fixed type list, mirroring
/// ScanModel's NWBrowser discipline. Collects (type, label, name,
/// endpoint) for everything heard, then stops.
private final class BonjourSweep {
    private var browsers: [NWBrowser] = []
    private let lock = NSLock()
    private var heard: [(type: String, label: String, name: String,
                         endpoint: NWEndpoint)] = []
    private let types: [(String, String)]

    init(types: [(String, String)]) { self.types = types }

    func run(for seconds: TimeInterval,
             done: @escaping ([(type: String, label: String,
                                name: String,
                                endpoint: NWEndpoint)]) -> Void) {
        let queue = DispatchQueue(label: "nightjar.emcon.bonjour")
        for (type, label) in types {
            let browser = NWBrowser(
                for: .bonjour(type: type, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                guard let self = self else { return }
                self.lock.lock()
                self.heard.removeAll { $0.type == type }
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.heard.append((type: type, label: label,
                                           name: name,
                                           endpoint: result.endpoint))
                    }
                }
                self.lock.unlock()
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { done([]); return }
            for browser in self.browsers { browser.cancel() }
            self.browsers = []
            self.lock.lock()
            let out = self.heard
            self.lock.unlock()
            done(out)
        }
    }
}
