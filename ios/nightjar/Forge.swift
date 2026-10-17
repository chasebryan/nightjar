import SwiftUI

/// Her forge: payload work built to order. From
/// her patterns she assembles real packets —
/// a DNS question with its labels counted, an
/// MQTT handshake with its lengths honest —
/// and from a plain brief her minds draft the
/// bytes. Everything forged here lands in the
/// armory, the mouth's saved payloads, ready
/// to be fired from Send like anything she
/// keeps. Nothing is sent from the forge
/// itself; it only makes, and keeps.
enum ForgeKit {

    struct Built {
        var name: String
        var source: String
        var text: String
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }

    static func byteCount(of built: Built) -> Int {
        if built.source == "hex" {
            return built.text.split(
                separator: " ").count
        }
        return built.text.utf8.count
    }

    static func http(method: String, host: String,
                     path: String, body: String)
        -> Built {
        var text = method + " "
            + (path.isEmpty ? "/" : path)
            + " HTTP/1.1\r\n"
            + "Host: " + host + "\r\n"
            + "User-Agent: nightjar-hack\r\n"
        if !body.isEmpty {
            text += "Content-Length: "
                + "\(body.utf8.count)\r\n"
        }
        text += "Connection: close\r\n\r\n" + body
        return Built(
            name: "Forged — HTTP " + method + " "
                + (path.isEmpty ? "/" : path),
            source: "text", text: text)
    }

    static func dns(host: String) -> Built {
        var bytes: [UInt8] = [
            0x1a, 0x2b, 0x01, 0x00,
            0x00, 0x01, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        ]
        for label in host.split(separator: ".") {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(
                contentsOf: label.utf8.map { $0 })
        }
        bytes.append(contentsOf: [
            0x00, 0x00, 0x01, 0x00, 0x01,
        ])
        return Built(
            name: "Forged — DNS query " + host,
            source: "hex", text: hex(bytes))
    }

    static func ssdp() -> Built {
        Built(
            name: "Forged — SSDP search",
            source: "text",
            text: "M-SEARCH * HTTP/1.1\r\n"
                + "Host: 239.255.255.250:1900\r\n"
                + "MAN: \"ssdp:discover\"\r\n"
                + "MX: 2\r\n"
                + "ST: ssdp:all\r\n\r\n")
    }

    static func mqtt(clientID: String) -> Built {
        let id = Array(clientID.utf8)
        var body: [UInt8] = [
            0x00, 0x04,
        ]
        body.append(contentsOf: "MQTT".utf8)
        body.append(contentsOf: [
            0x04, 0x02, 0x00, 0x3c,
            UInt8(id.count >> 8), UInt8(id.count & 0xff),
        ])
        body.append(contentsOf: id)
        var packet: [UInt8] = [0x10]
        var length = body.count
        repeat {
            var byte = UInt8(length & 0x7f)
            length >>= 7
            if length > 0 { byte |= 0x80 }
            packet.append(byte)
        } while length > 0
        packet.append(contentsOf: body)
        return Built(
            name: "Forged — MQTT connect "
                + clientID,
            source: "hex", text: hex(packet))
    }

    static func probe() -> Built {
        Built(
            name: "Forged — banner probe",
            source: "text", text: "\r\n")
    }
}

