"""Human-readable output: the live NEW-device line and the summaries.

Two summaries, because two questions. *By identity* answers "who was
here" — rotating phones folded into one row each, kinds decoded. *By
address* answers "what did the radio literally hear", one row per
address, which is what a raw log is made of.
"""

from __future__ import annotations

import time

from .identify import Identity, IdentityResolver
from .registry import DeviceRecord, Registry
from .services import service_name
from .text import fmt_clock, fmt_rssi, sparkline, trend_arrow, truncate

__all__ = [
    "format_identity_summary",
    "format_new_device",
    "format_summary",
    "sparkline",
    "summary_dict",
    "trend_arrow",
]


def format_new_device(record: DeviceRecord) -> str:
    who = record.name or record.kind or "(unnamed)"
    line = (
        f"NEW  {fmt_clock(record.first_seen)}  {record.address}  "
        f"{fmt_rssi(record.rssi_last)}  {who}  [{_maker(record)}]"
    )
    if record.details:
        line += f"  — {record.details[0]}"
    return line


def format_summary(registry: Registry) -> str:
    """One row per address: what the radio literally heard."""
    lines = [
        "",
        f"— {len(registry)} addresses, {registry.total_sightings} sightings —",
        f"{'ADDRESS':<38} {'CLOSEST':>9} {'SEEN':>5}  {'SIGNAL':<16} NAME / KIND [MAKER]",
    ]
    for record in registry.devices:
        who = record.name or record.kind or "(unnamed)"
        companies = ", ".join(record.companies)
        label = f"{who} [{companies}]" if companies else who
        window = f"{fmt_clock(record.first_seen)}-{fmt_clock(record.last_seen)}"
        signal = (sparkline([r for _, r in record.rssi_history])
                  + " " + trend_arrow(record)).strip()
        lines.append(
            f"{record.address:<38} {fmt_rssi(record.rssi_closest)} "
            f"{record.sightings:>5}  {signal:<16} {label}  ({window})"
        )
    return "\n".join(lines)


def _identity_notes(identity: Identity) -> list[str]:
    notes = []
    rotation = identity.rotation_note()
    if rotation:
        notes.append(rotation)
    if identity.basis != "address":
        notes.append(f"by {identity.basis}")
    if identity.tracker_like:
        notes.append("tracker-shaped")
    elif identity.findmy_with_owner:
        notes.append("Find My, with owner")
    return notes


def _maker(record: DeviceRecord) -> str:
    """'[Apple]', '[Google Fast Pair]', or '[unknown maker]'."""
    if record.companies:
        return ", ".join(record.companies)
    names = sorted({name for name in (service_name(u) for u in record.service_uuids)
                    if name})
    return ", ".join(names) if names else "unknown maker"


def format_identity_summary(resolver: IdentityResolver,
                            total_sightings: int | None = None) -> str:
    """One row per resolved identity: who was here."""
    identities = sorted(resolver.identities,
                        key=lambda i: (i.rssi_closest is None,
                                       -(i.rssi_closest or 0)))
    total = total_sightings if total_sightings is not None else \
        sum(i.sightings for i in identities)
    rotating = sum(1 for i in identities if len(i.addresses) > 1)
    head = f"— {len(identities)} devices, {total} sightings"
    if rotating:
        head += f"; {rotating} rotated addresses"
    lines = [
        "",
        head + " —",
        f"{'DEVICE':<28} {'KIND':<34} {'CLOSEST':>9} {'SEEN':>5}  "
        f"{'SIGNAL':<16} {'WINDOW':<17} NOTES",
    ]
    for identity in identities:
        signal = (sparkline(identity.signal.values) + " "
                  + trend_arrow(identity)).strip()
        window = f"{fmt_clock(identity.first_seen)}-{fmt_clock(identity.last_seen)}"
        lines.append(
            f"{truncate(identity.label, 28):<28} {truncate(identity.kind, 34):<34} "
            f"{fmt_rssi(identity.rssi_closest)} {identity.sightings:>5}  "
            f"{signal:<16} {window:<17} {'; '.join(_identity_notes(identity))}"
        )
        if identity.details:
            lines.append(f"{'':<28} {identity.details[0]}")
        if len(identity.addresses) == 1:
            lines.append(f"{'':<28} {next(iter(identity.addresses))}")
    return "\n".join(lines)


def summary_dict(registry: Registry, resolver: IdentityResolver | None = None,
                 **extra) -> dict:
    """Everything a run learned, as one JSON-ready document."""
    doc = {
        "generated_at": time.time(),
        **extra,
        **registry.to_dict(),
    }
    if resolver is not None:
        doc.update(resolver.to_dict())
    return doc
