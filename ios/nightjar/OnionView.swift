import SwiftUI

// MARK: - OnionView
//
// The Onion room: the wrap around the house's
// own network life, and the LAYERS score that
// grades the whole device's posture as far as
// an app can honestly see it.
//
// The room is built on the standard
// (OnionStandard): the header carries the
// live score, its band, and the EMCON line
// (the condition and the floor it declares);
// the inventory shows every layer with its
// earned value and the evidence it was
// earned on; the wrap section works the
// SOCKS road; the roads table names what
// wraps, what doesn't yet, and what cannot;
// and the boundary card says plainly what
// this room can never do — torify the whole
// device. An app has no such road, and this
// room never pretends one.

struct OnionView: View {
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var emcon: Emcon
    @AppStorage("onion.wrap") private var wrapOn = false
    @State private var audit: OnionScore?
    @State private var hostDraft = ""
    @State private var portDraft = ""
    @State private var probing = false
    @State private var probeNote = ""

    var body: some View {
        NavigationStack {
            List {
                headerSection
                inventorySection
                wrapSection
                roadsSection
                boundarySection
            }
            // The backdrop is painted HERE,
            // behind the list itself — the
            // recipe the Vault and Knocktalk
            // proved on device.
            .scrollContentBackground(.hidden)
            .macColumn(880)
            .macListStyle()
            .background { AppBackdrop() }
            .navigationTitle(L("Onion"))
            .onAppear { refresh() }
        }
    }

