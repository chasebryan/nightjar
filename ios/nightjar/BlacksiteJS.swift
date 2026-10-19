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
    private var execInFlight = 0

    /// The shell installs this so a script
    /// can run a console line and read
    /// what it printed. The grok client's
    /// run_command tool rides it.
    static var execProvider:
        ((String,
          @escaping (String) -> Void)
            -> Void)?
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
var house = {
    state: function() { return __houseState(); },
    emcon: function() { return __emcon(); }
};
function registerCommand(name, fn) {
    __register(String(name), fn);
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
        if (__exists(candidates[n])) {
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
            runGeneration += 1
            let gen = runGeneration
            let started = Date()
            let state = RunState()
            self.installBridge(into: context,
                               state: state)
            for name in self.installedPackages() {
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
            armTimeLimit(context, timeLimit)
            killSwitch?.install { [weak self] in
                self?.armTimeLimit(
                    context, 0.05)
                self?.forceDrain(context)
            }
            _ = context.evaluateScript(source)
            _ = context.evaluateScript(
                "__dirStack.pop();")
            clearTimeLimit(context)
            drainRunFile(
                context, gen: gen,
                deadline: started
                    .addingTimeInterval(
                        timeLimit),
                error: { state.error },
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
        if let body = parsed["body"]
            as? String {
            request.httpBody =
                Data(body.utf8)
        }
        request.timeoutInterval = 120
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
                    out["body"] = data
                        .flatMap {
                            String(
                                data: $0,
                                encoding: .utf8)
                        } ?? ""
                }
                self.queue.async {
                    self.deliverFetch(id, out)
                }
            }
        box.task = task
        task.resume()
        return id
    }

    private func deliverFetch(
        _ id: Int,
        _ payload: [String: Any]) {
        guard let box = fetchBoxes
            .removeValue(forKey: id)
        else { return }
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
        fetchBoxes.values.contains {
            $0.context === context
                && $0.gen == gen
        }
    }

    private func cancelFetches(
        context: JSContext, gen: Int) {
        for (id, box) in fetchBoxes
            where box.context === context
                && box.gen == gen {
            box.task?.cancel()
            fetchBoxes[id] = nil
        }
    }

    private func cancelFetches(
        _ context: JSContext) {
        for (id, box) in fetchBoxes
            where box.context === context {
            box.task?.cancel()
            fetchBoxes[id] = nil
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
        error: @escaping () -> String?,
        completion: @escaping
            (String?) -> Void) {
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
                        error: error,
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
