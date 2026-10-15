import json
import unittest

from nightjar.registry import Registry, Sighting, company_name


def sighting(address="AA:BB:CC:DD:EE:FF", when=1000.0, **kw):
    defaults = dict(name=None, rssi=-60, manufacturer_data={}, service_uuids=[])
    defaults.update(kw)
    return Sighting(address=address, seen_at=when, **defaults)


class RegistryTests(unittest.TestCase):
    def test_new_device_is_flagged_once(self):
        reg = Registry()
        _, first = reg.observe(sighting())
        _, second = reg.observe(sighting())
        self.assertTrue(first)
        self.assertFalse(second)
        self.assertEqual(len(reg), 1)

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

    def test_distinct_addresses_are_distinct_devices(self):
        reg = Registry()
        reg.observe(sighting(address="AA:AA"))
        reg.observe(sighting(address="BB:BB"))
        self.assertEqual(len(reg), 2)
        self.assertEqual(reg.total_sightings, 2)

    def test_to_dict_is_json_serializable(self):
        reg = Registry()
        reg.observe(sighting(manufacturer_data={0x004C: b"\x01\x02"},
                             service_uuids=["feed"]))
        json.dumps(reg.to_dict())  # must not raise

    def test_company_name_fallback(self):
        self.assertEqual(company_name(0x004C), "Apple")
        self.assertEqual(company_name(0xBEEF), "0xBEEF")


if __name__ == "__main__":
    unittest.main()
