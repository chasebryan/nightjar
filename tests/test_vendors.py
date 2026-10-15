import unittest

from nightjar.companies import company_name
from nightjar.vendors import (
    decode_microsoft,
    decode_ruuvi,
    identify_manufacturer,
)


class MicrosoftTests(unittest.TestCase):
    def test_cdp_beacon_names_the_device_class(self):
        ident = decode_microsoft(bytes([0x01, 0x09, 0x20, 0x00]) + bytes(20))
        self.assertEqual(ident.kind, "Windows desktop")
        self.assertTrue(ident.windows_pc)
        self.assertEqual(ident.specificity, 2)
        phone = decode_microsoft(bytes([0x01, 0x06]))
        self.assertEqual(phone.kind, "iPhone (CDP)")
        self.assertFalse(phone.windows_pc)

    def test_cdp_version_bits_are_masked_off(self):
        ident = decode_microsoft(bytes([0x01, 0xE0 | 0x0F]))
        self.assertEqual(ident.kind, "Windows laptop")

    def test_swift_pair_with_display_name(self):
        ident = decode_microsoft(bytes([0x03, 0x00, 0x80]) + b"Surface Earbuds")
        self.assertEqual(ident.kind, "Windows device (Swift Pair)")
        self.assertIn("announces itself as 'Surface Earbuds'", ident.describe())

    def test_swift_pair_legacy_vector(self):
        self.assertEqual(decode_microsoft(bytes.fromhex("03060800")).kind,
                         "Windows device (Swift Pair)")

    def test_other_microsoft_payloads_stay_generic(self):
        self.assertEqual(decode_microsoft(bytes([0x07, 0x01])).kind, "Microsoft device")
        self.assertIsNone(decode_microsoft(b""))


class RuuviTests(unittest.TestCase):
    def test_rawv2_decode(self):
        payload = (bytes([0x05]) + (4500).to_bytes(2, "big")
                   + (18000).to_bytes(2, "big") + (51325).to_bytes(2, "big")
                   + bytes(6) + ((1400 << 5) | 0x1F).to_bytes(2, "big")
                   + bytes([0x12, 0x00, 0x2A]) + bytes(6))
        reading = decode_ruuvi(payload)
        self.assertAlmostEqual(reading.temperature_c, 22.5)
        self.assertAlmostEqual(reading.humidity_pct, 45.0)
        self.assertAlmostEqual(reading.pressure_hpa, 1013.25)
        self.assertEqual(reading.battery_mv, 3000)
        self.assertEqual(reading.movement_count, 0x12)
        self.assertIn("1013.2 hPa", reading.describe())

    def test_invalid_values_are_none(self):
        payload = (bytes([0x05, 0x80, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]) + bytes(6)
                   + bytes([0xFF, 0xFF, 0xFF]) + bytes(8))
        reading = decode_ruuvi(payload)
        self.assertIsNone(reading.temperature_c)
        self.assertIsNone(reading.humidity_pct)
        self.assertIsNone(reading.pressure_hpa)
        self.assertIsNone(reading.battery_mv)
        self.assertIsNone(reading.movement_count)
        self.assertIsNone(decode_ruuvi(bytes([0x03]) + bytes(23)))


class DispatchTests(unittest.TestCase):
    def test_families_and_fallbacks(self):
        self.assertEqual(identify_manufacturer({0x0087: b"\x01"}).kind, "Garmin device")
        self.assertEqual(identify_manufacturer({0x0065: b"\x01"}).kind, "HP device")
        self.assertIsNone(identify_manufacturer({0xBEEF: b"\x01"}))
        self.assertEqual(identify_manufacturer({0x0499: b"\x05" + bytes(23)}).kind,
                         "RuuviTag sensor")
        self.assertEqual(identify_manufacturer({0x0499: b"\x03"}).kind, "Ruuvi device")

    def test_company_name_table(self):
        self.assertEqual(company_name(0x004C), "Apple")
        self.assertEqual(company_name(0x0059), "Nordic Semiconductor")
        self.assertEqual(company_name(0xBEEF), "0xBEEF")


if __name__ == "__main__":
    unittest.main()
