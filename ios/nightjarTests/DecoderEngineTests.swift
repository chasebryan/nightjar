import XCTest
@testable import nightjar

/// The decoder engine: batteries from every format
/// present, the battery forecaster's honesty rules,
/// cadence, and advertisement-shape fingerprints.
final class DecoderEngineTests: XCTestCase {
    private func hexBytes(_ hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return result
    }

    private func sighting(
        manufacturer: [UInt16: [UInt8]] = [:],
        serviceData: [String: [UInt8]] = [:],
        at: TimeInterval = 0
    ) -> Sighting {
        Sighting(seenAt: at, address: "AA", name: nil,
                 rssi: -60, manufacturerData: manufacturer,
                 serviceData: serviceData)
    }

    private let fcd2 = "0000fcd2-0000-1000-8000-00805f9b34fb"
    private let fe95 = "0000fe95-0000-1000-8000-00805f9b34fb"
    private let feaa = "0000feaa-0000-1000-8000-00805f9b34fb"

    func testAirPodsComponentBatteries() {
        let payload = hexBytes(
            "0719010e202a980708000000000000000000000000000000000000")
        let readings = DecoderEngine.batteryReadings(
            sighting(manufacturer: [0x004C: payload]))
        let byComponent = Dictionary(uniqueKeysWithValues:
            readings.map { ($0.component, $0.percent) })
        XCTAssertEqual(byComponent["left"], 80)
        XCTAssertEqual(byComponent["right"], 90)
        XCTAssertEqual(byComponent["case"], 70)
    }

    func testRuuviVoltage() {
        let payload = hexBytes(
            "0511944718c878fe0c00fa03e8ac342a01f4a1b2c3d4e5f6")
        let readings = DecoderEngine.batteryReadings(
            sighting(manufacturer: [0x0499: payload]))
        XCTAssertEqual(readings.first?.millivolts, 2977)
        XCTAssertEqual(readings.first?.source, "RuuviTag")
    }

    func testBTHomeAndMiBeaconPercents() {
        let btHome = DecoderEngine.batteryReadings(
            sighting(serviceData: [
                fcd2: hexBytes("40001b016402c808036c1a")]))
        XCTAssertEqual(btHome.first?.percent, 100)
        let mi = DecoderEngine.batteryReadings(
            sighting(serviceData: [
                fe95: hexBytes(
                    "40505b052a041002d700061002c7010a10015a")]))
        XCTAssertEqual(mi.first?.percent, 90)
    }

    func testEddystoneTLMVoltage() {
        // TLM: version 0, battery 3000 mV, temp
        // 0x0B00 (11.0 C), count 1, uptime 600.
        let frame: [UInt8] = [0x20, 0x00, 0x0B, 0xB8,
                              0x0B, 0x00, 0x00, 0x00,
                              0x00, 0x01, 0x00, 0x00,
                              0x17, 0x70]
        let readings = DecoderEngine.batteryReadings(
            sighting(serviceData: [feaa: frame]))
        XCTAssertEqual(readings.first?.millivolts, 3000)
        XCTAssertEqual(readings.first?.source,
                       "Eddystone-TLM")
    }

    func testForecasterGivesARangedETA() {
        let samples: [(at: TimeInterval, percent: Int)] = [
            (0, 100), (1800, 95), (3600, 91), (5400, 85),
        ]
        let forecast = BatteryForecaster.percentForecast(
            samples: samples)
        XCTAssertNotNil(forecast)
        XCTAssertEqual(forecast!.ratePerHour, -9.8,
                       accuracy: 0.2)
        XCTAssertLessThan(forecast!.etaLowHours!, 8.6)
        XCTAssertGreaterThan(forecast!.etaHighHours!, 8.7)
        XCTAssertTrue(forecast!.text.contains("draining"))
    }

    func testForecasterRefusesNoisySlopes() {
        let samples: [(at: TimeInterval, percent: Int)] = [
            (0, 100), (900, 40), (1800, 95), (2700, 35),
        ]
        XCTAssertNil(BatteryForecaster.percentForecast(
            samples: samples))
    }

    func testForecasterNeedsTimeAndSamples() {
        let samples: [(at: TimeInterval, percent: Int)] = [
            (0, 100), (60, 99),
        ]
        XCTAssertNil(BatteryForecaster.percentForecast(
            samples: samples))
    }

    func testCadenceFromIntervals() {
        var row = DeviceRow(sighting: sighting(at: 0))
        for t in [10.0, 20, 30, 40] {
            row.observe(sighting(at: t))
        }
        XCTAssertEqual(row.cadenceText,
                       "advertises about every 10 s")
    }

    func testShapeSignatureIgnoresValues() {
        let a = sighting(manufacturer: [0x0499:
            hexBytes("0511944718c878fe0c00fa03e8ac342a01f4a1b2c3d4e5f6")])
        let b = sighting(manufacturer: [0x0499:
            hexBytes("050000000000000000000000000000000000000000000000")])
        XCTAssertEqual(DecoderEngine.payloadSignature(a),
                       DecoderEngine.payloadSignature(b))
        let c = sighting(
            manufacturer: [0x0499: hexBytes("0511")],
            serviceData: [fcd2: [0x40]])
        XCTAssertNotEqual(DecoderEngine.payloadSignature(a),
                          DecoderEngine.payloadSignature(c))
    }

    func testEntropyExtremes() {
        XCTAssertEqual(DecoderEngine.shannonEntropy(
            [UInt8](repeating: 0xAA, count: 64)), 0,
            accuracy: 0.001)
        let spread = (0..<256).map { UInt8($0 % 256) }
        XCTAssertGreaterThan(DecoderEngine
            .shannonEntropy(spread), 7.9)
    }

    func testRowCarriesBatteriesIntoDetails() {
        let row = DeviceRow(sighting: sighting(
            serviceData: [
                fcd2: hexBytes("40001b016402c808036c1a")]))
        XCTAssertEqual(row.batterySummary,
                       "battery 100% (BTHome v2)")
        XCTAssertTrue(row.details.contains(
            "battery 100% (BTHome v2)"))
    }
}
