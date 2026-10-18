import SwiftUI
import UniformTypeIdentifiers

/// The Helm — a remote control for the operator's OWN gear.
///
/// The Flipper audit's one honest heir: Flipper points an
/// infrared eye at anything in the room; this phone has no
/// such eye, and this app does not reach for other people's
/// devices. What it has is a mouth — Wake-on-LAN, HTTP,
/// MQTT, BLE writes, every payload in the book — and the
/// Helm gathers that lawful control into named remotes
/// with buttons, the way a universal remote gathers a
/// living room. A button is a payload from the book, a
/// target it belongs to, and a label. Pressing it fires
/// through the same build-and-send path the Send tab uses;
/// nothing here speaks a transport the mouth doesn't
/// already speak, and nothing is aimed anywhere the
/// operator didn't write down themselves.
struct HelmButton: Codable, Identifiable {
    var id: String
    var label: String
    var target: String
    var payloadName: String
    var method: String = "POST"
}

struct HelmRemote: Codable, Identifiable {
    var id: String
    var name: String
    var buttons: [HelmButton] = []
}

enum HelmStore {
    static let key = "helmRemotes.v1"

    static func load() -> [HelmRemote] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder()
                .decode([HelmRemote].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ remotes: [HelmRemote]) {
        if let data = try? JSONEncoder().encode(remotes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func exportURL(_ remotes: [HelmRemote]) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(remotes)
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-helm.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func decode(_ data: Data) -> [HelmRemote]? {
        try? JSONDecoder().decode([HelmRemote].self, from: data)
    }
}

/// Firing a button: the Send tab's own path, borrowed
/// whole — build the book payload (templates substituted
/// against the target, text source only), parse the
/// target, and route it the way step 3 routes it.
enum HelmFire {
    static func fire(_ button: HelmButton,
                     book: PayloadBook, mouth: Mouth) -> String {
        guard let payload = book.items.first(where: {
            $0.name == button.payloadName
        }) else {
            return "No payload named “\(button.payloadName)” "
                + "is in the book"
        }
        let built: Data
        do {
            built = try PayloadKit.build(
                source: payload.source,
                text: payload.source == "text"
                    ? PayloadKit.substitute(payload.text,
                        targetText: button.target)
                    : payload.text,
                hex: payload.source == "hex" ? payload.text : "",
                b64: payload.source == "base64" ? payload.text : "",
                xorSpec: payload.xorKey,
                useGzip: payload.useGzip)
        } catch {
            return "The payload would not build: "
                + error.localizedDescription
        }
        if button.target.hasPrefix("phone:") {
            let name = String(button.target.dropFirst(6))
            mouth.sendToPhone(name: name, payload: built,
                              framing: payload.framing,
                              read: true, timeout: 5)
            Journal.log("helm", "fired",
                        "\(button.label) → \(button.target)")
            return "Fired \(button.label) at \(name)"
        }
        let target: SendTarget
        do {
            target = try SendTarget.parse(button.target)
        } catch {
            return "That target does not parse: "
                + error.localizedDescription
        }
        switch target {
        case .http(_, _):
            mouth.sendHTTP(target: target, payload: built,
                           framing: payload.framing,
                           method: button.method, timeout: 10)
        case .tcp(_, _, _), .udp(_, _):
            mouth.sendNetwork(target: target, payload: built,
                              framing: payload.framing,
                              read: true, timeout: 5)
        case .bleBeacon, .bleGatt, .bleWrite(_):
            return "BLE buttons fire from the Send tab "
                + "in this build — the Helm speaks network"
        }
        Journal.log("helm", "fired",
                    "\(button.label) → \(button.target)")
        return "Fired \(button.label) → \(button.target)"
    }
}

struct HelmButtonDraft: Identifiable {
    var id = UUID()
    var remoteID: String
    var label = ""
    var target = ""
    var payloadName = ""
    var method = "POST"
}

struct HelmView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var book = PayloadBook()
    @State private var remotes: [HelmRemote] = HelmStore.load()
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var showNewRemote = false
    @State private var newRemoteName = ""
    @State private var editingButton: HelmButtonDraft?
    @State private var remoteToDelete: HelmRemote?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Remotes for your own gear. A button "
                        + "is a payload from the book, aimed "
                        + "where you wrote — Wake-on-LAN, an "
                        + "HTTP command, an MQTT word, any "
                        + "send the mouth knows. Nothing here "
                        + "reaches for a device you did not "
                        + "name yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(remotes) { remote in
                    Section(remote.name) {
                        ForEach(remote.buttons) { button in
                            Button {
                                Haptics.tap()
                                toasts.show(HelmFire.fire(
                                    button, book: book,
                                    mouth: mouth))
                            } label: {
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text(button.label)
                                    Text("\(button.payloadName) → "
                                        + button.target)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button("Delete",
                                       role: .destructive) {
                                    deleteButton(button,
                                                 in: remote)
                                }
                            }
                        }
                        Button {
                            Haptics.tap()
                            editingButton = HelmButtonDraft(
                                remoteID: remote.id,
                                payloadName:
                                    book.items.first?.name ?? "")
                        } label: {
                            Label("Add a button",
                                  systemImage: "plus.circle")
                        }
                        Button("Delete remote",
                               role: .destructive) {
                            remoteToDelete = remote
                        }
                        .font(.caption)
                    }
                }
                if !mouth.inbox.isEmpty {
                    Section("Learn from the inbox") {
                        Text("A payload your own gear sent you, "
                            + "kept as a button: the bytes join "
                            + "the book, and the button aims "
                            + "back at the house they came from. "
                            + "Set the port in the editor "
                            + "before you fire it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(mouth.inbox.suffix(8)) { item in
                            Button {
                                Haptics.tap()
                                learn(from: item)
                            } label: {
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text("\(item.transport) · "
                                        + item.peer)
                                        .font(.caption)
                                    Text(PayloadKit.printableText(
                                            item.data)
                                        ?? "\(item.data.count) bytes")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("The Helm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New remote") {
                            Haptics.tap()
                            showNewRemote = true
                        }
                        Button("Share remotes") {
                            Haptics.tap()
                            if let url = HelmStore
                                .exportURL(remotes) {
                                shareItem = ShareItem(items: [url])
                            }
                        }
                        Button("Import remotes") {
                            Haptics.tap()
                            showImporter = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("New remote", isPresented: $showNewRemote) {
                TextField("Name — Projector, Lab Pi…",
                          text: $newRemoteName)
                Button("Create") {
                    Haptics.tap()
                    let name = newRemoteName
                        .trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    remotes.append(HelmRemote(
                        id: UUID().uuidString, name: name))
                    HelmStore.save(remotes)
                    newRemoteName = ""
                }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Delete this remote?",
                isPresented: Binding(
                    get: { remoteToDelete != nil },
                    set: { if !$0 { remoteToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete "
                       + (remoteToDelete?.name ?? "remote"),
                       role: .destructive) {
                    if let remote = remoteToDelete {
                        remotes.removeAll {
                            $0.id == remote.id
                        }
                        HelmStore.save(remotes)
                    }
                    remoteToDelete = nil
                    Haptics.success()
                }
                Button("Cancel", role: .cancel) {
                    remoteToDelete = nil
                }
            } message: {
                Text("The remote and its buttons go — "
                    + "the payloads stay in the book.")
            }
            .sheet(item: $editingButton) { draft in
                HelmButtonEditor(draft: draft, book: book) {
                    saved in
                    keepButton(saved)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                importRemotes(result)
            }
        }
    }

    private func keepButton(_ draft: HelmButtonDraft) {
        guard let index = remotes.firstIndex(where: {
            $0.id == draft.remoteID
        }) else { editingButton = nil; return }
        remotes[index].buttons.append(HelmButton(
            id: UUID().uuidString,
            label: draft.label
                .trimmingCharacters(in: .whitespaces),
            target: draft.target
                .trimmingCharacters(in: .whitespaces),
            payloadName: draft.payloadName,
            method: draft.method))
        HelmStore.save(remotes)
        editingButton = nil
        toasts.show("Button kept — \(draft.label)")
    }

    private func deleteButton(_ button: HelmButton,
                              in remote: HelmRemote) {
        guard let index = remotes.firstIndex(where: {
            $0.id == remote.id
        }) else { return }
        remotes[index].buttons.removeAll { $0.id == button.id }
        HelmStore.save(remotes)
    }

    /// Learn: the inbox payload joins the book as a hex
    /// payload, and the button editor opens aimed back at
    /// the house it came from.
    private func learn(from item: ReceivedPayload) {
        let hex = item.data.map {
            String(format: "%02x", $0)
        }.joined(separator: " ")
        let name = "Learned — \(item.transport) \(item.peer)"
        book.add(SavedPayload(name: name, source: "hex",
                              text: hex, xorKey: "",
                              useGzip: false, framing: "raw"))
        let host = item.peer.split(separator: ":")
            .first.map(String.init) ?? item.peer
        let remoteID = remotes.first?.id ?? {
            let remote = HelmRemote(id: UUID().uuidString,
                                    name: "Learned")
            remotes.append(remote)
            HelmStore.save(remotes)
            return remote.id
        }()
        editingButton = HelmButtonDraft(
            remoteID: remoteID,
            label: name,
            target: "\(item.transport)://\(host):9000",
            payloadName: name)
        Journal.log("helm", "learned",
                    "button learned from the inbox — \(name)")
    }

    private func importRemotes(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let data = try? Data(contentsOf: url),
              let incoming = HelmStore.decode(data)
        else {
            toasts.show("That file is not a helm file",
                        error: true)
            return
        }
        for remote in incoming {
            if let index = remotes.firstIndex(where: {
                $0.id == remote.id
            }) {
                remotes[index] = remote
            } else {
                remotes.append(remote)
            }
        }
        HelmStore.save(remotes)
        toasts.show("Imported \(incoming.count) remote(s)")
    }
}

/// The button editor: label, target, a payload from the
/// book, and a method for HTTP targets.
struct HelmButtonEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var target: String
    @State private var payloadName: String
    @State private var method: String
    private let remoteID: String
    private let book: PayloadBook
    private let onKeep: (HelmButtonDraft) -> Void

    init(draft: HelmButtonDraft, book: PayloadBook,
         onKeep: @escaping (HelmButtonDraft) -> Void) {
        _label = State(initialValue: draft.label)
        _target = State(initialValue: draft.target)
        _payloadName = State(initialValue: draft.payloadName)
        _method = State(initialValue: draft.method)
        self.remoteID = draft.remoteID
        self.book = book
        self.onKeep = onKeep
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label — Power on, Reboot…",
                          text: $label)
                TextField("Target — tcp://…, udp://…, "
                            + "https://…, phone:Name",
                          text: $target)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.body.monospaced())
                Picker("Payload", selection: $payloadName) {
                    ForEach(book.items) { item in
                        Text(item.name).tag(item.name)
                    }
                }
                Picker("Method (HTTP targets)",
                       selection: $method) {
                    ForEach(["GET", "POST", "PUT", "DELETE"],
                            id: \.self) { Text($0).tag($0) }
                }
                Section {
                    Button("Keep this button") {
                        onKeep(HelmButtonDraft(
                            remoteID: remoteID, label: label,
                            target: target,
                            payloadName: payloadName,
                            method: method))
                        dismiss()
                    }
                    .disabled(label.trimmingCharacters(
                                in: .whitespaces).isEmpty
                        || target.trimmingCharacters(
                                in: .whitespaces).isEmpty
                        || payloadName.isEmpty)
                }
            }
            .navigationTitle("Button")
        }
    }
}
