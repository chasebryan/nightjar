"""A fake BLE neighbourhood, so nightjar can be tried without hardware.

Every profile is a believable device: a pair of AirPods whose
Continuity payload is framed the way real ones are (so Level 3 can
decode their model and batteries out of it), a rotating-address
iPhone, a TV, a Windows laptop, tracker tags of three persuasions,
Fast Pair earbuds, a Ruuvi sensor.

The rotating phone is the teaching device: keyed on address it
splinters into dozens of registry ghosts, while identity resolution
(Level 3) folds it back into one device — because its broadcast's
stable core repeats within a rotation epoch, the way real captures
behave.

`write_demo_log` goes further and writes a whole week-in-the-life:
labelled home and office sessions over several days, residents in
each place, and one separated AirTag that turns up everywhere the
listener goes — so `report` and `trackers` have something to find.
"""

from __future__ import annotations

import json
import random
import time
import uuid
from dataclasses import dataclass, field

from . import __version__
from .registry import Sighting

_APPLE = 0x004C
_MICROSOFT = 0x0006
_SAMSUNG = 0x0075
_RUUVI = 0x0499

_TILE_UUID = "0000feed-0000-1000-8000-00805f9b34fb"
_FAST_PAIR_UUID = "0000fe2c-0000-1000-8000-00805f9b34fb"
_EDDYSTONE_UUID = "0000feaa-0000-1000-8000-00805f9b34fb"

# Proximity Pairing (0x07): [type][len=25][prefix][model][status]
# [pod batteries][charging | case battery][lid][colour][zero][encrypted]
# status 0x2A: not flipped (0x20), left (0x02) and right (0x08) in ear.
_AIRPODS_VALUE = bytes(
    [0x01, 0x0E, 0x20, 0x2A, 0x98, 0x07, 0x08, 0x00] + [0x00] * 17
)
_AIRPODS_PAYLOAD = bytes([0x07, len(_AIRPODS_VALUE)]) + _AIRPODS_VALUE

# Nearby Info (0x10): [type][len=17][state/action][device bytes...]
_IPHONE_PAYLOAD = bytes([0x10, 0x11, 0x03, 0x21, 0x8A, 0x3C, 0x51, 0x09,
                         0xBE, 0x77, 0x02, 0xD4, 0x6F, 0x88, 0x1A, 0xC5,
                         0x49, 0xE0, 0x5B])

# Find My accessory broadcast: NOT a TLV chain — the fixed format
# [0x12][0x19][status][22 public-key bytes][key bits][hint].
# Status 0x50 = battery medium, in the documented AirTag encoding.
_AIRTAG_PAYLOAD = bytes([0x12, 0x19, 0x50]) + bytes(range(0x30, 0x46)) \
    + bytes([0x00, 0x00])

# The short form an accessory broadcasts while its owner is nearby.
_AIRTAG_WITH_OWNER_PAYLOAD = bytes([0x12, 0x02, 0x10, 0x00])

# Microsoft CDP beacon: scenario 1 (Bluetooth), device type 15 (laptop).
_SURFACE_PAYLOAD = bytes([0x01, 0x0F, 0x20, 0x00]) + bytes(range(0x40, 0x54))

# Google Find My Device network beacon: Eddystone frame 0x40 + 20-byte EID.
_FMDN_SERVICE_DATA = bytes([0x40]) + bytes(range(0x60, 0x74)) + bytes([0x00])

# Fast Pair, paired and not discoverable: version/flags + account-key filter.
_FAST_PAIR_SERVICE_DATA = bytes([0x00, 0x62]) + bytes(range(0x11, 0x1D))

# Ruuvi RAWv2: 22.5 °C, 45 % RH, 1013.25 hPa, 3.0 V battery.
_RUUVI_PAYLOAD = (bytes([0x05]) + (4500).to_bytes(2, "big")
                  + (18000).to_bytes(2, "big") + (51325).to_bytes(2, "big")
                  + bytes(6) + ((1400 << 5) | 0x1F).to_bytes(2, "big")
                  + bytes([0x12, 0x00, 0x2A]) + bytes([0xC1, 0x02, 0x03, 0x04, 0x05, 0x06]))


