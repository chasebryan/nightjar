#if os(iOS)
import CoreNFC
import CryptoKit
import SwiftUI

/// The Coin: a physical key for a digital instrument.
///
/// Any NDEF tag — a transit card, a hotel key, a blank from a
/// drawer — can be claimed as the coin. The app remembers a
/// hash of the tag's contents, never the contents; from then
/// on, that tag, in a pocket, is a key: tap it to check in
/// the dead hand, tap it to raise the knock vault, tap it to
/// unlock Knocktalk. What the key opens is decided here;
/// what the key IS is a thing you can hold, hide, lend, or
/// lose — and losing it is handled the honest way: claim a
/// new one in the open, and the night log says it happened.
///
/// Stated plainly: a copied tag is the same coin. The factor
/// is possession, not secrecy — like every physical key ever
/// cut.
final class CoinCenter: NSObject, ObservableObject {
    static let shared = CoinCenter()

    enum Purpose { case claim, mint, checkin, vault, unlock }

    @Published private(set) var lastResult = ""
    @Published private(set) var claimed = false

    private var session: NFCNDEFReaderSession?
    private var purpose: Purpose = .claim
    private weak var emcon: Emcon?
    private var completion: ((Bool, String) -> Void)?

    private static let hashKey = "coin.hash"

    var coinHash: String? {
        UserDefaults.standard.string(forKey: Self.hashKey)
    }

    override init() {
        super.init()
        claimed = coinHash != nil
    }

    static func hash(of message: NFCNDEFMessage) -> String {
        var hasher = SHA256()
        for record in message.records {
            hasher.update(data: record.payload)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Begin a tap. The phone prompts for the tag itself; the
    /// completion reports what the tap did, in words.
    func tap(_ purpose: Purpose, emcon: Emcon?,
             completion: ((Bool, String) -> Void)? = nil) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion?(false, L("This phone cannot read NFC tags."))
            return
        }
        self.purpose = purpose
        self.emcon = emcon
        self.completion = completion
        let session = NFCNDEFReaderSession(
            delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = alert(for: purpose)
        self.session = session
        session.begin()
    }

    private func alert(for purpose: Purpose) -> String {
        switch purpose {
        case .claim: return L("Hold the tag to the top of the phone to claim it as the coin.")
        case .mint: return L("Hold a writable tag to the top of the phone to mint it as the coin.")
        case .checkin: return L("Tap the coin to check in the dead hand.")
        case .vault: return L("Tap the coin to raise the vault.")
        case .unlock: return L("Tap the coin to unlock Knocktalk.")
        }
    }

    private func finish(_ ok: Bool, _ text: String,
                        session: NFCNDEFReaderSession?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastResult = text
            self.claimed = self.coinHash != nil
            let completion = self.completion
            self.completion = nil
            session?.invalidate()
            self.session = nil
            completion?(ok, text)
        }
    }

    private func judge(hash: String,
                       session: NFCNDEFReaderSession) {
        guard let stored = coinHash else {
            finish(false,
                   L("No coin claimed yet — claim a tag first, in EMCON."),
                   session: session)
            return
        }
        guard stored == hash else {
            finish(false, L("Not the coin — a different tag."),
                   session: session)
            return
        }
        switch purpose {
        case .checkin:
            emcon?.deadHandCheckIn()
            Journal.log("coin", "checkin",
                        "dead hand checked in by the coin")
            finish(true, L("Checked in — the hand stays up."),
                   session: session)
        case .vault:
            emcon?.openVault(source: "the coin")
            Journal.log("coin", "vault",
                        "knock vault raised by the coin")
            finish(true, L("The vault stands open."), session: session)
        case .unlock:
            Journal.log("coin", "unlock",
                        "Knocktalk unlocked by the coin")
            finish(true, L("Unlocked."), session: session)
        case .claim, .mint:
            finish(true, L("The coin, recognized."), session: session)
        }
    }

    private func claim(hash: String,
                       session: NFCNDEFReaderSession) {
        if let stored = coinHash, stored != hash {
            finish(false,
                   L("A different coin is already claimed. This tag is not it — forget the old coin first if this one is to rule."),
                   session: session)
            return
        }
        UserDefaults.standard.set(hash, forKey: Self.hashKey)
        Journal.log("coin", "claim",
                    "a tag was claimed as the coin")
        finish(true, L("Claimed — this tag is the coin now."),
               session: session)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.hashKey)
        claimed = false
        lastResult = L("The coin is forgotten. Any tag may be claimed in its place.")
        Journal.log("coin", "forget",
                    "the coin was forgotten by the operator")
    }
}

