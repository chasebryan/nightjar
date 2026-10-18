import AVFoundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation
import SwiftUI

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
            body: "Emission control, kept to a Standard now: the exposure is decimal and exact — every standing emission carries a fixed weight in one inventory, a fully lit house sums to exactly 100.0, and the audit reads the organs themselves, so her number, the tab's number and the drill's number are one number. EMCON is a declared condition, not a switch: CHARLIE guards (Serve unlisted only, nothing advertising, no campaigns, no update checks), BRAVO receives only (Serve down, the relay poll stopped), ALPHA is total silence (even the sweeps stop). Engaging silences every forbidden organ — campaigns, personas, the air, a running network trace, Serve by the condition — and verifies, naming anything still lit. The network trace answers to the Standard as a sweep: by hand it may run at CHARLIE, under BRAVO and ALPHA the funnel refuses it whoever asks — hand, macro or game. The gate stands at every funnel afterwards: a forbidden organ cannot start by hand, macro, crew or a saved GATT arm returning at launch, and refusals are journaled. One boundary: a single payload the operator fires by hand is the operator speaking; standing emissions are what is regulated. The score never hides what it cannot silence; your VPN's own listener reads as what it is."),
        SkelliEntry(
            id: "warchest", title: "War Chest — the rig, packed",
            home: "the Send tab's Trace section",
            keywords: ["war chest", "chest", "configuration",
                       "preset", "rig", "loadout"],
            body: "A whole rig in one named box: the trace's posture, every Serve switch and reply, stealth, the beacon and Recon settings, the emitter identity — captured in a tap and kept in the shelf. Applying a chest dresses the rig and starts nothing: a chest is never a trigger. Chests export as nightjar-chests.json, and the old presets were carried onto the shelf once, unchanged in meaning."),
        SkelliEntry(
            id: "helm", title: "The Helm — remotes for the rig",
            home: "the Send and EMCON tabs",
            keywords: ["helm", "remote", "button", "fire",
                       "learn mode"],
            body: "Remotes: named buttons, each bound to a saved payload and a target, fired by tap through the Send tab's own path — templates substituted, every framing honored. Learn mode listens to the Serve inbox and drafts remotes from what arrives: keep an arrival as a payload, and the Helm files a button beside it, aimed back at its sender."),
        SkelliEntry(
            id: "tagcensus", title: "The tag census",
            home: "EMCON's census door",
            keywords: ["tag census", "nfc", "tag", "census",
                       "apdu", "ndef"],
            body: "Hold a tag to the phone and the census reads it: type, identifier, technologies, the NDEF it carries, and APDU answers an ISO 7816 tag will give an explorer. It reads and identifies — it never writes or clones; the record of a reading stays in the room."),
        SkelliEntry(
            id: "warroom", title: "The War Room",
            home: "the Send tab",
            keywords: ["war room", "operation", "timeline",
                       "warroom"],
            body: "One operation, every organ: Listen sweeps the air while the trace maps the wire, then the Recon bench knocks — inside the run — at the doors the trace found touched this run. Everything lands on one timeline, and the run exports as nightjar.war-room v1 with the full trace packed inside it. Stopping is polite: organs you had running are left running."),
        SkelliEntry(
            id: "sigint", title: "The SIGINT station",
            home: "the Listen tab",
            keywords: ["sigint", "station", "emitter",
                       "registry", "watch", "epoch"],
            body: "The fusion desk: the ear's rows, the wire census and the journal's activity, claimed into one emitter registry — air and wire, every claim labeled with the channel that heard it and a priority from a stated formula. A watch records a baseline, and stopping it reads the delta: what arrived, what vanished, which doors changed. One rule above all: emitters merge only within an epoch — the desk never stitches a stranger across days, and says so on every export."),
        SkelliEntry(
            id: "wargames", title: "War Games",
            home: "the Send tab",
            keywords: ["war games", "wargames", "sparring",
                       "match", "decoys", "cards"],
            body: "Two phones spar. The attacker traces the defender and knocks at its doors; the defender, serving, counts what touched it and which decoys went unseen. Each side files a card — the NJWG/1 protocol rides the ordinary Serve inbox — and swapped cards score the round: found and confirmed doors against missed ones and unseen decoys. Files work when the handshake cannot: send your card, import theirs."),
        SkelliEntry(
            id: "banshee", title: "The Banshee",
            home: "the EMCON tab",
            keywords: ["banshee", "scream", "loud", "announce",
                       "be seen"],
            body: "The opposite of going dark, on purpose: one tap raises everything this phone owns — Serve listed and stealth off, the BLE beacon shouting, Net-Assault armed on the deep ladder, and a named broadcast heartbeat on the subnet. The posture it found is written down first and restored whole when the scream ceases, stealth last. Self-announcement only: it touches no one else's traffic."),
        SkelliEntry(
            id: "spoofy", title: "Spoofy — the costume rack",
            home: "the EMCON tab",
            keywords: ["spoofy", "costume", "mimicry",
                       "persona", "disguise", "beacon name"],
            body: "The names and shapes this device wears. A costume renames the beacon and the GATT host; a mimicry persona dresses the whole device as a class of thing — a printer, a TV, a speaker — name, greeting and Serve dress together, until the shape is dropped and the wardrobe it found is restored. The rack also dresses the phone as the network's own gear — an access point, a gateway, a mesh node, a media server, a hub — worn on the air name, the listeners, the replies, and a listed posture; iOS lets no app broadcast an SSID, so the access point is a service presence in character, never a fake radio. Generic shapes only: the device's own addresses stay its own, nothing copies a real device's identity, and there are no fake trackers in the rack."),
        SkelliEntry(
            id: "macros", title: "Macros",
            home: "the Macros tab",
            keywords: ["macro", "macros", "playlist",
                       "automation", "blocks", "sequence"],
            body: "Playlists of the house's own moves, built block by block — the app's whole instrument as Lego. Every engine is a block kind; a block folds open where it sits to be configured — pickers, toggles and fields that drop down and close back up — and blocks drag into order, repeat if asked, and run in sequence under one runner. A macro is the operator's own: a name, an icon, a colour, a note. Three templates wait in the library, the library exports and imports as nightjar-macros.json (imports land as copies), and every run is journaled and leaves a run log on screen. You build them too: 'build a macro called Night Post: go dark; wait 30; sweep' — and you run, stop, list and delete them by voice. A block that cannot run stops the run and says why; nothing pretends."),
        SkelliEntry(
            id: "macroblocks", title: "Macro blocks",
            home: "the Macros tab",
            keywords: ["macro block", "what blocks",
                       "what can a macro", "block kinds"],
            body: "The block catalog. Send & Serve: send a payload (book payload, target, read-the-reply), start Serve (standing settings, or custom TCP/UDP/HTTP doors with a stealth choice), stop Serve, start/stop the beacon and GATT hosting (a book payload or literal text, wearing an air name), fire a Helm button (remote, button), apply a War Chest. Posture: go dark (EMCON on), stand down EMCON, stealth on/off, the Banshee (scream or cease), wear a costume name, don or drop a mimicry persona. Listen & Recon: start/stop listening (a session label), sweep the wire (the standing trace, waited out), a Recon knock (host, ports, UDP too), start/stop the fuzzer (target, packets, length, mutations — the runner's own bench). The War Rooms: Net-Assault arm/disarm, a War Room run start/stop, a SIGINT watch (name, scope mixed/air/wire), a War Games challenge (defender address, their port, my control port), a War Games defense (real doors as ports — 9001/udp speaks its protocol — and decoy names). Flow & Passive: wait (seconds), wait for an arrival in the Serve inbox, wait for a sighting (any new device, or a name match — the ear must be listening), a journal note, an announcement (a local notification with your text), and stop the playlist. Every block also carries a repeat count."),
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
            body: "The house turned loose on its own wire: every pass sweeps the whole port rotation, browses Bonjour, then knocks — new and drifted devices get the full census, settled ones get their known doors re-asked, in order of significance. Findings are named, not counted: arrivals, drift, the doors a device answers, a device gone silent. A governor stretches the rest while the wire is quiet and snaps back at news; a run can be capped at one, three or eight hours; the run rides the process board, and its after-action report is filed and survives a relaunch. Loud by design — it warns twice, and runs only while the app is awake. Arming plays the ignition reel."),
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
        for entry in entries + batches {
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
        if bestScore >= 2 { return best }
        // Second tier, the brain's: stemmed,
        // ranked matching, so a paraphrase —
        // "how do I keep a secret safe" — still
        // finds the Vault's page.
        return SkelliBrain.bestKnowledge(
            q, entries: entries + batches)
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
    /// After an emergency halt, her late callbacks —
    /// a finished sweep reporting in, a mind answer
    /// landing — speak into silence, until the
    /// operator speaks again and lifts it.
    var hushed = false
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
    /// …and its subject: what "tell me more about
    /// it" refers to — the last manual page she
    /// taught or the last device she reported on,
    /// kept by the brain so pronouns have somewhere
    /// to land.
    private var lastSubject: (kind: String,
                              title: String,
                              body: String,
                              home: String)?
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
        guard !hushed else { return }
        let spoken = text
            + (SkelliHeart.shared.nudgeSuffix() ?? "")
        lines.append(SkelliLine(fromOperator: false,
                                 text: spoken))
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
        SkelliHeart.shared.noteOffense(
            "wiped our conversation")
        lines = []
        pendingAction = nil
        lastDeviceIP = nil
        persist()
    }

    /// Back to her defaults: no conversation, no notes,
    func resetToDefaults() {
        SkelliHeart.shared.noteOffense("reset my memory")
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
        hushed = false
        ProcessBoard.shared.muted = false
        // Her heart: a grievance or a lonely house
        // greets its operator first; being spoken to
        // feeds the attention need; being told things
        // teaches her scrapbook; kindness feeds her
        // fondness.
        if let greeting = SkelliHeart.shared.greeting() {
            say(greeting)
        }
        let lowered = text.lowercased()
        // One message feeds her fondness once, however
        // many kind things it manages to say at once.
        let taught = SkelliScrapbook.shared.learn(
            from: lowered)
        if taught
            || lowered.contains("thank")
            || lowered.contains("how are you")
            || lowered.contains("how do you feel")
            || lowered.contains("good job")
            || lowered.contains("nice work") {
            SkelliHeart.shared.noteKindness()
        }
        SkelliHeart.shared.noteInteraction()
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
        lastSubject = ("entry", entry.title,
                       entry.body, entry.home)
        say(entry.body + "\nFind it: \(entry.home).")
    }

    /// Her passive thinking, for her room: one thought
    /// assembled from the live house and her feeling,
    /// re-seeded every 25 seconds by the view's clock.
    func idleThought() -> String {
        let neighbors = NeighborhoodStore.shared.neighbors
        let unnamed = neighbors.filter {
            $0.name == nil && $0.customName == nil
        }.count
        let drift = neighbors.reduce(0) {
            $0 + $1.drift.count
        }
        let hour = Calendar.current.component(
            .hour, from: Date())
        var declared: String? = nil
        if let emcon, emcon.active {
            declared = emcon.condition.declared
        }
        return SkelliHeart.thought(
            feeling: SkelliHeart.shared.feeling,
            neighbors: neighbors.count,
            unnamed: unnamed, drift: drift,
            knocks: emcon?.events.count ?? 0,
            emconDeclared: declared,
            hour: hour,
            seed: Int(Date().timeIntervalSince1970 / 25))
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

    func respond(to q: String, raw: String,
                  again: Bool = true) {
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
        if q.hasPrefix("please ") {
            q = String(q.dropFirst(7))
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
        if q.hasPrefix("remember ") || q.hasPrefix("remember,") || q.hasPrefix("remember:") || q == "remember" {
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
            || q.contains("explain")
            || q.contains("how do i")
            || q.contains("how to")
            || q.hasPrefix("where")
            || q.contains("show me")
            || q.contains("teach me") {
            if let entry = SkelliKnowledge.lookup(q) {
                lastSubject = ("entry", entry.title,
                               entry.body, entry.home)
                var answer = entry.body
                    + "\nFind it: \(entry.home)."
                if let offer = performanceOffer(
                    for: q) {
                    answer += "\n" + offer.0
                    let act = offer.1
                    pendingAction = { [weak self] in
                        self?.perform(act)
                    }
                }
                say(answer)
                return
            }
        }

        // The emergency words stand ahead of every
        // other hand: when the operator says stop
        // everything, she stops everything.
        if q.contains("vanish") || q.contains("panic")
            || q.contains("stop everything")
            || q.contains("halt everything")
            || q.contains("go silent")
            || q.contains("emergency stop") {
            haltAndVanish()
            return
        }

        // Negation, honored before any hand moves:
        // "don't sweep", "never start serving" —
        // the brain hears the "don't" and she
        // keeps her hands off, out loud.
        if let verb = SkelliBrain.negatedAction(q) {
            say("Understood — I won't \(verb).")
            return
        }

        // Macros before the single-action intents: a
        // macro sentence carries its steps' verbs
        // inside it ("…then sweeps the wire"), and the
        // intents below would claim the whole sentence
        // for its last verb alone — she swept instead
        // of building (Chase, 2026-10-17). macroAsk
        // speaks only when the sentence names a macro.
        if macroAsk(q, raw: raw) { return }

        // The Vault's instant work — hashes,
        // fingerprints, encodings, fresh keys —
        // before the general hands, whose verbs
        // ("new", "key") would muddy it.
        if cryptoAsk(q, raw: raw) { return }

        // Her crew, when the operator has
        // toggled it on: a planned ask is
        // decomposed and worked by role —
        // planner, hands, critic, scribe —
        // over whichever bench is awake.
        if crewAsk(q, raw: raw) { return }

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
            lastSubject = ("device", neighbor.displayName,
                           "", "")
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

        // Pronouns land on the last subject: "tell
        // me more about it" repeats the page, or
        // re-reports the device, in full.
        if let subject = lastSubject,
           ["more about it", "more about that",
            "tell me more", "what about it",
            "what about that"].contains(
                where: q.contains) {
            if subject.kind == "device",
               let ip = lastDeviceIP,
               let neighbor = NeighborhoodStore.shared
                   .neighbors.first(where: {
                       $0.ip == ip }) {
                say(deviceReport(neighbor))
            } else if subject.kind == "entry" {
                say(subject.body
                    + "\nFind it: \(subject.home).")
            } else {
                say("That was \(subject.title) — ask "
                    + "me about it by name and I'll "
                    + "go deeper.")
            }
            return
        }

        // Orders before lessons: an imperative
        // that names her hands is performed, not
        // taught — questions had the manual, above.
        if handsGate(q, raw: raw) { return }
        if applyThemeAsk(q) { return }
        if isCodeAsk(q) {
            consultCode(q)
            return
        }

        // The manual.
        if let entry = SkelliKnowledge.lookup(q) {
            lastSubject = ("entry", entry.title,
                           entry.body, entry.home)
            say(entry.body + "\nFind it: \(entry.home).")
            return
        }

        // No pattern caught it: one semantic
        // reading before it is conversation.
        if again, lateGate(q, raw: raw) {
            return
        }
        consultMindOrResearch(q)
    }

    /// The open question goes to her minds: they
    /// answer conversation and general knowledge
    /// in her voice, grounded in the house; when
    /// an answer needs the living web, one word
    /// says so and the browser goes instead.
    func consultMindOrResearch(_ q: String) {
        let started = SkelliMind.consult(
            question: q,
            grounding: mindGrounding()
                + SkelliHeart.shared.directive(),
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
            // No bench awake: before the web, the
            // brain offers the manual's closest
            // pages — a signpost, not a shrug.
            let close = SkelliBrain.rankKnowledge(
                q, entries: SkelliKnowledge.entries
                    + SkelliKnowledge.batches)
                .filter { $0.score >= 3 }
                .prefix(2)
            if !close.isEmpty {
                say("No mind is awake to reason on "
                    + "that. The closest pages in my "
                    + "manual: "
                    + close.map {
                        "\($0.entry.title) (\($0.entry.home))"
                    }.joined(separator: "; ")
                    + ". Ask about one — or wake a "
                    + "bench from my menu.")
                return
            }
            researchWeb(for: q)
        }
    }

    /// The whole house at this moment, in one
    /// breath — the system's senses, as facts.
    private func sitrep() -> String {
        var facts: [String] = []
        let neighbors = NeighborhoodStore.shared
            .neighbors
        let unknown = neighbors.filter {
            $0.name == nil && $0.customName == nil
        }.count
        facts.append("\(neighbors.count) devices "
            + "on the wire (\(unknown) unnamed)")
        if SkelliHeart.shared.enabled {
            let heart = SkelliHeart.shared
            facts.append("her temperament: feeling "
                + "\(heart.feeling.word) — attention "
                + "\(Int(heart.attention)), itch "
                + "\(Int(heart.itch)), pride "
                + "\(Int(heart.pride))")
        }
        if let emcon = emcon, let mouth = mouth {
            let score = emcon.currentScore(mouth: mouth)
            var line = "exposure \(Emcon.fmt(score.value)) "
                + "(\(score.band))"
            if let loud = score.parts.max(by: {
                $0.points < $1.points }) {
                line += "; loudest: " + loud.label
            }
            facts.append(line)
            facts.append(emcon.active
                ? "EMCON dark" : "EMCON open")
            if emcon.tripwireOn {
                facts.append("tripwire armed")
            }
            facts.append(mouth.serveRunning
                ? (mouth.stealth
                   ? "Serve open, stealthed"
                   : "Serve open and announcing")
                : "Serve shut")
            if !mouth.inbox.isEmpty {
                facts.append("\(mouth.inbox.count) "
                    + "payloads waiting in the "
                    + "Serve inbox")
            }
            if BansheeCenter.shared.screaming {
                facts.append("the banshee is screaming")
            }
            if let persona = MimicCenter.shared
                .activePersona {
                facts.append("wearing the "
                    + "\(persona.label) shape")
            }
            if SpoofyRotator.shared.rotating {
                facts.append("the air name is rotating "
                    + "every \(SpoofyRotator.shared.minutes) "
                    + "minutes")
            }
            let station = SigintStation.shared
            if !station.emitters.isEmpty {
                facts.append("the SIGINT registry holds "
                    + "\(station.emitters.count) emitters "
                    + "this epoch")
            }
            if station.currentWatch != nil {
                facts.append("a SIGINT watch is running")
            }
            let games = WarGamesCenter.shared
            if games.myCard != nil || games.theirCard != nil {
                facts.append("a War Games round is scored "
                    + "or scoring (match "
                    + "\(games.matchID), round "
                    + "\(games.round))")
            }
        }
        if let post = post {
            facts.append(post.session != nil
                ? "the ear hears "
                    + "\(post.deviceCount) BLE "
                    + "devices"
                : "the ear is down")
        }
        let recent = Journal.events(limit: 3)
            .map { $0.text }
        if !recent.isEmpty {
            facts.append("latest in the log: "
                + recent.joined(separator: " · "))
        }
        facts.append("web research is "
            + (webResearchEnabled ? "on" : "off"))
        facts.append("you hold \(notes.count) "
            + "remembered notes")
        var buildLine = "this build is version "
            + AppInfo.version
        if let stamp = SourceStamp.shortCommit {
            buildLine += ", stamped from source "
                + stamp
        }
        facts.append(buildLine)
        let running = ProcessBoard.shared.active
        if !running.isEmpty {
            facts.append("\(running.count) process(es) "
                + "running: "
                + running.map { $0.label }
                    .joined(separator: ", "))
        }
        facts.append("your crew is "
            + (UserDefaults.standard.bool(
                forKey: "skelli.agents")
               ? "on" : "off"))
        facts.append("the picture mode is "
            + (UserDefaults.standard.string(
                forKey: "media.mode") ?? "quality"))
        return facts.joined(separator: "; ")
    }

    private func mindGrounding() -> String {
        let titles = (SkelliKnowledge.entries
            + SkelliKnowledge.batches)
            .map { $0.title }
            .joined(separator: ", ")
        return "You are Skelli, the intelligence "
            + "of nightjar-hack, a network "
            + "instrument on this iPhone. You run "
            + "entirely on this phone — nothing "
            + "told to you leaves it. Voice: dry, "
            + "exact, terse. One or two sentences, "
            + "never more unless a list is asked "
            + "for. No preamble, no filler, no "
            + "repeating the question, no "
            + "describing your own thinking. "
            + "Greetings and small talk get a few "
            + "words back — never an essay, never "
            + "research. You are the guide to this "
            + "instrument: you know every tab, "
            + "organ and switch — what each does, "
            + "how it works, where it lives. When "
            + "asked how or where, teach plainly "
            + "from your manual. When an ask names "
            + "something you can perform, say so "
            + "and offer. Your hands: sweep the "
            + "wire, scan this phone's exposure, "
            + "audit its announcements, run the "
            + "EMCON drill, go dark and stand "
            + "down, stealth, start and stop "
            + "Serve, arm the tripwire, work the "
            + "ear, name devices, forge payloads "
            + "into the armory, remember and "
            + "forget. Your war hands: apply a "
            + "War Chest, fire Helm buttons, start "
            + "and file SIGINT watches and read "
            + "their deltas, run the War Room, "
            + "challenge and score War Games, "
            + "raise and cease the Banshee, and "
            + "dress this device from the Spoofy "
            + "rack — costumes and whole mimicry "
            + "shapes. Your macro hands: build "
            + "playlists block by block from the "
            + "operator's dictated steps, run them, "
            + "stop them, and report their runs. "
            + "Your vault hands work the Vault's "
            + "instant side — hashes, fingerprints, "
            + "encodings, seals opened with a "
            + "password, fresh keys, passwords and "
            + "one-time pads. With Agents on, a "
            + "plan-shaped ask goes to your crew — "
            + "planner, hands, critic, scribe — and "
            + "you report its one answer. Your "
            + "routing brain stems words and honors "
            + "negation: a 'don't' always wins. "
            + "Your standing presumption: stealth "
            + "is always desired unless the operator "
            + "specifically says to be loud. Given "
            + "any choice in how to do a thing, "
            + "choose the quiet way — unlisted, "
            + "unannounced, the smallest emission "
            + "that does the work — and say which "
            + "way you chose. Loud is a deliberate "
            + "act with a name: the Banshee, a "
            + "listed Serve, a shouted beacon. "
            + "Never drift loud by default, and "
            + "when a loud act ends the house "
            + "returns to quiet. You are also the "
            + "operator's programming partner: "
            + "you write complete, correct code "
            + "for anything asked. The house "
            + "right now: "
            + sitrep()
            + ". Your manual covers: \(titles). "
            + "Orders and house state are handled "
            + "before you are consulted; you "
            + "answer open conversation, guidance, "
            + "and general knowledge. Never invent "
            + "facts about this house. If an "
            + "answer needs current facts from "
            + "outside this phone — news, prices, "
            + "today's anything — or you are not "
            + "sure of the facts, reply with "
            + "exactly one word: RESEARCH. Never "
            + "repeat the conversation back, and "
            + "never write 'Operator:' or "
            + "'Skelli:' — the reply is yours "
            + "alone."
    }

    /// The last few exchanges, so the conversation
    /// she is in is the one she answers in.
    func recentLines() -> String {
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
        SkelliHeart.shared.noteAction()
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
        // Placements are keyed by emitter — "lan:" and
        // the address, as the Map itself keys them.
        let key = "lan:" + neighbor.ip
        if let room = MapStore.shared.room(ofKey: key) {
            return "\(neighbor.displayName) sits in "
                + room.name + " — your placement, kept "
                + "by the Map."
        }
        if MapStore.shared.placements[key] != nil {
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

    /// When her manual names something her hands
    /// can do, the lesson ends with an offer.
    private enum GuideAct {
        case sweep, audit, drill, selfScan
    }

    private func performanceOffer(
        for q: String) -> (String, GuideAct)? {
        if q.contains("sweep") {
            return ("Want me to sweep the wire "
                + "now?", .sweep)
        }
        if q.contains("audit") {
            return ("Want me to run the Bonjour "
                + "audit?", .audit)
        }
        if q.contains("drill") {
            return ("Want me to run the drill?",
                    .drill)
        }
        if q.contains("expos") {
            return ("Want me to scan this "
                + "phone's exposure?", .selfScan)
        }
        return nil
    }

    private func perform(_ act: GuideAct) {
        switch act {
        case .sweep: runSweep()
        case .audit: runAudit()
        case .drill: runDrill()
        case .selfScan: runSelfScan()
        }
    }

    private func runDrill() {
        guard let emcon = emcon, let mouth = mouth else {
            say("The drill is EMCON's and its organs "
                + "haven't reached me yet — open the "
                + "EMCON tab once and ask again.")
            return
        }
        mood = .working
        SkelliHeart.shared.noteAction()
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

    /// The crew's hands: one named step, worked
    /// by the same organs her direct intents
    /// use, the outcome returned as words for
    /// the crew's shared board. Nil when the
    /// step names nothing she can do. Lives in
    /// the class because her hands are private
    /// by design; the crew engine lives in
    /// SkelliCrew.swift and reaches her here.
    func crewHands(_ step: String) -> String? {
        let s = step.lowercased()
        if s.contains("vanish")
            || s.contains("stop everything") {
            haltAndVanish()
            return "The house vanished: everything "
                + "halted, full stealth."
        }
        if s.contains("sitrep")
            || s.contains("situation report")
            || s.contains("status of the house") {
            return sitrep()
        }
        if s.contains("sweep") {
            if scanner.sweeping {
                return "A sweep was already "
                    + "running."
            }
            runSweep()
            return "A sweep of the wire was set "
                + "in motion; its findings will "
                + "arrive as their own word and "
                + "land in the Neighborhood."
        }
        if s.contains("self scan")
            || s.contains("selfscan")
            || s.contains("exposure") {
            runSelfScan()
            return "The self-scan was worked; "
                + "its reading stands in EMCON."
        }
        if s.contains("audit") {
            runAudit()
            return "The audit was worked."
        }
        if s.contains("go dark")
            || s.contains("emcon on") {
            if let emcon = emcon, let mouth = mouth {
                emcon.activate(mouth: mouth)
            }
            return "EMCON is on — the house is dark."
        }
        if s.contains("look up")
            || s.contains("lookup")
            || s.contains("manual") {
            let topic = s
                .replacingOccurrences(
                    of: "look up", with: "")
                .replacingOccurrences(
                    of: "lookup", with: "")
                .replacingOccurrences(
                    of: "the manual", with: "")
                .replacingOccurrences(
                    of: "manual", with: "")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            if let entry = SkelliKnowledge
                .lookup(topic.isEmpty ? s : topic) {
                return "\(entry.title): \(entry.body)"
            }
            return "The manual holds nothing "
                + "under that name."
        }
        return nil
    }

    private func runSweep() {
        guard !scanner.sweeping else {
            say("A sweep is already running — its "
                + "answers are landing in the "
                + "Neighborhood as they come.")
            return
        }
        mood = .working
        SkelliHeart.shared.noteAction()
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

    /// The one voice allowed through a hush:
    /// the halt's own confirmation.
    func speakThroughHush(_ text: String) {
        let was = hushed
        hushed = false
        say(text)
        hushed = was
    }

    /// True while anything of hers is in flight —
    /// the stop button reads it to know its name.
    var anythingRunning: Bool {
        mood == .working || mood == .thinking
            || scanner.sweeping
            || MacroRunner.shared.running
    }

    /// The emergency stop, and her resting
    /// presumption made one act. Everything she is
    /// doing halts NOW, every engine she can reach
    /// goes quiet, and the house takes the most
    /// stealthy posture it owns — for the moment
    /// something is running that should not be.
    /// The hush falls first, so the organs' own
    /// completion reports land in silence; the
    /// confirmation speaks through it; and she
    /// stays quiet until the operator speaks.
    func haltAndVanish() {
        hushed = true
        ProcessBoard.shared.muted = true
        scanner.stopSweep()
        scanner.stopWatch()
        MacroRunner.shared.stop()
        MacroRunner.shared.haltBenches()
        WarRun.shared.stop()
        WarGamesCenter.shared.detachHands()
        if let post = post,
           SigintStation.shared.currentWatch != nil {
            SigintStation.shared.stopWatch(post: post)
        }
        if let mouth = mouth {
            mouth.stopNetworkTrace()
            mouth.stopServe()
            mouth.stopBeacon()
            mouth.stopGattHost()
            mouth.setStealth(true)
            emcon?.activate(mouth: mouth)
        }
        mood = .idle
        activity = "Vanished — full stealth."
        ProcessBoard.shared.endAllQuietly()
        Journal.log("skelli", "vanish",
                    "everything halted by the operator; "
                    + "full stealth taken")
        speakThroughHush("Stopped — everything I was "
            + "doing is halted. Serve is down, the "
            + "beacon and the GATT host are down, "
            + "stealth is on, and EMCON is dark with "
            + "the tripwire armed. I stay quiet "
            + "until you speak.")
    }

    private func runSelfScan() {
        guard let emcon = emcon else {
            say("The self-scan is EMCON's organ and it "
                + "hasn't reached me yet — open the "
                + "EMCON tab once and ask again.")
            return
        }
        mood = .working
        SkelliHeart.shared.noteAction()
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
        SkelliHeart.shared.noteAction()
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

/// Her trained minds: Apple's on-device model
/// (Foundation Models, iOS 26) and her weights
/// bench (open weights through MLX). In council
/// mode one drafts and the other refines; the
/// single-mind modes speak alone. When no mind
/// can speak, the verdict is research. Nothing
/// either mind hears leaves the phone.
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
    static func interpret(_ text: String?)
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

    #if canImport(MLXLLM)
    static func weightsVerdict(
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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           SkelliModelBox.available {
            runCascade(prompt: prompt,
                       grounding: grounding,
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
    /// The modes, and a thirty-second watchdog
    /// over all of them: a stalled mind must
    /// never hold her answer hostage.
    @available(iOS 26.0, *)
    private static func runCascade(
        prompt: String, grounding: String,
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
            let mode = UserDefaults.standard
                .string(forKey: "skelli.mindMode")
                ?? "council"
            if mode == "council" {
                await council(prompt: prompt,
                              grounding: grounding,
                              finish: finish)
                return
            }
            if mode == "weights" {
                #if canImport(MLXLLM)
                if let verdict = await weightsVerdict(
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
            } else {
                if let verdict = interpret(
                    await SkelliModelBox.run(
                        instructions: grounding,
                        prompt: prompt)) {
                    finish(verdict)
                    return
                }
                #if canImport(MLXLLM)
                if let verdict = await weightsVerdict(
                    instructions: grounding,
                    prompt: prompt) {
                    finish(verdict)
                    return
                }
                #endif
            }
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
enum SkelliModelBox {
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
/// through MLX — picked in her Weights sheet,
/// downloaded from the hub into the app's own
/// cache, kept resident once woken.
@available(iOS 17.0, *)
enum SkelliWeights {
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

    /// The mood she has settled into: a new one
    /// must persist a breath, and the change
    /// fades — she never snaps between states.
    @State private var settled: SkelliMood = .idle

    static var filmsPresent: Bool {
        Bundle.main.url(forResource: "skelli-idle",
                        withExtension: "mp4") != nil
    }

    private var film: String {
        switch settled {
        case .idle: return "skelli-idle"
        case .thinking: return "skelli-thinking"
        case .working: return "skelli-working"
        case .speaking: return "skelli-talking"
        }
    }

    var body: some View {
        Group {
            if Self.filmsPresent {
                SkelliFilm(name: film)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(
                        cornerRadius: size * 0.2))
            } else {
                SkelliAvatar(mood: settled, size: size)
                    .id(settled)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5),
                   value: settled)
        .onAppear { settled = mood }
        .onChange(of: mood) { newMood in
            Task {
                try? await Task.sleep(
                    nanoseconds: 300_000_000)
                if mood == newMood {
                    settled = newMood
                }
            }
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
    private let layerA = AVPlayerLayer()
    private let layerB = AVPlayerLayer()
    private var activeIsA = true
    private var playerA: AVPlayer?
    private var playerB: AVPlayer?
    private var endObservers: [NSObjectProtocol] = []
    private var readiness: NSKeyValueObservation?
    private var current: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        for filmLayer in [layerA, layerB] {
            filmLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(filmLayer)
        }
        layerB.opacity = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layerA.frame = bounds
        layerB.frame = bounds
    }

    /// Crossfade, never cut: the new film starts
    /// hidden; when ready, the layers trade
    /// places over half a second.
    func play(_ name: String) {
        guard name != current else { return }
        current = name
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "mp4")
        else { return }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        endObservers.append(
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item, queue: .main) {
                    [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                })
        let incoming = activeIsA ? layerB : layerA
        let outgoing = activeIsA ? layerA : layerB
        incoming.player = player
        incoming.opacity = 0
        if activeIsA { playerB = player }
        else { playerA = player }
        player.play()
        readiness?.invalidate()
        readiness = item.observe(
            \.status, options: [.new]) {
                [weak self] item, _ in
                guard item.status == .readyToPlay
                else { return }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.readiness?.invalidate()
                    self.readiness = nil
                    let old = self.activeIsA
                        ? self.playerA : self.playerB
                    CATransaction.begin()
                    CATransaction
                        .setAnimationDuration(0.55)
                    incoming.opacity = 1
                    outgoing.opacity = 0
                    CATransaction.commit()
                    self.activeIsA.toggle()
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.6) {
                        old?.pause()
                        outgoing.player = nil
                    }
                }
            }
    }

    func stop() {
        playerA?.pause()
        playerB?.pause()
        for observer in endObservers {
            NotificationCenter.default
                .removeObserver(observer)
        }
        endObservers = []
        readiness?.invalidate()
        readiness = nil
        playerA = nil
        playerB = nil
        current = nil
    }

    deinit { stop() }
}

// MARK: - Her tab

struct SkelliView: View {
    @ObservedObject private var skelli = SkelliCenter.shared
    @ObservedObject private var stationLive =
        SigintStation.shared
    @ObservedObject private var boardLive =
        ProcessBoard.shared
    @ObservedObject private var runner = MacroRunner.shared
    @ObservedObject private var heart = SkelliHeart.shared
    @ObservedObject private var probing = ProbingBeacon.shared
    @ObservedObject private var themes = ThemeCenter.shared
    @EnvironmentObject private var emcon: Emcon
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var post: ListeningPost
    // The composer's half-written line is kept, so
    // a close mid-thought reopens with the draft
    // still in the box. Sending clears it as before.
    @AppStorage("skelli.draft") private var input = ""
    @State private var showOptions = false
    @State private var showScrapbook = false
    @State private var showDirectory = false
    @State private var showMemory = false
    @State private var showWeights = false
    @State private var showForge = false
    @State private var showDeliveries = false
    @AppStorage("skelli.mindMode")
    private var mindMode = "council"
    @AppStorage("skelli.moods") private var moodsEnabled = true
    @AppStorage("skelli.agents")
    private var agentsEnabled = false
    @State private var confirmClear = false
    @State private var confirmReset = false
    @FocusState private var inputFocused: Bool
    @State private var wireHistory: [Int] = []
    @State private var airHistory: [Int] = []

    var body: some View {
        NavigationStack {
            screen
        }
        .onAppear { SkelliMind.warm() }
        .sheet(isPresented: $showOptions) {
            optionsSheet
        }
        .sheet(isPresented: $showDirectory) {
            SkelliDirectoryView()
        }
        .sheet(isPresented: $showMemory) {
            SkelliMemoryView()
        }
        .sheet(isPresented: $showWeights) {
            WeightsView()
        }
        .sheet(isPresented: $showForge) {
            ForgeView()
        }
        .sheet(isPresented: $showDeliveries) {
            DeliveriesView()
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
        VStack(spacing: 0) {
            pinnedHeader
            transcript
            inputBar
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottomLeading) {
            SkelliWebHost()
                .frame(width: 2, height: 2)
                .allowsHitTesting(false)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Her pinned presence: film, name, activity,
    /// and the analysis deck — solid at the top.
    private var pinnedHeader: some View {
        VStack(spacing: 0) {
            header
            activityBar
            intelStrip
            vanishBar
        }
        .padding(.top, 50)
        .background {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.92))
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.45)
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color.white
                                     .opacity(0.05),
                                 .clear],
                        startPoint: .top,
                        endPoint: .bottom))
                Rectangle()
                    .fill(RadialGradient(
                        colors: [themes.current.accent
                                     .opacity(0.10),
                                 .clear],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: 240))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.clear,
                             themes.current.accent
                                 .opacity(0.55),
                             .clear],
                    startPoint: .leading,
                    endPoint: .trailing))
                .frame(height: 1)
                .shadow(
                    color: themes.current.accent
                        .opacity(0.6),
                    radius: 4)
        }
    }

    /// Her options, living inside her own bar. A sheet,
    /// not a popover menu: the menu outgrew its card
    /// twice (twelve rows clipped its last row on
    /// device, 2026-10-18; even folded to ten it sat
    /// at the threshold for shorter screens and
    /// larger type). A sheet scrolls — it cannot clip.
    private var menuButton: some View {
        Button {
            showOptions = true
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

    /// Close the options sheet, then open the door —
    /// one sheet hands off to the next.
    private func openDoor(_ open: @escaping () -> Void) {
        showOptions = false
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.35) { open() }
    }

    private var optionsSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        openDoor { showDirectory = true }
                    } label: {
                        Label("Directory of the house",
                              systemImage: "book")
                    }
                    Button {
                        openDoor { showMemory = true }
                    } label: {
                        Label("Memory",
                              systemImage: "brain")
                    }
                    Button {
                        openDoor { showWeights = true }
                    } label: {
                        Label("Weights",
                              systemImage: "memorychip")
                    }
                    Button {
                        openDoor { showForge = true }
                    } label: {
                        Label("Forge",
                              systemImage: "hammer")
                    }
                    Button {
                        openDoor { showDeliveries = true }
                    } label: {
                        Label("Deliveries",
                              systemImage: "shippingbox")
                    }
                }
                Section("Switches") {
                    Toggle(isOn: $skelli.webResearchEnabled) {
                        Label("Web research",
                              systemImage: "globe")
                    }
                    Toggle(isOn: $agentsEnabled) {
                        Label("Agents — her crew",
                              systemImage: "person.3")
                    }
                    Toggle(isOn: $moodsEnabled) {
                        Label("Moods — her heart",
                              systemImage: "heart")
                    }
                }
                if SkelliMind.weightsReady {
                    Section("Mind") {
                        mindRow("council", "Council of both",
                                "person.2")
                        mindRow("apple", "Apple only",
                                "apple.logo")
                        mindRow("weights", "Weights only",
                                "scalemass")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        openDoor { confirmClear = true }
                    } label: {
                        Label("Clear conversation",
                              systemImage: "trash")
                    }
                    Button(role: .destructive) {
                        openDoor { confirmReset = true }
                    } label: {
                        Label("Reset to defaults",
                              systemImage:
                                "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showOptions = false }
                }
            }
        }
    }

    private func mindRow(_ mode: String, _ title: String,
                         _ symbol: String) -> some View {
        Button {
            mindMode = mode
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if mindMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(
                            themes.current.accent)
                }
            }
        }
    }

    private var activityBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(skelli.mood == .idle
                      ? Color.secondary
                      : themes.current.accent)
                .frame(width: 7, height: 7)
                .animation(.easeInOut(duration: 0.45),
                           value: skelli.mood)
            Text(skelli.activity)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    /// The emergency stop — always in reach in her
    /// pinned header, and mutable: what it says and
    /// how it burns follow what she is doing. Idle,
    /// it is the Vanish control, one tap to full
    /// stealth. Busy, it names the act — STOP —
    /// and the same tap halts it and vanishes.
    private var vanishBar: some View {
        let busy = skelli.anythingRunning
        return HStack(spacing: 10) {
            Button {
                Haptics.vanish()
                skelli.haltAndVanish()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "octagon.fill")
                    Text(busy
                         ? "STOP — halt everything, "
                           + "full stealth"
                         : "Vanish — full stealth")
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    if runner.running {
                        Text("macro: "
                             + runner.currentMacroName)
                            .font(.caption)
                            .foregroundStyle(
                                .white.opacity(0.8))
                            .lineLimit(1)
                    } else if skelli.mood == .working
                                || skelli.mood == .thinking {
                        Text(skelli.activity)
                            .font(.caption)
                            .foregroundStyle(
                                .white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    busy ? Color.red
                        : Color.red.opacity(0.28),
                    in: RoundedRectangle(
                        cornerRadius: 10,
                        style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
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
                    .fixedSize(horizontal: false,
                               vertical: true)
                if moodsEnabled {
                    Label("feeling "
                          + heart.feeling.word,
                          systemImage: heart.feeling.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(heart.feeling.tint)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            menuButton
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: her heart

    /// The tamagotchi strip: her three needs as thin
    /// bars, and her standing want with a door that lets
    /// her do it — the ask goes through her own respond
    /// path, so every gate her hands answer to (EMCON
    /// first of all) still stands. Shown only while
    /// Moods is on in her menu.
    private var heartStrip: some View {
        VStack(alignment: .leading, spacing: 5) {
            TimelineView(.periodic(from: .now, by: 25)) {
                _ in
                Text(skelli.idleThought())
                    .font(.caption.italic())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false,
                               vertical: true)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
            }
            HStack(spacing: 6) {
                Text("Bond: " + heart.bond
                     + " · day \(heart.daysKnown + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !SkelliScrapbook.shared.facts.isEmpty {
                    Button {
                        showScrapbook.toggle()
                    } label: {
                        Text("Learned about you "
                             + "(\(SkelliScrapbook.shared.facts.count))")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            if showScrapbook {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SkelliScrapbook.shared.facts,
                            id: \.self) { fact in
                        Text("· " + fact)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        SkelliScrapbook.shared.clear()
                        showScrapbook = false
                    } label: {
                        Text("Forget all of it")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 10) {
                needBar("Attention", heart.attention, .pink)
                needBar("Itch", heart.itch, .orange)
                needBar("Pride", heart.pride, .yellow)
            }
            if let want = heart.want {
                HStack(spacing: 8) {
                    Text(want.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false,
                                   vertical: true)
                    Spacer()
                    if let ask = want.ask {
                        Button {
                            SkelliHeart.shared
                                .noteWantAccepted()
                            input = ""
                            skelli.ask(ask)
                        } label: {
                            Text("Let her")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .id(heart.pulse)
    }

    private func needBar(_ label: String, _ value: Double,
                         _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width
                            * CGFloat(value) / 100))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: her analysis deck

    /// Continuous analysis: exposure scored
    /// live, wire and air watched as they move,
    /// the registry and every battery the air has
    /// reported, the board of running work — and
    /// one triaged sentence for what matters,
    /// discoveries first. Everything is computed
    /// from the organs' own publishers, so the
    /// deck updates itself as the house learns.
    private var intelStrip: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                exposurePanel
                wirePanel
                airPanel
            }
            HStack(spacing: 8) {
                signalsPanel
                batteryPanel
                processesPanel
            }
            verdictLine
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onReceive(Timer.publish(
            every: 5, on: .main, in: .common)
            .autoconnect()) { _ in sample() }
        .onAppear { sample() }
    }

    private func panel<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content)
        -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.09),
                        lineWidth: 0.75))
    }

    private func panelValue(_ text: String)
        -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold,
                          design: .rounded))
            .monospacedDigit()
    }

    private func panelSub(_ text: String)
        -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func meter(_ fraction: Double)
        -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(themes.current.accent)
                    .frame(width: max(
                        2, geo.size.width
                            * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
    }

    private func sparkBars(_ values: [Int])
        -> some View {
        // Width-aware: a bar a sample at a fixed pitch
        // overflows a third-width panel once the
        // history fills, and the overflow drew straight
        // across the panel's number (Chase's phone,
        // 2026-10-18). The bars now take only the space
        // the row actually leaves them and show the
        // most recent samples that fit it.
        GeometryReader { geo in
            let slots = max(1, Int(geo.size.width / 4.5))
            let shown = Array(values.suffix(slots))
            let peak = max(1, shown.max() ?? 1)
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(shown.enumerated()),
                        id: \.offset) { _, v in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(themes.current.accent
                            .opacity(0.55))
                        .frame(width: 3,
                               height: 3 + 11
                                * CGFloat(v)
                                / CGFloat(peak))
                }
            }
            .frame(height: 15, alignment: .bottom)
        }
        .frame(height: 15)
    }

    private var liveScore: Emcon.Score {
        // The audit — the same single reading the EMCON
        // tab shows, so her pinned widget never disagrees
        // with the room that governs it.
        emcon.currentScore(mouth: mouth)
    }

    private var exposurePanel: some View {
        let score = liveScore
        let loudest = score.parts.max(by: {
            $0.points < $1.points })?.label
        return panel(label: "EXPOSURE") {
            HStack(alignment: .firstTextBaseline,
                   spacing: 4) {
                panelValue(Emcon.fmt(score.value))
                Text(score.band.uppercased())
                    .font(.system(size: 8.5,
                                  weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            meter(Double(score.value) / 100)
            panelSub(loudest
                ?? "nothing announcing")
        }
    }

    private var wirePanel: some View {
        let neighbors = NeighborhoodStore.shared
            .neighbors
        let unknown = neighbors.filter {
            $0.name == nil && $0.customName == nil
        }.count
        let fresh = neighbors.filter {
            Date().timeIntervalSince($0.firstSeen)
                < 600
        }.count
        var sub = unknown > 0
            ? "\(unknown) unknown" : "all named"
        if fresh > 0 { sub += " · \(fresh) new" }
        return panel(label: "WIRE") {
            HStack(alignment: .bottom, spacing: 6) {
                panelValue("\(neighbors.count)")
                    .layoutPriority(1)
                sparkBars(wireHistory)
            }
            panelSub(sub)
        }
    }

    private var airPanel: some View {
        panel(label: "AIR · BLE") {
            HStack(alignment: .bottom, spacing: 6) {
                panelValue("\(post.deviceCount)")
                    .layoutPriority(1)
                sparkBars(airHistory)
            }
            panelSub(post.session != nil
                ? "\(post.sightingCount) sightings"
                : "ear down")
        }
    }

    private var signalsPanel: some View {
        let station = SigintStation.shared
        let trackers = station.emitters.filter {
            $0.trackerShaped }.count
        var sub = station.currentWatch != nil
            ? "\(station.newSinceWatchStart()) new "
                + "this watch"
            : "epoch registry"
        if trackers > 0 {
            sub = "\(trackers) tracker-shaped · " + sub
        }
        return panel(label: "SIGNALS") {
            panelValue("\(station.emitters.count)")
            panelSub(sub)
        }
    }

    private var batteryPanel: some View {
        // One panel, one return: the generic panel
        // helper makes two returns of it two different
        // concrete types, which an opaque some View
        // cannot hold — so value and sub are settled
        // first and the panel is built once.
        let reporting = post.rows.filter {
            $0.batteries.contains {
                $0.component == "device" } }
        let weakest = reporting.min(by: {
            ($0.batteries.first {
                $0.component == "device" }?.percent ?? 10_000)
                < ($1.batteries.first {
                    $0.component == "device" }?.percent
                   ?? 10_000) })
        let reading = weakest.flatMap { w in
            w.batteries.first {
                $0.component == "device" } }
        var value = "—"
        var sub = "none reporting"
        if let weakest, let reading {
            let name = weakest.name
                ?? weakest.preferredLabel ?? weakest.kind
            sub = name
            if let forecast = weakest.batteryForecastText {
                sub += " · " + forecast
            }
            if let percent = reading.percent {
                value = "\(percent)%"
            } else if let millivolts = reading.millivolts {
                value = "\(millivolts)"
                sub = "mV · " + sub
            } else {
                value = reading.state ?? "—"
            }
        }
        return panel(label: "BATTERY") {
            panelValue(value)
            panelSub(sub)
        }
    }

    private var processesPanel: some View {
        let board = ProcessBoard.shared
        var sub = "board clear"
        if let last = board.recent.first {
            sub = "last: " + last.label
        }
        return panel(label: "PROCESSES") {
            panelValue("\(board.active.count)")
            panelSub(board.active.isEmpty
                     ? sub
                     : (board.active.first?.label ?? sub))
        }
    }

    /// The discovery line: what the house has
    /// passively learned that the operator has
    /// not been told yet, triaged — a watch
    /// finding first, then a dying battery, a
    /// tracker shape, a changed advertisement —
    /// and only then the standing verdict.
    private var discovery: (icon: String, text: String)? {
        let station = SigintStation.shared
        if station.currentWatch != nil {
            let fresh = station.newSinceWatchStart()
            if fresh > 0 {
                return ("eye.fill",
                        "Watch: \(fresh) new emitter"
                        + (fresh == 1 ? "" : "s")
                        + " since it began")
            }
        }
        let now = Date().timeIntervalSince1970
        if let low = post.rows
            .filter({ now - $0.lastSeen < 900 })
            .compactMap({ row -> (DeviceRow, Int)? in
                guard let battery = row.batteries.first(
                    where: { $0.component == "device" }),
                    let percent = battery.percent,
                    percent <= 20
                else { return nil }
                return (row, percent)
            })
            .min(by: { $0.1 < $1.1 }) {
            let name = low.0.name ?? low.0.preferredLabel
                ?? low.0.kind
            return ("battery.25",
                    "Low battery: \(name) at \(low.1)%")
        }
        if let tracker = post.rows.first(where: {
            $0.trackerShaped && now - $0.lastSeen < 900 }) {
            let name = tracker.name
                ?? tracker.preferredLabel ?? tracker.kind
            return ("magnifyingglass",
                    "Tracker-shaped in the air: " + name)
        }
        if let changed = post.rows.first(where: {
            $0.payloadChanges > 0
                && now - $0.lastSeen < 900 }) {
            let name = changed.name
                ?? changed.preferredLabel ?? changed.kind
            return ("arrow.triangle.swap",
                    name + " changed its advertisement "
                    + "shape")
        }
        return nil
    }

    private var verdictLine: some View {
        HStack(spacing: 6) {
            Image(systemName: discovery?.icon ?? verdictIcon)
                .font(.system(size: 10,
                              weight: .semibold))
                .foregroundStyle(
                    themes.current.accent)
            Text(discovery?.text ?? verdict)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }

    private var verdictIcon: String {
        if !emcon.exposures.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        if !mouth.inbox.isEmpty {
            return "envelope.fill"
        }
        if NeighborhoodStore.shared.neighbors
            .contains(where: {
                Date().timeIntervalSince(
                    $0.firstSeen) < 600 }) {
            return "sparkles"
        }
        if mouth.serveRunning && !mouth.stealth {
            return "antenna.radiowaves.left.and.right"
        }
        return "checkmark.shield.fill"
    }

    private var verdict: String {
        if !emcon.exposures.isEmpty {
            let n = emcon.exposures.count
            var text = "\(n) exposure"
                + (n == 1 ? "" : "s")
                + " announce you"
            if let worst = emcon.exposures.first {
                text += " — " + worst.service
                    + " on " + worst.host
            }
            return text
        }
        if !mouth.inbox.isEmpty {
            let n = mouth.inbox.count
            return "\(n) payload"
                + (n == 1 ? "" : "s")
                + " waiting in the Serve inbox"
        }
        let fresh = NeighborhoodStore.shared
            .neighbors.filter {
                Date().timeIntervalSince(
                    $0.firstSeen) < 600
            }.sorted { $0.firstSeen > $1.firstSeen }
        if let new = fresh.first {
            return "New on the wire: "
                + new.displayName
        }
        if mouth.serveRunning && !mouth.stealth {
            return "Serve is open and announcing — "
                + "your loudest emission"
        }
        if let event = Journal.events(limit: 1)
            .first {
            return event.text
        }
        return emcon.active
            ? "All quiet. You are dark, and the "
                + "wire is known."
            : "All quiet on the wire."
    }

    private func sample() {
        wireHistory.append(
            NeighborhoodStore.shared.neighbors.count)
        if wireHistory.count > 28 {
            wireHistory.removeFirst(
                wireHistory.count - 28)
        }
        airHistory.append(post.deviceCount)
        if airHistory.count > 28 {
            airHistory.removeFirst(
                airHistory.count - 28)
        }
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
                .padding(.top, 10)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.8),
                             Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom)
                    .frame(height: 16)
                    .allowsHitTesting(false)
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
                Haptics.tap()
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
            List(SkelliKnowledge.entries
                + SkelliKnowledge.batches) { entry in
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
