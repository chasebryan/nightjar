import unittest

from nightjar.live import render_live
from nightjar.registry import Registry, Sighting
from nightjar.report import sparkline


def feed(registry, address, rssis, start=1000.0, name=None):
    for i, rssi in enumerate(rssis):
        registry.observe(Sighting(address=address, name=name, rssi=rssi,
                                  seen_at=start + i * 10))


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

    def test_render_live_frame(self):
        reg = Registry()
        feed(reg, "AA:05", [-70, -65, -60], name="AirPods Pro")
        frame = render_live(reg, started_at=900.0, now=1000.0,
                            place="HomeNet")
        self.assertIn("live radar", frame)
        self.assertIn("HomeNet", frame)
        self.assertIn("AirPods Pro", frame)
        self.assertIn("█", frame)


if __name__ == "__main__":
    unittest.main()
