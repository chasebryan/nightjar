"""Level 9: drones — reading the digital licence plate.

Under the FAA's Remote ID rule (ASTM F3411 / Open Drone ID), nearly
every camera drone must broadcast a "digital licence plate" while it
flies — what it is, where it is, and where its operator is standing.
One of the mandated transports is a plain BLE advertisement, the exact
stream nightjar already listens to. The broadcasts are public by
design: any receiver is an intended audience, the drone equivalent of
ADS-B. Decoding them is receive-only, like everything else here.

A legacy advertisement carries a Service Data structure for UUID
0xFFFA whose value is:

    [0]      app code 0x0D (Open Drone ID)
    [1]      message counter (increments per message set)
    [2..26]  one 25-byte Open Drone ID message

Each advertisement carries one message; a drone cycles through its set
(Basic ID, Location, System, …) over seconds, so a session accumulates
the whole picture — nightjar's session model already fits.

The bit-level field packing follows the reference encoder/decoder,
opendroneid-core-c (Intel, Apache-2.0), verified against its header's
packed structs and its `test_inout.c` canonical values — not secondary
write-ups, whose nibble orders vary. No code is copied; this is a clean
reimplementation of the public format.
"""

from __future__ import annotations

from dataclasses import dataclass, field

REMOTE_ID_UUID_16 = 0xFFFA
REMOTE_ID_UUID = "0000fffa-0000-1000-8000-00805f9b34fb"
APP_CODE_ODID = 0x0D
ODID_MESSAGE_SIZE = 25
# System / Authentication timestamps are seconds since this instant.
EPOCH_2019 = 1_546_300_800  # 2019-01-01T00:00:00Z, Unix seconds

MSG_BASIC_ID = 0x0
MSG_LOCATION = 0x1
MSG_AUTH = 0x2
MSG_SELF_ID = 0x3
MSG_SYSTEM = 0x4
MSG_OPERATOR_ID = 0x5
MSG_PACK = 0xF

MESSAGE_TYPES = {
    MSG_BASIC_ID: "Basic ID",
    MSG_LOCATION: "Location",
    MSG_AUTH: "Authentication",
    MSG_SELF_ID: "Self ID",
    MSG_SYSTEM: "System",
    MSG_OPERATOR_ID: "Operator ID",
    MSG_PACK: "Message Pack",
}

ID_TYPES = {
    0: "none",
    1: "serial number",
    2: "CAA registration",
    3: "UTM UUID",
    4: "specific session ID",
}

UA_TYPES = {
    0: "none",
    1: "aeroplane",
    2: "helicopter/multirotor",
    3: "gyroplane",
    4: "hybrid lift (VTOL)",
    5: "ornithopter",
    6: "glider",
    7: "kite",
    8: "free balloon",
    9: "captive balloon",
    10: "airship",
    11: "free fall / parachute",
    12: "rocket",
    13: "tethered powered aircraft",
    14: "ground obstacle",
    15: "other",
}

OPERATIONAL_STATUS = {
    0: "undeclared",
    1: "ground",
    2: "airborne",
    3: "emergency",
    4: "RID system failure",
}

OPERATOR_LOCATION_TYPE = {
    0: "takeoff point",
    1: "live GPS",
    2: "fixed",
}

_COMPASS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")


def compass(bearing: float) -> str:
    """Nearest of 8 compass points for a bearing in degrees."""
    return _COMPASS[int((bearing % 360) / 45 + 0.5) % 8]


def _u16(data: bytes, off: int) -> int:
    return int.from_bytes(data[off:off + 2], "little")


def _i32(data: bytes, off: int) -> int:
    return int.from_bytes(data[off:off + 4], "little", signed=True)


def _u32(data: bytes, off: int) -> int:
    return int.from_bytes(data[off:off + 4], "little")


def _altitude(raw: int) -> float | None:
    """uint16 → metres = raw × 0.5 − 1000; raw 0 (== MIN_ALT/INV_ALT) invalid."""
    return None if raw == 0 else raw * 0.5 - 1000.0


def _latlon(raw: int) -> float | None:
    """int32 × 1e-7 degrees; 0 means no fix."""
    return None if raw == 0 else raw / 1e7


# --- decoded message payloads ------------------------------------------------

@dataclass
class BasicID:
    id_type: int
    ua_type: int
    uas_id: str

    @property
    def id_type_name(self) -> str:
        return ID_TYPES.get(self.id_type, f"type {self.id_type}")

    @property
    def ua_type_name(self) -> str:
        return UA_TYPES.get(self.ua_type, f"type {self.ua_type}")

    @property
    def is_serial(self) -> bool:
        # Serial number or CAA registration are stable, device-identifying.
        return self.id_type in (1, 2) and bool(self.uas_id)


