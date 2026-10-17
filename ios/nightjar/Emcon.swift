import Combine
import Foundation
import Network
import UIKit
import UserNotifications

/// EMCON — emissions control. The defensive half of nightjar-hack:
/// turn the app's own instruments inward so the operator can see
/// (and shut down) what this device announces to the network, and
/// hear anyone who comes probing with the same techniques.
///
///  - Exposure score: a single number for how visible this device
///    is right now, plus the weights that produced it, computed
///    from live emissions, the broadcast name, the last self-recon
///    and the last Bonjour audit.
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
///    (TLS ClientHello, SSH banners, HTTP request lines). A knock
///    is logged once — late bytes beat the silent-knock timer —
///    and a burst from the same source and port collapses into
///    one row. The log persists across launches and can be shared.
///    The tripwire never replies.
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

    struct TripEvent: Identifiable, Codable, Equatable {
        var id: String
        var when: Date
        var source: String
        var port: Int
        var proto: String
        var verdict: String
        var byteCount: Int
        /// Identical knocks folded into this row. Old logs omit it.
        var repeatCount: Int
        /// The knock's actual first words, hex — kept so the
        /// self-sparring loop can replay and mutate REAL captured
        /// probes against the app's own Serve. Old logs omit it.
        var bytesHex: String?

        init(id: String = UUID().uuidString, when: Date, source: String,
             port: Int, proto: String, verdict: String, byteCount: Int,
             repeatCount: Int = 1, bytesHex: String? = nil) {
            self.id = id
            self.when = when
            self.source = source
            self.port = port
            self.proto = proto
            self.verdict = verdict
            self.byteCount = byteCount
            self.repeatCount = repeatCount
            self.bytesHex = bytesHex
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
                ?? UUID().uuidString
            when = try c.decode(Date.self, forKey: .when)
            source = try c.decode(String.self, forKey: .source)
            port = try c.decode(Int.self, forKey: .port)
            proto = try c.decode(String.self, forKey: .proto)
            verdict = try c.decode(String.self, forKey: .verdict)
            byteCount = try c.decode(Int.self, forKey: .byteCount)
            repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
            bytesHex = try c.decodeIfPresent(String.self, forKey: .bytesHex)
        }

        private enum CodingKeys: String, CodingKey {
            case id, when, source, port, proto, verdict, byteCount, repeatCount, bytesHex
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(when, forKey: .when)
            try c.encode(source, forKey: .source)
            try c.encode(port, forKey: .port)
            try c.encode(proto, forKey: .proto)
            try c.encode(verdict, forKey: .verdict)
            try c.encode(byteCount, forKey: .byteCount)
            try c.encode(repeatCount, forKey: .repeatCount)
            try c.encodeIfPresent(bytesHex, forKey: .bytesHex)
        }
    }

    /// Exposure score with the weights that produced it. `value` is
    /// capped at 100; `parts` are the raw contributions, zeros omitted.
    struct Score: Equatable {
        struct Part: Identifiable, Equatable {
            let label: String
            let points: Int
            var id: String { label }
        }
        let value: Int
        let band: String
        let parts: [Part]
        var raw: Int { parts.reduce(0) { $0 + $1.points } }
        var capped: Bool { raw > value }
    }

    struct Snapshot {
        var exposures: [Exposure] = []
        var announcers: [Announcer] = []
    }

    @Published private(set) var active: Bool
    @Published private(set) var homeSubnet: String?
    @Published private(set) var scanning = false
    @Published private(set) var exposures: [Exposure] = []
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var auditing = false
    @Published private(set) var announcers: [Announcer] = []
    @Published private(set) var heardCount = 0
    @Published private(set) var lastAuditAt: Date?
    @Published private(set) var drilling = false
    /// The score as it stood the moment before going
    /// dark — the header reads the fall from it, so
    /// engaging EMCON shows what it actually bought.
    @Published private(set) var scoreBeforeDark: Score?
    @Published private(set) var drillBefore: Snapshot?
    @Published private(set) var drillAfter: Snapshot?
    /// What the drill itself switched off, by name —
    /// recorded from the mouth's own state at the moment
    /// of going dark, not inferred from the second scan.
    /// The scans can only see listeners and listings,
    /// and a withdrawn listing echoes in mDNS after it
    /// dies; the ledger is the source of truth for the
    /// house's own emissions.
    @Published private(set) var drillSilenced: [String] = []
    @Published private(set) var tripwireOn = false
    @Published private(set) var watched: [Int] = []
    @Published private(set) var watchedUDP: [Int] = []
    @Published private(set) var unwatched: [Int] = []
    @Published private(set) var events: [TripEvent] = []

    private var listeners: [NWListener] = []
    /// Which listener holds which port — the escalation needs
    /// to hand ONE port to the canary without dropping the rest.
    private var listenerPorts: [ObjectIdentifier:
                                 (port: Int, udp: Bool)] = [:]
    private var sweep: BonjourSweep?
    private let tripQueue = DispatchQueue(label: "nightjar.emcon.tripwire")
    private let saveQueue = DispatchQueue(label: "nightjar.emcon.save")
    private static let activeKey = "emconActive"
    private static let homeKey = "emconHomeSubnet"

    // MARK: - knocktalk + vault state

    /// The sequence engine (Knocktalk decoder, structure grader,
    /// vault combination), fed every raw knock from logEvent.
    let knockEngine = KnockEngine()
    /// The conversation layer: threads, delivery states, ACK /
    /// NACK repair, the burn timer. It lives in its own tab now;
    /// EMCON keeps the patterns — the detection side.
    let chat = KnockChat()
    /// The ventriloquist: throws land here first.
    let voiceThrow = VoiceThrowCenter()
    /// The sparring season's ghost lives here.
    let season = Season()
    /// The duel arena's referee and herald.
    let duel = DuelCenter()

    /// The watch officer: reads every knock against the
    /// whole situation and answers under its charter.
    let steward = Steward()
    @Published private(set) var knockPatterns: [KnockPattern] = []
    @Published private(set) var vaultOpenUntil: Date?
    /// Set by the view on appear — the vault needs the mouth to
    /// raise and seal its hidden Serve (the activate() path gets
    /// one directly; this is the standing reference).
    weak var mouth: Mouth?
    private var vaultTimer: Timer?
    private var vaultStartedServe = false
    private var vaultStartedCanary = false

    init() {
        active = UserDefaults.standard.bool(forKey: Self.activeKey)
        homeSubnet = UserDefaults.standard.string(forKey: Self.homeKey)
        events = Self.loadEvents()
        hometurf = Self.loadHometurf()
        // One-time migration: the v1 inbox becomes chat threads,
        // then the old store goes away.
        let legacy = Self.loadKnockMessages()
        if !legacy.isEmpty {
            chat.importLegacy(legacy)
            try? FileManager.default.removeItem(
                at: Self.knockMessagesURL)
        }
        reloadVaultCombination()
        knockEngine.onOutput = { [weak self] output in
            DispatchQueue.main.async {
                self?.handleKnockOutput(output)
            }
        }
        // Relay-replayed knocks enter the same engine. The
        // verdict is the honest one — a relay knock carries no
        // bytes — so no protocol digit is ever derived from
        // one, and the vault combination can only ever be
        // spoken on the local perimeter.
        chat.onRelayFrame = { [weak self] from, ports in
            for port in ports {
                self?.knockEngine.note(
                    source: "relay:" + from, port: port,
                    proto: "TCP",
                    verdict: "silent knock (no bytes sent)")
            }
        }
        chat.refreshRelayPolling()
        // The readable copy only. JSON is already on disk; rewriting
        // it here would race a knock that lands during launch.
        if !events.isEmpty { Self.writeReport(events) }
    }

    var deviceName: String { UIDevice.current.name }
    var ownIP: String? { Mouth.localIPAddress() }

    /// The name this device actually answers to on the wire —
    /// its mDNS hostname, derived from the name in Settings.
    /// UIDevice.current.name has returned the generic "iPhone"
    /// to ordinary apps since iOS 16, so the score reads the
    /// hostname the wire itself sees instead.
    var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0 else { return "" }
        let raw = String(cString: buffer)
        return raw.split(separator: ".").first.map(String.init) ?? raw
    }

    // MARK: - exposure score

    /// 0 = ghost, 100 = a lighthouse. Computed from what is true
    /// right now, not from intentions: mere presence on the wire
    /// weighs first (a joined device is addressable and answers
    /// under a name, EMCON or not), then live emissions, then
    /// what the last recon and audit actually found. The parts
    /// are those same weights, so the band can be read back to
    /// a cause.
    static func score(gattHostOn: Bool, beaconOn: Bool,
                      serveRunning: Bool, stealth: Bool,
                      deviceName: String,
                      exposureCount: Int,
                      announcerCount: Int,
                      assaultOn: Bool = false,
                      serveListeners: Int = 1,
                      probingOn: Bool = false,
                      onLan: Bool = false,
                      hostName: String = "") -> Score {
        var parts: [Score.Part] = []
        func weigh(_ label: String, _ points: Int) {
            guard points > 0 else { return }
            parts.append(Score.Part(label: label, points: points))
        }
        if onLan { weigh("On the wire", 10) }
        if assaultOn { weigh("Net-Assault running", 30) }
        if gattHostOn { weigh("GATT host", 25) }
        if beaconOn { weigh("BLE beacon", 20) }
        if probingOn { weigh("Active probing", 10) }
        if serveRunning {
            let extra = max(0, serveListeners - 1)
            let counted = serveListeners > 1
                ? " ×\(serveListeners)" : ""
            if stealth {
                weigh("Serve, stealth" + counted, 4 + extra)
            } else {
                weigh("Serve, listed" + counted, 20 + 3 * extra)
            }
        }
        if deviceName.contains("\u{2019}s ") || deviceName.contains("'s ") {
            weigh("Personal name", 12)
        } else if !hostName.isEmpty
                    && hostName.lowercased() != "iphone" {
            // The wire-facing name: what every device on the LAN
            // can read off this phone without asking it anything.
            weigh("Answers as \(hostName)", 8)
        } else if deviceName != "iPhone" {
            weigh("Broadcast name", 6)
        }
        if exposureCount > 0 {
            let raw = exposureCount * 4
            weigh("Recon hits ×\(exposureCount)"
                  + (raw > 20 ? ", capped" : ""), min(20, raw))
        }
        if announcerCount > 0 {
            let raw = announcerCount * 6
            weigh("Bonjour ×\(announcerCount)"
                  + (raw > 18 ? ", capped" : ""), min(18, raw))
        }
        let raw = parts.reduce(0) { $0 + $1.points }
        let value = min(100, raw)
        let band: String
        switch value {
        case 0: band = "GHOST"
        case 1...15: band = "DARK"
        case 16...40: band = "LIT"
        case 41...70: band = "LOUD"
        default: band = "BEACONING"
        }
        return Score(value: value, band: band, parts: parts)
    }

    // MARK: - home turf

    /// First three octets of an IPv4 address, or nil when it isn't
    /// a dotted quad. The comparison EMCON actually stores.
    static func subnet(of ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".")
    }

    /// Away only when both sides are known and they differ.
    /// Unmarked, or not on Wi-Fi, is not "away".
    static func away(home: String?, here: String?) -> Bool {
        guard let home, let here else { return false }
        return home != here
    }

    var currentSubnet: String? {
        guard let ip = ownIP else { return nil }
        return Self.subnet(of: ip)
    }

    /// Away = on a network that is not the marked home subnet.
    var isAway: Bool { Self.away(home: homeSubnet, here: currentSubnet) }

    func markHome() {
        guard let here = currentSubnet else { return }
        UserDefaults.standard.set(here, forKey: Self.homeKey)
        homeSubnet = here
    }

    func unmarkHome() {
        UserDefaults.standard.removeObject(forKey: Self.homeKey)
        homeSubnet = nil
    }

    // MARK: - posture

    /// Go dark: silence every emission the app controls and arm the
    /// tripwire. Serve listeners keep running if they were running,
    /// but under stealth — unlisted, silent arrivals.
    func activate(mouth: Mouth) {
        // The reading before the fall, taken from the
        // figures as they stand — engaging EMCON
        // must be able to show what it bought.
        scoreBeforeDark = Self.score(
            gattHostOn: mouth.gattHostOn,
            beaconOn: mouth.beaconOn,
            serveRunning: mouth.serveRunning,
            stealth: mouth.stealth,
            deviceName: deviceName,
            exposureCount: exposures.count,
            announcerCount: announcers.count,
            serveListeners: mouth.serveListenerCount,
            onLan: ownIP != nil,
            hostName: hostName)
        active = true
        UserDefaults.standard.set(true, forKey: Self.activeKey)
        mouth.setStealth(true)
        if mouth.gattHostOn { mouth.stopGattHost() }
        if mouth.beaconOn { mouth.stopBeacon() }
        startTripwire()
        Journal.log("emcon", "posture",
                    "EMCON active — emissions silenced, tripwire armed")
    }

    /// Stand down the tripwire. Stealth, the GATT host and the
    /// beacon are left exactly as they are — re-arming an emission
    /// is always a deliberate act in its own tab.
    func deactivate() {
        scoreBeforeDark = nil
        active = false
        UserDefaults.standard.set(false, forKey: Self.activeKey)
        stopTripwire()
        Journal.log("emcon", "posture", "EMCON stood down")
    }

    /// On tab appearance after a relaunch: if EMCON was left active,
    /// re-arm the tripwire so the posture survives restarts the way
    /// the GATT host arm does.
    func restoreIfNeeded() {
        reloadVaultCombination()
        chat.purge()
        // Reconcile with the persisted flag in BOTH directions:
        // a settings reset (About tab) clears the flag while this
        // instance may still be running, and the live posture must
        // follow the stored truth, not the stale in-memory one.
        let persisted = UserDefaults.standard.bool(forKey: Self.activeKey)
        if persisted, !active { active = true }
        if !persisted, active {
            active = false
            stopTripwire()
            return
        }
        if active, !tripwireOn { startTripwire() }
    }

    // MARK: - self-recon

    /// Knock this device on every port in Recon's registry, over
    /// both loopback and the LAN address, speaking each port's own
    /// probe. Whatever answers is what another operator sees.
    ///
    /// The tripwire stands down for the duration: armed, it accepts
    /// on every probed port, so a scan taken under it would report
    /// the tripwire's own listeners as exposures (141 phantom hits
    /// on first field use) and the tripwire would log the scan as
    /// an attack. It re-arms when the scan completes.
    func runSelfScan(completion: (() -> Void)? = nil) {
        guard !scanning else { completion?(); return }
        let resumeTripwire = tripwireOn
        let releasedPorts = watched
        if resumeTripwire { stopTripwire() }
        guard resumeTripwire, !releasedPorts.isEmpty else {
            performSelfScan(resumeTripwire: resumeTripwire,
                            completion: completion)
            return
        }
        // Teardown is asynchronous: cancel() enqueues behind the
        // tripwire queue's pending work, and the sockets outlive it.
        // A scan fired immediately re-measures the dying listeners —
        // field evidence: exactly the first semaphore wave (~24
        // ports, loopback, where connects complete instantly)
        // reported as open. So the scan waits until a watched port
        // can actually be re-bound (with a short floor), and only
        // then knocks.
        awaitRelease(of: releasedPorts, attempts: 40) { [weak self] in
            self?.performSelfScan(resumeTripwire: resumeTripwire,
                                   completion: completion)
        }
    }

    /// Poll-bind a canary: the last watched port, until the old
    /// listener's socket is really gone (bind succeeds) or the
    /// attempts run out. Never resolves in under 0.3 s. The last
    /// port is the canary because the canary's own socket also
    /// needs a moment to die — and the scan, knocking in ascending
    /// order, reaches that port seconds later.
    private func awaitRelease(of ports: [Int], attempts: Int,
                              done: @escaping () -> Void) {
        let entered = DispatchTime.now()
        func finish() {
            let wait = entered + 0.3
            if DispatchTime.now() < wait {
                DispatchQueue.main.asyncAfter(deadline: wait) { done() }
            } else {
                DispatchQueue.main.async { done() }
            }
        }
        guard attempts > 0, let canary = ports.last,
              let port = NWEndpoint.Port(rawValue: UInt16(canary)) else {
            finish()
            return
        }
        let queue = DispatchQueue(label: "nightjar.emcon.release")
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            queue.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.awaitRelease(of: ports, attempts: attempts - 1,
                                   done: done)
            }
            return
        }
        var settled = false
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if !settled {
                    settled = true
                    listener.cancel()
                    finish()
                }
            case .failed:
                if !settled {
                    settled = true
                    listener.cancel()
                    queue.asyncAfter(deadline: .now() + 0.06) {
                        self?.awaitRelease(of: ports,
                                           attempts: attempts - 1,
                                           done: done)
                    }
                }
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    private func performSelfScan(resumeTripwire: Bool,
                                 completion: (() -> Void)?) {
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
            if resumeTripwire { self.startTripwire() }
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

    static func exposureLine(_ hit: Exposure) -> String {
        "\(hit.host):\(hit.port) \(hit.service)"
    }

    static func announcerLine(_ ad: Announcer) -> String {
        "\(ad.label): \(ad.name)"
    }

    /// In the first snapshot, gone from the second.
    static func silenced(before: Snapshot, after: Snapshot) -> [String] {
        let afterPorts = Set(after.exposures.map(\.id))
        let afterAds = Set(after.announcers.map(\.id))
        return before.exposures.filter { !afterPorts.contains($0.id) }
            .map(exposureLine)
            + before.announcers.filter { !afterAds.contains($0.id) }
            .map(announcerLine)
    }

    /// Everything the second snapshot still shows, service and name.
    static func stillShowing(_ after: Snapshot) -> [String] {
        after.exposures.map(exposureLine) + after.announcers.map(announcerLine)
    }

    /// Scan and audit, go dark, scan and audit again. The two
    /// snapshots land in drillBefore / drillAfter for the delta view.
    func runDrill(mouth: Mouth) {
        guard !drilling, !scanning, !auditing else { return }
        drilling = true
        drillBefore = nil
        drillAfter = nil
        drillSilenced = []
        runSelfScan { [weak self] in
            guard let self = self else { return }
            self.runBonjourAudit {
                self.drillBefore = Snapshot(exposures: self.exposures,
                                            announcers: self.announcers)
                // Name what going dark is about to silence,
                // from the mouth's own state — the second
                // scan is an echo-prone witness for these.
                var ledger: [String] = []
                if mouth.serveRunning, !mouth.stealth {
                    ledger.append("Serve's Bonjour listing — "
                        + "withdrawn; the listeners stay up, "
                        + "unlisted")
                }
                if mouth.gattHostOn {
                    ledger.append("BLE GATT host — stood down")
                }
                if mouth.beaconOn {
                    ledger.append("BLE beacon — stood down")
                }
                self.drillSilenced = ledger
                self.activate(mouth: mouth)
                // A beat longer than feels necessary: a
                // withdrawn listing lingers in the browse
                // for a moment after it dies, and the
                // second pass should measure the wire as
                // it is, not its echo.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
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
            listenerPorts[ObjectIdentifier(listener)] =
                (port, udp)
            return true
        } catch {
            return false
        }
    }

    func stopTripwire() {
        for listener in listeners { listener.cancel() }
        listeners = []
        listenerPorts = [:]
        watched = []
        watchedUDP = []
        unwatched = []
        tripwireOn = false
    }

    /// Give one TCP port up (the canary is taking it), or take
    /// it back (the escalation ended). The rest of the wire
    /// never notices.
    private func releasePort(_ port: Int) {
        for (id, tag) in listenerPorts
            where tag.port == port && !tag.udp {
            if let index = listeners.firstIndex(
                where: { ObjectIdentifier($0) == id }) {
                listeners[index].cancel()
                listeners.remove(at: index)
            }
            listenerPorts.removeValue(forKey: id)
        }
        watched.removeAll { $0 == port }
    }

    private func rebindPort(_ port: Int) {
        guard tripwireOn, !watched.contains(port) else { return }
        if bind(port: port, udp: false) {
            watched.append(port)
            watched.sort()
        }
    }

    func clearEvents() {
        events = []
        saveEvents()
    }

    /// First caller logs the knock. The receive path and the
    /// silent-knock timer both try; the second one is dropped.
    final class TripOnce {
        private let lock = NSLock()
        private var settled = false

        var isSettled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return settled
        }

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if settled { return false }
            settled = true
            return true
        }
    }

    private func handleTrip(_ connection: NWConnection, port: Int,
                            udp: Bool) {
        let source: String
        if case .hostPort(let host, _) = connection.endpoint {
            source = host.debugDescription
        } else {
            source = "unknown"
        }
        let once = TripOnce()
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: tripQueue)
        // One knock, one row. Bytes that show up as the grace
        // timer cancels still win — cancel flushes the receive,
        // and claim() drops the silent fallback.
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: 1024) { [weak self] data, _, _, _ in
            self?.finishTrip(once, connection, source: source,
                             port: port, udp: udp, bytes: data ?? Data())
        }
        tripQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, !once.isSettled else { return }
            // Still up, still mute. Cancel so a receive holding
            // bytes completes and takes the row. If that
            // completion never comes, the follow-up is the
            // silent knock.
            guard connection.state == .ready else { return }
            connection.cancel()
            self.tripQueue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.finishTrip(once, connection, source: source,
                                 port: port, udp: udp, bytes: Data())
            }
        }
    }

    /// One knock, one result. The second call — the grace timer
    /// racing a receive, or a receive racing the timer — is nil.
    static func noteKnock(_ once: TripOnce, bytes: Data,
                          port: Int, udp: Bool) -> (verdict: String, byteCount: Int)? {
        guard once.claim() else { return nil }
        return (tripVerdict(bytes, port: port, udp: udp), bytes.count)
    }

    private func finishTrip(_ once: TripOnce, _ connection: NWConnection,
                            source: String, port: Int, udp: Bool,
                            bytes: Data) {
        guard let noted = Self.noteKnock(once, bytes: bytes,
                                         port: port, udp: udp) else { return }
        connection.cancel()
        logEvent(source: source, port: port,
                 proto: udp ? "UDP" : "TCP",
                 verdict: noted.verdict, byteCount: noted.byteCount,
                 bytes: bytes)
    }

    /// How long identical knocks from one source and port fold
    /// into the same row. The window slides with the latest hit,
    /// so a steady flood stays one line.
    static let burstWindow: TimeInterval = 30
    static let eventCap = 200

    /// Insert a knock, or fold it into a recent identical row.
    /// Identical means same source, port, protocol, and verdict.
    static func record(_ events: inout [TripEvent],
                       source: String, port: Int, proto: String,
                       verdict: String, byteCount: Int,
                       bytesHex: String? = nil,
                       now: Date = Date()) {
        if let index = events.firstIndex(where: { event in
            event.source == source && event.port == port
                && event.proto == proto && event.verdict == verdict
                && now.timeIntervalSince(event.when) >= 0
                && now.timeIntervalSince(event.when) < burstWindow
        }) {
            var hit = events.remove(at: index)
            hit.repeatCount += 1
            hit.when = now
            hit.byteCount = byteCount
            hit.bytesHex = bytesHex ?? hit.bytesHex
            events.insert(hit, at: 0)
            return
        }
        events.insert(TripEvent(when: now, source: source, port: port,
                                proto: proto, verdict: verdict,
                                byteCount: byteCount,
                                bytesHex: bytesHex), at: 0)
        if events.count > eventCap {
            events.removeLast(events.count - eventCap)
        }
    }

    /// The season ghost's door: a synthetic knock fed through
    /// the very path real arrivals take, so every defense —
    /// tripwire, engine, prober files, steward, conductor —
    /// answers it exactly as it would answer the world.
    func ghostKnock(source: String, port: Int, verdict: String) {
        logEvent(source: source, port: port, proto: "TCP",
                 verdict: verdict, byteCount: 0)
    }

    private func logEvent(source: String, port: Int, proto: String,
                          verdict: String, byteCount: Int,
                          bytes: Data? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let mine = self.ownIP != nil && source.contains(self.ownIP!)
            let labeled = mine ? "\(source) (this device)" : source
            Self.record(&self.events, source: labeled, port: port,
                        proto: proto, verdict: verdict,
                        byteCount: byteCount,
                        bytesHex: bytes.map { data in
                            data.map { String(format: "%02x", $0) }
                                .joined()
                        })
            self.saveEvents()
            Journal.log("emcon", "knock",
                        "\(labeled) → \(proto)/\(port) — \(verdict)")
            self.knockEngine.note(source: labeled, port: port,
                                  proto: proto, verdict: verdict)
            self.maybeEscalate(source: labeled, port: port,
                               proto: proto, verdict: verdict,
                               mine: mine)
            self.hometurfObserve(source: labeled, port: port,
                                 verdict: verdict, mine: mine)
            self.senseObserve(source: labeled, port: port,
                              proto: proto, verdict: verdict,
                              mine: mine)
            if let ip = NeighborhoodStore.lanIPv4(from: labeled) {
                NeighborhoodStore.shared.recordArrival(ip: ip)
            }
            Conductor.onKnock(emcon: self, source: labeled,
                              port: port, proto: proto,
                              verdict: verdict, mine: mine)
            steward.onKnock(emcon: self, source: labeled,
                            port: port, proto: proto,
                            verdict: verdict, mine: mine)
        }
    }

    // MARK: - home-turf memory

    /// What a normal night at home sounds like, learned from
    /// the tripwire's own log: the sources that knock, the
    /// doors they try, the first words they speak. It learns
    /// only while EMCON is up on the home subnet — anywhere
    /// else, or standing down, teaches it nothing. After three
    /// banked nights the pattern is held, and anything off it
    /// is flagged as a deviation: the point is not to report
    /// events but to make the ONE new thing in a week of
    /// sameness impossible to miss.
    struct Hometurf: Codable {
        var nights: Int = 0
        var sources: Set<String> = []
        var ports: Set<Int> = []
        var verdicts: Set<String> = []
        var stagingDay: String = ""
        var stagedSources: Set<String> = []
        var stagedPorts: Set<Int> = []
        var stagedVerdicts: Set<String> = []
    }

    @Published private(set) var hometurf = Hometurf()
    @Published private(set) var hometurfNotes: [String] = []

    var hometurfReady: Bool { hometurf.nights >= 3 }

    private static var hometurfURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("emcon-hometurf.json")
    }

    private static func loadHometurf() -> Hometurf {
        guard let data = try? Data(contentsOf: hometurfURL),
              let decoded = try? JSONDecoder().decode(
                Hometurf.self, from: data)
        else { return Hometurf() }
        return decoded
    }

    private func saveHometurf() {
        guard let data = try? JSONEncoder().encode(hometurf)
        else { return }
        try? data.write(to: Self.hometurfURL, options: [.atomic])
    }

    private static func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    /// Fed every knock the funnel sees. Learns silently;
    /// flags only once the pattern is held — and only once
    /// per novelty, since tonight's staging absorbs it.
    func hometurfObserve(source: String, port: Int,
                         verdict: String, mine: Bool) {
        guard active, !mine, homeSubnet != nil, !isAway
        else { return }
        let host = source.components(separatedBy: " ").first
            ?? source
        let today = Self.dayString(Date())
        if hometurf.stagingDay != today {
            if !hometurf.stagingDay.isEmpty,
               !hometurf.stagedSources.isEmpty
                || !hometurf.stagedPorts.isEmpty {
                hometurf.sources.formUnion(hometurf.stagedSources)
                hometurf.ports.formUnion(hometurf.stagedPorts)
                hometurf.verdicts.formUnion(
                    hometurf.stagedVerdicts)
                hometurf.nights += 1
                Journal.log("emcon", "hometurf",
                            "night \(hometurf.nights) banked "
                            + "into the home pattern")
            }
            hometurf.stagingDay = today
            hometurf.stagedSources = []
            hometurf.stagedPorts = []
            hometurf.stagedVerdicts = []
        }
        if hometurfReady {
            var notes: [String] = []
            if !hometurf.sources.contains(host),
               !hometurf.stagedSources.contains(host) {
                notes.append("a new source knocked: \(host)")
            }
            if !hometurf.ports.contains(port),
               !hometurf.stagedPorts.contains(port) {
                notes.append("a new door tried: port \(port)")
            }
            if !hometurf.verdicts.contains(verdict),
               !hometurf.stagedVerdicts.contains(verdict) {
                notes.append("a new first word: \(verdict)")
            }
            for note in notes
            where !Steward.isDismissed(note: note) {
                hometurfNotes.append(note)
                if hometurfNotes.count > 20 {
                    hometurfNotes.removeFirst(
                        hometurfNotes.count - 20)
                }
                Journal.log("emcon", "hometurf",
                            "off the learned pattern — " + note)
            }
        }
        hometurf.stagedSources.insert(host)
        hometurf.stagedPorts.insert(port)
        hometurf.stagedVerdicts.insert(verdict)
        saveHometurf()
    }

    /// The operator dismisses a deviation: it leaves
    /// tonight's list, and the steward records the dismissal
    /// so the pattern stops flagging this exact novelty.
    /// Restorable from the steward section.
    func hometurfDismiss(_ note: String) {
        hometurfNotes.removeAll { $0 == note }
        Steward.addDismissal(note: note)
    }

    func hometurfReset() {
        hometurf = Hometurf()
        hometurfNotes = []
        saveHometurf()
        Journal.log("emcon", "hometurf",
                    "the home pattern was forgotten — "
                    + "learning starts over")
    }

    // MARK: - second sense

    /// The perimeter's threat level as a behavior. A foreign
    /// nightjar-grade probe, or a honeydrop taken, raises a
    /// thirty-minute heightened state on its own: while it
    /// lasts, answer in character is armed whether or not its
    /// toggle is set, and the state shows in the EMCON tab
    /// with its reason and its expiry. Nothing else changes —
    /// a tightened perimeter should be legible, not magical.
    @Published private(set) var senseUntil: Date?
    @Published private(set) var senseReason = ""

    var senseActive: Bool {
        senseUntil.map { $0 > Date() } ?? false
    }

    func raiseSense(reason: String) {
        let wasActive = senseActive
        senseUntil = Date().addingTimeInterval(30 * 60)
        senseReason = reason
        if !wasActive {
            Journal.log("emcon", "sense",
                        "second sense raised for 30 minutes — "
                        + reason + ". Answer in character is "
                        + "armed while it lasts.")
        }
    }

    func senseStandDown() {
        guard senseActive else { return }
        senseUntil = nil
        senseReason = ""
        Journal.log("emcon", "sense",
                    "second sense stood down by the operator")
    }

    /// Fed every knock: someone out there is running tooling
    /// of this instrument's own grade at it. That fact alone
    /// tightens the perimeter.
    func senseObserve(source: String, port: Int, proto: String,
                      verdict: String, mine: Bool) {
        guard !mine, proto == "TCP",
              verdict.hasPrefix("nightjar-hack probe:")
        else { return }
        raiseSense(reason: "a foreign nightjar-grade probe "
                   + "(\(verdict)) from \(source)")
    }

    // MARK: - dead hand

    /// The dead hand. Arm it, then check in deliberately before
    /// the interval runs out. If the app is next opened (launch
    /// or foreground) with the check-in overdue, the hand falls:
    /// the Knocktalk threads burn and EMCON rises, before the
    /// operator has touched anything else. iOS gives a
    /// third-party app no background timer it can trust, so the
    /// hand falls at the next OPENING, not at the deadline
    /// itself — two reminder notifications are scheduled as
    /// courtesies, and the UI copy says all of this plainly.
    /// Only the deliberate check-in resets the clock: merely
    /// opening the app must never feed the hand.
    static let deadHandHoursOptions = [12, 24, 72, 168]

    @Published private(set) var deadHandDown = false

    private var deadHandOn: Bool {
        UserDefaults.standard.bool(forKey: "deadHand.on")
    }
    private var deadHandInterval: TimeInterval {
        let h = UserDefaults.standard.integer(
            forKey: "deadHand.hours")
        return TimeInterval((h > 0 ? h : 24) * 3600)
    }
    private var deadHandLast: Date? {
        let t = UserDefaults.standard.double(forKey: "deadHand.last")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    var deadHandDeadline: Date? {
        deadHandLast?.addingTimeInterval(deadHandInterval)
    }
    var deadHandOverdue: Bool {
        guard deadHandOn, let deadline = deadHandDeadline
        else { return false }
        return Date() > deadline
    }
    var deadHandHasFallen: Bool {
        deadHandDown
            || UserDefaults.standard.double(
                forKey: "deadHand.firedAt") > 0
    }

    /// Arming counts as the first check-in — the operator is
    /// never ambushed by their own switch.
    func deadHandArm() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "deadHand.last")
        UserDefaults.standard.set(0.0, forKey: "deadHand.firedAt")
        deadHandDown = false
        deadHandScheduleReminders()
        Journal.log("emcon", "deadhand",
                    "dead hand armed — check in within "
                    + "\(Int(deadHandInterval / 3600)) h, or the "
                    + "next opening burns and goes dark")
    }

    func deadHandDisarm() {
        deadHandCancelReminders()
    }

    /// The deliberate check-in: the ONLY thing that resets the
    /// clock.
    func deadHandCheckIn() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "deadHand.last")
        UserDefaults.standard.set(0.0, forKey: "deadHand.firedAt")
        deadHandDown = false
        deadHandScheduleReminders()
    }

    /// Changing the interval re-times the reminders; the clock
    /// itself is untouched.
    func deadHandReschedule() {
        deadHandScheduleReminders()
    }

    /// Launch and every foreground. Fires once per overdue
    /// period; a check-in re-arms the trigger.
    func deadHandEvaluate(mouth: Mouth) {
        guard deadHandOn, !deadHandDown,
              UserDefaults.standard.double(
                forKey: "deadHand.firedAt") == 0,
              deadHandOverdue, let deadline = deadHandDeadline
        else { return }
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "deadHand.firedAt")
        deadHandDown = true
        chat.burnNow()
        activate(mouth: mouth)
        let overdueH = Int(
            Date().timeIntervalSince(deadline) / 3600)
        Journal.log("emcon", "deadhand",
                    "DEAD HAND FELL — check-in overdue "
                    + "(\(overdueH) h past the deadline). "
                    + "Knocktalk threads burned; EMCON raised.")
    }

    private func deadHandScheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        deadHandCancelReminders()
        guard let deadline = deadHandDeadline else { return }
        func schedule(_ id: String, at date: Date, body: String) {
            let seconds = date.timeIntervalSinceNow
            guard seconds > 60 else { return }
            let content = UNMutableNotificationContent()
            content.title = "Dead hand"
            content.body = body
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(
                identifier: id, content: content, trigger: trigger))
        }
        schedule("deadhand.warn",
                 at: deadline.addingTimeInterval(-2 * 3600),
                 body: "Check-in due in about two hours. Miss "
                    + "it, and the next opening burns the "
                    + "Knocktalk threads and raises EMCON.")
        schedule("deadhand.due", at: deadline,
                 body: "Check-in overdue. The hand falls at "
                    + "the next opening.")
    }

    private func deadHandCancelReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(
                withIdentifiers: ["deadhand.warn", "deadhand.due"])
    }

    // MARK: - escalation (answer in character)

    /// The perimeter's second reflex, when the operator arms
    /// it: a knock the tripwire can fingerprint as a real
    /// protocol stops meeting silence. The tripwire hands the
    /// knocked port to the matching canary persona for ten
    /// minutes — honeydrop included, per the Serve tab's
    /// settings — then takes the port back. A port that has
    /// escalated cools down for half an hour before it can
    /// escalate again, so a persistent prober meets a rhythm,
    /// not a loop.
    @Published private(set) var escalation:
        (persona: String, port: Int, until: Date)?
    private var escalationTimer: Timer?
    private var escalationCooldown: [Int: Date] = [:]

    static var escalationArmed: Bool {
        UserDefaults.standard.bool(forKey: "emconEscalation")
    }

    static func persona(forVerdict verdict: String) -> String? {
        let text = verdict.lowercased()
        if text.contains("ssh") { return "ssh" }
        if text.contains("mqtt") { return "mqtt" }
        if text.contains("smtp") { return "smtp" }
        if text.contains("http") { return "http" }
        return nil
    }

    /// The steward's anticipation: raise the matching canary
    /// on a door a filed visitor is predicted to try next,
    /// through the identical hand-off an answer uses — same
    /// release, same ten minutes, same cooldown, same
    /// teardown-race guard. The only difference is tense.
    func prestageCanary(port: Int, persona: String,
                        source: String) {
        guard tripwireOn, escalation == nil,
              let mouth = mouth,
              mouth.canary.runningPersona == nil
        else { return }
        if let until = escalationCooldown[port], until > Date() {
            return
        }
        releasePort(port)
        let defaults = UserDefaults.standard
        func raiseCanary() {
            mouth.canary.start(
                mouth: mouth, persona: persona, port: port,
                honeydrop: defaults.bool(
                    forKey: "canaryHoneydrop"),
                drop: defaults.string(forKey: "canaryDrop") ?? "")
        }
        raiseCanary()
        let until = Date().addingTimeInterval(600)
        escalation = (persona, port, until)
        escalationTimer?.invalidate()
        escalationTimer = Timer.scheduledTimer(
            withTimeInterval: 600, repeats: false) { [weak self] _ in
            self?.endEscalation()
        }
        Journal.log("emcon", "escalation",
                    "the steward pre-staged the \(persona) "
                    + "canary on \(port) — \(source)'s own "
                    + "sequence points there; it answers for "
                    + "10 minutes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            [weak self] in
            guard let self = self, self.escalation != nil,
                  mouth.canary.runningPersona == nil
            else { return }
            raiseCanary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                [weak self] in
                guard let self = self, self.escalation != nil,
                      mouth.canary.runningPersona == nil
                else { return }
                Journal.log("emcon", "escalation",
                            "the pre-stage hand-off failed "
                            + "— port \(port) stays on the wire")
                self.endEscalation()
            }
        }
    }

    /// The conductor's road into the same hand-off: a reflex
    /// may order the answer even with the toggle off and the
    /// sense at ease — every other guard still applies.
    func escalateNow(source: String, port: Int, verdict: String) {
        maybeEscalate(source: source, port: port, proto: "TCP",
                      verdict: verdict, mine: false, forced: true)
    }

    private func maybeEscalate(source: String, port: Int,
                               proto: String, verdict: String,
                               mine: Bool, forced: Bool = false) {
        guard Self.escalationArmed || senseActive || forced,
              proto == "TCP", !mine,
              tripwireOn, escalation == nil,
              let mouth = mouth,
              mouth.canary.runningPersona == nil,
              let persona = Self.persona(forVerdict: verdict)
        else { return }
        if let until = escalationCooldown[port], until > Date() {
            return
        }
        releasePort(port)
        let defaults = UserDefaults.standard
        func raiseCanary() {
            mouth.canary.start(
                mouth: mouth, persona: persona, port: port,
                honeydrop: defaults.bool(
                    forKey: "canaryHoneydrop"),
                drop: defaults.string(forKey: "canaryDrop") ?? "")
        }
        raiseCanary()
        let until = Date().addingTimeInterval(600)
        escalation = (persona, port, until)
        escalationTimer?.invalidate()
        escalationTimer = Timer.scheduledTimer(
            withTimeInterval: 600, repeats: false) { [weak self] _ in
            self?.endEscalation()
        }
        Journal.log("emcon", "escalation",
                    "\(persona) knock from \(source) on \(port) "
                    + "— answered in character for 10 minutes")
        // Listener teardown is asynchronous (the self-scan saga
        // taught that): the canary's first bind can lose the
        // race against the tripwire's dying socket. Check, retry
        // once, and if the port still won't take, give it back
        // rather than leave it unwatched under a false flag.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            [weak self] in
            guard let self = self, self.escalation != nil,
                  mouth.canary.runningPersona == nil
            else { return }
            raiseCanary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                [weak self] in
                guard let self = self, self.escalation != nil,
                      mouth.canary.runningPersona == nil
                else { return }
                Journal.log("emcon", "escalation",
                            "the hand-off to the canary failed "
                            + "— port \(port) stays on the wire")
                self.endEscalation()
            }
        }
    }

    func endEscalation() {
        escalationTimer?.invalidate()
        escalationTimer = nil
        guard let current = escalation else { return }
        escalation = nil
        escalationCooldown[current.port] =
            Date().addingTimeInterval(1800)
        if let mouth = mouth,
           mouth.canary.runningPersona == current.persona {
            mouth.canary.stop()
        }
        rebindPort(current.port)
        Journal.log("emcon", "escalation",
                    "escalation over — tripwire re-armed on "
                    + "\(current.port)")
    }

    // MARK: - sequence engine outputs

    /// Cadence Seal: grade the rhythm of the message that just
    /// landed. The engine cut the sample out of the knock train
    /// before it emitted the message; the key decided the
    /// message opens — the cadence decides whether the hands
    /// are believed.
    private func gradeCadence(of message: KnockMessage) {
        guard CadenceSeal.enabled,
              let sample = knockEngine.lastCadence[message.source]
        else { return }
        let peer = KnockChat.peerKey(message.source)
        let verdict = CadenceSeal.record(peer: peer, sample: sample)
        if let note = CadenceSeal.note(for: verdict) {
            chat.setCadenceNote(peer: peer, note: note)
        }
        switch verdict {
        case .foreign(let score):
            Journal.log("emcon", "cadence",
                        "FOREIGN HANDS from \(message.source) — "
                        + "right key, wrong rhythm (distance "
                        + String(format: "%.1f", score) + ")")
            // A foreign verdict is no longer a dead
            // end. The streak is counted per peer,
            // and the third in a row escalates for
            // real — the second sense rises and the
            // conductor hears of it — because right
            // key, wrong hands, REPEATEDLY is the
            // clone scenario the seal exists for.
            // One stray verdict (a new phone, a
            // congested relay) stays a note, as
            // before; the seal still never blocks.
            let streakKey = "cadenceForeignStreaks"
            var streaks = UserDefaults.standard
                .dictionary(forKey: streakKey)
                as? [String: Int] ?? [:]
            let streak = (streaks[peer] ?? 0) + 1
            streaks[peer] = streak
            UserDefaults.standard.set(streaks,
                                      forKey: streakKey)
            if streak == 3 {
                Journal.log("emcon", "cadence",
                            "ESCALATION — three foreign "
                            + "verdicts running from "
                            + "\(message.source); the "
                            + "second sense rises")
                raiseSense(reason: "cadence: foreign "
                    + "hands from \(message.source), "
                    + "three verdicts running")
                Conductor.onForeignHands(emcon: self,
                                         host: peer)
            }
        case .match:
            // A matching hand clears the streak.
            let streakKey = "cadenceForeignStreaks"
            var streaks = UserDefaults.standard
                .dictionary(forKey: streakKey)
                as? [String: Int] ?? [:]
            if streaks[peer] != nil {
                streaks[peer] = 0
                UserDefaults.standard.set(streaks,
                                          forKey: streakKey)
            }
        case .learning(let have, let need) where have == need:
            Journal.log("emcon", "cadence",
                        "cadence enrolled for \(message.source) — "
                        + "\(need) samples learned")
        default:
            break
        }
    }

    private func handleKnockOutput(_ output: KnockEngine.Output) {
        switch output {
        case .message(let message, let ackHash):
            // The duel herald and the ventriloquist get
            // first refusal: their messages are business,
            // not conversation.
            if duel.intercept(text: message.text,
                              source: message.source,
                              chat: chat, emcon: self) {
                break
            }
            if voiceThrow.intercept(text: message.text,
                                    source: message.source,
                                    chat: chat) {
                break
            }
            chat.receive(text: message.text, from: message.source,
                         ackHash: ackHash)
            // The journal records THAT a message arrived, never
            // what it says — the text lives only in the thread.
            Journal.log("emcon", "knocktalk",
                        "message received from \(message.source) — "
                        + "\(message.text.count) characters")
            gradeCadence(of: message)
            NeighborhoodStore.shared.discover(
                source: message.source, via: "knocktalk")
        case .ack(let source, let hash):
            chat.handleAck(from: source, hash: hash)
            Journal.log("emcon", "knocktalk",
                        "delivery confirmed by \(source)")
            NeighborhoodStore.shared.discover(
                source: source, via: "knocktalk")
        case .nack(let source, let missing):
            chat.handleNack(from: source, missing: missing)
            Journal.log("emcon", "knocktalk",
                        "\(source) asked for \(missing.count) "
                        + "fragment(s) again — re-knocking them")
        case .nackNeeded(let source, let missing):
            chat.requestRepair(to: source, missing: missing)
            Journal.log("emcon", "knocktalk",
                        "message from \(source) arrived with "
                        + "\(missing.count) hole(s) — NACK "
                        + "knocked back")
        case .pattern(let pattern):
            knockPatterns.insert(pattern, at: 0)
            if knockPatterns.count > 50 {
                knockPatterns.removeLast(knockPatterns.count - 50)
            }
            Journal.log("emcon", "knocktalk",
                        "structured pattern from \(pattern.source) — "
                        + pattern.note)
        case .vaultUnlock(let source):
            openVault(source: source)
        }
    }

    private static var knockMessagesURL: URL {
        documentsURL.appendingPathComponent("knocktalk-messages.json")
    }

    /// The retired v1 inbox, read once for migration.
    private static func loadKnockMessages() -> [KnockMessage] {
        guard let data = try? Data(contentsOf: knockMessagesURL),
              let decoded = try? JSONDecoder().decode(
                [KnockMessage].self, from: data) else { return [] }
        return decoded
    }

    // MARK: - the knock vault

    @Published private(set) var vaultCombo: [String] =
        ["ssh", "tls", "mqtt"]
    private static let vaultComboKey = "emconVaultCombo"

    /// What the combination DOES when spoken. The vault began
    /// as a one-trick door (a hidden Serve for sixty seconds);
    /// it is a macro trigger now — the combination stays the
    /// key, the action is the operator's choice.
    @Published private(set) var vaultAction = "serve"
    private static let vaultActionKey = "emconVaultAction"
    static let vaultActions = ["serve", "emcon", "burn", "canary"]

    static func vaultActionLabel(_ action: String) -> String {
        switch action {
        case "emcon": return "Raise EMCON"
        case "burn": return "Burn Knocktalk threads now"
        case "canary": return "Raise the canary (60 s)"
        default: return "Open hidden Serve (60 s)"
        }
    }

    func reloadVaultAction() {
        let stored = UserDefaults.standard
            .string(forKey: Self.vaultActionKey) ?? "serve"
        vaultAction = Self.vaultActions.contains(stored)
            ? stored : "serve"
    }

    func setVaultAction(_ action: String) {
        UserDefaults.standard.set(action,
                                  forKey: Self.vaultActionKey)
        reloadVaultAction()
    }

    func reloadVaultCombination() {
        let stored = UserDefaults.standard
            .string(forKey: Self.vaultComboKey)?
            .split(separator: ",").map(String.init) ?? []
        let combo = stored.count == 3
            ? stored : ["ssh", "tls", "mqtt"]
        vaultCombo = combo
        knockEngine.vaultCombination = combo
        reloadVaultAction()
    }

    func setVaultDigit(_ index: Int, _ digit: String) {
        var combo = vaultCombo
        guard combo.indices.contains(index) else { return }
        combo[index] = digit
        UserDefaults.standard.set(combo.joined(separator: ","),
                                  forKey: Self.vaultComboKey)
        reloadVaultCombination()
    }

    /// The combination was spoken: fire the chosen macro.
    /// Timed macros (Serve, canary) ride the vault's sixty
    /// seconds and are stood back down at the seal — and only
    /// if the vault itself raised them; anything the operator
    /// already had running on their own orders is left exactly
    /// as it was. Instant macros (raise EMCON, burn) simply
    /// happen; the open window is their refractory period.
    func openVault(source: String) {
        guard vaultOpenUntil == nil else { return }
        vaultOpenUntil = Date().addingTimeInterval(60)
        vaultTimer?.invalidate()
        vaultTimer = Timer.scheduledTimer(
            withTimeInterval: 60, repeats: false) { [weak self] _ in
            self?.sealVault()
        }
        var detail = ""
        switch vaultAction {
        case "emcon":
            if let mouth = mouth, !active {
                activate(mouth: mouth)
                detail = " — EMCON raised"
            } else {
                detail = " — EMCON already up"
            }
        case "burn":
            chat.burnNow()
            detail = " — Knocktalk threads burned"
        case "canary":
            if let mouth = mouth,
               mouth.canary.runningPersona == nil {
                let defaults = UserDefaults.standard
                let persona = defaults.string(
                    forKey: "canaryPersona") ?? "ssh"
                let port = Int(defaults.string(
                    forKey: "canaryPort") ?? "")
                    ?? CanaryHost.defaultPort(persona)
                mouth.canary.start(
                    mouth: mouth, persona: persona, port: port,
                    honeydrop: defaults.bool(
                        forKey: "canaryHoneydrop"),
                    drop: defaults.string(
                        forKey: "canaryDrop") ?? "")
                vaultStartedCanary = true
                detail = " — canary raised for the window"
            } else {
                detail = " — canary already up"
            }
        default:
            if let mouth = mouth, !mouth.serveRunning {
                mouth.startServeFromSettings()
                vaultStartedServe = mouth.serveRunning
                detail = vaultStartedServe
                    ? " — hidden Serve raised" : ""
            }
        }
        Journal.log("emcon", "vault",
                    "combination spoken by \(source) — macro: "
                    + Self.vaultActionLabel(vaultAction) + detail)
        Conductor.onVault(emcon: self)
    }

    func sealVault() {
        vaultTimer?.invalidate()
        vaultTimer = nil
        guard vaultOpenUntil != nil else { return }
        vaultOpenUntil = nil
        if vaultStartedServe, let mouth = mouth, mouth.serveRunning {
            mouth.stopServe()
        }
        vaultStartedServe = false
        if vaultStartedCanary, let mouth = mouth {
            mouth.canary.stop()
        }
        vaultStartedCanary = false
        Journal.log("emcon", "vault", "vault sealed")
    }

    // MARK: - tripwire log persistence

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
    }

    private static var eventsURL: URL {
        documentsURL.appendingPathComponent("emcon-tripwire.json")
    }

    static var tripwireReportURL: URL {
        documentsURL.appendingPathComponent("emcon-tripwire.txt")
    }

    private static func writeReport(_ events: [TripEvent]) {
        try? Data(tripwireReport(events).utf8)
            .write(to: tripwireReportURL, options: .atomic)
    }

    /// Readable export. One block per row; a burst shows as ×N.
    /// JSON in Documents is the same log, for anything that parses.
    static func tripwireReport(_ events: [TripEvent]) -> String {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines = [
            "EMCON tripwire",
            "The tripwire never replies.",
            "",
        ]
        if events.isEmpty {
            lines.append("Nobody has knocked.")
            return lines.joined(separator: "\n")
        }
        for event in events {
            let times = event.repeatCount > 1 ? " ×\(event.repeatCount)" : ""
            lines.append("\(stamp.string(from: event.when))  "
                         + "\(event.source) → \(event.proto)/\(event.port)\(times)")
            lines.append("  \(event.verdict)")
        }
        return lines.joined(separator: "\n")
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
        Self.writeReport(snapshot)
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
    private typealias Signature = (name: String, port: Int,
                                   udp: Bool, bytes: Data)

    private static let signatures: [Signature] =
        ReconPayloads.all.values.map {
            (name: $0.name, port: $0.port, udp: $0.udp, bytes: $0.build())
        }

    /// Best library probe for these bytes. Overlap is how many
    /// bytes agree: a full signature sitting inside the payload,
    /// or a partial send that is a prefix of one. A full match
    /// beats an equal-length partial, so a short probe can't be
    /// stolen by a longer one that merely starts the same way,
    /// and a stub of a long probe can't lose to an even shorter
    /// prefix. Several probes share one payload (the plain
    /// GET /); the one aimed at this port wins that tie, then
    /// the name.
    private static func bestSignature(for data: Data, port: Int,
                                      udp: Bool) -> Signature? {
        guard data.count >= 3 else { return nil }
        var best: (sig: Signature, overlap: Int, full: Bool)?
        for sig in signatures where sig.bytes.count >= 3 {
            let full = data.starts(with: sig.bytes)
            let partial = sig.bytes.starts(with: data)
            guard full || partial else { continue }
            let overlap = full ? sig.bytes.count : data.count
            let take: Bool
            if let current = best {
                if overlap != current.overlap {
                    take = overlap > current.overlap
                } else if full != current.full {
                    take = full
                } else if fits(sig, port: port, udp: udp)
                            != fits(current.sig, port: port, udp: udp) {
                    take = fits(sig, port: port, udp: udp)
                } else {
                    take = sig.name < current.sig.name
                }
            } else {
                take = true
            }
            if take { best = (sig, overlap, full) }
        }
        return best?.sig
    }

    private static func fits(_ sig: Signature, port: Int, udp: Bool) -> Bool {
        sig.port == port && sig.udp == udp
    }

    private static func verdict(for sig: Signature, port: Int, udp: Bool) -> String {
        var verdict = "nightjar-hack probe: \(sig.name)"
        if sig.port != port {
            verdict += " (on the wrong port)"
        } else if sig.udp != udp {
            verdict += " (a \(sig.udp ? "UDP" : "TCP") probe "
                + "over \(udp ? "UDP" : "TCP"))"
        }
        return verdict
    }

    /// Empty bytes are a silent knock. Anything else is fingerprinted.
    static func tripVerdict(_ bytes: Data, port: Int, udp: Bool) -> String {
        guard !bytes.isEmpty else { return "silent knock (no bytes sent)" }
        return fingerprint(bytes, port: port, udp: udp)
    }

    static func fingerprint(_ data: Data, port: Int, udp: Bool) -> String {
        guard !data.isEmpty else { return "empty connection" }
        if let sig = bestSignature(for: data, port: port, udp: udp) {
            return verdict(for: sig, port: port, udp: udp)
        }
        if data.count >= 2, data[0] == 0x16, data[1] == 0x03 {
            return "TLS ClientHello — a TLS scanner or client knocked"
        }
        if data.starts(with: Data("SSH-2.0-".utf8)) {
            let line = ReconPayloads.firstLine(data, limit: 60)
            return "SSH client banner: \(line)"
        }
        for verb in ["GET ", "POST ", "HEAD ", "PUT ", "DELETE ",
                     "OPTIONS ", "CONNECT "] {
            if data.starts(with: Data(verb.utf8)) {
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
