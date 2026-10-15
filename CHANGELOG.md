# Changelog

## Unreleased

- **Centipede (iOS Send).** A route walked hop by hop: each
  route line is a target, a range, `host:80,443` (a port train),
  or a bare host (a train across the usual ports). Chain mode
  feeds each hop the previous hop's reply; Seed mode sends the
  same payload everywhere. *Return to sender* walks the route
  back in reverse; the final carried payload comes home to a
  homecoming card, the history, and — optionally — one delivery
  to a target you name. The phone makes every send on both legs.
  The route loads from Scan hits, nearby phones, or the fan-out
  list, and per-device mode gives every device in the list its
  own walk, the chain resetting at each device. A built-in
  discovery sweep feeds the route: a short list of common
  ports knocked across a /24 (the phone's own by default, or
  any named /24), each answering host arriving as a port train
  over the ports it answered on — plus a one-tap target for
  the phone's own Serve endpoint. Smart seed makes fresh hops
  speak their port's library probe; every reply is kept in a
  harvest list (homecoming card + history); trail lines carry
  per-hop round-trip times. (The crawl/discovery code also
  moved from Mouth.swift into a new Crawl.swift extension.)
  The Send tab's feature sections now fold open and shut from
  their headers, with the open set remembered between launches.
  Releasing the centipede plays a full-screen GIF — a
  glitching, laughing skull (Chase's own, kept in the project
  as `centipede.gif`; the splash lasts the GIF's own ~2 s;
  tap to skip; a built-in fallback covers a missing asset).
  Fixed: centipede hops reported "no reply" even for
  servers that answered. The send pump's finish() fired the
  caller's completion BEFORE noting the reply, so the crawl
  — which reads the reply channel from its completion —
  always looked too early. (An earlier theory blamed the
  published value's main-queue lag; that lag was real but
  secondary, and replies are now also mirrored synchronously
  under a lock.) finish() now notes and logs the reply
  first, completion last — the invariant the HTTP send path
  already kept.
  New: **Crosstalk** in the Send tab. Two doors — any targets
  the route parser accepts (TCP, UDP, TLS, HTTP(S), phones;
  trains and ranges speak through their first door) — are
  patched together: A is knocked with its port's probe (smart
  seed) or the step-2 payload, its reply is carried verbatim
  to B, B's reply back to A, for up to 12 rounds, ending on
  silence, a verbatim echo, or a repeated reply. One-tap
  buttons seat the phone's own Serve at either door. The
  transcript (timings + reply summaries) is shown live,
  logged to history, and the last word is carded like a
  homecoming. The centipede and Crosstalk refuse to run at
  the same time — they share the reply channel.
  Listen tab fleshed out (collection untouched — still
  receive-only; this is ordering and presentation). Rows are
  ordered by an exponentially smoothed RSSI, re-ranked every
  5 s with a 3 dB challenge margin, so the list settles and
  drifts with the perimeter instead of re-sorting on raw
  per-packet jitter every second; contents still refresh
  every tick. Device rows now also carry the makers, TX
  power, advertised services, a rotating-address flag and a
  rough distance estimate, and tapping a device opens a
  detail page with everything the post knows: all decoded
  details, last/smoothed/closest RSSI, an RSSI-history
  sparkline, first/last heard, dwell, sighting rate, the
  identifier — and the write-a-payload handoff as a button,
  not just a long-press.

## 2.5.0 — 2026-10-15 — the pocket release

### Landed before tagging — the audit fix rounds

A full theoretical audit of the iOS app (every tab, every
transport, every parser, checked against what each claims to do)
followed by two fix rounds. The headline: **the port scan was
broken by a timer race** — open-ness is now latched the moment a
connection succeeds, so silent services on slow connects report
truthfully. Also fixed, among ~45 findings: the observation feed
silently dying when a watch sweep was refused; serve state
desync (stale listeners flipping the global Serving flag,
pre-Stop peers landing in the inbox, live-edited reply config
answering for a running serve — now generation-tracked and
snapshotted); HTTP serve (request-line parsing, HEAD without a
body, chunked bodies, idle timeouts); the timed-delivery cancel
race; fan-out counting HTTP 4xx/5xx as success; PayPlant
claiming success before the plant landed (MQTT plants now do a
real CONNACK handshake, and Verify reads the plant, not the
form); SnatchSteal's soft 64 KB cap and missing idle timeout;
a crafted-BLE-advertisement crash in the drone Message Pack
parser; DNS answers accepted without a transaction-ID check;
the pcap dissector's ARP pairing and Ethernet-padding inventions;
corrupt session logs becoming invisible and undeletable;
PayloadBook wiping customs on a bad decode; BLE beacon/host
state claimed before the radio confirmed it; the byte preview
ignoring templating and framing while calling itself exact;
and a boot log whose status lines are now actually checked
(backdrop asset present, BLE permission, real interface
address). The CLI is untouched; its 41 tests still pass.

### The pocket release proper

*Release notes for the GitHub release: this whole 2.5.0 entry,
verbatim.*

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

### Docs

README.md, HACKER.md and ios/README.md rewritten for the full
feature set; this changelog started. The stale `nightjar-hack.zip`
convenience archive was removed from the repo before tagging —
releases carry GitHub's own source archives; the single-file
build and the bundle are regenerated from source.

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
