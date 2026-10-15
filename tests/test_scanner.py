import asyncio
import unittest
from types import SimpleNamespace

from nightjar.scanner import ScanOutcome, _address_type, _to_sighting, run_scan


class FakeAdvertisement:
    def __init__(self, **kw):
        self.local_name = kw.get("local_name")
        self.rssi = kw.get("rssi", -60)
        self.manufacturer_data = kw.get("manufacturer_data", {})
        self.service_uuids = kw.get("service_uuids", [])
        self.service_data = kw.get("service_data", {})
        self.tx_power = kw.get("tx_power")


class ToSightingTests(unittest.TestCase):
    def test_fields_are_copied_and_normalized(self):
        device = SimpleNamespace(address="CA:BB:CC:DD:EE:FF", name="Cached Name",
                                 details={"props": {"AddressType": "random"}})
        adv = FakeAdvertisement(
            local_name=None, rssi=-61,
            manufacturer_data={76: bytearray(b"\x12\x02\x10\x00")},
            service_uuids=["0000FEAA-0000-1000-8000-00805F9B34FB"],
            service_data={"0000FEAA-0000-1000-8000-00805F9B34FB": bytearray(b"\x40")},
            tx_power=4)
        sighting = _to_sighting(device, adv)
        self.assertEqual(sighting.address, "CA:BB:CC:DD:EE:FF")
        self.assertEqual(sighting.name, "Cached Name")  # device name as fallback
        self.assertEqual(sighting.rssi, -61)
        self.assertEqual(sighting.manufacturer_data, {76: b"\x12\x02\x10\x00"})
        self.assertEqual(sighting.service_uuids, ["0000feaa-0000-1000-8000-00805f9b34fb"])
        self.assertEqual(sighting.service_data,
                         {"0000feaa-0000-1000-8000-00805f9b34fb": b"\x40"})
        self.assertEqual(sighting.tx_power, 4)
        self.assertEqual(sighting.address_type, "random")
        self.assertEqual(sighting.address_kind, "random static")

    def test_local_name_wins_and_rssi_falls_back_to_device(self):
        device = SimpleNamespace(address="AA:BB", name="Cached", rssi=-70, details=None)
        adv = FakeAdvertisement(local_name="Live Name", rssi=None)
        sighting = _to_sighting(device, adv)
        self.assertEqual(sighting.name, "Live Name")
        self.assertEqual(sighting.rssi, -70)
        self.assertIsNone(sighting.address_type)


class AddressTypeTests(unittest.TestCase):
    def test_bluez_props(self):
        device = SimpleNamespace(details={"props": {"AddressType": "public"}})
        self.assertEqual(_address_type(device), "public")

    def test_winrt_style_enum(self):
        adv = SimpleNamespace(bluetooth_address_type=SimpleNamespace(value=1))
        device = SimpleNamespace(details=SimpleNamespace(adv=adv))
        self.assertEqual(_address_type(device), "random")
        self.assertIsNone(_address_type(SimpleNamespace(details=SimpleNamespace(adv=None))))

    def test_garbage_is_none(self):
        self.assertIsNone(_address_type(SimpleNamespace(details=42)))
        self.assertIsNone(_address_type(SimpleNamespace()))


class RunScanTests(unittest.TestCase):
    def test_simulated_scan_reports_its_mode(self):
        seen = []
        started = []
        outcome = asyncio.run(run_scan(0.3, seen.append, simulate=True, seed=1,
                                       on_start=started.append))
        self.assertIsInstance(outcome, ScanOutcome)
        self.assertEqual(outcome.mode, "simulated")
        self.assertEqual(started[0].mode, "simulated")
        self.assertGreater(len(seen), 0)

    def test_unknown_mode_is_rejected(self):
        with self.assertRaises(ValueError):
            asyncio.run(run_scan(0.1, lambda s: None, simulate=True, mode="sideways"))


if __name__ == "__main__":
    unittest.main()
