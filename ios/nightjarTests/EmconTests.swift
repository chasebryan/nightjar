import XCTest
@testable import nightjar

/// EMCON's pure half: the Standard's decimal score and its
/// regulations, probe fingerprints, home-subnet comparison,
/// one-knock tripwire accounting, and the drill's names.
/// Nothing here needs a radio or a socket.
final class EmconTests: XCTestCase {

    private func score(
        _ mutate: (inout EmconSnapshot) -> Void = { _ in }
    ) -> Emcon.Score {
        var snapshot = EmconSnapshot()
        mutate(&snapshot)
        return EmconStandard.score(snapshot)
    }

    // MARK: - the Standard's score

    func testGhostWhenNothingIsEmitting() {
        let ghost = score()
        XCTAssertEqual(ghost.value, 0.0, accuracy: 0.001)
        XCTAssertEqual(ghost.band, "GHOST")
        XCTAssertTrue(ghost.parts.isEmpty)
        XCTAssertFalse(ghost.capped)
    }

    // MARK: - the standing board

    func testBoardStatesTheHouseAtCharlie() {
        var s = EmconSnapshot()
        s.serveRunning = true
        s.stealth = true
        s.gattHostOn = true
        let rows = EmconStandard.board(s,
                                       condition: .charlie)
        XCTAssertEqual(rows.count, 10)
        let serve = rows.first { $0.label == "Serve" }
        XCTAssertEqual(serve?.standing, true)
        XCTAssertEqual(serve?.ruling, "Permitted")
        XCTAssertEqual(serve?.weight ?? -1, 4.0,
                       accuracy: 0.001)
        let gatt = rows.first { $0.label == "GATT host" }
        XCTAssertEqual(gatt?.ruling, "Forbidden")
        XCTAssertEqual(gatt?.violation, true)
        let dark = rows.first { $0.label == "Persona" }
        XCTAssertEqual(dark?.standing, false)
        XCTAssertEqual(dark?.violation, false)
    }

    func testBoardServeRulingsFollowTheCondition() {
        let dark = EmconSnapshot()
        let charlie = EmconStandard.board(
            dark, condition: .charlie)
        XCTAssertEqual(charlie.first {
            $0.label == "Serve" }?.ruling, "Stealth only")
        let bravo = EmconStandard.board(
            dark, condition: .bravo)
        XCTAssertEqual(bravo.first {
            $0.label == "Serve" }?.ruling, "Forbidden")
        let open = EmconStandard.board(
            dark, condition: .open)
        XCTAssertTrue(open.allSatisfy {
            $0.ruling == "Permitted" })
    }

    func testRefusedLabelsNameTheChange() {
        let charlie = EmconStandard.refusedLabels(
            for: .charlie)
        XCTAssertTrue(charlie.contains("a listed Serve"))
        XCTAssertFalse(charlie.contains("the relay poll"))
        XCTAssertFalse(charlie.contains("an active sweep"))
        let bravo = EmconStandard.refusedLabels(
            for: .bravo)
        XCTAssertTrue(bravo.contains("Serve"))
        XCTAssertTrue(bravo.contains("the relay poll"))
        XCTAssertTrue(EmconStandard.refusedLabels(
            for: .alpha).contains("an active sweep"))
        XCTAssertTrue(EmconStandard.refusedLabels(
            for: .open).isEmpty)
    }

    func testInventorySumsToExactlyOneHundred() {
        // The scale's construction contract: a fully lit
        // house is 100.0, not a cap's artifact.
        XCTAssertEqual(EmconStandard.maximumTotal, 100.0,
                       accuracy: 0.001)
        let lit = score {
            $0.onLan = true
            $0.deviceName = "Chase's iPhone"
            $0.serveRunning = true
            $0.serveListeners = 4
            $0.gattHostOn = true
            $0.beaconOn = true
            $0.personaOn = true
            $0.assaultOn = true
            $0.probingOn = true
            $0.warKnocking = true
            $0.bansheeOn = true
            $0.relayPolling = true
            $0.writeScanning = true
            $0.exposureCount = 10000
            $0.announcerCount = 10000
        }
        XCTAssertEqual(lit.value, 100.0, accuracy: 0.15)
        XCTAssertEqual(lit.band, "BEACONING")
        XCTAssertFalse(lit.capped)
    }

