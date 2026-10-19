import SwiftUI
import WebKit
import GameController

// Freedoom — the big demo. Chocolate Doom
// compiled to WebAssembly (cloudflare/
// doom-wasm, GPL-2.0), running Freedoom
// Phase 1 (0.13.0, BSD-3-Clause) in a
// WKWebView room. The engine ships in
// the bundle; the game data does not —
// on first open the room downloads
// Freedoom's official release zip,
// takes freedoom1.wad out of it with
// the house zip reader (CRC-checked),
// and caches it in Application Support.
// After that it plays offline, forever,
// under any EMCON condition. The fetch
// itself answers to the Standard as an
// update check: above Open, it refuses.

enum FreedoomStore {
    static let releaseZipURL = URL(
        string: "https://github.com/"
            + "freedoom/freedoom/releases/"
            + "download/v0.13.0/"
            + "freedoom-0.13.0.zip")!
    static let zipEntryName =
        "freedoom-0.13.0/freedoom1.wad"
    static let wadBytes = 28_795_076

    static var cacheDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory,
                  in: .userDomainMask)[0]
        return base.appendingPathComponent(
            "Freedoom", isDirectory: true)
    }

    static var wadURL: URL {
        cacheDirectory.appendingPathComponent(
            "doom1.wad")
    }

    static var wadCached: Bool {
        let path = wadURL.path
        guard FileManager.default
            .fileExists(atPath: path),
              let attrs = try? FileManager
                .default.attributesOfItem(
                    atPath: path),
              let size = attrs[.size]
                as? NSNumber
        else { return false }
        return size.intValue == wadBytes
    }

    /// The lobby's uninstall: the whole
    /// cache folder goes — the WAD and
    /// anything the room filed with it.
    /// The engine stays in the app.
    static func uninstall() {
        try? FileManager.default.removeItem(
            at: cacheDirectory)
    }
}

@MainActor
final class FreedoomLoader:
    NSObject, ObservableObject {

    enum Phase: Equatable {
        case checking
        case needsDownload
        case refusedByStandard
        case downloading(Double)
        case unpacking
        case ready
        case failed(String)
    }

    @Published var phase: Phase = .checking

    private var session: URLSession?
    private var task: URLSessionDownloadTask?

    func refresh() {
        phase = FreedoomStore.wadCached
            ? .ready : .needsDownload
    }

    func beginDownload() {
        if FreedoomStore.wadCached {
            phase = .ready
            return
        }
        if EmconStandard.refused(.updateCheck) {
            phase = .refusedByStandard
            return
        }
        phase = .downloading(0)
        let config = URLSessionConfiguration
            .default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(
            with: FreedoomStore.releaseZipURL)
        self.task = task
        task.resume()
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        phase = .needsDownload
    }

    fileprivate func downloadFinished(
        at tempURL: URL) {
        phase = .unpacking
        let target = FreedoomStore.wadURL
        Task.detached(priority: .userInitiated) {
            let zipData: Data
            do {
                zipData = try Data(
                    contentsOf: tempURL)
            } catch {
                await self.fail(
                    "the download could not "
                    + "be read back.")
                return
            }
            do {
                let wad = try FreedoomZip.entry(
                    named: FreedoomStore
                        .zipEntryName,
                    in: zipData)
                try FileManager.default
                    .createDirectory(
                        at: FreedoomStore
                            .cacheDirectory,
                        withIntermediateDirectories:
                            true)
                try wad.write(
                    to: target,
                    options: .atomic)
            } catch let error
                        as FreedoomZipError {
                await self.fail(Self.describe(
                    error))
                return
            } catch {
                await self.fail(
                    "the game data could not "
                    + "be filed away.")
                return
            }
            await self.downloadDone()
        }
    }

    fileprivate func downloadDone() {
        session?.finishTasksAndInvalidate()
        session = nil
        phase = .ready
    }

    fileprivate func fail(_ message: String) {
        session?.invalidateAndCancel()
        session = nil
        phase = .failed(message)
    }

    private static func describe(
        _ error: FreedoomZipError) -> String {
        switch error {
        case .notAZip:
            return "what arrived is not "
                + "the release zip."
        case .entryMissing:
            return "the release zip holds "
                + "no freedoom1.wad."
        case .unsupportedMethod(let method):
            return "the zip uses a packing "
                + "this house does not read "
                + "(method \(method))."
        case .corrupt(let whereabouts):
            return "the archive is corrupt "
                + "at its \(whereabouts)."
        case .sizeMismatch:
            return "the game data unpacked "
                + "to the wrong size."
        case .crcMismatch:
            return "the game data failed "
                + "its CRC check — it is "
                + "not the archive's own "
                + "bytes."
        }
    }
}

