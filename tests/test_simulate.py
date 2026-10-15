import random
import unittest

from nightjar.registry import Registry
from nightjar.simulate import PROFILES, random_sighting


class SimulateTests(unittest.TestCase):
    def test_sightings_are_well_formed(self):
        rng = random.Random(42)
        for _ in range(50):
            s = random_sighting(rng)
            self.assertTrue(s.address)
            self.assertIsNotNone(s.rssi)
            self.assertTrue(-100 <= s.rssi <= 0)

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


if __name__ == "__main__":
    unittest.main()
