import SwiftUI

/// The Map — the house, on one canvas.
///
/// A special section of Scan: every device the app keeps a
/// file on — on the wire or in the air — placed by the
/// operator in the room where it physically sits, so the
/// world can be investigated with feet as well as packets.
/// Placement is the operator's testimony: an address
/// carries no coordinates, and the map never pretends
/// otherwise, never moves a node on signal's say-so. What
/// the app contributes is intelligence AROUND the
/// testimony: freshness, drift shown rather than silently
/// acknowledged, batteries and claims from the SIGINT
/// registry on every node's inspector, rooms that can be
/// moved, resized and renamed, lenses that cut the
/// canvas down to what matters, and the SIGINT watch
/// riding over it all.

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

/// A node on the map, named the way the SIGINT
/// registry names its emitters — one identity
/// language across the house.
enum MapNodeRef: Identifiable, Equatable {
    case lan(String)
    case ble(String)

    var key: String {
        switch self {
        case .lan(let ip): return "lan:" + ip
        case .ble(let id): return "ble:" + id
        }
    }
    var id: String { key }
}

final class MapStore: ObservableObject {
    static let shared = MapStore()

    @Published var rooms: [MapRoom] = []
    /// Where each node sits, by emitter key
    /// ("lan:<ip>", "ble:<peripheral id>"),
    /// normalized 0…1.
    @Published var placements: [String: MapPlacement] = [:]
    /// Drift counts the operator has laid eyes on,
    /// by emitter key.
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
            // Migration: placements were once keyed
            // by bare IP. The key gains its channel
            // prefix; the testimony itself is
            // untouched.
            placements = Dictionary(uniqueKeysWithValues:
                file.placements.map { key, value in
                    (key.contains(":") ? key : "lan:" + key,
                     value)
                })
            ackedDrift = Dictionary(uniqueKeysWithValues:
                file.ackedDrift.map { key, value in
                    (key.contains(":") ? key : "lan:" + key,
                     value)
                })
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

    func room(ofKey key: String) -> MapRoom? {
        guard let p = placements[key] else { return nil }
        return room(atX: p.x, y: p.y)
    }

    func place(key: String, x: Double, y: Double) {
        placements[key] = MapPlacement(
            x: min(max(x, 0.02), 0.98),
            y: min(max(y, 0.02), 0.98))
        save()
    }

