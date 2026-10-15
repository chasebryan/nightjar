"""A fake BLE neighbourhood, so nightjar can be tried without hardware.

Every profile is a believable device: a pair of AirPods whose
Continuity payload is framed the way real ones are (so Level 3 can
decode their model and batteries out of it), a rotating-address
iPhone, a TV, a Windows laptop, and a tracker tag.

The rotating phone is the teaching device: keyed on address it
splinters into dozens of registry ghosts, while identity resolution
(Level 3) folds it back into one device — because its broadcast's
stable core repeats within a rotation epoch, the way real captures
behave.
"""

from __future__ import annotations

import random
import time

from .registry import Sighting

_APPLE = 0x004C
_MICROSOFT = 0x0006
_SAMSUNG = 0x0075

# Proximity Pairing (0x07): [type][len=25][const][model][status]
# [pod batteries][case battery][lid counter][colour][zeros...]
_AIRPODS_VALUE = bytes(
    [0x01, 0x0E, 0x20, 0x03, 0x98, 0x70, 0x08, 0x00] + [0x00] * 17
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


class _Profile:
    def __init__(self, *, name, base_rssi, weight, address=None,
                 manufacturer_data=None, service_uuids=None, rotates=False):
        self.name = name
        self.base_rssi = base_rssi
        self.weight = weight
        self.address = address
        self.manufacturer_data = manufacturer_data or {}
        self.service_uuids = service_uuids or []
        self.rotates = rotates


PROFILES = [
    _Profile(
        name="AirPods Pro", base_rssi=-48, weight=5,
        address="C1:2A:9D:44:10:7E",
        manufacturer_data={_APPLE: _AIRPODS_PAYLOAD},
    ),
    _Profile(
        name=None, base_rssi=-63, weight=4,  # an iPhone: Nearby Info only
        manufacturer_data={_APPLE: _IPHONE_PAYLOAD},
        rotates=True,
    ),
    _Profile(
        name="Samsung QLED TV", base_rssi=-71, weight=2,
        address="8C:3B:AD:91:22:0F",
        manufacturer_data={_SAMSUNG: bytes.fromhex("7500420001")},
    ),
    _Profile(
        name=None, base_rssi=-58, weight=3,  # a Tile-style tracker tag
        address="D4:61:0A:BE:37:52",
        service_uuids=["0000feed-0000-1000-8000-00805f9b34fb"],
    ),
    _Profile(
        name=None, base_rssi=-70, weight=3,  # an AirTag, separated
        address="E7:04:9B:12:6C:88",
        manufacturer_data={_APPLE: _AIRTAG_PAYLOAD},
    ),
    _Profile(
        name="Surface Laptop", base_rssi=-66, weight=2,
        address="5A:20:C8:77:91:3D",
        manufacturer_data={_MICROSOFT: bytes.fromhex("03060800")},
    ),
]


def _random_address(rng: random.Random) -> str:
    return ":".join(f"{rng.randrange(256):02X}" for _ in range(6))


def random_sighting(rng: random.Random, now: float | None = None) -> Sighting:
    """One plausible advertisement from the fake neighbourhood."""
    profile = rng.choices(PROFILES, weights=[p.weight for p in PROFILES])[0]
    address = _random_address(rng) if profile.rotates else profile.address
    return Sighting(
        address=address,
        name=profile.name,
        rssi=profile.base_rssi + rng.randint(-6, 6),
        manufacturer_data=dict(profile.manufacturer_data),
        service_uuids=list(profile.service_uuids),
        seen_at=time.time() if now is None else now,
    )
