import SwiftUI

/// EMCON tab: the device's own exposure — scored, itemized, and
/// shut down. See Emcon.swift for the engine and the honest limits.
struct EmconView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var emcon: Emcon
    @StateObject private var spar = Recon()
    @StateObject private var assault = AssaultCenter()
    @State private var armAssault = false
    @State private var assaultIgnition = false

    @AppStorage("emconEscalation") private var escalationArmed = false
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
            NetAssaultSectionView(center: assault,
                                  armRequest: $armAssault)
            drillSection
            emissionsSection
            selfReconSection
            auditSection
            tripwireSection
            proberFilesSection
            hometurfSection
            senseSection
            conductorSection
            StewardSectionView(steward: emcon.steward)
            SubconsciousSectionView(showMind: $showMind)
            sparringSection
            SeasonSectionView(season: emcon.season,
                              emcon: emcon)
            DuelSectionView(emcon: emcon, showing: $showDuel)
            maneuversSection
            knockTrafficSection
            vaultSection
            deadHandSection
            CoinSectionView(center: CoinCenter.shared,
                            emcon: emcon)
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
        .sheet(isPresented: $showMind) {
            SubconsciousView()
        }
        .sheet(isPresented: $showDuel) {
            DuelView(center: emcon.duel, emcon: emcon,
                     chat: emcon.chat)
        }
        .sheet(item: $proberSelection) { file in
            ProberFileView(file: file)
        }
        .fullScreenCover(isPresented: $assaultIgnition) {
            AssaultIgnitionView(isShown: $assaultIgnition)
        }
        .confirmationDialog(
            "Turn loose the net-assault?",
            isPresented: $armAssault,
            titleVisibility: .visible) {
            Button("Begin the assault", role: .destructive) {
                assault.arm()
                // The run starts now; the ignition theatre
                // lays over its first pass, a breath behind
                // this dialog so the two never race.
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.35) {
                    assaultIgnition = true
                }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Pass after pass it will sweep this wire, "
                 + "let it announce itself, and knock the "
                 + "full census against every known device "
                 + "— for as long as you leave it armed. "
                 + "Anything watching for exactly this will "
                 + "see the phone coming, and on networks "
                 + "you do not own that attention may arrive "
                 + "with questions attached.")
        }
        .onAppear {
            emcon.restoreIfNeeded()
            emcon.mouth = mouth
        }
        .onChange(of: spar.fuzzing) { now in
            if !now, sparWasFuzzing {
                Journal.log("emcon", "spar",
                            (sparSummary ?? "sparring run")
                            + " — \(spar.fuzzDead) dead connection(s), "
                            + "Serve \(mouth.serveRunning ? "still up" : "down")")
            }
            sparWasFuzzing = now
        }
    }

    @State private var sparWasFuzzing = false
    @State private var sparSummary: String?
    @State private var showMind = false
    @State private var showDuel = false

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

    /// The bare host of a tripwire row — the stored source may
    /// carry the " (this device)" label, which is display text,
    /// not an address.
    private func knockBackHost(_ event: Emcon.TripEvent) -> String {
        event.source.components(separatedBy: " ").first ?? event.source
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
            Toggle("Answer in character", isOn: $escalationArmed)
            Text("When a knock fingerprints as a real protocol "
                 + "— SSH, HTTP, MQTT, SMTP — the tripwire hands "
                 + "that port to the matching canary for ten "
                 + "minutes, honeydrop as configured on the "
                 + "Serve tab, then takes the port back. The "
                 + "prober's first knock meets silence; their "
                 + "second meets an actor. A port cools down "
                 + "for half an hour afterwards.")
                .font(.caption).foregroundStyle(.secondary)
            if let live = emcon.escalation {
                HStack {
                    Text("Answering on \(live.port) as "
                         + "\(live.persona.uppercased()) until "
                         + live.until.formatted(date: .omitted,
                                                time: .shortened))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Stand down") { emcon.endEscalation() }
                }
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
                    HStack(alignment: .top) {
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
                        Spacer()
                        if knockBackHost(event) != "127.0.0.1" {
                            Button {
                                mouth.reconHandoff = Mouth.ReconHandoff(
                                    host: knockBackHost(event),
                                    port: event.port,
                                    nonce: UUID())
                            } label: {
                                Image(systemName: "scope")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Knock back in Recon")
                        }
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

    // MARK: - prober files

    @State private var proberSelection: ProberFile?

    private var proberFilesSection: some View {
        let files = ProberFiles.build(events: emcon.events)
        return Section(header: Text("Prober files"),
                footer: Text("A dossier for everyone who has "
                    + "knocked — assembled from the tripwire "
                    + "log this phone keeps. It covers what "
                    + "the log still holds.")) {
            if files.isEmpty {
                Text("No probers yet. When something knocks, "
                     + "its file opens here.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(files) { file in
                    Button {
                        proberSelection = file
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.host)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text("\(file.knocks) knock(s) · "
                                     + "\(file.ports.count) port(s)"
                                     + (file.drops > 0
                                        ? " · took \(file.drops) "
                                            + "drop(s)" : "")
                                     + " · last "
                                     + file.lastSeen.formatted(
                                        date: .omitted,
                                        time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if ProberFiles.changed(file) {
                                Text("CHANGED")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - self-sparring

    /// TCP captures carrying their actual first words — the seeds.
    private var sparSeeds: [Emcon.TripEvent] {
        emcon.events.filter { $0.proto == "TCP" && $0.bytesHex != nil }
    }

    private var serveTCPPort: Int {
        UserDefaults.standard.string(forKey: "serveTcpPort")
            .flatMap(Int.init) ?? 9000
    }

    private var sparringSection: some View {
        Section(header: Text("Self-sparring"),
                footer: Text("The loop fires only at this device: "
                             + "the target is loopback, and the "
                             + "mutations are of traffic this phone "
                             + "actually received.")) {
            if sparSeeds.isEmpty {
                Text("No captured bytes yet. When the tripwire "
                     + "catches a knock, its first words are kept — "
                     + "and become ammunition here: replayed, "
                     + "mutated, and fired at your own Serve to see "
                     + "what holds.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if !mouth.serveRunning {
                Text("\(sparSeeds.count) captured probe(s) ready. "
                     + "Start Serve (TCP :\(serveTCPPort)) on the "
                     + "Serve tab — sparring fires mutations of a "
                     + "real capture at your own listener, on "
                     + "loopback, and reads what it answers.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let seed = sparSeeds.first,
                      let seedData = try? PayloadKit.decodeHex(
                        seed.bytesHex ?? "") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest capture: \(seed.verdict) — "
                         + "\(seed.byteCount) B from \(seed.source)")
                        .font(.caption)
                    if spar.fuzzing {
                        HStack {
                            ProgressView()
                            Text("Sparring…").font(.callout)
                        }
                        Button("Stop") { spar.stopFuzz() }
                    } else {
                        Button {
                            sparSummary = "60 mutations of a captured "
                                + "\(seed.verdict) probe vs own Serve "
                                + ":\(serveTCPPort)"
                            spar.startFuzz(
                                target: "tcp://127.0.0.1:\(serveTCPPort)",
                                seed: seedData, count: 60,
                                length: seedData.count, mutations: 2,
                                seedValue: nil, read: true,
                                timeout: 1.2)
                        } label: {
                            Label("Spar — 60 mutations vs own Serve "
                                  + ":\(serveTCPPort)",
                                  systemImage: "figure.fencing")
                        }
                    }
                }
            }
            if !spar.fuzzLines.isEmpty {
                ForEach(Array(spar.fuzzLines.suffix(10).enumerated()),
                        id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced())
                }
                if !spar.fuzzing {
                    Text(spar.fuzzDead == 0
                         ? "Serve held: no dead connections."
                         : "Serve dropped \(spar.fuzzDead) "
                           + "connection(s) under mutation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - knock traffic (the detection side)

    /// Knocktalk's conversations live in their own tab now.
    /// What stays here is what EMCON is FOR: the traffic that
    /// framed like speech but could not be opened — sealed,
    /// mangled, or structured like spelling.
    private var knockTrafficSection: some View {
        Section(header: Text("Knock traffic"),
                footer: Text("Decoded conversations live in the "
                             + "Knocktalk tab. What remains here "
                             + "never opened: framed traffic under "
                             + "a wrong or missing key, and knock "
                             + "patterns shaped like speech.")) {
            if emcon.knockPatterns.isEmpty {
                Text("Nothing sealed or structured has knocked. "
                     + "A scan sweeps; anything that spells — "
                     + "and fails to open — lands here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(emcon.knockPatterns) { pattern in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(pattern.source) — \(pattern.knocks) "
                         + "knocks")
                        .font(.caption.weight(.semibold))
                    Text(pattern.note).font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pattern.when.formatted(
                        date: .omitted, time: .standard))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }


    // MARK: - knock vault

    private static let vaultDigitOptions =
        ["ssh", "tls", "mqtt", "http", "smtp", "ftp"]

    private var vaultSection: some View {
        Section(header: Text("Knock vault"),
                footer: Text("Speak the combination from one "
                             + "other device and the chosen macro "
                             + "fires. Timed macros ride a "
                             + "sixty-second window and stand "
                             + "back down at the seal; anything "
                             + "you already had running stays "
                             + "yours. The ear must be listening — "
                             + "the tripwire, or the relay. The "
                             + "default "
                             + "combination is printed in the app — "
                             + "it is no secret. Change the digits: "
                             + "the combination is the key. Knocks "
                             + "from this device itself never count.")) {
            Text("Speak three protocols, in order, from one other "
                 + "device, inside 20 seconds — each knock's bytes "
                 + "recognized as its protocol:")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { index in
                Picker("Digit \(index + 1)",
                       selection: Binding(
                        get: { emcon.vaultCombo[index] },
                        set: { emcon.setVaultDigit(index, $0) })) {
                    ForEach(Self.vaultDigitOptions, id: \.self) {
                        digit in
                        Text(digit.uppercased()).tag(digit)
                    }
                }
            }
            Picker("When spoken", selection: Binding(
                get: { emcon.vaultAction },
                set: { emcon.setVaultAction($0) })) {
                ForEach(Emcon.vaultActions, id: \.self) { action in
                    Text(Emcon.vaultActionLabel(action)).tag(action)
                }
            }
            if let until = emcon.vaultOpenUntil {
                HStack {
                    Text("Vault")
                    Spacer()
                    Text("OPEN — seals "
                         + until.formatted(date: .omitted,
                                           time: .standard))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Button("Seal now") { emcon.sealVault() }
            } else {
                HStack {
                    Text("Vault")
                    Spacer()
                    Text("sealed")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - hardening

    // MARK: - home-turf memory

    private var hometurfSection: some View {
        Section(header: Text("Home-turf memory"),
                footer: Text("Learned only while EMCON is up "
                    + "on the home subnet — three banked nights "
                    + "hold the pattern, and after that the tab "
                    + "stops reporting events and starts "
                    + "reporting deviations. It learns from "
                    + "the tripwire's hearing alone; a quiet "
                    + "house teaches it a quiet pattern.")) {
            if emcon.homeSubnet == nil {
                Text("No home subnet is marked, so there is "
                     + "no turf to learn.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !emcon.hometurfReady {
                Text("Learning the pattern — "
                     + "\(emcon.hometurf.nights) of 3 nights "
                     + "banked.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Pattern held: \(emcon.hometurf.nights) "
                     + "nights · \(emcon.hometurf.sources.count) "
                     + "sources · \(emcon.hometurf.ports.count) "
                     + "doors · \(emcon.hometurf.verdicts.count) "
                     + "first words.")
                    .font(.callout)
                if emcon.hometurfNotes.isEmpty {
                    Text("Nothing off-pattern tonight.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(emcon.hometurfNotes, id: \.self) {
                        note in
                        Label(note, systemImage: "waveform.path.ecg")
                            .font(.callout)
                    }
                }
                Button("Forget the pattern", role: .destructive) {
                    emcon.hometurfReset()
                }
            }
        }
    }

    // MARK: - second sense

    private var senseSection: some View {
        Section(header: Text("Second sense"),
                footer: Text("The perimeter tightens itself "
                    + "for thirty minutes when a foreign "
                    + "nightjar-grade probe speaks to it, or a "
                    + "honeydrop is taken: answer in character "
                    + "arms whether or not its switch is set. "
                    + "Nothing else changes — a tightened "
                    + "perimeter stays legible.")) {
            if emcon.senseActive, let until = emcon.senseUntil {
                Label("Heightened until "
                      + until.formatted(date: .omitted,
                                        time: .shortened),
                      systemImage: "exclamationmark.shield")
                    .font(.callout.weight(.medium))
                Text(emcon.senseReason)
                    .font(.caption).foregroundStyle(.secondary)
                Button("Stand it down") { emcon.senseStandDown() }
            } else {
                Text("At ease. The perimeter is at its "
                     + "ordinary posture.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - the conductor

    @AppStorage("conductorOn") private var conductorOn = false
    @State private var rules: [Conductor.Rule] = []
    @State private var newTrigger = "fingerprinted"
    @State private var newAction = "pivotRecon"

    private var conductorSection: some View {
        Section(header: Text("The conductor"),
                footer: Text("Reflexes you arm once, fired "
                    + "without you: a trigger on the wire, an "
                    + "action the instrument already knows. "
                    + "Each rule rests five minutes between "
                    + "firings, every firing is journaled, and "
                    + "actions needing a mouth or a target "
                    + "degrade to the journal line alone when "
                    + "they have neither. Firing the bench "
                    + "stays your press — a reflex can load "
                    + "Recon, never pull its trigger.")) {
            Toggle("Conductor", isOn: $conductorOn)
            ForEach($rules) { $rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name).font(.callout)
                        Text(Conductor.triggerLabel(rule.trigger)
                             + " → "
                             + Conductor.actionLabel(rule.action))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $rule.enabled)
                        .labelsHidden()
                        .onChange(of: rule.enabled) { _ in
                            Conductor.saveRules(rules)
                        }
                    Button(role: .destructive) {
                        rules.removeAll { $0.id == rule.id }
                        Conductor.saveRules(rules)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Picker("When", selection: $newTrigger) {
                ForEach(Conductor.triggers, id: \.id) { t in
                    Text(t.label).tag(t.id)
                }
            }
            Picker("Then", selection: $newAction) {
                ForEach(Conductor.actions, id: \.id) { a in
                    Text(a.label).tag(a.id)
                }
            }
            Button {
                let rule = Conductor.Rule(
                    id: UUID().uuidString,
                    name: Conductor.triggerLabel(newTrigger)
                        + " → " + Conductor.actionLabel(newAction),
                    trigger: newTrigger, action: newAction,
                    enabled: true)
                rules.append(rule)
                Conductor.saveRules(rules)
            } label: {
                Label("Add the reflex", systemImage: "plus.circle")
            }
        }
        .onAppear {
            Conductor.seedIfNeeded()
            rules = Conductor.loadRules()
        }
    }

    // MARK: - night maneuvers

    private struct ManeuverLeg: Identifiable {
        enum Outcome { case pass, flag, skip }
        var id: String { name }
        let name: String
        let outcome: Outcome
        let detail: String
    }

    @StateObject private var maneuverSpar = Recon()
    @State private var maneuverLegs: [ManeuverLeg] = []
    @State private var maneuversRunning = false
    @State private var maneuverWasFuzzing = false
    @State private var maneuversGrade: String?

    /// One press, three examinations, one grade in the sealed
    /// log: the chain proves the record, the census reads the
    /// posture, the spar tests the listener. A leg that cannot
    /// run says so — skipped is a finding, not a failure.
    private func runManeuvers() {
        maneuverLegs = []
        maneuversGrade = nil
        maneuversRunning = true

        let chain = Journal.verifyChain()
        maneuverLegs.append(ManeuverLeg(
            name: "Seal chain",
            outcome: chain.brokenLine == nil ? .pass : .flag,
            detail: chain.brokenLine == nil
                ? "\(chain.sealed) sealed line(s) hold, "
                    + "\(chain.legacy) legacy line(s) predate "
                    + "the chain"
                : "BROKEN at sealed line "
                    + "\(chain.brokenLine ?? 0)"))

        let censusDetail = "exposure \(score.value) · tripwire "
            + (emcon.tripwireOn ? "up" : "DOWN")
            + (emcon.unwatched.isEmpty
                ? " · every port watched"
                : " · \(emcon.unwatched.count) port(s) unwatched")
        maneuverLegs.append(ManeuverLeg(
            name: "Census",
            outcome: emcon.tripwireOn && emcon.unwatched.isEmpty
                ? .pass : .flag,
            detail: censusDetail))

        guard mouth.serveRunning else {
            maneuverLegs.append(ManeuverLeg(
                name: "Spar", outcome: .skip,
                detail: "Serve is down — no listener to test"))
            finishManeuvers()
            return
        }
        guard let seed = sparSeeds.first,
              let seedData = try? PayloadKit.decodeHex(
                seed.bytesHex ?? "") else {
            maneuverLegs.append(ManeuverLeg(
                name: "Spar", outcome: .skip,
                detail: "no captured probe to replay yet"))
            finishManeuvers()
            return
        }
        maneuverSpar.startFuzz(
            target: "tcp://127.0.0.1:\(serveTCPPort)",
            seed: seedData, count: 60, length: seedData.count,
            mutations: 2, seedValue: nil, read: true, timeout: 1.2)
    }

    private func finishManeuvers(sparDead: Int? = nil) {
        if let sparDead {
            maneuverLegs.append(ManeuverLeg(
                name: "Spar",
                outcome: sparDead == 0 ? .pass : .flag,
                detail: sparDead == 0
                    ? "Serve held all 60 mutations"
                    : "Serve dropped \(sparDead) connection(s) "
                        + "under mutation"))
        }
        let clean = maneuverLegs.filter { $0.outcome == .pass }.count
        maneuversGrade = "\(clean) of \(maneuverLegs.count) "
            + "legs clean"
        Journal.log("emcon", "maneuvers",
                    maneuversGrade! + " — "
                    + maneuverLegs.map {
                        "\($0.name): \($0.detail)"
                    }.joined(separator: " · "))
        maneuversRunning = false
    }

    private var maneuversSection: some View {
        Section(header: Text("Night maneuvers"),
                footer: Text("The instrument reports for duty: "
                    + "the seal chain proves the record, the "
                    + "census reads the posture, the spar fires "
                    + "sixty mutations of a real capture at your "
                    + "own Serve. The grade goes into the sealed "
                    + "log either way.")) {
            Button {
                runManeuvers()
            } label: {
                Label(maneuversRunning
                        ? "Running maneuvers…"
                        : "Run night maneuvers",
                      systemImage: "checklist")
            }
            .disabled(maneuversRunning)
            ForEach(maneuverLegs) { leg in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: leg.outcome == .pass
                            ? "checkmark.circle.fill"
                            : leg.outcome == .flag
                                ? "exclamationmark.circle.fill"
                                : "minus.circle")
                        .foregroundStyle(leg.outcome == .pass
                            ? .green
                            : leg.outcome == .flag
                                ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.name).font(.callout.weight(.medium))
                        Text(leg.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let grade = maneuversGrade, !maneuversRunning {
                Text(grade + " — graded into the night log.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: maneuverSpar.fuzzing) { now in
            if !now, maneuverWasFuzzing, maneuversRunning {
                finishManeuvers(sparDead: maneuverSpar.fuzzDead)
            }
            maneuverWasFuzzing = now
        }
    }

    // MARK: - dead hand

    @AppStorage("deadHand.on") private var deadHandOn = false
    @AppStorage("deadHand.hours") private var deadHandHours = 24

    private var deadHandSection: some View {
        Section(header: Text("Dead hand"),
                footer: Text("Arm it, then check in here — "
                    + "deliberately, with the button — before "
                    + "the interval runs out. If the app is "
                    + "next opened with the check-in overdue, "
                    + "the Knocktalk threads burn and EMCON "
                    + "rises before anything else happens. It "
                    + "falls at the next OPENING, not at the "
                    + "deadline: iOS gives no app a background "
                    + "timer worth trusting. The reminders are "
                    + "courtesies. Merely opening the app never "
                    + "counts as a check-in — that is the "
                    + "point of the hand.")) {
            Toggle("Arm the dead hand", isOn: $deadHandOn)
                .onChange(of: deadHandOn) { on in
                    if on { emcon.deadHandArm() }
                    else { emcon.deadHandDisarm() }
                }
            if deadHandOn {
                Picker("Check in every",
                       selection: $deadHandHours) {
                    ForEach(Emcon.deadHandHoursOptions,
                            id: \.self) { h in
                        Text(h < 24 ? "\(h) hours"
                                    : "\(h / 24) day(s)")
                            .tag(h)
                    }
                }
                .onChange(of: deadHandHours) { _ in
                    emcon.deadHandReschedule()
                }
                if emcon.deadHandHasFallen {
                    Text("THE HAND HAS FALLEN — threads "
                         + "burned, EMCON raised. Check in to "
                         + "re-arm it.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                } else if let deadline = emcon.deadHandDeadline {
                    LabeledContent(
                        "Deadline",
                        value: deadline.formatted(
                            date: .abbreviated, time: .shortened))
                    if emcon.deadHandOverdue {
                        Text("OVERDUE — the hand falls at "
                             + "the next opening.")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Button {
                    emcon.deadHandCheckIn()
                } label: {
                    Label("Check in — I'm here",
                          systemImage: "hand.raised.fill")
                }
            }
        }
    }

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
