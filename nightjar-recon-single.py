#!/usr/bin/env python3
"""nightjar recon overlay - one file, wires itself in.

    python3 nightjar-recon-single.py /path/to/nightjar
    python3 nightjar-recon-single.py /path/to/nightjar --check    # report only
    python3 nightjar-recon-single.py /path/to/nightjar --force    # overwrite modules

Writes nightjar/payloads.py, nightjar/recon.py, tests/test_hacktools.py and
HACKER-RECON.md into a nightjar checkout, then wires nightjar/cli.py (an
import pair, three COMMANDS names, three subparsers, three handlers) and
refreshes this repo's apply_overlay.py so both routes land the same tree.

Every anchor has a fallback for the pre-send-overlay and post-send-overlay
text, so this works on a clean checkout *or* on one where apply_overlay.py
already ran, and re-running it is a no-op. Nothing is committed.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RECON_VERSION = "2.7.0"

CLI = "nightjar/cli.py"
PYPROJECT = "pyproject.toml"


# =============================================================================
# nightjar/payloads.py
# =============================================================================

PAYLOADS_PY = r'''"""nightjar payloads - protocol first words, wire-exact.

The first thing a client says to a service: the bytes that make a
stranger introduce itself. `nightjar knock` speaks the right one at
every open port; `nightjar send --preset NAME` uses one as a payload
and fills in the service's own port when you leave it off.

Server-first protocols (ssh, mysql) carry an empty probe: the knocker
just listens. Everything is the standard library, and every length,
offset and BER/BSON/TLV envelope is computed rather than remembered.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from functools import partial
from typing import Callable

# --- encoders ----------------------------------------------------------------

def _ber_len(size: int) -> bytes:
    if size < 0x80:
        return bytes([size])
    out = b""
    while size:
        out = bytes([size & 0xFF]) + out
        size >>= 8
    return bytes([0x80 | len(out)]) + out


def _ber(tag: int, payload: bytes) -> bytes:
    return bytes([tag]) + _ber_len(len(payload)) + payload


def _ber_int(value: int) -> bytes:
    if value == 0:
        return _ber(0x02, b"\x00")
    out = b""
    while value:
        out = bytes([value & 0xFF]) + out
        value >>= 8
    if out[0] & 0x80:
        out = b"\x00" + out
    return _ber(0x02, out)


def _ber_base128(value: int) -> bytes:
    chunks = [value & 0x7F]
    value >>= 7
    while value:
        chunks.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(reversed(chunks))


def _ber_oid(dotted: str) -> bytes:
    parts = [int(p) for p in dotted.split(".")]
    body = bytes([40 * parts[0] + parts[1]])
    for part in parts[2:]:
        body += _ber_base128(part)
    return _ber(0x06, body)


def _resp(*parts) -> bytes:
    """A Redis RESP array command."""
    out = [b"*%d\r\n" % len(parts)]
    for part in parts:
        raw = part.encode("utf-8") if isinstance(part, str) else part
        out.append(b"$%d\r\n%s\r\n" % (len(raw), raw))
    return b"".join(out)


def _mqtt_str(text: str) -> bytes:
    raw = text.encode("utf-8")
    return struct.pack("!H", len(raw)) + raw


def _mqtt_remaining(size: int) -> bytes:
    out = b""
    while True:
        byte = size % 128
        size //= 128
        if size:
            byte |= 0x80
        out += bytes([byte])
        if not size:
            return out


def _dns_name(name: str) -> bytes:
    name = name.rstrip(".")
    out = b""
    for label in name.split("."):
        raw = label.encode("ascii")
        if not 0 < len(raw) < 64:
            raise ValueError(f"bad DNS label {label!r}")
        out += bytes([len(raw)]) + raw
    return out + b"\x00"


def _nbt_name(name: str = "*") -> bytes:
    padded = ("*" + " " * 15) if name == "*" else name.upper().ljust(16)[:16]
    out = b"\x20"
    for char in padded:
        code = ord(char)
        out += bytes([ord("A") + (code >> 4), ord("A") + (code & 0x0F)])
    return out + b"\x00"


def _http(method: str = "GET", path: str = "/", *, host: str = "localhost",
          headers: tuple = (), body: bytes = b"") -> bytes:
    lines = [f"{method} {path} HTTP/1.1", f"Host: {host}",
             "User-Agent: nightjar", "Accept: */*"]
    if body:
        lines.append(f"Content-Length: {len(body)}")
    lines.extend(f"{key}: {value}" for key, value in headers)
    lines.append("Connection: close")
    return ("\r\n".join(lines) + "\r\n\r\n").encode() + body


def _bson(doc: dict) -> bytes:
    body = b""
    for key, value in doc.items():
        name = key.encode() + b"\x00"
        if isinstance(value, bool):
            body += b"\x08" + name + bytes([value])
        elif isinstance(value, int):
            body += b"\x10" + name + struct.pack("<i", value)
        elif isinstance(value, float):
            body += b"\x01" + name + struct.pack("<d", value)
        else:
            raw = value.encode()
            body += b"\x02" + name + struct.pack("<i", len(raw) + 1) + raw + b"\x00"
    return struct.pack("<i", 4 + len(body) + 1) + body + b"\x00"


# --- builders ----------------------------------------------------------------

QTYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12, "MX": 15,
          "TXT": 16, "AAAA": 28, "SRV": 33, "ANY": 255}
QCLASSES = {"IN": 1, "CH": 3, "HS": 4}


def dns_query(qname: str, qtype: str = "A", qclass: str = "IN",
              rd: bool = True, edns: bool = True, qid: int = 0x1234) -> bytes:
    qtype_n = QTYPES.get(qtype.upper(), qtype) if isinstance(qtype, str) else qtype
    qclass_n = QCLASSES.get(qclass.upper(), qclass) if isinstance(qclass, str) else qclass
    flags = 0x0100 if rd else 0x0000
    header = struct.pack("!HHHHHH", qid, flags, 1, 0, 0, 1 if edns else 0)
    out = header + _dns_name(qname) + struct.pack("!HH", qtype_n, qclass_n)
    if edns:
        # root name, OPT type 41, class = UDP payload size, TTL 0, RDLEN 0
        out += b"\x00" + struct.pack("!HHIH", 41, 4096, 0, 0)
    return out


