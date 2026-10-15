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

Classification — *what kind of thing is this* — draws on every channel
a broadcast has: Apple's Continuity chain, other makers' manufacturer
data, and the service UUIDs and service data that beacons, earbuds
and tracker tags speak through.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field

from .companies import company_name
from .continuity import (
    APPLE_COMPANY_ID,
    FindMyState,
    identify_apple,
    parse_continuity,
    parse_findmy,
)
from .registry import Sighting, SignalTrack, address_kind
from .remoteid import DroneReport, parse_service_data, remoteid_value
from .remoteid import describe as describe_drone
from .services import TRACKER_SERVICE_UUIDS, identify_services, normalize_uuid
from .vendors import identify_manufacturer

__all__ = [
    "TRACKER_SERVICE_UUIDS",
    "Classification",
    "Identity",
    "IdentityResolver",
    "classify",
    "kind_of",
]

# Specificity ranks: how far a kind narrows the device down. A more
# specific kind always replaces a less specific one; equally specific
# kinds keep the first seen, so identities don't flap between labels.
RANK_UNKNOWN = 0
RANK_FAMILY = 10       # "Apple device", "Samsung device"
RANK_FAMILY_HINT = 15  # "Apple device (Nearby Info)"
RANK_SUBFAMILY = 20    # "Apple Watch", "Windows laptop"
RANK_PRODUCT = 30      # "AirPods Pro", "Tile tracker", "RuuviTag sensor"

_CONTINUITY_RANK = {1: RANK_FAMILY, 2: RANK_SUBFAMILY, 3: RANK_PRODUCT}
_SERVICE_RANK = {1: RANK_FAMILY, 2: RANK_SUBFAMILY, 3: RANK_PRODUCT}


@dataclass
class Classification:
    """What one sighting says about the device behind it."""

    kind: str = "Unknown device"
    details: list[str] = field(default_factory=list)
    rank: int = RANK_UNKNOWN
    tracker_shaped: bool = False   # shaped like a standalone tag
    rotating_phone: bool = False   # a phone/wearable rotating by design
    findmy: FindMyState | None = None
    messages: list[str] = field(default_factory=list)


def classify(sighting: Sighting) -> Classification:
    """Best classification of one sighting, from all its signals."""
    apple = sighting.manufacturer_data.get(APPLE_COMPANY_ID)
    if apple:
        ident = identify_apple(apple)
        tracker = ident.findmy is not None and ident.findmy.separated
        rank = _CONTINUITY_RANK.get(ident.specificity, RANK_FAMILY)
        if ident.kind == "Apple device (Nearby Info)":
            rank = RANK_FAMILY_HINT
        return Classification(kind=ident.kind, details=list(ident.details),
                              rank=rank, tracker_shaped=tracker,
                              findmy=ident.findmy, messages=ident.messages)

    service = identify_services(sighting.service_uuids, sighting.service_data)
    if service is not None and service.specificity >= 2:
        return Classification(
            kind=service.kind, details=list(service.details),
            rank=_SERVICE_RANK[service.specificity],
            tracker_shaped=service.tracker_shaped,
            rotating_phone=service.rotating_phone)

    vendor = identify_manufacturer(sighting.manufacturer_data)
    if vendor is not None:
        rank = {1: RANK_FAMILY, 2: RANK_SUBFAMILY, 3: RANK_PRODUCT}[
            min(3, max(1, vendor.specificity))]
        return Classification(kind=vendor.kind, details=list(vendor.details),
                              rank=rank)

    if service is not None:
        return Classification(kind=service.kind, details=list(service.details),
                              rank=RANK_FAMILY)
    if sighting.name:
        return Classification(kind="Named device")
    return Classification()


def kind_of(sighting: Sighting) -> tuple[str, list[str]]:
    """Best (kind, details) for one sighting — the classic view."""
    result = classify(sighting)
    return result.kind, result.details


def remoteid_serial(sighting: Sighting) -> str | None:
    """The drone serial a sighting broadcasts in a Basic ID, or None."""
    value = remoteid_value(sighting.service_data)
    if value is None:
        return None
    for message in parse_service_data(value):
        if message.basic_id is not None and message.basic_id.is_serial:
            return message.basic_id.uas_id
    return None


