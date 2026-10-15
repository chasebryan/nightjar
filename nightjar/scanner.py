"""Collection: the passive scan itself.

nightjar is receive-only. With real hardware it opens a Bleak scanner
and listens; it never connects to, pairs with, or transmits data to
any device. With simulate=True it consumes the fake neighbourhood from
nightjar.simulate instead, through the same callback.

One honest footnote about "receive-only". A BLE scanner has two
modes. In *passive* mode the radio only listens. In *active* mode it
answers each advertisement with a standard scan request, which the
device may answer with a scan response (that is where many device
names live). Scan requests carry no data beyond the scanner's own
address, but they are transmissions. nightjar asks for passive mode
first and falls back to active with a visible notice when the platform
can't do passive — CoreBluetooth on macOS can't, and BlueZ on Linux
needs its experimental features switched on. `--active` picks active
mode outright; `--passive` refuses to fall back.
"""

from __future__ import annotations

import asyncio
import random
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass, field

from .registry import Sighting
from .simulate import random_sighting

OnSighting = Callable[[Sighting], None]

MODES = ("passive", "active")


@dataclass
class ScanOutcome:
    """How the scan actually ran — the mode in force, and any caveats."""

    mode: str  # "passive" | "active" | "simulated"
    notes: list[str] = field(default_factory=list)


def _address_type(device) -> str | None:
    """Best-effort address type from the backend's own details."""
    details = getattr(device, "details", None)
    try:
        if isinstance(details, dict):  # BlueZ: {"path": ..., "props": {...}}
            props = details.get("props") or {}
            value = props.get("AddressType")
            return str(value).lower() if value else None
        adv = getattr(details, "adv", None)  # WinRT raw advertisement
        value = getattr(adv, "bluetooth_address_type", None)
        if value is not None:
            number = int(getattr(value, "value", value))
            return {0: "public", 1: "random"}.get(number)
    except Exception:
        return None
    return None


def _to_sighting(device, advertisement) -> Sighting:
    rssi = getattr(advertisement, "rssi", None)
    if rssi is None:
        rssi = getattr(device, "rssi", None)
    service_data = {}
    for uuid, payload in (getattr(advertisement, "service_data", None) or {}).items():
        service_data[str(uuid).lower()] = bytes(payload)
    return Sighting(
        address=device.address,
        name=advertisement.local_name or device.name,
        rssi=rssi,
        manufacturer_data={
            int(cid): bytes(payload)
            for cid, payload in (advertisement.manufacturer_data or {}).items()
        },
        service_uuids=[str(u).lower() for u in (advertisement.service_uuids or [])],
        tx_power=advertisement.tx_power,
        seen_at=time.time(),
        service_data=service_data,
        address_type=_address_type(device),
    )


async def _scan_simulated(duration, on_sighting, seed, on_start) -> ScanOutcome:
    rng = random.Random(seed)
    loop = asyncio.get_running_loop()
    outcome = ScanOutcome(mode="simulated")
    if on_start is not None:
        on_start(outcome)
    end = None if duration is None else loop.time() + duration
    while end is None or loop.time() < end:
        on_sighting(random_sighting(rng))
        await asyncio.sleep(rng.uniform(0.15, 0.6))
    return outcome


def _bluez_passive_patterns():
    """A wide net of BlueZ advertisement-monitor patterns.

    BlueZ's passive scanning only reports advertisements matching at
    least one pattern, so cast widely: the usual Flags values (most
    connectable devices), the big makers' manufacturer-data prefixes
    (Apple's covers AirTags, which carry no Flags field at all), and
    the service-data UUIDs tracker tags and beacons speak through.
    """
    try:
        from bleak.assigned_numbers import AdvertisementDataType
        from bleak.backends.bluezdbus.advertisement_monitor import OrPattern
    except Exception:  # older bleak, or no BlueZ backend
        return None
    patterns = []
    for flags in (0x02, 0x04, 0x05, 0x06, 0x1A, 0x1E):
        patterns.append(OrPattern(0, AdvertisementDataType.FLAGS, bytes([flags])))
    for company_id in (0x004C, 0x0006, 0x0075, 0x00E0):
        patterns.append(OrPattern(0, AdvertisementDataType.MANUFACTURER_SPECIFIC_DATA,
                                  company_id.to_bytes(2, "little")))
    for service in (0xFEAA, 0xFD5A, 0xFEED, 0xFE2C):
        patterns.append(OrPattern(0, AdvertisementDataType.SERVICE_DATA_UUID16,
                                  service.to_bytes(2, "little")))
    return patterns


def _short_error(exc: BaseException) -> str:
    text = str(exc).strip().splitlines()[0] if str(exc).strip() else type(exc).__name__
    return text[:120]


async def _scan_real(duration, on_sighting, *, mode, strict, adapter,
                     on_start) -> ScanOutcome:
    try:
        from bleak import BleakScanner
    except ImportError as exc:  # pragma: no cover - environment issue
        raise RuntimeError(
            "bleak is not installed. Install nightjar's dependencies, "
            "or try --simulate to run without Bluetooth hardware."
        ) from exc

    def callback(device, advertisement):
        on_sighting(_to_sighting(device, advertisement))

    attempts = [mode] if (mode == "active" or strict) else ["passive", "active"]
    notes: list[str] = []
    for attempt in attempts:
        kwargs: dict = {"detection_callback": callback, "scanning_mode": attempt}
        if adapter:
            kwargs["adapter"] = adapter
        if attempt == "passive" and sys.platform.startswith("linux"):
            patterns = _bluez_passive_patterns()
            if patterns:
                kwargs["bluez"] = {"or_patterns": patterns}
        try:
            scanner = BleakScanner(**kwargs)
            await scanner.start()
        except Exception as exc:
            if attempt == "passive" and not strict:
                notes.append(
                    "passive scanning is not available here "
                    f"({_short_error(exc)}); using active scanning, which "
                    "sends standard scan requests. Pass --active to choose "
                    "this silently, or --passive to refuse the fallback.")
                continue
            raise RuntimeError(
                f"could not start {attempt} scanning: {_short_error(exc)}"
            ) from exc
        outcome = ScanOutcome(mode=attempt, notes=notes)
        if on_start is not None:
            on_start(outcome)
        try:
            if duration is None:
                await asyncio.Event().wait()  # until cancelled (Ctrl-C)
            else:
                await asyncio.sleep(duration)
        finally:
            await scanner.stop()
        return outcome
    raise RuntimeError("could not start the Bluetooth scanner")  # pragma: no cover


async def run_scan(duration, on_sighting, *, simulate=False, seed=None,
                   mode: str = "passive", strict: bool = False,
                   adapter: str | None = None,
                   on_start: Callable[[ScanOutcome], None] | None = None
                   ) -> ScanOutcome:
    """Listen for `duration` seconds (None = until interrupted).

    `mode` is the scanning mode to ask for; with `strict` False a
    failed passive start falls back to active. `on_start` is called
    once scanning is actually under way, with the mode in force.
    """
    if mode not in MODES:
        raise ValueError(f"mode must be one of {MODES}, not {mode!r}")
    if simulate:
        return await _scan_simulated(duration, on_sighting, seed, on_start)
    return await _scan_real(duration, on_sighting, mode=mode, strict=strict,
                            adapter=adapter, on_start=on_start)
