import SwiftUI

/// EMCON tab: the device's own exposure — scored, itemized, and
/// shut down. See Emcon.swift for the engine and the honest limits.
struct EmconView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @StateObject private var emcon = Emcon()

    @AppStorage("emconCheckName") private var checkName = false
    @AppStorage("emconCheckAirdrop") private var checkAirdrop = false
    @AppStorage("emconCheckHotspot") private var checkHotspot = false
    @AppStorage("emconCheckWifi") private var checkWifi = false
    @AppStorage("emconCheckBluetooth") private var checkBluetooth = false

    private var score: Emcon.Score {
        Emcon.score(gattHostOn: mouth.gattHostOn,
                    beaconOn: mouth.beaconOn,
                    serveRunning: mouth.serveRunning,
                    stealth: mouth.stealth,
                    deviceName: emcon.deviceName,
                    exposureCount: emcon.exposures.count,
                    announcerCount: emcon.announcers.count)
    }

    var body: some View {
        List {
            statusSection
            drillSection
            emissionsSection
            selfReconSection
            auditSection
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

    // MARK: - status + score

    private var statusSection: some View {
        Section {
            HStack(spacing: 14) {
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
                Spacer()
                VStack(spacing: 0) {
                    Text("\(score.value)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(scoreColor)
                    Text(score.band)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(scoreColor)
                }
            }
            Text("Exposure score — live emissions weigh most, then "
                 + "what the last knock and audit actually found. "
                 + "Run the drill for the full picture.")
                .font(.caption).foregroundStyle(.secondary)
            if !score.parts.isEmpty {
                Text("Why \(score.band):")
                    .font(.caption.weight(.semibold))
                ForEach(score.parts) { part in
                    HStack {
                        Text(part.label).font(.caption)
                        Spacer()
                        Text("+\(part.points)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(scoreColor)
                    }
                }
                if score.capped {
                    Text("Parts sum past 100 — the score stops there.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if emcon.isAway, !emcon.active {
                Label("Off home turf — this network is not your "
                      + "marked home. Going dark is advised.",
                      systemImage: "exclamationmark.shield")
                    .font(.callout).foregroundStyle(.orange)
                Button {
                    Haptics.tap()
                    goDark()
                } label: {
                    Label("Go dark now", systemImage: "shield.slash")
                }
                .buttonStyle(.borderedProminent)
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
            } else if !emcon.isAway {
                Button {
                    Haptics.tap()
                    goDark()
                } label: {
                    Label("Go dark", systemImage: "shield.slash")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func goDark() {
        emcon.activate(mouth: mouth)
        toasts.show("EMCON active — emissions silenced, "
                    + "tripwire armed.")
    }

    private var scoreColor: Color {
        switch score.value {
        case 0: return .green
        case 1...15: return .mint
        case 16...40: return .yellow
        case 41...70: return .orange
        default: return .red
        }
    }

    // MARK: - the drill

    private var drillSection: some View {
        Section(header: Text("The drill")) {
            Button {
                Haptics.tap()
                emcon.runDrill(mouth: mouth)
            } label: {
                Label(emcon.drilling
                      ? "Running the drill…"
                      : "Prove it — scan, go dark, scan again",
                      systemImage: "checklist")
            }
            .disabled(emcon.drilling || emcon.scanning || emcon.auditing)
            if emcon.drilling {
                ProgressView()
            } else if let before = emcon.drillBefore,
                      let after = emcon.drillAfter {
                let gone = Emcon.silenced(before: before, after: after)
                let still = Emcon.stillShowing(after)
                if gone.isEmpty, still.isEmpty {
                    Text("Before and after agree: nothing was "
                         + "exposed in the first place.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    if !gone.isEmpty {
                        Text("Silenced by going dark:")
                            .font(.callout.weight(.semibold))
                        ForEach(Array(gone.enumerated()), id: \.offset) { item in
                            Text("— \(item.element)").font(.callout)
                        }
                    } else if !still.isEmpty {
                        Text("Nothing went quiet.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if still.isEmpty {
                        Text("Nothing survived the drill. The second "
                             + "scan found a clean device.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text("Still showing:")
                            .font(.callout.weight(.semibold))
                        ForEach(Array(still.enumerated()), id: \.offset) { item in
                            Text("— \(item.element)").font(.callout)
                        }
                        Text("These are real listeners on the device "
                             + "that EMCON does not own — the OS, other "
                             + "apps, or Serve ports kept under stealth. "
                             + "The hardening list below is where the "
                             + "OS ones die.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("One tap: full knock and Bonjour audit, then "
                     + "EMCON engages, then both run again and the "
                     + "difference is read out here.")
                    .font(.caption).foregroundStyle(.secondary)
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
            .disabled(emcon.scanning || emcon.drilling)
            if emcon.scanning {
                ProgressView()
            } else if emcon.lastScanAt != nil {
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
                Text("★ = the reply carried the service's own tell.")
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

    // MARK: - Bonjour audit

    private var auditSection: some View {
        Section(header: Text("Announcements — Bonjour audit")) {
            Button {
                Haptics.tap()
                emcon.runBonjourAudit()
            } label: {
                Label(emcon.auditing
                      ? "Listening…"
                      : "Audit what this device announces",
                      systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(emcon.auditing || emcon.drilling)
            if emcon.auditing {
                ProgressView()
            } else if emcon.lastAuditAt != nil {
                if emcon.announcers.isEmpty {
                    Text("Heard \(emcon.heardCount) announcement(s) "
                         + "on this network — none of them is this "
                         + "device. mDNS has nothing of yours.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(emcon.announcers) { ad in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(ad.label) — \(ad.name)")
                                .font(.callout.weight(.semibold))
                            Text(ad.why + " · \(ad.type)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("These are the OS's own megaphones — "
                         + "AirPlay and friends. EMCON can't switch "
                         + "them off; the hardening list is where "
                         + "they die (name, AirDrop).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Browses the LAN the way the Scan tab does and "
                     + "flags every announcement that is this "
                     + "device — by name, or by resolving to this "
                     + "phone's address.")
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
                     ? "\(emcon.watched.count) TCP + "
                       + "\(emcon.watchedUDP.count) UDP watched"
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
                     + "used. The log persists across launches. The "
                     + "tripwire never replies.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(emcon.events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(event.source) → \(event.proto)"
                             + "/\(event.port)"
                             + (event.repeatCount > 1
                                ? " ×\(event.repeatCount)" : ""))
                            .font(.callout.weight(.semibold))
                        Text(event.verdict)
                            .font(.caption)
                        Text(event.when.formatted(
                            date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ShareLink(item: Emcon.tripwireReportURL) {
                    Label("Share the log",
                          systemImage: "square.and.arrow.up")
                }
                Text("Readable text. The same log is kept as JSON "
                     + "in Documents. The tripwire never replies.")
                    .font(.caption).foregroundStyle(.secondary)
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
            HStack {
                Text("This network")
                Spacer()
                Text(emcon.currentSubnet.map { "\($0).0/24" }
                     ?? "not on Wi-Fi")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text("Home turf")
                Spacer()
                Text(emcon.homeSubnet.map { "\($0).0/24" } ?? "unmarked")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if emcon.currentSubnet != nil,
               emcon.currentSubnet != emcon.homeSubnet {
                Button {
                    Haptics.tap()
                    emcon.markHome()
                    toasts.show("Marked — EMCON will warn you off "
                                + "home turf.")
                } label: {
                    Label("Mark this network as home",
                          systemImage: "house")
                }
            }
            if emcon.homeSubnet != nil {
                Button(role: .destructive) {
                    Haptics.tap()
                    emcon.unmarkHome()
                    toasts.show("Home turf unmarked.")
                } label: {
                    Label("Unmark home", systemImage: "house.slash")
                }
            }
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
