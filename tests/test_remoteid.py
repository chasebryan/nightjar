"""Remote ID decoder tests.

The field packing is taken from opendroneid-core-c's packed structs and
the canonical example values in its `test_inout.c` (Basic ID serial,
Location at 45.539309 / -122.966389 airborne, System operator offset by
+0.00001). We rebuild those messages byte for byte per the verified
layout and assert the documented decodes, plus the invalid sentinels
(lat 0, altitude raw 0 = -1000, timestamp 0xFFFF).
"""

import struct
import unittest

from nightjar.remoteid import (
    APP_CODE_ODID,
    EPOCH_2019,
    DroneReport,
    bearing,
    compass,
    decode_message,
    describe,
    haversine,
    parse_service_data,
    remoteid_value,
    report_from_service_data,
)


def basic_id(id_type, ua_type, uas_id, proto=2):
    return (bytes([(0x0 << 4) | proto, (id_type << 4) | ua_type])
            + uas_id.encode().ljust(20, b"\x00") + bytes(3))


def location(*, status, dir_raw, ew, speed_mult, speed_raw, speed_v_raw,
             lat, lon, alt_baro, alt_geo, height, height_type, ts):
    flags = (status << 4) | (height_type << 2) | (ew << 1) | speed_mult
    return (bytes([(0x1 << 4) | 2, flags, dir_raw, speed_raw])
            + struct.pack("<b", speed_v_raw)
            + struct.pack("<i", lat) + struct.pack("<i", lon)
            + struct.pack("<H", alt_baro) + struct.pack("<H", alt_geo)
            + struct.pack("<H", height) + bytes([0, 0])
            + struct.pack("<H", ts) + bytes([0, 0]))


def system(*, op_loc, op_lat, op_lon, area_count, area_radius, area_ceiling,
           area_floor, category, ua_class, op_alt, ts_unix):
    return (bytes([(0x4 << 4) | 2, op_loc & 0x3])
            + struct.pack("<i", op_lat) + struct.pack("<i", op_lon)
            + struct.pack("<H", area_count) + bytes([area_radius])
            + struct.pack("<H", area_ceiling) + struct.pack("<H", area_floor)
            + bytes([(category << 4) | ua_class])
            + struct.pack("<H", op_alt) + struct.pack("<I", ts_unix) + bytes([0]))


def self_id(desc_type, text):
    return bytes([(0x3 << 4) | 2, desc_type]) + text.encode().ljust(23, b"\x00")


def operator_id(id_type, oid):
    return (bytes([(0x5 << 4) | 2, id_type])
            + oid.encode().ljust(20, b"\x00") + bytes(3))


CORE_C_LOCATION = location(
    status=2, dir_raw=36, ew=1, speed_mult=0, speed_raw=22, speed_v_raw=10,
    lat=455393090, lon=-1229663890, alt_baro=2200, alt_geo=2220, height=2160,
    height_type=1, ts=3605)
CORE_C_BASIC = basic_id(2, 2, "12345678901234567890")
CORE_C_SYSTEM = system(
    op_loc=0, op_lat=455393190, op_lon=-1229663790, area_count=35,
    area_radius=75, area_ceiling=round((176.9 + 1000) * 2),
    area_floor=round((41.7 + 1000) * 2), category=0, ua_class=0,
    op_alt=round((20.5 + 1000) * 2), ts_unix=28_000_000)


class MessageSizeTests(unittest.TestCase):
    def test_all_messages_are_25_bytes(self):
        for msg in (CORE_C_BASIC, CORE_C_LOCATION, CORE_C_SYSTEM,
                    self_id(0, "hi"), operator_id(0, "OP")):
            self.assertEqual(len(msg), 25)


