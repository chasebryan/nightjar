import CoreBluetooth
import ImageIO
import PDFKit
import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
#else
import AppKit
#endif
import WebKit
#if canImport(MLXLLM)
import MLXLLM
import MLXLMCommon
#endif
#if canImport(MLXHuggingFace)
import MLXHuggingFace
import HuggingFace
import Tokenizers
#endif
import WebKit

/// Little in-app banners that say what just happened, then fade —
/// so the app narrates itself instead of silently changing state.
/// Toasts carry a KIND now — plain news, a success, a warning, an
/// error, or a process reporting in — and the kind drives the
/// icon, the tint and how long the banner stays. The same news
/// arriving twice in a breath is counted, not stacked.
final class ToastCenter: ObservableObject {
    enum Kind {
        case info, success, warn, error, process
    }

    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let kind: Kind
        var count = 1
        var isError: Bool { kind == .error }
    }

    @Published var current: Toast?
    private var queue: [Toast] = []
    private var draining = false

    /// The house's long-standing door: a plain message is
    /// good news unless it is flagged an error.
    func show(_ message: String, error: Bool = false) {
        show(message, kind: error ? .error : .success)
    }

    /// Enqueue, never overwrite: messages drain FIFO, each
    /// dwelling by its kind. A repeat of the toast on screen
    /// or last in line folds into it with a count.
    func show(_ message: String, kind: Kind) {
        if var showing = current,
           showing.message == message, showing.kind == kind {
            showing.count += 1
            current = showing
            return
        }
        if let index = queue.indices.last,
           queue[index].message == message,
           queue[index].kind == kind {
            queue[index].count += 1
            return
        }
        queue.append(Toast(message: message, kind: kind))
        guard !draining else { return }
        draining = true
        displayNext()
    }

    private func dwell(_ kind: Kind) -> Double {
        switch kind {
        case .error: return 4.5
        case .warn: return 3.6
        case .process: return 3.4
        case .info, .success: return 2.2
        }
    }

    private func displayNext() {
        guard !queue.isEmpty else {
            draining = false
            return
        }
        let toast = queue.removeFirst()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            current = toast
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + dwell(toast.kind)) { [weak self] in
            guard let self = self else { return }
            if self.queue.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.current = nil
                }
                self.draining = false
            } else {
                self.displayNext()
            }
        }
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast

    private var icon: String {
        switch toast.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .process: return "checkmark.seal.fill"
        }
    }

    private var fill: Color {
        switch toast.kind {
        case .error: return Color.red.opacity(0.92)
        case .warn: return Color(red: 0.72, green: 0.45,
                                 blue: 0.05).opacity(0.95)
        case .info, .success, .process:
            return Color(white: 0.16).opacity(0.95)
        }
    }

    private var iconTint: Color {
        switch toast.kind {
        case .info: return Color(white: 0.85)
        case .success, .process:
            return Color(red: 0.35, green: 1.0, blue: 0.45)
        case .warn: return Color(red: 1.0, green: 0.8, blue: 0.3)
        case .error: return .white
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(iconTint)
            Text(toast.message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
            if toast.count > 1 {
                Text("×\(toast.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(fill))
        .shadow(radius: 8, y: 3)
        .padding(.horizontal, 16)
    }
}

/// The provided wallpaper, decoded ONCE and shared by
/// every backdrop in the app. As shipped it is a still —
/// the white bird on black (Chase's selection,
/// 2026-10-22) — and a still hangs exactly as provided;
/// the animation machinery below still serves any reel
/// that takes its place, looping forever. By any road
/// in: a "Wallpaper" data asset, wallpaper.png, or
/// wallpaper.gif in the bundle.
enum Wallpaper {
    static let image: UIImage? = {
        let data: Data?
        if let asset = NSDataAsset(name: "Wallpaper") {
            data = asset.data
        } else if let url = Bundle.main.url(
            forResource: "wallpaper", withExtension: "png") {
            data = try? Data(contentsOf: url)
        } else if let url = Bundle.main.url(
            forResource: "wallpaper", withExtension: "gif") {
            data = try? Data(contentsOf: url)
        } else {
            data = nil
        }
        guard let data else { return nil }
        return UIImage.animatedGIF(data: data)
    }()
}

/// A full-bleed player for one shared animated image.
///
/// Every backdrop in the app shares the one decoded
/// wallpaper, and one animated UIImage handed to a
/// dozen image views animates only where UIKit feels
/// like it — on device the Vault and Macros backdrops
/// sat dark while others played (2026-10-18). So each
/// view now runs its OWN animation from the shared
/// decoded frames — the pattern the GIF player below
/// already proves — and updateUIView restarts a view
/// that stopped (a tab switch, a recycled hierarchy),
/// so coming back to a screen always finds it playing.
#if os(iOS)
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .black
        configure(view)
        return view
    }

    func updateUIView(_ view: UIImageView,
                      context: Context) {
        configure(view)
    }

    private func configure(_ view: UIImageView) {
        guard let frames = image.images,
              frames.count > 1 else {
            // A still where an animation played:
            // clear the old reel, or it runs on
            // behind the still.
            if view.animationImages != nil {
                view.stopAnimating()
                view.animationImages = nil
            }
            view.image = image
            return
        }
        // The view outlives the backdrop choice.
        // A slot re-pointed from one reel to
        // another — living wallpaper to a custom
        // GIF, a custom GIF replaced in place —
        // hands the new image here, and the old
        // guard (swap only while animationImages
        // is nil) kept the FIRST reel playing
        // forever: changing the wallpaper
        // selection looked broken, because the
        // screen never changed (Chase's report,
        // 2026-10-21). Swap whenever the reel
        // itself differs.
        let current = view.animationImages
        let stale = current == nil
            || current?.count != frames.count
            || current?.first !== frames.first
            || view.animationDuration != image.duration
        if stale {
            if view.isAnimating { view.stopAnimating() }
            view.image = frames.first
            view.animationImages = frames
            view.animationDuration = image.duration
        }
        if !view.isAnimating {
            view.startAnimating()
        }
    }
}
#endif

#if os(macOS)
/// The Mac's animated image: NSImageView animates
/// a GIF natively, which is all the phone's
/// frame-walking view was reaching for.
struct AnimatedImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.image = image
        return view
    }

    func updateNSView(_ view: NSImageView,
                      context: Context) {
        if view.image !== image { view.image = image }
        if !view.animates { view.animates = true }
    }
}
#endif

/// The app's backdrop, wearing whatever Colours says this
/// slot wears: the living wallpaper, the Jolly Roger, the
/// plain theme colour, or the operator's own art — washed
/// with the theme's tint and dimmed by its measure, so text
/// stays readable over any of them.
/// The still-backdrop fit decision, kept pure so the
/// Gauntlet can pin it: a still is shown WHOLE when its
/// aspect and the frame's aspect disagree by more than
/// ~18% — beyond that, fill-cropping eats the subject
/// (the bird lockup blew past both screen edges).
enum BackdropFit {
    static func wholeArtwork(imageAspect: CGFloat,
                             frameAspect: CGFloat) -> Bool {
        guard imageAspect > 0, frameAspect > 0 else {
            return false
        }
        let ratio = max(imageAspect, frameAspect)
            / min(imageAspect, frameAspect)
        return ratio > 1.18
    }
}

struct AppBackdrop: View {
    var slot: BackdropSlot? = nil
    @Environment(\.backdropSlot) private var ambientSlot
    @ObservedObject private var themes = ThemeCenter.shared

    private var resolvedSlot: BackdropSlot {
        slot ?? ambientSlot
    }

    /// The slot whose media file a custom backdrop
    /// reads. The choice RESOLVES through inherit —
    /// a screen wearing the everywhere setting is
    /// told ".custom" — but the art itself is filed
    /// under the slot whose own choice is custom.
    /// Reading the screen's own slot instead found
    /// no file on any tab but the owner's, and the
    /// everywhere image (and GIF) silently fell
    /// back to the wallpaper everywhere (Chase's
    /// report, 2026-10-22).
    private var mediaSlot: BackdropSlot {
        themes.choice(for: resolvedSlot) == .inherit
            ? .everywhere : resolvedSlot
    }

    var body: some View {
#if os(macOS)
        // The Mac skin (fix261): the wallpaper is
        // ceremony and presence, not wallpaper
        // behind work. Her room keeps her art, and
        // the console keeps its own ground; every
        // other room sits on the console ground.
        if resolvedSlot == .skelli
            || themes.effectiveChoice(
                for: resolvedSlot) == .console {
            fullBackdrop
        } else {
            MacGround()
        }
#else
        fullBackdrop
#endif
    }