extension CoinCenter: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(
        _ session: NFCNDEFReaderSession) {}

    /// The protocol's required detection path. The coin's
    /// real work rides the tag-level path below; a message
    /// that arrives whole is treated as a plain tap read,
    /// and a mint asked of it is refused honestly.
    func readerSession(_ session: NFCNDEFReaderSession,
                       didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first else {
            session.invalidate(
                errorMessage: L("That tag said nothing."))
            return
        }
        if purpose == .mint {
            finish(false,
                   L("The mint needs the tag itself, not its message — hold it steady and try again."),
                   session: session)
            return
        }
        let hash = Self.hash(of: message)
        if purpose == .claim {
            claim(hash: hash, session: session)
        } else {
            judge(hash: hash, session: session)
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession,
                       didInvalidateWithError error: Error) {
        let code = (error as NSError).code
        // 200 is the operator simply cancelling — not news.
        if code != 200 {
            DispatchQueue.main.async { [weak self] in
                self?.lastResult =
                    String(format: L("The tap failed: %@"), error.localizedDescription)
                let completion = self?.completion
                self?.completion = nil
                completion?(false, self?.lastResult ?? "")
            }
        }
        DispatchQueue.main.async { [weak self] in
            if self?.session === session { self?.session = nil }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession,
                       didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        if purpose == .mint {
            mint(tag: tag, session: session)
            return
        }
        tag.readNDEF { [weak self] message, _ in
            guard let self = self, let message = message else {
                self?.finish(false,
                             L("That tag carries nothing readable."),
                             session: session)
                return
            }
            let hash = Self.hash(of: message)
            if self.purpose == .claim {
                self.claim(hash: hash, session: session)
            } else {
                self.judge(hash: hash, session: session)
            }
        }
    }

    private func mint(tag: NFCNDEFTag,
                      session: NFCNDEFReaderSession) {
        tag.queryNDEFStatus { [weak self] status, _, _ in
            guard let self = self else { return }
            guard status == .readWrite else {
                self.finish(false,
                            L("That tag cannot be written — mint needs a blank, writable tag."),
                            session: session)
                return
            }
            let token = "nightjar-coin:" + UUID().uuidString
            guard let record = NFCNDEFPayload.wellKnownTypeTextPayload(
                    string: token, locale: Locale(identifier: "en"))
            else {
                self.finish(false, L("The coin would not strike."),
                            session: session)
                return
            }
            let message = NFCNDEFMessage(records: [record])
            tag.writeNDEF(message) { [weak self] error in
                guard let self = self else { return }
                if error != nil {
                    self.finish(false,
                                L("The mint failed mid-strike."),
                                session: session)
                    return
                }
                self.claim(hash: Self.hash(of: message),
                           session: session)
            }
        }
    }
}

/// EMCON's coin card: claim, tap, govern.
struct CoinSectionView: View {
    @ObservedObject var center: CoinCenter
    let emcon: Emcon
    @AppStorage("coin.lockKnocktalk") private var lockKnocktalk = false

    var body: some View {
        Section(header: Text(L("The coin — a key you can hold")),
                footer: Text(L("Any NDEF tag can be the coin: a transit card, a hotel key, a blank. The app keeps a hash of the tag, never its contents. A copied tag is the same coin — the factor is possession, like every physical key ever cut. One honesty: NFC reading needs the NFC Tag Reading capability, which only a paid developer team's profile grants — under free Personal Team signing the taps will fail, and that is the team talking, not the tag."))) {
            if center.claimed {
                Label(L("A coin is claimed"),
                      systemImage: "circle.circle.fill")
                    .font(.callout)
                Button {
                    center.tap(.checkin, emcon: emcon)
                } label: {
                    Label(L("Tap the coin — check in the dead hand"),
                          systemImage: "hand.raised")
                }
                Button {
                    center.tap(.vault, emcon: emcon)
                } label: {
                    Label(L("Tap the coin — raise the vault"),
                          systemImage: "lock.open")
                }
                Button {
                    center.tap(.claim, emcon: emcon)
                } label: {
                    Label(L("Present the coin"), systemImage: "wave.3.right")
                }
                Toggle(L("Knocktalk requires the coin"),
                       isOn: $lockKnocktalk)
                Button(role: .destructive) {
                    center.forget()
                } label: {
                    Text(L("Forget the coin"))
                }
            } else {
                Text(L("No coin yet. Claim any NFC tag, or mint a blank one with the mark of the house."))
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    center.tap(.claim, emcon: emcon)
                } label: {
                    Label(L("Claim a tag as the coin"),
                          systemImage: "circle.circle")
                }
                Button {
                    center.tap(.mint, emcon: emcon)
                } label: {
                    Label(L("Mint a blank tag"),
                          systemImage: "seal")
                }
            }
            if !center.lastResult.isEmpty {
                Text(center.lastResult)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#else
import SwiftUI
import Combine

/// The coin is an NFC tag — a phone sense. The
/// Mac center is inert and honest: nothing is
/// claimed here, and a tap says why.
final class CoinCenter: ObservableObject {
    enum Purpose { case claim, mint, checkin, vault, unlock }
    static let shared = CoinCenter()
    @Published private(set) var claimed = false
    @Published private(set) var lastResult = ""
    func tap(_ purpose: Purpose, emcon: Emcon?,
             completion: ((Bool, String) -> Void)? = nil) {
        completion?(false, L("This Mac cannot read NFC tags."))
    }
}

/// The coin card on the Mac: the section stands,
/// and its body says the organ lives on the phone.
struct CoinSectionView: View {
    @ObservedObject var center: CoinCenter
    let emcon: Emcon
    var body: some View {
        Section(header: Text(L("The coin — a key you can hold"))) {
            Text(L("Phone-only for now — this organ hasn't crossed to the Mac yet."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