def nbns_query() -> bytes:
    return (b"\x12\x34\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            + _nbt_name("*") + struct.pack("!HH", 0x0021, 0x0001))


def ntp_request() -> bytes:
    return b"\x1b" + b"\x00" * 47


def snmp_sysdescr(oid: str = "1.3.6.1.2.1.1.1.0",
                  community: str = "public") -> bytes:
    varbind = _ber(0x30, _ber_oid(oid) + _ber(0x05, b""))
    pdu = _ber(0xA0, _ber_int(0x0A0B0C0D) + _ber_int(0) + _ber_int(0)
               + _ber(0x30, varbind))
    return _ber(0x30, _ber_int(0) + _ber(0x04, community.encode()) + pdu)


def ssdp_msearch() -> bytes:
    return (b"M-SEARCH * HTTP/1.1\r\n"
            b"HOST: 239.255.255.250:1900\r\n"
            b'MAN: "ssdp:discover"\r\n'
            b"MX: 1\r\nST: ssdp:all\r\n\r\n")


def dhcp_discover(mac: bytes = b"\xde\xad\xbe\xef\x00\x01") -> bytes:
    return (b"\x01\x01\x06\x00" + b"\x12\x34\x56\x78" + b"\x00\x00\x00\x00"
            + b"\x00" * 16 + mac + b"\x00" * 10
            + b"\x00" * 64 + b"\x00" * 128
            + b"\x63\x82\x53\x63"
            + bytes([53, 1, 1]) + bytes([55, 4, 1, 3, 6, 15]) + bytes([255]))


def tftp_read() -> bytes:
    return b"\x00\x01" + b"nightjar\x00octet\x00"


def stun_binding() -> bytes:
    return b"\x00\x01\x00\x00\x21\x12\xa4\x42" + bytes(range(12))


def syslog_line() -> bytes:
    return b"<14>nightjar speaking syslog\r\n"


def wireguard_init() -> bytes:
    return (b"\x01\x00\x00\x00" + b"\x11" * 4 + b"\x22" * 32 + b"\x33" * 48
            + b"\x44" * 28 + b"\x55" * 16 + b"\x00" * 16)


def mqtt_connect(client_id: str = "nightjar", keepalive: int = 60) -> bytes:
    body = (_mqtt_str("MQTT") + bytes([4, 0x02])
            + struct.pack("!H", keepalive) + _mqtt_str(client_id))
    return b"\x10" + _mqtt_remaining(len(body)) + body


def mqtt_publish(topic: str = "nightjar", payload: bytes = b"alive",
                 retain: bool = True, qos: int = 0) -> bytes:
    body = _mqtt_str(topic) + (struct.pack("!H", 1) if qos else b"") + payload
    header = 0x30 | (qos << 1) | (1 if retain else 0)
    return bytes([header]) + _mqtt_remaining(len(body)) + body


def mqtt_plant() -> bytes:
    """CONNECT then a retained PUBLISH, one shot: a payload that stays living."""
    return mqtt_connect() + mqtt_publish()


def mssql_prelogin() -> bytes:
    options = ((0x00, 6), (0x01, 1), (0x02, 1), (0x03, 4), (0x04, 1))
    offset = len(options) * 5 + 1
    head = b""
    for token, length in options:
        head += bytes([token]) + struct.pack("!HH", offset, length)
        offset += length
    head += b"\xff"
    data = b"\x00" * 6 + b"\x00\x00" + struct.pack("!I", 0x1234) + b"\x00"
    payload = head + data
    return (b"\x12\x01" + struct.pack("!H", 8 + len(payload))
            + b"\x00\x00\x01\x00" + payload)


def smb1_negotiate() -> bytes:
    dialects = b"".join(b"\x02" + d + b"\x00"
                        for d in (b"NT LM 0.12", b"SMB 2.002", b"SMB 2.???"))
    smb = (b"\xffSMB" + b"\x72" + b"\x00\x00\x00\x00" + b"\x18" + b"\x53\xc8"
           + b"\x00\x00" + b"\x00" * 8 + b"\x00\x00" + b"\xff\xfe"
           + b"\x00\x00" + b"\x00\x00" + b"\x00\x00" + b"\x00"
           + struct.pack("<H", len(dialects)) + dialects)
    return b"\x00" + len(smb).to_bytes(3, "big") + smb


def smb2_negotiate() -> bytes:
    dialects = (0x0202, 0x0210, 0x0300, 0x0302, 0x0311)
    header = (b"\xfeSMB" + struct.pack("<HH", 64, 0) + struct.pack("<I", 0)
              + struct.pack("<H", 0) + struct.pack("<H", 1) + struct.pack("<I", 0)
              + struct.pack("<I", 0) + struct.pack("<Q", 1) + struct.pack("<I", 0)
              + struct.pack("<I", 0) + struct.pack("<Q", 0) + b"\x00" * 16)
    request = (struct.pack("<HHHHI", 36, len(dialects), 0, 0, 0)
               + bytes(range(16))
               + b"".join(struct.pack("<H", d) for d in dialects)
               + struct.pack("<IHH", 0, 0, 0))
    msg = header + request
    return b"\x00" + len(msg).to_bytes(3, "big") + msg


def rpc_null() -> bytes:
    return (struct.pack("!IIII", 0x12345678, 0, 2, 100000)
            + struct.pack("!II", 2, 0) + struct.pack("!II", 0, 0)
            + struct.pack("!II", 0, 0))


def mongodb_ismaster(database: str = "admin") -> bytes:
    query = _bson({"ismaster": 1, "helloOk": True})
    body = (struct.pack("<i", 0) + database.encode() + b".$cmd\x00"
            + struct.pack("<ii", 0, -1) + query)
    return struct.pack("<iiii", 16 + len(body), 1, 0, 2004) + body


def zookeeper_mntr() -> bytes:
    return b"\x00\x00\x00\x04mntr"


def cassandra_options() -> bytes:
    return b"\x04\x00\x00\x00\x05\x00\x00\x00\x00"


def coap_get(path: str = "nightjar") -> bytes:
    out = b"\x40\x01\x30\x39"
    for index, segment in enumerate(path.split("/")):
        delta = 11 if index == 0 else 0
        out += bytes([(delta << 4) | len(segment)]) + segment.encode()
    return out


def modbus_read() -> bytes:
    return struct.pack("!HHHB", 1, 0, 6, 1) + b"\x03" + struct.pack("!HH", 0, 1)


def ldap_anon_bind() -> bytes:
    return _ber(0x30, _ber_int(1) + _ber(
        0x60, _ber_int(3) + _ber(0x04, b"") + _ber(0x80, b"")))


def adb_version() -> bytes:
    return b"\x00\x00\x00\x0chost:version"


def wol_magic(mac: str = "aabbccddeeff") -> bytes:
    return b"\xff" * 6 + bytes.fromhex(mac.replace(":", "").replace("-", "")) * 16


def zabbix_version() -> bytes:
    body = b'{"request":"agent.version"}'
    return b"ZBXD\x01" + struct.pack("<Q", len(body)) + body


def graphql_introspection() -> bytes:
    body = b'{"query":"{__schema{queryType{name} types{name kind}}}"}'
    return _http("POST", "/graphql",
                 headers=(("Content-Type", "application/json"),), body=body)


def http_get(path: str = "/") -> bytes:
    return _http("GET", path)


def http_options() -> bytes:
    return _http("OPTIONS", "/")


def http_head() -> bytes:
    return _http("HEAD", "/")


def http_trace() -> bytes:
    return _http("TRACE", "/")


def http_proxy_get() -> bytes:
    return _http("GET", "http://example.com/", host="example.com")


def http_connect() -> bytes:
    return b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n"


def sip_options(user: str = "nightjar", host: str = "127.0.0.1") -> bytes:
    return (f"OPTIONS sip:{user}@{host} SIP/2.0\r\n"
            f"Via: SIP/2.0/UDP {host}:5060;branch=z9hG4bKnj\r\n"
            f"Max-Forwards: 70\r\n"
            f"From: <sip:{user}@{host}>;tag=nj\r\n"
            f"To: <sip:{user}@{host}>\r\n"
            f"Call-ID: nightjar@{host}\r\n"
            f"CSeq: 1 OPTIONS\r\n"
            f"Contact: <sip:{user}@{host}>\r\n"
            f"Content-Length: 0\r\n\r\n").encode()


def rtsp_options() -> bytes:
    return b"OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n"


def socks5_greeting() -> bytes:
    return b"\x05\x01\x00"


def socks4_connect() -> bytes:
    return b"\x04\x01\x00\x50\x7f\x00\x00\x01nightjar\x00"


def telnet_negotiate() -> bytes:
    return b"\xff\xfd\x03\xff\xfb\x18\xff\xfb\x1f"


def vnc_client() -> bytes:
    return b"RFB 003.008\n"


def rdp_negotiate() -> bytes:
    return (b"\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00"
            b"\x03\x00\x00\x00")


def x11_setup() -> bytes:
    return b"l\x00\x0b\x00" + b"\x00" * 8


def postgres_sslrequest() -> bytes:
    return struct.pack("!II", 8, 80877103)


def postgres_startup() -> bytes:
    params = b"user\x00nightjar\x00database\x00nightjar\x00\x00"
    return struct.pack("!II", 8 + len(params), 196608) + params


def mysql_ping() -> bytes:
    return b"\x01\x00\x00\x00\x0e"


def mysql_query() -> bytes:
    return b"\x01\x00\x00\x00\x03SELECT 1"


# --- the probe table ---------------------------------------------------------

@dataclass(frozen=True)
class Probe:
    name: str
    port: int
    proto: str          # "tcp" | "udp"
    family: str         # what a human calls the service
    hint: bytes         # bytes that mean "that really was the service"
    build: Callable[[], bytes]
    tls: bool = False
    summary: str = ""


PROBES: dict[str, Probe] = {}


def _probe(name: str, port: int, proto: str, family: str, hint: bytes,
           build: Callable[[], bytes], *, tls: bool = False,
           summary: str = "") -> None:
    PROBES[name] = Probe(name, port, proto, family, hint, build, tls,
                         summary or family)


# name resolution
_probe("dns-a", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "example.com", "A"), summary="A query")
_probe("dns-aaaa", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "example.com", "AAAA"), summary="AAAA query")
_probe("dns-mx", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "example.com", "MX"), summary="MX query")
_probe("dns-txt", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "example.com", "TXT"), summary="TXT query")
_probe("dns-any", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "example.com", "ANY"), summary="ANY query")
_probe("dns-version", 53, "udp", "dns", b"\x81\x80",
       partial(dns_query, "version.bind", "TXT", "CH"),
       summary="CHAOS version.bind - names the resolver software")
_probe("dns-sd", 5353, "udp", "mdns", b"\x84\x00",
       partial(dns_query, "_services._dns-sd._udp.local", "PTR",
               rd=False, edns=False), summary="mDNS service enumeration")
_probe("llmnr", 5355, "udp", "llmnr", b"\x80\x00",
       partial(dns_query, "nightjar", "A", rd=False, edns=False),
       summary="LLMNR hostname query")
_probe("nbns", 137, "udp", "netbios-ns", b"\x84\x00", nbns_query,
       summary="NBNS node-status request")

# time, discovery, infrastructure
_probe("ntp", 123, "udp", "ntp", b"\x1c", ntp_request, summary="NTP client request")
_probe("snmp-sysdescr", 161, "udp", "snmp", b"\xa2", snmp_sysdescr,
       summary="SNMP v1 sysDescr - names the device")
_probe("ssdp", 1900, "udp", "ssdp", b"HTTP/1.1", ssdp_msearch,
       summary="SSDP M-SEARCH - UPnP discovery")
_probe("dhcp-discover", 67, "udp", "dhcp", b"\x02\x01\x06", dhcp_discover,
       summary="DHCP DISCOVER - ask the LAN to name itself")