@dataclass
class _Profile:
    name: str | None
    base_rssi: int
    weight: int
    address: str | None = None
    manufacturer_data: dict[int, bytes] = field(default_factory=dict)
    service_uuids: list[str] = field(default_factory=list)
    service_data: dict[str, bytes] = field(default_factory=dict)
    rotates: bool = False
    address_type: str | None = None


PROFILES = [
    _Profile(
        name="AirPods Pro", base_rssi=-48, weight=5,
        address="C1:2A:9D:44:10:7E",
        manufacturer_data={_APPLE: _AIRPODS_PAYLOAD},
        address_type="random",
    ),
    _Profile(
        name=None, base_rssi=-63, weight=4,  # an iPhone: Nearby Info only
        manufacturer_data={_APPLE: _IPHONE_PAYLOAD},
        rotates=True, address_type="random",
    ),
    _Profile(
        name="Samsung QLED TV", base_rssi=-71, weight=2,
        address="8C:3B:AD:91:22:0F",
        manufacturer_data={_SAMSUNG: bytes.fromhex("7500420001")},
        address_type="public",
    ),
    _Profile(
        name=None, base_rssi=-58, weight=3,  # a Tile-style tracker tag
        address="D4:61:0A:BE:37:52",
        service_uuids=[_TILE_UUID],
        service_data={_TILE_UUID: bytes([0x02, 0x00])},
        address_type="random",
    ),
    _Profile(
        name=None, base_rssi=-70, weight=3,  # an AirTag, separated
        address="E7:04:9B:12:6C:88",
        manufacturer_data={_APPLE: _AIRTAG_PAYLOAD},
        address_type="random",
    ),
    _Profile(
        name=None, base_rssi=-74, weight=2,  # an AirTag riding with its owner
        address="F2:19:77:AC:03:5E",
        manufacturer_data={_APPLE: _AIRTAG_WITH_OWNER_PAYLOAD},
        address_type="random",
    ),
    _Profile(
        name="Surface Laptop", base_rssi=-66, weight=2,
        address="DA:20:C8:77:91:3D",
        manufacturer_data={_MICROSOFT: _SURFACE_PAYLOAD},
        address_type="random",
    ),
    _Profile(
        name=None, base_rssi=-67, weight=2,  # a Google FMDN tracker tag
        address="C9:5D:11:08:AF:40",
        service_uuids=[_EDDYSTONE_UUID],
        service_data={_EDDYSTONE_UUID: _FMDN_SERVICE_DATA},
        address_type="random",
    ),
    _Profile(
        name=None, base_rssi=-61, weight=2,  # Fast Pair earbuds, paired
        address="FB:30:E2:19:4C:A1",
        service_uuids=[_FAST_PAIR_UUID],
        service_data={_FAST_PAIR_UUID: _FAST_PAIR_SERVICE_DATA},
        address_type="random",
    ),
    _Profile(
        name="Ruuvi 4B2C", base_rssi=-76, weight=1,
        address="C1:02:03:04:05:06",
        manufacturer_data={_RUUVI: _RUUVI_PAYLOAD},
        address_type="random",
    ),
]


def _random_address(rng: random.Random) -> str:
    first = 0x40 | rng.randrange(0x40)  # 01xxxxxx: a resolvable private address
    rest = [rng.randrange(256) for _ in range(5)]
    return ":".join(f"{b:02X}" for b in [first, *rest])


def _sighting_from(profile: _Profile, rng: random.Random, now: float,
                   address: str | None = None, rssi: int | None = None) -> Sighting:
    if address is None:
        address = _random_address(rng) if profile.rotates else profile.address
    return Sighting(
        address=address or _random_address(rng),
        name=profile.name,
        rssi=profile.base_rssi + rng.randint(-6, 6) if rssi is None else rssi,
        manufacturer_data=dict(profile.manufacturer_data),
        service_uuids=list(profile.service_uuids),
        seen_at=now,
        service_data=dict(profile.service_data),
        address_type=profile.address_type,
    )


