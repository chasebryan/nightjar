import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The developer kit: a section of its own, for
/// building and improving the house. While it is
/// armed, two recorders run. The flight recorder
/// (DevLog) keeps a short, capped trail of what
/// Skelli and the system just did — asks, bench
/// loads, second readings, memory warnings,
/// lifecycle. The crash recorder (CrashRecorder)
/// stands at the two doors a dying app leaves
/// by — an uncaught exception, a fatal signal —
/// and writes down why before the process ends:
/// the exception or signal, and the backtrace.
///
/// Everything lives as plain text under
/// Documents/Developer, reads back in the
/// console below, and leaves the phone as ONE
/// log file (share or copy) that can be handed
/// to whoever maintains her. Off, nothing is
/// recorded and nothing is installed. The
/// records are the operator's: they are never
/// sent anywhere by the app itself.
///
/// Honest limits: a kill the system delivers
/// without a signal the app can catch — a
/// jetsam memory execution, a watchdog
/// termination — leaves no record here; the
/// system's own Analytics log remains the
/// backstop for those.
enum DevKit {
    static let enabledKey = "app.developer"

    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var directory: URL {
        let base = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(
            "Developer", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var crashesDirectory: URL {
        let dir = directory.appendingPathComponent(
            "crashes", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var breadcrumbsURL: URL {
        directory.appendingPathComponent(
            "breadcrumbs.txt")
    }

    /// This process's memory footprint, in MB
    /// (-1 when the kernel will not say).
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size
                / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(
            to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(TASK_VM_INFO),
                          $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.phys_footprint / 1_048_576)
    }

    private static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine)
            .children.reduce(into: "") { text, child in
                if let byte = child.value as? Int8,
                   byte != 0 {
                    text.append(Character(
                        UnicodeScalar(UInt8(byte))))
                }
            }
    }

    /// The state of the house, as one text block —
    /// the same block the console shows and the
    /// export carries.
    static func houseState() -> String {
        let defaults = UserDefaults.standard
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "?"
        let commit = SourceStamp.shortCommit
            ?? "unstamped"
        let changes = SourceStamp.uncommittedChanges
        let diskMB: String
        if let capacity = try? URL(
            fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey
            ]).volumeAvailableCapacityForImportantUsage {
            diskMB = "\(capacity / 1_048_576) MB free"
        } else {
            diskMB = "unknown"
        }
        let downloaded = defaults.stringArray(
            forKey: "skelli.weightsDownloaded") ?? []
        let mindMode = defaults.string(
            forKey: "skelli.mindMode") ?? "council"
        let weightsModel = defaults.string(
            forKey: "skelli.weightsModel") ?? "none"
        let language = LanguageCenter.shared
        // Built line by line, on purpose: one
        // sixteen-element literal of joined and
        // interpolated strings is more expression
        // than the type-checker will chew.
        var lines: [String] = []
        lines.append("App: nightjar "
            + "\(AppInfo.version) (\(build))")
        lines.append("Source: \(commit)"
            + (changes > 0
               ? " + \(changes) uncommitted" : ""))
        lines.append("iOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Device: \(deviceModel)")
        lines.append("Memory footprint: "
            + "\(footprintMB()) MB")
        lines.append("Disk: \(diskMB)")
        lines.append("Language: "
            + "\(language.effective) "
            + "(welcomed: \(language.welcomed))")
        lines.append("EMCON condition: "
            + "\(EmconCondition.current)")
        lines.append("Mind mode: \(mindMode)")
        lines.append("Weights model: "
            + "\(weightsModel) "
            + "(\(downloaded.count) downloaded)")
        lines.append("Skelli is feeling: "
            + "\(SkelliHeart.shared.feeling.word)")
        let saved = SkelliStore.load()
        lines.append("Chat: \(saved.lines.count) "
            + "lines on screen, "
            + "\(saved.archive.count) archived, "
            + "\(saved.notes.count) notes kept")
        let factCount = SubconsciousCenter
            .shared.facts.count
        lines.append("Learned facts: "
            + "\(factCount)")
        lines.append("Registries: "
            + "\(CompanyRegistry.names.count) "
            + "makers, "
            + "\(MemberRegistry.names.count) "
            + "members, "
            + "\(PortRegistry.names.count) "
            + "named ports")
        let marks = TomatoMarks.shared.marked
        lines.append("Tomato marks: "
            + (marks.isEmpty
               ? "none"
               : "\(marks.count) — "
                 + marks.sorted()
                     .joined(separator: ", ")))
        lines.append("Tomato barrage: "
            + (TomatoBarrage.shared.running
               ? "running at "
                 + TomatoBarrage.shared
                     .targetLabel
               : "idle"))
        lines.append("Macro library: "
            + "\(MacroStore.load().count) saved, "
            + "\(MacroTemplates.all.count) "
            + "house presets")
#if os(iOS)
        let headroomMB = os_proc_available_memory()
            / 1_048_576
#else
        let headroomMB = macAvailableMemoryBytes()
            / 1_048_576
#endif
        lines.append("Weights headroom: ~"
            + "\(headroomMB) MB free")
        lines.append("Developer options: "
            + "\(enabled ? "on" : "off")")
        lines.append("Crash records: "
            + "\(CrashRecorder.records().count)")
        lines.append("Flight recorder: "
            + "\(DevLog.recent(10_000).count) "
            + "event(s) kept")
        return lines.joined(separator: "\n")
    }

