import unittest

from nightjar.services import (
    TRACKER_SERVICE_UUIDS,
    decode_eddystone,
    decode_fast_pair,
    describe_uuid,
    identify_services,
    normalize_uuid,
    service_name,
    short_uuid,
)

from .helpers import (
    EDDYSTONE_UUID,
    EXPOSURE_UUID,
    FAST_PAIR_UUID,
    FMDN_FRAME,
    SMARTTHINGS_UUID,
    TILE_UUID,
)


class UuidTests(unittest.TestCase):
    def test_short_forms_expand(self):
        self.assertEqual(normalize_uuid("FEAA"), EDDYSTONE_UUID)
        self.assertEqual(normalize_uuid("0xfeaa"), EDDYSTONE_UUID)
        self.assertEqual(normalize_uuid("0000FEAA-0000-1000-8000-00805F9B34FB"),
                         EDDYSTONE_UUID)

    def test_short_uuid_only_for_sig_base(self):
        self.assertEqual(short_uuid(TILE_UUID), 0xFEED)
        self.assertIsNone(short_uuid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"))

    def test_names_and_descriptions(self):
        self.assertEqual(service_name("180d"), "Heart Rate")
        self.assertEqual(describe_uuid("180d"), "Heart Rate (0x180d)")
        self.assertEqual(describe_uuid("abcd"), "0xabcd")
        self.assertIsNone(service_name("6e400001-b5a3-f393-e0a9-e50e24dcca9e"))
        self.assertIn(TILE_UUID, TRACKER_SERVICE_UUIDS)
        self.assertIn(SMARTTHINGS_UUID, TRACKER_SERVICE_UUIDS)


class EddystoneTests(unittest.TestCase):
    def test_uid_frame(self):
        payload = bytes([0x00, 0xEE]) + bytes(range(10)) + bytes(range(6)) + bytes(2)
        frame = decode_eddystone(payload)
        self.assertEqual(frame.frame_name, "UID")
        self.assertEqual(frame.tx_power, -18)
        self.assertEqual(frame.namespace, "00010203040506070809")
        self.assertEqual(frame.instance, "000102030405")

    def test_url_frame_expands_prefixes(self):
        payload = bytes([0x10, 0xF0, 0x03]) + b"example" + bytes([0x07]) + b"/x"
        frame = decode_eddystone(payload)
        self.assertEqual(frame.url, "https://example.com/x")
        self.assertEqual(frame.describe(), "Eddystone-URL https://example.com/x")

    def test_tlm_frame(self):
        payload = (bytes([0x20, 0x00]) + (3000).to_bytes(2, "big")
                   + (22 * 256 + 128).to_bytes(2, "big")
                   + (12345).to_bytes(4, "big") + (36000).to_bytes(4, "big"))
        frame = decode_eddystone(payload)
        self.assertEqual(frame.battery_mv, 3000)
        self.assertAlmostEqual(frame.temperature_c, 22.5)
        self.assertEqual(frame.adv_count, 12345)
        self.assertEqual(frame.uptime_s, 3600.0)
        self.assertIn("22.5 °C", frame.describe())

    def test_fmdn_frames_are_trackers(self):
        frame = decode_eddystone(FMDN_FRAME)
        self.assertTrue(frame.is_fmdn)
        self.assertEqual(frame.eid, FMDN_FRAME[1:].hex())
        ident = identify_services([EDDYSTONE_UUID], {EDDYSTONE_UUID: FMDN_FRAME})
        self.assertTrue(ident.tracker_shaped)
        self.assertEqual(ident.kind, "Find My Device network tag (Google)")

    def test_unknown_frame_is_presence_only(self):
        frame = decode_eddystone(bytes([0x50, 0x01]))
        self.assertEqual(frame.frame_name, "frame 0x50")
        self.assertIsNone(decode_eddystone(b""))


class FastPairTests(unittest.TestCase):
    def test_discoverable_model_id(self):
        state = decode_fast_pair(bytes([0x2D, 0x7A, 0x23]))
        self.assertTrue(state.discoverable)
        self.assertEqual(state.model_id, 0x2D7A23)
        self.assertIn("model 0x2D7A23", state.describe())

    def test_account_key_filter_is_not_discoverable(self):
        state = decode_fast_pair(bytes([0x00, 0x62]) + bytes(12))
        self.assertFalse(state.discoverable)
        ident = identify_services([FAST_PAIR_UUID], {FAST_PAIR_UUID: bytes(8)})
        self.assertEqual(ident.kind, "Fast Pair device (Google)")
        self.assertFalse(ident.tracker_shaped)


class IdentifyServicesTests(unittest.TestCase):
    def test_tile_and_smartthings_are_tracker_shaped(self):
        self.assertTrue(identify_services([TILE_UUID], {}).tracker_shaped)
        self.assertEqual(identify_services([TILE_UUID], {}).kind, "Tile tracker")
        self.assertTrue(identify_services([SMARTTHINGS_UUID], {}).tracker_shaped)

    def test_exposure_notification_is_a_rotating_phone(self):
        ident = identify_services([EXPOSURE_UUID], {EXPOSURE_UUID: bytes(20)})
        self.assertTrue(ident.rotating_phone)
        self.assertFalse(ident.tracker_shaped)
        self.assertEqual(ident.kind, "Phone (Exposure Notification)")

    def test_known_gatt_services_are_named(self):
        ident = identify_services(["180d", "180f"], {})
        self.assertEqual(ident.kind, "Device advertising Battery, Heart Rate")
        self.assertEqual(ident.specificity, 1)

    def test_nothing_recognizable_is_none(self):
        self.assertIsNone(identify_services([], {}))
        self.assertIsNone(identify_services(["6e400001-b5a3-f393-e0a9-e50e24dcca9e"], {}))


if __name__ == "__main__":
    unittest.main()
