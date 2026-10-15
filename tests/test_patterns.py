import json
import time
import unittest

from nightjar.history import Session
from nightjar.patterns import analyze, format_report

from .helpers import AIRPODS_PRO, APPLE, BASE, HOUR, TILE_UUID, sighting


def session(sid, label, sightings, started_at=None):
    return Session(session_id=sid, label=label,
                   sightings=sorted(sightings, key=lambda x: x.seen_at),
                   header_started_at=started_at)


class PatternTests(unittest.TestCase):
    def setUp(self):
        self.sessions = []
        for day in range(3):
            start = BASE + day * 24 * HOUR
            self.sessions.append(session(f"s{day}", "home", [
                sighting("TV:01", start + 10, name="Samsung QLED TV", rssi=-70),
                sighting("TV:01", start + 600, name="Samsung QLED TV", rssi=-72),
                sighting("AA:01", start + 20, rssi=-50,
                         manufacturer_data={APPLE: AIRPODS_PRO}),
            ]))
        self.sessions.append(session("visit", "office", [
            sighting("D4:61", BASE + 50 * HOUR, service_uuids=[TILE_UUID]),
        ]))

    def test_regular_detection_and_labels(self):
        patterns = analyze(self.sessions)
        tv = next(p for p in patterns if p.identity.label.startswith("Samsung"))
        self.assertTrue(tv.is_regular)
        self.assertEqual(tv.status, "regular")
        self.assertEqual(tv.days_present, 3)
        self.assertEqual(tv.labels, {"home"})
        self.assertEqual(tv.sessions_present, 3)
        self.assertEqual(len(tv.presences), 3)
        self.assertEqual(tv.presences[0].sightings, 2)
        self.assertEqual(tv.presences[0].rssi_median, -70)
        self.assertAlmostEqual(tv.average_presence_seconds, 590.0)
        self.assertEqual(tv.rssi_median, -70)

    def test_one_off_and_visitor_status(self):
        patterns = analyze(self.sessions)
        tile = next(p for p in patterns if p.identity.kind == "Tile tracker")
        self.assertEqual(tile.status, "one-off")
        self.assertEqual(tile.labels, {"office"})

    def test_hour_and_weekday_profiles(self):
        patterns = analyze(self.sessions)
        tv = next(p for p in patterns if p.identity.label.startswith("Samsung"))
        profile = tv.hour_profile
        self.assertEqual(len(profile), 24)
        hour = time.localtime(BASE + 10).tm_hour
        self.assertNotEqual(profile[hour], "·")
        self.assertEqual(sum(1 for c in profile if c != "·"), 1)
        self.assertNotEqual(tv.usual_hours, "—")
        self.assertNotEqual(tv.usual_days, "—")
        self.assertEqual(sum(tv.weekday_histogram.values()), 6)

    def test_to_dict_is_json_ready(self):
        patterns = analyze(self.sessions)
        docs = [p.to_dict() for p in patterns]
        json.dumps(docs)
        tv = next(d for d in docs if d["identity"]["label"].startswith("Samsung"))
        self.assertEqual(tv["status"], "regular")
        self.assertEqual(len(tv["sessions"]), 3)
        self.assertIn("hour_histogram", tv)

    def test_format_report_text(self):
        patterns = analyze(self.sessions)
        text = format_report(self.sessions, patterns)
        self.assertIn("Pattern of life — 4 sessions", text)
        self.assertIn("places: home, office", text)
        self.assertIn("regular", text)
        self.assertIn("tracker-shaped", text)
        self.assertIn("AirPods Pro: L 80%", text)
        wide = format_report(self.sessions, patterns, wide=True)
        self.assertIn("avg stay", wide)

    def test_format_report_handles_empty_sessions(self):
        empty = session("e", "home", [], started_at=BASE)
        text = format_report([empty, *self.sessions], analyze([empty, *self.sessions]))
        self.assertIn("(1 heard nothing)", text)
        self.assertEqual(format_report([], []), "No sessions found in the given logs.")


if __name__ == "__main__":
    unittest.main()
