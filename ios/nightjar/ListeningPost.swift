import Combine
import CoreBluetooth
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The listening post: one `CBCentralManager`, one session at a time.
///
/// Receive-only, by construction: the only CoreBluetooth calls in this
/// file are `scanForPeripherals` and `stopScan`. There is no `connect`,
/// no GATT, no pairing in the listening post. (This is the nightjar
/// build: the transmitting engines live in Mouth.swift, in separate
/// managers the listener never touches. The ear stays pure; the mouth
/// is a different organ.)
final class ListeningPost: NSObject, ObservableObject {
    struct ActiveSession {
        let id: String
        let label: String?
        let startedAt: TimeInterval
        let url: URL
    }

    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var session: ActiveSession?
    @Published private(set) var rows: [DeviceRow] = []
    @Published private(set) var sightingCount = 0
    @Published private(set) var deviceCount = 0
    @Published private(set) var inBackground = false
    @Published private(set) var lastError: String?

    /// Keep the screen on while a session runs (foreground sessions hear
    /// the most, and a dark phone in a pocket is a locked phone).
    var keepScreenAwake = true {
        didSet { applyIdleTimer() }
    }

    private static let restoreIdentifier = "net.nosuchmachine.nightjarhack.central"
    private static let activeSessionKey = "nightjar.activeSession"

    /// The service UUIDs iOS will keep delivering in the background. A
    /// backgrounded scan for *everything* hears nothing on iOS; a scan
    /// for these still hears the tags that matter most.
    static let backgroundServices: [CBUUID] = [
        CBUUID(string: "FEED"),  // Tile
        CBUUID(string: "FEEC"),  // Tile
        CBUUID(string: "FD5A"),  // Samsung SmartThings Find
        CBUUID(string: "FEAA"),  // Eddystone / Google Find My Device network
        CBUUID(string: "FE2C"),  // Google Fast Pair
        CBUUID(string: "FD44"),  // Apple Find My accessory service (rare in beacons)
    ]

    private var central: CBCentralManager!
    /// The ear's own serial queue: every
    /// advertisement is received, decoded, and
    /// filed HERE, never on the main queue —
    /// in a busy room the pipeline runs at
    /// advertisement rate, and the interface
    /// must never pay for it (the sweep's
    /// finding P1, 2026-10-18). `devices`,
    /// `sightingsSeen`, `dirty`, `sessionActive`,
    /// and `backgroundMode` are confined to
    /// this queue; the published face (rows,
    /// counts, state) hops to main.
    private let bleQueue = DispatchQueue(
        label: "nightjar.listen.ble")
    private let bleKey = DispatchSpecificKey<
        Void>()
    /// Queue-confined mirrors of the published
    /// session state, so delegate callbacks
    /// never read main-owned state.
    private var sessionActive = false
    private var backgroundMode = false
    private var devices: [String: DeviceRow] = [:]
    private var rankOrder: [String] = []
    private var lastRankAt: TimeInterval = 0
    private var writer: JSONLWriter?
    private var ticker: Timer?
    private var dirty = false
    private var sightingsSeen = 0  // published once a second, not per packet
    private var restoring = false  // iOS relaunched us to continue a scan

