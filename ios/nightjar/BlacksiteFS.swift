import Foundation

/// BLACKSITE FS — the console's own file
/// system (the operator's order, 2026-10-19:
/// "it should have its own file directory").
///
/// A chroot-shaped tree living in the app's
/// Application Support, seeded on first
/// touch: /home is the operator's desk, /etc
/// holds the house papers, /packages is
/// where installed packages live, /tmp is
/// scratch, and /bin is a mirror — it lists
/// the shell's built-in commands as files,
/// the way a real /bin does, and refuses
/// writes. Paths can never climb out of the
/// root: `..` at the top stays at the top,
/// like a chroot. Everything the shell, the
/// editors and the JavaScript engine touch
/// goes through here, so the four of them
/// always agree about what a file is.
enum BlacksiteFS {
    /// The shell's built-in command names,
    /// mirrored as /bin's contents. The shell
    /// sets this at boot.
    static var binNames: [String] = []

    static let home = "/home"

    // MARK: The root

    static func rootURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
            ?? FileManager.default
                .temporaryDirectory
        let root = base.appendingPathComponent(
            "Blacksite", isDirectory: true)
        seedIfNeeded(root)
        return root
    }

    static func url(forVirtual path: String)
        -> URL {
        let clean = normalize(path, cwd: "/")
        return rootURL().appendingPathComponent(
            String(clean.dropFirst()))
    }

    private static func seedIfNeeded(_ root: URL) {
        let fm = FileManager.default
        let motd = root.appendingPathComponent(
            "etc/motd")
        guard !fm.fileExists(
            atPath: motd.path) else { return }
        for dir in ["bin", "etc", "home", "tmp",
                    "packages", "var"] {
            try? fm.createDirectory(
                at: root.appendingPathComponent(
                    dir, isDirectory: true),
                withIntermediateDirectories: true)
        }
        writeSeed(motd, text: motdText)
        writeSeed(
            root.appendingPathComponent(
                "home/welcome.txt"),
            text: welcomeText)
        writeSeed(
            root.appendingPathComponent(
                "home/hello.js"),
            text: helloJS)
    }

    private static func writeSeed(_ url: URL,
                                  text: String) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true,
                        encoding: .utf8)
    }

    // MARK: Paths

    /// Resolve a typed path against the
    /// working directory into an absolute
    /// virtual path. Chroot rules: the root
    /// is a floor — `..` cannot escape it.
    static func normalize(_ path: String,
                          cwd: String) -> String {
        var raw = path
        if raw == "~" || raw.hasPrefix("~/") {
            raw = home + String(raw.dropFirst())
        }
        if !raw.hasPrefix("/") {
            raw = cwd + "/" + raw
        }
        var parts: [String] = []
        for piece in raw.split(separator: "/") {
            if piece == "." { continue }
            if piece == ".." {
                if !parts.isEmpty {
                    parts.removeLast()
                }
                continue
            }
            parts.append(String(piece))
        }
        return "/" + parts.joined(separator: "/")
    }

    static func parent(of path: String) -> String {
        let clean = normalize(path, cwd: "/")
        guard clean != "/" else { return "/" }
        let cut = clean.lastIndex(of: "/")
            ?? clean.startIndex
        let head = String(clean[..<cut])
        return head.isEmpty ? "/" : head
    }

    static func baseName(of path: String)
        -> String {
        let clean = normalize(path, cwd: "/")
        guard clean != "/" else { return "/" }
        return clean.split(separator: "/")
            .last.map(String.init) ?? clean
    }

    // MARK: Reading the tree

    static func exists(_ path: String) -> Bool {
        let clean = normalize(path, cwd: "/")
        if clean == "/bin"
            || clean.hasPrefix("/bin/") {
            if clean == "/bin" { return true }
            return binNames.contains(
                baseName(of: clean))
        }
        return FileManager.default.fileExists(
            atPath: url(forVirtual: clean).path)
    }

    static func isDirectory(_ path: String)
        -> Bool {
        let clean = normalize(path, cwd: "/")
        if clean == "/bin" { return true }
        if clean.hasPrefix("/bin/") { return false }
        var isDir: ObjCBool = false
        let found = FileManager.default
            .fileExists(
                atPath: url(forVirtual: clean).path,
                isDirectory: &isDir)
        return found && isDir.boolValue
    }

    /// Directory entries as (name, isDir),
    /// sorted, dotfiles included. nil when
    /// the path is not a directory.
    static func list(_ path: String)
        -> [(name: String, isDir: Bool)]? {
        let clean = normalize(path, cwd: "/")
        if clean == "/bin" {
            return binNames.sorted().map {
                (name: $0, isDir: false)
            }
        }
        guard isDirectory(clean) else {
            return nil
        }
        let fm = FileManager.default
        guard let names = try? fm
            .contentsOfDirectory(
                atPath: url(
                    forVirtual: clean).path)
        else { return nil }
        return names.sorted().map { name in
            (name: name,
             isDir: isDirectory(
                clean + "/" + name))
        }
    }

    static func readText(_ path: String)
        -> String? {
        let clean = normalize(path, cwd: "/")
        if clean.hasPrefix("/bin/") {
            let name = baseName(of: clean)
            guard binNames.contains(name) else {
                return nil
            }
            return "built-in command: \(name) — "
                + "it lives in the shell itself. "
                + "'help' shows its papers."
        }
        guard !isDirectory(clean) else {
            return nil
        }
        return try? String(
            contentsOf: url(forVirtual: clean),
            encoding: .utf8)
    }

    static func fileSize(_ path: String) -> Int? {
        let clean = normalize(path, cwd: "/")
        if clean.hasPrefix("/bin/") {
            return readText(clean)?.count
        }
        let attrs = try? FileManager.default
            .attributesOfItem(
                atPath: url(
                    forVirtual: clean).path)
        return attrs?[.size] as? Int
    }

    // MARK: Writing the tree

    @discardableResult
    static func writeText(_ path: String,
                          text: String,
                          append: Bool = false)
        -> Bool {
        let clean = normalize(path, cwd: "/")
        guard !clean.hasPrefix("/bin") else {
            return false
        }
        guard !isDirectory(clean) else {
            return false
        }
        let target = url(forVirtual: clean)
        try? FileManager.default.createDirectory(
            at: target
                .deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if append,
           let old = readText(clean) {
            return (try? (old + text).write(
                to: target, atomically: true,
                encoding: .utf8)) != nil
        }
        return (try? text.write(
            to: target, atomically: true,
            encoding: .utf8)) != nil
    }

    /// Binary write — the graphics engine
    /// files its PNGs through here.
    @discardableResult
    static func writeData(_ path: String,
                          data: Data) -> Bool {
        let clean = normalize(path, cwd: "/")
        guard !clean.hasPrefix("/bin"),
              !isDirectory(clean) else {
            return false
        }
        let target = url(forVirtual: clean)
        try? FileManager.default.createDirectory(
            at: target
                .deletingLastPathComponent(),
            withIntermediateDirectories: true)
        return (try? data.write(to: target))
            != nil
    }

    static func readData(_ path: String)
        -> Data? {
        let clean = normalize(path, cwd: "/")
        guard !isDirectory(clean) else {
            return nil
        }
        return try? Data(
            contentsOf: url(forVirtual: clean))
    }

    @discardableResult
    static func makeDir(_ path: String) -> Bool {
        let clean = normalize(path, cwd: "/")
        guard !clean.hasPrefix("/bin") else {
            return false
        }
        return (try? FileManager.default
            .createDirectory(
                at: url(forVirtual: clean),
                withIntermediateDirectories: true))
            != nil
    }

    @discardableResult
    static func remove(_ path: String) -> Bool {
        let clean = normalize(path, cwd: "/")
        guard clean != "/",
              !clean.hasPrefix("/bin") else {
            return false
        }
        return (try? FileManager.default
            .removeItem(
                at: url(forVirtual: clean)))
            != nil
    }

    @discardableResult
    static func copy(from: String, to: String)
        -> Bool {
        let src = normalize(from, cwd: "/")
        let dst = normalize(to, cwd: "/")
        guard !dst.hasPrefix("/bin"),
              exists(src) else { return false }
        if isDirectory(src) { return false }
        guard let text = readText(src) else {
            return false
        }
        return writeText(dst, text: text)
    }

    @discardableResult
    static func move(from: String, to: String)
        -> Bool {
        guard copy(from: from, to: to) else {
            return false
        }
        return remove(from)
    }

    /// Every file under a directory,
    /// recursively, as virtual paths —
    /// the find/grep walk.
    static func walk(_ path: String) -> [String] {
        let clean = normalize(path, cwd: "/")
        guard let entries = list(clean) else {
            return exists(clean) ? [clean] : []
        }
        var out: [String] = []
        for entry in entries {
            let child = clean == "/"
                ? "/" + entry.name
                : clean + "/" + entry.name
            if entry.isDir {
                out += walk(child)
            } else {
                out.append(child)
            }
        }
        return out
    }

    // MARK: Seed papers

    private static let motdText = """
BLACKSITE — the house's own machine room.
Files here are yours: they persist, they
are never shown to anyone else, and no
gate in the house reads them but yours.
"""

    private static let welcomeText = """
welcome to the blacksite.

your desk is /home. the tree:
/bin       the shell's built-in commands
/etc       house papers (cat /etc/motd)
/home      your files
/packages  installed packages live here
/tmp       scratch — wipe it freely
/var       the house's scratch papers

try:
  ls /            walk the whole tree
  cat welcome.txt read this again, slower
  vim notes.txt   write something (i = insert,
                  esc, then :wq writes + quits)
  emacs notes.txt the other church: C-x C-s
                  saves, C-x C-c leaves
  run hello.js    compile + run a program
  js 2 + 2        the engine, inline
  pkg list        what can be installed
  echo "mine" > first.txt   then: cat first.txt
  sys | grep chat pipe the house through grep

help lists every command. the editors are
real: vim is modal, emacs has its chords,
the kill ring, buffers and M-x.
"""

    private static let helloJS = """
// hello.js — your first blacksite program.
// run it:  run hello.js
// the engine is JavaScriptCore: full
// JavaScript, compiled and run for real.
print("hello from inside the house.");
var doors = 12093;
print("the port registry holds " + doors
      + " named doors.");
for (var i = 1; i <= 3; i++) {
    print("floor " + i + " — swept clean.");
}
print("write() and read() reach the files:"
      + " write('/tmp/proof.txt', 'i ran')");
"""
}
