import AVFoundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import PDFKit
import SwiftUI
import WebKit

/// Skelli — the house's specialist.

extension Notification.Name {
    static let houseNavigate = Notification.Name(
        "house.navigate")
}

// MARK: - The knowledge

struct SkelliEntry: Identifiable {
    var id: String
    var title: String
    /// Where it lives, in words a person can follow.
    var home: String
    var keywords: [String]
    var body: String
}

enum SkelliKnowledge {
    static let entries: [SkelliEntry] = [
        SkelliEntry(
            id: "listen", title: "Listen — the ear",
            home: "the Listen tab",
            keywords: ["listen", "ear", "bluetooth", "ble",
                       "radar", "sightings", "nearby", "drone"],
            body: "A passive Bluetooth LE listening post. It never connects or pairs; it logs advertisements, builds a presence registry, decodes Apple Continuity and Remote ID drone broadcasts, and flags unknown trackers. Sessions are kept in the same JSONL the Mac tools read."),
        SkelliEntry(
            id: "send", title: "Send — the throwing arm",
            home: "the Send tab",
            keywords: ["send", "payload", "throw", "fan-out",
                       "fanout", "snatchsteal", "payplant",
                       "timed", "template"],
            body: "Payloads out over TCP, UDP, TLS, HTTP, and BLE — typed by hand or from the protocol library, templated with the target, fanned out to many hosts, timed, repeated, or planted to stay living on a service (PayPlant). SnatchSteal knocks, then drains everything the target sends back."),
        SkelliEntry(
            id: "serve", title: "Serve — the open door",
            home: "the Serve tab",
            keywords: ["serve", "listener", "listen on",
                       "inbox", "stealth", "reply"],
            body: "TCP, UDP, and HTTP listeners with fixed or echo replies and an inbox that banners arrivals. Stealth stops the Bonjour listing — reachable by known address, invisible on the board. The BLE GATT host arms once and survives backgrounding until you stop it yourself."),
        SkelliEntry(
            id: "sessions", title: "Sessions",
            home: "the Sessions tab",
            keywords: ["sessions", "recordings", "history",
                       "export", "jsonl"],
            body: "Every listening session the ear has kept, in the nightjar JSONL the desktop tools read. Sessions can be shared out, and deleted — singly or all at once, behind a confirmation."),
        SkelliEntry(
            id: "nightlog", title: "The Night log",
            home: "EMCON's brief and the About tab",
            keywords: ["night log", "journal", "sealed",
                       "log", "hash", "record", "brief",
                       "morning"],
            body: "The house's sealed journal: every organ writes to one hash-chained JSONL in Documents, each line bound to the one before it, so the record testifies about tampering itself. It folds behind an Entries door, clears behind a confirmation, and its morning brief opens the day. Contents of knocktalk are never journaled — only arrivals."),
        SkelliEntry(
            id: "scan", title: "Scan — the wire, swept",
            home: "the Scan tab",
            keywords: ["scan", "sweep", "ports", "subnet",
                       "discovery", "bonjour", "tls", "dns",
                       "pcap", "feed"],
            body: "A connect scanner and a /24 subnet sweep, a Bonjour board that resolves to addresses, an observation feed that narrates hosts coming and going, a TLS inspector, a DNS toolkit, and a pcap dissector for captures from your own machines. Everything it finds feeds the Neighborhood and the Map."),
        SkelliEntry(
            id: "dossiers", title: "Dossiers",
            home: "the Scan tab, under Dossiers",
            keywords: ["dossier", "device page", "baseline",
                       "profile"],
            body: "One page per device, every organ's testimony in one place: what Scan heard, whether the ear knows the name over Bluetooth, its given name and mark, its drift — and a knock baseline you can set, so the house can say when the device stops sounding like itself."),
        SkelliEntry(
            id: "map", title: "The Map",
            home: "the top of the Scan tab",
            keywords: ["map", "rooms", "room", "placed",
                       "floor", "house plan", "layout"],
            body: "The house on one canvas: you name rooms and place each neighbor where the device physically sits; nodes glow by freshness, carry their drift, and open their dossiers. Placement is your testimony — the app keeps it and never invents a location of its own. The Map resets from its More menu; the devices stay, the sitting is forgotten."),
        SkelliEntry(
            id: "compass", title: "The Compass",
            home: "the Map's 'In the air' strip",
            keywords: ["compass", "homing", "walk", "find",
                       "direction", "bearing", "paw"],
            body: "Walk to a Bluetooth device the ear is hearing: signal in honest bands with paw-prints for distance, a ring that fills as you close in, and a bearing that condenses out of your own footsteps — Bluetooth gives a loudness, never a direction, so the direction is learned from your walking. No wedge until you have walked."),
        SkelliEntry(
            id: "neighborhood", title: "The Neighborhood",
            home: "the Scan tab",
            keywords: ["neighborhood", "neighbors",
                       "neighbours", "devices", "given name",
                       "name a device", "rename", "mark"],
            body: "The wire's cast, kept: every device the house has learned — by sweep, by announcement, by knock at its own door — with its sightings, ports, drift, and arrivals. Any of them can be given your own name and a mark, and the name follows the device everywhere. The board folds behind a counted door and clears behind a confirmation."),
        SkelliEntry(
            id: "recon", title: "The Recon bench",
            home: "the Recon tab",
            keywords: ["recon", "bench", "knock", "connect",
                       "fuzz", "census", "probe"],
            body: "The pocket bench: knock a host across the full port census speaking each port's own first words, read banners, fuzz a service with malformed greetings, and keep presets of the knocks you run often. Its answers feed the Neighborhood like everything else's."),
        SkelliEntry(
            id: "emcon", title: "EMCON — the posture",
            home: "the EMCON tab",
            keywords: ["emcon", "score", "posture", "ghost",
                       "exposure", "dark", "visible"],
            body: "Emission control: one number for how visible this phone is — its own listeners, its announcements, its radios — with the weights shown. Going dark silences what the house owns: stealth on, beacon and GATT host down, tripwire armed. The score never hides what it cannot silence; your VPN's own listener reads as what it is."),
        SkelliEntry(
            id: "tripwire", title: "The tripwire & prober files",
            home: "the EMCON tab",
            keywords: ["tripwire", "prober", "knocked me",
                       "who knocked", "probed"],
            body: "Silent listeners bound on the census ports: anyone who knocks this phone is logged — source, port, first words — and never answered. The prober files assemble a dossier per knocker from that log. Both fold to six with a door to the rest, and the log clears from its own section."),
        SkelliEntry(
            id: "drill", title: "The drill",
            home: "the EMCON tab",
            keywords: ["drill", "prove it", "went quiet",
                       "silenced"],
            body: "'Prove it — scan, go dark, scan again.' The drill snapshots the phone's exposure, engages EMCON, measures again, and reads the difference out — from a ledger of what it switched off, beside the snapshot diff, because a withdrawn Bonjour listing echoes in mDNS after it dies and a scan alone would swear nothing happened."),
        SkelliEntry(
            id: "assault", title: "Net-Assault",
            home: "the EMCON tab, under the skull",
            keywords: ["net-assault", "net assault",
                       "assault", "autonomous", "passes",
                       "after-action", "after action"],
            body: "The house turned loose on its own wire: sweeps on rotating ports, the Bonjour browse, and the bench knocking the full census against every known neighbor, pass after pass until you stand it down. Loud by design — it warns twice, runs only while the app is awake, and exports an after-action report when it stands down. Arming plays the ignition reel."),
        SkelliEntry(
            id: "steward", title: "The Steward",
            home: "the EMCON tab",
            keywords: ["steward", "proposals", "suggests",
                       "latitude", "home-turf", "home turf"],
            body: "The house's judgment, on a leash: it watches and proposes — enact or dismiss, and it learns the shape of your house from three banked nights of home-turf before it proposes there. It ships at observe latitude: it asks, it does not act alone."),
        SkelliEntry(
            id: "subconscious", title: "The Subconscious",
            home: "the EMCON tab — 'Open the mind'",
            keywords: ["subconscious", "mind", "findings",
                       "facts", "learned", "verdict",
                       "pattern", "brief", "ask"],
            body: "The mind underneath: it reads across every organ — log, wire, Map, cadence, the Instrument — and names what breaks the house's pattern, with citations and printed confidence. It consolidates: durable facts with their evidence, contradicted in the open when the house breaks them. Your True / Not so verdicts bend its confidences and teach its priorities. Ask it about the record in its own view. It never acts; it advises."),
        SkelliEntry(
            id: "instrument", title: "The Instrument",
            home: "the EMCON tab, below the Subconscious",
            keywords: ["instrument", "watch", "apple watch",
                       "heart", "sleep", "health", "oxygen",
                       "hrv", "steps"],
            body: "The Apple Watch, read: worn and paired, it already measures you and leaves the readings in this phone's health store — no watch app, no session. Heart, variability, resting heart, blood oxygen, breath, wrist temperature, steps, and last night's sleep as a window. A reading, not a live feed: every value carries its age. The mind reads you against your own fortnight baseline."),
        SkelliEntry(
            id: "knocktalk", title: "Knocktalk",
            home: "the Knocktalk tab",
            keywords: ["knocktalk", "messages", "chat",
                       "sealed", "pairing", "burn"],
            body: "Messages that travel as knock ORDER alone — a ChaCha20-Poly1305 sealed box spelled in port sequences under a pairing key kept in the Keychain. The journal records arrivals, never contents. A burn timer deletes decoded messages after the retention you set. Threads clear from its Housekeeping, key untouched."),
        SkelliEntry(
            id: "vault", title: "The knock vault",
            home: "the EMCON tab",
            keywords: ["vault", "combination", "raise serve",
                       "secret knock"],
            body: "Three protocol digits you choose, spoken properly by one other device inside twenty seconds, raise Serve from its settings for sixty seconds — then it seals itself. The combination is yours, changeable in EMCON."),
        SkelliEntry(
            id: "cadence", title: "The Cadence Seal",
            home: "the Knocktalk tab and EMCON's grading",
            keywords: ["cadence", "foreign hands", "rhythm",
                       "timing", "hands", "fingerprint"],
            body: "Knock timing is a fingerprint: the seal learns each peer's rhythm across six features and flags a correct key knocked by the wrong hands — FOREIGN HANDS — in the thread, the banner, and the journal. It annotates, never blocks. Profiles forget from Knocktalk's Housekeeping."),
        SkelliEntry(
            id: "throw", title: "Throw Your Voice",
            home: "the Knocktalk tab",
            keywords: ["throw", "voice", "remote", "receipt",
                       "command another"],
            body: "One phone instructs another by knocktalk — send this, there, now — and the armed mouth executes and returns a receipt that settles the delivery in the thread. The instruction rides sealed, like any other message."),
        SkelliEntry(
            id: "coin", title: "The Coin",
            home: "the EMCON tab",
            keywords: ["coin", "nfc", "tag", "physical key"],
            body: "A physical key: any NFC tag, claimed by a hash of its contents. Taps check in the dead hand, raise the vault, or unlock a coin-locked Knocktalk. Honest limit: under free (Personal Team) signing iOS refuses the NFC entitlement, so the Coin ships dormant — present, truthful, and live the moment a paid team signs the app."),
        SkelliEntry(
            id: "testament", title: "Last Testament & the dead hand",
            home: "the EMCON tab",
            keywords: ["testament", "dead hand", "capsule",
                       "after", "sealed note"],
            body: "A note sealed under a time-lock grind that the app refuses to open until the dead hand has fallen and its days have passed — the refusal is the feature. When the terms are met, the grind runs and the plaintext replaces the blob."),
        SkelliEntry(
            id: "duel", title: "Duel Mode",
            home: "the EMCON tab",
            keywords: ["duel", "arena", "strikes", "game",
                       "opponent"],
            body: "Two phones, one arena: the host's real ports and decoys; the guest strikes three a round for three rounds with the recon bench; scoring is read from the defender's own event log. Herald messages ride knocktalk."),
        SkelliEntry(
            id: "season", title: "Sparring Season",
            home: "the EMCON tab",
            keywords: ["sparring", "season", "ghost",
                       "visits", "training", "grade"],
            body: "Nine ghost visits over seven days — loud spelling, quiet knocks, a vault combination spoken at the door — played through the real tripwire and scored from the journal: did the house hear, did the Steward react, did the vault open. A final grade is journaled. It plays only while the app is awake, and says so."),
        SkelliEntry(
            id: "canary", title: "Canary & honeydrop",
            home: "the Serve and EMCON tabs",
            keywords: ["canary", "honeydrop", "bait",
                       "drop", "lure"],
            body: "Bait the house keeps: a canary service that should never be touched, and a honeydrop payload whose takers announce themselves — every taker joins the Neighborhood through the same LAN-guarded door as any other discovery."),
        SkelliEntry(
            id: "chirp", title: "Chirp, Blink & Flare",
            home: "the Knocktalk tab",
            keywords: ["chirp", "blink", "flare", "tones",
                       "qr", "sound", "light"],
            body: "Knocktalk's other voices: messages as audible tones (Chirp), as looping QR frames read by the camera (Blink), and Flare — each authenticated with the pairing key and a five-minute window, like everything else in the tab."),
        SkelliEntry(
            id: "hunt", title: "The tracker hunt",
            home: "the Listen tab — a row's Hunt",
            keywords: ["hunt", "tracker", "airtag", "find",
                       "following me", "tone"],
            body: "Walk down an unknown tracker the ear has flagged: a tone that quickens as its smoothed signal strengthens. It reads the listening post's own rows — the hunt never transmits."),
        SkelliEntry(
            id: "capsule", title: "The time capsule",
            home: "the Knocktalk tab",
            keywords: ["time capsule", "rsw", "time-lock",
                       "timelock", "puzzle"],
            body: "A message sealed behind repeated squaring — Rivest–Shamir–Wagner — so the opening takes the time it takes and cannot be hurried by cleverness. Share the blob; the clock does the rest."),
        SkelliEntry(
            id: "conductor", title: "Conductor & night maneuvers",
            home: "the EMCON tab",
            keywords: ["conductor", "maneuvers", "manoeuvres",
                       "choreograph", "sequence", "routine"],
            body: "Choreography for the house: maneuvers that run the organs in sequence — scan, darken, listen — and a conductor that keeps the evening's routine in step. Schedules the house can keep while it is awake."),
        SkelliEntry(
            id: "colours", title: "Colours",
            home: "the About tab — the Colours section",
            keywords: ["colours", "colors", "theme",
                       "wallpaper", "backdrop", "accent",
                       "look", "customise", "customize"],
            body: "The app's wardrobe: six built-in themes and your own — accent, glow, and tint washing every backdrop — plus per-tab backdrops: the living wallpaper, the Jolly Roger kept forever as a choice, plain colour, or your own image or GIF, copied onto the device and never leaving it."),
    ]

