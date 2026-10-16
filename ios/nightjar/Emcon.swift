import Combine
import Foundation
import Network
import UIKit

/// EMCON — emissions control. The defensive half of nightjar-hack:
/// turn the app's own instruments inward so the operator can see
/// (and shut down) what this device announces to the network, and
/// hear anyone who comes probing with the same techniques.
///
/// Three parts:
///  - Self-recon: knock this device with Recon's own probe registry
///    and itemize what answers — the view another operator gets.
///  - Silence: one switch forces Serve stealth, disarms the BLE
///    GATT host and stops the BLE beacon. EMCON never re-opens an
///    emission on its own; turning EMCON off leaves stealth as it
///    finds it.
///  - Tripwire: quiet listeners on the probe ports. The probes are
///    wire-exact, which makes them fingerprintable — a knock with
///    this app's own first words is recognized and logged with its
///    source. The tripwire never replies.
///
/// Honest limit, also stated in the UI: nothing at the app layer can
/// hide the device from the access point it is associated with, and
/// Apple's own radios answer to Settings, not to this app. EMCON
/// strips what identifies the device and turns probing into an
/// announcement by the prober.
final class Emcon: ObservableObject {

    struct Exposure: Identifiable {
        var id: String { "\(host):\(port)" }
        let host: String
        let port: Int
        let service: String
        let banner: String
        let confirmed: Bool
    }

    struct TripEvent: Identifiable {
        let id = UUID()
        let when: Date
        let source: String
        let port: Int
        let verdict: String
        let byteCount: Int
    }

    @Published private(set) var active: Bool
    @Published private(set) var scanning = false
    @Published private(set) var exposures: [Exposure] = []
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var tripwireOn = false
    @Published private(set) var watched: [Int] = []
    @Published private(set) var unwatched: [Int] = []
    @Published private(set) var events: [TripEvent] = []

    private var listeners: [NWListener] = []
    private let tripQueue = DispatchQueue(label: "nightjar.emcon.tripwire")
    private static let activeKey = "emconActive"

    init() {
        active = UserDefaults.standard.bool(forKey: Self.activeKey)
    }

    var deviceName: String { UIDevice.current.name }
    var ownIP: String? { Mouth.localIPAddress() }

    // MARK: - posture

    /// Go dark: silence every emission the app controls and arm the
    /// tripwire. Serve listeners keep running if they were running,
    /// but under stealth — unlisted, silent arrivals.
    func activate(mouth: Mouth) {
        active = true
        UserDefaults.standard.set(true, forKey: Self.activeKey)
        mouth.setStealth(true)
        if mouth.gattHostOn { mouth.stopGattHost() }
        if mouth.beaconOn { mouth.stopBeacon() }
        startTripwire()
    }

    /// Stand down the tripwire. Stealth, the GATT host and the
    /// beacon are left exactly as they are — re-arming an emission
    /// is always a deliberate act in its own tab.
    func deactivate() {
        active = false
        UserDefaults.standard.set(false, forKey: Self.activeKey)
        stopTripwire()
    }

    /// On tab appearance after a relaunch: if EMCON was left active,
    /// re-arm the tripwire so the posture survives restarts the way
    /// the GATT host arm does.
    func restoreIfNeeded() {
        if active, !tripwireOn { startTripwire() }
    }

    // MARK: - self-recon

