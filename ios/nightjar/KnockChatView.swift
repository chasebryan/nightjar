import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Knocktalk tab: conversations carried by knock order.
///
/// The tripwire (EMCON's ear) is what makes this a conversation
/// rather than a flare gun — both phones listen while they
/// knock, so delivery confirms itself, holes get named and
/// re-knocked, and a thread reads like a thread.
struct KnockChatView: View {
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var chat: KnockChat
    @EnvironmentObject private var mouth: Mouth
    @State private var newPeer = ""
    @AppStorage("coin.lockKnocktalk") private var coinLock = false
    @State private var coinUnlocked = false
    @State private var coinNote = ""
    @State private var openedPeer: String?
    @State private var navActive = false
    @State private var keyDraft = ""
    @State private var keyHex: String?
    @StateObject private var chirpSender = ChirpSender()
    @StateObject private var chirpListener = ChirpListener()
    @State private var chirpDraft = ""
    @State private var chirpWavURL: URL?
    @State private var chirpImporting = false
    @State private var chirpFileNote: String?

    /// One door for chirps, however they arrived — sung live,
    /// or decoded from a mailed file.
    private func openChirpPayload(_ data: Data) -> Bool {
        guard let key = KnockKeyStore.key else { return false }
        for suite in [Knocktalk.suiteChaCha,
                      Knocktalk.suiteAESGCM] {
            if let text = Knocktalk.open(
                sealed: data, key: key, suite: suite) {
                chat.receiveChirp(text: text)
                return true
            }
        }
        return false
    }
    @StateObject private var brushVisitor = BrushVisitor()
    @State private var brushDraft = ""
    @State private var blinkDraft = ""
    @State private var blinkFrames: [String] = []
    @State private var blinkShowing = false
    @State private var boardSeen: [String: Date] = [:]
    @State private var boardChecked = false
    @State private var capsuleDraft = ""
    @State private var capsuleDelay: Double = 600
    @State private var capsuleBlob: String?
    @State private var capsuleStatus = ""
    @State private var capsuleBusy = false
    @State private var capsulePaste = ""
    @State private var capsuleProgress: Double?
    @State private var capsuleNote = ""
    @State private var grindControl = GrindControl()
    @State private var blinkReceiving = false
    @State private var shareItem: ShareItem?
    @State private var confirmClearThreads = false
    @State private var confirmForgetCadence = false

