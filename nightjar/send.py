"""nightjar send / serve - give the listening post a mouth.

nightjar was receive-only by design: it never connects, never pairs,
never transmits. These two commands add the other direction, on
purpose, so the receive path keeps its promises.

    nightjar send tcp://10.0.0.5:9000 --payload "hello"
    nightjar send udp://10.0.0.5:9999 --payload-hex deadbeef
    nightjar send https://ntfy.sh/my-topic --method POST --payload "ping"
    nightjar send ble:// --payload "nj" --name nightjar-post
    nightjar send ble-gatt:// --payload "read me" --duration 60
    nightjar send AA:BB:CC:DD:EE:FF --char 2a19 --payload "x"
    nightjar serve --tcp 9000 --udp 9001 --reply "ack" --out rx.jsonl

Targets
    tcp://host:port            raw TCP; --read waits for a reply
    udp://host:port            one datagram; --read waits for one back
    tcp+tls://host:port        TLS-wrapped TCP
    http:// https://           urllib, any --method, --header repeatable
    ble://                     advertise: a BLE beacon carrying your payload
    ble-gatt://                a GATT server (peripheral) exposing the payload
    ble-write://ADDR|name:X    central: connect and write a characteristic
    AA:BB:CC:DD:EE:FF          a bare MAC is shorthand for ble-write

Payloads
    --payload TEXT   --payload-hex HEX   --payload-b64 B64
    --payload-file PATH   --stdin
    --xor KEY        XOR the bytes with KEY (hex or text)
    --gzip           gzip the bytes first

Dependencies
    Network sends are the standard library alone.
    ble-write uses bleak - which scanning already needs.
    ble:// and ble-gatt:// need the optional bless:
        pip install 'nightjar[tx]'
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import binascii
import contextlib
import gzip
import hashlib
import http.server
import json
import os
import socket
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

DEFAULT_COMPANY_ID = 0xFFFF
DEFAULT_SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb"
DEFAULT_CHAR_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"
DEFAULT_ADV_NAME = "nightjar"
FRAMINGS = ("raw", "len", "json")
METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD")


class SendError(RuntimeError):
    """A send or serve that could not be done, with a human reason."""


# --- payloads ----------------------------------------------------------------

@dataclass
class Payload:
    data: bytes
    encoding: str = "text"
    source: str = ""

    def __len__(self) -> int:
        return len(self.data)

    @property
    def hex(self) -> str:
        return self.data.hex()

    @property
    def b64(self) -> str:
        return base64.b64encode(self.data).decode("ascii")

    @property
    def sha1(self) -> str:
        return hashlib.sha1(self.data).hexdigest()


@dataclass
class SendResult:
    transport: str
    target: str
    sent: int
    reply: bytes = b""
    status: int | None = None
    note: str = ""

    def to_dict(self) -> dict:
        out: dict = {
            "transport": self.transport,
            "target": self.target,
            "sent": self.sent,
            "reply_bytes": len(self.reply),
        }
        if self.status is not None:
            out["status"] = self.status
        if self.reply:
            out["reply"] = self.reply.decode("utf-8", "replace")[:512]
            out["reply_b64"] = base64.b64encode(self.reply).decode("ascii")[:512]
        if self.note:
            out["note"] = self.note
        return out


def hexdump(data: bytes, width: int = 16, indent: str = "    ") -> str:
    if not data:
        return f"{indent}(empty)"
    lines = []
    for offset in range(0, len(data), width):
        chunk = data[offset:offset + width]
        hexes = " ".join(f"{b:02x}" for b in chunk)
        glyphs = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append(f"{indent}{offset:08x}  {hexes:<{width * 3}}  {glyphs}")
    return "\n".join(lines)


def _xor_key(spec: str) -> bytes:
    text = spec.strip()
    if text.lower().startswith("0x"):
        text = text[2:]
    compact = text.replace(":", "").replace(" ", "")
    if compact and len(compact) % 2 == 0 and all(
            c in "0123456789abcdefABCDEF" for c in compact):
        return binascii.unhexlify(compact)
    return spec.encode("utf-8")


def xor_bytes(data: bytes, key: bytes) -> bytes:
    if not key:
        return data
    return bytes(b ^ key[i % len(key)] for i, b in enumerate(data))


def _raw_source(args) -> tuple[str, str]:
    if getattr(args, "payload_hex", None) is not None:
        return "hex", args.payload_hex
    if getattr(args, "payload_b64", None) is not None:
        return "base64", args.payload_b64
    if getattr(args, "payload_file", None) is not None:
        return "file", args.payload_file
    if getattr(args, "payload", None) is not None:
        return "text", args.payload
    if getattr(args, "stdin", False) and not sys.stdin.isatty():
        return "text", sys.stdin.read()
    return "text", ""


def build_payload(args) -> Payload:
    kind, raw = _raw_source(args)
    try:
        if kind == "hex":
            compact = (raw.replace(":", "").replace(" ", "")
                       .replace("-", "").replace("\n", ""))
            data = binascii.unhexlify(compact)
        elif kind == "base64":
            data = base64.b64decode(raw, validate=False)
        elif kind == "file":
            with open(raw, "rb") as fh:
                data = fh.read()
        else:
            data = raw.encode("utf-8")
    except (binascii.Error, ValueError) as exc:
        raise SendError(f"could not decode {kind} payload: {exc}") from exc
    except OSError as exc:
        raise SendError(f"could not read payload file {raw!r}: {exc}") from exc

    if getattr(args, "xor", None):
        data = xor_bytes(data, _xor_key(args.xor))
    if getattr(args, "gzip", False):
        data = gzip.compress(data)
    return Payload(data=data, encoding=kind, source=raw)


def frame(data: bytes, framing: str, meta: dict | None = None) -> bytes:
    """Put the payload on the wire in the chosen shape."""
    if framing == "raw":
        return data
    if framing == "len":
        return len(data).to_bytes(4, "big") + data
    if framing == "json":
        envelope = {"ts": time.time(), "tool": "nightjar-send"}
        if meta:
            envelope.update(meta)
        envelope["encoding"] = "base64"
        envelope["payload"] = base64.b64encode(data).decode("ascii")
        return json.dumps(envelope).encode("utf-8")
    raise SendError(f"unknown framing {framing!r}")


def unframe(data: bytes, framing: str) -> bytes:
    if framing == "len" and len(data) >= 4:
        size = int.from_bytes(data[:4], "big")
        return data[4:4 + size]
    if framing == "json":
        with contextlib.suppress(Exception):
            obj = json.loads(data.decode("utf-8"))
            if isinstance(obj, dict) and obj.get("payload"):
                return base64.b64decode(obj["payload"])
    return data


# --- targets -----------------------------------------------------------------

def looks_like_mac(text: str) -> bool:
    parts = text.split(":")
    if len(parts) not in (6, 8):
        return False
    return all(len(p) == 2 and all(c in "0123456789abcdefABCDEF" for c in p)
               for p in parts)


@dataclass
class Target:
    scheme: str
    host: str | None = None
    port: int | None = None
    address: str | None = None
    tls: bool = False
    raw: str = ""


def parse_target(raw: str) -> Target:
    if "://" in raw:
        scheme, rest = raw.split("://", 1)
        scheme = scheme.lower()
    else:
        if looks_like_mac(raw):
            return Target("ble-write", address=raw.upper(), raw=raw)
        if raw.lower().startswith("name:"):
            return Target("ble-write", address=raw[5:], raw=raw)
        scheme, rest = "tcp", raw

    if scheme in ("http", "https"):
        return Target(scheme, host=rest, raw=raw)
    if scheme in ("ws", "wss"):
        return Target("ws", host=rest, tls=(scheme == "wss"), raw=raw)
    if scheme == "serial":
        device, _, query = rest.partition("?")
        if not device:
            raise SendError(f"serial:// needs a device, got {raw!r}")
        baud = 115200
        for pair in query.split("&"):
            key, _, value = pair.partition("=")
            if key == "baud" and value:
                try:
                    baud = int(value)
                except ValueError as exc:
                    raise SendError(f"bad baud in {raw!r}") from exc
        return Target("serial", address=device, port=baud, raw=raw)
    if scheme in ("ble", "adv", "advertise"):
        return Target("ble", raw=raw)
    if scheme in ("ble-gatt", "gatt", "peripheral"):
        return Target("ble-gatt", raw=raw)
    if scheme in ("ble-write", "gatt-write", "write"):
        if not rest:
            raise SendError(f"{scheme}:// needs an address or name:DEVICE")
        return Target("ble-write", address=rest, raw=raw)
    if scheme in ("tcp", "udp", "tls", "tcp+tls", "ssl"):
        host, sep, port = rest.rpartition(":")
        if not sep or not host:
            raise SendError(f"{scheme}:// target needs host:port, got {rest!r}")
        try:
            port_n = int(port)
        except ValueError as exc:
            raise SendError(f"bad port in {raw!r}") from exc
        use_tls = scheme in ("tls", "tcp+tls", "ssl")
        return Target("tcp" if use_tls else scheme, host=host, port=port_n,
                      tls=use_tls, raw=raw)
    raise SendError(f"unknown target scheme {scheme!r} in {raw!r}")


# --- network senders ---------------------------------------------------------

def send_tcp(target: Target, data: bytes, *, read: bool = False,
             timeout: float = 5.0) -> SendResult:
    if not target.host or not target.port:
        raise SendError("tcp needs host:port")
    with socket.create_connection((target.host, target.port), timeout=timeout) as sock:
        if target.tls:
            sock = ssl.create_default_context().wrap_socket(
                sock, server_hostname=target.host)
        sock.sendall(data)
        reply = b""
        if read:
            sock.settimeout(timeout)
            with contextlib.suppress(socket.timeout, OSError):
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    reply += chunk
    return SendResult("tcp", target.raw, len(data), reply)


def send_udp(target: Target, data: bytes, *, read: bool = False,
             timeout: float = 3.0) -> SendResult:
    if not target.host or not target.port:
        raise SendError("udp needs host:port")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(data, (target.host, target.port))
        reply = b""
        if read:
            with contextlib.suppress(socket.timeout, OSError):
                reply, _ = sock.recvfrom(65535)
    return SendResult("udp", target.raw, len(data), reply)


def send_http(target: Target, data: bytes, *, method: str = "POST",
              headers: dict | None = None, timeout: float = 10.0,
              framing: str = "raw", meta: dict | None = None) -> SendResult:
    method = method.upper()
    url = target.raw
    hdrs = dict(headers or {})
    body: bytes | None = None
    if method in ("GET", "HEAD"):
        if data:
            sep = "&" if "?" in url else "?"
            url = f"{url}{sep}payload=" + urllib.parse.quote(
                base64.b64encode(data).decode("ascii"))
    else:
        body = frame(data, framing, meta)
        hdrs.setdefault("Content-Type",
                        "application/json" if framing == "json"
                        else "application/octet-stream")
    hdrs.setdefault("User-Agent", "nightjar-send")

    request = urllib.request.Request(url, data=body, method=method, headers=hdrs)
    status: int | None = None
    reply = b""
    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            status = resp.status
            reply = b"" if method == "HEAD" else resp.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        reply = exc.read()
    except urllib.error.URLError as exc:
        raise SendError(f"http failed: {exc.reason}") from exc
    return SendResult("http", target.raw, len(body if body is not None else data),
                      reply, status=status)


# --- bluetooth senders -------------------------------------------------------

def _bleak():
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise SendError("BLE writes need bleak: pip install bleak") from exc
    return BleakClient, BleakScanner


def _bless():
    try:
        from bless import (BlessServer, GATTAttributePermissions,
                           GATTCharacteristicProperties)
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise SendError(
            "BLE broadcast and GATT server need bless: "
            "pip install 'nightjar[tx]'") from exc
    return BlessServer, GATTCharacteristicProperties, GATTAttributePermissions


def send_ble_write(target: Target, data: bytes, *, char_uuid: str,
                   timeout: float = 10.0) -> SendResult:
    """Central role: connect to a peripheral and write a characteristic."""
    BleakClient, BleakScanner = _bleak()
    address = (target.address or "").strip()
    if not address:
        raise SendError("ble-write needs an address or name:DEVICE")

    async def run() -> None:
        if looks_like_mac(address):
            client = BleakClient(address, timeout=timeout)
        else:
            device = await BleakScanner.find_device_by_name(address, timeout=timeout)
            if device is None:
                raise SendError(f"no BLE device named {address!r} in range")
            client = BleakClient(device, timeout=timeout)
        async with client:
            await client.write_gatt_char(char_uuid, data, response=False)

    asyncio.run(run())
    return SendResult("ble-write", address, len(data))


def _stamp_advertisement(server, name: str, data: bytes, company_id: int) -> None:
    """Best effort: also carry the payload where a passive scanner can see it.
    bless's advertisement surface moves between versions, so this is guarded."""
    with contextlib.suppress(Exception):
        adv = server.advertisement
        adv.local_name = name
        adv.manufacturer_data = {company_id: bytes(data[:24])}
        adv.service_data = {DEFAULT_SERVICE_UUID: bytes(data[:24])}


