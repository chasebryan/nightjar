"""Level 4, second half: pattern of life.

Intelligence is not a packet; it's the pattern. This module reads
sessions, resolves identities across them, and describes each device
the way an analyst would: how often it's around, on which days, in
which sessions, at what hours — and whether it's a regular, a recent
arrival, or a regular who has gone missing.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from .history import Session
from .identify import Identity, IdentityResolver

REGULAR_MIN_SESSIONS = 3


@dataclass
class IdentityPattern:
    identity: Identity
    sessions_present: int = 0
    days_present: int = 0
    labels: set[str] = field(default_factory=set)
    presence_seconds: float = 0.0  # sum of per-session first-to-last span
    hour_histogram: dict[int, int] = field(default_factory=dict)

    @property
    def is_regular(self) -> bool:
        return (self.sessions_present >= REGULAR_MIN_SESSIONS
                or self.days_present >= REGULAR_MIN_SESSIONS)

    @property
    def usual_hours(self) -> str:
        if not self.hour_histogram:
            return "—"
        top = sorted(self.hour_histogram.items(), key=lambda kv: -kv[1])[:3]
        return ", ".join(f"{hour:02d}:00" for hour, _ in sorted(top))


def _local_day(epoch: float) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(epoch))


def analyze(sessions: list[Session]) -> list[IdentityPattern]:
    """Pattern-of-life for every identity across the given sessions."""
    resolver = IdentityResolver()
    patterns: dict[str, IdentityPattern] = {}
    days: dict[str, set[str]] = {}
    for session in sessions:
        first_in: dict[str, float] = {}
        last_in: dict[str, float] = {}
        for sighting in session.sightings:
            identity = resolver.observe(sighting)
            pattern = patterns.get(identity.key)
            if pattern is None:
                pattern = IdentityPattern(identity=identity)
                patterns[identity.key] = pattern
                days[identity.key] = set()
            first_in.setdefault(identity.key, sighting.seen_at)
            last_in[identity.key] = sighting.seen_at
            days[identity.key].add(_local_day(sighting.seen_at))
            hour = time.localtime(sighting.seen_at).tm_hour
            pattern.hour_histogram[hour] = \
                pattern.hour_histogram.get(hour, 0) + 1
        for key in first_in:
            patterns[key].sessions_present += 1
            patterns[key].presence_seconds += last_in[key] - first_in[key]
            if session.label:
                patterns[key].labels.add(session.label)
    for key, pattern in patterns.items():
        pattern.days_present = len(days[key])
    return sorted(patterns.values(), key=lambda p: -p.identity.sightings)


def _fmt_time(epoch: float) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(epoch))


def format_report(sessions: list[Session],
                  patterns: list[IdentityPattern]) -> str:
    if not sessions:
        return "No sessions found in the given logs."
    total = sum(len(s.sightings) for s in sessions)
    span_start = min(s.started_at for s in sessions if s.started_at)
    span_end = max(s.ended_at for s in sessions if s.ended_at)
    lines = [
        f"Pattern of life — {len(sessions)} sessions, {total} sightings, "
        f"{_fmt_time(span_start)} to {_fmt_time(span_end)}",
        "",
        f"{'DEVICE':<28} {'SEEN':>5} {'SESS':>4} {'DAYS':>4}  "
        f"{'USUAL HOURS':<18} NOTES",
    ]
    for pattern in patterns:
        ident = pattern.identity
        notes = []
        if pattern.is_regular:
            notes.append("regular")
        if len(pattern.identity.addresses) > 1:
            notes.append(f"{len(ident.addresses)} addresses (rotates)")
        if ident.tracker_like:
            notes.append("tracker-shaped")
        if pattern.labels:
            notes.append("@" + ",".join(sorted(pattern.labels)))
        lines.append(
            f"{ident.label[:28]:<28} {ident.sightings:>5} "
            f"{pattern.sessions_present:>4} {pattern.days_present:>4}  "
            f"{pattern.usual_hours:<18} {'; '.join(notes)}"
        )
        if ident.details:
            lines.append(f"{'':<28} {ident.details[0]}")
    return "\n".join(lines)
