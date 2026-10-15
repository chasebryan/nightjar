import unittest

from nightjar.continuity import (
    MESSAGE_TYPES,
    NEARBY_ACTION_LABELS,
    decode_airpods,
    decode_ibeacon,
    decode_nearby_action,
    decode_nearby_info,
    decode_tethering_source,
    identify_apple,
    parse_continuity,
    parse_findmy,
)

from .helpers import AIRPODS_LEGACY, AIRPODS_PRO, AIRTAG_SEPARATED, AIRTAG_WITH_OWNER


class TlvTests(unittest.TestCase):
    def test_tlv_chain_parses_multiple_messages(self):
        payload = bytes([0x0F, 0x02, 0xAA, 0xBB, 0x10, 0x01, 0x7F])
        messages = parse_continuity(payload)
        self.assertEqual([m.type_id for m in messages], [0x0F, 0x10])
        self.assertEqual(messages[0].value, bytes([0xAA, 0xBB]))
        self.assertEqual(messages[0].type_name, "Nearby Action")

    def test_truncated_tail_is_dropped(self):
        messages = parse_continuity(bytes([0x0F, 0x05, 0x01]))
        self.assertEqual(messages, [])

    def test_message_type_table_covers_the_documented_chain(self):
        for type_id in (0x02, 0x05, 0x07, 0x0C, 0x0E, 0x0F, 0x10, 0x12):
            self.assertIn(type_id, MESSAGE_TYPES)
        self.assertEqual(MESSAGE_TYPES[0x0E], "Tethering Source")


class AirPodsTests(unittest.TestCase):
    def test_simulated_payload_not_flipped(self):
        (message,) = parse_continuity(AIRPODS_PRO)
        state = decode_airpods(message)
        self.assertIsNotNone(state)
        self.assertEqual(state.model, "AirPods Pro")
        self.assertEqual(state.model_code, "0e20")
        self.assertEqual((state.left_battery, state.right_battery), (80, 90))
        self.assertEqual(state.case_battery, 70)
        self.assertTrue(state.left_in_ear and state.right_in_ear)
        self.assertFalse(state.left_charging or state.right_charging
                         or state.case_charging)
        self.assertTrue(state.lid_open)
        self.assertEqual(state.colour, "white")
        self.assertEqual(
            state.describe(),
            "AirPods Pro: L 80% (in ear), R 90% (in ear), case 70%, lid open, white")

    def test_legacy_vector_follows_the_flipped_layout(self):
        # Status 0x03 has the 0x20 "not flipped" bit clear, so the nibbles
        # swap: right = low (80), left = high (90); case battery is the low
        # nibble of 0x70 (0%), and every charging flag in its high nibble
        # (0x7) is set.
        (message,) = parse_continuity(AIRPODS_LEGACY)
        state = decode_airpods(message)
        self.assertEqual((state.left_battery, state.right_battery), (90, 80))
        self.assertTrue(state.right_in_ear)
        self.assertFalse(state.left_in_ear)
        self.assertEqual(state.case_battery, 0)
        self.assertTrue(state.left_charging and state.right_charging
                        and state.case_charging)
        self.assertTrue(state.lid_open)
        # The old primary/secondary names still resolve (right, left).
        self.assertEqual(state.primary_battery, 80)
        self.assertEqual(state.secondary_battery, 90)

    def test_unknown_battery_nibble_is_none(self):
        value = bytes([0x01, 0x0E, 0x20, 0x20, 0xFF, 0x0F, 0x00, 0x05]) + bytes(17)
        (message,) = parse_continuity(bytes([0x07, len(value)]) + value)
        state = decode_airpods(message)
        self.assertIsNone(state.left_battery)
        self.assertIsNone(state.right_battery)
        self.assertIsNone(state.case_battery)
        self.assertEqual(state.colour, "gray")
        self.assertFalse(state.lid_open)

    def test_unknown_model_is_reported_by_code(self):
        value = bytes([0x01, 0xAB, 0xCD, 0x20, 0x55, 0x05, 0x00, 0x00]) + bytes(17)
        (message,) = parse_continuity(bytes([0x07, len(value)]) + value)
        self.assertEqual(decode_airpods(message).model, "AirPods-class (model abcd)")

    def test_short_value_is_rejected(self):
        self.assertIsNone(decode_airpods(parse_continuity(b"\x07\x03\x01\x0e\x20")[0]))

    def test_identify_apple_names_airpods(self):
        ident = identify_apple(AIRPODS_PRO)
        self.assertEqual(ident.kind, "AirPods Pro")
        self.assertEqual(ident.specificity, 3)
        self.assertIn("Proximity Pairing", ident.messages)