class BasicIDTests(unittest.TestCase):
    def test_core_c_serial(self):
        bid = decode_message(CORE_C_BASIC).basic_id
        self.assertEqual(bid.uas_id, "12345678901234567890")
        self.assertEqual(bid.id_type, 2)
        self.assertEqual(bid.id_type_name, "CAA registration")
        self.assertEqual(bid.ua_type, 2)
        self.assertEqual(bid.ua_type_name, "helicopter/multirotor")
        self.assertTrue(bid.is_serial)

    def test_id_type_none_is_not_a_serial(self):
        bid = decode_message(basic_id(0, 1, "")).basic_id
        self.assertFalse(bid.is_serial)

    def test_nibble_order(self):
        # byte 1 high nibble = ID type, low nibble = UA type.
        bid = decode_message(basic_id(1, 4, "SN")).basic_id
        self.assertEqual((bid.id_type, bid.ua_type), (1, 4))


class LocationTests(unittest.TestCase):
    def test_core_c_location(self):
        loc = decode_message(CORE_C_LOCATION).location
        self.assertEqual(loc.status, 2)
        self.assertTrue(loc.airborne)
        self.assertEqual(loc.status_name, "airborne")
        self.assertAlmostEqual(loc.latitude, 45.539309, places=7)
        self.assertAlmostEqual(loc.longitude, -122.966389, places=7)
        self.assertEqual(loc.altitude_baro, 100.0)
        self.assertEqual(loc.altitude_geo, 110.0)
        self.assertEqual(loc.height, 80.0)
        self.assertEqual(loc.height_type, 1)
        self.assertEqual(loc.height_ref, "AGL")
        self.assertEqual(loc.direction, 216.0)  # 36 + 180 (E/W bit)
        self.assertEqual(loc.speed_h, 5.5)       # 22 * 0.25
        self.assertEqual(loc.speed_v, 5.0)       # 10 * 0.5
        self.assertEqual(loc.timestamp_tenths, 3605)

    def test_speed_multiplier(self):
        fast = location(status=2, dir_raw=0, ew=0, speed_mult=1, speed_raw=100,
                        speed_v_raw=0, lat=1, lon=1, alt_baro=0, alt_geo=0,
                        height=0, height_type=0, ts=0)
        loc = decode_message(fast).location
        self.assertEqual(loc.speed_h, 100 * 0.75 + 63.75)

    def test_west_direction(self):
        west = location(status=1, dir_raw=10, ew=1, speed_mult=0, speed_raw=0,
                        speed_v_raw=0, lat=1, lon=1, alt_baro=0, alt_geo=0,
                        height=0, height_type=0, ts=0)
        self.assertEqual(decode_message(west).location.direction, 190.0)

    def test_invalid_sentinels(self):
        inv = location(status=0, dir_raw=0xFF, ew=0, speed_mult=0, speed_raw=0,
                       speed_v_raw=0, lat=0, lon=0, alt_baro=0, alt_geo=0,
                       height=0, height_type=0, ts=0xFFFF)
        loc = decode_message(inv).location
        self.assertIsNone(loc.latitude)
        self.assertIsNone(loc.longitude)
        self.assertIsNone(loc.altitude_baro)
        self.assertIsNone(loc.altitude_geo)
        self.assertIsNone(loc.height)
        self.assertIsNone(loc.timestamp_tenths)
        self.assertIsNone(loc.direction)

    def test_negative_vertical_speed(self):
        down = location(status=2, dir_raw=0, ew=0, speed_mult=0, speed_raw=0,
                        speed_v_raw=-6, lat=1, lon=1, alt_baro=0, alt_geo=0,
                        height=0, height_type=0, ts=0)
        self.assertEqual(decode_message(down).location.speed_v, -3.0)


class SystemTests(unittest.TestCase):
    def test_core_c_system(self):
        sysm = decode_message(CORE_C_SYSTEM).system
        self.assertAlmostEqual(sysm.operator_latitude, 45.539319, places=7)
        self.assertAlmostEqual(sysm.operator_longitude, -122.966379, places=7)
        self.assertEqual(sysm.operator_location_type, 0)
        self.assertEqual(sysm.operator_location_name, "takeoff point")
        self.assertEqual(sysm.area_count, 35)
        self.assertEqual(sysm.area_radius_m, 750)  # 75 * 10
        self.assertEqual(sysm.operator_altitude, 20.5)
        self.assertEqual(sysm.timestamp_unix, 28_000_000 + EPOCH_2019)

    def test_bit_fields(self):
        # op loc type in bits 0-1, classification in bits 2-4.
        sysm = decode_message(system(
            op_loc=1, op_lat=0, op_lon=0, area_count=0, area_radius=0,
            area_ceiling=0, area_floor=0, category=3, ua_class=5, op_alt=0,
            ts_unix=0)).system
        self.assertEqual(sysm.operator_location_type, 1)
        self.assertEqual(sysm.category, 3)
        self.assertEqual(sysm.ua_class, 5)
        self.assertIsNone(sysm.timestamp_unix)  # raw 0 = unknown


