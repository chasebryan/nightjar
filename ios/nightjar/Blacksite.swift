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

    private let scanner = ScanModel()
    private let recon = Recon()
    private var history: [String] = []
    private var booted = false

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
    private var scriptDepth = 0

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
        "scan", "knock", "census", "decode",
        "company", "port", "emcon", "macro",
        "gauntlet", "journal", "log", "tomato",
        "freedoom", "doom",
        "theme", "haptics", "skelli", "open",
        "halt", "pwd", "cd", "ls", "mkdir",
        "touch", "cat", "echo", "cp", "mv",
        "rm", "tree", "head", "tail", "wc",
        "grep", "find", "stat", "env",
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
        if capturing {
            if kind == .err { stageError = true }
            captureStack[captureStack.count - 1]
                .append(text)
            return
        }
        let append = { [weak self] in
            guard let self = self else { return }
            self.lines.append(
                Line(text: text, kind: kind,
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
        BlacksiteFS.binNames =
            BlacksiteShell.builtinNames
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
        let command = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        emit("▸ " + command, .cmd)
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

    private func envValue(_ name: String)
        -> String {
        if name == "PWD" { return cwd }
        if name == "?" {
            return String(lastStatus)
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
        for part in splitSequence(line) {
            let text = part.text
                .trimmingCharacters(
                    in: .whitespaces)
            if text.isEmpty { continue }
            if part.gate == .and,
               lastStatus != 0 { continue }
            execPipeline(text, stdin: stdin)
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
            if !isLast || redirect != nil {
                let text = captureOutput {
                    runStage(stage, stdin: input)
                }
                lastStatus = stageError ? 1 : 0
                if isLast, let redirect = redirect {
                    writeRedirect(text, redirect)
                } else {
                    input = text
                }
            } else {
                runStage(stage, stdin: input)
                lastStatus = stageError ? 1 : 0
            }
        }
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

    // MARK: One stage

    private func runStage(_ stage: String,
                          stdin: String) {
        stageInput = stdin
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
        let args = Array(tokens.dropFirst())
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
            if words.first == "-n" {
                words.removeFirst()
            }
            emit(words.joined(separator: " "))
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
        case "stat":
            statCommand(args)
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
                    emit(pad(entry.name + "/", 26)
                         + "dir", .out)
                } else {
                    let child = target == "/"
                        ? "/" + entry.name
                        : target + "/" + entry.name
                    let size = BlacksiteFS
                        .fileSize(child) ?? 0
                    emit(pad(entry.name, 26)
                         + "\(size)", .out)
                }
            } else {
                emit(entry.name
                     + (entry.isDir ? "/" : ""),
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
                emit(row, .out)
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
        busy = true
        BlacksiteJS.shared.printSink =
            { [weak self] line in
                self?.emit(line)
            }
        BlacksiteJS.shared.eval(source) {
            [weak self] result, error in
            guard let self = self else { return }
            self.busy = false
            if let error = error {
                self.emit("js: \(error)", .err)
            } else if let result = result {
                self.emit(result, .out)
            }
        }
    }

    /// `python3 [file.py [args…]]` — the
    /// house's small python (BlacksitePy).
    /// Bare, it lists what the subset
    /// carries and what it leaves out.
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
        busy = true
        BlacksitePy.runFile(
            path, args: args,
            emit: emitBlock) { [weak self] in
                self?.busy = false
            }
    }

    private func runFileCommand(_ args: [String]) {
        guard let file = args.first else {
            emit("run <file.js | file.py | "
                 + "file.sh>", .err)
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
            busy = true
            BlacksiteJS.shared.printSink =
                { [weak self] line in
                    self?.emit(line)
                }
            BlacksiteJS.shared.runFile(
                target,
                args: Array(args.dropFirst())
            ) { [weak self] error in
                guard let self = self
                else { return }
                self.busy = false
                if let error = error {
                    self.emit("run: \(error)",
                              .err)
                }
            }
        } else if target.hasSuffix(".py") {
            guard !capturing else {
                emit("programs run live — they "
                     + "cannot be piped.", .err)
                return
            }
            busy = true
            BlacksitePy.runFile(
                target, args: [file]
                    + Array(
                        args.dropFirst()),
                emit: emitBlock) {
                    [weak self] in
                    self?.busy = false
                }
        } else if target.hasSuffix(".sh")
                    || target.hasSuffix(".bsh") {
            runScript(target)
        } else {
            emit("run takes a .js, .py or "
                 + ".sh "
                 + "file — '\(file)' is "
                 + "neither.", .err)
        }
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
        guard scriptDepth < 8 else {
            emit("scripts nest too deep — "
                 + "eight is the house limit.",
                 .err)
            return
        }
        guard let text = BlacksiteFS.readText(
            target) else {
            emit("cannot read \(target).",
                 .err)
            return
        }
        scriptDepth += 1
        for rawLine in text.components(
            separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(
                in: .whitespaces)
            if line.isEmpty
                || line.hasPrefix("#") {
                continue
            }
            execLine(line, stdin: "")
        }
        scriptDepth -= 1
    }

    private func jsInvoke(_ name: String,
                          _ args: [String]) {
        guard !capturing else {
            emit("\(name) runs live — package "
                 + "commands cannot be "
                 + "piped.", .err)
            return
        }
        busy = true
        BlacksiteJS.shared.printSink =
            { [weak self] line in
                self?.emit(line)
            }
        BlacksiteJS.shared.callCommand(
            name, args: args
        ) { [weak self] text, error in
            guard let self = self else { return }
            self.busy = false
            if let error = error {
                self.emit("\(name): \(error)",
                          .err)
            } else if let text = text,
                      !text.isEmpty {
                self.emit(text, .out)
            }
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
            ]),
            ("editors", [
                ("vim [file]", "the modal church — :help inside"),
                ("emacs [file]", "the chord church — M-x help inside"),
                ("nano [file]", "the plain church — ^G lists its keys"),
                ("edit [file]", "whichever $EDITOR names"),
            ]),
            ("code — the engine room", [
                ("js <code>", "JavaScript, compiled + run (node works too)"),
                ("run <file.js>", "run a program from the files"),
                ("run <file.sh> · sh", "run a shell script"),
                ("python3 <file.py>", "the house's small python — python3 alone lists its edges"),
                ("run <file.py>", "run a python program"),
                ("NAME=value · export", "shell variables — $NAME ${NAME} $?"),
                ("a | b", "pipe one command through another"),
                ("cmd > file · >>", "write · append output to a file"),
                ("$(cmd)", "run it, use what it said"),
                ("a ; b · a && b", "then · then-if-it-worked"),
            ]),
            ("packages", [
                ("pkg list", "installed + the bundled shelf"),
                ("pkg install <name>", "install a bundled package"),
                ("pkg install <url>", "install a package from the wire"),
                ("pkg remove <name>", "uninstall"),
                ("pkg commands", "the commands packages gave the shell"),
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
        if board.active.isEmpty {
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
                                Text(line.text)
                                    .font(.system(
                                        .caption,
                                        design: .monospaced))
                                    .foregroundStyle(
                                        color(
                                            for: line.kind))
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
