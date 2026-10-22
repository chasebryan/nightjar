import Foundation
import Security

// MARK: - OnionStandard
//
// The Onion standard: what the wrap is, what it
// honestly isn't, and the LAYERS score that
// grades the device's posture — seven layers,
// one decimal inventory, a pure scorer the
// Gauntlet can pin.
//
// THE HONESTY SPINE. An app cannot reach into
// the system and torify other apps' traffic —
// iOS offers no such road, and this room never
// claims one. What the Onion does:
//
// 1. WRAPS THE HOUSE'S OWN EMISSIONS. Everything
//    that leaves through the shared bench core
//    (BlacksiteNet.streamConnect — the road the
//    bench's BSD helpers all ride) is carried
//    through a SOCKS5 endpoint — the operator's
//    Tor road, Orbot on this device — when the
//    wrap is engaged. FAIL-CLOSED: wrap on and
//    the road down, the connect refuses; nothing
//    is sent bare. Protocols the wrap can't
//    honestly carry yet are NAMED in the roads
//    table, not silently exempted.
// 2. AUDITS AND GRADES. A snapshot of what the
//    app can actually see — tunnels, resolvers,
//    standing emissions, listeners, broadcast
//    identity, outward metadata organs — scored
//    by a pure function. What it cannot see it
//    names as unverifiable.
// 3. COUPLES TO EMCON. Each EMCON condition
//    declares an Onion floor; switching the
//    condition reports whether the floor is met
//    and exactly what the gap is. The floor
//    never blocks and is never faked.
//
// THE SCORE — LAYERS, 0.0 to 7.0. The inventory
// and its maxima (they sum to exactly 7.0):
//
//   Tunnel     1.50 — an interface (VPN / utun)
//              carries the default route. A
//              tunnel present but not carrying
//              the default route earns 0.50.
//   Tor road   1.50 — the wrap is on, the SOCKS
//              endpoint answers, and a wrapped
//              probe succeeded. Road answers but
//              the wrap is off: 0.50. Wrap on,
//              road down: 0.25.
//   DNS        1.00 — resolution rides the
//              tunnel. One bare answerer on the
//              LAN earns 0.25; evidence names
//              the answerer the app can see.
//   Emissions  1.00 — fractional: each standing
//              emission (Bonjour listing, GATT
//              hosting, beacon) deducts its
//              share. The SAME organs EMCON's
//              audit reads — one source of
//              truth, a second lens.
//   Listeners  0.75 — standing doors. Stealth-
//              only or none: full. Each listed
//              listener deducts a quarter.
//   Identity   0.50 — the names announced on
//              the wire carry no personal name;
//              a personal name earns 0.
//   Metadata   0.75 — fractional: the outward
//              organs that phone home (relay
//              polling, a running assault, a war
//              drive) deduct their shares.
//
// BANDS: 0.0 PEELED · 0.1–1.9 THIN · 2.0–3.9
// SKINNED · 4.0–5.4 WRAPPED · 5.5–6.9 LAYERED ·
// 7.0 FULL ONION.
//
// The snapshot is a plain struct; the scorer is
// pure; the gatherers are the only live reads.
// The Gauntlet tests the scorer and the SOCKS
// wire bytes against synthetic snapshots and
// fixtures, so the number can never drift from
// the standard.

enum OnionStandard {

    // MARK: The inventory (maxima sum to 7.0)

    static let maxTunnel = 1.50
    static let maxTorRoad = 1.50
    static let maxDNS = 1.00
    static let maxEmissions = 1.00
    static let maxListeners = 0.75
    static let maxIdentity = 0.50
    static let maxMetadata = 0.75

    static var maximumTotal: Double {
        maxTunnel + maxTorRoad + maxDNS
            + maxEmissions + maxListeners
            + maxIdentity + maxMetadata
    }

    // MARK: The score

    static func band(for value: Double) -> String {
        if value <= 0 { return L("PEELED") }
        if value < 2.0 { return L("THIN") }
        if value < 4.0 { return L("SKINNED") }
        if value < 5.5 { return L("WRAPPED") }
        if value < 7.0 { return L("LAYERED") }
        return L("FULL ONION")
    }

