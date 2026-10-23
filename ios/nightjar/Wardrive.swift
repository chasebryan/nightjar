import Combine
import CoreLocation
import Foundation
#if os(iOS)
import NetworkExtension
#endif

// MARK: - Wardrive
//
// War driving: the listening post taken for a
// drive. While a drive rolls, a sampler wakes
// every five seconds and writes ONE line to
// the drive's log: the time, where the phone
// is when it holds a fix, the Wi-Fi network
// it is joined to at that moment, and every
// Bluetooth device the post heard for the
// first time since the line before — each
// with the classification the post read off
// the air and the strength it was heard at.
//
// The honest boundary, stated wherever the
// drive is named: iOS shows an app only the
// Wi-Fi network the phone is CONNECTED to.
// A drive logs each network as the phone
// joins it, and the full Bluetooth field the
// post hears. It never claims a scan of
// nearby Wi-Fi networks — the platform gives
// no such thing, and this file does not
// pretend otherwise.
//
// The drive transmits nothing. It is ears
// only, riding the listening post's scan;
// EMCON BRAVO (receive-only) permits it by
// doctrine, and only ALPHA — total silence —
// refuses it.

// MARK: - The record

/// One sampler tick of a drive, as it lands
/// in the log: a JSONL line, codable both
/// ways so the Gauntlet can prove the line
/// round-trips and the room can read a log
/// back without a second format.
struct WardriveRecord: Codable, Equatable {

    /// A device heard for the first time
    /// since the previous tick.
    struct Heard: Codable, Equatable {
        var id: String
        var name: String?
        var kind: String
        var rssi: Int
    }

    var ts: Double
    var lat: Double?
    var lon: Double?
    var ssid: String?
    var bssid: String?
    var heard: [Heard]

