"""Load nightjar/send.py (the overlay's source copy) as a standalone module.

send.py imports only the standard library at module level — the BLE
transports import bleak/bless lazily — so the network and payload
machinery can be tested without a nightjar checkout or a radio.
"""

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load():
    spec = importlib.util.spec_from_file_location(
        "njhack_send", ROOT / "nightjar" / "send.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["njhack_send"] = module
    spec.loader.exec_module(module)
    return module


send = _load()
