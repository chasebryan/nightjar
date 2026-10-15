import random
import unittest

from nightjar.identify import IdentityResolver, kind_of
from nightjar.registry import Sighting
from nightjar.simulate import PROFILES, random_sighting

APPLE = 0x004C
IPHONE_PAYLOAD = next(
    p.manufacturer_data[APPLE] for p in PROFILES
    if p.rotates and APPLE in p.manufacturer_data
)
TILE_UUID = "0000feed-0000-1000-8000-00805f9b34fb"


def sighting(address, when, **kw):
    base = dict(name=None, rssi=-60, manufacturer_data={}, service_uuids=[])
    base.update(kw)
    return Sighting(address=address, seen_at=when, **base)


class IdentityTests(unittest.TestCase):
    def test_rotating_phone_folds_into_one_identity(self):
        resolver = IdentityResolver()
        for i in range(6):
            resolver.observe(sighting(
                f"11:22:33:44:55:{i:02X}", 1000.0 + i,
                manufacturer_data={APPLE: IPHONE_PAYLOAD}))
        self.assertEqual(len(resolver), 1)
        identity = resolver.identities[0]
        self.assertEqual(len(identity.addresses), 6)
        self.assertEqual(identity.basis, "payload fingerprint")
        self.assertEqual(identity.sightings, 6)

    def test_distinct_devices_stay_distinct(self):
        resolver = IdentityResolver()
        resolver.observe(sighting("AA:01", 1000.0, name="AirPods Pro",
                                  manufacturer_data={APPLE: b"\x07\x19"}))
        resolver.observe(sighting("BB:02", 1001.0,
                                  service_uuids=[TILE_UUID]))
        self.assertEqual(len(resolver), 2)

    def test_tracker_like_classification(self):
        resolver = IdentityResolver()
        tile = resolver.observe(sighting("BB:02", 1001.0,
                                         service_uuids=[TILE_UUID]))
        pods = resolver.observe(sighting("AA:01", 1002.0, name="AirPods Pro"))
        self.assertTrue(tile.tracker_like)
        self.assertFalse(pods.tracker_like)

    def test_kind_of_swift_pair(self):
        kind, _ = kind_of(sighting("CC:03", 1000.0, manufacturer_data={
            0x0006: bytes.fromhex("03060800")}))
        self.assertEqual(kind, "Windows device (Swift Pair)")

    def test_simulated_neighbourhood_resolves_to_few_identities(self):
        rng = random.Random(11)
        resolver = IdentityResolver()
        for _ in range(300):
            resolver.observe(random_sighting(rng))
        # 5 profiles, one rotating: addresses number in the dozens,
        # identities stay in single digits.
        self.assertLessEqual(len(resolver), len(PROFILES) + 1)


if __name__ == "__main__":
    unittest.main()