    func testDecimalWeights() {
        let stealth = score {
            $0.serveRunning = true
            $0.stealth = true
        }
        XCTAssertEqual(stealth.value, 4.0, accuracy: 0.001)
        XCTAssertEqual(stealth.band, "DARK")
        XCTAssertEqual(stealth.parts.map(\.label),
                       ["Serve, stealth"])

        let stealthThree = score {
            $0.serveRunning = true
            $0.stealth = true
            $0.serveListeners = 3
        }
        XCTAssertEqual(stealthThree.value, 5.0,
                       accuracy: 0.001)

        let listed = score { $0.serveRunning = true }
        XCTAssertEqual(listed.value, 12.0, accuracy: 0.001)
        XCTAssertEqual(listed.band, "LIT")

        let personal = score { $0.deviceName = "Chase's iPhone" }
        XCTAssertEqual(personal.parts.map(\.points), [8.0])
        let curly = "Chase\u{2019}s iPhone"
        XCTAssertEqual(score { $0.deviceName = curly }.value,
                       8.0, accuracy: 0.001)

        let hosted = score { $0.hostName = "chasembp" }
        XCTAssertEqual(hosted.value, 5.0, accuracy: 0.001)
        let named = score { $0.deviceName = "Nightjar" }
        XCTAssertEqual(named.value, 3.0, accuracy: 0.001)
        // "iPhone" is the generic zero. Anything else is a name.
        XCTAssertEqual(score { $0.deviceName = "iPhone 15" }
                        .value, 3.0, accuracy: 0.001)
    }

    func testEvidenceSaturatesByItsFormula() {
        let one = score { $0.exposureCount = 1 }
        let six = score { $0.exposureCount = 6 }
        let many = score { $0.exposureCount = 600 }
        XCTAssertLessThan(one.value, six.value)
        XCTAssertLessThan(six.value, many.value)
        XCTAssertLessThanOrEqual(many.value,
                                 EmconStandard.wReconMax)
        // 9 x (1 - e^-1) = 5.69 -> 5.7 at the Standard's tenth.
        XCTAssertEqual(six.value, 5.7, accuracy: 0.001)
        let ads = score { $0.announcerCount = 4 }
        // 6 x (1 - e^-1) = 3.79 -> 3.8.
        XCTAssertEqual(ads.value, 3.8, accuracy: 0.001)
    }

    func testBreakdownMatchesTheInventory() {
        let full = score {
            $0.gattHostOn = true
            $0.beaconOn = true
            $0.serveRunning = true
            $0.deviceName = "Chase's iPhone"
            $0.exposureCount = 2
            $0.announcerCount = 1
        }
        XCTAssertEqual(full.parts.map(\.label), [
            "GATT host", "BLE beacon", "Serve, listed",
            "Personal name", "Recon hits ×2", "Bonjour ×1",
        ])
        XCTAssertEqual(full.parts.map(\.points),
                       [13.0, 9.0, 12.0, 8.0, 2.6, 1.3])
        XCTAssertEqual(full.value, 45.9, accuracy: 0.001)
        XCTAssertEqual(full.band, "LOUD")
    }

    // MARK: - the regulations

