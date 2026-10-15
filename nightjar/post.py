"""The listening post itself: everything one run keeps in its head.

`scan` and `watch` differ only in what they say out loud. Underneath,
both fold sightings into an address registry and an identity resolver,
write the session log, and (for `watch`) ask the alert engine what is
worth interrupting for. That shared machinery lives here so the CLI
is just wiring.
"""

from __future__ import annotations

import json
import time
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import TextIO

from . import __version__
from .identify import Identity, IdentityResolver, classify
from .registry import DeviceRecord, Registry, Sighting
from .watch import Alert, AlertDispatcher, AlertEngine

LOG_FORMAT_VERSION = 1


class SessionLog:
    """Append-only JSON Lines writer for one listening run.

    The header is written when scanning actually starts (so it can
    record the scan mode in force), sightings and alerts as they come,
    and a footer when the run ends cleanly.
    """

    def __init__(self, path: str, *, label: str | None, label_source: str | None):
        self.path = path
        self.label = label
        self.label_source = label_source
        self.session_id = uuid.uuid4().hex[:12]
        self.started_at: float | None = None
        self.sightings = 0
        self._fh: TextIO | None = None

    @property
    def is_open(self) -> bool:
        return self._fh is not None

    def open(self, scan_mode: str) -> None:
        if self._fh is not None:
            return
        self._fh = open(self.path, "a", encoding="utf-8")  # noqa: SIM115 - lives across a run
        self.started_at = time.time()
        self._write({
            "type": "session",
            "session_id": self.session_id,
            "label": self.label,
            "label_source": self.label_source,
            "started_at": self.started_at,
            "scan_mode": scan_mode,
            "format": LOG_FORMAT_VERSION,
            "nightjar_version": __version__,
        })

    def _write(self, record: dict) -> None:
        if self._fh is None:
            return
        self._fh.write(json.dumps(record) + "\n")
        self._fh.flush()

    def sighting(self, sighting: Sighting) -> None:
        self.sightings += 1
        self._write(sighting.to_dict())

    def alert(self, alert: Alert) -> None:
        self._write(alert.to_dict())

    def close(self) -> None:
        if self._fh is None:
            return
        self._write({
            "type": "session_end",
            "session_id": self.session_id,
            "ended_at": time.time(),
            "sightings": self.sightings,
        })
        self._fh.close()
        self._fh = None


@dataclass
class Observation:
    """What one sighting changed."""

    sighting: Sighting
    record: DeviceRecord
    new_address: bool
    identity: Identity
    new_identity: bool
    alerts: list[Alert] = field(default_factory=list)


class ListeningPost:
    """Folds sightings into registry + identities, logs, and alerts."""

    def __init__(self, *, log: SessionLog | None = None,
                 engine: AlertEngine | None = None,
                 dispatcher: AlertDispatcher | None = None,
                 on_observation: Callable[[Observation], None] | None = None):
        self.registry = Registry()
        self.engine = engine
        self.resolver = engine.resolver if engine is not None else IdentityResolver()
        self.log = log
        self.dispatcher = dispatcher
        self.on_observation = on_observation
        self.alerts: list[Alert] = []
        self.started_at: float | None = None
        self.scan_mode: str | None = None
        self._record_rank: dict[str, int] = {}

    def started(self, scan_mode: str) -> None:
        """Scanning is under way: open the log and start the clock."""
        self.scan_mode = scan_mode
        self.started_at = time.time()
        if self.log is not None:
            self.log.open(scan_mode)

    def observe(self, sighting: Sighting) -> Observation:
        record, new_address = self.registry.observe(sighting)
        if self.log is not None:
            self.log.sighting(sighting)
        before = len(self.resolver)
        if self.engine is not None:
            alerts = self.engine.observe(sighting)
            identity = self.resolver.for_address(sighting.address)
            assert identity is not None
        else:
            alerts = []
            identity = self.resolver.observe(sighting)
        new_identity = len(self.resolver) > before
        classification = classify(sighting)
        if classification.rank >= self._record_rank.get(sighting.address, 0):
            self._record_rank[sighting.address] = classification.rank
            record.kind = classification.kind
        if classification.details:
            record.details = list(classification.details)
        for alert in alerts:
            self.alerts.append(alert)
            if self.log is not None:
                self.log.alert(alert)
            if self.dispatcher is not None:
                self.dispatcher.submit(alert)
        observation = Observation(sighting=sighting, record=record,
                                  new_address=new_address, identity=identity,
                                  new_identity=new_identity, alerts=alerts)
        if self.on_observation is not None:
            self.on_observation(observation)
        return observation

    def close(self) -> None:
        if self.log is not None:
            self.log.close()
        if self.dispatcher is not None:
            self.dispatcher.close()