def run_ble_peripheral(data: bytes, *, service_uuid: str, char_uuid: str,
                       name: str, duration: float | None,
                       on_write: Callable[[bytes], None] | None = None,
                       company_id: int = DEFAULT_COMPANY_ID,
                       verbose: bool = True) -> SendResult:
    """Peripheral role: advertise a payload and serve it over GATT."""
    BlessServer, Props, Perms = _bless()
    holder = {"value": bytearray(data)}
    writes = {"count": 0}

    def read_request(characteristic):
        return holder["value"]

    def write_request(characteristic):
        value = bytes(characteristic.value or b"")
        holder["value"] = bytearray(value)
        writes["count"] += 1
        if on_write is not None:
            on_write(value)

    async def forever() -> None:
        await asyncio.Event().wait()

    async def serve() -> None:
        loop = asyncio.get_running_loop()
        server = BlessServer(name=name, loop=loop)
        server.read_request_func = read_request
        server.write_request_func = write_request
        await server.add_new_service(service_uuid)
        await server.add_new_characteristic(
            service_uuid, char_uuid,
            Props.read | Props.write | Props.notify,
            bytearray(data),
            Perms.readable | Perms.writeable)
        await server.start()
        _stamp_advertisement(server, name, data, company_id)
        if verbose:
            print(f"advertising as {name!r}: service {service_uuid}, "
                  f"characteristic {char_uuid}, {len(data)} byte payload",
                  file=sys.stderr, flush=True)
        if duration and duration > 0:
            with contextlib.suppress(asyncio.TimeoutError):
                await asyncio.wait_for(forever(), timeout=duration)
        else:
            await forever()
        await server.stop()

    try:
        asyncio.run(serve())
    except KeyboardInterrupt:
        pass
    return SendResult("ble", name, len(data),
                      note=f"{writes['count']} write(s) received")


