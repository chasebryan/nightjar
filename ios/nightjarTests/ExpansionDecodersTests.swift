import XCTest
@testable import nightjar

/// The expansion batch: formats admitted on
/// fetched public specifications, every vector
/// hand-worked from the layout it pins.
final class ExpansionDecodersTests: XCTestCase {
    private func uuid(_ short: String) -> String {
        "0000\(short)-0000-1000-8000-00805f9b34fb"
    }

    private func sighting(
        name: String? = nil,
        manufacturer: [UInt16: [UInt8]] = [:],
        serviceData: [String: [UInt8]] = [:]
    ) -> Sighting {
        Sighting(seenAt: 0, address: "AA", name: name,
                 rssi: -60, manufacturerData: manufacturer,
                 serviceData: serviceData)
    }

    func testSwitchBotMeterDetailed() {
        // Type 'T', battery 73, temperature 21.3 C,
        // humidity 65.
        let frame: [UInt8] = [0x54, 0x00, 73, 0x03,
                              0x95, 65]
        let s = sighting(serviceData: [uuid("fd3d"): frame])
        let found = ExpansionDecoders.identify(s)
        XCTAssertEqual(found?.kind, "SwitchBot Meter")
        XCTAssertTrue(found?.details.contains(
            "temperature 21.3 °C") ?? false)
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "SwitchBot" }
        XCTAssertEqual(battery?.percent, 73)
    }

    func testSwitchBotContactStates() {
        // Type 'd', battery 55, HAL open + light.
        let frame: [UInt8] = [0x64, 0x00, 55, 0x03,
                              0, 0, 0, 0, 0]
        let s = sighting(serviceData: [uuid("fd3d"): frame])
        let found = ExpansionDecoders.identify(s)
        XCTAssertEqual(found?.kind, "SwitchBot Contact sensor")
        XCTAssertTrue(found?.details.contains("door open")
                      ?? false)
    }

    func testPVVXCustom() {
        let frame: [UInt8] = [
            0xA4, 0xC1, 0x38, 0, 0, 0,
            0x08, 0x09,        // 23.12 C
            0xC6, 0x11,        // 45.50 %
            0xB3, 0x0B,        // 2995 mV
            88, 7, 0]
        let s = sighting(serviceData: [uuid("181a"): frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Mi thermometer (PVVX firmware)")
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "PVVX" }
        XCTAssertEqual(battery?.percent, 88)
        XCTAssertEqual(battery?.millivolts, 2995)
    }

    func testATC1441() {
        let frame: [UInt8] = [
            0xA4, 0xC1, 0x38, 0, 0, 0,
            0x00, 0xEB,        // 23.5 C, big-endian
            45,                // humidity
            76,                // battery %
            0x0B, 0xA4,        // 2980 mV, big-endian
            3]
        let s = sighting(serviceData: [uuid("181a"): frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Mi thermometer (ATC firmware)")
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "ATC" }
        XCTAssertEqual(battery?.percent, 76)
        XCTAssertEqual(battery?.millivolts, 2980)
    }

    func testEstimoteBattery() {
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0x12        // version 1, telemetry
        frame[9] = 0x01        // subframe B
        frame[17] = 0xE0       // voltage low bits
        frame[18] = 0x2E       // voltage high bits -> 3000 mV
        frame[19] = 82         // battery %
        let s = sighting(serviceData: [uuid("fe9a"): frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Estimote beacon")
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "Estimote" }
        XCTAssertEqual(battery?.percent, 82)
        XCTAssertEqual(battery?.millivolts, 3000)
    }

    func testBASBroadcast() {
        // Flags: level present. Power state:
        // charging + charge level good. Level 64.
        let frame: [UInt8] = [0x02, 0x20, 0x01, 64]
        let s = sighting(serviceData: [uuid("180f"): frame])
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "Battery Service" }
        XCTAssertEqual(battery?.percent, 64)
        XCTAssertEqual(battery?.state, "charging")
        // A length the flags don't predict is refused.
        let bad: [UInt8] = [0x02, 0x20, 0x01, 64, 0x00]
        XCTAssertNil(ExpansionDecoders
            .basBroadcastReading(bad))
    }

    func testBTHomeV1OptIn() {
        let frame: [UInt8] = [0x02, 0x01, 87,
                              0x03, 0x02, 0x2E, 0x09]
        let s = sighting(serviceData: [uuid("181c"): frame])
        UserDefaults.standard.set(false,
                                  forKey: "listen.bthomeV1")
        XCTAssertNil(ExpansionDecoders.identify(s))
        UserDefaults.standard.set(true,
                                  forKey: "listen.bthomeV1")
        defer {
            UserDefaults.standard.set(false,
                                      forKey: "listen.bthomeV1")
        }
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "BTHome v1 sensor")
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "BTHome v1" }
        XCTAssertEqual(battery?.percent, 87)
    }

    func testQingpingWeatherStation() {
        var frame = [UInt8](repeating: 0, count: 21)
        frame[1] = 0x09
        frame[10] = 0xE1; frame[11] = 0x00   // 22.5 C
        frame[12] = 0xC7; frame[13] = 0x01   // 45.5 %
        frame[20] = 0xDF                     // 95 %, flag bit set
        let s = sighting(serviceData: [uuid("fdcd"): frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Qingping weather station")
        let battery = DecoderEngine.batteryReadings(s)
            .first { $0.source == "Qingping" }
        XCTAssertEqual(battery?.percent, 95)
    }

    func testInkbird() {
        let frame: [UInt8] = [0x8E, 0x09, 0x88, 0x13,
                              0, 0, 0, 66, 0]
        let s = sighting(name: "sps",
                         manufacturer: [0x0000: frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Inkbird thermo-hygrometer")
    }

    func testThermoProLowBattery() {
        // Bit 1 of byte 4 CLEAR means low — the
        // inverted sense is the trap this pins.
        let frame: [UInt8] = [0xC2, 0xD7, 0x00, 48, 0, 0]
        let s = sighting(name: "TP357",
                         manufacturer: [0x0000: frame])
        let found = ExpansionDecoders.identify(s)
        XCTAssertEqual(found?.kind, "ThermoPro sensor")
        XCTAssertTrue(found?.details.contains(
            "battery low (ThermoPro)") ?? false)
        let ok: [UInt8] = [0xC2, 0xD7, 0x00, 48, 0x02, 0]
        let s2 = sighting(name: "TP357",
                          manufacturer: [0x0000: ok])
        XCTAssertFalse(ExpansionDecoders.identify(s2)?
            .details.contains("battery low (ThermoPro)")
            ?? true)
    }

    func testMicrosoftCDP() {
        let frame: [UInt8] = [0x01, 9, 8, 7, 6,
                              5, 4, 3, 2, 1]
        let s = sighting(manufacturer: [0x0006: frame])
        XCTAssertEqual(ExpansionDecoders.identify(s)?.kind,
                       "Windows / Android device")
    }
}
