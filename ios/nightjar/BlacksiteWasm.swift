import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import WebKit

// BlacksiteWasm — the WebAssembly
// substrate: where a compiled program
// becomes a kernel process.
//
// A .wasm guest believes it is a Linux
// process. Its whole world is staged by
// the kernel before it wakes: argv, the
// environment, stdin, and the filesystem
// as a capability grant — the tree it
// may see, nothing else. Its syscalls
// (WASI preview1) are answered by a shim
// in its own page, and the shim's only
// door out is a message handler here,
// where the kernel's law is applied a
// second time on the way back: output
// is counted against the process's
// quota, writes land in the house files
// (and /bin refuses them, as it refuses
// everyone's), and the process ends
// when the guest calls proc_exit or
// when the kernel's kill switch fires.
//
// The guest runs in a Web Worker inside
// its page when the engine allows, so a
// kill terminates it mid-loop — the
// scheduler's word, enforced. When a
// worker cannot be had it runs on the
// page itself, like the house's other
// web engine, and a kill navigates the
// page away. Each machine gets its own
// web content process pool, its own
// freshly staged memory, and a temp
// room that is swept when it exits:
// isolation by construction, not by
// promise.

final class BlacksiteWasm: NSObject {
    /// The linux userspace's applets —
    /// names the shell resolves to the
    /// bundled linuxbox binary.
    static let applets: [String] = [
        "ls", "cat", "echo", "pwd", "wc",
        "head", "tail", "true", "false",
        "env", "cp", "mv", "rm", "mkdir",
        "touch", "uname", "grep", "sleep",
        "sort", "uniq", "cut", "tr", "rev",
        "tac", "nl", "basename", "dirname",
        "date", "rmdir", "test", "[",
        "seq", "yes", "printf", "clear",
        "whoami",
    ]

    static func isApplet(_ name: String)
        -> Bool {
        applets.contains(name)
            || name == "linuxbox"
    }

    /// A bundled fixture guest (the
    /// diagnose battery's looper and
    /// hog), decoded from its base64
    /// beside the userspace.
    static func fixtureData(
        _ base: String) -> Data? {
        guard let url = Bundle.main.url(
                forResource: base,
                withExtension: "wasm.b64"),
              let text = try? String(
                contentsOf: url,
                encoding: .utf8)
        else { return nil }
        return Data(
            base64Encoded: text,
            options: [
                .ignoreUnknownCharacters
            ])
    }

    private static var cachedLinuxbox: Data?

    /// The bundled linux userspace,
    /// decoded once per launch of the
    /// app.
    static func linuxboxData() -> Data? {
        if let cached = cachedLinuxbox {
            return cached
        }
        guard let url = Bundle.main.url(
                forResource: "linuxbox.wasm",
                withExtension: "b64"),
              let text = try? String(
                contentsOf: url,
                encoding: .utf8),
              let data = Data(
                base64Encoded: text,
                options: [
                    .ignoreUnknownCharacters
                ])
        else { return nil }
        cachedLinuxbox = data
        return data
    }

    private let proc: KernelProcess
    private let emitLine: BlacksiteEmit
    private let completion: (Int) -> Void
    private var webView: WKWebView?
    private var room: URL?
    private var finished = false
    private var heardAnything = false
    private var bootTimer: Timer?
    private var outTail = ""
    private var errTail = ""

    init(proc: KernelProcess,
         emit: @escaping BlacksiteEmit,
         completion: @escaping (Int)
            -> Void) {
        self.proc = proc
        self.emitLine = emit
        self.completion = completion
        super.init()
    }

    // MARK: Launch

    func launch(data: Data, argv: [String],
                env: [String: String],
                cwd: String, stdin: String) {
        DispatchQueue.main.async {
            [weak self] in
            self?.start(data: data,
                        argv: argv, env: env,
                        cwd: cwd, stdin: stdin)
        }
    }

