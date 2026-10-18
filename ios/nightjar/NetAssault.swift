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

    private enum Stage { case idle, sweeping, browsing,
                         knocking, resting }
    private var stage: Stage = .idle
    private var stageEnds = Date.distantPast
    private let model = ScanModel()
    private let recon = Recon()
    private var timer: Timer?
    private var knockQueue: [Neighbor] = []

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

    func arm() {
        guard !running else { return }
        running = true
        passes = 0
        newThisRun = 0
        driftThisRun = 0
        probedThisRun = 0
        log = []
        startedAt = Date()
        baseNeighbors = NeighborhoodStore.shared
            .neighbors.count
        baseDrift = Self.totalDrift()
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
        stage = .idle
        phase = "Stood down"
        Journal.log("assault", "disarmed",
                    "net-assault stood down after "
                    + "\(passes) pass(es) — \(reason). "
                    + "\(newThisRun) new device(s), "
                    + "\(driftThisRun) drift line(s), "
                    + "\(probedThisRun) ports knocked.")
        note("Stood down after \(passes) pass(es).")
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
        let port = sweepPorts[(cycle - 1) % sweepPorts.count]
        stage = .sweeping
        phase = "Pass \(cycle): sweeping the wire on "
            + "port \(port)"
        model.sweep(port: port)
    }

    private func tick() {
        guard running else { return }
        newThisRun = max(0, NeighborhoodStore.shared
            .neighbors.count - baseNeighbors)
        driftThisRun = Self.totalDrift() - baseDrift
        if UIApplication.shared.applicationState != .active {
            phase = "Paused — the house sleeps; "
                + "it resumes when you return"
            return
        }
        switch stage {
        case .sweeping:
            if !model.sweeping && !model.scanning {
                passes += 1
                let line = "Pass \(cycle) swept: "
                    + "\(NeighborhoodStore.shared.neighbors.count) "
                    + "devices known, \(newThisRun) new this run."
                note(line)
                Journal.log("assault", "pass", line)
                if depth >= 1 {
                    stage = .browsing
                    stageEnds = Date().addingTimeInterval(12)
                    phase = "Listening to the wire announce "
                        + "itself (Bonjour)"
                    model.startDiscovery()
                } else {
                    rest()
                }
            }
        case .browsing:
            if Date() > stageEnds {
                model.stopDiscovery()
                if depth >= 2 {
                    beginKnocking()
                } else {
                    rest()
                }
            }
        case .knocking:
            if !recon.knocking {
                if knockQueue.isEmpty {
                    rest()
                } else {
                    let next = knockQueue.removeFirst()
                    let census = ScanModel.topPorts.map { $0.0 }
                    probedThisRun += census.count
                    phase = "Knocking \(next.displayName) — "
                        + "the full census (\(census.count) ports)"
                    var records = Self.loadKnockRecords()
                    records[next.ip] = KnockRecord(
                        lastKnocked: Date()
                            .timeIntervalSince1970,
                        driftSeen: next.drift.count,
                        ports: next.ports.sorted(),
                        cycle: cycle)
                    Self.saveKnockRecords(records)
                    recon.knock(host: next.ip, ports: census,
                                udp: false, speak: false)
                }
            }
        case .resting:
            let left = Int(stageEnds.timeIntervalSinceNow)
            if left <= 0 {
                startPass()
            } else {
                phase = "Resting — next pass in \(left)s. "
                    + "The ear stays up."
            }
        case .idle:
            break
        }
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

    private func rest() {
        stage = .resting
        stageEnds = Date().addingTimeInterval(restSeconds)
    }

    /// The after-action report: the run, on one page.
    var report: String {
        var lines = ["NET-ASSAULT — after-action report",
                     "Passes: \(passes) · new devices: "
                        + "\(newThisRun) · drift: "
                        + "\(driftThisRun) · ports knocked: "
                        + "\(probedThisRun)",
                     ""]
        lines += log
        lines.append("")
        lines.append("The sealed journal carries the same "
                     + "run under module 'assault', citable "
                     + "line by line.")
        return lines.joined(separator: "\n")
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
                Text("Net-Assault")
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
            Text("Runs while the app is awake in front of "
                 + "you — sleep pauses it, waking resumes it. "
                 + "It uses only the house's own organs: the "
                 + "sweep, the browse, the recon bench, the "
                 + "ear. Nothing is exploited and nothing is "
                 + "flooded; things are knocked on and "
                 + "listened to — loudly, and in the open.")
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
            Text("Every organ in the house, one continuous "
                 + "autonomous run: sweep the wire on "
                 + "rotating ports, let it announce itself, "
                 + "then knock the full census against every "
                 + "known device — pass after pass, for as "
                 + "long as you leave it armed. Everything "
                 + "it learns walks the usual roads: the "
                 + "Neighborhood, the Map, the sealed log, "
                 + "the mind underneath.")
                .font(.callout)
            Label("This is loud. It announces this phone to "
                  + "every device — and every watcher — on "
                  + "the wire. On networks you do not own it "
                  + "may trip intrusion detection, alerts, "
                  + "and logs with your name on them.",
                  systemImage: "exclamationmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Picker("Depth", selection: $depth) {
                Text("Sweep").tag(0)
                Text("+ Bonjour").tag(1)
                Text("Full").tag(2)
            }
            .pickerStyle(.segmented)
            Picker("Pause between passes",
                   selection: $restSeconds) {
                Text("30s").tag(30.0)
                Text("75s").tag(75.0)
                Text("3 min").tag(180.0)
            }
            .pickerStyle(.segmented)
            Text("How long the wire rests between one full "
                 + "pass — sweep, browse, knock — and the "
                 + "next. Shorter keeps the pressure "
                 + "continuous; longer revisits on a slower, "
                 + "quieter cadence.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                armRequest = true
            } label: {
                HStack {
                    SkullMark(color: .red, size: 18)
                    Text("Arm the net-assault")
                        .font(.body.weight(.bold))
                    Spacer()
                }
            }
            .foregroundStyle(.red)
            if center.passes > 0 {
                // A door, not a ShareLink: a bare ShareLink
                // buried in a List section cannot find a
                // presentation host in this app and dies
                // silently under the finger. The sheet
                // itself hangs off the screen's root.
                Button { shareRequest = true } label: {
                    Label("After-action report — last run",
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
            if let top = mind.insights.first {
                Text("The mind, watching: \(top.title)")
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
                    Text("Stand down")
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
        guard let data = gifData,
              let image = UIImage.animatedGIF(data: data)
        else { return 3.0 }
        return min(max(image.duration + 0.3, 1.5), 6.0)
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
                    Text("NET-ASSAULT")
                        .font(.title.monospaced().weight(.bold))
                        .tracking(5)
                        .foregroundStyle(.white)
                    Text("the wire will hear this phone coming")
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