    static func lookup(_ query: String) -> SkelliEntry? {
        let q = query.lowercased()
        var best: SkelliEntry?
        var bestScore = 0
        for entry in entries {
            var score = 0
            for key in entry.keywords where q.contains(key) {
                score += 2
            }
            for word in entry.title.lowercased()
                .split(separator: " ")
            where word.count > 3 && q.contains(word) {
                score += 1
            }
            if score > bestScore {
                bestScore = score
                best = entry
            }
        }
        return bestScore >= 2 ? best : nil
    }
}

// MARK: - The transcript

struct SkelliLine: Identifiable, Codable {
    var id = UUID()
    var fromOperator: Bool
    var text: String
    var when = Date()
}

/// One thing she has been told and keeps.
struct SkelliNote: Identifiable, Codable {
    var id = UUID()
    var text: String
    var learnedAt = Date()
}

/// Her persistence: the conversation and her notes in
enum SkelliStore {
    struct Saved: Codable {
        var lines: [SkelliLine] = []
        var notes: [SkelliNote] = []
    }

    static var fileURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("skelli.json")
    }

    static func load() -> Saved {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode(
                  Saved.self, from: data)
        else { return Saved() }
        return saved
    }

    static func save(_ saved: Saved) {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - The center

final class SkelliCenter: ObservableObject {
    static let shared = SkelliCenter()

    @Published var lines: [SkelliLine] = []
    @Published var notes: [SkelliNote] = []
    @Published var mood: SkelliMood = .idle
    @Published var activity: String = "Ready."
    /// Her outward eye, on unless the operator
    @Published var webResearchEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(
                webResearchEnabled,
                forKey: "skelli.webResearch")
        }
    }
    private(set) var mouth: Mouth?
    private(set) var emcon: Emcon?
    private(set) var post: ListeningPost?
    private let scanner = ScanModel()
    private var sweepWatch: AnyCancellable?
    private var idleWork: DispatchWorkItem?
    /// The conversation's short-term memory: the device
    private var lastDeviceIP: String?
    private var pendingAction: (() -> Void)?

    init() {
        let saved = SkelliStore.load()
        lines = saved.lines
        notes = saved.notes
        webResearchEnabled = (UserDefaults.standard
            .object(forKey: "skelli.webResearch")
            as? Bool) ?? true
        SkelliWeb.onProgress = { [weak self] text in
            DispatchQueue.main.async {
                self?.activity = text
            }
        }
    }

    /// The app hands over its own organs at first light,
    func wire(mouth: Mouth, emcon: Emcon,
              post: ListeningPost) {
        self.mouth = mouth
        self.emcon = emcon
        self.post = post
    }

    private func persist() {
        SkelliStore.save(SkelliStore.Saved(
            lines: Array(lines.suffix(300)), notes: notes))
    }

    func say(_ text: String) {
        lines.append(SkelliLine(fromOperator: false,
                                 text: text))
        persist()
        mood = .speaking
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.mood == .speaking { self?.mood = .idle }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1.4, execute: work)
        activity = "Ready."
    }

    /// The operator empties the conversation. Her notes
    func clearConversation() {
        lines = []
        pendingAction = nil
        lastDeviceIP = nil
        persist()
    }

    /// Back to her defaults: no conversation, no notes,
    func resetToDefaults() {
        lines = []
        notes = []
        pendingAction = nil
        lastDeviceIP = nil
        webResearchEnabled = true
        mood = .idle
        SkelliStore.wipe()
    }

    func remember(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.append(SkelliNote(text: trimmed))
        persist()
    }

    func forgetNote(id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    func forgetNotes(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        persist()
    }

    func ask(_ raw: String) {
        let text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append(SkelliLine(fromOperator: true,
                                 text: text))
        persist()
        // Thinking is always on — a short, real beat
        mood = .thinking
        let q = text.lowercased()
        let delay = Self.thinkDelay(for: q)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay) { [weak self] in
            self?.respond(to: q, raw: text)
        }
    }

    /// The directory's way in: the entry itself,
    func askAbout(_ entry: SkelliEntry) {
        lines.append(SkelliLine(fromOperator: true,
                                 text: entry.title))
        say(entry.body + "\nFind it: \(entry.home).")
    }

    private func navigate(to tab: Int) {
        NotificationCenter.default.post(
            name: .houseNavigate, object: nil,
            userInfo: ["tab": tab])
    }

    // MARK: small favors

    /// How long she thinks before answering: a breath
    /// for a plain order, longer for a real question.
    /// Research takes its own time once it starts.
    private static func thinkDelay(for q: String)
        -> TimeInterval {
        if ["say ", "repeat", "echo", "spell ",
            "uppercase", "lowercase", "reverse ",
            "how many"].contains(where: q.hasPrefix)
            || q.contains("what time")
            || q.count <= 16 {
            return 0.2
        }
        if q.count > 90 || q.contains("search the web")
            || q.contains("research") {
            return 0.9
        }
        return 0.55
    }

    // MARK: the routing

    private func respond(to q: String,
                         raw: String) {
        // Addressed by name: "Skelli, what's up" is
        // speech to her, not a search about her.
        var q = q
        if q.hasPrefix("skelli") {
            let rest = q.dropFirst(6)
            if rest.isEmpty
                || " ,.!?:".contains(rest.first!) {
                q = String(rest).trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: " ,.!?:"))
            }
        }
        // …and at the tail: "hi skelli", "thanks
        // skelli" — the same address, lifted off
        // when what remains is social speech.
        let core = q.trimmingCharacters(
            in: CharacterSet(charactersIn: " !?.,;:"))
        if core.hasSuffix("skelli") {
            let before = core.dropLast(6)
            if before.isEmpty
                || " ,.!?:".contains(before.last!) {
                let candidate = String(before)
                    .trimmingCharacters(
                        in: CharacterSet(
                            charactersIn: " ,.!?:"))
                let head = candidate
                    .split(separator: " ")
                    .first.map(String.init) ?? ""
                if candidate.isEmpty
                    || ["hi", "hello", "hey", "thank",
                        "thanks", "good", "bye", "ok",
                        "okay", "please", "sorry"]
                        .contains(head) {
                    q = candidate
                }
            }
        }
        if q.isEmpty {
            say("Here. Ask about the house, or give "
                + "an order.")
            return
        }

        // An offered action, awaiting a word.
        if let pending = pendingAction {
            if ["yes", "yeah", "yep", "do it", "go",
                 "go ahead", "ok", "okay", "sure"]
                    .contains(q) || q.hasPrefix("yes") {
                pendingAction = nil
                pending()
                return
            }
            if q == "no" || q == "nope"
                || q.contains("never mind") {
                pendingAction = nil
                say("Understood — left as it is.")
                return
            }
        }

        // Small favors first: plain orders, plainly
        // done, before the machinery wakes.
        if smallFavor(q, raw: raw) { return }

        // Being told things: her long memory.
        if q.hasPrefix("remember ") {
            var note = String(q.dropFirst(9))
            if note.hasPrefix("that ") {
                note = String(note.dropFirst(5))
            }
            if note.isEmpty {
                say("Remember what? Tell me, and "
                    + "it's kept.")
            } else {
                remember(note)
                say("Kept: " + note + ". It stays with "
                    + "me across conversations — ask "
                    + "'what do you remember', or tell "
                    + "me to forget it.")
            }
            return
        }
        if q.contains("what do you remember")
            || q.contains("your memory")
            || q.contains("what have you learned") {
            say(notesReport())
            return
        }
        if q.hasPrefix("forget ") {
            let needle = String(q.dropFirst(7))
            if let hit = notes.first(where: {
                $0.text.contains(needle) }) {
                forgetNote(id: hit.id)
                say("Forgotten: " + hit.text + ".")
                return
            }
            // No note matched — fall through; the
        }

        // Greetings and the tour.
        if ["hello", "hi", "hey"].contains(q)
            || q.contains("who are you")
            || q.contains("what are you")
            || q.contains("your name") {
            say("Skelli. I answer from the system "
                + "itself: its "
                + "manual, its live state, its "
                + "controls — and when a question "
                + "leaves the house, I research it "
                + "through this phone's connection and "
                + "name the source. Ask 'what can you "
                + "do'.")
            return
        }
        if q.contains("what can you do")
            || q == "help" || q.contains("capabilit")
            || q.contains("what do you do")
            || q.contains("your job")
            || q.contains("your purpose")
            || q.contains("around here")
            || q.contains("you do here") {
            say(capabilities)
            return
        }

        // Explanations go to the manual before the
        if q.hasPrefix("what is") || q.hasPrefix("what's")
            || q.contains("how does")
            || q.contains("explain") {
            if let entry = SkelliKnowledge.lookup(q) {
                say(entry.body + "\nFind it: \(entry.home).")
                return
            }
        }

        // Hands first: the action intents.
        if q.contains("sweep") {
            runSweep()
            return
        }
        if q.contains("scan me") || q.contains("scan myself")
            || q.contains("self scan")
            || q.contains("how exposed") {
            runSelfScan()
            return
        }
        if q.contains("audit") {
            runAudit()
            return
        }
        if q.contains("go dark") || q.contains("emcon on")
            || q.contains("activate emcon") {
            goDark()
            return
        }
        if q.contains("stand down") && !q.contains("assault") {
            standDown()
            return
        }
        if q.contains("stealth on") {
            mouth?.setStealth(true)
            say("Stealth on — Serve keeps its listeners "
                + "and loses its listing.")
            return
        }
        if q.contains("stealth off") {
            mouth?.setStealth(false)
            say("Stealth off — Serve lists itself again "
                + "whenever it runs.")
            return
        }
        if q.contains("start serving")
            || q.contains("start serve")
            || q.contains("serve on") {
            mouth?.startServeFromSettings()
            say("Serve raised from its own settings — "
                + "the doors you configured, nothing "
                + "bespoke. The Serve tab shows it live.")
            return
        }
        if q.contains("stop serving")
            || q.contains("stop serve")
            || q.contains("serve off") {
            mouth?.stopServe()
            say("Serve stood down; its listeners are "
                + "closed and the inbox keeps what it "
                + "caught.")
            return
        }
        if q.contains("tripwire on")
            || q.contains("arm the tripwire") {
            emcon?.startTripwire()
            say("Tripwire armed — the census ports are "
                + "listening in silence, and every knock "
                + "will be logged and never answered.")
            return
        }
        if q.contains("tripwire off")
            || q.contains("disarm the tripwire") {
            emcon?.stopTripwire()
            say("Tripwire stood down.")
            return
        }
        if q.contains("drill") {
            runDrill()
            return
        }
        if q.contains("start listening")
            || q.contains("listen on") {
            startListening()
            return
        }
        if q.contains("stop listening")
            || q.contains("listen off") {
            post?.stop()
            say("The ear is closed. Its sessions keep "
                + "what they heard.")
            return
        }
        if (q.contains("name ") || q.contains("call "))
            && nameDevice(q) {
            return
        }
        if q.contains("assault")
            && (q.contains("stand down")
                || q.contains("stop")) {
            navigate(to: 7)
            say("Net-Assault stands down from its own "
                + "section — the button is in the "
                + "dashboard there, under the skull. "
                + "Taken you to EMCON.")
            return
        }
        if q.contains("assault") {
            navigate(to: 7)
            say("Net-Assault keeps its own arming: the "
                + "confirmation there names the "
                + "consequence — watchers, intrusion "
                + "detection, questions — and that tap "
                + "stays yours by design. I've taken you "
                + "to EMCON; the section sits under the "
                + "skull, second from the top.")
            return
        }
        if q.contains("clear") || q.contains("delete")
            || q.contains("reset") || q.contains("forget") {
            say(clearGuidance(for: q))
            return
        }
        if q.contains("open") || q.contains("go to")
            || q.contains("show me") || q.contains("take me") {
            if let route = navRoute(for: q) {
                navigate(to: route.0)
                say(route.1)
                return
            }
        }

        // Senses next: the live state of the house.
        if q.contains("on my wire") || q.contains("on the wire")
            || q.contains("on my network")
            || q.contains("who's here")
            || q.contains("who is here")
            || q.contains("neighbors")
            || q.contains("neighbours") {
            say(wireReport())
            return
        }
        if q.contains("last night") || q.contains("knocked")
            || q.contains("what happened") {
            say(nightReport())
            return
        }
        if q.contains("exposed") || q.contains("posture")
            || q.contains("score") || q.contains("visible") {
            say(postureReport())
            return
        }
        if q.contains("learned") || q.contains("facts") {
            say(factsReport())
            return
        }
        if q.contains("mind") || q.contains("subconscious")
            || q.contains("brief") {
            let mind = SubconsciousCenter.shared
            mind.refresh()
            say(mind.awake
                ? mind.brief
                : "The mind is still learning the house "
                  + "— \(mind.eventCount) sealed events "
                  + "so far. It names patterns once "
                  + "history gives it a normal to break.")
            return
        }
        if q.contains("serving") || q.contains("serve up")
            || q.contains("is serve") {
            if let mouth = mouth {
                say(mouth.serveRunning
                    ? "Serve is up"
                      + (mouth.stealth
                         ? " — running unlisted, under "
                           + "stealth."
                         : " — and listed on the wire.")
                    : "Serve is down. Say 'start "
                      + "serving' and I'll raise it from "
                      + "its settings.")
            } else {
                say("Serve's state reaches me once the "
                    + "app has finished waking — a "
                    + "moment.")
            }
            return
        }

        // A device, in depth — every organ's word
        if let neighbor = matchDevice(q) {
            lastDeviceIP = neighbor.ip
            say(deviceReport(neighbor))
            return
        }
        if let ip = lastDeviceIP,
           let neighbor = NeighborhoodStore.shared
               .neighbors.first(where: { $0.ip == ip }) {
            if q.contains("port") {
                say(neighbor.ports.isEmpty
                    ? "\(neighbor.displayName) has no "
                      + "recorded open ports — no knock "
                      + "of ours has found one answering."
                    : "\(neighbor.displayName) answers "
                      + "on: "
                      + neighbor.ports.map(String.init)
                          .joined(separator: ", ")
                      + ".")
                return
            }
            if q.contains("where") {
                say(roomLine(neighbor))
                return
            }
        }

        // The record: the mind's own answering, reused.
        if ["quiet", "foreign", "drift", "first", "asleep",
             "busiest", "missing", "sleep", "heart"]
            .contains(where: q.contains) {
            let found = SubconsciousCenter.shared
                .answer(q)
            if !found.isEmpty {
                say(found.prefix(5).map { event in
                    "— \(event.text) (\(event.module) · "
                        + "\(event.kind) · "
                        + event.when.formatted(
                            date: .abbreviated,
                            time: .shortened)
                }.joined(separator: "\n"))
                return
            }
        }

        // The manual.
        if let entry = SkelliKnowledge.lookup(q) {
            say(entry.body + "\nFind it: \(entry.home).")
            return
        }

        // Open water: her trained mind first, the
        // browser when the mind says the living web
        // is needed — or when no mind can speak.
        consultMindOrResearch(q)
    }

    /// The open question goes to her trained mind
    /// first — Apple's on-device model, when this
    /// build and this phone carry it. It answers
    /// conversation and general knowledge in her
    /// voice, grounded in the house's facts; when
    /// an answer needs the living web, it says so
    /// with one word and the browser goes instead.
    /// No model, or a model error, takes the
    /// browser path exactly as before.
    private func consultMindOrResearch(_ q: String) {
        let started = SkelliMind.consult(
            question: q,
            grounding: mindGrounding(),
            recent: recentLines()) { [weak self] verdict in
            guard let self = self else { return }
            switch verdict {
            case .answer(let text):
                self.say(text)
            case .research:
                self.researchWeb(for: q)
            }
        }
        if started {
            activity = "Thinking…"
        } else {
            researchWeb(for: q)
        }
    }

    /// Her grounding: who she is, the state of the
    /// house right now, and what her manual covers —
    /// the facts the model may speak from, and the
    /// fence it may not cross.
    private func mindGrounding() -> String {
        let wire = NeighborhoodStore.shared
            .neighbors.count
        let titles = SkelliKnowledge.entries
            .map { $0.title }
            .joined(separator: ", ")
        return "You are Skelli, the onboard "
            + "specialist of nightjar-hack, a network "
            + "instrument on this iPhone. You run "
            + "entirely on this phone — nothing told "
            + "to you leaves it. Voice: dry, exact, "
            + "terse. One or two sentences, never "
            + "more unless a list is asked for. No "
            + "preamble, no filler, no repeating the "
            + "question, no describing your own "
            + "thinking. Greetings and small talk get "
            + "a few words back — never an essay, "
            + "never research. The house right now: "
            + "\(wire) devices on the wire; web "
            + "research is "
            + (webResearchEnabled ? "on" : "off")
            + "; you hold \(notes.count) remembered "
            + "notes. Your manual covers: \(titles). "
            + "Orders and house state are handled "
            + "before you are consulted; you answer "
            + "open conversation and general "
            + "knowledge only. Never invent facts "
            + "about this house. If an answer needs "
            + "current facts from outside this "
            + "phone — news, prices, today's "
            + "anything — or you are not sure of "
            + "the facts, reply with exactly one "
            + "word: RESEARCH. Never repeat the "
            + "conversation back, and never write "
            + "'Operator:' or 'Skelli:' — the "
            + "reply is yours alone."
    }

    /// The last few exchanges, so the conversation
    /// she is in is the one she answers in.
    private func recentLines() -> String {
        lines.suffix(6).map { line in
            (line.fromOperator
             ? "Operator: " : "Skelli: ") + line.text
        }.joined(separator: "\n")
    }

    /// What the house cannot answer, the web might —
    private func researchWeb(for q: String) {
        guard webResearchEnabled else {
            say("That's outside the house, and my "
                + "web research is off — it's in my "
                + "menu, under Web research. Inside "
                + "the house I know every tab, organ, "
                + "and switch, and the live state of "
                + "your wire, your log, and your night.")
            return
        }
        guard let query = Self.webQuery(from: q) else {
            say("That one touches the house's own "
                + "record — addresses and the like — "
                + "and I don't send house details "
                + "outward. Ask it as a general "
                + "question, without the house's "
                + "particulars, and I'll research it.")
            return
        }
        mood = .working
        activity = "Researching…"
        SkelliWeb.research(query) { [weak self] result in
            self?.say(result)
        }
    }

    /// Build the outward query: command words off,
    private static func webQuery(from q: String) -> String? {
        let lowered = q.lowercased()
        if ["password", "pairing key", "secret",
            "token", "credential"].contains(
                where: lowered.contains) {
            return nil
        }
        var text = q.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let prefixes = [
            "search the web for", "search online for",
            "search the web", "search online",
            "look up online", "use the web for",
            "use the web", "web search for", "web search",
            "search for", "search", "look up", "research",
            "google", "find out", "find", "tell me about",
            "what is", "what's", "who is", "explain",
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes {
                if text.lowercased().hasPrefix(prefix + " ")
                    || text.lowercased() == prefix {
                    text = String(text.dropFirst(
                        min(prefix.count + 1, text.count)))
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }
        let words = text
            .split(whereSeparator: {
                $0 == " " || $0 == "?" || $0 == "\t"
            })
            .map(String.init)
            .filter { word in
                !isPrivateAddress(word)
                    && !word.hasSuffix(".local")
                    && !word.contains("@")
            }
        let query = words.joined(separator: " ")
        guard query.count >= 3 else { return nil }
        return query
    }

    private static func isPrivateAddress(_ word: String)
        -> Bool {
        let parts = word.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ Int($0) != nil })
        else { return false }
        let first = Int(parts[0]) ?? -1
        let second = Int(parts[1]) ?? -1
        return first == 10 || first == 127
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 169 && second == 254)
    }

    private var capabilities: String {
        "I can work the house: 'sweep the wire', "
            + "'scan me', 'run the audit', 'go dark', "
            + "'stand down', 'start serving', 'stop "
            + "serving', 'stealth on', 'tripwire on' — "
            + "and I can take you anywhere: 'open the "
            + "map', 'open the mind', 'open knocktalk'. "
            + "I can report the live state: who's on "
            + "the wire, what knocked last night, how "
            + "exposed this phone is, what the mind "
            + "has learned. And I can explain anything "
            + "in the app — try 'what is the drill' or "
            + "'how does cadence work'. Loud and "
            + "destructive levers — arming Net-Assault, "
            + "clearing records — keep their own "
            + "confirmations; I'll walk you to those. "
            + "I also run the drill ('run the drill') "
            + "and the ear ('start listening'), and I "
            + "can name a device: 'name 192.168.4.50 "
            + "the printer'. Tell me 'remember …' and "
            + "I keep it across conversations. And "
            + "when a question is beyond the house, I "
            + "research it through this phone's own "
            + "network connection, through my own "
            + "browser: it searches, visits, and "
            + "reads the pages itself — standards, "
            + "papers, books, code, and the open web "
            + "— working only the sources that let a "
            + "machine in cleanly, and bringing the "
            + "answer back with its sources named. "
            + "'Search the web for …' forces the "
            + "outward look. House particulars are "
            + "never sent out; the switch is in my "
            + "menu."
    }

    // MARK: memory and devices

    private func notesReport() -> String {
        guard !notes.isEmpty else {
            return "I hold nothing yet. Tell me "
                + "'remember …' and I keep it — names, "
                + "habits, how you like things read — "
                + "across conversations."
        }
        return "What I remember:\n"
            + notes.map {
                "— \($0.text) (kept "
                    + $0.learnedAt.formatted(
                        date: .abbreviated, time: .omitted)
                    + ")"
            }.joined(separator: "\n")
    }

    private func matchDevice(_ q: String) -> Neighbor? {
        NeighborhoodStore.shared.neighbors.first {
            q.contains($0.ip)
                || q.contains($0.displayName.lowercased())
                || ($0.name.map {
                    q.contains($0.lowercased()) } ?? false)
        }
    }

    private func roomLine(_ neighbor: Neighbor) -> String {
        // A placement is a position; the room is
        if let room = MapStore.shared.room(of: neighbor.ip) {
            return "\(neighbor.displayName) sits in "
                + room.name + " — your placement, kept "
                + "by the Map."
        }
        if MapStore.shared.placements[neighbor.ip] != nil {
            return "\(neighbor.displayName) is placed "
                + "on the Map, on open floor outside "
                + "any named room."
        }
        return "\(neighbor.displayName) is unplaced — "
            + "it waits in the Map's tray for you to "
            + "say where it sits."
    }

    private func deviceReport(_ neighbor: Neighbor)
        -> String {
        var lines: [String] = []
        lines.append("\(neighbor.displayName) — "
            + "\(neighbor.ip).")
        if let wire = neighbor.name,
           wire != neighbor.displayName {
            lines.append("On the wire it answers as "
                + wire + ".")
        }
        lines.append("Seen \(neighbor.sightings) time"
            + (neighbor.sightings == 1 ? "" : "s")
            + "; last "
            + InstrumentCenter.ageLine(neighbor.lastSeen)
            + ".")
        lines.append(neighbor.ports.isEmpty
            ? "No recorded open ports."
            : "Answers on: "
              + neighbor.ports.map(String.init)
                  .joined(separator: ", ") + ".")
        lines.append(roomLine(neighbor))
        let acked = MapStore.shared
            .ackedDrift[neighbor.ip] ?? 0
        let unacked = max(0, neighbor.drift.count - acked)
        if !neighbor.drift.isEmpty {
            lines.append("Drift: "
                + (neighbor.drift.first ?? "")
                + (unacked > 0
                   ? " — \(unacked) unacknowledged."
                   : " — all acknowledged."))
        }
        if neighbor.arrivals > 0 {
            lines.append("It has knocked at this "
                + "phone's door \(neighbor.arrivals) "
                + "time"
                + (neighbor.arrivals == 1 ? "" : "s")
                + ".")
        }
        if let mention = Journal.events(limit: 400)
            .first(where: { $0.text.contains(neighbor.ip) }) {
            lines.append("The log's latest word: "
                + mention.text + " ("
                + mention.when.formatted(
                    date: .abbreviated, time: .shortened)
                + ")")
        }
        return lines.joined(separator: "\n")
    }

    private func nameDevice(_ q: String) -> Bool {
        let tokens = q.split(separator: " ")
            .map(String.init)
        guard let ipIndex = tokens.firstIndex(where: {
            let parts = $0.split(separator: ".")
            return parts.count == 4
                && parts.allSatisfy {
                    Int($0) != nil
                        && (0...255).contains(Int($0) ?? -1)
                }
        }) else { return false }
        let ip = tokens[ipIndex]
        guard let neighbor = NeighborhoodStore.shared
            .neighbors.first(where: { $0.ip == ip }) else {
            say("The wire doesn't know " + ip + " yet — "
                + "I can only name devices the house "
                + "has met. A sweep might introduce you.")
            return true
        }
        var words = Array(tokens.dropFirst(ipIndex + 1))
        if words.first == "the" { words.removeFirst() }
        let name = words.joined(separator: " ")
        guard !name.isEmpty else {
            say("Call it what? 'Name " + ip + " the "
                + "printer' and it's done.")
            return true
        }
        NeighborhoodStore.shared.rename(
            ip: ip, to: name, mark: neighbor.customMark)
        lastDeviceIP = ip
        say("Named. " + ip + " answers as " + name
            + " now — on the board, the Map, its "
            + "dossier, and in the mind's findings. "
            + "The wire's own name for it is kept "
            + "underneath, only outranked.")
        return true
    }

    // MARK: hands

    private func runDrill() {
        guard let emcon = emcon, let mouth = mouth else {
            say("The drill is EMCON's and its organs "
                + "haven't reached me yet — open the "
                + "EMCON tab once and ask again.")
            return
        }
        mood = .working
        emcon.runDrill(mouth: mouth)
        say("The drill is running — scan, go dark, "
            + "scan again. Its readout lands in "
            + "EMCON's drill section, where the ledger "
            + "names what went quiet.")
        activity = "Running the drill — scan, dark, "
            + "scan…" 
    }

    private func startListening() {
        guard let post = post else {
            say("The ear hasn't reached me yet — open "
                + "the Listen tab once and ask again.")
            return
        }
        if post.session != nil {
            say("The ear is already open — "
                + "\(post.deviceCount) devices in its "
                + "registry this session.")
            return
        }
        post.start(label: "Skelli")
        say("The ear is open. It hears passively — "
            + "it never connects or pairs — and its "
            + "sightings land in the Listen tab and "
            + "the log.")
    }

    private func runSweep() {
        guard !scanner.sweeping else {
            say("A sweep is already running — its "
                + "answers are landing in the "
                + "Neighborhood as they come.")
            return
        }
        mood = .working
        activity = "Sweeping the wire on port 80…"
        scanner.sweep(port: 80)
        sweepWatch = scanner.$sweeping
            .dropFirst()
            .filter { !$0 }
            .first()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let hosts = self.scanner.sweepHosts
                self.say(hosts.isEmpty
                    ? "The sweep finished: nobody "
                      + "answered on port 80."
                    : "The sweep finished: "
                      + "\(hosts.count) host"
                      + (hosts.count == 1 ? "" : "s")
                      + " answered — "
                      + hosts.prefix(5).map(\.ip)
                          .joined(separator: ", ")
                      + (hosts.count > 5 ? "…" : "")
                      + ". They're in the Neighborhood, "
                      + "and the Map has them in its "
                      + "tray.")
            }
    }

    private func runSelfScan() {
        guard let emcon = emcon else {
            say("The self-scan is EMCON's organ and it "
                + "hasn't reached me yet — open the "
                + "EMCON tab once and ask again.")
            return
        }
        mood = .working
        activity = "Knocking this phone, every "
            + "census port…"
        emcon.runSelfScan { [weak self] in
            guard let self = self,
                  let emcon = self.emcon else { return }
            if emcon.exposures.isEmpty {
                self.say("The self-scan found nothing "
                    + "answering. On the wire, this phone "
                    + "is a closed door.")
            } else {
                self.say("The self-scan found "
                    + "\(emcon.exposures.count) listener"
                    + (emcon.exposures.count == 1
                       ? "" : "s")
                    + " answering:\n"
                    + emcon.exposures.prefix(8).map {
                        "— \(Emcon.exposureLine($0))"
                    }.joined(separator: "\n")
                    + "\nEMCON's self-recon holds the "
                    + "full readout.")
            }
        }
    }

    private func runAudit() {
        guard let emcon = emcon else {
            say("The audit is EMCON's organ and it "
                + "hasn't reached me yet — open the "
                + "EMCON tab once and ask again.")
            return
        }
        mood = .working
        activity = "Listening for this phone's own "
            + "announcements…"
        emcon.runBonjourAudit { [weak self] in
            guard let self = self,
                  let emcon = self.emcon else { return }
            if emcon.announcers.isEmpty {
                self.say("The audit heard \(emcon.heardCount) "
                    + "announcements on the wire and none "
                    + "of them were this phone's. It is "
                    + "not introducing itself to anyone.")
            } else {
                self.say("This phone is announcing "
                    + "itself:\n"
                    + emcon.announcers.map {
                        "— \(Emcon.announcerLine($0))"
                    }.joined(separator: "\n"))
            }
        }
    }

    private func goDark() {
        guard let emcon = emcon, let mouth = mouth else {
            say("EMCON's organs haven't reached me yet "
                + "— open the EMCON tab once and ask "
                + "again.")
            return
        }
        emcon.activate(mouth: mouth)
        say("Dark. Stealth is on, the beacon and GATT "
            + "host are down, and the tripwire is armed. "
            + "What EMCON doesn't own — the OS's own "
            + "listeners, your VPN's — still shows, and "
            + "the score says so honestly.")
    }

    private func standDown() {
        emcon?.deactivate()
        say("EMCON stood down — the tripwire is off. "
            + "Stealth, the beacon, and the host stay "
            + "exactly as they are; re-arming an "
            + "emission is always its own deliberate "
            + "act.")
    }

    // MARK: senses

    private func wireReport() -> String {
        let all = NeighborhoodStore.shared.neighbors
        guard !all.isEmpty else {
            return "The wire knows nobody yet — no "
                + "sweep has answered, nothing has "
                + "announced itself, and nothing has "
                + "knocked. Say 'sweep the wire' and "
                + "I'll populate it."
        }
        let placed = all.filter {
            MapStore.shared.placements[$0.ip] != nil
        }.count
        let names = all.sorted { $0.lastSeen > $1.lastSeen }
            .prefix(5)
            .map { "\($0.displayName) (\($0.ip))" }
            .joined(separator: ", ")
        var report = "The wire knows \(all.count) device"
            + (all.count == 1 ? "" : "s")
            + (placed > 0
               ? ", \(placed) of them placed on the Map"
               : "")
            + ". Most recently seen: \(names)"
            + (all.count > 5 ? "…" : "")
            + ". The Neighborhood board in Scan holds "
            + "them all."
        if let drifting = all.first(where: {
            $0.drift.count
                > (MapStore.shared.ackedDrift[$0.ip] ?? 0)
        }) {
            pendingAction = { [weak self] in
                self?.navigate(to: 4)
                self?.say("The Map is open — "
                    + drifting.displayName
                    + "'s node glows orange until you "
                    + "tap it and acknowledge the "
                    + "drift.")
            }
            report += "\n" + drifting.displayName
                + " carries drift the house hasn't "
                + "acknowledged. Shall I take you to "
                + "the Map?"
        }
        return report
    }

    private func nightReport() -> String {
        let events = Journal.events(limit: 4000)
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        let last24 = events.filter { $0.when > dayAgo }
        guard !last24.isEmpty else {
            return "The log holds nothing from the "
                + "last day — a quiet house, or a young "
                + "one."
        }
        let latest = last24.prefix(3).map {
            "— \($0.text) (\($0.when.formatted(date: .omitted, time: .shortened)))"
        }.joined(separator: "\n")
        return "The last day sealed \(last24.count) "
            + "events. The latest:\n\(latest)"
    }

    private func postureReport() -> String {
        guard let emcon = emcon else {
            return "EMCON's organs haven't reached me "
                + "yet — open the EMCON tab once and "
                + "ask again."
        }
        var lines: [String] = []
        lines.append(emcon.active
            ? "EMCON is active — the house is dark and "
              + "the tripwire is armed."
            : "EMCON is standing down — the tripwire "
              + "is off.")
        if let scanned = emcon.lastScanAt {
            lines.append("The last self-scan ("
                + InstrumentCenter.ageLine(scanned)
                + ") found \(emcon.exposures.count) "
                + "listener"
                + (emcon.exposures.count == 1 ? "" : "s")
                + " answering"
                + (emcon.exposures.isEmpty
                   ? "."
                   : ": " + emcon.exposures.prefix(4)
                       .map(Emcon.exposureLine)
                       .joined(separator: ", ") + "."))
        } else {
            lines.append("No self-scan yet — say 'scan "
                + "me' and I'll knock every census "
                + "port.")
        }
        if let audited = emcon.lastAuditAt {
            lines.append("The last audit ("
                + InstrumentCenter.ageLine(audited)
                + ") heard this phone announcing "
                + "\(emcon.announcers.count) service"
                + (emcon.announcers.count == 1
                   ? "" : "s") + ".")
        }
        return lines.joined(separator: " ")
    }

    private func factsReport() -> String {
        let facts = SubconsciousCenter.shared.facts
        guard !facts.isEmpty else {
            return "The mind has consolidated nothing "
                + "yet — facts are earned from a "
                + "fortnight of record. As it learns, "
                + "they'll stand in the Subconscious, "
                + "each forgettable."
        }
        return "What the house has learned:\n"
            + facts.prefix(6).map { "— \($0.text)" }
                .joined(separator: "\n")
    }

    // MARK: guidance for the levers that stay the operator's

    private func clearGuidance(for q: String) -> String {
        if q.contains("night log") || q.contains("journal")
            || q.contains("log") {
            navigate(to: 7)
            return "The Night log clears from its own "
                + "page — the Entries section holds "
                + "'Clear the log', behind a "
                + "confirmation, and the seal chain "
                + "starts fresh. Clears stay your tap; "
                + "I've taken you to EMCON, where the "
                + "brief and the log live."
        }
        if q.contains("neighbor") || q.contains("wire")
            || q.contains("devices") {
            navigate(to: 4)
            return "The Neighborhood clears from its "
                + "board in Scan — open the Devices "
                + "door and 'Clear the Neighborhood' "
                + "sits at the bottom, behind a "
                + "confirmation; their Map placements "
                + "go with them. Taken you there."
        }
        if q.contains("map") {
            navigate(to: 4)
            return "The Map resets from its own More "
                + "menu — 'Reset the map…' — rooms and "
                + "placements forgotten, devices kept. "
                + "Open the Map at the top of Scan."
        }
        if q.contains("thread") || q.contains("knocktalk")
            || q.contains("cadence") {
            navigate(to: 8)
            return "Knocktalk's Housekeeping holds both "
                + "doors: 'Clear all threads' and "
                + "'Forget cadence profiles', each "
                + "behind a confirmation. The pairing "
                + "key is never touched. Taken you "
                + "there."
        }
        if q.contains("mind") || q.contains("subconscious")
            || q.contains("facts") {
            navigate(to: 7)
            return "The mind's memory resets from the "
                + "Subconscious's own Housekeeping — "
                + "and single facts can be forgotten "
                + "one by one in 'What the house has "
                + "learned', where the forgetting "
                + "itself is remembered. Open the mind "
                + "from EMCON."
        }
        return "Every store in the house has its own "
            + "clear, behind its own confirmation — "
            + "the Night log, the Neighborhood, the "
            + "Map, the mind's memory, Knocktalk's "
            + "threads and cadence profiles, and "
            + "reset-all-settings in About. Name one "
            + "and I'll walk you to its door; the tap "
            + "stays yours."
    }

    private func navRoute(for q: String) -> (Int, String)? {
        let routes: [(String, Int, String)] = [
            ("map", 4, "The Map crowns the Scan tab — "
                + "its own section at the very top. "
                + "Taken you there."),
            ("scan", 4, "Scan — taken you there."),
            ("recon", 6, "The Recon bench — taken you "
                + "there."),
            ("emcon", 7, "EMCON — taken you there."),
            ("mind", 7, "The Subconscious card lives "
                + "in EMCON — 'Open the mind' unfolds "
                + "its full reading. Taken you there."),
            ("subconscious", 7, "The Subconscious card "
                + "lives in EMCON — 'Open the mind' "
                + "unfolds its full reading. Taken you "
                + "there."),
            ("knocktalk", 8, "Knocktalk — taken you "
                + "there."),
            ("listen", 0, "Listen — taken you there."),
            ("send", 1, "Send — taken you there."),
            ("serve", 2, "Serve — taken you there."),
            ("session", 3, "Sessions — taken you there."),
            ("colour", 5, "Colours lives inside About "
                + "— its own section there. Taken you "
                + "to About."),
            ("color", 5, "Colours lives inside About "
                + "— its own section there. Taken you "
                + "to About."),
            ("about", 5, "About — the house's options "
                + "hub. Taken you there."),
            ("instrument", 7, "The Instrument is a "
                + "section in EMCON, below the "
                + "Subconscious. Taken you there."),
            ("assault", 7, "Net-Assault's section sits "
                + "in EMCON under the skull, second "
                + "from the top. Taken you there."),
        ]
        for route in routes where q.contains(route.0) {
            return (route.1, route.2)
        }
        return nil
    }
}

