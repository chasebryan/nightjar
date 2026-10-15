import json
import os
import tempfile
import unittest
from pathlib import Path

from nightjar.history import expand_paths, filter_sessions, load_log, load_sessions
from nightjar.registry import Sighting

from .helpers import BASE, HOUR


def write_log(lines, directory=None, name=None):
    if directory is None:
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False,
                                         encoding="utf-8") as fh:
            path = fh.name
    else:
        path = str(Path(directory) / (name or "log.jsonl"))
    with open(path, "w", encoding="utf-8") as fh:
        for line in lines:
            fh.write((json.dumps(line) if not isinstance(line, str) else line) + "\n")
    return path


def sighting_line(when, address="AA:BB"):
    return Sighting(address=address, name=None, rssi=-60,
                    seen_at=when).to_dict()


class HistoryTests(unittest.TestCase):
    def test_headers_define_labeled_sessions(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home",
             "started_at": BASE, "scan_mode": "passive"},
            sighting_line(BASE + 10),
            sighting_line(BASE + 20),
            {"type": "session", "session_id": "s2", "label": "office",
             "started_at": BASE + 90000},
            sighting_line(BASE + 90010),
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 2)
        self.assertEqual(sessions[0].label, "home")
        self.assertEqual(sessions[0].scan_mode, "passive")
        self.assertEqual(len(sessions[0].sightings), 2)
        self.assertEqual(sessions[0].started_at, BASE)  # the header, not the first sighting
        self.assertEqual(sessions[1].label, "office")
        self.assertEqual(sessions[1].session_id, "s2")

    def test_legacy_logs_split_on_gaps(self):
        path = write_log([
            sighting_line(BASE),
            sighting_line(BASE + 60),
            sighting_line(BASE + 3 * HOUR),  # 3h later: new session
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 2)
        self.assertIsNone(sessions[0].label)
        self.assertFalse(sessions[0].has_header)

    def test_headed_sessions_never_gap_split(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
            sighting_line(BASE + 3 * HOUR),  # a quiet spell, still one run
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 1)
        self.assertEqual(len(sessions[0].sightings), 2)

    def test_footer_closes_a_session_and_sets_its_end(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
            {"type": "session_end", "session_id": "s1", "ended_at": BASE + 600},
            sighting_line(BASE + 700),  # orphan after the footer: legacy session
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 2)
        self.assertEqual(sessions[0].ended_at, BASE + 600)
        self.assertEqual(sessions[0].span_seconds, 600)
        self.assertFalse(sessions[1].has_header)

    def test_empty_headed_session_is_kept(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            {"type": "session_end", "session_id": "s1", "ended_at": BASE + 60},
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 1)
        self.assertEqual(sessions[0].sightings, [])
        self.assertEqual(sessions[0].started_at, BASE)
        self.assertEqual(sessions[0].span_seconds, 60)

    def test_corrupt_lines_are_skipped_and_counted(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
            '{"type": "sighting", "seen_at": 17',   # cut off mid-write
            "not json at all",
            {"type": "sighting", "seen_at": BASE + 20},  # no address
            {"type": "mystery", "x": 1},
            sighting_line(BASE + 30),
        ])
        report = load_log([path])
        self.assertEqual(report.skipped_lines, 3)
        self.assertEqual(report.unknown_records, 1)
        self.assertEqual(report.sighting_count, 2)
        self.assertEqual(len(report.sessions), 1)

    def test_alerts_attach_to_their_session(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
            {"type": "alert", "seen_at": BASE + 11, "kind": "new-device", "text": "hi"},
        ])
        report = load_log([path])
        self.assertEqual(report.alert_count, 1)
        self.assertEqual(report.sessions[0].alerts[0]["text"], "hi")

    def test_multiple_files_combine_in_time_order(self):
        a = write_log([sighting_line(BASE + 5000)])
        b = write_log([sighting_line(BASE)])
        sessions = load_sessions([a, b])
        self.assertEqual(sessions[0].sightings[0].seen_at, BASE)
        self.assertTrue(Path(a).exists() and Path(b).exists())
        self.assertNotEqual(sessions[0].source, sessions[1].source)

    def test_directories_and_globs_expand(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_log([sighting_line(BASE)], tmp, "a.jsonl")
            write_log([sighting_line(BASE + 1)], tmp, "b.ndjson")
            Path(tmp, "notes.txt").write_text("not a log", encoding="utf-8")
            files = expand_paths([tmp])
            self.assertEqual([Path(f).name for f in files], ["a.jsonl", "b.ndjson"])
            globbed = expand_paths([os.path.join(tmp, "*.jsonl")])
            self.assertEqual([Path(f).name for f in globbed], ["a.jsonl"])
            self.assertEqual(len(load_sessions([tmp])), 2)

    def test_filter_sessions(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
            {"type": "session", "session_id": "s2", "label": "Office Wifi",
             "started_at": BASE + 90000},
            sighting_line(BASE + 90010),
        ])
        sessions = load_sessions([path])
        self.assertEqual([s.label for s in filter_sessions(sessions, place="office")],
                         ["Office Wifi"])
        self.assertEqual(len(filter_sessions(sessions, since=BASE + 1)), 1)
        self.assertEqual(len(filter_sessions(sessions, since=BASE - 1)), 2)

    def test_session_to_dict(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home", "started_at": BASE},
            sighting_line(BASE + 10),
        ])
        doc = load_sessions([path])[0].to_dict()
        self.assertEqual(doc["session_id"], "s1")
        self.assertEqual(doc["sightings"], 1)
        json.dumps(doc)


if __name__ == "__main__":
    unittest.main()