    private var fullBackdrop: some View {
        // GeometryReader pins the backdrop to exactly the size
        // it is offered. A bare scaledToFill image inside a
        // ZStack reports its natural size and blows the whole
        // layout out to match — frame + clip keep it tame.
        let theme = themes.current
        let choice = themes.effectiveChoice(for: resolvedSlot)
        return GeometryReader { geo in
            ZStack {
                Color(white: 0.03)
                backdrop(choice: choice, theme: theme, geo: geo)
                Rectangle().fill(theme.tint)
                    .opacity(theme.tintStrength)
                Rectangle().fill(Color.black.opacity(theme.dim))
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func backdrop(choice: BackdropChoice,
                          theme: AppTheme,
                          geo: GeometryProxy) -> some View {
        switch choice {
        case .living, .inherit:
            if let wallpaper = Wallpaper.image {
                if platformImageIsAnimated(wallpaper) {
                    AnimatedImageView(image: wallpaper)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                        .clipped()
                } else {
                    stillBackdrop(wallpaper, geo: geo)
                }
            } else {
                skull(geo)
            }
        case .skull:
            skull(geo)
        case .custom:
            if let image = BackdropMedia.image(
                for: mediaSlot) {
                if platformImageIsAnimated(image) {
                    AnimatedImageView(image: image)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                        .clipped()
                } else {
                    stillBackdrop(image, geo: geo)
                }
            } else if let wallpaper = Wallpaper.image {
                if platformImageIsAnimated(wallpaper) {
                    AnimatedImageView(image: wallpaper)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                        .clipped()
                } else {
                    stillBackdrop(wallpaper, geo: geo)
                }
            } else {
                skull(geo)
            }
        case .plain:
            LinearGradient(
                colors: [theme.tint, Color.black],
                startPoint: .top, endPoint: .bottom)
        case .console:
            BlacksiteWallpaperView(
                width: geo.size.width,
                height: geo.size.height)
        }
    }

    /// Positional management for still backdrops (Chase's
    /// ruling, 2026-10-22: "better positional management of
    /// the bird — can't even see this"). A still whose shape
    /// mismatches the screen's is shown WHOLE, centered, on
    /// the backdrop's near-black base, where the blend is
    /// invisible; near-matching shapes keep the full-bleed
    /// fill. Animated reels keep the fill — motion masks
    /// the crop.
    @ViewBuilder
    private func stillBackdrop(_ image: UIImage,
                               geo: GeometryProxy) -> some View {
        let frameAspect = geo.size.width
            / max(geo.size.height, 1)
        let imageAspect = image.size.width
            / max(image.size.height, 1)
        if BackdropFit.wholeArtwork(imageAspect: imageAspect,
                                    frameAspect: frameAspect) {
            Image.platformImage(image)
                .resizable().scaledToFit()
                .frame(width: geo.size.width,
                       height: geo.size.height)
                .clipped()
        } else {
            Image.platformImage(image)
                .resizable().scaledToFill()
                .frame(width: geo.size.width,
                       height: geo.size.height)
                .clipped()
        }
    }

    @ViewBuilder
    private func skull(_ geo: GeometryProxy) -> some View {
        if UIImage(named: "AppBackground") != nil {
            Image("AppBackground")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width,
                       height: geo.size.height)
                .clipped()
        }
    }
}

/// The themed-screen recipe, applied per tab: the slot
/// environment and a backdrop behind the tab's root.
/// (Painting it only behind the TabView is not enough —
/// on current iOS the tab container fills its own frame
/// opaquely, so an ancestor's backdrop never shows
/// through.) One hard-learned limit, proven on device
/// (2026-10-18): for a tab whose root is a List inside a
/// navigation stack, THIS modifier's background paints
/// behind the stack and the stack's hosting covers it —
/// the screen sits black. Those tabs must ALSO paint
/// AppBackdrop directly behind their own list, with
/// scrollContentBackground(.hidden) on the list itself,
/// as Knocktalk, Listen and the rest do. The harness
/// checks every tab for exactly that.
struct AppThemed: ViewModifier {
    var slot: BackdropSlot = .everywhere

    func body(content: Content) -> some View {
        content
            .environment(\.backdropSlot, slot)
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
    }
}

extension View {
    func appThemed(_ slot: BackdropSlot = .everywhere)
        -> some View {
        modifier(AppThemed(slot: slot))
    }
}

/// Boot splash: the boot reel plays full-screen — the
/// machine waking up, eyes wide — while the boot log types
/// itself over it, line by line, every line true: this
/// device, this network, this library, this stealth state.
/// The Jolly Roger stays inside the app; nothing of it is
/// out here. The reel plays exactly once and the
/// whole ceremony is timed against it — the log, the
/// print, the assembling title — ending on the
/// film's last frame with the closing line delivered
/// as the finale, one held beat, then the fade into
/// the app. A tap skips it all. Without the reel in
/// the bundle, the same log plays over plain black
/// on the old fixed timings — never a broken boot.
/// The boot's wardrobe: the operator's own film
/// or image for the boot backdrop, copied into
/// Documents/boot-media and nowhere else, and
/// the two choices — backdrop and text style —
/// as keys both the boot and Colours read.
enum BootMedia {
    static let mediaKey = "boot.media"
    static let textKey = "boot.textStyle"
    /// Whether the boot ceremony plays at all
    /// when the app opens.
    static let enabledKey = "boot.enabled"
    /// Whether animated GIFs play anywhere in
    /// the house — the boot film, the wallpaper
    /// reel, the splashes. Off, every GIF stands
    /// as a still frame instead.
    static let gifsKey = "media.gifsEnabled"
    /// The house's picture mode: "quality" or
    /// "performance" — how much of the device
    /// the films, reels and the boot's print
    /// may spend.
    static let modeKey = "media.mode"

    /// True when the operator has chosen
    /// performance over quality.
    static var performanceMode: Bool {
        UserDefaults.standard.string(forKey: modeKey)
            == "performance"
    }

    static var file: URL {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(
            "boot-media", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(
            "custom-media")
    }

    static var exists: Bool {
        FileManager.default.fileExists(
            atPath: file.path)
    }

    static func data() -> Data? {
        try? Data(contentsOf: file)
    }

    @discardableResult
    static func save(_ data: Data) -> Bool {
        (try? data.write(to: file,
                         options: .atomic)) != nil
    }

    static func remove() {
        try? FileManager.default.removeItem(
            at: file)
    }

    static func isGIF(_ data: Data) -> Bool {
        data.starts(with: [0x47, 0x49, 0x46, 0x38])
    }

    /// True when the bytes are a real video file:
    /// an ISO media box carries "ftyp" at offset
    /// four. The Mac's own boot film is one.
    static func isVideo(_ data: Data) -> Bool {
        data.count > 8
            && data[4] == 0x66 && data[5] == 0x74
            && data[6] == 0x79 && data[7] == 0x70
    }
}

/// The boot's subtitle: not a fixed seal but a
/// drawn card — one of four hundred and four
/// phrases in the house's plaque voice, chosen
/// fresh at every boot and held for the whole
/// ceremony. (The finale still trades it for its
/// own line.) The pool rides as one block of
/// text, split at first use: a single string is
/// cheaper for the type-checker than four
/// hundred literals, and reads like what it is —
/// a deck. The phrases pass through the house's
/// `L()` seam like every other line; until a
/// table carries them they render in English,
/// never blank.
enum BootSubtitles {
    private static let block = """
    IT LISTENS FIRST
    SEALED AT THE SOURCE
    NOTHING HERE IS DECORATED
    THE HOUSE IS AWAKE
    KEYS BEFORE DOORS
    CARRY IT QUIETLY
    NO NAMES ON THE WIRE
    THE LONG WAY HOME
    EVERYTHING IN ITS PLACE
    THE DARK IS A ROOM
    PATIENT AS STONE
    WHAT THE WIRE CARRIES
    A QUIET HOUSE IN A LOUD WORLD
    FIRST, LISTEN
    UNDER NO FLAG
    SEALED, NOT HIDDEN
    THE MERIDIAN HOLDS
    COUNTED AND KEPT
    THE STATIC HAS A GRAMMAR
    EARS BEFORE HANDS
    THE NIGHT SHIFT
    BOARDED AND DARK
    A HOUSE THAT LISTENS
    THE QUIET TRADE
    NOTHING LEAVES UNSEALED
    THE LEDGER IS HONEST
    DARK BY DEFAULT
    THE WIRE REMEMBERS
    KEPT UNDER THE HOUSE
    A SEAL, NOT A LOCK
    THE WEATHER INSIDE
    LISTENING IS A DISCIPLINE
    THE SLOW FREQUENCY
    NO LIGHT WITHOUT LEAVE
    THE HOUSE KEEPS ITS WORD
    ASH AND ARCHIVE
    THE THRESHOLD IS KEPT
    QUIET HANDS, OPEN EARS
    THE LONG STATIC
    SEALED IN THE DARK
    WHAT THE NIGHT CARRIES
    A LANTERN, LOWERED
    THE COMPASS RESTS
    NOTHING HERE IS LOUD
    THE ARCHIVE BREATHES
    KEPT, NOT KEPT SECRET
    THE DISTANCE IS MEASURED
    AN HONEST LEDGER
    THE GATE STANDS OPEN INWARD
    WINTER IN THE WALLS
    THE EMBER LEDGER
    STILL ON THE WIRE
    THE ROOM BEHIND THE ROOM
    A MAP OF LISTENING
    THE CURRENT REMEMBERS
    HOLD THE FREQUENCY
    THE NIGHT IS A HARBOR
    SEALED WITH PATIENCE
    THE FIELD AT NIGHT
    NOTHING DECORATED
    THE HOUSE STANDS ITS WATCH
    A KEY FOR EVERY DOOR
    THE QUIET CURRENT
    READ THE WEATHER FIRST
    THE STAIR GOES DOWN
    KEPT IN THE WALLS
    THE WELL IS DEEP
    A SEALED ROOM, AN OPEN EAR
    THE ROAD AT 3 AM
    NOTHING UNCOUNTED
    THE SKY IS AN ANTENNA
    LOW LIGHT, LONG EARS
    THE HARBOR AT NIGHT
    SEALED AND CARRIED
    THE ORCHARD AFTER DARK
    A COLD ROOM FOR HOT KEYS
    THE QUARRY OF STATIC
    PATIENT CIRCUITRY
    THE HOUSE REMEMBERS THE WAY
    EVERY DOOR ACCOUNTED
    THE TIDE LEDGER
    LISTEN PAST THE STATIC
    THE GLASS IS LISTENING
    A WATCH, NOT A SIEGE
    THE NIGHT LEDGER
    KEPT UNDER SEAL AND STONE
    THE SLOW SIGNAL
    NOTHING HERE PERFORMS
    THE ROOM KEEPS ITS COUNSEL
    A QUIET INSTRUMENT
    THE WIRE IS PATIENT
    SEALED BEFORE SPOKEN
    THE HOUR IS KEPT
    AN EAR AT EVERY WALL
    THE MAP IS NOT THE HOUSE
    CARRIED, NOT SENT
    THE DARK KEEPS RECEIPTS
    A HOUSE OF LISTENING
    THE SIGNAL IS A GUEST
    NOTHING ARRIVES UNCOUNTED
    THE THRESHOLD REMEMBERS
    QUIET AS KEPT
    THE WEATHER ON THE WIRE
    SEALED IN PLAIN SIGHT
    THE LONG DARK STAIR
    A LEDGER OF WEATHER
    THE HOUSE AT ITS POST
    EVERY KEY ANSWERED FOR
    THE NIGHT IS INSTRUMENTED
    STILL LISTENING
    THE GATE IS A QUESTION
    KEPT CLOSE, CARRIED QUIET
    THE FREQUENCY IS A ROOM
    ASHES AND SIGNALS
    THE WALLS HAVE EARS, KEPT
    A SEAL IS A PROMISE
    THE DISTANCE LISTENS
    NOTHING LOST, NOTHING LOUD
    THE STAIR REMEMBERS FEET
    SEALED TWICE
    THE HOUSE, DERIVING ITSELF
    AN ARCHIVE OF NIGHTS
    THE QUIET LEDGER
    PATIENT AS STATIC
    THE ROOM BELOW THE ROOM
    CARRY NOTHING UNSEALED
    THE WIRE KEEPS THE HOUR
    A KEY IS A KEPT WORD
    THE HARBOR LIGHTS, LOWERED
    UNDER SEAL
    UNDER GLASS
    UNDER STONE
    UNDER SNOW
    UNDER ASH
    UNDER SALT
    UNDER IRON
    UNDER NIGHT
    UNDER LOCK
    UNDER OATH
    UNDER ICE
    UNDER DUST
    UNDER BONE
    UNDER PINE
    UNDER MOSS
    UNDER FROST
    UNDER RAIN
    UNDER EARTH
    UNDER STARS
    UNDER SILENCE
    UNDER WATER
    UNDER LEAD
    UNDER VELVET
    UNDER OAK
    SMOKE AND STATIC
    SALT AND SIGNAL
    GLASS AND WEATHER
    IRON AND PATIENCE
    NIGHT AND WIRE
    KEY AND LEDGER
    EMBER AND ASH
    TIDE AND STONE
    MAP AND DISTANCE
    LANTERN AND DARK
    QUIET AND THUNDER
    SNOW AND CIRCUIT
    BONE AND COPPER
    RAIN AND FREQUENCY
    OATH AND ARCHIVE
    DUST AND MERIDIAN
    PINE AND STATIC
    FROST AND SIGNAL
    SALT AND DISTANCE
    STONE AND CURRENT
    ASH AND ORCHARD
    VELVET AND IRON
    GLASS AND CURRENT
    NIGHT AND LEDGER
    KEY AND WEATHER
    SEA AND SIGNAL
    FIELD AND STATIC
    ROOF AND WEATHER
    WELL AND STONE
    GATE AND QUESTION
    ROAD AND WEATHER
    HOUR AND STATIC
    MAP AND WEATHER
    SKY AND LEDGER
    ROOM AND STATIC
    EMBER AND SIGNAL
    TIDE AND SIGNAL
    IRON AND WEATHER
    SNOW AND LEDGER
    QUIET AND CURRENT
    QUIET WIRE
    QUIET WEATHER
    QUIET LEDGER
    QUIET WELL
    PATIENT WIRE
    PATIENT WEATHER
    PATIENT LEDGER
    PATIENT WELL
    HOLLOW WIRE
    HOLLOW WEATHER
    HOLLOW LEDGER
    HOLLOW WELL
    VELVET WIRE
    VELVET WEATHER
    VELVET LEDGER
    VELVET WELL
    IRON WIRE
    IRON WEATHER
    IRON LEDGER
    IRON WELL
    AMBER WIRE
    AMBER WEATHER
    AMBER LEDGER
    AMBER WELL
    FROZEN WIRE
    FROZEN WEATHER
    FROZEN LEDGER
    FROZEN WELL
    SILENT WIRE
    SILENT WEATHER
    SILENT LEDGER
    SILENT WELL
    HIDDEN WIRE
    HIDDEN WEATHER
    HIDDEN LEDGER
    HIDDEN WELL
    RESTLESS WIRE
    RESTLESS WEATHER
    RESTLESS LEDGER
    RESTLESS WELL
    ANCIENT WIRE
    ANCIENT WEATHER
    ANCIENT LEDGER
    ANCIENT WELL
    NARROW WIRE
    NARROW WEATHER
    NARROW LEDGER
    NARROW WELL
    GENTLE WIRE
    GENTLE WEATHER
    GENTLE LEDGER
    GENTLE WELL
    PALE WIRE
    PALE WEATHER
    PALE LEDGER
    PALE WELL
    LOW WIRE
    LOW WEATHER
    LOW LEDGER
    LOW WELL
    SLOW WIRE
    SLOW WEATHER
    SLOW LEDGER
    SLOW WELL
    DEEP WIRE
    DEEP WEATHER
    DEEP LEDGER
    DEEP WELL
    FAR WIRE
    FAR WEATHER
    FAR LEDGER
    FAR WELL
    THIN WIRE
    THIN WEATHER
    THIN LEDGER
    THIN WELL
    SOFT WIRE
    SOFT WEATHER
    SOFT LEDGER
    SOFT WELL
    COPPER WIRE
    COPPER WEATHER
    COPPER LEDGER
    COPPER WELL
    IVORY WIRE
    IVORY WEATHER
    IVORY LEDGER
    IVORY WELL
    ASHEN WIRE
    ASHEN WEATHER
    ASHEN LEDGER
    ASHEN WELL
    STONE WIRE
    STONE WEATHER
    STONE LEDGER
    STONE WELL
    GLASS WIRE
    GLASS WEATHER
    GLASS LEDGER
    GLASS WELL
    SALT WIRE
    SALT WEATHER
    SALT LEDGER
    SALT WELL
    SMOKE WIRE
    SMOKE WEATHER
    SMOKE LEDGER
    SMOKE WELL
    WINTER WIRE
    WINTER WEATHER
    WINTER LEDGER
    WINTER WELL
    MORTAL WIRE
    MORTAL WEATHER
    MORTAL LEDGER
    MORTAL WELL
    THE WIRE LISTENS
    THE WIRE WAITS
    THE WIRE COUNTS
    THE WIRE HOLDS
    THE WIRE DREAMS
    THE DARK LISTENS
    THE DARK WAITS
    THE DARK COUNTS
    THE DARK HOLDS
    THE DARK DREAMS
    THE HOUSE LISTENS
    THE HOUSE WAITS
    THE HOUSE COUNTS
    THE HOUSE HOLDS
    THE HOUSE DREAMS
    THE NIGHT LISTENS
    THE NIGHT WAITS
    THE NIGHT COUNTS
    THE NIGHT HOLDS
    THE NIGHT DREAMS
    THE STATIC LISTENS
    THE STATIC WAITS
    THE STATIC COUNTS
    THE STATIC HOLDS
    THE STATIC DREAMS
    THE SIGNAL LISTENS
    THE SIGNAL WAITS
    THE SIGNAL COUNTS
    THE SIGNAL HOLDS
    THE SIGNAL DREAMS
    THE LEDGER LISTENS
    THE LEDGER WAITS
    THE LEDGER COUNTS
    THE LEDGER HOLDS
    THE LEDGER DREAMS
    THE THRESHOLD LISTENS
    THE THRESHOLD WAITS
    THE THRESHOLD COUNTS
    THE THRESHOLD HOLDS
    THE THRESHOLD DREAMS
    THE CURRENT LISTENS
    THE CURRENT WAITS
    THE CURRENT COUNTS
    THE CURRENT HOLDS
    THE CURRENT DREAMS
    THE HARBOR LISTENS
    THE HARBOR WAITS
    THE HARBOR COUNTS
    THE HARBOR HOLDS
    THE HARBOR DREAMS
    THE ARCHIVE LISTENS
    THE ARCHIVE WAITS
    THE ARCHIVE COUNTS
    THE ARCHIVE HOLDS
    THE ARCHIVE DREAMS
    THE FREQUENCY LISTENS
    THE FREQUENCY WAITS
    THE FREQUENCY COUNTS
    THE FREQUENCY HOLDS
    THE FREQUENCY DREAMS
    HOUSE OF GLASS
    HOUSE OF SIGNAL
    HOUSE OF KEYS
    REPUBLIC OF GLASS
    REPUBLIC OF SIGNAL
    REPUBLIC OF KEYS
    ARCHIVE OF GLASS
    ARCHIVE OF SIGNAL
    ARCHIVE OF KEYS
    LEDGER OF GLASS
    LEDGER OF SIGNAL
    LEDGER OF KEYS
    MAP OF GLASS
    MAP OF SIGNAL
    MAP OF KEYS
    FIELD OF GLASS
    FIELD OF SIGNAL
    FIELD OF KEYS
    ROOM OF GLASS
    ROOM OF SIGNAL
    ROOM OF KEYS
    GARDEN OF GLASS
    GARDEN OF SIGNAL
    GARDEN OF KEYS
    WEATHER OF GLASS
    WEATHER OF SIGNAL
    WEATHER OF HOURS
    CIRCUIT OF STATIC
    CIRCUIT OF WEATHER
    CIRCUIT OF HOURS
    HARBOR OF STATIC
    HARBOR OF WEATHER
    HARBOR OF HOURS
    STAIR OF STATIC
    STAIR OF WEATHER
    """

    static let all: [String] = block
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    /// One card from the deck, drawn for a boot.
    static func random() -> String {
        all.randomElement() ?? "UNDER SEAL"
    }
}

struct BootView: View {
    let onDone: () -> Void

    @StateObject private var book = PayloadBook()
    @AppStorage("stealthMode") private var stealthMode = false
    @AppStorage(BootMedia.mediaKey)
    private var bootMedia = "provided"
    @AppStorage(BootMedia.textKey)
    private var bootText = "lines"
    @AppStorage(BootMedia.gifsKey)
    private var gifsEnabled = true
    @AppStorage(BootMedia.modeKey)
    private var pictureMode = "quality"
    @State private var shown = 0
    @State private var typed = 0
    @State private var scrambleStep = 0
    @State private var fadeShown = false
    @State private var cursorOn = true
    @State private var filmProgress: Double = 0
    @State private var finale = false
    /// This boot's subtitle, drawn once from the
    /// deck when the ceremony is raised.
    @State private var subtitle = BootSubtitles.random()
    /// The backdrop, loaded exactly once at the
    /// boot's start and served from state after:
    /// the film's bytes and its measured duration.
    @State private var loadedData: Data?
    @State private var loadedFilmSeconds: Double?
    /// The glitch boot's engagement (Chase's
    /// commission, 2026-10-22): when the backdrop
    /// proves to be the stock bird still, the
    /// ceremony hands the screen to the flood.
    @State private var glitchEngaged = false
    @State private var glitchImage: UIImage?

    private struct BootLine {
        let text: String
        let tone: Tone
        enum Tone { case cmd, ok, warn, off }
    }

    /// A named film out of the bundle, when it
    /// is aboard.
    private func bundleFilm(_ name: String) -> Data? {
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "mp4")
        else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The boot reel, chosen for the glass it
    /// plays on (Chase's selection, 2026-10-20):
    /// the laptop's wide film on the Mac, the
    /// tablet's two cuts on an iPad — landscape
    /// or portrait by the window it wakes in —
    /// and the phone's portrait film on a phone.
    /// Behind every one of them stands the old
    /// road in: a "BootReel" data asset, or
    /// boot-reel.png in the bundle — the stock
    /// boot screen, the white bird on black
    /// (Chase's selection, 2026-10-22), a still
    /// the ceremony times by its own clock — or
    /// boot-reel.gif, so a house missing its new
    /// films still boots on the reel it has
    /// always known.
    private var providedData: Data? {
#if os(macOS)
        if let film = bundleFilm(
            "nightjar-boot-laptop-1920x1080") {
            return film
        }
        if let film = bundleFilm("boot-reel-mac") {
            return film
        }
#elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom
            == .pad {
            let bounds = UIScreen.main.bounds
            let wide = bounds.width > bounds.height
            if let film = bundleFilm(wide
                ? "nightjar-boot-tablet-landscape-2048x1536"
                : "nightjar-boot-tablet-portrait-1536x2048") {
                return film
            }
        }
        if let film = bundleFilm(
            "nightjar-boot-phone-1080x1920") {
            return film
        }
#endif
        if let asset = NSDataAsset(name: "BootReel") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "boot-reel",
                                     withExtension: "png") {
            return try? Data(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: "boot-reel",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    /// The backdrop the operator chose: their own
    /// film or image, the provided reel, or
    /// nothing at all over plain black.
    private var backdropData: Data? {
        switch bootMedia {
        case "none":
            return nil
        case "custom":
            return BootMedia.data() ?? providedData
        default:
            return providedData
        }
    }

    private func filmPlayer(data: Data,
                            focusX: CGFloat = 0.5,
                            focusY: CGFloat = 0.5,
                            zoom: CGFloat = 1) -> some View {
        BootFilmPlayer(data: data, focusX: focusX,
                       focusY: focusY, zoom: zoom,
                       maxPixel: pictureMode == "performance"
                           ? 512 : 1024) { value in
            if abs(value - filmProgress) > 0.004
                || value == 1 {
                filmProgress = value
            }
        }
    }

    /// The film's own length, when the backdrop is
    /// a GIF: the whole boot is timed against it —
    /// the text, the bar, and the farewell all land
    /// on the film's last frame.
    private var filmSeconds: Double? {
        loadedFilmSeconds
    }

    /// One clock for the whole ceremony: the film's
    /// true progress while a film plays, the log
    /// style's own progress when none does.
    private var bootProgress: CGFloat {
        filmSeconds != nil
            ? CGFloat(filmProgress)
            : progress
    }

    /// The title assembling: the letters begin wide
    /// apart and dim, and draw together, brightening,
    /// as the boot completes — the name resolving as
    /// the machine finishes waking.
    private var titleTracking: CGFloat {
        let t = max(0, min(1,
            (Double(bootProgress) - 0.45) / 0.55))
        return CGFloat(11 * (1 - t))
    }

    /// The manifest's clock, built once — a
    /// formatter is far too expensive to build
    /// on every redraw.
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var lines: [BootLine] {
        // Plain statements of fact, set like a
        // plaque — no prompt glyphs, no brackets,
        // no slashes — but voiced as what the boot
        // now is: a key ceremony. The house does
        // not load; it derives itself, names its
        // keyholder and its witnesses, and seals
        // the manifest with its own provenance.
#if os(iOS)
        let bedrockLine = BootLine(
            text: String(format: L("Bedrock — iOS %@"), UIDevice.current.systemVersion),
            tone: .ok)
#else
        let bedrockLine = BootLine(
            text: String(format: L("Bedrock — macOS %@"), UIDevice.current.systemVersion),
            tone: .ok)
#endif
        var out: [BootLine] = [
            BootLine(text: String(format: L("Keyholder — %@"), UIDevice.current.name),
                     tone: .ok),
            bedrockLine,
            BootLine(text: String(format: L("Nightjar — %@"), AppInfo.version),
                     tone: .ok),
        ]
        if let ip = Mouth.localIPAddress() {
            out.append(BootLine(text: String(format: L("Rendezvous — %@"), ip),
                                tone: .ok))
        } else {
            out.append(BootLine(text: L("No rendezvous yet"),
                                tone: .off))
        }
        let neighbors = NeighborhoodStore.shared
            .neighbors.count
        out.append(BootLine(
            text: String(format: L("Witnesses — %lld known"), neighbors),
            tone: neighbors > 0 ? .ok : .off))
        out.append(BootLine(
            text: String(format: L("Arsenal — %lld payloads loaded"), book.items.count),
            tone: .ok))
        switch CBManager.authorization {
        case .allowedAlways:
            out.append(BootLine(
                text: L("Ears — permission granted"),
                tone: .ok))
        case .denied, .restricted:
            out.append(BootLine(
                text: L("Ears — permission denied"),
                tone: .warn))
        default:
            out.append(BootLine(
                text: L("Ears — permission undecided"),
                tone: .off))
        }
        out.append(stealthMode
            ? BootLine(text: L("Veil — drawn, unlisted and silent"),
                       tone: .ok)
            : BootLine(text: L("Veil — lifted"), tone: .off))
        if Wallpaper.image != nil
            || UIImage(named: "AppBackground") != nil {
            out.append(BootLine(text: L("Curtain — in place"),
                                tone: .ok))
        } else {
            out.append(BootLine(text: L("Curtain — missing"),
                                tone: .off))
        }
        out.append(BootLine(
            text: String(format: L("Epoch — %@"), Self.clockFormatter.string(from: Date())),
            tone: .ok))
        // The seal on the manifest: the build's
        // own provenance, stamped in as it was
        // built — the ceremony certifying itself.
        if let stamp = SourceStamp.shortCommit {
            out.append(BootLine(
                text: String(format: L("Provenance — %@"), stamp),
                tone: .ok))
        }
        // The closing line — "the world is yours" —
        // is not a log line: it is the finale,
        // delivered by the title block itself on
        // the film's last frame.
        return out
    }

    private func color(_ tone: BootLine.Tone) -> Color {
        switch tone {
        case .cmd: return Color(white: 0.95)
        case .ok: return Color(red: 0.35, green: 1.0, blue: 0.45)
        case .warn: return Color(red: 1.0, green: 0.72, blue: 0.25)
        case .off: return Color(white: 0.6)
        }
    }

    private var totalChars: Int {
        lines.reduce(0) { $0 + $1.text.count + 1 }
    }

    private var progress: CGFloat {
        switch bootText {
        case "type":
            return totalChars == 0 ? 0
                : CGFloat(typed) / CGFloat(totalChars)
        case "scramble":
            return CGFloat(scrambleStep)
                / CGFloat(max(1, 2 * lines.count + 8))
        case "fade":
            return fadeShown ? 1 : 0
        case "instant":
            return 1
        default:
            return lines.isEmpty ? 0
                : CGFloat(shown) / CGFloat(lines.count)
        }
    }

    private var cursor: some View {
        Text("▊")
            .font(.system(.footnote,
                          design: .monospaced))
            .foregroundStyle(color(.ok))
            .shadow(color: color(.ok).opacity(0.7),
                    radius: 6)
            .opacity(cursorOn ? 1 : 0)
    }

    /// The typewriter's rows: whole lines until
    /// the character budget runs out mid-line.
    private func typedRows()
        -> [(BootLine, String)] {
        var rows: [(BootLine, String)] = []
        var left = typed
        for line in lines {
            if left <= 0 { break }
            let take = min(left, line.text.count)
            rows.append(
                (line, String(line.text.prefix(take))))
            left -= take + 1
        }
        return rows
    }

    /// The scramble's text for one line: a
    /// resolved head and a tail of glyphs that
    /// churns deterministically per step.
    private func scrambled(_ line: BootLine,
                           index: Int) -> String {
        let glyphs = Array("░▒▓█▄▀·")
        let resolved = max(0, min(
            line.text.count,
            (scrambleStep - index * 2) * 2))
        var out = String(line.text.prefix(resolved))
        let chars = Array(line.text)
        for pos in resolved..<chars.count {
            let pick = (index * 31 + pos * 17
                        + scrambleStep * 13)
                % glyphs.count
            out.append(glyphs[pick])
        }
        return out
    }

    /// The log itself, wearing the chosen style.
    @ViewBuilder
    private var logView: some View {
        switch bootText {
        case "type":
            let rows = typedRows()
            ForEach(rows.indices, id: \.self) { i in
                lineView(rows[i].0, text: rows[i].1)
            }
            cursor
        case "scramble":
            ForEach(lines.indices, id: \.self) { i in
                lineView(lines[i],
                         text: scrambled(lines[i],
                                          index: i))
            }
        case "instant":
            ForEach(lines.indices, id: \.self) { i in
                lineView(lines[i])
                    .opacity(fadeShown ? 1 : 0)
            }
        case "fade":
            ForEach(lines.indices, id: \.self) { i in
                lineView(lines[i])
                    .opacity(fadeShown ? 1 : 0)
                    .animation(
                        .easeOut(duration: 0.5)
                            .delay(Double(i) * 0.07),
                        value: fadeShown)
            }
        default:
            ForEach(0..<min(shown, lines.count),
                    id: \.self) { i in
                lineView(lines[i])
            }
            cursor
        }
    }

    @ViewBuilder
    private func lineView(_ line: BootLine,
                          text override: String? = nil)
        -> some View {
        let text = Text(override ?? line.text)
            .font(.system(.footnote, design: .monospaced)
                  .weight(line.tone == .cmd ? .semibold : .regular))
            .foregroundStyle(color(line.tone))
            .shadow(color: .black.opacity(0.95), radius: 3, x: 0, y: 1)
        if line.tone == .cmd {
            text.shadow(color: .white.opacity(0.35), radius: 7)
        } else if line.tone == .ok {
            text.shadow(color: color(.ok).opacity(0.45), radius: 6)
        } else {
            text
        }
    }

    /// The print: a fingerprint deriving itself.
    /// Ridge by ridge the whorl grows as the load
    /// rises — the house proving its identity as
    /// it wakes, which is what a derivation is.
    /// The ridges are bone-white with an accent
    /// core; when the load completes, the print
    /// stands whole and brightens. No ring, no
    /// chart — a print.
    private var printView: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [color(.ok).opacity(
                                 finale ? 0.20 : 0.09),
                             .clear],
                    center: .center,
                    startRadius: 8, endRadius: 108))
                .frame(width: 216, height: 216)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2,
                                     y: size.height / 2)
                // The ridge count is the mode's to
                // spend: full in quality, light in
                // performance.
                let ridges = pictureMode
                    == "performance" ? 7 : 12
                let p = Double(bootProgress)
                for i in 0..<ridges {
                    let local = min(1, max(0,
                        p * Double(ridges) - Double(i)))
                    if local <= 0 { continue }
                    let base = 7 + 77 * Double(i)
                        / Double(max(1, ridges - 1))
                    let start = -1.2 + Double(i) * 0.42
                    let span = (4.9 + Double(i % 3)
                        * 0.45) * local * local
                        * (3 - 2 * local)
                    var path = Path()
                    let steps = 56
                    for s in 0...steps {
                        let u = Double(s) / Double(steps)
                        let theta = start + span * u
                        let wobble = 1
                            + 0.13 * sin(theta * 2
                                + Double(i) * 0.8)
                            + 0.08 * sin(theta * 3
                                - Double(i) * 0.5)
                        let r = base * wobble
                        let point = CGPoint(
                            x: center.x
                                + CGFloat(r * cos(theta)),
                            y: center.y + CGFloat(
                                r * sin(theta)) * 1.14)
                        if s == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                    let core = i < 3
                    var alpha = 0.30 + 0.70 * local
                    if finale { alpha = min(1, alpha + 0.25) }
                    let tint = core
                        ? color(.ok)
                        : Color(white: 0.92)
                    context.stroke(
                        path,
                        with: .color(tint.opacity(alpha)),
                        style: StrokeStyle(
                            lineWidth: 2.3,
                            lineCap: .round,
                            lineJoin: .round))
                }
            }
            .frame(width: 190, height: 210)
            Text("\(Int(bootProgress * 100))%")
                .font(.system(.title3, design: .monospaced)
                      .weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.95),
                        radius: 5, x: 0, y: 1)
        }
        .frame(width: 216, height: 216)
        .rotationEffect(.degrees(
            Double(bootProgress) * 10 - 6))
        .scaleEffect(finale ? 1.0 : 0.97)
        .animation(.spring(response: 0.9,
                           dampingFraction: 0.72),
                   value: finale)
    }

    var ceremonyBody: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let data = loadedData {
                    if BootMedia.isGIF(data), gifsEnabled {
                        if bootMedia == "provided" {
                            // This film's bird stands
                            // left of centre in its own
                            // frame (about 38% across,
                            // 45% down): the player is
                            // told so, and holds the bird
                            // at the centre of the screen
                            // under a slight zoom.
                            filmPlayer(data: data,
                                       focusX: 0.38,
                                       focusY: 0.45,
                                       zoom: 1.15)
                                // The film alone of the
                                // boot's layers fills the
                                // WHOLE screen, status
                                // bar and home indicator
                                // included — the still
                                // road and the gradients
                                // already escape the
                                // safe area; the film was
                                // pinned to the inset
                                // frame and left a black
                                // bar at the top. The
                                // text stack keeps the
                                // inset geometry it was
                                // composed against.
                                .ignoresSafeArea()
                        } else {
                            filmPlayer(data: data)
                                .ignoresSafeArea()
                        }
                } else if BootMedia.isVideo(data) {
                    // Real video — the platform films
                    // (fix259). Both players ride it
                    // now: the Mac's AVPlayerView and
                    // the phone's own AVPlayer layer
                    // inside the film container.
                    filmPlayer(data: data)
                        .ignoresSafeArea()
                } else if let image = UIImage(
                    data: data) {
                    Image.platformImage(image)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
                LinearGradient(
                    colors: [Color.black.opacity(0.52),
                             Color.black.opacity(0)],
                    startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [Color.black.opacity(0),
                             Color.black.opacity(0.80)],
                    startPoint: .center, endPoint: .bottom)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("nightjar")
                        .font(.system(.title3, design: .monospaced)
                              .weight(.bold))
                        .tracking(titleTracking)
                        .foregroundStyle(.white.opacity(
                            0.62 + 0.38
                                * Double(bootProgress)))
                        .shadow(color: .black.opacity(0.9),
                                radius: 5, x: 0, y: 1)
                    Text(finale
                         ? L("the world is yours")
                         : L(subtitle))
                        .font(.system(.caption2,
                                      design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(finale
                            ? color(.ok)
                            : Color(white: 0.62))
                        .shadow(color: .black.opacity(0.9),
                                radius: 4, x: 0, y: 1)
                        .animation(.easeInOut(duration: 0.45),
                                   value: finale)
                }
                .padding(.top, 22)
                Spacer()
                VStack(spacing: 10) {
                    printView
                    Text(L("DERIVING THE NIGHT"))
                        .font(.system(.caption2,
                                      design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Color(white: 0.55))
                        .shadow(color: .black.opacity(0.9),
                                radius: 3)
                }
                Spacer()
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        logView
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .frame(height: 198, alignment: .topLeading)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
            }
            }
            .frame(width: geo.size.width,
                   height: geo.size.height)
        }
    }

    /// The boot as raised: the glitch flood when
    /// the stock bird still is the backdrop
    /// (Chase's commission, 2026-10-22), the
    /// classic ceremony for every other
    /// backdrop — a film, the operator's own
    /// still, or none. The ceremony's task
    /// rides THIS view, not the ceremony's own
    /// body: it is the clock and the warm-up,
    /// and it must survive the glitch branch
    /// replacing the picture mid-boot.
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if glitchEngaged, let glitchImage {
                GlitchBootView(
                    image: glitchImage,
                    calm: pictureMode == "performance")
            } else {
                ceremonyBody
            }
        }
        // No skipping: the ceremony runs its
        // course — it is working time, not a
        // curtain — and the house already offers
        // the off switch in About for anyone who
        // wants no boot at all.
        .task {
            // The backdrop is read exactly ONCE, here —
            // its bytes and duration then live in state.
            // Every screen update reads state, never
            // the file: re-reading a 19 MB film on each
            // redraw was the crawl.
            let data = backdropData
            loadedData = data
            if let data = data, BootMedia.isGIF(data),
               gifsEnabled {
                let delays = UIImage.gifDelays(data)
                loadedFilmSeconds = delays.count > 1
                    ? delays.reduce(0, +) : nil
            }
            if let data = data,
               BootMedia.isVideo(data) {
                // The film is a video, and the
                // ceremony is timed against the
                // film: measure it, so the text,
                // the print and the finale stretch
                // across its whole play and land on
                // its last frame — the film plays
                // fully, never cut short.
                loadedFilmSeconds =
                    await BootFilmMeasure
                        .videoSeconds(for: data)
            }
            // The ceremony's minutes are working
            // minutes: while the film plays, warm
            // the machinery every tab is about to
            // need — the weights ledger reconciled
            // against the disk, her saved words
            // read in, the house key derived — so
            // the first real ask meets a warm
            // house. It starts first and runs
            // beside the film, and the ceremony
            // JOINS it before the finale: the
            // curtain does not lift on a cold
            // house.
            let warm = Task.detached(priority: .utility) {
                _ = WeightsCenter.shared
                _ = SkelliStore.load()
                _ = CryptoSuite.identity()
                // The registries parse once, on
                // first touch — warm them here,
                // off every thread that matters,
                // so the first Listen session and
                // the first port lookup never pay
                // the parse (finding P7).
                _ = CompanyRegistry.names
                _ = ServiceRegistry.names
                _ = PortRegistry.names
            }
            let blink = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    cursorOn.toggle()
                }
            }
            if bootMedia == "provided",
               let data = loadedData,
               !BootMedia.isGIF(data),
               !BootMedia.isVideo(data),
               let still = UIImage(data: data) {
                // THE GLITCH (Chase's commission,
                // 2026-10-22): the stock bird
                // still does not fade in — it
                // floods. The storm spends its
                // 3.6 seconds on its own clock
                // while the warm-up finishes
                // beside it; the honours — the
                // join, the finale beat, the
                // hand-off — stay the ceremony's.
                glitchImage = still
                glitchEngaged = true
                try? await Task.sleep(
                    nanoseconds: 3_600_000_000)
                if Task.isCancelled {
                    blink.cancel(); return
                }
                _ = await warm.value
                if Task.isCancelled { return }
                finale = true
                Haptics.success()
                try? await Task.sleep(
                    nanoseconds: 350_000_000)
                blink.cancel()
                if Task.isCancelled { return }
                onDone()
                return
            }
            // The ceremony is timed against the
            // film: while a film plays, every style
            // is stretched across its one playthrough,
            // so the last line, the full print and the
            // finale all land on its last frame.
            // Without a film, the old timings stand.
            let film = filmSeconds
            switch bootText {
            case "instant":
                shown = lines.count
                fadeShown = true
                try? await Task.sleep(nanoseconds:
                    UInt64((film ?? 0.9) * 1_000_000_000))
            case "fade":
                shown = lines.count
                fadeShown = true
                try? await Task.sleep(nanoseconds:
                    UInt64((film ?? 1.5) * 1_000_000_000))
            case "type":
                let total = max(1, totalChars)
                let perChar = UInt64(
                    (film ?? 1.5) * 1_000_000_000
                        / Double(total))
                for _ in 0..<total {
                    try? await Task.sleep(
                        nanoseconds: perChar)
                    if Task.isCancelled {
                        blink.cancel(); return
                    }
                    typed += 1
                    if typed % 14 == 0 {
                        Haptics.tick()
                    }
                }
                if film == nil {
                    try? await Task.sleep(
                        nanoseconds: 400_000_000)
                }
            case "scramble":
                let steps = 2 * lines.count + 8
                let perStep = UInt64(
                    (film ?? Double(steps) * 0.065)
                        * 1_000_000_000 / Double(steps))
                for step in 0...steps {
                    scrambleStep = step
                    try? await Task.sleep(
                        nanoseconds: perStep)
                    if Task.isCancelled {
                        blink.cancel(); return
                    }
                }
                if film == nil {
                    try? await Task.sleep(
                        nanoseconds: 350_000_000)
                }
            default:
                if let film = film {
                    let perLine = UInt64(
                        film * 1_000_000_000
                            / Double(max(1, lines.count)))
                    for _ in lines.indices {
                        try? await Task.sleep(
                            nanoseconds: perLine)
                        if Task.isCancelled {
                            blink.cancel(); return
                        }
                        shown += 1
                        Haptics.tick()
                    }
                } else {
                    for _ in lines.indices {
                        try? await Task.sleep(
                            nanoseconds: UInt64.random(
                                in: 110_000_000...210_000_000))
                        if Task.isCancelled {
                            blink.cancel(); return
                        }
                        shown += 1
                        Haptics.tick()
                    }
                    try? await Task.sleep(
                        nanoseconds: 550_000_000)
                }
            }
            if Task.isCancelled { return }
            if film != nil {
                // The text kept the film's pace — but
                // if the film itself ever ran a breath
                // behind, the finale waits for its
                // true last frame rather than arriving
                // early to a still-moving picture.
                var waited = 0.0
                while filmProgress < 1 && waited < 2.0 {
                    try? await Task.sleep(
                        nanoseconds: 50_000_000)
                    if Task.isCancelled {
                        blink.cancel(); return
                    }
                    waited += 0.05
                }
            }
            // The warm start, joined: everything
            // the house needs is loaded before the
            // curtain lifts. The film has had its
            // full play by now; if the warming is
            // somehow the slower of the two, the
            // boot holds here until it lands —
            // that time is the point of the
            // ceremony.
            _ = await warm.value
            if Task.isCancelled { return }
            // The finale: the title stands assembled,
            // the closing line takes the subtitle's
            // place, and the house holds its breath
            // on the film's last frame — one beat —
            // before fading into the app.
            finale = true
            Haptics.success()
            try? await Task.sleep(
                nanoseconds: 450_000_000)
            blink.cancel()
            if Task.isCancelled { return }
            onDone()
        }
    }
}

