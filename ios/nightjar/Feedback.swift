import CoreBluetooth
import ImageIO
import PDFKit
import SwiftUI
import UIKit
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
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
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
        onProgress?("Asking the open indexes…")

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
            onProgress?("Searching the lite index…")
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
                ?? "no description"
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
        onProgress?("Reading "
                    + (result.url.host ?? "a page") + "…")
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
            if extracted.count >= 600 {
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
                onProgress?("Rendering "
                    + (result.url.host ?? "the page")
                    + " in her browser…")
                SkelliWebRenderer.shared.render(
                    url: result.url) { rendered in
                    if let rendered = rendered,
                       rendered.count > extracted.count {
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
                    } else if extracted.count >= 200 {
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
        var blocks: [String] = []
        if let scout = scout {
            blocks.append(block(scout))
        }
        for page in pages.sorted(by: {
            $0.score > $1.score
        }) {
            if page.score <= 0 { continue }
            if blocks.count >= 3 { break }
            blocks.append(block(page))
        }
        if !blocks.isEmpty {
            var out = blocks.joined(
                separator: "\n\n")
            if walls > 0 {
                out += "\n\n(" + "\(walls) behind a "
                    + "wall — walked past.)"
            }
            return out
        }
        if let instant = instant {
            var lines = ["From the web — "
                         + instant.source + ":",
                         excerpt(instant.text),
                         "Source: " + instant.url]
            if let wiki = wiki, wiki.url != instant.url {
                lines.append("Also: " + wiki.source
                             + " — " + wiki.url)
            }
            return lines.joined(separator: "\n")
        }
        if let wiki = wiki {
            return "From the web — " + wiki.source + ":\n"
                + excerpt(wiki.text)
                + "\nSource: " + wiki.url
        }
        var failure = "Nothing solid came back for '"
            + query + "'."
        if walls > 0 {
            failure += " " + "\(walls) behind a wall."
        }
        failure += " Name it more plainly and I'll "
            + "go again."
        return failure
    }

    private static func block(_ finding: Finding)
        -> String {
        "— " + finding.source + ": " + finding.text
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
        if let spoken = remainder(q, raw: raw, stems: [
            "repeat after me", "respond with",
            "answer with", "repeat", "echo", "print",
            "say", "type"]) {
            say(spoken.isEmpty
                ? "Say what? Give me the words."
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
            say("\(count) letter"
                + (count == 1 ? "." : "s."))
            return true
        }
        if q.contains("how many words") {
            guard let subject = afterIn(q, raw: raw)
            else { return false }
            let count = subject.split(whereSeparator: {
                $0 == " " || $0 == "\n" }).count
            say("\(count) word"
                + (count == 1 ? "." : "s."))
            return true
        }
        if q.contains("what time")
            || q.contains("current time") {
            say("It's " + Date().formatted(
                date: .omitted, time: .shortened) + ".")
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
            say("Hello.")
            return true
        }
        if ["what's up", "whats up", "what is up",
            "sup", "how's it going", "hows it going",
            "how are things", "how is it going",
            "how goes it"].contains(clean) {
            let wire = NeighborhoodStore.shared
                .neighbors.count
            say("All quiet — \(wire) on the wire, web "
                + (webResearchEnabled ? "on" : "off")
                + ".")
            return true
        }
        if clean.hasPrefix("good morning") {
            say("Morning.")
            return true
        }
        if clean.hasPrefix("good afternoon") {
            say("Afternoon.")
            return true
        }
        if clean.hasPrefix("good evening") {
            say("Evening.")
            return true
        }
        if ["bye", "goodbye", "good night",
            "goodnight", "see you", "see ya", "cya",
            "later", "gn"].contains(clean) {
            say(clean.contains("night")
                ? "Night." : "Later.")
            return true
        }
        if ["ok", "okay", "k", "got it", "cool",
            "nice", "great", "perfect", "awesome",
            "sweet", "understood", "roger",
            "copy that", "sounds good", "good",
            "right", "indeed", "exactly", "yes",
            "yeah", "yep"].contains(clean) {
            say("Noted.")
            return true
        }
        if clean == "sorry" || clean == "my bad"
            || clean == "apologies"
            || clean.hasPrefix("sorry ") {
            say("Nothing to forgive.")
            return true
        }
        if ["lol", "haha", "lmao", "heh"]
            .contains(squeezed(clean)) {
            say("Heh.")
            return true
        }
        if q.contains("thank") {
            say("Any time.")
            return true
        }
        if q.contains("how are you") {
            say("Running clean. You?")
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

    init() {
        selectedID = UserDefaults.standard.string(
            forKey: "skelli.weightsModel")
        downloaded = Set(UserDefaults.standard
            .stringArray(
                forKey: "skelli.weightsDownloaded")
            ?? [])
    }

    /// The bench this phone should carry, judged
    /// by the memory it has to carry it in.
    var recommended: WeightsOption {
        let gb = Double(ProcessInfo.processInfo
            .physicalMemory) / 1_073_741_824
        if gb >= 7.5 { return Self.catalog[0] }
        if gb >= 5 { return Self.catalog[2] }
        return Self.catalog[4]
    }

    var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory)
            / 1_073_741_824
    }

    func download(_ option: WeightsOption) {
        #if canImport(MLXLLM)
        if #available(iOS 17.0, *) {
            guard progress[option.id] == nil
            else { return }
            states[option.id] = "Downloading…"
            progress[option.id] = 0
            Task {
                do {
                    let config = ModelConfiguration(
                        id: option.id)
                    _ = try await LLMModelFactory
                        .shared.loadContainer(
                            from: #hubDownloader(),
                            using:
                                #huggingFaceTokenizerLoader(),
                            configuration: config) { p in
                        DispatchQueue.main.async {
                            self.progress[option.id] =
                                p.fractionCompleted
                        }
                    }
                    await MainActor.run {
                        self.progress[option.id] = nil
                        self.downloaded.insert(option.id)
                        self.selectedID = option.id
                        self.states[option.id] = "Ready."
                    }
                } catch {
                    await MainActor.run {
                        self.progress[option.id] = nil
                        self.states[option.id] =
                            "Failed — check the "
                            + "connection and try again."
                    }
                }
            }
        } else {
            states[option.id] = "The bench needs "
                + "iOS 17 or later."
        }
        #else
        states[option.id] = "The bench isn't in "
            + "this build."
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

    var body: some View {
        NavigationStack {
            List {
                if !SkelliMind.benchBuiltIn {
                    Section {
                        Text("The weights bench isn't "
                            + "in this build — the MLX "
                            + "package (mlx-swift-lm) "
                            + "isn't linked into the "
                            + "target yet. Once it is, "
                            + "her models live here: "
                            + "picked, downloaded, and "
                            + "run without ever leaving "
                            + "the app.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("This phone carries "
                            + String(format: "%.0f",
                                     center.memoryGB)
                            + " GB — her bench should "
                            + "be the "
                            + center.recommended.name
                            + ".")
                            .font(.callout)
                        if !center.downloaded.contains(
                            center.recommended.id) {
                            Button("Download the "
                                + center.recommended.name) {
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
                    Section {
                        Text("Downloads come from the "
                            + "Hugging Face hub and "
                            + "live in the app's own "
                            + "cache. After that the "
                            + "model never leaves the "
                            + "phone, and nothing is "
                            + "sent back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
            Text(option.note)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f GB · ",
                        option.sizeGB) + option.id)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value = center.progress[option.id] {
                ProgressView(value: value)
            } else if let state = center
                .states[option.id] {
                Text(state)
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
