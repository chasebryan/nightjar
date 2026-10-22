import Foundation
import SwiftUI
import AVFoundation

// Platform.swift — the macOS bridge (fix237).
//
// The house is one source tree serving two targets:
// the iPhone app and its Mac sibling. The shims in
// the gated blocks below exist ONLY on macOS; the
// helpers after them are shared by both targets —
// mind which side of a gate a symbol lives on
// before shared code calls it (fix260's lesson:
// BootFilmMeasure sat in the Mac gate while the
// boot measured films on both platforms). The
// shims are deliberately narrow — each
// one covers exactly the surface the shared sources
// already use, spelled the way they use it, so the
// shared code does not grow platform branches for
// one-line system services. Anything richer than a
// one-line service (the tab shell, the NFC organs,
// the background-task checker) is gated at its own
// site instead, where the difference is honest.

#if os(macOS)
import AppKit
import ImageIO

/// Photos and artwork cross as NSImage on the Mac.
/// Display-side uses (size, data) line up; anything
/// iOS-shaped beyond that is gated at its site.
typealias UIImage = NSImage

/// Colour literals and dynamic colours cross as
/// NSColor, whose calibrated initializers match the
/// spelling the shared sources use.
typealias UIColor = NSColor

/// Fonts cross as NSFont; the monospaced system
/// font the canvas hands ask for exists under
/// the same spelling there.
typealias UIFont = NSFont

/// The pasteboard: the shared code only ever writes
/// a string to the general pasteboard. On the Mac
/// that is NSPasteboard.general.
final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.setString(newValue, forType: .string)
            }
        }
    }
}

/// The machine's name and system version, in the
/// shape UIDevice.current spells them on iOS. The
/// name is the Mac's computer name; the version is
/// the host OS version string.
final class UIDevice {
    static let current = UIDevice()
    var name: String {
        Host.current().localizedName ?? "Mac"
    }
    var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// The battery surface, answered honestly for a
    /// laptop: state unknown, level unread — the
    /// Gauntlet's battery derate simply never bites.
    enum BatteryState { case unknown, unplugged, charging, full }
    var batteryState: BatteryState { .unknown }
    var batteryLevel: Float { -1 }
    var isBatteryMonitoringEnabled = false
}