@dataclass
class Location:
    status: int
    direction: float | None
    speed_h: float | None
    speed_v: float | None
    latitude: float | None
    longitude: float | None
    altitude_baro: float | None
    altitude_geo: float | None
    height: float | None
    height_type: int
    timestamp_tenths: int | None  # tenths of a second since the top of the hour

    @property
    def status_name(self) -> str:
        return OPERATIONAL_STATUS.get(self.status, f"status {self.status}")

    @property
    def airborne(self) -> bool:
        return self.status == 2

    @property
    def height_ref(self) -> str:
        return "AGL" if self.height_type == 1 else "above takeoff"


@dataclass
class System:
    operator_latitude: float | None
    operator_longitude: float | None
    operator_location_type: int
    area_count: int
    area_radius_m: int
    area_ceiling: float | None
    area_floor: float | None
    category: int
    ua_class: int
    operator_altitude: float | None
    timestamp_unix: int | None

    @property
    def operator_location_name(self) -> str:
        return OPERATOR_LOCATION_TYPE.get(self.operator_location_type,
                                          f"type {self.operator_location_type}")


@dataclass
class SelfID:
    description_type: int
    description: str


@dataclass
class OperatorID:
    operator_id_type: int
    operator_id: str


@dataclass
class RemoteIDMessage:
    type_id: int
    proto_version: int
    basic_id: BasicID | None = None
    location: Location | None = None
    system: System | None = None
    self_id: SelfID | None = None
    operator_id: OperatorID | None = None

    @property
    def type_name(self) -> str:
        return MESSAGE_TYPES.get(self.type_id, f"type 0x{self.type_id:X}")


def _ascii(raw: bytes) -> str:
    return raw.split(b"\x00", 1)[0].decode("ascii", "replace").strip()


def decode_message(msg: bytes) -> RemoteIDMessage | None:
    """Decode one 25-byte Open Drone ID message."""
    if len(msg) < ODID_MESSAGE_SIZE:
        return None
    type_id = msg[0] >> 4
    proto = msg[0] & 0x0F
    out = RemoteIDMessage(type_id=type_id, proto_version=proto)

    if type_id == MSG_BASIC_ID:
        out.basic_id = BasicID(
            id_type=msg[1] >> 4,
            ua_type=msg[1] & 0x0F,
            uas_id=_ascii(msg[2:22]),
        )
    elif type_id == MSG_LOCATION:
        flags = msg[1]
        ew = (flags >> 1) & 1
        direction_raw = msg[2]
        direction = direction_raw + 180.0 if ew else float(direction_raw)
        speed_mult = flags & 1
        speed_raw = msg[3]
        speed_h = (speed_raw * 0.25 if speed_mult == 0
                   else speed_raw * 0.75 + 63.75)
        v_raw = int.from_bytes(msg[4:5], "little", signed=True)
        ts_raw = _u16(msg, 21)
        out.location = Location(
            status=(flags >> 4) & 0x0F,
            direction=direction if direction_raw != 0xFF else None,
            speed_h=speed_h,
            speed_v=v_raw * 0.5,
            latitude=_latlon(_i32(msg, 5)),
            longitude=_latlon(_i32(msg, 9)),
            altitude_baro=_altitude(_u16(msg, 13)),
            altitude_geo=_altitude(_u16(msg, 15)),
            height=_altitude(_u16(msg, 17)),
            height_type=(flags >> 2) & 1,
            timestamp_tenths=None if ts_raw == 0xFFFF else ts_raw,
        )
    elif type_id == MSG_SYSTEM:
        flags = msg[1]
        ts_raw = _u32(msg, 20)
        out.system = System(
            operator_latitude=_latlon(_i32(msg, 2)),
            operator_longitude=_latlon(_i32(msg, 6)),
            operator_location_type=flags & 0x3,
            area_count=_u16(msg, 10),
            area_radius_m=msg[12] * 10,
            area_ceiling=_altitude(_u16(msg, 13)),
            area_floor=_altitude(_u16(msg, 15)),
            category=msg[17] >> 4,
            ua_class=msg[17] & 0x0F,
            operator_altitude=_altitude(_u16(msg, 18)),
            timestamp_unix=None if ts_raw == 0 else ts_raw + EPOCH_2019,
        )
    elif type_id == MSG_SELF_ID:
        out.self_id = SelfID(description_type=msg[1],
                             description=_ascii(msg[2:25]))
    elif type_id == MSG_OPERATOR_ID:
        out.operator_id = OperatorID(operator_id_type=msg[1],
                                     operator_id=_ascii(msg[2:22]))
    # Authentication (0x2) and anything else: recognized, not decoded.
    return out


def parse_service_data(value: bytes) -> list[RemoteIDMessage]:
    """Decode the 0xFFFA service-data value into its message(s).

    Legacy BLE carries one message per advertisement; a Message Pack
    (BLE 5 extended / Wi-Fi) carries several. Returns [] when the value
    is not an Open Drone ID payload.
    """
    if len(value) < 2 or value[0] != APP_CODE_ODID:
        return []
    body = value[2:]  # drop app code + counter
    if not body:
        return []
    if body[0] >> 4 == MSG_PACK:
        return _parse_pack(body)
    message = decode_message(body[:ODID_MESSAGE_SIZE])
    return [message] if message is not None else []


