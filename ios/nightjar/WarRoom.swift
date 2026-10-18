import SwiftUI

// MARK: - The unified timeline
//
// One operation, one story. Every engine in the room — Listen,
// the trace, the knock bench — reports into a single timestamped
// timeline in this one shape, so a run can be read top to bottom
// as it happened. The SIGINT station reads the same types: an
// event is an event, whichever room collected it.

struct WarEvent: Identifiable, Codable {
    enum Kind: String, Codable {
        case run       // the operation itself: started, stopped, done
        case sighting  // a BLE device heard by Listen
        case host      // a host found on the wire
        case door      // a service confirmed on a host
        case banner    // a known door answering differently
        case recon     // a knock verdict
        case note      // anything else worth the record
    }

    var id: String
    var at: Date
    var kind: Kind
    var label: String
    var detail: String
    var source: String   // "war-room" | "listen" | "trace" | "recon"

    init(kind: Kind, label: String, detail: String = "",
         source: String, at: Date = Date()) {
        self.id = UUID().uuidString
        self.at = at
        self.kind = kind
        self.label = label
        self.detail = detail
        self.source = source
    }
}

/// One knock, as the War Room files it: which door, which wire,
/// what the bench concluded.
struct WarReconHit: Codable {
    var host: String
    var port: Int
    var udp: Bool
    var state: String
    var service: String
    var banner: String
    var confirmed: Bool

    var isOpen: Bool { state == "open" }
}

/// The wrapper document: one JSON carrying the whole operation —
/// the run's own timeline and knock record, and the trace's own
/// export embedded whole rather than summarised, so nothing the
/// trace knew is lost in the wrapping.
struct WarRoomExport: Codable {
    struct RunInfo: Codable {
        var id: String
        var startedAt: Date
        var endedAt: Date
        var subnet: String
        var includedBLE: Bool
        var listenStartedByRun: Bool
        var stoppedEarly: Bool
    }

    var schema: String
    var schemaVersion: Int
    var run: RunInfo
    var timeline: [WarEvent]
    var reconHits: [WarReconHit]
    var trace: TraceExport?
    var limitations: [String]

    static let limitations = [
        "Foreground only: the run lives while this screen is "
            + "open. iOS suspends the engines in the background.",
        "The BLE side is heard, never probed — Listen is "
            + "receive-only, and the War Room keeps it that way.",
        "The trace sees TCP: a host answering nothing on the "
            + "knocked ports is invisible to it (the trace "
            + "export lists its own limits in full).",
        "Knocks speak each port's own expected protocol "
            + "(the Recon bench's behaviour) on the operator's "
            + "own wire, against doors this run's trace found.",
    ]
}

// MARK: - The run's settings
//
// Read from the same persisted keys the Trace section and the
// Recon bench use, so the War Room runs the operator's standing
// configuration — the War Chest can redress all of it at once.

struct WarConfig {
    var scopeText: String
    var discoveryPorts: [Int]
    var profilePorts: [Int]
    var includeBonjour: Bool
    var adaptive: Bool
    var rulesText: String
    var includeBLE: Bool
    var knockTimeout: Double
    var knockJobs: Int
}

// MARK: - The coordinator

/// Runs one operation: Listen up (if the air is wanted), the
/// trace across one named /24, then the knock bench against
/// every door the trace confirmed — all of it feeding the one
/// timeline. Operator-started, foreground, stoppable.
final class WarRun: ObservableObject {
    /// The room's own console keeps its own run; this one is
    /// Skelli's, so a run she starts is a run with its own
    /// coordinator — and the trace's own busy guard keeps
    /// the two from ever colliding on the wire.
    static let shared = WarRun()

    enum Phase: String {
        case idle = "Ready"
        case tracing = "Tracing the wire"
        case knocking = "Knocking the doors found"
        case complete = "Complete"
        case stopped = "Stopped"
        case failed = "Failed to start"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var events: [WarEvent] = []
    @Published private(set) var reconHits: [WarReconHit] = []
    @Published private(set) var exportURL: URL?
    @Published private(set) var statusLine: String?

