import SwiftUI
import UniformTypeIdentifiers

// BetafischView — the dissector's room.
// A sheet of its own with its own
// NavigationStack (the house doctrine:
// detail pushes live inside the sheet,
// never inside the tab's stack). The
// capture list, the display filter, the
// dissection tree and the hex below it.
// Nothing is read from disk in a view
// body or a computed property: files
// load in the importer handler, the
// seed in onAppear, the sample in its
// button.

struct BetafischView: View {
    var seedName: String? = nil
    var seedData: Data? = nil
    /// Driftnet's seed: when set, the
    /// room opens already walking to the
    /// gallery — the seeded capture (or
    /// the sample, when the seed says
    /// so) is loaded and its pictures
    /// lifted without another touch.
    var seedDrift: Bool = false
    var seedDriftSample: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var capture: BFCapture?
    @State private var errorLine: String?
    @State private var filterText = ""
    @State private var appliedFilter:
        Betafisch.FilterExpr?
    @State private var filterError: String?
    @State private var showImporter = false
    @State private var didSeed = false
    @State private var path: [DriftRoute] = []
    @State private var driftObjects: [DriftObject] = []
    @State private var driftStats: DriftStats?
    @State private var driftRunning = false
    /// The opened capture's own bytes,
    /// kept so the export door can hand
    /// them back unchanged.
    @State private var sourceData: Data?
    @State private var shareItem: ShareItem?
    @State private var exportNote: String?
    /// The house-wire tap's standing,
    /// refreshed when the room appears
    /// and after every touch of it.
    @State private var tapOn = false
    @State private var tapFrames = 0
    @State private var tapBytes = 0
    @State private var tapCapped = false
    @State private var tapNote: String?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                controls
                Divider()
                content
            }
            .navigationTitle(L("BETAFISCH"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(
                for: DriftRoute.self) { route in
                switch route {
                case .gallery:
                    DriftGalleryView(
                        objects: driftObjects,
                        stats: driftStats)
                }
            }
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button(L("Done")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
        }
        .onAppear {
            refreshTap()
            guard !didSeed else { return }
            didSeed = true
            if let seedData {
                load(data: seedData,
                     name: seedName
                         ?? L("a capture"))
            }
            if seedDrift {
                if capture == nil, seedDriftSample {
                    capture = Betafisch.sampleCapture()
                    errorLine = nil
                    resetFilter()
                }
                if capture != nil {
                    runDrift()
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: BetafischView
                .captureTypes
        ) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource()
            else { return }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            guard let data = try? Data(contentsOf: url)
            else {
                errorLine = L("that file could not be read.")
                return
            }
            load(data: data,
                 name: url.lastPathComponent)
        }
    }

    static var captureTypes: [UTType] {
        var types: [UTType] = []
        if let pcap = UTType(filenameExtension: "pcap") {
            types.append(pcap)
        }
        if let pcapng = UTType(
            filenameExtension: "pcapng") {
            types.append(pcapng)
        }
        types.append(.data)
        return types
    }

    // MARK: The head of the room

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showImporter = true
                } label: {
                    Label(L("open a capture"),
                          systemImage: "folder")
                }
                Button {
                    capture = Betafisch.sampleCapture()
                    sourceData = nil
                    exportNote = nil
                    errorLine = nil
                    resetFilter()
                    resetDrift()
                } label: {
                    Label(L("the sample"),
                          systemImage: "play.rectangle")
                }
                Button {
                    runDrift()
                } label: {
                    Label(L("driftnet"),
                          systemImage:
                            "photo.on.rectangle.angled")
                }
                .disabled(capture == nil || driftRunning)
            }
            .font(.system(.caption, design: .monospaced))
            if driftRunning {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("lifting the pictures…"))
                        .font(.system(.caption,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            if let capture {
                Text(String(format: L("%@ — %lld frames, %@"),
                            capture.name,
                            capture.frames.count,
                            capture.format))
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    NavigationLink {
                        BFStreamsView(
                            capture: capture)
                    } label: {
                        Label(L("streams"),
                              systemImage:
                                "arrow.left.arrow.right")
                    }
                    NavigationLink {
                        BFStatsView(
                            capture: capture)
                    } label: {
                        Label(L("statistics"),
                              systemImage:
                                "chart.bar")
                    }
                    Menu {
                        Button(L("share it as it came")) {
                            exportOriginal()
                        }
                        Button(L("share as .pcapng")) {
                            exportPCAPNG()
                        }
                        Button(L("share as .pcap (classic)")) {
                            exportPCAP()
                        }
                    } label: {
                        Label(L("export"),
                              systemImage:
                                "square.and.arrow.up")
                    }
                }
                .font(.system(.caption,
                              design: .monospaced))
            }
            if let exportNote {
                Text(exportNote)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            tapSection
            if let errorLine {
                Text(errorLine)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField(L("display filter — tcp, ip.addr == 192.168.1.1, len > 100"),
                          text: $filterText)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { applyFilter() }
                Button(L("apply")) { applyFilter() }
                if appliedFilter != nil
                    || filterError != nil {
                    Button(L("clear")) {
                        filterText = ""
                        resetFilter()
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            if let filterError {
                Text(filterError)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.red)
            } else if appliedFilter != nil,
                      let capture {
                Text(String(format: L("showing %lld of %lld frames"),
                            visibleFrames.count,
                            capture.frames.count))
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    // MARK: The house-wire tap

    /// The tap's corner of the room: its
    /// standing, its switch, and the
    /// doors to what it has recorded.
    /// The coverage note stands here in
    /// full — what the tap cannot see is
    /// said where the switch is.
    private var tapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label(L("the house-wire tap"),
                      systemImage: "waveform.path")
                    .font(.system(.caption,
                                  design: .monospaced)
                        .weight(.semibold))
                Text(tapOn ? L("on") : L("off"))
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(
                        tapOn ? .green : .secondary)
            }
            Text(BetafischTap.coverageNote)
                .font(.system(.caption2,
                              design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
            if tapFrames > 0 {
                Text(String(format: L("%lld frames of the house's own wire are recorded (%lld bytes)%@"),
                            tapFrames, tapBytes,
                            tapCapped
                                ? L(" — the recording stopped at the tap's cap")
                                : ""))
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Button {
                    BetafischTap.shared.enabled =
                        !tapOn
                    refreshTap()
                } label: {
                    Label(tapOn
                            ? L("turn the tap off")
                            : L("turn the tap on"),
                          systemImage: tapOn
                            ? "pause.circle"
                            : "record.circle")
                }
                if tapFrames > 0 {
                    Button {
                        openTapCapture()
                    } label: {
                        Label(L("open the tap capture"),
                              systemImage:
                                "doc.text.magnifyingglass")
                    }
                    Button {
                        saveTapCapture()
                    } label: {
                        Label(L("save it to the tree"),
                              systemImage:
                                "tray.and.arrow.down")
                    }
                    Button {
                        BetafischTap.shared.clear()
                        refreshTap()
                    } label: {
                        Label(L("clear it"),
                              systemImage: "trash")
                    }
                }
            }
            .font(.system(.caption,
                          design: .monospaced))
            if let tapNote {
                Text(tapNote)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }

    private func refreshTap() {
        tapOn = BetafischTap.shared.enabled
        let standing = BetafischTap.shared
            .snapshot()
        tapFrames = standing.frames
        tapBytes = standing.bytes
        tapCapped = standing.capped
    }

    private func openTapCapture() {
        guard let data = BetafischTap.shared
            .captureData() else {
            tapNote = L("the tap has recorded nothing yet.")
            return
        }
        load(data: data,
             name: L("the house wire.pcapng"))
        tapNote = nil
    }

    private func saveTapCapture() {
        guard let data = BetafischTap.shared
            .captureData() else {
            tapNote = L("the tap has recorded nothing yet.")
            return
        }
        if BlacksiteFS.writeData(
            "housewire.pcapng", data: data) {
            tapNote = L("saved to the tree as housewire.pcapng — betafisch housewire.pcapng opens it.")
        } else {
            tapNote = L("the tree would not take it.")
        }
    }

    // MARK: Export — the share door

    /// Write bytes to a file the share
    /// sheet can hand over, and raise
    /// the door. The file rides in the
    /// temporary directory; the capture
    /// itself never leaves the room
    /// except through this door.
    private func shareBytes(_ data: Data,
                            name: String) {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(name)
        do {
            try data.write(to: url)
            shareItem = ShareItem(items: [url])
        } catch {
            exportNote = L("the export could not be written.")
        }
    }

    private func exportOriginal() {
        guard let capture else { return }
        if let sourceData {
            shareBytes(sourceData,
                       name: capture.name)
            exportNote = L("the capture's own bytes, unchanged.")
        } else {
            let data = BetafischWrite.pcapng(
                capture: capture)
            shareBytes(
                data,
                name: exportStem(capture.name)
                    + ".pcapng")
            exportNote = L("this capture was made inside the room, so it is written out fresh as pcapng.")
        }
    }

    private func exportPCAPNG() {
        guard let capture else { return }
        let data = BetafischWrite.pcapng(
            capture: capture)
        shareBytes(
            data,
            name: exportStem(capture.name)
                + ".pcapng")
        exportNote = L("the frames are carried unchanged; the source file's comments and interface names are not.")
    }

    private func exportPCAP() {
        guard let capture else { return }
        let made = BetafischWrite.classicPCAP(
            capture: capture)
        shareBytes(
            made.data,
            name: exportStem(capture.name)
                + ".pcap")
        if made.skipped > 0 {
            exportNote = String(
                format: L("the classic format carries one link type — %lld frame(s) of other link types were left out, and the count is the loss."),
                made.skipped)
        } else {
            exportNote = L("every frame is in it; timestamps land at the classic format's microsecond resolution.")
        }
    }

    private func exportStem(_ name: String)
        -> String {
        let stem = (name as NSString)
            .deletingPathExtension
        return stem.isEmpty ? L("capture") : stem
    }

    // MARK: The list and the empty room

    @ViewBuilder private var content: some View {
        if let capture {
            if capture.frames.isEmpty {
                emptyNote(L("this capture holds no frames betafisch could read."))
            } else if visibleFrames.isEmpty {
                emptyNote(L("no frame matches the filter."))
            } else {
                List(visibleFrames) { frame in
                    NavigationLink {
                        BFFrameDetailView(
                            frame: frame,
                            baseTime: capture.frames
                                .first?.timestamp ?? 0)
                    } label: {
                        frameRow(frame,
                                 baseTime: capture.frames
                                    .first?.timestamp ?? 0)
                    }
                }
                .listStyle(.plain)
            }
        } else {
            emptyNote(L("betafisch reads captures — it cannot sniff the wire from this phone. iOS keeps the wire to itself; what the room can do is take a capture apart, frame by frame. Open a .pcap or .pcapng, or try the sample."))
        }
    }

    private func emptyNote(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(.caption,
                              design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
    }

    private func frameRow(_ frame: BFFrame,
                          baseTime: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(String(format: "#%lld", frame.number))
                    .bold()
                Text(String(format: "%.3f",
                            frame.timestamp - baseTime))
                Text(frame.proto)
                    .bold()
                Spacer()
                Text(String(format: L("%lld bytes"),
                            frame.origLen))
            }
            Text(String(format: L("%@ → %@"),
                        frame.src, frame.dst))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(frame.info)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.system(.caption, design: .monospaced))
    }

    // MARK: Loading and filtering

    private var visibleFrames: [BFFrame] {
        guard let capture else { return [] }
        guard let appliedFilter else {
            return capture.frames
        }
        return capture.frames.filter {
            Betafisch.filterMatches(appliedFilter, $0)
        }
    }

    private func load(data: Data, name: String) {
        do {
            capture = try Betafisch.load(
                data: data, name: name)
            sourceData = data
            exportNote = nil
            errorLine = nil
            resetFilter()
            resetDrift()
        } catch let failure as Betafisch.LoadError {
            errorLine = failure.message
        } catch {
            errorLine = L("that file could not be read as a capture.")
        }
    }

    private func applyFilter() {
        let compiled = Betafisch.compileFilter(filterText)
        filterError = compiled.error
        appliedFilter = compiled.error == nil
            ? compiled.expr : nil
    }

    private func resetFilter() {
        appliedFilter = nil
        filterError = nil
    }

    // MARK: Driftnet

    /// A new capture on the table means
    /// the old catch no longer belongs
    /// to it: the wall is cleared and the
    /// room walks back to the list.
    private func resetDrift() {
        driftObjects = []
        driftStats = nil
        driftRunning = false
        path = []
    }

    /// Run the extraction off the main
    /// thread — a big capture's streams
    /// take real work to lay out — and
    /// walk to the gallery when the
    /// catch is in.
    private func runDrift() {
        guard let capture, !driftRunning else {
            return
        }
        driftRunning = true
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let extraction = BetafischDrift
                    .extractDetailed(capture)
                DispatchQueue.main.async {
                    driftObjects = extraction.objects
                    driftStats = extraction.stats
                    driftRunning = false
                    if !path.contains(.gallery) {
                        path.append(.gallery)
                    }
                }
            }
    }
}

// MARK: - One frame, taken apart

struct BFFrameDetailView: View {
    let frame: BFFrame
    let baseTime: Double
    @State private var selected: Range<Int>?

    var body: some View {
        List {
            Section {
                row(L("Number"),
                    String(format: "%lld", frame.number))
                row(L("Time"),
                    String(format: "%.6f (%@)",
                           frame.timestamp,
                           String(format: L("+%.3f s"),
                                  frame.timestamp - baseTime)))
                row(L("Captured"),
                    String(format: L("%lld bytes"),
                           frame.bytes.count))
                if frame.origLen != frame.bytes.count {
                    row(L("On the wire"),
                        String(format: L("%lld bytes"),
                               frame.origLen))
                }
                row(L("Protocol"), frame.proto)
            }
            Section(L("the dissection")) {
                ForEach(frame.tree) { node in
                    BFNodeRow(node: node,
                              selected: $selected)
                }
            }
            Section(L("the bytes")) {
                hexDump
            }
        }
        .groupedListStyle()
        .navigationTitle(String(format: L("frame %lld"),
                                frame.number))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String,
                     _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(.caption, design: .monospaced))
    }

    // The hex dump: offset, sixteen
    // bytes, the ASCII gutter. A tapped
    // tree node's bytes wear the accent.
    @ViewBuilder private var hexDump: some View {
        let cap = 8192
        let shown = min(frame.bytes.count, cap)
        ForEach(Array(stride(from: 0, to: shown,
                             by: 16)), id: \.self) {
            start in
            hexRow(start: start)
        }
        if frame.bytes.count > shown {
            Text(String(format: L("the first %lld of %lld bytes are shown"),
                        shown, frame.bytes.count))
                .font(.system(.caption2,
                              design: .monospaced))
                .foregroundStyle(.secondary)
        }
        if selected != nil {
            Button(L("clear the highlight")) {
                selected = nil
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func hexRow(start: Int) -> some View {
        let rowEnd = min(start + 16, frame.bytes.count)
        let slice = Array(frame.bytes[start..<rowEnd])
        let hexParts = slice.map {
            Betafisch.hexByte(Int($0))
        }
        let hex = hexParts.joined(separator: " ")
        let ascii = Betafisch.textRender(slice)
        return HStack(alignment: .top, spacing: 10) {
            Text(Betafisch.hexDumpWord(start, 4))
                .foregroundStyle(.secondary)
            hexText(hex: hex, start: start, end: rowEnd)
            Text(ascii)
                .foregroundStyle(.secondary)
        }
        .font(.system(.caption2, design: .monospaced))
    }

    @ViewBuilder
    private func hexText(hex: String, start: Int,
                         end: Int) -> some View {
        if let selected,
           selected.lowerBound < end,
           selected.upperBound > start {
            let lo = max(selected.lowerBound, start)
            let hi = min(selected.upperBound, end)
            let preChars = (lo - start) * 3
            let midChars = max(0, (hi - lo) * 3 - 1)
            let pre = String(hex.prefix(preChars))
            let mid = String(
                hex.dropFirst(preChars).prefix(midChars))
            let post = String(
                hex.dropFirst(preChars + midChars))
            HStack(spacing: 0) {
                if !pre.isEmpty { Text(pre) }
                Text(mid)
                    .background(
                        Color.accentColor.opacity(0.35))
                if !post.isEmpty { Text(post) }
            }
        } else {
            Text(hex)
        }
    }
}

// MARK: - The tree

struct BFNodeRow: View {
    let node: BFNode
    @Binding var selected: Range<Int>?

    var body: some View {
        if node.children.isEmpty {
            label
                .contentShape(Rectangle())
                .onTapGesture {
                    selected = node.range
                }
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    BFNodeRow(node: child,
                              selected: $selected)
                }
            } label: {
                label
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selected = node.range
                    }
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(node.title)
                .font(.system(.caption,
                              design: .monospaced)
                    .weight(.semibold))
            if !node.detail.isEmpty {
                Text(node.detail)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !node.range.isEmpty {
                Text(String(format: L("bytes %lld–%lld"),
                            node.range.lowerBound,
                            node.range.upperBound - 1))
                    .font(.system(.caption2,
                                  design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Driftnet's wall

/// Where the room can walk: the
/// gallery driftnet lifts.
enum DriftRoute: Hashable {
    case gallery
}

/// The wall: every picture the capture
/// carried, pinned up as it was found.
struct DriftGalleryView: View {
    let objects: [DriftObject]
    let stats: DriftStats?

    private let columns = [
        GridItem(.adaptive(minimum: 104),
                 spacing: 10),
    ]

    var body: some View {
        Group {
            if objects.isEmpty {
                VStack {
                    Spacer()
                    Text(L("this capture carries no pictures."))
                        .font(.system(.caption,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading,
                           spacing: 10) {
                        Text(String(format:
                            L("%lld pictures lifted"),
                                    objects.count))
                            .font(.system(
                                .caption,
                                design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let stats,
                           stats.cappedStreams > 0 {
                            Text(L("some streams ran past the reading limit — only their first stretch was searched."))
                                .font(.system(
                                    .caption,
                                    design: .monospaced))
                                .foregroundStyle(
                                    .secondary)
                        }
                        LazyVGrid(columns: columns,
                                  spacing: 10) {
                            ForEach(objects) { object in
                                NavigationLink {
                                    DriftDetailView(
                                        object: object)
                                } label: {
                                    tile(object)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(12)
                }
            }
        }
        .navigationTitle(L("driftnet"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tile(
        _ object: DriftObject) -> some View {
        VStack(spacing: 4) {
            tileImage(object)
                .frame(height: 92)
                .frame(maxWidth: .infinity)
                .clipped()
            Text(String(format: L("%@ · %lld bytes"),
                        object.kind.displayName,
                        object.byteCount))
                .font(.system(.caption2,
                              design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func tileImage(
        _ object: DriftObject) -> some View {
        if let thumb = object.thumbnail,
           let image = UIImage(data: thumb) {
            Image.platformImage(image)
                .resizable()
                .scaledToFill()
        } else if let image = UIImage(
            data: object.data) {
            Image.platformImage(image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }
}

/// One lifted picture, full-size, with
/// where it came from told plainly.
struct DriftDetailView: View {
    let object: DriftObject
    @State private var filedNote: String?

    var body: some View {
        List {
            Section(L("the picture")) {
                picture
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }
            Section(L("where it was found")) {
                row(L("kind"),
                    object.kind.displayName)
                row(L("size"),
                    String(format: L("%lld bytes"),
                           object.byteCount))
                row(L("stream"), object.source)
                if let host = object.host {
                    row(L("host"), host)
                }
                if let path = object.path {
                    row(L("path"), path)
                }
                if let method = object.method {
                    row(L("method"), method)
                }
                row(L("frames"),
                    String(format:
                        L("frames %lld–%lld"),
                           object.firstFrame,
                           object.lastFrame))
                row(L("sha-256"), object.shortSHA)
                row(L("times seen"),
                    String(format: "%lld",
                           object.hitCount))
                row(L("found"),
                    object.viaHTTP
                        ? L("served over HTTP")
                        : L("carved from the stream"))
                if object.torn {
                    Text(L("torn stream — some of its bytes never arrived"))
                        .font(.system(.caption,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    fileIt()
                } label: {
                    Label(L("file it in Deliveries"),
                          systemImage:
                            "tray.and.arrow.down")
                }
                if let filedNote {
                    Text(filedNote)
                        .font(.system(.caption,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .groupedListStyle()
        .navigationTitle(object.kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var picture: some View {
        if object.kind == .gif {
            gifPicture
        } else if let image = UIImage(
            data: object.data) {
            Image.platformImage(image)
                .resizable()
                .scaledToFit()
                .frame(height: 280)
        } else {
            Image(systemName: "photo")
                .frame(height: 120)
        }
    }

    /// A GIF rides the house road — the
    /// platform player, never a hand-
    /// rolled one.
    @ViewBuilder private var gifPicture: some View {
        #if os(iOS)
        GIFPlayerView(data: object.data,
                      contentMode: .scaleAspectFit)
            .frame(height: 280)
        #else
        GIFPlayerView(data: object.data)
            .frame(height: 280)
        #endif
    }

    private func row(_ title: String,
                     _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(2)
        }
        .font(.system(.caption, design: .monospaced))
    }

    /// File the picture with the house
    /// hand: DeliveriesCenter writes it
    /// to the shelf under a name drawn
    /// from where it was found.
    private func fileIt() {
        var name = "drift " + object.kind.rawValue
            + " " + object.shortSHA
        if let path = object.path {
            let base = (path as NSString)
                .lastPathComponent
            let stem = (base as NSString)
                .deletingPathExtension
            if !stem.isEmpty {
                name = stem
            }
        }
        DeliveriesCenter.shared.add(
            name: name, data: object.data,
            ext: object.kind.fileExtension)
        filedNote = L("filed in Deliveries")
    }
}

// MARK: - Follow-stream (B2)

/// The conversations in a capture,
/// lifted out to read: pick one and
/// follow either direction, or both.
/// TCP is laid out by driftnet's
/// reassembly; UDP keeps its datagram
/// boundaries. Content is shown as
/// text or hex — never rendered,
/// never run.
struct BFStreamsView: View {
    let capture: BFCapture
    @State private var streams: [BFStream] = []
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if streams.isEmpty {
                VStack {
                    Spacer()
                    Text(L("this capture holds no conversations — no TCP streams and no UDP exchanges."))
                        .font(.system(.caption,
                                      design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
                List(streams) { stream in
                    NavigationLink {
                        BFStreamDetailView(
                            stream: stream)
                    } label: {
                        streamRow(stream)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L("streams"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            let held = capture
            DispatchQueue.global(
                qos: .userInitiated).async {
                let found = BFStreams.all(of: held)
                DispatchQueue.main.async {
                    streams = found
                    loaded = true
                }
            }
        }
    }

    private func streamRow(
        _ stream: BFStream) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(stream.transport == .tcp
                        ? "TCP" : "UDP")
                    .bold()
                Text(stream.label)
                    .lineLimit(1)
            }
            Text(String(format: L("%lld bytes %@ · %lld bytes %@ · frames %lld–%lld"),
                        stream.aToB.count,
                        stream.aLabel,
                        stream.bToA.count,
                        stream.bLabel,
                        stream.firstFrame,
                        stream.lastFrame))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .font(.system(.caption, design: .monospaced))
    }
}

/// One conversation, read closely.
struct BFStreamDetailView: View {
    let stream: BFStream
    /// 0: A→B. 1: B→A. 2: both.
    @State private var direction = 0
    /// 0: text. 1: hex.
    @State private var encoding = 0

    var body: some View {
        List {
            Section(L("the conversation")) {
                row(L("transport"),
                    stream.transport == .tcp
                        ? "TCP" : "UDP")
                row(stream.aLabel,
                    String(format: L("%lld bytes"),
                           stream.aToB.count))
                row(stream.bLabel,
                    String(format: L("%lld bytes"),
                           stream.bToA.count))
                row(L("frames"),
                    String(format: L("%lld (frames %lld–%lld)"),
                           stream.frameCount,
                           stream.firstFrame,
                           stream.lastFrame))
                if stream.transport == .tcp {
                    if stream.retransmissions > 0 {
                        row(L("retransmissions"),
                            String(format: L("%lld segments arrived whole a second time"),
                                   stream.retransmissions))
                    }
                    let holes = stream.aHoles
                        + stream.bHoles
                    if holes > 0 || stream.torn {
                        row(L("holes"),
                            String(format: L("%lld stretch(es) the capture never held — the reading skips them, it does not invent them"),
                                   max(holes, 1)))
                    }
                    if stream.capped {
                        row(L("reading limit"),
                            L("the stream ran past the reading limit — only its first stretch is laid out"))
                    }
                } else {
                    row(L("datagrams"),
                        String(format: L("%lld %@ · %lld %@"),
                               stream.aDatagrams.count,
                               stream.aLabel,
                               stream.bDatagrams.count,
                               stream.bLabel))
                }
            }
            Section {
                Picker(L("direction"),
                       selection: $direction) {
                    Text(stream.aLabel).tag(0)
                    Text(stream.bLabel).tag(1)
                    Text(L("both")).tag(2)
                }
                .pickerStyle(.segmented)
                Picker(L("shown as"),
                       selection: $encoding) {
                    Text(L("text")).tag(0)
                    Text(L("hex")).tag(1)
                }
                .pickerStyle(.segmented)
            }
            Section(L("the bytes")) {
                streamContent
            }
        }
        .groupedListStyle()
        .navigationTitle(L("stream"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String,
                     _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(value)
                .lineLimit(2)
        }
        .font(.system(.caption, design: .monospaced))
    }

    @ViewBuilder private var streamContent: some View {
        if direction == 2 {
            block(title: stream.aLabel,
                  bytes: stream.aToB,
                  datagrams: stream.aDatagrams)
            block(title: stream.bLabel,
                  bytes: stream.bToA,
                  datagrams: stream.bDatagrams)
        } else if direction == 0 {
            block(title: stream.aLabel,
                  bytes: stream.aToB,
                  datagrams: stream.aDatagrams)
        } else {
            block(title: stream.bLabel,
                  bytes: stream.bToA,
                  datagrams: stream.bDatagrams)
        }
    }

    /// One direction laid out. Text is
    /// the house rendering (printables
    /// stand, the rest are dots); hex
    /// caps at 32 KB and says so.
    @ViewBuilder
    private func block(title: String,
                       bytes: [UInt8],
                       datagrams: [Int])
        -> some View {
        Text(title)
            .font(.system(.caption,
                          design: .monospaced)
                .weight(.semibold))
        if bytes.isEmpty {
            Text(L("nothing was said in this direction."))
                .font(.system(.caption,
                              design: .monospaced))
                .foregroundStyle(.secondary)
        } else if encoding == 0 {
            if stream.transport == .udp
                && datagrams.count > 1 {
                udpText(bytes: bytes,
                        datagrams: datagrams)
            } else {
                textBlock(bytes)
            }
        } else {
            hexBlock(bytes)
        }
    }

    private func textBlock(_ bytes: [UInt8])
        -> some View {
        let cap = 65_536
        let shown = Array(bytes.prefix(cap))
        return VStack(alignment: .leading,
                      spacing: 6) {
            Text(Betafisch.textRender(shown))
                .font(.system(.caption2,
                              design: .monospaced))
                .textSelection(.enabled)
            if bytes.count > cap {
                Text(String(format: L("the first %lld of %lld bytes are shown"),
                            cap, bytes.count))
                    .font(.system(.caption2,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// UDP text keeps its boundaries:
    /// each datagram under its own
    /// marker, in arrival order.
    private func udpText(bytes: [UInt8],
                         datagrams: [Int])
        -> some View {
        var chunks: [(Int, [UInt8])] = []
        var cursor = 0
        for (index, size) in datagrams
            .enumerated() {
            let end = min(bytes.count,
                          cursor + size)
            chunks.append((index + 1,
                           Array(bytes[cursor..<end])))
            cursor = end
        }
        return VStack(alignment: .leading,
                      spacing: 6) {
            ForEach(Array(chunks.enumerated()),
                    id: \.offset) { _, chunk in
                Text(String(format: L("— datagram %lld (%lld bytes) —"),
                            chunk.0, chunk.1.count))
                    .font(.system(.caption2,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(Betafisch.textRender(chunk.1))
                    .font(.system(.caption2,
                                  design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func hexBlock(_ bytes: [UInt8])
        -> some View {
        let cap = 32_768
        let shown = min(bytes.count, cap)
        return VStack(alignment: .leading,
                      spacing: 2) {
            ForEach(Array(stride(from: 0,
                                 to: shown, by: 16)),
                    id: \.self) { start in
                let rowEnd = min(start + 16, shown)
                let slice = Array(
                    bytes[start..<rowEnd])
                HStack(alignment: .top,
                       spacing: 10) {
                    Text(Betafisch.hexDumpWord(
                        start, 4))
                        .foregroundStyle(.secondary)
                    Text(slice.map {
                        Betafisch.hexByte(Int($0))
                    }.joined(separator: " "))
                    Text(Betafisch.textRender(
                        slice))
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption2,
                              design: .monospaced))
            }
            if bytes.count > shown {
                Text(String(format: L("the first %lld of %lld bytes are shown"),
                            shown, bytes.count))
                    .font(.system(.caption2,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Statistics (B2)

/// The capture counted: hierarchy,
/// endpoints, conversations, lengths,
/// time. Nothing here is estimated —
/// every number is a count of the
/// frames in hand.
struct BFStatsView: View {
    let capture: BFCapture
    @State private var stats: BFStats?

    var body: some View {
        Group {
            if let stats {
                List {
                    Section(L("the capture")) {
                        row(L("frames"),
                            String(format: "%lld",
                                   stats.totalFrames))
                        row(L("bytes"),
                            String(format: "%lld",
                                   stats.totalBytes))
                        row(L("span"),
                            String(format: L("%.3f seconds"),
                                   stats.span))
                        if stats.totalFrames > 1 {
                            row(L("mean gap"),
                                String(format: L("%.4f seconds"),
                                       stats.meanGap))
                            row(L("rate"),
                                String(format: L("%.1f frames/s · %lld bytes/s"),
                                       stats.framesPerSecond,
                                       Int64(
                                        stats.bytesPerSecond)))
                        }
                        row(L("lengths"),
                            String(format: L("min %lld · mean %.1f · max %lld"),
                                   stats.minLength,
                                   stats.meanLength,
                                   stats.maxLength))
                    }
                    Section(L("protocol hierarchy")) {
                        ForEach(stats.hierarchy) {
                            proto in
                            row(proto.name,
                                String(format: L("%lld frames · %lld frame bytes"),
                                       proto.frames,
                                       proto.bytes))
                        }
                    }
                    Section(L("endpoints")) {
                        ForEach(stats.endpoints) {
                            endpoint in
                            VStack(alignment: .leading,
                                   spacing: 1) {
                                Text(endpoint.address)
                                    .font(.system(
                                        .caption,
                                        design: .monospaced)
                                        .weight(.semibold))
                                Text(String(format: L("sent %lld frames (%lld bytes) · received %lld (%lld)"),
                                            endpoint.sentFrames,
                                            endpoint.sentBytes,
                                            endpoint.receivedFrames,
                                            endpoint.receivedBytes))
                                    .font(.system(
                                        .caption,
                                        design: .monospaced))
                                    .foregroundStyle(
                                        .secondary)
                            }
                        }
                    }
                    Section(L("conversations")) {
                        ForEach(stats.conversations) {
                            convo in
                            VStack(alignment: .leading,
                                   spacing: 1) {
                                Text(convo.transport
                                        + " "
                                        + convo.label)
                                    .font(.system(
                                        .caption,
                                        design: .monospaced)
                                        .weight(.semibold))
                                    .lineLimit(1)
                                Text(String(format: L("%lld frames · %lld bytes · %@ → %@ frames one way, %@ the other · starts +%.3fs, runs %.3fs"),
                                            convo.frames,
                                            convo.bytes,
                                            String(convo.aToBFrames),
                                            String(convo.bToAFrames),
                                            convo.startOffset,
                                            convo.duration))
                                    .font(.system(
                                        .caption,
                                        design: .monospaced))
                                    .foregroundStyle(
                                        .secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                    Section(L("packet lengths")) {
                        ForEach(Array(
                            stats.lengthRows
                                .enumerated()),
                                id: \.offset) { _, item in
                            row(item.label,
                                String(format: "%lld",
                                       item.count))
                        }
                    }
                }
                .groupedListStyle()
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .navigationTitle(L("statistics"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard stats == nil else { return }
            let held = capture
            DispatchQueue.global(
                qos: .userInitiated).async {
                let made = BFStatistics.compute(
                    held)
                DispatchQueue.main.async {
                    stats = made
                }
            }
        }
    }

    private func row(_ title: String,
                     _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(.caption, design: .monospaced))
    }
}
