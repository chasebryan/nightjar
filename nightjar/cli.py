"""nightjar command line.

  nightjar scan      listen, live (the default command)
  nightjar report    pattern of life over past logs (Level 4)
  nightjar trackers  hunt following-tags in past logs (Level 5)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
import uuid

from .history import load_sessions
from .patterns import analyze, format_report
from .registry import Registry
from .report import format_new_device, format_summary
from .scanner import run_scan
from .trackers import find_suspects, format_suspects

COMMANDS = ("scan", "report", "trackers")


def _add_scan_args(parser) -> None:
    parser.add_argument(
        "--duration", type=float, default=None, metavar="SECONDS",
        help="how long to listen (default: until Ctrl-C)")
    parser.add_argument(
        "--label", metavar="PLACE",
        help="label this session with where you are listening "
             "(e.g. home, office) — pattern and tracker analysis use it")
    parser.add_argument(
        "--log", metavar="FILE",
        help="append this session (header + sightings) to FILE as JSON lines")
    parser.add_argument(
        "--out", metavar="FILE",
        help="write the final device registry to FILE as JSON")
    parser.add_argument(
        "--simulate", action="store_true",
        help="run against a fake BLE neighbourhood (no hardware needed)")
    parser.add_argument(
        "--seed", type=int, default=None, help="random seed for --simulate")
    parser.add_argument(
        "--quiet", action="store_true",
        help="don't print devices as they are discovered")


def _cmd_scan(args) -> int:
    registry = Registry()
    log_file = open(args.log, "a", encoding="utf-8") if args.log else None
    if log_file is not None:
        header = {
            "type": "session",
            "session_id": uuid.uuid4().hex[:12],
            "label": args.label,
            "started_at": time.time(),
        }
        log_file.write(json.dumps(header) + "\n")
        log_file.flush()

    def on_sighting(sighting):
        record, is_new = registry.observe(sighting)
        if log_file is not None:
            log_file.write(json.dumps(sighting.to_dict()) + "\n")
            log_file.flush()
        if is_new and not args.quiet:
            print(format_new_device(record), flush=True)

    mode = "simulated neighbourhood" if args.simulate else "Bluetooth radio"
    where = f" @ {args.label}" if args.label else ""
    print(f"nightjar listening ({mode}{where}) — Ctrl-C to stop.", flush=True)
    try:
        asyncio.run(run_scan(args.duration, on_sighting,
                             simulate=args.simulate, seed=args.seed))
    except KeyboardInterrupt:
        pass
    except RuntimeError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 1
    finally:
        if log_file is not None:
            log_file.close()

    print(format_summary(registry))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(registry.to_dict(), fh, indent=2)
        print(f"registry written to {args.out}")
    return 0


def _load_or_report(logs) -> list:
    try:
        return load_sessions(logs)
    except (OSError, ValueError) as exc:
        print(f"nightjar: could not read logs: {exc}", file=sys.stderr)
        return []


def _cmd_report(args) -> int:
    sessions = _load_or_report(args.log)
    if not sessions:
        print("nightjar: no sessions found.", file=sys.stderr)
        return 1
    print(format_report(sessions, analyze(sessions)))
    return 0


def _cmd_trackers(args) -> int:
    sessions = _load_or_report(args.log)
    if not sessions:
        print("nightjar: no sessions found.", file=sys.stderr)
        return 1
    suspects = find_suspects(sessions, min_sessions=args.min_sessions,
                              min_span_hours=args.min_span_hours)
    print(format_suspects(suspects))
    return 0


def main(argv=None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0].startswith("-") or argv[0] not in COMMANDS:
        argv = ["scan"] + argv  # bare `nightjar` means "start listening"

    parser = argparse.ArgumentParser(
        prog="nightjar",
        description="A passive Bluetooth Low Energy listening post. "
                    "Receive-only: it never transmits or connects.")
    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", help="listen, live")
    _add_scan_args(scan)

    report = sub.add_parser("report", help="pattern of life over past logs")
    report.add_argument("--log", action="append", required=True,
                        metavar="FILE", help="a sightings log (repeatable)")

    trackers = sub.add_parser("trackers",
                              help="hunt following-tags in past logs")
    trackers.add_argument("--log", action="append", required=True,
                          metavar="FILE", help="a sightings log (repeatable)")
    trackers.add_argument("--min-sessions", type=int, default=2)
    trackers.add_argument("--min-span-hours", type=float, default=8.0)

    args = parser.parse_args(argv)
    if args.command == "scan":
        return _cmd_scan(args)
    if args.command == "report":
        return _cmd_report(args)
    return _cmd_trackers(args)
