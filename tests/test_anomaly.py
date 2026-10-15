import time
import unittest

from nightjar.anomaly import find_anomalies, format_anomalies, split_baseline
from nightjar.history import Session
from nightjar.registry import Sighting

from .helpers import APPLE, IPHONE_NEARBY

DAY = 86400.0


def at_hour(day_epoch, hour, minute=0):
    local = time.localtime(day_epoch)
    midnight = day_epoch - (local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec)
    return midnight + hour * 3600 + minute * 60


def tv_session(sid, day, hour=19):
    t = at_hour(day, hour)
    return Session(session_id=sid, label="home", post="mac",
                   sightings=[Sighting(address="8C:3B:AD:91:22:0F",
                                       name="Samsung QLED TV", rssi=-70,
                                       manufacturer_data={0x0075: bytes.fromhex("7500420001")},
                                       seen_at=t + i * 60) for i in range(5)])


class SplitTests(unittest.TestCase):
    def test_split_baseline(self):
        # Three older days, then a clear gap, then the recent session: the
        # recent window is unambiguous.
        start = time.time() - 10 * DAY
        sessions = [tv_session(f"s{d}", start + d * DAY) for d in range(3)]
        sessions.append(tv_session("recent", start + 9 * DAY))
        baseline, observation = split_baseline(sessions, observation_days=1.0)
        self.assertEqual(len(baseline), 3)
        self.assertEqual(len(observation), 1)
        self.assertEqual(observation[0].session_id, "recent")

    def test_split_boundary_is_inclusive(self):
        # A session exactly `observation_days` before the latest falls in
        # the observation window, not the baseline.
        start = time.time() - 3 * DAY
        sessions = [tv_session(f"s{d}", start + d * DAY) for d in range(3)]
        baseline, observation = split_baseline(sessions, observation_days=1.0)
        self.assertEqual([s.session_id for s in observation], ["s1", "s2"])
        self.assertEqual([s.session_id for s in baseline], ["s0"])

    def test_empty(self):
        self.assertEqual(split_baseline([]), ([], []))


class AnomalyTests(unittest.TestCase):
    def setUp(self):
        self.start = time.time() - 6 * DAY
        # Four baseline days with the TV at 19:00.
        self.sessions = [tv_session(f"b{d}", self.start + d * DAY) for d in range(4)]

    def test_missing_regular(self):
        # Observation day: a session at the TV's usual hour, but no TV.
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address="PR:02", name="Printer", rssi=-75,
                                seen_at=at_hour(obs, 19) + i * 60) for i in range(3)]))
        anomalies = find_anomalies(self.sessions)
        missing = [a for a in anomalies if a.kind == "missing-regular"]
        self.assertEqual(len(missing), 1)
        self.assertEqual(missing[0].label, "Samsung QLED TV")
        self.assertIn("did not appear", missing[0].detail)

    def test_present_regular_is_not_missing(self):
        self.sessions.append(tv_session("o", self.start + 5 * DAY))
        anomalies = find_anomalies(self.sessions)
        self.assertEqual([a for a in anomalies if a.kind == "missing-regular"], [])

    def test_missing_only_when_expected_by_hour(self):
        # Observation at 04:00 — nowhere near the TV's 19:00 habit, so its
        # absence is not flagged.
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address="PR:02", name="Printer", rssi=-75,
                                seen_at=at_hour(obs, 4) + i * 60) for i in range(3)]))
        anomalies = find_anomalies(self.sessions)
        self.assertEqual([a for a in anomalies if a.kind == "missing-regular"], [])

    def test_new_at_odd_hour(self):
        # A brand-new, stable-address device at 03:00, an hour that is
        # quiet in the baseline.
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address="DA:AA:BB:CC:DD:EE", name="Prowler",
                                rssi=-55, seen_at=at_hour(obs, 3) + i * 60)
                       for i in range(4)]
                      + tv_session("x", obs).sightings))
        anomalies = find_anomalies(self.sessions)
        odd = [a for a in anomalies if a.kind == "new-at-odd-hour"]
        self.assertEqual(len(odd), 1)
        self.assertEqual(odd[0].label, "Prowler")
        self.assertIn("quiet", odd[0].detail)

    def test_new_at_busy_hour_is_not_flagged(self):
        # Same new device, but at 19:00 (the busy hour) — just a visitor.
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address="DA:AA:BB:CC:DD:EE", name="Visitor",
                                rssi=-55, seen_at=at_hour(obs, 19) + i * 60)
                       for i in range(4)]
                      + tv_session("x", obs).sightings))
        anomalies = find_anomalies(self.sessions)
        self.assertEqual([a for a in anomalies if a.kind == "new-at-odd-hour"], [])

    def test_rotating_device_is_not_flagged_either_way(self):
        # A rotating phone (resolvable-private address) at 03:00 is "new"
        # every epoch by construction — the detector stays silent rather
        # than cry wolf at the epoch boundary.
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address=f"7B:00:00:00:00:{i:02X}", name=None,
                                rssi=-55, address_type="random",
                                manufacturer_data={APPLE: IPHONE_NEARBY},
                                seen_at=at_hour(obs, 3) + i * 60) for i in range(4)]
                      + tv_session("x", obs).sightings))
        anomalies = find_anomalies(self.sessions)
        self.assertEqual([a for a in anomalies if a.kind == "new-at-odd-hour"], [])

    def test_too_little_baseline_is_silent(self):
        thin = [tv_session("b0", self.start), tv_session("o", self.start + DAY)]
        self.assertEqual(find_anomalies(thin), [])

    def test_format(self):
        obs = self.start + 5 * DAY
        self.sessions.append(Session(
            session_id="o", label="home", post="mac",
            sightings=[Sighting(address="PR:02", name="Printer", rssi=-75,
                                seen_at=at_hour(obs, 19) + i * 60) for i in range(3)]))
        text = format_anomalies(find_anomalies(self.sessions))
        self.assertIn("Missing regulars", text)
        self.assertIn("prompts to look", text)
        self.assertIn("Not enough history", format_anomalies([], had_baseline=False))
        self.assertIn("Nothing out of the ordinary", format_anomalies([]))


if __name__ == "__main__":
    unittest.main()
