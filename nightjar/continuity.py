"""Level 3, first half: reading what an Apple broadcast *says*.

Apple devices pack their manufacturer payload (company 0x004C) as a
chain of small messages, each framed [type][length][value]. This is
the "Continuity" protocol, documented publicly by reverse engineers:
the furiousMAC/continuity dissector notes, the "Handoff All Your
Privacy" study (Martin et al., PETS 2019), the OpenPods project, and
the TU Darmstadt Secure Mobile Networking group's Find My work (the
AirGuard paper and "Who Can Find My Devices?", PETS 2021). Decoding
it turns an anonymous Apple sighting into "someone's AirPods Pro,
left bud at 90%, case open" — identification from pure broadcast
metadata, no connection involved.

Where a field's meaning rests on a single public source rather than
corroborated captures, the comments say so. Codes nightjar can't vouch
for are reported numerically rather than guessed at.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field

APPLE_COMPANY_ID = 0x004C

MESSAGE_TYPES = {
    0x02: "iBeacon",
    0x03: "AirPrint",
    0x05: "AirDrop",
    0x06: "HomeKit",
    0x07: "Proximity Pairing",
    0x08: "Hey Siri",
    0x09: "AirPlay Target",
    0x0A: "AirPlay Source",
    0x0B: "Magic Switch",
    0x0C: "Handoff",
    0x0D: "Tethering Target",
    0x0E: "Tethering Source",
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


# --- Proximity Pairing (AirPods, Beats) --------------------------------------

# Model codes, as they appear in bytes 1:3 of the Proximity Pairing
# value. Best-effort, compiled from public Continuity documentation
# and the OpenPods project's model table.
AIRPODS_MODELS = {
    "0220": "AirPods (1st gen)",
    "0f20": "AirPods (2nd gen)",
    "1320": "AirPods (3rd gen)",
    "1b20": "AirPods 4",
    "1920": "AirPods 4 (ANC)",
    "0e20": "AirPods Pro",
    "1420": "AirPods Pro (2nd gen)",
    "2420": "AirPods Pro (2nd gen, USB-C)",
    "0a20": "AirPods Max",
    "1f20": "AirPods Max (USB-C)",
    "0320": "Powerbeats3",
    "0b20": "Powerbeats Pro",
    "2b20": "Powerbeats Pro 2",
    "0c20": "Beats Solo Pro",
    "0520": "BeatsX",
    "0620": "Beats Solo3",
    "2720": "Beats Solo 4",
    "2520": "Beats Solo Buds",
    "0920": "Beats Studio3",
    "1020": "Beats Flex",
    "1120": "Beats Studio Buds",
    "1620": "Beats Studio Buds+",
    "1720": "Beats Studio Pro",
    "1220": "Beats Fit Pro",
}

# Colour byte, per the furiousMAC Proximity Pairing notes. Best-effort.
AIRPODS_COLOURS = {
    0x00: "white", 0x01: "black", 0x02: "red", 0x03: "blue", 0x04: "pink",
    0x05: "gray", 0x06: "silver", 0x07: "gold", 0x08: "rose gold",
    0x09: "space gray", 0x0A: "dark blue", 0x0B: "light blue", 0x0C: "yellow",
}


def _battery_level(nibble: int) -> int | None:
    """Battery nibbles run 0..10 (x10 %); 15 means unknown/absent."""
    return nibble * 10 if nibble <= 10 else None


@dataclass
class AirPodsState:
    model: str
    left_battery: int | None
    right_battery: int | None
    case_battery: int | None
    left_in_ear: bool
    right_in_ear: bool
    left_charging: bool = False
    right_charging: bool = False
    case_charging: bool = False
    lid_open: bool = False
    colour: str | None = None
    model_code: str = ""

    # Older names, kept so nothing that read "primary/secondary" breaks.
    @property
    def primary_battery(self) -> int | None:
        return self.right_battery

    @property
    def secondary_battery(self) -> int | None:
        return self.left_battery

    @property
    def primary_in_ear(self) -> bool:
        return self.right_in_ear

    @property
    def secondary_in_ear(self) -> bool:
        return self.left_in_ear

    def describe(self) -> str:
        def batt(v, charging):
            text = f"{v}%" if v is not None else "?"
            return text + (" charging" if charging else "")

        pods = [
            f"L {batt(self.left_battery, self.left_charging)}"
            f"{' (in ear)' if self.left_in_ear else ''}",
            f"R {batt(self.right_battery, self.right_charging)}"
            f"{' (in ear)' if self.right_in_ear else ''}",
        ]
        text = (f"{self.model}: {', '.join(pods)}, "
                f"case {batt(self.case_battery, self.case_charging)}, "
                f"lid {'open' if self.lid_open else 'closed'}")
        if self.colour:
            text += f", {self.colour}"
        return text


def decode_airpods(message: ContinuityMessage) -> AirPodsState | None:
    """Decode a Proximity Pairing message into an AirPods state.

    Value layout (public documentation): a prefix byte, the model
    code, a status byte, one byte packing both pods' battery nibbles,
    one byte packing charging flags and the case battery, a lid byte,
    and a colour byte, followed by an encrypted tail.

    Which nibble is which pod depends on a "flipped" bit in the status
    byte — the convention OpenPods established from captures: when the
    0x20 bit of the status byte is clear, left and right swap.
    """
    v = message.value
    if message.type_id != 0x07 or len(v) < 8:
        return None
    model_hex = v[1:3].hex()
    status = v[3]
    flipped = not (status & 0x20)
    high, low = (v[4] >> 4) & 0xF, v[4] & 0xF
    right_nibble, left_nibble = (low, high) if flipped else (high, low)
    charge = (v[5] >> 4) & 0xF
    left_bit, right_bit = (0x02, 0x01) if flipped else (0x01, 0x02)
    ear = status & 0x0F
    left_ear_bit, right_ear_bit = (0x08, 0x02) if flipped else (0x02, 0x08)
    colour = v[7] if len(v) > 7 else None
    return AirPodsState(
        model=AIRPODS_MODELS.get(model_hex, f"AirPods-class (model {model_hex})"),
        model_code=model_hex,
        left_battery=_battery_level(left_nibble),
        right_battery=_battery_level(right_nibble),
        case_battery=_battery_level(v[5] & 0xF),
        left_in_ear=bool(ear & left_ear_bit),
        right_in_ear=bool(ear & right_ear_bit),
        left_charging=bool(charge & left_bit),
        right_charging=bool(charge & right_bit),
        case_charging=bool(charge & 0x04),
        lid_open=bool(v[6] & 0x08),
        colour=AIRPODS_COLOURS.get(colour) if colour is not None else None,
    )


# --- iBeacon -----------------------------------------------------------------

@dataclass
class IBeaconState:
    proximity_uuid: str
    major: int
    minor: int
    measured_power: int | None = None  # calibrated RSSI at 1 m

    def describe(self) -> str:
        text = f"iBeacon {self.proximity_uuid} major {self.major} minor {self.minor}"
        if self.measured_power is not None:
            text += f", {self.measured_power} dBm @ 1 m"
        return text


def decode_ibeacon(message: ContinuityMessage) -> IBeaconState | None:
    v = message.value
    if message.type_id != 0x02 or len(v) < 20:
        return None
    power = None
    if len(v) >= 21:
        power = v[20] - 256 if v[20] > 127 else v[20]
    return IBeaconState(
        proximity_uuid=str(uuid.UUID(bytes=v[0:16])),
        major=int.from_bytes(v[16:18], "big"),
        minor=int.from_bytes(v[18:20], "big"),
        measured_power=power,
    )


# --- Find My network broadcasts ---------------------------------------------
#
# A Find My accessory (an AirTag, or a lost Apple device) does NOT use
# the TLV chain. Its manufacturer payload is one fixed-format record,
# documented byte-for-byte in the AirGuard paper (Heinrich et al.,
# TU Darmstadt) and the PETS AirTag safety analysis:
#
#   byte 0      0x12  Find My network type
#   byte 1      0x19  data length (25): the *separated* format
#   byte 2      status (battery in the top two bits)
#   bytes 3-24  public key bytes (the key rotates; so does the address)
#   byte 25     public key bits
#   byte 26     hint (0x00)
#
# An accessory that is still near its owner broadcasts a short form
# instead — length 0x02, status plus one byte — which AirGuard treats
# as "nearby its owner". Only the separated form is the shape of an
# unwanted tracker; a tag riding with its own keys is not following
# anyone.

FINDMY_BATTERY = ("full", "medium", "low", "very low")


@dataclass
class FindMyState:
    status: int
    separated: bool  # the 0x19 "offline finding" format

    @property
    def battery(self) -> str:
        return FINDMY_BATTERY[(self.status >> 6) & 0x3]

    def describe(self) -> str:
        if self.separated:
            return f"Find My network broadcast (separated from owner), battery {self.battery}"
        return "Find My network broadcast (nearby its owner)"


def parse_findmy(payload: bytes) -> FindMyState | None:
    """Recognize a Find My accessory broadcast (not a TLV message)."""
    if len(payload) >= 27 and payload[0] == 0x12 and payload[1] == 0x19:
        return FindMyState(status=payload[2], separated=True)
    if len(payload) == 4 and payload[0] == 0x12 and payload[1] == 0x02:
        return FindMyState(status=payload[2], separated=False)
    return None


# --- Nearby Info -------------------------------------------------------------

# The first value byte packs status flags in its high nibble and an
# "action code" — what the device is doing right now — in its low
# nibble. Most codes are documented only partially in public
# dissectors (furiousMAC/continuity, seemoo-lab); 0x0A is the verified
# "watch worn & unlocked" code and the only one nightjar labels. The
# others are reported numerically rather than guessed at.
NEARBY_ACTION_LABELS = {
    0x0A: "watch worn & unlocked",
}

# What public dissectors say the other codes mean. Kept here for the
# day a capture confirms one — not applied to output until then.
NEARBY_ACTION_CANDIDATES = {
    0x00: "activity level not known",
    0x01: "activity reporting disabled",
    0x03: "idle (screen off)",
    0x05: "audio playing, screen locked",
    0x07: "active (screen on)",
    0x09: "screen on, video playing",
    0x0B: "recent user interaction",
    0x0D: "driving",
    0x0E: "phone call or FaceTime",
}


@dataclass
class NearbyInfoState:
    action_code: int
    status_flags: int = 0
    data_flags: int | None = None

    @property
    def action_label(self) -> str | None:
        return NEARBY_ACTION_LABELS.get(self.action_code)

    @property
    def is_watch(self) -> bool:
        return self.action_code == 0x0A

    def describe(self) -> str:
        if self.action_label:
            return f"nearby state 0x{self.action_code:02X} ({self.action_label})"
        return f"nearby state 0x{self.action_code:02X}"


def decode_nearby_info(message: ContinuityMessage) -> NearbyInfoState | None:
    if message.type_id != 0x10 or not message.value:
        return None
    first = message.value[0]
    return NearbyInfoState(
        action_code=first & 0x0F,
        status_flags=(first >> 4) & 0x0F,
        data_flags=message.value[1] if len(message.value) > 1 else None,
    )


# --- Nearby Action -----------------------------------------------------------

# Action types in the second value byte of a Nearby Action message:
# a device inviting something to happen (setup, Wi-Fi password share,
# Apple Pay, ...). From the table in "Handoff All Your Privacy"
# (Martin et al., PETS 2019) and the furiousMAC notes; best-effort.
NEARBY_ACTION_TYPES = {
    0x01: "Apple TV setup",
    0x04: "mobile backup",
    0x05: "watch setup",
    0x06: "Apple TV pair",
    0x07: "internet relay",
    0x08: "Wi-Fi password share",
    0x09: "iOS setup",
    0x0A: "repair",
    0x0B: "speaker setup",
    0x0C: "Apple Pay",
    0x0D: "whole-home audio setup",
    0x0E: "developer tools pairing",
    0x0F: "answered call",
    0x10: "ended call",
    0x11: "DD ping",
    0x12: "DD pong",
    0x13: "remote AutoFill",
    0x14: "companion link proximity",
    0x15: "remote management",
    0x16: "remote AutoFill pong",
    0x17: "remote display",
}


@dataclass
class NearbyActionState:
    flags: int
    action_type: int

    @property
    def action_label(self) -> str | None:
        return NEARBY_ACTION_TYPES.get(self.action_type)

    def describe(self) -> str:
        label = self.action_label or f"type 0x{self.action_type:02X}"
        return f"nearby action: {label}"


def decode_nearby_action(message: ContinuityMessage) -> NearbyActionState | None:
    if message.type_id != 0x0F or len(message.value) < 2:
        return None
    return NearbyActionState(flags=message.value[0],
                             action_type=message.value[1])


# --- Tethering Source (Instant Hotspot) --------------------------------------

@dataclass
class TetheringSourceState:
    battery: int | None  # percent
    cell_bars: int | None

    def describe(self) -> str:
        parts = ["hotspot-capable"]
        if self.battery is not None:
            parts.append(f"battery {self.battery}%")
        if self.cell_bars is not None:
            parts.append(f"cell {self.cell_bars} bars")
        return ", ".join(parts)


def decode_tethering_source(message: ContinuityMessage) -> TetheringSourceState | None:
    """Value: version, flags, battery %, cell service type, cell bars.

    Per the furiousMAC Tethering Source notes; battery and bars are the
    fields captures agree on.
    """
    v = message.value
    if message.type_id != 0x0E or len(v) < 3:
        return None
    battery = v[2] if v[2] <= 100 else None
    bars = v[4] if len(v) > 4 and v[4] <= 5 else None
    return TetheringSourceState(battery=battery, cell_bars=bars)


# --- Putting it together ----------------------------------------------------

@dataclass
class Identification:
    """What one sighting's payloads say about the device behind it."""

    kind: str                       # e.g. "AirPods Pro", "Apple device"
    details: list[str] = field(default_factory=list)
    messages: list[str] = field(default_factory=list)  # continuity type names
    findmy: FindMyState | None = None
    specificity: int = 1  # how far the kind narrows things (1 family, 3 product)

    def describe(self) -> str:
        text = self.kind
        if self.details:
            text += " — " + "; ".join(self.details)
        return text