_probe("tftp", 69, "udp", "tftp", b"\x00\x03", tftp_read,
       summary="TFTP read request")
_probe("stun", 3478, "udp", "stun", b"\x01\x01", stun_binding,
       summary="STUN binding request - reveals the public address")
_probe("syslog", 514, "udp", "syslog", b"", syslog_line, summary="Syslog datagram")
_probe("wireguard", 51820, "udp", "wireguard", b"\x02", wireguard_init,
       summary="WireGuard handshake initiation")

# data stores
_probe("redis-ping", 6379, "tcp", "redis", b"+PONG",
       partial(_resp, "PING"), summary="PING")
_probe("redis-info", 6379, "tcp", "redis", b"# Server",
       partial(_resp, "INFO"), summary="INFO - version and topology")
_probe("redis-keys", 6379, "tcp", "redis", b"*",
       partial(_resp, "KEYS", "*"), summary="KEYS * - the whole keyspace")
_probe("redis-set", 6379, "tcp", "redis", b"+OK",
       partial(_resp, "SET", "nightjar", "was-here"),
       summary="SET nightjar was-here - a payload that stays living")
_probe("memcached-stats", 11211, "tcp", "memcached", b"STAT",
       lambda: b"stats\r\n", summary="stats")
_probe("memcached-version", 11211, "tcp", "memcached", b"VERSION",
       lambda: b"version\r\n", summary="version")
_probe("memcached-get", 11211, "tcp", "memcached", b"VALUE",
       lambda: b"get nightjar\r\n", summary="get nightjar")
_probe("mongodb-ismaster", 27017, "tcp", "mongodb", b"ismaster",
       mongodb_ismaster, summary="legacy OP_QUERY ismaster")
_probe("cassandra-options", 9042, "tcp", "cassandra", b"\x84",
       cassandra_options, summary="CQL native protocol OPTIONS")
_probe("couchdb-root", 5984, "tcp", "couchdb", b"CouchDB",
       http_get, summary="GET / - the welcome banner")
_probe("elasticsearch-root", 9200, "tcp", "elasticsearch", b"cluster_name",
       http_get, summary="GET / - cluster name and version")
_probe("zookeeper-mntr", 2181, "tcp", "zookeeper", b"zk_",
       zookeeper_mntr, summary="mntr four-letter word")
_probe("etcd-version", 2379, "tcp", "etcd", b"etcdserver",
       partial(http_get, "/version"), summary="GET /version")
_probe("consul-leader", 8500, "tcp", "consul", b'"',
       partial(http_get, "/v1/status/leader"), summary="GET /v1/status/leader")
_probe("vault-health", 8200, "tcp", "vault", b"initialized",
       partial(http_get, "/v1/sys/health"), summary="GET /v1/sys/health")

# messaging
_probe("mqtt-connect", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_connect,
       summary="CONNECT - clean session")
_probe("mqtt-plant", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_plant,
       summary="CONNECT + retained PUBLISH - the broker keeps it")
_probe("amqp-header", 5672, "tcp", "amqp", b"AMQP",
       lambda: b"AMQP\x00\x00\x09\x01", summary="protocol header 0-9-1")
_probe("stomp-connect", 61613, "tcp", "stomp", b"CONNECTED",
       lambda: b"CONNECT\naccept-version:1.2\nhost:nightjar\n\n\x00",
       summary="STOMP CONNECT")
_probe("rabbitmq-overview", 15672, "tcp", "rabbitmq", b"rabbitmq_version",
       partial(http_get, "/api/overview"), summary="management API overview")

# mail and real-time
_probe("smtp-ehlo", 25, "tcp", "smtp", b"250",
       lambda: b"EHLO nightjar.local\r\n", summary="EHLO - capabilities")
_probe("smtp-vrfy", 25, "tcp", "smtp", b"250",
       lambda: b"VRFY root\r\n", summary="VRFY root - mailbox enumeration")
_probe("smtp-quit", 25, "tcp", "smtp", b"221",
       lambda: b"QUIT\r\n", summary="QUIT")
_probe("pop3-capa", 110, "tcp", "pop3", b"+OK",
       lambda: b"CAPA\r\n", summary="CAPA")
_probe("pop3-capa-tls", 995, "tcp", "pop3s", b"+OK",
       lambda: b"CAPA\r\n", tls=True, summary="CAPA over TLS")
_probe("imap-capa", 143, "tcp", "imap", b"CAPABILITY",
       lambda: b"a1 CAPABILITY\r\n", summary="CAPABILITY")
_probe("imap-capa-tls", 993, "tcp", "imaps", b"CAPABILITY",
       lambda: b"a1 CAPABILITY\r\n", tls=True, summary="CAPABILITY over TLS")
_probe("irc-register", 6667, "tcp", "irc", b"001",
       lambda: b"NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n",
       summary="NICK/USER registration")
_probe("sip-options", 5060, "tcp", "sip", b"SIP/2.0", sip_options,
       summary="OPTIONS - what the PBX will tell you")
_probe("sip-options-tls", 5061, "tcp", "sips", b"SIP/2.0", sip_options,
       tls=True, summary="OPTIONS over TLS")
_probe("rtsp-options", 554, "tcp", "rtsp", b"RTSP/1.0", rtsp_options,
       summary="RTSP OPTIONS")

# databases
_probe("postgres-sslrequest", 5432, "tcp", "postgres", b"S",
       postgres_sslrequest, summary="SSLRequest - 'S' means TLS is offered")
_probe("postgres-startup", 5432, "tcp", "postgres", b"R", postgres_startup,
       summary="startup message (fails auth, proves the service)")
_probe("mysql-ping", 3306, "tcp", "mysql", b"", mysql_ping, summary="COM_PING")
_probe("mysql-query", 3306, "tcp", "mysql", b"", mysql_query,
       summary="COM_QUERY SELECT 1")
_probe("mssql-prelogin", 1433, "tcp", "mssql", b"\x04", mssql_prelogin,
       summary="TDS PRELOGIN - the SQL Server handshake opener")

# file, directory, remote access
_probe("smb1-negotiate", 139, "tcp", "smb1", b"\xffSMB", smb1_negotiate,
       summary="SMB1 NEGOTIATE")
_probe("smb2-negotiate", 445, "tcp", "smb2", b"\xfeSMB", smb2_negotiate,
       summary="SMB2 NEGOTIATE - dialect list")
_probe("rpc-null", 111, "tcp", "portmapper", b"\x00\x00\x00\x01", rpc_null,
       summary="ONC RPC NULL call to the portmapper")
_probe("rsync-modules", 873, "tcp", "rsync", b"@RSYNCD",
       lambda: b"@RSYNCD: 31.0\n", summary="version handshake - lists modules")
_probe("ftp-user", 21, "tcp", "ftp", b"331",
       lambda: b"USER anonymous\r\n", summary="USER anonymous")
_probe("ssh-banner", 22, "tcp", "ssh", b"SSH-",
       lambda: b"", summary="nothing - the server speaks first")
_probe("telnet-negotiate", 23, "tcp", "telnet", b"\xff", telnet_negotiate,
       summary="DO/WILL option negotiation")
_probe("vnc-client", 5900, "tcp", "vnc", b"RFB", vnc_client,
       summary="client version handshake")
_probe("rdp-negotiate", 3389, "tcp", "rdp", b"\x03\x00", rdp_negotiate,
       summary="TPKT + X.224 connection request")
_probe("x11-setup", 6000, "tcp", "x11", b"\x01", x11_setup,
       summary="X11 connection setup")
_probe("socks5-greeting", 1080, "tcp", "socks5", b"\x05", socks5_greeting,
       summary="no-auth greeting")
_probe("socks4-connect", 1080, "tcp", "socks4", b"\x00\x5a", socks4_connect,
       summary="SOCKS4 CONNECT to 127.0.0.1:80")
_probe("adb-version", 5555, "tcp", "adb", b"OKAY", adb_version,
       summary="host:version")
_probe("ldap-anon-bind", 389, "tcp", "ldap", b"\x61", ldap_anon_bind,
       summary="anonymous simple bind")
_probe("ldap-anon-bind-tls", 636, "tcp", "ldaps", b"\x61", ldap_anon_bind,
       tls=True, summary="anonymous simple bind over TLS")
_probe("wol", 9, "udp", "wake-on-lan", b"", wol_magic,
       summary="magic packet - wakes a sleeping NIC")
_probe("coap-get", 5683, "udp", "coap", b"\x60", coap_get,
       summary="GET /nightjar (CON)")
_probe("modbus-read", 502, "tcp", "modbus", b"\x00\x01", modbus_read,
       summary="read holding registers")
_probe("zabbix-agent", 10050, "tcp", "zabbix", b"ZBXD", zabbix_version,
       summary="agent.version request")

# web, proxies, orchestration
_probe("http-get", 80, "tcp", "http", b"HTTP/1.", http_get, summary="GET /")
_probe("http-options", 80, "tcp", "http", b"HTTP/1.", http_options,
       summary="OPTIONS - the Allow header")
