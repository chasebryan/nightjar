"""Level 5: counter-detection — is something following you?

The unwanted-tracking pattern, as the Apple/Google joint spec
describes it, is behavioral: a small tag, separated from its owner,
that keeps turning up near the same person across time and place.
nightjar can't prove intent, but it can apply exactly that shape to
your own listening history and show its work:

  * the identity is tracker-shaped (unnamed, tag signatures) —  gate
  * it appears in session after session, not just once          +2
  * it appears under more than one session label (place)         +2
  * it has been around for many hours                            +1
  * within some session it was present near both the start and
    the end — it travelled with the listener                     +1

Score 4 or more and the identity is reported as a suspect, with the
evidence listed. A listener that never leaves one room can still
catch persistence, but multi-place evidence is what separates "tag
in the building" from "tag in your life" — hence the labels.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .history import Session
from .identify import IdentityResolver

EDGE_WINDOW_SECONDS = 10 * 60


@dataclass
class Suspect:
    label: str
    kind: str
    score: int
    reasons: list[str] = field(default_factory=list)
    sightings: int = 0


def find_suspects(sessions: list[Session], *,
                  min_sessions: int = 2,
                  min_span_hours: float = 8.0) -> list[Suspect]:
    resolver = IdentityResolver()
    presence: dict[str, dict] = {}
    for session in sessions:
        in_session: dict[str, list[float]] = {}
        for sighting in session.sightings:
            identity = resolver.observe(sighting)
            in_session.setdefault(identity.key, []).append(sighting.seen_at)
        for key, times in in_session.items():
            entry = presence.setdefault(key, {
                "identity": resolver.get(key),
                "sessions": 0, "labels": set(), "co_travel": False,
            })
            entry["sessions"] += 1
            if session.label:
                entry["labels"].add(session.label)
            if session.sightings:
                start = session.sightings[0].seen_at
                end = session.sightings[-1].seen_at
                if (min(times) <= start + EDGE_WINDOW_SECONDS
                        and max(times) >= end - EDGE_WINDOW_SECONDS):
                    entry["co_travel"] = True

    suspects: list[Suspect] = []
    for entry in presence.values():
        identity = entry["identity"]
        if not identity.tracker_like:
            continue  # gate: only tag-shaped identities are candidates
        score = 0
        reasons: list[str] = []
        if entry["sessions"] >= min_sessions:
            score += 2
            reasons.append(f"present in {entry['sessions']} sessions")
        if len(entry["labels"]) >= 2:
            score += 2
            reasons.append(
                f"seen at multiple places: {', '.join(sorted(entry['labels']))}")
        span_hours = (identity.last_seen - identity.first_seen) / 3600.0
        if span_hours >= min_span_hours:
            score += 1
            reasons.append(f"tracked over {span_hours:.1f} hours")
        if entry["co_travel"]:
            score += 1
            reasons.append("present at both the start and end of a session "
                           "(travelled with the listener)")
        if score >= 4:
            suspects.append(Suspect(
                label=identity.label, kind=identity.kind, score=score,
                reasons=reasons, sightings=identity.sightings))
    return sorted(suspects, key=lambda s: -s.score)


def format_suspects(suspects: list[Suspect]) -> str:
    if not suspects:
        return ("No tracker-shaped device met the suspicion threshold. "
                "That is evidence, not proof — a tag you never listened "
                "near leaves no trace here.")
    lines = [f"{len(suspects)} suspect(s):"]
    for suspect in suspects:
        lines.append(f"\n  {suspect.label} ({suspect.kind}) — "
                     f"score {suspect.score}, {suspect.sightings} sightings")
        for reason in suspect.reasons:
            lines.append(f"    - {reason}")
    return "\n".join(lines)
