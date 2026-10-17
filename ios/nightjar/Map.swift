import SwiftUI

/// The Map — the house, on one canvas.
///
/// A special section of Scan: every neighbor the app keeps a
/// file on, placed by the operator in the room where the
/// device physically sits, so the wire can be investigated
/// with feet as well as packets. Placement is the operator's
/// testimony — a LAN address carries no coordinates, and the
/// map never pretends otherwise. What the app contributes is
/// memory: freshness, drift, and the dossier behind each
/// node, one tap away.

// MARK: - The kept map

struct MapRoom: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Normalized canvas coordinates, 0…1.
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct MapPlacement: Codable, Equatable {
    var x: Double
    var y: Double
}

final class MapStore: ObservableObject {
    static let shared = MapStore()

    @Published var rooms: [MapRoom] = []
    /// Where each neighbor sits, by IP, normalized 0…1.
    @Published var placements: [String: MapPlacement] = [:]
    /// Drift lines the operator has already laid eyes on.
    @Published var ackedDrift: [String: Int] = [:]

    private struct MapFile: Codable {
        var rooms: [MapRoom] = []
        var placements: [String: MapPlacement] = [:]
        var ackedDrift: [String: Int] = [:]
    }

    private static var fileURL: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("map.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let file = try? JSONDecoder().decode(
               MapFile.self, from: data) {
            rooms = file.rooms
            placements = file.placements
            ackedDrift = file.ackedDrift
        }
    }

    private func save() {
        let file = MapFile(rooms: rooms, placements: placements,
                           ackedDrift: ackedDrift)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    /// The room a point falls in, if any — membership is
    /// derived from position, never stored on the node.
    func room(atX x: Double, y: Double) -> MapRoom? {
        rooms.first {
            x >= $0.x && x <= $0.x + $0.w
                && y >= $0.y && y <= $0.y + $0.h
        }
    }

    func room(of ip: String) -> MapRoom? {
        guard let p = placements[ip] else { return nil }
        return room(atX: p.x, y: p.y)
    }

    func place(ip: String, x: Double, y: Double) {
        placements[ip] = MapPlacement(
            x: min(max(x, 0.02), 0.98),
            y: min(max(y, 0.02), 0.98))
        save()
    }

    func unplace(ip: String) {
        placements.removeValue(forKey: ip)
        save()
    }

    func addRoom(name: String) {
        let step = Double(rooms.count % 4) * 0.05
        rooms.append(MapRoom(
            id: UUID().uuidString,
            name: name.isEmpty ? "Room" : name,
            x: 0.08 + step, y: 0.08 + step, w: 0.36, h: 0.24))
        save()
    }

    func removeRoom(_ room: MapRoom) {
        rooms.removeAll { $0.id == room.id }
        save()
    }

    func ackDrift(ip: String, count: Int) {
        ackedDrift[ip] = count
        save()
    }
}

// MARK: - The door in Scan

struct MapSectionView: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var neighborhood =
        NeighborhoodStore.shared
    @Binding var shown: Bool

    var body: some View {
        Section(header: Text("The Map — the house, on one canvas"),
                footer: Text("Which device is what, and where "
                    + "in the real world it sits — placed by "
                    + "your hand, kept by the app. Walk the "
                    + "house with it.")) {
            Button {
                shown = true
            } label: {
                Label("Open the map", systemImage: "map")
            }
            Text(summary)
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let total = neighborhood.neighbors.count
        let placed = neighborhood.neighbors.filter {
            store.placements[$0.ip] != nil
        }.count
        if total == 0 {
            return "No devices yet — the Neighborhood fills "
                + "first, then the map gives them rooms."
        }
        return "\(placed) of \(total) devices placed "
            + "in \(store.rooms.count) room"
            + (store.rooms.count == 1 ? "" : "s")
            + " · \(total - placed) unplaced"
    }
}

// MARK: - The canvas

