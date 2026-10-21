import SwiftUI
import Network

/// The Neighborhood: a cast of characters for your own wire.
///
/// Dossiers testify on demand — knock, and a page is written.
/// The neighborhood is the opposite posture: it only ever
/// WATCHES. Every sweep Scan runs, every Bonjour announcement
/// that resolves, every knock that arrives at this phone's
/// own door adds a line to a standing file on the device
/// that owns the address. Over weeks the wire stops being a
/// list of numbers and becomes a cast: the television that
/// answers at all hours, the laptop that appears at nine and
/// vanishes at five, the stranger who knocked once in March
/// and never again.
///
/// The boundary is the same one the whole instrument keeps:
/// this is the operator's own network, observed by the
/// operator's own phone, from traffic the phone itself sent
/// or received. Nothing is followed off the wire, and a
/// neighbor is an address — never a person.
struct Neighbor: Codable, Identifiable {
    var id: String { ip }
    var ip: String
    var name: String?
    var firstSeen: Date
    var lastSeen: Date
    var sightings = 0
    /// Ports this address has ever answered on, ascending.
    var ports: [Int] = []
    /// Bonjour labels it announces, in full ("_ssh._tcp — Mac").
    var announcements: [String] = []
    /// Times it knocked THIS phone (Serve / tripwire arrivals).
    var arrivals = 0
    /// The newest stories first, capped.
    var drift: [String] = []

    /// The operator's given name for this address, if any —
    /// the name it answers to in every section. The wire's
    /// own name stays in `name`; this one outranks it.
    var customName: String? = nil
    /// An SF Symbol the operator picked to tell it apart
    /// at a glance.
    var customMark: String? = nil

    var displayName: String { customName ?? name ?? ip }

    var lastSeenLine: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return L("last seen ") + fmt.localizedString(
            for: lastSeen, relativeTo: Date())
    }
}

/// The router, read by signs (Chase's ruling,
/// 2026-10-20: "we should still be capable
/// of interpreting which signal is the
/// router through signs"). One certainty
/// exists — the default route's gateway IS
/// the router by definition — and the store
/// crowns it outright. Everything else is
/// weighed evidence, scored and SHOWN: the
/// signs are listed with the verdict, and
/// the verdict's language never outruns
/// them.
enum RouterSigns {
    enum Weight {
        case certain, likely, possible, none
        var line: String {
            switch self {
            case .certain: return L("THE ROUTER")
            case .likely: return L("likely the router")
            case .possible:
                return L("possibly router or access point")
            case .none: return ""
            }
        }
    }

    /// Score one neighbor's signs. The
    /// gateway fact is applied by the store
    /// (it owns the comparison); here are
    /// the circumstantial signs: the doors
    /// it holds, the chair it sits in, the
    /// name it answers to, what it has been
    /// heard announcing.
    static func score(
        ip: String, name: String?,
        ports: [Int], announcements: [String])
        -> (weight: Weight, signs: [String]) {
        var points = 0
        var signs: [String] = []
        if ports.contains(67) {
            points += 3
            signs.append(L("answers DHCP — it hands out the addresses"))
        }
        if ports.contains(53) {
            points += 2
            signs.append(L("serves DNS"))
        }
        let adminDoors = [80, 443, 8080, 8443,
                          7547].filter {
            ports.contains($0)
        }
        if let door = adminDoors.first {
            points += 1
            signs.append(L("holds a web-admin ")
                         + String(format: L("door (%@)"), String(describing: door)))
        }
        if let last = ip.split(separator: ".")
            .last, last == "1" || last == "254" {
            points += 1
            signs.append(String(format: L("sits at .%@ — the router's usual chair"), String(describing: last)))
        }
        let gearWords = ["router", "gateway",
                         "fritz", "asus",
                         "tplink", "tp-link",
                         "deco", "eero", "orbi",
                         "velop", "meraki",
                         "aruba", "mikrotik",
                         "unifi", "ubiquiti",
                         "starlink", "linksys",
                         "netgear", "airport",
                         "synology"]
        if let name {
            let low = name.lowercased()
            if gearWords.contains(
                where: { low.contains($0) }) {
                points += 2
                signs.append(L("answers to a ")
                             + L("network-gear name ")
                             + "(\u{201C}\(name)"
                             + "\u{201D})")
            }
        }
        for line in announcements {
            let lowLine = line.lowercased()
            if gearWords.contains(
                where: { lowLine.contains($0) }),
               name == nil {
                points += 1
                signs.append(L("announces ")
                             + L("network gear in ")
                             + L("its own words"))
                break
            }
        }
        for line in announcements {
            if line.contains("MikroTik") {
                points += 3
                signs.append(L("speaks MikroTik's ")
                             + L("own discovery ")
                             + "(MNDP)")
                break
            }
        }
        let weight: Weight = points >= 4
            ? .likely
            : points >= 2 ? .possible : .none
        return (weight, signs)
    }
}

final class NeighborhoodStore: ObservableObject {
    static let shared = NeighborhoodStore()

