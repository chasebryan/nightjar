"""The post stands guard — watch mode and its alerts.

`scan` answers when you stop it. `watch` speaks when something
happens:

  * a NEW device identity appears (after a warmup window, so the
    devices that were always there don't trigger a flood at start-up)
  * a tracker-shaped identity has travelled with the listener:
    present across several distinct hours, near enough to matter

Alerts print to the console, go into the session log as records of
their own, and — if a webhook is configured (--webhook or the
NIGHTJAR_WEBHOOK_URL environment variable) — are posted to Discord,
Slack, ntfy, or any JSON endpoint. Delivery runs on a background
thread: a slow webhook must never stall the radio. Each alert fires
once per identity — a guard that cries constantly gets ignored, and
this one knows it.
"""

from __future__ import annotations

import json
import os
import queue
import threading
import urllib.parse
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from statistics import median

from .identify import Identity, IdentityResolver
from .registry import Sighting
from .remoteid import describe as describe_drone

WEBHOOK_FORMATS = ("discord", "slack", "ntfy", "json")


@dataclass
class Alert:
    """One thing worth interrupting for."""

    kind: str           # "new-device" | "tracker"
    text: str
    seen_at: float
    identity_key: str
    label: str
    device_kind: str
    address: str
    data: dict = field(default_factory=dict)

    def __str__(self) -> str:
        return self.text

    def to_dict(self) -> dict:
        return {
            "type": "alert",
            "seen_at": self.seen_at,
            "kind": self.kind,
            "text": self.text,
            "identity_key": self.identity_key,
            "label": self.label,
            "device_kind": self.device_kind,
            "address": self.address,
            "data": dict(self.data),
        }


def guess_webhook_format(url: str | None) -> str:
    """Pick a payload shape from the webhook's host."""
    if not url:
        return "json"
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    if "discord" in host:
        return "discord"
    if "slack" in host:
        return "slack"
    if "ntfy" in host:
        return "ntfy"
    return "json"


