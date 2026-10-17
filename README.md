# nightjar-hack

<p align="center">
  <img src="assets/the-world-is-yours.gif" width="560" alt="The world is yours">
</p>

**4.0.0.**

nightjar-hack began as an overlay that taught the nightjar
BLE listening post to talk. It is its own project now, and
its flagship is the iOS app: the listening post, the mouth,
a recon bench, a defensive posture tab, and Knocktalk —
encrypted messaging carried by knock order alone. A Python
CLI carries the same mouth to the desktop. An Android port
was carried alongside the flagship for a time; its
development has been discontinued (see
[Android](#android)).

## The flagship: the iOS app

Nine tabs, one instrument. This is where nightjar-hack is
developed, and the standard everything else is measured
against. It boots over a living reel — the boot log typing itself across the film — and wears a live wallpaper behind every tab. Build and install notes live in
[ios/README.md](ios/README.md).

- **Listen** — the purist half: receive-only BLE, sessions in
  the same JSONL the Mac tools read, a wide decoder bench for
  the air (MiBeacon, BTHome, Ruuvi, drone Remote ID, and
  more), and **tracker hunt**, an RSSI Geiger counter for
  walking onto one advertiser. A flame marks an advertiser
  carrying a paired operator's **flare**.
- **Send** — the 1-2-3 flow with a protocol payload library,
  `{{host}}` / `{{port}}` templating, one-tap phone-to-phone
  targets, a fan-out list, timed delivery, SnatchSteal, and
  PayPlant.
- **Serve** — TCP/UDP/HTTP listeners, stealth mode, an
  arm-once BLE GATT host, and **canary personas**: fake SSH,
  HTTP, MQTT, and SMTP services that answer probers in
  character. Arm **Honeydrop** and they carry a prize.
- **Sessions** — the **night log**: one sealed timeline for
  the whole instrument, hash-chained so alterations show.
- **Scan** — connect scanner, /24 sweep, observation feed,
  TLS inspector, DNS toolkit, Bonjour, a pcap dissector, and
  **device dossiers** with knock baselines and drift watch.
  Below them, **the Neighborhood** keeps standing files
  on every device on your wire, fed by observation alone.
- **Recon** — the probe bench: protocol-speaking knocks, a
  connect console, a seeded fuzzer, and a probe library that
  hands off to Send.
- **EMCON** — the defensive tab: an exposure score, a silence
  switch, a self-audit, a fingerprinting tripwire, prober
  files, a knock vault that fires operator-chosen macros,
  the dead hand, self-sparring, night maneuvers, and Answer
  in character — the tripwire hands a knocked port to the
  matching canary, then takes it back. A **sparring
  season** runs a week-long ghost campaign through those
  same defenses, **duel mode** scores rounds between two
  phones on one wire, and **the Coin** — any NFC tag,
  claimed — works as a physical key for dead-hand
  check-ins and the vault.
- **Knocktalk** — encrypted chat where the knock ORDER is
  the channel: AEAD sealed boxes with delivery repair, a
  burn timer, per-operator cipher choice, an optional relay
  server (`tools/knocktalk-relay/`), and four more carriers
  for the same sealed box: **Chirp** (sound), **brush pass**
  (a BLE brush-by), **Blink** (QR frames), and **time
  capsules** (RSW time-locked messages). Also here:
  **Cadence Seal**, a peer's knock rhythm kept as a
  second factor; **Throw Your Voice**, where a paired
  phone emits your payload while yours stays silent; and
  **Last Testament**, a capsule under a second lock —
  the dead hand must have fallen before the phone will
  grind.
- **About** — the options hub: identity, the authorized-use
  statement, the privacy policy, and the sane-defaults
  census, resettable in one confirmed action.

## Sideload the iOS app

There is no App Store listing and no TestFlight. The app
ships as source, and putting it on your phone means
building it yourself — which sounds like a barrier and is
really about ten minutes with a Mac.

You need: a Mac with Xcode (free in the Mac App Store),
an iPhone on iOS 16 or later, a cable that fits both,
and an Apple ID. No paid developer account, no fee.

1. Clone this repo and open `ios/nightjar.xcodeproj`
   in Xcode.
2. Click the **nightjar** target → **Signing &
   Capabilities**. Check *Automatically manage signing*
   and choose your Personal Team (if your Apple ID isn't
   listed, add it under Xcode → Settings → Accounts).
   If Xcode says the bundle ID is taken, change it to
   anything unique — it ships as
   `net.nosuchmachine.nightjarhack`.
3. On the iPhone, turn on Developer Mode: Settings →
   Privacy & Security → Developer Mode. The phone will
   restart to apply it.
4. Plug the phone in, trust the computer when asked,
   pick the phone as the run destination in Xcode, and
   press **Run**. The first build takes a few minutes.
5. The first launch is blocked until you trust the
   builder: Settings → General → VPN & Device
   Management → your Apple ID → **Trust**.
6. Open the app and answer its permission prompts as
   features ask for them — Bluetooth and the local
   network first. Everything it hears stays on the
   phone (see [PRIVACY.md](PRIVACY.md)).

Two honest wrinkles. Free signing expires after 7 days;
when it does, plug in and press Run again — the app
re-signs in place, and all your data, logs, and settings
survive. And sideloading is per-phone: every iPhone
needs its own build-and-trust pass.

Deeper build notes live in
[ios/README.md](ios/README.md).

<p align="center">
  <img src="assets/scarface.gif" width="380" alt="Scarface">
</p>

## 60 seconds (the CLI)

    # 1. get the upstream repo
    git clone https://github.com/chasebryan/nightjar
    cd nightjar

    # 2. lay the overlay on top
    python3 /path/to/nightjar-hack/apply_overlay.py .

    # 3. install
    pip install -e .
    pip install 'nightjar[tx]'      # only needed for ble:// and ble-gatt://

    # 4. try it
    nightjar send --help
    nightjar send tcp://127.0.0.1:9000 --payload "hello" --dry-run
    nightjar serve --tcp 9000

Then, in a second terminal:

    nightjar send tcp://127.0.0.1:9000 --payload "hello from the other side" --read

The first terminal prints the hexdump and answers.

## What the CLI adds

`nightjar send TARGET [TARGET ...]` — payload out over TCP,
UDP, TLS, HTTP(S), WebSocket, serial, and BLE (advertise,
GATT host, or write). Several targets fan out.

`nightjar serve` — payload in over TCP, UDP, HTTP,
WebSocket, serial, and BLE GATT, with static, echo, or file
replies and a relay tap.

The full CLI manual — every transport, framing, transform,
and trick (`--expect`, `--follow`, `--replay`) — is
[HACKER.md](HACKER.md).

## Single-file route

If you would rather not unzip anything, use
nightjar-hack-single.py: it writes the same files into the
checkout and then calls apply_overlay.py.

## Android

Android development has stopped, and the APK will not be
continued at this time.

The port never reached the standard the flagship sets.
Build after build failed at the last mile — packaging,
then installation, and in the end reliable launch — and
an instrument that cannot be trusted to open does not
ship under this name. The effort belongs on the iOS app,
and that is where it has gone back to.

The Android source remains in this tree under
[android/](android/) as the record of the attempt. The
APK previously offered for download here is withdrawn:
the Android file on the release page is a leftover of
the discontinued port, not the current instrument. If
the port is ever resumed, it will be announced here.

## Documents

- [HACKER.md](HACKER.md) — the CLI manual
- [HACKER-RECON.md](HACKER-RECON.md) — the Recon bench
- [ios/README.md](ios/README.md) — building the iOS app
- [android/README.md](android/README.md) — the discontinued Android port (archive)
- [CHANGELOG.md](CHANGELOG.md) — what shipped, when
- [PRIVACY.md](PRIVACY.md) — what the app collects (nothing)

## About me

<img align="right" width="230" src="assets/triangle.gif" alt="Triangle">

I'm Chase Bryan — cryptographer and builder. nightjar-hack
is my instrument: I build the tools I want to exist, and I
build them in the open.

The rest of the shelf: **orange**, a language for
specifying and verifying cryptography; **snoot**, a
post-quantum crypto-inventory scanner; **mawkbox**, an
encrypted text-to-audio modem; and **Magic Box**, keyless
time-lock encryption.

## What it does not do

The CLI overlay does not change how scanning works, does not
touch the log format, and adds no dependency to the default
install. Network sending is pure standard library; BLE
writes reuse the `bleak` that scanning already needs. Only
the peripheral role (broadcasting / GATT server) and the
WebSocket/serial transports pull in the optional `tx` extra,
and only if you ask for it.

It is a testing instrument for devices and networks you own,
or that you are engaged in writing to test — the app carries
the same statement in its About tab.

## Uninstall

    git checkout nightjar/cli.py pyproject.toml nightjar/__init__.py
    rm nightjar/send.py

Nothing was committed, so `git status` shows the overlay as
your working tree changes and `git diff` shows exactly the
six edits.
