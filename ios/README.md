# nightjar-hack for iOS — 4.2.0

The unpure build. This is the nightjar listening post — the same
receive-only scanner, decoders and session logs as the app in
`chasebryan/nightjar` (`ios/` there) — **plus the mouth**: the send and
serve payload tools from nightjar-hack, as native iOS tabs — **plus a
recon bench**: the Scan tab, a pentester's pocket kit for your own
gear and your written engagements.

- **Listen** (the purist half) — copied from upstream nightjar and
  unchanged where it counts: `ListeningPost` still only ever calls
  `scanForPeripherals`/`stopScan`. It never connects, pairs or
  transmits, and it shares no radio state with the transmitting half.
  Sessions are the same JSONL format; they feed the same
  `nightjar report` / `nightjar trackers` on the Mac. The live list
  is calmer and richer than a raw feed: ordering follows an
  exponentially smoothed RSSI, re-ranked every 5 s with a 3 dB
  challenge margin, so devices hold their positions and drift
  with the perimeter instead of dancing on per-packet jitter
  (contents still refresh every second). Rows carry the range
  band, a rough distance estimate (from TX power and the
  smoothed signal), sighting counts, closest-ever RSSI and a
  rotating-address flag, and tapping a device opens its full
  file — every decoded detail, maker, signal history sparkline,
  first/last heard, dwell and rate, advertised services, and the
  identifier, with the write-a-payload handoff a tap away.
- **Send** — payloads out, like `nightjar send`: TCP, UDP, TLS-wrapped
  TCP, HTTP(S) (any method, payload-in-query for GET/HEAD), BLE
  advertisement beacons, a hosted GATT characteristic, and BLE writes
  to a peripheral you pick from a scan. Payload sources: text, hex,
  base64. Transforms: XOR, gzip. Framing: raw, len-prefix, JSON
  envelope. Replies are shown as hexdumps, like the CLI.
- **Serve** — payloads in, like `nightjar serve`: TCP, UDP and HTTP
  listeners with a fixed or echo reply, an inbox of everything
  received (shareable as JSONL), plus GATT writes that arrive while
  the Send tab is hosting a characteristic.

New in this build, from nightjar 2.2: **drone detection**. The Listen
tab decodes FAA Remote ID broadcasts (Open Drone ID over BLE,
service 0xFFFA) — a drone in earshot shows as `Drone <serial>` with
its status, altitude, speed and its operator's broadcast position in
the details. The decoder is a Swift port of `nightjar/remoteid.py`
and shares test vectors with it.

## How the Send tab flows

