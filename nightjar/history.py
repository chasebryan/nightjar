"""Level 4, first half: turning log files into sessions.

A *session* is one continuous stretch of listening — one run of
`nightjar scan` or `watch`, ideally labelled with where it happened
("home", "office", "the truck"). Sessions are the unit pattern-of-life
and tracker analysis think in: a device seen in one session is a
visitor; a device seen in every session, at every label, is something
else.

Log format: JSON lines. A listening run writes a session header first,
then one record per sighting, then (when it ends cleanly) a footer.
Alerts raised during a watch are logged inline too:

    {"type": "session", "session_id": ..., "label": ..., "started_at": ...}
    {"type": "sighting", "seen_at": ..., "address": ..., ...}
    {"type": "alert", "seen_at": ..., "kind": ..., "text": ...}
    {"type": "session_end", "session_id": ..., "ended_at": ...}

Logs without headers (including nightjar 0.1 logs) still load: their
sightings are split into sessions wherever the gap between sightings
exceeds `gap_seconds`. A corrupt line — a run cut off mid-write, a
stray edit — is skipped and counted, not fatal: one bad byte should
never cost you a week of history.
"""

from __future__ import annotations

import glob
import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from .registry import Sighting

DEFAULT_GAP_SECONDS = 30 * 60
LOG_SUFFIXES = (".jsonl", ".ndjson", ".log", ".json")


@dataclass
class Session:
    session_id: str
    label: str | None
    sightings: list[Sighting] = field(default_factory=list)
    header_started_at: float | None = None
    footer_ended_at: float | None = None
    label_source: str | None = None
    scan_mode: str | None = None
    source: str | None = None  # the file it came from
    alerts: list[dict] = field(default_factory=list)
    # Which listening post heard this session — the Mac, the phone, a
    # sniffer by the door. A *place* (label) is where the listener was;
    # a *post* is which ear heard it. Two posts at two places hearing one
    # device at the same instant is how fusion proves it wasn't following
    # anyone. None when the log predates posts or didn't name one.
    post: str | None = None

    @property
    def where(self) -> str:
        """A short 'post @ place' tag for output, using whichever exist."""
        if self.post and self.label:
            return f"{self.post} @ {self.label}"
        return self.post or self.label or "—"

    @property
    def started_at(self) -> float | None:
        if self.sightings:
            first = self.sightings[0].seen_at
            if self.header_started_at is not None:
                return min(first, self.header_started_at)
            return first
        return self.header_started_at

    @property
    def ended_at(self) -> float | None:
        if self.sightings:
            last = self.sightings[-1].seen_at
            if self.footer_ended_at is not None:
                return max(last, self.footer_ended_at)
            return last
        return self.footer_ended_at or self.header_started_at

    @property
    def span_seconds(self) -> float:
        start, end = self.started_at, self.ended_at
        if start is None or end is None:
            return 0.0
        return max(0.0, end - start)

    @property
    def has_header(self) -> bool:
        return self.header_started_at is not None

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "label": self.label,
            "label_source": self.label_source,
            "post": self.post,
            "scan_mode": self.scan_mode,
            "started_at": self.started_at,
            "ended_at": self.ended_at,
            "span_seconds": self.span_seconds,
            "sightings": len(self.sightings),
            "alerts": len(self.alerts),
            "source": self.source,
        }


@dataclass
class LoadReport:
    """What came out of the logs, and what didn't parse."""

    sessions: list[Session] = field(default_factory=list)
    files: list[str] = field(default_factory=list)
    sighting_count: int = 0
    skipped_lines: int = 0
    unknown_records: int = 0

    @property
    def alert_count(self) -> int:
        return sum(len(s.alerts) for s in self.sessions)


def expand_paths(paths) -> list[str]:
    """Files, directories (their logs) and glob patterns -> file list."""
    files: list[str] = []
    for raw in paths:
        text = os.path.expanduser(str(raw))
        path = Path(text)
        if path.is_dir():
            found = sorted(p for p in path.iterdir()
                           if p.is_file() and p.suffix.lower() in LOG_SUFFIXES)
            files.extend(str(p) for p in found)
        elif any(ch in text for ch in "*?["):
            files.extend(sorted(glob.glob(text)))
        else:
            files.append(text)
    seen: set[str] = set()
    unique = []
    for name in files:
        if name not in seen:
            seen.add(name)
            unique.append(name)
    return unique