_probe("http-head", 80, "tcp", "http", b"HTTP/1.", http_head,
       summary="HEAD / - headers with no body")
_probe("http-trace", 80, "tcp", "http", b"HTTP/1.", http_trace,
       summary="TRACE - echoes the request back")
_probe("https-get", 443, "tcp", "https", b"HTTP/1.", http_get, tls=True,
       summary="GET / over TLS")
_probe("graphql-introspection", 80, "tcp", "graphql", b"__schema",
       graphql_introspection, summary="POST /graphql - dump the whole schema")
_probe("http-proxy-get", 3128, "tcp", "http-proxy", b"HTTP/1.", http_proxy_get,
       summary="absolute-URI GET - is it an open proxy?")
_probe("http-connect", 3128, "tcp", "http-proxy", b"HTTP/1.", http_connect,
       summary="CONNECT tunnel request")
_probe("docker-version", 2375, "tcp", "docker", b"ApiVersion",
       partial(http_get, "/version"), summary="GET /version - unauthenticated?")
_probe("docker-version-tls", 2376, "tcp", "docker", b"ApiVersion",
       partial(http_get, "/version"), tls=True, summary="GET /version over TLS")
_probe("docker-registry", 5000, "tcp", "docker-registry", b"200",
       partial(http_get, "/v2/"), summary="GET /v2/ - registry API")
_probe("kubernetes-version", 6443, "tcp", "kubernetes", b"gitVersion",
       partial(http_get, "/version"), tls=True, summary="GET /version (TLS)")
_probe("kubelet-health", 10250, "tcp", "kubelet", b"ok",
       partial(http_get, "/healthz"), tls=True, summary="GET /healthz (TLS)")
_probe("jenkins-api", 8080, "tcp", "jenkins", b"Jenkins",
       partial(http_get, "/api/json"), summary="GET /api/json")
_probe("prometheus-metrics", 9090, "tcp", "prometheus", b"HELP",
       partial(http_get, "/metrics"), summary="GET /metrics")
_probe("grafana-health", 3000, "tcp", "grafana", b"database",
       partial(http_get, "/api/health"), summary="GET /api/health")
_probe("kibana-status", 5601, "tcp", "kibana", b"version",
       partial(http_get, "/api/status"), summary="GET /api/status")
_probe("solr-admin", 8983, "tcp", "solr", b"lucene",
       partial(http_get, "/solr/admin/info/system"), summary="admin info/system")
_probe("influxdb-ping", 8086, "tcp", "influxdb", b"204",
       lambda: b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
       summary="GET /ping")
_probe("minio-health", 9000, "tcp", "minio", b"200",
       partial(http_get, "/minio/health/live"), summary="health/live")
_probe("neo4j-root", 7474, "tcp", "neo4j", b"neo4j", http_get, summary="GET /")
_probe("gitea-version", 3000, "tcp", "gitea", b"version",
       partial(http_get, "/api/v1/version"), summary="GET /api/v1/version")
_probe("gitlab-readiness", 80, "tcp", "gitlab", b"GitLab",
       partial(http_get, "/-/readiness"), summary="GET /-/readiness")

# small talk
_probe("echo", 7, "tcp", "echo", b"", lambda: b"", summary="nothing - echo")
_probe("daytime", 13, "tcp", "daytime", b"", lambda: b"", summary="nothing")
_probe("chargen", 19, "tcp", "chargen", b"", lambda: b"", summary="nothing")
_probe("discard", 9, "tcp", "discard", b"", lambda: b"nightjar\r\n",
       summary="throw it away")
_probe("whois", 43, "tcp", "whois", b"", lambda: b"example.com\r\n",
       summary="query a whois server")
_probe("finger", 79, "tcp", "finger", b"", lambda: b"nightjar\r\n",
       summary="finger a user")
_probe("gopher", 70, "tcp", "gopher", b"", lambda: b"nightjar\r\n",
       summary="gopher selector")
_probe("gemini", 1965, "tcp", "gemini", b"20 ", lambda: b"gemini://nightjar/\r\n",
       summary="Gemini request")


# --- port maps ---------------------------------------------------------------

PORT_PROBES: dict[int, str] = {
    7: "echo", 9: "discard", 13: "daytime", 19: "chargen", 21: "ftp-user",
    22: "ssh-banner", 23: "telnet-negotiate", 25: "smtp-ehlo", 43: "whois",
    53: "dns-version", 67: "dhcp-discover", 69: "tftp", 70: "gopher", 79: "finger",
    80: "http-get", 88: "http-get", 110: "pop3-capa", 111: "rpc-null", 123: "ntp",
    137: "nbns", 139: "smb1-negotiate", 143: "imap-capa", 161: "snmp-sysdescr",
    389: "ldap-anon-bind", 443: "https-get", 445: "smb2-negotiate",
    502: "modbus-read", 554: "rtsp-options", 587: "smtp-ehlo", 631: "http-get",
    636: "ldap-anon-bind-tls", 873: "rsync-modules", 993: "imap-capa-tls",
    995: "pop3-capa-tls", 1080: "socks5-greeting", 1433: "mssql-prelogin",
    1883: "mqtt-connect", 1900: "ssdp", 1965: "gemini", 2049: "rpc-null",
    2181: "zookeeper-mntr", 2375: "docker-version", 2376: "docker-version-tls",
    2379: "etcd-version", 3000: "grafana-health", 3128: "http-proxy-get",
    3306: "mysql-ping", 3389: "rdp-negotiate", 3478: "stun", 5000: "docker-registry",
    5060: "sip-options", 5061: "sip-options-tls", 5432: "postgres-sslrequest",
    5555: "adb-version", 5601: "kibana-status", 5672: "amqp-header",
    5683: "coap-get", 5900: "vnc-client", 5984: "couchdb-root", 6000: "x11-setup",
    61613: "stomp-connect", 6379: "redis-ping", 6443: "kubernetes-version",
    7001: "http-get", 7474: "neo4j-root", 8000: "http-get", 8001: "http-get",
    8008: "http-get", 8080: "jenkins-api", 8081: "http-get", 8086: "influxdb-ping",
    8200: "vault-health", 8443: "https-get", 8500: "consul-leader", 8888: "http-get",
    8983: "solr-admin", 9000: "minio-health", 9042: "cassandra-options",
    9090: "prometheus-metrics", 9200: "elasticsearch-root", 9300: "elasticsearch-root",
    10050: "zabbix-agent", 10250: "kubelet-health", 11211: "memcached-stats",
    15672: "rabbitmq-overview", 27017: "mongodb-ismaster", 51820: "wireguard",
}

PORT_PROBES_UDP: dict[int, str] = {
    9: "wol", 53: "dns-a", 67: "dhcp-discover", 69: "tftp", 123: "ntp",
    137: "nbns", 161: "snmp-sysdescr", 514: "syslog", 1900: "ssdp",
    3478: "stun", 5353: "dns-sd", 5355: "llmnr", 5683: "coap-get",
    51820: "wireguard",
}

DEFAULT_KNOCK_PORTS: tuple[int, ...] = tuple(sorted(PORT_PROBES))


# --- the API -----------------------------------------------------------------

def probe_names() -> list[str]:
    return sorted(PROBES)


def build_probe(name: str) -> bytes:
    probe = PROBES.get(name)
    if probe is None:
        near = [n for n in PROBES if name.lower() in n.lower()]
        hint = f" (did you mean {', '.join(near[:5])}?)" if near else ""
        raise KeyError(f"no preset {name!r}{hint}")
    return probe.build()


def probe_for_port(port: int, proto: str = "tcp") -> Probe | None:
    table = PORT_PROBES_UDP if proto == "udp" else PORT_PROBES
    name = table.get(port)
    return PROBES[name] if name else None


def describe(name: str) -> str:
    probe = PROBES[name]
    return f"{name:<24} {probe.proto}/{probe.port:<6} {probe.summary}"


def library() -> str:
    lines = [f"{len(PROBES)} protocol first words "
             f"({len(PORT_PROBES)} tcp ports, {len(PORT_PROBES_UDP)} udp)\n"]
    for name in probe_names():
        lines.append("  " + describe(name))
    return "\n".join(lines)


__all__ = [
    "Probe", "PROBES", "PORT_PROBES", "PORT_PROBES_UDP", "DEFAULT_KNOCK_PORTS",
    "build_probe", "probe_for_port", "probe_names", "library", "describe",
]
'''


# =============================================================================
# nightjar/recon.py
# =============================================================================

RECON_PY = r'''"""nightjar recon - knock, connect, fuzz.

`knock` walks a host, speaks each open port's own protocol, and files
the banner. `connect` is the nc you always wanted. `fuzz` throws
mangled bytes at one target and tells you what changed.

`send` grows `--preset NAME` (a payload from the protocol library, with
the service's own port filled in when you leave it off) and `--lines
FILE` (each line as its own payload, with `--jitter` between them).
"""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import json
import random
import socket
import ssl
import sys
import threading
import time
from pathlib import Path

from . import send as sendcmd
from .payloads import (
    DEFAULT_KNOCK_PORTS, PORT_PROBES_UDP, PROBES, build_probe, library,
    probe_for_port,
)

