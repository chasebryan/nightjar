import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Colours — the app's wardrobe.
///
/// A theme is a handful of colours with judgement: an accent
/// for the controls, a glow for what deserves light, and a
/// tint washed over the backdrop under a measured dim. Six
/// ship with the app; the operator can tailor more and keep
/// them. Backdrops are chosen per tab — the living wallpaper,
/// the Jolly Roger the app was born wearing, the plain theme
/// colour, or the operator's own image or GIF, which never
/// leaves this device.

// MARK: - Hex colours

extension Color {
    init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }
}

// MARK: - The theme

struct AppTheme: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var accentHex: String
    var glowHex: String
    var tintHex: String
    /// How hard the tint washes over the backdrop (0…0.55).
    var tintStrength: Double
    /// How far the backdrop is dimmed for legibility (0…0.65).
    var dim: Double
    var builtIn: Bool

    var accent: Color { Color(hex: accentHex) }
    var glow: Color { Color(hex: glowHex) }
    var tint: Color { Color(hex: tintHex) }

    // Accent brightened in the beauty pass
    // (2026-10-19): #148040 measured 3.75:1
    // against its own tint — the muddiest
    // working pair in the wardrobe. #1DB35A
    // keeps the phosphor hue, unmistakably,
    // and clears 6.8:1 on the tint, 6.2:1
    // on a panel.
    static let phosphor = AppTheme(
        id: "phosphor", name: "Phosphor",
        accentHex: "#1DB35A", glowHex: "#B6FFC9",
        tintHex: "#04150A", tintStrength: 0.35, dim: 0.18,
        builtIn: true)
    static let bloodwork = AppTheme(
        id: "bloodwork", name: "Bloodwork",
        accentHex: "#FF3B47", glowHex: "#FF9E97",
        tintHex: "#170405", tintStrength: 0.38, dim: 0.22,
        builtIn: true)
    static let ultraviolet = AppTheme(
        id: "ultraviolet", name: "Ultraviolet",
        accentHex: "#B18CFF", glowHex: "#E3CCFF",
        tintHex: "#0D0618", tintStrength: 0.38, dim: 0.20,
        builtIn: true)
    static let arctic = AppTheme(
        id: "arctic", name: "Arctic Signal",
        accentHex: "#6FE3FF", glowHex: "#C9F4FF",
        tintHex: "#041019", tintStrength: 0.35, dim: 0.18,
        builtIn: true)
    static let amber = AppTheme(
        id: "amber", name: "Amber Deck",
        accentHex: "#FFB340", glowHex: "#FFDFA3",
        tintHex: "#140C02", tintStrength: 0.36, dim: 0.20,
        builtIn: true)
    static let bone = AppTheme(
        id: "bone", name: "Bone",
        accentHex: "#E9E2D0", glowHex: "#FFFFFF",
        tintHex: "#0B0B0C", tintStrength: 0.22, dim: 0.12,
        builtIn: true)
    /// The special one (the operator's order,
    /// 2026-10-19): pumpkin orange over
    /// near-black, a ghost-white glow, and
    /// grey in the wash — Halloween, wearable
    /// any night of the year.
    static let halloween = AppTheme(
        id: "halloween", name: "Halloween",
        accentHex: "#FF7518", glowHex: "#EDEDED",
        tintHex: "#0A0A0A", tintStrength: 0.40,
        dim: 0.22,
        builtIn: true)

    /// The other special one (the operator's
    /// order, 2026-10-19): the season's whole
    /// trio, one colour to a role — holly red
    /// works the controls, snow-white carries
    /// the glow, and the wash runs deep pine,
    /// strong enough for the green to be in
    /// the room. Christmas, wearable any
    /// night of the year.
    static let christmas = AppTheme(
        id: "christmas", name: "Christmas",
        accentHex: "#E8443A", glowHex: "#FFFBF0",
        tintHex: "#06130B", tintStrength: 0.42,
        dim: 0.20,
        builtIn: true)

    static let builtIns: [AppTheme] = [.phosphor, .bloodwork,
                                       .ultraviolet, .arctic,
                                       .amber, .bone,
                                       .halloween, .christmas]
}

