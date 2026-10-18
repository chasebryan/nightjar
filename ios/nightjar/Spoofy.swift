import SwiftUI

// MARK: - Spoofy
//
// The costume rack: the names and shapes THIS device wears
// on the wire and in the air, kept in one place. A costume
// is a name for your own beacon and GATT host. A mimicry
// persona goes further — name, greeting, and the Serve
// dress of a class of thing (a printer, a TV, a speaker) —
// so the whole device presents as that class until you
// drop the shape and the posture it found is restored.
//
// The line, kept in the open: costumes dress this device
// in generic shapes. Its own addresses stay its own —
// nothing here copies a real device's identity, clones an
// advertisement the ear has heard, or plants a fake
// tracker. It is a wardrobe, not a forgery kit.

enum Spoofy {
    /// Name-only costumes for the beacon / GATT field.
    static let costumeNames: [String] = [
        "Office Printer — 4th Floor",
        "Living Room TV",
        "Kitchen Speaker",
        "Lobby Display",
        "Hall Thermostat",
        "Smart Fridge",
        "Guest Room Console",
        "BACKUP-NAS",
        "Robot Vacuum — Hallway",
        "Front Desk Bulb",
        "HomeNet-5G",
        "Home Gateway",
        "Mesh Node — Kitchen",
    ]

    /// The name the beacon and GATT host wear, as the
    /// Send tab's own setting holds it.
    static var currentName: String {
        UserDefaults.standard
            .string(forKey: "beaconName") ?? "nightjar-post"
    }

    /// Wear a name. The setting changes for the next start;
    /// a beacon or host live right now restarts wearing it,
    /// with the name as its greeting.
    @discardableResult
    static func applyName(_ name: String,
                          mouth: Mouth) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return "No name given." }
        UserDefaults.standard.set(clean, forKey: "beaconName")
        if mouth.beaconOn {
            mouth.stopBeacon()
            mouth.startBeacon(payload: Data(clean.utf8),
                              name: clean)
            return "The beacon already wears “\(clean)”."
        }
        if mouth.gattHostOn {
            mouth.stopGattHost()
            mouth.startGattHost(payload: Data(clean.utf8),
                                name: clean)
            return "The GATT host already wears “\(clean)”."
        }
        return "“\(clean)” is on the rack — the beacon and "
            + "the GATT host wear it from their next start."
    }

    /// A name out of the dice cup: a room, a thing, and
    /// sometimes a suffix with delusions of modelhood.
    static func diceName() -> String {
        let rooms = ["Living Room", "Kitchen", "Office",
                     "Lobby", "Front", "Back", "Guest",
                     "Main", "Upstairs", "Studio"]
        let things = ["TV", "Speaker", "Printer", "Display",
                      "Thermostat", "Fridge", "Console",
                      "Vacuum", "NAS", "Bulb", "Camera Hub",
                      "Soundbar"]
        let suffixes = ["", "", "", " 3000", " Pro", " X2",
                        " Mini", " Plus"]
        return (rooms.randomElement() ?? "Main") + " "
            + (things.randomElement() ?? "TV")
            + (suffixes.randomElement() ?? "")
    }
}

// MARK: - The operator's own rack

/// Costumes and personas the operator makes himself,
/// kept beside the built-in rack — same shelf discipline
/// as the chests and the Helm.
enum SpoofyStore {
    static let costumeKey = "spoofy.costumes.v1"
    static let personaKey = "spoofy.personas.v1"

    static func loadCostumes() -> [String] {
        guard let data = UserDefaults.standard
            .data(forKey: costumeKey),
              let names = try? JSONDecoder()
                .decode([String].self, from: data)
        else { return [] }
        return names
    }

    static func addCostume(_ name: String) {
        var names = loadCostumes()
        guard !names.contains(name),
              !Spoofy.costumeNames.contains(name)
        else { return }
        names.append(name)
        saveCostumes(names)
    }

