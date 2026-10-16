import Foundation
import Network
import SwiftUI

/// The canary: a persona service.
///
/// The tripwire listens in silence and learns a prober's
/// first words. A canary goes one better: it ANSWERS, in
/// character — an SSH banner from a plausible Ubuntu box, a
/// web server that serves its little "It works!" page, an
/// MQTT broker that accepts the connection, a mail server
/// that plays along through MAIL FROM. Every byte the prober
/// then commits to the conversation is filed into the Serve
/// inbox as one transcript, through the same arrival funnel
/// as any other payload.
///
/// Deception pointed the defensive way: the persona exists
/// only on this phone, on a port the operator raises, and it
/// speaks only to whoever came knocking on it.
final class CanaryHost: ObservableObject {
    @Published private(set) var runningPersona: String?
    @Published private(set) var runningPort: Int?
    @Published var error: String?

    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private let queue = DispatchQueue(label: "nightjar.canary")
    private weak var mouth: Mouth?

    static let personas = ["ssh", "http", "mqtt", "smtp"]

    static func defaultPort(_ persona: String) -> Int {
        switch persona {
        case "ssh": return 22
        case "http": return 80
        case "mqtt": return 1883
        default: return 25
        }
    }

    static func label(_ persona: String) -> String {
        switch persona {
        case "ssh": return "SSH server"
        case "http": return "HTTP server"
        case "mqtt": return "MQTT broker"
        default: return "SMTP server"
        }
    }

    private final class Session {
        let persona: String
        let peer: String
        var transcript = Data()
        var stage = 0
        var idleWork: DispatchWorkItem?
        init(persona: String, peer: String) {
            self.persona = persona
            self.peer = peer
        }
    }

