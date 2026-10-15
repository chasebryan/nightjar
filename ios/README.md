# nightjar-hack for iOS

The unpure build. This is the nightjar listening post — the same
receive-only scanner, decoders and session logs as the app in
`chasebryan/nightjar` (`ios/` there) — **plus the mouth**: the send and
serve payload tools from nightjar-hack, as native iOS tabs.

- **Listen** (the purist half) — copied from upstream nightjar and
  unchanged where it counts: `ListeningPost` still only ever calls
  `scanForPeripherals`/`stopScan`. It never connects, pairs or
  transmits, and it shares no radio state with the transmitting half.
  Sessions are the same JSONL format; they feed the same
  `nightjar report` / `nightjar trackers` on the Mac.
- **Send** — payloads out, like `nightjar send`: TCP, UDP, TLS-wrapped
  TCP, HTTP(S) (any method, payload-in-query for GET/HEAD), BLE
  advertisement beacons, a hosted GATT characteristic, and BLE writes
  to a peripheral you pick from a scan. Payload sources: text, hex,
  base64. Transforms: XOR, gzip. Framing: raw, len-prefix, JSON
  envelope. Replies are shown as hexdumps, like the CLI.
- **Serve** — payloads in, like `nightjar serve`: TCP, UDP and HTTP
  listeners with an optional reply, an inbox of everything received
  (shareable as JSONL), plus GATT writes that arrive while the Send
  tab is hosting a characteristic.

New in this build, from nightjar 2.2: **drone detection**. The Listen
tab decodes FAA Remote ID broadcasts (Open Drone ID over BLE,
service 0xFFFA) — a drone in earshot shows as `Drone <serial>` with
its status, altitude, speed and its operator's broadcast position in
the details. The decoder is a Swift port of `nightjar/remoteid.py`
and shares test vectors with it.

## How the Send tab flows

Three numbered steps, in order: **1 · Destination** (a nearby phone
by name, or a typed target), **2 · Payload** (the library as a
scrollable dropdown sheet — search, tap to load, swipe to delete,
save-your-current at the bottom — with a collapsed custom builder
underneath), **3 · Send** (one big button that names its target).
The mouth's log lives behind the scroll-icon button in the corner,
not in the form. Everything narrates itself: sends, replies,
failures, listener starts, and toggles raise a small popup that
explains what just happened and fades on its own, and every button
and selection buzzes under your thumb.

## Also in the app

- **Payload library.** The Send tab saves named payloads (source,
  transforms, framing included) and loads them back in one tap. It
  ships preloaded with built-ins: the basics (hello, ping, a JSON
  hello, a Wake-on-LAN template, a raw HTTP GET, a 32-byte length
  test) plus real protocol first words — a DNS query, an NTP time
  request, Redis PING, memcached stats, SMTP EHLO, an MQTT CONNECT,
  a Modbus read, a CoAP GET, and a raw printer test page. Deletable,
  restorable, and side by side with your own customs.
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

## Honest platform limits

iOS is not Linux with a fruit logo. What differs from the CLI, and why:

- **Foreground only for the mouth.** iOS suspends an app's listeners
  and advertisements when it leaves the screen, and a Personal Team
  build gets no say in it. Beacons and servers stop being reachable
  in the background. The Listen tab keeps its background hearing
  (state restoration + the tracker-service list), exactly like
  upstream — the two halves have different physics and the app says so.
- **No manufacturer-data stamping.** Python's `ble://` also writes the
  payload into manufacturer data; iOS gives apps no API to set
  manufacturer data in an advertisement. The payload rides in
  **service data for FFF0** instead — the one payload slot iOS offers.
  Keep beacons small (~20 bytes); iOS advertisement space is tight.
- **No MAC addresses.** iOS hides them, for sending as for listening:
  `ble-write://AA:BB:…` becomes "scan and tap the device" here.
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
  construction, transports, listeners, and the Send/Serve tabs (new).
- `nightjarTests/` — upstream decoder/log tests, plus `DroneTests`
  (vectors shared in spirit with `tests/test_remoteid.py`) and
  `HackTests` (payloads, framing, target parsing).

Not compiled on a Mac before first commit — the code was written
against the upstream app's patterns and reviewed, but Xcode is the
compiler of record. If the first build argues, the errors will be
small and local; the architecture is upstream's.
