import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from nightjar import __version__
from nightjar.cli import main


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(argv)
    return code, out.getvalue(), err.getvalue()


class CliTests(unittest.TestCase):
    def test_scan_report_trackers_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = str(Path(tmp) / "sightings.jsonl")
            code, out, _ = run(["scan", "--simulate", "--duration", "2",
                                "--seed", "3", "--label", "home",
                                "--log", log, "--quiet"])
            self.assertEqual(code, 0)
            self.assertIn("simulated neighbourhood @ home", out)
            self.assertIn("devices", out)
            lines = Path(log).read_text(encoding="utf-8").splitlines()
            header = json.loads(lines[0])
            self.assertEqual(header["type"], "session")
            self.assertEqual(header["label"], "home")
            self.assertEqual(header["label_source"], "manual")
            self.assertEqual(header["scan_mode"], "simulated")
            self.assertEqual(json.loads(lines[-1])["type"], "session_end")
            self.assertGreater(len(lines), 5)

            code, out, _ = run(["report", "--log", log])
            self.assertEqual(code, 0)
            self.assertIn("Pattern of life", out)
            code, out, _ = run(["trackers", log])
            self.assertEqual(code, 0)
            code, out, _ = run(["show", "airpods", log])
            self.assertEqual(code, 0)
            self.assertIn("AirPods Pro", out)
            code, _, err = run(["show", "nothing-like-this", log])
            self.assertEqual(code, 1)
            self.assertIn("nothing in these logs", err)

    def test_watch_simulated_run(self):
        code, out, _ = run(["watch", "--simulate", "--duration", "1",
                            "--seed", "4", "--label", "home", "--quiet",
                            "--warmup", "0"])
        self.assertEqual(code, 0)
        self.assertIn("ALERT", out)
        self.assertIn("New device appeared", out)

    def test_scan_live_mode_runs(self):
        code, out, _ = run(["scan", "--simulate", "--duration", "2",
                            "--seed", "4", "--label", "home", "--live"])
        self.assertEqual(code, 0)
        self.assertIn("live radar", out)

    def test_bare_flags_default_to_scan(self):
        with tempfile.TemporaryDirectory() as tmp:
            out_file = str(Path(tmp) / "devices.json")
            code, out, _ = run(["--simulate", "--duration", "1", "--seed", "5",
                                "--out", out_file, "--quiet", "--addresses"])
            self.assertEqual(code, 0)
            data = json.loads(Path(out_file).read_text(encoding="utf-8"))
            self.assertGreater(data["device_count"], 0)
            self.assertGreater(data["identity_count"], 0)
            self.assertEqual(data["scan_mode"], "simulated")
            self.assertIn("addresses,", out)

    def test_json_event_stream(self):
        code, out, _ = run(["scan", "--simulate", "--duration", "1", "--seed", "6",
                            "--label", "home", "--json"])
        self.assertEqual(code, 0)
        events = [json.loads(line) for line in out.splitlines()]
        self.assertEqual(events[0]["event"], "start")
        self.assertEqual(events[0]["mode"], "simulated")
        self.assertEqual(events[-1]["event"], "summary")
        self.assertIn("new-device", {e["event"] for e in events})

    def test_live_and_json_do_not_mix(self):
        code, _, err = run(["scan", "--simulate", "--live", "--json", "--duration", "0.1"])
        self.assertEqual(code, 2)
        self.assertIn("don't mix", err)

    def test_version_and_help_are_reachable(self):
        with self.assertRaises(SystemExit) as ctx:
            run(["--version"])
        self.assertEqual(ctx.exception.code, 0)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(SystemExit):
            main(["--help"])
        self.assertIn("scan", out.getvalue())
        self.assertIn("trackers", out.getvalue())
        self.assertNotIn("--simulate", out.getvalue())  # top-level, not scan's help
        self.assertEqual(__version__, "2.0.0")

    def test_demo_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "demo.jsonl")
            code, out, _ = run(["demo", "--out", path, "--days", "1", "--seed", "1"])
            self.assertEqual(code, 0)
            self.assertIn("wrote 3 demo sessions", out)
            self.assertIn("Pattern of life", out)
            self.assertIn("suspect(s)", out)
            code, out, _ = run(["demo", "--out", path, "--days", "1", "--no-report"])
            self.assertEqual(code, 0)
            self.assertIn("try:", out)

    def test_report_filters_and_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "demo.jsonl")
            run(["demo", "--out", path, "--days", "1", "--seed", "2", "--no-report"])
            code, out, _ = run(["report", path, "--place", "office", "--json",
                                "--min-sessions", "1", "--sort", "last"])
            self.assertEqual(code, 0)
            doc = json.loads(out)
            self.assertEqual([s["label"] for s in doc["sessions"]], ["office"])
            self.assertTrue(doc["devices"])
            code, out, _ = run(["report", path, "--wide"])
            self.assertEqual(code, 0)
            self.assertIn("avg stay", out)
            code, out, _ = run(["trackers", path, "--json", "--ignore", "Find My"])
            self.assertEqual(json.loads(out)["suspects"], [])
            code, _, err = run(["report", path, "--place", "nowhere"])
            self.assertEqual(code, 1)
            self.assertIn("no sessions", err)

    def test_log_from_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "env.jsonl")
            with mock.patch.dict(os.environ, {"NIGHTJAR_LOG": path, "NIGHTJAR_LABEL": "shed"}):
                code, _, _ = run(["scan", "--simulate", "--duration", "1", "--seed", "8",
                                  "--quiet"])
                self.assertEqual(code, 0)
                header = json.loads(Path(path).read_text(encoding="utf-8").splitlines()[0])
                self.assertEqual(header["label"], "shed")
                self.assertEqual(header["label_source"], "env")
                code, out, _ = run(["report"])
                self.assertEqual(code, 0)
                self.assertIn("places: shed", out)

    def test_no_logs_is_an_error(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            code, _, err = run(["report"])
        self.assertEqual(code, 1)
        self.assertIn("no logs given", err)
        code, _, err = run(["report", "/nonexistent/*.jsonl"])
        self.assertEqual(code, 1)
        self.assertIn("no log files matched", err)


if __name__ == "__main__":
    unittest.main()
