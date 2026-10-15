import random
import tempfile
import unittest
from pathlib import Path

from nightjar.history import load_log
from nightjar.identify import IdentityResolver
from nightjar.patterns import analyze
from nightjar.registry import Registry
from nightjar.simulate import PROFILES, random_sighting, write_demo_log
from nightjar.trackers import find_suspects

from .helpers import BASE


class SimulateTests(unittest.TestCase):
    def test_sightings_are_well_formed(self):
        rng = random.Random(42)
        for _ in range(50):
            s = random_sighting(rng)
            self.assertTrue(s.address)
            self.assertIsNotNone(s.rssi)
            self.assertTrue(-100 <= s.rssi <= 0)
            s.to_dict()

    def test_registry_folds_the_neighbourhood(self):
        # 200 simulated sightings should collapse to a small set of
        # resident devices, plus extra entries for the rotating phone.
        rng = random.Random(7)
        reg = Registry()
        for _ in range(200):
            reg.observe(random_sighting(rng))
        self.assertGreaterEqual(len(reg), len(PROFILES))
        self.assertLess(len(reg), 200)
        self.assertEqual(reg.total_sightings, 200)

    def test_every_profile_is_recognized(self):
        rng = random.Random(3)
        resolver = IdentityResolver()
        for _ in range(400):
            resolver.observe(random_sighting(rng))
        kinds = {identity.kind for identity in resolver}
        for expected in ("AirPods Pro", "Apple device (Nearby Info)", "Samsung device",
                         "Tile tracker", "Find My device (AirTag-class)",
                         "Find My accessory (with owner)", "Windows laptop",
                         "Find My Device network tag (Google)",
                         "Fast Pair device (Google)", "RuuviTag sensor"):
            self.assertIn(expected, kinds)


class DemoLogTests(unittest.TestCase):
    def test_demo_log_tells_its_story(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "demo.jsonl")
            ids = write_demo_log(path, days=2, seed=7, start=BASE)
            self.assertEqual(len(ids), 6)
            report = load_log([path])
            self.assertEqual(report.skipped_lines, 0)
            sessions = report.sessions
            self.assertEqual([s.label for s in sessions],
                             ["home", "office", "home"] * 2)
            self.assertTrue(all(s.has_header and s.footer_ended_at for s in sessions))
            patterns = analyze(sessions)
            labels = {p.identity.label for p in patterns}
            self.assertIn("AirPods Pro", labels)
            self.assertIn("Office Printer", labels)
            suspects = find_suspects(sessions)
            # One separated AirTag per day (it rotates its address daily),
            # each seen at both places from start to end: strong suspects.
            self.assertEqual(len(suspects), 2)
            self.assertTrue(all(s.confidence == "strong" for s in suspects))
            self.assertTrue(all(s.kind == "Find My device (AirTag-class)" for s in suspects))
            # The colleague's Tile lives at the office and is not a suspect.
            self.assertNotIn("Tile tracker", [s.kind for s in suspects])


if __name__ == "__main__":
    unittest.main()