    func start(mouth: Mouth, persona: String, port: Int) {
        stop()
        self.mouth = mouth
        guard let endpoint = NWEndpoint.Port(
            rawValue: UInt16(clamping: port)) else { return }
        do {
            let listener = try NWListener(using: .tcp,
                                          on: endpoint)
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn, persona: persona)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let err) = state {
                    DispatchQueue.main.async {
                        self?.error = "the canary could not "
                            + "hold port \(port) — the tripwire "
                            + "or Serve may already be on it "
                            + "(\(err.localizedDescription))"
                        self?.runningPersona = nil
                        self?.runningPort = nil
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            DispatchQueue.main.async {
                self.runningPersona = persona
                self.runningPort = port
                self.error = nil
            }
            Journal.log("canary", "start",
                        "\(persona) canary up on port \(port)")
        } catch {
            DispatchQueue.main.async {
                self.error = "canary failed to start: "
                    + error.localizedDescription
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for id in Array(sessions.keys) { finish(id) }
        if runningPersona != nil {
            Journal.log("canary", "stop", "canary down")
        }
        DispatchQueue.main.async {
            self.runningPersona = nil
            self.runningPort = nil
        }
    }

    private func accept(_ connection: NWConnection,
                        persona: String) {
        let id = ObjectIdentifier(connection)
        let session = Session(persona: persona,
                              peer: "\(connection.endpoint)")
        sessions[id] = session
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.finish(id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        switch persona {
        case "ssh":
            send(connection, Data(
                "SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.3\r\n"
                    .utf8))
        case "smtp":
            send(connection, Data(
                "220 mail.example.org ESMTP Postfix (Ubuntu)\r\n"
                    .utf8))
        default:
            break
        }
        read(connection, id: id)
    }

    private func read(_ connection: NWConnection,
                      id: ObjectIdentifier) {
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: 16384) {
            [weak self] data, _, isComplete, error in
            guard let self = self,
                  let session = self.sessions[id] else { return }
            if let data = data, !data.isEmpty {
                session.transcript.append(data)
                self.armIdleFlush(id)
                self.script(connection, session: session,
                            chunk: data)
            }
            if isComplete || error != nil {
                self.finish(id)
            } else {
                self.read(connection, id: id)
            }
        }
    }

    /// The persona scripts: just enough protocol to keep the
    /// prober talking. Everything they say is already captured;
    /// these replies exist so they keep saying it.
    private func script(_ connection: NWConnection,
                        session: Session, chunk: Data) {
        switch session.persona {
        case "http":
            guard session.stage == 0,
                  let text = String(data: session.transcript,
                                    encoding: .utf8),
                  text.contains("\r\n\r\n") else { return }
            session.stage = 1
            let body = "<html><body><h1>It works!</h1>"
                + "</body></html>"
            let head = "HTTP/1.1 200 OK\r\n"
                + "Server: Apache/2.4.57 (Ubuntu)\r\n"
                + "Content-Type: text/html\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n"
            send(connection, Data(head.utf8) + Data(body.utf8))
        case "mqtt":
            guard session.stage == 0,
                  session.transcript.first == 0x10 else { return }
            session.stage = 1
            send(connection, Data([0x20, 0x02, 0x00, 0x00]))
        case "smtp":
            guard let text = String(data: chunk, encoding: .utf8)
            else { return }
            for line in text.uppercased()
                .components(separatedBy: "\r\n") {
                if line.hasPrefix("EHLO")
                    || line.hasPrefix("HELO") {
                    send(connection, Data(
                        "250-mail.example.org\r\n"
                        + "250-PIPELINING\r\n"
                        + "250 8BITMIME\r\n".utf8))
                } else if line.hasPrefix("MAIL FROM") {
                    send(connection, Data("250 2.1.0 Ok\r\n".utf8))
                } else if line.hasPrefix("RCPT TO") {
                    send(connection, Data("250 2.1.5 Ok\r\n".utf8))
                } else if line == "DATA" {
                    send(connection, Data(
                        "354 End data with <CR><LF>.<CR><LF>\r\n"
                            .utf8))
                }
            }
        default:
            break
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) {
        connection.send(content: data,
                        completion: .contentProcessed { _ in })
    }

    private func armIdleFlush(_ id: ObjectIdentifier) {
        sessions[id]?.idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finish(id)
        }
        sessions[id]?.idleWork = work
        queue.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func finish(_ id: ObjectIdentifier) {
        guard let session = sessions.removeValue(forKey: id)
        else { return }
        session.idleWork?.cancel()
        guard !session.transcript.isEmpty else { return }
        mouth?.fileArrival(transport: "canary-\(session.persona)",
                           peer: session.peer,
                           data: session.transcript)
    }
}

/// The Serve tab's canary controls.
struct CanarySectionView: View {
    @EnvironmentObject private var mouth: Mouth
    @ObservedObject var host: CanaryHost
    @AppStorage("canaryPersona") private var persona = "ssh"
    @AppStorage("canaryPort") private var port = "22"

    var body: some View {
        Section(header: Text("Canary"),
                footer: Text("A persona answers whoever knocks, "
                    + "in character, and files everything they "
                    + "say into the inbox as one transcript. "
                    + "One canary at a time, and it cannot share "
                    + "a port with the tripwire or Serve.")) {
            Picker("Persona", selection: $persona) {
                ForEach(CanaryHost.personas, id: \.self) { p in
                    Text(CanaryHost.label(p)).tag(p)
                }
            }
            TextField("Port", text: $port)
                .keyboardType(.numberPad)
                .font(.body.monospaced())
            if let error = host.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let running = host.runningPersona {
                Button(role: .destructive) {
                    host.stop()
                } label: {
                    Label("Stand the canary down — "
                          + "\(CanaryHost.label(running)) on "
                          + "\(host.runningPort ?? 0)",
                          systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    host.start(
                        mouth: mouth, persona: persona,
                        port: Int(port)
                            ?? CanaryHost.defaultPort(persona))
                } label: {
                    Label("Raise the canary",
                          systemImage: "play.circle.fill")
                }
            }
        }
        .onChange(of: persona) { newPersona in
            // Keep the port honest: if it still holds another
            // persona's default, follow the persona.
            let current = Int(port) ?? -1
            if CanaryHost.personas
                .map(CanaryHost.defaultPort).contains(current) {
                port = String(CanaryHost.defaultPort(newPersona))
            }
        }
    }
}