    @Published private(set) var neighbors: [Neighbor] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("neighborhood.json")
    }

    init() { load() }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? decoder.decode(
                  [Neighbor].self, from: data)
        else { neighbors = []; return }
        neighbors = decoded.sorted {
            $0.lastSeen > $1.lastSeen
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(neighbors) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// Persistence, coalesced: a sweep can land
    /// hundreds of sightings in a breath, and the
    /// file used to be rewritten whole for every
    /// one of them. Mutations now mark the store
    /// dirty and the write lands once, a second
    /// later, with everything the breath brought.
    /// (Deliberate acts — a rename, a clear — still
    /// save on the spot.)
    private var savePending = false
    private func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.savePending = false
            self.save()
        }
    }

    /// Empty the board: every neighbor forgotten, and
    /// their Map placements with them (a placement for a
    /// device the house no longer keeps is a ghost). The
    /// wire will populate its own cast again.
    func clear() {
        neighbors = []
        save()
        MapStore.shared.prune(to: [])
    }

    /// Give an address its operator name — or take it
    /// back. The name follows the address everywhere it is
    /// presented: this board, the Map, its dossier, the
    /// Subconscious's findings.
    func rename(ip: String, to newName: String?,
                mark: String?) {
        guard let index = neighbors.firstIndex(
            where: { $0.ip == ip }) else { return }
        let trimmed = newName?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        neighbors[index].customName =
            (trimmed?.isEmpty == true) ? nil : trimmed
        neighbors[index].customMark = mark
        save()
        if let given = neighbors[index].customName {
            Journal.log("neighborhood", "named",
                        String(format: L("%@ answers to '%@' now"), String(describing: ip), String(describing: given)))
        } else {
            Journal.log("neighborhood", "named",
                        String(format: L("%@'s given name was cleared"), String(describing: ip)))
        }
    }

    /// The one mutation door: every feed arrives on the main
    /// queue, upserts its neighbor, and journals what is NEWS
    /// — a first sighting, a new port, a changed name. Routine
    /// re-sightings are tallied in silence.
    private func upsert(ip: String,
                        mutate: @escaping (inout Neighbor, Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.applyUpsert(ip: ip, mutate: mutate)
            self.neighbors.sort { $0.lastSeen > $1.lastSeen }
            self.scheduleSave()
        }
    }

    /// The upsert itself — main queue, no sort, no
    /// save. The batch door runs a whole sweep
    /// through it and settles both once, instead of
    /// per host.
    private func applyUpsert(
        ip: String,
        mutate: (inout Neighbor, Bool) -> Void) {
        if let index = neighbors.firstIndex(
            where: { $0.ip == ip }) {
            var neighbor = neighbors[index]
            mutate(&neighbor, false)
            neighbor.lastSeen = Date()
            neighbor.sightings += 1
            neighbors[index] = neighbor
        } else {
            var neighbor = Neighbor(ip: ip, name: nil,
                                    firstSeen: Date(),
                                    lastSeen: Date())
            mutate(&neighbor, true)
            neighbor.sightings = 1
            neighbors.append(neighbor)
            Journal.log("neighborhood", "new",
                        String(format: L("a new neighbor at %@ — the wire has one more character"), String(describing: ip)))
        }
    }

    private func noteDrift(_ neighbor: inout Neighbor,
                           _ line: String) {
        neighbor.drift.insert(line, at: 0)
        if neighbor.drift.count > 10 {
            neighbor.drift.removeLast(neighbor.drift.count - 10)
        }
        Journal.log("neighborhood", "drift",
                    "\(neighbor.displayName) (\(neighbor.ip)): "
                    + line)
    }

    /// The one discovery door. Anything any feature finds
    /// on this wire walks in here — a recon answer, a reply
    /// the mouth collected, a knocktalk peer, a honeydrop
    /// taker — and becomes a neighbor the Map can place.
    /// The same LAN filter the arrivals feed uses stands
    /// guard, so relay labels, the ghost, loopback, and the
    /// wide internet are turned away at the door.
    func discover(source rawLabel: String, port: Int? = nil,
                  via: String) {
        guard let ip = Self.lanIPv4(from: rawLabel) else {
            return
        }
        upsert(ip: ip) { neighbor, isNew in
            if let port, !neighbor.ports.contains(port) {
                neighbor.ports.append(port)
                neighbor.ports.sort()
                if !isNew {
                    self.noteDrift(
                        &neighbor,
                        String(format: L("answered on port %@ for the first time"), String(describing: port)))
                }
            }
            if isNew {
                Journal.log("neighborhood", "discovery",
                            String(format: L("%@ found by %@"), String(describing: ip), String(describing: via)))
            }
        }
    }

    // MARK: - the three feeds

    /// Scan's /24 sweep answered: who is up, on this port.
    /// One door for the whole sweep: a single main-queue
    /// pass, a single sort, a single coalesced save —
    /// not one of each per host. The completion fires
    /// AFTER the pass lands — a reader who asks the
    /// moment the sweep returns (her census hand,
    /// fix270) must not read the board from before it.
    func recordSweep(_ hosts: [SweepHost],
                     completion: (() -> Void)? = nil) {
        let byIP = Dictionary(grouping: hosts, by: { $0.ip })
        guard !byIP.isEmpty else {
            completion?()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (ip, answers) in byIP {
                self.applyUpsert(ip: ip) { neighbor, isNew in
                    // Port 0 is a liveness row
                    // (fix275): the host is up —
                    // it refused a closed door,
                    // fast — but no door stands
                    // open to record.
                    for answer in answers
                    where answer.port > 0
                        && !neighbor.ports.contains(answer.port) {
                        neighbor.ports.append(answer.port)
                        neighbor.ports.sort()
                        if !isNew {
                            self.noteDrift(&neighbor,
                                      L("answered on port ")
                                      + "\(answer.port) "
                                      + "(\(ScanModel.serviceName(for: answer.port) ?? "unknown")) "
                                      + L("for the first time"))
                        }
                    }
                }
            }
            self.neighbors.sort { $0.lastSeen > $1.lastSeen }
            self.scheduleSave()
            completion?()
        }
    }

    /// The router report: the crowned
    /// gateway first (certainty, not a
    /// sign), then every candidate with its
    /// weighed signs, strongest first.
    func routerReport(
        gatewayIP: String?)
        -> [(neighbor: Neighbor,
             weight: RouterSigns.Weight,
             signs: [String])] {
        var rows: [(Neighbor,
                     RouterSigns.Weight,
                     [String])] = []
        for neighbor in neighbors {
            if let gatewayIP,
               neighbor.ip == gatewayIP {
                rows.append((neighbor,
                    .certain,
                    [L("this phone's default ")
                     + L("route lands here — ")
                     + L("the router by ")
                     + "definition"]))
                continue
            }
            let scored = RouterSigns.score(
                ip: neighbor.ip,
                name: neighbor.name,
                ports: neighbor.ports,
                announcements:
                    neighbor.announcements)
            if scored.weight != .none {
                rows.append((neighbor,
                             scored.weight,
                             scored.signs))
            }
        }
        rows.sort {
            if $0.1 == .certain { return true }
            if $1.1 == .certain { return false }
            return $0.2.count > $1.2.count
        }
        return rows
    }

    /// A Bonjour announcement, resolved to its address.
    func recordBonjour(ip: String, name: String, label: String) {
        upsert(ip: ip) { neighbor, isNew in
            if let old = neighbor.name, old != name, !isNew {
                self.noteDrift(&neighbor,
                          String(format: L("announces itself as “%@” now — it was “%@”"), String(describing: name), String(describing: old)))
            }
            if neighbor.name == nil || neighbor.name != name {
                neighbor.name = name
            }
            let line = "\(label) — \(name)"
            if !neighbor.announcements.contains(line) {
                neighbor.announcements.append(line)
                if !isNew {
                    self.noteDrift(&neighbor,
                              String(format: L("began announcing %@"), String(describing: label)))
                }
            }
        }
    }

    /// The facts a service's Bonjour TXT record
    /// states about itself — the model it names,
    /// the capabilities it lists — read at resolve
    /// time (decoders arc, 2026-10-20). Each fact
    /// joins the announcements in the label's own
    /// name, so the dossier reads them where the
    /// announcement itself is told.
    func recordBonjourFacts(ip: String, label: String,
                            facts: [String]) {
        guard !facts.isEmpty else { return }
        upsert(ip: ip) { neighbor, _ in
            for fact in facts {
                let line = "\(label) — \(fact)"
                if !neighbor.announcements
                    .contains(line) {
                    neighbor.announcements
                        .append(line)
                }
            }
        }
    }

    /// It knocked US: a Serve or tripwire arrival.
    func recordArrival(ip: String) {
        upsert(ip: ip) { neighbor, _ in
            neighbor.arrivals += 1
        }
    }

    /// Pull a LAN IPv4 address out of an arrival's source
    /// label, or nothing: the ghost, relay peers, this device,
    /// and loopback are not neighbors.
    static func lanIPv4(from source: String) -> String? {
        guard !source.contains(L("(this device)")),
              !source.hasPrefix("relay:") else { return nil }
        let head = source.split(separator: ":").first
            .map(String.init) ?? source
        let parts = head.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.allSatisfy(\.isNumber)
                      && Int(part) != nil && Int(part)! <= 255
              }),
              parts[0] != "127"
        else { return nil }
        return head
    }

    /// The neighbor's testimony, as the dossier page takes it.
    func wifiLines(for neighbor: Neighbor) -> [String] {
        var lines: [String] = []
        let stamp = neighbor.firstSeen.formatted(
            date: .abbreviated, time: .shortened)
        lines.append(String(format: L("On the wire since %@ — %@ sightings, %@"), String(describing: stamp), String(describing: neighbor.sightings), String(describing: neighbor.lastSeenLine)))
        for port in neighbor.ports {
            lines.append(String(format: L("Answered on %@/tcp (%@)"), String(describing: port), String(describing: ScanModel.serviceName(for: port) ?? L("unknown"))))
        }
        for announcement in neighbor.announcements {
            lines.append(L("Announces itself via Bonjour: ")
                         + announcement)
        }
        if neighbor.arrivals > 0 {
            lines.append(L("Knocked this phone ")
                         + String(format: L("%@ time(s)"), String(describing: neighbor.arrivals)))
        }
        for line in neighbor.drift.prefix(5) {
            lines.append(L("Drift: ") + line)
        }
        lines.append(L("Census: the neighborhood — observed, ")
                     + L("never knocked for this page"))
        return lines
    }
}

