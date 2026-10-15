"""Service UUIDs and service data: the other half of what a broadcast says.

Manufacturer data is one channel; the 16-bit service UUIDs a device
lists, and the *service data* it attaches to them, are the other. Many
of the devices nightjar most wants to recognize speak only here:

  * Google Fast Pair earbuds (0xFE2C) carry a model id
  * Eddystone beacons (0xFEAA) carry UID / URL / telemetry frames —
    and the Find My Device network's tracker beacons reuse the same
    UUID with their own frame types
  * Tile (0xFEED) and Samsung SmartThings Find (0xFD5A) tags announce
    themselves by UUID alone
  * Exposure Notification (0xFD6F) is a phone, rotating on purpose

Everything here is receive-side parsing of public formats. Sources:
Bluetooth SIG Assigned Numbers ("16-bit UUIDs"), the Google Eddystone
protocol specification, the Google Fast Pair specification, and the
Apple/Google Exposure Notification Bluetooth specification.
"""

from __future__ import annotations

from dataclasses import dataclass, field

SIG_BASE_SUFFIX = "-0000-1000-8000-00805f9b34fb"

# Bluetooth SIG assigned 16-bit service UUIDs (GATT services) and the
# member-company UUIDs that matter for identification. Partial, like
# the company table: the ones that mean something in a summary.
SERVICE_NAMES: dict[int, str] = {
    0x1800: "Generic Access",
    0x1801: "Generic Attribute",
    0x1802: "Immediate Alert",
    0x1803: "Link Loss",
    0x1804: "Tx Power",
    0x1805: "Current Time",
    0x1808: "Glucose",
    0x1809: "Health Thermometer",
    0x180A: "Device Information",
    0x180D: "Heart Rate",
    0x180F: "Battery",
    0x1810: "Blood Pressure",
    0x1811: "Alert Notification",
    0x1812: "Human Interface Device",
    0x1814: "Running Speed and Cadence",
    0x1816: "Cycling Speed and Cadence",
    0x1818: "Cycling Power",
    0x1819: "Location and Navigation",
    0x181A: "Environmental Sensing",
    0x181B: "Body Composition",
    0x181C: "User Data",
    0x181D: "Weight Scale",
    0x181F: "Continuous Glucose Monitoring",
    0x1822: "Pulse Oximeter",
    0x1826: "Fitness Machine",
    0x1827: "Mesh Provisioning",
    0x1828: "Mesh Proxy",
    0x184E: "Audio Stream Control (LE Audio)",
    0x1850: "Published Audio Capabilities (LE Audio)",
    0x1852: "Broadcast Audio Announcement (LE Audio)",
    0x1853: "Common Audio (LE Audio)",
    0x1854: "Hearing Access (LE Audio)",
    0xFD3D: "SwitchBot",
    0xFD43: "Apple",
    0xFD44: "Apple (Find My accessory)",
    0xFD5A: "Samsung SmartThings Find",
    0xFD6F: "Exposure Notification",
    0xFE03: "Amazon",
    0xFE07: "Sonos",
    0xFE0F: "Signify (Philips Hue)",
    0xFE2C: "Google Fast Pair",
    0xFE59: "Nordic DFU",
    0xFE61: "Logitech",
    0xFE95: "Xiaomi",
    0xFE9F: "Google",
    0xFEAA: "Eddystone",
    0xFEBE: "Bose",
    0xFEE0: "Huami",
    0xFEE7: "Tencent (WeChat)",
    0xFEEC: "Tile",
    0xFEED: "Tile",
    0xFEF3: "Google",
    0xFEF4: "Google",
}

# Apple reserves a run of member UUIDs; they turn up on Macs and iPhones.
for _apple_uuid in range(0xFECA, 0xFED5):
    SERVICE_NAMES.setdefault(_apple_uuid, "Apple")

FAST_PAIR_UUID = 0xFE2C
EDDYSTONE_UUID = 0xFEAA
EXPOSURE_NOTIFICATION_UUID = 0xFD6F
SMARTTHINGS_FIND_UUID = 0xFD5A
TILE_UUIDS = (0xFEED, 0xFEEC)


def normalize_uuid(uuid: str) -> str:
    """Lower-case 128-bit form of a UUID given short or long."""
    text = uuid.strip().lower()
    if text.startswith("0x"):
        text = text[2:]
    if len(text) in (4, 8) and all(c in "0123456789abcdef" for c in text):
        return f"{int(text, 16):08x}{SIG_BASE_SUFFIX}"
    return text