struct ForgeView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @Environment(\.dismiss) private var dismiss

    @State private var pattern = 0
    @State private var host = ""
    @State private var path = "/"
    @State private var method = "GET"
    @State private var domain = "example.com"
    @State private var clientID = "nightjar"
    @State private var keepName = ""
    @State private var keptPattern = false

    @State private var brief = ""
    @State private var drafting = false
    @State private var draft = ""
    @State private var draftSource = "text"
    @State private var keptDraft = false

    private let patterns = [
        "HTTP request", "DNS query", "SSDP search",
        "MQTT connect", "Banner probe",
    ]

    private var built: ForgeKit.Built {
        switch pattern {
        case 0:
            return ForgeKit.http(
                method: method,
                host: host.isEmpty
                    ? "192.168.4.1" : host,
                path: path, body: "")
        case 1:
            return ForgeKit.dns(
                host: domain.isEmpty
                    ? "example.com" : domain)
        case 2:
            return ForgeKit.ssdp()
        case 3:
            return ForgeKit.mqtt(
                clientID: clientID.isEmpty
                    ? "nightjar" : clientID)
        default:
            return ForgeKit.probe()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("She builds; the armory "
                        + "keeps. Fire what she "
                        + "forges from the Send tab.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("From her patterns") {
                    Picker("Pattern",
                           selection: $pattern) {
                        ForEach(patterns.indices,
                                id: \.self) { i in
                            Text(patterns[i]).tag(i)
                        }
                    }
                    if pattern == 0 {
                        TextField("Host or IP",
                                  text: $host)
                        TextField("Path", text: $path)
                        Picker("Method",
                               selection: $method) {
                            Text("GET").tag("GET")
                            Text("POST").tag("POST")
                            Text("HEAD").tag("HEAD")
                            Text("OPTIONS")
                                .tag("OPTIONS")
                        }
                        .pickerStyle(.segmented)
                    }
                    if pattern == 1 {
                        TextField("Domain",
                                  text: $domain)
                    }
                    if pattern == 3 {
                        TextField("Client ID",
                                  text: $clientID)
                    }
                    Text(built.text)
                        .font(.system(.caption,
                                      design: .monospaced))
                    Text("\(ForgeKit.byteCount(of: built)) "
                        + "bytes · " + built.source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Name for the armory",
                              text: $keepName)
                    Button(keptPattern
                           ? "Kept in the armory"
                           : "Keep in the armory") {
                        keep(built,
                             name: keepName)
                        keptPattern = true
                    }
                    .disabled(keptPattern)
                }
                .onChange(of: pattern) { _ in
                    keptPattern = false
                    keepName = ""
                }
                Section("From a brief") {
                    TextField(
                        "Tell her what to build…",
                        text: $brief, axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        draftIt()
                    } label: {
                        if drafting {
                            ProgressView()
                        } else {
                            Text("Have her draft it")
                        }
                    }
                    .disabled(drafting || brief
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        .isEmpty)
                    if !draft.isEmpty {
                        TextEditor(text: $draft)
                            .font(.system(.caption,
                                          design: .monospaced))
                            .frame(minHeight: 110)
                        Picker("Form",
                               selection: $draftSource) {
                            Text("Text").tag("text")
                            Text("Hex").tag("hex")
                        }
                        .pickerStyle(.segmented)
                        Button(keptDraft
                               ? "Kept in the armory"
                               : "Keep in the armory") {
                            keep(ForgeKit.Built(
                                name: "Forged — "
                                    + String(brief.prefix(28)),
                                source: draftSource,
                                text: draft),
                                 name: "")
                            keptDraft = true
                        }
                        .disabled(keptDraft)
                    }
                }
            }
            .navigationTitle("The Forge")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func keep(_ built: ForgeKit.Built,
                      name: String) {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines)
        mouth.add(SavedPayload(
            name: trimmed.isEmpty
                ? built.name : trimmed,
            source: built.source,
            text: built.text,
            xorKey: "", useGzip: false,
            framing: "raw"))
        toasts.show("Kept in the armory.")
    }

    private func draftIt() {
        drafting = true
        keptDraft = false
        let ask = brief
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are the forge "
                    + "inside nightjar-hack, a "
                    + "network instrument. The "
                    + "operator describes a "
                    + "payload; you produce ONLY "
                    + "the payload itself — raw "
                    + "protocol text, or "
                    + "space-separated hex bytes "
                    + "when the payload is "
                    + "binary. No explanation, no "
                    + "code fences, no commentary. "
                    + "If the brief is unclear, "
                    + "produce the closest "
                    + "standard probe.",
                prompt: ask)
            await MainActor.run {
                drafting = false
                guard var text = text else {
                    toasts.show(
                        "No bench could draft it.",
                        error: true)
                    return
                }
                text = text
                    .replacingOccurrences(
                        of: "```", with: "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                draft = text
                let hexish = !text.isEmpty
                    && text.allSatisfy {
                        $0.isHexDigit
                            || $0 == " "
                            || $0 == "\n"
                    }
                draftSource = hexish ? "hex" : "text"
            }
        }
    }
}