/// Scan's neighborhood board: every character on the wire,
/// each opening into its full dossier.
/// The census (fix265, widened fix275): one
/// deliberate pass over this phone's own /24,
/// collecting whoever is there into the
/// Neighborhood — the collection the Scan
/// room shows, Send offers as targets, and
/// Skelli reads aloud (Chase, 2026-10-21:
/// "i should be able to collect ip addresses
/// with the mobile ios version also" — all
/// three shapes). The first cut knocked eight
/// doors and missed most of the house: gear
/// that answers no TCP door stayed invisible
/// even awake. The wide net (fix275): first a
/// closed-door knock on every address — a
/// fast refusal is a live host, and live
/// hosts are collected even with no door
/// open; then the full door list on the live
/// hosts only; meanwhile a Bonjour battery
/// (the service types the house declares)
/// resolves names to addresses, and an SSDP
/// round calls the UPnP gear. A census is a
/// sweep under the Standard: where sweeps
/// are forbidden, it does not run.
final class AddressCensus: NSObject, ObservableObject,
                           NetServiceBrowserDelegate,
                           NetServiceDelegate {
    static let shared = AddressCensus()

    @Published private(set) var running = false
    @Published private(set) var lastRun: Date?
    @Published private(set) var lastCount = 0

    private let queue = DispatchQueue(
        label: "nightjar.census",
        attributes: .concurrent)
    /// NWConnection starts and their deadline
    /// timers live here, NOT on `queue` — the
    /// Scan bench's standing lesson (fix268:
    /// the first census starved to death
    /// exactly this way): the probe workers
    /// block `queue` on their semaphore, so a
    /// connection started there waits behind
    /// its own gating and never answers.
    private let connectionQueue = DispatchQueue(
        label: "nightjar.census-connections")

    /// The discovery doors, from the trace's own
    /// stored list — one fallback for every reader.
    static var discoveryPorts: [Int] {
        let text = UserDefaults.standard.string(
            forKey: "traceDiscoveryPorts")
            ?? "80,443,22,445,1883,8080,8443,9100"
        let ports = Array(Set(text
            .split(separator: ",")
            .compactMap {
                Int($0.trimmingCharacters(
                    in: .whitespaces))
            }
            .filter { (1...65535).contains($0) }))
            .sorted()
        return ports.isEmpty ? [80, 443, 22] : ports
    }

    /// The wide net's extra doors (fix275):
    /// DNS, NetBIOS, AFP, printing, RDP, media
    /// servers, cast receivers, and 62078 —
    /// the lockdown door every Apple device
    /// answers. Knocked on live hosts only.
    private static let extraDoors: [Int] = [
        53, 139, 548, 631, 3389, 3689, 5000,
        5001, 5555, 7000, 8008, 8009, 8888,
        9090, 32400, 62078,
    ]

    /// A door nobody keeps: the liveness knock.
    private static let closedDoor = 59999

    /// The Bonjour battery: the service types
    /// the house declares in its Info.plist,
    /// each with the name she files it under.
    private static let serviceTypes:
        [(type: String, label: String)] = [
        ("_nightjar._tcp", "nightjar"),
        ("_http._tcp", "HTTP"),
        ("_https._tcp", "HTTPS"),
        ("_airplay._tcp", "AirPlay"),
        ("_raop._tcp", "AirPlay audio"),
        ("_googlecast._tcp", "Google Cast"),
        ("_printer._tcp", "Printer"),
        ("_ipp._tcp", "Printer (IPP)"),
        ("_device-info._tcp", "Device info"),
        ("_apple-mobdev2._tcp", "Apple device"),
        ("_companion-link._tcp", "Apple companion"),
        ("_ssh._tcp", "SSH"),
        ("_smb._tcp", "SMB share"),
        ("_afpovertcp._tcp", "AFP share"),
        ("_hap._tcp", "HomeKit"),
        ("_sonos._tcp", "Sonos"),
        ("_spotify-connect._tcp", "Spotify Connect"),
        ("_mqtt._tcp", "MQTT"),
        ("_airdrop._tcp", "AirDrop"),
    ]

    // One run's service finds (Bonjour + SSDP),
    // recorded in the settle, in order.
    private var browsers: [NetServiceBrowser] = []
    private var resolving: [String: NetService] = [:]
    private var serviceLabels: [String: String] = [:]
    private var serviceResults:
        [(ip: String, name: String, label: String)] = []
    private let serviceLock = NSLock()
    private var censusPrefix: String?
    private var censusOwn: String?
    private var ssdpListener: NWListener?
    private var ssdpSender: NWConnection?

    private enum Knock {
        case open, refused, silent
    }

    /// Run the pass. The completion receives the
    /// neighbors standing on this wire, ordered
    /// by address — the collection as it stands
    /// the moment the pass ends. When the pass
    /// cannot run (already running, silenced by
    /// the Standard, no wire), the completion
    /// receives the collection as it stands.
    func run(completion: (([Neighbor]) -> Void)? = nil) {
        let standing = NeighborhoodStore.shared.neighbors
        guard !running,
              !EmconStandard.refused(.sweep),
              let own = Mouth.localIPAddress()
        else { completion?(standing); return }
        let parts = own.split(separator: ".")
        guard parts.count == 4
        else { completion?(standing); return }
        let prefix = parts.dropLast()
            .joined(separator: ".") + "."
        censusPrefix = prefix
        censusOwn = own
        let doors = Array(Set(Self.discoveryPorts
            + Self.extraDoors)).sorted()
        running = true
        let boardID = ProcessBoard.shared.begin(
            label: L("Census — collecting addresses"),
            organ: "Scan",
            detail: L("across the /24"),
            stop: nil)

        var openAnswers: [SweepHost] = []
        var liveOctets: Set<Int> = []
        let resultsLock = NSLock()
        let outer = DispatchGroup()
        // Three legs ride the group: the door
        // work, the Bonjour window, the SSDP
        // window.
        outer.enter()
        outer.enter()
        outer.enter()

        // The service legs open first; they
        // listen while the knocks fly.
        startServiceBattery()
        startSSDP()
        queue.asyncAfter(deadline: .now() + 7.0) {
            outer.leave()
        }
        queue.asyncAfter(deadline: .now() + 4.5) {
            outer.leave()
        }

        // Phase A: who is alive at all — one
        // closed-door knock per address. A
        // refusal comes back at wire speed; a
        // dead address costs the deadline.
        let phaseA = DispatchGroup()
        let semA = DispatchSemaphore(value: 64)
        for octet in 1...254 {
            let ip = prefix + "\(octet)"
            if ip == own { continue }
            phaseA.enter()
            queue.async {
                semA.wait()
                self.knock(host: ip,
                           port: Self.closedDoor,
                           deadline: 0.55) { outcome in
                    if outcome != .silent {
                        resultsLock.lock()
                        liveOctets.insert(octet)
                        resultsLock.unlock()
                    }
                    semA.signal()
                    phaseA.leave()
                }
            }
        }
        // Phase B: the full door list, live
        // hosts only — fast, because the dead
        // two hundred are already excused.
        phaseA.notify(queue: queue) {
            resultsLock.lock()
            let live = liveOctets
            resultsLock.unlock()
            let phaseB = DispatchGroup()
            let semB = DispatchSemaphore(value: 48)
            for octet in live {
                let ip = prefix + "\(octet)"
                for port in doors {
                    phaseB.enter()
                    queue.async {
                        semB.wait()
                        self.knock(host: ip,
                                   port: port,
                                   deadline: 0.45) {
                            outcome in
                            if outcome == .open {
                                resultsLock.lock()
                                openAnswers.append(
                                    SweepHost(
                                        ip: ip,
                                        octet: octet,
                                        port: port))
                                resultsLock.unlock()
                            }
                            semB.signal()
                            phaseB.leave()
                        }
                    }
                }
            }
            phaseB.notify(queue: queue) {
                outer.leave()
            }
        }

        outer.notify(queue: .main) {
            self.running = false
            self.lastRun = Date()
            self.stopServiceBattery()
            self.stopSSDP()
            self.serviceLock.lock()
            let services = self.serviceResults
            self.serviceResults = []
            self.serviceLock.unlock()
            // The recording order is the fix270
            // discipline, kept: service finds
            // first — each recordBonjour pass is
            // enqueued ahead of the sweep pass
            // below (the main queue is FIFO), so
            // the board read inside its
            // completion sees every door's work
            // landed.
            var seen = Set<String>()
            for result in services {
                let key = result.ip + "|"
                    + result.label
                guard seen.insert(key).inserted
                else { continue }
                NeighborhoodStore.shared
                    .recordBonjour(ip: result.ip,
                                   name: result.name,
                                   label: result.label)
            }
            resultsLock.lock()
            var rows = openAnswers
            for octet in liveOctets {
                rows.append(SweepHost(
                    ip: prefix + "\(octet)",
                    octet: octet, port: 0))
            }
            resultsLock.unlock()
            NeighborhoodStore.shared
                .recordSweep(rows) {
                    let wire = NeighborhoodStore
                        .shared.neighbors
                        .filter {
                            $0.ip.hasPrefix(prefix)
                        }
                        .sorted { lhs, rhs in
                            let lo = Int(lhs.ip
                                .split(
                                    separator: ".")
                                .last ?? "") ?? 0
                            let ro = Int(rhs.ip
                                .split(
                                    separator: ".")
                                .last ?? "") ?? 0
                            return lo < ro
                        }
                    self.lastCount = wire.count
                    ProcessBoard.shared.end(
                        boardID, .done(
                            String(format: L("%@ address(es) collected"), String(describing: wire.count))))
                    completion?(wire)
                }
        }
    }

    /// One knock, three outcomes (fix275): a
    /// door that opens; a refusal that lands
    /// well inside the deadline — a live host
    /// with the door shut; or silence — nobody
    /// there, or a host dropping everything.
    private func knock(host: String, port: Int,
                       deadline: TimeInterval,
                       done: @escaping (Knock) -> Void) {
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(clamping: port))
        else { done(.silent); return }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort, using: .tcp)
        let started = Date()
        let finishLock = NSLock()
        var finished = false
        let finish: (Knock) -> Void = { outcome in
            finishLock.lock()
            defer { finishLock.unlock() }
            guard !finished else { return }
            finished = true
            connection.cancel()
            done(outcome)
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(.open)
            case .failed, .cancelled:
                finish(Date().timeIntervalSince(started)
                       < deadline * 0.8
                       ? .refused : .silent)
            default: break
            }
        }
        connection.start(queue: connectionQueue)
        connectionQueue.asyncAfter(
            deadline: .now() + deadline) {
            finish(.silent)
        }
    }

    // MARK: the Bonjour battery

    private func startServiceBattery() {
        for entry in Self.serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.schedule(in: .main,
                             forMode: .default)
            browser.searchForServices(
                ofType: entry.type, inDomain: "local.")
            browsers.append(browser)
        }
    }

    private func stopServiceBattery() {
        for browser in browsers {
            browser.stop()
            browser.remove(from: .main,
                           forMode: .default)
        }
        browsers = []
        for service in resolving.values {
            service.stop()
        }
        resolving = [:]
        serviceLabels = [:]
    }

    private func label(forType type: String) -> String {
        Self.serviceTypes.first {
            $0.type == type
        }?.label ?? type
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool) {
        let key = service.type + "|" + service.name
        serviceLabels[key] = label(forType: service.type)
        resolving[key] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(
        _ sender: NetService) {
        let key = sender.type + "|" + sender.name
        let label = serviceLabels[key]
            ?? label(forType: sender.type)
        resolving.removeValue(forKey: key)
        serviceLabels.removeValue(forKey: key)
        guard let prefix = censusPrefix else { return }
        for address in sender.addresses ?? [] {
            guard let ip = ipv4String(from: address),
                  ip.hasPrefix(prefix),
                  ip != censusOwn
            else { continue }
            serviceLock.lock()
            serviceResults.append(
                (ip: ip, name: sender.name,
                 label: label))
            serviceLock.unlock()
        }
    }

    func netService(
        _ sender: NetService,
        didNotResolve errorDict: [String: NSNumber]) {
        let key = sender.type + "|" + sender.name
        resolving.removeValue(forKey: key)
        serviceLabels.removeValue(forKey: key)
    }

    /// A resolved service address, read as an
    /// IPv4 string — the sockaddr's own bytes.
    private func ipv4String(from address: Data)
        -> String? {
        address.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress
            else { return nil }
            let family = base.assumingMemoryBound(
                to: sockaddr.self).pointee.sa_family
            guard family == sa_family_t(AF_INET)
            else { return nil }
            var sin = base.assumingMemoryBound(
                to: sockaddr_in.self).pointee
            var buffer = [CChar](
                repeating: 0,
                count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET,
                            &sin.sin_addr,
                            &buffer,
                            socklen_t(INET_ADDRSTRLEN))
                    != nil
            else { return nil }
            return String(cString: buffer)
        }
    }

    // MARK: the SSDP round

    /// One M-SEARCH call into the multicast
    /// dark, shouted twice: the listener takes
    /// an ephemeral UDP port, the sender binds
    /// that same port and calls — so replies
    /// land on the listener as connections
    /// whose far end names the responder.
    private func startSSDP() {
        let listener: NWListener
        do {
            listener = try NWListener(using: .udp)
        } catch { return }
        ssdpListener = listener
        listener.newConnectionHandler = {
            [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.start(queue: self.connectionQueue)
            connection.receiveMessage {
                data, _, _, _ in
                if let data {
                    self.noteSSDP(data,
                                  from: connection)
                }
                connection.cancel()
            }
        }
        listener.stateUpdateHandler = {
            [weak self] state in
            guard let self else { return }
            if case .ready = state,
               let port = listener.port {
                let params = NWParameters.udp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint =
                    .hostPort(host: "0.0.0.0",
                              port: port)
                let sender = NWConnection(
                    host: NWEndpoint.Host(
                        "239.255.255.250"),
                    port: 1900, using: params)
                self.ssdpSender = sender
                sender.stateUpdateHandler = { s in
                    if case .ready = s {
                        let search = "M-SEARCH * HTTP/1.1\r\n"
                            + "HOST: 239.255.255.250:1900\r\n"
                            + "MAN: \"ssdp:discover\"\r\n"
                            + "MX: 2\r\n"
                            + "ST: ssdp:all\r\n\r\n"
                        sender.send(
                            content: Data(search.utf8),
                            completion:
                                .contentProcessed { _ in })
                        self.connectionQueue.asyncAfter(
                            deadline: .now() + 1.4) {
                            sender.send(
                                content: Data(
                                    search.utf8),
                                completion:
                                    .contentProcessed { _ in })
                        }
                    }
                }
                sender.start(queue: self.connectionQueue)
            }
        }
        listener.start(queue: connectionQueue)
    }

    private func stopSSDP() {
        ssdpSender?.cancel()
        ssdpSender = nil
        ssdpListener?.cancel()
        ssdpListener = nil
    }

    private func noteSSDP(_ data: Data,
                          from connection: NWConnection) {
        guard let text = String(data: data,
                                encoding: .utf8),
              let endpoint = connection.currentPath?
                .remoteEndpoint,
              case .hostPort(let host, _) = endpoint
        else { return }
        let ip = "\(host)"
        guard let prefix = censusPrefix,
              ip.hasPrefix(prefix),
              ip != censusOwn
        else { return }
        var name = "SSDP device"
        for line in text.components(
            separatedBy: "\r\n") {
            let low = line.lowercased()
            if low.hasPrefix("server:") {
                name = String(line.dropFirst(7))
                    .trimmingCharacters(
                        in: .whitespaces)
            } else if low.hasPrefix("st:"),
                      name == "SSDP device" {
                name = String(line.dropFirst(3))
                    .trimmingCharacters(
                        in: .whitespaces)
            }
        }
        serviceLock.lock()
        serviceResults.append(
            (ip: ip, name: name, label: "SSDP"))
        serviceLock.unlock()
    }
}