extension FreedoomLoader:
    URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL) {
        // The temp file dies when this
        // call returns; move it first.
        let staging = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "freedoom-release.zip")
        try? FileManager.default
            .removeItem(at: staging)
        do {
            try FileManager.default.moveItem(
                at: location, to: staging)
        } catch {
            Task { @MainActor in
                self.fail(
                    "the download could not "
                    + "be staged.")
            }
            return
        }
        Task { @MainActor in
            self.downloadFinished(at: staging)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0
        else { return }
        let fraction = Double(
            totalBytesWritten)
            / Double(
                totalBytesExpectedToWrite)
        Task { @MainActor in
            if case .downloading = self.phase {
                self.phase = .downloading(
                    fraction)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError
            error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled {
            return
        }
        Task { @MainActor in
            self.fail(
                "the download failed — "
                + "check the connection "
                + "and try again.")
        }
    }
}

// MARK: - The scheme handler

/// Serves the room's world: the engine
/// files from the bundle, the game data
/// from the cache, nothing from anywhere
/// else. A custom scheme is what lets
/// the .wasm arrive with its proper
/// application/wasm type — WebKit
/// refuses to compile wasm fetched any
/// other local way.
final class FreedoomSchemeHandler:
    NSObject, WKURLSchemeHandler {

    static let scheme = "nightjar-doom"

    private static let mimeTypes = [
        "html": "text/html",
        "js": "text/javascript",
        "wasm": "application/wasm",
        "cfg": "text/plain",
        "wad": "application/octet-stream",
    ]

    func webView(_ webView: WKWebView,
                 start urlSchemeTask:
                    WKURLSchemeTask) {
        guard let url = urlSchemeTask
            .request.url else {
            urlSchemeTask.didFailWithError(
                FreedoomWebError.badRequest)
            return
        }
        let name = url.lastPathComponent
        FreedoomTrail.shared.log(
            "GET " + name)
        if name == "doom1.wad" {
            serveFile(
                FreedoomStore.wadURL,
                name: name, requestURL: url,
                task: urlSchemeTask)
            return
        }
        if name == "websockets-doom.wasm" {
            if let direct = Bundle.main.url(
                forResource: name,
                withExtension: nil) {
                serveFile(
                    direct, name: name,
                    requestURL: url,
                    task: urlSchemeTask)
            } else if let decoded =
                        FreedoomEngineBytes
                            .wasm() {
                serveData(
                    decoded, name: name,
                    requestURL: url,
                    task: urlSchemeTask)
            } else {
                urlSchemeTask
                    .didFailWithError(
                        FreedoomWebError
                            .notFound)
            }
            return
        }
        guard let bundleURL = Bundle.main
            .url(forResource: name,
                 withExtension: nil)
        else {
            urlSchemeTask.didFailWithError(
                FreedoomWebError.notFound)
            return
        }
        serveFile(bundleURL, name: name,
                  requestURL: url,
                  task: urlSchemeTask)
    }

    func webView(_ webView: WKWebView,
                 stop urlSchemeTask:
                    WKURLSchemeTask) {
        // Chunked reads finish inside one
        // call; nothing to unwind.
    }

    private func serveData(
        _ data: Data, name: String,
        requestURL: URL,
        task: WKURLSchemeTask) {
        let ext = (name as NSString)
            .pathExtension.lowercased()
        let mime = Self.mimeTypes[ext]
            ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length":
                    "\(data.count)",
                "Cache-Control": "no-store",
                "Access-Control-Allow-Origin":
                    "*",
            ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
        FreedoomTrail.shared.log(
            "SENT " + name + " "
            + "\(data.count)")
    }

    private func serveFile(
        _ fileURL: URL, name: String,
        requestURL: URL,
        task: WKURLSchemeTask) {
        guard let handle = try? FileHandle(
            forReadingFrom: fileURL),
              let attrs = try? FileManager
                .default.attributesOfItem(
                    atPath: fileURL.path),
              let size = attrs[.size]
                as? NSNumber
        else {
            task.didFailWithError(
                FreedoomWebError.notFound)
            return
        }
        defer { try? handle.close() }
        let ext = (name as NSString)
            .pathExtension.lowercased()
        let mime = Self.mimeTypes[ext]
            ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length":
                    "\(size.intValue)",
                "Cache-Control": "no-store",
                "Access-Control-Allow-Origin":
                    "*",
            ])!
        task.didReceive(response)
        while true {
            let chunk = handle
                .readData(ofLength: 262_144)
            if chunk.isEmpty { break }
            task.didReceive(chunk)
        }
        task.didFinish()
        FreedoomTrail.shared.log(
            "SENT " + name + " "
            + "\(size.intValue)")
    }
}

