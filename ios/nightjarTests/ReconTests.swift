import XCTest
@testable import nightjar

/// The library builds, the maps are sane, the wire shapes are what
/// they claim to be.
final class ReconTests: XCTestCase {

    func testEveryProbeBuilds() {
        for name in ReconPayloads.names {
            XCTAssertNotNil(ReconPayloads.all[name])
            _ = try? ReconPayloads.build(name)
        }
    }

    func testPortMapsPointAtRealProbes() {
        for (_, name) in ReconPayloads.portMap {
            XCTAssertNotNil(ReconPayloads.all[name], "tcp map names \(name)")
        }
        for (_, name) in ReconPayloads.udpPortMap {
            XCTAssertNotNil(ReconPayloads.all[name], "udp map names \(name)")
        }
    }

    func testDNSQueryShape() {
        let blob = ReconPayloads.dnsQuery("example.com", "A")
        XCTAssertEqual(blob[0], 0x12)
        XCTAssertEqual(blob[2], 0x01)            // RD set
        XCTAssertEqual(blob[5], 0x01)            // QDCOUNT = 1
        XCTAssertTrue(blob.range(of: Data("\u{7}example\u{3}com".utf8)) != nil)
    }

    func testSNMPSysdescrIsBER() {
        let blob = ReconPayloads.snmpSysdescr()
        XCTAssertEqual(blob[0], 0x30)            // SEQUENCE
        XCTAssertTrue(blob.range(of: Data("public".utf8)) != nil)
        // 1.3.6.1.2.1.1.1.0 packed
        XCTAssertTrue(blob.range(of: Data([0x06, 0x08, 0x2B, 0x06, 0x01,
                                           0x02, 0x01, 0x01, 0x01, 0x00])) != nil)
    }

    func testMSSQLPreloginLengthMatches() {
        let blob = ReconPayloads.mssqlPrelogin()
        XCTAssertEqual(blob[0], 0x12)
        let declared = Int(blob[2]) << 8 | Int(blob[3])
        XCTAssertEqual(declared, blob.count)
    }

    func testSMB2Header() {
        let blob = ReconPayloads.smb2Negotiate()
        XCTAssertEqual(Array(blob[4..<8]), Array("SMB".utf8) + [0x00][0...0] + [])
        XCTAssertEqual(blob[4], 0xFE)
        let structure = Int(blob[8]) | Int(blob[9]) << 8
        XCTAssertEqual(structure, 64)
    }

    func testSMB1NegotiateLengthMatches() {
        let blob = ReconPayloads.smb1Negotiate()
        XCTAssertEqual(blob[1], 0xFF)
        let declared = Int(blob[1]) << 16 | Int(blob[2]) << 8 | Int(blob[3])
        XCTAssertEqual(declared, blob.count - 4)
    }

    func testWireguardInitIs148Bytes() {
        XCTAssertEqual(ReconPayloads.wireguardInit().count, 148)
    }

    func testWOLShape() {
        let blob = ReconPayloads.wolMagic()
        XCTAssertEqual(Array(blob.prefix(6)), Array(repeating: 0xFF, count: 6))
        XCTAssertEqual(blob.count, 6 + 16 * 6)
    }

    func testMQTTPlantConnectsThenPublishes() {
        let blob = ReconPayloads.mqttPlant()
        XCTAssertEqual(blob[0], 0x10)                    // CONNECT first
        XCTAssertTrue(blob.dropFirst(2).contains(0x31))  // retained PUBLISH
    }

    func testUnknownProbeSuggests() {
        XCTAssertThrowsError(try ReconPayloads.build("redis-pig")) { error in
            XCTAssertTrue("\(error)".contains("redis-ping"))
        }
    }

    func testFirstLineFallsBackToHex() {
        XCTAssertEqual(ReconPayloads.firstLine(Data("+PONG\r\nx".utf8)), "+PONG")
        XCTAssertFalse(ReconPayloads.firstLine(Data([0x00, 0x01, 0x02])).isEmpty)
    }
}
