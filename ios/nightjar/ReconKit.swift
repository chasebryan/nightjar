import Combine
import Foundation
import Network

/// The recon bench engine: knock, connect, fuzz.
///
/// Same shape as `ScanModel`: a concurrent worker queue gated by a
/// semaphore, and a separate serial queue for NWConnection starts and
/// deadlines so a connection is never starved behind its own gating.
/// One fact, kept once: is any bench in the app
/// probing the wire right now? Every Recon bench
/// reports its fuzz lifecycle here, so the exposure
/// score — on every surface that shows it — weighs
/// the same probing state.
final class ProbingBeacon: ObservableObject {
    static let shared = ProbingBeacon()
    @Published private(set) var active = false
    private var running = 0

    func begin() {
        running += 1
        active = true
    }

    func end() {
        running = max(0, running - 1)
        active = running > 0
    }
}

final class Recon: NSObject, ObservableObject {

    struct Hit: Identifiable {
        let id = UUID()
        let port: Int
        let udp: Bool
        let state: String
        let service: String
        let banner: String
        let confirmed: Bool
        let reply: Data
        var label: String { "\(port)/\(udp ? "udp" : "tcp")" }
        var isOpen: Bool { state == "open" }
    }

    @Published private(set) var hits: [Hit] = []
    @Published private(set) var knocking = false
    @Published private(set) var probed = 0
    @Published private(set) var total = 0
    @Published private(set) var lastKnocked = ""

    @Published private(set) var console: [String] = []
    @Published private(set) var connected = false
    @Published var connectTarget = ""

    @Published private(set) var fuzzing = false {
        didSet {
            guard fuzzing != oldValue else { return }
            if fuzzing {
                ProbingBeacon.shared.begin()
                ProcessBoard.shared.beginKeyed(
                    "recon.fuzz.\(ObjectIdentifier(self))",
                    label: "Fuzz", organ: "Recon",
                    announce: false)
            } else {
                ProbingBeacon.shared.end()
                ProcessBoard.shared.endKeyed(
                    "recon.fuzz.\(ObjectIdentifier(self))",
                    .done("Fuzz ended"))
            }
        }
    }
    @Published private(set) var fuzzLines: [String] = []
    @Published private(set) var fuzzDead = 0

    weak var mouth: Mouth?

    private let queue = DispatchQueue(label: "nightjar-recon",
                                      attributes: .concurrent)
    private let connectionQueue = DispatchQueue(label: "nightjar-recon-connections")
    private let lock = NSLock()
    private var generation = 0
    private var consoleConnection: NWConnection?
    private var fuzzToken = 0

    /// UDP socket readiness is not proof a remote port is open.
    /// Without a response, the strongest supported result is open|filtered.
    static func probeState(_ state: String, udp: Bool, replyBytes: Int) -> String {
        return udp && state == "open" && replyBytes == 0 ? "open|filtered" : state
    }

    // MARK: - knock

    func knock(host rawHost: String, ports: [Int], udp: Bool,
               timeout: TimeInterval = 1.5, jobs: Int = 24,
               speak: Bool = true) {
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !ports.isEmpty, !knocking else { return }
        knocking = true
        ProcessBoard.shared.beginKeyed(
            "recon.knock.\(ObjectIdentifier(self))",
            label: "Knock — \(host)", organ: "Recon",
            detail: "\(ports.count) ports", announce: false)
        hits = []
        probed = 0
        total = ports.count
        lastKnocked = host
        generation += 1
        let gen = generation

        // Two phases, because the knock used to have
        // one fixed order, one fixed timeout, and no
        // memory. What the host is KNOWN to answer —
        // the neighborhood's record, fed by every
        // organ, together with this engine's own
        // last knock — goes first at a short
        // deadline, with the head of the caller's
        // list: a fast liveness verdict and a fast
        // partial picture. The rest of the census
        // follows only for a host that answered, or
        // one never known. A known host silent on
        // everything it used to answer is itself
        // the finding — the census is not burned
        // proving a dark box is dark.
        let known = Self.knownPorts(for: host)
            .filter { ports.contains($0) }
        var phaseOne = known
        for port in ports.prefix(16)
        where !phaseOne.contains(port) {
            phaseOne.append(port)
        }
        let phaseTwo = ports.filter {
            !phaseOne.contains($0) }
        let shared = KnockShared()
        probePhase(host: host, ports: phaseOne, udp: udp,
                   timeout: min(timeout, 0.6), jobs: jobs,
                   speak: speak, shared: shared) {
            [weak self] in
            guard let self = self,
                  self.generation == gen else { return }
            let answered = shared.found.contains {
                $0.isOpen || !$0.reply.isEmpty }
            if phaseTwo.isEmpty || answered
                || known.isEmpty {
                self.probePhase(host: host, ports: phaseTwo,
                                udp: udp, timeout: timeout,
                                jobs: jobs, speak: speak,
                                shared: shared) {
                    [weak self] in
                    self?.finishKnock(host: host,
                                      ports: ports, gen: gen,
                                      shared: shared)
                }
            } else {
                self.console.append(
                    "knock \(host): silent on all "
                    + "\(phaseOne.count) known ports — "
                    + "the census stands down")
                self.finishKnock(host: host, ports: ports,
                                 gen: gen, shared: shared)
            }
        }
    }

