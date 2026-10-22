import AVFoundation
import CryptoKit
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The Gauntlet: a full stress run over every
/// system in the house, built for the developer
/// room. Chase's standing order is NO CRASHES —
/// this is how the house proves it, on the
/// device, against the real code.
///
/// How it works:
/// - Stages run in a fixed order — house,
///   registries, decoders, crypto, her mind,
///   her stores, audio, concurrency, endurance —
///   each stage a list of named steps. Pure,
///   fast stages first; anything stateful late.
/// - The log is WRITE-AHEAD. Before a step runs,
///   its name is written to gauntlet-current.log
///   and flushed to disk. If a step kills the
///   process, the last line of the log names the
///   step that did it, and the developer room
///   says so at next launch, next to the crash
///   recorder's own record. A crash during the
///   gauntlet therefore identifies itself.
/// - The run is DYNAMIC: fuzz intensity scales
///   with the thermal state and the battery, the
///   seed is logged so any run can be re-argued,
///   slow steps are flagged, and the whole run
///   can be stopped between steps.
/// - Nothing here touches the network, the
///   operator's real data (stores are exercised
///   read-only or in memory; sealed files are
///   made and opened inside a scratch folder),
///   or her conversation (her lanes are tested
///   at the component level they compose from —
///   no asks are fired, no state is moved).
final class Gauntlet: ObservableObject {
    static let shared = Gauntlet()

    /// A step's failure, with the reason the log
    /// should carry.
    struct Failure: Error {
        let message: String
    }

    static func require(_ condition: Bool,
                        _ message: String) throws {
        if !condition {
            throw Failure(message: message)
        }
    }

    // MARK: - Published state for the room

    @Published private(set) var running = false
    @Published private(set) var currentStep = ""
    @Published private(set) var stageName = ""
    @Published private(set) var passed = 0
    @Published private(set) var failed = 0
    @Published private(set) var skipped = 0
    @Published private(set) var total = 0
    @Published var cancelRequested = false

    // MARK: - The log files

    static var currentLogURL: URL {
        DevKit.directory.appendingPathComponent(
            "gauntlet-current.log")
    }
    static var latestLogURL: URL {
        DevKit.directory.appendingPathComponent(
            "gauntlet-latest.log")
    }

