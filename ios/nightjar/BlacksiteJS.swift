import Foundation
import JavaScriptCore

/// BLACKSITE JS — the console's engine room
/// (the operator's orders, 2026-10-19:
/// program in any language, compile,
/// execute; install packages).
///
/// The execution engine is JavaScriptCore —
/// the one real code engine iOS lets an app
/// carry: full JavaScript, JIT-compiled and
/// run for real, no interpreter theatre.
/// Scripts live in the console's own file
/// system, reach it through read()/write(),
/// read the house through house.state(),
/// draw through gfx, and packages installed
/// into /packages register brand-new shell
/// commands with registerCommand() — the
/// shell grows the way a real system grows:
/// by installing software.
///
/// Everything runs on one serial queue;
/// print() streams to the terminal live.
final class BlacksiteJS {
    static let shared = BlacksiteJS()

    /// Where print() goes while code runs.
    /// The shell sets this before every run.
    var printSink: ((String) -> Void)?

    private let queue = DispatchQueue(
        label: "blacksite.js")
    private var commandContext: JSContext?
    private var registered: [String: JSValue] = [:]
    private var loadedPackages: [String] = []
    private var bridgeReady = false

    private final class RunState {
        var error: String?
    }

    // MARK: Lifecycle

    /// Build the persistent command context
    /// and load every installed package.
    /// Idempotent; call before any JS work.
    func prepare() {
        queue.sync { prepareLocked() }
    }

    private func prepareLocked() {
        guard !bridgeReady else { return }
        bridgeReady = true
        rebuildCommandContext()
    }

    private func rebuildCommandContext() {
        registered = [:]
        loadedPackages = []
        let context = JSContext()
        commandContext = context
        guard let context = context else {
            return
        }
        installBridge(into: context,
                      state: RunState())
        for name in installedPackages() {
            loadPackage(name, into: context)
        }
    }

    /// Drop the command context and reload
    /// every package from disk — the remove /
    /// install path, so no ghost commands.
    func reloadPackages() {
        queue.async { [weak self] in
            self?.rebuildCommandContext()
        }
    }

    // MARK: The bridge

