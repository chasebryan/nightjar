import SwiftUI
import UIKit

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
        guard !running else { return }
        if EmconStandard.refused(.netAssault) {
            note("Net-Assault stays dark — "
                 + EmconCondition.current.declared)
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
            label: "Net-Assault", organ: "Assault",
            detail: "depth \(depth)", announce: false,
            stop: { AssaultCenter.shared.disarm() })
        Journal.log("assault", "armed",
                    "net-assault armed — depth "
                    + "\(depth), rest "
                    + "\(Int(restSeconds))s. The operator was "
                    + "warned it is loud.")
        note("Armed. The wire will hear this phone coming.")
        startPass()
        timer = Timer.scheduledTimer(withTimeInterval: 1,
                                     repeats: true) { _ in
            self.tick()
        }
    }

    func disarm(reason: String = "the operator stood it down") {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        model.stopDiscovery()
        model.stopSweep()
        recon.cancelKnock()
        knockingNow = nil
        stage = .idle
        phase = "Stood down"
        if let boardID {
            ProcessBoard.shared.end(boardID,
                                    .done("Stood down"))
            self.boardID = nil
        }
        Journal.log("assault", "disarmed",
                    "net-assault stood down after "
                    + "\(passes) pass(es) — \(reason). "
                    + "\(newThisRun) new device(s), "
                    + "\(driftThisRun) drift line(s), "
                    + "\(probedThisRun) ports knocked.")
        note("Stood down after \(passes) pass(es).")
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
        phase = "Pass \(cycle): sweeping the wire on "
            + "port \(port)"
        model.sweep(port: port)
    }

    private func tick() {
        guard running else { return }
        // The background check comes FIRST: a sleeping
        // house does no arithmetic at all.
        if UIApplication.shared.applicationState != .active {
            phase = "Paused — the house sleeps; "
                + "it resumes when you return"
            return
        }
        newThisRun = max(0, NeighborhoodStore.shared
            .neighbors.count - baseNeighbors)
        driftThisRun = max(0, Self.totalDrift() - baseDrift)
        if maxHours > 0, let startedAt,
           Date().timeIntervalSince(startedAt)
            > maxHours * 3600 {
            disarm(reason: "the run reached its set length "
                   + "of \(Int(maxHours))h")
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
                    ? "Resting — the wire is quiet; next "
                      + "pass in \(left)s."
                    : "Resting — next pass in \(left)s. "
                      + "The ear stays up."
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
            found.append("Arrived on the wire: "
                         + "\(neighbor.displayName) "
                         + "(\(neighbor.ip))")
        }
        for neighbor in neighbors {
            let before = passDrift[neighbor.ip]
                ?? neighbor.drift.count
            if neighbor.drift.count > before {
                found.append("Drift at "
                             + "\(neighbor.displayName): "
                             + "+\(neighbor.drift.count - before) "
                             + "line(s)")
            }
        }
        for line in found { addFinding(line) }
        if found.isEmpty {
            quietStreak += 1
        } else {
            quietStreak = 0
        }
        let line = "Pass \(cycle) swept: "
            + "\(neighbors.count) devices known, "
            + "\(newThisRun) new this run"
            + (found.isEmpty ? "."
               : " — " + found.joined(separator: "; ") + ".")
        note(line)
        Journal.log("assault", "pass", line)
        if depth >= 1 {
            stage = .browsing
            stageEnds = Date().addingTimeInterval(12)
            browseStarted = Date()
            browseCountAtStart = model.discovered.count
            phase = "Listening to the wire announce "
                + "itself (Bonjour)"
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
        phase = "Knocking \(next.displayName) — "
            + "\(ports.count) ports"
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
    private func harvestKnock(_ neighbor: Neighbor) {
        let opens = recon.hits.filter { $0.isOpen }
        if !opens.isEmpty {
            let doors = opens.map {
                "\($0.port) \($0.service)"
            }.joined(separator: " · ")
            addFinding("\(neighbor.displayName) answers: "
                       + doors)
            // News is news: the governor's rest snaps
            // back when the knock stage finds something,
            // exactly as it does for the sweep stage.
            quietStreak = 0
        } else if let record =
                    Self.loadKnockRecords()[neighbor.ip],
                  !record.ports.isEmpty {
            addFinding("\(neighbor.displayName) went silent "
                       + "— none of its known doors answered")
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
        knockQueue = Array(NeighborhoodStore.shared.neighbors
            .filter { !unchanged($0) }
            .sorted { significance($0) > significance($1) }
            .prefix(12))
        if knockQueue.isEmpty {
            rest()
            return
        }
        stage = .knocking
        phase = "Knocking the cast — "
            + "\(knockQueue.count) device(s) this pass, "
            + "in order of significance"
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
            phase = "Resting — the wire is quiet "
                + "(\(quietStreak) empty pass(es)); "
                + "next pass in \(Int(seconds))s."
        }
    }

    /// The after-action report: the run, on one page —
    /// the tallies, the findings by name, then the log.
    private func buildReport(reason: String) -> String {
        var lines = ["NET-ASSAULT — after-action report",
                     "Stood down: \(reason).",
                     "Passes: \(passes) · new devices: "
                        + "\(newThisRun) · drift: "
                        + "\(driftThisRun) · ports knocked: "
                        + "\(probedThisRun)",
                     ""]
        if findings.isEmpty {
            lines.append("Findings: none — the wire "
                         + "said nothing new.")
        } else {
            lines.append("Findings:")
            lines += findings.map { "  · " + $0 }
        }
        lines.append("")
        lines += log
        lines.append("")
        lines.append("The sealed journal carries the same "
                     + "run under module 'assault', citable "
                     + "line by line.")
        return lines.joined(separator: "\n")
    }

    /// What the share door offers: the standing run's own
    /// page while it runs, the filed after-action after.
    var report: String {
        if running || lastReport == nil {
            return buildReport(reason: running
                ? "report taken mid-run"
                : "no run yet — it has never taken the wire")
        }
        return lastReport!
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
            Text(name)
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