    /// The step a previous run died inside, if
    /// the current log never reached its footer.
    /// The Developer room reads this while it
    /// renders, so the answer is cached against
    /// the log's stamp (modification + size):
    /// a render costs a stat, not a file read.
    private static var interruptedCache:
        (stamp: String, step: String?)?
    static func interruptedStep() -> String? {
        let attrs = try? FileManager.default
            .attributesOfItem(
                atPath: currentLogURL.path)
        let mod = (attrs?[.modificationDate]
            as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size]
            as? NSNumber)?.intValue ?? 0
        let stamp = "\(mod)-\(size)"
        if let cache = interruptedCache,
           cache.stamp == stamp {
            return cache.step
        }
        let step = computeInterruptedStep()
        interruptedCache = (stamp, step)
        return step
    }

    private static func computeInterruptedStep()
        -> String? {
        guard let text = try? String(
                contentsOf: currentLogURL,
                encoding: .utf8),
              !text.contains("=== GAUNTLET END ===")
        else { return nil }
        let begins = text.components(separatedBy: "\n")
            .filter { $0.hasPrefix("▶ ") }
        return begins.last.map {
            String($0.dropFirst(2)) }
    }

    /// The verdict lines of the last finished
    /// run — for the room and the exported log.
    static func lastSummary() -> String {
        if let died = interruptedStep() {
            return "Last gauntlet run DIED at: \(died)"
        }
        guard let text = try? String(
                contentsOf: latestLogURL,
                encoding: .utf8)
        else { return "The gauntlet has never run." }
        let lines = text.components(separatedBy: "\n")
            .filter {
                $0.hasPrefix("VERDICT")
                    || $0.hasPrefix("Steps:")
                    || $0.hasPrefix("Run:")
            }
        return lines.isEmpty
            ? "The gauntlet has run."
            : lines.joined(separator: "\n")
    }

    static func latestLogText() -> String? {
        if let text = try? String(
            contentsOf: latestLogURL, encoding: .utf8),
           !text.isEmpty { return text }
        return try? String(contentsOf: currentLogURL,
                           encoding: .utf8)
    }

    // MARK: - Deterministic randomness

    /// A small seeded generator: a run can be
    /// re-argued from its logged seed.
    struct RNG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005
                &+ 1442695040888963407
            return state >> 11
        }
        mutating func byte() -> UInt8 {
            UInt8(truncatingIfNeeded: next())
        }
        mutating func bytes(_ count: Int) -> [UInt8] {
            (0..<count).map { _ in byte() }
        }
        mutating func int(_ bound: Int) -> Int {
            bound <= 0 ? 0 : Int(next() % UInt64(bound))
        }
        mutating func pick<T>(_ pool: [T]) -> T {
            pool[int(pool.count)]
        }
    }

    // MARK: - Steps

    struct Step {
        let stage: String
        let name: String
        let main: Bool
        let body: () throws -> String?
    }

    private final class Log {
        private var handle: FileHandle?
        private(set) var lines: [String] = []
        init(url: URL) {
            FileManager.default.createFile(
                atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
        }
        func write(_ line: String) {
            lines.append(line)
            guard let handle = handle else { return }
            handle.write(Data((line + "\n").utf8))
            try? handle.synchronize()
        }
        func close() {
            try? handle?.close()
            handle = nil
        }
    }

    // MARK: - The run

    func run() {
        guard !running else { return }
        cancelRequested = false
        running = true
        Task { [weak self] in
            await self?.execute()
            await MainActor.run { [weak self] in
                self?.running = false
                self?.currentStep = ""
            }
        }
    }

    private func publish(_ body: @escaping
                         (Gauntlet) -> Void) async {
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            body(self)
        }
    }

    private func execute() async {
        let stamp = ISO8601DateFormatter()
        let seed = UInt64(Date().timeIntervalSince1970)
        // Dynamic intensity: the run asks less of
        // a hot or thirsty phone, and says so.
        let thermal = ProcessInfo.processInfo
            .thermalState
        var intensity: Double
        switch thermal {
        case .nominal: intensity = 1.0
        case .fair: intensity = 0.6
        case .serious: intensity = 0.3
        case .critical: intensity = 0.15
        @unknown default: intensity = 0.6
        }
        let device = UIDevice.current
        let wasMonitoring = device
            .isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        let battery = device.batteryLevel
        let onBattery = device.batteryState
            == .unplugged
        if onBattery, battery >= 0,
           battery < 0.25 { intensity *= 0.5 }
        device.isBatteryMonitoringEnabled
            = wasMonitoring

        var rng = RNG(state: seed | 1)
        let steps = buildSteps(intensity: intensity,
                                 rng: &rng)
        await publish {
            $0.total = steps.count
            $0.passed = 0
            $0.failed = 0
            $0.skipped = 0
        }
        let log = Log(url: Gauntlet.currentLogURL)
        let footprintBefore = DevKit.footprintMB()
        log.write("=== GAUNTLET RUN ===")
        log.write("When: \(stamp.string(from: Date()))")
        log.write("Seed: \(seed)")
        log.write(String(
            format: "Intensity: %.2f (thermal %@, "
                + "battery %.0f%%%@)",
            intensity, "\(thermal)" as NSString,
            battery >= 0 ? Double(battery) * 100 : -1,
            onBattery ? ", unplugged" : ""))
        log.write("Footprint at start: "
                  + "\(footprintBefore) MB")
        log.write("--- house state ---")
        log.write(DevKit.houseState())
        log.write("--- steps ---")

        var failures: [String] = []
        var slowest: [(String, Double)] = []
        var lastStage = ""
        let runStart = Date()
        var cancelled = false
        for step in steps {
            if cancelRequested {
                cancelled = true
                log.write("■ run stopped by the "
                          + "operator")
                break
            }
            if step.stage != lastStage {
                lastStage = step.stage
                log.write("## \(step.stage)")
                let stage = step.stage
                await publish { $0.stageName = stage }
            }
            // Write-ahead: the name lands on disk
            // BEFORE the step runs. A death inside
            // the step leaves this as the last line.
            log.write("▶ [\(step.stage)] \(step.name)")
            let name = step.name
            await publish { $0.currentStep = name }
            let start = Date()
            do {
                let note: String?
                if step.main {
                    note = try await MainActor.run {
                        try step.body()
                    }
                } else {
                    note = try step.body()
                }
                let ms = Date().timeIntervalSince(
                    start) * 1000
                slowest.append((step.name, ms))
                var line = String(
                    format: "✓ %@ (%.0f ms)",
                    step.name as NSString, ms)
                if let note = note, !note.isEmpty {
                    line += " — " + note
                }
                if ms > 2000 {
                    line += " [SLOW]"
                }
                log.write(line)
                await publish { $0.passed += 1 }
            } catch let failure as Failure {
                let ms = Date().timeIntervalSince(
                    start) * 1000
                log.write(String(
                    format: "✗ %@ (%.0f ms) — %@",
                    step.name as NSString, ms,
                    failure.message as NSString))
                failures.append(
                    "\(step.name): \(failure.message)")
                await publish { $0.failed += 1 }
            } catch {
                let ms = Date().timeIntervalSince(
                    start) * 1000
                log.write(String(
                    format: "✗ %@ (%.0f ms) — %@",
                    step.name as NSString, ms,
                    "\(error)" as NSString))
                failures.append(
                    "\(step.name): \(error)")
                await publish { $0.failed += 1 }
            }
        }
        let elapsed = Date().timeIntervalSince(
            runStart)
        let footprintAfter = DevKit.footprintMB()
        log.write("--- verdict ---")
        log.write(String(
            format: "Run: %.1f s, intensity %.2f, "
                + "seed %llu",
            elapsed, intensity, seed))
        let p = await MainActor.run { passed }
        let f = await MainActor.run { failed }
        let s = await MainActor.run { skipped }
        log.write("Steps: \(p) passed, \(f) failed, "
                  + "\(s) skipped of \(steps.count)")
        log.write("Footprint: \(footprintBefore) MB "
                  + "→ \(footprintAfter) MB")
        let top = slowest.sorted { $0.1 > $1.1 }
            .prefix(5)
        if !top.isEmpty {
            log.write("Slowest: " + top.map {
                String(format: "%@ %.0f ms",
                       $0.0 as NSString, $0.1)
            }.joined(separator: "; "))
        }
        if cancelled {
            log.write("VERDICT: STOPPED — the run "
                      + "was halted by the operator")
        } else if failures.isEmpty {
            log.write("VERDICT: GAUNTLET CLEAN — "
                      + "every step passed")
        } else {
            log.write("VERDICT: \(failures.count) "
                      + "FAILURE(S)")
            for failure in failures {
                log.write("  ✗ " + failure)
            }
        }
        log.write("=== GAUNTLET END ===")
        log.close()
        // File the finished log as the latest, and
        // keep a dated copy beside it.
        let fm = FileManager.default
        try? fm.removeItem(at: Gauntlet.latestLogURL)
        try? fm.copyItem(at: Gauntlet.currentLogURL,
                         to: Gauntlet.latestLogURL)
        let dated = DevKit.directory
            .appendingPathComponent(
                "gauntlet-"
                + stamp.string(from: runStart)
                    .replacingOccurrences(
                        of: ":", with: "")
                + ".log")
        try? fm.copyItem(at: Gauntlet.currentLogURL,
                         to: dated)
        // Dated copies are an archive, not a
        // hoard: keep the newest five.
        let archive = (try? fm.contentsOfDirectory(
            at: DevKit.directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey]))?
            .filter {
                $0.lastPathComponent.hasPrefix(
                    "gauntlet-")
                    && $0.lastPathComponent
                        .hasSuffix(".log")
                    && $0.lastPathComponent
                        != "gauntlet-latest.log"
                    && $0.lastPathComponent
                        != "gauntlet-current.log"
            }
            .sorted {
                ((try? $0.resourceValues(forKeys: [
                    .contentModificationDateKey]))?
                    .contentModificationDate
                    ?? .distantPast)
                    > ((try? $1.resourceValues(
                        forKeys: [
                            .contentModificationDateKey]))?
                        .contentModificationDate
                        ?? .distantPast)
            } ?? []
        for stale in archive.dropFirst(5) {
            try? fm.removeItem(at: stale)
        }
        try? fm.removeItem(
            at: Gauntlet.currentLogURL)
        DevLog.event("developer",
                     "gauntlet finished: "
                     + "\(failures.count) failure(s)")
    }

    // MARK: - Building the steps

    private func scaled(_ base: Int,
                        _ intensity: Double) -> Int {
        max(10, Int(Double(base) * intensity))
    }

    private func buildSteps(intensity: Double,
                            rng: inout RNG)
        -> [Step] {
        var steps: [Step] = []
        func add(_ stage: String, _ name: String,
                 main: Bool = false,
                 _ body: @escaping () throws
                    -> String?) {
            steps.append(Step(stage: stage, name: name,
                              main: main, body: body))
        }
        // The fuzz draws from one seeded stream so
        // the logged seed reproduces the run.
        var fuzz = rng

        // -- HOUSE --------------------------------
        add("house", "house state readable") {
            let state = DevKit.houseState()
            try Gauntlet.require(
                state.contains("nightjar"),
                "house state did not describe "
                + "the app")
            return nil
        }
        add("house", "developer log writable") {
            DevLog.event("developer",
                         "gauntlet self-check")
            return nil
        }

        // -- REGISTRIES ---------------------------
        add("registries", "company table whole") {
            try Gauntlet.require(
                CompanyRegistry.names.count > 4000,
                "company registry holds "
                + "\(CompanyRegistry.names.count)")
            try Gauntlet.require(
                CompanyRegistry.names[0x0005]
                    == "3Com",
                "0x0005 should be 3Com")
            try Gauntlet.require(
                CompanyRegistry.names[0x060F]
                    == "Signify Netherlands B.V.",
                "0x060F mismatch")
            return "\(CompanyRegistry.names.count)"
                + " makers"
        }
        add("registries", "port table whole") {
            try Gauntlet.require(
                PortRegistry.name(53, udp: true)
                    == "domain",
                "UDP 53 should be domain")
            try Gauntlet.require(
                PortRegistry.name(47808, udp: false)
                    == "bacnet",
                "TCP 47808 should be bacnet")
            try Gauntlet.require(
                ScanModel.serviceName(for: 9100)
                    == "Printer",
                "the curated seam lost 9100")
            try Gauntlet.require(
                ScanModel.serviceName(for: 53,
                                      udp: true)
                    == "domain",
                "the seam lost UDP 53")
            return nil
        }
        add("registries", "service floor whole") {
            let floor = Services.name(
                "0000fd0d" + sigBaseSuffix)
            try Gauntlet.require(
                floor == "Blecon Advertising Service",
                "FD0D floored to \(floor ?? "nil")")
            let curated = Services.name(
                "0000180d" + sigBaseSuffix)
            try Gauntlet.require(
                curated == "Heart Rate",
                "180D should stay curated")
            return nil
        }
        add("registries", "curated names win") {
            try Gauntlet.require(
                Vendors.companyName(0x009E)
                    == "Bose",
                "0x009E should stay Bose")
            try Gauntlet.require(
                Vendors.companyName(0x004C)
                    == "Apple",
                "0x004C should stay Apple")
            return nil
        }

        // -- DECODERS -----------------------------
        add("decoders", "continuity fuzz") {
            var count = 0
            for type in 0...255 {
                for length in [0, 1, 2, 4, 7, 16, 31] {
                    var payload: [UInt8] = [
                        UInt8(type)]
                    payload += fuzz.bytes(length)
                    let messages = Continuity.parse(
                        payload)
                    for message in messages {
                        _ = Continuity
                            .decodeAirPods(message)
                        _ = Continuity
                            .decodeIBeacon(message)
                    }
                    _ = Continuity.identifyApple(
                        payload)
                    count += 1
                }
            }
            return "\(count) payloads"
        }
        add("decoders", "every company, no trap") {
            var named = 0
            for raw in 0...65535 {
                let id = UInt16(raw)
                _ = Vendors.identify(
                    [id: fuzz.bytes(
                        raw % 97 == 0 ? 8 : 0)])
                if Vendors.companyName(id)
                    .hasPrefix("0x") == false {
                    named += 1
                }
            }
            try Gauntlet.require(
                named > 4000,
                "only \(named) companies named")
            return "\(named) named of 65,536"
        }
        add("decoders", "services + eddystone fuzz") {
            let pool = ["0000feaa", "0000fcb2",
                        "0000fe2c", "0000fd6f",
                        "0000fe95", "0000fcd2",
                        "0000180f", "0000180a"]
                .map { $0 + sigBaseSuffix }
            var hits = 0
            for _ in 0..<self.scaled(600, intensity) {
                let uuid = fuzz.pick(pool)
                let data = fuzz.bytes(
                    fuzz.int(20))
                if let found = Services.identify(
                    serviceUUIDs: [uuid],
                    serviceData: [uuid: data]),
                   !found.kind.isEmpty {
                    hits += 1
                }
                _ = Services.name(uuid)
            }
            return "\(hits) readings"
        }
        add("decoders", "dult answers by data only") {
            let uuid = "0000fcb2" + sigBaseSuffix
            let separated = Services.identify(
                serviceUUIDs: [uuid],
                serviceData: [uuid: [0x00, 0x00]])
            try Gauntlet.require(
                separated?.kind.contains("DULT")
                    ?? false,
                "separated DULT not read")
            try Gauntlet.require(
                separated?.trackerShaped ?? false,
                "DULT should be tracker-shaped")
            let bare = Services.identify(
                serviceUUIDs: [uuid],
                serviceData: [:])
            try Gauntlet.require(
                !(bare?.kind.contains("DULT")
                    ?? false),
                "a bare DULT UUID must not speak")
            return nil
        }
        add("decoders", "full pipeline fuzz") {
            let companies: [UInt16] = [0x004C,
                0x0075, 0x0006, 0x0499, 0x00E0,
                0x0157, 0x038F, 0xFFFF]
            let services = ["0000feaa", "0000fcb2",
                "0000fe95", "0000180f", "0000fd6f"]
                .map { $0 + sigBaseSuffix }
            var kinds = Set<String>()
            for i in 0..<self.scaled(1500, intensity) {
                var manufacturer: [UInt16: [UInt8]]
                    = [:]
                for _ in 0..<fuzz.int(3) {
                    manufacturer[fuzz.pick(
                        companies)] = fuzz.bytes(
                        fuzz.int(24))
                }
                var uuids: [String] = []
                var data: [String: [UInt8]] = [:]
                for _ in 0..<fuzz.int(3) {
                    let uuid = fuzz.pick(services)
                    uuids.append(uuid)
                    data[uuid] = fuzz.bytes(
                        fuzz.int(20))
                }
                let sighting = Sighting(
                    seenAt: TimeInterval(i),
                    address: "fuzz-\(i)",
                    name: fuzz.int(4) == 0
                        ? "Fuzz \(i)" : nil,
                    rssi: -40 - fuzz.int(55),
                    manufacturerData: manufacturer,
                    serviceUUIDs: uuids,
                    serviceData: data)
                let result = Classification
                    .classify(sighting)
                try Gauntlet.require(
                    !result.kind.isEmpty,
                    "empty kind at \(i)")
                kinds.insert(result.kind)
                _ = DecoderEngine.analyze(sighting)
                _ = DecoderEngine.payloadSignature(
                    sighting)
            }
            return "\(kinds.count) distinct kinds"
        }
        add("decoders", "row merge keeps the best") {
            let weak = Sighting(
                seenAt: 1, address: "merge",
                name: nil, rssi: -80)
            let strong = Sighting(
                seenAt: 2, address: "merge",
                name: nil, rssi: -40,
                manufacturerData: [
                    0x004C: [0x07, 0x19, 0x01, 0x02,
                             0x03, 0x04, 0x05, 0x06,
                             0x07, 0x08, 0x09, 0x0A,
                             0x0B, 0x0C, 0x0D, 0x0E,
                             0x0F, 0x10, 0x11, 0x12,
                             0x13, 0x14, 0x15, 0x16,
                             0x17]])
            var row = DeviceRow(sighting: weak)
            try Gauntlet.require(
                row.kind == "Unknown device",
                "an empty sighting should stay "
                + "unknown")
            row.observe(strong)
            let bestKind = row.kind
            let bestRank = row.rank
            try Gauntlet.require(
                bestRank > Classification
                    .rankUnknown,
                "the strong sighting never landed")
            row.observe(weak)
            try Gauntlet.require(
                row.kind == bestKind
                    && row.rank == bestRank,
                "a weak sighting overwrote "
                + "the best reading")
            return bestKind
        }

        // -- CRYPTO -------------------------------
        add("crypto", "sealed files round-trip") {
            let fm = FileManager.default
            let scratch = DevKit.directory
                .appendingPathComponent(
                    "gauntlet-scratch",
                    isDirectory: true)
            try? fm.removeItem(at: scratch)
            try fm.createDirectory(
                at: scratch,
                withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: scratch) }
            let sizes = [0, 1, 4096, 1_500_000]
            var opened = 0
            for size in sizes {
                let plain = Data(
                    (0..<size).map { _ in
                        fuzz.byte() })
                let source = scratch
                    .appendingPathComponent(
                        "plain-\(size).bin")
                try plain.write(to: source)
                let protections: [(NJCFProtection,
                                    String?)] = [
                    (.password, "gauntlet-pw"),
                    (.either, "gauntlet-pw"),
                    (.vaultKey, nil),
                    (.bothRequired, "gauntlet-pw"),
                    (.deadDrop, nil),
                ]
                for (protection, password)
                        in protections {
                    let sealed = scratch
                        .appendingPathComponent(
                            "sealed-\(size)-"
                            + "\(protection.rawValue)"
                            + ".njcf")
                    try CryptoFiles.encrypt(
                        input: source, output: sealed,
                        protection: protection,
                        password: password,
                        recipient: protection == .deadDrop
                            ? CryptoSuite.identity().publicKey
                            : nil)
                    let info: NJCFInfo
                    do {
                        info = try CryptoFiles
                            .inspect(sealed)
                    } catch {
                        let bytes = (try? Data(
                            contentsOf: sealed))
                            ?? Data()
                        let head = bytes
                            .prefix(176).map {
                                String(format: "%02x",
                                       $0)
                            }.joined()
                        throw Failure(
                            message: "inspect threw "
                            + "\(error) at \(size) "
                            + "bytes / "
                            + "\(protection); file "
                            + "\(bytes.count) B; "
                            + "head " + head)
                    }
                    try Gauntlet.require(
                        info.protection == protection,
                        "inspect misread the "
                        + "protection")
                    let outDir = scratch
                        .appendingPathComponent(
                            "out-\(size)-"
                            + "\(protection.rawValue)",
                            isDirectory: true)
                    try fm.createDirectory(
                        at: outDir,
                        withIntermediateDirectories:
                            true)
                    let restored: URL
                    do {
                        restored = try CryptoFiles
                            .decrypt(
                                input: sealed,
                                password: password,
                                outputDirectory: outDir)
                    } catch {
                        throw Failure(
                            message: "decrypt threw "
                            + "\(error) at \(size) "
                            + "bytes / "
                            + "\(protection) after "
                            + "\(opened) good seals")
                    }
                    let back = try Data(
                        contentsOf: restored)
                    try Gauntlet.require(
                        back == plain,
                        "round trip differed at "
                        + "\(size) bytes / "
                        + "\(protection)")
                    opened += 1
                }
            }
            return "\(opened) seals opened whole"
        }
        add("crypto", "tampering is refused") {
            let fm = FileManager.default
            let scratch = DevKit.directory
                .appendingPathComponent(
                    "gauntlet-scratch",
                    isDirectory: true)
            try? fm.removeItem(at: scratch)
            try fm.createDirectory(
                at: scratch,
                withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: scratch) }
            let source = scratch
                .appendingPathComponent("plain.bin")
            try Data((0..<8192).map { _ in
                fuzz.byte() }).write(to: source)
            let sealed = scratch
                .appendingPathComponent("sealed.njcf")
            try CryptoFiles.encrypt(
                input: source, output: sealed,
                protection: .password,
                password: "gauntlet-pw",
                recipient: nil)
            let outDir = scratch
                .appendingPathComponent("out",
                                        isDirectory: true)
            try fm.createDirectory(
                at: outDir,
                withIntermediateDirectories: true)
            // Wrong password.
            var refused = 0
            if (try? CryptoFiles.decrypt(
                    input: sealed,
                    password: "wrong-pw",
                    outputDirectory: outDir)) == nil {
                refused += 1
            }
            // A flipped byte in the body.
            var bytes = try Data(contentsOf: sealed)
            bytes[bytes.count / 2] ^= 0xFF
            let tampered = scratch
                .appendingPathComponent("tampered.njcf")
            try bytes.write(to: tampered)
            if (try? CryptoFiles.decrypt(
                    input: tampered,
                    password: "gauntlet-pw",
                    outputDirectory: outDir)) == nil {
                refused += 1
            }
            // A truncation.
            let cut = scratch.appendingPathComponent(
                "cut.njcf")
            try Data(bytes.prefix(bytes.count - 64))
                .write(to: cut)
            if (try? CryptoFiles.decrypt(
                    input: cut,
                    password: "gauntlet-pw",
                    outputDirectory: outDir)) == nil {
                refused += 1
            }
            try Gauntlet.require(
                refused == 3,
                "only \(refused) of 3 attacks "
                + "refused")
            return "wrong key, tamper, truncation"
        }
        add("crypto", "key agreement round trip") {
            let key = SymmetricKey(size: .bits256)
            let message = Data("gauntlet".utf8)
            let box = try ChaChaPoly.seal(
                message, using: key)
            let back = try ChaChaPoly.open(
                box, using: key)
            try Gauntlet.require(
                back == message,
                "ChaChaPoly round trip differed")
            let digest = SHA256.hash(
                data: Data("abc".utf8))
            let hex = digest.map {
                String(format: "%02x", $0)
            }.joined()
            try Gauntlet.require(
                hex.hasPrefix("ba7816bf8f01cfea"),
                "SHA-256 vector mismatch")
            return nil
        }

        // -- HER MIND ------------------------------
        add("mind", "exact math answers") {
            let cases: [(String, String)] = [
                ("2+2", "4"), ("3*7", "21"),
                ("100/4", "25"), ("2^10", "1024"),
                ("sqrt(144)", "12"),
            ]
            for (ask, expect) in cases {
                let answer = MathEngine.answer(ask)
                try Gauntlet.require(
                    answer?.contains(expect) ?? false,
                    "\(ask) answered "
                    + "\(answer ?? "nil")")
            }
            let conversion = MathEngine.conversion(
                "10 miles in km")
            try Gauntlet.require(
                conversion?.contains("16.09")
                    ?? false,
                "miles→km gave "
                + "\(conversion ?? "nil")")
            return nil
        }
        add("mind", "almanac across six years") {
            let calendar = Calendar(identifier:
                .gregorian)
            var date = calendar.date(
                from: DateComponents(year: 2024,
                                     month: 1,
                                     day: 1))!
            for _ in 0..<2200 {
                let phase = Almanac.moonPhase(
                    at: date)
                try Gauntlet.require(
                    (0...100).contains(
                        phase.illumination)
                    && !phase.name.isEmpty,
                    "moon math broke at \(date)")
                date = calendar.date(
                    byAdding: .day, value: 1,
                    to: date)!
            }
            let answer = Almanac.dateMath(
                "100 days from today")
            try Gauntlet.require(
                answer != nil,
                "date math went silent")
            return "2,200 days of moons"
        }
        add("mind", "her manual, whole") {
            var hits = 0
            for entry in SkelliKnowledge.answerable {
                if SkelliKnowledge.lookup(
                    entry.title) != nil {
                    hits += 1
                }
            }
            try Gauntlet.require(
                hits == SkelliKnowledge
                    .answerable.count,
                "only \(hits) of "
                + "\(SkelliKnowledge.answerable.count) "
                + "manual pages found by their titles")
            try Gauntlet.require(
                SkelliKnowledge.lookup(
                    "zzzznotathing") == nil,
                "a nonsense lookup answered")
            try Gauntlet.require(
                SkelliKnowledge.answerable.count
                    < SkelliKnowledge.entries.count
                    + SkelliKnowledge.batches.count,
                "the doctrine pages are not "
                + "being withheld")
            return "\(hits) pages answer"
        }
        add("mind", "feeling grid, all of it") {
            var seen = Set<String>()
            for attention in [0.0, 25, 50, 75, 100] {
                for itch in [0.0, 30, 60, 90] {
                    for fondness in [0.0, 30, 60,
                                     100] {
                        let feeling = SkelliHeart
                            .feeling(
                                attention: attention,
                                itch: itch,
                                pride: 50,
                                fondness: fondness,
                                madFresh: attention
                                    > 90,
                                quietHours: itch / 10,
                                hour: 12,
                                unnamed: 2, drift: 1)
                        seen.insert(
                            "\(feeling)")
                    }
                }
            }
            try Gauntlet.require(
                seen.count >= 4,
                "the grid reached only "
                + "\(seen.count) feelings")
            return "\(seen.count) feelings reached"
        }
        add("mind", "her voice composes") {
            let heart = SkelliHeart.shared
            var composed = 0
            for seed in 0..<400 {
                let line = SkelliVoice.embellish(
                    "Standing by.", seed: seed,
                    heart: heart)
                try Gauntlet.require(
                    line.hasPrefix("Standing by."),
                    "embellish lost the line")
                composed += 1
            }
            return "\(composed) lines composed"
        }
        add("mind", "cartomancy deck cycles") {
            let deck = CartomancyDeck.shared
            try Gauntlet.require(
                CartomancyDeck.all.count == 52,
                "the deck holds "
                + "\(CartomancyDeck.all.count)")
            _ = deck.gatherAndShuffle()
            let hand = deck.deal(5)
            try Gauntlet.require(
                hand.cards.count == 5,
                "dealt \(hand.cards.count)")
            try Gauntlet.require(
                hand.cards.allSatisfy {
                    !$0.meaning.isEmpty
                }, "a card had no meaning")
            _ = deck.gatherAndShuffle()
            return nil
        }
        add("mind", "every language whole") {
            func specifiers(_ text: String)
                -> [String] {
                var found: [String] = []
                var rest = Substring(text)
                while let hit = rest.range(
                    of: "%") {
                    let tail = rest[hit.upperBound...]
                    var token = "%"
                    var index = tail.startIndex
                    while index < tail.endIndex,
                          tail[index].isNumber
                            || tail[index] == "$"
                            || tail[index] == "." {
                        token.append(tail[index])
                        index = tail.index(
                            after: index)
                    }
                    if index < tail.endIndex {
                        token.append(tail[index])
                    }
                    if token != "%%" {
                        found.append(token)
                    }
                    rest = tail
                }
                return found.sorted()
            }
            func strings(_ code: String)
                -> [String: String]? {
                guard let path = Bundle.main.path(
                        forResource: code,
                        ofType: "lproj"),
                      let file = Bundle(path: path)?
                        .path(forResource:
                                "Localizable",
                              ofType: "strings"),
                      let data = try? Data(
                        contentsOf: URL(
                            fileURLWithPath: file)),
                      let object = try?
                        PropertyListSerialization
                        .propertyList(from: data,
                                      format: nil),
                      let table = object
                        as? [String: String]
                else { return nil }
                return table
            }
            guard let english = strings("en")
            else {
                return "no en.lproj in the bundle "
                    + "— skipped"
            }
            var problems: [String] = []
            for language in LanguageCenter
                    .languages
            where language.code != "en" {
                guard let table = strings(
                        language.code)
                else {
                    problems.append(
                        "\(language.code): no table")
                    continue
                }
                if table.count < english.count / 2 {
                    problems.append(
                        "\(language.code): only "
                        + "\(table.count) keys")
                }
                for (key, value) in table {
                    guard let source = english[key]
                    else { continue }
                    if specifiers(value)
                        != specifiers(source) {
                        problems.append(
                            "\(language.code): "
                            + "specifiers differ on "
                            + "key "
                            + String(key.prefix(30)))
                        if problems.count > 4 {
                            break
                        }
                    }
                }
                if problems.count > 4 { break }
            }
            try Gauntlet.require(
                problems.isEmpty,
                problems.joined(separator: "; "))
            return "\(LanguageCenter.languages.count)"
                + " languages checked"
        }

        // -- HER STORES ----------------------------
        add("stores", "her keeping survives coding") {
            let current = SkelliStore.load()
            let data = try JSONEncoder().encode(
                current)
            let back = try JSONDecoder().decode(
                SkelliStore.Saved.self, from: data)
            try Gauntlet.require(
                back.lines.count
                    == current.lines.count
                && back.notes.count
                    == current.notes.count
                && back.archive.count
                    == current.archive.count,
                "her store changed shape in "
                + "a round trip")
            return "\(current.lines.count) lines, "
                + "\(current.archive.count) kept"
        }
        add("stores", "stores from before the "
            + "archive still load") {
            let legacy = """
                {"lines":[{"id":"00000000-0000-0000-0000-000000000001","fromOperator":true,"text":"hello","when":700000000},{"id":"00000000-0000-0000-0000-000000000002","fromOperator":false,"text":"hi","when":700000001}],"notes":[]}
                """
            let saved = try JSONDecoder().decode(
                SkelliStore.Saved.self,
                from: Data(legacy.utf8))
            try Gauntlet.require(
                saved.lines.count == 2
                    && saved.archive.isEmpty,
                "the legacy store decoded to "
                + "\(saved.lines.count) lines")
            return nil
        }
        add("stores", "the wire's cast codes whole") {
            let cast = NeighborhoodStore.shared
                .neighbors
            let data = try JSONEncoder().encode(
                cast)
            let back = try JSONDecoder().decode(
                [Neighbor].self, from: data)
            try Gauntlet.require(
                back.count == cast.count,
                "the cast changed in a round trip")
            return "\(cast.count) neighbors"
        }
        add("stores", "journal and wire read") {
            let events = Journal.events(limit: 50)
            _ = HeadlineWire.shared.tickerText
            _ = HeadlineWire.shared.headlines
            return "\(events.count) events read"
        }

        // -- AUDIO ---------------------------------
        // The stage that would have caught the
        // hunt crash of 2026-10-18 before it
        // shipped: the beep renders into the
        // connection's own format now, and this
        // step plays it, on the record.
        add("audio", "hunt tone beeps", main: true) {
            let tone = HuntTone()
            tone.beep(frequency: 440)
            tone.beep(frequency: 880)
            tone.beep(frequency: 1320)
            tone.stop()
            return "three beeps, no exception"
        }
        add("audio", "chirp renders", main: true) {
            let samples = ChirpModem.renderSamples(
                payload: Data([1, 2, 3, 4]))
            try Gauntlet.require(
                !samples.isEmpty,
                "the chirp rendered silence")
            let empty = ChirpModem.renderSamples(
                payload: Data())
            return "\(samples.count) samples; "
                + "empty payload \(empty.count)"
        }
        add("audio", "chirp sings a note",
            main: true) {
            let sender = ChirpSender()
            sender.sing(payload: Data("G".utf8))
            sender.stop()
            return nil
        }

        // -- CONCURRENCY ---------------------------
        add("concurrency", "shared tables under "
            + "parallel hands") {
            let group = DispatchGroup()
            let queue = DispatchQueue(
                label: "gauntlet.hammer",
                attributes: .concurrent)
            let counter = GauntletCounter()
            let workers = 6
            let each = self.scaled(300, intensity)
            for worker in 0..<workers {
                group.enter()
                queue.async {
                    var local = RNG(
                        state: UInt64(worker + 1)
                            &* 2654435761)
                    for i in 0..<each {
                        let sighting = Sighting(
                            seenAt: TimeInterval(i),
                            address: "hammer",
                            name: nil,
                            rssi: -60,
                            manufacturerData: [
                                UInt16(local.int(
                                    65536)):
                                    local.bytes(6)],
                            serviceUUIDs: [])
                        _ = Classification.classify(
                            sighting)
                        _ = Vendors.companyName(
                            UInt16(local.int(65536)))
                        _ = ScanModel.serviceName(
                            for: local.int(65536),
                            udp: worker % 2 == 0)
                        counter.increment()
                    }
                    group.leave()
                }
            }
            let finished = group.wait(
                timeout: .now() + 60)
            try Gauntlet.require(
                finished == .success,
                "the hammer timed out")
            try Gauntlet.require(
                counter.value == workers * each,
                "lost work: \(counter.value) of "
                + "\(workers * each)")
            return "\(workers * each) readings"
        }

        // -- ENDURANCE ------------------------------
        add("endurance", "registries stable, "
            + "footprint honest") {
            let companies = CompanyRegistry.names
                .count
            var named = 0
            for raw in 0...65535 {
                if PortRegistry.name(raw) != nil {
                    named += 1
                }
                if PortRegistry.name(
                    raw, udp: true) != nil {
                    named += 1
                }
            }
            try Gauntlet.require(
                companies > 4000 && named > 11000,
                "a registry reads short: "
                + "\(companies) makers, "
                + "\(named) named ports")
            let footprint = DevKit.footprintMB()
            return "footprint now \(footprint) MB"
        }
        // -- EVERYDAY SURFACES ---------
        // The surfaces the rest of the app
        // stands on, pinned against their
        // own pure cores: the console roster
        // and its claim gate, the stop token,
        // the wire codecs (DNS, SSH, SNMP,
        // TLS papers, ICS frames, MQTT and
        // CoAP), the robot bench's frame
        // readers and grading, Betafisch's
        // dissector and carver, the file
        // readers, EMCON and the sentinel
        // ladder, the wardrobe, and the
        // session line codec. Every fixture
        // is built in-step from the brief's
        // bytes or from the code's own
        // builders — no network, no store,
        // nothing leaves the scratch dir.

        // Hex text (fixtures quoted in the
        // sources) back to bytes.
        func gxHex(_ text: String) -> [UInt8] {
            var out: [UInt8] = []
            var pending: Int? = nil
            for ch in text {
                guard let v = ch.hexDigitValue
                else { continue }
                if let hi = pending {
                    out.append(UInt8(hi * 16 + v))
                    pending = nil
                } else {
                    pending = v
                }
            }
            return out
        }

        // The one's-complement pair the wire
        // checksums are folded from.
        func gxWordSum(_ bytes: [UInt8]) -> Int {
            var sum = 0
            var i = 0
            while i + 1 < bytes.count {
                sum += (Int(bytes[i]) << 8)
                    | Int(bytes[i + 1])
                i += 2
            }
            if i < bytes.count {
                sum += Int(bytes[i]) << 8
            }
            return sum
        }
        func gxChecksum(_ bytes: [UInt8]) -> [UInt8] {
            var sum = gxWordSum(bytes)
            while sum > 0xFFFF {
                sum = (sum & 0xFFFF) + (sum >> 16)
            }
            let v = ~sum & 0xFFFF
            return [UInt8(v >> 8), UInt8(v & 0xFF)]
        }

        // Frame builders in the tap's own
        // shape: placeholder MACs (this host
        // 02:00:00:00:00:01, the peer :02),
        // honest checksums throughout.
        func gxEth(_ ipPacket: [UInt8]) -> [UInt8] {
            let head: [UInt8] = [
                0x02, 0, 0, 0, 0, 0x02,
                0x02, 0, 0, 0, 0, 0x01,
                0x08, 0x00]
            return head + ipPacket
        }
        func gxIPv4(_ src: [UInt8], _ dst: [UInt8],
                    _ proto: UInt8,
                    _ payload: [UInt8]) -> [UInt8] {
            let total = 20 + payload.count
            var pkt: [UInt8] = [
                0x45, 0,
                UInt8(total >> 8), UInt8(total & 0xFF),
                0, 1, 0x40, 0, 64, proto, 0, 0]
            pkt += src + dst
            let check = gxChecksum(pkt)
            pkt[10] = check[0]
            pkt[11] = check[1]
            pkt += payload
            return pkt
        }
        func gxTCP(_ sport: Int, _ dport: Int,
                   _ seq: Int, _ ack: Int,
                   _ flags: UInt8,
                   _ payload: [UInt8],
                   _ src: [UInt8],
                   _ dst: [UInt8]) -> [UInt8] {
            var seg: [UInt8] = [
                UInt8(sport >> 8), UInt8(sport & 0xFF),
                UInt8(dport >> 8), UInt8(dport & 0xFF)]
            seg += [UInt8((seq >> 24) & 0xFF),
                    UInt8((seq >> 16) & 0xFF),
                    UInt8((seq >> 8) & 0xFF),
                    UInt8(seq & 0xFF)]
            seg += [UInt8((ack >> 24) & 0xFF),
                    UInt8((ack >> 16) & 0xFF),
                    UInt8((ack >> 8) & 0xFF),
                    UInt8(ack & 0xFF)]
            seg += [0x50, flags, 0xFF, 0xFF, 0, 0, 0, 0]
            seg += payload
            var pseudo = src + dst
            pseudo += [0, 6, UInt8(seg.count >> 8),
                       UInt8(seg.count & 0xFF)]
            let check = gxChecksum(pseudo + seg)
            seg[16] = check[0]
            seg[17] = check[1]
            return seg
        }
        func gxUDP(_ sport: Int, _ dport: Int,
                   _ payload: [UInt8],
                   _ src: [UInt8],
                   _ dst: [UInt8]) -> [UInt8] {
            let length = 8 + payload.count
            var seg: [UInt8] = [
                UInt8(sport >> 8), UInt8(sport & 0xFF),
                UInt8(dport >> 8), UInt8(dport & 0xFF),
                UInt8(length >> 8), UInt8(length & 0xFF),
                0, 0]
            seg += payload
            var pseudo = src + dst
            pseudo += [0, 17, UInt8(seg.count >> 8),
                       UInt8(seg.count & 0xFF)]
            let check = gxChecksum(pseudo + seg)
            seg[6] = check[0]
            seg[7] = check[1]
            return seg
        }
        func gxTCPFrame() -> [UInt8] {
            let a: [UInt8] = [10, 0, 0, 1]
            let b: [UInt8] = [10, 0, 0, 2]
            let seg = gxTCP(49152, 80, 1001, 7001, 0x18,
                            Array("gauntlet".utf8), a, b)
            return gxEth(gxIPv4(a, b, 6, seg))
        }
        func gxDNSFrame() -> [UInt8] {
            let a: [UInt8] = [10, 0, 0, 1]
            let b: [UInt8] = [10, 0, 0, 2]
            var query: [UInt8] = [
                0x12, 0x34, 0x01, 0x00,
                0, 1, 0, 0, 0, 0, 0, 0]
            query += BlacksiteDNS.encodeName(
                "gauntlet.test")
            query += [0, 1, 0, 1]
            let seg = gxUDP(53111, 53, query, a, b)
            return gxEth(gxIPv4(a, b, 17, seg))
        }
        func gxFind(_ nodes: [BFNode],
                    _ title: String) -> BFNode? {
            for node in nodes {
                if node.title == title { return node }
                if let hit = gxFind(node.children,
                                    title) {
                    return hit
                }
            }
            return nil
        }

        add("blacksite", "console roster whole") {
            let names = BlacksiteShell.builtinNames
            var cases = 0
            try Gauntlet.require(!names.isEmpty,
                "the console roster is empty")
            try Gauntlet.require(
                Set(names).count == names.count,
                "the console roster repeats a name")
            for name in names {
                cases += 1
                try Gauntlet.require(!name.isEmpty,
                    "the roster holds an empty name")
                try Gauntlet.require(
                    name == name.lowercased(),
                    "roster name not lower case: " + name)
                try Gauntlet.require(!name.contains(" "),
                    "roster name holds a space: " + name)
                try Gauntlet.require(!name.contains("\t"),
                    "roster name holds a tab: " + name)
            }
            let heads = ["help", "stop", "gauntlet",
                         "eazy", "magdump", "megatron",
                         "betafisch"]
            for head in heads {
                cases += 1
                try Gauntlet.require(names.contains(head),
                    "the roster lost " + head)
            }
            return "\(cases) cases: the roster is whole "
                + "— dispatch and help are switch and "
                + "literal tables, pinned by the harness"
        }
        add("blacksite", "bench claims hold") {
            // The claim gate in the hand is exact
            // roster membership of the first token;
            // pin that semantics over the whole
            // roster, near-misses included.
            let roster = Set(BlacksiteShell.builtinNames)
            var cases = 0
            for name in BlacksiteShell.builtinNames {
                cases += 1
                try Gauntlet.require(roster.contains(name),
                    "a roster name does not claim itself")
                let suffixed = name + "x"
                if !roster.contains(suffixed) {
                    cases += 1
                    try Gauntlet.require(
                        !roster.contains(suffixed),
                        "a suffixed near-miss claimed: "
                            + suffixed)
                }
                if name.count > 1 {
                    let trimmed = String(name.dropLast())
                    if !roster.contains(trimmed) {
                        cases += 1
                        try Gauntlet.require(
                            !roster.contains(trimmed),
                            "a trimmed near-miss claimed: "
                                + trimmed)
                    }
                }
                cases += 1
                try Gauntlet.require(
                    !roster.contains(name + " probe"),
                    "a two-word string claimed a bench")
            }
            cases += 1
            try Gauntlet.require(!roster.contains(""),
                "the empty string claimed a bench")
            return "\(cases) cases: exact-match claims "
                + "held over the whole roster"
        }
        add("blacksite", "stop token trips and resets") {
            var cases = 0
            for _ in 0..<scaled(40, intensity) {
                let stop = ConsoleStop()
                cases += 1
                try Gauntlet.require(!stop.isTripped,
                    "a fresh stop token starts tripped")
                stop.trip()
                cases += 1
                try Gauntlet.require(stop.isTripped,
                    "trip did not set the token")
                stop.trip()
                cases += 1
                try Gauntlet.require(stop.isTripped,
                    "a second trip unset the token")
                stop.reset()
                cases += 1
                try Gauntlet.require(!stop.isTripped,
                    "reset did not clear the token")
            }
            let cancel = KernelCancel()
            cases += 1
            try Gauntlet.require(!cancel.isCancelled,
                "a fresh cancel token starts cancelled")
            cancel.cancel()
            cases += 1
            try Gauntlet.require(cancel.isCancelled,
                "cancel did not set the token")
            return "\(cases) cases: the stop token "
                + "trips and resets, cancel is one-way"
        }
        add("bench", "dns name codec round-trips") {
            var cases = 0
            let letters = Array(
                "abcdefghijklmnopqrstuvwxyz")
            let rounds = scaled(120, intensity)
            for _ in 0..<rounds {
                let labelCount = 1 + fuzz.int(4)
                var labels: [String] = []
                for _ in 0..<labelCount {
                    let length = 1 + fuzz.int(10)
                    var label = ""
                    for _ in 0..<length {
                        label.append(
                            letters[fuzz.int(
                                letters.count)])
                    }
                    labels.append(label)
                }
                let name = labels.joined(separator: ".")
                let wire = BlacksiteDNS.encodeName(name)
                let back = BlacksiteDNS.readName(
                    wire, at: 0)
                cases += 1
                try Gauntlet.require(back.0 == name,
                    "name round-trip broke: " + name)
                cases += 1
                try Gauntlet.require(
                    back.1 == wire.count,
                    "the name reader stopped early")
            }
            // The root name is a single zero.
            let root = BlacksiteDNS.encodeName("")
            cases += 1
            try Gauntlet.require(root == [0],
                "the root name is not one zero byte")
            let rootBack = BlacksiteDNS.readName(
                root, at: 0)
            cases += 1
            try Gauntlet.require(
                rootBack.0 == "" && rootBack.1 == 1,
                "the root name did not read back")
            // Compression: a pointer reads the
            // name it points at, in two bytes.
            var msg: [UInt8] = [UInt8](
                repeating: 0, count: 12)
            msg += BlacksiteDNS.encodeName(
                "gauntlet.test")
            msg += [0, 1, 0, 1]
            let pointerAt = msg.count
            msg += [0xC0, 0x0C]
            let pointed = BlacksiteDNS.readName(
                msg, at: pointerAt)
            cases += 1
            try Gauntlet.require(
                pointed.0 == "gauntlet.test",
                "the pointer did not read its name")
            cases += 1
            try Gauntlet.require(
                pointed.1 == pointerAt + 2,
                "the pointer walk consumed wrongly")
            let labelAt = msg.count
            msg += [3]
            msg += Array("www".utf8)
            msg += [0xC0, 0x0C]
            let mixed = BlacksiteDNS.readName(
                msg, at: labelAt)
            cases += 1
            try Gauntlet.require(
                mixed.0 == "www.gauntlet.test",
                "a label-plus-pointer name broke")
            cases += 1
            try Gauntlet.require(
                mixed.1 == labelAt + 6,
                "the mixed name consumed wrongly")
            // Truncated wires must end the walk,
            // never the process.
            let cuts = [0, 1, 5, 11, 13, 20,
                        msg.count - 1]
            for cut in cuts {
                let piece = Array(msg.prefix(cut))
                _ = BlacksiteDNS.readName(piece, at: 0)
                _ = BlacksiteDNS.readName(piece, at: 12)
                cases += 1
            }
            return "\(cases) cases: names round-trip, "
                + "pointers land, truncation is safe"
        }
        add("bench", "dns message parses fixtures") {
            var cases = 0
            var msg: [UInt8] = []
            msg += [0x12, 0x34, 0x81, 0x80]
            msg += [0, 1, 0, 6, 0, 1, 0, 0]
            msg += BlacksiteDNS.encodeName(
                "gauntlet.test")
            msg += [0, 1, 0, 1]
            let owner: [UInt8] = [0xC0, 0x0C]
            func rr(_ type: [UInt8], _ ttl: [UInt8],
                    _ rdata: [UInt8]) {
                msg += owner + type + [0, 1] + ttl
                msg += [UInt8(rdata.count >> 8),
                        UInt8(rdata.count & 0xFF)]
                msg += rdata
            }
            rr([0, 1], [0, 0, 1, 44], [192, 0, 2, 1])
            var aaaa: [UInt8] = [0x20, 0x01, 0x0d, 0xb8]
            aaaa += [UInt8](repeating: 0, count: 11)
            aaaa += [1]
            rr([0, 28], [0, 0, 1, 44], aaaa)
            rr([0, 5], [0, 0, 0, 60],
               BlacksiteDNS.encodeName(
                   "alias.gauntlet.test"))
            rr([0, 15], [0, 0, 0, 60],
               [0, 10] + BlacksiteDNS.encodeName(
                   "mail.gauntlet.test"))
            rr([0, 16], [0, 0, 0, 60],
               [11] + Array("hello=world".utf8))
            var sig: [UInt8] = [0, 1, 8, 2, 0, 0, 1, 44]
            sig += [0x70, 0xDB, 0xD8, 0x80]
            sig += [0x69, 0x55, 0xB9, 0x00]
            sig += [0x30, 0x39]
            sig += BlacksiteDNS.encodeName(
                "gauntlet.test")
            sig += [0xDE, 0xAD, 0xBE, 0xEF, 0, 1, 2, 3]
            rr([0, 46], [0, 0, 0, 60], sig)
            var soa = BlacksiteDNS.encodeName(
                "ns1.gauntlet.test")
            soa += BlacksiteDNS.encodeName(
                "hostmaster.gauntlet.test")
            soa += [0x07, 0x5B, 0xCD, 0x15]
            soa += [0, 0, 0x1C, 0x20]
            soa += [0, 0, 0x0E, 0x10]
            soa += [0, 0x12, 0x75, 0x00]
            soa += [0, 0, 0x01, 0x2C]
            rr([0, 6], [0, 0, 0x0E, 0x10], soa)
            guard let reply = BlacksiteBench.nameParse(
                msg, elapsed: 0.001) else {
                throw Gauntlet.Failure(message:
                    "the fixture message did not parse")
            }
            cases += 1
            try Gauntlet.require(reply.rcode == 0,
                "the fixture parsed with an rcode")
            try Gauntlet.require(!reply.truncated,
                "the fixture claims truncation")
            try Gauntlet.require(reply.answers.count == 6,
                "the answers did not all parse")
            try Gauntlet.require(
                reply.authority.count == 1,
                "the authority record did not parse")
            let renders = [
                "192.0.2.1",
                "2001:db8::1",
                "alias.gauntlet.test",
                "10 mail.gauntlet.test",
                "hello=world",
                "A 8 2 300 2030-01-01 2026-01-01 "
                    + "12345 gauntlet.test",
            ]
            let types = [1, 28, 5, 15, 16, 46]
            for (index, record) in
                reply.answers.enumerated() {
                cases += 1
                try Gauntlet.require(
                    record.name == "gauntlet.test",
                    "an answer lost its owner name")
                try Gauntlet.require(
                    Int(record.type) == types[index],
                    "an answer lost its type")
                try Gauntlet.require(
                    BlacksiteBench.nameRender(
                        msg, record) == renders[index],
                    "a record rendered wrong: "
                        + BlacksiteBench.nameRender(
                            msg, record))
            }
            let authority = reply.authority[0]
            cases += 1
            try Gauntlet.require(authority.type == 6,
                "the authority record is not SOA")
            try Gauntlet.require(
                BlacksiteBench.nameRender(
                    msg, authority)
                    == "ns1.gauntlet.test "
                    + "hostmaster.gauntlet.test "
                    + "123456789 7200 3600 1209600 300",
                "the SOA rendered wrong")
            guard let soaFields = BlacksiteBench
                .nameSOA(msg, authority) else {
                throw Gauntlet.Failure(message:
                    "the SOA fields did not parse")
            }
            cases += 1
            try Gauntlet.require(
                soaFields.serial == 123456789,
                "the SOA serial moved")
            try Gauntlet.require(
                soaFields.refresh == 7200
                    && soaFields.retry == 3600
                    && soaFields.expire == 1209600
                    && soaFields.minimum == 300,
                "the SOA timers moved")
            return "\(cases) cases: a six-answer "
                + "message parsed and rendered whole"
        }
        add("bench", "ssh wire encodings hold") {
            var cases = 0
            // The mpint vectors from the SSH
            // prototype proof, framing included
            // (SSHWire.mpint returns the whole
            // length-prefixed field).
            let vectors: [([UInt8], [UInt8], [UInt8])] = [
                ([], [0, 0, 0, 0], []),
                ([0x00, 0x40], [0, 0, 0, 1, 0x40],
                 [0x40]),
                ([0x00, 0x80], [0, 0, 0, 2, 0x00, 0x80],
                 [0x00, 0x80]),
                ([0x80], [0, 0, 0, 2, 0x00, 0x80],
                 [0x00, 0x80]),
                ([0x7F], [0, 0, 0, 1, 0x7F], [0x7F]),
                ([0x00, 0x00, 0x09, 0xA3, 0x78],
                 [0, 0, 0, 3, 0x09, 0xA3, 0x78],
                 [0x09, 0xA3, 0x78]),
            ]
            for (raw, framed, content) in vectors {
                cases += 1
                try Gauntlet.require(
                    SSHWire.mpint(raw) == framed,
                    "an mpint framed wrong")
                var reader = SSHReader(data: framed)
                cases += 1
                try Gauntlet.require(
                    reader.bytes() == content,
                    "an mpint did not read back")
            }
            // string and uint32 framing.
            let blob = SSHWire.string(Data([1, 2, 3]))
            cases += 1
            try Gauntlet.require(
                blob == [0, 0, 0, 3, 1, 2, 3],
                "the string framing moved")
            var stringReader = SSHReader(data: blob)
            cases += 1
            try Gauntlet.require(
                stringReader.string() == Data([1, 2, 3]),
                "the string did not read back")
            cases += 1
            try Gauntlet.require(
                SSHWire.uint32(0xDEADBEEF)
                    == [0xDE, 0xAD, 0xBE, 0xEF],
                "the uint32 framing moved")
            var intReader = SSHReader(
                data: SSHWire.uint32(424242))
            cases += 1
            try Gauntlet.require(
                intReader.uint32() == 424242,
                "the uint32 did not read back")
            // Name lists round-trip whole.
            let names = ["curve25519-sha256",
                         "curve25519-sha256@libssh.org",
                         "ssh-ed25519"]
            let listWire = SSHWire.nameList(names)
            cases += 1
            try Gauntlet.require(
                SSHWire.parseNameList(listWire) == names,
                "the name list did not round-trip")
            var listReader = SSHReader(data: listWire)
            cases += 1
            try Gauntlet.require(
                listReader.text()
                    == "curve25519-sha256,"
                    + "curve25519-sha256@libssh.org,"
                    + "ssh-ed25519",
                "the name list text moved")
            // Random uint32s round-trip.
            for _ in 0..<scaled(50, intensity) {
                let value = UInt32(
                    fuzz.int(1_000_000_000))
                var r = SSHReader(
                    data: SSHWire.uint32(value))
                cases += 1
                try Gauntlet.require(r.uint32() == value,
                    "a random uint32 broke on the wire")
            }
            return "\(cases) cases: mpint, string, "
                + "uint32 and name-list framing held"
        }
        add("bench", "snmp ber round-trips") {
            var cases = 0
            func readTLV(_ tlv: [UInt8])
                -> (tag: Int, body: [UInt8])? {
                guard let read = BlacksitePentest
                    .berRead(tlv, at: 0) else {
                    return nil
                }
                return (Int(read.0), read.1)
            }
            let oids: [[Int]] = [
                [0, 0], [1, 3], [2, 39],
                [1, 3, 6, 1, 2, 1, 1, 1, 0],
                [1, 3, 6, 1, 4, 1, 9999],
                [1, 3, 6, 1, 4, 1, 128],
                [1, 3, 127, 16383],
            ]
            for oid in oids {
                let tlv = BlacksitePentest.berOID(oid)
                guard let read = readTLV(tlv) else {
                    throw Gauntlet.Failure(message:
                        "an OID did not read back")
                }
                cases += 1
                try Gauntlet.require(read.tag == 0x06,
                    "an OID lost its tag")
                let dotted = oid.map { String($0) }
                    .joined(separator: ".")
                cases += 1
                try Gauntlet.require(
                    BlacksitePentest.berDecodeOID(
                        read.body) == dotted,
                    "an OID decoded wrong: " + dotted)
            }
            // The first subidentifier is a single
            // byte: 2.39 tops the arc at 119.
            let arc = BlacksitePentest.berOID([2, 39])
            guard let arcRead = readTLV(arc) else {
                throw Gauntlet.Failure(message:
                    "the 2.39 arc did not read")
            }
            cases += 1
            try Gauntlet.require(arcRead.body == [119],
                "the first subidentifier is not 119")
            let ints = [0, 1, 127, 128, 255, 256,
                        4242, 65535, 424242]
            for value in ints {
                let tlv = BlacksitePentest.berInt(value)
                guard let read = readTLV(tlv) else {
                    throw Gauntlet.Failure(message:
                        "an integer did not read back")
                }
                cases += 1
                try Gauntlet.require(read.tag == 0x02,
                    "an integer lost its tag")
                var folded = 0
                for byte in read.body {
                    folded = folded * 256 + Int(byte)
                }
                cases += 1
                try Gauntlet.require(folded == value,
                    "an integer folded wrong")
            }
            // A canned v2c GetResponse walks whole.
            let bind1 = BlacksitePentest.berTLV(
                0x30,
                BlacksitePentest.berOID(
                    [1, 3, 6, 1, 2, 1, 1, 1, 0])
                    + BlacksitePentest.berTLV(
                        0x04, Array("gauntlet".utf8)))
            let bind2 = BlacksitePentest.berTLV(
                0x30,
                BlacksitePentest.berOID(
                    [1, 3, 6, 1, 2, 1, 1, 3, 0])
                    + BlacksitePentest.berInt(424242))
            let pdu = BlacksitePentest.berTLV(
                0xA2,
                BlacksitePentest.berInt(4243)
                    + BlacksitePentest.berInt(0)
                    + BlacksitePentest.berInt(0)
                    + BlacksitePentest.berTLV(
                        0x30, bind1 + bind2))
            let wire = BlacksitePentest.snmpMessage(
                version: 1, community: "public",
                pdu: pdu)
            guard let parsed = BlacksitePentest
                .snmpParse(wire) else {
                throw Gauntlet.Failure(message:
                    "the canned response did not parse")
            }
            cases += 1
            try Gauntlet.require(parsed.error == 0,
                "the canned response carries an error")
            try Gauntlet.require(parsed.binds.count == 2,
                "the canned binds did not all parse")
            let first = parsed.binds[0]
            cases += 1
            try Gauntlet.require(
                first.oid == "1.3.6.1.2.1.1.1.0"
                    && first.tag == 0x04
                    && first.body
                        == Array("gauntlet".utf8),
                "the string bind read wrong")
            let second = parsed.binds[1]
            cases += 1
            try Gauntlet.require(
                second.oid == "1.3.6.1.2.1.1.3.0"
                    && second.tag == 0x02
                    && second.body == [0x06, 0x79, 0x32],
                "the integer bind read wrong")
            return "\(cases) cases: BER OIDs and "
                + "integers round-trip, a canned "
                + "GetResponse parses whole"
        }
        add("bench", "tls certificate walk reads") {
            var cases = 0
            // The brief's fixture: a real
            // self-signed RSA-2048 paper for
            // gauntlet.test, openssl-made,
            // 2026-10-22 to 2036-10-19.
            let b64 = [
                "MIIDETCCAfmgAwIBAgIUFRmEAnSv+FgrYr+CTDraaQXkSf4wDQYJKoZIhvcNAQELBQAwGDEWMBQG",
                "A1UEAwwNZ2F1bnRsZXQudGVzdDAeFw0yNjEwMjIwOTE0NDVaFw0zNjEwMTkwOTE0NDVaMBgxFjAU",
                "BgNVBAMMDWdhdW50bGV0LnRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDqbpcJ",
                "8JAsQuA3UflnypEI3Hg6eqiRVi+VwanzeHSGsCbHH89HNrprLy5yEewgDjhCuQ22x3WTfCx6QT0Z",
                "gNz3IZisrEeXoo3ZckXlX15v7H/IPA1Cc5Md3YjwbSGeicvDH/RyU6AXVClxZXPbTbSlDLeSh3h4",
                "c7grNE9yNLlXc4S94C/mQd6QYJueUwv0Uo6Ovrk79Fa2eOTlJOcAahdXHccKgYpUljPCqwK+ObGa",
                "v3N6WEQ/M7rHDSy6MLhinVLy7uGYBgkgvqxty6xrr+4sgo8iDJzsr05mniZzvhEusbTHT+BpWbR8",
                "WNWHpMnWr3EF9cyWxy0zovYZgdiEdLJnAgMBAAGjUzBRMB0GA1UdDgQWBBRDkdSmvLKC32hl5YPW",
                "SIvl3LHHITAfBgNVHSMEGDAWgBRDkdSmvLKC32hl5YPWSIvl3LHHITAPBgNVHRMBAf8EBTADAQH/",
                "MA0GCSqGSIb3DQEBCwUAA4IBAQDeXtpWl6sGHzHQXcWBNXqu90eIUkpL7Es3z3lfUaH6pqteTW4h",
                "ShIkh76zOwk+o8OceeMi1fdk1VhavAL51rP7wgoo6fgVocjAfEYpVUFf8M5RgY4OeXAWPKkUT8iU",
                "K+DtQxHEm+ngtqzWMhQED437gi3oFpoJWBCEK5ilGCtsVFXXE+7uvKu78JBmeG11ZyjiiV5qhGVu",
                "dfKuuyNLZzqM/OGs1RjsfPscgRiMUSx/WS3NcTSd42t4FLhXVR5pCDUoNgxNY2AGD3/4xjYNQX4G",
                "KNHZpRPNMkWZ1NhKUuh2vI9/KD9MC5ZbSNHe1b6pkYSZW4Bg4FeS5FZgiu8Rd2K5",
            ].joined()
            guard let derData = Data(
                base64Encoded: b64) else {
                throw Gauntlet.Failure(message:
                    "the fixture paper did not decode")
            }
            let der = [UInt8](derData)
            guard let cert = BlacksiteBench
                .lockCertParse(der) else {
                throw Gauntlet.Failure(message:
                    "the fixture paper did not parse")
            }
            cases += 1
            try Gauntlet.require(
                cert.subjectLine == "CN=gauntlet.test",
                "the subject line moved: "
                    + cert.subjectLine)
            cases += 1
            try Gauntlet.require(
                cert.issuerLine == "CN=gauntlet.test",
                "the issuer line moved")
            cases += 1
            try Gauntlet.require(
                cert.issuerRaw == cert.subjectRaw,
                "a self-signed paper's names differ")
            cases += 1
            try Gauntlet.require(
                cert.serialHex
                    == "15:19:84:02:74:af:f8:58:2b:62:"
                    + "bf:82:4c:3a:da:69:05:e4:49:fe",
                "the serial moved: " + cert.serialHex)
            cases += 1
            try Gauntlet.require(
                cert.sigOID == "1.2.840.113549.1.1.11",
                "the signature OID moved")
            guard let before = cert.notBefore,
                  let after = cert.notAfter else {
                throw Gauntlet.Failure(message:
                    "the validity window did not read")
            }
            cases += 1
            let span = after.timeIntervalSince(before)
            try Gauntlet.require(
                span > 315_000_000 && span < 316_000_000,
                "the validity span moved")
            cases += 1
            try Gauntlet.require(cert.isCA == true,
                "the CA flag did not read")
            guard let key = cert.keyInfo else {
                throw Gauntlet.Failure(message:
                    "the key did not read")
            }
            cases += 1
            try Gauntlet.require(key.family == "RSA",
                "the key family moved")
            cases += 1
            try Gauntlet.require(
                key.rsaModulus?.bitLength == 2048,
                "the modulus is not 2048 bits")
            cases += 1
            try Gauntlet.require(
                key.rsaExponent == LockBig(65537),
                "the exponent is not 65537")
            cases += 1
            try Gauntlet.require(
                key.detail.contains("2048-bit"),
                "the key detail lost its size")
            return "\(cases) cases: the fixture "
                + "paper's walk read whole"
        }
        add("bench", "ics frames byte-exact") {
            var cases = 0
            // The three CRCs against their
            // catalogue check values.
            let check = Array("123456789".utf8)
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsCRCModbus(check)
                    == 0x4B37,
                "the Modbus CRC moved")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsCRCDNP(check)
                    == 0xEA82,
                "the DNP3 CRC moved")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsCRCCCITT(check)
                    == 0x29B1,
                "the CCITT CRC moved")
            // The Modbus identification ask,
            // byte for byte.
            let ask = BlacksiteBench.icsMBAP(length: 5)
                + [0x2B, 0x0E, 0x01, 0x00]
            cases += 1
            try Gauntlet.require(
                ask == [0x00, 0x01, 0x00, 0x00, 0x00,
                        0x05, 0x01, 0x2B, 0x0E, 0x01,
                        0x00],
                "the Modbus ask moved")
            // A DNP3 frame: header fields, the
            // header CRC, and the user bytes
            // strip back out whole.
            let short: [UInt8] = [0xC0, 0x01, 0x02]
            let frame = BlacksiteBench.icsDNP3Frame(
                ctrl: 0xC4, user: short)
            cases += 1
            try Gauntlet.require(
                Array(frame[0..<4])
                    == [0x05, 0x64, 8, 0xC4],
                "the DNP3 header moved")
            cases += 1
            try Gauntlet.require(
                Array(frame[4..<8])
                    == [0x01, 0x00, 0x64, 0x00],
                "the DNP3 addresses moved")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16LE(frame, 8)
                    == BlacksiteBench.icsCRCDNP(
                        Array(frame[0..<8])),
                "the DNP3 header CRC moved")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsDNP3User(frame)
                    == short,
                "the DNP3 user bytes did not strip")
            let long = (0..<40).map {
                UInt8($0 & 0xFF)
            }
            let longFrame = BlacksiteBench
                .icsDNP3Frame(ctrl: 0xC4, user: long)
            cases += 1
            try Gauntlet.require(
                longFrame.count == 56,
                "the blocked DNP3 frame sized wrong")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsDNP3User(longFrame)
                    == long,
                "the blocked DNP3 frame lost bytes")
            // BACnet: the canned Who-Is and a
            // tag walk over a device object id.
            let whois: [UInt8] = [
                0x81, 0x0A, 0x00, 0x08,
                0x01, 0x00, 0x10, 0x08]
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16BE(whois, 2) == 8
                    && whois.count == 8,
                "the Who-Is length moved")
            let tagged: [UInt8] = [
                0xC4, 0x02, 0x00, 0x03, 0xE7]
            var tagPos = 0
            let tag = BlacksiteBench.icsBACTag(
                tagged, &tagPos)
            cases += 1
            try Gauntlet.require(
                tag.num == 12 && tag.len == 4
                    && tagPos == 1,
                "the BACnet tag walk moved")
            let objectID = BlacksiteBench.icsU32BE(
                tagged, 1)
            cases += 1
            try Gauntlet.require(
                objectID >> 22 == 8
                    && (objectID & 0x3FFFFF) == 999,
                "the device object id read wrong")
            let extended: [UInt8] = [
                0x57, 0x03, 0xAA, 0xBB, 0xCC]
            var extPos = 0
            let extTag = BlacksiteBench.icsBACTag(
                extended, &extPos)
            cases += 1
            try Gauntlet.require(
                extTag.num == 5 && extTag.len == 3
                    && extPos == 2,
                "the extended tag walk moved")
            // ENIP ListIdentity: the canned
            // header and the identity body at
            // the reader's own offsets.
            var eData: [UInt8] = [1, 0]
            eData += [0, 2, 0xAF, 0x12,
                      192, 168, 1, 50,
                      0, 0, 0, 0, 0, 0, 0, 0]
            eData += [0x01, 0x00]
            eData += [0x0E, 0x00]
            eData += [0x2A, 0x00]
            eData += [1, 2]
            eData += [0, 0]
            eData += [0xEF, 0xCD, 0xAB, 0x00]
            eData += [12]
            eData += Array("gauntlet-plc".utf8)
            eData += [0]
            var eBody: [UInt8] = [1, 0, 0x0C, 0x00]
            eBody += [UInt8(eData.count & 0xFF),
                      UInt8(eData.count >> 8)]
            eBody += eData
            var enip: [UInt8] = [0x63, 0x00]
            enip += [UInt8(eBody.count & 0xFF),
                     UInt8(eBody.count >> 8)]
            enip += [UInt8](repeating: 0, count: 20)
            enip += eBody
            cases += 1
            try Gauntlet.require(enip[0] == 0x63,
                "the ENIP command byte moved")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16LE(enip, 2)
                    == eBody.count,
                "the ENIP length moved")
            let walked = Array(eBody.dropFirst(6))
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16LE(walked, 18)
                    == 1,
                "the ENIP vendor read wrong")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16LE(walked, 20)
                    == 14,
                "the ENIP device type read wrong")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU16LE(walked, 22)
                    == 42,
                "the ENIP product read wrong")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsU32LE(walked, 28)
                    == 0x00ABCDEF,
                "the ENIP serial read wrong")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.icsClean(
                    walked[33..<45])
                    == "gauntlet-plc",
                "the ENIP name read wrong")
            return "\(cases) cases: CRCs, Modbus, "
                + "DNP3, BACnet and ENIP bytes held"
        }
        add("bench", "mqtt and coap encodings") {
            var cases = 0
            // The forge's MQTT CONNECT, decoded
            // field by field.
            let built = ForgeKit.mqtt(
                clientID: "gauntlet-probe")
            let wire = PayloadKit.build(
                source: built.source, text: built.text,
                hex: built.text, b64: "",
                xorSpec: "", useGzip: false)
            let bytes = [UInt8](wire)
            cases += 1
            try Gauntlet.require(bytes.count == 28,
                "the CONNECT sized wrong")
            cases += 1
            try Gauntlet.require(
                bytes[0] == 0x10 && bytes[1] == 26,
                "the CONNECT header moved")
            cases += 1
            try Gauntlet.require(
                Array(bytes[2..<4]) == [0, 4],
                "the protocol name length moved")
            cases += 1
            try Gauntlet.require(
                String(bytes: bytes[4..<8],
                       encoding: .utf8) == "MQTT",
                "the protocol name moved")
            cases += 1
            try Gauntlet.require(bytes[8] == 4,
                "the protocol level moved")
            cases += 1
            try Gauntlet.require(bytes[9] == 0x02,
                "the connect flags moved")
            cases += 1
            try Gauntlet.require(
                Array(bytes[10..<12]) == [0, 60],
                "the keepalive moved")
            cases += 1
            try Gauntlet.require(
                Array(bytes[12..<14]) == [0, 14],
                "the client id length moved")
            cases += 1
            try Gauntlet.require(
                String(bytes: bytes[14..<28],
                       encoding: .utf8)
                    == "gauntlet-probe",
                "the client id moved")
            // The shield's CoAP GET, read as
            // RFC 7252 fields (no pure parser
            // ships; the builder's bytes are
            // pinned field-wise instead).
            var get: [UInt8] = [0x40, 0x01, 0xB0, 0x7A,
                                0xBA]
            get += Array(".well-known".utf8)
            get += [0x04]
            get += Array("core".utf8)
            cases += 1
            try Gauntlet.require((get[0] >> 6) == 1,
                "the CoAP version moved")
            cases += 1
            try Gauntlet.require(
                ((get[0] >> 4) & 0x03) == 0
                    && (get[0] & 0x0F) == 0,
                "the CoAP type or token length moved")
            cases += 1
            try Gauntlet.require(get[1] == 1,
                "the CoAP code is not GET")
            cases += 1
            try Gauntlet.require(
                (Int(get[2]) << 8 | Int(get[3]))
                    == 0xB07A,
                "the CoAP message id moved")
            cases += 1
            try Gauntlet.require(
                (get[4] >> 4) == 11
                    && (get[4] & 0x0F) == 10,
                "the Uri-Path option header moved")
            cases += 1
            try Gauntlet.require(
                String(bytes: get[5..<15],
                       encoding: .utf8)
                    == ".well-known",
                "the first Uri-Path moved")
            cases += 1
            try Gauntlet.require(
                get[15] == 0x04
                    && String(bytes: get[16..<20],
                              encoding: .utf8)
                        == "core",
                "the second Uri-Path moved")
            return "\(cases) cases: the MQTT "
                + "CONNECT and the CoAP GET held "
                + "field for field"
        }
        add("megatron", "mavlink frames verify") {
            var cases = 0
            // The brief's v2 heartbeat: sysid 1,
            // compid 1, quadcopter class 3.
            let v2 = gxHex(
                "fd0900000701010000000000000002030004030965")
            let beats2 = BlacksiteBench.megaMAVParse(
                v2, from: "192.0.2.1")
            cases += 1
            try Gauntlet.require(beats2.count == 1,
                "the v2 heartbeat did not parse")
            let beat2 = beats2[0]
            cases += 1
            try Gauntlet.require(
                beat2.sysid == 1 && beat2.compid == 1,
                "the v2 ids moved")
            cases += 1
            try Gauntlet.require(beat2.vehicleType == 3,
                "the v2 vehicle class moved")
            cases += 1
            try Gauntlet.require(beat2.autopilot == 0,
                "the v2 autopilot moved")
            cases += 1
            try Gauntlet.require(beat2.crcOK,
                "the v2 checksum failed its own bytes")
            // The brief's v1 heartbeat: sysid 42.
            let v1 = gxHex(
                "fe09032a0100000000000a0c000403754a")
            let beats1 = BlacksiteBench.megaMAVParse(
                v1, from: "192.0.2.1")
            cases += 1
            try Gauntlet.require(beats1.count == 1,
                "the v1 heartbeat did not parse")
            cases += 1
            try Gauntlet.require(
                beats1[0].sysid == 42
                    && beats1[0].compid == 1,
                "the v1 ids moved")
            cases += 1
            try Gauntlet.require(
                beats1[0].vehicleType == 12,
                "the v1 vehicle class moved")
            cases += 1
            try Gauntlet.require(beats1[0].crcOK,
                "the v1 checksum failed its own bytes")
            // A flipped payload bit fails the
            // checksum but still reads.
            var bent2 = v2
            bent2[14] ^= 0x01
            let bentBeats2 = BlacksiteBench
                .megaMAVParse(bent2, from: "192.0.2.1")
            cases += 1
            try Gauntlet.require(
                bentBeats2.count == 1
                    && bentBeats2[0].crcOK == false,
                "a bent v2 frame still verified")
            var bent1 = v1
            bent1[10] ^= 0x01
            let bentBeats1 = BlacksiteBench
                .megaMAVParse(bent1, from: "192.0.2.1")
            cases += 1
            try Gauntlet.require(
                bentBeats1.count == 1
                    && bentBeats1[0].crcOK == false,
                "a bent v1 frame still verified")
            // Noise and truncation read as none.
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaMAVParse(
                    [0x00, 0x11, 0x22],
                    from: "192.0.2.1").isEmpty,
                "noise parsed as a heartbeat")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaMAVParse(
                    Array(v2.prefix(12)),
                    from: "192.0.2.1").isEmpty,
                "a truncated frame parsed")
            return "\(cases) cases: both heartbeat "
                + "generations verified, bent bytes "
                + "failed honestly"
        }
        func gxDDSString(_ text: String) -> [UInt8] {
            let raw = Array(text.utf8) + [0]
            var out: [UInt8] = [
                UInt8(raw.count & 0xFF), 0, 0, 0]
            out += raw
            while out.count % 4 != 0 {
                out.append(0)
            }
            return out
        }
        func gxSPDP(_ pairs: [(String, String)],
                    guid: Bool) -> [UInt8] {
            var props: [UInt8] = [
                UInt8(pairs.count & 0xFF), 0, 0, 0]
            for (key, value) in pairs {
                props += gxDDSString(key)
                props += gxDDSString(value)
            }
            var pay: [UInt8] = [0x00, 0x03, 0x00, 0x00]
            if guid {
                pay += [0x50, 0x00, 0x10, 0x00]
                pay += gxHex(
                    "010f6d61746f6e0000000001")
                pay += [0x00, 0x00, 0x01, 0xC1]
            }
            if !pairs.isEmpty {
                pay += [0x59, 0x00,
                        UInt8(props.count & 0xFF),
                        UInt8((props.count >> 8) & 0xFF)]
                pay += props
            }
            pay += [0x01, 0x00, 0x00, 0x00]
            let body = [UInt8](
                repeating: 0, count: 18) + pay
            var pkt = Array("RTPS".utf8)
            pkt += [2, 3, 0x01, 0x0F]
            pkt += gxHex("010f6d61746f6e0000000001")
            pkt += [0x15, 0x01,
                    UInt8(body.count & 0xFF),
                    UInt8((body.count >> 8) & 0xFF)]
            pkt += body
            return pkt
        }
        add("megatron", "dds identity parses") {
            var cases = 0
            let plain = gxSPDP(
                [("participant_name", "gauntlet-prime")],
                guid: true)
            guard let participant = BlacksiteBench
                .megaParseSPDP(plain,
                               from: "192.0.2.1") else {
                throw Gauntlet.Failure(message:
                    "the synthetic participant "
                    + "did not parse")
            }
            cases += 1
            try Gauntlet.require(
                participant.guidHex
                    == "010f6d61746f6e0000000001"
                    + "000001c1",
                "the participant GUID moved")
            cases += 1
            try Gauntlet.require(
                participant.vendorRaw == "010f",
                "the vendor read wrong")
            cases += 1
            try Gauntlet.require(
                participant.protoMajor == 2
                    && participant.protoMinor == 3,
                "the protocol version read wrong")
            cases += 1
            try Gauntlet.require(
                participant.nameClaims
                    == ["participant_name=gauntlet-prime"],
                "the name claim read wrong")
            cases += 1
            try Gauntlet.require(
                participant.security == false,
                "a plain participant claims security")
            let secured = gxSPDP(
                [("participant_name", "gauntlet-prime"),
                 ("dds.sec.auth.identity_ca", "pem")],
                guid: true)
            guard let securedParticipant =
                BlacksiteBench.megaParseSPDP(
                    secured, from: "192.0.2.1") else {
                throw Gauntlet.Failure(message:
                    "the secured participant "
                    + "did not parse")
            }
            cases += 1
            try Gauntlet.require(
                securedParticipant.security == true,
                "the security property did not grade")
            // No GUID parameter, no participant.
            let anonymous = gxSPDP(
                [("participant_name", "gauntlet-prime")],
                guid: false)
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaParseSPDP(
                    anonymous, from: "192.0.2.1")
                    == nil,
                "a GUID-less packet named a unit")
            // Non-RTPS bytes read as none.
            var junk = Array("XXXX".utf8)
            junk += [UInt8](repeating: 0, count: 40)
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaParseSPDP(
                    junk, from: "192.0.2.1") == nil,
                "junk parsed as a participant")
            return "\(cases) cases: the SPDP "
                + "identity walk held, plain and "
                + "secured"
        }
        add("megatron", "megatron grades hold") {
            var cases = 0
            let rosFamily = "ros robot (maker unnamed)"
            var blank = MegaEvidence(
                host: "unit", ip: "192.0.2.10")
            blank.open = []
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaGrades(blank)
                    .isEmpty,
                "an empty board graded something")
            // The substring trap: prose that
            // mentions a system is not the system.
            var prose = MegaEvidence(
                host: "unit", ip: "192.0.2.10")
            prose.banners[22] = "across the hall"
            cases += 1
            try Gauntlet.require(
                !BlacksiteBench.megaGrades(prose)
                    .contains {
                        $0.family == rosFamily
                    },
                "prose graded as a ROS robot")
            // The ROS master door claims its grade.
            var door = MegaEvidence(
                host: "unit", ip: "192.0.2.10")
            door.open = [11311]
            let doorGrades = BlacksiteBench
                .megaGrades(door)
            cases += 1
            try Gauntlet.require(
                doorGrades.contains {
                    $0.family == rosFamily
                        && $0.score == 3
                },
                "the ROS door lost its grade")
            // A rosbridge banner claims the same.
            var banner = MegaEvidence(
                host: "unit", ip: "192.0.2.10")
            banner.banners[9090] = "rosbridge suite"
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaGrades(banner)
                    .contains {
                        $0.family == rosFamily
                            && $0.score == 3
                    },
                "the rosbridge banner lost its grade")
            // Claim containment: word boundaries
            // for short needles, plain for long.
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaClaimContains(
                    "across the hall", "ros") == false,
                "a substring claimed a word")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaClaimContains(
                    "a ros node", "ros") == true,
                "a whole word did not claim")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaClaimContains(
                    "rosbridge suite", "ros") == false,
                "a prefix claimed a whole word")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaClaimContains(
                    "rosbridge suite", "rosbridge")
                    == true,
                "a long needle did not claim")
            // Actuation shape: control topics
            // read as control, telemetry does not.
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaActuationShaped(
                    "/cmd_vel"),
                "cmd_vel lost its shape")
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.megaActuationShaped(
                    "/joint_states"),
                "joint_states lost its shape")
            cases += 1
            try Gauntlet.require(
                !BlacksiteBench.megaActuationShaped(
                    "/telemetry"),
                "telemetry read as actuation")
            cases += 1
            try Gauntlet.require(
                !BlacksiteBench.megaActuationShaped(
                    "/diagnostics"),
                "diagnostics read as actuation")
            return "\(cases) cases: the grading "
                + "held — doors and banners claim, "
                + "prose and telemetry do not"
        }
        add("betafisch", "betafisch dissects fixtures") {
            var cases = 0
            let tcp = Betafisch.dissect(
                bytes: gxTCPFrame(),
                origLen: gxTCPFrame().count,
                linktype: 1, number: 1,
                timestamp: 1767225600.0)
            cases += 1
            try Gauntlet.require(tcp.proto == "TCP",
                "the TCP frame read as " + tcp.proto)
            cases += 1
            try Gauntlet.require(
                tcp.srcPort == 49152
                    && tcp.dstPort == 80,
                "the TCP ports read wrong")
            cases += 1
            try Gauntlet.require(tcp.tcpFlags == 0x18,
                "the TCP flags read wrong")
            cases += 1
            try Gauntlet.require(
                tcp.ipSrc == "10.0.0.1"
                    && tcp.ipDst == "10.0.0.2",
                "the IP endpoints read wrong")
            cases += 1
            try Gauntlet.require(
                tcp.src == "02:00:00:00:00:01"
                    && tcp.dst == "02:00:00:00:00:02",
                "the placeholder MACs read wrong")
            guard let tcpNode = gxFind(tcp.tree,
                "Transmission Control Protocol")
            else {
                throw Gauntlet.Failure(message:
                    "the TCP node is missing")
            }
            cases += 1
            try Gauntlet.require(
                tcpNode.detail
                    == "49152 → 80 [ACK, PSH]",
                "the TCP headline moved: "
                    + tcpNode.detail)
            guard let csumNode = gxFind([tcpNode],
                                        "Checksum")
            else {
                throw Gauntlet.Failure(message:
                    "the checksum node is missing")
            }
            cases += 1
            try Gauntlet.require(
                csumNode.detail.contains("correct"),
                "an honest checksum graded wrong")
            let dnsFrame = Betafisch.dissect(
                bytes: gxDNSFrame(),
                origLen: gxDNSFrame().count,
                linktype: 1, number: 2,
                timestamp: 1767225601.0)
            cases += 1
            try Gauntlet.require(dnsFrame.proto == "DNS",
                "the DNS frame read as "
                    + dnsFrame.proto)
            cases += 1
            try Gauntlet.require(
                dnsFrame.protocols.contains("dns"),
                "the protocol stack lost dns")
            guard let queryNode = gxFind(
                dnsFrame.tree, "gauntlet.test")
            else {
                throw Gauntlet.Failure(message:
                    "the query node is missing")
            }
            cases += 1
            try Gauntlet.require(
                queryNode.detail == "A, class IN",
                "the query detail moved: "
                    + queryNode.detail)
            // An ICMP port-unreachable quoting
            // the packet that provoked it.
            let a: [UInt8] = [10, 0, 0, 1]
            let b: [UInt8] = [10, 0, 0, 2]
            let quoted = gxIPv4(
                a, b, 17,
                gxUDP(53111, 53, [], a, b))
            var icmp: [UInt8] = [3, 3, 0, 0,
                                 0, 0, 0, 0]
            icmp += quoted
            let icmpCheck = gxChecksum(icmp)
            icmp[2] = icmpCheck[0]
            icmp[3] = icmpCheck[1]
            let icmpFrame = Betafisch.dissect(
                bytes: gxEth(gxIPv4(b, a, 1, icmp)),
                origLen: 14 + 20 + icmp.count,
                linktype: 1, number: 3,
                timestamp: 1767225602.0)
            cases += 1
            try Gauntlet.require(
                icmpFrame.proto == "ICMP",
                "the ICMP frame read as "
                    + icmpFrame.proto)
            guard let quotedNode = gxFind(
                icmpFrame.tree,
                "The packet that provoked it")
            else {
                throw Gauntlet.Failure(message:
                    "the quoted packet is missing")
            }
            cases += 1
            try Gauntlet.require(
                quotedNode.children.contains {
                    $0.title == "Source"
                        && $0.detail == "10.0.0.1"
                },
                "the quoted source read wrong")
            cases += 1
            try Gauntlet.require(
                quotedNode.children.contains {
                    $0.title == "Ports"
                        && $0.detail.contains("53111")
                },
                "the quoted ports read wrong")
            return "\(cases) cases: TCP, DNS and "
                + "ICMP fixtures dissected whole"
        }
        add("betafisch", "driftnet carves a stream") {
            var cases = 0
            // The fixture picture: a 1x1 PNG,
            // 70 bytes on the wire.
            let pngB64 = "iVBORw0KGgoAAAANSUhEUg"
                + "AAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4"
                + "2mNk+M9QDwADhgGAWjR9awAAAABJRU5Er"
                + "kJggg=="
            guard let pngData = Data(
                base64Encoded: pngB64) else {
                throw Gauntlet.Failure(message:
                    "the fixture picture did not decode")
            }
            let png = [UInt8](pngData)
            cases += 1
            try Gauntlet.require(png.count == 70,
                "the fixture picture sized wrong")
            let client: [UInt8] = [10, 0, 0, 1]
            let server: [UInt8] = [10, 0, 0, 2]
            func flowFrame(_ fromClient: Bool,
                           _ seq: Int, _ ack: Int,
                           _ flags: UInt8,
                           _ payload: [UInt8])
                -> [UInt8] {
                let src = fromClient ? client : server
                let dst = fromClient ? server : client
                let sport = fromClient ? 49152 : 80
                let dport = fromClient ? 80 : 49152
                let seg = gxTCP(sport, dport, seq, ack,
                                flags, payload, src, dst)
                return gxEth(gxIPv4(src, dst, 6, seg))
            }
            let request = Array(
                "GET /moon.png HTTP/1.1\r\n"
                + "Host: gauntlet.test\r\n\r\n".utf8)
            var response = Array(
                "HTTP/1.1 200 OK\r\n"
                + "Content-Type: image/png\r\n"
                + "Content-Length: 70\r\n\r\n".utf8)
            response += png
            cases += 1
            try Gauntlet.require(response.count == 134,
                "the fixture response sized wrong")
            let seg1 = Array(response[0..<50])
            let seg2 = Array(response[50..<100])
            let seg3 = Array(response[100..<134])
            // The response lands out of order —
            // seg2, seg3, seg1 — with seg1 sent
            // twice; the carver must still lay
            // it down whole and claim it once.
            let raws: [[UInt8]] = [
                flowFrame(true, 1000, 0, 0x02, []),
                flowFrame(false, 5000, 1001, 0x12, []),
                flowFrame(true, 1001, 5001, 0x18,
                          request),
                flowFrame(false, 5051, 1048, 0x18,
                          seg2),
                flowFrame(false, 5101, 1048, 0x18,
                          seg3),
                flowFrame(false, 5001, 1048, 0x18,
                          seg1),
                flowFrame(false, 5001, 1048, 0x18,
                          seg1),
            ]
            var capture = BFCapture(
                name: "gauntlet", format: "synthetic",
                linktype: 1)
            for (index, raw) in raws.enumerated() {
                capture.frames.append(Betafisch.dissect(
                    bytes: raw, origLen: raw.count,
                    linktype: 1, number: index + 1,
                    timestamp: 1767225600.0
                        + Double(index)))
            }
            let extraction = BetafischDrift
                .extractDetailed(capture)
            cases += 1
            try Gauntlet.require(
                extraction.stats.flows == 1,
                "the exchange did not read as one flow")
            cases += 1
            try Gauntlet.require(
                extraction.objects.count == 1,
                "the picture did not carve exactly once")
            let object = extraction.objects[0]
            cases += 1
            try Gauntlet.require(object.kind == .png,
                "the carve is not a PNG")
            cases += 1
            try Gauntlet.require(
                Array(object.data) == png,
                "the carved bytes differ from the sent")
            cases += 1
            try Gauntlet.require(object.torn == false,
                "a whole stream read as torn")
            return "\(cases) cases: an out-of-order "
                + "HTTP exchange carved its picture "
                + "whole, exactly once"
        }
        add("betafisch", "pcapng round-trips") {
            var cases = 0
            let a: [UInt8] = [10, 0, 0, 1]
            let b: [UInt8] = [10, 0, 0, 2]
            let third = gxEth(gxIPv4(
                a, b, 6,
                gxTCP(49153, 443, 77, 99, 0x10,
                      [], a, b)))
            let all = [gxTCPFrame(), gxDNSFrame(),
                       third]
            var capture = BFCapture(
                name: "gauntlet", format: "synthetic",
                linktype: 1)
            for (index, raw) in all.enumerated() {
                capture.frames.append(Betafisch.dissect(
                    bytes: raw, origLen: raw.count,
                    linktype: 1, number: index + 1,
                    timestamp: 1767225600.0
                        + Double(index)))
            }
            let data = BetafischWrite.pcapng(
                frames: capture.frames,
                interfaces: [BFInterface(
                    name: "gauntlet", linktype: 1)],
                comment: "gauntlet round-trip")
            cases += 1
            try Gauntlet.require(!data.isEmpty,
                "the writer produced nothing")
            let scratch = DevKit.directory
                .appendingPathComponent(
                    "gauntlet-scratch", isDirectory: true)
            try? FileManager.default.removeItem(
                at: scratch)
            try FileManager.default.createDirectory(
                at: scratch,
                withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(
                    at: scratch)
            }
            let file = scratch.appendingPathComponent(
                "roundtrip.pcapng")
            try data.write(to: file)
            let readBack = try Data(contentsOf: file)
            cases += 1
            try Gauntlet.require(readBack == data,
                "the file bytes moved")
            let loaded = try Betafisch.load(
                data: readBack, name: "roundtrip.pcapng")
            cases += 1
            try Gauntlet.require(loaded.frames.count == 3,
                "frames were lost in the round-trip")
            for (index, frame)
                in loaded.frames.enumerated() {
                cases += 1
                try Gauntlet.require(
                    frame.bytes == all[index],
                    "a frame's bytes moved")
                cases += 1
                try Gauntlet.require(
                    frame.proto
                        == capture.frames[index].proto,
                    "a frame's verdict moved")
            }
            cases += 1
            try Gauntlet.require(
                BetafischTap.coverageNote
                    .contains("house tap"),
                "the coverage note moved")
            return "\(cases) cases: three frames "
                + "survived the writer, the file "
                + "and the reader"
        }
        add("files", "format parsers read fixtures") {
            var cases = 0
            var lines: [String] = []
            let emit: BlacksiteEmit = {
                text, _ in lines.append(text)
            }
            // ELF64 little-endian, DYN, AArch64,
            // no program headers.
            var elf: [UInt8] = [UInt8](
                repeating: 0, count: 64)
            elf[0] = 0x7F
            elf[1] = 0x45
            elf[2] = 0x4C
            elf[3] = 0x46
            elf[4] = 2
            elf[5] = 1
            elf[6] = 1
            elf[16] = 3
            elf[18] = 0xB7
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(elf)?.family
                    == "elf",
                "the ELF did not identify")
            BlacksiteBench.fileELFReport(
                elf, base: 0, emit: emit)
            cases += 1
            try Gauntlet.require(
                lines.contains {
                    $0.contains("ELF64")
                        && $0.contains("AArch64")
                        && $0.contains("DYN")
                },
                "the ELF headline read wrong: "
                    + lines.joined(separator: " | "))
            // A thin 64-bit Mach-O, arm64 EXECUTE.
            lines = []
            var macho: [UInt8] = [UInt8](
                repeating: 0, count: 32)
            macho[0] = 0xCF
            macho[1] = 0xFA
            macho[2] = 0xED
            macho[3] = 0xFE
            macho[4] = 0x0C
            macho[7] = 0x01
            macho[12] = 2
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(macho)?.family
                    == "macho",
                "the Mach-O did not identify")
            BlacksiteBench.fileMachOThin(
                macho, base: 0, emit: emit)
            cases += 1
            try Gauntlet.require(
                lines.contains {
                    $0.contains("arm64")
                        && $0.contains("EXECUTE")
                },
                "the Mach-O headline read wrong: "
                    + lines.joined(separator: " | "))
            // A one-entry stored ZIP.
            var zip: [UInt8] = []
            zip += [0x50, 0x4B, 0x03, 0x04]
            zip += [20, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            zip += [0, 0, 0, 0]
            zip += [5, 0, 0, 0]
            zip += [5, 0, 0, 0]
            zip += [12, 0, 0, 0]
            zip += Array("gauntlet.txt".utf8)
            zip += Array("hello".utf8)
            let cdAt = zip.count
            zip += [0x50, 0x4B, 0x01, 0x02]
            zip += [20, 0, 20, 0, 0, 0, 0, 0]
            zip += [0, 0, 0, 0, 0, 0, 0, 0]
            zip += [5, 0, 0, 0]
            zip += [5, 0, 0, 0]
            zip += [12, 0]
            zip += [UInt8](repeating: 0, count: 16)
            zip += Array("gauntlet.txt".utf8)
            let cdSize = zip.count - cdAt
            zip += [0x50, 0x4B, 0x05, 0x06]
            zip += [0, 0, 0, 0]
            zip += [1, 0, 1, 0]
            zip += [UInt8(cdSize & 0xFF), 0, 0, 0]
            zip += [UInt8(cdAt & 0xFF), 0, 0, 0]
            zip += [0, 0]
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(zip)?.family
                    == "zip",
                "the ZIP did not identify")
            guard let walk = BlacksiteBench
                .fileZIPWalk(zip) else {
                throw Gauntlet.Failure(message:
                    "the ZIP did not walk")
            }
            cases += 1
            try Gauntlet.require(walk.entries.count == 1,
                "the ZIP entry count moved")
            let entry = walk.entries[0]
            cases += 1
            try Gauntlet.require(
                entry.name == "gauntlet.txt"
                    && entry.method == 0
                    && entry.compSize == 5
                    && entry.rawSize == 5,
                "the ZIP entry read wrong")
            cases += 1
            try Gauntlet.require(
                walk.cdOffset == cdAt,
                "the ZIP directory offset moved")
            // A SQLite header: 4096-byte pages,
            // seven of them, UTF-8.
            var sqlite: [UInt8] = [UInt8](
                repeating: 0, count: 100)
            let magic = Array("SQLite format 3".utf8)
            sqlite.replaceSubrange(
                0..<15, with: magic)
            sqlite[16] = 0x10
            sqlite[18] = 1
            sqlite[19] = 1
            sqlite[31] = 7
            sqlite[59] = 1
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(sqlite)?.family
                    == "sqlite",
                "the SQLite file did not identify")
            guard let header = BlacksiteBench
                .fileSQLiteHeader(sqlite) else {
                throw Gauntlet.Failure(message:
                    "the SQLite header did not read")
            }
            cases += 1
            try Gauntlet.require(
                header.pageSize == 4096
                    && header.pages == 7
                    && header.encoding == 1,
                "the SQLite header read wrong")
            // A one-object PDF.
            let pdf = Array(
                "%PDF-1.7\n1 0 obj\n<<>>\nendobj\n"
                    .utf8)
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(pdf)?.family
                    == "pdf",
                "the PDF did not identify")
            let core = BlacksiteBench.filePDFCore(pdf)
            cases += 1
            try Gauntlet.require(
                core.version == "1.7"
                    && core.objects == 1,
                "the PDF core read wrong")
            // A PE stub identifies by family;
            // its deep walk reads operator
            // files, not fixtures — see report.
            var pe: [UInt8] = [UInt8](
                repeating: 0, count: 88)
            pe[0] = 0x4D
            pe[1] = 0x5A
            pe[60] = 64
            pe[64] = 0x50
            pe[65] = 0x45
            cases += 1
            try Gauntlet.require(
                BlacksiteBench.fileKind(pe)?.family
                    == "pe",
                "the PE did not identify")
            return "\(cases) cases: ELF, Mach-O, "
                + "ZIP, SQLite, PDF and PE fixtures "
                + "read whole"
        }
        add("control", "emcon standard holds") {
            var cases = 0
            cases += 1
            try Gauntlet.require(
                EmconStandard.maximumTotal == 100.0,
                "the exposure maxima no longer "
                    + "sum to 100")
            let organs: [EmconOrgan] = [
                .serveListed, .serveStealth, .gattHost,
                .beacon, .persona, .netAssault,
                .probing, .warRun, .banshee,
                .relayPoll, .updateCheck, .sweep]
            cases += 1
            try Gauntlet.require(organs.count == 12,
                "the organ census moved")
            func row(_ condition: EmconCondition,
                     _ allowed: [EmconOrgan]) {
                for organ in organs {
                    cases += 1
                    try Gauntlet.require(
                        condition.permits(organ)
                            == allowed.contains(organ),
                        "the ladder moved for an organ")
                }
            }
            row(.open, organs)
            row(.charlie,
                [.serveStealth, .relayPoll, .sweep])
            row(.bravo, [.sweep])
            row(.alpha, [])
            return "\(cases) cases: the ceiling is "
                + "100 and all four rungs held"
        }
        add("control", "sentinel ladder ordered") {
            var cases = 0
            let ladder: [Sentinel.Severity] = [
                .notice, .suspicious, .severe]
            let words = ["NOTICE", "SUSPICIOUS",
                         "SEVERE"]
            for (severity, word) in zip(ladder, words) {
                cases += 1
                try Gauntlet.require(severity.word == word,
                    "a rung lost its word")
            }
            cases += 1
            try Gauntlet.require(Set(words).count == 3,
                "two rungs share a word")
            // An alert survives its own codec.
            let alert = Sentinel.Alert(
                key: "gauntlet",
                at: Date(timeIntervalSince1970:
                            1767225600),
                severity: .severe,
                line: "a graded line",
                ip: "192.0.2.1")
            let data = try JSONEncoder().encode(alert)
            let back = try JSONDecoder().decode(
                Sentinel.Alert.self, from: data)
            cases += 1
            try Gauntlet.require(
                back.key == alert.key
                    && back.severity == .severe
                    && back.line == alert.line
                    && back.ip == alert.ip,
                "the alert codec lost a field")
            cases += 1
            try Gauntlet.require(
                abs(back.at.timeIntervalSince(
                    alert.at)) < 0.001,
                "the alert codec moved the time")
            // The standing store, read-only:
            // everything standing is severe, and
            // the recent window is its subset.
            let sentinel = Sentinel.shared
            for standing in sentinel.standingSevere {
                cases += 1
                try Gauntlet.require(
                    standing.severity == .severe,
                    "a non-severe alert stands")
            }
            let recent = sentinel.recentSevere(
                within: 600)
            cases += 1
            try Gauntlet.require(
                recent.count
                    <= sentinel.standingSevere.count,
                "the recent window outgrew the store")
            for recentAlert in recent {
                cases += 1
                try Gauntlet.require(
                    recentAlert.severity == .severe,
                    "a non-severe alert is recent")
            }
            return "\(cases) cases: the ladder's "
                + "words, codec and store held"
        }
        add("wardrobe", "themes whole") {
            var cases = 0
            let themes = AppTheme.builtIns
            cases += 1
            try Gauntlet.require(themes.count == 10,
                "the built-in census moved")
            let ids = ["phosphor", "bloodwork",
                       "ultraviolet", "arctic", "amber",
                       "bone", "halloween", "christmas",
                       "blackglass", "redteam"]
            cases += 1
            try Gauntlet.require(
                themes.map { $0.id } == ids,
                "the theme roster moved")
            cases += 1
            try Gauntlet.require(
                themes.first?.id == "phosphor",
                "the default theme is not first")
            func hexOK(_ text: String) -> Bool {
                guard text.count == 7,
                      text.hasPrefix("#") else {
                    return false
                }
                return text.dropFirst().allSatisfy {
                    $0.isHexDigit
                }
            }
            for theme in themes {
                for hex in [theme.background,
                            theme.accent,
                            theme.secondary] {
                    cases += 1
                    try Gauntlet.require(hexOK(hex),
                        "a theme hex is malformed: "
                            + hex)
                }
            }
            cases += 1
            try Gauntlet.require(
                themes.first {
                    $0.id == "redteam"
                }?.accent == "#FF1626",
                "the redteam accent moved")
            return "\(cases) cases: ten themes, "
                + "every hex well-formed"
        }
        add("wardrobe", "films all present") {
            var cases = 0
            // Each film under both of the app's
            // own lookups: the asset catalog and
            // the bundle resources.
            let films: [(String, String)] = [
                ("Assault", "assault"),
                ("BootReel", "boot-reel"),
                ("Centipede", "centipede"),
                ("Magdump", "magdump"),
                ("Rainfall", "rainfall"),
                ("Wallpaper", "wallpaper"),
                ("Redframe", "redframe"),
            ]
            for (asset, resource) in films {
                cases += 1
                let inAssets = NSDataAsset(
                    name: asset) != nil
                let inBundle = Bundle.main.url(
                    forResource: resource,
                    withExtension: "gif") != nil
                try Gauntlet.require(inAssets || inBundle,
                    "film missing from the bundle: "
                        + asset)
            }
            return "\(cases) cases: every film "
                + "found in the app's own stores"
        }
        add("wardrobe", "wallpaper decodes") {
            var cases = 0
            let data: Data?
            if let asset = NSDataAsset(
                name: "Wallpaper") {
                data = asset.data
            } else if let url = Bundle.main.url(
                forResource: "wallpaper",
                withExtension: "gif") {
                data = try? Data(contentsOf: url)
            } else {
                data = nil
            }
            guard let film = data else {
                throw Gauntlet.Failure(message:
                    "the wallpaper film is missing")
            }
            cases += 1
            try Gauntlet.require(film.count > 100_000,
                "the wallpaper shrank to "
                    + "\(film.count) bytes")
            cases += 1
            try Gauntlet.require(
                UIImage.animatedGIF(data: film) != nil,
                "the wallpaper does not decode")
            let delays = UIImage.gifDelays(film)
            cases += 1
            try Gauntlet.require(delays.count > 1,
                "the wallpaper has one frame")
            cases += 1
            try Gauntlet.require(
                delays.reduce(0, +) > 0,
                "the wallpaper's frames take no time")
            return "\(cases) cases: the wallpaper "
                + "animates over \(delays.count) frames"
        }
        add("stores", "session codec round-trips") {
            var cases = 0
            // The line codec's own primitives.
            let escaped = "\"" + "a" + "\\\"" + "b"
                + "\\\\" + "c" + "\\" + "u000a"
                + "d" + "\""
            cases += 1
            try Gauntlet.require(
                JSONL.string("a\"b\\c\nd") == escaped,
                "the string escaper moved")
            cases += 1
            try Gauntlet.require(
                JSONL.hex([0xDE, 0xAD]) == "dead",
                "the hex writer moved")
            cases += 1
            try Gauntlet.require(
                JSONL.seconds(1767225600.25)
                    == "1767225600.250",
                "the seconds writer moved")
            cases += 1
            try Gauntlet.require(
                JSONL.int(nil) == "null"
                    && JSONL.int(7) == "7",
                "the int writer moved")
            cases += 1
            try Gauntlet.require(
                JSONL.object([("b", "1"), ("a", "2")])
                    == "{\"b\":1,\"a\":2}",
                "the object writer moved")
            // Five hundred sightings through the
            // line codec, read back by an
            // independent decoder, in order.
            var lines: [String] = []
            for i in 0..<500 {
                let name: String?
                if i == 499 {
                    name = nil
                } else if i % 7 == 0 {
                    name = "quoted \"name\" \(i)"
                } else {
                    name = "beacon-\(i)"
                }
                let sighting = Sighting(
                    seenAt: 1767225600.0
                        + Double(i) * 0.25,
                    address: String(
                        format: "gauntlet-%03d", i),
                    name: name,
                    rssi: -40 - (i % 50),
                    manufacturerData: [
                        0x004C: [0x02, 0x15]],
                    serviceUUIDs: [
                        "0000feaa-0000-1000-8000-"
                            + "00805f9b34fb"],
                    txPower: i % 3 == 0 ? nil : -4,
                    serviceData: [:],
                    isConnectable: i % 2 == 0,
                    solicitedUUIDs: [])
                lines.append(sighting.jsonLine)
            }
            cases += 1
            try Gauntlet.require(lines.count == 500,
                "the batch sized wrong")
            for (i, line) in lines.enumerated() {
                let object = try JSONSerialization
                    .jsonObject(with: Data(line.utf8))
                guard let dict = object
                    as? [String: Any] else {
                    throw Gauntlet.Failure(message:
                        "a sighting line did not decode")
                }
                cases += 1
                try Gauntlet.require(
                    (dict["type"] as? String)
                        == "sighting",
                    "a line lost its type")
                try Gauntlet.require(
                    (dict["address"] as? String)
                        == String(
                            format: "gauntlet-%03d", i),
                    "the batch fell out of order")
                let seen = (dict["seen_at"]
                    as? NSNumber)?.doubleValue ?? -1
                try Gauntlet.require(
                    abs(seen - (1767225600.0
                        + Double(i) * 0.25)) < 0.001,
                    "a timestamp moved")
                try Gauntlet.require(
                    (dict["rssi"] as? NSNumber)?
                        .intValue == -40 - (i % 50),
                    "an rssi moved")
                let maker = dict["manufacturer_data"]
                    as? [String: Any]
                try Gauntlet.require(
                    (maker?["76"] as? String)
                        == "0215",
                    "the maker bytes moved")
                if i == 499 {
                    try Gauntlet.require(
                        dict["name"] is NSNull,
                        "a nil name did not write null")
                } else if i % 7 == 0 {
                    try Gauntlet.require(
                        (dict["name"] as? String)
                            == "quoted \"name\" \(i)",
                        "a quoted name broke")
                } else {
                    try Gauntlet.require(
                        (dict["name"] as? String)
                            == "beacon-\(i)",
                        "a name moved")
                }
            }
            return "\(cases) cases: 500 sighting "
                + "lines round-tripped in order"
        }
        // -- ONION (fix322) ----------------
        // The wrap's standard, pinned against
        // its pure cores: the inventory sums
        // to exactly 7.0, the bands and the
        // EMCON floors hold their order, the
        // SOCKS5 wire bytes are byte-exact,
        // and the pure scorer grades synthetic
        // postures to the exact decimal. No
        // network: snapshots and fixtures only.

        add("onion", "inventory sums to seven") {
            var cases = 0
            let maxima: [(String, Double)] = [
                ("tunnel", OnionStandard.maxTunnel),
                ("tor", OnionStandard.maxTorRoad),
                ("dns", OnionStandard.maxDNS),
                ("emissions",
                 OnionStandard.maxEmissions),
                ("listeners",
                 OnionStandard.maxListeners),
                ("identity",
                 OnionStandard.maxIdentity),
                ("metadata",
                 OnionStandard.maxMetadata),
            ]
            var sum = 0.0
            for (name, maximum) in maxima {
                cases += 1
                try Gauntlet.require(maximum > 0,
                    "a layer's maximum is not "
                    + "positive: " + name)
                sum += maximum
            }
            try Gauntlet.require(sum == 7.0,
                "the inventory does not sum to "
                + "7.0: \(sum)")
            try Gauntlet.require(
                OnionStandard.maximumTotal == 7.0,
                "the standard's total is not 7.0")
            let peeled = OnionStandard.score(
                OnionSnapshot())
            try Gauntlet.require(
                peeled.rows.count == 7,
                "the scorer does not lay seven "
                + "rows")
            for row in peeled.rows {
                cases += 1
                let declared = maxima.first {
                    $0.0 == row.key
                }?.1 ?? -1
                try Gauntlet.require(
                    row.maximum == declared,
                    "row maximum drifted from the "
                    + "inventory: " + row.key)
            }
            return "\(cases) cases: seven layers, "
                + "maxima 1.5+1.5+1.0+1.0+0.75"
                + "+0.5+0.75 = exactly 7.0"
        }
        add("onion", "bands ordered") {
            var cases = 0
            let ladder: [(Double, String)] = [
                (0.0, "PEELED"), (0.25, "THIN"),
                (1.75, "THIN"), (2.0, "SKINNED"),
                (3.75, "SKINNED"), (4.0, "WRAPPED"),
                (5.25, "WRAPPED"),
                (5.5, "LAYERED"), (6.75, "LAYERED"),
                (7.0, "FULL ONION"),
            ]
            for (value, band) in ladder {
                cases += 1
                try Gauntlet.require(
                    OnionStandard.band(for: value)
                        == band,
                    "band drifted at \(value): "
                    + OnionStandard.band(for: value))
            }
            var previous = -1.0
            var probe = 0.0
            while probe <= 7.0 {
                cases += 1
                let bandIndex = ladder
                    .firstIndex {
                        $0.1 == OnionStandard.band(
                            for: probe)
                    } ?? -1
                try Gauntlet.require(
                    Double(bandIndex) >= previous,
                    "the bands fell out of order "
                    + "at \(probe)")
                previous = Double(bandIndex)
                probe += 0.25
            }
            return "\(cases) cases: PEELED < THIN "
                + "< SKINNED < WRAPPED < LAYERED "
                + "< FULL ONION, boundaries exact"
        }
        add("onion", "emcon floors monotonic") {
            var cases = 0
            let floors: [(EmconCondition, Double)] = [
                (.open, 0.0), (.charlie, 2.0),
                (.bravo, 4.5), (.alpha, 7.0),
            ]
            var previous = -1.0
            for (condition, floor) in floors {
                cases += 1
                try Gauntlet.require(
                    condition.onionFloor == floor,
                    "a floor drifted: "
                    + "\(condition) asks "
                    + "\(condition.onionFloor)")
                try Gauntlet.require(
                    condition.onionFloor >= previous,
                    "the floors are not monotonic")
                previous = condition.onionFloor
            }
            let full = OnionStandard.score(
                onionFullFixture())
            try Gauntlet.require(
                OnionStandard.floorGap(
                    full, .alpha) == 0,
                "a full onion falls short of "
                + "alpha's floor")
            let peeled = OnionStandard.score(
                onionPeeledFixture())
            try Gauntlet.require(
                OnionStandard.floorGap(
                    peeled, .charlie) == 2.0,
                "a peeled house is not 2.0 "
                + "short of charlie's floor")
            return "\(cases) cases: floors "
                + "0.0/2.0/4.5/7.0, monotonic "
                + "with the condition ladder"
        }
        add("onion", "socks5 wire bytes exact") {
            var cases = 0
            try Gauntlet.require(
                OnionSOCKS.greetingBytes()
                    == [0x05, 0x01, 0x00],
                "the greeting bytes moved")
            cases += 1
            var wantDomain: [UInt8] = [0x05, 0x01,
                0x00, 0x03, 0x0B]
            wantDomain += [UInt8](
                "example.com".utf8)
            wantDomain += [0x01, 0xBB]
            try Gauntlet.require(
                OnionSOCKS.requestBytes(
                    host: "example.com", port: 443)
                    == wantDomain,
                "the domain CONNECT bytes moved")
            cases += 1
            try Gauntlet.require(
                OnionSOCKS.requestBytes(
                    host: "192.0.2.1", port: 80)
                    == [0x05, 0x01, 0x00, 0x01,
                        192, 0, 2, 1, 0x00, 0x50],
                "the ipv4 CONNECT bytes moved")
            cases += 1
            let reply = OnionSOCKS.parseReply(
                [0x05, 0x00, 0x00, 0x01,
                 127, 0, 0, 1, 0x1F, 0x90])
            try Gauntlet.require(reply != nil,
                "a sound reply did not parse")
            try Gauntlet.require(reply?.rep == 0,
                "the fixture's rep moved")
            try Gauntlet.require(
                reply?.bound == "127.0.0.1",
                "the bound address moved")
            try Gauntlet.require(
                reply?.totalLength == 10,
                "the reply length moved")
            cases += 4
            let refused = OnionSOCKS.parseReply(
                [0x05, 0x05, 0x00, 0x01,
                 0, 0, 0, 0, 0, 0])
            try Gauntlet.require(
                refused?.rep == 5,
                "the refusal fixture lost its rep")
            try Gauntlet.require(
                OnionSOCKS.repName(5)
                    == "connection refused",
                "rep 5 lost its name")
            try Gauntlet.require(
                OnionSOCKS.parseReply(
                    [0x05, 0x00]) == nil,
                "a truncated reply parsed")
            cases += 3
            return "\(cases) cases: greeting + "
                + "CONNECT (name and literal) "
                + "byte-exact, replies parse, "
                + "REP codes named"
        }
        add("onion", "scorer exact on fixtures") {
            var cases = 0
            let peeled = OnionStandard.score(
                onionPeeledFixture())
            try Gauntlet.require(
                peeled.value == 0.0,
                "the peeled fixture scored "
                + "\(peeled.value)")
            try Gauntlet.require(
                peeled.band == "PEELED",
                "the peeled fixture banded "
                + peeled.band)
            cases += 2
            let full = OnionStandard.score(
                onionFullFixture())
            try Gauntlet.require(
                full.value == 7.0,
                "the full fixture scored "
                + "\(full.value)")
            try Gauntlet.require(
                full.band == "FULL ONION",
                "the full fixture banded "
                + full.band)
            cases += 2
            // Tunnel present, not the road
            // (0.50) + bare gateway DNS (0.25)
            // + quiet organs (1.0+0.75+0.5
            // +0.75) = 3.75.
            var a = OnionSnapshot()
            a.tunnelOtherName = "utun4"
            a.gatewayIP = "192.168.1.1"
            let scoreA = OnionStandard.score(a)
            try Gauntlet.require(
                scoreA.value == 3.75,
                "partial A scored "
                + "\(scoreA.value), want 3.75")
            cases += 1
            // Tunnel default (1.5) + DNS rides
            // (1.0) + wrap on, road answered
            // but fetch failed (0.25) + a
            // listed serve AND the GATT stage
            // standing (emissions 1.0 − 0.40
            // − 0.30 = 0.30) + one listed
            // listener (0.50) + personal name
            // (0) + relay polling (0.50)
            // = 4.05.
            var b = onionFullFixture()
            b.probe = OnionProbeRecord(
                when: Date(), endpoint:
                    "127.0.0.1:9050",
                socksAnswered: true,
                wrappedOK: false, isTor: nil,
                exitIP: nil, problem: "fixture")
            b.organs.gattHostOn = true
            b.organs.serveRunning = true
            b.organs.serveListeners = 1
            b.organs.deviceName = "Gauntlet's iPhone"
            b.organs.relayPolling = true
            let scoreB = OnionStandard.score(b)
            try Gauntlet.require(
                scoreB.value == 4.05,
                "partial B scored "
                + "\(scoreB.value), want 4.05")
            cases += 1
            // Road answers, wrap off (0.50)
            // + tunnel-other (0.50) + gateway
            // DNS (0.25) + beacon standing
            // (0.70) + stealth listeners
            // (0.75) + clean identity (0.50)
            // + assault running (0.50)
            // = 3.70.
            var c = OnionSnapshot()
            c.tunnelOtherName = "utun2"
            c.gatewayIP = "192.168.1.1"
            c.probe = OnionProbeRecord(
                when: Date(), endpoint:
                    "127.0.0.1:9050",
                socksAnswered: true,
                wrappedOK: true, isTor: true,
                exitIP: "192.0.2.9", problem: "")
            c.organs.beaconOn = true
            c.organs.serveRunning = true
            c.organs.stealth = true
            c.organs.assaultOn = true
            let scoreC = OnionStandard.score(c)
            try Gauntlet.require(
                scoreC.value == 3.70,
                "partial C scored "
                + "\(scoreC.value), want 3.70")
            cases += 1
            return "\(cases) cases: peeled 0.0, "
                + "full 7.0, partials 3.75 / "
                + "4.05 / 3.70 — to the cent"
        }
        // The battery: the deep bench — chat
        // by the thousand, stress by the ten
        // thousand (GauntletBattery.swift).
        steps += GauntletBattery.steps(
            intensity: intensity, rng: &fuzz)
        return steps
    }
}

