"""Automatic place labels: where is this listening post right now?

Tracker analysis thinks in places ("seen at home AND at the office"),
and a label you have to remember to type is a label you'll forget.
The cheapest honest place signal a host has is the Wi-Fi network it
is associated with, so nightjar reads it from the OS's own tools —
airport/ipconfig/networksetup on macOS, nmcli/iwgetid on Linux,
netsh on Windows. Reading it transmits nothing.

Returns the SSID (with BSSID appended when available, since the same
SSID name can exist in two places), or None when no association can
be determined — in which case the session simply stays unlabelled.
"""

from __future__ import annotations

import subprocess
import sys
from typing import Callable

Runner = Callable[[list[str]], str]

_AIRPORT = ("/System/Library/PrivateFrameworks/Apple80211.framework"
            "/Versions/Current/Resources/airport")


def _default_runner(argv: list[str]) -> str:
    completed = subprocess.run(argv, capture_output=True, text=True,
                               timeout=5)
    return completed.stdout or ""


def _clean(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip().strip('"')
    if not value or value.lower() in ("<redacted>", "off", "none"):
        return None
    return value


def _field(text: str, key: str) -> str | None:
    for line in text.splitlines():
        name, sep, value = line.partition(":")
        if sep and name.strip().lower() == key.lower():
            return _clean(value)
    return None


def _compose(ssid: str | None, bssid: str | None) -> str | None:
    if ssid and bssid:
        return f"{ssid} ({bssid.lower()})"
    return ssid


def _parse_airport(text: str) -> str | None:
    return _compose(_field(text, "SSID"), _field(text, "BSSID"))


def _parse_ipconfig(text: str) -> str | None:
    return _compose(_field(text, "SSID"), _field(text, "BSSID"))


def _parse_networksetup(text: str) -> str | None:
    for line in text.splitlines():
        if "Current Wi-Fi Network:" in line:
            return _clean(line.split(":", 1)[1])
    return None


def _parse_nmcli(text: str) -> str | None:
    for line in text.splitlines():
        parts = line.split(":")
        if len(parts) >= 2 and parts[0] == "yes":
            return _clean(parts[1])
    return None


def _parse_iwgetid(text: str) -> str | None:
    return _clean(text.splitlines()[0]) if text.splitlines() else None


def _parse_netsh(text: str) -> str | None:
    # netsh has both "SSID" and "BSSID" lines; _field takes the first
    # exact-key match, and the plain SSID line comes first.
    ssid = _field(text, "SSID")
    bssid = None
    for line in text.splitlines():
        name, sep, value = line.partition(":")
        if sep and name.strip().lower() == "bssid":
            bssid = _clean(value)
    return _compose(ssid, bssid)


def _attempts(platform: str):
    if platform == "darwin":
        return [
            ([_AIRPORT, "-I"], _parse_airport),
            (["ipconfig", "getsummary", "en0"], _parse_ipconfig),
            (["networksetup", "-getairportnetwork", "en0"],
             _parse_networksetup),
        ]
    if platform.startswith("linux"):
        return [
            (["nmcli", "-t", "-f", "active,ssid", "dev", "wifi"],
             _parse_nmcli),
            (["iwgetid", "-r"], _parse_iwgetid),
        ]
    if platform == "win32":
        return [(["netsh", "wlan", "show", "interfaces"], _parse_netsh)]
    return []


def current_place(runner: Runner = _default_runner,
                  platform: str | None = None) -> str | None:
    """The place this host is in, per its Wi-Fi association, or None."""
    for argv, parser in _attempts(platform or sys.platform):
        try:
            place = parser(runner(argv) or "")
        except Exception:
            continue  # tool missing/failed: fall through to the next
        if place:
            return place
    return None
