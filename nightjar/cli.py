"""nightjar command line.

  nightjar scan      listen, live (the default command)
  nightjar watch     listen indefinitely, alert on events
  nightjar report    pattern of life over past logs (Level 4)
  nightjar trackers  hunt following-tags in past logs (Level 5)
  nightjar show      everything the logs know about one device
  nightjar demo      write a multi-day demo log and analyze it

Environment: NIGHTJAR_LOG (default log file), NIGHTJAR_LABEL (default
place label), NIGHTJAR_WEBHOOK_URL / NIGHTJAR_WEBHOOK_FORMAT (alerts),
NIGHTJAR_IGNORE (comma-separated addresses or names that are yours).
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import sys
import time
from collections import deque

from . import __version__
from .anomaly import (
    MIN_BASELINE_SESSIONS,
    find_anomalies,
    format_anomalies,
    split_baseline,
)
from .history import LoadReport, Session, filter_sessions, load_log
from .live import render_live
from .patterns import IdentityPattern, analyze, format_report
from .place import current_place
from .post import ListeningPost, Observation, SessionLog
from .report import (
    format_identity_summary,
    format_new_device,
    format_summary,
    summary_dict,
)
from .scanner import MODES, ScanOutcome, run_scan
from .services import describe_uuid
from .simulate import write_demo_log
from .terminal import AlternateScreen
from .terminal import size as terminal_size
from .text import fmt_hours, fmt_local, sparkline
from .trackers import (
    DEFAULT_MIN_RSSI,
    SUSPECT_THRESHOLD,
    analyze_trackers,
    format_tracker_report,
)
from .watch import WEBHOOK_FORMATS, AlertDispatcher, AlertEngine, WebhookAlerter

COMMANDS = ("scan", "watch", "report", "trackers", "show", "anomalies", "demo")
GLOBAL_FLAGS = ("-h", "--help", "-V", "--version")


# --- Shared argument blocks --------------------------------------------------

def _env_list(name: str) -> list[str]:
    raw = os.environ.get(name, "")
    return [item.strip() for item in raw.split(",") if item.strip()]


def _add_listen_args(parser) -> None:
    parser.add_argument(
        "--duration", type=float, default=None, metavar="SECONDS",
        help="how long to listen (default: until Ctrl-C)")
    parser.add_argument(
        "--label", metavar="PLACE",
        help="label this session with where you are listening; "
             "default: $NIGHTJAR_LABEL, else detected from the Wi-Fi network")
    parser.add_argument(
        "--post", metavar="NAME", default=os.environ.get("NIGHTJAR_POST"),
        help="name this listening post (the ear, not the place: 'mac', "
             "'phone', 'front-door'); default: $NIGHTJAR_POST, else the hostname")
    parser.add_argument(
        "--live", action="store_true",
        help="show the live radar instead of discovery lines")
    parser.add_argument(
        "--addresses", action="store_true",
        help="also print the per-address table in the summary")
    parser.add_argument(
        "--log", metavar="FILE", default=os.environ.get("NIGHTJAR_LOG"),
        help="append this session (header + sightings) to FILE as JSON lines "
             "(default: $NIGHTJAR_LOG)")
    parser.add_argument(
        "--out", metavar="FILE",
        help="write the final registry and identities to FILE as JSON")
    parser.add_argument(
        "--simulate", action="store_true",
        help="run against a fake BLE neighbourhood (no hardware needed)")
    parser.add_argument(
        "--seed", type=int, default=None, help="random seed for --simulate")
    parser.add_argument(
        "--quiet", action="store_true",
        help="don't print devices as they are discovered")
    parser.add_argument(
        "--json", action="store_true",
        help="print events and the final summary as JSON lines instead of text")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--mode", choices=MODES, default="passive",
        help="scanning mode to ask for (default: passive, falling back to "
             "active with a notice when the platform can't do passive)")
    mode.add_argument(
        "--passive", action="store_const", const="strict-passive", dest="mode",
        help="passive scanning only; fail rather than fall back to active")
    mode.add_argument(
        "--active", action="store_const", const="active", dest="mode",
        help="active scanning: sends standard scan requests, hears scan responses")
    parser.add_argument(
        "--adapter", metavar="NAME",
        help="Bluetooth adapter to use (Linux: hci0, hci1, ...)")
    parser.add_argument(
        "--ignore", action="append", default=_env_list("NIGHTJAR_IGNORE"),
        metavar="ADDRESS|NAME",
        help="your own devices (address prefix or name), never alerted on; "
             "repeatable, also $NIGHTJAR_IGNORE")
    parser.add_argument(
        "--home", metavar="LAT,LON", default=os.environ.get("NIGHTJAR_HOME"),
        help="your own position, opt-in: turns a drone's broadcast operator "
             "coordinates into a distance and bearing from you. Never logged "
             "into any device's record. Also $NIGHTJAR_HOME")


def _parse_home(value: str | None):
    """'45.54,-122.96' → (lat, lon), or None. Invalid input is ignored."""
    if not value:
        return None
    try:
        lat, lon = (float(part) for part in value.split(",", 1))
    except (ValueError, TypeError):
        return None
    if -90 <= lat <= 90 and -180 <= lon <= 180:
        return (lat, lon)
    return None


def _add_log_args(parser) -> None:
    parser.add_argument(
        "logs", nargs="*", metavar="LOG",
        help="sightings logs: files, directories of logs, or globs "
             "(default: $NIGHTJAR_LOG)")
    parser.add_argument("--log", action="append", default=[], metavar="FILE",
                        help="a sightings log (repeatable; same as a positional LOG)")
    parser.add_argument("--since", type=float, default=None, metavar="DAYS",
                        help="only sessions that started in the last DAYS days")
    parser.add_argument("--place", metavar="LABEL",
                        help="only sessions whose label contains LABEL")
    parser.add_argument("--json", action="store_true",
                        help="print the result as JSON")


# --- Helpers -----------------------------------------------------------------

def _resolve_place(args) -> tuple[str | None, str | None]:
    """(label, source): the user's --label wins; else the Wi-Fi."""
    label = getattr(args, "label", None)
    if label:
        return label, "manual"
    env_label = os.environ.get("NIGHTJAR_LABEL")
    if env_label:
        return env_label, "env"
    place = current_place()
    return (place, "wifi") if place else (None, None)


