import CryptoKit
import Foundation
import SwiftUI

/// The night log: one timeline for the whole instrument.
///
/// Until now each organ kept its own records — Listen its session
/// JSONL, Serve its inbox, EMCON its tripwire log — and none of
/// them could see the others. The journal is the shared ledger:
/// modules append one line per event worth remembering (a Serve
/// arrival, a tripwire knock, a posture change, a listening
/// session's bounds), and the Night Log view in the Sessions tab
/// reads them back as a single chronological record. The file is
/// JSONL — one object per line — so it feeds the same offline
/// tooling as every other nightjar log.
///
/// Deliberately human-scale: Listen journals its session bounds,
/// not every advertisement; the firehose stays in the session
/// files where it belongs.
struct NightEvent: Identifiable, Codable {
    var id: String
    var when: Date
    var module: String
    var kind: String
    var text: String
    /// Seal chain: `p` names the previous sealed line's hash,
    /// `h` is this line's SHA-256 (over the line carrying `p`
    /// but not `h`). Nil on lines written before the chain
    /// existed — history is not rewritten to look sealed.
    var p: String? = nil
    var h: String? = nil
}

/// The backup shield (fix205 — NSA/CISA
/// program, Arc A): the house's sensitive
/// stores — inbox captures, the night log,
/// session and trace records, her transcript
/// and subconscious, canary lessons, chat
/// threads, device baselines, the developer
/// kit's records — are marked out of device
/// backups, so what was gathered on this
/// phone does not ride an iCloud or desktop
/// backup out of it unsealed. The vault's
/// files were always sealed; these were the
/// unsealed remainder. Run at launch and
/// again on backgrounding, so stores born
/// during a session are shielded before the
/// system takes its snapshots.
enum BackupShield {
    static func shieldSensitiveStores() {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0]
        let names = [
            "exchanges.jsonl",
            "nightjar-nightlog.jsonl",
            "canary-lessons.json",
            "knocktalk-threads.json",
            "network-trace-logbook.json",
            "skelli.json",
            "subconscious.json",
            "dossier-baselines.json",
            "sessions", "Traces", "Developer",
        ]
        for name in names {
            var url = docs
                .appendingPathComponent(name)
            guard FileManager.default.fileExists(
                atPath: url.path) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }
}

