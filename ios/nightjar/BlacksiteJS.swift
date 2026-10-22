import Darwin
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

    /// Timers the guests have asked the
    /// host to keep: the kernel's clock,
    /// lent out. A timer belongs to the
    /// context that set it and carries
    /// the generation of the run that
    /// was live when it was set, so a
    /// run drains (and, if it must,
    /// cancels) only its own.
    private final class TimerBox {
        let id: Int
        let context: JSContext
        let fn: JSValue
        let delay: Double
        let repeats: Bool
        let gen: Int
        var work: DispatchWorkItem?
        init(id: Int, context: JSContext,
             fn: JSValue, delay: Double,
             repeats: Bool, gen: Int) {
            self.id = id
            self.context = context
            self.fn = fn
            self.delay = delay
            self.repeats = repeats
            self.gen = gen
        }
    }

    private var timerBoxes: [Int: TimerBox] =
        [:]
    private var timerSeq = 0
    private var runGeneration = 0
    private var drainForced =
        Set<ObjectIdentifier>()
    private var commandGeneration = 0

    /// A fetch in flight for a context:
    /// the kernel's drains wait on these
    /// the same way they wait on timers.
    private final class FetchBox {
        let context: JSContext
        let gen: Int
        let callback: JSValue
        var task: URLSessionDataTask?
        /// A large binary body is HELD
        /// here, not shipped through the
        /// callback as one base64 JSON
        /// string: the script pulls it
        /// in slices (__fetchSlice) and
        /// releases it (__fetchRelease).
        /// `delivered` marks that the
        /// completion already fired, so
        /// drains stop waiting on it.
        var body: Data?
        var delivered = false
        init(context: JSContext, gen: Int,
             callback: JSValue) {
            self.context = context
            self.gen = gen
            self.callback = callback
        }
    }

    private var fetchBoxes:
        [Int: FetchBox] = [:]
    private var fetchSeq = 0

    /// A staged upload (fix146): the
    /// request is opened with
    /// __fetchBegin, the body arrives
    /// through __fetchAppend in
    /// base64 slices, and __fetchSend
    /// fires it — a giant body never
    /// exists as one JS string, the
    /// mirror of fix145's sliced
    /// replies.
    private final class SendBox {
        let context: JSContext
        let gen: Int
        let url: String
        let parsed: [String: Any]
        let callback: JSValue
        var body = Data()
        init(context: JSContext,
             gen: Int, url: String,
             parsed: [String: Any],
             callback: JSValue) {
            self.context = context
            self.gen = gen
            self.url = url
            self.parsed = parsed
            self.callback = callback
        }
    }
    private var sendBoxes:
        [Int: SendBox] = [:]
    private var execInFlight = 0

    /// The shell installs this so a script
    /// can run a console line and read
    /// what it printed. The grok client's
    /// run_command tool rides it.
    static var execProvider:
        ((String,
          @escaping (String) -> Void)
            -> Void)?
    /// The shell installs this so a
    /// script can read the console's
    /// environment (the shim's
    /// process.env rides it).
    static var envProvider:
        (() -> [String: String])?
    private var registered: [String: JSValue] = [:]
    private var loadedPackages: [String] = []
    private var bridgeReady = false

    private final class RunState {
        var error: String?
        // Confined to the JavaScript queue, including cancellation cleanup.
        var finished = false
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
        let read64Block: @convention(block)
            (String) -> String? = { path in
            BlacksiteFS.readData(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home))?
                .base64EncodedString()
        }
        context.setObject(
            read64Block,
            forKeyedSubscript: "__read64"
                as NSString)
        let write64Block: @convention(block)
            (String, String) -> Bool = {
                path, encoded in
            guard let data = Data(
                base64Encoded: encoded)
            else { return false }
            return BlacksiteFS.writeData(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home),
                data: data)
        }
        context.setObject(
            write64Block,
            forKeyedSubscript: "__write64"
                as NSString)
        let statBlock: @convention(block)
            (String) -> String = { path in
            let clean = BlacksiteFS.normalize(
                path, cwd: BlacksiteFS.home)
            var out: [String: Any] = [
                "exists":
                    BlacksiteFS.exists(clean),
                "dir":
                    BlacksiteFS.isDirectory(
                        clean),
                "size": 0,
                "mtime": 0]
            if BlacksiteFS.exists(clean) {
                let attrs = try? FileManager
                    .default
                    .attributesOfItem(
                        atPath: BlacksiteFS
                            .url(forVirtual:
                                clean).path)
                if let size = attrs?[.size]
                    as? NSNumber {
                    out["size"] =
                        size.intValue
                }
                if let mtime = attrs?[
                    .modificationDate]
                    as? Date {
                    out["mtime"] =
                        mtime.timeIntervalSince1970
                }
            }
            let data = try? JSONSerialization
                .data(withJSONObject: out)
            return data.flatMap {
                String(data: $0,
                       encoding: .utf8)
            } ?? "{}"
        }
        context.setObject(
            statBlock,
            forKeyedSubscript: "__stat"
                as NSString)
        let mkdirBlock: @convention(block)
            (String) -> Bool = { path in
            BlacksiteFS.makeDir(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home))
        }
        context.setObject(
            mkdirBlock,
            forKeyedSubscript: "__mkdir"
                as NSString)
        let rmBlock: @convention(block)
            (String) -> Bool = { path in
            BlacksiteFS.remove(
                BlacksiteFS.normalize(
                    path, cwd: BlacksiteFS.home))
        }
        context.setObject(
            rmBlock,
            forKeyedSubscript: "__rm"
                as NSString)
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
        let setTimerBlock: @convention(block)
            (JSValue, Double, Bool) -> Int = {
                [weak self] fn, ms, repeats in
                self?.scheduleTimer(
                    fn, ms: ms,
                    repeats: repeats) ?? 0
            }
        context.setObject(
            setTimerBlock,
            forKeyedSubscript: "__setTimer"
                as NSString)
        let clearTimerBlock:
            @convention(block)
            (Int) -> Void = {
                [weak self] id in
                self?.cancelTimer(id)
            }
        context.setObject(
            clearTimerBlock,
            forKeyedSubscript: "__clearTimer"
                as NSString)
        let fetchBlock: @convention(block)
            (String, String, JSValue) -> Int = {
                [weak self] url, options,
                callback in
                self?.startFetch(
                    url: url,
                    optionsJSON: options,
                    callback: callback) ?? 0
            }
        context.setObject(
            fetchBlock,
            forKeyedSubscript: "__fetch"
                as NSString)
        let fetchSliceBlock:
            @convention(block)
            (Int, Int, Int) -> String? = {
                [weak self] id, offset,
                count in
                self?.fetchSlice(
                    id, offset: offset,
                    count: count)
            }
        context.setObject(
            fetchSliceBlock,
            forKeyedSubscript: "__fetchSlice"
                as NSString)
        let fetchReleaseBlock:
            @convention(block)
            (Int) -> Void = {
                [weak self] id in
                self?.fetchRelease(id)
            }
        context.setObject(
            fetchReleaseBlock,
            forKeyedSubscript:
                "__fetchRelease" as NSString)
        let envBlock: @convention(block)
            () -> String = {
                let env = BlacksiteJS
                    .envProvider?() ?? [:]
                let data = (try?
                    JSONSerialization.data(
                        withJSONObject: env))
                    ?? Data()
                return String(
                    data: data,
                    encoding: .utf8) ?? "{}"
            }
        context.setObject(
            envBlock,
            forKeyedSubscript: "__env"
                as NSString)
        let fetchBeginBlock:
            @convention(block)
            (String, String, JSValue)
            -> Int = {
                [weak self] url, options,
                callback in
                self?.fetchBegin(
                    url: url,
                    optionsJSON: options,
                    callback: callback)
                    ?? 0
            }
        context.setObject(
            fetchBeginBlock,
            forKeyedSubscript: "__fetchBegin"
                as NSString)
        let fetchAppendBlock:
            @convention(block)
            (Int, String) -> Bool = {
                [weak self] id, chunk in
                self?.fetchAppend(
                    id, chunk) ?? false
            }
        context.setObject(
            fetchAppendBlock,
            forKeyedSubscript:
                "__fetchAppend" as NSString)
        let fetchSendBlock:
            @convention(block)
            (Int) -> Bool = {
                [weak self] id in
                self?.fetchSend(id)
                    ?? false
            }
        context.setObject(
            fetchSendBlock,
            forKeyedSubscript: "__fetchSend"
                as NSString)
        let execBlock: @convention(block)
            (String, JSValue) -> Bool = {
                [weak self] line, callback in
                self?.startExec(
                    line: line,
                    callback: callback)
                    ?? false
            }
        context.setObject(
            execBlock,
            forKeyedSubscript: "__exec"
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
var self = this;
function fsRead64(path) {
    return __read64(path);
}
function fsWrite64(path, encoded) {
    return __write64(path, String(encoded));
}
function fsStat(path) {
    try {
        return JSON.parse(__stat(path));
    } catch (e) {
        return { exists: false, dir: false,
                 size: 0, mtime: 0 };
    }
}
function fsMkdir(path) {
    return __mkdir(path);
}
function fsRm(path) { return __rm(path); }
var house = {
    state: function() { return __houseState(); },
    emcon: function() { return __emcon(); }
};
// ---------- runtime citizens ----------
// What a Node-ish program expects to
// find already in the room (fix146).
// Packages used to polyfill these one
// by one; they live here now.
if (typeof TextEncoder === "undefined") {
    self.TextEncoder = function() {};
    TextEncoder.prototype.encode =
        function(text) {
            var out = [];
            var str = String(text);
            for (var i = 0; i < str.length;
                 i++) {
                var code = str.charCodeAt(i);
                if (code < 0x80) {
                    out.push(code);
                } else if (code < 0x800) {
                    out.push(
                        0xc0 | (code >> 6),
                        0x80 | (code & 0x3f));
                } else if (code >= 0xd800
                    && code <= 0xdbff
                    && i + 1 < str.length) {
                    var next =
                        str.charCodeAt(i + 1);
                    if (next >= 0xdc00
                        && next <= 0xdfff) {
                        i++;
                        var cp = 0x10000
                            + ((code - 0xd800)
                               << 10)
                            + (next - 0xdc00);
                        out.push(
                            0xf0 | (cp >> 18),
                            0x80
                                | ((cp >> 12)
                                   & 0x3f),
                            0x80
                                | ((cp >> 6)
                                   & 0x3f),
                            0x80
                                | (cp & 0x3f));
                    } else {
                        out.push(0xef, 0xbf,
                                 0xbd);
                    }
                } else {
                    out.push(
                        0xe0 | (code >> 12),
                        0x80
                            | ((code >> 6)
                               & 0x3f),
                        0x80
                            | (code & 0x3f));
                }
            }
            return new Uint8Array(out);
        };
}
if (typeof TextDecoder === "undefined") {
    self.TextDecoder = function() {};
    TextDecoder.prototype.decode =
        function(bytes) {
            var out = [];
            var i = 0;
            while (i < bytes.length) {
                var b = bytes[i];
                if (b < 0x80) {
                    out.push(
                        String.fromCharCode(b));
                    i += 1;
                } else if (b >= 0xc0
                    && b < 0xe0) {
                    out.push(
                        String.fromCharCode(
                            ((b & 0x1f) << 6)
                            | (bytes[i + 1]
                               & 0x3f)));
                    i += 2;
                } else if (b >= 0xe0
                    && b < 0xf0) {
                    out.push(
                        String.fromCharCode(
                            ((b & 0x0f) << 12)
                            | ((bytes[i + 1]
                                & 0x3f) << 6)
                            | (bytes[i + 2]
                               & 0x3f)));
                    i += 3;
                } else {
                    var cp =
                        ((b & 0x07) << 18)
                        | ((bytes[i + 1]
                            & 0x3f) << 12)
                        | ((bytes[i + 2]
                            & 0x3f) << 6)
                        | (bytes[i + 3]
                           & 0x3f);
                    cp -= 0x10000;
                    out.push(
                        String.fromCharCode(
                            0xd800
                                + (cp >> 10),
                            0xdc00
                                + (cp
                                   & 0x3ff)));
                    i += 4;
                }
            }
            return out.join("");
        };
}
if (typeof URL === "undefined") {
    self.URL = function(url, base) {
        var text = String(url);
        if (base
            && text.indexOf("://") < 0) {
            var b = new URL(base);
            if (text.charAt(0) === "/") {
                text = b.protocol + "//"
                    + b.host + text;
            } else {
                text = b.protocol + "//"
                    + b.host
                    + b.pathname.replace(
                        /[^\\/]*$/, "")
                    + text;
            }
        }
        var m = text.match(
            /^([a-zA-Z][a-zA-Z0-9+.-]*:)\\/\\/([^\\/:?#]*)(?::([0-9]+))?([^?#]*)(\\?[^#]*)?(#.*)?$/);
        if (!m) {
            throw new Error(
                "bad url: " + text);
        }
        this.protocol = m[1];
        this.hostname = m[2];
        this.port = m[3] || "";
        this.host = this.port
            ? this.hostname + ":" + this.port
            : this.hostname;
        this.pathname = m[4] || "/";
        this.search = m[5] || "";
        this.hash = m[6] || "";
        this.origin = this.protocol + "//"
            + this.host;
        this.href = text;
    };
    URL.prototype.toString = function() {
        return this.href;
    };
}
var process = {
    platform: "blacksite",
    argv: [],
    env: {},
    cwd: function() {
        return process.env.PWD || "/home";
    },
    exit: function(code) {
        var e = new Error("process.exit");
        e.__exit = true;
        e.exitCode = code | 0;
        throw e;
    }
};
self.process = process;
function __refreshProcess(name, args) {
    process.argv = [String(name)]
        .concat(args || []);
    try {
        process.env = JSON.parse(__env());
    } catch (e) { /* keep the last */ }
}
function registerCommand(name, fn) {
    __register(String(name), function(args) {
        __refreshProcess(name, args);
        try {
            return fn(args);
        } catch (e) {
            if (e && e.__exit) { return; }
            throw e;
        }
    });
}
function setTimeout(fn, ms) {
    var rest = Array.prototype.slice.call(
        arguments, 2);
    return __setTimer(function() {
        fn.apply(null, rest);
    }, ms || 0, false);
}
function setInterval(fn, ms) {
    var rest = Array.prototype.slice.call(
        arguments, 2);
    return __setTimer(function() {
        fn.apply(null, rest);
    }, ms || 0, true);
}
function clearTimeout(id) {
    __clearTimer(id);
}
function clearInterval(id) {
    __clearTimer(id);
}
function fetch(url, opts) {
    opts = opts || {};
    return new Promise(function(resolve,
                               reject) {
        var started = __fetch(
            String(url),
            JSON.stringify({
                method: opts.method || "GET",
                headers: opts.headers || {},
                body: (opts.body === undefined
                       || opts.body === null)
                    ? null : String(opts.body)
            }),
            function(payload) {
                var r;
                try {
                    r = JSON.parse(payload);
                } catch (e) {
                    reject(new Error(
                        "fetch: bad reply"));
                    return;
                }
                if (r.error) {
                    reject(new Error(r.error));
                    return;
                }
                resolve({
                    status: r.status,
                    headers: r.headers,
                    body: r.body,
                    text: function() {
                        return Promise.resolve(
                            r.body);
                    },
                    json: function() {
                        return Promise.resolve(
                            JSON.parse(r.body));
                    }
                });
            });
        if (!started) {
            reject(new Error(
                "fetch: unavailable"));
        }
    });
}
var __b64rev = null;
function __b64decode(text) {
    // Chunked decode into a
    // preallocated array — a body
    // can be tens of megabytes, and
    // the one-number-per-byte array
    // this replaces peaked at over
    // a gigabyte on a 42 MB pack in
    // the bench (fix145).
    if (__b64rev === null) {
        __b64rev = {};
        var chars =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            + "abcdefghijklmnopqrstuvwxyz"
            + "0123456789+/";
        for (var n = 0; n < chars.length;
             n++) {
            __b64rev[chars.charAt(n)] = n;
        }
    }
    var clean = String(text).replace(
        /[^A-Za-z0-9+/=]/g, "");
    var pad = 0;
    if (clean.length >= 1
        && clean.charAt(
            clean.length - 1) === "=") {
        pad = clean.length >= 2
            && clean.charAt(
                clean.length - 2) === "="
            ? 2 : 1;
    }
    var size = Math.max(
        0, Math.floor(clean.length / 4)
            * 3 - pad);
    var out = new Uint8Array(size);
    var at = 0;
    for (var i = 0; i < clean.length;
         i += 4) {
        var a = __b64rev[
            clean.charAt(i)] || 0;
        var b = __b64rev[
            clean.charAt(i + 1)] || 0;
        var ch = clean.charAt(i + 2);
        var d = clean.charAt(i + 3);
        var c = ch === "=" ? 0
            : (__b64rev[ch] || 0);
        var e = d === "=" ? 0
            : (__b64rev[d] || 0);
        if (at < size) {
            out[at++] = (a << 2) | (b >> 4);
        }
        if (ch !== "=" && at < size) {
            out[at++] =
                ((b & 15) << 4) | (c >> 2);
        }
        if (d !== "=" && at < size) {
            out[at++] =
                ((c & 3) << 6) | e;
        }
    }
    return out;
}
function __assembleSlices(id, total) {
    // Pull a held body down in slices
    // of 786,432 bytes (a multiple of
    // 3, so every slice's base64
    // decodes independently) straight
    // into one preallocated array.
    var out = new Uint8Array(total);
    var step = 786432;
    var offset = 0;
    try {
        while (offset < total) {
            var want = Math.min(
                step, total - offset);
            var slice = __fetchSlice(
                id, offset, want);
            if (slice === null
                || slice === undefined) {
                throw new Error(
                    "fetch: a slice went "
                    + "missing");
            }
            var bytes =
                __b64decode(slice);
            out.set(bytes, offset);
            offset += want;
        }
    } finally {
        __fetchRelease(id);
    }
    return out;
}
function __binaryReply(resolve, reject) {
    return function(payload) {
        var r;
        try {
            r = JSON.parse(payload);
        } catch (e) {
            reject(new Error(
                "fetch: bad reply"));
            return;
        }
        if (r.error) {
            reject(new Error(r.error));
            return;
        }
        var bytes;
        try {
            bytes = (r.bodyId
                    !== undefined
                    && r.bodyBytes)
                ? __assembleSlices(
                    r.bodyId,
                    r.bodyBytes)
                : __b64decode(
                    r.body64 || "");
        } catch (e) {
            reject(e);
            return;
        }
        resolve({
            status: r.status,
            headers: r.headers,
            body64: r.body64 || "",
            bytes: bytes
        });
    };
}
function fetchBinary(url, opts) {
    opts = opts || {};
    return new Promise(function(resolve,
                                reject) {
        var reply = __binaryReply(
            resolve, reject);
        var body64 = (opts.body64
                === undefined
                || opts.body64 === null)
            ? null : String(opts.body64);
        if (body64 !== null
            && body64.length > 1048576) {
            // Staged upload (fix146): a
            // big body crosses in slices
            // instead of one string. The
            // slice size is a multiple of
            // 4, so every slice decodes
            // on its own at the far end.
            var id = __fetchBegin(
                String(url),
                JSON.stringify({
                    method: opts.method
                        || "GET",
                    headers: opts.headers
                        || {},
                    binary: true
                }), reply);
            if (!id) {
                reject(new Error(
                    "fetch: bad url"));
                return;
            }
            var step = 1048576;
            for (var at = 0;
                 at < body64.length;
                 at += step) {
                var chunk = body64.substring(
                    at, Math.min(
                        at + step,
                        body64.length));
                if (!__fetchAppend(
                        id, chunk)) {
                    reject(new Error(
                        "fetch: upload "
                        + "failed"));
                    return;
                }
            }
            if (!__fetchSend(id)) {
                reject(new Error(
                    "fetch: unavailable"));
            }
            return;
        }
        var started = __fetch(
            String(url),
            JSON.stringify({
                method: opts.method || "GET",
                headers: opts.headers || {},
                bodyBase64: body64,
                binary: true
            }), reply);
        if (!started) {
            reject(new Error(
                "fetch: unavailable"));
        }
    });
}
function execCb(line, done) {
    var ok = __exec(String(line),
        function(out) { done(out); });
    if (!ok) { done("(exec unavailable)"); }
}
function exec(line) {
    return new Promise(function(resolve) {
        execCb(line, resolve);
    });
}
var __moduleCache = {};
var __dirStack = ["/home"];
function __dirnameOf(path) {
    var cut = path.lastIndexOf("/");
    return cut <= 0 ? "/" : path.substring(
        0, cut);
}
function __joinDir(dir, spec) {
    var parts = dir.split("/");
    var segs = spec.split("/");
    for (var n = 0; n < segs.length; n++) {
        var seg = segs[n];
        if (seg === "" || seg === ".") {
            continue;
        }
        if (seg === "..") {
            if (parts.length > 1) {
                parts.pop();
            }
            continue;
        }
        parts.push(seg);
    }
    var joined = parts.join("/");
    return joined === "" ? "/" : joined;
}
function require(spec) {
    var dir = __dirStack[
        __dirStack.length - 1];
    var base;
    if (spec.charAt(0) === "/") {
        base = spec;
    } else if (spec.indexOf("./") === 0
               || spec.indexOf("../") === 0
               || spec === "."
               || spec === "..") {
        base = __joinDir(dir, spec);
    } else {
        base = "/packages/" + spec;
    }
    var candidates = [base, base + ".js",
        base + "/main.js",
        base + "/index.js"];
    var path = null;
    for (var n = 0; n < candidates.length;
         n++) {
        if (__exists(candidates[n])
            && !fsStat(candidates[n]).dir) {
            path = candidates[n];
            break;
        }
    }
    if (path === null) {
        throw new Error(
            "cannot find module '"
            + spec + "'");
    }
    if (__moduleCache[path]) {
        return __moduleCache[path].exports;
    }
    var module = { exports: {} };
    __moduleCache[path] = module;
    var src = __read(path);
    var wrapped = new Function(
        "exports", "require", "module",
        "__filename", "__dirname", src);
    var home = __dirnameOf(path);
    __dirStack.push(home);
    try {
        wrapped.call(module.exports,
            module.exports, require, module,
            path, home);
    } finally {
        __dirStack.pop();
    }
    return module.exports;
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
            self.commandGeneration += 1
            let gen = self.commandGeneration
            let state = RunState()
            context.exceptionHandler = { _, v in
                state.error = v?.toString()
                    ?? "unknown error"
            }
            let result = fn.call(
                withArguments: [args])
            let text = result?.isString == true
                ? result?.toString() : nil
            self.drainCommand(
                context, gen: gen,
                deadline: Date()
                    .addingTimeInterval(960),
                state: state,
                result: text,
                completion: completion)
        }
    }

    /// A package command ends when its
    /// work does: timers it set and
    /// fetches it started drain under a
    /// sixteen-minute roof (a device
    /// sign-in may legitimately wait out
    /// a ten-minute code), whatever is
    /// left at the roof is cancelled —
    /// and a cut with work still pending
    /// SAYS SO through the completion's
    /// error instead of ending silently.
    private func drainCommand(
        _ context: JSContext, gen: Int,
        deadline: Date, state: RunState,
        result: String?,
        completion: @escaping
            (String?, String?) -> Void) {
        let key = ObjectIdentifier(context)
        let forced = drainForced.contains(
            key)
        if forced
            || (!timersPending(
                context: context, gen: gen)
                && !fetchesPending(
                    context: context,
                    gen: gen))
            || Date() >= deadline {
            let stillWorking =
                timersPending(
                    context: context,
                    gen: gen)
                || fetchesPending(
                    context: context,
                    gen: gen)
            drainForced.remove(key)
            cancelTimers(
                context: context, gen: gen)
            cancelFetches(
                context: context, gen: gen)
            let error = state.error
                ?? (stillWorking
                    ? "cut off at the house "
                        + "limit while still "
                        + "working — whatever "
                        + "it was waiting for "
                        + "will not arrive now"
                    : nil)
            DispatchQueue.main.async {
                completion(result, error)
            }
            return
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 0.1) {
                [weak self] in
                self?.queue.async {
                    [weak self] in
                    self?.drainCommand(
                        context, gen: gen,
                        deadline: deadline,
                        state: state,
                        result: result,
                        completion: completion)
                }
            }
    }

    /// Evaluate an expression or snippet in
    /// the command context (package helpers
    /// are in scope). Completion on main:
    /// (printed result, error).
    /// Put a context's group on the
    /// kernel's clock: past the limit the
    /// VM itself stops the script — a
    /// preemptive timeslice enforced by
    /// the engine, not by politeness.
    private func armTimeLimit(
        _ context: JSContext,
        _ seconds: Double) {
        guard let ref = context
            .jsGlobalContextRef else {
            return
        }
        Self.setLimitFn?(
            JSContextGetGroup(ref),
            seconds, nil, nil)
    }

    /// The execution-time-limit pair is
    /// declared only in JavaScriptCore's
    /// private header, which Swift's
    /// importer never sees, so the two
    /// symbols are taken from the loaded
    /// framework itself (RTLD_DEFAULT is
    /// the -2 handle). Same functions,
    /// same behaviour; if a future system
    /// hides them, the limit simply never
    /// arms and the kernel's other fences
    /// still stand.
    private typealias TerminateProbe =
        @convention(c) (
            JSContextRef?,
            UnsafeMutableRawPointer?) -> Bool
    private typealias SetLimitFn =
        @convention(c) (
            JSContextGroupRef, Double,
            TerminateProbe?,
            UnsafeMutableRawPointer?) -> Void
    private typealias ClearLimitFn =
        @convention(c) (
            JSContextGroupRef) -> Void

    private static let setLimitFn:
        SetLimitFn? = {
            guard let symbol = dlsym(
                UnsafeMutableRawPointer(
                    bitPattern: -2),
                "JSContextGroupSetExecution"
                    + "TimeLimit")
            else { return nil }
            return unsafeBitCast(
                symbol, to: SetLimitFn.self)
        }()

    private static let clearLimitFn:
        ClearLimitFn? = {
            guard let symbol = dlsym(
                UnsafeMutableRawPointer(
                    bitPattern: -2),
                "JSContextGroupClearExecution"
                    + "TimeLimit")
            else { return nil }
            return unsafeBitCast(
                symbol,
                to: ClearLimitFn.self)
        }()

    private func clearTimeLimit(
        _ context: JSContext) {
        guard let ref = context
            .jsGlobalContextRef else {
            return
        }
        Self.clearLimitFn?(
            JSContextGetGroup(ref))
    }

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
            runGeneration += 1
            let gen = runGeneration
            let started = Date()
            armTimeLimit(context, 30)
            let value = context.evaluateScript(
                source)
            clearTimeLimit(context)
            var result: String?
            if let value = value,
               !value.isUndefined {
                result = value.toString()
            }
            drainEval(
                context, gen: gen,
                deadline: started
                    .addingTimeInterval(30),
                result: result,
                error: { state.error },
                completion: completion)
        }
    }

    /// Run a script file in a fresh context:
    /// the bridge, every installed package's
    /// code (their helpers are in scope),
    /// then the script, with argv set.
    func runFile(_ virtualPath: String,
                 args: [String],
                 timeLimit: Double = 120,
                 killSwitch: KernelKillSwitch?
                    = nil,
                 completion: @escaping
                    (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // The kernel admits a process before this serial queue runs it.
            // A Stop while it was queued must prevent any guest code running.
            guard killSwitch?.isFired != true else {
                DispatchQueue.main.async { completion("stopped") }
                return
            }
            self.prepareLocked()
            guard killSwitch?.isFired != true else {
                DispatchQueue.main.async { completion("stopped") }
                return
            }
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
            runGeneration += 1
            let gen = runGeneration
            let started = Date()
            let state = RunState()
            self.installBridge(into: context,
                               state: state)
            // Cover package initialization as well as the script itself.
            armTimeLimit(context, timeLimit)
            killSwitch?.install { [weak self] in
                self?.armTimeLimit(context, 0.05)
                // The VM interrupt must be immediate, but the dictionaries
                // and drain state belong to the engine's serial queue.
                self?.queue.async { [weak self] in
                    guard !state.finished else { return }
                    self?.forceDrain(context)
                }
            }
            for name in self.installedPackages() {
                guard killSwitch?.isFired != true else { break }
                let path = "/packages/\(name)/main.js"
                if let pkg = BlacksiteFS
                    .readText(path) {
                    let dir = "/packages/\(name)"
                    _ = context.evaluateScript(
                        "__dirStack.push("
                        + self.jsLiteral(dir)
                        + ");")
                    _ = context.evaluateScript(pkg)
                    _ = context.evaluateScript(
                        "__dirStack.pop();")
                }
            }
            context.setObject(
                args,
                forKeyedSubscript: "argv" as NSString)
            let scriptDir = BlacksiteFS
                .parent(of: virtualPath)
            _ = context.evaluateScript(
                "__dirStack.push("
                + self.jsLiteral(scriptDir)
                + ");")
            if killSwitch?.isFired != true {
                _ = context.evaluateScript(source)
                _ = context.evaluateScript(
                    "__dirStack.pop();")
            }
            clearTimeLimit(context)
            drainRunFile(
                context, gen: gen,
                deadline: started
                    .addingTimeInterval(
                        timeLimit),
                state: state, killSwitch: killSwitch,
                completion: completion)
        }
    }

    // MARK: Timers — the kernel's clock,
    // lent to guests
    //
    // setTimeout/setInterval ask the
    // host to call back later; the host
    // grants it under the run's own
    // fences: a run is not finished
    // while its timers are pending —
    // they drain, the deadline arrives,
    // or the kernel speaks, and what is
    // left is cancelled.

    private func scheduleTimer(
        _ fn: JSValue, ms: Double,
        repeats: Bool) -> Int {
        guard let context = fn.context
        else { return 0 }
        timerSeq += 1
        let box = TimerBox(
            id: timerSeq, context: context,
            fn: fn,
            delay: min(max(0, ms),
                       3_600_000) / 1000,
            repeats: repeats,
            gen: context === commandContext
                ? commandGeneration
                : runGeneration)
        timerBoxes[box.id] = box
        armTimer(box)
        return box.id
    }

    private func armTimer(_ box: TimerBox) {
        let item = DispatchWorkItem {
            [weak self] in
            self?.queue.async {
                [weak self] in
                self?.fireTimer(box.id)
            }
        }
        box.work = item
        DispatchQueue.global().asyncAfter(
            deadline: .now() + box.delay,
            execute: item)
    }

    private func fireTimer(_ id: Int) {
        guard let box = timerBoxes[id]
        else { return }
        if !box.repeats {
            timerBoxes[id] = nil
        }
        box.fn.call(withArguments: [])
        if box.repeats,
           timerBoxes[id] != nil {
            armTimer(box)
        }
    }

    private func cancelTimer(_ id: Int) {
        timerBoxes[id]?.work?.cancel()
        timerBoxes[id] = nil
    }

    private func timersPending(
        context: JSContext, gen: Int)
        -> Bool {
        timerBoxes.values.contains {
            $0.context === context
                && $0.gen == gen
        }
    }

    private func cancelTimers(
        context: JSContext, gen: Int) {
        for (id, box) in timerBoxes
            where box.context === context
                && box.gen == gen {
            box.work?.cancel()
            timerBoxes[id] = nil
        }
    }

    private func forceDrain(
        _ context: JSContext) {
        drainForced.insert(
            ObjectIdentifier(context))
        cancelFetches(context)
    }

    /// The context's generation for
    /// fetches: packages drain under the
    /// command generation, everything
    /// else under the run generation.
    private func fetchGen(
        _ context: JSContext) -> Int {
        context === commandContext
            ? commandGeneration
            : runGeneration
    }

    private func startFetch(
        url: String, optionsJSON: String,
        callback: JSValue) -> Int {
        guard let context = callback.context
        else { return 0 }
        fetchSeq += 1
        let id = fetchSeq
        let box = FetchBox(
            context: context,
            gen: fetchGen(context),
            callback: callback)
        fetchBoxes[id] = box
        let parsed =
            (try? JSONSerialization
                .jsonObject(
                    with: Data(
                        optionsJSON.utf8))
            as? [String: Any]) ?? [:]
        guard let link = URL(string: url)
        else {
            deliverFetch(id,
                         ["error": "fetch: bad url"])
            return id
        }
        let binary = parsed["binary"]
            as? Bool ?? false
        let request = buildRequest(
            link, parsed, nil)
        launchFetch(id, request,
                    binary: binary)
        return id
    }

    private func buildRequest(
        _ link: URL,
        _ parsed: [String: Any],
        _ bodyOverride: Data?)
        -> URLRequest {
        var request = URLRequest(url: link)
        request.httpMethod =
            (parsed["method"] as? String)
            ?? "GET"
        if let headers = parsed["headers"]
            as? [String: String] {
            for (name, value) in headers {
                request.setValue(
                    value,
                    forHTTPHeaderField: name)
            }
        }
        if let bodyOverride = bodyOverride {
            request.httpBody = bodyOverride
        } else if let body = parsed["body"]
            as? String {
            request.httpBody =
                Data(body.utf8)
        } else if let body64 =
            parsed["bodyBase64"]
            as? String,
           let data = Data(
            base64Encoded: body64) {
            request.httpBody = data
        }
        request.timeoutInterval = 120
        return request
    }

    private func launchFetch(
        _ id: Int, _ request: URLRequest,
        binary: Bool) {
        var hold: Data? = nil
        let task = URLSession.shared
            .dataTask(with: request) {
                [weak self] data, response,
                error in
                guard let self = self
                else { return }
                var out: [String: Any] = [:]
                if let error = error {
                    out["error"] = "fetch: "
                        + error
                        .localizedDescription
                } else {
                    let http = response
                        as? HTTPURLResponse
                    out["status"] =
                        http?.statusCode ?? 0
                    var fields:
                        [String: String] = [:]
                    for (name, value) in
                        http?.allHeaderFields
                        ?? [:] {
                        fields[String(
                            describing: name)] =
                            String(
                                describing: value)
                    }
                    out["headers"] = fields
                    if binary {
                        out["body"] = ""
                        if let data = data,
                           data.count
                            > 1_000_000 {
                            hold = data
                            out["body64"] = ""
                        } else {
                            out["body64"] = data?
                                .base64EncodedString()
                                ?? ""
                        }
                    } else {
                        out["body"] = data
                            .flatMap {
                                String(
                                    data: $0,
                                    encoding: .utf8)
                            } ?? ""
                    }
                }
                self.queue.async {
                    if let held = hold,
                       let box =
                        self.fetchBoxes[id] {
                        box.body = held
                        out["bodyId"] = id
                        out["bodyBytes"] =
                            held.count
                    }
                    self.deliverFetch(id, out)
                }
            }
        fetchBoxes[id]?.task = task
        task.resume()
    }

    private func fetchBegin(
        url: String, optionsJSON: String,
        callback: JSValue) -> Int {
        guard let context = callback.context,
              URL(string: url) != nil
        else { return 0 }
        let parsed =
            (try? JSONSerialization
                .jsonObject(
                    with: Data(
                        optionsJSON.utf8))
            as? [String: Any]) ?? [:]
        fetchSeq += 1
        let id = fetchSeq
        sendBoxes[id] = SendBox(
            context: context,
            gen: fetchGen(context),
            url: url, parsed: parsed,
            callback: callback)
        return id
    }

    private func fetchAppend(
        _ id: Int, _ chunk: String)
        -> Bool {
        guard let box = sendBoxes[id],
              let data = Data(
                base64Encoded: chunk)
        else { return false }
        box.body.append(data)
        return true
    }

    private func fetchSend(_ id: Int)
        -> Bool {
        guard let staged = sendBoxes
                .removeValue(forKey: id),
              let link = URL(
                string: staged.url)
        else { return false }
        fetchSeq += 1
        let fid = fetchSeq
        fetchBoxes[fid] = FetchBox(
            context: staged.context,
            gen: staged.gen,
            callback: staged.callback)
        let binary = staged.parsed["binary"]
            as? Bool ?? false
        let request = buildRequest(
            link, staged.parsed,
            staged.body)
        launchFetch(fid, request,
                    binary: binary)
        return true
    }

    private func deliverFetch(
        _ id: Int,
        _ payload: [String: Any]) {
        let sliced = payload["bodyId"]
            != nil
        guard let box = sliced
            ? fetchBoxes[id]
            : fetchBoxes
                .removeValue(forKey: id)
        else { return }
        if sliced {
            box.delivered = true
        }
        let json =
            (try? JSONSerialization.data(
                withJSONObject: payload))
            .flatMap {
                String(data: $0,
                       encoding: .utf8)
            } ?? "{\"error\":\"fetch: "
            + "encode\"}"
        box.callback.call(
            withArguments: [json])
    }

    private func fetchesPending(
        context: JSContext, gen: Int)
        -> Bool {
        // The pending test is spelled
        // with contains(where:) — a
        // trailing closure cannot serve
        // as an if condition (Swift
        // reads its brace as the body's,
        // and the closure's $0s fall
        // outside any closure at all).
        if fetchBoxes.values.contains(where: {
            $0.context === context
                && $0.gen == gen
                && !$0.delivered
        }) {
            return true
        }
        return sendBoxes.values.contains {
            $0.context === context
                && $0.gen == gen
        }
    }

    /// One slice of a held binary
    /// body, base64 — nil when the id
    /// is unknown or the range is off
    /// the end. Slice sizes keep every
    /// offset on a 3-byte boundary so
    /// each slice decodes on its own.
    private func fetchSlice(
        _ id: Int, offset: Int,
        count: Int) -> String? {
        guard let body = fetchBoxes[id]?
                .body,
              offset >= 0, count > 0,
              offset < body.count
        else { return nil }
        let end = min(
            offset + count, body.count)
        return body
            .subdata(in: offset..<end)
            .base64EncodedString()
    }

    private func fetchRelease(_ id: Int) {
        fetchBoxes[id] = nil
    }

    private func cancelFetches(
        context: JSContext, gen: Int) {
        for (id, box) in fetchBoxes
            where box.context === context
                && box.gen == gen {
            box.task?.cancel()
            fetchBoxes[id] = nil
        }
        for (id, box) in sendBoxes
            where box.context === context
                && box.gen == gen {
            sendBoxes[id] = nil
        }
    }

    private func cancelFetches(
        _ context: JSContext) {
        for (id, box) in fetchBoxes
            where box.context === context {
            box.task?.cancel()
            fetchBoxes[id] = nil
        }
        for (id, box) in sendBoxes
            where box.context === context {
            sendBoxes[id] = nil
        }
    }

    private func startExec(
        line: String, callback: JSValue)
        -> Bool {
        guard let provider =
            BlacksiteJS.execProvider,
            execInFlight < 3
        else { return false }
        execInFlight += 1
        provider(line) { [weak self] out in
            guard let self = self
            else { return }
            self.queue.async {
                self.execInFlight -= 1
                callback.call(
                    withArguments: [out])
            }
        }
        return true
    }

    private func drainRunFile(
        _ context: JSContext, gen: Int,
        deadline: Date,
        state: RunState,
        killSwitch: KernelKillSwitch?,
        completion: @escaping
            (String?) -> Void) {
        let key = ObjectIdentifier(context)
        let forced = drainForced.contains(
            key)
        if forced || killSwitch?.isFired == true
            || (!timersPending(
                context: context, gen: gen)
                && !fetchesPending(
                    context: context,
                    gen: gen))
            || Date() >= deadline {
            state.finished = true
            killSwitch?.removeHandler()
            drainForced.remove(key)
            cancelTimers(
                context: context, gen: gen)
            cancelFetches(
                context: context, gen: gen)
            if runGeneration == gen {
                runGeneration = 0
            }
            let text = killSwitch?.isFired == true ? "stopped" : state.error
            DispatchQueue.main.async {
                completion(text)
            }
            return
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 0.1) {
                [weak self] in
                self?.queue.async {
                    [weak self] in
                    self?.drainRunFile(
                        context, gen: gen,
                        deadline: deadline,
                        state: state, killSwitch: killSwitch,
                        completion: completion)
                }
            }
    }

    private func drainEval(
        _ context: JSContext, gen: Int,
        deadline: Date,
        result: String?,
        error: @escaping () -> String?,
        completion: @escaping
            (String?, String?) -> Void) {
        let key = ObjectIdentifier(context)
        let forced = drainForced.contains(
            key)
        if forced
            || (!timersPending(
                context: context, gen: gen)
                && !fetchesPending(
                    context: context,
                    gen: gen))
            || Date() >= deadline {
            drainForced.remove(key)
            cancelTimers(
                context: context, gen: gen)
            cancelFetches(
                context: context, gen: gen)
            if runGeneration == gen {
                runGeneration = 0
            }
            let text = error()
            DispatchQueue.main.async {
                completion(result, text)
            }
            return
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 0.1) {
                [weak self] in
                self?.queue.async {
                    [weak self] in
                    self?.drainEval(
                        context, gen: gen,
                        deadline: deadline,
                        result: result,
                        error: error,
                        completion: completion)
                }
            }
    }

    /// A path as a single-quoted JS
    /// string literal.
    private func jsLiteral(_ text: String)
        -> String {
        var out = text
        out = out.replacingOccurrences(
            of: "\u{5c}", with: "\u{5c}\u{5c}")
        out = out.replacingOccurrences(
            of: "'", with: "\u{5c}'")
        return "'" + out + "'"
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
        let dir = "/packages/\(name)"
        _ = context.evaluateScript(
            "__dirStack.push("
            + jsLiteral(dir) + ");")
        _ = context.evaluateScript(source)
        _ = context.evaluateScript(
            "__dirStack.pop();")
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
        "grok": (
            blurb: "grok — ask xAI's grok "
                + "from here; the house's "
                + "own client (SuperGrok "
                + "sign-in via X), tools "
                + "over your files",
            source: grokSource),
        "isomorphic-git": (
            blurb: "the git engine "
                + "library "
                + "(isomorphic-git "
                + "1.30.1, MIT) — it "
                + "carries the git "
                + "package",
            source: isoGitSource),
        "git": (
            blurb: "git — clone · "
                + "status · add · "
                + "commit · log · "
                + "branch · checkout · "
                + "pull · push; real "
                + "objects, real wire",
            source: gitSource),
        "gh": (
            blurb: "gh — github from "
                + "here: auth · repos "
                + "· issues · pull "
                + "requests · api (the "
                + "house's own client "
                + "over the REST api)",
            source: ghSource),
    ]

    private static let grokSource = """
// grok — the console's own client for
// xAI's grok. It is a compatible client,
// not the Rust CLI: same sign-in, same
// API, tools over these files.
//   grok login            SuperGrok
//                         sign-in via X
//                         (device flow)
//   grok status           who is signed in
//   grok logout           forget the token
//   grok <words>          ask — with file
//                         + shell tools
// An XAI_API_KEY in the environment
// works instead of signing in.
var GROK_CLIENT_ID =
    "b1a00492-073a-47ea-816f-4c329264a828";
var GROK_ISSUER = "https://auth.x.ai";
var GROK_API = "https://api.x.ai/v1";
var GROK_AUTH_FILE = "/home/.grok-auth.json";
var GROK_SCOPES =
    "openid profile email "
    + "offline_access api:access";

function grokForm(fields) {
    var parts = [];
    for (var key in fields) {
        parts.push(encodeURIComponent(key)
            + "="
            + encodeURIComponent(fields[key]));
    }
    return parts.join("&");
}

function grokLoadAuth() {
    var text = read(GROK_AUTH_FILE);
    if (!text) { return null; }
    try { return JSON.parse(text); }
    catch (e) { return null; }
}

function grokSaveAuth(auth) {
    write(GROK_AUTH_FILE,
          JSON.stringify(auth));
}

function grokEnv(done) {
    execCb("env", function(out) {
        var env = {};
        out.split("\\n").forEach(function(line) {
            var cut = line.indexOf("=");
            if (cut > 0) {
                env[line.substring(0, cut)] =
                    line.substring(cut + 1);
            }
        });
        done(env);
    });
}

// Hand back a bearer token, refreshing
// the signed-in one when it has lapsed.
function grokBearer(done) {
    var auth = grokLoadAuth();
    if (auth && auth.access_token) {
        var now = Math.floor(
            new Date().getTime() / 1000);
        if (!auth.expires_at
            || auth.expires_at > now + 60) {
            done(auth.access_token);
            return;
        }
        if (auth.refresh_token) {
            fetch(GROK_ISSUER + "/oauth2/token", {
                method: "POST",
                headers: {
                    "Content-Type":
                        "application/x-www-form-urlencoded"
                },
                body: grokForm({
                    grant_type: "refresh_token",
                    refresh_token:
                        auth.refresh_token,
                    client_id: GROK_CLIENT_ID
                })
            }).then(function(r) {
                var parsed = null;
                try {
                    parsed = JSON.parse(r.body);
                } catch (e) { /* handled below */ }
                if (r.status === 200 && parsed
                    && parsed.access_token) {
                    auth.access_token =
                        parsed.access_token;
                    if (parsed.refresh_token) {
                        auth.refresh_token =
                            parsed.refresh_token;
                    }
                    auth.expires_at = now
                        + (parsed.expires_in
                           || 3600);
                    grokSaveAuth(auth);
                    done(auth.access_token);
                } else {
                    print("grok: the saved "
                        + "sign-in has lapsed — "
                        + "'grok login' again.");
                    done(null);
                }
            }).catch(function(e) {
                print("grok: refresh failed — "
                    + e.message);
                done(null);
            });
            return;
        }
        done(auth.access_token);
        return;
    }
    grokEnv(function(env) {
        done(env.XAI_API_KEY || null);
    });
}

function grokLogin() {
    print("grok: asking x.ai for a "
        + "device code…");
    fetch(GROK_ISSUER + "/oauth2/device/code", {
        method: "POST",
        headers: {
            "Content-Type":
                "application/x-www-form-urlencoded",
            "x-grok-client-surface": "cli"
        },
        body: grokForm({
            client_id: GROK_CLIENT_ID,
            scope: GROK_SCOPES
        })
    }).then(function(r) {
        var body = null;
        try { body = JSON.parse(r.body); }
        catch (e) { /* handled below */ }
        if (r.status !== 200 || !body
            || !body.device_code) {
            print("grok: x.ai refused the "
                + "device code (HTTP "
                + r.status + ") — "
                + (body && body.error
                   ? body.error
                   : "no details"));
            return;
        }
        print("");
        print("  sign in with your X "
            + "account (SuperGrok):");
        print("  "
            + (body.verification_uri_complete
               || body.verification_uri));
        print("  code: " + body.user_code);
        print("");
        print("grok: waiting for you to "
            + "approve it — this window "
            + "stays open a few minutes…");
        var interval = Math.max(
            2, body.interval || 5);
        var deadline = new Date().getTime()
            + (body.expires_in || 600) * 1000;
        var poll = function() {
            if (new Date().getTime()
                > deadline) {
                print("grok: the code "
                    + "expired — 'grok "
                    + "login' for a fresh "
                    + "one.");
                return;
            }
            fetch(GROK_ISSUER
                + "/oauth2/token", {
                method: "POST",
                headers: {
                    "Content-Type":
                        "application/x-www-form-urlencoded"
                },
                body: grokForm({
                    grant_type:
                        "urn:ietf:params:oauth:grant-type:device_code",
                    device_code:
                        body.device_code,
                    client_id: GROK_CLIENT_ID
                })
            }).then(function(tr) {
                var tb = null;
                try {
                    tb = JSON.parse(tr.body);
                } catch (e) { /* below */ }
                if (tr.status === 200 && tb
                    && tb.access_token) {
                    var now = Math.floor(
                        new Date().getTime()
                        / 1000);
                    grokSaveAuth({
                        access_token:
                            tb.access_token,
                        refresh_token:
                            tb.refresh_token
                            || null,
                        expires_at: now
                            + (tb.expires_in
                               || 3600)
                    });
                    print("grok: signed in. "
                        + "The token lives "
                        + "in " + GROK_AUTH_FILE
                        + " — 'grok logout' "
                        + "forgets it.");
                    return;
                }
                var err = tb && tb.error;
                if (err
                    === "authorization_pending") {
                    setTimeout(poll,
                               interval * 1000);
                } else if (err
                    === "slow_down") {
                    interval += 5;
                    setTimeout(poll,
                               interval * 1000);
                } else {
                    print("grok: sign-in ended "
                        + "— " + (err
                        || ("HTTP " + tr.status)));
                }
            }).catch(function(e) {
                print("grok: poll failed — "
                    + e.message);
            });
        };
        setTimeout(poll, interval * 1000);
    }).catch(function(e) {
        print("grok: " + e.message);
    });
}

function grokTools() {
    return [
        { type: "function",
          function: {
              name: "read_file",
              description: "Read a file from the console's files.",
              parameters: {
                  type: "object",
                  properties: {
                      path: { type: "string" }
                  },
                  required: ["path"]
              } } },
        { type: "function",
          function: {
              name: "write_file",
              description: "Write a whole file (creates or replaces).",
              parameters: {
                  type: "object",
                  properties: {
                      path: { type: "string" },
                      content: { type: "string" }
                  },
                  required: ["path", "content"]
              } } },
        { type: "function",
          function: {
              name: "edit_file",
              description: "Replace one exact passage in a file.",
              parameters: {
                  type: "object",
                  properties: {
                      path: { type: "string" },
                      old: { type: "string" },
                      new: { type: "string" }
                  },
                  required: ["path", "old", "new"]
              } } },
        { type: "function",
          function: {
              name: "list_dir",
              description: "List a directory in the console's files.",
              parameters: {
                  type: "object",
                  properties: {
                      path: { type: "string" }
                  },
                  required: ["path"]
              } } },
        { type: "function",
          function: {
              name: "run_command",
              description: "Run a line in the console's shell and read what it prints.",
              parameters: {
                  type: "object",
                  properties: {
                      command: { type: "string" }
                  },
                  required: ["command"]
              } } }
    ];
}

function grokResolve(cwd, path) {
    if (!path) { return cwd; }
    if (path.charAt(0) === "/") { return path; }
    return (cwd === "/" ? "" : cwd)
        + "/" + path;
}

function grokRunTool(cwd, call, done) {
    var name = call.function.name;
    var args = {};
    try {
        args = JSON.parse(
            call.function.arguments || "{}");
    } catch (e) { /* empty args */ }
    print("  ▸ " + name + " "
        + (args.path || args.command || ""));
    if (name === "read_file") {
        var text = read(grokResolve(
            cwd, args.path));
        done(text === null
            ? "(no such file: " + args.path + ")"
            : text.substring(0, 30000));
    } else if (name === "write_file") {
        done(write(grokResolve(cwd, args.path),
                   args.content || "")
            ? "written."
            : "(write refused)");
    } else if (name === "edit_file") {
        var path = grokResolve(cwd, args.path);
        var before = read(path);
        if (before === null) {
            done("(no such file: "
                 + args.path + ")");
            return;
        }
        var first = before.indexOf(args.old);
        if (first < 0) {
            done("(passage not found)");
            return;
        }
        if (before.indexOf(args.old,
                           first + 1) >= 0) {
            done("(passage is not unique — "
                 + "widen it)");
            return;
        }
        done(write(path, before.substring(0, first)
                   + args.new
                   + before.substring(
                       first + args.old.length))
            ? "edited."
            : "(write refused)");
    } else if (name === "list_dir") {
        var names = ls(grokResolve(
            cwd, args.path));
        done(names.length
            ? names.join("\\n")
            : "(empty)");
    } else if (name === "run_command") {
        execCb(args.command || "",
            function(out) {
                done(out.substring(0, 30000)
                    || "(no output)");
            });
    } else {
        done("(unknown tool)");
    }
}

function grokRound(bearer, model, cwd,
                     messages, rounds) {
    fetch(GROK_API + "/chat/completions", {
        method: "POST",
        headers: {
            "Content-Type":
                "application/json",
            "Authorization":
                "Bearer " + bearer
        },
        body: JSON.stringify({
            model: model,
            messages: messages,
            tools: grokTools()
        })
    }).then(function(r) {
        var body = null;
        try { body = JSON.parse(r.body); }
        catch (e) { /* below */ }
        if (r.status !== 200 || !body
            || !body.choices
            || !body.choices.length) {
            print("grok: the API answered "
                + "HTTP " + r.status + " — "
                + (body && body.error
                   ? (body.error.message
                      || JSON.stringify(
                          body.error))
                   : r.body.substring(0, 300)));
            return;
        }
        var message = body.choices[0].message;
        messages.push(message);
        var calls = message.tool_calls || [];
        if (!calls.length) {
            if (message.content) {
                print(message.content);
            }
            return;
        }
        if (rounds >= 12) {
            print("grok: twelve tool rounds "
                + "in — stopping here.");
            if (message.content) {
                print(message.content);
            }
            return;
        }
        var step = function(index) {
            if (index >= calls.length) {
                grokRound(bearer, model, cwd,
                          messages, rounds + 1);
                return;
            }
            grokRunTool(cwd, calls[index],
                function(result) {
                    messages.push({
                        role: "tool",
                        tool_call_id:
                            calls[index].id,
                        content: result
                    });
                    step(index + 1);
                });
        };
        step(0);
    }).catch(function(e) {
        print("grok: " + e.message);
    });
}

function grokAsk(prompt) {
    grokBearer(function(bearer) {
        if (!bearer) {
            print("grok: not signed in — "
                + "'grok login' (SuperGrok "
                + "via X), or set "
                + "XAI_API_KEY.");
            return;
        }
        grokEnv(function(env) {
            var model = env.GROK_MODEL
                || "grok-4.5";
            execCb("pwd", function(cwd) {
                cwd = (cwd || "/home")
                    .split("\\n")[0];
                var messages = [
                    { role: "system",
                      content: "You are grok, "
                        + "working inside the "
                        + "Blacksite console on "
                        + "the operator's phone. "
                        + "Your tools read and "
                        + "write the console's "
                        + "own files and run its "
                        + "shell. The working "
                        + "directory is "
                        + cwd + ". Be direct; "
                        + "do the work with "
                        + "tools when the answer "
                        + "needs the files, and "
                        + "show your results "
                        + "plainly." },
                    { role: "user",
                      content: prompt }
                ];
                grokRound(bearer, model, cwd,
                          messages, 0);
            });
        });
    });
}

registerCommand("grok", function(args) {
    var sub = (args[0] || "").toLowerCase();
    if (sub === "login") {
        grokLogin();
        return "grok: sign-in started.";
    }
    if (sub === "logout") {
        execCb("rm -f " + GROK_AUTH_FILE,
            function() {
                print("grok: signed out — "
                    + "the saved token is "
                    + "gone.");
            });
        return undefined;
    }
    if (sub === "status") {
        var auth = grokLoadAuth();
        if (auth && auth.access_token) {
            var when = auth.expires_at
                ? new Date(
                    auth.expires_at * 1000)
                    .toISOString()
                : "unknown";
            print("grok: signed in "
                + "(SuperGrok via X); the "
                + "token rests until "
                + when + ".");
        } else {
            print("grok: not signed in — "
                + "'grok login', or set "
                + "XAI_API_KEY.");
        }
        return undefined;
    }
    if (!args.length || sub === "help") {
        return "grok login | grok status | "
            + "grok logout | grok <words> "
            + "— the console's client for "
            + "xAI's grok";
    }
    grokAsk(args.join(" "));
    return undefined;
});

"""

    private static let isoGitSource = """
!function(t,e){"object"==typeof exports&&"object"==typeof module?module.exports=e():"function"==typeof define&&define.amd?define([],e):"object"==typeof exports?exports.git=e():t.git=e()}(self,(function(){return function(t){var e={};function r(n){if(e[n])return e[n].exports;var i=e[n]={i:n,l:!1,exports:{}};return t[n].call(i.exports,i,i.exports,r),i.l=!0,i.exports}return r.m=t,r.c=e,r.d=function(t,e,n){r.o(t,e)||Object.defineProperty(t,e,{enumerable:!0,get:n})},r.r=function(t){"undefined"!=typeof Symbol&&Symbol.toStringTag&&Object.defineProperty(t,Symbol.toStringTag,{value:"Module"}),Object.defineProperty(t,"__esModule",{value:!0})},r.t=function(t,e){if(1&e&&(t=r(t)),8&e)return t;if(4&e&&"object"==typeof t&&t&&t.__esModule)return t;var n=Object.create(null);if(r.r(n),Object.defineProperty(n,"default",{enumerable:!0,value:t}),2&e&&"string"!=typeof t)for(var i in t)r.d(n,i,function(e){return t[e]}.bind(null,i));return n},r.n=function(t){var e=t&&t.__esModule?function(){return t.default}:function(){return t};return r.d(e,"a",e),e},r.o=function(t,e){return Object.prototype.hasOwnProperty.call(t,e)},r.p="",r(r.s=167)}([function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(24);function i(t,e){if(void 0===e)throw new n.a(t)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));class n extends Error{constructor(t){super(t),this.caller=""}toJSON(){return{code:this.code,data:this.data,caller:this.caller,message:this.message,stack:this.stack}}fromJSON(t){const e=new n(t.message);return e.code=t.code,e.data=t.data,e.caller=t.caller,e.stack=t.stack,e}get isIsomorphicGitError(){return!0}}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return p}));var n=r(91),i=r.n(n),o=r(38),a=r(27),s=r(116),c=r(136);function u(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function f(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){u(o,n,i,a,s,"next",t)}function s(t){u(o,n,i,a,s,"throw",t)}a(void 0)}))}}function l(t){return Object(c.a)((t=>{try{return t.readFile().catch(t=>t)}catch(t){return t}})(t))}const d=["readFile","writeFile","mkdir","rmdir","unlink","stat","lstat","readdir","readlink","symlink"];function h(t,e){if(l(e))for(const r of d)t[`_${r}`]=e[r].bind(e);else for(const r of d)t[`_${r}`]=i()(e[r].bind(e));l(e)?e.rm?t._rm=e.rm.bind(e):e.rmdir.length>1?t._rm=e.rmdir.bind(e):t._rm=s.a.bind(null,t):e.rm?t._rm=i()(e.rm.bind(e)):e.rmdir.length>2?t._rm=i()(e.rmdir.bind(e)):t._rm=s.a.bind(null,t)}class p{constructor(t){if(void 0!==t._original_unwrapped_fs)return t;const e=Object.getOwnPropertyDescriptor(t,"promises");e&&e.enumerable?h(this,t.promises):h(this,t),this._original_unwrapped_fs=t}exists(t,e={}){var r=this;return f((function*(){try{return yield r._stat(t),!0}catch(t){if("ENOENT"===t.code||"ENOTDIR"===t.code||(t.code||"").includes("ENS"))return!1;throw console.log('Unhandled error in "FileSystem.exists()" function',t),t}}))()}read(e,r={}){var n=this;return f((function*(){try{let i=yield n._readFile(e,r);if("true"===r.autocrlf)try{i=new TextDecoder("utf8",{fatal:!0}).decode(i),i=i.replace(/\\r\\n/g,"\\n"),i=(new TextEncoder).encode(i)}catch(t){}return"string"!=typeof i&&(i=t.from(i)),i}catch(t){return null}}))()}write(t,e,r={}){var n=this;return f((function*(){try{return void(yield n._writeFile(t,e,r))}catch(i){yield n.mkdir(Object(a.a)(t)),yield n._writeFile(t,e,r)}}))()}mkdir(t,e=!1){var r=this;return f((function*(){try{return void(yield r._mkdir(t))}catch(n){if(null===n)return;if("EEXIST"===n.code)return;if(e)throw n;if("ENOENT"===n.code){const e=Object(a.a)(t);if("."===e||"/"===e||e===t)throw n;yield r.mkdir(e),yield r.mkdir(t,!0)}}}))()}rm(t){var e=this;return f((function*(){try{yield e._unlink(t)}catch(t){if("ENOENT"!==t.code)throw t}}))()}rmdir(t,e){var r=this;return f((function*(){try{e&&e.recursive?yield r._rm(t,e):yield r._rmdir(t)}catch(t){if("ENOENT"!==t.code)throw t}}))()}readdir(t){var e=this;return f((function*(){try{const r=yield e._readdir(t);return r.sort(o.a),r}catch(t){return"ENOTDIR"===t.code?null:[]}}))()}readdirDeep(t){var e=this;return f((function*(){const r=yield e._readdir(t);return(yield Promise.all(r.map(function(){var r=f((function*(r){const n=t+"/"+r;return(yield e._stat(n)).isDirectory()?e.readdirDeep(n):n}));return function(t){return r.apply(this,arguments)}}()))).reduce((t,e)=>t.concat(e),[])}))()}lstat(t){var e=this;return f((function*(){try{return yield e._lstat(t)}catch(t){if("ENOENT"===t.code||(t.code||"").includes("ENS"))return null;throw t}}))()}readlink(e,r={encoding:"buffer"}){var n=this;return f((function*(){try{const i=yield n._readlink(e,r);return t.isBuffer(i)?i:t.from(i)}catch(t){if("ENOENT"===t.code||(t.code||"").includes("ENS"))return null;throw t}}))()}writelink(t,e){var r=this;return f((function*(){return r._symlink(e.toString("utf8"),t)}))()}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";var n=r(33),i=r.n(n),o=r(32),a=r(72),s=r(8);class c{constructor(t){if(this.refs=new Map,this.parsedConfig=[],t){let e=null;this.parsedConfig=t.trim().split("\\n").map(t=>{if(/^\\s*#/.test(t))return{line:t,comment:!0};const r=t.indexOf(" ");if(t.startsWith("^")){const r=t.slice(1);return this.refs.set(e+"^{}",r),{line:t,ref:e,peeled:r}}{const n=t.slice(0,r);return e=t.slice(r+1),this.refs.set(e,n),{line:t,ref:e,oid:n}}})}return this}static from(t){return new c(t)}delete(t){this.parsedConfig=this.parsedConfig.filter(e=>e.ref!==t),this.refs.delete(t)}toString(){return this.parsedConfig.map(({line:t})=>t).join("\\n")+"\\n"}}var u=r(109);function f(t,e){const r=t.replace(/\\^\\{\\}$/,""),n=e.replace(/\\^\\{\\}$/,""),i=-(r<n)||+(r>n);return 0===i?t.endsWith("^{}")?1:-1:i}var l=r(16),d=r(11);function h(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function p(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){h(o,n,i,a,s,"next",t)}function s(t){h(o,n,i,a,s,"throw",t)}a(void 0)}))}}r.d(e,"a",(function(){return b}));const y=t=>[`${t}`,`refs/${t}`,`refs/tags/${t}`,`refs/heads/${t}`,`refs/remotes/${t}`,`refs/remotes/${t}/HEAD`],g=["config","description","index","shallow","commondir"];let m;function v(t,e){return w.apply(this,arguments)}function w(){return(w=p((function*(t,e){return void 0===m&&(m=new i.a),m.acquire(t,e)}))).apply(this,arguments)}class b{static updateRemoteRefs({fs:t,gitdir:e,remote:r,refs:n,symrefs:i,tags:s,refspecs:c,prune:f=!1,pruneTags:h=!1}){return p((function*(){for(const t of n.values())if(!t.match(/[0-9a-f]{40}/))throw new o.a(t);const y=yield d.a.get({fs:t,gitdir:e});if(!c){if(0===(c=yield y.getall(`remote.${r}.fetch`)).length)throw new a.a(r);c.unshift(`+HEAD:refs/remotes/${r}/HEAD`)}const g=u.a.from(c),m=new Map;if(h){const r=yield b.listRefs({fs:t,gitdir:e,filepath:"refs/tags"});yield b.deleteRefs({fs:t,gitdir:e,refs:r.map(t=>`refs/tags/${t}`)})}if(s)for(const r of n.keys())if(r.startsWith("refs/tags")&&!r.endsWith("^{}")&&!(yield b.exists({fs:t,gitdir:e,ref:r}))){const t=n.get(r);m.set(r,t)}const w=g.translate([...n.keys()]);for(const[t,e]of w){const r=n.get(t);m.set(e,r)}const _=g.translate([...i.keys()]);for(const[t,e]of _){const r=i.get(t),n=g.translateOne(r);n&&m.set(e,`ref: ${n}`)}const j=[];if(f){for(const r of g.localNamespaces()){const n=(yield b.listRefs({fs:t,gitdir:e,filepath:r})).map(t=>`${r}/${t}`);for(const t of n)m.has(t)||j.push(t)}j.length>0&&(yield b.deleteRefs({fs:t,gitdir:e,refs:j}))}for(const[r,n]of m)yield v(r,p((function*(){return t.write(Object(l.join)(e,r),`${n.trim()}\\n`,"utf8")})));return{pruned:j}}))()}static writeRef({fs:t,gitdir:e,ref:r,value:n}){return p((function*(){if(!n.match(/[0-9a-f]{40}/))throw new o.a(n);yield v(r,p((function*(){return t.write(Object(l.join)(e,r),`${n.trim()}\\n`,"utf8")})))}))()}static writeSymbolicRef({fs:t,gitdir:e,ref:r,value:n}){return p((function*(){yield v(r,p((function*(){return t.write(Object(l.join)(e,r),"ref: "+`${n.trim()}\\n`,"utf8")})))}))()}static deleteRef({fs:t,gitdir:e,ref:r}){return p((function*(){return b.deleteRefs({fs:t,gitdir:e,refs:[r]})}))()}static deleteRefs({fs:t,gitdir:e,refs:r}){return p((function*(){yield Promise.all(r.map(r=>t.rm(Object(l.join)(e,r))));let n=yield v("packed-refs",p((function*(){return t.read(`${e}/packed-refs`,{encoding:"utf8"})})));const i=c.from(n),o=i.refs.size;for(const t of r)i.refs.has(t)&&i.delete(t);i.refs.size<o&&(n=i.toString(),yield v("packed-refs",p((function*(){return t.write(`${e}/packed-refs`,n,{encoding:"utf8"})}))))}))()}static resolve({fs:t,gitdir:e,ref:r,depth:n}){return p((function*(){if(void 0!==n&&-1===--n)return r;if(r.startsWith("ref: "))return r=r.slice("ref: ".length),b.resolve({fs:t,gitdir:e,ref:r,depth:n});if(40===r.length&&/[0-9a-f]{40}/.test(r))return r;const i=yield b.packedRefs({fs:t,gitdir:e}),o=y(r).filter(t=>!g.includes(t));for(const r of o){const o=yield v(r,p((function*(){return(yield t.read(`${e}/${r}`,{encoding:"utf8"}))||i.get(r)})));if(o)return b.resolve({fs:t,gitdir:e,ref:o.trim(),depth:n})}throw new s.a(r)}))()}static exists({fs:t,gitdir:e,ref:r}){return p((function*(){try{return yield b.expand({fs:t,gitdir:e,ref:r}),!0}catch(t){return!1}}))()}static expand({fs:t,gitdir:e,ref:r}){return p((function*(){if(40===r.length&&/[0-9a-f]{40}/.test(r))return r;const n=yield b.packedRefs({fs:t,gitdir:e}),i=y(r);for(const r of i){if(yield v(r,p((function*(){return t.exists(`${e}/${r}`)}))))return r;if(n.has(r))return r}throw new s.a(r)}))()}static expandAgainstMap({ref:t,map:e}){return p((function*(){const r=y(t);for(const t of r)if(yield e.has(t))return t;throw new s.a(t)}))()}static resolveAgainstMap({ref:t,fullref:e=t,depth:r,map:n}){if(void 0!==r&&-1===--r)return{fullref:e,oid:t};if(t.startsWith("ref: "))return t=t.slice("ref: ".length),b.resolveAgainstMap({ref:t,fullref:e,depth:r,map:n});if(40===t.length&&/[0-9a-f]{40}/.test(t))return{fullref:e,oid:t};const i=y(t);for(const t of i){const e=n.get(t);if(e)return b.resolveAgainstMap({ref:e.trim(),fullref:t,depth:r,map:n})}throw new s.a(t)}static packedRefs({fs:t,gitdir:e}){return p((function*(){const r=yield v("packed-refs",p((function*(){return t.read(`${e}/packed-refs`,{encoding:"utf8"})})));return c.from(r).refs}))()}static listRefs({fs:t,gitdir:e,filepath:r}){return p((function*(){const n=b.packedRefs({fs:t,gitdir:e});let i=null;try{i=yield t.readdirDeep(`${e}/${r}`),i=i.map(t=>t.replace(`${e}/${r}/`,""))}catch(t){i=[]}for(let t of(yield n).keys())t.startsWith(r)&&(t=t.replace(r+"/",""),i.includes(t)||i.push(t));return i.sort(f),i}))()}static listBranches({fs:t,gitdir:e,remote:r}){return p((function*(){return r?b.listRefs({fs:t,gitdir:e,filepath:`refs/remotes/${r}`}):b.listRefs({fs:t,gitdir:e,filepath:"refs/heads"})}))()}static listTags({fs:t,gitdir:e}){return p((function*(){return(yield b.listRefs({fs:t,gitdir:e,filepath:"refs/tags"})).filter(t=>!t.endsWith("^{}"))}))()}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`An internal error caused this command to fail. Please file a bug report at https://github.com/isomorphic-git/isomorphic-git/issues with this error message: ${t}`),this.code=this.name=i.code,this.data={message:t}}}i.code="InternalError"},,,function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return d}));var n=r(4),i=r(8),o=r(25),a=r(113),s=r(110),c=r(83),u=r(19);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:e,cache:r,gitdir:f,oid:l,format:h="content"}){const p=t=>d({fs:e,cache:r,gitdir:f,oid:t});let y;if("4b825dc642cb6eb9a060e54bf8d69288fbee4904"===l&&(y={format:"wrapped",object:t.from("tree 0\\0")}),y||(y=yield Object(a.a)({fs:e,gitdir:f,oid:l})),!y){if(y=yield Object(s.a)({fs:e,cache:r,gitdir:f,oid:l,getExternalRefDelta:p}),!y)throw new i.a(l);return y}if("deflated"===h)return y;if("deflated"===y.format&&(y.object=t.from(yield Object(c.a)(y.object)),y.format="wrapped"),"wrapped"===h)return y;const g=yield Object(u.a)(y.object);if(g!==l)throw new n.a(`SHA check failed! Expected ${l}, computed ${g}`);const{object:m,type:v}=o.a.unwrap(y.object);if(y.type=v,y.object=m,y.format="content","content"===h)return y;throw new n.a(`invalid requested format "${h}"`)}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Could not find ${t}.`),this.code=this.name=i.code,this.data={what:t}}}i.code="NotFoundError"},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return a}));var n=r(82),i=r(50);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}class a{static flush(){return t.from("0000","utf8")}static delim(){return t.from("0001","utf8")}static encode(e){"string"==typeof e&&(e=t.from(e));const r=e.length+4,n=Object(i.a)(4,r);return t.concat([t.from(n,"utf8"),e])}static streamReader(t){const e=new n.a(t);return(function(){var r,n=(r=function*(){try{let t=yield e.read(4);if(null==t)return!0;if(t=parseInt(t.toString("utf8"),16),0===t)return null;if(1===t)return null;const r=yield e.read(t-4);return null==r||r}catch(e){return t.error=e,!0}},function(){var t=this,e=arguments;return new Promise((function(n,i){var a=r.apply(t,e);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))});return function(){return n.apply(this,arguments)}}())}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";(function(t){
/*!
 * The buffer module from node.js, for the browser.
 *
 * @author   Feross Aboukhadijeh <http://feross.org>
 * @license  MIT
 */
var n=r(145),i=r(146),o=r(147);function a(){return c.TYPED_ARRAY_SUPPORT?2147483647:1073741823}function s(t,e){if(a()<e)throw new RangeError("Invalid typed array length");return c.TYPED_ARRAY_SUPPORT?(t=new Uint8Array(e)).__proto__=c.prototype:(null===t&&(t=new c(e)),t.length=e),t}function c(t,e,r){if(!(c.TYPED_ARRAY_SUPPORT||this instanceof c))return new c(t,e,r);if("number"==typeof t){if("string"==typeof e)throw new Error("If encoding is specified then the first argument must be a string");return l(this,t)}return u(this,t,e,r)}function u(t,e,r,n){if("number"==typeof e)throw new TypeError('"value" argument must not be a number');return"undefined"!=typeof ArrayBuffer&&e instanceof ArrayBuffer?function(t,e,r,n){if(e.byteLength,r<0||e.byteLength<r)throw new RangeError("'offset' is out of bounds");if(e.byteLength<r+(n||0))throw new RangeError("'length' is out of bounds");e=void 0===r&&void 0===n?new Uint8Array(e):void 0===n?new Uint8Array(e,r):new Uint8Array(e,r,n);c.TYPED_ARRAY_SUPPORT?(t=e).__proto__=c.prototype:t=d(t,e);return t}(t,e,r,n):"string"==typeof e?function(t,e,r){"string"==typeof r&&""!==r||(r="utf8");if(!c.isEncoding(r))throw new TypeError('"encoding" must be a valid string encoding');var n=0|p(e,r),i=(t=s(t,n)).write(e,r);i!==n&&(t=t.slice(0,i));return t}(t,e,r):function(t,e){if(c.isBuffer(e)){var r=0|h(e.length);return 0===(t=s(t,r)).length?t:(e.copy(t,0,0,r),t)}if(e){if("undefined"!=typeof ArrayBuffer&&e.buffer instanceof ArrayBuffer||"length"in e)return"number"!=typeof e.length||(n=e.length)!=n?s(t,0):d(t,e);if("Buffer"===e.type&&o(e.data))return d(t,e.data)}var n;throw new TypeError("First argument must be a string, Buffer, ArrayBuffer, Array, or array-like object.")}(t,e)}function f(t){if("number"!=typeof t)throw new TypeError('"size" argument must be a number');if(t<0)throw new RangeError('"size" argument must not be negative')}function l(t,e){if(f(e),t=s(t,e<0?0:0|h(e)),!c.TYPED_ARRAY_SUPPORT)for(var r=0;r<e;++r)t[r]=0;return t}function d(t,e){var r=e.length<0?0:0|h(e.length);t=s(t,r);for(var n=0;n<r;n+=1)t[n]=255&e[n];return t}function h(t){if(t>=a())throw new RangeError("Attempt to allocate Buffer larger than maximum size: 0x"+a().toString(16)+" bytes");return 0|t}function p(t,e){if(c.isBuffer(t))return t.length;if("undefined"!=typeof ArrayBuffer&&"function"==typeof ArrayBuffer.isView&&(ArrayBuffer.isView(t)||t instanceof ArrayBuffer))return t.byteLength;"string"!=typeof t&&(t=""+t);var r=t.length;if(0===r)return 0;for(var n=!1;;)switch(e){case"ascii":case"latin1":case"binary":return r;case"utf8":case"utf-8":case void 0:return M(t).length;case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return 2*r;case"hex":return r>>>1;case"base64":return F(t).length;default:if(n)return M(t).length;e=(""+e).toLowerCase(),n=!0}}function y(t,e,r){var n=!1;if((void 0===e||e<0)&&(e=0),e>this.length)return"";if((void 0===r||r>this.length)&&(r=this.length),r<=0)return"";if((r>>>=0)<=(e>>>=0))return"";for(t||(t="utf8");;)switch(t){case"hex":return A(this,e,r);case"utf8":case"utf-8":return k(this,e,r);case"ascii":return E(this,e,r);case"latin1":case"binary":return S(this,e,r);case"base64":return P(this,e,r);case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return R(this,e,r);default:if(n)throw new TypeError("Unknown encoding: "+t);t=(t+"").toLowerCase(),n=!0}}function g(t,e,r){var n=t[e];t[e]=t[r],t[r]=n}function m(t,e,r,n,i){if(0===t.length)return-1;if("string"==typeof r?(n=r,r=0):r>2147483647?r=2147483647:r<-2147483648&&(r=-2147483648),r=+r,isNaN(r)&&(r=i?0:t.length-1),r<0&&(r=t.length+r),r>=t.length){if(i)return-1;r=t.length-1}else if(r<0){if(!i)return-1;r=0}if("string"==typeof e&&(e=c.from(e,n)),c.isBuffer(e))return 0===e.length?-1:v(t,e,r,n,i);if("number"==typeof e)return e&=255,c.TYPED_ARRAY_SUPPORT&&"function"==typeof Uint8Array.prototype.indexOf?i?Uint8Array.prototype.indexOf.call(t,e,r):Uint8Array.prototype.lastIndexOf.call(t,e,r):v(t,[e],r,n,i);throw new TypeError("val must be string, number or Buffer")}function v(t,e,r,n,i){var o,a=1,s=t.length,c=e.length;if(void 0!==n&&("ucs2"===(n=String(n).toLowerCase())||"ucs-2"===n||"utf16le"===n||"utf-16le"===n)){if(t.length<2||e.length<2)return-1;a=2,s/=2,c/=2,r/=2}function u(t,e){return 1===a?t[e]:t.readUInt16BE(e*a)}if(i){var f=-1;for(o=r;o<s;o++)if(u(t,o)===u(e,-1===f?0:o-f)){if(-1===f&&(f=o),o-f+1===c)return f*a}else-1!==f&&(o-=o-f),f=-1}else for(r+c>s&&(r=s-c),o=r;o>=0;o--){for(var l=!0,d=0;d<c;d++)if(u(t,o+d)!==u(e,d)){l=!1;break}if(l)return o}return-1}function w(t,e,r,n){r=Number(r)||0;var i=t.length-r;n?(n=Number(n))>i&&(n=i):n=i;var o=e.length;if(o%2!=0)throw new TypeError("Invalid hex string");n>o/2&&(n=o/2);for(var a=0;a<n;++a){var s=parseInt(e.substr(2*a,2),16);if(isNaN(s))return a;t[r+a]=s}return a}function b(t,e,r,n){return H(M(e,t.length-r),t,r,n)}function _(t,e,r,n){return H(function(t){for(var e=[],r=0;r<t.length;++r)e.push(255&t.charCodeAt(r));return e}(e),t,r,n)}function j(t,e,r,n){return _(t,e,r,n)}function O(t,e,r,n){return H(F(e),t,r,n)}function x(t,e,r,n){return H(function(t,e){for(var r,n,i,o=[],a=0;a<t.length&&!((e-=2)<0);++a)r=t.charCodeAt(a),n=r>>8,i=r%256,o.push(i),o.push(n);return o}(e,t.length-r),t,r,n)}function P(t,e,r){return 0===e&&r===t.length?n.fromByteArray(t):n.fromByteArray(t.slice(e,r))}function k(t,e,r){r=Math.min(t.length,r);for(var n=[],i=e;i<r;){var o,a,s,c,u=t[i],f=null,l=u>239?4:u>223?3:u>191?2:1;if(i+l<=r)switch(l){case 1:u<128&&(f=u);break;case 2:128==(192&(o=t[i+1]))&&(c=(31&u)<<6|63&o)>127&&(f=c);break;case 3:o=t[i+1],a=t[i+2],128==(192&o)&&128==(192&a)&&(c=(15&u)<<12|(63&o)<<6|63&a)>2047&&(c<55296||c>57343)&&(f=c);break;case 4:o=t[i+1],a=t[i+2],s=t[i+3],128==(192&o)&&128==(192&a)&&128==(192&s)&&(c=(15&u)<<18|(63&o)<<12|(63&a)<<6|63&s)>65535&&c<1114112&&(f=c)}null===f?(f=65533,l=1):f>65535&&(f-=65536,n.push(f>>>10&1023|55296),f=56320|1023&f),n.push(f),i+=l}return function(t){var e=t.length;if(e<=4096)return String.fromCharCode.apply(String,t);var r="",n=0;for(;n<e;)r+=String.fromCharCode.apply(String,t.slice(n,n+=4096));return r}(n)}e.Buffer=c,e.SlowBuffer=function(t){+t!=t&&(t=0);return c.alloc(+t)},e.INSPECT_MAX_BYTES=50,c.TYPED_ARRAY_SUPPORT=void 0!==t.TYPED_ARRAY_SUPPORT?t.TYPED_ARRAY_SUPPORT:function(){try{var t=new Uint8Array(1);return t.__proto__={__proto__:Uint8Array.prototype,foo:function(){return 42}},42===t.foo()&&"function"==typeof t.subarray&&0===t.subarray(1,1).byteLength}catch(t){return!1}}(),e.kMaxLength=a(),c.poolSize=8192,c._augment=function(t){return t.__proto__=c.prototype,t},c.from=function(t,e,r){return u(null,t,e,r)},c.TYPED_ARRAY_SUPPORT&&(c.prototype.__proto__=Uint8Array.prototype,c.__proto__=Uint8Array,"undefined"!=typeof Symbol&&Symbol.species&&c[Symbol.species]===c&&Object.defineProperty(c,Symbol.species,{value:null,configurable:!0})),c.alloc=function(t,e,r){return function(t,e,r,n){return f(e),e<=0?s(t,e):void 0!==r?"string"==typeof n?s(t,e).fill(r,n):s(t,e).fill(r):s(t,e)}(null,t,e,r)},c.allocUnsafe=function(t){return l(null,t)},c.allocUnsafeSlow=function(t){return l(null,t)},c.isBuffer=function(t){return!(null==t||!t._isBuffer)},c.compare=function(t,e){if(!c.isBuffer(t)||!c.isBuffer(e))throw new TypeError("Arguments must be Buffers");if(t===e)return 0;for(var r=t.length,n=e.length,i=0,o=Math.min(r,n);i<o;++i)if(t[i]!==e[i]){r=t[i],n=e[i];break}return r<n?-1:n<r?1:0},c.isEncoding=function(t){switch(String(t).toLowerCase()){case"hex":case"utf8":case"utf-8":case"ascii":case"latin1":case"binary":case"base64":case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return!0;default:return!1}},c.concat=function(t,e){if(!o(t))throw new TypeError('"list" argument must be an Array of Buffers');if(0===t.length)return c.alloc(0);var r;if(void 0===e)for(e=0,r=0;r<t.length;++r)e+=t[r].length;var n=c.allocUnsafe(e),i=0;for(r=0;r<t.length;++r){var a=t[r];if(!c.isBuffer(a))throw new TypeError('"list" argument must be an Array of Buffers');a.copy(n,i),i+=a.length}return n},c.byteLength=p,c.prototype._isBuffer=!0,c.prototype.swap16=function(){var t=this.length;if(t%2!=0)throw new RangeError("Buffer size must be a multiple of 16-bits");for(var e=0;e<t;e+=2)g(this,e,e+1);return this},c.prototype.swap32=function(){var t=this.length;if(t%4!=0)throw new RangeError("Buffer size must be a multiple of 32-bits");for(var e=0;e<t;e+=4)g(this,e,e+3),g(this,e+1,e+2);return this},c.prototype.swap64=function(){var t=this.length;if(t%8!=0)throw new RangeError("Buffer size must be a multiple of 64-bits");for(var e=0;e<t;e+=8)g(this,e,e+7),g(this,e+1,e+6),g(this,e+2,e+5),g(this,e+3,e+4);return this},c.prototype.toString=function(){var t=0|this.length;return 0===t?"":0===arguments.length?k(this,0,t):y.apply(this,arguments)},c.prototype.equals=function(t){if(!c.isBuffer(t))throw new TypeError("Argument must be a Buffer");return this===t||0===c.compare(this,t)},c.prototype.inspect=function(){var t="",r=e.INSPECT_MAX_BYTES;return this.length>0&&(t=this.toString("hex",0,r).match(/.{2}/g).join(" "),this.length>r&&(t+=" ... ")),"<Buffer "+t+">"},c.prototype.compare=function(t,e,r,n,i){if(!c.isBuffer(t))throw new TypeError("Argument must be a Buffer");if(void 0===e&&(e=0),void 0===r&&(r=t?t.length:0),void 0===n&&(n=0),void 0===i&&(i=this.length),e<0||r>t.length||n<0||i>this.length)throw new RangeError("out of range index");if(n>=i&&e>=r)return 0;if(n>=i)return-1;if(e>=r)return 1;if(this===t)return 0;for(var o=(i>>>=0)-(n>>>=0),a=(r>>>=0)-(e>>>=0),s=Math.min(o,a),u=this.slice(n,i),f=t.slice(e,r),l=0;l<s;++l)if(u[l]!==f[l]){o=u[l],a=f[l];break}return o<a?-1:a<o?1:0},c.prototype.includes=function(t,e,r){return-1!==this.indexOf(t,e,r)},c.prototype.indexOf=function(t,e,r){return m(this,t,e,r,!0)},c.prototype.lastIndexOf=function(t,e,r){return m(this,t,e,r,!1)},c.prototype.write=function(t,e,r,n){if(void 0===e)n="utf8",r=this.length,e=0;else if(void 0===r&&"string"==typeof e)n=e,r=this.length,e=0;else{if(!isFinite(e))throw new Error("Buffer.write(string, encoding, offset[, length]) is no longer supported");e|=0,isFinite(r)?(r|=0,void 0===n&&(n="utf8")):(n=r,r=void 0)}var i=this.length-e;if((void 0===r||r>i)&&(r=i),t.length>0&&(r<0||e<0)||e>this.length)throw new RangeError("Attempt to write outside buffer bounds");n||(n="utf8");for(var o=!1;;)switch(n){case"hex":return w(this,t,e,r);case"utf8":case"utf-8":return b(this,t,e,r);case"ascii":return _(this,t,e,r);case"latin1":case"binary":return j(this,t,e,r);case"base64":return O(this,t,e,r);case"ucs2":case"ucs-2":case"utf16le":case"utf-16le":return x(this,t,e,r);default:if(o)throw new TypeError("Unknown encoding: "+n);n=(""+n).toLowerCase(),o=!0}},c.prototype.toJSON=function(){return{type:"Buffer",data:Array.prototype.slice.call(this._arr||this,0)}};function E(t,e,r){var n="";r=Math.min(t.length,r);for(var i=e;i<r;++i)n+=String.fromCharCode(127&t[i]);return n}function S(t,e,r){var n="";r=Math.min(t.length,r);for(var i=e;i<r;++i)n+=String.fromCharCode(t[i]);return n}function A(t,e,r){var n=t.length;(!e||e<0)&&(e=0),(!r||r<0||r>n)&&(r=n);for(var i="",o=e;o<r;++o)i+=N(t[o]);return i}function R(t,e,r){for(var n=t.slice(e,r),i="",o=0;o<n.length;o+=2)i+=String.fromCharCode(n[o]+256*n[o+1]);return i}function $(t,e,r){if(t%1!=0||t<0)throw new RangeError("offset is not uint");if(t+e>r)throw new RangeError("Trying to access beyond buffer length")}function B(t,e,r,n,i,o){if(!c.isBuffer(t))throw new TypeError('"buffer" argument must be a Buffer instance');if(e>i||e<o)throw new RangeError('"value" argument is out of bounds');if(r+n>t.length)throw new RangeError("Index out of range")}function T(t,e,r,n){e<0&&(e=65535+e+1);for(var i=0,o=Math.min(t.length-r,2);i<o;++i)t[r+i]=(e&255<<8*(n?i:1-i))>>>8*(n?i:1-i)}function I(t,e,r,n){e<0&&(e=4294967295+e+1);for(var i=0,o=Math.min(t.length-r,4);i<o;++i)t[r+i]=e>>>8*(n?i:3-i)&255}function C(t,e,r,n,i,o){if(r+n>t.length)throw new RangeError("Index out of range");if(r<0)throw new RangeError("Index out of range")}function U(t,e,r,n,o){return o||C(t,0,r,4),i.write(t,e,r,n,23,4),r+4}function D(t,e,r,n,o){return o||C(t,0,r,8),i.write(t,e,r,n,52,8),r+8}c.prototype.slice=function(t,e){var r,n=this.length;if((t=~~t)<0?(t+=n)<0&&(t=0):t>n&&(t=n),(e=void 0===e?n:~~e)<0?(e+=n)<0&&(e=0):e>n&&(e=n),e<t&&(e=t),c.TYPED_ARRAY_SUPPORT)(r=this.subarray(t,e)).__proto__=c.prototype;else{var i=e-t;r=new c(i,void 0);for(var o=0;o<i;++o)r[o]=this[o+t]}return r},c.prototype.readUIntLE=function(t,e,r){t|=0,e|=0,r||$(t,e,this.length);for(var n=this[t],i=1,o=0;++o<e&&(i*=256);)n+=this[t+o]*i;return n},c.prototype.readUIntBE=function(t,e,r){t|=0,e|=0,r||$(t,e,this.length);for(var n=this[t+--e],i=1;e>0&&(i*=256);)n+=this[t+--e]*i;return n},c.prototype.readUInt8=function(t,e){return e||$(t,1,this.length),this[t]},c.prototype.readUInt16LE=function(t,e){return e||$(t,2,this.length),this[t]|this[t+1]<<8},c.prototype.readUInt16BE=function(t,e){return e||$(t,2,this.length),this[t]<<8|this[t+1]},c.prototype.readUInt32LE=function(t,e){return e||$(t,4,this.length),(this[t]|this[t+1]<<8|this[t+2]<<16)+16777216*this[t+3]},c.prototype.readUInt32BE=function(t,e){return e||$(t,4,this.length),16777216*this[t]+(this[t+1]<<16|this[t+2]<<8|this[t+3])},c.prototype.readIntLE=function(t,e,r){t|=0,e|=0,r||$(t,e,this.length);for(var n=this[t],i=1,o=0;++o<e&&(i*=256);)n+=this[t+o]*i;return n>=(i*=128)&&(n-=Math.pow(2,8*e)),n},c.prototype.readIntBE=function(t,e,r){t|=0,e|=0,r||$(t,e,this.length);for(var n=e,i=1,o=this[t+--n];n>0&&(i*=256);)o+=this[t+--n]*i;return o>=(i*=128)&&(o-=Math.pow(2,8*e)),o},c.prototype.readInt8=function(t,e){return e||$(t,1,this.length),128&this[t]?-1*(255-this[t]+1):this[t]},c.prototype.readInt16LE=function(t,e){e||$(t,2,this.length);var r=this[t]|this[t+1]<<8;return 32768&r?4294901760|r:r},c.prototype.readInt16BE=function(t,e){e||$(t,2,this.length);var r=this[t+1]|this[t]<<8;return 32768&r?4294901760|r:r},c.prototype.readInt32LE=function(t,e){return e||$(t,4,this.length),this[t]|this[t+1]<<8|this[t+2]<<16|this[t+3]<<24},c.prototype.readInt32BE=function(t,e){return e||$(t,4,this.length),this[t]<<24|this[t+1]<<16|this[t+2]<<8|this[t+3]},c.prototype.readFloatLE=function(t,e){return e||$(t,4,this.length),i.read(this,t,!0,23,4)},c.prototype.readFloatBE=function(t,e){return e||$(t,4,this.length),i.read(this,t,!1,23,4)},c.prototype.readDoubleLE=function(t,e){return e||$(t,8,this.length),i.read(this,t,!0,52,8)},c.prototype.readDoubleBE=function(t,e){return e||$(t,8,this.length),i.read(this,t,!1,52,8)},c.prototype.writeUIntLE=function(t,e,r,n){(t=+t,e|=0,r|=0,n)||B(this,t,e,r,Math.pow(2,8*r)-1,0);var i=1,o=0;for(this[e]=255&t;++o<r&&(i*=256);)this[e+o]=t/i&255;return e+r},c.prototype.writeUIntBE=function(t,e,r,n){(t=+t,e|=0,r|=0,n)||B(this,t,e,r,Math.pow(2,8*r)-1,0);var i=r-1,o=1;for(this[e+i]=255&t;--i>=0&&(o*=256);)this[e+i]=t/o&255;return e+r},c.prototype.writeUInt8=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,1,255,0),c.TYPED_ARRAY_SUPPORT||(t=Math.floor(t)),this[e]=255&t,e+1},c.prototype.writeUInt16LE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,2,65535,0),c.TYPED_ARRAY_SUPPORT?(this[e]=255&t,this[e+1]=t>>>8):T(this,t,e,!0),e+2},c.prototype.writeUInt16BE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,2,65535,0),c.TYPED_ARRAY_SUPPORT?(this[e]=t>>>8,this[e+1]=255&t):T(this,t,e,!1),e+2},c.prototype.writeUInt32LE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,4,4294967295,0),c.TYPED_ARRAY_SUPPORT?(this[e+3]=t>>>24,this[e+2]=t>>>16,this[e+1]=t>>>8,this[e]=255&t):I(this,t,e,!0),e+4},c.prototype.writeUInt32BE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,4,4294967295,0),c.TYPED_ARRAY_SUPPORT?(this[e]=t>>>24,this[e+1]=t>>>16,this[e+2]=t>>>8,this[e+3]=255&t):I(this,t,e,!1),e+4},c.prototype.writeIntLE=function(t,e,r,n){if(t=+t,e|=0,!n){var i=Math.pow(2,8*r-1);B(this,t,e,r,i-1,-i)}var o=0,a=1,s=0;for(this[e]=255&t;++o<r&&(a*=256);)t<0&&0===s&&0!==this[e+o-1]&&(s=1),this[e+o]=(t/a>>0)-s&255;return e+r},c.prototype.writeIntBE=function(t,e,r,n){if(t=+t,e|=0,!n){var i=Math.pow(2,8*r-1);B(this,t,e,r,i-1,-i)}var o=r-1,a=1,s=0;for(this[e+o]=255&t;--o>=0&&(a*=256);)t<0&&0===s&&0!==this[e+o+1]&&(s=1),this[e+o]=(t/a>>0)-s&255;return e+r},c.prototype.writeInt8=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,1,127,-128),c.TYPED_ARRAY_SUPPORT||(t=Math.floor(t)),t<0&&(t=255+t+1),this[e]=255&t,e+1},c.prototype.writeInt16LE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,2,32767,-32768),c.TYPED_ARRAY_SUPPORT?(this[e]=255&t,this[e+1]=t>>>8):T(this,t,e,!0),e+2},c.prototype.writeInt16BE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,2,32767,-32768),c.TYPED_ARRAY_SUPPORT?(this[e]=t>>>8,this[e+1]=255&t):T(this,t,e,!1),e+2},c.prototype.writeInt32LE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,4,2147483647,-2147483648),c.TYPED_ARRAY_SUPPORT?(this[e]=255&t,this[e+1]=t>>>8,this[e+2]=t>>>16,this[e+3]=t>>>24):I(this,t,e,!0),e+4},c.prototype.writeInt32BE=function(t,e,r){return t=+t,e|=0,r||B(this,t,e,4,2147483647,-2147483648),t<0&&(t=4294967295+t+1),c.TYPED_ARRAY_SUPPORT?(this[e]=t>>>24,this[e+1]=t>>>16,this[e+2]=t>>>8,this[e+3]=255&t):I(this,t,e,!1),e+4},c.prototype.writeFloatLE=function(t,e,r){return U(this,t,e,!0,r)},c.prototype.writeFloatBE=function(t,e,r){return U(this,t,e,!1,r)},c.prototype.writeDoubleLE=function(t,e,r){return D(this,t,e,!0,r)},c.prototype.writeDoubleBE=function(t,e,r){return D(this,t,e,!1,r)},c.prototype.copy=function(t,e,r,n){if(r||(r=0),n||0===n||(n=this.length),e>=t.length&&(e=t.length),e||(e=0),n>0&&n<r&&(n=r),n===r)return 0;if(0===t.length||0===this.length)return 0;if(e<0)throw new RangeError("targetStart out of bounds");if(r<0||r>=this.length)throw new RangeError("sourceStart out of bounds");if(n<0)throw new RangeError("sourceEnd out of bounds");n>this.length&&(n=this.length),t.length-e<n-r&&(n=t.length-e+r);var i,o=n-r;if(this===t&&r<e&&e<n)for(i=o-1;i>=0;--i)t[i+e]=this[i+r];else if(o<1e3||!c.TYPED_ARRAY_SUPPORT)for(i=0;i<o;++i)t[i+e]=this[i+r];else Uint8Array.prototype.set.call(t,this.subarray(r,r+o),e);return o},c.prototype.fill=function(t,e,r,n){if("string"==typeof t){if("string"==typeof e?(n=e,e=0,r=this.length):"string"==typeof r&&(n=r,r=this.length),1===t.length){var i=t.charCodeAt(0);i<256&&(t=i)}if(void 0!==n&&"string"!=typeof n)throw new TypeError("encoding must be a string");if("string"==typeof n&&!c.isEncoding(n))throw new TypeError("Unknown encoding: "+n)}else"number"==typeof t&&(t&=255);if(e<0||this.length<e||this.length<r)throw new RangeError("Out of range index");if(r<=e)return this;var o;if(e>>>=0,r=void 0===r?this.length:r>>>0,t||(t=0),"number"==typeof t)for(o=e;o<r;++o)this[o]=t;else{var a=c.isBuffer(t)?t:M(new c(t,n).toString()),s=a.length;for(o=0;o<r-e;++o)this[o+e]=a[o%s]}return this};var z=/[^+\\/0-9A-Za-z-_]/g;function N(t){return t<16?"0"+t.toString(16):t.toString(16)}function M(t,e){var r;e=e||1/0;for(var n=t.length,i=null,o=[],a=0;a<n;++a){if((r=t.charCodeAt(a))>55295&&r<57344){if(!i){if(r>56319){(e-=3)>-1&&o.push(239,191,189);continue}if(a+1===n){(e-=3)>-1&&o.push(239,191,189);continue}i=r;continue}if(r<56320){(e-=3)>-1&&o.push(239,191,189),i=r;continue}r=65536+(i-55296<<10|r-56320)}else i&&(e-=3)>-1&&o.push(239,191,189);if(i=null,r<128){if((e-=1)<0)break;o.push(r)}else if(r<2048){if((e-=2)<0)break;o.push(r>>6|192,63&r|128)}else if(r<65536){if((e-=3)<0)break;o.push(r>>12|224,r>>6&63|128,63&r|128)}else{if(!(r<1114112))throw new Error("Invalid code point");if((e-=4)<0)break;o.push(r>>18|240,r>>12&63|128,r>>6&63|128,63&r|128)}}return o}function F(t){return n.toByteArray(function(t){if((t=function(t){return t.trim?t.trim():t.replace(/^\\s+|\\s+$/g,"")}(t).replace(z,"")).length<2)return"";for(;t.length%4!=0;)t+="=";return t}(t))}function H(t,e,r,n){for(var i=0;i<n&&!(i+r>=e.length||i>=t.length);++i)e[i+r]=t[i];return i}}).call(this,r(144))},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(108);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}class a{static get({fs:t,gitdir:e}){return o((function*(){const r=yield t.read(`${e}/config`,{encoding:"utf8"});return n.a.from(r)}))()}static save({fs:t,gitdir:e,config:r}){return o((function*(){yield t.write(`${e}/config`,r.toString(),{encoding:"utf8"})}))()}}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return u}));var n=r(4),i=r(46),o=r(61),a=r(131);function s(t){switch(t){case"040000":return"tree";case"100644":case"100755":case"120000":return"blob";case"160000":return"commit"}throw new n.a(`Unexpected GitTree entry mode: ${t}`)}function c(t){return!t.oid&&t.sha&&(t.oid=t.sha),t.mode=function(t){if("number"==typeof t&&(t=t.toString(8)),t.match(/^0?4.*/))return"040000";if(t.match(/^1006.*/))return"100644";if(t.match(/^1007.*/))return"100755";if(t.match(/^120.*/))return"120000";if(t.match(/^160.*/))return"160000";throw new n.a(`Could not understand file mode: ${t}`)}(t.mode),t.type||(t.type=s(t.mode)),t}class u{constructor(e){if(t.isBuffer(e))this._entries=function(t){const e=[];let r=0;for(;r<t.length;){const o=t.indexOf(32,r);if(-1===o)throw new n.a(`GitTree: Error parsing buffer at byte location ${r}: Could not find the next space character.`);const a=t.indexOf(0,r);if(-1===a)throw new n.a(`GitTree: Error parsing buffer at byte location ${r}: Could not find the next null character.`);let c=t.slice(r,o).toString("utf8");"40000"===c&&(c="040000");const u=s(c),f=t.slice(o+1,a).toString("utf8");if(f.includes("\\\\")||f.includes("/"))throw new i.a(f);const l=t.slice(a+1,a+21).toString("hex");r=a+21,e.push({mode:c,path:f,oid:l,type:u})}return e}(e);else{if(!Array.isArray(e))throw new n.a("invalid type passed to GitTree constructor");this._entries=e.map(c)}this._entries.sort(o.a)}static from(t){return new u(t)}render(){return this._entries.map(t=>`${t.mode} ${t.type} ${t.oid}    ${t.path}`).join("\\n")}toObject(){const e=[...this._entries];return e.sort(a.a),t.concat(e.map(e=>{const r=t.from(e.mode.replace(/^0/,"")),n=t.from(" "),i=t.from(e.path,"utf8"),o=t.from([0]),a=t.from(e.oid,"hex");return t.concat([r,n,i,o,a])}))}entries(){return this._entries}*[Symbol.iterator](){for(const t of this._entries)yield t}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return p}));var n=r(33),i=r.n(n),o=r(76),a=r(106),s=r(69);function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function u(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){c(o,n,i,a,s,"next",t)}function s(t){c(o,n,i,a,s,"throw",t)}a(void 0)}))}}let f=null;const l=Symbol("IndexCache");function d(){return(d=u((function*(t,e,r){const[n,i]=yield Promise.all([t.lstat(e),t.read(e)]),o=yield a.a.from(i);r.map.set(e,o),r.stats.set(e,n)}))).apply(this,arguments)}function h(){return(h=u((function*(t,e,r){const n=r.stats.get(e);if(void 0===n)return!0;if(null===n)return!1;const i=yield t.lstat(e);return null!==i&&Object(s.a)(n,i)}))).apply(this,arguments)}class p{static acquire({fs:t,gitdir:e,cache:r,allowUnmerged:n=!0},a){return u((function*(){r[l]||(r[l]={map:new Map,stats:new Map});const s=`${e}/index`;let c;null===f&&(f=new i.a({maxPending:1/0}));let p=[];return yield f.acquire(s,u((function*(){const e=r[l];(yield function(t,e,r){return h.apply(this,arguments)}(t,s,e))&&(yield function(t,e,r){return d.apply(this,arguments)}(t,s,e));const i=e.map.get(s);if(p=i.unmergedPaths,p.length&&!n)throw new o.a(p);if(c=yield a(i),i._dirty){const r=yield i.toObject();yield t.write(s,r),e.stats.set(s,yield t.lstat(s)),i._dirty=!1}}))),c}))()}}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return f}));var n=r(4),i=r(64),o=r(90),a=r(23),s=r(135),c=r(51);function u(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}class f{constructor(e){if("string"==typeof e)this._commit=e;else if(t.isBuffer(e))this._commit=e.toString("utf8");else{if("object"!=typeof e)throw new n.a("invalid type passed to GitCommit constructor");this._commit=f.render(e)}}static fromPayloadSignature({payload:t,signature:e}){const r=f.justHeaders(t),n=f.justMessage(t),i=Object(a.a)(r+"\\ngpgsig"+Object(o.a)(e)+"\\n"+n);return new f(i)}static from(t){return new f(t)}toObject(){return t.from(this._commit,"utf8")}headers(){return this.parseHeaders()}message(){return f.justMessage(this._commit)}parse(){return Object.assign({message:this.message()},this.headers())}static justMessage(t){return Object(a.a)(t.slice(t.indexOf("\\n\\n")+2))}static justHeaders(t){return t.slice(0,t.indexOf("\\n\\n"))}parseHeaders(){const t=f.justHeaders(this._commit).split("\\n"),e=[];for(const r of t)" "===r[0]?e[e.length-1]+="\\n"+r.slice(1):e.push(r);const r={parent:[]};for(const t of e){const e=t.slice(0,t.indexOf(" ")),n=t.slice(t.indexOf(" ")+1);Array.isArray(r[e])?r[e].push(n):r[e]=n}return r.author&&(r.author=Object(c.a)(r.author)),r.committer&&(r.committer=Object(c.a)(r.committer)),r}static renderHeaders(t){let e="";if(t.tree?e+=`tree ${t.tree}\\n`:e+="tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\\n",t.parent){if(void 0===t.parent.length)throw new n.a("commit 'parent' property should be an array");for(const r of t.parent)e+=`parent ${r}\\n`}const r=t.author;e+=`author ${Object(i.a)(r)}\\n`;const a=t.committer||t.author;return e+=`committer ${Object(i.a)(a)}\\n`,t.gpgsig&&(e+="gpgsig"+Object(o.a)(t.gpgsig)),e}static render(t){return f.renderHeaders(t)+"\\n"+Object(a.a)(t.message)}render(){return this._commit}withoutSignature(){const t=Object(a.a)(this._commit);if(-1===t.indexOf("\\ngpgsig"))return t;const e=t.slice(0,t.indexOf("\\ngpgsig")),r=t.slice(t.indexOf("-----END PGP SIGNATURE-----\\n")+"-----END PGP SIGNATURE-----\\n".length);return Object(a.a)(e+"\\n"+r)}isolateSignature(){const t=this._commit.slice(this._commit.indexOf("-----BEGIN PGP SIGNATURE-----"),this._commit.indexOf("-----END PGP SIGNATURE-----")+"-----END PGP SIGNATURE-----".length);return Object(s.a)(t)}static sign(t,e,r){return(n=function*(){const n=t.withoutSignature(),i=f.justMessage(t._commit);let{signature:s}=yield e({payload:n,secretKey:r});s=Object(a.a)(s);const c=f.justHeaders(t._commit)+"\\ngpgsig"+Object(o.a)(s)+"\\n"+i;return f.from(c)},function(){var t=this,e=arguments;return new Promise((function(r,i){var o=n.apply(t,e);function a(t){u(o,r,i,a,s,"next",t)}function s(t){u(o,r,i,a,s,"throw",t)}a(void 0)}))})();var n}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return u}));var n=r(25),i=r(138),o=r(84),a=r(19);function s(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function c(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){s(o,n,i,a,c,"next",t)}function c(t){s(o,n,i,a,c,"throw",t)}a(void 0)}))}}function u(t){return f.apply(this,arguments)}function f(){return(f=c((function*({fs:e,gitdir:r,type:s,object:c,format:u="content",oid:f,dryRun:l=!1}){return"deflated"!==u&&("wrapped"!==u&&(c=n.a.wrap({type:s,object:c})),f=yield Object(a.a)(c),c=t.from(yield Object(o.a)(c))),l||(yield Object(i.a)({fs:e,gitdir:r,object:c,format:"deflated",oid:f})),f}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";(function(e){function r(t){if("string"!=typeof t)throw new TypeError("Path must be a string. Received "+JSON.stringify(t))}function n(t,e){for(var r,n="",i=0,o=-1,a=0,s=0;s<=t.length;++s){if(s<t.length)r=t.charCodeAt(s);else{if(47===r)break;r=47}if(47===r){if(o===s-1||1===a);else if(o!==s-1&&2===a){if(n.length<2||2!==i||46!==n.charCodeAt(n.length-1)||46!==n.charCodeAt(n.length-2))if(n.length>2){var c=n.lastIndexOf("/");if(c!==n.length-1){-1===c?(n="",i=0):i=(n=n.slice(0,c)).length-1-n.lastIndexOf("/"),o=s,a=0;continue}}else if(2===n.length||1===n.length){n="",i=0,o=s,a=0;continue}e&&(n.length>0?n+="/..":n="..",i=2)}else n.length>0?n+="/"+t.slice(o+1,s):n=t.slice(o+1,s),i=s-o-1;o=s,a=0}else 46===r&&-1!==a?++a:a=-1}return n}var i={resolve:function(){for(var t,i="",o=!1,a=arguments.length-1;a>=-1&&!o;a--){var s;a>=0?s=arguments[a]:(void 0===t&&(t=e.cwd()),s=t),r(s),0!==s.length&&(i=s+"/"+i,o=47===s.charCodeAt(0))}return i=n(i,!o),o?i.length>0?"/"+i:"/":i.length>0?i:"."},normalize:function(t){if(r(t),0===t.length)return".";var e=47===t.charCodeAt(0),i=47===t.charCodeAt(t.length-1);return 0!==(t=n(t,!e)).length||e||(t="."),t.length>0&&i&&(t+="/"),e?"/"+t:t},isAbsolute:function(t){return r(t),t.length>0&&47===t.charCodeAt(0)},join:function(){if(0===arguments.length)return".";for(var t,e=0;e<arguments.length;++e){var n=arguments[e];r(n),n.length>0&&(void 0===t?t=n:t+="/"+n)}return void 0===t?".":i.normalize(t)},relative:function(t,e){if(r(t),r(e),t===e)return"";if((t=i.resolve(t))===(e=i.resolve(e)))return"";for(var n=1;n<t.length&&47===t.charCodeAt(n);++n);for(var o=t.length,a=o-n,s=1;s<e.length&&47===e.charCodeAt(s);++s);for(var c=e.length-s,u=a<c?a:c,f=-1,l=0;l<=u;++l){if(l===u){if(c>u){if(47===e.charCodeAt(s+l))return e.slice(s+l+1);if(0===l)return e.slice(s+l)}else a>u&&(47===t.charCodeAt(n+l)?f=l:0===l&&(f=0));break}var d=t.charCodeAt(n+l);if(d!==e.charCodeAt(s+l))break;47===d&&(f=l)}var h="";for(l=n+f+1;l<=o;++l)l!==o&&47!==t.charCodeAt(l)||(0===h.length?h+="..":h+="/..");return h.length>0?h+e.slice(s+f):(s+=f,47===e.charCodeAt(s)&&++s,e.slice(s))},_makeLong:function(t){return t},dirname:function(t){if(r(t),0===t.length)return".";for(var e=t.charCodeAt(0),n=47===e,i=-1,o=!0,a=t.length-1;a>=1;--a)if(47===(e=t.charCodeAt(a))){if(!o){i=a;break}}else o=!1;return-1===i?n?"/":".":n&&1===i?"//":t.slice(0,i)},basename:function(t,e){if(void 0!==e&&"string"!=typeof e)throw new TypeError('"ext" argument must be a string');r(t);var n,i=0,o=-1,a=!0;if(void 0!==e&&e.length>0&&e.length<=t.length){if(e.length===t.length&&e===t)return"";var s=e.length-1,c=-1;for(n=t.length-1;n>=0;--n){var u=t.charCodeAt(n);if(47===u){if(!a){i=n+1;break}}else-1===c&&(a=!1,c=n+1),s>=0&&(u===e.charCodeAt(s)?-1==--s&&(o=n):(s=-1,o=c))}return i===o?o=c:-1===o&&(o=t.length),t.slice(i,o)}for(n=t.length-1;n>=0;--n)if(47===t.charCodeAt(n)){if(!a){i=n+1;break}}else-1===o&&(a=!1,o=n+1);return-1===o?"":t.slice(i,o)},extname:function(t){r(t);for(var e=-1,n=0,i=-1,o=!0,a=0,s=t.length-1;s>=0;--s){var c=t.charCodeAt(s);if(47!==c)-1===i&&(o=!1,i=s+1),46===c?-1===e?e=s:1!==a&&(a=1):-1!==e&&(a=-1);else if(!o){n=s+1;break}}return-1===e||-1===i||0===a||1===a&&e===i-1&&e===n+1?"":t.slice(e,i)},format:function(t){if(null===t||"object"!=typeof t)throw new TypeError('The "pathObject" argument must be of type Object. Received type '+typeof t);return function(t,e){var r=e.dir||e.root,n=e.base||(e.name||"")+(e.ext||"");return r?r===e.root?r+n:r+t+n:n}("/",t)},parse:function(t){r(t);var e={root:"",dir:"",base:"",ext:"",name:""};if(0===t.length)return e;var n,i=t.charCodeAt(0),o=47===i;o?(e.root="/",n=1):n=0;for(var a=-1,s=0,c=-1,u=!0,f=t.length-1,l=0;f>=n;--f)if(47!==(i=t.charCodeAt(f)))-1===c&&(u=!1,c=f+1),46===i?-1===a?a=f:1!==l&&(l=1):-1!==a&&(l=-1);else if(!u){s=f+1;break}return-1===a||-1===c||0===l||1===l&&a===c-1&&a===s+1?-1!==c&&(e.base=e.name=0===s&&o?t.slice(1,c):t.slice(s,c)):(0===s&&o?(e.name=t.slice(1,a),e.base=t.slice(1,c)):(e.name=t.slice(s,a),e.base=t.slice(s,c)),e.ext=t.slice(a,c)),s>0?e.dir=t.slice(0,s-1):o&&(e.dir="/"),e},sep:"/",delimiter:":",win32:null,posix:null};i.posix=i,t.exports=i}).call(this,r(92))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r,n){super(`Object ${t} ${n?`at ${n}`:""}was anticipated to be a ${r} but it is a ${e}.`),this.code=this.name=i.code,this.data={oid:t,actual:e,expected:r,filepath:n}}}i.code="ObjectTypeError"},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return c}));var n=r(4),i=r(64),o=r(23),a=r(51);function s(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}class c{constructor(e){if("string"==typeof e)this._tag=e;else if(t.isBuffer(e))this._tag=e.toString("utf8");else{if("object"!=typeof e)throw new n.a("invalid type passed to GitAnnotatedTag constructor");this._tag=c.render(e)}}static from(t){return new c(t)}static render(t){return`object ${t.object}\\ntype ${t.type}\\ntag ${t.tag}\\ntagger ${Object(i.a)(t.tagger)}\\n\\n${t.message}\\n${t.gpgsig?t.gpgsig:""}`}justHeaders(){return this._tag.slice(0,this._tag.indexOf("\\n\\n"))}message(){const t=this.withoutSignature();return t.slice(t.indexOf("\\n\\n")+2)}parse(){return Object.assign(this.headers(),{message:this.message(),gpgsig:this.gpgsig()})}render(){return this._tag}headers(){const t=this.justHeaders().split("\\n"),e=[];for(const r of t)" "===r[0]?e[e.length-1]+="\\n"+r.slice(1):e.push(r);const r={};for(const t of e){const e=t.slice(0,t.indexOf(" ")),n=t.slice(t.indexOf(" ")+1);Array.isArray(r[e])?r[e].push(n):r[e]=n}return r.tagger&&(r.tagger=Object(a.a)(r.tagger)),r.committer&&(r.committer=Object(a.a)(r.committer)),r}withoutSignature(){const t=Object(o.a)(this._tag);return-1===t.indexOf("\\n-----BEGIN PGP SIGNATURE-----")?t:t.slice(0,t.lastIndexOf("\\n-----BEGIN PGP SIGNATURE-----"))}gpgsig(){if(-1===this._tag.indexOf("\\n-----BEGIN PGP SIGNATURE-----"))return;const t=this._tag.slice(this._tag.indexOf("-----BEGIN PGP SIGNATURE-----"),this._tag.indexOf("-----END PGP SIGNATURE-----")+"-----END PGP SIGNATURE-----".length);return Object(o.a)(t)}payload(){return this.withoutSignature()+"\\n"}toObject(){return t.from(this._tag,"utf8")}static sign(t,e,r){return(n=function*(){const n=t.payload();let{signature:i}=yield e({payload:n,secretKey:r});i=Object(o.a)(i);const a=n+i;return c.from(a)},function(){var t=this,e=arguments;return new Promise((function(r,i){var o=n.apply(t,e);function a(t){s(o,r,i,a,c,"next",t)}function c(t){s(o,r,i,a,c,"throw",t)}a(void 0)}))})();var n}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";var n=r(78),i=r.n(n);function o(t){let e="";for(const r of new Uint8Array(t))r<16&&(e+="0"),e+=r.toString(16);return e}function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}r.d(e,"a",(function(){return u}));let c=null;function u(t){return f.apply(this,arguments)}function f(){return(f=s((function*(t){return null===c&&(c=yield p()),c?d(t):l(t)}))).apply(this,arguments)}function l(t){return(new i.a).update(t).digest("hex")}function d(t){return h.apply(this,arguments)}function h(){return(h=s((function*(t){return o(yield crypto.subtle.digest("SHA-1",t))}))).apply(this,arguments)}function p(){return y.apply(this,arguments)}function y(){return(y=s((function*(){try{if("da39a3ee5e6b4b0d3255bfef95601890afd80709"===(yield d(new Uint8Array([]))))return!0}catch(t){}return!1}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));class n{constructor(t){this.buffer=t,this._start=0}eof(){return this._start>=this.buffer.length}tell(){return this._start}seek(t){this._start=t}slice(t){const e=this.buffer.slice(this._start,this._start+t);return this._start+=t,e}toString(t,e){const r=this.buffer.toString(t,this._start,this._start+e);return this._start+=e,r}write(t,e,r){const n=this.buffer.write(t,this._start,e,r);return this._start+=e,n}copy(t,e,r){const n=t.copy(this.buffer,this._start,e,r);return this._start+=n,n}readUInt8(){const t=this.buffer.readUInt8(this._start);return this._start+=1,t}writeUInt8(t){const e=this.buffer.writeUInt8(t,this._start);return this._start+=1,e}readUInt16BE(){const t=this.buffer.readUInt16BE(this._start);return this._start+=2,t}writeUInt16BE(t){const e=this.buffer.writeUInt16BE(t,this._start);return this._start+=2,e}readUInt32BE(){const t=this.buffer.readUInt32BE(this._start);return this._start+=4,t}writeUInt32BE(t){const e=this.buffer.writeUInt32BE(t,this._start);return this._start+=4,e}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`No name was provided for ${t} in the argument or in the .git/config file.`),this.code=this.name=i.code,this.data={role:t}}}i.code="MissingNameError"},function(t,e,r){"use strict";var n=r(8),i=r(17),o=r(3),a=r(12),s=r(7),c=r(16),u=r(79),f=r(47);function l(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function d(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){l(o,n,i,a,s,"next",t)}function s(t){l(o,n,i,a,s,"throw",t)}a(void 0)}))}}class h{constructor({fs:t,gitdir:e,ref:r,cache:i}){var a=this;this.fs=t,this.cache=i,this.gitdir=e,this.mapPromise=d((function*(){const i=new Map;let s;try{s=yield o.a.resolve({fs:t,gitdir:e,ref:r})}catch(t){t instanceof n.a&&(s="4b825dc642cb6eb9a060e54bf8d69288fbee4904")}const c=yield Object(f.a)({fs:t,cache:a.cache,gitdir:e,oid:s});return c.type="tree",c.mode="40000",i.set(".",c),i}))();const s=this;this.ConstructEntry=class{constructor(t){this._fullpath=t,this._type=!1,this._mode=!1,this._stat=!1,this._content=!1,this._oid=!1}type(){var t=this;return d((function*(){return s.type(t)}))()}mode(){var t=this;return d((function*(){return s.mode(t)}))()}stat(){var t=this;return d((function*(){return s.stat(t)}))()}content(){var t=this;return d((function*(){return s.content(t)}))()}oid(){var t=this;return d((function*(){return s.oid(t)}))()}}}readdir(t){var e=this;return d((function*(){const r=t._fullpath,{fs:n,cache:o,gitdir:u}=e,f=yield e.mapPromise,l=f.get(r);if(!l)throw new Error(`No obj for ${r}`);const d=l.oid;if(!d)throw new Error(`No oid for obj ${JSON.stringify(l)}`);if("tree"!==l.type)return null;const{type:h,object:p}=yield Object(s.a)({fs:n,cache:o,gitdir:u,oid:d});if(h!==l.type)throw new i.a(d,h,l.type);const y=a.a.from(p);for(const t of y)f.set(Object(c.join)(r,t.path),t);return y.entries().map(t=>Object(c.join)(r,t.path))}))()}type(t){var e=this;return d((function*(){if(!1===t._type){const r=yield e.mapPromise,{type:n}=r.get(t._fullpath);t._type=n}return t._type}))()}mode(t){var e=this;return d((function*(){if(!1===t._mode){const r=yield e.mapPromise,{mode:n}=r.get(t._fullpath);t._mode=Object(u.a)(parseInt(n,8))}return t._mode}))()}stat(t){return d((function*(){}))()}content(t){var e=this;return d((function*(){if(!1===t._content){const r=yield e.mapPromise,{fs:n,cache:i,gitdir:o}=e,a=r.get(t._fullpath).oid,{type:c,object:u}=yield Object(s.a)({fs:n,cache:i,gitdir:o,oid:a});t._content="blob"!==c?void 0:new Uint8Array(u)}return t._content}))()}oid(t){var e=this;return d((function*(){if(!1===t._oid){const r=(yield e.mapPromise).get(t._fullpath);t._oid=r.oid}return t._oid}))()}}var p=r(37);function y({ref:t="HEAD"}={}){const e=Object.create(null);return Object.defineProperty(e,p.a,{value:function({fs:e,gitdir:r,cache:n}){return new h({fs:e,gitdir:r,ref:t,cache:n})}}),Object.freeze(e),e}r.d(e,"a",(function(){return y}))},function(t,e,r){"use strict";function n(t){return t=(t=(t=t.replace(/\\r/g,"")).replace(/^\\n+/,"")).replace(/\\n+$/,"")+"\\n"}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`The function requires a "${t}" parameter but none was provided.`),this.code=this.name=i.code,this.data={parameter:t}}}i.code="MissingParameterError"},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return i}));var n=r(4);class i{static wrap({type:e,object:r}){return t.concat([t.from(`${e} ${r.byteLength.toString()}\\0`),t.from(r)])}static unwrap(e){const r=e.indexOf(32),i=e.indexOf(0),o=e.slice(0,r).toString("utf8"),a=e.slice(r+1,i).toString("utf8"),s=e.length-(i+1);if(parseInt(a)!==s)throw new n.a(`Length mismatch: expected ${a} bytes but got ${s} instead.`);return{type:o,object:t.from(e.slice(i+1))}}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r=!0){super(`Failed to create ${t} at ${e} because it already exists.${r?` (Hint: use 'force: true' parameter to overwrite existing ${t}.)`:""}`),this.code=this.name=i.code,this.data={noun:t,where:e,canForce:r}}}i.code="AlreadyExistsError"},function(t,e,r){"use strict";function n(t){const e=Math.max(t.lastIndexOf("/"),t.lastIndexOf("\\\\"));return-1===e?".":0===e?"/":t.slice(0,e)}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`"${t}" would be an invalid git reference. (Hint: a valid alternative would be "${e}".)`),this.code=this.name=i.code,this.data={ref:t,suggestion:e}}}i.code="InvalidRefNameError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(41),i=r(85);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({fs:t,gitdir:e,author:r,commit:o}){const a=Math.floor(Date.now()/1e3),s={name:yield Object(n.a)({fs:t,gitdir:e,path:"user.name"}),email:(yield Object(n.a)({fs:t,gitdir:e,path:"user.email"}))||"",timestamp:a,timezoneOffset:new Date(1e3*a).getTimezoneOffset()},c=Object(i.a)({},s,o?o.author:void 0,r);if(void 0!==c.name)return c}))).apply(this,arguments)}},function(t,e,r){"use strict";function n(t,e){const r=e-t;return Array.from({length:r},(e,r)=>t+r)}var i=r(114),o=r(37);class a{constructor(){this.value=null}consider(t){null!=t&&(null===this.value?this.value=t:t<this.value&&(this.value=t))}reset(){this.value=null}}function*s(t){const e=new a;let r;const n=[],i=t.length;for(let r=0;r<i;r++)n[r]=t[r].next().value,void 0!==n[r]&&e.consider(n[r]);if(null!==e.value)for(;;){const o=[];r=e.value,e.reset();for(let a=0;a<i;a++)void 0!==n[a]&&n[a]===r?(o[a]=n[a],n[a]=t[a].next().value):o[a]=null,void 0!==n[a]&&e.consider(n[a]);if(yield o,null===e.value)return}}function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function u(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){c(o,n,i,a,s,"next",t)}function s(t){c(o,n,i,a,s,"throw",t)}a(void 0)}))}}function f(t){return l.apply(this,arguments)}function l(){return(l=u((function*({fs:t,cache:e,dir:r,gitdir:a,trees:c,map:f=function(){var t=u((function*(t,e){return e}));return function(e,r){return t.apply(this,arguments)}}(),reduce:l=function(){var t=u((function*(t,e){const r=Object(i.a)(e);return void 0!==t&&r.unshift(t),r}));return function(e,r){return t.apply(this,arguments)}}(),iterate:d=((t,e)=>Promise.all([...e].map(t)))}){const h=c.map(n=>n[o.a]({fs:t,dir:r,gitdir:a,cache:e})),p=new Array(h.length).fill("."),y=n(0,h.length),g=function(){var t=u((function*(t){y.map(e=>{const r=t[e];t[e]=r&&new h[e].ConstructEntry(r)});const e=(yield Promise.all(y.map(e=>{const r=t[e];return r?h[e].readdir(r):[]}))).map(t=>(null===t?[]:t)[Symbol.iterator]());return{entries:t,children:s(e)}}));return function(e){return t.apply(this,arguments)}}(),m=function(){var t=u((function*(t){const{entries:e,children:r}=yield g(t),n=e.find(t=>t&&t._fullpath)._fullpath,i=yield f(n,e);if(null!==i){let t=yield d(m,r);return t=t.filter(t=>void 0!==t),l(i,t)}}));return function(e){return t.apply(this,arguments)}}();return m(p)}))).apply(this,arguments)}r.d(e,"a",(function(){return f}))},function(t,e,r){"use strict";var n="undefined"!=typeof Uint8Array&&"undefined"!=typeof Uint16Array&&"undefined"!=typeof Int32Array;function i(t,e){return Object.prototype.hasOwnProperty.call(t,e)}e.assign=function(t){for(var e=Array.prototype.slice.call(arguments,1);e.length;){var r=e.shift();if(r){if("object"!=typeof r)throw new TypeError(r+"must be non-object");for(var n in r)i(r,n)&&(t[n]=r[n])}}return t},e.shrinkBuf=function(t,e){return t.length===e?t:t.subarray?t.subarray(0,e):(t.length=e,t)};var o={arraySet:function(t,e,r,n,i){if(e.subarray&&t.subarray)t.set(e.subarray(r,r+n),i);else for(var o=0;o<n;o++)t[i+o]=e[r+o]},flattenChunks:function(t){var e,r,n,i,o,a;for(n=0,e=0,r=t.length;e<r;e++)n+=t[e].length;for(a=new Uint8Array(n),i=0,e=0,r=t.length;e<r;e++)o=t[e],a.set(o,i),i+=o.length;return a}},a={arraySet:function(t,e,r,n,i){for(var o=0;o<n;o++)t[i+o]=e[r+o]},flattenChunks:function(t){return[].concat.apply([],t)}};e.setTyped=function(t){t?(e.Buf8=Uint8Array,e.Buf16=Uint16Array,e.Buf32=Int32Array,e.assign(e,o)):(e.Buf8=Array,e.Buf16=Array,e.Buf32=Array,e.assign(e,a))},e.setTyped(n)},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Expected a 40-char hex object id but saw "${t}".`),this.code=this.name=i.code,this.data={value:t}}}i.code="InvalidOidError"},function(t,e,r){"use strict";t.exports=r(143)},function(t,e,r){"use strict";r.d(e,"a",(function(){return o}));var n=r(79);function i(t,e,r,n){if(void 0!==t&&void 0!==e)return[t,e];void 0===r&&(r=n.valueOf());const i=Math.floor(r/1e3);return[i,1e6*(r-1e3*i)]}function o(t){const[e,r]=i(t.ctimeSeconds,t.ctimeNanoseconds,t.ctimeMs,t.ctime),[o,a]=i(t.mtimeSeconds,t.mtimeNanoseconds,t.mtimeMs,t.mtime);return{ctimeSeconds:e%2**32,ctimeNanoseconds:r%2**32,mtimeSeconds:o%2**32,mtimeNanoseconds:a%2**32,dev:t.dev%2**32,ino:t.ino%2**32,mode:Object(n.a)(t.mode%2**32),uid:t.uid%2**32,gid:t.gid%2**32,size:t.size>-1?t.size%2**32:0}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(3),i=r(66);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({fs:t,gitdir:e,fullname:r=!1,test:o=!1}){const a=yield n.a.resolve({fs:t,gitdir:e,ref:"HEAD",depth:2});if(o)try{yield n.a.resolve({fs:t,gitdir:e,ref:a})}catch(t){return}if(a.startsWith("refs/"))return r?a:Object(i.a)(a)}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`Expected "${t}" but received "${e}".`),this.code=this.name=i.code,this.data={expected:t,actual:e}}}i.code="ParseError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));const n=Symbol("GitWalkSymbol")},function(t,e,r){"use strict";function n(t,e){return-(t<e)||+(t>e)}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(88);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t,e){return s.apply(this,arguments)}function s(){return(s=o((function*(t,e){const r=Object(n.a)(t);for(;;){const{value:t,done:n}=yield r.next();if(t&&(yield e(t)),n)break}r.return&&r.return()}))).apply(this,arguments)}},function(t,e,r){"use strict";function n(t){const e=Math.max(t.lastIndexOf("/"),t.lastIndexOf("\\\\"));return e>-1&&(t=t.slice(e+1)),t}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(11);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t){return s.apply(this,arguments)}function s(){return(s=o((function*({fs:t,gitdir:e,path:r}){return(yield n.a.get({fs:t,gitdir:e})).get(r)}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return u}));var n=r(137),i=r.n(n),o=r(40),a=r(27),s=r(16);function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}class u{static isIgnored({fs:t,dir:e,gitdir:r=Object(s.join)(e,".git"),filepath:n}){return(u=function*(){if(".git"===Object(o.a)(n))return!0;if("."===n)return!1;let c="";const u=Object(s.join)(r,"info","exclude");(yield t.exists(u))&&(c=yield t.read(u,"utf8"));const f=[{gitignore:Object(s.join)(e,".gitignore"),filepath:n}],l=n.split("/").filter(Boolean);for(let t=1;t<l.length;t++){const r=l.slice(0,t).join("/"),n=l.slice(t).join("/");f.push({gitignore:Object(s.join)(e,r,".gitignore"),filepath:n})}let d=!1;for(const e of f){let r;try{r=yield t.read(e.gitignore,"utf8")}catch(t){if("NOENT"===t.code)continue}const n=i()().add(c);n.add(r);const o=Object(a.a)(e.filepath);if("."!==o&&n.ignores(o))return!0;d=d?!n.test(e.filepath).unignored:n.test(e.filepath).ignored}return d},function(){var t=this,e=arguments;return new Promise((function(r,n){var i=u.apply(t,e);function o(t){c(i,r,n,o,a,"next",t)}function a(t){c(i,r,n,o,a,"throw",t)}o(void 0)}))})();var u}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(41),i=r(85);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({fs:t,gitdir:e,author:r,committer:o,commit:a}){const s=Math.floor(Date.now()/1e3),c={name:yield Object(n.a)({fs:t,gitdir:e,path:"user.name"}),email:(yield Object(n.a)({fs:t,gitdir:e,path:"user.email"}))||"",timestamp:s,timezoneOffset:new Date(1e3*s).getTimezoneOffset()},u=Object(i.a)({},c,a?a.committer:void 0,r,o);if(void 0!==u.name)return u}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return u}));var n=r(33),i=r.n(n),o=r(16);function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}let c=null;class u{static read({fs:t,gitdir:e}){return s((function*(){null===c&&(c=new i.a);const r=Object(o.join)(e,"shallow"),n=new Set;return yield c.acquire(r,s((function*(){const e=yield t.read(r,{encoding:"utf8"});return null===e?n:""===e.trim()?n:void e.trim().split("\\n").map(t=>n.add(t))}))),n}))()}static write({fs:t,gitdir:e,oids:r}){return s((function*(){null===c&&(c=new i.a);const n=Object(o.join)(e,"shallow");if(r.size>0){const e=[...r].join("\\n")+"\\n";yield c.acquire(n,s((function*(){yield t.write(n,e,{encoding:"utf8"})})))}else yield c.acquire(n,s((function*(){yield t.rm(n)})))}))()}}},function(t,e,r){"use strict";function n(t,e,r){return e=e instanceof RegExp?e:new RegExp(e.replace(/[.*+?^${}()|[\\]\\\\]/g,"\\\\$&"),"g"),t.replace(e,r)}var i={clean:function(t){if("string"!=typeof t)throw new Error("Expected a string, received: "+t);return t=n(t,"./","/"),t=n(t,"..","."),t=n(t," ","-"),t=n(t,/^[~^:?*\\\\\\-]/g,""),t=n(t,/[~^:?*\\\\]/g,"-"),t=n(t,/[~^:?*\\\\\\-]$/g,""),t=n(t,"@{","-"),t=n(t,/\\.$/g,""),t=n(t,/\\/$/g,""),t=n(t,/\\.lock$/g,"")}};t.exports=i},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`The filepath "${t}" contains unsafe character sequences`),this.code=this.name=i.code,this.data={filepath:t}}}i.code="UnsafeFilepathError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return f}));var n=r(17),i=r(18),o=r(14),a=r(12),s=r(7);function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function u(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){c(o,n,i,a,s,"next",t)}function s(t){c(o,n,i,a,s,"throw",t)}a(void 0)}))}}function f(t){return l.apply(this,arguments)}function l(){return(l=u((function*({fs:t,cache:e,gitdir:r,oid:c}){if("4b825dc642cb6eb9a060e54bf8d69288fbee4904"===c)return{tree:a.a.from([]),oid:c};const{type:u,object:l}=yield Object(s.a)({fs:t,cache:e,gitdir:r,oid:c});if("tag"===u)return f({fs:t,cache:e,gitdir:r,oid:c=i.a.from(l).parse().object});if("commit"===u)return f({fs:t,cache:e,gitdir:r,oid:c=o.a.from(l).parse().tree});if("tree"!==u)throw new n.a(c,u,"tree");return{tree:a.a.from(l),oid:c}}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));const n={name:"isomorphic-git",version:"1.30.1",agent:"git/isomorphic-git@1.30.1"}},function(t,e,r){"use strict";var n={};(0,r(31).assign)(n,r(150),r(153),r(124)),t.exports=n},function(t,e,r){"use strict";function n(t,e){const r=e.toString(16);return"0".repeat(t-r.length)+r}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";function n(t){const[,e,r,n,o]=t.match(/^(.*) <(.*)> (.*) (.*)$/);return{name:e,email:r,timestamp:Number(n),timezoneOffset:i(o)}}function i(t){let[,e,r,n]=t.match(/(\\+|-)(\\d\\d)(\\d\\d)/);return n=("+"===e?1:-1)*(60*Number(r)+Number(n)),0===(i=n)?i:-i;var i}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(39);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t){return s.apply(this,arguments)}function s(){return(s=o((function*(t){let e=0;const r=[];yield Object(n.a)(t,t=>{r.push(t),e+=t.byteLength});const i=new Uint8Array(e);let o=0;for(const t of r)i.set(t,o),o+=t.byteLength;return i}))).apply(this,arguments)}},function(t,e,r){"use strict";function n(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function i(t){return function(){var e=this,r=arguments;return new Promise((function(i,o){var a=t.apply(e,r);function s(t){n(a,i,o,s,c,"next",t)}function c(t){n(a,i,o,s,c,"throw",t)}s(void 0)}))}}function o(t,e){return a.apply(this,arguments)}function a(){return(a=i((function*(t,e){return!(!t&&!e)&&(!(!t||e)||(!(t||!e)||("tree"!==(yield t.type())||"tree"!==(yield e.type()))&&((yield t.type())!==(yield e.type())||(yield t.mode())!==(yield e.mode())||(yield t.oid())!==(yield e.oid()))))}))).apply(this,arguments)}r.d(e,"a",(function(){return o}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(70),i=r(47);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({fs:t,cache:e,gitdir:r,oid:o,filepath:a}){void 0!==a&&(o=yield Object(n.a)({fs:t,cache:e,gitdir:r,oid:o,filepath:a}));const{tree:s,oid:c}=yield Object(i.a)({fs:t,cache:e,gitdir:r,oid:o});return{oid:c,tree:s.entries()}}))).apply(this,arguments)}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return v}));var n=r(59),i=r(73),o=r(58),a=r(86),s=r(52),c=r(117),u=r(87);function f(t,e){var r=Object.keys(t);if(Object.getOwnPropertySymbols){var n=Object.getOwnPropertySymbols(t);e&&(n=n.filter((function(e){return Object.getOwnPropertyDescriptor(t,e).enumerable}))),r.push.apply(r,n)}return r}function l(t){for(var e=1;e<arguments.length;e++){var r=null!=arguments[e]?arguments[e]:{};e%2?f(Object(r),!0).forEach((function(e){d(t,e,r[e])})):Object.getOwnPropertyDescriptors?Object.defineProperties(t,Object.getOwnPropertyDescriptors(r)):f(Object(r)).forEach((function(e){Object.defineProperty(t,e,Object.getOwnPropertyDescriptor(r,e))}))}return t}function d(t,e,r){return e in t?Object.defineProperty(t,e,{value:r,enumerable:!0,configurable:!0,writable:!0}):t[e]=r,t}function h(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function p(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){h(o,n,i,a,s,"next",t)}function s(t){h(o,n,i,a,s,"throw",t)}a(void 0)}))}}const y=(t,e)=>t.endsWith("?")?`${t}${e}`:`${t}/${e.replace(/^https?:\\/\\//,"")}`,g=(t,e)=>{(e.username||e.password)&&(t.Authorization=Object(a.a)(e)),e.headers&&Object.assign(t,e.headers)},m=function(){var e=p((function*(e){try{const r=t.from(yield Object(s.a)(e.body)),n=r.toString("utf8");return{preview:n.length<256?n:n.slice(0,256)+"...",response:n,data:r}}catch(t){return{}}}));return function(t){return e.apply(this,arguments)}}();class v{static capabilities(){return p((function*(){return["discover","connect"]}))()}static discover({http:t,onProgress:e,onAuth:r,onAuthSuccess:s,onAuthFailure:f,corsProxy:d,service:h,url:v,headers:w,protocolVersion:b}){return p((function*(){let{url:p,auth:_}=Object(c.a)(v);const j=d?y(d,p):p;let O,x;(_.username||_.password)&&(w.Authorization=Object(a.a)(_)),2===b&&(w["Git-Protocol"]="version=2");let P=!1;do{if(O=yield t.request({onProgress:e,method:"GET",url:`${j}/info/refs?service=${h}`,headers:w}),x=!1,401===O.statusCode||203===O.statusCode){const t=P?f:r;if(t){if(_=yield t(p,l({},_,{headers:l({},w)})),_&&_.cancel)throw new o.a;_&&(g(w,_),P=!0,x=!0)}}else 200===O.statusCode&&P&&s&&(yield s(p,_))}while(x);if(200!==O.statusCode){const{response:t}=yield m(O);throw new n.a(O.statusCode,O.statusMessage,t)}if(O.headers["content-type"]===`application/x-${h}-advertisement`){const t=yield Object(u.a)(O.body,{service:h});return t.auth=_,t}{const{preview:t,response:e,data:r}=yield m(O);try{const t=yield Object(u.a)([r],{service:h});return t.auth=_,t}catch(r){throw new i.a(t,e)}}}))()}static connect({http:t,onProgress:e,corsProxy:r,service:i,url:o,auth:a,body:s,headers:u}){return p((function*(){const f=Object(c.a)(o);f&&(o=f.url),r&&(o=y(r,o)),u["content-type"]=`application/x-${i}-request`,u.accept=`application/x-${i}-result`,g(u,a);const l=yield t.request({onProgress:e,method:"POST",url:`${o}/${i}`,body:s,headers:u});if(200!==l.statusCode){const{response:t}=m(l);throw new n.a(l.statusCode,l.statusMessage,t)}return l}))()}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(){super("Merges with conflicts are not supported yet."),this.code=this.name=i.code,this.data={}}}i.code="MergeNotSupportedError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r,n){super(`Automatic merge failed with one or more merge conflicts in the following files: ${t.toString()}. Fix conflicts then commit the result.`),this.code=this.name=i.code,this.data={filepaths:t,bothModified:e,deleteByUs:r,deleteByTheirs:n}}}i.code="MergeConflictError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(){super("The operation was canceled."),this.code=this.name=i.code,this.data={}}}i.code="UserCanceledError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r){super(`HTTP Error: ${t} ${e}`),this.code=this.name=i.code,this.data={statusCode:t,statusMessage:e,response:r}}}i.code="HttpError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){let e="invalid filepath";"leading-slash"===t||"trailing-slash"===t?e='"filepath" parameter should not include leading or trailing directory separators because these can cause problems on some platforms.':"directory"===t&&(e='"filepath" should not be a directory.'),super(e),this.code=this.name=i.code,this.data={reason:t}}}i.code="InvalidFilepathError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(38);function i(t,e){return Object(n.a)(t.path,e.path)}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return p}));var n=r(132),i=r.n(n),o=r(4),a=r(25),s=r(20),c=r(134),u=r(133),f=r(83),l=r(19);function d(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function h(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){d(o,n,i,a,s,"next",t)}function s(t){d(o,n,i,a,s,"throw",t)}a(void 0)}))}}class p{constructor(t){Object.assign(this,t),this.offsetCache={}}static fromIdx({idx:t,getExternalRefDelta:e}){return h((function*(){const r=new s.a(t);if("ff744f63"!==r.slice(4).toString("hex"))return;const n=r.readUInt32BE();if(2!==n)throw new o.a(`Unable to read version ${n} packfile IDX. (Only version 2 supported)`);if(t.byteLength>2147483648)throw new o.a("To keep implementation simple, I haven't implemented the layer 5 feature needed to support packfiles > 2GB in size.");r.seek(r.tell()+1020);const i=r.readUInt32BE(),a=[];for(let t=0;t<i;t++){const e=r.slice(20).toString("hex");a[t]=e}r.seek(r.tell()+4*i);const c=new Map;for(let t=0;t<i;t++)c.set(a[t],r.readUInt32BE());const u=r.slice(20).toString("hex");return new p({hashes:a,crcs:{},offsets:c,packfileSha:u,getExternalRefDelta:e})}))()}static fromPack({pack:t,getExternalRefDelta:e,onProgress:r}){return h((function*(){const n={1:"commit",2:"tree",3:"blob",4:"tag",6:"ofs-delta",7:"ref-delta"},o={},s=t.slice(-20).toString("hex"),c=[],f={},d=new Map;let y=null,g=null;yield Object(u.a)([t],function(){var t=h((function*({data:t,type:e,reference:i,offset:a,num:s}){null===y&&(y=s);const c=Math.floor(100*(y-s)/y);c!==g&&r&&(yield r({phase:"Receiving objects",loaded:y-s,total:y})),g=c,["commit","tree","blob","tag"].includes(e=n[e])?o[a]={type:e,offset:a}:"ofs-delta"===e?o[a]={type:e,offset:a}:"ref-delta"===e&&(o[a]={type:e,offset:a})}));return function(e){return t.apply(this,arguments)}}());const m=Object.keys(o).map(Number);for(const[e,r]of m.entries()){const n=e+1===m.length?t.byteLength-20:m[e+1],a=o[r],s=i.a.buf(t.slice(r,n))>>>0;a.end=n,a.crc=s}const v=new p({pack:Promise.resolve(t),packfileSha:s,crcs:f,hashes:c,offsets:d,getExternalRefDelta:e});g=null;let w=0;const b=[0,0,0,0,0,0,0,0,0,0,0,0];for(let t in o){t=Number(t);const e=Math.floor(100*w/y);e!==g&&r&&(yield r({phase:"Resolving deltas",loaded:w,total:y})),w++,g=e;const n=o[t];if(!n.oid)try{v.readDepth=0,v.externalReadDepth=0;const{type:e,object:r}=yield v.readSlice({start:t});b[v.readDepth]+=1;const i=yield Object(l.a)(a.a.wrap({type:e,object:r}));n.oid=i,c.push(i),d.set(i,t),f[i]=n.crc}catch(t){continue}}return c.sort(),v}))()}toBuffer(){var e=this;return h((function*(){const r=[],n=(e,n)=>{r.push(t.from(e,n))};n("ff744f63","hex"),n("00000002","hex");const i=new s.a(t.alloc(1024));for(let t=0;t<256;t++){let r=0;for(const n of e.hashes)parseInt(n.slice(0,2),16)<=t&&r++;i.writeUInt32BE(r)}r.push(i.buffer);for(const t of e.hashes)n(t,"hex");const o=new s.a(t.alloc(4*e.hashes.length));for(const t of e.hashes)o.writeUInt32BE(e.crcs[t]);r.push(o.buffer);const a=new s.a(t.alloc(4*e.hashes.length));for(const t of e.hashes)a.writeUInt32BE(e.offsets.get(t));r.push(a.buffer),n(e.packfileSha,"hex");const c=t.concat(r),u=yield Object(l.a)(c),f=t.alloc(20);return f.write(u,"hex"),t.concat([c,f])}))()}load({pack:t}){var e=this;return h((function*(){e.pack=t}))()}unload(){var t=this;return h((function*(){t.pack=null}))()}read({oid:t}){var e=this;return h((function*(){if(!e.offsets.get(t)){if(e.getExternalRefDelta)return e.externalReadDepth++,e.getExternalRefDelta(t);throw new o.a(`Could not read object ${t} from packfile`)}const r=e.offsets.get(t);return e.readSlice({start:r})}))()}readSlice({start:e}){var r=this;return h((function*(){if(r.offsetCache[e])return Object.assign({},r.offsetCache[e]);r.readDepth++;if(!r.pack)throw new o.a("Tried to read from a GitPackIndex with no packfile loaded into memory");const n=(yield r.pack).slice(e),i=new s.a(n),a=i.readUInt8(),u=112&a;let l={16:"commit",32:"tree",48:"blob",64:"tag",96:"ofs_delta",112:"ref_delta"}[u];if(void 0===l)throw new o.a("Unrecognized type: 0b"+u.toString(2));const d=15&a;let h=d;128&a&&(h=function(t,e){let r=e,n=4,i=null;do{i=t.readUInt8(),r|=(127&i)<<n,n+=7}while(128&i);return r}(i,d));let p=null,y=null;if("ofs_delta"===l){const t=function(t){const e=[];let r=0,n=0;do{r=t.readUInt8();const i=127&r;e.push(i),n=128&r}while(n);return e.reduce((t,e)=>t+1<<7|e,-1)}(i),n=e-t;({object:p,type:l}=yield r.readSlice({start:n}))}if("ref_delta"===l){const t=i.slice(20).toString("hex");({object:p,type:l}=yield r.read({oid:t}))}const g=n.slice(i.tell());if(y=t.from(yield Object(f.a)(g)),y.byteLength!==h)throw new o.a(`Packfile told us object would have length ${h} but it had length ${y.byteLength}`);return p&&(y=t.from(Object(c.a)(y,p))),r.readDepth>3&&(r.offsetCache[e]={type:l,object:y}),{type:l,format:"content",object:y}}))()}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";var n=r(74),i=r(75);var o=r(55);r.d(e,"a",(function(){return a}));class a{static getRemoteHelperFor({url:t}){const e=new Map;e.set("http",o.a),e.set("https",o.a);const r=function({url:t}){if(t.startsWith("git@"))return{transport:"ssh",address:t};const e=t.match(/(\\w+)(:\\/\\/|::)(.*)/);return null!==e?"://"===e[2]?{transport:e[1],address:e[0]}:"::"===e[2]?{transport:e[1],address:e[3]}:void 0:void 0}({url:t});if(!r)throw new i.a(t);if(e.has(r.transport))return e.get(r.transport);throw new n.a(t,r.transport,"ssh"===r.transport?function(t){return t=(t=t.replace(/^git@([^:]+):/,"https://$1/")).replace(/^ssh:\\/\\//,"https://")}(t):void 0)}}},function(t,e,r){"use strict";function n({name:t,email:e,timestamp:r,timezoneOffset:n}){return`${t} <${e}> ${r} ${n=function(t){const e=function(t){return Math.sign(t)||(Object.is(t,-0)?-1:1)}((r=t,0===r?r:-r));var r;t=Math.abs(t);const n=Math.floor(t/60);t-=60*n;let i=String(n),o=String(t);i.length<2&&(i="0"+i);o.length<2&&(o="0"+o);return(-1===e?"-":"+")+i+o}(n)}`}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";var n=r(17),i=r(18),o=r(14),a=r(7);function s(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function c(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){s(o,n,i,a,c,"next",t)}function c(t){s(o,n,i,a,c,"throw",t)}a(void 0)}))}}function u(t){return f.apply(this,arguments)}function f(){return(f=c((function*({fs:t,cache:e,gitdir:r,oid:s}){const{type:c,object:f}=yield Object(a.a)({fs:t,cache:e,gitdir:r,oid:s});if("tag"===c)return u({fs:t,cache:e,gitdir:r,oid:s=i.a.from(f).parse().object});if("commit"!==c)throw new n.a(s,c,"commit");return{commit:o.a.from(f),oid:s}}))).apply(this,arguments)}function l(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function d(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){l(o,n,i,a,s,"next",t)}function s(t){l(o,n,i,a,s,"throw",t)}a(void 0)}))}}function h(t){return p.apply(this,arguments)}function p(){return(p=d((function*({fs:t,cache:e,gitdir:r,oid:n}){const{commit:i,oid:o}=yield u({fs:t,cache:e,gitdir:r,oid:n});return{oid:o,commit:i.parse(),payload:i.withoutSignature()}}))).apply(this,arguments)}r.d(e,"a",(function(){return h}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));const n=new RegExp("^refs/(heads/|tags/|remotes/)?(.*)");function i(t){const e=n.exec(t);return e?"remotes/"===e[1]&&t.endsWith("/HEAD")?e[2].slice(0,-5):e[2]:t}},function(t,e,r){"use strict";function n(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}r.d(e,"a",(function(){return i}));class i{constructor(){this._queue=[]}write(t){if(this._ended)throw Error("You cannot write to a FIFO that has already been ended!");if(this._waiting){const e=this._waiting;this._waiting=null,e({value:t})}else this._queue.push(t)}end(){if(this._ended=!0,this._waiting){const t=this._waiting;this._waiting=null,t({done:!0})}}destroy(t){this.error=t,this.end()}next(){var t,e=this;return(t=function*(){if(e._queue.length>0)return{value:e._queue.shift()};if(e._ended)return{done:!0};if(e._waiting)throw Error("You cannot call read until the previous call to read has returned!");return new Promise(t=>{e._waiting=t})},function(){var e=this,r=arguments;return new Promise((function(i,o){var a=t.apply(e,r);function s(t){n(a,i,o,s,c,"next",t)}function c(t){n(a,i,o,s,c,"throw",t)}s(void 0)}))})()}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`Remote does not support the "${t}" so the "${e}" parameter cannot be used.`),this.code=this.name=i.code,this.data={capability:t,parameter:e}}}i.code="RemoteCapabilityError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(34);function i(t,e,r=!0,i=!0){const o=Object(n.a)(t),a=Object(n.a)(e);return r&&o.mode!==a.mode||o.mtimeSeconds!==a.mtimeSeconds||o.ctimeSeconds!==a.ctimeSeconds||o.uid!==a.uid||o.gid!==a.gid||i&&o.ino!==a.ino||o.size!==a.size}},function(t,e,r){"use strict";r.d(e,"a",(function(){return l}));var n=r(60),i=r(8),o=r(17),a=r(12),s=r(7),c=r(47);function u(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function f(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){u(o,n,i,a,s,"next",t)}function s(t){u(o,n,i,a,s,"throw",t)}a(void 0)}))}}function l(t){return d.apply(this,arguments)}function d(){return(d=f((function*({fs:t,cache:e,gitdir:r,oid:i,filepath:o}){if(o.startsWith("/"))throw new n.a("leading-slash");if(o.endsWith("/"))throw new n.a("trailing-slash");const a=i,s=yield Object(c.a)({fs:t,cache:e,gitdir:r,oid:i}),u=s.tree;if(""===o)i=s.oid;else{const n=o.split("/");i=yield h({fs:t,cache:e,gitdir:r,tree:u,pathArray:n,oid:a,filepath:o})}return i}))).apply(this,arguments)}function h(t){return p.apply(this,arguments)}function p(){return(p=f((function*({fs:t,cache:e,gitdir:r,tree:n,pathArray:c,oid:u,filepath:f}){const l=c.shift();for(const i of n)if(i.path===l){if(0===c.length)return i.oid;{const{type:l,object:d}=yield Object(s.a)({fs:t,cache:e,gitdir:r,oid:i.oid});if("tree"!==l)throw new o.a(u,l,"tree",f);return h({fs:t,cache:e,gitdir:r,tree:n=a.a.from(d),pathArray:c,oid:u,filepath:f})}}throw new i.a(`file or directory found at "${u}:${f}"`)}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(){super("Empty response from git server."),this.code=this.name=i.code,this.data={}}}i.code="EmptyServerResponseError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Could not find a fetch refspec for remote "${t}". Make sure the config file has an entry like the following:\\n[remote "${t}"]\\n\\tfetch = +refs/heads/*:refs/remotes/origin/*\\n`),this.code=this.name=i.code,this.data={remote:t}}}i.code="NoRefspecError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`Remote did not reply using the "smart" HTTP protocol. Expected "001e# service=git-upload-pack" but received: ${t}`),this.code=this.name=i.code,this.data={preview:t,response:e}}}i.code="SmartHttpError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r){super(`Git remote "${t}" uses an unrecognized transport protocol: "${e}"`),this.code=this.name=i.code,this.data={url:t,transport:e,suggestion:r}}}i.code="UnknownTransportError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Cannot parse remote URL: "${t}"`),this.code=this.name=i.code,this.data={url:t}}}i.code="UrlParseError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Modifying the index is not possible because you have unmerged files: ${t.toString}. Fix them up in the work tree, and then use 'git add/rm as appropriate to mark resolution and make a commit.`),this.code=this.name=i.code,this.data={filepaths:t}}}i.code="UnmergedPathsError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(67),i=r(9);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}class a{static demux(t){const e=i.a.streamReader(t),r=new n.a,a=new n.a,s=new n.a,c=function(){var n,i=(n=function*(){const n=yield e();if(null===n)return c();if(!0===n)return r.end(),s.end(),void(t.error?a.destroy(t.error):a.end());switch(n[0]){case 1:a.write(n.slice(1));break;case 2:s.write(n.slice(1));break;case 3:{const t=n.slice(1);return s.write(t),r.end(),s.end(),void a.destroy(new Error(t.toString("utf8")))}default:r.write(n)}c()},function(){var t=this,e=arguments;return new Promise((function(r,i){var a=n.apply(t,e);function s(t){o(a,r,i,s,c,"next",t)}function c(t){o(a,r,i,s,c,"throw",t)}s(void 0)}))});return function(){return i.apply(this,arguments)}}();return c(),{packetlines:r,packfile:a,progress:s}}}},function(t,e,r){var n=r(148),i=r(149),o=r(119).Buffer,a=[1518500249,1859775393,-1894007588,-899497514],s=new Array(80);function c(){this.init(),this._w=s,i.call(this,64,56)}function u(t){return t<<5|t>>>27}function f(t){return t<<30|t>>>2}function l(t,e,r,n){return 0===t?e&r|~e&n:2===t?e&r|e&n|r&n:e^r^n}n(c,i),c.prototype.init=function(){return this._a=1732584193,this._b=4023233417,this._c=2562383102,this._d=271733878,this._e=3285377520,this},c.prototype._update=function(t){for(var e,r=this._w,n=0|this._a,i=0|this._b,o=0|this._c,s=0|this._d,c=0|this._e,d=0;d<16;++d)r[d]=t.readInt32BE(4*d);for(;d<80;++d)r[d]=(e=r[d-3]^r[d-8]^r[d-14]^r[d-16])<<1|e>>>31;for(var h=0;h<80;++h){var p=~~(h/20),y=u(n)+l(p,i,o,s)+c+r[h]+a[p]|0;c=s,s=o,o=f(i),i=n,n=y}this._a=n+this._a|0,this._b=i+this._b|0,this._c=o+this._c|0,this._d=s+this._d|0,this._e=c+this._e|0},c.prototype._hash=function(){var t=o.allocUnsafe(20);return t.writeInt32BE(0|this._a,0),t.writeInt32BE(0|this._b,4),t.writeInt32BE(0|this._c,8),t.writeInt32BE(0|this._d,12),t.writeInt32BE(0|this._e,16),t},t.exports=c},function(t,e,r){"use strict";function n(t){let e=t>0?t>>12:0;4!==e&&8!==e&&10!==e&&14!==e&&(e=8);let r=511&t;return r=73&r?493:420,8!==e&&(r=0),(e<<12)+r}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(4);class i{constructor({remotePath:t,localPath:e,force:r,matchPrefix:n}){Object.assign(this,{remotePath:t,localPath:e,force:r,matchPrefix:n})}static from(t){const[e,r,o,a,s]=t.match(/^(\\+?)(.*?)(\\*?):(.*?)(\\*?)$/).slice(1),c="+"===e,u="*"===o;if(u!==("*"===s))throw new n.a("Invalid refspec");return new i({remotePath:r,localPath:a,force:c,matchPrefix:u})}translate(t){if(this.matchPrefix){if(t.startsWith(this.remotePath))return this.localPath+t.replace(this.remotePath,"")}else if(t===this.remotePath)return this.localPath;return null}reverseTranslate(t){if(this.matchPrefix){if(t.startsWith(this.localPath))return this.remotePath+t.replace(this.localPath,"")}else if(t===this.localPath)return this.remotePath;return null}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return c}));var n=r(62);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}const a=Symbol("PackfileCache");function s(){return(s=o((function*({fs:t,filename:e,getExternalRefDelta:r,emitter:i,emitterPrefix:o}){const a=yield t.read(e);return n.a.fromIdx({idx:a,getExternalRefDelta:r})}))).apply(this,arguments)}function c({fs:t,cache:e,filename:r,getExternalRefDelta:n,emitter:i,emitterPrefix:o}){e[a]||(e[a]=new Map);let c=e[a].get(r);return c||(c=function(t){return s.apply(this,arguments)}({fs:t,filename:r,getExternalRefDelta:n,emitter:i,emitterPrefix:o}),e[a].set(r,c)),c}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return a}));var n=r(88);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}class a{constructor(e){if(void 0===t)throw new Error("Missing Buffer dependency");this.stream=Object(n.a)(e),this.buffer=null,this.cursor=0,this.undoCursor=0,this.started=!1,this._ended=!1,this._discardedBytes=0}eof(){return this._ended&&this.cursor===this.buffer.length}tell(){return this._discardedBytes+this.cursor}byte(){var t=this;return o((function*(){if(!t.eof()&&(t.started||(yield t._init()),t.cursor!==t.buffer.length||(yield t._loadnext(),!t._ended)))return t._moveCursor(1),t.buffer[t.undoCursor]}))()}chunk(){var t=this;return o((function*(){if(!t.eof()&&(t.started||(yield t._init()),t.cursor!==t.buffer.length||(yield t._loadnext(),!t._ended)))return t._moveCursor(t.buffer.length),t.buffer.slice(t.undoCursor,t.cursor)}))()}read(t){var e=this;return o((function*(){if(!e.eof())return e.started||(yield e._init()),e.cursor+t>e.buffer.length&&(e._trim(),yield e._accumulate(t)),e._moveCursor(t),e.buffer.slice(e.undoCursor,e.cursor)}))()}skip(t){var e=this;return o((function*(){e.eof()||(e.started||(yield e._init()),e.cursor+t>e.buffer.length&&(e._trim(),yield e._accumulate(t)),e._moveCursor(t))}))()}undo(){var t=this;return o((function*(){t.cursor=t.undoCursor}))()}_next(){var e=this;return o((function*(){e.started=!0;let{done:r,value:n}=yield e.stream.next();return r&&(e._ended=!0,!n)?t.alloc(0):(n&&(n=t.from(n)),n)}))()}_trim(){this.buffer=this.buffer.slice(this.undoCursor),this.cursor-=this.undoCursor,this._discardedBytes+=this.undoCursor,this.undoCursor=0}_moveCursor(t){this.undoCursor=this.cursor,this.cursor+=t,this.cursor>this.buffer.length&&(this.cursor=this.buffer.length)}_accumulate(e){var r=this;return o((function*(){if(r._ended)return;const n=[r.buffer];for(;r.cursor+e>s(n);){const t=yield r._next();if(r._ended)break;n.push(t)}r.buffer=t.concat(n)}))()}_loadnext(){var t=this;return o((function*(){t._discardedBytes+=t.buffer.length,t.undoCursor=0,t.cursor=0,t.buffer=yield t._next()}))()}_init(){var t=this;return o((function*(){t.buffer=yield t._next()}))()}}function s(t){return t.reduce((t,e)=>t+e.length,0)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return c}));var n=r(49),i=r.n(n);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}let s=!1;function c(t){return u.apply(this,arguments)}function u(){return(u=a((function*(t){return null===s&&(s=d()),s?f(t):i.a.inflate(t)}))).apply(this,arguments)}function f(t){return l.apply(this,arguments)}function l(){return(l=a((function*(t){const e=new DecompressionStream("deflate"),r=new Blob([t]).stream().pipeThrough(e);return new Uint8Array(yield new Response(r).arrayBuffer())}))).apply(this,arguments)}function d(){try{if(new DecompressionStream("deflate"))return!0}catch(t){}return!1}},function(t,e,r){"use strict";r.d(e,"a",(function(){return c}));var n=r(49),i=r.n(n);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}let s=null;function c(t){return u.apply(this,arguments)}function u(){return(u=a((function*(t){return null===s&&(s=d()),s?f(t):i.a.deflate(t)}))).apply(this,arguments)}function f(t){return l.apply(this,arguments)}function l(){return(l=a((function*(t){const e=new CompressionStream("deflate"),r=new Blob([t]).stream().pipeThrough(e);return new Uint8Array(yield new Response(r).arrayBuffer())}))).apply(this,arguments)}function d(){try{return new CompressionStream("deflate").writable.close(),new Blob([]).stream().cancel(),!0}catch(t){return!1}}},function(t,e,r){"use strict";function n(t,...e){for(const r of e)if(r)for(const e of Object.keys(r)){const n=r[e];void 0!==n&&(t[e]=n)}return t}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";(function(t){function n({username:e="",password:r=""}){return`Basic ${t.from(`${e}:${r}`).toString("base64")}`}r.d(e,"a",(function(){return n}))}).call(this,r(10).Buffer)},function(t,e,r){"use strict";var n=r(71),i=r(36),o=r(9);function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}function c(t){return u.apply(this,arguments)}function u(){return(u=s((function*(t){const e={};let r;for(;r=yield t(),!0!==r;){if(null===r)continue;r=r.toString("utf8").replace(/\\n$/,"");const t=r.indexOf("=");if(t>-1){const n=r.slice(0,t),i=r.slice(t+1);e[n]=i}else e[r]=!0}return{protocolVersion:2,capabilities2:e}}))).apply(this,arguments)}function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t,e){return h.apply(this,arguments)}function h(){return(h=l((function*(t,{service:e}){const r=new Set,a=new Map,s=new Map,u=o.a.streamReader(t);let f=yield u();for(;null===f;)f=yield u();if(!0===f)throw new n.a;if(f.includes("version 2"))return c(u);if(f.toString("utf8").replace(/\\n$/,"")!==`# service=${e}`)throw new i.a(`# service=${e}\\\\n`,f.toString("utf8"));let l=yield u();for(;null===l;)l=yield u();if(!0===l)return{capabilities:r,refs:a,symrefs:s};if(l=l.toString("utf8"),l.includes("version 2"))return c(u);const[d,h]=p(l,"\\0","\\\\x00");if(h.split(" ").map(t=>r.add(t)),"0000000000000000000000000000000000000000 capabilities^{}"!==d){const[t,e]=p(d," "," ");for(a.set(e,t);;){const t=yield u();if(!0===t)break;if(null!==t){const[e,r]=p(t.toString("utf8")," "," ");a.set(r,e)}}}for(const t of r)if(t.startsWith("symref=")){const e=t.match(/symref=([^:]+):(.*)/);3===e.length&&s.set(e[1],e[2])}return{protocolVersion:1,capabilities:r,refs:a,symrefs:s}}))).apply(this,arguments)}function p(t,e,r){const n=t.trim().split(e);if(2!==n.length)throw new i.a(`Two strings separated by '${r}'`,t.toString("utf8"));return n}r.d(e,"a",(function(){return d}))},function(t,e,r){"use strict";function n(t){return t[Symbol.asyncIterator]?t[Symbol.asyncIterator]():t[Symbol.iterator]?t[Symbol.iterator]():t.next?t:function(t){let e=[t];return{next:()=>Promise.resolve({done:0===e.length,value:e.pop()}),return:()=>(e=[],{}),[Symbol.asyncIterator](){return this}}}(t)}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(12),i=r(15);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({fs:t,gitdir:e,tree:r}){const o=n.a.from(r).toObject();return yield Object(i.a)({fs:t,gitdir:e,type:"tree",object:o,format:"content"})}))).apply(this,arguments)}},function(t,e,r){"use strict";function n(t){return t.trim().split("\\n").map(t=>" "+t).join("\\n")+"\\n"}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";const n=(t,e)=>function(...r){return new(0,e.promiseModule)((n,i)=>{e.multiArgs?r.push((...t)=>{e.errorFirst?t[0]?i(t):(t.shift(),n(t)):n(t)}):e.errorFirst?r.push((t,e)=>{t?i(t):n(e)}):r.push(n),t.apply(this,r)})};t.exports=(t,e)=>{e=Object.assign({exclude:[/.+(Sync|Stream)$/],errorFirst:!0,promiseModule:Promise},e);const r=typeof t;if(null===t||"object"!==r&&"function"!==r)throw new TypeError(`Expected \\`input\\` to be a \\`Function\\` or \\`Object\\`, got \\`${null===t?"null":r}\\``);const i=t=>{const r=e=>"string"==typeof e?t===e:e.test(t);return e.include?e.include.some(r):!e.exclude.some(r)};let o;o="function"===r?function(...r){return e.excludeMain?t(...r):n(t,e).apply(this,r)}:Object.create(Object.getPrototypeOf(t));for(const r in t){const a=t[r];o[r]="function"==typeof a&&i(r)?n(a,e):a}return o}},function(t,e){var r,n,i=t.exports={};function o(){throw new Error("setTimeout has not been defined")}function a(){throw new Error("clearTimeout has not been defined")}function s(t){if(r===setTimeout)return setTimeout(t,0);if((r===o||!r)&&setTimeout)return r=setTimeout,setTimeout(t,0);try{return r(t,0)}catch(e){try{return r.call(null,t,0)}catch(e){return r.call(this,t,0)}}}!function(){try{r="function"==typeof setTimeout?setTimeout:o}catch(t){r=o}try{n="function"==typeof clearTimeout?clearTimeout:a}catch(t){n=a}}();var c,u=[],f=!1,l=-1;function d(){f&&c&&(f=!1,c.length?u=c.concat(u):l=-1,u.length&&h())}function h(){if(!f){var t=s(d);f=!0;for(var e=u.length;e;){for(c=u,u=[];++l<e;)c&&c[l].run();l=-1,e=u.length}c=null,f=!1,function(t){if(n===clearTimeout)return clearTimeout(t);if((n===a||!n)&&clearTimeout)return n=clearTimeout,clearTimeout(t);try{n(t)}catch(e){try{return n.call(null,t)}catch(e){return n.call(this,t)}}}(t)}}function p(t,e){this.fun=t,this.array=e}function y(){}i.nextTick=function(t){var e=new Array(arguments.length-1);if(arguments.length>1)for(var r=1;r<arguments.length;r++)e[r-1]=arguments[r];u.push(new p(t,e)),1!==u.length||f||s(h)},p.prototype.run=function(){this.fun.apply(null,this.array)},i.title="browser",i.browser=!0,i.env={},i.argv=[],i.version="",i.versions={},i.on=y,i.addListener=y,i.once=y,i.off=y,i.removeListener=y,i.removeAllListeners=y,i.emit=y,i.prependListener=y,i.prependOnceListener=y,i.listeners=function(t){return[]},i.binding=function(t){throw new Error("process.binding is not supported")},i.cwd=function(){return"/"},i.chdir=function(t){throw new Error("process.chdir is not supported")},i.umask=function(){return 0}},function(t,e,r){"use strict";r.r(e);var n=r(26);r.d(e,"AlreadyExistsError",(function(){return n.a}));var i=r(97);r.d(e,"AmbiguousError",(function(){return i.a}));var o=r(98);r.d(e,"CheckoutConflictError",(function(){return o.a}));var a=r(99);r.d(e,"CommitNotFetchedError",(function(){return a.a}));var s=r(71);r.d(e,"EmptyServerResponseError",(function(){return s.a}));var c=r(100);r.d(e,"FastForwardError",(function(){return c.a}));var u=r(101);r.d(e,"GitPushError",(function(){return u.a}));var f=r(59);r.d(e,"HttpError",(function(){return f.a}));var l=r(4);r.d(e,"InternalError",(function(){return l.a}));var d=r(60);r.d(e,"InvalidFilepathError",(function(){return d.a}));var h=r(32);r.d(e,"InvalidOidError",(function(){return h.a}));var p=r(28);r.d(e,"InvalidRefNameError",(function(){return p.a}));var y=r(102);r.d(e,"MaxDepthError",(function(){return y.a}));var g=r(56);r.d(e,"MergeNotSupportedError",(function(){return g.a}));var m=r(57);r.d(e,"MergeConflictError",(function(){return m.a}));var v=r(21);r.d(e,"MissingNameError",(function(){return v.a}));var w=r(24);r.d(e,"MissingParameterError",(function(){return w.a}));var b=r(103);r.d(e,"MultipleGitError",(function(){return b.a}));var _=r(72);r.d(e,"NoRefspecError",(function(){return _.a}));var j=r(8);r.d(e,"NotFoundError",(function(){return j.a}));var O=r(17);r.d(e,"ObjectTypeError",(function(){return O.a}));var x=r(36);r.d(e,"ParseError",(function(){return x.a}));var P=r(94);r.d(e,"PushRejectedError",(function(){return P.a}));var k=r(68);r.d(e,"RemoteCapabilityError",(function(){return k.a}));var E=r(73);r.d(e,"SmartHttpError",(function(){return E.a}));var S=r(74);r.d(e,"UnknownTransportError",(function(){return S.a}));var A=r(46);r.d(e,"UnsafeFilepathError",(function(){return A.a}));var R=r(75);r.d(e,"UrlParseError",(function(){return R.a}));var $=r(58);r.d(e,"UserCanceledError",(function(){return $.a}));var B=r(76);r.d(e,"UnmergedPathsError",(function(){return B.a}));var T=r(104);r.d(e,"IndexResetError",(function(){return T.a}));var I=r(105);r.d(e,"NoCommitError",(function(){return I.a}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){let e="";"not-fast-forward"===t?e=" because it was not a simple fast-forward":"tag-exists"===t&&(e=" because tag already exists"),super(`Push rejected${e}. Use "force: true" to override.`),this.code=this.name=i.code,this.data={reason:t}}}i.code="PushRejectedError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return m}));var n=r(21),i=r(24),o=r(105),a=r(13),s=r(3),c=r(14),u=r(12),f=r(15),l=r(107),d=r(29),h=r(43),p=r(65);function y(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function g(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){y(o,n,i,a,s,"next",t)}function s(t){y(o,n,i,a,s,"throw",t)}a(void 0)}))}}function m(t){return v.apply(this,arguments)}function v(){return(v=g((function*({fs:t,cache:e,onSign:r,gitdir:u,message:y,author:m,committer:v,signingKey:b,amend:_=!1,dryRun:j=!1,noUpdateBranch:O=!1,ref:x,parent:P,tree:k}){let E,S,A=!1;x||(x=yield s.a.resolve({fs:t,gitdir:u,ref:"HEAD",depth:2}));try{E=yield s.a.resolve({fs:t,gitdir:u,ref:x}),S=yield Object(p.a)({fs:t,gitdir:u,oid:E,cache:{}})}catch{A=!0}if(_&&A)throw new o.a(x);const R=_?yield Object(d.a)({fs:t,gitdir:u,author:m,commit:S.commit}):yield Object(d.a)({fs:t,gitdir:u,author:m});if(!R)throw new n.a("author");const $=_?yield Object(h.a)({fs:t,gitdir:u,author:R,committer:v,commit:S.commit}):yield Object(h.a)({fs:t,gitdir:u,author:R,committer:v});if(!$)throw new n.a("committer");return a.a.acquire({fs:t,gitdir:u,cache:e,allowUnmerged:!1},function(){var e=g((function*(e){const n=Object(l.a)(e.entries).get(".");if(k||(k=yield w({fs:t,gitdir:u,inode:n,dryRun:j})),P=P?yield Promise.all(P.map(e=>s.a.resolve({fs:t,gitdir:u,ref:e}))):_?S.commit.parent:E?[E]:[],!y){if(!_)throw new i.a("message");y=S.commit.message}let o=c.a.from({tree:k,parent:P,author:R,committer:$,message:y});b&&(o=yield c.a.sign(o,r,b));const a=yield Object(f.a)({fs:t,gitdir:u,type:"commit",object:o.toObject(),dryRun:j});return O||j||(yield s.a.writeRef({fs:t,gitdir:u,ref:x,value:a})),a}));return function(t){return e.apply(this,arguments)}}())}))).apply(this,arguments)}function w(t){return b.apply(this,arguments)}function b(){return(b=g((function*({fs:t,gitdir:e,inode:r,dryRun:n}){const i=r.children;for(const r of i)"tree"===r.type&&(r.metadata.mode="040000",r.metadata.oid=yield w({fs:t,gitdir:e,inode:r,dryRun:n}));const o=i.map(t=>({mode:t.metadata.mode,path:t.basename,oid:t.metadata.oid,type:t.type})),a=u.a.from(o);return yield Object(f.a)({fs:t,gitdir:e,type:"tree",object:a.toObject(),dryRun:n})}))).apply(this,arguments)}},function(t,e,r){"use strict";t.exports={2:"need dictionary",1:"stream end",0:"","-1":"file error","-2":"stream error","-3":"data error","-4":"insufficient memory","-5":"buffer error","-6":"incompatible version"}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e,r){super(`Found multiple ${t} matching "${e}" (${r.join(", ")}). Use a longer abbreviation length to disambiguate them.`),this.code=this.name=i.code,this.data={nouns:t,short:e,matches:r}}}i.code="AmbiguousError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Your local changes to the following files would be overwritten by checkout: ${t.join(", ")}`),this.code=this.name=i.code,this.data={filepaths:t}}}i.code="CheckoutConflictError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`Failed to checkout "${t}" because commit ${e} is not available locally. Do a git fetch to make the branch available locally.`),this.code=this.name=i.code,this.data={ref:t,oid:e}}}i.code="CommitNotFetchedError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(){super("A simple fast-forward merge was not possible."),this.code=this.name=i.code,this.data={}}}i.code="FastForwardError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t,e){super(`One or more branches were not updated: ${t}`),this.code=this.name=i.code,this.data={prettyDetails:t,result:e}}}i.code="GitPushError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Maximum search depth of ${t} exceeded.`),this.code=this.name=i.code,this.data={depth:t}}}i.code="MaxDepthError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super('There are multiple errors that were thrown by the method. Please refer to the "errors" property to see more'),this.code=this.name=i.code,this.data={errors:t},this.errors=t}}i.code="MultipleGitError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`Could not merge index: Entry for '${t}' is not up to date. Either reset the index entry to HEAD, or stage your unstaged changes.`),this.code=this.name=i.code,this.data={filepath:t}}}i.code="IndexResetError"},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(1);class i extends n.a{constructor(t){super(`"${t}" does not point to any commit. You're maybe working on a repository with no commits yet. `),this.code=this.name=i.code,this.data={ref:t}}}i.code="NoCommitError"},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return l}));var n=r(4),i=r(46),o=r(20),a=r(61),s=r(34),c=r(19);function u(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function f(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){u(o,n,i,a,s,"next",t)}function s(t){u(o,n,i,a,s,"throw",t)}a(void 0)}))}}class l{constructor(t,e){this._dirty=!1,this._unmergedPaths=e||new Set,this._entries=t||new Map}_addEntry(t){if(0===t.flags.stage)t.stages=[t],this._entries.set(t.path,t),this._unmergedPaths.delete(t.path);else{let e=this._entries.get(t.path);e||(this._entries.set(t.path,t),e=t),e.stages[t.flags.stage]=t,this._unmergedPaths.add(t.path)}}static from(e){return f((function*(){if(t.isBuffer(e))return l.fromBuffer(e);if(null===e)return new l(null);throw new n.a("invalid type passed to GitIndex.from")}))()}static fromBuffer(t){return f((function*(){if(0===t.length)throw new n.a("Index file is empty (.git/index)");const e=new l,r=new o.a(t),a=r.toString("utf8",4);if("DIRC"!==a)throw new n.a(`Invalid dircache magic file number: ${a}`);const s=yield Object(c.a)(t.slice(0,-20)),u=t.slice(-20).toString("hex");if(u!==s)throw new n.a(`Invalid checksum in GitIndex buffer: expected ${u} but saw ${s}`);const f=r.readUInt32BE();if(2!==f)throw new n.a(`Unsupported dircache version: ${f}`);const d=r.readUInt32BE();let h=0;for(;!r.eof()&&h<d;){const o={};o.ctimeSeconds=r.readUInt32BE(),o.ctimeNanoseconds=r.readUInt32BE(),o.mtimeSeconds=r.readUInt32BE(),o.mtimeNanoseconds=r.readUInt32BE(),o.dev=r.readUInt32BE(),o.ino=r.readUInt32BE(),o.mode=r.readUInt32BE(),o.uid=r.readUInt32BE(),o.gid=r.readUInt32BE(),o.size=r.readUInt32BE(),o.oid=r.slice(20).toString("hex");const a=r.readUInt16BE();o.flags=(p=a,{assumeValid:Boolean(32768&p),extended:Boolean(16384&p),stage:(12288&p)>>12,nameLength:4095&p});const s=t.indexOf(0,r.tell()+1)-r.tell();if(s<1)throw new n.a(`Got a path length of: ${s}`);if(o.path=r.toString("utf8",s),o.path.includes("..\\\\")||o.path.includes("../"))throw new i.a(o.path);let c=8-(r.tell()-12)%8;for(0===c&&(c=8);c--;){const t=r.readUInt8();if(0!==t)throw new n.a(`Expected 1-8 null characters but got '${t}' after ${o.path}`);if(r.eof())throw new n.a("Unexpected end of file")}o.stages=[],e._addEntry(o),h++}var p;return e}))()}get unmergedPaths(){return[...this._unmergedPaths]}get entries(){return[...this._entries.values()].sort(a.a)}get entriesMap(){return this._entries}get entriesFlat(){return[...this.entries].flatMap(t=>t.stages.length>1?t.stages.filter(t=>t):t)}*[Symbol.iterator](){for(const t of this.entries)yield t}insert({filepath:e,stats:r,oid:n,stage:i=0}){r||(r={ctimeSeconds:0,ctimeNanoseconds:0,mtimeSeconds:0,mtimeNanoseconds:0,dev:0,ino:0,mode:0,uid:0,gid:0,size:0}),r=Object(s.a)(r);const o=t.from(e),a={ctimeSeconds:r.ctimeSeconds,ctimeNanoseconds:r.ctimeNanoseconds,mtimeSeconds:r.mtimeSeconds,mtimeNanoseconds:r.mtimeNanoseconds,dev:r.dev,ino:r.ino,mode:r.mode||33188,uid:r.uid,gid:r.gid,size:r.size,path:e,oid:n,flags:{assumeValid:!1,extended:!1,stage:i,nameLength:o.length<4095?o.length:4095},stages:[]};this._addEntry(a),this._dirty=!0}delete({filepath:t}){if(this._entries.has(t))this._entries.delete(t);else for(const e of this._entries.keys())e.startsWith(t+"/")&&this._entries.delete(e);this._unmergedPaths.has(t)&&this._unmergedPaths.delete(t),this._dirty=!0}clear(){this._entries.clear(),this._dirty=!0}has({filepath:t}){return this._entries.has(t)}render(){return this.entries.map(t=>`${t.mode.toString(8)} ${t.oid}    ${t.path}`).join("\\n")}static _entryToBuffer(e){return f((function*(){const r=t.from(e.path),n=8*Math.ceil((62+r.length+1)/8),i=t.alloc(n),a=new o.a(i),c=Object(s.a)(e);return a.writeUInt32BE(c.ctimeSeconds),a.writeUInt32BE(c.ctimeNanoseconds),a.writeUInt32BE(c.mtimeSeconds),a.writeUInt32BE(c.mtimeNanoseconds),a.writeUInt32BE(c.dev),a.writeUInt32BE(c.ino),a.writeUInt32BE(c.mode),a.writeUInt32BE(c.uid),a.writeUInt32BE(c.gid),a.writeUInt32BE(c.size),a.write(e.oid,20,"hex"),a.writeUInt16BE(function(e){const r=e.flags;return r.extended=!1,r.nameLength=Math.min(t.from(e.path).length,4095),(r.assumeValid?32768:0)+(r.extended?16384:0)+((3&r.stage)<<12)+(4095&r.nameLength)}(e)),a.write(e.path,r.length,"utf8"),i}))()}toObject(){var e=this;return f((function*(){const r=t.alloc(12),n=new o.a(r);n.write("DIRC",4,"utf8"),n.writeUInt32BE(2),n.writeUInt32BE(e.entriesFlat.length);let i=[];for(const t of e.entries)if(i.push(l._entryToBuffer(t)),t.stages.length>1)for(const e of t.stages)e&&e!==t&&i.push(l._entryToBuffer(e));i=yield Promise.all(i);const a=t.concat(i),s=t.concat([r,a]),u=yield Object(c.a)(s);return t.concat([s,t.from(u,"hex")])}))()}}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return o}));var n=r(40),i=r(27);function o(t){const e=new Map,r=function(t){if(!e.has(t)){const o={type:"tree",fullpath:t,basename:Object(n.a)(t),metadata:{},children:[]};e.set(t,o),o.parent=r(Object(i.a)(t)),o.parent&&o.parent!==o&&o.parent.children.push(o)}return e.get(t)},o=function(t,o){if(!e.has(t)){const a={type:"blob",fullpath:t,basename:Object(n.a)(t),metadata:o,parent:r(Object(i.a)(t)),children:[]};a.parent&&a.parent.children.push(a),e.set(t,a)}return e.get(t)};r(".");for(const e of t)o(e.path,e);return e}},function(t,e,r){"use strict";function n(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function i(t){return function(){var e=this,r=arguments;return new Promise((function(i,o){var a=t.apply(e,r);function s(t){n(a,i,o,s,c,"next",t)}function c(t){n(a,i,o,s,c,"throw",t)}s(void 0)}))}}r.d(e,"a",(function(){return v}));const o=t=>{if("boolean"==typeof t)return t;if("true"===(t=t.trim().toLowerCase())||"yes"===t||"on"===t)return!0;if("false"===t||"no"===t||"off"===t)return!1;throw Error(`Expected 'true', 'false', 'yes', 'no', 'on', or 'off', but got ${t}`)},a={core:{filemode:o,bare:o,logallrefupdates:o,symlinks:o,ignorecase:o,bigFileThreshold:t=>{if("number"==typeof t)return t;t=t.toLowerCase();let e=parseInt(t);return t.endsWith("k")&&(e*=1024),t.endsWith("m")&&(e*=1048576),t.endsWith("g")&&(e*=1073741824),e}}},s=/^\\[([A-Za-z0-9-.]+)(?: "(.*)")?\\]$/,c=/^[A-Za-z0-9-.]+$/,u=/^([A-Za-z][A-Za-z-]*)(?: *= *(.*))?$/,f=/^[A-Za-z][A-Za-z-]*$/,l=/^(.*?)( *[#;].*)$/,d=t=>{const e=l.exec(t);if(null==e)return t;const[r,n]=e.slice(1);return h(r)&&h(n)?`${r}${n}`:r},h=t=>(t.match(/(?:^|[^\\\\])"/g)||[]).length%2!=0,p=t=>t.split("").reduce((t,e,r,n)=>{const i='"'===e&&"\\\\"!==n[r-1],o="\\\\"===e&&'"'===n[r+1];return i||o?t:t+e},""),y=t=>null!=t?t.toLowerCase():null,g=(t,e,r)=>[y(t),e,y(r)].filter(t=>null!=t).join("."),m=t=>{const e=t.split("."),r=e.shift(),n=e.pop(),i=e.length?e.join("."):void 0;return{section:r,subsection:i,name:n,path:g(r,i,n),sectionPath:g(r,i,null),isSection:!!r}};class v{constructor(t){let e=null,r=null;this.parsedConfig=t?t.split("\\n").map(t=>{let n=null,i=null;const o=t.trim(),a=(t=>{const e=s.exec(t);if(null!=e){const[t,r]=e.slice(1);return[t,r]}return null})(o),c=null!=a;if(c)[e,r]=a;else{const t=(t=>{const e=u.exec(t);if(null!=e){const[t,r="true"]=e.slice(1),n=d(r);return[t,p(n)]}return null})(o);null!=t&&([n,i]=t)}const f=g(e,r,n);return{line:t,isSection:c,section:e,subsection:r,name:n,value:i,path:f}}):[]}static from(t){return new v(t)}get(t,e=!1){var r=this;return i((function*(){const n=m(t).path,i=r.parsedConfig.filter(t=>t.path===n).map(({section:t,name:e,value:r})=>{const n=a[t]&&a[t][e];return n?n(r):r});return e?i:i.pop()}))()}getall(t){var e=this;return i((function*(){return e.get(t,!0)}))()}getSubsections(t){var e=this;return i((function*(){return e.parsedConfig.filter(e=>e.isSection&&e.section===t).map(t=>t.subsection)}))()}deleteSection(t,e){var r=this;return i((function*(){r.parsedConfig=r.parsedConfig.filter(r=>!(r.section===t&&r.subsection===e))}))()}append(t,e){var r=this;return i((function*(){return r.set(t,e,!0)}))()}set(t,e,r=!1){var n=this;return i((function*(){const{section:i,subsection:o,name:a,path:s,sectionPath:u,isSection:l}=m(t),d=(h=n.parsedConfig,p=t=>t.path===s,h.reduce((t,e,r)=>p(e)?r:t,-1));var h,p;if(null==e)-1!==d&&n.parsedConfig.splice(d,1);else if(-1!==d){const t=n.parsedConfig[d],i=Object.assign({},t,{name:a,value:e,modified:!0});r?n.parsedConfig.splice(d+1,0,i):n.parsedConfig[d]=i}else{const t=n.parsedConfig.findIndex(t=>t.path===u),r={section:i,subsection:o,name:a,value:e,modified:!0,path:s};if(c.test(i)&&f.test(a))if(t>=0)n.parsedConfig.splice(t+1,0,r);else{const t={isSection:l,section:i,subsection:o,modified:!0,path:u};n.parsedConfig.push(t,r)}}}))()}toString(){return this.parsedConfig.map(({line:t,section:e,subsection:r,name:n,value:i,modified:o=!1})=>o?null!=n&&null!=i?"string"==typeof i&&/[#;]/.test(i)?`\\t${n} = "${i}"`:`\\t${n} = ${i}`:null!=r?`[${e} "${r}"]`:`[${e}]`:t).join("\\n")}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(80);class i{constructor(t=[]){this.rules=t}static from(t){const e=[];for(const r of t)e.push(n.a.from(r));return new i(e)}add(t){const e=n.a.from(t);this.rules.push(e)}translate(t){const e=[];for(const r of this.rules)for(const n of t){const t=r.translate(n);t&&e.push([n,t])}return e}translateOne(t){let e=null;for(const r of this.rules){const n=r.translate(t);n&&(e=n)}return e}localNamespaces(){return this.rules.filter(t=>t.matchPrefix).map(t=>t.localPath.replace(/\\/$/,""))}}},function(t,e,r){"use strict";r.d(e,"a",(function(){return c}));var n=r(4),i=r(81),o=r(16);function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}function c(t){return u.apply(this,arguments)}function u(){return(u=s((function*({fs:t,cache:e,gitdir:r,oid:a,format:s="content",getExternalRefDelta:c}){let u=yield t.readdir(Object(o.join)(r,"objects/pack"));u=u.filter(t=>t.endsWith(".idx"));for(const o of u){const s=`${r}/objects/pack/${o}`,u=yield Object(i.a)({fs:t,cache:e,filename:s,getExternalRefDelta:c});if(u.error)throw new n.a(u.error);if(u.offsets.has(a)){if(!u.pack){const e=s.replace(/idx$/,"pack");u.pack=t.read(e)}const e=yield u.read({oid:a,getExternalRefDelta:c});return e.format="content",e.source=`objects/pack/${o.replace(/idx$/,"pack")}`,e}}return null}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(139),i=r.n(n);const o=/^.*(\\r?\\n|$)/gm;function a({branches:t,contents:e}){const r=t[1],n=t[2],a=e[0],s=e[1],c=e[2],u=s.match(o),f=a.match(o),l=c.match(o),d=i()(u,f,l);let h="",p=!0;for(const t of d)t.ok&&(h+=t.ok.join("")),t.conflict&&(p=!1,h+=`${"<".repeat(7)} ${r}\\n`,h+=t.conflict.a.join(""),h+=`${"=".repeat(7)}\\n`,h+=t.conflict.b.join(""),h+=`${">".repeat(7)} ${n}\\n`);return{cleanMerge:p,mergedText:h}}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return d}));var n=r(78),i=r.n(n),o=r(140),a=r(7),s=r(84),c=r(16),u=r(50);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:e,cache:r,dir:n,gitdir:f=Object(c.join)(n,".git"),oids:d}){const h=new i.a,p=[];function y(e,r){const n=t.from(e,r);p.push(n),h.update(n)}function g(t){return m.apply(this,arguments)}function m(){return(m=l((function*({stype:e,object:r}){const n=o.a[e];let i=r.length,a=i>15?128:0;const c=15&i;i>>>=4;let f=(a|n|c).toString(16);for(y(f,"hex");a;)a=i>127?128:0,f=a|127&i,y(Object(u.a)(2,f),"hex"),i>>>=7;y(t.from(yield Object(s.a)(r)))}))).apply(this,arguments)}y("PACK"),y("00000002","hex"),y(Object(u.a)(8,d.length),"hex");for(const t of d){const{type:n,object:i}=yield Object(a.a)({fs:e,cache:r,gitdir:f,oid:t});yield g({write:y,object:i,stype:n})}const v=h.digest();return p.push(v),p}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";function n(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function i(t){return function(){var e=this,r=arguments;return new Promise((function(i,o){var a=t.apply(e,r);function s(t){n(a,i,o,s,c,"next",t)}function c(t){n(a,i,o,s,c,"throw",t)}s(void 0)}))}}function o(t){return a.apply(this,arguments)}function a(){return(a=i((function*({fs:t,gitdir:e,oid:r}){const n=`objects/${r.slice(0,2)}/${r.slice(2)}`,i=yield t.read(`${e}/${n}`);return i?{object:i,format:"deflated",source:n}:null}))).apply(this,arguments)}r.d(e,"a",(function(){return o}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));const n=void 0===Array.prototype.flat?t=>t.reduce((t,e)=>t.concat(e),[]):t=>t.flat()},function(t,e,r){"use strict";r.d(e,"a",(function(){return f}));var n=r(18),i=r(14),o=r(12),a=r(7),s=r(16);function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function u(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){c(o,n,i,a,s,"next",t)}function s(t){c(o,n,i,a,s,"throw",t)}a(void 0)}))}}function f(t){return l.apply(this,arguments)}function l(){return(l=u((function*({fs:t,cache:e,dir:r,gitdir:c=Object(s.join)(r,".git"),oids:f}){const l=new Set;function d(t){return h.apply(this,arguments)}function h(){return(h=u((function*(r){if(l.has(r))return;l.add(r);const{type:s,object:u}=yield Object(a.a)({fs:t,cache:e,gitdir:c,oid:r});if("tag"===s){const t=n.a.from(u).headers().object;yield d(t)}else if("commit"===s){const t=i.a.from(u).headers().tree;yield d(t)}else if("tree"===s){const t=o.a.from(u);for(const e of t)"blob"===e.type&&l.add(e.oid),"tree"===e.type&&(yield d(e.oid))}}))).apply(this,arguments)}for(const t of f)yield d(t);return l}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(16);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t,e){return s.apply(this,arguments)}function s(){return(s=o((function*(t,e){const r=yield t.readdir(e);null==r?yield t.rm(e):r.length?yield Promise.all(r.map(r=>{const i=Object(n.join)(e,r);return t.lstat(i).then(e=>{if(e)return e.isDirectory()?a(t,i):t.rm(i)})})).then(()=>t.rmdir(e)):yield t.rmdir(e)}))).apply(this,arguments)}},function(t,e,r){"use strict";function n(t){let e=t.match(/^https?:\\/\\/([^/]+)@/);if(null==e)return{url:t,auth:{}};e=e[1];const[r,n]=e.split(":");return{url:t=t.replace(`${e}@`,""),auth:{username:r,password:n}}}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return k}));var n=r(35),i=r(24),o=r(68),a=r(11),s=r(3),c=r(63),u=r(44),f=r(14),l=r(62),d=r(161),h=r(7),p=r(66),y=r(52),g=r(164),m=r(141),v=r(39),w=r(16),b=r(48),_=r(142),j=r(126),O=r(125);function x(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function P(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){x(o,n,i,a,s,"next",t)}function s(t){x(o,n,i,a,s,"throw",t)}a(void 0)}))}}function k(t){return E.apply(this,arguments)}function E(){return(E=P((function*({fs:e,cache:r,http:x,onProgress:k,onMessage:E,onAuth:S,onAuthSuccess:A,onAuthFailure:R,gitdir:$,ref:B,remoteRef:T,remote:I,url:C,corsProxy:U,depth:D=null,since:z=null,exclude:N=[],relative:M=!1,tags:F=!1,singleBranch:H=!1,headers:L={},prune:q=!1,pruneTags:G=!1}){const Y=B||(yield Object(n.a)({fs:e,gitdir:$,test:!0})),W=yield a.a.get({fs:e,gitdir:$}),Z=I||Y&&(yield W.get(`branch.${Y}.remote`))||"origin",K=C||(yield W.get(`remote.${Z}.url`));if(void 0===K)throw new i.a("remote OR url");const V=T||Y&&(yield W.get(`branch.${Y}.merge`))||B||"HEAD";void 0===U&&(U=yield W.get("http.corsProxy"));const X=c.a.getRemoteHelperFor({url:K}),J=yield X.discover({http:x,onAuth:S,onAuthSuccess:A,onAuthFailure:R,corsProxy:U,service:"git-upload-pack",url:K,headers:L,protocolVersion:1}),Q=J.auth,tt=J.refs;if(0===tt.size)return{defaultBranch:null,fetchHead:null,fetchHeadDescription:null};if(null!==D&&!J.capabilities.has("shallow"))throw new o.a("shallow","depth");if(null!==z&&!J.capabilities.has("deepen-since"))throw new o.a("deepen-since","since");if(N.length>0&&!J.capabilities.has("deepen-not"))throw new o.a("deepen-not","exclude");if(!0===M&&!J.capabilities.has("deepen-relative"))throw new o.a("deepen-relative","relative");const{oid:et,fullref:rt}=s.a.resolveAgainstMap({ref:V,map:tt});for(const t of tt.keys())t===rt||"HEAD"===t||t.startsWith("refs/heads/")||F&&t.startsWith("refs/tags/")||tt.delete(t);const nt=Object(m.a)([...J.capabilities],["multi_ack_detailed","no-done","side-band-64k","ofs-delta",`agent=${b.a.agent}`]);M&&nt.push("deepen-relative");const it=H?[et]:tt.values(),ot=H?[Y]:yield s.a.listRefs({fs:e,gitdir:$,filepath:"refs"});let at=[];for(let t of ot)try{t=yield s.a.expand({fs:e,gitdir:$,ref:t});const n=yield s.a.resolve({fs:e,gitdir:$,ref:t});(yield Object(d.a)({fs:e,cache:r,gitdir:$,oid:n}))&&at.push(n)}catch(t){}at=[...new Set(at)];const st=yield u.a.read({fs:e,gitdir:$}),ct=J.capabilities.has("shallow")?[...st]:[],ut=Object(O.a)({capabilities:nt,wants:it,haves:at,shallows:ct,depth:D,since:z,exclude:N}),ft=t.from(yield Object(y.a)(ut)),lt=yield X.connect({http:x,onProgress:k,corsProxy:U,service:"git-upload-pack",url:K,auth:Q,body:[ft],headers:L}),dt=yield Object(j.a)(lt.body);lt.headers&&(dt.headers=lt.headers);for(const t of dt.shallows)if(!st.has(t))try{const{object:n}=yield Object(h.a)({fs:e,cache:r,gitdir:$,oid:t}),i=new f.a(n),o=yield Promise.all(i.headers().parent.map(t=>Object(d.a)({fs:e,cache:r,gitdir:$,oid:t})));0===o.length||o.every(t=>t)||st.add(t)}catch(e){st.add(t)}for(const t of dt.unshallows)st.delete(t);if(yield u.a.write({fs:e,gitdir:$,oids:st}),H){const t=new Map([[rt,et]]),r=new Map;let n=10,i=rt;for(;n--;){const t=J.symrefs.get(i);if(void 0===t)break;r.set(i,t),i=t}const o=tt.get(i);o&&t.set(i,o);const{pruned:a}=yield s.a.updateRemoteRefs({fs:e,gitdir:$,remote:Z,refs:t,symrefs:r,tags:F,prune:q});q&&(dt.pruned=a)}else{const{pruned:t}=yield s.a.updateRemoteRefs({fs:e,gitdir:$,remote:Z,refs:tt,symrefs:J.symrefs,tags:F,prune:q,pruneTags:G});q&&(dt.pruned=t)}if(dt.HEAD=J.symrefs.get("HEAD"),void 0===dt.HEAD){const{oid:t}=s.a.resolveAgainstMap({ref:"HEAD",map:tt});for(const[e,r]of tt.entries())if("HEAD"!==e&&r===t){dt.HEAD=e;break}}const ht=rt.startsWith("refs/tags")?"tag":"branch";if(dt.FETCH_HEAD={oid:et,description:`${ht} '${Object(p.a)(rt)}' of ${K}`},k||E){const t=Object(_.a)(dt.progress);Object(v.a)(t,function(){var t=P((function*(t){if(E&&(yield E(t)),k){const e=t.match(/([^:]*).*\\((\\d+?)\\/(\\d+?)\\)/);e&&(yield k({phase:e[1].trim(),loaded:parseInt(e[2],10),total:parseInt(e[3],10)}))}}));return function(e){return t.apply(this,arguments)}}())}const pt=t.from(yield Object(y.a)(dt.packfile));if(lt.body.error)throw lt.body.error;const yt=pt.slice(-20).toString("hex"),gt={defaultBranch:dt.HEAD,fetchHead:dt.FETCH_HEAD.oid,fetchHeadDescription:dt.FETCH_HEAD.description};if(dt.headers&&(gt.headers=dt.headers),q&&(gt.pruned=dt.pruned),""!==yt&&!Object(g.a)(pt)){gt.packfile=`objects/pack/pack-${yt}.pack`;const t=Object(w.join)($,gt.packfile);yield e.write(t,pt);const n=t=>Object(h.a)({fs:e,cache:r,gitdir:$,oid:t}),i=yield l.a.fromPack({pack:pt,getExternalRefDelta:n,onProgress:k});yield e.write(t.replace(/\\.pack$/,".idx"),yield i.toBuffer())}return gt}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){var n=r(10),i=n.Buffer;function o(t,e){for(var r in t)e[r]=t[r]}function a(t,e,r){return i(t,e,r)}i.from&&i.alloc&&i.allocUnsafe&&i.allocUnsafeSlow?t.exports=n:(o(n,e),e.Buffer=a),o(i,a),a.from=function(t,e,r){if("number"==typeof t)throw new TypeError("Argument must not be a number");return i(t,e,r)},a.alloc=function(t,e,r){if("number"!=typeof t)throw new TypeError("Argument must be a number");var n=i(t);return void 0!==e?"string"==typeof r?n.fill(e,r):n.fill(e):n.fill(0),n},a.allocUnsafe=function(t){if("number"!=typeof t)throw new TypeError("Argument must be a number");return i(t)},a.allocUnsafeSlow=function(t){if("number"!=typeof t)throw new TypeError("Argument must be a number");return n.SlowBuffer(t)}},function(t,e,r){"use strict";t.exports=function(t,e,r,n){for(var i=65535&t|0,o=t>>>16&65535|0,a=0;0!==r;){r-=a=r>2e3?2e3:r;do{o=o+(i=i+e[n++]|0)|0}while(--a);i%=65521,o%=65521}return i|o<<16|0}},function(t,e,r){"use strict";var n=function(){for(var t,e=[],r=0;r<256;r++){t=r;for(var n=0;n<8;n++)t=1&t?3988292384^t>>>1:t>>>1;e[r]=t}return e}();t.exports=function(t,e,r,i){var o=n,a=i+r;t^=-1;for(var s=i;s<a;s++)t=t>>>8^o[255&(t^e[s])];return-1^t}},function(t,e,r){"use strict";var n=r(31),i=!0,o=!0;try{String.fromCharCode.apply(null,[0])}catch(t){i=!1}try{String.fromCharCode.apply(null,new Uint8Array(1))}catch(t){o=!1}for(var a=new n.Buf8(256),s=0;s<256;s++)a[s]=s>=252?6:s>=248?5:s>=240?4:s>=224?3:s>=192?2:1;function c(t,e){if(e<65534&&(t.subarray&&o||!t.subarray&&i))return String.fromCharCode.apply(null,n.shrinkBuf(t,e));for(var r="",a=0;a<e;a++)r+=String.fromCharCode(t[a]);return r}a[254]=a[254]=1,e.string2buf=function(t){var e,r,i,o,a,s=t.length,c=0;for(o=0;o<s;o++)55296==(64512&(r=t.charCodeAt(o)))&&o+1<s&&56320==(64512&(i=t.charCodeAt(o+1)))&&(r=65536+(r-55296<<10)+(i-56320),o++),c+=r<128?1:r<2048?2:r<65536?3:4;for(e=new n.Buf8(c),a=0,o=0;a<c;o++)55296==(64512&(r=t.charCodeAt(o)))&&o+1<s&&56320==(64512&(i=t.charCodeAt(o+1)))&&(r=65536+(r-55296<<10)+(i-56320),o++),r<128?e[a++]=r:r<2048?(e[a++]=192|r>>>6,e[a++]=128|63&r):r<65536?(e[a++]=224|r>>>12,e[a++]=128|r>>>6&63,e[a++]=128|63&r):(e[a++]=240|r>>>18,e[a++]=128|r>>>12&63,e[a++]=128|r>>>6&63,e[a++]=128|63&r);return e},e.buf2binstring=function(t){return c(t,t.length)},e.binstring2buf=function(t){for(var e=new n.Buf8(t.length),r=0,i=e.length;r<i;r++)e[r]=t.charCodeAt(r);return e},e.buf2string=function(t,e){var r,n,i,o,s=e||t.length,u=new Array(2*s);for(n=0,r=0;r<s;)if((i=t[r++])<128)u[n++]=i;else if((o=a[i])>4)u[n++]=65533,r+=o-1;else{for(i&=2===o?31:3===o?15:7;o>1&&r<s;)i=i<<6|63&t[r++],o--;o>1?u[n++]=65533:i<65536?u[n++]=i:(i-=65536,u[n++]=55296|i>>10&1023,u[n++]=56320|1023&i)}return c(u,n)},e.utf8border=function(t,e){var r;for((e=e||t.length)>t.length&&(e=t.length),r=e-1;r>=0&&128==(192&t[r]);)r--;return r<0?e:0===r?e:r+a[t[r]]>e?r:e}},function(t,e,r){"use strict";t.exports=function(){this.input=null,this.next_in=0,this.avail_in=0,this.total_in=0,this.output=null,this.next_out=0,this.avail_out=0,this.total_out=0,this.msg="",this.state=null,this.data_type=2,this.adler=0}},function(t,e,r){"use strict";t.exports={Z_NO_FLUSH:0,Z_PARTIAL_FLUSH:1,Z_SYNC_FLUSH:2,Z_FULL_FLUSH:3,Z_FINISH:4,Z_BLOCK:5,Z_TREES:6,Z_OK:0,Z_STREAM_END:1,Z_NEED_DICT:2,Z_ERRNO:-1,Z_STREAM_ERROR:-2,Z_DATA_ERROR:-3,Z_BUF_ERROR:-5,Z_NO_COMPRESSION:0,Z_BEST_SPEED:1,Z_BEST_COMPRESSION:9,Z_DEFAULT_COMPRESSION:-1,Z_FILTERED:1,Z_HUFFMAN_ONLY:2,Z_RLE:3,Z_FIXED:4,Z_DEFAULT_STRATEGY:0,Z_BINARY:0,Z_TEXT:1,Z_UNKNOWN:2,Z_DEFLATED:8}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(9);function i({capabilities:t=[],wants:e=[],haves:r=[],shallows:i=[],depth:o=null,since:a=null,exclude:s=[]}){const c=[];e=[...new Set(e)];let u=` ${t.join(" ")}`;for(const t of e)c.push(n.a.encode(`want ${t}${u}\\n`)),u="";for(const t of i)c.push(n.a.encode(`shallow ${t}\\n`));null!==o&&c.push(n.a.encode(`deepen ${o}\\n`)),null!==a&&c.push(n.a.encode(`deepen-since ${Math.floor(a.valueOf()/1e3)}\\n`));for(const t of s)c.push(n.a.encode(`deepen-not ${t}\\n`));c.push(n.a.flush());for(const t of r)c.push(n.a.encode(`have ${t}\\n`));return c.push(n.a.encode("done\\n")),c}},function(t,e,r){"use strict";r.d(e,"a",(function(){return c}));var n=r(32),i=r(77),o=r(39);function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}function c(t){return u.apply(this,arguments)}function u(){return(u=s((function*(t){const{packetlines:e,packfile:r,progress:a}=i.a.demux(t),s=[],c=[],u=[];let f=!1,l=!1;return new Promise((i,d)=>{Object(o.a)(e,e=>{const o=e.toString("utf8").trim();if(o.startsWith("shallow")){const t=o.slice(-41).trim();40!==t.length&&d(new n.a(t)),s.push(t)}else if(o.startsWith("unshallow")){const t=o.slice(-41).trim();40!==t.length&&d(new n.a(t)),c.push(t)}else if(o.startsWith("ACK")){const[,t,e]=o.split(" ");u.push({oid:t,status:e}),e||(l=!0)}else o.startsWith("NAK")?(f=!0,l=!0):(l=!0,f=!0);l&&(t.error?d(t.error):i({shallows:s,unshallows:c,acks:u,nak:f,packfile:r,progress:a}))}).finally(()=>{l||(t.error?d(t.error):i({shallows:s,unshallows:c,acks:u,nak:f,packfile:r,progress:a}))})})}))).apply(this,arguments)}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return y}));var n=r(22),i=r(30),o=r(57),a=r(56),s=r(12),c=r(15),u=r(40),f=r(16),l=r(111),d=r(53);function h(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function p(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){h(o,n,i,a,s,"next",t)}function s(t){h(o,n,i,a,s,"throw",t)}a(void 0)}))}}function y(t){return g.apply(this,arguments)}function g(){return(g=p((function*({fs:t,cache:e,dir:r,gitdir:l=Object(f.join)(r,".git"),index:h,ourOid:y,baseOid:g,theirOid:v,ourName:w="ours",baseName:b="base",theirName:_="theirs",dryRun:j=!1,abortOnConflict:O=!0,mergeDriver:x}){const P=Object(n.a)({ref:y}),k=Object(n.a)({ref:g}),E=Object(n.a)({ref:v}),S=[],A=[],R=[],$=[],B=yield Object(i.a)({fs:t,cache:e,dir:r,gitdir:l,trees:[P,k,E],map:(T=p((function*(e,[r,n,i]){const o=Object(u.a)(e);switch(`${yield Object(d.a)(r,n)}-${yield Object(d.a)(i,n)}`){case"false-false":return{mode:yield n.mode(),path:o,oid:yield n.oid(),type:yield n.type()};case"false-true":return i?{mode:yield i.mode(),path:o,oid:yield i.oid(),type:yield i.type()}:void 0;case"true-false":return r?{mode:yield r.mode(),path:o,oid:yield r.oid(),type:yield r.type()}:void 0;case"true-true":if(r&&n&&i&&"blob"===(yield r.type())&&"blob"===(yield n.type())&&"blob"===(yield i.type()))return m({fs:t,gitdir:l,path:o,ours:r,base:n,theirs:i,ourName:w,baseName:b,theirName:_,mergeDriver:x}).then(function(){var t=p((function*(t){if(t.cleanMerge)O||h.insert({filepath:e,oid:t.mergeResult.oid,stage:0});else if(S.push(e),A.push(e),!O){const t=yield n.oid(),o=yield r.oid(),a=yield i.oid();h.delete({filepath:e}),h.insert({filepath:e,oid:t,stage:1}),h.insert({filepath:e,oid:o,stage:2}),h.insert({filepath:e,oid:a,stage:3})}return t.mergeResult}));return function(e){return t.apply(this,arguments)}}());if(n&&!r&&i&&"blob"===(yield n.type())&&"blob"===(yield i.type())){if(S.push(e),R.push(e),!O){const t=yield n.oid(),r=yield i.oid();h.delete({filepath:e}),h.insert({filepath:e,oid:t,stage:1}),h.insert({filepath:e,oid:r,stage:3})}return{mode:yield i.mode(),oid:yield i.oid(),type:"blob",path:o}}if(n&&r&&!i&&"blob"===(yield n.type())&&"blob"===(yield r.type())){if(S.push(e),$.push(e),!O){const t=yield n.oid(),i=yield r.oid();h.delete({filepath:e}),h.insert({filepath:e,oid:t,stage:1}),h.insert({filepath:e,oid:i,stage:2})}return{mode:yield r.mode(),oid:yield r.oid(),type:"blob",path:o}}if(n&&!r&&!i&&"blob"===(yield n.type()))return;throw new a.a}})),function(t,e){return T.apply(this,arguments)}),reduce:0===S.length||r&&!O?function(){var e=p((function*(e,r){const n=r.filter(Boolean);if(e&&(!e||"tree"!==e.type||0!==n.length)){if(n.length>0){const r=new s.a(n).toObject(),i=yield Object(c.a)({fs:t,gitdir:l,type:"tree",object:r,dryRun:j});e.oid=i}return e}}));return function(t,r){return e.apply(this,arguments)}}():void 0});var T,I;return 0!==S.length?(r&&!O&&(yield Object(i.a)({fs:t,cache:e,dir:r,gitdir:l,trees:[Object(n.a)({ref:B.oid})],map:(I=p((function*(e,[n]){const i=`${r}/${e}`;if("blob"===(yield n.type())){const e=yield n.mode(),r=(new TextDecoder).decode(yield n.content());yield t.write(i,r,{mode:e})}return!0})),function(t,e){return I.apply(this,arguments)})})),new o.a(S,A,R,$)):B.oid}))).apply(this,arguments)}function m(t){return v.apply(this,arguments)}function v(){return(v=p((function*({fs:e,gitdir:r,path:n,ours:i,base:o,theirs:a,ourName:s,theirName:u,baseName:f,dryRun:d,mergeDriver:h=l.a}){const p=(yield o.mode())===(yield i.mode())?yield a.mode():yield i.mode();if((yield i.oid())===(yield a.oid()))return{cleanMerge:!0,mergeResult:{mode:p,path:n,oid:yield i.oid(),type:"blob"}};if((yield i.oid())===(yield o.oid()))return{cleanMerge:!0,mergeResult:{mode:p,path:n,oid:yield a.oid(),type:"blob"}};if((yield a.oid())===(yield o.oid()))return{cleanMerge:!0,mergeResult:{mode:p,path:n,oid:yield i.oid(),type:"blob"}};const y=t.from(yield i.content()).toString("utf8"),g=t.from(yield o.content()).toString("utf8"),m=t.from(yield a.content()).toString("utf8"),{mergedText:v,cleanMerge:w}=yield h({branches:[f,s,u],contents:[g,y,m],path:n});return{cleanMerge:w,mergeResult:{mode:p,path:n,oid:yield Object(c.a)({fs:e,gitdir:r,type:"blob",object:t.from(v,"utf8"),dryRun:d}),type:"blob"}}}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.d(e,"a",(function(){return d}));var n=r(17),i=r(3),o=r(44),a=r(18),s=r(14),c=r(7),u=r(16);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:t,cache:e,dir:r,gitdir:f=Object(u.join)(r,".git"),start:d,finish:h}){const p=yield o.a.read({fs:t,gitdir:f}),y=new Set,g=new Set;for(const e of d)y.add(yield i.a.resolve({fs:t,gitdir:f,ref:e}));for(const e of h)try{const r=yield i.a.resolve({fs:t,gitdir:f,ref:e});g.add(r)}catch(t){}const m=new Set;function v(t){return w.apply(this,arguments)}function w(){return(w=l((function*(r){m.add(r);const{type:i,object:o}=yield Object(c.a)({fs:t,cache:e,gitdir:f,oid:r});if("tag"===i){return v(a.a.from(o).headers().object)}if("commit"!==i)throw new n.a(r,i,"commit");if(!p.has(r)){const t=s.a.from(o).headers().parent;for(r of t)g.has(r)||m.has(r)||(yield v(r))}}))).apply(this,arguments)}for(const t of y)yield v(t);return m}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(9);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t){return s.apply(this,arguments)}function s(){return(s=o((function*({capabilities:t=[],triplets:e=[]}){const r=[];let i=`\\0 ${t.join(" ")}`;for(const t of e)r.push(n.a.encode(`${t.oldoid} ${t.oid} ${t.fullRef}${i}\\n`)),i="";return r.push(n.a.flush()),r}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(36),i=r(9);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*(t){const e={};let r="";const o=i.a.streamReader(t);let a=yield o();for(;!0!==a;)null!==a&&(r+=a.toString("utf8")+"\\n"),a=yield o();const s=r.toString("utf8").split("\\n");if(a=s.shift(),!a.startsWith("unpack "))throw new n.a('unpack ok" or "unpack [error message]',a);e.ok="unpack ok"===a,e.ok||(e.error=a.slice("unpack ".length)),e.refs={};for(const t of s){if(""===t.trim())continue;const r=t.slice(0,2),n=t.slice(3);let i=n.indexOf(" ");-1===i&&(i=n.length);const o=n.slice(0,i),a=n.slice(i+1);e.refs[o]={ok:"ok"===r,error:a}}return e}))).apply(this,arguments)}},function(t,e,r){"use strict";r.d(e,"a",(function(){return i}));var n=r(38);function i(t,e){return Object(n.a)(o(t),o(e))}function o(t){return"040000"===t.mode?t.path+"/":t.path}},function(t,e,r){var n;n=function(t){t.version="1.2.0";var e=function(){for(var t=0,e=new Array(256),r=0;256!=r;++r)t=1&(t=1&(t=1&(t=1&(t=1&(t=1&(t=1&(t=1&(t=r)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1)?-306674912^t>>>1:t>>>1,e[r]=t;return"undefined"!=typeof Int32Array?new Int32Array(e):e}();t.table=e,t.bstr=function(t,r){for(var n=-1^r,i=t.length-1,o=0;o<i;)n=(n=n>>>8^e[255&(n^t.charCodeAt(o++))])>>>8^e[255&(n^t.charCodeAt(o++))];return o===i&&(n=n>>>8^e[255&(n^t.charCodeAt(o))]),-1^n},t.buf=function(t,r){if(t.length>1e4)return function(t,r){for(var n=-1^r,i=t.length-7,o=0;o<i;)n=(n=(n=(n=(n=(n=(n=(n=n>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])];for(;o<i+7;)n=n>>>8^e[255&(n^t[o++])];return-1^n}(t,r);for(var n=-1^r,i=t.length-3,o=0;o<i;)n=(n=(n=(n=n>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])])>>>8^e[255&(n^t[o++])];for(;o<i+3;)n=n>>>8^e[255&(n^t[o++])];return-1^n},t.str=function(t,r){for(var n,i,o=-1^r,a=0,s=t.length;a<s;)(n=t.charCodeAt(a++))<128?o=o>>>8^e[255&(o^n)]:n<2048?o=(o=o>>>8^e[255&(o^(192|n>>6&31))])>>>8^e[255&(o^(128|63&n))]:n>=55296&&n<57344?(n=64+(1023&n),i=1023&t.charCodeAt(a++),o=(o=(o=(o=o>>>8^e[255&(o^(240|n>>8&7))])>>>8^e[255&(o^(128|n>>2&63))])>>>8^e[255&(o^(128|i>>6&15|(3&n)<<4))])>>>8^e[255&(o^(128|63&i))]):o=(o=(o=o>>>8^e[255&(o^(224|n>>12&15))])>>>8^e[255&(o^(128|n>>6&63))])>>>8^e[255&(o^(128|63&n))];return-1^o}},"undefined"==typeof DO_NOT_EXPORT_CRC?n(e):n({})},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return u}));var n=r(49),i=r.n(n),o=r(4),a=r(82);function s(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function c(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){s(o,n,i,a,c,"next",t)}function c(t){s(o,n,i,a,c,"throw",t)}a(void 0)}))}}function u(t,e){return f.apply(this,arguments)}function f(){return(f=c((function*(t,e){const r=new a.a(t);let n=yield r.read(4);if(n=n.toString("utf8"),"PACK"!==n)throw new o.a(`Invalid PACK header '${n}'`);let s=yield r.read(4);if(s=s.readUInt32BE(0),2!==s)throw new o.a(`Invalid packfile version: ${s}`);let c=yield r.read(4);if(c=c.readUInt32BE(0),!(c<1))for(;!r.eof()&&c--;){const t=r.tell(),{type:n,length:a,ofs:s,reference:u}=yield l(r),f=new i.a.Inflate;for(;!f.result;){const i=yield r.chunk();if(!i)break;if(f.push(i,!1),f.err)throw new o.a(`Pako error: ${f.msg}`);if(f.result){if(f.result.length!==a)throw new o.a("Inflated object size is different from that stated in packfile.");yield r.undo(),yield r.read(i.length-f.strm.avail_in);const l=r.tell();yield e({data:f.result,type:n,num:c,offset:t,end:l,reference:u,ofs:s})}}}}))).apply(this,arguments)}function l(t){return d.apply(this,arguments)}function d(){return(d=c((function*(e){let r=yield e.byte();const n=r>>4&7;let i,o,a=15&r;if(128&r){let t=4;do{r=yield e.byte(),a|=(127&r)<<t,t+=7}while(128&r)}if(6===n){let n=0;i=0;const a=[];do{r=yield e.byte(),i|=(127&r)<<n,n+=7,a.push(r)}while(128&r);o=t.from(a)}if(7===n){o=yield e.read(20)}return{type:n,length:a,ofs:i,reference:o}}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return o}));var n=r(4),i=r(20);function o(e,r){const o=new i.a(e),s=a(o);if(s!==r.byteLength)throw new n.a(`applyDelta expected source buffer to be ${s} bytes but the provided buffer was ${r.length} bytes`);const u=a(o);let f;const l=c(o,r);if(l.byteLength===u)f=l;else{f=t.alloc(u);const e=new i.a(f);for(e.copy(l);!o.eof();)e.copy(c(o,r));const a=e.tell();if(u!==a)throw new n.a(`applyDelta expected target buffer to be ${u} bytes but the resulting buffer was ${a} bytes`)}return f}function a(t){let e=0,r=0,n=null;do{n=t.readUInt8(),e|=(127&n)<<r,r+=7}while(128&n);return e}function s(t,e,r){let n=0,i=0;for(;r--;)1&e&&(n|=t.readUInt8()<<i),e>>=1,i+=8;return n}function c(t,e){const r=t.readUInt8();if(128&r){const n=s(t,15&r,4);let i=s(t,(112&r)>>4,3);return 0===i&&(i=65536),e.slice(n,n+i)}return t.slice(r)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";function n(t){return t.split("\\n").map(t=>t.replace(/^ /,"")).join("\\n")}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";function n(t){return function(t){return t&&"object"==typeof t}(t)&&i(t.then)&&i(t.catch)}function i(t){return"function"==typeof t}r.d(e,"a",(function(){return n}))},function(t,e,r){(function(e){function r(t){return Array.isArray(t)?t:[t]}const n=/^\\s+$/,i=/^\\\\!/,o=/^\\\\#/,a=/\\r?\\n/g,s=/^\\.*\\/|^\\.+$/,c="undefined"!=typeof Symbol?Symbol.for("node-ignore"):"node-ignore",u=/([0-z])-([0-z])/g,f=()=>!1,l=[[/\\\\?\\s+$/,t=>0===t.indexOf("\\\\")?" ":""],[/\\\\\\s/g,()=>" "],[/[\\\\$.|*+(){^]/g,t=>`\\\\${t}`],[/(?!\\\\)\\?/g,()=>"[^/]"],[/^\\//,()=>"^"],[/\\//g,()=>"\\\\/"],[/^\\^*\\\\\\*\\\\\\*\\\\\\//,()=>"^(?:.*\\\\/)?"],[/^(?=[^^])/,function(){return/\\/(?!$)/.test(this)?"^":"(?:^|\\\\/)"}],[/\\\\\\/\\\\\\*\\\\\\*(?=\\\\\\/|$)/g,(t,e,r)=>e+6<r.length?"(?:\\\\/[^\\\\/]+)*":"\\\\/.+"],[/(^|[^\\\\]+)\\\\\\*(?=.+)/g,(t,e)=>`${e}[^\\\\/]*`],[/\\\\\\\\\\\\(?=[$.|*+(){^])/g,()=>"\\\\"],[/\\\\\\\\/g,()=>"\\\\"],[/(\\\\)?\\[([^\\]/]*?)(\\\\*)($|\\])/g,(t,e,r,n,i)=>"\\\\"===e?`\\\\[${r}${(t=>{const{length:e}=t;return t.slice(0,e-e%2)})(n)}${i}`:"]"===i&&n.length%2==0?`[${(t=>t.replace(u,(t,e,r)=>e.charCodeAt(0)<=r.charCodeAt(0)?t:""))(r)}${n}]`:"[]"],[/(?:[^*])$/,t=>/\\/$/.test(t)?`${t}$`:`${t}(?=$|\\\\/$)`],[/(\\^|\\\\\\/)?\\\\\\*$/,(t,e)=>`${e?`${e}[^/]+`:"[^/]*"}(?=$|\\\\/$)`]],d=Object.create(null),h=t=>"string"==typeof t;class p{constructor(t,e,r,n){this.origin=t,this.pattern=e,this.negative=r,this.regex=n}}const y=(t,e)=>{const r=t;let n=!1;0===t.indexOf("!")&&(n=!0,t=t.substr(1));const a=((t,e)=>{let r=d[t];return r||(r=l.reduce((e,r)=>e.replace(r[0],r[1].bind(t)),t),d[t]=r),e?new RegExp(r,"i"):new RegExp(r)})(t=t.replace(i,"!").replace(o,"#"),e);return new p(r,t,n,a)},g=(t,e)=>{throw new e(t)},m=(t,e,r)=>{if(!h(t))return r(`path must be a string, but got \\`${e}\\``,TypeError);if(!t)return r("path must not be empty",TypeError);if(m.isNotRelative(t)){return r(`path should be a ${"`path.relative()`d"} string, but got "${e}"`,RangeError)}return!0},v=t=>s.test(t);m.isNotRelative=v,m.convert=t=>t;class w{constructor({ignorecase:t=!0,ignoreCase:e=t,allowRelativePaths:r=!1}={}){var n,i,o;n=this,i=c,o=!0,Object.defineProperty(n,i,{value:o}),this._rules=[],this._ignoreCase=e,this._allowRelativePaths=r,this._initCache()}_initCache(){this._ignoreCache=Object.create(null),this._testCache=Object.create(null)}_addPattern(t){if(t&&t[c])return this._rules=this._rules.concat(t._rules),void(this._added=!0);if((t=>t&&h(t)&&!n.test(t)&&0!==t.indexOf("#"))(t)){const e=y(t,this._ignoreCase);this._added=!0,this._rules.push(e)}}add(t){return this._added=!1,r(h(t)?(t=>t.split(a))(t):t).forEach(this._addPattern,this),this._added&&this._initCache(),this}addPattern(t){return this.add(t)}_testOne(t,e){let r=!1,n=!1;return this._rules.forEach(i=>{const{negative:o}=i;n===o&&r!==n||o&&!r&&!n&&!e||i.regex.test(t)&&(r=!o,n=o)}),{ignored:r,unignored:n}}_test(t,e,r,n){const i=t&&m.convert(t);return m(i,t,this._allowRelativePaths?f:g),this._t(i,e,r,n)}_t(t,e,r,n){if(t in e)return e[t];if(n||(n=t.split("/")),n.pop(),!n.length)return e[t]=this._testOne(t,r);const i=this._t(n.join("/")+"/",e,r,n);return e[t]=i.ignored?i:this._testOne(t,r)}ignores(t){return this._test(t,this._ignoreCache,!1).ignored}createFilter(){return t=>!this.ignores(t)}filter(t){return r(t).filter(this.createFilter())}test(t){return this._test(t,this._testCache,!0)}}const b=t=>new w(t);if(b.isPathValid=t=>m(t&&m.convert(t),t,f),b.default=b,t.exports=b,void 0!==e&&(e.env&&e.env.IGNORE_TEST_WIN32||"win32"===e.platform)){const t=t=>/^\\\\\\\\\\?\\\\/.test(t)||/["<>|\\u0000-\\u001F]+/u.test(t)?t:t.replace(/\\\\/g,"/");m.convert=t;const e=/^[a-z]:\\//i;m.isNotRelative=t=>e.test(t)||v(t)}}).call(this,r(92))},function(t,e,r){"use strict";r.d(e,"a",(function(){return a}));var n=r(4);function i(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function o(t){return function(){var e=this,r=arguments;return new Promise((function(n,o){var a=t.apply(e,r);function s(t){i(a,n,o,s,c,"next",t)}function c(t){i(a,n,o,s,c,"throw",t)}s(void 0)}))}}function a(t){return s.apply(this,arguments)}function s(){return(s=o((function*({fs:t,gitdir:e,object:r,format:i,oid:o}){if("deflated"!==i)throw new n.a("GitObjectStoreLoose expects objects to write to be in deflated format");const a=`${e}/${`objects/${o.slice(0,2)}/${o.slice(2)}`}`;(yield t.exists(a))||(yield t.write(a,r))}))).apply(this,arguments)}},function(t,e,r){var n=r(158);function i(t,e){for(var r=[],i=t.length,o=e.length,a=function(t,e){var r=new n(t,e);r.compose();for(var i,o,a=r.getses(),s=t.length-1,c=e.length-1,u=a.length-1;u>=0;--u)a[u].t===r.SES_COMMON?(o?(o.chain={file1index:s,file2index:c,chain:null},o=o.chain):o=i={file1index:s,file2index:c,chain:null},s--,c--):a[u].t===r.SES_DELETE?s--:a[u].t===r.SES_ADD&&c--;var f={file1index:-1,file2index:-1,chain:null};return o?(o.chain=f,i):f}(t,e);null!==a;a=a.chain){var s=i-a.file1index-1,c=o-a.file2index-1;i=a.file1index,o=a.file2index,(s||c)&&r.push({file1:[i+1,s],file2:[o+1,c]})}return r.reverse(),r}t.exports=function(t,e,r){var n=[],o=[t,e,r],a=function(t,e,r){var n,o=i(e,t),a=i(e,r),s=[];function c(t,e){s.push([t.file1[0],e,t.file1[1],t.file2[0],t.file2[1]])}for(n=0;n<o.length;n++)c(o[n],0);for(n=0;n<a.length;n++)c(a[n],2);s.sort((function(t,e){return t[0]-e[0]}));var u=[],f=0;function l(t){t>f&&(u.push([1,f,t-f]),f=t)}for(var d=0;d<s.length;d++){for(var h=d,p=s[d],y=p[0],g=y+p[2];d<s.length-1;){var m=s[d+1],v=m[0];if(v>g)break;g=Math.max(g,v+m[2]),d++}if(l(y),h==d)p[4]>0&&u.push([p[1],p[3],p[4]]);else{var w={0:[t.length,-1,e.length,-1],2:[r.length,-1,e.length,-1]};for(n=h;n<=d;n++){var b=w[(p=s[n])[1]],_=p[0],j=_+p[2],O=p[3],x=O+p[4];b[0]=Math.min(O,b[0]),b[1]=Math.max(x,b[1]),b[2]=Math.min(_,b[2]),b[3]=Math.max(j,b[3])}var P=w[0][0]+(y-w[0][2]),k=w[0][1]+(g-w[0][3]),E=w[2][0]+(y-w[2][2]),S=w[2][1]+(g-w[2][3]);u.push([-1,P,k-P,y,g-y,E,S-E])}f=g}return l(e.length),u}(t,e,r),s=[];function c(){s.length&&n.push({ok:s}),s=[]}function u(t){for(var e=0;e<t.length;e++)s.push(t[e])}function f(e){if(e[2]!=e[6])return!0;for(var n=e[1],i=e[5],o=0;o<e[2];o++)if(t[o+n]!=r[o+i])return!0;return!1}for(var l=0;l<a.length;l++){var d=a[l],h=d[0];-1==h?f(d)?(c(),n.push({conflict:{a:t.slice(d[1],d[1]+d[2]),aIndex:d[1],o:e.slice(d[3],d[3]+d[4]),oIndex:d[3],b:r.slice(d[5],d[5]+d[6]),bIndex:d[5]}})):u(o[0].slice(d[1],d[1]+d[2])):u(o[h].slice(d[1],d[1]+d[2]))}return c(),n}},function(t,e,r){"use strict";r.d(e,"a",(function(){return n}));const n={commit:16,tree:32,blob:48,tag:64,ofs_delta:96,ref_delta:112}},function(t,e,r){"use strict";function n(t,e){const r=t.map(t=>t.split("=",1)[0]);return e.filter(t=>{const e=t.split("=",1)[0];return r.includes(e)})}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(67),i=r(39);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){const e=t.indexOf("\\r"),r=t.indexOf("\\n");return-1===e&&-1===r?-1:-1===e?r+1:-1===r?e+1:r===e+1?r+1:Math.min(e,r)+1}function s(t){const e=new n.a;let r="";var s;return(s=function*(){yield Object(i.a)(t,t=>{for(t=t.toString("utf8"),r+=t;;){const t=a(r);if(-1===t)break;e.write(r.slice(0,t)),r=r.slice(t)}}),r.length>0&&e.write(r),e.end()},function(){var t=this,e=arguments;return new Promise((function(r,n){var i=s.apply(t,e);function a(t){o(i,r,n,a,c,"next",t)}function c(t){o(i,r,n,a,c,"throw",t)}a(void 0)}))})(),e}},function(t,e,r){"use strict";(function(e){var r=function(t){if(t=t||{},this.Promise=t.Promise||Promise,this.queues=Object.create(null),this.domainReentrant=t.domainReentrant||!1,this.domainReentrant){if(void 0===e||void 0===e.domain)throw new Error("Domain-reentrant locks require `process.domain` to exist. Please flip `opts.domainReentrant = false`, use a NodeJS version that still implements Domain, or install a browser polyfill.");this.domains=Object.create(null)}this.timeout=t.timeout||r.DEFAULT_TIMEOUT,this.maxOccupationTime=t.maxOccupationTime||r.DEFAULT_MAX_OCCUPATION_TIME,this.maxExecutionTime=t.maxExecutionTime||r.DEFAULT_MAX_EXECUTION_TIME,t.maxPending===1/0||Number.isInteger(t.maxPending)&&t.maxPending>=0?this.maxPending=t.maxPending:this.maxPending=r.DEFAULT_MAX_PENDING};r.DEFAULT_TIMEOUT=0,r.DEFAULT_MAX_OCCUPATION_TIME=0,r.DEFAULT_MAX_EXECUTION_TIME=0,r.DEFAULT_MAX_PENDING=1e3,r.prototype.acquire=function(t,r,n,i){if(Array.isArray(t))return this._acquireBatch(t,r,n,i);if("function"!=typeof r)throw new Error("You must pass a function to execute");var o=null,a=null,s=null;"function"!=typeof n&&(i=n,n=null,s=new this.Promise((function(t,e){o=t,a=e}))),i=i||{};var c=!1,u=null,f=null,l=null,d=this,h=function(e,r,i){f&&(clearTimeout(f),f=null),l&&(clearTimeout(l),l=null),e&&(d.queues[t]&&0===d.queues[t].length&&delete d.queues[t],d.domainReentrant&&delete d.domains[t]),c||(s?r?a(r):o(i):"function"==typeof n&&n(r,i),c=!0),e&&d.queues[t]&&d.queues[t].length>0&&d.queues[t].shift()()},p=function(n){if(c)return h(n);u&&(clearTimeout(u),u=null),d.domainReentrant&&n&&(d.domains[t]=e.domain);var o=i.maxExecutionTime||d.maxExecutionTime;if(o&&(l=setTimeout((function(){d.queues[t]&&h(n,new Error("Maximum execution time is exceeded "+t))}),o)),1===r.length){var a=!1;try{r((function(t,e){a||(a=!0,h(n,t,e))}))}catch(t){a||(a=!0,h(n,t))}}else d._promiseTry((function(){return r()})).then((function(t){h(n,void 0,t)}),(function(t){h(n,t)}))};d.domainReentrant&&e.domain&&(p=e.domain.bind(p));var y=i.maxPending||d.maxPending;if(d.queues[t])if(d.domainReentrant&&e.domain&&e.domain===d.domains[t])p(!1);else if(d.queues[t].length>=y)h(!1,new Error("Too many pending tasks in queue "+t));else{var g=function(){p(!0)};i.skipQueue?d.queues[t].unshift(g):d.queues[t].push(g);var m=i.timeout||d.timeout;m&&(u=setTimeout((function(){u=null,h(!1,new Error("async-lock timed out in queue "+t))}),m))}else d.queues[t]=[],p(!0);var v=i.maxOccupationTime||d.maxOccupationTime;return v&&(f=setTimeout((function(){d.queues[t]&&h(!1,new Error("Maximum occupation time is exceeded in queue "+t))}),v)),s||void 0},r.prototype._acquireBatch=function(t,e,r,n){"function"!=typeof r&&(n=r,r=null);var i=this,o=t.reduceRight((function(t,e){return function(t,e){return function(r){i.acquire(t,e,r,n)}}(e,t)}),e);if("function"!=typeof r)return new this.Promise((function(t,e){1===o.length?o((function(r,n){r?e(r):t(n)})):t(o())}));o(r)},r.prototype.isBusy=function(t){return t?!!this.queues[t]:Object.keys(this.queues).length>0},r.prototype._promiseTry=function(t){try{return this.Promise.resolve(t())}catch(t){return this.Promise.reject(t)}},t.exports=r}).call(this,r(92))},function(t,e){var r;r=function(){return this}();try{r=r||new Function("return this")()}catch(t){"object"==typeof window&&(r=window)}t.exports=r},function(t,e,r){"use strict";e.byteLength=function(t){var e=u(t),r=e[0],n=e[1];return 3*(r+n)/4-n},e.toByteArray=function(t){var e,r,n=u(t),a=n[0],s=n[1],c=new o(function(t,e,r){return 3*(e+r)/4-r}(0,a,s)),f=0,l=s>0?a-4:a;for(r=0;r<l;r+=4)e=i[t.charCodeAt(r)]<<18|i[t.charCodeAt(r+1)]<<12|i[t.charCodeAt(r+2)]<<6|i[t.charCodeAt(r+3)],c[f++]=e>>16&255,c[f++]=e>>8&255,c[f++]=255&e;2===s&&(e=i[t.charCodeAt(r)]<<2|i[t.charCodeAt(r+1)]>>4,c[f++]=255&e);1===s&&(e=i[t.charCodeAt(r)]<<10|i[t.charCodeAt(r+1)]<<4|i[t.charCodeAt(r+2)]>>2,c[f++]=e>>8&255,c[f++]=255&e);return c},e.fromByteArray=function(t){for(var e,r=t.length,i=r%3,o=[],a=0,s=r-i;a<s;a+=16383)o.push(f(t,a,a+16383>s?s:a+16383));1===i?(e=t[r-1],o.push(n[e>>2]+n[e<<4&63]+"==")):2===i&&(e=(t[r-2]<<8)+t[r-1],o.push(n[e>>10]+n[e>>4&63]+n[e<<2&63]+"="));return o.join("")};for(var n=[],i=[],o="undefined"!=typeof Uint8Array?Uint8Array:Array,a="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",s=0,c=a.length;s<c;++s)n[s]=a[s],i[a.charCodeAt(s)]=s;function u(t){var e=t.length;if(e%4>0)throw new Error("Invalid string. Length must be a multiple of 4");var r=t.indexOf("=");return-1===r&&(r=e),[r,r===e?0:4-r%4]}function f(t,e,r){for(var i,o,a=[],s=e;s<r;s+=3)i=(t[s]<<16&16711680)+(t[s+1]<<8&65280)+(255&t[s+2]),a.push(n[(o=i)>>18&63]+n[o>>12&63]+n[o>>6&63]+n[63&o]);return a.join("")}i["-".charCodeAt(0)]=62,i["_".charCodeAt(0)]=63},function(t,e){e.read=function(t,e,r,n,i){var o,a,s=8*i-n-1,c=(1<<s)-1,u=c>>1,f=-7,l=r?i-1:0,d=r?-1:1,h=t[e+l];for(l+=d,o=h&(1<<-f)-1,h>>=-f,f+=s;f>0;o=256*o+t[e+l],l+=d,f-=8);for(a=o&(1<<-f)-1,o>>=-f,f+=n;f>0;a=256*a+t[e+l],l+=d,f-=8);if(0===o)o=1-u;else{if(o===c)return a?NaN:1/0*(h?-1:1);a+=Math.pow(2,n),o-=u}return(h?-1:1)*a*Math.pow(2,o-n)},e.write=function(t,e,r,n,i,o){var a,s,c,u=8*o-i-1,f=(1<<u)-1,l=f>>1,d=23===i?Math.pow(2,-24)-Math.pow(2,-77):0,h=n?0:o-1,p=n?1:-1,y=e<0||0===e&&1/e<0?1:0;for(e=Math.abs(e),isNaN(e)||e===1/0?(s=isNaN(e)?1:0,a=f):(a=Math.floor(Math.log(e)/Math.LN2),e*(c=Math.pow(2,-a))<1&&(a--,c*=2),(e+=a+l>=1?d/c:d*Math.pow(2,1-l))*c>=2&&(a++,c/=2),a+l>=f?(s=0,a=f):a+l>=1?(s=(e*c-1)*Math.pow(2,i),a+=l):(s=e*Math.pow(2,l-1)*Math.pow(2,i),a=0));i>=8;t[r+h]=255&s,h+=p,s/=256,i-=8);for(a=a<<i|s,u+=i;u>0;t[r+h]=255&a,h+=p,a/=256,u-=8);t[r+h-p]|=128*y}},function(t,e){var r={}.toString;t.exports=Array.isArray||function(t){return"[object Array]"==r.call(t)}},function(t,e){"function"==typeof Object.create?t.exports=function(t,e){t.super_=e,t.prototype=Object.create(e.prototype,{constructor:{value:t,enumerable:!1,writable:!0,configurable:!0}})}:t.exports=function(t,e){t.super_=e;var r=function(){};r.prototype=e.prototype,t.prototype=new r,t.prototype.constructor=t}},function(t,e,r){var n=r(119).Buffer;function i(t,e){this._block=n.alloc(t),this._finalSize=e,this._blockSize=t,this._len=0}i.prototype.update=function(t,e){"string"==typeof t&&(e=e||"utf8",t=n.from(t,e));for(var r=this._block,i=this._blockSize,o=t.length,a=this._len,s=0;s<o;){for(var c=a%i,u=Math.min(o-s,i-c),f=0;f<u;f++)r[c+f]=t[s+f];s+=u,(a+=u)%i==0&&this._update(r)}return this._len+=o,this},i.prototype.digest=function(t){var e=this._len%this._blockSize;this._block[e]=128,this._block.fill(0,e+1),e>=this._finalSize&&(this._update(this._block),this._block.fill(0));var r=8*this._len;if(r<=4294967295)this._block.writeUInt32BE(r,this._blockSize-4);else{var n=(4294967295&r)>>>0,i=(r-n)/4294967296;this._block.writeUInt32BE(i,this._blockSize-8),this._block.writeUInt32BE(n,this._blockSize-4)}this._update(this._block);var o=this._hash();return t?o.toString(t):o},i.prototype._update=function(){throw new Error("_update must be implemented by subclass")},t.exports=i},function(t,e,r){"use strict";var n=r(151),i=r(31),o=r(122),a=r(96),s=r(123),c=Object.prototype.toString;function u(t){if(!(this instanceof u))return new u(t);this.options=i.assign({level:-1,method:8,chunkSize:16384,windowBits:15,memLevel:8,strategy:0,to:""},t||{});var e=this.options;e.raw&&e.windowBits>0?e.windowBits=-e.windowBits:e.gzip&&e.windowBits>0&&e.windowBits<16&&(e.windowBits+=16),this.err=0,this.msg="",this.ended=!1,this.chunks=[],this.strm=new s,this.strm.avail_out=0;var r=n.deflateInit2(this.strm,e.level,e.method,e.windowBits,e.memLevel,e.strategy);if(0!==r)throw new Error(a[r]);if(e.header&&n.deflateSetHeader(this.strm,e.header),e.dictionary){var f;if(f="string"==typeof e.dictionary?o.string2buf(e.dictionary):"[object ArrayBuffer]"===c.call(e.dictionary)?new Uint8Array(e.dictionary):e.dictionary,0!==(r=n.deflateSetDictionary(this.strm,f)))throw new Error(a[r]);this._dict_set=!0}}function f(t,e){var r=new u(e);if(r.push(t,!0),r.err)throw r.msg||a[r.err];return r.result}u.prototype.push=function(t,e){var r,a,s=this.strm,u=this.options.chunkSize;if(this.ended)return!1;a=e===~~e?e:!0===e?4:0,"string"==typeof t?s.input=o.string2buf(t):"[object ArrayBuffer]"===c.call(t)?s.input=new Uint8Array(t):s.input=t,s.next_in=0,s.avail_in=s.input.length;do{if(0===s.avail_out&&(s.output=new i.Buf8(u),s.next_out=0,s.avail_out=u),1!==(r=n.deflate(s,a))&&0!==r)return this.onEnd(r),this.ended=!0,!1;0!==s.avail_out&&(0!==s.avail_in||4!==a&&2!==a)||("string"===this.options.to?this.onData(o.buf2binstring(i.shrinkBuf(s.output,s.next_out))):this.onData(i.shrinkBuf(s.output,s.next_out)))}while((s.avail_in>0||0===s.avail_out)&&1!==r);return 4===a?(r=n.deflateEnd(this.strm),this.onEnd(r),this.ended=!0,0===r):2!==a||(this.onEnd(0),s.avail_out=0,!0)},u.prototype.onData=function(t){this.chunks.push(t)},u.prototype.onEnd=function(t){0===t&&("string"===this.options.to?this.result=this.chunks.join(""):this.result=i.flattenChunks(this.chunks)),this.chunks=[],this.err=t,this.msg=this.strm.msg},e.Deflate=u,e.deflate=f,e.deflateRaw=function(t,e){return(e=e||{}).raw=!0,f(t,e)},e.gzip=function(t,e){return(e=e||{}).gzip=!0,f(t,e)}},function(t,e,r){"use strict";var n,i=r(31),o=r(152),a=r(120),s=r(121),c=r(96);function u(t,e){return t.msg=c[e],e}function f(t){return(t<<1)-(t>4?9:0)}function l(t){for(var e=t.length;--e>=0;)t[e]=0}function d(t){var e=t.state,r=e.pending;r>t.avail_out&&(r=t.avail_out),0!==r&&(i.arraySet(t.output,e.pending_buf,e.pending_out,r,t.next_out),t.next_out+=r,e.pending_out+=r,t.total_out+=r,t.avail_out-=r,e.pending-=r,0===e.pending&&(e.pending_out=0))}function h(t,e){o._tr_flush_block(t,t.block_start>=0?t.block_start:-1,t.strstart-t.block_start,e),t.block_start=t.strstart,d(t.strm)}function p(t,e){t.pending_buf[t.pending++]=e}function y(t,e){t.pending_buf[t.pending++]=e>>>8&255,t.pending_buf[t.pending++]=255&e}function g(t,e){var r,n,i=t.max_chain_length,o=t.strstart,a=t.prev_length,s=t.nice_match,c=t.strstart>t.w_size-262?t.strstart-(t.w_size-262):0,u=t.window,f=t.w_mask,l=t.prev,d=t.strstart+258,h=u[o+a-1],p=u[o+a];t.prev_length>=t.good_match&&(i>>=2),s>t.lookahead&&(s=t.lookahead);do{if(u[(r=e)+a]===p&&u[r+a-1]===h&&u[r]===u[o]&&u[++r]===u[o+1]){o+=2,r++;do{}while(u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&u[++o]===u[++r]&&o<d);if(n=258-(d-o),o=d-258,n>a){if(t.match_start=e,a=n,n>=s)break;h=u[o+a-1],p=u[o+a]}}}while((e=l[e&f])>c&&0!=--i);return a<=t.lookahead?a:t.lookahead}function m(t){var e,r,n,o,c,u,f,l,d,h,p=t.w_size;do{if(o=t.window_size-t.lookahead-t.strstart,t.strstart>=p+(p-262)){i.arraySet(t.window,t.window,p,p,0),t.match_start-=p,t.strstart-=p,t.block_start-=p,e=r=t.hash_size;do{n=t.head[--e],t.head[e]=n>=p?n-p:0}while(--r);e=r=p;do{n=t.prev[--e],t.prev[e]=n>=p?n-p:0}while(--r);o+=p}if(0===t.strm.avail_in)break;if(u=t.strm,f=t.window,l=t.strstart+t.lookahead,d=o,h=void 0,(h=u.avail_in)>d&&(h=d),r=0===h?0:(u.avail_in-=h,i.arraySet(f,u.input,u.next_in,h,l),1===u.state.wrap?u.adler=a(u.adler,f,h,l):2===u.state.wrap&&(u.adler=s(u.adler,f,h,l)),u.next_in+=h,u.total_in+=h,h),t.lookahead+=r,t.lookahead+t.insert>=3)for(c=t.strstart-t.insert,t.ins_h=t.window[c],t.ins_h=(t.ins_h<<t.hash_shift^t.window[c+1])&t.hash_mask;t.insert&&(t.ins_h=(t.ins_h<<t.hash_shift^t.window[c+3-1])&t.hash_mask,t.prev[c&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=c,c++,t.insert--,!(t.lookahead+t.insert<3)););}while(t.lookahead<262&&0!==t.strm.avail_in)}function v(t,e){for(var r,n;;){if(t.lookahead<262){if(m(t),t.lookahead<262&&0===e)return 1;if(0===t.lookahead)break}if(r=0,t.lookahead>=3&&(t.ins_h=(t.ins_h<<t.hash_shift^t.window[t.strstart+3-1])&t.hash_mask,r=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart),0!==r&&t.strstart-r<=t.w_size-262&&(t.match_length=g(t,r)),t.match_length>=3)if(n=o._tr_tally(t,t.strstart-t.match_start,t.match_length-3),t.lookahead-=t.match_length,t.match_length<=t.max_lazy_match&&t.lookahead>=3){t.match_length--;do{t.strstart++,t.ins_h=(t.ins_h<<t.hash_shift^t.window[t.strstart+3-1])&t.hash_mask,r=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart}while(0!=--t.match_length);t.strstart++}else t.strstart+=t.match_length,t.match_length=0,t.ins_h=t.window[t.strstart],t.ins_h=(t.ins_h<<t.hash_shift^t.window[t.strstart+1])&t.hash_mask;else n=o._tr_tally(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++;if(n&&(h(t,!1),0===t.strm.avail_out))return 1}return t.insert=t.strstart<2?t.strstart:2,4===e?(h(t,!0),0===t.strm.avail_out?3:4):t.last_lit&&(h(t,!1),0===t.strm.avail_out)?1:2}function w(t,e){for(var r,n,i;;){if(t.lookahead<262){if(m(t),t.lookahead<262&&0===e)return 1;if(0===t.lookahead)break}if(r=0,t.lookahead>=3&&(t.ins_h=(t.ins_h<<t.hash_shift^t.window[t.strstart+3-1])&t.hash_mask,r=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart),t.prev_length=t.match_length,t.prev_match=t.match_start,t.match_length=2,0!==r&&t.prev_length<t.max_lazy_match&&t.strstart-r<=t.w_size-262&&(t.match_length=g(t,r),t.match_length<=5&&(1===t.strategy||3===t.match_length&&t.strstart-t.match_start>4096)&&(t.match_length=2)),t.prev_length>=3&&t.match_length<=t.prev_length){i=t.strstart+t.lookahead-3,n=o._tr_tally(t,t.strstart-1-t.prev_match,t.prev_length-3),t.lookahead-=t.prev_length-1,t.prev_length-=2;do{++t.strstart<=i&&(t.ins_h=(t.ins_h<<t.hash_shift^t.window[t.strstart+3-1])&t.hash_mask,r=t.prev[t.strstart&t.w_mask]=t.head[t.ins_h],t.head[t.ins_h]=t.strstart)}while(0!=--t.prev_length);if(t.match_available=0,t.match_length=2,t.strstart++,n&&(h(t,!1),0===t.strm.avail_out))return 1}else if(t.match_available){if((n=o._tr_tally(t,0,t.window[t.strstart-1]))&&h(t,!1),t.strstart++,t.lookahead--,0===t.strm.avail_out)return 1}else t.match_available=1,t.strstart++,t.lookahead--}return t.match_available&&(n=o._tr_tally(t,0,t.window[t.strstart-1]),t.match_available=0),t.insert=t.strstart<2?t.strstart:2,4===e?(h(t,!0),0===t.strm.avail_out?3:4):t.last_lit&&(h(t,!1),0===t.strm.avail_out)?1:2}function b(t,e,r,n,i){this.good_length=t,this.max_lazy=e,this.nice_length=r,this.max_chain=n,this.func=i}function _(){this.strm=null,this.status=0,this.pending_buf=null,this.pending_buf_size=0,this.pending_out=0,this.pending=0,this.wrap=0,this.gzhead=null,this.gzindex=0,this.method=8,this.last_flush=-1,this.w_size=0,this.w_bits=0,this.w_mask=0,this.window=null,this.window_size=0,this.prev=null,this.head=null,this.ins_h=0,this.hash_size=0,this.hash_bits=0,this.hash_mask=0,this.hash_shift=0,this.block_start=0,this.match_length=0,this.prev_match=0,this.match_available=0,this.strstart=0,this.match_start=0,this.lookahead=0,this.prev_length=0,this.max_chain_length=0,this.max_lazy_match=0,this.level=0,this.strategy=0,this.good_match=0,this.nice_match=0,this.dyn_ltree=new i.Buf16(1146),this.dyn_dtree=new i.Buf16(122),this.bl_tree=new i.Buf16(78),l(this.dyn_ltree),l(this.dyn_dtree),l(this.bl_tree),this.l_desc=null,this.d_desc=null,this.bl_desc=null,this.bl_count=new i.Buf16(16),this.heap=new i.Buf16(573),l(this.heap),this.heap_len=0,this.heap_max=0,this.depth=new i.Buf16(573),l(this.depth),this.l_buf=0,this.lit_bufsize=0,this.last_lit=0,this.d_buf=0,this.opt_len=0,this.static_len=0,this.matches=0,this.insert=0,this.bi_buf=0,this.bi_valid=0}function j(t){var e;return t&&t.state?(t.total_in=t.total_out=0,t.data_type=2,(e=t.state).pending=0,e.pending_out=0,e.wrap<0&&(e.wrap=-e.wrap),e.status=e.wrap?42:113,t.adler=2===e.wrap?0:1,e.last_flush=0,o._tr_init(e),0):u(t,-2)}function O(t){var e,r=j(t);return 0===r&&((e=t.state).window_size=2*e.w_size,l(e.head),e.max_lazy_match=n[e.level].max_lazy,e.good_match=n[e.level].good_length,e.nice_match=n[e.level].nice_length,e.max_chain_length=n[e.level].max_chain,e.strstart=0,e.block_start=0,e.lookahead=0,e.insert=0,e.match_length=e.prev_length=2,e.match_available=0,e.ins_h=0),r}function x(t,e,r,n,o,a){if(!t)return-2;var s=1;if(-1===e&&(e=6),n<0?(s=0,n=-n):n>15&&(s=2,n-=16),o<1||o>9||8!==r||n<8||n>15||e<0||e>9||a<0||a>4)return u(t,-2);8===n&&(n=9);var c=new _;return t.state=c,c.strm=t,c.wrap=s,c.gzhead=null,c.w_bits=n,c.w_size=1<<c.w_bits,c.w_mask=c.w_size-1,c.hash_bits=o+7,c.hash_size=1<<c.hash_bits,c.hash_mask=c.hash_size-1,c.hash_shift=~~((c.hash_bits+3-1)/3),c.window=new i.Buf8(2*c.w_size),c.head=new i.Buf16(c.hash_size),c.prev=new i.Buf16(c.w_size),c.lit_bufsize=1<<o+6,c.pending_buf_size=4*c.lit_bufsize,c.pending_buf=new i.Buf8(c.pending_buf_size),c.d_buf=1*c.lit_bufsize,c.l_buf=3*c.lit_bufsize,c.level=e,c.strategy=a,c.method=r,O(t)}n=[new b(0,0,0,0,(function(t,e){var r=65535;for(r>t.pending_buf_size-5&&(r=t.pending_buf_size-5);;){if(t.lookahead<=1){if(m(t),0===t.lookahead&&0===e)return 1;if(0===t.lookahead)break}t.strstart+=t.lookahead,t.lookahead=0;var n=t.block_start+r;if((0===t.strstart||t.strstart>=n)&&(t.lookahead=t.strstart-n,t.strstart=n,h(t,!1),0===t.strm.avail_out))return 1;if(t.strstart-t.block_start>=t.w_size-262&&(h(t,!1),0===t.strm.avail_out))return 1}return t.insert=0,4===e?(h(t,!0),0===t.strm.avail_out?3:4):(t.strstart>t.block_start&&(h(t,!1),t.strm.avail_out),1)})),new b(4,4,8,4,v),new b(4,5,16,8,v),new b(4,6,32,32,v),new b(4,4,16,16,w),new b(8,16,32,32,w),new b(8,16,128,128,w),new b(8,32,128,256,w),new b(32,128,258,1024,w),new b(32,258,258,4096,w)],e.deflateInit=function(t,e){return x(t,e,8,15,8,0)},e.deflateInit2=x,e.deflateReset=O,e.deflateResetKeep=j,e.deflateSetHeader=function(t,e){return t&&t.state?2!==t.state.wrap?-2:(t.state.gzhead=e,0):-2},e.deflate=function(t,e){var r,i,a,c;if(!t||!t.state||e>5||e<0)return t?u(t,-2):-2;if(i=t.state,!t.output||!t.input&&0!==t.avail_in||666===i.status&&4!==e)return u(t,0===t.avail_out?-5:-2);if(i.strm=t,r=i.last_flush,i.last_flush=e,42===i.status)if(2===i.wrap)t.adler=0,p(i,31),p(i,139),p(i,8),i.gzhead?(p(i,(i.gzhead.text?1:0)+(i.gzhead.hcrc?2:0)+(i.gzhead.extra?4:0)+(i.gzhead.name?8:0)+(i.gzhead.comment?16:0)),p(i,255&i.gzhead.time),p(i,i.gzhead.time>>8&255),p(i,i.gzhead.time>>16&255),p(i,i.gzhead.time>>24&255),p(i,9===i.level?2:i.strategy>=2||i.level<2?4:0),p(i,255&i.gzhead.os),i.gzhead.extra&&i.gzhead.extra.length&&(p(i,255&i.gzhead.extra.length),p(i,i.gzhead.extra.length>>8&255)),i.gzhead.hcrc&&(t.adler=s(t.adler,i.pending_buf,i.pending,0)),i.gzindex=0,i.status=69):(p(i,0),p(i,0),p(i,0),p(i,0),p(i,0),p(i,9===i.level?2:i.strategy>=2||i.level<2?4:0),p(i,3),i.status=113);else{var g=8+(i.w_bits-8<<4)<<8;g|=(i.strategy>=2||i.level<2?0:i.level<6?1:6===i.level?2:3)<<6,0!==i.strstart&&(g|=32),g+=31-g%31,i.status=113,y(i,g),0!==i.strstart&&(y(i,t.adler>>>16),y(i,65535&t.adler)),t.adler=1}if(69===i.status)if(i.gzhead.extra){for(a=i.pending;i.gzindex<(65535&i.gzhead.extra.length)&&(i.pending!==i.pending_buf_size||(i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),d(t),a=i.pending,i.pending!==i.pending_buf_size));)p(i,255&i.gzhead.extra[i.gzindex]),i.gzindex++;i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),i.gzindex===i.gzhead.extra.length&&(i.gzindex=0,i.status=73)}else i.status=73;if(73===i.status)if(i.gzhead.name){a=i.pending;do{if(i.pending===i.pending_buf_size&&(i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),d(t),a=i.pending,i.pending===i.pending_buf_size)){c=1;break}c=i.gzindex<i.gzhead.name.length?255&i.gzhead.name.charCodeAt(i.gzindex++):0,p(i,c)}while(0!==c);i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),0===c&&(i.gzindex=0,i.status=91)}else i.status=91;if(91===i.status)if(i.gzhead.comment){a=i.pending;do{if(i.pending===i.pending_buf_size&&(i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),d(t),a=i.pending,i.pending===i.pending_buf_size)){c=1;break}c=i.gzindex<i.gzhead.comment.length?255&i.gzhead.comment.charCodeAt(i.gzindex++):0,p(i,c)}while(0!==c);i.gzhead.hcrc&&i.pending>a&&(t.adler=s(t.adler,i.pending_buf,i.pending-a,a)),0===c&&(i.status=103)}else i.status=103;if(103===i.status&&(i.gzhead.hcrc?(i.pending+2>i.pending_buf_size&&d(t),i.pending+2<=i.pending_buf_size&&(p(i,255&t.adler),p(i,t.adler>>8&255),t.adler=0,i.status=113)):i.status=113),0!==i.pending){if(d(t),0===t.avail_out)return i.last_flush=-1,0}else if(0===t.avail_in&&f(e)<=f(r)&&4!==e)return u(t,-5);if(666===i.status&&0!==t.avail_in)return u(t,-5);if(0!==t.avail_in||0!==i.lookahead||0!==e&&666!==i.status){var v=2===i.strategy?function(t,e){for(var r;;){if(0===t.lookahead&&(m(t),0===t.lookahead)){if(0===e)return 1;break}if(t.match_length=0,r=o._tr_tally(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++,r&&(h(t,!1),0===t.strm.avail_out))return 1}return t.insert=0,4===e?(h(t,!0),0===t.strm.avail_out?3:4):t.last_lit&&(h(t,!1),0===t.strm.avail_out)?1:2}(i,e):3===i.strategy?function(t,e){for(var r,n,i,a,s=t.window;;){if(t.lookahead<=258){if(m(t),t.lookahead<=258&&0===e)return 1;if(0===t.lookahead)break}if(t.match_length=0,t.lookahead>=3&&t.strstart>0&&(n=s[i=t.strstart-1])===s[++i]&&n===s[++i]&&n===s[++i]){a=t.strstart+258;do{}while(n===s[++i]&&n===s[++i]&&n===s[++i]&&n===s[++i]&&n===s[++i]&&n===s[++i]&&n===s[++i]&&n===s[++i]&&i<a);t.match_length=258-(a-i),t.match_length>t.lookahead&&(t.match_length=t.lookahead)}if(t.match_length>=3?(r=o._tr_tally(t,1,t.match_length-3),t.lookahead-=t.match_length,t.strstart+=t.match_length,t.match_length=0):(r=o._tr_tally(t,0,t.window[t.strstart]),t.lookahead--,t.strstart++),r&&(h(t,!1),0===t.strm.avail_out))return 1}return t.insert=0,4===e?(h(t,!0),0===t.strm.avail_out?3:4):t.last_lit&&(h(t,!1),0===t.strm.avail_out)?1:2}(i,e):n[i.level].func(i,e);if(3!==v&&4!==v||(i.status=666),1===v||3===v)return 0===t.avail_out&&(i.last_flush=-1),0;if(2===v&&(1===e?o._tr_align(i):5!==e&&(o._tr_stored_block(i,0,0,!1),3===e&&(l(i.head),0===i.lookahead&&(i.strstart=0,i.block_start=0,i.insert=0))),d(t),0===t.avail_out))return i.last_flush=-1,0}return 4!==e?0:i.wrap<=0?1:(2===i.wrap?(p(i,255&t.adler),p(i,t.adler>>8&255),p(i,t.adler>>16&255),p(i,t.adler>>24&255),p(i,255&t.total_in),p(i,t.total_in>>8&255),p(i,t.total_in>>16&255),p(i,t.total_in>>24&255)):(y(i,t.adler>>>16),y(i,65535&t.adler)),d(t),i.wrap>0&&(i.wrap=-i.wrap),0!==i.pending?0:1)},e.deflateEnd=function(t){var e;return t&&t.state?42!==(e=t.state.status)&&69!==e&&73!==e&&91!==e&&103!==e&&113!==e&&666!==e?u(t,-2):(t.state=null,113===e?u(t,-3):0):-2},e.deflateSetDictionary=function(t,e){var r,n,o,s,c,u,f,d,h=e.length;if(!t||!t.state)return-2;if(2===(s=(r=t.state).wrap)||1===s&&42!==r.status||r.lookahead)return-2;for(1===s&&(t.adler=a(t.adler,e,h,0)),r.wrap=0,h>=r.w_size&&(0===s&&(l(r.head),r.strstart=0,r.block_start=0,r.insert=0),d=new i.Buf8(r.w_size),i.arraySet(d,e,h-r.w_size,r.w_size,0),e=d,h=r.w_size),c=t.avail_in,u=t.next_in,f=t.input,t.avail_in=h,t.next_in=0,t.input=e,m(r);r.lookahead>=3;){n=r.strstart,o=r.lookahead-2;do{r.ins_h=(r.ins_h<<r.hash_shift^r.window[n+3-1])&r.hash_mask,r.prev[n&r.w_mask]=r.head[r.ins_h],r.head[r.ins_h]=n,n++}while(--o);r.strstart=n,r.lookahead=2,m(r)}return r.strstart+=r.lookahead,r.block_start=r.strstart,r.insert=r.lookahead,r.lookahead=0,r.match_length=r.prev_length=2,r.match_available=0,t.next_in=u,t.input=f,t.avail_in=c,r.wrap=s,0},e.deflateInfo="pako deflate (from Nodeca project)"},function(t,e,r){"use strict";var n=r(31);function i(t){for(var e=t.length;--e>=0;)t[e]=0}var o=[0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0],a=[0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13],s=[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,3,7],c=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15],u=new Array(576);i(u);var f=new Array(60);i(f);var l=new Array(512);i(l);var d=new Array(256);i(d);var h=new Array(29);i(h);var p,y,g,m=new Array(30);function v(t,e,r,n,i){this.static_tree=t,this.extra_bits=e,this.extra_base=r,this.elems=n,this.max_length=i,this.has_stree=t&&t.length}function w(t,e){this.dyn_tree=t,this.max_code=0,this.stat_desc=e}function b(t){return t<256?l[t]:l[256+(t>>>7)]}function _(t,e){t.pending_buf[t.pending++]=255&e,t.pending_buf[t.pending++]=e>>>8&255}function j(t,e,r){t.bi_valid>16-r?(t.bi_buf|=e<<t.bi_valid&65535,_(t,t.bi_buf),t.bi_buf=e>>16-t.bi_valid,t.bi_valid+=r-16):(t.bi_buf|=e<<t.bi_valid&65535,t.bi_valid+=r)}function O(t,e,r){j(t,r[2*e],r[2*e+1])}function x(t,e){var r=0;do{r|=1&t,t>>>=1,r<<=1}while(--e>0);return r>>>1}function P(t,e,r){var n,i,o=new Array(16),a=0;for(n=1;n<=15;n++)o[n]=a=a+r[n-1]<<1;for(i=0;i<=e;i++){var s=t[2*i+1];0!==s&&(t[2*i]=x(o[s]++,s))}}function k(t){var e;for(e=0;e<286;e++)t.dyn_ltree[2*e]=0;for(e=0;e<30;e++)t.dyn_dtree[2*e]=0;for(e=0;e<19;e++)t.bl_tree[2*e]=0;t.dyn_ltree[512]=1,t.opt_len=t.static_len=0,t.last_lit=t.matches=0}function E(t){t.bi_valid>8?_(t,t.bi_buf):t.bi_valid>0&&(t.pending_buf[t.pending++]=t.bi_buf),t.bi_buf=0,t.bi_valid=0}function S(t,e,r,n){var i=2*e,o=2*r;return t[i]<t[o]||t[i]===t[o]&&n[e]<=n[r]}function A(t,e,r){for(var n=t.heap[r],i=r<<1;i<=t.heap_len&&(i<t.heap_len&&S(e,t.heap[i+1],t.heap[i],t.depth)&&i++,!S(e,n,t.heap[i],t.depth));)t.heap[r]=t.heap[i],r=i,i<<=1;t.heap[r]=n}function R(t,e,r){var n,i,s,c,u=0;if(0!==t.last_lit)do{n=t.pending_buf[t.d_buf+2*u]<<8|t.pending_buf[t.d_buf+2*u+1],i=t.pending_buf[t.l_buf+u],u++,0===n?O(t,i,e):(O(t,(s=d[i])+256+1,e),0!==(c=o[s])&&j(t,i-=h[s],c),O(t,s=b(--n),r),0!==(c=a[s])&&j(t,n-=m[s],c))}while(u<t.last_lit);O(t,256,e)}function $(t,e){var r,n,i,o=e.dyn_tree,a=e.stat_desc.static_tree,s=e.stat_desc.has_stree,c=e.stat_desc.elems,u=-1;for(t.heap_len=0,t.heap_max=573,r=0;r<c;r++)0!==o[2*r]?(t.heap[++t.heap_len]=u=r,t.depth[r]=0):o[2*r+1]=0;for(;t.heap_len<2;)o[2*(i=t.heap[++t.heap_len]=u<2?++u:0)]=1,t.depth[i]=0,t.opt_len--,s&&(t.static_len-=a[2*i+1]);for(e.max_code=u,r=t.heap_len>>1;r>=1;r--)A(t,o,r);i=c;do{r=t.heap[1],t.heap[1]=t.heap[t.heap_len--],A(t,o,1),n=t.heap[1],t.heap[--t.heap_max]=r,t.heap[--t.heap_max]=n,o[2*i]=o[2*r]+o[2*n],t.depth[i]=(t.depth[r]>=t.depth[n]?t.depth[r]:t.depth[n])+1,o[2*r+1]=o[2*n+1]=i,t.heap[1]=i++,A(t,o,1)}while(t.heap_len>=2);t.heap[--t.heap_max]=t.heap[1],function(t,e){var r,n,i,o,a,s,c=e.dyn_tree,u=e.max_code,f=e.stat_desc.static_tree,l=e.stat_desc.has_stree,d=e.stat_desc.extra_bits,h=e.stat_desc.extra_base,p=e.stat_desc.max_length,y=0;for(o=0;o<=15;o++)t.bl_count[o]=0;for(c[2*t.heap[t.heap_max]+1]=0,r=t.heap_max+1;r<573;r++)(o=c[2*c[2*(n=t.heap[r])+1]+1]+1)>p&&(o=p,y++),c[2*n+1]=o,n>u||(t.bl_count[o]++,a=0,n>=h&&(a=d[n-h]),s=c[2*n],t.opt_len+=s*(o+a),l&&(t.static_len+=s*(f[2*n+1]+a)));if(0!==y){do{for(o=p-1;0===t.bl_count[o];)o--;t.bl_count[o]--,t.bl_count[o+1]+=2,t.bl_count[p]--,y-=2}while(y>0);for(o=p;0!==o;o--)for(n=t.bl_count[o];0!==n;)(i=t.heap[--r])>u||(c[2*i+1]!==o&&(t.opt_len+=(o-c[2*i+1])*c[2*i],c[2*i+1]=o),n--)}}(t,e),P(o,u,t.bl_count)}function B(t,e,r){var n,i,o=-1,a=e[1],s=0,c=7,u=4;for(0===a&&(c=138,u=3),e[2*(r+1)+1]=65535,n=0;n<=r;n++)i=a,a=e[2*(n+1)+1],++s<c&&i===a||(s<u?t.bl_tree[2*i]+=s:0!==i?(i!==o&&t.bl_tree[2*i]++,t.bl_tree[32]++):s<=10?t.bl_tree[34]++:t.bl_tree[36]++,s=0,o=i,0===a?(c=138,u=3):i===a?(c=6,u=3):(c=7,u=4))}function T(t,e,r){var n,i,o=-1,a=e[1],s=0,c=7,u=4;for(0===a&&(c=138,u=3),n=0;n<=r;n++)if(i=a,a=e[2*(n+1)+1],!(++s<c&&i===a)){if(s<u)do{O(t,i,t.bl_tree)}while(0!=--s);else 0!==i?(i!==o&&(O(t,i,t.bl_tree),s--),O(t,16,t.bl_tree),j(t,s-3,2)):s<=10?(O(t,17,t.bl_tree),j(t,s-3,3)):(O(t,18,t.bl_tree),j(t,s-11,7));s=0,o=i,0===a?(c=138,u=3):i===a?(c=6,u=3):(c=7,u=4)}}i(m);var I=!1;function C(t,e,r,i){j(t,0+(i?1:0),3),function(t,e,r,i){E(t),i&&(_(t,r),_(t,~r)),n.arraySet(t.pending_buf,t.window,e,r,t.pending),t.pending+=r}(t,e,r,!0)}e._tr_init=function(t){I||(!function(){var t,e,r,n,i,c=new Array(16);for(r=0,n=0;n<28;n++)for(h[n]=r,t=0;t<1<<o[n];t++)d[r++]=n;for(d[r-1]=n,i=0,n=0;n<16;n++)for(m[n]=i,t=0;t<1<<a[n];t++)l[i++]=n;for(i>>=7;n<30;n++)for(m[n]=i<<7,t=0;t<1<<a[n]-7;t++)l[256+i++]=n;for(e=0;e<=15;e++)c[e]=0;for(t=0;t<=143;)u[2*t+1]=8,t++,c[8]++;for(;t<=255;)u[2*t+1]=9,t++,c[9]++;for(;t<=279;)u[2*t+1]=7,t++,c[7]++;for(;t<=287;)u[2*t+1]=8,t++,c[8]++;for(P(u,287,c),t=0;t<30;t++)f[2*t+1]=5,f[2*t]=x(t,5);p=new v(u,o,257,286,15),y=new v(f,a,0,30,15),g=new v(new Array(0),s,0,19,7)}(),I=!0),t.l_desc=new w(t.dyn_ltree,p),t.d_desc=new w(t.dyn_dtree,y),t.bl_desc=new w(t.bl_tree,g),t.bi_buf=0,t.bi_valid=0,k(t)},e._tr_stored_block=C,e._tr_flush_block=function(t,e,r,n){var i,o,a=0;t.level>0?(2===t.strm.data_type&&(t.strm.data_type=function(t){var e,r=4093624447;for(e=0;e<=31;e++,r>>>=1)if(1&r&&0!==t.dyn_ltree[2*e])return 0;if(0!==t.dyn_ltree[18]||0!==t.dyn_ltree[20]||0!==t.dyn_ltree[26])return 1;for(e=32;e<256;e++)if(0!==t.dyn_ltree[2*e])return 1;return 0}(t)),$(t,t.l_desc),$(t,t.d_desc),a=function(t){var e;for(B(t,t.dyn_ltree,t.l_desc.max_code),B(t,t.dyn_dtree,t.d_desc.max_code),$(t,t.bl_desc),e=18;e>=3&&0===t.bl_tree[2*c[e]+1];e--);return t.opt_len+=3*(e+1)+5+5+4,e}(t),i=t.opt_len+3+7>>>3,(o=t.static_len+3+7>>>3)<=i&&(i=o)):i=o=r+5,r+4<=i&&-1!==e?C(t,e,r,n):4===t.strategy||o===i?(j(t,2+(n?1:0),3),R(t,u,f)):(j(t,4+(n?1:0),3),function(t,e,r,n){var i;for(j(t,e-257,5),j(t,r-1,5),j(t,n-4,4),i=0;i<n;i++)j(t,t.bl_tree[2*c[i]+1],3);T(t,t.dyn_ltree,e-1),T(t,t.dyn_dtree,r-1)}(t,t.l_desc.max_code+1,t.d_desc.max_code+1,a+1),R(t,t.dyn_ltree,t.dyn_dtree)),k(t),n&&E(t)},e._tr_tally=function(t,e,r){return t.pending_buf[t.d_buf+2*t.last_lit]=e>>>8&255,t.pending_buf[t.d_buf+2*t.last_lit+1]=255&e,t.pending_buf[t.l_buf+t.last_lit]=255&r,t.last_lit++,0===e?t.dyn_ltree[2*r]++:(t.matches++,e--,t.dyn_ltree[2*(d[r]+256+1)]++,t.dyn_dtree[2*b(e)]++),t.last_lit===t.lit_bufsize-1},e._tr_align=function(t){j(t,2,3),O(t,256,u),function(t){16===t.bi_valid?(_(t,t.bi_buf),t.bi_buf=0,t.bi_valid=0):t.bi_valid>=8&&(t.pending_buf[t.pending++]=255&t.bi_buf,t.bi_buf>>=8,t.bi_valid-=8)}(t)}},function(t,e,r){"use strict";var n=r(154),i=r(31),o=r(122),a=r(124),s=r(96),c=r(123),u=r(157),f=Object.prototype.toString;function l(t){if(!(this instanceof l))return new l(t);this.options=i.assign({chunkSize:16384,windowBits:0,to:""},t||{});var e=this.options;e.raw&&e.windowBits>=0&&e.windowBits<16&&(e.windowBits=-e.windowBits,0===e.windowBits&&(e.windowBits=-15)),!(e.windowBits>=0&&e.windowBits<16)||t&&t.windowBits||(e.windowBits+=32),e.windowBits>15&&e.windowBits<48&&0==(15&e.windowBits)&&(e.windowBits|=15),this.err=0,this.msg="",this.ended=!1,this.chunks=[],this.strm=new c,this.strm.avail_out=0;var r=n.inflateInit2(this.strm,e.windowBits);if(r!==a.Z_OK)throw new Error(s[r]);if(this.header=new u,n.inflateGetHeader(this.strm,this.header),e.dictionary&&("string"==typeof e.dictionary?e.dictionary=o.string2buf(e.dictionary):"[object ArrayBuffer]"===f.call(e.dictionary)&&(e.dictionary=new Uint8Array(e.dictionary)),e.raw&&(r=n.inflateSetDictionary(this.strm,e.dictionary))!==a.Z_OK))throw new Error(s[r])}function d(t,e){var r=new l(e);if(r.push(t,!0),r.err)throw r.msg||s[r.err];return r.result}l.prototype.push=function(t,e){var r,s,c,u,l,d=this.strm,h=this.options.chunkSize,p=this.options.dictionary,y=!1;if(this.ended)return!1;s=e===~~e?e:!0===e?a.Z_FINISH:a.Z_NO_FLUSH,"string"==typeof t?d.input=o.binstring2buf(t):"[object ArrayBuffer]"===f.call(t)?d.input=new Uint8Array(t):d.input=t,d.next_in=0,d.avail_in=d.input.length;do{if(0===d.avail_out&&(d.output=new i.Buf8(h),d.next_out=0,d.avail_out=h),(r=n.inflate(d,a.Z_NO_FLUSH))===a.Z_NEED_DICT&&p&&(r=n.inflateSetDictionary(this.strm,p)),r===a.Z_BUF_ERROR&&!0===y&&(r=a.Z_OK,y=!1),r!==a.Z_STREAM_END&&r!==a.Z_OK)return this.onEnd(r),this.ended=!0,!1;d.next_out&&(0!==d.avail_out&&r!==a.Z_STREAM_END&&(0!==d.avail_in||s!==a.Z_FINISH&&s!==a.Z_SYNC_FLUSH)||("string"===this.options.to?(c=o.utf8border(d.output,d.next_out),u=d.next_out-c,l=o.buf2string(d.output,c),d.next_out=u,d.avail_out=h-u,u&&i.arraySet(d.output,d.output,c,u,0),this.onData(l)):this.onData(i.shrinkBuf(d.output,d.next_out)))),0===d.avail_in&&0===d.avail_out&&(y=!0)}while((d.avail_in>0||0===d.avail_out)&&r!==a.Z_STREAM_END);return r===a.Z_STREAM_END&&(s=a.Z_FINISH),s===a.Z_FINISH?(r=n.inflateEnd(this.strm),this.onEnd(r),this.ended=!0,r===a.Z_OK):s!==a.Z_SYNC_FLUSH||(this.onEnd(a.Z_OK),d.avail_out=0,!0)},l.prototype.onData=function(t){this.chunks.push(t)},l.prototype.onEnd=function(t){t===a.Z_OK&&("string"===this.options.to?this.result=this.chunks.join(""):this.result=i.flattenChunks(this.chunks)),this.chunks=[],this.err=t,this.msg=this.strm.msg},e.Inflate=l,e.inflate=d,e.inflateRaw=function(t,e){return(e=e||{}).raw=!0,d(t,e)},e.ungzip=d},function(t,e,r){"use strict";var n=r(31),i=r(120),o=r(121),a=r(155),s=r(156);function c(t){return(t>>>24&255)+(t>>>8&65280)+((65280&t)<<8)+((255&t)<<24)}function u(){this.mode=0,this.last=!1,this.wrap=0,this.havedict=!1,this.flags=0,this.dmax=0,this.check=0,this.total=0,this.head=null,this.wbits=0,this.wsize=0,this.whave=0,this.wnext=0,this.window=null,this.hold=0,this.bits=0,this.length=0,this.offset=0,this.extra=0,this.lencode=null,this.distcode=null,this.lenbits=0,this.distbits=0,this.ncode=0,this.nlen=0,this.ndist=0,this.have=0,this.next=null,this.lens=new n.Buf16(320),this.work=new n.Buf16(288),this.lendyn=null,this.distdyn=null,this.sane=0,this.back=0,this.was=0}function f(t){var e;return t&&t.state?(e=t.state,t.total_in=t.total_out=e.total=0,t.msg="",e.wrap&&(t.adler=1&e.wrap),e.mode=1,e.last=0,e.havedict=0,e.dmax=32768,e.head=null,e.hold=0,e.bits=0,e.lencode=e.lendyn=new n.Buf32(852),e.distcode=e.distdyn=new n.Buf32(592),e.sane=1,e.back=-1,0):-2}function l(t){var e;return t&&t.state?((e=t.state).wsize=0,e.whave=0,e.wnext=0,f(t)):-2}function d(t,e){var r,n;return t&&t.state?(n=t.state,e<0?(r=0,e=-e):(r=1+(e>>4),e<48&&(e&=15)),e&&(e<8||e>15)?-2:(null!==n.window&&n.wbits!==e&&(n.window=null),n.wrap=r,n.wbits=e,l(t))):-2}function h(t,e){var r,n;return t?(n=new u,t.state=n,n.window=null,0!==(r=d(t,e))&&(t.state=null),r):-2}var p,y,g=!0;function m(t){if(g){var e;for(p=new n.Buf32(512),y=new n.Buf32(32),e=0;e<144;)t.lens[e++]=8;for(;e<256;)t.lens[e++]=9;for(;e<280;)t.lens[e++]=7;for(;e<288;)t.lens[e++]=8;for(s(1,t.lens,0,288,p,0,t.work,{bits:9}),e=0;e<32;)t.lens[e++]=5;s(2,t.lens,0,32,y,0,t.work,{bits:5}),g=!1}t.lencode=p,t.lenbits=9,t.distcode=y,t.distbits=5}function v(t,e,r,i){var o,a=t.state;return null===a.window&&(a.wsize=1<<a.wbits,a.wnext=0,a.whave=0,a.window=new n.Buf8(a.wsize)),i>=a.wsize?(n.arraySet(a.window,e,r-a.wsize,a.wsize,0),a.wnext=0,a.whave=a.wsize):((o=a.wsize-a.wnext)>i&&(o=i),n.arraySet(a.window,e,r-i,o,a.wnext),(i-=o)?(n.arraySet(a.window,e,r-i,i,0),a.wnext=i,a.whave=a.wsize):(a.wnext+=o,a.wnext===a.wsize&&(a.wnext=0),a.whave<a.wsize&&(a.whave+=o))),0}e.inflateReset=l,e.inflateReset2=d,e.inflateResetKeep=f,e.inflateInit=function(t){return h(t,15)},e.inflateInit2=h,e.inflate=function(t,e){var r,u,f,l,d,h,p,y,g,w,b,_,j,O,x,P,k,E,S,A,R,$,B,T,I=0,C=new n.Buf8(4),U=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];if(!t||!t.state||!t.output||!t.input&&0!==t.avail_in)return-2;12===(r=t.state).mode&&(r.mode=13),d=t.next_out,f=t.output,p=t.avail_out,l=t.next_in,u=t.input,h=t.avail_in,y=r.hold,g=r.bits,w=h,b=p,$=0;t:for(;;)switch(r.mode){case 1:if(0===r.wrap){r.mode=13;break}for(;g<16;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(2&r.wrap&&35615===y){r.check=0,C[0]=255&y,C[1]=y>>>8&255,r.check=o(r.check,C,2,0),y=0,g=0,r.mode=2;break}if(r.flags=0,r.head&&(r.head.done=!1),!(1&r.wrap)||(((255&y)<<8)+(y>>8))%31){t.msg="incorrect header check",r.mode=30;break}if(8!=(15&y)){t.msg="unknown compression method",r.mode=30;break}if(g-=4,R=8+(15&(y>>>=4)),0===r.wbits)r.wbits=R;else if(R>r.wbits){t.msg="invalid window size",r.mode=30;break}r.dmax=1<<R,t.adler=r.check=1,r.mode=512&y?10:12,y=0,g=0;break;case 2:for(;g<16;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(r.flags=y,8!=(255&r.flags)){t.msg="unknown compression method",r.mode=30;break}if(57344&r.flags){t.msg="unknown header flags set",r.mode=30;break}r.head&&(r.head.text=y>>8&1),512&r.flags&&(C[0]=255&y,C[1]=y>>>8&255,r.check=o(r.check,C,2,0)),y=0,g=0,r.mode=3;case 3:for(;g<32;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.head&&(r.head.time=y),512&r.flags&&(C[0]=255&y,C[1]=y>>>8&255,C[2]=y>>>16&255,C[3]=y>>>24&255,r.check=o(r.check,C,4,0)),y=0,g=0,r.mode=4;case 4:for(;g<16;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.head&&(r.head.xflags=255&y,r.head.os=y>>8),512&r.flags&&(C[0]=255&y,C[1]=y>>>8&255,r.check=o(r.check,C,2,0)),y=0,g=0,r.mode=5;case 5:if(1024&r.flags){for(;g<16;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.length=y,r.head&&(r.head.extra_len=y),512&r.flags&&(C[0]=255&y,C[1]=y>>>8&255,r.check=o(r.check,C,2,0)),y=0,g=0}else r.head&&(r.head.extra=null);r.mode=6;case 6:if(1024&r.flags&&((_=r.length)>h&&(_=h),_&&(r.head&&(R=r.head.extra_len-r.length,r.head.extra||(r.head.extra=new Array(r.head.extra_len)),n.arraySet(r.head.extra,u,l,_,R)),512&r.flags&&(r.check=o(r.check,u,_,l)),h-=_,l+=_,r.length-=_),r.length))break t;r.length=0,r.mode=7;case 7:if(2048&r.flags){if(0===h)break t;_=0;do{R=u[l+_++],r.head&&R&&r.length<65536&&(r.head.name+=String.fromCharCode(R))}while(R&&_<h);if(512&r.flags&&(r.check=o(r.check,u,_,l)),h-=_,l+=_,R)break t}else r.head&&(r.head.name=null);r.length=0,r.mode=8;case 8:if(4096&r.flags){if(0===h)break t;_=0;do{R=u[l+_++],r.head&&R&&r.length<65536&&(r.head.comment+=String.fromCharCode(R))}while(R&&_<h);if(512&r.flags&&(r.check=o(r.check,u,_,l)),h-=_,l+=_,R)break t}else r.head&&(r.head.comment=null);r.mode=9;case 9:if(512&r.flags){for(;g<16;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(y!==(65535&r.check)){t.msg="header crc mismatch",r.mode=30;break}y=0,g=0}r.head&&(r.head.hcrc=r.flags>>9&1,r.head.done=!0),t.adler=r.check=0,r.mode=12;break;case 10:for(;g<32;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}t.adler=r.check=c(y),y=0,g=0,r.mode=11;case 11:if(0===r.havedict)return t.next_out=d,t.avail_out=p,t.next_in=l,t.avail_in=h,r.hold=y,r.bits=g,2;t.adler=r.check=1,r.mode=12;case 12:if(5===e||6===e)break t;case 13:if(r.last){y>>>=7&g,g-=7&g,r.mode=27;break}for(;g<3;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}switch(r.last=1&y,g-=1,3&(y>>>=1)){case 0:r.mode=14;break;case 1:if(m(r),r.mode=20,6===e){y>>>=2,g-=2;break t}break;case 2:r.mode=17;break;case 3:t.msg="invalid block type",r.mode=30}y>>>=2,g-=2;break;case 14:for(y>>>=7&g,g-=7&g;g<32;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if((65535&y)!=(y>>>16^65535)){t.msg="invalid stored block lengths",r.mode=30;break}if(r.length=65535&y,y=0,g=0,r.mode=15,6===e)break t;case 15:r.mode=16;case 16:if(_=r.length){if(_>h&&(_=h),_>p&&(_=p),0===_)break t;n.arraySet(f,u,l,_,d),h-=_,l+=_,p-=_,d+=_,r.length-=_;break}r.mode=12;break;case 17:for(;g<14;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(r.nlen=257+(31&y),y>>>=5,g-=5,r.ndist=1+(31&y),y>>>=5,g-=5,r.ncode=4+(15&y),y>>>=4,g-=4,r.nlen>286||r.ndist>30){t.msg="too many length or distance symbols",r.mode=30;break}r.have=0,r.mode=18;case 18:for(;r.have<r.ncode;){for(;g<3;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.lens[U[r.have++]]=7&y,y>>>=3,g-=3}for(;r.have<19;)r.lens[U[r.have++]]=0;if(r.lencode=r.lendyn,r.lenbits=7,B={bits:r.lenbits},$=s(0,r.lens,0,19,r.lencode,0,r.work,B),r.lenbits=B.bits,$){t.msg="invalid code lengths set",r.mode=30;break}r.have=0,r.mode=19;case 19:for(;r.have<r.nlen+r.ndist;){for(;P=(I=r.lencode[y&(1<<r.lenbits)-1])>>>16&255,k=65535&I,!((x=I>>>24)<=g);){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(k<16)y>>>=x,g-=x,r.lens[r.have++]=k;else{if(16===k){for(T=x+2;g<T;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(y>>>=x,g-=x,0===r.have){t.msg="invalid bit length repeat",r.mode=30;break}R=r.lens[r.have-1],_=3+(3&y),y>>>=2,g-=2}else if(17===k){for(T=x+3;g<T;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}g-=x,R=0,_=3+(7&(y>>>=x)),y>>>=3,g-=3}else{for(T=x+7;g<T;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}g-=x,R=0,_=11+(127&(y>>>=x)),y>>>=7,g-=7}if(r.have+_>r.nlen+r.ndist){t.msg="invalid bit length repeat",r.mode=30;break}for(;_--;)r.lens[r.have++]=R}}if(30===r.mode)break;if(0===r.lens[256]){t.msg="invalid code -- missing end-of-block",r.mode=30;break}if(r.lenbits=9,B={bits:r.lenbits},$=s(1,r.lens,0,r.nlen,r.lencode,0,r.work,B),r.lenbits=B.bits,$){t.msg="invalid literal/lengths set",r.mode=30;break}if(r.distbits=6,r.distcode=r.distdyn,B={bits:r.distbits},$=s(2,r.lens,r.nlen,r.ndist,r.distcode,0,r.work,B),r.distbits=B.bits,$){t.msg="invalid distances set",r.mode=30;break}if(r.mode=20,6===e)break t;case 20:r.mode=21;case 21:if(h>=6&&p>=258){t.next_out=d,t.avail_out=p,t.next_in=l,t.avail_in=h,r.hold=y,r.bits=g,a(t,b),d=t.next_out,f=t.output,p=t.avail_out,l=t.next_in,u=t.input,h=t.avail_in,y=r.hold,g=r.bits,12===r.mode&&(r.back=-1);break}for(r.back=0;P=(I=r.lencode[y&(1<<r.lenbits)-1])>>>16&255,k=65535&I,!((x=I>>>24)<=g);){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(P&&0==(240&P)){for(E=x,S=P,A=k;P=(I=r.lencode[A+((y&(1<<E+S)-1)>>E)])>>>16&255,k=65535&I,!(E+(x=I>>>24)<=g);){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}y>>>=E,g-=E,r.back+=E}if(y>>>=x,g-=x,r.back+=x,r.length=k,0===P){r.mode=26;break}if(32&P){r.back=-1,r.mode=12;break}if(64&P){t.msg="invalid literal/length code",r.mode=30;break}r.extra=15&P,r.mode=22;case 22:if(r.extra){for(T=r.extra;g<T;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.length+=y&(1<<r.extra)-1,y>>>=r.extra,g-=r.extra,r.back+=r.extra}r.was=r.length,r.mode=23;case 23:for(;P=(I=r.distcode[y&(1<<r.distbits)-1])>>>16&255,k=65535&I,!((x=I>>>24)<=g);){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(0==(240&P)){for(E=x,S=P,A=k;P=(I=r.distcode[A+((y&(1<<E+S)-1)>>E)])>>>16&255,k=65535&I,!(E+(x=I>>>24)<=g);){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}y>>>=E,g-=E,r.back+=E}if(y>>>=x,g-=x,r.back+=x,64&P){t.msg="invalid distance code",r.mode=30;break}r.offset=k,r.extra=15&P,r.mode=24;case 24:if(r.extra){for(T=r.extra;g<T;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}r.offset+=y&(1<<r.extra)-1,y>>>=r.extra,g-=r.extra,r.back+=r.extra}if(r.offset>r.dmax){t.msg="invalid distance too far back",r.mode=30;break}r.mode=25;case 25:if(0===p)break t;if(_=b-p,r.offset>_){if((_=r.offset-_)>r.whave&&r.sane){t.msg="invalid distance too far back",r.mode=30;break}_>r.wnext?(_-=r.wnext,j=r.wsize-_):j=r.wnext-_,_>r.length&&(_=r.length),O=r.window}else O=f,j=d-r.offset,_=r.length;_>p&&(_=p),p-=_,r.length-=_;do{f[d++]=O[j++]}while(--_);0===r.length&&(r.mode=21);break;case 26:if(0===p)break t;f[d++]=r.length,p--,r.mode=21;break;case 27:if(r.wrap){for(;g<32;){if(0===h)break t;h--,y|=u[l++]<<g,g+=8}if(b-=p,t.total_out+=b,r.total+=b,b&&(t.adler=r.check=r.flags?o(r.check,f,b,d-b):i(r.check,f,b,d-b)),b=p,(r.flags?y:c(y))!==r.check){t.msg="incorrect data check",r.mode=30;break}y=0,g=0}r.mode=28;case 28:if(r.wrap&&r.flags){for(;g<32;){if(0===h)break t;h--,y+=u[l++]<<g,g+=8}if(y!==(4294967295&r.total)){t.msg="incorrect length check",r.mode=30;break}y=0,g=0}r.mode=29;case 29:$=1;break t;case 30:$=-3;break t;case 31:return-4;case 32:default:return-2}return t.next_out=d,t.avail_out=p,t.next_in=l,t.avail_in=h,r.hold=y,r.bits=g,(r.wsize||b!==t.avail_out&&r.mode<30&&(r.mode<27||4!==e))&&v(t,t.output,t.next_out,b-t.avail_out)?(r.mode=31,-4):(w-=t.avail_in,b-=t.avail_out,t.total_in+=w,t.total_out+=b,r.total+=b,r.wrap&&b&&(t.adler=r.check=r.flags?o(r.check,f,b,t.next_out-b):i(r.check,f,b,t.next_out-b)),t.data_type=r.bits+(r.last?64:0)+(12===r.mode?128:0)+(20===r.mode||15===r.mode?256:0),(0===w&&0===b||4===e)&&0===$&&($=-5),$)},e.inflateEnd=function(t){if(!t||!t.state)return-2;var e=t.state;return e.window&&(e.window=null),t.state=null,0},e.inflateGetHeader=function(t,e){var r;return t&&t.state?0==(2&(r=t.state).wrap)?-2:(r.head=e,e.done=!1,0):-2},e.inflateSetDictionary=function(t,e){var r,n=e.length;return t&&t.state?0!==(r=t.state).wrap&&11!==r.mode?-2:11===r.mode&&i(1,e,n,0)!==r.check?-3:v(t,e,n,n)?(r.mode=31,-4):(r.havedict=1,0):-2},e.inflateInfo="pako inflate (from Nodeca project)"},function(t,e,r){"use strict";t.exports=function(t,e){var r,n,i,o,a,s,c,u,f,l,d,h,p,y,g,m,v,w,b,_,j,O,x,P,k;r=t.state,n=t.next_in,P=t.input,i=n+(t.avail_in-5),o=t.next_out,k=t.output,a=o-(e-t.avail_out),s=o+(t.avail_out-257),c=r.dmax,u=r.wsize,f=r.whave,l=r.wnext,d=r.window,h=r.hold,p=r.bits,y=r.lencode,g=r.distcode,m=(1<<r.lenbits)-1,v=(1<<r.distbits)-1;t:do{p<15&&(h+=P[n++]<<p,p+=8,h+=P[n++]<<p,p+=8),w=y[h&m];e:for(;;){if(h>>>=b=w>>>24,p-=b,0===(b=w>>>16&255))k[o++]=65535&w;else{if(!(16&b)){if(0==(64&b)){w=y[(65535&w)+(h&(1<<b)-1)];continue e}if(32&b){r.mode=12;break t}t.msg="invalid literal/length code",r.mode=30;break t}_=65535&w,(b&=15)&&(p<b&&(h+=P[n++]<<p,p+=8),_+=h&(1<<b)-1,h>>>=b,p-=b),p<15&&(h+=P[n++]<<p,p+=8,h+=P[n++]<<p,p+=8),w=g[h&v];r:for(;;){if(h>>>=b=w>>>24,p-=b,!(16&(b=w>>>16&255))){if(0==(64&b)){w=g[(65535&w)+(h&(1<<b)-1)];continue r}t.msg="invalid distance code",r.mode=30;break t}if(j=65535&w,p<(b&=15)&&(h+=P[n++]<<p,(p+=8)<b&&(h+=P[n++]<<p,p+=8)),(j+=h&(1<<b)-1)>c){t.msg="invalid distance too far back",r.mode=30;break t}if(h>>>=b,p-=b,j>(b=o-a)){if((b=j-b)>f&&r.sane){t.msg="invalid distance too far back",r.mode=30;break t}if(O=0,x=d,0===l){if(O+=u-b,b<_){_-=b;do{k[o++]=d[O++]}while(--b);O=o-j,x=k}}else if(l<b){if(O+=u+l-b,(b-=l)<_){_-=b;do{k[o++]=d[O++]}while(--b);if(O=0,l<_){_-=b=l;do{k[o++]=d[O++]}while(--b);O=o-j,x=k}}}else if(O+=l-b,b<_){_-=b;do{k[o++]=d[O++]}while(--b);O=o-j,x=k}for(;_>2;)k[o++]=x[O++],k[o++]=x[O++],k[o++]=x[O++],_-=3;_&&(k[o++]=x[O++],_>1&&(k[o++]=x[O++]))}else{O=o-j;do{k[o++]=k[O++],k[o++]=k[O++],k[o++]=k[O++],_-=3}while(_>2);_&&(k[o++]=k[O++],_>1&&(k[o++]=k[O++]))}break}}break}}while(n<i&&o<s);n-=_=p>>3,h&=(1<<(p-=_<<3))-1,t.next_in=n,t.next_out=o,t.avail_in=n<i?i-n+5:5-(n-i),t.avail_out=o<s?s-o+257:257-(o-s),r.hold=h,r.bits=p}},function(t,e,r){"use strict";var n=r(31),i=[3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258,0,0],o=[16,16,16,16,16,16,16,16,17,17,17,17,18,18,18,18,19,19,19,19,20,20,20,20,21,21,21,21,16,72,78],a=[1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0],s=[16,16,16,16,17,17,18,18,19,19,20,20,21,21,22,22,23,23,24,24,25,25,26,26,27,27,28,28,29,29,64,64];t.exports=function(t,e,r,c,u,f,l,d){var h,p,y,g,m,v,w,b,_,j=d.bits,O=0,x=0,P=0,k=0,E=0,S=0,A=0,R=0,$=0,B=0,T=null,I=0,C=new n.Buf16(16),U=new n.Buf16(16),D=null,z=0;for(O=0;O<=15;O++)C[O]=0;for(x=0;x<c;x++)C[e[r+x]]++;for(E=j,k=15;k>=1&&0===C[k];k--);if(E>k&&(E=k),0===k)return u[f++]=20971520,u[f++]=20971520,d.bits=1,0;for(P=1;P<k&&0===C[P];P++);for(E<P&&(E=P),R=1,O=1;O<=15;O++)if(R<<=1,(R-=C[O])<0)return-1;if(R>0&&(0===t||1!==k))return-1;for(U[1]=0,O=1;O<15;O++)U[O+1]=U[O]+C[O];for(x=0;x<c;x++)0!==e[r+x]&&(l[U[e[r+x]]++]=x);if(0===t?(T=D=l,v=19):1===t?(T=i,I-=257,D=o,z-=257,v=256):(T=a,D=s,v=-1),B=0,x=0,O=P,m=f,S=E,A=0,y=-1,g=($=1<<E)-1,1===t&&$>852||2===t&&$>592)return 1;for(;;){w=O-A,l[x]<v?(b=0,_=l[x]):l[x]>v?(b=D[z+l[x]],_=T[I+l[x]]):(b=96,_=0),h=1<<O-A,P=p=1<<S;do{u[m+(B>>A)+(p-=h)]=w<<24|b<<16|_|0}while(0!==p);for(h=1<<O-1;B&h;)h>>=1;if(0!==h?(B&=h-1,B+=h):B=0,x++,0==--C[O]){if(O===k)break;O=e[r+l[x]]}if(O>E&&(B&g)!==y){for(0===A&&(A=E),m+=P,R=1<<(S=O-A);S+A<k&&!((R-=C[S+A])<=0);)S++,R<<=1;if($+=1<<S,1===t&&$>852||2===t&&$>592)return 1;u[y=B&g]=E<<24|S<<16|m-f|0}}return 0!==B&&(u[m+B]=O-A<<24|64<<16|0),d.bits=E,0}},function(t,e,r){"use strict";t.exports=function(){this.text=0,this.time=0,this.xflags=0,this.os=0,this.extra=null,this.extra_len=0,this.name="",this.comment="",this.hcrc=0,this.done=!1}},function(t,e){t.exports=function(t,e){var r,n,i=t,o=e,a=i.length,s=o.length,c=!1,u=null,f=a+1,l=[],d=[],h=[],p="",y=function(t,e,r){return{x:t,y:e,k:r}},g=function(t,e){return{elem:t,t:e}},m=function(t,e,r){var n,c,u;for(n=e>r?l[t-1+f]:l[t+1+f],c=(u=Math.max(e,r))-t;c<a&&u<s&&i[c]===o[u];)++c,++u;return l[t+f]=d.length,d[d.length]=new y(c,u,n),u};return a>=s&&(r=i,n=a,i=o,o=r,a=s,s=n,c=!0,f=a+1),{SES_DELETE:-1,SES_COMMON:0,SES_ADD:1,editdistance:function(){return u},getlcs:function(){return p},getses:function(){return h},compose:function(){var t,e,r,n,v,w,b,_;for(t=s-a,e=a+s+3,r={},b=0;b<e;++b)r[b]=-1,l[b]=-1;n=-1;do{for(_=-++n;_<=t-1;++_)r[_+f]=m(_,r[_-1+f]+1,r[_+1+f]);for(_=t+n;_>=t+1;--_)r[_+f]=m(_,r[_-1+f]+1,r[_+1+f]);r[t+f]=m(t,r[t-1+f]+1,r[t+1+f])}while(r[t+f]!==s);for(u=t+2*n,v=l[t+f],w=[];-1!==v;)w[w.length]=new y(d[v].x,d[v].y,null),v=d[v].k;!function(t){var e,r,n;for(1,e=r=0,n=t.length-1;n>=0;--n)for(;e<t[n].x||r<t[n].y;)t[n].y-t[n].x>r-e?(h[h.length]=new g(o[r],c?-1:1),++r):t[n].y-t[n].x<r-e?(h[h.length]=new g(i[e],c?1:-1),++e):(h[h.length]=new g(i[e],0),p+=i[e],++e,++r)}(w)}}}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return s}));var n=r(165),i=r(0);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({object:e}){try{Object(i.a)("object",e),e="string"==typeof e?t.from(e,"utf8"):t.from(e);const r="blob",{oid:o,object:a}=yield Object(n.a)({type:"blob",format:"content",object:e});return{oid:o,type:r,object:new Uint8Array(a),format:"wrapped"}}catch(t){throw t.caller="git.hashBlob",t}}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return d}));var n=r(17),i=r(2),o=r(18),a=r(14),s=r(12),c=r(15),u=r(16);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:e,dir:r,gitdir:f=Object(u.join)(r,".git"),type:l,object:d,format:h="parsed",oid:p,encoding:y}){try{const r=new i.a(e);if("parsed"===h){switch(l){case"commit":d=a.a.from(d).toObject();break;case"tree":d=s.a.from(d).toObject();break;case"blob":d=t.from(d,y);break;case"tag":d=o.a.from(d).toObject();break;default:throw new n.a(p||"",l,"blob|commit|tag|tree")}h="content"}return p=yield Object(c.a)({fs:r,gitdir:f,type:l,object:d,oid:p,format:h})}catch(t){throw t.caller="git.writeObject",t}}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";function n(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function i(t){return function(){var e=this,r=arguments;return new Promise((function(i,o){var a=t.apply(e,r);function s(t){n(a,i,o,s,c,"next",t)}function c(t){n(a,i,o,s,c,"throw",t)}s(void 0)}))}}function o(t){return a.apply(this,arguments)}function a(){return(a=i((function*({fs:t,gitdir:e,oid:r}){const n=`objects/${r.slice(0,2)}/${r.slice(2)}`;return t.exists(`${e}/${n}`)}))).apply(this,arguments)}var s=r(4),c=r(81),u=r(16);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:t,cache:e,gitdir:r,oid:n,getExternalRefDelta:i}){let o=yield t.readdir(Object(u.join)(r,"objects/pack"));o=o.filter(t=>t.endsWith(".idx"));for(const a of o){const o=`${r}/objects/pack/${a}`,u=yield Object(c.a)({fs:t,cache:e,filename:o,getExternalRefDelta:i});if(u.error)throw new s.a(u.error);if(u.offsets.has(n))return!0}return!1}))).apply(this,arguments)}var p=r(7);function y(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function g(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){y(o,n,i,a,s,"next",t)}function s(t){y(o,n,i,a,s,"throw",t)}a(void 0)}))}}function m(t){return v.apply(this,arguments)}function v(){return(v=g((function*({fs:t,cache:e,gitdir:r,oid:n,format:i="content"}){const a=n=>Object(p.a)({fs:t,cache:e,gitdir:r,oid:n});let s=yield o({fs:t,gitdir:r,oid:n});return s||(s=yield d({fs:t,cache:e,gitdir:r,oid:n,getExternalRefDelta:a})),s}))).apply(this,arguments)}r.d(e,"a",(function(){return m}))},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return d}));var n=r(11),i=r(13),o=r(69),a=r(16),s=r(34),c=r(19),u=r(25);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}class d{constructor({fs:t,dir:e,gitdir:r,cache:n}){this.fs=t,this.cache=n,this.dir=e,this.gitdir=r,this.config=null;const i=this;this.ConstructEntry=class{constructor(t){this._fullpath=t,this._type=!1,this._mode=!1,this._stat=!1,this._content=!1,this._oid=!1}type(){var t=this;return l((function*(){return i.type(t)}))()}mode(){var t=this;return l((function*(){return i.mode(t)}))()}stat(){var t=this;return l((function*(){return i.stat(t)}))()}content(){var t=this;return l((function*(){return i.content(t)}))()}oid(){var t=this;return l((function*(){return i.oid(t)}))()}}}readdir(t){var e=this;return l((function*(){const r=t._fullpath,{fs:n,dir:i}=e,o=yield n.readdir(Object(a.join)(i,r));return null===o?null:o.map(t=>Object(a.join)(r,t))}))()}type(t){return l((function*(){return!1===t._type&&(yield t.stat()),t._type}))()}mode(t){return l((function*(){return!1===t._mode&&(yield t.stat()),t._mode}))()}stat(t){var e=this;return l((function*(){if(!1===t._stat){const{fs:r,dir:n}=e;let i=yield r.lstat(`${n}/${t._fullpath}`);if(!i)throw new Error(`ENOENT: no such file or directory, lstat '${t._fullpath}'`);let o=i.isDirectory()?"tree":"blob";"blob"!==o||i.isFile()||i.isSymbolicLink()||(o="special"),t._type=o,i=Object(s.a)(i),t._mode=i.mode,-1===i.size&&t._actualSize&&(i.size=t._actualSize),t._stat=i}return t._stat}))()}content(t){var e=this;return l((function*(){if(!1===t._content){const{fs:r,dir:n,gitdir:i}=e;if("tree"===(yield t.type()))t._content=void 0;else{const o=yield e._getGitConfig(r,i),a=yield o.get("core.autocrlf"),s=yield r.read(`${n}/${t._fullpath}`,{autocrlf:a});t._actualSize=s.length,t._stat&&-1===t._stat.size&&(t._stat.size=t._actualSize),t._content=new Uint8Array(s)}}return t._content}))()}oid(e){var r=this;return l((function*(){if(!1===e._oid){const n=r,{fs:a,gitdir:s,cache:f}=r;let d;yield i.a.acquire({fs:a,gitdir:s,cache:f},function(){var r=l((function*(r){const i=r.entriesMap.get(e._fullpath),f=yield e.stat(),l=yield n._getGitConfig(a,s),h=yield l.get("core.filemode"),p=void 0===t||!("win32"===t.platform);if(!i||Object(o.a)(f,i,h,p)){const t=yield e.content();void 0===t?d=void 0:(d=yield Object(c.a)(u.a.wrap({type:"blob",object:t})),!i||d!==i.oid||h&&f.mode!==i.mode||!Object(o.a)(f,i,h,p)||r.insert({filepath:e._fullpath,stats:f,oid:d}))}else d=i.oid}));return function(t){return r.apply(this,arguments)}}()),e._oid=d}return e._oid}))()}_getGitConfig(t,e){var r=this;return l((function*(){return r.config?r.config:(r.config=yield n.a.get({fs:t,gitdir:e}),r.config)}))()}}}).call(this,r(92))},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return d}));var n=r(95),i=r(54),o=r(89),a=r(26),s=r(8),c=r(3),u=r(15);function f(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function l(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){f(o,n,i,a,s,"next",t)}function s(t){f(o,n,i,a,s,"throw",t)}a(void 0)}))}}function d(t){return h.apply(this,arguments)}function h(){return(h=l((function*({fs:e,cache:r,onSign:f,gitdir:l,ref:d,oid:h,note:p,force:y,author:g,committer:m,signingKey:v}){let w;try{w=yield c.a.resolve({gitdir:l,fs:e,ref:d})}catch(t){if(!(t instanceof s.a))throw t}let b=(yield Object(i.a)({fs:e,cache:r,gitdir:l,oid:w||"4b825dc642cb6eb9a060e54bf8d69288fbee4904"})).tree;if(y)b=b.filter(t=>t.path!==h);else for(const t of b)if(t.path===h)throw new a.a("note",h);"string"==typeof p&&(p=t.from(p,"utf8"));const _=yield Object(u.a)({fs:e,gitdir:l,type:"blob",object:p,format:"content"});b.push({mode:"100644",path:h,oid:_,type:"blob"});const j=yield Object(o.a)({fs:e,gitdir:l,tree:b});return yield Object(n.a)({fs:e,cache:r,onSign:f,gitdir:l,ref:d,tree:j,parent:w&&[w],message:"Note added by 'isomorphic-git addNote'\\n",author:g,committer:m,signingKey:v})}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";function n(t){return"5041434b0000000200000000"===t.slice(0,12).toString("hex")}r.d(e,"a",(function(){return n}))},function(t,e,r){"use strict";r.d(e,"a",(function(){return s}));var n=r(25),i=r(19);function o(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function a(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var a=t.apply(e,r);function s(t){o(a,n,i,s,c,"next",t)}function c(t){o(a,n,i,s,c,"throw",t)}s(void 0)}))}}function s(t){return c.apply(this,arguments)}function c(){return(c=a((function*({type:t,object:e,format:r="content",oid:o}){return"deflated"!==r&&("wrapped"!==r&&(e=n.a.wrap({type:t,object:e})),o=yield Object(i.a)(e)),{oid:o,object:e}}))).apply(this,arguments)}},function(t,e,r){"use strict";(function(t){r.d(e,"a",(function(){return c}));var n=r(52),i=r(16),o=r(112);function a(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function s(t){a(o,n,i,s,c,"next",t)}function c(t){a(o,n,i,s,c,"throw",t)}s(void 0)}))}}function c(t){return u.apply(this,arguments)}function u(){return(u=s((function*({fs:e,cache:r,gitdir:a,oids:s,write:c}){const u=yield Object(o.a)({fs:e,cache:r,gitdir:a,oids:s}),f=t.from(yield Object(n.a)(u)),l=`pack-${f.slice(-20).toString("hex")}.pack`;return c?(yield e.write(Object(i.join)(a,`objects/pack/${l}`),f),{filename:l}):{filename:l,packfile:new Uint8Array(f)}}))).apply(this,arguments)}}).call(this,r(10).Buffer)},function(t,e,r){"use strict";r.r(e);var n=r(13),i=r(38),o=r(107),a=r(4);var s=r(34);function c(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function u(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){c(o,n,i,a,s,"next",t)}function s(t){c(o,n,i,a,s,"throw",t)}a(void 0)}))}}class f{constructor({fs:t,gitdir:e,cache:r}){this.treePromise=n.a.acquire({fs:t,gitdir:e,cache:r},function(){var t=u((function*(t){return Object(o.a)(t.entries)}));return function(e){return t.apply(this,arguments)}}());const i=this;this.ConstructEntry=class{constructor(t){this._fullpath=t,this._type=!1,this._mode=!1,this._stat=!1,this._oid=!1}type(){var t=this;return u((function*(){return i.type(t)}))()}mode(){var t=this;return u((function*(){return i.mode(t)}))()}stat(){var t=this;return u((function*(){return i.stat(t)}))()}content(){var t=this;return u((function*(){return i.content(t)}))()}oid(){var t=this;return u((function*(){return i.oid(t)}))()}}}readdir(t){var e=this;return u((function*(){const r=t._fullpath,n=(yield e.treePromise).get(r);if(!n)return null;if("blob"===n.type)return null;if("tree"!==n.type)throw new Error(`ENOTDIR: not a directory, scandir '${r}'`);const o=n.children.map(t=>t.fullpath);return o.sort(i.a),o}))()}type(t){return u((function*(){return!1===t._type&&(yield t.stat()),t._type}))()}mode(t){return u((function*(){return!1===t._mode&&(yield t.stat()),t._mode}))()}stat(t){var e=this;return u((function*(){if(!1===t._stat){const r=(yield e.treePromise).get(t._fullpath);if(!r)throw new Error(`ENOENT: no such file or directory, lstat '${t._fullpath}'`);const n="tree"===r.type?{}:Object(s.a)(r.metadata);t._type="tree"===r.type?"tree":function(t){switch(t){case 16384:return"tree";case 33188:case 33261:case 40960:return"blob";case 57344:return"commit"}throw new a.a(`Unexpected GitTree entry mode: ${t.toString(8)}`)}(n.mode),t._mode=n.mode,"tree"===r.type?t._stat=void 0:t._stat=n}return t._stat}))()}content(t){return u((function*(){}))()}oid(t){var e=this;return u((function*(){if(!1===t._oid){const r=(yield e.treePromise).get(t._fullpath);t._oid=r.metadata.oid}return t._oid}))()}}var l=r(37);function d(){const t=Object.create(null);return Object.defineProperty(t,l.a,{value:function({fs:t,gitdir:e,cache:r}){return new f({fs:t,gitdir:e,cache:r})}}),Object.freeze(t),t}var h=r(22),p=r(162);function y(){const t=Object.create(null);return Object.defineProperty(t,l.a,{value:function({fs:t,dir:e,gitdir:r,cache:n}){return new p.a({fs:t,dir:e,gitdir:r,cache:n})}}),Object.freeze(t),t}var g=r(30),m=r(104),v=r(2),w=r(0),b=r(16),_=r(53);function j(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function O(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){j(o,n,i,a,s,"next",t)}function s(t){j(o,n,i,a,s,"throw",t)}a(void 0)}))}}function x(t){return P.apply(this,arguments)}function P(){return(P=O((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),commit:i="HEAD",cache:o={}}){try{Object(w.a)("fs",t),Object(w.a)("dir",e),Object(w.a)("gitdir",r);const s=new v.a(t),c=[Object(h.a)({ref:i}),y(),d()];let u=[];yield n.a.acquire({fs:s,gitdir:r,cache:o},function(){var t=O((function*(t){u=t.unmergedPaths}));return function(e){return t.apply(this,arguments)}}());const f=yield Object(g.a)({fs:s,cache:o,dir:e,gitdir:r,trees:c,map:(a=O((function*(t,[e,r,n]){const i=!(yield Object(_.a)(r,n)),o=u.includes(t),a=!(yield Object(_.a)(n,e));if(i||o)return e?{path:t,mode:yield e.mode(),oid:yield e.oid(),type:yield e.type(),content:yield e.content()}:void 0;if(a)return!1;throw new m.a(t)})),function(t,e){return a.apply(this,arguments)})});yield n.a.acquire({fs:s,gitdir:r,cache:o},function(){var t=O((function*(t){for(const r of f)if(!1!==r)if(r){if("blob"===r.type){const n=(new TextDecoder).decode(r.content);yield s.write(`${e}/${r.path}`,n,{mode:r.mode}),t.insert({filepath:r.path,oid:r.oid,stage:0})}}else yield s.rmdir(`${e}/${r.path}`,{recursive:!0}),t.delete({filepath:r.path})}));return function(e){return t.apply(this,arguments)}}())}catch(t){throw t.caller="git.abortMerge",t}var a}))).apply(this,arguments)}var k=r(103),E=r(8),S=r(11),A=r(42),R=r(15);function $(t){let e;for(;~(e=t.indexOf(92));)t[e]=47;return t}function B(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function T(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){B(o,n,i,a,s,"next",t)}function s(t){B(o,n,i,a,s,"throw",t)}a(void 0)}))}}function I(t){return C.apply(this,arguments)}function C(){return(C=T((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:i,cache:o={},force:a=!1,parallel:s=!0}){try{Object(w.a)("fs",t),Object(w.a)("dir",e),Object(w.a)("gitdir",r),Object(w.a)("filepath",i);const c=new v.a(t);yield n.a.acquire({fs:c,gitdir:r,cache:o},function(){var t=T((function*(t){const n=yield S.a.get({fs:c,gitdir:r}),o=yield n.get("core.autocrlf");return U({dir:e,gitdir:r,fs:c,filepath:i,index:t,force:a,parallel:s,autocrlf:o})}));return function(e){return t.apply(this,arguments)}}())}catch(t){throw t.caller="git.add",t}}))).apply(this,arguments)}function U(t){return D.apply(this,arguments)}function D(){return(D=T((function*({dir:t,gitdir:e,fs:r,filepath:n,index:i,force:o,parallel:a,autocrlf:s}){const c=(n=Array.isArray(n)?n:[n]).map(function(){var n=T((function*(n){if(!o){if(yield A.a.isIgnored({fs:r,dir:t,gitdir:e,filepath:n}))return}const c=yield r.lstat(Object(b.join)(t,n));if(!c)throw new E.a(n);if(c.isDirectory()){const c=yield r.readdir(Object(b.join)(t,n));if(a){const u=c.map(c=>U({dir:t,gitdir:e,fs:r,filepath:[Object(b.join)(n,c)],index:i,force:o,parallel:a,autocrlf:s}));yield Promise.all(u)}else for(const u of c)yield U({dir:t,gitdir:e,fs:r,filepath:[Object(b.join)(n,u)],index:i,force:o,parallel:a,autocrlf:s})}else{const o=c.isSymbolicLink()?yield r.readlink(Object(b.join)(t,n)).then($):yield r.read(Object(b.join)(t,n),{autocrlf:s});if(null===o)throw new E.a(n);const a=yield Object(R.a)({fs:r,gitdir:e,type:"blob",object:o});i.insert({filepath:n,stats:c,oid:a})}}));return function(t){return n.apply(this,arguments)}}()),u=yield Promise.allSettled(c),f=u.filter(t=>"rejected"===t.status).map(t=>t.reason);if(f.length>1)throw new k.a(f);if(1===f.length)throw f[0];return u.filter(t=>"fulfilled"===t.status&&t.value).map(t=>t.value)}))).apply(this,arguments)}var z=r(163),N=r(21),M=r(29),F=r(43);function H(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function L(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){H(o,n,i,a,s,"next",t)}function s(t){H(o,n,i,a,s,"throw",t)}a(void 0)}))}}function q(t){return G.apply(this,arguments)}function G(){return(G=L((function*({fs:t,onSign:e,dir:r,gitdir:n=Object(b.join)(r,".git"),ref:i="refs/notes/commits",oid:o,note:a,force:s,author:c,committer:u,signingKey:f,cache:l={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",n),Object(w.a)("oid",o),Object(w.a)("note",a),f&&Object(w.a)("onSign",e);const r=new v.a(t),d=yield Object(M.a)({fs:r,gitdir:n,author:c});if(!d)throw new N.a("author");const h=yield Object(F.a)({fs:r,gitdir:n,author:d,committer:u});if(!h)throw new N.a("committer");return yield Object(z.a)({fs:new v.a(r),cache:l,onSign:e,gitdir:n,ref:i,oid:o,note:a,force:s,author:d,committer:h,signingKey:f})}catch(t){throw t.caller="git.addNote",t}}))).apply(this,arguments)}var Y=r(45),W=r.n(Y),Z=r(26),K=r(28);function V(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function X(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){V(o,n,i,a,s,"next",t)}function s(t){V(o,n,i,a,s,"throw",t)}a(void 0)}))}}function J(t){return Q.apply(this,arguments)}function Q(){return(Q=X((function*({fs:t,gitdir:e,remote:r,url:n,force:i}){if(r!==W.a.clean(r))throw new K.a(r,W.a.clean(r));const o=yield S.a.get({fs:t,gitdir:e});if(!i){if((yield o.getSubsections("remote")).includes(r)&&n!==(yield o.get(`remote.${r}.url`)))throw new Z.a("remote",r)}yield o.set(`remote.${r}.url`,n),yield o.set(`remote.${r}.fetch`,`+refs/heads/*:refs/remotes/${r}/*`),yield S.a.save({fs:t,gitdir:e,config:o})}))).apply(this,arguments)}function tt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function et(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){tt(o,n,i,a,s,"next",t)}function s(t){tt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function rt(t){return nt.apply(this,arguments)}function nt(){return(nt=et((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),remote:n,url:i,force:o=!1}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("remote",n),Object(w.a)("url",i),yield J({fs:new v.a(t),gitdir:r,remote:n,url:i,force:o})}catch(t){throw t.caller="git.addRemote",t}}))).apply(this,arguments)}var it=r(3),ot=r(18),at=r(7);function st(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ct(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){st(o,n,i,a,s,"next",t)}function s(t){st(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ut(t){return ft.apply(this,arguments)}function ft(){return(ft=ct((function*({fs:t,cache:e,onSign:r,gitdir:n,ref:i,tagger:o,message:a=i,gpgsig:s,object:c,signingKey:u,force:f=!1}){if(i=i.startsWith("refs/tags/")?i:`refs/tags/${i}`,!f&&(yield it.a.exists({fs:t,gitdir:n,ref:i})))throw new Z.a("tag",i);const l=yield it.a.resolve({fs:t,gitdir:n,ref:c||"HEAD"}),{type:d}=yield Object(at.a)({fs:t,cache:e,gitdir:n,oid:l});let h=ot.a.from({object:l,type:d,tag:i.replace("refs/tags/",""),tagger:o,message:a,gpgsig:s});u&&(h=yield ot.a.sign(h,r,u));const p=yield Object(R.a)({fs:t,gitdir:n,type:"tag",object:h.toObject()});yield it.a.writeRef({fs:t,gitdir:n,ref:i,value:p})}))).apply(this,arguments)}function lt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function dt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){lt(o,n,i,a,s,"next",t)}function s(t){lt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ht(t){return pt.apply(this,arguments)}function pt(){return(pt=dt((function*({fs:t,onSign:e,dir:r,gitdir:n=Object(b.join)(r,".git"),ref:i,tagger:o,message:a=i,gpgsig:s,object:c,signingKey:u,force:f=!1,cache:l={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",n),Object(w.a)("ref",i),u&&Object(w.a)("onSign",e);const r=new v.a(t),d=yield Object(M.a)({fs:r,gitdir:n,author:o});if(!d)throw new N.a("tagger");return yield ut({fs:r,cache:l,onSign:e,gitdir:n,ref:i,tagger:d,message:a,gpgsig:s,object:c,signingKey:u,force:f})}catch(t){throw t.caller="git.annotatedTag",t}}))).apply(this,arguments)}function yt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function gt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){yt(o,n,i,a,s,"next",t)}function s(t){yt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function mt(t){return vt.apply(this,arguments)}function vt(){return(vt=gt((function*({fs:t,gitdir:e,ref:r,object:n,checkout:i=!1,force:o=!1}){if(r!==W.a.clean(r))throw new K.a(r,W.a.clean(r));const a=`refs/heads/${r}`;if(!o){if(yield it.a.exists({fs:t,gitdir:e,ref:a}))throw new Z.a("branch",r,!1)}let s;try{s=yield it.a.resolve({fs:t,gitdir:e,ref:n||"HEAD"})}catch(t){}s&&(yield it.a.writeRef({fs:t,gitdir:e,ref:a,value:s})),i&&(yield it.a.writeSymbolicRef({fs:t,gitdir:e,ref:"HEAD",value:a}))}))).apply(this,arguments)}function wt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function bt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){wt(o,n,i,a,s,"next",t)}function s(t){wt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function _t(t){return jt.apply(this,arguments)}function jt(){return(jt=bt((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,object:i,checkout:o=!1,force:a=!1}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),yield mt({fs:new v.a(t),gitdir:r,ref:n,object:i,checkout:o,force:a})}catch(t){throw t.caller="git.branch",t}}))).apply(this,arguments)}var Ot=r(98),xt=r(99),Pt=r(114);const kt=(t,e)=>"."===t||null==e||0===e.length||"."===e||(e.length>=t.length?e.startsWith(t):t.startsWith(e));function Et(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function St(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Et(o,n,i,a,s,"next",t)}function s(t){Et(o,n,i,a,s,"throw",t)}a(void 0)}))}}function At(t){return Rt.apply(this,arguments)}function Rt(){return(Rt=St((function*({fs:t,cache:e,onProgress:r,onPostCheckout:i,dir:o,gitdir:s,remote:c,ref:u,filepaths:f,noCheckout:l,noUpdateHead:d,dryRun:h,force:p,track:y=!0}){let g,m;if(i)try{g=yield it.a.resolve({fs:t,gitdir:s,ref:"HEAD"})}catch(t){g="0000000000000000000000000000000000000000"}try{m=yield it.a.resolve({fs:t,gitdir:s,ref:u})}catch(e){if("HEAD"===u)throw e;const r=`${c}/${u}`;if(m=yield it.a.resolve({fs:t,gitdir:s,ref:r}),y){const e=yield S.a.get({fs:t,gitdir:s});yield e.set(`branch.${u}.remote`,c),yield e.set(`branch.${u}.merge`,`refs/heads/${u}`),yield S.a.save({fs:t,gitdir:s,config:e})}yield it.a.writeRef({fs:t,gitdir:s,ref:`refs/heads/${u}`,value:m})}if(!l){let c;try{c=yield $t({fs:t,cache:e,onProgress:r,dir:o,gitdir:s,ref:u,force:p,filepaths:f})}catch(t){throw t instanceof E.a&&t.data.what===m?new xt.a(u,m):t}const l=c.filter(([t])=>"conflict"===t).map(([t,e])=>e);if(l.length>0)throw new Ot.a(l);const d=c.filter(([t])=>"error"===t).map(([t,e])=>e);if(d.length>0)throw new a.a(d.join(", "));if(h)return void(i&&(yield i({previousHead:g,newHead:m,type:null!=f&&f.length>0?"file":"branch"})));let y=0;const v=c.length;yield n.a.acquire({fs:t,gitdir:s,cache:e},function(){var e=St((function*(e){yield Promise.all(c.filter(([t])=>"delete"===t||"delete-index"===t).map(function(){var n=St((function*([n,i]){const a=`${o}/${i}`;"delete"===n&&(yield t.rm(a)),e.delete({filepath:i}),r&&(yield r({phase:"Updating workdir",loaded:++y,total:v}))}));return function(t){return n.apply(this,arguments)}}()))}));return function(t){return e.apply(this,arguments)}}()),yield n.a.acquire({fs:t,gitdir:s,cache:e},function(){var e=St((function*(e){for(const[n,i]of c)if("rmdir"===n||"rmdir-index"===n){const a=`${o}/${i}`;try{"rmdir-index"===n&&e.delete({filepath:i}),yield t.rmdir(a),r&&(yield r({phase:"Updating workdir",loaded:++y,total:v}))}catch(t){if("ENOTEMPTY"!==t.code)throw t;console.log(`Did not delete ${i} because directory is not empty`)}}}));return function(t){return e.apply(this,arguments)}}()),yield Promise.all(c.filter(([t])=>"mkdir"===t||"mkdir-index"===t).map(function(){var e=St((function*([e,n]){const i=`${o}/${n}`;yield t.mkdir(i),r&&(yield r({phase:"Updating workdir",loaded:++y,total:v}))}));return function(t){return e.apply(this,arguments)}}())),yield n.a.acquire({fs:t,gitdir:s,cache:e},function(){var n=St((function*(n){yield Promise.all(c.filter(([t])=>"create"===t||"create-index"===t||"update"===t||"mkdir-index"===t).map(function(){var i=St((function*([i,c,u,f,l]){const d=`${o}/${c}`;try{if("create-index"!==i&&"mkdir-index"!==i){const{object:r}=yield Object(at.a)({fs:t,cache:e,gitdir:s,oid:u});if(l&&(yield t.rm(d)),33188===f)yield t.write(d,r);else if(33261===f)yield t.write(d,r,{mode:511});else{if(40960!==f)throw new a.a(`Invalid mode 0o${f.toString(8)} detected in blob ${u}`);yield t.writelink(d,r)}}const o=yield t.lstat(d);33261===f&&(o.mode=493),"mkdir-index"===i&&(o.mode=57344),n.insert({filepath:c,stats:o,oid:u}),r&&(yield r({phase:"Updating workdir",loaded:++y,total:v}))}catch(t){console.log(t)}}));return function(t){return i.apply(this,arguments)}}()))}));return function(t){return n.apply(this,arguments)}}()),i&&(yield i({previousHead:g,newHead:m,type:null!=f&&f.length>0?"file":"branch"}))}if(!d){const e=yield it.a.expand({fs:t,gitdir:s,ref:u});e.startsWith("refs/heads")?yield it.a.writeSymbolicRef({fs:t,gitdir:s,ref:"HEAD",value:e}):yield it.a.writeRef({fs:t,gitdir:s,ref:"HEAD",value:m})}}))).apply(this,arguments)}function $t(t){return Bt.apply(this,arguments)}function Bt(){return(Bt=St((function*({fs:t,cache:e,onProgress:r,dir:n,gitdir:i,ref:o,force:a,filepaths:s}){let c=0;return Object(g.a)({fs:t,cache:e,dir:n,gitdir:i,trees:[Object(h.a)({ref:o}),y(),d()],map:(f=St((function*(t,[e,n,i]){if("."!==t){if(s&&!s.some(e=>kt(t,e)))return null;switch(r&&(yield r({phase:"Analyzing workdir",loaded:++c})),[!!i,!!e,!!n].map(Number).join("")){case"000":return;case"001":return a&&s&&s.includes(t)?["delete",t]:void 0;case"010":switch(yield e.type()){case"tree":return["mkdir",t];case"blob":return["create",t,yield e.oid(),yield e.mode()];case"commit":return["mkdir-index",t,yield e.oid(),yield e.mode()];default:return["error",`new entry Unhandled type ${yield e.type()}`]}case"011":switch(`${yield e.type()}-${yield n.type()}`){case"tree-tree":return;case"tree-blob":case"blob-tree":return["conflict",t];case"blob-blob":return(yield e.oid())!==(yield n.oid())?a?["update",t,yield e.oid(),yield e.mode(),(yield e.mode())!==(yield n.mode())]:["conflict",t]:(yield e.mode())!==(yield n.mode())?a?["update",t,yield e.oid(),yield e.mode(),!0]:["conflict",t]:["create-index",t,yield e.oid(),yield e.mode()];case"commit-tree":return;case"commit-blob":return["conflict",t];default:return["error",`new entry Unhandled type ${e.type}`]}case"100":return["delete-index",t];case"101":switch(yield i.type()){case"tree":return["rmdir",t];case"blob":return(yield i.oid())!==(yield n.oid())?a?["delete",t]:["conflict",t]:["delete",t];case"commit":return["rmdir-index",t];default:return["error",`delete entry Unhandled type ${yield i.type()}`]}case"110":case"111":switch(`${yield i.type()}-${yield e.type()}`){case"tree-tree":return;case"blob-blob":if((yield i.oid())===(yield e.oid())&&(yield i.mode())===(yield e.mode())&&!a)return;if(n){if((yield n.oid())!==(yield i.oid())&&(yield n.oid())!==(yield e.oid()))return a?["update",t,yield e.oid(),yield e.mode(),(yield e.mode())!==(yield n.mode())]:["conflict",t]}else if(a)return["update",t,yield e.oid(),yield e.mode(),(yield e.mode())!==(yield i.mode())];return(yield e.mode())!==(yield i.mode())?["update",t,yield e.oid(),yield e.mode(),!0]:(yield e.oid())!==(yield i.oid())?["update",t,yield e.oid(),yield e.mode(),!1]:void 0;case"tree-blob":return["update-dir-to-blob",t,yield e.oid()];case"blob-tree":return["update-blob-to-tree",t];case"commit-commit":return["mkdir-index",t,yield e.oid(),yield e.mode()];default:return["error",`update entry Unhandled type ${yield i.type()}-${yield e.type()}`]}}}})),function(t,e){return f.apply(this,arguments)}),reduce:(u=St((function*(t,e){return e=Object(Pt.a)(e),t?t&&"rmdir"===t[0]?(e.push(t),e):(e.unshift(t),e):e})),function(t,e){return u.apply(this,arguments)})});var u,f}))).apply(this,arguments)}function Tt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function It(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Tt(o,n,i,a,s,"next",t)}function s(t){Tt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ct(t){return Ut.apply(this,arguments)}function Ut(){return(Ut=It((function*({fs:t,onProgress:e,onPostCheckout:r,dir:n,gitdir:i=Object(b.join)(n,".git"),remote:o="origin",ref:a,filepaths:s,noCheckout:c=!1,noUpdateHead:u=void 0===a,dryRun:f=!1,force:l=!1,track:d=!0,cache:h={}}){try{Object(w.a)("fs",t),Object(w.a)("dir",n),Object(w.a)("gitdir",i);const p=a||"HEAD";return yield At({fs:new v.a(t),cache:h,onProgress:e,onPostCheckout:r,dir:n,gitdir:i,remote:o,ref:p,filepaths:s,noCheckout:c,noUpdateHead:u,dryRun:f,force:l,track:d})}catch(t){throw t.caller="git.checkout",t}}))).apply(this,arguments)}var Dt=r(118);function zt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Nt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){zt(o,n,i,a,s,"next",t)}function s(t){zt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Mt(t){return Ft.apply(this,arguments)}function Ft(){return(Ft=Nt((function*({fs:t,bare:e=!1,dir:r,gitdir:n=(e?r:Object(b.join)(r,".git")),defaultBranch:i="master"}){if(yield t.exists(n+"/config"))return;let o=["hooks","info","objects/info","objects/pack","refs/heads","refs/tags"];o=o.map(t=>n+"/"+t);for(const e of o)yield t.mkdir(e);yield t.write(n+"/config","[core]\\n\\trepositoryformatversion = 0\\n\\tfilemode = false\\n"+`\\tbare = ${e}\\n`+(e?"":"\\tlogallrefupdates = true\\n")+"\\tsymlinks = false\\n\\tignorecase = true\\n"),yield t.write(n+"/HEAD",`ref: refs/heads/${i}\\n`)}))).apply(this,arguments)}function Ht(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Lt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ht(o,n,i,a,s,"next",t)}function s(t){Ht(o,n,i,a,s,"throw",t)}a(void 0)}))}}function qt(t){return Gt.apply(this,arguments)}function Gt(){return(Gt=Lt((function*({fs:t,cache:e,http:r,onProgress:n,onMessage:i,onAuth:o,onAuthSuccess:a,onAuthFailure:s,onPostCheckout:c,dir:u,gitdir:f,url:l,corsProxy:d,ref:h,remote:p,depth:y,since:g,exclude:m,relative:v,singleBranch:w,noCheckout:b,noTags:_,headers:j}){try{if(yield Mt({fs:t,gitdir:f}),yield J({fs:t,gitdir:f,remote:p,url:l,force:!1}),d){const e=yield S.a.get({fs:t,gitdir:f});yield e.set("http.corsProxy",d),yield S.a.save({fs:t,gitdir:f,config:e})}const{defaultBranch:O,fetchHead:x}=yield Object(Dt.a)({fs:t,cache:e,http:r,onProgress:n,onMessage:i,onAuth:o,onAuthSuccess:a,onAuthFailure:s,gitdir:f,ref:h,remote:p,corsProxy:d,depth:y,since:g,exclude:m,relative:v,singleBranch:w,headers:j,tags:!_});if(null===x)return;h=(h=h||O).replace("refs/heads/",""),yield At({fs:t,cache:e,onProgress:n,onPostCheckout:c,dir:u,gitdir:f,ref:h,remote:p,noCheckout:b})}catch(e){throw yield t.rmdir(f,{recursive:!0,maxRetries:10}).catch(()=>{}),e}}))).apply(this,arguments)}function Yt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Wt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Yt(o,n,i,a,s,"next",t)}function s(t){Yt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Zt(t){return Kt.apply(this,arguments)}function Kt(){return(Kt=Wt((function*({fs:t,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,onPostCheckout:s,dir:c,gitdir:u=Object(b.join)(c,".git"),url:f,corsProxy:l,ref:d,remote:h="origin",depth:p,since:y,exclude:g=[],relative:m=!1,singleBranch:_=!1,noCheckout:j=!1,noTags:O=!1,headers:x={},cache:P={}}){try{return Object(w.a)("fs",t),Object(w.a)("http",e),Object(w.a)("gitdir",u),j||Object(w.a)("dir",c),Object(w.a)("url",f),yield qt({fs:new v.a(t),cache:P,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,onPostCheckout:s,dir:c,gitdir:u,url:f,corsProxy:l,ref:d,remote:h,depth:p,since:y,exclude:g,relative:m,singleBranch:_,noCheckout:j,noTags:O,headers:x})}catch(t){throw t.caller="git.clone",t}}))).apply(this,arguments)}var Vt=r(95);function Xt(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Jt(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Xt(o,n,i,a,s,"next",t)}function s(t){Xt(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Qt(t){return te.apply(this,arguments)}function te(){return(te=Jt((function*({fs:t,onSign:e,dir:r,gitdir:n=Object(b.join)(r,".git"),message:i,author:o,committer:a,signingKey:s,amend:c=!1,dryRun:u=!1,noUpdateBranch:f=!1,ref:l,parent:d,tree:h,cache:p={}}){try{Object(w.a)("fs",t),c||Object(w.a)("message",i),s&&Object(w.a)("onSign",e);const r=new v.a(t);return yield Object(Vt.a)({fs:r,cache:p,onSign:e,gitdir:n,message:i,author:o,committer:a,signingKey:s,amend:c,dryRun:u,noUpdateBranch:f,ref:l,parent:d,tree:h})}catch(t){throw t.caller="git.commit",t}}))).apply(this,arguments)}var ee=r(35);function re(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ne(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){re(o,n,i,a,s,"next",t)}function s(t){re(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ie(t){return oe.apply(this,arguments)}function oe(){return(oe=ne((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),fullname:n=!1,test:i=!1}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),yield Object(ee.a)({fs:new v.a(t),gitdir:r,fullname:n,test:i})}catch(t){throw t.caller="git.currentBranch",t}}))).apply(this,arguments)}var ae=r(66);function se(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ce(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){se(o,n,i,a,s,"next",t)}function s(t){se(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ue(t){return fe.apply(this,arguments)}function fe(){return(fe=ce((function*({fs:t,gitdir:e,ref:r}){if(r=r.startsWith("refs/heads/")?r:`refs/heads/${r}`,!(yield it.a.exists({fs:t,gitdir:e,ref:r})))throw new E.a(r);const n=yield it.a.expand({fs:t,gitdir:e,ref:r});if(n===(yield Object(ee.a)({fs:t,gitdir:e,fullname:!0}))){const r=yield it.a.resolve({fs:t,gitdir:e,ref:n});yield it.a.writeRef({fs:t,gitdir:e,ref:"HEAD",value:r})}yield it.a.deleteRef({fs:t,gitdir:e,ref:n});const i=Object(ae.a)(r),o=yield S.a.get({fs:t,gitdir:e});yield o.deleteSection("branch",i),yield S.a.save({fs:t,gitdir:e,config:o})}))).apply(this,arguments)}function le(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function de(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){le(o,n,i,a,s,"next",t)}function s(t){le(o,n,i,a,s,"throw",t)}a(void 0)}))}}function he(t){return pe.apply(this,arguments)}function pe(){return(pe=de((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n}){try{return Object(w.a)("fs",t),Object(w.a)("ref",n),yield ue({fs:new v.a(t),gitdir:r,ref:n})}catch(t){throw t.caller="git.deleteBranch",t}}))).apply(this,arguments)}function ye(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ge(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ye(o,n,i,a,s,"next",t)}function s(t){ye(o,n,i,a,s,"throw",t)}a(void 0)}))}}function me(t){return ve.apply(this,arguments)}function ve(){return(ve=ge((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n}){try{Object(w.a)("fs",t),Object(w.a)("ref",n),yield it.a.deleteRef({fs:new v.a(t),gitdir:r,ref:n})}catch(t){throw t.caller="git.deleteRef",t}}))).apply(this,arguments)}function we(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function be(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){we(o,n,i,a,s,"next",t)}function s(t){we(o,n,i,a,s,"throw",t)}a(void 0)}))}}function _e(t){return je.apply(this,arguments)}function je(){return(je=be((function*({fs:t,gitdir:e,remote:r}){const n=yield S.a.get({fs:t,gitdir:e});yield n.deleteSection("remote",r),yield S.a.save({fs:t,gitdir:e,config:n})}))).apply(this,arguments)}function Oe(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function xe(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Oe(o,n,i,a,s,"next",t)}function s(t){Oe(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Pe(t){return ke.apply(this,arguments)}function ke(){return(ke=xe((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),remote:n}){try{return Object(w.a)("fs",t),Object(w.a)("remote",n),yield _e({fs:new v.a(t),gitdir:r,remote:n})}catch(t){throw t.caller="git.deleteRemote",t}}))).apply(this,arguments)}function Ee(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Se(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ee(o,n,i,a,s,"next",t)}function s(t){Ee(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ae(t){return Re.apply(this,arguments)}function Re(){return(Re=Se((function*({fs:t,gitdir:e,ref:r}){r=r.startsWith("refs/tags/")?r:`refs/tags/${r}`,yield it.a.deleteRef({fs:t,gitdir:e,ref:r})}))).apply(this,arguments)}function $e(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Be(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){$e(o,n,i,a,s,"next",t)}function s(t){$e(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Te(t){return Ie.apply(this,arguments)}function Ie(){return(Ie=Be((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n}){try{return Object(w.a)("fs",t),Object(w.a)("ref",n),yield Ae({fs:new v.a(t),gitdir:r,ref:n})}catch(t){throw t.caller="git.deleteTag",t}}))).apply(this,arguments)}var Ce=r(97);function Ue(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function De(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ue(o,n,i,a,s,"next",t)}function s(t){Ue(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ze(t){return Ne.apply(this,arguments)}function Ne(){return(Ne=De((function*({fs:t,gitdir:e,oid:r}){const n=r.slice(0,2);return(yield t.readdir(`${e}/objects/${n}`)).map(t=>`${n}${t}`).filter(t=>t.startsWith(r))}))).apply(this,arguments)}var Me=r(81);function Fe(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function He(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Fe(o,n,i,a,s,"next",t)}function s(t){Fe(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Le(t){return qe.apply(this,arguments)}function qe(){return(qe=He((function*({fs:t,cache:e,gitdir:r,oid:n,getExternalRefDelta:i}){const o=[];let s=yield t.readdir(Object(b.join)(r,"objects/pack"));s=s.filter(t=>t.endsWith(".idx"));for(const c of s){const s=`${r}/objects/pack/${c}`,u=yield Object(Me.a)({fs:t,cache:e,filename:s,getExternalRefDelta:i});if(u.error)throw new a.a(u.error);for(const t of u.offsets.keys())t.startsWith(n)&&o.push(t)}return o}))).apply(this,arguments)}function Ge(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ye(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ge(o,n,i,a,s,"next",t)}function s(t){Ge(o,n,i,a,s,"throw",t)}a(void 0)}))}}function We(t){return Ze.apply(this,arguments)}function Ze(){return(Ze=Ye((function*({fs:t,cache:e,gitdir:r,oid:n}){const i=yield ze({fs:t,gitdir:r,oid:n}),o=yield Le({fs:t,cache:e,gitdir:r,oid:n,getExternalRefDelta:n=>Object(at.a)({fs:t,cache:e,gitdir:r,oid:n})});for(const t of o)-1===i.indexOf(t)&&i.push(t);if(1===i.length)return i[0];if(i.length>1)throw new Ce.a("oids",n,i);throw new E.a(`an object matching "${n}"`)}))).apply(this,arguments)}function Ke(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ve(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ke(o,n,i,a,s,"next",t)}function s(t){Ke(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Xe(t){return Je.apply(this,arguments)}function Je(){return(Je=Ve((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),yield We({fs:new v.a(t),cache:i,gitdir:r,oid:n})}catch(t){throw t.caller="git.expandOid",t}}))).apply(this,arguments)}function Qe(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function tr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Qe(o,n,i,a,s,"next",t)}function s(t){Qe(o,n,i,a,s,"throw",t)}a(void 0)}))}}function er(t){return rr.apply(this,arguments)}function rr(){return(rr=tr((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),yield it.a.expand({fs:new v.a(t),gitdir:r,ref:n})}catch(t){throw t.caller="git.expandRef",t}}))).apply(this,arguments)}var nr=r(14);function ir(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function or(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ir(o,n,i,a,s,"next",t)}function s(t){ir(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ar(t){return sr.apply(this,arguments)}function sr(){return(sr=or((function*({fs:t,cache:e,gitdir:r,oids:n}){const i={},o=n.length;let a=n.map((t,e)=>({index:e,oid:t}));for(;a.length;){const n=new Set;for(const t of a){const{oid:e,index:r}=t;i[e]||(i[e]=new Set),i[e].add(r),i[e].size===o&&n.add(e)}if(n.size>0)return[...n];const s=new Map;for(const n of a){const{oid:o,index:a}=n;try{const{object:n}=yield Object(at.a)({fs:t,cache:e,gitdir:r,oid:o}),c=nr.a.from(n),{parent:u}=c.parseHeaders();for(const t of u)i[t]&&i[t].has(a)||s.set(t+":"+a,{oid:t,index:a})}catch(t){}}a=Array.from(s.values())}return[]}))).apply(this,arguments)}var cr=r(100),ur=r(57),fr=r(56),lr=r(127);function dr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function hr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){dr(o,n,i,a,s,"next",t)}function s(t){dr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function pr(t){return yr.apply(this,arguments)}function yr(){return(yr=hr((function*({fs:t,cache:e,dir:r,gitdir:i,ours:o,theirs:a,fastForward:s=!0,fastForwardOnly:c=!1,dryRun:u=!1,noUpdateBranch:f=!1,abortOnConflict:l=!0,message:d,author:h,committer:p,signingKey:y,onSign:g,mergeDriver:m}){void 0===o&&(o=yield Object(ee.a)({fs:t,gitdir:i,fullname:!0})),o=yield it.a.expand({fs:t,gitdir:i,ref:o}),a=yield it.a.expand({fs:t,gitdir:i,ref:a});const v=yield it.a.resolve({fs:t,gitdir:i,ref:o}),w=yield it.a.resolve({fs:t,gitdir:i,ref:a}),b=yield ar({fs:t,cache:e,gitdir:i,oids:[v,w]});if(1!==b.length)throw new fr.a;const _=b[0];if(_===w)return{oid:v,alreadyMerged:!0};if(s&&_===v)return u||f||(yield it.a.writeRef({fs:t,gitdir:i,ref:o,value:w})),{oid:w,fastForward:!0};{if(c)throw new cr.a;const s=yield n.a.acquire({fs:t,gitdir:i,cache:e,allowUnmerged:!1},function(){var n=hr((function*(n){return Object(lr.a)({fs:t,cache:e,dir:r,gitdir:i,index:n,ourOid:v,theirOid:w,baseOid:_,ourName:Object(ae.a)(o),baseName:"base",theirName:Object(ae.a)(a),dryRun:u,abortOnConflict:l,mergeDriver:m})}));return function(t){return n.apply(this,arguments)}}());if(s instanceof ur.a)throw s;return d||(d=`Merge branch '${Object(ae.a)(a)}' into ${Object(ae.a)(o)}`),{oid:yield Object(Vt.a)({fs:t,cache:e,gitdir:i,message:d,ref:o,tree:s,parent:[v,w],author:h,committer:p,signingKey:y,onSign:g,dryRun:u,noUpdateBranch:f}),tree:s,mergeCommit:!0}}}))).apply(this,arguments)}var gr=r(24);function mr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function vr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){mr(o,n,i,a,s,"next",t)}function s(t){mr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function wr(t){return br.apply(this,arguments)}function br(){return(br=vr((function*({fs:t,cache:e,http:r,onProgress:n,onMessage:i,onAuth:o,onAuthSuccess:a,onAuthFailure:s,dir:c,gitdir:u,ref:f,url:l,remote:d,remoteRef:h,prune:p,pruneTags:y,fastForward:g,fastForwardOnly:m,corsProxy:v,singleBranch:w,headers:b,author:_,committer:j,signingKey:O}){try{if(!f){const e=yield Object(ee.a)({fs:t,gitdir:u});if(!e)throw new gr.a("ref");f=e}const{fetchHead:x,fetchHeadDescription:P}=yield Object(Dt.a)({fs:t,cache:e,http:r,onProgress:n,onMessage:i,onAuth:o,onAuthSuccess:a,onAuthFailure:s,gitdir:u,corsProxy:v,ref:f,url:l,remote:d,remoteRef:h,singleBranch:w,headers:b,prune:p,pruneTags:y});yield pr({fs:t,cache:e,gitdir:u,ours:f,theirs:x,fastForward:g,fastForwardOnly:m,message:`Merge ${P}`,author:_,committer:j,signingKey:O,dryRun:!1,noUpdateBranch:!1}),yield At({fs:t,cache:e,onProgress:n,dir:c,gitdir:u,ref:f,remote:d,noCheckout:!1})}catch(t){throw t.caller="git.pull",t}}))).apply(this,arguments)}function _r(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function jr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){_r(o,n,i,a,s,"next",t)}function s(t){_r(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Or(t){return xr.apply(this,arguments)}function xr(){return(xr=jr((function*({fs:t,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,dir:s,gitdir:c=Object(b.join)(s,".git"),ref:u,url:f,remote:l,remoteRef:d,corsProxy:h,singleBranch:p,headers:y={},cache:g={}}){try{Object(w.a)("fs",t),Object(w.a)("http",e),Object(w.a)("gitdir",c);const m={name:"",email:"",timestamp:Date.now(),timezoneOffset:0};return yield wr({fs:new v.a(t),cache:g,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,dir:s,gitdir:c,ref:u,url:f,remote:l,remoteRef:d,fastForwardOnly:!0,corsProxy:h,singleBranch:p,headers:y,author:m,committer:m})}catch(t){throw t.caller="git.fastForward",t}}))).apply(this,arguments)}function Pr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function kr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Pr(o,n,i,a,s,"next",t)}function s(t){Pr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Er(t){return Sr.apply(this,arguments)}function Sr(){return(Sr=kr((function*({fs:t,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,dir:s,gitdir:c=Object(b.join)(s,".git"),ref:u,remote:f,remoteRef:l,url:d,corsProxy:h,depth:p=null,since:y=null,exclude:g=[],relative:m=!1,tags:_=!1,singleBranch:j=!1,headers:O={},prune:x=!1,pruneTags:P=!1,cache:k={}}){try{return Object(w.a)("fs",t),Object(w.a)("http",e),Object(w.a)("gitdir",c),yield Object(Dt.a)({fs:new v.a(t),cache:k,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,gitdir:c,ref:u,remote:f,remoteRef:l,url:d,corsProxy:h,depth:p,since:y,exclude:g,relative:m,tags:_,singleBranch:j,headers:O,prune:x,pruneTags:P})}catch(t){throw t.caller="git.fetch",t}}))).apply(this,arguments)}function Ar(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Rr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ar(o,n,i,a,s,"next",t)}function s(t){Ar(o,n,i,a,s,"throw",t)}a(void 0)}))}}function $r(t){return Br.apply(this,arguments)}function Br(){return(Br=Rr((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oids:n,cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oids",n),yield ar({fs:new v.a(t),cache:i,gitdir:r,oids:n})}catch(t){throw t.caller="git.findMergeBase",t}}))).apply(this,arguments)}var Tr=r(27);function Ir(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Cr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ir(o,n,i,a,s,"next",t)}function s(t){Ir(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ur(t){return Dr.apply(this,arguments)}function Dr(){return(Dr=Cr((function*({fs:t,filepath:e}){if(yield t.exists(Object(b.join)(e,".git")))return e;{const r=Object(Tr.a)(e);if(r===e)throw new E.a(`git root for ${e}`);return Ur({fs:t,filepath:r})}}))).apply(this,arguments)}function zr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Nr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){zr(o,n,i,a,s,"next",t)}function s(t){zr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Mr(t){return Fr.apply(this,arguments)}function Fr(){return(Fr=Nr((function*({fs:t,filepath:e}){try{return Object(w.a)("fs",t),Object(w.a)("filepath",e),yield Ur({fs:new v.a(t),filepath:e})}catch(t){throw t.caller="git.findRoot",t}}))).apply(this,arguments)}var Hr=r(41);function Lr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function qr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Lr(o,n,i,a,s,"next",t)}function s(t){Lr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Gr(t){return Yr.apply(this,arguments)}function Yr(){return(Yr=qr((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),path:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("path",n),yield Object(Hr.a)({fs:new v.a(t),gitdir:r,path:n})}catch(t){throw t.caller="git.getConfig",t}}))).apply(this,arguments)}function Wr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Zr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Wr(o,n,i,a,s,"next",t)}function s(t){Wr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Kr(t){return Vr.apply(this,arguments)}function Vr(){return(Vr=Zr((function*({fs:t,gitdir:e,path:r}){return(yield S.a.get({fs:t,gitdir:e})).getall(r)}))).apply(this,arguments)}function Xr(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Jr(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Xr(o,n,i,a,s,"next",t)}function s(t){Xr(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Qr(t){return tn.apply(this,arguments)}function tn(){return(tn=Jr((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),path:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("path",n),yield Kr({fs:new v.a(t),gitdir:r,path:n})}catch(t){throw t.caller="git.getConfigAll",t}}))).apply(this,arguments)}var en=r(63);function rn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function nn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){rn(o,n,i,a,s,"next",t)}function s(t){rn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function on(t){return an.apply(this,arguments)}function an(){return(an=nn((function*({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,url:o,headers:a={},forPush:s=!1}){try{Object(w.a)("http",t),Object(w.a)("url",o);const c=en.a.getRemoteHelperFor({url:o}),u=yield c.discover({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,service:s?"git-receive-pack":"git-upload-pack",url:o,headers:a,protocolVersion:1}),f={capabilities:[...u.capabilities]};for(const[t,e]of u.refs){const r=t.split("/"),n=r.pop();let i=f;for(const t of r)i[t]=i[t]||{},i=i[t];i[n]=e}for(const[t,e]of u.symrefs){const r=t.split("/"),n=r.pop();let i=f;for(const t of r)i[t]=i[t]||{},i=i[t];i[n]=e}return f}catch(t){throw t.caller="git.getRemoteInfo",t}}))).apply(this,arguments)}function sn(t,e,r,n){const i=[];for(const[o,a]of t.refs){if(e&&!o.startsWith(e))continue;if(o.endsWith("^{}")){if(n){const t=o.replace("^{}",""),e=i[i.length-1],r=e.ref===t?e:i.find(e=>e.ref===t);if(void 0===r)throw new Error("I did not expect this to happen");r.peeled=a}continue}const s={ref:o,oid:a};r&&t.symrefs.has(o)&&(s.target=t.symrefs.get(o)),i.push(s)}return i}function cn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function un(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){cn(o,n,i,a,s,"next",t)}function s(t){cn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function fn(t){return ln.apply(this,arguments)}function ln(){return(ln=un((function*({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,url:o,headers:a={},forPush:s=!1,protocolVersion:c=2}){try{Object(w.a)("http",t),Object(w.a)("url",o);const u=en.a.getRemoteHelperFor({url:o}),f=yield u.discover({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,service:s?"git-receive-pack":"git-upload-pack",url:o,headers:a,protocolVersion:c});if(2===f.protocolVersion)return{protocolVersion:f.protocolVersion,capabilities:f.capabilities2};const l={};for(const t of f.capabilities){const[e,r]=t.split("=");l[e]=r||!0}return{protocolVersion:1,capabilities:l,refs:sn(f,void 0,!0,!0)}}catch(t){throw t.caller="git.getRemoteInfo2",t}}))).apply(this,arguments)}var dn=r(159),hn=r(62);function pn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function yn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){pn(o,n,i,a,s,"next",t)}function s(t){pn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function gn(t){return mn.apply(this,arguments)}function mn(){return(mn=yn((function*({fs:t,cache:e,onProgress:r,dir:n,gitdir:i,filepath:o}){try{o=Object(b.join)(n,o);const a=yield t.read(o),s=r=>Object(at.a)({fs:t,cache:e,gitdir:i,oid:r}),c=yield hn.a.fromPack({pack:a,getExternalRefDelta:s,onProgress:r});return yield t.write(o.replace(/\\.pack$/,".idx"),yield c.toBuffer()),{oids:[...c.hashes]}}catch(t){throw t.caller="git.indexPack",t}}))).apply(this,arguments)}function vn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function wn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){vn(o,n,i,a,s,"next",t)}function s(t){vn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function bn(t){return _n.apply(this,arguments)}function _n(){return(_n=wn((function*({fs:t,onProgress:e,dir:r,gitdir:n=Object(b.join)(r,".git"),filepath:i,cache:o={}}){try{return Object(w.a)("fs",t),Object(w.a)("dir",r),Object(w.a)("gitdir",r),Object(w.a)("filepath",i),yield gn({fs:new v.a(t),cache:o,onProgress:e,dir:r,gitdir:n,filepath:i})}catch(t){throw t.caller="git.indexPack",t}}))).apply(this,arguments)}function jn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function On(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){jn(o,n,i,a,s,"next",t)}function s(t){jn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function xn(t){return Pn.apply(this,arguments)}function Pn(){return(Pn=On((function*({fs:t,bare:e=!1,dir:r,gitdir:n=(e?r:Object(b.join)(r,".git")),defaultBranch:i="master"}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",n),e||Object(w.a)("dir",r),yield Mt({fs:new v.a(t),bare:e,dir:r,gitdir:n,defaultBranch:i})}catch(t){throw t.caller="git.init",t}}))).apply(this,arguments)}var kn=r(102),En=r(17),Sn=r(44);function An(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Rn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){An(o,n,i,a,s,"next",t)}function s(t){An(o,n,i,a,s,"throw",t)}a(void 0)}))}}function $n(t){return Bn.apply(this,arguments)}function Bn(){return(Bn=Rn((function*({fs:t,cache:e,gitdir:r,oid:n,ancestor:i,depth:o}){const a=yield Sn.a.read({fs:t,gitdir:r});if(!n)throw new gr.a("oid");if(!i)throw new gr.a("ancestor");if(n===i)return!1;const s=[n],c=new Set;let u=0;for(;s.length;){if(u++===o)throw new kn.a(o);const n=s.shift(),{type:f,object:l}=yield Object(at.a)({fs:t,cache:e,gitdir:r,oid:n});if("commit"!==f)throw new En.a(n,f,"commit");const d=nr.a.from(l).parse();for(const t of d.parent)if(t===i)return!0;if(!a.has(n))for(const t of d.parent)c.has(t)||(s.push(t),c.add(t))}return!1}))).apply(this,arguments)}function Tn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function In(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Tn(o,n,i,a,s,"next",t)}function s(t){Tn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Cn(t){return Un.apply(this,arguments)}function Un(){return(Un=In((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,ancestor:i,depth:o=-1,cache:a={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),Object(w.a)("ancestor",i),yield $n({fs:new v.a(t),cache:a,gitdir:r,oid:n,ancestor:i,depth:o})}catch(t){throw t.caller="git.isDescendent",t}}))).apply(this,arguments)}function Dn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function zn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Dn(o,n,i,a,s,"next",t)}function s(t){Dn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Nn(t){return Mn.apply(this,arguments)}function Mn(){return(Mn=zn((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:n}){try{return Object(w.a)("fs",t),Object(w.a)("dir",e),Object(w.a)("gitdir",r),Object(w.a)("filepath",n),A.a.isIgnored({fs:new v.a(t),dir:e,gitdir:r,filepath:n})}catch(t){throw t.caller="git.isIgnored",t}}))).apply(this,arguments)}function Fn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Hn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Fn(o,n,i,a,s,"next",t)}function s(t){Fn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ln(t){return qn.apply(this,arguments)}function qn(){return(qn=Hn((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),remote:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),it.a.listBranches({fs:new v.a(t),gitdir:r,remote:n})}catch(t){throw t.caller="git.listBranches",t}}))).apply(this,arguments)}var Gn=r(54);function Yn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Wn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Yn(o,n,i,a,s,"next",t)}function s(t){Yn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Zn(t){return Kn.apply(this,arguments)}function Kn(){return(Kn=Wn((function*({fs:t,gitdir:e,ref:r,cache:i}){if(r){const n=yield it.a.resolve({gitdir:e,fs:t,ref:r}),o=[];return yield Vn({fs:t,cache:i,gitdir:e,oid:n,filenames:o,prefix:""}),o}return n.a.acquire({fs:t,gitdir:e,cache:i},function(){var t=Wn((function*(t){return t.entries.map(t=>t.path)}));return function(e){return t.apply(this,arguments)}}())}))).apply(this,arguments)}function Vn(t){return Xn.apply(this,arguments)}function Xn(){return(Xn=Wn((function*({fs:t,cache:e,gitdir:r,oid:n,filenames:i,prefix:o}){const{tree:a}=yield Object(Gn.a)({fs:t,cache:e,gitdir:r,oid:n});for(const n of a)"tree"===n.type?yield Vn({fs:t,cache:e,gitdir:r,oid:n.oid,filenames:i,prefix:Object(b.join)(o,n.path)}):i.push(Object(b.join)(o,n.path))}))).apply(this,arguments)}function Jn(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Qn(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Jn(o,n,i,a,s,"next",t)}function s(t){Jn(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ti(t){return ei.apply(this,arguments)}function ei(){return(ei=Qn((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),yield Zn({fs:new v.a(t),cache:i,gitdir:r,ref:n})}catch(t){throw t.caller="git.listFiles",t}}))).apply(this,arguments)}function ri(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ni(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ri(o,n,i,a,s,"next",t)}function s(t){ri(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ii(t){return oi.apply(this,arguments)}function oi(){return(oi=ni((function*({fs:t,cache:e,gitdir:r,ref:n}){let i;try{i=yield it.a.resolve({gitdir:r,fs:t,ref:n})}catch(t){if(t instanceof E.a)return[]}return(yield Object(Gn.a)({fs:t,cache:e,gitdir:r,oid:i})).tree.map(t=>({target:t.path,note:t.oid}))}))).apply(this,arguments)}function ai(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function si(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ai(o,n,i,a,s,"next",t)}function s(t){ai(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ci(t){return ui.apply(this,arguments)}function ui(){return(ui=si((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n="refs/notes/commits",cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),yield ii({fs:new v.a(t),cache:i,gitdir:r,ref:n})}catch(t){throw t.caller="git.listNotes",t}}))).apply(this,arguments)}function fi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function li(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){fi(o,n,i,a,s,"next",t)}function s(t){fi(o,n,i,a,s,"throw",t)}a(void 0)}))}}function di(t){return hi.apply(this,arguments)}function hi(){return(hi=li((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),it.a.listRefs({fs:new v.a(t),gitdir:r,filepath:n})}catch(t){throw t.caller="git.listRefs",t}}))).apply(this,arguments)}function pi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function yi(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){pi(o,n,i,a,s,"next",t)}function s(t){pi(o,n,i,a,s,"throw",t)}a(void 0)}))}}function gi(t){return mi.apply(this,arguments)}function mi(){return(mi=yi((function*({fs:t,gitdir:e}){const r=yield S.a.get({fs:t,gitdir:e}),n=yield r.getSubsections("remote");return Promise.all(n.map(function(){var t=yi((function*(t){return{remote:t,url:yield r.get(`remote.${t}.url`)}}));return function(e){return t.apply(this,arguments)}}()))}))).apply(this,arguments)}function vi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function wi(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){vi(o,n,i,a,s,"next",t)}function s(t){vi(o,n,i,a,s,"throw",t)}a(void 0)}))}}function bi(t){return _i.apply(this,arguments)}function _i(){return(_i=wi((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git")}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),yield gi({fs:new v.a(t),gitdir:r})}catch(t){throw t.caller="git.listRemotes",t}}))).apply(this,arguments)}var ji=r(55),Oi=r(9);function xi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Pi(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){xi(o,n,i,a,s,"next",t)}function s(t){xi(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ki(t){return Ei.apply(this,arguments)}function Ei(){return(Ei=Pi((function*(t){const e=Oi.a.streamReader(t),r=[];let n;for(;n=yield e(),!0!==n;){if(null===n)continue;n=n.toString("utf8").replace(/\\n$/,"");const[t,e,...i]=n.split(" "),o={ref:e,oid:t};for(const t of i){const[e,r]=t.split(":");"symref-target"===e?o.target=r:"peeled"===e&&(o.peeled=r)}r.push(o)}return r}))).apply(this,arguments)}var Si=r(48);function Ai(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ri(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ai(o,n,i,a,s,"next",t)}function s(t){Ai(o,n,i,a,s,"throw",t)}a(void 0)}))}}function $i(t){return Bi.apply(this,arguments)}function Bi(){return(Bi=Ri((function*({prefix:t,symrefs:e,peelTags:r}){const n=[];return n.push(Oi.a.encode("command=ls-refs\\n")),n.push(Oi.a.encode(`agent=${Si.a.agent}\\n`)),(r||e||t)&&n.push(Oi.a.delim()),r&&n.push(Oi.a.encode("peel")),e&&n.push(Oi.a.encode("symrefs")),t&&n.push(Oi.a.encode(`ref-prefix ${t}`)),n.push(Oi.a.flush()),n}))).apply(this,arguments)}function Ti(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ii(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ti(o,n,i,a,s,"next",t)}function s(t){Ti(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ci(t){return Ui.apply(this,arguments)}function Ui(){return(Ui=Ii((function*({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,url:o,headers:a={},forPush:s=!1,protocolVersion:c=2,prefix:u,symrefs:f,peelTags:l}){try{Object(w.a)("http",t),Object(w.a)("url",o);const d=yield ji.a.discover({http:t,onAuth:e,onAuthSuccess:r,onAuthFailure:n,corsProxy:i,service:s?"git-receive-pack":"git-upload-pack",url:o,headers:a,protocolVersion:c});if(1===d.protocolVersion)return sn(d,u,f,l);const h=yield $i({prefix:u,symrefs:f,peelTags:l});return ki((yield ji.a.connect({http:t,auth:d.auth,headers:a,corsProxy:i,service:s?"git-receive-pack":"git-upload-pack",url:o,body:h})).body)}catch(t){throw t.caller="git.listServerRefs",t}}))).apply(this,arguments)}function Di(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function zi(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Di(o,n,i,a,s,"next",t)}function s(t){Di(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ni(t){return Mi.apply(this,arguments)}function Mi(){return(Mi=zi((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git")}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),it.a.listTags({fs:new v.a(t),gitdir:r})}catch(t){throw t.caller="git.listTags",t}}))).apply(this,arguments)}var Fi=r(65);function Hi(t,e){return t.committer.timestamp-e.committer.timestamp}var Li=r(12),qi=r(47);function Gi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Yi(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Gi(o,n,i,a,s,"next",t)}function s(t){Gi(o,n,i,a,s,"throw",t)}a(void 0)}))}}const Wi="e69de29bb2d1d6434b8b29ae775ad8c2e48c5391";function Zi(t){return Ki.apply(this,arguments)}function Ki(){return(Ki=Yi((function*({fs:t,cache:e,gitdir:r,oid:n,fileId:i}){if(i===Wi)return;const o=n;let a;const s=yield Object(qi.a)({fs:t,cache:e,gitdir:r,oid:n}),c=s.tree;return i===s.oid?a=s.path:(a=yield Vi({fs:t,cache:e,gitdir:r,tree:c,fileId:i,oid:o}),Array.isArray(a)&&(0===a.length?a=void 0:1===a.length&&(a=a[0]))),a}))).apply(this,arguments)}function Vi(t){return Xi.apply(this,arguments)}function Xi(){return(Xi=Yi((function*({fs:t,cache:e,gitdir:r,tree:n,fileId:i,oid:o,filepaths:a=[],parentPath:s=""}){const c=n.entries().map((function(n){let c;return n.oid===i?(c=Object(b.join)(s,n.path),a.push(c)):"tree"===n.type&&(c=Object(at.a)({fs:t,cache:e,gitdir:r,oid:n.oid}).then((function({object:c}){return Vi({fs:t,cache:e,gitdir:r,tree:Li.a.from(c),fileId:i,oid:o,filepaths:a,parentPath:Object(b.join)(s,n.path)})}))),c}));return yield Promise.all(c),a}))).apply(this,arguments)}var Ji=r(70);function Qi(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function to(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Qi(o,n,i,a,s,"next",t)}function s(t){Qi(o,n,i,a,s,"throw",t)}a(void 0)}))}}function eo(t){return ro.apply(this,arguments)}function ro(){return(ro=to((function*({fs:t,cache:e,gitdir:r,filepath:n,ref:i,depth:o,since:a,force:s,follow:c}){const u=void 0===a?void 0:Math.floor(a.valueOf()/1e3),f=[],l=yield Sn.a.read({fs:t,gitdir:r}),d=yield it.a.resolve({fs:t,gitdir:r,ref:i}),h=[yield Object(Fi.a)({fs:t,cache:e,gitdir:r,oid:d})];let p,y,g;function m(t){g&&n&&f.push(t)}for(;h.length>0;){const i=h.pop();if(void 0!==u&&i.commit.committer.timestamp<=u)break;if(n){let o;try{o=yield Object(Ji.a)({fs:t,cache:e,gitdir:r,oid:i.commit.tree,filepath:n}),y&&p!==o&&f.push(y),p=o,y=i,g=!0}catch(o){if(!(o instanceof E.a))throw o;{let a=c&&p;if(a&&(a=yield Zi({fs:t,cache:e,gitdir:r,oid:i.commit.tree,fileId:p}),a))if(Array.isArray(a)){if(y){const i=yield Zi({fs:t,cache:e,gitdir:r,oid:y.commit.tree,fileId:p});if(Array.isArray(i)){if(a=a.filter(t=>-1===i.indexOf(t)),1!==a.length){a=!1,y&&f.push(y);break}a=a[0],n=a,y&&f.push(y)}}}else n=a,y&&f.push(y);if(!a){if(g&&p&&(f.push(y),!s))break;if(!s&&!c)throw o}y=i,g=!1}}}else f.push(i);if(void 0!==o&&f.length===o){m(i);break}if(!l.has(i.oid))for(const n of i.commit.parent){const i=yield Object(Fi.a)({fs:t,cache:e,gitdir:r,oid:n});h.map(t=>t.oid).includes(i.oid)||h.push(i)}0===h.length&&m(i),h.sort((t,e)=>Hi(t.commit,e.commit))}return f}))).apply(this,arguments)}function no(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function io(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){no(o,n,i,a,s,"next",t)}function s(t){no(o,n,i,a,s,"throw",t)}a(void 0)}))}}function oo(t){return ao.apply(this,arguments)}function ao(){return(ao=io((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:n,ref:i="HEAD",depth:o,since:a,force:s,follow:c,cache:u={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",i),yield eo({fs:new v.a(t),cache:u,gitdir:r,filepath:n,ref:i,depth:o,since:a,force:s,follow:c})}catch(t){throw t.caller="git.log",t}}))).apply(this,arguments)}function so(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function co(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){so(o,n,i,a,s,"next",t)}function s(t){so(o,n,i,a,s,"throw",t)}a(void 0)}))}}function uo(t){return fo.apply(this,arguments)}function fo(){return(fo=co((function*({fs:t,onSign:e,dir:r,gitdir:n=Object(b.join)(r,".git"),ours:i,theirs:o,fastForward:a=!0,fastForwardOnly:s=!1,dryRun:c=!1,noUpdateBranch:u=!1,abortOnConflict:f=!0,message:l,author:d,committer:h,signingKey:p,cache:y={},mergeDriver:g}){try{Object(w.a)("fs",t),p&&Object(w.a)("onSign",e);const m=new v.a(t),b=yield Object(M.a)({fs:m,gitdir:n,author:d});if(!(b||s&&a))throw new N.a("author");const _=yield Object(F.a)({fs:m,gitdir:n,author:b,committer:h});if(!(_||s&&a))throw new N.a("committer");return yield pr({fs:m,cache:y,dir:r,gitdir:n,ours:i,theirs:o,fastForward:a,fastForwardOnly:s,dryRun:c,noUpdateBranch:u,abortOnConflict:f,message:l,author:b,committer:_,signingKey:p,onSign:e,mergeDriver:g})}catch(t){throw t.caller="git.merge",t}}))).apply(this,arguments)}var lo=r(166);function ho(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function po(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ho(o,n,i,a,s,"next",t)}function s(t){ho(o,n,i,a,s,"throw",t)}a(void 0)}))}}function yo(t){return go.apply(this,arguments)}function go(){return(go=po((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oids:n,write:i=!1,cache:o={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oids",n),yield Object(lo.a)({fs:new v.a(t),cache:o,gitdir:r,oids:n,write:i})}catch(t){throw t.caller="git.packObjects",t}}))).apply(this,arguments)}function mo(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function vo(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){mo(o,n,i,a,s,"next",t)}function s(t){mo(o,n,i,a,s,"throw",t)}a(void 0)}))}}function wo(t){return bo.apply(this,arguments)}function bo(){return(bo=vo((function*({fs:t,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,dir:s,gitdir:c=Object(b.join)(s,".git"),ref:u,url:f,remote:l,remoteRef:d,prune:h=!1,pruneTags:p=!1,fastForward:y=!0,fastForwardOnly:g=!1,corsProxy:m,singleBranch:_,headers:j={},author:O,committer:x,signingKey:P,cache:k={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",c);const b=new v.a(t),E=yield Object(M.a)({fs:b,gitdir:c,author:O});if(!E)throw new N.a("author");const S=yield Object(F.a)({fs:b,gitdir:c,author:E,committer:x});if(!S)throw new N.a("committer");return yield wr({fs:b,cache:k,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,dir:s,gitdir:c,ref:u,url:f,remote:l,remoteRef:d,fastForward:y,fastForwardOnly:g,corsProxy:m,singleBranch:_,headers:j,author:E,committer:S,signingKey:P,prune:h,pruneTags:p})}catch(t){throw t.caller="git.pull",t}}))).apply(this,arguments)}var _o=r(128),jo=r(115),Oo=r(112),xo=r(101),Po=r(94),ko=r(58),Eo=r(77),So=r(141),Ao=r(39),Ro=r(142),$o=r(130),Bo=r(129);function To(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Io(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){To(o,n,i,a,s,"next",t)}function s(t){To(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Co(t){return Uo.apply(this,arguments)}function Uo(){return(Uo=Io((function*({fs:t,cache:e,http:r,onProgress:n,onMessage:i,onAuth:o,onAuthSuccess:a,onAuthFailure:s,onPrePush:c,gitdir:u,ref:f,remoteRef:l,remote:d,url:h,force:p=!1,delete:y=!1,corsProxy:g,headers:m={}}){const v=f||(yield Object(ee.a)({fs:t,gitdir:u}));if(void 0===v)throw new gr.a("ref");const w=yield S.a.get({fs:t,gitdir:u});d=d||(yield w.get(`branch.${v}.pushRemote`))||(yield w.get("remote.pushDefault"))||(yield w.get(`branch.${v}.remote`))||"origin";const b=h||(yield w.get(`remote.${d}.pushurl`))||(yield w.get(`remote.${d}.url`));if(void 0===b)throw new gr.a("remote OR url");const _=l||(yield w.get(`branch.${v}.merge`));if(void 0===b)throw new gr.a("remoteRef");void 0===g&&(g=yield w.get("http.corsProxy"));const j=yield it.a.expand({fs:t,gitdir:u,ref:v}),O=y?"0000000000000000000000000000000000000000":yield it.a.resolve({fs:t,gitdir:u,ref:j}),x=en.a.getRemoteHelperFor({url:b}),P=yield x.discover({http:r,onAuth:o,onAuthSuccess:a,onAuthFailure:s,corsProxy:g,service:"git-receive-pack",url:b,headers:m,protocolVersion:1}),k=P.auth;let A;if(_)try{A=yield it.a.expandAgainstMap({ref:_,map:P.refs})}catch(t){if(!(t instanceof E.a))throw t;A=_.startsWith("refs/")?_:`refs/heads/${_}`}else A=j;const R=P.refs.get(A)||"0000000000000000000000000000000000000000";if(c){if(!(yield c({remote:d,url:b,localRef:{ref:y?"(delete)":j,oid:O},remoteRef:{ref:A,oid:R}})))throw new ko.a}const $=!P.capabilities.has("no-thin");let B=new Set;if(!y){const r=[...P.refs.values()];let n=new Set;if("0000000000000000000000000000000000000000"!==R){const i=yield ar({fs:t,cache:e,gitdir:u,oids:[O,R]});for(const t of i)r.push(t);$&&(n=yield Object(jo.a)({fs:t,cache:e,gitdir:u,oids:i}))}if(!r.includes(O)){const n=yield Object(_o.a)({fs:t,cache:e,gitdir:u,start:[O],finish:r});B=yield Object(jo.a)({fs:t,cache:e,gitdir:u,oids:n})}if($){try{const r=yield it.a.resolve({fs:t,gitdir:u,ref:`refs/remotes/${d}/HEAD`,depth:2}),{oid:i}=yield it.a.resolveAgainstMap({ref:r.replace(`refs/remotes/${d}/`,""),fullref:r,map:P.refs}),o=[i];for(const r of yield Object(jo.a)({fs:t,cache:e,gitdir:u,oids:o}))n.add(r)}catch(t){}for(const t of n)B.delete(t)}if(O===R&&(p=!0),!p){if(j.startsWith("refs/tags")&&"0000000000000000000000000000000000000000"!==R)throw new Po.a("tag-exists");if("0000000000000000000000000000000000000000"!==O&&"0000000000000000000000000000000000000000"!==R&&!(yield $n({fs:t,cache:e,gitdir:u,oid:O,ancestor:R,depth:-1})))throw new Po.a("not-fast-forward")}}const T=Object(So.a)([...P.capabilities],["report-status","side-band-64k",`agent=${Si.a.agent}`]),I=yield Object(Bo.a)({capabilities:T,triplets:[{oldoid:R,oid:O,fullRef:A}]}),C=y?[]:yield Object(Oo.a)({fs:t,cache:e,gitdir:u,oids:[...B]}),U=yield x.connect({http:r,onProgress:n,corsProxy:g,service:"git-receive-pack",url:b,auth:k,headers:m,body:[...I,...C]}),{packfile:D,progress:z}=yield Eo.a.demux(U.body);if(i){const t=Object(Ro.a)(z);Object(Ao.a)(t,function(){var t=Io((function*(t){yield i(t)}));return function(e){return t.apply(this,arguments)}}())}const N=yield Object($o.a)(D);if(U.headers&&(N.headers=U.headers),d&&N.ok&&N.refs[A].ok&&!j.startsWith("refs/tags")){const e=`refs/remotes/${d}/${A.replace("refs/heads","")}`;y?yield it.a.deleteRef({fs:t,gitdir:u,ref:e}):yield it.a.writeRef({fs:t,gitdir:u,ref:e,value:O})}if(N.ok&&Object.values(N.refs).every(t=>t.ok))return N;{const t=Object.entries(N.refs).filter(([t,e])=>!e.ok).map(([t,e])=>`\\n  - ${t}: ${e.error}`).join("");throw new xo.a(t,N)}}))).apply(this,arguments)}function Do(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function zo(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Do(o,n,i,a,s,"next",t)}function s(t){Do(o,n,i,a,s,"throw",t)}a(void 0)}))}}function No(t){return Mo.apply(this,arguments)}function Mo(){return(Mo=zo((function*({fs:t,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,onPrePush:s,dir:c,gitdir:u=Object(b.join)(c,".git"),ref:f,remoteRef:l,remote:d="origin",url:h,force:p=!1,delete:y=!1,corsProxy:g,headers:m={},cache:_={}}){try{return Object(w.a)("fs",t),Object(w.a)("http",e),Object(w.a)("gitdir",u),yield Co({fs:new v.a(t),cache:_,http:e,onProgress:r,onMessage:n,onAuth:i,onAuthSuccess:o,onAuthFailure:a,onPrePush:s,gitdir:u,ref:f,remoteRef:l,remote:d,url:h,force:p,delete:y,corsProxy:g,headers:m})}catch(t){throw t.caller="git.push",t}}))).apply(this,arguments)}function Fo(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ho(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Fo(o,n,i,a,s,"next",t)}function s(t){Fo(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Lo(t){return qo.apply(this,arguments)}function qo(){return(qo=Ho((function*({fs:t,cache:e,gitdir:r,oid:n}){const{type:i,object:o}=yield Object(at.a)({fs:t,cache:e,gitdir:r,oid:n});if("tag"===i)return Lo({fs:t,cache:e,gitdir:r,oid:n=ot.a.from(o).parse().object});if("blob"!==i)throw new En.a(n,i,"blob");return{oid:n,blob:new Uint8Array(o)}}))).apply(this,arguments)}function Go(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Yo(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Go(o,n,i,a,s,"next",t)}function s(t){Go(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Wo(t){return Zo.apply(this,arguments)}function Zo(){return(Zo=Yo((function*({fs:t,cache:e,gitdir:r,oid:n,filepath:i}){return void 0!==i&&(n=yield Object(Ji.a)({fs:t,cache:e,gitdir:r,oid:n,filepath:i})),yield Lo({fs:t,cache:e,gitdir:r,oid:n})}))).apply(this,arguments)}function Ko(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Vo(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ko(o,n,i,a,s,"next",t)}function s(t){Ko(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Xo(t){return Jo.apply(this,arguments)}function Jo(){return(Jo=Vo((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,filepath:i,cache:o={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),yield Wo({fs:new v.a(t),cache:o,gitdir:r,oid:n,filepath:i})}catch(t){throw t.caller="git.readBlob",t}}))).apply(this,arguments)}function Qo(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ta(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Qo(o,n,i,a,s,"next",t)}function s(t){Qo(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ea(t){return ra.apply(this,arguments)}function ra(){return(ra=ta((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),yield Object(Fi.a)({fs:new v.a(t),cache:i,gitdir:r,oid:n})}catch(t){throw t.caller="git.readCommit",t}}))).apply(this,arguments)}function na(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ia(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){na(o,n,i,a,s,"next",t)}function s(t){na(o,n,i,a,s,"throw",t)}a(void 0)}))}}function oa(t){return aa.apply(this,arguments)}function aa(){return(aa=ia((function*({fs:t,cache:e,gitdir:r,ref:n="refs/notes/commits",oid:i}){const o=yield it.a.resolve({gitdir:r,fs:t,ref:n}),{blob:a}=yield Wo({fs:t,cache:e,gitdir:r,oid:o,filepath:i});return a}))).apply(this,arguments)}function sa(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ca(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){sa(o,n,i,a,s,"next",t)}function s(t){sa(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ua(t){return fa.apply(this,arguments)}function fa(){return(fa=ca((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n="refs/notes/commits",oid:i,cache:o={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),Object(w.a)("oid",i),yield oa({fs:new v.a(t),cache:o,gitdir:r,ref:n,oid:i})}catch(t){throw t.caller="git.readNote",t}}))).apply(this,arguments)}function la(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function da(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){la(o,n,i,a,s,"next",t)}function s(t){la(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ha(t){return pa.apply(this,arguments)}function pa(){return(pa=da((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,format:i="parsed",filepath:o,encoding:a,cache:s={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n);const e=new v.a(t);void 0!==o&&(n=yield Object(Ji.a)({fs:e,cache:s,gitdir:r,oid:n,filepath:o}));const c="parsed"===i?"content":i,u=yield Object(at.a)({fs:e,cache:s,gitdir:r,oid:n,format:c});if(u.oid=n,"parsed"===i)switch(u.format="parsed",u.type){case"commit":u.object=nr.a.from(u.object).parse();break;case"tree":u.object=Li.a.from(u.object).entries();break;case"blob":a?u.object=u.object.toString(a):(u.object=new Uint8Array(u.object),u.format="content");break;case"tag":u.object=ot.a.from(u.object).parse();break;default:throw new En.a(u.oid,u.type,"blob|commit|tag|tree")}else"deflated"!==u.format&&"wrapped"!==u.format||(u.type=u.format);return u}catch(t){throw t.caller="git.readObject",t}}))).apply(this,arguments)}function ya(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ga(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ya(o,n,i,a,s,"next",t)}function s(t){ya(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ma(t){return va.apply(this,arguments)}function va(){return(va=ga((function*({fs:t,cache:e,gitdir:r,oid:n}){const{type:i,object:o}=yield Object(at.a)({fs:t,cache:e,gitdir:r,oid:n,format:"content"});if("tag"!==i)throw new En.a(n,i,"tag");const a=ot.a.from(o);return{oid:n,tag:a.parse(),payload:a.payload()}}))).apply(this,arguments)}function wa(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function ba(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){wa(o,n,i,a,s,"next",t)}function s(t){wa(o,n,i,a,s,"throw",t)}a(void 0)}))}}function _a(t){return ja.apply(this,arguments)}function ja(){return(ja=ba((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,cache:i={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),yield ma({fs:new v.a(t),cache:i,gitdir:r,oid:n})}catch(t){throw t.caller="git.readTag",t}}))).apply(this,arguments)}function Oa(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function xa(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Oa(o,n,i,a,s,"next",t)}function s(t){Oa(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Pa(t){return ka.apply(this,arguments)}function ka(){return(ka=xa((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),oid:n,filepath:i,cache:o={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("oid",n),yield Object(Gn.a)({fs:new v.a(t),cache:o,gitdir:r,oid:n,filepath:i})}catch(t){throw t.caller="git.readTree",t}}))).apply(this,arguments)}function Ea(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Sa(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ea(o,n,i,a,s,"next",t)}function s(t){Ea(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Aa(t){return Ra.apply(this,arguments)}function Ra(){return(Ra=Sa((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:i,cache:o={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("filepath",i),yield n.a.acquire({fs:new v.a(t),gitdir:r,cache:o},function(){var t=Sa((function*(t){t.delete({filepath:i})}));return function(e){return t.apply(this,arguments)}}())}catch(t){throw t.caller="git.remove",t}}))).apply(this,arguments)}var $a=r(89);function Ba(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ta(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ba(o,n,i,a,s,"next",t)}function s(t){Ba(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ia(t){return Ca.apply(this,arguments)}function Ca(){return(Ca=Ta((function*({fs:t,cache:e,onSign:r,gitdir:n,ref:i="refs/notes/commits",oid:o,author:a,committer:s,signingKey:c}){let u;try{u=yield it.a.resolve({gitdir:n,fs:t,ref:i})}catch(t){if(!(t instanceof E.a))throw t}let f=(yield Object(Gn.a)({fs:t,gitdir:n,oid:u||"4b825dc642cb6eb9a060e54bf8d69288fbee4904"})).tree;f=f.filter(t=>t.path!==o);const l=yield Object($a.a)({fs:t,gitdir:n,tree:f});return yield Object(Vt.a)({fs:t,cache:e,onSign:r,gitdir:n,ref:i,tree:l,parent:u&&[u],message:"Note removed by 'isomorphic-git removeNote'\\n",author:a,committer:s,signingKey:c})}))).apply(this,arguments)}function Ua(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Da(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ua(o,n,i,a,s,"next",t)}function s(t){Ua(o,n,i,a,s,"throw",t)}a(void 0)}))}}function za(t){return Na.apply(this,arguments)}function Na(){return(Na=Da((function*({fs:t,onSign:e,dir:r,gitdir:n=Object(b.join)(r,".git"),ref:i="refs/notes/commits",oid:o,author:a,committer:s,signingKey:c,cache:u={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",n),Object(w.a)("oid",o);const r=new v.a(t),f=yield Object(M.a)({fs:r,gitdir:n,author:a});if(!f)throw new N.a("author");const l=yield Object(F.a)({fs:r,gitdir:n,author:f,committer:s});if(!l)throw new N.a("committer");return yield Ia({fs:r,cache:u,onSign:e,gitdir:n,ref:i,oid:o,author:f,committer:l,signingKey:c})}catch(t){throw t.caller="git.removeNote",t}}))).apply(this,arguments)}function Ma(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Fa(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ma(o,n,i,a,s,"next",t)}function s(t){Ma(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ha(t){return La.apply(this,arguments)}function La(){return(La=Fa((function*({fs:t,gitdir:e,oldref:r,ref:n,checkout:i=!1}){if(n!==W.a.clean(n))throw new K.a(n,W.a.clean(n));if(r!==W.a.clean(r))throw new K.a(r,W.a.clean(r));const o=`refs/heads/${r}`,a=`refs/heads/${n}`;if(yield it.a.exists({fs:t,gitdir:e,ref:a}))throw new Z.a("branch",n,!1);const s=yield it.a.resolve({fs:t,gitdir:e,ref:o,depth:1});yield it.a.writeRef({fs:t,gitdir:e,ref:a,value:s}),yield it.a.deleteRef({fs:t,gitdir:e,ref:o});const c=yield Object(ee.a)({fs:t,gitdir:e,fullname:!0});(i||c===o)&&(yield it.a.writeSymbolicRef({fs:t,gitdir:e,ref:"HEAD",value:a}))}))).apply(this,arguments)}function qa(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ga(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){qa(o,n,i,a,s,"next",t)}function s(t){qa(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ya(t){return Wa.apply(this,arguments)}function Wa(){return(Wa=Ga((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,oldref:i,checkout:o=!1}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),Object(w.a)("oldref",i),yield Ha({fs:new v.a(t),gitdir:r,ref:n,oldref:i,checkout:o})}catch(t){throw t.caller="git.renameBranch",t}}))).apply(this,arguments)}var Za=r(25),Ka=r(19);function Va(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Xa(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Va(o,n,i,a,s,"next",t)}function s(t){Va(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ja(t){return Qa.apply(this,arguments)}function Qa(){return(Qa=Xa((function*({gitdir:t,type:e,object:r}){return Object(Ka.a)(Za.a.wrap({type:e,object:r}))}))).apply(this,arguments)}function ts(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function es(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ts(o,n,i,a,s,"next",t)}function s(t){ts(o,n,i,a,s,"throw",t)}a(void 0)}))}}function rs(t){return ns.apply(this,arguments)}function ns(){return(ns=es((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:i,ref:o,cache:a={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("filepath",i);const s=new v.a(t);let c,u;try{c=yield it.a.resolve({fs:s,gitdir:r,ref:o||"HEAD"})}catch(t){if(o)throw t}if(c)try{c=yield Object(Ji.a)({fs:s,cache:a,gitdir:r,oid:c,filepath:i})}catch(t){c=null}let f={ctime:new Date(0),mtime:new Date(0),dev:0,ino:0,mode:0,uid:0,gid:0,size:0};const l=e&&(yield s.read(Object(b.join)(e,i)));l&&(u=yield Ja({gitdir:r,type:"blob",object:l}),c===u&&(f=yield s.lstat(Object(b.join)(e,i)))),yield n.a.acquire({fs:s,gitdir:r,cache:a},function(){var t=es((function*(t){t.delete({filepath:i}),c&&t.insert({filepath:i,stats:f,oid:c})}));return function(e){return t.apply(this,arguments)}}())}catch(t){throw t.caller="git.reset",t}}))).apply(this,arguments)}function is(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function os(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){is(o,n,i,a,s,"next",t)}function s(t){is(o,n,i,a,s,"throw",t)}a(void 0)}))}}function as(t){return ss.apply(this,arguments)}function ss(){return(ss=os((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,depth:i}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),yield it.a.resolve({fs:new v.a(t),gitdir:r,ref:n,depth:i})}catch(t){throw t.caller="git.resolveRef",t}}))).apply(this,arguments)}function cs(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function us(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){cs(o,n,i,a,s,"next",t)}function s(t){cs(o,n,i,a,s,"throw",t)}a(void 0)}))}}function fs(t){return ls.apply(this,arguments)}function ls(){return(ls=us((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),path:n,value:i,append:o=!1}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("path",n);const e=new v.a(t),a=yield S.a.get({fs:e,gitdir:r});o?yield a.append(n,i):yield a.set(n,i),yield S.a.save({fs:e,gitdir:r,config:a})}catch(t){throw t.caller="git.setConfig",t}}))).apply(this,arguments)}function ds(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function hs(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){ds(o,n,i,a,s,"next",t)}function s(t){ds(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ps(t){return ys.apply(this,arguments)}function ys(){return(ys=hs((function*({fs:t,gitdir:e,commit:r}){const n=nr.a.from(r).toObject();return yield Object(R.a)({fs:t,gitdir:e,type:"commit",object:n,format:"content"})}))).apply(this,arguments)}class gs{static get timezoneOffsetForRefLogEntry(){const t=(new Date).getTimezoneOffset(),e=Math.abs(Math.floor(t/60)),r=Math.abs(t%60).toString().padStart(2,"0");return`${t>0?"-":"+"}${e.toString().padStart(2,"0")}${r}`}static createStashReflogEntry(t,e,r){const n=t.name.replace(/\\s/g,""),i=Math.floor(Date.now()/1e3),o=gs.timezoneOffsetForRefLogEntry;return`0000000000000000000000000000000000000000 ${e} ${n} ${t.email} ${i} ${o}\\t${r}\\n`}static getStashReflogEntry(t,e=!1){return t.split("\\n").filter(t=>t).reverse().map((t,r)=>e?`stash@{${r}}: ${t.split("\\t")[1]}`:t)}}var ms=r(33),vs=r.n(ms),ws=r(113);function bs(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function _s(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){bs(o,n,i,a,s,"next",t)}function s(t){bs(o,n,i,a,s,"throw",t)}a(void 0)}))}}const js={stage:d,workdir:y};let Os;function xs(t,e){return Ps.apply(this,arguments)}function Ps(){return(Ps=_s((function*(t,e){return void 0===Os&&(Os=new vs.a),Os.acquire(t,e)}))).apply(this,arguments)}function ks(t,e,r,n){return Es.apply(this,arguments)}function Es(){return(Es=_s((function*(t,e,r,n,i=null){const o=Object(b.join)(r,n),s=yield t.lstat(o);if(!s)throw new E.a(o);if(s.isDirectory())throw new a.a(`${o}: file expected, but found directory`);const c=i?yield Object(ws.a)({fs:t,gitdir:e,oid:i}):void 0;let u=c?i:void 0;return c||(yield xs({fs:t,gitdir:e,currentFilepath:o},_s((function*(){const r=s.isSymbolicLink()?yield t.readlink(o).then($):yield t.read(o);if(null===r)throw new E.a(o);u=yield Object(R.a)({fs:t,gitdir:e,type:"blob",object:r})})))),u}))).apply(this,arguments)}function Ss(t){return As.apply(this,arguments)}function As(){return(As=_s((function*({fs:t,dir:e,gitdir:r,entries:n}){function i(t){return o.apply(this,arguments)}function o(){return(o=_s((function*(n){if("tree"===n.type){if(!n.oid){const e=yield Promise.all(n.children.map(i));n.oid=yield Object($a.a)({fs:t,gitdir:r,tree:e}),n.mode=16384}}else"blob"===n.type&&(n.oid=yield ks(t,r,e,n.path,n.oid),n.mode=33188);return n.path=n.path.split("/").pop(),n}))).apply(this,arguments)}return Promise.all(n.map(i))}))).apply(this,arguments)}function Rs(t){return $s.apply(this,arguments)}function $s(){return($s=_s((function*({fs:t,dir:e,gitdir:r,treePair:n}){const i="stage"===n[1],o=n.map(t=>"string"==typeof t?js[t]():t),a=[],s=function(){var n=_s((function*(n,[i,o]){if("."!==n&&!(yield A.a.isIgnored({fs:t,dir:e,gitdir:r,filepath:n})))return o?((!i||(yield i.oid())!==(yield o.oid())&&void 0!==(yield o.oid()))&&a.push([i,o]),{mode:yield o.mode(),path:n,oid:yield o.oid(),type:yield o.type()}):void 0}));return function(t,e){return n.apply(this,arguments)}}(),c=function(){var t=_s((function*(t,e){return e=e.filter(Boolean),t?(t.children=e,t):e.length>0?e:void 0}));return function(e,r){return t.apply(this,arguments)}}(),u=function(){var r=_s((function*(r,n){const o=[];for(const r of n){const[n,s]=r;i?s&&((yield t.exists(`${e}/${s.toString()}`))?o.push(r):a.push([null,s])):n&&(s?o.push(r):a.push([n,null]))}return o.length?Promise.all(o.map(r)):[]}));return function(t,e){return r.apply(this,arguments)}}(),f=yield Object(g.a)({fs:t,cache:{},dir:e,gitdir:r,trees:o,map:s,reduce:c,iterate:u});if(0===a.length||0===f.length)return null;const l=(yield Ss({fs:t,dir:e,gitdir:r,entries:f})).filter(Boolean).map(t=>({mode:t.mode,path:t.path,oid:t.oid,type:t.type}));return Object($a.a)({fs:t,gitdir:r,tree:l})}))).apply(this,arguments)}function Bs(t){return Ts.apply(this,arguments)}function Ts(){return(Ts=_s((function*({fs:t,dir:e,gitdir:r,stashCommit:i,parentCommit:o,wasStaged:a}){const s=[],c=[],u=yield Object(g.a)({fs:t,cache:{},dir:e,gitdir:r,trees:[Object(h.a)({ref:o}),Object(h.a)({ref:i})],map:(f=_s((function*(n,[i,o]){if("."===n||(yield A.a.isIgnored({fs:t,dir:e,gitdir:r,filepath:n})))return;const u=o?yield o.type():yield i.type();if("tree"!==u&&"blob"!==u)return;if(!o&&i){const t="tree"===u?"rmdir":"rm";return"tree"===u&&s.push(n),"blob"===u&&a&&c.push({filepath:n,oid:yield i.oid()}),{method:t,filepath:n}}const f=yield o.oid();return i&&(yield i.oid())===f?void 0:"tree"===u?{method:"mkdir",filepath:n}:(a&&c.push({filepath:n,oid:f,stats:yield t.lstat(Object(b.join)(e,n))}),{method:"write",filepath:n,oid:f})})),function(t,e){return f.apply(this,arguments)})});var f;yield xs({fs:t,gitdir:r,dirRemoved:s,ops:u},_s((function*(){for(const n of u){const i=Object(b.join)(e,n.filepath);switch(n.method){case"rmdir":yield t.rmdir(i);break;case"mkdir":yield t.mkdir(i);break;case"rm":yield t.rm(i);break;case"write":if(!s.some(t=>i.startsWith(t))){const{object:e}=yield Object(at.a)({fs:t,cache:{},gitdir:r,oid:n.oid});(yield t.exists(i))&&(yield t.rm(i)),yield t.write(i,e)}}}}))),yield n.a.acquire({fs:t,gitdir:r,cache:{}},function(){var t=_s((function*(t){c.forEach(({filepath:e,stats:r,oid:n})=>{t.insert({filepath:e,stats:r,oid:n})})}));return function(e){return t.apply(this,arguments)}}())}))).apply(this,arguments)}function Is(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Cs(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Is(o,n,i,a,s,"next",t)}function s(t){Is(o,n,i,a,s,"throw",t)}a(void 0)}))}}class Us{constructor({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git")}){Object.assign(this,{fs:t,dir:e,gitdir:r,_author:null})}static get refStash(){return"refs/stash"}static get refLogsStash(){return"logs/refs/stash"}get refStashPath(){return Object(b.join)(this.gitdir,Us.refStash)}get refLogsStashPath(){return Object(b.join)(this.gitdir,Us.refLogsStash)}getAuthor(){var t=this;return Cs((function*(){if(!t._author&&(t._author=yield Object(M.a)({fs:t.fs,gitdir:t.gitdir,author:{}}),!t._author))throw new N.a("author");return t._author}))()}getStashSHA(t,e){var r=this;return Cs((function*(){if(!(yield r.fs.exists(r.refStashPath)))return null;return(e||(yield r.readStashReflogs({parsed:!1})))[t].split(" ")[1]}))()}writeStashCommit({message:t,tree:e,parent:r}){var n=this;return Cs((function*(){return ps({fs:n.fs,gitdir:n.gitdir,commit:{message:t,tree:e,parent:r,author:yield n.getAuthor(),committer:yield n.getAuthor()}})}))()}readStashCommit(t){var e=this;return Cs((function*(){const r=yield e.readStashReflogs({parsed:!1});if(0!==t&&(t<0||t>r.length-1))throw new K.a(`stash@${t}`,"number that is in range of [0, num of stash pushed]");const n=yield e.getStashSHA(t,r);return n?Object(Fi.a)({fs:e.fs,cache:{},gitdir:e.gitdir,oid:n}):{}}))()}writeStashRef(t){var e=this;return Cs((function*(){return it.a.writeRef({fs:e.fs,gitdir:e.gitdir,ref:Us.refStash,value:t})}))()}writeStashReflogEntry({stashCommit:t,message:e}){var r=this;return Cs((function*(){const n=yield r.getAuthor(),i=gs.createStashReflogEntry(n,t,e),o=r.refLogsStashPath;yield xs({filepath:o,entry:i},Cs((function*(){const t=(yield r.fs.exists(o))?yield r.fs.read(o,"utf8"):"";yield r.fs.write(o,t+i,"utf8")})))}))()}readStashReflogs({parsed:t=!1}){var e=this;return Cs((function*(){if(!(yield e.fs.exists(e.refLogsStashPath)))return[];const r=(yield e.fs.read(e.refLogsStashPath)).toString();return gs.getStashReflogEntry(r,t)}))()}}function Ds(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function zs(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Ds(o,n,i,a,s,"next",t)}function s(t){Ds(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ns(t){return Ms.apply(this,arguments)}function Ms(){return(Ms=zs((function*({fs:t,dir:e,gitdir:r,message:n=""}){const i=new Us({fs:t,dir:e,gitdir:r});yield i.getAuthor();const o=yield Object(ee.a)({fs:t,gitdir:r,fullname:!1}),a=yield it.a.resolve({fs:t,gitdir:r,ref:"HEAD"}),s=(yield ea({fs:t,dir:e,gitdir:r,oid:a})).commit.message,c=[a];let u=null,f=Object(h.a)({ref:"HEAD"});const l=yield Rs({fs:t,dir:e,gitdir:r,treePair:[Object(h.a)({ref:"HEAD"}),"stage"]});if(l){const t=yield i.writeStashCommit({message:`stash-Index: WIP on ${o} - ${(new Date).toISOString()}`,tree:l,parent:c});c.push(t),u=l,f=d()}const p=yield Rs({fs:t,dir:e,gitdir:r,treePair:[f,"workdir"]});if(p){const t=yield i.writeStashCommit({message:`stash-WorkDir: WIP on ${o} - ${(new Date).toISOString()}`,tree:p,parent:[c[c.length-1]]});c.push(t),u=p}if(!u||!l&&!p)throw new E.a("changes, nothing to stash");const y=(n.trim()||`WIP on ${o}`)+`: ${a.substring(0,7)} ${s}`,g=yield i.writeStashCommit({message:y,tree:u,parent:c});return yield i.writeStashRef(g),yield i.writeStashReflogEntry({stashCommit:g,message:y}),yield Ct({fs:t,dir:e,gitdir:r,ref:o,track:!1,force:!0}),g}))).apply(this,arguments)}function Fs(t){return Hs.apply(this,arguments)}function Hs(){return(Hs=zs((function*({fs:t,dir:e,gitdir:r,refIdx:n=0}){const i=new Us({fs:t,dir:e,gitdir:r}),o=yield i.readStashCommit(n),{parent:a=null}=o.commit?o.commit:{};if(a&&Array.isArray(a))for(let n=0;n<a.length-1;n++){const i=(yield Object(Fi.a)({fs:t,cache:{},gitdir:r,oid:a[n+1]})).commit.message.startsWith("stash-Index");yield Bs({fs:t,dir:e,gitdir:r,stashCommit:a[n+1],parentCommit:a[n],wasStaged:i})}}))).apply(this,arguments)}function Ls(t){return qs.apply(this,arguments)}function qs(){return(qs=zs((function*({fs:t,dir:e,gitdir:r,refIdx:n=0}){const i=new Us({fs:t,dir:e,gitdir:r});if(!(yield i.readStashCommit(n)).commit)return;const o=i.refStashPath;yield xs(o,zs((function*(){(yield t.exists(o))&&(yield t.rm(o))})));const a=yield i.readStashReflogs({parsed:!1});if(!a.length)return;a.splice(n,1);const s=i.refLogsStashPath;yield xs({reflogEntries:a,stashReflogPath:s,stashMgr:i},zs((function*(){if(a.length){yield t.write(s,a.join("\\n"),"utf8");const e=a[a.length-1].split(" ")[1];yield i.writeStashRef(e)}else yield t.rm(s)})))}))).apply(this,arguments)}function Gs(t){return Ys.apply(this,arguments)}function Ys(){return(Ys=zs((function*({fs:t,dir:e,gitdir:r}){return new Us({fs:t,dir:e,gitdir:r}).readStashReflogs({parsed:!0})}))).apply(this,arguments)}function Ws(t){return Zs.apply(this,arguments)}function Zs(){return(Zs=zs((function*({fs:t,dir:e,gitdir:r}){const n=new Us({fs:t,dir:e,gitdir:r}),i=[n.refStashPath,n.refLogsStashPath];yield xs(i,zs((function*(){yield Promise.all(i.map(function(){var e=zs((function*(e){if(yield t.exists(e))return t.rm(e)}));return function(t){return e.apply(this,arguments)}}()))})))}))).apply(this,arguments)}function Ks(t){return Vs.apply(this,arguments)}function Vs(){return(Vs=zs((function*({fs:t,dir:e,gitdir:r,refIdx:n=0}){yield Fs({fs:t,dir:e,gitdir:r,refIdx:n}),yield Ls({fs:t,dir:e,gitdir:r,refIdx:n})}))).apply(this,arguments)}function Xs(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Js(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Xs(o,n,i,a,s,"next",t)}function s(t){Xs(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Qs(t){return tc.apply(this,arguments)}function tc(){return(tc=Js((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),op:n="push",message:i="",refIdx:o=0}){Object(w.a)("fs",t),Object(w.a)("dir",e),Object(w.a)("gitdir",r),Object(w.a)("op",n);const a={push:Ns,apply:Fs,drop:Ls,list:Gs,clear:Ws,pop:Ks},s=["apply","drop","pop"];try{const c=new v.a(t);["refs","logs","logs/refs"].map(t=>Object(b.join)(r,t)).forEach(function(){var t=Js((function*(t){(yield c.exists(t))||(yield c.mkdir(t))}));return function(e){return t.apply(this,arguments)}}());const u=a[n];if(u){if(s.includes(n)&&o<0)throw new K.a(`stash@${o}`,"number that is in range of [0, num of stash pushed]");return yield u({fs:c,dir:e,gitdir:r,message:i,refIdx:o})}throw new Error(`To be implemented: ${n}`)}catch(t){throw t.caller="git.stash",t}}))).apply(this,arguments)}var ec=r(69);function rc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function nc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){rc(o,n,i,a,s,"next",t)}function s(t){rc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function ic(t){return oc.apply(this,arguments)}function oc(){return(oc=nc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),filepath:i,cache:o={}}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("filepath",i);const a=new v.a(t);if(yield A.a.isIgnored({fs:a,gitdir:r,dir:e,filepath:i}))return"ignored";const s=yield cc({fs:a,cache:o,gitdir:r}),c=yield ac({fs:a,cache:o,gitdir:r,tree:s,path:i}),u=yield n.a.acquire({fs:a,gitdir:r,cache:o},function(){var t=nc((function*(t){for(const e of t)if(e.path===i)return e;return null}));return function(e){return t.apply(this,arguments)}}()),f=yield a.lstat(Object(b.join)(e,i)),l=null!==c,d=null!==u,h=null!==f,p=function(){var t=nc((function*(){if(d&&!Object(ec.a)(u,f))return u.oid;{const t=yield a.read(Object(b.join)(e,i)),s=yield Ja({gitdir:r,type:"blob",object:t});return d&&u.oid===s&&-1!==f.size&&n.a.acquire({fs:a,gitdir:r,cache:o},function(){var t=nc((function*(t){t.insert({filepath:i,stats:f,oid:s})}));return function(e){return t.apply(this,arguments)}}()),s}}));return function(){return t.apply(this,arguments)}}();if(!l&&!h&&!d)return"absent";if(!l&&!h&&d)return"*absent";if(!l&&h&&!d)return"*added";if(!l&&h&&d){return(yield p())===u.oid?"added":"*added"}if(l&&!h&&!d)return"deleted";if(l&&!h&&d)return u.oid,"*deleted";if(l&&h&&!d){return(yield p())===c?"*undeleted":"*undeletemodified"}if(l&&h&&d){const t=yield p();return t===c?t===u.oid?"unmodified":"*unmodified":t===u.oid?"modified":"*modified"}}catch(t){throw t.caller="git.status",t}}))).apply(this,arguments)}function ac(t){return sc.apply(this,arguments)}function sc(){return(sc=nc((function*({fs:t,cache:e,gitdir:r,tree:n,path:i}){"string"==typeof i&&(i=i.split("/"));const o=i.shift();for(const a of n)if(a.path===o){if(0===i.length)return a.oid;const{type:n,object:o}=yield Object(at.a)({fs:t,cache:e,gitdir:r,oid:a.oid});if("tree"===n){return ac({fs:t,cache:e,gitdir:r,tree:Li.a.from(o),path:i})}if("blob"===n)throw new En.a(a.oid,n,"blob",i.join("/"))}return null}))).apply(this,arguments)}function cc(t){return uc.apply(this,arguments)}function uc(){return(uc=nc((function*({fs:t,cache:e,gitdir:r}){let n;try{n=yield it.a.resolve({fs:t,gitdir:r,ref:"HEAD"})}catch(t){if(t instanceof E.a)return[]}const{tree:i}=yield Object(Gn.a)({fs:t,cache:e,gitdir:r,oid:n});return i}))).apply(this,arguments)}function fc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function lc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){fc(o,n,i,a,s,"next",t)}function s(t){fc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function dc(t){return hc.apply(this,arguments)}function hc(){return(hc=lc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n="HEAD",filepaths:i=["."],filter:o,cache:a={},ignored:s=!1}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n);const u=new v.a(t);return yield Object(g.a)({fs:u,cache:a,dir:e,gitdir:r,trees:[Object(h.a)({ref:n}),y(),d()],map:(c=lc((function*(t,[r,n,a]){if(!r&&!a&&n&&!s&&(yield A.a.isIgnored({fs:u,dir:e,filepath:t})))return null;if(!i.some(e=>kt(t,e)))return null;if(o&&!o(t))return;const[c,f,l]=yield Promise.all([r&&r.type(),n&&n.type(),a&&a.type()]),d=[c,f,l].includes("blob");if(("tree"===c||"special"===c)&&!d)return;if("commit"===c)return null;if(("tree"===f||"special"===f)&&!d)return;if("commit"===l)return null;if(("tree"===l||"special"===l)&&!d)return;const h="blob"===c?yield r.oid():void 0,p="blob"===l?yield a.oid():void 0;let y;"blob"!==c&&"blob"===f&&"blob"!==l?y="42":"blob"===f&&(y=yield n.oid());const g=[void 0,h,y,p],m=g.map(t=>g.indexOf(t));return m.shift(),[t,...m]})),function(t,e){return c.apply(this,arguments)})})}catch(t){throw t.caller="git.statusMatrix",t}var c}))).apply(this,arguments)}function pc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function yc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){pc(o,n,i,a,s,"next",t)}function s(t){pc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function gc(t){return mc.apply(this,arguments)}function mc(){return(mc=yc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,object:i,force:o=!1}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n);const e=new v.a(t);if(void 0===n)throw new gr.a("ref");n=n.startsWith("refs/tags/")?n:`refs/tags/${n}`;const a=yield it.a.resolve({fs:e,gitdir:r,ref:i||"HEAD"});if(!o&&(yield it.a.exists({fs:e,gitdir:r,ref:n})))throw new Z.a("tag",n);yield it.a.writeRef({fs:e,gitdir:r,ref:n,value:a})}catch(t){throw t.caller="git.tag",t}}))).apply(this,arguments)}var vc=r(60);function wc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function bc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){wc(o,n,i,a,s,"next",t)}function s(t){wc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function _c(t){return jc.apply(this,arguments)}function jc(){return(jc=bc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),cache:i={},filepath:o,oid:a,mode:s,add:c,remove:u,force:f}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("filepath",o);const l=new v.a(t);if(u)return yield n.a.acquire({fs:l,gitdir:r,cache:i},function(){var t=bc((function*(t){if(!f){const t=yield l.lstat(Object(b.join)(e,o));if(t){if(t.isDirectory())throw new vc.a("directory");return}}t.has({filepath:o})&&t.delete({filepath:o})}));return function(e){return t.apply(this,arguments)}}());let d;if(!a){if(d=yield l.lstat(Object(b.join)(e,o)),!d)throw new E.a(`file at "${o}" on disk and "remove" not set`);if(d.isDirectory())throw new vc.a("directory")}return yield n.a.acquire({fs:l,gitdir:r,cache:i},function(){var t=bc((function*(t){if(!c&&!t.has({filepath:o}))throw new E.a(`file at "${o}" in index and "add" not set`);let n;if(a)n={ctime:new Date(0),mtime:new Date(0),dev:0,ino:0,mode:s,uid:0,gid:0,size:0};else{n=d;const t=n.isSymbolicLink()?yield l.readlink(Object(b.join)(e,o)):yield l.read(Object(b.join)(e,o));a=yield Object(R.a)({fs:l,gitdir:r,type:"blob",format:"content",object:t})}return t.insert({filepath:o,oid:a,stats:n}),a}));return function(e){return t.apply(this,arguments)}}())}catch(t){throw t.caller="git.updateIndex",t}}))).apply(this,arguments)}function Oc(){try{return Si.a.version}catch(t){throw t.caller="git.version",t}}function xc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Pc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){xc(o,n,i,a,s,"next",t)}function s(t){xc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function kc(t){return Ec.apply(this,arguments)}function Ec(){return(Ec=Pc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),trees:n,map:i,reduce:o,iterate:a,cache:s={}}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("trees",n),yield Object(g.a)({fs:new v.a(t),cache:s,dir:e,gitdir:r,trees:n,map:i,reduce:o,iterate:a})}catch(t){throw t.caller="git.walk",t}}))).apply(this,arguments)}function Sc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Ac(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Sc(o,n,i,a,s,"next",t)}function s(t){Sc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Rc(t){return $c.apply(this,arguments)}function $c(){return($c=Ac((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),blob:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("blob",n),yield Object(R.a)({fs:new v.a(t),gitdir:r,type:"blob",object:n,format:"content"})}catch(t){throw t.caller="git.writeBlob",t}}))).apply(this,arguments)}function Bc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Tc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Bc(o,n,i,a,s,"next",t)}function s(t){Bc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Ic(t){return Cc.apply(this,arguments)}function Cc(){return(Cc=Tc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),commit:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("commit",n),yield ps({fs:new v.a(t),gitdir:r,commit:n})}catch(t){throw t.caller="git.writeCommit",t}}))).apply(this,arguments)}var Uc=r(160);function Dc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function zc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Dc(o,n,i,a,s,"next",t)}function s(t){Dc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Nc(t){return Mc.apply(this,arguments)}function Mc(){return(Mc=zc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),ref:n,value:i,force:o=!1,symbolic:a=!1}){try{Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("ref",n),Object(w.a)("value",i);const e=new v.a(t);if(n!==W.a.clean(n))throw new K.a(n,W.a.clean(n));if(!o&&(yield it.a.exists({fs:e,gitdir:r,ref:n})))throw new Z.a("ref",n);a?yield it.a.writeSymbolicRef({fs:e,gitdir:r,ref:n,value:i}):(i=yield it.a.resolve({fs:e,gitdir:r,ref:i}),yield it.a.writeRef({fs:e,gitdir:r,ref:n,value:i}))}catch(t){throw t.caller="git.writeRef",t}}))).apply(this,arguments)}function Fc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Hc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Fc(o,n,i,a,s,"next",t)}function s(t){Fc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Lc(t){return qc.apply(this,arguments)}function qc(){return(qc=Hc((function*({fs:t,gitdir:e,tag:r}){const n=ot.a.from(r).toObject();return yield Object(R.a)({fs:t,gitdir:e,type:"tag",object:n,format:"content"})}))).apply(this,arguments)}function Gc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Yc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Gc(o,n,i,a,s,"next",t)}function s(t){Gc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Wc(t){return Zc.apply(this,arguments)}function Zc(){return(Zc=Yc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),tag:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("tag",n),yield Lc({fs:new v.a(t),gitdir:r,tag:n})}catch(t){throw t.caller="git.writeTag",t}}))).apply(this,arguments)}function Kc(t,e,r,n,i,o,a){try{var s=t[o](a),c=s.value}catch(t){return void r(t)}s.done?e(c):Promise.resolve(c).then(n,i)}function Vc(t){return function(){var e=this,r=arguments;return new Promise((function(n,i){var o=t.apply(e,r);function a(t){Kc(o,n,i,a,s,"next",t)}function s(t){Kc(o,n,i,a,s,"throw",t)}a(void 0)}))}}function Xc(t){return Jc.apply(this,arguments)}function Jc(){return(Jc=Vc((function*({fs:t,dir:e,gitdir:r=Object(b.join)(e,".git"),tree:n}){try{return Object(w.a)("fs",t),Object(w.a)("gitdir",r),Object(w.a)("tree",n),yield Object($a.a)({fs:new v.a(t),gitdir:r,tree:n})}catch(t){throw t.caller="git.writeTree",t}}))).apply(this,arguments)}var Qc=r(93);r.d(e,"Errors",(function(){return Qc})),r.d(e,"STAGE",(function(){return d})),r.d(e,"TREE",(function(){return h.a})),r.d(e,"WORKDIR",(function(){return y})),r.d(e,"abortMerge",(function(){return x})),r.d(e,"add",(function(){return I})),r.d(e,"addNote",(function(){return q})),r.d(e,"addRemote",(function(){return rt})),r.d(e,"annotatedTag",(function(){return ht})),r.d(e,"branch",(function(){return _t})),r.d(e,"checkout",(function(){return Ct})),r.d(e,"clone",(function(){return Zt})),r.d(e,"commit",(function(){return Qt})),r.d(e,"getConfig",(function(){return Gr})),r.d(e,"getConfigAll",(function(){return Qr})),r.d(e,"setConfig",(function(){return fs})),r.d(e,"currentBranch",(function(){return ie})),r.d(e,"deleteBranch",(function(){return he})),r.d(e,"deleteRef",(function(){return me})),r.d(e,"deleteRemote",(function(){return Pe})),r.d(e,"deleteTag",(function(){return Te})),r.d(e,"expandOid",(function(){return Xe})),r.d(e,"expandRef",(function(){return er})),r.d(e,"fastForward",(function(){return Or})),r.d(e,"fetch",(function(){return Er})),r.d(e,"findMergeBase",(function(){return $r})),r.d(e,"findRoot",(function(){return Mr})),r.d(e,"getRemoteInfo",(function(){return on})),r.d(e,"getRemoteInfo2",(function(){return fn})),r.d(e,"hashBlob",(function(){return dn.a})),r.d(e,"indexPack",(function(){return bn})),r.d(e,"init",(function(){return xn})),r.d(e,"isDescendent",(function(){return Cn})),r.d(e,"isIgnored",(function(){return Nn})),r.d(e,"listBranches",(function(){return Ln})),r.d(e,"listFiles",(function(){return ti})),r.d(e,"listNotes",(function(){return ci})),r.d(e,"listRefs",(function(){return di})),r.d(e,"listRemotes",(function(){return bi})),r.d(e,"listServerRefs",(function(){return Ci})),r.d(e,"listTags",(function(){return Ni})),r.d(e,"log",(function(){return oo})),r.d(e,"merge",(function(){return uo})),r.d(e,"packObjects",(function(){return yo})),r.d(e,"pull",(function(){return wo})),r.d(e,"push",(function(){return No})),r.d(e,"readBlob",(function(){return Xo})),r.d(e,"readCommit",(function(){return ea})),r.d(e,"readNote",(function(){return ua})),r.d(e,"readObject",(function(){return ha})),r.d(e,"readTag",(function(){return _a})),r.d(e,"readTree",(function(){return Pa})),r.d(e,"remove",(function(){return Aa})),r.d(e,"removeNote",(function(){return za})),r.d(e,"renameBranch",(function(){return Ya})),r.d(e,"resetIndex",(function(){return rs})),r.d(e,"updateIndex",(function(){return _c})),r.d(e,"resolveRef",(function(){return as})),r.d(e,"status",(function(){return ic})),r.d(e,"statusMatrix",(function(){return dc})),r.d(e,"tag",(function(){return gc})),r.d(e,"version",(function(){return Oc})),r.d(e,"walk",(function(){return kc})),r.d(e,"writeBlob",(function(){return Rc})),r.d(e,"writeCommit",(function(){return Ic})),r.d(e,"writeObject",(function(){return Uc.a})),r.d(e,"writeRef",(function(){return Nc})),r.d(e,"writeTag",(function(){return Wc})),r.d(e,"writeTree",(function(){return Xc})),r.d(e,"stash",(function(){return Qs}));e.default={Errors:Qc,STAGE:d,TREE:h.a,WORKDIR:y,add:I,abortMerge:x,addNote:q,addRemote:rt,annotatedTag:ht,branch:_t,checkout:Ct,clone:Zt,commit:Qt,getConfig:Gr,getConfigAll:Qr,setConfig:fs,currentBranch:ie,deleteBranch:he,deleteRef:me,deleteRemote:Pe,deleteTag:Te,expandOid:Xe,expandRef:er,fastForward:Or,fetch:Er,findMergeBase:$r,findRoot:Mr,getRemoteInfo:on,getRemoteInfo2:fn,hashBlob:dn.a,indexPack:bn,init:xn,isDescendent:Cn,isIgnored:Nn,listBranches:Ln,listFiles:ti,listNotes:ci,listRefs:di,listRemotes:bi,listServerRefs:Ci,listTags:Ni,log:oo,merge:uo,packObjects:yo,pull:wo,push:No,readBlob:Xo,readCommit:ea,readNote:ua,readObject:ha,readTag:_a,readTree:Pa,remove:Aa,removeNote:za,renameBranch:Ya,resetIndex:rs,updateIndex:_c,resolveRef:as,status:ic,statusMatrix:dc,tag:gc,version:Oc,walk:kc,writeBlob:Rc,writeCommit:Ic,writeObject:Uc.a,writeRef:Nc,writeTag:Wc,writeTree:Xc,stash:Qs}}])}));
//# sourceMappingURL=index.umd.min.js.map
"""

    private static let gitSource = """
// git — version control for the
// console, over the house's files and
// wire. The engine is isomorphic-git
// 1.30.1 (MIT), a real git in pure
// JavaScript: objects, packfiles,
// the smart-HTTP wire — cloned,
// staged, committed and pushed from
// right here.
//   git clone <url> [dir] [--full]
//   git init [dir]
//   git status
//   git add <path>… | git add .
//   git rm <path>
//   git commit -m <words>
//   git log [-n N]
//   git branch [name]
//   git checkout [-b] <name|ref>
//   git remote [-v]
//   git remote add <name> <url>
//   git fetch | git pull | git push
//   git config user.name|user.email [v]
//   git diff — changed names, in brief
// Sign-in for private repos and for
// pushing is the gh package's token
// ('gh auth login'); a GH_TOKEN in
// the environment works too. Clones
// are shallow (depth 1) unless --full
// is given. Symlinks are not carried.

// ---------- small polyfills ----------
// JavaScriptCore has no TextEncoder,
// and no URL; isomorphic-git uses
// both. Pure-JS stand-ins:

if (typeof TextEncoder === "undefined") {
    self.TextEncoder = function() {};
    TextEncoder.prototype.encode =
        function(text) {
            var out = [];
            var str = String(text);
            for (var i = 0; i < str.length;
                 i++) {
                var code = str.charCodeAt(i);
                if (code < 0x80) {
                    out.push(code);
                } else if (code < 0x800) {
                    out.push(
                        0xc0 | (code >> 6),
                        0x80 | (code & 0x3f));
                } else if (code >= 0xd800
                    && code <= 0xdbff
                    && i + 1 < str.length) {
                    var next =
                        str.charCodeAt(i + 1);
                    if (next >= 0xdc00
                        && next <= 0xdfff) {
                        i++;
                        var cp = 0x10000
                            + ((code - 0xd800)
                               << 10)
                            + (next - 0xdc00);
                        out.push(
                            0xf0 | (cp >> 18),
                            0x80
                                | ((cp >> 12)
                                   & 0x3f),
                            0x80
                                | ((cp >> 6)
                                   & 0x3f),
                            0x80
                                | (cp & 0x3f));
                    } else {
                        out.push(0xef, 0xbf,
                                 0xbd);
                    }
                } else {
                    out.push(
                        0xe0 | (code >> 12),
                        0x80
                            | ((code >> 6)
                               & 0x3f),
                        0x80
                            | (code & 0x3f));
                }
            }
            return new Uint8Array(out);
        };
}
if (typeof TextDecoder === "undefined") {
    self.TextDecoder = function() {};
    TextDecoder.prototype.decode =
        function(bytes) {
            var out = [];
            var i = 0;
            while (i < bytes.length) {
                var b = bytes[i];
                if (b < 0x80) {
                    out.push(
                        String.fromCharCode(b));
                    i += 1;
                } else if (b >= 0xc0
                    && b < 0xe0) {
                    out.push(
                        String.fromCharCode(
                            ((b & 0x1f) << 6)
                            | (bytes[i + 1]
                               & 0x3f)));
                    i += 2;
                } else if (b >= 0xe0
                    && b < 0xf0) {
                    out.push(
                        String.fromCharCode(
                            ((b & 0x0f) << 12)
                            | ((bytes[i + 1]
                                & 0x3f) << 6)
                            | (bytes[i + 2]
                               & 0x3f)));
                    i += 3;
                } else {
                    var cp =
                        ((b & 0x07) << 18)
                        | ((bytes[i + 1]
                            & 0x3f) << 12)
                        | ((bytes[i + 2]
                            & 0x3f) << 6)
                        | (bytes[i + 3]
                           & 0x3f);
                    cp -= 0x10000;
                    out.push(
                        String.fromCharCode(
                            0xd800
                                + (cp >> 10),
                            0xdc00
                                + (cp
                                   & 0x3ff)));
                    i += 4;
                }
            }
            return out.join("");
        };
}
if (typeof URL === "undefined") {
    self.URL = function(url, base) {
        var text = String(url);
        if (base
            && text.indexOf("://") < 0) {
            var b = new URL(base);
            if (text.charAt(0) === "/") {
                text = b.protocol + "//"
                    + b.host + text;
            } else {
                text = b.protocol + "//"
                    + b.host
                    + b.pathname.replace(
                        /[^\\/]*$/, "")
                    + text;
            }
        }
        var m = text.match(
            /^([a-zA-Z][a-zA-Z0-9+.-]*:)\\/\\/([^\\/:?#]*)(?::([0-9]+))?([^?#]*)(\\?[^#]*)?(#.*)?$/);
        if (!m) {
            throw new Error(
                "bad url: " + text);
        }
        this.protocol = m[1];
        this.hostname = m[2];
        this.port = m[3] || "";
        this.host = this.port
            ? this.hostname + ":" + this.port
            : this.hostname;
        this.pathname = m[4] || "/";
        this.search = m[5] || "";
        this.hash = m[6] || "";
        this.origin = this.protocol + "//"
            + this.host;
        this.href = text;
    };
    URL.prototype.toString = function() {
        return this.href;
    };
}

var git = require("isomorphic-git");

// ---------- bytes ----------

var B64CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    + "abcdefghijklmnopqrstuvwxyz"
    + "0123456789+/";
var B64REV = {};
for (var bi = 0; bi < B64CHARS.length;
     bi++) {
    B64REV[B64CHARS.charAt(bi)] = bi;
}
function b64encode(bytes) {
    // Chunked, always: the first cut
    // pushed one small string per
    // triplet into a single array,
    // which at pack scale is its own
    // memory bomb. Blocks are a
    // multiple of 3 bytes so each
    // encodes independently; padding
    // appears only in the final block.
    var parts = [];
    var BLOCK = 786432;
    for (var start = 0;
         start < bytes.length;
         start += BLOCK) {
        var end = Math.min(
            start + BLOCK, bytes.length);
        var chars = [];
        for (var i = start; i < end;
             i += 3) {
            var a = bytes[i];
            var b = i + 1 < end
                ? bytes[i + 1] : 0;
            var c = i + 2 < end
                ? bytes[i + 2] : 0;
            chars.push(
                B64CHARS.charAt(a >> 2),
                B64CHARS.charAt(
                    ((a & 3) << 4)
                    | (b >> 4)),
                i + 1 < end
                    ? B64CHARS.charAt(
                        ((b & 15) << 2)
                        | (c >> 6))
                    : "=",
                i + 2 < end
                    ? B64CHARS.charAt(c & 63)
                    : "=");
        }
        parts.push(chars.join(""));
    }
    return parts.join("");
}
function b64decode(text) {
    // Chunked into a preallocated
    // array. The first cut pushed one
    // JS number per byte into a plain
    // array and copied at the end; on
    // a 42 MB pack that peaked at
    // 1.3 GB in the bench (fix145).
    // Here the only allocations are
    // the output itself and one
    // block's worth of scratch.
    var clean = String(text).replace(
        /[^A-Za-z0-9+/=]/g, "");
    var pad = 0;
    if (clean.length >= 1
        && clean.charAt(
            clean.length - 1) === "=") {
        pad = clean.length >= 2
            && clean.charAt(
                clean.length - 2) === "="
            ? 2 : 1;
    }
    var size = Math.max(
        0, Math.floor(clean.length / 4)
            * 3 - pad);
    var out = new Uint8Array(size);
    var BLOCK = 262144;
    var at = 0;
    for (var start = 0;
         start < clean.length;
         start += BLOCK) {
        var end = Math.min(
            start + BLOCK, clean.length);
        for (var i = start; i < end;
             i += 4) {
            var a = B64REV[
                clean.charAt(i)] || 0;
            var b = B64REV[
                clean.charAt(i + 1)] || 0;
            var ch = clean.charAt(i + 2);
            var d = clean.charAt(i + 3);
            var c = ch === "=" ? 0
                : (B64REV[ch] || 0);
            var e = d === "=" ? 0
                : (B64REV[d] || 0);
            if (at < size) {
                out[at++] =
                    (a << 2) | (b >> 4);
            }
            if (ch !== "=" && at < size) {
                out[at++] =
                    ((b & 15) << 4)
                    | (c >> 2);
            }
            if (d !== "=" && at < size) {
                out[at++] =
                    ((c & 3) << 6) | e;
            }
        }
    }
    return out;
}
function utf8encode(text) {
    return new TextEncoder()
        .encode(String(text));
}
function utf8decode(bytes) {
    return new TextDecoder()
        .decode(bytes);
}

// ---------- the fs adapter ----------
// isomorphic-git speaks a promise fs
// and PROBES it (it calls readFile()
// bare and checks for a promise), so
// every method here is genuinely
// async — a sync method gets wrapped
// callback-style and never settles.
// The house bridges underneath are
// synchronous and base64 for binary.
// Every path the adapter sees is
// already absolute in the virtual
// tree.

function fsFail(code, message) {
    var err = new Error(message);
    err.code = code;
    return err;
}
function statsOf(path) {
    var st = fsStat(path);
    if (!st.exists) { return null; }
    var mode = st.dir ? 0o40755 : 0o100644;
    return {
        type: st.dir ? "dir" : "file",
        mode: mode,
        size: st.size,
        ino: 1,
        mtimeMs: st.mtime * 1000,
        ctimeMs: st.mtime * 1000,
        uid: 0,
        gid: 0,
        dev: 1,
        isFile: function() {
            return !st.dir;
        },
        isDirectory: function() {
            return st.dir;
        },
        isSymbolicLink: function() {
            return false;
        }
    };
}
var houseFs = {
    readFile: async function(path, opts) {
        opts = opts || {};
        var encoded = fsRead64(path);
        if (encoded === null
            || encoded === undefined) {
            throw fsFail("ENOENT",
                "no such file: " + path);
        }
        var bytes = b64decode(encoded);
        if (opts.encoding === "utf8"
            || opts.encoding === "utf-8") {
            return utf8decode(bytes);
        }
        return bytes;
    },
    writeFile: async function(path, data) {
        var bytes = typeof data === "string"
            ? utf8encode(data) : data;
        if (!fsWrite64(path,
                       b64encode(bytes))) {
            throw fsFail("EIO",
                "write failed: " + path);
        }
    },
    mkdir: async function(path) {
        fsMkdir(path);
    },
    rmdir: async function(path) {
        if (!fsRm(path)) {
            throw fsFail("ENOENT",
                "no such dir: " + path);
        }
    },
    unlink: async function(path) {
        if (!fsRm(path)) {
            throw fsFail("ENOENT",
                "no such file: " + path);
        }
    },
    stat: async function(path) {
        var st = statsOf(path);
        if (!st) {
            throw fsFail("ENOENT",
                "no such path: " + path);
        }
        return st;
    },
    lstat: async function(path) {
        var st = statsOf(path);
        if (!st) {
            throw fsFail("ENOENT",
                "no such path: " + path);
        }
        return st;
    },
    readdir: async function(path) {
        var names = ls(path) || [];
        return names.map(function(name) {
            return name.charAt(
                name.length - 1) === "/"
                ? name.substring(
                    0, name.length - 1)
                : name;
        }).filter(function(name) {
            return name !== "";
        });
    },
    readlink: async function(path) {
        throw fsFail("ENOTSUP",
            "symlinks are not carried");
    },
    symlink: async function() {
        throw fsFail("ENOTSUP",
            "symlinks are not carried");
    }
};

// ---------- the http adapter ----------
// isomorphic-git wants an async-
// iterable body; the house wire is one
// base64 payload per request.

function emptyBody() {
    var spent = false;
    var iter = {
        next: function() {
            if (spent) {
                return Promise.resolve(
                    { done: true });
            }
            spent = true;
            return Promise.resolve(
                { done: true });
        }
    };
    var body = {};
    body[Symbol.asyncIterator] =
        function() { return iter; };
    return body;
}
function oneChunkBody(bytes) {
    var spent = false;
    var iter = {
        next: function() {
            if (spent || bytes.length
                === 0) {
                return Promise.resolve(
                    { done: true });
            }
            spent = true;
            return Promise.resolve(
                { value: bytes,
                  done: false });
        }
    };
    var body = {};
    body[Symbol.asyncIterator] =
        function() { return iter; };
    return body;
}
function collectRequestBody(body) {
    if (!body) {
        return Promise.resolve(null);
    }
    if (body instanceof Uint8Array) {
        return Promise.resolve(body);
    }
    var iter = null;
    if (body[Symbol.asyncIterator]) {
        iter = body[Symbol.asyncIterator]();
    } else if (body[Symbol.iterator]) {
        iter = body[Symbol.iterator]();
    } else if (body.next) {
        iter = body;
    } else {
        return Promise.resolve(
            new Uint8Array(body));
    }
    var chunks = [];
    var step = function() {
        return Promise.resolve(iter.next())
            .then(function(part) {
                if (part.done) {
                    var total = 0;
                    chunks.forEach(
                        function(c) {
                            total +=
                                c.length;
                        });
                    var all =
                        new Uint8Array(total);
                    var at = 0;
                    chunks.forEach(
                        function(c) {
                            all.set(c, at);
                            at += c.length;
                        });
                    return all;
                }
                chunks.push(
                    part.value
                        instanceof
                        Uint8Array
                        ? part.value
                        : new Uint8Array(
                            part.value));
                return step();
            });
    };
    return step();
}
var houseHttp = {
    request: function(cfg) {
        return collectRequestBody(cfg.body)
            .then(function(bytes) {
                return fetchBinary(cfg.url, {
                    method: cfg.method
                        || "GET",
                    headers: cfg.headers
                        || {},
                    body64: bytes
                        && bytes.length
                        ? b64encode(bytes)
                        : null
                });
            })
            .then(function(r) {
                var headers = {};
                var src = r.headers || {};
                for (var name in src) {
                    headers[name
                        .toLowerCase()] =
                        src[name];
                }
                var bytes = r.bytes
                    || (r.body64
                        ? b64decode(r.body64)
                        : new Uint8Array(0));
                return {
                    url: cfg.url,
                    statusCode: r.status,
                    statusMessage: "",
                    headers: headers,
                    body: bytes.length
                        ? oneChunkBody(bytes)
                        : emptyBody()
                };
            });
    }
};

// ---------- house helpers ----------

function shellEnv() {
    return exec("env").then(function(out) {
        var env = {};
        String(out).split("\\n").forEach(
            function(line) {
                var cut = line.indexOf("=");
                if (cut > 0) {
                    env[line.substring(0, cut)]
                        = line.substring(
                            cut + 1);
                }
            });
        return env;
    });
}
function shellCwd() {
    return exec("pwd").then(function(out) {
        var dir = String(out).trim()
            .split("\\n")[0];
        return dir && dir.charAt(0) === "/"
            ? dir : "/home";
    });
}
function joinPath(dir, name) {
    if (name.charAt(0) === "/") {
        return name;
    }
    return dir === "/"
        ? "/" + name
        : dir + "/" + name;
}
function resolvePath(cwd, given) {
    if (!given) { return cwd; }
    if (given.charAt(0) === "/") {
        return given;
    }
    var parts = cwd.split("/");
    given.split("/").forEach(
        function(seg) {
            if (seg === "" || seg === ".") {
                return;
            }
            if (seg === "..") {
                if (parts.length > 1) {
                    parts.pop();
                }
                return;
            }
            parts.push(seg);
        });
    var joined = parts.join("/");
    return joined === "" ? "/" : joined;
}
function findRepoRoot(cwd) {
    var dir = cwd;
    while (true) {
        if (fsStat(joinPath(dir, ".git"))
            .exists) {
            return dir;
        }
        if (dir === "/") { return null; }
        var cut = dir.lastIndexOf("/");
        dir = cut <= 0 ? "/"
            : dir.substring(0, cut);
    }
}
var AUTH_FILE = "/home/.github-auth.json";
function loadToken() {
    var text = read(AUTH_FILE);
    if (text) {
        try {
            var saved = JSON.parse(text);
            if (saved && saved.token) {
                return Promise.resolve(
                    saved.token);
            }
        } catch (e) { /* fall through */ }
    }
    return shellEnv().then(function(env) {
        return env.GH_TOKEN
            || env.GITHUB_TOKEN || null;
    });
}
function authSource() {
    return loadToken().then(
        function(token) {
            if (!token) { return null; }
            return {
                username: "x-access-token",
                password: token
            };
        });
}
function repoAuthor(dir) {
    return Promise.all([
        git.getConfig({
            fs: houseFs, dir: dir,
            path: "user.name" }),
        git.getConfig({
            fs: houseFs, dir: dir,
            path: "user.email" })
    ]).then(function(values) {
        if (values[0] && values[1]) {
            return { name: values[0],
                     email: values[1] };
        }
        var text = read(AUTH_FILE);
        if (text) {
            try {
                var saved =
                    JSON.parse(text);
                if (saved && saved.login) {
                    return {
                        name: values[0]
                            || saved.login,
                        email: values[1]
                            || saved.login
                            + "@users.noreply"
                            + ".github.com"
                    };
                }
            } catch (e) { /* below */ }
        }
        return null;
    });
}
function needAuthor(dir) {
    return repoAuthor(dir).then(
        function(author) {
            if (!author) {
                throw new Error(
                    "who are you? set it: "
                    + "git config user.name "
                    + "<name> and git config "
                    + "user.email <email>");
            }
            return author;
        });
}
function note(line) { print(line); }
function fail(err) {
    var message = err && err.message
        ? err.message : String(err);
    print("git: " + message);
}

// ---------- commands ----------

function cmdClone(cwd, args) {
    var url = null;
    var dirGiven = null;
    var depth = 1;
    var ref = null;
    args.forEach(function(arg) {
        if (arg === "--full") {
            depth = null;
        } else if (arg === "--depth") {
            depth = -1;
        } else if (typeof arg === "string"
            && arg.indexOf("--depth=") === 0) {
            depth = parseInt(
                arg.substring(8), 10) || 1;
        } else if (arg === "-b"
            || arg === "--branch") {
            ref = -1;
        } else if (depth === -1) {
            depth = parseInt(arg, 10) || 1;
        } else if (ref === -1) {
            ref = arg;
        } else if (!url) {
            url = arg;
        } else if (!dirGiven) {
            dirGiven = arg;
        }
    });
    if (!url) {
        print("git: clone needs a url — "
            + "git clone <url> [dir] "
            + "[--full]");
        return Promise.resolve();
    }
    var name = url.replace(/\\/+$/, "")
        .split("/").pop()
        .replace(/\\.git$/, "");
    var dir = resolvePath(
        cwd, dirGiven || name);
    print("cloning " + url + " into "
        + dir
        + (depth ? " (depth " + depth + ")"
                 : " (full history)")
        + "…");
    var opts = {
        fs: houseFs, http: houseHttp,
        dir: dir, url: url,
        onAuth: authSource,
        onMessage: function(line) {
            print("  " + line);
        }
    };
    if (depth) {
        opts.depth = depth;
        opts.singleBranch = true;
    }
    if (ref) { opts.ref = ref; }
    return git.clone(opts).then(function() {
        return git.currentBranch({
            fs: houseFs, dir: dir,
            fullname: false });
    }).then(function(branch) {
        print("cloned — on branch "
            + (branch || "(detached)")
            + ". the files are yours.");
    });
}
function cmdInit(cwd, args) {
    var dir = resolvePath(
        cwd, args[0] || ".");
    return git.init({
        fs: houseFs, dir: dir,
        defaultBranch: "main"
    }).then(function() {
        print("an empty repository wakes "
            + "in " + dir + "/.git");
    });
}
var STATUS_WORDS = {
    "000": null,
    "101": " D",
    "100": "D ",
    "110": " M",
    "111": null,
    "120": "M ",
    "121": "MM",
    "122": "M ",
    "001": "??",
    "010": "??",
    "020": "A ",
    "021": "AM",
    "022": "A "
};
function statusRows(dir) {
    return git.statusMatrix({
        fs: houseFs, dir: dir });
}
function cmdStatus(dir) {
    return git.currentBranch({
        fs: houseFs, dir: dir,
        fullname: false
    }).then(function(branch) {
        print("on branch "
            + (branch || "(detached)"));
        return statusRows(dir);
    }).then(function(rows) {
        var shown = 0;
        rows.forEach(function(row) {
            var code = "" + row[1]
                + row[2] + row[3];
            var words = STATUS_WORDS[code];
            if (words) {
                print(words + " " + row[0]);
                shown++;
            }
        });
        if (!shown) {
            print("the tree is clean — "
                + "nothing to commit.");
        }
    });
}
function cmdAdd(dir, args) {
    if (!args.length) {
        print("git: add what? — git add "
            + "<path>… or git add .");
        return Promise.resolve();
    }
    var chain = Promise.resolve();
    args.forEach(function(path) {
        chain = chain.then(function() {
            return git.add({
                fs: houseFs, dir: dir,
                filepath: path });
        }).then(function() {
            print("staged " + path);
        });
    });
    return chain;
}
function cmdRemove(dir, args) {
    if (!args.length) {
        print("git: rm what?");
        return Promise.resolve();
    }
    var chain = Promise.resolve();
    args.forEach(function(path) {
        chain = chain.then(function() {
            return git.remove({
                fs: houseFs, dir: dir,
                filepath: path });
        }).then(function() {
            print("unstaged and removed "
                + path
                + " from the index — the "
                + "file itself stays.");
        });
    });
    return chain;
}
function cmdCommit(dir, args) {
    var message = null;
    for (var i = 0; i < args.length; i++) {
        if (args[i] === "-m"
            || args[i] === "--message") {
            message = args.slice(i + 1)
                .join(" ");
            break;
        }
    }
    if (!message) {
        print("git: a commit needs its "
            + "words — git commit -m "
            + "<message>");
        return Promise.resolve();
    }
    return needAuthor(dir).then(
        function(author) {
            return git.commit({
                fs: houseFs, dir: dir,
                author: author,
                message: message });
        }).then(function(oid) {
        print("committed "
            + oid.substring(0, 7)
            + " — " + message);
    });
}
function cmdLog(dir, args) {
    var depth = 10;
    var oneline = false;
    for (var i = 0; i < args.length; i++) {
        if (args[i] === "-n"
            && args[i + 1]) {
            depth = parseInt(
                args[i + 1], 10) || 10;
            i++;
        } else if (args[i].indexOf("-") === 0
            && args[i].length > 1
            && !isNaN(parseInt(
                args[i].substring(1), 10))) {
            depth = parseInt(
                args[i].substring(1), 10);
        } else if (args[i]
            === "--oneline") {
            oneline = true;
        }
    }
    return git.log({
        fs: houseFs, dir: dir,
        depth: depth
    }).then(function(entries) {
        if (!entries.length) {
            print("no commits yet.");
            return;
        }
        entries.forEach(function(entry) {
            var commit = entry.commit;
            var when = new Date(
                commit.author.timestamp
                * 1000).toISOString()
                .substring(0, 10);
            if (oneline) {
                print(entry.oid.substring(
                    0, 7) + "  "
                    + commit.message
                        .split("\\n")[0]);
            } else {
                print("commit "
                    + entry.oid);
                print("  " + commit.author
                    .name + " · " + when);
                print("  " + commit.message
                    .split("\\n")
                    .join("\\n  "));
                print("");
            }
        });
    });
}
function cmdBranch(dir, args) {
    if (!args.length) {
        return git.listBranches({
            fs: houseFs, dir: dir
        }).then(function(names) {
            return git.currentBranch({
                fs: houseFs, dir: dir,
                fullname: false
            }).then(function(current) {
                names.forEach(
                    function(name) {
                        print((name === current
                            ? "* " : "  ")
                            + name);
                    });
            });
        });
    }
    return git.branch({
        fs: houseFs, dir: dir,
        ref: args[0]
    }).then(function() {
        print("branch " + args[0]
            + " created.");
    });
}
function cmdCheckout(dir, args) {
    var fresh = false;
    var ref = null;
    args.forEach(function(arg) {
        if (arg === "-b") {
            fresh = true;
        } else {
            ref = arg;
        }
    });
    if (!ref) {
        print("git: checkout what?");
        return Promise.resolve();
    }
    var step = fresh
        ? git.branch({
            fs: houseFs, dir: dir,
            ref: ref, checkout: true })
        : git.checkout({
            fs: houseFs, dir: dir,
            ref: ref });
    return step.then(function() {
        print("on " + ref + " now.");
    });
}
function cmdRemote(dir, args) {
    if (args[0] === "add"
        && args[1] && args[2]) {
        return git.addRemote({
            fs: houseFs, dir: dir,
            remote: args[1], url: args[2]
        }).then(function() {
            print("remote " + args[1]
                + " → " + args[2]);
        });
    }
    return git.listRemotes({
        fs: houseFs, dir: dir
    }).then(function(remotes) {
        if (!remotes.length) {
            print("no remotes.");
            return;
        }
        var chain = Promise.resolve();
        remotes.forEach(function(entry) {
            chain = chain.then(function() {
                print(entry.remote + "  "
                    + entry.url);
            });
        });
        return chain;
    });
}
function cmdFetch(dir, args) {
    var remote = args[0] || "origin";
    print("fetching from " + remote + "…");
    return git.fetch({
        fs: houseFs, http: houseHttp,
        dir: dir, remote: remote,
        onAuth: authSource
    }).then(function() {
        print("fetched.");
    });
}
function cmdPull(dir, args) {
    var remote = args[0] || "origin";
    return git.currentBranch({
        fs: houseFs, dir: dir,
        fullname: false
    }).then(function(branch) {
        return needAuthor(dir).then(
            function(author) {
                print("pulling " + remote
                    + "/" + branch + "…");
                return git.pull({
                    fs: houseFs,
                    http: houseHttp,
                    dir: dir,
                    remote: remote,
                    ref: branch,
                    author: author,
                    onAuth: authSource });
            });
    }).then(function() {
        print("up to date with the "
            + "remote — the tree matches.");
    });
}
function cmdPush(dir, args) {
    var remote = args[0] || "origin";
    var force = args.indexOf("--force")
        >= 0 || args.indexOf("-f") >= 0;
    return git.currentBranch({
        fs: houseFs, dir: dir,
        fullname: false
    }).then(function(branch) {
        var ref = args[1] || branch;
        print("pushing " + ref + " to "
            + remote + "…");
        return git.push({
            fs: houseFs, http: houseHttp,
            dir: dir, remote: remote,
            ref: ref, force: force,
            onAuth: authSource });
    }).then(function(result) {
        if (result && result.ok === false) {
            var why = result.error
                || "refused";
            print("git: the push was "
                + "refused — " + why);
            return;
        }
        print("pushed — the remote "
            + "carries it now.");
    });
}
function cmdConfig(dir, args) {
    var key = args[0];
    if (!key) {
        print("git: config <user.name|"
            + "user.email> [value]");
        return Promise.resolve();
    }
    if (args.length > 1) {
        return git.setConfig({
            fs: houseFs, dir: dir,
            path: key, value: args[1]
        }).then(function() {
            print(key + " = " + args[1]);
        });
    }
    return git.getConfig({
        fs: houseFs, dir: dir, path: key
    }).then(function(value) {
        print(value === undefined
            ? "(unset)" : value);
    });
}
function cmdDiff(dir) {
    return statusRows(dir).then(
        function(rows) {
            var shown = 0;
            rows.forEach(function(row) {
                var head = row[1];
                var work = row[2];
                if (head === 0
                    && work === 1) {
                    print("untracked  "
                        + row[0]);
                    shown++;
                } else if (head === 1
                    && work === 0) {
                    print("deleted    "
                        + row[0]);
                    shown++;
                } else if (work === 2) {
                    print((head === 0
                        ? "added      "
                        : "modified   ")
                        + row[0]);
                    shown++;
                }
            });
            if (!shown) {
                print("no differences.");
            }
        });
}
function cmdHelp() {
    print("git — the console's own git "
        + "(isomorphic-git; real objects, "
        + "real wire)");
    print("  git clone <url> [dir] "
        + "[--full]   fetch a repository "
        + "(shallow by default)");
    print("  git init [dir] · git status"
        + " · git log [-n N] [--oneline]");
    print("  git add <path>… · git rm "
        + "<path> · git commit -m <words>");
    print("  git branch [name] · git "
        + "checkout [-b] <name|ref>");
    print("  git remote [-v] · git "
        + "remote add <name> <url>");
    print("  git fetch · git pull · "
        + "git push [--force]");
    print("  git config user.name|"
        + "user.email [value]");
    print("  git diff — the changed "
        + "names, in brief");
    print("pushing and private repos "
        + "ride the gh token — "
        + "'gh auth login'.");
}

// ---------- the door ----------

function runGit(args) {
    var sub = (args[0] || "help")
        .toLowerCase();
    var rest = args.slice(1);
    if (sub === "help" || sub === "--help"
        || sub === "-h") {
        cmdHelp();
        return Promise.resolve();
    }
    if (sub === "version"
        || sub === "--version") {
        print("git (console) — engine "
            + "isomorphic-git "
            + (git.version
               ? git.version() : "1.30.1"));
        return Promise.resolve();
    }
    return shellCwd().then(function(cwd) {
        if (sub === "clone") {
            return cmdClone(cwd, rest);
        }
        if (sub === "init") {
            return cmdInit(cwd, rest);
        }
        var root = findRepoRoot(cwd);
        if (!root) {
            print("git: not a repository "
                + "(no .git from here up) "
                + "— 'git init' or "
                + "'git clone' first.");
            return null;
        }
        switch (sub) {
            case "status":
                return cmdStatus(root);
            case "add":
                return cmdAdd(root, rest);
            case "rm":
                return cmdRemove(root, rest);
            case "commit":
                return cmdCommit(root, rest);
            case "log":
                return cmdLog(root, rest);
            case "branch":
                return cmdBranch(root, rest);
            case "checkout":
                return cmdCheckout(root, rest);
            case "remote":
                return cmdRemote(root, rest);
            case "fetch":
                return cmdFetch(root, rest);
            case "pull":
                return cmdPull(root, rest);
            case "push":
                return cmdPush(root, rest);
            case "config":
                return cmdConfig(root, rest);
            case "diff":
                return cmdDiff(root);
            default:
                print("git: '" + sub
                    + "' is not a command "
                    + "this git carries — "
                    + "'git help'.");
                return null;
        }
    });
}
registerCommand("git", function(args) {
    runGit(args || []).catch(fail);
});
"""

    private static let ghSource = """
// gh — GitHub from the console, the
// house's own client over the REST
// API (api.github.com). Not the
// official CLI — the same account,
// the same data, spoken from here.
//   gh auth login <token>
//   gh auth status · gh auth logout
//   gh repo view [owner/repo]
//   gh repo list [n]
//   gh issue list [owner/repo]
//   gh issue view <n> [owner/repo]
//   gh pr list [owner/repo]
//   gh pr view <n> [owner/repo]
//   gh api <path> [method]
// The token is a personal access
// token (github.com → Settings →
// Developer settings → Personal
// access tokens). It lives in
// /home/.github-auth.json and is
// shared with the git package for
// pushes and private clones. A
// GH_TOKEN or GITHUB_TOKEN in the
// environment works instead.

var GH_API = "https://api.github.com";
var GH_AUTH_FILE =
    "/home/.github-auth.json";

function ghSaved() {
    var text = read(GH_AUTH_FILE);
    if (!text) { return null; }
    try { return JSON.parse(text); }
    catch (e) { return null; }
}
function ghEnvToken() {
    return exec("env").then(function(out) {
        var found = null;
        String(out).split("\\n").forEach(
            function(line) {
                var cut = line.indexOf("=");
                if (cut > 0) {
                    var key = line.substring(
                        0, cut);
                    if (key === "GH_TOKEN"
                        || key
                        === "GITHUB_TOKEN") {
                        found = line.substring(
                            cut + 1);
                    }
                }
            });
        return found;
    });
}
function ghToken() {
    var saved = ghSaved();
    if (saved && saved.token) {
        return Promise.resolve({
            token: saved.token,
            login: saved.login || null,
            source: "the saved sign-in" });
    }
    return ghEnvToken().then(
        function(token) {
            if (!token) { return null; }
            return { token: token,
                     login: null,
                     source: "the environment" };
        });
}
function ghCall(path, method, body) {
    return ghToken().then(function(auth) {
        var headers = {
            "Accept":
                "application/vnd.github+json",
            "X-GitHub-Api-Version":
                "2022-11-28",
            "Content-Type":
                "application/json"
        };
        if (auth) {
            headers["Authorization"] =
                "Bearer " + auth.token;
        }
        return fetch(GH_API + path, {
            method: method || "GET",
            headers: headers,
            body: body
                ? JSON.stringify(body)
                : null
        }).then(function(r) {
            var parsed = null;
            try {
                parsed = JSON.parse(r.body);
            } catch (e) { /* below */ }
            if (r.status >= 400) {
                var why = parsed
                    && parsed.message
                    ? parsed.message
                    : "HTTP " + r.status;
                throw new Error(why);
            }
            return { status: r.status,
                     body: parsed,
                     raw: r.body };
        });
    });
}
function ghNeedAuth() {
    return ghToken().then(function(auth) {
        if (!auth) {
            throw new Error(
                "not signed in — 'gh auth "
                + "login <token>' with a "
                + "personal access token, "
                + "or set GH_TOKEN.");
        }
        return auth;
    });
}
function ghCwdRepo() {
    return exec("pwd").then(function(out) {
        var dir = String(out).trim()
            .split("\\n")[0] || "/home";
        var here = dir;
        while (true) {
            var cfg = read(
                (here === "/"
                 ? "" : here)
                + "/.git/config");
            if (cfg) {
                var m = cfg.match(
                    /github\\.com[:\\/]([A-Za-z0-9_.-]+)\\/([A-Za-z0-9_.-]+?)(?:\\.git)?[\\s"']/);
                if (m) {
                    return m[1] + "/" + m[2];
                }
                return null;
            }
            if (here === "/"
                || here === "") {
                return null;
            }
            var cut = here.lastIndexOf("/");
            here = cut <= 0 ? "/"
                : here.substring(0, cut);
        }
    });
}
function ghRepoArg(given) {
    if (given
        && given.indexOf("/") > 0) {
        return Promise.resolve(given);
    }
    return ghCwdRepo().then(
        function(repo) {
            if (!repo) {
                throw new Error(
                    "which repository? "
                    + "name it (owner/repo) "
                    + "or run this inside "
                    + "a clone.");
            }
            return repo;
        });
}
function ghFail(err) {
    print("gh: " + (err && err.message
        ? err.message : String(err)));
}

// ---------- auth ----------

function ghAuth(args) {
    var sub = (args[0] || "status")
        .toLowerCase();
    if (sub === "login") {
        var token = args[1];
        if (!token) {
            print("gh: paste the token "
                + "after login — gh auth "
                + "login <token>");
            print("make one at github.com "
                + "→ Settings → Developer "
                + "settings → Personal "
                + "access tokens (repo "
                + "scope for pushes).");
            return Promise.resolve();
        }
        return fetch(GH_API + "/user", {
            headers: {
                "Accept":
                    "application/vnd.github+json",
                "Authorization":
                    "Bearer " + token
            }
        }).then(function(r) {
            var user = null;
            try {
                user = JSON.parse(r.body);
            } catch (e) { /* below */ }
            if (r.status !== 200
                || !user || !user.login) {
                throw new Error(
                    "github refused that "
                    + "token (HTTP "
                    + r.status + ").");
            }
            write(GH_AUTH_FILE,
                JSON.stringify({
                    token: token,
                    login: user.login }));
            print("signed in to github as "
                + user.login
                + " — the token lives in "
                + GH_AUTH_FILE
                + " and the git package "
                + "rides it too.");
        });
    }
    if (sub === "logout") {
        write(GH_AUTH_FILE, "");
        print("signed out — the saved "
            + "token is forgotten.");
        return Promise.resolve();
    }
    return ghToken().then(function(auth) {
        if (!auth) {
            print("not signed in — "
                + "'gh auth login "
                + "<token>'.");
            return null;
        }
        return ghCall("/user").then(
            function(r) {
                print("signed in as "
                    + r.body.login
                    + " (" + r.body.name
                    + ") via "
                    + auth.source + ".");
            });
    });
}

// ---------- repos & social ----------

function ghRepo(args) {
    var sub = (args[0] || "view")
        .toLowerCase();
    if (sub === "list") {
        var count = parseInt(args[1], 10)
            || 20;
        return ghNeedAuth().then(
            function() {
                return ghCall(
                    "/user/repos?per_page="
                    + count
                    + "&sort=updated");
            }).then(function(r) {
                r.body.forEach(
                    function(repo) {
                        print(repo.full_name
                            + (repo.private
                               ? "  (private)"
                               : "")
                            + "  ★"
                            + repo
                                .stargazers_count
                            + "  "
                            + (repo.language
                               || ""));
                    });
            });
    }
    return ghRepoArg(args[1]).then(
        function(repo) {
            return ghCall("/repos/" + repo);
        }).then(function(r) {
            var repo = r.body;
            print(repo.full_name
                + (repo.private
                   ? "  (private)" : ""));
            if (repo.description) {
                print("  " + repo.description);
            }
            print("  ★" + repo.stargazers_count
                + " · forks "
                + repo.forks_count
                + " · open issues "
                + repo.open_issues_count);
            print("  default branch "
                + repo.default_branch
                + " · " + repo.html_url);
        });
}
function ghIssueList(repo) {
    return ghCall("/repos/" + repo
        + "/issues?state=open"
        + "&per_page=30").then(
        function(r) {
            var issues = r.body.filter(
                function(item) {
                    return !item.pull_request;
                });
            if (!issues.length) {
                print("no open issues in "
                    + repo + ".");
                return;
            }
            issues.forEach(function(item) {
                print("#" + item.number
                    + "  " + item.title
                    + "  (" + item.user.login
                    + ")");
            });
        });
}
function ghIssue(args) {
    var sub = (args[0] || "list")
        .toLowerCase();
    if (sub === "view" && args[1]) {
        return ghRepoArg(args[2]).then(
            function(repo) {
                return ghCall("/repos/"
                    + repo + "/issues/"
                    + args[1]);
            }).then(function(r) {
                var item = r.body;
                print("#" + item.number
                    + "  " + item.title);
                print("  " + item.state
                    + " · " + item.user.login
                    + " · "
                    + (item.created_at || "")
                        .substring(0, 10));
                if (item.body) {
                    print("");
                    print(item.body);
                }
            });
    }
    return ghRepoArg(args[1]).then(
        ghIssueList);
}
function ghPrList(repo) {
    return ghCall("/repos/" + repo
        + "/pulls?state=open"
        + "&per_page=30").then(
        function(r) {
            if (!r.body.length) {
                print("no open pull "
                    + "requests in " + repo
                    + ".");
                return;
            }
            r.body.forEach(function(item) {
                print("#" + item.number
                    + "  " + item.title
                    + "  (" + item.user.login
                    + " → " + item.base.ref
                    + ")");
            });
        });
}
function ghPr(args) {
    var sub = (args[0] || "list")
        .toLowerCase();
    if (sub === "view" && args[1]) {
        return ghRepoArg(args[2]).then(
            function(repo) {
                return ghCall("/repos/"
                    + repo + "/pulls/"
                    + args[1]);
            }).then(function(r) {
                var item = r.body;
                print("#" + item.number
                    + "  " + item.title);
                print("  " + item.state
                    + " · " + item.user.login
                    + " · " + item.head.ref
                    + " → " + item.base.ref);
                if (item.body) {
                    print("");
                    print(item.body);
                }
            });
    }
    return ghRepoArg(args[1]).then(
        ghPrList);
}
function ghApiCommand(args) {
    var path = args[0];
    if (!path) {
        print("gh: api <path> — e.g. "
            + "gh api /user/repos");
        return Promise.resolve();
    }
    if (path.charAt(0) !== "/") {
        path = "/" + path;
    }
    return ghCall(path,
        (args[1] || "GET").toUpperCase())
        .then(function(r) {
            print(JSON.stringify(
                r.body, null, 2));
        });
}
function ghHelp() {
    print("gh — github from here (the "
        + "house's client over the "
        + "REST api)");
    print("  gh auth login <token> · "
        + "gh auth status · "
        + "gh auth logout");
    print("  gh repo view [owner/repo] "
        + "· gh repo list [n]");
    print("  gh issue list|view "
        + "[owner/repo]");
    print("  gh pr list|view "
        + "[owner/repo]");
    print("  gh api <path> [method] — "
        + "the raw wire, printed");
}

// ---------- the door ----------

function runGh(args) {
    var sub = (args[0] || "help")
        .toLowerCase();
    var rest = args.slice(1);
    switch (sub) {
        case "auth":
            return ghAuth(rest);
        case "repo":
            return ghRepo(rest);
        case "issue":
            return ghIssue(rest);
        case "pr":
            return ghPr(rest);
        case "api":
            return ghApiCommand(rest);
        case "help":
        case "--help":
            ghHelp();
            return Promise.resolve();
        default:
            print("gh: '" + sub
                + "' is not carried — "
                + "'gh help'.");
            return Promise.resolve();
    }
}
registerCommand("gh", function(args) {
    runGh(args || []).catch(ghFail);
});

"""

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