def _resolve_post(args) -> str | None:
    """Which ear this is: --post / $NIGHTJAR_POST, else the short hostname."""
    post = getattr(args, "post", None)
    if post:
        return post
    try:
        import socket

        host = socket.gethostname().split(".")[0].strip()
        return host or None
    except Exception:
        return None


def _banner(args, label, mode, watching=False, post=None) -> str:
    where_mode = ("simulated neighbourhood" if args.simulate
                  else f"Bluetooth radio, {mode} scan")
    where = f" @ {label}" if label else ""
    ear = f" [{post}]" if post else ""
    verb = "watching" if watching else "listening"
    return f"nightjar {verb} ({where_mode}{where}){ear} — Ctrl-C to stop."


def _scan_kwargs(args) -> dict:
    mode = args.mode
    strict = mode == "strict-passive"
    return {
        "simulate": args.simulate, "seed": args.seed,
        "mode": "passive" if strict else mode, "strict": strict,
        "adapter": args.adapter,
    }


def _emit_json(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def _gather_logs(args) -> list[str]:
    logs = list(args.logs) + list(args.log)
    if not logs and os.environ.get("NIGHTJAR_LOG"):
        logs = [os.environ["NIGHTJAR_LOG"]]
    return logs


def _load(args) -> tuple[list[Session], LoadReport] | None:
    logs = _gather_logs(args)
    if not logs:
        print("nightjar: no logs given (pass files, or set NIGHTJAR_LOG).",
              file=sys.stderr)
        return None
    try:
        report = load_log(logs)
    except OSError as exc:
        print(f"nightjar: could not read logs: {exc}", file=sys.stderr)
        return None
    if not report.files:
        print("nightjar: no log files matched.", file=sys.stderr)
        return None
    if report.skipped_lines and not args.json:
        print(f"nightjar: skipped {report.skipped_lines} unreadable line(s).",
              file=sys.stderr)
    sessions = report.sessions
    since = time.time() - args.since * 86400 if args.since else None
    sessions = filter_sessions(sessions, since=since, place=args.place)
    if not sessions:
        print("nightjar: no sessions found.", file=sys.stderr)
        return None
    return sessions, report


# --- Listening commands --------------------------------------------------------

def _listen(args, *, watching: bool) -> int:
    label, label_source = _resolve_place(args)
    post_name = _resolve_post(args)
    log = SessionLog(args.log, label=label, label_source=label_source,
                     post=post_name) if args.log else None
    engine = None
    dispatcher = None
    alerter = None
    if watching:
        engine = AlertEngine(
            alert_new=not args.no_alert_new,
            warmup_seconds=args.warmup,
            tracker_min_span=args.tracker_min_minutes * 60.0,
            tracker_min_hours=args.tracker_min_hours,
            tracker_min_rssi=args.tracker_min_rssi,
            ignore=args.ignore,
            home=_parse_home(args.home))
        alerter = WebhookAlerter(args.webhook, fmt=args.webhook_format)
        dispatcher = AlertDispatcher([alerter] if alerter.url else [])
    live = getattr(args, "live", False)
    if live and args.json:
        print("nightjar: --live and --json don't mix.", file=sys.stderr)
        return 2
    screen = AlternateScreen() if live else None
    recent_alerts: deque[str] = deque(maxlen=3)

    def on_observation(obs: Observation) -> None:
        if args.json:
            if obs.new_identity:
                _emit_json({"event": "new-device", "seen_at": obs.sighting.seen_at,
                            **obs.identity.to_dict()})
            for alert in obs.alerts:
                _emit_json({"event": "alert", **alert.to_dict()})
            return
        if obs.new_address and not args.quiet and not live:
            print(format_new_device(obs.record), flush=True)
        for alert in obs.alerts:
            stamp = time.strftime("%H:%M:%S", time.localtime(alert.seen_at))
            line = f"ALERT {stamp}  {alert.text}"
            recent_alerts.append(line)  # the radar frame shows the latest few
            if screen is None:
                print(line, flush=True)

    post = ListeningPost(log=log, engine=engine, dispatcher=dispatcher,
                         on_observation=on_observation)
    started: dict[str, ScanOutcome | None] = {"outcome": None}

    def on_start(outcome: ScanOutcome) -> None:
        started["outcome"] = outcome
        post.started(outcome.mode)
        if args.json:
            _emit_json({"event": "start", "mode": outcome.mode, "label": label,
                        "label_source": label_source, "post": post_name,
                        "notes": outcome.notes,
                        "session_id": log.session_id if log else None,
                        "started_at": post.started_at})
            return
        for note in outcome.notes:
            print(f"nightjar: {note}", file=sys.stderr, flush=True)
        if screen is None:
            print(_banner(args, label, outcome.mode, watching=watching,
                          post=post_name), flush=True)
            if alerter is not None and alerter.url:
                print(f"alerts will also post to the {alerter.format} webhook.",
                      flush=True)

    async def run_live(screen: AlternateScreen) -> None:
        task = asyncio.create_task(run_scan(
            args.duration, post.observe, on_start=on_start, **_scan_kwargs(args)))
        try:
            while not task.done():
                columns, rows = terminal_size()
                frame = render_live(post.resolver, started_at=post.started_at or time.time(),
                                    place=label, top=max(3, rows - 7 - len(recent_alerts)),
                                    width=columns, mode=post.scan_mode,
                                    alerts=list(recent_alerts))
                screen.frame(frame)
                await asyncio.sleep(1.0)
            await task
        except asyncio.CancelledError:
            task.cancel()
            raise

    code = 0
    try:
        if screen is not None:
            with screen:
                asyncio.run(run_live(screen))
        else:
            asyncio.run(run_scan(args.duration, post.observe, on_start=on_start,
                                 **_scan_kwargs(args)))
    except KeyboardInterrupt:
        pass
    except (RuntimeError, ValueError) as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        code = 1
    finally:
        post.close()

    if started["outcome"] is None:
        return code or 1

    summary = summary_dict(
        post.registry, post.resolver, scan_mode=post.scan_mode,
        label=label, label_source=label_source, post=post_name,
        started_at=post.started_at,
        ended_at=time.time(), alerts=[a.to_dict() for a in post.alerts],
        session_id=log.session_id if log else None, log=args.log)
    if args.json:
        _emit_json({"event": "summary", **summary})
    else:
        print(format_identity_summary(post.resolver, post.registry.total_sightings))
        if args.addresses or len(post.resolver) == 0:
            print(format_summary(post.registry))
        if post.alerts:
            print(f"\n{len(post.alerts)} alert(s) raised this session.")
        if dispatcher is not None and dispatcher.failed:
            print(f"{dispatcher.failed} alert(s) could not be delivered to the webhook.",
                  file=sys.stderr)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(summary, fh, indent=2)
        if not args.json:
            print(f"summary written to {args.out}")
    return code


def _cmd_scan(args) -> int:
    return _listen(args, watching=False)


def _cmd_watch(args) -> int:
    return _listen(args, watching=True)


# --- Analysis commands ----------------------------------------------------------

def _cmd_report(args) -> int:
    loaded = _load(args)
    if loaded is None:
        return 1
    sessions, report = loaded
    patterns = analyze(sessions)
    if args.min_sessions > 1:
        patterns = [p for p in patterns if p.sessions_present >= args.min_sessions]
    if args.sort == "first":
        patterns.sort(key=lambda p: p.identity.first_seen)
    elif args.sort == "last":
        patterns.sort(key=lambda p: -p.identity.last_seen)
    elif args.sort == "sessions":
        patterns.sort(key=lambda p: (-p.sessions_present, -p.identity.sightings))
    if args.json:
        _emit_json({
            "sessions": [s.to_dict() for s in sessions],
            "skipped_lines": report.skipped_lines,
            "devices": [p.to_dict() for p in patterns],
        })
        return 0
    print(format_report(sessions, patterns, wide=args.wide))
    alerts = sum(len(s.alerts) for s in sessions)
    if alerts:
        print(f"\n{alerts} alert(s) were raised during these sessions.")
    return 0


def _cmd_trackers(args) -> int:
    loaded = _load(args)
    if loaded is None:
        return 1
    sessions, _ = loaded
    report = analyze_trackers(sessions, min_sessions=args.min_sessions,
                              min_span_hours=args.min_span_hours,
                              min_rssi=args.min_rssi, ignore=args.ignore,
                              threshold=args.threshold)
    if args.json:
        _emit_json({"sessions": len(sessions), **report.to_dict()})
        return 0
    print(format_tracker_report(report))
    return 0


def _cmd_anomalies(args) -> int:
    loaded = _load(args)
    if loaded is None:
        return 1
    sessions, _ = loaded
    baseline, observation = split_baseline(
        sessions, observation_days=args.observation_days)
    anomalies = find_anomalies(sessions, baseline=baseline, observation=observation)
    had_baseline = len(baseline) >= MIN_BASELINE_SESSIONS and bool(observation)
    if args.json:
        _emit_json({
            "baseline_sessions": len(baseline),
            "observation_sessions": len(observation),
            "had_baseline": had_baseline,
            "anomalies": [a.to_dict() for a in anomalies],
        })
        return 0
    print(format_anomalies(anomalies, had_baseline=had_baseline))
    return 0


def _format_show(pattern: IdentityPattern) -> str:
    ident = pattern.identity
    lines = [
        f"{ident.label}",
        f"  kind:        {ident.kind}",
        f"  identity:    {ident.key} (by {ident.basis})",
        f"  status:      {pattern.status}; {pattern.sessions_present} sessions, "
        f"{pattern.days_present} days, {ident.sightings} sightings",
        f"  first seen:  {fmt_local(ident.first_seen)}",
        f"  last seen:   {fmt_local(ident.last_seen)}",
        f"  usual hours: {pattern.usual_hours} on {pattern.usual_days}",
        f"  hour profile {pattern.hour_profile}  (00→23)",
        f"  avg stay:    {fmt_hours(pattern.average_presence_seconds)}",
    ]
    if pattern.labels:
        lines.append(f"  places:      {', '.join(sorted(pattern.labels))}")
    addresses = sorted(ident.addresses)
    shown = ", ".join(addresses[:6]) + (f" (+{len(addresses) - 6} more)"
                                        if len(addresses) > 6 else "")
    lines.append(f"  addresses:   {shown}")
    if ident.address_kinds:
        lines.append(f"  addr type:   {', '.join(sorted(ident.address_kinds))}")
    if ident.names:
        lines.append(f"  names:       {', '.join(sorted(ident.names))}")
    if ident.companies:
        lines.append(f"  makers:      {', '.join(sorted(ident.companies))}")
    if ident.service_uuids:
        lines.append("  services:    "
                     + ", ".join(describe_uuid(u) for u in sorted(ident.service_uuids)))
    if ident.details:
        lines.append(f"  decoded:     {ident.details[0]}")
    flags = []
    if ident.tracker_like:
        flags.append("tracker-shaped")
    if ident.findmy_with_owner:
        flags.append("Find My, seen with owner")
    if ident.rotates:
        flags.append("rotates address")
    if flags:
        lines.append(f"  flags:       {', '.join(flags)}")
    median = pattern.rssi_median
    lines.append(f"  signal:      median {median if median is not None else '?'} dBm, "
                 f"closest {ident.rssi_closest if ident.rssi_closest is not None else '?'} dBm  "
                 f"{sparkline(ident.signal.values, width=24)}")
    lines.append("  sessions:")
    for presence in pattern.presences:
        where = f" @ {presence.label}" if presence.label else ""
        lines.append(
            f"    {fmt_local(presence.first_seen)} → "
            f"{time.strftime('%H:%M', time.localtime(presence.last_seen))}"
            f"{where}: {presence.sightings} sightings, "
            f"median {presence.rssi_median if presence.rssi_median is not None else '?'} dBm, "
            f"stayed {fmt_hours(presence.span_seconds)}")
    return "\n".join(lines)


def _drone_track(sessions: list[Session], key: str):
    """Re-walk the logs for one drone identity: its positions and operators."""
    from .identify import IdentityResolver
    from .remoteid import parse_service_data, remoteid_value
    resolver = IdentityResolver()
    track = []       # (seen_at, Location)
    operators: dict[tuple, object] = {}
    for session in sessions:
        for sighting in session.sightings:
            identity = resolver.observe(sighting)
            if identity.key != key:
                continue
            value = remoteid_value(sighting.service_data)
            if value is None:
                continue
            for message in parse_service_data(value):
                if message.location is not None and message.location.latitude is not None:
                    track.append((sighting.seen_at, message.location))
                sysm = message.system
                if sysm is not None and sysm.operator_latitude is not None \
                        and sysm.operator_longitude is not None:
                    operators[(round(sysm.operator_latitude, 6),
                               round(sysm.operator_longitude, 6))] = sysm
    return track, operators


def _format_drone_track(track, operators, home) -> str:
    from .remoteid import bearing, compass, haversine
    lines = ["  flight track:"]
    if not track:
        lines.append("    (no positions decoded)")
    else:
        alts = [loc.altitude_geo for _, loc in track if loc.altitude_geo is not None]
        lines.append(f"    {len(track)} positions, "
                     f"{fmt_local(track[0][0])} → {fmt_local(track[-1][0])}")
        if alts:
            lines.append(f"    max altitude {max(alts):.0f} m (geodetic)")
        step = max(1, len(track) // 6)
        for seen, loc in track[::step][:6]:
            alt = loc.altitude_geo if loc.altitude_geo is not None else loc.altitude_baro
            move = ""
            if loc.speed_h is not None and loc.direction is not None:
                move = f", {loc.speed_h:.1f} m/s {compass(loc.direction)}"
            lines.append(
                f"    {time.strftime('%H:%M:%S', time.localtime(seen))}  "
                f"{loc.latitude:.5f},{loc.longitude:.5f}  "
                f"alt {alt:.0f} m{move}" if alt is not None else
                f"    {time.strftime('%H:%M:%S', time.localtime(seen))}  "
                f"{loc.latitude:.5f},{loc.longitude:.5f}{move}")
    for (lat, lon), sysm in operators.items():
        if home is not None:
            dist = haversine(home[0], home[1], lat, lon)
            brg = bearing(home[0], home[1], lat, lon)
            lines.append(f"    operator {dist:.0f} m {compass(brg)} "
                         f"({sysm.operator_location_name})")
        else:
            lines.append(f"    operator {lat:.5f},{lon:.5f} "
                         f"({sysm.operator_location_name})")
    return "\n".join(lines)


def _cmd_show(args) -> int:
    loaded = _load(args)
    if loaded is None:
        return 1
    sessions, _ = loaded
    patterns = [p for p in analyze(sessions) if p.identity.matches(args.query)]
    if not patterns:
        print(f"nightjar: nothing in these logs matches {args.query!r}.",
              file=sys.stderr)
        return 1
    if args.json:
        _emit_json({"query": args.query, "matches": [p.to_dict() for p in patterns]})
        return 0
    home = _parse_home(getattr(args, "home", None))
    blocks = []
    for pattern in patterns:
        text = _format_show(pattern)
        if pattern.identity.drone is not None:
            track, operators = _drone_track(sessions, pattern.identity.key)
            text += "\n" + _format_drone_track(track, operators, home)
        blocks.append(text)
    print("\n\n".join(blocks))
    return 0


def _cmd_demo(args) -> int:
    session_ids = write_demo_log(args.out, days=args.days, seed=args.seed)
    print(f"wrote {len(session_ids)} demo sessions over {args.days} day(s) to {args.out}")
    if args.no_report:
        print(f"try:  nightjar report {args.out}\n      nightjar trackers {args.out}")
        return 0
    sessions = load_log([args.out]).sessions
    print()
    print(format_report(sessions, analyze(sessions)))
    print()
    print(format_tracker_report(analyze_trackers(sessions)))
    return 0


# --- Parser ----------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="nightjar",
        description="A passive Bluetooth Low Energy listening post. "
                    "Receive-only: it never connects or pairs, and asks the "
                    "radio for passive scanning wherever the platform allows.",
        epilog="Run `nightjar` with no command to start listening.")
    parser.add_argument("-V", "--version", action="version",
                        version=f"nightjar {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan", help="listen, live (the default)")
    _add_listen_args(scan)

    watch = sub.add_parser("watch", help="listen and alert on events")
    _add_listen_args(watch)
    watch.add_argument(
        "--webhook", metavar="URL",
        help="webhook for alerts: Discord, Slack, ntfy, or any JSON endpoint "
             "(or set NIGHTJAR_WEBHOOK_URL)")
    watch.add_argument(
        "--webhook-format", choices=WEBHOOK_FORMATS, default=None,
        help="payload shape for the webhook (default: guessed from the URL)")
    watch.add_argument(
        "--no-alert-new", action="store_true",
        help="don't alert when a new device appears")
    watch.add_argument(
        "--warmup", type=float, default=120.0, metavar="SECONDS",
        help="don't alert on new devices for the first SECONDS (default 120)")
    watch.add_argument(
        "--tracker-min-minutes", type=float, default=45.0, metavar="MIN",
        help="a tag must be around this long before it is a suspect (default 45)")
    watch.add_argument(
        "--tracker-min-hours", type=int, default=2, metavar="N",
        help="...and across this many distinct clock hours (default 2)")
    watch.add_argument(
        "--tracker-min-rssi", type=int, default=-80, metavar="DBM",
        help="...with a median signal at least this strong (default -80)")

    report = sub.add_parser("report", help="pattern of life over past logs")
    _add_log_args(report)
    report.add_argument("--wide", action="store_true",
                        help="a second line per device: first/last seen, usual days, stays")
    report.add_argument("--min-sessions", type=int, default=1, metavar="N",
                        help="only devices present in at least N sessions")
    report.add_argument("--sort", choices=("seen", "first", "last", "sessions"),
                        default="seen", help="row order (default: most sightings first)")

    trackers = sub.add_parser("trackers",
                              help="hunt following-tags in past logs")
    _add_log_args(trackers)
    trackers.add_argument("--min-sessions", type=int, default=2)
    trackers.add_argument("--min-span-hours", type=float, default=8.0)
    trackers.add_argument("--min-rssi", type=int, default=DEFAULT_MIN_RSSI,
                          metavar="DBM", help="close-range floor (default -80)")
    trackers.add_argument("--threshold", type=int, default=SUSPECT_THRESHOLD,
                          help=f"minimum score to report (default {SUSPECT_THRESHOLD})")
    trackers.add_argument("--ignore", action="append",
                          default=_env_list("NIGHTJAR_IGNORE"), metavar="ADDRESS|NAME",
                          help="your own tags (address prefix or name); repeatable, "
                               "also $NIGHTJAR_IGNORE")

    show = sub.add_parser("show", help="everything the logs know about one device")
    show.add_argument("query", metavar="QUERY",
                      help="an address (or prefix), a name, a kind, or an identity key")
    show.add_argument("--home", metavar="LAT,LON", default=os.environ.get("NIGHTJAR_HOME"),
                      help="your position, to show a drone operator's distance and bearing")
    _add_log_args(show)

    anomalies = sub.add_parser(
        "anomalies", help="what broke the pattern: missing regulars, odd-hour arrivals")
    _add_log_args(anomalies)
    anomalies.add_argument(
        "--observation-days", type=float, default=1.0, metavar="DAYS",
        help="treat sessions in the last DAYS as 'what just happened', "
             "the rest as the baseline (default 1)")

    demo = sub.add_parser("demo", help="write a multi-day demo log and analyze it")
    demo.add_argument("--out", default="nightjar-demo.jsonl", metavar="FILE")
    demo.add_argument("--days", type=int, default=2)
    demo.add_argument("--seed", type=int, default=None)
    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")
    return parser


def _never_crash_on_a_glyph() -> None:
    """The reports use sparklines and arrows; a console that can't draw
    them should show a placeholder, not kill the run."""
    for stream in (sys.stdout, sys.stderr):
        encoding = (getattr(stream, "encoding", None) or "").lower().replace("-", "")
        if encoding != "utf8" and hasattr(stream, "reconfigure"):
            with contextlib.suppress(Exception):  # exotic streams: leave them be
                stream.reconfigure(errors="replace")


def main(argv=None) -> int:
    _never_crash_on_a_glyph()
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or (argv[0] not in COMMANDS and argv[0] not in GLOBAL_FLAGS):
        argv = ["scan", *argv]  # bare `nightjar` means "start listening"
    parser = build_parser()
    args = parser.parse_args(argv)
    handlers = {
        "scan": _cmd_scan,
        "watch": _cmd_watch,
        "report": _cmd_report,
        "trackers": _cmd_trackers,
        "show": _cmd_show,
        "anomalies": _cmd_anomalies,
        "demo": _cmd_demo,
    }
    return handlers[args.command](args)
