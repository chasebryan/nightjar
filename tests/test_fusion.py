import json
import tempfile
import unittest

from nightjar.history import Session, load_log, load_sessions, posts_of
from nightjar.patterns import analyze
from nightjar.trackers import analyze_trackers, find_suspects

from .helpers import BASE, HOUR, TILE_UUID, sighting


def tag(addr, when, **kw):
    return sighting(addr, when, service_uuids=[TILE_UUID], **kw)


def session(sid, label, post, sightings):
    return Session(session_id=sid, label=label, post=post,
                   sightings=sorted(sightings, key=lambda x: x.seen_at))


class PostLoadingTests(unittest.TestCase):
    def _write(self, records):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False,
                                         encoding="utf-8") as fh:
            for rec in records:
                fh.write(json.dumps(rec) + "\n")
            return fh.name

    def test_post_read_from_header(self):
        path = self._write([
            {"type": "session", "session_id": "s1", "label": "home",
             "post": "mac", "started_at": BASE},
            sighting("AA:BB", BASE + 1).to_dict(),
        ])
        sessions = load_sessions([path])
        self.assertEqual(sessions[0].post, "mac")
        self.assertEqual(sessions[0].where, "mac @ home")
        self.assertEqual(sessions[0].to_dict()["post"], "mac")

    def test_default_post_fills_only_headerless(self):
        path = self._write([
            {"type": "session", "session_id": "s1", "label": "home",
             "post": "mac", "started_at": BASE},
            sighting("AA:BB", BASE + 1).to_dict(),
        ])
        # Header names its post, so default_post does not override it.
        sessions = load_sessions([path], default_post="elsewhere")
        self.assertEqual(sessions[0].post, "mac")

    def test_default_post_applies_to_legacy_logs(self):
        path = self._write([sighting("AA:BB", BASE).to_dict()])
        sessions = load_sessions([path], default_post="door")
        self.assertEqual(sessions[0].post, "door")
        self.assertEqual(sessions[0].where, "door")  # no label

    def test_post_by_path(self):
        a = self._write([sighting("AA:BB", BASE).to_dict()])
        b = self._write([sighting("CC:DD", BASE + 1).to_dict()])
        report = load_log([a, b], post_by_path={a: "mac", b: "phone"})
        posts = {s.post for s in report.sessions}
        self.assertEqual(posts, {"mac", "phone"})

    def test_posts_of(self):
        sessions = [session("a", "home", "mac", []),
                    session("b", "office", "phone", []),
                    session("c", "home", "mac", [])]
        self.assertEqual(posts_of(sessions), ["mac", "phone"])


class PatternPostsTests(unittest.TestCase):
    def test_pattern_records_which_posts_heard_a_device(self):
        sessions = [
            session("h", "home", "mac",
                    [sighting("TV:01", BASE + i, name="TV") for i in range(3)]),
            session("o", "office", "phone",
                    [sighting("TV:01", BASE + HOUR + i, name="TV") for i in range(3)]),
        ]
        patterns = analyze(sessions)
        tv = next(p for p in patterns if p.identity.label == "TV")
        self.assertEqual(tv.posts, {"mac", "phone"})
        self.assertEqual(tv.to_dict()["posts"], ["mac", "phone"])


class ExonerationTests(unittest.TestCase):
    def test_simultaneous_two_places_is_cleared(self):
        # One tag heard at home (mac) and office (phone) in the same window:
        # it cannot be a single object riding with the listener.
        home = session("h", "home", "mac",
                       [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        office = session("o", "office", "phone",
                         [tag("D4:61", BASE + 5 * 60 + m * 60) for m in range(0, 61, 10)])
        report = analyze_trackers([home, office])
        self.assertEqual(report.suspects, [])
        self.assertEqual(len(report.exonerations), 1)
        exo = report.exonerations[0]
        self.assertEqual(exo.places, ["home", "office"])
        self.assertEqual(exo.posts, ["mac", "phone"])
        self.assertIn("same moment", exo.reason)
        json.dumps(report.to_dict())

    def test_sequential_at_two_places_still_a_suspect(self):
        # Carried from home to office a day later: genuine following shape.
        home = session("h", "home", "mac",
                       [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        office = session("o", "office", "phone",
                         [tag("D4:61", BASE + 26 * HOUR + m * 60) for m in range(0, 61, 10)])
        report = analyze_trackers([home, office])
        self.assertEqual(report.exonerations, [])
        self.assertEqual(len(report.suspects), 1)
        self.assertEqual(report.suspects[0].posts, ["mac", "phone"])

    def test_same_place_two_posts_is_not_exoneration(self):
        # Two posts in the same room both hear the tag: that is not two
        # places at once, so it is not cleared.
        a = session("a", "home", "mac",
                    [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        b = session("b", "home", "pi",
                    [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        report = analyze_trackers([a, b])
        self.assertEqual(report.exonerations, [])

    def test_find_suspects_wrapper_excludes_exonerated(self):
        home = session("h", "home", "mac",
                       [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        office = session("o", "office", "phone",
                         [tag("D4:61", BASE + 5 * 60 + m * 60) for m in range(0, 61, 10)])
        self.assertEqual(find_suspects([home, office]), [])

    def test_postless_logs_behave_like_before(self):
        # No posts: no fusion, identical to 2.0 — the carried tag is a suspect.
        home = session("h", "home", None,
                       [tag("D4:61", BASE + m * 60) for m in range(0, 61, 10)])
        office = session("o", "office", None,
                         [tag("D4:61", BASE + 26 * HOUR + m * 60) for m in range(0, 61, 10)])
        report = analyze_trackers([home, office])
        self.assertEqual(report.exonerations, [])
        self.assertEqual(len(report.suspects), 1)


if __name__ == "__main__":
    unittest.main()
