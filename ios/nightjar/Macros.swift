import Combine
import Foundation
import UserNotifications

// MARK: - Macros
//
// Playlists of the rig's own moves, built block by
// block — Scratch for the instrument. Every engine
// the app presents is a block kind in the catalog
// below; a block carries its configuration as plain
// key/value text (the same discipline as the war
// protocols), folds open in the editor to be set,
// and runs in order under the MacroRunner. Macros
// are the operator's: named, iconed, colored,
// exportable, and Skelli builds and runs them from
// dictated steps through the same store and runner
// the tab uses — one system, two pairs of hands.

/// One block in a playlist.
struct MacroBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: String
    var config: [String: String] = [:]
    var repeatCount: Int = 1

    func value(_ key: String, _ fallback: String = "") -> String {
        let raw = config[key] ?? ""
        return raw.isEmpty ? fallback : raw
    }

    func flag(_ key: String, _ fallback: Bool = false) -> Bool {
        guard let raw = config[key] else { return fallback }
        return raw == "on"
    }

    func number(_ key: String, _ fallback: Double) -> Double {
        Double(config[key] ?? "") ?? fallback
    }

    func intList(_ key: String) -> [Int] {
        value(key).split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }.filter { (1...65535).contains($0) }
    }
}

/// A saved playlist.
struct Macro: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "puzzlepiece.extension.fill"
    var colorHex: String = "148040"
    var note: String = ""
    var blocks: [MacroBlock] = []
    var createdAt = Date()
    var modifiedAt = Date()
}

// MARK: - The store

enum MacroStore {
    static let key = "macros.v1"

    static func load() -> [Macro] {
        guard let data = UserDefaults.standard.data(
                forKey: key),
              let macros = try? JSONDecoder().decode(
                [Macro].self, from: data) else { return [] }
        return macros
    }