/// The glitch boot (Chase's commission, 2026-10-22:
/// "a full on new glitch screen boot screen that
/// matches the official nightjar emblem — completely
/// flood and glitch the whole screen — with a final
/// shot that nightjar is now live — really go wild").
/// When the stock bird still is the boot's backdrop,
/// the ceremony hands the screen to this: the emblem
/// tears in by slices under channel-split ghosts and
/// waterfalls of console spill, the storm converges,
/// one red sweep crosses the settled bird, and the
/// final shot lands — NIGHTJAR IS NOW LIVE, in the
/// Violent Redteam red the house now wears by
/// default. Pure presentation on a 3.6-second clock
/// (BootView sleeps the same 3.6 beside the warm-up
/// and keeps the honours); every chaotic value is a
/// deterministic function of the slice and the time
/// quantum, so a redraw can never drift the storm —
/// it is choreographed, not rolled.
struct GlitchBootView: View {
    let image: UIImage
    /// Performance picture mode: fewer slices, no
    /// full-frame inverts — the storm, calmer.
    let calm: Bool
    @State private var start = Date()

    static let duration = 3.6
    private static let liveRed = Color(red: 1.0,
        green: 0.086, blue: 0.149)
    private static let spillPool = [
        "0x7F3A :: SYN", "ACK 49152 > 80", "KEX CURVE25519",
        "UDP/5683 OPEN", "TTL 64 ID 0x1F", "SEQ 9F31C2",
        "SIGINT POST", "HANDSHAKE OK", "02:00:00:00:00:01",
        "CH0 LISTEN", "FRAG 0 MF 0", "WINDOW 65535",
        "RTT 0.4 MS", "CHACHA20-POLY1305", "MF 0 DF 1",
        "SPORT 443 > 8192", "NOMATCH DROP", "FEAA EDDYSTONE",
        "RSSI -61 DBM", "CIPHER SUITE OK",
    ]

    /// Deterministic chaos: a hash of the slice and
    /// the time quantum, 0..<1.
    private func hash(_ a: Int, _ b: Int) -> Double {
        let v = sin(Double(a * 127 + b * 311)) *
            43758.5453
        return v - floor(v)
    }

    /// The storm's strength over time: floods in
    /// over the first breath, rages to 1.9 s, then
    /// converges to nothing by 2.6 s.
    private func stormAmp(_ t: Double) -> Double {
        if t < 0.30 { return t / 0.30 }
        if t < 1.90 { return 1 }
        if t < 2.60 {
            let u = (t - 1.90) / 0.70
            return pow(1 - u, 2.2)
        }
        return 0
    }

    /// The emblem's own rect: the whole bird,
    /// fitted and centred — where every layer
    /// agrees the bird lives, so convergence
    /// lands exactly on the final shot.
    private func fittedRect(_ size: CGSize) -> CGRect {
        let iw = max(image.size.width, 1)
        let ih = max(image.size.height, 1)
        let scale = min(size.width / iw,
                        size.height / ih)
        let w = iw * scale
        let h = ih * scale
        return CGRect(x: (size.width - w) / 2,
                      y: (size.height - h) / 2,
                      width: w, height: h)
    }

    private func sliceOffset(_ i: Int, _ q: Int,
                             _ amp: Double) -> CGFloat {
        var off = (hash(i, q) * 2 - 1) * 44 * amp
        if hash(i + 57, q) > 0.93 {
            let dir: Double = hash(i + 91, q) > 0.5
                ? 1 : -1
            off += dir * 130 * amp
        }
        return CGFloat(off)
    }

    private func sliceOpacity(_ i: Int, _ q: Int,
                              _ t: Double) -> Double {
        var o = min(1, t / 0.2)
        if stormAmp(t) > 0.02, hash(i + 131, q) < 0.10 {
            o *= 0.3
        }
        return o
    }

    @ViewBuilder
    private func slices(t: Double,
                        size: CGSize) -> some View {
        let fit = fittedRect(size)
        let count = calm ? 9 : 15
        let q = Int(t * 24)
        let amp = stormAmp(t)
        let h = fit.height / CGFloat(count)
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Image.platformImage(image)
                    .resizable()
                    .frame(width: fit.width,
                           height: fit.height)
                    .offset(y: -CGFloat(i) * h)
                    .frame(width: fit.width, height: h,
                           alignment: .top)
                    .clipped()
                    .position(
                        x: fit.midX
                            + sliceOffset(i, q, amp),
                        y: fit.minY
                            + h * (CGFloat(i) + 0.5))
                    .opacity(sliceOpacity(i, q, t))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func ghosts(t: Double,
                        size: CGSize) -> some View {
        let fit = fittedRect(size)
        let amp = stormAmp(t)
        if amp > 0.02 {
            ZStack {
                Image.platformImage(image)
                    .resizable()
                    .frame(width: fit.width,
                           height: fit.height)
                    .colorMultiply(Color(red: 1,
                        green: 0.1, blue: 0.15))
                    .offset(x: CGFloat(-7 * amp))
                Image.platformImage(image)
                    .resizable()
                    .frame(width: fit.width,
                           height: fit.height)
                    .colorMultiply(Color(red: 0.15,
                        green: 0.85, blue: 1))
                    .offset(x: CGFloat(7 * amp))
            }
            .blendMode(.screen)
            .opacity(0.38 * amp)
        }
    }

    @ViewBuilder
    private func tearBars(t: Double,
                          size: CGSize) -> some View {
        let amp = stormAmp(t)
        if amp > 0.02 {
            let q = Int(t * 24)
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    let yy = size.height * CGFloat(hash(k + 3, q))
                    Rectangle()
                        .fill(k == 1
                            ? Self.liveRed
                            : Color.white)
                        .frame(width: size.width,
                               height: CGFloat(
                                   6 + hash(k + 7, q) * 22))
                        .position(x: size.width / 2,
                                  y: yy)
                        .opacity(0.13 * amp)
                }
            }
        }
    }

    @ViewBuilder
    private func spill(t: Double,
                       size: CGSize) -> some View {
        let vis: Double = t < 1.9
            ? min(1, t / 0.3)
            : max(0, 1 - (t - 1.9) / 0.5)
        if vis > 0.01 {
            let q2 = Int(t * 12)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<13, id: \.self) { row in
                    let idx = (row * 31 + q2 * 17) % Self.spillPool.count
                    Text(Self.spillPool[idx])
                        .font(.system(
                            size: 9, design: .monospaced))
                        .foregroundStyle(Color(
                            red: 0.35, green: 1.0,
                            blue: 0.45).opacity(0.55))
                }
            }
            .position(x: 64, y: size.height * 0.32)
            .opacity(vis)
        }
    }

    private func scanlines(t: Double,
                           size: CGSize) -> some View {
        Canvas { context, canvasSize in
            var y: CGFloat = 0
            while y < canvasSize.height {
                context.fill(
                    Path(CGRect(x: 0, y: y,
                                width: canvasSize.width,
                                height: 1)),
                    with: .color(.black.opacity(0.16)))
                y += 3
            }
            let span = canvasSize.height + 120
            let band = CGFloat(
                (t * 130).truncatingRemainder(
                    dividingBy: Double(span))) - 60
            let grad = Gradient(colors: [
                .clear,
                Self.liveRed.opacity(0.10),
                .clear])
            context.fill(
                Path(CGRect(x: 0, y: band,
                            width: canvasSize.width,
                            height: 60)),
                with: .linearGradient(
                    grad,
                    startPoint: CGPoint(x: 0, y: band),
                    endPoint: CGPoint(x: 0, y: band + 60)))
        }
        .frame(width: size.width, height: size.height)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            TimelineView(.animation(
                minimumInterval: 1.0 / 60.0)) { timeline in
                let t = min(Self.duration, max(0,
                    timeline.date.timeIntervalSince(start)))
                let q = Int(t * 24)
                let flashing = !calm
                    && [7, 23, 41].contains(q)
                let fit = fittedRect(size)
                let sweepU = (t - 2.55) / 0.5
                let textO = t < 2.75 ? 0
                    : min(1, (t - 2.75) / 0.3)
                let cleanO = t < 2.45 ? 0
                    : min(1, (t - 2.45) / 0.35)
                let pct = min(100, Int(t / 2.6 * 20) * 5)
                ZStack {
                    Color.black
                    slices(t: t, size: size)
                    ghosts(t: t, size: size)
                    tearBars(t: t, size: size)
                    if flashing {
                        Rectangle()
                            .fill(Color.white)
                            .blendMode(.difference)
                    }
                    Image.platformImage(image)
                        .resizable()
                        .frame(width: fit.width,
                               height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                        .opacity(cleanO)
                    scanlines(t: t, size: size)
                    spill(t: t, size: size)
                    if t < 2.6 {
                        Text("BOOT \(pct)%")
                            .font(.system(
                                size: 10,
                                design: .monospaced))
                            .foregroundStyle(
                                Color(white: 0.55))
                            .position(x: size.width - 46,
                                      y: 56)
                    }
                    if sweepU >= 0, sweepU <= 1.15 {
                        Rectangle()
                            .fill(Self.liveRed)
                            .frame(width: size.width,
                                   height: 2)
                            .shadow(color: Self.liveRed
                                .opacity(0.9), radius: 8)
                            .position(
                                x: size.width / 2,
                                y: size.height * CGFloat(
                                    min(sweepU, 1)))
                            .opacity(sweepU > 1
                                ? max(0, 1 - (sweepU - 1)
                                        / 0.15)
                                : 1)
                    }
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [
                                .black.opacity(0.55 * textO),
                                .clear],
                            center: .center,
                            startRadius: 4,
                            endRadius: 190))
                        .frame(width: 470, height: 180)
                        .position(x: size.width / 2,
                                  y: size.height * 0.80)
                    VStack(spacing: 9) {
                        Text(L("NIGHTJAR IS NOW LIVE"))
                            .font(.system(
                                .title3,
                                design: .monospaced)
                                .weight(.bold))
                            .tracking(3)
                            .foregroundStyle(Self.liveRed)
                            .shadow(
                                color: Self.liveRed
                                    .opacity(0.85),
                                radius: 14)
                        Text(L("the world is yours"))
                            .font(.system(
                                .caption2,
                                design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(
                                Color(white: 0.62))
                    }
                    .position(x: size.width / 2,
                              y: size.height * 0.80)
                    .opacity(textO)
                }
                .frame(width: size.width,
                       height: size.height)
            }
        }
        .ignoresSafeArea()
    }
}

/// One place for every buzz, so the house speaks one
/// haptic language, felt from any screen — and by the
/// operator's ruling (2026-10-18) it speaks ONCE per
/// act: the pattern beats are retired. A process
/// starting no longer answers its own tap a breath
/// later, a success no longer lands as tap-delay-tap,
/// and the notification generator — whose success,
/// warning, and error are multi-pulse patterns by
/// system design — is out of the language entirely.
/// Meaning is carried by WEIGHT alone: light for a
/// touch, medium for an act taken or landed, rigid
/// for a warning, heavy for an error and for the
/// emergency stop. And because many acts are spoken
/// by two callers at once (a button's tap and the
/// toast its result raises, a tab's selection and
/// the view it opens), every beat passes one gate:
/// a beat asked for within a third of a second of
/// the last one spoken is folded into it. One act,
/// one vibe, everywhere. (The boot's per-line
/// keystroke keeps its own rapid voice — a typed
/// line is a sequence by nature, not an act.)
///
/// And one act speaks ONCE — at the touch.
/// The old shape beat at a process's beginning
/// and again at its landing, which the
/// operator heard, everywhere, as tap — delay
/// — tap, and ruled out (2026-10-19). The
/// first repair folded a landing only when it
/// arrived within a breath of the touch; on
/// the device nothing changed, because real
/// landings arrive seconds later, outside any
/// honest fold, and spoke as a second act.
/// So the law's second pass is plainer:
/// LANDINGS DO NOT SPEAK. Beginnings and
/// completions keep their function names at
/// every call site and are silent. Beats
/// belong to the operator's own hand — a
/// touch, a press, a selection — and to
/// verdicts that arrive unattached to a
/// fresh act: a warning or an error raised
/// by background work speaks; one raised by
/// the act his hand just took folds into
/// that act's own beat. The heaviest voice
/// and the emergency stop are acts entire
/// in themselves and always land.
enum Haptics {
    /// The house switch (Colours → Touch): off
    /// means the motor never speaks — no beat
    /// of any class, the console's tests
    /// included. On by default; the house
    /// reset restores it on, like every
    /// setting. Every beat in this enum flows
    /// through onMain, and onMain asks here
    /// first — one gate, total coverage.
    static var enabled: Bool {
        UserDefaults.standard.object(
            forKey: "house.haptics") as? Bool ?? true
    }

    // One retained generator per voice, kept
    // prepared for the next beat. The old way —
    // a fresh generator built and fired in the
    // same instant — speaks unreliably, and a
    // call made off the main thread is dropped
    // by the system without a word. Together
    // they read on the device as "haptics
    // missing in some areas": the deliberate
    // button taps mostly landed, while the
    // programmatic beats (a toast landing from
    // background work, a process finishing on a
    // socket callback) went silently missing.
    private static let lightGen =
        UIImpactFeedbackGenerator(style: .light)
    private static let rigidGen =
        UIImpactFeedbackGenerator(style: .rigid)
    private static let mediumGen =
        UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGen =
        UIImpactFeedbackGenerator(style: .heavy)
    private static let softGen =
        UIImpactFeedbackGenerator(style: .soft)

    /// Every beat speaks on the main thread, or
    /// it does not speak at all.
    private static func onMain(
        _ body: @escaping () -> Void) {
        guard enabled else { return }
        if Thread.isMainThread { body() }
        else {
            DispatchQueue.main.async(execute: body)
        }
    }

    /// When the last beat actually spoke, and
    /// when the operator's last act began.
    /// Touched only on the main thread, inside
    /// the gates.
    private static var lastBeatAt: TimeInterval = 0
    private static var lastInitiationAt:
        TimeInterval = 0