    /// One decimal place for whole and
    /// half values, two where the cents
    /// matter (3.5, not 3.50; 4.45 stays 4.45).
    static func fmt(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    /// Score a snapshot. Pure: same snapshot,
    /// same rows, every time. Each row's earned
    /// value is rounded to cents, and the total
    /// to cents, so the arithmetic the Gauntlet
    /// pins is exact.
    static func score(_ s: OnionSnapshot)
        -> OnionScore {
        var rows: [OnionRow] = []

        // Tunnel.
        if let name = s.tunnelDefaultName {
            rows.append(OnionRow(
                key: "tunnel", label: L("Tunnel"),
                earned: maxTunnel, maximum: maxTunnel,
                state: L("carries the default route"),
                evidence: String(format: L(
                    "the default route rides %@"),
                    name)))
        } else if let name = s.tunnelOtherName {
            rows.append(OnionRow(
                key: "tunnel", label: L("Tunnel"),
                earned: 0.50, maximum: maxTunnel,
                state: L("present, not the road"),
                evidence: String(format: L(
                    "%@ is addressed, but the "
                    + "default route does not "
                    + "ride it"), name)))
        } else {
            rows.append(OnionRow(
                key: "tunnel", label: L("Tunnel"),
                earned: 0, maximum: maxTunnel,
                state: L("no tunnel"),
                evidence: L("no utun interface "
                    + "carries an address on this "
                    + "device right now")))
        }

        // Tor road — from the wrap state and
        // the last probe record. No probe, no
        // claim: the road is unproven, never
        // assumed.
        let probe = s.probe
        let roadAnswers = probe?.socksAnswered
            == true
        let wrappedOK = probe?.wrappedOK == true
        if s.wrapOn && roadAnswers && wrappedOK {
            rows.append(OnionRow(
                key: "tor", label: L("Tor road"),
                earned: maxTorRoad,
                maximum: maxTorRoad,
                state: L("wrap on, road proven"),
                evidence: torEvidence(s)))
        } else if !s.wrapOn && roadAnswers {
            rows.append(OnionRow(
                key: "tor", label: L("Tor road"),
                earned: 0.50, maximum: maxTorRoad,
                state: L("road answers, wrap off"),
                evidence: torEvidence(s)))
        } else if s.wrapOn {
            rows.append(OnionRow(
                key: "tor", label: L("Tor road"),
                earned: 0.25, maximum: maxTorRoad,
                state: L("wrap on, road unproven"),
                evidence: torEvidence(s)))
        } else {
            rows.append(OnionRow(
                key: "tor", label: L("Tor road"),
                earned: 0, maximum: maxTorRoad,
                state: L("no road"),
                evidence: torEvidence(s)))
        }

        // DNS — the app cannot read the system's
        // resolver list (no such API reaches an
        // app), so the row grades what it can
        // see: whether resolution rides a
        // tunnel, or the LAN's answerer — the
        // gateway, the same witness dnsaudit
        // reads. Evidence says so, out loud.
        if s.tunnelDefaultName != nil {
            rows.append(OnionRow(
                key: "dns", label: L("DNS posture"),
                earned: maxDNS, maximum: maxDNS,
                state: L("rides the tunnel"),
                evidence: L("the default route "
                    + "rides a tunnel, so lookups "
                    + "leave through it too")))
        } else if let gw = s.gatewayIP {
            rows.append(OnionRow(
                key: "dns", label: L("DNS posture"),
                earned: 0.25, maximum: maxDNS,
                state: L("the LAN's answerer, "
                    + "in the clear"),
                evidence: String(format: L(
                    "no tunnel carries the "
                    + "route; the answerer this "
                    + "app can see is the "
                    + "gateway, %@"), gw)))
        } else {
            rows.append(OnionRow(
                key: "dns", label: L("DNS posture"),
                earned: 0, maximum: maxDNS,
                state: L("no resolver visible"),
                evidence: L("no gateway is "
                    + "visible from inside the "
                    + "app right now")))
        }

        // Emissions — the SAME standing organs
        // EMCON's audit reads, through its
        // snapshot. Fractions of the layer:
        // a listed serve is the loudest voice
        // in the house, then the GATT stage,
        // then the beacon.
        let o = s.organs
        var emitCut = 0.0
        var emitNames: [String] = []
        if o.serveRunning && !o.stealth {
            emitCut += 0.40
            emitNames.append(L("Bonjour listing"))
        }
        if o.gattHostOn {
            emitCut += 0.30
            emitNames.append(L("GATT hosting"))
        }
        if o.beaconOn || o.flareOn {
            emitCut += 0.30
            emitNames.append(L("the beacon"))
        }
        let emitEarned = cents(max(
            0, maxEmissions - emitCut))
        rows.append(OnionRow(
            key: "emissions", label: L("Emissions"),
            earned: emitEarned, maximum: maxEmissions,
            state: emitNames.isEmpty
                ? L("silent")
                : L("standing emissions"),
            evidence: emitNames.isEmpty
                ? L("no standing emission is up — "
                    + "the same organs EMCON "
                    + "grades read silent")
                : String(format: L(
                    "standing and deductible: %@"),
                    emitNames.joined(
                        separator: ", "))))

        // Listeners — standing doors. Stealth
        // (reachable, unlisted) or none earns
        // the whole layer; every LISTED
        // listener deducts a quarter.
        if !o.serveRunning {
            rows.append(OnionRow(
                key: "listeners",
                label: L("Listeners"),
                earned: maxListeners,
                maximum: maxListeners,
                state: L("none standing"),
                evidence: L("serve is down — no "
                    + "door stands open")))
        } else if o.stealth {
            rows.append(OnionRow(
                key: "listeners",
                label: L("Listeners"),
                earned: maxListeners,
                maximum: maxListeners,
                state: L("stealth only"),
                evidence: L("serve stands, but "
                    + "unlisted — reachable by "
                    + "address, announced "
                    + "nowhere")))
        } else {
            let cut = 0.25 * Double(min(
                3, max(1, o.serveListeners)))
            let earned = cents(max(
                0, maxListeners - cut))
            rows.append(OnionRow(
                key: "listeners",
                label: L("Listeners"),
                earned: earned,
                maximum: maxListeners,
                state: L("listed listeners"),
                evidence: String(format: L(
                    "%lld listener(s) stand "
                    + "listed on the wire"),
                    Int64(o.serveListeners))))
        }

        // Identity — the names the wire hears.
        // The test is EMCON's own: a personal
        // name hides in "X's iPhone".
        let personal = o.deviceName.contains("'s ")
            || o.deviceName.contains("’s ")
        if personal {
            rows.append(OnionRow(
                key: "identity", label: L("Identity"),
                earned: 0, maximum: maxIdentity,
                state: L("a personal name rides "
                    + "the wire"),
                evidence: String(format: L(
                    "the announced device name, "
                    + "%@, carries a personal "
                    + "name"), o.deviceName)))
        } else {
            rows.append(OnionRow(
                key: "identity", label: L("Identity"),
                earned: maxIdentity,
                maximum: maxIdentity,
                state: L("no personal name"),
                evidence: String(format: L(
                    "the announced names (%@ / "
                    + "%@) carry no personal "
                    + "name"), o.deviceName,
                    o.hostName)))
        }

        // Metadata — the outward organs whose
        // destinations learn the house's shape:
        // relay polling, a running assault, a
        // war drive in motion.
        var metaCut = 0.0
        var metaNames: [String] = []
        if o.relayPolling {
            metaCut += 0.25
            metaNames.append(L("relay polling"))
        }
        if o.assaultOn {
            metaCut += 0.25
            metaNames.append(L("net-assault"))
        }
        if o.warKnocking || o.warTracing {
            metaCut += 0.25
            metaNames.append(L("a war drive"))
        }
        let metaEarned = cents(max(
            0, maxMetadata - metaCut))
        rows.append(OnionRow(
            key: "metadata", label: L("Metadata"),
            earned: metaEarned,
            maximum: maxMetadata,
            state: metaNames.isEmpty
                ? L("nothing phones home")
                : L("outward organs up"),
            evidence: metaNames.isEmpty
                ? L("no relay polling, no "
                    + "assault, no war drive — "
                    + "nothing is telling an "
                    + "outsider the house's shape")
                : String(format: L(
                    "up and outward: %@"),
                    metaNames.joined(
                        separator: ", "))))

        let total = cents(rows.reduce(0) {
            $0 + $1.earned
        })
        return OnionScore(value: total, rows: rows)
    }

    private static func cents(_ v: Double)
        -> Double {
        (v * 100).rounded() / 100
    }

    private static func torEvidence(
        _ s: OnionSnapshot) -> String {
        guard let p = s.probe else {
            return s.wrapOn
                ? L("the wrap is engaged, but no "
                    + "probe has proven the road "
                    + "— run a Tor check")
                : L("no probe has been run — "
                    + "the road is a claim until "
                    + "one knocks")
        }
        let age = probeAgeText(p.when)
        if p.socksAnswered && p.wrappedOK {
            var text = String(format: L(
                "the endpoint at %@ answered "
                + "and a wrapped fetch came "
                + "back (%@)"), p.endpoint, age)
            if let ip = p.exitIP, !ip.isEmpty {
                text += String(format: L(
                    " — the check service says "
                    + "the exit was %@"), ip)
            }
            return text
        }
        if p.socksAnswered {
            return String(format: L(
                "the endpoint at %@ answered, "
                + "but the wrapped fetch failed "
                + "(%@): %@"), p.endpoint, age,
                p.problem)
        }
        return String(format: L(
            "no SOCKS road answered (%@): %@"),
            age, p.problem)
    }

    static func probeAgeText(_ when: Date)
        -> String {
        let seconds = max(0, Int(Date()
            .timeIntervalSince(when)))
        if seconds < 90 {
            return L("just now")
        }
        if seconds < 3600 {
            return String(format: L(
                "%lld min ago"), Int64(seconds / 60))
        }
        return String(format: L(
            "%lld h ago"), Int64(seconds / 3600))
    }

    // MARK: The EMCON coupling — floors

    /// The floor verdict for a condition:
    /// met, or short by how much and what the
    /// gap is made of. Reported, never
    /// enforced — EMCON stays the operator's
    /// instrument; the Onion only grades.
    static func floorGap(_ score: OnionScore,
                         _ condition: EmconCondition)
        -> Double {
        max(0, condition.onionFloor - score.value)
    }

    static func floorLine(_ score: OnionScore,
                          _ condition: EmconCondition)
        -> String {
        let floor = condition.onionFloor
        let gap = floorGap(score, condition)
        if gap <= 0 {
            return String(format: L(
                "onion floor met — %@ of 7.0 "
                + "layers over a %@ floor"),
                fmt(score.value), fmt(floor))
        }
        let short = score.rows
            .filter { $0.earned < $0.maximum }
            .sorted {
                ($0.maximum - $0.earned)
                    > ($1.maximum - $1.earned)
            }
            .prefix(3)
            .map { "\($0.label) (\($0.state))" }
            .joined(separator: ", ")
        return String(format: L(
            "onion floor short by %@ — the "
            + "gap: %@"), fmt(gap), short)
    }

    // MARK: The wrap state

    static var wrapEngaged: Bool {
        UserDefaults.standard.bool(
            forKey: "onion.wrap")
    }

    static func setWrap(_ on: Bool) {
        UserDefaults.standard.set(
            on, forKey: "onion.wrap")
        Journal.log("onion", "wrap", on
            ? "the wrap is engaged — the bench "
              + "core rides the tor road, "
              + "fail-closed"
            : "the wrap is off — the bench "
              + "core runs bare")
    }

    static var socksHost: String {
        let saved = UserDefaults.standard
            .string(forKey: "onion.socksHost")
        if let saved, !saved.isEmpty {
            return saved
        }
        return "127.0.0.1"
    }

    static var socksPort: Int {
        let saved = UserDefaults.standard
            .integer(forKey: "onion.socksPort")
        return saved > 0 ? saved : 9050
    }

    static var endpointLabel: String {
        "\(socksHost):\(socksPort)"
    }

    static func setEndpoint(host: String,
                            port: Int) {
        let clean = host.trimmingCharacters(
            in: .whitespacesAndNewlines)
        UserDefaults.standard.set(
            clean.isEmpty ? "127.0.0.1" : clean,
            forKey: "onion.socksHost")
        UserDefaults.standard.set(
            min(65535, max(1, port)),
            forKey: "onion.socksPort")
    }

    /// The last fail-closed refusal, kept so
    /// the room (and her voice) can say exactly
    /// why a road went nowhere.
    static var lastWrapRefusal: String?

    static func noteWrapRefusal(_ problem: String) {
        let text = L("the wrap is on and the "
            + "tor road is down — nothing "
            + "sent bare")
            + " (\(problem))"
        lastWrapRefusal = text
        Journal.log("onion", "refusal", text)
    }

    /// Posture reset — the room's clear
    /// control: wrap off, endpoint back to
    /// the default road, probe record let go.
    static func resetPosture() {
        setWrap(false)
        UserDefaults.standard.removeObject(
            forKey: "onion.socksHost")
        UserDefaults.standard.removeObject(
            forKey: "onion.socksPort")
        UserDefaults.standard.removeObject(
            forKey: "onion.lastProbe")
        lastWrapRefusal = nil
        Journal.log("onion", "posture",
                    "the posture was reset — "
                    + "wrap off, the default "
                    + "road, no probe kept")
    }

    // MARK: The snapshot + gatherers

    /// The live read: tunnels and the route
    /// from the interface table, the gateway
    /// from the route walk (the same witness
    /// dnsaudit uses), the organs from EMCON's
    /// own snapshot — one source of truth —
    /// and the wrap + probe record from the
    /// Onion's kept state.
    static func snapshot(emcon: Emcon,
                         mouth: Mouth)
        -> OnionSnapshot {
        var snap = OnionSnapshot()
        let names = BlacksiteNet.interfaces()
            .map { $0.name }
        let routeIface = BlacksiteNet
            .defaultRouteInterfaceName()
        let utuns = names.filter {
            $0.hasPrefix("utun")
        }
        if let routeIface,
           routeIface.hasPrefix("utun") {
            snap.tunnelDefaultName = routeIface
        }
        snap.tunnelOtherName = utuns.first {
            $0 != routeIface
        } ?? utuns.first
        snap.gatewayIP = BlacksiteNet
            .defaultGatewayIP()
        snap.organs = emcon.snapshot(mouth: mouth)
        snap.wrapOn = wrapEngaged
        snap.socksEndpoint = endpointLabel
        snap.probe = lastProbe
        return snap
    }

    static func audit(emcon: Emcon, mouth: Mouth)
        -> OnionScore {
        score(snapshot(emcon: emcon, mouth: mouth))
    }

    // MARK: The probe record

    static var lastProbe: OnionProbeRecord? {
        guard let data = UserDefaults.standard
            .data(forKey: "onion.lastProbe"),
              let record = try? JSONDecoder()
                .decode(OnionProbeRecord.self,
                        from: data) else {
            return nil
        }
        return record
    }

    static func keepProbe(_ record: OnionProbeRecord) {
        if let data = try? JSONEncoder()
            .encode(record) {
            UserDefaults.standard.set(
                data, forKey: "onion.lastProbe")
        }
        Journal.log("onion", "probe",
                    record.socksAnswered
                        ? "the tor road answered "
                          + "at \(record.endpoint)"
                          + (record.wrappedOK
                             ? " and a wrapped "
                               + "fetch came back"
                             : " but the wrapped "
                               + "fetch failed")
                        : "no socks road answered: "
                          + record.problem)
    }

    // MARK: The Tor check (operator-fired)
    //
    // ONE knock, never automatic: reach for the
    // SOCKS road — 9050, then 9150, then the
    // configured endpoint — CONNECT to the Tor
    // Project's check service BY NAME through
    // it, speak TLS over the tunnelled fd, and
    // ask the one question the service exists
    // to answer. The answer is reported AS A
    // CLAIM: the service's word about the exit,
    // not this app's proof.

    static func probeTor(
        completion: @escaping (OnionProbeRecord)
            -> Void) {
        DispatchQueue.global(qos: .userInitiated)
            .async {
                let record = runProbe()
                keepProbe(record)
                DispatchQueue.main.async {
                    completion(record)
                }
            }
    }

    private static func runProbe()
        -> OnionProbeRecord {
        var candidates: [(String, Int)] = [
            ("127.0.0.1", 9050),
            ("127.0.0.1", 9150),
        ]
        let configured = (socksHost, socksPort)
        if !candidates.contains(where: {
            $0.0 == configured.0
                && $0.1 == configured.1
        }) {
            candidates.append(configured)
        }
        var lastProblem = L("no SOCKS road "
            + "answered")
        for (host, port) in candidates {
            let endpoint = "\(host):\(port)"
            let (fd, problem) = OnionSOCKS.connect(
                endpointHost: host,
                endpointPort: port,
                targetHost: "check.torproject.org",
                targetPort: 443, timeout: 4)
            guard let fd else {
                lastProblem = problem
                    ?? lastProblem
                continue
            }
            // The road answered. Speak TLS over
            // the tunnelled stream and ask.
            let answer = onionFetchCheck(fd: fd)
            close(fd)
            if let answer {
                return OnionProbeRecord(
                    when: Date(), endpoint: endpoint,
                    socksAnswered: true,
                    wrappedOK: true,
                    isTor: answer.isTor,
                    exitIP: answer.ip, problem: "")
            }
            return OnionProbeRecord(
                when: Date(), endpoint: endpoint,
                socksAnswered: true,
                wrappedOK: false, isTor: nil,
                exitIP: nil,
                problem: L("the SOCKS road "
                    + "answered, but the check "
                    + "service's answer never "
                    + "came back whole"))
        }
        return OnionProbeRecord(
            when: Date(),
            endpoint: endpointLabel,
            socksAnswered: false, wrappedOK: false,
            isTor: nil, exitIP: nil,
            problem: lastProblem)
    }

    /// TLS over an already-connected fd, then
    /// one HTTP question. The SecureTransport
    /// shape is the house's proven one (the
    /// lock bench's TLS knock): a context, IO
    /// funcs over the fd, the peer's papers
    /// VERIFIED before the question is asked —
    /// a claim is only as good as who made it.
    private static func onionFetchCheck(
        fd: Int32) -> (isTor: Bool, ip: String)? {
        guard let context = SSLCreateContext(
            nil, .clientSide, .streamType) else {
            return nil
        }
        let box = OnionTLSBox(fd: fd)
        SSLSetIOFuncs(context, onionTLSRead,
                      onionTLSWrite)
        SSLSetConnection(context,
            Unmanaged.passUnretained(box)
                .toOpaque())
        SSLSetPeerDomainName(
            context, "check.torproject.org",
            "check.torproject.org".count)
        SSLSetSessionOption(context,
            .breakOnServerAuth, true)
        var status = SSLHandshake(context)
        // -9841 is errSSLServerAuthCompleted:
        // the handshake paused so the peer's
        // papers can be judged (the locks bench
        // compares the same literal — the named
        // constants are not in scope here).
        if status == -9841 {
            var trust: SecTrust?
            SSLCopyPeerTrust(context, &trust)
            var trusted = false
            if let trust {
                var evalError: CFError?
                trusted = SecTrustEvaluateWithError(
                    trust, &evalError)
            }
            guard trusted else { return nil }
            status = SSLHandshake(context)
        }
        guard status == errSecSuccess else {
            return nil
        }
        let request = "GET /api/ip HTTP/1.0\r\n"
            + "Host: check.torproject.org\r\n"
            + "Accept: application/json\r\n"
            + "Connection: close\r\n\r\n"
        var requestBytes = [UInt8](request.utf8)
        var written = 0
        let writeStatus = SSLWrite(
            context, &requestBytes,
            requestBytes.count, &written)
        guard writeStatus == errSecSuccess,
              written == requestBytes.count else {
            return nil
        }
        var raw: [UInt8] = []
        var buffer = [UInt8](
            repeating: 0, count: 8192)
        while raw.count < 65536 {
            var read = 0
            let readStatus = SSLRead(
                context, &buffer, buffer.count,
                &read)
            if read > 0 {
                raw.append(contentsOf:
                    buffer[0..<read])
            }
            if readStatus != errSecSuccess {
                break
            }
        }
        SSLClose(context)
        guard let text = String(bytes: raw,
                                encoding: .utf8),
              let split = text.range(
                of: "\r\n\r\n") else {
            return nil
        }
        let body = String(text[split.upperBound...])
        guard let bodyData = body.data(
                using: .utf8),
              let object = try? JSONSerialization
                .jsonObject(with: bodyData),
              let dict = object
                as? [String: Any] else {
            return nil
        }
        let isTor = (dict["IsTor"] as? Bool)
            ?? false
        let ip = (dict["IP"] as? String) ?? ""
        return (isTor, ip)
    }

    // MARK: The roads table
    //
    // The honest map of what the wrap carries,
    // drawn in the room where the operator can
    // read it. Three honest states: wraps /
    // doesn't wrap yet / cannot wrap (v1).

    static let roads: [OnionRoadRow] = [
        OnionRoadRow(
            family: L("The bench's TCP core — "
                + "ICS, Shield, Doors, Names, "
                + "Sat, the core verbs"),
            state: L("wraps"),
            note: L("one road: BlacksiteNet"
                + ".streamConnect. The SOCKS "
                + "gate stands at its head, so "
                + "every helper that rides it "
                + "wraps.")),
        OnionRoadRow(
            family: L("The bench's UDP — DNS "
                + "lookups, Wire, ICS "
                + "datagrams"),
            state: L("cannot wrap"),
            note: L("SOCKS5 UDP associate is "
                + "out of v1's scope. These "
                + "still run bare, and the "
                + "room says so.")),
        OnionRoadRow(
            family: L("Door probes — the "
                + "port census, eazy's knocks, "
                + "megatron's doors"),
            state: L("doesn't wrap yet"),
            note: L("a probe through the wrap "
                + "would grade the exit's "
                + "road, not the door in front "
                + "of it.")),
        OnionRoadRow(
            family: L("Console streams — "
                + "nc, banner"),
            state: L("doesn't wrap yet"),
            note: L("their own connections, "
                + "not the shared core's — a "
                + "later wave carries them.")),
        OnionRoadRow(
            family: L("The web bench + "
                + "console curl (URLSession)"),
            state: L("doesn't wrap yet"),
            note: L("URLSession has no SOCKS "
                + "handle an app may turn.")),
        OnionRoadRow(
            family: L("SSH + Knocktalk"),
            state: L("doesn't wrap yet"),
            note: L("named, not exempted — "
                + "they run bare until a wave "
                + "wraps them.")),
        OnionRoadRow(
            family: L("Her fetches + the "
                + "update check (URLSession)"),
            state: L("doesn't wrap yet"),
            note: L("Skelli's wire reads ride "
                + "URLSession; the wrap does "
                + "not reach them yet.")),
        OnionRoadRow(
            family: L("The tab engines — "
                + "Recon, Scan, Net-Assault"),
            state: L("doesn't wrap yet"),
            note: L("each knocks with its own "
                + "hand; the roads table "
                + "keeps them honest until "
                + "they ride the core.")),
    ]
}

// MARK: - The snapshot + score types

/// Everything the scorer is allowed to see.
/// Plain data, all defaults — the Gauntlet
/// builds synthetic postures from it.
struct OnionSnapshot {
    var tunnelDefaultName: String? = nil
    var tunnelOtherName: String? = nil
    var gatewayIP: String? = nil
    var organs = EmconSnapshot()
    var wrapOn: Bool = false
    var socksEndpoint: String = "127.0.0.1:9050"
    var probe: OnionProbeRecord? = nil
}

struct OnionRow: Identifiable {
    let key: String
    let label: String
    let earned: Double
    let maximum: Double
    let state: String
    let evidence: String
    var id: String { key }
}

struct OnionScore {
    let value: Double
    let rows: [OnionRow]
    var band: String {
        OnionStandard.band(for: value)
    }
}

/// The kept word of the last Tor check: when,
/// at which endpoint, whether the road
/// answered, whether a wrapped fetch came
/// back, and — as a claim — what the check
/// service said about the exit.
struct OnionProbeRecord: Codable {
    var when: Date
    var endpoint: String
    var socksAnswered: Bool
    var wrappedOK: Bool
    var isTor: Bool?
    var exitIP: String?
    var problem: String
}

struct OnionRoadRow: Identifiable {
    let family: String
    let state: String
    let note: String
    var id: String { family }
}

// MARK: - The EMCON floor, declared per condition

extension EmconCondition {
    /// The Onion floor this condition asks of
    /// the house. Monotonic with the condition
    /// itself — the Gauntlet pins both.
    var onionFloor: Double {
        switch self {
        case .open: return 0.0
        case .charlie: return 2.0
        case .bravo: return 4.5
        case .alpha: return 7.0
        }
    }
}

// MARK: - OnionSOCKS
//
// A small SOCKS5 client (RFC 1928), no-auth
// in v1 — Tor's local road asks for none.
// CONNECT BY DOMAIN (atyp 0x03) whenever the
// caller hands over a name: the target is
// never resolved locally inside the wrap —
// a local lookup would leak the question and
// pin the answer to the LAN's word. IPv4
// literals ride atyp 0x01. REP codes are
// named in every refusal, never swallowed.

enum OnionSOCKS {

