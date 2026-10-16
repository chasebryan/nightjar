import SwiftUI

/// The Knocktalk tab: conversations carried by knock order.
///
/// The tripwire (EMCON's ear) is what makes this a conversation
/// rather than a flare gun — both phones listen while they
/// knock, so delivery confirms itself, holes get named and
/// re-knocked, and a thread reads like a thread.
struct KnockChatView: View {
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var chat: KnockChat
    @State private var newPeer = ""
    @State private var openedPeer: String?
    @State private var navActive = false
    @State private var keyDraft = ""
    @State private var keyHex: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if emcon.tripwireOn {
                        Label("Listening — the tripwire is up, so "
                              + "this phone hears knocks, ACKs and "
                              + "replies.",
                              systemImage: "ear")
                            .font(.callout)
                    } else {
                        Label("Deaf right now — raise EMCON so the "
                              + "tripwire listens. You can still "
                              + "knock messages out, but nothing "
                              + "can knock back.",
                              systemImage: "ear.trianglebadge.exclamationmark")
                            .font(.callout)
                    }
                }
                if keyHex == nil {
                    keySetupSection
                } else {
                    keySection
                }
                suiteSection
                threadsSection
                retentionSection
            }
            .navigationTitle("Knocktalk")
            .background {
                // iOS 16 navigation: one hidden link, driven by
                // the Open button; thread rows are plain links.
                NavigationLink(isActive: $navActive) {
                    ConversationView(peer: openedPeer ?? "")
                } label: {
                    EmptyView()
                }
                .hidden()
            }
            .onAppear {
                if keyHex == nil { keyHex = KnockKeyStore.keyHex }
                chat.purge()
            }
        }
    }

    private var keySetupSection: some View {
        Section(header: Text("Pairing key"),
                footer: Text("One 256-bit key, both phones, kept "
                             + "in the Keychain. Generate it on "
                             + "one phone and carry it to the "
                             + "other — or paste the one it made.")) {
            Text("No key yet: Knocktalk seals with ChaCha20-"
                 + "Poly1305, and without the shared key nothing "
                 + "here can be sealed or opened.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                let hex = KnockKeyStore.generate()
                KnockKeyStore.keyHex = hex
                keyHex = hex
            } label: {
                Label("Generate a pairing key", systemImage: "key")
            }
            TextField("paste a pairing key (64 hex digits)",
                      text: $keyDraft)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.caption.monospaced())
            Button("Save the pasted key") {
                let hex = keyDraft
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if (try? PayloadKit.decodeHex(hex))?.count == 32 {
                    KnockKeyStore.keyHex = hex
                    keyHex = hex
                    keyDraft = ""
                }
            }
            .disabled((try? PayloadKit.decodeHex(
                keyDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines)))?.count != 32)
        }
    }

    private var keySection: some View {
        Section(header: Text("Pairing key")) {
            HStack {
                Text("Fingerprint")
                Spacer()
                Text(KnockKeyStore.fingerprint(ofHex: keyHex!))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            Button {
                let hex = KnockKeyStore.generate()
                KnockKeyStore.keyHex = hex
                keyHex = hex
            } label: {
                Text("Replace the pairing key")
            }
            Button(role: .destructive) {
                KnockKeyStore.keyHex = nil
                keyHex = nil
            } label: {
                Text("Forget the pairing key")
            }
        }
    }

    private var suiteSection: some View {
        Section(header: Text("Sending encryption"),
                footer: Text("Your choice rides inside every "
                             + "fragment you knock. The other "
                             + "phone opens your messages with the "
                             + "suite you picked — its own setting "
                             + "governs only what IT sends. Nothing "
                             + "has to match.")) {
            Picker("Suite for messages I send",
                   selection: Binding(
                    get: { chat.sendSuite },
                    set: { chat.setSendSuite($0) })) {
                ForEach(Knocktalk.suiteNames.indices, id: \.self) {
                    index in
                    Text(Knocktalk.suiteNames[index]).tag(index)
                }
            }
        }
    }

    private var threadsSection: some View {
        Section(header: Text("Conversations")) {
            HStack {
                TextField("peer address (192.168.4.21)",
                          text: $newPeer)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button("Open") {
                    openedPeer = KnockChat.peerKey(newPeer)
                    newPeer = ""
                    navActive = true
                }
                .disabled(newPeer
                    .trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if chat.peersByRecency.isEmpty {
                Text("No conversations yet. Open one by address — "
                     + "the other phone needs the app, the same "
                     + "pairing key, and EMCON up.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(chat.peersByRecency, id: \.self) { peer in
                NavigationLink {
                    ConversationView(peer: peer)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            if let last = chat.threads[peer]?.last {
                                Text((last.outgoing ? "You: " : "")
                                     + last.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        threadBadge(peer)
                    }
                }
            }
        }
    }

    @ViewBuilder private func threadBadge(_ peer: String) -> some View {
        let messages = chat.threads[peer] ?? []
        if messages.contains(where: {
            $0.outgoing && $0.state == "failed" }) {
            Text("failed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if messages.contains(where: {
            $0.outgoing
                && ($0.state == "sending" || $0.state == "awaiting")
        }) {
            Text("awaiting")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var retentionSection: some View {
        Section(header: Text("Burn timer"),
                footer: Text("Checked at launch, when this tab "
                             + "opens, and when a message lands — "
                             + "a closed app cannot burn on "
                             + "schedule. The journal never held "
                             + "contents; this is the only copy.")) {
            Picker("Auto-delete messages",
                   selection: Binding(
                    get: { chat.retentionHours },
                    set: { chat.setRetention(hours: $0) })) {
                Text("after 1 hour").tag(1.0)
                Text("after 6 hours").tag(6.0)
                Text("after 24 hours").tag(24.0)
                Text("after 7 days").tag(168.0)
                Text("never").tag(0.0)
            }
        }
    }
}

/// One conversation: bubbles, delivery states, a composer.
struct ConversationView: View {
    let peer: String
    @EnvironmentObject private var chat: KnockChat
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var tooLong = false

    private var messages: [KnockChat.ChatMessage] {
        chat.threads[peer] ?? []
    }

    private var draftSealedBytes: Int {
        draft.utf8.count + 28
    }

    var body: some View {
        List {
            if messages.isEmpty {
                Text("Nothing yet. The first message knocks the "
                     + "whole conversation open — fragments, "
                     + "about twelve seconds each, and the other "
                     + "phone knocks its ACK back the same way.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(messages) { message in
                HStack {
                    if message.outgoing { Spacer(minLength: 40) }
                    VStack(alignment: message.outgoing
                           ? .trailing : .leading, spacing: 2) {
                        Text(message.text)
                            .font(.callout)
                        Text(caption(for: message))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if message.outgoing,
                           message.state == "failed" {
                            Button("Resend") {
                                if let key = KnockKeyStore.key {
                                    chat.resend(messageID: message.id,
                                                key: key)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    if !message.outgoing { Spacer(minLength: 40) }
                }
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(peer)
        .toolbar {
            if !messages.isEmpty {
                Button(role: .destructive) {
                    chat.clearThread(peer)
                    dismiss()
                } label: {
                    Text("Clear thread")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("knock a message", text: $draft,
                              axis: .vertical)
                        .lineLimit(1...4)
                        .disableAutocorrection(true)
                    Button {
                        if let key = KnockKeyStore.key {
                            if chat.send(text: draft, to: peer,
                                         key: key) {
                                draft = ""
                                tooLong = false
                            } else {
                                tooLong = true
                            }
                        }
                    } label: {
                        Image(systemName: "hand.tap.fill")
                            .font(.title3)
                    }
                    .disabled(draft.isEmpty
                              || KnockKeyStore.key == nil)
                }
                HStack {
                    Text(draftSealedBytes
                         <= Knocktalk.maxSealedBytes
                         ? "≈\(draft.utf8.count + 28) sealed bytes "
                           + "of \(Knocktalk.maxSealedBytes)"
                         : "too long for one knock stream")
                        .font(.caption2)
                        .foregroundStyle(tooLong ? .red : .secondary)
                    Spacer()
                    if chat.sender.sending {
                        Text("knocking \(chat.sender.sent)/"
                             + "\(chat.sender.total)…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func caption(for message: KnockChat.ChatMessage) -> String {
        let time = message.when.formatted(date: .omitted,
                                           time: .shortened)
        guard message.outgoing else { return time }
        switch message.state {
        case "sending": return "\(time) · knocking…"
        case "awaiting": return "\(time) · sent, awaiting ACK"
        case "delivered": return "\(time) · delivered ✓"
        case "failed": return "\(time) · not confirmed"
        default: return time
        }
    }
}
