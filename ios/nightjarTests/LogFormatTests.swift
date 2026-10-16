import XCTest
@testable import nightjar

/// The log contract: what the phone writes must be what the Mac reads.
final class LogFormatTests: XCTestCase {
    func testSightingLineMatchesTheContractExactly() {
        let sighting = Sighting(
            seenAt: 1760000001.25,
            address: "778F707E-A2F9-1661-F38D-75A6A13CFCB5",
            name: "AirPods Pro",
            rssi: -58,
            manufacturerData: [0x004C: [0x07, 0x19, 0x01, 0x0E, 0x20]],
            serviceUUIDs: ["0000feed-0000-1000-8000-00805f9b34fb"],
            txPower: nil)
        XCTAssertEqual(
            sighting.jsonLine,
            "{\"type\": \"sighting\", \"seen_at\": 1760000001.250, "
            + "\"address\": \"778F707E-A2F9-1661-F38D-75A6A13CFCB5\", \"name\": \"AirPods Pro\", "
            + "\"rssi\": -58, \"manufacturer_data\": {\"76\": \"0719010e20\"}, "
            + "\"service_uuids\": [\"0000feed-0000-1000-8000-00805f9b34fb\"], \"tx_power\": null}")
    }

    func testNullsAndServiceData() {
        let sighting = Sighting(
            seenAt: 1760000000,
            address: "X",
            name: nil,
            rssi: nil,
            serviceData: ["0000feaa-0000-1000-8000-00805f9b34fb": [0x40, 0x01]])
        let line = sighting.jsonLine
        XCTAssertTrue(line.contains("\"name\": null"))
        XCTAssertTrue(line.contains("\"rssi\": null"))
        XCTAssertTrue(line.contains("\"manufacturer_data\": {}"))
        XCTAssertTrue(line.contains("\"service_data\": {\"0000feaa-0000-1000-8000-00805f9b34fb\": \"4001\"}"))
        XCTAssertTrue(line.hasSuffix("}"))
        // And it is valid JSON by Foundation's reckoning too.
        let object = try? JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "sighting")
        XCTAssertEqual(object?["seen_at"] as? Double, 1760000000)
    }

    func testStringEscaping() {
        XCTAssertEqual(JSONL.string("plain"), "\"plain\"")
        XCTAssertEqual(JSONL.string("a \"quoted\" name"), "\"a \\\"quoted\\\" name\"")
        XCTAssertEqual(JSONL.string("back\\slash"), "\"back\\\\slash\"")
        XCTAssertEqual(JSONL.string("line\nbreak\ttab"), "\"line\\nbreak\\ttab\"")
        XCTAssertEqual(JSONL.string("\u{01}"), "\"\\u0001\"")
        XCTAssertEqual(JSONL.string("émoji 🐦"), "\"émoji 🐦\"")
    }

    func testNumbers() {
        XCTAssertEqual(JSONL.seconds(1760000001.25), "1760000001.250")
        XCTAssertEqual(JSONL.int(-61), "-61")
        XCTAssertEqual(JSONL.int(nil), "null")
        XCTAssertEqual(JSONL.hex([0x00, 0xAB, 0xFF]), "00abff")
    }

    func testTimestampIsALocaleIndependentJSONNumber() throws {
        let timestamp = JSONL.seconds(1760000001.25)
        XCTAssertEqual(timestamp, "1760000001.250")

        // Device locales can substitute commas and grouping separators,
        // neither of which is legal in an unquoted JSON number.
        let german = String(format: "%.3f", locale: Locale(identifier: "de_DE"),
                            1760000001.25)
        XCTAssertNotEqual(timestamp, german)

        let encoded = Data("{\"ts\": \(timestamp)}".utf8)
        let decoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(decoded["ts"] as? Double, 1760000001.25)
    }

    func testUUIDSpelling() {
        XCTAssertEqual(CBUUIDTestHelper.spell("FEED"), "0000feed-0000-1000-8000-00805f9b34fb")
        XCTAssertEqual(CBUUIDTestHelper.spell("0000FEAA-0000-1000-8000-00805F9B34FB"),
                       "0000feaa-0000-1000-8000-00805f9b34fb")
        XCTAssertEqual(CBUUIDTestHelper.spell("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"),
                       "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        XCTAssertEqual(Services.short("0000feed-0000-1000-8000-00805f9b34fb"), 0xFEED)
        XCTAssertNil(Services.short("6e400001-b5a3-f393-e0a9-e50e24dcca9e"))
    }

    func testWriterAppendsLinesAndFooterSurvivesReopen() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = JSONLWriter(url: url)
        try writer.open()
        writer.append("{\"type\": \"session\", \"session_id\": \"abc123def456\", \"label\": null, "
                      + "\"label_source\": null, \"started_at\": 1760000000.000}")
        writer.append("{\"type\": \"sighting\", \"seen_at\": 1760000001.000, \"address\": \"A\", "
                      + "\"name\": null, \"rssi\": -60, \"manufacturer_data\": {}, "
                      + "\"service_uuids\": [], \"tx_power\": null}")
        writer.close()
        // Reopening appends rather than truncating — state restoration relies on it.
        let again = JSONLWriter(url: url)
        try again.open()
        again.append("{\"type\": \"session_end\", \"session_id\": \"abc123def456\", "
                     + "\"ended_at\": 1760000002.000, \"sightings\": 1}")
        again.close()
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(text.hasSuffix("\n"))

        let summary = SessionStore.summary(for: url)
        XCTAssertEqual(summary?.id, "abc123def456")
        XCTAssertEqual(summary?.startedAt, 1760000000)
        XCTAssertEqual(summary?.endedAt, 1760000002)
        XCTAssertEqual(summary?.sightings, 1)
        XCTAssertNil(summary?.label)
        XCTAssertEqual(SessionStore.countSightings(in: url), 1)
    }

    func testSessionFooterSurvivesUTF8SplitAtTailBoundary() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let header = "{\"type\":\"session\",\"session_id\":\"abc\",\"started_at\":1760000000.0}\n"
        let footer = "{\"type\":\"session_end\",\"ended_at\":1760000002.0,\"sightings\":1}\n"
        let closeSighting = "\"}\n"
        // Position the 4 KB tail read two bytes into the four-byte bird emoji.
        let padding = 4096 - 2 - closeSighting.utf8.count - footer.utf8.count
        XCTAssertGreaterThan(padding, 0)
        var log = Data(header.utf8)
        log.append(contentsOf: "{\"type\":\"sighting\",\"name\":\"".utf8)
        log.append(contentsOf: "🐦".utf8)
        log.append(Data(repeating: 0x61, count: padding))
        log.append(contentsOf: closeSighting.utf8)
        log.append(contentsOf: footer.utf8)
        try log.write(to: url)

        let summary = SessionStore.summary(for: url)
        XCTAssertEqual(summary?.id, "abc")
        XCTAssertEqual(summary?.endedAt, 1760000002)
        XCTAssertEqual(summary?.sightings, 1)
        XCTAssertEqual(summary?.isUnfinished, false)
    }

    func testSessionHeaderSurvivesUTF8SplitAtHeadBoundary() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nightjar-head-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let header = "{\"type\":\"session\",\"session_id\":\"abc\",\"started_at\":1760000000.0}\n"
        let footer = "{\"type\":\"session_end\",\"ended_at\":1760000002.0,\"sightings\":1}\n"
        var log = Data(header.utf8)
        log.append(contentsOf: "{\"type\":\"sighting\",\"name\":\"".utf8)
        // Position the 4 KB header read two bytes into the bird emoji
        // on the second line. The first, complete line must still parse.
        let padding = 4096 - log.count - 2
        XCTAssertGreaterThan(padding, 0)
        log.append(Data(repeating: 0x61, count: padding))
        log.append(contentsOf: "🐦".utf8)
        log.append(contentsOf: "\"}\n".utf8)
        log.append(contentsOf: footer.utf8)
        try log.write(to: url)

        let summary = SessionStore.summary(for: url)
        XCTAssertEqual(summary?.id, "abc")
        XCTAssertEqual(summary?.startedAt, 1760000000)
        XCTAssertEqual(summary?.endedAt, 1760000002)
    }

}

import CoreBluetooth

enum CBUUIDTestHelper {
    static func spell(_ text: String) -> String {
        return CBUUID(string: text).nightjarString
    }
}