/// One screen use exists in the house (the virtual
/// display in BlacksiteGFX). On the Mac the main
/// screen's frame plays the part.
final class UIScreen {
    static let main = UIScreen()
    var bounds: CGRect {
        NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
    var scale: CGFloat {
        NSScreen.main?.backingScaleFactor ?? 2
    }
    var nativeScale: CGFloat { scale }
}

/// The application object, in the narrow shape the
/// shared sources use on iOS: a state that is simply
/// always active (a Mac app that is running is in
/// front of its operator), and the memory-warning
/// notice's name (posted by UIKit on the phone; on
/// the Mac it simply never arrives).
final class UIApplication {
    static let shared = UIApplication()
    enum State { case active, inactive, background }
    var applicationState: State { .active }
    static let didReceiveMemoryWarningNotification =
        Notification.Name("UIApplicationDidReceiveMemoryWarning")
}

/// Free memory, the macOS way: the host's VM
/// statistics, free plus inactive pages.
func macAvailableMemoryBytes() -> Int {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
        MemoryLayout<vm_statistics64>.size
            / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &stats) { ptr in
        ptr.withMemoryRebound(to: integer_t.self,
                              capacity: Int(count)) {
            host_statistics64(mach_host_self(),
                              HOST_VM_INFO64, $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    let pages = Int(stats.free_count)
        + Int(stats.inactive_count)
    return pages * Int(vm_page_size)
}

extension NSImage {
    /// PNG bytes, the spelling the shared sources
    /// use on the phone.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif

#if os(macOS)
import SwiftUI
import AVKit

/// The haptic generators, as silent stand-ins: a
/// Mac has no Taptic Engine, and the house's beats
/// are felt, not heard — on the laptop they simply
/// do not sound. Every call site keeps its shape;
/// the motor just isn't there.
final class UIImpactFeedbackGenerator {
    enum FeedbackStyle { case light, medium, heavy, rigid, soft }
    init(style: FeedbackStyle) {}
    func prepare() {}
    func impactOccurred() {}
    func impactOccurred(intensity: CGFloat) {}
}

final class UISelectionFeedbackGenerator {
    func prepare() {}
    func selectionChanged() {}
}

/// The title display mode is an iOS navigation
/// spelling; on the Mac the modifier is a no-op
/// and the window's title bar is the system's own.
enum NavigationBarItem {
    enum TitleDisplayMode { case automatic, inline, large }
}

extension View {
    func navigationBarTitleDisplayMode(
        _ mode: NavigationBarItem.TitleDisplayMode) -> some View {
        self
    }
    func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }
}

/// Keyboard types are an iOS spelling too; the Mac
/// has one keyboard, and it is already attached.
enum UIKeyboardType: Int {
    case `default` = 0
    case asciiCapable = 1
    case numbersAndPunctuation = 2
    case URL = 3
    case numberPad = 4
    case phonePad = 5
    case namePhonePad = 6
    case emailAddress = 7
    case decimalPad = 8
    case twitter = 9
    case webSearch = 10
    case asciiCapableNumberPad = 11
}

/// The boot's GIF player on the Mac: NSImageView
/// animates a GIF natively, which is all the
/// phone's hand-rolled player was reaching for.
struct GIFPlayerView: NSViewRepresentable {
    let data: Data
    var playOnce = false
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        let image = NSImage(data: data)
        if playOnce {
            for case let bitmap as NSBitmapImageRep in image?.representations ?? [] {
                bitmap.setProperty(.loopCount, withValue: NSNumber(value: 1))
            }
        }
        view.image = image
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {}
}

/// The boot film on the Mac. The reel's bytes are
/// a GIF, which no AVPlayer can decode — so the
/// film takes the animated-image road, its length
/// measured off the frames and its progress told
/// on a clock, the same contract the phone's
/// player keeps. A film the operator brings as
/// real video still rides the AVPlayer road.
struct BootFilmPlayer: NSViewRepresentable {
    let data: Data
    var focusX: CGFloat = 0.5
    var focusY: CGFloat = 0.5
    var zoom: CGFloat = 1
    var maxPixel: Int = 1024
    var onProgress: (Double) -> Void

    private var isGIF: Bool {
        data.starts(with: [0x47, 0x49, 0x46, 0x38])
    }

    func makeNSView(context: Context) -> NSView {
        if isGIF {
            let view = NSImageView()
            view.image = NSImage(data: data)
            view.animates = true
            view.imageScaling =
                .scaleProportionallyUpOrDown
            reportGIFProgress()
            return view
        }
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-bootfilm.mp4")
        try? data.write(to: url, options: .atomic)
        let player = AVPlayer(url: url)
        view.player = player
        let report = onProgress
        player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1,
                                preferredTimescale: 600),
            queue: .main) { time in
                if let duration = player.currentItem?
                    .duration.seconds, duration > 0 {
                    report(min(1, time.seconds / duration))
                }
            }
        player.play()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}

    /// The GIF's own length, summed from its frame
    /// delays, and a clock that tells the boot how
    /// much of it has played.
    private func reportGIFProgress() {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else { return }
        var total = 0.0
        for i in 0..<CGImageSourceGetCount(source) {
            if let props = CGImageSourceCopyPropertiesAtIndex(
                source, i, nil) as? [String: Any],
               let gif = props[kCGImagePropertyGIFDictionary
                as String] as? [String: Any],
               let delay = gif[kCGImagePropertyGIFDelayTime
                as String] as? Double {
                total += max(delay, 0.02)
            }
        }
        guard total > 0 else { return }
        let report = onProgress
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.1,
                             repeats: true) { timer in
            let value = min(1, Date()
                .timeIntervalSince(start) / total)
            report(value)
            if value >= 1 { timer.invalidate() }
        }
    }
}

/// Capitalization is a phone-keyboard concern; the
/// Mac has a real keyboard. The spelling exists so
/// shared text fields keep theirs — and does nothing.
enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