def short_uuid(uuid: str) -> int | None:
    """The 16-bit value of a SIG-base UUID, or None for a custom UUID."""
    text = normalize_uuid(uuid)
    if len(text) == 36 and text.endswith(SIG_BASE_SUFFIX) \
            and text.startswith("0000"):
        try:
            return int(text[4:8], 16)
        except ValueError:
            return None
    return None


def service_name(uuid: str) -> str | None:
    """Readable name for a well-known service UUID, else None."""
    short = short_uuid(uuid)
    if short is None:
        return None
    return SERVICE_NAMES.get(short)


def describe_uuid(uuid: str) -> str:
    """'Heart Rate (0x180d)', '0xfeaa', or the custom UUID itself."""
    short = short_uuid(uuid)
    if short is None:
        return normalize_uuid(uuid)
    name = SERVICE_NAMES.get(short)
    return f"{name} (0x{short:04x})" if name else f"0x{short:04x}"


def _full(short: int) -> str:
    return f"{short:08x}{SIG_BASE_SUFFIX}"


# Service UUIDs advertised by standalone tracker tags (full form).
TRACKER_SERVICE_UUIDS: frozenset[str] = frozenset(
    _full(u) for u in (*TILE_UUIDS, SMARTTHINGS_FIND_UUID)
)


# --- Eddystone (and the Find My Device network that borrows its UUID) ------

EDDYSTONE_URL_SCHEMES = {
    0x00: "http://www.",
    0x01: "https://www.",
    0x02: "http://",
    0x03: "https://",
}
EDDYSTONE_URL_EXPANSIONS = {
    0x00: ".com/", 0x01: ".org/", 0x02: ".edu/", 0x03: ".net/",
    0x04: ".info/", 0x05: ".biz/", 0x06: ".gov/",
    0x07: ".com", 0x08: ".org", 0x09: ".edu", 0x0A: ".net",
    0x0B: ".info", 0x0C: ".biz", 0x0D: ".gov",
}

EDDYSTONE_FRAME_NAMES = {
    0x00: "UID",
    0x10: "URL",
    0x20: "TLM",
    0x30: "EID",
    0x40: "Find My Device network (20-byte EID)",
    0x41: "Find My Device network (32-byte EID)",
}


def _int8(value: int) -> int:
    return value - 256 if value > 127 else value


@dataclass
class EddystoneFrame:
    frame_type: int
    tx_power: int | None = None
    namespace: str | None = None
    instance: str | None = None
    url: str | None = None
    battery_mv: int | None = None
    temperature_c: float | None = None
    adv_count: int | None = None
    uptime_s: float | None = None
    eid: str | None = None

    @property
    def frame_name(self) -> str:
        return EDDYSTONE_FRAME_NAMES.get(self.frame_type,
                                         f"frame 0x{self.frame_type:02X}")

    @property
    def is_fmdn(self) -> bool:
        """A Google Find My Device network tracker beacon."""
        return self.frame_type in (0x40, 0x41)

    def describe(self) -> str:
        if self.is_fmdn:
            return "Find My Device network beacon (Google)"
        if self.frame_type == 0x00:
            return f"Eddystone-UID {self.namespace}/{self.instance}"
        if self.frame_type == 0x10:
            return f"Eddystone-URL {self.url}"
        if self.frame_type == 0x20:
            parts = []
            if self.battery_mv:
                parts.append(f"battery {self.battery_mv} mV")
            if self.temperature_c is not None:
                parts.append(f"{self.temperature_c:.1f} °C")
            if self.uptime_s is not None:
                parts.append(f"up {self.uptime_s / 3600:.1f} h")
            return "Eddystone-TLM" + (": " + ", ".join(parts) if parts else "")
        if self.frame_type == 0x30:
            return f"Eddystone-EID {self.eid}"
        return f"Eddystone {self.frame_name}"