def random_sighting(rng: random.Random, now: float | None = None) -> Sighting:
    """One plausible advertisement from the fake neighbourhood."""
    profile = rng.choices(PROFILES, weights=[p.weight for p in PROFILES])[0]
    return _sighting_from(profile, rng, time.time() if now is None else now)


# --- A multi-day demo log --------------------------------------------------

@dataclass
class _Resident:
    profile: _Profile
    places: tuple[str, ...]          # which session labels it lives in
    interval: tuple[float, float]    # seconds between sightings
    rotate_per_session: bool = False  # fresh address (and payload) each session
    rotate_per_day: bool = False      # fresh address each day (AirTag, separated)
    presence: float = 1.0             # fraction of the session it is present
    late_start: float = 0.0           # fraction of the session before it arrives


def _daily_plan(day_start: float) -> list[tuple[str, float, float]]:
    """(label, start, end) for one day's listening, in epoch seconds."""
    h = 3600.0
    return [
        ("home", day_start + 7.5 * h, day_start + 8.75 * h),
        ("office", day_start + 9.25 * h, day_start + 17.5 * h),
        ("home", day_start + 18.25 * h, day_start + 22.5 * h),
    ]


def _nearby_payload(rng: random.Random, action: int = 0x03) -> bytes:
    body = bytes([action]) + bytes(rng.randrange(256) for _ in range(16))
    return bytes([0x10, len(body)]) + body


def _demo_residents(rng: random.Random) -> list[_Resident]:
    def profile(**kw) -> _Profile:
        return _Profile(**kw)

    return [
        # The listener's own earbuds: everywhere, named, never a suspect.
        _Resident(profile(name="AirPods Pro", base_rssi=-46, weight=1,
                          address="C1:2A:9D:44:10:7E",
                          manufacturer_data={_APPLE: _AIRPODS_PAYLOAD},
                          address_type="random"),
                  places=("home", "office"), interval=(60, 150)),
        # Home.
        _Resident(profile(name="Samsung QLED TV", base_rssi=-70, weight=1,
                          address="8C:3B:AD:91:22:0F",
                          manufacturer_data={_SAMSUNG: bytes.fromhex("7500420001")},
                          address_type="public"),
                  places=("home",), interval=(90, 200)),
        _Resident(profile(name=None, base_rssi=-62, weight=1,  # partner's iPhone
                          manufacturer_data={_APPLE: _nearby_payload(rng)},
                          rotates=True, address_type="random"),
                  places=("home",), interval=(60, 160), rotate_per_session=True,
                  presence=0.8),
        _Resident(profile(name="Ruuvi 4B2C", base_rssi=-78, weight=1,
                          address="C1:02:03:04:05:06",
                          manufacturer_data={_RUUVI: _RUUVI_PAYLOAD},
                          address_type="random"),
                  places=("home",), interval=(120, 240)),
        # Office.
        _Resident(profile(name="Office Printer", base_rssi=-72, weight=1,
                          address="94:57:A5:30:1E:C2",
                          manufacturer_data={0x0065: bytes([0x01, 0x02])},
                          address_type="public"),
                  places=("office",), interval=(120, 240)),
        _Resident(profile(name="Surface Laptop", base_rssi=-64, weight=1,
                          address="DA:20:C8:77:91:3D",
                          manufacturer_data={_MICROSOFT: _SURFACE_PAYLOAD},
                          address_type="random"),
                  places=("office",), interval=(90, 200), presence=0.9),
        _Resident(profile(name=None, base_rssi=-69, weight=1,  # coworker's Tile
                          address="D4:61:0A:BE:37:52",
                          service_uuids=[_TILE_UUID],
                          service_data={_TILE_UUID: bytes([0x02, 0x00])},
                          address_type="random"),
                  places=("office",), interval=(90, 200), presence=0.7),
        _Resident(profile(name=None, base_rssi=-75, weight=1,  # a coworker's AirTag, with owner
                          address="F2:19:77:AC:03:5E",
                          manufacturer_data={_APPLE: _AIRTAG_WITH_OWNER_PAYLOAD},
                          address_type="random"),
                  places=("office",), interval=(90, 200), presence=0.6),
        _Resident(profile(name=None, base_rssi=-66, weight=1,  # meeting-room beacon
                          address="00:1A:7D:DA:71:13",
                          manufacturer_data={_APPLE: bytes([0x02, 0x15]) + bytes(range(16))
                                             + bytes([0x00, 0x07, 0x00, 0x2A, 0xC5])},
                          address_type="public"),
                  places=("office",), interval=(120, 240)),
        # The follower: a separated AirTag that is wherever the listener is.
        _Resident(profile(name=None, base_rssi=-57, weight=1,
                          manufacturer_data={_APPLE: _AIRTAG_PAYLOAD},
                          rotates=True, address_type="random"),
                  places=("home", "office"), interval=(60, 150),
                  rotate_per_day=True, presence=0.95, late_start=0.0),
    ]