# --- receivers ---------------------------------------------------------------

class Sink:
    """Where received payloads land: the console, a JSONL file, or both."""

    def __init__(self, *, out: str | None = None, as_json: bool = False,
                 reply: bytes = b"", quiet: bool = False,
                 reply_fn=None) -> None:
        self.out = out
        self.as_json = as_json
        self.reply = reply
        self.reply_fn = reply_fn  # callable(bytes) -> bytes, beats `reply`
        self.quiet = quiet
        self.count = 0
        self._lock = threading.Lock()

    def __call__(self, transport: str, peer: str, data: bytes) -> bytes:
        with self._lock:
            self.count += 1
            n = self.count
        stamp = time.strftime("%H:%M:%S")
        if self.as_json:
            print(json.dumps({
                "event": "payload", "ts": time.time(), "transport": transport,
                "peer": peer, "bytes": len(data),
                "payload_b64": base64.b64encode(data).decode("ascii")}), flush=True)
        elif not self.quiet:
            print(f"\n[{stamp}] {n}  {transport} <- {peer}  ({len(data)} bytes)",
                  flush=True)
            print(hexdump(data), flush=True)
            text = data.decode("utf-8", "replace")
            if text.strip() and text.isprintable():
                print(f"    text: {text[:400]}", flush=True)
        if self.out:
            with open(self.out, "a", encoding="utf-8") as fh:
                fh.write(json.dumps({
                    "ts": time.time(), "transport": transport, "peer": peer,
                    "bytes": len(data), "payload_hex": data.hex(),
                    "payload_b64": base64.b64encode(data).decode("ascii")}) + "\n")
        if self.reply_fn is not None:
            return self.reply_fn(data)
        return self.reply


