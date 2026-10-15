import json
import tempfile
import unittest
from pathlib import Path

from nightjar.history import load_log
from nightjar.post import ListeningPost, SessionLog
from nightjar.watch import AlertDispatcher, AlertEngine

from .helpers import AIRPODS_PRO, APPLE, BASE, TILE_UUID, sighting


class SessionLogTests(unittest.TestCase):
    def test_header_sightings_alerts_footer(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "log.jsonl")
            log = SessionLog(path, label="home", label_source="manual")
            self.assertFalse(log.is_open)
            log.open("passive")
            self.assertTrue(log.is_open)
            log.sighting(sighting("AA:01", BASE))
            log.open("active")  # a second open is a no-op
            log.close()
            log.close()  # idempotent
            records = [json.loads(line) for line in
                       Path(path).read_text(encoding="utf-8").splitlines()]
            self.assertEqual([r["type"] for r in records],
                             ["session", "sighting", "session_end"])
            header = records[0]
            self.assertEqual(header["label"], "home")
            self.assertEqual(header["scan_mode"], "passive")
            self.assertEqual(header["format"], 1)
            self.assertEqual(len(header["session_id"]), 12)
            self.assertEqual(records[-1]["sightings"], 1)
            self.assertEqual(records[-1]["session_id"], header["session_id"])
            report = load_log([path])
            self.assertEqual(len(report.sessions), 1)
            self.assertEqual(report.sessions[0].scan_mode, "passive")


class ListeningPostTests(unittest.TestCase):
    def test_observe_fills_registry_identities_and_kinds(self):
        seen = []
        post = ListeningPost(on_observation=seen.append)
        post.started("simulated")
        first = post.observe(sighting("AA:01", BASE, manufacturer_data={APPLE: AIRPODS_PRO}))
        second = post.observe(sighting("AA:01", BASE + 1,
                                       manufacturer_data={APPLE: AIRPODS_PRO}))
        self.assertTrue(first.new_address and first.new_identity)
        self.assertFalse(second.new_address or second.new_identity)
        self.assertEqual(first.record.kind, "AirPods Pro")
        self.assertIn("L 80%", first.record.details[0])
        self.assertEqual(first.identity.kind, "AirPods Pro")
        self.assertEqual(len(seen), 2)
        self.assertEqual(post.scan_mode, "simulated")
        post.close()

    def test_alerts_flow_to_log_and_dispatcher(self):
        delivered = []
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "log.jsonl")
            log = SessionLog(path, label=None, label_source=None)
            engine = AlertEngine(warmup_seconds=0)
            dispatcher = AlertDispatcher([lambda a: delivered.append(a.kind) or True])
            post = ListeningPost(log=log, engine=engine, dispatcher=dispatcher)
            post.started("active")
            obs = post.observe(sighting("D4:61", BASE, service_uuids=[TILE_UUID]))
            self.assertEqual([a.kind for a in obs.alerts], ["new-device"])
            self.assertIs(post.resolver, engine.resolver)
            post.close()
            records = [json.loads(line) for line in
                       Path(path).read_text(encoding="utf-8").splitlines()]
            self.assertIn("alert", [r["type"] for r in records])
            self.assertEqual(delivered, ["new-device"])
            self.assertEqual(len(post.alerts), 1)


if __name__ == "__main__":
    unittest.main()
