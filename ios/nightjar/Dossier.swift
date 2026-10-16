import SwiftUI

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

    @EnvironmentObject private var post: ListeningPost
    @StateObject private var recon = Recon()

    private var bleMatches: [DeviceRow] {
        post.rows.filter { row in
            row.name == title || row.preferredLabel == title
        }
    }

    private var openHits: [Recon.Hit] {
        recon.hits.filter { $0.isOpen }
    }

    private var dossierText: String {
        var lines = ["DOSSIER — \(title)", ""]
        lines.append("Wi-Fi (Scan):")
        lines += wifiLines.map { "  \($0)" }
        lines.append("Bluetooth (Listen):")
        if bleMatches.isEmpty {
            lines.append("  not heard advertising under this name")
        } else {
            for row in bleMatches {
                lines.append("  possible match by name — \(row.kind), "
                             + "\(row.sightings) sightings")
            }
        }
        lines.append("Knock (Recon):")
        if recon.hits.isEmpty {
            lines.append("  not knocked from this page")
        } else if openHits.isEmpty {
            lines.append("  knocked \(recon.lastKnocked) — nothing open")
        } else {
            for hit in openHits {
                lines.append("  \(hit.label) \(hit.service)"
                             + (hit.confirmed ? " ★" : "")
                             + (hit.banner.isEmpty
                                ? "" : " — \(hit.banner)"))
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section(header: Text("Wi-Fi — Scan testifies")) {
                ForEach(wifiLines, id: \.self) { line in
                    Text(line).font(.callout)
                }
            }
            Section(header: Text("Bluetooth — Listen testifies")) {
                if bleMatches.isEmpty {
                    Text("Not heard advertising under this name. "
                         + "(Listen matches by name only — a name "
                         + "is a claim, not an identity.)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(bleMatches) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Possible match by name")
                                .font(.callout.weight(.semibold))
                            Text("\(row.kind) · \(row.sightings) "
                                 + "sightings · last RSSI "
                                 + "\(row.rssiLast.map(String.init) ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(header: Text("Knock — Recon testifies")) {
                if let ip = ip {
                    if recon.knocking {
                        HStack {
                            ProgressView()
                            Text("Knocking \(ip) — "
                                 + "\(recon.probed)/\(recon.total)")
                                .font(.callout)
                        }
                        Button("Cancel") { recon.cancelKnock() }
                    } else {
                        Button {
                            recon.knock(
                                host: ip,
                                ports: ReconPayloads.defaultPorts,
                                udp: false)
                        } label: {
                            Label("Knock \(ip) — full registry",
                                  systemImage: "hammer")
                        }
                    }
                    if !recon.hits.isEmpty {
                        if openHits.isEmpty {
                            Text("Nothing open.")
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
                } else {
                    Text("No address swept for this device yet — "
                         + "run a sweep on the Scan tab and its "
                         + "dossier gains a knock.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                ShareLink(item: dossierText) {
                    Label("Share the dossier",
                          systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(title)
    }
}
