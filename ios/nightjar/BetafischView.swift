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

    @Environment(\.dismiss) private var dismiss
    @State private var capture: BFCapture?
    @State private var errorLine: String?
    @State private var filterText = ""
    @State private var appliedFilter:
        Betafisch.FilterExpr?
    @State private var filterError: String?
    @State private var showImporter = false
    @State private var didSeed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider()
                content
            }
            .navigationTitle(L("betafisch"))
            .navigationBarTitleDisplayMode(.inline)
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
                } label: {
                    Label(L("the sample"),
                          systemImage: "play.rectangle")
                }
            }
            .font(.system(.caption, design: .monospaced))
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