struct NeighborhoodSectionView: View {
    @ObservedObject var store: NeighborhoodStore
    @ObservedObject private var census =
        AddressCensus.shared
    @ObservedObject private var tomato =
        TomatoMarks.shared
    @Binding var editing: Neighbor?
    @Binding var dossier: DossierPresentation?
    @Binding var administer: Neighbor?
    @Binding var clearRequest: Bool
    @State private var boardOpen = false

    var body: some View {
        Section(header: Text(L("The Neighborhood — this wire, kept")),
                footer: Text(L("Fed only by what this phone itself observes: sweeps it ran, announcements it heard, knocks at its own door. An address is a character, never a person — and nothing here is followed off this network."))) {
            if EmconStandard.refused(.sweep) {
                Text(L("The Standard forbids sweeps at this condition — the census stays silent."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    census.run { _ in
                        boardOpen = true
                    }
                } label: {
                    Label(census.running
                            ? L("Collecting…")
                            : L("Collect addresses"),
                          systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(census.running)
            }
            if store.neighbors.isEmpty {
                Text(L("No neighbors yet. Run a sweep, let Bonjour resolve, or simply be knocked — the wire will populate its own cast."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Button {
                    withAnimation { boardOpen.toggle() }
                } label: {
                    HStack {
                        Label(L("Devices"), systemImage: "house")
                        Spacer()
                        Text("\(store.neighbors.count)")
                            .foregroundStyle(.secondary)
                        Image(systemName: boardOpen
                              ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            if boardOpen {
            ForEach(store.neighbors) { neighbor in
                Button {
                    dossier = DossierPresentation(
                        title: neighbor.displayName,
                        ip: neighbor.ip,
                        wifiLines: store.wifiLines(for: neighbor),
                        wireName: neighbor.name)
                } label: {
                    HStack(spacing: 8) {
                        if tomato.isMarked(neighbor.ip) {
                            Text("🍅").font(.callout)
                        }
                        if let mark = neighbor.customMark {
                            Image(systemName: mark)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(neighbor.displayName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(neighborCaption(neighbor))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contextMenu {
                    Button {
                        administer = neighbor
                    } label: {
                        Label("Administer\u{2026}",
                              systemImage: "wrench.and.screwdriver")
                    }
                    Button {
                        editing = neighbor
                    } label: {
                        Label(L("Name this device…"),
                              systemImage: "pencil")
                    }
                    Button {
                        if tomato.isMarked(neighbor.ip) {
                            tomato.unmark(neighbor.ip)
                            Journal.log(
                                "tomato", "unmark",
                                "\(neighbor.displayName) "
                                    + "(\(neighbor.ip))")
                        } else {
                            tomato.mark(neighbor.ip)
                            Journal.log(
                                "tomato", "mark",
                                "\(neighbor.displayName) "
                                    + "(\(neighbor.ip))")
                        }
                    } label: {
                        Label(tomato.isMarked(neighbor.ip)
                                ? L("Wipe the tomato off")
                                : L("Throw a tomato"),
                              systemImage: tomato
                                .isMarked(neighbor.ip)
                                ? "arrow.uturn.backward"
                                : "target")
                    }
                }
            }
            }
            if !store.neighbors.isEmpty {
                Button(role: .destructive) {
                    clearRequest = true
                } label: {
                    Label(L("Clear the Neighborhood"),
                          systemImage: "trash")
                }
            }
        }
    }

    private func neighborCaption(_ neighbor: Neighbor) -> String {
        var parts: [String] = []
        if neighbor.customName != nil {
            parts.append(neighbor.ip)
            if let wire = neighbor.name {
                parts.append(String(format: L("answers as %@"), String(describing: wire)))
            }
        } else if neighbor.name != nil {
            parts.append(neighbor.ip)
        }
        parts.append(String(format: L("%@ sightings"), String(describing: neighbor.sightings)))
        parts.append(neighbor.lastSeenLine)
        if !neighbor.ports.isEmpty {
            parts.append(L("ports ") + neighbor.ports
                .map(String.init).joined(separator: ", "))
        }
        if neighbor.arrivals > 0 {
            parts.append(String(format: L("knocked us %@×"), String(describing: neighbor.arrivals)))
        }
        if let latest = neighbor.drift.first {
            parts.append(L("drift: ") + latest)
        }
        return parts.joined(separator: " · ")
    }
}


/// Name a device, and give it a mark to be told apart by.
/// The name is the operator's word for the address, kept in
/// the neighbor's own file — it follows the device into the
/// Map, its dossier, and the Subconscious's findings.
struct NeighborNameEditor: View {
    @ObservedObject var store: NeighborhoodStore
    let neighbor: Neighbor
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var mark: String?

    private static let marks: [String] = [
        "house.fill", "tv.fill", "laptopcomputer",
        "desktopcomputer", "iphone", "gamecontroller.fill",
        "video.fill", "speaker.wave.3.fill", "printer.fill",
        "network", "lock.fill", "questionmark.circle",
    ]

    init(store: NeighborhoodStore, neighbor: Neighbor) {
        self.store = store
        self.neighbor = neighbor
        _draft = State(initialValue: neighbor.customName ?? "")
        _mark = State(initialValue: neighbor.customMark)
    }

    private var wireNameFooter: String {
        String(format: L("The wire calls it %@. Your name outranks the wire's everywhere in the app."),
               neighbor.name ?? neighbor.ip)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("Its name here")),
                        footer: Text(wireNameFooter)) {
                    TextField(neighbor.name ?? neighbor.ip,
                              text: $draft)
                        .disableAutocorrection(true)
                }
                Section(header: Text(L("Its mark"))) {
                    LazyVGrid(columns: [GridItem(.adaptive(
                        minimum: 52))], spacing: 12) {
                        ForEach(Self.marks, id: \.self) { symbol in
                            Button {
                                mark = (mark == symbol)
                                    ? nil : symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(
                                            cornerRadius: 10)
                                            .fill(mark == symbol
                                                  ? Color.accentColor
                                                    .opacity(0.3)
                                                  : Color.white
                                                    .opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if neighbor.customName != nil {
                    Section {
                        Button(L("Clear the given name"),
                               role: .destructive) {
                            store.rename(ip: neighbor.ip, to: nil,
                                         mark: nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(L("Name this device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        store.rename(ip: neighbor.ip, to: draft,
                                     mark: mark)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Administer one neighbor (Netadmin Phase 4b):
/// the levers the house honestly holds for a
/// device, on one sheet — walk its MIB, grade
/// its SNMP posture against the NSA's sheet, or
/// quarantine it at the gear. Every lever rides
/// the operator's own kept credentials and the
/// same engines the console runs; what a lever
/// cannot do — probing dark under EMCON, no
/// credential kept for the gear — is said on
/// the sheet, in the open, never faked.
struct AdministerSheetView: View {
    let neighbor: Neighbor
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var running = false

    private var gearIP: String? {
        BlacksiteNet.defaultGatewayIP()
    }
    private var gearCommunity: String? {
        gearIP.flatMap {
            CryptoSuite.NetCred.secret(for: $0)
        }
    }
    private var probingDark: Bool {
        EmconStandard.refused(.probing)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent {
                        Text(neighbor.ip)
                    } label: {
                        Text(L("Address"))
                    }
                    if let wire = neighbor.name {
                        LabeledContent {
                            Text(wire)
                        } label: {
                            Text(L("Answers as"))
                        }
                    }
                }
                Section(header: Text(L("Administer"))) {
                    Button {
                        walk()
                    } label: {
                        Label(L("Walk (SNMP)"),
                              systemImage: "list.bullet.indent")
                    }
                    .disabled(running || probingDark)
                    Button {
                        audit()
                    } label: {
                        Label(L("Audit posture"),
                              systemImage: "checklist")
                    }
                    .disabled(running || probingDark)
                    if probingDark {
                        Text(String(format: L("Probing is dark under EMCON %@."),
                                    EmconCondition.current.name))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        quarantine(down: true)
                    } label: {
                        Label(L("Quarantine this device"),
                              systemImage: "nosign")
                    }
                    .disabled(running || gearCommunity == nil)
                    Button {
                        quarantine(down: false)
                    } label: {
                        Label(L("Lift the quarantine"),
                              systemImage: "arrow.uturn.backward")
                    }
                    .disabled(running || gearCommunity == nil)
                    if gearCommunity == nil {
                        Text(L("Quarantine rides the gear's kept credential — none is kept, so the lever is dark."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if running || !lines.isEmpty {
                    Section(header: Text(L("The run"))) {
                        if running {
                            Text(L("Working…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(lines.enumerated()),
                                id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle(neighbor.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func append(_ text: String) {
        DispatchQueue.main.async {
            lines.append(text)
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            running = false
        }
    }

    private func walk() {
        lines = []
        running = true
        let kept = CryptoSuite.NetCred
            .secret(for: neighbor.ip)
        if kept == nil {
            lines.append(L("No credential kept for this device — the walk rides the factory word."))
        }
        BlacksitePentest.snmpWalk(
            host: neighbor.ip,
            community: kept ?? "public",
            root: "1.3.6.1.2.1",
            emit: { text, _ in append(text) },
            done: { finish() })
    }

    private func audit() {
        lines = []
        running = true
        BlacksitePentest.snmpAudit(
            host: neighbor.ip,
            emit: { text, _ in append(text) },
            done: { finish() })
    }

    private func quarantine(down: Bool) {
        guard let gear = gearIP,
              let community = gearCommunity
        else { return }
        lines = []
        running = true
        let target = neighbor.ip
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let out = BlacksitePentest.quarantine(
                    targetIP: target, gearIP: gear,
                    community: community, down: down)
                DispatchQueue.main.async {
                    lines = out
                    running = false
                }
            }
    }
}