// MARK: - Backdrop slots and choices

enum BackdropSlot: String, CaseIterable, Identifiable {
    case everywhere, listen, send, serve, sessions, scan,
         recon, emcon, knocktalk, about, skelli, macros,
         vault, blacksite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everywhere: return "Everywhere (the default)"
        case .listen: return "Listen"
        case .send: return "Send"
        case .serve: return "Serve"
        case .sessions: return "Sessions"
        case .scan: return "Scan"
        case .recon: return "Recon"
        case .emcon: return "EMCON"
        case .knocktalk: return "Knocktalk"
        case .about: return "About"
        case .skelli: return "Skelli"
        case .macros: return "Macros"
        case .vault: return "Vault"
        case .blacksite: return "Blacksite"
        }
    }
}

enum BackdropChoice: String, Codable, CaseIterable,
                     Identifiable {
    case inherit, living, skull, plain, custom,
         console

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inherit: return "Use the everywhere setting"
        case .living: return "Living wallpaper"
        case .skull: return "Jolly Roger"
        case .plain: return "Plain theme colour"
        case .custom: return "My image or GIF"
        case .console: return "Generated art (Blacksite)"
        }
    }
}

private struct BackdropSlotKey: EnvironmentKey {
    static let defaultValue: BackdropSlot = .everywhere
}

extension EnvironmentValues {
    var backdropSlot: BackdropSlot {
        get { self[BackdropSlotKey.self] }
        set { self[BackdropSlotKey.self] = newValue }
    }
}

// MARK: - The picker door

/// One continuation, resumed once: the photo
/// library's data handler may call back more
/// than once, and a continuation resumed twice
/// is a crash — the very thing this door exists
/// to keep out of the operator's art.
private final class ResumeOnce {
    private let lock = NSLock()
    private var done = false
    private let body: (Data?) -> Void
    init(_ body: @escaping (Data?) -> Void) {
        self.body = body
    }
    func resume(_ data: Data?) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        lock.unlock()
        body(data)
    }
}

/// How a picked picture actually arrives. The
/// picker's quick representation is not the
/// file: for a GIF — the operator's whole
/// point — `loadTransferable(Data.self)` can
/// hand back nothing at all, or a flattened
/// still of the first frame, and "adding my
/// own gif doesn't work" was the report
/// (2026-10-19). So the door is two-stage:
/// the quick bytes, accepted only when their
/// own header says a picture this house can
/// wear; failing that, the asset's ORIGINAL
/// bytes from the library itself, which for
/// a GIF are the GIF.
enum PickerMedia {
    static func isImage(_ data: Data) -> Bool {
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return true
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return true
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47,
                              0x0D, 0x0A, 0x1A, 0x0A]) {
            return true
        }
        if data.count > 12 {
            let head = [UInt8](data.prefix(12))
            if head[4] == 0x66, head[5] == 0x74,
               head[6] == 0x79, head[7] == 0x70 {
                return true
            }
            if head[0] == 0x52, head[1] == 0x49,
               head[2] == 0x46, head[3] == 0x46,
               head[8] == 0x57, head[9] == 0x45,
               head[10] == 0x42, head[11] == 0x50 {
                return true
            }
        }
        return UIImage(data: data) != nil
    }

    static func load(
        _ item: PhotosPickerItem) async -> Data? {
        if let data = try? await item.loadTransferable(
            type: Data.self), isImage(data) {
            return data
        }
        return await originalBytes(for: item)
    }

    private static func originalBytes(
        for item: PhotosPickerItem) async -> Data? {
        guard let id = item.itemIdentifier else {
            return nil
        }
        _ = await PHPhotoLibrary.requestAuthorization(
            for: .readWrite)
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        return await withCheckedContinuation {
            continuation in
            let once = ResumeOnce {
                continuation.resume(returning: $0)
            }
            PHImageManager.default()
                .requestImageDataAndOrientation(
                    for: asset, options: options) {
                    data, _, _, _ in
                    if let data, isImage(data) {
                        once.resume(data)
                    } else {
                        once.resume(nil)
                    }
                }
        }
    }
}

