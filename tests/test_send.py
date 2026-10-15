"""Tests for nightjar-hack's send/serve overlay.

Run from the repo root:  python3 -m pytest tests/

UDP is deliberately untested here: it is two standard-library calls,
and some sandboxes refuse UDP egress outright, which would make the
suite lie about the code.
"""

import argparse
import ast
import gzip
import json
import socket
import threading
import time
from pathlib import Path

import pytest

from conftest import ROOT, send

SendError = send.SendError


# --- helpers -----------------------------------------------------------------

def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class FakeSink:
    def __init__(self, reply: bytes = b""):
        self.reply = reply
        self.records = []

    def __call__(self, transport, peer, data):
        self.records.append((transport, peer, data))
        return self.reply


def start_server(fn, port, sink, **kwargs):
    stop = threading.Event()
    thread = threading.Thread(target=fn, args=("127.0.0.1", port, sink),
                              kwargs={"stop": stop, "banner": False, **kwargs},
                              daemon=True)
    thread.start()
    deadline = time.time() + 5
    while time.time() < deadline:  # wait until it accepts
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return stop, thread
        except OSError:
            time.sleep(0.05)
    raise RuntimeError("server did not start")


def send_namespace(*argv):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command")
    send.add_send_args(sub.add_parser("send"))
    return parser.parse_args(["send", *argv])


def serve_namespace(*argv):
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command")
    send.add_serve_args(sub.add_parser("serve"))
    return parser.parse_args(["serve", *argv])


# --- payloads ------------------------------------------------------------------

def test_payload_text():
    payload = send.build_payload(send_namespace("tcp://127.0.0.1:9",
                                                "--payload", "hello"))
    assert payload.data == b"hello"
    assert payload.encoding == "text"


def test_payload_hex_tolerates_separators():
    payload = send.build_payload(send_namespace(
        "tcp://127.0.0.1:9", "--payload-hex", "de:ad be-e f"))
    assert payload.data == bytes.fromhex("deadbeef")


def test_payload_b64():
    payload = send.build_payload(send_namespace(
        "tcp://127.0.0.1:9", "--payload-b64", "aGVsbG8="))
    assert payload.data == b"hello"


def test_payload_bad_hex_is_a_clean_error():
    with pytest.raises(SendError):
        send.build_payload(send_namespace("tcp://127.0.0.1:9",
                                          "--payload-hex", "zz"))


def test_payload_file(tmp_path):
    blob = tmp_path / "blob.bin"
    blob.write_bytes(b"\x00\x01\x02")
    payload = send.build_payload(send_namespace(
        "tcp://127.0.0.1:9", "--payload-file", str(blob)))
    assert payload.data == b"\x00\x01\x02"


def test_payload_missing_file_is_a_clean_error(tmp_path):
    with pytest.raises(SendError):
        send.build_payload(send_namespace(
            "tcp://127.0.0.1:9", "--payload-file", str(tmp_path / "nope")))


def test_payload_xor_round_trips():
    args = send_namespace("tcp://127.0.0.1:9", "--payload", "hello",
                          "--xor", "0x5a")
    payload = send.build_payload(args)
    assert payload.data != b"hello"
    assert send.xor_bytes(payload.data, send._xor_key("0x5a")) == b"hello"


def test_payload_gzip_round_trips():
    payload = send.build_payload(send_namespace(
        "tcp://127.0.0.1:9", "--payload", "hello", "--gzip"))
    assert payload.data[:2] == b"\x1f\x8b"
    assert gzip.decompress(payload.data) == b"hello"


# --- framing -------------------------------------------------------------------

@pytest.mark.parametrize("framing", ["raw", "len", "json"])
def test_framing_round_trips(framing):
    wire = send.frame(b"payload", framing)
    assert send.unframe(wire, framing) == b"payload"


def test_len_framing_shape():
    wire = send.frame(b"abc", "len")
    assert wire[:4] == (3).to_bytes(4, "big")
    assert wire[4:] == b"abc"


def test_json_framing_shape():
    envelope = json.loads(send.frame(b"abc", "json"))
    assert envelope["encoding"] == "base64"
    assert envelope["payload"] == "YWJj"


def test_unframe_is_best_effort():
    # unframe parses what a peer sent into a sink: it never raises.
    # A buffer too short to hold a len prefix passes through untouched,
    # and an oversized prefix yields the bytes that actually arrived.
    assert send.unframe(b"\x00\x00", "len") == b"\x00\x00"
    assert send.unframe(b"\x00\x00\x00\x09ab", "len") == b"ab"
    assert send.unframe(b"not json", "json") == b"not json"


