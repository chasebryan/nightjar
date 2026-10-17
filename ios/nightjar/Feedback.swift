import CoreBluetooth
import ImageIO
import SwiftUI
import UIKit

/// Little in-app banners that say what just happened, then fade —
/// so the app narrates itself instead of silently changing state.
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    @Published var current: Toast?
    private var queue: [Toast] = []
    private var draining = false

    /// Enqueue, never overwrite: messages drain FIFO, each on
    /// screen for ~2.2 s (errors ~4.5 s), carrying its own error
    /// flag with it.
    func show(_ message: String, error: Bool = false) {
        queue.append(Toast(message: message, isError: error))
        guard !draining else { return }
        draining = true
        displayNext()
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
        let dwell = toast.isError ? 4.5 : 2.2
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) { [weak self] in
            guard let self = self else { return }
            if self.queue.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) { self.current = nil }
                self.draining = false
            } else {
                self.displayNext()
            }
        }
    }
}

struct ToastView: View {
    let toast: ToastCenter.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError
                  ? "exclamationmark.triangle.fill"
                  : "checkmark.circle.fill")
            Text(toast.message)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(
            toast.isError ? Color.red.opacity(0.92)
                          : Color(white: 0.16).opacity(0.95)))
        .shadow(radius: 8, y: 3)
        .padding(.horizontal, 16)
    }
}

/// The living wallpaper: the operator's reel, decoded ONCE
/// and shared by every backdrop in the app. It plays from
/// the beginning of its loop to the end and starts again,
/// forever — a background that breathes instead of a picture
/// that hangs. By either road in: a "Wallpaper" data asset,
/// or wallpaper.gif in the bundle.
enum Wallpaper {
    static let image: UIImage? = {
        let data: Data?
        if let asset = NSDataAsset(name: "Wallpaper") {
            data = asset.data
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
struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .black
        view.startAnimating()
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}
}

/// The app's backdrop, wearing whatever Colours says this
/// slot wears: the living wallpaper, the Jolly Roger, the
/// plain theme colour, or the operator's own art — washed
/// with the theme's tint and dimmed by its measure, so text
/// stays readable over any of them.
struct AppBackdrop: View {
    var slot: BackdropSlot? = nil
    @Environment(\.backdropSlot) private var ambientSlot
    @ObservedObject private var themes = ThemeCenter.shared

    private var resolvedSlot: BackdropSlot {
        slot ?? ambientSlot
    }