    private func start(data: Data,
                       argv: [String],
                       env: [String: String],
                       cwd: String,
                       stdin: String) {
        guard let room = makeRoom(
                data: data, argv: argv,
                env: env, cwd: cwd,
                stdin: stdin)
        else {
            emitLine("wasm: the guest's "
                     + "room could not be "
                     + "staged.", .err)
            completion(127)
            return
        }
        self.room = room
        let config = WKWebViewConfiguration()
        config.processPool = WKProcessPool()
        config.websiteDataStore =
            .nonPersistent()
        config.setURLSchemeHandler(
            self,
            forURLScheme: "blacksite-wasm")
        config.userContentController.add(
            self, name: "wasi")
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0,
                          width: 2, height: 2),
            configuration: config)
        view.isUserInteractionEnabled =
            false
        attach(view)
        webView = view
        proc.killSwitch.install {
            [weak self] in
            self?.terminate()
        }
        bootTimer = Timer.scheduledTimer(
            withTimeInterval: 20,
            repeats: false) { [weak self] _ in
            guard let self = self,
                  !self.heardAnything,
                  !self.finished else { return }
            self.emitLine(
                "wasm: the host never "
                + "answered — the guest "
                + "did not start.", .err)
            self.finish(127)
        }
        view.load(URLRequest(
            url: URL(string:
                "blacksite-wasm://guest/"
                + "wasi-host.html")!))
    }

    /// Set the engine in a corner of the
    /// key window, invisible and
    /// untouchable: a web view with a
    /// window behind it runs its guest
    /// at full speed, and one without
    /// may be throttled by the system.
    private func attach(_ view: WKWebView) {
        view.alpha = 0.02
        let scenes = UIApplication.shared
            .connectedScenes
            .compactMap {
                $0 as? UIWindowScene
            }
        let window = scenes.flatMap {
            $0.windows
        }.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }
                .first
        window?.addSubview(view)
    }

    // MARK: The staged room

    /// Stage the guest's world in a temp
    /// room: its binary, the host page
    /// and shim from the bundle, and
    /// stage.json — argv, environment,
    /// stdin, and the filesystem as the
    /// kernel grants it. Contents are
    /// granted until a size budget runs
    /// out (the working subtree first);
    /// a file whose contents were not
    /// granted reads as an honest I/O
    /// error in the guest, never as
    /// somebody else's bytes.
    private func makeRoom(
        data: Data, argv: [String],
        env: [String: String], cwd: String,
        stdin: String) -> URL? {
        let fm = FileManager.default
        let room = fm.temporaryDirectory
            .appendingPathComponent(
                "blacksite-wasm-\(proc.pid)",
                isDirectory: true)
        try? fm.removeItem(at: room)
        do {
            try fm.createDirectory(
                at: room,
                withIntermediateDirectories:
                    true)
            try data.write(
                to: room.appendingPathComponent(
                    "guest.wasm"))
            for (base, ext) in [
                ("wasi-host", "html"),
                ("wasi-shim", "js"),
            ] {
                guard let src = Bundle.main
                    .url(forResource: base,
                         withExtension: ext)
                else { return nil }
                try fm.copyItem(
                    at: src,
                    to: room
                        .appendingPathComponent(
                            base + "." + ext))
            }
            let staged = stageFiles(cwd: cwd)
            let stage: [String: Any] = [
                "argv": argv,
                "env": env,
                "cwd": cwd,
                "stdin": stdin,
                "files": staged.files,
            ]
            if !staged.unstaged.isEmpty {
                let named = staged.unstaged
                    .prefix(4).map {
                        "\($0.0) (\($0.1) B)"
                    }
                    .joined(separator: ", ")
                emitLine(
                    "wasm: \(staged.unstaged.count) "
                        + "file(s) did not fit "
                        + "the 32 MB staging grant "
                        + "read as I/O errors "
                        + "in the guest: "
                        + named,
                    .err)
            }
            let json = try JSONSerialization
                .data(withJSONObject: stage)
            try json.write(
                to: room.appendingPathComponent(
                    "stage.json"))
            return room
        } catch {
            return nil
        }
    }

    private func stageFiles(
        cwd: String)
        -> (files: [String: Any],
            unstaged: [(String, Int)]) {
        var entries: [(String, Bool)] = []
        func walk(_ path: String) {
            guard let listed = BlacksiteFS
                .list(path) else { return }
            for entry in listed {
                let child = path == "/"
                    ? "/" + entry.name
                    : path + "/" + entry.name
                entries.append(
                    (child, entry.isDir))
                if entry.isDir {
                    walk(child)
                }
            }
        }
        walk("/")
        // The working subtree is granted
        // first; the rest of the tree
        // after it, until the budget is
        // spent.
        entries.sort { a, b in
            let aHome = a.0 == cwd
                || a.0.hasPrefix(cwd + "/")
            let bHome = b.0 == cwd
                || b.0.hasPrefix(cwd + "/")
            if aHome != bHome { return aHome }
            return a.0 < b.0
        }
        var budget = 32 * 1024 * 1024
        var unstaged: [(String, Int)] = []
        var files: [String: Any] = [:]
        for (path, isDir) in entries {
            if isDir {
                files[path] = ["d": 1]
                continue
            }
            if path.hasPrefix("/bin/") {
                files[path] = [
                    "stagedEmpty": true
                ]
                continue
            }
            let size = BlacksiteFS
                .fileSize(path) ?? 0
            if size <= budget,
               let bytes = BlacksiteFS
                .readData(path) {
                budget -= size
                files[path] = [
                    "b64": bytes
                        .base64EncodedString()
                ]
            } else {
                // Over the grant, or
                // the grant ran out
                // first: either way the
                // operator hears the
                // name.
                unstaged.append((path, size))
                files[path] = [
                    "stagedEmpty": true
                ]
            }
        }
        return (files, unstaged)
    }

    // MARK: Ending

    /// The kernel has spoken: terminate
    /// the worker if there is one, tear
    /// the page down, and close the
    /// books at 137 — 128 and SIGKILL,
    /// the way a shell tells it.
    private func terminate() {
        DispatchQueue.main.async {
            [weak self] in
            guard let self = self,
                  !self.finished else {
                return
            }
            self.webView?
                .evaluateJavaScript(
                    "window.__killGuest"
                    + " && window"
                    + ".__killGuest()")
            self.finish(137)
        }
    }

    private func finish(_ code: Int) {
        guard !finished else { return }
        finished = true
        bootTimer?.invalidate()
        if !outTail.isEmpty {
            emitLine(outTail, .out)
            outTail = ""
        }
        if !errTail.isEmpty {
            emitLine(errTail, .err)
            errTail = ""
        }
        webView?.configuration
            .userContentController
            .removeScriptMessageHandler(
                forName: "wasi")
        webView?.removeFromSuperview()
        webView = nil
        if let room = room {
            try? FileManager.default
                .removeItem(at: room)
            self.room = nil
        }
        completion(code)
    }

    // MARK: Guest messages

    private func drain(_ text: String,
                       fd: Int) {
        if fd == 2 {
            errTail += text
            while let cut = errTail
                .firstIndex(of: "\n") {
                let line = String(
                    errTail[..<cut])
                errTail = String(errTail[
                    errTail.index(after: cut)...])
                emitLine(line, .err)
            }
        } else {
            outTail += text
            while let cut = outTail
                .firstIndex(of: "\n") {
                let line = String(
                    outTail[..<cut])
                outTail = String(outTail[
                    outTail.index(after: cut)...])
                emitLine(line, .out)
            }
        }
    }

    private func handle(_ body: [String: Any]) {
        heardAnything = true
        guard let kind = body["t"] as? String
        else { return }
        switch kind {
        case "out":
            let fd = body["fd"] as? Int ?? 1
            let text = body["s"] as? String
                ?? ""
            drain(text, fd: fd)
        case "write":
            guard let path = body["path"]
                    as? String,
                  let b64 = body["b64"]
                    as? String,
                  let bytes = Data(
                    base64Encoded: b64)
            else { return }
            _ = BlacksiteFS.writeData(
                path, data: bytes)
        case "mkdir":
            if let path = body["path"]
                as? String {
                _ = BlacksiteFS.makeDir(path)
            }
        case "unlink", "rmdir":
            if let path = body["path"]
                as? String {
                _ = BlacksiteFS.remove(path)
            }
        case "rename":
            if let from = body["from"]
                as? String,
               let to = body["to"]
                as? String {
                _ = BlacksiteFS.move(
                    from: from, to: to)
            }
        case "exit":
            finish(body["code"] as? Int ?? 0)
        default:
            break
        }
    }
}

// MARK: - The wire

extension BlacksiteWasm:
    WKScriptMessageHandler {
    func userContentController(
        _ controller:
            WKUserContentController,
        didReceive message: WKScriptMessage) {
        guard let body = message.body
                as? [String: Any]
        else { return }
        handle(body)
    }
}

extension BlacksiteWasm:
    WKURLSchemeHandler {
    func webView(_ webView: WKWebView,
                 start task:
                    WKURLSchemeTask) {
        guard let room = room,
              let url = task.request.url
        else {
            task.didFailWithError(
                NSError(domain: "wasm",
                        code: 404))
            return
        }
        let file = room
            .appendingPathComponent(
                url.lastPathComponent)
        guard let data = try? Data(
                contentsOf: file)
        else {
            task.didFailWithError(
                NSError(domain: "wasm",
                        code: 404))
            return
        }
        let mime: String
        switch url.pathExtension {
        case "html": mime = "text/html"
        case "js":
            mime = "text/javascript"
        case "json":
            mime = "application/json"
        case "wasm":
            mime = "application/wasm"
        default:
            mime = "application/octet-stream"
        }
        task.didReceive(URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength:
                data.count,
            textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView,
                 stop task:
                    WKURLSchemeTask) {}
}
