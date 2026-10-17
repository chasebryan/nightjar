#!/usr/bin/env python3
"""Apply the nightjar-hack overlay onto a nightjar checkout.

    python3 apply_overlay.py /path/to/nightjar
    python3 apply_overlay.py /path/to/nightjar --check     # report only
    python3 apply_overlay.py /path/to/nightjar --force     # overwrite send.py

It drops nightjar/send.py into the package and makes six small,
anchored edits (five in nightjar/cli.py, one in pyproject.toml) plus a
version bump. Anchors are exact strings, so a small upstream drift is
caught and reported rather than silently mis-patched. Nothing is
committed, nothing is pushed: the checkout is yours.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HACK_VERSION = "4.0.0"

CLI = "nightjar/cli.py"
PYPROJECT = "pyproject.toml"

# (file, exact old text, replacement) - each old text must appear once.
PATCHES: list[tuple[str, str, str]] = [
    (
        CLI,
        '''from .scanner import MODES, ScanOutcome, run_scan
''',
        '''from .scanner import MODES, ScanOutcome, run_scan
from . import send as sendcmd
''',
    ),
    (
        CLI,
        '''        description="A passive Bluetooth Low Energy listening post. "
                    "Receive-only: it never connects or pairs, and asks the "
                    "radio for passive scanning wherever the platform allows.",
''',
        '''        description="A Bluetooth Low Energy listening post that can talk. "
                    "Passive receive by default; `send` pushes payloads out "
                    "over TCP, UDP, HTTP and BLE.",
''',
    ),
    (
        CLI,
        '''COMMANDS = ("scan", "watch", "report", "trackers", "show", "anomalies", "demo")
''',
        '''COMMANDS = ("scan", "watch", "send", "serve", "report", "trackers",
            "show", "anomalies", "demo")
''',
    ),
    (
        CLI,
        '''    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")
    return parser
''',
        '''    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")

    send = sub.add_parser("send", help="send a payload over the network or BLE")
    sendcmd.add_send_args(send)

    serve = sub.add_parser("serve", help="receive payloads over the network")
    sendcmd.add_serve_args(serve)
    return parser
''',
    ),
    (
        CLI,
        '''        "demo": _cmd_demo,
    }
''',
        '''        "demo": _cmd_demo,
        "send": sendcmd.cmd_send,
        "serve": sendcmd.cmd_serve,
    }
''',
    ),
    (
        PYPROJECT,
        '''dev = [
    "ruff>=0.5",
    "mypy>=1.10",
    "pytest>=8",
]
''',
        '''dev = [
    "ruff>=0.5",
    "mypy>=1.10",
    "pytest>=8",
]
tx = [
    "bless>=0.2.0",
    "websockets>=12",
    "pyserial>=3.5",
]
''',
    ),
]


def patch_file(path: Path, old: str, new: str, *, write: bool) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    if new in text and old not in text:
        return "already"
    if old not in text:
        return "anchor-not-found"
    if text.count(old) != 1:
        return f"anchor-ambiguous({text.count(old)})"
    if write:
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return "patched"


def bump_version(path: Path, *, write: bool) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    match = re.search(r'__version__\s*=\s*"([^"]+)"', text)
    if match is None:
        return "no-version"
    if match.group(1) == HACK_VERSION:
        return "already"
    if write:
        path.write_text(text[:match.start(1)] + HACK_VERSION + text[match.end(1):],
                        encoding="utf-8")
    return f"{match.group(1)} -> {HACK_VERSION}"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="apply_overlay",
        description="Apply the nightjar-hack overlay (send/serve) to a nightjar checkout.")
    parser.add_argument("repo", nargs="?", default=".",
                        help="path to the nightjar checkout (default: .)")
    parser.add_argument("--check", action="store_true",
                        help="report what would change, write nothing")
    parser.add_argument("--force", action="store_true",
                        help="overwrite an existing nightjar/send.py")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / "nightjar" / "cli.py").exists():
        print(f"not a nightjar checkout (no nightjar/cli.py under {repo})",
              file=sys.stderr)
        return 2
    write = not args.check
    print(f"nightjar checkout: {repo}{'  [check only]' if args.check else ''}")

    source = HERE / "nightjar" / "send.py"
    if not source.exists():
        print(f"  ! overlay is incomplete: {source} not found", file=sys.stderr)
        return 2
    destination = repo / "nightjar" / "send.py"
    if destination.exists() and not args.force:
        print("  = nightjar/send.py already present (use --force to overwrite)")
    else:
        if write:
            shutil.copyfile(source, destination)
        print("  + nightjar/send.py")

    problems = 0
    for relative, old, new in PATCHES:
        outcome = patch_file(repo / relative, old, new, write=write)
        if outcome == "missing" or outcome.startswith("anchor"):
            problems += 1
            print(f"  ! {relative}: {outcome}")
        elif outcome == "already":
            print(f"  = {relative}: already applied")
        else:
            print(f"  ~ {relative}: patched")

    version = bump_version(repo / "nightjar" / "__init__.py", write=write)
    if version in ("missing", "no-version"):
        problems += 1
        print(f"  ! nightjar/__init__.py: {version}")
    elif version == "already":
        print("  = nightjar/__init__.py: version already " + HACK_VERSION)
    else:
        print(f"  ~ nightjar/__init__.py: version {version}")

    print()
    if problems:
        print(f"{problems} anchor(s) need a hand - the file is plain text, "
              "the edits are obvious.")
    print("next:")
    print(f"  cd {repo}")
    print("  pip install -e .")
    print("  pip install 'nightjar[tx]'   # only for ble:// and ble-gatt://")
    print("  nightjar send --help")
    print("  nightjar send tcp://127.0.0.1:9000 --payload hello")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