def send_ws(target: Target, data: bytes, *, read: bool = False,
            timeout: float = 5.0) -> SendResult:
    """One WebSocket message (and optionally one reply message)."""
    try:
        from websockets.sync.client import connect as ws_connect
    except ImportError as exc:
        raise SendError("websocket sends need the websockets package: "
                        "pip install websockets (or the tx extra)") from exc
    scheme = "wss" if target.tls else "ws"
    uri = f"{scheme}://{target.host}"
    try:
        with ws_connect(uri, open_timeout=timeout) as conn:
            conn.send(data)
            reply = b""
            if read:
                got = conn.recv(timeout=timeout)
                reply = got.encode("utf-8") if isinstance(got, str) else got
            return SendResult(transport="ws", target=target.raw,
                              sent=len(data), reply=reply)
    except OSError:
        raise
    except Exception as exc:  # websockets raises a zoo of error types
        raise SendError(f"websocket to {uri}: {exc}") from exc


def _serial_port():
    try:
        import serial
    except ImportError as exc:
        raise SendError("serial transports need pyserial: "
                        "pip install pyserial (or the tx extra)") from exc
    return serial


def send_serial(target: Target, data: bytes, *, read: bool = False,
                timeout: float = 5.0) -> SendResult:
    serial = _serial_port()
    try:
        with serial.Serial(target.address, target.port or 115200,
                           timeout=timeout) as port:
            port.write(data)
            port.flush()
            reply = port.read(65536) if read else b""
            return SendResult(transport="serial", target=target.raw,
                              sent=len(data), reply=reply)
    except SendError:
        raise
    except Exception as exc:
        raise OSError(f"serial {target.address}: {exc}") from exc


def _tcp_conn(conn, addr, sink: Sink, framing: str) -> None:
    peer = f"{addr[0]}:{addr[1]}"
    with conn:
        conn.settimeout(2.0)
        buf = b""
        try:
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                buf += chunk
        except (socket.timeout, OSError):
            pass
        if not buf:
            return
        reply = sink("tcp", peer, unframe(buf, framing))
        if reply:
            with contextlib.suppress(OSError):
                conn.sendall(reply)


def serve_tcp(host: str, port: int, sink: Sink, *, framing: str = "raw",
              stop: threading.Event | None = None, banner: bool = True) -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(16)
    srv.settimeout(0.5)
    if banner:
        print(f"  tcp  listening on {host}:{port}", file=sys.stderr, flush=True)
    try:
        while not (stop and stop.is_set()):
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            threading.Thread(target=_tcp_conn, args=(conn, addr, sink, framing),
                             daemon=True).start()
    finally:
        srv.close()


def serve_udp(host: str, port: int, sink: Sink, *,
              stop: threading.Event | None = None, banner: bool = True) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((host, port))
    sock.settimeout(0.5)
    if banner:
        print(f"  udp  listening on {host}:{port}", file=sys.stderr, flush=True)
    try:
        while not (stop and stop.is_set()):
            try:
                data, addr = sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            reply = sink("udp", f"{addr[0]}:{addr[1]}", data)
            if reply:
                with contextlib.suppress(OSError):
                    sock.sendto(reply, addr)
    finally:
        sock.close()


def _make_http_handler(sink: Sink):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _handle(self, method: str) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else b""
            reply = sink("http", f"{self.client_address[0]}:{self.client_address[1]}",
                         body)
            payload = reply or b"ok\n"
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            if method != "HEAD":
                self.wfile.write(payload)

        def do_GET(self): self._handle("GET")
        def do_POST(self): self._handle("POST")
        def do_PUT(self): self._handle("PUT")
        def do_PATCH(self): self._handle("PATCH")
        def do_DELETE(self): self._handle("DELETE")
        def do_HEAD(self): self._handle("HEAD")

        def log_message(self, *args) -> None:
            return

    return Handler


def serve_http(host: str, port: int, sink: Sink, *,
               stop: threading.Event | None = None, banner: bool = True) -> None:
    httpd = http.server.ThreadingHTTPServer((host, port), _make_http_handler(sink))
    httpd.timeout = 0.5
    if banner:
        print(f"  http listening on http://{host}:{port}/", file=sys.stderr,
              flush=True)
    try:
        while not (stop and stop.is_set()):
            httpd.handle_request()
    finally:
        httpd.server_close()


