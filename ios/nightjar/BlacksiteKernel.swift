import Foundation

// BlacksiteKernel — the kernel under the
// console.
//
// The console stopped being a shell with
// programs bolted on: programs now run
// UNDER something. Every program the
// operator starts — python, javascript,
// a shell script, and in time the wasm
// guests — is admitted by this kernel,
// entered in its process table with a
// pid, a parent, a kind and a state, and
// lives inside quotas the kernel enforces:
//
//   · at most 32 live processes — a fork
//     bomb fills the table and dies there,
//     refused at the gate, taking nothing
//     with it;
//   · a spawn tree at most 8 deep, and a
//     burst limit on spawning itself;
//   · an output quota per process, so a
//     screaming loop goes quiet instead
//     of burning the room down;
//   · a wall clock per process — the
//     watchdog walks the table every
//     second and reaps what overruns,
//     except a process parked in input(),
//     which is waiting on the operator,
//     not on the clock.
//
// Killing is kind-shaped: python checks
// its cancel token at the interpreter's
// own step gate and raises KeyboardInterrupt;
// javascript's context is handed a kill
// switch that clamps its execution limit
// to nothing; a shell script checks its
// token between lines. The kernel owns
// the table, the quotas and the clock —
// the programs own nothing but their own
// state, and reach the house only through
// the doors they were given.

/// A one-way flag, safe to set from any
/// thread and read from the hot loop of
/// an interpreter.
final class KernelCancel {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

/// A kill switch whose hook is installed
/// by whatever runs the process — the
/// kernel fires it, the runner decides
/// what firing means (for javascript:
/// clamp the context's execution limit).
final class KernelKillSwitch {
    private let lock = NSLock()
    private var hook: (() -> Void)?

    func install(_ body: @escaping () -> Void) {
        lock.lock()
        hook = body
        lock.unlock()
    }

    func fire() {
        lock.lock()
        let body = hook
        lock.unlock()
        body?()
    }
}

enum KernelKind: String {
    case python
    case javascript
    case shell
    case wasm
}

enum KernelState: String {
    case running
    case waiting
    case done
    case killed
}

/// One row of the process table. Fields
/// are written by the kernel under its
/// lock; readers (ps) may see a row a
/// moment stale, never a torn one.
final class KernelProcess {
    let pid: Int
    let parent: Int
    let name: String
    let kind: KernelKind
    let depth: Int
    let background: Bool
    let started = Date()
    let cancel = KernelCancel()
    let killSwitch = KernelKillSwitch()
    var state: KernelState = .running
    var ended: Date?
    var exitNote = ""
    var outputLines = 0
    var waitsForInput = false

    init(pid: Int, parent: Int, name: String,
         kind: KernelKind, depth: Int,
         background: Bool) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.kind = kind
        self.depth = depth
        self.background = background
    }

    var isLive: Bool {
        state == .running || state == .waiting
    }

    var elapsed: TimeInterval {
        (ended ?? Date()).timeIntervalSince(
            started)
    }
}

final class BlacksiteKernel {
    static let shared = BlacksiteKernel()

    // The failsafes. A fork bomb meets the
    // first and second together; a flood
    // meets the third; a runaway meets the
    // fourth.
    static let maxLive = 32
    static let maxDepth = 8
    static let outputQuota = 20_000
    static let wallQuota: TimeInterval = 600
    static let spawnBurst = 24
    static let spawnWindow: TimeInterval = 2

    /// Called on the main queue whenever a
    /// process reaches a terminal state —
    /// the shell hangs its notes and its
    /// busy light on this.
    var onProcessEnd: ((KernelProcess) -> Void)?

    private let lock = NSLock()
    private var table: [Int: KernelProcess] = [:]
    private var nextPID = 1
    private var spawnTimes: [Date] = []
    private var watchdog: DispatchSourceTimer?

