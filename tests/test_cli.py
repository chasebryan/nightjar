import json
import tempfile
import unittest
from pathlib import Path

from nightjar.cli import main


class CliTests(unittest.TestCase):
    def test_scan_report_trackers_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = str(Path(tmp) / "sightings.jsonl")
            code = main(["scan", "--simulate", "--duration", "2",
                         "--seed", "3", "--label", "home",
                         "--log", log, "--quiet"])
            self.assertEqual(code, 0)
            lines = Path(log).read_text(encoding="utf-8").splitlines()
            header = json.loads(lines[0])
            self.assertEqual(header["type"], "session")
            self.assertEqual(header["label"], "home")
            self.assertGreater(len(lines), 5)

            self.assertEqual(main(["report", "--log", log]), 0)
            self.assertEqual(main(["trackers", "--log", log]), 0)

    def test_bare_flags_default_to_scan(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = str(Path(tmp) / "devices.json")
            code = main(["--simulate", "--duration", "1", "--seed", "5",
                         "--out", out, "--quiet"])
            self.assertEqual(code, 0)
            data = json.loads(Path(out).read_text(encoding="utf-8"))
            self.assertGreater(data["device_count"], 0)


if __name__ == "__main__":
    unittest.main()