def serve_ws(host: str, port: int, sink: Sink, *, framing: str = "raw",
             stop: threading.Event | None = None, banner: bool = True) -> None:
    try:
        from websockets.sync.server import serve as ws_serve
    except ImportError as exc:
        raise SendError("websocket serving needs the websockets package: "
                        "pip install websockets (or the tx extra)") from exc

    def handler(conn) -> None:
        peer = f"{conn.remote_address[0]}:{conn.remote_address[1]}"
        try:
            for message in conn:
                data = (message.encode("utf-8") if isinstance(message, str)
                        else message)
                reply = sink("ws", peer, unframe(data, framing))
                if reply:
                    conn.send(reply)
        except Exception:
            pass  # the peer went away mid-conversation; the sink has the data

    server = ws_serve(handler, host, port)
    if banner:
        print(f"  ws   listening on ws://{host}:{port}/", file=sys.stderr,
              flush=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        while not (stop and stop.is_set()):
            time.sleep(0.2)
    finally:
        server.shutdown()


def serve_serial(device: str, baud: int, sink: Sink, *,
                 stop: threading.Event | None = None,
                 banner: bool = True) -> None:
    serial = _serial_port()
    try:
        port = serial.Serial(device, baud, timeout=0.5)
    except Exception as exc:
        raise OSError(f"serial {device}: {exc}") from exc
    if banner:
        print(f"  serial listening on {device} @ {baud}", file=sys.stderr,
              flush=True)
    buffer = bytearray()
    try:
        while not (stop and stop.is_set()):
            chunk = port.read(4096)
            if chunk:
                buffer += chunk
                continue
            if buffer:
                # An idle gap ends the payload, like the TCP read timeout.
                reply = sink("serial", device, bytes(buffer))
                buffer = bytearray()
                if reply:
                    port.write(reply)
    finally:
        port.close()


def serve_relay_tcp(host: str, port: int, upstream: Target, sink: Sink, *,
                    stop: threading.Event | None = None,
                    banner: bool = True) -> None:
    """Listen, and relay every connection to an upstream TCP target,
    sinking both directions: a tap between a client and its server."""
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(16)
    srv.settimeout(0.5)
    if banner:
        print(f"  relay listening on {host}:{port} -> "
              f"{upstream.host}:{upstream.port}", file=sys.stderr, flush=True)
    try:
        while not (stop and stop.is_set()):
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue
            threading.Thread(target=_relay_conn, args=(conn, addr, upstream, sink),
                             daemon=True).start()
    finally:
        srv.close()


def _relay_conn(client, addr, upstream: Target, sink: Sink) -> None:
    peer = f"{addr[0]}:{addr[1]}"
    try:
        remote = socket.create_connection((upstream.host, upstream.port),
                                          timeout=10)
    except OSError:
        client.close()
        return

    def pump(source, dest, label: str) -> None:
        try:
            while True:
                data = source.recv(65536)
                if not data:
                    break
                sink(label, peer, data)
                dest.sendall(data)
        except OSError:
            pass
        finally:
            try:
                dest.shutdown(socket.SHUT_WR)
            except OSError:
                pass

    threads = [
        threading.Thread(target=pump, args=(client, remote, "relay-c2s"),
                         daemon=True),
        threading.Thread(target=pump, args=(remote, client, "relay-s2c"),
                         daemon=True),
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    client.close()
    remote.close()


# --- command entry points ----------------------------------------------------

def _headers(args) -> dict:
    headers: dict = {}
    for item in getattr(args, "header", None) or []:
        key, sep, value = item.partition(":")
        if not sep:
            raise SendError(f"--header needs 'Name: value', got {item!r}")
        headers[key.strip()] = value.strip()
    return headers


def _report(result: SendResult, count: int = 1) -> None:
    status = f" HTTP {result.status}" if result.status is not None else ""
    suffix = f"  [{count}]" if count > 1 else ""
    print(f"sent {result.sent} bytes over {result.transport} "
          f"to {result.target}{status}{suffix}")
    if result.reply:
        print(f"  <- {len(result.reply)} byte reply")
        print(hexdump(result.reply))
        text = result.reply.decode("utf-8", "replace")
        if text.strip() and text.isprintable():
            print(f"  text: {text[:400]}")
    if result.note:
        print(f"  note: {result.note}")


def do_send(target: Target, payload: Payload, args) -> SendResult:
    meta = {"encoding": payload.encoding, "source_len": len(payload)}
    if target.scheme == "tcp":
        return send_tcp(target, frame(payload.data, args.framing, meta),
                        read=args.read, timeout=args.timeout)
    if target.scheme == "udp":
        return send_udp(target, frame(payload.data, args.framing, meta),
                        read=args.read, timeout=args.timeout)
    if target.scheme in ("http", "https"):
        return send_http(target, payload.data, method=args.method,
                         headers=_headers(args), timeout=args.timeout,
                         framing=args.framing, meta=meta)
    if target.scheme == "ws":
        return send_ws(target, frame(payload.data, args.framing, meta),
                       read=args.read, timeout=args.timeout)
    if target.scheme == "serial":
        return send_serial(target, payload.data,
                           read=args.read, timeout=args.timeout)
    if target.scheme == "ble-write":
        return send_ble_write(target, payload.data, char_uuid=args.char,
                              timeout=args.timeout)
    raise SendError(f"nothing handles {target.scheme!r}")


def _send_ble_peripheral(target: Target, payload: Payload, args) -> int:
    def on_write(value: bytes) -> None:
        print(f"  <- {len(value)} byte write from a client", file=sys.stderr)
        print(hexdump(value), file=sys.stderr)

    try:
        result = run_ble_peripheral(
            payload.data, service_uuid=args.service, char_uuid=args.char,
            name=args.name, duration=args.duration, on_write=on_write,
            company_id=args.company_id)
    except SendError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result.to_dict()), flush=True)
    else:
        _report(result)
    return 0