    var running: Bool { phase == .tracing || phase == .knocking }

    private var timer: Timer?
    private weak var mouth: Mouth?
    private weak var post: ListeningPost?
    /// Held, not weak: a run Skelli starts hands over a
    /// bench of her own, and the run must keep it alive for
    /// as long as the knocks run. The console's bench is
    /// owned by its view and outlives the run either way.
    private var recon: Recon?
    private var book: PayloadBook?

    private var runID = ""
    private var startedAt = Date()
    private var base = ""
    private var config: WarConfig?
    private var startedListen = false
    private var sawTraceBusy = false
    private var graceTicks = 0

    // The run's memory: what was already known when it began,
    // so the timeline tells this run's story, not the logbook's.
    private var knownListenIDs: Set<String> = []
    private var knownHosts: Set<String> = []
    private var knownDoors: Set<String> = []
    private var doorSignatures: [String: String] = [:]

    private var knockPlan: [(host: String, ports: [Int], udp: Bool)] = []
    private var knockIndex = 0
    private var knockInFlight = false

    // MARK: start / stop

    func start(mouth: Mouth, post: ListeningPost, recon: Recon,
               book: PayloadBook, config: WarConfig) {
        guard !running else { return }
        guard !mouth.traceBusy else {
            phase = .blocked
            statusLine = "The trace is already working — "
                + "a run waits for the wire to free."
            return
        }
        self.mouth = mouth
        self.post = post
        self.recon = recon
        self.book = book
        self.config = config
        recon.mouth = mouth

        guard let ownIP = Mouth.localIPAddress(),
              let subnet = Mouth.sweepBase(config.scopeText,
                                           ownIP: ownIP) else {
            phase = .failed
            statusLine = "Couldn't read that scope — blank means "
                + "this phone's /24; otherwise an address in the "
                + "/24 or its base."
            return
        }
        base = subnet
        startedAt = Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        runID = "warroom-" + stamp.string(from: startedAt)

        events = []
        reconHits = []
        exportURL = nil
        sawTraceBusy = false
        graceTicks = 0
        knockPlan = []
        knockIndex = 0
        knockInFlight = false

        // Baselines: the world as it stood when the run began.
        let baseline = TraceBookStore.shared.scopeDossiers(base: base)
        knownHosts = Set(baseline.map { $0.ip })
        knownDoors = []
        doorSignatures = [:]
        for host in baseline {
            for service in host.services {
                let key = doorKey(host.ip, service)
                knownDoors.insert(key)
                doorSignatures[key] = service.signature
            }
        }
        knownListenIDs = Set(post.rows.map { $0.id })

        if config.includeBLE, post.session == nil {
            post.start(label: "War Room")
            startedListen = true
        } else {
            startedListen = false
        }

        addEvent(.run, "War Room run started",
                 detail: "\(base).0/24"
                    + (config.includeBLE ? " · air included" : " · wire only"),
                 source: "war-room")
        if startedListen {
            addEvent(.note, "Listen started for this run",
                     detail: "It stops again when the run ends — "
                        + "the room is left as it was found.",
                     source: "listen")
        }
        Journal.log("war-room", "run",
                    "run \(runID) started on \(base).0/24")

        phase = .tracing
        mouth.startNetworkTrace(
            scopeText: config.scopeText,
            discoveryPorts: config.discoveryPorts,
            profilePorts: config.profilePorts,
            includeBonjour: config.includeBonjour,
            adaptive: config.adaptive,
            rules: TraceRule.parse(config.rulesText),
            probeFor: { [weak self] target in
                self?.probeForTarget(target)
            },
            payloadNamed: { [weak self] name in
                self?.payloadNamed(name)
            })

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5,
                                     repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// Operator stop: halt whichever engine is working and close
    /// the run out with whatever the timeline already holds.
    func stop() {
        guard running else { return }
        if phase == .tracing { mouth?.stopNetworkTrace() }
        if phase == .knocking { recon?.cancelKnock() }
        addEvent(.run, "Run stopped by the operator",
                 source: "war-room")
        finish(stopped: true)
    }

    /// The sheet went away mid-run: close out cleanly rather
    /// than leave engines running under a dead coordinator.
    func detach() {
        guard running else { return }
        stop()
    }

    func clearTimeline() {
        guard !running else { return }
        events = []
        reconHits = []
        exportURL = nil
        phase = .idle
        statusLine = nil
    }

    // MARK: the watch

    private func tick() {
        guard running, let mouth = mouth else { return }
        switch phase {
        case .tracing:
            if mouth.traceBusy { sawTraceBusy = true }
            watchWire()
            if config?.includeBLE == true { watchAir() }
            if sawTraceBusy, !mouth.traceBusy {
                beginKnocks()
            } else if !sawTraceBusy {
                graceTicks += 1
                if graceTicks > 4 {
                    // The trace refused (busy elsewhere, bad
                    // ports): its own status says why.
                    statusLine = mouth.traceStatus
                    addEvent(.note, "The trace did not start",
                             detail: mouth.traceStatus ?? "",
                             source: "trace")
                    phase = .failed
                    finish(stopped: false, failed: true)
                }
            }
        case .knocking:
            tickKnocks()
        default:
            break
        }
    }

    /// Diff the logbook's picture of the scope against the run's
    /// memory: new hosts, new doors, changed banners.
    private func watchWire() {
        let dossiers = TraceBookStore.shared.scopeDossiers(base: base)
        for host in dossiers {
            if !knownHosts.contains(host.ip) {
                knownHosts.insert(host.ip)
                let name = host.names.first ?? ""
                addEvent(.host, "Host \(host.ip)",
                         detail: name, source: "trace")
            }
            for service in host.services {
                let key = doorKey(host.ip, service)
                if !knownDoors.contains(key) {
                    knownDoors.insert(key)
                    doorSignatures[key] = service.signature
                    addEvent(.door,
                             "Door \(host.ip):\(service.port)/\(service.proto)",
                             detail: service.bannerFirstLine.isEmpty
                                ? service.serviceName
                                : service.bannerFirstLine,
                             source: "trace")
                } else if let old = doorSignatures[key],
                          old != service.signature {
                    doorSignatures[key] = service.signature
                    addEvent(.banner,
                             "Banner changed \(host.ip):\(service.port)",
                             detail: service.bannerFirstLine,
                             source: "trace")
                }
            }
        }
    }

    /// New BLE devices heard since the run began.
    private func watchAir() {
        guard let post = post else { return }
        for row in post.rows where !knownListenIDs.contains(row.id) {
            knownListenIDs.insert(row.id)
            let label = row.preferredLabel ?? row.name ?? row.kind
            var detail = row.id
            if let rssi = row.rssiLast { detail += " · \(rssi) dBm" }
            addEvent(.sighting, label, detail: detail,
                     source: "listen",
                     at: Date(timeIntervalSince1970: row.firstSeen))
        }
    }

    // MARK: the knocks

    private func beginKnocks() {
        // Doors this run actually touched: filed or re-seen
        // since it began, from the logbook's current picture.
        let grace = startedAt.addingTimeInterval(-5)
        var tcpByHost: [String: [Int]] = [:]
        var udpByHost: [String: [Int]] = [:]
        for host in TraceBookStore.shared.scopeDossiers(base: base) {
            for service in host.services
            where service.lastSeen >= grace {
                if service.proto == "udp" {
                    udpByHost[host.ip, default: []]
                        .append(service.port)
                } else {
                    tcpByHost[host.ip, default: []]
                        .append(service.port)
                }
            }
        }
        knockPlan = []
        let ips = Set(tcpByHost.keys).union(udpByHost.keys)
            .sorted(by: TraceBookStore.ipLess)
        for ip in ips {
            if let ports = tcpByHost[ip], !ports.isEmpty {
                knockPlan.append((ip, ports.sorted(), false))
            }
            if let ports = udpByHost[ip], !ports.isEmpty {
                knockPlan.append((ip, ports.sorted(), true))
            }
        }
        knockIndex = 0
        knockInFlight = false
        if knockPlan.isEmpty {
            addEvent(.note, "No doors to knock",
                     detail: "The trace found no answering "
                        + "services on this run.",
                     source: "recon")
            finish(stopped: false)
            return
        }
        phase = .knocking
        addEvent(.run, "Trace complete — knocking "
                    + "\(knockPlan.count) door group(s)",
                 source: "war-room")
    }

    private func tickKnocks() {
        guard let recon = recon, let config = config else { return }
        if knockInFlight {
            guard !recon.knocking else { return }
            knockInFlight = false
            let step = knockPlan[knockIndex]
            for hit in recon.hits {
                reconHits.append(WarReconHit(
                    host: step.host, port: hit.port, udp: hit.udp,
                    state: hit.state, service: hit.service,
                    banner: hit.banner, confirmed: hit.confirmed))
                if hit.isOpen {
                    addEvent(.recon,
                             "\(step.host):\(hit.port) answered",
                             detail: hit.confirmed
                                ? "★ answered as \(hit.service)"
                                : (hit.banner.isEmpty
                                    ? hit.service : hit.banner),
                             source: "recon")
                }
            }
            knockIndex += 1
        }
        guard knockIndex < knockPlan.count else {
            finish(stopped: false)
            return
        }
        let step = knockPlan[knockIndex]
        statusLine = "Knocking \(step.host) — "
            + "group \(knockIndex + 1)/\(knockPlan.count)"
        recon.knock(host: step.host, ports: step.ports,
                    udp: step.udp, timeout: config.knockTimeout,
                    jobs: config.knockJobs)
        knockInFlight = true
    }

    // MARK: close-out

    private func finish(stopped: Bool, failed: Bool = false) {
        timer?.invalidate()
        timer = nil
        let listenWasStarted = startedListen
        if startedListen {
            post?.stop()
            startedListen = false
        }
        if !failed {
            phase = stopped ? .stopped : .complete
            let open = reconHits.filter { $0.isOpen }.count
            addEvent(.run,
                     stopped ? "Run closed" : "Run complete",
                     detail: "\(events.count) timeline events · "
                        + "\(open) open door(s) knocked",
                     source: "war-room")
            writeExport(stopped: stopped,
                        listenWasStarted: listenWasStarted)
        }
        Journal.log("war-room", "run",
                    "run \(runID) \(failed ? "failed" : (stopped ? "stopped" : "complete")) — "
                    + "\(events.count) events, "
                    + "\(reconHits.filter { $0.isOpen }.count) open")
    }

    private func writeExport(stopped: Bool,
                             listenWasStarted: Bool) {
        var trace: TraceExport? = nil
        if let url = mouth?.traceLatestExport,
           let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            trace = try? decoder.decode(TraceExport.self, from: data)
        }
        let export = WarRoomExport(
            schema: "net.nosuchmachine.nightjar.war-room",
            schemaVersion: 1,
            run: WarRoomExport.RunInfo(
                id: runID,
                startedAt: startedAt,
                endedAt: Date(),
                subnet: "\(base).0/24",
                includedBLE: config?.includeBLE ?? false,
                listenStartedByRun: listenWasStarted,
                stoppedEarly: stopped),
            timeline: events,
            reconHits: reconHits,
            trace: trace,
            limitations: WarRoomExport.limitations)
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WarRoom", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "nightjar-" + runID + ".json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(export) {
            try? data.write(to: url, options: .atomic)
            exportURL = url
        }
    }