def decode_eddystone(payload: bytes) -> EddystoneFrame | None:
    """Decode the service data attached to UUID 0xFEAA."""
    if not payload:
        return None
    frame_type = payload[0]
    if frame_type == 0x00 and len(payload) >= 18:
        return EddystoneFrame(
            frame_type, tx_power=_int8(payload[1]),
            namespace=payload[2:12].hex(), instance=payload[12:18].hex())
    if frame_type == 0x10 and len(payload) >= 3:
        url = EDDYSTONE_URL_SCHEMES.get(payload[2], "")
        for byte in payload[3:]:
            if byte in EDDYSTONE_URL_EXPANSIONS:
                url += EDDYSTONE_URL_EXPANSIONS[byte]
            elif 0x20 < byte < 0x7F:
                url += chr(byte)
        return EddystoneFrame(frame_type, tx_power=_int8(payload[1]), url=url)
    if frame_type == 0x20 and len(payload) >= 14 and payload[1] == 0x00:
        temp_raw = int.from_bytes(payload[4:6], "big", signed=True)
        return EddystoneFrame(
            frame_type,
            battery_mv=int.from_bytes(payload[2:4], "big") or None,
            temperature_c=(temp_raw / 256.0
                           if payload[4:6] != b"\x80\x00" else None),
            adv_count=int.from_bytes(payload[6:10], "big"),
            uptime_s=int.from_bytes(payload[10:14], "big") / 10.0,
        )
    if frame_type == 0x20:
        return EddystoneFrame(frame_type)  # encrypted TLM: presence only
    if frame_type == 0x30 and len(payload) >= 10:
        return EddystoneFrame(frame_type, tx_power=_int8(payload[1]),
                              eid=payload[2:10].hex())
    if frame_type in (0x40, 0x41):
        return EddystoneFrame(frame_type, eid=payload[1:].hex())
    return EddystoneFrame(frame_type)


# --- Google Fast Pair -------------------------------------------------------

@dataclass
class FastPairState:
    model_id: int | None  # 24-bit, only broadcast while discoverable
    discoverable: bool

    def describe(self) -> str:
        if self.discoverable and self.model_id is not None:
            return f"Fast Pair, discoverable (model 0x{self.model_id:06X})"
        return "Fast Pair device (paired, not discoverable)"


def decode_fast_pair(payload: bytes) -> FastPairState | None:
    """Decode the service data attached to UUID 0xFE2C.

    While discoverable a Fast Pair device broadcasts its 3-byte model
    id in the clear; afterwards it broadcasts an account-key filter
    that identifies only its owner's accounts, and only to them.
    """
    if not payload:
        return None
    if len(payload) == 3:
        return FastPairState(model_id=int.from_bytes(payload, "big"),
                             discoverable=True)
    return FastPairState(model_id=None, discoverable=False)


# --- Putting it together ----------------------------------------------------

@dataclass
class ServiceIdentification:
    """What a sighting's service UUIDs and service data say."""

    kind: str
    details: list[str] = field(default_factory=list)
    tracker_shaped: bool = False   # shaped like a standalone tag
    rotating_phone: bool = False   # a phone/wearable rotating by design
    specificity: int = 1           # how much the kind narrows things

    def describe(self) -> str:
        text = self.kind
        if self.details:
            text += " — " + "; ".join(self.details)
        return text


def identify_services(service_uuids: list[str],
                      service_data: dict[str, bytes]) -> ServiceIdentification | None:
    """Identify a device from its service UUIDs and service data."""
    shorts: dict[int, str] = {}
    for uuid in list(service_uuids) + list(service_data):
        short = short_uuid(uuid)
        if short is not None:
            shorts[short] = normalize_uuid(uuid)
    data = {short_uuid(u): payload for u, payload in service_data.items()}

    if EDDYSTONE_UUID in shorts:
        frame = decode_eddystone(data.get(EDDYSTONE_UUID) or b"")
        if frame is not None and frame.is_fmdn:
            return ServiceIdentification(
                kind="Find My Device network tag (Google)",
                details=[frame.describe()], tracker_shaped=True,
                specificity=3)
        if frame is not None:
            return ServiceIdentification(
                kind=f"Eddystone beacon ({frame.frame_name})",
                details=[frame.describe()], specificity=3)
        return ServiceIdentification(kind="Eddystone beacon", specificity=2)

    if FAST_PAIR_UUID in shorts:
        state = decode_fast_pair(data.get(FAST_PAIR_UUID) or b"")
        details = [state.describe()] if state else []
        return ServiceIdentification(kind="Fast Pair device (Google)",
                                     details=details, specificity=2)

    if EXPOSURE_NOTIFICATION_UUID in shorts:
        return ServiceIdentification(
            kind="Phone (Exposure Notification)",
            details=["contact-tracing beacon; rotates every ~15 min"],
            rotating_phone=True, specificity=2)

    if any(u in shorts for u in TILE_UUIDS):
        return ServiceIdentification(kind="Tile tracker", tracker_shaped=True,
                                     specificity=3)

    if SMARTTHINGS_FIND_UUID in shorts:
        return ServiceIdentification(
            kind="SmartThings Find device (Samsung tag or Galaxy)",
            tracker_shaped=True, specificity=2)

    named = [SERVICE_NAMES[s] for s in shorts if s in SERVICE_NAMES]
    if named:
        return ServiceIdentification(
            kind="Device advertising " + ", ".join(sorted(set(named))),
            specificity=1)
    return None