def _stable_fingerprint(sighting: Sighting) -> str | None:
    """Hash of the parts of a broadcast that don't change per packet.

    For Apple payloads, volatile bytes are masked per message type:
    Proximity Pairing carries battery nibbles and a lid counter that
    change constantly, so only its prefix and model bytes count. Other
    messages hash whole — they repeat verbatim within a rotation epoch
    in real captures.
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
            canonical += message.value[:3]
        else:
            canonical += message.value
    if not canonical:
        return None
    return hashlib.sha1(bytes(canonical)).hexdigest()[:12]


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
    basis: str = "address"  # "address" | "payload fingerprint" | "name + fingerprint"
    findmy: bool = False            # ever seen in the Find My separated format
    findmy_with_owner: bool = False  # ever seen in the short "with owner" format
    tracker_shaped: bool = False    # ever classified as tag-shaped
    rotating_phone: bool = False    # ever classified as a rotating phone
    rank: int = RANK_UNKNOWN
    signal: SignalTrack = field(default_factory=SignalTrack)
    address_kinds: set[str] = field(default_factory=set)
    last_address: str = ""
    last_name: str | None = None
    drone: DroneReport | None = None   # accumulated Remote ID across sightings
    drone_serial: str | None = None    # its broadcast serial, once seen

    @property
    def label(self) -> str:
        # A Remote ID serial is a licence plate — it wins over any local name.
        if self.drone_serial:
            return f"Drone {self.drone_serial}"
        if self.last_name:
            return self.last_name
        if self.names:
            return sorted(self.names)[0]
        return self.kind

    @property
    def headline(self) -> str:
        """'Chase's iPhone (Apple device)' — or just the kind when unnamed."""
        if self.label == self.kind:
            return self.kind
        if self.drone_serial:  # avoid "Drone X (Drone (Remote ID))"
            return self.label
        return f"{self.label} ({self.kind})"

    @property
    def tracker_like(self) -> bool:
        """Unnamed, and shaped like a standalone tracking tag.

        A Find My accessory still riding with its owner is not a tag
        following anyone, and a rotating phone is not a tag at all.
        """
        if self.names or self.rotating_phone:
            return False
        if self.findmy:
            return True
        if self.service_uuids & TRACKER_SERVICE_UUIDS:
            return True
        return self.tracker_shaped

    @property
    def rotates(self) -> bool:
        """More than one address, or an address the radio says rotates."""
        return (len(self.addresses) > 1
                or "random resolvable" in self.address_kinds
                or "random non-resolvable" in self.address_kinds)

    def rotation_note(self) -> str | None:
        """'7 addresses (rotates)', 'private address (rotates)', or None."""
        if len(self.addresses) > 1:
            return f"{len(self.addresses)} addresses (rotates)"
        if "random resolvable" in self.address_kinds \
                or "random non-resolvable" in self.address_kinds:
            return "private address (rotates)"
        return None

    def observe(self, sighting: Sighting, kind: str, details: list[str],
                classification: Classification | None = None) -> None:
        if classification is None:
            classification = classify(sighting)
        self.sightings += 1
        if self.first_seen == 0.0 or sighting.seen_at < self.first_seen:
            self.first_seen = sighting.seen_at
        self.last_seen = max(self.last_seen, sighting.seen_at)
        self.addresses.add(sighting.address)
        self.last_address = sighting.address
        if sighting.name:
            self.names.add(sighting.name)
            self.last_name = sighting.name
        for cid in sighting.manufacturer_data:
            self.companies.add(company_name(cid))
        if classification.findmy is not None:
            if classification.findmy.separated:
                self.findmy = True
            else:
                self.findmy_with_owner = True
        self.tracker_shaped = self.tracker_shaped or classification.tracker_shaped
        self.rotating_phone = self.rotating_phone or classification.rotating_phone
        self.service_uuids.update(normalize_uuid(u) for u in sighting.service_uuids)
        self.service_uuids.update(normalize_uuid(u) for u in sighting.service_data)
        kind_label = address_kind(sighting.address, sighting.address_type)
        if kind_label:
            self.address_kinds.add(kind_label)
        self.signal.observe(sighting.seen_at, sighting.rssi)
        # Keep the most specific kind seen: a product name beats a family.
        if classification.rank > self.rank or self.rank == RANK_UNKNOWN:
            self.kind, self.rank = kind, classification.rank
        if details:
            self.details = list(details)
        # Accumulate Remote ID across the drone's message set, so the
        # details line carries the fullest current picture (serial from a
        # Basic ID, position from a Location, operator from a System).
        value = remoteid_value(sighting.service_data)
        if value is not None:
            if self.drone is None:
                self.drone = DroneReport()
            for message in parse_service_data(value):
                self.drone.ingest(message)
            if self.drone.serial:
                self.drone_serial = self.drone.serial
            self.details = [describe_drone(self.drone)]

    def matches(self, query: str) -> bool:
        """Does a user-typed query name this identity?

        Matches the identity key exactly, an address by prefix, or a
        name / kind / label by substring — all case-insensitively.
        """
        q = query.strip().lower()
        if not q:
            return False
        if q == self.key.lower():
            return True
        if any(a.lower().startswith(q) for a in self.addresses):
            return True
        haystack = [self.label, self.kind, *self.names]
        return any(q in h.lower() for h in haystack if h)

    # Signal views, mirroring DeviceRecord so renderers can treat both alike.
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

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "kind": self.kind,
            "basis": self.basis,
            "first_seen": self.first_seen,
            "last_seen": self.last_seen,
            "sightings": self.sightings,
            "addresses": sorted(self.addresses),
            "address_kinds": sorted(self.address_kinds),
            "rotates": self.rotates,
            "names": sorted(self.names),
            "companies": sorted(self.companies),
            "service_uuids": sorted(self.service_uuids),
            "details": list(self.details),
            "tracker_like": self.tracker_like,
            "findmy_separated": self.findmy,
            "findmy_with_owner": self.findmy_with_owner,
            "drone_serial": self.drone_serial,
            "rssi_last": self.rssi_last,
            "rssi_closest": self.rssi_closest,
            "rssi_median": self.signal.median(),
            "trend": self.trend(),
        }


