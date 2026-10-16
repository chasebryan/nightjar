import Foundation
import SwiftUI

/// The night log: one timeline for the whole instrument.
///
/// Until now each organ kept its own records — Listen its session
/// JSONL, Serve its inbox, EMCON its tripwire log — and none of
/// them could see the others. The journal is the shared ledger:
/// modules append one line per event worth remembering (a Serve
/// arrival, a tripwire knock, a posture change, a listening
/// session's bounds), and the Night Log view in the Sessions tab
/// reads them back as a single chronological record. The file is
/// JSONL — one object per line — so it feeds the same offline
/// tooling as every other nightjar log.
///
/// Deliberately human-scale: Listen journals its session bounds,
/// not every advertisement; the firehose stays in the session
/// files where it belongs.
struct NightEvent: Identifiable, Codable {
    var id: String
    var when: Date
    var module: String
    var kind: String
    var text: String
}

enum Journal {
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("nightjar-nightlog.jsonl")
    }

    private static let queue = DispatchQueue(label: "nightjar.journal")
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

    static func log(_ module: String, _ kind: String, _ text: String) {
        let event = NightEvent(id: UUID().uuidString, when: Date(),
                               module: module, kind: kind, text: text)
        queue.async {
            guard let data = try? encoder.encode(event) else { return }
            var line = data
            line.append(contentsOf: [0x0A])
            let url = fileURL
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url, options: .atomic)
            }
        }
    }

    /// Newest first, capped — the view's working set.
    static func events(limit: Int = 300) -> [NightEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var parsed: [NightEvent] = []
        for line in text.split(separator: "\n") {
            if let event = try? decoder.decode(
                NightEvent.self, from: Data(line.utf8)) {
                parsed.append(event)
            }
        }
        return Array(parsed.suffix(limit).reversed())
    }
}

struct NightLogView: View {
    @State private var events: [NightEvent] = []

    var body: some View {
        List {
            if events.isEmpty {
                Text("Nothing journaled yet. Serve arrivals, tripwire "
                     + "knocks, EMCON posture changes, sparring runs "
                     + "and listening-session bounds land here as one "
                     + "timeline — the whole instrument, one night at "
                     + "a time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(event.module.uppercased())
                            .font(.caption.weight(.bold))
                        Text(event.kind)
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(event.when.formatted(
                            date: .omitted, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.text).font(.callout)
                    Text(event.when.formatted(
                        date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !events.isEmpty {
                ShareLink(item: Journal.fileURL) {
                    Label("Share the night log (JSONL)",
                          systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Night log")
        .onAppear { events = Journal.events() }
    }
}
