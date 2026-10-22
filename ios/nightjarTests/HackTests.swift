import XCTest
@testable import nightjar

/// The mouth's pure machinery: payload sources, transforms, framing and
/// target parsing — the parts of send.py that can be pinned down
/// without a network or a radio.
final class HackTests: XCTestCase {
    func testHexDecodingToleratesSeparators() throws {
        let data = try PayloadKit.decodeHex("de:ad be-e f")
        XCTAssertEqual([UInt8](data), [0xDE, 0xAD, 0xBE, 0xEF])
    }

    func testHexDecodingRejectsBadInput() {
        XCTAssertThrowsError(try PayloadKit.decodeHex("zz"))
        XCTAssertThrowsError(try PayloadKit.decodeHex("abc"))
    }

    func testXorKeyParsing() {
        XCTAssertEqual([UInt8](PayloadKit.xorKey("0x5a")), [0x5A])
        XCTAssertEqual([UInt8](PayloadKit.xorKey("5a")), [0x5A])
        XCTAssertEqual([UInt8](PayloadKit.xorKey("de:ad")), [0xDE, 0xAD])
        XCTAssertEqual([UInt8](PayloadKit.xorKey("key")), [UInt8]("key".utf8))
    }

    func testXorRoundTrips() {
        let data = Data("hello".utf8)
        let key = PayloadKit.xorKey("0x5a")
        XCTAssertEqual(PayloadKit.xor(PayloadKit.xor(data, key: key), key: key), data)
    }

    func testGzipRoundTrips() throws {
        let data = Data("hello, world — the quick brown payload".utf8)
        let zipped = try XCTUnwrap(PayloadKit.gzipCompress(data))
        XCTAssertEqual(Array(zipped.prefix(2)), [0x1F, 0x8B])
        XCTAssertEqual(try FreedoomZip.gunzip(zipped), data)
    }

    func testGzipEmpty() throws {
        let zipped = try XCTUnwrap(PayloadKit.gzipCompress(Data()))
        XCTAssertEqual(try FreedoomZip.gunzip(zipped), Data())
    }

    func testBuildAppliesTransformsInOrder() throws {
        let data = try PayloadKit.build(source: "text", text: "hello", hex: "", b64: "",
                                        xorSpec: "0x5a", useGzip: false)
        XCTAssertEqual(PayloadKit.xor(data, key: PayloadKit.xorKey("0x5a")),
                       Data("hello".utf8))
    }

    func testFramingShapes() {
        let len = PayloadKit.frame(Data("abc".utf8), framing: "len")
        XCTAssertEqual([UInt8](len.prefix(4)), [0, 0, 0, 3])
        XCTAssertEqual(PayloadKit.unframe(len, framing: "len"), Data("abc".utf8))

        let json = PayloadKit.frame(Data("abc".utf8), framing: "json")
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual(object?["payload"] as? String, "YWJj")
        XCTAssertEqual(PayloadKit.unframe(json, framing: "json"), Data("abc".utf8))

        let raw = Data([1, 2, 3])
        XCTAssertEqual(PayloadKit.frame(raw, framing: "raw"), raw)
        XCTAssertEqual(PayloadKit.unframe(raw, framing: "raw"), raw)
    }

    func testHexdumpShape() {
        let dump = PayloadKit.hexdump(Data("hello".utf8))
        XCTAssertTrue(dump.hasPrefix("    00000000  68 65 6c 6c 6f"))
        XCTAssertTrue(dump.hasSuffix("hello"))
        XCTAssertEqual(PayloadKit.hexdump(Data()), "    (empty)")
    }


    func testNetworkTargetsRejectInvalidPortsAndMissingHosts() {
        for target in [
            "tcp://127.0.0.1:0",
            "tcp://127.0.0.1:65536",
            "tcp://127.0.0.1:-1",
            "tcp://:443",
            "udp://example.com:0",
            "udp://example.com:65536",
            "tcp+tls://example.com:99999",
            "http://",
            "http://:80",
            "http://example.com:0",
            "http://example.com:",
            "https://example.com:65536",
            "https://example.com:9999999999999999999999",
            "https://[::1]:9999999999999999999999",
        ] {
            XCTAssertThrowsError(try SendTarget.parse(target), "Accepted invalid target: \(target)")
        }
    }

    func testNetworkTargetsAcceptPortBoundariesAndImplicitHTTPPorts() throws {
        switch try SendTarget.parse("tcp://127.0.0.1:1") {
        case .tcp(_, let port, _): XCTAssertEqual(port, 1)
        default: XCTFail("expected tcp")
        }
        switch try SendTarget.parse("udp://127.0.0.1:65535") {
        case .udp(_, let port): XCTAssertEqual(port, 65535)
        default: XCTFail("expected udp")
        }
        switch try SendTarget.parse("https://example.com/path") {
        case .http(let url, let https):
            XCTAssertTrue(https)
            XCTAssertEqual(url.host, "example.com")
            XCTAssertNil(url.port)
        default: XCTFail("expected https")
        }
        XCTAssertNoThrow(try SendTarget.parse("https://[::1]/path"))
    }

    func testTargetParsing() throws {
        switch try SendTarget.parse("tcp://127.0.0.1:9000") {
        case .tcp(let host, let port, let tls):
            XCTAssertEqual(host, "127.0.0.1"); XCTAssertEqual(port, 9000); XCTAssertFalse(tls)
        default: XCTFail("expected tcp")
        }
        switch try SendTarget.parse("tcp+tls://example.com:443") {
        case .tcp(_, _, let tls): XCTAssertTrue(tls)
        default: XCTFail("expected tls tcp")
        }
        switch try SendTarget.parse("udp://example.com:53") {
        case .udp(let host, let port):
            XCTAssertEqual(host, "example.com"); XCTAssertEqual(port, 53)
        default: XCTFail("expected udp")
        }
        switch try SendTarget.parse("https://example.com/hook") {
        case .http(_, let https): XCTAssertTrue(https)
        default: XCTFail("expected http")
        }
        if case .bleBeacon = try SendTarget.parse("ble://") {} else { XCTFail("expected beacon") }
        if case .bleGatt = try SendTarget.parse("ble-gatt://") {} else { XCTFail("expected gatt") }
        if case .bleWrite(_) = try SendTarget.parse("AA:BB:CC:DD:EE:FF") {} else {
            XCTFail("expected write for a bare MAC")
        }
        if case .bleWrite(_) = try SendTarget.parse("name:AirPods") {} else {
            XCTFail("expected write for name:")
        }
        XCTAssertThrowsError(try SendTarget.parse("carrier-pigeon://loft"))
        XCTAssertThrowsError(try SendTarget.parse("tcp://127.0.0.1:notaport"))
    }
}
