"""Level 4, first half: turning log files into sessions.

A *session* is one continuous stretch of listening — one run of
`nightjar scan`, ideally labelled with where it happened ("home",
"office", "the truck"). Sessions are the unit pattern-of-life and
tracker analysis think in: a device seen in one session is a visitor;
a device seen in every session, at every label, is something else.

Log format: JSON lines. `scan` writes a session header record first:

    {"type": "session", "session_id": ..., "label": ..., "started_at": ...}
    {"type": "sighting", "seen_at": ..., "address": ..., ...}

Logs without headers (including nightjar 0.1 logs) still load: their
sightings are split into sessions wherever the gap between sightings
exceeds `gap_seconds`.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

from .registry import Sighting

DEFAULT_GAP_SECONDS = 30 * 60


@dataclass
class Session:
    session_id: str
    label: str | None
    sightings: list[Sighting] = field(default_factory=list)

    @property
    def started_at(self) -> float | None:
        return self.sightings[0].seen_at if self.sightings else None

    @property
    def ended_at(self) -> float | None:
        return self.sightings[-1].seen_at if self.sightings else None

    @property
    def span_seconds(self) -> float:
        if not self.sightings:
            return 0.0
        return self.ended_at - self.started_at


def load_sessions(paths, gap_seconds: float = DEFAULT_GAP_SECONDS
                  ) -> list[Session]:
    """Read sighting logs and group them into sessions, in time order."""
    sightings: list[Sighting] = []
    headers: list[tuple[float, str, str | None]] = []  # (started_at, id, label)
    for path in paths:
        with open(Path(path), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                if rec.get("type") == "session":
                    headers.append((float(rec.get("started_at", 0.0)),
                                    rec.get("session_id", "session"),
                                    rec.get("label")))
                else:
                    sightings.append(Sighting.from_dict(rec))
    sightings.sort(key=lambda s: s.seen_at)

    headers.sort()
    sessions: list[Session] = []
    current: Session | None = None
    prev_seen_at: float | None = None
    h = 0
    for sighting in sightings:
        # A scan header that began at or before this sighting means a
        # new listening run started: this sighting opens its session.
        due_header = None
        while h < len(headers) and headers[h][0] <= sighting.seen_at:
            due_header = headers[h]
            h += 1
        gap_split = (prev_seen_at is not None
                     and sighting.seen_at - prev_seen_at > gap_seconds)
        if current is None or due_header is not None or gap_split:
            if due_header is not None:
                _, sid, label = due_header
            else:
                sid, label = f"session-{len(sessions) + 1}", None
            current = Session(session_id=sid, label=label)
            sessions.append(current)
        current.sightings.append(sighting)
        prev_seen_at = sighting.seen_at
    return sessions