    func testConditionPermits() {
        XCTAssertTrue(EmconCondition.open.permits(.gattHost))
        XCTAssertTrue(EmconCondition.charlie
                        .permits(.serveStealth))
        XCTAssertFalse(EmconCondition.charlie
                        .permits(.serveListed))
        XCTAssertFalse(EmconCondition.charlie
                        .permits(.netAssault))
        XCTAssertTrue(EmconCondition.charlie
                        .permits(.relayPoll))
        XCTAssertFalse(EmconCondition.bravo
                        .permits(.serveStealth))
        XCTAssertFalse(EmconCondition.bravo
                        .permits(.relayPoll))
        XCTAssertTrue(EmconCondition.bravo.permits(.sweep))
        XCTAssertFalse(EmconCondition.alpha.permits(.sweep))
        XCTAssertFalse(EmconCondition.alpha
                        .permits(.updateCheck))
    }

    func testConditionOrderingAndMigration() {
        XCTAssertLessThan(EmconCondition.open,
                          EmconCondition.charlie)
        XCTAssertLessThan(EmconCondition.bravo,
                          EmconCondition.alpha)
        // The legacy binary flag migrates to CHARLIE.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "emcon.condition")
        defaults.set(true, forKey: "emconActive")
        XCTAssertEqual(EmconCondition.current, .charlie)
        EmconCondition.store(.alpha)
        XCTAssertEqual(EmconCondition.current, .alpha)
        EmconCondition.store(.open)
        XCTAssertEqual(EmconCondition.current, .open)
        XCTAssertFalse(defaults.bool(forKey: "emconActive"))
    }

    // MARK: - fingerprints

    func testFingerprintClassifiesKnownProbes() throws {
        let redis = try ReconPayloads.build("redis-ping")
        XCTAssertEqual(Emcon.fingerprint(redis, port: 6379, udp: false),
                       "nightjar-hack probe: redis-ping")
        XCTAssertEqual(Emcon.fingerprint(redis, port: 80, udp: false),
                       "nightjar-hack probe: redis-ping (on the wrong port)")
        XCTAssertEqual(Emcon.fingerprint(redis, port: 6379, udp: true),
                       "nightjar-hack probe: redis-ping (a TCP probe over UDP)")

        // Several probes are the same GET /. The port breaks the tie.
        let http = try ReconPayloads.build("http-get")
        XCTAssertEqual(Emcon.fingerprint(http, port: 80, udp: false),
                       "nightjar-hack probe: http-get")
        XCTAssertEqual(Emcon.fingerprint(http, port: 9200, udp: false),
                       "nightjar-hack probe: elasticsearch-root")
        XCTAssertEqual(Emcon.fingerprint(http, port: 443, udp: false),
                       "nightjar-hack probe: https-get")
        let dns = try ReconPayloads.build("dns-a")
        XCTAssertEqual(Emcon.fingerprint(dns, port: 53, udp: true),
                       "nightjar-hack probe: dns-a")

        // A partial send still names the probe. The trailing byte is
        // what a short read would drop; "PING" is already in hand.
        let partial = Data(redis.prefix(redis.count - 1))
        XCTAssertEqual(Emcon.fingerprint(partial, port: 6379, udp: false),
                       "nightjar-hack probe: redis-ping")
    }

    func testFingerprintClassifiesGenericScanners() {
        let hello = Data([0x16, 0x03, 0x01, 0x00, 0x2a, 0x01, 0x00])
        XCTAssertEqual(
            Emcon.fingerprint(hello, port: 443, udp: false),
            "TLS ClientHello — a TLS scanner or client knocked")

        let ssh = Data("SSH-2.0-OpenSSH_9.9\r\n".utf8)
        XCTAssertTrue(Emcon.fingerprint(ssh, port: 22, udp: false)
            .hasPrefix("SSH client banner:"))

        let post = Data("POST /nightjar-emcon HTTP/1.1\r\nHost: x\r\n\r\n".utf8)
        XCTAssertTrue(Emcon.fingerprint(post, port: 8080, udp: false)
            .hasPrefix("HTTP request:"))

        XCTAssertEqual(Emcon.fingerprint(Data(), port: 80, udp: false),
                       "empty connection")
        let junk = Data("not-a-probe".utf8)
        XCTAssertEqual(Emcon.fingerprint(junk, port: 1, udp: false),
                       "unrecognized probe: not-a-probe")
    }