// MARK: - Custom backdrop media (the operator's own art)

enum BackdropMedia {
    private static var cache: [String: (Date, UIImage)] = [:]
    /// The cache's lock: its readers are
    /// view-side today, but the type never
    /// promised a thread — now it doesn't
    /// have to (the sweep's finding F4).
    private static let cacheLock = NSLock()

    private static func cached(
        _ key: String) -> (Date, UIImage)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[key]
    }

    private static func store(
        _ value: (Date, UIImage), for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache[key] = value
    }

    private static func evict(_ key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeValue(forKey: key)
    }

    private static func fileURL(for slot: BackdropSlot) -> URL {
        let dir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("theme-media", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(slot.rawValue + ".dat")
    }

    static func exists(for slot: BackdropSlot) -> Bool {
        FileManager.default.fileExists(
            atPath: fileURL(for: slot).path)
    }

    @discardableResult
    static func save(_ data: Data, for slot: BackdropSlot) -> Bool {
        let url = fileURL(for: slot)
        do {
            try data.write(to: url, options: .atomic)
            evict(slot.rawValue)
            return true
        } catch {
            return false
        }
    }

    static func remove(for slot: BackdropSlot) {
        try? FileManager.default.removeItem(
            at: fileURL(for: slot))
        evict(slot.rawValue)
    }

    /// The slot's custom art, decoded once per file version:
    /// a GIF comes back animated, a photo holds still.
    static func image(for slot: BackdropSlot) -> UIImage? {
        let url = fileURL(for: slot)
        guard let attrs = try? FileManager.default.attributesOfItem(
                atPath: url.path),
              let stamp = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        if let hit = cached(slot.rawValue),
           hit.0 == stamp {
            return hit.1
        }
        let image = UIImage.animatedGIF(data: data)
            ?? UIImage(data: data)
        if let image {
            store((stamp, image), for: slot.rawValue)
        }
        return image
    }
}

// MARK: - The center

final class ThemeCenter: ObservableObject {
    static let shared = ThemeCenter()

    @Published var current: AppTheme
    @Published var customs: [AppTheme] = []
    /// Bumped whenever anything visual changes, so backdrops
    /// re-read their choices.
    @Published var revision = 0

    private let selectedKey = "theme.selected"
    private let customsKey = "theme.customs"

    private init() {
        let defaults = UserDefaults.standard
        var savedCustoms: [AppTheme] = []
        if let data = defaults.data(forKey: customsKey),
           let saved = try? JSONDecoder().decode(
               [AppTheme].self, from: data) {
            savedCustoms = saved
        }
        customs = savedCustoms
        let wanted = defaults.string(forKey: selectedKey)
        current = AppTheme.builtIns.first { $0.id == wanted }
            ?? savedCustoms.first { $0.id == wanted }
            ?? .phosphor
    }

    var allThemes: [AppTheme] { AppTheme.builtIns + customs }

    func apply(_ theme: AppTheme) {
        current = theme
        UserDefaults.standard.set(theme.id, forKey: selectedKey)
        revision += 1
        Journal.log("colours", "theme",
                    "theme applied: \(theme.name)")
        Haptics.select()
    }

    func saveCustom(_ theme: AppTheme) {
        if let index = customs.firstIndex(
            where: { $0.id == theme.id }) {
            customs[index] = theme
        } else {
            customs.append(theme)
        }
        persistCustoms()
        apply(theme)
    }

    func deleteCustom(_ theme: AppTheme) {
        customs.removeAll { $0.id == theme.id }
        persistCustoms()
        if current.id == theme.id { apply(.phosphor) }
        revision += 1
    }

    private func persistCustoms() {
        if let data = try? JSONEncoder().encode(customs) {
            UserDefaults.standard.set(data, forKey: customsKey)
        }
    }

    // MARK: backdrop choices

