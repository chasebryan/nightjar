import SwiftUI
import UniformTypeIdentifiers

/// The Send and Serve tabs — the mouth's face. Everything here is a
/// thin skin over `Mouth` (Mouth.swift); nothing transmits except from
/// these buttons.

// MARK: - Send

struct SendView: View {
    @EnvironmentObject private var mouth: Mouth
    @StateObject private var book = PayloadBook()
    @State private var libraryName = ""
    @State private var target = "tcp://127.0.0.1:9000"
    @State private var source = "text"
    @State private var payloadText = "hello"
    @State private var payloadHex = "68 65 6c 6c 6f"
    @State private var payloadB64 = "aGVsbG8="
    @State private var xorKey = ""
    @State private var useGzip = false
    @State private var framing = "raw"
    @State private var method = "POST"
    @State private var readReply = true
    @State private var beaconName = "nightjar-post"
    @State private var showError: String?

    private var parsed: Result<SendTarget, Error> {
        Result { try SendTarget.parse(target) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Target")) {
                    TextField("tcp://host:port", text: $target)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.body.monospaced())
                    switch parsed {
                    case .failure(let error):
                        Text(error.localizedDescription)
                            .font(.caption).foregroundStyle(.red)
                    case .success(let value):
                        Text(describe(value)).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Payload")) {
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
                    Picker("Framing", selection: $framing) {
                        Text("raw").tag("raw")
                        Text("len prefix").tag("len")
                        Text("json envelope").tag("json")
                    }
                }

                handoffSection

                actionSection

                librarySection

                Section(header: Text("Log")) {
                    if mouth.sendLines.isEmpty {
                        Text("Nothing sent yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(Array(mouth.sendLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                    if !mouth.sendLines.isEmpty {
                        Button("Clear log") { mouth.clearSendLog() }
                    }
                }
            }
            .navigationTitle("Send")
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
                    if let data = build() { mouth.writeHandoff(payload: data) }
                } label: {
                    Label("Write to \(label)", systemImage: "paperplane.fill")
                }
                Button("Dismiss", role: .cancel) { mouth.clearPendingWrite() }
            }
        }
    }

    private var librarySection: some View {
        Section(header: Text("Library")) {
            HStack {
                TextField("Name this payload", text: $libraryName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Save") { saveToLibrary() }
                    .disabled(libraryName.trimmingCharacters(
                        in: .whitespaces).isEmpty)
            }
            if book.items.isEmpty {
                Text("Saved payloads live here — your greatest hits, "
                     + "one tap to load.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(book.items) { item in
                Button { load(item) } label: {
                    HStack {
                        Text(item.name).foregroundStyle(.primary)
                        Spacer()
                        Text("\(item.source) · \(item.text.count) ch")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { book.remove(at: $0) }
        }
    }

    private func saveToLibrary() {
        let name = libraryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let text = source == "text" ? payloadText
            : source == "hex" ? payloadHex : payloadB64
        book.add(SavedPayload(name: name, source: source, text: text,
                              xorKey: xorKey, useGzip: useGzip,
                              framing: framing))
        libraryName = ""
    }

    private func load(_ item: SavedPayload) {
        source = item.source
        switch item.source {
        case "hex": payloadHex = item.text
        case "base64": payloadB64 = item.text
        default: payloadText = item.text
        }
        xorKey = item.xorKey
        useGzip = item.useGzip
        framing = item.framing
    }

    @ViewBuilder private var actionSection: some View {
        switch parsed {
        case .success(let value) where isNetwork(value):
            Section {
                Picker("Method (http)", selection: $method) {
                    ForEach(["POST", "GET", "PUT", "PATCH", "DELETE", "HEAD"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Toggle("Read a reply", isOn: $readReply)
                Button {
                    sendNetwork(value)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
            }
        case .success(.bleBeacon):
            Section(header: Text("BLE beacon")) {
                TextField("Advertised name", text: $beaconName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Text("The payload rides in service data for FFF0 — the slot "
                     + "iOS lets an app set. Foreground only, and small: "
                     + "keep it under ~20 bytes.")
                    .font(.caption).foregroundStyle(.secondary)
                if mouth.beaconOn {
                    Button(role: .destructive) { mouth.stopBeacon() } label: {
                        Label("Stop beacon", systemImage: "stop.circle.fill")
                    }
                } else {
                    Button {
                        if let data = build() { mouth.startBeacon(payload: data, name: beaconName) }
                    } label: {
                        Label("Start beacon", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
        case .success(.bleGatt):
            Section(header: Text("GATT host")) {
                TextField("Advertised name", text: $beaconName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Text("Hosts service FFF0 with characteristic FFF1 holding "
                     + "the payload: readable, writable, notifiable. Writes "
                     + "from a central land in the Serve inbox.")
                    .font(.caption).foregroundStyle(.secondary)
                if mouth.gattHostOn {
                    Button(role: .destructive) { mouth.stopGattHost() } label: {
                        Label("Stop hosting", systemImage: "stop.circle.fill")
                    }
                } else {
                    Button {
                        if let data = build() { mouth.startGattHost(payload: data, name: beaconName) }
                    } label: {
                        Label("Host payload", systemImage: "server.rack")
                    }
                }
            }
        case .success(.bleWrite(_)):
            Section(header: Text("Write to a peripheral")) {
                Text("iOS hides MAC addresses, so pick the device by name "
                     + "from a scan — the Python side's ble-write://ADDR "
                     + "becomes a tap here.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
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
                            if let data = build() { mouth.write(to: device, payload: data) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        default:
            EmptyView()
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
}

// MARK: - Serve

struct ServeView: View {
    @EnvironmentObject private var mouth: Mouth
    @State private var useTCP = true
    @State private var tcpPort = "9000"
    @State private var useUDP = false
    @State private var udpPort = "9001"
    @State private var useHTTP = false
    @State private var httpPort = "8080"
    @State private var reply = "ack"
    @State private var framing = "raw"

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Listeners"),
                        footer: Text("Foreground only: iOS suspends listeners "
                                     + "when the app leaves the screen. First use "
                                     + "asks for local-network permission.")) {
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
                        Button(role: .destructive) { mouth.stopServe() } label: {
                            Label("Stop serving", systemImage: "stop.circle.fill")
                        }
                    } else {
                        Button { start() } label: {
                            Label("Start serving", systemImage: "play.circle.fill")
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
                    }
                    if !mouth.inbox.isEmpty {
                        HStack {
                            ShareLink(item: inboxFile()) {
                                Label("Share inbox (.jsonl)", systemImage: "square.and.arrow.up")
                            }
                            Spacer()
                            Button("Clear", role: .destructive) { mouth.clearInbox() }
                        }
                    }
                }
            }
            .navigationTitle("Serve")
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
