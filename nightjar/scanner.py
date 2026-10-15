"""Collection: the passive scan itself.

nightjar is receive-only. With real hardware it opens a Bleak scanner
and listens; it never connects to, pairs with, or transmits to any
device. With simulate=True it consumes the fake neighbourhood from
nightjar.simulate instead, through the same callback.
"""

from __future__ import annotations

import asyncio
import random
import time
from typing import Callable

from .registry import Sighting
from .simulate import random_sighting

OnSighting = Callable[[Sighting], None]


def _to_sighting(device, advertisement) -> Sighting:
    rssi = getattr(advertisement, "rssi", None)
    if rssi is None:
        rssi = getattr(device, "rssi", None)
    return Sighting(
        address=device.address,
        name=advertisement.local_name or device.name,
        rssi=rssi,
        manufacturer_data=dict(advertisement.manufacturer_data or {}),
        service_uuids=list(advertisement.service_uuids or []),
        tx_power=advertisement.tx_power,
        seen_at=time.time(),
    )


async def _scan_simulated(duration, on_sighting, seed) -> None:
    rng = random.Random(seed)
    loop = asyncio.get_running_loop()
    end = None if duration is None else loop.time() + duration
    while end is None or loop.time() < end:
        on_sighting(random_sighting(rng))
        await asyncio.sleep(rng.uniform(0.15, 0.6))


async def _scan_real(duration, on_sighting) -> None:
    try:
        from bleak import BleakScanner
    except ImportError as exc:  # pragma: no cover - environment issue
        raise RuntimeError(
            "bleak is not installed. Install nightjar's dependencies, "
            "or try --simulate to run without Bluetooth hardware."
        ) from exc

    def callback(device, advertisement):
        on_sighting(_to_sighting(device, advertisement))

    async with BleakScanner(detection_callback=callback):
        if duration is None:
            await asyncio.Event().wait()  # until cancelled (Ctrl-C)
        else:
            await asyncio.sleep(duration)


async def run_scan(duration, on_sighting, *, simulate=False, seed=None) -> None:
    """Listen for `duration` seconds (None = until interrupted)."""
    if simulate:
        await _scan_simulated(duration, on_sighting, seed)
    else:
        await _scan_real(duration, on_sighting)