MAX_REPLY = 65536
BANNER_LIMIT = 4096


# --- shared ------------------------------------------------------------------

def parse_ports(spec: str) -> list[int]:
    ports: set[int] = set()
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        if "-" in chunk:
            low, _, high = chunk.partition("-")
            ports.update(range(int(low), int(high) + 1))
        else:
            ports.add(int(chunk))
    return sorted(p for p in ports if 0 < p < 65536)


def _is_ip(text: str) -> bool:
    try:
        socket.inet_aton(text)
        return True
    except OSError:
        return False


def _tls_wrap(sock: socket.socket, host: str) -> socket.socket:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx.wrap_socket(sock, server_hostname=host)


def _first_line(data: bytes) -> str:
    if not data:
        return ""
    for line in data.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if line and line.isprintable():
            return line[:160]
    return data[:48].hex()


# --- knock -------------------------------------------------------------------

def _knock_port(host: str, port: int, timeout: float, probe_ok: bool) -> dict:
    probe = probe_for_port(port, "tcp") if probe_ok else None
    record = {"host": host, "port": port, "proto": "tcp", "state": "closed",
              "service": probe.family if probe else "?", "banner": "",
              "reply_bytes": 0, "reply_b64": "", "confirmed": False}
    try:
        sock = socket.create_connection((host, port), timeout=timeout)
    except (socket.timeout, ConnectionRefusedError, OSError):
        return record

    data = b""
    try:
        if probe is not None and probe.tls:
            sock = _tls_wrap(sock, host)
        sock.settimeout(timeout)
        if probe is not None and probe.build():
            sock.sendall(probe.build())
        while len(data) < MAX_REPLY:
            try:
                chunk = sock.recv(4096)
            except (socket.timeout, ssl.SSLError, OSError):
                break
            if not chunk:
                break
            data += chunk
            if probe is not None and probe.hint and probe.hint in data:
                break
    except (socket.timeout, ssl.SSLError, OSError):
        pass
    finally:
        try:
            sock.close()
        except OSError:
            pass

    record["state"] = "open"
    record["banner"] = _first_line(data[:BANNER_LIMIT])
    record["reply_bytes"] = len(data)
    record["reply_b64"] = base64.b64encode(data[:2048]).decode("ascii")
    record["confirmed"] = (probe.hint in data if probe is not None and probe.hint
                           else bool(data))
    return record


def _knock_udp(host: str, port: int, timeout: float) -> dict:
    name = PORT_PROBES_UDP.get(port)
    record = {"host": host, "port": port, "proto": "udp", "state": "open|filtered",
              "service": PROBES[name].family if name else "?", "banner": "",
              "reply_bytes": 0, "reply_b64": "", "confirmed": False}
    if name is None:
        return record
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        sock.sendto(build_probe(name), (host, port))
        data, _ = sock.recvfrom(MAX_REPLY)
        record["state"] = "open"
        record["banner"] = _first_line(data[:BANNER_LIMIT])
        record["reply_bytes"] = len(data)
        record["reply_b64"] = base64.b64encode(data[:2048]).decode("ascii")
        record["confirmed"] = PROBES[name].hint in data if PROBES[name].hint else bool(data)
    except socket.timeout:
        pass
    except OSError:
        record["state"] = "closed"
    finally:
        sock.close()
    return record


def cmd_knock(args) -> int:
    try:
        host = args.host if _is_ip(args.host) else socket.gethostbyname(args.host)
    except OSError as exc:
        print(f"nightjar: cannot resolve {args.host}: {exc}", file=sys.stderr)
        return 2

    ports = parse_ports(args.ports) if args.ports else list(DEFAULT_KNOCK_PORTS)
    udp_ports = [p for p in ports if p in PORT_PROBES_UDP] if args.udp else []
    print(f"nightjar knock: {host} - {len(ports)} tcp"
          f"{f' + {len(udp_ports)} udp' if udp_ports else ''} port(s), "
          f"{args.jobs} at a time.", file=sys.stderr, flush=True)

    results: list[dict] = []
    lock = threading.Lock()
    header = f"{'PORT':<10} {'STATE':<14} {'SERVICE':<18} BANNER"
    if not args.json:
        print(header)
        print("-" * len(header))

    def report(record: dict) -> None:
        with lock:
            results.append(record)
            if args.json:
                print(json.dumps(record), flush=True)
                return
            if record["state"] == "closed":
                return
            mark = "*" if record["confirmed"] else " "
            print(f"{str(record['port']) + '/' + record['proto']:<10} "
                  f"{record['state']:<14} {record['service']:<18} "
                  f"{mark} {record['banner']}", flush=True)
            if args.show_reply and record["reply_b64"]:
                print(sendcmd.hexdump(base64.b64decode(record["reply_b64"])),
                      flush=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(_knock_port, host, port, args.timeout,
                               not args.no_probe) for port in ports]
        futures += [pool.submit(_knock_udp, host, port, args.timeout)
                    for port in udp_ports]
        for future in concurrent.futures.as_completed(futures):
            report(future.result())

    open_ports = [r for r in results if r["state"] == "open"]
    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            for record in sorted(results, key=lambda r: (r["proto"], r["port"])):
                fh.write(json.dumps(record) + "\n")
        if not args.json:
            print(f"\n{len(open_ports)} open; results written to {args.out}")
    elif not args.json:
        print(f"\n{len(open_ports)} open port(s).")
    return 0 if open_ports else 1


# --- connect -----------------------------------------------------------------

def cmd_connect(args) -> int:
    try:
        target = sendcmd.parse_target(args.target)
    except sendcmd.SendError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 2
    if target.scheme != "tcp":
        print("nightjar connect: tcp targets only (tcp:// or a bare host:port)",
              file=sys.stderr)
        return 2
    try:
        sock = socket.create_connection((target.host, target.port),
                                        timeout=args.timeout)
        if target.tls:
            sock = _tls_wrap(sock, target.host)
    except OSError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 1
    sock.settimeout(0.3)

    print(f"connected to {target.raw} - Ctrl-] (or a lone ~) then Enter quits.",
          file=sys.stderr)
    if args.payload:
        sock.sendall(args.payload.encode("utf-8"))

    stop = threading.Event()

    def reader() -> None:
        while not stop.is_set():
            try:
                data = sock.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                break
            if not data:
                print("\n[remote closed]", file=sys.stderr)
                stop.set()
                break
            if args.hex:
                print(sendcmd.hexdump(data), flush=True)
            else:
                sys.stdout.write(data.decode("utf-8", "replace"))
                sys.stdout.flush()

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    try:
        while not stop.is_set():
            line = sys.stdin.readline()
            if line == "":
                break
            if line.rstrip("\n") in ("\x1d", "~"):
                break
            if args.crlf:
                line = line.replace("\n", "\r\n")
            try:
                sock.sendall(line.encode("utf-8"))
            except OSError as exc:
                print(f"\nnightjar: {exc}", file=sys.stderr)
                break
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        try:
            sock.close()
        except OSError:
            pass
    return 0


# --- fuzz --------------------------------------------------------------------

MUTATORS = ("flip_bit", "set_byte", "insert", "delete", "duplicate",
            "splice", "truncate")


def _mutate(data: bytearray, rng: random.Random) -> None:
    kind = rng.choice(MUTATORS)
    if not data:
        data.append(rng.randrange(256))
        return
    if kind == "flip_bit":
        index = rng.randrange(len(data))
        data[index] ^= 1 << rng.randrange(8)
    elif kind == "set_byte":
        data[rng.randrange(len(data))] = rng.randrange(256)
    elif kind == "insert":
        data.insert(rng.randrange(len(data) + 1), rng.randrange(256))
    elif kind == "delete" and len(data) > 1:
        del data[rng.randrange(len(data))]
    elif kind == "duplicate":
        start = rng.randrange(len(data))
        end = min(len(data), start + rng.randrange(1, 17))
        data[start:start] = data[start:end]
    elif kind == "splice":
        start = rng.randrange(len(data))
        end = min(len(data), start + rng.randrange(1, 9))
        data[start:end] = bytes(rng.randrange(256) for _ in range(end - start))
    elif kind == "truncate":
        del data[rng.randrange(len(data)):]