class IdentityResolver:
    """Groups a stream of sightings (in time order) into identities.

    Keys: a payload fingerprint when the broadcast has a stable core
    (so rotating addresses fold together), the name plus fingerprint
    when the device also announces a name, and the bare address when
    there is nothing better. An address, once assigned to an identity,
    sticks to it — a device that sometimes answers with its name and
    sometimes doesn't is still one device.
    """

    def __init__(self) -> None:
        self._identities: dict[str, Identity] = {}
        self._address_keys: dict[str, str] = {}
        self._address_serials: dict[str, str] = {}

    def _key_for(self, sighting: Sighting) -> tuple[str, str]:
        # A Remote ID serial is a licence plate: it keys the device above
        # address or fingerprint, and folds every address the drone rotates
        # through. Before a Basic ID is seen, the address stands.
        serial = remoteid_serial(sighting)
        if serial is not None:
            self._address_serials[sighting.address] = serial
            return f"rid:{serial}", "remote id"
        learned = self._address_serials.get(sighting.address)
        if learned is not None:
            return f"rid:{learned}", "remote id"
        known = self._address_keys.get(sighting.address)
        if known is not None:
            return known, self._identities[known].basis
        fingerprint = _stable_fingerprint(sighting)
        if fingerprint is not None and sighting.name:
            return f"nfp:{sighting.name}|{fingerprint}", "name + fingerprint"
        if fingerprint is not None:
            return f"fp:{fingerprint}", "payload fingerprint"
        return f"addr:{sighting.address}", "address"

    def observe(self, sighting: Sighting) -> Identity:
        key, basis = self._key_for(sighting)
        identity = self._identities.get(key)
        if identity is None:
            identity = Identity(key=key, basis=basis,
                                first_seen=sighting.seen_at)
            self._identities[key] = identity
        self._address_keys.setdefault(sighting.address, key)
        classification = classify(sighting)
        identity.observe(sighting, classification.kind, classification.details,
                         classification)
        return identity

    def get(self, key: str) -> Identity | None:
        return self._identities.get(key)

    def for_address(self, address: str) -> Identity | None:
        key = self._address_keys.get(address)
        return self._identities.get(key) if key else None

    @property
    def identities(self) -> list[Identity]:
        return sorted(self._identities.values(),
                      key=lambda i: -i.sightings)

    def by_signal(self) -> list[Identity]:
        """Loudest first, most recent breaking ties."""
        return sorted(
            self._identities.values(),
            key=lambda i: (i.rssi_last is None, -(i.rssi_last or 0),
                           -i.last_seen),
        )

    def __len__(self) -> int:
        return len(self._identities)

    def __iter__(self):
        return iter(self._identities.values())

    def to_dict(self) -> dict:
        return {
            "identities": [i.to_dict() for i in self.identities],
            "identity_count": len(self),
        }
