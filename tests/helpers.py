"""Shared fixtures: canned payloads and a terse sighting constructor."""

from __future__ import annotations

from nightjar.registry import Sighting

APPLE = 0x004C
MICROSOFT = 0x0006
BASE = 1_700_000_000.0
HOUR = 3600.0

TILE_UUID = "0000feed-0000-1000-8000-00805f9b34fb"
SMARTTHINGS_UUID = "0000fd5a-0000-1000-8000-00805f9b34fb"
EDDYSTONE_UUID = "0000feaa-0000-1000-8000-00805f9b34fb"
FAST_PAIR_UUID = "0000fe2c-0000-1000-8000-00805f9b34fb"
EXPOSURE_UUID = "0000fd6f-0000-1000-8000-00805f9b34fb"

# The original nightjar test vector for AirPods Pro (status 0x03: flipped,
# right bud in ear; batteries 0x98; charging/case 0x70; lid 0x08).
AIRPODS_LEGACY = bytes.fromhex(
    "0719010e2003987008000000000000000000000000000000000000")
# nightjar 2's simulated AirPods Pro: not flipped, both in ear, L 80 R 90,
# case 70, lid open, white.
AIRPODS_PRO = bytes.fromhex(
    "0719010e202a980708000000000000000000000000000000000000")
AIRTAG_SEPARATED = bytes.fromhex(
    "121950303132333435363738393a3b3c3d3e3f4041424344450000")
AIRTAG_WITH_OWNER = bytes.fromhex("12021000")
IPHONE_NEARBY = bytes.fromhex("101103218a3c5109be7702d46f881ac549e05b")
FMDN_FRAME = bytes([0x40]) + bytes(range(0x60, 0x74)) + bytes([0x00])


def sighting(address="AA:BB:CC:DD:EE:FF", when=BASE, **kw) -> Sighting:
    base = {"name": None, "rssi": -60, "manufacturer_data": {},
            "service_uuids": []}
    base.update(kw)
    return Sighting(address=address, seen_at=when, **base)