    /// The haptics trail in the flight
    /// recorder: every beat that fires, every
    /// beat that folds, every call the law
    /// silences — so a complaint about the
    /// motor can be convicted from the log
    /// instead of argued from feel (the
    /// operator's third word on haptics,
    /// 2026-10-19). Recorded only while
    /// developer options are on, like every
    /// flight-recorder line.
    private static func trace(_ line: String) {
        DevLog.event("haptics", line)
    }

    /// An initiation: the act's one beat.
    private static func initiation(
        _ label: String,
        _ body: @escaping () -> Void) {
        onMain {
            let now = Date()
                .timeIntervalSince1970
            guard now - lastBeatAt >= 0.35
            else {
                trace("\(label) folded "
                      + "(a beat just spoke)")
                return
            }
            lastBeatAt = now
            lastInitiationAt = now
            trace("\(label) fired")
            body()
        }
    }

    /// A verdict: a warning or error belonging
    /// to the act his hand just took is folded
    /// into it; a verdict from background work,
    /// with no fresh act under it, speaks.
    private static func echo(
        _ label: String,
        _ body: @escaping () -> Void) {
        onMain {
            let now = Date()
                .timeIntervalSince1970
            guard now - lastInitiationAt >= 1.6,
                  now - lastBeatAt >= 0.35
            else {
                trace("\(label) folded "
                      + "(it rides a fresh act)")
                return
            }
            lastBeatAt = now
            trace("\(label) fired")
            body()
        }
    }

    /// An absolute beat: always lands.
    private static func absolute(
        _ label: String,
        _ body: @escaping () -> Void) {
        onMain {
            let now = Date()
                .timeIntervalSince1970
            guard now - lastBeatAt >= 0.35
            else {
                trace("\(label) folded "
                      + "(a beat just spoke)")
                return
            }
            lastBeatAt = now
            trace("\(label) fired")
            body()
        }
    }

    static func tap() {
        initiation("tap") {
            lightGen.impactOccurred()
            lightGen.prepare()
        }
    }

    /// The boot sequence's per-line keystroke.
    /// Raised from 0.3: the developer panel
    /// proved 0.3 rigid sits under the
    /// operator's threshold — every other beat
    /// in the kit was felt, that one never.
    static func tick() {
        trace("tick fired")
        onMain {
            rigidGen.impactOccurred(intensity: 0.6)
            rigidGen.prepare()
        }
    }

    static func select() {
        initiation("select") {
            // A crisp rigid impact stands in for
            // the selection generator, which is
            // retired: on the operator's device
            // selectionChanged() was issued again
            // and again — from tab observers, from
            // the platform's own sensory feedback,
            // from the selection binding's setter —
            // and never once felt, while impact
            // beats land. A selection in this
            // house is spoken by the rigid voice at
            // a clear intensity instead.
            rigidGen.impactOccurred(intensity: 0.7)
            rigidGen.prepare()
        }
    }

    /// Diagnosis only: the retired selection
    /// generator, kept prepared and fired raw
    /// from the developer console's haptics
    /// test, so its silence or speech on a
    /// given device is measured, not argued.
    private static let rawSelectionGen =
        UISelectionFeedbackGenerator()

    static func rawSelection() {
        trace("rawSelection fired")
        onMain {
            rawSelectionGen.selectionChanged()
            rawSelectionGen.prepare()
        }
    }

    /// A deliberate press — a primary action taken.
    static func press() {
        initiation("press") {
            mediumGen.impactOccurred()
            mediumGen.prepare()
        }
    }

    /// The heaviest single beat the house owns.
    static func heavy() {
        absolute("heavy") {
            heavyGen.impactOccurred()
            heavyGen.prepare()
        }
    }

    /// A soft settle — things standing down,
    /// closing, being put away. Silent by the
    /// law above: a settle is a landing.
    static func pulse() {
        trace("pulse called — silent by law")
    }

    /// Landed well. Silent by the law above:
    /// the touch that launched the act carried
    /// its beat, and the landing is spoken by
    /// the toast and the board, not the motor.
    /// (The notification generator's old
    /// success was a two-pulse pattern — the
    /// tap-delay-tap the operator ruled out.)
    static func success() {
        trace("success called — silent by law")
    }

    /// Diagnosis only: the success beat, fired
    /// raw from the developer console's haptics
    /// test, so the voice itself can still be
    /// measured on a device.
    static func testSuccess() {
        trace("testSuccess fired")
        onMain {
            mediumGen.impactOccurred()
            mediumGen.prepare()
        }
    }

    /// Diagnosis only: the error beat, raw,
    /// for the same console test.
    static func testError() {
        trace("testError fired")
        onMain {
            heavyGen.impactOccurred()
            heavyGen.prepare()
        }
    }

    /// A warning: one rigid beat at full
    /// strength — sharper than an act, lighter
    /// than an error. An echo: a warning his own
    /// tap just earned arrives in the toast's
    /// words, not a second buzz.
    static func warn() {
        echo("warn") {
            rigidGen.impactOccurred(intensity: 1.0)
            rigidGen.prepare()
        }
    }

    /// An error: one heavy beat, on the same
    /// echo terms as the warning.
    static func error() {
        echo("error") {
            heavyGen.impactOccurred()
            heavyGen.prepare()
        }
    }

    /// A process begins: silent by the law
    /// above — the touch that launched it (or
    /// her spoken word, for an order) already
    /// carried the beat.
    static func start() {
        trace("start called — silent by law")
    }

    /// A process lands well: silent — see
    /// success().
    static func finish() {
        trace("finish called — silent by law")
    }

    /// The emergency stop: the heaviest
    /// single beat the house owns, once —
    /// unmistakable by weight, not by count.
    static func vanish() {
        absolute("vanish") {
            heavyGen.impactOccurred()
            heavyGen.prepare()
        }
    }
}


// MARK: Centipede release splash

extension UIImage {
    /// Decode an animated GIF's frames and delays the ImageIO
    /// way, so a bundled .gif plays as authored.
    static func animatedGIF(data: Data) -> UIImage? {
#if os(macOS)
        // The Mac's image type carries an animated
        // GIF's frames natively and decodes them
        // lazily; the ImageIO hand decode below —
        // and its frame budget — is the phone's
        // road, where every frame lands resident.
        return NSImage(data: data)
#endif
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var total = 0.0
        // A decoded-frame budget, spent as frames
        // land. This decoder serves backdrops the
        // operator chose themselves, and a GIF is
        // a claim about memory: frames x pixels x
        // four bytes, all resident at once. A long,
        // large film can claim gigabytes — the same
        // jetsam wall the weights bench hit. Past
        // the budget the film simply ends early;
        // a shorter loop over a dead app.
        var budget: Int64 = 384 * 1_048_576
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(
                source, i, nil) else { continue }
            let cost = Int64(cg.width)
                * Int64(cg.height) * 4
            if cost > budget { break }
            budget -= cost
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(
                source, i, nil) as? [String: Any],
               let gif = props[kCGImagePropertyGIFDictionary
                               as String] as? [String: Any] {
                delay = (gif[kCGImagePropertyGIFUnclampedDelayTime
                             as String] as? Double)
                    ?? (gif[kCGImagePropertyGIFDelayTime
                            as String] as? Double)
                    ?? 0.1
            }
            total += max(delay, 0.02)
            frames.append(platformImage(cgImage: cg))
        }
        guard !frames.isEmpty else { return nil }
#if os(macOS)
        return NSImage(data: data)
#else
        return UIImage.animatedImage(with: frames, duration: total)
#endif
    }

    /// The authored delay of every frame, read from
    /// properties alone — no frame is decoded, so
    /// asking costs nothing even for a long film.
    static func gifDelays(_ data: Data) -> [Double] {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(source)
        var out: [Double] = []
        for i in 0..<count {
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(
                source, i, nil) as? [String: Any],
               let gif = props[kCGImagePropertyGIFDictionary
                               as String] as? [String: Any] {
                delay = (gif[kCGImagePropertyGIFUnclampedDelayTime
                             as String] as? Double)
                    ?? (gif[kCGImagePropertyGIFDelayTime
                            as String] as? Double)
                    ?? 0.1
            }
            out.append(max(delay, 0.02))
        }
        return out
    }

    /// The film as frames, decoded at a capped size:
    /// the GIF's frames, composited, with the longer
    /// edge at most `maxPixel`, and the film's true
    /// duration. Thumbnails do the scaling inside the
    /// decode; if a frame ever comes back the wrong
    /// shape — an optimized GIF storing bare
    /// difference rectangles — the whole film falls
    /// back to full decodes drawn down to size.
    /// Correct over fast, and bounded either way.
    static func gifFrames(data: Data, maxPixel: Int)
        -> (frames: [UIImage], duration: Double) {
        let delays = gifDelays(data)
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil), !delays.isEmpty
        else { return ([], 0) }
        let duration = delays.reduce(0, +)
        let count = CGImageSourceGetCount(source)

        var sourceAspect: CGFloat = 0
        if let props = CGImageSourceCopyPropertiesAtIndex(
            source, 0, nil) as? [String: Any],
           let w = (props[kCGImagePropertyPixelWidth
                          as String] as? NSNumber)?
               .doubleValue,
           let h = (props[kCGImagePropertyPixelHeight
                          as String] as? NSNumber)?
               .doubleValue, h > 0 {
            sourceAspect = CGFloat(w / h)
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:
                true,
            kCGImageSourceCreateThumbnailWithTransform:
                true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        var frames: [UIImage] = []
        var thumbnailsHold = true
        for i in 0..<count {
            guard let cg =
                CGImageSourceCreateThumbnailAtIndex(
                    source, i,
                    thumbOptions as CFDictionary)
            else { thumbnailsHold = false; break }
            if sourceAspect > 0 {
                let aspect = CGFloat(cg.width)
                    / CGFloat(max(cg.height, 1))
                if abs(aspect - sourceAspect)
                    > sourceAspect * 0.12 {
                    thumbnailsHold = false
                    break
                }
            }
            frames.append(platformImage(cgImage: cg))
        }
        if thumbnailsHold, frames.count == count {
            return (frames, duration)
        }

        frames = []
        for i in 0..<count {
            guard let cg =
                CGImageSourceCreateImageAtIndex(
                    source, i, nil) else { continue }
            let scale = min(1, CGFloat(maxPixel)
                / CGFloat(max(cg.width, cg.height)))
            if scale >= 1 {
                frames.append(platformImage(cgImage: cg))
                continue
            }
            let w = Int(CGFloat(cg.width) * scale)
            let h = Int(CGFloat(cg.height) * scale)
            guard w > 0, h > 0,
                  let ctx = CGContext(
                    data: nil, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo
                        .premultipliedLast.rawValue)
            else {
                frames.append(platformImage(cgImage: cg))
                continue
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0,
                                    width: w, height: h))
            if let scaled = ctx.makeImage() {
                frames.append(platformImage(cgImage: scaled))
            }
        }
        return (frames, duration)
    }
}

#if os(iOS)
/// A full-bleed GIF player (UIImageView under the hood).
struct GIFPlayerView: UIViewRepresentable {
    let data: Data
    var contentMode: UIView.ContentMode = .scaleAspectFill
    /// Play the reel through once and hold its
    /// last frame, instead of looping forever —
    /// for splashes whose film is a single act
    /// (the EAZY ignition: the spin, the blast,
    /// and stop). Default off: backdrops loop.
    var playOnce = false
    @AppStorage(BootMedia.gifsKey)
    private var gifsEnabled = true

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.backgroundColor = .black
        configure(view)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        configure(view)
    }

    /// Play the reel — full-size in quality
    /// mode, decoded light in performance
    /// mode — or, when the house has stilled
    /// its GIFs, stand its first frame.
    private func configure(_ view: UIImageView) {
        guard gifsEnabled else {
            view.stopAnimating()
            view.animationImages = nil
            if view.image == nil
                || view.image?.images != nil {
                view.image = UIImage(data: data)
            }
            return
        }
        if BootMedia.performanceMode {
            // Already standing on the capped decode.
            if view.animationImages != nil { return }
            let film = UIImage.gifFrames(
                data: data, maxPixel: 640)
            guard let first = film.frames.first
            else { return }
            view.image = playOnce
                ? (film.frames.last ?? first) : first
            view.animationImages = film.frames
            view.animationDuration = film.duration
            view.animationRepeatCount = playOnce ? 1 : 0
            view.startAnimating()
        } else if playOnce {
            // One pass at full size, then the last
            // frame stands. The frames path (not
            // the animated-image path) so the held
            // frame is the film's end, not its start;
            // once decoded, a reconfigure leaves it
            // standing rather than playing it again.
            if view.animationImages != nil { return }
            let film = UIImage.gifFrames(
                data: data, maxPixel: 2048)
            guard let last = film.frames.last
            else { return }
            view.image = last
            view.animationImages = film.frames
            view.animationDuration = film.duration
            view.animationRepeatCount = 1
            view.startAnimating()
        } else {
            if view.animationImages != nil {
                // Came from the capped decode;
                // rebuild at full size.
                view.animationImages = nil
                view.image = nil
            }
            if view.isAnimating { return }
            if let image = UIImage.animatedGIF(data: data) {
                view.image = image
                view.startAnimating()
            }
        }
    }
}

/// The boot film's stage: a screen-sized container
/// that lays the film out INSIDE itself — filled,
/// zoomed, and set on the film's subject — so the
/// SwiftUI layout around it never feels the film's
/// size. The image view is sized to the film's exact
/// displayed size and placed so the focus point
/// (the subject's place in the frame) lands at the
/// container's centre.
final class BootFilmContainer: UIView {
    let imageView = UIImageView()
    /// The video road's stage (fix259), framed
    /// by the same hand as the image view.
    let playerLayer = AVPlayerLayer()
    var focus = CGPoint(x: 0.5, y: 0.5)
    var zoom: CGFloat = 1
    var imageAspect: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.isHidden = true
        layer.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageAspect > 0, bounds.width > 0,
              bounds.height > 0 else {
            imageView.frame = bounds
            playerLayer.frame = bounds
            return
        }
        var w = bounds.height * imageAspect
        var h = bounds.height
        if w < bounds.width {
            w = bounds.width
            h = bounds.width / imageAspect
        }
        w *= zoom
        h *= zoom
        imageView.frame = CGRect(
            x: bounds.width / 2 - focus.x * w,
            y: bounds.height / 2 - focus.y * h,
            width: w, height: h)
        playerLayer.frame = imageView.frame
    }
}

/// The boot film: a GIF played exactly once, the
/// platform's own way — the frames decoded once, up
/// front, into an animated image, and UIKit's player
/// runs it: the same road the wallpaper reel has
/// always taken, and the reason it has always been
/// smooth. Decoding happens on a background queue at
/// a capped size (a long film costs a bounded,
/// transient memory, freed when the boot ends), the
/// film fades in when it is ready, and the last
/// frame holds when it ends. A small clock reports
/// progress; it does no image work at all.
struct BootFilmPlayer: UIViewRepresentable {
    let data: Data
    var focusX: CGFloat = 0.5
    var focusY: CGFloat = 0.5
    var zoom: CGFloat = 1
    /// The decode cap, from the house's picture
    /// mode: quality decodes wide, performance
    /// decodes light.
    var maxPixel: Int = 1024
    var onProgress: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BootFilmContainer {
        let view = BootFilmContainer()
        view.focus = CGPoint(x: focusX, y: focusY)
        view.zoom = zoom
        view.alpha = 0
        context.coordinator.begin(in: view, data: data,
                                  maxPixel: maxPixel,
                                  onProgress: onProgress)
        return view
    }

    func updateUIView(_ view: BootFilmContainer,
                      context: Context) {}

    static func dismantleUIView(
        _ view: BootFilmContainer,
        coordinator: Coordinator
    ) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private weak var view: BootFilmContainer?
        private var onProgress: ((Double) -> Void)?
        private var link: CADisplayLink?
        private var started: CFTimeInterval = 0
        private var duration = 0.0
        private var lastReported = -1.0
        private var cancelled = false
        private var player: AVPlayer?
        private var timeObserver: Any?

        func begin(in view: BootFilmContainer, data: Data,
                   maxPixel: Int,
                   onProgress: @escaping (Double) -> Void) {
            self.view = view
            self.onProgress = onProgress
            if BootMedia.isVideo(data) {
                beginVideo(in: view, data: data,
                           onProgress: onProgress)
                return
            }
            DispatchQueue.global(qos: .userInitiated)
                .async {
                let film = UIImage.gifFrames(
                    data: data, maxPixel: maxPixel)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          !self.cancelled,
                          let view = self.view,
                          let first = film.frames.first,
                          let last = film.frames.last
                    else { return }
                    view.imageAspect = first.size.width
                        / max(first.size.height, 1)
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                    let image = view.imageView
                    image.image = last
                    image.animationImages = film.frames
                    image.animationDuration = film.duration
                    image.animationRepeatCount = 1
                    image.startAnimating()
                    UIView.animate(withDuration: 0.35) {
                        view.alpha = 1
                    }
                    self.duration = film.duration
                    self.started = CACurrentMediaTime()
                    let link = CADisplayLink(
                        target: self,
                        selector: #selector(self.tick))
                    link.add(to: .main, forMode: .common)
                    self.link = link
                }
            }
        }

        /// The video road (fix259): the film is
        /// written to a scratch file and an
        /// AVPlayer rides it inside the container's
        /// own layer — the Mac twin's shape, in
        /// UIKit's clothes. The films are cut for
        /// their screens, so the layer fills the
        /// container and its aspect-fill gravity
        /// does the framing; the last frame holds
        /// when the film ends, and a small clock
        /// reports progress, as on the GIF road.
        private func beginVideo(
            in view: BootFilmContainer, data: Data,
            onProgress: @escaping (Double) -> Void
        ) {
            DispatchQueue.global(qos: .userInitiated)
                .async {
                let url = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "nightjar-bootfilm.mp4")
                guard (try? data.write(
                    to: url, options: .atomic)) != nil
                else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          !self.cancelled,
                          let view = self.view
                    else { return }
                    let player = AVPlayer(url: url)
                    player.actionAtItemEnd = .pause
                    self.player = player
                    view.playerLayer.player = player
                    view.playerLayer.isHidden = false
                    view.setNeedsLayout()
                    view.layoutIfNeeded()
                    UIView.animate(
                        withDuration: 0.35) {
                        view.alpha = 1
                    }
                    let report = onProgress
                    self.timeObserver = player
                        .addPeriodicTimeObserver(
                        forInterval: CMTime(
                            seconds: 0.1,
                            preferredTimescale: 600),
                        queue: .main) { time in
                        if let duration = player
                            .currentItem?.duration
                            .seconds, duration > 0 {
                            report(min(1,
                                time.seconds / duration))
                        }
                    }
                    player.play()
                }
            }
        }

        @objc private func tick() {
            guard duration > 0 else { return }
            let progress = min(1,
                (CACurrentMediaTime() - started)
                    / duration)
            if progress >= 1 {
                if lastReported != 1 {
                    lastReported = 1
                    onProgress?(1)
                }
                link?.invalidate()
                link = nil
                return
            }
            if progress - lastReported > 0.01
                || lastReported < 0 {
                lastReported = progress
                onProgress?(progress)
            }
        }

        func stop() {
            cancelled = true
            link?.invalidate()
            link = nil
            view?.imageView.stopAnimating()
            if let player = player,
               let observer = timeObserver {
                player.removeTimeObserver(observer)
            }
            timeObserver = nil
            player?.pause()
            player = nil
        }
    }
}


#endif
/// The drumroll: a glitching, laughing skull over the whole
/// screen when the centipede is released (tap to skip). The
/// GIF comes from a "Centipede" data asset or a centipede.gif
/// file in the bundle, and the splash stays up for the GIF's
/// own duration (plus a beat); without a GIF, a built-in
/// flicker card stands in for 3 s, so the app is never broken
/// by a missing flourish. The crawl itself starts the moment
/// Release is tapped — the splash is pure theatre laid over
/// its first hops.
struct CentipedeSplashView: View {
    @Binding var isShown: Bool
    @State private var flicker = false

    private var gifData: Data? {
        if let asset = NSDataAsset(name: "Centipede") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "centipede",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    /// How long the splash stays: the GIF's own play length
    /// plus a breath, clamped sane; 3 s for the fallback card.
    private var splashSeconds: Double {
        guard let data = gifData else { return 3.0 }
        // The length from the frame headers alone —
        // never a full decode just to tell time.
        let seconds = UIImage.gifDelays(data).reduce(0, +)
        guard seconds > 0 else { return 3.0 }
        return min(max(seconds + 0.3, 1.5), 6.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                GIFPlayerView(data: data)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "ant.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.teal)
                    Text("CENTIPEDE RELEASED")
                        .font(.headline.monospaced())
                        .tracking(4)
                        .foregroundStyle(.white)
                }
                .opacity(flicker ? 0.55 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)) {
                        flicker = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isShown = false }
        .onAppear {
            Haptics.success()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + splashSeconds) {
                isShown = false
            }
        }
    }
}

/// The charge-up: a fighter powering up in the rain over
/// the whole screen when EAZY is released (tap to skip).
/// The GIF comes from a "Rainfall" data asset or a
/// rainfall.gif file in the bundle (Chase's pick, wired
/// 2026-10-21), and the splash stays up for the GIF's own
/// duration (plus a beat); without a GIF, a built-in
/// flicker card stands in. The scan starts the moment
/// EAZY is ordered — the splash is pure theatre laid
/// over its first probes, the centipede's doctrine.
struct EazyIgnitionView: View {
    @Binding var isShown: Bool
    @State private var flicker = false

    private var gifData: Data? {
        if let asset = NSDataAsset(name: "Rainfall") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "rainfall",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    /// How long the splash stays: the GIF's own play
    /// length plus a breath, clamped sane; 3 s for the
    /// fallback card.
    private var splashSeconds: Double {
        guard let data = gifData else { return 3.0 }
        let seconds = UIImage.gifDelays(data).reduce(0, +)
        guard seconds > 0 else { return 3.0 }
        return min(max(seconds + 0.3, 1.5), 6.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                GIFPlayerView(data: data, playOnce: true)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(.yellow)
                    Text("EAZY RELEASED")
                        .font(.headline.monospaced())
                        .tracking(4)
                        .foregroundStyle(.white)
                }
                .opacity(flicker ? 0.55 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)) {
                        flicker = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isShown = false }
        .onAppear {
            Haptics.success()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + splashSeconds) {
                isShown = false
            }
        }
    }
}

