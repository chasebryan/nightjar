import unittest

from nightjar.continuity import (
    decode_airpods, decode_ibeacon, decode_nearby_info, identify_apple,
    parse_continuity, parse_findmy,
)
from nightjar.simulate import PROFILES

APPLE = 0x004C


def airtag_payload():
    for profile in PROFILES:
        data = profile.manufacturer_data.get(APPLE)
        if data and data[0] == 0x12:
            return data
    raise AssertionError("simulate lost its AirTag profile")


def airpods_payload():
    for profile in PROFILES:
        data = profile.manufacturer_data.get(APPLE)
        if data and data[0] == 0x07:
            return data
    raise AssertionError("simulate lost its AirPods profile")


class ContinuityTests(unittest.TestCase):
    def test_tlv_chain_parses_multiple_messages(self):
        payload = bytes([0x0F, 0x02, 0xAA, 0xBB, 0x10, 0x01, 0x7F])
        messages = parse_continuity(payload)
        self.assertEqual([m.type_id for m in messages], [0x0F, 0x10])
        self.assertEqual(messages[0].value, bytes([0xAA, 0xBB]))

    def test_truncated_tail_is_dropped(self):
        messages = parse_continuity(bytes([0x0F, 0x05, 0x01]))
        self.assertEqual(messages, [])

    def test_airpods_decode_from_simulated_payload(self):
        (message,) = parse_continuity(airpods_payload())
        state = decode_airpods(message)
        self.assertIsNotNone(state)
        self.assertEqual(state.model, "AirPods Pro")
        self.assertEqual(state.primary_battery, 90)
        self.assertEqual(state.secondary_battery, 80)
        self.assertEqual(state.case_battery, 70)
        self.assertTrue(state.primary_in_ear)
        self.assertTrue(state.lid_open)

    def test_ibeacon_decode(self):
        raw = bytes(range(16))
        payload = bytes([0x02, 0x15]) + raw + bytes([0x00, 0x07, 0x01, 0x02, 0xC5])
        (message,) = parse_continuity(payload)
        beacon = decode_ibeacon(message)
        self.assertEqual(beacon.major, 7)
        self.assertEqual(beacon.minor, 258)

    def test_identify_apple_names_airpods(self):
        ident = identify_apple(airpods_payload())
        self.assertEqual(ident.kind, "AirPods Pro")
        self.assertIn("Proximity Pairing", ident.messages)

    def test_findmy_format_recognized(self):
        state = parse_findmy(airtag_payload())
        self.assertIsNotNone(state)
        self.assertEqual(state.battery, "medium")  # status byte 0x50

    def test_findmy_rejects_tlv_payloads(self):
        self.assertIsNone(parse_findmy(airpods_payload()))
        self.assertIsNone(parse_findmy(b"\x12\x19"))  # too short

    def test_identify_apple_names_findmy(self):
        ident = identify_apple(airtag_payload())
        self.assertEqual(ident.kind, "Find My device (AirTag-class)")
        self.assertIn("battery medium", ident.describe())

    def test_nearby_info_state_code(self):
        payload = bytes([0x10, 0x03, 0x0A, 0x00, 0x00])
        (message,) = parse_continuity(payload)
        self.assertEqual(message.type_name, "Nearby Info")
        state = decode_nearby_info(message)
        self.assertEqual(state.action_label, "watch worn & unlocked")


if __name__ == "__main__":
    unittest.main()