// MARK: - Her mind

/// Fires once: whichever mind in the cascade
/// answers first, answers — the rest stand down.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Her trained minds, in cascade. Apple's on-device
/// model (Foundation Models, iOS 26) speaks first —
/// fast, free, on the phone. Her weights bench (an
/// open-weights model the operator stages into the
/// bundle, run through MLX) speaks when Apple's
/// cannot, or first when the operator prefers it.
/// When no mind can speak — or one stalls past the
/// watchdog — the verdict is research, and her
/// browser goes, exactly as it did before any mind
/// existed. Nothing either mind hears leaves the
/// phone.
enum SkelliMind {
    enum Verdict {
        case answer(String)
        case research
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SkelliModelBox.available
        }
        #endif
        return false
    }

    /// Whether the MLX package rode into this
    /// build at all — her Weights sheet says so
    /// plainly when it didn't.
    static var benchBuiltIn: Bool {
        #if canImport(MLXLLM)
        return true
        #else
        return false
        #endif
    }

    static var weightsReady: Bool {
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *) {
            return SkelliWeights.canSpeak
        }
        #endif
        return false
    }

    /// Wake Apple's model before it is needed.
    static func warm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            SkelliModelBox.warm()
        }
        #endif
    }

    /// Read a mind's words into a verdict. Silence
    /// or failure is no verdict at all.
    private static func interpret(_ text: String?)
        -> Verdict? {
        guard let text = text else { return nil }
        let trimmed = decontaminate(text)
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("RESEARCH") {
            return .research
        }
        return .answer(trimmed)
    }

    /// Small models love to continue the script
    /// they were shown — echoing the transcript
    /// back before answering. Cut any echo: what
    /// she says is what follows the last script
    /// marker, marker lines removed.
    private static func decontaminate(
        _ text: String) -> String {
        guard text.contains("Operator:") else {
            return text
        }
        var lines = text.components(
            separatedBy: "\n")
        if let last = lines.lastIndex(where: {
            $0.hasPrefix("Skelli:")
        }) {
            lines = Array(lines[last...])
        }
        let kept = lines.filter {
            !$0.hasPrefix("Operator:")
        }.map { line -> String in
            line.hasPrefix("Skelli:")
                ? String(line.dropFirst(7))
                    .trimmingCharacters(
                        in: .whitespaces)
                : line
        }
        let cleaned = kept.joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }

    #if canImport(MLXLLM)
    private static func weightsVerdict(
        instructions: String, prompt: String)
        async -> Verdict? {
        if #available(iOS 17.0, *) {
            return interpret(await SkelliWeights.ask(
                instructions: instructions,
                prompt: prompt))
        }
        return nil
    }
    #endif

    /// Consult her minds. False means no mind can
    /// speak and the caller falls back at once;
    /// true means the verdict arrives on the main
    /// queue.
    static func consult(question: String,
                        grounding: String,
                        recent: String,
                        completion:
                            @escaping (Verdict) -> Void)
        -> Bool {
        let prompt = recent.isEmpty
            ? question
            : recent + "\nOperator: " + question
        let preferWeights = UserDefaults.standard
            .bool(forKey: "skelli.preferWeights")
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SkelliModelBox.available {
            runCascade(prompt: prompt,
                       grounding: grounding,
                       preferWeights: preferWeights,
                       completion: completion)
            return true
        }
        #endif
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *),
           SkelliWeights.canSpeak {
            Task {
                let verdict = await weightsVerdict(
                    instructions: grounding,
                    prompt: prompt) ?? .research
                await MainActor.run {
                    completion(verdict)
                }
            }
            return true
        }
        #endif
        return false
    }

    #if canImport(FoundationModels)
    /// Apple's model first (or the bench, when
    /// preferred), the other bench on failure, and
    /// a thirty-second watchdog over all of it: a
    /// stalled mind must never hold her answer
    /// hostage.
    @available(iOS 26.0, *)
    private static func runCascade(
        prompt: String, grounding: String,
        preferWeights: Bool,
        completion: @escaping (Verdict) -> Void) {
        let flag = OnceFlag()
        func finish(_ verdict: Verdict) {
            if flag.claim() {
                Task {
                    await MainActor.run {
                        completion(verdict)
                    }
                }
            }
        }
        Task {
            #if canImport(MLXLLM)
            if preferWeights,
               let verdict = await weightsVerdict(
                   instructions: grounding,
                   prompt: prompt) {
                finish(verdict)
                return
            }
            #endif
            if let verdict = interpret(
                await SkelliModelBox.run(
                    instructions: grounding,
                    prompt: prompt)) {
                finish(verdict)
                return
            }
            #if canImport(MLXLLM)
            if !preferWeights,
               let verdict = await weightsVerdict(
                   instructions: grounding,
                   prompt: prompt) {
                finish(verdict)
                return
            }
            #endif
            finish(.research)
        }
        Task {
            try? await Task.sleep(
                nanoseconds: 30_000_000_000)
            finish(.research)
        }
    }
    #endif
}

