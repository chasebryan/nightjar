import SwiftUI

/// The Neighborhood: a cast of characters for your own wire.
///
/// Dossiers testify on demand — knock, and a page is written.
/// The neighborhood is the opposite posture: it only ever
/// WATCHES. Every sweep Scan runs, every Bonjour announcement
/// that resolves, every knock that arrives at this phone's
/// own door adds a line to a standing file on the device
/// that owns the address. Over weeks the wire stops being a
/// list of numbers and becomes a cast: the television that
/// answers at all hours, the laptop that appears at nine and
/// vanishes at five, the stranger who knocked once in March
/// and never again.
///
/// The boundary is the same one the whole instrument keeps:
/// this is the operator's own network, observed by the
/// operator's own phone, from traffic the phone itself sent
/// or received. Nothing is followed off the wire, and a
/// neighbor is an address — never a person.
struct Neighbor: Codable, Identifiable {
    var id: String { ip }
    var ip: String
    var name: String?
    var firstSeen: Date
    var lastSeen: Date
    var sightings = 0
    /// Ports this address has ever answered on, ascending.
    var ports: [Int] = []
    /// Bonjour labels it announces, in full ("_ssh._tcp — Mac").
    var announcements: [String] = []
    /// Times it knocked THIS phone (Serve / tripwire arrivals).
    var arrivals = 0
    /// The newest stories first, capped.
    var drift: [String] = []

    var displayName: String { name ?? ip }

    var lastSeenLine: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return "last seen " + fmt.localizedString(
            for: lastSeen, relativeTo: Date())
    }
}

final class NeighborhoodStore: ObservableObject {
    static let shared = NeighborhoodStore()