    static func saveCostumes(_ names: [String]) {
        if let data = try? JSONEncoder()
            .encode(names) {
            UserDefaults.standard
                .set(data, forKey: costumeKey)
        }
    }

    static func loadPersonas() -> [SpoofyPersona] {
        guard let data = UserDefaults.standard
            .data(forKey: personaKey),
              let personas = try? JSONDecoder()
                .decode([SpoofyPersona].self, from: data)
        else { return [] }
        return personas
    }

    static func savePersonas(_ personas: [SpoofyPersona]) {
        if let data = try? JSONEncoder()
            .encode(personas) {
            UserDefaults.standard
                .set(data, forKey: personaKey)
        }
    }
}

// MARK: - Mimicry personas

/// A full shape: a class of device, worn across every
/// surface at once — the air name, the greeting, and the
/// Serve dress (which listeners, which ports, what they
/// answer). Classes, never a specific device.
struct SpoofyPersona: Identifiable, Codable {
    var id: String
    var label: String
    var beaconName: String
    var greeting: String
    var useTCP: Bool
    var tcpPort: Int
    var useUDP: Bool
    var udpPort: Int
    var useHTTP: Bool
    var httpPort: Int
    var reply: String
    /// Infrastructure announces itself: while a listed
    /// persona is worn, Serve stands listed (stealth off),
    /// restored whole when the shape drops.
    var listed: Bool = false

    /// The network gear — the phone dressed as the
    /// infrastructure itself. An app cannot broadcast an
    /// SSID or hold a radio AP (iOS keeps that), so the
    /// access point is worn where an app can wear it: the
    /// air name, the listeners on the wire, the replies in
    /// character, and a listed posture.
    static let gear: [SpoofyPersona] = [
        SpoofyPersona(
            id: "accesspoint", label: "Network access point",
            beaconName: "HomeNet-5G",
            greeting: "HomeNet-5G",
            useTCP: false, tcpPort: 9000,
            useUDP: false, udpPort: 9001,
            useHTTP: true, httpPort: 8080,
            reply: "AP/1.0 HomeNet-5G — clients 4, "
                + "channel 44, uptime 6d 04:12\n",
            listed: true),
        SpoofyPersona(
            id: "gateway", label: "Home gateway",
            beaconName: "Home Gateway",
            greeting: "gateway ready",
            useTCP: false, tcpPort: 9000,
            useUDP: false, udpPort: 9001,
            useHTTP: true, httpPort: 80,
            reply: "Home Gateway — status: connected, "
                + "WAN up, LAN 24 clients\n",
            listed: true),
        SpoofyPersona(
            id: "mesh", label: "Mesh Wi-Fi node",
            beaconName: "Mesh Node — Hallway",
            greeting: "Mesh node online",
            useTCP: false, tcpPort: 9000,
            useUDP: false, udpPort: 9001,
            useHTTP: true, httpPort: 8080,
            reply: "MESH/1 node — backhaul excellent, "
                + "2 clients\n",
            listed: true),
        SpoofyPersona(
            id: "mediaserver", label: "Media server",
            beaconName: "Living Room Media",
            greeting: "Media server ready",
            useTCP: true, tcpPort: 32400,
            useUDP: false, udpPort: 32401,
            useHTTP: false, httpPort: 8080,
            reply: "MediaServer/1.0 — library ready\n"),
        SpoofyPersona(
            id: "hub", label: "Smart home hub",
            beaconName: "Home Hub",
            greeting: "Home Hub ready",
            useTCP: true, tcpPort: 8081,
            useUDP: false, udpPort: 8082,
            useHTTP: false, httpPort: 8080,
            reply: "HUB/1 — 18 devices paired\n"),
    ]

