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

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                controls
                Divider()
                content
            }
            .navigationTitle(L("betafisch"))
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
        }
        .onAppear {
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
            }
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
        .listStyle(.insetGrouped)
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
        .listStyle(.insetGrouped)
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
