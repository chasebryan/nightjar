import CryptoKit
import SwiftUI

/// The Vault: the cryptography suite's own room.
/// A workbench (material in, a preset chosen,
/// the result out), the preset catalogue, the
/// operator's own saved configurations, and the
/// house's kept keys — every explanation folded
/// behind a What-this-does row, per the house's
/// doctrine. The engine is CryptoSuite; this
/// room is only its furniture.
struct CryptoView: View {
    @EnvironmentObject private var toasts: ToastCenter
    @State private var input = ""
    @State private var inputEncoding = "text"
    @State private var password = ""
    @State private var recipientKey = ""
    @State private var selectedPreset = "sealed-note"
    @State private var output = ""
    @State private var notice: String?
    @State private var shareItem: ShareItem?
    @State private var userPresets =
        CryptoUserPreset.load()
    @State private var customName = ""
    @State private var customCipher =
        "ChaCha20-Poly1305"
    @State private var customRounds = 600_000
    /// The identity's public face, read from
    /// the Keychain once when the room opens —
    /// never inside a redraw.
    @State private var identityPublic = ""
    @State private var identityFingerprint = ""
    // Files: the NJCF side of the room.
    @State private var pickedFile: URL?
    @State private var pickedName = ""
    @State private var pickedInfo: NJCFInfo?
    @State private var fileProtection:
        NJCFProtection = .password
    @State private var filePassword = ""
    @State private var fileRecipient = ""
    @State private var fileBusy = false
    @State private var fileNotice: String?
    @State private var producedFile: URL?
    @State private var producedLabel = ""
    @State private var importingFile = false

    private var preset: CryptoPreset? {
        CryptoPreset.all.first {
            $0.id == selectedPreset
        }
    }

    private var userPreset: CryptoUserPreset? {
        userPresets.first {
            "user:" + $0.id == selectedPreset
        }
    }

    private var needsPassword: Bool {
        if userPreset != nil { return true }
        guard let preset else { return false }
        return preset.operation == .sealPassword
            || preset.operation == .openPassword
            || preset.operation == .oneTimePad
    }

