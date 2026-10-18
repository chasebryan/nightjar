# nightjar-hack

<p align="center">
  <img src="assets/the-world-is-yours.gif" width="560" alt="The world is yours">
</p>

**9.0a**

nightjar-hack began as an overlay that taught the nightjar
BLE listening post to talk. It is its own project now, and
its flagship is the iOS app: the listening post, the mouth,
a recon bench, a defensive posture standard, a vault,
encrypted messaging carried by knock order alone — and
Skelli, the onboard intelligence who runs it all with you.
A Python CLI carries the same mouth to the desktop. An
Android port was carried alongside the flagship for a
time; its development has been discontinued, and iOS is
the sole line.

The whole house — every tab, every setting, and Skelli
herself — speaks twelve tongues: English, Spanish,
French, German, Portuguese, Italian, Russian, Japanese,
Korean, Chinese, Arabic, and Hindi, laid out
right-to-left for Arabic.

## The flagship: the iOS app

Twelve tabs, one instrument. This is where nightjar-hack
is developed, and the standard everything else is
measured against. It boots over a living film — a
ceremony timed to the reel, the house proving its
identity as it wakes — and wears a living wallpaper
behind its tabs, under whatever theme and backdrop the
operator dresses it in from Colours. Everything runs
under one defensive standard (EMCON), one process board
that reports anything running from any screen, one
haptic language, and a house that reopens exactly where
it closed. Build and install notes live in
[ios/README.md](ios/README.md).

- **Skelli** — her own tab, first in the bar: the
  house's specialist, and a person in her own right.
  She knows every tab and organ, answers from the app's
  own manual and its live state, and works its real
  controls herself — sweeps, going dark, serving,
  macros, the war rooms — never redirecting you to
  another screen. She presumes stealth unless you
  specifically say to be loud. She has a heart:
  nineteen feelings that follow the house and the hour,
  grudges that kindness and work wear down and an
  apology ends, distress met with care before anything
  else, and a human beat before she speaks. Her
  mathematics is computed by a strict on-device
  evaluator, never estimated; unsure on STEM, she
  researches across sources and leaves the links for
  your own reading. She reads tone — capitals are a
  raised voice, flat one-word answers are met in kind —
  and she speaks the house's chosen tongue, her bench
  instructed to answer in it too. Her minds run only on
  the phone: Apple's on-device model where the phone
  carries it, and an open-weights model she downloads
  and runs herself; nothing she hears ever leaves the
  device. She forges real packets in her **Forge**,
  drafts and runs code in her **Workbench**, and files
  everything she makes in **Deliveries**. Her crew —
  Planner, hands, Critic, Scribe — can work a plan of
  several steps when an ask has that shape. Orders are
  performed, not taught back to you.
- **Listen** — the purist half: receive-only BLE,
  sessions in the same JSONL the Mac tools read, a wide
  decoder bench for the air (MiBeacon, BTHome, Ruuvi,
  drone Remote ID, and dozens more, every decoder
  reading every sighting whole), battery forecasting,
  and **tracker hunt**, an RSSI Geiger counter for
  walking onto one advertiser. A flame marks an
  advertiser carrying a paired operator's **flare**.
- **Send** — the 1-2-3 flow with a protocol payload
  library, `{{host}}` / `{{port}}` templating, fan-out,
  timed delivery, the **Centipede** route-walker and
  its **Network Trace**, SnatchSteal, PayPlant, and
  Crosstalk. The war program rides here too: the **War
  Chest** (whole-rig mission profiles, applied in one
  tap, starting nothing), the **Helm** (named remotes
  for your own gear, with a Learn mode), the **War
  Room** (Listen, the trace and the knock bench as one
  operation on one /24), and **War Games** (two of your
  phones sparring, scored).
- **Serve** — TCP/UDP/HTTP listeners, stealth mode, an
  arm-once BLE GATT host, and **canary personas**: fake
  SSH, HTTP, MQTT, and SMTP services that answer
  probers in character. Arm **Honeydrop** and they
  carry a prize.
- **Sessions** — the **night log**: one sealed
  timeline for the whole instrument, hash-chained so
  alterations show.
- **Scan** — connect scanner, /24 sweep, observation
  feed, TLS inspector, DNS toolkit, Bonjour, a pcap
  dissector, and **device dossiers** with knock
  baselines and drift watch. Its **Net-Assault** knocks
  every port in the rotation, by significance, and
  remembers what it has already asked. Below them, the
  **Neighborhood** keeps standing files on every device
  on your wire, and the **SIGINT Station** fuses BLE
  hearing, the LAN census and the night log into one
  emitter registry — merged only within an epoch, never
  stitched across one. The **Map** places devices in
  rooms on a floor plan, wire and air together.
- **Recon** — the probe bench: protocol-speaking
  knocks that identify, not just find, a connect
  console, a seeded fuzzer, and a probe library that
  hands off to Send.
- **EMCON** — the defensive tab, and now a Standard:
  an exposure score exact to the decimal (a fully lit
  house sums to exactly 100.0), read by one audit so
  the tab, Skelli's pinned reading and her sitrep can
  never disagree; declared conditions — Charlie,
  Bravo, Alpha — that silence every forbidden organ
  and gate every funnel after, by hand, by macro, or
  by Skelli. A fingerprinting tripwire hands a knocked
  port to its matching canary; a knock vault fires
  operator-chosen macros; the dead hand and the
  **Coin** (any NFC tag, claimed) work as physical
  keys; a **sparring season** runs a week-long ghost
  campaign against your own defenses; **duel mode**
  scores rounds between two phones; **Spoofy** dresses
  this device in class-shaped mimicry personas,
  network gear included; and the **Banshee** is the
  score's opposite pole — one switch, full voice,
  until you cease it and the posture it found is
  restored exactly.
