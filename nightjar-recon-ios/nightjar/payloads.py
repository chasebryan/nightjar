"""nightjar payloads - protocol first words, wire-exact.

The Python mirror of ios/nightjar/ReconPayloads.swift. `nightjar knock`
speaks the right probe at every open port; `nightjar send --preset NAME`
uses one as a payload and fills in the service's own port when you leave
it off. Keep the two tables in step - tools/parity is the place to prove
it.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from functools import partial
from typing import Callable


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


QTYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12, "MX": 15,
          "TXT": 16, "AAAA": 28, "SRV": 33, "ANY": 255}
QCLASSES = {"IN": 1, "CH": 3, "HS": 4}


def dns_query(qname: str, qtype: str = "A", qclass: str = "IN",
              rd: bool = True, edns: bool = True) -> bytes:
    flags = 0x0100 if rd else 0x0000
    header = struct.pack("!HHHHHH", 0x1234, flags, 1, 0, 0, 1 if edns else 0)
    out = header + _dns_name(qname)
    out += struct.pack("!HH", QTYPES.get(qtype, 1), QCLASSES.get(qclass, 1))
    if edns:
        out += b"\x00" + struct.pack("!HHIH", 41, 4096, 0, 0)
    return out


def nbns_query() -> bytes:
    return (b"\x12\x34\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            + _nbt_name() + struct.pack("!HH", 0x0021, 0x0001))


def ntp_request() -> bytes:
    return b"\x1b" + b"\x00" * 47


def snmp_sysdescr() -> bytes:
    varbind = _ber(0x30, _ber_oid("1.3.6.1.2.1.1.1.0") + _ber(0x05, b""))
    pdu = _ber(0xA0, _ber_int(0x0A0B0C0D) + _ber_int(0) + _ber_int(0)
               + _ber(0x30, varbind))
    return _ber(0x30, _ber_int(0) + _ber(0x04, b"public") + pdu)


def ssdp_msearch() -> bytes:
    return (b"M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
            b'MAN: "ssdp:discover"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n')


def dhcp_discover() -> bytes:
    return (b"\x01\x01\x06\x00" + b"\x12\x34\x56\x78" + b"\x00" * 4
            + b"\x00" * 16 + b"\xde\xad\xbe\xef\x00\x01" + b"\x00" * 10
            + b"\x00" * 64 + b"\x00" * 128 + b"\x63\x82\x53\x63"
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


def mqtt_connect(client_id: str = "nightjar") -> bytes:
    body = _mqtt_str("MQTT") + bytes([4, 0x02]) + struct.pack("!H", 60)
    body += _mqtt_str(client_id)
    return b"\x10" + _mqtt_remaining(len(body)) + body


def mqtt_publish(topic: str = "nightjar", payload: bytes = b"alive",
                 retain: bool = True) -> bytes:
    body = _mqtt_str(topic) + payload
    return bytes([0x31 if retain else 0x30]) + _mqtt_remaining(len(body)) + body


def mqtt_plant() -> bytes:
    return mqtt_connect() + mqtt_publish()


def mssql_prelogin() -> bytes:
    options = ((0x00, 6), (0x01, 1), (0x02, 1), (0x03, 4), (0x04, 1))
    offset = len(options) * 5 + 1
    head = b""
    for token, length in options:
        head += bytes([token]) + struct.pack("!HH", offset, length)
        offset += length
    head += b"\xff"
    payload = head + b"\x00" * 6 + b"\x00\x00" + struct.pack("!I", 0x1234) + b"\x00"
    return (b"\x12\x01" + struct.pack("!H", 8 + len(payload))
            + b"\x00\x00\x01\x00" + payload)


def smb1_negotiate() -> bytes:
    dialects = b"".join(b"\x02" + d + b"\x00"
                        for d in (b"NT LM 0.12", b"SMB 2.002", b"SMB 2.???"))
    smb = (b"\xffSMB" + b"\x72" + b"\x00" * 4 + b"\x18" + b"\x53\xc8"
           + b"\x00\x00" + b"\x00" * 8 + b"\x00\x00" + b"\xff\xfe"
           + b"\x00" * 6 + b"\x00" + struct.pack("<H", len(dialects)) + dialects)
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


def mongodb_ismaster() -> bytes:
    body = struct.pack("<i", 0) + b"admin.$cmd\x00" + struct.pack("<ii", 0, -1)
    body += struct.pack("<i", 4 + 12 + 1) + b"\x10ismaster\x00" + struct.pack("<i", 1) + b"\x00"
    return struct.pack("<iiii", 16 + len(body), 1, 0, 2004) + body


def zookeeper_mntr() -> bytes:
    return b"\x00\x00\x00\x04mntr"


def cassandra_options() -> bytes:
    return b"\x04\x00\x00\x00\x05\x00\x00\x00\x00"


def coap_get(path: str = "nightjar") -> bytes:
    out = b"\x40\x01\x30\x39"
    for index, segment in enumerate(path.split("/")):
        out += bytes([((11 if index == 0 else 0) << 4) | len(segment)])
        out += segment.encode()
    return out


def modbus_read() -> bytes:
    return struct.pack("!HHHB", 1, 0, 6, 1) + b"\x03" + struct.pack("!HH", 0, 1)


def ldap_anon_bind() -> bytes:
    return _ber(0x30, _ber_int(1) + _ber(
        0x60, _ber_int(3) + _ber(0x04, b"") + _ber(0x80, b"")))


def adb_version() -> bytes:
    return b"\x00\x00\x00\x0chost:version"


def wol_magic() -> bytes:
    return b"\xff" * 6 + bytes.fromhex("aabbccddeeff") * 16


def zabbix_version() -> bytes:
    body = b'{"request":"agent.version"}'
    return b"ZBXD\x01" + struct.pack("<Q", len(body)) + body


def graphql_introspection() -> bytes:
    body = b'{"query":"{__schema{queryType{name} types{name kind}}}"}'
    return _http("POST", "/graphql",
                 headers=(("Content-Type", "application/json"),), body=body)


def http_get(path: str = "/") -> bytes:
    return _http("GET", path)


def sip_options() -> bytes:
    return (b"OPTIONS sip:nightjar@127.0.0.1 SIP/2.0\r\n"
            b"Via: SIP/2.0/UDP 127.0.0.1:5060;branch=z9hG4bKnj\r\n"
            b"Max-Forwards: 70\r\n"
            b"From: <sip:nightjar@127.0.0.1>;tag=nj\r\n"
            b"To: <sip:nightjar@127.0.0.1>\r\n"
            b"Call-ID: nightjar@127.0.0.1\r\n"
            b"CSeq: 1 OPTIONS\r\n"
            b"Contact: <sip:nightjar@127.0.0.1>\r\n"
            b"Content-Length: 0\r\n\r\n")


def postgres_sslrequest() -> bytes:
    return struct.pack("!II", 8, 80877103)


def postgres_startup() -> bytes:
    params = b"user\x00nightjar\x00database\x00nightjar\x00\x00"
    return struct.pack("!II", 8 + len(params), 196608) + params


def mysql_ping() -> bytes:
    return b"\x01\x00\x00\x00\x0e"


def mysql_query() -> bytes:
    return b"\x01\x00\x00\x00\x03SELECT 1"


@dataclass(frozen=True)
class Probe:
    name: str
    port: int
    proto: str
    family: str
    hint: bytes
    build: Callable[[], bytes]
    tls: bool = False
    summary: str = ""


PROBES: dict[str, Probe] = {}


def _probe(name, port, proto, family, hint, build, *, tls=False, summary=""):
    PROBES[name] = Probe(name, port, proto, family, hint, build, tls,
                         summary or family)


def _register() -> None:
    add = _probe
    add("dns-a", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "A"), summary="A query")
    add("dns-aaaa", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "AAAA"), summary="AAAA query")
    add("dns-mx", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "MX"), summary="MX query")
    add("dns-txt", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "TXT"), summary="TXT query")
    add("dns-any", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "ANY"), summary="ANY query")
    add("dns-version", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "version.bind", "TXT", "CH"), summary="CHAOS version.bind")
    add("dns-sd", 5353, "udp", "mdns", b"\x84\x00", partial(dns_query, "_services._dns-sd._udp.local", "PTR", rd=False, edns=False), summary="mDNS enumeration")
    add("llmnr", 5355, "udp", "llmnr", b"\x80\x00", partial(dns_query, "nightjar", "A", rd=False, edns=False), summary="LLMNR query")
    add("nbns", 137, "udp", "netbios-ns", b"\x84\x00", nbns_query, summary="NBNS node-status")
    add("ntp", 123, "udp", "ntp", b"\x1c", ntp_request, summary="NTP request")
    add("snmp-sysdescr", 161, "udp", "snmp", b"\xa2", snmp_sysdescr, summary="SNMP sysDescr")
    add("ssdp", 1900, "udp", "ssdp", b"HTTP/1.1", ssdp_msearch, summary="SSDP M-SEARCH")
    add("dhcp-discover", 67, "udp", "dhcp", b"\x02\x01\x06", dhcp_discover, summary="DHCP DISCOVER")
    add("tftp", 69, "udp", "tftp", b"\x00\x03", tftp_read, summary="TFTP read")
    add("stun", 3478, "udp", "stun", b"\x01\x01", stun_binding, summary="STUN binding")
    add("syslog", 514, "udp", "syslog", b"", syslog_line, summary="syslog datagram")
    add("wireguard", 51820, "udp", "wireguard", b"\x02", wireguard_init, summary="WireGuard init")
    add("redis-ping", 6379, "tcp", "redis", b"+PONG", partial(_resp, "PING"), summary="PING")
    add("redis-info", 6379, "tcp", "redis", b"# Server", partial(_resp, "INFO"), summary="INFO")
    add("redis-keys", 6379, "tcp", "redis", b"*", partial(_resp, "KEYS", "*"), summary="KEYS *")
    add("redis-set", 6379, "tcp", "redis", b"+OK", partial(_resp, "SET", "nightjar", "was-here"), summary="SET - a plant")
    add("memcached-stats", 11211, "tcp", "memcached", b"STAT", lambda: b"stats\r\n", summary="stats")
    add("memcached-version", 11211, "tcp", "memcached", b"VERSION", lambda: b"version\r\n", summary="version")
    add("memcached-get", 11211, "tcp", "memcached", b"VALUE", lambda: b"get nightjar\r\n", summary="get")
    add("mongodb-ismaster", 27017, "tcp", "mongodb", b"ismaster", mongodb_ismaster, summary="OP_QUERY ismaster")
    add("cassandra-options", 9042, "tcp", "cassandra", b"\x84", cassandra_options, summary="CQL OPTIONS")
    add("couchdb-root", 5984, "tcp", "couchdb", b"CouchDB", http_get, summary="GET /")
    add("elasticsearch-root", 9200, "tcp", "elasticsearch", b"cluster_name", http_get, summary="GET /")
    add("zookeeper-mntr", 2181, "tcp", "zookeeper", b"zk_", zookeeper_mntr, summary="mntr")
    add("etcd-version", 2379, "tcp", "etcd", b"etcdserver", partial(http_get, "/version"), summary="GET /version")
    add("consul-leader", 8500, "tcp", "consul", b'"', partial(http_get, "/v1/status/leader"), summary="status/leader")
    add("vault-health", 8200, "tcp", "vault", b"initialized", partial(http_get, "/v1/sys/health"), summary="sys/health")
    add("mqtt-connect", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_connect, summary="CONNECT")
    add("mqtt-plant", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_plant, summary="CONNECT + retained PUBLISH")
    add("amqp-header", 5672, "tcp", "amqp", b"AMQP", lambda: b"AMQP\x00\x00\x09\x01", summary="AMQP 0-9-1")
    add("stomp-connect", 61613, "tcp", "stomp", b"CONNECTED", lambda: b"CONNECT\naccept-version:1.2\nhost:nightjar\n\n\x00", summary="STOMP CONNECT")
    add("rabbitmq-overview", 15672, "tcp", "rabbitmq", b"rabbitmq_version", partial(http_get, "/api/overview"), summary="management overview")
    add("smtp-ehlo", 25, "tcp", "smtp", b"250", lambda: b"EHLO nightjar.local\r\n", summary="EHLO")
    add("smtp-vrfy", 25, "tcp", "smtp", b"250", lambda: b"VRFY root\r\n", summary="VRFY root")
    add("smtp-quit", 25, "tcp", "smtp", b"221", lambda: b"QUIT\r\n", summary="QUIT")
    add("pop3-capa", 110, "tcp", "pop3", b"+OK", lambda: b"CAPA\r\n", summary="CAPA")
    add("pop3-capa-tls", 995, "tcp", "pop3s", b"+OK", lambda: b"CAPA\r\n", tls=True, summary="CAPA over TLS")
    add("imap-capa", 143, "tcp", "imap", b"CAPABILITY", lambda: b"a1 CAPABILITY\r\n", summary="CAPABILITY")
    add("imap-capa-tls", 993, "tcp", "imaps", b"CAPABILITY", lambda: b"a1 CAPABILITY\r\n", tls=True, summary="CAPABILITY over TLS")
    add("irc-register", 6667, "tcp", "irc", b"001", lambda: b"NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n", summary="NICK/USER")
    add("sip-options", 5060, "tcp", "sip", b"SIP/2.0", sip_options, summary="OPTIONS")
    add("sip-options-tls", 5061, "tcp", "sips", b"SIP/2.0", sip_options, tls=True, summary="OPTIONS over TLS")
    add("rtsp-options", 554, "tcp", "rtsp", b"RTSP/1.0", lambda: b"OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n", summary="RTSP OPTIONS")
    add("postgres-sslrequest", 5432, "tcp", "postgres", b"S", postgres_sslrequest, summary="SSLRequest")
    add("postgres-startup", 5432, "tcp", "postgres", b"R", postgres_startup, summary="startup message")
    add("mysql-ping", 3306, "tcp", "mysql", b"", mysql_ping, summary="COM_PING")
    add("mysql-query", 3306, "tcp", "mysql", b"", mysql_query, summary="COM_QUERY")
    add("mssql-prelogin", 1433, "tcp", "mssql", b"\x04", mssql_prelogin, summary="TDS PRELOGIN")
    add("smb1-negotiate", 139, "tcp", "smb1", b"\xffSMB", smb1_negotiate, summary="SMB1 NEGOTIATE")
    add("smb2-negotiate", 445, "tcp", "smb2", b"\xfeSMB", smb2_negotiate, summary="SMB2 NEGOTIATE")
    add("rpc-null", 111, "tcp", "portmapper", b"\x00\x00\x00\x01", rpc_null, summary="RPC NULL")
    add("rsync-modules", 873, "tcp", "rsync", b"@RSYNCD", lambda: b"@RSYNCD: 31.0\n", summary="version handshake")
    add("ftp-user", 21, "tcp", "ftp", b"331", lambda: b"USER anonymous\r\n", summary="USER anonymous")
    add("ssh-banner", 22, "tcp", "ssh", b"SSH-", lambda: b"", summary="server speaks first")
    add("telnet-negotiate", 23, "tcp", "telnet", b"\xff", lambda: b"\xff\xfd\x03\xff\xfb\x18\xff\xfb\x1f", summary="option negotiation")
    add("vnc-client", 5900, "tcp", "vnc", b"RFB", lambda: b"RFB 003.008\n", summary="client handshake")
    add("rdp-negotiate", 3389, "tcp", "rdp", b"\x03\x00", lambda: b"\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00", summary="TPKT + X.224")
    add("x11-setup", 6000, "tcp", "x11", b"\x01", lambda: b"l\x00\x0b\x00" + b"\x00" * 8, summary="X11 setup")
    add("socks5-greeting", 1080, "tcp", "socks5", b"\x05", lambda: b"\x05\x01\x00", summary="no-auth greeting")
    add("socks4-connect", 1080, "tcp", "socks4", b"\x00\x5a", lambda: b"\x04\x01\x00\x50\x7f\x00\x00\x01nightjar\x00", summary="SOCKS4 CONNECT")
    add("adb-version", 5555, "tcp", "adb", b"OKAY", adb_version, summary="host:version")
    add("ldap-anon-bind", 389, "tcp", "ldap", b"\x61", ldap_anon_bind, summary="anonymous bind")
    add("ldap-anon-bind-tls", 636, "tcp", "ldaps", b"\x61", ldap_anon_bind, tls=True, summary="anonymous bind over TLS")
    add("wol", 9, "udp", "wake-on-lan", b"", wol_magic, summary="magic packet")
    add("coap-get", 5683, "udp", "coap", b"\x60", coap_get, summary="GET /nightjar")
    add("modbus-read", 502, "tcp", "modbus", b"\x00\x01", modbus_read, summary="read holding registers")
    add("zabbix-agent", 10050, "tcp", "zabbix", b"ZBXD", zabbix_version, summary="agent.version")
    add("http-get", 80, "tcp", "http", b"HTTP/1.", http_get, summary="GET /")
    add("http-options", 80, "tcp", "http", b"HTTP/1.", lambda: _http("OPTIONS", "/"), summary="OPTIONS")
    add("http-head", 80, "tcp", "http", b"HTTP/1.", lambda: _http("HEAD", "/"), summary="HEAD /")
    add("http-trace", 80, "tcp", "http", b"HTTP/1.", lambda: _http("TRACE", "/"), summary="TRACE")
    add("https-get", 443, "tcp", "https", b"HTTP/1.", http_get, tls=True, summary="GET / over TLS")
    add("graphql-introspection", 80, "tcp", "graphql", b"__schema", graphql_introspection, summary="POST /graphql")
    add("http-proxy-get", 3128, "tcp", "http-proxy", b"HTTP/1.", lambda: _http("GET", "http://example.com/", host="example.com"), summary="open proxy test")
    add("http-connect", 3128, "tcp", "http-proxy", b"HTTP/1.", lambda: b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n", summary="CONNECT tunnel")
    add("docker-version", 2375, "tcp", "docker", b"ApiVersion", partial(http_get, "/version"), summary="GET /version")
    add("docker-version-tls", 2376, "tcp", "docker", b"ApiVersion", partial(http_get, "/version"), tls=True, summary="GET /version over TLS")
    add("docker-registry", 5000, "tcp", "docker-registry", b"200", partial(http_get, "/v2/"), summary="GET /v2/")
    add("kubernetes-version", 6443, "tcp", "kubernetes", b"gitVersion", partial(http_get, "/version"), tls=True, summary="GET /version")
    add("kubelet-health", 10250, "tcp", "kubelet", b"ok", partial(http_get, "/healthz"), tls=True, summary="GET /healthz")
    add("jenkins-api", 8080, "tcp", "jenkins", b"Jenkins", partial(http_get, "/api/json"), summary="GET /api/json")
    add("prometheus-metrics", 9090, "tcp", "prometheus", b"HELP", partial(http_get, "/metrics"), summary="GET /metrics")
    add("grafana-health", 3000, "tcp", "grafana", b"database", partial(http_get, "/api/health"), summary="GET /api/health")
    add("kibana-status", 5601, "tcp", "kibana", b"version", partial(http_get, "/api/status"), summary="GET /api/status")
    add("solr-admin", 8983, "tcp", "solr", b"lucene", partial(http_get, "/solr/admin/info/system"), summary="admin info")
    add("influxdb-ping", 8086, "tcp", "influxdb", b"204", lambda: b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", summary="GET /ping")
    add("minio-health", 9000, "tcp", "minio", b"200", partial(http_get, "/minio/health/live"), summary="health/live")
    add("neo4j-root", 7474, "tcp", "neo4j", b"neo4j", http_get, summary="GET /")
    add("gitea-version", 3000, "tcp", "gitea", b"version", partial(http_get, "/api/v1/version"), summary="GET /api/v1/version")
    add("gitlab-readiness", 80, "tcp", "gitlab", b"GitLab", partial(http_get, "/-/readiness"), summary="GET /-/readiness")
    add("echo", 7, "tcp", "echo", b"", lambda: b"", summary="nothing - echo")
    add("daytime", 13, "tcp", "daytime", b"", lambda: b"", summary="nothing")
    add("chargen", 19, "tcp", "chargen", b"", lambda: b"", summary="nothing")
    add("discard", 9, "tcp", "discard", b"", lambda: b"nightjar\r\n", summary="throw it away")
    add("whois", 43, "tcp", "whois", b"", lambda: b"example.com\r\n", summary="whois query")
    add("finger", 79, "tcp", "finger", b"", lambda: b"nightjar\r\n", summary="finger")
    add("gopher", 70, "tcp", "gopher", b"", lambda: b"nightjar\r\n", summary="gopher selector")
    add("gemini", 1965, "tcp", "gemini", b"20 ", lambda: b"gemini://nightjar/\r\n", summary="Gemini request")


_register()

PORT_PROBES: dict[int, str] = {
    7: "echo", 9: "discard", 13: "daytime", 19: "chargen", 21: "ftp-user",
    22: "ssh-banner", 23: "telnet-negotiate", 25: "smtp-ehlo", 43: "whois",
    53: "dns-version", 67: "dhcp-discover", 69: "tftp", 70: "gopher",
    79: "finger", 80: "http-get", 110: "pop3-capa", 111: "rpc-null",
    123: "ntp", 137: "nbns", 139: "smb1-negotiate", 143: "imap-capa",
    161: "snmp-sysdescr", 389: "ldap-anon-bind", 443: "https-get",
    445: "smb2-negotiate", 502: "modbus-read", 554: "rtsp-options",
    587: "smtp-ehlo", 636: "ldap-anon-bind-tls", 873: "rsync-modules",
    993: "imap-capa-tls", 995: "pop3-capa-tls", 1080: "socks5-greeting",
    1433: "mssql-prelogin", 1883: "mqtt-connect", 1965: "gemini",
    2181: "zookeeper-mntr", 2375: "docker-version", 2376: "docker-version-tls",
    2379: "etcd-version", 3000: "grafana-health", 3128: "http-proxy-get",
    3306: "mysql-ping", 3389: "rdp-negotiate", 5000: "docker-registry",
    5060: "sip-options", 5061: "sip-options-tls", 5432: "postgres-sslrequest",
    5555: "adb-version", 5601: "kibana-status", 5672: "amqp-header",
    5900: "vnc-client", 5984: "couchdb-root", 6000: "x11-setup",
    61613: "stomp-connect", 6379: "redis-ping", 6443: "kubernetes-version",
    7474: "neo4j-root", 8000: "http-get", 8080: "jenkins-api",
    8086: "influxdb-ping", 8200: "vault-health", 8443: "https-get",
    8500: "consul-leader", 8983: "solr-admin", 9000: "minio-health",
    9042: "cassandra-options", 9090: "prometheus-metrics",
    9200: "elasticsearch-root", 10050: "zabbix-agent",
    10250: "kubelet-health", 11211: "memcached-stats",
    15672: "rabbitmq-overview", 27017: "mongodb-ismaster",
}

PORT_PROBES_UDP: dict[int, str] = {
    9: "wol", 53: "dns-a", 67: "dhcp-discover", 69: "tftp", 123: "ntp",
    137: "nbns", 161: "snmp-sysdescr", 514: "syslog", 1900: "ssdp",
    3478: "stun", 5353: "dns-sd", 5355: "llmnr", 5683: "coap-get",
    51820: "wireguard",
}

DEFAULT_KNOCK_PORTS: tuple[int, ...] = tuple(sorted(PORT_PROBES))


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
