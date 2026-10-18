# nightjar-hack

<p align="center">
  <img src="assets/the-world-is-yours.gif" width="560" alt="The world is yours">
</p>

**7.0.0 — "the war chest."**

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
against. It boots over a living reel — the boot log typing itself across the film — and wears a living wallpaper behind its tabs, under whatever theme and backdrop the operator dresses it in from Colours. Build and install notes live in
[ios/README.md](ios/README.md).

- **Skelli** — her own tab, first in the bar: the
  house's specialist. She knows every tab and organ,
  answers from the app's own manual and its live
  state, runs its controls on request (sweeps, going
  dark, the drill, listening, serving), remembers
  what you tell her across conversations, and
  researches the open web through a browser of her
  own that works only the sources which let a machine
  in cleanly. She thinks with a cascade of trained
  minds (see *Two ways in*, below): Apple's on-device
  model where the phone carries it, and an
  open-weights model she downloads and runs herself —
  nothing she hears ever leaves the phone. Her minds
  work as a council — one drafts, the other checks it
  against the house before she speaks. She forges
  real packets to order in her **Forge**, drafts and
  runs code in her **Workbench**, files everything
  she makes in **Deliveries**, and understands plain
  intent in plain words: no modes to pick, no
  phrasing to memorize. As of 6.0.0 her hands answer
  in the conversation too: *forge me a DNS packet for
  the gateway* builds a real packet and keeps it,
  *download the 7B* works her weights bench,
  *delete the packet you forged* strikes it again,
  and *remember, the printer is not to be trusted* —
  said any natural way, punctuation and all — is
  written to her notes for real. Orders are
  performed, not taught back to you.
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
  Its **Net-Assault** knocks by significance — the
  changed and the never-knocked first — and remembers
  what it has already asked.
  Below them, **the Neighborhood** keeps standing files
  on every device on your wire, fed by observation alone.
- **Recon** — the probe bench: protocol-speaking knocks, a
  connect console, a seeded fuzzer, and a probe library that
  hands off to Send.
- **EMCON** — the defensive tab: an exposure score that
  feels the room — it counts Net-Assault, active
  probing, every Serve listener, and the stealth
  switch itself, live, and going dark reports the
  band you fell from — a silence
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
  the channel: AEAD sealed boxes with delivery repair
  budgeted from each peer's own measured rhythm and
  loss, a
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
  statement, the privacy policy, the sane-defaults census
  (resettable in one confirmed action), and **Colours** —
  six themes plus the operator's own tailoring, a
  backdrop of its own for every tab, and the boot
  screen's dress. About also keeps the version watch
  (see *Staying current*) and carries a quiet support
  door for anyone who wants to chip in toward the
  costs.

## What's new in 7.0.0 — "the war chest"

7.0.0 is the war release: five rooms built for
running this instrument as one rig, and one
score put on an honest footing.

- **The War Chest** — whole-rig mission profiles.
  One chest captures the standing configuration
  of Send, Serve, Recon and the trace — every
  setting, stealth included — and applies it in
  one tap. Applying dresses the rig; it starts
  nothing. Old presets migrate once, untouched.
- **The Helm** — named remotes for your own gear.
  Big buttons fire the payload book through the
  Send path, and Learn mode binds what your gear
  sends you into a new button. In EMCON, the tag
  census reads your own NFC cards and tags whole
  — NDEF, chip identity, an APDU explorer.
  Nothing written, nothing emulated.
- **The War Room** — Listen, the trace and the
  knock bench as one operation on one /24, one
  timestamped timeline, one export carrying the
  whole record with the trace export embedded.
- **The SIGINT Station** — one emitter registry
  fusing BLE hearing, the LAN census and the
  Night log, merged only within an epoch (no
  cross-epoch stitching, ever), with recorded
  watches that file themselves with their delta.
- **War Games** — two of your phones spar:
  defender serving with decoys flying, attacker
  tracing and knocking, the match protocol
  riding the Serve inbox, and a scored report.
- **The Banshee** — EMCON's opposite pole in
  the same tab: one switch lists Serve with
  stealth off, shouts the BLE beacon, arms
  Net-Assault and beats a named broadcast
  heartbeat across the subnet, until you cease
  it — and ceasing restores the posture it
  found, exactly.
- **EMCON's score, honestly based** — presence
  itself is weighed now: on the wire, and
  answering under its own name, before a single
  emission counts.
- **Spoofy & a wired Skelli** — EMCON's costume
  rack dresses this device in its own names and
  class-shaped mimicry personas — network gear
  included: access point, gateway, mesh node,
  media server, hub — the rack keeps the
  operator's own costumes and built personas,
  restores the exact air wardrobe on a drop,
  and revolves names on an interval — and
  Skelli works every war room herself: chests,
  the Helm, watches, War Room runs, whole War
  Games rounds by voice, the Banshee, the
  rack. A dynamics pass then taught the
  organs to move together — warned restores,
  a woken station, one-motion shape
  switches, a trace that refuses double
  work.

## What's new in 6.0.0 — "the open mind"

6.0.0 is an intelligence release. Nothing was
bolted on; everything already there was audited in
its own code and taught from what it already
observes:

- **Her hands, in conversation** — the Forge and
  the weights bench answer in Skelli's chat, facts
  are remembered in plain words, and forged things
  can be struck by asking. Orders are performed,
  not taught. (This carries everything prepared as
  5.0.5, which was never tagged on its own.)
- **The exposure score feels the room** — EMCON's
  number counts Serve's listeners, Net-Assault,
  active probing, and the stealth switch itself,
  live; going dark reports the fall it bought.
- **The house remembers better** — the
  Consolidation keeps facts the fortnight stops
  re-deriving, counts the Steward's rulings, and
  watches pairings as well as hours; the Instrument
  reckons baselines from complete days only, and
  HRV and wrist temperature speak at last.
- **The wire works smarter** — Net-Assault knocks
  by significance and remembers; identification
  weighs all its evidence before it names a thing;
  Recon knocks in two phases, and its fuzzer breeds
  from the payloads that earned replies; the
  Neighborhood writes itself once per sighting, not
  five times.
- **Reflexes with judgment** — Knocktalk times
  each peer by that peer's own rhythm; deliveries
  and repairs are budgeted from a per-peer ledger;
  a third foreign-hands verdict raises the second
  sense; the Conductor's rests deepen per host and
  jitter; the Canary arms the lures its own probers
  keep asking for; the Hunt judges closeness
  against the target's own strength.

And one question settled: a new living-wallpaper
reel — the red bloom — was tried as the default
and stepped down at the operator's word. The orb
keeps the wallpaper; the bloom is kept in `assets/`
under its own name.

## Two ways in: 7.0.0, or v4.0.0

7.0.0 is the current release, and it asks more of
your gear than the older line did. There are two
supported ways in, and which one is yours depends
on your Mac and your phone.

**The current build** (this repo, `main`, the
7.0.0 release) carries Skelli and everything in
6.0.0 — the Map, the Subconscious, the Instrument,
her conversational hands, the intelligence pass —
plus the whole war campaign above. Building it requires:

- **Xcode 26** on the Mac. Skelli's Apple-model code
  is written against the iOS 26 SDK.
- **The Metal Toolchain component for Xcode.** MLX
  compiles Metal shaders while it builds, and Xcode
  26 keeps that toolchain as a separate download. If
  the build stops with *"The Metal Toolchain was not
  installed"*, install it once — Xcode → Settings →
  Components, the download button on the error
  itself, or `xcodebuild -downloadComponent
  MetalToolchain` in Terminal. It is a per-Mac,
  one-time thing.
- **An iPhone on iOS 17 or later.** The project's
  deployment floor rose from 16 to 17 because the
  MLX package requires it.
- **For Skelli's Apple mind specifically:** iOS 26
  and an Apple Intelligence iPhone (15 Pro or later),
  with Apple Intelligence turned on. Without it she
  loses nothing else — her engine, her weights
  bench, and her browser all still run; her status
  line simply won't say *model on*.

One thing you do **not** have to do: add any
package. The MLX package (`mlx-swift-lm`) is
declared in the project file itself, so Xcode
downloads and builds it automatically the first
time you open and build — the first build is long,
and that is the package, not a problem. After the
app is installed, her weights models are chosen
and downloaded **inside the app** (her menu →
Weights), sized to your phone's memory; nothing
about them touches Xcode or a computer again.

**v4.0.0 "the masquerade"** is the last release
before all of that, and it asks for none of it:
**iOS 16 or later, any recent Xcode, no packages,
no Metal toolchain, no Apple Intelligence.** It is
the complete flagship as it stood at that release —
the listening post, the mouth, Recon, EMCON,
Knocktalk, Colours, the works — without the 4.2.0
additions (the Map, the Subconscious, the
Instrument) and without Skelli. If your phone or
Mac can't carry the current build, this is your
version, and it is a finished instrument, not a
demo: get it from the
[v4.0.0 release](https://github.com/chasebryan/nightjar-hack/releases/tag/v4.0.0)
or `git checkout v4.0.0`, then sideload exactly as
below.

## Sideload the iOS app

There is no App Store listing and no TestFlight. The app
ships as source, and putting it on your phone means
building it yourself — which sounds like a barrier and is
really about ten minutes with a Mac.

You need: a Mac with Xcode 26 (free in the Mac App
Store), an iPhone on iOS 17 or later, a cable that
fits both, and an Apple ID. No paid developer
account, no fee. (Building v4.0.0 instead? Any
recent Xcode and iOS 16 will do — see *Two ways in*,
above.)

1. Clone this repo and open `ios/nightjar.xcodeproj`
   in Xcode. The first build also downloads the MLX
   package and may ask for the Metal Toolchain
   component — both one-time, both explained in
   *Two ways in*.
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

## Staying current

The app watches for its own next release — at launch,
whenever you return to it, every few minutes while it
is open, and now and then while it sleeps. When a
newer release exists, the Listen banner and About's
Version row say so; if the release carries an
over-the-air build, the update installs from inside
the app, and if not, the notice links to the release
page. Nothing installs unasked, and dismissing a
version silences that one alone.

Two roads feed it, both documented in
[ota/README.md](ota/README.md): ad hoc over-the-air
builds on the paid Developer Program, and the free
[SideStore source](sidestore-source.json) — add its
address to SideStore and releases surface there,
re-signed on the phone itself. Rebuilding from
source, as above, always works too.

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