    // MARK: helpers

    private func doorKey(_ ip: String,
                         _ service: TraceServiceDossier) -> String {
        "\(ip):\(service.port)/\(service.proto)"
    }

    private func addEvent(_ kind: WarEvent.Kind, _ label: String,
                          detail: String = "", source: String,
                          at: Date = Date()) {
        guard events.count < 500 else { return }
        events.append(WarEvent(kind: kind, label: label,
                               detail: detail, source: source,
                               at: at))
    }

    /// The trace's probe ammunition, exactly as the Send tab
    /// supplies it: the book payload mapped to the target's
    /// port, when one is mapped.
    private func probeForTarget(_ targetText: String)
        -> (data: Data, name: String)?
    {
        guard let parsed = try? SendTarget.parse(targetText)
        else { return nil }
        let port: Int
        switch parsed {
        case .tcp(_, let p, _), .udp(_, let p): port = p
        default: return nil
        }
        guard let name = ScanModel.payloadByPort[port],
              let item = book?.items.first(where: { $0.name == name }),
              let data = try? PayloadKit.build(
                source: item.source,
                text: item.source == "text" ? item.text : "",
                hex: item.source == "hex" ? item.text : "",
                b64: item.source == "base64" ? item.text : "",
                xorSpec: item.xorKey, useGzip: item.useGzip)
        else { return nil }
        return (data, name)
    }