    /// Accumulates one knock's hits across its phases.
    private final class KnockShared {
        var found: [Hit] = []
        let lock = NSLock()
    }

    private func probePhase(host: String, ports: [Int],
                            udp: Bool, timeout: TimeInterval,
                            jobs: Int, speak: Bool,
                            shared: KnockShared,
                            done: @escaping () -> Void) {
        guard !ports.isEmpty else { done(); return }
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(
            value: max(1, min(jobs, 64)))
        for port in ports {
            group.enter()
            queue.async { [weak self] in
                guard let self = self else {
                    group.leave(); return }
                semaphore.wait()
                self.probe(host: host, port: port, udp: udp,
                           timeout: timeout, speak: speak) { hit in
                    if let hit = hit {
                        shared.lock.lock()
                        shared.found.append(hit)
                        shared.lock.unlock()
                    }
                    DispatchQueue.main.async {
                        self.probed += 1 }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { done() }
    }

    private func finishKnock(host: String, ports: [Int],
                             gen: Int, shared: KnockShared) {
        guard generation == gen else { return }
        let sorted = shared.found.sorted {
            ($0.port, $0.udp ? 1 : 0)
                < ($1.port, $1.udp ? 1 : 0) }
        hits = sorted
        knocking = false
        let open = sorted.filter { $0.isOpen }
        ProcessBoard.shared.endKeyed(
            "recon.knock.\(ObjectIdentifier(self))",
            .done("\(open.count) open of \(ports.count)"))
        console.append("knock \(host): \(open.count) open of \(ports.count)")
        if let mouth = mouth {
            mouth.logRecon("knock", host, lines: open.map {
                "\($0.label) \($0.service) \($0.banner)"
            })
            mouth.uiSuccess("Knock: \(open.count) open of \(ports.count)")
        }
        for hit in open {
            NeighborhoodStore.shared.discover(
                source: host, port: hit.port, via: "recon")
        }
        Self.rememberKnock(host: host,
                           openPorts: open.map { $0.port })
    }

    // MARK: - knock memory

    private static let knockMemoryKey = "reconKnockMemory"

    /// The ports a host is known to answer: the
    /// neighborhood's record together with this
    /// engine's own last knock of it.
    private static func knownPorts(for host: String)
        -> [Int] {
        var known = Set<Int>()
        if let neighbor = NeighborhoodStore.shared
            .neighbors.first(where: { $0.ip == host }) {
            known.formUnion(neighbor.ports)
        }
        let memory = UserDefaults.standard.dictionary(
            forKey: knockMemoryKey)
            as? [String: [String: Any]]
        if let entry = memory?[host],
           let ports = entry["ports"] as? [Int] {
            known.formUnion(ports)
        }
        return known.sorted()
    }

    private static func rememberKnock(host: String,
                                      openPorts: [Int]) {
        var memory = UserDefaults.standard.dictionary(
            forKey: knockMemoryKey)
            as? [String: [String: Any]] ?? [:]
        memory[host] = ["ports": openPorts,
                        "when": Date().timeIntervalSince1970]
        UserDefaults.standard.set(memory,
                                  forKey: knockMemoryKey)
    }

    func cancelKnock() {
        generation += 1
        knocking = false
        ProcessBoard.shared.endKeyed(
            "recon.knock.\(ObjectIdentifier(self))",
            .stopped)
    }

    private func probe(host: String, port: Int, udp: Bool, timeout: TimeInterval,
                       speak: Bool, done: @escaping (Hit?) -> Void) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            done(nil)
            return
        }
        let spec = speak ? ReconPayloads.probe(forPort: port, udp: udp) : nil
        let params: NWParameters
        if udp {
            params = .udp
        } else if spec?.tls == true {
            params = NWParameters(tls: NWProtocolTLS.Options())
        } else {
            params = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: params)
        var reply = Data()
        var finished = false
        var wasReady = false
        let finishLock = NSLock()

        func finish(_ state: String) {
            finishLock.lock()
            if finished { finishLock.unlock(); return }
            finished = true
            finishLock.unlock()
            connection.cancel()
            let service = spec?.family ?? "?"
            let banner = ReconPayloads.firstLine(reply)
            var confirmed = false
            if let hint = spec?.hint {
                confirmed = hint.isEmpty ? !reply.isEmpty
                                         : reply.range(of: hint) != nil
            }
            let observed = Self.probeState(state, udp: udp, replyBytes: reply.count)
            done(Hit(port: port, udp: udp, state: observed, service: service,
                     banner: banner, confirmed: confirmed, reply: reply))
        }

        func isReady() -> Bool {
            finishLock.lock()
            defer { finishLock.unlock() }
            return wasReady
        }

        func drain() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty { reply += data }
                if isComplete || error != nil {
                    finish("open")
                } else {
                    drain()
                }
            }
        }