def _expected_bytes(args) -> bytes | None:
    if getattr(args, "expect_hex", None):
        try:
            return bytes.fromhex(args.expect_hex.replace(":", "").replace(" ", ""))
        except ValueError as exc:
            raise SendError(f"bad --expect-hex: {exc}") from exc
    if getattr(args, "expect", None):
        return args.expect.encode("utf-8")
    return None


def _send_loop(target: Target, payload: Payload, args) -> int:
    expected = _expected_bytes(args)
    repeats = max(0, args.repeat)
    started = time.time()
    count = 0
    total = 0
    while True:
        count += 1
        try:
            result = do_send(target, payload, args)
        except SendError as exc:
            print(f"nightjar: send failed: {exc}", file=sys.stderr)
            return 1
        total += result.sent
        if args.json:
            print(json.dumps(result.to_dict()), flush=True)
        else:
            _report(result, count)
        if expected is not None:
            if expected in (result.reply or b""):
                if not args.json:
                    print("  expect: ok")
            else:
                print("nightjar: reply did not contain the expected bytes",
                      file=sys.stderr)
                return 1
        if repeats and count >= repeats:
            break
        if args.duration and (time.time() - started) >= args.duration:
            break
        if not repeats and not args.duration:
            break
        time.sleep(max(0.0, args.interval))
    if not args.json and count > 1:
        print(f"{count} payload(s), {total} bytes to {target.raw}")
    return 0


def _follow_loop(target: Target, path: str, args) -> int:
    """Send a file's contents every time the file changes."""
    print(f"nightjar send: watching {path} - Ctrl-C to stop.",
          file=sys.stderr, flush=True)
    last_mtime: float | None = None
    started = time.time()
    sent = 0
    try:
        while True:
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                mtime = None
            if mtime is not None and mtime != last_mtime:
                last_mtime = mtime
                shot = argparse.Namespace(**vars(args))
                shot.payload_file = path
                shot.payload = shot.payload_hex = shot.payload_b64 = None
                shot.duration = None  # one shot per change, not a burst
                shot.repeat = 0
                try:
                    code = _send_loop(target, build_payload(shot), shot)
                except SendError as exc:
                    print(f"nightjar: {exc}", file=sys.stderr)
                    code = 2
                if code != 0:
                    return code
                sent += 1
            if args.duration and (time.time() - started) >= args.duration:
                break
            time.sleep(max(0.05, min(args.interval, 0.5)))
    except KeyboardInterrupt:
        pass
    print(f"{sent} payload(s) sent from {path}")
    return 0


def _replay(target: Target, path: str, args) -> int:
    """Re-send a serve --out recording, with its timing (scaled)."""
    records: list[tuple[float, bytes]] = []
    try:
        lines = Path(path).read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        print(f"nightjar: cannot read replay file: {exc}", file=sys.stderr)
        return 2
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
            if record.get("payload_b64"):
                data = base64.b64decode(record["payload_b64"])
            elif record.get("payload_hex"):
                data = bytes.fromhex(record["payload_hex"])
            elif record.get("payload"):
                data = base64.b64decode(record["payload"])
            else:
                continue
        except (ValueError, KeyError):
            continue
        records.append((float(record.get("ts") or 0), data))
    if not records:
        print(f"nightjar: no payloads found in {path}", file=sys.stderr)
        return 2
    speed = getattr(args, "speed", 1.0) or 0
    previous: float | None = None
    try:
        for stamp, data in records:
            if previous is not None and speed > 0:
                gap = min(10.0, max(0.0, stamp - previous) / speed)
                if gap:
                    time.sleep(gap)
            previous = stamp
            payload = Payload(data=data, encoding="replay", source=path)
            shot = argparse.Namespace(**vars(args))
            shot.duration = None  # one shot per record, not a burst
            shot.repeat = 0
            code = _send_loop(target, payload, shot)
            if code != 0:
                return code
    except KeyboardInterrupt:
        pass
    print(f"replayed {len(records)} payload(s) from {path}")
    return 0


def cmd_send(args) -> int:
    raw_targets = args.target if isinstance(args.target, list) else [args.target]
    raws: list[str] = []
    for item in raw_targets:
        raws.extend(part for part in (p.strip() for p in item.split(",")) if part)
    try:
        targets = [parse_target(raw) for raw in raws]
    except SendError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 2
    if getattr(args, "expect", None) or getattr(args, "expect_hex", None):
        args.read = True

    single = len(targets) == 1
    try:
        payload = None if (args.replay or getattr(args, "follow", None)) \
            else build_payload(args)
    except SendError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 2

    worst = 0
    for target in targets:
        try:
            if args.replay:
                code = _replay(target, args.replay, args)
            elif args.dry_run:
                print(json.dumps({
                    "target": target.raw, "scheme": target.scheme,
                    "bytes": len(payload), "encoding": payload.encoding,
                    "sha1": payload.sha1, "framing": args.framing}, indent=2))
                print(hexdump(payload.data))
                code = 0
            elif getattr(args, "follow", None):
                if not single:
                    print("nightjar: --follow takes exactly one target",
                          file=sys.stderr)
                    return 2
                code = _follow_loop(target, args.follow, args)
            elif target.scheme in ("ble", "ble-gatt"):
                if not single:
                    print("nightjar: BLE targets cannot be fanned out",
                          file=sys.stderr)
                    return 2
                code = _send_ble_peripheral(target, payload, args)
            else:
                code = _send_loop(target, payload, args)
        except (SendError, OSError) as exc:
            print(f"nightjar: {exc}", file=sys.stderr)
            code = 2
        worst = max(worst, code)
        if code == 2 and not single:
            continue
    return worst