    private func payloadNamed(_ name: String) -> Data? {
        guard let item = book?.items.first(where: { $0.name == name })
        else { return nil }
        return try? PayloadKit.build(
            source: item.source,
            text: item.source == "text" ? item.text : "",
            hex: item.source == "hex" ? item.text : "",
            b64: item.source == "base64" ? item.text : "",
            xorSpec: item.xorKey, useGzip: item.useGzip)
    }
}

// MARK: - The room itself

struct WarRoomView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var post: ListeningPost
    @StateObject private var run = WarRun()
    @StateObject private var recon = Recon()
    @StateObject private var book = PayloadBook()
    @State private var shareItem: ShareItem?
    @State private var showAllEvents = false

    @AppStorage("traceScope") private var traceScope = ""
    @AppStorage("traceDiscoveryPorts")
    private var traceDiscoveryPorts =
        "80,443,22,445,1883,8080,8443,9100"
    @AppStorage("traceProfilePorts") private var traceProfilePorts = ""
    @AppStorage("traceBonjour") private var traceBonjour = true
    @AppStorage("traceAdaptive") private var traceAdaptive = true
    @AppStorage("traceRules") private var traceRules = ""
    @AppStorage("warRoomBLE") private var includeBLE = true
    @AppStorage("reconTimeout") private var reconTimeout = 1.5
    @AppStorage("reconJobs") private var reconJobs = 24.0