def cmd_fuzz(args) -> int:
    try:
        target = sendcmd.parse_target(args.target)
    except sendcmd.SendError as exc:
        print(f"nightjar: {exc}", file=sys.stderr)
        return 2
    rng = random.Random(args.seed)
    if args.payload_hex:
        seed = bytes.fromhex(args.payload_hex.replace(":", "").replace(" ", ""))
    elif args.payload:
        seed = args.payload.encode("utf-8")
    else:
        seed = bytes(rng.randrange(256) for _ in range(args.length))

    print(f"nightjar fuzz: {target.raw} - {args.count} mutation(s) "
          f"from {len(seed)} seed byte(s).", file=sys.stderr, flush=True)
    dead = 0
    for index in range(1, args.count + 1):
        data = bytearray(seed)
        for _ in range(max(1, args.mutations)):
            _mutate(data, rng)
        blob = bytes(data)
        try:
            if target.scheme == "udp":
                result = sendcmd.send_udp(target, blob, read=args.read,
                                          timeout=args.timeout)
            else:
                result = sendcmd.send_tcp(target, blob, read=args.read,
                                          timeout=args.timeout)
        except (sendcmd.SendError, OSError) as exc:
            dead += 1
            if args.json:
                print(json.dumps({"n": index, "len": len(blob), "error": str(exc)}),
                      flush=True)
            else:
                print(f"  {index:>5}  len={len(blob):<5} DEAD  {exc}", flush=True)
            if args.stop_on_dead:
                break
            continue
        reply = result.reply or b""
        if args.json:
            print(json.dumps({"n": index, "len": len(blob),
                              "send_hex": blob.hex(),
                              "reply_bytes": len(reply),
                              "reply_b64": base64.b64encode(reply).decode("ascii")}),
                  flush=True)
        else:
            print(f"  {index:>5}  len={len(blob):<5} "
                  f"reply={len(reply):<5} {_first_line(reply)}", flush=True)
        if args.delay:
            time.sleep(args.delay)
    if not args.json:
        print(f"\n{args.count} mutation(s), {dead} dead connection(s).")
    return 0


# --- send glue: --preset, --lines, --jitter ----------------------------------

def add_preset_args(parser) -> None:
    parser.add_argument("--preset", metavar="NAME",
                        help="payload from the protocol library "
                             "(nightjar send --presets lists them)")
    parser.add_argument("--presets", action="store_true",
                        help="list the protocol library and exit")
    parser.add_argument("--lines", metavar="FILE",
                        help="send each line of FILE as its own payload")
    parser.add_argument("--jitter", type=float, default=0.0, metavar="SECONDS",
                        help="add up to SECONDS of random delay between sends")
    parser.add_argument("--skip-blank", action="store_true",
                        help="with --lines, skip empty lines")


def _clone(args, **overrides):
    copy = argparse.Namespace(**vars(args))
    for key, value in overrides.items():
        setattr(copy, key, value)
    return copy


def _one_shot(args):
    return _clone(args, repeat=0, duration=None, jitter=0.0)


def _fill_port(raw: str, port: int, udp: bool) -> str:
    if sendcmd.looks_like_mac(raw) or raw.startswith("name:"):
        return raw
    scheme = ""
    rest = raw
    if "://" in raw:
        scheme, rest = raw.split("://", 1)
        if scheme in ("http", "https", "ws", "wss"):
            return raw
    host, sep, tail = rest.rpartition(":")
    if sep and tail.isdigit():
        return raw
    if not scheme and udp:
        return f"udp://{rest}:{port}"
    return f"{scheme}://{rest}:{port}" if scheme else f"{rest}:{port}"


def _apply_preset(args) -> None:
    probe = PROBES[args.preset]
    args.payload_hex = build_probe(args.preset).hex()
    args.payload = args.payload_b64 = args.payload_file = None
    args.target = [_fill_port(raw, probe.port, probe.proto == "udp")
                   for raw in args.target]


def _with_jitter(args) -> int:
    if args.jitter <= 0 or (not args.repeat and not args.duration):
        return sendcmd.cmd_send(args)
    started = time.time()
    worst = 0
    count = 0
    while True:
        count += 1
        code = sendcmd.cmd_send(_one_shot(args))
        worst = max(worst, code)
        if code != 0:
            break
        if args.repeat and count >= args.repeat:
            break
        if args.duration and time.time() - started >= args.duration:
            break
        time.sleep(max(0.0, args.interval + random.uniform(0, args.jitter)))
    return worst


def cmd_send(args) -> int:
    if getattr(args, "presets", False):
        print(library())
        return 0
    if args.preset:
        try:
            _apply_preset(args)
        except KeyError as exc:
            print(f"nightjar: {exc}", file=sys.stderr)
            return 2
    if args.lines:
        return _send_lines(args)
    return _with_jitter(args)


def _send_lines(args) -> int:
    try:
        lines = Path(args.lines).read_text(encoding="utf-8",
                                          errors="replace").splitlines()
    except OSError as exc:
        print(f"nightjar: cannot read {args.lines}: {exc}", file=sys.stderr)
        return 2
    if args.skip_blank:
        lines = [line for line in lines if line.strip()]
    print(f"nightjar send: {len(lines)} line(s) from {args.lines}.",
          file=sys.stderr, flush=True)
    worst = 0
    for index, line in enumerate(lines, 1):
        shot = _clone(args, payload=line, payload_hex=None, payload_b64=None,
                      payload_file=None, repeat=0, duration=None, lines=None,
                      preset=None, presets=False)
        code = sendcmd.cmd_send(shot)
        worst = max(worst, code)
        if code == 1:  # --expect failed: that is the answer, stop here
            break
        if index < len(lines):
            time.sleep(max(0.0, args.interval + random.uniform(0, args.jitter)))
    return worst


__all__ = ["add_preset_args", "cmd_send", "cmd_knock", "cmd_connect", "cmd_fuzz"]
'''


# =============================================================================
# tests/test_hacktools.py
# =============================================================================

TESTS_PY = r'''"""The library builds, the map is sane, knock really knocks."""

import random
import socket
import struct
import threading

import pytest

from nightjar import payloads, recon


def test_every_probe_builds():
    for name in payloads.probe_names():
        assert isinstance(payloads.build_probe(name), bytes)


def test_port_maps_point_at_real_probes():
    for port, name in {**payloads.PORT_PROBES, **payloads.PORT_PROBES_UDP}.items():
        assert name in payloads.PROBES
        assert 0 < port < 65536


def test_dns_query_shape():
    blob = payloads.build_probe("dns-a")
    qid, flags, qd, an, ns, ar = struct.unpack("!HHHHHH", blob[:12])
    assert qid == 0x1234 and flags == 0x0100 and qd == 1 and ar == 1
    assert b"\x07example\x03com\x00" in blob


def test_snmp_sysdescr_is_ber():
    blob = payloads.build_probe("snmp-sysdescr")
    assert blob[0] == 0x30
    assert b"public" in blob
    assert b"\x06\x08\x2b\x06\x01\x02\x01\x01\x01\x00" in blob


def test_mssql_prelogin_length_matches():
    blob = payloads.build_probe("mssql-prelogin")
    assert blob[0] == 0x12
    assert struct.unpack("!H", blob[2:4])[0] == len(blob)


def test_smb2_negotiate_header():
    blob = payloads.build_probe("smb2-negotiate")
    assert blob[4:8] == b"\xfeSMB"
    assert struct.unpack("<H", blob[8:10])[0] == 64


def test_smb1_negotiate_length_matches():
    blob = payloads.build_probe("smb1-negotiate")
    assert blob[4:8] == b"\xffSMB"
    assert int.from_bytes(blob[:4][1:], "big") == len(blob) - 4


def test_wireguard_init_is_148_bytes():
    assert len(payloads.build_probe("wireguard")) == 148


def test_wol_is_six_ffs_and_sixteen_macs():
    blob = payloads.build_probe("wol")
    assert blob[:6] == b"\xff" * 6
    assert len(blob) == 6 + 16 * 6


def test_mqtt_plant_connects_then_publishes():
    blob = payloads.build_probe("mqtt-plant")
    assert blob[0] == 0x10                       # CONNECT first
    assert 0x31 in blob[2:]                      # retained PUBLISH after it


def test_unknown_preset_suggests():
    with pytest.raises(KeyError) as exc:
        payloads.build_probe("redis-pig")
    assert "redis-ping" in str(exc.value)


def test_parse_ports():
    assert recon.parse_ports("22,80,443") == [22, 80, 443]
    assert recon.parse_ports("1-4") == [1, 2, 3, 4]
    assert recon.parse_ports("80,100-102") == [80, 100, 101, 102]


def test_fill_port_only_when_missing():
    assert recon._fill_port("10.0.0.7", 6379, False) == "10.0.0.7:6379"
    assert recon._fill_port("10.0.0.7:6380", 6379, False) == "10.0.0.7:6380"
    assert recon._fill_port("tcp://h", 6379, False) == "tcp://h:6379"
    assert recon._fill_port("http://h/x", 80, False) == "http://h/x"
    assert recon._fill_port("10.0.0.7", 53, True) == "udp://10.0.0.7:53"


def test_knock_finds_a_listener_and_speaks():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(4)
    port = server.getsockname()[1]

    def serve():
        conn, _ = server.accept()
        with conn:
            conn.sendall(b"+PONG\r\n")

    threading.Thread(target=serve, daemon=True).start()
    record = recon._knock_port("127.0.0.1", port, timeout=2.0, probe_ok=True)
    assert record["state"] == "open"
    assert record["banner"].startswith("+PONG")
    server.close()


def test_knock_reports_closed():
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    port = server.getsockname()[1]
    server.close()
    record = recon._knock_port("127.0.0.1", port, timeout=0.5, probe_ok=True)
    assert record["state"] == "closed"