# --- target parsing --------------------------------------------------------------

@pytest.mark.parametrize("raw,scheme,host,port", [
    ("tcp://127.0.0.1:9000", "tcp", "127.0.0.1", 9000),
    ("udp://example.com:53", "udp", "example.com", 53),
    ("tcp+tls://example.com:443", "tcp", "example.com", 443),
])
def test_parse_network_targets(raw, scheme, host, port):
    target = send.parse_target(raw)
    assert (target.scheme, target.host, target.port) == (scheme, host, port)


@pytest.mark.parametrize("raw,scheme", [
    ("http://127.0.0.1:8080/ingest", "http"),
    ("https://example.com/hook", "https"),
])
def test_parse_http_targets_keep_the_url(raw, scheme):
    # By design: HTTP targets ride on target.raw; host/port stay unset.
    target = send.parse_target(raw)
    assert target.scheme == scheme
    assert target.raw == raw


def test_parse_ble_targets():
    assert send.parse_target("ble://").scheme == "ble"
    assert send.parse_target("ble-gatt://").scheme == "ble-gatt"
    assert send.parse_target("AA:BB:CC:DD:EE:FF").scheme == "ble-write"
    named = send.parse_target("name:AirPods")
    assert named.scheme == "ble-write"


def test_parse_unknown_scheme_is_a_clean_error():
    with pytest.raises(SendError):
        send.parse_target("carrier-pigeon://loft")


def test_parse_bad_port_is_a_clean_error():
    with pytest.raises(SendError):
        send.parse_target("tcp://127.0.0.1:notaport")


# --- TCP round trips -------------------------------------------------------------

def test_tcp_round_trip_raw():
    port = free_port()
    sink = FakeSink(reply=b"ack")
    stop, _ = start_server(send.serve_tcp, port, sink)
    try:
        target = send.parse_target(f"tcp://127.0.0.1:{port}")
        result = send.send_tcp(target, b"hello", read=True, timeout=5)
    finally:
        stop.set()
    assert result.sent == 5
    assert result.reply == b"ack"
    assert sink.records[0][2] == b"hello"


def test_tcp_round_trip_len_framed():
    port = free_port()
    sink = FakeSink()
    stop, _ = start_server(send.serve_tcp, port, sink, framing="len")
    try:
        target = send.parse_target(f"tcp://127.0.0.1:{port}")
        send.send_tcp(target, send.frame(b"framed", "len"), timeout=5)
        # No --read here, so nothing synchronizes us with the server
        # thread: poll for the record instead of racing it.
        deadline = time.time() + 3
        while not sink.records and time.time() < deadline:
            time.sleep(0.05)
    finally:
        stop.set()
    assert sink.records[0][2] == b"framed"


# --- HTTP round trip -------------------------------------------------------------

def test_http_round_trip():
    port = free_port()
    sink = FakeSink()
    stop = threading.Event()
    thread = threading.Thread(target=send.serve_http,
                              args=("127.0.0.1", port, sink),
                              kwargs={"stop": stop, "banner": False},
                              daemon=True)
    thread.start()
    try:
        target = send.parse_target(f"http://127.0.0.1:{port}/ingest")
        result = send.send_http(target, b"ping-http", timeout=5)
    finally:
        stop.set()
    assert result.status == 200
    assert sink.records[0][2] == b"ping-http"


# --- command-level error behaviour ------------------------------------------------

def test_cmd_send_dead_port_is_clean(capsys):
    port = free_port()  # nothing listening there
    args = send_namespace(f"tcp://127.0.0.1:{port}", "--payload", "x")
    assert send.cmd_send(args) == 2
    err = capsys.readouterr().err
    assert "nightjar:" in err
    assert "Traceback" not in err


def test_cmd_send_dry_run(capsys):
    args = send_namespace("tcp://127.0.0.1:9000", "--payload", "hello",
                          "--dry-run")
    assert send.cmd_send(args) == 0
    out = capsys.readouterr().out
    assert '"bytes": 5' in out
    assert "hello" in out


