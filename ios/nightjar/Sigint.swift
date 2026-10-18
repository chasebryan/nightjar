import SwiftUI

// MARK: - The SIGINT Station
//
// One console where everything the phone can hear becomes one
// picture: a registry of emitters, one station timeline,
// recorded watches, and exports — built entirely from the
// sensors and engines the app already has. No dongles, no SDR,
// no companion hardware. The station adds no radio capability;
// it fuses the ones that exist and says so in its own UI.
//
// The held lines, written into the registry's rules: records
// merge ONLY within an epoch of continuous observation — no
// cross-epoch identity stitching, no location profiling of
// passersby. Receive-and-observe, plus the app's existing
// lawful probes on the operator's own wire (run from their
// own organs, under their own scope rules). No transmission
// interference of any kind. Knock contents never enter the
// timeline — arrivals, never contents.

/// One emitter, whatever kind it is: a BLE advertiser, a LAN
/// host. Keyed by the strongest identifier the emitter itself
/// offers. Identity is carried as claims, each labeled with
/// the channel that claimed it — the station repeats what was
/// heard, it does not crown it.
struct SigintEmitter: Identifiable, Codable {
    var key: String            // "ble:<address>" | "lan:<ip>"
    var kind: String           // "ble" | "lan"
    var label: String
    var claims: [String]       // "name — via BLE advertisement"
    var sources: [String]      // "listen" | "trace-logbook"
    var firstHeard: Date
    var lastHeard: Date
    var hearings: Int
    var rssiLast: Int?
    var rssiHistory: [Int]     // BLE only, capped
    var doors: [String]        // LAN only: "443/tcp · https"
    var trackerShaped: Bool
    var samples: [Int]         // heard-this-tick flags, capped

    var id: String { key }

    /// The station's working priority: how much an emitter
    /// matters to the operator's attention. Transparent on
    /// purpose — hearings, doors, independent sources, a
    /// tracker shape, and plain recency, nothing hidden.
    var priority: Int {
        var score = min(hearings, 50)
        score += doors.count * 4
        score += max(0, sources.count - 1) * 8
        if trackerShaped { score += 20 }
        if Date().timeIntervalSince(lastHeard) < 300 { score += 12 }
        if let rssi = rssiLast, rssi >= -60 { score += 6 }
        return score
    }
}

/// One recorded watch: a named, scoped span of the registry's
/// life, with its delta against the moment it began — new
/// emitters, vanished emitters, changed doors — and the
/// timeline slice it lived through.
struct SigintWatch: Identifiable, Codable {
    var id: String
    var name: String
    var scope: String          // "mixed" | "air" | "wire"
    var startedAt: Date
    var endedAt: Date
    var baseline: [SigintEmitter]
    var finalRegistry: [SigintEmitter]
    var timeline: [WarEvent]
    var newKeys: [String]
    var vanishedKeys: [String]
    var changedDoors: [String]
    var exportFilename: String?

    /// The delta in words — the shape Skelli reads back when
    /// asked what a watch found.
    var summaryText: String {
        func label(_ key: String) -> String {
            (finalRegistry + baseline)
                .first { $0.key == key }?.label ?? key
        }
        var parts: [String] = []
        if newKeys.isEmpty {
            parts.append("No new emitters.")
        } else {
            parts.append("\(newKeys.count) new: "
                + newKeys.prefix(4).map(label).joined(separator: ", ")
                + (newKeys.count > 4 ? "…" : "") + ".")
        }
        if !vanishedKeys.isEmpty {
            parts.append("\(vanishedKeys.count) went silent: "
                + vanishedKeys.prefix(3).map(label)
                    .joined(separator: ", ")
                + (vanishedKeys.count > 3 ? "…" : "") + ".")
        }
        if !changedDoors.isEmpty {
            parts.append("\(changedDoors.count) door(s) answered "
                + "differently: "
                + changedDoors.prefix(3).joined(separator: ", ")
                + (changedDoors.count > 3 ? "…" : "") + ".")
        }
        return parts.joined(separator: " ")
    }
}

/// The export document: `net.nosuchmachine.nightjar.sigint` v1.
struct SigintExport: Codable {
    struct WatchInfo: Codable {
        var id: String
        var name: String
        var scope: String
        var startedAt: Date
        var endedAt: Date
    }

