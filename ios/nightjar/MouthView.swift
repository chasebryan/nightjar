import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Send and Serve tabs — the mouth's face. Everything here is a
/// thin skin over `Mouth` (Mouth.swift); nothing transmits except from
/// these buttons.

// MARK: - Send

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

    /// The exact bytes a send would emit right now, for the preview.
    private var previewData: Data? {
        try? PayloadKit.build(source: source, text: payloadText,
                              hex: payloadHex, b64: payloadB64,
                              xorSpec: xorKey, useGzip: useGzip)
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
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Send")
            .onAppear { mouth.startBrowsing() }
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
                    if let data = build() {
                        mouth.sendToPhone(name: phone, payload: data,
                                          framing: framing, read: readReply,
                                          timeout: 5)
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
                        sendNetwork(value)
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

    private func build() -> Data? {
        do {
            return try PayloadKit.build(source: source, text: payloadText, hex: payloadHex,
                                        b64: payloadB64, xorSpec: xorKey, useGzip: useGzip)
        } catch {
            showError = error.localizedDescription
            return nil
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
        selectedPayloadID = book.items.last?.id
        toasts.show("Saved '\(trimmed)' to the library")
    }

    /// Manual edits turn a library pick back into a custom payload —
    /// except while `load` itself is doing the editing.
    private func unselectIfEditing() {
        if !suppressClear { selectedPayloadID = nil }
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
        selectedPayloadID = item.id
        customExpanded = false
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
                }
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
                         reply: reply, framing: framing)
    }

    private func inboxFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-hack-inbox.jsonl")
        try? (mouth.inboxJSONL + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
