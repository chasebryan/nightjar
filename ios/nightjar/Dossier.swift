import Foundation
import SwiftUI

/// Drift watch: the baselines dossiers keep.
///
/// A knock testifies about a moment. A baseline is that
/// testimony, kept — so the next knock on the same address can
/// be compared against it and the DIFFERENCE becomes the
/// testimony: a port that opened since, a service that went
/// silent. A device's own story changing is one of the
/// earliest signals that something happened to it; until now
/// nobody was keeping the old story. Baselines are keyed by
/// address and live in Documents/dossier-baselines.json.
enum DossierBaselines {
    struct Baseline: Codable {
        var when: Date
        var lines: [String]
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("dossier-baselines.json")
    }
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load() -> [String: Baseline] {
        guard let data = try? Data(contentsOf: fileURL),
              let all = try? decoder.decode(
                [String: Baseline].self, from: data)
        else { return [:] }
        return all
    }

    static func baseline(for ip: String) -> Baseline? {
        load()[ip]
    }

    static func set(_ baseline: Baseline, for ip: String) {
        var all = load()
        all[ip] = baseline
        if let data = try? encoder.encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// (opened since, closed since) — set differences both ways.
    static func diff(_ baseline: Baseline,
                     current: [String]) -> ([String], [String]) {
        let before = Set(baseline.lines)
        let now = Set(current)
        return (now.subtracting(before).sorted(),
                before.subtracting(now).sorted())
    }
}

/// A device dossier: everything the instrument knows about one
/// device, from every organ that has testified about it.
///
/// Scan testifies about Wi-Fi (it swept the address, or it heard
/// the Bonjour announcement). Listen testifies about Bluetooth —
/// a row whose name matches is a POSSIBLE match by name, labeled
/// as exactly that and no more: a name is not an identity. Recon
/// testifies on demand: knock the address now, with the full
/// probe registry, and the answers join the page.
struct DossierView: View {
    let title: String
    let ip: String?
    let wifiLines: [String]
    /// The name the device itself answers to on the
    /// wire — as distinct from the operator's given
    /// name in `title`. Bluetooth evidence is matched
    /// against this: a nickname matches nothing in
    /// the air.
    var wireName: String? = nil

    @EnvironmentObject private var post: ListeningPost
    @StateObject private var recon = Recon()
    @State private var baseline: DossierBaselines.Baseline?
    @State private var knockedOnce = false
    @State private var shareItem: ShareItem?
    @State private var driftOpened: [String] = []
    @State private var driftClosed: [String] = []

    private var bleMatches: [DeviceRow] {
        let matchName = wireName ?? title
        return post.rows.filter { row in
            row.name == matchName
                || row.preferredLabel == matchName
        }
    }

    private var openHits: [Recon.Hit] {
        recon.hits.filter { $0.isOpen }
    }

    /// The knock's testimony as comparable lines —
    /// port, service, banner, and whether the
    /// service confirmed itself. A port that still
    /// answers but banners a different service or
    /// version than the baseline knew IS drift;
    /// the old signature (port + service only) was
    /// blind to exactly that change.
    private var knockSignature: [String] {
        openHits.map { hit in
            let banner = hit.banner
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            return "\(hit.label) \(hit.service) \(banner) "
                + (hit.confirmed ? "confirmed" : "unconfirmed")
        }.sorted()
    }

    private var hasDrift: Bool {
        !driftOpened.isEmpty || !driftClosed.isEmpty
    }

    /// A knock just finished: if a baseline is kept for this
    /// address, the difference is the story — show it, and put
    /// it in the night log once.
    private func knockFinished() {
        knockedOnce = true
        guard let ip = ip, let baseline = baseline else { return }
        let (opened, closed) = DossierBaselines.diff(
            baseline, current: knockSignature)
        driftOpened = opened
        driftClosed = closed
        if !opened.isEmpty || !closed.isEmpty {
            let stamp = baseline.when.formatted(
                date: .abbreviated, time: .shortened)
            var parts: [String] = []
            if !opened.isEmpty {
                parts.append(L("opened ")
                    + opened.joined(separator: ", "))
            }
            if !closed.isEmpty {
                parts.append(L("closed ")
                    + closed.joined(separator: ", "))
            }
            Journal.log(
                "dossier", "drift",
                "\(title) (\(ip)) drifted since \(stamp): "
                + parts.joined(separator: "; "))
        }
    }

    private func takeBaseline() {
        guard let ip = ip else { return }
        let fresh = DossierBaselines.Baseline(
            when: Date(), lines: knockSignature)
        DossierBaselines.set(fresh, for: ip)
        baseline = fresh
        driftOpened = []
        driftClosed = []
        Journal.log("dossier", "baseline",
                    String(format: L("%@ (%@) baselined — %@ open"), String(describing: title), String(describing: ip), String(describing: knockSignature.count)))
    }

