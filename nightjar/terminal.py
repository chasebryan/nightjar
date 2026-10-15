"""Terminal plumbing for the live radar: ANSI on Windows, the alternate
screen, and the size of the window we're drawing into.
"""

from __future__ import annotations

import os
import shutil
import sys

ENTER_ALT_SCREEN = "\033[?1049h\033[?25l"
LEAVE_ALT_SCREEN = "\033[?25h\033[?1049l"
HOME_AND_CLEAR = "\033[H\033[J"


def enable_ansi() -> bool:
    """Turn on VT100 processing in the Windows console; a no-op elsewhere."""
    if os.name != "nt":
        return True
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE
        mode = ctypes.c_uint32()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        return bool(kernel32.SetConsoleMode(handle, mode.value | 0x0004))
    except Exception:
        return False


def size() -> tuple[int, int]:
    """(columns, rows) of the terminal, with sane fallbacks."""
    columns, rows = shutil.get_terminal_size((100, 30))
    return max(60, columns), max(10, rows)


class AlternateScreen:
    """Draw on the alternate screen and put the shell back afterwards."""

    def __init__(self, stream=None):
        self.stream = stream or sys.stdout
        self.active = False

    def __enter__(self):
        if self.stream.isatty():
            enable_ansi()
            self.stream.write(ENTER_ALT_SCREEN)
            self.stream.flush()
            self.active = True
        return self

    def frame(self, text: str) -> None:
        self.stream.write(HOME_AND_CLEAR + text + "\n")
        self.stream.flush()

    def __exit__(self, *exc):
        if self.active:
            self.stream.write(LEAVE_ALT_SCREEN)
            self.stream.flush()
            self.active = False
        return False
