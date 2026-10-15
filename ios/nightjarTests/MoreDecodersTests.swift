import XCTest
@testable import nightjar

/// Vectors for the MoreDecoders chain step. Each vector is a complete
/// advertisement payload (manufacturer block after the company ID, or
/// service data after the UUID) with the reading worked out by hand
/// from the format's public spec, so a decoder change that alters a
/// label or a number fails here first.
final class MoreDecodersTests: XCTestCase {
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

    private func sighting(manufacturer: [UInt16: [UInt8]] = [:],
                          services: [String] = [],
                          serviceData: [String: [UInt8]] = [:]) -> Sighting {
        Sighting(seenAt: 0, address: "AA:BB:CC:DD:EE:FF", name: nil, rssi: -60,
                 manufacturerData: manufacturer, serviceUUIDs: services,
                 serviceData: serviceData)
    }

    private let fe95 = "0000fe95-0000-1000-8000-00805f9b34fb"
    private let fcd2 = "0000fcd2-0000-1000-8000-00805f9b34fb"
    private let fd3d = "0000fd3d-0000-1000-8000-00805f9b34fb"
    private let fd5a = "0000fd5a-0000-1000-8000-00805f9b34fb"
    private let feed = "0000feed-0000-1000-8000-00805f9b34fb"

    // MARK: - Xiaomi MiBeacon

