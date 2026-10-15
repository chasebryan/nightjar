import unittest

from nightjar.identify import IdentityResolver
from nightjar.live import GONE_AFTER, QUIET_AFTER, render_live
from nightjar.registry import Registry, Sighting
from nightjar.report import sparkline

from .helpers import AIRPODS_PRO, APPLE, IPHONE_NEARBY


def feed(target, address, rssis, start=1000.0, name=None, **kw):
    for i, rssi in enumerate(rssis):
        target.observe(Sighting(address=address, name=name, rssi=rssi,
                                seen_at=start + i * 10, **kw))


class LiveTests(unittest.TestCase):
    def test_trend_approaching(self):
        reg = Registry()
        feed(reg, "AA:01", [-85, -84, -83, -60, -58, -55])
        record = reg.devices[0]
        self.assertEqual(record.trend(), "approaching")

    def test_trend_receding_and_steady(self):
        reg = Registry()
        feed(reg, "AA:02", [-50, -52, -51, -80, -82, -84])
        feed(reg, "AA:03", [-60, -61, -60, -61, -60, -61])
        by_addr = {r.address: r for r in reg.devices}
        self.assertEqual(by_addr["AA:02"].trend(), "receding")
        self.assertEqual(by_addr["AA:03"].trend(), "steady")

    def test_trend_needs_samples(self):
        reg = Registry()
        feed(reg, "AA:04", [-50, -40])
        self.assertIsNone(reg.devices[0].trend())

    def test_sparkline_shape(self):
        self.assertEqual(sparkline([]), "")
        line = sparkline([-90, -70, -50, -40])
        self.assertEqual(len(line), 4)
        self.assertLess(line[0], line[-1])  # rises with signal
        self.assertEqual(len(sparkline(list(range(-90, -30)))), 14)

    def test_render_live_frame_from_registry(self):
        reg = Registry()
        feed(reg, "AA:05", [-70, -65, -60], name="AirPods Pro")
        frame = render_live(reg, started_at=900.0, now=1030.0, place="HomeNet")
        self.assertIn("live radar", frame)
        self.assertIn("HomeNet", frame)
        self.assertIn("AirPods Pro", frame)
        self.assertIn("█", frame)
        self.assertIn("addresses", frame)

    def test_render_live_frame_from_identities(self):
        resolver = IdentityResolver()
        for i in range(4):
            feed(resolver, f"11:22:33:44:55:0{i}", [-62], start=1000.0 + i,
                 manufacturer_data={APPLE: IPHONE_NEARBY})
        feed(resolver, "AA:05", [-48, -47, -46], name="AirPods Pro",
             manufacturer_data={APPLE: AIRPODS_PRO})
        frame = render_live(resolver, started_at=900.0, now=1030.0, mode="passive",
                            alerts=["ALERT 12:00:00  hello"])
        self.assertIn("2 devices / 7 sightings", frame)
        self.assertIn("passive scan", frame)
        self.assertIn("Apple device (Nearby Info)", frame)
        self.assertIn("AirPods Pro", frame)
        self.assertIn("immediate", frame)
        self.assertIn("ALERT 12:00:00  hello", frame)
        # The loudest row comes first.
        lines = frame.splitlines()
        first_row = next(line for line in lines if "dBm" not in line and "-4" in line)
        self.assertIn("AirPods Pro", first_row)

    def test_quiet_and_gone_rows(self):
        reg = Registry()
        feed(reg, "AA:06", [-50], start=1000.0)
        feed(reg, "AA:07", [-55], start=1000.0 + QUIET_AFTER + 30)
        now = 1000.0 + QUIET_AFTER + 40
        frame = render_live(reg, started_at=900.0, now=now)
        self.assertIn("quiet", frame)
        gone = render_live(reg, started_at=900.0, now=1000.0 + GONE_AFTER + 1)
        self.assertIn("not heard for", gone)

    def test_top_limit_and_width(self):
        reg = Registry()
        for i in range(6):
            feed(reg, f"AA:1{i}", [-50 - i])
        frame = render_live(reg, started_at=900.0, now=1010.0, top=2, width=70)
        self.assertIn("4 more below the fold", frame)
        self.assertTrue(all(len(line) <= 70 for line in frame.splitlines()))


if __name__ == "__main__":
    unittest.main()
