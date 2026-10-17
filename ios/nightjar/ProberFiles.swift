import Foundation
import SwiftUI

/// A dossier for the other side of the wire: everyone who has
/// ever knocked on this phone, assembled from the tripwire log
/// and the canary's journal. The instrument already builds
/// dossiers for devices it finds (Scan tab); prober files are
/// the same courtesy extended to devices that found IT.
///
/// Everything here is testimony the phone itself collected:
/// when they came, which doors they tried, what their first
/// words said they were speaking — and whether they ever took
/// a honeydrop. Nothing is inferred beyond the record.
struct ProberFile: Identifiable {
    var id: String { host }
    let host: String
    var knocks = 0
    var firstSeen: Date
    var lastSeen: Date
    /// Port -> folded knock count.
    var ports: [Int: Int] = [:]
    /// Distinct first-word verdicts, in the order first heard.
    var verdicts: [String] = []
    /// Honeydrops this source has taken (from the journal).
    var drops = 0
    /// First-words byte prefixes (hex), one trait family for
    /// the same-hands correlation.
    var bytePrefixes: Set<String> = []
    /// This source is the phone itself (its events carry the
    /// label) — own addresses never take part in correlation.
    var isSelf = false
    /// Same-hands candidates: other addresses sharing enough
    /// of this file's habits, with the shared traits spelled
    /// out. Correlation over the phone's own log — a labeled
    /// suspicion, never an identification.
    var links: [(host: String, shared: [String])] = []

    /// The habit set correlation runs over: doors tried,
    /// vocabularies spoken, byte prefixes sent.
    var traits: Set<String> {
        var t = Set(ports.keys.map { "port:\($0)" })
        t.formUnion(verdicts.map { "word:\($0)" })
        t.formUnion(bytePrefixes.map { "bytes:\($0)" })
        return t
    }

    static func traitLabel(_ trait: String) -> String {
        if trait.hasPrefix("port:") {
            return "knocked port \(trait.dropFirst(5))"
        }
        if trait.hasPrefix("word:") {
            return "spoke \u{201C}\(trait.dropFirst(5))\u{201D}"
        }
        if trait.hasPrefix("bytes:") {
            return "first words began \(trait.dropFirst(6))…"
        }
        return trait
    }

    var portsByTraffic: [(port: Int, count: Int)] {
        ports.sorted { $0.value > $1.value }
            .map { (port: $0.key, count: $0.value) }
    }

    /// The port they knock most — the natural knock-back aim.
    var favoritePort: Int? { portsByTraffic.first?.port }

    /// The file as shareable text, in the dossier's voice.
    var text: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        var out = "Prober file — \(host)\n"
        out += "First seen \(fmt.string(from: firstSeen)); "
        out += "last seen \(fmt.string(from: lastSeen)).\n"
        out += "\(knocks) knock(s) across "
        out += "\(ports.count) port(s): "
        out += portsByTraffic
            .map { "\($0.port)×\($0.count)" }
            .joined(separator: ", ")
        out += "\n"
        if !verdicts.isEmpty {
            out += "First words heard:\n"
            for v in verdicts { out += "  · \(v)\n" }
        }
        if drops > 0 {
            out += "Took \(drops) honeydrop(s).\n"
        }
        out += "\nAssembled by nightjar-hack from its own "
        out += "tripwire log and journal — testimony, not "
        out += "attribution: an address is a claim about a "
        out += "network, not an identity."
        return out
    }
}

enum ProberFiles {
    /// Build every file from the retained tripwire events and
    /// the journal's honeydrop lines. The tripwire log is
    /// capped (200 events), so a file covers what the log
    /// still holds — the copy in the UI says so.
    static func build(events: [Emcon.TripEvent]) -> [ProberFile] {
        var byHost: [String: ProberFile] = [:]
        for e in events {
            let host = e.source
                .components(separatedBy: " ").first ?? e.source
            guard !host.isEmpty else { continue }
            var f = byHost[host] ?? ProberFile(
                host: host, firstSeen: e.when, lastSeen: e.when)
            let n = max(1, e.repeatCount)
            f.knocks += n
            f.firstSeen = min(f.firstSeen, e.when)
            f.lastSeen = max(f.lastSeen, e.when)
            f.ports[e.port, default: 0] += n
            if !f.verdicts.contains(e.verdict) {
                f.verdicts.append(e.verdict)
            }
            if let hex = e.bytesHex, hex.count >= 8 {
                f.bytePrefixes.insert(String(hex.prefix(8)))
            }
            if e.source.contains("(this device)") {
                f.isSelf = true
            }
            byHost[host] = f
        }
        // Honeydrop takes are journal lines naming the taker's
        // endpoint as "host:port" — anchor on the colon so a
        // short address can't match inside a longer one.
        for line in Journal.events(limit: 400)
        where line.module == "canary" && line.kind == "honeydrop" {
            for host in Array(byHost.keys)
            where line.text.contains(host + ":") {
                byHost[host]?.drops += 1
            }
        }
        var files = byHost.values.sorted {
            $0.lastSeen > $1.lastSeen
        }
        correlate(&files)
        return files
    }

