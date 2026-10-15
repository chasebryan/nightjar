import XCTest
@testable import nightjar

/// The seeded library: every built-in must build to the bytes its
/// protocol expects — a typo'd hex string here is a broken payload
/// out in the world.
final class PayloadBookTests: XCTestCase {
    private func bytes(of item: SavedPayload) throws -> Data {
        try PayloadKit.build(source: item.source, text: item.text,
                             hex: item.text, b64: item.text,
                             xorSpec: item.xorKey, useGzip: item.useGzip)
    }

    func testFifteenBuiltIns() {
        XCTAssertEqual(PayloadBook.builtIns.count, 15)
        XCTAssertTrue(PayloadBook.builtIns.allSatisfy { $0.builtIn })
        XCTAssertEqual(Set(PayloadBook.builtIns.map { $0.name }).count, 15)
    }

    func testEveryBuiltInBuilds() throws {
        for item in PayloadBook.builtIns {
            let data = try bytes(of: item)
            XCTAssertFalse(data.isEmpty, item.name)
        }
    }

    func testWakeOnLanShape() throws {
        let wol = try XCTUnwrap(PayloadBook.builtIns.first {
            $0.name.hasPrefix("Wake-on-LAN")
        })
        let data = try bytes(of: wol)
        XCTAssertEqual(data.count, 102)               // 6 sync + 16 x MAC
        XCTAssertEqual([UInt8](data.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
    }

    func testDNSQueryShape() throws {
        let dns = try XCTUnwrap(PayloadBook.builtIns.first {
            $0.name.hasPrefix("DNS query")
        })
        let data = try bytes(of: dns)
        XCTAssertEqual(data.count, 29)
        XCTAssertEqual([UInt8](data.suffix(4)), [0x00, 0x01, 0x00, 0x01])
    }

    func testNTPRequestShape() throws {
        let ntp = try XCTUnwrap(PayloadBook.builtIns.first {
            $0.name.hasPrefix("NTP time")
        })
        let data = try bytes(of: ntp)
        XCTAssertEqual(data.count, 48)
        XCTAssertEqual(data.first, 0x1B)              // LI 0, VN 3, mode 3
    }

    func testMQTTConnectShape() throws {
        let mqtt = try XCTUnwrap(PayloadBook.builtIns.first {
            $0.name.hasPrefix("MQTT CONNECT")
        })
        let data = try bytes(of: mqtt)
        XCTAssertEqual(data[0], 0x10)                 // CONNECT packet
        XCTAssertEqual(Int(data[1]), data.count - 2) // remaining length
    }

    func testLegacySaveDecodesAsCustom() throws {
        // Payloads saved before `builtIn` existed have no such key.
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","name":"old",\
        "source":"text","text":"hi","xorKey":"","useGzip":false,\
        "framing":"raw"}
        """
        let item = try JSONDecoder().decode(SavedPayload.self,
                                            from: Data(json.utf8))
        XCTAssertFalse(item.builtIn)
        XCTAssertEqual(item.name, "old")
    }
}
