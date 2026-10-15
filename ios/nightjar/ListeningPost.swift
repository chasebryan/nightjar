import Combine
import CoreBluetooth
import Foundation
import UIKit

/// The listening post: one `CBCentralManager`, one session at a time.
///
/// Receive-only, by construction: the only CoreBluetooth calls in this
/// file are `scanForPeripherals` and `stopScan`. There is no `connect`,
/// no GATT, no pairing anywhere in the app.
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

    private static let restoreIdentifier = "net.nosuchmachine.nightjar.central"
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
    private var devices: [String: DeviceRow] = [:]
    private var writer: JSONLWriter?
    private var ticker: Timer?
    private var dirty = false
    private var sightingsSeen = 0  // published once a second, not per packet
    private var restoring = false  // iOS relaunched us to continue a scan

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerOptionRestoreIdentifierKey: ListeningPost.restoreIdentifier,
        ])
    }

    var isListening: Bool { return session != nil }

    // MARK: - Session control

    func start(label rawLabel: String) {
        guard session == nil else { return }
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
        writer.append(JSONL.object([
            ("type", JSONL.string("session")),
            ("session_id", JSONL.string(id)),
            ("label", JSONL.optionalString(label)),
            ("label_source", JSONL.optionalString(label == nil ? nil : "manual")),
            ("started_at", JSONL.seconds(startedAt)),
            ("scan_mode", JSONL.string("active")),
            ("format", "1"),
            ("nightjar_version", JSONL.string("ios-\(AppInfo.version)")),
        ]))
        writer.flush()
        self.writer = writer

        let active = ActiveSession(id: id, label: label, startedAt: startedAt, url: url)
        session = active
        remember(active)
        devices = [:]
        rows = []
        sightingsSeen = 0
        sightingCount = 0
        deviceCount = 0
        lastError = nil
        startTicker()
        applyIdleTimer()
        scan()
    }

    func stop() {
        guard let active = session else { return }
        central.stopScan()
        if let writer = writer {
            writer.append(JSONL.object([
                ("type", JSONL.string("session_end")),
                ("session_id", JSONL.string(active.id)),
                ("ended_at", JSONL.seconds(Date().timeIntervalSince1970)),
                ("sightings", String(sightingsSeen)),
            ]))
            writer.close()
        }
        writer = nil
        session = nil
        forgetActiveSession()
        stopTicker()
        applyIdleTimer()
        publishRows()
    }

    // MARK: - Scanning

    private func scan() {
        guard session != nil, central.state == .poweredOn else { return }
        central.stopScan()
        if inBackground {
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
        if session != nil {
            scan()
        }
    }

    // MARK: - Bookkeeping

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        writer?.flush()
        if dirty {
            publishRows()
        }
    }

    private func publishRows() {
        let now = Date().timeIntervalSince1970
        rows = devices.values.sorted { lhs, rhs in
            let lhsQuiet = lhs.age(now: now) > 20
            let rhsQuiet = rhs.age(now: now) > 20
            if lhsQuiet != rhsQuiet { return !lhsQuiet }
            return (lhs.rssiLast ?? -200) > (rhs.rssiLast ?? -200)
        }
        deviceCount = devices.count
        sightingCount = sightingsSeen
        dirty = false
    }

    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && session != nil
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
        session = ActiveSession(id: id, label: (label?.isEmpty ?? true) ? nil : label,
                                startedAt: startedAt, url: url)
        sightingsSeen = SessionStore.countSightings(in: url)
        sightingCount = sightingsSeen
        startTicker()
        applyIdleTimer()
        scan()
    }
}

// MARK: - CBCentralManagerDelegate

extension ListeningPost: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn {
            resumeInterruptedSessionIfAny()
            scan()
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // iOS relaunched the app because a scan was in progress. The
        // session itself is restored once the radio reports powered on.
        restoring = true
        inBackground = true
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard session != nil else { return }
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
