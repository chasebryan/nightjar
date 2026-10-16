<p align="center">
  <img src="docs/readme/app-icon.png" width="168" alt="App icon: a great eared nightjar, face-on, red eye.">
</p>

<h1 align="center">nightjar-hack</h1>

<p align="center">
  <strong>Native iOS.</strong> A listening post, a mouth, and a pocket recon kit.<br>
  Dark only. Jolly Roger on the boot screen. The ear only listens.
</p>

<p align="center">
  <strong>3.0.0</strong>
  &nbsp;·&nbsp; sideload with Xcode and a Personal Team
  &nbsp;·&nbsp; <a href="ios/README.md">install</a>
</p>

<p align="center">
  <img src="docs/readme/jolly-roger-flag.jpg" width="440" alt="Jolly Roger from the app backdrop: a skull over crossed bones.">
</p>

The phone is the product. The app lives in [`ios/`](ios/README.md).
Clone this repo, open the Xcode project, sign with your Personal
Team, run it on the phone. The manual — signing, Developer Mode,
what survives backgrounding — is [ios/README.md](ios/README.md).

The Python overlay, for an upstream nightjar checkout, is
[folded up below](#cli-overlay).

## On the phone

Listen, Send, Serve, and Sessions sit on the bar. The rest live
under More, About first: Scan, Recon, EMCON, Knocktalk.

| Listen | Send | Serve |
| --- | --- | --- |
| Receive-only BLE. `scanForPeripherals` and `stopScan` only — the mouth's radio is a different organ. A Remote ID drone reads as `Drone <serial>`. Sessions are the JSONL the Mac tools already read. | Payloads out. TCP, UDP, TLS, HTTP(S), a BLE beacon, a GATT host, a write to a device you tap. Fan-out, templates, timers. Centipede walks a route. SnatchSteal drains the reply. PayPlant leaves a payload where a service is built to keep one. | Payloads in. TCP, UDP, HTTP — fixed reply or echo — and an inbox. Stealth drops the Bonjour name. Arm the GATT host once and it stays armed. Canaries answer a prober in character. |

| Scan | Recon | EMCON |
| --- | --- | --- |
| Connect scan, banners, a /24 sweep, an observation feed. TLS certs read from the handshake. Real DNS. Bonjour that resolves to an address. A pcap dissector for captures from your own machines. | Knock with the first words that port expects. A star means the reply carried the protocol's tell. A console against one target. A fuzzer with a seed you can rerun. | Exposure score, 0 GHOST through 100 BEACONING. Go dark. A tripwire that hears the knock and never replies. |

## Look and boot

<p align="center">
  <img src="docs/readme/jolly-roger.jpg" width="220" alt="The full AppBackground plate: the same Jolly Roger, tall, on black.">
</p>

The banner at the top of this page is that plate, cropped to the
skull. This one is the whole asset, the file the app calls
`AppBackground`. Forms and lists sit transparent over it, with a
thin black veil so the type still reads, and the app is pinned
to dark.

Boot is a black splash. The flag in a square, the wordmark
`nightjar-hack`, then a log that types itself over a progress
bar. Every line is true: this device, this address, this
library's payload count, this stealth state. Tap to skip. It
fades into the tabs in about two seconds.

The icon is a photograph of a great eared nightjar, cropped to
the face. Same picture as
`ios/nightjar/Assets.xcassets/AppIcon.appiconset/IMG_1434.png`.

## What the tabs actually do

The deep manual is still [ios/README.md](ios/README.md). This is
the short version, from the running build.

### Listen

The purist half, from upstream nightjar. It never connects,
pairs, or transmits. Rows hold still: RSSI is smoothed and
re-ranked every 5 seconds, with a range band and a rough
distance. Tap a device for the file — maker, sparkline, services,
the identifier. Long-press **Write a payload…** and Send opens
on that device; the ear's radio is untouched.

Open Drone ID (BLE service `0xFFFA`) shows as `Drone <serial>`
with status, altitude, speed, and the operator position the
drone broadcast. The air also decodes Xiaomi, BTHome, Govee,
RuuviTag, AltBeacon, Swift Pair, Tile, SwitchBot, SmartTags.
**Hunt this signal** is an RSSI walk onto one advertiser.

Sessions export from the Sessions tab. On the Mac:
`nightjar report` and `nightjar trackers`.

### Send

Three steps. Destination (a nearby phone by name, or a target
you type). Payload (the library, or your own bytes). Send.

The library ships 19 first words — Redis PING, an SMTP EHLO, an
MQTT CONNECT, Modbus, CoAP, SNMP, a Wake-on-LAN template, and
the plain ones. Sources are text, hex, or base64. Transforms:
XOR, gzip. Framing: raw, a length prefix, or a JSON envelope.
`{{host}}`, `{{port}}`, `{{ip}}`, `{{target}}`, and `{{scheme}}`
resolve per destination.

**Send to many** takes a typed list, a file, Scan's hits, or a
range like `192.168.1.10-40:6379` (up to 300). Nearby phones
join as `phone:NAME` over Bonjour (`_nightjar._tcp`) — no
addresses. Timers delay or repeat while the app is on screen.

**Centipede** walks a route hop by hop. Chain carries the
previous reply; Seed repeats your payload. Return to sender
walks it home. Smart seed speaks the probe that matches the
port. Crosstalk lets two doors talk until one of them goes
quiet. **Network Trace** maps one /24 in the foreground, three
levels deep, and records leads outside that /24 without
contacting them. The JSON map opens in
[`tools/trace-view/`](tools/trace-view/).

**SnatchSteal** knocks, then takes everything that comes back —
until the peer closes, 15 seconds, or 64 KB.
**PayPlant** leaves a payload living where a service is already
built to keep one: an MQTT retained publish, a Redis `SET`, a
memcached `set`.

### Serve

TCP, UDP, and HTTP listeners. A fixed reply, or echo. The inbox
shares as JSONL; a long-press copies text or hex. Arrivals can
banner. Stealth keeps the function and drops the announcement:
no Bonjour name, silent inbox.

The socket listeners need the app in front. The GATT host does
not: arm it once and a write still lands, backgrounded or after
a relaunch.

**Canary** personas (SSH, HTTP, MQTT, SMTP) answer in character
and file the transcript. A Honeydrop arms one of them with a
bait; a taken drop is journaled on the spot.

### Scan

A "this network" panel: your address, the /24, a likely gateway.
Connect scans over the usual ports, or yours, with banners. A
subnet sweep knocks one port across the /24. The observation
feed re-sweeps and narrates who appeared and who went dark.

TLS inspection runs a real handshake and reads subjects and
validity out of the certificate DER, because iOS exposes no API
for that. DNS sends a real query (A, AAAA, MX, NS, CNAME, TXT)
and parses it on the phone. Bonjour rows resolve to `IP:port`
on tap.

The **pcap dissector** takes apart classic `.pcap` files
recorded on your own machines — Ethernet, IPv4/IPv6, TCP flags,
UDP, ICMP, ARP — in plain text. An open port, tapped, loads
into Send with the probe that speaks its language.

### Recon

Beside the mouth: knock, connect, fuzz.

Knock hits the ports the library can name, each with the
protocol that port expects. A star means identified, not merely
open. Connect is a console, hexdump for binary replies. Fuzz
runs seven mutators from a seed, with a reply digest per round.
One button adds the probes to the Send library.

A tripwire row in EMCON can aim this bench at the knocker.
Firing is still your press.

### EMCON

Emissions control, aimed at this phone.

The score is live: your own Serve, beacon, and GATT host weigh
the most, then whatever the last self-knock and Bonjour audit
actually found. Bands run GHOST, DARK, LIT, LOUD, BEACONING.
**Go dark** forces stealth, disarms the GATT host, and stops
the beacon. Standing down does not turn an emission back on.

The tripwire listens on the probe ports, TCP and UDP, and
never replies. A knock with this app's own first words is
recognized, logged with its source, and kept. The drill is one
tap: scan, go dark, scan again, read the difference.

EMCON cannot hide the phone from the access point it has
joined. Find My and AirDrop answer to Settings, not to this
app. What it strips is everything the app itself was
announcing — and anyone who probes announces themselves.

### Knocktalk

Encrypted messages where the knock order is the channel.
Sealed boxes, ChaCha20-Poly1305 or AES-256-GCM, a burn timer,
threads. Without a relay, both phones share a network. With
one — yours, [`tools/knocktalk-relay/`](tools/knocktalk-relay/)
— they address `relay:<mailbox>`. The relay forwards knocks.
It never holds the pairing key. It sees timing, lengths, and
mailbox names.

The same sealed box also moves as sound (Chirp, including a
`.wav`), a BLE drop the host cannot see taken (brush pass), or
a looping QR (Blink).

## Honest limits

iOS is not Linux with a fruit logo.

- **The mouth is foreground.** Leave the app and the socket
  listeners and beacons stop. The GATT arm is the exception:
  the system wakes the app for a write. Listen keeps its
  background hearing, the same way upstream does, and only for
  the trackers iOS will still deliver.
- **No raw sockets.** No SYN scan, no UDP scan, no ARP, no
  capture from the app. Captures are made on a real machine
  and dissected here. UDP as a *send* still lives on the Send
  tab.
- **No manufacturer data in an advertisement.** The beacon
  payload rides in service data for `FFF0`. Keep it short.
- **No MAC addresses.** A BLE write is "scan and tap the
  device."
- **The Wi-Fi name is best-effort.** A sideloaded build may
  not be allowed to read the SSID. The row is simply absent.
- **The first LAN use asks permission.** That prompt is the
  local-network usage string doing its job.

## Sideload

There is no binary to tap. Install is Xcode on a phone you
trust.

1. Open `ios/nightjar.xcodeproj`.
2. Target `nightjar` → Signing & Capabilities → Automatically
   manage signing → your Personal Team. The bundle id is
   `net.nosuchmachine.nightjarhack`, so this build sits
   **beside** upstream nightjar.
3. Plug in, trust the computer, turn on Developer Mode, Run.
4. On the phone: Settings → General → VPN & Device Management
   → trust your certificate. Free signing lasts 7 days.
   Running from Xcode again re-signs and keeps the logs.

The full procedure is [ios/README.md](ios/README.md).

An Android port lives in [`android/`](android/README.md). It
tracks an earlier build. The phone app in `ios/` is this one.

## Authorized use

nightjar-hack is a testing instrument for devices and networks
you own, or that you are engaged in writing to test. Aim
everything it sends, scans, plants, or records only at targets
you are authorized for. You are responsible for your
authorization. The same paragraph is in the About tab.

[PRIVACY.md](PRIVACY.md): no accounts, no analytics, no server
of the developer's. Sightings, messages, captures, and the
tripwire log stay in the app's private storage on the device.
Export is an action you take. Deleting the app deletes them.

## CLI overlay

<details>
<summary>Python overlay for upstream nightjar — <code>send</code> and <code>serve</code></summary>

nightjar listens. This overlay gives the checkout a mouth:
`nightjar send` and `nightjar serve`. Scanning is undisturbed.
The receiver still never connects or pairs during a scan. The
manual for every transport and trick is [HACKER.md](HACKER.md).
Recon parity (`nightjar send --preset`, `nightjar knock`) is
[HACKER-RECON.md](HACKER-RECON.md).

```bash
# 1. upstream nightjar (nothing was uploaded; just clone)
git clone https://github.com/chasebryan/nightjar
cd nightjar

# 2. lay the overlay on top
python3 /path/to/nightjar-hack/apply_overlay.py .

# 3. install
pip install -e .
pip install 'nightjar[tx]'      # only for ble:// and ble-gatt://

# 4. try it
nightjar send --help
nightjar send tcp://127.0.0.1:9000 --payload "hello" --dry-run
nightjar serve --tcp 9000
```

In a second terminal:

```bash
nightjar send tcp://127.0.0.1:9000 --payload "hello from the other side" --read
```

The first terminal prints the hexdump and answers.

`nightjar-hack-single.py` writes the same files into the
checkout and then calls `apply_overlay.py`, if you would
rather not unpack anything.

```text
nightjar send TARGET [TARGET...]   tcp, udp, tls, http(s), ws(s), serial, ble, ble-gatt, ble-write — several targets fan out
nightjar serve [...]               tcp, udp, http, ws, serial, ble-gatt; static, echo, or file replies; a relay tap
```

Network sending is the standard library. BLE writes reuse the
`bleak` that scanning already needs. The peripheral role and
the 2.4 transports (WebSocket, serial) pull in the optional
`tx` extra, and only if you ask.

The log format is untouched. The default install gains no
dependency.

Uninstall, from the upstream checkout:

```bash
git checkout nightjar/cli.py pyproject.toml nightjar/__init__.py
rm nightjar/send.py
```

`apply_overlay.py --check` reports drift without writing.

</details>

---

[GNU AGPL-3.0](LICENSE). The iOS manual is [ios/README.md](ios/README.md).
The privacy policy is [PRIVACY.md](PRIVACY.md).