Three numbered steps, in order: **1 · Destination** (a nearby phone
by name — never your own phone, which is filtered out — or a typed
target, with your recent addresses one tap away), **2 · Payload**
(the library as a scrollable dropdown sheet — search, tap to load,
swipe to delete, save-your-current at the bottom — with a collapsed
custom builder underneath, and a live preview of the exact bytes
about to go out), **3 · Send** (one big button that names its
target, and the last reply printed right under it the moment it
lands). The mouth's log lives behind the scroll-icon button in the
corner, not in the form. Everything narrates itself: sends, replies,
failures, listener starts, and toggles raise a small popup that
explains what just happened and fades on its own, and every button
and selection buzzes under your thumb. The Serve tab tells you the
name other phones see (or, in stealth, the exact `tcp://` address
you're reachable at), and inbox rows long-press to copy as text or
hex. Send-side settings persist like Serve's do.

Below the steps, the Send tab keeps working:

- **Send to many.** One payload, a whole list of targets — typed or
  pasted, imported from a .txt/.csv, harvested from the Scan tab, or
  expanded from a range like `192.168.1.10-40:6379` (up to 300).
  Fires sequentially with per-target ✓/✗ results; every exchange
  is logged like a single send. Nearby phones join the list as
  `phone:NAME` entries.
- **Templating.** `{{host}}`, `{{port}}`, `{{ip}}`, `{{target}}` and
  `{{scheme}}` in any payload source resolve per destination before
  the bytes are built — in fan-out, each target gets a payload
  addressed to itself.
- **Timed delivery.** Fire after a delay, or repeat every N
  seconds for X rounds, for both the step-3 send and fan-out —
  with a live countdown and a cancel button. Timers run while the
  app is open; iOS suspends background apps, and the section says
  so.
- **Centipede.** A route, walked hop by hop: each line of the
  route is a stop — a target, a range, `host:80,443` (a port
  train), or a bare host (a train across the usual scan ports).
  In **Chain** mode each hop sends the previous hop's reply, so
  the payload evolves as it travels; **Seed** mode sends the
  step-2 payload at every stop. *Return to sender* walks the
  route back in reverse, and whatever the creature is carrying
  at the end comes home — shown on a homecoming card, logged to
  history, and optionally delivered once to a target you name.
  A stop button calls it home early. The route can be loaded
  from the Scan tab's hits, nearby phones, or the fan-out list —
  or from its **built-in discovery sweep**, which knocks a
  short list of common ports (80, 443, 22, 445, 62078, 8080
  by default, editable) across a /24 — 32 knocks at a time —
  and loads every answering host into the route as a port
  train over the ports it answered on. The phone's own subnet
  is the default; any /24 can be named in the subnet field.
  With **smart seed** on, fresh hops speak the library probe
  that matches their port (a real Redis PING, an EHLO, an HTTP
  GET) instead of the generic payload; every reply the walk
  hears is kept in a **harvest** list on the homecoming card
  and in the history, and each trail line carries its hop's
  round-trip time. The Send tab's feature sections — Send to
  many, Timed delivery, Centipede, SnatchSteal, PayPlant —
  fold open and shut from their headers, and the tab remembers
  which ones you left open. Releasing the centipede plays a
  full-screen flourish for the GIF's own length — a glitching,
  laughing skull (Chase's own `centipede.gif`, kept in the
  app folder; tap to skip) — while the walk's first hops run
  underneath. **Crosstalk** patches two doors together and
  lets them talk: door A is knocked (its port's probe under
  smart seed), its reply is carried verbatim to B, B's reply
  back to A — alternating until silence, an echo, a repeat,
  or the chosen rounds (1–12) run out. Any route-parser
  target can be a door — TCP, UDP, TLS, HTTP(S), other
  phones — and a train or range speaks through its first
  door; one-tap buttons seat this phone's own Serve at
  either end. The transcript, with timings and reply
  summaries, stays on screen and in the history, and the
  conversation's last word gets its own card.
  A *this phone* button adds the phone's own Serve endpoint
  as a guaranteed-live first target. **Per-device mode** gives
  every device in the list its own out-and-back walk (the
  chain resets at each device).
  Every send on both legs is made by the phone; nothing is
  installed or left running on any target.
- **Network Trace.** The Centipede's map-making mode. Name
  one /24 (blank = this phone's) and start a foreground
  trace: every address is knocked on the discovery ports,
  every answering host is profiled across the usual ports
  with banners grabbed, every open door is spoken to with
  its library probe, and every endpoint a banner or reply
  *references* — an IP:port in a page, a redirect target —
  is queued and explored in turn, three levels deep, until
  the frontier is exhausted and the trace stops itself.
  References outside the named /24 are recorded as leads
  and never contacted; Bonjour services join the map.
  **Adaptive rules** steer the trace and ordinary walks
  alike — `contains Redis => followup Redis PING (RESP)`,
  `contains HTTP => tag web`, `contains SSH => stop`: a
  follow-up sends a second, chosen probe to the same door,
  a tag sticks to the device's dossier, and stop keeps
  that reply out of the chain. All of it feeds a persistent
  **crawl logbook** of per-host dossiers, and each trace
  exports a downloadable JSON map (hosts, services, a
  node/edge graph, the diff against the logbook, and a
  limitations block) in a versioned schema for other
  tools to ingest. **Trace & set up the Centipede** runs
  the trace and then loads every door it found as the
  Centipede's route — one port train per host — so the
  map becomes a walk with no manual configuration. New in
  2.6.0: the map (schema v2) and the logbook also file the
  **Bluetooth devices the Listen tab heard** during the run
  — passive sightings, never probed — and the whole
  Send-side setup (scope, ports, rules, route) saves as a
  named **preset** you can apply, share, and import. The
  Listen tab itself decodes more of the air in 2.6.0 —
  Xiaomi MiBeacon, BTHome v2, Govee, RuuviTag formats 3
  and 5, AltBeacon, Swift Pair, Tile, SwitchBot, SmartTags
  — so fewer rows read "unknown device". A trace export
  opens beautifully in `tools/trace-view/` in the repo.
- **SnatchSteal.** The receive-side weapon: knock on the step-1
  target with the step-2 payload (or don't knock at all), then
  drain *everything* it sends back — until it closes, a 15-second
  cap, or 64 KB in the bag. The haul lands on a loot card (bytes,
  text, hexdump) and in the history.
- **PayPlant.** Leave a payload living on a target: an MQTT
  **retained** publish (the broker serves it to every future
  subscriber), a Redis `SET`, or a memcached `set` — wire formats
  built byte-exact in `PayloadKit`. Redis plants get a one-tap
  Verify that `GET`s the key back. It plants only where a service
  is built to store what you hand it; there is no mode that
  installs software on a machine running nothing cooperative.

## Also in the app

- **The look — and the boot.** The Jolly Roger flies behind
  everything: forms and lists are transparent over the backdrop
  (dimmed slightly for readability) and the app is pinned to dark
  appearance to match. The image itself is an asset-catalog
  imageset named `AppBackground`, added in Xcode — binaries can't
  ride the repo connector, the same reason the app icon moved by
  hand. And it boots like an OS: black splash, the flag as an
  emblem card over the wordmark, and a terminal boot log that
  types itself over a progress bar — every line true (this device,
  this Wi-Fi address, this library's real payload count, this
  stealth state), tap to skip, fading into the app in ~2 seconds.
- **The Scan tab.** A "This network" panel (SSID where iOS offers
  it, your IP, the /24, a one-tap likely-gateway target); a TCP
  connect scanner over the usual 28 ports (or your own list) with
  banner grabbing; a **subnet sweep** that knocks on one port
  across all 254 addresses; an **observation feed** that re-sweeps
  on an interval and streams the diffs — hosts answering, hosts
  going dark, Bonjour services appearing and vanishing — into a
  timestamped timeline; a TLS certificate inspector that reads the
  chain out of a real handshake (system trust verdict, subjects,
  validity windows parsed out of the certificate DER by hand,
  because iOS exposes no API for them); a **DNS toolkit** that
  sends a real query over UDP and parses the answers locally (A,
  AAAA, MX, NS, CNAME, TXT); a Bonjour sweep whose rows **resolve
  to IP:port on tap**; and a **pcap dissector** that takes apart
  classic `.pcap` files recorded on your own machines (Ethernet,
  IPv4/IPv6, TCP flags, UDP, ICMP, ARP, payload previews) in
  plain text. Tapping any open port — from a scan or a sweep —
  loads it, plus the library probe that speaks its language,
  straight into the Send tab. Connect scans only: iOS gives apps
  no raw sockets, so no SYN or UDP scans and no monitor mode —
  the Send tab remains the UDP tool.
- **History, and deleting it.** Every send, reply, scan, sweep,
  DNS lookup, snatch and dissection is written to a persistent
  exchange history (`exchanges.jsonl`), exportable from the mouth
  log sheet: what was probed, when, and what answered. The same
  sheet deletes the file outright (size shown, confirmation
  required); the send log and the Serve inbox clear from their
  own buttons, as does the observation feed. The purist half's
  recordings get the same treatment in the Sessions tab: a
  storage total, swipe / long-press / Edit-mode multi-select
  deletion, and a Delete-all that shows the count and size
  first — the session recording right now is never deleted.
- **Payload library.** The Send tab saves named payloads (source,
  transforms, framing included) and loads them back in one tap. It
  ships preloaded with built-ins: the basics (hello, ping, a JSON
  hello, a Wake-on-LAN template, a raw HTTP GET, a 32-byte length
  test) plus real protocol first words — a DNS query, an NTP time
  request, Redis PING, memcached stats, SMTP EHLO, an MQTT CONNECT,
  a Modbus read, a CoAP GET, a raw printer test page, an SNMP
  sysDescr get, a SIP OPTIONS, a Postgres SSLRequest, and an HTTP
  OPTIONS. Deletable, restorable, and side by side with your own
  customs.
- **Listen → Send.** Long-press a device in the Listen tab and choose
  "Write a payload…" — the Send tab opens with that device as the
  write target. The halves share the CoreBluetooth identifier only;
  the listener's radio state is untouched.
- **Shortcuts.** A "Send a payload" action for Shortcuts and Siri
  sends a text payload to a tcp/udp/http target without opening the
  app (BLE targets need the app's UI, and the action says so).
- **Phone to phone, painlessly.** With serving started, a phone
  advertises itself over Bonjour (`_nightjar._tcp`); the Send tab
  lists nearby phones by name — tap one and the payload goes, no IP
  addresses anywhere. Arrivals also banner as a local notification
  with the message text, and the Send target and Serve settings are
  remembered between launches, so receiving is: open, Serve, Start.
- **Arm once (Bluetooth).** The socket listeners still need the app
  in front of you, but the GATT host's physics are different: start
  it once and it stays armed — hosting continues in the background,
  the arm persists across relaunches (peripheral state restoration),
  and a write to it lands in the inbox and banners like any arrival.
  That makes the BLE route the "always set up" one.
- **Stealth mode** (Serve tab). Full function, no announcement:
  the TCP listener drops its Bonjour listing (reachable by IP
  address only, like the CLI — which never listed itself anywhere),
  arrivals go to the inbox silently, and even the notification
  permission ask is deferred. Toggling it while serving restarts
  the listeners so it takes effect immediately. BLE hosting still
  advertises, because a thing that cannot be found cannot be
  connected to.
- **Authorized use** (About tab). The app is a testing instrument
  for devices and networks you own, or that you are engaged in
  writing to test; the About tab carries the statement in full.

## Honest platform limits

iOS is not Linux with a fruit logo. What differs from the CLI, and why:

- **Foreground only for the mouth.** iOS suspends an app's listeners
  and advertisements when it leaves the screen, and a Personal Team
  build gets no say in it. Beacons and servers stop being reachable
  in the background (the BLE GATT arm above is the one exception —
  the OS wakes the app for writes). The Listen tab keeps its
  background hearing (state restoration + the tracker-service list),
  exactly like upstream — the two halves have different physics and
  the app says so.
- **No raw sockets, ever.** No SYN scans, no UDP scans, no ARP
  anything, no packet injection or capture from the app itself —
  captures are made on real machines and dissected here.
- **No manufacturer-data stamping.** Python's `ble://` also writes the
  payload into manufacturer data; iOS gives apps no API to set
  manufacturer data in an advertisement. The payload rides in
  **service data for FFF0** instead — the one payload slot iOS offers.
  Keep beacons small (~20 bytes); iOS advertisement space is tight.
- **No MAC addresses.** iOS hides them, for sending as for listening:
  `ble-write://AA:BB:…` becomes "scan and tap the device" here.
- **SSID is best-effort.** Reading the Wi-Fi name needs an
  entitlement a sideloaded build may not carry; where iOS withholds
  it, the "This network" panel simply omits the row.
- **First tap on "Scan for devices"** may report Bluetooth is not
  ready while the radio warms up; tap again.
- **Local network permission.** The first listener (or LAN send)
  triggers iOS's local-network prompt; that's what
  `NSLocalNetworkUsageDescription` in `Support/Info.plist` is for.
- **App icon.** The icon is a photo of a great eared nightjar,
  cropped square on the face. Its file (`IMG_1434.png`) lives in the
  AppIcon set; the same PNG also sits at the repo root as uploaded.

## Install (sideload, same as upstream)

1. Clone this repo, open `ios/nightjar.xcodeproj` in Xcode.
2. Select the `nightjar` target → Signing & Capabilities → check
   *Automatically manage signing* and pick your Personal Team.
   The bundle ID is `net.nosuchmachine.nightjarhack`, so this app
   installs **alongside** the purist nightjar, not over it.
3. Plug in the phone, trust the computer, enable Developer Mode
   (Settings → Privacy & Security → Developer Mode), press Run.
4. On the phone: Settings → General → VPN & Device Management →
   trust your developer certificate. Free signing lasts 7 days;
   re-running from Xcode re-signs and keeps all data and logs.

## Layout

Same shape as upstream, on purpose (the folder is even still called
`nightjar/` — the Xcode target didn't change, only its bundle ID and
display name, so upstream muscle memory and the synchronized-folder
project keep working):

- `nightjar/ListeningPost.swift`, `Sighting.swift`, `JSONL.swift`,
  `SessionStore.swift`, `Continuity.swift`, `Vendors.swift` — the
  purist core, upstream code (two one-line exceptions: the state
  restoration identifier is namespaced to this app, and the update
  checker watches this repo).
- `nightjar/Identify.swift`, `Services.swift` — upstream, plus the
  Remote ID branch and a `preferredLabel` so a drone's row is named
  by its serial.
- `nightjar/Drones.swift` — the Remote ID decoder (new).
- `nightjar/Mouth.swift`, `MouthView.swift` — the mouth: payload
  construction, transports, listeners, fan-out, scheduling,
  snatching, planting, and the Send/Serve tabs (new).
- `nightjar/ReconView.swift` — the Scan tab: scanner, sweep, feed,
  TLS and DNS tools, Bonjour resolution, pcap dissector (new).
- `nightjar/Feedback.swift` — the narration toasts, the haptics,
  the Jolly Roger backdrop, and the boot splash (new).
- `nightjarTests/` — upstream decoder/log tests, plus `DroneTests`
  (vectors shared in spirit with `tests/test_remoteid.py`),
  `HackTests` (payloads, framing, target parsing) and
  `PayloadBookTests` (the library, its built-ins and their shapes).

The app is built and run on a real iPhone from this repo,
continuously — the features above are described from the running
build, not from intentions. Xcode remains the compiler of record:
the Swift is written in a Linux VM with no Xcode in it, so the
first build of a given change may surface a small, local error;
the fix follows in the next commit, and the burn-down so far has
never taken more than two rounds.

## Recon (2.7.0)

A **Recon** tab, beside Send and Serve: knock, connect, fuzz, over a
library of wire-exact protocol first words.

- **Knock** — every port the library can name, each knocked with the
  protocol that port expects. A star means the reply carried the
  protocol's own tell, so the port is *identified*, not merely open.
  Tap a hit to load it into Send.
- **Connect** — a console against one target, with hexdump rendering
  for binary replies.
- **Fuzz** — seven mutators, a reproducible seed, a reply digest per
  round.
- **Library** — 105 probes over 78 TCP and 14 UDP ports, with one
  button to add every one to the payload library so they are sendable
  by hand from the Send tab too.

The Listen tab is untouched: the ear still never connects. The same
library is mirrored into the Python CLI (`nightjar send --preset`,
`nightjar knock`) for parity, and the manual is
[HACKER-RECON.md](../HACKER-RECON.md).
