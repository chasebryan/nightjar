#!/usr/bin/env python3
"""knocktalk_relay — an operator-run rendezvous for Knocktalk.

Run this on any host you control (a VPS, a home server). The relay
owns a public knock surface — the sync port and the 16 alphabet
ports — and a small token-gated mailbox API:

  1. A phone POSTs /declare {token, from, to}: "the next knock
     burst from my IP is for mailbox `to`."
  2. The phone knocks THIS host exactly as it would knock another
     phone (connect-and-close, no bytes).
  3. The relay records the burst. Every sync knock starts a new
     sequence, mirroring the app's engine, so each Knocktalk frame
     lands as exactly one mailbox entry.
  4. The receiving phone GETs /inbox?box=<its mailbox>&token=…,
     which returns and clears its sequences; the phone replays them
     into its own Knocktalk engine.

The relay NEVER sees message content. Knocktalk payloads are sealed
between the phones (ChaCha20-Poly1305 or AES-256-GCM under a pairing
key the relay never holds). All the relay can observe is port
numbers, timing, source IPs, and mailbox names — rendezvous
metadata, nothing more. It can drop or delay sequences (a phone
will report the delivery as failed); it cannot forge one, because
the AEAD tag will not verify on the receiving phone.

Usage:
    KNOCKTALK_TOKEN=<a long random string> python3 knocktalk_relay.py

Environment:
    KNOCKTALK_TOKEN         required; shared gate token for the API
    KNOCKTALK_CONTROL_PORT  API port (default 8901)
    KNOCKTALK_BIND          bind address (default 0.0.0.0)

The knock ports are all below 1024, so on Linux this needs root or
CAP_NET_BIND_SERVICE:  sudo KNOCKTALK_TOKEN=... python3 ...

State is in memory: a restart empties the mailboxes. Delivery is
still honest — senders time out and mark messages failed rather
than delivered.
"""

import hmac
import json
import os
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = os.environ.get("KNOCKTALK_TOKEN", "")
CONTROL_PORT = int(os.environ.get("KNOCKTALK_CONTROL_PORT", "8901"))
BIND = os.environ.get("KNOCKTALK_BIND", "0.0.0.0")

SYNC_PORT = 443
ALPHABET = [7, 9, 13, 19, 21, 22, 23, 25, 43, 53, 70, 79, 80, 110,
            111, 143]
KNOCK_PORTS = [SYNC_PORT] + ALPHABET

GAP_SECONDS = 3.5        # quiet that closes a trailing burst
DECLARE_TTL = 300        # a declaration lives five minutes
MAX_BOX = 64             # sequences kept per mailbox

_lock = threading.Lock()
_declares = {}           # source ip -> (to_box, from_box, expires)
_bursts = {}             # source ip -> [ports]
_timers = {}             # source ip -> threading.Timer
_mailboxes = {}          # box -> [ {"from":…, "ports":[…], "at":…} ]
_last_seen = {}          # box -> epoch of its last declare or collect


def _flush_locked(ip):
    """Move the pending burst for `ip` into its declared mailbox.
    Caller holds the lock."""
    ports = _bursts.pop(ip, None)
    timer = _timers.pop(ip, None)
    if timer is not None:
        timer.cancel()
    if not ports:
        return
    decl = _declares.get(ip)
    if decl is None or decl[2] < time.time():
        return  # undeclared knocks are just scans; drop them
    to_box, from_box, _ = decl
    box = _mailboxes.setdefault(to_box, [])
    box.append({"from": from_box, "ports": ports, "at": time.time()})
    del box[:-MAX_BOX]


def _flush(ip):
    with _lock:
        _flush_locked(ip)


def _arm_timer_locked(ip):
    old = _timers.get(ip)
    if old is not None:
        old.cancel()
    timer = threading.Timer(GAP_SECONDS, _flush, args=(ip,))
    timer.daemon = True
    _timers[ip] = timer
    timer.start()


def record_knock(ip, port):
    with _lock:
        if port == SYNC_PORT:
            _flush_locked(ip)          # a new frame begins
            _bursts[ip] = [port]
        else:
            _bursts.setdefault(ip, []).append(port)
        _arm_timer_locked(ip)


def knock_listener(port):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((BIND, port))
    srv.listen(32)
    while True:
        try:
            conn, addr = srv.accept()
        except OSError:
            continue
        conn.close()
        record_knock(addr[0], port)


def token_ok(candidate):
    return bool(TOKEN) and hmac.compare_digest(candidate or "", TOKEN)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep the console quiet
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        qs = parse_qs(url.query)
        if url.path == "/health":
            self._json(200, {"ok": True, "ports": KNOCK_PORTS})
            return
        if url.path == "/inbox":
            if not token_ok(qs.get("token", [""])[0]):
                self._json(403, {"ok": False, "error": "bad token"})
                return
            box = (qs.get("box", [""])[0] or "").strip().lower()
            if not box:
                self._json(400, {"ok": False, "error": "box required"})
                return
            with _lock:
                frames = _mailboxes.pop(box, [])
                _last_seen[box] = time.time()
            self._json(200, {"ok": True, "frames": frames})
            return
        if url.path == "/presence":
            if not token_ok(qs.get("token", [""])[0]):
                self._json(403, {"ok": False, "error": "bad token"})
                return
            box = (qs.get("box", [""])[0] or "").strip().lower()
            if not box:
                self._json(400, {"ok": False, "error": "box required"})
                return
            with _lock:
                seen = _last_seen.get(box)
            self._json(200, {"ok": True, "box": box, "last_seen": seen})
            return
        self._json(404, {"ok": False, "error": "no such path"})

    def do_POST(self):
        url = urlparse(self.path)
        if url.path != "/declare":
            self._json(404, {"ok": False, "error": "no such path"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, json.JSONDecodeError):
            self._json(400, {"ok": False, "error": "bad json"})
            return
        if not token_ok(data.get("token", "")):
            self._json(403, {"ok": False, "error": "bad token"})
            return
        to_box = (data.get("to") or "").strip().lower()
        from_box = (data.get("from") or "").strip().lower()
        if not to_box or not from_box:
            self._json(400, {"ok": False,
                             "error": "from and to required"})
            return
        with _lock:
            _declares[self.client_address[0]] = (
                to_box, from_box, time.time() + DECLARE_TTL)
            _last_seen[from_box] = time.time()
        self._json(200, {"ok": True})


def main():
    if not TOKEN:
        raise SystemExit(
            "KNOCKTALK_TOKEN is not set — the mailbox API must be "
            "gated. Pick a long random string and put the same one "
            "in each phone's Knocktalk settings.")
    for port in KNOCK_PORTS:
        t = threading.Thread(target=knock_listener, args=(port,),
                             daemon=True)
        t.start()
    api = ThreadingHTTPServer((BIND, CONTROL_PORT), Handler)
    print(f"knocktalk relay: knock surface on {len(KNOCK_PORTS)} "
          f"ports, mailbox API on {BIND}:{CONTROL_PORT}")
    api.serve_forever()


if __name__ == "__main__":
    main()