enum FreedoomWebError: Error {
    case badRequest
    case notFound
}

/// The engine's wasm, recovered from
/// the bundle's text chunks: base64
/// letters (.b64a, .b64b, …) holding a
/// gzipped module — the repo's write
/// doors are text-only, so the binary
/// travels encoded and is decoded once,
/// here, then kept.
enum FreedoomEngineBytes {
    private static var cached: Data?

    static func wasm() -> Data? {
        if let cached { return cached }
        let decodeStart =
            CFAbsoluteTimeGetCurrent()
        FreedoomTrail.shared.log(
            "engine decode begin")
        var encoded = ""
        let letters = "abcdefghijklmnopqrstuvwxyz"
        for letter in letters {
            let chunkName =
                "websockets-doom.wasm.b64"
                + String(letter)
            guard let url = Bundle.main.url(
                forResource: chunkName,
                withExtension: nil),
                  let text = try? String(
                    contentsOf: url,
                    encoding: .utf8)
            else { break }
            encoded += text
        }
        guard !encoded.isEmpty,
              let packed = Data(
                base64Encoded: encoded),
              let plain = try? FreedoomZip
                .gunzip(packed)
        else {
            FreedoomTrail.shared.log(
                "engine decode FAILED")
            return nil
        }
        cached = plain
        FreedoomTrail.shared.log(
            "engine decode done "
            + String(format: "%.1fs",
                     CFAbsoluteTimeGetCurrent()
                        - decodeStart))
        return plain
    }
}

// MARK: - The room's flight recorder

/// Every step the room takes lands
/// here: requests the scheme handler
/// serves, the engine decode's timing,
/// and milestones the page itself posts
/// over the script bridge. Painted
/// under the room, so a room that dies
/// says where it died.
final class FreedoomTrail:
    ObservableObject {
    static let shared = FreedoomTrail()
    @Published private(set) var lines:
        [String] = []
    private let born =
        CFAbsoluteTimeGetCurrent()

    func log(_ text: String) {
        let stamp = String(
            format: "%.1f",
            CFAbsoluteTimeGetCurrent()
                - born)
        DispatchQueue.main.async {
            self.lines.append(
                stamp + " " + text)
            if self.lines.count > 300 {
                self.lines.removeFirst(
                    self.lines.count - 300)
            }
            DevLog.event("doom",
                         stamp + " " + text)
        }
    }
}

// MARK: - The web view

/// A web view that hears a hardware
/// keyboard itself. Focusing the canvas
/// inside the page is not enough for
/// WebKit to hand a game page real key
/// presses — the UIKit first responder
/// chain is the door — so the view takes
/// first responder and translates each
/// press into the page's own deck call
/// (window.sendkey, the exact path the
/// touch deck proves), HID usage codes
/// in, DOM key codes out. Mapped presses
/// are consumed here and never passed
/// on, so a key can never land twice.
final class FreedoomKeyWebView: WKWebView {