    func testTripVerdictTreatsEmptyAsOneSilentKnock() throws {
        XCTAssertEqual(Emcon.tripVerdict(Data(), port: 22, udp: false),
                       "silent knock (no bytes sent)")
        let redis = try ReconPayloads.build("redis-ping")
        XCTAssertEqual(Emcon.tripVerdict(redis, port: 6379, udp: false),
                       "nightjar-hack probe: redis-ping")
    }

    /// The receive path and the grace timer share one gate. Whichever
    /// presents first is the row; the other is dropped. handleTrip
    /// feeds bytes into that first claim and only falls back to empty.
    func testNoteKnockLogsOnce() throws {
        let redis = try ReconPayloads.build("redis-ping")
        let once = Emcon.TripOnce()
        let logged = Emcon.noteKnock(once, bytes: redis, port: 6379, udp: false)
        let dropped = Emcon.noteKnock(once, bytes: Data(), port: 6379, udp: false)
        XCTAssertEqual(logged?.verdict, Optional("nightjar-hack probe: redis-ping"))
        XCTAssertEqual(logged?.byteCount, Optional(redis.count))
        XCTAssertNil(dropped)
        XCTAssertTrue(once.isSettled)

        let silent = Emcon.TripOnce()
        let quiet = Emcon.noteKnock(silent, bytes: Data(), port: 22, udp: false)
        let late = Emcon.noteKnock(silent, bytes: redis, port: 22, udp: false)
        XCTAssertEqual(quiet?.verdict, Optional("silent knock (no bytes sent)"))
        XCTAssertEqual(quiet?.byteCount, Optional(0))
        XCTAssertNil(late)
    }

    // MARK: - tripwire log

