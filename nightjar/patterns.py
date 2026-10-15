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
from .text import fmt_hours, fmt_local, hour_sparkline, truncate

REGULAR_MIN_SESSIONS = 3
WEEKDAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


@dataclass
class SessionPresence:
    """One identity's presence inside one session."""

    session_id: str
    label: str | None
    first_seen: float
    last_seen: float
    sightings: int = 0
    rssi_values: list[int] = field(default_factory=list)

    @property
    def rssi_median(self) -> int | None:
        if not self.rssi_values:
            return None
        values = sorted(self.rssi_values)
        return values[len(values) // 2]

    @property
    def span_seconds(self) -> float:
        return self.last_seen - self.first_seen

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "label": self.label,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
            "span_seconds": self.span_seconds,
            "sightings": self.sightings,
            "rssi_median": self.rssi_median,
        }


@dataclass
class IdentityPattern:
    identity: Identity
    sessions_present: int = 0
    days_present: int = 0
    labels: set[str] = field(default_factory=set)
    posts: set[str] = field(default_factory=set)  # which ears heard it
    presence_seconds: float = 0.0  # sum of per-session first-to-last span
    hour_histogram: dict[int, int] = field(default_factory=dict)
    weekday_histogram: dict[int, int] = field(default_factory=dict)
    presences: list[SessionPresence] = field(default_factory=list)
    days: set[str] = field(default_factory=set)

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

    @property
    def usual_days(self) -> str:
        if not self.weekday_histogram:
            return "—"
        if len(self.weekday_histogram) >= 6:
            return "every day"
        return ", ".join(WEEKDAYS[d] for d in sorted(self.weekday_histogram))

    @property
    def hour_profile(self) -> str:
        """24-character sparkline of activity by local hour, 00..23."""
        return hour_sparkline(self.hour_histogram)

    @property
    def rssi_median(self) -> int | None:
        return self.identity.signal.median()

    @property
    def average_presence_seconds(self) -> float:
        if not self.sessions_present:
            return 0.0
        return self.presence_seconds / self.sessions_present

    @property
    def status(self) -> str:
        """regular / visitor / one-off, in one word."""
        if self.is_regular:
            return "regular"
        if self.sessions_present >= 2:
            return "visitor"
        return "one-off"

    def to_dict(self) -> dict:
        return {
            "identity": self.identity.to_dict(),
            "status": self.status,
            "is_regular": self.is_regular,
            "sessions_present": self.sessions_present,
            "days_present": self.days_present,
            "days": sorted(self.days),
            "labels": sorted(self.labels),
            "posts": sorted(self.posts),
            "presence_seconds": self.presence_seconds,
            "average_presence_seconds": self.average_presence_seconds,
            "hour_histogram": {str(h): n for h, n in sorted(self.hour_histogram.items())},
            "weekday_histogram": {WEEKDAYS[d]: n for d, n
                                  in sorted(self.weekday_histogram.items())},
            "usual_hours": self.usual_hours,
            "usual_days": self.usual_days,
            "sessions": [p.to_dict() for p in self.presences],
        }


def _local_day(epoch: float) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(epoch))


def analyze(sessions: list[Session]) -> list[IdentityPattern]:
    """Pattern-of-life for every identity across the given sessions."""
    resolver = IdentityResolver()
    patterns: dict[str, IdentityPattern] = {}
    for session in sessions:
        in_session: dict[str, SessionPresence] = {}
        for sighting in session.sightings:
            identity = resolver.observe(sighting)
            pattern = patterns.get(identity.key)
            if pattern is None:
                pattern = IdentityPattern(identity=identity)
                patterns[identity.key] = pattern
            presence = in_session.get(identity.key)
            if presence is None:
                presence = SessionPresence(
                    session_id=session.session_id, label=session.label,
                    first_seen=sighting.seen_at, last_seen=sighting.seen_at)
                in_session[identity.key] = presence
            presence.last_seen = max(presence.last_seen, sighting.seen_at)
            presence.sightings += 1
            if sighting.rssi is not None:
                presence.rssi_values.append(sighting.rssi)
            pattern.days.add(_local_day(sighting.seen_at))
            local = time.localtime(sighting.seen_at)
            pattern.hour_histogram[local.tm_hour] = \
                pattern.hour_histogram.get(local.tm_hour, 0) + 1
            pattern.weekday_histogram[local.tm_wday] = \
                pattern.weekday_histogram.get(local.tm_wday, 0) + 1
        for key, presence in in_session.items():
            pattern = patterns[key]
            pattern.sessions_present += 1
            pattern.presence_seconds += presence.span_seconds
            pattern.presences.append(presence)
            if session.label:
                pattern.labels.add(session.label)
            if session.post:
                pattern.posts.add(session.post)
    for pattern in patterns.values():
        pattern.days_present = len(pattern.days)
    return sorted(patterns.values(), key=lambda p: -p.identity.sightings)


def format_report(sessions: list[Session],
                  patterns: list[IdentityPattern], *,
                  wide: bool = False) -> str:
    if not sessions:
        return "No sessions found in the given logs."
    total = sum(len(s.sightings) for s in sessions)
    starts = [s.started_at for s in sessions if s.started_at is not None]
    ends = [s.ended_at for s in sessions if s.ended_at is not None]
    empty = sum(1 for s in sessions if not s.sightings)
    labels = sorted({s.label for s in sessions if s.label})
    head = (f"Pattern of life — {len(sessions)} sessions"
            + (f" ({empty} heard nothing)" if empty else "")
            + f", {total} sightings, {len(patterns)} devices")
    if starts and ends:
        head += f", {fmt_local(min(starts))} to {fmt_local(max(ends))}"
    posts = sorted({s.post for s in sessions if s.post})
    lines = [head]
    if labels:
        lines.append("places: " + ", ".join(labels))
    if posts:
        lines.append("posts: " + ", ".join(posts))
    lines += [
        "",
        f"{'DEVICE':<28} {'KIND':<30} {'SEEN':>5} {'SESS':>4} {'DAYS':>4}  "
        f"{'HOURS 00→23':<24} {'MED':>4}  NOTES",
    ]
    for pattern in patterns:
        ident = pattern.identity
        notes = [pattern.status]
        rotation = ident.rotation_note()
        if rotation:
            notes.append(rotation)
        if ident.tracker_like:
            notes.append("tracker-shaped")
        if ident.findmy_with_owner and not ident.findmy:
            notes.append("Find My, with owner")
        if pattern.labels:
            notes.append("@" + ",".join(sorted(pattern.labels)))
        if len(pattern.posts) > 1:
            notes.append("heard by " + ",".join(sorted(pattern.posts)))
        median = pattern.rssi_median
        lines.append(
            f"{truncate(ident.label, 28):<28} {truncate(ident.kind, 30):<30} "
            f"{ident.sightings:>5} "
            f"{pattern.sessions_present:>4} {pattern.days_present:>4}  "
            f"{pattern.hour_profile:<24} {median if median is not None else '?':>4}  "
            f"{'; '.join(notes)}"
        )
        if wide:
            lines.append(
                f"{'':<28} first {fmt_local(ident.first_seen)}, "
                f"last {fmt_local(ident.last_seen)}, usual {pattern.usual_hours} "
                f"on {pattern.usual_days}, "
                f"avg stay {fmt_hours(pattern.average_presence_seconds)}")
        if ident.details:
            lines.append(f"{'':<28} {ident.details[0]}")
    return "\n".join(lines)