    @Published private(set) var neighbors: [Neighbor] = []

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("neighborhood.json")
    }

    init() { load() }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? decoder.decode(
                  [Neighbor].self, from: data)
        else { neighbors = []; return }
        neighbors = decoded.sorted {
            $0.lastSeen > $1.lastSeen
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(neighbors) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// The one mutation door: every feed arrives on the main
    /// queue, upserts its neighbor, and journals what is NEWS
    /// — a first sighting, a new port, a changed name. Routine
    /// re-sightings are tallied in silence.
    private func upsert(ip: String,
                        mutate: @escaping (inout Neighbor,
                                           Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.neighbors.firstIndex(
                where: { $0.ip == ip }) {
                var neighbor = self.neighbors[index]
                mutate(&neighbor, false)
                neighbor.lastSeen = Date()
                neighbor.sightings += 1
                self.neighbors[index] = neighbor
            } else {
                var neighbor = Neighbor(ip: ip, name: nil,
                                        firstSeen: Date(),
                                        lastSeen: Date())
                mutate(&neighbor, true)
                neighbor.sightings = 1
                self.neighbors.append(neighbor)
                Journal.log("neighborhood", "new",
                            "a new neighbor at \(ip) — the wire "
                            + "has one more character")
            }
            self.neighbors.sort { $0.lastSeen > $1.lastSeen }
            self.save()
        }
    }

    private func noteDrift(_ neighbor: inout Neighbor,
                           _ line: String) {
        neighbor.drift.insert(line, at: 0)
        if neighbor.drift.count > 10 {
            neighbor.drift.removeLast(neighbor.drift.count - 10)
        }
        Journal.log("neighborhood", "drift",
                    "\(neighbor.displayName) (\(neighbor.ip)): "
                    + line)
    }

    // MARK: - the three feeds

    /// Scan's /24 sweep answered: who is up, on this port.
    func recordSweep(_ hosts: [SweepHost]) {
        let byIP = Dictionary(grouping: hosts, by: { $0.ip })
        for (ip, answers) in byIP {
            upsert(ip: ip) { neighbor, isNew in
                for answer in answers
                where !neighbor.ports.contains(answer.port) {
                    neighbor.ports.append(answer.port)
                    neighbor.ports.sort()
                    if !isNew {
                        self.noteDrift(&neighbor,
                                  "answered on port "
                                  + "\(answer.port) "
                                  + "(\(ScanModel.serviceNames[answer.port] ?? "unknown")) "
                                  + "for the first time")
                    }
                }
            }
        }
    }

    /// A Bonjour announcement, resolved to its address.
    func recordBonjour(ip: String, name: String, label: String) {
        upsert(ip: ip) { neighbor, isNew in
            if let old = neighbor.name, old != name, !isNew {
                self.noteDrift(&neighbor,
                          "announces itself as \u{201C}\(name)\u{201D} now — "
                          + "it was \u{201C}\(old)\u{201D}")
            }
            if neighbor.name == nil || neighbor.name != name {
                neighbor.name = name
            }
            let line = "\(label) — \(name)"
            if !neighbor.announcements.contains(line) {
                neighbor.announcements.append(line)
                if !isNew {
                    self.noteDrift(&neighbor,
                              "began announcing \(label)")
                }
            }
        }
    }

    /// It knocked US: a Serve or tripwire arrival.
    func recordArrival(ip: String) {
        upsert(ip: ip) { neighbor, _ in
            neighbor.arrivals += 1
        }
    }

    /// Pull a LAN IPv4 address out of an arrival's source
    /// label, or nothing: the ghost, relay peers, this device,
    /// and loopback are not neighbors.
    static func lanIPv4(from source: String) -> String? {
        guard !source.contains("(this device)"),
              !source.hasPrefix("relay:") else { return nil }
        let head = source.split(separator: ":").first
            .map(String.init) ?? source
        let parts = head.split(separator: ".")
        guard parts.count == 4,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.allSatisfy(\.isNumber)
                      && Int(part) != nil && Int(part)! <= 255
              }),
              parts[0] != "127"
        else { return nil }
        return head
    }

    /// The neighbor's testimony, as the dossier page takes it.
    func wifiLines(for neighbor: Neighbor) -> [String] {
        var lines: [String] = []
        let stamp = neighbor.firstSeen.formatted(
            date: .abbreviated, time: .shortened)
        lines.append("On the wire since \(stamp) — "
                     + "\(neighbor.sightings) sightings, "
                     + neighbor.lastSeenLine)
        for port in neighbor.ports {
            lines.append("Answered on \(port)/tcp "
                         + "(\(ScanModel.serviceNames[port] ?? "unknown"))")
        }
        for announcement in neighbor.announcements {
            lines.append("Announces itself via Bonjour: "
                         + announcement)
        }
        if neighbor.arrivals > 0 {
            lines.append("Knocked this phone "
                         + "\(neighbor.arrivals) time(s)")
        }
        for line in neighbor.drift.prefix(5) {
            lines.append("Drift: " + line)
        }
        lines.append("Census: the neighborhood — observed, "
                     + "never knocked for this page")
        return lines
    }
}

/// Scan's neighborhood board: every character on the wire,
/// each opening into its full dossier.
struct NeighborhoodSectionView: View {
    @ObservedObject var store: NeighborhoodStore

    var body: some View {
        Section(header: Text("The Neighborhood — this wire, kept"),
                footer: Text("Fed only by what this phone "
                    + "itself observes: sweeps it ran, "
                    + "announcements it heard, knocks at its own "
                    + "door. An address is a character, never a "
                    + "person — and nothing here is followed "
                    + "off this network.")) {
            if store.neighbors.isEmpty {
                Text("No neighbors yet. Run a sweep, let "
                     + "Bonjour resolve, or simply be knocked — "
                     + "the wire will populate its own cast.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(store.neighbors) { neighbor in
                NavigationLink {
                    DossierView(
                        title: neighbor.displayName,
                        ip: neighbor.ip,
                        wifiLines: store.wifiLines(for: neighbor))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(neighbor.displayName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(neighborCaption(neighbor))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func neighborCaption(_ neighbor: Neighbor) -> String {
        var parts: [String] = []
        if neighbor.name != nil { parts.append(neighbor.ip) }
        parts.append("\(neighbor.sightings) sightings")
        parts.append(neighbor.lastSeenLine)
        if !neighbor.ports.isEmpty {
            parts.append("ports " + neighbor.ports
                .map(String.init).joined(separator: ", "))
        }
        if neighbor.arrivals > 0 {
            parts.append("knocked us \(neighbor.arrivals)×")
        }
        if let latest = neighbor.drift.first {
            parts.append("drift: " + latest)
        }
        return parts.joined(separator: " · ")
    }
}
