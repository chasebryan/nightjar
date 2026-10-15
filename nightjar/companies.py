"""Bluetooth SIG company identifiers, for readable summaries.

Manufacturer-specific advertising data starts with a 16-bit company
identifier assigned by the Bluetooth SIG. The full list runs to
thousands of entries; this is a curated subset — the makers of things
people actually carry, wear, drive and put on shelves — so that
"0x004C" reads as "Apple" in a summary. Anything not listed is shown
as its hex code, which is still a perfectly good search term.

Source: Bluetooth SIG Assigned Numbers, "Company Identifiers".
https://www.bluetooth.com/specifications/assigned-numbers/
"""

from __future__ import annotations

COMPANY_NAMES: dict[int, str] = {
    0x0000: "Ericsson",
    0x0001: "Nokia",
    0x0002: "Intel",
    0x0003: "IBM",
    0x0004: "Toshiba",
    0x0006: "Microsoft",
    0x0008: "Motorola",
    0x0009: "Infineon",
    0x000A: "Cambridge Silicon Radio",
    0x000D: "Texas Instruments",
    0x000F: "Broadcom",
    0x0013: "Atmel",
    0x001D: "Qualcomm",
    0x0022: "NEC",
    0x0025: "NXP Semiconductors",
    0x0029: "Hitachi",
    0x0030: "ST Microelectronics",
    0x0036: "Renesas",
    0x003A: "Panasonic",
    0x003C: "BlackBerry",
    0x0040: "Seiko Epson",
    0x0044: "Socket Mobile",
    0x0046: "MediaTek",
    0x0047: "Bluegiga",
    0x0048: "Marvell",
    0x004C: "Apple",
    0x0055: "Plantronics",
    0x0056: "Sony Ericsson",
    0x0057: "Harman",
    0x0058: "Vizio",
    0x0059: "Nordic Semiconductor",
    0x005C: "Belkin",
    0x005D: "Realtek",
    0x0065: "HP",
    0x0067: "GN Audio (Jabra)",
    0x0068: "General Motors",
    0x006B: "Polar",
    0x0075: "Samsung",
    0x0076: "Creative",
    0x0078: "Nike",
    0x0082: "Sennheiser",
    0x0087: "Garmin",
    0x0089: "GN Hearing",
    0x008A: "Jawbone",
    0x008C: "Gimbal",
    0x009E: "Bose",
    0x009F: "Suunto",
    0x00A0: "Kensington",
    0x00B9: "Johnson Controls",
    0x00BA: "Starkey Hearing",
    0x00C4: "LG Electronics",
    0x00CC: "Beats",
    0x00CD: "Microchip",
    0x00CE: "Elgato",
    0x00D0: "Dexcom",
    0x00D2: "Dialog Semiconductor",
    0x00D6: "Timex",
    0x00D7: "Qualcomm Technologies",
    0x00D9: "Turtle Beach",
    0x00E0: "Google",
    0x00E8: "Lenovo",
    0x0118: "Radius Networks",
    0x012D: "Sony",
    0x0131: "Cypress Semiconductor",
    0x0157: "Huami (Zepp / Mi Band)",
    0x0171: "Amazon",
    0x01AB: "Meta (Facebook)",
    0x01DA: "Logitech",
    0x027D: "Huawei",
    0x02E1: "Victron Energy",
    0x02E5: "Espressif",
    0x02FF: "Silicon Labs",
    0x038F: "Xiaomi",
    0x0499: "Ruuvi",
    0x0553: "Nintendo",
    0x05A7: "Sonos",
    0x0969: "SwitchBot (Woan)",
    0xFFFF: "(reserved / test)",
}


def company_name(company_id: int) -> str:
    """Readable maker name for a SIG company id, or its hex code."""
    return COMPANY_NAMES.get(company_id, f"0x{company_id:04X}")
