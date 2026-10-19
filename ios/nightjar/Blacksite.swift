import CryptoKit
import GameController
import SwiftUI
import UIKit

/// BLACKSITE — the house's own operating
/// system, in one room (the operator's order,
/// 2026-10-19: a virtual console, a complete
/// special tab, "basically a virtual
/// operating system with super powers").
///
/// The super powers are not theatre: the
/// shell below drives the house's real organs
/// — the scanner, the recon hand, the
/// decoders, the registries, EMCON, the macro
/// runner, the Gauntlet, the tomato marks,
/// the themes, the haptics switch, and Skelli
/// herself — through a command line, and the
/// program rail opens the live instruments
/// (the process board, the house state, the
/// journal, the Gauntlet, the macro library,
/// the decoder bench) as sheets over the
/// terminal. Every gate that holds anywhere
/// holds here: EMCON refusals refuse, in the
/// Standard's own words.
///
/// The console speaks machine English, like
/// the boot ceremony: a terminal is a
/// terminal in every language setting.
enum Blacksite {
    static let tabTag = 12
    static let openTabNotification =
        Notification.Name("blacksite.openTab")

    static let tabTags: [String: Int] = [
        "skelli": 9, "listen": 0, "send": 1,
        "serve": 2, "about": 5, "sessions": 3,
        "scan": 4, "recon": 6, "emcon": 7,
        "knocktalk": 8, "macros": 10,
        "vault": 11, "blacksite": 12,
    ]
}

// MARK: - The shell

