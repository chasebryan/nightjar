import SwiftUI

// MARK: - The Banshee
//
// The opposite pole of this whole tab. EMCON exists to make
// this device a ghost; the Banshee exists to make it scream:
// every self-announcement the app owns, up at once, at full
// voice — Serve listed and named on the wire, the BLE beacon
// shouting BANSHEE into the room, Net-Assault announcing
// itself pass after pass, and a broadcast heartbeat calling
// the device's own name across the subnet, so any admin
// watching any part of the network meets this phone in
// seconds.
//
// It is a flare, not a weapon: everything here is this
// device announcing ITSELF. It touches no one else's
// traffic, silences nothing, spoofs nothing. And it keeps
// a memory: cease, and the posture it found — serve state,
// stealth, beacon, assault — is restored exactly.

final class BansheeCenter: ObservableObject {
    /// One banshee for the house — the EMCON tab and
    /// Skelli's hands raise and cease the same scream.
    static let shared = BansheeCenter()

    @Published private(set) var screaming = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var shoutsSent = 0

    @AppStorage("serveUdpPort") private var serveUdpPort = "9001"

    private struct Snapshot {
        var serve: Bool
        var stealth: Bool
        var beacon: Bool
        var gatt: Bool
        var assault: Bool
    }

    private var snapshot: Snapshot?
    private var timer: Timer?

    var shoutPort: Int { Int(serveUdpPort) ?? 9001 }

    /// The name this device answers to — the name the
    /// shout carries.
    private var hostName: String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard gethostname(&buffer, buffer.count) == 0
        else { return "this phone" }
        let raw = String(cString: buffer)
        return raw.split(separator: ".").first.map(String.init)
            ?? "this phone"
    }

    // MARK: scream / cease

    func scream(mouth: Mouth, assault: AssaultCenter) {
        guard !screaming else { return }
        mouthRef = mouth
        snapshot = Snapshot(serve: mouth.serveRunning,
                            stealth: mouth.stealth,
                            beacon: mouth.beaconOn,
                            gatt: mouth.gattHostOn,
                            assault: assault.running)

        // Be listed, be named: stealth is the first thing
        // a scream cannot afford.
        if mouth.stealth { mouth.setStealth(false) }
        if !mouth.serveRunning { mouth.startServeFromSettings() }

        // The air: the beacon shouts unless the GATT arm
        // already holds the channel — one BLE voice, full
        // volume either way.
        if !mouth.gattHostOn, !mouth.beaconOn {
            let text = "BANSHEE — \(hostName) — this device "
                + "announces itself at full voice"
            mouth.startBeacon(payload: Data(text.utf8),
                              name: "BANSHEE")
        }

        // The loud organ itself: announce, census, knock,
        // pass after pass.
        if !assault.running { assault.arm() }

        screaming = true
        startedAt = Date()
        shoutsSent = 0
        shout(mouth: mouth)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4,
                                     repeats: true) { [weak self] _ in
            guard let self = self, let mouth = self.mouthRef
            else { return }
            self.shout(mouth: mouth)
        }
        Journal.log("banshee", "scream",
                    "the banshee screams — serve listed, "
                    + "stealth off, beacon up, net-assault "
                    + "armed, broadcast heartbeat on "
                    + "\(shoutPort)")
    }

    func cease(mouth: Mouth, assault: AssaultCenter) {
        guard screaming else { return }
        timer?.invalidate()
        timer = nil
        mouthRef = nil
        if let snap = snapshot {
            if !snap.assault, assault.running {
                assault.disarm(
                    reason: "the banshee ceased")
            }
            if !snap.beacon, mouth.beaconOn {
                mouth.stopBeacon()
            }
            if !snap.serve, mouth.serveRunning {
                mouth.stopServe()
            }
            // The setting returns last, so a Serve that was
            // running stealthed before the scream ends the
            // cease stealthed again.
            if snap.stealth != mouth.stealth {
                mouth.setStealth(snap.stealth)
            }
        }
        snapshot = nil
        screaming = false
        startedAt = nil
        Journal.log("banshee", "cease",
                    "the banshee is silent — the posture it "
                    + "found is restored")
    }

    private weak var mouthRef: Mouth?

    // MARK: the broadcast heartbeat

    /// One shout: a named datagram to the whole subnet —
    /// the limited broadcast and the subnet-directed
    /// broadcast both — carrying nothing but this device's
    /// own name and address. A heartbeat, not a flood:
    /// one pair of packets every four seconds.
    private func shout(mouth: Mouth) {
        let ip = Mouth.localIPAddress() ?? ""
        let text = "BANSHEE \(hostName) \(ip) nightjar-hack — "
            + "this device announces itself"
        let payload = Data(text.utf8)
        var targets = ["255.255.255.255"]
        if let base = Mouth.sweepBase("", ownIP: ip) {
            targets.append(base + ".255")
        }
        for host in targets {
            mouth.sendNetwork(
                target: .udp(host: host, port: shoutPort),
                payload: payload,
                framing: "raw", read: false, timeout: 2)
        }
        shoutsSent += 1
    }
}