#if canImport(FoundationModels)
/// Apple's model itself, behind the gate.
@available(iOS 26.0, *)
private enum SkelliModelBox {
    static var available: Bool {
        if case .available = SystemLanguageModel
            .default.availability {
            return true
        }
        return false
    }

    static func warm() {
        LanguageModelSession(
            instructions: "You are Skelli.").prewarm()
    }

    static func run(instructions: String,
                    prompt: String) async -> String? {
        let session = LanguageModelSession(
            instructions: instructions)
        do {
            let response = try await session
                .respond(to: prompt)
            return response.content
        } catch {
            return nil
        }
    }
}
#endif

#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
#if canImport(MLXHuggingFace)
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif

/// Her weights bench: open-weights models run
/// through MLX. The operator picks one in her
/// Weights sheet; it downloads from the Hugging
/// Face hub into the app's own cache, is selected
/// there, and is kept resident once woken. A
/// folder named SkelliWeights staged into the
/// bundle still serves as a bench when nothing
/// has been chosen. Nothing here compiles unless
/// the mlx-swift-lm package is in the target.
@available(iOS 17.0, *)
private enum SkelliWeights {
    private static var container: ModelContainer?
    private static var containerKey: String?

    /// The model chosen in her Weights sheet.
    static var selectedID: String? {
        UserDefaults.standard.string(
            forKey: "skelli.weightsModel")
    }