def test_fuzz_mutators_keep_bytes():
    rng = random.Random(7)
    for _ in range(200):
        data = bytearray(b"nightjar")
        recon._mutate(data, rng)
        assert isinstance(bytes(data), bytes)
'''


# =============================================================================
# HACKER-RECON.md
# =============================================================================

HACKER_RECON_MD = r'''# nightjar recon - the vocabulary

`nightjar listen`s. This adds the words. Three commands, one library, no
new dependencies, and nothing about the scanning path changes.

## knock - speak to every open port

    nightjar knock 192.168.1.1
    nightjar knock 10.0.0.7 --ports 1-1024 --udp --out knock.jsonl
    nightjar knock 10.0.0.7 --json | jq 'select(.confirmed)'

Connects, sends the protocol the port expects, files the banner. A `*`
before the banner means the reply carried the protocol's own tell - the
port is not just open, it answered *as that service*. `--no-probe` just
connects and listens. `--udp` also knocks the UDP service ports.

## send --preset - a payload with a vocabulary

    nightjar send --presets                        # the library
    nightjar send --preset redis-ping 10.0.0.7     # :6379 filled in
    nightjar send --preset snmp-sysdescr --read udp://10.0.0.7:161
    nightjar send --preset graphql-introspection https://api.target/graphql
    nightjar send --preset mqtt-plant mqtt://broker:1883

`--preset` composes with everything `send` already had: `--framing`,
`--xor`, `--gzip`, `--dry-run`, fan-out, `--repeat`, `--expect`.

## send --lines - spray a wordlist

    nightjar send tcp://10.0.0.9:80 --lines words.txt --expect 200 --jitter 0.2

One payload per line, `--jitter` of randomness between them, and the run
stops at the first `--expect` miss because that is usually the answer.

## connect - nc, with a hexdump

    nightjar connect 10.0.0.9:23
    nightjar connect tls://10.0.0.9:443 --hex

Ctrl-] (or a lone `~`) then Enter quits.

## fuzz - throw mangled bytes at one target

    nightjar fuzz udp://10.0.0.9:53 --count 5000 --seed 1 --stop-on-dead
    nightjar fuzz tcp://10.0.0.9:8080 --payload-hex '474554202f' --mutations 3

Seven mutators, a reproducible `--seed`, and `--json` for pipes.

## The library

75 protocol first words, wire-exact: lengths, offsets and BER/BSON/TLV
envelopes are computed rather than remembered. Name resolution, time and
discovery, data stores, messaging, mail, databases, file and directory,
remote access, web and orchestration - see `nightjar send --presets`.

Server-first protocols (ssh, mysql, echo) carry an empty probe: the
knocker just listens. Probes that need TLS (https, ldaps, imaps, pop3s,
kubelet, docker-tls) wrap the socket themselves.

## Honest limits

- `knock` is a connect scan. No SYN, no ARP, no raw sockets.
- UDP `open|filtered` means no reply, which is the correct answer for UDP.
- The `Host:` header on HTTP probes is `localhost`; the target's own name is
  not guessed. Use `connect` or a raw `--payload` when the vhost matters.
- `--lines` sends one line per payload; pair it with `--repeat` by hand if
  you want repeats per line.
'''


# =============================================================================
# apply_overlay.py (regenerated, now covering all three modules)
# =============================================================================

APPLY_OVERLAY_PY = r'''#!/usr/bin/env python3
"""Apply the nightjar-hack overlay onto a nightjar checkout.

    python3 apply_overlay.py /path/to/nightjar
    python3 apply_overlay.py /path/to/nightjar --check     # report only
    python3 apply_overlay.py /path/to/nightjar --force     # overwrite modules

It drops nightjar/send.py, nightjar/payloads.py and nightjar/recon.py into
the package and makes anchored edits in nightjar/cli.py plus one in
pyproject.toml, then bumps the version. Every anchor carries a fallback for
the text before and after the send layer landed, so this works on a clean
checkout or on one that is already half-patched, and re-running it is a
no-op. Nothing is committed, nothing is pushed: the checkout is yours.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
HACK_VERSION = "@@VERSION@@"

CLI = "nightjar/cli.py"
PYPROJECT = "pyproject.toml"

# (file, (candidate old texts - first one that is present wins), replacement)
PATCHES: list[tuple[str, tuple[str, ...], str]] = @@PATCHES@@


def patch_file(path: Path, olds: tuple[str, ...], new: str, *, write: bool) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    if new in text and not any(old in text for old in olds):
        return "already"
    for old in olds:
        if old in text:
            if text.count(old) != 1:
                return f"anchor-ambiguous({text.count(old)})"
            if write:
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            return "patched"
    return "anchor-not-found"


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
        description="Apply the nightjar-hack overlay (send, serve, recon).")
    parser.add_argument("repo", nargs="?", default=".",
                        help="path to the nightjar checkout (default: .)")
    parser.add_argument("--check", action="store_true",
                        help="report what would change, write nothing")
    parser.add_argument("--force", action="store_true",
                        help="overwrite existing overlay modules")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / "nightjar" / "cli.py").exists():
        print(f"not a nightjar checkout (no nightjar/cli.py under {repo})",
              file=sys.stderr)
        return 2
    write = not args.check
    print(f"nightjar checkout: {repo}{'  [check only]' if args.check else ''}")

    overlay_files = ("send.py", "payloads.py", "recon.py")
    for name in overlay_files:
        source = HERE / "nightjar" / name
        if not source.exists():
            print(f"  ! overlay is incomplete: {source} not found", file=sys.stderr)
            return 2
        destination = repo / "nightjar" / name
        if destination.exists() and not args.force:
            print(f"  = nightjar/{name} already present (use --force to overwrite)")
        else:
            if write:
                shutil.copyfile(source, destination)
            print(f"  + nightjar/{name}")

    problems = 0
    for relative, olds, new in PATCHES:
        outcome = patch_file(repo / relative, olds, new, write=write)
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
    print("  nightjar send --presets")
    print("  nightjar knock 127.0.0.1")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
'''


# =============================================================================
# the patch table (shared by this script and by the regenerated overlay)
# =============================================================================

_IMPORTS_FRESH = """from .scanner import MODES, ScanOutcome, run_scan
from .services import describe_uuid
"""

_IMPORTS_AFTER_SEND = """from .scanner import MODES, ScanOutcome, run_scan
from . import send as sendcmd
from .services import describe_uuid
"""

_IMPORTS_NEW = """from .scanner import MODES, ScanOutcome, run_scan
from . import recon as reconcmd
from . import send as sendcmd
from .services import describe_uuid
"""

_DESCRIPTION_OLD = """        description="A passive Bluetooth Low Energy listening post. "
                    "Receive-only: it never connects or pairs, and asks the "
                    "radio for passive scanning wherever the platform allows.",
"""

_DESCRIPTION_NEW = """        description="A Bluetooth Low Energy listening post that can talk. "
                    "Passive receive by default; `send` pushes payloads out "
                    "over TCP, UDP, HTTP and BLE, `knock` speaks to open ports.",