/// The edit toggle: on the Mac the lists select
/// with the pointer and the delete bar answers to
/// the selection, so the toggle itself stands down
/// to nothing.
struct EditButton: View {
    var body: some View { EmptyView() }
}

extension View {
    func textInputAutocapitalization(
        _ style: TextInputAutocapitalization?) -> some View {
        self
    }
}
#endif

/// The length of a video backdrop, measured off
/// the file itself. The boot times its whole
/// ceremony against the film — the text, the
/// print and the finale land on its last frame —
/// so the film needs its seconds known before
/// the printing starts, on the phone as much as
/// on the laptop. (Born Mac-only in fix248; the
/// phone grew its own video road in fix259 and
/// calls it too — fix260 lifts it out of the
/// Mac gate so both targets see it.)
enum BootFilmMeasure {
    static func videoSeconds(for data: Data) async
        -> Double? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "nightjar-bootfilm-measure.mp4")
        guard (try? data.write(to: url,
                               options: .atomic)) != nil
        else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset
            .load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0
            ? seconds : nil
    }
}

// MARK: - The Mac window's shape (fix240)
//
// The house was drawn for a phone in the hand; opened
// cold on a laptop it would inherit that portrait shape.
// On macOS the app's scene and root view carry a laptop's
// proportions instead — a wide default window with a
// floor it will not shrink below. On iOS both helpers
// are pass-throughs: the phone keeps its own shape.

extension Scene {
    func macWindowDefaults() -> some Scene {
#if os(macOS)
        self.defaultSize(width: 1240, height: 820)
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
#else
        self
#endif
    }
}

// MARK: - The Mac skin (fix261)
//
// The port gave the Mac the phone's bones; this is
// its own skin. A Mac-first nightjar is a console:
// dark, calm, dense — working rooms on a quiet
// charcoal ground, prose in a reading column,
// panels with hairline edges, and the theme's
// accent spent like a spice. The living wallpaper
// keeps the boot and Skelli's room; it does not
// sit behind forms and tables. Every helper here
// is identity on iOS — the phone keeps its skin.

#if os(macOS)
/// The console ground: what the Mac's working
/// rooms sit on. A near-black charcoal washed
/// faintly with the theme's tint from the top,
/// so the chosen theme still breathes without
/// art behind the work.
struct MacGround: View {
    @ObservedObject private var themes =
        ThemeCenter.shared

    var body: some View {
        let theme = themes.current
        ZStack {
            Color(red: 0.052, green: 0.058,
                  blue: 0.068)
            LinearGradient(
                colors: [theme.tint.opacity(0.13),
                         theme.tint.opacity(0.0)],
                startPoint: .top,
                endPoint: .center)
            Rectangle()
                .fill(Color.black
                    .opacity(theme.dim * 0.4))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The window's own bar, dressed as a Mac app's:
/// the room's own title stands in it once (each
/// room's stack names it — fix264 took the
/// shell's duplicate principal title out), and
/// a running-work button rides at the trailing
/// end while the process board has anything
/// on it.
struct MacShellBar: ViewModifier {
    let processes: Int
    let onProcesses: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if processes > 0 {
                ToolbarItem(
                    placement: .primaryAction) {
                    Button(action: onProcesses) {
                        Label("\(processes)",
                              systemImage:
                                "circle.grid.2x2.fill")
                    }
                    .help(L("Running work"))
                }
            }
        }
    }
}
#endif

extension View {
    /// The shell's Mac bar (see MacShellBar); the
    /// phone's strip needs no second dress.
    func macShellBar(processes: Int,
                     onProcesses: @escaping () -> Void)
        -> some View {
#if os(macOS)
        modifier(MacShellBar(
            processes: processes,
            onProcesses: onProcesses))
#else
        self
#endif
    }

    /// A pane of the Mac's detail (fix264): the
    /// shown room stands; a hidden one takes no
    /// touches and stays silent for VoiceOver,
    /// but stays alive — its work is not lost
    /// for being looked away from.
    func macRoomVisible(_ shown: Bool) -> some View {
#if os(macOS)
        opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
#else
        self
#endif
    }