def _parse_line(line: str) -> dict | None:
    try:
        rec = json.loads(line)
    except ValueError:
        return None
    return rec if isinstance(rec, dict) else None


def _load_file(path: str, gap_seconds: float, report: LoadReport,
               default_post: str | None = None) -> list[Session]:
    sessions: list[Session] = []
    current: Session | None = None
    legacy_count = 0
    prev_seen_at: float | None = None

    def open_session(session: Session) -> Session:
        nonlocal current
        session.source = path
        sessions.append(session)
        current = session
        return session

    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rec = _parse_line(line)
            if rec is None:
                report.skipped_lines += 1
                continue
            rtype = rec.get("type", "sighting")
            if rtype == "session":
                started = rec.get("started_at")
                open_session(Session(
                    session_id=str(rec.get("session_id") or "session"),
                    label=rec.get("label") or None,
                    header_started_at=float(started) if started is not None else None,
                    label_source=rec.get("label_source"),
                    scan_mode=rec.get("scan_mode"),
                    post=rec.get("post") or default_post,
                ))
                prev_seen_at = None
            elif rtype == "session_end":
                if current is not None:
                    ended = rec.get("ended_at")
                    current.footer_ended_at = (float(ended)
                                               if ended is not None else None)
                    current = None
            elif rtype == "alert":
                if current is not None:
                    current.alerts.append(rec)
                else:
                    report.unknown_records += 1
            elif rtype == "sighting" or "address" in rec:
                try:
                    sighting = Sighting.from_dict(rec)
                except (KeyError, TypeError, ValueError):
                    report.skipped_lines += 1
                    continue
                gap_split = (prev_seen_at is not None
                             and sighting.seen_at - prev_seen_at > gap_seconds)
                if current is None or (not current.has_header and gap_split):
                    legacy_count += 1
                    open_session(Session(
                        session_id=f"{Path(path).stem}-{legacy_count}",
                        label=None, post=default_post))
                assert current is not None
                current.sightings.append(sighting)
                prev_seen_at = sighting.seen_at
                report.sighting_count += 1
            else:
                report.unknown_records += 1
    for session in sessions:
        session.sightings.sort(key=lambda s: s.seen_at)
    return sessions


def load_log(paths, gap_seconds: float = DEFAULT_GAP_SECONDS, *,
             default_post: str | None = None,
             post_by_path: dict[str, str] | None = None) -> LoadReport:
    """Read sighting logs into sessions, with a report of what loaded.

    Each file is parsed on its own — sessions never straddle files —
    and the sessions from all files are merged in time order. A session's
    post comes from its own header; `post_by_path` overrides it per file
    and `default_post` fills in any that still lack one (both apply only
    where the header didn't name a post).
    """
    report = LoadReport()
    post_by_path = post_by_path or {}
    for path in expand_paths(paths):
        report.files.append(path)
        file_post = post_by_path.get(path, default_post)
        report.sessions.extend(_load_file(path, gap_seconds, report, file_post))
    report.sessions.sort(key=lambda s: (s.started_at is None, s.started_at or 0.0))
    return report


def load_sessions(paths, gap_seconds: float = DEFAULT_GAP_SECONDS, **kwargs
                  ) -> list[Session]:
    """Read sighting logs and group them into sessions, in time order."""
    return load_log(paths, gap_seconds, **kwargs).sessions


def posts_of(sessions: list[Session]) -> list[str]:
    """The distinct named posts across these sessions, sorted."""
    return sorted({s.post for s in sessions if s.post})


def filter_sessions(sessions: list[Session], *, since: float | None = None,
                    place: str | None = None) -> list[Session]:
    """Sessions that started at/after `since` and match `place` (substring)."""
    kept = []
    for session in sessions:
        if since is not None:
            started = session.started_at
            if started is None or started < since:
                continue
        if place is not None and (not session.label
                                  or place.lower() not in session.label.lower()):
            continue
        kept.append(session)
    return kept