    override init() {
        super.init()
        bleQueue.setSpecific(key: bleKey, value: ())
        central = CBCentralManager(delegate: self, queue: bleQueue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: ListeningPost.restoreIdentifier,
        ])
    }

    var isListening: Bool { return session != nil }

    /// Run work on the BLE queue, inline when
    /// already there (a delegate callback
    /// stopping the session must not deadlock
    /// on its own queue).
    private func onBle(_ work: () -> Void) {
        if DispatchQueue.getSpecific(key: bleKey)
            != nil {
            work()
        } else {
            bleQueue.sync(execute: work)
        }
    }

    /// This post's name, for the log header — which ear heard it. The user
    /// sets it on the About tab (so the Mac's fusion can tell the phone
    /// apart from the Mac); defaults to "phone".
    static func postName() -> String? {
        let stored = UserDefaults.standard.string(forKey: "postName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored = stored, !stored.isEmpty {
            return stored
        }
        return "phone"
    }

    // MARK: - Session control

    func start(label rawLabel: String) {
        guard session == nil else { return }
        Haptics.start()
        let trimmed = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let label: String? = trimmed.isEmpty ? nil : trimmed
        let startedAt = Date().timeIntervalSince1970
        let id = SessionStore.newSessionID()
        let url = SessionStore.newFileURL(sessionID: id, startedAt: startedAt)

        let writer = JSONLWriter(url: url)
        do {
            try writer.open()
        } catch {
            lastError = "Could not create the log file: \(error.localizedDescription)"
            return
        }
        var header: [(String, String)] = [
            ("type", JSONL.string("session")),
            ("session_id", JSONL.string(id)),
            ("label", JSONL.optionalString(label)),
            ("label_source", JSONL.optionalString(label == nil ? nil : "manual")),
            ("started_at", JSONL.seconds(startedAt)),
            ("scan_mode", JSONL.string("active")),
            ("format", "1"),
            ("nightjar_version", JSONL.string("ios-\(AppInfo.version)")),
        ]
        if let post = Self.postName() {
            header.append(("post", JSONL.string(post)))
        }
        writer.append(JSONL.object(header))
        writer.flush()
        self.writer = writer

        let active = ActiveSession(id: id, label: label, startedAt: startedAt, url: url)
        session = active
        Journal.log("listen", "session",
                    "listening started"
                    + (label.map { " — \($0)" } ?? ""))
        remember(active)
        onBle {
            devices = [:]
            sightingsSeen = 0
            sessionActive = true
            backgroundMode = inBackground
        }
        rows = []
        sightingCount = 0
        deviceCount = 0
        lastError = nil
        startTicker()
        applyIdleTimer()
        bleQueue.async { [weak self] in
            self?.scan()
        }
    }

    func stop() {
        // The radio's death calls this from the
        // BLE queue; the session's face lives on
        // main. Silence the confined side on the
        // spot, then settle the rest on main.
        if DispatchQueue.getSpecific(key: bleKey)
            != nil {
            onBle { sessionActive = false }
            central.stopScan()
            DispatchQueue.main.async {
                [weak self] in self?.stop() }
            return
        }
        guard let active = session else { return }
        Haptics.finish()
        onBle { sessionActive = false }
        central.stopScan()
        if let writer = writer {
            var heard = 0
            onBle { heard = sightingsSeen }
            writer.append(JSONL.object([
                ("type", JSONL.string("session_end")),
                ("session_id", JSONL.string(active.id)),
                ("ended_at", JSONL.seconds(Date().timeIntervalSince1970)),
                ("sightings", String(heard)),
            ]))
            writer.close()
        }
        writer = nil
        session = nil
        var heardNow = 0
        onBle { heardNow = sightingsSeen }
        Journal.log("listen", "session",
                    "listening stopped — \(heardNow) sightings")
        forgetActiveSession()
        stopTicker()
        applyIdleTimer()
        publishRows()
    }

    // MARK: - Scanning

    /// Queue-confined: call only on bleQueue.
    private func scan() {
        guard sessionActive,
              central.state == .poweredOn else { return }
        central.stopScan()
        if backgroundMode {
            central.scanForPeripherals(withServices: ListeningPost.backgroundServices, options: nil)
        } else {
            // Repeated advertisements are the point: RSSI movement is data.
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
            ])
        }
    }

    func sceneDidChange(toBackground background: Bool) {
        guard background != inBackground else { return }
        inBackground = background
        writer?.flush()
        bleQueue.async { [weak self] in
            guard let self else { return }
            backgroundMode = background
            if sessionActive { scan() }
        }
    }

    // MARK: - Bookkeeping

    private func startTicker() {
        // Timers live on the main run loop,
        // whichever queue asked.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
    }

    private func stopTicker() {
        DispatchQueue.main.async { [weak self] in
            self?.ticker?.invalidate()
            self?.ticker = nil
        }
    }

    private func tick() {
        writer?.flush()
        bleQueue.async { [weak self] in
            guard let self, dirty else { return }
            publishRowsOnQueue()
        }
    }

    private func publishRows() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            publishRowsOnQueue()
        }
    }

    private func publishRowsOnQueue() {
        let now = Date().timeIntervalSince1970
        // The registry is not a hoard either
        // (finding F9): past 150 devices, rows
        // unheard for ten minutes are evicted —
        // pinned shapes (trackers, flares) are
        // exempt; they are the point of the post.
        if devices.count > 150 {
            devices = devices.filter { _, row in
                now - row.lastSeen <= 600
                    || row.trackerShaped || row.flare
            }
        }
        // Contents (ages, signal, counts) refresh every tick,
        // but the ORDER is re-ranked on a slow cadence, and
        // even then a device climbs only by clearing the one
        // above it by a margin (see ranked()). RSSI jitters by
        // several dB between advertisements; sorting on the
        // raw value every second made the list dance faster
        // than anyone could read or tap it. Positions now
        // settle and drift — the perimeter, not the noise.
        if now - lastRankAt >= 5 || rankOrder.isEmpty {
            lastRankAt = now
            rankOrder = Self.ranked(devices: devices,
                                    previous: rankOrder, now: now)
        }
        var ordered = rankOrder.compactMap { devices[$0] }
        let rankedIDs = Set(rankOrder)
        ordered += devices.values
            .filter { !rankedIDs.contains($0.id) }
            .sorted { ($0.rssiSmooth ?? -200)
                > ($1.rssiSmooth ?? -200) }
        // The trace borrows the ear's picture of the room:
        // note the current registry (as plain values) so a
        // finished trace can file the air alongside the
        // wires. Collection itself is untouched — this only
        // reads what publishRows already built.
        BLESightings.note(ordered.map { row in
            TraceBLEDevice(
                id: row.id,
                name: row.name ?? row.preferredLabel,
                kind: row.kind,
                vendor: row.makers.isEmpty ? nil
                    : row.makers.sorted().joined(separator: ", "),
                serviceUUIDs: row.serviceUUIDs,
                rotatingAddress: row.rotatingAddress,
                firstHeard: Date(timeIntervalSince1970: row.firstSeen),
                lastHeard: Date(timeIntervalSince1970: row.lastSeen),
                sightings: row.sightings,
                closestRSSI: row.rssiClosest,
                smoothedRSSI: row.rssiSmooth)
        })
        let totalDevices = devices.count
        let totalSightings = sightingsSeen
        dirty = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            rows = ordered
            deviceCount = totalDevices
            sightingCount = totalSightings
        }
    }

    /// The settled order: keep the previous one, let
    /// newcomers join by smoothed RSSI, then settle into
    /// tiers — the pinned, the active, the quiet — with
    /// hysteresis passes inside each tier (a device
    /// overtakes only when its smoothed RSSI beats the
    /// device above by the margin). The pin and the
    /// patience are kind-aware: tracker-class beacons
    /// advertise slowly and intermittently BY DESIGN,
    /// so the old flat 20-second quiet sink buried
    /// exactly the devices this post exists to catch.
    /// Trackers go quiet on a minutes scale, and while
    /// they are about they hold the top — as does a
    /// flare, a key-holder in radio range.
    private static func ranked(devices: [String: DeviceRow],
                               previous: [String],
                               now: TimeInterval) -> [String] {
        var order = previous.filter { devices[$0] != nil }
        let known = Set(order)
        let newcomers = devices.values
            .filter { !known.contains($0.id) }
            .sorted { ($0.rssiSmooth ?? -200)
                > ($1.rssiSmooth ?? -200) }
        order += newcomers.map { $0.id }
        func isPinned(_ id: String) -> Bool {
            guard let row = devices[id] else { return false }
            return row.trackerShaped || row.flare
        }
        func isQuiet(_ id: String) -> Bool {
            let limit: TimeInterval = isPinned(id) ? 300 : 20
            return (devices[id]?.age(now: now) ?? 0) > limit
        }
        func tier(_ id: String) -> Int {
            if isPinned(id), !isQuiet(id) { return 0 }
            return isQuiet(id) ? 2 : 1
        }
        func smooth(_ id: String) -> Double {
            devices[id]?.rssiSmooth ?? -200
        }
        order = order.filter { tier($0) == 0 }
            + order.filter { tier($0) == 1 }
            + order.filter { tier($0) == 2 }
        let margin = 3.0
        if order.count > 1 {
            for _ in 0..<3 {
                var swapped = false
                for i in 0..<(order.count - 1) {
                    let a = order[i], b = order[i + 1]
                    if tier(a) == tier(b),
                       smooth(b) > smooth(a) + margin {
                        order.swapAt(i, i + 1)
                        swapped = true
                    }
                }
                if !swapped { break }
            }
        }
        return order
    }

    private func applyIdleTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
