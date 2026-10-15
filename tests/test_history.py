import json
import tempfile
import unittest
from pathlib import Path

from nightjar.history import load_sessions
from nightjar.registry import Sighting

BASE = 1_700_000_000.0


def write_log(lines):
    fh = tempfile.NamedTemporaryFile(
        "w", suffix=".jsonl", delete=False, encoding="utf-8")
    for line in lines:
        fh.write(json.dumps(line) + "\n")
    fh.close()
    return fh.name


def sighting_line(when, address="AA:BB"):
    return Sighting(address=address, name=None, rssi=-60,
                    seen_at=when).to_dict()


class HistoryTests(unittest.TestCase):
    def test_headers_define_labeled_sessions(self):
        path = write_log([
            {"type": "session", "session_id": "s1", "label": "home",
             "started_at": BASE},
            sighting_line(BASE + 10),
            sighting_line(BASE + 20),
            {"type": "session", "session_id": "s2", "label": "office",
             "started_at": BASE + 90000},
            sighting_line(BASE + 90010),
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 2)
        self.assertEqual(sessions[0].label, "home")
        self.assertEqual(len(sessions[0].sightings), 2)
        self.assertEqual(sessions[1].label, "office")

    def test_legacy_logs_split_on_gaps(self):
        path = write_log([
            sighting_line(BASE),
            sighting_line(BASE + 60),
            sighting_line(BASE + 3 * 3600),  # 3h later: new session
        ])
        sessions = load_sessions([path])
        self.assertEqual(len(sessions), 2)
        self.assertIsNone(sessions[0].label)

    def test_multiple_files_combine_in_time_order(self):
        a = write_log([sighting_line(BASE + 5000)])
        b = write_log([sighting_line(BASE)])
        sessions = load_sessions([a, b])
        self.assertEqual(sessions[0].sightings[0].seen_at, BASE)
        self.assertTrue(Path(a).exists() and Path(b).exists())


if __name__ == "__main__":
    unittest.main()