    /// The Mac's form dress (fix264): grouped —
    /// sections stand as cards with their labels
    /// over their fields, the way System Settings
    /// is built — instead of the wide two-column
    /// sprawl a phone form stretches into across
    /// a laptop window. The phone's forms are
    /// already the shape it wants.
    func macFormStyle() -> some View {
#if os(macOS)
        formStyle(.grouped)
#else
        self
#endif
    }

    /// The Mac's list dress (fix264): inset —
    /// rows stand in a margined, rounded group
    /// instead of running bleed-edge across the
    /// window. Identity on the phone.
    func macListStyle() -> some View {
#if os(macOS)
        listStyle(.inset)
#else
        self
#endif
    }

    /// Keep the phone's explicit grouped presentation while using the
    /// supported inset style on Mac; insetGrouped is unavailable there.
    func groupedListStyle() -> some View {
#if os(macOS)
        listStyle(.inset)
#else
        listStyle(.insetGrouped)
#endif
    }

    /// A reading measure: on the Mac the content
    /// stands in a centered column of the given
    /// width instead of stretching edge to edge
    /// across a laptop window; the phone's layout
    /// is already the width it wants.
    func macColumn(_ width: CGFloat) -> some View {
#if os(macOS)
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
#else
        self
#endif
    }

    /// The panel dress: a quiet fill and a hairline
    /// edge, the dark console's card. On the phone
    /// the lists already dress their own rows.
    func macPanel() -> some View {
#if os(macOS)
        background(
            RoundedRectangle(cornerRadius: 10,
                             style: .continuous)
                .fill(Color.white.opacity(0.045)))
            .overlay(
                RoundedRectangle(cornerRadius: 10,
                                 style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.09),
                        lineWidth: 1))
            .clipShape(
                RoundedRectangle(cornerRadius: 10,
                                 style: .continuous))
#else
        self
#endif
    }
}

struct MacWindowSizing: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.frame(minWidth: 920, idealWidth: 1240,
                      minHeight: 620, idealHeight: 820)
#else
        content
#endif
    }
}

// MARK: - One image spelling

extension Image {
    /// The platform's own image type, wrapped: on the
    /// phone a UIImage, on the Mac an NSImage — one
    /// spelling at every call site.
    static func platformImage(_ image: UIImage) -> Image {
#if os(macOS)
        Image(nsImage: image)
#else
        Image(uiImage: image)
#endif
    }
}

// MARK: - Bars and covers, in both houses' spellings

extension ToolbarItemPlacement {
    /// The bar's leading end: the navigation bar's
    /// leading slot on the phone, the toolbar's
    /// navigation area on the Mac.
    static var houseLeading: ToolbarItemPlacement {
#if os(macOS)
        .navigation
#else
        .navigationBarLeading
#endif
    }
    /// The bar's trailing end, likewise.
    static var houseTrailing: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#else
        .navigationBarTrailing
#endif
    }
    /// The bottom bar: a phone bar on iOS, the
    /// window's status area on the Mac.
    static var houseBottom: ToolbarItemPlacement {
#if os(macOS)
        .status
#else
        .bottomBar
#endif
    }
}

extension View {
    /// The dark bar scheme: the navigation bar on
    /// the phone, the window toolbar on the Mac.
    func houseToolbarColorScheme() -> some View {
#if os(macOS)
        toolbarColorScheme(.dark, for: .windowToolbar)
#else
        toolbarColorScheme(.dark, for: .navigationBar)
#endif
    }

    /// A full-screen cover on the phone; on the Mac
    /// a sheet, which is the window's own full dress.
    func houseFullScreenCover<C: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> C) -> some View {
#if os(macOS)
        sheet(isPresented: isPresented, content: content)
#else
        fullScreenCover(isPresented: isPresented, content: content)
#endif
    }

    func houseFullScreenCover<Item: Identifiable, C: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> C) -> some View {
#if os(macOS)
        sheet(item: item, content: content)
#else
        fullScreenCover(item: item, content: content)
#endif
    }
}

// MARK: - Images and memory, in both houses' spellings

