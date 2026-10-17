import SwiftUI

/// Her deliveries: everything she makes —
/// forged payloads, drafted code, built tools —
/// filed as real documents the operator can
/// take off the phone: share one, or zip the
/// lot into a single archive. She files them
/// herself, named and extensioned by what they
/// are, the moment she makes them; this sheet
/// is simply where they wait to be collected.
/// The zip writer is hers too — a small honest
/// stored-entry archiver, no dependencies.
final class DeliveriesCenter: ObservableObject {

    static let shared = DeliveriesCenter()

    struct Item: Identifiable, Codable {
        var id = UUID()
        var name: String
        var file: String
        var bytes: Int
        var made: Date
    }

    @Published var items: [Item] = []

    private let directory: URL
    private let indexKey = "skelli.deliveries"

    private init() {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0]
        directory = docs.appendingPathComponent(
            "deliveries", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(
            forKey: indexKey),
           let saved = try? JSONDecoder().decode(
               [Item].self, from: data) {
            items = saved
        }
    }

    /// File something she made. The name is
    /// cleaned into a document name; the
    /// extension says what it is.
    func add(name: String, text: String,
             ext: String) {
        add(name: name,
            data: Data(text.utf8), ext: ext)
    }

    func add(name: String, data: Data,
             ext: String) {
        let clean = name
            .components(separatedBy:
                CharacterSet.alphanumerics
                    .union(CharacterSet(
                        charactersIn: " -_"))
                    .inverted)
            .joined()
            .trimmingCharacters(
                in: .whitespaces)
        let base = clean.isEmpty ? "delivery" : clean
        let file = base + "." + ext
        let url = directory.appendingPathComponent(
            file)
        try? data.write(to: url, options: .atomic)
        items.removeAll { $0.file == file }
        items.insert(
            Item(name: base, file: file,
                 bytes: data.count, made: Date()),
            at: 0)
        if items.count > 100 {
            for old in items.suffix(
                items.count - 100) {
                try? FileManager.default
                    .removeItem(
                        at: directory
                            .appendingPathComponent(
                                old.file))
            }
            items = Array(items.prefix(100))
        }
        persist()
    }

    func url(for item: Item) -> URL {
        directory.appendingPathComponent(item.file)
    }

    func data(for item: Item) -> Data? {
        try? Data(contentsOf: url(for: item))
    }

    func remove(_ item: Item) {
        try? FileManager.default.removeItem(
            at: url(for: item))
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(
                at: url(for: item))
        }
        items = []
        persist()
    }

    /// Zip the chosen deliveries into one
    /// archive in the temporary folder, ready
    /// to be handed over by the share sheet.
    func zip(_ chosen: [Item]) -> URL? {
        var files: [(String, Data)] = []
        for item in chosen {
            if let data = data(for: item) {
                files.append((item.file, data))
            }
        }
        guard !files.isEmpty else { return nil }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "nightjar-delivery-"
                + stamp.string(from: Date())
                + ".zip")
        try? ZipWriter.archive(files).write(
            to: url, options: .atomic)
        return url
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(
            items) {
            UserDefaults.standard.set(
                data, forKey: indexKey)
        }
    }
}

/// A minimal, correct ZIP writer: stored
/// entries (no compression — her artifacts are
/// small), UTF-8 names, honest CRCs.
enum ZipWriter {

    static func archive(
        _ files: [(name: String, data: Data)])
        -> Data {
        var out = Data()
        var central = Data()
        for (name, data) in files {
            let nameBytes = [UInt8](name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            let (time, date) = dosTime(Date())
            out.appendLE(UInt32(0x04034b50))
            out.appendLE(UInt16(20))
            out.appendLE(UInt16(0x0800))
            out.appendLE(UInt16(0))
            out.appendLE(time)
            out.appendLE(date)
            out.appendLE(crc)
            out.appendLE(UInt32(data.count))
            out.appendLE(UInt32(data.count))
            out.appendLE(UInt16(nameBytes.count))
            out.appendLE(UInt16(0))
            out.append(contentsOf: nameBytes)
            out.append(data)

            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(time)
            central.appendLE(date)
            central.appendLE(crc)
            central.appendLE(UInt32(data.count))
            central.appendLE(UInt32(data.count))
            central.appendLE(
                UInt16(nameBytes.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0))
            central.appendLE(offset)
            central.append(contentsOf: nameBytes)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(UInt32(0x06054b50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(files.count))
        out.appendLE(UInt16(files.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(centralOffset)
        out.appendLE(UInt16(0))
        return out
    }

    private static func dosTime(
        _ date: Date) -> (UInt16, UInt16) {
        let c = Calendar.current
            .dateComponents(
                [.year, .month, .day, .hour,
                 .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        let dosDate = UInt16(
            ((year - 1980) << 9)
            | ((c.month ?? 1) << 5)
            | (c.day ?? 1))
        let dosTime = UInt16(
            ((c.hour ?? 0) << 11)
            | ((c.minute ?? 0) << 5)
            | ((c.second ?? 0) / 2))
        return (dosTime, dosDate)
    }

    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0
                    ? 0xEDB88320 ^ (c >> 1)
                    : c >> 1
            }
            return c
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int(
                (crc ^ UInt32(byte)) & 0xFF)]
                ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(
        _ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { raw in
            append(contentsOf: [UInt8](
                raw.bindMemory(to: UInt8.self)))
        }
    }
}

struct DeliveriesView: View {
    @ObservedObject private var center =
        DeliveriesCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shareItem: ShareItem?
    @State private var selected = Set<UUID>()
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                Section {
                    Text("Everything she makes "
                        + "is filed here — take "
                        + "one, or zip the lot "
                        + "and take it all.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if center.items.isEmpty {
                    Text("Nothing filed yet. "
                        + "What she forges and "
                        + "builds lands here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(center.items) { item in
                    HStack {
                        VStack(alignment: .leading,
                               spacing: 2) {
                            Text(item.file)
                                .font(.callout)
                            Text("\(item.bytes) "
                                + "bytes · "
                                + item.made
                                    .formatted(
                                        date: .abbreviated,
                                        time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(
                                    .secondary)
                        }
                        Spacer()
                        Button {
                            shareItem = ShareItem(
                                items: [center.url(
                                    for: item)])
                        } label: {
                            Image(systemName:
                                "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(item.id)
                }
                .onDelete { offsets in
                    for i in offsets {
                        center.remove(
                            center.items[i])
                    }
                }
                if !center.items.isEmpty {
                    Section {
                        Button("Zip the chosen "
                            + "(\(selected.count))") {
                            zipItems(center.items
                                .filter {
                                    selected.contains(
                                        $0.id)
                                })
                        }
                        .disabled(selected.isEmpty)
                        Button("Zip everything "
                            + "(\(center.items.count))") {
                            zipItems(center.items)
                        }
                        Button("Clear the shelf",
                               role: .destructive) {
                            confirmClear = true
                        }
                    }
                }
            }
            .navigationTitle("Deliveries")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: item.items)
            }
            .confirmationDialog(
                "Clear every delivery?",
                isPresented: $confirmClear,
                titleVisibility: .visible) {
                Button("Clear them all",
                       role: .destructive) {
                    center.clear()
                }
                Button("Keep them", role: .cancel) {}
            }
        }
    }

    private func zipItems(
        _ chosen: [DeliveriesCenter.Item]) {
        if let url = center.zip(chosen) {
            shareItem = ShareItem(items: [url])
        }
    }
}
