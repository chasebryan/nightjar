import SwiftUI

/// Throw Your Voice: the ventriloquist, made literal.
///
/// One phone stays silent. Another — paired, lent — speaks
/// for it. The hand composes a payload and a target, seals the
/// instruction into an ordinary Knocktalk message, and knocks
/// it across (LAN or relay, the channel's own roads). The
/// mouth, if it has been lent, performs the send from ITS
/// radios: the bytes leave a device that is not in your hand,
/// and your handset never transmits a thing but knocks.
///
/// The receipt travels back the same road, in full sentences
/// where an ACK is four nibbles, and settles the throw's
/// delivery in the thread.
///
/// Honest limits, stated once: a throw rides the knock
/// channel, so the payload is a signal, not a file — a word, a
/// command, a wake-up. TCP, UDP, and HTTP targets are thrown
/// headlessly; a target that needs the Send tab's full flow
/// comes back refused, in the receipt, in plain language.
enum VoiceThrowCodec {
    static let throwPrefix = "NJ-THROW/1:"
    static let receiptPrefix = "NJ-RECEIPT/1:"

    struct Instruction: Codable {
        var v = 1
        var id: String
        var target: String
        var payload: String
    }

    struct Receipt: Codable {
        var v = 1
        var id: String
        var ok: Bool
        var detail: String
    }

    static func encode(_ instruction: Instruction) -> String? {
        guard let data = try? JSONEncoder().encode(instruction)
        else { return nil }
        return throwPrefix + data.base64EncodedString()
    }

    static func decodeInstruction(_ text: String) -> Instruction? {
        guard text.hasPrefix(throwPrefix),
              let data = Data(
                  base64Encoded: String(text.dropFirst(
                      throwPrefix.count))),
              let instruction = try? JSONDecoder().decode(
                  Instruction.self, from: data),
              instruction.v == 1
        else { return nil }
        return instruction
    }

    static func encode(_ receipt: Receipt) -> String? {
        guard let data = try? JSONEncoder().encode(receipt)
        else { return nil }
        return receiptPrefix + data.base64EncodedString()
    }

    static func decodeReceipt(_ text: String) -> Receipt? {
        guard text.hasPrefix(receiptPrefix),
              let data = Data(
                  base64Encoded: String(text.dropFirst(
                      receiptPrefix.count))),
              let receipt = try? JSONDecoder().decode(
                  Receipt.self, from: data),
              receipt.v == 1
        else { return nil }
        return receipt
    }

    static func instructionID(of text: String) -> String? {
        decodeInstruction(text)?.id
    }

    /// How a throw or receipt reads in the thread — the wire
    /// form is for machines; the thread is for the operator.
    static func displayText(_ text: String) -> String {
        if let instruction = decodeInstruction(text) {
            return "🎙 thrown payload → \(instruction.target): "
                + "“\(instruction.payload)”"
        }
        if let receipt = decodeReceipt(text) {
            return "🎙 receipt — "
                + (receipt.ok ? "thrown: " : "refused: ")
                + receipt.detail
        }
        return text
    }
}

final class VoiceThrowCenter: ObservableObject {
    struct LandedReceipt: Identifiable {
        let id: String
        let from: String
        let ok: Bool
        let detail: String
        let when: Date
    }

    @Published private(set) var receipts: [LandedReceipt] = []