    /// The chosen model, once its download has
    /// finished — the cascade only ever speaks to
    /// a bench that is actually on the phone.
    static var downloadedSelection: String? {
        guard let id = selectedID else { return nil }
        let downloaded = UserDefaults.standard
            .stringArray(
                forKey: "skelli.weightsDownloaded")
            ?? []
        return downloaded.contains(id) ? id : nil
    }

    static var folderURL: URL? {
        Bundle.main.url(forResource: "SkelliWeights",
                        withExtension: nil)
    }

    static var canSpeak: Bool {
        container != nil
            || downloadedSelection != nil
            || folderURL != nil
    }

    static func ask(instructions: String,
                    prompt: String) async -> String? {
        do {
            let box = try await loadedContainer()
            let text = try await box.perform {
                context in
                let userInput = UserInput(chat: [
                    .system(instructions),
                    .user(prompt)
                ])
                let input = try await context.processor
                    .prepare(input: userInput)
                var parameters = GenerateParameters()
                parameters.maxTokens = 240
                parameters.temperature = 0.6
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: parameters,
                    context: context)
                var raw = ""
                for await generation in stream {
                    if let chunk = generation.chunk {
                        raw += chunk
                    }
                }
                let trimmed = raw.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return text
        } catch {
            return nil
        }
    }