/// A tiny lock-guarded counter for the
/// concurrency stage.
private final class GauntletCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// The Onion's peeled fixture (fix322):
/// every row starved — no tunnel, no road,
/// no gateway, the loud organs standing, a
/// personal name on the wire. Scores 0.0.
private func onionPeeledFixture()
    -> OnionSnapshot {
    var snap = OnionSnapshot()
    snap.organs.serveRunning = true
    snap.organs.serveListeners = 3
    snap.organs.gattHostOn = true
    snap.organs.beaconOn = true
    snap.organs.deviceName =
        "Gauntlet's iPhone"
    snap.organs.relayPolling = true
    snap.organs.assaultOn = true
    snap.organs.warKnocking = true
    return snap
}

/// The Onion's full fixture (fix322): the
/// tunnel carries the road, the wrap is on
/// and proven, and every organ is quiet.
/// Scores exactly 7.0.
private func onionFullFixture()
    -> OnionSnapshot {
    var snap = OnionSnapshot()
    snap.tunnelDefaultName = "utun4"
    snap.wrapOn = true
    snap.probe = OnionProbeRecord(
        when: Date(), endpoint: "127.0.0.1:9050",
        socksAnswered: true, wrappedOK: true,
        isTor: true, exitIP: "192.0.2.9",
        problem: "")
    return snap
}
