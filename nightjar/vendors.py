"""Level 3, other makers: what non-Apple manufacturer data says.

Apple's Continuity chain gets its own module. This one covers the
other manufacturer payloads worth reading on sight:

  * Microsoft's Connected Devices Platform beacon (every Windows
    machine, Xbox and Surface broadcasts one) names its device class
    outright — documented in Microsoft's open MS-CDP specification.
  * Microsoft Swift Pair announces a device in pairing mode, usually
    with its display name in the clear.
  * Ruuvi environmental tags broadcast temperature, humidity and
    pressure in their public RAWv2 format.
  * A handful of makers are identified by company id alone, which is
    still worth saying: "Garmin device" beats "0x0087".
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .companies import company_name

MICROSOFT_COMPANY_ID = 0x0006
SAMSUNG_COMPANY_ID = 0x0075
GOOGLE_COMPANY_ID = 0x00E0
RUUVI_COMPANY_ID = 0x0499

# MS-CDP beacon "device type" values (section 2.2.3.1 of the spec).
CDP_DEVICE_TYPES = {
    1: "Xbox One",
    6: "iPhone (CDP)",
    7: "iPad (CDP)",
    8: "Android device (CDP)",
    9: "Windows desktop",
    11: "Windows phone",
    12: "Linux device (CDP)",
    13: "Windows IoT device",
    14: "Surface Hub",
    15: "Windows laptop",
    16: "Windows tablet",
}

# Makers whose company id alone says what family a thing belongs to.
FAMILY_BY_COMPANY = {
    0x0059: "Nordic-chip device",
    0x0075: "Samsung device",
    0x0087: "Garmin device",
    0x009E: "Bose device",
    0x00E0: "Google device",
    0x012D: "Sony device",
    0x0157: "Huami wearable (Mi Band / Amazfit)",
    0x0171: "Amazon device",
    0x01DA: "Logitech device",
    0x027D: "Huawei device",
    0x02E5: "ESP32 device",
    0x038F: "Xiaomi device",
    0x0553: "Nintendo controller",
    0x05A7: "Sonos speaker",
    0x0969: "SwitchBot device",
}


@dataclass
class VendorIdentification:
    kind: str
    details: list[str] = field(default_factory=list)
    specificity: int = 1
    windows_pc: bool = False

    def describe(self) -> str:
        text = self.kind
        if self.details:
            text += " — " + "; ".join(self.details)
        return text


# --- Microsoft -------------------------------------------------------------

def decode_microsoft(payload: bytes) -> VendorIdentification | None:
    """CDP beacon (0x01 ...) or Swift Pair (0x03 0x00 ...)."""
    if not payload:
        return None
    if payload[0] == 0x03 and len(payload) >= 3:
        name = payload[3:].decode("utf-8", "replace").strip("\x00").strip()
        details = ["in pairing mode (Swift Pair)"]
        if name:
            details.append(f"announces itself as {name!r}")
        return VendorIdentification(kind="Windows device (Swift Pair)",
                                    details=details, specificity=2,
                                    windows_pc=True)
    if payload[0] == 0x01 and len(payload) >= 2:
        device_type = payload[1] & 0x1F
        kind = CDP_DEVICE_TYPES.get(device_type,
                                    f"CDP device type {device_type}")
        return VendorIdentification(
            kind=kind, details=["Microsoft CDP beacon"], specificity=2,
            windows_pc=device_type in (9, 11, 13, 14, 15, 16))
    return VendorIdentification(kind="Microsoft device", specificity=1)


# --- Ruuvi -------------------------------------------------------------------

@dataclass
class RuuviReading:
    temperature_c: float | None
    humidity_pct: float | None
    pressure_hpa: float | None
    battery_mv: int | None
    movement_count: int | None

    def describe(self) -> str:
        parts = []
        if self.temperature_c is not None:
            parts.append(f"{self.temperature_c:.2f} °C")
        if self.humidity_pct is not None:
            parts.append(f"{self.humidity_pct:.1f}% RH")
        if self.pressure_hpa is not None:
            parts.append(f"{self.pressure_hpa:.1f} hPa")
        if self.battery_mv is not None:
            parts.append(f"battery {self.battery_mv} mV")
        return "RuuviTag: " + ", ".join(parts) if parts else "RuuviTag"


def decode_ruuvi(payload: bytes) -> RuuviReading | None:
    """Ruuvi RAWv2 (data format 5), per Ruuvi's public documentation."""
    if len(payload) < 24 or payload[0] != 0x05:
        return None
    temp_raw = int.from_bytes(payload[1:3], "big", signed=True)
    hum_raw = int.from_bytes(payload[3:5], "big")
    pres_raw = int.from_bytes(payload[5:7], "big")
    power = int.from_bytes(payload[13:15], "big")
    voltage = (power >> 5) + 1600
    return RuuviReading(
        temperature_c=temp_raw * 0.005 if temp_raw != -32768 else None,
        humidity_pct=hum_raw * 0.0025 if hum_raw != 0xFFFF else None,
        pressure_hpa=(pres_raw + 50000) / 100.0 if pres_raw != 0xFFFF else None,
        battery_mv=voltage if (power >> 5) != 2047 else None,
        movement_count=payload[15] if payload[15] != 0xFF else None,
    )


# --- Dispatch ----------------------------------------------------------------

def identify_manufacturer(manufacturer_data: dict[int, bytes]) -> VendorIdentification | None:
    """Best non-Apple identification from manufacturer data, or None."""
    if MICROSOFT_COMPANY_ID in manufacturer_data:
        ident = decode_microsoft(manufacturer_data[MICROSOFT_COMPANY_ID])
        if ident is not None:
            return ident
    if RUUVI_COMPANY_ID in manufacturer_data:
        reading = decode_ruuvi(manufacturer_data[RUUVI_COMPANY_ID])
        if reading is not None:
            return VendorIdentification(kind="RuuviTag sensor",
                                        details=[reading.describe()],
                                        specificity=3)
        return VendorIdentification(kind="Ruuvi device", specificity=2)
    for company_id in manufacturer_data:
        family = FAMILY_BY_COMPANY.get(company_id)
        if family:
            return VendorIdentification(kind=family, specificity=1)
    for company_id in manufacturer_data:
        name = company_name(company_id)
        if not name.startswith("0x"):
            return VendorIdentification(kind=f"{name} device", specificity=1)
    return None
