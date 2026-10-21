#if os(iOS)
import SwiftUI
import CoreNFC

/// The tag census — Flipper's "read and analyze" half, the
/// half iOS permits, for cards and tags the operator holds
/// in their own hand.
///
/// Present a tag and the census reports what the tag
/// itself offers any reader: its kind, its identifier, its
/// historical bytes and application id where it carries
/// them, and its NDEF records read whole. An ISO 7816 tag
/// also opens an APDU explorer — the operator types a
/// command, the tag answers, both are kept on screen —
/// because a census of your own card should go as deep as
/// the card allows.
///
/// The other half of Flipper's NFC is not here and will
/// not be: nothing is emulated, cloned, or written, and
/// iOS gives third-party apps no card-emulation role in
/// any case. Payment cards answer a census with only the
/// public facts they choose to tell any reader; the census
/// reports what it was told, never more.
final class TagCensus: NSObject, ObservableObject,
                       NFCTagReaderSessionDelegate {
    struct Report {
        var kind: String
        var uid: String
        var lines: [String] = []
        var ndef: [String] = []
        var isISO7816 = false
    }

    @Published private(set) var report: Report?
    @Published private(set) var status =
        "No tag read yet in this sitting."
    @Published private(set) var apduLog: [String] = []

    private var session: NFCTagReaderSession?
    private var isoTag: NFCISO7816Tag?

    func scan() {
        guard NFCTagReaderSession.readingAvailable else {
            status = "This phone cannot read NFC tags."
            return
        }
        report = nil
        isoTag = nil
        session = NFCTagReaderSession(
            pollingOption: [.iso14443, .iso15693, .iso18092],
            delegate: self, queue: nil)
        session?.alertMessage =
            "Hold your own tag or card to the phone."
        session?.begin()
        status = "Listening — hold a tag to the phone."
    }

    func tagReaderSessionDidBecomeActive(
        _ session: NFCTagReaderSession) { }

    func tagReaderSession(_ session: NFCTagReaderSession,
                          didInvalidateWithError error: Error) {
        let nsError = error as NSError
        DispatchQueue.main.async {
            if nsError.code == NFCReaderError.Code
                .readerSessionInvalidationErrorUserCanceled
                .rawValue {
                self.status = "The reading was set aside."
            } else {
                self.status = "Session ended: "
                    + error.localizedDescription
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession,
                          didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { [weak self] error in
            guard let self else { return }
            if let error {
                session.invalidate(errorMessage:
                    "That tag would not connect: "
                    + error.localizedDescription)
                return
            }
            var found: Report
            // Every specific tag the switch binds also
            // speaks NDEF through the one protocol they
            // share; the enum itself offers no conversion.
            var ndefTag: NFCNDEFTag?
            switch tag {
            case .iso7816(let iso):
                self.isoTag = iso
                ndefTag = iso
                found = Report(
                    kind: "ISO 14443 · ISO 7816",
                    uid: iso.identifier.censusHexString,
                    isISO7816: true)
                if let historical = iso.historicalBytes,
                   !historical.isEmpty {
                    found.lines.append(
                        "Historical bytes: "
                        + historical.censusHexString)
                }
                if !iso.initialSelectedAID.isEmpty {
                    found.lines.append(
                        "Selected application: "
                        + iso.initialSelectedAID)
                }
            case .miFare(let mifare):
                ndefTag = mifare
                found = Report(
                    kind: "MIFARE "
                        + "(family \(mifare.mifareFamily.rawValue))",
                    uid: mifare.identifier.censusHexString)
            case .iso15693(let v):
                ndefTag = v
                found = Report(
                    kind: "ISO 15693",
                    uid: v.identifier.censusHexString)
                found.lines.append(
                    "IC manufacturer code: "
                    + "\(v.icManufacturerCode)")
                found.lines.append(
                    "IC serial: " + v.icSerialNumber.censusHexString)
            case .feliCa(let f):
                ndefTag = f
                found = Report(kind: "FeliCa",
                               uid: f.currentIDm.censusHexString)
                found.lines.append(
                    "System code: " + f.currentSystemCode
                        .map {
                            String(format: "%02x", $0)
                        }.joined(separator: " "))
            @unknown default:
                found = Report(kind: "An unrecognized kind",
                               uid: "")
            }
            // NDEF, where the tag carries it: read whole.
            if let ndefTag {
                ndefTag.queryNDEFStatus { status, _, _ in
                    guard status == .readWrite
                            || status == .readOnly else {
                        self.finish(found, session: session)
                        return
                    }
                    ndefTag.readNDEF { message, _ in
                        if let message {
                            found.ndef = message.records.map {
                                record in
                                let payload = record.payload
                                let text =
                                    PayloadKit.printableText(
                                        payload)
                                    ?? payload.censusHexString
                                return "type "
                                    + "\(record.typeNameFormat.rawValue)"
                                    + " · " + text
                            }
                        }
                        self.finish(found, session: session)
                    }
                }
            } else {
                self.finish(found, session: session)
            }
        }
    }

    private func finish(_ found: Report,
                        session: NFCTagReaderSession) {
        DispatchQueue.main.async {
            self.report = found
            self.status = "Read — \(found.kind)."
        }
        session.alertMessage = "Read: \(found.kind)"
        // Keep the session alive for the APDU explorer when
        // the tag speaks 7816; otherwise close politely.
        if !found.isISO7816 {
            session.invalidate()
        }
    }

    /// The APDU explorer: one command the operator typed,
    /// sent to the tag they are holding, the answer kept.
    /// The explorer's log is the operator's to clear —
    /// what the app collects, the operator can empty.
    func clearAPDULog() {
        apduLog = []
    }

    func sendAPDU(hex: String) {
        guard let isoTag else {
            apduLog.append("— no ISO 7816 tag is connected")
            return
        }
        let bytes = Data(censusHex: hex)
        guard bytes.count >= 4 else {
            apduLog.append("— an APDU needs at least "
                + "CLA INS P1 P2")
            return
        }
        guard let apdu = NFCISO7816APDU(data: bytes) else {
            apduLog.append("— that packet would not parse "
                + "as an APDU")
            return
        }
        apduLog.append("→ " + bytes.censusHexString)
        isoTag.sendCommand(apdu: apdu) {
            [weak self] response, sw1, sw2, error in
            DispatchQueue.main.async {
                if let error {
                    self?.apduLog.append(
                        "← error: "
                        + error.localizedDescription)
                    return
                }
                let tail = String(format: "%02x %02x", sw1, sw2)
                self?.apduLog.append(
                    "← " + response.censusHexString + " · " + tail)
            }
        }
    }
}

extension Data {
    /// "aa bb cc" or "aabbcc" — spaced pairs, the book's
    /// own hex dialect, win; bare hex is read too.
    init(censusHex text: String) {
        let cleaned = text.lowercased().filter {
            $0.isHexDigit
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2,
                                     limitedBy: cleaned.endIndex)
                ?? cleaned.endIndex
            if let byte = UInt8(cleaned[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        self.init(bytes)
    }

    var censusHexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

struct TagCensusView: View {
    @StateObject private var census = TagCensus()
    @State private var apduDraft = "00 a4 04 00"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(L("A census of your own cards and tags: what a tag tells any reader, read whole and kept only on this screen. Nothing is written, emulated, or cloned — iOS allows this app no such role, and the census asks for none."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        Haptics.tap()
                        census.scan()
                    } label: {
                        Label(L("Read a tag"),
                              systemImage: "wave.3.right")
                    }
                    Text(census.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let report = census.report {
                    Section(L("The tag")) {
                        LabeledContent(L("Kind"), value: report.kind)
                        if !report.uid.isEmpty {
                            LabeledContent(L("Identifier"),
                                           value: report.uid)
                                .font(.body.monospaced())
                        }
                        ForEach(report.lines, id: \.self) {
                            Text($0).font(.caption.monospaced())
                        }
                    }
                    if !report.ndef.isEmpty {
                        Section(L("NDEF records")) {
                            ForEach(report.ndef, id: \.self) {
                                Text($0).font(.caption.monospaced())
                            }
                        }
                    }
                    if report.isISO7816 {
                        Section(L("APDU explorer")) {
                            Text(L("Commands you type, answers the tag gives — your card, your questions."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(L("00 a4 04 00 …"),
                                      text: $apduDraft)
                                .font(.body.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                            Button(L("Send APDU")) {
                                Haptics.tap()
                                census.sendAPDU(hex: apduDraft)
                            }
                            ForEach(census.apduLog, id: \.self) {
                                Text($0)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if !census.apduLog.isEmpty {
                                Button(L("Clear the log"),
                                       role: .destructive) {
                                    Haptics.tap()
                                    census.clearAPDULog()
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L("Tag census"))
        }
    }
}

#else
import SwiftUI

/// The census reads NFC tags — a phone sense. On
/// the Mac the sheet opens to say so, plainly.
struct TagCensusView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wave.3.right")
                .font(.largeTitle)
            Text(L("Phone-only for now — this organ hasn't crossed to the Mac yet."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
#endif
