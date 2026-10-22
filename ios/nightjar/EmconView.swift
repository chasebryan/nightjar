import SwiftUI

/// EMCON tab: the device's own exposure — scored, itemized, and
/// shut down. See Emcon.swift for the engine and the honest limits.
struct EmconView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var emcon: Emcon
    @StateObject private var spar = Recon()
    @ObservedObject private var assault = AssaultCenter.shared
    @ObservedObject private var banshee = BansheeCenter.shared
    @ObservedObject private var probing = ProbingBeacon.shared
    @ObservedObject private var warRun = WarRun.shared
    @ObservedObject private var mimic = MimicCenter.shared
    @State private var chosenCondition: EmconCondition = .charlie
    @State private var armAssault = false
    @State private var assaultIgnition = false
    @State private var redframeSplash = false
    @State private var shareAssaultReport = false
    @State private var shareItem: ShareItem?
    @State private var tripShowAll = false

    @AppStorage("emconEscalation") private var escalationArmed = false
    @AppStorage("emconCheckName") private var checkName = false
    @AppStorage("emconCheckAirdrop") private var checkAirdrop = false
    @AppStorage("emconCheckHotspot") private var checkHotspot = false
    @AppStorage("emconCheckWifi") private var checkWifi = false
    @AppStorage("emconCheckBluetooth") private var checkBluetooth = false

    private var score: Emcon.Score {
        // The audit is the only way a score is made — it
        // reads the organs themselves, never a snapshot a
        // caller assembled.
        emcon.currentScore(mouth: mouth)
    }

    var body: some View {
        List {
            statusSection
            standardSection
            Section {
                if banshee.screaming {
                    HStack {
                        Label(L("THE BANSHEE IS SCREAMING"),
                              systemImage: "speaker.wave.3.fill")
                            .foregroundStyle(.red)
                            .font(.callout.weight(.bold))
                        Spacer()
                        Button(L("Cease"), role: .destructive) {
                            Haptics.tap()
                            banshee.cease(mouth: mouth,
                                          assault: assault)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        Haptics.tap()
                        showBanshee = true
                    } label: {
                        Label(L("The Banshee — scream on every channel"),
                              systemImage: "speaker.wave.3")
                    }
                }
                Text(L("The opposite of everything on this tab: Serve listed, stealth off, the beacon shouting, Net-Assault armed, a broadcast heartbeat — this device announcing itself at full voice until you cease it. Ceasing restores the posture it found."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Haptics.tap()
                    showSpoofy = true
                } label: {
                    Label(L("Spoofy — the costume rack"),
                          systemImage: "theatermasks")
                }
                Text(L("The names and shapes this device wears: costumes for the air, and mimicry personas that dress the whole device as a class of thing — or as the network's own gear, access point included — until you drop the shape."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NetAssaultSectionView(center: assault,
                                  armRequest: $armAssault,
                                  shareRequest: $shareAssaultReport)
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
            instrumentSection
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
            Section {
                Button {
                    Haptics.tap()
                    showTagCensus = true
                } label: {
                    Label(L("Tag census — read your own cards and tags"),
                          systemImage: "wave.3.right")
                }
                Text(L("What a tag tells any reader, read whole: its kind, its identifier, its NDEF records, and an APDU explorer for ISO 7816 cards. Nothing is written, emulated, or cloned."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            hardeningSection
            Section {
                Text(L("EMCON cannot hide this device from the access point it is joined to, and Apple's own radios (Find My, AirDrop) answer to Settings, not to this app. What EMCON strips is everything that identifies the device — and anyone who probes it announces themselves to the tripwire."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // The backdrop is painted HERE, behind the list
        // itself — the tab-level modifier alone never
        // reached through on device (Macros and the
        // Vault sat black for trusting it). Same recipe
        // as the tabs that play.
        .scrollContentBackground(.hidden)
        .macColumn(880)
        .macListStyle()
        .background { AppBackdrop() }
        .sheet(isPresented: $showMind) {
            SubconsciousView()
        }
        .sheet(isPresented: $showDuel) {
            DuelView(center: emcon.duel, emcon: emcon,
                     chat: emcon.chat)
        }
        .sheet(isPresented: $showTagCensus) {
            TagCensusView()
        }
        .sheet(isPresented: $showBanshee) {
            BansheeView(assault: assault, banshee: banshee)
        }
        .sheet(isPresented: $showSpoofy) {
            SpoofyView()
        }
        .sheet(item: $proberSelection) { file in
            ProberFileView(file: file)
        }
        .houseFullScreenCover(isPresented: $assaultIgnition) {
            AssaultIgnitionView(isShown: $assaultIgnition)
        }
        .houseFullScreenCover(isPresented: $redframeSplash) {
            RedframeSplashView(isShown: $redframeSplash)
        }
        .onChange(of: shareAssaultReport) { wanted in
            // The after-action report goes out the same
            // door as every other share in the app.
            if wanted {
                shareItem = ShareItem(items: [assault.report])
                shareAssaultReport = false
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .confirmationDialog(
            L("Turn loose the net-assault?"),
            isPresented: $armAssault,
            titleVisibility: .visible) {
            Button(L("Begin the assault"), role: .destructive) {
                assault.arm()
                if assault.running {
                    // The run starts now; the ignition
                    // theatre lays over its first pass, a
                    // breath behind this dialog so the two
                    // never race.
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.35) {
                        assaultIgnition = true
                    }
                } else {
                    // A refused arm is spoken, never
                    // silent: the Standard held it dark,
                    // and the operator hears why.
                    toasts.show(String(format: L("Net-Assault stays dark — %@ forbids it under the Standard."),
                                       EmconCondition.current.declared))
                }
            }
            Button(L("Not yet"), role: .cancel) {}
        } message: {
            Text(L("Pass after pass it will sweep this wire, let it announce itself, and knock the full census against every known device — for as long as you leave it armed. Anything watching for exactly this will see the phone coming, and on networks you do not own that attention may arrive with questions attached."))
        }
        .onAppear {
            emcon.restoreIfNeeded()
            WireWatch.restoreIfNeeded()
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
    @State private var showTagCensus = false
    @State private var showBanshee = false
    @State private var showSpoofy = false

    // MARK: - status + score

    private var statusSection: some View {
        // One audit per render: the section's
        // dozen reads all draw on this single
        // score (the sweep's finding P3).
        let live = score
        return Section {
            HStack(spacing: 14) {
                Image(systemName: emcon.active
                      ? "checkmark.shield.fill" : "shield")
                    .font(.title)
                    .foregroundStyle(emcon.active ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(emcon.active
                         ? emcon.condition.declared
                         : L("EMCON OFF"))
                        .font(.headline)
                    Text(emcon.active
                         ? emcon.condition.summary
                         : L("This device answers the network under its own name."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text(Emcon.fmt(live.value))
                        .font(.title.weight(.bold))
                        .foregroundStyle(scoreColor(live.value))
                    Text(L(live.band))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(scoreColor(live.value))
                }
            }
            Text(L("Exposure, to the decimal — the Standard's inventory: presence first, then each standing emission at its fixed weight, then the evidence, folded by its formula. Nothing is capped; a fully lit house sums to exactly 100.0."))
                .font(.caption).foregroundStyle(.secondary)
            if emcon.active,
               let before = emcon.scoreBeforeDark,
               before.value > live.value {
                Text(String(format: L("Going dark took you from %@ %@ to %@ %@."),
                            Emcon.fmt(before.value), L(before.band),
                            Emcon.fmt(live.value), L(live.band)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if !live.parts.isEmpty {
                Text(String(format: L("Why %@:"), L(live.band)))
                    .font(.caption.weight(.semibold))
                ForEach(live.parts) { part in
                    HStack {
                        Text(part.label).font(.caption)
                        Spacer()
                        Text("+" + Emcon.fmt(part.points))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(scoreColor(live.value))
                    }
                }
            }
            // The standing board: every governed organ, its
            // live state, and this condition's ruling on it.
            // A switch redraws it even in a quiet house.
            Text(L("The standing board"))
                .font(.caption.weight(.semibold))
            ForEach(emcon.board(mouth: mouth)) { row in
                HStack {
                    Text(row.label).font(.caption)
                    Spacer()
                    if row.standing {
                        Text(String(format: L("standing · %@"),
                                    Emcon.fmt(row.weight)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.violation
                                              ? .red
                                              : scoreColor(live.value))
                    } else {
                        Text(L("dark"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(L(row.ruling))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            row.ruling == "Forbidden"
                                ? .red : .secondary)
                        .frame(width: 78,
                               alignment: .trailing)
                }
            }
            if emcon.active {
                if emcon.lastSilenced.isEmpty {
                    Text(L("Nothing was standing — nothing had to be silenced."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                let refused = EmconStandard.refusedLabels(
                    for: emcon.condition)
                if !refused.isEmpty {
                    Text(String(format: L("The gates now refuse: %@."),
                                refused.joined(separator: ", ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !emcon.lastSilenced.isEmpty {
                    Text(String(format: L("Silenced on engage: %@."),
                                emcon.lastSilenced.joined(
                                    separator: ", ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !emcon.lastUnsilenced.isEmpty {
                    Label(String(format: L("Still lit: %@"),
                                 emcon.lastUnsilenced.joined(
                                    separator: ", ")),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            if emcon.isAway, !emcon.active {
                Label(L("Off home turf — this network is not your marked home. Going dark is advised."),
                      systemImage: "exclamationmark.shield")
                    .font(.callout).foregroundStyle(.orange)
                Button {
                    Haptics.tap()
                    goDark()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield")
                        Text(L("Go dark now"))
                    }
                }
                .buttonStyle(HouseProminentStyle())
            }
            if emcon.active {
                Menu {
                    ForEach([EmconCondition.charlie,
                             .bravo, .alpha], id: \.self) { goal in
                        Button {
                            Haptics.tap()
                            emcon.activate(mouth: mouth,
                                           condition: goal)
                            if goal == .alpha {
                                // Total silence gets its
                                // theatre: her red frame
                                // closes over the hush.
                                redframeSplash = true
                            }
                            toasts.show(String(format: L("%@ — the house is re-regulated."), goal.declared))
                        } label: {
                            Text(String(format: L("Move to %@"), goal.name))
                        }
                    }
                } label: {
                    Label(L("Change condition"),
                          systemImage: "arrow.left.arrow.right")
                }
                Button(role: .destructive) {
                    Haptics.tap()
                    emcon.deactivate()
                    toasts.show(L("EMCON off — tripwire stood down. Stealth left as it was."))
                } label: {
                    Label(L("Stand down EMCON"), systemImage: "shield")
                }
            } else if !emcon.isAway {
                Picker(L("Condition"), selection: $chosenCondition) {
                    Text(L("Charlie")).tag(EmconCondition.charlie)
                    Text(L("Bravo")).tag(EmconCondition.bravo)
                    Text(L("Alpha")).tag(EmconCondition.alpha)
                }
                .pickerStyle(.segmented)
                Text(chosenCondition.summary)
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    Haptics.tap()
                    emcon.activate(mouth: mouth,
                                   condition: chosenCondition)
                    if chosenCondition == .alpha {
                        // Total silence gets its
                        // theatre: her red frame
                        // closes over the hush.
                        redframeSplash = true
                    }
                    toasts.show(String(format: L("%@ — emissions regulated, tripwire armed."), chosenCondition.declared))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield")
                        Text(String(format: L("Engage %@"),
                                    chosenCondition.declared))
                    }
                }
                .buttonStyle(HouseProminentStyle())
            }
        }
    }

    private func goDark() {
        emcon.activate(mouth: mouth)
        toasts.show(L("EMCON active — emissions silenced, tripwire armed."))
    }

    private func scoreColor(_ value: Double) -> Color {
        switch value {
        case 0: return .green
        case ..<10: return .mint
        case ..<30: return .yellow
        case ..<60: return .orange
        default: return .red
        }
    }

    /// The Standard, posted in the room it governs: the
    /// conditions, what each permits, and the one boundary
    /// (a deliberate transmission by hand is the operator
    /// speaking; standing emissions are what is regulated).
    private var standardSection: some View {
        Section {
            ForEach([EmconCondition.charlie, .bravo, .alpha],
                    id: \.self) { condition in
                VStack(alignment: .leading, spacing: 2) {
                    Text(condition.declared)
                        .font(.caption.weight(.semibold))
                    Text(condition.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(L("The gate stands at every funnel: under a condition, a forbidden organ cannot start — not by hand, not by macro, not by her, not by a saved arm returning at launch. Refusals are journaled. A single payload you fire yourself is you speaking, and is not regulated; everything that stands, advertises, serves, probes or polls is."))
                .font(.caption2).foregroundStyle(.secondary)
        } header: {
            Text(L("The Standard"))
        }
    }

    // MARK: - the drill

    private var drillSection: some View {
        Section(header: Text(L("The drill"))) {
            Button {
                Haptics.tap()
                emcon.runDrill(mouth: mouth)
            } label: {
                Label(emcon.drilling
                      ? L("Running the drill…")
                      : L("Prove it — scan, go dark, scan again"),
                      systemImage: "checklist")
            }
            .disabled(emcon.drilling || emcon.scanning || emcon.auditing)
            if emcon.drilling {
                ProgressView()
            } else if let before = emcon.drillBefore,
                      let after = emcon.drillAfter {
                // The readout is the ledger plus the
                // snapshot diff: what the drill switched
                // off by name, and what the wire itself
                // stopped showing.
                let gone = emcon.drillSilenced
                    + Emcon.silenced(before: before, after: after)
                let still = Emcon.stillShowing(after)
                if gone.isEmpty, still.isEmpty {
                    Text(L("Before and after agree: nothing was exposed in the first place."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    if !gone.isEmpty {
                        Text(L("Silenced by going dark:"))
                            .font(.callout.weight(.semibold))
                        ForEach(Array(gone.enumerated()), id: \.offset) { item in
                            Text(String(format: L("— %@"), item.element)).font(.callout)
                        }
                    } else if !still.isEmpty {
                        Text(L("Nothing went quiet."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if still.isEmpty {
                        Text(L("Nothing survived the drill. The second scan found a clean device."))
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        Text(L("Still showing:"))
                            .font(.callout.weight(.semibold))
                        ForEach(Array(still.enumerated()), id: \.offset) { item in
                            Text(String(format: L("— %@"), item.element)).font(.callout)
                        }
                        Text(L("These are real listeners on the device that EMCON does not own — the OS, other apps, or Serve ports kept under stealth. The hardening list below is where the OS ones die."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(L("One tap: full knock and Bonjour audit, then EMCON engages, then both run again and the difference is read out here."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - emissions

    private var emissionsSection: some View {
        Section(header: Text(L("Emissions"))) {
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
            Text(L("Going dark forces Serve stealth, disarms the GATT host and stops the beacon. Coming back never re-opens one — re-arm each in its own tab."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func emissionRow(_ name: String, state: String,
                             bad: Bool) -> some View {
        HStack {
            Text(L(name))
            Spacer()
            Text(L(state))
                .font(.callout)
                .foregroundStyle(bad ? .red : .secondary)
        }
    }

    // MARK: - self-recon

    private var selfReconSection: some View {
        Section(header: Text(L("Self-recon — what they see"))) {
            HStack {
                Text(L("Broadcast name"))
                Spacer()
                Text(emcon.deviceName).font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(L("LAN address"))
                Spacer()
                Text(emcon.ownIP ?? L("not on Wi-Fi")).font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                emcon.runSelfScan()
            } label: {
                Label(emcon.scanning ? L("Knocking…") : L("Knock myself"),
                      systemImage: "target")
            }
            .disabled(emcon.scanning || emcon.drilling)
            if emcon.scanning {
                ProgressView()
            } else if emcon.lastScanAt != nil {
                if emcon.exposures.isEmpty {
                    Text(L("Nothing answered on any probed port, on loopback or the LAN address. From out there, this device is a rumor."))
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
                Text(L("★ = the reply carried the service's own tell."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(L("Runs Recon's own knock against this phone — every registry port, loopback and LAN address, each port spoken to in its own protocol."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bonjour audit

    private var auditSection: some View {
        Section(header: Text(L("Announcements — Bonjour audit"))) {
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
                    Text(String(format: L("Heard %lld announcement(s) on this network — none of them is this device. mDNS has nothing of yours."), emcon.heardCount))
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
                    Text(L("These are the OS's own megaphones — AirPlay and friends. EMCON can't switch them off; the hardening list is where they die (name, AirDrop)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("Browses the LAN the way the Scan tab does and flags every announcement that is this device — by name, or by resolving to this phone's address."))
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
        Section(header: Text(L("Tripwire"))) {
            HStack {
                Text(L("Listeners"))
                Spacer()
                Text(emcon.tripwireOn
                     ? String(format: L("%lld TCP + %lld UDP watched"),
                              emcon.watched.count,
                              emcon.watchedUDP.count)
                     : L("off"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !emcon.unwatched.isEmpty {
                Text(String(format: L("Not watched (already in use): %@"),
                            emcon.unwatched.map(String.init)
                                .joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(L("Answer in character"), isOn: $escalationArmed)
            Text(L("When a knock fingerprints as a real protocol — SSH, HTTP, MQTT, SMTP — the tripwire hands that port to the matching canary for ten minutes, honeydrop as configured on the Serve tab, then takes the port back. The prober's first knock meets silence; their second meets an actor. A port cools down for half an hour afterwards."))
                .font(.caption).foregroundStyle(.secondary)
            if let live = emcon.escalation {
                HStack {
                    Text(String(format: L("Answering on %lld as %@ until "), live.port, live.persona.uppercased())
                         + live.until.formatted(date: .omitted,
                                                time: .shortened))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Button(L("Stand down")) { emcon.endEscalation() }
                }
            }
            if emcon.events.isEmpty {
                Text(L("Nobody has knocked. When someone runs these probes against this phone, it lands here — source, port, and which first words they used. The log persists across launches. The tripwire never replies."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(tripShowAll
                        ? emcon.events
                        : Array(emcon.events.prefix(6))) { event in
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
                            .accessibilityLabel(L("Knock back in Recon"))
                        }
                    }
                }
                if emcon.events.count > 6 {
                    Button {
                        withAnimation { tripShowAll.toggle() }
                    } label: {
                        Label(tripShowAll
                              ? L("Show fewer")
                              : String(format: L("Show all %lld knocks"),
                                       emcon.events.count),
                              systemImage: tripShowAll
                                ? "chevron.up" : "chevron.down")
                    }
                }
                Button {
                    shareItem = ShareItem(
                        items: [Emcon.tripwireReportURL])
                } label: {
                    Label(L("Share the log"),
                          systemImage: "square.and.arrow.up")
                }
                Text(L("Readable text. The same log is kept as JSON in Documents. The tripwire never replies."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    emcon.clearEvents()
                } label: {
                    Label(L("Clear the log"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - the instrument

    @ObservedObject private var instrument = InstrumentCenter.shared

    private func vitalRow(_ label: String,
                          _ reading: VitalReading?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(label)).font(.callout)
                Text(reading.map {
                    InstrumentCenter.ageLine($0.when)
                        + ($0.source.map { " · \($0)" } ?? "")
                } ?? L("no reading yet"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(reading?.value ?? "—")
                .font(.callout.weight(.semibold))
        }
    }

    private var instrumentSection: some View {
        Section(header: Text(L("The Instrument — the operator, read")),
                footer: Text(L("The Watch is never asked to do anything — worn and paired, it already measures, and the readings wait in this phone's health store. A reading, not a live feed: samples arrive at the Watch's sync cadence, and every value carries its age. Read-only and on-device; raw readings are never written to the night log."))) {
            switch instrument.phase {
            case .unavailable:
                Text(L("This device has no health store to read."))
                    .font(.callout).foregroundStyle(.secondary)
            case .dormant:
                Text(L("This build's signing doesn't carry the HealthKit entitlement, so the instrument sleeps — the way the Coin sleeps under free signing. A signing that carries it wakes the instrument with no other change."))
                    .font(.callout).foregroundStyle(.secondary)
            case .unknown:
                Text(L("Your Watch already knows the state of the operator — heart, breath, blood, sleep. Let the house read it, and that state stands beside the state of the house."))
                    .font(.callout).foregroundStyle(.secondary)
                Button {
                    instrument.requestAccess()
                } label: {
                    Label(L("Let the house read the instrument"),
                          systemImage: "heart.text.square")
                }
            case .asking:
                HStack {
                    ProgressView()
                    Text(L("Asking…"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .reading:
                if let watch = instrument.watchName {
                    Text(String(format: L("Reading %@, through the health store it already feeds. It was never asked to do anything else."), watch))
                        .font(.caption).foregroundStyle(.secondary)
                }
                vitalRow("Heart rate", instrument.heartRate)
                vitalRow("Heart rate variability",
                         instrument.hrv)
                vitalRow("Resting heart rate",
                         instrument.restingHeartRate)
                vitalRow("Blood oxygen", instrument.oxygen)
                vitalRow("Respiratory rate",
                         instrument.respiratory)
                vitalRow("Wrist temperature (sleeping)",
                         instrument.wristTemp)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Sleep, last night")).font(.callout)
                        Text(instrument.lastSleep.map {
                            String(format: L("asleep %@ → %@"),
                                   $0.start.formatted(
                                       date: .omitted, time: .shortened),
                                   $0.end.formatted(
                                       date: .omitted, time: .shortened))
                        } ?? L("no sleep recorded"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(instrument.lastSleep.map(
                        InstrumentCenter.durationLine) ?? "—")
                        .font(.callout.weight(.semibold))
                }
                HStack {
                    Text(L("Steps today")).font(.callout)
                    Spacer()
                    Text(instrument.stepsToday?.formatted() ?? "—")
                        .font(.callout.weight(.semibold))
                }
                Button {
                    instrument.fetchAll()
                } label: {
                    Label(L("Read again"), systemImage: "arrow.clockwise")
                }
                if let read = instrument.lastReadAt {
                    Text(String(format: L("Read %@."),
                                InstrumentCenter.ageLine(read)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if instrument.phase == .reading {
                instrument.fetchAll()
            }
        }
    }

    // MARK: - prober files

    @State private var proberSelection: ProberFile?
    @State private var proberShowAll = false

    private var proberFilesSection: some View {
        let files = ProberFiles.build(events: emcon.events)
        return Section(header: Text(L("Prober files")),
                footer: Text(L("A dossier for everyone who has knocked — assembled from the tripwire log this phone keeps. It covers what the log still holds."))) {
            if files.isEmpty {
                Text(L("No probers yet. When something knocks, its file opens here."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(proberShowAll
                        ? files
                        : Array(files.prefix(6))) { file in
                    Button {
                        proberSelection = file
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.host)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(String(format: L("%lld knock(s) · %lld port(s)"), file.knocks, file.ports.count)
                                     + (file.drops > 0
                                        ? String(format: L(" · took %lld drop(s)"),
                                                 file.drops) : "")
                                     + String(format: L(" · last %@"),
                                              file.lastSeen.formatted(
                                                  date: .omitted,
                                                  time: .shortened)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if ProberFiles.changed(file) {
                                Text(L("CHANGED"))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.orange)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if files.count > 6 {
                    Button {
                        withAnimation { proberShowAll.toggle() }
                    } label: {
                        Label(proberShowAll
                              ? L("Show fewer")
                              : String(format: L("Show all %lld files"),
                                       files.count),
                              systemImage: proberShowAll
                                ? "chevron.up" : "chevron.down")
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
        Section(header: Text(L("Self-sparring")),
                footer: Text(L("The loop fires only at this device: the target is loopback, and the mutations are of traffic this phone actually received."))) {
            if sparSeeds.isEmpty {
                Text(L("No captured bytes yet. When the tripwire catches a knock, its first words are kept — and become ammunition here: replayed, mutated, and fired at your own Serve to see what holds."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !mouth.serveRunning {
                Text(String(format: L("%lld captured probe(s) ready. Start Serve (TCP :%lld) on the Serve tab — sparring fires mutations of a real capture at your own listener, on loopback, and reads what it answers."), sparSeeds.count, serveTCPPort))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let seed = sparSeeds.first,
                      let seedData = try? PayloadKit.decodeHex(
                        seed.bytesHex ?? "") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: L("Latest capture: %@ — %lld B from %@"), seed.verdict, seed.byteCount, seed.source))
                        .font(.caption)
                    if spar.fuzzing {
                        HStack {
                            ProgressView()
                            Text(L("Sparring…")).font(.callout)
                        }
                        Button(L("Stop")) { spar.stopFuzz() }
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
                            Label(String(format: L("Spar — 60 mutations vs own Serve :%lld"),
                                         serveTCPPort),
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
                         ? L("Serve held: no dead connections.")
                         : String(format: L("Serve dropped %lld connection(s) under mutation."),
                                  spar.fuzzDead))
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
        Section(header: Text(L("Knock traffic")),
                footer: Text(L("Decoded conversations live in the Knocktalk tab. What remains here never opened: framed traffic under a wrong or missing key, and knock patterns shaped like speech."))) {
            if emcon.knockPatterns.isEmpty {
                Text(L("Nothing sealed or structured has knocked. A scan sweeps; anything that spells — and fails to open — lands here."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(emcon.knockPatterns) { pattern in
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("%@ — %lld knocks"), pattern.source, pattern.knocks))
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
        Section(header: Text(L("Knock vault")),
                footer: Text(L("Speak the combination from one other device and the chosen macro fires. Timed macros ride a sixty-second window and stand back down at the seal; anything you already had running stays yours. The ear must be listening — the tripwire, or the relay. The default combination is printed in the app — it is no secret. Change the digits: the combination is the key. Knocks from this device itself never count."))) {
            Text(L("Speak three protocols, in order, from one other device, inside 20 seconds — each knock's bytes recognized as its protocol:"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { index in
                Picker(String(format: L("Digit %lld"), index + 1),
                       selection: Binding(
                        get: { emcon.vaultCombo[index] },
                        set: { emcon.setVaultDigit(index, $0) })) {
                    ForEach(Self.vaultDigitOptions, id: \.self) {
                        digit in
                        Text(digit.uppercased()).tag(digit)
                    }
                }
            }
            Picker(L("When spoken"), selection: Binding(
                get: { emcon.vaultAction },
                set: { emcon.setVaultAction($0) })) {
                ForEach(Emcon.vaultActions, id: \.self) { action in
                    Text(Emcon.vaultActionLabel(action)).tag(action)
                }
            }
            if let until = emcon.vaultOpenUntil {
                HStack {
                    Text(L("Vault"))
                    Spacer()
                    Text(String(format: L("OPEN — seals %@"),
                                until.formatted(date: .omitted,
                                                time: .standard)))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
                Button(L("Seal now")) { emcon.sealVault() }
            } else {
                HStack {
                    Text(L("Vault"))
                    Spacer()
                    Text(L("sealed"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - hardening

    // MARK: - home-turf memory

    private var hometurfSection: some View {
        Section(header: Text(L("Home-turf memory")),
                footer: Text(L("Learned only while EMCON is up on the home subnet — three banked nights hold the pattern, and after that the tab stops reporting events and starts reporting deviations. It learns from the tripwire's hearing alone; a quiet house teaches it a quiet pattern."))) {
            if emcon.homeSubnet == nil {
                Text(L("No home subnet is marked, so there is no turf to learn."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if !emcon.hometurfReady {
                Text(String(format: L("Learning the pattern — %lld of 3 nights banked."),
                            emcon.hometurf.nights))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(String(format: L("Pattern held: %lld nights · %lld sources · %lld doors · %lld first words."), emcon.hometurf.nights, emcon.hometurf.sources.count, emcon.hometurf.ports.count, emcon.hometurf.verdicts.count))
                    .font(.callout)
                if emcon.hometurfNotes.isEmpty {
                    Text(L("Nothing off-pattern tonight."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(emcon.hometurfNotes, id: \.self) {
                        note in
                        Label(note, systemImage: "waveform.path.ecg")
                            .font(.callout)
                    }
                }
                Button(L("Forget the pattern"), role: .destructive) {
                    emcon.hometurfReset()
                }
            }
        }
    }

    // MARK: - second sense

    private var senseSection: some View {
        Section(header: Text(L("Second sense")),
                footer: Text(L("The perimeter tightens itself for thirty minutes when a foreign nightjar-grade probe speaks to it, or a honeydrop is taken: answer in character arms whether or not its switch is set. Nothing else changes — a tightened perimeter stays legible."))) {
            if emcon.senseActive, let until = emcon.senseUntil {
                Label(String(format: L("Heightened until %@"),
                             until.formatted(date: .omitted,
                                             time: .shortened)),
                      systemImage: "exclamationmark.shield")
                    .font(.callout.weight(.medium))
                Text(emcon.senseReason)
                    .font(.caption).foregroundStyle(.secondary)
                Button(L("Stand it down")) { emcon.senseStandDown() }
            } else {
                Text(L("At ease. The perimeter is at its ordinary posture."))
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
        Section(header: Text(L("The conductor")),
                footer: Text(L("Reflexes you arm once, fired without you: a trigger on the wire, an action the instrument already knows. Each rule rests five minutes between firings, every firing is journaled, and actions needing a mouth or a target degrade to the journal line alone when they have neither. Firing the bench stays your press — a reflex can load Recon, never pull its trigger."))) {
            Toggle(L("Conductor"), isOn: $conductorOn)
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
                    Toggle(L(""), isOn: $rule.enabled)
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
            Picker(L("When"), selection: $newTrigger) {
                ForEach(Conductor.triggers, id: \.id) { t in
                    Text(t.label).tag(t.id)
                }
            }
            Picker(L("Then"), selection: $newAction) {
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
                Label(L("Add the reflex"), systemImage: "plus.circle")
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
            name: L("Seal chain"),
            outcome: chain.brokenLine == nil ? .pass : .flag,
            detail: chain.brokenLine == nil
                ? String(format: L("%lld sealed line(s) hold, %lld legacy line(s) predate the chain"),
                         chain.sealed, chain.legacy)
                : String(format: L("BROKEN at sealed line %lld"),
                         chain.brokenLine ?? 0)))

        let censusDetail = String(format: L("exposure %@ · tripwire %@"),
                                  Emcon.fmt(score.value),
                                  emcon.tripwireOn ? L("up") : L("DOWN"))
            + (emcon.unwatched.isEmpty
                ? L(" · every port watched")
                : String(format: L(" · %lld port(s) unwatched"),
                         emcon.unwatched.count))
        maneuverLegs.append(ManeuverLeg(
            name: L("Census"),
            outcome: emcon.tripwireOn && emcon.unwatched.isEmpty
                ? .pass : .flag,
            detail: censusDetail))

        guard mouth.serveRunning else {
            maneuverLegs.append(ManeuverLeg(
                name: L("Spar"), outcome: .skip,
                detail: L("Serve is down — no listener to test")))
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
        Section(header: Text(L("Night maneuvers")),
                footer: Text(L("The instrument reports for duty: the seal chain proves the record, the census reads the posture, the spar fires sixty mutations of a real capture at your own Serve. The grade goes into the sealed log either way."))) {
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
        Section(header: Text(L("Dead hand")),
                footer: Text(L("Arm it, then check in here — deliberately, with the button — before the interval runs out. If the app is next opened with the check-in overdue, the Knocktalk threads burn and EMCON rises before anything else happens. It falls at the next OPENING, not at the deadline: iOS gives no app a background timer worth trusting. The reminders are courtesies. Merely opening the app never counts as a check-in — that is the point of the hand."))) {
            Toggle(L("Arm the dead hand"), isOn: $deadHandOn)
                .onChange(of: deadHandOn) { on in
                    if on { emcon.deadHandArm() }
                    else { emcon.deadHandDisarm() }
                }
            if deadHandOn {
                Picker(L("Check in every"),
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
                    Text(L("THE HAND HAS FALLEN — threads burned, EMCON raised. Check in to re-arm it."))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                } else if let deadline = emcon.deadHandDeadline {
                    LabeledContent(
                        "Deadline",
                        value: deadline.formatted(
                            date: .abbreviated, time: .shortened))
                    if emcon.deadHandOverdue {
                        Text(L("OVERDUE — the hand falls at the next opening."))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Button {
                    emcon.deadHandCheckIn()
                } label: {
                    Label(L("Check in — I'm here"),
                          systemImage: "hand.raised.fill")
                }
            }
        }
    }

    private var hardeningSection: some View {
        Section(header: Text(L("Hardening — the OS half"))) {
            HStack {
                Text(L("This network"))
                Spacer()
                Text(emcon.currentSubnet.map { "\($0).0/24" }
                     ?? "not on Wi-Fi")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Text(L("Home turf"))
                Spacer()
                Text(emcon.homeSubnet.map { "\($0).0/24" } ?? "unmarked")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if emcon.currentSubnet != nil,
               emcon.currentSubnet != emcon.homeSubnet {
                Button {
                    Haptics.tap()
                    emcon.markHome()
                    toasts.show(L("Marked — EMCON will warn you off home turf."))
                } label: {
                    Label(L("Mark this network as home"),
                          systemImage: "house")
                }
            }
            if emcon.homeSubnet != nil {
                Button(role: .destructive) {
                    Haptics.tap()
                    emcon.unmarkHome()
                    toasts.show(L("Home turf unmarked."))
                } label: {
                    Label(L("Unmark home"), systemImage: "house.slash")
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
            Text(L("EMCON can verify the broadcast name and the app's emissions. These five live in Settings — check them off on your word."))
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