    struct Delta: Codable {
        var newKeys: [String]
        var vanishedKeys: [String]
        var changedDoors: [String]
    }

    var schema: String
    var schemaVersion: Int
    var watch: WatchInfo
    var registry: [SigintEmitter]
    var timeline: [WarEvent]
    var delta: Delta
    var limitations: [String]

    static let limitations = [
        "No spectrum beyond Bluetooth is available to any iOS "
            + "app. This station fuses BLE hearing and the LAN "
            + "census; it has no other ears and claims none.",
        "Wi-Fi is visible only as the network this phone is "
            + "joined to, plus what the LAN census builds by "
            + "knocking — there is no monitor mode and no "
            + "neighbor-network visibility.",
        "Identities are as emitters claim them, per channel, "
            + "per epoch. Records merge only within one epoch "
            + "of continuous observation; nothing here stitches "
            + "an identity across epochs or profiles where a "
            + "passerby has been.",
        "RSSI is a rumor of distance, not a measurement.",
        "Knock and canary activity appears as arrivals and "
            + "verdicts only — contents never enter the record.",
        "A watch is a foreground instrument: iOS suspends "
            + "background work, and an emitter that never "
            + "transmits during the watch does not exist "
            + "for the station.",
    ]
}

// MARK: - The station

/// The shared station: the epoch registry, the unified
/// timeline, and the watch recorder. Shared so the console
/// view — and in time Skelli's hands — work the same room.
final class SigintStation: ObservableObject {
    static let shared = SigintStation()

    @Published private(set) var emitters: [SigintEmitter] = []
    @Published private(set) var timeline: [WarEvent] = []
    @Published private(set) var epochStart: Date?
    @Published private(set) var currentWatch: SigintWatch?
    @Published private(set) var lastWatch: SigintWatch?
    @Published private(set) var watches: [SigintWatch] = []

    private var timer: Timer?
    private weak var postRef: ListeningPost?
    private var attachCount = 0
    private var emitterIndex: [String: Int] = [:]
    private var doorSignatures: [String: [String: String]] = [:]
    private var seenJournalIDs: Set<String> = []
    private var lastHeardTick: [String: Date] = [:]
    private var startedListenForWatch = false

    private init() { loadWatches() }

    // MARK: presence

    /// Whether anything holds the fusion warm — the
    /// console, a watch, or Skelli's standing ask.
    var isAttached: Bool { attachCount > 0 }

    /// The console is on screen: keep the fusion warm.
    func attach(post: ListeningPost) {
        postRef = post
        attachCount += 1
        if epochStart == nil { beginEpoch() }
        ensureTimer()
    }

