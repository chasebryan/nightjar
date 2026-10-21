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