    /// Admit a program, or refuse it.
    /// The refusal is a sentence the shell
    /// can say out loud.
    func admit(name: String, kind: KernelKind,
               parent: Int, background: Bool)
        -> (proc: KernelProcess?,
            refusal: String?) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        spawnTimes = spawnTimes.filter {
            now.timeIntervalSince($0)
                < Self.spawnWindow
        }
        let live = table.values.filter {
            $0.isLive
        }
        if live.count >= Self.maxLive {
            return (nil, "the process table is "
                + "full — \(Self.maxLive) "
                + "programs already live; the "
                + "kernel admits no more")
        }
        let parentDepth = parent > 0
            ? (table[parent]?.depth ?? 0) : 0
        let depth = parentDepth + 1
        if depth > Self.maxDepth {
            return (nil, "programs nest at "
                + "most \(Self.maxDepth) deep "
                + "here — the kernel refuses "
                + "to spawn deeper")
        }
        if spawnTimes.count >= Self.spawnBurst {
            return (nil, "programs are "
                + "spawning faster than the "
                + "kernel allows — a burst "
                + "over \(Int(Self.spawnWindow))s "
                + "is refused")
        }
        let proc = KernelProcess(
            pid: nextPID, parent: parent,
            name: name, kind: kind,
            depth: depth, background: background)
        nextPID += 1
        spawnTimes.append(now)
        table[proc.pid] = proc
        pruneLocked()
        startWatchdogLocked()
        return (proc, nil)
    }

    /// A process finished on its own.
    func finish(_ proc: KernelProcess,
                note: String) {
        lock.lock()
        guard proc.isLive else {
            lock.unlock()
            return
        }
        proc.state = .done
        proc.exitNote = note
        proc.ended = Date()
        lock.unlock()
        announce(proc)
    }

    /// Stop a process, whatever it takes
    /// its kind to stop.
    func kill(_ proc: KernelProcess,
              reason: String) {
        lock.lock()
        guard proc.isLive else {
            lock.unlock()
            return
        }
        proc.state = .killed
        proc.exitNote = reason
        proc.ended = Date()
        lock.unlock()
        proc.cancel.cancel()
        proc.killSwitch.fire()
        announce(proc)
    }

    func kill(pid: Int, reason: String)
        -> KernelProcess? {
        lock.lock()
        let proc = table[pid]
        lock.unlock()
        guard let proc = proc, proc.isLive
        else { return nil }
        kill(proc, reason: reason)
        return proc
    }

    func killAll(reason: String) {
        for proc in snapshot()
        where proc.isLive {
            kill(proc, reason: reason)
        }
    }

    func process(_ pid: Int) -> KernelProcess? {
        lock.lock()
        defer { lock.unlock() }
        return table[pid]
    }

    func snapshot() -> [KernelProcess] {
        lock.lock()
        defer { lock.unlock() }
        return table.values.sorted {
            $0.pid < $1.pid
        }
    }

    var liveCount: Int {
        snapshot().filter { $0.isLive }.count
    }

    /// Every process the kernel has ever
    /// admitted — fastfetch's spawned
    /// count reads it.
    var totalSpawned: Int {
        lock.lock()
        defer { lock.unlock() }
        return nextPID - 1
    }

    var hasForegroundLive: Bool {
        snapshot().contains {
            $0.isLive && !$0.background
        }
    }

    /// Park or unpark a process at input():
    /// a parked process is exempt from the
    /// wall clock — it waits on the
    /// operator, not the kernel.
    func markWaiting(_ proc: KernelProcess,
                     _ waiting: Bool) {
        lock.lock()
        proc.waitsForInput = waiting
        if proc.isLive {
            proc.state = waiting
                ? .waiting : .running
        }
        lock.unlock()
    }

    /// Count one line of a process's
    /// output. Returns false when the
    /// quota is spent — the process has
    /// been killed, and the line is not
    /// to be shown.
    func accountOutput(_ proc: KernelProcess)
        -> Bool {
        lock.lock()
        proc.outputLines += 1
        let over = proc.outputLines
            > Self.outputQuota
        lock.unlock()
        if over {
            if proc.isLive {
                kill(proc, reason: "output "
                    + "quota — \(Self.outputQuota) "
                    + "lines is the house limit")
            }
            return false
        }
        return proc.isLive
            || proc.state == .done
    }

    // MARK: The watchdog

    private func startWatchdogLocked() {
        guard watchdog == nil else { return }
        let source = DispatchSource
            .makeTimerSource(
                queue: DispatchQueue.global(
                    qos: .utility))
        source.schedule(deadline: .now() + 1,
                        repeating: 1)
        source.setEventHandler {
            [weak self] in
            self?.sweep()
        }
        source.resume()
        watchdog = source
    }

    private func sweep() {
        let now = Date()
        for proc in snapshot()
        where proc.isLive
            && !proc.waitsForInput
            && now.timeIntervalSince(
                proc.started) > Self.wallQuota {
            kill(proc, reason: "wall clock — "
                + "\(Int(Self.wallQuota))s is "
                + "the house limit")
        }
    }

    private func pruneLocked() {
        let finished = table.values.filter {
            !$0.isLive
        }.sorted { $0.pid < $1.pid }
        if finished.count > 64 {
            for proc in finished.prefix(
                finished.count - 64) {
                table[proc.pid] = nil
            }
        }
    }

    private func announce(_ proc: KernelProcess) {
        let hook = onProcessEnd
        DispatchQueue.main.async {
            hook?(proc)
        }
    }
}