    /// Frame control 0x5040 (v5, object-include), product 0x055B
    /// (LYWSD03MMC), counter 42, then temperature object 0x1004 =
    /// 215 -> 21.5 C, humidity object 0x1006 = 455 -> 45.5 %,
    /// battery object 0x100A = 90.
    func testMiBeaconPlaintextReadings() {
        let data = hexBytes("40505b052a041002d700061002c7010a10015a")
        let s = sighting(serviceData: [fe95: data])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "Xiaomi Mijia temperature/humidity sensor 2")
        XCTAssertEqual(hit?.details, ["21.5 °C, 45.5% RH, battery 90%"])
        XCTAssertEqual(Classification.classify(s).kind,
                       "Xiaomi Mijia temperature/humidity sensor 2")
    }

    /// Frame control 0x5050 adds the MAC-include bit: six MAC bytes sit
    /// between the frame counter and the objects.
    func testMiBeaconMACAndBatteryObject() {
        let data = hexBytes("50505b0509a4c1381122330a100164")
        let hit = MoreDecoders.identify(sighting(serviceData: [fe95: data]))
        XCTAssertEqual(hit?.kind, "Xiaomi Mijia temperature/humidity sensor 2")
        XCTAssertEqual(hit?.details,
                       ["device MAC a4:c1:38:11:22:33", "battery 100%"])
    }

    /// Frame control 0x5048 sets the encrypted bit: labelled with the
    /// product name, contents never decoded.
    func testMiBeaconEncryptedIsLabelledNotDecoded() {
        let data = hexBytes("48505b0507aabbccddeeff112233")
        let hit = MoreDecoders.identify(sighting(serviceData: [fe95: data]))
        XCTAssertEqual(hit?.kind, "Xiaomi Mijia temperature/humidity sensor 2")
        XCTAssertEqual(hit?.details,
                       ["encrypted, readings not decoded (bindkey required)"])
    }

    /// An unlisted product ID falls back to the bare ID, never a guess.
    func testMiBeaconUnknownProductFallback() {
        let data = hexBytes("4050341201")
        let hit = MoreDecoders.identify(sighting(serviceData: [fe95: data]))
        XCTAssertEqual(hit?.kind, "Xiaomi MiBeacon device 0x1234")
        XCTAssertEqual(hit?.details, [])
    }

    func testMiBeaconTruncatedFrameRejected() {
        let data = hexBytes("4050")
        XCTAssertNil(MoreDecoders.identify(sighting(serviceData: [fe95: data])))
    }

    // MARK: - BTHome v2

    /// A real-world style capture: info 0x40 (v2, plaintext), packet
    /// id 27, battery 100 %, temperature 0x08C8 -> 22.48 C, humidity
    /// 0x1A6C -> 67.64 %.
    func testBTHomeV2Readings() {
        let data = hexBytes("40001b016402c808036c1a")
        let s = sighting(serviceData: [fcd2: data])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "BTHome sensor")
        XCTAssertEqual(hit?.details, ["battery 100%, 22.48 °C, 67.64% RH"])
        XCTAssertEqual(Classification.classify(s).kind, "BTHome sensor")
    }

    /// Info 0x41 sets the encryption bit.
    func testBTHomeEncryptedIsLabelledNotDecoded() {
        let data = hexBytes("41deadbeef")
        let hit = MoreDecoders.identify(sighting(serviceData: [fcd2: data]))
        XCTAssertEqual(hit?.kind, "BTHome sensor")
        XCTAssertEqual(hit?.details,
                       ["encrypted, readings not decoded (bindkey required)"])
    }

    /// Version bits other than 2 are not BTHome v2 (v1 frames share
    /// the UUID with a different layout) and stay unclaimed.
    func testBTHomeV1FramingNotClaimed() {
        let data = hexBytes("00020164")
        XCTAssertNil(MoreDecoders.identify(sighting(serviceData: [fcd2: data])))
    }

    // MARK: - RuuviTag

    /// Format 5: 22.50 C, 45.5 % RH, 1013.2 hPa, accel
    /// -500/250/1000 mG, power field 0xAC34 -> battery 2977 mV.
    func testRuuviFormat5() {
        let payload = hexBytes("0511944718c878fe0c00fa03e8ac342a01f4a1b2c3d4e5f6")
        let s = sighting(manufacturer: [0x0499: payload])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "RuuviTag sensor")
        XCTAssertEqual(hit?.details,
                       ["22.50 °C, 45.5% RH, 1013.2 hPa, accel -500/250/1000 mG, battery 2977 mV"])
        XCTAssertEqual(Classification.classify(s).kind, "RuuviTag sensor")
    }

    /// Format 3: humidity 128 -> 64.0 %, temperature bytes 0x16 0x32
    /// -> 22.50 C, same pressure/accel/battery as the format-5 vector.
    func testRuuviFormat3() {
        let payload = hexBytes("03801632c878fe0c00fa03e80ba1")
        let hit = MoreDecoders.identify(sighting(manufacturer: [0x0499: payload]))
        XCTAssertEqual(hit?.kind, "RuuviTag sensor")
        XCTAssertEqual(hit?.details,
                       ["22.50 °C, 64.0% RH, 1013.2 hPa, accel -500/250/1000 mG, battery 2977 mV"])
    }

    func testRuuviUnknownFormatNotClaimed() {
        let payload = hexBytes("070102030405060708090a0b0c0d")
        XCTAssertNil(MoreDecoders.identify(sighting(manufacturer: [0x0499: payload])))
    }

    // MARK: - AltBeacon

    /// Beacon code BE AC, ID 0x01...0x14, reference RSSI 0xC5 = -59,
    /// reserved 0x00 — 24 payload bytes under Radius Networks' 0x0118.
    func testAltBeacon() {
        let payload = hexBytes("beac0102030405060708090a0b0c0d0e0f1011121314c500")
        let hit = MoreDecoders.identify(sighting(manufacturer: [0x0118: payload]))
        XCTAssertEqual(hit?.kind, "AltBeacon")
        XCTAssertEqual(hit?.details, ["beacon id 0102030405060708..., -59 dBm @ 1 m"])
    }

    func testAltBeaconWrongCodeRejected() {
        let payload = hexBytes("beab0102030405060708090a0b0c0d0e0f1011121314c500")
        XCTAssertNil(MoreDecoders.identify(sighting(manufacturer: [0x0118: payload])))
    }

    // MARK: - Govee

    /// Packed reading 0x036C4C = 224332: temperature 224 -> 22.4 C,
    /// humidity 332 -> 33.2 %, battery byte 0x5A = 90 %.
    func testGoveeH5075Frame() {
        let payload = hexBytes("00036c4c5a00")
        let s = sighting(manufacturer: [0xEC88: payload])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "Govee thermometer")
        XCTAssertEqual(hit?.details, ["22.4 °C, 33.2% RH, battery 90%"])
        XCTAssertEqual(Classification.classify(s).kind, "Govee thermometer")
    }

    func testGoveeBadTrailerRejected() {
        let payload = hexBytes("00036c4c5a01")
        XCTAssertNil(MoreDecoders.identify(sighting(manufacturer: [0xEC88: payload])))
    }

    // MARK: - Microsoft Swift Pair

    func testSwiftPairStrictPrefix() {
        var payload: [UInt8] = [0x03, 0x00, 0x80]
        payload.append(contentsOf: "Surface Earbuds".utf8)
        let s = sighting(manufacturer: [0x0006: payload])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "Microsoft Swift Pair")
        XCTAssertEqual(hit?.details,
                       ["in pairing mode (Swift Pair)",
                        "announces itself as 'Surface Earbuds'"])
        XCTAssertEqual(Classification.classify(s).kind, "Microsoft Swift Pair")
    }

    /// The looser 0x03 0x06 ... beacon is NOT the documented prefix:
    /// MoreDecoders passes and Vendors keeps its existing answer.
    func testSwiftPairNonStrictStaysWithVendors() {
        let s = sighting(manufacturer: [0x0006: hexBytes("03060800")])
        XCTAssertNil(MoreDecoders.identify(s))
        XCTAssertEqual(Classification.classify(s).kind, "Windows device (Swift Pair)")
    }

    // MARK: - Recognition only

    func testTileRecognition() {
        let hit = MoreDecoders.identify(sighting(services: [feed]))
        XCTAssertEqual(hit?.kind, "Tile tracker")
        XCTAssertEqual(hit?.trackerShaped, true)
    }

    func testSmartTagRecognition() {
        let s = sighting(services: [fd5a])
        let hit = MoreDecoders.identify(s)
        XCTAssertEqual(hit?.kind, "SmartThings Find device (Samsung tag or Galaxy)")
        XCTAssertEqual(hit?.trackerShaped, true)
        XCTAssertEqual(Classification.classify(s).kind, "SmartThings Find device (Samsung tag or Galaxy)")
    }

    func testSwitchBotRecognition() {
        let hit = MoreDecoders.identify(sighting(serviceData: [fd3d: [0x48, 0x46]]))
        XCTAssertEqual(hit?.kind, "SwitchBot")
    }

    /// A bare FD3D UUID with no service data is not claimed here.
    func testSwitchBotUUIDOnlyNotClaimed() {
        XCTAssertNil(MoreDecoders.identify(sighting(services: [fd3d])))
    }

    // MARK: - Already covered elsewhere

    /// iBeacon is Continuity's job (Apple company 0x004C, type 0x02,
    /// length 0x15): the chain answers before MoreDecoders is asked,
    /// and this pins that the new step did not disturb it.
    func testIBeaconStaysWithContinuity() {
        let payload = hexBytes("0215000102030405060708090a0b0c0d0e0f00070102c5")
        let s = sighting(manufacturer: [0x004C: payload])
        XCTAssertEqual(Classification.classify(s).kind, "iBeacon")
    }
}
