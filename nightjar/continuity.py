"""Level 3, first half: reading what a broadcast *says*.

Apple devices pack their manufacturer payload (company 0x004C) as a
chain of small messages, each framed [type][length][value]. This is
the "Continuity" protocol, documented publicly by reverse engineers
(the OpenPods project and the TU Darmstadt Secure Mobile Networking
group, among others). Decoding it turns an anonymous Apple sighting
into "someone's AirPods, left bud at 90%, case open" — identification
from pure broadcast metadata, no connection involved.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field

APPLE_COMPANY_ID = 0x004C

MESSAGE_TYPES = {
    0x02: "iBeacon",
    0x05: "AirDrop",
    0x07: "Proximity Pairing",
    0x08: "Hey Siri",
    0x09: "AirPlay Target",
    0x0C: "Handoff",
    0x0D: "Tethering",
    0x0F: "Nearby Action",
    0x10: "Nearby Info",
    0x12: "Find My",
}


@dataclass
class ContinuityMessage:
    type_id: int
    value: bytes

    @property
    def type_name(self) -> str:
        return MESSAGE_TYPES.get(self.type_id, f"Unknown 0x{self.type_id:02X}")


def parse_continuity(payload: bytes) -> list[ContinuityMessage]:
    """Split an Apple manufacturer payload into its TLV messages."""
    messages = []
    i = 0
    while i + 2 <= len(payload):
        type_id, length = payload[i], payload[i + 1]
        value = payload[i + 2: i + 2 + length]
        if len(value) < length:
            break  # truncated tail; keep what parsed cleanly
        messages.append(ContinuityMessage(type_id, value))
        i += 2 + length
    return messages


# --- Specific message decoders -------------------------------------------

# AirPods model codes, as they appear in bytes 1:3 of the Proximity
# Pairing value. Best-effort, from public Continuity documentation.
AIRPODS_MODELS = {
    "0220": "AirPods (1st gen)",
    "0f20": "AirPods (2nd gen)",
    "1320": "AirPods (3rd gen)",
    "0e20": "AirPods Pro",
    "1420": "AirPods Pro (2nd gen)",
    "0a20": "AirPods Max",
}


def _battery_level(nibble: int) -> int | None:
    """Battery nibbles run 0..10 (x10 %); 15 means unknown/absent."""
    return nibble * 10 if nibble <= 10 else None


@dataclass
class AirPodsState:
    model: str
    primary_in_ear: bool
    secondary_in_ear: bool
    primary_battery: int | None
    secondary_battery: int | None
    case_battery: int | None
    lid_open: bool

    def describe(self) -> str:
        def batt(v):
            return f"{v}%" if v is not None else "?"
        pods = []
        pods.append(f"primary {batt(self.primary_battery)}"
                    f"{' (in ear)' if self.primary_in_ear else ''}")
        pods.append(f"secondary {batt(self.secondary_battery)}"
                    f"{' (in ear)' if self.secondary_in_ear else ''}")
        return (f"{self.model}: {', '.join(pods)}, "
                f"case {batt(self.case_battery)}, "
                f"lid {'open' if self.lid_open else 'closed'}")


def decode_airpods(message: ContinuityMessage) -> AirPodsState | None:
    """Decode a Proximity Pairing message into an AirPods state.

    Value layout (public documentation): a constant byte, the model
    code, a status byte (pod-in-ear bits), one byte packing both pods'
    battery nibbles, one byte packing the case battery, and a lid
    counter whose parity tracks the lid.
    """
    v = message.value
    if message.type_id != 0x07 or len(v) < 8:
        return None
    model_hex = v[1:3].hex()
    status = v[3]
    return AirPodsState(
        model=AIRPODS_MODELS.get(model_hex, f"AirPods (model {model_hex})"),
        primary_in_ear=bool(status & 0x02),
        secondary_in_ear=bool(status & 0x01),
        primary_battery=_battery_level((v[4] >> 4) & 0xF),
        secondary_battery=_battery_level(v[4] & 0xF),
        case_battery=_battery_level((v[5] >> 4) & 0xF),
        lid_open=bool(v[6] & 0x08),
    )


@dataclass
class IBeaconState:
    proximity_uuid: str
    major: int
    minor: int

    def describe(self) -> str:
        return f"iBeacon {self.proximity_uuid} major {self.major} minor {self.minor}"


def decode_ibeacon(message: ContinuityMessage) -> IBeaconState | None:
    v = message.value
    if message.type_id != 0x02 or len(v) < 20:
        return None
    return IBeaconState(
        proximity_uuid=str(uuid.UUID(bytes=v[0:16])),
        major=int.from_bytes(v[16:18], "big"),
        minor=int.from_bytes(v[18:20], "big"),
    )


# --- Find My network broadcasts -------------------------------------------
#
# A Find My accessory (an AirTag, or a lost Apple device) does NOT use
# the TLV chain. Its manufacturer payload is one fixed-format record,
# documented byte-for-byte in the AirGuard paper (Heinrich et al.,
# TU Darmstadt) and the PETS AirTag safety analysis:
#
#   byte 0      0x12  Find My network type
#   byte 1      0x19  data length (25)
#   byte 2      status (device class + battery)
#   bytes 3-24  public key bytes (the key rotates; so does the address)
#   byte 25     public key bits
#   byte 26     hint (0x00)
#
# The status byte's documented AirTag values encode battery:
FINDMY_STATUS_BATTERY = {
    0x10: "full",
    0x50: "medium",
    0x90: "low",
    0xD0: "very low",
}


@dataclass
class FindMyState:
    status: int
    battery: str | None  # decoded for the documented AirTag values

    def describe(self) -> str:
        text = "Find My network broadcast"
        if self.battery:
            text += f", battery {self.battery}"
        return text


def parse_findmy(payload: bytes) -> FindMyState | None:
    """Recognize a Find My accessory broadcast (not a TLV message)."""
    if len(payload) < 27 or payload[0] != 0x12 or payload[1] != 0x19:
        return None
    status = payload[2]
    return FindMyState(status=status,
                       battery=FINDMY_STATUS_BATTERY.get(status))


# --- Nearby Info ------------------------------------------------------------

# The first byte of a Nearby Info value is a state/action code: what
# the device is doing right now. Most codes are documented only
# partially in public dissectors (furiousMAC/continuity, seemoo-lab);
# 0x0A is the verified "watch worn & unlocked" code. Other codes are
# reported numerically rather than guessed at.
NEARBY_ACTION_LABELS = {
    0x0A: "watch worn & unlocked",
}


@dataclass
class NearbyInfoState:
    action_code: int

    @property
    def action_label(self) -> str | None:
        return NEARBY_ACTION_LABELS.get(self.action_code)

    def describe(self) -> str:
        if self.action_label:
            return f"nearby state 0x{self.action_code:02X} ({self.action_label})"
        return f"nearby state 0x{self.action_code:02X}"


def decode_nearby_info(message: ContinuityMessage) -> NearbyInfoState | None:
    if message.type_id != 0x10 or not message.value:
        return None
    return NearbyInfoState(action_code=message.value[0])


@dataclass
class Identification:
    """What one sighting's payloads say about the device behind it."""

    kind: str                       # e.g. "AirPods Pro", "Apple device"
    details: list[str] = field(default_factory=list)
    messages: list[str] = field(default_factory=list)  # continuity type names

    def describe(self) -> str:
        text = self.kind
        if self.details:
            text += " — " + "; ".join(self.details)
        return text


def identify_apple(payload: bytes) -> Identification:
    """Identify an Apple device from its Continuity payload."""
    findmy = parse_findmy(payload)
    if findmy is not None:
        return Identification(
            kind="Find My device (AirTag-class)",
            details=[findmy.describe()],
            messages=["Find My"],
        )
    messages = parse_continuity(payload)
    names = [m.type_name for m in messages]
    details: list[str] = []
    kind = "Apple device"
    for message in messages:
        if message.type_id == 0x07:
            state = decode_airpods(message)
            if state is not None:
                kind = state.model
                details.append(state.describe())
        elif message.type_id == 0x02:
            beacon = decode_ibeacon(message)
            if beacon is not None:
                kind = "iBeacon"
                details.append(beacon.describe())
        elif message.type_id == 0x10:
            nearby = decode_nearby_info(message)
            if nearby is not None:
                details.append(nearby.describe())
    if kind == "Apple device" and "Nearby Info" in names:
        kind = "Apple device (Nearby Info)"
    return Identification(kind=kind, details=details, messages=names)