    func testBurstsCollapseAndTheLogStaysCapped() {
        XCTAssertEqual(Emcon.burstWindow, 30)
        XCTAssertEqual(Emcon.eventCap, 200)
        var events: [Emcon.TripEvent] = []
        let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
        let verdict = "nightjar-hack probe: redis-ping"
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: verdict, byteCount: 14, now: t0)
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: verdict, byteCount: 14,
                     now: t0.addingTimeInterval(5))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].repeatCount, 2)
        XCTAssertEqual(events[0].when, t0.addingTimeInterval(5))

        // A different port, verdict, or protocol is a different knock.
        Emcon.record(&events, source: "10.1.1.8", port: 22, proto: "TCP",
                     verdict: "silent knock (no bytes sent)", byteCount: 0,
                     now: t0.addingTimeInterval(6))
        Emcon.record(&events, source: "10.9.9.9", port: 6379, proto: "TCP",
                     verdict: verdict, byteCount: 14,
                     now: t0.addingTimeInterval(6))
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "UDP",
                     verdict: verdict, byteCount: 14,
                     now: t0.addingTimeInterval(6))
        XCTAssertEqual(events.count, 4)

        // The window slides with the latest hit. 29s folds in; 30s does not.
        let slid = t0.addingTimeInterval(5)
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: verdict, byteCount: 14,
                     now: slid.addingTimeInterval(29))
        XCTAssertEqual(events[0].repeatCount, 3)
        XCTAssertEqual(events.count, 4)
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: verdict, byteCount: 14,
                     now: slid.addingTimeInterval(29 + 30))
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events[0].repeatCount, 1)

        var flood: [Emcon.TripEvent] = []
        for i in 0..<201 {
            Emcon.record(&flood, source: "10.0.0.1", port: i, proto: "TCP",
                         verdict: "knock \(i)", byteCount: 1,
                         now: Date(timeIntervalSinceReferenceDate: Double(i)))
        }
        XCTAssertEqual(flood.count, 200)
        XCTAssertEqual(flood[0].port, 200)
        XCTAssertFalse(flood.contains { $0.port == 0 })
    }

    func testTripwireReportAndOldLogs() throws {
        let when = Date(timeIntervalSinceReferenceDate: 50_000)
        var events: [Emcon.TripEvent] = []
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: "nightjar-hack probe: redis-ping",
                     byteCount: 14, now: when)
        Emcon.record(&events, source: "10.1.1.8", port: 6379, proto: "TCP",
                     verdict: "nightjar-hack probe: redis-ping",
                     byteCount: 14, now: when.addingTimeInterval(2))
        let report = Emcon.tripwireReport(events)
        XCTAssertTrue(report.contains("EMCON tripwire"))
        XCTAssertTrue(report.contains("The tripwire never replies."))
        XCTAssertTrue(report.contains("10.1.1.8 → TCP/6379 ×2"))
        XCTAssertTrue(report.contains("nightjar-hack probe: redis-ping"))
        XCTAssertEqual(Emcon.tripwireReport([]),
                       "EMCON tripwire\nThe tripwire never replies.\n\nNobody has knocked.")

        let old = Data(#"{"id":"k1","when":0,"source":"10.0.0.8","port":22,"proto":"TCP","verdict":"silent knock (no bytes sent)","byteCount":0}"#.utf8)
        let decoded = try JSONDecoder().decode(Emcon.TripEvent.self, from: old)
        XCTAssertEqual(decoded.id, "k1")
        XCTAssertEqual(decoded.repeatCount, 1)
        XCTAssertEqual(decoded.port, 22)

        let data = try JSONEncoder().encode(events[0])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"repeatCount\""))
        let round = try JSONDecoder().decode(Emcon.TripEvent.self, from: data)
        XCTAssertEqual(round, events[0])
    }

    // MARK: - home turf

    func testHomeSubnetComparison() {
        XCTAssertEqual(Emcon.subnet(of: "10.0.0.8"), "10.0.0")
        XCTAssertEqual(Emcon.subnet(of: "192.168.4.20"), "192.168.4")
        XCTAssertNil(Emcon.subnet(of: "10.0.0"))
        XCTAssertNil(Emcon.subnet(of: "fe80::1"))
        XCTAssertNil(Emcon.subnet(of: ""))

        XCTAssertFalse(Emcon.away(home: nil, here: "10.0.0"))
        XCTAssertFalse(Emcon.away(home: "10.0.0", here: nil))
        XCTAssertFalse(Emcon.away(home: nil, here: nil))
        XCTAssertFalse(Emcon.away(home: "10.0.0", here: "10.0.0"))
        XCTAssertTrue(Emcon.away(home: "10.0.0", here: "10.1.0"))
    }

    // MARK: - drill

    func testDrillNamesWhatWentQuietAndWhatStillShows() {
        let http = Emcon.Exposure(host: "10.0.0.5", port: 80,
                                  service: "http", banner: "HTTP/1.1",
                                  confirmed: true)
        let ssh = Emcon.Exposure(host: "127.0.0.1", port: 22,
                                 service: "ssh", banner: "", confirmed: false)
        let airplay = Emcon.Announcer(type: "_airplay._tcp", label: "AirPlay",
                                      name: "Chase's iPhone",
                                      why: "announced under this device's name")
        let airdrop = Emcon.Announcer(type: "_airdrop._tcp", label: "AirDrop",
                                      name: "Chase's iPhone",
                                      why: "announced under this device's name")
        let before = Emcon.Snapshot(exposures: [http, ssh],
                                    announcers: [airplay, airdrop])
        let after = Emcon.Snapshot(exposures: [ssh], announcers: [airplay])
        XCTAssertEqual(Emcon.silenced(before: before, after: after), [
            "10.0.0.5:80 http",
            "AirDrop: Chase's iPhone",
        ])
        XCTAssertEqual(Emcon.stillShowing(after), [
            "127.0.0.1:22 ssh",
            "AirPlay: Chase's iPhone",
        ])
        XCTAssertTrue(Emcon.silenced(before: after, after: after).isEmpty)
        XCTAssertTrue(Emcon.stillShowing(Emcon.Snapshot()).isEmpty)
    }
}