    override var canBecomeFirstResponder:
        Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }

    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        if FreedoomKeyboardRouter.shared
            .active { return }
        forward(presses, down: true) {
            super.pressesBegan(
                $0, with: event)
        }
    }

    override func pressesEnded(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        if FreedoomKeyboardRouter.shared
            .active { return }
        forward(presses, down: false) {
            super.pressesEnded(
                $0, with: event)
        }
    }

    override func pressesCancelled(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        if FreedoomKeyboardRouter.shared
            .active { return }
        forward(presses, down: false) {
            super.pressesCancelled(
                $0, with: event)
        }
    }

    private func forward(
        _ presses: Set<UIPress>,
        down: Bool,
        unhandled: (Set<UIPress>) -> Void) {
        var rest: Set<UIPress> = []
        for press in presses {
            if let code = Self.domCode(
                for: press) {
                let type = down
                    ? "keydown" : "keyup"
                evaluateJavaScript(
                    "window.sendkey && "
                    + "window.sendkey(["
                    + String(code) + "], \""
                    + type + "\")",
                    completionHandler: nil)
            } else {
                rest.insert(press)
            }
        }
        if !rest.isEmpty {
            unhandled(rest)
        }
    }

    static func domCode(
        for press: UIPress) -> Int? {
        guard let key = press.key
        else { return nil }
        switch key.keyCode {
        case .keyboardUpArrow: return 38
        case .keyboardDownArrow: return 40
        case .keyboardLeftArrow: return 37
        case .keyboardRightArrow: return 39
        case .keyboardEscape: return 27
        case .keyboardTab: return 9
        case .keyboardReturnOrEnter:
            return 13
        case .keyboardSpacebar: return 32
        case .keyboardLeftShift,
             .keyboardRightShift: return 16
        case .keyboardLeftControl,
             .keyboardRightControl: return 17
        case .keyboardLeftAlt,
             .keyboardRightAlt: return 18
        default:
            // Letters and digits ride the
            // character the key reports
            // with modifiers ignored; its
            // uppercase scalar IS the DOM
            // key code.
            guard let ch = key
                .charactersIgnoringModifiers
                .first,
                  ch.isLetter || ch.isNumber,
                  let scalar = ch.uppercased()
                    .unicodeScalars.first
            else { return nil }
            return Int(scalar.value)
        }
    }

    /// HID usage code in, DOM key code
    /// out — the GameController router's
    /// half of the map. GCKeyCode raw
    /// values are HID usage codes, so
    /// one table serves both paths.
    static func domCode(
        forHID hid: Int) -> Int? {
        switch hid {
        case 82: return 38   // up
        case 81: return 40   // down
        case 80: return 37   // left
        case 79: return 39   // right
        case 41: return 27   // esc
        case 43: return 9    // tab
        case 40: return 13   // enter
        case 44: return 32   // space
        case 42: return 8    // backspace
        case 225, 229: return 16  // shift
        case 224, 228: return 17  // ctrl
        case 226, 230: return 18  // alt
        case 4...29:
            // a-z -> A-Z
            return hid - 4 + 65
        case 30...38:
            // 1-9
            return hid - 30 + 49
        case 39: return 48   // 0
        default: return nil
        }
    }
}

