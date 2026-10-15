"""The live radar: nightjar as an instrument, not a log file.

One ANSI frame, redrawn about once a second: every device currently
in earshot as a signal bar, strongest at the top, with its trend, how
long since it was last heard, and a sparkline of where its signal has
been. Given an identity resolver it draws one row per *device*, with
rotating phones folded; given a plain registry it draws one row per
address. Pure stdlib — the frame is just a string; the CLI handles
the terminal.
"""

from __future__ import annotations

import time

from .text import fmt_age, fmt_elapsed, proximity_band, rssi_level, sparkline, trend_arrow, truncate

_BAR_CELLS = 20
QUIET_AFTER = 20.0    # seconds since last sighting before a row is "quiet"
GONE_AFTER = 120.0    # seconds before a row drops off the radar


def _bar(rssi: int | None) -> str:
    if rssi is None:
        return " " * _BAR_CELLS
    filled = min(_BAR_CELLS, max(0, round(rssi_level(rssi) * _BAR_CELLS)))
    return "█" * filled + "░" * (_BAR_CELLS - filled)


def _rows_for(source) -> list:
    if hasattr(source, "by_signal"):
        return list(source.by_signal())
    return sorted(source.devices,
                  key=lambda r: (r.rssi_last is None, -(r.rssi_last or 0)))


def _row_label(row) -> str:
    kind = getattr(row, "kind", None)
    if hasattr(row, "label"):
        label = row.label
        if kind and kind != label and getattr(row, "names", None):
            return f"{label} [{kind}]"
        if getattr(row, "names", None):
            return label
        return kind or label
    who = row.name or kind or "(unnamed)"
    companies = ", ".join(row.companies)
    return f"{who} [{companies}]" if companies else who


def render_live(source, *, started_at: float, place: str | None = None,
                top: int = 14, now: float | None = None,
                width: int = 100, mode: str | None = None,
                alerts: list[str] | None = None) -> str:
    """Render one frame. `source` is a Registry or an IdentityResolver."""
    now = time.time() if now is None else now
    where = f"  @ {place}" if place else ""
    rows = _rows_for(source)
    total = getattr(source, "total_sightings", None)
    if total is None:
        total = sum(r.sightings for r in rows)
    live = [r for r in rows if now - r.last_seen <= GONE_AFTER]
    gone = len(rows) - len(live)
    live.sort(key=lambda r: (now - r.last_seen > QUIET_AFTER,
                             r.rssi_last is None, -(r.rssi_last or 0)))
    noun = "devices" if hasattr(source, "by_signal") else "addresses"
    mode_text = f"   {mode} scan" if mode else ""
    lines = [
        truncate(
            f"nightjar — live radar{where}   elapsed {fmt_elapsed(now - started_at)}   "
            f"{len(rows)} {noun} / {total} sightings{mode_text}", width),
        "",
        truncate(f"{'SIGNAL':<22} {'RSSI':>5}  {'RANGE':<9} {'DEVICE':<34} "
                 f"TREND  {'AGE':>7}  HISTORY", width),
    ]
    for row in live[:top]:
        rssi = f"{row.rssi_last:>4}" if row.rssi_last is not None else "   ?"
        age = now - row.last_seen
        quiet = age > QUIET_AFTER
        lines.append(truncate(
            f"{_bar(row.rssi_last if not quiet else None)}  {rssi}  "
            f"{(proximity_band(row.rssi_last) if not quiet else 'quiet'):<9} "
            f"{truncate(_row_label(row), 34):<34} {trend_arrow(row):^5}  "
            f"{fmt_age(age):>7}  {sparkline(row.signal.values)}", width))
    extra = []
    if len(live) > top:
        extra.append(f"{len(live) - top} more below the fold")
    if gone:
        extra.append(f"{gone} not heard for {int(GONE_AFTER // 60)} min")
    if extra:
        lines.append("  … " + "; ".join(extra))
    if alerts:
        lines.append("")
        lines.extend(truncate(line, width) for line in alerts)
    lines.append("")
    lines.append("Ctrl-C to stop and summarize.")
    return "\n".join(lines)
