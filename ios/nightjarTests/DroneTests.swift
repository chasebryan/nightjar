import XCTest
@testable import nightjar

/// Remote ID (drone) decoding — vectors laid out per the field packing
/// in nightjar/remoteid.py, which is verified against
/// opendroneid-core-c. If the Python decoder and this one ever disagree
/// on a vector, one of them is wrong; they share these numbers on
/// purpose.
final class DroneTests: XCTestCase {
    private func message(_ type: UInt8, _ fill: (inout [UInt8]) -> Void) -> [UInt8] {
        var msg = [UInt8](repeating: 0, count: 25)
        msg[0] = (type << 4) | 0x02  // protocol version 2
        fill(&msg)
        return msg
    }

    private func serviceData(_ messages: [[UInt8]]) -> [UInt8] {
        if messages.count == 1 {
            return [0x0D, 0x00] + messages[0]
        }
        var pack: [UInt8] = [0xF2, 25, UInt8(messages.count)]
        for msg in messages { pack += msg }
        return [0x0D, 0x00] + pack
    }

    private func basicID(serial: String = "1581F6MK20240001") -> [UInt8] {
        message(0x0) { msg in
            msg[1] = 0x12  // ID type 1 (serial number), UA type 2 (multicopter)
            for (i, byte) in Array(serial.utf8).enumerated() { msg[2 + i] = byte }
        }
    }

    private func putI32(_ msg: inout [UInt8], _ offset: Int, _ value: Int32) {
        let bits = UInt32(bitPattern: value)
        msg[offset] = UInt8(bits & 0xFF)
        msg[offset + 1] = UInt8((bits >> 8) & 0xFF)
        msg[offset + 2] = UInt8((bits >> 16) & 0xFF)
        msg[offset + 3] = UInt8((bits >> 24) & 0xFF)
    }

    private func putU16(_ msg: inout [UInt8], _ offset: Int, _ value: Int) {
        msg[offset] = UInt8(value & 0xFF)
        msg[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    func testBasicIDDecodesSerialAndType() {
        let report = Drones.report(fromServiceData: serviceData([basicID()]))
        XCTAssertEqual(report?.serial, "1581F6MK20240001")
        XCTAssertEqual(report?.uaTypeName, "helicopter/multirotor")
        XCTAssertEqual(report?.idType, 1)
    }

    func testLocationDecodesPositionAltitudeSpeed() {
        let location = message(0x1) { msg in
            msg[1] = 0x24  // status airborne (2), height type AGL, no E/W, mult 0
            msg[2] = 45    // direction 45 degrees
            msg[3] = 34    // 34 * 0.25 = 8.5 m/s
            msg[4] = 0     // vertical speed 0
            putI32(&msg, 5, 312_235_000)    // 31.2235 N
            putI32(&msg, 9, -853_905_000)   // 85.3905 W
            putU16(&msg, 13, 2120)          // baro alt (60 + 1000) * 2 = 60 m
            putU16(&msg, 15, 2120)          // geo alt 60 m
            putU16(&msg, 17, 2082)          // height (41 + 1000) * 2 = 41 m
            putU16(&msg, 21, 3600)          // 360.0 s into the hour
        }
        let report = Drones.report(fromServiceData: serviceData([location]))
        let loc = report?.location
        XCTAssertEqual(loc?.statusName, "airborne")
        XCTAssertEqual(loc?.direction, 45)
        XCTAssertEqual(loc?.speedH, 8.5)
        XCTAssertEqual(loc?.latitude ?? 0, 31.2235, accuracy: 1e-9)
        XCTAssertEqual(loc?.longitude ?? 0, -85.3905, accuracy: 1e-9)
        XCTAssertEqual(loc?.altitudeGeo, 60)
        XCTAssertEqual(loc?.height, 41)
        XCTAssertEqual(loc?.heightRef, "AGL")
        XCTAssertEqual(report?.airborne, true)
    }

    func testSystemDecodesOperator() {
        let system = message(0x4) { msg in
            msg[1] = 0x01  // operator location: live GPS
            putI32(&msg, 2, 312_230_000)
            putI32(&msg, 6, -853_900_000)
            putU16(&msg, 10, 1)             // area count
            msg[12] = 25                    // radius 250 m
            putU16(&msg, 13, 2240)          // ceiling 120 m
            putU16(&msg, 15, 2000)          // floor 0 m
            msg[17] = 0x21                  // category 2, class 1
            putU16(&msg, 18, 2010)          // operator altitude 5 m
            msg[20] = 0x00; msg[21] = 0xE1; msg[22] = 0xF5; msg[23] = 0x05  // 100,000,000 LE
        }
        let report = Drones.report(fromServiceData: serviceData([system]))
        let sys = report?.system
        XCTAssertEqual(sys?.operatorLatitude ?? 0, 31.2230, accuracy: 1e-9)
        XCTAssertEqual(sys?.operatorLongitude ?? 0, -85.3900, accuracy: 1e-9)
        XCTAssertEqual(sys?.operatorLocationName, "live GPS")
        XCTAssertEqual(sys?.areaRadiusM, 250)
        XCTAssertEqual(sys?.timestampUnix, 1_546_300_800 + 100_000_000)
    }

    func testMessagePackDecodesAll() {
        let report = Drones.report(fromServiceData: serviceData([basicID(), basicID()]))
        XCTAssertEqual(report?.serial, "1581F6MK20240001")
    }

    func testNonRemoteIDIsNotADrone() {
        XCTAssertNil(Drones.report(fromServiceData: [0x00, 0x01, 0x02]))
        XCTAssertNil(Drones.report(fromServiceData: []))
        // Right shape, wrong app code.
        var wrong = serviceData([basicID()])
        wrong[0] = 0x00
        XCTAssertNil(Drones.report(fromServiceData: wrong))
    }

    func testClassificationLabelsTheDroneBySerial() {
        let sighting = Sighting(
            seenAt = 0, address: "AA", name: nil, rssi: -60,
            serviceData: ["0000fffa-0000-1000-8000-00805f9b34fb": serviceData([basicID()])])
        let classification = Classification.classify(sighting)
        XCTAssertEqual(classification.kind, "Drone (Remote ID)")
        XCTAssertEqual(classification.preferredLabel, "Drone 1581F6MK20240001")
        XCTAssertTrue(classification.details.first?.contains("serial 1581F6MK20240001") ?? false)
    }
}