    /// A blink names its suite in every frame; open with the
    /// carried suite first, the other second.
    private func openBlinkPayload(_ data: Data,
                                  suite: Int) -> Bool {
        guard let key = KnockKeyStore.key else { return false }
        let order = suite == Knocktalk.suiteAESGCM
            ? [Knocktalk.suiteAESGCM, Knocktalk.suiteChaCha]
            : [Knocktalk.suiteChaCha, Knocktalk.suiteAESGCM]
        for candidate in order {
            if let text = Knocktalk.open(
                sealed: data, key: key, suite: candidate) {
                chat.receiveBlink(text: text)
                return true
            }
        }
        return false
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if emcon.tripwireOn {
                        Label(L("Listening — the tripwire is up, so this phone hears knocks, ACKs and replies."),
                              systemImage: "ear")
                            .font(.callout)
                    } else {
                        Label(L("Deaf right now — raise EMCON so the tripwire listens. You can still knock messages out, but nothing can knock back."),
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
                cadenceSection
                VoiceThrowSection(center: emcon.voiceThrow,
                                  chat: chat)
                relaySection
                chirpSection
                brushSection
                blinkSection
                flareSection
                capsuleSection
                TestamentSectionView(store: TestamentStore.shared)
                if coinLock && !coinUnlocked {
                    coinLockSection
                } else {
                    threadsSection
                }
                retentionSection
                housekeepingSection
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle(L("Knocktalk"))
            .onAppear {
                if keyHex == nil { keyHex = KnockKeyStore.keyHex }
                chat.purge()
                chirpListener.onPayload = { data in
                    openChirpPayload(data)
                }
                brushVisitor.onPayload = { data in
                    guard let key = KnockKeyStore.key
                    else { return false }
                    for suite in [Knocktalk.suiteChaCha,
                                  Knocktalk.suiteAESGCM] {
                        if let text = Knocktalk.open(
                            sealed: data, key: key, suite: suite) {
                            chat.receiveBrush(text: text)
                            Journal.log(
                                "brush", "pickup",
                                "drop opened — \(text.count) chars")
                            return true
                        }
                    }
                    return false
                }
            }
        }
        .sheet(isPresented: $navActive) {
            // A conversation is a sheet, not a push — the
            // same cure Colours and the dossiers took for
            // the doubled back chevron inside More-tab
            // screens. One stack, one Done.
            NavigationStack {
                ConversationView(peer: openedPeer ?? "")
                    .toolbar {
                        ToolbarItem(
                            placement: .confirmationAction) {
                            Button(L("Done")) {
                                navActive = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $blinkShowing) {
            BlinkSenderView(frames: blinkFrames)
        }
        .sheet(isPresented: $blinkReceiving) {
            BlinkReceiverView { data, suite in
                openBlinkPayload(data, suite: suite)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .confirmationDialog(
            "Clear every Knocktalk thread?",
            isPresented: $confirmClearThreads,
            titleVisibility: .visible) {
            Button(L("Delete all threads"), role: .destructive) {
                chat.clearAllThreads()
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("Every conversation and cadence note is deleted. The pairing key stays — the house forgets the conversations, not how to have them."))
        }
        .confirmationDialog(
            "Forget every cadence profile?",
            isPresented: $confirmForgetCadence,
            titleVisibility: .visible) {
            Button(L("Forget all profiles"), role: .destructive) {
                CadenceSeal.resetAll()
            }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("The timing fingerprints learned for every peer are deleted. Cadence learns each hand again from its next knocks."))
        }
        .fileImporter(
            isPresented: $chirpImporting,
            allowedContentTypes: [.wav, .mp3, .mpeg4Audio,
                                  .audio]) { result in
            guard case .success(let url) = result else { return }
            chirpFileNote = "decoding…"
            DispatchQueue.global(qos: .userInitiated).async {
                let scoped = url
                    .startAccessingSecurityScopedResource()
                let payload = ChirpMail.decode(fileURL: url)
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
                DispatchQueue.main.async {
                    if let payload = payload {
                        chirpFileNote = openChirpPayload(payload)
                            ? "decoded — filed in the Chirp "
                                + "thread below"
                            : "that file carries a chirp that "
                                + "does not open with your "
                                + "pairing key"
                    } else {
                        chirpFileNote = "no complete chirp "
                            + "heard in that file"
                    }
                }
            }
        }

    }

    private var keySetupSection: some View {
        Section(header: Text(L("Pairing key")),
                footer: Text(L("One 256-bit key, both phones, kept in the Keychain. Generate it on one phone and carry it to the other — or paste the one it made."))) {
            Text(L("No key yet: Knocktalk seals with ChaCha20-Poly1305, and without the shared key nothing here can be sealed or opened."))
                .font(.callout).foregroundStyle(.secondary)
            Button {
                let hex = KnockKeyStore.generate()
                KnockKeyStore.keyHex = hex
                keyHex = hex
            } label: {
                Label(L("Generate a pairing key"), systemImage: "key")
            }
            TextField(L("paste a pairing key (64 hex digits)"),
                      text: $keyDraft)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.caption.monospaced())
            Button(L("Save the pasted key")) {
                Haptics.tap()
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
        Section(header: Text(L("Pairing key"))) {
            HStack {
                Text(L("Fingerprint"))
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
                Text(L("Replace the pairing key"))
            }
            Button(role: .destructive) {
                KnockKeyStore.keyHex = nil
                keyHex = nil
            } label: {
                Text(L("Forget the pairing key"))
            }
        }
    }

    private var suiteSection: some View {
        Section(header: Text(L("Sending encryption")),
                footer: Text(L("Your choice rides inside every fragment you knock. The other phone opens your messages with the suite you picked — its own setting governs only what IT sends. Nothing has to match."))) {
            Picker(L("Suite for messages I send"),
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

    @AppStorage("cadenceSealOn") private var cadenceSealOn = true

    private var cadenceSection: some View {
        Section(header: Text(L("Cadence Seal — the second factor is rhythm")),
                footer: Text(L("The pairing key decides what opens. Cadence decides what is believed: the seal learns a peer's knock timing from its first messages, then flags any later message that arrives in foreign hands — right key, wrong rhythm. It never blocks a message; it marks it, and the night log remembers."))) {
            Toggle(L("Cadence Seal"), isOn: $cadenceSealOn)
            ForEach(chat.peersByRecency, id: \.self) { peer in
                HStack {
                    Text(peer).font(.callout)
                    Spacer()
                    Text(cadenceStatus(peer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Reset")) {
                        CadenceSeal.reset(peer: peer)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func cadenceStatus(_ peer: String) -> String {
        if let note = chat.cadenceNotes[peer] { return note }
        guard let profile = CadenceSeal.profile(for: peer) else {
            return "not enrolled"
        }
        if profile.samples >= CadenceSeal.enrollSamples {
            return "enrolled — watching the hands"
        }
        return "learning \(profile.samples)/"
            + "\(CadenceSeal.enrollSamples)"
    }

    @AppStorage("knocktalkRelayEnabled") private var relayEnabled = false
    @AppStorage("knocktalkRelayURL") private var relayURL = ""
    @AppStorage("knocktalkRelayToken") private var relayToken = ""
    @AppStorage("knocktalkRelayBox") private var relayBox = ""

    /// The board: every mailbox this phone talks to (plus its
    /// own), and when the relay last saw each — a declaration
    /// or a collection counts as a sighting. Presence is all
    /// the relay can offer: it holds nothing else.
    private var boardBoxes: [String] {
        var boxes = Set(chat.threads.keys.compactMap {
            KnockRelay.mailbox(ofPeer: $0)
        })
        if !KnockRelay.mailbox.isEmpty {
            boxes.insert(KnockRelay.mailbox)
        }
        return boxes.sorted()
    }

    private func refreshBoard() {
        boardChecked = true
        for box in boardBoxes {
            KnockRelay.presence(of: box) { date in
                if let date { boardSeen[box] = date }
            }
        }
    }

    private func boardLabel(_ box: String) -> String {
        guard boardChecked else { return "—" }
        guard let date = boardSeen[box] else {
            return "never seen by the relay"
        }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "seen " + fmt.localizedString(for: date,
                                              relativeTo: Date())
    }

    private var relaySection: some View {
        Section(header: Text(L("Relay server")),
                footer: Text(L("Without a relay, Knocktalk is perimeter-only: both phones must share a network. Run your own relay (this repo, tools/knocktalk-relay) on any host you control, point both phones at it, and address each other as relay:<mailbox>. The relay forwards knock sequences between mailboxes — it never holds the pairing key and cannot read a word; it sees timing, lengths, and mailbox names. The vault, which is a perimeter ritual, never answers a relay knock."))) {
            Toggle(L("Use my relay server"), isOn: $relayEnabled)
            if relayEnabled {
                TextField(L("server (host:8901 or https://…)"),
                          text: $relayURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)
                TextField(L("this phone's mailbox name"),
                          text: $relayBox)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                SecureField(L("relay token"), text: $relayToken)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !chat.relayStatus.isEmpty {
                    Text(chat.relayStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if KnockRelay.configured {
                    Button(L("Check the board")) { refreshBoard() }
                    ForEach(boardBoxes, id: \.self) { box in
                        LabeledContent(
                            box == KnockRelay.mailbox
                                ? "\(box) (this phone)" : box,
                            value: boardLabel(box))
                    }
                }
            }
        }
        .onChange(of: relayEnabled) { _ in
            chat.refreshRelayPolling()
        }
        .onChange(of: relayURL) { _ in
            chat.refreshRelayPolling()
        }
        .onChange(of: relayToken) { _ in
            chat.refreshRelayPolling()
        }
        .onChange(of: relayBox) { _ in
            chat.refreshRelayPolling()
        }
    }

    private var chirpTooLong: Bool {
        chirpDraft.utf8.count + 28 > ChirpModem.maxPayload
    }

    private var chirpSection: some View {
        Section(header: Text(L("Chirp — messages by sound")),
                footer: Text(L("The same sealed box as a knock, sung as tones: speaker to microphone, no network, no radio — it works in airplane mode. Short messages only (sound is a narrow pipe), and keep this tab open while listening. Heard chirps land in a thread named chirp."))) {
            if let key = KnockKeyStore.key {
                HStack {
                    TextField(L("sing a short message"),
                              text: $chirpDraft)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button(L("Sing")) {
                        Haptics.tap()
                        if let sealed = try? Knocktalk.seal(
                            chirpDraft, key: key,
                            suite: chat.sendSuite) {
                            chirpSender.sing(payload: sealed)
                            chirpDraft = ""
                        }
                    }
                    .disabled(chirpDraft.isEmpty || chirpTooLong
                              || chirpSender.singing)
                }
                if chirpTooLong {
                    Text(L("Too long for sound — chirps carry about 90 characters."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if chirpSender.singing {
                    ProgressView(value: chirpSender.progress)
                    Button(L("Stop singing")) { chirpSender.stop() }
                }
                Button(chirpListener.listening
                       ? "Stop listening" : "Listen for a chirp") {
                    if chirpListener.listening {
                        chirpListener.stop()
                    } else {
                        chirpListener.start()
                    }
                }
                if chirpListener.listening
                    || chirpListener.status != "idle" {
                    Text(chirpListener.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(L("Sing it to a file instead")) {
                    if let sealed = try? Knocktalk.seal(
                        chirpDraft, key: key,
                        suite: chat.sendSuite) {
                        chirpWavURL = ChirpMail.export(
                            payload: sealed)
                        chirpFileNote = chirpWavURL == nil
                            ? "the .wav would not render"
                            : "rendered — share it through "
                                + "anything that moves audio; "
                                + "it decodes on arrival"
                        if chirpWavURL != nil { chirpDraft = "" }
                    }
                }
                .disabled(chirpDraft.isEmpty || chirpTooLong)
                if let wav = chirpWavURL {
                    Button {
                        shareItem = ShareItem(items: [wav])
                    } label: {
                        Label(L("Share the chirp (.wav)"),
                              systemImage: "waveform")
                    }
                }
                Button(L("Decode a chirp file…")) {
                    chirpImporting = true
                }
                if let note = chirpFileNote {
                    Text(note)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Set up a pairing key above — chirps are sealed with it, exactly like knocks."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var brushTooLong: Bool {
        brushDraft.utf8.count + 28 > Knocktalk.maxSealedBytes
    }

    private var brushSection: some View {
        Section(header: Text(L("Brush pass — the proximity drop")),
                footer: Text(L("Leave a drop: seal a short message and arm this phone's GATT host with it. Anyone in Bluetooth range can read the sealed bytes; only the pairing key opens them. A paired phone that comes hunting files it in a thread named brush — and you never learn it was taken. EMCON stands the GATT host down, so a drop does not survive going dark."))) {
            if let key = KnockKeyStore.key {
                HStack {
                    TextField(L("leave a short drop"),
                              text: $brushDraft)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button(L("Arm drop")) {
                        Haptics.tap()
                        if let sealed = try? Knocktalk.seal(
                            brushDraft, key: key,
                            suite: chat.sendSuite) {
                            mouth.startGattHost(
                                payload: sealed,
                                name: "nightjar-hack")
                            brushDraft = ""
                        }
                    }
                    .disabled(brushDraft.isEmpty || brushTooLong)
                }
                if brushTooLong {
                    Text(L("Too long for a drop — about 160 characters."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if mouth.gattHostOn {
                    Text(L("GATT host is up — a paired phone in range can take the drop. Stop hosting (Send tab) to disarm it."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(brushVisitor.hunting
                       ? "Stop hunting" : "Hunt for a drop") {
                    if brushVisitor.hunting {
                        brushVisitor.stop()
                    } else {
                        brushVisitor.start()
                    }
                }
                if brushVisitor.hunting
                    || brushVisitor.status != "idle" {
                    Text(brushVisitor.status)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Set up a pairing key above — drops are sealed with it, like everything else here."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var blinkTooLong: Bool {
        blinkDraft.utf8.count + 28 > Knocktalk.maxSealedBytes
    }

    private var blinkSection: some View {
        Section(header: Text(L("Blink — messages by light")),
                footer: Text(L("The sealed box as a looping sequence of QR frames — for the room where even a chirp is too loud. The camera gathers frames until the set is whole; the loop forgives every miss. One-way, like sound: no acknowledgement rides the light back."))) {
            if KnockKeyStore.key != nil {
                HStack {
                    TextField(L("blink a short message"),
                              text: $blinkDraft)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Button(L("Show")) {
                        if let key = KnockKeyStore.key,
                           let sealed = try? Knocktalk.seal(
                            blinkDraft, key: key,
                            suite: chat.sendSuite) {
                            blinkFrames = BlinkFraming.frames(
                                payload: sealed,
                                suite: chat.sendSuite)
                            blinkShowing = true
                            blinkDraft = ""
                        }
                    }
                    .disabled(blinkDraft.isEmpty || blinkTooLong)
                }
                if blinkTooLong {
                    Text(L("Too long for light — about 160 characters."))
                        .font(.caption).foregroundStyle(.orange)
                }
                Button(L("Receive a blink")) {
                    blinkReceiving = true
                }
            } else {
                Text(L("Set up a pairing key above — blinks are sealed with it, like everything else here."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var flareSection: some View {
        Section(header: Text(L("Flare — be recognized, by key-holders only")),
                footer: Text(L("With the flare up, this phone's beacon slot carries a token only the pairing key can compute — it turns over every five minutes and names nobody. A paired phone listening sees a flame beside the row in Listen and knows one of ours is near. It outranks a plain payload beacon for the slot while it's up, and EMCON takes it down like any other emission."))) {
            if KnockKeyStore.key != nil {
                Toggle(L("Raise my flare"), isOn: Binding(
                    get: { mouth.flareOn },
                    set: { on in
                        if on { mouth.startFlare() }
                        else { mouth.stopFlare() }
                    }))
                if mouth.flareOn {
                    Text(L("On the air. Holders of this key, listening now, can see it."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Set up a pairing key above — a flare is computed from it."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var capsuleTooLong: Bool {
        capsuleDraft.utf8.count + 28 > Knocktalk.maxSealedBytes
    }

    private func sealCapsule() {
        let draft = capsuleDraft
        let delay = capsuleDelay
        let suite = chat.sendSuite
        capsuleBusy = true
        capsuleStatus = "Working…"
        DispatchQueue.global(qos: .userInitiated).async {
            let blob = TimeCapsule.seal(
                message: draft, seconds: delay, suite: suite
            ) { status in
                DispatchQueue.main.async { capsuleStatus = status }
            }
            DispatchQueue.main.async {
                capsuleBusy = false
                capsuleStatus = ""
                capsuleBlob = blob
                if blob != nil { capsuleDraft = "" }
            }
        }
    }

    private func grindCapsule() {
        let blob = capsulePaste
        grindControl = GrindControl()
        let control = grindControl
        capsuleProgress = 0
        capsuleNote = "Grinding — the squarings are sequential; "
            + "that's the lock working."
        DispatchQueue.global(qos: .userInitiated).async {
            TimeCapsule.grind(
                blob: blob, control: control,
                progress: { p in
                    DispatchQueue.main.async { capsuleProgress = p }
                },
                completion: { text in
                    DispatchQueue.main.async {
                        capsuleProgress = nil
                        if control.cancelled {
                            capsuleNote = "Grind stopped. The "
                                + "capsule keeps — grind it any "
                                + "time; the work restarts from "
                                + "the first squaring."
                        } else if let text {
                            chat.receiveCapsule(text: text)
                            capsulePaste = ""
                            capsuleNote = "Opened — filed in "
                                + "the capsule thread below."
                        } else {
                            capsuleNote = "That didn't open — "
                                + "damaged in transit, or not a "
                                + "capsule."
                        }
                    }
                })
        }
    }

    private var capsuleSection: some View {
        Section(header: Text(L("Time capsule — sealed until the grinding is done")),
                footer: Text(L("A message locked by repeated squaring, in the Magic Box manner: the sealer forges two primes, slips through the φ shortcut, and throws the factors away. After that, the only road in is the grind — sequential, unparallelizable, calibrated to this phone's pace. A lock delays; it does not schedule: anyone holding the capsule can start grinding now, and faster hardware finishes sooner. Carry the capsule by any means — the lock travels with it."))) {
            if KnockKeyStore.key != nil {
                TextField(L("seal a message into the future"),
                          text: $capsuleDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Picker(L("Hold for"), selection: $capsuleDelay) {
                    Text(L("a breath — 30 seconds (test it)"))
                        .tag(30.0)
                    Text(L("10 minutes")).tag(600.0)
                    Text(L("an hour")).tag(3600.0)
                    Text(L("6 hours")).tag(21600.0)
                }
                Button {
                    Haptics.tap()
                    sealCapsule()
                } label: {
                    Label(capsuleBusy ? "Sealing…"
                                      : "Seal the capsule",
                          systemImage: "lock.badge.clock")
                }
                .disabled(capsuleDraft.isEmpty || capsuleBusy
                          || capsuleTooLong)
                if capsuleTooLong {
                    Text(L("Too long — capsules carry what a Knocktalk message carries."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if !capsuleStatus.isEmpty {
                    Text(capsuleStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let blob = capsuleBlob {
                    Text(blob)
                        .font(.caption2.monospaced())
                        .lineLimit(4)
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            shareItem = ShareItem(items: [blob])
                        } label: {
                            Label(L("Share capsule"),
                                  systemImage: "square.and.arrow.up")
                        }
                        Spacer()
                        Button(L("Copy")) {
                            UIPasteboard.general.string = blob
                        }
                    }
                }
                Divider()
                TextField(L("paste a capsule to open"),
                          text: $capsulePaste)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.caption.monospaced())
                if let progress = capsuleProgress {
                    ProgressView(value: progress)
                    Button(L("Stop grinding")) {
                        grindControl.cancelled = true
                    }
                } else {
                    Button {
                        grindCapsule()
                    } label: {
                        Label(L("Grind it open"),
                              systemImage: "hammer")
                    }
                    .disabled(capsulePaste.isEmpty)
                }
                if !capsuleNote.isEmpty {
                    Text(capsuleNote)
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Set up a pairing key above — capsules seal with the same suites as everything here."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var coinLockSection: some View {
        Section(header: Text(L("Knocktalk is locked"))) {
            Label(L("The coin stands guard over these conversations."), systemImage: "lock.fill")
                .font(.callout)
            Button {
                CoinCenter.shared.tap(.unlock, emcon: nil) {
                    ok, text in
                    coinNote = text
                    if ok { coinUnlocked = true }
                }
            } label: {
                Label(L("Tap the coin to unlock"),
                      systemImage: "wave.3.right")
            }
            if !coinNote.isEmpty {
                Text(coinNote).font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var threadsSection: some View {
        Section(header: Text(L("Conversations"))) {
            HStack {
                TextField(L("peer address — IP, or relay:name"),
                          text: $newPeer)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                Button(L("Open")) {
                    openedPeer = KnockChat.peerKey(newPeer)
                    newPeer = ""
                    navActive = true
                }
                .disabled(newPeer
                    .trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if chat.peersByRecency.isEmpty {
                Text(L("No conversations yet. Open one by address — the other phone needs the app, the same pairing key, and EMCON up."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(chat.peersByRecency, id: \.self) { peer in
                Button {
                    openedPeer = peer
                    navActive = true
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
            Text(L("failed"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        } else if messages.contains(where: {
            $0.outgoing
                && ($0.state == "sending" || $0.state == "awaiting")
        }) {
            Text(L("awaiting"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var housekeepingSection: some View {
        Section(header: Text(L("Housekeeping")),
                footer: Text(L("What this tab has collected, and the doors to empty it."))) {
            Button(role: .destructive) {
                confirmClearThreads = true
            } label: {
                Label(L("Clear all threads"),
                      systemImage: "trash")
            }
            .disabled(chat.threads.isEmpty)
            Button(role: .destructive) {
                confirmForgetCadence = true
            } label: {
                Label(L("Forget cadence profiles"),
                      systemImage: "hand.raised.slash")
            }
        }
    }

    private var retentionSection: some View {
        Section(header: Text(L("Burn timer")),
                footer: Text(L("Checked at launch, when this tab opens, and when a message lands — a closed app cannot burn on schedule. The journal never held contents; this is the only copy."))) {
            Picker(L("Auto-delete messages"),
                   selection: Binding(
                    get: { chat.retentionHours },
                    set: { chat.setRetention(hours: $0) })) {
                Text(L("after 1 hour")).tag(1.0)
                Text(L("after 6 hours")).tag(6.0)
                Text(L("after 24 hours")).tag(24.0)
                Text(L("after 7 days")).tag(168.0)
                Text(L("never")).tag(0.0)
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
            if let note = chat.cadenceNotes[peer] {
                Text(note)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(note.contains("FOREIGN")
                        ? Color.red
                        : (note.contains("✓") ? Color.green
                           : Color.secondary))
                    .listRowSeparator(.hidden)
            }
            if messages.isEmpty {
                Text(L("Nothing yet. The first message knocks the whole conversation open — fragments, about twelve seconds each, and the other phone knocks its ACK back the same way."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(messages) { message in
                HStack {
                    if message.outgoing { Spacer(minLength: 40) }
                    VStack(alignment: message.outgoing
                           ? .trailing : .leading, spacing: 2) {
                        Text(VoiceThrowCodec.displayText(
                            DuelCodec.displayText(message.text)))
                            .font(.callout)
                        Text(caption(for: message))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if message.outgoing,
                           message.state == "failed" {
                            Button(L("Resend")) {
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
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle(peer)
        .toolbar {
            if !messages.isEmpty {
                Button(role: .destructive) {
                    chat.clearThread(peer)
                    dismiss()
                } label: {
                    Text(L("Clear thread"))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(L("knock a message"), text: $draft,
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
                        Text(String(format: L("knocking %lld/%lld…"), chat.sender.sent, chat.sender.total))
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
