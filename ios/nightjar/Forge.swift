import JavaScriptCore
import SwiftUI
import UIKit

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
            bytes.append(UInt8(clamping: label.utf8.count))
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

/// A payload pattern of her own — or yours:
/// a template with {host}, {path}, {domain},
/// {client} and {method} holes she fills from
/// the forge's own fields. Patterns are data,
/// kept on the phone; she gains new shapes
/// without a rebuild.
struct ForgePattern: Identifiable, Codable {
    var id = UUID()
    var name: String
    var source: String
    var template: String
}

enum ForgePatternStore {
    private static let key = "skelli.forgePatterns"

    static func load() -> [ForgePattern] {
        guard let data = UserDefaults.standard
            .data(forKey: key),
              let saved = try? JSONDecoder().decode(
                  [ForgePattern].self, from: data)
        else { return [] }
        return saved
    }

    static func save(_ all: [ForgePattern]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data,
                                      forKey: key)
        }
    }
}

/// A tool she keeps: JavaScript she wrote,
/// runnable on the spot with an input string.
struct ForgeTool: Identifiable, Codable {
    var id = UUID()
    var name: String
    var code: String
}

enum ForgeToolStore {
    private static let key = "skelli.forgeTools"

    static func load() -> [ForgeTool] {
        guard let data = UserDefaults.standard
            .data(forKey: key),
              let saved = try? JSONDecoder().decode(
                  [ForgeTool].self, from: data)
        else { return [] }
        return saved
    }

    static func save(_ all: [ForgeTool]) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data,
                                      forKey: key)
        }
    }
}

struct ForgeView: View {
    @StateObject private var book = PayloadBook()
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
    @State private var codeBrief = ""
    @State private var codeLang = "Swift"
    @State private var codeDraft = ""
    @State private var codeOutput = ""
    @State private var draftingCode = false
    @State private var runningCode = false
    @State private var shareItem: ShareItem?
    @State private var customs: [ForgePattern] =
        ForgePatternStore.load()
    @State private var newPatternName = ""
    @State private var newPatternSource = "text"
    @State private var newPatternTemplate = ""
    @State private var tools: [ForgeTool] =
        ForgeToolStore.load()
    @State private var toolInput = ""
    @State private var toolOutput = ""
    @State private var toolOutputID: UUID?
    @State private var drafting = false
    @State private var draft = ""
    @State private var draftSource = "text"
    @State private var keptDraft = false

    private let patterns = [
        "HTTP request", "DNS query", "SSDP search",
        "MQTT connect", "Banner probe",
    ]

    private var isCustom: Bool {
        pattern >= patterns.count
    }

