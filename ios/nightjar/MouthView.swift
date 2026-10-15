import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Send and Serve tabs — the mouth's face. Everything here is a
/// thin skin over `Mouth` (Mouth.swift); nothing transmits except from
/// these buttons.

// MARK: - Send

/// A saved Send-tab setup: the Network Trace's fields and
/// the Centipede's route, named and kept together, so a
/// configuration that worked can be recalled in one tap —
/// or carried to the other phone as a JSON file.
struct NJPreset: Codable, Identifiable {
    var id: String
    var name: String
    var traceScope: String
    var traceDiscoveryPorts: String
    var traceProfilePorts: String
    var traceBonjour: Bool
    var traceAdaptive: Bool
    var traceRules: String
    var centipedeRoute: String
}

/// The preset shelf: a JSON array in UserDefaults, plus
/// the temp file the share sheet hands out.
enum NJPresetStore {
    static let key = "njPresets.v1"

    static func load() -> [NJPreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder()
                .decode([NJPreset].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ presets: [NJPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func exportURL(_ presets: [NJPreset]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(presets)
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-presets.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

struct SendView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var book = PayloadBook()
    @AppStorage("sendTarget") private var target = "tcp://127.0.0.1:9000"
    @State private var phoneSelection: String?
    @AppStorage("sendSource") private var source = "text"
    @State private var payloadText = "hello"
    @State private var payloadHex = "68 65 6c 6c 6f"
    @State private var payloadB64 = "aGVsbG8="
    @State private var xorKey = ""
    @State private var useGzip = false
    @AppStorage("sendFraming") private var framing = "raw"
    @AppStorage("sendMethod") private var method = "POST"
    @AppStorage("sendReadReply") private var readReply = true
    @AppStorage("beaconName") private var beaconName = "nightjar-post"
    @AppStorage("recentTargets") private var recentTargetsBlob = ""

    private var recentTargets: [String] {
        recentTargetsBlob.split(separator: "\n").map(String.init)
    }

    private func noteTargetUsed(_ used: String) {
        var list = recentTargets.filter { $0 != used }
        list.insert(used, at: 0)
        recentTargetsBlob = list.prefix(5).joined(separator: "\n")
    }
    @State private var showError: String?
    @State private var selectedPayloadID: UUID?
    @State private var suppressClear = false
    @State private var customExpanded = false
    @State private var showLibrary = false
    @State private var showLog = false
    @AppStorage("fanoutTargets") private var fanoutTargets = ""
    @AppStorage("centipedeRoute") private var centipedeRoute = ""
    @AppStorage("centipedeMode") private var centipedeMode = "chain"
    @AppStorage("centipedeReturn") private var centipedeReturn = true
    @AppStorage("centipedePerDevice") private var centipedePerDevice = false
    @AppStorage("centipedeSmartSeed") private var centipedeSmartSeed = true
    @AppStorage("sectionOpen.fanout") private var openFanout = false
    @AppStorage("sectionOpen.timing") private var openTiming = false
    @AppStorage("sectionOpen.centipede") private var openCentipede = true
    @AppStorage("sectionOpen.crosstalk") private var openTalk = false
    @AppStorage("talkTargetA") private var talkA = ""
    @AppStorage("talkTargetB") private var talkB = ""
    @AppStorage("talkRounds") private var talkRounds = 4
    @AppStorage("sectionOpen.trace") private var openTrace = false
    @AppStorage("traceScope") private var traceScope = ""
    @AppStorage("traceDiscoveryPorts") private var traceDiscoveryPorts = "80,443,22,445,1883,8080,8443,9100"
    @AppStorage("traceProfilePorts") private var traceProfilePorts = ""
    @AppStorage("traceBonjour") private var traceBonjour = true
    @AppStorage("traceAdaptive") private var traceAdaptive = true
    @AppStorage("traceRules") private var traceRules = """
        # Rules — one per line. They steer the trace and
        # the centipede: followup sends the named library
        # payload to the same door, tag files a label,
        # stop leaves the reply where it lies.
        # contains nginx => tag web
        # contains Redis => followup Redis PING (RESP)
        # port 22 => tag ssh
        """
    @AppStorage("sectionOpen.snatch") private var openSnatch = false
    @AppStorage("sectionOpen.plant") private var openPlant = false
    @State private var centipedeHome = ""
    @State private var showCentipedeSplash = false
    @State private var presets: [NJPreset] = NJPresetStore.load()
    @State private var selectedPresetID = ""
    @State private var presetNameDraft = ""
    @State private var showPresetImporter = false
    @State private var presetExportURL: URL?
    @State private var centipedeSweepPort = "80,443,22,445,62078,8080"
    @AppStorage("centipedeSweepTarget") private var centipedeSweepTarget = ""
    @AppStorage("serveTcpPort") private var serveTcpPort = "9000"
    private var centipedeLines: [String] {
        centipedeRoute.split(separator: "\n").map(String.init)
    }
    private var centipedeHopCount: Int {
        Mouth.journeyCount(route: centipedeLines,
                           perDevice: centipedePerDevice,
                           returnLeg: centipedeReturn)
    }
    @State private var showImporter = false
    @AppStorage("timingMode") private var timingMode = "now"
    @AppStorage("timingDelay") private var timingDelay = "30"
    @AppStorage("timingInterval") private var timingInterval = "10"
    @AppStorage("timingRounds") private var timingRounds = "5"
    @State private var snatchKnock = true
    @AppStorage("plantKind") private var plantKind = "mqtt"
    @AppStorage("plantTopic") private var plantTopic = "nightjar/plant"
    @AppStorage("plantKey") private var plantKey = "nightjar:plant"
    @AppStorage("plantValue") private var plantValue = "planted by nightjar-hack"
    /// The most recent plant: which service, under what key/topic,
    /// at which target. Verify reads this, not the form's current
    /// values, so editing the form after planting can't misdirect it.
    @State private var lastPlant: (service: String, key: String, target: String)?

    private var verifyPlantLabel: String {
        guard let last = lastPlant else {
            return "Verify — plant something first"
        }
        if last.service != "redis" {
            return "Verify — only Redis plants can be checked"
        }
        return "Verify — GET '\(last.key)' back"
    }

    private var fanoutList: [String] {
        fanoutTargets.split(separator: "\n").map(String.init)
    }

    /// How many targets the fan-out runner will actually attempt:
    /// the same expansion `sendToMany` runs — ranges expand, blanks,
    /// comments and duplicates drop, capped at 300. A range-shaped
    /// line that expands to nothing is an invalid range: the runner
    /// reports it as a failed entry, so it never counts here (and is
    /// never treated as a literal hostname).
    private var fanoutExpandedCount: Int {
        var expanded: [String] = []
        for entry in fanoutList {
            let text = entry.trimmingCharacters(in: .whitespaces)
            if let range = Mouth.expandRange(text) {
                expanded += range
            } else if Mouth.looksLikeRange(text) {
                continue
            } else {
                expanded.append(text)
            }
        }
        var seen = Set<String>()
        return expanded
            .filter { !$0.isEmpty && !$0.hasPrefix("#")
                      && seen.insert($0).inserted }
            .prefix(300).count
    }

    private var parsed: Result<SendTarget, Error> {
        Result { try SendTarget.parse(target) }
    }

    private var selectedPayloadName: String? {
        book.items.first { $0.id == selectedPayloadID }?.name
    }

    /// Phones are step 1 material unless the typed target is a BLE one.
    private var showPhones: Bool {
        if case .success(let value) = parsed { return isNetwork(value) }
        return true
    }

    /// The destination a step-3 send would use right now: a picked
    /// phone wins over the typed address.
    private var effectiveTargetText: String {
        phoneSelection.map { "phone:\($0)" } ?? target
    }

    /// The exact bytes a send would emit right now, for the preview:
    /// built through the same path `build(forTargetText:)` uses —
    /// substitution against the current effective target (text source
    /// only; hex/base64 sources skip substitution) — with the step-3
    /// framing applied, just as the network send applies it.
    private var previewData: Data? {
        guard let built = try? PayloadKit.build(
            source: source,
            text: PayloadKit.substitute(payloadText,
                                        targetText: effectiveTargetText),
            hex: payloadHex, b64: payloadB64,
            xorSpec: xorKey, useGzip: useGzip) else { return nil }
        return PayloadKit.frame(built, framing: framing)
    }

    @ViewBuilder private var lastReplyView: some View {
        if let reply = mouth.lastReply {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last reply · \(reply.label) · "
                     + reply.at.formatted(date: .omitted, time: .standard))
                    .font(.caption.weight(.medium))
                Text(PayloadKit.hexdump(reply.data))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let text = PayloadKit.printableText(reply.data) {
                    Text(text).font(.caption)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                handoffSection

                Section(header: Text("Step 1 · Destination")) {
                    if showPhones && !mouth.nearbyPhones.isEmpty {
                        ForEach(mouth.nearbyPhones, id: \.self) { name in
                            Button {
                                Haptics.select()
                                phoneSelection = name
                            } label: {
                                HStack {
                                    Label(name, systemImage: "iphone")
                                    Spacer()
                                    if phoneSelection == name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        Text("…or send to an address instead:")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("tcp://host:port", text: $target)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                        .onTapGesture { phoneSelection = nil }
                    if showPhones && mouth.nearbyPhones.isEmpty
                        && phoneSelection == nil {
                        Text("No nearby phones right now — start serving "
                             + "on another phone on this Wi-Fi and it "
                             + "appears here, or type an address.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if phoneSelection != nil {
                        Text("A nearby phone is selected — the address "
                             + "is ignored until you tap it.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        switch parsed {
                        case .failure(let error):
                            Text(error.localizedDescription)
                                .font(.caption).foregroundStyle(.red)
                        case .success(let value):
                            Text(describe(value))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if !recentTargets.isEmpty && phoneSelection == nil {
                    Section(header: Text("Recent addresses")) {
                        ForEach(recentTargets, id: \.self) { recent in
                            Button {
                                Haptics.select()
                                target = recent
                            } label: {
                                HStack {
                                    Text(recent).font(.body.monospaced())
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section(header: Text("Step 2 · Payload")) {
                    Button {
                        Haptics.tap()
                        showLibrary = true
                    } label: {
                        HStack {
                            Label(selectedPayloadName
                                  ?? "Choose from the library",
                                  systemImage: "books.vertical")
                            Spacer()
                            Text(selectedPayloadName == nil ? "browse" : "change")
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup("…or build a custom one",
                                    isExpanded: $customExpanded) {
                        Picker("Encoding", selection: $source) {
                            Text("Text").tag("text")
                            Text("Hex").tag("hex")
                            Text("Base 64").tag("base64")
                        }
                        .pickerStyle(.segmented)
                        if source == "text" {
                            TextField("payload", text: $payloadText, axis: .vertical)
                                .font(.body.monospaced())
                        } else if source == "hex" {
                            TextField("68 65 6c 6c 6f", text: $payloadHex, axis: .vertical)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        } else {
                            TextField("aGVsbG8=", text: $payloadB64, axis: .vertical)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                        TextField("XOR key (optional, hex or text)", text: $xorKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.body.monospaced())
                        Toggle("gzip the payload first", isOn: $useGzip)
                    }
                    if selectedPayloadName != nil {
                        Text("The library payload is loaded — open "
                             + "Custom to tweak it into your own.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let data = previewData {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.isEmpty
                                 ? "0 bytes — an empty payload"
                                 : "\(data.count) bytes, exactly as they will go out:")
                                .font(.caption).foregroundStyle(.secondary)
                            if !data.isEmpty {
                                Text(PayloadKit.hexdump(
                                    Data(data.prefix(64))))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                if data.count > 64 {
                                    Text("… (\(data.count - 64) more bytes)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                stepThreeSection

                CollapsibleSection("Send to many", isOpen: $openFanout) {
                    Text("One payload, a whole list of targets — typed, "
                         + "pasted, imported from a file, or harvested "
                         + "from the network by the Scan tab.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $fanoutTargets)
                        .font(.body.monospaced())
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                    HStack {
                        Button {
                            Haptics.tap()
                            fanoutTargets = (mouth.lastScanTargets
                                + fanoutList)
                                .joined(separator: "\n")
                            toasts.show("Added \(mouth.lastScanTargets.count) "
                                        + "target(s) from Scan")
                        } label: {
                            Label("From Scan (\(mouth.lastScanTargets.count))",
                                  systemImage: "scope")
                        }
                        .disabled(mouth.lastScanTargets.isEmpty)
                        Spacer()
                        Button {
                            Haptics.tap()
                            fanoutTargets = (mouth.nearbyPhones
                                    .map { "phone:\($0)" } + fanoutList)
                                .joined(separator: "\n")
                        } label: {
                            Label("Phones (\(mouth.nearbyPhones.count))",
                                  systemImage: "iphone")
                        }
                        .disabled(mouth.nearbyPhones.isEmpty)
                        Spacer()
                        Button {
                            Haptics.tap()
                            showImporter = true
                        } label: {
                            Label("Import", systemImage: "doc.badge.plus")
                        }
                    }
                    .font(.caption)
                    Button {
                        Haptics.tap()
                        guard build() != nil else { return }
                        withTiming(label: "fan-out to "
                                         + "\(fanoutExpandedCount) target(s)") {
                            mouth.sendToMany(
                                targets: fanoutList,
                                payloadFor: { build(forTargetText: $0) },
                                framing: framing, method: method,
                                readReply: readReply)
                        }
                    } label: {
                        Label(mouth.fanoutBusy
                                ? "Sending…"
                                : "Send payload to \(fanoutExpandedCount) target(s)",
                              systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mouth.fanoutBusy || fanoutList.isEmpty)
                    if mouth.fanoutBusy {
                        ProgressView()
                    }
                    ForEach(mouth.fanoutLines, id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }

                CollapsibleSection("Timed delivery", isOpen: $openTiming) {
                    Picker("When", selection: $timingMode) {
                        Text("Now").tag("now")
                        Text("After a delay").tag("delay")
                        Text("Repeat").tag("repeat")
                    }
                    .pickerStyle(.segmented)
                    if timingMode == "delay" {
                        HStack {
                            Text("Fire in (seconds)")
                                .foregroundStyle(.secondary)
                            TextField("30", text: $timingDelay)
                                .keyboardType(.numberPad)
                                .font(.body.monospaced())
                        }
                    }
                    if timingMode == "repeat" {
                        HStack {
                            Text("Every (seconds)")
                                .foregroundStyle(.secondary)
                            TextField("10", text: $timingInterval)
                                .keyboardType(.numberPad)
                                .font(.body.monospaced())
                        }
                        HStack {
                            Text("Rounds")
                                .foregroundStyle(.secondary)
                            TextField("5", text: $timingRounds)
                                .keyboardType(.numberPad)
                                .font(.body.monospaced())
                        }
                    }
                    if let status = mouth.scheduleStatus {
                        HStack {
                            Text(status).font(.caption.monospaced())
                            Spacer()
                            Button("Cancel") {
                                Haptics.tap()
                                mouth.cancelSchedule()
                            }
                            .font(.caption)
                        }
                    }
                    Text("Applies to the step-3 send and to fan-out. "
                         + "Timers run while the app is open — iOS "
                         + "suspends background apps, so a scheduled "
                         + "send waits for the app to be on screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                CollapsibleSection("Centipede", isOpen: $openCentipede) {
                    Text("A route, walked hop by hop. Each line is a "
                         + "stop: a target, a range, host:80,443 (a "
                         + "port train), or a bare host (a train "
                         + "across the usual ports). Chain sends each "
                         + "hop the previous hop's reply; Seed sends "
                         + "the step-2 payload everywhere. The phone "
                         + "makes every send, out and back — nothing "
                         + "is left behind on any target.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $centipedeRoute)
                        .font(.body.monospaced())
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                    HStack {
                        Button {
                            Haptics.tap()
                            centipedeRoute = (mouth.lastScanTargets
                                + centipedeLines)
                                .joined(separator: "\n")
                            toasts.show("Added \(mouth.lastScanTargets.count) "
                                        + "device(s) from Scan")
                        } label: {
                            Label("From Scan (\(mouth.lastScanTargets.count))",
                                  systemImage: "scope")
                        }
                        .disabled(mouth.lastScanTargets.isEmpty)
                        Spacer()
                        Button {
                            Haptics.tap()
                            centipedeRoute = (mouth.nearbyPhones
                                    .map { "phone:\($0)" } + centipedeLines)
                                .joined(separator: "\n")
                        } label: {
                            Label("Phones (\(mouth.nearbyPhones.count))",
                                  systemImage: "iphone")
                        }
                        .disabled(mouth.nearbyPhones.isEmpty)
                        Spacer()
                        Button {
                            Haptics.tap()
                            centipedeRoute = (fanoutList + centipedeLines)
                                .joined(separator: "\n")
                        } label: {
                            Label("Fan-out list",
                                  systemImage: "list.bullet")
                        }
                        .disabled(fanoutList.isEmpty)
                    }
                    .font(.caption)
                    TextField("Subnet to sweep — blank = this phone's",
                              text: $centipedeSweepTarget)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.monospaced())
                    HStack {
                        Text("Sweep ports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("80,443,…", text: $centipedeSweepPort)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.body.monospaced())
                        Button {
                            Haptics.tap()
                            sweepIntoRoute()
                        } label: {
                            Label(mouth.crawlSweepBusy
                                    ? "Sweeping…"
                                    : "Sweep this subnet",
                                  systemImage: "dot.radiowaves.left.and.right")
                        }
                        .disabled(mouth.crawlSweepBusy)
                    }
                    .font(.caption)
                    if let status = mouth.crawlSweepStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Discovery knocks the listed ports on every "
                         + "address; each answering host joins the "
                         + "route as a port train over the ports it "
                         + "answered on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Haptics.tap()
                        addThisPhone()
                    } label: {
                        Label("Add this phone's Serve as a target",
                              systemImage: "iphone")
                    }
                    .font(.caption)
                    Picker("Mode", selection: $centipedeMode) {
                        Text("Chain").tag("chain")
                        Text("Seed").tag("seed")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Return to sender (walk the route back)",
                           isOn: $centipedeReturn)
                    Toggle("Every device in the list gets its own walk",
                           isOn: $centipedePerDevice)
                    Toggle("Smart seed — speak each port's protocol",
                           isOn: $centipedeSmartSeed)
                    TextField("Deliver homecoming to (optional)",
                              text: $centipedeHome)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.monospaced())
                    if mouth.crawlBusy {
                        Button(role: .destructive) {
                            Haptics.tap()
                            mouth.stopCrawl()
                        } label: {
                            Label("Stop the centipede",
                                  systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            Haptics.tap()
                            guard build() != nil else { return }
                            mouth.crawl(
                                route: centipedeLines,
                                mode: centipedeMode,
                                returnLeg: centipedeReturn,
                                perDevice: centipedePerDevice,
                                homeTarget: centipedeHome,
                                smartSeed: centipedeSmartSeed,
                                probeFor: probeForTarget,
                                payloadFor: { build(forTargetText: $0) },
                                framing: framing, method: method,
                                rules: TraceRule.parse(traceRules),
                                payloadNamed: payloadNamed)
                            showCentipedeSplash = true
                        } label: {
                            Label("Release the centipede "
                                  + "(\(centipedeHopCount) hop(s))",
                                  systemImage: "ant.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(centipedeLines.isEmpty)
                    }
                    ForEach(mouth.crawlLines, id: \.self) { trailLine in
                        Text(trailLine).font(.caption.monospaced())
                    }
                    if !mouth.crawlFindings.isEmpty {
                        Text("Harvest — what the doors said")
                            .font(.caption.weight(.semibold))
                        ForEach(mouth.crawlFindings, id: \.self) { finding in
                            Text(finding).font(.caption.monospaced())
                        }
                    }
                    if let home = mouth.crawlHomecoming {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("What it brought home — "
                                 + "\(home.count) bytes")
                                .font(.caption.weight(.semibold))
                            if let text = PayloadKit.printableText(home) {
                                Text(text)
                                    .font(.caption.monospaced())
                                    .lineLimit(6)
                            }
                            Text(PayloadKit.hexdump(
                                Data(home.prefix(128))))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                CollapsibleSection("Network Trace", isOpen: $openTrace) {
                    Text("Map one whole /24: every address is "
                         + "knocked, every answering host profiled "
                         + "door by door, and every endpoint a "
                         + "banner or reply mentions is followed "
                         + "(three hops deep) until nothing new is "
                         + "left — then it stops on its own and "
                         + "files a trace JSON. Foreground only, "
                         + "stoppable anytime. Endpoints outside "
                         + "the /24 are written into the report, "
                         + "never contacted.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .onAppear { refreshPresetExport() }
                    if !presets.isEmpty {
                        Picker("Preset", selection: $selectedPresetID) {
                            Text("Choose…").tag("")
                            ForEach(presets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)
                        HStack {
                            Button("Apply preset") {
                                Haptics.tap()
                                applySelectedPreset()
                            }
                            .disabled(selectedPresetID.isEmpty)
                            Button("Delete", role: .destructive) {
                                Haptics.tap()
                                deleteSelectedPreset()
                            }
                            .disabled(selectedPresetID.isEmpty)
                        }
                        .font(.caption)
                    }
                    HStack {
                        TextField("New preset name",
                                  text: $presetNameDraft)
                            .font(.body.monospaced())
                        Button("Save current") {
                            Haptics.tap()
                            saveCurrentPreset()
                        }
                        .disabled(presetNameDraft
                            .trimmingCharacters(
                                in: .whitespaces).isEmpty)
                    }
                    .font(.caption)
                    HStack {
                        if let url = presetExportURL {
                            ShareLink(item: url) {
                                Label("Share presets",
                                      systemImage: "square.and.arrow.up")
                            }
                        }
                        Button {
                            Haptics.tap()
                            showPresetImporter = true
                        } label: {
                            Label("Import presets",
                                  systemImage: "square.and.arrow.down")
                        }
                    }
                    .font(.caption)
                    TextField("Scope — blank = this phone's /24",
                              text: $traceScope)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.monospaced())
                    HStack {
                        Text("Discovery ports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("80,443,…",
                                  text: $traceDiscoveryPorts)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.body.monospaced())
                    }
                    HStack {
                        Text("Profile ports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("blank = usual ports",
                                  text: $traceProfilePorts)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.body.monospaced())
                    }
                    Toggle("Listen for Bonjour while tracing",
                           isOn: $traceBonjour)
                    Toggle("Adaptive — let the rules below steer",
                           isOn: $traceAdaptive)
                    Text("Rules (shared with the Centipede)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $traceRules)
                        .font(.caption.monospaced())
                        .frame(minHeight: 72)
                        .scrollContentBackground(.hidden)
                    if mouth.traceBusy {
                        Button(role: .destructive) {
                            Haptics.tap()
                            mouth.stopNetworkTrace()
                        } label: {
                            Label("Stop the trace",
                                  systemImage: "stop.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            Haptics.tap()
                            mouth.traceAutoCentipede = true
                        } label: {
                            Label(mouth.traceAutoCentipede
                                  ? "Centipede setup armed for this trace"
                                  : "Set up the Centipede from this trace",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(mouth.traceAutoCentipede)
                    } else {
                        Button {
                            Haptics.tap()
                            startTrace()
                        } label: {
                            Label("Start network trace",
                                  systemImage: "point.3.connected.trianglepath.dotted")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mouth.crawlBusy || mouth.talkBusy)
                        Button {
                            Haptics.tap()
                            mouth.traceAutoCentipede = true
                            startTrace()
                        } label: {
                            Label("Trace & set up the Centipede",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(mouth.crawlBusy || mouth.talkBusy)
                        Text("Runs the trace, then replaces the "
                             + "Centipede's route with every door "
                             + "it found — one port train per host, "
                             + "ready to release. Nothing else to "
                             + "configure.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let status = mouth.traceStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mouth.traceLines, id: \.self) { traceLine in
                        Text(traceLine).font(.caption.monospaced())
                    }
                    if let export = mouth.traceLatestExport {
                        ShareLink(item: export) {
                            Label("Download trace JSON",
                                  systemImage: "square.and.arrow.up")
                        }
                        .font(.caption)
                    }
                    if FileManager.default.fileExists(
                        atPath: TraceBookStore.logbookURL.path) {
                        ShareLink(item: TraceBookStore.logbookURL) {
                            Label("Download the crawl logbook",
                                  systemImage: "book.closed")
                        }
                        .font(.caption)
                        Button(role: .destructive) {
                            Haptics.tap()
                            TraceBookStore.shared.clear()
                            toasts.show("Logbook cleared")
                        } label: {
                            Label("Clear logbook",
                                  systemImage: "trash")
                        }
                        .font(.caption)
                    }
                }
                .onChange(of: mouth.traceCentipedeRoute) { route in
                    guard let route = route else { return }
                    centipedeRoute = route
                    mouth.traceCentipedeRoute = nil
                    openCentipede = true
                    toasts.show("Centipede configured from the trace")
                }
                .fileImporter(isPresented: $showPresetImporter,
                              allowedContentTypes: [.json]) { result in
                    importPresets(result)
                }

                CollapsibleSection("Crosstalk", isOpen: $openTalk) {
                    Text("Patch two doors together and let them "
                         + "talk: door A is knocked (its port's "
                         + "probe when smart seed is on), its reply "
                         + "is carried verbatim to B, B's reply back "
                         + "to A — until silence, an echo, a repeat, "
                         + "or the rounds run out. Any targets the "
                         + "route parser accepts; a train or range "
                         + "speaks through its first door.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Door A — tcp://host:port, phone:Name, https://…",
                              text: $talkA)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("Door B — the other door",
                              text: $talkB)
                        .font(.callout.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Button("Serve as A") { setServeDoor(a: true) }
                        Button("Serve as B") { setServeDoor(a: false) }
                        Button("Swap ⇄") {
                            Haptics.tap()
                            (talkA, talkB) = (talkB, talkA)
                        }
                    }
                    .font(.caption)
                    Stepper("Rounds: \(talkRounds)",
                            value: $talkRounds, in: 1...12)
                    if mouth.talkBusy {
                        Button(role: .destructive) {
                            mouth.stopTalk()
                        } label: {
                            Label("Hang up",
                                  systemImage: "phone.down.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Haptics.success()
                            mouth.startTalk(
                                a: talkA, b: talkB,
                                rounds: talkRounds,
                                seed: build(forTargetText: talkA)
                                    ?? Data(),
                                smartSeed: centipedeSmartSeed,
                                probeFor: probeForTarget)
                        } label: {
                            Label("Start the conversation",
                                  systemImage: "bubble.left.and.bubble.right.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(mouth.crawlBusy
                                  || talkA.trimmingCharacters(
                                        in: .whitespaces).isEmpty
                                  || talkB.trimmingCharacters(
                                        in: .whitespaces).isEmpty)
                    }
                    if !mouth.talkLines.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(mouth.talkLines, id: \.self) { entry in
                                Text(entry)
                                    .font(.caption.monospaced())
                            }
                        }
                    }
                    if let last = mouth.talkHomecoming {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The last word — \(last.count) bytes")
                                .font(.caption.weight(.semibold))
                            if let text = PayloadKit.printableText(last) {
                                Text(text)
                                    .font(.caption.monospaced())
                                    .lineLimit(6)
                            }
                            Text(PayloadKit.hexdump(
                                Data(last.prefix(128))))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                CollapsibleSection("SnatchSteal", isOpen: $openSnatch) {
                    Text("Knock on the step-1 target, then take "
                         + "everything it sends back — full drain, "
                         + "not the scanner's polite banner peek. "
                         + "The haul is saved to history.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Knock first (the step-2 payload)",
                           isOn: $snatchKnock)
                    Button {
                        Haptics.tap()
                        snatch()
                    } label: {
                        Label(mouth.snatchBusy
                                ? "Snatching… \(mouth.snatchBytes) bytes so far"
                                : "Snatch from \(phoneSelection ?? target)",
                              systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mouth.snatchBusy)
                    if let result = mouth.snatchResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(result.label) — \(result.data.count) bytes")
                                .font(.caption.weight(.semibold))
                            if let text = PayloadKit.printableText(result.data) {
                                Text(text)
                                    .font(.caption.monospaced())
                                    .lineLimit(6)
                            }
                            Text(PayloadKit.hexdump(result.data)
                                    .components(separatedBy: "\n")
                                    .prefix(6).joined(separator: "\n"))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                CollapsibleSection("PayPlant", isOpen: $openPlant) {
                    Text("Leave a payload living on the target: a "
                         + "service that stores things keeps yours "
                         + "until someone comes to collect. Verify "
                         + "with SnatchSteal or the Redis GET check.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Plant in", selection: $plantKind) {
                        Text("MQTT retained").tag("mqtt")
                        Text("Redis SET").tag("redis")
                        Text("memcached set").tag("memcached")
                    }
                    .pickerStyle(.segmented)
                    if plantKind == "mqtt" {
                        TextField("Topic", text: $plantTopic)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.body.monospaced())
                    } else {
                        TextField("Key", text: $plantKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.body.monospaced())
                    }
                    TextField("Value", text: $plantValue)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    Button {
                        Haptics.tap()
                        plant()
                    } label: {
                        Label("Plant it in \(target)",
                              systemImage: "leaf.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Haptics.tap()
                        verifyPlant()
                    } label: {
                        Label(verifyPlantLabel,
                              systemImage: "checkmark.circle")
                    }
                    .disabled(lastPlant == nil
                              || lastPlant?.service != "redis")
                    Text("Targets step 1 (tcp://host:port — the "
                         + "broker or store's port). Replies land "
                         + "in the readout under step 3.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Send")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.plainText, .text]) { result in
                if case .success(let url) = result,
                   url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let text = try? String(contentsOf: url,
                                              encoding: .utf8) {
                        let imported = text
                            .split(whereSeparator: { $0 == "\n" || $0 == "," })
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        fanoutTargets = (imported + fanoutList)
                            .joined(separator: "\n")
                        toasts.show("Imported \(imported.count) target(s)")
                    }
                }
            }
            .onAppear {
                mouth.startBrowsing()
                consumeScanHandoff()
            }
            .onChange(of: mouth.scanHandoffTarget) { _ in
                consumeScanHandoff()
            }
            .onChange(of: payloadText) { _ in unselectIfEditing() }
            .onChange(of: payloadHex) { _ in unselectIfEditing() }
            .onChange(of: payloadB64) { _ in unselectIfEditing() }
            .onChange(of: xorKey) { _ in unselectIfEditing() }
            .onChange(of: useGzip) { _ in unselectIfEditing() }
            .onChange(of: mouth.nearbyPhones) { names in
                if let picked = phoneSelection, !names.contains(picked) {
                    phoneSelection = nil
                    toasts.show("\(picked) left the network — "
                                + "pick a destination in step 1")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showLog = true
                    } label: {
                        Label("Log", systemImage: "scroll")
                    }
                }
            }
            .sheet(isPresented: $showLibrary) {
                LibrarySheet(book: book, onPick: load,
                             onSave: saveToLibrary)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showLog) {
                MouthLogSheet()
            }
            .fullScreenCover(isPresented: $showCentipedeSplash) {
                CentipedeSplashView(isShown: $showCentipedeSplash)
            }
            .alert("Could not build the payload", isPresented: .constant(showError != nil)) {
                Button("OK") { showError = nil }
            } message: {
                Text(showError ?? "")
            }
        }
    }

    @ViewBuilder private var handoffSection: some View {
        if let label = mouth.pendingWriteLabel {
            Section(header: Text("From Listen")) {
                Text("Write this payload to \(label)? It was picked in "
                     + "the Listen tab — same write as a picked device.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Haptics.tap()
                    if let data = build() { mouth.writeHandoff(payload: data) }
                } label: {
                    Label("Write to \(label)", systemImage: "paperplane.fill")
                }
                Button("Dismiss", role: .cancel) {
                    Haptics.tap()
                    mouth.clearPendingWrite()
                }
            }
        }
    }

    @ViewBuilder private var stepThreeSection: some View {
        if let phone = phoneSelection {
            Section(header: Text("Step 3 · Send")) {
                framingPicker
                Toggle("Read a reply", isOn: $readReply)
                Button {
                    Haptics.tap()
                    withTiming(label: "send to \(phone)") {
                        if let data = build() {
                            noteTargetUsed("phone:\(phone)")
                            mouth.sendToPhone(name: phone, payload: data,
                                              framing: framing, read: readReply,
                                              timeout: 5)
                        }
                    }
                } label: {
                    Label("Send to \(phone)", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                lastReplyView
            }
        } else {
            switch parsed {
            case .success(let value) where isNetwork(value):
                Section(header: Text("Step 3 · Send")) {
                    framingPicker
                    if case .http(_, _) = value {
                        Picker("Method (http)", selection: $method) {
                            ForEach(["POST", "GET", "PUT", "PATCH", "DELETE", "HEAD"], id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                    }
                    Toggle("Read a reply", isOn: $readReply)
                    Button {
                        Haptics.tap()
                        withTiming(label: "send to \(target)") {
                            sendNetwork(value)
                        }
                    } label: {
                        Label("Send to \(target)", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    lastReplyView
                }
            case .success(.bleBeacon):
                Section(header: Text("Step 3 · BLE beacon")) {
                    TextField("Advertised name", text: $beaconName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("The payload rides in service data for FFF0 — the slot "
                         + "iOS lets an app set. Foreground only, and small: "
                         + "keep it under ~20 bytes.")
                        .font(.caption).foregroundStyle(.secondary)
                    if mouth.beaconOn {
                        Button(role: .destructive) {
                            Haptics.tap()
                            mouth.stopBeacon()
                        } label: {
                            Label("Stop beacon", systemImage: "stop.circle.fill")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            if let data = build() { mouth.startBeacon(payload: data, name: beaconName) }
                        } label: {
                            Label("Start beacon", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .success(.bleGatt):
                Section(header: Text("Step 3 · GATT host")) {
                    TextField("Advertised name", text: $beaconName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("Hosts service FFF0 with characteristic FFF1 holding "
                         + "the payload: readable, writable, notifiable. Writes "
                         + "from a central land in the Serve inbox. Once started "
                         + "it stays armed — it keeps hosting in the background "
                         + "and re-arms after a relaunch. Stop it here to disarm.")
                        .font(.caption).foregroundStyle(.secondary)
                    if mouth.gattHostOn {
                        Button(role: .destructive) {
                            Haptics.tap()
                            mouth.stopGattHost()
                        } label: {
                            Label("Stop hosting", systemImage: "stop.circle.fill")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            if let data = build() { mouth.startGattHost(payload: data, name: beaconName) }
                        } label: {
                            Label("Host payload", systemImage: "server.rack")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            case .success(.bleWrite(_)):
                Section(header: Text("Step 3 · Write to a peripheral")) {
                    Text("iOS hides MAC addresses, so pick the device by name "
                         + "from a scan — the Python side's ble-write://ADDR "
                         + "becomes a tap here.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        Haptics.tap()
                        mouth.scanForWriteTargets()
                    } label: {
                        Label(mouth.writeScanning ? "Scanning…" : "Scan for devices",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(mouth.writeScanning)
                    ForEach(mouth.writeTargets) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name ?? "unnamed").lineLimit(1)
                                Text(device.id.uuidString)
                                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(device.rssi.map { "\($0) dBm" } ?? "")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Write") {
                                Haptics.tap()
                                if let data = build() { mouth.write(to: device, payload: data) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            default:
                Section(header: Text("Step 3 · Send")) {
                    Text("Fix the address in step 1 and the send "
                         + "button appears here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var framingPicker: some View {
        Picker("Framing", selection: $framing) {
            Text("raw").tag("raw")
            Text("len prefix").tag("len")
            Text("json envelope").tag("json")
        }
    }

    private func isNetwork(_ target: SendTarget) -> Bool {
        switch target {
        case .tcp(_, _, _), .udp(_, _), .http(_, _): return true
        default: return false
        }
    }

    private func describe(_ target: SendTarget) -> String {
        switch target {
        case .tcp(_, _, let tls): return tls ? "TLS-wrapped TCP" : "raw TCP"
        case .udp(_, _): return "one UDP datagram"
        case .http(_, let https): return https ? "HTTPS request" : "HTTP request"
        case .bleBeacon: return "BLE advertisement carrying the payload"
        case .bleGatt: return "BLE GATT server hosting the payload"
        case .bleWrite(_): return "BLE central write — pick the device below"
        }
    }

    private func build() -> Data? { build(forTargetText: target) }

    /// Build the payload for one destination, resolving templates
    /// ({{host}}, {{port}}, {{target}}, {{scheme}}) against it.
    /// The Centipede's built-in feeder: discovery-knock the
    /// listed ports across the chosen /24 and load every
    /// answering host into the route as a port train over the
    /// ports it answered on.
    private func sweepIntoRoute() {
        let ports = centipedeSweepPort
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...65535).contains($0) }
        guard !ports.isEmpty, ports.count <= 16 else {
            toasts.show("Give 1–16 sweep ports, comma-separated",
                        error: true)
            return
        }
        mouth.discoverSubnet(ports: ports,
                             target: centipedeSweepTarget) { found in
            guard !found.isEmpty else { return }
            let newLines = found.map { entry in
                "tcp://\(entry.host):"
                    + entry.ports.map(String.init).joined(separator: ",")
            }
            centipedeRoute = (newLines + centipedeLines)
                .joined(separator: "\n")
            toasts.show("Added \(found.count) host(s) from discovery")
        }
    }

    /// Put this phone's own Serve listener in a Crosstalk
    /// door — the partner that's always in the room.
    private func setServeDoor(a: Bool) {
        guard let ip = Mouth.localIPAddress() else {
            toasts.show("No Wi-Fi address on this phone", error: true)
            return
        }
        if a { talkA = "tcp://\(ip):\(serveTcpPort)" }
        else { talkB = "tcp://\(ip):\(serveTcpPort)" }
    }

    /// The one target guaranteed to be real: this phone itself.
    /// Adds its own Serve endpoint to the route — start Serve,
    /// release the centipede, and watch the walk knock on your
    /// own listener and carry its reply home.
    private func addThisPhone() {
        guard let ip = Mouth.localIPAddress() else {
            toasts.show("No Wi-Fi address on this phone", error: true)
            return
        }
        centipedeRoute = (["tcp://\(ip):\(serveTcpPort)"] + centipedeLines)
            .joined(separator: "\n")
        toasts.show("Added this phone — start Serve, then release")
    }

    /// The smart seed: for a TCP/UDP target whose port has a
    /// library probe (the Scan tab's port map), the probe's
    /// built bytes and its name — or nil, when the port has no
    /// probe and the step-2 payload should speak instead.
    private func probeForTarget(_ targetText: String)
        -> (data: Data, name: String)?
    {
        guard let parsed = try? SendTarget.parse(targetText) else {
            return nil
        }
        let port: Int
        switch parsed {
        case .tcp(_, let p, _), .udp(_, let p): port = p
        default: return nil
        }
        guard let name = ScanModel.payloadByPort[port],
              let item = book.items.first(where: { $0.name == name }),
              let data = try? PayloadKit.build(
                source: item.source,
                text: item.source == "text" ? item.text : "",
                hex: item.source == "hex" ? item.text : "",
                b64: item.source == "base64" ? item.text : "",
                xorSpec: item.xorKey, useGzip: item.useGzip)
        else { return nil }
        return (data, name)
    }

    /// A library payload by its name, built — the follow-up
    /// rules' ammunition for both the trace and the centipede.
    /// Nil when no item carries that name (or it fails to
    /// build): a rule naming a deleted payload simply never
    /// fires.
    private func payloadNamed(_ name: String) -> Data? {
        guard let item = book.items.first(where: { $0.name == name })
        else { return nil }
        return try? PayloadKit.build(
            source: item.source,
            text: item.source == "text" ? item.text : "",
            hex: item.source == "hex" ? item.text : "",
            b64: item.source == "base64" ? item.text : "",
            xorSpec: item.xorKey, useGzip: item.useGzip)
    }

    /// "80, 443, 22" → [22, 80, 443]: valid ports only,
    /// deduplicated, in order.
    private func parsePortList(_ text: String) -> [Int] {
        Array(Set(text.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...65535).contains($0) })).sorted()
    }

    /// The preset the picker is pointing at, if any.
    private var selectedPreset: NJPreset? {
        presets.first { $0.id == selectedPresetID }
    }

    private func refreshPresetExport() {
        presetExportURL = NJPresetStore.exportURL(presets)
    }

    /// A preset recalls the whole setup: the trace fields
    /// and the Centipede's route alike.
    private func applySelectedPreset() {
        guard let preset = selectedPreset else { return }
        traceScope = preset.traceScope
        traceDiscoveryPorts = preset.traceDiscoveryPorts
        traceProfilePorts = preset.traceProfilePorts
        traceBonjour = preset.traceBonjour
        traceAdaptive = preset.traceAdaptive
        traceRules = preset.traceRules
        centipedeRoute = preset.centipedeRoute
        toasts.show("Preset applied — \(preset.name)")
    }

    /// Save the fields as they stand. A name already on
    /// the shelf is overwritten in place (kept id), so
    /// fixing a preset doesn't fork it.
    private func saveCurrentPreset() {
        let name = presetNameDraft
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let snapshot = NJPreset(
            id: presets.first { $0.name == name }?.id
                ?? UUID().uuidString,
            name: name,
            traceScope: traceScope,
            traceDiscoveryPorts: traceDiscoveryPorts,
            traceProfilePorts: traceProfilePorts,
            traceBonjour: traceBonjour,
            traceAdaptive: traceAdaptive,
            traceRules: traceRules,
            centipedeRoute: centipedeRoute)
        if let index = presets.firstIndex(where: { $0.id == snapshot.id }) {
            presets[index] = snapshot
        } else {
            presets.append(snapshot)
        }
        NJPresetStore.save(presets)
        selectedPresetID = snapshot.id
        presetNameDraft = ""
        refreshPresetExport()
        toasts.show("Preset saved — \(name)")
    }

    private func deleteSelectedPreset() {
        guard let preset = selectedPreset else { return }
        presets.removeAll { $0.id == preset.id }
        NJPresetStore.save(presets)
        selectedPresetID = ""
        refreshPresetExport()
        toasts.show("Preset deleted — \(preset.name)")
    }

    /// Import merges by id: a preset already on the shelf
    /// is replaced by the imported telling, new ones join.
    private func importPresets(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url),
              let incoming = try? JSONDecoder()
                .decode([NJPreset].self, from: data)
        else {
            toasts.show("That file is not a presets file",
                        error: true)
            return
        }
        for preset in incoming {
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[index] = preset
            } else {
                presets.append(preset)
            }
        }
        NJPresetStore.save(presets)
        refreshPresetExport()
        toasts.show("Imported \(incoming.count) preset(s)")
    }

    /// Release a Network Trace with the section's settings.
    private func startTrace() {
        let discovery = parsePortList(traceDiscoveryPorts)
        guard !discovery.isEmpty else {
            toasts.show("Give at least one discovery port",
                        error: true)
            return
        }
        let profileText = traceProfilePorts
            .trimmingCharacters(in: .whitespaces)
        mouth.startNetworkTrace(
            scopeText: traceScope,
            discoveryPorts: discovery,
            profilePorts: profileText.isEmpty
                ? [] : parsePortList(traceProfilePorts),
            includeBonjour: traceBonjour,
            adaptive: traceAdaptive,
            rules: TraceRule.parse(traceRules),
            probeFor: probeForTarget,
            payloadNamed: payloadNamed)
    }

    private func build(forTargetText targetText: String) -> Data? {
        do {
            // Only the text source substitutes templates against the
            // target; hex/base64 sources go out exactly as typed.
            return try PayloadKit.build(
                source: source,
                text: PayloadKit.substitute(payloadText,
                                            targetText: targetText),
                hex: payloadHex,
                b64: payloadB64,
                xorSpec: xorKey, useGzip: useGzip)
        } catch {
            showError = error.localizedDescription
            return nil
        }
    }

    /// Route a send through the Timed delivery settings: fire now,
    /// after the delay, or on the repeat interval.
    private func withTiming(label: String,
                            _ action: @escaping () -> Void) {
        switch timingMode {
        case "delay":
            let secs = Double(timingDelay) ?? 30
            mouth.schedule(after: secs, every: nil, rounds: 1,
                           label: label, action: action)
            toasts.show("Scheduled: \(label) in \(Int(secs))s")
        case "repeat":
            let secs = Double(timingInterval) ?? 10
            let rounds = Int(timingRounds) ?? 5
            mouth.schedule(after: secs, every: secs, rounds: rounds,
                           label: label, action: action)
            toasts.show("Repeating: \(label) every \(Int(secs))s "
                        + "× \(rounds)")
        default:
            action()
        }
    }

    private func sendNetwork(_ target: SendTarget) {
        guard let data = build() else { return }
        noteTargetUsed(self.target)
        switch target {
        case .http(_, _):
            mouth.sendHTTP(target: target, payload: data, framing: framing,
                           method: method, timeout: 10)
        case .tcp(_, _, _), .udp(_, _):
            mouth.sendNetwork(target: target, payload: data, framing: framing,
                              read: readReply, timeout: 5)
        default:
            break
        }
    }

    private func saveToLibrary(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let text = source == "text" ? payloadText
            : source == "hex" ? payloadHex : payloadB64
        book.add(SavedPayload(name: trimmed, source: source, text: text,
                              xorKey: xorKey, useGzip: useGzip,
                              framing: framing))
        // add() replaces a same-name entry in place, so the saved
        // payload is not necessarily the last row — select by name.
        selectedPayloadID = book.items.first { $0.name == trimmed }?.id
        toasts.show("Saved '\(trimmed)' to the library")
    }

    /// Manual edits turn a library pick back into a custom payload —
    /// except while `load` itself is doing the editing.
    private func unselectIfEditing() {
        if !suppressClear { selectedPayloadID = nil }
    }

    private func snatch() {
        // Clear the previous haul at launch, before the run — a
        // failed attempt must not display what an earlier one took.
        mouth.snatchResult = nil
        mouth.snatchBytes = 0
        let probe = snatchKnock ? build() : nil
        if snatchKnock, probe == nil { return }
        if let phone = phoneSelection {
            mouth.snatchPhone(name: phone, probe: probe, framing: framing)
        } else if case .success(let value) = parsed {
            mouth.snatch(target: value, probe: probe, framing: framing)
        } else {
            toasts.show("SnatchSteal needs a target in step 1",
                        error: true)
        }
    }

    private func plant() {
        // Plants are TCP protocols — every other scheme (udp and
        // http included) is rejected outright.
        guard case .success(let value) = parsed,
              case .tcp(let host, let port, _) = value else {
            toasts.show("PayPlant needs a tcp:// target in step 1 — "
                        + "plants are TCP protocols", error: true)
            return
        }
        let plantedTarget = target
        // No success toast until the send completion returns.
        let report: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                if ok {
                    toasts.show("Planted in \(plantedTarget)")
                } else {
                    toasts.show("Could not plant in \(plantedTarget)",
                                error: true)
                }
            }
        }
        switch plantKind {
        case "redis":
            lastPlant = (service: "redis", key: plantKey,
                         target: plantedTarget)
            mouth.sendNetwork(
                target: value,
                payload: PayloadKit.redisCommand(
                    ["SET", plantKey, plantValue]),
                framing: "raw", read: true, timeout: 5,
                completion: report)
        case "memcached":
            lastPlant = (service: "memcached", key: plantKey,
                         target: plantedTarget)
            mouth.sendNetwork(
                target: value,
                payload: PayloadKit.memcachedSet(key: plantKey,
                                                 value: plantValue),
                framing: "raw", read: true, timeout: 5,
                completion: report)
        default:
            lastPlant = (service: "mqtt", key: plantTopic,
                         target: plantedTarget)
            mouth.plantMQTT(host: host, port: port, topic: plantTopic,
                            payload: Data(plantValue.utf8),
                            completion: report)
        }
    }

    private func verifyPlant() {
        // Reads the recorded plant — its key and its target — not
        // whatever the form happens to hold now.
        guard let last = lastPlant, last.service == "redis",
              let value = try? SendTarget.parse(last.target),
              case .tcp = value else { return }
        mouth.sendNetwork(target: value,
                          payload: PayloadKit.redisCommand(
                            ["GET", last.key]),
                          framing: "raw", read: true, timeout: 5)
    }

    /// Scan → Send handoff: an open port tapped in the Scan tab
    /// arrives as a target (and, where one fits, the library probe
    /// that speaks the port's language).
    private func consumeScanHandoff() {
        guard let handed = mouth.scanHandoffTarget else { return }
        mouth.scanHandoffTarget = nil
        target = handed
        noteTargetUsed(handed)
        phoneSelection = nil
        if let name = mouth.scanHandoffPayload,
           let item = book.items.first(where: { $0.name == name }) {
            mouth.scanHandoffPayload = nil
            load(item)
        } else {
            mouth.scanHandoffPayload = nil
            toasts.show("From Scan: \(handed) is set in step 1")
        }
    }

    private func load(_ item: SavedPayload) {
        suppressClear = true
        source = item.source
        switch item.source {
        case "hex": payloadHex = item.text
        case "base64": payloadB64 = item.text
        default: payloadText = item.text
        }
        xorKey = item.xorKey
        useGzip = item.useGzip
        framing = item.framing
        customExpanded = false
        // Last, in the same synchronous block: the selection is set
        // only once every field it describes is in place, and
        // suppressClear is released on the next main-queue turn,
        // after this block (and its onChange deliveries) completes.
        selectedPayloadID = item.id
        DispatchQueue.main.async { suppressClear = false }
        toasts.show("Loaded '\(item.name)' — ready in step 3")
    }
}

// MARK: - Library sheet (the dropdown)

struct LibrarySheet: View {
    @ObservedObject var book: PayloadBook
    var onPick: (SavedPayload) -> Void
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var newName = ""

    private var filtered: [SavedPayload] {
        query.isEmpty ? book.items
            : book.items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filtered) { item in
                        Button {
                            Haptics.select()
                            onPick(item)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).foregroundStyle(.primary)
                                    Text(item.text.prefix(40).description)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                                if item.builtIn {
                                    Text("built-in")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(item.source)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { filtered[$0] }
                        for item in doomed {
                            if let index = book.items.firstIndex(of: item) {
                                book.remove(at: IndexSet(integer: index))
                            }
                        }
                    }
                    if !book.missingBuiltIns.isEmpty {
                        Button("Restore built-ins") {
                            Haptics.tap()
                            book.restoreBuiltIns()
                        }
                    }
                } header: {
                    Text("Tap a payload to load it")
                }

                Section(header: Text("Save the current payload")) {
                    HStack {
                        TextField("Name", text: $newName)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Button("Save") {
                            Haptics.tap()
                            onSave(newName)
                            newName = ""
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(
                            in: .whitespaces).isEmpty)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search payloads")
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Payload library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Mouth log sheet

struct MouthLogSheet: View {
    @EnvironmentObject private var mouth: Mouth
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if mouth.sendLines.isEmpty {
                    Text("Nothing yet — sends, replies, and listener "
                         + "events land here.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(mouth.sendLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Mouth log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) {
                        Haptics.tap()
                        mouth.clearSendLog()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                if FileManager.default.fileExists(
                    atPath: Mouth.exchangesURL.path) {
                    ToolbarItem(placement: .bottomBar) {
                        ShareLink(item: Mouth.exchangesURL) {
                            Label("Export exchange history (.jsonl)",
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            Haptics.tap()
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete history",
                                  systemImage: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete the exchange history?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible) {
                Button("Delete "
                       + (Mouth.exchangeHistoryDescription()
                          ?? "history"),
                       role: .destructive) {
                    mouth.deleteExchangeHistory()
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The .jsonl holding every send, scan, sweep, "
                     + "DNS lookup, snatch, and dissection is "
                     + "deleted from this phone. This cannot be "
                     + "undone.")
            }
        }
    }
}

// MARK: - Serve

struct ServeView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage("serveUseTCP") private var useTCP = true
    @AppStorage("serveTcpPort") private var tcpPort = "9000"
    @AppStorage("serveUseUDP") private var useUDP = false
    @AppStorage("serveUdpPort") private var udpPort = "9001"
    @AppStorage("serveUseHTTP") private var useHTTP = false
    @AppStorage("serveHttpPort") private var httpPort = "8080"
    @AppStorage("serveReply") private var reply = "ack"
    @AppStorage("serveReplyMode") private var replyMode = "static"
    @AppStorage("serveFraming") private var framing = "raw"
    @AppStorage("stealthMode") private var stealthMode = false
    @State private var showLog = false

    private var stealthBinding: Binding<Bool> {
        Binding(get: { stealthMode },
                set: { mouth.setStealth($0); stealthMode = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Stealth"),
                        footer: Text("Everything keeps working, quietly: "
                                     + "this phone stops listing itself on "
                                     + "the Wi-Fi (no Bonjour — reachable "
                                     + "by IP address only), and arrivals "
                                     + "slip into the inbox with no banners "
                                     + "or sounds. BLE hosting must still "
                                     + "advertise to be reachable; that is "
                                     + "radio physics, not a setting.")) {
                    Toggle("Stealth mode", isOn: stealthBinding)
                }

                Section(header: Text("Listeners"),
                        footer: Text("Foreground only: iOS suspends listeners "
                                     + "when the app leaves the screen. First use "
                                     + "asks for local-network permission. While "
                                     + "TCP serving is on, other phones find this "
                                     + "one by name — no IP addresses.")) {
                    Toggle("TCP", isOn: $useTCP)
                    if useTCP {
                        TextField("TCP port", text: $tcpPort)
                            .keyboardType(.numberPad).font(.body.monospaced())
                    }
                    Toggle("UDP", isOn: $useUDP)
                    if useUDP {
                        TextField("UDP port", text: $udpPort)
                            .keyboardType(.numberPad).font(.body.monospaced())
                    }
                    Toggle("HTTP", isOn: $useHTTP)
                    if useHTTP {
                        TextField("HTTP port", text: $httpPort)
                            .keyboardType(.numberPad).font(.body.monospaced())
                    }
                    TextField("Reply (blank = none; HTTP answers ok)", text: $reply)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    Picker("Reply mode", selection: $replyMode) {
                        Text("Fixed reply").tag("static")
                        Text("Echo what arrived").tag("echo")
                    }
                    Picker("Framing", selection: $framing) {
                        Text("raw").tag("raw")
                        Text("len prefix").tag("len")
                        Text("json envelope").tag("json")
                    }
                    if let error = mouth.serveError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    if mouth.serveRunning {
                        Button(role: .destructive) {
                            Haptics.tap()
                            mouth.stopServe()
                        } label: {
                            Label("Stop serving", systemImage: "stop.circle.fill")
                        }
                    } else {
                        Button {
                            Haptics.tap()
                            start()
                        } label: {
                            Label("Start serving", systemImage: "play.circle.fill")
                        }
                    }
                    if mouth.serveRunning {
                        if mouth.stealth {
                            Text("Stealth: unlisted. Reachable only at "
                                 + "\(Mouth.localIPAddress().map { "tcp://\($0):\(tcpPort)" } ?? "this phone's IP address") "
                                 + "for anyone who already knows it.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if useTCP {
                            Text("Other phones see this one as "
                                 + "'\(UIDevice.current.name)' in their "
                                 + "Nearby phones list.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(header: Text("Inbox")) {
                    if mouth.inbox.isEmpty {
                        Text("Nothing received yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(mouth.inbox) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("\(item.transport) · \(item.data.count) bytes")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(item.at, style: .time)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.peer).font(.caption2.monospaced())
                                .foregroundStyle(.tertiary).lineLimit(1)
                            Text(PayloadKit.hexdump(item.data))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if let text = PayloadKit.printableText(item.data) {
                                Text(text).font(.caption)
                            }
                        }
                        .contextMenu {
                            if let text = PayloadKit.printableText(item.data) {
                                Button {
                                    UIPasteboard.general.string = text
                                    toasts.show("Copied the payload text")
                                } label: {
                                    Label("Copy text", systemImage: "doc.on.doc")
                                }
                            }
                            Button {
                                UIPasteboard.general.string = item.data
                                    .map { String(format: "%02x", $0) }.joined()
                                toasts.show("Copied the payload as hex")
                            } label: {
                                Label("Copy hex", systemImage: "number")
                            }
                        }
                    }
                    if !mouth.inbox.isEmpty {
                        HStack {
                            ShareLink(item: inboxFile()) {
                                Label("Share inbox (.jsonl)", systemImage: "square.and.arrow.up")
                            }
                            Spacer()
                            Button("Clear", role: .destructive) {
                                Haptics.tap()
                                mouth.clearInbox()
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Serve")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showLog = true
                    } label: {
                        Label("Log", systemImage: "scroll")
                    }
                }
            }
            .sheet(isPresented: $showLog) {
                MouthLogSheet()
            }
        }
    }

    private func start() {
        mouth.startServe(tcpPort: useTCP ? Int(tcpPort) : nil,
                         udpPort: useUDP ? Int(udpPort) : nil,
                         httpPort: useHTTP ? Int(httpPort) : nil,
                         reply: reply, framing: framing,
                         echo: replyMode == "echo")
    }

    private func inboxFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-hack-inbox.jsonl")
        try? (mouth.inboxJSONL + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}


/// A Form section whose header is a tappable menu title: tap
/// to open or fold away the whole feature, chevron showing the
/// way. The open state is the caller's (persisted), so the Send
/// tab remembers which tools you keep out and which you keep
/// folded — the tab opens as a menu, not a scroll marathon.
private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    @ViewBuilder var content: () -> Content

    init(_ title: String, isOpen: Binding<Bool>,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isOpen = isOpen
        self.content = content
    }

    var body: some View {
        Section {
            if isOpen { content() }
        } header: {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOpen.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