    func detach() {
        attachCount = max(0, attachCount - 1)
        if attachCount == 0, currentWatch == nil {
            timer?.invalidate()
            timer = nil
        }
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2,
                                     repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    // MARK: epochs

    /// A new epoch: the registry forgets, on purpose and out
    /// loud. Nothing is stitched across this line.
    func beginEpoch() {
        emitters = []
        emitterIndex = [:]
        timeline = []
        doorSignatures = [:]
        seenJournalIDs = []
        lastHeardTick = [:]
        epochStart = Date()
        addEvent(.run, "New epoch begun",
                 detail: "The registry starts empty. What is "
                    + "heard from here is this epoch's alone.",
                 source: "sigint")
    }

    // MARK: watches

    func startWatch(name: String, scope: String,
                    post: ListeningPost) {
        guard currentWatch == nil else { return }
        postRef = post
        if epochStart == nil { beginEpoch() }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let watch = SigintWatch(
            id: "watch-" + stamp.string(from: Date()),
            name: name.isEmpty ? "Untitled watch" : name,
            scope: scope,
            startedAt: Date(),
            endedAt: Date(),
            baseline: emitters,
            finalRegistry: [],
            timeline: [],
            newKeys: [], vanishedKeys: [], changedDoors: [])
        currentWatch = watch
        startedListenForWatch = false
        if scope != "wire", post.session == nil {
            post.start(label: "SIGINT watch")
            startedListenForWatch = true
            addEvent(.note, "Listen started for this watch",
                     detail: "It stops again when the watch "
                        + "ends, if the watch started it.",
                     source: "listen")
        }
        addEvent(.run, "Watch started — \(watch.name)",
                 detail: "Scope: \(scope)", source: "sigint")
        Journal.log("sigint", "watch",
                    "watch \(watch.id) started (\(scope))")
        ensureTimer()
    }

    func stopWatch(post: ListeningPost) {
        guard var watch = currentWatch else { return }
        watch.endedAt = Date()

        let baseline = scoped(watch.baseline, scope: watch.scope)
        let final = scoped(emitters, scope: watch.scope)
        let baseKeys = Set(baseline.map { $0.key })
        let finalKeys = Set(final.map { $0.key })
        watch.newKeys = finalKeys.subtracting(baseKeys)
            .sorted()
        watch.vanishedKeys = baseline
            .filter { emitter in
                !finalKeys.contains(emitter.key)
                    || emitter.lastHeard <= watch.startedAt
            }
            .map { $0.key }
            .sorted()
        var changed: [String] = []
        for emitter in final where baseKeys.contains(emitter.key) {
            guard let before = baseline
                .first(where: { $0.key == emitter.key }) else {
                continue
            }
            let beforeDoors = Set(before.doors)
            for door in emitter.doors
            where !beforeDoors.contains(door) {
                changed.append("\(emitter.label) \(door)")
            }
        }
        watch.changedDoors = changed.sorted()
        watch.finalRegistry = final
        watch.timeline = timeline.filter {
            $0.at >= watch.startedAt
                && scopeAllows($0, scope: watch.scope)
        }

        let filename = writeExport(for: watch)
        watch.exportFilename = filename
        currentWatch = nil
        lastWatch = watch
        watches.insert(watch, at: 0)
        watches = Array(watches.prefix(20))
        saveWatches()

        if startedListenForWatch {
            post.stop()
            startedListenForWatch = false
        }
        addEvent(.run, "Watch filed — \(watch.name)",
                 detail: watch.summaryText, source: "sigint")
        Journal.log("sigint", "watch",
                    "watch \(watch.id) filed — "
                    + "\(watch.newKeys.count) new, "
                    + "\(watch.vanishedKeys.count) silent, "
                    + "\(watch.changedDoors.count) changed")
    }

    /// Live count for the console: emitters in the current
    /// registry the running watch has not seen before.
    func newSinceWatchStart() -> Int {
        guard let watch = currentWatch else { return 0 }
        let baseKeys = Set(watch.baseline.map { $0.key })
        return emitters.filter { !baseKeys.contains($0.key) }.count
    }

    // MARK: fusion

    private func tick() {
        if let post = postRef { fuseBLE(rows: post.rows) }
        fuseLAN()
        fuseJournal()
        sampleActivity()
    }

    /// The air side of the fusion: Listen's current rows,
    /// upserted into the epoch registry.
    private func fuseBLE(rows: [DeviceRow]) {
        var heardNow: Set<String> = []
        for row in rows {
            let key = "ble:" + row.id
            heardNow.insert(key)
            let label = row.preferredLabel ?? row.name ?? row.kind
            var claims: [String] = []
            if let name = row.name {
                claims.append("\(name) — via BLE advertisement")
            }
            claims += row.details.prefix(3)
                .map { "\($0) — via BLE decode" }
            upsert(key: key, kind: "ble", label: label,
                   claims: claims, source: "listen",
                   first: Date(timeIntervalSince1970: row.firstSeen),
                   last: Date(timeIntervalSince1970: row.lastSeen),
                   hearings: row.sightings,
                   rssi: row.rssiLast,
                   rssiHistory: row.rssiHistory,
                   doors: [],
                   tracker: row.trackerShaped)
        }
    }

    private func fuseLAN() {
        guard let epochStart = epochStart else { return }
        for host in TraceBookStore.shared.allDossiers()
        where host.lastSeen >= epochStart
                || emitterIndex["lan:" + host.ip] != nil {
            let key = "lan:" + host.ip
            let doors = host.services.map {
                "\($0.port)/\($0.proto) · \($0.serviceName)"
            }
            var claims = host.names
                .map { "\($0) — via the LAN census" }
            claims += host.tags.prefix(2)
                .map { "\($0) — via the census" }
            upsert(key: key, kind: "lan",
                   label: host.names.first ?? host.ip,
                   claims: claims, source: "trace-logbook",
                   first: host.firstSeen, last: host.lastSeen,
                   hearings: host.timesSeen,
                   rssi: nil, rssiHistory: [],
                   doors: doors, tracker: false)
            // Door-level change against the epoch's memory.
            var sigs = doorSignatures[key] ?? [:]
            for service in host.services {
                let doorID = "\(service.port)/\(service.proto)"
                if sigs[doorID] == nil,
                   emitterIndex[key] != nil {
                    addEvent(.door,
                             "Door \(host.ip):\(service.port)/\(service.proto)",
                             detail: service.bannerFirstLine.isEmpty
                                ? service.serviceName
                                : service.bannerFirstLine,
                             source: "trace-logbook")
                } else if let old = sigs[doorID],
                          old != service.signature {
                    addEvent(.banner,
                             "Banner changed \(host.ip):\(service.port)",
                             detail: service.bannerFirstLine,
                             source: "trace-logbook")
                }
                sigs[doorID] = service.signature
            }
            doorSignatures[key] = sigs
        }
    }

    /// Knock, canary and verdict activity from the Night log:
    /// arrivals and outcomes, never contents — the journal
    /// itself keeps that rule, and the station inherits it.
    private func fuseJournal() {
        guard let epochStart = epochStart else { return }
        let interesting: Set<String> = [
            "emcon", "canary", "knocktalk", "steward",
            "conductor", "war-room", "sigint", "assault",
        ]
        for event in Journal.events(limit: 200).reversed()
        where event.when >= epochStart
            && !seenJournalIDs.contains(event.id) {
            seenJournalIDs.insert(event.id)
            let kindText = (event.module + " " + event.kind)
                .lowercased()
            guard interesting.contains(event.module)
                    || kindText.contains("knock")
                    || kindText.contains("canary")
                    || kindText.contains("tripwire")
            else { continue }
            addEvent(.note, "\(event.module) · \(event.kind)",
                     detail: event.text, source: "night-log",
                     at: event.when)
        }
    }

    private func sampleActivity() {
        for index in emitters.indices {
            let key = emitters[index].key
            let heard = (lastHeardTick[key] ?? .distantPast)
                >= Date().addingTimeInterval(-2.5)
            emitters[index].samples.append(heard ? 1 : 0)
            if emitters[index].samples.count > 40 {
                emitters[index].samples
                    .removeFirst(emitters[index].samples.count - 40)
            }
        }
    }

    private func upsert(key: String, kind: String, label: String,
                        claims: [String], source: String,
                        first: Date, last: Date, hearings: Int,
                        rssi: Int?, rssiHistory: [Int],
                        doors: [String], tracker: Bool) {
        if let index = emitterIndex[key] {
            var emitter = emitters[index]
            emitter.label = label
            emitter.lastHeard = max(emitter.lastHeard, last)
            emitter.firstHeard = min(emitter.firstHeard, first)
            emitter.hearings = max(emitter.hearings, hearings)
            if let rssi = rssi {
                emitter.rssiLast = rssi
            }
            if last > (lastHeardTick[key] ?? .distantPast) {
                lastHeardTick[key] = last
            }
            if !rssiHistory.isEmpty {
                emitter.rssiHistory = Array(rssiHistory.suffix(24))
            }
            if !doors.isEmpty { emitter.doors = doors }
            if !claims.isEmpty {
                emitter.claims = Array(Set(emitter.claims + claims))
                    .sorted()
            }
            if !emitter.sources.contains(source) {
                emitter.sources.append(source)
            }
            emitter.trackerShaped = emitter.trackerShaped || tracker
            emitters[index] = emitter
        } else {
            let emitter = SigintEmitter(
                key: key, kind: kind, label: label,
                claims: claims, sources: [source],
                firstHeard: first, lastHeard: last,
                hearings: hearings, rssiLast: rssi,
                rssiHistory: Array(rssiHistory.suffix(24)),
                doors: doors, trackerShaped: tracker,
                samples: [])
            emitterIndex[key] = emitters.count
            emitters.append(emitter)
            lastHeardTick[key] = last
            addEvent(kind == "ble" ? .sighting : .host,
                     kind == "ble" ? label : "Host \(label)",
                     detail: key, source: source, at: last)
        }
    }

    private func addEvent(_ kind: WarEvent.Kind, _ label: String,
                          detail: String = "", source: String,
                          at: Date = Date()) {
        guard timeline.count < 600 else { return }
        timeline.append(WarEvent(kind: kind, label: label,
                                 detail: detail, source: source,
                                 at: at))
    }

    // MARK: scope

    private func scoped(_ list: [SigintEmitter],
                        scope: String) -> [SigintEmitter] {
        switch scope {
        case "air": return list.filter { $0.kind == "ble" }
        case "wire": return list.filter { $0.kind == "lan" }
        default: return list
        }
    }

    private func scopeAllows(_ event: WarEvent,
                             scope: String) -> Bool {
        switch scope {
        case "air":
            return event.kind == .sighting
                || event.source == "night-log"
                || event.kind == .run || event.kind == .note
        case "wire":
            return event.kind == .host || event.kind == .door
                || event.kind == .banner
                || event.source == "night-log"
                || event.kind == .run || event.kind == .note
        default:
            return true
        }
    }

    // MARK: files

    private var sigintDirectory: URL {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sigint", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeExport(for watch: SigintWatch) -> String? {
        let export = SigintExport(
            schema: "net.nosuchmachine.nightjar.sigint",
            schemaVersion: 1,
            watch: SigintExport.WatchInfo(
                id: watch.id, name: watch.name,
                scope: watch.scope,
                startedAt: watch.startedAt,
                endedAt: watch.endedAt),
            registry: watch.finalRegistry,
            timeline: watch.timeline,
            delta: SigintExport.Delta(
                newKeys: watch.newKeys,
                vanishedKeys: watch.vanishedKeys,
                changedDoors: watch.changedDoors),
            limitations: SigintExport.limitations)
        let filename = "nightjar-" + watch.id + ".json"
        let url = sigintDirectory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else {
            return nil
        }
        do {
            try data.write(to: url, options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    func exportURL(for watch: SigintWatch) -> URL? {
        guard let filename = watch.exportFilename else { return nil }
        return sigintDirectory.appendingPathComponent(filename)
    }

    private func saveWatches() {
        let url = sigintDirectory
            .appendingPathComponent("watches.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(watches) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadWatches() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sigint")
            .appendingPathComponent("watches.json")
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([SigintWatch].self,
                                           from: data) {
            watches = saved
            lastWatch = saved.first
        }
    }
}

// MARK: - The console

/// How long ago, in the station's own shorthand.
private func sigintAgo(_ date: Date) -> String {
    let secs = max(0, Int(Date().timeIntervalSince(date)))
    if secs < 60 { return "\(secs)s ago" }
    if secs < 3600 { return "\(secs / 60)m ago" }
    if secs < 86400 { return "\(secs / 3600)h ago" }
    return "\(secs / 86400)d ago"
}

/// A per-emitter activity strip: BLE draws its RSSI history
/// (a rumor of distance, and the caption says so); LAN draws
/// heard-per-tick samples across the epoch.
struct SigintStripView: View {
    let emitter: SigintEmitter

    private var bars: [Double] {
        if emitter.kind == "ble" {
            return emitter.rssiHistory.suffix(24).map {
                min(1, max(0.08, (Double($0) + 100) / 65))
            }
        }
        return emitter.samples.suffix(24).map { $0 == 0 ? 0.08 : 1 }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 4,
                           height: 3 + 19 * bars[index])
            }
        }
        .foregroundStyle(.secondary)
        .frame(height: 24, alignment: .bottom)
    }
}

struct SigintStationView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var station = SigintStation.shared
    @State private var watchName = ""
    @State private var watchScope = "mixed"
    @State private var sortMode = "priority"
    @State private var showAllTimeline = false
    @State private var shareItem: ShareItem?
    @State private var confirmEpoch = false