struct FreedoomWebView:
    UIViewRepresentable {

    final class Coordinator: NSObject,
        WKNavigationDelegate,
        WKScriptMessageHandler {

        func userContentController(
            _ userContentController:
                WKUserContentController,
            didReceive message:
                WKScriptMessage) {
            FreedoomTrail.shared.log(
                "page: "
                + (message.body as? String
                    ?? "?"))
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation:
                WKNavigation!) {
            FreedoomTrail.shared.log(
                "nav finished")
        }
        func webView(
            _ webView: WKWebView,
            webContentProcessDidTerminate
                notification: WKWebView) {
            // WebKit kills the content
            // process under memory
            // pressure; the room's answer
            // is to stand back up.
            webView.reload()
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor
                        action:
                        WKNavigationAction,
                     decisionHandler:
                        @escaping (
                            WKNavigationActionPolicy
                        ) -> Void) {
            if action.navigationType
                    == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(
        context: Context)
        -> FreedoomKeyWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            FreedoomSchemeHandler(),
            forURLScheme:
                FreedoomSchemeHandler.scheme)
        config.userContentController.add(
            context.coordinator,
            name: "doom")
        config.websiteDataStore =
            .nonPersistent()
        config.allowsInlineMediaPlayback =
            true
        let view = FreedoomKeyWebView(
            frame: .zero,
            configuration: config)
        view.navigationDelegate =
            context.coordinator
        view.backgroundColor = .black
        view.isOpaque = true
        view.scrollView.isScrollEnabled =
            false
        view.scrollView.bounces = false
        if let page = URL(
            string: FreedoomSchemeHandler
                .scheme + "://room/doom.html"
                + "?launch="
                + UUID().uuidString) {
            // A fresh URL every opening: no
            // cache anywhere in the stack can
            // serve the room a stale page.
            view.load(URLRequest(
                url: page,
                cachePolicy:
                    .reloadIgnoringLocalCacheData))
        }
        FreedoomKeyboardRouter.shared
            .attach(webView: view)
        return view
    }

    static func dismantleUIView(
        _ uiView: FreedoomKeyWebView,
        coordinator: Coordinator) {
        FreedoomKeyboardRouter.shared
            .detach()
    }

    func updateUIView(
        _ uiView: FreedoomKeyWebView,
        context: Context) {}
}

/// Hardware keys at the app level.
/// GameController reports every press
/// of a connected keyboard — wired or
/// Bluetooth — with no first responder,
/// no focus and no WebKit cooperation,
/// which is everything the responder
/// chain cannot promise a game page.
/// While a game is up the router
/// forwards each press into the page
/// as a deck key (window.sendkey, the
/// proven path); the responder path in
/// FreedoomKeyWebView stands down
/// whenever the router is live, so a
/// key can never land twice. It binds
/// on attach and rebinds if a keyboard
/// connects mid-game.
final class FreedoomKeyboardRouter {
    static let shared =
        FreedoomKeyboardRouter()
    private(set) var active = false
    private weak var webView: WKWebView?
    private var input: GCKeyboardInput?
    private var observers:
        [NSObjectProtocol] = []

    func attach(webView: WKWebView) {
        self.webView = webView
        if observers.isEmpty {
            let center =
                NotificationCenter.default
            observers.append(center
                .addObserver(
                    forName:
                        .GCKeyboardDidConnect,
                    object: nil,
                    queue: .main) {
                [weak self] _ in
                self?.bind()
            })
            observers.append(center
                .addObserver(
                    forName:
                        .GCKeyboardDidDisconnect,
                    object: nil,
                    queue: .main) {
                [weak self] _ in
                self?.unbindIfGone()
            })
        }
        bind()
    }

    private func bind() {
        guard let input = GCKeyboard
            .coalesced?.keyboardInput
        else { return }
        self.input = input
        active = true
        input.keyChangedHandler = {
            [weak self] _, _, code,
            pressed in
            self?.forward(
                code: code, pressed: pressed)
        }
    }

    private func unbindIfGone() {
        guard GCKeyboard.coalesced == nil
        else { return }
        input?.keyChangedHandler = nil
        input = nil
        active = false
    }

    func detach() {
        input?.keyChangedHandler = nil
        input = nil
        active = false
        webView = nil
        for observer in observers {
            NotificationCenter.default
                .removeObserver(observer)
        }
        observers = []
    }

    private func forward(
        code: GCKeyCode, pressed: Bool) {
        guard let dom = FreedoomKeyWebView
            .domCode(forHID: code.rawValue)
        else { return }
        let type = pressed
            ? "keydown" : "keyup"
        let js = "window.sendkey && "
            + "window.sendkey(["
            + String(dom) + "], '"
            + type + "')"
        DispatchQueue.main.async {
            [weak self] in
            self?.webView?
                .evaluateJavaScript(
                    js,
                    completionHandler: nil)
        }
    }
}

// MARK: - The room

