import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import Network

/// Net-Assault — the house, turned loose on its own wire.
///
/// Every organ the app owns, orchestrated into one
/// continuous autonomous run: the subnet sweep on rotating
/// ports, the Bonjour browse, the recon bench knocking the
/// full census against every known neighbor — pass after
/// pass, for as long as the operator leaves it armed. What
/// it finds walks the same roads everything else does:
/// the Neighborhood learns it, the Map can place it, the
/// journal seals it, and the Subconscious reads over its
/// shoulder.
///
/// It is LOUD, and it says so before it starts and while it
/// runs: a sweep is an announcement, a knock is a knock on
/// a stranger's door, and anything on the wire that watches
/// for exactly this will see it. That warning is not fine
/// print; it is the first thing the section shows.
///
/// It uses only the house's own organs — nothing new is
/// exploited, flooded, or broken into. Things are knocked
/// on and listened to, at length, in the open.

// MARK: - The mark

/// A line-art skull and crossbones, drawn — the Jolly
/// Roger in the matrix's own geometry.
struct SkullMark: View {
    var color: Color
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvas in
            let w = canvas.width, h = canvas.height
            let stroke = StrokeStyle(lineWidth: 1.6,
                                     lineCap: .round)
            let cranium = CGRect(x: w * 0.22, y: h * 0.06,
                                 width: w * 0.56,
                                 height: h * 0.52)
            context.stroke(Path(ellipseIn: cranium),
                           with: .color(color), style: stroke)
            let jaw = CGRect(x: w * 0.37, y: h * 0.52,
                             width: w * 0.26, height: h * 0.15)
            context.stroke(
                Path(roundedRect: jaw, cornerRadius: 2),
                with: .color(color), style: stroke)
            for cx in [0.38, 0.62] {
                let eye = CGRect(x: w * cx - w * 0.055,
                                 y: h * 0.29,
                                 width: w * 0.11,
                                 height: h * 0.13)
                context.fill(Path(ellipseIn: eye),
                             with: .color(color))
            }
            let bone = StrokeStyle(lineWidth: 2.6,
                                   lineCap: .round)
            for flip in [false, true] {
                var path = Path()
                let y1 = h * 0.78, y2 = h * 0.97
                if flip {
                    path.move(to: CGPoint(x: w * 0.82, y: y1))
                    path.addLine(to: CGPoint(x: w * 0.18, y: y2))
                } else {
                    path.move(to: CGPoint(x: w * 0.18, y: y1))
                    path.addLine(to: CGPoint(x: w * 0.82, y: y2))
                }
                context.stroke(path, with: .color(color),
                               style: bone)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - The center

final class AssaultCenter: ObservableObject {
    /// One assault engine for the whole house — the EMCON
    /// tab and Skelli's hands work the same instance, so a
    /// run armed in one room is the run the other room sees.
    static let shared = AssaultCenter()

    @Published var running = false
    @Published var phase = "Standing by"
    @Published var passes = 0
    @Published var newThisRun = 0
    @Published var driftThisRun = 0
    @Published var probedThisRun = 0
    @Published var startedAt: Date?
    @Published var log: [String] = []
    /// This run's named findings — not counts, the actual
    /// news: who arrived, who drifted, who answers what,
    /// who went silent. The report is built from these.
    @Published private(set) var findings: [String] = []
    /// The last completed run's report, persisted — a
    /// relaunch no longer burns the after-action.
    @Published private(set) var lastReport: String?

    private enum Stage { case idle, sweeping, browsing,
                         knocking, resting }
    private var stage: Stage = .idle
    private var stageEnds = Date.distantPast
    private let model = ScanModel()
    private let recon = Recon()
    private var timer: Timer?
    private var knockQueue: [Neighbor] = []
    /// The sweep stage works the whole port rotation in
    /// one pass now — a device that only answers on 443
    /// no longer waits five passes to be found.
    private var sweepQueue: [Int] = []
    /// Pass baselines, for naming what THIS pass found.
    private var passIPs: Set<String> = []
    private var passDrift: [String: Int] = [:]
    /// Consecutive passes that found nothing — the wire
    /// is quiet, so the rest between passes backs off.
    private var quietStreak = 0
    /// The host currently under the knock, for harvesting
    /// its answers when the bench finishes.
    private var knockingNow: Neighbor?
    private var browseStarted = Date.distantPast
    private var browseCountAtStart = 0
    private var boardID: UUID?
    private static let lastReportKey = "assault.lastReport"

    // MARK: - knock memory

    /// What the knocking stage remembers per neighbor,
    /// persisted across runs: when it was knocked, how
    /// much drift it carried then, the ports it had
    /// answered, and on which pass. Until now the
    /// stage was amnesiac — every pass re-knocked the
    /// identical full census against the twelve most
    /// recently seen, forever: an unchanged cast got
    /// the same thousand questions on pass eleven as
    /// on pass one, and a changed device waited
    /// behind static ones.
    private static let knockKey = "assaultKnock"

    private struct KnockRecord {
        var lastKnocked: TimeInterval = 0
        var driftSeen: Int = 0
        var ports: [Int] = []
        var cycle: Int = 0
    }

    private static func loadKnockRecords()
        -> [String: KnockRecord] {
        let raw = UserDefaults.standard.dictionary(
            forKey: knockKey)
            as? [String: [String: Any]] ?? [:]
        return raw.mapValues {
            KnockRecord(
                lastKnocked: $0["lastKnocked"] as? Double ?? 0,
                driftSeen: $0["driftSeen"] as? Int ?? 0,
                ports: $0["ports"] as? [Int] ?? [],
                cycle: $0["cycle"] as? Int ?? 0)
        }
    }

    private static func saveKnockRecords(
        _ records: [String: KnockRecord]) {
        let raw = records.mapValues {
            ["lastKnocked": $0.lastKnocked,
             "driftSeen": $0.driftSeen,
             "ports": $0.ports,
             "cycle": $0.cycle] as [String: Any]
        }
        UserDefaults.standard.set(raw, forKey: knockKey)
    }
    private var baseNeighbors = 0
    private var baseDrift = 0
    private var cycle = 0
    private let sweepPorts = [80, 443, 22, 8080, 8443]

    private var depth: Int {
        // Unset means the picker's own default: Full.
        UserDefaults.standard.object(forKey: "assault.depth")
            as? Int ?? 2
    }
    private var restSeconds: Double {
        let v = UserDefaults.standard.double(
            forKey: "assault.rest")
        return v > 0 ? v : 75
    }

    /// The operator's chosen run-length cap, in hours;
    /// 0 means until stood down by hand.
    private var maxHours: Double {
        UserDefaults.standard.double(forKey: "assault.maxHours")
    }

    init() {
        lastReport = UserDefaults.standard.string(
            forKey: Self.lastReportKey)
    }

    func arm() {
        // A new run, a clean postcard ledger.
        postcardedThisRun = []
        guard !running else { return }
        if EmconStandard.refused(.netAssault) {
            note(String(format: L("Net-Assault stays dark — %@"),
                        EmconCondition.current.declared))
            return
        }
        Haptics.start()
        running = true
        passes = 0
        newThisRun = 0
        driftThisRun = 0
        probedThisRun = 0
        findings = []
        quietStreak = 0
        knockingNow = nil
        log = []
        startedAt = Date()
        baseNeighbors = NeighborhoodStore.shared
            .neighbors.count
        baseDrift = Self.totalDrift()
        boardID = ProcessBoard.shared.begin(
            label: L("Net-Assault"), organ: "Assault",
            detail: String(format: L("depth %lld"), depth), announce: false,
            stop: { AssaultCenter.shared.disarm() })
        Journal.log("assault", "armed",
                    "net-assault armed — depth "
                    + "\(depth), rest "
                    + "\(Int(restSeconds))s. The operator was "
                    + "warned it is loud.")
        note(L("Armed. The wire will hear this phone coming."))
        startPass()
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                     repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func disarm(reason: String = L("the operator stood it down")) {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        model.stopDiscovery()
        model.stopSweep()
        recon.cancelKnock()
        // The house going quiet quiets the
        // pestering too.
        TomatoBarrage.shared.stop()
        knockingNow = nil
        stage = .idle
        phase = L("Stood down")
        if let boardID {
            ProcessBoard.shared.end(boardID,
                                    .done(L("Stood down")))
            self.boardID = nil
        }
        Journal.log("assault", "disarmed",
                    "net-assault stood down after "
                    + "\(passes) pass(es) — \(reason). "
                    + "\(newThisRun) new device(s), "
                    + "\(driftThisRun) drift line(s), "
                    + "\(probedThisRun) ports knocked.")
        note(String(format: L("Stood down after %lld pass(es)."),
                    passes))
        // The after-action survives the run — and the
        // relaunch: it is filed before anything resets.
        let text = buildReport(reason: reason)
        lastReport = text
        UserDefaults.standard.set(text,
                                  forKey: Self.lastReportKey)
    }

    private static func totalDrift() -> Int {
        NeighborhoodStore.shared.neighbors.reduce(0) {
            $0 + $1.drift.count
        }
    }

    private func note(_ line: String) {
        let stamp = Date().formatted(date: .omitted,
                                     time: .shortened)
        log.append("\(stamp) — \(line)")
        if log.count > 60 {
            log.removeFirst(log.count - 60)
        }
    }

    private func startPass() {
        cycle += 1
        // Baselines first: what this pass finds is measured
        // against the wire as it stands this moment.
        let neighbors = NeighborhoodStore.shared.neighbors
        passIPs = Set(neighbors.map(\.ip))
        passDrift = Dictionary(uniqueKeysWithValues:
            neighbors.map { ($0.ip, $0.drift.count) })
        // The whole rotation in one pass, starting at a
        // rotating offset so consecutive passes do not
        // always knock the same door first.
        let offset = (cycle - 1) % sweepPorts.count
        sweepQueue = Array(sweepPorts[offset...])
            + Array(sweepPorts[..<offset])
        stage = .sweeping
        sweepNext()
    }

    private func sweepNext() {
        guard let port = sweepQueue.first else { return }
        phase = String(format: L("Pass %lld: sweeping the wire on port %lld"),
                       cycle, port)
        model.sweep(port: port)
    }

    private func tick() {
        guard running else { return }
        // The background check comes FIRST: a sleeping
        // house does no arithmetic at all.
        if UIApplication.shared.applicationState != .active {
            phase = L("Paused — the house sleeps; it resumes when you return")
            return
        }
        newThisRun = max(0, NeighborhoodStore.shared
            .neighbors.count - baseNeighbors)
        driftThisRun = max(0, Self.totalDrift() - baseDrift)
        if maxHours > 0, let startedAt,
           Date().timeIntervalSince(startedAt)
            > maxHours * 3600 {
            disarm(reason: String(format: L("the run reached its set length of %lldh"),
                                  Int(maxHours)))
            return
        }
        switch stage {
        case .sweeping:
            if !model.sweeping && !model.scanning {
                // The stage should never outlive its
                // queue — but a tick that finds it
                // empty finishes the stage instead of
                // reaching into a drained queue.
                guard !sweepQueue.isEmpty else {
                    finishSweepStage()
                    return
                }
                sweepQueue.removeFirst()
                if !sweepQueue.isEmpty {
                    sweepNext()
                } else {
                    finishSweepStage()
                }
            }
        case .browsing:
            // The browse ends on its deadline — or early,
            // when the wire has had six seconds and
            // announced nothing new: silence is also a
            // complete answer.
            let quiet = Date().timeIntervalSince(browseStarted)
                > 6 && model.discovered.count
                == browseCountAtStart
            if Date() > stageEnds || quiet {
                model.stopDiscovery()
                if depth >= 2 {
                    beginKnocking()
                } else {
                    rest()
                }
            }
        case .knocking:
            if !recon.knocking {
                if let done = knockingNow {
                    harvestKnock(done)
                    knockingNow = nil
                }
                if knockQueue.isEmpty {
                    rest()
                } else {
                    knockNext()
                }
            }
        case .resting:
            let left = Int(stageEnds.timeIntervalSinceNow)
            if left <= 0 {
                startPass()
            } else {
                phase = quietStreak > 0
                    ? String(format: L("Resting — the wire is quiet; next pass in %llds."),
                             left)
                    : String(format: L("Resting — next pass in %llds. The ear stays up."),
                             left)
            }
        case .idle:
            break
        }
    }

    /// The sweep chain is complete: name what the pass
    /// actually found — arrivals and drift, by name — then
    /// move the run along.
    private func finishSweepStage() {
        passes += 1
        let neighbors = NeighborhoodStore.shared.neighbors
        var found: [String] = []
        for neighbor in neighbors
        where !passIPs.contains(neighbor.ip) {
            found.append(String(format: L("Arrived on the wire: %@ (%@)"),
                                neighbor.displayName,
                                neighbor.ip))
        }
        for neighbor in neighbors {
            let before = passDrift[neighbor.ip]
                ?? neighbor.drift.count
            if neighbor.drift.count > before {
                found.append(String(format: L("Drift at %@: +%lld line(s)"),
                                    neighbor.displayName,
                                    neighbor.drift.count - before))
            }
        }
        for line in found { addFinding(line) }
        if found.isEmpty {
            quietStreak += 1
        } else {
            quietStreak = 0
        }
        let line = String(format: L("Pass %lld swept: %lld devices known, %lld new this run"),
                          cycle, neighbors.count, newThisRun)
            + (found.isEmpty ? "."
               : " — " + found.joined(separator: "; ") + ".")
        note(line)
        Journal.log("assault", "pass", line)
        if depth >= 1 {
            stage = .browsing
            stageEnds = Date().addingTimeInterval(12)
            browseStarted = Date()
            browseCountAtStart = model.discovered.count
            phase = L("Listening to the wire announce itself (Bonjour)")
            model.startDiscovery()
        } else {
            rest()
        }
    }

    /// One host under the bench: the question set fits
    /// what the host is. New and drifted hosts get the
    /// full census — something about them is unknown.
    /// A returning host whose picture is merely old gets
    /// its known doors re-asked, not the thousand
    /// questions again.
    private func knockNext() {
        let next = knockQueue.removeFirst()
        let records = Self.loadKnockRecords()
        let record = records[next.ip]
        let drifted = next.drift.count
            > (record?.driftSeen ?? 0)
        let census = ScanModel.topPorts.map { $0.0 }
        let ports: [Int]
        if record == nil || drifted {
            ports = census
        } else {
            let known = Set(record!.ports + next.ports)
            ports = known.isEmpty ? census : known.sorted()
        }
        probedThisRun += ports.count
        phase = String(format: L("Knocking %@ — %lld ports"),
                       next.displayName, ports.count)
        var updated = records
        updated[next.ip] = KnockRecord(
            lastKnocked: Date().timeIntervalSince1970,
            driftSeen: next.drift.count,
            ports: next.ports.sorted(),
            cycle: cycle)
        Self.saveKnockRecords(updated)
        knockingNow = next
        recon.knock(host: next.ip, ports: ports,
                    udp: false, speak: false)
    }

    /// The bench finished with a host: its answers are a
    /// finding — what it speaks, or that it has gone
    /// silent on doors it used to answer.
    /// This run's postcard ledger: the tomato
    /// arrives once per device per run — once is
    /// an insult, twice is pestering, and
    /// pestering is the barrage's job.
    private var postcardedThisRun: Set<String> = []

    private func harvestKnock(_ neighbor: Neighbor) {
        let opens = recon.hits.filter { $0.isOpen }
        if !opens.isEmpty {
            let doors = opens.map {
                let said = $0.banner
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                return "\($0.port) \($0.service)"
                    + (said.isEmpty
                        ? ""
                        : String(format: L(" says '%@'"),
                                 String(said.prefix(64))))
            }.joined(separator: " · ")
            addFinding(String(format: L("%@ answers: %@"),
                              neighbor.displayName, doors))
            // The tomato, made literal: one
            // postcard per marked device per run,
            // on its first open door.
            if TomatoMarks.shared
                .isMarked(neighbor.ip),
               !postcardedThisRun
                .contains(neighbor.ip),
               let first = opens.first {
                postcardedThisRun
                    .insert(neighbor.ip)
                Postcard.deliver(
                    ip: neighbor.ip,
                    port: first.port,
                    bytes: Postcard.tomatoBytes)
                addFinding(String(format: L("🍅 The tomato, made literal: a postcard left on %@'s door at port %lld."),
                                  neighbor.displayName,
                                  first.port))
            }
            // News is news: the governor's rest snaps
            // back when the knock stage finds something,
            // exactly as it does for the sweep stage.
            quietStreak = 0
        } else if let record =
                    Self.loadKnockRecords()[neighbor.ip],
                  !record.ports.isEmpty {
            addFinding(String(format: L("%@ went silent — none of its known doors answered"),
                              neighbor.displayName))
            quietStreak = 0
        }
        // The record learns what the knock actually
        // found: the doors that answered replace the
        // doors that were expected. A device gone silent
        // is filed with no known doors, so its silence
        // is news once — not every pass forever.
        var records = Self.loadKnockRecords()
        if var record = records[neighbor.ip] {
            record.ports = opens.map { $0.port }.sorted()
            records[neighbor.ip] = record
            Self.saveKnockRecords(records)
        }
    }

    private func addFinding(_ line: String) {
        // A finding feeds her pride — a measure
        // of it; findings are her day's work, and
        // no single one crowns her.
        SkelliHeart.shared.noteTriumph(10)
        findings.append(line)
        if findings.count > 120 {
            findings.removeFirst(findings.count - 120)
        }
        Journal.log("assault", "finding", line)
    }

    /// The queue is ordered by significance, not
    /// recency: unseen drift first, then the never
    /// knocked, then arrivals of this run, then the
    /// longest unprobed. A neighbor unchanged since
    /// a knock within the last three passes keeps
    /// the picture that knock took — it is skipped,
    /// not re-asked the whole census.
    private func beginKnocking() {
        let records = Self.loadKnockRecords()
        let now = Date()
        func significance(_ n: Neighbor) -> Double {
            let record = records[n.ip]
            var score = 0.0
            if n.drift.count > (record?.driftSeen ?? 0) {
                score += 1000
            }
            if record == nil { score += 500 }
            if let startedAt, n.firstSeen >= startedAt {
                score += 100
            }
            if let record {
                score += min(90, (now.timeIntervalSince1970
                    - record.lastKnocked) / 3600)
            }
            return score
        }
        func unchanged(_ n: Neighbor) -> Bool {
            guard let record = records[n.ip],
                  record.driftSeen == n.drift.count,
                  record.ports == n.ports.sorted()
            else { return false }
            return cycle - record.cycle < 3
        }
        // The tomato outranks significance: a
        // marked device is knocked first in
        // every pass and is never skipped as
        // unchanged — picked on amongst whoever
        // else the pass chooses, by the
        // operator's standing order.
        let cast = NeighborhoodStore.shared.neighbors
        let markedFirst = cast.filter {
            TomatoMarks.shared.isMarked($0.ip)
        }
        let theRest = cast
            .filter {
                !TomatoMarks.shared.isMarked($0.ip)
                    && !unchanged($0)
            }
            .sorted { significance($0) > significance($1) }
        knockQueue = Array(
            (markedFirst + theRest).prefix(12))
        if knockQueue.isEmpty {
            rest()
            return
        }
        stage = .knocking
        phase = String(format: L("Knocking the cast — %lld device(s) this pass, %@"),
                       knockQueue.count,
                       markedFirst.isEmpty
                           ? L("in order of significance")
                           : L("the marked first, then by significance"))
    }

    /// The governor: rest is the operator's setting,
    /// stretched while the wire stays quiet — a pass that
    /// found nothing earns the next one at 1.5x, up to
    /// three stretches and a ten-minute ceiling — and
    /// snapped back to the setting the moment anything
    /// is found. Pressure where there is news; patience
    /// where there is none.
    private func rest() {
        stage = .resting
        let stretch = pow(1.5, Double(min(quietStreak, 3)))
        let seconds = min(600, restSeconds * stretch)
        stageEnds = Date().addingTimeInterval(seconds)
        if quietStreak > 0 {
            phase = String(format: L("Resting — the wire is quiet (%lld empty pass(es)); next pass in %llds."),
                           quietStreak, Int(seconds))
        }
    }

    /// The after-action report: the run, on one page —
    /// the tallies, the findings by name, then the log.
    private func buildReport(reason: String) -> String {
        var lines = [L("NET-ASSAULT — after-action report"),
                     String(format: L("Stood down: %@."), reason),
                     String(format: L("Passes: %lld · new devices: %lld · drift: %lld · ports knocked: %lld"),
                            passes, newThisRun, driftThisRun,
                            probedThisRun),
                     ""]
        if findings.isEmpty {
            lines.append(L("Findings: none — the wire said nothing new."))
        } else {
            lines.append(L("Findings:"))
            lines += findings.map { "  · " + $0 }
        }
        lines.append("")
        lines += log
        lines.append("")
        lines.append(L("The sealed journal carries the same run under module 'assault', citable line by line."))
        return lines.joined(separator: "\n")
    }

    /// What the share door offers: the standing run's own
    /// page while it runs, the filed after-action after.
    var report: String {
        if running || lastReport == nil {
            return buildReport(reason: running
                ? L("report taken mid-run")
                : L("no run yet — it has never taken the wire"))
        }
        return lastReport!
    }
}

// MARK: - The Watch — safe passives, standing

/// The watch (Sentinel program, 2026-10-20):
/// the passives that stand when the operator
/// toggles them on — a standing Bonjour
/// browse, an MNDP ear, a gateway heartbeat,
/// and a diff of the neighborhood — receiving
/// and remembering, never transmitting a
/// campaign. Net-Assault campaigns; the watch
/// is how the house keeps learning the wire
/// between campaigns and notices what changed.
/// It files everything into one ledger the
/// Sentinel reads. Under EMCON Bravo or
/// Alpha it will not stand (the sweep organ
/// covers its browse); lockdown stands it
/// down with everything else.
final class WireWatch: ObservableObject {
    static let shared = WireWatch()

    @Published var on = false
    /// The ledger: timestamped lines, oldest
    /// first, capped at 200, persisted — a
    /// relaunch keeps what the watch learned.
    @Published private(set) var events: [String] = []
    @Published private(set) var gatewayIP: String?

    private var model: ScanModel?
    private var listener: NWListener?
    private var timer: Timer?
    private var knownIPs: Set<String> = []
    private var firedSigns: Set<String> = []
    private let watchQueue = DispatchQueue(
        label: "nightjar.wirewatch")
    private static let onKey = "wirewatch.on"
    private static let eventsKey =
        "wirewatch.events"

    private init() {
        events = UserDefaults.standard
            .stringArray(forKey: Self.eventsKey)
            ?? []
    }

    static func restoreIfNeeded() {
        if UserDefaults.standard.bool(
            forKey: onKey) {
            WireWatch.shared.start()
        }
    }

    /// Stand the passives up. Returns true
    /// when they stand (or already stood).
    @discardableResult
    func start() -> Bool {
        guard !EmconStandard.refused(.sweep)
        else { return false }
        guard !on else { return true }
        let scan = ScanModel()
        scan.startDiscovery()
        model = scan
        startMNDPEar()
        gatewayIP = BlacksiteNet
            .defaultGatewayIP()
        knownIPs = Set(NeighborhoodStore.shared
            .neighbors.map(\.ip))
        timer = Timer.scheduledTimer(
            withTimeInterval: 60,
            repeats: true) { [weak self] _ in
            self?.heartbeat()
        }
        on = true
        UserDefaults.standard.set(
            true, forKey: Self.onKey)
        note(L("the watch stands — Bonjour browse, an MNDP ear, a gateway heartbeat, a neighbor diff"))
        return true
    }

    func stop() {
        model?.stopDiscovery()
        model = nil
        listener?.cancel()
        listener = nil
        timer?.invalidate()
        timer = nil
        if on {
            note(L("the watch stands down"))
        }
        on = false
        UserDefaults.standard.set(
            false, forKey: Self.onKey)
    }

    private func startMNDPEar() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let ear = try? NWListener(
            using: params,
            on: NWEndpoint.Port(
                rawValue: 5678)!)
        else { return }
        ear.newConnectionHandler = {
            [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.start(
                queue: self.watchQueue)
            func receiveMore() {
                connection.receiveMessage {
                    data, _, _, error in
                    if let data, !data.isEmpty,
                       let facts =
                        BlacksitePentest
                        .parseMNDP(
                            [UInt8](data)) {
                        let ip = String(
                            describing:
                                connection
                                .endpoint)
                            .split(
                                separator: ":")
                            .first.map(
                                String.init)
                            ?? "?"
                        NeighborhoodStore.shared
                            .recordBonjourFacts(
                                ip: ip,
                                label: "MNDP",
                                facts: facts)
                        self.note("MNDP: "
                                  + "\(ip) — "
                                  + facts.joined(
                                    separator:
                                        " · "))
                    }
                    if error == nil {
                        receiveMore()
                    } else {
                        connection.cancel()
                    }
                }
            }
            receiveMore()
        }
        ear.start(queue: watchQueue)
        listener = ear
    }

    /// One heartbeat: the crown re-read, the
    /// neighborhood diffed, the standing
    /// signs checked. Sixty seconds apart.
    private func heartbeat() {
        let now = BlacksiteNet
            .defaultGatewayIP()
        if let now, let was = gatewayIP,
           now != was {
            Sentinel.shared.noteGatewayMoved(
                from: was, to: now, watch: self)
            note("the default gateway MOVED: "
                 + "\(was) → \(now) — a "
                 + "gateway that changes "
                 + "without the operator's hand "
                 + "is a sign to read hard")
            gatewayIP = now
        } else if gatewayIP == nil {
            gatewayIP = now
        }
        let store = NeighborhoodStore.shared
        for neighbor in store.neighbors
        where !knownIPs.contains(neighbor.ip) {
            knownIPs.insert(neighbor.ip)
            let named = neighbor.name.map {
                String(format: L(" — %@"), $0)
            } ?? ""
            note(String(format: L("a new neighbor at %@%@"),
                        neighbor.ip, named))
        }
        Sentinel.shared.evaluate(
            store: store,
            gateway: gatewayIP ?? now,
            watch: self)
        if on, !Lockdown.active,
           Lockdown.autoArmed {
            let severe = Sentinel.shared
                .recentSevere(within: 600)
            if severe.count >= 2 {
                let why = severe.map { $0.line }
                    .joined(separator: " · ")
                let summary = Lockdown.engage(
                    reason: String(format: L("two severe signs inside ten minutes: %@"),
                                   why))
                Journal.log("lockdown",
                            "automatic",
                            summary)
            }
        }
        if let crown = gatewayIP ?? now {
            for neighbor in store.neighbors
            where neighbor.ports.contains(67)
                && neighbor.ip != crown {
                let key = "rogue-dhcp-"
                    + neighbor.ip
                if !firedSigns.contains(key) {
                    firedSigns.insert(key)
                    note(String(format: L("SIGN — %@ answers DHCP but is not the gateway: a second address-giver on the wire is how quiet intercepts begin"),
                                neighbor.ip))
                }
            }
        }
    }

    private static let clock: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    /// The ledger's pen — the Sentinel
    /// writes through it too, so alerts and
    /// events share one timeline.
    func note(_ line: String) {
        let stamped = Self.clock.string(
            from: Date()) + " — " + line
        DispatchQueue.main.async {
            [weak self] in
            guard let self else { return }
            self.events.append(stamped)
            if self.events.count > 200 {
                self.events.removeFirst(
                    self.events.count - 200)
            }
            UserDefaults.standard.set(
                self.events,
                forKey: Self.eventsKey)
        }
    }
}

// MARK: - The Sentinel — what the signs mean

/// The Sentinel (Sentinel program, 2026-10-20):
/// the classification layer over everything
/// the watch and the neighborhood learn. The
/// watch testifies; the Sentinel judges. Its
/// rules name the shapes an attacker's hand
/// makes on a home wire:
///
/// - a second address-giver (rogue DHCP) —
///   SEVERE: that is how quiet intercepts
///   begin;
/// - a second device wearing the gateway's
///   name — SEVERE: impersonation;
/// - the gateway itself moving — SEVERE
///   (raised by the watch's heartbeat);
/// - a non-gateway newly serving DNS —
///   SUSPICIOUS: answers can be steered;
/// - a burst of knocks against this phone —
///   SUSPICIOUS, SEVERE when it pours;
/// - the router's own doors changing —
///   SUSPICIOUS: its surface is its story;
/// - a new arrival already wearing many
///   doors — a NOTICE, nothing more.
///
/// Every alert is ledgered with its severity
/// and its evidence line, deduplicated per
/// rule and address, and baselines persist —
/// the Sentinel remembers what normal looked
/// like yesterday.
final class Sentinel: ObservableObject {
    static let shared = Sentinel()

    enum Severity: String, Codable {
        case notice, suspicious, severe
        var word: String {
            switch self {
            case .notice: return "NOTICE"
            case .suspicious: return "SUSPICIOUS"
            case .severe: return "SEVERE"
            }
        }
    }

    struct Alert: Codable, Identifiable {
        var id: String { key }
        var key: String
        var at: Date
        var severity: Severity
        var line: String
        var ip: String?
    }

    @Published private(set) var alerts: [Alert] = []

    private var portBaseline: [String: [Int]] = [:]
    private var arrivalBaseline: [String: Int] = [:]
    private var fired: Set<String> = []
    private static let alertsKey =
        "sentinel.alerts"
    private static let stateKey =
        "sentinel.state"

    private init() {
        if let data = UserDefaults.standard
            .data(forKey: Self.alertsKey),
           let saved = try? JSONDecoder()
            .decode([Alert].self, from: data) {
            alerts = saved
        }
        if let data = UserDefaults.standard
            .data(forKey: Self.stateKey),
           let saved = try? JSONDecoder()
            .decode(State.self, from: data) {
            portBaseline = saved.ports
            arrivalBaseline = saved.arrivals
            fired = Set(saved.fired)
        }
    }

    private struct State: Codable {
        var ports: [String: [Int]]
        var arrivals: [String: Int]
        var fired: [String]
    }

    private func persist() {
        if let data = try? JSONEncoder()
            .encode(alerts) {
            UserDefaults.standard.set(
                data, forKey: Self.alertsKey)
        }
        let state = State(ports: portBaseline,
                          arrivals: arrivalBaseline,
                          fired: Array(fired))
        if let data = try? JSONEncoder()
            .encode(state) {
            UserDefaults.standard.set(
                data, forKey: Self.stateKey)
        }
    }

    /// Severe alerts inside a window — the
    /// lockdown's tripwire reads this.
    func recentSevere(
        within seconds: TimeInterval) -> [Alert] {
        let cutoff = Date()
            .addingTimeInterval(-seconds)
        return alerts.filter {
            $0.severity == .severe
                && $0.at > cutoff
        }
    }

    var standingSevere: [Alert] {
        alerts.filter { $0.severity == .severe }
    }

    func clearAlerts() {
        alerts = []
        fired = []
        persist()
    }

    private func raise(key: String,
                       severity: Severity,
                       line: String,
                       ip: String?,
                       watch: WireWatch) {
        guard !fired.contains(key) else { return }
        fired.insert(key)
        let alert = Alert(key: key, at: Date(),
                          severity: severity,
                          line: line, ip: ip)
        alerts.append(alert)
        persist()
        watch.note("ALERT · \(severity.word) — "
                   + line)
    }

    /// The heartbeat's own severe: the
    /// crown moved. Judged here so the
    /// lockdown tripwire counts it.
    func noteGatewayMoved(from: String,
                          to: String,
                          watch: WireWatch) {
        raise(key: "gateway-moved-"
                + from + "-" + to,
              severity: .severe,
              line: String(format: L("the default gateway moved: %@ → %@ — a gateway that changes without the operator's hand is a sign to read hard"),
                           from, to),
              ip: to, watch: watch)
    }

    /// An SSH host key that changed under
    /// the operator's feet — the console's
    /// client refused it, and the refusal
    /// is ledgered here at the severe
    /// grade: keys change when gear is
    /// replaced, and also when someone
    /// stands in the middle.
    func noteHostKeyChanged(host: String,
                            fingerprint: String) {
        raise(key: "ssh-key-changed-" + host,
              severity: .severe,
              line: String(format: L("the SSH host key for %@ changed — now %@. The client refused it. If the gear was not replaced, read this hard"),
                           host, fingerprint),
              ip: nil, watch: WireWatch.shared)
    }

    /// Judge the neighborhood as it stands.
    /// Called by the watch's heartbeat; cheap
    /// enough to run every minute.
    func evaluate(store: NeighborhoodStore,
                  gateway: String?,
                  watch: WireWatch) {
        let neighbors = store.neighbors
        let crowned = gateway.flatMap { ip in
            neighbors.first { $0.ip == ip }
        }
        for neighbor in neighbors {
            let isCrown = gateway != nil
                && neighbor.ip == gateway
            // Rogue DHCP — severe.
            if neighbor.ports.contains(67),
               !isCrown, gateway != nil {
                raise(key: "rogue-dhcp-"
                        + neighbor.ip,
                      severity: .severe,
                      line: String(format: L("%@ answers DHCP but is not the gateway — a second address-giver"),
                                   neighbor.ip),
                      ip: neighbor.ip,
                      watch: watch)
            }
            // Gateway impersonation — severe.
            if let crowned, !isCrown,
               let crownName = crowned.name,
               neighbor.name == crownName {
                raise(key: "impersonation-"
                        + neighbor.ip,
                      severity: .severe,
                      line: String(format: L("%@ wears the gateway's name (“%@”)"),
                                   neighbor.ip, crownName),
                      ip: neighbor.ip,
                      watch: watch)
            }
            // Non-gateway DNS — suspicious,
            // judged against the baseline so
            // the house's known resolver (a Pi-
            // hole the operator runs) alerts
            // once, at first sight, not daily.
            if neighbor.ports.contains(53),
               !isCrown {
                if let base = portBaseline[
                    neighbor.ip],
                   !base.contains(53) {
                    raise(key: "new-dns-"
                            + neighbor.ip,
                          severity: .suspicious,
                          line: String(format: L("%@ has begun serving DNS — it did not before"),
                                       neighbor.ip),
                          ip: neighbor.ip,
                          watch: watch)
                }
            }
            // Knock bursts against this phone.
            let arrivals = neighbor.arrivals
            if let before = arrivalBaseline[
                neighbor.ip] {
                let delta = arrivals - before
                if delta >= 15 {
                    raise(key: "knock-pour-"
                            + neighbor.ip
                            + "-\(arrivals)",
                          severity: .severe,
                          line: String(format: L("%@ has knocked this phone %lld times in a minute — that is a probe pour, not a visit"),
                                       neighbor.ip, delta),
                          ip: neighbor.ip,
                          watch: watch)
                } else if delta >= 5 {
                    raise(key: "knock-burst-"
                            + neighbor.ip
                            + "-\(arrivals)",
                          severity: .suspicious,
                          line: String(format: L("%@ knocked this phone %lld times in a minute"),
                                       neighbor.ip, delta),
                          ip: neighbor.ip,
                          watch: watch)
                }
            }
            arrivalBaseline[neighbor.ip] =
                arrivals
            // The router's own doors changing.
            if isCrown {
                if let base = portBaseline[
                    neighbor.ip],
                   base != neighbor.ports {
                    let gained = neighbor.ports
                        .filter {
                            !base.contains($0)
                        }
                    let lost = base.filter {
                        !neighbor.ports
                            .contains($0)
                    }
                    var parts: [String] = []
                    if !gained.isEmpty {
                        parts.append(String(format: L("opened %@"),
                            gained.map(
                                String.init)
                            .joined(
                                separator: ", ")))
                    }
                    if !lost.isEmpty {
                        parts.append(String(format: L("closed %@"),
                            lost.map(String.init)
                            .joined(
                                separator: ", ")))
                    }
                    raise(key: "router-doors-"
                            + neighbor.ip + "-"
                            + "\(neighbor.ports)",
                          severity: .suspicious,
                          line: String(format: L("the router's own doors changed: %@"),
                                       parts.joined(
                                           separator: "; ")),
                          ip: neighbor.ip,
                          watch: watch)
                }
            }
            // A many-doored newcomer — a
            // notice, set the first time its
            // port baseline is laid.
            if portBaseline[neighbor.ip] == nil,
               neighbor.ports.count >= 6,
               !isCrown {
                let doors = neighbor.ports.count
                raise(key: "many-doors-"
                        + neighbor.ip,
                      severity: .notice,
                      line: String(format: L("%@ stands with %lld doors open — worth knowing"),
                                   neighbor.ip, doors),
                      ip: neighbor.ip,
                      watch: watch)
            }
            if portBaseline[neighbor.ip] == nil {
                portBaseline[neighbor.ip] =
                    neighbor.ports
            }
        }
        persist()
    }
}

// MARK: - The wire brief — her answers

/// The brief (Sentinel S4, 2026-10-20): what
/// Skelli says when she is asked about the
/// network — composed on the spot from the
/// crown, the census, and the Sentinel's
/// ledger, never from memory of an older
/// wire. And when the knowledge isn't
/// there, the answer goes and gets it: the
/// watch is stood up, a pass is armed. Her
/// use cases are hers to trigger.
enum WireBrief {
    static func crownAnswer() -> String {
        let gateway = BlacksiteNet
            .defaultGatewayIP()
        let rows = NeighborhoodStore.shared
            .routerReport(gatewayIP: gateway)
        if let crown = rows.first(
            where: { $0.weight == .certain }),
           let gateway {
            let n = crown.neighbor
            var line: String
            if let name = n.name {
                line = String(format: L("Your router is %@ at %@ — crowned, not guessed: this phone's default route lands there."),
                              name, gateway)
            } else {
                line = String(format: L("Your router is %@ — crowned, not guessed: this phone's default route lands there."),
                              gateway)
            }
            if !n.ports.isEmpty {
                let doors = n.ports.prefix(5)
                    .map(String.init)
                    .joined(separator: ", ")
                line += String(format: L(" It holds doors %@."),
                               doors)
            }
            return line
        }
        if let best = rows.first {
            let n = best.neighbor
            let verdict = best.weight == .likely
                ? L("Likely") : L("Possibly")
            return String(format: L("The gateway itself did not read, so no crown — by signs the strongest candidate is %@ at %@: %@. %@ the router."),
                          n.displayName, n.ip,
                          best.signs.joined(
                              separator: "; "),
                          verdict)
        }
        return L("I can't crown a router on this wire yet — the gateway didn't read and no neighbor carries router signs. A Net-Assault pass and a minute of the watch would give me the evidence.")
    }

    static func alertAnswer() -> String {
        let sentinel = Sentinel.shared
        let severe = sentinel.standingSevere
        if !severe.isEmpty {
            let lines = severe.suffix(3)
                .map { $0.line }
            return String(format: L("Yes — the Sentinel has judged, and it isn't quiet: %@. Read those hard."),
                          lines.joined(
                              separator: " · "))
        }
        let others = sentinel.alerts.filter {
            $0.severity == .suspicious
        }
        if !others.isEmpty {
            let lines = others.suffix(3)
                .map { $0.line }
            return String(format: L("Nothing severe, but not nothing: %@."),
                          lines.joined(
                              separator: " · "))
        }
        let watch = WireWatch.shared
        if watch.on {
            let count = watch.events.count
            return String(format: L("Nothing the Sentinel judges — and the watch has been standing over the wire (%lld events in its ledger, none rising to an alert). The wire looks like itself."),
                          count)
        }
        if watch.start() {
            return L("Nothing judged yet — but the watch wasn't standing, so any answer would have been a guess. I've stood it up: browse, an MNDP ear, a gateway heartbeat. Ask me again as it learns and the answer will be evidence.")
        }
        let declared = EmconCondition.current
            .declared
        return String(format: L("Nothing judged yet, and the watch won't stand under %@ — the condition forbids its browse. The ledger holds what earlier standing learned."),
                      declared)
    }

    static func newcomerAnswer() -> String {
        let cutoff = Date()
            .addingTimeInterval(-24 * 3600)
        let fresh = NeighborhoodStore.shared
            .neighbors
            .filter { $0.firstSeen > cutoff }
            .sorted {
                $0.firstSeen > $1.firstSeen
            }
        if fresh.isEmpty {
            return L("No new faces in the last day — the cast on this wire is the cast.")
        }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        let lines = fresh.prefix(4).map { n in
            String(format: L("%@ at %@ (first seen %@)"),
                   n.displayName, n.ip,
                   fmt.localizedString(
                       for: n.firstSeen,
                       relativeTo: Date()))
        }
        return String(format: L("New in the last day: %@."),
                      lines.joined(separator: "; "))
    }

    static func briefAnswer() -> String {
        let store = NeighborhoodStore.shared
        if store.neighbors.isEmpty {
            let center = AssaultCenter.shared
            if center.running {
                return String(format: L("Net-Assault is mid-pass right now (%@) — the census is being taken as we speak."),
                              center.phase)
            }
            center.arm()
            if center.running {
                return L("This wire is a blank page to me — no neighbors on the board at all. I've armed Net-Assault for a pass to census it; give it a breath and ask me again.")
            }
            let declared = EmconCondition
                .current.declared
            return String(format: L("This wire is a blank page to me, and Net-Assault stays dark under %@ — the census waits on the condition, or on Recon's own eyes."),
                          declared)
        }
        var parts: [String] = []
        let gateway = BlacksiteNet
            .defaultGatewayIP()
        if let gateway {
            let crown = store.neighbors
                .first { $0.ip == gateway }
            if let crown, let name =
                crown.name {
                parts.append(String(format: L("The router is %@ at %@."),
                                    name, gateway))
            } else {
                parts.append(String(format: L("The router is at %@."),
                                    gateway))
            }
        }
        let count = store.neighbors.count
        parts.append(String(format: L("%lld neighbor(s) known."),
                            count))
        let named = store.neighbors
            .filter { $0.name != nil }
            .prefix(3)
            .map { $0.displayName }
        if !named.isEmpty {
            parts.append(String(format: L("Named among them: %@."),
                                named.joined(
                                    separator: ", ")))
        }
        let severe = Sentinel.shared
            .standingSevere.count
        let suspicious = Sentinel.shared
            .alerts.filter {
                $0.severity == .suspicious
            }.count
        if severe > 0 {
            parts.append(String(format: L("The Sentinel holds %lld severe alert(s) — ask me what's strange and I'll read them."),
                                severe))
        } else if suspicious > 0 {
            parts.append(String(format: L("The Sentinel holds %lld suspicious alert(s)."),
                                suspicious))
        } else {
            parts.append(L("The Sentinel judges nothing amiss."))
        }
        parts.append(WireWatch.shared.on
            ? L("The watch stands.")
            : L("The watch is down."))
        return parts.joined(separator: " ")
    }
}

// MARK: - Lockdown — the house goes dark

/// Lockdown (Sentinel S5, 2026-10-20): the
/// defensive procedure, one motion — EMCON
/// Alpha declared and enforced (the
/// Standard's own silencer stills every
/// forbidden organ), Net-Assault stood
/// down, the watch stood down, the prior
/// condition remembered. It fires three
/// ways: the operator's word, Skelli's
/// hand, and automatically — two severe
/// Sentinel signs inside ten minutes while
/// the watch stands (the toggle rides in
/// UserDefaults as lockdown.auto, on
/// unless the operator turns it off).
/// Only the operator lifts it; lifting
/// restores the condition that stood
/// before. Honest scope, stated once: an
/// app can silence ITSELF completely — it
/// cannot firewall the phone or leave the
/// network for the operator; those moves
/// are the operator's own hands, and the
/// lockdown speech says so.
enum Lockdown {
    private static let activeKey =
        "lockdown.active"
    private static let priorKey =
        "lockdown.prior"
    static let autoKey = "lockdown.auto"

    static var active: Bool {
        UserDefaults.standard.bool(
            forKey: activeKey)
    }

    static var autoArmed: Bool {
        UserDefaults.standard.object(
            forKey: autoKey) as? Bool ?? true
    }

    /// Engage. Returns the spoken summary —
    /// what went dark, and why.
    @discardableResult
    static func engage(reason: String)
        -> String {
        if active {
            return L("Lockdown is already standing — the house is dark.")
        }
        let prior = EmconCondition.current
        UserDefaults.standard.set(
            prior.rawValue, forKey: priorKey)
        UserDefaults.standard.set(
            true, forKey: activeKey)
        WireWatch.shared.stop()
        var silenced: [String] = []
        let center = SkelliCenter.shared
        if let mouth = center.mouth,
           let emcon = center.emcon {
            emcon.activate(
                mouth: mouth, condition: .alpha)
            silenced = emcon.lastSilenced
        } else {
            EmconCondition.store(.alpha)
        }
        if AssaultCenter.shared.running {
            AssaultCenter.shared.disarm(
                reason: "lockdown")
            silenced.append(L("Net-Assault"))
        }
        Journal.log("lockdown", "engaged",
                    reason + " — prior "
                    + prior.declared)
        var line = L("Lockdown. EMCON Alpha — total silence. ")
        if silenced.isEmpty {
            line += L("Nothing was standing to silence. ")
        } else {
            line += String(format: L("Silenced: %@. "),
                           silenced.joined(
                               separator: ", "))
        }
        line += String(format: L("The watch stands down too. Why: %@. The phone itself is beyond my hands — airplane mode and forgetting the network are yours. Say “lift the lockdown” when you want the house back."),
                       reason)
        return line
    }

    /// Lift — the operator's word only.
    /// Restores the remembered condition.
    @discardableResult
    static func lift() -> String {
        guard active else {
            return L("No lockdown is standing.")
        }
        UserDefaults.standard.set(
            false, forKey: activeKey)
        let raw = UserDefaults.standard
            .integer(forKey: priorKey)
        let prior = EmconCondition(
            rawValue: raw) ?? .open
        let center = SkelliCenter.shared
        if let mouth = center.mouth,
           let emcon = center.emcon {
            emcon.activate(
                mouth: mouth, condition: prior)
        } else {
            EmconCondition.store(prior)
        }
        Journal.log("lockdown", "lifted",
                    "restored "
                    + prior.declared)
        return String(format: L("Lockdown lifted — the house returns to %@. The watch stays down until you stand it; nothing resumes itself."),
                      prior.declared)
    }
}

// MARK: - The section

struct NetAssaultSectionView: View {
    @ObservedObject var center: AssaultCenter
    @Binding var armRequest: Bool
    @Binding var shareRequest: Bool
    @ObservedObject private var mind =
        SubconsciousCenter.shared
    @ObservedObject private var themeCenter =
        ThemeCenter.shared
    @AppStorage("assault.depth") private var depth = 2
    @AppStorage("assault.rest") private var restSeconds = 75.0
    @AppStorage("assault.maxHours") private var maxHours = 0.0

    var body: some View {
        Section {
            if center.running {
                runningDashboard
            } else {
                idlePitch
            }
        } header: {
            HStack(spacing: 8) {
                SkullMark(color: themeCenter.current.accent,
                          size: 20)
                Text(L("Net-Assault"))
                    .font(.headline)
                    .foregroundStyle(
                        themeCenter.current.accent)
                Spacer()
                Text(center.running ? "RUNNING" : "HOLSTERED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(center.running
                                     ? .red : .secondary)
            }
        } footer: {
            Text(L("Runs while the app is awake in front of you — sleep pauses it, waking resumes it. It uses only the house's own organs: the sweep, the browse, the recon bench, the ear. Nothing is exploited and nothing is flooded; things are knocked on and listened to — loudly, and in the open."))
        }
    }

    // Rows, not one stuffed cell: this section's content
    // used to live in a single VStack inside a single list
    // cell — copy, warning, both pickers, and both buttons
    // in one row. When the report button appeared after a
    // run, the cell's hit geometry went stale and taps on
    // it landed on the Arm button. As real rows, every
    // control is measured and hit on its own.
    private var idlePitch: some View {
        Group {
            Text(L("Every organ in the house, one continuous autonomous run: sweep the wire on every port in the rotation, let it announce itself, then knock — new and drifted devices get the full census, settled ones get their known doors re-asked — pass after pass, for as long as you leave it armed. Findings are named, not just counted: who arrived, who drifted, who answers, who went silent. Everything it learns walks the usual roads: the Neighborhood, the Map, the sealed log, the mind underneath."))
                .font(.callout)
            Label(L("This is loud. It announces this phone to every device — and every watcher — on the wire. On networks you do not own it may trip intrusion detection, alerts, and logs with your name on them."),
                  systemImage: "exclamationmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            if !EmconCondition.current.permits(.netAssault) {
                Label(String(format: L("Held dark by %@ — the Standard forbids Net-Assault under this condition; it arms only while the condition is open."), EmconCondition.current.declared),
                      systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
            Picker(L("Depth"), selection: $depth) {
                Text(L("Sweep")).tag(0)
                Text(L("+ Bonjour")).tag(1)
                Text(L("Full")).tag(2)
            }
            .pickerStyle(.segmented)
            Picker(L("Pause between passes"),
                   selection: $restSeconds) {
                Text(L("30s")).tag(30.0)
                Text(L("75s")).tag(75.0)
                Text(L("3 min")).tag(180.0)
            }
            .pickerStyle(.segmented)
            Text(L("How long the wire rests between one full pass — sweep, browse, knock — and the next. Shorter keeps the pressure continuous; longer revisits on a slower, quieter cadence. While the wire stays quiet the rest stretches itself, up to ten minutes, and snaps back the moment a pass finds something."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(L("Run length"), selection: $maxHours) {
                Text(L("Until stood down")).tag(0.0)
                Text(L("1 hour")).tag(1.0)
                Text(L("3 hours")).tag(3.0)
                Text(L("8 hours")).tag(8.0)
            }
            .pickerStyle(.segmented)
            Button {
                armRequest = true
            } label: {
                HStack {
                    SkullMark(color: .red, size: 18)
                    Text(L("Arm the net-assault"))
                        .font(.body.weight(.bold))
                    Spacer()
                }
            }
            .foregroundStyle(.red)
            .disabled(
                !EmconCondition.current.permits(.netAssault))
            if center.passes > 0
                || center.lastReport != nil {
                // A door, not a ShareLink: a bare ShareLink
                // buried in a List section cannot find a
                // presentation host in this app and dies
                // silently under the finger. The sheet
                // itself hangs off the screen's root.
                Button { shareRequest = true } label: {
                    Label(L("After-action report — last run"),
                          systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private var runningDashboard: some View {
        Group {
            Text(center.phase)
                .font(.callout.weight(.bold))
                .foregroundStyle(themeCenter.current.glow)
            LazyVGrid(columns: [GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())],
                      spacing: 8) {
                stat("Passes", "\(center.passes)")
                stat("New", "\(center.newThisRun)")
                stat("Drift", "\(center.driftThisRun)")
                stat("Knocked", "\(center.probedThisRun)")
                stat("Elapsed", elapsed)
                stat("Known",
                     "\(NeighborhoodStore.shared.neighbors.count)")
            }
            if let latest = center.findings.last {
                Text(String(format: L("Latest: %@"), latest))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let top = mind.insights.first {
                Text(String(format: L("The mind, watching: %@"), top.title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(center.log.suffix(4), id: \.self) {
                    line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Button(role: .destructive) {
                center.disarm()
            } label: {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text(L("Stand down"))
                        .font(.body.weight(.bold))
                    Spacer()
                }
            }
        }
        .onAppear { mind.refresh() }
    }

    private func stat(_ name: String, _ value: String)
        -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline.monospaced())
                .foregroundStyle(themeCenter.current.accent)
            Text(L(name))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05)))
    }

    private var elapsed: String {
        guard let start = center.startedAt else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}

// MARK: - Sharing

/// The system's share sheet as a plain view controller, so
/// it can hang off a screen's root like every other working
/// presenter in the house.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(
        context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items,
                                 applicationActivities: nil)
    }

    func updateUIViewController(
        _ controller: UIActivityViewController,
        context: Context) {}
}

// MARK: - The ignition

/// What plays when the mode is initialized: the operator's
/// GIF, full-bleed, over the run's first pass — pure theatre
/// laid over real work, exactly like the centipede's drumroll.
/// The GIF comes from an "Assault" data asset or an
/// assault.gif in the bundle; without one, a flickering
/// skull card stands in, so the mode is never broken by a
/// missing flourish. Tap to skip.
struct AssaultIgnitionView: View {
    @Binding var isShown: Bool
    @ObservedObject private var themeCenter =
        ThemeCenter.shared
    @State private var flicker = false

    private var gifData: Data? {
        if let asset = NSDataAsset(name: "Assault") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "assault",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        // Any bundled GIF with the assault in its name —
        // the reel is forgiving about filenames.
        if let path = Bundle.main.paths(
            forResourcesOfType: "gif", inDirectory: nil)
            .first(where: {
                $0.lowercased().contains("assault") }) {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        return nil
    }

    /// The GIF's own play length plus a breath, clamped
    /// sane; 3 s for the fallback card.
    private var splashSeconds: Double {
        guard let data = gifData else { return 3.0 }
        // The length from the frame headers alone —
        // never a full decode just to tell time.
        let seconds = UIImage.gifDelays(data).reduce(0, +)
        guard seconds > 0 else { return 3.0 }
        return min(max(seconds + 0.3, 1.5), 6.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                // Just the reel, delivered the way the boot
                // screen delivers its own: full-bleed,
                // edge to edge, nothing over it.
                GIFPlayerView(data: data)
                    .ignoresSafeArea()
            } else {
                MatrixDots(color: themeCenter.current.accent
                    .opacity(0.15))
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    SkullMark(color: .red, size: 110)
                    Text(L("NET-ASSAULT"))
                        .font(.title.monospaced().weight(.bold))
                        .tracking(5)
                        .foregroundStyle(.white)
                    Text(L("the wire will hear this phone coming"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .opacity(flicker ? 0.55 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)) {
                        flicker = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isShown = false }
        .onAppear {
            Haptics.success()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + splashSeconds) {
                isShown = false
            }
        }
    }
}
