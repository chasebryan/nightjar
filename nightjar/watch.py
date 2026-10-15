"""Improvement 4: the post stands guard — watch mode and its alerts.

`scan` answers when you stop it. `watch` speaks when something
happens:

  * a NEW device identity appears (after a warmup window, so the
    devices that were always there don't trigger a flood at start-up)
  * a tracker-shaped identity has travelled with the listener:
    present across several distinct hours, near enough to matter

Alerts print to the console and, if a Discord webhook is configured
(--webhook or the NIGHTJAR_WEBHOOK_URL environment variable), are
posted there too. Each alert fires once per identity — a guard that
cries constantly gets ignored, and this one knows it.
"""

from __future__ import annotations

import json
import os
import urllib.request
from statistics import median

from .identify import IdentityResolver
from .registry import Sighting


class DiscordAlerter:
    """Posts alert text to a Discord webhook. Stdlib only."""

    def __init__(self, webhook_url: str | None = None, opener=None):
        self.url = webhook_url or os.environ.get("NIGHTJAR_WEBHOOK_URL")
        self._opener = opener or self._default_opener

    @staticmethod
    def _default_opener(request) -> int:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status

    def send(self, text: str) -> bool:
        if not self.url:
            return False
        request = urllib.request.Request(
            self.url,
            data=json.dumps({"content": text}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            return self._opener(request) < 300
        except Exception:
            return False  # alerting must never kill the watch


class AlertEngine:
    """Decides, sighting by sighting, what is worth interrupting for."""

    def __init__(self, *, alert_new: bool = True,
                 warmup_seconds: float = 120.0,
                 tracker_min_span: float = 45 * 60.0,
                 tracker_min_hours: int = 2,
                 tracker_min_rssi: int = -80):
        self.alert_new = alert_new
        self.warmup_seconds = warmup_seconds
        self.tracker_min_span = tracker_min_span
        self.tracker_min_hours = tracker_min_hours
        self.tracker_min_rssi = tracker_min_rssi
        self._resolver = IdentityResolver()
        self._started_at: float | None = None
        self._known: set[str] = set()
        self._tracker_alerted: set[str] = set()
        self._tracker_stats: dict[str, dict] = {}

    def observe(self, sighting: Sighting) -> list[str]:
        if self._started_at is None:
            self._started_at = sighting.seen_at
        identity = self._resolver.observe(sighting)
        alerts: list[str] = []

        if identity.key not in self._known:
            self._known.add(identity.key)
            past_warmup = (sighting.seen_at - self._started_at
                           >= self.warmup_seconds)
            if self.alert_new and past_warmup:
                alerts.append(
                    f"New device appeared: {identity.label} "
                    f"({identity.kind}) at {sighting.address}")

        if identity.tracker_like:
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
                alerts.append(
                    f"Tracker suspect travelling with you: {identity.label} "
                    f"({identity.kind}) — present for {span / 60:.0f} min "
                    f"across {len(stats['hours'])} hours, "
                    f"median signal {int(median(stats['rssis']))} dBm")
        return alerts