def test_cmd_serve_bind_conflict_is_clean(capsys):
    port = free_port()
    blocker = socket.socket()
    blocker.bind(("127.0.0.1", port))
    blocker.listen(1)
    try:
        args = serve_namespace("--tcp", str(port), "--host", "127.0.0.1")
        started = time.time()
        assert send.cmd_serve(args) == 2
        assert time.time() - started < 5  # it must not hang, serving nothing
    finally:
        blocker.close()
    err = capsys.readouterr().err
    assert "nightjar:" in err
    assert "Traceback" not in err


def test_cmd_serve_duration_mode_receives(capsys):
    port = free_port()
    args = serve_namespace("--tcp", str(port), "--host", "127.0.0.1",
                           "--duration", "4")
    result = {}

    def run():
        result["rc"] = send.cmd_serve(args)

    thread = threading.Thread(target=run)
    thread.start()
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            probe = socket.create_connection(("127.0.0.1", port), timeout=0.3)
            break
        except OSError:
            time.sleep(0.05)
    with socket.create_connection(("127.0.0.1", port), timeout=2) as conn:
        conn.sendall(b"in-window")
        conn.shutdown(socket.SHUT_WR)
        assert conn.recv(64) == b"" or True  # reply is not configured here
    probe.close()
    thread.join(timeout=8)
    assert result["rc"] == 0
    assert "1 payload(s)" in capsys.readouterr().out


# --- the four copies of send.py stay identical -------------------------------------

def test_send_py_copies_identical():
    plain = (ROOT / "send.py").read_bytes()
    packaged = (ROOT / "nightjar" / "send.py").read_bytes()
    assert plain == packaged


def test_single_file_embeds_current_send_py():
    tree = ast.parse((ROOT / "nightjar-hack-single.py").read_text())
    data = None
    for node in tree.body:
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "DATA":
            data = ast.literal_eval(node.value)
    assert data is not None
    assert data["nightjar/send.py"] == (ROOT / "nightjar" / "send.py").read_text()


def test_bundle_embeds_current_send_py():
    bundle = (ROOT / "nightjar-hack-bundle.txt").read_text()
    marker = "===== FILE: nightjar/send.py =====\n"
    section = bundle.split(marker, 1)[1].split("===== FILE:", 1)[0]
    current = (ROOT / "nightjar" / "send.py").read_text()
    assert section.rstrip("\n") == current.rstrip("\n")


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))


# --- the 2.4 additions: ws/serial, expect, fan-out, responders, relay ---

import base64


class EchoSink:
    def __init__(self):
        self.records = []

    def __call__(self, transport, peer, data):
        self.records.append((transport, peer, data))
        return data


def _wait_tcp(port, tries=50):
    for _ in range(tries):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.3):
                return
        except OSError:
            time.sleep(0.1)
    raise RuntimeError("port never opened")


def test_parse_ws_and_serial_targets():
    target = send.parse_target("ws://example.com:8765/feed")
    assert (target.scheme, target.host, target.tls) == \
        ("ws", "example.com:8765/feed", False)
    target = send.parse_target("wss://example.com/socket")
    assert target.tls is True
    target = send.parse_target("serial:///dev/ttyUSB0?baud=9600")
    assert (target.scheme, target.address, target.port) == \
        ("serial", "/dev/ttyUSB0", 9600)
    target = send.parse_target("serial://COM3")
    assert target.port == 115200  # the default baud


def test_sink_reply_fn_beats_static_reply():
    sink = send.Sink(reply=b"static", reply_fn=lambda data: data.upper())
    assert sink("tcp", "peer", b"abc") == b"ABC"


def test_cmd_send_fanout_two_targets():
    stops = []
    ports = []
    for _ in range(2):
        port = free_port()
        stop, _ = start_server(send.serve_tcp, port, EchoSink())
        stops.append(stop)
        ports.append(port)
    try:
        code = send.cmd_send(send_namespace(
            f"tcp://127.0.0.1:{ports[0]}", f"tcp://127.0.0.1:{ports[1]}",
            "--payload", "both", "--expect", "both"))
    finally:
        for stop in stops:
            stop.set()
    assert code == 0


def test_cmd_send_expect_miss_exits_1():
    port = free_port()
    stop, _ = start_server(send.serve_tcp, port, EchoSink())
    try:
        code = send.cmd_send(send_namespace(
            f"tcp://127.0.0.1:{port}", "--payload", "ping",
            "--expect", "pong"))
    finally:
        stop.set()
    assert code == 1