    /// The record as its one log line.
    static func encode(_ record: WardriveRecord)
        -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              let line = String(data: data,
                                encoding: .utf8)
        else { return "" }
        return line
    }

    /// A log line back into a record; nil when
    /// the line is not one of ours.
    static func decode(_ line: String)
        -> WardriveRecord? {
        guard let data = line.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(
            WardriveRecord.self, from: data)
    }

    /// The great-circle distance between two
    /// fixes, in meters — the haversine, the
    /// same arithmetic every survey tool on
    /// Earth answers with.
    static func distanceMeters(lat1: Double,
                               lon1: Double,
                               lat2: Double,
                               lon2: Double)
        -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180) *
            cos(lat2 * .pi / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 *
            atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A finished (or rolling) drive's log, as
/// the room lists it. A struct rather than a
/// tuple so the list can key its rows.
struct WardriveSession: Identifiable, Equatable {
    var name: String
    var count: Int
    var bytes: Int
    var id: String { name }
}

// MARK: - The center

final class WardriveCenter: ObservableObject {
    static let shared = WardriveCenter()

    @Published private(set) var running = false
    @Published private(set) var uniqueDevices = 0
    @Published private(set) var uniqueNetworks = 0
    @Published private(set) var distanceMetersTotal = 0.0
    @Published private(set) var recordCount = 0
    @Published private(set) var currentLogName: String?

    /// The house's one listening post. The
    /// center is a singleton the console and
    /// her hand must reach as readily as the
    /// room, so the app root (and the Listen
    /// room, on appearance) attach the post
    /// here. Weak: the post is owned by the
    /// app, never by the drive.
    weak var post: ListeningPost?

    private var timer: Timer?
    private var writer: JSONLWriter?
    private var startedPost = false
    /// Every device id the post's board has
    /// shown since the drive began, seeded
    /// with the board at the start — the diff
    /// against it is what a tick calls new.
    private var seenDeviceIDs: Set<String> = []
    /// Devices first heard on THIS drive —
    /// the unique count the room reports.
    private var driveDeviceIDs: Set<String> = []
    private var seenBSSIDs: Set<String> = []
    private var lastFix: (lat: Double, lon: Double)?

    private init() {}

    /// Where the drive logs live: the app's
    /// Documents, beside the session logs'
    /// folder — visible in Files, like them.
    static var documentsDirectory: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// A distance the way the room speaks it:
    /// meters whole, kilometers to a tenth.
    static func distanceText(_ meters: Double)
        -> String {
        if meters < 1000 {
            return String(format: L("%lld m"),
                          Int64(meters.rounded()))
        }
        return String(format: L("%.1f km"),
                      meters / 1000)
    }

    // MARK: - Start and stop

    /// Roll the drive. Returns nil when it
    /// started; otherwise the refusal, in
    /// words the caller can speak as they are.
    @discardableResult
    func start() -> String? {
        guard !running else { return nil }
        // The EMCON gate: the drive transmits
        // nothing — it only hears — so BRAVO's
        // receive-only ruling permits it, and
        // CHARLIE and OPEN ask nothing at all.
        // ALPHA is total silence: even the ears
        // close, and the drive stays home.
        guard EmconCondition.current != .alpha
        else {
            Journal.log("wardrive", "refused",
                        "EMCON ALPHA forbids the "
                        + "wardrive — total silence")
            return L("EMCON ALPHA is total "
                + "silence — the wardrive "
                + "stays home.")
        }
        guard let post else {
            return L("The listening post is "
                + "not wired to the wardrive yet.")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "wardrive-" +
            formatter.string(from: Date()) +
            ".jsonl"
        let url = Self.documentsDirectory
            .appendingPathComponent(name)
        let writer = JSONLWriter(url: url)
        do {
            try writer.open()
        } catch {
            return L("The drive's log could "
                + "not be opened.")
        }
        self.writer = writer
        currentLogName = name
        seenDeviceIDs = Set(post.rows.map { $0.id })
        driveDeviceIDs = []
        seenBSSIDs = []
        lastFix = nil
        uniqueDevices = 0
        uniqueNetworks = 0
        distanceMetersTotal = 0
        recordCount = 0
        if post.isListening {
            startedPost = false
        } else {
            post.start(label: "wardrive")
            startedPost = true
        }
        running = true
        Journal.log("wardrive", "session",
                    "wardrive started — " + name)
        tick()
        timer = Timer.scheduledTimer(
            withTimeInterval: 5, repeats: true) {
            [weak self] _ in
            self?.tick()
        }
        return nil
    }

    /// Bring the drive home: the sampler
    /// stops, the log closes, and the post
    /// stops too — but only when the drive
    /// raised it. A post the operator started
    /// is the operator's, and rolls on.
    func stop() {
        guard running else { return }
        timer?.invalidate()
        timer = nil
        running = false
        writer?.close()
        writer = nil
        Journal.log("wardrive", "session",
                    "wardrive stopped — "
                    + "\(recordCount) records, "
                    + "\(uniqueDevices) devices, "
                    + "\(uniqueNetworks) networks in "
                    + (currentLogName ?? "the log"))
        if startedPost {
            startedPost = false
            post?.stop()
        }
        currentLogName = nil
    }

    // MARK: - The sampler

    /// One tick: ask the platform for the
    /// network the phone is joined to (iOS
    /// only — the hotspot helpers live there),
    /// then write the line with whatever came
    /// back.
    private func tick() {
        guard running else { return }
#if os(iOS)
        NEHotspotNetwork.fetchCurrent {
            [weak self] network in
            DispatchQueue.main.async {
                self?.sample(ssid: network?.ssid,
                             bssid: network?.bssid)
            }
        }
#else
        sample(ssid: nil, bssid: nil)
#endif
    }

    private func sample(ssid: String?,
                        bssid: String?) {
        guard running, let post, let writer
        else { return }
        var lat: Double?
        var lon: Double?
        if PlaceCenter.shared.isAuthorized,
           let snap = PlaceCenter.shared.snapshot {
            lat = snap.latitude
            lon = snap.longitude
        }
        // Keep her sense of place warm while
        // the drive rolls: the fix is cached,
        // so asking costs nothing when fresh.
        Task { _ = await PlaceCenter.shared.fix() }
        if let bssid, !seenBSSIDs.contains(bssid) {
            seenBSSIDs.insert(bssid)
            uniqueNetworks = seenBSSIDs.count
        }
        if let lat, let lon {
            if let last = lastFix {
                distanceMetersTotal +=
                    WardriveRecord.distanceMeters(
                        lat1: last.lat, lon1: last.lon,
                        lat2: lat, lon2: lon)
            }
            lastFix = (lat, lon)
        }
        var heard: [WardriveRecord.Heard] = []
        for row in post.rows
            where !seenDeviceIDs.contains(row.id) {
            seenDeviceIDs.insert(row.id)
            driveDeviceIDs.insert(row.id)
            heard.append(WardriveRecord.Heard(
                id: row.id,
                name: row.name ?? row.preferredLabel,
                kind: row.kind,
                rssi: row.rssiLast
                    ?? row.rssiClosest ?? -100))
        }
        uniqueDevices = driveDeviceIDs.count
        let record = WardriveRecord(
            ts: Date().timeIntervalSince1970,
            lat: lat, lon: lon,
            ssid: ssid, bssid: bssid,
            heard: heard)
        writer.append(WardriveRecord.encode(record))
        writer.flush()
        recordCount += 1
    }

    // MARK: - The shelf

    /// Every drive log on file, newest first,
    /// with its record count and its weight.
    static func sessions() -> [WardriveSession] {
        let manager = FileManager.default
        guard let urls = try? manager
            .contentsOfDirectory(
                at: documentsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
        else { return [] }
        var found: [WardriveSession] = []
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("wardrive-"),
                  url.pathExtension == "jsonl"
            else { continue }
            let bytes = (try? manager
                .attributesOfItem(atPath: url.path)[.size]
                as? Int) ?? 0
            found.append(WardriveSession(
                name: name,
                count: countRecords(in: url),
                bytes: bytes))
        }
        return found.sorted { $0.name > $1.name }
    }

    /// Throw one drive's log away.
    static func deleteSession(_ name: String) {
        let url = documentsDirectory
            .appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    /// Count a log's records by its newlines,
    /// streamed — a long drive's file is never
    /// loaded whole to be counted.
    private static func countRecords(in url: URL)
        -> Int {
        guard let handle = try? FileHandle(
            forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }
        var count = 0
        while true {
            let chunk = handle.readData(
                ofLength: 65_536)
            if chunk.isEmpty { break }
            for byte in chunk where byte == 0x0A {
                count += 1
            }
        }
        return count
    }
}