    private static func loadedContainer()
        async throws -> ModelContainer {
        let key = downloadedSelection ?? "folder"
        if let container = container,
           containerKey == key {
            return container
        }
        let box: ModelContainer
        if let id = downloadedSelection {
            box = try await LLMModelFactory.shared
                .loadContainer(
                    from: #hubDownloader(),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: ModelConfiguration(
                        id: id))
        } else if let folder = folderURL {
            box = try await LLMModelFactory.shared
                .loadContainer(
                    from: folder,
                    using: #huggingFaceTokenizerLoader())
        } else {
            throw WeightsError.noBench
        }
        container = box
        containerKey = key
        return box
    }

    private enum WeightsError: Error {
        case noBench
    }
}
#endif

// MARK: - Her body

/// Skelli, drawn from the original: the skeleton in
struct SkelliAvatar: View {
    var mood: SkelliMood = .idle
    var size: CGFloat = 96
    @ObservedObject private var themes = ThemeCenter.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) {
            timeline in
            Canvas { context, canvas in
                draw(context: context, canvas: canvas,
                     t: timeline.date
                         .timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size * 0.75, height: size)
    }

    private func draw(context: GraphicsContext,
                      canvas: CGSize, t: TimeInterval) {
        let u = canvas.width / 75
        let accent = themes.current.accent
        let bone = Color(red: 0.93, green: 0.92,
                         blue: 0.89)
        let boneShade = Color(red: 0.79, green: 0.78,
                              blue: 0.72)
        let black = Color(red: 0.05, green: 0.05,
                          blue: 0.07)
        let navy = Color(red: 0.16, green: 0.24,
                         blue: 0.42)
        let navyDark = Color(red: 0.10, green: 0.16,
                             blue: 0.30)
        let steel = Color(red: 0.36, green: 0.42,
                          blue: 0.50)
        let steelDark = Color(red: 0.24, green: 0.29,
                              blue: 0.36)
        let shoe = Color(red: 0.23, green: 0.27,
                           blue: 0.36)
        let detail = size >= 56

        let bob = mood == .speaking
            ? sin(t * 2.2) * 0.5 : sin(t * 1.3) * 0.8
        let dy = bob * u
        let faceDX = mood == .thinking
            ? sin(t * 0.8) * 0.9 * u : 0
        let faceDY = (mood == .working ? 1.1 : 0) * u

        // Legs and sneakers — the ground she stands on.
        for side in [-1.0, 1.0] {
            let hipX = (37.5 + side * 6.5) * u
            let kneeX = (37.5 + side * 6.8) * u
            var leg = Path()
            leg.move(to: CGPoint(x: hipX, y: 80 * u))
            leg.addLine(to: CGPoint(x: kneeX, y: 90 * u))
            leg.addLine(to: CGPoint(x: kneeX, y: 96 * u))
            context.stroke(leg, with: .color(boneShade),
                           style: StrokeStyle(
                               lineWidth: 4.2 * u,
                               lineCap: .round,
                               lineJoin: .round))
            context.fill(
                Path(ellipseIn: CGRect(
                    x: kneeX - 2 * u, y: 88.2 * u,
                    width: 4 * u, height: 4 * u)),
                with: .color(bone))
            context.fill(
                Path(roundedRect: CGRect(
                    x: kneeX - 6.8 * u, y: 95.6 * u,
                    width: 13.5 * u, height: 4.4 * u),
                     cornerRadius: 2 * u),
                with: .color(shoe))
            if detail {
                for lace in 0..<2 {
                    let lx = kneeX
                        + (-2.2 + Double(lace) * 3.4) * u
                    var mark = Path()
                    mark.move(to: CGPoint(x: lx, y: 96.6 * u))
                    mark.addLine(to: CGPoint(
                        x: lx + 1.6 * u, y: 98 * u))
                    context.stroke(
                        mark, with: .color(black.opacity(0.5)),
                        lineWidth: max(0.7, 0.7 * u))
                }
            }
        }

        // The pelvis, below the hem.
        context.fill(
            Path(ellipseIn: CGRect(
                x: 30 * u, y: 75 * u + dy * 0.4,
                width: 15 * u, height: 7.5 * u)),
            with: .color(boneShade))

        // The open hoodie: two panels, a hem, and the
        for panelX in [17.0, 41.0] {
            context.fill(
                Path(roundedRect: CGRect(
                    x: panelX * u, y: 41 * u + dy,
                    width: 17 * u, height: 33 * u),
                     cornerRadius: 5 * u),
                with: .color(navy))
        }
        context.fill(
            Path(roundedRect: CGRect(
                x: 33.5 * u, y: 42 * u + dy,
                width: 8 * u, height: 27 * u),
                 cornerRadius: 3 * u),
            with: .color(black.opacity(0.85)))
        if detail {
            for rib in 0..<4 {
                let ry = (46 + Double(rib) * 5.5) * u + dy
                var arc = Path()
                arc.move(to: CGPoint(x: 33.8 * u, y: ry))
                arc.addQuadCurve(
                    to: CGPoint(x: 41.2 * u, y: ry),
                    control: CGPoint(x: 37.5 * u,
                                     y: ry + 2.6 * u))
                context.stroke(
                    arc, with: .color(bone),
                    style: StrokeStyle(lineWidth: 1.9 * u,
                                       lineCap: .round))
            }
            var sternum = Path()
            sternum.move(to: CGPoint(x: 37.5 * u,
                                     y: 44 * u + dy))
            sternum.addLine(to: CGPoint(x: 37.5 * u,
                                        y: 66 * u + dy))
            context.stroke(sternum, with: .color(bone),
                           lineWidth: 2.2 * u)
        }
        context.fill(
            Path(roundedRect: CGRect(
                x: 17 * u, y: 68 * u + dy,
                width: 41 * u, height: 6.5 * u),
                 cornerRadius: 3 * u),
            with: .color(navyDark))

        // The hood, up and framing the skull.
        context.fill(
            Path(roundedRect: CGRect(
                x: 15 * u, y: 3 * u + dy,
                width: 45 * u, height: 40 * u),
                 cornerRadius: 17 * u),
            with: .color(navy))
        context.fill(
            Path(ellipseIn: CGRect(
                x: 19.5 * u, y: 7 * u + dy,
                width: 36 * u, height: 34 * u)),
            with: .color(navyDark))

        // Thinking: three dots circle above the hood.
        if mood == .thinking {
            for i in 0..<3 {
                let phase = t * 2.4 + Double(i) * 0.9
                let a = 0.35 + 0.65 * max(0, sin(phase))
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: (26 + Double(i) * 11) * u - 2 * u,
                        y: 0.2 * u,
                        width: 4 * u, height: 4 * u)),
                    with: .color(accent.opacity(a)))
            }
        }

        // The skull: cranium, grin, and the empty
        let fx = faceDX
        let fy = dy + faceDY
        context.fill(
            Path(ellipseIn: CGRect(
                x: 24 * u + fx, y: 9 * u + fy,
                width: 27 * u, height: 24 * u)),
            with: .color(bone))
        let jawDy = mood == .speaking
            ? abs(sin(t * 9)) * 1.1 * u : 0
        context.fill(
            Path(roundedRect: CGRect(
                x: 28.5 * u + fx, y: 28.5 * u + fy + jawDy,
                width: 18 * u, height: 9.5 * u),
                 cornerRadius: 3.5 * u),
            with: .color(bone))
        var grin = Path()
        grin.move(to: CGPoint(x: 30 * u + fx,
                              y: 33.5 * u + fy + jawDy))
        grin.addLine(to: CGPoint(x: 45 * u + fx,
                                 y: 33.5 * u + fy + jawDy))
        context.stroke(grin, with: .color(black.opacity(0.65)),
                       lineWidth: max(0.8, 0.9 * u))
        if detail {
            for tooth in 1...4 {
                let tx = (30 + Double(tooth) * 3) * u + fx
                var tick = Path()
                tick.move(to: CGPoint(
                    x: tx, y: 33.5 * u + fy + jawDy))
                tick.addLine(to: CGPoint(
                    x: tx, y: 36.3 * u + fy + jawDy))
                context.stroke(
                    tick, with: .color(black.opacity(0.4)),
                    lineWidth: max(0.6, 0.6 * u))
            }
        }
        let cycle = t.truncatingRemainder(dividingBy: 3.9)
        let open = cycle < 3.74 ? 1.0 : 0.15
        for side in [-1.0, 1.0] {
            let ex = (37.5 + side * 6.8) * u + fx
            context.fill(
                Path(ellipseIn: CGRect(
                    x: ex - 4.3 * u,
                    y: 22.7 * u + fy - 5.2 * u * open,
                    width: 8.6 * u,
                    height: 10.4 * u * open)),
                with: .color(black))
        }
        var nose = Path()
        nose.move(to: CGPoint(x: 37.5 * u + fx,
                              y: 26 * u + fy))
        nose.addLine(to: CGPoint(x: 35 * u + fx,
                                 y: 30.5 * u + fy))
        nose.addLine(to: CGPoint(x: 40 * u + fx,
                                 y: 30.5 * u + fy))
        nose.closeSubpath()
        context.fill(nose, with: .color(black))

        // Arms: navy sleeves down to bone hands that
        let tapA = mood == .working
            ? sin(t * 11) * 1.3 * u : 0
        let tapB = mood == .working
            ? cos(t * 11) * 1.3 * u : 0
        for (shoulder, wrist, hand, tap) in [
            (CGPoint(x: 20 * u, y: 45 * u),
             CGPoint(x: 22.5 * u, y: 60 * u),
             CGPoint(x: 21.5 * u, y: 69 * u), tapA),
            (CGPoint(x: 55 * u, y: 45 * u),
             CGPoint(x: 52.5 * u, y: 60 * u),
             CGPoint(x: 53.5 * u, y: 69 * u), tapB)] {
            var sleeve = Path()
            sleeve.move(to: CGPoint(x: shoulder.x,
                                    y: shoulder.y + dy))
            sleeve.addLine(to: CGPoint(x: wrist.x,
                                       y: wrist.y + dy))
            context.stroke(sleeve, with: .color(navy),
                           style: StrokeStyle(
                               lineWidth: 7 * u,
                               lineCap: .round))
            var forearm = Path()
            forearm.move(to: CGPoint(x: wrist.x,
                                     y: wrist.y + dy))
            forearm.addLine(to: CGPoint(
                x: hand.x, y: hand.y + dy + tap))
            context.stroke(forearm, with: .color(boneShade),
                           style: StrokeStyle(
                               lineWidth: 3.4 * u,
                               lineCap: .round))
        }

        // The gray laptop, held — its back to us.
        let lapBob = mood == .working
            ? sin(t * 11) * 0.3 * u : 0
        let lid = CGRect(x: 19.5 * u,
                         y: 55 * u + dy + lapBob,
                         width: 36 * u, height: 21 * u)
        context.fill(Path(roundedRect: lid,
                          cornerRadius: 2.2 * u),
                     with: .color(steel))
        context.stroke(Path(roundedRect: lid,
                            cornerRadius: 2.2 * u),
                       with: .color(steelDark),
                       lineWidth: max(0.8, 0.9 * u))
        var base = Path()
        base.move(to: CGPoint(x: 18 * u,
                              y: 76 * u + dy + lapBob))
        base.addLine(to: CGPoint(x: 57 * u,
                                 y: 76 * u + dy + lapBob))
        base.addLine(to: CGPoint(x: 59.5 * u,
                                 y: 79 * u + dy + lapBob))
        base.addLine(to: CGPoint(x: 15.5 * u,
                                 y: 79 * u + dy + lapBob))
        base.closeSubpath()
        context.fill(base, with: .color(steelDark))

        // Her fingers over the laptop's near edge —
        if detail {
            for (hx, tap) in [(24.0, tapA), (28.5, tapB),
                              (46.5, tapB), (51.0, tapA)] {
                var finger = Path()
                finger.move(to: CGPoint(
                    x: hx * u, y: 74.5 * u + dy + lapBob))
                finger.addLine(to: CGPoint(
                    x: hx * u,
                    y: 78.5 * u + dy + lapBob + tap))
                context.stroke(
                    finger, with: .color(bone),
                    style: StrokeStyle(lineWidth: 2 * u,
                                       lineCap: .round))
            }
        }
    }
}