def write_demo_log(path: str, *, days: int = 2, seed: int | None = None,
                   start: float | None = None) -> list[str]:
    """Write a labelled, multi-day demo log. Returns the session ids."""
    rng = random.Random(seed)
    if start is None:
        # Local midnight, `days` days ago, so the sessions end before now.
        now = time.time()
        local = time.localtime(now)
        midnight = now - (local.tm_hour * 3600 + local.tm_min * 60 + local.tm_sec)
        start = midnight - days * 86400.0
    residents = _demo_residents(rng)
    daily_addresses: dict[int, str] = {}
    session_ids: list[str] = []
    with open(path, "w", encoding="utf-8") as fh:
        for day in range(days):
            day_start = start + day * 86400.0
            for index, resident in enumerate(residents):
                if resident.rotate_per_day:
                    daily_addresses[index] = _random_address(rng)
            for label, s_start, s_end in _daily_plan(day_start):
                session_id = uuid.uuid4().hex[:12]
                session_ids.append(session_id)
                fh.write(json.dumps({
                    "type": "session", "session_id": session_id,
                    "label": label, "label_source": "demo",
                    "started_at": s_start, "scan_mode": "simulated",
                    "format": 1, "nightjar_version": __version__,
                }) + "\n")
                events: list[Sighting] = []
                for index, resident in enumerate(residents):
                    if label not in resident.places:
                        continue
                    profile = resident.profile
                    if resident.rotate_per_session:
                        profile = _Profile(
                            name=profile.name, base_rssi=profile.base_rssi,
                            weight=1, rotates=True, address_type=profile.address_type,
                            manufacturer_data={_APPLE: _nearby_payload(rng)})
                    fixed = daily_addresses.get(index)
                    span = s_end - s_start
                    t = s_start + resident.late_start * span + rng.uniform(0, 30)
                    leave_at = s_start + span * resident.presence + rng.uniform(-60, 60)
                    drift = 0
                    while t < min(s_end, leave_at):
                        drift = max(-8, min(8, drift + rng.randint(-2, 2)))
                        rssi = profile.base_rssi + drift + rng.randint(-3, 3)
                        events.append(_sighting_from(profile, rng, t,
                                                     address=fixed, rssi=rssi))
                        t += rng.uniform(*resident.interval)
                events.sort(key=lambda s: s.seen_at)
                for sighting in events:
                    fh.write(json.dumps(sighting.to_dict()) + "\n")
                fh.write(json.dumps({
                    "type": "session_end", "session_id": session_id,
                    "ended_at": s_end, "sightings": len(events),
                }) + "\n")
    return session_ids
