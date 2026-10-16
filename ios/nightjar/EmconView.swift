import SwiftUI

/// EMCON tab: the device's own exposure, itemized and shut down.
/// See Emcon.swift for the engine and the honest limits.
struct EmconView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var emcon = Emcon()

    @AppStorage("emconCheckName") private var checkName = false
    @AppStorage("emconCheckAirdrop") private var checkAirdrop = false
    @AppStorage("emconCheckHotspot") private var checkHotspot = false
    @AppStorage("emconCheckWifi") private var checkWifi = false
    @AppStorage("emconCheckBluetooth") private var checkBluetooth = false

    var body: some View {
        List {
            statusSection
            emissionsSection
            selfReconSection
            tripwireSection
            hardeningSection
            Section {
                Text("EMCON cannot hide this device from the access "
                     + "point it is joined to, and Apple's own radios "
                     + "(Find My, AirDrop) answer to Settings, not to "
                     + "this app. What EMCON strips is everything that "
                     + "identifies the device — and anyone who probes "
                     + "it announces themselves to the tripwire.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { emcon.restoreIfNeeded() }
    }

    // MARK: - status

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: emcon.active
                      ? "shield.slash.fill" : "shield")
                    .font(.title)
                    .foregroundStyle(emcon.active ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(emcon.active ? "EMCON ACTIVE" : "EMCON OFF")
                        .font(.headline)
                    Text(emcon.active
                         ? "Dark. Unlisted, silent, and listening "
                           + "for probes."
                         : "This device answers the network under "
                           + "its own name.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if emcon.active {
                Button(role: .destructive) {
                    Haptics.tap()
                    emcon.deactivate()
                    toasts.show("EMCON off — tripwire stood down. "
                                + "Stealth left as it was.")
                } label: {
                    Label("Stand down EMCON", systemImage: "shield")
                }
            } else {
                Button {
                    Haptics.tap()
                    emcon.activate(mouth: mouth)
                    toasts.show("EMCON active — emissions silenced, "
                                + "tripwire armed.")
                } label: {
                    Label("Go dark", systemImage: "shield.slash")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - emissions

    private var emissionsSection: some View {
        Section(header: Text("Emissions")) {
            emissionRow("Serve listeners",
                        state: mouth.serveRunning
                            ? (mouth.stealth ? "running, unlisted"
                                             : "RUNNING, LISTED")
                            : "off",
                        bad: mouth.serveRunning && !mouth.stealth)
            emissionRow("Bonjour listing",
                        state: mouth.stealth ? "off (stealth)"
                                             : "on when serving",
                        bad: !mouth.stealth && mouth.serveRunning)
            emissionRow("BLE GATT host",
                        state: mouth.gattHostOn ? "ARMED — ADVERTISING"
                                                : "off",
                        bad: mouth.gattHostOn)
            emissionRow("BLE beacon",
                        state: mouth.beaconOn ? "ON — ADVERTISING"
                                              : "off",
                        bad: mouth.beaconOn)
            Text("Going dark forces Serve stealth, disarms the GATT "
                 + "host and stops the beacon. Coming back never "
                 + "re-opens one — re-arm each in its own tab.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emissionRow(_ name: String, state: String,
                             bad: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(state)
                .font(.callout)
                .foregroundStyle(bad ? .red : .secondary)
        }
    }

    // MARK: - self-recon

    private var selfReconSection: some View {
        Section(header: Text("Self-recon — what they see")) {
            HStack {
                Text("Broadcast name")
                Spacer()
                Text(emcon.deviceName).font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("LAN address")
                Spacer()
                Text(emcon.ownIP ?? "not on Wi-Fi").font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                emcon.runSelfScan()
            } label: {
                Label(emcon.scanning ? "Knocking…" : "Knock myself",
                      systemImage: "target")
            }
            .disabled(emcon.scanning)
            if emcon.scanning {
                ProgressView()
            } else if let at = emcon.lastScanAt {
                if emcon.exposures.isEmpty {
                    Text("Nothing answered on any probed port, on "
                         + "loopback or the LAN address. From out "
                         + "there, this device is a rumor.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(emcon.exposures) { hit in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(hit.host):\(hit.port) — "
                                 + "\(hit.service)"
                                 + (hit.confirmed ? " ★" : ""))
                                .font(.callout.weight(.semibold))
                            if !hit.banner.isEmpty {
                                Text(hit.banner)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                Text("Last scan "
                     + at.formatted(date: .omitted, time: .shortened)
                     + ". ★ = the reply carried the service's own tell.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Runs Recon's own knock against this phone — "
                     + "every registry port, loopback and LAN "
                     + "address, each port spoken to in its own "
                     + "protocol.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - tripwire

    private var tripwireSection: some View {
        Section(header: Text("Tripwire")) {
            HStack {
                Text("Listeners")
                Spacer()
                Text(emcon.tripwireOn
                     ? "\(emcon.watched.count) ports watched"
                     : "off")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !emcon.unwatched.isEmpty {
                Text("Not watched (already in use): "
                     + emcon.unwatched.map(String.init)
                        .joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if emcon.events.isEmpty {
                Text("Nobody has knocked. When someone runs these "
                     + "probes against this phone, it lands here — "
                     + "source, port, and which first words they "
                     + "used. The tripwire never replies.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(emcon.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.source) → :\(event.port)")
                            .font(.callout.weight(.semibold))
                        Text(event.verdict)
                            .font(.caption)
                        Text(event.when.formatted(
                            date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(role: .destructive) {
                    emcon.clearEvents()
                } label: {
                    Label("Clear the log", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - hardening

    private var hardeningSection: some View {
        Section(header: Text("Hardening — the OS half")) {
            checklistRow($checkName,
                         "Rename this device to something generic",
                         detail: "Settings → General → About → Name. "
                            + "Right now it broadcasts \u{201C}"
                            + "\(emcon.deviceName)\u{201D} — verify "
                            + "the change above after renaming.")
            checklistRow($checkAirdrop,
                         "AirDrop: Contacts Only or Receiving Off",
                         detail: "Settings → General → AirDrop.")
            checklistRow($checkHotspot,
                         "Personal Hotspot off",
                         detail: "Settings → Personal Hotspot — off "
                            + "unless you are deliberately sharing.")
            checklistRow($checkWifi,
                         "Wi-Fi: Ask to Join off, Auto-Join Hotspot "
                            + "never",
                         detail: "Settings → Wi-Fi — stops the phone "
                            + "shouting for known networks by name.")
            checklistRow($checkBluetooth,
                         "Bluetooth off when not in use",
                         detail: "Settings → Bluetooth. Trade-off: "
                            + "Listen needs Bluetooth on to hear "
                            + "anything — weigh it per situation.")
            Text("EMCON can verify the broadcast name and the app's "
                 + "emissions. These five live in Settings — check "
                 + "them off on your word.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func checklistRow(_ done: Binding<Bool>, _ title: String,
                              detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: done) { Text(title).font(.callout) }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