// MARK: - Her living model

/// Herself, alive: the same 3D animation that fronts
/// the assistant — resting, conjuring, at the desk,
/// talking — chosen by her mood and looped without
/// end. The films ride the bundle as skelli-*.mp4;
/// until they are in the tree, her drawn model
/// stands in.
struct SkelliLiveView: View {
    var mood: SkelliMood = .idle
    var size: CGFloat = 96

    static var filmsPresent: Bool {
        Bundle.main.url(forResource: "skelli-idle",
                        withExtension: "mp4") != nil
    }

    private var film: String {
        switch mood {
        case .idle: return "skelli-idle"
        case .thinking: return "skelli-thinking"
        case .working: return "skelli-working"
        case .speaking: return "skelli-talking"
        }
    }

    var body: some View {
        if Self.filmsPresent {
            SkelliFilm(name: film)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(
                    cornerRadius: size * 0.2))
        } else {
            SkelliAvatar(mood: mood, size: size)
        }
    }
}

struct SkelliFilm: UIViewRepresentable {
    var name: String

    func makeUIView(context: Context) -> SkelliFilmView {
        let view = SkelliFilmView()
        view.play(name)
        return view
    }

    func updateUIView(_ view: SkelliFilmView,
                      context: Context) {
        view.play(name)
    }

