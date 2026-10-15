import json
import unittest

from nightjar.registry import (
    Registry,
    Sighting,
    SignalTrack,
    address_kind,
    company_name,
)

from .helpers import sighting


class RegistryTests(unittest.TestCase):
    def test_new_device_is_flagged_once(self):
        reg = Registry()
        _, first = reg.observe(sighting())
        _, second = reg.observe(sighting())
        self.assertTrue(first)
        self.assertFalse(second)
        self.assertEqual(len(reg), 1)
        self.assertIsNotNone(reg.get("AA:BB:CC:DD:EE:FF"))

    def test_record_accumulates(self):
        reg = Registry()
        reg.observe(sighting(when=1000.0, rssi=-80, name=None))
        record, _ = reg.observe(
            sighting(when=1010.0, rssi=-50, name="AirPods Pro",
                     manufacturer_data={0x004C: b"\x10\x05"})
        )
        self.assertEqual(record.sightings, 2)
        self.assertEqual(record.first_seen, 1000.0)
        self.assertEqual(record.last_seen, 1010.0)
        self.assertEqual(record.rssi_last, -50)
        self.assertEqual(record.rssi_closest, -50)  # strongest wins
        self.assertEqual(record.name, "AirPods Pro")
        self.assertEqual(record.companies, ["Apple"])
        self.assertEqual(record.rssi_history, [(1000.0, -80), (1010.0, -50)])

    def test_distinct_addresses_are_distinct_devices(self):
        reg = Registry()
        reg.observe(sighting(address="AA:AA"))
        reg.observe(sighting(address="BB:BB"))
        self.assertEqual(len(reg), 2)
        self.assertEqual(reg.total_sightings, 2)
        self.assertEqual({r.address for r in reg}, {"AA:AA", "BB:BB"})

    def test_to_dict_is_json_serializable(self):
        reg = Registry()
        reg.observe(sighting(manufacturer_data={0x004C: b"\x01\x02"},
                             service_uuids=["feed"]))
        doc = reg.to_dict()
        json.dumps(doc)  # must not raise
        self.assertEqual(doc["device_count"], 1)
        self.assertIn("rssi_median", doc["devices"][0])

    def test_company_name_fallback(self):
        self.assertEqual(company_name(0x004C), "Apple")
        self.assertEqual(company_name(0xBEEF), "0xBEEF")


class SightingTests(unittest.TestCase):
    def test_round_trip_keeps_service_data_and_address_type(self):
        original = sighting(
            manufacturer_data={0x004C: b"\x12\x02\x10\x00"},
            service_uuids=["0000FEAA-0000-1000-8000-00805F9B34FB"],
            service_data={"0000feaa-0000-1000-8000-00805f9b34fb": b"\x40\x01"},
            tx_power=-4, address_type="random")
        rec = original.to_dict()
        self.assertEqual(rec["service_data"],
                         {"0000feaa-0000-1000-8000-00805f9b34fb": "4001"})
        self.assertEqual(rec["address_type"], "random")
        back = Sighting.from_dict(json.loads(json.dumps(rec)))
        self.assertEqual(back.manufacturer_data, original.manufacturer_data)
        self.assertEqual(back.service_data, original.service_data)
        self.assertEqual(back.tx_power, -4)
        self.assertEqual(back.address_type, "random")

    def test_legacy_records_without_new_fields_load(self):
        rec = {"type": "sighting", "seen_at": 1.5, "address": "AA:BB",
               "name": None, "rssi": -60, "manufacturer_data": {"76": "0a"},
               "service_uuids": [], "tx_power": None}
        back = Sighting.from_dict(rec)
        self.assertEqual(back.service_data, {})
        self.assertIsNone(back.address_type)
        self.assertEqual(back.manufacturer_data, {76: b"\x0a"})
        self.assertNotIn("service_data", back.to_dict())

    def test_corrupt_payloads_are_dropped_not_fatal(self):
        rec = {"address": "AA:BB", "manufacturer_data": {"76": "zz", "6": "01"}}
        back = Sighting.from_dict(rec)
        self.assertEqual(back.manufacturer_data, {6: b"\x01"})


class AddressKindTests(unittest.TestCase):
    def test_random_subtypes_from_the_top_bits(self):
        self.assertEqual(address_kind("C1:00:00:00:00:00", "random"), "random static")
        self.assertEqual(address_kind("7B:00:00:00:00:00", "random"), "random resolvable")
        self.assertEqual(address_kind("3B:00:00:00:00:00", "random"),
                         "random non-resolvable")
        self.assertEqual(address_kind("AA:BB", "public"), "public")
        self.assertIsNone(address_kind("778F707E-A2F9-1661-F38D-75A6A13CFCB5", None))
        self.assertEqual(address_kind("not-a-mac", "random"), "random")


class SignalTrackTests(unittest.TestCase):
    def test_history_is_capped_and_median_works(self):
        track = SignalTrack()
        for i in range(300):
            track.observe(float(i), -90 + (i % 40))
        self.assertEqual(len(track.history), SignalTrack.CAP)
        self.assertEqual(track.closest, -51)
        self.assertEqual(track.last, -90 + (299 % 40))
        self.assertIsNotNone(track.median())
        self.assertIsNone(SignalTrack().median())

    def test_none_rssi_is_ignored(self):
        track = SignalTrack()
        track.observe(1.0, None)
        self.assertEqual(track.history, [])
        self.assertIsNone(track.last)


if __name__ == "__main__":
    unittest.main()