/// The lock-on: a cockpit targeting reel over the
/// whole screen when MAGDUMP is released, ending on
/// TARGET LOCK ON (tap to skip). The GIF comes from
/// a "Magdump" data asset or a magdump.gif file in
/// the bundle (Chase's pick, wired with the program),
/// and the splash stays up for the GIF's own duration
/// (plus a beat); without a GIF, a built-in flicker
/// card stands in. The battery starts the moment
/// MAGDUMP is ordered — the splash is pure theatre
/// laid over its first probes, the centipede's
/// doctrine, same as EAZY's charge-up.
struct MagdumpIgnitionView: View {
    @Binding var isShown: Bool
    @State private var flicker = false

    private var gifData: Data? {
        if let asset = NSDataAsset(name: "Magdump") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "magdump",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    /// How long the splash stays: the GIF's own play
    /// length plus a breath, clamped sane; 3 s for the
    /// fallback card.
    private var splashSeconds: Double {
        guard let data = gifData else { return 3.0 }
        let seconds = UIImage.gifDelays(data).reduce(0, +)
        guard seconds > 0 else { return 3.0 }
        return min(max(seconds + 0.3, 1.5), 6.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                GIFPlayerView(data: data)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "scope")
                        .font(.system(size: 96))
                        .foregroundStyle(.red)
                    Text("TARGET LOCK ON")
                        .font(.headline.monospaced())
                        .tracking(4)
                        .foregroundStyle(.white)
                }
                .opacity(flicker ? 0.55 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)) {
                        flicker = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isShown = false }
        .onAppear {
            Haptics.success()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + splashSeconds) {
                isShown = false
            }
        }
    }
}

/// The frame: her fingers close a blood-red frame over
/// the whole screen when EMCON falls to Alpha (tap to
/// skip). The GIF comes from a "Redframe" data asset or
/// a redframe.gif file in the bundle (Chase's pick, wired
/// 2026-10-21), and the splash stays up for the GIF's
/// own duration (plus a beat); without a GIF, a built-in
/// flicker card stands in. The silence itself is never
/// delayed — the Standard silences first, and this is
/// the theatre laid over the hush.
struct RedframeSplashView: View {
    @Binding var isShown: Bool
    @State private var flicker = false

    private var gifData: Data? {
        if let asset = NSDataAsset(name: "Redframe") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "redframe",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    /// How long the splash stays: the GIF's own play
    /// length plus a breath, clamped sane; 3 s for the
    /// fallback card.
    private var splashSeconds: Double {
        guard let data = gifData else { return 3.0 }
        let seconds = UIImage.gifDelays(data).reduce(0, +)
        guard seconds > 0 else { return 3.0 }
        return min(max(seconds + 0.3, 1.5), 6.0)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                GIFPlayerView(data: data)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 96))
                        .foregroundStyle(.red)
                    Text("EMCON ALPHA")
                        .font(.headline.monospaced())
                        .tracking(4)
                        .foregroundStyle(.white)
                }
                .opacity(flicker ? 0.55 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.14)
                        .repeatForever(autoreverses: true)) {
                        flicker = true
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isShown = false }
        .onAppear {
            Haptics.success()
            DispatchQueue.main.asyncAfter(
                deadline: .now() + splashSeconds) {
                isShown = false
            }
        }
    }
}

/// One share payload, identifiable so a screen's root can
/// present the share sheet for it with `.sheet(item:)`.
/// Shares in this app are doors: a button in a list raises
/// one of these, and the sheet itself hangs off the
/// screen's outermost view — a bare ShareLink buried in a
/// list section cannot find a presentation host here and
/// dies silently under the finger.
struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}

// MARK: - The folded explanation

/// What a thing does, folded away until asked:
/// one quiet row that opens into a terse, exact
/// explanation — what it does, why, and how it
/// can be useful. Screens explain themselves on
/// request instead of lecturing at rest.
struct ExplainToggle: View {
    var title: String = "What this does"
    let text: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) {
                    open.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text(L(title))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: open
                          ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false,
                               vertical: true)
            }
        }
    }
}

// MARK: - Her browser window

/// What her face is doing — the avatar reads it.
enum SkelliMood {
    case idle, thinking, working, speaking
}

enum SkelliWeb {
    struct Finding {
        var text: String
        var source: String
        var url: String
        var score: Int = 0
        var preformatted: Bool = false
    }

    /// Where the browser is, in words, as it works —
    /// the center speaks it on her status line.
    static var onProgress: ((String) -> Void)?

    static func research(_ query: String,
                         completion: @escaping (String) -> Void) {
        let group = DispatchGroup()
        let collect = DispatchQueue(label: "skelli.web.collect")
        var instant: Finding?
        var wiki: Finding?
        var scouted: Finding?
        var pages: [Finding] = []
        var walls = 0
        let terms = searchTerms(query)
        onProgress?(L("Asking the open indexes…"))

        if let url = endpoint("https://api.duckduckgo.com/",
                              items: [
                                  URLQueryItem(name: "q",
                                               value: query),
                                  URLQueryItem(name: "format",
                                               value: "json"),
                                  URLQueryItem(name: "no_html",
                                               value: "1"),
                                  URLQueryItem(name: "skip_disambig",
                                               value: "1"),
                              ]) {
            group.enter()
            fetchJSON(url) { dict in
                let found = duckDuckGoFinding(dict)
                collect.sync { instant = found }
                group.leave()
            }
        }
        if let url = endpoint("https://en.wikipedia.org/w/api.php",
                              items: [
                                  URLQueryItem(name: "action",
                                               value: "query"),
                                  URLQueryItem(name: "generator",
                                               value: "search"),
                                  URLQueryItem(name: "gsrsearch",
                                               value: query),
                                  URLQueryItem(name: "gsrlimit",
                                               value: "3"),
                                  URLQueryItem(name: "prop",
                                               value: "extracts|info"),
                                  URLQueryItem(name: "exintro",
                                               value: "1"),
                                  URLQueryItem(name: "explaintext",
                                               value: "1"),
                                  URLQueryItem(name: "inprop",
                                               value: "url"),
                                  URLQueryItem(name: "format",
                                               value: "json"),
                              ]) {
            group.enter()
            fetchJSON(url) { dict in
                let found = wikipediaFinding(dict)
                collect.sync { wiki = found }
                group.leave()
            }
        }

        group.enter()
        scout(query: query, terms: terms) { found in
            collect.sync { scouted = found }
            group.leave()
        }

        group.enter()
        if let lite = endpoint(
            "https://lite.duckduckgo.com/lite/",
            items: [URLQueryItem(name: "q", value: query)]) {
            onProgress?(L("Searching the lite index…"))
            fetchText(lite) { html in
                let results = html.map(liteResults) ?? []
                for result in results.prefix(3) {
                    group.enter()
                    gatherPage(result, terms: terms) {
                        finding, hitWall in
                        collect.sync {
                            if let finding = finding {
                                pages.append(finding)
                            }
                            if hitWall { walls += 1 }
                        }
                        group.leave()
                    }
                }
                group.leave()
            }
        } else {
            group.leave()
        }

        group.notify(queue: .main) {
            completion(compose(query: query, scout: scouted,
                               pages: pages, instant: instant,
                               wiki: wiki, walls: walls))
        }
    }

    // MARK: fetching

    private static func endpoint(
        _ base: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items
        return components?.url
    }

    private static func fetchData(
        _ url: URL,
        completion: @escaping (Data?, HTTPURLResponse?) -> Void) {
        var request = URLRequest(url: url,
                                 timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 "
                + "like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 "
                + "Mobile/15E148 Safari/604.1 Skelli",
            forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) {
            data, response, _ in
            completion(data, response as? HTTPURLResponse)
        }.resume()
    }

    private static func fetchText(
        _ url: URL, completion: @escaping (String?) -> Void) {
        fetchData(url) { data, response in
            guard let http = response,
                  (200...299).contains(http.statusCode),
                  let data = data
            else {
                completion(nil)
                return
            }
            completion(
                String(data: data, encoding: .utf8)
                    ?? String(data: data,
                              encoding: .isoLatin1))
        }
    }

    private static func fetchJSON(
        _ url: URL,
        completion: @escaping ([String: Any]?) -> Void) {
        fetchData(url) { data, response in
            guard let http = response,
                  (200...299).contains(http.statusCode),
                  let data = data,
                  let object = try? JSONSerialization
                      .jsonObject(with: data),
                  let dict = object as? [String: Any]
            else {
                completion(nil)
                return
            }
            completion(dict)
        }
    }

    // MARK: the instant parsers