class TextMessageTests(unittest.TestCase):
    def test_self_id_and_operator_id(self):
        s = decode_message(self_id(0, "Filming a house tour")).self_id
        self.assertEqual(s.description, "Filming a house tour")
        o = decode_message(operator_id(0, "FA3GH7B9")).operator_id
        self.assertEqual(o.operator_id, "FA3GH7B9")


class ServiceDataTests(unittest.TestCase):
    def test_framing_and_report(self):
        value = bytes([APP_CODE_ODID, 7]) + CORE_C_LOCATION
        messages = parse_service_data(value)
        self.assertEqual(len(messages), 1)
        report = report_from_service_data(value)
        self.assertTrue(report.airborne)

    def test_not_remote_id(self):
        self.assertEqual(parse_service_data(b"\x00\x01" + bytes(25)), [])
        self.assertEqual(parse_service_data(b""), [])
        self.assertIsNone(report_from_service_data(b"\xaa\xbb"))

    def test_message_pack(self):
        pack = bytes([APP_CODE_ODID, 3,
                      (0xF << 4) | 2, 25, 3]) + CORE_C_BASIC + CORE_C_LOCATION + CORE_C_SYSTEM
        messages = parse_service_data(pack)
        self.assertEqual(len(messages), 3)
        report = DroneReport()
        for m in messages:
            report.ingest(m)
        self.assertEqual(report.serial, "12345678901234567890")
        self.assertTrue(report.airborne)
        self.assertIsNotNone(report.system)

    def test_remoteid_value_extraction(self):
        value = bytes([APP_CODE_ODID, 1]) + CORE_C_BASIC
        sd = {"0000fffa-0000-1000-8000-00805f9b34fb": value}
        self.assertEqual(remoteid_value(sd), value)
        self.assertIsNone(remoteid_value({"0000feaa-0000-1000-8000-00805f9b34fb": b"\x40"}))
        self.assertIsNone(remoteid_value({"0000fffa-0000-1000-8000-00805f9b34fb": b"\x00\x01"}))


class ReportAndDescribeTests(unittest.TestCase):
    def _full_report(self):
        report = DroneReport()
        for msg in (CORE_C_BASIC, CORE_C_LOCATION, CORE_C_SYSTEM,
                    self_id(0, "Survey flight")):
            report.ingest(decode_message(msg))
        return report

    def test_describe(self):
        report = self._full_report()
        text = describe(report)
        self.assertIn("Drone (Remote ID):", text)
        self.assertIn("serial 12345678901234567890", text)
        self.assertIn("helicopter/multirotor", text)
        self.assertIn("airborne", text)
        self.assertIn("alt 110 m", text)
        self.assertIn("height 80 m AGL", text)
        self.assertIn("Survey flight", text)
        self.assertEqual(report.serial, "12345678901234567890")

    def test_describe_with_home_gives_relative_operator(self):
        report = self._full_report()
        text = describe(report, home=(45.5375, -122.9640))
        self.assertRegex(text, r"operator \d+ m [NSEW]+")
        self.assertNotIn("45.539", text.split("operator", 1)[1])

    def test_geo_helpers(self):
        self.assertEqual(compass(0), "N")
        self.assertEqual(compass(90), "E")
        self.assertEqual(compass(225), "SW")
        self.assertEqual(round(haversine(0, 0, 0, 0)), 0)
        self.assertAlmostEqual(bearing(0, 0, 1, 0), 0, places=1)
        self.assertAlmostEqual(bearing(0, 0, 0, 1), 90, places=1)


if __name__ == "__main__":
    unittest.main()
