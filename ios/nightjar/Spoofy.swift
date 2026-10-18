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

// MARK: - Mimicry personas

/// A full shape: a class of device, worn across every
/// surface at once — the air name, the greeting, and the
/// Serve dress (which listeners, which ports, what they
/// answer). Classes, never a specific device.
struct SpoofyPersona: Identifiable {
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

    private struct Wardrobe {
        var values: [String: Any]
        var wasServing: Bool
        var wasBeacon: Bool
        var wasGatt: Bool
        var wasStealth: Bool
        var stealthTouched: Bool
    }

    private var wardrobe: Wardrobe?

    private static let keys = [
        "beaconName", "serveUseTCP", "serveTcpPort",
        "serveUseUDP", "serveUdpPort", "serveUseHTTP",
        "serveHttpPort", "serveReply", "serveReplyMode",
    ]

    func don(_ persona: SpoofyPersona, mouth: Mouth) {
        if activePersona != nil { drop(mouth: mouth) }
        let defaults = UserDefaults.standard
        var values: [String: Any] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                values[key] = value
            }
        }
        let touchStealth = persona.listed && mouth.stealth
        wardrobe = Wardrobe(values: values,
                            wasServing: mouth.serveRunning,
                            wasBeacon: mouth.beaconOn,
                            wasGatt: mouth.gattHostOn,
                            wasStealth: mouth.stealth,
                            stealthTouched: touchStealth)

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
        Journal.log("spoofy", "mimicry",
                    "wearing the \(persona.label) — "
                    + "“\(persona.beaconName)”")
    }

    func drop(mouth: Mouth) {
        guard let persona = activePersona else { return }
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
            let name = defaults.string(forKey: "beaconName")
                ?? "nightjar-post"
            if wardrobe.wasBeacon, mouth.beaconOn {
                mouth.stopBeacon()
                mouth.startBeacon(payload: Data(name.utf8),
                                  name: name)
            }
            if wardrobe.wasGatt, mouth.gattHostOn {
                mouth.stopGattHost()
                mouth.startGattHost(payload: Data(name.utf8),
                                    name: name)
            }
        }
        wardrobe = nil
        activePersona = nil
        Journal.log("spoofy", "mimicry",
                    "dropped the \(persona.label) — the "
                    + "wardrobe it found is restored")
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

// MARK: - The rack itself

struct SpoofyView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @ObservedObject private var mimic = MimicCenter.shared
    @State private var customName = ""

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
                    }
                }

                Section("Costumes — a name for the air") {
                    ForEach(Spoofy.costumeNames, id: \.self) {
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
                    HStack {
                        TextField("Your own costume name",
                                  text: $customName)
                            .autocorrectionDisabled()
                        Button("Wear") {
                            Haptics.tap()
                            toasts.show(Spoofy.applyName(
                                customName, mouth: mouth))
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
                        + "as their greeting.")
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
                                mimic.drop(mouth: mouth)
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
        }
    }

    @ViewBuilder
    private func personaRow(_ persona: SpoofyPersona)
        -> some View {
        Button {
            Haptics.tap()
            mimic.don(persona, mouth: mouth)
            toasts.show("Wearing the " + persona.label)
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