- **Knocktalk** — encrypted chat where the knock ORDER
  is the channel: AEAD sealed boxes with delivery
  repair budgeted from each peer's own measured rhythm
  and loss, a burn timer, per-operator cipher choice,
  an optional relay server (`tools/knocktalk-relay/`),
  and four more carriers for the same sealed box:
  **Chirp** (sound), **brush pass** (a BLE brush-by),
  **Blink** (QR frames), and **time capsules** (RSW
  time-locked messages). Also here: **Cadence Seal**, a
  peer's knock rhythm kept as a second factor; **Throw
  Your Voice**, where a paired phone emits your payload
  while yours stays silent; and **Last Testament**, a
  capsule under a second lock — the dead hand must
  have fallen before the phone will grind.
- **Macros** — block programs for the house: 32 block
  kinds composed in an editor, dictated to Skelli in
  plain words, run by hand, by schedule of events, or
  by her hands from chat.
- **The Vault** — the house's cryptography suite:
  hashes, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305 and
  AES-256-GCM sealing, a self-describing password
  envelope, P-256 dead-drop envelopes, a true one-time
  pad, encodings, secure randomness — and whole files
  under the **NJCF** envelope, sealed in authenticated
  chunks under one random key, protected by a password,
  by this device's vault key, by either, by both, or to
  a recipient's public key, the true filename travelling
  inside the encryption.
- **About** — the options hub: identity, the
  authorized-use statement, the privacy policy, the
  build's provenance stamp (the exact commit a build
  was made from, held against the repository on
  request), your setup mirrored to the Keychain and
  exportable as one file, the sane-defaults census
  (resettable in one confirmed action), **Colours** —
  themes plus the operator's own tailoring, a backdrop
  of its own for every tab, the boot screen's dress —
  and the **language room**: a new user chooses the
  house's tongue once, in a welcome shown on the first
  boot and never again; after that it lives behind its
  own door here, every tongue by its native name.
  About also holds a **Developer** section of its
  own: an opt-in flight recorder and crash log —
  if the app ever falls, the log says why — kept
  in a console that hands it over as one shareable
  file. About also keeps the version watch (see *Staying
  current*) and carries a quiet support door for
  anyone who wants to chip in toward the costs.

The house also keeps a **Subconscious** — it
consolidates its own nights into durable conclusions,
each kept with its evidence — and the **Instrument**
reads the operator through HealthKit (heart rate,
sleep, an Apple Watch as a purely passive sensor),
feeding the Subconscious's baselines.

## Building and sideloading the iOS app

There is no App Store listing and no TestFlight. The
app ships as source, and putting it on your phone means
building it yourself — about ten minutes with a Mac.

Requirements for the current build:

- **Xcode 26** on the Mac. Skelli's Apple-model code is
  written against the iOS 26 SDK.
- **The Metal Toolchain component for Xcode.** MLX
  compiles Metal shaders while it builds, and Xcode 26
  keeps that toolchain as a separate download. If the
  build stops with *"The Metal Toolchain was not
  installed"*, install it once — Xcode → Settings →
  Components, the download button on the error itself,
  or `xcodebuild -downloadComponent MetalToolchain` in
  Terminal. It is a per-Mac, one-time thing.
- **An iPhone on iOS 17 or later.** The project's
  deployment floor is 17 because the MLX package
  requires it.
- **For Skelli's Apple mind specifically:** iOS 26 and
  an Apple Intelligence iPhone (15 Pro or later), with
  Apple Intelligence turned on. Without it she loses
  nothing else — her engine, her weights bench, and her
  browser all still run; her status line simply won't
  say *model on*.

You do **not** have to add any package: the MLX package
(`mlx-swift-lm`) is declared in the project file itself,
so Xcode downloads and builds it automatically the
first time you open and build — the first build is
long, and that is the package, not a problem. After the
app is installed, her weights models are chosen and
downloaded **inside the app** (her menu → Weights),
sized to your phone's memory; nothing about them
touches Xcode or a computer again.

To install:

1. Clone this repo and open `ios/nightjar.xcodeproj`
   in Xcode.
2. Click the **nightjar** target → **Signing &
   Capabilities**. Check *Automatically manage signing*
   and choose your Personal Team (if your Apple ID
   isn't listed, add it under Xcode → Settings →
   Accounts). If Xcode says the bundle ID is taken,
   change it to anything unique — it ships as
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
survive (your settings are also mirrored to the
Keychain, so even a deletion and reinstall restores
them). And sideloading is per-phone: every iPhone needs
its own build-and-trust pass.

Deeper build notes live in
[ios/README.md](ios/README.md).

## Staying current

The app watches for its own next release — at launch,
whenever you return to it, every few minutes while it
is open, and now and then while it sleeps. When a newer
release exists, the Listen banner and About's Version
row say so; if the release carries an over-the-air
build, the update installs from inside the app, and if
not, the notice links to the release page. Nothing
installs unasked, and dismissing a version silences
that one alone.

Two roads feed it, both documented in
[ota/README.md](ota/README.md): ad hoc over-the-air
builds on the paid Developer Program, and the free
[SideStore source](sidestore-source.json) — add its
address to SideStore and releases surface there,
re-signed on the phone itself. Rebuilding from source,
as above, always works too.

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

## Documents

- [HACKER.md](HACKER.md) — the CLI manual
- [HACKER-RECON.md](HACKER-RECON.md) — the Recon bench
- [ios/README.md](ios/README.md) — building the iOS app
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