def cmd_serve(args) -> int:
    reply_fn = None
    mode = getattr(args, "reply_mode", "static")
    if mode == "echo":
        reply_fn = lambda data: data  # noqa: E731 - a responder, not a helper
    elif mode == "file":
        if not getattr(args, "reply_file", None):
            print("nightjar: --reply-mode file needs --reply-file",
                  file=sys.stderr)
            return 2
        try:
            blob = Path(args.reply_file).read_bytes()
        except OSError as exc:
            print(f"nightjar: cannot read reply file: {exc}", file=sys.stderr)
            return 2
        reply_fn = lambda data, blob=blob: blob  # noqa: E731
    sink = Sink(out=args.out, as_json=args.json,
                reply=(args.reply or "").encode("utf-8"), quiet=args.quiet,
                reply_fn=reply_fn)
    stop = threading.Event()
    threads: list[threading.Thread] = []
    started: list[str] = []
    errors: list[str] = []

    def spawn(fn, *fn_args, **fn_kwargs) -> None:
        def runner() -> None:
            try:
                fn(*fn_args, **{**fn_kwargs, "stop": stop})
            except (OSError, SendError) as exc:
                errors.append(f"{fn.__name__}: {exc}")
                stop.set()
        threads.append(threading.Thread(target=runner, daemon=True))

    relay_upstream = None
    if getattr(args, "relay", None):
        try:
            relay_upstream = parse_target(args.relay)
        except SendError as exc:
            print(f"nightjar: {exc}", file=sys.stderr)
            return 2
        if relay_upstream.scheme != "tcp":
            print("nightjar: --relay target must be tcp://", file=sys.stderr)
            return 2
        if args.tcp is None:
            print("nightjar: --relay needs --tcp PORT to listen on",
                  file=sys.stderr)
            return 2
    if (args.tcp is None and args.udp is None and args.http is None
            and not args.ble and getattr(args, "ws", None) is None
            and not getattr(args, "serial", None)):
        args.tcp = 9000
    if args.tcp is not None and relay_upstream is not None:
        spawn(serve_relay_tcp, args.host, args.tcp, relay_upstream, sink)
        started.append(
            f"relay tcp://{args.host}:{args.tcp} -> {relay_upstream.raw}")
    elif args.tcp is not None:
        spawn(serve_tcp, args.host, args.tcp, sink, framing=args.framing)
        started.append(f"tcp://{args.host}:{args.tcp}")
    if args.udp is not None:
        spawn(serve_udp, args.host, args.udp, sink)
        started.append(f"udp://{args.host}:{args.udp}")
    if args.http is not None:
        spawn(serve_http, args.host, args.http, sink)
        started.append(f"http://{args.host}:{args.http}/")
    if getattr(args, "ws", None) is not None:
        spawn(serve_ws, args.host, args.ws, sink, framing=args.framing)
        started.append(f"ws://{args.host}:{args.ws}")
    if getattr(args, "serial", None):
        spawn(serve_serial, args.serial, args.baud, sink)
        started.append(f"serial://{args.serial}")
    if args.ble:
        started.append("ble-gatt")

    for thread in threads:
        thread.start()
    time.sleep(0.15)
    if not args.json and not errors:
        print(f"nightjar serve: {', '.join(started)} - Ctrl-C to stop.",
              file=sys.stderr, flush=True)

    def on_write(value: bytes) -> None:
        sink("ble", "central", value)

    try:
        if args.ble:
            try:
                run_ble_peripheral(
                    b"", service_uuid=args.service, char_uuid=args.char,
                    name=args.name, duration=args.duration, on_write=on_write)
            except SendError as exc:
                print(f"nightjar: {exc}", file=sys.stderr)
                return 1
        elif args.duration:
            deadline = time.time() + args.duration
            while time.time() < deadline and not stop.is_set():
                time.sleep(0.2)
        else:
            while not stop.is_set():
                time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        # A connection handler sinks its payload only once the read ends
        # (EOF or its 2s timeout), so give in-flight handlers a grace
        # window to finish instead of exiting from under them.
        grace_deadline = time.time() + 2.5
        while time.time() < grace_deadline:
            if not any(t is not threading.current_thread() and t.is_alive()
                       and t not in threads for t in threading.enumerate()):
                break
            time.sleep(0.1)
    if errors:
        print(f"nightjar: {errors[0]}", file=sys.stderr)
        return 2
    if not args.json:
        print(f"\nreceived {sink.count} payload(s).")
        if args.out:
            print(f"appended to {args.out}")
    return 0


# --- argparse ----------------------------------------------------------------