enum Journal {
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("nightjar-nightlog.jsonl")
    }

    private static let queue = DispatchQueue(label: "nightjar.journal")
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func log(_ module: String, _ kind: String, _ text: String) {
        queue.async {
            if !chainLoaded { loadChainTail() }
            var event = NightEvent(id: UUID().uuidString, when: Date(),
                                   module: module, kind: kind,
                                   text: text)
            event.p = lastHash
            guard let body = try? encoder.encode(event)
            else { return }
            let hash = sha256Hex(body)
            event.h = hash
            // One encode per event, not two: the
            // seal folds into the body's own bytes
            // ahead of its closing brace, with the
            // honest double-encode as the fallback
            // if the body ever isn't a JSON object.
            var line: Data
            if body.last == UInt8(ascii: "}") {
                line = body.dropLast()
                line.append(contentsOf:
                    ",\"h\":\"\(hash)\"}"
                        .utf8)
            } else if let full = try? encoder
                .encode(event) {
                line = full
            } else { return }
            line.append(contentsOf: [0x0A])
            let url = fileURL
            // The chain commits only once the event is
            // actually on disk — committing first left a
            // permanent missing link after any failed
            // write, and every later event chained onto
            // a hash that was never in the file.
            var written = false
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                written = (try? handle.write(
                    contentsOf: line)) != nil
            } else {
                written = (try? line.write(
                    to: url, options: .atomic)) != nil
            }
            guard written else { return }
            lastHash = event.h
            onEvent?(event)
        }
    }

    /// A feed of everything written, for the one listener
    /// whose job is the whole picture: the steward. Set by
    /// the app at launch; called on the journal's queue, so
    /// the listener hops queues itself.
    static var onEvent: ((NightEvent) -> Void)?

    // MARK: - seal chain

    /// Every line names the hash of the sealed line before it,
    /// so the log is a chain: alter, reorder, or remove a
    /// sealed line and verification breaks at exactly that
    /// line. (Cutting lines off the END leaves nothing pointing
    /// forward to miss them — no chain can prove a negative
    /// about its own tail, and this one doesn't claim to.)
    private static var lastHash: String?
    private static var chainLoaded = false

    private static func sha256Hex(_ data: Data) -> String {
        let digits: [Character] =
            Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(64)
        for byte in SHA256.hash(data: data) {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return out
    }

    /// The file's tail as text, beginning at a
    /// line boundary: reads are bounded no
    /// matter how long the house's history
    /// grows. (The seal chain's genesis rule
    /// forbids rotating the file away — a
    /// rotated head would read as tampering —
    /// so instead, no reader ever pays for
    /// more history than it asked for.)
    private static func tailText(
        maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(
            forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes)
            ? size - UInt64(maxBytes) : 0
        _ = try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd(),
              !data.isEmpty else { return nil }
        if start > 0,
           let newline = data.firstIndex(of: 0x0A) {
            // The first line is a fragment of a
            // longer history; drop it whole.
            // (0x0A never occurs inside a
            // multi-byte UTF-8 sequence, so the
            // cut is always on a character edge.)
            data = data.subdata(
                in: (newline + 1)..<data.count)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func loadChainTail() {
        chainLoaded = true
        guard let text = tailText(
            maxBytes: 256 * 1024) else { return }
        for line in text.split(separator: "\n").reversed() {
            if let event = try? decoder.decode(
                NightEvent.self, from: Data(line.utf8)),
               let h = event.h {
                lastHash = h
                return
            }
        }
    }

    struct ChainReport {
        var sealed: Int
        var legacy: Int
        var brokenLine: Int?
    }

    static func verifyChain() -> ChainReport {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return ChainReport(sealed: 0, legacy: 0,
                                  brokenLine: nil) }
        var prev: String?
        var sealed = 0
        var legacy = 0
        var lineNo = 0
        for raw in text.split(separator: "\n",
                              omittingEmptySubsequences: false) {
            lineNo += 1
            if raw.isEmpty { continue }
            guard let event = try? decoder.decode(
                NightEvent.self, from: Data(raw.utf8)) else {
                return ChainReport(sealed: sealed, legacy: legacy,
                                   brokenLine: lineNo)
            }
            guard let h = event.h else { legacy += 1; continue }
            var body = event
            body.h = nil
            guard let encoded = try? encoder.encode(body),
                  sha256Hex(encoded) == h, event.p == prev else {
                return ChainReport(sealed: sealed, legacy: legacy,
                                   brokenLine: lineNo)
            }
            sealed += 1
            prev = h
        }
        return ChainReport(sealed: sealed, legacy: legacy,
                           brokenLine: nil)
    }

    /// Newest first, capped — the view's working set.
    /// Reads only the tail the limit can need:
    /// the SIGINT station asks every two seconds
    /// and must never pay for the whole history.
    static func events(limit: Int = 300) -> [NightEvent] {
        let budget = min(4 * 1024 * 1024,
                         max(256 * 1024, limit * 1024))
        guard let text = tailText(maxBytes: budget)
        else { return [] }
        var parsed: [NightEvent] = []
        for line in text.split(separator: "\n") {
            if let event = try? decoder.decode(
                NightEvent.self, from: Data(line.utf8)) {
                parsed.append(event)
            }
        }
        return Array(parsed.suffix(limit).reversed())
    }

    /// Start the ledger over: the file is deleted on the
    /// journal's own queue, so no append can interleave,
    /// and the chain head forgets — the next line written
    /// opens a fresh chain and names no parent.
    static func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
            lastHash = nil
            chainLoaded = true
        }
    }
}

/// The morning brief: the sealed log distilled to the lines
/// worth reading first. A ledger answers "what happened, in
/// order, provably"; the brief answers "what matters" — the
/// last twelve hours, counted by kind, with the narrative
/// lines quoted whole.
enum MorningBrief {
    static let window: TimeInterval = 12 * 3600

    static func lines(events: [NightEvent],
                      now: Date = Date()) -> [String] {
        let recent = events.filter {
            now.timeIntervalSince($0.when) <= window
        }
        guard !recent.isEmpty else { return [] }
        func count(_ module: String, _ kind: String) -> Int {
            recent.filter { $0.module == module && $0.kind == kind }
                .count
        }
        func latest(_ module: String, _ kind: String) -> NightEvent? {
            recent.filter { $0.module == module && $0.kind == kind }
                .max { $0.when < $1.when }
        }
        var out: [String] = []
        let knocks = count("emcon", "knock")
        if knocks > 0 {
            out.append("\(knocks) knock(s) on the tripwire.")
        }
        let drops = count("canary", "honeydrop")
        if drops > 0 {
            out.append("\(drops) honeydrop(s) TAKEN — someone "
                       + "reached for the prize.")
        }
        if let dh = latest("emcon", "deadhand"),
           dh.text.contains("FELL") {
            out.append("The dead hand fell: " + dh.text)
        }
        if let c = latest("emcon", "conductor") {
            let n = count("emcon", "conductor")
            out.append("The conductor fired \(n) time(s). "
                       + "Latest: " + c.text)
        }
        if let s = latest("emcon", "sense") {
            out.append("Second sense: " + s.text)
        }
        let deviations = count("emcon", "hometurf")
        if deviations > 0 {
            out.append("\(deviations) deviation(s) from the "
                       + "learned home pattern.")
        }
        let drift = count("dossier", "drift")
        if drift > 0 {
            out.append("\(drift) dossier drift report(s) — a "
                       + "watched address changed its story.")
        }
        let capsules = count("knocktalk", "capsule")
        if capsules > 0 {
            out.append("\(capsules) time capsule(s) opened.")
        }
        let flares = count("listen", "flare")
        if flares > 0 {
            out.append("\(flares) flare sighting(s) — a paired "
                       + "operator was in radio range.")
        }
        if let m = latest("emcon", "maneuvers") {
            out.append("Maneuvers: " + m.text)
        }
        let stewardPlans = count("steward", "plan")
        if stewardPlans > 0 {
            out.append("The steward acted \(stewardPlans) "
                       + "time(s) under its charter.")
        }
        let grades = count("steward", "grade")
        if grades > 0, let g = latest("steward", "grade") {
            out.append("Steward's record: \(grades) plan(s) "
                       + "graded. Latest — " + g.text)
        }
        let caseCount = count("steward", "case")
        if caseCount > 0 {
            out.append("\(caseCount) case-file event(s) — "
                       + "investigations are accumulating "
                       + "in the EMCON tab.")
        }
        if let s = latest("steward", "shift") {
            out.append("Steward's shift report: " + s.text)
        }
        let spars = count("emcon", "spar")
        if spars > 0 {
            out.append("\(spars) self-sparring run(s) against "
                       + "your own Serve.")
        }
        return out
    }

