import random
import unittest

from nightjar.identify import (
    RANK_FAMILY_HINT,
    RANK_PRODUCT,
    IdentityResolver,
    classify,
    kind_of,
)
from nightjar.simulate import PROFILES, random_sighting

from .helpers import (
    AIRPODS_PRO,
    AIRTAG_SEPARATED,
    AIRTAG_WITH_OWNER,
    APPLE,
    EDDYSTONE_UUID,
    EXPOSURE_UUID,
    FMDN_FRAME,
    IPHONE_NEARBY,
    TILE_UUID,
    sighting,
)


class ClassifyTests(unittest.TestCase):
    def test_apple_payload_wins(self):
        result = classify(sighting(manufacturer_data={APPLE: AIRPODS_PRO},
                                   service_uuids=[TILE_UUID]))
        self.assertEqual(result.kind, "AirPods Pro")
        self.assertEqual(result.rank, RANK_PRODUCT)
        self.assertFalse(result.tracker_shaped)

    def test_findmy_separated_is_tracker_shaped(self):
        result = classify(sighting(manufacturer_data={APPLE: AIRTAG_SEPARATED}))
        self.assertTrue(result.tracker_shaped)
        self.assertTrue(result.findmy.separated)
        with_owner = classify(sighting(manufacturer_data={APPLE: AIRTAG_WITH_OWNER}))
        self.assertFalse(with_owner.tracker_shaped)

    def test_service_data_beats_generic_manufacturer_data(self):
        result = classify(sighting(manufacturer_data={0x0087: b"\x01"},
                                   service_uuids=[EDDYSTONE_UUID],
                                   service_data={EDDYSTONE_UUID: FMDN_FRAME}))
        self.assertEqual(result.kind, "Find My Device network tag (Google)")
        self.assertTrue(result.tracker_shaped)

    def test_vendor_beats_vague_services(self):
        result = classify(sighting(manufacturer_data={0x0087: b"\x01"},
                                   service_uuids=["180f"]))
        self.assertEqual(result.kind, "Garmin device")

    def test_named_and_unknown(self):
        self.assertEqual(classify(sighting(name="Printer")).kind, "Named device")
        self.assertEqual(classify(sighting()).kind, "Unknown device")
        swift = sighting(manufacturer_data={0x0006: bytes.fromhex("03060800")})
        self.assertEqual(kind_of(swift)[0], "Windows device (Swift Pair)")

    def test_nearby_info_hint_rank(self):
        result = classify(sighting(manufacturer_data={APPLE: IPHONE_NEARBY}))
        self.assertEqual(result.kind, "Apple device (Nearby Info)")
        self.assertEqual(result.rank, RANK_FAMILY_HINT)


