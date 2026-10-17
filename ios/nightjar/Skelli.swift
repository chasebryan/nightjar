import Combine
import Foundation
import SwiftUI

/// Skelli — the house's specialist.
///
/// Not a general intelligence and never pretending to
/// be: a specialist for this one application, at home
/// in it. Its knowledge is the app's own manual, its
/// senses are the app's live state — the wire, the log,
/// the mind, the instrument — and its hands are the
/// app's own controls, worked through the same organs
/// the tabs use. It answers only from those, and when
/// a question leaves the house it says so.
///
/// Loud and destructive levers keep their own
/// confirmations: Skelli walks the operator to them
/// and names why, rather than pulling them itself.
/// Everything it does directly, it does in the open,
/// and its acts are journaled under its own name.

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
            body: "A passive Bluetooth LE listening post. "
                + "It never connects or pairs; it logs "
                + "advertisements, builds a presence "
                + "registry, decodes Apple Continuity and "
                + "Remote ID drone broadcasts, and flags "
                + "unknown trackers. Sessions are kept in "
                + "the same JSONL the Mac tools read."),
        SkelliEntry(
            id: "send", title: "Send — the throwing arm",
            home: "the Send tab",
            keywords: ["send", "payload", "throw", "fan-out",
                       "fanout", "snatchsteal", "payplant",
                       "timed", "template"],
            body: "Payloads out over TCP, UDP, TLS, HTTP, "
                + "and BLE — typed by hand or from the "
                + "protocol library, templated with the "
                + "target, fanned out to many hosts, "
                + "timed, repeated, or planted to stay "
                + "living on a service (PayPlant). "
                + "SnatchSteal knocks, then drains "
                + "everything the target sends back."),
        SkelliEntry(
            id: "serve", title: "Serve — the open door",
            home: "the Serve tab",
            keywords: ["serve", "listener", "listen on",
                       "inbox", "stealth", "reply"],
            body: "TCP, UDP, and HTTP listeners with "
                + "fixed or echo replies and an inbox "
                + "that banners arrivals. Stealth stops "
                + "the Bonjour listing — reachable by "
                + "known address, invisible on the board. "
                + "The BLE GATT host arms once and "
                + "survives backgrounding until you stop "
                + "it yourself."),
        SkelliEntry(
            id: "sessions", title: "Sessions",
            home: "the Sessions tab",
            keywords: ["sessions", "recordings", "history",
                       "export", "jsonl"],
            body: "Every listening session the ear has "
                + "kept, in the nightjar JSONL the "
                + "desktop tools read. Sessions can be "
                + "shared out, and deleted — singly or "
                + "all at once, behind a confirmation."),
        SkelliEntry(
            id: "nightlog", title: "The Night log",
            home: "EMCON's brief and the About tab",
            keywords: ["night log", "journal", "sealed",
                       "log", "hash", "record", "brief",
                       "morning"],
            body: "The house's sealed journal: every "
                + "organ writes to one hash-chained JSONL "
                + "in Documents, each line bound to the "
                + "one before it, so the record testifies "
                + "about tampering itself. It folds "
                + "behind an Entries door, clears behind "
                + "a confirmation, and its morning brief "
                + "opens the day. Contents of knocktalk "
                + "are never journaled — only arrivals."),
        SkelliEntry(
            id: "scan", title: "Scan — the wire, swept",
            home: "the Scan tab",
            keywords: ["scan", "sweep", "ports", "subnet",
                       "discovery", "bonjour", "tls", "dns",
                       "pcap", "feed"],
            body: "A connect scanner and a /24 subnet "
                + "sweep, a Bonjour board that resolves "
                + "to addresses, an observation feed that "
                + "narrates hosts coming and going, a TLS "
                + "inspector, a DNS toolkit, and a pcap "
                + "dissector for captures from your own "
                + "machines. Everything it finds feeds "
                + "the Neighborhood and the Map."),
        SkelliEntry(
            id: "dossiers", title: "Dossiers",
            home: "the Scan tab, under Dossiers",
            keywords: ["dossier", "device page", "baseline",
                       "profile"],
            body: "One page per device, every organ's "
                + "testimony in one place: what Scan "
                + "heard, whether the ear knows the name "
                + "over Bluetooth, its given name and "
                + "mark, its drift — and a knock baseline "
                + "you can set, so the house can say when "
                + "the device stops sounding like itself."),
        SkelliEntry(
            id: "map", title: "The Map",
            home: "the top of the Scan tab",
            keywords: ["map", "rooms", "room", "placed",
                       "floor", "house plan", "layout"],
            body: "The house on one canvas: you name "
                + "rooms and place each neighbor where "
                + "the device physically sits; nodes "
                + "glow by freshness, carry their drift, "
                + "and open their dossiers. Placement is "
                + "your testimony — the app keeps it and "
                + "never invents a location of its own. "
                + "The Map resets from its More menu; "
                + "the devices stay, the sitting is "
                + "forgotten."),
        SkelliEntry(
            id: "compass", title: "The Compass",
            home: "the Map's 'In the air' strip",
            keywords: ["compass", "homing", "walk", "find",
                       "direction", "bearing", "paw"],
            body: "Walk to a Bluetooth device the ear is "
                + "hearing: signal in honest bands with "
                + "paw-prints for distance, a ring that "
                + "fills as you close in, and a bearing "
                + "that condenses out of your own "
                + "footsteps — Bluetooth gives a loudness, "
                + "never a direction, so the direction is "
                + "learned from your walking. No wedge "
                + "until you have walked."),
        SkelliEntry(
            id: "neighborhood", title: "The Neighborhood",
            home: "the Scan tab",
            keywords: ["neighborhood", "neighbors",
                       "neighbours", "devices", "given name",
                       "name a device", "rename", "mark"],
            body: "The wire's cast, kept: every device "
                + "the house has learned — by sweep, by "
                + "announcement, by knock at its own door "
                + "— with its sightings, ports, drift, "
                + "and arrivals. Any of them can be given "
                + "your own name and a mark, and the name "
                + "follows the device everywhere. The "
                + "board folds behind a counted door and "
                + "clears behind a confirmation."),
        SkelliEntry(
            id: "recon", title: "The Recon bench",
            home: "the Recon tab",
            keywords: ["recon", "bench", "knock", "connect",
                       "fuzz", "census", "probe"],
            body: "The pocket bench: knock a host across "
                + "the full port census speaking each "
                + "port's own first words, read banners, "
                + "fuzz a service with malformed "
                + "greetings, and keep presets of the "
                + "knocks you run often. Its answers feed "
                + "the Neighborhood like everything "
                + "else's."),
        SkelliEntry(
            id: "emcon", title: "EMCON — the posture",
            home: "the EMCON tab",
            keywords: ["emcon", "score", "posture", "ghost",
                       "exposure", "dark", "visible"],
            body: "Emission control: one number for how "
                + "visible this phone is — its own "
                + "listeners, its announcements, its "
                + "radios — with the weights shown. "
                + "Going dark silences what the house "
                + "owns: stealth on, beacon and GATT "
                + "host down, tripwire armed. The score "
                + "never hides what it cannot silence; "
                + "your VPN's own listener reads as what "
                + "it is."),
        SkelliEntry(
            id: "tripwire", title: "The tripwire & prober files",
            home: "the EMCON tab",
            keywords: ["tripwire", "prober", "knocked me",
                       "who knocked", "probed"],
            body: "Silent listeners bound on the census "
                + "ports: anyone who knocks this phone "
                + "is logged — source, port, first words "
                + "— and never answered. The prober files "
                + "assemble a dossier per knocker from "
                + "that log. Both fold to six with a door "
                + "to the rest, and the log clears from "
                + "its own section."),
        SkelliEntry(
            id: "drill", title: "The drill",
            home: "the EMCON tab",
            keywords: ["drill", "prove it", "went quiet",
                       "silenced"],
            body: "'Prove it — scan, go dark, scan "
                + "again.' The drill snapshots the "
                + "phone's exposure, engages EMCON, "
                + "measures again, and reads the "
                + "difference out — from a ledger of "
                + "what it switched off, beside the "
                + "snapshot diff, because a withdrawn "
                + "Bonjour listing echoes in mDNS after "
                + "it dies and a scan alone would swear "
                + "nothing happened."),
        SkelliEntry(
            id: "assault", title: "Net-Assault",
            home: "the EMCON tab, under the skull",
            keywords: ["net-assault", "net assault",
                       "assault", "autonomous", "passes",
                       "after-action", "after action"],
            body: "The house turned loose on its own "
                + "wire: sweeps on rotating ports, the "
                + "Bonjour browse, and the bench knocking "
                + "the full census against every known "
                + "neighbor, pass after pass until you "
                + "stand it down. Loud by design — it "
                + "warns twice, runs only while the app "
                + "is awake, and exports an after-action "
                + "report when it stands down. Arming "
                + "plays the ignition reel."),
        SkelliEntry(
            id: "steward", title: "The Steward",
            home: "the EMCON tab",
            keywords: ["steward", "proposals", "suggests",
                       "latitude", "home-turf", "home turf"],
            body: "The house's judgment, on a leash: it "
                + "watches and proposes — enact or "
                + "dismiss, and it learns the shape of "
                + "your house from three banked nights "
                + "of home-turf before it proposes there. "
                + "It ships at observe latitude: it asks, "
                + "it does not act alone."),
        SkelliEntry(
            id: "subconscious", title: "The Subconscious",
            home: "the EMCON tab — 'Open the mind'",
            keywords: ["subconscious", "mind", "findings",
                       "facts", "learned", "verdict",
                       "pattern", "brief", "ask"],
            body: "The mind underneath: it reads across "
                + "every organ — log, wire, Map, "
                + "cadence, the Instrument — and names "
                + "what breaks the house's pattern, with "
                + "citations and printed confidence. It "
                + "consolidates: durable facts with "
                + "their evidence, contradicted in the "
                + "open when the house breaks them. "
                + "Your True / Not so verdicts bend its "
                + "confidences and teach its priorities. "
                + "Ask it about the record in its own "
                + "view. It never acts; it advises."),
        SkelliEntry(
            id: "instrument", title: "The Instrument",
            home: "the EMCON tab, below the Subconscious",
            keywords: ["instrument", "watch", "apple watch",
                       "heart", "sleep", "health", "oxygen",
                       "hrv", "steps"],
            body: "The Apple Watch, read: worn and "
                + "paired, it already measures you and "
                + "leaves the readings in this phone's "
                + "health store — no watch app, no "
                + "session. Heart, variability, resting "
                + "heart, blood oxygen, breath, wrist "
                + "temperature, steps, and last night's "
                + "sleep as a window. A reading, not a "
                + "live feed: every value carries its "
                + "age. The mind reads you against your "
                + "own fortnight baseline."),
        SkelliEntry(
            id: "knocktalk", title: "Knocktalk",
            home: "the Knocktalk tab",
            keywords: ["knocktalk", "messages", "chat",
                       "sealed", "pairing", "burn"],
            body: "Messages that travel as knock ORDER "
                + "alone — a ChaCha20-Poly1305 sealed box "
                + "spelled in port sequences under a "
                + "pairing key kept in the Keychain. The "
                + "journal records arrivals, never "
                + "contents. A burn timer deletes decoded "
                + "messages after the retention you set. "
                + "Threads clear from its Housekeeping, "
                + "key untouched."),
        SkelliEntry(
            id: "vault", title: "The knock vault",
            home: "the EMCON tab",
            keywords: ["vault", "combination", "raise serve",
                       "secret knock"],
            body: "Three protocol digits you choose, "
                + "spoken properly by one other device "
                + "inside twenty seconds, raise Serve "
                + "from its settings for sixty seconds — "
                + "then it seals itself. The combination "
                + "is yours, changeable in EMCON."),
        SkelliEntry(
            id: "cadence", title: "The Cadence Seal",
            home: "the Knocktalk tab and EMCON's grading",
            keywords: ["cadence", "foreign hands", "rhythm",
                       "timing", "hands", "fingerprint"],
            body: "Knock timing is a fingerprint: the "
                + "seal learns each peer's rhythm across "
                + "six features and flags a correct key "
                + "knocked by the wrong hands — FOREIGN "
                + "HANDS — in the thread, the banner, "
                + "and the journal. It annotates, never "
                + "blocks. Profiles forget from "
                + "Knocktalk's Housekeeping."),
        SkelliEntry(
            id: "throw", title: "Throw Your Voice",
            home: "the Knocktalk tab",
            keywords: ["throw", "voice", "remote", "receipt",
                       "command another"],
            body: "One phone instructs another by "
                + "knocktalk — send this, there, now — "
                + "and the armed mouth executes and "
                + "returns a receipt that settles the "
                + "delivery in the thread. The "
                + "instruction rides sealed, like any "
                + "other message."),
        SkelliEntry(
            id: "coin", title: "The Coin",
            home: "the EMCON tab",
            keywords: ["coin", "nfc", "tag", "physical key"],
            body: "A physical key: any NFC tag, claimed "
                + "by a hash of its contents. Taps check "
                + "in the dead hand, raise the vault, or "
                + "unlock a coin-locked Knocktalk. "
                + "Honest limit: under free (Personal "
                + "Team) signing iOS refuses the NFC "
                + "entitlement, so the Coin ships "
                + "dormant — present, truthful, and live "
                + "the moment a paid team signs the app."),
        SkelliEntry(
            id: "testament", title: "Last Testament & the dead hand",
            home: "the EMCON tab",
            keywords: ["testament", "dead hand", "capsule",
                       "after", "sealed note"],
            body: "A note sealed under a time-lock "
                + "grind that the app refuses to open "
                + "until the dead hand has fallen and its "
                + "days have passed — the refusal is the "
                + "feature. When the terms are met, the "
                + "grind runs and the plaintext replaces "
                + "the blob."),
        SkelliEntry(
            id: "duel", title: "Duel Mode",
            home: "the EMCON tab",
            keywords: ["duel", "arena", "strikes", "game",
                       "opponent"],
            body: "Two phones, one arena: the host's "
                + "real ports and decoys; the guest "
                + "strikes three a round for three "
                + "rounds with the recon bench; scoring "
                + "is read from the defender's own event "
                + "log. Herald messages ride knocktalk."),
        SkelliEntry(
            id: "season", title: "Sparring Season",
            home: "the EMCON tab",
            keywords: ["sparring", "season", "ghost",
                       "visits", "training", "grade"],
            body: "Nine ghost visits over seven days — "
                + "loud spelling, quiet knocks, a "
                + "vault combination spoken at the door "
                + "— played through the real tripwire "
                + "and scored from the journal: did the "
                + "house hear, did the Steward react, "
                + "did the vault open. A final grade is "
                + "journaled. It plays only while the "
                + "app is awake, and says so."),
        SkelliEntry(
            id: "canary", title: "Canary & honeydrop",
            home: "the Serve and EMCON tabs",
            keywords: ["canary", "honeydrop", "bait",
                       "drop", "lure"],
            body: "Bait the house keeps: a canary "
                + "service that should never be touched, "
                + "and a honeydrop payload whose takers "
                + "announce themselves — every taker "
                + "joins the Neighborhood through the "
                + "same LAN-guarded door as any other "
                + "discovery."),
        SkelliEntry(
            id: "chirp", title: "Chirp, Blink & Flare",
            home: "the Knocktalk tab",
            keywords: ["chirp", "blink", "flare", "tones",
                       "qr", "sound", "light"],
            body: "Knocktalk's other voices: messages as "
                + "audible tones (Chirp), as looping QR "
                + "frames read by the camera (Blink), "
                + "and Flare — each authenticated with "
                + "the pairing key and a five-minute "
                + "window, like everything else in the "
                + "tab."),
        SkelliEntry(
            id: "hunt", title: "The tracker hunt",
            home: "the Listen tab — a row's Hunt",
            keywords: ["hunt", "tracker", "airtag", "find",
                       "following me", "tone"],
            body: "Walk down an unknown tracker the ear "
                + "has flagged: a tone that quickens as "
                + "its smoothed signal strengthens. It "
                + "reads the listening post's own rows — "
                + "the hunt never transmits."),
        SkelliEntry(
            id: "capsule", title: "The time capsule",
            home: "the Knocktalk tab",
            keywords: ["time capsule", "rsw", "time-lock",
                       "timelock", "puzzle"],
            body: "A message sealed behind repeated "
                + "squaring — Rivest–Shamir–Wagner — so "
                + "the opening takes the time it takes "
                + "and cannot be hurried by cleverness. "
                + "Share the blob; the clock does the "
                + "rest."),
        SkelliEntry(
            id: "conductor", title: "Conductor & night maneuvers",
            home: "the EMCON tab",
            keywords: ["conductor", "maneuvers", "manoeuvres",
                       "choreograph", "sequence", "routine"],
            body: "Choreography for the house: maneuvers "
                + "that run the organs in sequence — "
                + "scan, darken, listen — and a conductor "
                + "that keeps the evening's routine in "
                + "step. Schedules the house can keep "
                + "while it is awake."),
        SkelliEntry(
            id: "colours", title: "Colours",
            home: "the About tab — the Colours section",
            keywords: ["colours", "colors", "theme",
                       "wallpaper", "backdrop", "accent",
                       "look", "customise", "customize"],
            body: "The app's wardrobe: six built-in "
                + "themes and your own — accent, glow, "
                + "and tint washing every backdrop — "
                + "plus per-tab backdrops: the living "
                + "wallpaper, the Jolly Roger kept "
                + "forever as a choice, plain colour, or "
                + "your own image or GIF, copied onto "
                + "the device and never leaving it."),
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