def add_send_args(parser) -> None:
    parser.add_argument(
        "target", metavar="TARGET", nargs="+",
        help="tcp://host:port, udp://host:port, tcp+tls://host:port, "
             "http(s)://url, ws(s)://url, serial://DEVICE?baud=N, ble://, "
             "ble-gatt://, ble-write://ADDR, a bare MAC, or name:DEVICE; "
             "several targets (space or comma separated) fan the payload out")
    src = parser.add_argument_group("payload")
    src.add_argument("--payload", metavar="TEXT", help="payload as text")
    src.add_argument("--payload-hex", metavar="HEX", help="payload as hex bytes")
    src.add_argument("--payload-b64", metavar="B64", help="payload as base64")
    src.add_argument("--payload-file", metavar="PATH", help="payload read from a file")
    src.add_argument("--stdin", action="store_true", help="payload read from stdin")
    src.add_argument("--xor", metavar="KEY",
                     help="XOR the payload with KEY (hex, or text as utf-8)")
    src.add_argument("--gzip", action="store_true", help="gzip the payload first")

    net = parser.add_argument_group("network")
    net.add_argument("--framing", choices=FRAMINGS, default="raw",
                     help="wire shape: raw, len (4-byte big-endian length), "
                          "json (base64 envelope)")
    net.add_argument("--method", choices=METHODS, default="POST",
                     help="HTTP method (default POST)")
    net.add_argument("--header", action="append", metavar="NAME:VALUE",
                     help="HTTP header; repeatable")
    net.add_argument("--read", action="store_true",
                     help="wait for a reply (tcp/udp)")
    net.add_argument("--expect", metavar="TEXT",
                     help="fail (exit 1) unless the reply contains TEXT; "
                          "implies --read")
    net.add_argument("--expect-hex", metavar="HEX",
                     help="like --expect, with the needle as hex bytes")
    net.add_argument("--timeout", type=float, default=5.0, metavar="SECONDS")

    ble = parser.add_argument_group("bluetooth")
    ble.add_argument("--name", default=DEFAULT_ADV_NAME,
                     help="BLE advertised local name")
    ble.add_argument("--service", default=DEFAULT_SERVICE_UUID, metavar="UUID")
    ble.add_argument("--char", default=DEFAULT_CHAR_UUID, metavar="UUID",
                     help="characteristic to write or expose")
    ble.add_argument("--company-id", type=lambda s: int(s, 0),
                     default=DEFAULT_COMPANY_ID, metavar="N")

    loop = parser.add_argument_group("repeat")
    loop.add_argument("--repeat", type=int, default=0, metavar="N",
                      help="send N times (0 = once, unless --duration is given)")
    loop.add_argument("--interval", type=float, default=1.0, metavar="SECONDS")
    loop.add_argument("--duration", type=float, default=None, metavar="SECONDS",
                      help="keep going for SECONDS (0 or unset = once / until Ctrl-C)")
    loop.add_argument("--follow", metavar="FILE",
                      help="send FILE's contents every time FILE changes")
    loop.add_argument("--replay", metavar="FILE",
                      help="re-send a serve --out recording, with its timing")
    loop.add_argument("--speed", type=float, default=1.0, metavar="X",
                      help="replay speed multiplier (0 = as fast as possible)")

    parser.add_argument("--dry-run", action="store_true",
                        help="show the payload and target, send nothing")
    parser.add_argument("--json", action="store_true",
                        help="one JSON object per result")


def add_serve_args(parser) -> None:
    parser.add_argument("--host", default="0.0.0.0",
                        help="interface to bind (default 0.0.0.0)")
    parser.add_argument("--tcp", type=int, default=None, metavar="PORT")
    parser.add_argument("--udp", type=int, default=None, metavar="PORT")
    parser.add_argument("--http", type=int, default=None, metavar="PORT")
    parser.add_argument("--ws", type=int, default=None, metavar="PORT",
                        help="WebSocket listener (needs websockets)")
    parser.add_argument("--serial", metavar="DEVICE",
                        help="serial listener on DEVICE (needs pyserial)")
    parser.add_argument("--baud", type=int, default=115200, metavar="N")
    parser.add_argument("--relay", metavar="TARGET",
                        help="relay the --tcp listener to an upstream "
                             "tcp:// target, logging both directions")
    parser.add_argument("--ble", action="store_true",
                        help="also accept BLE GATT writes (needs bless)")
    parser.add_argument("--name", default=DEFAULT_ADV_NAME)
    parser.add_argument("--service", default=DEFAULT_SERVICE_UUID, metavar="UUID")
    parser.add_argument("--char", default=DEFAULT_CHAR_UUID, metavar="UUID")
    parser.add_argument("--framing", choices=FRAMINGS, default="raw",
                        help="how tcp payloads are framed")
    parser.add_argument("--reply", metavar="TEXT",
                        help="answer every payload with TEXT")
    parser.add_argument("--reply-mode", choices=("static", "echo", "file"),
                        default="static",
                        help="static: --reply text; echo: the payload itself; "
                             "file: the contents of --reply-file")
    parser.add_argument("--reply-file", metavar="FILE",
                        help="reply source for --reply-mode file")
    parser.add_argument("--out", metavar="FILE",
                        help="append every payload to FILE as JSON lines")
    parser.add_argument("--duration", type=float, default=None, metavar="SECONDS")
    parser.add_argument("--quiet", action="store_true", help="no hexdump")
    parser.add_argument("--json", action="store_true",
                        help="one JSON object per payload")


__all__ = [
    "Payload", "SendResult", "SendError", "Target", "Sink",
    "build_payload", "parse_target", "frame", "unframe", "hexdump",
    "add_send_args", "add_serve_args", "cmd_send", "cmd_serve",
    "run_ble_peripheral", "send_ble_write", "send_http", "send_tcp", "send_udp",
    "send_ws", "send_serial", "serve_ws", "serve_serial", "serve_relay_tcp",
]
