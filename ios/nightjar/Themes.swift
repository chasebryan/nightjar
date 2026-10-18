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

    static let phosphor = AppTheme(
        id: "phosphor", name: "Phosphor",
        accentHex: "#148040", glowHex: "#B6FFC9",
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

    static let builtIns: [AppTheme] = [.phosphor, .bloodwork,
                                       .ultraviolet, .arctic,
                                       .amber, .bone]
}

// MARK: - Backdrop slots and choices

enum BackdropSlot: String, CaseIterable, Identifiable {
    case everywhere, listen, send, serve, sessions, scan,
         recon, emcon, knocktalk, about, skelli, macros,
         vault

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
        }
    }
}

enum BackdropChoice: String, Codable, CaseIterable,
                     Identifiable {
    case inherit, living, skull, plain, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inherit: return "Use the everywhere setting"
        case .living: return "Living wallpaper"
        case .skull: return "Jolly Roger"
        case .plain: return "Plain theme colour"
        case .custom: return "My image or GIF"
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

// MARK: - Custom backdrop media (the operator's own art)

enum BackdropMedia {
    private static var cache: [String: (Date, UIImage)] = [:]

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
            cache.removeValue(forKey: slot.rawValue)
            return true
        } catch {
            return false
        }
    }

    static func remove(for slot: BackdropSlot) {
        try? FileManager.default.removeItem(
            at: fileURL(for: slot))
        cache.removeValue(forKey: slot.rawValue)
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
        if let hit = cache[slot.rawValue], hit.0 == stamp {
            return hit.1
        }
        let image = UIImage.animatedGIF(data: data)
            ?? UIImage(data: data)
        if let image { cache[slot.rawValue] = (stamp, image) }
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
            Section(header: Text("Theme")) {
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
                                Button("Edit") { editing = theme }
                                Button("Delete", role: .destructive) {
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
                    Label("Create a theme",
                          systemImage: "paintpalette")
                }
            }

            Section(header: Text("Backdrops")) {
                ForEach(BackdropSlot.allCases) { slot in
                    BackdropRow(slot: slot)
                }
                ExplainToggle(
                    title: "How backdrops work",
                    text: "Every tab may wear its "
                        + "own. The Jolly Roger is "
                        + "the backdrop the app was "
                        + "born with — retired from "
                        + "default duty, never from "
                        + "the wardrobe. Your own "
                        + "art is copied into the "
                        + "app and never leaves this "
                        + "device; a GIF plays, a "
                        + "photograph holds still.")
            }

            Section(header: Text("Boot screen")) {
                BootRow()
            }
        }
        .navigationTitle("Colours")
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
                Picker("", selection: binding) {
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
                        Button("Remove", role: .destructive) {
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
                if let data = try? await item.loadTransferable(
                    type: Data.self),
                   BackdropMedia.save(data, for: slot) {
                    await MainActor.run {
                        themes.setChoice(.custom, for: slot)
                        notice = nil
                    }
                } else {
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
                Section(header: Text("The suit, as you cut it")) {
                    ThemeCard(theme: draft, selected: false) {}
                        .listRowInsets(EdgeInsets(
                            top: 8, leading: 16,
                            bottom: 8, trailing: 16))
                }
                Section(header: Text("Name")) {
                    TextField("Theme name", text: $name)
                }
                Section(header: Text("Colours")) {
                    ColorPicker("Accent — the controls",
                                selection: $accent,
                                supportsOpacity: false)
                    ColorPicker("Glow — names and light",
                                selection: $glow,
                                supportsOpacity: false)
                    ColorPicker("Tint — the backdrop's wash",
                                selection: $tint,
                                supportsOpacity: false)
                }
                Section(header: Text("Judgement")) {
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        themes.saveCustom(draft)
                        dismiss()
                    }
                }
            }
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
            Toggle("Boot screen", isOn: $bootEnabled)
            ExplainToggle(
                text: "What plays when the app "
                    + "opens: the film, the sphere, "
                    + "and the manifest of true facts "
                    + "about this device. Off stops "
                    + "the ceremony entirely — the "
                    + "app opens straight onto its "
                    + "tabs, and none of it runs.")
            HStack {
                Text("Picture")
                Spacer()
                Picker("", selection: $pictureMode) {
                    Text("Quality").tag("quality")
                    Text("Performance")
                        .tag("performance")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            ExplainToggle(
                text: "Quality decodes the boot "
                    + "film at 1024 px with the "
                    + "sphere at full density, and "
                    + "the wallpaper reel plays "
                    + "full-size. Performance "
                    + "decodes the film at 512 — "
                    + "about a fifth of the memory — "
                    + "thins the sphere, and caps "
                    + "the reel at 640. Same app, "
                    + "lighter feet: choose "
                    + "Performance when the device "
                    + "runs hot or the boot feels "
                    + "heavy.")
            Toggle("Animated GIFs", isOn: $gifsEnabled)
            ExplainToggle(
                text: "Off stills every GIF in "
                    + "the house: the boot film and "
                    + "the splashes stand on their "
                    + "first frame, and the "
                    + "wallpaper reel holds still. "
                    + "Nothing is removed — the "
                    + "pictures stay, the motion "
                    + "goes.")
            HStack {
                Text("Backdrop")
                Spacer()
                Picker("", selection: $media) {
                    Text("Provided film")
                        .tag("provided")
                    Text("Your own").tag("custom")
                    Text("None — black")
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
                        Button("Remove",
                               role: .destructive) {
                            BootMedia.remove()
                        }
                        .font(.callout)
                    }
                }
            }
            HStack {
                Text("Log text")
                Spacer()
                Picker("", selection: $textStyle) {
                    Text("Line by line")
                        .tag("lines")
                    Text("Typewriter").tag("type")
                    Text("Scramble")
                        .tag("scramble")
                    Text("Fade in").tag("fade")
                    Text("Instant").tag("instant")
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
                title: "About your own art",
                text: "Your own art is copied "
                    + "into the app and never "
                    + "leaves this device; a GIF "
                    + "plays, a photograph holds "
                    + "still. Changes take hold "
                    + "from the next launch, and a "
                    + "tap still skips the boot.")
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item
                    .loadTransferable(
                        type: Data.self),
                   BootMedia.save(data) {
                    await MainActor.run {
                        notice = nil
                    }
                } else {
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