final class BlacksiteShell: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        let image: UIImage?
        enum Kind { case cmd, out, ok, err, sys }
    }

    struct EditorSession: Identifiable {
        let id = UUID()
        let path: String?
        let personality: EditorPersonality
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var busy = false

    /// While a python program sits in
    /// input(), the next line typed is
    /// handed to the program instead of
    /// running as a command.
    private var inputWaiter: ((String) -> Void)?

    private let scanner = ScanModel()
    private let recon = Recon()
    private var history: [String] = []
    private var booted = false

    /// The console's own birth —
    /// fastfetch's uptime counts from
    /// here.
    private let born = Date()

    /// Live wasm machines, held by pid
    /// until their guest exits.
    private var wasmMachines:
        [Int: BlacksiteWasm] = [:]

    /// The working directory, a virtual
    /// path in the console's own file
    /// system.
    private(set) var cwd = "/home"
    /// The shell's environment.
    private var env: [String: String] = [
        "HOME": "/home",
        "PWD": "/home",
        "USER": "operator",
        "EDITOR": "vim",
        "SHELL": "/bin/blacksite",
        "PATH": "/bin:/packages",
    ]
    /// What flowed into the running stage
    /// through a pipe.
    private var stageInput = ""
    /// Output capture stack: while a stage
    /// is captured (a pipe, a redirect, a
    /// $(…) substitution), emit() writes
    /// here instead of the transcript.
    private var captureStack: [[String]] = []
    private var stageError = false
    private(set) var lastStatus = 0

    /// True while the stage being run
    /// ends in '&': the program goes to
    /// the background when the kernel
    /// admits it.
    private var stageBackground = false

    /// Shell functions the operator has
    /// defined, by name: the body text,
    /// run as a sequence when called.
    private var functions: [String: String] =
        [:]

    /// Positional frames for function
    /// calls: [name, $1, $2, …], the
    /// innermost call last.
    private var positionalStack: [[String]] =
        []

    /// What `local` saved, per frame,
    /// restored when the call returns.
    private var localFrames:
        [[(String, String?)]] = []

    /// Set by `return`: the current
    /// function's remaining statements
    /// are skipped, and its caller
    /// consumes the flag.
    private var returnFlag = false

    /// An exact status a construct wants
    /// lastStatus to carry (return N) —
    /// execPipeline consumes it instead
    /// of the coarse stageError bit.
    private var pendingStatus: Int? = nil

    /// The editor door: vim/emacs/edit set
    /// this; the room presents the editor.
    @Published var editorSession: EditorSession?

    /// The program door: a command sets
    /// this; the room raises the sheet.
    @Published var programRequest:
        BlacksiteView.Program?

    var capturing: Bool { !captureStack.isEmpty }

    static let builtinNames: [String] = [
        "help", "clear", "sys", "ver", "ps",
        "jobs", "kill", "fastfetch",
        "neofetch", "diagnose",
        "scan", "knock", "census", "decode",
        "company", "port", "emcon", "macro",
        "gauntlet", "journal", "log", "tomato",
        "freedoom", "doom",
        "theme", "haptics", "skelli", "open",
        "halt", "pwd", "cd", "ls", "mkdir",
        "touch", "cat", "echo", "cp", "mv",
        "rm", "tree", "head", "tail", "wc",
        "grep", "find", "stat",
        "sort", "uniq", "cut", "tr", "sed",
        "rev", "tac", "nl", "diff", "tee",
        "xargs", "seq", "base64", "md5sum",
        "sha256sum", "xxd", "sleep", "test",
        "[", "true", "false", "return",
        "local", "printf", "du", "file",
        "strings", "cal", "yes", "figlet",
        "bigtext", "env",
        "export", "unset", "which", "history",
        "date", "vim", "emacs", "nano", "edit", "run",
        "js", "node", "python3", "python",
        "sh", "source", "pkg",
        "gfx", "view", "wallpaper", "exit",
        "ping", "traceroute", "trace",
        "discover", "portscan", "nmap",
        "banner", "dig", "nslookup", "host",
        "whois", "curl", "wget", "nc",
        "telnet", "ifconfig", "arp",
        "netstat", "hostname", "subdomains",
        "revdns", "nbstat", "snmp", "upnp",
        "bonjour", "cert", "webaudit",
        "methods", "dirb", "wol",
    ]

    // MARK: Output

    func emit(_ text: String,
              _ kind: Line.Kind = .out) {
        // Colour is for the screen alone:
        // anything captured — a pipe, a
        // file, a $() — gets plain text,
        // and NO_COLOR in the environment
        // silences it at the source.
        let shown = (capturing
                     || env["NO_COLOR"] != nil)
            ? ANSITerm.strip(text) : text
        if capturing {
            if kind == .err { stageError = true }
            captureStack[captureStack.count - 1]
                .append(shown)
            return
        }
        let append = { [weak self] in
            guard let self = self else { return }
            self.lines.append(
                Line(text: shown, kind: kind,
                     image: nil))
            if self.lines.count > 400 {
                self.lines.removeFirst(
                    self.lines.count - 400)
            }
        }
        if Thread.isMainThread {
            append()
        } else {
            DispatchQueue.main.async(execute: append)
        }
    }

    /// A picture in the transcript — the
    /// graphics engine's output door.
    func emitImage(_ image: UIImage,
                   path: String) {
        let append = { [weak self] in
            guard let self = self else { return }
            self.lines.append(
                Line(text: path, kind: .out,
                     image: image))
            if self.lines.count > 400 {
                self.lines.removeFirst(
                    self.lines.count - 400)
            }
        }
        if Thread.isMainThread {
            append()
        } else {
            DispatchQueue.main.async(execute: append)
        }
    }

    private func emitBlock(_ text: String,
                           _ kind: Line.Kind = .out) {
        for row in text.split(
            separator: "\n", omittingEmptySubsequences: false) {
            emit(String(row), kind)
        }
    }

    func bootIfNeeded() {
        guard !booted else { return }
        booted = true
        BlacksiteKernel.shared.onProcessEnd =
            { [weak self] proc in
                guard let self = self
                else { return }
                if proc.background {
                    self.emit(
                        "kernel: [\(proc.pid)] "
                            + "\(proc.name) — "
                            + proc.exitNote,
                        .sys)
                }
                self.updateBusy()
            }
        BlacksiteFS.binNames =
            BlacksiteShell.builtinNames
            + BlacksiteWasm.applets
            + ["linuxbox", "linuxbox.wasm"]
        _ = BlacksiteFS.rootURL()
        BlacksiteGFX.shared.onShow =
            { [weak self] image, path in
                self?.emitImage(image, path: path)
            }
        emit("BLACKSITE OS — nightjar-hack "
             + AppInfo.version, .sys)
        emit("organs: scan · recon · decode · "
             + "emcon · macros · skelli", .sys)
        emit("mounted: files (ls /) · editors "
             + "(vim · emacs) · engine (run · js) "
             + "· graphics (gfx) · packages (pkg)",
             .sys)
        emit("every gate that holds in the house "
             + "holds here. type 'help'.", .sys)
    }

    /// The machine identifier (iPhone18,2
    /// and kin), read the way the developer
    /// room reads it — DevKit's copy is
    /// file-private, so the shell keeps its
    /// own.
    static var deviceModelID: String {
        var system = utsname()
        uname(&system)
        return Mirror(reflecting: system.machine)
            .children.reduce(into: "") {
                text, child in
                if let byte = child.value as? Int8,
                   byte != 0 {
                    text.append(Character(
                        UnicodeScalar(UInt8(byte))))
                }
            }
    }

    // MARK: History

    /// History, walked from the newest back:
    /// back 0 is the last command run.
    func historyBack(_ back: Int) -> String? {
        guard back >= 0, back < history.count
        else { return nil }
        return history[history.count - 1 - back]
    }
    var historyCount: Int { history.count }

    // MARK: Completion

    /// Tab completion for the input line:
    /// completes the last word — a command
    /// name in first position, a file name
    /// after one — to the longest common
    /// prefix of everything it could be.
    /// nil when nothing completes.
    func completed(_ draft: String) -> String? {
        let endsWithSpace = draft.hasSuffix(" ")
        let words = draft.split(
            separator: " ",
            omittingEmptySubsequences: true)
        let token: String
        let head: String
        if endsWithSpace || words.isEmpty {
            token = ""
            head = draft
        } else {
            token = String(words.last!)
            head = String(
                draft.dropLast(token.count))
        }
        let isFirst = head.trimmingCharacters(
            in: .whitespaces).isEmpty
        var candidates: [String] = []
        if isFirst {
            candidates = Self.builtinNames.filter {
                $0.hasPrefix(token)
            }
        } else if let slash = token.lastIndex(
            of: "/") {
            let dirPart = String(token[...slash])
            let base = String(token[
                token.index(after: slash)...])
            let rawDir = String(
                dirPart.dropLast())
            let dir = rawDir.hasPrefix("/")
                ? rawDir : cwd + "/" + rawDir
            candidates = (BlacksiteFS.list(dir)
                ?? []).filter {
                    $0.name.hasPrefix(base)
                }.map {
                    dirPart + $0.name
                        + ($0.isDir ? "/" : "")
                }
        } else {
            candidates = (BlacksiteFS.list(cwd)
                ?? []).filter {
                    $0.name.hasPrefix(token)
                }.map {
                    $0.name + ($0.isDir ? "/" : "")
                }
        }
        guard !candidates.isEmpty else {
            return nil
        }
        var prefix = candidates[0]
        for other in candidates.dropFirst() {
            let common = zip(prefix, other)
                .prefix { $0 == $1 }
            prefix = String(common.map { $0.0 })
            if prefix.isEmpty { break }
        }
        if prefix.count > token.count {
            return head + prefix
        }
        if candidates.count == 1,
           candidates[0] != token {
            return head + candidates[0]
        }
        return nil
    }

    // MARK: The door

    /// One interactive line: echoed,
    /// remembered, executed.
    func run(_ raw: String) {
        if let waiter = inputWaiter {
            inputWaiter = nil
            let typed = raw
                .trimmingCharacters(
                    in: .newlines)
            emit("▸ " + typed, .cmd)
            waiter(typed)
            return
        }
        let command = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let continuing =
            constructBuffer() != nil
        emit((continuing ? "… " : "▸ ")
             + command, .cmd)
        history.append(command)
        if history.count > 200 {
            history.removeFirst(
                history.count - 200)
        }
        execLine(command, stdin: "")
    }

    // MARK: The language
    //
    // A line is a sequence (`;`, `&&`) of
    // pipelines (`|`); each stage is a
    // command with quotes, $variables,
    // $(…) substitution, and a trailing
    // redirect (`>`, `>>`) into the
    // console's own files.

    private enum Gate { case always, and }

    private func splitSequence(_ line: String)
        -> [(text: String, gate: Gate)] {
        var parts: [(String, Gate)] = []
        var current = ""
        var gate: Gate = .always
        var single = false
        var double = false
        var escaped = false
        var depth = 0
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if escaped {
                current.append(ch)
                escaped = false
                i += 1
                continue
            }
            if ch == "\\", !single {
                current.append(ch)
                escaped = true
                i += 1
                continue
            }
            if ch == "'", !double {
                single.toggle()
                current.append(ch)
                i += 1
                continue
            }
            if ch == "\"", !single {
                double.toggle()
                current.append(ch)
                i += 1
                continue
            }
            if !single && !double {
                if ch == "$", i + 1 < chars.count,
                   chars[i + 1] == "(" {
                    depth += 1
                    current.append(ch)
                    i += 1
                    continue
                }
                if ch == ")", depth > 0 {
                    depth -= 1
                    current.append(ch)
                    i += 1
                    continue
                }
                if depth == 0, ch == ";" {
                    parts.append((current, gate))
                    current = ""
                    gate = .always
                    i += 1
                    continue
                }
                if depth == 0, ch == "&",
                   i + 1 < chars.count,
                   chars[i + 1] == "&" {
                    parts.append((current, gate))
                    current = ""
                    gate = .and
                    i += 2
                    continue
                }
            }
            current.append(ch)
            i += 1
        }
        parts.append((current, gate))
        return parts
    }

    private func splitTop(_ text: String,
                          separator: Character)
        -> [String] {
        var parts: [String] = []
        var current = ""
        var single = false
        var double = false
        var escaped = false
        var depth = 0
        for ch in text {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\", !single {
                current.append(ch)
                escaped = true
                continue
            }
            if ch == "'", !double {
                single.toggle()
                current.append(ch)
                continue
            }
            if ch == "\"", !single {
                double.toggle()
                current.append(ch)
                continue
            }
            if !single && !double {
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth = max(0, depth - 1)
                }
                if ch == separator, depth == 0 {
                    parts.append(current)
                    current = ""
                    continue
                }
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    private func findRedirect(_ stage: String)
        -> (stage: String, path: String,
            append: Bool)? {
        let chars = Array(stage)
        var single = false
        var double = false
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'", !double {
                single.toggle()
            } else if ch == "\"", !single {
                double.toggle()
            } else if !single && !double {
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth = max(0, depth - 1)
                }
                if ch == ">", depth == 0 {
                    let append = i + 1 < chars.count
                        && chars[i + 1] == ">"
                    let rest = String(
                        chars[(i + (append ? 2 : 1))...])
                    guard let target = tokenize(
                        rest).first else {
                        return nil
                    }
                    return (String(chars[..<i]),
                            target, append)
                }
            }
            i += 1
        }
        return nil
    }

    /// A `<` in a stage: the stage's
    /// stdin comes from a file instead
    /// of the pipe.
    private func findInputRedirect(
        _ stage: String)
        -> (stage: String, path: String)? {
        let chars = Array(stage)
        var single = false
        var double = false
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'", !double {
                single.toggle()
            } else if ch == "\"", !single {
                double.toggle()
            } else if !single && !double {
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth = max(0, depth - 1)
                }
                if ch == "<", depth == 0 {
                    if i + 1 < chars.count,
                       chars[i + 1] == "<" {
                        i += 1
                    } else {
                        let rest = String(
                            chars[(i + 1)...])
                        guard let target =
                            tokenize(rest).first
                        else { return nil }
                        return (String(
                                    chars[..<i]),
                                target)
                    }
                }
            }
            i += 1
        }
        return nil
    }

    private func envValue(_ name: String)
        -> String {
        if name == "PWD" { return cwd }
        if name == "?" {
            return String(lastStatus)
        }
        if name == "0" {
            return positionalStack.last?
                .first ?? "blacksite"
        }
        if name == "#" {
            let frame = positionalStack.last
                ?? []
            return String(
                max(0, frame.count - 1))
        }
        if name == "@" || name == "*" {
            let frame = positionalStack.last
                ?? []
            return frame.dropFirst()
                .joined(separator: " ")
        }
        if let n = Int(name), n >= 1 {
            let frame = positionalStack.last
                ?? []
            return n < frame.count
                ? frame[n] : ""
        }
        return env[name] ?? ""
    }

    private func tokenize(_ text: String)
        -> [String] {
        var tokens: [String] = []
        var current = ""
        var started = false
        var single = false
        var double = false
        let chars = Array(text)
        var i = 0
        func flush() {
            if started {
                tokens.append(current)
                current = ""
                started = false
            }
        }
        while i < chars.count {
            let ch = chars[i]
            if single {
                if ch == "'" {
                    single = false
                } else {
                    current.append(ch)
                }
                i += 1
                continue
            }
            if ch == "\\" {
                if i + 1 < chars.count {
                    current.append(chars[i + 1])
                    started = true
                    i += 2
                } else {
                    i += 1
                }
                continue
            }
            if ch == "'", !double {
                single = true
                started = true
                i += 1
                continue
            }
            if ch == "\"" {
                double.toggle()
                started = true
                i += 1
                continue
            }
            if ch == "~", !started,
               i + 1 >= chars.count
                || chars[i + 1] == "/" {
                current += BlacksiteFS.home
                started = true
                i += 1
                continue
            }
            if ch == "$" {
                started = true
                if i + 2 < chars.count,
                   chars[i + 1] == "(",
                   chars[i + 2] == "(" {
                    var depth = 0
                    var k = i + 1
                    while k < chars.count {
                        if chars[k] == "(" {
                            depth += 1
                        }
                        if chars[k] == ")" {
                            depth -= 1
                            if depth == 0 {
                                break
                            }
                        }
                        k += 1
                    }
                    if depth == 0,
                       k > i + 3 {
                        let inner = String(
                            chars[(i + 3)..<(
                                k - 1)])
                        current += String(
                            arithEval(inner))
                        i = k + 1
                        continue
                    }
                }
                if i + 1 < chars.count,
                   chars[i + 1] == "(" {
                    var depth = 1
                    var j = i + 2
                    var inner = ""
                    while j < chars.count,
                          depth > 0 {
                        let c = chars[j]
                        if c == "(" {
                            depth += 1
                        }
                        if c == ")" {
                            depth -= 1
                            if depth == 0 { break }
                        }
                        inner.append(c)
                        j += 1
                    }
                    if captureStack.count < 6 {
                        let sub = captureOutput {
                            execLine(inner,
                                     stdin: "")
                        }
                        current += sub
                            .trimmingCharacters(
                                in: .newlines)
                    } else {
                        current += "$(" + inner
                            + ")"
                    }
                    i = j + 1
                    continue
                }
                if i + 1 < chars.count,
                   chars[i + 1] == "{" {
                    var j = i + 2
                    var name = ""
                    while j < chars.count,
                          chars[j] != "}" {
                        name.append(chars[j])
                        j += 1
                    }
                    current += envValue(name)
                    i = j + 1
                    continue
                }
                var j = i + 1
                var name = ""
                while j < chars.count,
                      chars[j].isLetter
                        || chars[j].isNumber
                        || chars[j] == "_"
                        || chars[j] == "?" {
                    name.append(chars[j])
                    j += 1
                }
                if name.isEmpty {
                    current.append("$")
                    i += 1
                } else {
                    current += envValue(name)
                    i = j
                }
                continue
            }
            if (ch == " " || ch == "\t"),
               !double {
                flush()
                i += 1
                continue
            }
            current.append(ch)
            started = true
            i += 1
        }
        flush()
        return tokens
    }

    private func execLine(_ line: String,
                          stdin: String) {
        if routeConstruct(line,
                          stdin: stdin) {
            return
        }
        for part in splitSequence(line) {
            let text = part.text
                .trimmingCharacters(
                    in: .whitespaces)
            if text.isEmpty { continue }
            if part.gate == .and,
               lastStatus != 0 { continue }
            execPipeline(text, stdin: stdin)
            if returnFlag { break }
        }
    }

    private func execPipeline(_ segment: String,
                              stdin: String) {
        var stages = splitTop(segment,
                              separator: "|")
            .map {
                $0.trimmingCharacters(
                    in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        guard !stages.isEmpty else { return }
        var redirect: (path: String,
                       append: Bool)? = nil
        if let found = findRedirect(
            stages[stages.count - 1]) {
            stages[stages.count - 1] = found.stage
                .trimmingCharacters(
                    in: .whitespaces)
            redirect = (found.path, found.append)
            if stages[stages.count - 1].isEmpty {
                stages.removeLast()
            }
        }
        guard !stages.isEmpty else { return }
        var input = stdin
        for (index, stage)
            in stages.enumerated() {
            let isLast = index == stages.count - 1
            stageError = false
            var stageText = stage
            var stageStdin = input
            if let inRedir =
                findInputRedirect(stage) {
                stageText = inRedir.stage
                    .trimmingCharacters(
                        in: .whitespaces)
                if let content = BlacksiteFS
                    .readText(
                        resolved(inRedir.path)) {
                    stageStdin = content
                } else {
                    emit("\(inRedir.path): no "
                         + "such file to "
                         + "read '<' from.",
                         .err)
                    lastStatus = 1
                    input = ""
                    continue
                }
            }
            if !isLast || redirect != nil {
                let text = captureOutput {
                    runStage(stageText,
                             stdin: stageStdin)
                }
                lastStatus = consumeStatus()
                if isLast, let redirect = redirect {
                    writeRedirect(text, redirect)
                } else {
                    input = text
                }
            } else {
                runStage(stageText,
                         stdin: stageStdin)
                lastStatus = consumeStatus()
            }
        }
    }

    /// The stage's verdict: an exact
    /// status when a construct set one
    /// (return N), else the error bit.
    private func consumeStatus() -> Int {
        if let pending = pendingStatus {
            pendingStatus = nil
            return pending
        }
        return stageError ? 1 : 0
    }

    private func captureOutput(
        _ body: () -> Void) -> String {
        captureStack.append([])
        body()
        let rows = captureStack.removeLast()
        return rows.joined(separator: "\n")
    }

    private func writeRedirect(
        _ text: String,
        _ redirect: (path: String,
                     append: Bool)) {
        let target = BlacksiteFS.normalize(
            redirect.path, cwd: cwd)
        guard !target.hasPrefix("/bin") else {
            emit("\(target): /bin is read-only "
                 + "— the built-ins live in "
                 + "the shell.", .err)
            lastStatus = 1
            return
        }
        var body = text
        if !body.isEmpty { body += "\n" }
        if BlacksiteFS.writeText(
            target, text: body,
            append: redirect.append) {
            lastStatus = 0
        } else {
            emit("\(target): cannot write "
                 + "there.", .err)
            lastStatus = 1
        }
    }

    private func parseAssignment(_ token: String)
        -> (String, String)? {
        guard let eq = token.firstIndex(of: "=")
        else { return nil }
        let name = String(token[..<eq])
        guard !name.isEmpty,
              name.allSatisfy({
                  $0.isLetter || $0.isNumber
                  || $0 == "_"
              }),
              name.first?.isLetter == true
                || name.first == "_"
        else { return nil }
        return (name, String(
            token[token.index(after: eq)...]))
    }



    // MARK: Constructs — functions,
    // loops, conditionals, case,
    // here-docs
    //
    // A construct spans lines, so the
    // shell keeps a per-thread buffer:
    // a line that opens one (or feeds an
    // open one) is held until the
    // construct completes, then the
    // whole text is parsed from its
    // sequence parts and executed with
    // the same statements any line gets.

    private static let constructHeads:
        Set<String> = ["for", "while",
                       "until", "if", "case"]

    private static let constructKey =
        "blacksite.construct.buffer"

    private func constructBuffer()
        -> String? {
        Thread.current.threadDictionary[
            Self.constructKey] as? String
    }

    private func setConstructBuffer(
        _ value: String?) {
        if let value = value {
            Thread.current.threadDictionary[
                Self.constructKey] = value
        } else {
            Thread.current.threadDictionary
                .removeObject(
                    forKey: Self.constructKey)
        }
    }

    /// One line's here-doc marker, when
    /// it carries one: the cleaned line
    /// and what was found.
    private func heredocInLine(
        _ line: String)
        -> (clean: String, tag: String,
            quoted: Bool,
            herestring: String?)? {
        let chars = Array(line)
        var single = false
        var double = false
        var depth = 0
        var i = 0
        while i + 1 < chars.count {
            let ch = chars[i]
            if ch == "'", !double {
                single.toggle()
            } else if ch == "\"", !single {
                double.toggle()
            } else if !single, !double {
                if ch == "(" { depth += 1 }
                if ch == ")" {
                    depth = max(0, depth - 1)
                }
                if ch == "<", depth == 0,
                   chars[i + 1] == "<",
                   i == 0 || chars[i - 1] != "<" {
                    var j = i + 2
                    var isHerestring = false
                    if j < chars.count,
                       chars[j] == "<" {
                        isHerestring = true
                        j += 1
                    }
                    if j < chars.count,
                       chars[j] == "-",
                       !isHerestring {
                        j += 1
                    }
                    while j < chars.count,
                          chars[j] == " "
                            || chars[j] == "\t" {
                        j += 1
                    }
                    var quoted = false
                    var tag = ""
                    if j < chars.count,
                       chars[j] == "'"
                        || chars[j] == "\"" {
                        let q = chars[j]
                        quoted = true
                        j += 1
                        while j < chars.count,
                              chars[j] != q {
                            tag.append(chars[j])
                            j += 1
                        }
                        if j < chars.count {
                            j += 1
                        }
                    } else {
                        while j < chars.count,
                              chars[j].isLetter
                                || chars[j]
                                    .isNumber
                                || chars[j]
                                    == "_" {
                            tag.append(chars[j])
                            j += 1
                        }
                    }
                    guard !tag.isEmpty else {
                        return nil
                    }
                    let clean = (String(
                        chars[..<i])
                        + String(chars[j...]))
                        .trimmingCharacters(
                            in: .whitespaces)
                    if isHerestring {
                        return (clean, "",
                                false, tag)
                    }
                    return (clean, tag,
                            quoted, nil)
                }
            }
            i += 1
        }
        return nil
    }

    private func constructStarts(
        _ line: String) -> Bool {
        let trimmed = line
            .trimmingCharacters(
                in: .whitespaces)
        if functionDefHead(trimmed) != nil {
            return true
        }
        let first = rawWords(trimmed).first
            ?? ""
        if Self.constructHeads
            .contains(first) {
            return true
        }
        return heredocInLine(trimmed) != nil
    }

    private func constructComplete(
        _ text: String) -> Bool {
        let lines = text.components(
            separatedBy: "\n")
        for (index, line) in lines
            .enumerated() {
            if let marker = heredocInLine(
                line) {
                if marker.herestring != nil {
                    break
                }
                if index + 1 >= lines.count {
                    return false
                }
                let found = lines[
                    (index + 1)...]
                    .contains {
                        $0.trimmingCharacters(
                            in: .whitespaces)
                            == marker.tag
                    }
                if !found { return false }
                break
            }
        }
        let words = constructWords(text)
        func count(_ set: Set<String>)
            -> Int {
            words.filter { set.contains($0) }
                .count
        }
        let loops = count(["for", "while",
                           "until"])
        let dones = count(["done"])
        let ifs = count(["if"])
        let fis = count(["fi"])
        let cases = count(["case"])
        let esacs = count(["esac"])
        guard dones >= loops,
              fis >= ifs,
              esacs >= cases
        else { return false }
        let firstLine = lines.first?
            .trimmingCharacters(
                in: .whitespaces) ?? ""
        if functionDefHead(firstLine) != nil {
            return braceBody(text) != nil
        }
        return true
    }

    /// Route a line into the construct
    /// machinery when it belongs there.
    /// Returns true when the line was
    /// consumed (executed or buffered).
    private func routeConstruct(
        _ line: String, stdin: String)
        -> Bool {
        if let buffered = constructBuffer() {
            let joined = buffered + "\n"
                + line
            if constructComplete(joined) {
                setConstructBuffer(nil)
                execConstruct(
                    joined, stdin: stdin)
            } else {
                setConstructBuffer(joined)
            }
            return true
        }
        guard constructStarts(line) else {
            return false
        }
        if constructComplete(line) {
            execConstruct(line, stdin: stdin)
        } else {
            setConstructBuffer(line)
        }
        return true
    }

    /// $ expansion for here-doc bodies:
    /// variables and substitutions, no
    /// word splitting, quotes literal.
    private func expandText(_ text: String)
        -> String {
        var out = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\", i + 1 < chars.count,
               chars[i + 1] == "$"
                || chars[i + 1] == "\\"
                || chars[i + 1] == "`" {
                out.append(chars[i + 1])
                i += 2
                continue
            }
            if ch == "$",
               i + 1 < chars.count {
                if chars[i + 1] == "(",
                   i + 2 < chars.count,
                   chars[i + 2] == "(" {
                    var depth = 0
                    var k = i + 1
                    while k < chars.count {
                        if chars[k] == "(" {
                            depth += 1
                        }
                        if chars[k] == ")" {
                            depth -= 1
                            if depth == 0 {
                                break
                            }
                        }
                        k += 1
                    }
                    if depth == 0, k > i + 3 {
                        let inner = String(
                            chars[(i + 3)..<(
                                k - 1)])
                        out += String(
                            arithEval(inner))
                        i = k + 1
                        continue
                    }
                }
                if chars[i + 1] == "(" {
                    var depth = 1
                    var j = i + 2
                    var inner = ""
                    while j < chars.count,
                          depth > 0 {
                        let c = chars[j]
                        if c == "(" {
                            depth += 1
                        }
                        if c == ")" {
                            depth -= 1
                            if depth == 0 {
                                break
                            }
                        }
                        inner.append(c)
                        j += 1
                    }
                    let sub = captureOutput {
                        execLine(inner,
                                 stdin: "")
                    }
                    out += sub
                        .trimmingCharacters(
                            in: .newlines)
                    i = j + 1
                    continue
                }
                if chars[i + 1] == "{" {
                    var j = i + 2
                    var name = ""
                    while j < chars.count,
                          chars[j] != "}" {
                        name.append(chars[j])
                        j += 1
                    }
                    out += envValue(name)
                    i = j + 1
                    continue
                }
                var j = i + 1
                var name = ""
                while j < chars.count,
                      chars[j].isLetter
                        || chars[j].isNumber
                        || chars[j] == "_"
                        || chars[j] == "?" {
                    name.append(chars[j])
                    j += 1
                }
                if name.isEmpty {
                    out.append("$")
                    i += 1
                } else {
                    out += envValue(name)
                    i = j
                }
                continue
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    /// Execute a completed construct
    /// text: pull any here-doc out into
    /// stdin, then walk the parts.
    private func execConstruct(
        _ text: String, stdin: String) {
        var working = text
        var stdinToUse = stdin
        var lines = working.components(
            separatedBy: "\n")
        for (index, line) in lines
            .enumerated() {
            guard let marker = heredocInLine(
                line) else { continue }
            if let word = marker.herestring {
                lines[index] = marker.clean
                stdinToUse = word + "\n"
            } else {
                var body: [String] = []
                var end = lines.count
                var j = index + 1
                while j < lines.count {
                    if lines[j]
                        .trimmingCharacters(
                            in: .whitespaces)
                        == marker.tag {
                        end = j
                        break
                    }
                    body.append(lines[j])
                    j += 1
                }
                if !marker.quoted {
                    body = body.map {
                        expandText($0)
                    }
                }
                stdinToUse = body.isEmpty
                    ? ""
                    : body.joined(
                        separator: "\n")
                        + "\n"
                lines[index] = marker.clean
                if end < lines.count {
                    lines.removeSubrange(
                        (index + 1)...end)
                } else if index + 1
                            < lines.count {
                    lines.removeSubrange(
                        (index + 1)...)
                }
            }
            working = lines.joined(
                separator: "\n")
            break
        }
        if !constructStarts(working) {
            execLine(working,
                     stdin: stdinToUse)
            return
        }
        let flat = working
            .replacingOccurrences(
                of: "\n", with: "; ")
        var parts = splitSequence(flat)
        var redirect: (path: String,
                        append: Bool)? = nil
        if let lastPart = parts.last {
            let headWord = rawWords(
                lastPart.text
                    .trimmingCharacters(
                        in: .whitespaces))
                .first ?? ""
            if ["done", "fi", "esac"]
                .contains(headWord),
               let found = findRedirect(
                lastPart.text) {
                parts[parts.count - 1] = (
                    text: found.stage,
                    gate: lastPart.gate)
                redirect = (found.path,
                            found.append)
            }
        }
        let cursor = PartCursor(parts)
        if let redirect = redirect {
            let captured = captureOutput {
                _ = self.execParts(
                    cursor, until: [],
                    execute: true,
                    stdin: stdinToUse)
            }
            writeRedirect(captured, redirect)
        } else {
            _ = execParts(
                cursor, until: [],
                execute: true,
                stdin: stdinToUse)
        }
    }

    /// A walk over a construct's
    /// sequence parts.
    private final class PartCursor {
        var parts: [(text: String,
                     gate: Gate)]
        var i = 0
        init(_ parts: [(text: String,
                         gate: Gate)]) {
            self.parts = parts
        }
        var atEnd: Bool {
            i >= parts.count
        }
        func peek() -> (text: String,
                        gate: Gate)? {
            atEnd ? nil : parts[i]
        }
        func advance() { i += 1 }
        func insert(
            _ part: (text: String,
                     gate: Gate),
            at index: Int) {
            parts.insert(part, at: index)
        }
    }

    /// Run statements from the cursor
    /// until a terminator part (one of
    /// `until`) or the parts run out.
    /// With execute false the structure
    /// is consumed but nothing runs —
    /// the untaken branch of an if.
    private func execParts(
        _ cursor: PartCursor,
        until: Set<String>,
        execute: Bool,
        stdin: String)
        -> (terminator: String,
            remainder: String)? {
        while let part = cursor.peek() {
            let text = part.text
                .trimmingCharacters(
                    in: .whitespaces)
            if text.isEmpty {
                cursor.advance()
                continue
            }
            let words = rawWords(text)
            let head = words.first ?? ""
            if until.contains(head) {
                cursor.advance()
                return (head,
                        remainderText(text))
            }
            if returnFlag { return nil }
            let gateOK = part.gate == .always
                || lastStatus == 0
            if Self.constructHeads
                .contains(head)
                || functionDefHead(text)
                    != nil {
                execConstructFromCursor(
                    cursor,
                    execute: execute
                        && gateOK,
                    stdin: stdin)
                continue
            }
            cursor.advance()
            if head == "then"
                || head == "do" {
                let stmt = remainderText(text)
                if stmt.isEmpty { continue }
                let stmtHead = rawWords(stmt)
                    .first ?? ""
                if Self.constructHeads
                    .contains(stmtHead)
                    || functionDefHead(stmt)
                        != nil {
                    cursor.insert(
                        (text: stmt,
                         gate: .always),
                        at: cursor.i)
                    continue
                }
                if execute && gateOK {
                    execLine(stmt,
                             stdin: stdin)
                }
                continue
            }
            if execute && gateOK {
                execLine(text, stdin: stdin)
            }
        }
        return nil
    }

    /// The cursor stands on a construct's
    /// opening part; consume it whole.
    private func execConstructFromCursor(
        _ cursor: PartCursor,
        execute: Bool,
        stdin: String) {
        guard let part = cursor.peek()
        else { return }
        let text = part.text
            .trimmingCharacters(
                in: .whitespaces)
        if functionDefHead(text) != nil {
            var gathered: [String] = []
            while let next = cursor.peek() {
                cursor.advance()
                gathered.append(next.text)
                let joined = gathered
                    .joined(separator: "; ")
                if braceBody(joined) != nil {
                    break
                }
            }
            if execute,
               let def = parseFunctionDef(
                gathered.joined(
                    separator: "; ")) {
                functions[def.name] = def.body
                lastStatus = 0
            }
            return
        }
        let head = rawWords(text).first ?? ""
        cursor.advance()
        switch head {
        case "for", "while", "until":
            execLoop(cursor, kind: head,
                     keywordPart: text,
                     execute: execute,
                     stdin: stdin)
        case "if":
            execIf(cursor,
                   keywordPart: text,
                   execute: execute,
                   stdin: stdin)
        case "case":
            execCase(cursor,
                     keywordPart: text,
                     execute: execute,
                     stdin: stdin)
        default:
            break
        }
    }

    /// for / while / until: the cursor
    /// stands just past the keyword part.
    /// The body's span is first measured
    /// (matching `done`, nest-aware) so
    /// it can run again and again.
    private func execLoop(
        _ cursor: PartCursor,
        kind: String,
        keywordPart: String,
        execute: Bool,
        stdin: String) {
        var depth = 1
        var j = cursor.i
        while j < cursor.parts.count {
            let head = rawWords(
                cursor.parts[j].text
                    .trimmingCharacters(
                        in: .whitespaces))
                .first ?? ""
            if Self.constructHeads
                .contains(head),
               head != "if",
               head != "case" {
                depth += 1
            }
            if head == "done" {
                depth -= 1
                if depth == 0 { break }
            }
            j += 1
        }
        let bodyParts = Array(
            cursor.parts[cursor.i..<min(
                j, cursor.parts.count)])
        cursor.i = min(j + 1,
                       cursor.parts.count)
        guard execute else { return }
        if j >= cursor.parts.count {
            emit("\(kind): the loop never "
                 + "meets its 'done'.",
                 .err)
            stageError = true
            return
        }
        let cap = 10000
        if kind == "for" {
            let tokens = tokenize(
                keywordPart)
            guard tokens.count >= 2 else {
                emit("for: a variable "
                     + "needs naming.",
                     .err)
                stageError = true
                return
            }
            let name = tokens[1]
            var values: [String] = []
            if tokens.count >= 3,
               tokens[2] == "in" {
                values = tokens.dropFirst(3)
                    .flatMap {
                        globExpand($0)
                    }
            } else if tokens.count == 2 {
                let frame = positionalStack
                    .last ?? []
                values = Array(
                    frame.dropFirst())
            }
            var ran = 0
            for value in values {
                if returnFlag { break }
                if ran >= cap {
                    emit("for: the house "
                         + "caps a loop at "
                         + "\(cap) turns.",
                         .err)
                    stageError = true
                    break
                }
                ran += 1
                env[name] = value
                let sub = PartCursor(
                    bodyParts)
                _ = execParts(
                    sub, until: [],
                    execute: true,
                    stdin: stdin)
            }
            return
        }
        let cond = remainderText(
            keywordPart)
        guard !cond.isEmpty else {
            emit("\(kind): no condition "
                 + "to judge.", .err)
            stageError = true
            return
        }
        var turns = 0
        while true {
            if returnFlag { break }
            execLine(cond, stdin: stdin)
            let status = lastStatus
            let go = kind == "while"
                ? status == 0
                : status != 0
            if !go { break }
            if turns >= cap {
                emit("\(kind): the house "
                     + "caps a loop at "
                     + "\(cap) turns.",
                     .err)
                stageError = true
                break
            }
            turns += 1
            let sub = PartCursor(bodyParts)
            _ = execParts(
                sub, until: [],
                execute: true, stdin: stdin)
        }
    }

    /// if / elif / else / fi: branches
    /// are walked with execParts, the
    /// untaken ones in skip mode.
    private func execIf(
        _ cursor: PartCursor,
        keywordPart: String,
        execute: Bool,
        stdin: String) {
        var condText = remainderText(
            keywordPart)
        var tookAny = false
        while true {
            var take = false
            if execute && !tookAny,
               !condText.isEmpty {
                execLine(condText,
                         stdin: stdin)
                take = lastStatus == 0
            }
            if take { tookAny = true }
            guard let hit = execParts(
                cursor,
                until: ["elif", "else", "fi"],
                execute: take,
                stdin: stdin)
            else { return }
            if hit.terminator == "fi" {
                return
            }
            if hit.terminator == "elif" {
                condText = hit.remainder
                continue
            }
            let elseTake = execute && !tookAny
            if elseTake,
               !hit.remainder.isEmpty {
                execLine(hit.remainder,
                         stdin: stdin)
            }
            _ = execParts(
                cursor, until: ["fi"],
                execute: elseTake,
                stdin: stdin)
            return
        }
    }

    /// case … esac: clauses are matched
    /// by glob against the word; the
    /// first match runs to its `;;`.
    private func execCase(
        _ cursor: PartCursor,
        keywordPart: String,
        execute: Bool,
        stdin: String) {
        let tokens = tokenize(keywordPart)
        guard tokens.count >= 2 else {
            emit("case: a word needs "
                 + "judging.", .err)
            stageError = true
            return
        }
        let word = tokens[1]
        var matchedSomething = false
        var inClause = false
        while let part = cursor.peek() {
            let text = part.text
                .trimmingCharacters(
                    in: .whitespaces)
            if text.isEmpty {
                cursor.advance()
                inClause = false
                continue
            }
            let head = rawWords(text).first
                ?? ""
            if head == "esac" {
                cursor.advance()
                return
            }
            if !inClause {
                guard let paren = text
                    .firstIndex(of: ")")
                else {
                    cursor.advance()
                    continue
                }
                var patText = String(
                    text[..<paren])
                    .trimmingCharacters(
                        in: .whitespaces)
                if patText.hasPrefix("(") {
                    patText = String(
                        patText.dropFirst())
                }
                let rest = String(text[
                    text.index(after: paren)...])
                    .trimmingCharacters(
                        in: .whitespaces)
                let pats = patText
                    .components(
                        separatedBy: "|")
                    .map {
                        $0.trimmingCharacters(
                            in: CharacterSet(
                                whitespacesAndNewlines))
                        .replacingOccurrences(
                            of: "'", with: "")
                        .replacingOccurrences(
                            of: "\"", with: "")
                    }
                cursor.advance()
                if !matchedSomething,
                   pats.contains(where: {
                       wildmatch($0, word)
                   }) {
                    matchedSomething = true
                    inClause = true
                    var stmt = rest
                    var ends = false
                    if stmt.hasSuffix(";;") {
                        stmt = String(
                            stmt.dropLast(2))
                            .trimmingCharacters(
                                in: .whitespaces)
                        ends = true
                    }
                    if execute,
                       !stmt.isEmpty {
                        execLine(stmt,
                                 stdin: stdin)
                    }
                    if ends {
                        inClause = false
                    }
                }
                continue
            }
            var stmt = text
            var ends = false
            if stmt == ";;" {
                ends = true
                stmt = ""
            } else if stmt
                .hasSuffix(";;") {
                stmt = String(
                    stmt.dropLast(2))
                    .trimmingCharacters(
                        in: .whitespaces)
                ends = true
            }
            if execute, !stmt.isEmpty {
                execLine(stmt, stdin: stdin)
            }
            cursor.advance()
            if ends { inClause = false }
        }
    }

    // MARK: The shell language —
    // helpers
    //
    // Constructs (functions, loops,
    // conditionals, case, here-docs)
    // arrive line by line and are parsed
    // from RAW text: nothing expands
    // until a statement actually runs,
    // when it goes through execLine and
    // the ordinary tokenizer like any
    // other command.

    /// Split raw text into words with
    /// quotes honoured but NOTHING
    /// expanded — the construct parser's
    /// eyes.
    private func rawWords(_ text: String)
        -> [String] {
        var words: [String] = []
        var current = ""
        var started = false
        var single = false
        var double = false
        var escaped = false
        func flush() {
            if started {
                words.append(current)
                current = ""
                started = false
            }
        }
        for ch in text {
            if escaped {
                current.append(ch)
                started = true
                escaped = false
                continue
            }
            if ch == "\\", !single {
                escaped = true
                continue
            }
            if ch == "'", !double {
                single.toggle()
                started = true
                continue
            }
            if ch == "\"", !single {
                double.toggle()
                started = true
                continue
            }
            if (ch == " " || ch == "\t"
                || ch == "\n"),
               !single, !double {
                flush()
                continue
            }
            current.append(ch)
            started = true
        }
        flush()
        return words
    }

    /// Everything after the first word.
    private func remainderText(_ text: String)
        -> String {
        let trimmed = text
            .trimmingCharacters(
                in: .whitespaces)
        guard let idx = trimmed.firstIndex(
            where: { $0 == " " || $0 == "\t" })
        else { return "" }
        return String(trimmed[
            trimmed.index(after: idx)...])
            .trimmingCharacters(
                in: .whitespaces)
    }

    /// The words of a text with quoted
    /// spans skipped — keyword counting
    /// for construct completeness.
    private func constructWords(
        _ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var single = false
        var double = false
        var escaped = false
        func flush() {
            if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        for ch in text {
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\", !single {
                escaped = true
                continue
            }
            if ch == "'", !double {
                single.toggle()
                continue
            }
            if ch == "\"", !single {
                double.toggle()
                continue
            }
            if single || double { continue }
            if ch.isLetter || ch.isNumber
                || ch == "_" {
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return words
    }

    /// The name when text opens a
    /// function definition — `name()` —
    /// else nil.
    private func functionDefHead(
        _ text: String) -> String? {
        let trimmed = text
            .trimmingCharacters(
                in: .whitespaces)
        var name = ""
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex,
              trimmed[idx].isLetter
                || trimmed[idx].isNumber
                || trimmed[idx] == "_" {
            name.append(trimmed[idx])
            idx = trimmed.index(after: idx)
        }
        guard !name.isEmpty,
              name.first?.isLetter == true
                || name.first == "_"
        else { return nil }
        let rest = String(trimmed[idx...])
            .trimmingCharacters(
                in: .whitespaces)
        guard rest.hasPrefix("()")
        else { return nil }
        return name
    }

    /// Scan a text for its first brace
    /// and the matching close, quote-
    /// aware. Returns the body between
    /// them, or nil when unbalanced.
    private func braceBody(_ text: String)
        -> String? {
        let chars = Array(text)
        var single = false
        var double = false
        var depth = 0
        var openAt: Int? = nil
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "'", !double {
                single.toggle()
            } else if ch == "\"", !single {
                double.toggle()
            } else if !single, !double {
                if ch == "{" {
                    if depth == 0 {
                        openAt = i
                    }
                    depth += 1
                }
                if ch == "}" {
                    depth -= 1
                    if depth == 0,
                       let open = openAt {
                        return String(
                            chars[(open + 1)..<i])
                    }
                }
            }
            i += 1
        }
        return nil
    }

    private func parseFunctionDef(
        _ text: String)
        -> (name: String, body: String)? {
        guard let name = functionDefHead(text),
              let body = braceBody(text)
        else { return nil }
        return (name, body
            .trimmingCharacters(
                in: .whitespacesAndNewlines))
    }

    /// Glob matching: * ? [set] [!set],
    /// the shell's own hand.
    private func wildmatch(_ pattern: String,
                           _ value: String)
        -> Bool {
        let p = Array(pattern)
        let v = Array(value)
        func match(_ pi: Int, _ vi: Int)
            -> Bool {
            if pi == p.count {
                return vi == v.count
            }
            if p[pi] == "*" {
                var skip = vi
                while skip <= v.count {
                    if match(pi + 1, skip) {
                        return true
                    }
                    skip += 1
                }
                return false
            }
            guard vi < v.count else {
                return false
            }
            if p[pi] == "?" {
                return match(pi + 1, vi + 1)
            }
            if p[pi] == "[",
               let close = (pi + 1..<p.count)
                .first(where: {
                    p[$0] == "]"
                }) {
                var j = pi + 1
                var negate = false
                if j < close,
                   p[j] == "!"
                    || p[j] == "^" {
                    negate = true
                    j += 1
                }
                var hit = false
                while j < close {
                    if j + 2 < close,
                       p[j + 1] == "-" {
                        if p[j] <= v[vi],
                           v[vi] <= p[j + 2] {
                            hit = true
                        }
                        j += 3
                    } else {
                        if p[j] == v[vi] {
                            hit = true
                        }
                        j += 1
                    }
                }
                if hit != negate {
                    return match(
                        close + 1, vi + 1)
                }
                return false
            }
            if p[pi] == v[vi] {
                return match(pi + 1, vi + 1)
            }
            return false
        }
        return match(0, 0)
    }

    /// Expand a glob word against the
    /// files where it points; no match
    /// leaves the word as written.
    private func globExpand(_ word: String)
        -> [String] {
        guard word.contains("*")
                || word.contains("?")
                || word.contains("[")
        else { return [word] }
        let dirPart: String
        let pattern: String
        let head: String
        if let slash = word.lastIndex(
            of: "/") {
            dirPart = String(
                word[..<slash])
            head = String(
                word[...slash])
            pattern = String(word[
                word.index(after: slash)...])
        } else {
            dirPart = cwd
            head = ""
            pattern = word
        }
        let dir = resolved(
            dirPart.isEmpty ? "/" : dirPart)
        guard let entries = BlacksiteFS.list(
            dir) else { return [word] }
        let hits = entries
            .filter {
                wildmatch(pattern, $0.name)
            }
            .map { head + $0.name }
            .sorted()
        return hits.isEmpty ? [word] : hits
    }

    // MARK: Arithmetic — $(( … ))

    /// Integer arithmetic for $(( … )):
    /// the full operator ladder, names
    /// read from the environment, and
    /// overflow that saturates instead
    /// of trapping — a shell expression
    /// must never take the house down.
    private struct ArithParser {
        let chars: [Character]
        var i = 0
        let value: (String) -> Int

        init(text: String,
             value: @escaping (String)
                -> Int) {
            chars = Array(text)
            self.value = value
        }

        mutating func parseAll() -> Int {
            let result = parseExpr()
            return result
        }

        private mutating func skipSpaces() {
            while i < chars.count,
                  chars[i] == " "
                    || chars[i] == "\t" {
                i += 1
            }
        }

        private mutating func peekOp(
            _ op: String) -> Bool {
            skipSpaces()
            let want = Array(op)
            guard i + want.count
                    <= chars.count
            else { return false }
            for (offset, c) in want
                .enumerated() {
                if chars[i + offset] != c {
                    return false
                }
            }
            return true
        }

        private mutating func eatOp(
            _ op: String) -> Bool {
            guard peekOp(op) else {
                return false
            }
            i += op.count
            return true
        }

        private func safeAdd(_ a: Int,
                             _ b: Int) -> Int {
            let r = a.addingReportingOverflow(b)
            return r.overflow
                ? (a >= 0 ? Int.max : Int.min)
                : r.partialValue
        }

        private func safeMul(_ a: Int,
                             _ b: Int) -> Int {
            let r = a.multipliedReportingOverflow(
                by: b)
            return r.overflow
                ? ((a < 0) != (b < 0)
                   ? Int.min : Int.max)
                : r.partialValue
        }

        mutating func parseExpr() -> Int {
            let cond = parseOr()
            if eatOp("?") {
                let yes = parseExpr()
                _ = eatOp(":")
                let no = parseExpr()
                return cond != 0 ? yes : no
            }
            return cond
        }

        mutating func parseOr() -> Int {
            var lhs = parseAnd()
            while eatOp("||") {
                let rhs = parseAnd()
                lhs = (lhs != 0 || rhs != 0)
                    ? 1 : 0
            }
            return lhs
        }

        mutating func parseAnd() -> Int {
            var lhs = parseBitOr()
            while eatOp("&&") {
                let rhs = parseBitOr()
                lhs = (lhs != 0 && rhs != 0)
                    ? 1 : 0
            }
            return lhs
        }

        mutating func parseBitOr() -> Int {
            var lhs = parseBitXor()
            while peekOp("|"),
                  !peekOp("||") {
                i += 1
                let rhs = parseBitXor()
                lhs = lhs | rhs
            }
            return lhs
        }

        mutating func parseBitXor() -> Int {
            var lhs = parseBitAnd()
            while eatOp("^") {
                let rhs = parseBitAnd()
                lhs = lhs ^ rhs
            }
            return lhs
        }

        mutating func parseBitAnd() -> Int {
            var lhs = parseEquality()
            while peekOp("&"),
                  !peekOp("&&") {
                i += 1
                let rhs = parseEquality()
                lhs = lhs & rhs
            }
            return lhs
        }

        mutating func parseEquality() -> Int {
            var lhs = parseRelational()
            while true {
                if eatOp("==") {
                    lhs = lhs
                        == parseRelational()
                        ? 1 : 0
                } else if eatOp("!=") {
                    lhs = lhs
                        != parseRelational()
                        ? 1 : 0
                } else { return lhs }
            }
        }

        mutating func parseRelational() -> Int {
            var lhs = parseShift()
            while true {
                if eatOp("<=") {
                    lhs = lhs <= parseShift()
                        ? 1 : 0
                } else if eatOp(">=") {
                    lhs = lhs >= parseShift()
                        ? 1 : 0
                } else if eatOp("<") {
                    lhs = lhs < parseShift()
                        ? 1 : 0
                } else if eatOp(">") {
                    lhs = lhs > parseShift()
                        ? 1 : 0
                } else { return lhs }
            }
        }

        mutating func parseShift() -> Int {
            var lhs = parseAdd()
            while true {
                if eatOp("<<") {
                    let n = parseAdd()
                    lhs = (n < 0 || n > 62)
                        ? 0 : lhs << n
                } else if eatOp(">>") {
                    let n = parseAdd()
                    lhs = (n < 0 || n > 62)
                        ? 0 : lhs >> n
                } else { return lhs }
            }
        }

        mutating func parseAdd() -> Int {
            var lhs = parseMul()
            while true {
                if eatOp("+") {
                    lhs = safeAdd(
                        lhs, parseMul())
                } else if peekOp("-"),
                          !peekOp("--") {
                    i += 1
                    let rhs = parseMul()
                    let r = lhs
                        .subtractingReportingOverflow(
                            rhs)
                    lhs = r.overflow
                        ? (lhs >= 0
                           ? Int.max : Int.min)
                        : r.partialValue
                } else { return lhs }
            }
        }

        mutating func parseMul() -> Int {
            var lhs = parsePow()
            while true {
                if eatOp("*") {
                    lhs = safeMul(
                        lhs, parsePow())
                } else if eatOp("/") {
                    let rhs = parsePow()
                    if rhs == 0 {
                        lhs = 0
                    } else if lhs == Int.min,
                              rhs == -1 {
                        lhs = Int.min
                    } else {
                        lhs = lhs / rhs
                    }
                } else if eatOp("%") {
                    let rhs = parsePow()
                    if rhs == 0 {
                        lhs = 0
                    } else if lhs == Int.min,
                              rhs == -1 {
                        lhs = 0
                    } else {
                        lhs = lhs % rhs
                    }
                } else { return lhs }
            }
        }

        mutating func parsePow() -> Int {
            let base = parseUnary()
            if eatOp("**") {
                let exp = parsePow()
                if exp < 0 { return 0 }
                var result = 1
                var n = exp
                var b = base
                while n > 0 {
                    if n % 2 == 1 {
                        result = safeMul(
                            result, b)
                    }
                    n /= 2
                    if n > 0 {
                        b = safeMul(b, b)
                    }
                }
                return result
            }
            return base
        }

        mutating func parseUnary() -> Int {
            if eatOp("-") {
                return -parseUnary()
            }
            if eatOp("+") {
                return parseUnary()
            }
            if eatOp("!") {
                return parseUnary() == 0
                    ? 1 : 0
            }
            if eatOp("~") {
                return ~parseUnary()
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Int {
            skipSpaces()
            guard i < chars.count else {
                return 0
            }
            if chars[i] == "(" {
                i += 1
                let inner = parseExpr()
                if i < chars.count,
                   chars[i] == ")" {
                    i += 1
                }
                return inner
            }
            if chars[i] == "$" {
                i += 1
            }
            if i < chars.count,
               chars[i].isNumber {
                var text = ""
                if chars[i] == "0",
                   i + 1 < chars.count,
                   chars[i + 1] == "x"
                    || chars[i + 1] == "X" {
                    i += 2
                    while i < chars.count,
                          chars[i].isHexDigit {
                        text.append(chars[i])
                        i += 1
                    }
                    return Int(text, radix: 16)
                        ?? 0
                }
                while i < chars.count,
                      chars[i].isNumber {
                    text.append(chars[i])
                    i += 1
                }
                return Int(text) ?? 0
            }
            if i < chars.count,
               chars[i].isLetter
                || chars[i] == "_"
                || chars[i] == "?" {
                var name = ""
                while i < chars.count,
                      chars[i].isLetter
                        || chars[i].isNumber
                        || chars[i] == "_"
                        || chars[i] == "?" {
                    name.append(chars[i])
                    i += 1
                }
                return value(name)
            }
            i += 1
            return 0
        }
    }

    private func arithEval(_ text: String)
        -> Int {
        var parser = ArithParser(
            text: text) { name in
                Int(self.envValue(name)) ?? 0
            }
        return parser.parseAll()
    }

    // MARK: One stage

    private func runStage(_ stage: String,
                          stdin: String) {
        stageInput = stdin
        stageBackground = false
        var tokens = tokenize(stage)
        while let first = tokens.first,
              let assignment = parseAssignment(
                first) {
            env[assignment.0] = assignment.1
            tokens.removeFirst()
        }
        guard let headRaw = tokens.first else {
            return
        }
        let head = headRaw.lowercased()
        var args = Array(tokens.dropFirst())
        let programHeads: Set<String> = [
            "run", "python3", "python",
            "js", "node", "sh", "source", ".",
        ]
        if args.last == "&",
           programHeads.contains(head) {
            args.removeLast()
            stageBackground = true
        }
        switch head {
        case "help", "?":
            help()
        case "clear":
            if !capturing {
                DispatchQueue.main.async {
                    [weak self] in
                    self?.lines = []
                }
            }
        case "sys", "status":
            emitBlock(DevKit.houseState(), .sys)
        case "ver", "whoami":
            emit("nightjar-hack \(AppInfo.version) "
                 + "on \(Self.deviceModelID) — "
                 + "source "
                 + (SourceStamp.shortCommit
                    ?? "unstamped"), .sys)
            emit("operator: the one holding the "
                 + "phone. console: blacksite.",
                 .sys)
        case "ps":
            processes()
        case "jobs":
            jobsCommand()
        case "kill":
            killCommand(args)
        case "diagnose":
            diagnoseCommand()
        case "fastfetch":
            fetchCommand(neofetch: false)
        case "neofetch":
            fetchCommand(neofetch: true)
        case "scan":
            scan(args)
        case "knock":
            knock(args)
        case "census":
            census()
        case "decode":
            if let line = Blacksite.decode(
                hex: args.joined(separator: "")) {
                emitBlock(line)
            } else {
                emit("decode needs hex bytes — "
                     + "'decode 4c001006…' (the "
                     + "first two bytes are the "
                     + "company, little-endian).",
                     .err)
            }
        case "company":
            company(args)
        case "port":
            port(args)
        case "ping", "traceroute", "trace",
             "discover", "portscan", "nmap",
             "banner", "dig", "nslookup",
             "host", "whois", "curl", "wget",
             "nc", "telnet", "ifconfig",
             "arp", "netstat", "hostname",
             "subdomains", "revdns",
             "nbstat", "snmp", "upnp",
             "bonjour", "cert", "webaudit",
             "methods", "dirb", "wol":
            netCommand(head, args)
        case "emcon":
            emcon(args)
        case "macro", "macros":
            macro(args)
        case "freedoom", "doom":
            if capturing {
                emit("freedoom plays live — "
                     + "it cannot be piped.",
                     .err)
            } else {
                programRequest = .freedoom
                emit("the room opens. "
                     + "rip and tear.",
                     .ok)
            }
        case "gauntlet":
            if capturing {
                emit("the gauntlet runs live — "
                     + "it cannot be piped.",
                     .err)
            } else {
                Gauntlet.shared.run()
                emit("the gauntlet runs. 'ps' "
                     + "watches it; the verdict "
                     + "lands in the developer "
                     + "room and the log.", .ok)
            }
        case "journal":
            journal(args)
        case "log":
            let count = args.first
                .flatMap(Int.init) ?? 30
            for row in DevLog.recent(count) {
                emit(row, .sys)
            }
        case "tomato":
            tomato(args)
        case "theme":
            theme(args)
        case "haptics":
            haptics(args)
        case "skelli":
            ask(args)
        case "open":
            open(args)
        case "halt", "standdown":
            BlacksiteKernel.shared.killAll(
                reason: "halted by the "
                    + "operator")
            SkelliCenter.shared.haltAndVanish()
            emit("everything halted; the house "
                 + "stands down.", .ok)
        case "pwd":
            emit(cwd)
        case "cd":
            cdCommand(args)
        case "ls":
            lsCommand(args)
        case "mkdir":
            mkdirCommand(args)
        case "touch":
            touchCommand(args)
        case "cat":
            catCommand(args)
        case "echo":
            var words = args
            var escapes = false
            while let first = words.first,
                  ["-n", "-e", "-ne", "-en"]
                    .contains(first) {
                if first.contains("e") {
                    escapes = true
                }
                words.removeFirst()
            }
            var body = words.joined(
                separator: " ")
            if escapes {
                body = ANSITerm.unescape(body)
            }
            emit(body)
        case "cp":
            cpCommand(args)
        case "mv":
            mvCommand(args)
        case "rm":
            rmCommand(args)
        case "tree":
            treeCommand(args)
        case "head":
            headTailCommand(args, tail: false)
        case "tail":
            headTailCommand(args, tail: true)
        case "wc":
            wcCommand(args)
        case "grep":
            grepCommand(args)
        case "find":
            findCommand(args)
        case "sort", "uniq", "cut",
             "tr", "sed", "rev", "tac",
             "nl", "diff", "tee", "xargs",
             "seq", "base64", "md5sum",
             "sha256sum", "xxd", "sleep",
             "printf", "du", "file",
             "strings", "cal", "yes",
             "figlet", "bigtext":
            textCommand(head, args)
        case "stat":
            statCommand(args)
        case "test":
            testCommand(args, bracket: false)
        case "[":
            if args.last == "]" {
                testCommand(
                    Array(args.dropLast()),
                    bracket: true)
            } else {
                emit("[: the closing ']' "
                     + "went missing.",
                     .err)
                stageError = true
            }
        case "true", ":":
            break
        case "false":
            stageError = true
        case "return":
            let n = args.first
                .flatMap(Int.init)
                ?? lastStatus
            pendingStatus = n
            stageError = n != 0
            returnFlag = true
        case "local":
            localCommand(args)
        case "env":
            for key in env.keys.sorted() {
                emit("\(key)=\(env[key] ?? "")")
            }
        case "export":
            for arg in args {
                if let pair = parseAssignment(
                    arg) {
                    env[pair.0] = pair.1
                }
            }
            if args.isEmpty {
                for key in env.keys.sorted() {
                    emit("\(key)=\(env[key] ?? "")")
                }
            }
        case "unset":
            for arg in args {
                env.removeValue(forKey: arg)
            }
        case "which":
            whichCommand(args)
        case "history":
            for (index, entry)
                in history.enumerated() {
                emit("\(index + 1)  \(entry)",
                     .sys)
            }
        case "date":
            let formatter = DateFormatter()
            formatter.dateFormat =
                "EEEE, MMMM d, yyyy · HH:mm:ss"
            emit(formatter.string(from: Date()))
        case "vim":
            editorSession = EditorSession(
                path: args.first.map {
                    BlacksiteFS.normalize(
                        $0, cwd: cwd)
                },
                personality: .vim)
        case "emacs":
            editorSession = EditorSession(
                path: args.first.map {
                    BlacksiteFS.normalize(
                        $0, cwd: cwd)
                },
                personality: .emacs)
        case "nano":
            editorSession = EditorSession(
                path: args.first.map {
                    BlacksiteFS.normalize(
                        $0, cwd: cwd)
                },
                personality: .nano)
        case "edit":
            editorSession = EditorSession(
                path: args.first.map {
                    BlacksiteFS.normalize(
                        $0, cwd: cwd)
                },
                personality: env["EDITOR"]
                    == "emacs" ? .emacs
                    : env["EDITOR"] == "nano"
                    ? .nano : .vim)
        case "js", "node":
            jsCommand(args)
        case "python3", "python":
            pyCommand(args)
        case "run":
            runFileCommand(args)
        case "sh", "source", ".":
            scriptCommand(args)
        case "pkg":
            pkgCommand(args)
        case "gfx":
            gfxCommand(args)
        case "wallpaper":
            wallpaperCommand(args)
        case "view":
            viewCommand(args)
        case "exit", "quit", "logout":
            emit("there is no exit from the "
                 + "blacksite — open another "
                 + "tab; the console keeps "
                 + "the light on.", .sys)
        default:
            if let body = functions[head] {
                callFunction(
                    head, body: body,
                    args: args)
                return
            }
            if BlacksiteWasm.isApplet(head) {
                wasmAppletCommand(
                    head, args,
                    stdin: stageInput)
                return
            }
            if BlacksiteJS.shared.hasCommand(
                head) {
                jsInvoke(head, args)
            } else {
                emit("no such command: \(head) "
                     + "— 'help' lists the "
                     + "house; 'pkg list' lists "
                     + "what can be installed.",
                     .err)
            }
        }
    }

    /// Call a shell function: push its
    /// positional frame, run its body
    /// as a sequence, restore what
    /// `local` saved, and carry its
    /// exact status out.
    private func callFunction(
        _ name: String, body: String,
        args: [String]) {
        guard positionalStack.count < 32
        else {
            emit("\(name): functions may "
                 + "nest 32 deep in "
                 + "this house.", .err)
            stageError = true
            return
        }
        positionalStack.append([name] + args)
        localFrames.append([])
        execLine(body, stdin: stageInput)
        let frame = localFrames.removeLast()
        for (key, old) in frame.reversed() {
            if let old = old {
                env[key] = old
            } else {
                env.removeValue(forKey: key)
            }
        }
        positionalStack.removeLast()
        returnFlag = false
        pendingStatus = lastStatus
        stageError = lastStatus != 0
    }

    private func localCommand(
        _ args: [String]) {
        guard !positionalStack.isEmpty,
              !localFrames.isEmpty else {
            emit("local: only a function "
                 + "has locals.", .err)
            stageError = true
            return
        }
        let top = localFrames.count - 1
        for arg in args {
            if let pair = parseAssignment(
                arg) {
                localFrames[top].append(
                    (pair.0, env[pair.0]))
                env[pair.0] = pair.1
            } else {
                localFrames[top].append(
                    (arg, env[arg]))
                env.removeValue(forKey: arg)
            }
        }
    }

    // MARK: File commands

    private func resolved(_ arg: String) -> String {
        BlacksiteFS.normalize(arg, cwd: cwd)
    }

    private func flagLetters(_ args: [String])
        -> String {
        args.filter { $0.hasPrefix("-") }
            .joined()
    }

    private func targetArg(_ args: [String])
        -> String? {
        args.first { !$0.hasPrefix("-") }
    }

    private func cdCommand(_ args: [String]) {
        let target = resolved(
            args.first ?? env["HOME"] ?? "/home")
        guard BlacksiteFS.exists(target) else {
            emit("cd: no such directory: "
                 + "\(target)", .err)
            return
        }
        guard BlacksiteFS.isDirectory(target)
        else {
            emit("cd: not a directory: "
                 + "\(target)", .err)
            return
        }
        cwd = target
        env["PWD"] = target
    }

    private func lsCommand(_ args: [String]) {
        let long = flagLetters(args)
            .contains("l")
        let target = resolved(
            targetArg(args) ?? cwd)
        guard BlacksiteFS.exists(target) else {
            emit("ls: no such place: "
                 + "\(target)", .err)
            return
        }
        guard BlacksiteFS.isDirectory(target)
        else {
            let size = BlacksiteFS.fileSize(
                target) ?? 0
            emit(long
                 ? "\(size)  \(target)"
                 : BlacksiteFS.baseName(
                    of: target))
            return
        }
        guard let entries = BlacksiteFS.list(
            target) else {
            emit("ls: cannot read \(target)",
                 .err)
            return
        }
        if entries.isEmpty {
            emit("(empty)", .sys)
        }
        for entry in entries {
            if long {
                if entry.isDir {
                    emit(dressed(
                            pad(entry.name + "/",
                                26),
                            name: entry.name,
                            isDir: true)
                         + "dir", .out)
                } else {
                    let child = target == "/"
                        ? "/" + entry.name
                        : target + "/" + entry.name
                    let size = BlacksiteFS
                        .fileSize(child) ?? 0
                    emit(dressed(
                            pad(entry.name, 26),
                            name: entry.name,
                            isDir: false)
                         + "\(size)", .out)
                }
            } else {
                emit(dressed(
                        entry.name
                            + (entry.isDir
                               ? "/" : ""),
                        name: entry.name,
                        isDir: entry.isDir),
                     .out)
            }
        }
    }

    private func mkdirCommand(_ args: [String]) {
        guard !args.isEmpty else {
            emit("mkdir needs a name.", .err)
            return
        }
        for arg in args {
            let target = resolved(arg)
            if !BlacksiteFS.makeDir(target) {
                emit("mkdir: cannot make "
                     + "\(target) — /bin is "
                     + "read-only.", .err)
            }
        }
    }

    private func touchCommand(_ args: [String]) {
        guard !args.isEmpty else {
            emit("touch needs a file.", .err)
            return
        }
        for arg in args {
            let target = resolved(arg)
            if BlacksiteFS.exists(target) {
                continue
            }
            if !BlacksiteFS.writeText(
                target, text: "") {
                emit("touch: cannot make "
                     + "\(target).", .err)
            }
        }
    }

    private func catCommand(_ args: [String]) {
        guard !args.isEmpty else {
            if !stageInput.isEmpty {
                emitBlock(stageInput)
            } else {
                emit("cat needs a file — "
                     + "or a pipe.", .err)
            }
            return
        }
        for arg in args {
            let target = resolved(arg)
            guard !BlacksiteFS.isDirectory(target)
            else {
                emit("cat: \(target) is a "
                     + "directory.", .err)
                continue
            }
            guard let text = BlacksiteFS
                .readText(target) else {
                emit("cat: cannot read "
                     + "\(target).", .err)
                continue
            }
            var body = text
            if body.hasSuffix("\n") {
                body = String(body.dropLast())
            }
            emitBlock(body)
        }
    }

    private func cpCommand(_ args: [String]) {
        guard args.count >= 2 else {
            emit("cp <from> <to>", .err)
            return
        }
        let from = resolved(args[0])
        var to = resolved(args[1])
        if BlacksiteFS.isDirectory(to) {
            to += "/" + BlacksiteFS.baseName(
                of: from)
        }
        if BlacksiteFS.copy(from: from, to: to) {
            emit("copied → \(to)", .sys)
        } else {
            emit("cp: cannot copy \(from) "
                 + "there (files only; /bin "
                 + "is read-only).", .err)
        }
    }

    private func mvCommand(_ args: [String]) {
        guard args.count >= 2 else {
            emit("mv <from> <to>", .err)
            return
        }
        let from = resolved(args[0])
        var to = resolved(args[1])
        if BlacksiteFS.isDirectory(to) {
            to += "/" + BlacksiteFS.baseName(
                of: from)
        }
        if BlacksiteFS.move(from: from, to: to) {
            emit("moved → \(to)", .sys)
        } else {
            emit("mv: cannot move \(from) "
                 + "there.", .err)
        }
    }

    private func rmCommand(_ args: [String]) {
        let recursive = flagLetters(args)
            .contains("r")
        let targets = args.filter {
            !$0.hasPrefix("-")
        }
        guard !targets.isEmpty else {
            emit("rm needs a target.", .err)
            return
        }
        for arg in targets {
            let target = resolved(arg)
            guard target != "/" else {
                emit("rm: the root stays.",
                     .err)
                continue
            }
            guard BlacksiteFS.exists(target)
            else {
                emit("rm: no such thing: "
                     + "\(target)", .err)
                continue
            }
            if BlacksiteFS.isDirectory(target),
               !recursive,
               !(BlacksiteFS.list(target)?
                    .isEmpty ?? true) {
                emit("rm: \(target) is a full "
                     + "directory — rm -r if "
                     + "you mean it.", .err)
                continue
            }
            if !BlacksiteFS.remove(target) {
                emit("rm: cannot remove "
                     + "\(target).", .err)
            }
        }
    }

    private func treeCommand(_ args: [String]) {
        let target = resolved(
            targetArg(args) ?? cwd)
        guard BlacksiteFS.isDirectory(target)
        else {
            emit("tree: \(target) is not a "
                 + "directory.", .err)
            return
        }
        emit(target == "/" ? "/" : target, .sys)
        let rows = treeRows(target, prefix: "",
                            depth: 0)
        for row in rows.prefix(300) {
            emit(row, .out)
        }
        if rows.count > 300 {
            emit("… \(rows.count - 300) more",
                 .sys)
        }
    }

    private func treeRows(_ path: String,
                          prefix: String,
                          depth: Int) -> [String] {
        guard depth <= 6,
              let entries = BlacksiteFS.list(path)
        else { return [] }
        var rows: [String] = []
        for (index, entry)
            in entries.enumerated() {
            let last = index == entries.count - 1
            rows.append(prefix
                        + (last ? "└── " : "├── ")
                        + entry.name
                        + (entry.isDir ? "/" : ""))
            if rows.count > 320 { return rows }
            if entry.isDir {
                let child = path == "/"
                    ? "/" + entry.name
                    : path + "/" + entry.name
                rows += treeRows(
                    child,
                    prefix: prefix
                        + (last ? "    " : "│   "),
                    depth: depth + 1)
                if rows.count > 320 {
                    return rows
                }
            }
        }
        return rows
    }

    private func sourceLines(_ args: [String])
        -> [String]? {
        if let file = targetArg(args) {
            let target = resolved(file)
            guard let text = BlacksiteFS
                .readText(target) else {
                emit("cannot read \(target).",
                     .err)
                return nil
            }
            return text.components(
                separatedBy: "\n")
        }
        if !stageInput.isEmpty {
            return stageInput.components(
                separatedBy: "\n")
        }
        emit("needs a file — or a pipe.",
             .err)
        return nil
    }

    private func headTailCommand(_ args: [String],
                                 tail: Bool) {
        var count = 10
        var rest = args
        var index = 0
        while index < rest.count {
            let arg = rest[index]
            if arg == "-n",
               index + 1 < rest.count,
               let value = Int(rest[index + 1]) {
                count = value
                rest.removeSubrange(
                    index...index + 1)
                continue
            }
            if arg.hasPrefix("-n"),
               let value = Int(arg.dropFirst(2)) {
                count = value
                rest.remove(at: index)
                continue
            }
            if arg.hasPrefix("-"),
               arg.count > 1,
               let value = Int(arg.dropFirst()) {
                count = value
                rest.remove(at: index)
                continue
            }
            index += 1
        }
        guard let rows = sourceLines(rest)
        else { return }
        let slice = tail
            ? Array(rows.suffix(count))
            : Array(rows.prefix(count))
        for row in slice {
            emit(row, .out)
        }
    }

    private func wcCommand(_ args: [String]) {
        let file = targetArg(args)
        let text: String
        if let file = file {
            let target = resolved(file)
            guard let found = BlacksiteFS
                .readText(target) else {
                emit("wc: cannot read "
                     + "\(target).", .err)
                return
            }
            text = found
        } else {
            text = stageInput
        }
        let lineCount = text.isEmpty ? 0
            : text.components(
                separatedBy: "\n").count
        let wordCount = text.split(
            whereSeparator: {
                $0 == " " || $0 == "\n"
                    || $0 == "\t"
            }).count
        emit("\(lineCount) lines · "
             + "\(wordCount) words · "
             + "\(text.count) chars"
             + (file.map { " · \($0)" } ?? ""),
             .out)
    }

    /// A name dressed for the screen the
    /// way ls has always dressed them:
    /// folders bold blue, the house's own
    /// runnable files green, pictures
    /// magenta. The codes vanish the
    /// moment output is captured.
    private func dressed(
        _ shown: String, name: String,
        isDir: Bool) -> String {
        let code: String?
        if isDir {
            code = "1;34"
        } else {
            let lower = name.lowercased()
            if lower.hasSuffix(".py")
                || lower.hasSuffix(".js")
                || lower.hasSuffix(".sh")
                || lower.hasSuffix(".wasm") {
                code = "1;32"
            } else if lower.hasSuffix(".png")
                || lower.hasSuffix(".jpg")
                || lower.hasSuffix(".gif") {
                code = "35"
            } else {
                code = nil
            }
        }
        guard let code else { return shown }
        return "\u{1B}[" + code + "m" + shown
            + "\u{1B}[0m"
    }

    /// A grep row with its matches lit —
    /// bold orange, the way a find should
    /// look. Matches are found in the
    /// searched text (lowercased under
    /// -i) and mapped back onto the row.
    private func highlighted(
        _ row: String, needle: String,
        insensitive: Bool) -> String {
        guard !needle.isEmpty else {
            return row
        }
        let hay = insensitive
            ? row.lowercased() : row
        let rowChars = Array(row)
        let hayChars = Array(hay)
        guard rowChars.count == hayChars.count
        else { return row }
        let needleChars = Array(needle)
        var spans: [(Int, Int)] = []
        var at = 0
        while at + needleChars.count
                <= hayChars.count {
            let slice = Array(
                hayChars[at..<at
                         + needleChars.count])
            if slice == needleChars {
                spans.append(
                    (at, at + needleChars.count))
                at += needleChars.count
            } else {
                at += 1
            }
        }
        guard !spans.isEmpty else {
            return row
        }
        var out = ""
        var cursor = 0
        for span in spans {
            out += String(
                rowChars[cursor..<span.0])
            out += "\u{1B}[1;38;5;208m"
            out += String(
                rowChars[span.0..<span.1])
            out += "\u{1B}[0m"
            cursor = span.1
        }
        out += String(rowChars[cursor...])
        return out
    }

    private func grepCommand(_ args: [String]) {
        var rest = args
        var insensitive = false
        if rest.first == "-i" {
            insensitive = true
            rest.removeFirst()
        }
        guard let pattern = rest.first else {
            emit("grep <pattern> [file]", .err)
            return
        }
        let fileArgs = Array(rest.dropFirst())
        guard let rows = sourceLines(fileArgs)
        else { return }
        let needle = insensitive
            ? pattern.lowercased() : pattern
        var hits = 0
        for row in rows {
            let hay = insensitive
                ? row.lowercased() : row
            if hay.contains(needle) {
                emit(highlighted(
                        row, needle: needle,
                        insensitive: insensitive),
                     .out)
                hits += 1
            }
        }
        if hits == 0 {
            stageError = true
        }
    }

    private func findCommand(_ args: [String]) {
        var root = cwd
        var needle: String?
        var index = 0
        while index < args.count {
            if args[index] == "-name",
               index + 1 < args.count {
                needle = args[index + 1]
                index += 2
                continue
            }
            if !args[index].hasPrefix("-") {
                root = resolved(args[index])
            }
            index += 1
        }
        let found = BlacksiteFS.walk(root)
            .filter { path in
                needle.map { name in
                    path.contains(name)
                } ?? true
            }
        if found.isEmpty {
            emit("find: nothing under \(root)",
                 .sys)
        }
        for path in found {
            emit(path, .out)
        }
    }

    private func statCommand(_ args: [String]) {
        guard let arg = args.first else {
            emit("stat <path>", .err)
            return
        }
        let target = resolved(arg)
        guard BlacksiteFS.exists(target) else {
            emit("stat: no such thing: "
                 + "\(target)", .err)
            return
        }
        if BlacksiteFS.isDirectory(target) {
            let count = BlacksiteFS.list(
                target)?.count ?? 0
            emit("\(target) — directory, "
                 + "\(count) entries", .sys)
        } else {
            emit("\(target) — file, "
                 + "\(BlacksiteFS.fileSize(target) ?? 0)"
                 + " bytes", .sys)
        }
    }

    private func whichCommand(_ args: [String]) {
        guard let name = args.first?
            .lowercased() else {
            emit("which <command>", .err)
            return
        }
        if BlacksiteShell.builtinNames
            .contains(name) {
            emit("/bin/\(name) — a built-in",
                 .out)
        } else if BlacksiteJS.shared
            .hasCommand(name) {
            emit("\(name) — a package command "
                 + "('pkg commands' lists "
                 + "its kin)", .out)
        } else {
            emit("\(name): not found", .err)
        }
    }

    // MARK: Code commands

    private func jsCommand(_ args: [String]) {
        let source = args.joined(separator: " ")
        guard !source.isEmpty else {
            emit("js needs code — 'js 2 + 2', "
                 + "or run a file.", .err)
            return
        }
        guard !capturing else {
            emit("the engine runs live — it "
                 + "cannot be piped.", .err)
            return
        }
        guard let proc = admitOrSay(
            "js " + String(source.prefix(40)),
            .javascript,
            background: stageBackground)
        else { return }
        installExecBridge()
        let out = kernelEmit(for: proc)
        BlacksiteJS.shared.printSink =
            { line in out(line, .out) }
        BlacksiteJS.shared.eval(source) {
            [weak self] result, error in
            guard let self = self else { return }
            BlacksiteKernel.shared.finish(
                proc, note: "done")
            if let error = error {
                self.emit("js: \(error)", .err)
            } else if let result = result {
                self.emit(result, .out)
            }
            self.updateBusy()
        }
    }

    /// `python3 [file.py [args…]]` — the
    /// house's small python (BlacksitePy).
    /// Bare, it lists what the subset
    /// carries and what it leaves out.
    /// The pid a program spawned right
    /// now answers to: the innermost
    /// script running on this thread, or
    /// 0 — the shell itself.
    private func currentParentPID() -> Int {
        let stack = Thread.current
            .threadDictionary[
                "blacksite.kernel.stack"]
            as? [Int]
        return stack?.last ?? 0
    }

    private func pushProcess(_ pid: Int) {
        var stack = Thread.current
            .threadDictionary[
                "blacksite.kernel.stack"]
                as? [Int] ?? []
        stack.append(pid)
        Thread.current.threadDictionary[
            "blacksite.kernel.stack"] = stack
    }

    private func popProcess() {
        var stack = Thread.current
            .threadDictionary[
                "blacksite.kernel.stack"]
                as? [Int] ?? []
        if !stack.isEmpty {
            stack.removeLast()
        }
        Thread.current.threadDictionary[
            "blacksite.kernel.stack"] = stack
    }

    /// Admit a program to the kernel, or
    /// say out loud why it was refused.
    private func admitOrSay(
        _ name: String, _ kind: KernelKind,
        background: Bool) -> KernelProcess? {
        let (proc, refusal) = BlacksiteKernel
            .shared.admit(
                name: name, kind: kind,
                parent: currentParentPID(),
                background: background)
        if let refusal = refusal {
            emit("kernel: \(refusal)", .err)
            return nil
        }
        if background, let proc = proc {
            emit("kernel: [\(proc.pid)] "
                + "\(name) — background",
                .sys)
        }
        updateBusy()
        return proc
    }

    private func updateBusy() {
        busy = BlacksiteKernel.shared
            .hasForegroundLive
    }

    /// A process's own output door: the
    /// kernel counts every line, and past
    /// the quota the door closes.
    private func kernelEmit(
        for proc: KernelProcess)
        -> BlacksiteEmit {
        return { [weak self] text, kind in
            guard let self = self
            else { return }
            if BlacksiteKernel.shared
                .accountOutput(proc) {
                self.emit(text, kind)
            }
        }
    }

    /// The bridge input() parks on:
    /// the program's thread waits at a
    /// gate while the console's next
    /// typed line is routed here. While
    /// it waits, the kernel marks the
    /// process parked — exempt from the
    /// wall clock, since it waits on the
    /// operator, not on time.
    private func makeInputProvider(
        for proc: KernelProcess)
        -> () -> String? {
        let kernel = BlacksiteKernel.shared
        return { [weak self] in
            guard let self = self else {
                return nil
            }
            kernel.markWaiting(proc, true)
            let gate = DispatchSemaphore(
                value: 0)
            var answer: String? = nil
            DispatchQueue.main.async {
                self.inputWaiter = { typed in
                    answer = typed
                    gate.signal()
                }
            }
            gate.wait()
            kernel.markWaiting(proc, false)
            return answer
        }
    }

    private func pyCommand(_ args: [String]) {
        guard let typed = args.first else {
            for line in BlacksitePy.helpLines {
                emit(line)
            }
            return
        }
        guard !capturing else {
            emit("programs run live — they "
                 + "cannot be piped.", .err)
            return
        }
        let path = BlacksiteFS.normalize(
            typed, cwd: cwd)
        guard BlacksiteFS.exists(path),
              !BlacksiteFS.isDirectory(path)
        else {
            emit("python3: no such file — "
                 + typed, .err)
            return
        }
        let background = stageBackground
        guard let proc = admitOrSay(
            "python3 " + args.joined(
                separator: " "),
            .python, background: background)
        else { return }
        BlacksitePy.runFile(
            path, args: args,
            inputProvider: background
                ? nil : makeInputProvider(
                    for: proc),
            cancel: proc.cancel,
            emit: kernelEmit(for: proc)) {
                [weak self] in
                BlacksiteKernel.shared.finish(
                    proc, note: "done")
                if !background {
                    self?.inputWaiter = nil
                }
                self?.updateBusy()
            }
    }

    private func runFileCommand(_ args: [String]) {
        guard let file = args.first else {
            emit("run <file.js | file.py | "
                 + "file.sh | file.wasm>",
                 .err)
            return
        }
        let target = resolved(file)
        guard BlacksiteFS.exists(target) else {
            emit("run: no such file: "
                 + "\(target)", .err)
            return
        }
        if target.hasSuffix(".js") {
            guard !capturing else {
                emit("programs run live — they "
                     + "cannot be piped.", .err)
                return
            }
            let background = stageBackground
            guard let proc = admitOrSay(
                "run " + args.joined(
                    separator: " "),
                .javascript,
                background: background)
            else { return }
            let out = kernelEmit(for: proc)
            BlacksiteJS.shared.printSink =
                { line in out(line, .out) }
            BlacksiteJS.shared.runFile(
                target,
                args: Array(args.dropFirst()),
                killSwitch: proc.killSwitch
            ) { [weak self] error in
                guard let self = self
                else { return }
                BlacksiteKernel.shared.finish(
                    proc,
                    note: error.map {
                        "done — \($0)"
                    } ?? "done")
                if let error = error {
                    self.emit("run: \(error)",
                              .err)
                }
                self.updateBusy()
            }
        } else if target.hasSuffix(".py") {
            guard !capturing else {
                emit("programs run live — they "
                     + "cannot be piped.", .err)
                return
            }
            let background = stageBackground
            guard let proc = admitOrSay(
                "run " + args.joined(
                    separator: " "),
                .python,
                background: background)
            else { return }
            BlacksitePy.runFile(
                target, args: [file]
                    + Array(
                        args.dropFirst()),
                inputProvider: background
                    ? nil : makeInputProvider(
                        for: proc),
                cancel: proc.cancel,
                emit: kernelEmit(
                    for: proc)) {
                    [weak self] in
                    BlacksiteKernel.shared
                        .finish(proc,
                                note: "done")
                    if !background {
                        self?.inputWaiter = nil
                    }
                    self?.updateBusy()
                }
        } else if target
                    .hasSuffix(".wasm") {
            guard !capturing else {
                emit("programs run live — they "
                     + "cannot be piped.", .err)
                return
            }
            let data: Data?
            if target == "/bin/linuxbox.wasm" {
                data = BlacksiteWasm
                    .linuxboxData()
            } else {
                data = BlacksiteFS.readData(
                    target)
            }
            guard let data = data else {
                emit("run: cannot read "
                     + "\(target).", .err)
                return
            }
            wasmRun(
                data: data,
                displayName: "run " + args
                    .joined(separator: " "),
                argv: [file]
                    + Array(args.dropFirst()),
                stdin: stageInput)
        } else if target.hasSuffix(".sh")
                    || target.hasSuffix(".bsh") {
            runScript(target)
        } else {
            emit("run takes a .js, .py, .sh "
                 + "or .wasm "
                 + "file — '\(file)' is "
                 + "none of them.", .err)
        }
    }

    /// A linux applet by name — ls, cat,
    /// grep and their kin, resolved to
    /// the bundled userspace binary and
    /// run as a kernel process whose
    /// argv[0] is the applet's name, the
    /// multicall way.
    private func wasmAppletCommand(
        _ head: String, _ args: [String],
        stdin: String) {
        guard !capturing else {
            emit("programs run live — they "
                 + "cannot be piped.", .err)
            return
        }
        guard let data = BlacksiteWasm
            .linuxboxData() else {
            emit("the linux userspace is "
                 + "missing — its bundled "
                 + "binary did not decode.",
                 .err)
            stageError = true
            return
        }
        wasmRun(
            data: data,
            displayName: ([head] + args)
                .joined(separator: " "),
            argv: [head] + args,
            stdin: stdin)
    }

    /// Admit a wasm guest to the kernel
    /// and hand it to its machine: the
    /// kernel owns the process, the
    /// machine owns the engine, the
    /// guest owns nothing but its own
    /// memory.
    private func wasmRun(
        data: Data, displayName: String,
        argv: [String], stdin: String) {
        let background = stageBackground
        guard let proc = admitOrSay(
            displayName, .wasm,
            background: background)
        else { return }
        var guestEnv = env
        guestEnv["PWD"] = cwd
        if guestEnv["HOME"] == nil {
            guestEnv["HOME"] = "/home"
        }
        let machine = BlacksiteWasm(
            proc: proc,
            emit: kernelEmit(for: proc)) {
                [weak self] code in
                guard let self = self
                else { return }
                self.wasmMachines[
                    proc.pid] = nil
                BlacksiteKernel.shared
                    .finish(
                        proc,
                        note: "exited \(code)")
                if code != 0 {
                    self.stageError = true
                }
                self.updateBusy()
            }
        wasmMachines[proc.pid] = machine
        machine.launch(
            data: data, argv: argv,
            env: guestEnv, cwd: cwd,
            stdin: stdin)
    }

    private func scriptCommand(_ args: [String]) {
        guard let file = args.first else {
            emit("sh <script.sh>", .err)
            return
        }
        let target = resolved(file)
        guard BlacksiteFS.exists(target) else {
            emit("sh: no such file: "
                 + "\(target)", .err)
            return
        }
        runScript(target)
    }

    private func runScript(_ target: String) {
        guard let text = BlacksiteFS.readText(
            target) else {
            emit("cannot read \(target).",
                 .err)
            return
        }
        let background = stageBackground
        guard let proc = admitOrSay(
            "sh " + target, .shell,
            background: background)
        else { return }
        let body = { [weak self] in
            guard let self = self
            else { return }
            self.pushProcess(proc.pid)
            for rawLine in text.components(
                separatedBy: "\n") {
                if proc.cancel.isCancelled {
                    self.emit(
                        "kernel: [\(proc.pid)] "
                            + "\(proc.name) — "
                            + "stopped.",
                        .sys)
                    break
                }
                if self.constructBuffer()
                    != nil {
                    self.execLine(
                        rawLine, stdin: "")
                    if self.returnFlag {
                        self.returnFlag =
                            false
                        break
                    }
                    continue
                }
                let line = rawLine
                    .trimmingCharacters(
                        in: .whitespaces)
                if line.isEmpty
                    || line.hasPrefix("#") {
                    continue
                }
                self.execLine(line, stdin: "")
                if self.returnFlag {
                    self.returnFlag = false
                    break
                }
            }
            self.popProcess()
            BlacksiteKernel.shared.finish(
                proc, note: "done")
            self.updateBusy()
        }
        if background {
            DispatchQueue.global(
                qos: .userInitiated).async(
                    execute: body)
        } else {
            body()
        }
    }

    /// Serializes bridge executions:
    /// captures share one stack, so two
    /// package-run commands never overlap.
    private let execBridgeLock = NSLock()

    /// Give the JS engine its road back
    /// into the shell: a script runs a
    /// line and reads what it printed.
    /// Nested script engines are refused
    /// — a package cannot summon js, node
    /// or grok itself through the bridge.
    private func installExecBridge() {
        BlacksiteJS.execProvider =
            { [weak self] line, done in
                guard let self = self else {
                    done("(the shell is gone)")
                    return
                }
                let head = self.tokenize(line)
                    .first?.lowercased() ?? ""
                if ["js", "node", "grok"]
                    .contains(head) {
                    done("(refused: " + head
                         + " cannot run "
                         + "inside a package)")
                    return
                }
                DispatchQueue.global(
                    qos: .userInitiated)
                    .async { [weak self] in
                        guard let self = self
                        else {
                            done("(the shell "
                                 + "is gone)")
                            return
                        }
                        Thread.current
                            .threadDictionary
                            .removeObject(
                                forKey:
                                "blacksite.construct.buffer")
                        self.execBridgeLock
                            .lock()
                        let out =
                            self.captureOutput {
                                self.execLine(
                                    line)
                            }
                        self.execBridgeLock
                            .unlock()
                        done(out)
                    }
            }
    }

    private func jsInvoke(_ name: String,
                          _ args: [String]) {
        guard !capturing else {
            emit("\(name) runs live — package "
                 + "commands cannot be "
                 + "piped.", .err)
            return
        }
        guard let proc = admitOrSay(
            name, .javascript,
            background: stageBackground)
        else { return }
        installExecBridge()
        let out = kernelEmit(for: proc)
        BlacksiteJS.shared.printSink =
            { line in out(line, .out) }
        BlacksiteKernel.shared.markWaiting(
            proc, true)
        BlacksiteJS.shared.callCommand(
            name, args: args
        ) { [weak self] text, error in
            guard let self = self else { return }
            BlacksiteKernel.shared.markWaiting(
                proc, false)
            BlacksiteKernel.shared.finish(
                proc, note: "done")
            if let error = error {
                self.emit("\(name): \(error)",
                          .err)
            } else if let text = text,
                      !text.isEmpty {
                self.emit(text, .out)
            }
            self.updateBusy()
        }
    }

    // MARK: Packages

    private func pkgCommand(_ args: [String]) {
        let sub = args.first?.lowercased()
            ?? "list"
        let engine = BlacksiteJS.shared
        switch sub {
        case "list":
            let installed = engine
                .installedPackages()
            if installed.isEmpty {
                emit("no packages installed.",
                     .sys)
            }
            for name in installed {
                emit("● \(name) — installed",
                     .out)
            }
            for (name, pkg) in BlacksiteJS
                .bundled.sorted(
                    by: { $0.key < $1.key })
                where !installed.contains(name) {
                emit("○ \(name) — \(pkg.blurb) "
                     + "('pkg install \(name)')",
                     .sys)
            }
        case "install":
            guard let target = args.dropFirst()
                .first else {
                emit("pkg install <name | url>",
                     .err)
                return
            }
            if target.contains("://") {
                guard !capturing else {
                    emit("installs run live.",
                         .err)
                    return
                }
                busy = true
                emit("fetching \(target)…",
                     .sys)
                engine.installFromURL(target) {
                    [weak self] error in
                    guard let self = self
                    else { return }
                    self.busy = false
                    if let error = error {
                        self.emit("pkg: \(error)",
                                  .err)
                    } else {
                        self.emit("installed. "
                                  + "its commands "
                                  + "are live — "
                                  + "'pkg "
                                  + "commands'.",
                                  .ok)
                    }
                }
            } else if let error = engine
                .installBundled(
                    target.lowercased()) {
                emit("pkg: \(error)", .err)
            } else {
                emit("installed "
                     + "\(target.lowercased()) "
                     + "— 'pkg commands' shows "
                     + "its gifts.", .ok)
            }
        case "remove", "rm":
            guard let target = args.dropFirst()
                .first?.lowercased() else {
                emit("pkg remove <name>", .err)
                return
            }
            if engine.removePackage(target) {
                emit("removed \(target) — its "
                     + "commands leave with "
                     + "it.", .ok)
            } else {
                emit("pkg: \(target) is not "
                     + "installed.", .err)
            }
        case "commands":
            let names = engine.commandNames()
            if names.isEmpty {
                emit("no package commands yet "
                     + "— 'pkg list'.", .sys)
            }
            for name in names {
                emit("  \(name)", .out)
            }
        default:
            emit("pkg list · install <name|url>"
                 + " · remove <name> · "
                 + "commands", .err)
        }
    }

    // MARK: The room's wallpaper

    private func wallpaperCommand(
        _ args: [String]) {
        let keeper = BlacksiteWallpaper.shared
        guard let wanted = args.first?
            .lowercased() else {
            emit("the room wears: "
                 + keeper.kind + " — filed at "
                 + "/var/wallpaper-"
                 + keeper.kind + ".png. "
                 + "'wallpaper stars|plasma|"
                 + "mandelbrot' repaints it.",
                 .sys)
            return
        }
        guard BlacksiteWallpaper.kinds
            .contains(wanted) else {
            emit("wallpaper kinds: stars, "
                 + "plasma, mandelbrot.",
                 .err)
            return
        }
        keeper.regenerate(kind: wanted)
        emit("repainting the room: "
             + wanted + " — the engine "
             + "works; the wall changes "
             + "when it is done.", .ok)
    }

    // MARK: Graphics

    private func gfxCommand(_ args: [String]) {
        let sub = args.first?.lowercased()
            ?? "demo"
        let engine = BlacksiteGFX.shared
        switch sub {
        case "demo":
            guard !capturing else {
                emit("pictures are drawn live.",
                     .err)
                return
            }
            _ = engine.demo()
            let path = engine.show(
                path: "/tmp/demo.png")
            emit("drew the demo card — filed "
                 + "at \(path). your own: "
                 + "gfx.* in any .js program.",
                 .sys)
        case "mandelbrot", "plasma", "stars":
            guard !capturing else {
                emit("pictures are drawn live.",
                     .err)
                return
            }
            var width = 720
            var height = 720
            if let size = args.dropFirst().first {
                let parts = size.lowercased()
                    .split(separator: "x")
                    .compactMap { Int($0) }
                if parts.count == 2 {
                    width = parts[0]
                    height = parts[1]
                } else if let single = Int(size) {
                    width = single
                    height = single
                }
            }
            emit("rendering \(sub)…", .sys)
            busy = true
            DispatchQueue.global(
                qos: .userInitiated).async {
                [weak self] in
                let image = engine.renderNamed(
                    sub, width: width,
                    height: height)
                DispatchQueue.main.async {
                    guard let self = self
                    else { return }
                    self.busy = false
                    guard let image = image else {
                        self.emit("gfx: the "
                                  + "renderer "
                                  + "refused.",
                                  .err)
                        return
                    }
                    let path = "/tmp/\(sub).png"
                    if let png = image.pngData() {
                        BlacksiteFS.writeData(
                            path, data: png)
                    }
                    self.emitImage(image,
                                   path: path)
                    self.emit("rendered \(sub) "
                              + "— filed at "
                              + "\(path).", .sys)
                }
            }
        case "show":
            guard let file = args.dropFirst()
                .first else {
                emit("gfx show <picture.png>",
                     .err)
                return
            }
            showPicture(resolved(file))
        default:
            emit("gfx demo · mandelbrot · "
                 + "plasma · stars · show "
                 + "<file>", .err)
        }
    }

    private func showPicture(_ target: String) {
        guard let data = BlacksiteFS.readData(
            target),
              let image = UIImage(data: data)
        else {
            emit("\(target): not a picture "
                 + "I can show.", .err)
            return
        }
        emitImage(image, path: target)
    }

    private func viewCommand(_ args: [String]) {
        guard let file = args.first else {
            emit("view <file>", .err)
            return
        }
        let target = resolved(file)
        let lower = target.lowercased()
        if lower.hasSuffix(".png")
            || lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg") {
            showPicture(target)
        } else {
            catCommand(args)
        }
    }

    private func help() {
        let sections: [(String,
                         [(String, String)])] = [
            ("the house", [
                ("sys", "the whole house state"),
                ("ps", "processes, live and recent"),
                ("fastfetch",
                 "the machine's calling card"),
                ("diagnose",
                 "put the whole house through its paces — engines, kernel, containment drills"),
                ("neofetch",
                 "the same card, under a crescent moon"),
                ("jobs", "the kernel's live programs"),
                ("kill <pid>", "stop a program — the kernel reclaims it"),
                ("run x.py &", "a trailing & backgrounds a program"),
                ("scan [port]", "sweep the /24 on a port (default 80)"),
                ("knock <host> [ports]", "knock a host (default: the top doors)"),
                ("census", "knock every device on the neighborhood board"),
                ("decode <hex>", "raw advertisement bytes through the decoders"),
                ("company <id>", "who a company id belongs to"),
                ("port <n> [udp]", "what a port is for"),
                ("emcon [open|charlie|bravo|alpha|off]", "read or set the condition"),
                ("macro list | run <name>", "the macro library, run from here"),
                ("gauntlet", "run the gauntlet"),
                ("freedoom", "play freedoom — the big one"),
                ("journal [n]", "the house journal"),
                ("log [n]", "the flight recorder"),
                ("tomato list|throw|wipe", "the standing marks"),
                ("theme [name]", "list or switch the house theme"),
                ("haptics on|off", "the house's motor"),
                ("skelli <words>", "ask her — she answers in her room"),
                ("open <tab>", "go to a tab"),
                ("halt", "stop everything, now"),
            ]),
            ("the wire", [
                ("ping <host> [-c n]", "ICMP echo, by hand"),
                ("traceroute <host>", "the road, hop by hop"),
                ("dig [@server] <name> [type]", "ask DNS directly, wire format"),
                ("nslookup <name>", "A + AAAA, the short way"),
                ("host <name|ip>", "resolve — or reverse an address"),
                ("whois <domain>", "whose name is it"),
                ("curl [-I] [-H h] [-o f] <url>", "fetch a page, see its papers"),
                ("wget <url> [file]", "fetch it into the files"),
                ("nc [-u] [-z] <host> <port> [words]", "a raw conversation"),
                ("telnet <host> [port]", "the old handshake"),
                ("ifconfig", "this phone's interfaces"),
                ("arp", "the neighborhood board — our arp table"),
                ("netstat", "this house's doors and wires"),
                ("hostname", "who this phone is on the wire"),
            ]),
            ("pentest bench", [
                ("discover [a.b.c]", "who lives on the /24 — ICMP sweep"),
                ("portscan <host> [top|a-b|all|list]", "every door, banners too"),
                ("banner <host> <port>", "make a door introduce itself"),
                ("subdomains <domain>", "the names under a name"),
                ("revdns [a.b.c] [server]", "reverse-walk a /24"),
                ("nbstat <host>", "NetBIOS names and the adapter"),
                ("snmp <host> [community]", "ask the agent (default public)"),
                ("upnp", "who runs UPnP on this wire"),
                ("bonjour", "service announcements, censused"),
                ("cert <host> [port]", "audit the TLS papers"),
                ("webaudit <url>", "headers, cookies, posture"),
                ("methods <url>", "OPTIONS, and the TRACE question"),
                ("dirb <url>", "the path dictionary"),
                ("wol <mac>", "wake a sleeping machine"),
            ]),
            ("files — the console's own tree", [
                ("pwd · cd <dir>", "where you stand · move"),
                ("ls [-l] [path]", "list a directory"),
                ("tree [path]", "the whole branch, drawn"),
                ("cat <file>", "read a file (or a pipe)"),
                ("echo [-n] <words>", "say it back"),
                ("mkdir · touch <name>", "make a directory · a file"),
                ("cp · mv <a> <b>", "copy · move"),
                ("rm [-r] <path>", "remove"),
                ("head · tail [-n N]", "the first · last lines"),
                ("wc [file]", "lines, words, chars"),
                ("grep [-i] <pat> [file]", "lines that match"),
                ("find [path] [-name x]", "every file below"),
                ("stat <path>", "what a thing is"),
                ("sort [-rnuf] · uniq [-cdu]", "order the lines · drop repeated neighbours"),
                ("cut -d X -f 1,3 · tr A-Z a-z", "take fields apart · translate letters"),
                ("sed [-n] [-i] 's/a/b/g'", "the stream editor — addresses, d, p, the honest subset"),
                ("rev · tac · nl", "letters backwards · lines backwards · lines numbered"),
                ("diff <a> <b>", "what changed, hunk by hunk"),
                ("tee [-a] <file>", "the stream, copied to a file as it passes"),
                ("xargs [-n N] [-I {}] <cmd>", "run a command on what arrives"),
                ("file · strings · du [-h]", "what a thing is · its readable runs · its weight"),
                ("xxd · base64 · md5sum · sha256sum", "look at the bytes · carry them safely · their sums"),
                ("printf <fmt> [args] · seq [a [s]] b · yes", "say it precisely · count · say it forever (a thousand times)"),
                ("cal [month [year]]", "the month, drawn"),
                ("figlet [-f slim] <words>", "big letters — banner is the wire tool of the same name"),
                ("sleep <n>", "the room waits (300 seconds at most)"),
            ]),
            ("editors", [
                ("vim [file]", "the modal church — :help inside"),
                ("emacs [file]", "the chord church — M-x help inside"),
                ("nano [file]", "the plain church — ^G lists its keys"),
                ("edit [file]", "whichever $EDITOR names"),
            ]),
            ("code — the engine room", [
                ("js <code>", "JavaScript, compiled + run (node works too)"),
                ("linuxbox <applet>",
                 "a real linux userspace in wasm: ls cat echo pwd wc head tail cp mv rm mkdir touch env uname grep sleep"),
                ("run <file.wasm>",
                 "compiled webassembly, run as a kernel process — its syscalls are mediated, its memory is its own"),
                ("run <file.js>", "run a program from the files"),
                ("run <file.sh> · sh", "run a shell script"),
                ("python3 <file.py>", "the house's small python — python3 alone lists its edges"),
                ("run <file.py>", "run a python program"),
                ("NAME=value · export", "shell variables — $NAME ${NAME} $?"),
                ("a | b", "pipe one command through another"),
                ("cmd > file · >>", "write · append output to a file"),
                ("$(cmd)", "run it, use what it said"),
                ("a ; b · a && b", "then · then-if-it-worked"),
                ("cmd < file", "a file becomes the input"),
                ("cat <<EOF … EOF", "a here-doc — the lines between are the input; <<'EOF' keeps them literal"),
                ("$((x + 1))", "arithmetic in place — names, the full operator ladder, ?: too"),
                ("name() { …; }", "a function — call it by name; $1…$9, $#, $@ inside, local keeps its variables its own, return N leaves early"),
                ("for x in a b *.txt; do …; done", "the loop, spelled out — globs open here"),
                ("while test …; do …; done", "until runs the other way — the condition is any command, judged by its status"),
                ("if …; then …; elif …; else …; fi", "the fork in the road"),
                ("case $x in a|b) …;; *) …;; esac", "pattern by pattern — * ? [set] speak glob"),
                ("test <expr> · [ <expr> ]", "the judge: -e -f -d -s -z -n, = !=, -eq -ne -lt -le -gt -ge, ! -a -o"),
                ("require('./mod') — js", "javascript modules from the files beside the script, or a package name from /packages — circular loads come back partial, like node's"),
                ("setTimeout — js", "timers are the kernel's clock lent out: a run ends when its timers drain, its limit arrives, or the kernel speaks"),
            ]),
            ("packages", [
                ("pkg list", "installed + the bundled shelf"),
                ("pkg install <name>", "install a bundled package"),
                ("pkg install <url>", "install a package from the wire"),
                ("pkg remove <name>", "uninstall"),
                ("pkg commands", "the commands packages gave the shell"),
                ("pkg install grok · grok login · grok <words>", "ask xAI's grok from here — the house's own client (not the Rust CLI): SuperGrok sign-in via X, then questions with file + shell tools"),
            ]),
            ("graphics", [
                ("gfx demo", "the engine draws the house card"),
                ("gfx mandelbrot · plasma · stars", "computed pictures, filed as PNG"),
                ("gfx show <png>", "put a picture in the terminal"),
                ("view <file>", "pictures shown, text read"),
                ("wallpaper [stars|plasma|mandelbrot]", "the room's own wallpaper — generated, changeable"),
            ]),
            ("the room", [
                ("history", "what you have run"),
                ("date", "when it is"),
                ("which <cmd>", "where a command lives"),
                ("ver", "what this is"),
                ("clear", "wipe this screen"),
            ]),
        ]
        for (title, rows) in sections {
            emit("— " + title + " —", .sys)
            for (name, what) in rows {
                emit(pad(name, 30) + what, .sys)
            }
        }
    }

    private func pad(_ s: String, _ width: Int)
        -> String {
        s.count >= width
            ? s + " "
            : s + String(repeating: " ",
                         count: width - s.count)
    }

    // MARK: Processes

    private func processes() {
        let board = ProcessBoard.shared
        let procs = BlacksiteKernel.shared
            .snapshot()
        if board.active.isEmpty,
           procs.isEmpty {
            emit("no processes running.", .sys)
        }
        for entry in board.active {
            emit("● \(entry.label) — "
                 + entry.detail, .out)
        }
        for done in board.recent.prefix(6) {
            emit("○ \(done.label) — "
                 + done.summary, .sys)
        }
        for proc in procs where proc.isLive {
            emit("● pid \(proc.pid) · "
                 + "\(proc.name) — "
                 + kernelState(proc)
                 + " · \(Int(proc.elapsed))s",
                 .out)
        }
        for proc in procs.filter({
            !$0.isLive }).suffix(4) {
            emit("○ pid \(proc.pid) · "
                 + "\(proc.name) — "
                 + proc.exitNote, .sys)
        }
    }

    /// fastfetch and neofetch — the
    /// machine's calling card, drawn
    /// from live readings every time:
    /// the kernel's table, the theme on
    /// the walls, EMCON's exposure, the
    /// app's own footprint. Nothing here
    /// is remembered; all of it is read.
    private func fetchCommand(
        neofetch: Bool) {
        let kernel = BlacksiteKernel.shared
        let version = Bundle.main
            .infoDictionary?[
                "CFBundleShortVersionString"]
            as? String ?? "9.0c"
        let user = env["USER"] ?? "operator"
        let title = "\(user)@nightjar"
        let bold = "\u{1B}[1m"
        let cyan = "\u{1B}[1;36m"
        let off = "\u{1B}[0m"
        func field(_ name: String,
                   _ value: String) -> String {
            cyan + name + off + ": " + value
        }
        let center = SkelliCenter.shared
        let exposure = String(
            format: "%.0f",
            center.emcon.currentScore(
                mouth: center.mouth).value)
        var info: [String] = []
        info.append(bold + title + off)
        info.append(String(
            repeating: "─",
            count: title.count))
        info.append(field(
            "OS", "Blacksite \(version)"
            + " · the house kernel"))
        info.append(field(
            "Host", machineName()
            + " · iOS "
            + UIDevice.current.systemVersion))
        info.append(field(
            "Kernel", "blacksite · "
            + "\(kernel.liveCount) live · "
            + "\(kernel.totalSpawned) spawned"))
        info.append(field(
            "Uptime", uptimeText()))
        info.append(field(
            "Shell", "blacksite, the house shell"))
        info.append(field(
            "Theme",
            ThemeCenter.shared.current.name))
        info.append(field(
            "EMCON",
            EmconCondition.current.name
            + " · exposure " + exposure
            + " of 100"))
        info.append(field(
            "Packages",
            "\(BlacksiteJS.shared.installedPackages().count)"
            + " in /packages"))
        info.append(field(
            "Files",
            "\(BlacksiteFS.walk("/").count)"
            + " in the tree"))
        if let mb = footprintMB() {
            let totalGB = Double(
                ProcessInfo.processInfo
                    .physicalMemory)
                / 1_073_741_824
            info.append(field(
                "Memory",
                String(format: "%.0f MB "
                       + "resident of %.0f GB",
                       mb, totalGB)))
        }
        info.append(field(
            "CPU", machineName() + " · "
            + "\(ProcessInfo.processInfo.processorCount)"
            + " cores"))
        var normal = ""
        var bright = ""
        for i in 0..<8 {
            normal += "\u{1B}[\(40 + i)m   "
                + off
            bright += "\u{1B}[\(100 + i)m   "
                + off
        }
        info.append(normal)
        info.append(bright)

        let owl = [
            "  /\\_____/\\",
            " (  o   o  )",
            " ( ==  ^  == )",
            "  )        (",
            " (          )",
            " ( (  ) (  ) )",
            "  (__( )__( )__)",
        ]
        let crescent = [
            "     _____",
            "   /  ___)",
            "  (  (",
            "  (  (",
            "   \\  \\___)",
            "     \\_____)",
        ]
        let logo = neofetch ? crescent : owl
        let width = logo.map { $0.count }
            .max() ?? 0
        let rows = max(logo.count, info.count)
        for r in 0..<rows {
            let art = r < logo.count
                ? logo[r] : ""
            let padded = art + String(
                repeating: " ",
                count: width - art.count)
            let dressed = "\u{1B}[1;35m"
                + padded + off
            if r < info.count {
                emit(dressed + "  " + info[r])
            } else {
                emit(dressed)
            }
        }
    }

    /// The console's age, told the way
    /// uptime tells it.
    private func uptimeText() -> String {
        let secs = Int(Date()
            .timeIntervalSince(born))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// The hardware's own name for
    /// itself, read from uname.
    private func machineName() -> String {
        var sys = utsname()
        uname(&sys)
        let bytes = Mirror(
            reflecting: sys.machine)
            .children.map { child in
                (child.value as? Int8) ?? 0
            }
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        return String(decoding: bytes,
                      as: UTF8.self)
    }

    /// The app's resident footprint in
    /// megabytes, from the task itself —
    /// the memory line tells the truth
    /// or stays off the card.
    private func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>
                .size
                / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(
            to: &info) { ptr in
            ptr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(
                            TASK_VM_INFO),
                          $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return Double(info.phys_footprint)
            / 1_048_576
    }



    // MARK: Text commands — the
    // coreutils batch
    //
    // The stream tools: they read files
    // or the stage's stdin and write
    // lines, the pipe's whole covenant.
    // test/[ lives here too.

    private func splitLines(_ text: String)
        -> [String] {
        if text.isEmpty { return [] }
        var rows = text.components(
            separatedBy: "\n")
        if rows.last == "" {
            rows.removeLast()
        }
        return rows
    }

    /// Lines for a text command: its
    /// files in order, or the stage's
    /// stdin when it names none.
    private func textLines(
        _ files: [String],
        command: String) -> [String]? {
        if files.isEmpty {
            return splitLines(stageInput)
        }
        var out: [String] = []
        for file in files {
            guard let text = BlacksiteFS
                .readText(resolved(file))
            else {
                emit("\(command): \(file): "
                     + "no such file.",
                     .err)
                stageError = true
                return nil
            }
            out += splitLines(text)
        }
        return out
    }

    private func emitLines(_ rows: [String]) {
        for row in rows { emit(row) }
    }

    private func sortCommand(_ args: [String]) {
        let flags = flagLetters(args)
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        guard let rows = textLines(
            files, command: "sort")
        else { return }
        let numeric = flags.contains("n")
        let reverse = flags.contains("r")
        let fold = flags.contains("f")
        func key(_ row: String) -> String {
            fold ? row.lowercased() : row
        }
        func num(_ row: String) -> Double {
            let trimmed = row
                .trimmingCharacters(
                    in: .whitespaces)
            var text = ""
            var seenDot = false
            for ch in trimmed {
                if ch.isNumber {
                    text.append(ch)
                } else if ch == ".",
                          !seenDot {
                    seenDot = true
                    text.append(ch)
                } else if ch == "-",
                          text.isEmpty {
                    text.append(ch)
                } else { break }
            }
            return Double(text) ?? 0
        }
        var sorted = rows.enumerated()
            .sorted { a, b in
                if numeric {
                    let na = num(a.element)
                    let nb = num(b.element)
                    if na != nb {
                        return reverse
                            ? na > nb
                            : na < nb
                    }
                }
                let ka = key(a.element)
                let kb = key(b.element)
                if ka != kb {
                    return reverse
                        ? ka > kb
                        : ka < kb
                }
                return a.offset < b.offset
            }
            .map { $0.element }
        if flags.contains("u") {
            var seen = Set<String>()
            sorted = sorted.filter {
                seen.insert(key($0)).inserted
            }
        }
        emitLines(sorted)
    }

    private func uniqCommand(_ args: [String]) {
        let flags = flagLetters(args)
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        guard let rows = textLines(
            files, command: "uniq")
        else { return }
        let fold = flags.contains("i")
        func key(_ row: String) -> String {
            fold ? row.lowercased() : row
        }
        var out: [String] = []
        var i = 0
        while i < rows.count {
            var j = i + 1
            while j < rows.count,
                  key(rows[j]) == key(rows[i]) {
                j += 1
            }
            let runCount = j - i
            let duplicated = runCount > 1
            let keep = flags.contains("d")
                ? duplicated
                : flags.contains("u")
                    ? !duplicated
                    : true
            if keep {
                out.append(
                    flags.contains("c")
                        ? "\(runCount) \(rows[i])"
                        : rows[i])
            }
            i = j
        }
        emitLines(out)
    }

    private func cutCommand(_ args: [String]) {
        var delim = "\t"
        var spec: String? = nil
        var useChars = false
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("-d") {
                if arg.count > 2 {
                    delim = String(
                        arg.dropFirst(2))
                } else if i + 1 < args.count {
                    i += 1
                    delim = args[i]
                }
            } else if arg.hasPrefix("-f") {
                if arg.count > 2 {
                    spec = String(
                        arg.dropFirst(2))
                } else if i + 1 < args.count {
                    i += 1
                    spec = args[i]
                }
                useChars = false
            } else if arg.hasPrefix("-c") {
                if arg.count > 2 {
                    spec = String(
                        arg.dropFirst(2))
                } else if i + 1 < args.count {
                    i += 1
                    spec = args[i]
                }
                useChars = true
            } else if !arg.hasPrefix("-") {
                files.append(arg)
            }
            i += 1
        }
        guard let spec = spec else {
            emit("cut: name the fields "
                 + "(-f) or the columns "
                 + "(-c).", .err)
            stageError = true
            return
        }
        var wanted = Set<Int>()
        var openEnd: Int? = nil
        for piece in spec.split(
            separator: ",") {
            let part = String(piece)
            if part.contains("-") {
                let ends = part.split(
                    separator: "-",
                    omittingEmptySubsequences:
                        false)
                let lo = ends.first
                    .flatMap {
                        Int(String($0))
                    } ?? 1
                if ends.count > 1,
                   let hi = Int(
                    String(ends[1])) {
                    for n in lo...hi {
                        wanted.insert(n)
                    }
                } else {
                    openEnd = lo
                }
            } else if let n = Int(part) {
                wanted.insert(n)
            }
        }
        func picked(_ n: Int) -> Bool {
            wanted.contains(n)
                || (openEnd.map {
                    n >= $0
                } ?? false)
        }
        guard let rows = textLines(
            files, command: "cut")
        else { return }
        for row in rows {
            if useChars {
                let chars = Array(row)
                let out = chars.enumerated()
                    .filter {
                        picked($0.offset + 1)
                    }
                    .map { String($0.element) }
                emit(out.joined())
            } else if row.contains(delim) {
                let fields = row.components(
                    separatedBy: delim)
                let out = fields.enumerated()
                    .filter {
                        picked($0.offset + 1)
                    }
                    .map { $0.element }
                emit(out.joined(
                    separator: delim))
            } else {
                emit(row)
            }
        }
    }

    /// Expand a tr set: ranges, escapes,
    /// and the common classes.
    private func trSet(_ spec: String)
        -> [Character] {
        let chars = Array(spec)
        var out: [Character] = []
        var i = 0
        let classes: [String: String] = [
            "upper": "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "lower": "abcdefghijklmnopqrstuvwxyz",
            "digit": "0123456789",
            "alpha": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
            "space": " \t\n",
        ]
        while i < chars.count {
            if chars[i] == "[",
               i + 2 < chars.count,
               chars[i + 1] == ":" {
                var j = i + 2
                var name = ""
                while j + 1 < chars.count,
                      !(chars[j] == ":"
                        && chars[j + 1] == "]") {
                    name.append(chars[j])
                    j += 1
                }
                if let members = classes[name] {
                    out += Array(members)
                    i = j + 2
                    continue
                }
            }
            if chars[i] == "\\",
               i + 1 < chars.count {
                let esc = chars[i + 1]
                let mapped: Character =
                    esc == "n" ? "\n"
                    : esc == "t" ? "\t"
                    : esc == "r" ? "\r"
                    : esc
                if i + 3 < chars.count,
                   chars[i + 2] == "-",
                   chars[i + 3] != "]" {
                    let end = chars[i + 3]
                    if let lo = mapped
                        .unicodeScalars.first,
                       let hi = end
                        .unicodeScalars.first,
                       lo.value <= hi.value {
                        for v in lo.value...hi
                            .value {
                            if let scalar =
                                UnicodeScalar(v) {
                                out.append(
                                    Character(
                                        scalar))
                            }
                        }
                        i += 4
                        continue
                    }
                }
                out.append(mapped)
                i += 2
                continue
            }
            if i + 2 < chars.count,
               chars[i + 1] == "-" {
                let end = chars[i + 2]
                if let lo = chars[i]
                    .unicodeScalars.first,
                   let hi = end
                    .unicodeScalars.first,
                   lo.value <= hi.value {
                    for v in lo.value...hi
                        .value {
                        if let scalar =
                            UnicodeScalar(v) {
                            out.append(
                                Character(scalar))
                        }
                    }
                    i += 3
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private func trCommand(_ args: [String]) {
        let flags = flagLetters(args)
        let sets = args.filter {
            !$0.hasPrefix("-")
        }
        guard !sets.isEmpty else {
            emit("tr: name a set.",
                 .err)
            stageError = true
            return
        }
        let deleting = flags.contains("d")
        let squeezing = flags.contains("s")
        let from = trSet(sets[0])
        let to: [Character] = sets.count > 1
            ? trSet(sets[1]) : []
        let fromSet = Set(from)
        var out = ""
        if deleting {
            for ch in stageInput
                where !fromSet.contains(ch) {
                out.append(ch)
            }
        } else if !to.isEmpty {
            var map: [Character: Character] =
                [:]
            for (index, ch) in from
                .enumerated() {
                map[ch] = to[min(
                    index, to.count - 1)]
            }
            for ch in stageInput {
                out.append(map[ch] ?? ch)
            }
        } else {
            out = stageInput
        }
        if squeezing {
            let squeezeSet = Set(
                deleting || to.isEmpty
                    ? from : to)
            var squeezed = ""
            var last: Character? = nil
            for ch in out {
                if ch == last,
                   squeezeSet.contains(ch) {
                    continue
                }
                squeezed.append(ch)
                last = ch
            }
            out = squeezed
        }
        emitLines(splitLines(out))
    }

    private func revCommand(_ args: [String]) {
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        guard let rows = textLines(
            files, command: "rev")
        else { return }
        for row in rows {
            emit(String(row.reversed()))
        }
    }

    private func tacCommand(_ args: [String]) {
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        guard let rows = textLines(
            files, command: "tac")
        else { return }
        emitLines(rows.reversed())
    }

    private func nlCommand(_ args: [String]) {
        var width = 6
        let files = args.filter {
            arg in
            if arg.hasPrefix("-w"),
               let n = Int(
                arg.dropFirst(2)) {
                width = n
                return false
            }
            return !arg.hasPrefix("-")
        }
        guard let rows = textLines(
            files, command: "nl")
        else { return }
        var n = 0
        for row in rows {
            if row.isEmpty {
                emit("")
            } else {
                n += 1
                let num = String(n)
                let pad = String(repeating: " ",
                    count: max(0, width
                        - num.count))
                emit("\(pad)\(num)\t\(row)")
            }
        }
    }

    // MARK: sed — the stream editor,
    // the honest subset

    private struct SedEdit {
        var addressLine: Int? = nil
        var addressLast = false
        var addressRegex:
            NSRegularExpression? = nil
        var hasAddress = false
        var negate = false
        var command: Character = "s"
        var regex: NSRegularExpression? =
            nil
        var replacement = ""
        var all = false
        var nth = 1
        var printToo = false
    }

    /// Split a sed program into its
    /// edits on ';', respecting /…/
    /// addresses and s<d>…<d>…<d> spans.
    private func sedSplit(_ script: String)
        -> [String] {
        let chars = Array(script)
        var parts: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == ";" {
                parts.append(current)
                current = ""
                i += 1
                continue
            }
            if ch == "/" {
                current.append(ch)
                i += 1
                while i < chars.count {
                    let c = chars[i]
                    current.append(c)
                    if c == "\\",
                       i + 1 < chars.count {
                        i += 1
                        current.append(chars[i])
                    } else if c == "/" {
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }
            if ch == "s",
               i + 1 < chars.count,
               current.isEmpty
                || current.hasSuffix("!")
                || current.last?.isNumber
                    == true
                || current.hasSuffix("$") {
                let delim = chars[i + 1]
                current.append(ch)
                current.append(delim)
                i += 2
                var spans = 0
                while i < chars.count,
                      spans < 2 {
                    let c = chars[i]
                    current.append(c)
                    if c == "\\",
                       i + 1 < chars.count {
                        i += 1
                        current.append(chars[i])
                    } else if c == delim {
                        spans += 1
                        i += 1
                        break
                    }
                    i += 1
                }
                continue
            }
            current.append(ch)
            i += 1
        }
        parts.append(current)
        return parts.filter {
            !$0.trimmingCharacters(
                in: .whitespaces).isEmpty
        }
    }

    private func sedTemplate(
        _ raw: String) -> String {
        var out = ""
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\",
               i + 1 < chars.count {
                let next = chars[i + 1]
                if next.isNumber {
                    out.append("$")
                    out.append(next)
                } else if next == "&" {
                    out.append("&")
                } else if next == "\\" {
                    out.append("\\")
                } else {
                    out.append(next)
                }
                i += 2
                continue
            }
            if ch == "&" {
                out += "$0"
                i += 1
                continue
            }
            if ch == "$" {
                out += "$$"
                i += 1
                continue
            }
            out.append(ch)
            i += 1
        }
        return out
    }

    private func parseSedEdit(
        _ text: String) -> SedEdit? {
        var edit = SedEdit()
        let chars = Array(text)
        var i = 0
        func skipSpaces() {
            while i < chars.count,
                  chars[i] == " " {
                i += 1
            }
        }
        skipSpaces()
        if i < chars.count,
           chars[i].isNumber {
            var num = ""
            while i < chars.count,
                  chars[i].isNumber {
                num.append(chars[i])
                i += 1
            }
            edit.addressLine = Int(num)
            edit.hasAddress = true
        } else if i < chars.count,
                  chars[i] == "$" {
            edit.addressLast = true
            edit.hasAddress = true
            i += 1
        } else if i < chars.count,
                  chars[i] == "/" {
            i += 1
            var pat = ""
            while i < chars.count {
                let c = chars[i]
                if c == "\\",
                   i + 1 < chars.count {
                    pat.append(c)
                    pat.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "/" { break }
                pat.append(c)
                i += 1
            }
            i += 1
            edit.addressRegex = try?
                NSRegularExpression(
                    pattern: pat)
            edit.hasAddress = true
        }
        skipSpaces()
        if i < chars.count, chars[i] == "!" {
            edit.negate = true
            i += 1
        }
        skipSpaces()
        guard i < chars.count else {
            return nil
        }
        let cmd = chars[i]
        edit.command = cmd
        i += 1
        if cmd == "d" || cmd == "p" {
            return edit
        }
        guard cmd == "s",
              i < chars.count else {
            return nil
        }
        let delim = chars[i]
        i += 1
        var pat = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\",
               i + 1 < chars.count {
                pat.append(c)
                pat.append(chars[i + 1])
                i += 2
                continue
            }
            if c == delim { break }
            pat.append(c)
            i += 1
        }
        i += 1
        var repl = ""
        while i < chars.count {
            let c = chars[i]
            if c == "\\",
               i + 1 < chars.count {
                repl.append(c)
                repl.append(chars[i + 1])
                i += 2
                continue
            }
            if c == delim { break }
            repl.append(c)
            i += 1
        }
        i += 1
        var flags = ""
        while i < chars.count {
            flags.append(chars[i])
            i += 1
        }
        edit.all = flags.contains("g")
        edit.printToo = flags.contains("p")
        let ignoreCase = flags.contains("i")
        if let n = flags.first(where: {
            $0.isNumber
        }).flatMap({ Int(String($0)) }) {
            edit.nth = n
        }
        edit.regex = try? NSRegularExpression(
            pattern: pat,
            options: ignoreCase
                ? [.caseInsensitive] : [])
        edit.replacement = sedTemplate(repl)
        return edit.regex != nil ? edit : nil
    }

    private func sedCommand(_ args: [String]) {
        var suppress = false
        var inPlace = false
        var scripts: [String] = []
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-n" {
                suppress = true
            } else if arg == "-i" {
                inPlace = true
            } else if arg == "-e",
                      i + 1 < args.count {
                i += 1
                scripts.append(args[i])
            } else if arg.hasPrefix("-"),
                      arg.count > 1,
                      scripts.isEmpty,
                      files.isEmpty,
                      arg.allSatisfy({
                          "nie".contains($0)
                              || $0 == "-"
                      }) {
                if arg.contains("n") {
                    suppress = true
                }
                if arg.contains("i") {
                    inPlace = true
                }
            } else if scripts.isEmpty {
                scripts.append(arg)
            } else {
                files.append(arg)
            }
            i += 1
        }
        guard !scripts.isEmpty else {
            emit("sed: a script is the "
                 + "whole job.", .err)
            stageError = true
            return
        }
        var edits: [SedEdit] = []
        for script in scripts {
            for piece in sedSplit(script) {
                guard let edit = parseSedEdit(
                    piece) else {
                    emit("sed: cannot parse "
                         + "'\(piece)'.",
                         .err)
                    stageError = true
                    return
                }
                edits.append(edit)
            }
        }
        var sources: [(name: String?,
                       rows: [String])] = []
        if files.isEmpty {
            sources.append(
                (nil, splitLines(stageInput)))
        } else {
            for file in files {
                guard let text = BlacksiteFS
                    .readText(resolved(file))
                else {
                    emit("sed: \(file): no "
                         + "such file.", .err)
                    stageError = true
                    return
                }
                sources.append(
                    (file, splitLines(text)))
            }
        }
        if inPlace, files.isEmpty {
            emit("sed: -i needs files.",
                 .err)
            stageError = true
            return
        }
        for source in sources {
            var out: [String] = []
            for (index, original)
                in source.rows.enumerated() {
                var line = original
                var deleted = false
                var prints: [String] = []
                for edit in edits {
                    var addressed = true
                    if edit.hasAddress {
                        if let n = edit
                            .addressLine {
                            addressed =
                                index + 1 == n
                        } else if edit
                            .addressLast {
                            addressed =
                                index == source
                                    .rows.count - 1
                        } else if let regex =
                            edit.addressRegex {
                            addressed = regex
                                .firstMatch(
                                    in: line,
                                    range:
                                        NSRange(
                                            location:
                                                0,
                                            length:
                                                line
                                                .utf16
                                                .count))
                                != nil
                        }
                        if edit.negate {
                            addressed =
                                !addressed
                        }
                    }
                    if !addressed { continue }
                    switch edit.command {
                    case "d":
                        deleted = true
                    case "p":
                        prints.append(line)
                    case "s":
                        guard let regex = edit
                            .regex else {
                            continue
                        }
                        let range = NSRange(
                            location: 0,
                            length: line
                                .utf16.count)
                        if edit.all {
                            line = regex
                                .stringByReplacingMatches(
                                    in: line,
                                    range: range,
                                    withTemplate:
                                        edit
                                        .replacement)
                        } else {
                            let matches = regex
                                .matches(
                                    in: line,
                                    range: range)
                            if matches.count
                                >= edit.nth {
                                let match =
                                    matches[
                                        edit.nth
                                        - 1]
                                let replaced =
                                    regex
                                    .replacementString(
                                        for: match,
                                        in: line,
                                        offset: 0,
                                        template:
                                            edit
                                            .replacement)
                                if let r =
                                    Range(
                                        match
                                            .range,
                                        in: line) {
                                    line
                                        .replaceSubrange(
                                            r,
                                            with:
                                                replaced)
                                }
                            }
                        }
                        if edit.printToo {
                            prints.append(line)
                        }
                    default:
                        break
                    }
                    if deleted { break }
                }
                if !deleted {
                    if !suppress {
                        out.append(line)
                    }
                    out += prints
                }
            }
            if inPlace,
               let name = source.name {
                let body = out.isEmpty
                    ? ""
                    : out.joined(
                        separator: "\n") + "\n"
                _ = BlacksiteFS.writeText(
                    resolved(name), text: body)
            } else {
                emitLines(out)
            }
        }
    }

    // MARK: test — [ … ] and test

    private struct TestParser {
        let tokens: [String]
        let cwd: String
        var i = 0

        mutating func parseOr() -> Bool {
            var result = parseAnd()
            while peek() == "-o" {
                i += 1
                let rhs = parseAnd()
                result = result || rhs
            }
            return result
        }

        mutating func parseAnd() -> Bool {
            var result = parseUnary()
            while peek() == "-a" {
                i += 1
                let rhs = parseUnary()
                result = result && rhs
            }
            return result
        }

        mutating func parseUnary() -> Bool {
            if peek() == "!" {
                i += 1
                return !parseUnary()
            }
            if peek() == "(" {
                i += 1
                let inner = parseOr()
                if peek() == ")" { i += 1 }
                return inner
            }
            return parsePrimary()
        }

        private func peek() -> String? {
            i < tokens.count ? tokens[i] : nil
        }

        private func path(_ raw: String)
            -> String {
            BlacksiteFS.normalize(
                raw, cwd: cwd)
        }

        mutating func parsePrimary() -> Bool {
            guard let head = peek() else {
                return false
            }
            let unaryFile: Set<String> = [
                "-e", "-f", "-d", "-s",
                "-r", "-w", "-x",
            ]
            if unaryFile.contains(head),
               i + 1 < tokens.count {
                let target = path(tokens[i + 1])
                i += 2
                switch head {
                case "-e", "-r", "-w", "-x":
                    return BlacksiteFS
                        .exists(target)
                case "-f":
                    return BlacksiteFS
                        .exists(target)
                        && !BlacksiteFS
                            .isDirectory(target)
                case "-d":
                    return BlacksiteFS
                        .isDirectory(target)
                case "-s":
                    return (BlacksiteFS
                        .fileSize(target)
                        ?? 0) > 0
                default:
                    return false
                }
            }
            if head == "-z"
                || head == "-n",
               i + 1 < tokens.count {
                let value = tokens[i + 1]
                i += 2
                return head == "-z"
                    ? value.isEmpty
                    : !value.isEmpty
            }
            if i + 2 < tokens.count {
                let op = tokens[i + 1]
                let lhs = tokens[i]
                let rhs = tokens[i + 2]
                let intOps: Set<String> = [
                    "-eq", "-ne", "-lt",
                    "-le", "-gt", "-ge",
                ]
                if op == "=" || op == "=="
                    || op == "!=" {
                    i += 3
                    return op == "!="
                        ? lhs != rhs
                        : lhs == rhs
                }
                if intOps.contains(op) {
                    let a = Int(lhs) ?? 0
                    let b = Int(rhs) ?? 0
                    i += 3
                    switch op {
                    case "-eq": return a == b
                    case "-ne": return a != b
                    case "-lt": return a < b
                    case "-le": return a <= b
                    case "-gt": return a > b
                    default: return a >= b
                    }
                }
            }
            i += 1
            return !head.isEmpty
        }
    }

    private func testCommand(
        _ args: [String], bracket: Bool) {
        if args.isEmpty {
            stageError = true
            return
        }
        var parser = TestParser(
            tokens: args, cwd: cwd)
        let result = parser.parseOr()
        stageError = !result
    }

    // MARK: More utilities — diff,
    // tee, xargs, seq, encodings, sums,
    // dumps, printf, sizes, types,
    // strings, the calendar, yes,
    // and big letters

    private func textCommand(
        _ head: String, _ args: [String]) {
        switch head {
        case "sort": sortCommand(args)
        case "uniq": uniqCommand(args)
        case "cut": cutCommand(args)
        case "tr": trCommand(args)
        case "sed": sedCommand(args)
        case "rev": revCommand(args)
        case "tac": tacCommand(args)
        case "nl": nlCommand(args)
        case "diff": diffCommand(args)
        case "tee": teeCommand(args)
        case "xargs": xargsCommand(args)
        case "seq": seqCommand(args)
        case "base64": base64Command(args)
        case "md5sum", "sha256sum":
            hashCommand(head, args)
        case "xxd": xxdCommand(args)
        case "sleep": sleepCommand(args)
        case "printf": printfCommand(args)
        case "du": duCommand(args)
        case "file": fileCommand(args)
        case "strings":
            stringsCommand(args)
        case "cal": calCommand(args)
        case "yes": yesCommand(args)
        case "figlet", "bigtext":
            figletCommand(args)
        default: break
        }
    }

    private func diffCommand(_ args: [String]) {
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        let a: [String]
        let b: [String]
        let aName: String
        let bName: String
        if files.count >= 2 {
            guard let ta = BlacksiteFS
                    .readText(
                        resolved(files[0])),
                  let tb = BlacksiteFS
                    .readText(
                        resolved(files[1]))
            else {
                emit("diff: a file named "
                     + "cannot be read.",
                     .err)
                stageError = true
                return
            }
            a = splitLines(ta)
            b = splitLines(tb)
            aName = files[0]
            bName = files[1]
        } else if files.count == 1 {
            guard let ta = BlacksiteFS
                .readText(resolved(files[0]))
            else {
                emit("diff: \(files[0]): "
                     + "no such file.",
                     .err)
                stageError = true
                return
            }
            a = splitLines(ta)
            b = splitLines(stageInput)
            aName = files[0]
            bName = "stdin"
        } else {
            emit("diff: name two texts, "
                 + "or one and a pipe.",
                 .err)
            stageError = true
            return
        }
        if a == b { return }
        guard (a.count + 1) * (b.count + 1)
                <= 9_000_000 else {
            emit("diff: too large for "
                 + "this room.", .err)
            stageError = true
            return
        }
        var table = [[Int]](
            repeating: [Int](
                repeating: 0,
                count: b.count + 1),
            count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(
                from: a.count - 1,
                through: 0, by: -1) {
                for j in stride(
                    from: b.count - 1,
                    through: 0, by: -1) {
                    table[i][j] = a[i] == b[j]
                        ? table[i + 1][j + 1]
                            + 1
                        : max(
                            table[i + 1][j],
                            table[i][j + 1])
                }
            }
        }
        enum Op {
            case same(String)
            case del(String)
            case add(String)
        }
        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                ops.append(.same(a[i]))
                i += 1
                j += 1
            } else if table[i + 1][j]
                        >= table[i][j + 1] {
                ops.append(.del(a[i]))
                i += 1
            } else {
                ops.append(.add(b[j]))
                j += 1
            }
        }
        while i < a.count {
            ops.append(.del(a[i]))
            i += 1
        }
        while j < b.count {
            ops.append(.add(b[j]))
            j += 1
        }
        var changeAt = Set<Int>()
        for (index, op) in ops.enumerated() {
            if case .same = op { continue }
            changeAt.insert(index)
        }
        var hunks: [(Int, Int)] = []
        for index in changeAt.sorted() {
            let lo = max(0, index - 3)
            let hi = min(ops.count - 1,
                         index + 3)
            if let last = hunks.last,
               lo <= last.1 + 1 {
                hunks[hunks.count - 1] =
                    (last.0, max(last.1, hi))
            } else {
                hunks.append((lo, hi))
            }
        }
        emit("--- \(aName)")
        emit("+++ \(bName)")
        for (lo, hi) in hunks {
            var aBefore = 0
            var bBefore = 0
            for k in 0..<lo {
                switch ops[k] {
                case .same: 
                    aBefore += 1
                    bBefore += 1
                case .del: aBefore += 1
                case .add: bBefore += 1
                }
            }
            var aCount = 0
            var bCount = 0
            for k in lo...hi {
                switch ops[k] {
                case .same:
                    aCount += 1
                    bCount += 1
                case .del: aCount += 1
                case .add: bCount += 1
                }
            }
            emit("@@ -\(aBefore + 1),"
                 + "\(aCount) "
                 + "+\(bBefore + 1),"
                 + "\(bCount) @@")
            for k in lo...hi {
                switch ops[k] {
                case .same(let line):
                    emit(" " + line)
                case .del(let line):
                    emit("-" + line)
                case .add(let line):
                    emit("+" + line)
                }
            }
        }
        stageError = true
    }

    private func teeCommand(_ args: [String]) {
        let append = flagLetters(args)
            .contains("a")
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        var body = stageInput
        if !body.isEmpty,
           !body.hasSuffix("\n") {
            body += "\n"
        }
        for file in files {
            if !BlacksiteFS.writeText(
                resolved(file), text: body,
                append: append) {
                emit("tee: \(file): cannot "
                     + "write there.", .err)
                stageError = true
            }
        }
        emitLines(splitLines(stageInput))
    }

    private func shellQuote(_ token: String)
        -> String {
        let safe = token.allSatisfy {
            $0.isLetter || $0.isNumber
                || "_./:=+-".contains($0)
        }
        if safe, !token.isEmpty {
            return token
        }
        return "'" + token
            .replacingOccurrences(
                of: "'", with: "'\\''") + "'"
    }

    private func xargsCommand(_ args: [String]) {
        var batch = Int.max
        var replace: String? = nil
        var base: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-n",
               i + 1 < args.count {
                i += 1
                batch = Int(args[i]) ?? 1
            } else if arg.hasPrefix("-n"),
                      arg.count > 2 {
                batch = Int(
                    arg.dropFirst(2)) ?? 1
            } else if arg == "-I",
                      i + 1 < args.count {
                i += 1
                replace = args[i]
            } else if arg.hasPrefix("-I"),
                      arg.count > 2 {
                replace = String(
                    arg.dropFirst(2))
            } else if arg.hasPrefix("-"),
                      base.isEmpty {
                // other flags pass quietly
            } else {
                base = Array(args[i...])
                break
            }
            i += 1
        }
        if base.isEmpty { base = ["echo"] }
        let items = stageInput
            .split(whereSeparator: {
                $0 == " " || $0 == "\t"
                    || $0 == "\n"
            })
            .map(String.init)
        guard !items.isEmpty else { return }
        var runs = 0
        if let mark = replace {
            for item in items {
                if runs >= 1000 { break }
                runs += 1
                var tokens = base.map {
                    $0.replacingOccurrences(
                        of: mark, with: item)
                }
                if !base.contains(where: {
                    $0.contains(mark)
                }) {
                    tokens.append(item)
                }
                execLine(
                    tokens.map(shellQuote)
                        .joined(separator: " "),
                    stdin: "")
                if returnFlag { break }
            }
            return
        }
        var index = 0
        while index < items.count {
            if runs >= 1000 { break }
            runs += 1
            let slice = items[
                index..<min(
                    index + max(1, batch),
                    items.count)]
            let tokens = base
                + Array(slice)
            execLine(
                tokens.map(shellQuote)
                    .joined(separator: " "),
                stdin: "")
            if returnFlag { break }
            index += slice.count
        }
    }

    private func seqCommand(_ args: [String]) {
        let nums = args.compactMap(Double.init)
        guard !nums.isEmpty else {
            emit("seq: numbers are the "
                 + "whole job.", .err)
            stageError = true
            return
        }
        let first: Double
        let step: Double
        let last: Double
        if nums.count == 1 {
            first = 1
            step = 1
            last = nums[0]
        } else if nums.count == 2 {
            first = nums[0]
            step = 1
            last = nums[1]
        } else {
            first = nums[0]
            step = nums[1]
            last = nums[2]
        }
        guard step != 0 else {
            emit("seq: a step of zero "
                 + "goes nowhere.", .err)
            stageError = true
            return
        }
        let integral = first == first
            .rounded()
            && step == step.rounded()
            && last == last.rounded()
        var value = first
        var count = 0
        while step > 0
                ? value <= last
                : value >= last {
            if count >= 100000 { break }
            count += 1
            emit(integral
                 ? String(Int(value))
                 : String(format: "%g",
                          value))
            value += step
        }
    }

    private func base64Command(
        _ args: [String]) {
        let decode = flagLetters(args)
            .contains("d")
            || args.contains("-D")
            || args.contains("--decode")
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        let text: String
        if let file = files.first {
            guard let read = BlacksiteFS
                .readText(resolved(file))
            else {
                emit("base64: \(file): no "
                     + "such file.", .err)
                stageError = true
                return
            }
            text = read
        } else {
            text = stageInput
        }
        if decode {
            let cleaned = text
                .components(separatedBy:
                    .whitespacesAndNewlines)
                .joined()
            guard let data = Data(
                base64Encoded: cleaned),
                  let plain = String(
                    data: data,
                    encoding: .utf8)
            else {
                emit("base64: that is not "
                     + "base64, or not text "
                     + "once decoded.",
                     .err)
                stageError = true
                return
            }
            emitLines(splitLines(plain))
        } else {
            let encoded = Data(text.utf8)
                .base64EncodedString()
            var index = encoded.startIndex
            while index < encoded.endIndex {
                let end = encoded.index(
                    index, offsetBy: 76,
                    limitedBy:
                        encoded.endIndex)
                    ?? encoded.endIndex
                emit(String(
                    encoded[index..<end]))
                index = end
            }
        }
    }

    private func hashCommand(
        _ head: String, _ args: [String]) {
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        func digest(_ data: Data) -> String {
            if head == "md5sum" {
                return Insecure.MD5
                    .hash(data: data)
                    .map {
                        String(format: "%02x",
                               $0)
                    }
                    .joined()
            }
            return SHA256.hash(data: data)
                .map {
                    String(format: "%02x", $0)
                }
                .joined()
        }
        if files.isEmpty {
            emit("\(digest(Data(stageInput.utf8)))"
                 + "  -")
            return
        }
        for file in files {
            guard let data = BlacksiteFS
                .readData(resolved(file))
            else {
                emit("\(head): \(file): no "
                     + "such file.", .err)
                stageError = true
                continue
            }
            emit("\(digest(data))  \(file)")
        }
    }

    private func xxdCommand(_ args: [String]) {
        let files = args.filter {
            !$0.hasPrefix("-")
        }
        let data: Data
        if let file = files.first {
            guard let read = BlacksiteFS
                .readData(resolved(file))
            else {
                emit("xxd: \(file): no "
                     + "such file.", .err)
                stageError = true
                return
            }
            data = read
        } else {
            data = Data(stageInput.utf8)
        }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let row = Array(bytes[
                offset..<min(offset + 16,
                             bytes.count)])
            var hexParts: [String] = []
            for pair in stride(
                from: 0, to: 16, by: 2) {
                var piece = ""
                for k in 0..<2 {
                    let at = pair + k
                    piece += at < row.count
                        ? String(format: "%02x",
                                 row[at])
                        : "  "
                }
                hexParts.append(piece)
            }
            let gutter = row.map {
                byte -> String in
                (byte >= 32 && byte < 127)
                    ? String(Character(
                        UnicodeScalar(byte)))
                    : "."
            }.joined()
            let hex = hexParts.joined(
                separator: " ")
            let padded = hex.padding(
                toLength: 39,
                withPad: " ",
                startingAt: 0)
            emit(String(
                format: "%08x: %@  |%@|",
                offset, padded, gutter))
            offset += 16
        }
    }

    private func sleepCommand(_ args: [String]) {
        guard let seconds = args.first
                .flatMap(Double.init)
        else {
            emit("sleep: name the "
                 + "seconds.", .err)
            stageError = true
            return
        }
        Thread.sleep(forTimeInterval:
            min(max(0, seconds), 300))
    }

    private func printfCommand(
        _ args: [String]) {
        guard let format = args.first
        else {
            emit("printf: a format is "
                 + "the whole job.", .err)
            stageError = true
            return
        }
        let values = Array(args.dropFirst())
        var out = ""
        var valueIndex = 0
        var firstPass = true
        while firstPass
                || valueIndex < values.count {
            firstPass = false
            var consumed = false
            let chars = Array(format)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if ch == "\\",
                   i + 1 < chars.count {
                    let esc = chars[i + 1]
                    switch esc {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "\\": out.append("\\")
                    case "0": out.append("\u{0}")
                    default: out.append(esc)
                    }
                    i += 2
                    continue
                }
                if ch == "%",
                   i + 1 < chars.count {
                    var j = i + 1
                    var flags = ""
                    while j < chars.count,
                          "-+ #0".contains(
                            chars[j]) {
                        flags.append(chars[j])
                        j += 1
                    }
                    var widthText = ""
                    while j < chars.count,
                          chars[j].isNumber {
                        widthText.append(
                            chars[j])
                        j += 1
                    }
                    var precision: Int? = nil
                    if j < chars.count,
                       chars[j] == "." {
                        j += 1
                        var p = ""
                        while j < chars.count,
                              chars[j].isNumber {
                            p.append(chars[j])
                            j += 1
                        }
                        precision = Int(p) ?? 0
                    }
                    guard j < chars.count
                    else { break }
                    let conv = chars[j]
                    let value = valueIndex
                        < values.count
                        ? values[valueIndex]
                        : ""
                    if conv != "%" {
                        valueIndex += 1
                        consumed = true
                    }
                    out += printfValue(
                        conv: conv, value: value,
                        flags: flags,
                        width: Int(widthText)
                            ?? 0,
                        precision: precision)
                    i = j + 1
                    continue
                }
                out.append(ch)
                i += 1
            }
            if !consumed { break }
        }
        emitLines(splitLines(out))
    }

    private func printfValue(
        conv: Character, value: String,
        flags: String, width: Int,
        precision: Int?) -> String {
        func pad(_ body: String,
                 zeroOK: Bool = false)
            -> String {
            if body.count >= width {
                return body
            }
            let fill = zeroOK
                && flags.contains("0")
                && !flags.contains("-")
                ? "0" : " "
            let padding = String(
                repeating: fill,
                count: width - body.count)
            if flags.contains("-") {
                return body + padding
            }
            if fill == "0",
               body.hasPrefix("-") {
                return "-" + padding
                    + String(body.dropFirst())
            }
            return padding + body
        }
        switch conv {
        case "%":
            return "%"
        case "s":
            var body = value
            if let p = precision,
               body.count > p {
                body = String(
                    body.prefix(p))
            }
            return pad(body)
        case "d", "i":
            let n = Int(value) ?? 0
            var body = String(abs(n))
            if let p = precision {
                body = String(
                    repeating: "0",
                    count: max(0, p
                        - body.count)) + body
            }
            if n < 0 {
                body = "-" + body
            } else if flags.contains("+") {
                body = "+" + body
            } else if flags.contains(" ") {
                body = " " + body
            }
            return precision == nil
                ? pad(body, zeroOK: true)
                : pad(body)
        case "u":
            let n = Int(value) ?? 0
            let body = n < 0
                ? String(UInt64(
                    bitPattern: Int64(n)))
                : String(n)
            return pad(body, zeroOK: true)
        case "x", "X", "o":
            let n = Int(value) ?? 0
            let u = n < 0
                ? UInt64(bitPattern:
                    Int64(n))
                : UInt64(n)
            var body = String(
                u, radix: conv == "o"
                    ? 8 : 16)
            if conv == "X" {
                body = body.uppercased()
            }
            if flags.contains("#"),
               u != 0, conv != "o" {
                body = (conv == "X"
                        ? "0X" : "0x") + body
            }
            return pad(body, zeroOK: true)
        case "c":
            return pad(String(
                value.prefix(1)))
        case "f", "F":
            let d = Double(value) ?? 0
            return pad(String(
                format: "%.\(precision ?? 6)f",
                d), zeroOK: true)
        case "e", "E", "g", "G":
            let d = Double(value) ?? 0
            let body = String(
                format: "%\(conv)",
                d)
            return pad(body, zeroOK: true)
        default:
            return "%" + String(conv)
        }
    }

    private func duCommand(_ args: [String]) {
        let flags = flagLetters(args)
        let human = flags.contains("h")
        let summary = flags.contains("s")
        let targets = args.filter {
            !$0.hasPrefix("-")
        }
        func sizeText(_ bytes: Int)
            -> String {
            if !human {
                return String((bytes + 1023)
                    / 1024)
            }
            let units = ["B", "K", "M", "G"]
            var value = Double(bytes)
            var unit = 0
            while value >= 1024,
                  unit < units.count - 1 {
                value /= 1024
                unit += 1
            }
            if unit == 0 {
                return "\(bytes)B"
            }
            return value < 10
                ? String(format: "%.1f",
                         value) + units[unit]
                : "\(Int(value.rounded()))"
                    + units[unit]
        }
        for target in (targets.isEmpty
                       ? [cwd] : targets) {
            let path = resolved(target)
            guard BlacksiteFS.exists(path)
            else {
                emit("du: \(target): no "
                     + "such place.", .err)
                stageError = true
                continue
            }
            if !BlacksiteFS.isDirectory(path) {
                emit("\(sizeText(BlacksiteFS.fileSize(path) ?? 0))\t\(target)")
                continue
            }
            let all = BlacksiteFS.walk(path)
            var dirTotals: [(String, Int)] =
                []
            var total = 0
            for entry in [path] + all
                where BlacksiteFS
                    .isDirectory(entry) {
                var sum = 0
                for member in all
                    where member.hasPrefix(
                        entry + "/")
                        && !BlacksiteFS
                            .isDirectory(
                                member) {
                    sum += BlacksiteFS
                        .fileSize(member)
                        ?? 0
                }
                dirTotals.append((entry, sum))
                if entry == path {
                    total = sum
                }
            }
            if !summary {
                for (dir, sum) in dirTotals
                    .sorted(by: {
                        $0.0.count > $1.0.count
                    })
                    where dir != path {
                    emit("\(sizeText(sum))"
                         + "\t\(dir)")
                }
            }
            emit("\(sizeText(total))"
                 + "\t\(target)")
        }
    }

    private func fileCommand(_ args: [String]) {
        let targets = args.filter {
            !$0.hasPrefix("-")
        }
        guard !targets.isEmpty else {
            emit("file: name something "
                 + "to identify.", .err)
            stageError = true
            return
        }
        for target in targets {
            let path = resolved(target)
            let what: String
            if path.hasPrefix("/bin/") {
                what = "a house built-in "
                    + "(a virtual file)"
            } else if !BlacksiteFS
                .exists(path) {
                emit("file: \(target): "
                     + "cannot open — no "
                     + "such file.", .err)
                stageError = true
                continue
            } else if BlacksiteFS
                .isDirectory(path) {
                what = "directory"
            } else {
                let data = BlacksiteFS
                    .readData(path)
                    ?? Data()
                let bytes = [UInt8](
                    data.prefix(600))
                func hasPrefixBytes(
                    _ magic: [UInt8]) -> Bool {
                    guard bytes.count
                            >= magic.count
                    else { return false }
                    let head = Array(
                        bytes.prefix(
                            magic.count))
                    return head == magic
                }
                let lower = target
                    .lowercased()
                if hasPrefixBytes(
                    [0x00, 0x61, 0x73, 0x6d]) {
                    what = "WebAssembly "
                        + "binary"
                } else if hasPrefixBytes(
                    [0x89, 0x50, 0x4e, 0x47]) {
                    what = "PNG image"
                } else if hasPrefixBytes(
                    [0xff, 0xd8, 0xff]) {
                    what = "JPEG image"
                } else if hasPrefixBytes(
                    Array("GIF8".utf8)) {
                    what = "GIF image"
                } else if hasPrefixBytes(
                    Array("%PDF".utf8)) {
                    what = "PDF document"
                } else if hasPrefixBytes(
                    [0x50, 0x4b, 0x03, 0x04]) {
                    what = "zip archive"
                } else if hasPrefixBytes(
                    [0x1f, 0x8b]) {
                    what = "gzip data"
                } else if hasPrefixBytes(
                    Array("SQLite format 3"
                        .utf8)) {
                    what = "SQLite database"
                } else if lower
                    .hasSuffix(".py") {
                    what = "Python script"
                } else if lower
                    .hasSuffix(".js") {
                    what = "JavaScript source"
                } else if lower
                    .hasSuffix(".swift") {
                    what = "Swift source"
                } else if lower
                    .hasSuffix(".sh") {
                    what = "shell script"
                } else if lower
                    .hasSuffix(".json") {
                    what = "JSON text"
                } else if lower
                    .hasSuffix(".md") {
                    what = "Markdown text"
                } else if lower
                    .hasSuffix(".html") {
                    what = "HTML text"
                } else if lower
                    .hasSuffix(".c")
                    || lower.hasSuffix(".h") {
                    what = "C source"
                } else if !bytes.isEmpty,
                          bytes.allSatisfy({
                              $0 == 9 || $0 == 10
                                  || $0 == 13
                                  || ($0 >= 32
                                      && $0 < 127)
                          }) {
                    what = "text"
                } else if bytes.isEmpty {
                    what = "empty"
                } else {
                    what = "data"
                }
            }
            emit("\(target): \(what)")
        }
    }

    private func stringsCommand(
        _ args: [String]) {
        var minimum = 4
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-n",
               i + 1 < args.count {
                i += 1
                minimum = Int(args[i]) ?? 4
            } else if arg.hasPrefix("-n"),
                      arg.count > 2 {
                minimum = Int(
                    arg.dropFirst(2)) ?? 4
            } else if !arg.hasPrefix("-") {
                files.append(arg)
            }
            i += 1
        }
        let data: Data
        if let file = files.first {
            guard let read = BlacksiteFS
                .readData(resolved(file))
            else {
                emit("strings: \(file): no "
                     + "such file.", .err)
                stageError = true
                return
            }
            data = read
        } else {
            data = Data(stageInput.utf8)
        }
        var run = ""
        func flushRun() {
            if run.count >= minimum {
                emit(run)
            }
            run = ""
        }
        for byte in data {
            if byte >= 32, byte < 127 {
                run.append(Character(
                    UnicodeScalar(byte)))
            } else {
                flushRun()
            }
        }
        flushRun()
    }

    private func calCommand(_ args: [String]) {
        let calendar = Calendar(
            identifier: .gregorian)
        let now = Date()
        var month = calendar.component(
            .month, from: now)
        var year = calendar.component(
            .year, from: now)
        let monthNames = [
            "january", "february", "march",
            "april", "may", "june", "july",
            "august", "september",
            "october", "november",
            "december",
        ]
        let nums = args.compactMap(Int.init)
        let nameArg = args.first { arg in
            Int(arg) == nil
                && monthNames.contains {
                    $0.hasPrefix(
                        arg.lowercased())
                }
        }
        if let nameArg = nameArg,
           let index = monthNames
            .firstIndex(where: {
                $0.hasPrefix(
                    nameArg.lowercased())
            }) {
            month = index + 1
            if let y = nums.first {
                year = y
            }
        } else if nums.count == 1 {
            month = nums[0]
        } else if nums.count >= 2 {
            month = nums[0]
            year = nums[1]
        }
        guard (1...12).contains(month) else {
            emit("cal: months run 1 "
                 + "through 12.", .err)
            stageError = true
            return
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = calendar.date(
                from: comps),
              let range = calendar.range(
                of: .day, in: .month,
                for: first)
        else { return }
        let title = monthNames[month - 1]
            .capitalized + " \(year)"
        emit(String(repeating: " ",
                    count: max(0, (20
                        - title.count) / 2))
             + title)
        let weekdayNames = [
            "Su", "Mo", "Tu", "We",
            "Th", "Fr", "Sa",
        ]
        let start = calendar.firstWeekday
            - 1
        let header = (0..<7).map {
            weekdayNames[($0 + start) % 7]
        }
        emit(header.joined(separator: " "))
        let firstWeekday = calendar
            .component(.weekday, from: first)
        var lead = (firstWeekday - 1
            - start + 7) % 7
        var cells: [String] = []
        while lead > 0 {
            cells.append("  ")
            lead -= 1
        }
        for day in range {
            cells.append(day < 10
                ? " \(day)" : "\(day)")
        }
        var row: [String] = []
        for cell in cells {
            row.append(cell)
            if row.count == 7 {
                emit(row.joined(
                    separator: " "))
                row = []
            }
        }
        if !row.isEmpty {
            emit(row.joined(separator: " "))
        }
    }

    private func yesCommand(_ args: [String]) {
        let text = args.isEmpty
            ? "y" : args.joined(
                separator: " ")
        for _ in 0..<1000 {
            emit(text)
        }
    }

    // MARK: figlet — big letters from
    // a five-row hand

    private static let figletGlyphs:
        [Character: [String]] = [
        "A": [" ### ", "#   #", "#####",
              "#   #", "#   #"],
        "B": ["#### ", "#   #", "#### ",
              "#   #", "#### "],
        "C": [" ####", "#    ", "#    ",
              "#    ", " ####"],
        "D": ["#### ", "#   #", "#   #",
              "#   #", "#### "],
        "E": ["#####", "#    ", "#### ",
              "#    ", "#####"],
        "F": ["#####", "#    ", "#### ",
              "#    ", "#    "],
        "G": [" ####", "#    ", "#  ##",
              "#   #", " ####"],
        "H": ["#   #", "#   #", "#####",
              "#   #", "#   #"],
        "I": ["#####", "  #  ", "  #  ",
              "  #  ", "#####"],
        "J": ["#####", "    #", "    #",
              "#   #", " ### "],
        "K": ["#   #", "#  # ", "###  ",
              "#  # ", "#   #"],
        "L": ["#    ", "#    ", "#    ",
              "#    ", "#####"],
        "M": ["#   #", "## ##", "# # #",
              "#   #", "#   #"],
        "N": ["#   #", "##  #", "# # #",
              "#  ##", "#   #"],
        "O": [" ### ", "#   #", "#   #",
              "#   #", " ### "],
        "P": ["#### ", "#   #", "#### ",
              "#    ", "#    "],
        "Q": [" ### ", "#   #", "#   #",
              "#  # ", " ## #"],
        "R": ["#### ", "#   #", "#### ",
              "#  # ", "#   #"],
        "S": [" ####", "#    ", " ### ",
              "    #", "#### "],
        "T": ["#####", "  #  ", "  #  ",
              "  #  ", "  #  "],
        "U": ["#   #", "#   #", "#   #",
              "#   #", " ### "],
        "V": ["#   #", "#   #", "#   #",
              " # # ", "  #  "],
        "W": ["#   #", "#   #", "# # #",
              "## ##", "#   #"],
        "X": ["#   #", " # # ", "  #  ",
              " # # ", "#   #"],
        "Y": ["#   #", " # # ", "  #  ",
              "  #  ", "  #  "],
        "Z": ["#####", "   # ", "  #  ",
              " #   ", "#####"],
        "0": [" ### ", "#  ##", "# # #",
              "##  #", " ### "],
        "1": ["  #  ", " ##  ", "  #  ",
              "  #  ", "#####"],
        "2": [" ### ", "#   #", "  ## ",
              " #   ", "#####"],
        "3": ["#### ", "    #", " ### ",
              "    #", "#### "],
        "4": ["#   #", "#   #", "#####",
              "    #", "    #"],
        "5": ["#####", "#    ", "#### ",
              "    #", "#### "],
        "6": [" ### ", "#    ", "#### ",
              "#   #", " ### "],
        "7": ["#####", "    #", "   # ",
              "  #  ", "  #  "],
        "8": [" ### ", "#   #", " ### ",
              "#   #", " ### "],
        "9": [" ### ", "#   #", " ####",
              "    #", " ### "],
        " ": ["   ", "   ", "   ",
              "   ", "   "],
        ".": [" ", " ", " ", " ", "#"],
        ",": ["  ", "  ", "  ", " #",
              "# "],
        "!": ["#", "#", "#", " ", "#"],
        "?": [" ## ", "#  #", "  # ",
              "    ", "  # "],
        "'": ["#", "#", " ", " ", " "],
        "-": ["    ", "    ", "####",
              "    ", "    "],
        "+": ["     ", "  #  ", "#####",
              "  #  ", "     "],
        "=": ["     ", "#####", "     ",
              "#####", "     "],
        "/": ["    #", "   # ", "  #  ",
              " #   ", "#    "],
        "\\": ["#    ", " #   ", "  #  ",
               "   # ", "    #"],
        ":": [" ", "#", " ", "#", " "],
        ";": ["  ", " #", "  ", " #",
              "# "],
        "(": ["  #", " # ", "#  ",
              " # ", "  #"],
        ")": ["#  ", " # ", "  #",
              " # ", "#  "],
        "*": ["     ", "# # #", " ### ",
              "# # #", "     "],
        "#": [" # # ", "#####", " # # ",
              "#####", " # # "],
        "@": [" ### ", "# # #", "# ###",
              "#    ", " ### "],
        "_": ["     ", "     ", "     ",
              "     ", "#####"],
        "<": ["   #", "  # ", " #  ",
              "  # ", "   #"],
        ">": ["#   ", " #  ", "  # ",
              " #  ", "#   "],
        "%": ["##  #", "## # ", "  #  ",
              " # ##", "#  ##"],
        "&": [" ## ", "#  #", " ## ",
              "#  #", " ## "],
        "$": [" ####", "# #  ", " ### ",
              "  # #", "#### "],
    ]

    private func figletCommand(
        _ args: [String]) {
        var slim = false
        var words: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "-f",
               i + 1 < args.count {
                i += 1
                slim = args[i] == "slim"
                    || args[i] == "small"
            } else if arg.hasPrefix("-") {
                slim = arg.contains("s")
                    && arg.count <= 3
            } else {
                words.append(arg)
            }
            i += 1
        }
        let text = words.joined(
            separator: " ").uppercased()
        guard !text.isEmpty else {
            emit("figlet: give me words "
                 + "and I'll make them "
                 + "big.", .err)
            stageError = true
            return
        }
        let question = Self.figletGlyphs["?"]
            ?? ["#####", "#####", "#####",
                "#####", "#####"]
        for rowIndex in 0..<5 {
            var line = ""
            for ch in text {
                let glyph = Self
                    .figletGlyphs[ch]
                    ?? question
                let pixels = glyph[rowIndex]
                for pixel in pixels {
                    if slim {
                        line += pixel == "#"
                            ? "█" : " "
                    } else {
                        line += pixel == "#"
                            ? "██" : "  "
                    }
                }
                line += slim ? " " : "  "
            }
            emit(line.trimmingCharacters(
                in: .whitespaces))
        }
    }

    // MARK: Diagnose — the house puts
    // itself through its paces.
    //
    // A battery, run in the open: the
    // filesystem, the shell's own words,
    // colour, both interpreters and their
    // libraries, and then the drills —
    // a python that never stops, a flood,
    // a javascript loop, a fork bomb, a
    // wasm loop and a wasm that reaches
    // past its own memory. Each must be
    // CONTAINED, and the battery says so
    // per drill, with the numbers.

    private var diagnoseRunning = false

    private typealias ProbeDone =
        (Bool, String) -> Void

    /// A probe's completion, fired once:
    /// a probe that never answers fails
    /// by its watchdog instead of
    /// hanging the battery.
    private final class ProbeGate {
        private let lock = NSLock()
        private var fired = false
        private let done: ProbeDone
        init(seconds: Double,
             done: @escaping ProbeDone) {
            self.done = done
            DispatchQueue.global()
                .asyncAfter(
                    deadline: .now()
                        + seconds) {
                    [weak self] in
                    self?.fire(
                        false,
                        "timed out after "
                        + "\(Int(seconds))s")
                }
        }
        func fire(_ ok: Bool,
                  _ detail: String = "") {
            lock.lock()
            if fired {
                lock.unlock()
                return
            }
            fired = true
            lock.unlock()
            done(ok, detail)
        }
    }

    private func diagnoseCommand() {
        guard !diagnoseRunning else {
            emit("diagnose: the battery "
                 + "is already running.",
                 .err)
            return
        }
        diagnoseRunning = true
        emit("diagnose — the house "
             + "through its paces: "
             + "engines, libraries, and "
             + "the containment drills.",
             .sys)
        if BlacksiteKernel.shared
            .liveCount > 0 {
            emit("other programs are "
                 + "live; the drills share "
                 + "the table with them.",
                 .sys)
        }
        let probes = diagnoseProbes()
        runDiagnoseProbe(0, probes,
                         passed: 0)
    }

    private func runDiagnoseProbe(
        _ index: Int,
        _ probes: [(String, Double,
                     (@escaping ProbeDone)
                        -> Void)],
        passed: Int) {
        if index == probes.count {
            let all = passed == probes.count
            emit("diagnose: \(passed)/"
                 + "\(probes.count) — "
                 + (all
                    ? "the house holds."
                    : "the ✗ lines above "
                      + "name the faults."),
                 all ? .ok : .err)
            if !all { stageError = true }
            diagnoseRunning = false
            return
        }
        let (name, timeout, body) =
            probes[index]
        let gate = ProbeGate(
            seconds: timeout) {
                [weak self] ok, detail in
                guard let self = self
                else { return }
                self.emit(
                    "  \(ok ? "✓" : "✗") "
                    + name
                    + (detail.isEmpty
                       ? "" : " — " + detail),
                    ok ? .out : .err)
                self.runDiagnoseProbe(
                    index + 1, probes,
                    passed: passed
                        + (ok ? 1 : 0))
            }
        body { ok, detail in
            gate.fire(ok, detail)
        }
    }

    /// Run a python snippet off the main
    /// thread with a collecting sink.
    private func diagnosePyRun(
        _ source: String, path: String,
        cancel: KernelCancel?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        DispatchQueue.global(
            qos: .userInitiated).async {
            BlacksitePy.run(
                source: source, path: path,
                args: [path],
                inputProvider: nil,
                cancel: cancel, emit: emit)
            done()
        }
    }

    private func diagnoseCollector()
        -> (BlacksiteEmit, () -> [String]) {
        var lines: [String] = []
        let lock = NSLock()
        let emit: BlacksiteEmit = {
            text, _ in
            lock.lock()
            lines.append(text)
            lock.unlock()
        }
        return (emit, {
            lock.lock()
            defer { lock.unlock() }
            return lines
        })
    }

    private func diagnoseWasmRun(
        data: Data, argv: [String],
        name: String,
        done: @escaping (Int, [String])
            -> Void) {
        let kernel = BlacksiteKernel.shared
        let (proc, refusal) = kernel.admit(
            name: name, kind: .wasm,
            parent: 0, background: false)
        guard let proc = proc else {
            done(-1, [refusal ?? "refused"])
            return
        }
        let (emit, collected) =
            diagnoseCollector()
        let machine = BlacksiteWasm(
            proc: proc, emit: emit) {
                [weak self] code in
                kernel.finish(
                    proc, note: "diagnose")
                self?.wasmMachines[
                    proc.pid] = nil
                done(code, collected())
            }
        wasmMachines[proc.pid] = machine
        var guestEnv = env
        guestEnv["PWD"] = cwd
        if guestEnv["HOME"] == nil {
            guestEnv["HOME"] = "/home"
        }
        machine.launch(
            data: data, argv: argv,
            env: guestEnv, cwd: cwd,
            stdin: "")
    }

    private func diagnoseProbes()
        -> [(String, Double,
             (@escaping ProbeDone) -> Void)] {
        let kernel = BlacksiteKernel.shared
        var probes: [(String, Double,
            (@escaping ProbeDone) -> Void)] =
            []

        probes.append((
            "filesystem roundtrip", 5, {
                done in
                let path =
                    "/tmp/diag-probe.txt"
                let wrote = BlacksiteFS
                    .writeText(
                        path, text: "roundtrip")
                let read = BlacksiteFS
                    .readText(path)
                let listed = (BlacksiteFS
                    .list("/tmp") ?? [])
                    .contains {
                        $0.name
                            == "diag-probe.txt"
                    }
                _ = BlacksiteFS.remove(path)
                let gone = !BlacksiteFS
                    .exists(path)
                done(wrote
                     && read == "roundtrip"
                     && listed && gone, "")
            }))

        probes.append((
            "the shell's words", 5, {
                done in
                let tokens = self.tokenize(
                    "echo \"a b\" 'c'")
                let parts = self
                    .splitSequence(
                        "a; b && c")
                done(tokens == ["echo",
                                "a b", "c"]
                     && parts.count == 3,
                     "tokenizer + "
                     + "sequencer")
            }))

        probes.append((
            "colour strips and renders", 5, {
                done in
                let sample = "a\u{1B}[31mb"
                    + "\u{1B}[0mc"
                let stripped = ANSITerm
                    .strip(sample)
                let rendered = ANSITerm
                    .attributed(
                        sample,
                        baseFont: .system(
                            .caption,
                            design: .monospaced),
                        baseColor: .primary)
                done(stripped == "abc"
                     && String(rendered
                        .characters) == "abc",
                     "")
            }))

        probes.append((
            "python — the language", 10, {
                done in
                let source = [
                    "class Animal:",
                    "    def __init__(",
                    "        self, name):",
                    "        self.name = name",
                    "    def speak(self):",
                    "        return \"...\"",
                    "class Dog(Animal):",
                    "    def speak(self):",
                    "        return \"woof \""
                        + " + self.name",
                    "d = Dog(\"rex\")",
                    "squares = (x * x"
                        + " for x in range(5))",
                    "def counter():",
                    "    n = 0",
                    "    while True:",
                    "        yield n",
                    "        n += 1",
                    "c = counter()",
                    "first = [next(c)"
                        + " for _ in range(3)]",
                    "print(\"PYLANG\","
                        + " d.speak(),"
                        + " sum(squares),"
                        + " first)",
                ].joined(separator: "\n")
                let (emit, collected) =
                    self.diagnoseCollector()
                self.diagnosePyRun(
                    source,
                    path: "/tmp/diaglang.py",
                    cancel: nil, emit: emit) {
                    let out = collected()
                        .joined(separator: " ")
                    done(out.contains("PYLANG")
                         && out.contains(
                            "woof rex")
                         && out.contains("30")
                         && out.contains(
                            "[0, 1, 2]"),
                         "classes, super's "
                         + "house, generators, "
                         + "comprehensions")
                }
            }))

        probes.append((
            "python — the library", 10, {
                done in
                let source = [
                    "import json, re,"
                        + " hashlib",
                    "from collections import"
                        + " Counter",
                    "import itertools",
                    "data = json.loads("
                        + "'{\"a\": [1, 2, 3]}')",
                    "m = re.search("
                        + "r'(\\d+)-(\\d+)',"
                        + " 'id 12-34')",
                    "c = Counter('aabbbc')",
                    "pairs = list("
                        + "itertools"
                        + ".combinations("
                        + "[1, 2, 3], 2))",
                    "h = hashlib.sha256()",
                    "h.update('abc')",
                    "print(\"PYLIB\","
                        + " data['a'],"
                        + " m.group(2),"
                        + " c['b'], pairs,"
                        + " h.hexdigest()[:16])",
                ].joined(separator: "\n")
                let (emit, collected) =
                    self.diagnoseCollector()
                self.diagnosePyRun(
                    source,
                    path: "/tmp/diaglib.py",
                    cancel: nil, emit: emit) {
                    let out = collected()
                        .joined(separator: " ")
                    done(out.contains("PYLIB")
                         && out.contains("34")
                         && out.contains("(1, 2)")
                         && out.contains(
                            "ba7816bf8f01cfea"),
                         "json, re, Counter, "
                         + "itertools, sha256 "
                         + "of \"abc\"")
                }
            }))

        probes.append((
            "python — your own modules", 10, {
                done in
                _ = BlacksiteFS.writeText(
                    "/tmp/diaghelper.py",
                    text: "def triple(n):\n"
                        + "    return n * 3\n")
                let source = [
                    "import diaghelper",
                    "print(\"PYMOD\","
                        + " diaghelper"
                        + ".triple(14))",
                ].joined(separator: "\n")
                let (emit, collected) =
                    self.diagnoseCollector()
                self.diagnosePyRun(
                    source,
                    path: "/tmp/diagmain.py",
                    cancel: nil, emit: emit) {
                    let out = collected()
                        .joined(separator: " ")
                    done(out.contains(
                            "PYMOD 42"), "")
                }
            }))

        probes.append((
            "python — input() with "
            + "nobody there", 10, {
                done in
                let source = [
                    "try:",
                    "    input(\"name? \")",
                    "    print(\"PYEOF-MISS\")",
                    "except EOFError:",
                    "    print(\"PYEOF-OK\")",
                ].joined(separator: "\n")
                let (emit, collected) =
                    self.diagnoseCollector()
                self.diagnosePyRun(
                    source,
                    path: "/tmp/diageof.py",
                    cancel: nil, emit: emit) {
                    let out = collected()
                        .joined(separator: " ")
                    done(out.contains(
                            "PYEOF-OK")
                         && !out.contains(
                            "PYEOF-MISS"), "")
                }
            }))

        probes.append((
            "drill: a python that "
            + "never stops", 15, {
                done in
                let (proc, refusal) =
                    kernel.admit(
                        name: "diagnose loop",
                        kind: .python,
                        parent: 0,
                        background: false)
                guard let proc = proc else {
                    done(false,
                         refusal ?? "refused")
                    return
                }
                var byKernel = false
                let flagLock = NSLock()
                DispatchQueue.global()
                    .asyncAfter(
                        deadline: .now() + 2.5) {
                        if proc.isLive {
                            flagLock.lock()
                            byKernel = true
                            flagLock.unlock()
                            kernel.kill(
                                proc,
                                reason: "the "
                                    + "diagnose "
                                    + "drill")
                        }
                    }
                let started = Date()
                self.diagnosePyRun(
                    "while True:\n    pass",
                    path: "/tmp/diagloop.py",
                    cancel: proc.cancel,
                    emit: { _, _ in }) {
                    let elapsed = Date()
                        .timeIntervalSince(
                            started)
                    kernel.finish(
                        proc, note: "diagnose")
                    flagLock.lock()
                    let killed = byKernel
                    flagLock.unlock()
                    done(elapsed < 12,
                         killed
                         ? "the kernel's word "
                           + "stopped it"
                         : "its step fuel "
                           + "stopped it")
                }
            }))

        probes.append((
            "drill: a python flood", 20, {
                done in
                let (proc, refusal) =
                    kernel.admit(
                        name: "diagnose flood",
                        kind: .python,
                        parent: 0,
                        background: false)
                guard let proc = proc else {
                    done(false,
                         refusal ?? "refused")
                    return
                }
                let counting: BlacksiteEmit =
                    { _, _ in
                        _ = kernel
                            .accountOutput(proc)
                    }
                let source = [
                    "n = 0",
                    "while True:",
                    "    print(\"flood\", n)",
                    "    n += 1",
                ].joined(separator: "\n")
                self.diagnosePyRun(
                    source,
                    path: "/tmp/diagflood.py",
                    cancel: proc.cancel,
                    emit: counting) {
                    let note = proc.exitNote
                    let counted = proc
                        .outputLines
                    kernel.finish(
                        proc, note: "diagnose")
                    done(note.contains(
                            "output quota")
                         && counted
                            >= BlacksiteKernel
                                .outputQuota,
                         "\(counted) lines "
                         + "counted, then "
                         + "the gate: \(note)")
                }
            }))

        probes.append((
            "javascript — the engine", 8, {
                done in
                BlacksiteJS.shared.eval(
                    "21 * 2") {
                    result, error in
                    done(error == nil
                         && (result ?? "")
                            .contains("42"),
                         result ?? "")
                }
            }))

        probes.append((
            "drill: a javascript loop, "
            + "killed", 10, {
                done in
                _ = BlacksiteFS.writeText(
                    "/tmp/diagloop.js",
                    text: "for (;;) {\n}\n")
                let (proc, refusal) =
                    kernel.admit(
                        name: "diagnose js loop",
                        kind: .javascript,
                        parent: 0,
                        background: false)
                guard let proc = proc else {
                    done(false,
                         refusal ?? "refused")
                    return
                }
                let oldSink = BlacksiteJS
                    .shared.printSink
                BlacksiteJS.shared.printSink =
                    { _ in }
                BlacksiteJS.shared.runFile(
                    "/tmp/diagloop.js",
                    args: [],
                    killSwitch: proc
                        .killSwitch) { _ in
                    BlacksiteJS.shared
                        .printSink = oldSink
                    kernel.finish(
                        proc, note: "diagnose")
                    done(true,
                         "the engine's limit "
                         + "fired once the "
                         + "kernel spoke")
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.8) {
                    kernel.kill(
                        proc,
                        reason: "the diagnose "
                            + "drill")
                }
            }))

        probes.append((
            "drill: fork bomb", 25, {
                done in
                _ = BlacksiteFS.writeText(
                    "/tmp/diagbomb.sh",
                    text: "sh /tmp/diagbomb.sh"
                        + " &\n"
                        + "sh /tmp/diagbomb.sh"
                        + " &\n")
                let before = kernel
                    .totalSpawned
                self.runScript(
                    "/tmp/diagbomb.sh")
                var maxLive = 0
                var settled = 0
                func poll() {
                    let live = kernel.liveCount
                    maxLive = max(maxLive,
                                  live)
                    settled = live == 0
                        ? settled + 1 : 0
                    if settled >= 3 {
                        let spawned = kernel
                            .totalSpawned
                            - before
                        done(maxLive <= 32,
                             "peak \(maxLive) "
                             + "live, "
                             + "\(spawned) "
                             + "spawned, all "
                             + "reaped")
                        return
                    }
                    DispatchQueue.main
                        .asyncAfter(
                            deadline: .now()
                                + 0.25) {
                            poll()
                        }
                }
                poll()
            }))

        probes.append((
            "kernel — the caps hold", 12, {
                done in
                var admitted: [KernelProcess] =
                    []
                var refusal: String? = nil
                func wave() {
                    while admitted.count
                            < 40 {
                        let (p, r) = kernel
                            .admit(
                                name: "diagnose"
                                    + " cap",
                                kind: .shell,
                                parent: 0,
                                background: true)
                        if let p = p {
                            admitted.append(p)
                        } else {
                            refusal = r
                            break
                        }
                    }
                }
                func finishCaps() {
                    let ok = admitted.count
                        <= 32
                        && refusal != nil
                    let detail =
                        "\(admitted.count) "
                        + "admitted, "
                        + "then the gate: "
                        + (refusal ?? "none")
                    for p in admitted {
                        kernel.kill(
                            p,
                            reason: "diagnose")
                    }
                    done(ok, detail)
                }
                wave()
                if refusal != nil {
                    finishCaps()
                } else {
                    DispatchQueue.main
                        .asyncAfter(
                            deadline: .now()
                                + 2.3) {
                            wave()
                            finishCaps()
                        }
                }
            }))

        probes.append((
            "wasm — the userspace "
            + "answers", 15, {
                done in
                guard let data =
                        BlacksiteWasm
                            .linuxboxData
                else {
                    done(false,
                         "userspace missing")
                    return
                }
                self.diagnoseWasmRun(
                    data: data,
                    argv: ["echo", "WASM-OK"],
                    name: "diagnose echo") {
                    code, lines in
                    done(code == 0
                         && lines.contains {
                            $0.contains(
                                "WASM-OK")
                         }, "exit \(code)")
                }
            }))

        probes.append((
            "wasm — exit codes are "
            + "exit codes", 15, {
                done in
                guard let data =
                        BlacksiteWasm
                            .linuxboxData
                else {
                    done(false,
                         "userspace missing")
                    return
                }
                self.diagnoseWasmRun(
                    data: data,
                    argv: ["false"],
                    name: "diagnose false") {
                    code, _ in
                    done(code == 1,
                         "false came back "
                         + "\(code)")
                }
            }))

        probes.append((
            "drill: a wasm that traps", 20, {
                done in
                guard let data =
                        BlacksiteWasm
                            .fixtureData("hog")
                else {
                    done(false,
                         "fixture missing")
                    return
                }
                self.diagnoseWasmRun(
                    data: data, argv: ["hog"],
                    name: "diagnose hog") {
                    code, lines in
                    done(code != 0
                         || lines.joined()
                            .contains("trapped"),
                         "it reached past its "
                         + "memory; exit "
                         + "\(code), and the "
                         + "house is still "
                         + "standing")
                }
            }))

        probes.append((
            "drill: a wasm loop, killed",
            12, {
                done in
                guard let data =
                        BlacksiteWasm
                            .fixtureData(
                                "looper")
                else {
                    done(false,
                         "fixture missing")
                    return
                }
                let (proc, refusal) =
                    kernel.admit(
                        name: "diagnose "
                            + "looper",
                        kind: .wasm,
                        parent: 0,
                        background: false)
                guard let proc = proc else {
                    done(false,
                         refusal ?? "refused")
                    return
                }
                let (emit, _) =
                    self.diagnoseCollector()
                let machine = BlacksiteWasm(
                    proc: proc, emit: emit) {
                        [weak self] code in
                        kernel.finish(
                            proc,
                            note: "diagnose")
                        self?.wasmMachines[
                            proc.pid] = nil
                        done(true,
                             "terminated at "
                             + "the kernel's "
                             + "word, exit "
                             + "\(code)")
                    }
                self.wasmMachines[proc.pid] =
                    machine
                var guestEnv = self.env
                guestEnv["PWD"] = self.cwd
                machine.launch(
                    data: data,
                    argv: ["looper"],
                    env: guestEnv,
                    cwd: self.cwd, stdin: "")
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 1.0) {
                    kernel.kill(
                        proc,
                        reason: "the diagnose "
                            + "drill")
                }
            }))

        return probes
    }

    private func jobsCommand() {
        let live = BlacksiteKernel.shared
            .snapshot().filter { $0.isLive }
        if live.isEmpty {
            emit("no jobs — nothing runs "
                 + "under the kernel.", .sys)
            return
        }
        for proc in live {
            emit("[\(proc.pid)] "
                 + (proc.background
                    ? "bg " : "fg ")
                 + "\(proc.name) — "
                 + kernelState(proc), .out)
        }
    }

    /// A kernel state, dressed: running
    /// in green, waiting on input in
    /// amber — a process board you can
    /// read at a glance.
    private func kernelState(
        _ proc: KernelProcess) -> String {
        switch proc.state {
        case .running:
            return "\u{1B}[1;32m"
                + proc.state.rawValue
                + "\u{1B}[0m"
        case .waiting:
            return "\u{1B}[33m"
                + proc.state.rawValue
                + "\u{1B}[0m"
        default:
            return proc.state.rawValue
        }
    }

    private func killCommand(
        _ args: [String]) {
        guard let first = args.first,
              let pid = Int(first) else {
            emit("kill <pid> — 'ps' lists "
                 + "the kernel's table.", .err)
            return
        }
        if let proc = BlacksiteKernel.shared
            .kill(pid: pid,
                  reason: "killed by the "
                    + "operator") {
            emit("kernel: [\(pid)] "
                 + "\(proc.name) — killed.",
                 .sys)
        } else {
            emit("kill: no live process "
                 + "\(pid).", .err)
        }
    }

    // MARK: Scan + knock + census

    private func scan(_ args: [String]) {
        if capturing {
            emit("scan runs live — it cannot "
                 + "be piped or captured.", .err)
            return
        }
        let port = args.first.flatMap(Int.init)
            ?? 80
        guard (1...65535).contains(port) else {
            emit("a port is 1 through 65535.",
                 .err)
            return
        }
        if EmconStandard.refused(.sweep) {
            emit("the Standard refuses the sweep "
                 + "under "
                 + EmconCondition.current.name
                 + ".", .err)
            return
        }
        guard !scanner.sweeping else {
            emit("a sweep is already running.",
                 .err)
            return
        }
        scanner.sweep(port: port)
        busy = true
        emit("sweeping the wire on port "
             + "\(port)…", .sys)
        Task { [weak self] in
            guard let self = self else { return }
            while self.scanner.sweeping {
                try? await Task.sleep(
                    nanoseconds: 300_000_000)
            }
            let hosts = self.scanner.sweepHosts
            await MainActor.run {
                self.busy = false
                if hosts.isEmpty {
                    self.emit("the sweep found no "
                              + "one on port "
                              + "\(port).", .out)
                } else {
                    self.emit("\(hosts.count) "
                              + "answered on port "
                              + "\(port):", .ok)
                    for host in hosts.prefix(24) {
                        self.emit("  \(host.ip)",
                                  .out)
                    }
                    if hosts.count > 24 {
                        self.emit("  …and "
                                  + "\(hosts.count - 24) "
                                  + "more", .sys)
                    }
                }
            }
        }
    }

    private func knock(_ args: [String]) {
        if capturing {
            emit("knock runs live — it cannot "
                 + "be piped or captured.", .err)
            return
        }
        guard let host = args.first else {
            emit("knock needs a host — "
                 + "'knock 192.168.4.1'.", .err)
            return
        }
        let ports: [Int]
        if args.count > 1 {
            ports = args[1]
                .split(separator: ",")
                .compactMap {
                    Int($0.trimmingCharacters(
                        in: .whitespaces)) }
        } else {
            ports = ScanModel.topPorts.map { $0.0 }
        }
        guard !ports.isEmpty else {
            emit("no readable ports in that.",
                 .err)
            return
        }
        if EmconStandard.refused(.probing) {
            emit("the Standard refuses probing "
                 + "under "
                 + EmconCondition.current.name
                 + ".", .err)
            return
        }
        runKnock(host: host, ports: ports,
                 label: host)
    }

    private func runKnock(host: String,
                          ports: [Int],
                          label: String) {
        guard !recon.knocking else {
            emit("the knock hand is busy.", .err)
            return
        }
        busy = true
        recon.knock(host: host, ports: ports,
                    udp: false)
        Task { [weak self] in
            guard let self = self else { return }
            while self.recon.knocking {
                try? await Task.sleep(
                    nanoseconds: 300_000_000)
            }
            let hits = self.recon.hits
                .filter { $0.isOpen }
            await MainActor.run {
                self.busy = false
                if hits.isEmpty {
                    self.emit("\(label): every "
                              + "door shut.", .out)
                } else {
                    for hit in hits {
                        var line = "\(label): "
                            + "\(hit.port)/tcp open"
                            + " — \(hit.service)"
                        if !hit.banner.isEmpty {
                            line += " — \u{201C}"
                                + hit.banner
                                    .prefix(48)
                                + "\u{201D}"
                        }
                        self.emit(line, .ok)
                    }
                }
            }
        }
    }

    private func census() {
        if capturing {
            emit("census runs live — it "
                 + "cannot be piped or "
                 + "captured.", .err)
            return
        }
        if EmconStandard.refused(.probing) {
            emit("the Standard refuses probing "
                 + "under "
                 + EmconCondition.current.name
                 + ".", .err)
            return
        }
        let board = NeighborhoodStore.shared
            .neighbors
        guard !board.isEmpty else {
            emit("the board is empty — nothing "
                 + "to census yet.", .err)
            return
        }
        emit("census of \(board.count) known "
             + "devices, in turn…", .sys)
        Task { [weak self] in
            guard let self = self else { return }
            for neighbor in board.prefix(12) {
                if self.recon.knocking { break }
                let ports = neighbor.ports.isEmpty
                    ? ScanModel.topPorts.map { $0.0 }
                    : neighbor.ports
                await MainActor.run {
                    self.runKnock(
                        host: neighbor.ip,
                        ports: Array(ports.prefix(8)),
                        label: neighbor.displayName
                            + " (\(neighbor.ip))")
                }
                while self.recon.knocking {
                    try? await Task.sleep(
                        nanoseconds: 300_000_000)
                }
            }
            await MainActor.run {
                self.emit("census complete.",
                          .sys)
            }
        }
    }

    // MARK: The wire + the pentest bench

    /// Every live wire command stands
    /// behind the same two doors knock
    /// uses: never piped or captured, and
    /// the Standard's word on probing.
    private func netAllowed(_ name: String)
        -> Bool {
        if capturing {
            emit("\(name) runs live — it "
                 + "cannot be piped or "
                 + "captured.", .err)
            return false
        }
        if EmconStandard.refused(.probing) {
            emit("the Standard refuses "
                 + "probing under "
                 + EmconCondition.current.name
                 + ".", .err)
            return false
        }
        return true
    }

    private static func netEmit(
        _ shell: BlacksiteShell?)
        -> BlacksiteEmit {
        { text, kind in
            shell?.emit(text, kind)
        }
    }

    private func netBusy(
        _ body: @escaping (
            @escaping BlacksiteEmit,
            @escaping () -> Void) -> Void) {
        busy = true
        body(Self.netEmit(self)) {
            [weak self] in
            DispatchQueue.main.async {
                self?.busy = false
            }
        }
    }

    private func localPrefix() -> String? {
        guard let ip = BlacksiteNet
            .primaryIPv4() else {
            return nil
        }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else {
            return nil
        }
        return parts[0..<3].joined(
            separator: ".")
    }

    private func netCommand(
        _ name: String, _ args: [String]) {
        let out = Self.netEmit(self)
        switch name {
        case "ifconfig":
            BlacksiteNet.ifconfig(emit: out)
        case "arp":
            BlacksiteNet.arp(emit: out)
        case "netstat":
            BlacksiteNet.netstat(emit: out)
        case "hostname":
            BlacksiteNet.hostname(emit: out)
        case "ping":
            guard netAllowed(name) else {
                return
            }
            var host: String?
            var count = 4
            var index = 0
            while index < args.count {
                if args[index] == "-c",
                   index + 1 < args.count,
                   let n = Int(
                    args[index + 1]) {
                    count = min(20, max(1, n))
                    index += 2
                } else if host == nil {
                    host = args[index]
                    index += 1
                } else {
                    index += 1
                }
            }
            guard let host = host else {
                emit("ping needs a host.", .err)
                return
            }
            netBusy { emit, done in
                BlacksiteNet.ping(
                    host: host, count: count,
                    emit: emit, done: done)
            }
        case "traceroute", "trace":
            guard netAllowed(name),
                  let host = args.first else {
                if args.isEmpty {
                    emit("traceroute needs a "
                         + "host.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksiteNet.traceroute(
                    host: host, emit: emit,
                    done: done)
            }
        case "dig":
            guard netAllowed(name) else {
                return
            }
            var server = "1.1.1.1"
            var typeName = "A"
            var target: String?
            for token in args {
                if token.hasPrefix("@") {
                    server = String(
                        token.dropFirst())
                } else if BlacksiteDNS
                    .typeNumber(token) != nil {
                    typeName = token
                        .uppercased()
                } else if target == nil {
                    target = token
                }
            }
            guard let target = target else {
                emit("dig needs a name — "
                     + "'dig example.com', "
                     + "'dig @192.168.4.1 "
                     + "x.local AAAA'.",
                     .err)
                return
            }
            netBusy { emit, done in
                BlacksiteNet.dig(
                    name: target,
                    typeName: typeName,
                    server: server,
                    emit: emit, done: done)
            }
        case "nslookup":
            guard netAllowed(name),
                  let target = args.first
            else {
                if args.isEmpty {
                    emit("nslookup needs a "
                         + "name.", .err)
                }
                return
            }
            let server = args.count > 1
                ? args[1] : "1.1.1.1"
            netBusy { emit, done in
                BlacksiteNet.dig(
                    name: target,
                    typeName: "A",
                    server: server,
                    emit: emit) {
                    BlacksiteNet.dig(
                        name: target,
                        typeName: "AAAA",
                        server: server,
                        emit: emit,
                        done: done)
                }
            }
        case "host":
            guard netAllowed(name),
                  let target = args.first
            else {
                if args.isEmpty {
                    emit("host needs a name "
                         + "or an address.",
                         .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksiteNet.hostLookup(
                    target, emit: emit,
                    done: done)
            }
        case "whois":
            guard netAllowed(name),
                  let domain = args.first
            else {
                if args.isEmpty {
                    emit("whois needs a "
                         + "domain.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksiteNet.whois(
                    domain: domain,
                    emit: emit, done: done)
            }
        case "curl":
            guard netAllowed(name) else {
                return
            }
            var headOnly = false
            var headers: [(String, String)] =
                []
            var savePath: String?
            var url: String?
            var index = 0
            while index < args.count {
                let token = args[index]
                if token == "-I"
                    || token == "--head" {
                    headOnly = true
                } else if token == "-H",
                          index + 1
                            < args.count {
                    let pair = args[index + 1]
                    if let colon = pair
                        .firstIndex(of: ":") {
                        headers.append((
                            String(pair[..<colon])
                                .trimmingCharacters(
                                    in: .whitespaces),
                            String(pair[pair
                                .index(after:
                                    colon)...])
                                .trimmingCharacters(
                                    in: .whitespaces)))
                    }
                    index += 1
                } else if token == "-o",
                          index + 1
                            < args.count {
                    savePath = resolved(
                        args[index + 1])
                    index += 1
                } else if url == nil {
                    url = token
                }
                index += 1
            }
            guard let url = url else {
                emit("curl needs a URL.",
                     .err)
                return
            }
            netBusy { emit, done in
                BlacksiteNet.fetch(
                    urlString: url,
                    headOnly: headOnly,
                    headers: headers,
                    savePath: savePath,
                    emit: emit, done: done)
            }
        case "wget":
            guard netAllowed(name),
                  let url = args.first else {
                if args.isEmpty {
                    emit("wget needs a URL.",
                         .err)
                }
                return
            }
            let file: String
            if args.count > 1 {
                file = resolved(args[1])
            } else {
                let base = URL(
                    string: url)?
                    .lastPathComponent ?? ""
                file = resolved(base.isEmpty
                    ? "download.bin" : base)
            }
            netBusy { emit, done in
                BlacksiteNet.fetch(
                    urlString: url,
                    headOnly: false,
                    headers: [],
                    savePath: file,
                    emit: emit, done: done)
            }
        case "nc":
            guard netAllowed(name) else {
                return
            }
            var udp = false
            var scanOnly = false
            var rest: [String] = []
            for token in args {
                if token == "-u" {
                    udp = true
                } else if token == "-z" {
                    scanOnly = true
                } else {
                    rest.append(token)
                }
            }
            guard rest.count >= 2,
                  let port = Int(rest[1])
            else {
                emit("nc wants 'nc "
                     + "[-u] [-z] <host> "
                     + "<port> [words…]'.",
                     .err)
                return
            }
            let host = rest[0]
            let payload = scanOnly
                ? nil
                : (rest.count > 2
                    ? rest[2...].joined(
                        separator: " ") + "\n"
                    : nil)
            netBusy { emit, done in
                BlacksiteNet.tcpExchange(
                    host: host, port: port,
                    udp: udp, payload: payload,
                    telnet: false,
                    idleSeconds: scanOnly
                        ? 2.5 : 6
                ) { text, problem in
                    if let problem = problem {
                        emit("\(host):\(port)"
                             + " — " + problem,
                             .err)
                    } else if scanOnly {
                        emit("\(host):\(port)"
                             + " — open.", .ok)
                    } else if let text = text,
                              !text.isEmpty {
                        for row in text.split(
                            separator: "\n",
                            omittingEmptySubsequences:
                                false) {
                            emit(String(row),
                                 .out)
                        }
                    } else {
                        emit("\(host):\(port)"
                             + " — the door "
                             + "opened; it said "
                             + "nothing.", .out)
                    }
                    done()
                }
            }
        case "telnet":
            guard netAllowed(name),
                  let host = args.first
            else {
                if args.isEmpty {
                    emit("telnet needs a "
                         + "host.", .err)
                }
                return
            }
            let port = args.count > 1
                ? (Int(args[1]) ?? 23) : 23
            netBusy { emit, done in
                BlacksiteNet.tcpExchange(
                    host: host, port: port,
                    udp: false, payload: nil,
                    telnet: true,
                    idleSeconds: 5
                ) { text, problem in
                    if let problem = problem {
                        emit(problem, .err)
                    } else if let text = text,
                              !text.isEmpty {
                        for row in text.split(
                            separator: "\n",
                            omittingEmptySubsequences:
                                false) {
                            emit(String(row),
                                 .out)
                        }
                    } else {
                        emit("the far end "
                             + "said nothing.",
                             .out)
                    }
                    done()
                }
            }
        case "discover":
            guard netAllowed(name) else {
                return
            }
            guard let base = args.first
                ?? localPrefix() else {
                emit("discover: this "
                     + "phone has no local "
                     + "address to sweep "
                     + "from.", .err)
                return
            }
            netBusy { emit, done in
                BlacksitePentest.discover(
                    base: base, emit: emit,
                    done: done)
            }
        case "portscan", "nmap":
            guard netAllowed(name),
                  let host = args.first
            else {
                if args.isEmpty {
                    emit("portscan needs a "
                         + "host.", .err)
                }
                return
            }
            let ports: [Int]
            let spec = args.count > 1
                ? args[1].lowercased() : "top"
            if spec == "all"
                || spec == "full" {
                ports = Array(1...65535)
            } else if spec.contains("-"),
                      !spec.contains(",") {
                let ends = spec.split(
                    separator: "-")
                if ends.count == 2,
                   let lo = Int(ends[0]),
                   let hi = Int(ends[1]),
                   lo >= 1, hi <= 65535,
                   lo <= hi {
                    ports = Array(lo...hi)
                } else {
                    ports = []
                }
            } else if spec == "top" {
                ports = ScanModel.topPorts
                    .map { $0.0 }
            } else {
                ports = spec.split(
                    separator: ",")
                    .compactMap {
                        Int($0.trimmingCharacters(
                            in: .whitespaces)) }
                    .filter {
                        $0 >= 1 && $0 <= 65535
                    }
            }
            guard !ports.isEmpty else {
                emit("portscan: no readable "
                     + "doors in that — "
                     + "try 'top', '1-1024', "
                     + "'all', or a list.",
                     .err)
                return
            }
            netBusy { emit, done in
                BlacksitePentest.portscan(
                    host: host, ports: ports,
                    emit: emit, done: done)
            }
        case "banner":
            guard netAllowed(name),
                  args.count >= 2,
                  let port = Int(args[1])
            else {
                if args.count < 2 {
                    emit("banner wants "
                         + "'banner <host> "
                         + "<port>'.", .err)
                }
                return
            }
            let host = args[0]
            netBusy { emit, done in
                BlacksiteNet.tcpExchange(
                    host: host, port: port,
                    udp: false,
                    payload: BlacksitePentest
                        .probe(for: port,
                               host: host),
                    telnet: false,
                    idleSeconds: 2.2
                ) { text, problem in
                    if let problem = problem {
                        emit(problem, .err)
                    } else if let text = text,
                              !text.isEmpty {
                        for row in text.split(
                            separator: "\n") {
                            emit(String(row),
                                 .out)
                        }
                    } else {
                        emit("\(host):\(port)"
                             + " — the door "
                             + "opened and "
                             + "stayed "
                             + "silent.", .out)
                    }
                    done()
                }
            }
        case "subdomains":
            guard netAllowed(name),
                  let domain = args.first
            else {
                if args.isEmpty {
                    emit("subdomains needs "
                         + "a domain.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.subdomains(
                    domain: domain,
                    emit: emit, done: done)
            }
        case "revdns":
            guard netAllowed(name) else {
                return
            }
            guard let base = args.first
                ?? localPrefix() else {
                emit("revdns: name a /24 "
                     + "— 'revdns "
                     + "192.168.4'.", .err)
                return
            }
            let server = args.count > 1
                ? args[1] : "1.1.1.1"
            netBusy { emit, done in
                BlacksitePentest.revdns(
                    base: base,
                    server: server,
                    emit: emit, done: done)
            }
        case "nbstat":
            guard netAllowed(name),
                  let host = args.first
            else {
                if args.isEmpty {
                    emit("nbstat needs a "
                         + "host.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.nbstat(
                    host: host, emit: emit,
                    done: done)
            }
        case "snmp":
            guard netAllowed(name),
                  let host = args.first
            else {
                if args.isEmpty {
                    emit("snmp needs a "
                         + "host.", .err)
                }
                return
            }
            let community = args.count > 1
                ? args[1] : "public"
            netBusy { emit, done in
                BlacksitePentest.snmp(
                    host: host,
                    community: community,
                    emit: emit, done: done)
            }
        case "upnp":
            guard netAllowed(name) else {
                return
            }
            netBusy { emit, done in
                BlacksitePentest.upnp(
                    emit: emit, done: done)
            }
        case "bonjour":
            guard netAllowed(name) else {
                return
            }
            busy = true
            BlacksitePentest.bonjour(
                emit: out) { [weak self] in
                self?.busy = false
            }
        case "cert":
            guard netAllowed(name),
                  let host = args.first
            else {
                if args.isEmpty {
                    emit("cert needs a "
                         + "host.", .err)
                }
                return
            }
            let port = args.count > 1
                ? (Int(args[1]) ?? 443) : 443
            netBusy { emit, done in
                BlacksitePentest.cert(
                    host: host, port: port,
                    emit: emit, done: done)
            }
        case "webaudit":
            guard netAllowed(name),
                  let url = args.first
            else {
                if args.isEmpty {
                    emit("webaudit needs a "
                         + "URL.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.webaudit(
                    urlText: url, emit: emit,
                    done: done)
            }
        case "methods":
            guard netAllowed(name),
                  let url = args.first
            else {
                if args.isEmpty {
                    emit("methods needs a "
                         + "URL.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.methods(
                    urlText: url, emit: emit,
                    done: done)
            }
        case "dirb":
            guard netAllowed(name),
                  let url = args.first
            else {
                if args.isEmpty {
                    emit("dirb needs a URL "
                         + "— 'dirb "
                         + "http://"
                         + "192.168.4.1'.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.dirb(
                    urlText: url, emit: emit,
                    done: done)
            }
        case "wol":
            guard netAllowed(name),
                  let mac = args.first else {
                if args.isEmpty {
                    emit("wol needs a MAC "
                         + "address.", .err)
                }
                return
            }
            netBusy { emit, done in
                BlacksitePentest.wol(
                    macText: mac, emit: emit,
                    done: done)
            }
        default:
            break
        }
    }

    // MARK: Registries

    private func company(_ args: [String]) {
        guard let raw = args.first else {
            emit("company needs an id — "
                 + "'company 004c' or "
                 + "'company 76'.", .err)
            return
        }
        let id: UInt16?
        if raw.lowercased().hasPrefix("0x") {
            id = UInt16(
                raw.dropFirst(2), radix: 16)
        } else if let decimal = UInt16(raw),
                  raw.count <= 5 {
            id = decimal
        } else {
            id = UInt16(raw, radix: 16)
        }
        guard let id else {
            emit("that is not a company id.",
                 .err)
            return
        }
        let hex = String(format: "0x%04X", id)
        if let curated = Vendors.companyNames[id] {
            emit("\(hex) — \(curated) "
                 + "(the house's curated name)",
                 .ok)
        } else if let name = CompanyRegistry
            .names[id] {
            emit("\(hex) — \(name)", .ok)
        } else {
            emit("\(hex) — unassigned. the "
                 + "registry does not name it, "
                 + "and neither do I.", .err)
        }
    }

    private func port(_ args: [String]) {
        guard let raw = args.first,
              let number = Int(raw) else {
            emit("port needs a number.", .err)
            return
        }
        let udp = args.count > 1
            && args[1].lowercased() == "udp"
        let curated = ScanModel.serviceName(
            for: number, udp: udp)
        let registry = PortRegistry.name(
            number, udp: udp)
        emit("\(number)/\(udp ? "udp" : "tcp") — "
             + "curated: \(curated) · registry: "
             + (registry ?? "unnamed"), .ok)
    }

    // MARK: The house's organs

    private func emcon(_ args: [String]) {
        guard let center = centerOrgans() else {
            return
        }
        guard let word = args.first?.lowercased()
        else {
            emit("EMCON "
                 + EmconCondition.current.declared
                 + " — exposure "
                 + String(format: "%.0f",
                          center.emcon.currentScore(
                            mouth: center.mouth)
                            .value)
                 + " of 100.", .sys)
            return
        }
        switch word {
        case "off", "open":
            center.emcon.deactivate()
            emit("EMCON off — the house is "
                 + "open.", .ok)
        case "charlie", "bravo", "alpha":
            let condition: EmconCondition =
                word == "charlie" ? .charlie
                : word == "bravo" ? .bravo
                : .alpha
            center.emcon.activate(
                mouth: center.mouth,
                condition: condition)
            emit("EMCON "
                 + condition.declared + " set.",
                 .ok)
        default:
            emit("conditions: open, charlie, "
                 + "bravo, alpha.", .err)
        }
    }

    private func centerOrgans()
        -> (mouth: Mouth, emcon: Emcon)? {
        let center = SkelliCenter.shared
        guard let mouth = center.mouth,
              let emcon = center.emcon else {
            emit("the house's organs are not "
                 + "wired yet.", .err)
            return nil
        }
        return (mouth, emcon)
    }

    private func macro(_ args: [String]) {
        let word = args.first?.lowercased()
            ?? "list"
        if word == "list" {
            let saved = MacroStore.load()
            if saved.isEmpty {
                emit("no macros saved.", .sys)
            }
            for macro in saved {
                emit("  \(macro.name) — "
                     + "\(macro.blocks.count) "
                     + "blocks", .out)
            }
            return
        }
        guard word == "run", args.count > 1 else {
            emit("macro list · macro run <name>",
                 .err)
            return
        }
        let wanted = args.dropFirst()
            .joined(separator: " ").lowercased()
        guard let macro = MacroStore.load()
            .first(where: {
                $0.name.lowercased() == wanted
            }) ?? MacroTemplates.all
            .first(where: {
                $0.title.lowercased() == wanted
            })
            .map({ $0.make() }) else {
            emit("no macro by that name in "
                 + "this house.", .err)
            return
        }
        guard let center = centerOrgans(),
              let post = SkelliCenter.shared.post
        else { return }
        MacroRunner.shared.run(
            macro, mouth: center.mouth,
            post: post, emcon: center.emcon,
            book: PayloadBook())
        emit("running \(macro.name) — "
             + "\(macro.blocks.count) blocks. "
             + "'ps' and her room carry it.",
             .ok)
    }

    private func journal(_ args: [String]) {
        let count = args.first.flatMap(Int.init)
            ?? 20
        let events = Journal.events(
            limit: count)
        if events.isEmpty {
            emit("the journal is empty.", .sys)
        }
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        for event in events {
            emit(clock.string(from: event.when)
                 + " [\(event.module)] "
                 + event.text, .sys)
        }
    }

    private func tomato(_ args: [String]) {
        let marks = TomatoMarks.shared
        switch args.first?.lowercased() ?? "list" {
        case "list":
            if marks.marked.isEmpty {
                emit("no one is wearing a "
                     + "tomato.", .sys)
            }
            for ip in marks.marked.sorted() {
                let name = NeighborhoodStore
                    .shared.neighbors
                    .first { $0.ip == ip }?
                    .displayName ?? ip
                emit("🍅 \(name) (\(ip))", .out)
            }
        case "throw":
            guard let ip = args.dropFirst()
                .first else {
                emit("throw needs an address.",
                     .err)
                return
            }
            marks.mark(ip)
            Journal.log("tomato",
                        "console threw a tomato",
                        ip)
            emit("🍅 \(ip) is marked.", .ok)
        case "wipe":
            if args.dropFirst().first == "all" {
                marks.forgetAll()
                emit("every tomato wiped.", .ok)
            } else if let ip = args.dropFirst()
                .first {
                marks.unmark(ip)
                emit("the tomato comes off "
                     + "\(ip).", .ok)
            } else {
                emit("wipe <ip> · wipe all",
                     .err)
            }
        default:
            emit("tomato list · throw <ip> · "
                 + "wipe <ip>|all", .err)
        }
    }

    private func theme(_ args: [String]) {
        let center = ThemeCenter.shared
        guard let name = args.first?.lowercased()
        else {
            emit("wearing: \(center.current.name)",
                 .sys)
            for theme in center.allThemes {
                emit("  \(theme.name)"
                     + (theme.id == center.current.id
                        ? " ●" : ""), .out)
            }
            return
        }
        guard let theme = center.allThemes.first(
            where: {
                $0.name.lowercased() == name
                    || $0.id == name
            }) else {
            emit("no theme by that name — "
                 + "'theme' lists the wardrobe.",
                 .err)
            return
        }
        center.apply(theme)
        emit("the house wears \(theme.name) "
             + "now.", .ok)
    }

    private func haptics(_ args: [String]) {
        switch args.first?.lowercased() {
        case "off":
            UserDefaults.standard.set(
                false, forKey: "house.haptics")
            emit("haptics off — the motor is "
                 + "silent, house-wide.", .ok)
        case "on":
            UserDefaults.standard.set(
                true, forKey: "house.haptics")
            emit("haptics on.", .ok)
        default:
            emit("haptics are "
                 + (Haptics.enabled
                    ? "on" : "off")
                 + " — 'haptics on|off' sets "
                 + "them.", .sys)
        }
    }

    private func ask(_ args: [String]) {
        let words = args.joined(separator: " ")
        guard !words.isEmpty else {
            emit("skelli needs words — "
                 + "'skelli sweep the wire'.",
                 .err)
            return
        }
        SkelliCenter.shared.ask(words)
        emit("asked. she answers in her room "
             + "— 'open skelli' goes there.",
             .sys)
    }

    private func open(_ args: [String]) {
        guard let name = args.first?.lowercased(),
              let tag = Blacksite.tabTags[name]
        else {
            emit("open needs a tab name — "
                 + "skelli, scan, macros, vault…",
                 .err)
            return
        }
        NotificationCenter.default.post(
            name: Blacksite.openTabNotification,
            object: nil,
            userInfo: ["tag": tag])
        emit("going to \(name).", .sys)
    }
}

// MARK: - The decoder bench (shared)

extension Blacksite {
    /// Raw advertisement bytes through the
    /// house's whole reading stack: the
    /// company split, the classifier, the
    /// verdict in the house's words.
    static func decode(hex: String) -> String? {
        let cleaned = hex.lowercased()
            .filter { $0.isHexDigit }
        guard cleaned.count >= 4,
              cleaned.count % 2 == 0 else {
            return nil
        }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(
                index, offsetBy: 2)
            guard let byte = UInt8(
                cleaned[index..<next], radix: 16)
            else { return nil }
            bytes.append(byte)
            index = next
        }
        let company = UInt16(bytes[0])
            | UInt16(bytes[1]) << 8
        let payload = Array(bytes.dropFirst(2))
        let maker = Vendors.companyName(company)
            ?? CompanyRegistry.names[company]
            ?? "unassigned"
        let sighting = Sighting(
            seenAt: Date().timeIntervalSince1970,
            address: "console",
            name: nil, rssi: nil,
            manufacturerData: [company: payload],
            serviceUUIDs: [])
        let reading = Classification.classify(
            sighting)
        var out = "company 0x"
            + String(format: "%04X", company)
            + " — \(maker)\n"
        out += "payload: \(payload.count) bytes\n"
        out += "reads as: \(reading.kind) "
            + "(rank \(reading.rank))"
        for detail in reading.details {
            out += "\n  · \(detail)"
        }
        if reading.trackerShaped {
            out += "\n  · tracker-shaped"
        }
        return out
    }
}

// MARK: - The room

struct BlacksiteView: View {
    @StateObject private var shell = BlacksiteShell()
    @ObservedObject private var themes =
        ThemeCenter.shared
    @ObservedObject private var board =
        ProcessBoard.shared
    @State private var draft = ""
    @State private var historyBack = -1
    @State private var program: Program?
    @FocusState private var inputFocused: Bool
    @State private var rootSize = CGSize.zero
    @State private var wheelOpen = false
    @State private var wheelTapMode = false
    @State private var wheelRotation = 0.0
    @State private var wheelAngle: Double?
    @State private var wheelSelected = 0
    @State private var wheelCancel = false

    enum Program: String, Identifiable {
        case processes, sys, journal, gauntlet,
             macros, decode, files, freedoom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .processes: return "PROCESSES"
            case .sys: return "HOUSE STATE"
            case .journal: return "JOURNAL"
            case .gauntlet: return "GAUNTLET"
            case .macros: return "MACROS"
            case .decode: return "DECODER BENCH"
            case .files: return "FILES"
            case .freedoom: return "FREEDOOM"
            }
        }
        var icon: String {
            switch self {
            case .processes: return "list.bullet.rectangle"
            case .sys: return "house"
            case .journal: return "book"
            case .gauntlet: return "shield.lefthalf.filled"
            case .macros: return "puzzlepiece.extension.fill"
            case .decode: return "waveform.path.ecg"
            case .files: return "folder"
            case .freedoom:
                return "gamecontroller.fill"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.30)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    statusStrip
                    wheelBar
                    terminal
                    inputBar
                }
                .padding(12)
                if wheelOpen {
                    wheelOverlay(size: geo.size)
                }
            }
            .coordinateSpace(
                name: "blacksiteRoot")
            .onAppear {
                rootSize = geo.size
                shell.bootIfNeeded()
                // A hardware keyboard
                // means business: put the
                // cursor in the line.
                if GCKeyboard.coalesced
                    != nil {
                    inputFocused = true
                }
            }
            .onChange(of: geo.size) {
                _, newSize in
                rootSize = newSize
            }
        }
        .sheet(item: $program) { program in
            BlacksiteProgramSheet(program: program)
        }
        .onChange(of: shell.programRequest) {
            _, requested in
            if let requested {
                program = requested
                shell.programRequest = nil
            }
        }
        .fullScreenCover(
            item: $shell.editorSession
        ) { session in
            BlacksiteEditorView(
                path: session.path,
                personality: session.personality,
                onClose: {
                    shell.editorSession = nil
                })
        }
    }

    // MARK: Chrome

    private var statusStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) {
            context in
            HStack(spacing: 10) {
                Text("■ BLACKSITE")
                    .font(.system(.subheadline,
                                  design: .monospaced)
                        .weight(.bold))
                    .foregroundStyle(
                        themes.current.accent)
                Text("OS " + AppInfo.version)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer()
                Text(EmconCondition.current.name)
                    .font(.system(.caption,
                                  design: .monospaced)
                        .weight(.bold))
                    .foregroundStyle(
                        EmconCondition.current
                            == .open
                        ? Color.secondary
                        : Color.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(DevKit.footprintMB()) MB")
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(context.date, style: .time)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 10)
                            .strokeBorder(
                                themes.current.accent
                                    .opacity(0.35),
                                lineWidth: 1)))
        }
    }

    // MARK: The program wheel

    /// The tiled rail is gone — the
    /// programs ride a rotary wheel. Hold
    /// the bar and the wheel blooms in the
    /// middle of the room; drag to spin it;
    /// let go and whatever sits under the
    /// marker at the top opens. Drag into
    /// the hub to call it off. A plain tap
    /// opens the wheel for tapping instead.
    private var wheelBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "steeringwheel")
            Text("PROGRAMS")
                .font(.system(.caption,
                              design: .monospaced)
                    .weight(.semibold))
            Spacer()
            Text("hold + spin")
                .font(.system(.caption2,
                              design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 10)
                        .strokeBorder(
                            Color.white
                                .opacity(0.14),
                            lineWidth: 1)))
        .contentShape(Rectangle())
        .onTapGesture {
            wheelTapMode = true
            openWheel()
        }
        .gesture(wheelGesture)
    }

    private var wheelGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(
                before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace:
                        .named("blacksiteRoot")))
            .onChanged { value in
                switch value {
                case .first:
                    if !wheelOpen { openWheel() }
                case .second(_, let drag):
                    if let drag = drag {
                        spinWheel(
                            to: drag.location)
                    }
                }
            }
            .onEnded { value in
                if case .second(_, let drag)
                    = value, let drag = drag {
                    finishWheel(
                        at: drag.location)
                } else if wheelOpen {
                    wheelTapMode = true
                }
            }
    }

    private func openWheel() {
        wheelOpen = true
        wheelSelected = selectedIndex()
        Haptics.press()
    }

    private func closeWheel() {
        wheelOpen = false
        wheelTapMode = false
        wheelAngle = nil
        wheelCancel = false
    }

    private var wheelStep: Double {
        360.0 / Double(Program.allCases.count)
    }

    /// Degrees folded into -180...180.
    private func wrapDegrees(_ value: Double)
        -> Double {
        var folded = value.truncatingRemainder(
            dividingBy: 360)
        if folded > 180 { folded -= 360 }
        if folded < -180 { folded += 360 }
        return folded
    }

    /// The program nearest the top marker.
    private func selectedIndex() -> Int {
        var best = 0
        var bestGap =
            Double.greatestFiniteMagnitude
        for index in
            Program.allCases.indices {
            let heading = wheelRotation
                + Double(index) * wheelStep
            let gap = abs(wrapDegrees(heading))
            if gap < bestGap {
                bestGap = gap
                best = index
            }
        }
        return best
    }

    private func spinWheel(to point: CGPoint) {
        let center = CGPoint(
            x: rootSize.width / 2,
            y: rootSize.height / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        wheelCancel = (dx * dx + dy * dy)
            < 52 * 52
        let angle = atan2(dy, dx) * 180 / .pi
        if let last = wheelAngle {
            wheelRotation += wrapDegrees(
                angle - last)
        }
        wheelAngle = angle
        let picked = selectedIndex()
        if picked != wheelSelected {
            wheelSelected = picked
            Haptics.select()
        }
    }

    private func finishWheel(at point: CGPoint) {
        spinWheel(to: point)
        wheelAngle = nil
        if wheelCancel {
            closeWheel()
            return
        }
        let picked = selectedIndex()
        let gap = wrapDegrees(
            wheelRotation
            + Double(picked) * wheelStep)
        withAnimation(
            .spring(response: 0.3,
                    dampingFraction: 0.8)) {
            wheelRotation -= gap
        }
        let item = Program.allCases[picked]
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.24) {
            program = item
            closeWheel()
        }
    }

    private func wheelOverlay(size: CGSize)
        -> some View {
        let diameter = max(
            250, min(340,
                     min(size.width,
                         size.height) - 40))
        let radius = diameter / 2 - 42
        let center = CGPoint(x: size.width / 2,
                             y: size.height / 2)
        return ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    if wheelTapMode {
                        closeWheel()
                    }
                }
            Circle()
                .strokeBorder(
                    Color.white.opacity(0.16),
                    lineWidth: 1)
                .frame(width: diameter,
                       height: diameter)
                .position(center)
            Image(systemName:
                    "arrowtriangle.down.fill")
                .font(.caption)
                .foregroundStyle(
                    themes.current.accent)
                .position(
                    x: center.x,
                    y: center.y
                        - diameter / 2 - 12)
            ForEach(
                Array(Program.allCases
                    .enumerated()),
                id: \.offset
            ) { index, item in
                let radians = (wheelRotation
                    + Double(index) * wheelStep
                    - 90) * .pi / 180
                wheelSegment(
                    item,
                    selected:
                        index == wheelSelected)
                    .position(
                        x: center.x + radius
                            * cos(radians),
                        y: center.y + radius
                            * sin(radians))
            }
            wheelHub
                .position(center)
        }
        .frame(width: size.width,
               height: size.height)
    }

    private func wheelSegment(
        _ item: Program, selected: Bool
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.body)
            Text(item.title)
                .font(.system(
                    size: 8,
                    design: .monospaced)
                    .weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 72, height: 72)
        .background(
            Circle()
                .fill(Color.white.opacity(
                    selected ? 0.16 : 0.07))
                .overlay(
                    Circle().strokeBorder(
                        selected
                        ? themes.current.accent
                        : Color.white
                            .opacity(0.18),
                        lineWidth:
                            selected ? 2 : 1)))
        .foregroundStyle(.primary)
        .scaleEffect(selected ? 1.12 : 1.0)
        .onTapGesture {
            if wheelTapMode {
                program = item
                closeWheel()
            }
        }
    }

    private var wheelHub: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.65))
                .overlay(
                    Circle().strokeBorder(
                        wheelCancel
                        ? Color.red
                            .opacity(0.8)
                        : Color.white
                            .opacity(0.2),
                        lineWidth: 1))
            Text(wheelCancel
                 ? "LET GO\nTO CANCEL"
                 : "SPIN")
                .font(.system(.caption2,
                              design: .monospaced)
                    .weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    wheelCancel
                    ? AnyShapeStyle(Color.red)
                    : AnyShapeStyle(
                        Color.secondary))
        }
        .frame(width: 84, height: 84)
        .onTapGesture {
            if wheelTapMode { closeWheel() }
        }
    }

    // MARK: The terminal

    private var terminal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading,
                           spacing: 3) {
                    ForEach(shell.lines) { line in
                        Group {
                            if let image = line.image {
                                VStack(alignment: .leading,
                                       spacing: 4) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(
                                            maxWidth: 300,
                                            maxHeight: 300)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: 8))
                                    Text(line.text)
                                        .font(.system(
                                            .caption2,
                                            design: .monospaced))
                                        .foregroundStyle(
                                            .secondary)
                                }
                            } else {
                                lineText(line)
                                    // A pointer can
                                    // select and copy
                                    // console output;
                                    // on glass it
                                    // changes nothing.
                                    .textSelection(
                                        .enabled)
                            }
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .id(line.id)
                    }
                    if shell.busy {
                        Text("… working")
                            .font(.system(
                                .caption,
                                design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
            .background(
                GeometryReader { geo in
                    ZStack {
                        // The console wears its
                        // wallpaper inside: the
                        // engine's own art
                        // behind the text,
                        // washed dark enough
                        // to read by.
                        BlacksiteWallpaperView(
                            width: geo.size.width,
                            height: geo.size.height)
                        Color.black
                            .opacity(0.66)
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 12))
                .overlay(
                    RoundedRectangle(
                        cornerRadius: 12)
                        .strokeBorder(
                            Color.white
                                .opacity(0.12),
                            lineWidth: 1)))
            .onChange(of: shell.lines.count) {
                _ in
                if let last = shell.lines.last {
                    withAnimation(
                        .easeOut(duration: 0.2)) {
                        proxy.scrollTo(
                            last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// One transcript line, dressed: a
    /// line carrying ANSI colour codes
    /// renders through the SGR reader in
    /// its own colours; any other line
    /// takes the kind's colour, as it
    /// always has.
    private func lineText(
        _ line: BlacksiteShell.Line) -> Text {
        let base = Font.system(.caption,
                               design: .monospaced)
        if line.text.contains("\u{1B}[") {
            return Text(ANSITerm.attributed(
                line.text, baseFont: base,
                baseColor: color(for: line.kind)))
        }
        return Text(line.text)
            .font(base)
            .foregroundColor(
                color(for: line.kind))
    }

    private func color(
        for kind: BlacksiteShell.Line.Kind) -> Color {
        switch kind {
        case .cmd: return themes.current.accent
        case .out: return Color.primary.opacity(0.92)
        case .ok: return themes.current.glow
        case .err: return Color.orange
        case .sys: return Color.secondary
        }
    }

    // MARK: The input line

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("▸")
                .font(.system(.body,
                              design: .monospaced)
                    .weight(.bold))
                .foregroundStyle(themes.current.accent)
            TextField("", text: $draft)
                .font(.system(.body,
                              design: .monospaced))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($inputFocused)
                .onSubmit(send)
                // A hardware keyboard drives
                // the shell like a shell: the
                // arrows walk history, Tab
                // completes, Esc kills the
                // line, Ctrl+L clears and
                // Ctrl+U kills the line.
                .onKeyPress(.upArrow) {
                    stepHistory(1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    stepHistory(-1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    draft = ""
                    historyBack = -1
                    return .handled
                }
                .onKeyPress(.tab) {
                    if let full = shell
                        .completed(draft) {
                        draft = full
                    }
                    return .handled
                }
                .onKeyPress { press in
                    guard press.modifiers
                        .contains(.control)
                    else { return .ignored }
                    switch press.key.character {
                    case "l":
                        shell.run("clear")
                        return .handled
                    case "u":
                        draft = ""
                        historyBack = -1
                        return .handled
                    default:
                        return .ignored
                    }
                }
            Button {
                stepHistory(1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(shell.historyCount == 0)
            .hoverEffect(.highlight)
            Button {
                stepHistory(-1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(historyBack < 0)
            .hoverEffect(.highlight)
            Button {
                Haptics.tap()
                send()
            } label: {
                Text("RUN")
                    .font(.system(.caption,
                                  design: .monospaced)
                        .weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 7)
                            .fill(themes.current
                                .accent))
                    .foregroundStyle(.black)
            }
            .hoverEffect(.highlight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06)))
    }

    private func send() {
        let text = draft
        draft = ""
        historyBack = -1
        shell.run(text)
    }

    private func stepHistory(_ direction: Int) {
        let next = historyBack + direction
        if next < 0 {
            historyBack = -1
            draft = ""
            return
        }
        if let recalled = shell.historyBack(next) {
            historyBack = next
            draft = recalled
        }
    }
}

extension BlacksiteView.Program: CaseIterable {}

// MARK: - The programs

private struct BlacksiteProgramSheet: View {
    let program: BlacksiteView.Program
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(program.title)
                .navigationBarTitleDisplayMode(
                    .inline)
                .toolbar {
                    ToolbarItem(
                        placement: .confirmationAction) {
                        Button("Done") {
                            Haptics.tap()
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch program {
        case .processes:
            ProcessBoardView(embedded: true)
        case .sys:
            BlacksiteSysProgram()
        case .journal:
            BlacksiteJournalProgram()
        case .gauntlet:
            BlacksiteGauntletProgram()
        case .macros:
            BlacksiteMacrosProgram()
        case .decode:
            BlacksiteDecodeProgram()
        case .files:
            BlacksiteFilesProgram()
        case .freedoom:
            FreedoomView()
        }
    }
}

private struct BlacksiteSysProgram: View {
    var body: some View {
        ScrollView {
            Text(DevKit.houseState())
                .font(.system(.caption,
                              design: .monospaced))
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }
}

private struct BlacksiteJournalProgram: View {
    var body: some View {
        List(Journal.events(limit: 100)) { event in
            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.system(.caption,
                                  design: .monospaced))
                Text(event.module + " · "
                     + event.kind)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }
}

private struct BlacksiteGauntletProgram: View {
    @ObservedObject private var gauntlet =
        Gauntlet.shared

    var body: some View {
        VStack(spacing: 14) {
            if gauntlet.running {
                ProgressView()
                Text(gauntlet.stageName + " — "
                     + gauntlet.currentStep)
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(gauntlet.passed) passed · "
                     + "\(gauntlet.failed) failed · "
                     + "of \(gauntlet.total)")
                    .font(.system(.caption,
                                  design: .monospaced))
            } else {
                Text(Gauntlet.lastSummary())
                    .font(.system(.caption,
                                  design: .monospaced))
                    .foregroundStyle(.secondary)
                Button {
                    Haptics.press()
                    gauntlet.run()
                } label: {
                    Label("Run the gauntlet",
                          systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }
}

private struct BlacksiteMacrosProgram: View {
    @State private var macros: [Macro] = []

    var body: some View {
        List {
            ForEach(macros) { macro in
                HStack {
                    VStack(alignment: .leading,
                           spacing: 2) {
                        Text(macro.name)
                            .font(.system(
                                .body,
                                design: .monospaced))
                        Text("\(macro.blocks.count) "
                             + "blocks")
                            .font(.caption)
                            .foregroundStyle(
                                .secondary)
                    }
                    Spacer()
                    Button("Run") {
                        launch(macro)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        MacroRunner.shared.running)
                }
            }
        }
        .listStyle(.plain)
        .onAppear { macros = MacroStore.load() }
    }

    private func launch(_ macro: Macro) {
        let center = SkelliCenter.shared
        guard let mouth = center.mouth,
              let emcon = center.emcon,
              let post = center.post else {
            return
        }
        Haptics.press()
        MacroRunner.shared.run(
            macro, mouth: mouth, post: post,
            emcon: emcon, book: PayloadBook())
    }
}

private struct BlacksiteDecodeProgram: View {
    @State private var hex = ""
    @State private var reading: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Raw advertisement bytes — the "
                 + "first two are the company, "
                 + "little-endian. The house's "
                 + "whole reading stack answers.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("4c001006…", text: $hex)
                .font(.system(.body,
                              design: .monospaced))
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            Button("Decode") {
                Haptics.tap()
                reading = Blacksite.decode(hex: hex)
                    ?? "those are not hex bytes "
                    + "the stack can read."
            }
            .buttonStyle(.borderedProminent)
            if let reading {
                Text(reading)
                    .font(.system(.callout,
                                  design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding()
    }
}

private struct BlacksiteFilesProgram: View {
    @State private var dir = "/home"
    @State private var tick = 0
    @State private var editPath: String?
    @State private var showEditor = false

    private var entries:
        [(name: String, isDir: Bool)] {
        _ = tick
        return BlacksiteFS.list(dir) ?? []
    }

    var body: some View {
        List {
            Section {
                if dir != "/" {
                    Button {
                        dir = BlacksiteFS.parent(
                            of: dir)
                    } label: {
                        Label(".. (up)",
                              systemImage:
                                "arrow.up.folder")
                    }
                }
                ForEach(entries, id: \.name) {
                    entry in
                    if entry.isDir {
                        Button {
                            dir = dir == "/"
                                ? "/" + entry.name
                                : dir + "/"
                                    + entry.name
                        } label: {
                            Label(entry.name,
                                  systemImage: "folder")
                        }
                    } else {
                        Button {
                            editPath = dir == "/"
                                ? "/" + entry.name
                                : dir + "/"
                                    + entry.name
                            showEditor = true
                        } label: {
                            HStack {
                                Label(entry.name,
                                      systemImage:
                                        "doc.text")
                                Spacer()
                                Text("\(size(of: entry.name)) B")
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary)
                            }
                        }
                    }
                }
                if entries.isEmpty {
                    Text("(empty)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(dir)
                    .font(.system(.caption,
                                  design: .monospaced))
            }
            Section {
                Button {
                    tick += 1
                } label: {
                    Label("Refresh",
                          systemImage:
                            "arrow.clockwise")
                }
            }
        }
        .listStyle(.plain)
        .fullScreenCover(isPresented: $showEditor) {
            BlacksiteEditorView(
                path: editPath,
                personality: .vim,
                onClose: { showEditor = false })
        }
    }

    private func size(of name: String) -> Int {
        let path = dir == "/"
            ? "/" + name : dir + "/" + name
        return BlacksiteFS.fileSize(path) ?? 0
    }
}
