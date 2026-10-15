import Combine
import Foundation
import Network

/// The recon bench engine: knock, connect, fuzz.
///
/// Same shape as `ScanModel`: a concurrent worker queue gated by a
/// semaphore, and a separate serial queue for NWConnection starts and
/// deadlines so a connection is never starved behind its own gating.
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

    @Published private(set) var fuzzing = false
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

    // MARK: - knock

    func knock(host rawHost: String, ports: [Int], udp: Bool,
               timeout: TimeInterval = 1.5, jobs: Int = 24,
               speak: Bool = true) {
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !ports.isEmpty, !knocking else { return }
        knocking = true
        hits = []
        probed = 0
        total = ports.count
        lastKnocked = host
        generation += 1
        let gen = generation
        var found: [Hit] = []
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: max(1, min(jobs, 64)))
        for port in ports {
            group.enter()
            queue.async { [weak self] in
                guard let self = self else { group.leave(); return }
                semaphore.wait()
                self.probe(host: host, port: port, udp: udp,
                           timeout: timeout, speak: speak) { hit in
                    if let hit = hit {
                        self.lock.lock()
                        found.append(hit)
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { self.probed += 1 }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.generation == gen else { return }
            let sorted = found.sorted { ($0.port, $0.udp ? 1 : 0) < ($1.port, $1.udp ? 1 : 0) }
            self.hits = sorted
            self.knocking = false
            let open = sorted.filter { $0.isOpen }
            self.console.append("knock \(host): \(open.count) open of \(ports.count)")
            if let mouth = self.mouth {
                mouth.logRecon("knock", host, lines: open.map {
                    "\($0.label) \($0.service) \($0.banner)"
                })
                mouth.uiSuccess("Knock: \(open.count) open of \(ports.count)")
            }
        }
    }

    func cancelKnock() {
        generation += 1
        knocking = false
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
            done(Hit(port: port, udp: udp, state: state, service: service,
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

    func sendBytes(_ data: Data, label: String) {
        guard let connection = consoleConnection else { return }
        console.append("» \(label) (\(data.count) bytes)")
        connection.send(content: data, completion: .contentProcessed { _ in })
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
             rng: &rng, token: token)
    }

    private func step(target: SendTarget, base: Data, index: Int, count: Int,
                      mutations: Int, read: Bool, timeout: TimeInterval,
                      rng: inout SplitMix64, token: Int) {
        guard token == fuzzToken else { return }
        if index > count {
            fuzzing = false
            fuzzLines.append("done — \(fuzzDead) dead connection(s)")
            return
        }
        var blob = [UInt8](base)
        for _ in 0..<max(1, mutations) { mutate(&blob, &rng) }
        let payload = Data(blob)
        exchange(target: target, payload: payload, read: read, timeout: timeout) {
            [weak self] reply, failed in
            guard let self = self, token == self.fuzzToken else { return }
            if failed { self.fuzzDead += 1 }
            let head = failed ? "DEAD" : ReconPayloads.firstLine(reply, limit: 60)
            DispatchQueue.main.async {
                self.fuzzLines.append(
                    "  \(String(format: "%5d", index))  len=\(payload.count)  "
                    + "reply=\(reply.count)  \(head)")
                if self.fuzzLines.count > 400 {
                    self.fuzzLines.removeFirst(self.fuzzLines.count - 400)
                }
                self.step(target: target, base: base, index: index + 1,
                          count: count, mutations: mutations, read: read,
                          timeout: timeout, rng: &rng, token: token)
            }
        }
    }

    func stopFuzz() { fuzzToken += 1; fuzzing = false }

    private func mutate(_ data: inout [UInt8], _ rng: inout SplitMix64) {
        guard !data.isEmpty else { data.append(UInt8(rng.next() & 0xFF)); return }
        switch Int(rng.next() % 7) {
        case 0:
            let i = Int(rng.next() % UInt64(data.count))
            data[i] ^= 1 << UInt8(rng.next() % 8)
        case 1:
            data[Int(rng.next() % UInt64(data.count))] = UInt8(rng.next() & 0xFF)
        case 2:
            data.insert(UInt8(rng.next() & 0xFF), at: Int(rng.next() % UInt64(data.count + 1)))
        case 3 where data.count > 1:
            data.remove(at: Int(rng.next() % UInt64(data.count)))
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
    }

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
                if isComplete || error != nil { finish(false) } else { drain() }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { _ in
                    if read { drain() } else { finish(false) }
                })
            case .failed:
                finish(true)
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        connectionQueue.asyncAfter(deadline: .now() + timeout + 1) { finish(false) }
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