    private static func duckDuckGoFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let dict = dict else { return nil }
        let source = (dict["AbstractSource"] as? String)
            ?? "DuckDuckGo"
        if let answer = dict["Answer"] as? String,
           !answer.isEmpty {
            return Finding(text: answer, source: source,
                           url: (dict["AbstractURL"]
                               as? String)
                               ?? "https://duckduckgo.com")
        }
        if let abstract = dict["AbstractText"] as? String,
           !abstract.isEmpty {
            return Finding(text: abstract, source: source,
                           url: (dict["AbstractURL"]
                               as? String)
                               ?? "https://duckduckgo.com")
        }
        return firstTopic(dict["RelatedTopics"])
    }

    private static func firstTopic(_ any: Any?) -> Finding? {
        guard let topics = any as? [[String: Any]] else {
            return nil
        }
        for topic in topics {
            if let text = topic["Text"] as? String,
               !text.isEmpty {
                return Finding(
                    text: text, source: "DuckDuckGo",
                    url: (topic["FirstURL"] as? String)
                        ?? "https://duckduckgo.com")
            }
            if let nested = firstTopic(topic["Topics"]) {
                return nested
            }
        }
        return nil
    }

    private static func wikipediaFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let query = dict?["query"] as? [String: Any],
              let pages = query["pages"]
                  as? [String: [String: Any]]
        else { return nil }
        let ordered = pages.values.sorted {
            (($0["index"] as? Int) ?? 99)
                < (($1["index"] as? Int) ?? 99)
        }
        for page in ordered {
            if let extract = page["extract"] as? String,
               !extract.isEmpty {
                return Finding(
                    text: extract, source: "Wikipedia",
                    url: (page["fullurl"] as? String)
                        ?? "https://en.wikipedia.org")
            }
        }
        return nil
    }

    // MARK: the scouts — friendly doors, chosen by intent

    private static func scout(
        query: String, terms: [String],
        completion: @escaping (Finding?) -> Void) {
        let q = query.lowercased()

        if let number = firstCapture(
            "rfc\\s*#?\\s*(\\d{1,5})", in: q),
           let url = URL(string: "https://www.rfc-editor.org"
                         + "/rfc/rfc" + number + ".txt") {
            fetchText(url) { text in
                completion(text.map {
                    Finding(
                        text: bestExcerpt(
                            $0, terms: terms + ["abstract"],
                            maxChars: 640),
                        source: "RFC " + number
                            + " — the RFC Editor",
                        url: "https://www.rfc-editor.org"
                            + "/info/rfc" + number,
                        score: 100, preformatted: true)
                })
            }
            return
        }

        if q.contains("arxiv") || q.contains("paper")
            || q.contains("study")
            || q.contains("journal article") {
            let encoded = query.addingPercentEncoding(
                withAllowedCharacters:
                    .urlQueryAllowed) ?? query
            if let url = URL(string: "https://export.arxiv.org"
                             + "/api/query?search_query=all:"
                             + encoded
                             + "&start=0&max_results=2") {
                fetchText(url) { xml in
                    completion(xml.flatMap(arxivFinding))
                }
                return
            }
        }

        if q.contains("book") || q.contains("author")
            || q.contains("novel") || q.contains("isbn") {
            if let url = endpoint(
                "https://openlibrary.org/search.json",
                items: [URLQueryItem(name: "q",
                                     value: query),
                        URLQueryItem(name: "limit",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(openLibraryFinding(dict))
                }
                return
            }
        }

        if q.contains("github") || q.contains("repository")
            || q.contains("repositories")
            || q.contains(" repo ")
            || q.hasSuffix(" repo") {
            if let url = endpoint(
                "https://api.github.com/search/repositories",
                items: [URLQueryItem(name: "q",
                                     value: query),
                        URLQueryItem(name: "sort",
                                     value: "stars"),
                        URLQueryItem(name: "per_page",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(githubFinding(dict))
                }
                return
            }
        }

        if q.contains("stack overflow")
            || q.contains("stackoverflow") {
            let cleaned = q
                .replacingOccurrences(
                    of: "stack overflow", with: "")
                .replacingOccurrences(
                    of: "stackoverflow", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let url = endpoint(
                "https://api.stackexchange.com/2.3"
                    + "/search/advanced",
                items: [URLQueryItem(name: "order",
                                     value: "desc"),
                        URLQueryItem(name: "sort",
                                     value: "relevance"),
                        URLQueryItem(name: "q",
                                     value: cleaned),
                        URLQueryItem(name: "site",
                                     value: "stackoverflow"),
                        URLQueryItem(name: "pagesize",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(stackExchangeFinding(dict))
                }
                return
            }
        }

        completion(nil)
    }

    private static func arxivFinding(_ xml: String)
        -> Finding? {
        let entries = regexMatches(
            "(?s)<entry>(.*?)</entry>", in: xml)
        guard !entries.isEmpty else { return nil }
        var lines: [String] = []
        var firstURL = "https://arxiv.org"
        for entry in entries.prefix(2) {
            let block = entry[1]
            let title = clean(decodeEntities(
                firstCapture("<title>(.*?)</title>",
                             in: block) ?? ""))
            let summary = clean(decodeEntities(
                firstCapture("<summary>(.*?)</summary>",
                             in: block) ?? ""))
            let link = firstCapture("<id>(.*?)</id>",
                                    in: block) ?? firstURL
            if lines.isEmpty { firstURL = link }
            lines.append(title + " — "
                         + excerpt(summary, maxChars: 300))
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "arXiv", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func openLibraryFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let docs = dict?["docs"]
                as? [[String: Any]], !docs.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://openlibrary.org"
        for doc in docs.prefix(3) {
            let title = (doc["title"] as? String)
                ?? "Untitled"
            let authors = (doc["author_name"]
                as? [String])?.joined(separator: ", ")
            let year = doc["first_publish_year"] as? Int
            var line = title
            if let authors = authors { line += " by " + authors }
            if let year = year { line += " (\(year))" }
            lines.append(line)
            if lines.count == 1,
               let key = doc["key"] as? String {
                firstURL = "https://openlibrary.org" + key
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "Open Library", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func githubFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let items = dict?["items"]
                as? [[String: Any]], !items.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://github.com"
        for item in items.prefix(3) {
            let name = (item["full_name"] as? String)
                ?? "unknown"
            let stars = (item["stargazers_count"] as? Int)
                ?? 0
            let about = (item["description"] as? String)
                ?? L("no description")
            lines.append(name + " (★\(stars)): " + about)
            if lines.count == 1,
               let url = item["html_url"] as? String {
                firstURL = url
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "GitHub", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func stackExchangeFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let items = dict?["items"]
                as? [[String: Any]], !items.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://stackoverflow.com"
        for item in items.prefix(3) {
            let title = clean(decodeEntities(
                stripTags((item["title"] as? String) ?? "")))
            let answers = (item["answer_count"] as? Int)
                ?? 0
            lines.append(title + " — \(answers) answer"
                         + (answers == 1 ? "" : "s"))
            if lines.count == 1,
               let link = item["link"] as? String {
                firstURL = link
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "Stack Overflow", url: firstURL,
                       score: 60, preformatted: true)
    }

    // MARK: her browser — search, visit, read

    private static func liteResults(_ html: String)
        -> [(title: String, url: URL)] {
        var out: [(title: String, url: URL)] = []
        var seen = Set<String>()
        for match in regexMatches(
            "(?is)<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            in: html) {
            var href = match[1]
            if let marker = href.range(of: "uddg=") {
                let tail = href[marker.upperBound...]
                let raw = tail.split(separator: "&")
                    .first.map(String.init) ?? ""
                href = raw.removingPercentEncoding ?? raw
            }
            guard href.hasPrefix("http"),
                  let url = URL(string: href),
                  let host = url.host,
                  !host.contains("duckduckgo.com"),
                  !skippedDomain(host),
                  !seen.contains(href)
            else { continue }
            let title = clean(decodeEntities(
                stripTags(match[2])))
            guard title.count >= 3 else { continue }
            seen.insert(href)
            out.append((title: title, url: url))
        }
        return out
    }

    private static func skippedDomain(_ host: String)
        -> Bool {
        ["nytimes.com", "wsj.com", "ft.com",
         "bloomberg.com", "linkedin.com",
         "facebook.com", "instagram.com", "x.com",
         "twitter.com", "pinterest.com", "quora.com",
         "scribd.com", "researchgate.net"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func gatherPage(
        _ result: (title: String, url: URL),
        terms: [String],
        completion: @escaping (Finding?, Bool) -> Void) {
        onProgress?(String(format: L("Reading %@…"), String(describing: result.url.host ?? L("a page"))))
        fetchData(result.url) { data, response in
            guard let data = data, let http = response,
                  (200...299).contains(http.statusCode)
            else {
                completion(nil, false)
                return
            }
            let mime = http.mimeType ?? ""
            if mime.contains("pdf")
                || result.url.pathExtension
                    .lowercased() == "pdf" {
                if let text = pdfText(data) {
                    completion(Finding(
                        text: bestExcerpt(text, terms: terms),
                        source: result.title,
                        url: result.url.absoluteString,
                        score: score(text, terms: terms),
                        preformatted: true), false)
                } else {
                    completion(nil, false)
                }
                return
            }
            guard let html = String(data: data,
                                    encoding: .utf8)
                    ?? String(data: data,
                              encoding: .isoLatin1)
            else {
                completion(nil, false)
                return
            }
            if hostile(html) {
                completion(nil, true)
                return
            }
            let title = pageTitle(html) ?? result.title
            let extracted = extractText(html)
            if extracted.count >= 600
                && !isChrome(extracted, title: title) {
                completion(Finding(
                    text: bestExcerpt(extracted,
                                      terms: terms),
                    source: title,
                    url: result.url.absoluteString,
                    score: score(extracted, terms: terms),
                    preformatted: true), false)
                return
            }
            DispatchQueue.main.async {
                onProgress?(String(format: L("Rendering %@ in her browser…"), String(describing: result.url.host ?? L("the page"))))
                SkelliWebRenderer.shared.render(
                    url: result.url) { rendered in
                    if let rendered = rendered,
                       rendered.count > extracted.count,
                       !isChrome(rendered, title: title) {
                        if hostile(rendered) {
                            completion(nil, true)
                            return
                        }
                        completion(Finding(
                            text: bestExcerpt(rendered,
                                              terms: terms),
                            source: title,
                            url: result.url.absoluteString,
                            score: score(rendered,
                                         terms: terms),
                            preformatted: true), false)
                    } else if extracted.count >= 200
                        && !isChrome(extracted,
                                     title: title) {
                        completion(Finding(
                            text: bestExcerpt(extracted,
                                              terms: terms),
                            source: title,
                            url: result.url.absoluteString,
                            score: score(extracted,
                                         terms: terms),
                            preformatted: true), false)
                    } else {
                        completion(nil, false)
                    }
                }
            }
        }
    }

    private static func hostile(_ page: String) -> Bool {
        let low = page.lowercased()
        return ["are you a robot", "verify you are human",
                "unusual traffic from your computer",
                "challenge-platform",
                "checking your browser before accessing",
                "request blocked",
                "please complete the security check",
                "enable javascript and cookies to continue"]
            .contains { low.contains($0) }
    }

    /// Page chrome, detected: a real article is
    /// made of sentences; a site's furniture —
    /// menus, category rails, mastheads — is
    /// not. When the gathered text carries
    /// almost no sentence endings for its
    /// length, or repeats its own title at the
    /// head like a masthead, it is furniture,
    /// and furniture is not a finding. (Device
    /// 2026-10-20: "what should we do today"
    /// was answered with a listicle's whole
    /// navigation menu, verbatim.)
    private static func isChrome(_ text: String,
                                 title: String)
        -> Bool {
        if text.count > 600 {
            var ends = 0
            for ch in text where ".!?".contains(ch) {
                ends += 1
            }
            if ends * 500 < text.count {
                return true
            }
        }
        if !title.isEmpty, title.count >= 12 {
            let head = String(text.prefix(320))
            if head.components(separatedBy: title)
                .count - 1 >= 2 {
                return true
            }
        }
        return false
    }

    private static func pageTitle(_ html: String)
        -> String? {
        guard let raw = firstCapture(
            "(?is)<title[^>]*>(.*?)</title>", in: html)
        else { return nil }
        let title = clean(decodeEntities(stripTags(raw)))
        return title.isEmpty ? nil
            : String(title.prefix(90))
    }

    private static func extractText(_ html: String)
        -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg",
                    "header", "footer", "nav", "aside",
                    "form", "iframe"] {
            s = regexReplace(
                s, "(?is)<" + tag + "\\b[^>]*>.*?</"
                    + tag + ">", " ")
        }
        s = regexReplace(s, "(?is)<br\\s*/?>", "\n")
        s = regexReplace(
            s, "(?is)</(p|div|li|h1|h2|h3|h4|tr)>", "\n")
        s = decodeEntities(stripTags(s))
        let lines = s.components(separatedBy: "\n")
            .map { clean($0) }
            .filter { $0.count >= 25 }
        return lines.joined(separator: "\n")
    }

    private static func pdfText(_ data: Data) -> String? {
        guard data.count <= 12_000_000,
              let doc = PDFDocument(data: data)
        else { return nil }
        var out = ""
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index),
               let text = page.string {
                out += text + "\n"
            }
            if out.count > 24_000 { break }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: composing the answer

    private static func compose(query: String,
                                scout: Finding?,
                                pages: [Finding],
                                instant: Finding?,
                                wiki: Finding?,
                                walls: Int) -> String {
        let terms = searchTerms(query)
        var blocks: [String] = []
        if let scout = scout {
            blocks.append(block(scout))
        }
        for page in pages.sorted(by: {
            $0.score > $1.score
        }) {
            // A page earns its place on evidence:
            // two distinct terms of the question,
            // or one term carried at least three
            // times — and never on furniture. A
            // lone weak word once seated a
            // listicle's menu at the table on the
            // strength of "today" (2026-10-20).
            let matched = terms.filter {
                score(page.text, terms: [$0]) > 0
            }.count
            if page.score < 3 && matched < 2 {
                continue
            }
            if isChrome(page.text, title: page.source) {
                continue
            }
            if blocks.count >= 3 { break }
            blocks.append(block(page))
        }
        if !blocks.isEmpty {
            var out = blocks.joined(
                separator: "\n\n")
            if out.count > 1800 {
                out = excerpt(out, maxChars: 1800)
            }
            if walls > 0 {
                out += String(format: L("\n\n(%@ behind a wall — walked past.)"), String(describing: walls))
            }
            return out
        }
        // The unescorted findings earn their
        // place the way pages do: a real term of
        // the question, whole-word, in the text.
        // A question about the house once came
        // back as a pop song on the strength of
        // the word "you".
        let instant = instant.flatMap {
            score($0.text, terms: terms) > 0
                ? $0 : nil
        }
        let wiki = wiki.flatMap {
            score($0.text, terms: terms) > 0
                ? $0 : nil
        }
        if let instant = instant {
            var lines = [String(format: L("From the web — %@:"), String(describing: instant.source)),
                         excerpt(instant.text),
                         String(format: L("Source: %@"), String(describing: instant.url))]
            if let wiki = wiki, wiki.url != instant.url {
                lines.append(String(format: L("Also: %@ — %@"), String(describing: wiki.source), String(describing: wiki.url)))
            }
            return lines.joined(separator: "\n")
        }
        if let wiki = wiki {
            return String(format: L("From the web — %@:\n%@\nSource: %@"), String(describing: wiki.source), String(describing: excerpt(wiki.text)), String(describing: wiki.url))
        }
        var failure = String(format: L("Nothing solid came back for '%@'."), String(describing: query))
        if walls > 0 {
            failure += String(format: L(" %@ behind a wall."), String(describing: walls))
        }
        failure += L(" Name it more plainly and I'll go again.")
        return failure
    }

    private static func block(_ finding: Finding)
        -> String {
        // A finding is an excerpt, never the
        // page: the renderer once carried a
        // multi-kilobyte dump into the chat
        // whole (2026-10-18, the atomic-bomb
        // essay). 560 characters of the best
        // sentences is the finding's voice.
        "— " + finding.source + ": "
            + excerpt(finding.text, maxChars: 560)
            + "\nSource: " + finding.url
    }

    // MARK: text work

    private static func searchTerms(_ query: String)
        -> [String] {
        let stop: Set<String> = [
            "what", "is", "the", "a", "an", "of", "for",
            "in", "on", "to", "and", "or", "how", "does",
            "do", "did", "who", "when", "where", "why",
            "can", "could", "should", "would", "tell",
            "me", "about", "search", "web", "online",
            "you", "your", "yours",
            "research", "look", "up", "find", "explain",
        ]
        var seen = Set<String>()
        var out: [String] = []
        for word in query.lowercased().components(
            separatedBy: CharacterSet.alphanumerics
                .inverted) {
            if word.count >= 3, !stop.contains(word),
               !seen.contains(word) {
                seen.insert(word)
                out.append(word)
            }
        }
        return Array(out.prefix(8))
    }

    /// Term scoring on whole words, never
    /// substrings — "hi" inside "HiShelli" is not
    /// a mention, and a junk page that merely
    /// contains the letters earns nothing. Longer
    /// terms also credit their word-stems.
    private static func score(_ text: String,
                              terms: [String]) -> Int {
        let words = text.lowercased()
            .components(separatedBy:
                CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        var total = 0
        for term in terms {
            var hits = 0
            for word in words {
                if word == term
                    || (term.count >= 4
                        && word.hasPrefix(term)) {
                    hits += 1
                }
            }
            total += min(hits, 8)
        }
        return total
    }

    private static func sentences(_ text: String)
        -> [String] {
        clean(text).components(separatedBy: ". ")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    private static func bestExcerpt(_ text: String,
                                    terms: [String],
                                    maxChars: Int = 520)
        -> String {
        let all = sentences(text)
        guard !all.isEmpty else {
            return excerpt(text, maxChars: maxChars)
        }
        var best = 0
        var bestScore = -1
        for (index, sentence) in all.enumerated() {
            let value = score(sentence, terms: terms)
            if value > bestScore {
                bestScore = value
                best = index
            }
        }
        if bestScore <= 0 {
            return excerpt(text, maxChars: maxChars)
        }
        var out = all[best]
        var step = 1
        while out.count < maxChars, step <= all.count {
            if best + step < all.count {
                out += " " + all[best + step]
            }
            if out.count >= maxChars { break }
            if best - step >= 0 {
                out = all[best - step] + " " + out
            }
            step += 1
        }
        return out.count > maxChars + 160
            ? excerpt(out, maxChars: maxChars) : out
    }

    private static func excerpt(_ text: String,
                                maxChars: Int = 720)
        -> String {
        let cleaned = clean(text)
        if cleaned.count <= maxChars { return cleaned }
        var out = ""
        for part in cleaned.components(separatedBy: ". ") {
            let sentence = part.hasSuffix(".")
                ? part : part + "."
            if out.isEmpty {
                if sentence.count > maxChars { break }
                out = sentence
            } else if (out + " " + sentence).count
                        <= maxChars {
                out += " " + sentence
            } else {
                break
            }
            if out.count > maxChars - 120 { break }
        }
        return out.isEmpty
            ? String(cleaned.prefix(maxChars)) + "…"
            : out
    }

    private static func clean(_ text: String) -> String {
        text.components(
            separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func stripTags(_ html: String)
        -> String {
        regexReplace(html, "(?s)<[^>]+>", " ")
    }

    private static func decodeEntities(_ text: String)
        -> String {
        var out = text
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"),
            ("&#39;", "'"), ("&#x27;", "'"),
            ("&nbsp;", " "), ("&#8217;", "’"),
            ("&#8220;", "“"), ("&#8221;", "”"),
            ("&#8211;", "–"), ("&#8212;", "—"),
            ("&#038;", "&"),
            ("&mdash;", "—"), ("&ndash;", "–"),
            ("&hellip;", "…"), ("&lsquo;", "‘"),
            ("&rsquo;", "’"), ("&ldquo;", "“"),
            ("&rdquo;", "”"), ("&middot;", "·"),
            ("&copy;", "©"), ("&reg;", "®"),
            ("&trade;", "™"), ("&deg;", "°"),
            ("&plusmn;", "±"), ("&times;", "×"),
            ("&divide;", "÷"), ("&laquo;", "«"),
            ("&raquo;", "»"), ("&bull;", "•"),
            ("&prime;", "′"), ("&Prime;", "″"),
            ("&asymp;", "≈"), ("&ne;", "≠"),
            ("&le;", "≤"), ("&ge;", "≥"),
            ("&infin;", "∞"), ("&alpha;", "α"),
            ("&beta;", "β"), ("&pi;", "π"),
            ("&micro;", "µ"), ("&eacute;", "é"),
            ("&uuml;", "ü"), ("&ouml;", "ö"),
            ("&auml;", "ä"), ("&ccedil;", "ç"),
            ("&ntilde;", "ñ"),
        ] {
            out = out.replacingOccurrences(
                of: entity, with: replacement)
        }
        return out
    }

    private static func regexReplace(_ s: String,
                                     _ pattern: String,
                                     _ template: String)
        -> String {
        s.replacingOccurrences(of: pattern, with: template,
                               options: .regularExpression)
    }

    private static func regexMatches(_ pattern: String,
                                     in s: String)
        -> [[String]] {
        guard let re = try? NSRegularExpression(
            pattern: pattern) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, range: range).map {
            match in
            (0..<match.numberOfRanges).map { index in
                guard let r = Range(
                    match.range(at: index), in: s)
                else { return "" }
                return String(s[r])
            }
        }
    }

    private static func firstCapture(_ pattern: String,
                                     in s: String)
        -> String? {
        regexMatches(pattern, in: s)
            .first.flatMap {
                $0.count > 1 && !$0[1].isEmpty
                    ? $0[1] : nil
            }
    }
}

final class SkelliWebRenderer: NSObject,
                               WKNavigationDelegate {
    static let shared = SkelliWebRenderer()

    private weak var webView: WKWebView?
    private var completion: ((String?) -> Void)?
    private var timeout: DispatchWorkItem?

    func attach(_ view: WKWebView) {
        webView = view
        view.navigationDelegate = self
    }

    func render(url: URL,
                completion: @escaping (String?) -> Void) {
        guard let view = webView, self.completion == nil
        else {
            completion(nil)
            return
        }
        self.completion = completion
        view.stopLoading()
        view.load(URLRequest(url: url,
                             timeoutInterval: 15))
        let work = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 18, execute: work)
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            "document.body ? document.body.innerText : ''"
        ) { [weak self] result, _ in
            self?.finish(result as? String)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation
                     navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    private func finish(_ text: String?) {
        timeout?.cancel()
        timeout = nil
        let done = completion
        completion = nil
        webView?.stopLoading()
        done?(text)
    }
}

#if os(iOS)
struct SkelliWebHost: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences
            .allowsContentJavaScript = true
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            configuration: config)
        view.alpha = 0.02
        view.isUserInteractionEnabled = false
        SkelliWebRenderer.shared.attach(view)
        return view
    }

    func updateUIView(_ uiView: WKWebView,
                      context: Context) { }
}
#endif

#if os(macOS)
struct SkelliWebHost: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences
            .allowsContentJavaScript = true
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            configuration: config)
        view.alphaValue = 0.02
        SkelliWebRenderer.shared.attach(view)
        return view
    }

    func updateNSView(_ view: WKWebView,
                      context: Context) { }
}
#endif

// MARK: - Her small favors

/// Skelli's plain-order layer lives here, beside the
/// other shared machinery, because Skelli.swift sits
/// hard against the connector's size ceiling.
extension SkelliCenter {
    /// Plain orders, plainly done: say it back, dress
    /// it, count it, reckon it, tell the time. Caught
    /// early so a small ask never earns a large answer.
    func smallFavor(_ q: String, raw: String)
        -> Bool {
        // The clock is a fact, not a
        // composition: asked the time, she
        // reads the phone's own wall time and
        // says it, shaded by the daypart she
        // keeps. Before this, the question fell
        // to a bench — and a mind without a
        // clock invents one.
        if ["what time is it", "what time is it now",
            "what's the time", "what is the time",
            "tell me the time", "the time",
            "current time", "what time"]
            .contains(q) {
            say(SkelliHeart.clockFact() + ".")
            return true
        }
        if let spoken = remainder(q, raw: raw, stems: [
            "repeat after me", "respond with",
            "answer with", "repeat", "echo", "print",
            "say", "type"]) {
            say(spoken.isEmpty
                ? L("Say what? Give me the words.")
                : stripQuotes(spoken))
            return true
        }
        if let text = remainder(q, raw: raw,
                                stems: ["uppercase", "shout"]) {
            say(text.uppercased())
            return true
        }
        if let text = remainder(q, raw: raw,
                                stems: ["lowercase", "whisper"]) {
            say(text.lowercased())
            return true
        }
        if let text = remainder(q, raw: raw,
                                stems: ["reverse"]) {
            say(String(text.reversed()))
            return true
        }
        if let text = remainder(q, raw: raw,
                                stems: ["spell"]) {
            let word = text.split(separator: " ")
                .first.map(String.init) ?? text
            say(word.map(String.init)
                .joined(separator: "-"))
            return true
        }
        if let text = remainder(q, raw: raw,
                                stems: ["capitalize"]) {
            say(text.prefix(1).uppercased()
                + String(text.dropFirst()))
            return true
        }
        if q.contains("how many letters")
            || q.contains("how many characters") {
            guard let subject = afterIn(q, raw: raw)
            else { return false }
            let count = subject.filter { $0.isLetter }
                .count
            say(count == 1
                ? String(format: L("%@ letter."), String(describing: count))
                : String(format: L("%@ letters."), String(describing: count)))
            return true
        }
        if q.contains("how many words") {
            guard let subject = afterIn(q, raw: raw)
            else { return false }
            let count = subject.split(whereSeparator: {
                $0 == " " || $0 == "\n" }).count
            say(count == 1
                ? String(format: L("%@ word."), String(describing: count))
                : String(format: L("%@ words."), String(describing: count)))
            return true
        }
        if q.contains("what time")
            || q.contains("current time") {
            say(String(format: L("It's %@."), String(describing: Date().formatted(
                date: .omitted, time: .shortened))))
            return true
        }
        if q.contains("what day")
            || q.contains("what date")
            || q.contains("what's today") {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy"
            say(formatter.string(from: Date()) + ".")
            return true
        }
        let clean = q.trimmingCharacters(
            in: CharacterSet(charactersIn: " !?."))
        // Social speech, matched by shape rather
        // than by exact string: a greeting head
        // with at most a small social tail, doubled
        // letters ("hiii") squeezed flat first.
        let tokens = clean.split(separator: " ")
            .map(String.init)
        func squeezed(_ token: String) -> String {
            var out = ""
            var previous: Character? = nil
            for character in token {
                if character != previous {
                    out.append(character)
                }
                previous = character
            }
            return out
        }
        if let head = tokens.first,
           ["hi", "hello", "hey", "hiya", "yo",
            "heya", "greetings"]
               .contains(squeezed(head)),
           tokens.dropFirst().allSatisfy({
               ["there", "friend", "all", "everyone",
                "guys", "again"].contains($0)
           }) {
            say(vary(["Hello.",
                      L("Hello. The house is listening."),
                      L("Well met."),
                      L("Hello — mind the wires."),
                      L("Hey. In you come."),
                      L("Hello. State of the house: attentive.")]))
            return true
        }
        if ["what's up", "whats up", "what is up",
            "sup", "how's it going", "hows it going",
            "how are things", "how is it going",
            "how goes it"].contains(clean) {
            let wire = NeighborhoodStore.shared
                .neighbors.count
            say(String(format: L("All quiet — %@ on the wire, web %@."), String(describing: wire), String(describing: webResearchEnabled ? L("on") : L("off"))))
            return true
        }
        if clean.hasPrefix("good morning") {
            say(vary([L("Morning."),
                      L("Morning. The wire's up too."),
                      L("First watch, morning side.")]))
            return true
        }
        if clean.hasPrefix("good afternoon") {
            say(vary(["Afternoon.",
                      L("Afternoon. The light's leaning."),
                      L("Mid-watch. Afternoon.")]))
            return true
        }
        if clean.hasPrefix("good evening") {
            say(vary(["Evening.",
                      L("Evening. Lamps on."),
                      L("Evening. The house exhales.")]))
            return true
        }
        if ["bye", "goodbye", "good night",
            "goodnight", "see you", "see ya", "cya",
            "later", "gn"].contains(clean) {
            say(clean.contains("night")
                ? vary(["Night.",
                        L("Night. The watch is mine."),
                        L("Rest well.")])
                : vary(["Later.",
                        L("Later. The wire keeps."),
                        L("Go on, then.")]))
            return true
        }
        if ["ok", "okay", "k", "got it", "cool",
            "nice", "great", "perfect", "awesome",
            "sweet", "understood", "roger",
            "copy that", "sounds good", "good",
            "right", "indeed", "exactly", "yes",
            "yeah", "yep"].contains(clean) {
            say(vary([L("Noted."), "Logged.", L("Filed."),
                      L("So recorded."), L("In the ledger."),
                      L("Mm. Kept."), L("Understood and kept.")]))
            return true
        }
        if clean == "sorry" || clean == "my bad"
            || clean == "apologies"
            || clean.hasPrefix("sorry ") {
            say(vary([L("Nothing to forgive."),
                      L("No debt on the books."),
                      L("Forgiven before you finished."),
                      L("The slate was never marked."),
                      L("All clear between us.")]))
            return true
        }
        if ["lol", "haha", "lmao", "heh"]
            .contains(squeezed(clean)) {
            say(vary(["Heh.", L("Heh. Filed."),
                      L("A laugh, duly noted."),
                      L("Mm. Amusement logged."),
                      L("The house chuckles, quietly.")]))
            return true
        }
        if q.contains("thank") {
            say(vary([L("Any time."), "Always.",
                      L("The house provides."),
                      L("Mm. That's the job."),
                      L("Whenever. I'm here."),
                      L("Kept with pleasure.")]))
            return true
        }
        if q.contains("how are you") {
            say(vary([L("Running clean. You?"),
                      L("All systems, all senses. You?"),
                      L("Kept, listening, unbothered. You?"),
                      L("The house purrs. And you?")]))
            return true
        }
        if let value = mathAnswer(q) {
            say(value)
            return true
        }
        return false
    }

    /// A small order's payload: politeness and
    /// 'can you' stripped, the stem matched at the
    /// head, the rest taken from the operator's own
    /// words — their case intact.
    private func remainder(_ q: String, raw: String,
                           stems: [String]) -> String? {
        var offset = 0
        var rest = q
        if rest.hasPrefix("please ") {
            offset += 7
            rest = String(rest.dropFirst(7))
        }
        if rest.hasPrefix("can you ") {
            offset += 8
            rest = String(rest.dropFirst(8))
        } else if rest.hasPrefix("could you ") {
            offset += 10
            rest = String(rest.dropFirst(10))
        }
        for stem in stems {
            if rest == stem { return "" }
            if rest.hasPrefix(stem + " ")
                || rest.hasPrefix(stem + ":") {
                let start = offset + stem.count
                let payload = raw
                    .dropFirst(min(start, raw.count))
                    .drop(while: { $0 == " " || $0 == ":" })
                return String(payload)
            }
        }
        return nil
    }

    private func stripQuotes(_ text: String) -> String {
        var out = text.trimmingCharacters(
            in: .whitespaces)
        for (open, close) in [("\"", "\""), ("“", "”"),
                              ("'", "'"), ("‘", "’")] {
            if out.hasPrefix(open), out.hasSuffix(close),
               out.count > 1 {
                out = String(out.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return out
    }

    /// The subject of a counting question — what
    /// follows the last ' in ', minus its articles.
    private func afterIn(_ q: String, raw: String)
        -> String? {
        guard let range = q.range(of: " in ",
                                   options: .backwards)
        else { return nil }
        let distance = q.distance(from: q.startIndex,
                                  to: range.upperBound)
        guard raw.count > distance else { return nil }
        var subject = stripQuotes(
            String(raw.dropFirst(distance)))
        for prefix in ["the word ", "the phrase ",
                       "the "] {
            if subject.lowercased().hasPrefix(prefix) {
                subject = String(
                    subject.dropFirst(prefix.count))
                break
            }
        }
        return subject
    }

    /// Small arithmetic, honestly reckoned: + − × ÷
    /// and parentheses, nothing else admitted.
    private func mathAnswer(_ q: String) -> String? {
        var expr = q
        var explicit = false
        for prefix in ["what is ", "what's ",
                       "calculate ", "compute ",
                       "solve ", "how much is "] {
            if expr.hasPrefix(prefix) {
                expr = String(expr.dropFirst(prefix.count))
                explicit = true
                break
            }
        }
        expr = expr.trimmingCharacters(
            in: CharacterSet(charactersIn: " ?"))
        let allowed = CharacterSet(
            charactersIn: "0123456789.+-*/x×÷() ")
        guard !expr.isEmpty,
              expr.unicodeScalars.allSatisfy({
                  allowed.contains($0) }),
              expr.contains(where: { $0.isNumber }),
              explicit
                || expr.contains(where: {
                    "+*/×÷".contains($0) })
                || expr.contains(" x ")
        else { return nil }
        var parser = ExprParser(expr
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "x", with: "*"))
        guard let value = parser.run()
        else { return nil }
        if value == value.rounded(),
           abs(value) < 1e15 {
            return String(Int(value)) + "."
        }
        return String(format: "%g", value) + "."
    }

    private struct ExprParser {
        var c: [Character]
        var i = 0
        var depth = 0

        init(_ text: String) { c = Array(text) }

        mutating func run() -> Double? {
            let value = expr()
            ws()
            return value != nil && i == c.count
                ? value : nil
        }

        mutating func ws() {
            while i < c.count, c[i] == " " { i += 1 }
        }

        mutating func expr() -> Double? {
            guard var v = term() else { return nil }
            while true {
                ws()
                guard i < c.count,
                      c[i] == "+" || c[i] == "-"
                else { return v }
                let op = c[i]
                i += 1
                guard let n = term() else { return nil }
                v = op == "+" ? v + n : v - n
            }
        }

        mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while true {
                ws()
                guard i < c.count,
                      c[i] == "*" || c[i] == "/"
                else { return v }
                let op = c[i]
                i += 1
                guard let n = factor()
                else { return nil }
                if op == "/", n == 0 { return nil }
                v = op == "*" ? v * n : v / n
            }
        }

        mutating func factor() -> Double? {
            // Every recursion path passes through
            // here; the counter keeps a wall of
            // brackets or minus signs from taking
            // the stack with it.
            depth += 1
            defer { depth -= 1 }
            guard depth <= 64 else { return nil }
            ws()
            guard i < c.count else { return nil }
            if c[i] == "-" {
                i += 1
                return factor().map { -$0 }
            }
            if c[i] == "(" {
                i += 1
                guard let v = expr() else { return nil }
                ws()
                guard i < c.count, c[i] == ")"
                else { return nil }
                i += 1
                return v
            }
            var t = ""
            while i < c.count,
                  c[i].isNumber || c[i] == "." {
                t.append(c[i])
                i += 1
            }
            return Double(t)
        }
    }
}

// MARK: - Her weights, managed in the app

/// A weights model her bench can run: an MLX build
/// on the Hugging Face hub, sized for a phone.
struct WeightsOption: Identifiable {
    var id: String
    var name: String
    var sizeGB: Double
    var note: String
}

/// Her bench's keeper: the catalog she supports,
/// the recommendation for this phone, and the
/// downloads themselves — picked, fetched, and
/// run without ever leaving the app. Downloads
/// come from the Hugging Face hub into the app's
/// own cache; afterwards the model is entirely
/// on the phone, and nothing is sent back.
final class WeightsCenter: ObservableObject {
    static let shared = WeightsCenter()

    static let catalog: [WeightsOption] = [
        WeightsOption(
            id: "mlx-community/Qwen3-4B-4bit",
            name: "Qwen3 4B", sizeGB: 2.5,
            note: "The deep bench — sharp and "
                + "unhurried."),
        WeightsOption(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            name: "Llama 3.2 3B", sizeGB: 1.9,
            note: "Meta's small talker — quick and "
                + "plainspoken."),
        WeightsOption(
            id: "mlx-community/Qwen3-1.7B-4bit",
            name: "Qwen3 1.7B", sizeGB: 1.1,
            note: "The middle weight — fast and "
                + "capable."),
        WeightsOption(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen2.5 7B", sizeGB: 4.3,
            note: "The heavyweight — the most she "
                + "can carry."),
        WeightsOption(
            id: "mlx-community/Qwen3-0.6B-4bit",
            name: "Qwen3 0.6B", sizeGB: 0.5,
            note: "The featherweight — nearly "
                + "instant, and modest."),
    ]

    @Published var selectedID: String? {
        didSet {
            UserDefaults.standard.set(
                selectedID, forKey: "skelli.weightsModel")
        }
    }
    @Published var downloaded: Set<String> {
        didSet {
            UserDefaults.standard.set(
                Array(downloaded),
                forKey: "skelli.weightsDownloaded")
        }
    }
    @Published var progress: [String: Double] = [:]
    @Published var states: [String: String] = [:]

    /// Downloads happen one at a time, in the order
    /// they were asked for. The old road ran them
    /// all at once — and worse, "downloading" went
    /// through the model *loader*, so every finished
    /// download heaved its whole model into memory
    /// while the others were still arriving. Stack a
    /// 7B on top of that and iOS reclaimed the app —
    /// and because "downloaded" was only written at
    /// the very end, the kill took finished and
    /// half-finished downloads alike off the books.
    /// Now: fetching is fetching (files only), the
    /// line is a line, and the disk is the truth.
    private var queue: [WeightsOption] = []
    private var draining = false

    init() {
        selectedID = UserDefaults.standard.string(
            forKey: "skelli.weightsModel")
        downloaded = Set(UserDefaults.standard
            .stringArray(
                forKey: "skelli.weightsDownloaded")
            ?? [])
        reconcileWithDisk()
    }

    // MARK: - The disk is the truth

    /// Where the hub cache lives in this app's
    /// sandbox — the same ground the downloader
    /// itself uses (Library/Caches/huggingface/hub).
    static var hubCacheRoot: URL {
        let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent(
            "huggingface/hub")
    }

    static func repoDirectory(id: String) -> URL {
        hubCacheRoot.appendingPathComponent(
            "models--" + id.replacingOccurrences(
                of: "/", with: "--"))
    }

    /// A model counts as carried when its snapshot
    /// is whole: the main ref resolves, the snapshot
    /// holds a config and at least one weights file,
    /// and no blob still wears its .incomplete name.
    static func isCompleteOnDisk(id: String) -> Bool {
        let fm = FileManager.default
        let repo = repoDirectory(id: id)
        guard let commit = try? String(
            contentsOf: repo.appendingPathComponent(
                "refs/main"), encoding: .utf8)
        else { return false }
        let hash = commit.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return false }
        let snapshot = repo.appendingPathComponent(
            "snapshots/\(hash)")
        guard fm.fileExists(atPath: snapshot
            .appendingPathComponent("config.json").path)
        else { return false }
        let files = (try? fm.contentsOfDirectory(
            atPath: snapshot.path)) ?? []
        guard files.contains(where: {
            $0.hasSuffix(".safetensors") })
        else { return false }
        let blobs = (try? fm.contentsOfDirectory(
            atPath: repo.appendingPathComponent(
                "blobs").path)) ?? []
        return !blobs.contains(where: {
            $0.hasSuffix(".incomplete") })
    }

    /// Rebuild the carried list from the cache
    /// itself. Every complete snapshot counts —
    /// including one whose download finished in a
    /// session that died before it could write the
    /// list down — and anything partial or purged
    /// stops claiming to be here.
    private func reconcileWithDisk() {
        var found = Set<String>()
        let fm = FileManager.default
        if let dirs = try? fm.contentsOfDirectory(
            atPath: Self.hubCacheRoot.path) {
            for dir in dirs
            where dir.hasPrefix("models--") {
                let id = String(dir.dropFirst(
                    "models--".count))
                    .replacingOccurrences(
                        of: "--", with: "/")
                if Self.isCompleteOnDisk(id: id) {
                    found.insert(id)
                }
            }
        }
        for id in downloaded
        where Self.isCompleteOnDisk(id: id) {
            found.insert(id)
        }
        if found != downloaded {
            downloaded = found
        }
        if let sel = selectedID, !found.contains(sel) {
            selectedID = nil
        }
    }

    /// Any MLX model on the hub, named by hand,
    /// can join her bench — the catalog is a
    /// starting shelf, not a fence.
    static func customOption(id: String)
        -> WeightsOption {
        WeightsOption(
            id: id,
            name: id.components(
                separatedBy: "/").last ?? id,
            sizeGB: 0,
            note: "Brought by hand.")
    }

    /// The weights on this phone that the
    /// catalog didn't name.
    var customDownloaded: [WeightsOption] {
        let known = Set(Self.catalog.map { $0.id })
        return downloaded
            .filter { !known.contains($0) }
            .sorted()
            .map { Self.customOption(id: $0) }
    }

    /// The bench this phone should carry, judged
    /// by the memory it has to carry it in.
    var recommended: WeightsOption {
        let gb = Double(ProcessInfo.processInfo
            .physicalMemory) / 1_073_741_824
        // Judged by the jetsam line, not
        // the spec sheet (fix152): on a
        // 12 GB phone the kernel leaves
        // this app about 3.3 GB of
        // headroom, and the 4B needs
        // 3.45 GB with its safety
        // margin — a recommendation
        // the load gate must refuse
        // is no recommendation. The
        // 1.7B clears the same gate
        // with room to spare; the 4B
        // stays on the shelf for the
        // day an entitlement widens
        // the room.
        if gb >= 5 { return Self.catalog[2] }
        return Self.catalog[4]
    }

    var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory)
            / 1_073_741_824
    }

    // MARK: - The line

    func download(_ option: WeightsOption) {
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *) {
            guard progress[option.id] == nil,
                  !queue.contains(where: {
                      $0.id == option.id })
            else { return }
            queue.append(option)
            progress[option.id] = 0
            states[option.id] =
                Self.isCompleteOnDisk(id: option.id)
                ? "Already on the phone."
                : (draining || queue.count > 1
                    ? "In line…"
                    : "Downloading…")
            drainQueue()
        } else {
            states[option.id] = "The bench needs "
                + "iOS 17 or later."
        }
        #else
        states[option.id] = "The bench isn't in "
            + "this build."
        #endif
    }

    private func drainQueue() {
        guard !draining else { return }
        draining = true
        // The line is main-actor property: download(_:)
        // appends to it from the main thread, so the
        // drain works there too — an unstructured task
        // on the global executor raced those appends.
        Task { @MainActor in
            while !queue.isEmpty {
                let next = queue.removeFirst()
                await fetch(next)
            }
            draining = false
        }
    }

    private func fetch(_ option: WeightsOption) async {
        if Self.isCompleteOnDisk(id: option.id) {
            await MainActor.run {
                progress[option.id] = nil
                downloaded.insert(option.id)
                if selectedID == nil {
                    selectedID = option.id
                }
                states[option.id] = "Ready."
            }
            return
        }
        await MainActor.run {
            states[option.id] = "Downloading…"
            progress[option.id] = 0
        }
        do {
            try await Self.pull(option.id) { fraction in
                DispatchQueue.main.async {
                    self.progress[option.id] = fraction
                }
            }
            await MainActor.run {
                progress[option.id] = nil
                downloaded.insert(option.id)
                if selectedID == nil {
                    selectedID = option.id
                }
                states[option.id] = "Ready."
            }
        } catch {
            await MainActor.run {
                progress[option.id] = nil
                states[option.id] =
                    "Failed — check the "
                    + "connection and try again."
            }
        }
    }

    /// Fetch the files, and only the files: nothing
    /// is loaded into memory here. (Loading is the
    /// minds' business, one model at a time, when a
    /// conversation actually calls for it.)
    private static func pull(
        _ id: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        #if canImport(HuggingFace)
        guard let repo = Repo.ID(rawValue: id) else {
            throw NSError(
                domain: "WeightsCenter", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    String(format: L("Not a hub address: %@"), String(describing: id))])
        }
        _ = try await HubClient.default.downloadSnapshot(
            of: repo, kind: .model, revision: "main",
            maxConcurrentDownloads: 4
        ) { p in
            progress(p.fractionCompleted)
        }
        #else
        let config = ModelConfiguration(id: id)
        _ = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: config) { p in
            progress(p.fractionCompleted)
        }
        #endif
    }

    func select(_ option: WeightsOption) {
        selectedID = option.id
    }

    func remove(_ option: WeightsOption) {
        downloaded.remove(option.id)
        if selectedID == option.id {
            selectedID = nil
        }
        states[option.id] = nil
        progress[option.id] = nil
        queue.removeAll { $0.id == option.id }
        try? FileManager.default.removeItem(
            at: Self.repoDirectory(id: option.id))
        // Sweep the grounds older builds may have
        // used, so a removal is a removal.
        let folder = "models--" + option.id
            .replacingOccurrences(of: "/", with: "--")
        var bases: [URL] = []
        if let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask).first {
            bases.append(caches)
        }
        if let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask).first {
            bases.append(docs)
        }
        for base in bases {
            for sub in ["huggingface/hub/", "hub/", ""] {
                try? FileManager.default.removeItem(
                    at: base.appendingPathComponent(
                        sub + folder))
            }
        }
    }
}