    func choice(for slot: BackdropSlot) -> BackdropChoice {
        let raw = UserDefaults.standard.string(
            forKey: "theme.backdrop.\(slot.rawValue)")
        let stored = raw.flatMap(BackdropChoice.init(rawValue:))
        if slot == .everywhere {
            return stored == .inherit ? .living : (stored ?? .living)
        }
        return stored ?? .inherit
    }

    func effectiveChoice(for slot: BackdropSlot) -> BackdropChoice {
        let mine = choice(for: slot)
        if mine != .inherit { return mine }
        // The Blacksite room wears its own
        // wallpaper — art its graphics engine
        // generates — until the operator
        // picks something else for the room
        // in Colours (Chase's order,
        // 2026-10-19: "give it its own
        // wallpaper").
        if slot == .blacksite { return .console }
        return choice(for: .everywhere)
    }

    func setChoice(_ choice: BackdropChoice,
                   for slot: BackdropSlot) {
        UserDefaults.standard.set(
            choice.rawValue,
            forKey: "theme.backdrop.\(slot.rawValue)")
        revision += 1
        Haptics.select()
    }
}

// MARK: - The studio

struct ColoursView: View {
    @ObservedObject private var themes = ThemeCenter.shared
    @State private var editing: AppTheme?
    @State private var creating = false

    var body: some View {
        List {
            Section(header: Text(L("Theme"))) {
                LazyVGrid(columns: [GridItem(.flexible()),
                                    GridItem(.flexible())],
                          spacing: 12) {
                    ForEach(themes.allThemes) { theme in
                        ThemeCard(theme: theme,
                                  selected: themes.current.id
                                      == theme.id) {
                            themes.apply(theme)
                        }
                        .contextMenu {
                            if !theme.builtIn {
                                Button(L("Edit")) { editing = theme }
                                Button(L("Delete"), role: .destructive) {
                                    themes.deleteCustom(theme)
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16,
                                          bottom: 12, trailing: 16))
                Button {
                    creating = true
                } label: {
                    Label(L("Create a theme"),
                          systemImage: "paintpalette")
                }
            }

            Section(header: Text(L("Backdrops"))) {
                ForEach(BackdropSlot.allCases) { slot in
                    BackdropRow(slot: slot)
                }
                ExplainToggle(
                    title: L("How backdrops work"),
                    text: L("Every tab may wear its own. The Jolly Roger is the backdrop the app was born with — retired from default duty, never from the wardrobe. Your own art is copied into the app and never leaves this device; a GIF plays, a photograph holds still."))
            }

            Section(header: Text(L("Boot screen"))) {
                BootRow()
            }

            Section(header: Text(L("Touch"))) {
                TouchRow()
            }
        }
        .navigationTitle(L("Colours"))
        .sheet(isPresented: $creating) {
            ThemeEditorView(theme: nil)
        }
        .sheet(item: $editing) { theme in
            ThemeEditorView(theme: theme)
        }
    }
}

/// One theme as a card: its tint as the ground, its accent as
/// the ring when worn, its three colours as swatches.
private struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(theme.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.glow)
                HStack(spacing: 6) {
                    swatch(theme.accent)
                    swatch(theme.glow)
                    swatch(theme.tint)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [theme.tint,
                                 theme.tint.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selected ? theme.accent
                                 : Color.white.opacity(0.14),
                        lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(
                Color.white.opacity(0.25), lineWidth: 1))
    }
}

/// One backdrop slot: what it wears, and the picker to change
/// it — with the photo door when the choice is custom art.
private struct BackdropRow: View {
    let slot: BackdropSlot
    @ObservedObject private var themes = ThemeCenter.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(slot.displayName)
                Spacer()
                Picker(L(""), selection: binding) {
                    ForEach(choices, id: \.self) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if themes.effectiveChoice(for: slot) == .custom {
                HStack(spacing: 12) {
                    if let image = BackdropMedia.image(for: slot) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(
                                cornerRadius: 8))
                    }
                    PhotosPicker(selection: $pickerItem,
                                 matching: .images) {
                        Text(BackdropMedia.exists(for: slot)
                             ? "Replace image or GIF"
                             : "Choose image or GIF")
                            .font(.callout.weight(.semibold))
                    }
                    if BackdropMedia.exists(for: slot) {
                        Button(L("Remove"), role: .destructive) {
                            BackdropMedia.remove(for: slot)
                            themes.revision += 1
                        }
                        .font(.callout)
                    }
                }
            }
            if let notice {
                Text(notice)
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = await PickerMedia.load(item),
                   BackdropMedia.save(data, for: slot) {
                    await MainActor.run {
                        themes.setChoice(.custom, for: slot)
                        notice = nil
                    }
                } else {
                    DevLog.event("colours",
                                 "backdrop pick brought "
                                 + "no wearable image")
                    await MainActor.run {
                        notice = "That file would not come — "
                            + "try another image or GIF."
                    }
                }
            }
        }
    }

    private var choices: [BackdropChoice] {
        slot == .everywhere
            ? BackdropChoice.allCases.filter { $0 != .inherit }
            : BackdropChoice.allCases
    }

    private var binding: Binding<BackdropChoice> {
        Binding(
            get: { themes.choice(for: slot) },
            set: { themes.setChoice($0, for: slot) })
    }
}