    static func greetingBytes() -> [UInt8] {
        [0x05, 0x01, 0x00]
    }

    static func isIPv4Literal(_ host: String)
        -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy {
                $0.isNumber
            } && (Int(part) ?? 999) <= 255
        }
    }

    static func requestBytes(host: String,
                             port: Int) -> [UInt8] {
        var bytes: [UInt8] = [0x05, 0x01, 0x00]
        if isIPv4Literal(host) {
            bytes.append(0x01)
            for part in host.split(separator: ".") {
                bytes.append(UInt8(Int(part) ?? 0))
            }
        } else {
            bytes.append(0x03)
            let name = [UInt8](host.utf8)
            bytes.append(UInt8(
                min(255, name.count)))
            bytes.append(contentsOf: name)
        }
        let clamped = UInt16(clamping: port)
        bytes.append(UInt8(clamped >> 8))
        bytes.append(UInt8(clamped & 0xFF))
        return bytes
    }

    /// The REP names, RFC 1928 §6 — refusals
    /// speak these, so a down road explains
    /// itself.
    static func repName(_ rep: Int) -> String {
        switch rep {
        case 0: return L("succeeded")
        case 1: return L("general failure")
        case 2: return L("connection not allowed")
        case 3: return L("network unreachable")
        case 4: return L("host unreachable")
        case 5: return L("connection refused")
        case 6: return L("TTL expired")
        case 7: return L("command not supported")
        case 8: return L("address type not "
            + "supported")
        default: return String(format: L(
            "unknown reply %lld"), Int64(rep))
        }
    }

    /// Parse a complete CONNECT reply. Returns
    /// the REP code, the bound address as the
    /// road reported it, and the reply's total
    /// length — nil on anything malformed.
    static func parseReply(_ bytes: [UInt8])
        -> (rep: Int, bound: String,
            totalLength: Int)? {
        guard bytes.count >= 4, bytes[0] == 0x05
        else { return nil }
        let rep = Int(bytes[1])
        switch bytes[3] {
        case 0x01:
            guard bytes.count >= 10 else {
                return nil
            }
            let bound = bytes[4..<8]
                .map { String($0) }
                .joined(separator: ".")
            return (rep, bound, 10)
        case 0x03:
            guard bytes.count >= 5 else {
                return nil
            }
            let length = Int(bytes[4])
            guard bytes.count >= 5 + length + 2
            else { return nil }
            let bound = String(
                bytes: bytes[5..<(5 + length)],
                encoding: .utf8) ?? ""
            return (rep, bound, 5 + length + 2)
        case 0x04:
            guard bytes.count >= 22 else {
                return nil
            }
            return (rep, "ipv6", 22)
        default:
            return nil
        }
    }

    /// Open a stream to `targetHost:targetPort`
    /// through the SOCKS endpoint. On success
    /// the returned fd IS the target stream,
    /// carrying the caller's recv timeout. On
    /// any failure: nil and a named problem —
    /// the caller (the wrap gate) decides what
    /// a refusal means; this client just tells
    /// the truth about the road.
    static func connect(
        endpointHost: String, endpointPort: Int,
        targetHost: String, targetPort: Int,
        timeout: Double)
        -> (fd: Int32?, problem: String?) {
        let endpointIP: String
        if isIPv4Literal(endpointHost) {
            endpointIP = endpointHost
        } else if let resolved = BlacksiteNet
            .resolve4(endpointHost) {
            endpointIP = resolved.ip
        } else {
            return (nil, L("the socks endpoint's "
                + "own name does not resolve"))
        }
        let fd = socket(AF_INET, SOCK_STREAM,
                        IPPROTO_TCP)
        guard fd >= 0 else {
            return (nil, L("no socket could be "
                + "opened"))
        }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: timeout > 0 ? timeout : 8)
        var addr = BlacksiteNet.sockaddrIn(
            ip: endpointIP,
            port: UInt16(clamping: endpointPort))
        let rc = withUnsafePointer(to: &addr) {
            pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self, capacity: 1) {
                    sa in
                    Darwin.connect(fd, sa, socklen_t(
                        MemoryLayout<sockaddr_in>
                            .size))
                }
        }
        guard rc == 0 else {
            let problem = String(format: L(
                "the socks road at %@ does not "
                + "answer"), "\(endpointHost):"
                + "\(endpointPort)")
            close(fd)
            return (nil, problem)
        }
        // Greeting: VER, one method, no-auth.
        guard sendAll(fd, greetingBytes()),
              let hello = readExact(fd, 2) else {
            close(fd)
            return (nil, L("the socks road "
                + "took the greeting and said "
                + "nothing"))
        }
        guard hello[0] == 0x05 else {
            close(fd)
            return (nil, L("the socks road "
                + "answered in the wrong "
                + "tongue"))
        }
        guard hello[1] == 0x00 else {
            close(fd)
            return (nil, L("the socks road "
                + "accepts no no-auth method "
                + "— v1 speaks no other"))
        }
        // CONNECT, by name whenever a name
        // was handed over.
        guard sendAll(fd, requestBytes(
                host: targetHost, port: targetPort)),
              let head = readExact(fd, 4),
              head[0] == 0x05 else {
            close(fd)
            return (nil, L("the socks road "
                + "dropped the connect"))
        }
        var rest = 0
        var domainLength = 0
        switch head[3] {
        case 0x01: rest = 6
        case 0x04: rest = 18
        case 0x03:
            guard let lenByte = readExact(fd, 1)
            else {
                close(fd)
                return (nil, L("the socks road "
                    + "dropped the reply"))
            }
            domainLength = Int(lenByte[0])
            rest = domainLength + 2
        default:
            close(fd)
            return (nil, L("the socks road "
                + "replied with an address "
                + "type this client cannot "
                + "read"))
        }
        var full = head
        if head[3] == 0x03 {
            full.append(UInt8(domainLength))
        }
        guard let tail = readExact(fd, rest) else {
            close(fd)
            return (nil, L("the socks road "
                + "dropped the reply"))
        }
        full.append(contentsOf: tail)
        guard let parsed = parseReply(full) else {
            close(fd)
            return (nil, L("the socks reply "
                + "did not parse"))
        }
        guard parsed.rep == 0 else {
            let problem = String(format: L(
                "the tor road refused the "
                + "connect: %@"),
                repName(parsed.rep))
            close(fd)
            return (nil, problem)
        }
        if timeout > 0 {
            BlacksiteNet.setRecvTimeout(
                fd, seconds: timeout)
        } else {
            // The caller asked for no standing
            // timeout (the satellite road's
            // shape) — clear the handshake's
            // so the wrapped stream behaves
            // like the bare one did.
            var tv = timeval(tv_sec: 0,
                             tv_usec: 0)
            setsockopt(fd, SOL_SOCKET,
                       SO_RCVTIMEO, &tv,
                       socklen_t(MemoryLayout
                        <timeval>.size))
        }
        return (fd, nil)
    }

    private static func sendAll(_ fd: Int32,
                                _ bytes: [UInt8])
        -> Bool {
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBufferPointer {
                buffer in
                send(fd, buffer.baseAddress!
                     + sent,
                     bytes.count - sent, 0)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    private static func readExact(_ fd: Int32,
                                  _ count: Int)
        -> [UInt8]? {
        var bytes: [UInt8] = []
        while bytes.count < count {
            var chunk = [UInt8](
                repeating: 0,
                count: count - bytes.count)
            let n = recv(fd, &chunk, chunk.count,
                         0)
            if n <= 0 { return nil }
            bytes.append(contentsOf:
                chunk[0..<n])
        }
        return bytes
    }
}

// MARK: - TLS over the tunnelled fd
//
// The box + C callbacks the probe's
// SecureTransport context reads and writes
// through. The shape is the lock bench's
// proven one, kept separate so the probe
// stands on its own.

private final class OnionTLSBox {
    let fd: Int32
    init(fd: Int32) { self.fd = fd }
}

private func onionTLSRead(
    _ connection: SSLConnectionRef,
    _ data: UnsafeMutableRawPointer,
    _ length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<OnionTLSBox>
        .fromOpaque(connection).takeUnretainedValue()
    let wanted = length.pointee
    let n = recv(box.fd, data, wanted, 0)
    if n > 0 {
        length.pointee = n
        return n == wanted
            ? errSecSuccess : errSSLWouldBlock
    }
    if n == 0 {
        length.pointee = 0
        return errSSLClosedGraceful
    }
    length.pointee = 0
    if errno == EAGAIN || errno == EWOULDBLOCK {
        return errSSLWouldBlock
    }
    return errSSLClosedAbort
}

private func onionTLSWrite(
    _ connection: SSLConnectionRef,
    _ data: UnsafeRawPointer,
    _ length: UnsafeMutablePointer<Int>)
    -> OSStatus {
    let box = Unmanaged<OnionTLSBox>
        .fromOpaque(connection).takeUnretainedValue()
    let n = send(box.fd, data, length.pointee, 0)
    if n > 0 {
        length.pointee = n
        return errSecSuccess
    }
    length.pointee = 0
    if errno == EAGAIN || errno == EWOULDBLOCK {
        return errSSLWouldBlock
    }
    return errSSLClosedAbort
}