    var body: some View {
        NavigationStack {
            List {
                workbenchSection
                filesSection
                presetsSection
                customSection
                keysSection
            }
            // The backdrop is painted HERE, behind the
            // list itself — the tab-level modifier alone
            // never reached through the navigation stack
            // on device (this screen and Macros sat
            // black while tabs that paint their own
            // backdrop played). Same recipe as Knocktalk.
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle(L("Vault"))
            .onAppear {
                if identityPublic.isEmpty {
                    let identity = CryptoSuite
                        .identity()
                    identityPublic = identity
                        .publicKey.rawRepresentation
                        .base64EncodedString()
                    identityFingerprint =
                        CryptoSuite.fingerprint(
                            identity.publicKey
                                .rawRepresentation)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .fileImporter(
                isPresented: $importingFile,
                allowedContentTypes: [.item]) { result in
                takePickedFile(result)
            }
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        Section(header: Text(L("Files"))) {
            Button {
                Haptics.tap()
                importingFile = true
            } label: {
                Label(pickedFile == nil
                      ? "Choose a file\u{2026}"
                      : "Choose a different file\u{2026}",
                      systemImage: "doc.badge.plus")
            }
            if let pickedFile {
                LabeledContent(
                    "File",
                    value: pickedName)
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(
                            pickedInfo?.byteCount
                            ?? fileSize(pickedFile)),
                        countStyle: .file))
                if let info = pickedInfo {
                    LabeledContent(
                        "Protected by",
                        value: info.protection.label)
                    if info.protection.involvesPassword {
                        SecureField(
                            info.protection == .either
                                ? "Password — blank uses "
                                    + "the vault key"
                                : L("Password"),
                            text: $filePassword)
                    }
                    Button(action: openPickedFile) {
                        Label(L("Open it"),
                              systemImage: "lock.open.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .disabled(fileBusy)
                } else {
                    Picker(L("Protection"),
                           selection: $fileProtection) {
                        ForEach(NJCFProtection.allCases,
                                id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    if fileProtection.involvesPassword {
                        SecureField(L("Password"),
                                    text: $filePassword)
                    }
                    if fileProtection == .deadDrop {
                        TextField(
                            "Recipient public key (base64) — empty seals to this house",
                            text: $fileRecipient)
                            .font(.system(.caption,
                                          design: .monospaced))
                    }
                    Button(action: sealPickedFile) {
                        Label(L("Seal it"),
                              systemImage: "lock.fill")
                            .font(.callout.weight(.semibold))
                    }
                    .disabled(fileBusy)
                }
            }
            if fileBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Working — large files take a moment."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fileNotice {
                Text(fileNotice)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let producedFile {
                LabeledContent(producedLabel,
                               value: producedFile
                                   .lastPathComponent)
                HStack(spacing: 16) {
                    Button(L("Share / send it")) {
                        Haptics.tap()
                        shareItem = ShareItem(
                            items: [producedFile])
                    }
                    Button(L("Forget the working copy")) {
                        Haptics.tap()
                        self.producedFile = nil
                    }
                }
                .font(.callout)
            }
            ExplainToggle(
                text: L("A file is sealed in chunks under one random key; the protection you choose is only how that key is kept — by a password (PBKDF2), by this device's vault key, by either, by both together (each holds half the secret), or sealed to a recipient's public key for a dead-drop hand-off. The original filename travels inside the encryption, and the finished file is filed in Deliveries, ready to send by any road. Opening restores the file under its own name."))
        }
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path)[.size]
            as? NSNumber)?.intValue ?? 0
    }

    private func takePickedFile(
        _ result: Result<URL, Error>) {
        guard case .success(let url) = result
        else { return }
        fileNotice = nil
        producedFile = nil
        pickedFile = url
        pickedName = url.lastPathComponent
        pickedInfo = try? CryptoFiles.inspect(url)
    }

    private func sealPickedFile() {
        Haptics.press()
        guard let pickedFile else { return }
        if fileProtection.involvesPassword,
           filePassword.isEmpty {
            fileNotice = "That protection wants "
                + "a password."
            return
        }
        var recipient: P256.KeyAgreement.PublicKey?
        if fileProtection == .deadDrop {
            if fileRecipient.trimmingCharacters(
                in: .whitespaces).isEmpty {
                recipient = CryptoSuite.identity()
                    .publicKey
            } else if let data = Data(
                base64Encoded: fileRecipient),
                      let key = try? P256.KeyAgreement
                        .PublicKey(
                            rawRepresentation: data) {
                recipient = key
            } else {
                fileNotice = "That recipient key "
                    + "would not read — it wants "
                    + "to be base64."
                return
            }
        }
        let sealedName = pickedName + ".njcf"
        runFileWork(sealing: true) { output in
            try CryptoFiles.encrypt(
                input: pickedFile, output: output,
                protection: fileProtection,
                password: filePassword.isEmpty
                    ? nil : filePassword,
                recipient: recipient)
            return sealedName
        }
    }

    private func openPickedFile() {
        Haptics.press()
        guard let pickedFile else { return }
        runFileWork(sealing: false) { output in
            let restored = try CryptoFiles.decrypt(
                input: pickedFile,
                password: filePassword.isEmpty
                    ? nil : filePassword,
                outputDirectory: output
                    .deletingLastPathComponent())
            // The restored file takes the working
            // path for filing, under its own name.
            if restored != output {
                try? FileManager.default.removeItem(
                    at: output)
                try FileManager.default.moveItem(
                    at: restored, to: output)
            }
            return restored.lastPathComponent
        }
    }

    /// Runs a file operation off the main
    /// thread, files the product in Deliveries
    /// under the name the work returns, and
    /// reports in the room's own voice.
    private func runFileWork(
        sealing: Bool,
        _ work: @escaping (URL) throws -> String) {
        guard let pickedFile else { return }
        fileBusy = true
        fileNotice = nil
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let scoped = pickedFile
                    .startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        pickedFile
                            .stopAccessingSecurityScopedResource()
                    }
                }
                let temp = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(
                        UUID().uuidString)
                try? FileManager.default
                    .createDirectory(
                        at: temp,
                        withIntermediateDirectories: true)
                let working = temp
                    .appendingPathComponent("working")
                do {
                    let display = try work(working)
                    let filed = DeliveriesCenter.shared
                        .addFile(at: working,
                                 displayName: display)
                    DispatchQueue.main.async {
                        fileBusy = false
                        if let filed {
                            producedFile = filed
                            producedLabel = sealing
                                ? L("Sealed, in Deliveries")
                                : L("Opened, in Deliveries")
                            toasts.show(sealing
                                ? L("File sealed")
                                : L("File opened"))
                        } else {
                            fileNotice = "The work "
                                + "finished but the "
                                + "filing failed."
                        }
                    }
                } catch let error as CryptoFileError {
                    DispatchQueue.main.async {
                        fileBusy = false
                        fileNotice = message(for: error)
                    }
                } catch {
                    DispatchQueue.main.async {
                        fileBusy = false
                        fileNotice = "The file work "
                            + "failed: "
                            + error.localizedDescription
                    }
                }
            }
    }