    private var subnetText: String {
        guard let ownIP = Mouth.localIPAddress(),
              let base = Mouth.sweepBase(traceScope, ownIP: ownIP)
        else { return "scope unreadable" }
        return "\(base).0/24"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(run.phase.rawValue,
                              systemImage: phaseIcon)
                            .font(.headline)
                        Spacer()
                        Text(subnetText)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if let status = run.statusLine, run.running {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("One operation: Listen (if the air is "
                        + "included) and the trace run as one, "
                        + "then the knock bench works every door "
                        + "the trace confirmed — all of it on one "
                        + "timeline, all of it in one export.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Include the air — BLE via Listen",
                           isOn: $includeBLE)
                        .disabled(run.running)
                    if run.running {
                        Button(role: .destructive) {
                            Haptics.tap()
                            run.stop()
                        } label: {
                            Label("Stop the run",
                                  systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            Haptics.tap()
                            startRun()
                        } label: {
                            Label("Start the operation",
                                  systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mouth.traceBusy || mouth.crawlBusy
                                  || mouth.talkBusy)
                        if mouth.traceBusy || mouth.crawlBusy
                            || mouth.talkBusy {
                            Text("Another engine is working — "
                                + "the War Room starts when the "
                                + "wire is free.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Foreground only, on the scope the "
                        + "Trace section is set to. The run uses "
                        + "your standing Trace and Recon settings "
                        + "— a War Chest redresses all of them "
                        + "at once.")
                }

                if !run.events.isEmpty {
                    Section("Timeline — \(run.events.count)") {
                        ForEach(visibleEvents) { event in
                            HStack(alignment: .firstTextBaseline,
                                   spacing: 8) {
                                Image(systemName: icon(for: event.kind))
                                    .foregroundStyle(color(for: event.kind))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.label)
                                        .font(.callout)
                                    if !event.detail.isEmpty {
                                        Text(event.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text(event.at.formatted(
                                    date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if run.events.count > 40 {
                            Button(showAllEvents
                                   ? "Fold — latest 40"
                                   : "Show all \(run.events.count)") {
                                showAllEvents.toggle()
                            }
                        }
                        if !run.running {
                            Button("Clear the timeline",
                                   role: .destructive) {
                                run.clearTimeline()
                                showAllEvents = false
                            }
                        }
                    }
                }

                if let url = run.exportURL {
                    Section("The record") {
                        Button {
                            Haptics.select()
                            shareItem = ShareItem(items: [url])
                        } label: {
                            Label("Share the War Room export",
                                  systemImage: "square.and.arrow.up")
                        }
                        Text("One JSON: this timeline, the "
                            + "knock record, and the trace's own "
                            + "export embedded whole.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("War Room")
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .onAppear { recon.mouth = mouth }
            .onDisappear {
                if run.running { run.detach() }
            }
        }
    }

    private var visibleEvents: [WarEvent] {
        let ordered = Array(run.events.reversed())
        return showAllEvents ? ordered : Array(ordered.prefix(40))
    }

    private var phaseIcon: String {
        switch run.phase {
        case .idle: return "circle.dashed"
        case .tracing: return "point.3.connected.trianglepath.dotted"
        case .knocking: return "target"
        case .complete: return "checkmark.circle.fill"
        case .stopped: return "stop.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func icon(for kind: WarEvent.Kind) -> String {
        switch kind {
        case .run: return "flag.fill"
        case .sighting: return "eye.fill"
        case .host: return "network"
        case .door: return "door.left.hand.open"
        case .banner: return "arrow.triangle.2.circlepath"
        case .recon: return "target"
        case .note: return "note.text"
        }
    }

    private func color(for kind: WarEvent.Kind) -> Color {
        switch kind {
        case .run: return .accentColor
        case .sighting: return .purple
        case .host: return .blue
        case .door: return .green
        case .banner: return .orange
        case .recon: return .teal
        case .note: return .secondary
        }
    }

    private func startRun() {
        let discovery = warParsePorts(traceDiscoveryPorts)
        guard !discovery.isEmpty else {
            toasts.show("The Trace section has no discovery "
                        + "ports set", error: true)
            return
        }
        let profileText = traceProfilePorts
            .trimmingCharacters(in: .whitespaces)
        run.start(mouth: mouth, post: post, recon: recon,
                  book: book,
                  config: WarConfig(
                    scopeText: traceScope,
                    discoveryPorts: discovery,
                    profilePorts: profileText.isEmpty
                        ? [] : warParsePorts(traceProfilePorts),
                    includeBonjour: traceBonjour,
                    adaptive: traceAdaptive,
                    rulesText: traceRules,
                    includeBLE: includeBLE,
                    knockTimeout: reconTimeout,
                    knockJobs: Int(reconJobs)))
        if run.phase == .failed {
            toasts.show(run.statusLine ?? "The run did not start",
                        error: true)
        }
    }
}

/// "80, 443, 22" → [22, 80, 443]: valid ports only,
/// deduplicated, in order.
private func warParsePorts(_ text: String) -> [Int] {
    Array(Set(text.split(separator: ",")
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        .filter { (1...65535).contains($0) })).sorted()
}
