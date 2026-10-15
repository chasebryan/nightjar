import json
import unittest

from nightjar.history import Session
from nightjar.trackers import SUSPECT_THRESHOLD, find_suspects, format_suspects

from .helpers import AIRTAG_SEPARATED, AIRTAG_WITH_OWNER, APPLE, BASE, HOUR, TILE_UUID, sighting


def session(sid, label, sightings):
    return Session(session_id=sid, label=label,
                   sightings=sorted(sightings, key=lambda x: x.seen_at))


def tag_sightings(start, minutes=range(0, 121, 20), address="D4:61", rssi=-60, **kw):
    return [sighting(address, start + m * 60, service_uuids=[TILE_UUID], rssi=rssi, **kw)
            for m in minutes]


class TrackerTests(unittest.TestCase):
    def setUp(self):
        # Two listening sessions, a day apart, in two places.
        self.home = session("home1", "home", [
            *tag_sightings(BASE),
            sighting("TV:01", BASE + 100, name="Samsung QLED TV"),
            sighting("TV:01", BASE + 3000, name="Samsung QLED TV"),
        ])
        self.office = session("off1", "office", [
            *tag_sightings(BASE + 26 * HOUR),
            sighting("PR:02", BASE + 26 * HOUR + 60, name="Office Printer"),
        ])

    def test_travelling_tag_is_flagged_with_reasons(self):
        suspects = find_suspects([self.home, self.office])
        self.assertEqual(len(suspects), 1)
        suspect = suspects[0]
        self.assertGreaterEqual(suspect.score, SUSPECT_THRESHOLD)
        joined = " ".join(suspect.reasons)
        self.assertIn("multiple places", joined)
        self.assertIn("start and end", joined)
        self.assertIn("close range", joined)
        self.assertEqual(suspect.addresses, ["D4:61"])
        self.assertEqual(suspect.labels, ["home", "office"])
        self.assertIn(suspect.confidence, ("possible", "likely", "strong"))
        json.dumps(suspect.to_dict())

    def test_named_devices_are_never_suspects(self):
        suspects = find_suspects([self.home, self.office])
        self.assertNotIn("Samsung QLED TV", [x.label for x in suspects])

    def test_stationary_tag_in_one_session_is_not_flagged(self):
        only_home = session("h", "home", tag_sightings(BASE))
        self.assertEqual(find_suspects([only_home]), [])

    def test_a_resident_of_one_place_does_not_reach_the_bar(self):
        # A colleague's keys: at the office every day, never anywhere else,
        # and gone before the listener leaves. Persistence alone scores 4.
        days = []
        for day in range(3):
            start = BASE + day * 24 * HOUR
            days.append(session(f"o{day}", "office", [
                *tag_sightings(start, minutes=range(0, 301, 15)),  # 5 h
                sighting("PR:02", start + 400 * 60, name="Office Printer"),
            ]))
        self.assertEqual(find_suspects(days), [])
        # Lower the bar and the same evidence surfaces, labelled honestly.
        suspects = find_suspects(days, threshold=4)
        self.assertEqual(len(suspects), 1)
        self.assertEqual(suspects[0].score, 4)
        self.assertEqual(suspects[0].confidence, "possible")

    def test_presence_hours_add_up_across_sessions(self):
        long_days = [
            session("a", "home", tag_sightings(BASE, minutes=range(0, 301, 30))),
            session("b", "home", tag_sightings(BASE + 24 * HOUR,
                                               minutes=range(0, 301, 30))),
        ]
        suspect = find_suspects(long_days, threshold=1)[0]
        self.assertIn("near you for 10.0 hours in total", " ".join(suspect.reasons))

    def test_far_tags_do_not_get_the_proximity_point(self):
        far_home = session("home1", "home", tag_sightings(BASE, rssi=-92))
        far_office = session("off1", "office", tag_sightings(BASE + 26 * HOUR, rssi=-92))
        suspect = find_suspects([far_home, far_office], threshold=1)[0]
        self.assertNotIn("close range", " ".join(suspect.reasons))
        close = find_suspects([self.home, self.office], min_rssi=-95)[0]
        self.assertIn("close range", " ".join(close.reasons))

    def test_ignore_list_removes_your_own_tags(self):
        self.assertEqual(find_suspects([self.home, self.office], ignore=["d4:61"]), [])
        self.assertEqual(find_suspects([self.home, self.office], ignore=["tile"]), [])
        self.assertEqual(len(find_suspects([self.home, self.office], ignore=["zz:zz"])), 1)

    def test_findmy_with_owner_is_not_a_suspect(self):
        tag = {"manufacturer_data": {APPLE: AIRTAG_WITH_OWNER}}
        home = session("h", "home", [sighting("F2:19", BASE + m * 60, **tag)
                                     for m in range(0, 121, 20)])
        office = session("o", "office", [sighting("F2:19", BASE + 26 * HOUR + m * 60, **tag)
                                         for m in range(0, 121, 20)])
        self.assertEqual(find_suspects([home, office]), [])
        separated = {"manufacturer_data": {APPLE: AIRTAG_SEPARATED}}
        home2 = session("h2", "home", [sighting("E7:04", BASE + m * 60, **separated)
                                       for m in range(0, 121, 20)])
        office2 = session("o2", "office", [sighting("E7:04", BASE + 26 * HOUR + m * 60,
                                                    **separated) for m in range(0, 121, 20)])
        self.assertEqual(len(find_suspects([home2, office2])), 1)

    def test_format_suspects(self):
        text = format_suspects(find_suspects([self.home, self.office]))
        self.assertIn("1 suspect(s)", text)
        self.assertIn("Tile tracker — score", text)
        self.assertIn("--ignore", text)
        self.assertIn("evidence, not proof", format_suspects([]).lower())


if __name__ == "__main__":
    unittest.main()
