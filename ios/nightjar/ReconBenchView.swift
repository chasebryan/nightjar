import SwiftUI

/// The Recon tab: knock a host with the right protocol on every open
/// port, hold a console against one target, or throw mangled bytes at
/// it. Any probe hands straight to the Send tab in a tap.
struct ReconBenchView: View {
    @Binding var tab: Int
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var book: PayloadBook
    @StateObject private var recon = Recon()

    // Persisted since the War Chest arrived: a chest
    // captures and recalls the bench's posture, so the
    // fields live under keys now, not in the view.
    @AppStorage("reconHost") private var host = ""
    @AppStorage("reconPorts") private var ports = ""
    @AppStorage("reconKnockUDP") private var knockUDP = false
    @AppStorage("reconJobs") private var jobs = 24.0
    @AppStorage("reconTimeout") private var timeout = 1.5
    @State private var showPresets = false
    @State private var presetFilter = ""
    @State private var connectLine = ""
    @State private var connectCRLF = true
    @State private var fuzzTarget = ""
    @State private var fuzzSeed = ""
    @State private var fuzzCount = 200.0
    @State private var fuzzMutations = 1.0

    private var portList: [Int] {
        let trimmed = ports.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ReconPayloads.defaultPorts }
        var out: [Int] = []
        for chunk in trimmed.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let text = String(chunk)
            if let dash = text.firstIndex(of: "-"), dash != text.startIndex {
                let low = Int(text[text.startIndex..<dash]) ?? 0
                let high = Int(text[text.index(after: dash)...]) ?? 0
                if low > 0, high >= low, high - low <= 1024 {
                    out.append(contentsOf: low...min(high, 65535))
                }
            } else if let port = Int(text), (1...65535).contains(port) {
                out.append(port)
            }
        }
        return Array(Set(out)).sorted().prefix(1024).map { $0 }
    }

    /// The counter-knock pivot: EMCON's tripwire hands a knock's
    /// source here — the bench aims itself (host + the knocked
    /// port). Firing is still the operator's press.
    private func consumeReconHandoff() {
        guard let handoff = mouth.reconHandoff else { return }
        host = handoff.host
        ports = "\(handoff.port)"
        knockUDP = false
    }

    var body: some View {
        NavigationStack {
            Form {
                knockSection
                if !recon.hits.isEmpty { resultsSection }
                connectSection
                fuzzSection
                librarySection
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle(L("Recon"))
            .onAppear {
                recon.mouth = mouth
                consumeReconHandoff()
            }
            .onChange(of: mouth.reconHandoff) { _ in
                consumeReconHandoff()
            }
        }
        .sheet(isPresented: $showPresets) { presetSheet }
    }

    // MARK: knock

    @ViewBuilder private var knockSection: some View {
        Section {
            TextField(L("host or IP (192.168.1.1)"), text: $host)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
            TextField(L("ports — blank for the usual suspects, or 22,80,443 or 1-1024"),
                      text: $ports)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Toggle(L("Also knock the UDP service ports"), isOn: $knockUDP)
            HStack {
                Text(L("At a time"))
                Slider(value: $jobs, in: 4...64, step: 4)
                Text("\(Int(jobs))").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text(L("Timeout"))
                Slider(value: $timeout, in: 0.5...5, step: 0.5)
                Text(String(format: "%.1fs", timeout))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                recon.knock(host: host, ports: portList, udp: knockUDP,
                            timeout: timeout, jobs: Int(jobs))
            } label: {
                Label(recon.knocking
                      ? "Knocking… \(recon.probed)/\(recon.total)"
                      : "Knock \(portList.count) port(s)",
                      systemImage: "target")
            }
            .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty
                      || recon.knocking)
            if recon.knocking {
                Button(L("Stop")) { recon.cancelKnock() }
            }
        } header: {
            Text(L("Knock"))
        } footer: {
            Text(L("Connects to each port and speaks the protocol that port expects. A star means the reply carried the protocol's own tell — the port answered as that service, not merely opened. Tap a hit to load it into Send."))
        }
    }

    @ViewBuilder private var resultsSection: some View {
        Section(String(format: L("Open — %lld"), recon.hits.filter { $0.isOpen }.count)) {
            ForEach(recon.hits.filter { $0.isOpen }) { hit in
                Button {
                    Haptics.select()
                    handoff(hit)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hit.confirmed ? "★" : "·")
                            .foregroundStyle(hit.confirmed ? .green : .secondary)
                        Text(hit.label)
                            .font(.callout.monospacedDigit())
                        Text(hit.service).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(hit.banner)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func handoff(_ hit: Recon.Hit) {
        let base = recon.lastKnocked.isEmpty
            ? host.trimmingCharacters(in: .whitespaces) : recon.lastKnocked
        mouth.scanHandoffTarget = hit.udp
            ? "udp://\(base):\(hit.port)" : "tcp://\(base):\(hit.port)"
        mouth.scanHandoffPayload = nil
        if let name = ReconPayloads.probe(forPort: hit.port, udp: hit.udp)?.name,
           let data = try? ReconPayloads.build(name) {
            mouth.scanHandoffPayload = name
            mouth.scanHandoffHex = data.map { String(format: "%02x", $0) }.joined()
        }
        toasts.show(String(format: L("Loaded %@ into Send"), hit.label))
        tab = 1
    }

    // MARK: connect

    @ViewBuilder private var connectSection: some View {
        Section {
            TextField(L("tcp://host:port"), text: $recon.connectTarget)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            HStack {
                Button(recon.connected ? L("Close") : L("Open")) {
                    Haptics.tap()
                    recon.connected ? recon.close() : recon.open(recon.connectTarget)
                }
                .disabled(recon.connectTarget.isEmpty)
                Spacer()
                Toggle(L("CRLF"), isOn: $connectCRLF).fixedSize()
            }
            if recon.connected {
                HStack {
                    TextField(L("send a line"), text: $connectLine)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            recon.sendLine(connectLine, crlf: connectCRLF)
                            connectLine = ""
                        }
                    Button(L("Send")) {
                        Haptics.tap()
                        recon.sendLine(connectLine, crlf: connectCRLF)
                        connectLine = ""
                    }
                }
            }
            if !recon.console.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(recon.console.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
                Button(L("Clear console")) { recon.clearConsole() }
                    .font(.caption)
            }
        } header: {
            Text(L("Connect"))
        } footer: {
            Text(L("A console, not a terminal: open the socket, send lines, watch what comes back. Binary replies print as hexdumps."))
        }
    }

    // MARK: fuzz

    @ViewBuilder private var fuzzSection: some View {
        Section {
            TextField(L("target (tcp://host:port or udp://…)"), text: $fuzzTarget)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            TextField(L("seed hex (optional)"), text: $fuzzSeed)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            HStack {
                Text(L("Rounds"))
                Slider(value: $fuzzCount, in: 10...2000, step: 10)
                Text("\(Int(fuzzCount))").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text(L("Mutations"))
                Slider(value: $fuzzMutations, in: 1...8, step: 1)
                Text("\(Int(fuzzMutations))").monospacedDigit().foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                let seed = fuzzSeed.isEmpty ? nil : try? PayloadKit.decodeHex(fuzzSeed)
                recon.startFuzz(target: fuzzTarget, seed: seed,
                                count: Int(fuzzCount), length: 32,
                                mutations: Int(fuzzMutations), seedValue: 1,
                                read: true, timeout: 2)
            } label: {
                Label(recon.fuzzing ? "Fuzzing…" : "Fuzz", systemImage: "waveform.path.ecg")
            }
            .disabled(fuzzTarget.isEmpty || recon.fuzzing)
            if recon.fuzzing {
                Button(L("Stop")) { recon.stopFuzz() }
            }
            if !recon.fuzzLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(recon.fuzzLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        } header: {
            Text(L("Fuzz"))
        } footer: {
            Text(L("Seven mutators, a reproducible seed, and a reply digest per round. DEAD means the connection was refused or reset."))
        }
    }

    // MARK: library

    @ViewBuilder private var librarySection: some View {
        Section {
            Button {
                Haptics.tap()
                showPresets = true
            } label: {
                Label(String(format: L("Protocol library — %lld probes"), ReconPayloads.all.count),
                      systemImage: "book")
            }
            Button {
                Haptics.tap()
                addAllToLibrary()
            } label: {
                Label(L("Add every probe to the payload library"),
                      systemImage: "square.and.arrow.down")
            }
        } header: {
            Text(L("Library"))
        } footer: {
            Text(String(format: L("Wire-exact first words for %lld TCP ports and %lld UDP ports. Adding them to the payload library makes every one sendable by hand from the Send tab."), ReconPayloads.portMap.count, ReconPayloads.udpPortMap.count))
        }
    }

    private func addAllToLibrary() {
        var added = 0
        for name in ReconPayloads.names {
            guard let probe = ReconPayloads.all[name] else { continue }
            let data = probe.build()
            book.add(SavedPayload(
                name: "probe · \(name)",
                source: "hex",
                text: data.map { String(format: "%02x", $0) }.joined(separator: " "),
                xorKey: "", useGzip: false, framing: "raw"))
            added += 1
        }
        toasts.show(String(format: L("Added %lld probes to the payload library"), added))
    }

    @ViewBuilder private var presetSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredPresets, id: \.name) { probe in
                    Button {
                        Haptics.select()
                        showPresets = false
                        mouth.scanHandoffTarget = probe.udp
                            ? "udp://\(host):\(probe.port)"
                            : "tcp://\(host):\(probe.port)"
                        mouth.scanHandoffPayload = probe.name
                        mouth.scanHandoffHex = probe.build()
                            .map { String(format: "%02x", $0) }.joined()
                        toasts.show(String(format: L("Loaded %@ into Send"), probe.name))
                        tab = 1
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(probe.name).font(.callout)
                                Text(probe.summary)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(probe.udp ? "udp" : "tcp")/\(probe.port)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $presetFilter)
            .navigationTitle(L("Protocol library"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { showPresets = false }
                }
            }
        }
    }

    private var filteredPresets: [ReconProbe] {
        let needle = presetFilter.lowercased()
        let all = ReconPayloads.names.compactMap { ReconPayloads.all[$0] }
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(needle)
                || $0.summary.lowercased().contains(needle)
                || $0.family.lowercased().contains(needle)
        }
    }
}