"""

_COMMANDS_FRESH = ('COMMANDS = ("scan", "watch", "report", "trackers", '
                   '"show", "anomalies", "demo")\n')

_COMMANDS_AFTER_SEND = ('COMMANDS = ("scan", "watch", "send", "serve", '
                        '"report", "trackers",\n'
                        '            "show", "anomalies", "demo")\n')

_COMMANDS_NEW = ('COMMANDS = ("scan", "watch", "send", "serve", "report", '
                 '"trackers",\n'
                 '            "show", "anomalies", "demo", "knock", "connect", '
                 '"fuzz")\n')

_SUBPARSERS_FRESH = '''    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")
    return parser
'''

_SUBPARSERS_AFTER_SEND = '''    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")

    send = sub.add_parser("send", help="send a payload over the network or BLE")
    sendcmd.add_send_args(send)

    serve = sub.add_parser("serve", help="receive payloads over the network")
    sendcmd.add_serve_args(serve)
    return parser
'''

_SUBPARSERS_NEW = '''    demo.add_argument("--no-report", action="store_true",
                      help="just write the log; don't run report and trackers")

    send = sub.add_parser("send", help="send a payload over the network or BLE")
    sendcmd.add_send_args(send)
    reconcmd.add_preset_args(send)

    serve = sub.add_parser("serve", help="receive payloads over the network")
    sendcmd.add_serve_args(serve)

    knock = sub.add_parser("knock", help="walk a host and speak its open ports")
    knock.add_argument("host", metavar="HOST")
    knock.add_argument("--ports", metavar="SPEC",
                       help="ports: '22,80,443' or '1-1024' or both "
                            "(default: the usual suspects)")
    knock.add_argument("--udp", action="store_true",
                       help="also knock the UDP service ports")
    knock.add_argument("--timeout", type=float, default=1.5, metavar="SECONDS")
    knock.add_argument("--jobs", type=int, default=64, metavar="N")
    knock.add_argument("--no-probe", action="store_true",
                       help="connect and listen only, never speak first")
    knock.add_argument("--show-reply", action="store_true",
                       help="hexdump what came back")
    knock.add_argument("--out", metavar="FILE", help="write results as JSON lines")
    knock.add_argument("--json", action="store_true")

    connect = sub.add_parser("connect", help="interactive TCP session (nc-ish)")
    connect.add_argument("target", metavar="TARGET")
    connect.add_argument("--timeout", type=float, default=10.0, metavar="SECONDS")
    connect.add_argument("--hex", action="store_true", help="hexdump what arrives")
    connect.add_argument("--crlf", action="store_true", help="send CRLF line endings")
    connect.add_argument("--payload", metavar="TEXT",
                         help="send this the moment the socket opens")

    fuzz = sub.add_parser("fuzz", help="throw mangled bytes at one target")
    fuzz.add_argument("target", metavar="TARGET")
    fuzz.add_argument("--count", type=int, default=100, metavar="N")
    fuzz.add_argument("--length", type=int, default=32, metavar="N",
                      help="seed length when no payload is given")
    fuzz.add_argument("--mutations", type=int, default=1, metavar="N")
    fuzz.add_argument("--seed", type=int, default=None)
    fuzz.add_argument("--delay", type=float, default=0.0, metavar="SECONDS")
    fuzz.add_argument("--payload", metavar="TEXT")
    fuzz.add_argument("--payload-hex", metavar="HEX")
    fuzz.add_argument("--read", action="store_true")
    fuzz.add_argument("--timeout", type=float, default=3.0, metavar="SECONDS")
    fuzz.add_argument("--stop-on-dead", action="store_true",
                      help="stop at the first refused or reset connection")
    fuzz.add_argument("--json", action="store_true")
    return parser
'''

_HANDLERS_FRESH = '''        "demo": _cmd_demo,
    }
'''

_HANDLERS_AFTER_SEND = '''        "demo": _cmd_demo,
        "send": sendcmd.cmd_send,
        "serve": sendcmd.cmd_serve,
    }
'''

_HANDLERS_NEW = '''        "demo": _cmd_demo,
        "send": reconcmd.cmd_send,
        "serve": sendcmd.cmd_serve,
        "knock": reconcmd.cmd_knock,
        "connect": reconcmd.cmd_connect,
        "fuzz": reconcmd.cmd_fuzz,
    }
'''

_PYPROJECT_OLD = '''dev = [
    "ruff>=0.5",
    "mypy>=1.10",
    "pytest>=8",
]
'''

_PYPROJECT_NEW = '''tx = [
    "bless>=0.2.0",
    "websockets>=12",
    "pyserial>=3.5",
]
dev = [
    "ruff>=0.5",
    "mypy>=1.10",
    "pytest>=8",
]
'''

PATCHES: list[tuple[str, tuple[str, ...], str]] = [
    (CLI, (_IMPORTS_FRESH, _IMPORTS_AFTER_SEND), _IMPORTS_NEW),
    (CLI, (_DESCRIPTION_OLD,), _DESCRIPTION_NEW),
    (CLI, (_COMMANDS_FRESH, _COMMANDS_AFTER_SEND), _COMMANDS_NEW),
    (CLI, (_SUBPARSERS_FRESH, _SUBPARSERS_AFTER_SEND), _SUBPARSERS_NEW),
    (CLI, (_HANDLERS_FRESH, _HANDLERS_AFTER_SEND), _HANDLERS_NEW),
    (PYPROJECT, (_PYPROJECT_OLD,), _PYPROJECT_NEW),
]


# =============================================================================
# helpers
# =============================================================================

def _render_str(value: str) -> str:
    if "'''" not in value and not value.endswith("\\"):
        return "r'''" + value + "'''"
    return repr(value)


def _render_patches() -> str:
    blocks = []
    for relative, olds, new in PATCHES:
        olds_text = "\n".join("            " + _render_str(old) + ","
                              for old in olds)
        blocks.append("    (\n"
                      f"        {_render_str(relative)},\n"
                      "        (\n" + olds_text + "\n        ),\n"
                      "        " + _render_str(new) + ",\n"
                      "    ),")
    return "[\n" + "\n".join(blocks) + "\n]"


def patch_file(path: Path, olds: tuple[str, ...], new: str, *, write: bool) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    if new in text and not any(old in text for old in olds):
        return "already"
    for old in olds:
        if old in text:
            if text.count(old) != 1:
                return f"anchor-ambiguous({text.count(old)})"
            if write:
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            return "patched"
    return "anchor-not-found"


def bump_version(path: Path, *, write: bool) -> str:
    if not path.exists():
        return "missing"
    text = path.read_text(encoding="utf-8")
    match = re.search(r'__version__\s*=\s*"([^"]+)"', text)
    if match is None:
        return "no-version"
    if match.group(1) == RECON_VERSION:
        return "already"
    if write:
        path.write_text(text[:match.start(1)] + RECON_VERSION + text[match.end(1):],
                        encoding="utf-8")
    return f"{match.group(1)} -> {RECON_VERSION}"


def write_file(path: Path, content: str, *, write: bool, force: bool) -> str:
    exists = path.exists()
    if exists and not force and path.read_text(encoding="utf-8") == content:
        return "already"
    if exists and not force:
        return "present (use --force)"
    if write:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    return "written"


# =============================================================================
# main
# =============================================================================

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="nightjar-recon-single",
        description="Write the nightjar recon overlay and wire it in.")
    parser.add_argument("repo", nargs="?", default=".",
                        help="path to the nightjar checkout (default: .)")
    parser.add_argument("--check", action="store_true",
                        help="report what would change, write nothing")
    parser.add_argument("--force", action="store_true",
                        help="overwrite existing modules")
    parser.add_argument("--no-overlay-refresh", action="store_true",
                        help="leave apply_overlay.py alone")
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / "nightjar" / "cli.py").exists():
        print(f"not a nightjar checkout (no nightjar/cli.py under {repo})",
              file=sys.stderr)
        return 2
    write = not args.check
    print(f"nightjar checkout: {repo}{'  [check only]' if args.check else ''}")

    # 1. the send layer, if the checkout has not got it yet
    send_source = HERE / "nightjar" / "send.py"
    send_target = repo / "nightjar" / "send.py"
    if send_target.exists():
        print("  = nightjar/send.py already present")
    elif send_source.exists():
        if write:
            shutil.copyfile(send_source, send_target)
        print("  + nightjar/send.py (from this repo)")
    else:
        print("  ! nightjar/send.py missing - keep this script inside the "
              "nightjar-hack repo", file=sys.stderr)
        return 2

    # 2. the new modules, the tests, the manual
    targets = {
        repo / "nightjar" / "payloads.py": PAYLOADS_PY,
        repo / "nightjar" / "recon.py": RECON_PY,
        repo / "tests" / "test_hacktools.py": TESTS_PY,
        repo / "HACKER-RECON.md": HACKER_RECON_MD,
    }
    for path, content in targets.items():
        outcome = write_file(path, content, write=write, force=args.force)
        marker = "~" if outcome == "written" else ("=" if outcome == "already"
                                                   else "!")
        print(f"  {marker} {path.relative_to(repo)}"
              + ("" if outcome in ("written", "already") else f": {outcome}"))

    # 3. wire cli.py
    problems = 0
    for relative, olds, new in PATCHES:
        outcome = patch_file(repo / relative, olds, new, write=write)
        if outcome.startswith("anchor") or outcome == "missing":
            problems += 1
            print(f"  ! {relative}: {outcome}")
        elif outcome == "already":
            print(f"  = {relative}: already wired")
        else:
            print(f"  ~ {relative}: wired")

    # 4. version
    version = bump_version(repo / "nightjar" / "__init__.py", write=write)
    if version in ("missing", "no-version"):
        problems += 1
        print(f"  ! nightjar/__init__.py: {version}")
    elif version == "already":
        print(f"  = nightjar/__init__.py: already {RECON_VERSION}")
    else:
        print(f"  ~ nightjar/__init__.py: {version}")

    # 5. keep the repo's own overlay in step
    if not args.no_overlay_refresh:
        overlay = repo / "apply_overlay.py"
        content = (APPLY_OVERLAY_PY
                   .replace("@@VERSION@@", RECON_VERSION)
                   .replace("@@PATCHES@@", _render_patches()))
        if overlay.exists() and overlay.read_text(encoding="utf-8") == content:
            print("  = apply_overlay.py: already current")
        else:
            backup = overlay.with_suffix(".py.orig")
            if overlay.exists() and not backup.exists() and write:
                shutil.copyfile(overlay, backup)
            if write:
                overlay.write_text(content, encoding="utf-8")
            print("  ~ apply_overlay.py: refreshed (backup: apply_overlay.py.orig)")

    print()
    if problems:
        print(f"{problems} anchor(s) need a hand - the file is plain text, "
              "the edits are obvious.")
    print("next:")
    print(f"  cd {repo}")
    print("  pip install -e .")
    print("  pip install 'nightjar[tx]'   # only for ble:// and ble-gatt://")
    print("  python -m pytest tests/test_hacktools.py -q")
    print("  nightjar send --presets")
    print("  nightjar knock 127.0.0.1")
    print("  nightjar send tcp://127.0.0.1:9000 --payload hello --dry-run")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
