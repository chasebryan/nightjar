import AVFoundation
import CryptoKit
import Foundation
import SwiftUI
import UIKit

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
                state.contains("nightjar-hack"),
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