    // MARK: The header — the score, live

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "circle.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading,
                       spacing: 2) {
                    Text(headerScoreText)
                        .font(.title3.weight(.bold))
                    Text(headerBandText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    refresh()
                } label: {
                    Label(L("Re-audit"),
                          systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            Text(emconLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var headerScoreText: String {
        guard let audit else { return "—" }
        return String(format: L("%@ of 7.0 layers"),
                      OnionStandard.fmt(audit.value))
    }

    private var headerBandText: String {
        guard let audit else {
            return L("the audit has not run yet")
        }
        return audit.band
    }

    private var emconLine: String {
        let floor = emcon.condition.onionFloor
        guard let audit else {
            return String(format: L(
                "%@ — its onion floor "
                + "is %@."),
                emcon.condition.declared,
                OnionStandard.fmt(floor))
        }
        let gap = OnionStandard.floorGap(
            audit, emcon.condition)
        if gap <= 0 {
            return String(format: L(
                "%@ — floor %@, met."),
                emcon.condition.declared,
                OnionStandard.fmt(floor))
        }
        return String(format: L(
            "%@ — floor %@, short "
            + "by %@."),
            emcon.condition.declared,
            OnionStandard.fmt(floor),
            OnionStandard.fmt(gap))
    }

    // MARK: The inventory — every layer, evidenced

    private var inventorySection: some View {
        Section(L("The layers")) {
            if let audit {
                ForEach(audit.rows) { row in
                    VStack(alignment: .leading,
                           spacing: 3) {
                        HStack {
                            Text(row.label)
                                .font(.body
                                    .weight(.medium))
                            Spacer()
                            Text(rowScoreText(row))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(
                                    row.earned
                                        >= row.maximum
                                        ? .green
                                        : .secondary)
                        }
                        Text(row.state)
                            .font(.caption)
                        Text(row.evidence)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                Text(L("No audit yet — one runs "
                    + "when the room opens."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowScoreText(_ row: OnionRow)
        -> String {
        String(format: "%@ / %@",
               OnionStandard.fmt(row.earned),
               OnionStandard.fmt(row.maximum))
    }

    // MARK: The wrap

    private var wrapSection: some View {
        Section(L("The wrap")) {
            Toggle(isOn: $wrapOn) {
                VStack(alignment: .leading,
                       spacing: 2) {
                    Text(L("Wrap the bench core"))
                    Text(L("Everything the shared "
                        + "bench core sends rides "
                        + "the Tor road."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: wrapOn) { newValue in
                OnionStandard.setWrap(newValue)
                refresh()
            }
            Text(L("Fail-closed: with the wrap on, "
                + "a down Tor road refuses the "
                + "connect — nothing is sent bare."))
                .font(.caption2)
                .foregroundStyle(.secondary)
            LabeledContent(L("SOCKS host")) {
                TextField("127.0.0.1",
                          text: $hostDraft)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(
                        .never)
            }
            LabeledContent(L("SOCKS port")) {
                TextField("9050", text: $portDraft)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
            }
            Button {
                Haptics.tap()
                OnionStandard.setEndpoint(
                    host: hostDraft,
                    port: Int(portDraft) ?? 9050)
                loadEndpointDrafts()
                refresh()
            } label: {
                Label(L("Keep this endpoint"),
                      systemImage: "checkmark.circle")
            }
            HStack {
                Text(L("The road"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(roadStatusText)
                    .font(.callout)
            }
            Button {
                Haptics.tap()
                runProbe()
            } label: {
                Label(probing
                      ? L("Knocking…")
                      : L("Run a Tor check"),
                      systemImage: "arrow.triangle"
                        + ".2.circlepath")
            }
            .disabled(probing)
            if !probeNote.isEmpty {
                Text(probeNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let refusal = OnionStandard
                .lastWrapRefusal {
                Label(refusal,
                      systemImage:
                        "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Button(role: .destructive) {
                Haptics.tap()
                OnionStandard.resetPosture()
                wrapOn = false
                loadEndpointDrafts()
                probeNote = ""
                refresh()
            } label: {
                Label(L("Reset the posture"),
                      systemImage: "arrow.counterclockwise")
            }
        }
    }

    private var roadStatusText: String {
        guard let probe = OnionStandard.lastProbe
        else {
            return L("never probed")
        }
        if probe.socksAnswered && probe.wrappedOK {
            if probe.isTor == true {
                return String(format: L(
                    "answers — the check says "
                    + "Tor (%@)"),
                    OnionStandard.probeAgeText(
                        probe.when))
            }
            return String(format: L(
                "answers (%@)"),
                OnionStandard.probeAgeText(
                    probe.when))
        }
        if probe.socksAnswered {
            return String(format: L(
                "answers, fetch failed (%@)"),
                OnionStandard.probeAgeText(
                    probe.when))
        }
        return String(format: L(
            "dark (%@)"),
            OnionStandard.probeAgeText(probe.when))
    }

    private func runProbe() {
        probing = true
        probeNote = ""
        OnionStandard.probeTor { record in
            probing = false
            if record.socksAnswered
                && record.wrappedOK {
                if record.isTor == true {
                    probeNote = String(format: L(
                        "The claim: the check "
                        + "service at %@ says "
                        + "this road exits "
                        + "through Tor — exit %@. "
                        + "Its word, reported as "
                        + "a claim."),
                        record.endpoint,
                        record.exitIP ?? "?")
                } else {
                    probeNote = String(format: L(
                        "The claim: the check "
                        + "service says this road "
                        + "does NOT exit through "
                        + "Tor (exit %@). The "
                        + "endpoint answered, but "
                        + "whatever it is, it is "
                        + "not a Tor road."),
                        record.exitIP ?? "?")
                }
            } else if record.socksAnswered {
                probeNote = String(format: L(
                    "The endpoint at %@ "
                    + "answered, but the "
                    + "wrapped fetch failed: %@"),
                    record.endpoint, record.problem)
            } else {
                probeNote = String(format: L(
                    "No SOCKS road answered — "
                    + "not 9050, not 9150, not "
                    + "%@: %@"),
                    record.endpoint, record.problem)
            }
            refresh()
        }
    }

    // MARK: The roads — what wraps, honestly

    private var roadsSection: some View {
        Section {
            DisclosureGroup(L("Which roads wrap")) {
                ForEach(OnionStandard.roads) { road in
                    VStack(alignment: .leading,
                           spacing: 3) {
                        HStack {
                            Text(road.family)
                                .font(.callout
                                    .weight(.medium))
                            Spacer()
                            Text(road.state)
                                .font(.caption
                                    .weight(.semibold))
                                .foregroundStyle(
                                    road.state
                                        == L("wraps")
                                        ? .green
                                        : .orange)
                        }
                        Text(road.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: The boundary — what this room cannot do

    private var boundarySection: some View {
        Section(L("The boundary")) {
            Text(L("This room wraps what THIS "
                + "app sends through its shared "
                + "core, and grades the posture "
                + "it can see. It cannot torify "
                + "the whole device: other apps "
                + "and the system keep their own "
                + "roads, and no app is given a "
                + "way to change that. For the "
                + "whole device, the road is a "
                + "Tor VPN app (Orbot is the one "
                + "this room's defaults assume) "
                + "carrying the default route — "
                + "the Tunnel layer above grades "
                + "exactly that. Anything this "
                + "audit cannot see, it names "
                + "unverifiable rather than "
                + "grading it blind."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Live reads

    private func refresh() {
        audit = OnionStandard.audit(
            emcon: emcon, mouth: mouth)
        loadEndpointDrafts()
    }

    private func loadEndpointDrafts() {
        hostDraft = OnionStandard.socksHost
        portDraft = String(OnionStandard.socksPort)
    }
}
