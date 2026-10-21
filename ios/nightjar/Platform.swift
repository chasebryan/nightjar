import Foundation
import SwiftUI

// Platform.swift — the macOS bridge (fix237).
//
// The house is one source tree serving two targets:
// the iPhone app and its Mac sibling. Everything in
// this file exists ONLY on macOS; the iOS build never
// sees it. The shims are deliberately narrow — each
// one covers exactly the surface the shared sources
// already use, spelled the way they use it, so the
// shared code does not grow platform branches for
// one-line system services. Anything richer than a
// one-line service (the tab shell, the NFC organs,
// the background-task checker) is gated at its own
// site instead, where the difference is honest.

#if os(macOS)
import AppKit

/// Photos and artwork cross as NSImage on the Mac.
/// Display-side uses (size, data) line up; anything
/// iOS-shaped beyond that is gated at its site.
typealias UIImage = NSImage

/// Colour literals and dynamic colours cross as
/// NSColor, whose calibrated initializers match the
/// spelling the shared sources use.
typealias UIColor = NSColor

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
    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(data: data)
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }
    func updateNSView(_ view: NSImageView, context: Context) {}
}

/// The boot film on the Mac: an AVPlayer view with
/// no controls, playing the film data from a
/// scratch file, reporting progress on a clock —
/// the same contract the phone's player keeps.
struct BootFilmPlayer: NSViewRepresentable {
    let data: Data
    var focusX: CGFloat = 0.5
    var focusY: CGFloat = 0.5
    var zoom: CGFloat = 1
    var maxPixel: Int = 1024
    var onProgress: (Double) -> Void

    func makeNSView(context: Context) -> AVPlayerView {
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
    func updateNSView(_ view: AVPlayerView, context: Context) {}
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
    /// Hide the bar itself: the navigation bar on
    /// the phone, the window toolbar on the Mac.
    func houseBarHidden() -> some View {
#if os(macOS)
        toolbar(.hidden, for: .windowToolbar)
#else
        toolbar(.hidden, for: .navigationBar)
#endif
    }

    /// Hide the bar's background, likewise.
    func houseBarBackgroundHidden() -> some View {
#if os(macOS)
        toolbarBackground(.hidden, for: .windowToolbar)
#else
        toolbarBackground(.hidden, for: .navigationBar)
#endif
    }
}