    private func message(
        for error: CryptoFileError) -> String {
        switch error {
        case .notAnEnvelope:
            return "That is not an NJCF envelope."
        case .unsupportedVersion:
            return "That envelope is from a newer "
                + "Vault than this one."
        case .needsPassword:
            return "A password is wanted."
        case .wrongKeyOrPassword:
            return "It would not open — the "
                + "password, the vault key or the "
                + "identity is not the one that "
                + "sealed it."
        case .truncated:
            return "The file ends early — it was "
                + "cut off on its road here."
        case .truncatedHeader:
            return "The envelope's head is cut "
                + "off — the file ends before its "
                + "protection material does."
        case .truncatedChunk:
            return "The file ends mid-chunk — "
                + "it was cut off on its road "
                + "here."
        case .corrupt:
            return "The envelope is damaged."
        case .unreadable:
            return "The file could not be read."
        }
    }

    // MARK: - The workbench

    private var workbenchSection: some View {
        Section(header: Text(L("The workbench"))) {
            Picker(L("Preset"), selection: $selectedPreset) {
                ForEach(CryptoPreset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
                ForEach(userPresets) { custom in
                    Text(custom.name)
                        .tag("user:" + custom.id)
                }
            }
            if let preset {
                ExplainToggle(title: preset.name,
                              text: preset.detail)
            } else if let userPreset {
                ExplainToggle(
                    title: userPreset.name,
                    text: L("Your configuration: ")
                        + "\(userPreset.cipher) under "
                        + L("a password, PBKDF2-HMAC-SHA256 at ")
                        + "\(userPreset.iterations) "
                        + "rounds, output as "
                        + "\(userPreset.encoding). "
                        + L("Run seals; to open, paste an envelope and run — the bench tells a sealed envelope by its mark."))
            }
            TextEditor(text: $input)
                .frame(minHeight: 90)
                .font(.system(.callout,
                              design: .monospaced))
            Picker(L("Input is"), selection: $inputEncoding) {
                Text(L("Text")).tag("text")
                Text(L("Hex")).tag("hex")
                Text(L("Base64")).tag("base64")
            }
            .pickerStyle(.segmented)
            if needsPassword {
                SecureField(
                    preset?.operation == .oneTimePad
                        ? "Pad (hex) — only to open"
                        : L("Password"),
                    text: $password)
            }
            if preset?.operation == .envelopeSeal {
                TextField(L("Recipient public key (base64) — empty seals to this house"),
                          text: $recipientKey)
                    .font(.system(.caption,
                                  design: .monospaced))
            }
            Button(action: run) {
                Label(runLabel,
                      systemImage: "play.fill")
                    .font(.callout.weight(.semibold))
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !output.isEmpty {
                Text(output)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .textSelection(.enabled)
                HStack(spacing: 16) {
                    Button(L("Copy")) {
                        Haptics.tap()
                        UIPasteboard.general.string =
                            output
                        toasts.show(L("Copied"))
                    }
                    Button(L("Share")) {
                        Haptics.tap()
                        shareItem = ShareItem(
                            items: [output])
                    }
                    Button(L("Save to Deliveries")) {
                        Haptics.press()
                        DeliveriesCenter.shared.add(
                            name: "vault-output",
                            text: output, ext: "txt")
                        toasts.show(L("Filed in Deliveries"))
                    }
                }
                .font(.callout)
            }
            ExplainToggle(
                text: L("Material goes in, a preset is chosen, the result comes out below — copyable, shareable, or filed into Deliveries. Sealed things travel as base64 envelopes that describe their own construction, so any copy of the suite can open them with the password. Nothing here leaves the device unless you send it."))
        }
    }

    private var runLabel: String {
        guard let preset else { return "Seal" }
        switch preset.operation {
        case .sealPassword, .sealVaultKey,
             .envelopeSeal, .oneTimePad:
            return "Seal"
        case .openPassword, .openVaultKey,
             .envelopeOpen:
            return "Open"
        case .hashDigest, .fingerprintCard:
            return "Work it"
        }
    }

    // MARK: - The catalogue

    private var presetsSection: some View {
        Section(header: Text(L("Presets"))) {
            ForEach(CryptoPreset.all) { preset in
                HStack {
                    ExplainToggle(
                        title: preset.name,
                        text: preset.detail)
                    Spacer()
                    Button(L("Use")) {
                        Haptics.tap()
                        selectedPreset = preset.id
                    }
                    .font(.callout.weight(.semibold))
                }
            }
        }
    }

    // MARK: - The operator's own configurations

    private var customSection: some View {
        Section(header: Text(L("Your configurations"))) {
            TextField(L("Name it"), text: $customName)
            Picker(L("Cipher"), selection: $customCipher) {
                Text(L("ChaCha20-Poly1305"))
                    .tag("ChaCha20-Poly1305")
                Text(L("AES-256-GCM"))
                    .tag("AES-256-GCM")
            }
            Picker(L("PBKDF2 rounds"),
                   selection: $customRounds) {
                Text(L("100,000")).tag(100_000)
                Text(L("210,000")).tag(210_000)
                Text(L("600,000")).tag(600_000)
                Text(L("1,000,000")).tag(1_000_000)
            }
            Button(L("Save this configuration")) {
                Haptics.press()
                let name = customName
                    .trimmingCharacters(
                        in: .whitespaces)
                guard !name.isEmpty else {
                    notice = "Name the configuration "
                        + "first."
                    return
                }
                userPresets.append(CryptoUserPreset(
                    id: UUID().uuidString,
                    name: name,
                    cipher: customCipher,
                    iterations: customRounds,
                    encoding: "base64"))
                CryptoUserPreset.save(userPresets)
                customName = ""
                toasts.show(L("Configuration saved"))
            }
            ForEach(userPresets) { custom in
                HStack {
                    Text(custom.name)
                    Spacer()
                    Button(L("Use")) {
                        Haptics.tap()
                        selectedPreset =
                            "user:" + custom.id
                    }
                    .font(.callout.weight(.semibold))
                    Button(L("Delete"),
                           role: .destructive) {
                        Haptics.warn()
                        userPresets.removeAll {
                            $0.id == custom.id
                        }
                        CryptoUserPreset.save(
                            userPresets)
                    }
                    .font(.callout)
                }
            }
            ExplainToggle(
                text: L("Your own named configurations — cipher, derivation rounds, output dress — saved beside the presets and kept with the house's setup, mirror and all. A configuration seals and opens with a password in the workbench."))
        }
    }

    // MARK: - The kept keys

    private var keysSection: some View {
        Section(header: Text(L("Keys"))) {
            HStack {
                Text(L("Vault key"))
                Spacer()
                Text(L("AES-256 · in the Keychain"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            HStack {
                Text(L("House identity"))
                Spacer()
                Text(L("P-256 · in the Keychain"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Text(String(format: L("Public key — %@"),
                        identityPublic))
                .font(.system(.caption2,
                              design: .monospaced))
                .textSelection(.enabled)
            Text(String(format: L("Its fingerprint — %@"),
                        identityFingerprint))
                .font(.system(.caption2,
                              design: .monospaced))
                .textSelection(.enabled)
            Button(L("Fresh random hex (32 bytes)")) {
                Haptics.tap()
                output = CryptoSuite.randomHex(32)
            }
            Button(L("Fresh password")) {
                Haptics.tap()
                output = CryptoSuite.randomPassword()
            }
            ExplainToggle(
                text: L("Two keys are kept for the house, both in the Keychain, neither ever shown: the Vault's AES-256 key, and the P-256 identity whose public half (above) others seal dead-drops to. Private keys do not leave the Keychain — that is the whole arrangement."))
        }
    }
}


extension CryptoView {
    /// The input, in the dress it declared.
    private func inputData() -> Data? {
        switch inputEncoding {
        case "hex":
            return CryptoSuite.hexDecode(input)
        case "base64":
            return Data(base64Encoded: input
                .filter { !$0.isWhitespace })
        default:
            return Data(input.utf8)
        }
    }

    /// An envelope as it arrives: base64 words,
    /// whatever the input picker says.
    private func envelopeData() -> Data? {
        Data(base64Encoded: input
            .filter { !$0.isWhitespace })
    }

    /// Opened material as words when it is
    /// words, hex when it is not.
    private func present(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? CryptoSuite.hexEncode(data)
    }

    private func run() {
        Haptics.press()
        notice = nil
        if let custom = userPreset {
            runCustom(custom)
            return
        }
        guard let preset else { return }
        switch preset.operation {
        case .sealPassword:
            guard let data = inputData() else {
                notice = "The input would not "
                    + "read in its declared dress."
                return
            }
            guard !password.isEmpty else {
                notice = "A password is wanted."
                return
            }
            if let sealed = CryptoSuite
                .sealWithPassword(
                    data, password: password,
                    cipher: preset.cipher,
                    iterations: preset.iterations) {
                output = sealed.base64EncodedString()
            } else {
                notice = "The seal failed."
            }
        case .openPassword:
            guard let envelope = envelopeData()
            else {
                notice = "The envelope wants to "
                    + "arrive as base64."
                return
            }
            guard !password.isEmpty else {
                notice = "A password is wanted."
                return
            }
            if let opened = CryptoSuite
                .openWithPassword(envelope,
                                  password: password) {
                output = present(opened)
            } else {
                notice = "It would not open — the "
                    + "password or the envelope is "
                    + "not right."
            }
        case .sealVaultKey:
            guard let data = inputData() else {
                notice = "The input would not read."
                return
            }
            if let sealed = CryptoSuite.seal(
                .aes, key: CryptoSuite.vaultKey(),
                data: data) {
                output = sealed.base64EncodedString()
            } else {
                notice = "The seal failed."
            }
        case .openVaultKey:
            guard let envelope = envelopeData(),
                  let opened = CryptoSuite.open(
                    .aes, key: CryptoSuite.vaultKey(),
                    sealed: envelope)
            else {
                notice = "It would not open — "
                    + "that was not sealed under "
                    + "this house's vault key."
                return
            }
            output = present(opened)
        case .envelopeSeal:
            guard let data = inputData() else {
                notice = "The input would not read."
                return
            }
            let recipient: P256.KeyAgreement.PublicKey
            if recipientKey.isEmpty {
                recipient = CryptoSuite.identity()
                    .publicKey
            } else if let keyData = Data(
                        base64Encoded: recipientKey),
                      let parsed = try? P256
                        .KeyAgreement.PublicKey(
                            rawRepresentation: keyData) {
                recipient = parsed
            } else {
                notice = "That recipient key would "
                    + "not read — it wants a P-256 "
                    + "public key as base64."
                return
            }
            if let sealed = CryptoSuite
                .envelopeSeal(data, for: recipient) {
                output = sealed.base64EncodedString()
            } else {
                notice = "The envelope failed."
            }
        case .envelopeOpen:
            guard let envelope = envelopeData(),
                  let opened = CryptoSuite
                    .envelopeOpen(envelope)
            else {
                notice = "It would not open — "
                    + "that envelope was not sealed "
                    + "to this house's identity."
                return
            }
            output = present(opened)
        case .hashDigest:
            guard let data = inputData() else {
                notice = "The input would not read."
                return
            }
            output = "SHA-256  "
                + CryptoSuite.hexEncode(
                    CryptoSuite.hash(.sha256, data))
                + "\nSHA-512  "
                + CryptoSuite.hexEncode(
                    CryptoSuite.hash(.sha512, data))
                + "\nFingerprint  "
                + CryptoSuite.fingerprint(data)
        case .fingerprintCard:
            guard let data = inputData() else {
                notice = "The input would not read."
                return
            }
            output = CryptoSuite.fingerprint(data)
        case .oneTimePad:
            guard let data = inputData() else {
                notice = "The input would not read."
                return
            }
            if password.isEmpty {
                let pad = CryptoSuite.randomBytes(
                    data.count)
                let cipher = xor(data, pad)
                output = "Cipher (hex)\n"
                    + CryptoSuite.hexEncode(cipher)
                    + "\nPad (hex)\n"
                    + CryptoSuite.hexEncode(pad)
            } else if let pad = CryptoSuite
                        .hexDecode(password) {
                output = present(xor(data, pad))
            } else {
                notice = "The pad wants to be hex."
            }
        }
    }

    private func runCustom(
        _ custom: CryptoUserPreset) {
        let cipher: CryptoSuite.Cipher =
            custom.cipher == "AES-256-GCM"
            ? .aes : .chacha
        guard !password.isEmpty else {
            notice = "A password is wanted."
            return
        }
        // An envelope announces itself; anything
        // else is material to seal.
        if let envelope = envelopeData(),
           envelope.count > 26,
           envelope.prefix(4) == Data("NJCS".utf8) {
            if let opened = CryptoSuite
                .openWithPassword(envelope,
                                  password: password) {
                output = present(opened)
            } else {
                notice = "It would not open — the "
                    + "password is not right."
            }
            return
        }
        guard let data = inputData() else {
            notice = "The input would not read."
            return
        }
        if let sealed = CryptoSuite.sealWithPassword(
            data, password: password, cipher: cipher,
            iterations: custom.iterations) {
            output = custom.encoding == "hex"
                ? CryptoSuite.hexEncode(sealed)
                : sealed.base64EncodedString()
        } else {
            notice = "The seal failed."
        }
    }

    private func xor(_ a: Data, _ b: Data) -> Data {
        var out = Data()
        out.reserveCapacity(min(a.count, b.count))
        for i in 0..<min(a.count, b.count) {
            out.append(a[i] ^ b[i])
        }
        return out
    }
}
