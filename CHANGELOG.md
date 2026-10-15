# Changelog

## 2.5.0 — 2026-10-15 — the pocket release

*Release notes for the GitHub release: this entry, verbatim.*

The iOS app grows from a merged companion into a full field unit,
and the overlay version moves to 2.5.0 to mark it. The CLI gains
no new commands this round; its docs were overhauled with the rest.

### iOS — Send

- **Scan → Send handoff**: tapping an open port in the scanner or
  the sweep loads the target *and* the library probe that speaks
  its language (Redis PING for 6379, Postgres SSLRequest for 5432,
  EHLO for 25, Modbus for 502, and so on) straight into Send.
- **Fan-out**: one payload to many targets — typed, pasted,
  imported from .txt/.csv, harvested from scans, nearby phones as
  `phone:NAME`, or ranges (`192.168.1.10-40:6379`, cap 300) —
  sequential, per-target ✓/✗, fully logged.
- **Templating**: `{{host}} {{port}} {{ip}} {{target}} {{scheme}}`
  resolve per destination inside any payload source.
- **Timed delivery**: delay and repeat scheduling for single sends
  and fan-out, with countdown and cancel.
- **SnatchSteal**: knock (or don't), then drain everything the
  target sends back — 15 s / 64 KB caps — onto a loot card and
  into the history.
- **PayPlant**: byte-exact MQTT retained publish, Redis SET and
  memcached set builders; Redis plants verify with a GET. Plants
  only where a service is built to store what you hand it.

### iOS — Serve

- **Echo reply mode** alongside the fixed reply (TCP/UDP/HTTP).
- Everything from the night's earlier rounds holds: Bonjour
  phone discovery, notification banners, stealth mode, arm-once
  BLE GATT hosting with state restoration, @AppStorage settings.

### iOS — Scan

- **Subnet sweep**: one port knocked across the whole /24,
  32 at a time; hits feed Send and fan-out.
- **Observation feed**: interval re-sweeps and Bonjour diffs
  streamed into a timestamped timeline — hosts answering, hosts
  going dark, services coming and going. Sessions are written
  to the history when the watch stops.
- **This network** panel: SSID (best-effort), own IP, gateway
  one-tap target.
- **Bonjour tap-to-resolve**: discovered services resolve to
  IP:port and load into Send.
- **DNS toolkit**: real UDP queries to 1.1.1.1, answers parsed
  locally (A/AAAA/MX/NS/CNAME/TXT, compression-aware).
- **Pcap dissector**: classic libpcap taken apart in plain text —
  Ethernet/VLAN/SLL/raw/loopback, IPv4/IPv6, TCP flags, UDP,
  ICMP(v6), ARP, payload previews. Captures are made on your own
  machines; the phone dissects.
- Scans, sweeps, DNS answers and dissections join the exchange
  history.

### iOS — the shell

- **Boot splash**: an OS-style black boot — Jolly Roger emblem,
  wordmark, a self-typing boot log whose lines are all true
  (device, Wi-Fi address, library size, stealth state), progress
  bar, tap to skip.
- **Data control**: the log sheet deletes the exchange-history
  file (size shown, confirmation required); send log, Serve
  inbox and observation feed each clear from their own buttons.
  The Sessions tab manages the listening post's recordings the
  same way — storage total, swipe / long-press / multi-select
  deletion, and a confirmed Delete-all; the live session is
  always protected.
- **About** carries an authorized-use statement: a testing
  instrument for devices and networks you own or are engaged in
  writing to test.

### Considered and refused (the boundaries are features)

- **HULK / HTTP flooding** — denial of service is not recon.
- **ARP poisoning / traffic interception feeds** — also
  impossible from an iOS app (no raw sockets, no link-layer
  access), and a man-in-the-middle on other people's traffic
  regardless of framing. The observation feed watches what the
  phone can see for itself.
- **A planted packet-capture implant** — a wiretap on a target
  device that exfiltrates traffic to its planter. Same shelf.
- **Wi-Fi deauth / evil twin / handshake cracking** — impossible
  on iOS and aimed at other people's networks besides.

### Docs

README.md, HACKER.md and ios/README.md rewritten for the full
feature set; this changelog started. `nightjar-hack.zip` is a
convenience archive refreshed by hand in the web UI; the
single-file build and the bundle are regenerated from source.

## 2.4.0 — 2026-10-15

- CLI: WebSocket (`ws://`/`wss://`, `serve --ws`) and serial
  (`serial://DEVICE?baud=N`, `serve --serial`) transports;
  fan-out multi-target sends; `--expect`/`--expect-hex` reply
  assertions (exit 1 on mismatch); `--follow FILE`; `--replay`
  of `serve --out` recordings with timing; serve reply modes
  (`--reply-mode echo|file`); `--relay` logging tap.
- iOS: payload library, Listen → Send write handoff, Shortcuts /
  Siri "Send a payload" intent; then the full UX rework (numbered
  send flow, toasts + haptics, stealth address readout), the Scan
  tab (connect scanner, TLS inspector, Bonjour sweep), persistent
  exportable exchange history, the Jolly Roger backdrop, one-tap
  Bonjour phone-to-phone, notification banners, and arm-once BLE
  hosting. Test suite: 32 → 41, all passing from a fresh clone.

## 2.3.0 — 2026-10-15

- The send/serve overlay itself: TCP/UDP/TLS/HTTP and the three
  BLE roles (beacon, GATT host, central write), payload sources
  and transforms (XOR, gzip), framing (raw, len-prefix, JSON
  envelope), serve recordings and replies, `apply_overlay.py`
  with anchored patches and `--check`, the single-file build,
  and the first test suite.
