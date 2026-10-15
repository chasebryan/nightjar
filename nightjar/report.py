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


def format_summary(registry: Registry) -> str:
    lines = [
        "",
        f"— {len(registry)} devices, {registry.total_sightings} sightings —",
        f"{'ADDRESS':<38} {'CLOSEST':>9} {'SEEN':>5}  NAME / MAKER",
    ]
    for record in registry.devices:
        who = record.name or "(unnamed)"
        companies = ", ".join(record.companies)
        label = f"{who} [{companies}]" if companies else who
        window = f"{_clock(record.first_seen)}–{_clock(record.last_seen)}"
        lines.append(
            f"{record.address:<38} {_rssi(record.rssi_closest)} "
            f"{record.sightings:>5}  {label}  ({window})"
        )
    return "\n".join(lines)