struct FreedoomView: View {
    @StateObject private var loader =
        FreedoomLoader()
    @State private var inGame = false
    @State private var gameSession = UUID()
    @State private var confirmUninstall =
        false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if inGame {
                FreedoomWebView()
                    .id(gameSession)
            } else {
                lobby
            }
        }
        // A game is played with swipes;
        // a downward drag on the stick
        // must play the game, not drag
        // the room away. Done is the
        // only way out.
        .interactiveDismissDisabled(true)
        .onAppear {
            loader.refresh()
            FreedoomTrail.shared.log(
                "room opened")
        }
        .confirmationDialog(
            "Remove the game data?",
            isPresented: $confirmUninstall) {
            Button("UNINSTALL",
                   role: .destructive) {
                FreedoomStore.uninstall()
                loader.refresh()
            }
            Button("KEEP IT",
                   role: .cancel) {}
        } message: {
            Text("The 28 MB WAD goes. "
                 + "The engine stays in "
                 + "the app — you can "
                 + "download the data "
                 + "again whenever the "
                 + "Standard allows.")
        }
    }

    private var lobby: some View {
        VStack(spacing: 16) {
            Text("FREEDOOM")
                .font(.system(
                    .largeTitle,
                    design: .monospaced)
                    .weight(.bold))
                .foregroundStyle(.red)
                .tracking(4)
            Text("Freedoom Phase 1 · 0.13.0\n"
                 + "Chocolate Doom in "
                 + "WebAssembly.\n"
                 + "The engine is in the "
                 + "app. The game data "
                 + "is not.")
                .font(.system(
                    .caption,
                    design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(
                    .center)
            lobbyState
        }
        .padding(24)
    }

    @ViewBuilder
    private var lobbyState: some View {
        switch loader.phase {
        case .checking:
            ProgressView()
                .tint(.secondary)
        case .needsDownload:
            VStack(spacing: 12) {
                Text("one download: the "
                     + "24 MB release zip "
                     + "from Freedoom's own "
                     + "GitHub, unpacked "
                     + "here to a 28 MB "
                     + "WAD and kept. "
                     + "After that — "
                     + "offline, always.")
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(
                        .secondary)
                    .multilineTextAlignment(
                        .center)
                Button {
                    Haptics.tap()
                    loader.beginDownload()
                } label: {
                    Text("DOWNLOAD FREEDOOM")
                        .font(.system(
                            .body,
                            design: .monospaced)
                            .weight(.bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        case .refusedByStandard:
            VStack(spacing: 12) {
                Text(EmconCondition.current
                        .declared
                     + " refuses the fetch "
                     + "— the Standard "
                     + "counts it an update "
                     + "check, and those "
                     + "stand only at Open. "
                     + "A house that already "
                     + "holds the WAD "
                     + "plays regardless.")
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(
                        .center)
                Button("CHECK AGAIN") {
                    Haptics.tap()
                    loader.beginDownload()
                }
                .font(.system(
                    .caption,
                    design: .monospaced))
            }
        case .downloading(let fraction):
            VStack(spacing: 10) {
                ProgressView(
                    value: fraction)
                    .tint(.red)
                    .frame(maxWidth: 240)
                Text("downloading… "
                     + "\(Int(fraction * 100))%")
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(
                        .secondary)
                Button("CANCEL") {
                    loader.cancelDownload()
                }
                .font(.system(
                    .caption,
                    design: .monospaced))
                .foregroundStyle(.secondary)
            }
        case .unpacking:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.red)
                Text("unpacking the WAD "
                     + "and checking its "
                     + "CRC…")
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(
                        .secondary)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(
                        .center)
                Button("TRY AGAIN") {
                    Haptics.tap()
                    loader.refresh()
                }
                .font(.system(
                    .caption,
                    design: .monospaced))
            }
        case .ready:
            VStack(spacing: 12) {
                Text("the game data is "
                     + "in — 28 MB, "
                     + "CRC-checked, yours "
                     + "offline under any "
                     + "condition.")
                    .font(.system(
                        .caption,
                        design: .monospaced))
                    .foregroundStyle(
                        .secondary)
                    .multilineTextAlignment(
                        .center)
                Button {
                    Haptics.tap()
                    gameSession = UUID()
                    inGame = true
                } label: {
                    Text("PLAY")
                        .font(.system(
                            .body,
                            design: .monospaced)
                            .weight(.bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button("UNINSTALL") {
                    confirmUninstall = true
                }
                .font(.system(
                    .caption,
                    design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }
}