/// A platform image from a CGImage: the phone's
/// initializer spells it bare; the Mac's wants
/// the size spoken.
func platformImage(cgImage cg: CGImage) -> UIImage {
#if os(macOS)
    NSImage(cgImage: cg,
            size: NSSize(width: cg.width,
                         height: cg.height))
#else
    UIImage(cgImage: cg)
#endif
}

/// Whether a platform image carries animation:
/// the phone's image keeps a frames array; the
/// Mac's keeps a frame count on its bitmap rep.
func platformImageIsAnimated(_ image: UIImage) -> Bool {
#if os(macOS)
    for rep in image.representations {
        guard let bitmap = rep as? NSBitmapImageRep,
              let frames = bitmap.value(
                forProperty: NSBitmapImageRep
                    .PropertyKey.frameCount) as? Int,
              frames > 1 else { continue }
        return true
    }
    return false
#else
    image.images != nil
#endif
}

/// The kernel's free-memory figure: the phone
/// asks os_proc directly; the Mac reads the
/// host's VM statistics (the shim above).
func platformAvailableMemory() -> Int {
#if os(macOS)
    macAvailableMemoryBytes()
#else
    os_proc_available_memory()
#endif
}

extension View {
    /// Hide the bar itself: the navigation bar
    /// on the phone. On the Mac this is a no-op
    /// BY DESIGN: there is no bar inside a room
    /// to hide, and the window toolbar belongs
    /// to the house — it carries the sidebar's
    /// chrome, and a room that hides it takes
    /// the navigator down with it (Skelli's
    /// room did exactly that, 2026-10-20: her
    /// panel lost its chrome and blended into
    /// her backdrop while every other room kept
    /// its). A room's full-bleed wish is already
    /// granted by the tab's own content area.
    func houseBarHidden() -> some View {
#if os(macOS)
        self
#else
        toolbar(.hidden, for: .navigationBar)
#endif
    }

    /// Hide the bar's background, likewise —
    /// and likewise the house's, not a room's,
    /// to strip on the Mac.
    func houseBarBackgroundHidden() -> some View {
#if os(macOS)
        self
#else
        toolbarBackground(.hidden, for: .navigationBar)
#endif
    }
}

/// An image's pixel scale: the phone carries it
/// on the image; the Mac reads it off the bitmap
/// rep — pixels against points.
func platformImageScale(_ image: UIImage) -> CGFloat {
#if os(macOS)
    guard let rep = image.representations.first
        as? NSBitmapImageRep, image.size.width > 0
    else { return 1 }
    return CGFloat(rep.pixelsWide) / image.size.width
#else
    image.scale
#endif
}

extension View {
    /// The pointer's highlight: a phone effect;
    /// on the Mac the system's own button hover
    /// answers, so the spelling simply rests.
    func houseHoverEffect() -> some View {
#if os(macOS)
        self
#else
        hoverEffect(.highlight)
#endif
    }
}

// houseMacTabStyle retired (fix264): the tab
// view's sidebar dress went with the tab view
// itself — the Mac's navigator is a native
// split view now (ContentView's macShell),
// and no caller remains.

#if os(macOS)
/// A clear pane that hears scroll-wheel turns
/// while it lives and hands their deltas up.
/// Some Mac instruments — Blacksite's program
/// wheel — turn by scrolling, and SwiftUI has
/// no ear for the wheel of a mouse; this is
/// it. The monitor is local to the app and
/// dies with the pane (dismantle removes it),
/// so it hears only while its owner is on
/// screen.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (Double) -> Void

    final class Coordinator {
        var monitor: Any?
        var onScroll: (Double) -> Void = { _ in }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onScroll = onScroll
        let coordinator = context.coordinator
        context.coordinator.monitor =
            NSEvent.addLocalMonitorForEvents(
                matching: .scrollWheel) { event in
                coordinator.onScroll(
                    Double(event.scrollingDeltaY))
                return event
            }
        return NSView()
    }

    func updateNSView(_ nsView: NSView,
                      context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: Coordinator
    ) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
            coordinator.monitor = nil
        }
    }
}
#endif
