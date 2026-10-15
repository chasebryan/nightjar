//
//  Crawl.swift
//  nightjar-hack
//
//  The Centipede, as an extension on Mouth: route expansion
//  (targets, ranges, port trains, per-device walks), the crawl
//  itself (chain/seed modes, the return-to-sender leg, the
//  homecoming and its optional delivery), and the discovery
//  sweep that feeds the route. Split out of Mouth.swift when
//  that file outgrew comfortable editing; the crawl's state
//  (crawlBusy, crawlLines, crawlHomecoming, crawlSweep*) stays
//  on Mouth itself, since extensions hold no stored properties.
//

import Foundation
import Network

extension Mouth {

    /// Expand a centipede route into the flat list of stops it
    /// will visit, in order. Each line of the route is one of:
    ///   - any ordinary target (tcp://h:p, udp://, http(s)://…,
    ///     phone:NAME)
    ///   - a last-octet range (the expandRange syntax)
    ///   - host:80,443,6379 — a port train across those ports
    ///   - a bare host — a port train across the usual scan ports
    /// Range-shaped lines that fail validation come back in
    /// `invalid` so they are reported, never aimed at. Stops are
    /// NOT deduplicated: a walk may visit the same door twice on
    /// purpose.
    static func expandRoute(_ lines: [String])
        -> (stops: [String], invalid: [String])
    {
        var stops: [String] = []
        var invalid: [String] = []
        for entry in lines {
            let text = entry.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            if let range = Mouth.expandRange(text) {
                stops += range
                continue
            }
            if Mouth.looksLikeRange(text) {
                invalid.append(text)
                continue
            }
            if text.hasPrefix("phone:")
                || text.hasPrefix("http://")
                || text.hasPrefix("https://")
            {
                stops.append(text)
                continue
            }
            var scheme = "tcp"
            var rest = text
            if let split = text.range(of: "://") {
                scheme = String(text[..<split.lowerBound])
                rest = String(text[split.upperBound...])
            }
            guard let colon = rest.lastIndex(of: ":") else {
                // A bare host: a train across the usual ports.
                stops += ScanModel.topPorts.map {
                    "\(scheme)://\(rest):\($0.0)"
                }
                continue
            }
            let host = String(rest[..<colon])
            let portPart = String(rest[rest.index(after: colon)...])
            if portPart.contains(",") {
                let ports = portPart
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(
                        in: .whitespaces)) }
                    .filter { (1...65535).contains($0) }
                if ports.isEmpty {
                    invalid.append(text)
                } else {
                    stops += ports.map { "\(scheme)://\(host):\($0)" }
                }
            } else if let port = Int(portPart), (1...65535).contains(port) {
                stops.append("\(scheme)://\(host):\(port)")
            } else {
                // Not a shape we unfold; let the hop itself judge
                // it (parse failures are reported in the trail).
                stops.append(text)
            }
        }
        return (stops, invalid)
    }

    /// One hop of a crawl: where it goes, which leg it belongs
    /// to, and whether the chain resets there (a fresh device
    /// starting its own walk in per-device mode).
    struct CrawlHop {
        let text: String
        let leg: String
        let blockStart: Bool
    }

    /// Build the full journey for a crawl. One-journey mode: the
    /// route's stops, then (with `returnLeg`) the same stops in
    /// reverse. Per-device mode: every route line is a device and
    /// each device gets its own out-and-back walk — a range line
    /// contributes one single-door device per expanded target.
    static func expandJourney(route rawLines: [String],
                              perDevice: Bool, returnLeg: Bool)
        -> (hops: [CrawlHop], invalid: [String])
    {
        if !perDevice {
            let (stops, bad) = expandRoute(rawLines)
            var hops = stops.map {
                CrawlHop(text: $0, leg: "out", blockStart: false)
            }
            if !hops.isEmpty {
                hops[0] = CrawlHop(text: hops[0].text, leg: "out",
                                   blockStart: true)
            }
            if returnLeg {
                hops += stops.reversed().map {
                    CrawlHop(text: $0, leg: "back", blockStart: false)
                }
            }
            return (hops, bad)
        }
        var hops: [CrawlHop] = []
        var invalid: [String] = []
        for entry in rawLines {
            let text = entry.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            let devices: [String]
            if let range = Mouth.expandRange(text) {
                devices = range
            } else if Mouth.looksLikeRange(text) {
                invalid.append(text)
                continue
            } else {
                devices = [text]
            }
            for device in devices {
                let walk = deviceWalk(device)
                var block = walk.map {
                    CrawlHop(text: $0, leg: "out", blockStart: false)
                }
                if returnLeg {
                    block += walk.reversed().map {
                        CrawlHop(text: $0, leg: "back",
                                 blockStart: false)
                    }
                }
                if !block.isEmpty {
                    block[0] = CrawlHop(text: block[0].text,
                                        leg: "out", blockStart: true)
                    hops += block
                }
            }
        }
        return (hops, invalid)
    }

    /// One device's outward walk in per-device mode: a phone or a
    /// URL is a single stop; a host with an explicit single port
    /// is that one door; `host:80,443` is a train over those
    /// ports; a bare host is a train across the usual ports.
    static func deviceWalk(_ device: String) -> [String] {
        if device.hasPrefix("phone:") || device.hasPrefix("http://")
            || device.hasPrefix("https://")
        {
            return [device]
        }
        var scheme = "tcp"
        var rest = device
        if let split = device.range(of: "://") {
            scheme = String(device[..<split.lowerBound])
            rest = String(device[split.upperBound...])
        }
        guard let colon = rest.lastIndex(of: ":") else {
            return ScanModel.topPorts.map { "\(scheme)://\(rest):\($0.0)" }
        }
        let host = String(rest[..<colon])
        let portPart = String(rest[rest.index(after: colon)...])
        if portPart.contains(",") {
            let ports = portPart
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(
                    in: .whitespaces)) }
                .filter { (1...65535).contains($0) }
            return ports.map { "\(scheme)://\(host):\($0)" }
        }
        return [device]
    }

    /// How many hops a crawl of this route would make (capped).
    static func journeyCount(route rawLines: [String],
                             perDevice: Bool, returnLeg: Bool) -> Int {
        min(expandJourney(route: rawLines, perDevice: perDevice,
                          returnLeg: returnLeg).hops.count, 300)
    }

    /// Walk a route one hop at a time. In "seed" mode every hop
    /// sends the payload built for it; in "chain" mode each hop
    /// after the first sends the previous hop's reply verbatim —
    /// the payload evolves as it travels. With `returnLeg` the
    /// creature then walks the same route backwards, and whatever
    /// it carries at the end comes home: published as
    /// `crawlHomecoming` and, when `homeTarget` is set, sent there
    /// once. In per-device mode every route line is a device that
    /// gets its own walk, and the chain resets at each device.
    /// The phone performs every send on both legs; nothing
    /// is installed, left running, or re-sent by any target.
    func crawl(route rawLines: [String], mode: String,
               returnLeg: Bool, perDevice: Bool, homeTarget: String,
               payloadFor: @escaping (String) -> Data?,
               framing: String, method: String) {
        guard !crawlBusy else { return }
        let (hops, invalid) = Mouth.expandJourney(
            route: rawLines, perDevice: perDevice,
            returnLeg: returnLeg)
        guard !hops.isEmpty else {
            crawlLines = invalid.map { "✗ \($0) — invalid range" }
            return
        }
        crawlGeneration += 1
        let generation = crawlGeneration
        let total = min(hops.count, 300)
        let journey = Array(hops.prefix(total))
        crawlBusy = true
        crawlHomecoming = nil
        crawlLines = ["Centipede released — \(total) hop(s)"
                      + (returnLeg ? ", out and back" : "")
                      + (perDevice ? ", per device" : "")]
        for text in invalid {
            crawlLines.append("✗ \(text) — invalid range")
        }
        line("centipede: \(total) hops, mode \(mode)")
        var index = 0
        var carried: Data?
        func trail(_ text: String) {
            DispatchQueue.main.async { [weak self] in
                self?.crawlLines.append(text)
            }
        }
        func finishJourney() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.crawlBusy = false
                self.crawlHomecoming = carried
                self.crawlLines.append(
                    "Home — carrying \(carried?.count ?? 0) byte(s)")
                self.logRecon("centipede", "\(total) hops",
                              lines: self.crawlLines)
                self.toasts?.show("Centipede home — "
                    + "\(carried?.count ?? 0) bytes back")
            }
            let home = homeTarget.trimmingCharacters(in: .whitespaces)
            if !home.isEmpty, let payload = carried {
                deliverHome(home: home, payload: payload,
                            framing: framing, method: method)
            }
        }
        func step() {
            guard generation == crawlGeneration, index < journey.count
            else {
                if generation == crawlGeneration { finishJourney() }
                return
            }
            let hop = journey[index]
            index += 1
            let hopNumber = index
            let text = hop.text
            let leg = hop.leg
            let hopStart = Date()
            if hop.blockStart { carried = nil }
            let payload: Data?
            if mode == "chain", !hop.blockStart, let soFar = carried {
                payload = soFar
            } else {
                payload = payloadFor(text)
            }
            guard let payload = payload else {
                trail("✗ hop \(hopNumber)/\(total) (\(leg)) \(text) — "
                      + "payload failed to build")
                DispatchQueue.main.async { step() }
                return
            }
            let report: (Bool) -> Void = { [weak self] ok in
                guard let self = self else { return }
                // This hop's reply, if it produced one: lastReply
                // is written only by send paths (noteReply), and
                // hops run strictly one at a time, so a timestamp
                // at or after this hop's start is its answer.
                var reply: Data?
                if let noted = self.lastReply, noted.at >= hopStart {
                    reply = noted.data
                }
                if let reply = reply { carried = reply }
                trail("\(ok ? "✓" : "✗") hop \(hopNumber)/\(total) "
                      + "(\(leg)) \(text) · \(payload.count) B out"
                      + (reply.map { " · \($0.count) B back" }
                         ?? " · no reply"))
                DispatchQueue.main.async { step() }
            }
            if text.hasPrefix("phone:") {
                sendToPhone(name: String(text.dropFirst(6)),
                            payload: payload, framing: framing,
                            read: true, timeout: 3, completion: report)
                return
            }
            guard let parsed = try? SendTarget.parse(text) else {
                trail("✗ hop \(hopNumber)/\(total) (\(leg)) \(text) — "
                      + "cannot parse target")
                DispatchQueue.main.async { step() }
                return
            }
            switch parsed {
            case .http:
                sendHTTP(target: parsed, payload: payload,
                         framing: framing, method: method, timeout: 5,
                         completion: report)
            case .tcp, .udp:
                sendNetwork(target: parsed, payload: payload,
                            framing: framing, read: true, timeout: 3,
                            completion: report)
            default:
                trail("✗ hop \(hopNumber)/\(total) (\(leg)) \(text) — "
                      + "not a network target")
                DispatchQueue.main.async { step() }
            }
        }
        step()
    }

    /// Stop a crawl between hops; the in-flight hop finishes on
    /// its own timeout. Whatever was carried so far stays visible
    /// in the trail.
    func stopCrawl() {
        crawlGeneration += 1
        if crawlBusy {
            crawlBusy = false
            crawlLines.append("Stopped — called home early")
            line("centipede: stopped by hand")
        }
    }

    /// One final send: the homecoming payload, delivered to a
    /// target the user named (their own server, another phone).
    private func deliverHome(home: String, payload: Data,
                             framing: String, method: String) {
        let note: (Bool) -> Void = { [weak self] ok in
            DispatchQueue.main.async {
                self?.crawlLines.append(
                    "\(ok ? "✓" : "✗") homecoming delivered to \(home)")
            }
        }
        if home.hasPrefix("phone:") {
            sendToPhone(name: String(home.dropFirst(6)),
                        payload: payload, framing: framing,
                        read: false, timeout: 3, completion: note)
            return
        }
        guard let parsed = try? SendTarget.parse(home) else {
            note(false)
            return
        }
        switch parsed {
        case .http:
            sendHTTP(target: parsed, payload: payload,
                     framing: framing, method: method, timeout: 5,
                     completion: note)
        case .tcp, .udp:
            sendNetwork(target: parsed, payload: payload,
                        framing: framing, read: false, timeout: 3,
                        completion: note)
        default:
            note(false)
        }
    }

    /// The /24 base ("192.168.2") a sweep target names: blank
    /// means the phone's own subnet; otherwise any address in
    /// the target /24 (192.168.2.15), its base (192.168.2.0), a
    /// bare base (192.168.2), or any of those with a /24 suffix.
    /// The sweep is always the /24 around the address. Nil when
    /// the text doesn't parse.
    static func sweepBase(_ target: String, ownIP: String?) -> String? {
        let text = target.trimmingCharacters(in: .whitespaces)
        let source = text.isEmpty ? (ownIP ?? "") : text
        let noPrefix = source.split(separator: "/").first
            .map(String.init) ?? source
        let parts = noPrefix.split(separator: ".")
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var octets: [Int] = []
        for part in parts {
            guard let value = Int(part), (0...255).contains(value)
            else { return nil }
            octets.append(value)
        }
        return octets.prefix(3).map(String.init).joined(separator: ".")
    }

    /// Knock one port across a /24 — the phone's own Wi-Fi
    /// subnet, or the subnet named by `target` — and hand back
    /// every host that answered, in numeric order: the Scan tab
    /// sweep's discipline (32 at a time, 1 s deadline), feeding
    /// the centipede's route. The phone's own address is skipped
    /// when it falls inside the swept range.
    /// Discovery: knock a handful of ports across a /24 — the
    /// phone's own subnet, or the one `target` names — and hand
    /// back every answering host with the ports it answered on,
    /// hosts in numeric order. One port's round at a time, 32
    /// knocks in flight, 1 s deadline per knock; the status line
    /// narrates each round. The phone's own address is skipped.
    func discoverSubnet(
        ports rawPorts: [Int], target: String,
        completion: @escaping ([(host: String, ports: [Int])]) -> Void
    ) {
        let ports = Array(Set(rawPorts.filter {
            (1...65535).contains($0)
        })).sorted()
        guard !crawlSweepBusy, !ports.isEmpty, ports.count <= 16 else {
            completion([])
            return
        }
        let own = Mouth.localIPAddress()
        guard let base = Mouth.sweepBase(target, ownIP: own) else {
            crawlSweepStatus =
                target.trimmingCharacters(in: .whitespaces).isEmpty
                ? "No Wi-Fi address to sweep from"
                : "Couldn't read that subnet — use the "
                  + "192.168.2.0/24 form"
            completion([])
            return
        }
        crawlSweepBusy = true
        crawlSweepStatus = "Discovering on \(base).0/24…"
        let lock = NSLock()
        var openByOctet: [Int: [Int]] = [:]
        func knockRound(port: Int, done: @escaping () -> Void) {
            let group = DispatchGroup()
            DispatchQueue.global().async { [weak self] in
                guard let self = self else { return }
                let gate = DispatchSemaphore(value: 32)
                for octet in 1...254 {
                    let host = "\(base).\(octet)"
                    if let own = own, host == own { continue }
                    gate.wait()
                    group.enter()
                    self.probe(host: host, port: port) { open in
                        if open {
                            lock.lock()
                            openByOctet[octet, default: []].append(port)
                            lock.unlock()
                        }
                        gate.signal()
                        group.leave()
                    }
                }
                group.notify(queue: .main) { done() }
            }
        }
        var round = 0
        func nextRound() {
            if round >= ports.count {
                crawlSweepBusy = false
                let found: [(host: String, ports: [Int])] =
                    openByOctet.keys.sorted().map { octet in
                        (host: "\(base).\(octet)",
                         ports: openByOctet[octet]?.sorted() ?? [])
                    }
                crawlSweepStatus = found.isEmpty
                    ? "Discovery done — nothing answered on "
                      + "\(base).0/24"
                    : "Discovery done — \(found.count) host(s) "
                      + "answered on \(base).0/24"
                completion(found)
                return
            }
            let port = ports[round]
            round += 1
            crawlSweepStatus = "Discovering \(base).0/24 — port "
                + "\(port) (\(round)/\(ports.count)), "
                + "\(openByOctet.count) host(s) so far"
            knockRound(port: port) { nextRound() }
        }
        nextRound()
    }

    /// One connect knock with a 1 s deadline; the completion
    /// fires exactly once with whether the port answered.
    private func probe(host: String, port: Int,
                       completion: @escaping (Bool) -> Void) {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port)) ?? .any,
            using: .tcp)
        let lock = NSLock()
        var done = false
        func finish(_ open: Bool) {
            lock.lock()
            if done { lock.unlock(); return }
            done = true
            lock.unlock()
            conn.cancel()
            completion(open)
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(true)
            case .failed, .cancelled: finish(false)
            default: break
            }
        }
        conn.start(queue: probeQueue)
        probeQueue.asyncAfter(deadline: .now() + 1.0) { finish(false) }
    }

}