    /// Knock this device on every port in Recon's registry, over
    /// both loopback and the LAN address, speaking each port's own
    /// probe. Whatever answers is what another operator sees.
    func runSelfScan() {
        guard !scanning else { return }
        scanning = true
        exposures = []
        var hosts = ["127.0.0.1"]
        if let ip = ownIP, ip != "127.0.0.1" { hosts.append(ip) }
        let ports = ReconPayloads.defaultPorts
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 24)
        let lock = NSLock()
        var found: [Exposure] = []
        for host in hosts {
            for port in ports {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    semaphore.wait()
                    Self.probe(host: host, port: port) { exposure in
                        if let exposure = exposure {
                            lock.lock()
                            found.append(exposure)
                            lock.unlock()
                        }
                        semaphore.signal()
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.exposures = found.sorted {
                ($0.host, $0.port) < ($1.host, $1.port)
            }
            self.lastScanAt = Date()
            self.scanning = false
        }
    }

    /// One connect + optional probe + banner read against a single
    /// host:port, Recon's exchange discipline at a shorter fuse.
    private static func probe(host: String, port: Int,
                              done: @escaping (Exposure?) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            done(nil)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "nightjar.emcon.selfscan")
        var finished = false
        let lock = NSLock()
        func finish(_ result: Exposure?) {
            lock.lock()
            if finished { lock.unlock(); return }
            finished = true
            lock.unlock()
            connection.cancel()
            done(result)
        }
        let probe = ReconPayloads.probe(forPort: port, udp: false)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let probe = probe else {
                    finish(Exposure(host: host, port: port,
                                    service: "open", banner: "",
                                    confirmed: false))
                    return
                }
                connection.send(content: probe.build(),
                                completion: .contentProcessed { _ in
                    connection.receive(minimumIncompleteLength: 1,
                                       maximumLength: 4096) {
                        data, _, _, _ in
                        let reply = data ?? Data()
                        let confirmed = probe.hint.isEmpty
                            ? !reply.isEmpty
                            : reply.range(of: probe.hint) != nil
                        finish(Exposure(
                            host: host, port: port,
                            service: probe.name,
                            banner: ReconPayloads.firstLine(
                                reply, limit: 80),
                            confirmed: confirmed))
                    }
                })
                queue.asyncAfter(deadline: .now() + 1.2) {
                    finish(Exposure(host: host, port: port,
                                    service: probe.name, banner: "",
                                    confirmed: false))
                }
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 0.9) {
            // Still not ready after the connect fuse: nothing there.
            // (If it became ready, the read fuse governs instead.)
            lock.lock()
            let doneAlready = finished
            lock.unlock()
            if !doneAlready, connection.state != .ready { finish(nil) }
        }
    }

    // MARK: - tripwire

    /// Bind a silent listener on every TCP port in the probe
    /// registry. Ports already in use (Serve, the OS) are reported
    /// as unwatched rather than fought over.
    func startTripwire() {
        guard !tripwireOn else { return }
        var bound: [Int] = []
        var failed: [Int] = []
        for port in ReconPayloads.defaultPorts {
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port))
            else { failed.append(port); continue }
            do {
                let listener = try NWListener(using: .tcp, on: nwPort)
                listener.newConnectionHandler = { [weak self] conn in
                    self?.handleTrip(conn, port: port)
                }
                listener.start(queue: tripQueue)
                listeners.append(listener)
                bound.append(port)
            } catch {
                failed.append(port)
            }
        }
        watched = bound
        unwatched = failed
        tripwireOn = true
    }

    func stopTripwire() {
        for listener in listeners { listener.cancel() }
        listeners = []
        watched = []
        unwatched = []
        tripwireOn = false
    }

    func clearEvents() { events = [] }

    private func handleTrip(_ connection: NWConnection, port: Int) {
        let source: String
        if case .hostPort(let host, _) = connection.endpoint {
            source = host.debugDescription
        } else {
            source = "unknown"
        }
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: tripQueue)
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: 1024) { [weak self] data, _, _, _ in
            let bytes = data ?? Data()
            let verdict = Self.fingerprint(bytes, port: port)
            connection.cancel()
            guard let self = self else { return }
            DispatchQueue.main.async {
                let mine = self.ownIP != nil && source.contains(self.ownIP!)
                self.events.insert(
                    TripEvent(when: Date(),
                              source: mine ? "\(source) (this device)"
                                           : source,
                              port: port, verdict: verdict,
                              byteCount: bytes.count),
                    at: 0)
                if self.events.count > 200 {
                    self.events.removeLast(self.events.count - 200)
                }
            }
        }
        // A connection that sends nothing still counts: someone
        // knocked and waited. Log it after a short grace period if
        // no bytes arrived (receive above simply never fires).
        tripQueue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            // If the receive fired, the connection was cancelled and
            // this block still runs; the duplicate is suppressed by
            // checking the connection state.
            if connection.state == .ready {
                connection.cancel()
                DispatchQueue.main.async {
                    self.events.insert(
                        TripEvent(when: Date(), source: source,
                                  port: port,
                                  verdict: "silent knock (no bytes sent)",
                                  byteCount: 0),
                        at: 0)
                }
            }
        }
    }

    /// Recognize first words. The probe builders are deterministic,
    /// so a byte stream that matches a builder's output — in either
    /// direction, to allow for partial sends — is that probe.
    private static func fingerprint(_ data: Data, port: Int) -> String {
        guard !data.isEmpty else { return "empty connection" }
        for probe in ReconPayloads.all.values where !probe.udp {
            let signature = probe.build()
            guard signature.count >= 3 else { continue }
            if data.hasPrefix(signature) || signature.hasPrefix(data) {
                return probe.port == port
                    ? "nightjar-hack probe: \(probe.name)"
                    : "nightjar-hack probe: \(probe.name) "
                        + "(on the wrong port)"
            }
        }
        let text = String(decoding: data, as: UTF8.self)
        let printable = text.split(whereSeparator: {
            $0 == "\n" || $0 == "\r"
        }).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
        }
        let line = ReconPayloads.firstLine(data, limit: 60)
        return printable
            ? "unrecognized probe: \(line)"
            : "unrecognized bytes (\(data.count)): \(line)"
    }
}