class WebhookAlerter:
    """Posts alert text to a webhook. Stdlib only.

    Formats: "discord" ({"content"}), "slack" ({"text"}), "ntfy" (plain
    text with a Title header), "json" ({"text", "alert"}). Chosen from
    the URL's host unless given outright.
    """

    def __init__(self, webhook_url: str | None = None, opener=None,
                 fmt: str | None = None):
        self.url = webhook_url or os.environ.get("NIGHTJAR_WEBHOOK_URL")
        fmt = fmt or os.environ.get("NIGHTJAR_WEBHOOK_FORMAT")
        self.format = fmt if fmt in WEBHOOK_FORMATS else guess_webhook_format(self.url)
        self._opener = opener or self._default_opener

    @staticmethod
    def _default_opener(request) -> int:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status

    def build_request(self, text: str, alert: Alert | None = None):
        url = self.url or ""
        if self.format == "ntfy":
            return urllib.request.Request(
                url, data=text.encode("utf-8"),
                headers={"Content-Type": "text/plain; charset=utf-8",
                         "Title": "nightjar"},
                method="POST")
        if self.format == "discord":
            body: dict = {"content": text}
        elif self.format == "slack":
            body = {"text": text}
        else:
            body = {"text": text, "alert": alert.to_dict() if alert else {}}
        return urllib.request.Request(
            url,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

    def send(self, text: str, alert: Alert | None = None) -> bool:
        if not self.url:
            return False
        try:
            return self._opener(self.build_request(text, alert)) < 300
        except Exception:
            return False  # alerting must never kill the watch

    def __call__(self, alert: Alert) -> bool:
        return self.send(f"nightjar: {alert.text}", alert)


DiscordAlerter = WebhookAlerter  # the original name, still honoured


class AlertDispatcher:
    """Runs alert sinks on a background thread, in order, one at a time."""

    def __init__(self, sinks: list[Callable[[Alert], object]] | None = None):
        self.sinks = list(sinks or [])
        self._queue: queue.Queue = queue.Queue()
        self._thread: threading.Thread | None = None
        self.delivered = 0
        self.failed = 0

    def submit(self, alert: Alert) -> None:
        if not self.sinks:
            return
        if self._thread is None:
            self._thread = threading.Thread(target=self._run, name="nightjar-alerts",
                                            daemon=True)
            self._thread.start()
        self._queue.put(alert)

    def _run(self) -> None:
        while True:
            alert = self._queue.get()
            if alert is None:
                return
            for sink in self.sinks:
                try:
                    ok = sink(alert)
                except Exception:
                    ok = False
                if ok is False:
                    self.failed += 1
                else:
                    self.delivered += 1

    def close(self, timeout: float = 5.0) -> None:
        if self._thread is None:
            return
        self._queue.put(None)
        self._thread.join(timeout)
        self._thread = None


class AlertEngine:
    """Decides, sighting by sighting, what is worth interrupting for."""

    # How many sightings of a drone without a usable Location before
    # presence alone is worth one alert (airborne alerts fire at once).
    DRONE_PRESENCE_SIGHTINGS = 4

    def __init__(self, *, alert_new: bool = True,
                 warmup_seconds: float = 120.0,
                 tracker_min_span: float = 45 * 60.0,
                 tracker_min_hours: int = 2,
                 tracker_min_rssi: int = -80,
                 ignore: list[str] | None = None,
                 home: tuple[float, float] | None = None,
                 resolver: IdentityResolver | None = None):
        self.alert_new = alert_new
        self.warmup_seconds = warmup_seconds
        self.tracker_min_span = tracker_min_span
        self.tracker_min_hours = tracker_min_hours
        self.tracker_min_rssi = tracker_min_rssi
        self.ignore = list(ignore or [])
        self.home = home
        self._resolver = resolver or IdentityResolver()
        self._started_at: float | None = None
        self._known: set[str] = set()
        self._tracker_alerted: set[str] = set()
        self._tracker_stats: dict[str, dict] = {}
        self._drone_alerted: set[str] = set()
        self._drone_seen: dict[str, int] = {}

    @property
    def resolver(self) -> IdentityResolver:
        return self._resolver

    def _ignored(self, identity: Identity) -> bool:
        return any(identity.matches(q) for q in self.ignore)

    def observe(self, sighting: Sighting) -> list[Alert]:
        if self._started_at is None:
            self._started_at = sighting.seen_at
        identity = self._resolver.observe(sighting)
        alerts: list[Alert] = []

        if identity.key not in self._known:
            self._known.add(identity.key)
            past_warmup = (sighting.seen_at - self._started_at
                           >= self.warmup_seconds)
            if self.alert_new and past_warmup and not self._ignored(identity):
                detail = f" — {identity.details[0]}" if identity.details else ""
                signal = f", {sighting.rssi} dBm" if sighting.rssi is not None else ""
                alerts.append(Alert(
                    kind="new-device",
                    text=(f"New device appeared: {identity.headline} "
                          f"at {sighting.address}{signal}{detail}"),
                    seen_at=sighting.seen_at, identity_key=identity.key,
                    label=identity.label, device_kind=identity.kind,
                    address=sighting.address,
                    data={"rssi": sighting.rssi, "details": list(identity.details)}))

        if identity.tracker_like and not self._ignored(identity):
            stats = self._tracker_stats.setdefault(
                identity.key,
                {"first": sighting.seen_at, "hours": set(), "rssis": []})
            stats["hours"].add(int(sighting.seen_at // 3600))
            if sighting.rssi is not None:
                stats["rssis"].append(sighting.rssi)
            span = sighting.seen_at - stats["first"]
            loud_enough = (stats["rssis"]
                           and median(stats["rssis"]) >= self.tracker_min_rssi)
            if (identity.key not in self._tracker_alerted
                    and span >= self.tracker_min_span
                    and len(stats["hours"]) >= self.tracker_min_hours
                    and loud_enough):
                self._tracker_alerted.add(identity.key)
                level = int(median(stats["rssis"]))
                alerts.append(Alert(
                    kind="tracker",
                    text=(f"Tracker suspect staying near you: {identity.headline} "
                          f"— present for {span / 60:.0f} min "
                          f"across {len(stats['hours'])} hours, "
                          f"median signal {level} dBm"),
                    seen_at=sighting.seen_at, identity_key=identity.key,
                    label=identity.label, device_kind=identity.kind,
                    address=sighting.address,
                    data={"present_minutes": round(span / 60, 1),
                          "hours": len(stats["hours"]),
                          "rssi_median": level,
                          "addresses": sorted(identity.addresses)}))

        if identity.drone is not None and identity.key not in self._drone_alerted \
                and not self._ignored(identity):
            seen = self._drone_seen.get(identity.key, 0) + 1
            self._drone_seen[identity.key] = seen
            airborne = identity.drone.airborne
            # Airborne + a known serial is the trigger (so the alert can name
            # the drone, and a pre-serial address orphan doesn't double-fire);
            # if a serial or Location never arrives, presence alone is worth
            # one alert once the drone has been heard a few times.
            if (airborne and identity.drone_serial) \
                    or seen >= self.DRONE_PRESENCE_SIGHTINGS:
                self._drone_alerted.add(identity.key)
                lead = "Drone overhead" if airborne else "Drone nearby"
                alerts.append(Alert(
                    kind="drone",
                    text=f"{lead}: {describe_drone(identity.drone, home=self.home)}",
                    seen_at=sighting.seen_at, identity_key=identity.key,
                    label=identity.label, device_kind=identity.kind,
                    address=sighting.address,
                    data={"serial": identity.drone_serial,
                          "airborne": airborne,
                          "ua_type": identity.drone.ua_type_name}))
        return alerts
