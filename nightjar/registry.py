"""Core data model: individual sightings and the device registry.

A *sighting* is one received BLE advertisement. The *registry* folds
every sighting into one record per device address, so raw noise becomes
a picture of who is around, when they arrived, and how close they got.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

# A handful of Bluetooth SIG company identifiers, for readable summaries.
# Full list: https://www.bluetooth.com/specifications/assigned-numbers/
COMPANY_NAMES = {
    0x004C: "Apple",
    0x0006: "Microsoft",
    0x0075: "Samsung",
    0x00E0: "Google",
    0x0059: "Nordic Semiconductor",
}


def company_name(company_id: int) -> str:
    return COMPANY_NAMES.get(company_id, f"0x{company_id:04X}")


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

    def to_dict(self) -> dict:
        return {
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

    @classmethod
    def from_dict(cls, rec: dict) -> "Sighting":
        return cls(
            address=rec["address"],
            name=rec.get("name"),
            rssi=rec.get("rssi"),
            manufacturer_data={
                int(cid): bytes.fromhex(payload)
                for cid, payload in (rec.get("manufacturer_data") or {}).items()
            },
            service_uuids=list(rec.get("service_uuids") or []),
            tx_power=rec.get("tx_power"),
            seen_at=float(rec.get("seen_at", 0.0)),
        )


@dataclass
class DeviceRecord:
    """Everything nightjar knows about one device address, so far."""

    address: str
    first_seen: float
    last_seen: float
    sightings: int = 0
    name: str | None = None
    rssi_last: int | None = None
    rssi_closest: int | None = None  # strongest RSSI = closest approach
    company_ids: set[int] = field(default_factory=set)
    service_uuids: set[str] = field(default_factory=set)
    # (epoch, rssi) samples, newest last, capped — the raw material
    # for trends, sparklines, and the live radar.
    rssi_history: list = field(default_factory=list)

    HISTORY_CAP = 240

    def observe(self, sighting: Sighting) -> None:
        self.sightings += 1
        self.first_seen = min(self.first_seen, sighting.seen_at)
        self.last_seen = max(self.last_seen, sighting.seen_at)
        if sighting.name:
            self.name = sighting.name
        if sighting.rssi is not None:
            self.rssi_last = sighting.rssi
            if self.rssi_closest is None or sighting.rssi > self.rssi_closest:
                self.rssi_closest = sighting.rssi
            self.rssi_history.append((sighting.seen_at, sighting.rssi))
            if len(self.rssi_history) > self.HISTORY_CAP:
                del self.rssi_history[: len(self.rssi_history) - self.HISTORY_CAP]
        self.company_ids.update(sighting.manufacturer_data.keys())
        self.service_uuids.update(sighting.service_uuids)

    def trend(self) -> str | None:
        """Approaching / receding / steady, from the RSSI history.

        Compares the mean of the older half of samples with the
        younger half; needs a handful of samples and a >3 dB move
        before it claims a direction.
        """
        values = [rssi for _, rssi in self.rssi_history]
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

    @property
    def companies(self) -> list[str]:
        return sorted(company_name(cid) for cid in self.company_ids)

    def to_dict(self) -> dict:
        return {
            "address": self.address,
            "name": self.name,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
            "sightings": self.sightings,
            "rssi_last": self.rssi_last,
            "rssi_closest": self.rssi_closest,
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

    def __len__(self) -> int:
        return len(self._devices)

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
