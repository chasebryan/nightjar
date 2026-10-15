"""The live radar: nightjar as an instrument, not a log file.

One ANSI frame, redrawn about once a second: every device currently
in earshot as a signal bar, strongest at the top, with its trend and
a sparkline of where its signal has been. Pure stdlib — the frame is
just a string; the CLI handles the terminal.
"""

from __future__ import annotations

import time

from .registry import Registry
from .report import sparkline, trend_arrow

_BAR_CELLS = 20


def _bar(rssi: int | None) -> str:
    if rssi is None:
        return " " * _BAR_CELLS
    level = (rssi + 95) / 60  # -95 dBm -> empty, -35 dBm -> full
    filled = min(_BAR_CELLS, max(0, round(level * _BAR_CELLS)))
    return "█" * filled + "░" * (_BAR_CELLS - filled)


def _elapsed(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 3600:02d}:{seconds // 60 % 60:02d}:{seconds % 60:02d}"


def render_live(registry: Registry, *, started_at: float,
                place: str | None = None, top: int = 14,
                now: float | None = None) -> str:
    now = time.time() if now is None else now
    where = f"  @ {place}" if place else ""
    lines = [
        f"nightjar — live radar{where}   "
        f"elapsed {_elapsed(now - started_at)}   "
        f"{len(registry)} devices / {registry.total_sightings} sightings",
        "",
        f"{'SIGNAL':<22} {'RSSI':>5}  {'DEVICE':<34} TREND  HISTORY",
    ]
    by_last = sorted(
        registry.devices,
        key=lambda r: (r.rssi_last is None, -(r.rssi_last or 0)),
    )
    for record in by_last[:top]:
        who = record.name or "(unnamed)"
        companies = ", ".join(record.companies)
        label = f"{who} [{companies}]" if companies else who
        rssi = f"{record.rssi_last:>4}" if record.rssi_last is not None else "   ?"
        lines.append(
            f"{_bar(record.rssi_last)}  {rssi}  "
            f"{label[:34]:<34} {trend_arrow(record):^5}  "
            f"{sparkline([r for _, r in record.rssi_history])}"
        )
    if len(by_last) > top:
        lines.append(f"  … and {len(by_last) - top} quieter devices")
    lines.append("")
    lines.append("Ctrl-C to stop and summarize.")
    return "\n".join(lines)