class IdentityTests(unittest.TestCase):
    def test_rotating_phone_folds_into_one_identity(self):
        resolver = IdentityResolver()
        for i in range(6):
            resolver.observe(sighting(
                f"11:22:33:44:55:{i:02X}", 1000.0 + i,
                manufacturer_data={APPLE: IPHONE_NEARBY}))
        self.assertEqual(len(resolver), 1)
        identity = resolver.identities[0]
        self.assertEqual(len(identity.addresses), 6)
        self.assertEqual(identity.basis, "payload fingerprint")
        self.assertEqual(identity.sightings, 6)
        self.assertTrue(identity.rotates)
        self.assertEqual(identity.rotation_note(), "6 addresses (rotates)")

    def test_distinct_devices_stay_distinct(self):
        resolver = IdentityResolver()
        resolver.observe(sighting("AA:01", 1000.0, name="AirPods Pro",
                                  manufacturer_data={APPLE: b"\x07\x19"}))
        resolver.observe(sighting("BB:02", 1001.0, service_uuids=[TILE_UUID]))
        self.assertEqual(len(resolver), 2)

    def test_named_sightings_key_by_name_and_fingerprint(self):
        resolver = IdentityResolver()
        for i in range(3):
            resolver.observe(sighting(f"AA:0{i}", 1000.0 + i, name="Chase's Watch",
                                      manufacturer_data={APPLE: IPHONE_NEARBY}))
        self.assertEqual(len(resolver), 1)
        self.assertEqual(resolver.identities[0].basis, "name + fingerprint")
        self.assertEqual(resolver.identities[0].label, "Chase's Watch")

    def test_an_address_sticks_to_its_first_identity(self):
        # The same address answers once with a name (scan response) and
        # once without: still one device.
        resolver = IdentityResolver()
        first = resolver.observe(sighting("AA:01", 1000.0, name="AirPods Pro",
                                          manufacturer_data={APPLE: AIRPODS_PRO}))
        second = resolver.observe(sighting("AA:01", 1001.0,
                                           manufacturer_data={APPLE: AIRPODS_PRO}))
        self.assertIs(first, second)
        self.assertEqual(len(resolver), 1)
        self.assertIs(resolver.for_address("AA:01"), first)

    def test_kind_upgrades_to_the_most_specific(self):
        resolver = IdentityResolver()
        resolver.observe(sighting("AA:01", 1000.0, name="Thing"))
        identity = resolver.observe(sighting("AA:01", 1001.0, name="Thing",
                                             manufacturer_data={APPLE: b"\x0c\x01\x00"}))
        self.assertEqual(identity.kind, "Apple device")
        identity = resolver.observe(sighting("AA:01", 1002.0, name="Thing",
                                             manufacturer_data={APPLE: AIRPODS_PRO}))
        self.assertEqual(identity.kind, "AirPods Pro")
        # A later, vaguer sighting doesn't demote it.
        identity = resolver.observe(sighting("AA:01", 1003.0, name="Thing",
                                             manufacturer_data={APPLE: b"\x0c\x01\x00"}))
        self.assertEqual(identity.kind, "AirPods Pro")
        self.assertEqual(identity.headline, "Thing (AirPods Pro)")

    def test_tracker_like_classification(self):
        resolver = IdentityResolver()
        tile = resolver.observe(sighting("BB:02", 1001.0, service_uuids=[TILE_UUID]))
        pods = resolver.observe(sighting("AA:01", 1002.0, name="AirPods Pro"))
        fmdn = resolver.observe(sighting("CC:03", 1003.0, service_uuids=[EDDYSTONE_UUID],
                                         service_data={EDDYSTONE_UUID: FMDN_FRAME}))
        phone = resolver.observe(sighting("DD:04", 1004.0, service_uuids=[EXPOSURE_UUID],
                                          service_data={EXPOSURE_UUID: bytes(20)}))
        self.assertTrue(tile.tracker_like)
        self.assertFalse(pods.tracker_like)
        self.assertTrue(fmdn.tracker_like)
        self.assertFalse(phone.tracker_like)

    def test_findmy_identity_is_tracker_like_only_when_separated(self):
        resolver = IdentityResolver()
        separated = resolver.observe(sighting(
            "E7:04", 1000.0, manufacturer_data={APPLE: AIRTAG_SEPARATED}))
        self.assertTrue(separated.findmy)
        self.assertTrue(separated.tracker_like)
        self.assertEqual(separated.kind, "Find My device (AirTag-class)")
        with_owner = resolver.observe(sighting(
            "F2:19", 1000.0, manufacturer_data={APPLE: AIRTAG_WITH_OWNER}))
        self.assertTrue(with_owner.findmy_with_owner)
        self.assertFalse(with_owner.tracker_like)

    def test_address_kinds_mark_private_addresses(self):
        resolver = IdentityResolver()
        identity = resolver.observe(sighting("7B:00:00:00:00:01", 1000.0,
                                             address_type="random"))
        self.assertIn("random resolvable", identity.address_kinds)
        self.assertTrue(identity.rotates)
        self.assertEqual(identity.rotation_note(), "private address (rotates)")

    def test_matches(self):
        resolver = IdentityResolver()
        identity = resolver.observe(sighting("D4:61:0A:BE:37:52", 1000.0,
                                             service_uuids=[TILE_UUID]))
        self.assertTrue(identity.matches("d4:61"))
        self.assertTrue(identity.matches("tile"))
        self.assertTrue(identity.matches(identity.key))
        self.assertFalse(identity.matches("airpods"))
        self.assertFalse(identity.matches(""))

    def test_to_dict_is_json_ready(self):
        import json
        resolver = IdentityResolver()
        identity = resolver.observe(sighting("AA:01", 1000.0,
                                             manufacturer_data={APPLE: AIRPODS_PRO}))
        doc = identity.to_dict()
        json.dumps(doc)
        self.assertEqual(doc["kind"], "AirPods Pro")
        self.assertEqual(doc["addresses"], ["AA:01"])
        json.dumps(resolver.to_dict())

    def test_simulated_neighbourhood_resolves_to_few_identities(self):
        rng = random.Random(11)
        resolver = IdentityResolver()
        for _ in range(300):
            resolver.observe(random_sighting(rng))
        # Profiles with rotating addresses number in the dozens by address,
        # but identities stay one per profile.
        self.assertLessEqual(len(resolver), len(PROFILES))
        by_signal = resolver.by_signal()
        self.assertEqual(len(by_signal), len(resolver))


if __name__ == "__main__":
    unittest.main()
