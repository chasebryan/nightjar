"""Small text helpers shared by every renderer: sparklines, arrows,
proximity bands, clocks. Pure functions over plain values, so the
summary, the live radar and the reports all speak one dialect.
"""

from __future__ import annotations

import time

BLOCKS = "▁▂▃▄▅▆▇█"
TREND_ARROWS = {"approaching": "▲", "receding": "▼", "steady": "●"}

RSSI_FLOOR = -95  # dBm: empty bar
RSSI_CEIL = -35   # dBm: full bar


def rssi_level(rssi: int) -> float:
    """0.0 at RSSI_FLOOR, 1.0 at RSSI_CEIL, clamped."""
    level = (rssi - RSSI_FLOOR) / (RSSI_CEIL - RSSI_FLOOR)
    return min(1.0, max(0.0, level))


def sparkline(values: list[int], width: int = 14) -> str:
    """A tiny signal-strength chart from RSSI samples (-95..-35 dBm)."""
    if not values:
        return ""
    if len(values) > width:  # bucket-average down to width points
        step = len(values) / width
        buckets = []
        for i in range(width):
            chunk = values[int(i * step): int((i + 1) * step)] or [values[-1]]
            buckets.append(int(sum(chunk) / len(chunk)))
        values = buckets
    return "".join(BLOCKS[min(7, int(rssi_level(v) * 8))] for v in values)


def hour_sparkline(histogram: dict[int, int]) -> str:
    """24 characters, one per local hour, scaled to the busiest hour."""
    if not histogram:
        return " " * 24
    peak = max(histogram.values()) or 1
    chars = []
    for hour in range(24):
        count = histogram.get(hour, 0)
        if count <= 0:
            chars.append("·")
        else:
            chars.append(BLOCKS[min(7, int(count / peak * 7.999))])
    return "".join(chars)


def trend_arrow(record) -> str:
    """▲ approaching, ▼ receding, ● steady, blank when undecided."""
    trend = record.trend()
    return TREND_ARROWS.get(trend, " ") if trend else " "


def proximity_band(rssi: int | None) -> str:
    """A coarse, honest range label from RSSI alone."""
    if rssi is None:
        return "?"
    if rssi >= -55:
        return "immediate"
    if rssi >= -70:
        return "near"
    if rssi >= -85:
        return "far"
    return "faint"


def estimate_distance_m(rssi: int | None, measured_power: int | None,
                        path_loss_exponent: float = 2.5) -> float | None:
    """Log-distance estimate in metres, given a calibrated 1 m power.

    Rough by nature: walls, bodies and antenna orientation swing RSSI
    by 20 dB. Useful for "closer than that one", not for "2.3 m".
    """
    if rssi is None or measured_power is None:
        return None
    return round(10 ** ((measured_power - rssi) / (10 * path_loss_exponent)), 1)


def fmt_rssi(value: int | None) -> str:
    return f"{value:>4} dBm" if value is not None else "   ? dBm"


def fmt_clock(epoch: float) -> str:
    return time.strftime("%H:%M:%S", time.localtime(epoch))


def fmt_local(epoch: float) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(epoch))


def fmt_elapsed(seconds: float) -> str:
    seconds = int(max(0, seconds))
    return f"{seconds // 3600:02d}:{seconds // 60 % 60:02d}:{seconds % 60:02d}"


def fmt_age(seconds: float) -> str:
    """'3s', '2m', '1h 05m' — how long ago, for a glance."""
    seconds = int(max(0, seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h {seconds // 60 % 60:02d}m"


def fmt_hours(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.0f} s"
    if seconds < 3600:
        return f"{seconds / 60:.0f} min"
    return f"{seconds / 3600:.1f} h"


def truncate(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    return text[: max(0, width - 1)] + "…"