    static func text(events: [NightEvent],
                     now: Date = Date()) -> String {
        let ls = lines(events: events, now: now)
        guard !ls.isEmpty else {
            return "The morning brief: a quiet twelve hours. "
                + "Nothing knocked that mattered."
        }
        return "The morning brief — the last twelve hours:\n"
            + ls.map { "· " + $0 }.joined(separator: "\n")
    }
}

struct NightLogView: View {
    @State private var events: [NightEvent] = []
    @State private var report: Journal.ChainReport?
    @State private var shareItem: ShareItem?
    @State private var entriesOpen = false
    @State private var confirmClear = false

    private var reportText: String? {
        guard let report = report else { return nil }
        if let broken = report.brokenLine {
            return "Chain broken at line \(broken) — a sealed "
                + "line was altered, reordered, or removed "
                + "there. \(report.sealed) sealed lines verified "
                + "before the break."
        }
        return "Chain intact: \(report.sealed) sealed lines "
            + "verify, in order."
            + (report.legacy > 0
                ? " \(report.legacy) older lines predate the "
                    + "chain and are unsealed."
                : "")
    }

    var body: some View {
        List {
            if !events.isEmpty {
                let brief = MorningBrief.lines(events: events)
                Section(header: Text(L("The morning brief")),
                        footer: Text(L("The last twelve hours, distilled from the sealed log below — counts and headlines; the proof stays in the ledger."))) {
                    if brief.isEmpty {
                        Text(L("A quiet twelve hours. Nothing knocked that mattered."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(brief, id: \.self) { line in
                            Text(line).font(.callout)
                        }
                        Button {
                            shareItem = ShareItem(items: [
                                MorningBrief.text(events: events)])
                        } label: {
                            Label(L("Share the brief"),
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Section(header: Text(L("Seal chain")),
                        footer: Text(L("Each new line names the hash of the sealed line before it. Verification proves no sealed line was altered, reordered, or removed from the middle of the log."))) {
                    Button {
                        report = Journal.verifyChain()
                    } label: {
                        Label(L("Verify the chain"),
                              systemImage: "checkmark.seal")
                    }
                    if let reportText = reportText {
                        Text(reportText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if events.isEmpty {
                Text(L("Nothing journaled yet. Serve arrivals, tripwire knocks, EMCON posture changes, sparring runs and listening-session bounds land here as one timeline — the whole instrument, one night at a time."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !events.isEmpty {
                Section {
                    Button {
                        withAnimation { entriesOpen.toggle() }
                    } label: {
                        HStack {
                            Label(L("Entries"),
                                  systemImage: "list.bullet")
                            Spacer()
                            Text("\(events.count)")
                                .foregroundStyle(.secondary)
                            Image(systemName: entriesOpen
                                  ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    if entriesOpen {
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(event.module.uppercased())
                                        .font(.caption.weight(.bold))
                                    Text(event.kind)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(event.when.formatted(
                                        date: .omitted,
                                        time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(event.text).font(.callout)
                                HStack(spacing: 6) {
                                    Text(event.when.formatted(
                                        date: .abbreviated,
                                        time: .omitted))
                                    if let h = event.h {
                                        Text(String(format: L("· sealed %@"),
                                                    String(h.prefix(10))))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label(L("Clear the log"),
                              systemImage: "trash")
                    }
                }
            }
            if !events.isEmpty {
                Button {
                    Haptics.tap()
                    shareItem = ShareItem(items: [Journal.fileURL])
                } label: {
                    Label(L("Share the night log (JSONL)"),
                          systemImage: "square.and.arrow.up")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle(L("Night log"))
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .confirmationDialog(
            "Clear the night log?",
            isPresented: $confirmClear,
            titleVisibility: .visible) {
            Button(String(format: L("Clear %lld entries"), events.count),
                   role: .destructive) {
                Journal.clear()
                events = []
                report = nil
                entriesOpen = false
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("The sealed log file is deleted and the seal chain starts fresh. This cannot be undone."))
        }
        .onAppear { events = Journal.events() }
    }
}
