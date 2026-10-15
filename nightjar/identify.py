"""Level 3, second half: identity resolution.

Addresses lie. Phones rotate their BLE address precisely so listeners
can't follow them, so a registry keyed on address shatters one phone
into dozens of ghosts. Identity resolution groups sightings by what
the device *is* instead: a stable name, an AirPods model signature,
or a fingerprint of the stable core of its Continuity payload.

The fingerprint is epoch-scoped: when a phone rotates its address it
also rotates the volatile bytes of its broadcasts, so correlation is
strong inside a rotation epoch and fades across epochs. That fade is
Apple's privacy design working as intended — nightjar reports what it
can support, and labels the confidence honestly.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field

from .continuity import (
    APPLE_COMPANY_ID, identify_apple, parse_continuity, parse_findmy,
)
from .registry import COMPANY_NAMES, Sighting

MICROSOFT_COMPANY_ID = 0x0006
SAMSUNG_COMPANY_ID = 0x0075

# Service UUIDs advertised by standalone tracker tags.
TRACKER_SERVICE_UUIDS = {
    "0000feed-0000-1000-8000-00805f9b34fb",  # Tile
    "0000fd5a-0000-1000-8000-00805f9b34fb",  # Samsung SmartThings Finding
}


def _stable_fingerprint(sighting: Sighting) -> str | None:
    """Hash of the parts of a broadcast that don't change per packet.

    For Apple payloads, volatile bytes are masked per message type:
    Proximity Pairing carries battery nibbles and a lid counter that
    change constantly, so only its constant prefix and model bytes
    count. Other messages hash whole — they repeat verbatim within a
    rotation epoch in real captures.
    """
    payload = sighting.manufacturer_data.get(APPLE_COMPANY_ID)
    if payload is None:
        return None
    if parse_findmy(payload) is not None:
        return None  # Find My keys rotate by design; nothing stable to hash
    canonical = bytearray()
    for message in parse_continuity(payload):
        canonical.append(message.type_id)
        if message.type_id == 0x07:  # Proximity Pairing
            canonical += message.value[:4]
        else:
            canonical += message.value
    if not canonical:
        return None
    return hashlib.sha1(bytes(canonical)).hexdigest()[:12]


def kind_of(sighting: Sighting) -> tuple[str, list[str]]:
    """Best (kind, details) for one sighting, from all its signals."""
    details: list[str] = []
    payload = sighting.manufacturer_data.get(APPLE_COMPANY_ID)
    if payload:
        ident = identify_apple(payload)
        return ident.kind, ident.details
    ms = sighting.manufacturer_data.get(MICROSOFT_COMPANY_ID)
    if ms is not None:
        if ms[:1] == b"\x03":
            return "Windows device (Swift Pair)", details
        return "Microsoft device", details
    if SAMSUNG_COMPANY_ID in sighting.manufacturer_data:
        return "Samsung device", details
    lowered = {u.lower() for u in sighting.service_uuids}
    if lowered & TRACKER_SERVICE_UUIDS:
        return "Tracker tag", details
    if sighting.name:
        return "Named device", details
    return "Unknown device", details


@dataclass
class Identity:
    """One real-world device, possibly behind many addresses."""

    key: str
    kind: str = "Unknown device"
    first_seen: float = 0.0
    last_seen: float = 0.0
    sightings: int = 0
    addresses: set[str] = field(default_factory=set)
    names: set[str] = field(default_factory=set)
    companies: set[str] = field(default_factory=set)
    service_uuids: set[str] = field(default_factory=set)
    details: list[str] = field(default_factory=list)
    basis: str = "address"  # "address" | "payload fingerprint"
    findmy: bool = False  # seen broadcasting in Find My accessory format

    @property
    def label(self) -> str:
        if self.names:
            return sorted(self.names)[0]
        return self.kind

    @property
    def tracker_like(self) -> bool:
        """Unnamed, and shaped like a standalone tracking tag."""
        if self.names:
            return False
        if self.findmy:
            return True
        if self.service_uuids & TRACKER_SERVICE_UUIDS:
            return True
        return self.kind in ("Find My device (AirTag-class)", "Tracker tag")

    def observe(self, sighting: Sighting, kind: str, details: list[str]):
        self.sightings += 1
        if self.first_seen == 0.0 or sighting.seen_at < self.first_seen:
            self.first_seen = sighting.seen_at
        self.last_seen = max(self.last_seen, sighting.seen_at)
        self.addresses.add(sighting.address)
        if sighting.name:
            self.names.add(sighting.name)
        for cid in sighting.manufacturer_data:
            self.companies.add(COMPANY_NAMES.get(cid, f"0x{cid:04X}"))
        apple = sighting.manufacturer_data.get(APPLE_COMPANY_ID)
        if apple is not None and parse_findmy(apple) is not None:
            self.findmy = True
        self.service_uuids.update(u.lower() for u in sighting.service_uuids)
        # Keep the most specific kind seen: a product name beats a family.
        if self.kind in ("Unknown device", "Named device", "Apple device") \
                or (self.kind == "Apple device (Nearby Info)"
                    and kind not in ("Apple device", "Unknown device")):
            self.kind = kind
        if details:
            self.details = details


class IdentityResolver:
    """Groups a stream of sightings (in time order) into identities."""

    def __init__(self) -> None:
        self._identities: dict[str, Identity] = {}

    def observe(self, sighting: Sighting) -> Identity:
        fingerprint = _stable_fingerprint(sighting)
        if fingerprint is not None and not sighting.name:
            key, basis = f"fp:{fingerprint}", "payload fingerprint"
        else:
            key, basis = f"addr:{sighting.address}", "address"
        identity = self._identities.get(key)
        if identity is None:
            identity = Identity(key=key, basis=basis,
                                first_seen=sighting.seen_at)
            self._identities[key] = identity
        kind, details = kind_of(sighting)
        identity.observe(sighting, kind, details)
        return identity

    def get(self, key: str) -> Identity | None:
        return self._identities.get(key)

    @property
    def identities(self) -> list[Identity]:
        return sorted(self._identities.values(),
                      key=lambda i: -i.sightings)

    def __len__(self) -> int:
        return len(self._identities)
