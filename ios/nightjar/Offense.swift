import Combine
import Foundation
import Network

/// Her offensive kit's moving parts: the postcard
/// (one small delivery, left on a doorstep), the
/// Tomato Barrage (a marked device pestered on a
/// timer, bounded and journaled), and the Prod
/// (one nonsense line to each known door, the
/// answers recorded). All of it works the
/// operator's own wire, on devices the house
/// already knows, inside the Standard's gates:
/// the barrage is a campaign and refuses under
/// EMCON exactly as Net-Assault does; the prod
/// and the interrogation are single sittings,
/// refused wherever probing is refused. Nothing
/// here floods, guesses a credential, or speaks
/// to anything off the home network — it is
/// offense with a wink: pressure, presence, and
/// an excellent memory for who answered rudely.

/// One delivery: connect, leave the bytes, go.
enum Postcard {
    static func deliver(ip: String, port: Int,
                        bytes: Data) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(
                  rawValue: UInt16(port))
        else { return }
        let connection = NWConnection(
            host: NWEndpoint.Host(ip), port: nwPort,
            using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: bytes,
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    })
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: .global(
            qos: .userInitiated))
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 3) {
            connection.cancel()
        }
    }

    /// The tomato, made literal.
    static var tomatoBytes: Data {
        Data("🍅 — nightjar sends its regards.\r\n"
            .utf8)
    }

    /// The barrage's smaller knock.
    static var tapBytes: Data {
        Data("🍅\r\n".utf8)
    }
}

/// A marked device, pestered on purpose: a
/// postcard first, then a small tomato tap every
/// few seconds, round-robin across its known
/// doors — twenty-four deliveries at most, then
/// it stops itself and reports. It exists to be
/// annoying to exactly one household appliance
/// at a time, and its every start is journaled.
final class TomatoBarrage: ObservableObject {

    static let shared = TomatoBarrage()

    @Published private(set) var running = false
    @Published private(set) var targetLabel = ""

    /// Set by her voice: the line to speak when
    /// the barrage ends on its own.
    var onFinished: ((String) -> Void)?

    private var timer: Timer?
    private var deliveries: [(ip: String, name: String,
                               port: Int, first: Bool)] = []
    private var cursor = 0
    private var boardID: UUID?
    private var totalPlanned = 0

    /// Targets: (address, its name, its known
    /// doors). Doors fall back to the usual three
    /// when the board knows none yet.
    func start(targets: [(ip: String, name: String,
                          ports: [Int])]) -> Bool {
        guard !running, !targets.isEmpty
        else { return false }
        var rotation: [(ip: String, name: String,
                         port: Int, first: Bool)] = []
        for target in targets {
            let doors = target.ports.isEmpty
                ? [80, 443, 22] : target.ports
            for (i, port) in doors.enumerated() {
                rotation.append((target.ip, target.name,
                                 port, i == 0))
            }
        }
        // Round-robin the rotation to a hard cap:
        // twenty-four deliveries, then it rests.
        var plan: [(ip: String, name: String,
                     port: Int, first: Bool)] = []
        var i = 0
        while plan.count < 24, !rotation.isEmpty {
            plan.append(rotation[i % rotation.count])
            i += 1
        }
        deliveries = plan
        totalPlanned = plan.count
        cursor = 0
        targetLabel = targets.map { $0.name }
            .joined(separator: ", ")
        running = true
        boardID = ProcessBoard.shared.begin(
            label: String(format: L("Tomato barrage — %@"), targetLabel),
            organ: "Net-Assault",
            detail: String(format: L("%lld deliveries, one door at a time"), totalPlanned),
            stop: { [weak self] in
                _ = self?.cease()
            })
        Journal.log("tomato", "barrage",
                    "barrage opened on \(targetLabel) "
                    + "(\(totalPlanned) deliveries)")
        tick()
        timer = Timer.scheduledTimer(
            withTimeInterval: 4.0, repeats: true) {
            [weak self] _ in self?.tick()
        }
        return true
    }

    private func tick() {
        guard running else { return }
        guard cursor < deliveries.count else {
            finish(natural: true)
            return
        }
        let shot = deliveries[cursor]
        cursor += 1
        Postcard.deliver(
            ip: shot.ip, port: shot.port,
            bytes: shot.first
                ? Postcard.tomatoBytes
                : Postcard.tapBytes)
        if cursor >= deliveries.count {
            finish(natural: true)
        }
    }

    /// Stop without a spoken report (a halt, a
    /// disarm — the house going quiet).
    func stop() {
        guard running else { return }
        finish(natural: false)
    }

    /// Stop with a report of what was delivered.
    @discardableResult
    func cease() -> String {
        guard running else {
            return "No barrage flying."
        }
        let thrown = cursor
        let names = targetLabel
        finish(natural: false)
        return "Barrage stood down — \(thrown) "
            + "tomato(es) delivered to \(names). "
            + "The point, presumably, is made."
    }

    private func finish(natural: Bool) {
        timer?.invalidate()
        timer = nil
        running = false
        let thrown = cursor
        let names = targetLabel
        deliveries = []
        cursor = 0
        if let boardID {
            ProcessBoard.shared.end(
                boardID, .done("\(thrown) delivered"))
            self.boardID = nil
        }
        Journal.log("tomato", "barrage",
                    "barrage closed on \(names): "
                    + "\(thrown) delivered"
                    + (natural ? " (ran its course)"
                               : " (stood down)"))
        if natural {
            onFinished?("The barrage ran its course "
                + "— \(thrown) tomato(es) left on "
                + "\(names)'s doorstep. It will "
                + "remember the attention.")
        }
    }
}

/// One nonsense line, politely delivered to each
/// of a device's known doors; what answers — and
/// how — is the intelligence. Services confess
/// versions to strangers who knock strangely.
final class ProdSession {

    private let ip: String
    private let ports: [Int]
    private var index = 0
    private var lines: [String] = []
    private let done: ([String]) -> Void

    init(ip: String, ports: [Int],
         done: @escaping ([String]) -> Void) {
        self.ip = ip
        self.ports = Array(ports.prefix(6))
        self.done = done
    }

    func start() { next() }

    private func next() {
        guard index < ports.count else {
            done(lines)
            return
        }
        let port = ports[index]
        index += 1
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(port)) else { next(); return }
        let connection = NWConnection(
            host: NWEndpoint.Host(ip), port: nwPort,
            using: .tcp)
        var settled = false
        let settle: (String) -> Void = { line in
            guard !settled else { return }
            settled = true
            connection.cancel()
            self.lines.append(line)
            self.next()
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(
                    content: Data("knock knock. 🍅\r\n"
                        .utf8),
                    completion: .contentProcessed { _ in
                        connection.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: 512) {
                            data, _, _, _ in
                            if let data = data,
                               !data.isEmpty {
                                let text = String(
                                    decoding: data,
                                    as: UTF8.self)
                                    .split(whereSeparator: {
                                        $0 == "\n"
                                            || $0 == "\r"
                                    }).first
                                    .map(String.init) ?? ""
                                settle("port \(port) "
                                    + "answered the prod: "
                                    + "'\(text)'")
                            } else {
                                settle("port \(port) "
                                    + "took it in silence")
                            }
                        }
                    })
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + 1.5) {
                    settle("port \(port) took it "
                        + "in silence")
                }
            case .failed:
                settle("port \(port) didn't answer — "
                    + "the door's shut since the "
                    + "board learned it")
            default:
                break
            }
        }
        connection.start(queue: .global(
            qos: .userInitiated))
    }
}