    static let devices: [SpoofyPersona] = [
        SpoofyPersona(
            id: "printer", label: "Office printer",
            beaconName: "OfficeJet — 4th Floor",
            greeting: "OfficeJet ready",
            useTCP: true, tcpPort: 9100,
            useUDP: false, udpPort: 9101,
            useHTTP: false, httpPort: 8080,
            reply: "@PJL INFO STATUS\nCODE=10001\n"
                + "DISPLAY=\"Ready\"\n"),
        SpoofyPersona(
            id: "tv", label: "Smart TV",
            beaconName: "Living Room TV",
            greeting: "Living Room TV",
            useTCP: true, tcpPort: 8008,
            useUDP: false, udpPort: 1901,
            useHTTP: false, httpPort: 8080,
            reply: "TV/1.0 receiver ready\n",
            listed: true),
        SpoofyPersona(
            id: "speaker", label: "Smart speaker",
            beaconName: "Kitchen Speaker",
            greeting: "Kitchen Speaker",
            useTCP: true, tcpPort: 8009,
            useUDP: false, udpPort: 1901,
            useHTTP: false, httpPort: 8080,
            reply: "SPEAKER/1.0 ready\n"),
        SpoofyPersona(
            id: "nas", label: "NAS box",
            beaconName: "BACKUP-NAS",
            greeting: "BACKUP-NAS",
            useTCP: true, tcpPort: 5000,
            useUDP: false, udpPort: 5001,
            useHTTP: true, httpPort: 5000,
            reply: "NAS/7 storage ready\n"),
        SpoofyPersona(
            id: "thermostat", label: "Thermostat",
            beaconName: "Hall Thermostat",
            greeting: "Hall Thermostat",
            useTCP: false, tcpPort: 9000,
            useUDP: false, udpPort: 9001,
            useHTTP: true, httpPort: 8080,
            reply: "{\"temp\":72,\"mode\":\"cool\"}\n"),
        SpoofyPersona(
            id: "vacuum", label: "Robot vacuum",
            beaconName: "Robot Vacuum — Hallway",
            greeting: "Vacuum docked",
            useTCP: true, tcpPort: 8888,
            useUDP: false, udpPort: 8889,
            useHTTP: false, httpPort: 8080,
            reply: "VAC/2 docked, battery 98\n"),
    ]

    static let all: [SpoofyPersona] = gear + devices
}

/// Wearing and dropping shapes, with the same memory the
/// Banshee keeps: the dress it found is written down
/// before a persona is donned, and restored whole when
/// the shape is dropped.
final class MimicCenter: ObservableObject {
    static let shared = MimicCenter()

    @Published private(set) var activePersona: SpoofyPersona?
    @Published private(set) var wornSince: Date?

    private struct Wardrobe {
        var values: [String: Any]
        var wasServing: Bool
        var wasBeacon: Bool
        var wasGatt: Bool
        var wasStealth: Bool
        var stealthTouched: Bool
        /// The air organs' exact found state — payloads
        /// included — so a drop restores what was really
        /// flying, not a name-shaped guess at it.
        var wasBeaconPayload: Data
        var wasGattPayload: Data
        var wasAirName: String
    }

    private var wardrobe: Wardrobe?

    private static let keys = [
        "beaconName", "serveUseTCP", "serveTcpPort",
        "serveUseUDP", "serveUdpPort", "serveUseHTTP",
        "serveHttpPort", "serveReply", "serveReplyMode",
    ]

