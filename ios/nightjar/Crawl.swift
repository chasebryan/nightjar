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
               smartSeed: Bool,
               probeFor: @escaping (String) -> (data: Data, name: String)?,
               payloadFor: @escaping (String) -> Data?,
               framing: String, method: String,
               rules: [TraceRule] = [],
               payloadNamed: ((String) -> Data?)? = nil) {
        guard !crawlBusy, !talkBusy else { return }
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
        crawlFindings = []
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
        func harvest(_ text: String, leg: String, reply: Data,
                     tags: [String] = [],
                     source: String = "centipede",
                     recordTarget: String? = nil) {
            let preview: String
            if let spoken = PayloadKit.printableText(reply),
               let first = spoken.split(separator: "\n").first {
                preview = String(first)
            } else {
                preview = "\(reply.count) bytes · " + reply.prefix(8)
                    .map { String(format: "%02x", $0) }
                    .joined(separator: " ")
            }
            let finding = "\(text) (\(leg)) — "
                + String(preview.prefix(70))
            DispatchQueue.main.async { [weak self] in
                self?.crawlFindings.append(finding)
            }
            // What a door said is worth keeping after the walk
            // moves on: file it in the shared logbook, under
            // the target that was actually aimed at (a
            // follow-up's display text names the rule, which
            // is not a parsable target).
            TraceBookStore.shared.record(
                targetText: recordTarget ?? text, reply: reply,
                source: source, extraTags: tags)
        }
        func finishJourney() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.crawlBusy = false
                self.crawlHomecoming = carried
                self.crawlLines.append(
                    "Home — carrying \(carried?.count ?? 0) byte(s)")
                if !self.crawlFindings.isEmpty {
                    self.crawlLines.append(
                        "Harvest — \(self.crawlFindings.count) "
                        + (self.crawlFindings.count == 1
                           ? "reply" : "replies") + " kept:")
                    self.crawlLines += self.crawlFindings
                        .map { "  \($0)" }
                }
                self.logRecon("centipede", "\(total) hops",
                              lines: self.crawlLines)
                self.toasts?.show(String(format: L("Centipede home — %lld bytes back"), carried?.count ?? 0))
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
            var probeName: String?
            if mode == "chain", !hop.blockStart, let soFar = carried {
                payload = soFar
            } else if smartSeed, let probe = probeFor(text) {
                // A fresh hop (every hop in seed mode, each
                // device's first door in chain mode) speaks the
                // probe that matches its port, when the library
                // has one — a real Redis PING beats a generic
                // hello nobody answers.
                payload = probe.data
                probeName = probe.name
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
                // This hop's reply, if it produced one — read
                // through the synchronous mirror (replyData):
                // the @Published lastReply publishes via the main
                // queue and can lag the very completion firing
                // here, which fast-closing servers (an HTTP/1.0
                // answer-and-close) reliably outrun.
                let reply = self.replyData(since: hopStart)
                // The adaptive rules judge the reply before
                // anything is done with it: tags are filed with
                // the finding, a stop means the reply is NOT
                // carried onward, and the first follow-up rule
                // earns one extra word with this door — sent
                // before the walk steps on, and harvested like
                // any other reply, but it never replaces what
                // the chain is carrying.
                var followName: String?
                var ruleNote = ""
                if let reply = reply {
                    var tags: [String] = []
                    var stopCarry = false
                    if !rules.isEmpty {
                        var targetPort = -1
                        if let parsed = try? SendTarget.parse(text) {
                            switch parsed {
                            case .tcp(_, let p, _),
                                 .udp(_, let p):
                                targetPort = p
                            case .http(let url, let https):
                                targetPort = url.port
                                    ?? (https ? 443 : 80)
                            default:
                                break
                            }
                        }
                        let replyText = TraceAnalyzer.text(of: reply)
                        for rule in rules
                        where rule.matches(text: replyText,
                                           port: targetPort) {
                            switch rule.action {
                            case .tag(let label):
                                if !tags.contains(label) {
                                    tags.append(label)
                                }
                            case .stop:
                                stopCarry = true
                            case .followup(let name):
                                if followName == nil {
                                    followName = name
                                }
                            }
                        }
                    }
                    carried = stopCarry ? nil : reply
                    harvest(text, leg: leg, reply: reply, tags: tags)
                    if !tags.isEmpty {
                        trail("  ↳ tagged: "
                              + tags.joined(separator: ", "))
                    }
                    if stopCarry {
                        ruleNote = " · rule: stop — reply left here"
                    }
                }
                let elapsed = Date().timeIntervalSince(hopStart)
                let trailLine = "\(ok ? "✓" : "✗") "
                    + "hop \(hopNumber)/\(total) "
                    + "(\(leg)) \(text) · \(payload.count) B out"
                    + (probeName.map { " · spoke \($0)" } ?? "")
                    + (reply.map { " · \($0.count) B back" }
                       ?? " · no reply")
                    + String(format: " · %.2fs", elapsed)
                    + ruleNote
                guard let name = followName,
                      let followPayload = payloadNamed?(name)
                else {
                    trail(trailLine)
                    DispatchQueue.main.async { step() }
                    return
                }
                let followStart = Date()
                self.talkSend(text: text, payload: followPayload) {
                    _ in
                    guard generation == self.crawlGeneration
                    else { return }
                    var note = " · follow-up: \(name)"
                    if let followReply = self.replyData(
                        since: followStart) {
                        harvest("\(text) (follow-up: \(name))",
                                leg: leg, reply: followReply,
                                source: "centipede-followup",
                                recordTarget: text)
                        note += " · \(followReply.count) B back"
                    } else {
                        note += " · silence"
                    }
                    trail(trailLine + note)
                    DispatchQueue.main.async { step() }
                }
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

// MARK: - Crosstalk

extension Mouth {

    /// Patch two doors together and let them talk. Door A is
    /// knocked with the opener (its port's probe when smart
    /// seed is on, else the step-2 payload); A's reply is
    /// carried verbatim to B, B's reply back to A, alternating
    /// until a side falls silent, echoes the words straight
    /// back, or repeats itself — or the rounds run out. The
    /// transcript lives in `talkLines` and history; the last
    /// word lands in `talkHomecoming`. Doors are anything the
    /// route parser accepts (TCP, UDP, TLS, HTTP(S), phones);
    /// a train, range, or bare host speaks through its first
    /// door. Every leg is sent by the phone, one at a time.
    func startTalk(a aText: String, b bText: String,
                   rounds: Int, seed: Data, smartSeed: Bool,
                   probeFor: @escaping (String)
                       -> (data: Data, name: String)?) {
        guard !talkBusy, !crawlBusy else { return }
        let doorA = Mouth.expandRoute([aText]).stops.first
        let doorB = Mouth.expandRoute([bText]).stops.first
        talkGeneration += 1
        let gen = talkGeneration
        talkLines = []
        talkHomecoming = nil
        guard let doorA = doorA, let doorB = doorB else {
            talkLines = ["✗ Both doors must be targets the route "
                         + "parser accepts — tcp://, udp://, "
                         + "http(s)://, phone:NAME, a train, "
                         + "a range."]
            return
        }
        talkBusy = true
        let opener: Data
        var openerNote = ""
        if smartSeed, let probe = probeFor(doorA) {
            opener = probe.data
            openerNote = " · spoke \(probe.name)"
        } else {
            opener = seed
        }
        talkLines.append("Crosstalk — \(doorA) ⇄ \(doorB), "
                         + "up to \(rounds) round(s)")
        line("crosstalk: \(doorA) ⇄ \(doorB)")

        var legsLeft = max(1, rounds) * 2
        var exchanges = 0
        var carriedBytes = 0
        var lastByDoor: [String: Data] = [:]

        func finish(_ why: String, lastWord: Data?) {
            guard talkGeneration == gen else { return }
            talkBusy = false
            talkHomecoming = lastWord
            talkLines.append(why)
            line("crosstalk: \(why)")
            logRecon("crosstalk", "\(doorA) ⇄ \(doorB)",
                     lines: talkLines)
        }

        func leg(to door: String, from other: String,
                 message: Data, note: String) {
            guard talkGeneration == gen else { return }
            guard legsLeft > 0 else {
                finish("Rounds done — \(exchanges) exchange(s), "
                       + "\(carriedBytes) byte(s) carried",
                       lastWord: message)
                return
            }
            legsLeft -= 1
            let started = Date()
            talkSend(text: door, payload: message) { ok in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.talkGeneration == gen else { return }
                    let reply = ok ? self.replyData(since: started)
                                   : nil
                    let secs = String(format: "%.2f",
                        Date().timeIntervalSince(started))
                    guard let reply = reply, !reply.isEmpty else {
                        self.talkLines.append(
                            "→ \(door) · \(message.count) B out"
                            + "\(note) · silence · \(secs)s")
                        finish("\(door) had nothing to say — "
                               + "conversation over after "
                               + "\(exchanges) exchange(s)",
                               lastWord: nil)
                        return
                    }
                    exchanges += 1
                    carriedBytes += reply.count
                    self.talkLines.append(
                        "→ \(door) · \(message.count) B out\(note)"
                        + " · \(reply.count) B back · \(secs)s")
                    self.talkLines.append(
                        "   \(Mouth.talkSummary(reply))")
                    if reply == message {
                        finish("\(door) echoed the words straight "
                               + "back — loop; conversation over",
                               lastWord: reply)
                        return
                    }
                    if lastByDoor[door] == reply {
                        finish("\(door) repeated itself — loop; "
                               + "conversation over",
                               lastWord: reply)
                        return
                    }
                    lastByDoor[door] = reply
                    leg(to: other, from: door, message: reply,
                        note: "")
                }
            }
        }
        leg(to: doorA, from: doorB, message: opener,
            note: openerNote)
    }

    /// Stop a conversation between legs; the in-flight leg
    /// finishes on its own timeout.
    func stopTalk() {
        talkGeneration += 1
        if talkBusy {
            talkBusy = false
            talkLines.append("Stopped — hung up on them both")
            line("crosstalk: stopped by hand")
        }
    }

    /// One conversational leg: send `payload` to the door
    /// named by `text` and report whether it went out; the
    /// reply is read through the reply mirror, exactly as the
    /// crawl reads its hops.
    private func talkSend(text: String, payload: Data,
                          completion: @escaping (Bool) -> Void) {
        if text.hasPrefix("phone:") {
            sendToPhone(name: String(text.dropFirst(6)),
                        payload: payload, framing: "raw",
                        read: true, timeout: 3,
                        completion: completion)
            return
        }
        guard let parsed = try? SendTarget.parse(text) else {
            completion(false)
            return
        }
        switch parsed {
        case .http:
            sendHTTP(target: parsed, payload: payload,
                     framing: "raw", method: "POST", timeout: 5,
                     completion: completion)
        case .tcp, .udp:
            sendNetwork(target: parsed, payload: payload,
                        framing: "raw", read: true, timeout: 3,
                        completion: completion)
        default:
            completion(false)
        }
    }

    /// A short printable summary of a reply for the
    /// transcript: its first printable line, else a byte
    /// count and a hex head.
    static func talkSummary(_ data: Data) -> String {
        if let text = PayloadKit.printableText(data) {
            let first = text.components(separatedBy: "\n").first
                ?? text
            return String(first.prefix(70))
        }
        let hex = data.prefix(8)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
        return "\(data.count) B · \(hex)"
    }
}
