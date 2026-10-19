import SwiftUI
import WebKit

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
}

@MainActor
final class FreedoomLoader:
    NSObject, ObservableObject {

    enum Phase {
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
        else { return nil }
        cached = plain
        return plain
    }
}

// MARK: - The web view

struct FreedoomWebView:
    UIViewRepresentable {

    final class Coordinator: NSObject,
        WKNavigationDelegate {
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
        context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            FreedoomSchemeHandler(),
            forURLScheme:
                FreedoomSchemeHandler.scheme)
        config.websiteDataStore =
            .nonPersistent()
        config.allowsInlineMediaPlayback =
            true
        let view = WKWebView(
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
        return view
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context) {}
}

// MARK: - The room

struct FreedoomView: View {
    @StateObject private var loader =
        FreedoomLoader()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch loader.phase {
            case .ready:
                FreedoomWebView()
            default:
                lobby
            }
        }
        .onAppear { loader.refresh() }
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
            EmptyView()
        }
    }
}