    /// The whole log — house state, every crash
    /// record, the flight recorder's tail — as
    /// one text, ready to read, copy, or share.
    static func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        var out = "NIGHTJAR DEVELOPER LOG\n"
        out += "generated: "
            + formatter.string(from: Date()) + "\n\n"
        out += "=== HOUSE STATE ===\n"
        out += houseState() + "\n\n"
        out += "=== CRASH RECORDS ===\n"
        let records = CrashRecorder.records()
        if records.isEmpty {
            out += "(none recorded)\n\n"
        }
        for record in records {
            out += "\n--- \(record.name) ---\n"
            out += record.text + "\n"
        }
        out += "\n=== FLIGHT RECORDER "
            + "(most recent last) ===\n"
        let crumbs = DevLog.recent(400)
        out += crumbs.isEmpty
            ? "(no events recorded)\n"
            : crumbs.joined(separator: "\n") + "\n"
        out += "\n=== GAUNTLET ===\n"
        out += Gauntlet.lastSummary() + "\n"
        out += "\n=== CHAT TRANSCRIPT ===\n"
        out += chatTranscriptText() + "\n"
        if let log = Gauntlet.latestLogText() {
            out += "\n--- latest gauntlet log ---\n"
            out += log + "\n"
        }
        return out
    }

    /// Every chat she has had — the archive
    /// the soft clear kept plus the lines on
    /// screen, in order, one text. The raw
    /// material for improving her: what was
    /// actually asked, and what she actually
    /// answered, in the field.
    static func chatTranscriptText() -> String {
        let saved = SkelliStore.load()
        var seen = Set<UUID>()
        let all = (saved.archive + saved.lines)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.when < $1.when }
        let stamp = ISO8601DateFormatter()
        let clock = DateFormatter()
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = "NIGHTJAR CHAT TRANSCRIPT\n"
        out += "generated: "
            + stamp.string(from: Date()) + "\n"
        out += "\(all.count) lines "
            + "(\(saved.archive.count) archived, "
            + "\(saved.lines.count) on screen), "
            + "\(saved.notes.count) notes kept\n\n"
        for line in all {
            out += "["
                + clock.string(from: line.when)
                + "] "
                + (line.fromOperator
                   ? "OPERATOR" : "SKELLI")
                + "\n"
            out += line.text + "\n\n"
        }
        return out
    }

    /// The transcript as a file, for the
    /// share sheet.
    static func chatExportFileURL() -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nightjar-chat-transcript.txt")
        try? chatTranscriptText().write(
            to: url, atomically: true,
            encoding: .utf8)
        return url
    }

    /// The export as a file, for the share sheet.
    static func exportFileURL() -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nightjar-developer-log.txt")
        try? exportText().write(
            to: url, atomically: true,
            encoding: .utf8)
        return url
    }
}