#if os(iOS)
            UIApplication.shared
                .isIdleTimerDisabled =
                keepScreenAwake && session != nil
#endif
        }
    }

    private func remember(_ active: ActiveSession) {
        let record: [String: Any] = [
            "id": active.id,
            "label": active.label ?? "",
            "started_at": active.startedAt,
            "path": active.url.lastPathComponent,
        ]
        UserDefaults.standard.set(record, forKey: ListeningPost.activeSessionKey)
    }

    private func forgetActiveSession() {
        UserDefaults.standard.removeObject(forKey: ListeningPost.activeSessionKey)
    }

    /// After iOS relaunched us in the background (state restoration), pick
    /// the interrupted session back up and keep appending to its file —
    /// no new header, the Mac side sees one continuous run. On an ordinary
    /// launch a leftover record means the app was force-quit mid-session;
    /// that log stays as it is (listed as unfinished) and is not resumed.
    private func resumeInterruptedSessionIfAny() {
        guard session == nil,
              let record = UserDefaults.standard.dictionary(forKey: ListeningPost.activeSessionKey),
              let id = record["id"] as? String,
              let startedAt = record["started_at"] as? Double,
              let path = record["path"] as? String else {
            return
        }
        guard restoring else {
            forgetActiveSession()
            return
        }
        restoring = false
        let url = SessionStore.directory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            forgetActiveSession()
            return
        }
        let writer = JSONLWriter(url: url)
        guard (try? writer.open()) != nil else {
            forgetActiveSession()
            return
        }
        let label = record["label"] as? String
        self.writer = writer
        let resumed = ActiveSession(
            id: id,
            label: (label?.isEmpty ?? true)
                ? nil : label,
            startedAt: startedAt, url: url)
        let heard = SessionStore.countSightings(
            in: url)
        // On the delegate queue here: set the
        // confined state directly, and publish
        // the session's face on main.
        sightingsSeen = heard
        sessionActive = true
        backgroundMode = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            session = resumed
            sightingCount = heard
            startTicker()
            applyIdleTimer()
        }
        scan()
    }
}

// MARK: - CBCentralManagerDelegate

extension ListeningPost: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        DispatchQueue.main.async { [weak self] in
            self?.bluetoothState = state
        }
        if central.state == .poweredOn {
            resumeInterruptedSessionIfAny()
            scan()
        } else if sessionActive {
            // The radio left .poweredOn mid-session: the scan is
            // gone, so finalize the log through the normal end
            // path (footer, close, Forget) instead of leaving a
            // session that claims to still be recording.
            stop()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // iOS relaunched the app because a scan was in progress. The
        // session itself is restored once the radio reports powered on.
        restoring = true
        backgroundMode = true
        DispatchQueue.main.async { [weak self] in
            self?.inBackground = true
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard sessionActive else { return }
        let sighting = Sighting(peripheral: peripheral, advertisementData: advertisementData,
                                rssi: RSSI)
        writer?.append(sighting.jsonLine)
        sightingsSeen += 1
        if var row = devices[sighting.address] {
            row.observe(sighting)
            devices[sighting.address] = row
        } else {
            devices[sighting.address] = DeviceRow(sighting: sighting)
        }
        dirty = true
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return short ?? "1.0"
    }
}
