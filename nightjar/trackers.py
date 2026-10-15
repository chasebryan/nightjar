"""Level 5: counter-detection — is something following you?

The unwanted-tracking pattern, as the Apple/Google joint spec
describes it, is behavioral: a small tag, separated from its owner,
that keeps turning up near the same person across time and place.
nightjar can't prove intent, but it can apply exactly that shape to
your own listening history and show its work:

  * the identity is tracker-shaped (unnamed, tag signatures; a Find
    My accessory in its *separated* format, not one riding with its
    owner; never a phone that rotates by design)              — gate
  * it appears in session after session, not just once         +2
  * it appears under more than one session label (place)        +2
  * it has been near you for many hours, adding up the time it
    was actually present in each session                        +1
  * within some session it was present near both the start and
    the end — it travelled with the listener                    +1
  * it stayed at close range (median signal above a floor)      +1

Score 5 or more and the identity is reported as a suspect, with the
evidence listed. The bar is set so that a tag which merely *lives*
somewhere you go — a colleague's keys, always on the same desk —
cannot reach it on persistence alone (sessions + hours + range is
4): it takes a second place, or riding along from the start of a
session to its end, to tip over. A listener that never leaves one
room can still catch a tag planted where it listens, but multi-place
evidence is what separates "tag in the building" from "tag in your
life" — hence the labels.

Your own tags follow you everywhere too. Tell nightjar about them
with --ignore (an address prefix or a name) and they drop out.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .history import Session
from .identify import Identity, IdentityResolver

EDGE_WINDOW_SECONDS = 10 * 60
SUSPECT_THRESHOLD = 5
DEFAULT_MIN_RSSI = -80
# How much clock slop still counts as "at the same moment" when two posts
# hear one device. Loose enough for unsynced phone/Mac clocks, tight
# enough that it means genuine overlap, not two visits an hour apart.
SIMULTANEITY_SLOP_SECONDS = 2 * 60


@dataclass
class Suspect:
    label: str
    kind: str
    score: int
    reasons: list[str] = field(default_factory=list)
    sightings: int = 0
    key: str = ""
    addresses: list[str] = field(default_factory=list)
    sessions: int = 0
    labels: list[str] = field(default_factory=list)
    posts: list[str] = field(default_factory=list)
    span_hours: float = 0.0
    rssi_median: int | None = None
    first_seen: float = 0.0
    last_seen: float = 0.0

    @property
    def confidence(self) -> str:
        if self.score >= 7:
            return "strong"
        if self.score >= 6:
            return "likely"
        return "possible"

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "kind": self.kind,
            "score": self.score,
            "confidence": self.confidence,
            "reasons": list(self.reasons),
            "sightings": self.sightings,
            "addresses": list(self.addresses),
            "sessions": self.sessions,
            "labels": list(self.labels),
            "posts": list(self.posts),
            "span_hours": round(self.span_hours, 2),
            "rssi_median": self.rssi_median,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
        }


@dataclass
class Exoneration:
    """A tracker-shaped device that fusion clears: two posts at two
    places heard it within the same moment, so it was not one object
    riding along with the listener."""

    label: str
    kind: str
    key: str
    reason: str
    places: list[str] = field(default_factory=list)
    posts: list[str] = field(default_factory=list)
    at: float = 0.0
    sightings: int = 0

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "kind": self.kind,
            "reason": self.reason,
            "places": list(self.places),
            "posts": list(self.posts),
            "at": self.at,
            "sightings": self.sightings,
        }


@dataclass
class TrackerReport:
    suspects: list[Suspect] = field(default_factory=list)
    exonerations: list[Exoneration] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "suspects": [s.to_dict() for s in self.suspects],
            "exonerations": [e.to_dict() for e in self.exonerations],
        }


def _simultaneous_elsewhere(intervals: list[tuple[str, str, float, float]]
                            ) -> tuple[str, str, str, str, float] | None:
    """Two intervals from different posts at different places that overlap.

    intervals: (post, place, start, end). Returns (post_a, place_a,
    post_b, place_b, overlap_mid) for the first qualifying pair, else None.
    """
    for i, (post_a, place_a, start_a, end_a) in enumerate(intervals):
        for post_b, place_b, start_b, end_b in intervals[i + 1:]:
            if post_a == post_b or place_a == place_b:
                continue
            lo = max(start_a, start_b)
            hi = min(end_a, end_b)
            if lo <= hi + SIMULTANEITY_SLOP_SECONDS:
                return post_a, place_a, post_b, place_b, (lo + hi) / 2
    return None


def is_ignored(identity: Identity, ignore: list[str] | None) -> bool:
    return any(identity.matches(q) for q in (ignore or []))


def analyze_trackers(sessions: list[Session], *,
                     min_sessions: int = 2,
                     min_span_hours: float = 8.0,
                     min_rssi: int = DEFAULT_MIN_RSSI,
                     ignore: list[str] | None = None,
                     threshold: int = SUSPECT_THRESHOLD) -> TrackerReport:
    """Hunt following-tags, and clear the ones fusion proves innocent."""
    resolver = IdentityResolver()
    presence: dict[str, dict] = {}
    for session in sessions:
        in_session: dict[str, list[float]] = {}
        for sighting in session.sightings:
            seen = resolver.observe(sighting)
            in_session.setdefault(seen.key, []).append(sighting.seen_at)
        for key, times in in_session.items():
            entry = presence.setdefault(key, {
                "sessions": 0, "labels": set(), "posts": set(),
                "co_travel": False, "presence_seconds": 0.0, "intervals": [],
            })
            entry["sessions"] += 1
            entry["presence_seconds"] += max(times) - min(times)
            if session.label:
                entry["labels"].add(session.label)
            if session.post:
                entry["posts"].add(session.post)
            # An interval only helps fusion if we know both which ear and
            # which place heard it — that's what makes "two places at once"
            # meaningful rather than one post hearing itself.
            if session.post and session.label:
                entry["intervals"].append(
                    (session.post, session.label, min(times), max(times)))
            if session.sightings:
                start = session.sightings[0].seen_at
                end = session.sightings[-1].seen_at
                if (min(times) <= start + EDGE_WINDOW_SECONDS
                        and max(times) >= end - EDGE_WINDOW_SECONDS):
                    entry["co_travel"] = True

    suspects: list[Suspect] = []
    exonerations: list[Exoneration] = []
    for key, entry in presence.items():
        identity: Identity | None = resolver.get(key)
        if identity is None or not identity.tracker_like:
            continue  # gate: only tag-shaped identities are candidates
        if is_ignored(identity, ignore):
            continue

        clash = _simultaneous_elsewhere(entry["intervals"])
        if clash is not None:
            post_a, place_a, post_b, place_b, when = clash
            exonerations.append(Exoneration(
                label=identity.label, kind=identity.kind, key=key,
                reason=(f"heard at {place_a} ({post_a}) and {place_b} "
                        f"({post_b}) within the same moment — it can't be "
                        f"one tag travelling with you"),
                places=sorted({place_a, place_b}),
                posts=sorted({post_a, post_b}),
                at=when, sightings=identity.sightings))
            continue  # cleared: never also a suspect

        score = 0
        reasons: list[str] = []
        if entry["sessions"] >= min_sessions:
            score += 2
            reasons.append(f"present in {entry['sessions']} sessions")
        if len(entry["labels"]) >= 2:
            score += 2
            reasons.append(
                f"seen at multiple places: {', '.join(sorted(entry['labels']))}")
        span_hours = entry["presence_seconds"] / 3600.0
        if span_hours >= min_span_hours:
            score += 1
            reasons.append(f"near you for {span_hours:.1f} hours in total")
        if entry["co_travel"]:
            score += 1
            reasons.append("present at both the start and end of a session "
                           "(travelled with the listener)")
        median = identity.signal.median()
        if median is not None and median >= min_rssi:
            score += 1
            reasons.append(f"stayed at close range (median {median} dBm)")
        if score >= threshold:
            suspects.append(Suspect(
                label=identity.label, kind=identity.kind, score=score,
                reasons=reasons, sightings=identity.sightings, key=key,
                addresses=sorted(identity.addresses),
                sessions=entry["sessions"], labels=sorted(entry["labels"]),
                posts=sorted(entry["posts"]),
                span_hours=span_hours, rssi_median=median,
                first_seen=identity.first_seen, last_seen=identity.last_seen))
    suspects.sort(key=lambda s: (-s.score, -s.sightings))
    exonerations.sort(key=lambda e: -e.sightings)
    return TrackerReport(suspects=suspects, exonerations=exonerations)


def find_suspects(sessions: list[Session], **kwargs) -> list[Suspect]:
    """The suspects alone — the classic return, now minus any fusion clears."""
    return analyze_trackers(sessions, **kwargs).suspects


def format_suspects(suspects: list[Suspect]) -> str:
    if not suspects:
        return ("No tracker-shaped device met the suspicion threshold. "
                "That is evidence, not proof — a tag you never listened "
                "near leaves no trace here.")
    lines = [f"{len(suspects)} suspect(s):"]
    for suspect in suspects:
        headline = (suspect.kind if suspect.label == suspect.kind
                    else f"{suspect.label} ({suspect.kind})")
        lines.append(f"\n  {headline} — "
                     f"score {suspect.score} ({suspect.confidence}), "
                     f"{suspect.sightings} sightings")
        for reason in suspect.reasons:
            lines.append(f"    - {reason}")
        addresses = ", ".join(suspect.addresses[:3])
        if len(suspect.addresses) > 3:
            addresses += f" (+{len(suspect.addresses) - 3} more)"
        lines.append(f"    addresses: {addresses}")
        if len(suspect.posts) > 1:
            lines.append(f"    heard by: {', '.join(suspect.posts)}")
    lines.append("")
    lines.append("Evidence, not proof. Your own tags match this shape too: "
                 "name them with --ignore.")
    return "\n".join(lines)


def format_tracker_report(report: TrackerReport) -> str:
    """Suspects, then anything fusion cleared."""
    text = format_suspects(report.suspects)
    if report.exonerations:
        lines = ["", f"Cleared by fusion ({len(report.exonerations)}):"]
        for item in report.exonerations:
            headline = (item.kind if item.label == item.kind
                        else f"{item.label} ({item.kind})")
            lines.append(f"\n  {headline} — {item.sightings} sightings")
            lines.append(f"    - {item.reason}")
        text += "\n" + "\n".join(lines)
    return text
