import XCTest
@testable import nightjar

/// Test vectors shared with the Python test-suite (tests/helpers.py),
/// so a payload decodes to the same words on both sides.
final class DecoderTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return result
    }

    func testAirPodsProSimulatedVector() {
        let payload = bytes("0719010e202a980708000000000000000000000000000000000000")
        let ident = Continuity.identifyApple(payload)
        XCTAssertEqual(ident.kind, "AirPods Pro")
        XCTAssertEqual(ident.details.first,
                       "AirPods Pro: L 80% (in ear), R 90% (in ear), case 70%, lid open, white")
        XCTAssertEqual(ident.messages, ["Proximity Pairing"])
    }

    func testAirPodsLegacyVectorFollowsTheFlippedLayout() {
        // Status 0x03: the 0x20 bit is clear, so left and right swap; case
        // battery is the low nibble of 0x70 and every charging flag is set.
        let payload = bytes("0719010e2003987008000000000000000000000000000000000000")
        let message = Continuity.parse(payload)[0]
        let state = Continuity.decodeAirPods(message)!
        XCTAssertEqual(state.leftBattery, 90)
        XCTAssertEqual(state.rightBattery, 80)
        XCTAssertTrue(state.rightInEar)
        XCTAssertFalse(state.leftInEar)
        XCTAssertEqual(state.caseBattery, 0)
        XCTAssertTrue(state.leftCharging && state.rightCharging && state.caseCharging)
        XCTAssertTrue(state.lidOpen)
        XCTAssertEqual(state.describe,
                       "AirPods Pro: L 90% charging, R 80% charging (in ear), case 0% charging, lid open, white")
    }

    func testUnknownBatteryNibbleIsNil() {
        let payload = bytes("0719010e2020ff0f0005000000000000000000000000000000000000")
        let state = Continuity.decodeAirPods(Continuity.parse(payload)[0])!
        XCTAssertNil(state.leftBattery)
        XCTAssertNil(state.caseBattery)
        XCTAssertEqual(state.colour, "gray")
    }

    func testFindMySeparatedVector() {
        let payload = bytes("121950303132333435363738393a3b3c3d3e3f4041424344450000")
        let ident = Continuity.identifyApple(payload)
        XCTAssertEqual(ident.kind, "Find My device (AirTag-class)")
        XCTAssertEqual(ident.details.first,
                       "Find My network broadcast (separated from owner), battery medium")
        XCTAssertEqual(ident.findMy?.separated, true)
    }

    func testFindMyBatteryBits() {
        let cases: [(UInt8, String)] = [(0x10, "full"), (0x50, "medium"), (0x90, "low"),
                                        (0xD0, "very low"), (0x7F, "medium")]
        for (status, expected) in cases {
            let payload = [0x12, 0x19, status] + [UInt8](repeating: 0, count: 24)
            XCTAssertEqual(Continuity.parseFindMy(payload)?.battery, expected)
        }
    }

    func testFindMyWithOwnerVector() {
        let ident = Continuity.identifyApple(bytes("12021000"))
        XCTAssertEqual(ident.kind, "Find My accessory (with owner)")
        XCTAssertEqual(ident.details.first, "Find My network broadcast (nearby its owner)")
        XCTAssertEqual(ident.findMy?.separated, false)
        XCTAssertNil(Continuity.parseFindMy(bytes("1219")))
    }

    func testIBeacon() {
        let payload = bytes("0215000102030405060708090a0b0c0d0e0f00070102c5")
        let ident = Continuity.identifyApple(payload)
        XCTAssertEqual(ident.kind, "iBeacon")
        XCTAssertEqual(ident.details.first,
                       "iBeacon 00010203-0405-0607-0809-0a0b0c0d0e0f major 7 minor 258, -59 dBm @ 1 m")
    }

    func testNearbyInfoOnlyLabelsTheVerifiedCode() {
        let watch = Continuity.identifyApple(bytes("10030a0000"))
        XCTAssertEqual(watch.kind, "Apple Watch")
        XCTAssertEqual(watch.details.first, "nearby state 0x0A (watch worn & unlocked)")
        let phone = Continuity.identifyApple(bytes("101103218a3c5109be7702d46f881ac549e05b"))
        XCTAssertEqual(phone.kind, "Apple device (Nearby Info)")
        XCTAssertEqual(phone.details.first, "nearby state 0x03")
        let flagged = Continuity.decodeNearbyInfo(Continuity.parse(bytes("10051a1c010203"))[0])!
        XCTAssertEqual(flagged.actionCode, 0x0A)
        XCTAssertEqual(flagged.statusFlags, 0x1)
        XCTAssertEqual(flagged.dataFlags, 0x1C)
    }

    func testNearbyActionAndTethering() {
        let action = Continuity.identifyApple(bytes("0f05c008112233"))
        XCTAssertEqual(action.details.first, "nearby action: Wi-Fi password share")
        let hotspot = Continuity.identifyApple(bytes("0e050100420103"))
        XCTAssertEqual(hotspot.kind, "iPhone (Instant Hotspot source)")
        XCTAssertEqual(hotspot.details.first, "hotspot-capable, battery 66%, cell 3 bars")
    }

    func testTlvChainAndTruncation() {
        let messages = Continuity.parse(bytes("0f02aabb10017f"))
        XCTAssertEqual(messages.map { $0.type }, [0x0F, 0x10])
        XCTAssertEqual(messages[0].value, [0xAA, 0xBB])
        XCTAssertEqual(Continuity.parse(bytes("0f0501")).count, 0)
    }

    func testTrackerTagsByServiceUUID() {
        let tile = Sighting(seenAt: 1, address: "A", name: nil, rssi: -60,
                            serviceUUIDs: ["0000feed-0000-1000-8000-00805f9b34fb"])
        let classified = Classification.classify(tile)
        XCTAssertEqual(classified.kind, "Tile tracker")
        XCTAssertTrue(classified.trackerShaped)

        let fmdn = Sighting(seenAt: 1, address: "B", name: nil, rssi: -60,
                            serviceUUIDs: ["0000feaa-0000-1000-8000-00805f9b34fb"],
                            serviceData: ["0000feaa-0000-1000-8000-00805f9b34fb":
                                            [0x40] + [UInt8](repeating: 0x11, count: 21)])
        let google = Classification.classify(fmdn)
        XCTAssertEqual(google.kind, "Find My Device network tag (Google)")
        XCTAssertTrue(google.trackerShaped)

        let exposure = Sighting(seenAt: 1, address: "C", name: nil, rssi: -60,
                                serviceUUIDs: ["0000fd6f-0000-1000-8000-00805f9b34fb"])
        XCTAssertEqual(Classification.classify(exposure).kind, "Phone (Exposure Notification)")
        XCTAssertFalse(Classification.classify(exposure).trackerShaped)
    }

    func testTheLastFloorNamesWhatNothingElseClaims() {
        // A custom 128-bit service and nothing
        // else: distinguishable, not "unknown".
        let custom = Sighting(
            seenAt: 1, address: "E", name: nil,
            rssi: -60,
            serviceUUIDs: [
                "12345678-1234-1234-1234-1234567890ab"])
        let hit = Classification.classify(custom)
        XCTAssertEqual(hit.kind,
                       "BLE device — custom service")
        XCTAssertEqual(hit.rank,
                       Classification.rankFloor)
        XCTAssertTrue(hit.details.contains(
            "advertises custom service "
            + "12345678-1234-1234-1234-1234567890ab"))

        // An unregistered 16-bit service
        // (0xFFF3: absent from the SIG list
        // and the curated table alike).
        let unnamed = Sighting(
            seenAt: 1, address: "F", name: nil,
            rssi: -60,
            serviceUUIDs: [
                "0000fff3-0000-1000-8000-00805f9b34fb"])
        XCTAssertEqual(
            Classification.classify(unnamed).kind,
            "BLE device — service 0xFFF3")

        // An unassigned maker code (0xBEEF).
        let maker = Sighting(
            seenAt: 1, address: "G", name: nil,
            rssi: -60,
            manufacturerData: [0xBEEF: [0x01, 0x02]])
        XCTAssertEqual(
            Classification.classify(maker).kind,
            "BLE device — maker code 0xBEEF")

        // The floor never outranks a real
        // reading standing beside it.
        let tile = Sighting(
            seenAt: 1, address: "H", name: nil,
            rssi: -60,
            serviceUUIDs: [
                "0000feed-0000-1000-8000-00805f9b34fb",
                "12345678-1234-1234-1234-1234567890ab"])
        XCTAssertEqual(
            Classification.classify(tile).kind,
            "Tile tracker")

        // A named device keeps its name as
        // the label; the floor names the kind.
        let named = Sighting(
            seenAt: 1, address: "I",
            name: "Porch sensor", rssi: -60,
            serviceUUIDs: [
                "12345678-1234-1234-1234-1234567890ab"])
        let row = DeviceRow(sighting: named)
        XCTAssertEqual(row.label, "Porch sensor")
        XCTAssertEqual(row.kind,
                       "BLE device — custom service")

        // A seeking-only broadcast: what it
        // wants names what it is.
        let seeking = Sighting(
            seenAt: 1, address: "J", name: nil,
            rssi: -60,
            solicitedUUIDs: [
                "0000180d-0000-1000-8000-00805f9b34fb"])
        let sought = Classification.classify(seeking)
        XCTAssertEqual(sought.kind,
                       "BLE device — seeking a service")
        XCTAssertTrue(sought.details.contains(
            "seeking service Heart Rate"))
    }

    func testFMDNSeparatedStateIsNamed() {
        // Round 3: the frame byte is a state.
        // 0x41 is the tag away from its owner —
        // the detail must say so, where 0x40
        // reads near owner.
        let separated = Sighting(
            seenAt: 1, address: "D", name: nil, rssi: -60,
            serviceUUIDs: ["0000feaa-0000-1000-8000-00805f9b34fb"],
            serviceData: ["0000feaa-0000-1000-8000-00805f9b34fb":
                            [0x41] + [UInt8](repeating: 0x22, count: 21)])
        let hit = Classification.classify(separated)
        XCTAssertEqual(hit.kind, "Find My Device network tag (Google)")
        XCTAssertEqual(hit.details.first,
                       "Find My Device network (separated from owner)")
    }

    func testDULTByServiceDataOnly() {
        // The unwanted-tracker standard, matched
        // on service data for 0xFCB2: byte 1
        // bit 0 clear = separated, set = near
        // owner. The bare UUID alone must NOT
        // claim it.
        let uuid = "0000fcb2-0000-1000-8000-00805f9b34fb"
        let away = Sighting(
            seenAt: 1, address: "E", name: nil, rssi: -60,
            serviceUUIDs: [uuid],
            serviceData: [uuid: [0x07, 0x00]])
        let awayHit = Classification.classify(away)
        XCTAssertEqual(awayHit.kind, "DULT tracker — separated")
        XCTAssertTrue(awayHit.trackerShaped)
        let near = Sighting(
            seenAt: 1, address: "F", name: nil, rssi: -60,
            serviceUUIDs: [uuid],
            serviceData: [uuid: [0x07, 0x01]])
        XCTAssertEqual(Classification.classify(near).kind,
                       "DULT tracker — near owner")
        let bare = Sighting(
            seenAt: 1, address: "G", name: nil, rssi: -60,
            serviceUUIDs: [uuid])
        XCTAssertNotEqual(Classification.classify(bare).kind,
                          "DULT tracker — separated")
        XCTAssertNotEqual(Classification.classify(bare).kind,
                          "DULT tracker — near owner")
    }

    func testServiceRegistryFloor() {
        // The SIG's registry names what the
        // curated table never carried (Blecon's
        // member service), and curated names
        // still outrank it.
        XCTAssertGreaterThan(
            ServiceRegistry.names.count, 70)
        XCTAssertEqual(
            ServiceRegistry.names[0xFD0D],
            "Blecon Advertising Service")
        XCTAssertEqual(
            Services.name("0000180d-0000-1000-8000-00805f9b34fb"),
            "Heart Rate")
    }

    func testEddystoneUrlAndFastPair() {
        let url: [UInt8] = [0x10, 0xF0, 0x03] + Array("example".utf8) + [0x07] + Array("/x".utf8)
        XCTAssertEqual(Services.decodeEddystone(url)?.describe, "Eddystone-URL https://example.com/x")
        XCTAssertEqual(Services.decodeFastPair([0x2D, 0x7A, 0x23])?.describe,
                       "Fast Pair, discoverable (model 0x2D7A23)")
        // Paired mode carries account-key filter data, not a three-byte model ID.
        let paired: [UInt8] = [0x00, 0x40, 0x01, 0x02, 0x03, 0x04, 0x21, 0x00, 0x01]
        XCTAssertEqual(Services.decodeFastPair(paired)?.describe,
                       "Fast Pair device (paired, not discoverable)")
    }

    func testMicrosoft() {
        let swift = Sighting(seenAt: 1, address: "D", name: nil, rssi: -60,
                             manufacturerData: [0x0006: bytes("03060800")])
        XCTAssertEqual(Classification.classify(swift).kind, "Windows device (Swift Pair)")
        let laptop = Sighting(seenAt: 1, address: "E", name: nil, rssi: -60,
                              manufacturerData: [0x0006: bytes("010f2000")])
        XCTAssertEqual(Classification.classify(laptop).kind, "Windows laptop")
        let named = Vendors.decodeMicrosoft([0x03, 0x00, 0x80] + Array("Surface Earbuds".utf8))!
        XCTAssertEqual(named.details, ["in pairing mode (Swift Pair)",
                                       "announces itself as 'Surface Earbuds'"])
    }

    func testMakersAndFallbacks() {
        let garmin = Sighting(seenAt: 1, address: "F", name: nil, rssi: -60,
                              manufacturerData: [0x0087: [0x01]])
        XCTAssertEqual(Classification.classify(garmin).kind, "Garmin device")
        let named = Sighting(seenAt: 1, address: "G", name: "Printer", rssi: -60)
        XCTAssertEqual(Classification.classify(named).kind, "Named device")
        let unknown = Sighting(seenAt: 1, address: "H", name: nil, rssi: -60)
        XCTAssertEqual(Classification.classify(unknown).kind, "Unknown device")
        XCTAssertEqual(Vendors.companyName(0x004C), "Apple")
        XCTAssertEqual(Vendors.companyName(0xBEEF), "0xBEEF")
    }

    func testCompanyRegistryCoversTheSIGList() {
        // The whole assigned registry rides
        // along: thousands of makers the curated
        // table never named are decodable now.
        XCTAssertGreaterThan(
            CompanyRegistry.names.count, 4000)
        XCTAssertEqual(
            Vendors.companyName(0x0005), "3Com")
        XCTAssertEqual(
            Vendors.companyName(0x060F),
            "Signify Netherlands B.V.")
        // The house's curated short names still
        // outrank the registry's legal names.
        XCTAssertEqual(
            Vendors.companyName(0x009E), "Bose")
    }

    func testDeviceRowTrendAndRange() {
        var row = DeviceRow(sighting: Sighting(seenAt: 1, address: "A", name: nil, rssi: -85))
        for (index, rssi) in [-84, -83, -60, -58, -55].enumerated() {
            row.observe(Sighting(seenAt: Double(index + 2), address: "A", name: nil, rssi: rssi))
        }
        XCTAssertEqual(row.trend, "approaching")
        XCTAssertEqual(row.trendArrow, "▲")
        XCTAssertEqual(row.rangeBand, "immediate")
        XCTAssertEqual(row.sightings, 6)
        XCTAssertEqual(row.rssiClosest, -55)
    }

    // MARK: - Bonjour TXT records

    /// An Apple TV's AirPlay record, keys as the
    /// device states them: model, device id, the
    /// two-part features word (0x5A7FFFF7 sets the
    /// video/photo/slideshow/screen/audio bits),
    /// and a password at the door.
    func testBonjourTXTAirPlay() {
        let facts = BonjourTXT.facts(
            type: "_airplay._tcp",
            txt: ["model": "AppleTV3,2",
                  "deviceid": "AA:BB:CC:DD:EE:FF",
                  "features": "0x5A7FFFF7,0x1E",
                  "pw": "1"])
        XCTAssertEqual(facts, [
            "model AppleTV3,2",
            "device id AA:BB:CC:DD:EE:FF",
            "plays video, photo, slideshow, screen, audio",
            "password required",
        ])
    }

    /// An AirPort Express RAOP record: the model
    /// rides under am, the encryption list names
    /// RSA/FairPlay, the codec list carries ALAC.
    func testBonjourTXTRAOP() {
        let facts = BonjourTXT.facts(
            type: "_raop._tcp",
            txt: ["am": "AirPort4,107",
                  "et": "0,1,3,5",
                  "cn": "0,1,2",
                  "pw": "0"])
        XCTAssertEqual(facts, [
            "model AirPort4,107",
            "audio encrypted (RSA/FairPlay)",
            "lossless audio (ALAC)",
        ])
    }

    /// A Chromecast states its model under md;
    /// a printer under ty, with its location in
    /// note. An empty record states nothing.
    func testBonjourTXTModelKeys() {
        XCTAssertEqual(BonjourTXT.facts(
            type: "_googlecast._tcp",
            txt: ["md": "Chromecast",
                  "fn": "Living Room"]),
            ["model Chromecast"])
        XCTAssertEqual(BonjourTXT.facts(
            type: "_ipp._tcp",
            txt: ["ty": "HP LaserJet Pro",
                  "note": "Office"]),
            ["model HP LaserJet Pro",
             "says it lives at Office"])
        XCTAssertEqual(BonjourTXT.facts(
            type: "_airplay._tcp", txt: [:]), [])
    }
}