def identify_apple(payload: bytes) -> Identification:
    """Identify an Apple device from its Continuity payload."""
    findmy = parse_findmy(payload)
    if findmy is not None:
        if findmy.separated:
            kind = "Find My device (AirTag-class)"
        else:
            kind = "Find My accessory (with owner)"
        return Identification(kind=kind, details=[findmy.describe()],
                              messages=["Find My"], findmy=findmy,
                              specificity=3)
    messages = parse_continuity(payload)
    names = [m.type_name for m in messages]
    details: list[str] = []
    kind = "Apple device"
    specificity = 1
    for message in messages:
        if message.type_id == 0x07:
            state = decode_airpods(message)
            if state is not None:
                kind, specificity = state.model, 3
                details.append(state.describe())
        elif message.type_id == 0x02:
            beacon = decode_ibeacon(message)
            if beacon is not None:
                kind, specificity = "iBeacon", 3
                details.append(beacon.describe())
        elif message.type_id == 0x10:
            nearby = decode_nearby_info(message)
            if nearby is not None:
                details.append(nearby.describe())
                if nearby.is_watch and specificity < 3:
                    kind, specificity = "Apple Watch", 2
        elif message.type_id == 0x0F:
            action = decode_nearby_action(message)
            if action is not None:
                details.append(action.describe())
        elif message.type_id == 0x0E:
            source = decode_tethering_source(message)
            if source is not None:
                details.append(source.describe())
                if specificity < 2:
                    kind, specificity = "iPhone (Instant Hotspot source)", 2
    if kind == "Apple device" and "Nearby Info" in names:
        kind = "Apple device (Nearby Info)"
    return Identification(kind=kind, details=details, messages=names,
                          specificity=specificity)
