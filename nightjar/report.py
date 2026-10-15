"""Human-readable output: the live NEW-device line and the summary."""

from __future__ import annotations

import time

from .registry import DeviceRecord, Registry


def _rssi(value: int | None) -> str:
    return f"{value:>4} dBm" if value is not None else "   ? dBm"


def _clock(epoch: float) -> str:
    return time.strftime("%H:%M:%S", time.localtime(epoch))


def format_new_device(record: DeviceRecord) -> str:
    who = record.name or "(unnamed)"
    companies = ", ".join(record.companies) or "unknown maker"
    return (
        f"NEW  {_clock(record.first_seen)}  {record.address}  "
        f"{_rssi(record.rssi_last)}  {who}  [{companies}]"
    )


_BLOCKS = "▁▂▃▄▅▆▇█"
_TREND_ARROWS = {"approaching": "▲", "receding": "▼", "steady": "●"}


def sparkline(values: list[int], width: int = 14) -> str:
    """A tiny signal-strength chart from RSSI samples (-95..-35 dBm)."""
    if not values:
        return ""
    if len(values) > width:  # bucket-average down to width points
        step = len(values) / width
        values = [
            int(sum(values[int(i * step): int((i + 1) * step)]
                    or [values[-1]]) /
                max(1, len(values[int(i * step): int((i + 1) * step)])))
            for i in range(width)
        ]
    chars = []
    for value in values:
        level = (value + 95) / 60  # -95 dBm -> 0, -35 dBm -> 1
        idx = min(7, max(0, int(level * 8)))
        chars.append(_BLOCKS[idx])
    return "".join(chars)


def trend_arrow(record: DeviceRecord) -> str:
    trend = record.trend()
    return _TREND_ARROWS.get(trend, " ") if trend else " "


def format_summary(registry: Registry) -> str:
    lines = [
        "",
        f"— {len(registry)} devices, {registry.total_sightings} sightings —",
        f"{'ADDRESS':<38} {'CLOSEST':>9} {'SEEN':>5}  {'SIGNAL':<16} NAME / MAKER",
    ]
    for record in registry.devices:
        who = record.name or "(unnamed)"
        companies = ", ".join(record.companies)
        label = f"{who} [{companies}]" if companies else who
        window = f"{_clock(record.first_seen)}–{_clock(record.last_seen)}"
        signal = (sparkline([r for _, r in record.rssi_history])
                  + " " + trend_arrow(record)).strip()
        lines.append(
            f"{record.address:<38} {_rssi(record.rssi_closest)} "
            f"{record.sightings:>5}  {signal:<16} {label}  ({window})"
        )
    return "\n".join(lines)