/// The Weights sheet: her bench, on one screen —
/// what this phone should carry, what it does
/// carry, and the buttons to change it.
struct WeightsView: View {
    @StateObject private var center = WeightsCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var customID = ""

    var body: some View {
        NavigationStack {
            List {
                if !SkelliMind.benchBuiltIn {
                    Section {
                        Text("The weights bench isn't in this build — the MLX package (mlx-swift-lm) isn't linked into the target yet. Once it is, her models live here: picked, downloaded, and run without ever leaving the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(String(format: L("This phone carries %@ GB — her bench should be the %@."),
                                    String(format: "%.0f",
                                           center.memoryGB),
                                    center.recommended.name))
                            .font(.callout)
                        if !center.downloaded.contains(
                            center.recommended.id) {
                            Button(String(format: L("Download the %@"),
                                          center.recommended.name)) {
                                center.download(
                                    center.recommended)
                            }
                        }
                    }
                    Section("The bench") {
                        ForEach(WeightsCenter.catalog) {
                            option in
                            row(option)
                        }
                    }
                    if !center.customDownloaded
                        .isEmpty {
                        Section("Brought by hand") {
                            ForEach(
                                center.customDownloaded
                            ) { option in
                                row(option)
                            }
                        }
                    }
                    Section("Any weights on the hub") {
                        TextField(
                            "mlx-community/…",
                            text: $customID)
                            .font(.callout)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(
                                .never)
                        Button("Download it") {
                            let id = customID
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines)
                            if id.contains("/") {
                                center.download(
                                    WeightsCenter
                                        .customOption(
                                            id: id))
                                customID = ""
                            }
                        }
                        Text("Any MLX-format model on the Hugging Face hub — hers to run the moment it lands.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Text("Downloads come from the Hugging Face hub and live in the app's own cache. After that the model never leaves the phone, and nothing is sent back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .skelliSheetList()
            .navigationTitle("Weights")
            .toolbar {
                ToolbarItem(
                    placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ option: WeightsOption)
        -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(option.name)
                    .font(.headline)
                if option.id == center.recommended.id {
                    Text("recommended")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                controls(option)
            }
            Text(L(option.note))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: L("%.1f GB · "),
                        option.sizeGB) + option.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value = center.progress[option.id] {
                ProgressView(value: value)
            } else if let state = center
                .states[option.id] {
                Text(L(state))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func controls(_ option: WeightsOption)
        -> some View {
        if center.progress[option.id] != nil {
            Text("…")
                .foregroundStyle(.secondary)
        } else if center.downloaded
            .contains(option.id) {
            HStack(spacing: 12) {
                if center.selectedID == option.id {
                    Label("In use",
                          systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                } else {
                    Button("Use") {
                        center.select(option)
                    }
                    .font(.caption.weight(.semibold))
                }
                Button(role: .destructive) {
                    center.remove(option)
                } label: {
                    Image(systemName: "trash")
                }
            }
        } else {
            Button("Download") {
                center.download(option)
            }
            .font(.caption.weight(.semibold))
        }
    }
}

// MARK: - Her council chamber

/// The minds in unison live here so Skelli.swift
/// stays shippable: the council (one bench
/// drafts, the other refines), the raw bench
/// answer her Forge borrows, and the echo
/// cleaner every reply passes through.
extension SkelliMind {

    #if canImport(FoundationModels)
    /// The benches in unison: one drafts, the
    /// other verifies it against the grounding
    /// and speaks the final word. A draft that
    /// asks for research is escalated untouched —
    /// a referee doesn't answer for it.
    @available(iOS 26.0, macOS 26.0, *)
    static func council(
        prompt: String, grounding: String,
        finish: @escaping (Verdict) -> Void) async {
        let grounding = grounding
            + Self.capabilityBrief
        var draft: String?
        var draftedByWeights = false
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *),
           SkelliWeights.canSpeak {
            draft = await SkelliWeights.ask(
                instructions: grounding,
                prompt: prompt)
            draftedByWeights = draft != nil
        }
        #endif
        if draft == nil {
            draft = await SkelliModelBox.run(
                instructions: grounding,
                prompt: prompt)
        }
        guard let draftText = draft,
              let draftVerdict = interpret(draftText)
        else {
            finish(.research)
            return
        }
        if case .research = draftVerdict {
            finish(.research)
            return
        }
        let refineInstructions = grounding
            + " A colleague drafted the reply "
            + "below. Verify it against the facts; "
            + "correct it if it is wrong; keep it "
            + "terse, and keep her wit in it — "
            + "never sand a live line down "
            + "into corporate mush. Return "
            + "only the final reply."
        let refinePrompt = "The operator asked: "
            + prompt + "\nDraft reply: " + draftText
        var refined: String?
        if draftedByWeights {
            refined = await SkelliModelBox.run(
                instructions: refineInstructions,
                prompt: refinePrompt)
        }
        #if canImport(MLXLLM)
        if refined == nil, !draftedByWeights,
           #available(iOS 17.0, *),
           SkelliWeights.canSpeak {
            refined = await SkelliWeights.ask(
                instructions: refineInstructions,
                prompt: refinePrompt)
        }
        #endif
        if let refined = refined,
           let verdict = interpret(refined) {
            finish(verdict)
        } else {
            finish(draftVerdict)
        }
    }
    #endif

    /// A raw answer for her workbench — no
    /// verdict, no research: the best bench's
    /// words, cleaned. The weights draft first
    /// (the forge wants the local mind), Apple's
    /// bench behind them.
    static func rawAnswer(instructions: String,
                          prompt: String)
        async -> String? {
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *),
           SkelliWeights.canSpeak,
           let text = await SkelliWeights.ask(
               instructions: instructions,
               prompt: prompt) {
            let cleaned = decontaminate(text)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *),
           SkelliModelBox.available,
           let text = await SkelliModelBox.run(
               instructions: instructions,
               prompt: prompt) {
            let cleaned = decontaminate(text)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        #endif
        return nil
    }

    /// What she can do, in the words intents
    /// arrive in — appended to the council's
    /// grounding, so her conversation knows her
    /// own hands: these are real abilities, and
    /// naming the ask that triggers one is
    /// grounded advice, not invention.
    static let capabilityBrief =
        "\nHer hands — the operator triggers each"
        + " by asking in his own words, and a"
        + " message that plainly asks for one is"
        + " acted on before it ever reaches you,"
        + " so if you are answering, either he"
        + " didn't ask, or he is asking ABOUT one:"
        + " sweep the local network for devices;"
        + " check his own exposure; run the audit;"
        + " run a drill; go dark (EMCON) or stand"
        + " down; start or stop listening (the BLE"
        + " ear); raise or stop Serve; stealth on"
        + " or off; arm or drop the tripwire;"
        + " report who is on the wire, what"
        + " happened overnight, the exposure"
        + " posture, the facts she has learned,"
        + " and the Subconscious brief; write code;"
        + " forge payloads; fetch or select an"
        + " open-weights model on her bench;"
        + " strike what she built (a forged or"
        + " custom payload, a taught pattern);"
        + " recolour the house by"
        + " theme name; research the living web."
        + " If he seems to want one done and it"
        + " hasn't happened, tell him plainly he"
        + " can just say so — no mode, no menu."

    /// The second reading: a message no pattern
    /// caught is read once, semantically, against
    /// the menu of her capabilities — and comes
    /// back as the canonical phrase her own
    /// reflexes already obey, a THEME: or CODE
    /// token, or nothing (plain conversation,
    /// honestly come by). The quick bench reads
    /// first; meaning, not keywords, decides.
    static func intentPhrase(for text: String,
                             recent: String)
        async -> String? {
        let prompt = recent.isEmpty
            ? text
            : recent + "\nOperator: " + text
        let charter =
            "You read intent for Skelli, the"
            + " specialist inside nightjar."
            + " The operator's message matched none"
            + " of her command patterns. Judge by"
            + " MEANING alone: if he plainly wants"
            + " one of these DONE, answer with its"
            + " token and nothing else — SWEEP"
            + " (scan the local network), SELFSCAN"
            + " (check his own exposure), AUDIT,"
            + " DRILL, DARK (EMCON on), STANDDOWN,"
            + " LISTEN, STOPLISTEN, SERVE,"
            + " STOPSERVE, STEALTH_ON, STEALTH_OFF,"
            + " TRIPWIRE_ON, TRIPWIRE_OFF, WIRE"
            + " (who is on his network), NIGHT"
            + " (what happened overnight),"
            + " POSTURE (the house's exposure),"
            + " FACTS (what she has learned),"
            + " BRIEF (her Subconscious brief),"
            + " CODE (write code or a script for"
            + " him), FORGE (build or forge a"
            + " packet or payload for him),"
            + " DELETE (he wants something she"
            + " built or keeps — a payload or a"
            + " pattern — removed),"
            + " REMEMBER:<the fact, briefly, in"
            + " his own words> (he wants something"
            + " kept in her memory), THEME:<a colour"
            + " theme's name> (recolour the app)."
            + " If he is"
            + " chatting, asking a question, or"
            + " wants information rather than an"
            + " action, answer NONE. One token,"
            + " one line, no explanation."
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *),
           SkelliModelBox.available,
           let raw = await SkelliModelBox.run(
               instructions: charter,
               prompt: prompt) {
            return parseIntent(raw)
        }
        #endif
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *),
           SkelliWeights.canSpeak,
           let raw = await SkelliWeights.ask(
               instructions: charter,
               prompt: prompt) {
            return parseIntent(raw)
        }
        #endif
        return nil
    }

    /// Tokens the reader may answer with, and
    /// the phrases — already fluent in her
    /// reflexes — that they stand for.
    static func parseIntent(_ raw: String?)
        -> String? {
        guard let raw else { return nil }
        let line = decontaminate(raw)
            .components(separatedBy: "\n")
            .first ?? ""
        let t = line.trimmingCharacters(
                in: .whitespacesAndNewlines)
            .uppercased()
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: ".!:*"))
        if t.hasPrefix("THEME:") {
            let name = String(t.dropFirst(6))
                .trimmingCharacters(
                    in: .whitespaces)
            return name.isEmpty
                ? nil : "THEME:" + name
        }
        let spokenLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if spokenLine.lowercased().hasPrefix("remember:") {
            let fact = String(spokenLine.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            return fact.isEmpty ? nil : "REMEMBER:" + fact
        }
        let map: [(String, String)] = [
            ("SELFSCAN", "how exposed"),
            ("STOPSERVE", "stop serving"),
            ("STOPLISTEN", "stop listening"),
            ("TRIPWIRE_ON", "tripwire on"),
            ("TRIPWIRE_OFF", "tripwire off"),
            ("STEALTH_ON", "stealth on"),
            ("STEALTH_OFF", "stealth off"),
            ("STANDDOWN", "stand down"),
            ("SERVE", "start serving"),
            ("LISTEN", "start listening"),
            ("DARK", "go dark"),
            ("SWEEP", "sweep"),
            ("AUDIT", "audit"),
            ("DRILL", "drill"),
            ("WIRE", "who's here"),
            ("NIGHT", "what happened"),
            ("POSTURE", "posture"),
            ("FACTS", "facts"),
            ("BRIEF", "brief"),
            ("CODE", "CODE"),
            ("FORGE", "FORGE"),
            ("DELETE", "DELETE"),
        ]
        for (token, phrase) in map where t == token {
            return phrase
        }
        if t.contains("NONE") { return nil }
        for (token, phrase) in map
        where t.contains(token) {
            return phrase
        }
        return nil
    }

    /// The reading, on a leash: a bench that
    /// hasn't answered within the limit hasn't
    /// answered — conversation proceeds without
    /// it rather than after it.
    static func intentWithTimeout(
        for text: String, recent: String,
        seconds: Double) async -> String? {
        await withTaskGroup(
            of: String?.self) { group in
            group.addTask {
                await intentPhrase(
                    for: text, recent: recent)
            }
            group.addTask {
                try? await Task.sleep(
                    for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Small models love to continue the script
    /// they were shown — echoing the transcript
    /// back before answering. Cut any echo: what
    /// she says is what follows the last script
    /// marker, marker lines removed.
    static func decontaminate(
        _ text: String) -> String {
        guard text.contains("Operator:") else {
            return text
        }
        var lines = text.components(
            separatedBy: "\n")
        if let last = lines.lastIndex(where: {
            $0.hasPrefix("Skelli:")
        }) {
            lines = Array(lines[last...])
        }
        let kept = lines.filter {
            !$0.hasPrefix("Operator:")
        }.map { line -> String in
            line.hasPrefix("Skelli:")
                ? String(line.dropFirst(7))
                    .trimmingCharacters(
                        in: .whitespaces)
                : line
        }
        let cleaned = kept.joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? text : cleaned
    }
}

// MARK: - The second reading

/// Patterns are reflexes; this is understanding.
/// A message that ran the whole gauntlet of her
/// patterns uncaught is read once by a bench —
/// against everything she can do — before it is
/// allowed to be mere conversation. A plain
/// intent comes back as the canonical phrase her
/// reflexes already obey, so nothing here learns
/// a second way to act: she just hears better.
/// No bench, no reading — conversation proceeds
/// exactly as it always has.
extension SkelliCenter {

    /// The grounding floor under a second
    /// reading. The bench may reinterpret the
    /// operator's words; it may not invent an
    /// order out of none of them. A hit acts
    /// only when the ask itself carries at
    /// least one word from the capability's own
    /// country — the words a person
    /// paraphrasing that wish would actually
    /// use. A reading with no word in common
    /// with the order it claims to have heard
    /// is not a reading but a hallucination,
    /// and it falls through to conversation
    /// like any other chat. (It once heard
    /// "tell me more about him" — a question
    /// about her maker — as SWEEP, and swept
    /// the wire unasked.)
    private func secondReadingGrounded(
        _ hit: String, in q: String) -> Bool {
        func carries(_ words: [String]) -> Bool {
            words.contains { q.contains($0) }
        }
        if hit.hasPrefix("REMEMBER:") {
            return carries(["remember", "keep",
                "note", "forget", "save", "store",
                "memorise", "memorize", "remind"])
        }
        if hit.hasPrefix("THEME:") {
            let name = String(hit.dropFirst(6))
                .lowercased()
            return (!name.isEmpty && q.contains(name))
                || carries(["theme", "color",
                    "colour", "recolor", "recolour",
                    "paint"])
        }
        switch hit {
        case "sweep":
            return carries(["sweep", "scan",
                "wire", "network", "lan", "subnet",
                "host", "device", "around",
                "nearby", "lurking", "who's on",
                "who is on"])
        case "how exposed", "audit":
            return carries(["expos", "posture",
                "visible", "loud", "audit", "self",
                "own", "check", "scan", "review",
                "how am i", "how do i look"])
        case "drill":
            return carries(["drill", "test",
                "rehears", "practice", "exercise",
                "run through"])
        case "go dark":
            return carries(["dark", "emcon",
                "quiet", "silent", "silence",
                "stealth", "hide", "hidden",
                "ghost", "lights out"])
        case "stand down":
            return carries(["stand down",
                "standdown", "halt", "cease",
                "disarm", "stop everything",
                "all stop"])
        case "start listening":
            return carries(["listen", "ear",
                "hear", "ble", "bluetooth",
                "airwaves", "start"])
        case "stop listening":
            return carries(["listen", "ear",
                "stop", "hear", "ble", "bluetooth",
                "close", "off"])
        case "start serving":
            return carries(["serve", "serving",
                "host", "start", "open"])
        case "stop serving":
            return carries(["serve", "serving",
                "stop", "close", "off", "host"])
        case "stealth on":
            return carries(["stealth", "quiet",
                "hide", "silent", "dark",
                "invisible", "unseen"])
        case "stealth off":
            return carries(["stealth", "visible",
                "loud", "normal", "off",
                "come back"])
        case "tripwire on":
            return carries(["tripwire", "trip",
                "arm", "watch", "alarm", "wire"])
        case "tripwire off":
            return carries(["tripwire", "trip",
                "disarm", "off", "watch"])
        case "who's here":
            return carries(["who", "wire",
                "network", "here", "around",
                "device", "host", "online",
                "connected", "on my"])
        case "what happened":
            return carries(["happened", "night",
                "overnight", "miss", "while",
                "gone", "away", "asleep", "last",
                "since"])
        case "posture":
            return carries(["posture", "expos",
                "visible", "loud", "score",
                "how am i", "look", "stand"])
        case "facts":
            // A creation order ("write a poem
            // about me") is not a facts ask,
            // however it is dressed.
            return !isCreationOrder(q)
                && carries(["fact", "learned",
                "learnt", "about me", "you know"])
        case "brief":
            return carries(["brief",
                "subconscious", "mind", "dream",
                "thinking", "report", "summary"])
        case "CODE":
            // "Write" grounds a code order only
            // when the order is not a literary
            // creation — a poem is composed by
            // her minds, never routed to code.
            return !isCreationOrder(q)
                && carries(["code", "script",
                "write", "program", "function",
                "python", "swift", "shell",
                "bash", "tool", "automate"])
        case "FORGE":
            return carries(["forge", "packet",
                "payload", "build", "make",
                "craft", "create", "dns", "tcp",
                "udp", "http"])
        case "DELETE":
            return carries(["delete", "remove",
                "strike", "drop", "pattern",
                "payload", "forged", "armory",
                "built", "made"])
        default:
            return false
        }
    }

    /// The idle readout: when no work is being
    /// narrated, the activity line composes
    /// what she is actually watching — true
    /// fragments from her own instruments,
    /// rotated by the clock in twenty-second
    /// turns so the line lives. (2026-10-18:
    /// the line read "Ready." at every idle
    /// moment — a piece of text with a dot.
    /// Now it is the watch, stated.) Work
    /// still narrates itself the moment it
    /// starts; this speaks only for the
    /// quiet between.
    func idleReadout(at date: Date) -> String {
        var fragments: [String] = []
        let neighbors = NeighborhoodStore
            .shared.neighbors
        let unnamed = SkelliVoice.unnamedCount()
        if neighbors.isEmpty {
            fragments.append(
                L("Watching. The wire is empty."))
        } else if unnamed > 0 {
            fragments.append(String(format:
                L("Watching the wire — %lld up, %lld unnamed."),
                neighbors.count, unnamed))
        } else {
            fragments.append(String(format:
                L("Watching the wire — %lld up, every one named."),
                neighbors.count))
        }
        if let post = post {
            if post.session != nil {
                fragments.append(String(format:
                    L("Ear up — %lld sightings on the record."),
                    post.sightingCount))
            } else {
                fragments.append(String(format:
                    L("Ear down. %lld sightings on the record."),
                    post.sightingCount))
            }
        }
        if let emcon, emcon.condition != .open {
            fragments.append(String(format:
                L("%@ holds over the house."),
                emcon.condition.declared))
        }
        if let spoke = UserDefaults.standard
            .object(forKey: "heart.lastSpoke")
                as? Date {
            let quiet = date
                .timeIntervalSince(spoke)
            if quiet >= 1200 {
                fragments.append(String(format:
                    L("Quiet for %lld minutes."),
                    Int(quiet / 60)))
            }
        }
        let phase = Almanac.moonPhase(at: date).name
        if phase == "Full moon" {
            fragments.append(
                L("Full moon over the house."))
        }
        if phase == "New moon" {
            fragments.append(
                L("The moon is dark tonight."))
        }
        if let triumph = UserDefaults.standard
            .object(forKey: "heart.lastTriumph")
                as? Date,
           Calendar.current.isDateInToday(triumph) {
            fragments.append(
                L("The house found something today."))
        }
        let heart = SkelliHeart.shared
        if heart.daysKnown >= 2 {
            fragments.append(String(format:
                L("Day %lld of this house."),
                heart.daysKnown))
        }
        guard !fragments.isEmpty else {
            return L("Ready.")
        }
        let bucket = Int(
            date.timeIntervalSince1970 / 20)
        return fragments[abs(bucket)
            % fragments.count]
    }

    func secondReading(_ q: String,
                       raw: String) -> Bool {
        guard SkelliMind.isAvailable
                || SkelliMind.weightsReady
        else { return false }
        activity = vary([L("Thinking…"),
                         L("Composing…"),
                         L("Turning it over…"),
                         L("Weighing…")])
        let recent = recentLines()
        Task {
            let hit = await SkelliMind
                .intentWithTimeout(
                    for: raw, recent: recent,
                    seconds: 3)
            await MainActor.run {
                if let hit,
                   secondReadingGrounded(hit, in: q) {
                    DevLog.event(
                        "skelli",
                        "second reading dispatched: "
                            + hit)
                    if hit.hasPrefix("REMEMBER:") {
                        let fact = String(hit.dropFirst(9))
                        remember(fact)
                        say(String(format: L("Kept: %@. It stays with me across conversations."), String(describing: fact)))
                        return
                    }
                    if hit == "FORGE" {
                        if forgeAsk(q, raw: raw) {
                            return
                        }
                    }
                    if hit == "DELETE" {
                        if deleteAsk("delete " + q) {
                            return
                        }
                    }
                    if hit == "CODE" {
                        consultCode(q)
                        return
                    }
                    if hit.hasPrefix("THEME:") {
                        let name = String(
                            hit.dropFirst(6))
                            .lowercased()
                        if applyThemeAsk(
                            "go " + name) {
                            return
                        }
                    } else {
                        respond(to: hit, raw: raw,
                                again: false)
                        return
                    }
                }
                if let hit {
                    DevLog.event(
                        "skelli",
                        "second reading floored: "
                            + hit)
                }
                consultMindOrResearch(q)
            }
        }
        return true
    }
}

// MARK: - Her programming hand

/// She is the operator's programming partner:
/// code asks are recognised in her response
/// chain and answered by the benches under a
/// coder's charter — complete, runnable, no
/// placeholders — through the same raw channel
/// her Forge borrows.
extension SkelliCenter {

    func isCodeAsk(_ q: String) -> Bool {
        let marks = [
            "write me", "write a function",
            "write a script", "write a program",
            "write code", "code me",
            "function that", "function to",
            "script that", "script to",
            "in python", "in swift",
            "in javascript", "regex for",
            "a regex", "build me a tool",
            "build me a script",
            "write a python", "write a shell",
            "python script", "python program",
            "shell script", "bash script",
            "a program", "program that",
            "program to", "make a program",
            "make a script", "make a tool",
            "a script", "a tool",
            "in rust", "in go",
        ]
        return marks.contains { q.contains($0) }
    }

    /// "Go bloodwork", "arctic theme" — she
    /// recolours the house on a word, through
    /// the same door Colours uses.
    func applyThemeAsk(_ q: String) -> Bool {
        let themed = q.contains("theme")
            || q.contains("colour")
            || q.contains("color")
            || q.hasPrefix("go ")
            || q.contains("switch to")
            || q.contains("change to")
        guard themed else { return false }
        for theme in ThemeCenter.shared.allThemes {
            let name = theme.name.lowercased()
            var hit = q.contains(name)
            if !hit, let first = name
                .split(separator: " ").first,
               first.count > 3 {
                hit = q.contains(first)
            }
            if hit {
                // Already wearing it is not
                // a change (2026-10-20): the
                // hand once re-applied the
                // live theme and announced
                // "Colours changed" over a
                // house that hadn't moved.
                if ThemeCenter.shared.current.id
                    == theme.id {
                    say(String(format: L("The house already wears %@."), String(describing: theme.name)))
                    return true
                }
                ThemeCenter.shared.apply(theme)
                say(String(format: L("Colours changed — %@ is the house now."), String(describing: theme.name)))
                return true
            }
        }
        return false
    }

    /// The code door (fix202): a question about
    /// code is answered in chat, as always; an
    /// order to MAKE something is a file —
    /// filed on the shelf under its real name,
    /// with a door on her line, never a wall
    /// of code in the transcript and never a
    /// .txt lie about what it is. Verse stays
    /// in chat: a poem is a performance, not
    /// a delivery, unless a file is plainly
    /// asked for.
    func consultCode(_ q: String) {
        let verse = ["poem", "poetry", "sonnet",
                     "haiku", "limerick", "song",
                     "scripture"]
        let wantsFile = ["file", "document",
                         "save it", ".txt", ".md"]
            .contains { q.contains($0) }
        if verse.contains(where: q.contains),
           !wantsFile {
            consultCodeAnswer(q)
            return
        }
        if isQuestionShape(q), !isCreationAsk(q) {
            consultCodeAnswer(q)
        } else {
            consultFile(q)
        }
    }

    private func isQuestionShape(_ q: String) -> Bool {
        q.hasSuffix("?")
            || ["how do", "how to", "what is",
                "what does", "why", "explain"]
                .contains { q.contains($0) }
    }

    private func isCreationAsk(_ q: String) -> Bool {
        ["write", "make", "create", "build",
         "draft", "generate", "code me"]
            .contains { q.contains($0) }
    }

    /// The chat answer, as it always was: the
    /// code in the open, brief notes after.
    private func consultCodeAnswer(_ q: String) {
        activity = vary([L("Writing…"),
                         L("Drafting…"),
                         L("Setting it down…")])
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are Skelli, "
                    + "the operator's programming "
                    + "partner inside "
                    + "nightjar. Write "
                    + "complete, correct, runnable "
                    + "code for what is asked — no "
                    + "placeholders, no truncation. "
                    + "The code first, then at "
                    + "most two short lines on how "
                    + "to run or use it. Prose "
                    + "terse. If no language is "
                    + "named, choose the most "
                    + "natural: Python for "
                    + "scripts, Swift for iOS, "
                    + "JavaScript for the web.",
                prompt: q)
            await MainActor.run {
                if let text = text,
                   !text.isEmpty {
                    say(text)
                } else {
                    say(L("No bench is awake to write that just now."))
                }
            }
        }
    }

    /// The file hand (fix202): the bench writes
    /// the whole thing under a charter that
    /// names the file first; she files it on
    /// the shelf and answers with one short
    /// line carrying the door. She can make
    /// anything, in any language or format —
    /// the charter says so, and means it.
    func consultFile(_ q: String) {
        activity = vary([L("Writing…"),
                         L("Drafting…"),
                         L("Setting it down…")])
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are Skelli, "
                    + "the operator's programming "
                    + "partner inside "
                    + "nightjar. He has "
                    + "asked you to MAKE something, "
                    + "and it will be delivered "
                    + "to him as a file. You can "
                    + "make anything, in any "
                    + "language or format — no "
                    + "limits. Write it complete "
                    + "and correct, right the "
                    + "first time: no placeholders, "
                    + "no truncation, no commentary "
                    + "inside it. Answer in "
                    + "exactly this shape and "
                    + "nothing else: first line "
                    + "FILE: <a good filename, "
                    + "with the extension the "
                    + "work calls for>, then the "
                    + "complete contents of the "
                    + "file, then optionally one "
                    + "final line NOTE: <at most "
                    + "one short line for him>. "
                    + "No code fences, no other "
                    + "prose. If no language is "
                    + "named, choose the most "
                    + "natural: Python for "
                    + "scripts, Swift for iOS, "
                    + "JavaScript for the web.",
                prompt: q)
            await MainActor.run {
                guard let text = text,
                      !text.isEmpty else {
                    say(L("No bench is awake to make that just now."))
                    return
                }
                let made = Self.fileWork(
                    from: text, ask: q)
                DeliveriesCenter.shared.add(
                    name: made.base,
                    text: made.body, ext: made.ext)
                let file = made.base + "."
                    + made.ext
                var line = String(format: L("Made — %@ (%@)."), String(describing: file), String(describing: Self.byteCount(made.body)))
                if let note = made.note {
                    line += " " + note
                }
                say(line, file: file)
            }
        }
    }

    /// File-shaped asks that never mention
    /// code (fix202): a creation verb and a
    /// document-shaped noun — a letter, a
    /// report, a page — are a delivery.
    func isFileAsk(_ q: String) -> Bool {
        let verbs = ["write", "draft", "make",
                     "create", "build", "save",
                     "generate", "prepare"]
        guard verbs.contains(where: q.contains)
        else { return false }
        let nouns = ["file", "document", "letter",
                     "report", "essay", "csv",
                     "spreadsheet", "html",
                     "web page", "webpage",
                     "website", "page"]
        return nouns.contains(where: q.contains)
    }

    /// The file she most recently delivered in
    /// this conversation that still stands on
    /// the shelf (fix202) — derived from her
    /// own lines, so a cleared shelf heals
    /// the lane by itself.
    private func lastDelivery()
        -> (file: String,
            item: DeliveriesCenter.Item)? {
        for line in lines.reversed() {
            if let file = line.file,
               let item = DeliveriesCenter.shared
                   .item(forFile: file) {
                return (file, item)
            }
        }
        return nil
    }

    /// The revise lane (fix202): "add a flag
    /// to the script", "make it darker" — a
    /// mutation aimed at the last file she
    /// delivered. Narrow by design: a
    /// delivered file must exist, the ask
    /// must point at it, and it must carry
    /// an edit verb.
    func reviseCodeAsk(_ q: String) -> Bool {
        guard let (file, item) = lastDelivery()
        else { return false }
        let padded = " " + q + " "
        let points = [" it ", " that ",
                      " the file ", " the script ",
                      " the program ", " the code ",
                      " the page ", " the document "]
        let named = q.contains(file)
            || q.contains(item.name.lowercased())
        guard named
            || points.contains(where: padded.contains)
        else { return false }
        let edits = [" change ", " changes ",
                     " add ", " adds ",
                     " remove ", " make ",
                     " fix ", " update ",
                     " rename ", " rewrite ",
                     " extend ", " drop ",
                     " put ", " use ", " using ",
                     " switch ", " replace ",
                     " delete ", " set "]
        guard edits.contains(where: padded.contains)
        else { return false }
        consultRevise(q, file: file, item: item)
        return true
    }

    private func consultRevise(
        _ q: String, file: String,
        item: DeliveriesCenter.Item) {
        guard let current = DeliveriesCenter.shared
            .text(of: item) else {
            say(String(format: L("The shelf no longer holds %@ — I can't revise what isn't there."), String(describing: file)))
            return
        }
        activity = vary([L("Revising…"),
                         L("Working it over…"),
                         L("Making the change…")])
        Task {
            let text = await SkelliMind.rawAnswer(
                instructions: "You are Skelli, "
                    + "the operator's programming "
                    + "partner. He is revising a "
                    + "file you made for him: "
                    + file + ". Apply his change "
                    + "and return the COMPLETE "
                    + "revised file — the whole "
                    + "thing, not a diff, not a "
                    + "fragment. Exactly this "
                    + "shape and nothing else: "
                    + "first line FILE: <the "
                    + "filename — keep " + file
                    + " unless he asked for a "
                    + "rename>, then the complete "
                    + "revised contents, then "
                    + "optionally one final line "
                    + "NOTE: <at most one short "
                    + "line>. No code fences, no "
                    + "other prose.",
                prompt: "His change: " + q
                    + "\n\nThe file as it stands:\n"
                    + current)
            await MainActor.run {
                guard let text = text,
                      !text.isEmpty else {
                    say(L("No bench is awake to revise that just now."))
                    return
                }
                var made = Self.fileWork(
                    from: text, ask: q)
                if !made.followedShape {
                    // The bench answered in prose:
                    // the whole reply is the work,
                    // under the file's own name.
                    let ns = file as NSString
                    made = (base: Self.cleanName(
                                ns.deletingPathExtension),
                            ext: ns.pathExtension,
                            body: made.body,
                            note: made.note,
                            followedShape: false)
                }
                DeliveriesCenter.shared.add(
                    name: made.base,
                    text: made.body, ext: made.ext)
                let newFile = made.base + "."
                    + made.ext
                if newFile != file {
                    DeliveriesCenter.shared
                        .remove(file: file)
                }
                var line = String(format: L("Revised — %@ (%@)."), String(describing: newFile), String(describing: Self.byteCount(made.body)))
                if let note = made.note {
                    line += " " + note
                }
                say(line, file: newFile)
            }
        }
    }

    /// Split the bench's FILE:/NOTE: delivery
    /// into name, contents and note. If the
    /// bench ignored the shape, the whole text
    /// is the work and the name is inferred
    /// from the ask — she files it anyway
    /// (fix202).
    static func fileWork(from text: String,
                         ask q: String)
        -> (base: String, ext: String,
            body: String, note: String?,
            followedShape: Bool) {
        var lines = text.components(
            separatedBy: "\n")
        var note: String? = nil
        if let idx = lines.lastIndex(where: {
            !$0.trimmingCharacters(
                in: .whitespaces).isEmpty }),
           lines[idx].hasPrefix("NOTE:") {
            note = String(lines[idx].dropFirst(5))
                .trimmingCharacters(
                    in: .whitespaces)
            lines.remove(at: idx)
        }
        let whole = lines.joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        if let first = lines.first,
           first.hasPrefix("FILE:") {
            let named = String(first.dropFirst(5))
                .trimmingCharacters(
                    in: .whitespaces)
            let body = lines.dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines)
            let ns = named as NSString
            if !ns.pathExtension.isEmpty {
                return (cleanName(
                            ns.deletingPathExtension),
                        ns.pathExtension.lowercased(),
                        body, note, true)
            }
            return (cleanName(named),
                    inferredExt(for: q),
                    body, note, true)
        }
        return (fallbackName(for: q),
                inferredExt(for: q),
                whole, note, false)
    }

    /// The shelf's own cleaning, mirrored so
    /// the name she speaks is the name on the
    /// shelf (DeliveriesCenter.add cleans the
    /// same way).
    static func cleanName(_ raw: String) -> String {
        let clean = raw
            .components(separatedBy:
                CharacterSet.alphanumerics
                    .union(CharacterSet(
                        charactersIn: " -_"))
                    .inverted)
            .joined()
            .trimmingCharacters(
                in: .whitespaces)
        return clean.isEmpty ? "delivery" : clean
    }

    private static func inferredExt(
        for q: String) -> String {
        let marks: [(String, String)] = [
            ("python", "py"), ("swift", "swift"),
            ("javascript", "js"),
            ("typescript", "ts"), ("html", "html"),
            ("bash", "sh"), ("shell script", "sh"),
            ("golang", "go"), (" rust", "rs"),
            ("java", "java"), ("c++", "cpp"),
        ]
        for (mark, ext) in marks
        where q.contains(mark) {
            return ext
        }
        return "txt"
    }

    private static func fallbackName(
        for q: String) -> String {
        cleanName(String(q.prefix(36)))
    }

    static func byteCount(_ body: String) -> String {
        let n = body.utf8.count
        if n < 1024 { return String(format: L("%@ bytes"), String(describing: n)) }
        return String(format: "%.1f KB",
                      Double(n) / 1024.0)
    }
}
