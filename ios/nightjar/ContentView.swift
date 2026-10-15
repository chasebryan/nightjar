import Combine
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ListenView()
                .tabItem { Label("Listen", systemImage: "dot.radiowaves.left.and.right") }
            SessionsView()
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

// MARK: - Listen

struct ListenView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var updater: UpdateChecker
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
                        }
                    }
                }
            }
            .navigationTitle("nightjar")
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
    @State private var sessions: [SessionSummary] = []

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    Text("No sessions yet. Start one on the Listen tab; each session becomes "
                         + "a .jsonl file you can share to the Mac and feed to "
                         + "`nightjar report` and `nightjar trackers`.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    SessionRowView(session: session, isLive: post.session?.id == session.id)
                }
                .onDelete { offsets in
                    for index in offsets where post.session?.id != sessions[index].id {
                        SessionStore.delete(sessions[index])
                    }
                    reload()
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: post.session?.id) { _ in reload() }
        }
    }

    private func reload() {
        sessions = SessionStore.list()
    }
}

struct SessionRowView: View {
    let session: SessionSummary
    let isLive: Bool

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
                Section(header: Text("Receive-only")) {
                    Text("nightjar scans and logs advertisements — signals devices send "
                         + "to everyone, on purpose. It never connects, pairs or sends "
                         + "data. Run it in spaces where you have a right to listen.")
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
                    Text("nightjar for iOS \(AppInfo.version) · log format 1")
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
            .navigationTitle("About")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ListeningPost())
        .environmentObject(UpdateChecker())
}
