"""Level 6: it thinks in places, not just devices.

Pattern-of-life tells you what a normal day looks like. This module
asks the next question — *did today match?* — and raises the two
anomalies that matter for a place you watch:

  * a **regular went missing**: a device that is normally here at this
    hour, in this place, didn't show. Absence is as loud as presence —
    the car that's always in the driveway by six, gone.
  * something **new arrived at an odd hour**: a device never seen
    before, turning up when the place is normally quiet. A new phone at
    2 AM is worth a look; a new phone at noon is just a visitor.

Both split the history into a *baseline* (what's normal) and an
*observation* (what just happened), learn the baseline, and compare.
It never invents a baseline it doesn't have: with too little history,
or an hour it has never watched, it stays silent rather than guess.

This is analysis over logs, not a live packet alarm — run it after a
session, or on a schedule (cron, a launchd timer) against your logs.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from .history import Session
from .patterns import REGULAR_MIN_SESSIONS, IdentityPattern, analyze

# An hour is "quiet" in the baseline if its share of activity is below
# this fraction of the busiest hour — that's when a newcomer stands out.
QUIET_FRACTION = 0.15
# Don't call anything an anomaly from a baseline thinner than this many
# sessions: you can't know what's normal from one day.
MIN_BASELINE_SESSIONS = REGULAR_MIN_SESSIONS


@dataclass
class Anomaly:
    kind: str            # "missing-regular" | "new-at-odd-hour"
    label: str
    device_kind: str
    key: str
    detail: str
    when: float = 0.0
    places: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "kind": self.kind,
            "label": self.label,
            "device_kind": self.device_kind,
            "key": self.key,
            "detail": self.detail,
            "when": self.when,
            "places": list(self.places),
        }


def _local_hour(epoch: float) -> int:
    return time.localtime(epoch).tm_hour


def split_baseline(sessions: list[Session], *, observation_days: float = 1.0,
                   now: float | None = None
                   ) -> tuple[list[Session], list[Session]]:
    """(baseline, observation): the recent window vs everything before it.

    The observation is every session that started within the last
    `observation_days` of the most recent session (or of `now`); the
    baseline is the rest.
    """
    dated_starts = [s.started_at for s in sessions if s.started_at is not None]
    if not dated_starts:
        return [], []
    latest = now if now is not None else max(dated_starts)
    cutoff = latest - observation_days * 86400.0
    baseline = [s for s in sessions if (s.started_at or 0.0) < cutoff]
    observation = [s for s in sessions if (s.started_at or 0.0) >= cutoff]
    return baseline, observation


def _observation_facts(observation: list[Session]):
    patterns = analyze(observation)
    keys = {p.identity.key for p in patterns}
    hours: set[int] = set()
    labels: set[str] = set()
    for session in observation:
        if session.label:
            labels.add(session.label)
        for sighting in session.sightings:
            hours.add(_local_hour(sighting.seen_at))
    ref = max((s.ended_at for s in observation if s.ended_at is not None),
              default=0.0)
    return patterns, keys, hours, labels, ref


def _baseline_hour_counts(baseline: list[Session]) -> dict[int, int]:
    counts: dict[int, int] = {}
    for session in baseline:
        for sighting in session.sightings:
            hour = _local_hour(sighting.seen_at)
            counts[hour] = counts.get(hour, 0) + 1
    return counts


def _expected_now(pattern: IdentityPattern, obs_hours: set[int],
                  obs_labels: set[str]) -> bool:
    """Would we expect this baseline regular during the observation?

    Yes when its usual hours overlap the hours the observation actually
    covered, and — if both sides name places — its places overlap the
    observation's. A home regular isn't 'missing' from an office session.
    """
    usual = {h for h, _ in sorted(pattern.hour_histogram.items(),
                                  key=lambda kv: -kv[1])[:3]}
    if not usual & obs_hours:
        return False
    if pattern.labels and obs_labels:
        return bool(pattern.labels & obs_labels)
    return True


def find_anomalies(sessions: list[Session], *,
                   observation_days: float = 1.0,
                   now: float | None = None,
                   baseline: list[Session] | None = None,
                   observation: list[Session] | None = None,
                   quiet_fraction: float = QUIET_FRACTION,
                   min_baseline_sessions: int = MIN_BASELINE_SESSIONS
                   ) -> list[Anomaly]:
    """Missing regulars and odd-hour arrivals in the recent window."""
    if baseline is None or observation is None:
        baseline, observation = split_baseline(
            sessions, observation_days=observation_days, now=now)
    if not observation or len(baseline) < min_baseline_sessions:
        return []  # nothing to compare, or too little normal to judge

    base_patterns = analyze(baseline)
    base_keys = {p.identity.key for p in base_patterns}
    _, obs_keys, obs_hours, obs_labels, obs_ref = _observation_facts(observation)

    anomalies: list[Anomaly] = []

    # Missing regulars: normally here now, didn't show. Only devices with
    # a stable identity are eligible — a device that rotates its address
    # (and, with it, its identity key) across epochs can't be matched from
    # one day to the next, so "it didn't show" would just be the rotation,
    # not an absence. That's the epoch-boundary limit, stated honestly.
    for pattern in base_patterns:
        if not pattern.is_regular or pattern.identity.rotates:
            continue
        if pattern.identity.key in obs_keys:
            continue
        if not _expected_now(pattern, obs_hours, obs_labels):
            continue
        where = ", ".join(sorted(pattern.labels)) or "the usual place"
        anomalies.append(Anomaly(
            kind="missing-regular",
            label=pattern.identity.label,
            device_kind=pattern.identity.kind,
            key=pattern.identity.key,
            detail=(f"a regular ({pattern.sessions_present} sessions, "
                    f"usual hours {pattern.usual_hours}) did not appear; "
                    f"normally at {where}"),
            when=obs_ref, places=sorted(pattern.labels)))

    # New arrivals at an hour the place is normally quiet.
    hour_counts = _baseline_hour_counts(baseline)
    peak = max(hour_counts.values(), default=0)
    if peak > 0:
        quiet = {h for h in range(24)
                 if hour_counts.get(h, 0) <= quiet_fraction * peak}
        obs_patterns = analyze(observation)
        for pattern in obs_patterns:
            if pattern.identity.key in base_keys:
                continue  # not new
            if pattern.identity.rotates:
                continue  # rotates its key every epoch: "new" tells us nothing
            hour = _local_hour(pattern.identity.first_seen)
            if hour not in quiet:
                continue
            where = ", ".join(sorted(pattern.labels)) or "the listening post"
            anomalies.append(Anomaly(
                kind="new-at-odd-hour",
                label=pattern.identity.label,
                device_kind=pattern.identity.kind,
                key=pattern.identity.key,
                detail=(f"never seen before, and arrived at "
                        f"{time.strftime('%H:%M', time.localtime(pattern.identity.first_seen))} "
                        f"— an hour {where} is normally quiet"),
                when=pattern.identity.first_seen, places=sorted(pattern.labels)))

    anomalies.sort(key=lambda a: (a.kind, a.label))
    return anomalies


def format_anomalies(anomalies: list[Anomaly], *, had_baseline: bool = True
                     ) -> str:
    if not anomalies:
        if not had_baseline:
            return ("Not enough history yet to know what's normal. "
                    "Keep logging; anomalies need a baseline to stand out from.")
        return "Nothing out of the ordinary in the recent window."
    missing = [a for a in anomalies if a.kind == "missing-regular"]
    arrived = [a for a in anomalies if a.kind == "new-at-odd-hour"]
    lines: list[str] = []
    if missing:
        lines.append(f"Missing regulars ({len(missing)}):")
        for item in missing:
            headline = (item.device_kind if item.label == item.device_kind
                        else f"{item.label} ({item.device_kind})")
            lines.append(f"  - {headline}: {item.detail}")
    if arrived:
        if lines:
            lines.append("")
        lines.append(f"New at an odd hour ({len(arrived)}):")
        for item in arrived:
            headline = (item.device_kind if item.label == item.device_kind
                        else f"{item.label} ({item.device_kind})")
            lines.append(f"  - {headline}: {item.detail}")
    lines.append("")
    lines.append("Absence and odd-hour arrivals are prompts to look, not proof "
                 "of anything. A regular may simply be away.")
    return "\n".join(lines)