    @discardableResult
    func don(_ persona: SpoofyPersona,
             mouth: Mouth) -> String {
        if BansheeCenter.shared.screaming {
            return "Not while the banshee screams — its "
                + "own snapshot owns the posture. Cease it "
                + "first."
        }
        if activePersona != nil { drop(mouth: mouth) }
        SpoofyRotator.shared.stop()
        let defaults = UserDefaults.standard
        var values: [String: Any] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        let touchStealth = persona.listed && mouth.stealth
        wardrobe = Wardrobe(
            values: values,
            wasServing: mouth.serveRunning,
            wasBeacon: mouth.beaconOn,
            wasGatt: mouth.gattHostOn,
            wasStealth: mouth.stealth,
            stealthTouched: touchStealth,
            wasBeaconPayload: mouth.currentBeaconPayload,
            wasGattPayload: mouth.currentGattPayload,
            wasAirName: mouth.currentAirName)

        defaults.set(persona.beaconName, forKey: "beaconName")
        defaults.set(persona.useTCP, forKey: "serveUseTCP")
        defaults.set(String(persona.tcpPort),
                     forKey: "serveTcpPort")
        defaults.set(persona.useUDP, forKey: "serveUseUDP")
        defaults.set(String(persona.udpPort),
                     forKey: "serveUdpPort")
        defaults.set(persona.useHTTP, forKey: "serveUseHTTP")
        defaults.set(String(persona.httpPort),
                     forKey: "serveHttpPort")
        defaults.set(persona.reply, forKey: "serveReply")
        defaults.set("static", forKey: "serveReplyMode")

        if mouth.serveRunning {
            mouth.stopServe()
            mouth.startServeFromSettings()
        }
        if touchStealth {
            // In character, the shape announces itself.
            mouth.setStealth(false)
        }
        wear(persona.beaconName,
             greeting: persona.greeting, mouth: mouth)
        activePersona = persona
        wornSince = Date()
        Journal.log("spoofy", "mimicry",
                    "wearing the \(persona.label) — "
                    + "“\(persona.beaconName)”")
        let live = mouth.serveRunning || mouth.beaconOn
            || mouth.gattHostOn
        return live
            ? "Wearing the \(persona.label) — live now, "
            + "in character on every surface it owns."
            : "Wearing the \(persona.label) — the dress "
            + "is set; it goes live when Serve or the "
            + "air organs next start."
    }

    @discardableResult
    func drop(mouth: Mouth) -> String {
        guard let persona = activePersona else {
            return "No shape is being worn."
        }
        let defaults = UserDefaults.standard
        if let wardrobe = wardrobe {
            for key in Self.keys {
                if let value = wardrobe.values[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            if mouth.serveRunning {
                mouth.stopServe()
                mouth.startServeFromSettings()
            }
            if wardrobe.stealthTouched {
                mouth.setStealth(wardrobe.wasStealth)
            }
            if wardrobe.wasBeacon, mouth.beaconOn {
                mouth.stopBeacon()
                mouth.startBeacon(
                    payload: wardrobe.wasBeaconPayload,
                    name: wardrobe.wasAirName)
            }
            if wardrobe.wasGatt, mouth.gattHostOn {
                mouth.stopGattHost()
                mouth.startGattHost(
                    payload: wardrobe.wasGattPayload,
                    name: wardrobe.wasAirName)
            }
        }
        wardrobe = nil
        activePersona = nil
        wornSince = nil
        Journal.log("spoofy", "mimicry",
                    "dropped the \(persona.label) — the "
                    + "wardrobe it found is restored")
        return "Shape dropped — the wardrobe it found is "
            + "restored whole: settings, stealth, and the "
            + "exact payloads the air was carrying."
    }

    /// Restart whichever air organ is live, wearing the
    /// shape's name and greeting.
    private func wear(_ name: String, greeting: String,
                      mouth: Mouth) {
        if mouth.beaconOn {
            mouth.stopBeacon()
            mouth.startBeacon(payload: Data(greeting.utf8),
                              name: name)
        } else if mouth.gattHostOn {
            mouth.stopGattHost()
            mouth.startGattHost(payload: Data(greeting.utf8),
                                name: name)
        }
    }
}

// MARK: - The rotator

/// The rack, revolving: while rotation runs, the air
/// name steps through the rack — built-ins and the
/// operator's own — on an interval. It turns only this
/// device's own name, the way the system itself rotates
/// its radio address; it steps aside while a persona is
/// worn, and stops when one is donned.
final class SpoofyRotator: ObservableObject {
    static let shared = SpoofyRotator()

    @Published private(set) var rotating = false
    @Published var minutes: Int = 15

    private var timer: Timer?
    private var names: [String] = []
    private var index = 0

    @discardableResult
    func start(mouth: Mouth) -> String {
        names = Spoofy.costumeNames
            + SpoofyStore.loadCostumes()
        guard names.count > 1 else {
            return "The rack needs more than one name "
                + "to rotate."
        }
        stop()
        if let current = names.firstIndex(
            of: Spoofy.currentName) {
            index = current
        }
        rotating = true
        timer = Timer.scheduledTimer(
            withTimeInterval: Double(minutes * 60),
            repeats: true) { [weak self] _ in
            self?.advance(mouth: mouth)
        }
        Journal.log("spoofy", "rotation",
                    "the rack revolves — a new name every "
                    + "\(minutes) minutes")
        return "The rack revolves: a new name every "
            + "\(minutes) minutes, through \(names.count) "
            + "costumes."
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if rotating {
            rotating = false
            Journal.log("spoofy", "rotation",
                        "the rack stands still")
        }
    }

    private func advance(mouth: Mouth) {
        guard MimicCenter.shared.activePersona == nil
        else { return }
        index = (index + 1) % names.count
        Spoofy.applyName(names[index], mouth: mouth)
    }
}

// MARK: - The rack itself

struct SpoofyView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var mimic = MimicCenter.shared
    @ObservedObject private var rotator = SpoofyRotator.shared
    @State private var customName = ""
    @State private var myCostumes: [String] = []
    @State private var myPersonas: [SpoofyPersona] = []
    @State private var showEditor = false

    private var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0
        else { return "—" }
        let raw = String(cString: buffer)
        return raw.split(separator: ".").first.map(String.init)
            ?? raw
    }