// MARK: - The banshee's room

struct BansheeView: View {
    @EnvironmentObject private var mouth: Mouth
    @ObservedObject var assault: AssaultCenter
    @ObservedObject var banshee: BansheeCenter
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main,
                                      in: .common).autoconnect()

    private var elapsed: String {
        guard let start = banshee.startedAt else { return "" }
        let secs = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: banshee.screaming
                              ? "speaker.wave.3.fill"
                              : "speaker.slash")
                            .font(.largeTitle)
                            .foregroundStyle(banshee.screaming
                                             ? .red : .secondary)
                        Text(banshee.screaming
                             ? "SCREAMING — \(elapsed)"
                             : "Silent")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(banshee.screaming
                                             ? .red : .primary)
                        Text("Every measure this app owns, "
                            + "announcing this one device at "
                            + "once. Nothing here touches "
                            + "anyone else's traffic.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("The measures") {
                    measure("Serve, listed by name",
                            on: mouth.serveRunning
                                && !mouth.stealth,
                            detail: mouth.serveRunning
                                ? (mouth.stealth
                                   ? "running, but stealthed"
                                   : "up and answering to "
                                    + "the wire")
                                : "down")
                    measure("BLE beacon — “BANSHEE”",
                            on: mouth.beaconOn,
                            detail: mouth.gattHostOn
                                ? "the GATT arm holds the air "
                                    + "instead — one voice, "
                                    + "full volume"
                                : (mouth.beaconOn
                                   ? "shouting into the room"
                                   : "quiet"))
                    measure("Net-Assault, armed",
                            on: assault.running,
                            detail: assault.running
                                ? "\(assault.phase) · pass "
                                    + "\(assault.passes)"
                                : "holstered")
                    measure("Broadcast heartbeat",
                            on: banshee.screaming,
                            detail: banshee.screaming
                                ? "\(banshee.shoutsSent) shout(s) "
                                    + "· UDP \(banshee.shoutPort), "
                                    + "subnet-wide"
                                : "still")
                }

                Section {
                    Text("This is meant to be noticed — by "
                        + "every admin measure on the network: "
                        + "the DHCP and flow logs, the "
                        + "controller's client list, anything "
                        + "watching broadcasts. On a network "
                        + "you do not own, expect exactly the "
                        + "attention it asks for.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Section {
                    if banshee.screaming {
                        Button(role: .destructive) {
                            Haptics.tap()
                            banshee.cease(mouth: mouth,
                                           assault: assault)
                        } label: {
                            Label("Cease — restore what was",
                                  systemImage: "speaker.slash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Haptics.tap()
                            banshee.scream(mouth: mouth,
                                            assault: assault)
                        } label: {
                            Label("SCREAM",
                                  systemImage: "speaker.wave.3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    Text("Ceasing restores the posture the "
                        + "scream found: Serve as it was, "
                        + "stealth as it was, the beacon and "
                        + "Net-Assault stood down unless they "
                        + "were already up on their own.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("The Banshee")
            .onReceive(clock) { now = $0 }
        }
    }

    private func measure(_ label: String, on: Bool,
                         detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on ? "circle.fill" : "circle")
                .foregroundStyle(on ? .red : .secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