/// Tailor a theme: three colours and two judgements, with the
/// card previewing the suit as it is cut.
private struct ThemeEditorView: View {
    @ObservedObject private var themes = ThemeCenter.shared
    @Environment(\.dismiss) private var dismiss

    private let existingID: String?
    @State private var name: String
    @State private var accent: Color
    @State private var glow: Color
    @State private var tint: Color
    @State private var tintStrength: Double
    @State private var dim: Double

    init(theme: AppTheme?) {
        existingID = theme?.id
        _name = State(initialValue: theme?.name ?? "My theme")
        _accent = State(initialValue:
            theme?.accent ?? Color(hex: "#148040"))
        _glow = State(initialValue:
            theme?.glow ?? Color(hex: "#B6FFC9"))
        _tint = State(initialValue:
            theme?.tint ?? Color(hex: "#04150A"))
        _tintStrength = State(initialValue:
            theme?.tintStrength ?? 0.35)
        _dim = State(initialValue: theme?.dim ?? 0.18)
    }

    private var draft: AppTheme {
        AppTheme(id: existingID ?? UUID().uuidString,
                 name: name.isEmpty ? "Untitled" : name,
                 accentHex: accent.hexString(),
                 glowHex: glow.hexString(),
                 tintHex: tint.hexString(),
                 tintStrength: tintStrength, dim: dim,
                 builtIn: false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("The suit, as you cut it"))) {
                    ThemeCard(theme: draft, selected: false) {}
                        .listRowInsets(EdgeInsets(
                            top: 8, leading: 16,
                            bottom: 8, trailing: 16))
                }
                Section(header: Text(L("Name"))) {
                    TextField(L("Theme name"), text: $name)
                }
                Section(header: Text(L("Colours"))) {
                    ColorPicker(L("Accent — the controls"),
                                selection: $accent,
                                supportsOpacity: false)
                    ColorPicker(L("Glow — names and light"),
                                selection: $glow,
                                supportsOpacity: false)
                    ColorPicker(L("Tint — the backdrop's wash"),
                                selection: $tint,
                                supportsOpacity: false)
                }
                Section(header: Text(L("Judgement"))) {
                    VStack(alignment: .leading) {
                        Text("Tint strength "
                             + "\(Int(tintStrength * 100))%")
                            .font(.callout)
                        Slider(value: $tintStrength, in: 0...0.55)
                    }
                    VStack(alignment: .leading) {
                        Text("Backdrop dim "
                             + "\(Int(dim * 100))%")
                            .font(.callout)
                        Slider(value: $dim, in: 0...0.65)
                    }
                }
            }
            .navigationTitle(existingID == nil
                             ? "New theme" : "Edit theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) {
                        themes.saveCustom(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The house's motor, switched: every beat
/// the app makes, from the one control the
/// operator asked for (2026-10-19) — off means
/// off everywhere, Hunt ear included.
private struct TouchRow: View {
    @AppStorage("house.haptics")
    private var hapticsOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(L("Haptics"), isOn: $hapticsOn)
            ExplainToggle(
                text: L("Every buzz the house makes, from one switch. Off silences them all — the beats at your touch, a verdict's beat, the emergency stop, even the Hunt ear's pulse as you close on a signal. The sounds and the toasts carry on without them, and the house reset turns them back on."))
        }
    }
}