        // Connect deadline: only until the connection is up. Once .ready
        // fires the port IS open and nothing later may un-open it.
        connectionQueue.asyncAfter(deadline: .now() + timeout) {
            if !isReady() {
                finish(udp ? "open|filtered" : "closed")
            } else {
                finish("open")
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finishLock.lock(); wasReady = true; finishLock.unlock()
                if let spec = spec, !spec.build().isEmpty {
                    connection.send(content: spec.build(),
                                    completion: .contentProcessed { _ in drain() })
                } else {
                    drain()
                }
            case .failed, .cancelled:
                if !isReady() { finish(udp ? "open|filtered" : "closed") }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    // MARK: - connect (a console, not a terminal)

    func open(_ rawTarget: String) {
        let text = rawTarget.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let target = try? SendTarget.parse(text) else {
            console.append("nightjar: cannot parse \(text)")
            return
        }
        close()
        switch target {
        case .tcp(let host, let port, let tls):
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: tls ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp),
                    label: target.raw)
        case .udp(let host, let port):
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: .udp),
                    label: target.raw)
        case .http(let url, let https):
            let host = url.host ?? ""
            let port = url.port ?? (https ? 443 : 80)
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: https ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp),
                    label: target.raw)
        default:
            console.append("nightjar: \(target.raw) is not a network target")
        }
    }

    private func connect(_ connection: NWConnection, label: String) {
        consoleConnection = connection
        console.append("— connecting to \(label) —")
        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if let data = data, !data.isEmpty { self.append(data) }
                if isComplete || error != nil {
                    self.console.append("— remote closed —")
                    DispatchQueue.main.async { self.connected = false }
                    return
                }
                pump()
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.connected = true
                    self.console.append("— connected —")
                }
                pump()
            case .failed(let error):
                DispatchQueue.main.async {
                    self.connected = false
                    self.console.append("nightjar: \(error.localizedDescription)")
                }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    func sendLine(_ text: String, crlf: Bool = true) {
        guard let connection = consoleConnection else { return }
        let payload = Data((crlf ? text + "\r\n" : text).utf8)
        console.append("» \(text)")
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    func close() {
        consoleConnection?.cancel()
        consoleConnection = nil
        DispatchQueue.main.async { [weak self] in self?.connected = false }
    }

    private func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.subtracting(CharacterSet.newlines)
                .contains($0)
        }) {
            for line in PayloadKit.hexdump(data).components(separatedBy: "\n") {
                console.append(line)
            }
        } else {
            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                console.append("  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    func clearConsole() { console = [] }

    // MARK: - fuzz

    func startFuzz(target rawTarget: String, seed: Data?, count: Int,
                   length: Int, mutations: Int, seedValue: UInt64?,
                   read: Bool, timeout: TimeInterval) {
        guard !fuzzing, count > 0 else { return }
        guard let target = try? SendTarget.parse(
                rawTarget.trimmingCharacters(in: .whitespaces)) else {
            fuzzLines = ["nightjar: cannot parse \(rawTarget)"]
            return
        }
        fuzzing = true
        fuzzDead = 0
        fuzzLines = ["fuzz \(target.raw) — \(count) mutation(s)"]
        fuzzToken += 1
        let token = fuzzToken
        var rng = seedValue.map { SplitMix64(seed: $0) } ?? SplitMix64(seed: 0x9E3779B97F4A7C15)
        var base = seed ?? Data()
        if base.isEmpty {
            base = Data((0..<max(1, length)).map { _ in UInt8(rng.next() & 0xFF) })
        }
        step(target: target, base: base, index: 1, count: count,
             mutations: mutations, read: read, timeout: timeout,
             rng: rng, corpus: FuzzCorpus(), token: token)
    }

    /// The fuzzer's memory, traveling by value beside
    /// the RNG: the payloads that earned a reply —
    /// above all a NEW reply shape — kept as parents
    /// for later steps, and each mutation
    /// operation's yield this run. The fuzzer used
    /// to restart from the pristine seed on every
    /// step and draw its seven operations uniformly
    /// forever, so nothing it learned from a reply
    /// ever steered the next payload. (Given the
    /// same seed and the same target behavior, the
    /// run is still the same run: every choice here
    /// is an RNG draw.)
    private struct FuzzCorpus {
        var parents: [Data] = []
        var seenShapes: Set<String> = []
        var opYield: [Int] = Array(repeating: 0, count: 7)
        var opTried: [Int] = Array(repeating: 0, count: 7)
    }

    private func step(target: SendTarget, base: Data, index: Int, count: Int,
                      mutations: Int, read: Bool, timeout: TimeInterval,
                      rng: SplitMix64, corpus: FuzzCorpus, token: Int) {
        // The RNG travels by value: an inout parameter cannot be
        // captured by the escaping exchange completion below, and
        // SplitMix64 is a value type — each step mutates its own
        // copy and hands the advanced state to the next step, so
        // the draw sequence is the same continuous stream.
        var rng = rng
        var corpus = corpus
        guard token == fuzzToken else { return }
        if index > count {
            fuzzing = false
            fuzzLines.append("done — \(fuzzDead) dead connection(s)"
                + (corpus.parents.isEmpty ? ""
                   : " · corpus kept \(corpus.parents.count) "
                    + "replying parent(s)"))
            return
        }
        // The parent: once the corpus has earned
        // anything, half the steps build on a payload
        // that already made the target speak, so
        // mutations accumulate on success instead of
        // restarting from the seed.
        var blob: [UInt8]
        if !corpus.parents.isEmpty, rng.next() % 2 == 0 {
            blob = [UInt8](corpus.parents[
                Int(rng.next()
                    % UInt64(corpus.parents.count))])
        } else {
            blob = [UInt8](base)
        }
        var opsUsed: [Int] = []
        for _ in 0..<max(1, mutations) {
            let op = mutate(&blob, &rng,
                            weights: corpus.opYield)
            if op >= 0 { opsUsed.append(op) }
        }
        let payload = Data(blob)
        exchange(target: target, payload: payload, read: read, timeout: timeout) {
            [weak self] reply, failed in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, token == self.fuzzToken else { return }
                // Published UI state must be updated on the main queue.
                if failed { self.fuzzDead += 1 }
                // Grade the operations, and keep the
                // payload as a parent when its reply
                // is a shape this run has not seen.
                for op in opsUsed {
                    corpus.opTried[op] += 1
                    if !failed, !reply.isEmpty {
                        corpus.opYield[op] += 1
                    }
                }
                if !failed, !reply.isEmpty {
                    let shape = "\(reply.count):"
                        + ReconPayloads.firstLine(
                            reply, limit: 24)
                    if corpus.seenShapes.insert(shape)
                        .inserted {
                        corpus.parents.append(payload)
                        if corpus.parents.count > 24 {
                            corpus.parents.removeFirst(
                                corpus.parents.count - 24)
                        }
                    }
                }
                let head = failed ? "DEAD" : ReconPayloads.firstLine(reply, limit: 60)
                self.fuzzLines.append(
                    "  \(String(format: "%5d", index))  len=\(payload.count)  "
                    + "reply=\(reply.count)  \(head)")
                if self.fuzzLines.count > 400 {
                    self.fuzzLines.removeFirst(self.fuzzLines.count - 400)
                }
                self.step(target: target, base: base, index: index + 1,
                          count: count, mutations: mutations, read: read,
                          timeout: timeout, rng: rng, corpus: corpus,
                          token: token)
            }
        }
    }

    func stopFuzz() { fuzzToken += 1; fuzzing = false }

    /// One mutation, drawn by yield: an operation
    /// that has earned replies this run is drawn
    /// oftener, with a floor of one so no operation
    /// ever starves. Returns the operation used, or
    /// -1 when the payload only needed a first byte.
    private func mutate(_ data: inout [UInt8],
                        _ rng: inout SplitMix64,
                        weights: [Int]) -> Int {
        guard !data.isEmpty else {
            data.append(UInt8(rng.next() & 0xFF)); return -1 }
        let totalWeight = (0..<7).reduce(0) {
            $0 + 1 + (weights.indices.contains($1)
                        ? weights[$1] : 0) }
        var draw = Int(rng.next()
            % UInt64(max(1, totalWeight)))
        var op = 6
        for i in 0..<7 {
            draw -= 1 + (weights.indices.contains(i)
                            ? weights[i] : 0)
            if draw < 0 { op = i; break }
        }
        switch op {
        case 0:
            let i = Int(rng.next() % UInt64(data.count))
            data[i] ^= 1 << UInt8(rng.next() % 8)
        case 1:
            data[Int(rng.next() % UInt64(data.count))] = UInt8(rng.next() & 0xFF)
        case 2:
            data.insert(UInt8(rng.next() & 0xFF), at: Int(rng.next() % UInt64(data.count + 1)))
        case 3:
            if data.count > 1 {
                data.remove(at: Int(rng.next() % UInt64(data.count)))
            } else {
                let i = Int(rng.next() % UInt64(data.count))
                data[i] ^= 1 << UInt8(rng.next() % 8)
            }
        case 4:
            let start = Int(rng.next() % UInt64(data.count))
            let end = min(data.count, start + 1 + Int(rng.next() % 16))
            data.insert(contentsOf: data[start..<end], at: start)
        case 5:
            let start = Int(rng.next() % UInt64(data.count))
            let end = min(data.count, start + 1 + Int(rng.next() % 8))
            for i in start..<end { data[i] = UInt8(rng.next() & 0xFF) }
        default:
            data.removeSubrange(Int(rng.next() % UInt64(data.count))..<data.count)
        }
        return op
    }

    /// A deadline is not successful unless the payload was actually sent.
    /// A completed send without a reply is not by itself a dead connection.
    static func timedOutExchangeFailed(didSend: Bool) -> Bool { !didSend }

    private func exchange(target: SendTarget, payload: Data, read: Bool,
                          timeout: TimeInterval,
                          done: @escaping (Data, Bool) -> Void) {
        let host: String
        let port: Int
        let params: NWParameters
        switch target {
        case .tcp(let h, let p, let tls):
            host = h; port = p
            params = tls ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        case .udp(let h, let p):
            host = h; port = p
            params = .udp
        case .http(let url, let https):
            host = url.host ?? ""
            port = url.port ?? (https ? 443 : 80)
            params = https ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        default:
            done(Data(), true)
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            done(Data(), true)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort,
                                      using: params)
        var reply = Data()
        var finished = false
        // NWConnection callbacks and the deadline run on connectionQueue.
        var didSend = false
        let finishLock = NSLock()
        func finish(_ failed: Bool) {
            finishLock.lock()
            if finished { finishLock.unlock(); return }
            finished = true
            finishLock.unlock()
            connection.cancel()
            done(reply, failed)
        }
        func drain() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty { reply += data }
                if error != nil {
                    finish(true)
                } else if isComplete {
                    finish(false)
                } else {
                    drain()
                }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { error in
                    guard error == nil else { finish(true); return }
                    didSend = true
                    if read { drain() } else { finish(false) }
                })
            case .failed, .cancelled:
                finish(true)
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        connectionQueue.asyncAfter(deadline: .now() + timeout + 1) {
            finish(Self.timedOutExchangeFailed(didSend: didSend))
        }
    }

    // MARK: - library handoff

    func payload(for preset: String) -> Data? {
        try? ReconPayloads.build(preset)
    }
}

/// A tiny deterministic RNG, so a fuzz run reproduces from a seed.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