struct SkelliLine: Identifiable {
    var id = UUID()
    var fromOperator: Bool
    var text: String
}

// MARK: - The center

final class SkelliCenter: ObservableObject {
    static let shared = SkelliCenter()

    @Published var lines: [SkelliLine] = []
    private(set) var mouth: Mouth?
    private(set) var emcon: Emcon?
    private let scanner = ScanModel()
    private var sweepWatch: AnyCancellable?

    /// The app hands over its own organs at first light,
    /// so the specialist works the real controls, not
    /// stand-ins.
    func wire(mouth: Mouth, emcon: Emcon) {
        self.mouth = mouth
        self.emcon = emcon
    }

    func greetIfNeeded() {
        guard lines.isEmpty else { return }
        say("I'm Skelli — the house's specialist. I "
            + "know every tab, organ, and switch in "
            + "this application; I read the wire, the "
            + "log, the mind, and the instrument live; "
            + "and I can work the controls — sweeps, "
            + "scans, posture, serve. Ask me anything "
            + "about the system, or tell me to do "
            + "something.")
    }

    func say(_ text: String) {
        lines.append(SkelliLine(fromOperator: false,
                                 text: text))
    }

    func ask(_ raw: String) {
        let text = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lines.append(SkelliLine(fromOperator: true,
                                 text: text))
        respond(to: text.lowercased())
    }