class IBeaconTests(unittest.TestCase):
    def test_ibeacon_decode_with_measured_power(self):
        raw = bytes(range(16))
        payload = bytes([0x02, 0x15]) + raw + bytes([0x00, 0x07, 0x01, 0x02, 0xC5])
        (message,) = parse_continuity(payload)
        beacon = decode_ibeacon(message)
        self.assertEqual(beacon.major, 7)
        self.assertEqual(beacon.minor, 258)
        self.assertEqual(beacon.measured_power, -59)
        self.assertEqual(beacon.proximity_uuid, "00010203-0405-0607-0809-0a0b0c0d0e0f")
        self.assertIn("-59 dBm @ 1 m", beacon.describe())
        self.assertEqual(identify_apple(payload).kind, "iBeacon")


class FindMyTests(unittest.TestCase):
    def test_separated_format_recognized(self):
        state = parse_findmy(AIRTAG_SEPARATED)
        self.assertIsNotNone(state)
        self.assertTrue(state.separated)
        self.assertEqual(state.battery, "medium")  # status byte 0x50
        self.assertIn("separated from owner", state.describe())

    def test_battery_lives_in_the_top_two_bits(self):
        for status, expected in ((0x10, "full"), (0x50, "medium"),
                                 (0x90, "low"), (0xD0, "very low"),
                                 (0x00, "full"), (0x7F, "medium")):
            payload = bytes([0x12, 0x19, status]) + bytes(24)
            self.assertEqual(parse_findmy(payload).battery, expected, hex(status))

    def test_with_owner_format_recognized(self):
        state = parse_findmy(AIRTAG_WITH_OWNER)
        self.assertIsNotNone(state)
        self.assertFalse(state.separated)
        ident = identify_apple(AIRTAG_WITH_OWNER)
        self.assertEqual(ident.kind, "Find My accessory (with owner)")

    def test_findmy_rejects_tlv_payloads(self):
        self.assertIsNone(parse_findmy(AIRPODS_PRO))
        self.assertIsNone(parse_findmy(b"\x12\x19"))  # too short

    def test_identify_apple_names_findmy(self):
        ident = identify_apple(AIRTAG_SEPARATED)
        self.assertEqual(ident.kind, "Find My device (AirTag-class)")
        self.assertIn("battery medium", ident.describe())
        self.assertTrue(ident.findmy.separated)


class NearbyTests(unittest.TestCase):
    def test_nearby_info_state_code(self):
        payload = bytes([0x10, 0x03, 0x0A, 0x00, 0x00])
        (message,) = parse_continuity(payload)
        self.assertEqual(message.type_name, "Nearby Info")
        state = decode_nearby_info(message)
        self.assertEqual(state.action_label, "watch worn & unlocked")
        self.assertTrue(state.is_watch)
        self.assertEqual(identify_apple(payload).kind, "Apple Watch")

    def test_action_code_is_the_low_nibble(self):
        (message,) = parse_continuity(bytes([0x10, 0x05, 0x1A, 0x1C, 0x01, 0x02, 0x03]))
        state = decode_nearby_info(message)
        self.assertEqual(state.action_code, 0x0A)
        self.assertEqual(state.status_flags, 0x1)
        self.assertEqual(state.data_flags, 0x1C)

    def test_only_verified_codes_are_labelled(self):
        self.assertEqual(set(NEARBY_ACTION_LABELS), {0x0A})
        (message,) = parse_continuity(bytes([0x10, 0x02, 0x03, 0x00]))
        state = decode_nearby_info(message)
        self.assertIsNone(state.action_label)
        self.assertEqual(state.describe(), "nearby state 0x03")
        self.assertEqual(identify_apple(bytes([0x10, 0x02, 0x03, 0x00])).kind,
                         "Apple device (Nearby Info)")

    def test_nearby_action_type(self):
        payload = bytes([0x0F, 0x05, 0xC0, 0x08, 0x11, 0x22, 0x33])
        (message,) = parse_continuity(payload)
        action = decode_nearby_action(message)
        self.assertEqual(action.action_type, 0x08)
        self.assertEqual(action.describe(), "nearby action: Wi-Fi password share")
        self.assertIn("Wi-Fi password share", identify_apple(payload).describe())

    def test_tethering_source(self):
        payload = bytes([0x0E, 0x05, 0x01, 0x00, 0x42, 0x01, 0x03])
        (message,) = parse_continuity(payload)
        state = decode_tethering_source(message)
        self.assertEqual(state.battery, 66)
        self.assertEqual(state.cell_bars, 3)
        ident = identify_apple(payload)
        self.assertEqual(ident.kind, "iPhone (Instant Hotspot source)")
        self.assertIn("battery 66%", ident.describe())


if __name__ == "__main__":
    unittest.main()
