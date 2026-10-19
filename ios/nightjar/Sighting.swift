import CoreBluetooth
import Foundation

let sigBaseSuffix = "-0000-1000-8000-00805f9b34fb"

extension CBUUID {
    /// Full 128-bit, lowercase, the way nightjar's logs spell UUIDs.
    var nightjarString: String {
        let text = uuidString.lowercased()
        if text.count == 4 { return "0000\(text)\(sigBaseSuffix)" }
        if text.count == 8 { return "\(text)\(sigBaseSuffix)" }
        return text
    }
}

/// One received BLE advertisement, as nightjar understands it.
struct Sighting {
    let seenAt: TimeInterval
    let address: String
    let name: String?
    let rssi: Int?
    let manufacturerData: [UInt16: [UInt8]]
    let serviceUUIDs: [String]
    let txPower: Int?
    let serviceData: [String: [UInt8]]
    /// Services this device is SEEKING — the
    /// solicited list. It names the role the
    /// device hopes to find, which is evidence
    /// about the device itself.
    let solicitedUUIDs: [String]
    /// Whether the advertiser accepts connections —
    /// CoreBluetooth reports it with the advertisement,
    /// and it separates beacons (listen-only by design)
    /// from devices that could be spoken to.
    let isConnectable: Bool?

    init(seenAt: TimeInterval, address: String, name: String?, rssi: Int?,
         manufacturerData: [UInt16: [UInt8]] = [:], serviceUUIDs: [String] = [],
         txPower: Int? = nil, serviceData: [String: [UInt8]] = [:],
         isConnectable: Bool? = nil,
         solicitedUUIDs: [String] = []) {
        self.seenAt = seenAt
        self.address = address
        self.name = name
        self.rssi = rssi
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.txPower = txPower
        self.serviceData = serviceData
        self.isConnectable = isConnectable
        self.solicitedUUIDs = solicitedUUIDs
    }

    /// Build a sighting from what CoreBluetooth hands the delegate.
    init(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber,
         seenAt: TimeInterval = Date().timeIntervalSince1970) {
        self.seenAt = seenAt
        // CoreBluetooth hides real MAC addresses; the per-host UUID is the
        // only stable handle there is, so that is the address.
        self.address = peripheral.identifier.uuidString

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        self.name = localName ?? peripheral.name

        let value = rssi.intValue
        self.rssi = (value == 127 || value == 0) ? nil : value  // 127: unavailable

        // Manufacturer data arrives as one blob whose first two bytes are
        // the company id, little-endian. Split those off: the id is the
        // key, the rest is the payload.
        var manufacturer: [UInt16: [UInt8]] = [:]
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           data.count >= 2 {
            let bytes = [UInt8](data)
            let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            manufacturer[company] = Array(bytes[2...])
        }
        self.manufacturerData = manufacturer

        var uuids: [String] = []
        if let list = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            uuids += list.map { $0.nightjarString }
        }
        if let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] {
            for uuid in overflow.map({ $0.nightjarString }) where !uuids.contains(uuid) {
                uuids.append(uuid)
            }
        }
        self.serviceUUIDs = uuids

        if let power = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            self.txPower = power.intValue
        } else {
            self.txPower = nil
        }

        if let connectable = advertisementData[
            CBAdvertisementDataIsConnectable] as? NSNumber {
            self.isConnectable = connectable.boolValue
        } else {
            self.isConnectable = nil
        }

        if let solicited = advertisementData[
            CBAdvertisementDataSolicitedServiceUUIDsKey]
            as? [CBUUID] {
            self.solicitedUUIDs = solicited.map {
                $0.nightjarString
            }
        } else {
            self.solicitedUUIDs = []
        }

        var serviceData: [String: [UInt8]] = [:]
        if let table = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in table {
                serviceData[uuid.nightjarString] = [UInt8](data)
            }
        }
        self.serviceData = serviceData
    }

    /// The log record: field order and spelling match the Python side.
    var jsonLine: String {
        let manufacturer = manufacturerData.keys.sorted().map { key -> (String, String) in
            (String(key), JSONL.string(JSONL.hex(manufacturerData[key] ?? [])))
        }
        var fields: [(String, String)] = [
            ("type", JSONL.string("sighting")),
            ("seen_at", JSONL.seconds(seenAt)),
            ("address", JSONL.string(address)),
            ("name", JSONL.optionalString(name)),
            ("rssi", JSONL.int(rssi)),
            ("manufacturer_data", JSONL.object(manufacturer)),
            ("service_uuids", JSONL.array(serviceUUIDs.map { JSONL.string($0) })),
            ("tx_power", JSONL.int(txPower)),
        ]
        if !serviceData.isEmpty {
            let entries = serviceData.keys.sorted().map { key -> (String, String) in
                (key, JSONL.string(JSONL.hex(serviceData[key] ?? [])))
            }
            fields.append(("service_data", JSONL.object(entries)))
        }
        if let connectable = isConnectable {
            fields.append(("connectable",
                           connectable ? "true" : "false"))
        }
        return JSONL.object(fields)
    }
}