    var body: some View {
        // GeometryReader pins the backdrop to exactly the size
        // it is offered. A bare scaledToFill image inside a
        // ZStack reports its natural size and blows the whole
        // layout out to match — frame + clip keep it tame.
        let theme = themes.current
        let choice = themes.effectiveChoice(for: resolvedSlot)
        GeometryReader { geo in
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
                AnimatedImageView(image: wallpaper)
                    .frame(width: geo.size.width,
                           height: geo.size.height)
                    .clipped()
            } else {
                skull(geo)
            }
        case .skull:
            skull(geo)
        case .custom:
            if let image = BackdropMedia.image(
                for: resolvedSlot) {
                if image.images != nil {
                    AnimatedImageView(image: image)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                        .clipped()
                } else {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                        .clipped()
                }
            } else if let wallpaper = Wallpaper.image {
                AnimatedImageView(image: wallpaper)
                    .frame(width: geo.size.width,
                           height: geo.size.height)
                    .clipped()
            } else {
                skull(geo)
            }
        case .plain:
            LinearGradient(
                colors: [theme.tint, Color.black],
                startPoint: .top, endPoint: .bottom)
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

/// The themed-screen recipe, applied per tab: transparent
/// scroll backgrounds AND the backdrop painted behind that
/// very screen, in that tab's own slot. (Painting it only
/// behind the TabView is not enough — on current iOS the tab
/// container fills its own frame opaquely, so an ancestor's
/// backdrop never shows through. Behind each tab's own root,
/// with its list transparent, it does.)
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
/// out here. Fades into the app after ~2 seconds; a tap
/// skips it. Without the reel in the bundle, the same log
/// plays over plain black — never a broken boot.
struct BootView: View {
    let onDone: () -> Void

    @StateObject private var book = PayloadBook()
    @AppStorage("stealthMode") private var stealthMode = false
    @State private var shown = 0
    @State private var cursorOn = true

    private struct BootLine {
        let text: String
        let tone: Tone
        enum Tone { case cmd, ok, warn, off }
    }

    /// The boot reel, by either road in: a "BootReel" data
    /// asset, or boot-reel.gif in the bundle.
    private var gifData: Data? {
        if let asset = NSDataAsset(name: "BootReel") {
            return asset.data
        }
        if let url = Bundle.main.url(forResource: "boot-reel",
                                     withExtension: "gif") {
            return try? Data(contentsOf: url)
        }
        return nil
    }

    private var lines: [BootLine] {
        var out: [BootLine] = [
            BootLine(text: "> nightjar-hack // ios", tone: .cmd),
            BootLine(text: "[ ok ] host      \(UIDevice.current.name)",
                     tone: .ok),
        ]
        if let ip = Mouth.localIPAddress() {
            out.append(BootLine(text: "[ ok ] net en0 \(ip)",
                                tone: .ok))
        } else {
            out.append(BootLine(text: "[ -- ] net no address yet",
                                tone: .off))
        }
        out.append(BootLine(
            text: "[ ok ] library   \(book.items.count) payloads loaded",
            tone: .ok))
        switch CBManager.authorization {
        case .allowedAlways:
            out.append(BootLine(text: "[ ok ] ble permission granted",
                                tone: .ok))
        case .denied, .restricted:
            out.append(BootLine(text: "[ !! ] ble permission denied",
                                tone: .warn))
        default:
            out.append(BootLine(text: "[ -- ] ble permission not determined",
                                tone: .off))
        }
        out.append(stealthMode
            ? BootLine(text: "[ ok ] stealth   ON — unlisted, silent",
                       tone: .ok)
            : BootLine(text: "[ -- ] stealth   off", tone: .off))
        if Wallpaper.image != nil
            || UIImage(named: "AppBackground") != nil {
            out.append(BootLine(text: "[ ok ] backdrop loaded",
                                tone: .ok))
        } else {
            out.append(BootLine(text: "[ -- ] backdrop image missing",
                                tone: .off))
        }
        out.append(BootLine(text: "> the world is yours",
                            tone: .cmd))
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

    private var progress: CGFloat {
        lines.isEmpty ? 0 : CGFloat(shown) / CGFloat(lines.count)
    }

    @ViewBuilder
    private func lineView(_ line: BootLine) -> some View {
        let text = Text(line.text)
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

    /// The loading bar: twenty-six blocks that fill with a
    /// phosphor glow as the log completes, and the count.
    private var loadingBar: some View {
        VStack(spacing: 7) {
            GeometryReader { geo in
                let count = 26
                let gap: CGFloat = 2.5
                let width = (geo.size.width
                             - gap * CGFloat(count - 1))
                            / CGFloat(count)
                HStack(spacing: gap) {
                    ForEach(0..<count, id: \.self) { i in
                        let lit = Double(i)
                            < Double(count) * Double(progress)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(lit ? color(.ok)
                                      : Color.white.opacity(0.10))
                            .frame(width: width, height: 14)
                            .shadow(color: lit
                                    ? color(.ok).opacity(0.85)
                                    : .clear, radius: 5)
                    }
                }
            }
            .frame(height: 14)
            HStack {
                Text("LOADING THE NIGHT")
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color(white: 0.55))
                    .shadow(color: .black.opacity(0.9), radius: 3)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced)
                          .weight(.bold))
                    .foregroundStyle(color(.ok))
                    .shadow(color: color(.ok).opacity(0.6), radius: 6)
            }
        }
        .animation(.easeOut(duration: 0.25), value: shown)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data = gifData {
                GIFPlayerView(data: data)
                    .ignoresSafeArea()
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
                    Text("nightjar-hack")
                        .font(.system(.title3, design: .monospaced)
                              .weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.9),
                                radius: 5, x: 0, y: 1)
                    Text("IOS BUILD · FIELD UNIT")
                        .font(.system(.caption2,
                                      design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.62))
                        .shadow(color: .black.opacity(0.9),
                                radius: 4, x: 0, y: 1)
                }
                .padding(.top, 22)
                Spacer()
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(0..<min(shown, lines.count),
                                id: \.self) { i in
                            lineView(lines[i])
                        }
                        Text("▊")
                            .font(.system(.footnote,
                                          design: .monospaced))
                            .foregroundStyle(color(.ok))
                            .shadow(color: color(.ok).opacity(0.7),
                                    radius: 6)
                            .opacity(cursorOn ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .frame(height: 172, alignment: .topLeading)
                    loadingBar
                        .padding(.top, 16)
                    Text("TAP TO SKIP")
                        .font(.system(.caption2,
                                      design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.45))
                        .shadow(color: .black.opacity(0.9),
                                radius: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .task {
            let blink = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    cursorOn.toggle()
                }
            }
            for _ in lines.indices {
                try? await Task.sleep(
                    nanoseconds: UInt64.random(in: 110_000_000...210_000_000))
                if Task.isCancelled { blink.cancel(); return }
                shown += 1
                Haptics.tick()
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
            blink.cancel()
            if Task.isCancelled { return }
            Haptics.success()
            onDone()
        }
    }
}

/// One place for every buzz, so buttons *feel* like they did something.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The boot sequence's per-line keystroke.
    static func tick() {
        UIImpactFeedbackGenerator(style: .rigid)
            .impactOccurred(intensity: 0.3)
    }

    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}


// MARK: Centipede release splash

extension UIImage {
    /// Decode an animated GIF's frames and delays the ImageIO
    /// way, so a bundled .gif plays as authored.
    static func animatedGIF(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(
                source, i, nil) else { continue }
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
            frames.append(UIImage(cgImage: cg))
        }
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: total)
    }
}

/// A full-bleed GIF player (UIImageView under the hood).
struct GIFPlayerView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .black
        if let image = UIImage.animatedGIF(data: data) {
            view.image = image
            view.startAnimating()
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {}
}

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
        guard let data = gifData,
              let image = UIImage.animatedGIF(data: data)
        else { return 3.0 }
        return min(max(image.duration + 0.3, 1.5), 6.0)
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