/// The flight recorder: one line per event —
/// time, category, text — appended on a serial
/// queue, capped by size so it can never grow
/// into the problem it describes. Every call
/// checks the developer switch first; off means
/// the event never existed.
enum DevLog {
    private static let queue = DispatchQueue(
        label: "nightjar.devlog")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX")
        formatter.dateFormat =
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()
    private static let maxBytes = 262_144

    static func event(_ category: String,
                      _ text: String) {
        guard DevKit.enabled else { return }
        let line = "\(stamp.string(from: Date())) "
            + "[\(category)] \(text)\n"
        queue.async {
            let url = DevKit.breadcrumbsURL
            if let handle = try? FileHandle(
                forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                if let data = line.data(
                    using: .utf8) {
                    try? handle.write(
                        contentsOf: data)
                }
            } else {
                try? line.write(
                    to: url, atomically: true,
                    encoding: .utf8)
            }
            rotateIfNeeded()
        }
    }

    /// Past the cap, the file is rewritten with
    /// only its newest lines — a recorder that
    /// fills the disk would be its own incident.
    private static func rotateIfNeeded() {
        let url = DevKit.breadcrumbsURL
        let size = (try? FileManager.default
            .attributesOfItem(atPath: url.path))?[.size]
            as? Int ?? 0
        guard size > maxBytes,
              let text = try? String(
                contentsOf: url, encoding: .utf8)
        else { return }
        let tail = text.split(
            separator: "\n", omittingEmptySubsequences: true)
            .suffix(400)
        try? tail.joined(separator: "\n")
            .write(to: url, atomically: true,
                   encoding: .utf8)
    }

    static func recent(_ limit: Int) -> [String] {
        guard let text = try? String(
            contentsOf: DevKit.breadcrumbsURL,
            encoding: .utf8) else { return [] }
        return Array(text.split(
            separator: "\n",
            omittingEmptySubsequences: true)
            .suffix(limit).map(String.init))
    }

    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(
                at: DevKit.breadcrumbsURL)
        }
    }
}

// MARK: - The crash trap (file scope: a signal
// handler must be a plain C function — no
// captures, no context, almost no calls)

/// Where the trap writes: the signal record's
/// path as a C string, prepared at install, and
/// whether recording is armed. The handler
/// reads nothing else from the app.
private var devSignalPath: ContiguousArray<CChar> = []
private var devSignalArmed = false

private func devTrapWrite(
    _ file: UnsafeMutablePointer<FILE>,
    _ text: String) {
    text.withCString { pointer in
        _ = fputs(pointer, file)
    }
}

/// A small number, written digit by digit —
/// the handler formats nothing any other way.
private func devTrapNumber(
    _ file: UnsafeMutablePointer<FILE>,
    _ value: Int) {
    var remaining = value
    var reversed: [CChar] = []
    if remaining == 0 { reversed = [48] }
    while remaining > 0 {
        reversed.append(
            CChar(48 + remaining % 10))
        remaining /= 10
    }
    for digit in reversed.reversed() {
        _ = fputc(Int32(digit), file)
    }
}

