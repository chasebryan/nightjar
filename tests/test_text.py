import unittest

from nightjar.text import (
    estimate_distance_m,
    fmt_age,
    fmt_elapsed,
    fmt_hours,
    hour_sparkline,
    proximity_band,
    rssi_level,
    sparkline,
    truncate,
)


class TextTests(unittest.TestCase):
    def test_rssi_level_is_clamped(self):
        self.assertEqual(rssi_level(-95), 0.0)
        self.assertEqual(rssi_level(-35), 1.0)
        self.assertEqual(rssi_level(-120), 0.0)
        self.assertEqual(rssi_level(0), 1.0)

    def test_sparkline_buckets_down_to_width(self):
        self.assertEqual(len(sparkline(list(range(-95, -35)), width=10)), 10)
        self.assertEqual(sparkline([-95, -35]), "▁█")

    def test_hour_sparkline(self):
        self.assertEqual(hour_sparkline({}), " " * 24)
        line = hour_sparkline({9: 10, 10: 5})
        self.assertEqual(len(line), 24)
        self.assertEqual(line[9], "█")
        self.assertEqual(line[0], "·")
        self.assertNotEqual(line[10], "·")

    def test_proximity_bands(self):
        self.assertEqual(proximity_band(-40), "immediate")
        self.assertEqual(proximity_band(-60), "near")
        self.assertEqual(proximity_band(-80), "far")
        self.assertEqual(proximity_band(-90), "faint")
        self.assertEqual(proximity_band(None), "?")

    def test_distance_estimate(self):
        self.assertEqual(estimate_distance_m(-59, -59), 1.0)
        self.assertGreater(estimate_distance_m(-79, -59), 5.0)
        self.assertIsNone(estimate_distance_m(None, -59))
        self.assertIsNone(estimate_distance_m(-59, None))

    def test_formatters(self):
        self.assertEqual(fmt_age(5), "5s")
        self.assertEqual(fmt_age(125), "2m")
        self.assertEqual(fmt_age(3900), "1h 05m")
        self.assertEqual(fmt_elapsed(3661), "01:01:01")
        self.assertEqual(fmt_elapsed(-5), "00:00:00")
        self.assertEqual(fmt_hours(30), "30 s")
        self.assertEqual(fmt_hours(600), "10 min")
        self.assertEqual(fmt_hours(5400), "1.5 h")

    def test_truncate(self):
        self.assertEqual(truncate("short", 10), "short")
        self.assertEqual(truncate("a long label here", 8), "a long …")
        self.assertEqual(truncate("x", 0), "")


if __name__ == "__main__":
    unittest.main()