    var body: some View {
        NavigationStack {
            List {
                Section("The mirror — what the wire calls you") {
                    LabeledContent("On the wire",
                                   value: hostName + ".local")
                    LabeledContent("In the air",
                                   value: Spoofy.currentName)
                    LabeledContent("Beacon",
                                   value: mouth.beaconOn
                                    ? "live" : "off")
                    LabeledContent("GATT host",
                                   value: mouth.gattHostOn
                                    ? "live" : "off")
                    LabeledContent("Serve",
                                   value: mouth.serveRunning
                                    ? (mouth.stealth
                                       ? "up, stealthed"
                                       : "up, listed")
                                    : "down")
                    if let persona = mimic.activePersona {
                        Label("Wearing the \(persona.label)",
                              systemImage: "theatermasks.fill")
                            .foregroundStyle(.purple)
                        if let since = mimic.wornSince {
                            LabeledContent(
                                "Worn since",
                                value: since.formatted(
                                    date: .omitted,
                                    time: .shortened))
                        }
                    }
                    if rotator.rotating {
                        LabeledContent(
                            "Name rotation",
                            value: "every "
                                + "\(rotator.minutes) min")
                    }
                }

                Section("Costumes — a name for the air") {
                    ForEach(Spoofy.costumeNames
                        + myCostumes, id: \.self) {
                        name in
                        Button {
                            Haptics.select()
                            toasts.show(Spoofy.applyName(
                                name, mouth: mouth))
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if Spoofy.currentName == name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        // Only the operator's own rows delete;
                        // built-ins sit before them.
                        let mine = offsets.map {
                            $0 - Spoofy.costumeNames.count
                        }.filter {
                            myCostumes.indices.contains($0)
                        }
                        guard !mine.isEmpty else { return }
                        myCostumes = myCostumes.enumerated()
                            .filter { !mine.contains($0.offset) }
                            .map { $0.element }
                        SpoofyStore.saveCostumes(myCostumes)
                    }
                    HStack {
                        TextField("Your own costume name",
                                  text: $customName)
                            .autocorrectionDisabled()
                        Button("Wear") {
                            Haptics.tap()
                            let name = customName
                                .trimmingCharacters(
                                    in: .whitespaces)
                            toasts.show(Spoofy.applyName(
                                name, mouth: mouth)
                                + " Kept on your rack.")
                            SpoofyStore.addCostume(name)
                            myCostumes =
                                SpoofyStore.loadCostumes()
                            customName = ""
                        }
                        .disabled(customName.trimmingCharacters(
                            in: .whitespaces).isEmpty)
                    }
                    Button {
                        Haptics.tap()
                        let name = Spoofy.diceName()
                        toasts.show(Spoofy.applyName(
                            name, mouth: mouth))
                    } label: {
                        Label("Roll the dice",
                              systemImage: "die.face.5")
                    }
                    Text("A costume sets the name the beacon "
                        + "and the GATT host wear. Live organs "
                        + "restart wearing it, with the name "
                        + "as their greeting. A name you type "
                        + "is kept on your own rack — swipe "
                        + "it away to clear it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("The revolving rack") {
                    Picker("A new name every",
                           selection: $rotator.minutes) {
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .disabled(rotator.rotating)
                    if rotator.rotating {
                        Button("Stop the rotation",
                               role: .destructive) {
                            Haptics.tap()
                            rotator.stop()
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Button {
                            Haptics.tap()
                            toasts.show(rotator.start(
                                mouth: mouth))
                        } label: {
                            Label("Start rotating names",
                                  systemImage:
                                    "arrow.triangle.2.circlepath")
                        }
                    }
                    Text("Rotation turns only this device's "
                        + "own air name, stepping through "
                        + "the rack. It stands aside while "
                        + "a persona is worn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Mimicry — network gear") {
                    if let persona = mimic.activePersona {
                        HStack {
                            Label("Wearing the \(persona.label)",
                                  systemImage: "theatermasks.fill")
                                .foregroundStyle(.purple)
                            Spacer()
                            Button("Drop the shape",
                                   role: .destructive) {
                                Haptics.tap()
                                toasts.show(mimic.drop(
                                    mouth: mouth))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    ForEach(SpoofyPersona.gear) { persona in
                        personaRow(persona)
                    }
                    Text("The network gear is worn where an "
                        + "app can wear it — the air name, "
                        + "the listeners, the replies, a "
                        + "listed posture. iOS lets no app "
                        + "broadcast an SSID, so there is no "
                        + "fake radio here: the access point "
                        + "is a shape on the wire, not a "
                        + "transmitter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Mimicry — wear a class whole") {
                    ForEach(SpoofyPersona.devices) { persona in
                        personaRow(persona)
                    }
                    Text("A persona dresses the whole device "
                        + "as a class of thing: the air name, "
                        + "the greeting, and Serve's listeners "
                        + "and replies, all in character. "
                        + "Dropping the shape restores the "
                        + "dress it found — ports, replies, "
                        + "name and all.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Mimicry — your own shapes") {
                    ForEach(myPersonas) { persona in
                        personaRow(persona)
                    }
                    .onDelete { offsets in
                        myPersonas = myPersonas.enumerated()
                            .filter {
                                !offsets.contains($0.offset)
                            }
                            .map { $0.element }
                        SpoofyStore.savePersonas(myPersonas)
                    }
                    Button {
                        Haptics.tap()
                        showEditor = true
                    } label: {
                        Label("Build a shape",
                              systemImage: "plus.circle")
                    }
                    Text("Your own personas, built from the "
                        + "same cloth as the rack's: a name, "
                        + "a greeting, Serve's dress, and "
                        + "whether the shape stands listed. "
                        + "Swipe one away to clear it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("Costumes dress this device in "
                        + "generic shapes; its own addresses "
                        + "stay its own. Nothing here copies a "
                        + "real device's identity, clones an "
                        + "advertisement the ear has heard, or "
                        + "plants a fake tracker — a wardrobe, "
                        + "not a forgery kit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Spoofy")
            .onAppear {
                myCostumes = SpoofyStore.loadCostumes()
                myPersonas = SpoofyStore.loadPersonas()
            }
            .sheet(isPresented: $showEditor) {
                SpoofyPersonaEditor {
                    myPersonas = SpoofyStore.loadPersonas()
                }
            }
        }
    }

    @ViewBuilder
    private func personaRow(_ persona: SpoofyPersona)
        -> some View {
        Button {
            Haptics.tap()
            toasts.show(mimic.don(persona, mouth: mouth))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.label)
                    .font(.callout)
                Text("“\(persona.beaconName)” · "
                    + serveDress(persona))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .disabled(mimic.activePersona?.id == persona.id)
    }

    private func serveDress(_ persona: SpoofyPersona) -> String {
        var parts: [String] = []
        if persona.useTCP { parts.append("TCP \(persona.tcpPort)") }
        if persona.useUDP { parts.append("UDP \(persona.udpPort)") }
        if persona.useHTTP {
            parts.append("HTTP \(persona.httpPort)")
        }
        var dress = parts.isEmpty ? "air only"
            : "serves " + parts.joined(separator: " · ")
        if persona.listed { dress += " · listed" }
        return dress
    }
}

// MARK: - Building a shape

/// The persona workshop: every field of a shape, from
/// the same cloth as the built-in rack — nothing a
/// built-in persona wears is beyond the operator's own.
struct SpoofyPersonaEditor: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: () -> Void

    @State private var label = ""
    @State private var beaconName = ""
    @State private var greeting = ""
    @State private var useTCP = true
    @State private var tcpPort = "9000"
    @State private var useUDP = false
    @State private var udpPort = "9001"
    @State private var useHTTP = false
    @State private var httpPort = "8080"
    @State private var reply = ""
    @State private var listed = false

    private func port(_ text: String,
                      fallback: Int) -> Int {
        guard let value = Int(text),
              (1...65535).contains(value)
        else { return fallback }
        return value
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && !beaconName.trimmingCharacters(
                in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The shape") {
                    TextField("Label — “Workshop radio”",
                              text: $label)
                    TextField("Air name — what it answers to",
                              text: $beaconName)
                        .autocorrectionDisabled()
                    TextField("Greeting — the air payload",
                              text: $greeting)
                    Toggle("Stands listed (stealth off "
                        + "while worn)", isOn: $listed)
                }
                Section("Serve's dress") {
                    Toggle("TCP listener", isOn: $useTCP)
                    if useTCP {
                        TextField("TCP port", text: $tcpPort)
                            .keyboardType(.numberPad)
                    }
                    Toggle("UDP listener", isOn: $useUDP)
                    if useUDP {
                        TextField("UDP port", text: $udpPort)
                            .keyboardType(.numberPad)
                    }
                    Toggle("HTTP listener", isOn: $useHTTP)
                    if useHTTP {
                        TextField("HTTP port", text: $httpPort)
                            .keyboardType(.numberPad)
                    }
                    TextField("What the listeners answer",
                              text: $reply)
                }
                Section {
                    Text("A shape is a class, never a "
                        + "specific device — the rack's "
                        + "line holds for your own cloth "
                        + "too.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Build a shape")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") {
                        let persona = SpoofyPersona(
                            id: "custom-"
                                + UUID().uuidString
                                    .prefix(8).lowercased(),
                            label: label.trimmingCharacters(
                                in: .whitespaces),
                            beaconName: beaconName
                                .trimmingCharacters(
                                    in: .whitespaces),
                            greeting: greeting.isEmpty
                                ? beaconName : greeting,
                            useTCP: useTCP,
                            tcpPort: port(tcpPort,
                                          fallback: 9000),
                            useUDP: useUDP,
                            udpPort: port(udpPort,
                                          fallback: 9001),
                            useHTTP: useHTTP,
                            httpPort: port(httpPort,
                                           fallback: 8080),
                            reply: reply.isEmpty
                                ? "ready\n" : reply,
                            listed: listed)
                        var personas =
                            SpoofyStore.loadPersonas()
                        personas.append(persona)
                        SpoofyStore.savePersonas(personas)
                        onSave()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
