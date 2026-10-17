import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var post: ListeningPost
    @State private var tab: Int
    @State private var showBoot = true

    init() {
        // The house reopens where you left it:
        // the last tab worked in is restored on
        // launch, even after a swipe-close, so
        // work continues where it stopped.
        let stored = UserDefaults.standard
            .object(forKey: "house.lastTab") as? Int
        _tab = State(initialValue:
            stored.flatMap {
                (0...9).contains($0) ? $0 : nil
            } ?? 0)
    }
    @ObservedObject private var themes = ThemeCenter.shared

    var body: some View {
        ZStack {
            AppBackdrop()
            TabView(selection: $tab) {
            SkelliView()
                .appThemed(.skelli)
                .tabItem { Label("Skelli",
                                 systemImage: "brain.head.profile") }
                .tag(9)
            ListenView(tab: $tab)
                .appThemed(.listen)
                .tabItem { Label("Listen", systemImage: "dot.radiowaves.left.and.right") }
                .tag(0)
            SendView()
                .appThemed(.send)
                .tabItem { Label("Send", systemImage: "paperplane") }
                .tag(1)
            ServeView()
                .appThemed(.serve)
                .tabItem { Label("Serve", systemImage: "tray.and.arrow.down") }
                .tag(2)
            // Declaration order is the More list's order:
            // About heads it — it is the app's identity and
            // its options hub — and Sessions sits under it.
            // Tags are unchanged by position.
            AboutView()
                .appThemed(.about)
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(5)
            SessionsView()
                .appThemed(.sessions)
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
                .tag(3)
            ScanView(tab: $tab)
                .appThemed(.scan)
                .tabItem { Label("Scan", systemImage: "scope") }
                .tag(4)
            ReconBenchView(tab: $tab)
                .appThemed(.recon)
                .tabItem { Label("Recon", systemImage: "target") }
                .tag(6)
            EmconView()
                .appThemed(.emcon)
                .tabItem { Label("EMCON", systemImage: "shield.slash") }
                .tag(7)
            KnockChatView()
                .appThemed(.knocktalk)
                .tabItem { Label("Knocktalk",
                                 systemImage: "message.badge.waveform") }
                .tag(8)
        }
        .tint(themes.current.accent)
        .onAppear {
            // The specialist gets the house's real
            // organs, so its hands work the real
            // controls.
            SkelliCenter.shared.wire(mouth: mouth,
                                     emcon: emcon,
                                     post: post)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .houseNavigate)) { note in
            if let target = note.userInfo?["tab"] as? Int {
                tab = target
            }
        }
        .onChange(of: tab) { newTab in
            Haptics.select()
            UserDefaults.standard.set(
                newTab, forKey: "house.lastTab")
        }
        .onChange(of: mouth.reconHandoff) { handoff in
            // Counter-knock pivot: a tripwire row tapped in EMCON
            // lands the operator on the Recon bench, pre-aimed.
            if handoff != nil { tab = 6 }
        }
        .overlay(alignment: .top) {
            if let toast = toasts.current {
                ToastView(toast: toast)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
            if showBoot {
                BootView {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showBoot = false
                    }
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Listen

struct ListenView: View {
    @Binding var tab: Int
    @EnvironmentObject private var post: ListeningPost
#if !STORE_BUILD
    @EnvironmentObject private var updater: UpdateChecker
#endif
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @State private var label = ""
    @State private var huntRow: DeviceRow?
    @State private var now = Date().timeIntervalSince1970

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
#if !STORE_BUILD
                if let release = updater.visibleUpdate {
                    Section {
                        UpdateBanner(release: release)
                    }
                }
#endif
                Section {
                    statusRow
                    if let session = post.session {
                        runningRows(session)
                    } else {
                        idleRows
                    }
                }
                Section {
                    NavigationLink {
                        SigintStationView()
                    } label: {
                        Label("SIGINT Station — the fused "
                            + "picture",
                              systemImage:
                                "antenna.radiowaves.left.and.right")
                    }
                    Text("Everything this phone can hear — "
                        + "the air, the wire, the Night log — "
                        + "in one registry, one timeline, "
                        + "recorded watches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if post.isListening || !post.rows.isEmpty {
                    Section(header: Text(post.isListening ? "In earshot" : "Last session")) {
                        if post.rows.isEmpty {
                            Text("Listening… nothing heard yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(post.rows) { row in
                            NavigationLink {
                                DeviceDetailView(row: row, tab: $tab)
                            } label: {
                                DeviceRowView(row: row, now: now)
                            }
                                .contextMenu {
                                    Button {
                                        if let id = UUID(uuidString: row.id) {
                                            let name = row.preferredLabel
                                                ?? row.kind
                                            mouth.requestWrite(to: id,
                                                               label: name)
                                            Haptics.select()
                                            toasts.show("Write target set: "
                                                + "\(name) — Send tab")
                                            tab = 1
                                        }
                                    } label: {
                                        Label("Write a payload…",
                                              systemImage: "paperplane")
                                    }
                                    Button {
                                        huntRow = row
                                    } label: {
                                        Label("Hunt this signal",
                                              systemImage: "location.viewfinder")
                                    }
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("nightjar-hack")
            .onReceive(clock) { _ in now = Date().timeIntervalSince1970 }
            .sheet(item: $huntRow) { row in
                HuntView(targetID: row.id)
                    .environmentObject(post)
            }
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            Image(systemName: bluetoothSymbol)
                .foregroundStyle(post.bluetoothState == .poweredOn ? Color.green : Color.orange)
            Text(bluetoothText)
            Spacer()
            if post.inBackground {
                Text("background").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let error = post.lastError {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var idleRows: some View {
        TextField("Place label (optional, e.g. home)", text: $label)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
        Button {
            Haptics.tap()
            post.start(label: label)
        } label: {
            Label("Start listening", systemImage: "play.circle.fill")
        }
        .disabled(post.bluetoothState != .poweredOn)
    }

    @ViewBuilder private func runningRows(_ session: ListeningPost.ActiveSession) -> some View {
        HStack {
            Text(session.label.map { "@ \($0)" } ?? "unlabelled session")
            Spacer()
            Text(elapsed(since: session.startedAt))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        HStack {
            Text("\(post.deviceCount) addresses · \(post.sightingCount) sightings")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        Button(role: .destructive) {
            Haptics.tap()
            post.stop()
        } label: {
            Label("Stop and save", systemImage: "stop.circle.fill")
        }
    }

    private var bluetoothSymbol: String {
        switch post.bluetoothState {
        case .poweredOn: return "antenna.radiowaves.left.and.right"
        case .unauthorized: return "lock.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var bluetoothText: String {
        switch post.bluetoothState {
        case .poweredOn: return post.isListening ? "Listening — receive-only" : "Bluetooth ready"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied (Settings › nightjar)"
        case .unsupported: return "Bluetooth LE unsupported"
        case .resetting: return "Bluetooth resetting…"
        default: return "Waiting for Bluetooth…"
        }
    }

    private func elapsed(since start: TimeInterval) -> String {
        let seconds = Int(max(0, now - start))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

#if !STORE_BUILD
struct UpdateBanner: View {
    let release: UpdateChecker.Release
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var updater: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Update available — \(release.name)", systemImage: "arrow.down.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Button {
                    updater.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Not now")
            }
            if let install = release.installURL {
                Text("This release carries an over-the-air build. "
                     + "iOS installs it over this one — your logs, "
                     + "notes and settings stay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    openURL(install)
                } label: {
                    Label("Update now",
                          systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.semibold))
                }
                .padding(.top, 2)
            } else {
                Text("A newer nightjar is out. This release has no "
                     + "over-the-air build, so it installs the Xcode "
                     + "way — open the project and press Run. "
                     + "Your logs are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(destination: release.url) {
                    Label("View release", systemImage: "arrow.up.right.square")
                        .font(.callout)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}
#endif

struct DeviceRowView: View {
    let row: DeviceRow
    let now: TimeInterval

    private var quiet: Bool { return row.age(now: now) > 20 }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if row.trackerShaped {
                    Image(systemName: "tag.fill").font(.caption).foregroundStyle(.orange)
                }
                if row.flare {
                    Image(systemName: "flame.fill")
                        .font(.caption).foregroundStyle(.yellow)
                        .accessibilityLabel(
                            "Flare: a paired operator is near")
                }
                Spacer()
                Text(row.rssiLast.map { "\($0) dBm" } ?? "? dBm")
                    .font(.callout.monospacedDigit())
                Text(row.trendArrow).font(.callout)
            }
            HStack {
                Text(subtitle)
                    .lineLimit(1)
                Spacer()
                Text(age)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let detail = row.details.first {
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(metaLine).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            Text(row.id).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
        .opacity(quiet ? 0.45 : 1)
    }

    private var age: String {
        let seconds = Int(row.age(now: now))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h \(seconds / 60 % 60)m ago"
    }

    /// Kind (when there is a name to headline instead) · the
    /// perimeter band · the rough range, when it can be read.
    private var subtitle: String {
        var parts: [String] = []
        if row.name != nil { parts.append(row.kind) }
        parts.append(row.rangeBand)
        if let d = row.distanceMeters {
            parts.append(d < 10
                ? String(format: "≈%.1f m", d)
                : String(format: "≈%.0f m", d))
        }
        return parts.joined(separator: " · ")
    }

    /// The quiet facts: how often it has spoken, the closest
    /// it ever came, and whether its address rotates.
    private var metaLine: String {
        var parts = ["×\(row.sightings) heard"]
        if let closest = row.rssiClosest {
            parts.append("closest \(closest) dBm")
        }
        if row.rotatingAddress { parts.append("rotating address") }
        return parts.joined(separator: " · ")
    }
}

/// Everything the post knows about one device, on one page —
/// the row is the headline, this is the file. Reads the live
/// row from the post each render, so the numbers keep moving
/// while you watch.
struct DeviceDetailView: View {
    let row: DeviceRow
    @Binding var tab: Int
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @State private var now = Date().timeIntervalSince1970
    @State private var hunting = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: DeviceRow {
        post.rows.first { $0.id == row.id } ?? row
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(live.label).font(.title3.weight(.semibold))
                    Text(live.kind).foregroundStyle(.secondary)
                    if live.trackerShaped {
                        Label("Tracker-shaped — separated Find My broadcasts",
                              systemImage: "tag.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if live.rotatingAddress {
                        Label("Rotating address — a phone-style private address",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Heard as") {
                if live.details.isEmpty {
                    Text("No decoded details — the broadcast carried "
                         + "nothing the decoders read.")
                        .foregroundStyle(.secondary)
                }
                ForEach(live.details, id: \.self) { detail in
                    Text(detail).font(.callout)
                }
                if !live.makers.isEmpty {
                    LabeledContent("Maker",
                                   value: live.makers.sorted()
                                       .joined(separator: ", "))
                }
            }
            Section("Signal") {
                LabeledContent("Last",
                               value: live.rssiLast.map { "\($0) dBm" } ?? "—")
                LabeledContent("Smoothed",
                               value: live.rssiSmooth.map {
                                   String(format: "%.0f dBm", $0) } ?? "—")
                LabeledContent("Closest ever",
                               value: live.rssiClosest.map { "\($0) dBm" } ?? "—")
                LabeledContent("TX power",
                               value: live.txPowerLast.map { "\($0) dBm" }
                                   ?? "not advertised")
                LabeledContent("Estimated range", value: rangeText)
                LabeledContent("Trend", value: live.trend ?? "—")
                Button {
                    hunting = true
                } label: {
                    Label("Hunt this signal",
                          systemImage: "location.viewfinder")
                }
                sparkline
            }
            Section("Timing") {
                LabeledContent("First heard",
                               value: clockTime(live.firstSeen))
                LabeledContent("Last heard",
                               value: clockTime(live.lastSeen))
                LabeledContent("Age", value: ageText)
                LabeledContent("Dwell", value: durationText(live.dwell))
                LabeledContent("Sightings", value: "\(live.sightings)")
                if live.sightingsPerMinute > 0 {
                    LabeledContent("Rate",
                                   value: String(format: "%.1f / min",
                                                 live.sightingsPerMinute))
                }
            }
            if !live.serviceUUIDs.isEmpty {
                Section("Services advertised") {
                    ForEach(live.serviceUUIDs, id: \.self) { uuid in
                        Text(shortUUID(uuid))
                            .font(.caption.monospaced())
                    }
                }
            }
            Section("Identifier") {
                Text(live.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("iOS shows a per-host UUID, never the MAC. "
                     + "A rotating-address device returns under a "
                     + "new one when its address rolls.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    if let id = UUID(uuidString: live.id) {
                        let name = live.preferredLabel ?? live.kind
                        mouth.requestWrite(to: id, label: name)
                        Haptics.select()
                        toasts.show("Write target set: \(name) — Send tab")
                        tab = 1
                    }
                } label: {
                    Label("Write a payload…", systemImage: "paperplane")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $hunting) {
            HuntView(targetID: row.id)
                .environmentObject(post)
        }
        .onReceive(clock) { _ in now = Date().timeIntervalSince1970 }
    }

    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("RSSI history — last \(live.rssiHistory.count) sightings")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(live.rssiHistory.enumerated()),
                        id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 6,
                               height: max(2, CGFloat(value + 100)
                                            / 60 * 32))
                }
            }
            .frame(height: 34, alignment: .bottom)
        }
        .padding(.vertical, 2)
    }

    private var rangeText: String {
        guard let d = live.distanceMeters else { return "—" }
        let text = d < 10
            ? String(format: "≈%.1f m", d)
            : String(format: "≈%.0f m", d)
        return "\(text) (\(live.rangeBand))"
    }

    private var ageText: String {
        let seconds = Int(live.age(now: now))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h \(seconds / 60 % 60)m ago"
    }

    private func clockTime(_ t: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: Date(timeIntervalSince1970: t))
    }

    private func durationText(_ d: TimeInterval) -> String {
        let s = Int(d)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s / 60 % 60)m"
    }

    /// SIG 128-bit UUIDs spell as their short 0xXXXX form.
    private func shortUUID(_ uuid: String) -> String {
        if uuid.count == 36, uuid.hasPrefix("0000"),
           uuid.hasSuffix(sigBaseSuffix) {
            return "0x" + String(uuid.dropFirst(4).prefix(4))
                .uppercased()
        }
        return uuid
    }
}

// MARK: - Sessions

struct SessionsView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.editMode) private var editMode
    @State private var sessions: [SessionSummary] = []
    @State private var selection = Set<String>()
    @State private var showClearConfirm = false
    @State private var shareItem: ShareItem?
    @State private var showNightLog = false

    private var deletable: [SessionSummary] {
        sessions.filter { $0.id != post.session?.id }
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(sessions.reduce(0) { $0 + $1.fileSize }),
            countStyle: .file)
    }

    private var deletableSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(deletable.reduce(0) { $0 + $1.fileSize }),
            countStyle: .file)
    }

    private var selectedDeletableCount: Int {
        deletable.filter { selection.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    Button {
                        showNightLog = true
                    } label: {
                        Label("Night log — the whole instrument, one timeline",
                              systemImage: "list.bullet.rectangle")
                    }
                    .foregroundStyle(.primary)
                }
                if sessions.isEmpty {
                    Text("No sessions yet. Start one on the Listen tab; each session becomes "
                         + "a .jsonl file you can share to the Mac and feed to "
                         + "`nightjar report` and `nightjar trackers`.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    SessionRowView(
                        session: session,
                        isLive: post.session?.id == session.id,
                        onDelete: deleteAction(for: session),
                        onShare: { url in
                            shareItem = ShareItem(items: [url])
                        })
                    .tag(session.id)
                }
                .onDelete { offsets in
                    for index in offsets where post.session?.id != sessions[index].id {
                        SessionStore.delete(sessions[index])
                    }
                    reload()
                }
                if !deletable.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            Haptics.tap()
                            showClearConfirm = true
                        } label: {
                            Label("Delete all sessions",
                                  systemImage: "trash")
                        }
                    } footer: {
                        Text("\(sessions.count) session"
                             + "\(sessions.count == 1 ? "" : "s") · "
                             + "\(totalSizeText) on this phone. Swipe "
                             + "a row, long-press it, or use Edit to "
                             + "pick several. The session recording "
                             + "right now is never deleted.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                }
                if editMode?.wrappedValue.isEditing == true,
                   selectedDeletableCount > 0 {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete selected (\(selectedDeletableCount))",
                               role: .destructive) {
                            deleteSelected()
                        }
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .confirmationDialog(
                "Delete all sessions?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible) {
                Button("Delete \(deletable.count) sessions "
                       + "(\(deletableSizeText))",
                       role: .destructive) {
                    deleteAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(post.session != nil
                     ? "The session recording right now is kept. "
                       + "This cannot be undone."
                     : "Every recorded session file is deleted. "
                       + "This cannot be undone.")
            }
            .onAppear(perform: reload)
            .onChange(of: post.session?.id) { _ in reload() }
            .sheet(isPresented: $showNightLog) {
                NavigationStack {
                    NightLogView()
                        .toolbar {
                            ToolbarItem(
                                placement:
                                    .confirmationAction) {
                                Button("Done") {
                                    showNightLog = false
                                }
                            }
                        }
                }
                .environment(\.backdropSlot, .sessions)
            }
        }
    }

    private func reload() {
        sessions = SessionStore.list()
    }

    /// The row's long-press delete: nothing for the session
    /// still recording, a real closure for everything else.
    /// (A named method, not an inline ternary in the body —
    /// the type checker timed out on that expression.)
    private func deleteAction(for session: SessionSummary)
        -> (() -> Void)?
    {
        if post.session?.id == session.id { return nil }
        return { deleteOne(session) }
    }

    private func deleteOne(_ session: SessionSummary) {
        let removed = SessionStore.delete(session)
        selection.remove(session.id)
        reload()
        if removed {
            toasts.show("Session deleted")
        } else {
            toasts.show("Could not delete session", error: true)
        }
    }

    private func deleteSelected() {
        var gone = 0
        for session in deletable where selection.contains(session.id) {
            SessionStore.delete(session)
            gone += 1
        }
        selection = []
        reload()
        toasts.show("Deleted \(gone) session"
                    + "\(gone == 1 ? "" : "s")")
    }

    private func deleteAll() {
        let gone = SessionStore.deleteAll(exceptLiveID: post.session?.id)
        selection = []
        reload()
        toasts.show("Deleted \(gone) session"
                    + "\(gone == 1 ? "" : "s")")
    }
}

struct SessionRowView: View {
    let session: SessionSummary
    let isLive: Bool
    var onDelete: (() -> Void)? = nil
    var onShare: ((URL) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.label ?? "unlabelled")
                        .font(.body.weight(.medium))
                    if isLive {
                        Text("recording").font(.caption).foregroundStyle(.red)
                    } else if session.isUnfinished {
                        Text("unfinished").font(.caption).foregroundStyle(.orange)
                    }
                }
                Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: session.startedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(session.url.lastPathComponent)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if !isLive, let onShare {
                Button {
                    onShare(session.url)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
            }
        }
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    Haptics.tap()
                    onDelete()
                } label: {
                    Label("Delete session", systemImage: "trash")
                }
            }
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let duration = session.duration {
            let minutes = Int(duration / 60)
            parts.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        if let count = session.sightings {
            parts.append("\(count) sightings")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(session.fileSize),
                                               countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - About

struct AboutView: View {
#if !STORE_BUILD
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var updater: UpdateChecker
    @State private var showSupport = false
#endif
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("postName") private var postName = "phone"
    @State private var confirmReset = false
    @State private var showColours = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("The unpure build")) {
                    Text("This is nightjar-hack: the listening post from nightjar, "
                         + "plus a mouth. The Listen tab is the purist half — it scans "
                         + "and logs advertisements and never connects, pairs or sends, "
                         + "exactly like the upstream app. The Send and Serve tabs are "
                         + "the hack half: they transmit, but only when you press their "
                         + "buttons, to targets you type. The two halves share no radio "
                         + "state; the ear stays pure, the mouth is a different organ.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Send and Serve work while the app is on screen. iOS does not "
                         + "let a sideloaded app hold listeners or advertisements open "
                         + "in the background, so a beacon or server stops being "
                         + "reachable when you leave the app — the Listen tab keeps "
                         + "its background hearing, the mouth does not.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(header: Text("Version")) {
                    Text("nightjar-hack for iOS \(AppInfo.version) · log format 1")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/chasebryan/nightjar-hack/blob/main/PRIVACY.md")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
#if !STORE_BUILD
                    if let release = updater.available {
                        if let install = release.installURL {
                            Button {
                                openURL(install)
                            } label: {
                                Label("Update to \(release.name) — install now",
                                      systemImage: "arrow.down.circle.fill")
                            }
                        } else {
                            Link(destination: release.url) {
                                Label("Update available — \(release.name)",
                                      systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                    Button {
                        Task { await updater.check() }
                    } label: {
                        HStack {
                            Text("Check for updates")
                            Spacer()
                            if updater.checking {
                                ProgressView()
                            } else if updater.noReleasesYet {
                                Text("no releases published yet")
                                    .foregroundStyle(.secondary)
                            } else if updater.available == nil, updater.lastChecked != nil {
                                Text("up to date").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(updater.checking)
#endif
                }
#if !STORE_BUILD
                Section(header: Text("Support the work")) {
                    Button {
                        showSupport = true
                    } label: {
                        HStack {
                            Label {
                                Text("Buy me a coffee")
                            } icon: {
                                Image(systemName: "cup.and.saucer.fill")
                                    .foregroundStyle(Color(red: 0.85, green: 0.58, blue: 0.30))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("Free and open source, always. If you'd "
                         + "like to help cover the costs, there's "
                         + "a quiet door here — no pressure at all.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif
                Section(header: Text("Colours")) {
                    Button {
                        showColours = true
                    } label: {
                        HStack {
                            Label("Themes & backdrops",
                                  systemImage: "paintpalette")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("Six themes ship with the app and "
                         + "you can tailor your own; every tab "
                         + "may wear its own backdrop — the "
                         + "living wallpaper, the Jolly Roger, "
                         + "the plain theme colour, or your own "
                         + "image or GIF.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(header: Text("Backdrop")) {
                    if let reel = Wallpaper.image {
                        Text("Living wallpaper: playing "
                             + "(\(Int(reel.size.width))×"
                             + "\(Int(reel.size.height)) pt) — it "
                             + "loops behind every tab, beginning "
                             + "to end, forever.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if UIImage(named: "AppBackground") != nil {
                        Text("The living wallpaper has not landed "
                             + "in this build — the retired Jolly "
                             + "Roger stands in behind every tab "
                             + "until wallpaper.gif joins the "
                             + "bundle.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("No backdrop in this build. The app "
                             + "looks for wallpaper.gif in the "
                             + "bundle (or a \"Wallpaper\" data "
                             + "asset) — and wears plain black "
                             + "until it finds one.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(header: Text("Authorized use")) {
                    Text("nightjar-hack is a testing instrument for "
                         + "devices and networks you own, or that "
                         + "you are engaged in writing to test. Aim "
                         + "everything it sends, scans, plants, or "
                         + "records only at targets you are "
                         + "authorized for. You are responsible for "
                         + "your authorization; the author is not "
                         + "responsible for misuse against devices "
                         + "or networks you were not authorized to "
                         + "test.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(header: Text("This post"),
                        footer: Text("The name of this ear, written into every session. "
                                     + "The Mac's fusion uses it to tell your phone apart "
                                     + "from your other posts — give each one its own name.")) {
                    HStack {
                        Text("Post name")
                        Spacer()
                        TextField("phone", text: $postName)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(header: Text("Listening")) {
                    Toggle("Keep the screen awake while listening", isOn: $keepScreenAwake)
                    Text("Foreground sessions hear everything. In the background iOS only "
                         + "delivers advertisements from a fixed list of services, so a "
                         + "backgrounded session keeps hearing tracker tags (Tile, "
                         + "SmartThings, Find My Device network, Fast Pair) but not "
                         + "phones, AirTags or anything else that broadcasts only "
                         + "manufacturer data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(header: Text("Defaults"),
                        footer: Text("Payloads, presets, sessions and logs are data, not settings — a reset never touches them.")) {
                    Text("Every setting in this app has a sane default — the safe, legible choice — and the app runs on those defaults until you configure otherwise.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text("Reset all settings to sane defaults")
                    }
                }
                Section(header: Text("Getting logs to the Mac")) {
                    Text("Each session is a JSON Lines file in Files › On My iPhone › "
                         + "nightjar › sessions, and shareable from the Sessions tab. On "
                         + "the Mac: nightjar report <file> and nightjar trackers <file>.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("About")
            .sheet(isPresented: $showColours) {
                NavigationStack {
                    ColoursView()
                        .toolbar {
                            ToolbarItem(
                                placement: .confirmationAction) {
                                Button("Done") {
                                    showColours = false
                                }
                            }
                        }
                }
            }
#if !STORE_BUILD
            .sheet(isPresented: $showSupport) {
                NavigationStack {
                    SupportView()
                        .toolbar {
                            ToolbarItem(
                                placement: .confirmationAction) {
                                Button("Done") {
                                    showSupport = false
                                }
                            }
                        }
                }
            }
#endif
            .confirmationDialog("Reset all settings?",
                                isPresented: $confirmReset) {
                Button("Reset to sane defaults", role: .destructive) {
                    SaneDefaults.reset(mouth: mouth)
                    toasts.show("Settings reset — sane defaults restored")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every setting returns to its sane default. EMCON stands down, the GATT host disarms, and stealth turns off. Payloads, presets, sessions and logs are not touched.")
            }
        }
    }
}

#if !STORE_BUILD
// MARK: - Support

/// The quiet door. A warm little room of its own — coffee colours,
/// apart from every theme in the house — that asks for nothing and
/// means it: the app is free either way, and this screen exists only
/// so an operator who wants to chip in can find the way. It links
/// out to Buy Me a Coffee; the app itself never touches a payment.
struct SupportView: View {
    private let cream = Color(red: 0.96, green: 0.91, blue: 0.83)
    private let tan = Color(red: 0.76, green: 0.65, blue: 0.52)
    private let amber = Color(red: 0.85, green: 0.58, blue: 0.30)
    private let espresso = Color(red: 0.10, green: 0.06, blue: 0.03)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.10, blue: 0.06),
                         Color(red: 0.05, green: 0.03, blue: 0.02)],
                startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(amber.opacity(0.16))
                            .frame(width: 118, height: 118)
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(amber)
                    }
                    .padding(.top, 36)

                    Text("Support the work")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(cream)

                    VStack(spacing: 14) {
                        Text("nightjar-hack is free, and it stays "
                             + "free either way — every tool in it "
                             + "is already yours. There are no "
                             + "paywalls here, and there never "
                             + "will be.")
                        Text("If it has earned its keep on your "
                             + "phone and you'd like to chip in, a "
                             + "coffee helps cover the developer "
                             + "fee and the test gear it takes to "
                             + "build this. And if not — that's "
                             + "cool too. Truly.")
                        Text("— Chase")
                            .foregroundStyle(amber)
                    }
                    .font(.body)
                    .foregroundStyle(tan)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                    Link(destination: URL(string: "https://buymeacoffee.com/realTechnique")!) {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill")
                            Text("Buy me a coffee")
                        }
                        .font(.headline)
                        .foregroundStyle(espresso)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(amber, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 6)

                    Text("Opens Buy Me a Coffee in your browser — "
                         + "the app never sees or touches your "
                         + "payment details.")
                        .font(.footnote)
                        .foregroundStyle(tan.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.bottom, 28)
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
#endif

#Preview {
    ContentView()
        .environmentObject(ListeningPost())
#if !STORE_BUILD
        .environmentObject(UpdateChecker())
#endif
        .environmentObject(Mouth())
        .environmentObject(ToastCenter())
}