    /// Same hands: two addresses whose habit sets overlap by
    /// at least half the smaller set, with at least three
    /// shared traits, are linked — in both directions, with
    /// the evidence attached. Own addresses never correlate
    /// (the phone answering itself is not a mystery).
    private static func correlate(_ files: inout [ProberFile]) {
        for i in files.indices where !files[i].isSelf {
            for j in files.indices
            where j != i && !files[j].isSelf {
                let mine = files[i].traits
                let theirs = files[j].traits
                let shared = mine.intersection(theirs)
                let smaller = min(mine.count, theirs.count)
                guard smaller > 0, shared.count >= 3,
                      Double(shared.count) / Double(smaller) >= 0.5
                else { continue }
                files[i].links.append((
                    host: files[j].host,
                    shared: shared.sorted().map(
                        ProberFile.traitLabel)))
            }
        }
    }

    // "Changed since you last looked": the last-seen stamp a
    // file carried when its detail was last opened, per host.
    private static func seenKey(_ host: String) -> String {
        "proberFileSeen.\(host)"
    }

    static func changed(_ file: ProberFile) -> Bool {
        let seen = UserDefaults.standard.double(
            forKey: seenKey(file.host))
        return file.lastSeen.timeIntervalSince1970 > seen
    }

    static func markSeen(_ file: ProberFile) {
        UserDefaults.standard.set(
            file.lastSeen.timeIntervalSince1970,
            forKey: seenKey(file.host))
    }
}

/// One prober's file, opened from the EMCON tab.
struct ProberFileView: View {
    let file: ProberFile
    @EnvironmentObject private var mouth: Mouth
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("The record")) {
                    LabeledContent("Address", value: file.host)
                    LabeledContent("Knocks",
                                     value: "\(file.knocks)")
                    LabeledContent(
                        "First seen",
                        value: file.firstSeen.formatted(
                            date: .abbreviated, time: .shortened))
                    LabeledContent(
                        "Last seen",
                        value: file.lastSeen.formatted(
                            date: .abbreviated, time: .shortened))
                    if file.drops > 0 {
                        LabeledContent(
                            "Honeydrops taken",
                            value: "\(file.drops)")
                    }
                }
                Section(header: Text("Doors tried")) {
                    ForEach(file.portsByTraffic, id: \.port) { row in
                        LabeledContent("Port \(row.port)",
                                       value: "×\(row.count)")
                    }
                }
                if !file.verdicts.isEmpty {
                    Section(header: Text("First words heard")) {
                        ForEach(file.verdicts, id: \.self) { v in
                            Text(v).font(.callout)
                        }
                    }
                }
                if !file.links.isEmpty {
                    Section(header: Text("Same hands?"),
                            footer: Text("Correlation over this "
                                + "phone's own tripwire log: "
                                + "shared habits suggest, they "
                                + "never prove. Two tenants of one "
                                + "NAT can share every trait here "
                                + "and still be strangers.")) {
                        ForEach(file.links, id: \.host) { link in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(link.host)
                                    .font(.callout.weight(.medium))
                                ForEach(link.shared, id: \.self) {
                                    trait in
                                    Text("· " + trait)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section(footer: Text("An address is a claim "
                    + "about a network, not an identity — "
                    + "addresses are borrowed, shared, and "
                    + "spoofed. The file records what knocked, "
                    + "never who.")) {
                    if let port = file.favoritePort,
                       !file.host.hasPrefix("127.") {
                        Button {
                            mouth.reconHandoff = Mouth.ReconHandoff(
                                host: file.host, port: port,
                                nonce: UUID())
                            dismiss()
                        } label: {
                            Label("Knock back at port \(port)",
                                  systemImage: "scope")
                        }
                    }
                    Button {
                        shareItem = ShareItem(items: [file.text])
                    } label: {
                        Label("Share this file",
                              systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Prober file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { ProberFiles.markSeen(file) }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.items)
        }
    }
}
