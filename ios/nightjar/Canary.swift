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
    @Published private(set) var dropArmed = false
    @Published var error: String?

    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private let queue = DispatchQueue(label: "nightjar.canary")
    private weak var mouth: Mouth?
    private var dropText = ""

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
        var dropTaken = false
        var dropNote = ""
        var idleWork: DispatchWorkItem?
        init(persona: String, peer: String) {
            self.persona = persona
            self.peer = peer
        }
    }

    func start(mouth: Mouth, persona: String, port: Int,
               honeydrop: Bool, drop: String) {
        stop()
        self.mouth = mouth
        dropArmed = honeydrop
        dropText = drop
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
                        "\(persona) canary up on port \(port)"
                        + (honeydrop ? " — honeydrop phase "
                            + "armed" : ""))
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
        dropArmed = false
        DispatchQueue.main.async {
            self.runningPersona = nil
            self.runningPort = nil
        }
    }

    // MARK: - the honeydrop

    /// The drop a persona hands over when the honeydrop phase
    /// is armed: the operator's own text when they wrote one,
    /// otherwise the persona's stock lure. Every drop is a
    /// decoy — plausible to a prober, worthless in fact, and
    /// unique enough that taking it is unmistakable.
    private func drop(for persona: String) -> Data {
        if !dropText.isEmpty { return Data(dropText.utf8) }
        switch persona {
        case "http":
            var text = "APP_ENV=production\n"
            text += "DB_HOST=db.internal\n"
            text += "DB_NAME=app\n"
            text += "DB_USER=backup_svc\n"
            text += "BACKUP_DIR=/var/backups/nightly\n"
            text += "BACKUP_FILE=db_dump_2026-10-15.sql.gz\n"
            return Data(text.utf8)
        case "mqtt":
            return Data(("{\"site\":\"home\",\"config\":"
                + "\"rev 41\",\"backup\":\"nas.internal:445\"}")
                .utf8)
        case "smtp":
            let text = "archive copy: https://mail.example.org"
                + "/archive/2026/10/msg-4471"
            return Data(text.utf8)
        default:
            return Data()
        }
    }

    /// A taken drop is the loudest signal the canary produces:
    /// journaled as its own event the moment it happens, and
    /// stamped into the transcript when the session files.
    private func takeDrop(_ session: Session, note: String) {
        guard !session.dropTaken else { return }
        session.dropTaken = true
        session.dropNote = note
        Journal.log("canary", "honeydrop",
                    "drop taken by \(session.peer) — \(note)")
    }

    /// A correctly-framed SSH KEXINIT packet — the SSH
    /// persona's drop. A prober that parses it and answers
    /// with its own algorithm lists has taken the bait and
    /// told you exactly what it is.
    private func sshKexInit() -> Data {
        func nameList(_ names: [String]) -> Data {
            let joined = names.joined(separator: ",")
            var out = Data()
            var len = UInt32(joined.utf8.count).bigEndian
            out.append(Data(bytes: &len, count: 4))
            out.append(Data(joined.utf8))
            return out
        }
        var payload = Data([20])
        payload.append(Data((0..<16).map { _ in
            UInt8.random(in: 0...255) }))
        payload.append(nameList(
            ["curve25519-sha256", "diffie-hellman-group14-sha256"]))
        payload.append(nameList(["ssh-ed25519", "rsa-sha2-512"]))
        payload.append(nameList(
            ["chacha20-poly1305@openssh.com", "aes128-ctr"]))
        payload.append(nameList(
            ["chacha20-poly1305@openssh.com", "aes128-ctr"]))
        payload.append(nameList(["hmac-sha2-256", "hmac-sha1"]))
        payload.append(nameList(["hmac-sha2-256", "hmac-sha1"]))
        payload.append(nameList(["none"]))
        payload.append(nameList(["none"]))
        payload.append(nameList([]))
        payload.append(nameList([]))
        payload.append(0)  // first_kex_packet_follows: false
        var reserved = UInt32(0).bigEndian
        payload.append(Data(bytes: &reserved, count: 4))
        var packetLength = payload.count + 1 + 4
        let remainder = (packetLength + 4) % 8
        if remainder != 0 { packetLength += 8 - remainder }
        let padding = packetLength - payload.count - 1
        var packet = Data()
        var lenBE = UInt32(packetLength).bigEndian
        packet.append(Data(bytes: &lenBE, count: 4))
        packet.append(UInt8(padding))
        packet.append(payload)
        packet.append(Data(repeating: 0, count: padding))
        return packet
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

    /// The paths web probers reach for first — where the
    /// honeydrop waits when the phase is armed.
    private static let baitPaths = ["/backup.zip", "/backup",
        "/.env", "/config.json", "/admin", "/db.sql",
        "/.git/config"]

    /// The persona scripts: just enough protocol to keep the
    /// prober talking. Everything they say is already captured;
    /// these replies exist so they keep saying it — and, with
    /// the honeydrop armed, so they reach for the prize.
    private func script(_ connection: NWConnection,
                        session: Session, chunk: Data) {
        switch session.persona {
        case "http":
            guard session.stage == 0,
                  let text = String(data: session.transcript,
                                    encoding: .utf8),
                  text.contains("\r\n\r\n") else { return }
            session.stage = 1
            let requestLine = text.components(
                separatedBy: "\r\n").first ?? ""
            let rawPath = requestLine
                .components(separatedBy: " ")
                .dropFirst().first ?? "/"
            let path = rawPath.components(
                separatedBy: "?").first ?? rawPath
            if dropArmed,
               CanaryHost.baitPaths.contains(path) {
                let lure = drop(for: "http")
                let head = "HTTP/1.1 200 OK\r\n"
                    + "Server: Apache/2.4.57 (Ubuntu)\r\n"
                    + "Content-Type: text/plain\r\n"
                    + "Content-Length: \(lure.count)\r\n"
                    + "Connection: close\r\n\r\n"
                send(connection, Data(head.utf8) + lure)
                takeDrop(session, note: "http GET \(path)")
            } else {
                let body = "<html><body><h1>It works!</h1>"
                    + "</body></html>"
                let head = "HTTP/1.1 200 OK\r\n"
                    + "Server: Apache/2.4.57 (Ubuntu)\r\n"
                    + "Content-Type: text/html\r\n"
                    + "Content-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n"
                send(connection, Data(head.utf8) + Data(body.utf8))
            }
        case "mqtt":
            if session.stage == 0,
               session.transcript.first == 0x10 {
                session.stage = 1
                send(connection, Data([0x20, 0x02, 0x00, 0x00]))
            } else if session.stage == 1, dropArmed,
                      chunk.first == 0x82, chunk.count >= 6 {
                // A SUBSCRIBE: grant it, then publish the drop
                // on the very topic they asked about.
                let packetId = Array(chunk[2...3])
                let topicLength = Int(chunk[4]) << 8
                    | Int(chunk[5])
                guard chunk.count >= 6 + topicLength
                else { return }
                let topic = Array(chunk[6..<(6 + topicLength)])
                var out = Data([0x90, 0x03])
                out.append(contentsOf: packetId)
                out.append(0x00)
                let lure = drop(for: "mqtt")
                let remaining = 2 + topicLength + lure.count
                var publish = Data([0x30])
                var value = remaining
                repeat {
                    var byte = UInt8(value % 128)
                    value /= 128
                    if value > 0 { byte |= 0x80 }
                    publish.append(byte)
                } while value > 0
                publish.append(UInt8(topicLength >> 8))
                publish.append(UInt8(topicLength & 0xFF))
                publish.append(contentsOf: topic)
                publish.append(lure)
                out.append(publish)
                send(connection, out)
                session.stage = 2
                takeDrop(session, note: "mqtt subscribe — drop "
                    + "published on their topic")
            }
        case "smtp":
            guard let text = String(data: chunk, encoding: .utf8)
            else { return }
            for line in text.uppercased()
                .components(separatedBy: "\r\n") {
                if line.hasPrefix("EHLO")
                    || line.hasPrefix("HELO") {
                    send(connection, Data(
                        "250-mail.example.org\r\n250-PIPELINING\r\n250 8BITMIME\r\n"
                            .utf8))
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
            // The completed message is the deepest engagement
            // this persona offers: answer it like a real server,
            // carrying the drop in the receipt when armed.
            if session.stage == 0,
               let all = String(data: session.transcript,
                                encoding: .utf8),
               all.contains("\r\n.\r\n") {
                session.stage = 1
                if dropArmed {
                    let receipt = drop(for: "smtp")
                    send(connection, Data("250 2.0.0 Ok ".utf8)
                         + receipt + Data("\r\n".utf8))
                    takeDrop(session, note: "smtp message "
                        + "completed — drop in the receipt")
                } else {
                    send(connection,
                         Data("250 2.0.0 Ok\r\n".utf8))
                }
            }
        case "ssh":
            if session.stage == 0, dropArmed,
               let text = String(data: session.transcript,
                                 encoding: .utf8),
               let firstLine = text.components(
                   separatedBy: "\r\n").first,
               firstLine.hasPrefix("SSH-") {
                // They identified themselves; offer the prize:
                // a real key-exchange opening to answer.
                session.stage = 1
                send(connection, sshKexInit())
            } else if session.stage == 1 {
                // Any bytes after the KEXINIT are an answer to
                // it — algorithm lists, a client speaking its
                // whole stack to a box that does not exist.
                takeDrop(session, note: "ssh prober answered "
                    + "the KEXINIT")
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
        var data = session.transcript
        if session.dropTaken {
            data = Data("[honeydrop taken — \(session.dropNote)]"
                .utf8) + Data([0x0A]) + data
        }
        mouth?.fileArrival(transport: "canary-\(session.persona)",
                           peer: session.peer,
                           data: data)
    }
}

/// The Serve tab's canary controls.
struct CanarySectionView: View {
    @EnvironmentObject private var mouth: Mouth
    @ObservedObject var host: CanaryHost
    @AppStorage("canaryPersona") private var persona = "ssh"
    @AppStorage("canaryPort") private var port = "22"
    @AppStorage("canaryHoneydrop") private var honeydrop = false
    @AppStorage("canaryDrop") private var drop = ""

    var body: some View {
        Section(header: Text("Canary"),
                footer: Text("A persona answers whoever knocks, "
                    + "in character, and files everything they "
                    + "say into the inbox as one transcript. "
                    + "One canary at a time, and it cannot share "
                    + "a port with the tripwire or Serve. "
                    + "Honeydrop is the activate phase beyond "
                    + "answering: the persona carries a prize — "
                    + "a bait file, a published message, a "
                    + "receipt, a key exchange — and a prober "
                    + "who takes it is journaled on the spot.")) {
            Picker("Persona", selection: $persona) {
                ForEach(CanaryHost.personas, id: \.self) { p in
                    Text(CanaryHost.label(p)).tag(p)
                }
            }
            TextField("Port", text: $port)
                .keyboardType(.numberPad)
                .font(.body.monospaced())
            Toggle("Honeydrop phase", isOn: $honeydrop)
            if honeydrop {
                TextField("Drop text (blank = stock lure)",
                          text: $drop)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.body.monospaced())
            }
            if let error = host.error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let running = host.runningPersona {
                if host.dropArmed {
                    Text("Honeydrop armed — the \(CanaryHost.label(running).lowercased()) "
                         + "is carrying its drop.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                            ?? CanaryHost.defaultPort(persona),
                        honeydrop: honeydrop, drop: drop)
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