    var armed: Bool {
        get { UserDefaults.standard.bool(forKey: "voiceThrow.armed") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue,
                                      forKey: "voiceThrow.armed")
            Journal.log("voice", "arm",
                        newValue
                            ? "this phone's mouth is lent — paired "
                              + "hands may throw through it"
                            : "mouth withdrawn — no more throwing "
                              + "through this phone")
        }
    }

    /// Offer a decoded message to the ventriloquist before it
    /// reaches the thread. True means consumed: a throw
    /// performed (or refused), or a receipt recorded. Neither
    /// belongs in the conversation.
    func intercept(text: String, source: String,
                   chat: KnockChat) -> Bool {
        if let receipt = VoiceThrowCodec.decodeReceipt(text) {
            receipts.insert(
                LandedReceipt(id: receipt.id, from: source,
                              ok: receipt.ok,
                              detail: receipt.detail, when: Date()),
                at: 0)
            if receipts.count > 20 {
                receipts.removeLast(receipts.count - 20)
            }
            chat.settleThrow(instructionID: receipt.id, peer: source)
            Journal.log("voice", "receipt",
                        "throw \(receipt.ok ? "landed" : "refused") "
                        + "via \(source) — \(receipt.detail)")
            return true
        }
        guard let instruction = VoiceThrowCodec.decodeInstruction(
            text) else { return false }
        guard armed else {
            reply(receipt: .init(id: instruction.id, ok: false,
                                 detail: "this phone's mouth is "
                                     + "not lent"),
                  to: source, chat: chat)
            Journal.log("voice", "refused",
                        "throw from \(source) refused — mouth "
                        + "not lent")
            return true
        }
        do {
            try Mouth.sendFromShortcut(
                targetText: instruction.target,
                payloadText: instruction.payload)
            reply(receipt: .init(
                    id: instruction.id, ok: true,
                    detail: "dispatched from this phone to "
                        + instruction.target),
                  to: source, chat: chat)
            Journal.log("voice", "throw",
                        "threw for \(source) → "
                        + "\(instruction.target) — "
                        + "\(instruction.payload.utf8.count) bytes "
                        + "left THIS phone's radios")
        } catch {
            reply(receipt: .init(id: instruction.id, ok: false,
                                 detail: "\(error)"),
                  to: source, chat: chat)
            Journal.log("voice", "refused",
                        "throw for \(source) failed — \(error)")
        }
        return true
    }

    private func reply(receipt: VoiceThrowCodec.Receipt,
                       to source: String, chat: KnockChat) {
        guard let key = KnockKeyStore.key,
              let text = VoiceThrowCodec.encode(receipt)
        else { return }
        chat.send(text: text, to: source, key: key)
    }
}

/// The Knocktalk tab's ventriloquist card: lend the mouth,
/// throw a payload, read the receipts.
struct VoiceThrowSection: View {
    @ObservedObject var center: VoiceThrowCenter
    @ObservedObject var chat: KnockChat
    @State private var peer = ""
    @State private var target = ""
    @State private var payload = ""
    @State private var note = ""

    var body: some View {
        Section(header: Text(L("Throw Your Voice — the ventriloquist")),
                footer: Text(L("Your phone stays silent; a paired phone speaks. Lend this phone's mouth and any paired hand can throw small payloads through it — the bytes leave THIS device. Or throw through theirs: the instruction rides Knocktalk, sealed, and the receipt comes back the same road. Payloads are signals — a word, a command, a wake-up."))) {
            Toggle(L("Lend this phone's mouth"),
                   isOn: Binding(
                       get: { center.armed },
                       set: { center.armed = $0 }))
            TextField(L("throw via peer — IP, or relay:name"),
                      text: $peer)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.callout.monospaced())
            TextField(L("target — tcp://host:port, udp://…, http://…"),
                      text: $target)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.callout.monospaced())
            TextField(L("payload — a word, a command, a wake-up"),
                      text: $payload)
                .disableAutocorrection(true)
            Button {
                throwIt()
            } label: {
                Label(L("Throw it"), systemImage: "waveform.path")
            }
            .disabled(KnockKeyStore.key == nil
                      || peer.trimmingCharacters(
                          in: .whitespaces).isEmpty
                      || target.trimmingCharacters(
                          in: .whitespaces).isEmpty
                      || payload.isEmpty)
            if !note.isEmpty {
                Text(note).font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(center.receipts) { receipt in
                HStack(spacing: 6) {
                    Image(systemName: receipt.ok
                          ? "checkmark.circle.fill"
                          : "xmark.octagon.fill")
                        .foregroundStyle(receipt.ok
                                          ? Color.green : Color.red)
                    Text("\(receipt.from) — \(receipt.detail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func throwIt() {
        guard let key = KnockKeyStore.key else { return }
        let instruction = VoiceThrowCodec.Instruction(
            id: UUID().uuidString,
            target: target.trimmingCharacters(in: .whitespaces),
            payload: payload)
        guard let text = VoiceThrowCodec.encode(instruction) else {
            note = "That throw would not encode."
            return
        }
        if chat.send(text: text, to: peer, key: key) {
            note = "Thrown. The receipt rides back the same road."
            payload = ""
            Journal.log("voice", "throw",
                        "threw a payload via \(peer) → "
                        + "\(instruction.target) — this phone "
                        + "sent only knocks")
        } else {
            note = "Too long for the knock channel — a throw is "
                + "a signal, not a file. Shorten the payload."
        }
    }
}