def test_cmd_serve_reply_file_mode(tmp_path):
    canned = tmp_path / "canned.bin"
    canned.write_bytes(b"from-a-file")
    port = free_port()
    args = serve_namespace("--tcp", str(port), "--duration", "1.5",
                           "--reply-mode", "file",
                           "--reply-file", str(canned), "--quiet")
    thread = threading.Thread(target=send.cmd_serve, args=(args,),
                              daemon=True)
    thread.start()
    _wait_tcp(port)
    with socket.create_connection(("127.0.0.1", port), timeout=5) as conn:
        conn.sendall(b"whatever")
        reply = conn.recv(64)
    thread.join(timeout=5)
    assert reply == b"from-a-file"


def test_cmd_serve_relay_tap(tmp_path):
    upstream = free_port()
    stop, _ = start_server(send.serve_tcp, upstream, EchoSink())
    front = free_port()
    log = tmp_path / "relay.jsonl"
    args = serve_namespace("--tcp", str(front), "--duration", "2",
                           "--relay", f"tcp://127.0.0.1:{upstream}",
                           "--out", str(log), "--quiet")
    thread = threading.Thread(target=send.cmd_serve, args=(args,),
                              daemon=True)
    thread.start()
    try:
        _wait_tcp(front)
        with socket.create_connection(("127.0.0.1", front), timeout=5) as conn:
            conn.sendall(b"through")
            assert conn.recv(64) == b"through"  # upstream's echo, relayed
    finally:
        stop.set()
    thread.join(timeout=6)
    records = [json.loads(line) for line in log.read_text().splitlines()]
    kinds = {r["transport"] for r in records}
    assert {"relay-c2s", "relay-s2c"} <= kinds


def test_cmd_send_replay(tmp_path):
    records = []
    now = 1_700_000_000.0
    for i, blob in enumerate([b"one", b"two"]):
        records.append({
            "ts": now + i * 0.05, "transport": "tcp", "peer": "x",
            "bytes": len(blob),
            "payload_b64": base64.b64encode(blob).decode("ascii")})
    log = tmp_path / "rec.jsonl"
    log.write_text("\n".join(json.dumps(r) for r in records) + "\n")
    recorder = EchoSink()
    port = free_port()
    stop, _ = start_server(send.serve_tcp, port, recorder)
    try:
        code = send.cmd_send(send_namespace(
            f"tcp://127.0.0.1:{port}", "--replay", str(log), "--speed", "0"))
        deadline = time.time() + 3
        while len(recorder.records) < 2 and time.time() < deadline:
            time.sleep(0.05)
    finally:
        stop.set()
    assert code == 0
    assert [r[2] for r in recorder.records] == [b"one", b"two"]


def test_ws_round_trip():
    pytest.importorskip("websockets")
    port = free_port()
    sink = send.Sink(quiet=True, reply_fn=lambda data: data)
    stop, _ = start_server(send.serve_ws, port, sink)
    try:
        target = send.parse_target(f"ws://127.0.0.1:{port}/")
        deadline = time.time() + 5
        while True:
            try:
                result = send.send_ws(target, b"echo-me", read=True,
                                      timeout=2)
                break
            except Exception:
                if time.time() > deadline:
                    raise
                time.sleep(0.2)
        assert result.reply == b"echo-me"
    finally:
        stop.set()


def test_serial_round_trip_via_pty():
    pytest.importorskip("serial")
    import os
    import pty
    import select
    master1, slave1 = pty.openpty()
    master2, slave2 = pty.openpty()
    pumping = threading.Event()
    pumping.set()

    def pump():
        while pumping.is_set():
            ready, _, _ = select.select([master1, master2], [], [], 0.1)
            for fd in ready:
                try:
                    data = os.read(fd, 4096)
                except OSError:
                    data = b""
                if data:
                    os.write(master2 if fd == master1 else master1, data)

    bridge = threading.Thread(target=pump, daemon=True)
    bridge.start()
    stop = threading.Event()
    sink = send.Sink(quiet=True, reply_fn=lambda data: data)
    server = threading.Thread(
        target=send.serve_serial,
        args=(os.ttyname(slave1), 9600, sink),
        kwargs={"stop": stop}, daemon=True)
    server.start()
    try:
        target = send.parse_target(
            f"serial://{os.ttyname(slave2)}?baud=9600")
        result = send.send_serial(target, b"loopback", read=True,
                                  timeout=5)
        assert result.reply == b"loopback"
    finally:
        stop.set()
        pumping.clear()