    static func save(_ macros: [Macro]) {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    struct MacroExport: Codable {
        var schema: String
        var version: Int
        var exportedAt: Date
        var macros: [Macro]
    }

    static func exportURL(_ macros: [Macro]) -> URL? {
        let envelope = MacroExport(
            schema: "net.nosuchmachine.nightjar.macros",
            version: 1, exportedAt: Date(), macros: macros)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else {
            return nil
        }
        let url = (FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("nightjar-macros.json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The house presets, seeded once (the
    /// operator's order, 2026-10-18): the library
    /// stocks itself from the templates on first
    /// launch, so every preset can be run — by
    /// hand or by her voice — with no building
    /// first. Seeding is by name, once: a preset
    /// the operator deletes stays deleted, and
    /// one he edits keeps his edits. A later
    /// generation of presets bumps the flag.
    /// One-time field repair for libraries
    /// seeded by the first factories, whose
    /// self-test fields were frozen at
    /// authoring ("127.0.0.1:9000"): the
    /// exact old values in house presets are
    /// rewritten to the discovered forms.
    /// Anything the operator changed himself
    /// no longer matches the old strings and
    /// is left exactly as he left it.
    static func repairSeededFieldsV2() {
        let flag = "macros.fieldRepair.v2"
        guard !UserDefaults.standard.bool(
            forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        let house = Set(MacroTemplates.all.map { $0.0 })
        var macros = load()
        var touched = false
        for i in macros.indices
        where house.contains(macros[i].name) {
            for j in macros[i].blocks.indices {
                var block = macros[i].blocks[j]
                func fix(_ key: String, _ from: String,
                         _ to: String) {
                    if block.value(key) == from {
                        block.config[key] = to
                        touched = true
                    }
                }
                switch block.kind {
                case "sendPayload", "fuzzStart":
                    fix("target", "127.0.0.1:9000",
                        "tcp://127.0.0.1:{serve}")
                case "knock":
                    if block.value("host") == "127.0.0.1" {
                        fix("ports", "9000", "{serve}")
                    }
                case "warDefense":
                    fix("doors", "9000", "{serve}")
                default:
                    break
                }
                macros[i].blocks[j] = block
            }
        }
        if touched { save(macros) }
    }

    static func seedPresetsIfNeeded() {
        let flag = "macros.presetsSeeded.v1"
        guard !UserDefaults.standard.bool(
            forKey: flag) else { return }
        UserDefaults.standard.set(true, forKey: flag)
        var macros = load()
        let existing = Set(macros.map { $0.name })
        for (_, make) in MacroTemplates.all {
            let preset = make()
            if !existing.contains(preset.name) {
                macros.append(preset)
            }
        }
        save(macros)
    }

    /// Imported macros arrive as copies — fresh ids,
    /// so an import never silently overwrites the
    /// library it lands in.
    static func decodeImport(_ data: Data) -> [Macro]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Imports are files from the world:
        // generous caps, far past any human
        // library, keep a hostile file from
        // costing the house its memory (the
        // crash audit's one uncapped importer).
        let macroCap = 500
        let blockCap = 1000
        if let envelope = try? decoder.decode(
            MacroExport.self, from: data),
           envelope.schema
            == "net.nosuchmachine.nightjar.macros" {
            return envelope.macros.prefix(macroCap)
                .map { macro in
                var copy = macro
                copy.id = UUID()
                copy.blocks = macro.blocks
                    .prefix(blockCap).map { block in
                    var blockCopy = block
                    blockCopy.id = UUID()
                    return blockCopy
                }
                return copy
            }
        }
        if let bare = try? decoder.decode(
            [Macro].self, from: data) {
            return Array(bare.prefix(macroCap))
        }
        return nil
    }
}

// MARK: - The dressing palette

enum MacroPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Moss", "148040"), ("Ember", "C2451E"),
        ("Gold", "C9962E"), ("Ocean", "1E6FC2"),
        ("Violet", "6C3BD4"), ("Rose", "C22E6E"),
        ("Blood", "8E1F1F"), ("Slate", "5A6B7A"),
        ("Frost", "7FB3C8"), ("Bone", "B8B2A7"),
    ]

    static let icons: [String] = [
        "puzzlepiece.extension.fill", "play.fill",
        "bolt.fill", "moon.fill", "moon.stars.fill",
        "eye.fill", "ear.fill", "shield.fill",
        "antenna.radiowaves.left.and.right",
        "paperplane.fill", "tray.full.fill",
        "waveform", "target", "scope",
        "bell.fill", "flame.fill", "snowflake",
        "leaf.fill", "star.fill", "crown.fill",
        "key.fill", "lock.fill", "globe",
        "list.bullet", "sun.max.fill", "cloud.fill",
        "drop.fill", "theatermasks.fill",
    ]

    static func colorName(forHex hex: String) -> String {
        colors.first { $0.hex == hex }?.name ?? "Custom"
    }
}

// MARK: - The block catalog

enum MacroFieldControl: Equatable {
    case text
    case number
    case toggle
    case picker([String])
    case payloadPicker
    case chestPicker
    case personaPicker
    case remotePicker
    case helmButtonPicker
}

struct MacroField {
    let key: String
    let label: String
    let control: MacroFieldControl
    let placeholder: String

    init(_ key: String, _ label: String,
         _ control: MacroFieldControl,
         placeholder: String = "") {
        self.key = key
        self.label = label
        self.control = control
        self.placeholder = placeholder
    }
}

struct MacroKindSpec {
    let kind: String
    let title: String
    let icon: String
    let category: String
    let blurb: String
    let fields: [MacroField]
}

enum MacroCatalog {
    static let categories = [
        "Send & Serve", "Posture", "Listen & Recon",
        "The War Rooms", "Flow & Passive",
    ]

    static let specs: [MacroKindSpec] = [
        // Send & Serve
        MacroKindSpec(
            kind: "sendPayload", title: "Send a payload",
            icon: "paperplane.fill", category: "Send & Serve",
            blurb: "Fire a payload from the book at a target.",
            fields: [
                MacroField("payload", "Payload",
                           .payloadPicker),
                MacroField("target", "Target", .text,
                           placeholder: "192.168.4.31:9000 or phone:Name"),
                MacroField("readReply", "Read the reply",
                           .toggle),
            ]),
        MacroKindSpec(
            kind: "serveStart", title: "Start Serve",
            icon: "tray.and.arrow.up.fill",
            category: "Send & Serve",
            blurb: "Raise Serve — standing settings, or doors you set here.",
            fields: [
                MacroField("mode", "Doors", .picker(
                    ["Standing settings", "Custom doors"])),
                MacroField("tcp", "TCP door", .toggle),
                MacroField("tcpPort", "TCP port", .number,
                           placeholder: "9000"),
                MacroField("udp", "UDP door", .toggle),
                MacroField("udpPort", "UDP port", .number,
                           placeholder: "9001"),
                MacroField("http", "HTTP door", .toggle),
                MacroField("httpPort", "HTTP port", .number,
                           placeholder: "8080"),
                MacroField("stealth", "Stealth", .picker(
                    ["Keep", "On", "Off"])),
            ]),
        MacroKindSpec(
            kind: "serveStop", title: "Stop Serve",
            icon: "tray.and.arrow.down.fill",
            category: "Send & Serve",
            blurb: "Stand Serve down.",
            fields: []),
        MacroKindSpec(
            kind: "beaconStart", title: "Start the beacon",
            icon: "antenna.radiowaves.left.and.right",
            category: "Send & Serve",
            blurb: "Raise the BLE beacon wearing a name.",
            fields: [
                MacroField("payload", "Payload (book)",
                           .payloadPicker),
                MacroField("text", "…or literal text", .text,
                           placeholder: "used when no payload is picked"),
                MacroField("name", "Air name", .text,
                           placeholder: "what it answers to"),
            ]),
        MacroKindSpec(
            kind: "beaconStop", title: "Stop the beacon",
            icon: "antenna.radiowaves.left.and.right",
            category: "Send & Serve",
            blurb: "Stand the beacon down.",
            fields: []),
        MacroKindSpec(
            kind: "gattStart", title: "Start GATT hosting",
            icon: "wave.3.right", category: "Send & Serve",
            blurb: "Host a GATT service wearing a name.",
            fields: [
                MacroField("payload", "Payload (book)",
                           .payloadPicker),
                MacroField("text", "…or literal text", .text,
                           placeholder: "used when no payload is picked"),
                MacroField("name", "Air name", .text,
                           placeholder: "what it answers to"),
            ]),
        MacroKindSpec(
            kind: "gattStop", title: "Stop GATT hosting",
            icon: "wave.3.right", category: "Send & Serve",
            blurb: "Stand GATT hosting down.",
            fields: []),
        MacroKindSpec(
            kind: "helmFire", title: "Fire a Helm button",
            icon: "button.programmable",
            category: "Send & Serve",
            blurb: "Press one of the Helm's buttons.",
            fields: [
                MacroField("remote", "Remote", .remotePicker),
                MacroField("button", "Button",
                           .helmButtonPicker),
            ]),
        MacroKindSpec(
            kind: "chestApply", title: "Apply a War Chest",
            icon: "shippingbox.fill",
            category: "Send & Serve",
            blurb: "Dress the whole rig from a chest. Applying starts nothing.",
            fields: [
                MacroField("chest", "Chest", .chestPicker),
            ]),
        // Posture
        MacroKindSpec(
            kind: "emconOn", title: "Go dark (EMCON)",
            icon: "shield.fill", category: "Posture",
            blurb: "Silence emissions and arm the tripwire.",
            fields: []),
        MacroKindSpec(
            kind: "emconOff", title: "Stand down EMCON",
            icon: "shield", category: "Posture",
            blurb: "Stand the tripwire down. Stealth is left as it was.",
            fields: []),
        MacroKindSpec(
            kind: "stealth", title: "Stealth",
            icon: "eye.slash.fill", category: "Posture",
            blurb: "Set Serve's stealth.",
            fields: [
                MacroField("on", "Stealth on", .toggle),
            ]),
        MacroKindSpec(
            kind: "banshee", title: "The Banshee",
            icon: "megaphone.fill", category: "Posture",
            blurb: "Scream at full voice, or cease and restore.",
            fields: [
                MacroField("mode", "Mode", .picker(
                    ["Scream", "Cease"])),
            ]),
        MacroKindSpec(
            kind: "costume", title: "Wear a costume name",
            icon: "theatermasks.fill", category: "Posture",
            blurb: "Put a name on the air — a saved costume or any name.",
            fields: [
                MacroField("name", "Name", .text,
                           placeholder: "a costume, or any name"),
            ]),
        MacroKindSpec(
            kind: "persona", title: "Mimicry persona",
            icon: "facemask.fill", category: "Posture",
            blurb: "Don a persona's whole shape, or drop it.",
            fields: [
                MacroField("mode", "Mode", .picker(
                    ["Don", "Drop"])),
                MacroField("name", "Persona",
                           .personaPicker),
            ]),
        // Listen & Recon
        MacroKindSpec(
            kind: "listenStart", title: "Start listening",
            icon: "ear.fill", category: "Listen & Recon",
            blurb: "Open the BLE ear under a session label.",
            fields: [
                MacroField("label", "Session label", .text,
                           placeholder: "Macro watch"),
            ]),
        MacroKindSpec(
            kind: "listenStop", title: "Stop listening",
            icon: "ear", category: "Listen & Recon",
            blurb: "Close the ear.",
            fields: []),
        MacroKindSpec(
            kind: "sweep", title: "Sweep the wire",
            icon: "scope", category: "Listen & Recon",
            blurb: "Run a network trace on the standing scope, and wait for it.",
            fields: []),
        MacroKindSpec(
            kind: "knock", title: "Recon knock",
            icon: "hand.tap.fill", category: "Listen & Recon",
            blurb: "Knock a host's doors and wait for the answers.",
            fields: [
                MacroField("host", "Host", .text,
                           placeholder: "192.168.4.31 or gateway"),
                MacroField("ports", "Ports", .text,
                           placeholder: "22, 80, 443"),
                MacroField("udp", "UDP too", .toggle),
            ]),
        MacroKindSpec(
            kind: "fuzzStart", title: "Start the fuzzer",
            icon: "waveform.path.ecg",
            category: "Listen & Recon",
            blurb: "Fuzz a target from the runner's own bench.",
            fields: [
                MacroField("target", "Target", .text,
                           placeholder: "192.168.4.31:9000"),
                MacroField("count", "Packets", .number,
                           placeholder: "50"),
                MacroField("length", "Length", .number,
                           placeholder: "64"),
                MacroField("mutations", "Mutations",
                           .number, placeholder: "8"),
            ]),
        MacroKindSpec(
            kind: "fuzzStop", title: "Stop the fuzzer",
            icon: "waveform.path.ecg",
            category: "Listen & Recon",
            blurb: "Stand the runner's fuzzer down.",
            fields: []),
        // The War Rooms
        MacroKindSpec(
            kind: "assault", title: "Net-Assault",
            icon: "flame.fill", category: "The War Rooms",
            blurb: "Arm the assault, or stand it down.",
            fields: [
                MacroField("mode", "Mode", .picker(
                    ["Arm", "Disarm"])),
            ]),
        MacroKindSpec(
            kind: "warRoom", title: "War Room run",
            icon: "map.fill", category: "The War Rooms",
            blurb: "Start or stop a unified War Room run on the standing settings.",
            fields: [
                MacroField("mode", "Mode", .picker(
                    ["Start", "Stop"])),
            ]),
        MacroKindSpec(
            kind: "sigintWatch", title: "SIGINT watch",
            icon: "waveform.and.magnifyingglass",
            category: "The War Rooms",
            blurb: "Open a SIGINT watch on the station.",
            fields: [
                MacroField("name", L("Watch name"), .text,
                           placeholder: "Macro watch"),
                MacroField("scope", L("Scope"), .picker(
                    ["mixed", "air", "wire"])),
            ]),
        MacroKindSpec(
            kind: "warChallenge", title: "War Games challenge",
            icon: "flag.fill", category: "The War Rooms",
            blurb: "Challenge a defender by address.",
            fields: [
                MacroField("ip", "Defender address", .text,
                           placeholder: "192.168.4.31"),
                MacroField("port", "Their Serve port",
                           .number, placeholder: "9000"),
                MacroField("control", "My control port",
                           .number, placeholder: "9000"),
            ]),
        MacroKindSpec(
            kind: "warDefense", title: "War Games defense",
            icon: "shield.lefthalf.filled",
            category: "The War Rooms",
            blurb: "Set which Serve doors are real, and fly decoys.",
            fields: [
                MacroField("doors", "Real doors (ports)",
                           .text, placeholder: "9000, 8080"),
                MacroField("decoys", "Decoys (names)",
                           .text,
                           placeholder: "Printer, TV"),
            ]),
        // Flow & Passive
        MacroKindSpec(
            kind: "wait", title: "Wait",
            icon: "hourglass", category: "Flow & Passive",
            blurb: "Hold the playlist for a while.",
            fields: [
                MacroField("seconds", "Seconds", .number,
                           placeholder: "10"),
            ]),
        MacroKindSpec(
            kind: "waitInbox", title: "Wait for an arrival",
            icon: "tray.and.arrow.down.fill",
            category: "Flow & Passive",
            blurb: "Hold until something lands in the Serve inbox.",
            fields: [
                MacroField("seconds", "Give up after (s)",
                           .number, placeholder: "60"),
                MacroField("onTimeout", "On timeout",
                           .picker(["Continue",
                                    "Stop the playlist"])),
            ]),
        MacroKindSpec(
            kind: "waitSighting", title: "Wait for a sighting",
            icon: "binoculars.fill",
            category: "Flow & Passive",
            blurb: "Hold until the ear sees a new device — any, or one matching.",
            fields: [
                MacroField("match", "Name matching", .text,
                           placeholder: "blank — any new device"),
                MacroField("seconds", "Give up after (s)",
                           .number, placeholder: "60"),
                MacroField("onTimeout", "On timeout",
                           .picker(["Continue",
                                    "Stop the playlist"])),
            ]),
        MacroKindSpec(
            kind: "note", title: "Journal note",
            icon: "note.text", category: "Flow & Passive",
            blurb: "Write a marker into the night log.",
            fields: [
                MacroField("text", "Note", .text,
                           placeholder: "phase one complete"),
            ]),
        MacroKindSpec(
            kind: "announce", title: "Announce",
            icon: "bell.fill", category: "Flow & Passive",
            blurb: "Raise a local notification with your text.",
            fields: [
                MacroField("text", "Text", .text,
                           placeholder: "the wire is swept"),
            ]),
        MacroKindSpec(
            kind: "stop", title: "Stop the playlist",
            icon: "stop.fill", category: "Flow & Passive",
            blurb: "End the run here, cleanly.",
            fields: []),
    ]

    static func spec(_ kind: String) -> MacroKindSpec {
        specs.first { $0.kind == kind } ?? MacroKindSpec(
            kind: kind, title: kind, icon: "questionmark",
            category: "Flow & Passive", blurb: "",
            fields: [])
    }

    static func defaults(for kind: String) -> [String: String] {
        switch kind {
        case "sendPayload":
            return ["readReply": "on"]
        case "serveStart":
            return ["mode": "Standing settings",
                    "tcp": "on", "tcpPort": "9000",
                    "udp": "off", "udpPort": "9001",
                    "http": "off", "httpPort": "8080",
                    "stealth": "Keep"]
        case "stealth":
            return ["on": "on"]
        case "banshee":
            return ["mode": "Scream"]
        case "persona":
            return ["mode": "Don"]
        case "assault":
            return ["mode": "Arm"]
        case "warRoom":
            return ["mode": "Start"]
        case "sigintWatch":
            return ["scope": "mixed"]
        case "warChallenge":
            return ["port": "9000", "control": "9000"]
        case "wait":
            return ["seconds": "10"]
        case "waitInbox", "waitSighting":
            return ["seconds": "60", "onTimeout": "Continue"]
        case "fuzzStart":
            return ["count": "50", "length": "64",
                    "mutations": "8"]
        default:
            return [:]
        }
    }
}

// MARK: - Names the pickers and the validator share

enum MacroNames {
    static func personas() -> [SpoofyPersona] {
        SpoofyPersona.all + SpoofyStore.loadPersonas()
    }

    static func personaNames() -> [String] {
        personas().map { $0.label }
    }

    static func persona(named label: String) -> SpoofyPersona? {
        personas().first {
            $0.label.caseInsensitiveCompare(label)
                == .orderedSame
        }
    }

    static func costumeNames() -> [String] {
        var names = Spoofy.costumeNames
        for custom in SpoofyStore.loadCostumes()
        where !names.contains(custom) {
            names.append(custom)
        }
        return names
    }

    static func chestNames() -> [String] {
        NJChestStore.load().map { $0.name }
    }

    static func remoteNames() -> [String] {
        HelmStore.load().map { $0.name }
    }

    static func helmButtons(remote: String) -> [String] {
        HelmStore.load()
            .first { $0.name == remote }?
            .buttons.map { $0.label } ?? []
    }
}

// MARK: - One-line summaries (cards, logs, her voice)

enum MacroSummary {
    static func line(for block: MacroBlock) -> String {
        let spec = MacroCatalog.spec(block.kind)
        func v(_ key: String, _ fallback: String = "—") -> String {
            block.value(key, fallback)
        }
        switch block.kind {
        case "sendPayload":
            return "\(v("payload")) → \(v("target"))"
        case "serveStart":
            if block.value("mode") == "Custom doors" {
                var doors: [String] = []
                if block.flag("tcp") {
                    doors.append("tcp \(v("tcpPort"))")
                }
                if block.flag("udp") {
                    doors.append("udp \(v("udpPort"))")
                }
                if block.flag("http") {
                    doors.append("http \(v("httpPort"))")
                }
                return doors.isEmpty
                    ? L("custom — no doors open")
                    : doors.joined(separator: ", ")
            }
            return L("standing settings")
        case "beaconStart", "gattStart":
            let source = block.value("payload").isEmpty
                ? String(format: L("“%@”"), L(v("text")))
                : v("payload")
            return String(format: L("%@ as “%@”"),
                          source, v("name"))
        case "helmFire":
            return "\(v("remote")) · \(v("button"))"
        case "chestApply":
            return v("chest")
        case "stealth":
            return block.flag("on") ? L("on") : L("off")
        case "banshee":
            return v("mode").lowercased()
        case "costume":
            return String(format: L("“%@”"), v("name"))
        case "persona":
            return block.value("mode") == "Drop"
                ? L("drop the shape")
                : String(format: L("don “%@”"), v("name"))
        case "listenStart":
            return String(format: L("“%@”"),
                          v("label", L("Macro watch")))
        case "knock":
            return "\(v("host")) · \(v("ports"))"
                + (block.flag("udp") ? " · udp" : "")
        case "fuzzStart":
            return String(format: L("%@ · %lld packets"),
                          v("target"),
                          Int(block.number("count", 50)))
        case "assault", "warRoom":
            return v("mode").lowercased()
        case "sigintWatch":
            return String(format: L("“%@”"),
                          v("name", L("Macro watch")))
                + " · " + v("scope", "mixed")
        case "warChallenge":
            return "\(v("ip")):\(v("port"))"
        case "warDefense":
            return String(format: L("doors %@ · decoys %@"),
                          v("doors"), v("decoys", L("none")))
        case "wait":
            return "\(Int(block.number("seconds", 10)))s"
        case "waitInbox":
            return String(format: L("up to %llds"),
                          Int(block.number("seconds", 60)))
        case "waitSighting":
            let match = block.value("match")
            return (match.isEmpty ? L("any new device")
                    : String(format: L("“%@”"), match))
                + String(format: L(" · up to %llds"),
                         Int(block.number("seconds", 60)))
        case "note", "announce":
            return String(format: L("“%@”"), L(v("text")))
        default:
            return L(spec.blurb)
        }
    }
}

// MARK: - Validation

/// Field resolution, shared by the validator
/// and the runner so a macro is judged on the
/// values it will actually fire with. Fields
/// are discovered from the net and the house
/// at run time, never frozen at authoring
/// (the operator's order, 2026-10-18):
/// "gateway" is the door of whatever net the
/// phone wakes on — off any net, herself at
/// 127.0.0.1; "self" is the phone's own
/// address on it; "{serve}" is the TCP door
/// Serve stands on right now.
enum MacroResolve {
    static var servePort: Int {
        Int(UserDefaults.standard.string(
            forKey: "serveTcpPort") ?? "9000") ?? 9000
    }

    static var gateway: String? {
        guard let ip = Mouth.localIPAddress()
        else { return nil }
        var parts = ip.split(separator: ".")
            .map(String.init)
        guard parts.count == 4 else { return nil }
        parts[3] = "1"
        return parts.joined(separator: ".")
    }

    static func host(_ host: String) -> String {
        switch host {
        case "gateway", "router":
            return gateway ?? "127.0.0.1"
        case "self", "me", "this phone":
            return Mouth.localIPAddress() ?? "127.0.0.1"
        default:
            return host
        }
    }

    static func field(_ text: String) -> String {
        text.replacingOccurrences(
            of: "{serve}", with: String(servePort))
    }

    static func target(_ target: String) -> String {
        let text = field(target)
        // Scheme-aware: the host inside
        // "tcp://gateway:9000" resolves just
        // as the bare "gateway:9000" form does.
        if let mark = text.range(of: "://") {
            let head = text[..<mark.upperBound]
            let rest = text[mark.upperBound...]
            let end = rest.firstIndex {
                $0 == ":" || $0 == "/"
            } ?? rest.endIndex
            return String(head)
                + host(String(rest[..<end]))
                + String(rest[end...])
        }
        // A bare host:port — the form the
        // editor's placeholder has always
        // promised — is upgraded to the
        // scheme the grammar demands, so a
        // macro stored by an older build
        // heals at fire time. A MAC stays a
        // MAC: it parses as a BLE write.
        if !SendTarget.looksLikeMAC(text),
           let cut = text.firstIndex(of: ":"),
           Int(text[text.index(after: cut)...]) != nil {
            return "tcp://" + host(String(text[..<cut]))
                + String(text[cut...])
        }
        guard let cut = text.firstIndex(of: ":")
        else { return host(text) }
        return host(String(text[..<cut]))
            + String(text[cut...])
    }
}

enum MacroValidator {
    /// Every reason this playlist is not ready to
    /// run, in block order. An empty list runs.
    static func problems(in macro: Macro,
                         book: PayloadBook) -> [String] {
        var problems: [String] = []
        if macro.blocks.isEmpty {
            problems.append(L("The playlist is empty — add a block first."))
            return problems
        }
        for (index, block) in macro.blocks.enumerated() {
            let spec = MacroCatalog.spec(block.kind)
            let at = String(format: L("Block %lld (%@)"),
                            index + 1, L(spec.title))
            func need(_ condition: Bool, _ message: String) {
                if !condition {
                    problems.append(String(format: L("%@: %@"),
                                           at, message))
                }
            }
            switch block.kind {
            case "sendPayload":
                let name = block.value("payload")
                need(book.items.contains { $0.name == name },
                     String(format: L("no payload named “%@” is in the book"), name))
                let target = block.value("target")
                need(target.hasPrefix("phone:")
                     || (try? SendTarget.parse(
                        MacroResolve.target(target))) != nil,
                     String(format: L("the target “%@” does not parse"), target))
            case "beaconStart", "gattStart":
                let name = block.value("payload")
                if !name.isEmpty {
                    need(book.items.contains { $0.name == name },
                         String(format: L("no payload named “%@” is in the book"), name))
                } else {
                    need(!block.value("text").isEmpty,
                         L("pick a payload or give literal text"))
                }
            case "helmFire":
                let remotes = HelmStore.load()
                let remote = remotes.first {
                    $0.name == block.value("remote")
                }
                need(remote != nil,
                     String(format: L("no remote named “%@”"), block.value("remote")))
                if let remote {
                    need(remote.buttons.contains {
                        $0.label == block.value("button")
                    }, String(format: L("the remote has no button “%@”"), block.value("button")))
                }
            case "chestApply":
                need(NJChestStore.load().contains {
                    $0.name == block.value("chest")
                }, String(format: L("no chest named “%@”"), block.value("chest")))
            case "persona":
                if block.value("mode") != "Drop" {
                    need(MacroNames.persona(
                        named: block.value("name")) != nil,
                        String(format: L("no persona named “%@”"), block.value("name")))
                }
            case "costume":
                need(!block.value("name").isEmpty,
                     L("give the costume a name"))
            case "knock":
                need(!block.value("host").isEmpty,
                     L("give the knock a host"))
                // Judged resolved, as the
                // runner fires: "{serve}" is
                // a port the moment either
                // of them looks at it.
                let ports = MacroResolve.field(
                    block.value("ports"))
                    .split(separator: ",").compactMap {
                        Int($0.trimmingCharacters(
                            in: .whitespaces))
                    }.filter { (1...65535).contains($0) }
                need(!ports.isEmpty,
                     L("give the knock at least one port"))
            case "fuzzStart":
                need((try? SendTarget.parse(
                    MacroResolve.target(
                        block.value("target")))) != nil,
                    String(format: L("the target “%@” does not parse"), block.value("target")))
            case "warChallenge":
                need(!block.value("ip").isEmpty,
                     L("give the challenge a defender address"))
            case "note", "announce":
                need(!block.value("text").isEmpty,
                     L("give it its text"))
            default:
                break
            }
        }
        return problems
    }
}

// MARK: - Templates

enum MacroTemplates {
    static func quietPost() -> Macro {
        Macro(name: "Quiet Post", icon: "moon.fill",
              colorHex: "5A6B7A",
              note: "Stealth on, Serve up quiet, the ear "
                + "open, and a hold for whatever arrives.",
              blocks: [
                MacroBlock(kind: "stealth",
                           config: ["on": "on"]),
                MacroBlock(kind: "serveStart",
                           config: MacroCatalog.defaults(
                            for: "serveStart")),
                MacroBlock(kind: "listenStart",
                           config: ["label": "Quiet post"]),
                MacroBlock(kind: "waitInbox",
                           config: MacroCatalog.defaults(
                            for: "waitInbox")),
                MacroBlock(kind: "note",
                           config: ["text": "quiet post held"]),
              ])
    }

    static func wireSweep() -> Macro {
        Macro(name: "Wire Sweep", icon: "scope",
              colorHex: "1E6FC2",
              note: "A full trace on the standing scope, "
                + "then the word that it is done.",
              blocks: [
                MacroBlock(kind: "note",
                           config: ["text": "sweep starting"]),
                MacroBlock(kind: "sweep"),
                MacroBlock(kind: "announce",
                           config: ["text": "The wire is swept."]),
              ])
    }

    static func loudArrival() -> Macro {
        Macro(name: "Loud Arrival", icon: "flame.fill",
              colorHex: "C2451E",
              note: "Ten seconds of the Banshee, then the "
                + "posture it found, restored.",
              blocks: [
                MacroBlock(kind: "banshee",
                           config: ["mode": "Scream"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "10"]),
                MacroBlock(kind: "banshee",
                           config: ["mode": "Cease"]),
                MacroBlock(kind: "note",
                           config: ["text": "loud arrival done"]),
              ])
    }

    // MARK: The house presets (the operator's
    // order, 2026-10-18): a stocked library from
    // first launch — each one runs from a single
    // initiation, by hand or by her voice, and
    // the flagship uses nearly everything in
    // the house. The Banshee is in none of
    // them. Blocks that need a state the
    // operator must build first (a Helm remote,
    // a War Chest) are left out of the presets
    // so every one of them validates clean in
    // any house.

    static func fullNetTest() -> Macro {
        Macro(name: "Atomic Netbomb", icon: "target",
              colorHex: "C2451E",
              note: "The whole house in one run: "
                + "posture, the ear, a wire census, "
                + "the rig testing its own Serve, "
                + "the air, the war rooms. It "
                + "stands EMCON down to run and "
                + "leaves the house dark at your "
                + "standing condition; the SIGINT "
                + "watch stays open and the war "
                + "defense stays set. Everything "
                + "else it starts, it stops. "
                + "Everything but the Banshee.",
              blocks: [
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — beginning"]),
                MacroBlock(kind: "announce", config: [
                    "text": "Atomic Netbomb running — "
                        + "the house is testing itself."]),
                MacroBlock(kind: "emconOff"),
                MacroBlock(kind: "stealth",
                           config: ["on": "on"]),
                MacroBlock(kind: "listenStart",
                           config: ["label": "Atomic Netbomb"]),
                MacroBlock(kind: "waitSighting",
                           config: ["seconds": "30",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — the wire census"]),
                MacroBlock(kind: "sweep"),
                MacroBlock(kind: "knock", config: [
                    "host": "gateway",
                    "ports": "22, 80, 443, 8080"]),
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — the rig tests itself"]),
                MacroBlock(kind: "serveStart",
                           config: MacroCatalog.defaults(
                            for: "serveStart")),
                MacroBlock(kind: "knock", config: [
                    "host": "127.0.0.1",
                    "ports": "{serve}"]),
                MacroBlock(kind: "sendPayload",
                           config: ["payload": "ping",
                                    "target": "tcp://127.0.0.1:{serve}",
                                    "readReply": "on"]),
                MacroBlock(kind: "waitInbox",
                           config: ["seconds": "20",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "fuzzStart",
                           config: ["target": "tcp://127.0.0.1:{serve}",
                                    "count": "25",
                                    "length": "64",
                                    "mutations": "8"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "8"]),
                MacroBlock(kind: "fuzzStop"),
                MacroBlock(kind: "serveStop"),
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — the air"]),
                MacroBlock(kind: "costume",
                           config: ["name": "nightjar-test"]),
                MacroBlock(kind: "beaconStart",
                           config: ["text": "nightjar — atomic netbomb",
                                    "name": "nightjar-test"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "6"]),
                MacroBlock(kind: "beaconStop"),
                MacroBlock(kind: "gattStart",
                           config: ["text": "nightjar — atomic netbomb",
                                    "name": "nightjar-test"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "6"]),
                MacroBlock(kind: "gattStop"),
                MacroBlock(kind: "persona",
                           config: ["mode": "Don",
                                    "name": "Office printer"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "4"]),
                MacroBlock(kind: "persona",
                           config: ["mode": "Drop"]),
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — the war rooms"]),
                MacroBlock(kind: "warDefense",
                           config: ["doors": "{serve}",
                                    "decoys": "Printer, TV"]),
                MacroBlock(kind: "warChallenge",
                           config: ["ip": "gateway",
                                    "port": "9000",
                                    "control": "9000"]),
                MacroBlock(kind: "warRoom",
                           config: ["mode": "Start"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "20"]),
                MacroBlock(kind: "warRoom",
                           config: ["mode": "Stop"]),
                MacroBlock(kind: "assault",
                           config: ["mode": "Arm"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "30"]),
                MacroBlock(kind: "assault",
                           config: ["mode": "Disarm"]),
                MacroBlock(kind: "sigintWatch",
                           config: ["name": "Atomic Netbomb",
                                    "scope": "mixed"]),
                MacroBlock(kind: "note", config: [
                    "text": "atomic netbomb — restore"]),
                MacroBlock(kind: "listenStop"),
                MacroBlock(kind: "emconOn"),
                MacroBlock(kind: "announce", config: [
                    "text": "Atomic Netbomb complete. "
                        + "The house stands dark; the "
                        + "log holds every phase."]),
              ])
    }

    static func firstContact() -> Macro {
        Macro(name: "First Contact", icon: "globe",
              colorHex: "1E6FC2",
              note: "For a network the rig has "
                + "never met: the ear, a census "
                + "trace, a knock on the "
                + "gateway's doors, and a watch "
                + "for new faces — then the word.",
              blocks: [
                MacroBlock(kind: "note", config: [
                    "text": "first contact — census beginning"]),
                MacroBlock(kind: "listenStart",
                           config: ["label": "First contact"]),
                MacroBlock(kind: "sweep"),
                MacroBlock(kind: "knock", config: [
                    "host": "gateway",
                    "ports": "22, 80, 443, 8080, 9100"]),
                MacroBlock(kind: "waitSighting",
                           config: ["seconds": "45",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "listenStop"),
                MacroBlock(kind: "note", config: [
                    "text": "first contact — census complete"]),
                MacroBlock(kind: "announce", config: [
                    "text": "First contact census "
                        + "complete — the log holds it."]),
              ])
    }

    static func serveDrill() -> Macro {
        Macro(name: "Serve Drill",
              icon: "list.bullet",
              colorHex: "C9962E",
              note: "The rig tests its own "
                + "doors: Serve up, a knock, a "
                + "payload at itself, a short "
                + "fuzz — then everything down.",
              blocks: [
                MacroBlock(kind: "note", config: [
                    "text": "serve drill — beginning"]),
                MacroBlock(kind: "serveStart",
                           config: MacroCatalog.defaults(
                            for: "serveStart")),
                MacroBlock(kind: "knock", config: [
                    "host": "127.0.0.1",
                    "ports": "{serve}"]),
                MacroBlock(kind: "sendPayload",
                           config: ["payload": "ping",
                                    "target": "tcp://127.0.0.1:{serve}",
                                    "readReply": "on"]),
                MacroBlock(kind: "waitInbox",
                           config: ["seconds": "20",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "fuzzStart",
                           config: ["target": "tcp://127.0.0.1:{serve}",
                                    "count": "25",
                                    "length": "64",
                                    "mutations": "8"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "8"]),
                MacroBlock(kind: "fuzzStop"),
                MacroBlock(kind: "serveStop"),
                MacroBlock(kind: "note", config: [
                    "text": "serve drill — complete"]),
                MacroBlock(kind: "announce", config: [
                    "text": "Serve drill complete."]),
              ])
    }

    static func warFooting() -> Macro {
        Macro(name: "War Footing",
              icon: "shield.fill",
              colorHex: "8E1F1F",
              note: "The war rooms in one "
                + "breath: defense set, a "
                + "challenge out, the unified "
                + "run and the assault worked, "
                + "a watch opened — then the "
                + "house goes dark.",
              blocks: [
                MacroBlock(kind: "note", config: [
                    "text": "war footing — beginning"]),
                MacroBlock(kind: "emconOff"),
                MacroBlock(kind: "warDefense",
                           config: ["doors": "{serve}",
                                    "decoys": "Printer, TV"]),
                MacroBlock(kind: "warChallenge",
                           config: ["ip": "gateway",
                                    "port": "9000",
                                    "control": "9000"]),
                MacroBlock(kind: "warRoom",
                           config: ["mode": "Start"]),
                MacroBlock(kind: "assault",
                           config: ["mode": "Arm"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "45"]),
                MacroBlock(kind: "assault",
                           config: ["mode": "Disarm"]),
                MacroBlock(kind: "warRoom",
                           config: ["mode": "Stop"]),
                MacroBlock(kind: "sigintWatch",
                           config: ["name": "War footing",
                                    "scope": "mixed"]),
                MacroBlock(kind: "note", config: [
                    "text": "war footing — complete; going dark"]),
                MacroBlock(kind: "emconOn"),
                MacroBlock(kind: "announce", config: [
                    "text": "War footing worked. "
                        + "The house stands dark."]),
              ])
    }

    static func airCensus() -> Macro {
        Macro(name: "Air Census",
              icon: "antenna.radiowaves.left.and.right",
              colorHex: "6C3BD4",
              note: "What the air says, and "
                + "what the rig looks like on "
                + "it: the ear open, the "
                + "beacon and the GATT host "
                + "worn and struck, a persona "
                + "worn and dropped. The "
                + "costume name stays set.",
              blocks: [
                MacroBlock(kind: "listenStart",
                           config: ["label": "Air census"]),
                MacroBlock(kind: "costume",
                           config: ["name": "nightjar"]),
                MacroBlock(kind: "beaconStart",
                           config: ["text": "nightjar — air census",
                                    "name": "nightjar"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "6"]),
                MacroBlock(kind: "beaconStop"),
                MacroBlock(kind: "gattStart",
                           config: ["text": "nightjar — air census",
                                    "name": "nightjar"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "6"]),
                MacroBlock(kind: "gattStop"),
                MacroBlock(kind: "persona",
                           config: ["mode": "Don",
                                    "name": "Office printer"]),
                MacroBlock(kind: "wait",
                           config: ["seconds": "4"]),
                MacroBlock(kind: "persona",
                           config: ["mode": "Drop"]),
                MacroBlock(kind: "waitSighting",
                           config: ["seconds": "30",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "listenStop"),
                MacroBlock(kind: "announce", config: [
                    "text": "Air census complete."]),
              ])
    }

    static func silentPost() -> Macro {
        Macro(name: "Silent Post",
              icon: "moon.stars.fill",
              colorHex: "5A6B7A",
              note: "A post, not a test: the "
                + "house dark, stealth on, "
                + "the ear open — and it ends "
                + "standing exactly that way, "
                + "by design.",
              blocks: [
                MacroBlock(kind: "emconOn"),
                MacroBlock(kind: "stealth",
                           config: ["on": "on"]),
                MacroBlock(kind: "listenStart",
                           config: ["label": "Silent post"]),
                MacroBlock(kind: "waitSighting",
                           config: ["seconds": "120",
                                    "onTimeout": "Continue"]),
                MacroBlock(kind: "note", config: [
                    "text": "silent post standing — dark, listening"]),
                MacroBlock(kind: "announce", config: [
                    "text": "Silent post stands — "
                        + "dark, and listening."]),
              ])
    }

    static let all: [(title: String, make: () -> Macro)] = [
        ("Atomic Netbomb", fullNetTest),
        ("First Contact", firstContact),
        ("Serve Drill", serveDrill),
        ("War Footing", warFooting),
        ("Air Census", airCensus),
        ("Silent Post", silentPost),
        ("Quiet Post", quietPost),
        ("Wire Sweep", wireSweep),
        ("Loud Arrival", loudArrival),
    ]
}

// MARK: - The runner

struct MacroRunLine: Identifiable {
    let id = UUID()
    let when = Date()
    var text: String
    var mark: String   // "▶" step, "✓" done, "✗" failed, "·" note
}

/// A block that cannot run as configured. The run
/// stops on it — a playlist with a broken step does
/// not pretend the rest meant anything.
struct MacroProblem: Error {
    var message: String
}

enum MacroStepOutcome {
    case done(String)
    case endPlaylist(String)
}

final class MacroRunner: ObservableObject {
    static let shared = MacroRunner()

    @Published private(set) var running = false
    @Published private(set) var currentMacroName = ""
    @Published private(set) var currentStep = ""
    @Published private(set) var log: [MacroRunLine] = []
    @Published private(set) var lastSummary = ""

    private var task: Task<Void, Never>?
    private var boardID: UUID?
    private let bench = Recon()
    private let warBench = Recon()

    private init() {}

    var isRunning: Bool { running }

    func run(_ macro: Macro, mouth: Mouth,
             post: ListeningPost, emcon: Emcon,
             book: PayloadBook) {
        guard !running else { return }
        running = true
        currentMacroName = macro.name
        currentStep = ""
        log = []
        lastSummary = ""
        bench.mouth = mouth
        warBench.mouth = mouth
        boardID = ProcessBoard.shared.begin(
            label: String(format: L("Macro — %@"), macro.name), organ: "Macros",
            detail: String(format: L("%lld blocks"), macro.blocks.count),
            stop: { MacroRunner.shared.stop() })
        note(macro.blocks.count == 1
            ? String(format: L("▶ %@ — %lld block"),
                     macro.name, macro.blocks.count)
            : String(format: L("▶ %@ — %lld blocks"),
                     macro.name, macro.blocks.count),
            mark: "▶")
        Journal.log("macro", "run",
                    "\(macro.name) started "
                    + "(\(macro.blocks.count) blocks)")
        task = Task { [weak self] in
            await self?.execute(macro, mouth: mouth,
                                post: post, emcon: emcon,
                                book: book)
        }
    }

    /// The emergency stop's reach: a fuzz the
    /// playlist started dies here even when no
    /// run is formally in flight.
    func haltBenches() {
        bench.stopFuzz()
        warBench.stopFuzz()
    }

    func stop() {
        guard running else { return }
        task?.cancel()
        note(L("Stopped by the operator."), mark: "✗")
        Journal.log("macro", "run",
                    "\(currentMacroName) stopped by the operator")
        finish(summary: String(format: L("%@: stopped."),
                               currentMacroName))
    }

    private func finish(summary: String) {
        task = nil
        running = false
        currentStep = ""
        lastSummary = summary
        if let id = boardID {
            boardID = nil
            ProcessBoard.shared.end(
                id, summary.hasSuffix("stopped.")
                    ? .stopped : .done(summary))
        }
    }

    private func note(_ text: String, mark: String) {
        log.append(MacroRunLine(text: text, mark: mark))
    }

    @MainActor
    private func execute(_ macro: Macro, mouth: Mouth,
                         post: ListeningPost, emcon: Emcon,
                         book: PayloadBook) async {
        var completed = 0
        for (index, block) in macro.blocks.enumerated() {
            if Task.isCancelled { return }
            let spec = MacroCatalog.spec(block.kind)
            let stepLabel = String(format: L("%lld. %@ — %@"),
                                   index + 1, L(spec.title),
                                   MacroSummary.line(for: block))
            currentStep = stepLabel
            note(stepLabel, mark: "▶")
            let times = max(1, block.repeatCount)
            var ended: String?
            var failed: String?
            for rep in 0..<times {
                if Task.isCancelled { return }
                if times > 1 {
                    note(String(format: L("pass %lld of %lld"),
                                rep + 1, times), mark: "·")
                }
                do {
                    let outcome = try await perform(
                        block, mouth: mouth, post: post,
                        emcon: emcon, book: book,
                        macroName: macro.name)
                    switch outcome {
                    case .done(let verdict):
                        note(verdict, mark: "✓")
                    case .endPlaylist(let verdict):
                        note(verdict, mark: "✓")
                        ended = verdict
                    }
                } catch let problem as MacroProblem {
                    failed = problem.message
                    note(problem.message, mark: "✗")
                } catch {
                    failed = error.localizedDescription
                    note(error.localizedDescription, mark: "✗")
                }
                if ended != nil || failed != nil { break }
            }
            if let failed {
                Journal.log("macro", "run",
                            "\(macro.name) stopped at block "
                            + "\(index + 1): \(failed)")
                finish(summary: "\(macro.name): stopped at "
                       + "block \(index + 1) — \(failed)")
                return
            }
            completed += 1
            if ended != nil { break }
        }
        if Task.isCancelled { return }
        Journal.log("macro", "run",
                    "\(macro.name) finished "
                    + "(\(completed) of \(macro.blocks.count) blocks)")
        note(String(format: L("Done — %lld of %lld blocks."),
                    completed, macro.blocks.count),
             mark: "✓")
        finish(summary: String(format: L("%@: finished, %lld of %lld blocks."),
                               macro.name, completed,
                               macro.blocks.count))
    }

    // MARK: one block

    @MainActor
    private func perform(_ block: MacroBlock, mouth: Mouth,
                         post: ListeningPost, emcon: Emcon,
                         book: PayloadBook,
                         macroName: String) async throws
        -> MacroStepOutcome {
        switch block.kind {
        case "sendPayload":
            return .done(try sendPayload(block, mouth: mouth,
                                         book: book))
        case "serveStart":
            serveStart(block, mouth: mouth)
            return .done(String(format: L("Serve is up — %@."),
                                MacroSummary.line(for: block)))
        case "serveStop":
            mouth.stopServe()
            return .done(L("Serve is down."))
        case "beaconStart":
            let data = try airPayload(block, book: book)
            let name = block.value("name").isEmpty
                ? block.value("payload", block.value("text"))
                : block.value("name")
            mouth.startBeacon(payload: data, name: name)
            return .done(String(format: L("The beacon wears “%@”."),
                                name))
        case "beaconStop":
            mouth.stopBeacon()
            return .done(L("The beacon is down."))
        case "gattStart":
            let data = try airPayload(block, book: book)
            let name = block.value("name").isEmpty
                ? block.value("payload", block.value("text"))
                : block.value("name")
            mouth.startGattHost(payload: data, name: name)
            return .done(String(format: L("GATT hosting wears “%@”."),
                                name))
        case "gattStop":
            mouth.stopGattHost()
            return .done(L("GATT hosting is down."))
        case "helmFire":
            return .done(try helmFire(block, mouth: mouth,
                                      book: book))
        case "chestApply":
            return .done(try chestApply(block, mouth: mouth))
        case "emconOn":
            emcon.activate(mouth: mouth)
            return .done(L("Dark — emissions silenced, tripwire armed."))
        case "emconOff":
            emcon.deactivate()
            return .done(L("EMCON stood down."))
        case "stealth":
            mouth.setStealth(block.flag("on"))
            return .done(block.flag("on")
                ? L("Stealth on.") : L("Stealth off."))
        case "banshee":
            if block.value("mode") == "Cease" {
                BansheeCenter.shared.cease(
                    mouth: mouth, assault: AssaultCenter.shared)
                return .done(L("The banshee is silent; the posture it found is restored."))
            }
            BansheeCenter.shared.scream(
                mouth: mouth, assault: AssaultCenter.shared)
            return .done(L("The banshee screams."))
        case "costume":
            let name = block.value("name")
            guard !name.isEmpty else {
                throw MacroProblem(message: L("The costume block has no name."))
            }
            return .done(Spoofy.applyName(name, mouth: mouth))
        case "persona":
            if block.value("mode") == "Drop" {
                return .done(MimicCenter.shared.drop(
                    mouth: mouth))
            }
            guard let persona = MacroNames.persona(
                named: block.value("name")) else {
                throw MacroProblem(message: String(format: L("No persona named “%@”."),
                                                  block.value("name")))
            }
            return .done(MimicCenter.shared.don(
                persona, mouth: mouth))
        case "listenStart":
            if post.session == nil {
                post.start(label: block.value(
                    "label", "Macro watch"))
            }
            return .done(L("The ear is open."))
        case "listenStop":
            post.stop()
            return .done(L("The ear is closed."))
        case "sweep":
            try await sweep(mouth: mouth)
            return .done(L("The sweep finished."))
        case "knock":
            return .done(try await knock(block))
        case "fuzzStart":
            bench.startFuzz(
                target: resolveTarget(
                    block.value("target")), seed: nil,
                count: Int(block.number("count", 50)),
                length: Int(block.number("length", 64)),
                mutations: Int(block.number("mutations", 8)),
                seedValue: nil, read: true,
                timeout: standingReconTimeout())
            return .done(String(format: L("The fuzzer is running at %@."),
                                block.value("target")))
        case "fuzzStop":
            bench.stopFuzz()
            return .done(L("The fuzzer stood down."))
        case "assault":
            if block.value("mode") == "Disarm" {
                AssaultCenter.shared.disarm(reason: "macro")
                return .done(L("The assault stood down."))
            }
            AssaultCenter.shared.arm()
            return .done(L("The assault is armed."))
        case "warRoom":
            if block.value("mode") == "Stop" {
                WarRun.shared.stop()
                return .done(L("The War Room run stood down."))
            }
            WarRun.shared.start(
                mouth: mouth, post: post, recon: warBench,
                book: book, config: standingWarConfig())
            return .done(WarRun.shared.running
                ? L("The War Room run is up.")
                : String(format: L("The run would not start — %@"),
                         WarRun.shared.statusLine
                            ?? L("no reason given")))
        case "sigintWatch":
            let station = SigintStation.shared
            station.attach(post: post)
            station.startWatch(
                name: block.value("name", "Macro watch"),
                scope: block.value("scope", "mixed"),
                post: post)
            return .done(station.currentWatch != nil
                ? L("The watch is open.")
                : L("A watch is already running — left as it was."))
        case "warChallenge":
            let games = WarGamesCenter.shared
            games.attachForHands(mouth: mouth, post: post)
            games.challenge(
                defenderIP: resolveHost(
                    block.value("ip")),
                port: Int(block.number("port", 9000)),
                myControlPort: Int(block.number("control", 9000)),
                myLabel: Mouth.wireHostName().isEmpty
                    ? "nightjar" : Mouth.wireHostName())
            return .done(String(format: L("Challenge out to %@."),
                                block.value("ip")))
        case "warDefense":
            let games = WarGamesCenter.shared
            games.attachForHands(mouth: mouth, post: post)
            if games.role != "defender" {
                games.setRole("defender")
            }
            games.setDefense(serveDoors: warDoors(block),
                             decoys: block.value("decoys")
                                .split(separator: ",").map {
                                    $0.trimmingCharacters(
                                        in: .whitespaces)
                                }.filter { !$0.isEmpty })
            return .done(String(format: L("Defense set — %@."),
                                MacroSummary.line(for: block)))
        case "wait":
            await sleep(block.number("seconds", 10))
            return .done(String(format: L("Waited %llds."),
                                Int(block.number("seconds", 10))))
        case "waitInbox":
            return try await waitInbox(block, mouth: mouth)
        case "waitSighting":
            return try await waitSighting(block, post: post)
        case "note":
            Journal.log("macro", "note",
                        "\(macroName): \(block.value("text"))")
            return .done(L("Noted in the night log."))
        case "announce":
            announce(block.value("text"))
            return .done(L("Announced."))
        case "stop":
            return .endPlaylist(L("The playlist ends here, by its own stop block."))
        default:
            throw MacroProblem(message: String(format: L("Unknown block kind “%@”."),
                                              block.kind))
        }
    }

    // MARK: block helpers

    /// Build a payload the way the Helm does — the
    /// book item's own recipe, target-substituted.
    private func buildPayload(named name: String,
                              targetText: String,
                              book: PayloadBook) throws -> Data {
        guard let payload = book.items.first(where: {
            $0.name == name
        }) else {
            throw MacroProblem(message: String(format: L("No payload named “%@” is in the book."),
                                              name))
        }
        do {
            return try PayloadKit.build(
                source: payload.source,
                text: payload.source == "text"
                    ? PayloadKit.substitute(payload.text,
                        targetText: targetText)
                    : payload.text,
                hex: payload.source == "hex" ? payload.text : "",
                b64: payload.source == "base64"
                    ? payload.text : "",
                xorSpec: payload.xorKey,
                useGzip: payload.useGzip)
        } catch {
            throw MacroProblem(message: String(format: L("The payload would not build: %@"),
                                              error.localizedDescription))
        }
    }

    private func sendPayload(_ block: MacroBlock,
                             mouth: Mouth,
                             book: PayloadBook) throws -> String {
        let name = block.value("payload")
        let targetText = resolveTarget(
            block.value("target"))
        let data = try buildPayload(named: name,
                                    targetText: targetText,
                                    book: book)
        guard let payload = book.items.first(where: {
            $0.name == name
        }) else {
            throw MacroProblem(message: String(format: L("No payload named “%@” is in the book."),
                                              name))
        }
        if targetText.hasPrefix("phone:") {
            let phone = String(targetText.dropFirst(6))
            mouth.sendToPhone(name: phone, payload: data,
                              framing: payload.framing,
                              read: true, timeout: 5)
            return String(format: L("Sent %@ to %@."), name, phone)
        }
        let target: SendTarget
        do {
            target = try SendTarget.parse(targetText)
        } catch {
            throw MacroProblem(message: String(format: L("That target does not parse: %@"),
                                              error.localizedDescription))
        }
        switch target {
        case .http(_, _):
            mouth.sendHTTP(target: target, payload: data,
                           framing: payload.framing,
                           method: "POST", timeout: 10)
        case .tcp(_, _, _), .udp(_, _):
            mouth.sendNetwork(
                target: target, payload: data,
                framing: payload.framing,
                read: block.flag("readReply", true),
                timeout: 5)
        case .bleBeacon, .bleGatt, .bleWrite(_):
            throw MacroProblem(message: L("That target is a BLE door — a macro sends it with a beacon or GATT block instead."))
        }
        return String(format: L("Sent %@ → %@."), name, targetText)
    }

    private func airPayload(_ block: MacroBlock,
                            book: PayloadBook) throws -> Data {
        let name = block.value("payload")
        if !name.isEmpty {
            return try buildPayload(named: name,
                                    targetText: "",
                                    book: book)
        }
        let text = block.value("text")
        guard !text.isEmpty else {
            throw MacroProblem(message: L("The block needs a payload or literal text."))
        }
        return Data(text.utf8)
    }

    private func helmFire(_ block: MacroBlock, mouth: Mouth,
                          book: PayloadBook) throws -> String {
        let remotes = HelmStore.load()
        guard let remote = remotes.first(where: {
            $0.name == block.value("remote")
        }) else {
            throw MacroProblem(message: String(format: L("No remote named “%@”."),
                                              block.value("remote")))
        }
        guard let button = remote.buttons.first(where: {
            $0.label == block.value("button")
        }) else {
            throw MacroProblem(message: String(format: L("The remote has no button “%@”."),
                                              block.value("button")))
        }
        return HelmFire.fire(button, book: book, mouth: mouth)
    }

    private func chestApply(_ block: MacroBlock,
                            mouth: Mouth) throws -> String {
        guard let chest = NJChestStore.load().first(where: {
            $0.name == block.value("chest")
        }) else {
            throw MacroProblem(message: String(format: L("No chest named “%@”."),
                                              block.value("chest")))
        }
        chest.apply(mouth: mouth)
        return String(format: L("The rig wears “%@” — dressed, nothing started."),
                      chest.name)
    }

    private func serveStart(_ block: MacroBlock,
                            mouth: Mouth) {
        if block.value("mode") == "Custom doors" {
            let defaults = UserDefaults.standard
            mouth.startServe(
                tcpPort: block.flag("tcp")
                    ? Int(block.number("tcpPort", 9000)) : nil,
                udpPort: block.flag("udp")
                    ? Int(block.number("udpPort", 9001)) : nil,
                httpPort: block.flag("http")
                    ? Int(block.number("httpPort", 8080)) : nil,
                reply: defaults.string(forKey: "serveReply")
                    ?? "ack",
                framing: defaults.string(
                    forKey: "serveFraming") ?? "raw",
                echo: (defaults.string(
                    forKey: "serveReplyMode") ?? "static")
                    == "echo")
        } else {
            mouth.startServeFromSettings()
        }
        switch block.value("stealth") {
        case "On": mouth.setStealth(true)
        case "Off": mouth.setStealth(false)
        default: break
        }
    }

    @MainActor
    private func sweep(mouth: Mouth) async throws {
        guard !mouth.traceBusy else {
            throw MacroProblem(message: L("The trace is already working — a sweep waits for the wire to free."))
        }
        let config = standingWarConfig()
        mouth.startNetworkTrace(
            scopeText: config.scopeText,
            discoveryPorts: config.discoveryPorts,
            profilePorts: config.profilePorts,
            includeBonjour: config.includeBonjour,
            adaptive: config.adaptive,
            rules: TraceRule.parse(config.rulesText),
            probeFor: { _ in nil },
            payloadNamed: { _ in nil })
        while mouth.traceBusy {
            if Task.isCancelled { return }
            try? await Task.sleep(
                nanoseconds: 500_000_000)
        }
    }

    /// "gateway" (or "router"), by the house
    /// convention the forge keeps: this phone's
    /// /24, door .1 — so a preset written once
    /// knocks the right door on any network the
    /// rig joins. Anything else passes through
    /// untouched.
    private func resolveHost(_ host: String) -> String {
        MacroResolve.host(host)
    }

    private func resolveTarget(_ target: String)
        -> String {
        MacroResolve.target(target)
    }

    @MainActor
    private func knock(_ block: MacroBlock) async throws
        -> String {
        let host = resolveHost(block.value("host"))
        let ports = MacroResolve.field(
            block.value("ports"))
            .split(separator: ",").compactMap {
                Int($0.trimmingCharacters(
                    in: .whitespaces))
            }.filter { (1...65535).contains($0) }
        guard !host.isEmpty, !ports.isEmpty else {
            throw MacroProblem(message: L("The knock needs a host and at least one port."))
        }
        bench.knock(host: host, ports: ports,
                    udp: block.flag("udp"),
                    timeout: standingReconTimeout(),
                    jobs: standingReconJobs())
        while bench.knocking {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let open = bench.hits.filter { $0.isOpen }
        if open.isEmpty {
            return String(format: L("Knocked %@ — no door answered."),
                          host)
        }
        return String(format: L("Knocked %@ — answered: %@."),
                      host,
                      open.map { "\($0.port)" }
                          .joined(separator: ", "))
    }

    @MainActor
    private func waitInbox(_ block: MacroBlock,
                           mouth: Mouth) async throws
        -> MacroStepOutcome {
        // Arrivals land at the FRONT of the
        // inbox and the box caps at 200 by
        // dropping the oldest — a count can
        // stand still at the cap while the
        // wire delivers, and .last is the
        // OLDEST resident, not the arrival.
        // Watch the front door's name instead.
        let baseline = mouth.inbox.first?.id
        let deadline = Date().addingTimeInterval(
            block.number("seconds", 60))
        while Date() < deadline {
            if Task.isCancelled {
                return .done(L("The wait ended early."))
            }
            if mouth.inbox.first?.id != baseline {
                let item = mouth.inbox.first
                return .done(String(format: L("An arrival landed — %@ from %@."),
                                    item?.transport ?? "",
                                    item?.peer ?? L("the wire")))
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if block.value("onTimeout") == "Stop the playlist" {
            return .endPlaylist(L("No arrival in time — the playlist stops here, as configured."))
        }
        return .done(String(format: L("No arrival in %llds — continuing, as configured."),
                            Int(block.number("seconds", 60))))
    }

    @MainActor
    private func waitSighting(_ block: MacroBlock,
                              post: ListeningPost) async throws
        -> MacroStepOutcome {
        guard post.session != nil else {
            throw MacroProblem(message: L("The ear is not listening — a sighting wait needs a listen block (or the Listen tab) first."))
        }
        let baseline = Set(post.rows.map { $0.id })
        let match = block.value("match").lowercased()
        let deadline = Date().addingTimeInterval(
            block.number("seconds", 60))
        while Date() < deadline {
            if Task.isCancelled {
                return .done(L("The wait ended early."))
            }
            for row in post.rows where !baseline.contains(row.id) {
                let label = row.preferredLabel ?? row.name
                    ?? row.id
                if match.isEmpty
                    || label.lowercased().contains(match) {
                    return .done(String(format: L("Sighted: %@."),
                                        label))
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if block.value("onTimeout") == "Stop the playlist" {
            return .endPlaylist(L("No sighting in time — the playlist stops here, as configured."))
        }
        return .done(String(format: L("No sighting in %llds — continuing, as configured."),
                            Int(block.number("seconds", 60))))
    }

    @MainActor
    private func sleep(_ seconds: Double) async {
        var remaining = max(0, seconds)
        while remaining > 0 {
            if Task.isCancelled { return }
            let slice = min(0.25, remaining)
            try? await Task.sleep(
                nanoseconds: UInt64(slice * 1_000_000_000))
            remaining -= slice
        }
    }

    private func announce(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "nightjar-hack — macro"
        content.body = L(text)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "macro-\(UUID().uuidString)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func warDoors(_ block: MacroBlock) -> [WarDoor] {
        MacroResolve.field(block.value("doors"))
            .split(separator: ",").compactMap {
            token -> WarDoor? in
            let parts = token.split(separator: "/")
            guard let port = Int(parts[0]
                .trimmingCharacters(in: .whitespaces)),
                  (1...65535).contains(port) else { return nil }
            let proto = parts.count > 1
                ? parts[1].trimmingCharacters(
                    in: .whitespaces).lowercased()
                : "tcp"
            return WarDoor(port: port, proto: proto,
                           service: "", confirmed: false)
        }
    }

    // MARK: standing configuration (the same keys the
    // War Room's own hands read)

    private func standingWarConfig() -> WarConfig {
        let d = UserDefaults.standard
        func ports(_ text: String) -> [Int] {
            Array(Set(text.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }.filter { (1...65535).contains($0) })).sorted()
        }
        return WarConfig(
            scopeText: d.string(forKey: "traceScope") ?? "",
            discoveryPorts: ports(d.string(
                forKey: "traceDiscoveryPorts")
                ?? "80,443,22,445,1883,8080,8443,9100"),
            profilePorts: ports(d.string(
                forKey: "traceProfilePorts") ?? ""),
            includeBonjour: (d.object(forKey: "traceBonjour")
                             as? Bool) ?? true,
            adaptive: (d.object(forKey: "traceAdaptive")
                       as? Bool) ?? true,
            rulesText: d.string(forKey: "traceRules") ?? "",
            includeBLE: true,
            knockTimeout: standingReconTimeout(),
            knockJobs: standingReconJobs())
    }

    private func standingReconTimeout() -> Double {
        (UserDefaults.standard.object(forKey: "reconTimeout")
            as? Double) ?? 1.5
    }

    private func standingReconJobs() -> Int {
        Int((UserDefaults.standard.object(
            forKey: "reconJobs") as? Double) ?? 24)
    }
}