    /// The directory's way in: the entry itself,
    /// verbatim from the manual.
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

    // MARK: the routing

    private func respond(to q: String) {
        // Greetings and the tour.
        if ["hello", "hi", "hey"].contains(q)
            || q.contains("who are you") {
            say("Skelli. Specialist for this house and "
                + "nothing else — which is why I can be "
                + "trusted about it: everything I tell "
                + "you is read from the system itself. "
                + "Ask 'what can you do' for the tour.")
            return
        }
        if q.contains("what can you do")
            || q == "help" || q.contains("capabilit") {
            say(capabilities)
            return
        }

        // Explanations go to the manual before the
        // senses — "what is the mind" wants the
        // manual, not the brief.
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
                            time: .shortened))
                }.joined(separator: "\n"))
                return
            }
        }

        // The manual.
        if let entry = SkelliKnowledge.lookup(q) {
            say(entry.body + "\nFind it: \(entry.home).")
            return
        }

        say("That's outside the house. I know this "
            + "application — every tab, organ, and "
            + "switch in it — and the live state of "
            + "your wire, your log, and your night. "
            + "Ask me about those, or say 'what can you "
            + "do'.")
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
            + "confirmations; I'll walk you to those."
    }

    // MARK: hands

    private func runSweep() {
        guard !scanner.sweeping else {
            say("A sweep is already running — its "
                + "answers are landing in the "
                + "Neighborhood as they come.")
            return
        }
        say("Sweeping the wire on port 80 — the whole "
            + "/24. Answers feed the Neighborhood and "
            + "the Map as they land.")
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
        say("Knocking this phone on every census port, "
            + "loopback and its wire address — whatever "
            + "answers is what another operator sees.")
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
        say("Browsing Bonjour for this phone's own "
            + "announcements — what it calls itself, "
            + "and where it points.")
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
        return "The wire knows \(all.count) device"
            + (all.count == 1 ? "" : "s")
            + (placed > 0
               ? ", \(placed) of them placed on the Map"
               : "")
            + ". Most recently seen: \(names)"
            + (all.count > 5 ? "…" : "")
            + ". The Neighborhood board in Scan holds "
            + "them all."
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

// MARK: - The section

struct SkelliView: View {
    @ObservedObject private var skelli = SkelliCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var directory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Skelli", selection: $directory) {
                    Text("Talk").tag(false)
                    Text("Directory").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                if directory {
                    directoryList
                } else {
                    talkPane
                }
            }
            .navigationTitle("Skelli")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { skelli.greetIfNeeded() }
    }

    private var directoryList: some View {
        List(SkelliKnowledge.entries) { entry in
            Button {
                directory = false
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
        .listStyle(.plain)
    }

    private var talkPane: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(skelli.lines) { line in
                            HStack {
                                if line.fromOperator {
                                    Spacer(minLength: 40)
                                }
                                Text(line.text)
                                    .font(.callout)
                                    .padding(10)
                                    .background(
                                        line.fromOperator
                                            ? Color.accentColor
                                                .opacity(0.25)
                                            : Color.secondary
                                                .opacity(0.15),
                                        in: RoundedRectangle(
                                            cornerRadius: 12))
                                if !line.fromOperator {
                                    Spacer(minLength: 40)
                                }
                            }
                            .id(line.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: skelli.lines.count) { _ in
                    if let last = skelli.lines.last {
                        withAnimation {
                            proxy.scrollTo(last.id,
                                           anchor: .bottom)
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Who's on my wire?",
                             "Sweep the wire",
                             "What knocked last night?",
                             "How did I sleep?",
                             "What has the mind learned?",
                             "How exposed am I?",
                             "What can you do?"],
                            id: \.self) { chip in
                        Button(chip) { skelli.ask(chip) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            HStack(spacing: 8) {
                TextField("Ask Skelli, or give an order…",
                          text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Ask") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(
                        in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    private func send() {
        let text = input
        input = ""
        skelli.ask(text)
    }
}
