import CoreBluetooth
import CryptoKit
import Foundation

/// Brush pass: the proximity dead drop.
///
/// The GATT host already serves its armed payload to anyone
/// who reads FFF1 — that read path is the drop. A host phone
/// seals a short message with the pairing key and arms the
/// host with the sealed bytes; the bytes are public to anyone
/// in BLE range and meaningless to all of them, because only
/// the pairing key opens the box.
///
/// The visitor is the missing half and lives here: armed by
/// the operator, it scans for a nightjar GATT host, connects,
/// reads the payload, and hands it up to be opened. One pickup
/// per arming — a drop is an event, not a feed — and an
/// identical payload re-read within the hour is recognized
/// as the same drop, not filed twice.
final class BrushVisitor: NSObject, ObservableObject {
    @Published private(set) var hunting = false
    @Published private(set) var status = "idle"
    /// Return true when the payload opened as a brush drop.
    var onPayload: ((Data) -> Bool)?

    private var central: CBCentralManager?
    private var candidate: CBPeripheral?
    private var deadline: Timer?

    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self,
                                       queue: .main)
        }
        hunting = true
        status = L("hunting — walk within BLE range of the host")
        deadline?.invalidate()
        deadline = Timer.scheduledTimer(
            withTimeInterval: 120, repeats: false) { [weak self] _ in
            guard let self = self, self.hunting else { return }
            self.stop()
            self.status = L("no drop found in two minutes — stood down")
        }
        if central?.state == .poweredOn { beginScan() }
    }

    func stop() {
        deadline?.invalidate()
        deadline = nil
        central?.stopScan()
        if let candidate = candidate {
            central?.cancelPeripheralConnection(candidate)
        }
        candidate = nil
        hunting = false
        if status == L("hunting — walk within BLE range of the host") { status = "idle" }
    }

    private func beginScan() {
        central?.scanForPeripherals(
            withServices: [Mouth.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey:
                      false])
    }

    private func finish(_ message: String) {
        deadline?.invalidate()
        deadline = nil
        central?.stopScan()
        if let candidate = candidate {
            central?.cancelPeripheralConnection(candidate)
        }
        candidate = nil
        hunting = false
        status = message
    }
}

extension BrushVisitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(
        _ central: CBCentralManager) {
        if central.state == .poweredOn, hunting {
            beginScan()
        } else if central.state != .poweredOn, hunting {
            status = L("Bluetooth is not ready")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard candidate == nil else { return }
        candidate = peripheral
        peripheral.delegate = self
        central.stopScan()
        status = L("found a nightjar host — connecting")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Mouth.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        finish(L("the host would not connect — stood down"))
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral:
                        CBPeripheral, error: Error?) {
        if hunting, candidate != nil {
            finish(L("the host dropped the connection"))
        }
    }
}

extension BrushVisitor: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(
            where: { $0.uuid == Mouth.serviceUUID })
        else {
            finish(L("that host carries no nightjar service"))
            return
        }
        peripheral.discoverCharacteristics([Mouth.charUUID],
                                           for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service:
                    CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(
            where: { $0.uuid == Mouth.charUUID })
        else {
            finish(L("that host has no drop slot"))
            return
        }
        status = L("reading the drop")
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic:
                    CBCharacteristic, error: Error?) {
        guard let value = characteristic.value, !value.isEmpty
        else {
            finish(L("the host's drop slot is empty"))
            return
        }
        // The same drop, re-read inside the hour, is the same
        // event — not a second delivery.
        let hash = SHA256.hash(data: value)
            .map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "brushLastHash") == hash,
           Date().timeIntervalSince1970
            - defaults.double(forKey: "brushLastAt") < 3600 {
            finish(L("same drop as last time — already filed"))
            return
        }
        let opened = onPayload?(value) ?? false
        if opened {
            defaults.set(hash, forKey: "brushLastHash")
            defaults.set(Date().timeIntervalSince1970,
                         forKey: "brushLastAt")
            finish(L("drop opened — filed in the Brush thread"))
        } else {
            finish(L("read a payload that does not open with your pairing key — not a drop for you"))
        }
    }
}
