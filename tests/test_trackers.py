import unittest

from nightjar.history import Session
from nightjar.patterns import analyze
from nightjar.registry import Sighting
from nightjar.trackers import find_suspects

BASE = 1_700_000_000.0
HOUR = 3600.0
TILE_UUID = "0000feed-0000-1000-8000-00805f9b34fb"


def s(address, when, **kw):
    base = dict(name=None, rssi=-60, manufacturer_data={}, service_uuids=[])
    base.update(kw)
    return Sighting(address=address, seen_at=when, **base)


def session(sid, label, sightings):
    return Session(session_id=sid, label=label,
                   sightings=sorted(sightings, key=lambda x: x.seen_at))


def tag_sightings(start, minutes=range(0, 121, 20)):
    return [s("D4:61", start + m * 60, service_uuids=[TILE_UUID])
            for m in minutes]


class TrackerTests(unittest.TestCase):
    def setUp(self):
        # Two listening sessions, a day apart, in two places.
        self.home = session("home1", "home", [
            *tag_sightings(BASE),
            s("TV:01", BASE + 100, name="Samsung QLED TV"),
            s("TV:01", BASE + 3000, name="Samsung QLED TV"),
        ])
        self.office = session("off1", "office", [
            *tag_sightings(BASE + 26 * HOUR),
            s("PR:02", BASE + 26 * HOUR + 60, name="Office Printer"),
        ])

    def test_travelling_tag_is_flagged_with_reasons(self):
        suspects = find_suspects([self.home, self.office])
        self.assertEqual(len(suspects), 1)
        suspect = suspects[0]
        self.assertGreaterEqual(suspect.score, 4)
        joined = " ".join(suspect.reasons)
        self.assertIn("multiple places", joined)
        self.assertIn("start and end", joined)

    def test_named_devices_are_never_suspects(self):
        suspects = find_suspects([self.home, self.office])
        self.assertNotIn("Samsung QLED TV", [x.label for x in suspects])

    def test_stationary_tag_in_one_session_is_not_flagged(self):
        only_home = session("h", "home", tag_sightings(BASE))
        self.assertEqual(find_suspects([only_home]), [])


class PatternTests(unittest.TestCase):
    def test_regular_detection_and_labels(self):
        sessions = []
        for day in range(3):
            start = BASE + day * 24 * HOUR
            sessions.append(session(f"s{day}", "home", [
                s("TV:01", start + 10, name="Samsung QLED TV"),
                s("TV:01", start + 600, name="Samsung QLED TV"),
            ]))
        patterns = analyze(sessions)
        tv = next(p for p in patterns if p.identity.label.startswith("Samsung"))
        self.assertTrue(tv.is_regular)
        self.assertEqual(tv.days_present, 3)
        self.assertEqual(tv.labels, {"home"})
        self.assertEqual(tv.sessions_present, 3)


if __name__ == "__main__":
    unittest.main()