private func devSignalTrap(_ sig: Int32) {
    if devSignalArmed, !devSignalPath.isEmpty {
        // stdio, not open(): the POSIX open is
        // variadic in C (its mode argument), and
        // Swift will not call variadic C
        // functions at all. fopen/fputs/fclose
        // are fixed-arity — and the same
        // pragmatic family every crash reporter
        // leans on inside a trap.
        let file = devSignalPath
            .withUnsafeBufferPointer {
                fopen($0.baseAddress, "a")
            }
        if let file {
            devTrapWrite(file, "\n=== NIGHTJAR "
                         + "SIGNAL CRASH ===\n")
            devTrapWrite(file, "epoch: ")
            devTrapNumber(file, Int(time(nil)))
            devTrapWrite(file, "\nsignal: ")
            devTrapNumber(file, Int(sig))
            devTrapWrite(file, "\nstack:\n")
            var frames: [UnsafeMutableRawPointer?] =
                Array(repeating: nil, count: 64)
            let count = backtrace(
                &frames, Int32(frames.count))
            if count > 0, let symbols =
                backtrace_symbols(&frames, count) {
                for index in 0..<Int(count) {
                    if let line = symbols[index] {
                        _ = fputs(line, file)
                        _ = fputs("\n", file)
                    }
                }
                free(symbols)
            }
            fclose(file)
        }
    }
    // The system still gets its own record: the
    // default disposition runs as if we had
    // never stood here.
    signal(sig, SIG_DFL)
    raise(sig)
    _exit(128 + sig)
}

private func devExceptionTrap(
    _ exception: NSException) {
    CrashRecorder.recordException(exception)
}

/// The crash recorder: installs the two traps,
/// keeps the records, and reads them back.
enum CrashRecorder {
    struct Record: Identifiable {
        var id: String { name }
        let name: String
        let date: Date
        let text: String
    }

    private static var installed = false
    private static var memoryToken: NSObjectProtocol?

    static func installIfEnabled() {
        guard DevKit.enabled else { return }
        install()
    }

    static func install() {
        guard !installed else {
            devSignalArmed = true
            return
        }
        installed = true
        let crashes = DevKit.crashesDirectory
        devSignalPath = crashes
            .appendingPathComponent("signal.txt")
            .path.utf8CString
        devSignalArmed = true
        NSSetUncaughtExceptionHandler(
            devExceptionTrap)
        for sig in [SIGABRT, SIGSEGV, SIGBUS,
                    SIGILL, SIGFPE, SIGTRAP] {
            signal(sig, devSignalTrap)
        }
        memoryToken = NotificationCenter.default
            .addObserver(
                forName: UIApplication
                    .didReceiveMemoryWarningNotification,
                object: nil, queue: nil) { _ in
                DevLog.event(
                    "system",
                    "memory warning — footprint "
                        + "\(DevKit.footprintMB()) MB")
                // Answer the pressure: the
                // heaviest resident in the house
                // is set down before the kernel
                // settles the matter itself.
                SkelliBenchRelief.memoryWarning()
            }
        DevLog.event("developer",
                     "crash recorder installed")
    }

    static func setArmed(_ on: Bool) {
        devSignalArmed = on
    }

    static func recordException(
        _ exception: NSException) {
        guard DevKit.enabled else { return }
        var text = "NIGHTJAR CRASH RECORD\n"
        text += "kind: exception\n"
        text += "name: "
            + "\(exception.name.rawValue)\n"
        if let reason = exception.reason {
            text += "reason: \(reason)\n"
        }
        text += headerLines()
        text += "stack:\n"
        text += exception.callStackSymbols
            .joined(separator: "\n") + "\n"
        writeRecord(text)
        DevLog.event("developer",
                     "exception recorded: "
                        + exception.name.rawValue)
    }

    /// A synthetic record, so the read-and-share
    /// loop can be proven without anyone dying.
    static func writeTestRecord() {
        var text = "NIGHTJAR CRASH RECORD\n"
        text += "kind: test (written by hand "
            + "from the developer console — "
            + "nothing crashed)\n"
        text += headerLines()
        text += "stack:\n"
        text += Thread.callStackSymbols
            .joined(separator: "\n") + "\n"
        writeRecord(text)
    }