    private var sortedEmitters: [SigintEmitter] {
        switch sortMode {
        case "recent":
            return station.emitters.sorted {
                $0.lastHeard > $1.lastHeard
            }
        case "signal":
            return station.emitters.sorted {
                ($0.rssiLast ?? -999) > ($1.rssiLast ?? -999)
            }
        default:
            return station.emitters.sorted {
                $0.priority > $1.priority
            }
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("SIGINT Station",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                    Spacer()
                    if let epoch = station.epochStart {
                        Text("epoch \(sigintAgo(epoch))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(station.emitters.filter { $0.kind == "ble" }.count) "
                    + "in the air · "
                    + "\(station.emitters.filter { $0.kind == "lan" }.count) "
                    + "on the wire · one registry, merged only "
                    + "within this epoch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Everything here is fused from organs the "
                    + "app already has — Listen's hearing, the "
                    + "LAN census, the Night log. No new ears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            watchSection

            if let watch = station.lastWatch,
               station.currentWatch == nil {
                Section("Last watch — \(watch.name)") {
                    Text(watch.summaryText).font(.callout)
                    if let url = station.exportURL(for: watch) {
                        Button {
                            Haptics.select()
                            shareItem = ShareItem(items: [url])
                        } label: {
                            Label("Share the watch export",
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }

            Section("Registry — \(station.emitters.count)") {
                Picker("Order", selection: $sortMode) {
                    Text("Priority").tag("priority")
                    Text("Last heard").tag("recent")
                    Text("Signal").tag("signal")
                }
                .pickerStyle(.segmented)
                if station.emitters.isEmpty {
                    Text("Nothing heard yet in this epoch. "
                        + "Start Listen, run a trace or a War "
                        + "Room operation — the registry fills "
                        + "from what the organs hear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedEmitters) { emitter in
                    NavigationLink {
                        SigintEmitterView(key: emitter.key,
                                          snapshot: emitter)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: emitter.kind == "ble"
                                  ? "wave.3.right"
                                  : "network")
                                .foregroundStyle(emitter.kind == "ble"
                                                 ? .purple : .blue)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(emitter.label)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text(emitter.kind == "ble"
                                     ? "\(emitter.hearings)× · "
                                        + sigintAgo(emitter.lastHeard)
                                     : "\(emitter.doors.count) door(s) · "
                                        + sigintAgo(emitter.lastHeard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if emitter.trackerShaped {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                            }
                            if let rssi = emitter.rssiLast {
                                Text("\(rssi)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(emitter.priority)")
                                .font(.caption2.weight(.semibold)
                                    .monospacedDigit())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.quaternary,
                                            in: Capsule())
                        }
                    }
                }
            }

            if !station.timeline.isEmpty {
                Section("Timeline — \(station.timeline.count)") {
                    ForEach(visibleTimeline) { event in
                        HStack(alignment: .firstTextBaseline,
                               spacing: 8) {
                            Image(systemName: timelineIcon(event.kind))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.label).font(.callout)
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
                    if station.timeline.count > 40 {
                        Button(showAllTimeline
                               ? "Fold — latest 40"
                               : "Show all \(station.timeline.count)") {
                            showAllTimeline.toggle()
                        }
                    }
                }
            }

            if station.watches.count > 1
                || (station.watches.count == 1
                    && station.lastWatch == nil) {
                Section("Filed watches") {
                    ForEach(station.watches) { watch in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(watch.name).font(.callout)
                                Text(watch.startedAt.formatted(
                                    date: .abbreviated,
                                    time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = station
                                .exportURL(for: watch) {
                                Button {
                                    Haptics.select()
                                    shareItem = ShareItem(items: [url])
                                } label: {
                                    Image(systemName:
                                        "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Begin a new epoch", role: .destructive) {
                    confirmEpoch = true
                }
                .disabled(station.currentWatch != nil)
                Text("A new epoch empties the registry and the "
                    + "timeline. Nothing is stitched across the "
                    + "line — an emitter heard again is a new "
                    + "record, by design.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("The station's limits, in its own words: "
                    + "no spectrum beyond Bluetooth is available "
                    + "to any iOS app; Wi-Fi is visible only as "
                    + "the joined network plus what the census "
                    + "builds by knocking; identities are as "
                    + "emitters claim them, per channel, per "
                    + "epoch. Receive and observe — the station "
                    + "never interferes with the spectrum it "
                    + "watches.")
                    .font(.caption)
            }
        }
        .navigationTitle("SIGINT Station")
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .confirmationDialog("Begin a new epoch?",
                            isPresented: $confirmEpoch) {
            Button("Empty the registry", role: .destructive) {
                station.beginEpoch()
                showAllTimeline = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The registry and timeline clear. Filed "
                + "watches are kept.")
        }
        .onAppear { station.attach(post: post) }
        .onDisappear { station.detach() }
    }

    @ViewBuilder private var watchSection: some View {
        Section("Watch") {
            if let watch = station.currentWatch {
                HStack {
                    Label("Recording — \(watch.name)",
                          systemImage: "record.circle")
                        .foregroundStyle(.red)
                    Spacer()
                    Text(sigintAgo(watch.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(station.newSinceWatchStart()) new "
                    + "emitter(s) since this watch began.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    Haptics.tap()
                    station.stopWatch(post: post)
                } label: {
                    Label("Stop and file the watch",
                          systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                TextField("Watch name", text: $watchName)
                Picker("Scope", selection: $watchScope) {
                    Text("Air + wire").tag("mixed")
                    Text("Air only").tag("air")
                    Text("Wire only").tag("wire")
                }
                .pickerStyle(.segmented)
                Button {
                    Haptics.tap()
                    station.startWatch(
                        name: watchName.trimmingCharacters(
                            in: .whitespaces),
                        scope: watchScope, post: post)
                    watchName = ""
                } label: {
                    Label("Start the watch",
                          systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("A watch records the registry and the "
                    + "timeline under a name, then files itself "
                    + "with its delta: what arrived, what went "
                    + "silent, what changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var visibleTimeline: [WarEvent] {
        let ordered = Array(station.timeline.reversed())
        return showAllTimeline ? ordered : Array(ordered.prefix(40))
    }

    private func timelineIcon(_ kind: WarEvent.Kind) -> String {
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
}

// MARK: - One emitter

struct SigintEmitterView: View {
    @EnvironmentObject private var post: ListeningPost
    @ObservedObject private var station = SigintStation.shared
    let key: String
    let snapshot: SigintEmitter

    private var emitter: SigintEmitter {
        station.emitters.first { $0.key == key } ?? snapshot
    }

    /// For a BLE emitter, the raw address behind the key —
    /// the Hunt's target when the device is in earshot now.
    private var bleAddress: String? {
        guard emitter.kind == "ble" else { return nil }
        return String(emitter.key.dropFirst(4))
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(emitter.label).font(.headline)
                    SigintStripView(emitter: emitter)
                    Text(emitter.kind == "ble"
                         ? "Signal history — RSSI is a rumor "
                            + "of distance, not a measurement."
                         : "Activity across this epoch's ticks.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("The record") {
                LabeledContent("Kind",
                               value: emitter.kind == "ble"
                                ? "BLE advertiser" : "LAN host")
                LabeledContent("Key", value: emitter.key)
                LabeledContent("First heard",
                               value: emitter.firstHeard.formatted(
                                date: .abbreviated, time: .standard))
                LabeledContent("Last heard",
                               value: sigintAgo(emitter.lastHeard))
                LabeledContent("Hearings",
                               value: "\(emitter.hearings)")
                if let rssi = emitter.rssiLast {
                    LabeledContent("Last RSSI", value: "\(rssi) dBm")
                }
                LabeledContent("Heard by",
                               value: emitter.sources
                                .joined(separator: ", "))
                if emitter.trackerShaped {
                    Label("Tracker-shaped advertiser",
                          systemImage: "location.fill")
                        .foregroundStyle(.orange)
                }
            }

            if !emitter.claims.isEmpty {
                Section("Identity — as claimed") {
                    ForEach(emitter.claims, id: \.self) { claim in
                        Text(claim).font(.callout)
                    }
                    Text("Claims are what the emitter said, on "
                        + "the channel noted — repeated here, "
                        + "not crowned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !emitter.doors.isEmpty {
                Section("Doors — \(emitter.doors.count)") {
                    ForEach(emitter.doors, id: \.self) { door in
                        Text(door).font(.callout.monospaced())
                    }
                }
            }

            if let address = bleAddress,
               post.rows.contains(where: { $0.id == address }) {
                Section {
                    NavigationLink {
                        HuntView(targetID: address)
                    } label: {
                        Label("Hunt this emitter",
                              systemImage: "location.magnifyingglass")
                    }
                    Text("The Hunt walks you onto the signal "
                        + "with Listen's own ears.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Emitter")
    }
}