/// The boot, tailored: which backdrop plays
/// behind its log — the provided reel, the
/// operator's own GIF or image, or plain
/// black — and how the log's text arrives.
private struct BootRow: View {
    @AppStorage(BootMedia.mediaKey)
    private var media = "provided"
    @AppStorage(BootMedia.textKey)
    private var textStyle = "lines"
    @AppStorage(BootMedia.enabledKey)
    private var bootEnabled = true
    @AppStorage(BootMedia.gifsKey)
    private var gifsEnabled = true
    @AppStorage(BootMedia.modeKey)
    private var pictureMode = "quality"
    @State private var pickerItem: PhotosPickerItem?
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L("Boot screen"), isOn: $bootEnabled)
            ExplainToggle(
                text: L("What plays when the app opens: the film, the print, and the manifest of true facts about this device. Off stops the ceremony entirely — the app opens straight onto its tabs, and none of it runs."))
            HStack {
                Text(L("Picture"))
                Spacer()
                Picker(L(""), selection: $pictureMode) {
                    Text(L("Quality")).tag("quality")
                    Text(L("Performance"))
                        .tag("performance")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            ExplainToggle(
                text: L("Quality decodes the boot film at 1024 px with the print at full density, and the wallpaper reel plays full-size. Performance decodes the film at 512 — about a fifth of the memory — thins the print, and caps the reel at 640. Same app, lighter feet: choose Performance when the device runs hot or the boot feels heavy."))
            Toggle(L("Animated GIFs"), isOn: $gifsEnabled)
            ExplainToggle(
                text: L("Off stills every GIF in the house: the boot film and the splashes stand on their first frame, and the wallpaper reel holds still. Nothing is removed — the pictures stay, the motion goes."))
            HStack {
                Text(L("Backdrop"))
                Spacer()
                Picker(L(""), selection: $media) {
                    Text(L("Provided film"))
                        .tag("provided")
                    Text(L("Your own")).tag("custom")
                    Text(L("None — black"))
                        .tag("none")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if media == "custom" {
                HStack(spacing: 12) {
                    if let data = BootMedia.data(),
                       let image = UIImage(
                           data: data) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 44,
                                   height: 44)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 8))
                    }
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images) {
                        Text(BootMedia.exists
                             ? "Replace GIF or image"
                             : "Choose a GIF or image")
                            .font(.callout
                                .weight(.semibold))
                    }
                    if BootMedia.exists {
                        Button(L("Remove"),
                               role: .destructive) {
                            BootMedia.remove()
                        }
                        .font(.callout)
                    }
                }
            }
            HStack {
                Text(L("Log text"))
                Spacer()
                Picker(L(""), selection: $textStyle) {
                    Text(L("Line by line"))
                        .tag("lines")
                    Text(L("Typewriter")).tag("type")
                    Text(L("Scramble"))
                        .tag("scramble")
                    Text(L("Fade in")).tag("fade")
                    Text(L("Instant")).tag("instant")
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ExplainToggle(
                title: L("About your own art"),
                text: L("Your own art is copied into the app and never leaves this device; a GIF plays, a photograph holds still. Changes take hold from the next launch, and a tap still skips the boot."))
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = await PickerMedia.load(item),
                   BootMedia.save(data) {
                    await MainActor.run {
                        notice = nil
                    }
                } else {
                    DevLog.event("colours",
                                 "boot pick brought "
                                 + "no wearable image")
                    await MainActor.run {
                        notice = "That file would "
                            + "not come — try "
                            + "another GIF or "
                            + "image."
                    }
                }
            }
        }
    }
}