    static func dismantleUIView(_ view: SkelliFilmView,
                                coordinator: ()) {
        view.stop()
    }
}

final class SkelliFilmView: UIView {
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var current: String?

    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var filmLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    func play(_ name: String) {
        guard name != current else { return }
        current = name
        stop()
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "mp4")
        else { return }
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        next.isMuted = true
        next.actionAtItemEnd = .none
        endObserver = NotificationCenter.default
            .addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item, queue: .main) { [weak next] _ in
                next?.seek(to: .zero)
                next?.play()
            }
        filmLayer.videoGravity = .resizeAspectFill
        filmLayer.player = next
        player = next
        next.play()
    }

    func stop() {
        player?.pause()
        if let endObserver = endObserver {
            NotificationCenter.default
                .removeObserver(endObserver)
            self.endObserver = nil
        }
        player = nil
    }

    deinit { stop() }
}

// MARK: - Her tab

struct SkelliView: View {
    @ObservedObject private var skelli = SkelliCenter.shared
    @ObservedObject private var themes = ThemeCenter.shared
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var post: ListeningPost
    @State private var input = ""
    @State private var showDirectory = false
    @State private var showMemory = false
    @State private var showWeights = false
    @State private var confirmClear = false
    @State private var confirmReset = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            screen
        }
        .onAppear { SkelliMind.warm() }
        .sheet(isPresented: $showDirectory) {
            SkelliDirectoryView()
        }
        .sheet(isPresented: $showMemory) {
            SkelliMemoryView()
        }
        .sheet(isPresented: $showWeights) {
            WeightsView()
        }
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $confirmClear,
            titleVisibility: .visible) {
            Button("Clear conversation",
                   role: .destructive) {
                skelli.clearConversation()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The transcript goes. What she "
                 + "remembers stays — forgetting that "
                 + "is its own act, under Reset.")
        }
        .confirmationDialog(
            "Reset to defaults?",
            isPresented: $confirmReset,
            titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                skelli.resetToDefaults()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Conversation and everything she "
                 + "has been told, forgotten. The "
                 + "house itself — its records, its "
                 + "organs — is untouched.")
        }
    }

    private var screen: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                transcript
                inputBar
            }
            pinnedHeader
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottomLeading) {
            SkelliWebHost()
                .frame(width: 2, height: 2)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Her pinned presence — the film, her name, and
    /// what she is doing — fixed at the top while the
    /// conversation scrolls beneath it, over a blur
    /// that fades away at its lower edge.
    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            header
            activityBar
            intelStrip
        }
        .padding(.top, 50)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Rectangle()
                    .fill(LinearGradient(
                        colors: [
                            themes.current.tint
                                .opacity(0.5),
                            themes.current.tint
                                .opacity(0.22),
                            themes.current.tint
                                .opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                Rectangle()
                    .fill(RadialGradient(
                        colors: [themes.current.accent
                                     .opacity(0.16),
                                 .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 260))
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black,
                              location: 0),
                        .init(color: .black,
                              location: 0.82),
                        .init(color: .clear,
                              location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom))
        }
    }

    /// Her options, living inside her own bar.
    private var menuButton: some View {
        Menu {
            Button {
                showDirectory = true
            } label: {
                Label("Directory of the house",
                      systemImage: "book")
            }
            Button {
                showMemory = true
            } label: {
                Label("Memory",
                      systemImage: "brain")
            }
            Button {
                showWeights = true
            } label: {
                Label("Weights",
                      systemImage: "memorychip")
            }
            Toggle(isOn: $skelli.webResearchEnabled) {
                Label("Web research",
                      systemImage: "globe")
            }
            if SkelliMind.weightsReady {
                Toggle(isOn: Binding(
                    get: {
                        UserDefaults.standard.bool(
                            forKey: "skelli.preferWeights")
                    },
                    set: {
                        UserDefaults.standard.set(
                            $0,
                            forKey: "skelli.preferWeights")
                    })) {
                    Label("Prefer the weights mind",
                          systemImage: "scalemass")
                }
            }
            Divider()
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("Clear conversation",
                      systemImage: "trash")
            }
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Reset to defaults",
                      systemImage:
                        "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(themes.current.accent)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle().stroke(
                        themes.current.accent
                            .opacity(0.4),
                        lineWidth: 1))
        }
    }

    private var activityBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(skelli.mood == .idle
                      ? Color.secondary
                      : themes.current.accent)
                .frame(width: 7, height: 7)
            Text(skelli.activity)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [themes.current.accent
                                     .opacity(0.36),
                                 .clear],
                        center: .center,
                        startRadius: 4, endRadius: 46))
                    .frame(width: 92, height: 92)
                SkelliLiveView(mood: skelli.mood,
                               size: 64)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(
                            themes.current.accent
                                .opacity(0.55),
                            lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Skelli")
                    .font(.title3.weight(.semibold))
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            menuButton
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: her vital signs

    /// The bar earns its height: the house's live
    /// state in one strip — EMCON posture, the
    /// wire, the Serve door, the ear, which mind
    /// is awake, the night's log — each a door to
    /// the organ it reports.
    private var intelStrip: some View {
        ScrollView(.horizontal,
                   showsIndicators: false) {
            HStack(spacing: 8) {
                chip(icon: "eye.slash.fill",
                     label: "EMCON",
                     value: emconChip,
                     hot: emcon.active) { go(7) }
                chip(icon: "network",
                     label: "WIRE",
                     value: "\(NeighborhoodStore.shared.neighbors.count)",
                     hot: false) { go(0) }
                chip(icon: "antenna.radiowaves.left.and.right",
                     label: "SERVE",
                     value: serveChip,
                     hot: mouth.serveRunning) { go(2) }
                chip(icon: "ear.fill",
                     label: "EAR",
                     value: post.session != nil
                         ? "\(post.deviceCount)" : "off",
                     hot: post.session != nil) { go(0) }
                chip(icon: "brain",
                     label: "MIND",
                     value: mindChip,
                     hot: SkelliMind.isAvailable
                         || SkelliMind.weightsReady) {
                    showWeights = true
                }
                chip(icon: "book.fill",
                     label: "LOG",
                     value: "\(logCount)",
                     hot: false) { go(5) }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private func chip(icon: String, label: String,
                      value: String, hot: Bool,
                      action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10,
                                  weight: .semibold))
                Text(value)
                    .font(.system(size: 12,
                                  weight: .semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 9,
                                  weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(hot
                ? themes.current.accent
                : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(hot
                    ? themes.current.accent
                        .opacity(0.16)
                    : Color.white.opacity(0.06)))
            .overlay(
                Capsule().stroke(hot
                    ? themes.current.accent
                        .opacity(0.45)
                    : Color.white.opacity(0.10),
                    lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private func go(_ tab: Int) {
        NotificationCenter.default.post(
            name: .houseNavigate, object: nil,
            userInfo: ["tab": tab])
    }

    private var emconChip: String {
        var value = emcon.active ? "GHOST" : "OPEN"
        if !emcon.exposures.isEmpty {
            value += " ·\(emcon.exposures.count)"
        }
        return value
    }

    private var serveChip: String {
        var value = mouth.serveRunning ? "OPEN" : "SHUT"
        if !mouth.inbox.isEmpty {
            value += " ·\(mouth.inbox.count)"
        }
        return value
    }

    private var mindChip: String {
        if SkelliMind.weightsReady {
            return "WEIGHTS"
        }
        return SkelliMind.isAvailable ? "APPLE" : "—"
    }

    private var logCount: Int {
        let since = Date()
            .addingTimeInterval(-12 * 3600)
        return Journal.events(limit: 300)
            .filter { $0.when > since }.count
    }

    private var statusLine: String {
        let wire = NeighborhoodStore.shared
            .neighbors.count
        return "\(wire) on the wire"
            + (skelli.webResearchEnabled
               ? " · web on" : " · web off")
            + (SkelliMind.isAvailable
               ? " · model on" : "")
            + (SkelliMind.weightsReady
               ? " · weights on" : "")
            + (skelli.notes.isEmpty
               ? ""
               : " · remembers \(skelli.notes.count)")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if skelli.lines.isEmpty {
                        Text("Ask about the house, or "
                            + "give an order.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity,
                                   alignment: .center)
                    }
                    ForEach(skelli.lines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            if line.fromOperator {
                                Spacer(minLength: 48)
                            }
                            VStack(alignment: line.fromOperator
                                       ? .trailing
                                       : .leading,
                                   spacing: 3) {
                                Text(line.text)
                                    .font(.callout)
                                    .foregroundStyle(
                                        line.fromOperator
                                            ? .white
                                            : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(
                                        line.fromOperator
                                            ? themes.current
                                                .accent
                                            : Color.secondary
                                                .opacity(0.16),
                                        in: RoundedRectangle(
                                            cornerRadius: 16))
                                Text(line.when.formatted(
                                    date: .omitted,
                                    time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                            }
                            if !line.fromOperator {
                                Spacer(minLength: 48)
                            }
                        }
                        .id(line.id)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .padding(.top, 188)
            }
            .onChange(of: skelli.lines.count) { _ in
                scrollToEnd(proxy)
            }
            .onChange(of: skelli.mood) { _ in
                scrollToEnd(proxy)
            }
            .onAppear { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let last = skelli.lines.last {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask, or give an order…",
                      text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit(send)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(themes.current.accent,
                                in: Circle())
            }
            .disabled(input.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func send() {
        let text = input
        input = ""
        inputFocused = false
        skelli.ask(text)
    }
}

// MARK: - The directory, as a sheet

struct SkelliDirectoryView: View {
    @ObservedObject private var skelli = SkelliCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SkelliKnowledge.entries) { entry in
                Button {
                    dismiss()
                    skelli.askAbout(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(entry.home)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("The house, indexed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Her memory, as a sheet

struct SkelliMemoryView: View {
    @ObservedObject private var skelli = SkelliCenter.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if skelli.notes.isEmpty {
                    Text("Nothing yet. Tell her "
                         + "'remember …' in conversation "
                         + "and it will be kept here — "
                         + "and only here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(skelli.notes) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.text).font(.callout)
                        Text("kept " + note.learnedAt
                            .formatted(date: .abbreviated,
                                       time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    skelli.forgetNotes(at: offsets)
                }
            }
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