    private func installBridge(into context: JSContext,
                               state: RunState) {
        context.exceptionHandler = { _, value in
            state.error = value?.toString()
                ?? "unknown error"
        }
        let printBlock: @convention(block)
            (JSValue) -> Void = { [weak self] value in
            let text = value.isUndefined
                ? "" : (value.toString() ?? "")
            self?.printSink?(text)
        }
        context.setObject(
            printBlock,
            forKeyedSubscript: "__print" as NSString)
        let existsBlock: @convention(block)
            (String) -> Bool = { path in
            BlacksiteFS.exists(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home))
        }
        context.setObject(
            existsBlock,
            forKeyedSubscript: "__exists" as NSString)
        let readBlock: @convention(block)
            (String) -> String = { path in
            BlacksiteFS.readText(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home))
                ?? ""
        }
        context.setObject(
            readBlock,
            forKeyedSubscript: "__read" as NSString)
        let writeBlock: @convention(block)
            (String, String) -> Bool = { path, text in
            BlacksiteFS.writeText(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home),
                text: text)
        }
        context.setObject(
            writeBlock,
            forKeyedSubscript: "__write" as NSString)
        let listBlock: @convention(block)
            (String) -> [String] = { path in
            let clean = BlacksiteFS.normalize(
                path, cwd: BlacksiteFS.home)
            return (BlacksiteFS.list(clean) ?? [])
                .map { $0.isDir
                    ? $0.name + "/" : $0.name }
        }
        context.setObject(
            listBlock,
            forKeyedSubscript: "__list" as NSString)
        let stateBlock: @convention(block)
            () -> String = {
            DevKit.houseState()
        }
        context.setObject(
            stateBlock,
            forKeyedSubscript: "__houseState"
                as NSString)
        let emconBlock: @convention(block)
            () -> String = {
            EmconCondition.current.declared
        }
        context.setObject(
            emconBlock,
            forKeyedSubscript: "__emcon" as NSString)
        let registerBlock: @convention(block)
            (String, JSValue) -> Void = {
                [weak self] name, fn in
                self?.registered[
                    name.lowercased()] = fn
            }
        context.setObject(
            registerBlock,
            forKeyedSubscript: "__register"
                as NSString)
        BlacksiteGFX.installBridge(
            into: context, owner: self)
        context.evaluateScript(Self.shim)
    }

    /// The JavaScript-side face of the bridge:
    /// varargs print, a console, the fs verbs
    /// with null-for-missing reads, the house,
    /// and the package door.
    private static let shim = """
var print = function() {
    __print(Array.prototype.map.call(
        arguments, String).join(" "));
};
var console = { log: print, error: print,
                warn: print };
function exists(path) { return __exists(path); }
function read(path) {
    return __exists(path) ? __read(path) : null;
}
function write(path, text) {
    return __write(path, String(text));
}
function ls(path) { return __list(path || "/home"); }
var house = {
    state: function() { return __houseState(); },
    emcon: function() { return __emcon(); }
};
function registerCommand(name, fn) {
    __register(String(name), fn);
}
"""

    // MARK: Running code

    /// Names of commands packages have
    /// registered with the shell.
    func commandNames() -> [String] {
        queue.sync {
            prepareLocked()
            return registered.keys.sorted()
        }
    }

    func hasCommand(_ name: String) -> Bool {
        queue.sync {
            prepareLocked()
            return registered[name.lowercased()]
                != nil
        }
    }

    /// Run a registered package command. The
    /// return string (if any) and the error
    /// come back on the main queue.
    func callCommand(_ name: String,
                     args: [String],
                     completion: @escaping
                        (String?, String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.prepareLocked()
            guard let fn = self.registered[
                name.lowercased()],
                  let context = self.commandContext
            else {
                DispatchQueue.main.async {
                    completion(nil,
                               "no such command")
                }
                return
            }
            let state = RunState()
            context.exceptionHandler = { _, v in
                state.error = v?.toString()
                    ?? "unknown error"
            }
            let result = fn.call(
                withArguments: [args])
            let text = result?.isString == true
                ? result?.toString() : nil
            let error = state.error
            DispatchQueue.main.async {
                completion(text, error)
            }
        }
    }

    /// Evaluate an expression or snippet in
    /// the command context (package helpers
    /// are in scope). Completion on main:
    /// (printed result, error).
    func eval(_ source: String,
              completion: @escaping
                (String?, String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil, "engine cold")
                }
                return
            }
            self.prepareLocked()
            guard let context = self.commandContext
            else {
                DispatchQueue.main.async {
                    completion(nil, "engine cold")
                }
                return
            }
            let state = RunState()
            context.exceptionHandler = { _, v in
                state.error = v?.toString()
                    ?? "unknown error"
            }
            let value = context.evaluateScript(
                source)
            var result: String?
            if let value = value,
               !value.isUndefined {
                result = value.toString()
            }
            let error = state.error
            DispatchQueue.main.async {
                completion(result, error)
            }
        }
    }

    /// Run a script file in a fresh context:
    /// the bridge, every installed package's
    /// code (their helpers are in scope),
    /// then the script, with argv set.
    func runFile(_ virtualPath: String,
                 args: [String],
                 completion: @escaping
                    (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.prepareLocked()
            guard let source = BlacksiteFS
                .readText(virtualPath) else {
                DispatchQueue.main.async {
                    completion(
                        "cannot read \(virtualPath)")
                }
                return
            }
            guard let context = JSContext()
            else {
                DispatchQueue.main.async {
                    completion("engine refused")
                }
                return
            }
            let state = RunState()
            self.installBridge(into: context,
                               state: state)
            for name in self.installedPackages() {
                let path = "/packages/\(name)/main.js"
                if let pkg = BlacksiteFS
                    .readText(path) {
                    _ = context.evaluateScript(pkg)
                }
            }
            context.setObject(
                args,
                forKeyedSubscript: "argv" as NSString)
            _ = context.evaluateScript(source)
            let error = state.error
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    // MARK: Packages

    func installedPackages() -> [String] {
        (BlacksiteFS.list("/packages") ?? [])
            .filter { $0.isDir }
            .map { $0.name }
            .sorted()
    }

    private func loadPackage(_ name: String,
                             into context: JSContext) {
        let path = "/packages/\(name)/main.js"
        guard let source = BlacksiteFS
            .readText(path) else { return }
        _ = context.evaluateScript(source)
        loadedPackages.append(name)
    }

    /// Install one of the bundled packages.
    /// Returns an error line or nil.
    func installBundled(_ name: String)
        -> String? {
        guard let pkg = Self.bundled[name]
        else {
            return "no bundled package "
                + "named \(name)"
        }
        let dir = "/packages/\(name)"
        BlacksiteFS.makeDir(dir)
        guard BlacksiteFS.writeText(
            dir + "/main.js", text: pkg.source)
        else {
            return "the package would not "
                + "write to disk"
        }
        reloadPackages()
        return nil
    }

    /// Install a package from a URL: the file
    /// lands as /packages/<name>/main.js and
    /// its commands register. Completion on
    /// main: error line or nil.
    func installFromURL(
        _ urlString: String,
        completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString),
              url.scheme == "https"
                || url.scheme == "http" else {
            completion("that is not a URL "
                       + "I can fetch")
            return
        }
        var name = url.deletingPathExtension()
            .lastPathComponent.lowercased()
        if name.isEmpty { name = "package" }
        let task = URLSession.shared.dataTask(
            with: url) { data, _, problem in
            let done: (String?) -> Void = {
                error in
                DispatchQueue.main.async {
                    completion(error)
                }
            }
            if let problem = problem {
                done("fetch failed: "
                     + problem.localizedDescription)
                return
            }
            guard let data = data,
                  let source = String(
                    data: data, encoding: .utf8)
            else {
                done("what came back was "
                     + "not text")
                return
            }
            let dir = "/packages/\(name)"
            BlacksiteFS.makeDir(dir)
            guard BlacksiteFS.writeText(
                dir + "/main.js", text: source)
            else {
                done("the package would not "
                     + "write to disk")
                return
            }
            BlacksiteJS.shared.reloadPackages()
            done(nil)
        }
        task.resume()
    }

    func removePackage(_ name: String) -> Bool {
        let gone = BlacksiteFS.remove(
            "/packages/\(name)")
        if gone { reloadPackages() }
        return gone
    }

    // MARK: The bundled shelf

    static let bundled: [String:
        (blurb: String, source: String)] = [
        "codec": (
            blurb: "b64e · b64d · hexe · hexd · rot13",
            source: codecSource),
        "textkit": (
            blurb: "upper · lower · reverse · count · slug",
            source: textkitSource),
        "fortune": (
            blurb: "fortune — the house oracle",
            source: fortuneSource),
        "dice": (
            blurb: "roll NdM · flip · pick",
            source: diceSource),
    ]

    private static let codecSource = """
// codec — encodings, in pure JS.
var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    + "abcdefghijklmnopqrstuvwxyz0123456789+/";
function b64encode(text) {
    var out = "", i = 0;
    while (i < text.length) {
        var a = text.charCodeAt(i++);
        var b = i < text.length
            ? text.charCodeAt(i++) : NaN;
        var c = i < text.length
            ? text.charCodeAt(i++) : NaN;
        out += B64.charAt(a >> 2);
        out += B64.charAt(((a & 3) << 4)
            | (isNaN(b) ? 0 : b >> 4));
        out += isNaN(b) ? "="
            : B64.charAt(((b & 15) << 2)
                | (isNaN(c) ? 0 : c >> 6));
        out += isNaN(c) ? "=" : B64.charAt(c & 63);
    }
    return out;
}
function b64decode(text) {
    var clean = text.replace(/[^A-Za-z0-9+/=]/g, "");
    var out = "", i = 0;
    while (i < clean.length) {
        var c1 = clean.charAt(i++);
        var c2 = clean.charAt(i++);
        var c3 = clean.charAt(i++);
        var c4 = clean.charAt(i++);
        var e1 = B64.indexOf(c1);
        var e2 = B64.indexOf(c2);
        var e3 = B64.indexOf(c3);
        var e4 = B64.indexOf(c4);
        out += String.fromCharCode(
            (e1 << 2) | (e2 >> 4));
        if (c3 !== "=" && e3 >= 0)
            out += String.fromCharCode(
                ((e2 & 15) << 4) | (e3 >> 2));
        if (c4 !== "=" && e4 >= 0)
            out += String.fromCharCode(
                ((e3 & 3) << 6) | e4);
    }
    return out;
}
registerCommand("b64e", function(args) {
    return b64encode(args.join(" "));
});
registerCommand("b64d", function(args) {
    return b64decode(args.join(" "));
});
registerCommand("hexe", function(args) {
    var text = args.join(" "), out = "";
    for (var i = 0; i < text.length; i++) {
        var h = text.charCodeAt(i).toString(16);
        out += (h.length < 2 ? "0" : "") + h;
    }
    return out;
});
registerCommand("hexd", function(args) {
    var hex = args.join("").replace(/[^0-9a-fA-F]/g, "");
    var out = "";
    for (var i = 0; i + 1 < hex.length; i += 2)
        out += String.fromCharCode(
            parseInt(hex.substr(i, 2), 16));
    return out;
});
registerCommand("rot13", function(args) {
    return args.join(" ").replace(/[a-zA-Z]/g,
        function(ch) {
            var base = ch <= "Z" ? 65 : 97;
            return String.fromCharCode(
                (ch.charCodeAt(0) - base + 13) % 26
                + base);
        });
});
"""

    private static let textkitSource = """
// textkit — small sharp text tools.
registerCommand("upper", function(args) {
    return args.join(" ").toUpperCase();
});
registerCommand("lower", function(args) {
    return args.join(" ").toLowerCase();
});
registerCommand("reverse", function(args) {
    return args.join(" ").split("")
        .reverse().join("");
});
registerCommand("count", function(args) {
    var text = args.join(" ");
    var words = text.length === 0 ? 0
        : text.split(/\\s+/).length;
    return text.length + " chars · " + words
        + " words";
});
registerCommand("slug", function(args) {
    return args.join(" ").toLowerCase()
        .replace(/[^a-z0-9]+/g, "-")
        .replace(/^-+|-+$/g, "");
});
"""

    private static let fortuneSource = """
// fortune — the house oracle.
var FORTUNES = [
    "the wire provides.",
    "a closed door is information.",
    "she already knows.",
    "silence, then one clean signal.",
    "the nightjar flies at dusk for a reason.",
    "count the ports. then count them again.",
    "what is not transmitted cannot be read.",
    "patience is a sensor too.",
    "the house keeps what it is given.",
    "somewhere, a beacon is lying.",
    "trust the log, not the feeling.",
    "emcon charlie: speak like it matters."
];
registerCommand("fortune", function() {
    return FORTUNES[Math.floor(
        Math.random() * FORTUNES.length)];
});
"""

    private static let diceSource = """
// dice — chance, fairly thrown.
registerCommand("roll", function(args) {
    var spec = (args[0] || "1d6").toLowerCase();
    var parts = spec.split("d");
    var n = parseInt(parts[0]) || 1;
    var m = parseInt(parts[1]) || 6;
    if (n < 1 || n > 100 || m < 2)
        return "roll NdM — N dice, M faces";
    var rolls = [], total = 0;
    for (var i = 0; i < n; i++) {
        var r = 1 + Math.floor(Math.random() * m);
        rolls.push(r); total += r;
    }
    return rolls.join(" + ") + " = " + total;
});
registerCommand("flip", function() {
    return Math.random() < 0.5 ? "heads" : "tails";
});
registerCommand("pick", function(args) {
    if (args.length === 0)
        return "pick needs candidates";
    return args[Math.floor(
        Math.random() * args.length)];
});
"""
}