    private var built: ForgeKit.Built {
        if isCustom {
            let custom = customs[
                pattern - patterns.count]
            var text = custom.template
            let swaps: [(String, String)] = [
                ("{host}", host.isEmpty
                    ? "192.168.4.1" : host),
                ("{path}", path.isEmpty
                    ? "/" : path),
                ("{domain}", domain.isEmpty
                    ? "example.com" : domain),
                ("{client}", clientID.isEmpty
                    ? "nightjar" : clientID),
                ("{method}", method),
            ]
            for (hole, value) in swaps {
                text = text.replacingOccurrences(
                    of: hole, with: value)
            }
            return ForgeKit.Built(
                name: "Forged — " + custom.name,
                source: custom.source, text: text)
        }
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
                    Text(L("She builds; the armory keeps. Fire what she forges from the Send tab."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section(L("From her patterns")) {
                    Picker(L("Pattern"),
                           selection: $pattern) {
                        ForEach(patterns.indices,
                                id: \.self) { i in
                            Text(patterns[i]).tag(i)
                        }
                        ForEach(
                            customs.indices,
                            id: \.self) { i in
                            Text(customs[i].name)
                                .tag(patterns.count
                                     + i)
                        }
                    }
                    if pattern == 0 || isCustom {
                        TextField(L("Host or IP"),
                                  text: $host)
                        TextField(L("Path"), text: $path)
                        Picker(L("Method"),
                               selection: $method) {
                            Text(L("GET")).tag("GET")
                            Text(L("POST")).tag("POST")
                            Text(L("HEAD")).tag("HEAD")
                            Text(L("OPTIONS"))
                                .tag("OPTIONS")
                        }
                        .pickerStyle(.segmented)
                    }
                    if pattern == 1 || isCustom {
                        TextField(L("Domain"),
                                  text: $domain)
                    }
                    if pattern == 3 || isCustom {
                        TextField(L("Client ID"),
                                  text: $clientID)
                    }
                    Text(built.text)
                        .font(.system(.caption,
                                      design: .monospaced))
                    Text(String(format: L("%lld bytes · "), ForgeKit.byteCount(of: built))
                        + built.source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(L("Name for the armory"),
                              text: $keepName)
                    Button(keptPattern
                           ? "Kept in the armory"
                           : "Keep in the armory") {
                        Haptics.tap()
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
                Section(L("Her own patterns")) {
                    Text(L("Teach her a new shape: a template with {host}, {path}, {domain}, {client} and {method} holes. It joins her patterns above, hers from then on — no rebuild, nothing to break."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L("Pattern name"),
                              text: $newPatternName)
                    Picker(L("Form"),
                           selection: $newPatternSource) {
                        Text(L("Text")).tag("text")
                        Text(L("Hex")).tag("hex")
                    }
                    .pickerStyle(.segmented)
                    TextEditor(
                        text: $newPatternTemplate)
                        .font(.system(
                            .caption,
                            design: .monospaced))
                        .frame(minHeight: 80)
                    Button(L("Teach her this pattern")) {
                        Haptics.press()
                        let name = newPatternName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines)
                        guard !name.isEmpty,
                              !newPatternTemplate
                                .isEmpty
                        else { return }
                        customs.append(ForgePattern(
                            name: name,
                            source: newPatternSource,
                            template: newPatternTemplate))
                        ForgePatternStore.save(
                            customs)
                        pattern = patterns.count
                            + customs.count - 1
                        newPatternName = ""
                        newPatternTemplate = ""
                        toasts.show(
                            L("She knows it now."))
                    }
                    ForEach(customs) { custom in
                        HStack {
                            Text(custom.name)
                                .font(.callout)
                            Spacer()
                            Button(role: .destructive) {
                                customs.removeAll {
                                    $0.id == custom.id
                                }
                                ForgePatternStore.save(
                                    customs)
                                if pattern
                                    >= patterns.count
                                        + customs.count {
                                    pattern = 0
                                }
                            } label: {
                                Image(systemName:
                                    "trash")
                            }
                        }
                    }
                }
                Section(L("From a brief")) {
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
                            Text(L("Have her draft it"))
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
                        Picker(L("Form"),
                               selection: $draftSource) {
                            Text(L("Text")).tag("text")
                            Text(L("Hex")).tag("hex")
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
                Section(L("The workbench")) {
                    Text(L("Anything else she builds: tools, scripts, whole programs — drafted by her minds, held here, yours to take anywhere. JavaScript runs on the spot."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(L("Language"),
                           selection: $codeLang) {
                        ForEach(["Swift", "Python",
                                 "JavaScript",
                                 "Shell", "Other"],
                                id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    TextField(
                        "Tell her what to build…",
                        text: $codeBrief,
                        axis: .vertical)
                        .lineLimit(2...4)
                    Button {
                        draftCode()
                    } label: {
                        if draftingCode {
                            ProgressView()
                        } else {
                            Text(L("Have her build it"))
                        }
                    }
                    .disabled(draftingCode
                        || codeBrief
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines)
                            .isEmpty)
                    if !codeDraft.isEmpty {
                        TextEditor(text: $codeDraft)
                            .font(.system(
                                .caption,
                                design: .monospaced))
                            .frame(minHeight: 150)
                        HStack(spacing: 14) {
                            if codeLang
                                == "JavaScript" {
                                Button(runningCode
                                       ? "Running…"
                                       : L("Run it")) {
                                    runCode()
                                }
                                .disabled(runningCode)
                            }
                            Button(L("Copy")) {
                                Haptics.tap()
                                UIPasteboard.general
                                    .string = codeDraft
                                toasts.show(
                                    L("Copied."))
                            }
                            Button(L("Share")) {
                                shareItem = ShareItem(
                                    items: [codeDraft])
                            }
                        }
                        if codeLang == "JavaScript" {
                            Button(L("Keep as a tool")) {
                                let name = codeBrief
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines)
                                tools.append(ForgeTool(
                                    name: name.isEmpty
                                        ? "Tool"
                                        : String(name
                                            .prefix(28)),
                                    code: codeDraft))
                                ForgeToolStore.save(
                                    tools)
                                toasts.show(
                                    L("Kept as a tool — it waits below."))
                            }
                        }
                        if !codeOutput.isEmpty {
                            Text(codeOutput)
                                .font(.system(
                                    .caption,
                                    design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                if !tools.isEmpty {
                    Section(L("Her tools")) {
                        Text(L("JavaScript she keeps, runnable with an input — it arrives in her code as `input`."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L("Input for the run"),
                                  text: $toolInput)
                        ForEach(tools) { tool in
                            VStack(alignment: .leading,
                                   spacing: 4) {
                                HStack {
                                    Text(tool.name)
                                        .font(.callout)
                                    Spacer()
                                    Button(L("Run")) {
                                        runTool(tool)
                                    }
                                    Button(
                                        role: .destructive
                                    ) {
                                        tools.removeAll {
                                            $0.id == tool.id
                                        }
                                        ForgeToolStore
                                            .save(tools)
                                    } label: {
                                        Image(systemName:
                                            "trash")
                                    }
                                }
                                if toolOutputID
                                    == tool.id,
                                   !toolOutput.isEmpty {
                                    Text(toolOutput)
                                        .font(.system(
                                            .caption,
                                            design: .monospaced))
                                        .textSelection(
                                            .enabled)
                                }
                            }
                        }
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .skelliSheetList()
            .navigationTitle(L("The Forge"))
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }

    private func draftCode() {
        draftingCode = true
        codeOutput = ""
        let lang = codeLang
        let ask = codeBrief
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are Skelli, "
                    + "the operator's programming "
                    + "partner. Produce ONLY "
                    + "complete, correct, runnable "
                    + "code — no explanation, no "
                    + "code fences, no commentary. "
                    + "Language: " + lang + ".",
                prompt: ask)
            await MainActor.run {
                draftingCode = false
                guard var text = text else {
                    toasts.show(
                        L("No bench could build it."),
                        error: true)
                    return
                }
                text = text
                    .replacingOccurrences(
                        of: "```", with: "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                codeDraft = text
                let exts = ["Swift": "swift",
                            "Python": "py",
                            "JavaScript": "js",
                            "Shell": "sh",
                            "Other": "txt"]
                DeliveriesCenter.shared.add(
                    name: "Built — "
                        + String(ask.prefix(28)),
                    text: text,
                    ext: exts[lang] ?? "txt")
            }
        }
    }

    private func runTool(_ tool: ForgeTool) {
        toolOutputID = tool.id
        toolOutput = "Running…"
        let code = tool.code
        let input = toolInput
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let output = JSRunner.run(
                    code, input: input)
                DispatchQueue.main.async {
                    toolOutput = output
                }
            }
    }

    private func runCode() {
        runningCode = true
        let code = codeDraft
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let output = JSRunner.run(code)
                DispatchQueue.main.async {
                    runningCode = false
                    codeOutput = output
                }
            }
    }

    private func keep(_ built: ForgeKit.Built,
                      name: String) {
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty
            ? built.name : trimmed
        book.add(SavedPayload(
            name: finalName,
            source: built.source,
            text: built.text,
            xorKey: "", useGzip: false,
            framing: "raw"))
        DeliveriesCenter.shared.add(
            name: finalName, text: built.text,
            ext: built.source == "hex"
                ? "hex" : "txt")
        toasts.show(L("Kept in the armory."))
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
                        L("No bench could draft it."),
                        error: true)
                    return
                }
                text = text
                    .replacingOccurrences(
                        of: "```", with: "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)
                draft = text
                DeliveriesCenter.shared.add(
                    name: "Draft — "
                        + String(ask.prefix(28)),
                    text: text, ext: "txt")
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


/// Her scratch interpreter: JavaScript, run on
/// the spot inside JavaScriptCore — no network,
/// no files, a three-second leash. Output is
/// what the code logged, plus its final value.
enum JSRunner {

    static func run(_ code: String) -> String {
        run(code, input: "")
    }

    static func run(_ code: String,
                    input: String) -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result = ""
        DispatchQueue.global(qos: .userInitiated)
            .async {
                result = evaluate(code,
                                  input: input)
                semaphore.signal()
            }
        if semaphore.wait(
            timeout: .now() + 3) == .timedOut {
            return "Ran past three seconds — "
                + "the leash pulled it back."
        }
        return result
    }

    private static func evaluate(
        _ code: String,
        input: String = "") -> String {
        guard let context = JSContext() else {
            return "The JavaScript engine would not start."
        }
        var logs: [String] = []
        var failure: String?
        context.exceptionHandler = { _, exc in
            failure = exc?.toString()
        }
        let log: @convention(block)
            (JSValue) -> Void = { value in
                logs.append(
                    value.isUndefined
                        ? "" : value.toString())
            }
        context.setObject(
            log, forKeyedSubscript: "log" as NSString)
        if let literal = try? JSONEncoder()
            .encode(input),
           let text = String(
               data: literal, encoding: .utf8) {
            _ = context.evaluateScript(
                "var input = " + text + ";")
        }
        _ = context.evaluateScript(
            "var console = { log: log, "
            + "error: log, warn: log };")
        let value = context.evaluateScript(code)
        if let failure = failure {
            logs.append("Error: " + failure)
        } else if let value = value,
                  !value.isUndefined,
                  !value.isNull {
            logs.append("→ " + value.toString())
        }
        let out = logs
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return out.isEmpty ? "(ran — no output)"
            : out
    }
}
