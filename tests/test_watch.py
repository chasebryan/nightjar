import json
import os
import threading
import unittest
from unittest import mock

from nightjar.watch import (
    Alert,
    AlertDispatcher,
    AlertEngine,
    DiscordAlerter,
    WebhookAlerter,
    guess_webhook_format,
)

from .helpers import AIRTAG_SEPARATED, AIRTAG_WITH_OWNER, APPLE, BASE, TILE_UUID, sighting


class AlertEngineTests(unittest.TestCase):
    def test_new_device_alert_waits_for_warmup(self):
        engine = AlertEngine(warmup_seconds=120)
        self.assertEqual(engine.observe(sighting("TV:01", BASE, name="TV")), [])
        alerts = engine.observe(sighting("XX:99", BASE + 200, name="Mystery Box"))
        self.assertEqual(len(alerts), 1)
        alert = alerts[0]
        self.assertIsInstance(alert, Alert)
        self.assertEqual(alert.kind, "new-device")
        self.assertIn("New device appeared: Mystery Box (Named device)", alert.text)
        self.assertEqual(str(alert), alert.text)
        self.assertEqual(alert.address, "XX:99")
        doc = alert.to_dict()
        self.assertEqual(doc["type"], "alert")
        json.dumps(doc)

    def test_headline_is_not_doubled_for_unnamed_devices(self):
        engine = AlertEngine(warmup_seconds=0)
        alerts = engine.observe(sighting("D4:61", BASE, service_uuids=[TILE_UUID]))
        self.assertIn("appeared: Tile tracker at D4:61", alerts[0].text)
        self.assertNotIn("Tile tracker (Tile tracker)", alerts[0].text)

    def test_new_device_alert_can_be_disabled(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        self.assertEqual(engine.observe(sighting("XX:99", BASE, name="Box")), [])

    def test_tracker_alert_after_travelling(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        tag = {"service_uuids": [TILE_UUID]}
        self.assertEqual(engine.observe(sighting("D4:61", BASE, **tag)), [])
        self.assertEqual(engine.observe(sighting("D4:61", BASE + 1800, **tag)), [])
        alerts = engine.observe(sighting("D4:61", BASE + 3700, **tag))
        self.assertEqual(len(alerts), 1)
        self.assertEqual(alerts[0].kind, "tracker")
        self.assertIn("Tracker suspect staying near you: Tile tracker", alerts[0].text)
        self.assertEqual(alerts[0].data["hours"], 2)
        # and it does not cry twice
        self.assertEqual(engine.observe(sighting("D4:61", BASE + 3800, **tag)), [])

    def test_quiet_far_tracker_does_not_alert(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        tag = {"service_uuids": [TILE_UUID], "rssi": -95}
        engine.observe(sighting("D4:61", BASE, **tag))
        engine.observe(sighting("D4:61", BASE + 3700, **tag))
        self.assertEqual(engine.observe(sighting("D4:61", BASE + 7400, **tag)), [])

    def test_findmy_with_owner_never_trips_the_tracker_alert(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        tag = {"manufacturer_data": {APPLE: AIRTAG_WITH_OWNER}}
        for offset in (0, 1800, 3700, 7400):
            self.assertEqual(engine.observe(sighting("F2:19", BASE + offset, **tag)), [])
        separated = {"manufacturer_data": {APPLE: AIRTAG_SEPARATED}}
        alerts = []
        for offset in (0, 1800, 3700):
            alerts += engine.observe(sighting("E7:04", BASE + offset, **separated))
        self.assertEqual([a.kind for a in alerts], ["tracker"])

    def test_ignored_devices_are_silent(self):
        engine = AlertEngine(warmup_seconds=0, ignore=["d4:61"])
        tag = {"service_uuids": [TILE_UUID]}
        alerts = []
        for offset in (0, 1800, 3700):
            alerts += engine.observe(sighting("D4:61", BASE + offset, **tag))
        self.assertEqual(alerts, [])
        self.assertEqual(len(engine.observe(sighting("AA:00", BASE + 3800, name="Other"))), 1)


class WebhookTests(unittest.TestCase):
    def _capture(self, status=204):
        seen = {}

        def opener(request):
            seen["url"] = request.full_url
            seen["body"] = request.data.decode("utf-8")
            seen["headers"] = {k.lower(): v for k, v in request.header_items()}
            return status
        return seen, opener

    def test_discord_posts_content(self):
        seen, opener = self._capture()
        alerter = WebhookAlerter("https://discord.com/api/webhooks/1/x", opener=opener)
        self.assertEqual(alerter.format, "discord")
        self.assertTrue(alerter.send("hello"))
        self.assertEqual(json.loads(seen["body"]), {"content": "hello"})

    def test_slack_posts_text(self):
        seen, opener = self._capture()
        alerter = WebhookAlerter("https://hooks.slack.com/services/T/B/x", opener=opener)
        self.assertEqual(alerter.format, "slack")
        alerter.send("hello")
        self.assertEqual(json.loads(seen["body"]), {"text": "hello"})

    def test_ntfy_posts_plain_text_with_a_title(self):
        seen, opener = self._capture()
        alerter = WebhookAlerter("https://ntfy.sh/nightjar", opener=opener)
        self.assertEqual(alerter.format, "ntfy")
        alerter.send("hello")
        self.assertEqual(seen["body"], "hello")
        self.assertEqual(seen["headers"]["title"], "nightjar")

    def test_generic_json_carries_the_alert(self):
        seen, opener = self._capture()
        alerter = WebhookAlerter("https://example.org/hook", opener=opener)
        self.assertEqual(alerter.format, "json")
        alert = Alert(kind="tracker", text="t", seen_at=BASE, identity_key="k",
                      label="l", device_kind="d", address="a")
        self.assertTrue(alerter(alert))
        body = json.loads(seen["body"])
        self.assertEqual(body["text"], "nightjar: t")
        self.assertEqual(body["alert"]["kind"], "tracker")

    def test_explicit_and_environment_format(self):
        opener = self._capture()[1]
        alerter = WebhookAlerter("https://example.org/hook", opener=opener, fmt="discord")
        self.assertEqual(alerter.format, "discord")
        with mock.patch.dict(os.environ, {"NIGHTJAR_WEBHOOK_URL": "https://ntfy.sh/t",
                                          "NIGHTJAR_WEBHOOK_FORMAT": "slack"}):
            from_env = WebhookAlerter(opener=opener)
        self.assertEqual(from_env.url, "https://ntfy.sh/t")
        self.assertEqual(from_env.format, "slack")
        self.assertEqual(guess_webhook_format(None), "json")

    def test_no_webhook_no_send(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            alerter = DiscordAlerter(None, opener=lambda req: 200)
        self.assertIsNone(alerter.url)
        self.assertFalse(alerter.send("hello"))

    def test_failed_post_is_swallowed(self):
        def opener(request):
            raise OSError("network down")
        alerter = DiscordAlerter("https://discord.test/hook", opener=opener)
        self.assertFalse(alerter.send("hello"))
        bad_status = self._capture(status=500)[1]
        self.assertFalse(WebhookAlerter("https://x.test/h", opener=bad_status).send("x"))


class DispatcherTests(unittest.TestCase):
    def test_sinks_run_off_the_calling_thread(self):
        seen = []
        threads = set()
        done = threading.Event()

        def sink(alert):
            seen.append(alert.text)
            threads.add(threading.current_thread().name)
            if len(seen) == 2:
                done.set()
            return True

        def failing(alert):
            raise RuntimeError("boom")

        dispatcher = AlertDispatcher([sink, failing])
        alert = Alert(kind="new-device", text="one", seen_at=BASE, identity_key="k",
                      label="l", device_kind="d", address="a")
        dispatcher.submit(alert)
        dispatcher.submit(Alert(kind="new-device", text="two", seen_at=BASE,
                                identity_key="k", label="l", device_kind="d", address="a"))
        self.assertTrue(done.wait(5))
        dispatcher.close()
        self.assertEqual(seen, ["one", "two"])
        self.assertNotIn(threading.current_thread().name, threads)
        self.assertEqual(dispatcher.delivered, 2)
        self.assertEqual(dispatcher.failed, 2)

    def test_no_sinks_means_no_thread(self):
        dispatcher = AlertDispatcher([])
        dispatcher.submit(Alert(kind="x", text="x", seen_at=BASE, identity_key="k",
                                label="l", device_kind="d", address="a"))
        self.assertIsNone(dispatcher._thread)
        dispatcher.close()


if __name__ == "__main__":
    unittest.main()