    func unplace(key: String) {
        placements.removeValue(forKey: key)
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

    /// Move, resize or rename a room, clamped to
    /// the canvas — rooms stay usable rectangles,
    /// never slivers off the edge.
    func updateRoom(_ room: MapRoom) {
        guard let index = rooms.firstIndex(
            where: { $0.id == room.id }) else { return }
        var room = room
        room.w = min(max(room.w, 0.14), 0.96)
        room.h = min(max(room.h, 0.10), 0.96)
        room.x = min(max(room.x, 0), 1 - room.w)
        room.y = min(max(room.y, 0), 1 - room.h)
        room.name = room.name.trimmingCharacters(
            in: .whitespaces)
        if room.name.isEmpty { room.name = "Room" }
        rooms[index] = room
        save()
    }

    func removeRoom(_ room: MapRoom) {
        rooms.removeAll { $0.id == room.id }
        save()
    }

    /// Keep only the given emitter keys' placements
    /// and drift acknowledgements — the rest are
    /// ghosts of devices the house no longer keeps.
    func prune(to keys: Set<String>) {
        placements = placements.filter { keys.contains($0.key) }
        ackedDrift = ackedDrift.filter { keys.contains($0.key) }
        save()
    }

    /// The map starts over: no rooms, no placements.
    /// The devices themselves are untouched — only
    /// where they sat is forgotten.
    func reset() {
        rooms = []
        placements = [:]
        ackedDrift = [:]
        save()
    }

    func ackDrift(key: String, count: Int) {
        ackedDrift[key] = count
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
            store.placements["lan:" + $0.ip] != nil
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
    @ObservedObject private var station = SigintStation.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var selectedKey: String?
    @State private var dragKey: String?
    @State private var dragPoint: CGPoint?
    @State private var roomDrag: (id: String, start: MapRoom,
                                  resize: Bool)?
    @State private var addingRoom = false
    @State private var newRoomName = ""
    @State private var editingRoom: MapRoom?
    @State private var dossierNeighbor: Neighbor?
    @State private var editingNeighbor: Neighbor?
    @State private var inspector: MapNodeRef?
    @State private var huntTarget: AirTarget?
    @State private var confirmReset = false
    @State private var lens: Lens = .all
    @State private var search = ""
    @State private var startingWatch = false
    @State private var watchNameDraft = ""
    @EnvironmentObject var post: ListeningPost
    @ObservedObject private var themeCenter = ThemeCenter.shared

    enum Lens: String, CaseIterable {
        case all = "All"
        case live = "Live"
        case drift = "Drift"
        case air = "Air"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let watch = station.currentWatch {
                    watchRibbon(watch.watch.name)
                }
                lensBar
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
                        if station.currentWatch == nil {
                            Button {
                                startingWatch = true
                            } label: {
                                Label("Start a SIGINT watch",
                                      systemImage: "eye")
                            }
                        }
                        Button(role: .destructive) {
                            confirmReset = true
                        } label: {
                            Label("Reset the map\u{2026}",
                                  systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog(
                "Reset the map?",
                isPresented: $confirmReset,
                titleVisibility: .visible) {
                Button("Remove every room and placement",
                       role: .destructive) {
                    store.reset()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The devices stay in the Neighborhood — "
                     + "only where they sat is forgotten.")
            }
            .alert("Name the room", isPresented: $addingRoom) {
                TextField("Living room", text: $newRoomName)
                Button("Add") {
                    store.addRoom(name: newRoomName)
                    newRoomName = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Name the watch",
                   isPresented: $startingWatch) {
                TextField("Evening watch",
                          text: $watchNameDraft)
                Button("Begin") {
                    station.startWatch(
                        name: watchNameDraft
                            .trimmingCharacters(
                                in: .whitespaces).isEmpty
                            ? "Map watch"
                            : watchNameDraft,
                        scope: "map", post: post)
                    watchNameDraft = ""
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $editingNeighbor) { neighbor in
                NeighborNameEditor(
                    store: NeighborhoodStore.shared,
                    neighbor: neighbor)
            }
            .sheet(item: $editingRoom) { room in
                RoomEditor(room: room)
            }
            .sheet(item: $huntTarget) { target in
                HomingCompassView(targetID: target.id,
                                  label: target.label,
                                  kind: target.kind)
            }
            .sheet(item: $inspector) { ref in
                MapNodeInspector(
                    ref: ref,
                    onDossier: { neighbor in
                        inspector = nil
                        dossierNeighbor = neighbor
                    },
                    onRename: { neighbor in
                        inspector = nil
                        editingNeighbor = neighbor
                    },
                    onHunt: { target in
                        inspector = nil
                        huntTarget = target
                    },
                    onMove: { key in
                        inspector = nil
                        selectedKey = key
                    })
            }
            .sheet(item: $dossierNeighbor) { neighbor in
                NavigationStack {
                    DossierView(
                        title: neighbor.displayName,
                        ip: neighbor.ip,
                        wifiLines: neighborhood.wifiLines(
                            for: neighbor),
                        wireName: neighbor.name)
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

    // MARK: the watch ribbon

    private func watchRibbon(_ name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Watching — \(name)")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(station.newSinceWatchStart()) new "
                     + "since it began · this epoch only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Stop & file") {
                station.stopWatch(post: post)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.red.opacity(0.12))
    }

    // MARK: the lens bar

    private var lensBar: some View {
        HStack(spacing: 8) {
            ForEach(Lens.allCases, id: \.self) { option in
                Button {
                    lens = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(lens == option
                                ? themeCenter.current.accent
                                    .opacity(0.35)
                                : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Find", text: $search)
                    .font(.caption)
                    .frame(maxWidth: 110)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: canvas

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                MatrixDots(color: themeCenter.current.accent
                    .opacity(0.13))
                if !reduceMotion {
                    MatrixSweep(color: themeCenter.current.accent)
                }
                ForEach(store.rooms) { room in
                    roomView(room, in: geo.size)
                }
                ForEach(placedLAN) { neighbor in
                    nodeView(neighbor, in: geo.size)
                }
                ForEach(placedBLE, id: \.id) { row in
                    bleNodeView(row, in: geo.size)
                }
                if store.rooms.isEmpty
                    && placedLAN.isEmpty && placedBLE.isEmpty {
                    Text("Add a room, then tap a device below "
                         + "and tap where it sits. Drag placed "
                         + "devices to their exact spot, drag "
                         + "a room to move it, and long-press "
                         + "anything for its record.")
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
                        guard let key = selectedKey else { return }
                        store.place(
                            key: key,
                            x: value.location.x / geo.size.width,
                            y: value.location.y / geo.size.height)
                        selectedKey = nil
                        Haptics.select()
                    })
        }
    }

    private func roomView(_ room: MapRoom,
                          in size: CGSize) -> some View {
        let digest = roomDigest(room)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(themeCenter.current.accent
                                .opacity(0.45),
                              lineWidth: 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(room.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !digest.isEmpty {
                    Text(digest)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            // The resize grip, bottom-right.
            Circle()
                .fill(themeCenter.current.accent.opacity(0.5))
                .frame(width: 14, height: 14)
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity,
                       alignment: .bottomTrailing)
                .padding(5)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if roomDrag?.id != room.id {
                                roomDrag = (room.id, room, true)
                            }
                            guard let start = roomDrag?.start
                            else { return }
                            var next = start
                            next.w = start.w
                                + Double(value.translation.width)
                                    / Double(size.width)
                            next.h = start.h
                                + Double(value.translation.height)
                                    / Double(size.height)
                            store.updateRoom(next)
                        }
                        .onEnded { _ in roomDrag = nil })
        }
        .frame(width: room.w * size.width,
               height: room.h * size.height)
        .position(x: (room.x + room.w / 2) * size.width,
                  y: (room.y + room.h / 2) * size.height)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if roomDrag?.id != room.id {
                        roomDrag = (room.id, room, false)
                    }
                    guard let drag = roomDrag,
                          !drag.resize,
                          let start = roomDrag?.start
                    else { return }
                    var next = start
                    next.x = start.x
                        + Double(value.translation.width)
                            / Double(size.width)
                    next.y = start.y
                        + Double(value.translation.height)
                            / Double(size.height)
                    store.updateRoom(next)
                }
                .onEnded { _ in roomDrag = nil })
        .onLongPressGesture {
            editingRoom = room
        }
        .contextMenu {
            Button("Edit room\u{2026}") {
                editingRoom = room
            }
            Button("Remove room", role: .destructive) {
                store.removeRoom(room)
            }
        }
    }

    /// "3 here · 1 drift" — the room's census at a
    /// glance, counted from the placements that
    /// fall inside it.
    private func roomDigest(_ room: MapRoom) -> String {
        var here = 0
        var drifting = 0
        for neighbor in placedLAN {
            guard let placement = store.placements[
                "lan:" + neighbor.ip],
                  store.room(atX: placement.x,
                             y: placement.y)?.id == room.id
            else { continue }
            here += 1
            if neighbor.drift.count
                > (store.ackedDrift["lan:" + neighbor.ip]
                   ?? 0) {
                drifting += 1
            }
        }
        for row in placedBLE {
            guard let placement = store.placements[
                "ble:" + row.id],
                  store.room(atX: placement.x,
                             y: placement.y)?.id == room.id
            else { continue }
            here += 1
        }
        if here == 0 { return "" }
        var text = "\(here) here"
        if drifting > 0 { text += " · \(drifting) drift" }
        return text
    }

    private func nodeView(_ neighbor: Neighbor,
                          in size: CGSize) -> some View {
        let key = "lan:" + neighbor.ip
        let placement = store.placements[key]
            ?? MapPlacement(x: 0.5, y: 0.5)
        let live = dragKey == key ? dragPoint : nil
        let point = live ?? CGPoint(
            x: placement.x * size.width,
            y: placement.y * size.height)
        return NodeChip(
            neighbor: neighbor,
            selected: selectedKey == key,
            warm: neighbor.drift.count
                > (store.ackedDrift[key] ?? 0),
            roomName: store.room(ofKey: key)?.name)
        .opacity(matches(.lan(neighbor.ip)) ? 1 : 0.25)
        .position(point)
        .onTapGesture {
            inspector = .lan(neighbor.ip)
        }
        .onLongPressGesture {
            dossierNeighbor = neighbor
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragKey = key
                    dragPoint = value.location
                }
                .onEnded { value in
                    store.place(
                        key: key,
                        x: value.location.x / size.width,
                        y: value.location.y / size.height)
                    dragKey = nil
                    dragPoint = nil
                })
    }

    private func bleNodeView(_ row: DeviceRow,
                              in size: CGSize) -> some View {
        let key = "ble:" + row.id
        let placement = store.placements[key]
            ?? MapPlacement(x: 0.5, y: 0.5)
        let live = dragKey == key ? dragPoint : nil
        let point = live ?? CGPoint(
            x: placement.x * size.width,
            y: placement.y * size.height)
        return BleNodeChip(row: row,
                           selected: selectedKey == key)
            .opacity(matches(.ble(row.id)) ? 1 : 0.25)
            .position(point)
            .onTapGesture {
                inspector = .ble(row.id)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragKey = key
                        dragPoint = value.location
                    }
                    .onEnded { value in
                        store.place(
                            key: key,
                            x: value.location.x / size.width,
                            y: value.location.y / size.height)
                        dragKey = nil
                        dragPoint = nil
                    })
    }

    // MARK: tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedKey == nil
                     ? "Unplaced — tap a device, then tap "
                         + "where it sits"
                     : "Now tap the canvas where it sits")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let key = selectedKey {
                    Button("Cancel") { selectedKey = nil }
                        .font(.caption.weight(.semibold))
                }
            }
            if trayLAN.isEmpty && trayBLE.isEmpty {
                Text(neighborhood.neighbors.isEmpty
                     && post.rows.isEmpty
                     ? "No devices known yet."
                     : "Everything known has a place.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal,
                           showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trayLAN) { neighbor in
                            NodeChip(
                                neighbor: neighbor,
                                selected: selectedKey
                                    == "lan:" + neighbor.ip,
                                warm: neighbor.drift.count
                                    > (store.ackedDrift[
                                        "lan:" + neighbor.ip]
                                       ?? 0),
                                roomName: nil)
                                .onTapGesture {
                                    selectedKey = "lan:"
                                        + neighbor.ip
                                }
                                .onLongPressGesture {
                                    dossierNeighbor = neighbor
                                }
                        }
                        ForEach(trayBLE, id: \.id) { row in
                            BleNodeChip(
                                row: row,
                                selected: selectedKey
                                    == "ble:" + row.id)
                                .onTapGesture {
                                    selectedKey = "ble:" + row.id
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Text("Tap a placed device for its inspector — "
                 + "drift is acknowledged there, by eye, "
                 + "never silently. Placement is your "
                 + "testimony — the app keeps it, and "
                 + "never invents a location of its own.")
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
                            Text(row.subtitleLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

    // MARK: sorting the cast — lens and search

    private func matches(_ ref: MapNodeRef) -> Bool {
        let needle = search.trimmingCharacters(
            in: .whitespaces).lowercased()
        switch ref {
        case .lan(let ip):
            guard let neighbor = neighborhood.neighbors
                .first(where: { $0.ip == ip }) else {
                return false
            }
            switch lens {
            case .all: break
            case .live:
                if Date().timeIntervalSince(
                    neighbor.lastSeen) >= 300 { return false }
            case .drift:
                if neighbor.drift.count
                    <= (store.ackedDrift["lan:" + ip] ?? 0) {
                    return false
                }
            case .air: return false
            }
            if needle.isEmpty { return true }
            return neighbor.displayName.lowercased()
                .contains(needle)
                || ip.contains(needle)
        case .ble(let id):
            guard let row = post.rows.first(
                where: { $0.id == id }) else { return false }
            switch lens {
            case .all: break
            case .live:
                if Date().timeIntervalSince1970
                    - row.lastSeen >= 300 { return false }
            case .drift:
                if !row.trackerShaped
                    && row.payloadChanges == 0 {
                    return false
                }
            case .air: break
            }
            if needle.isEmpty { return true }
            return (row.name ?? row.preferredLabel
                    ?? row.kind).lowercased()
                .contains(needle)
                || row.kind.lowercased().contains(needle)
        }
    }

    private var placedLAN: [Neighbor] {
        neighborhood.neighbors.filter {
            store.placements["lan:" + $0.ip] != nil
        }
    }

    private var placedBLE: [DeviceRow] {
        post.rows.filter {
            store.placements["ble:" + $0.id] != nil
        }
    }

    private var trayLAN: [Neighbor] {
        neighborhood.neighbors.filter {
            store.placements["lan:" + $0.ip] == nil
                && matches(.lan($0.ip))
        }
    }

    private var trayBLE: [DeviceRow] {
        post.rows.filter {
            store.placements["ble:" + $0.id] == nil
                && matches(.ble($0.id))
        }
        .sorted { $0.lastSeen > $1.lastSeen }
        .prefix(14)
        .map { $0 }
    }
}

// MARK: - The room editor

private struct RoomEditor: View {
    @ObservedObject private var store = MapStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MapRoom
    @State private var confirmRemove = false

    init(room: MapRoom) {
        _draft = State(initialValue: room)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Room name", text: $draft.name)
                }
                Section("Shape") {
                    slider("Left", $draft.x, 0...0.85)
                    slider("Top", $draft.y, 0...0.85)
                    slider("Width", $draft.w, 0.14...0.96)
                    slider("Height", $draft.h, 0.10...0.96)
                }
                Section {
                    Button("Remove room",
                           role: .destructive) {
                        confirmRemove = true
                    }
                } footer: {
                    Text("Devices placed in it keep their "
                         + "spots — only the room is "
                         + "forgotten.")
                }
            }
            .navigationTitle("Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateRoom(draft)
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Remove this room?",
                isPresented: $confirmRemove,
                titleVisibility: .visible) {
                Button("Remove room", role: .destructive) {
                    store.removeRoom(draft)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private func slider(_ label: String,
                        _ value: Binding<Double>,
                        _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).font(.callout)
            Slider(value: value, in: range)
            Text("\(Int((value.wrappedValue * 100).rounded()))")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

// MARK: - The node inspector

/// One device, examined: its facts, its drift with
/// the lines shown, its SIGINT claims, and the
/// honest actions — acknowledge, dossier, rename,
/// hunt, move, unplace. Tapping a node opens this;
/// nothing is acknowledged by a tap ever again.
private struct MapNodeInspector: View {
    let ref: MapNodeRef
    var onDossier: (Neighbor) -> Void
    var onRename: (Neighbor) -> Void
    var onHunt: (AirTarget) -> Void
    var onMove: (String) -> Void

    @ObservedObject private var store = MapStore.shared
    @ObservedObject private var neighborhood =
        NeighborhoodStore.shared
    @ObservedObject private var station = SigintStation.shared
    @EnvironmentObject var post: ListeningPost
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                switch ref {
                case .lan(let ip):
                    if let neighbor = neighborhood.neighbors
                        .first(where: { $0.ip == ip }) {
                        lanBody(neighbor)
                    } else {
                        Text("This device has left the "
                             + "Neighborhood's keeping.")
                            .foregroundStyle(.secondary)
                    }
                case .ble(let id):
                    if let row = post.rows.first(
                        where: { $0.id == id }) {
                        bleBody(row)
                    } else {
                        Text("Not in earshot this session — "
                             + "the placement is kept for "
                             + "its return.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func lanBody(_ neighbor: Neighbor) -> some View {
        let key = "lan:" + neighbor.ip
        let unacked = neighbor.drift.count
            - (store.ackedDrift[key] ?? 0)
        Section {
            LabeledContent("Device",
                           value: neighbor.displayName)
            LabeledContent("Address", value: neighbor.ip)
            LabeledContent("Room",
                           value: store.room(ofKey: key)?.name
                               ?? "In the open")
            LabeledContent("Last seen",
                           value: neighbor.lastSeen
                               .formatted(date: .omitted,
                                          time: .shortened))
            LabeledContent("Ports",
                           value: neighbor.ports.isEmpty
                               ? "none open"
                               : neighbor.ports.sorted()
                                   .map(String.init)
                                   .joined(separator: ", "))
            if neighbor.arrivals > 0 {
                LabeledContent("Knocks heard",
                               value: "\(neighbor.arrivals)")
            }
        }
        if unacked > 0 {
            Section {
                ForEach(Array(neighbor.drift.suffix(unacked)
                    .enumerated()), id: \.offset) { _, line in
                    Text(line).font(.callout)
                }
                Button("Acknowledge drift") {
                    store.ackDrift(key: key,
                                   count: neighbor.drift.count)
                }
            } header: {
                Text("Drift — \(unacked) unseen")
            } footer: {
                Text("What changed about this device, "
                     + "in the house's own words.")
            }
        }
        claimsSection(key: key)
        Section {
            Button("Open the dossier") {
                onDossier(neighbor)
            }
            Button("Rename\u{2026}") {
                onRename(neighbor)
            }
            Button("Move — tap its new spot") {
                onMove(key)
            }
            Button("Unplace", role: .destructive) {
                store.unplace(key: key)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func bleBody(_ row: DeviceRow) -> some View {
        let key = "ble:" + row.id
        Section {
            LabeledContent("Device",
                           value: row.name
                               ?? row.preferredLabel
                               ?? row.kind)
            LabeledContent("Kind", value: row.kind)
            LabeledContent("Room",
                           value: store.room(ofKey: key)?.name
                               ?? "In the open")
            if let battery = row.batterySummary {
                LabeledContent("Battery", value: battery)
            }
            if let forecast = row.batteryForecastText {
                LabeledContent("Battery trend",
                               value: forecast)
            }
            if let cadence = row.cadenceText {
                LabeledContent("Cadence", value: cadence)
            }
            ForEach(row.details.prefix(6), id: \.self) { line in
                Text(line).font(.callout)
            }
        }
        claimsSection(key: key)
        Section {
            Button("Walk to it") {
                onHunt(AirTarget(
                    id: row.id,
                    label: row.name ?? row.preferredLabel
                        ?? row.kind,
                    kind: row.kind))
            }
            Button("Move — tap its new spot") {
                onMove(key)
            }
            Button("Unplace", role: .destructive) {
                store.unplace(key: key)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func claimsSection(key: String) -> some View {
        if let emitter = station.emitters.first(
            where: { $0.key == key }) {
            Section {
                ForEach(emitter.claims.prefix(6),
                        id: \.self) { claim in
                    Text(claim).font(.callout)
                }
                if let percent = emitter.batteryPercent {
                    LabeledContent("Battery (registry)",
                                   value: "\(percent)%")
                }
            } header: {
                Text("The registry's word")
            } footer: {
                Text("SIGINT, this epoch. Claims carry "
                     + "their channel — a name match is "
                     + "a claim, never a fusion.")
            }
        }
    }
}

// MARK: - The chips

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

/// A voice in the air, as a chip: name and kind,
/// its battery when a format reported one, and a
/// freshness ring on the listener's clock.
private struct BleNodeChip: View {
    let row: DeviceRow
    let selected: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(row.name ?? row.preferredLabel ?? row.kind)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
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
        var parts = [row.kind]
        if let battery = row.batteries.first(
            where: { $0.component == "device" }) {
            if let percent = battery.percent {
                parts.append("\(percent)%")
            } else if let millivolts = battery.millivolts {
                parts.append("\(millivolts) mV")
            }
        }
        if row.trackerShaped { parts.append("tracker-shaped") }
        return parts.joined(separator: " · ")
    }

    private var ring: Color {
        let age = Date().timeIntervalSince1970 - row.lastSeen
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
