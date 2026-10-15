import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var toasts: ToastCenter
    @State private var tab = 0
    @State private var showBoot = true

    var body: some View {
        ZStack {
            AppBackdrop()
            TabView(selection: $tab) {
            ListenView(tab: $tab)
                .appThemed()
                .tabItem { Label("Listen", systemImage: "dot.radiowaves.left.and.right") }
                .tag(0)
            SendView()
                .appThemed()
                .tabItem { Label("Send", systemImage: "paperplane") }
                .tag(1)
            ServeView()
                .appThemed()
                .tabItem { Label("Serve", systemImage: "tray.and.arrow.down") }
                .tag(2)
            SessionsView()
                .appThemed()
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
                .tag(3)
            ScanView(tab: $tab)
                .appThemed()
                .tabItem { Label("Scan", systemImage: "scope") }
                .tag(4)
            AboutView()
                .appThemed()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(5)
        }
        .onChange(of: tab) { _ in Haptics.select() }
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
    @EnvironmentObject private var updater: UpdateChecker
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @State private var label = ""
    @State private var now = Date().timeIntervalSince1970

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                if let release = updater.available {
                    Section {
                        UpdateBanner(release: release)
                    }
                }
                Section {
                    statusRow
                    if let session = post.session {
                        runningRows(session)
                    } else {
                        idleRows
                    }
                }
                if post.isListening || !post.rows.isEmpty {
                    Section(header: Text(post.isListening ? "In earshot" : "Last session")) {
                        if post.rows.isEmpty {
                            Text("Listening… nothing heard yet.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(post.rows) { row in
                            DeviceRowView(row: row, now: now)
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
                                }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("nightjar-hack")
            .onReceive(clock) { _ in now = Date().timeIntervalSince1970 }
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

struct UpdateBanner: View {
    let release: UpdateChecker.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Update available — \(release.name)", systemImage: "arrow.down.circle.fill")
                .font(.body.weight(.medium))
                .foregroundStyle(.tint)
            Text("A newer nightjar is out. A sideloaded app can't update "
                 + "itself — open the project in Xcode and press Run to rebuild. "
                 + "Your logs are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(destination: release.url) {
                Label("View release", systemImage: "arrow.up.right.square")
                    .font(.callout)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}

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
                Spacer()
                Text(row.rssiLast.map { "\($0) dBm" } ?? "? dBm")
                    .font(.callout.monospacedDigit())
                Text(row.trendArrow).font(.callout)
            }
            HStack {
                Text(row.name == nil ? row.rangeBand : "\(row.kind) · \(row.rangeBand)")
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
}

// MARK: - Sessions

struct SessionsView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.editMode) private var editMode
    @State private var sessions: [SessionSummary] = []
    @State private var selection = Set<String>()
    @State private var showClearConfirm = false

    private var deletable: [SessionSummary] {
        sessions.filter { $0.id != post.session?.id }
    }

    private var totalSizeText: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(sessions.reduce(0) { $0 + $1.fileSize }),
            countStyle: .file)
    }

    private var selectedDeletableCount: Int {
        deletable.filter { selection.contains($0.id) }.count
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
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
                        onDelete: deleteAction(for: session))
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
            .confirmationDialog(
                "Delete all sessions?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible) {
                Button("Delete \(deletable.count) sessions "
                       + "(\(totalSizeText))",
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
        SessionStore.delete(session)
        selection.remove(session.id)
        reload()
        toasts.show("Session deleted")
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
            if !isLive {
                ShareLink(item: session.url,
                          preview: SharePreview(session.url.lastPathComponent)) {
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
    @EnvironmentObject private var updater: UpdateChecker
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("postName") private var postName = "phone"

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Backdrop")) {
                    if let flag = UIImage(named: "AppBackground") {
                        Text("Jolly Roger: loaded "
                             + "(\(Int(flag.size.width))×"
                             + "\(Int(flag.size.height)) pt) — it flies "
                             + "behind every tab.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Jolly Roger: NOT FOUND in this build. The "
                             + "app looks for an image set named exactly "
                             + "AppBackground in this project's "
                             + "Assets.xcassets, with the picture in "
                             + "its 1x slot.")
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
                Section(header: Text("Getting logs to the Mac")) {
                    Text("Each session is a JSON Lines file in Files › On My iPhone › "
                         + "nightjar › sessions, and shareable from the Sessions tab. On "
                         + "the Mac: nightjar report <file> and nightjar trackers <file>.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(header: Text("Version")) {
                    Text("nightjar-hack for iOS \(AppInfo.version) · log format 1")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let release = updater.available {
                        Link(destination: release.url) {
                            Label("Update available — \(release.name)",
                                  systemImage: "arrow.up.right.square")
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
                            } else if updater.available == nil, updater.lastChecked != nil {
                                Text("up to date").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(updater.checking)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("About")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ListeningPost())
        .environmentObject(UpdateChecker())
        .environmentObject(Mouth())
}