def _parse_pack(body: bytes) -> list[RemoteIDMessage]:
    if len(body) < 3:
        return []
    single = body[1] or ODID_MESSAGE_SIZE
    count = body[2]
    messages: list[RemoteIDMessage] = []
    for i in range(count):
        start = 3 + i * single
        chunk = body[start:start + single]
        if len(chunk) < ODID_MESSAGE_SIZE:
            break
        decoded = decode_message(chunk)
        if decoded is not None:
            messages.append(decoded)
    return messages


# --- a drone, assembled from its message set --------------------------------

@dataclass
class DroneReport:
    """Everything one advertisement (or an accumulated set) says."""

    serial: str | None = None
    ua_type: int | None = None
    id_type: int | None = None
    location: Location | None = None
    system: System | None = None
    self_id_text: str | None = None
    operator_id: str | None = None
    auth_pages: int = 0
    message_types: set[int] = field(default_factory=set)

    def ingest(self, message: RemoteIDMessage) -> None:
        self.message_types.add(message.type_id)
        if message.basic_id is not None:
            if message.basic_id.is_serial:
                self.serial = message.basic_id.uas_id
            self.ua_type = message.basic_id.ua_type
            self.id_type = message.basic_id.id_type
        if message.location is not None:
            self.location = message.location
        if message.system is not None:
            self.system = message.system
        if message.self_id is not None and message.self_id.description:
            self.self_id_text = message.self_id.description
        if message.operator_id is not None and message.operator_id.operator_id:
            self.operator_id = message.operator_id.operator_id
        if message.type_id == MSG_AUTH:
            self.auth_pages += 1

    @property
    def ua_type_name(self) -> str:
        return UA_TYPES.get(self.ua_type, "aircraft") if self.ua_type is not None else "aircraft"

    @property
    def airborne(self) -> bool:
        return self.location is not None and self.location.airborne


def report_from_service_data(value: bytes) -> DroneReport | None:
    """A DroneReport from one 0xFFFA value, or None if it isn't Remote ID."""
    messages = parse_service_data(value)
    if not messages:
        return None
    report = DroneReport()
    for message in messages:
        report.ingest(message)
    return report


def remoteid_value(sighting_service_data: dict) -> bytes | None:
    """Pull the 0xFFFA Open Drone ID value out of a sighting's service data."""
    for uuid, payload in sighting_service_data.items():
        text = str(uuid).lower()
        looks_like = text in (REMOTE_ID_UUID, "fffa") or text.startswith("0000fffa")
        if looks_like and len(payload) >= 2 and payload[0] == APP_CODE_ODID:
            return payload
    return None


def haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres."""
    import math
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def bearing(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Initial compass bearing from point 1 to point 2, degrees."""
    import math
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def describe(report: DroneReport, home: tuple[float, float] | None = None) -> str:
    """One-line human summary, as the registry and alerts show it.

    e.g. "Drone (Remote ID): serial 1581F…, multirotor, airborne, alt 62 m,
    8.4 m/s NE, height 41 m AGL, operator 210 m SE (live GPS)"
    """
    parts: list[str] = []
    if report.serial:
        parts.append(f"serial {report.serial}")
    if report.ua_type not in (None, 0):
        parts.append(report.ua_type_name)
    loc = report.location
    if loc is not None:
        parts.append(loc.status_name)
        if loc.altitude_geo is not None:
            parts.append(f"alt {loc.altitude_geo:.0f} m")
        elif loc.altitude_baro is not None:
            parts.append(f"baro alt {loc.altitude_baro:.0f} m")
        if loc.speed_h is not None and loc.direction is not None:
            parts.append(f"{loc.speed_h:.1f} m/s {compass(loc.direction)}")
        elif loc.speed_h is not None:
            parts.append(f"{loc.speed_h:.1f} m/s")
        if loc.height is not None:
            parts.append(f"height {loc.height:.0f} m {loc.height_ref}")
    sys = report.system
    if sys is not None and sys.operator_latitude is not None \
            and sys.operator_longitude is not None:
        if home is not None and loc is not None \
                and loc.latitude is not None:
            # Operator relative to the listener, not to the drone.
            dist = haversine(home[0], home[1], sys.operator_latitude,
                             sys.operator_longitude)
            brg = bearing(home[0], home[1], sys.operator_latitude,
                          sys.operator_longitude)
            parts.append(f"operator {dist:.0f} m {compass(brg)} "
                         f"({sys.operator_location_name})")
        else:
            parts.append(f"operator {sys.operator_latitude:.5f},"
                         f"{sys.operator_longitude:.5f} ({sys.operator_location_name})")
    if report.self_id_text:
        parts.append(f"“{report.self_id_text}”")
    return "Drone (Remote ID)" + (": " + ", ".join(parts) if parts else "")
