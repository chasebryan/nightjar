"""Core data model: individual sightings and the device registry.

A *sighting* is one received BLE advertisement. The *registry* folds
every sighting into one record per device address, so raw noise becomes
a picture of who is around, when they arrived, and how close they got.

Addresses are the registry's key and also its weakness: phones rotate
theirs. Identity resolution (nightjar.identify) sits on top of the
registry and sees through that; the registry itself stays honest and
address-keyed, which is the right shape for a raw log.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from .companies import COMPANY_NAMES, company_name

__all__ = [
    "COMPANY_NAMES",
    "DeviceRecord",
    "Registry",
    "Sighting",
    "SignalTrack",
    "address_kind",
    "company_name",
]


def address_kind(address: str, address_type: str | None) -> str | None:
    """Classify a BLE address the way the radio sees it.

    The link layer marks an address as *public* (burned-in, stable) or
    *random*. Random addresses carry their sub-type in the top two bits
    of the first octet: ``11`` static (stable until reboot), ``01``
    resolvable private (rotates on a timer — the privacy feature phones
    use), ``00`` non-resolvable (rotates, never resolvable). Returns
    None when the type is unknown (macOS hands out UUIDs, not MACs).
    """
    if not address_type:
        return None
    kind = address_type.lower()
    if kind == "public":
        return "public"
    if kind != "random":
        return kind
    try:
        first = int(address.split(":")[0], 16)
    except (ValueError, IndexError):
        return "random"
    top = first >> 6
    if top == 0b11:
        return "random static"
    if top == 0b01:
        return "random resolvable"
    if top == 0b00:
        return "random non-resolvable"
    return "random"


@dataclass
class Sighting:
    """One received BLE advertisement."""

    address: str
    name: str | None
    rssi: int | None
    manufacturer_data: dict[int, bytes] = field(default_factory=dict)
    service_uuids: list[str] = field(default_factory=list)
    tx_power: int | None = None
    seen_at: float = field(default_factory=time.time)  # epoch seconds
    service_data: dict[str, bytes] = field(default_factory=dict)
    address_type: str | None = None  # "public" / "random" when the radio says

    def to_dict(self) -> dict:
        rec = {
            "type": "sighting",
            "seen_at": self.seen_at,
            "address": self.address,
            "name": self.name,
            "rssi": self.rssi,
            "manufacturer_data": {
                str(cid): payload.hex()
                for cid, payload in sorted(self.manufacturer_data.items())
            },
            "service_uuids": list(self.service_uuids),
            "tx_power": self.tx_power,
        }
        if self.service_data:
            rec["service_data"] = {
                uuid: payload.hex()
                for uuid, payload in sorted(self.service_data.items())
            }
        if self.address_type:
            rec["address_type"] = self.address_type
        return rec

    @classmethod
    def from_dict(cls, rec: dict) -> Sighting:
        manufacturer_data: dict[int, bytes] = {}
        for cid, payload in (rec.get("manufacturer_data") or {}).items():
            try:
                manufacturer_data[int(cid)] = bytes.fromhex(payload)
            except (TypeError, ValueError):
                continue  # one corrupt payload shouldn't lose the sighting
        service_data: dict[str, bytes] = {}
        for uuid, payload in (rec.get("service_data") or {}).items():
            try:
                service_data[str(uuid).lower()] = bytes.fromhex(payload)
            except (TypeError, ValueError):
                continue
        rssi = rec.get("rssi")
        tx_power = rec.get("tx_power")
        return cls(
            address=str(rec["address"]),
            name=rec.get("name") or None,
            rssi=int(rssi) if rssi is not None else None,
            manufacturer_data=manufacturer_data,
            service_uuids=[str(u) for u in (rec.get("service_uuids") or [])],
            tx_power=int(tx_power) if tx_power is not None else None,
            seen_at=float(rec.get("seen_at", 0.0)),
            service_data=service_data,
            address_type=rec.get("address_type") or None,
        )

    @property
    def address_kind(self) -> str | None:
        return address_kind(self.address, self.address_type)


@dataclass
class SignalTrack:
    """Where one device's signal has been: last, strongest, and history.

    Shared by address-keyed records and resolved identities, so trends
    and sparklines mean the same thing wherever they appear.
    """

    last: int | None = None
    closest: int | None = None  # strongest RSSI seen = closest approach
    # (epoch, rssi) samples, newest last, capped — the raw material for
    # trends, sparklines, and the live radar.
    history: list[tuple[float, int]] = field(default_factory=list)

    CAP = 240

    def observe(self, seen_at: float, rssi: int | None) -> None:
        if rssi is None:
            return
        self.last = rssi
        if self.closest is None or rssi > self.closest:
            self.closest = rssi
        self.history.append((seen_at, rssi))
        if len(self.history) > self.CAP:
            del self.history[: len(self.history) - self.CAP]

    @property
    def values(self) -> list[int]:
        return [rssi for _, rssi in self.history]

    def trend(self) -> str | None:
        """Approaching / receding / steady, from the RSSI history.

        Compares the mean of the older half of samples with the
        younger half; needs a handful of samples and a >3 dB move
        before it claims a direction.
        """
        values = self.values
        if len(values) < 6:
            return None
        mid = len(values) // 2
        older = sum(values[:mid]) / mid
        younger = sum(values[mid:]) / (len(values) - mid)
        delta = younger - older
        if delta > 3:
            return "approaching"
        if delta < -3:
            return "receding"
        return "steady"

    def median(self) -> int | None:
        values = sorted(self.values)
        if not values:
            return None
        return values[len(values) // 2]


@dataclass
class DeviceRecord:
    """Everything nightjar knows about one device address, so far."""

    address: str
    first_seen: float
    last_seen: float
    sightings: int = 0
    name: str | None = None
    company_ids: set[int] = field(default_factory=set)
    service_uuids: set[str] = field(default_factory=set)
    signal: SignalTrack = field(default_factory=SignalTrack)
    address_type: str | None = None
    # Filled in by the listening post, which runs identification;
    # the registry itself only folds what the radio said.
    kind: str | None = None
    details: list[str] = field(default_factory=list)

    HISTORY_CAP = SignalTrack.CAP

    def observe(self, sighting: Sighting) -> None:
        self.sightings += 1
        self.first_seen = min(self.first_seen, sighting.seen_at)
        self.last_seen = max(self.last_seen, sighting.seen_at)
        if sighting.name:
            self.name = sighting.name
        if sighting.address_type:
            self.address_type = sighting.address_type
        self.signal.observe(sighting.seen_at, sighting.rssi)
        self.company_ids.update(sighting.manufacturer_data.keys())
        self.service_uuids.update(u.lower() for u in sighting.service_uuids)

    # Convenience views kept for callers (and tests) that think in
    # terms of the record rather than its signal track.
    @property
    def rssi_last(self) -> int | None:
        return self.signal.last

    @property
    def rssi_closest(self) -> int | None:
        return self.signal.closest

    @property
    def rssi_history(self) -> list[tuple[float, int]]:
        return self.signal.history

    def trend(self) -> str | None:
        return self.signal.trend()

    @property
    def address_kind(self) -> str | None:
        return address_kind(self.address, self.address_type)

    @property
    def companies(self) -> list[str]:
        return sorted(company_name(cid) for cid in self.company_ids)

    def to_dict(self) -> dict:
        return {
            "address": self.address,
            "address_kind": self.address_kind,
            "name": self.name,
            "kind": self.kind,
            "details": list(self.details),
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
            "sightings": self.sightings,
            "rssi_last": self.rssi_last,
            "rssi_closest": self.rssi_closest,
            "rssi_median": self.signal.median(),
            "trend": self.trend(),
            "companies": self.companies,
            "service_uuids": sorted(self.service_uuids),
        }


class Registry:
    """Folds sightings into one DeviceRecord per address."""

    def __init__(self) -> None:
        self._devices: dict[str, DeviceRecord] = {}
        self.total_sightings = 0

    def observe(self, sighting: Sighting) -> tuple[DeviceRecord, bool]:
        """Record a sighting. Returns (record, is_new_device)."""
        self.total_sightings += 1
        record = self._devices.get(sighting.address)
        if record is None:
            record = DeviceRecord(
                address=sighting.address,
                first_seen=sighting.seen_at,
                last_seen=sighting.seen_at,
            )
            self._devices[sighting.address] = record
            record.observe(sighting)
            return record, True
        record.observe(sighting)
        return record, False

    def get(self, address: str) -> DeviceRecord | None:
        return self._devices.get(address)

    def __len__(self) -> int:
        return len(self._devices)

    def __iter__(self):
        return iter(self._devices.values())

    @property
    def devices(self) -> list[DeviceRecord]:
        """All records, closest (strongest best RSSI) first."""
        return sorted(
            self._devices.values(),
            key=lambda r: (r.rssi_closest is None, -(r.rssi_closest or 0)),
        )

    def to_dict(self) -> dict:
        return {
            "devices": [r.to_dict() for r in self.devices],
            "total_sightings": self.total_sightings,
            "device_count": len(self),
        }
