import unittest

from nightjar.registry import Sighting
from nightjar.watch import AlertEngine, DiscordAlerter

BASE = 1_700_000_000.0
TILE_UUID = "0000feed-0000-1000-8000-00805f9b34fb"


def s(address, when, **kw):
    base = dict(name=None, rssi=-60, manufacturer_data={}, service_uuids=[])
    base.update(kw)
    return Sighting(address=address, seen_at=when, **base)


class AlertEngineTests(unittest.TestCase):
    def test_new_device_alert_waits_for_warmup(self):
        engine = AlertEngine(warmup_seconds=120)
        self.assertEqual(engine.observe(s("TV:01", BASE, name="TV")), [])
        alerts = engine.observe(s("XX:99", BASE + 200, name="Mystery Box"))
        self.assertEqual(len(alerts), 1)
        self.assertIn("New device appeared", alerts[0])

    def test_new_device_alert_can_be_disabled(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        self.assertEqual(engine.observe(s("XX:99", BASE, name="Box")), [])

    def test_tracker_alert_after_travelling(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        tag = dict(service_uuids=[TILE_UUID])
        self.assertEqual(engine.observe(s("D4:61", BASE, **tag)), [])
        self.assertEqual(engine.observe(s("D4:61", BASE + 1800, **tag)), [])
        alerts = engine.observe(s("D4:61", BASE + 3700, **tag))
        self.assertEqual(len(alerts), 1)
        self.assertIn("Tracker suspect", alerts[0])
        # and it does not cry twice
        self.assertEqual(engine.observe(s("D4:61", BASE + 3800, **tag)), [])

    def test_quiet_far_tracker_does_not_alert(self):
        engine = AlertEngine(alert_new=False, warmup_seconds=0)
        tag = dict(service_uuids=[TILE_UUID], rssi=-95)
        engine.observe(s("D4:61", BASE, **tag))
        engine.observe(s("D4:61", BASE + 3700, **tag))
        self.assertEqual(engine.observe(s("D4:61", BASE + 7400, **tag)), [])


class AlerterTests(unittest.TestCase):
    def test_send_posts_content(self):
        seen = {}

        def opener(request):
            seen["url"] = request.full_url
            seen["body"] = request.data.decode("utf-8")
            return 204

        alerter = DiscordAlerter("https://discord.test/hook", opener=opener)
        self.assertTrue(alerter.send("hello"))
        self.assertIn("hello", seen["body"])

    def test_no_webhook_no_send(self):
        alerter = DiscordAlerter(None, opener=lambda req: 200)
        alerter.url = None
        self.assertFalse(alerter.send("hello"))

    def test_failed_post_is_swallowed(self):
        def opener(request):
            raise OSError("network down")
        alerter = DiscordAlerter("https://discord.test/hook", opener=opener)
        self.assertFalse(alerter.send("hello"))


if __name__ == "__main__":
    unittest.main()