    private var dossierText: String {
        var lines = [String(format: L("DOSSIER — %@"), String(describing: title)), ""]
        lines.append(L("Wi-Fi (Scan):"))
        lines += wifiLines.map { "  \($0)" }
        lines.append(L("Bluetooth (Listen):"))
        if bleMatches.isEmpty {
            lines.append(L("  not heard advertising under this name"))
        } else {
            for row in bleMatches {
                lines.append(String(format: L("  possible match by name — %@, %@ sightings"), String(describing: row.kind), String(describing: row.sightings)))
            }
        }
        lines.append(L("Knock (Recon):"))
        if recon.hits.isEmpty {
            lines.append(L("  not knocked from this page"))
        } else if openHits.isEmpty {
            lines.append(String(format: L("  knocked %@ — nothing open"), String(describing: recon.lastKnocked)))
        } else {
            for hit in openHits {
                lines.append("  \(hit.label) \(hit.service)"
                             + (hit.confirmed ? " ★" : "")
                             + (hit.banner.isEmpty
                                ? "" : " — \(hit.banner)"))
            }
        }
        if let baseline = baseline {
            let stamp = baseline.when.formatted(
                date: .abbreviated, time: .shortened)
            lines.append(String(format: L("Baseline (%@):"), String(describing: stamp)))
            if baseline.lines.isEmpty {
                lines.append(L("  nothing open"))
            } else {
                lines += baseline.lines.map { "  \($0)" }
            }
            if hasDrift {
                lines.append(L("Drift since baseline:"))
                lines += driftOpened.map { String(format: L("  opened: %@"), String(describing: $0)) }
                lines += driftClosed.map { String(format: L("  closed: %@"), String(describing: $0)) }
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section(header: Text(L("Wi-Fi — Scan testifies"))) {
                ForEach(wifiLines, id: \.self) { line in
                    Text(line).font(.callout)
                }
            }
            Section(header: Text(L("Bluetooth — Listen testifies"))) {
                if bleMatches.isEmpty {
                    Text(L("Not heard advertising under this name. (Listen matches by name only — a name is a claim, not an identity.)"))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(bleMatches) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Possible match by name"))
                                .font(.callout.weight(.semibold))
                            Text(String(format: L("%@ · %lld sightings · last RSSI %@"), row.kind, row.sightings, row.rssiLast.map(String.init) ?? "—"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(header: Text(L("Knock — Recon testifies"))) {
                if let ip = ip {
                    if recon.knocking {
                        HStack {
                            ProgressView()
                            Text(String(format: L("Knocking %@ — %lld/%lld"), ip, recon.probed, recon.total))
                                .font(.callout)
                        }
                        Button(L("Cancel")) { recon.cancelKnock() }
                    } else {
                        Button {
                            recon.knock(
                                host: ip,
                                ports: ReconPayloads.defaultPorts,
                                udp: false)
                        } label: {
                            Label(String(format: L("Knock %@ — full registry"), ip),
                                  systemImage: "hammer")
                        }
                    }
                    if !recon.hits.isEmpty {
                        if openHits.isEmpty {
                            Text(L("Nothing open."))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(openHits) { hit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(hit.label) \(hit.service)"
                                     + (hit.confirmed ? " ★" : ""))
                                    .font(.callout.weight(.semibold))
                                if !hit.banner.isEmpty {
                                    Text(hit.banner)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if knockedOnce {
                        if let baseline = baseline {
                            Text(String(format: L("Baseline kept — %@, %lld open."),
                                        baseline.when.formatted(
                                            date: .abbreviated,
                                            time: .shortened),
                                        baseline.lines.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if hasDrift {
                                ForEach(driftOpened, id: \.self) {
                                    line in
                                    Label(String(format: L("Opened since: %@"), line),
                                          systemImage: "plus.circle")
                                        .font(.callout)
                                        .foregroundStyle(.green)
                                }
                                ForEach(driftClosed, id: \.self) {
                                    line in
                                    Label(String(format: L("Closed since: %@"), line),
                                          systemImage: "minus.circle")
                                        .font(.callout)
                                        .foregroundStyle(.red)
                                }
                            } else if !recon.hits.isEmpty {
                                Text(L("No drift — it answers exactly as baselined."))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                takeBaseline()
                            } label: {
                                Label(L("Update the baseline to now"),
                                      systemImage: "arrow.clockwise")
                            }
                        } else {
                            Button {
                                takeBaseline()
                            } label: {
                                Label(L("Keep this knock as the baseline"),
                                      systemImage: "bookmark")
                            }
                        }
                    }
                } else {
                    Text(L("No address swept for this device yet — run a sweep on the Scan tab and its dossier gains a knock."))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Haptics.tap()
                    shareItem = ShareItem(items: [dossierText])
                } label: {
                    Label(L("Share the dossier"),
                          systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(title)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
        .onAppear {
            if let ip = ip {
                baseline = DossierBaselines.baseline(for: ip)
            }
        }
        .onChange(of: recon.knocking) { knocking in
            if !knocking { knockFinished() }
        }
    }
}


// MARK: - The dossier, presented

/// A dossier as a sheet carries its evidence with it, so
/// any section can present it whole.
struct DossierPresentation: Identifiable {
    let id = UUID()
    let title: String
    let ip: String?
    let wifiLines: [String]
    var wireName: String? = nil
}

/// The dossier as a sheet: its own single stack, one Done —
/// the standing cure for the doubled back chevron that a
/// push inside a More-tab screen kept producing (the same
/// cure Colours took).
struct DossierSheetView: View {
    let presentation: DossierPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DossierView(title: presentation.title,
                        ip: presentation.ip,
                        wifiLines: presentation.wifiLines,
                        wireName: presentation.wireName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                }
        }
    }
}