struct MapView: View {
    @ObservedObject var model: ScanModel
    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var neighborhood =
        NeighborhoodStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIP: String?
    @State private var dragIP: String?
    @State private var dragPoint: CGPoint?
    @State private var addingRoom = false
    @State private var newRoomName = ""
    @State private var dossierNeighbor: Neighbor?
    @State private var editingNeighbor: Neighbor?
    @State private var huntTarget: AirTarget?
    @EnvironmentObject var post: ListeningPost
    @ObservedObject private var themeCenter = ThemeCenter.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvas
                tray
                airStrip
            }
            .navigationTitle("The Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            model.sweep(port: 80)
                        } label: {
                            Label("Sweep the wire",
                                  systemImage: "scope")
                        }
                        Button {
                            addingRoom = true
                        } label: {
                            Label("Add a room",
                                  systemImage: "square.dashed")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .alert("Name the room", isPresented: $addingRoom) {
                TextField("Living room", text: $newRoomName)
                Button("Add") {
                    store.addRoom(name: newRoomName)
                    newRoomName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editingNeighbor) { neighbor in
                NeighborNameEditor(
                    store: NeighborhoodStore.shared,
                    neighbor: neighbor)
            }
            .sheet(item: $huntTarget) { target in
                HomingCompassView(targetID: target.id,
                                  label: target.label,
                                  kind: target.kind)
            }
            .sheet(item: $dossierNeighbor) { neighbor in
                NavigationStack {
                    DossierView(
                        title: neighbor.displayName,
                        ip: neighbor.ip,
                        wifiLines: neighborhood.wifiLines(
                            for: neighbor))
                    .toolbar {
                        ToolbarItem(
                            placement: .confirmationAction) {
                            Button("Done") {
                                dossierNeighbor = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                MatrixDots(color: themeCenter.current.accent
                    .opacity(0.13))
                MatrixSweep(color: themeCenter.current.accent)
                ForEach(store.rooms) { room in
                    roomView(room, in: geo.size)
                }
                ForEach(placedNeighbors) { neighbor in
                    nodeView(neighbor, in: geo.size)
                }
                if store.rooms.isEmpty
                    && placedNeighbors.isEmpty {
                    Text("Add a room, then tap a device below "
                         + "and tap where it sits. Drag placed "
                         + "devices to their exact spot.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(32)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard let ip = selectedIP else { return }
                        store.place(
                            ip: ip,
                            x: value.location.x / geo.size.width,
                            y: value.location.y / geo.size.height)
                        selectedIP = nil
                        Haptics.select()
                    })
        }
    }

    private func roomView(_ room: MapRoom,
                          in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(themeCenter.current.accent
                                .opacity(0.45),
                              lineWidth: 1)
            Text(room.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: room.w * size.width,
               height: room.h * size.height)
        .position(x: (room.x + room.w / 2) * size.width,
                  y: (room.y + room.h / 2) * size.height)
        .contextMenu {
            Button("Remove room", role: .destructive) {
                store.removeRoom(room)
            }
        }
    }

    private func nodeView(_ neighbor: Neighbor,
                          in size: CGSize) -> some View {
        let placement = store.placements[neighbor.ip]
            ?? MapPlacement(x: 0.5, y: 0.5)
        let live = dragIP == neighbor.ip ? dragPoint : nil
        let point = live ?? CGPoint(
            x: placement.x * size.width,
            y: placement.y * size.height)
        return NodeChip(
            neighbor: neighbor,
            selected: selectedIP == neighbor.ip,
            warm: neighbor.drift.count
                > (store.ackedDrift[neighbor.ip] ?? 0),
            roomName: store.room(of: neighbor.ip)?.name)
        .position(point)
        .onTapGesture {
            selectedIP = neighbor.ip
            store.ackDrift(ip: neighbor.ip,
                           count: neighbor.drift.count)
        }
        .onLongPressGesture {
            dossierNeighbor = neighbor
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragIP = neighbor.ip
                    dragPoint = value.location
                }
                .onEnded { value in
                    store.place(
                        ip: neighbor.ip,
                        x: value.location.x / size.width,
                        y: value.location.y / size.height)
                    dragIP = nil
                    dragPoint = nil
                })
    }

    // MARK: tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedIP == nil
                     ? "Unplaced — tap a device, then tap "
                         + "where it sits"
                     : "Now tap the canvas where it sits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ip = selectedIP,
                   let neighbor = neighborhood.neighbors.first(
                       where: { $0.ip == ip }) {
                    Button("Name\u{2026}") {
                        editingNeighbor = neighbor
                    }
                    .font(.caption.weight(.semibold))
                    Button("Dossier") {
                        dossierNeighbor = neighbor
                    }
                    .font(.caption.weight(.semibold))
                    Button("Unplace") {
                        store.unplace(ip: ip)
                        selectedIP = nil
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            if unplacedNeighbors.isEmpty {
                Text(neighborhood.neighbors.isEmpty
                     ? "No devices known yet."
                     : "Everything known has a place.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal,
                           showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(unplacedNeighbors) { neighbor in
                            NodeChip(
                                neighbor: neighbor,
                                selected: selectedIP
                                    == neighbor.ip,
                                warm: neighbor.drift.count
                                    > (store.ackedDrift[
                                        neighbor.ip] ?? 0),
                                roomName: nil)
                                .onTapGesture {
                                    selectedIP = neighbor.ip
                                    store.ackDrift(
                                        ip: neighbor.ip,
                                        count: neighbor
                                            .drift.count)
                                }
                                .onLongPressGesture {
                                    dossierNeighbor = neighbor
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Text("Long-press any device for its dossier. "
                 + "Placement is your testimony — the app "
                 + "keeps it, and never invents a location "
                 + "of its own.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: in the air

    /// What the ear is hearing right now, autonomously —
    /// and the door to walking to it.
    private var airStrip: some View {
        Section(header: Text("In the air — heard now"),
                footer: Text("The ear hears these on its "
                    + "own, no asking. Pick one and walk: "
                    + "the compass ring closes as you near "
                    + "it, and your steps teach it the way.")) {
            let heard = post.rows.filter {
                Date().timeIntervalSince1970 - $0.lastSeen < 90
                    && $0.rssiSmooth != nil
            }.sorted {
                ($0.rssiSmooth ?? -120)
                    > ($1.rssiSmooth ?? -120)
            }
            if heard.isEmpty {
                Text("Nothing fresh in the air. The ear "
                     + "wakes in Listen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(heard.prefix(6)) { row in
                Button {
                    huntTarget = AirTarget(
                        id: row.id,
                        label: row.name ?? row.preferredLabel
                            ?? row.kind,
                        kind: row.kind)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name
                                 ?? row.preferredLabel
                                 ?? row.kind)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(row.kind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.rssiSmooth.map {
                            "\(Int($0.rounded())) dBm"
                        } ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Image(systemName: "location.north.line")
                            .foregroundStyle(
                                themeCenter.current.accent)
                    }
                }
            }
        }
    }

    // MARK: sorting the cast

    private var placedNeighbors: [Neighbor] {
        neighborhood.neighbors.filter {
            store.placements[$0.ip] != nil
        }
    }

    private var unplacedNeighbors: [Neighbor] {
        neighborhood.neighbors.filter {
            store.placements[$0.ip] == nil
        }
    }
}

/// One device as a chip: its name, its wire facts compressed,
/// a ring that says how fresh it is, warmth when it has
/// drifted in ways nobody has laid eyes on yet.
private struct NodeChip: View {
    let neighbor: Neighbor
    let selected: Bool
    let warm: Bool
    let roomName: String?

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                if let mark = neighbor.customMark {
                    Image(systemName: mark)
                        .font(.caption2)
                }
                Text(neighbor.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ring, lineWidth: selected ? 3 : 2))
        .shadow(color: ring.opacity(0.55), radius: 7)
    }

    private var caption: String {
        var parts = ["\(neighbor.ports.count) ports"]
        if neighbor.arrivals > 0 {
            parts.append("knocked \(neighbor.arrivals)×")
        }
        if let roomName { parts.append(roomName) }
        return parts.joined(separator: " · ")
    }

    private var ring: Color {
        if warm { return .orange }
        let age = Date().timeIntervalSince(neighbor.lastSeen)
        if age < 300 { return .green }
        if age < 3600 { return .yellow }
        return Color(white: 0.45)
    }
}


/// A voice in the air, chosen for the walk.
struct AirTarget: Identifiable {
    let id: String
    let label: String
    let kind: String
}