    private static func headerLines() -> String {
        let formatter = ISO8601DateFormatter()
        let commit = SourceStamp.shortCommit
            ?? "unstamped"
        var text = "when: "
            + formatter.string(from: Date()) + "\n"
        text += "app: \(AppInfo.version) "
            + "· commit \(commit)\n"
        return text
    }

    private static func writeRecord(_ text: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "crash-"
            + formatter.string(from: Date()) + ".txt"
        try? text.write(
            to: DevKit.crashesDirectory
                .appendingPathComponent(name),
            atomically: true, encoding: .utf8)
    }

    static func records() -> [Record] {
        let directory = DevKit.crashesDirectory
        let files = (try? FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
        return files.compactMap { url in
            guard let text = try? String(
                contentsOf: url, encoding: .utf8)
            else { return nil }
            let date = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            return Record(name: url.lastPathComponent,
                          date: date, text: text)
        }
        .sorted { $0.date > $1.date }
    }

    static func clearAll() {
        let directory = DevKit.crashesDirectory
        for url in (try? FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(
                at: url)
        }
        DevLog.clear()
    }
}

// MARK: - The console

struct DeveloperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter
    @State private var records:
        [CrashRecorder.Record] = []
    @State private var crumbs: [String] = []
    @State private var stateText = ""
    @State private var confirmClear = false
    @State private var showGauntletLog = false
    @ObservedObject private var gauntlet =
        Gauntlet.shared

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Recording"))) {
                    LabeledContent(
                        L("Crash records"),
                        value: "\(records.count)")
                    LabeledContent(
                        L("Flight recorder"),
                        value: String(
                            format: L("%lld event(s)"),
                            crumbs.count))
                    LabeledContent(
                        L("Memory footprint"),
                        value: "\(DevKit.footprintMB()) MB")
                }
                Section(header: Text(L("House state"))) {
                    Text(stateText)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                if !records.isEmpty {
                    Section(header: Text(
                        L("Crash records"))) {
                        ForEach(records) { record in
                            NavigationLink {
                                DeveloperRecordView(
                                    record: record)
                            } label: {
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text(record.name)
                                        .font(.subheadline)
                                    Text(record.date,
                                         format: .dateTime)
                                        .font(.caption)
                                        .foregroundStyle(
                                            .secondary)
                                }
                            }
                        }
                    }
                }
                if !crumbs.isEmpty {
                    Section(header: Text(
                        L("Flight recorder"))) {
                        NavigationLink {
                            DeveloperCrumbsView(
                                lines: crumbs)
                        } label: {
                            Text(L("Recent events"))
                        }
                    }
                }
                Section(header: Text(L("Hand it over"))) {
                    ShareLink(
                        item: DevKit.exportFileURL()) {
                        Label(L("Share the full log"),
                              systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Haptics.tap()
                        UIPasteboard.general.string =
                            DevKit.exportText()
                        toasts.show(L("The developer log is copied — paste it anywhere."))
                    } label: {
                        Label(L("Copy the full log"),
                              systemImage: "doc.on.doc")
                    }
                    ShareLink(
                        item: DevKit
                            .chatExportFileURL()) {
                        Label(L("Share all chats"),
                              systemImage: "text.bubble")
                    }
                    Button {
                        Haptics.tap()
                        UIPasteboard.general.string =
                            DevKit.chatTranscriptText()
                        toasts.show(L("Every chat is copied — the archive and the screen."))
                    } label: {
                        Label(L("Copy all chats"),
                              systemImage: "doc.on.doc")
                    }
                }
                Section(header: Text(L("Prove the loop"))) {
                    Button(L("Write a test crash record")) {
                        Haptics.warn()
                        CrashRecorder.writeTestRecord()
                        refresh()
                    }
                    Button(L("Write a test event")) {
                        Haptics.tap()
                        DevLog.event(
                            "developer",
                            "test event from the "
                                + "console")
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + 0.3) {
                            refresh()
                        }
                    }
                }
                Section(header: Text(L("The Gauntlet"))) {
                    Text(L("A full stress run over every system in the house — decoders, crypto, her mind, her stores, the audio paths, the shared tables under parallel hands. The log is written ahead of each step, so if a step ever kills the app, the log names it."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let died = Gauntlet
                        .interruptedStep() {
                        Label(String(format: L("Last run died at: %@"),
                                     died),
                              systemImage:
                                "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if gauntlet.running {
                        ProgressView(
                            value: Double(gauntlet.passed
                                + gauntlet.failed),
                            total: Double(
                                max(gauntlet.total, 1)))
                        LabeledContent(
                            gauntlet.stageName,
                            value: gauntlet.currentStep)
                            .font(.caption)
                        LabeledContent(
                            L("So far"),
                            value: String(
                                format: L("%lld passed · %lld failed"),
                                gauntlet.passed,
                                gauntlet.failed))
                        Button(L("Stop after this step"),
                               role: .destructive) {
                            gauntlet.cancelRequested
                                = true
                        }
                    } else {
                        Button(L("Run the gauntlet")) {
                            Haptics.press()
                            gauntlet.run()
                        }
                        LabeledContent(
                            L("Last run"),
                            value: Gauntlet
                                .lastSummary()
                                .components(
                                    separatedBy: "\n")
                                .first ?? "—")
                        Button(L("Read the latest gauntlet log")) {
                            showGauntletLog = true
                        }
                    }
                }
                Section(header: Text(L("Haptics test"))) {
                    // Each button fires ONLY its
                    // named beat, straight from the
                    // tap — no UI beat of its own —
                    // so what the operator feels (or
                    // does not) maps one-to-one to a
                    // generator and a strength.
                    Button(L("Tap — light impact")) {
                        Haptics.tap()
                    }
                    Button(L("Tick — rigid at 0.3")) {
                        Haptics.tick()
                    }
                    Button(L("Select — rigid at 0.7")) {
                        Haptics.select()
                    }
                    Button(L("Press — medium impact")) {
                        Haptics.press()
                    }
                    Button(L("Heavy — heavy impact")) {
                        Haptics.heavy()
                    }
                    Button(L("Success — notification (raw test)")) {
                        Haptics.testSuccess()
                    }
                    Button(L("Error — notification (raw test)")) {
                        Haptics.testError()
                    }
                    Button(L("Raw selection — retired generator")) {
                        Haptics.rawSelection()
                    }
                }
                Section {
                    Button(L("Clear all developer records"),
                           role: .destructive) {
                        Haptics.warn()
                        confirmClear = true
                    }
                }
            }
            .navigationTitle(L("Developer"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .onAppear { refresh() }
            .sheet(isPresented: $showGauntletLog) {
                GauntletLogView()
            }
            .confirmationDialog(
                L("Clear every crash record and the flight recorder?"),
                isPresented: $confirmClear,
                titleVisibility: .visible) {
                Button(L("Clear all"), role: .destructive) {
                    Haptics.error()
                    CrashRecorder.clearAll()
                    refresh()
                }
                Button(L("Keep them"), role: .cancel) {}
            }
        }
    }

    private func refresh() {
        records = CrashRecorder.records()
        crumbs = DevLog.recent(400)
        stateText = DevKit.houseState()
    }
}

private struct DeveloperRecordView: View {
    let record: CrashRecorder.Record

    var body: some View {
        ScrollView {
            Text(record.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding()
        }
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DeveloperCrumbsView: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding()
        }
        .navigationTitle(L("Flight recorder"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The gauntlet's log, readable in the room and
/// shareable as itself.
private struct GauntletLogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(Gauntlet.latestLogText()
                     ?? L("The gauntlet has never run."))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding()
            }
            .navigationTitle(L("Gauntlet log"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
                ToolbarItem(
                    placement: .cancellationAction) {
                    ShareLink(
                        item: Gauntlet.latestLogURL) {
                        Image(systemName:
                                "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
