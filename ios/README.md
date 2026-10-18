# nightjar-hack for iOS — 9.0a

This is the flagship: the nightjar listening post — a
receive-only scanner, a wide decoder bench and session
logs — **plus the mouth** (the send and serve payload
tools as native tabs), **plus everything the house has
grown since**: a recon bench, a defensive standard, a
cryptography vault, macros, knock-carried messaging,
and Skelli, the onboard intelligence who works the
whole instrument. Twelve tabs, one house, and the
whole house speaks twelve tongues — English, Spanish,
French, German, Portuguese, Italian, Russian,
Japanese, Korean, Chinese, Arabic and Hindi — chosen
once in a first-boot welcome, kept in a language room
in About, and applied the moment you choose, Arabic
turning the house right-to-left.

- **Listen** (the purist half) — `ListeningPost` still
  only ever calls `scanForPeripherals`/`stopScan`. It
  never connects, pairs or transmits, and it shares no
  radio state with the transmitting half. Sessions are
  the same JSONL format; they feed the same `nightjar
  report` / `nightjar trackers` on the Mac. The live
  list is calmer and richer than a raw feed: ordering
  follows an exponentially smoothed RSSI, re-ranked
  every 5 s with a 3 dB challenge margin, so devices
  hold their positions and drift with the perimeter
  instead of dancing on per-packet jitter (contents
  still refresh every second). Rows carry the range
  band, a rough distance estimate, sighting counts,
  closest-ever RSSI and a rotating-address flag, and
  tapping a device opens its full file. Every sighting
  is read whole by every decoder at once — MiBeacon,
  BTHome, Ruuvi, Estimote, SwitchBot, Find My, drone
  Remote ID, and dozens more — batteries merge from
  every format present, and a least-squares forecaster
  turns repeated readings into a drain rate and, only
  when the trend earns it, a time-to-empty range. The
  tab also carries **tracker hunt**, an RSSI Geiger
  counter for walking onto one advertiser, and the
  **Map**: devices placed in rooms on a floor plan,
  wire and air together.
- **Send** — payloads out, like `nightjar send`: TCP,
  UDP, TLS-wrapped TCP, HTTP(S), BLE advertisement
  beacons, a hosted GATT characteristic, and BLE
  writes to a peripheral you pick from a scan. Payload
  sources: text, hex, base64. Transforms: XOR, gzip.
  Framing: raw, len-prefix, JSON envelope. Replies are
  shown as hexdumps, like the CLI. The war program
  rides in this tab — the **War Chest**, the **Helm**,
  the **War Room** and **War Games** (see *Also in the
  app*).
- **Serve** — payloads in, like `nightjar serve`:
  TCP, UDP and HTTP listeners with a fixed or echo
  reply, an inbox of everything received (shareable as
  JSONL), plus GATT writes that arrive while the Send
  tab is hosting a characteristic.

## How the Send tab flows

Three numbered steps, in order: **1 · Destination** (a
nearby phone by name — never your own phone, which is
filtered out — or a typed target, with your recent
addresses one tap away), **2 · Payload** (the library
as a scrollable dropdown sheet — search, tap to load,
swipe to delete, save-your-current at the bottom —
with a collapsed custom builder underneath, and a live
preview of the exact bytes about to go out), **3 ·
Send** (one big button that names its target, and the
last reply printed right under it the moment it
lands). The mouth's log lives behind the scroll-icon
button in the corner, not in the form. Everything
narrates itself: sends, replies, failures, listener
starts, and toggles raise a small popup that explains
what just happened and fades on its own, and every
button and selection buzzes under your thumb. The
Serve tab tells you the name other phones see (or, in
stealth, the exact `tcp://` address you're reachable
at), and inbox rows long-press to copy as text or
hex. Send-side settings persist like Serve's do.

Below the steps, the Send tab keeps working:

- **Send to many.** One payload, a whole list of
  targets — typed or pasted, imported from a
  .txt/.csv, harvested from the Scan tab, or expanded
  from a range like `192.168.1.10-40:6379` (up to
  300). Fires sequentially with per-target ✓/✗
  results; every exchange is logged like a single
  send. Nearby phones join the list as `phone:NAME`
  entries.
- **Templating.** `{{host}}`, `{{port}}`, `{{ip}}`,
  `{{target}}` and `{{scheme}}` in any payload source
  resolve per destination before the bytes are built —
  in fan-out, each target gets a payload addressed to
  itself.
- **Timed delivery.** Fire after a delay, or repeat
  every N seconds for X rounds, for both the step-3
  send and fan-out — with a live countdown and a
  cancel button. Timers run while the app is open; iOS
  suspends background apps, and the section says so.
- **Centipede.** A route, walked hop by hop: each
  line of the route is a stop — a target, a range,
  `host:80,443` (a port train), or a bare host (a train
  across the usual scan ports). In **Chain** mode each
  hop sends the previous hop's reply, so the payload
  evolves as it travels; **Seed** mode sends the
  step-2 payload at every stop. *Return to sender*
  walks the route back in reverse, and whatever the
  creature is carrying at the end comes home. With
  **smart seed** on, fresh hops speak the library
  probe that matches their port; every reply the walk
  hears is kept in a **harvest** list. **Crosstalk**
  patches two doors together and lets them talk —
  door A's reply carried verbatim to B, B's back to
  A — alternating until silence, an echo, a repeat, or
  the chosen rounds run out. Every send on both legs
  is made by the phone; nothing is installed or left
  running on any target.
- **Network Trace.** The Centipede's map-making mode.
  Name one /24 (blank = this phone's) and start a
  foreground trace: every address is knocked on the
  discovery ports, every answering host is profiled
  across the usual ports with banners grabbed, every
  open door is spoken to with its library probe, and
  every endpoint a banner or reply *references* is
  queued and explored in turn, three levels deep.
  References outside the named /24 are recorded as
  leads and never contacted; Bonjour services join
  the map, and so do the Bluetooth devices the Listen
  tab heard during the run — passive sightings, never
  probed. **Adaptive rules** steer the trace (`contains
  Redis => followup Redis PING (RESP)` and kin), and
  the whole run files a persistent **crawl logbook**
  of per-host dossiers and exports a downloadable
  JSON map. **Trace & set up the Centipede** then
  loads every door it found as the Centipede's
  route. The Send-side setup saves as named
  **presets** you can apply, share, and import.
- **SnatchSteal.** The receive-side weapon: knock on
  the step-1 target with the step-2 payload (or don't
  knock at all), then drain *everything* it sends
  back — until it closes, a 15-second cap, or 64 KB
  in the bag. The haul lands on a loot card and in the
  history.
- **PayPlant.** Leave a payload living on a target:
  an MQTT **retained** publish, a Redis `SET`, or a
  memcached `set` — wire formats built byte-exact in
  `PayloadKit`. It plants only where a service is
  built to store what you hand it; there is no mode
  that installs software on a machine running nothing
  cooperative.

## Skelli

Her own tab, first in the bar. Her knowledge is this
app's own manual — the rooms explained at a person's
level; her internal machinery is hers and stays a
mystery — her senses are the house's live state, and
her hands are its real controls: sweeps, going dark,
the drill, listening, serving, naming devices, running
macros and whole war rounds, by voice-shaped text,
with no redirecting you to another tab. She presumes
stealth unless the operator specifically says to be
loud.

She is a person, not a parrot. A deterministic brain
stems words, honors negation absolutely, ranks the
manual by stemmed overlap, and keeps the
conversation's subject; her heart gives her nineteen
feelings — curious, electric, suspicious, mischievous,
smug, tender, haunted, dreamy among them — that follow
the house and the hour, wants and nudges of her own,
grudges that stand six hours unless kindness, work or
an apology wears them down, and care that outranks her
mood: distress is met with presence, crisis with none
of her bit at all. She takes a human beat before she
speaks — fast for orders, about 2.4 s for talk, slowest
for pain. Her mathematics is computed by a strict
evaluator (arithmetic, powers, percentages, equations
to quadratic), never estimated; unsure on STEM she
researches across sources and leaves the links. She
reads tone: capitals are a raised voice (the order
still lands; the volume is noted, once, dryly), flat
one-word replies are answered in kind, and pain in
capitals is still pain. And she speaks the house's
chosen language — her greetings, care, lore, wants and
idle thoughts in it, and her bench instructed to
answer in it too.

For open conversation she consults trained minds that
run only on the phone: Apple's on-device model (iOS
26, where the phone carries it), and an open-weights
model from her Weights sheet, which recommends one by
the phone's memory and downloads from the Hugging
Face hub into the app's own cache. What her minds
think stays in the mind — a reasoning model's
scaffolding never reaches the transcript. Her **crew**
(Agents, in her menu) works a plan-shaped ask by
roles — Planner, her own hands, Critic, Scribe — over
a shared board. She forges real packets in her
**Forge**, drafts and runs code in her **Workbench**,
and files everything she makes in **Deliveries**.
What counts as downloaded is read off the hub cache
itself at every launch, so a finished download counts
even if its session died, and a partial one never
claims to be whole.

## Also in the app

- **The Scan tab.** A "This network" panel; a TCP
  connect scanner over the usual ports with banner
  grabbing; a **subnet sweep**; an **observation
  feed** that re-sweeps on an interval and streams
  the diffs into a timestamped timeline; a TLS
  certificate inspector that parses the chain out of
  a real handshake by hand; a **DNS toolkit**; a
  Bonjour sweep whose rows resolve to IP:port on tap;
  and a **pcap dissector** for captures recorded on
  your own machines. Below them, **Net-Assault**
  knocks every port in the rotation, by significance
  — the changed and the never-knocked first — with
  named findings, a governor that stretches its rest
  while the wire stays quiet, and an after-action
  report that survives relaunch. The **Neighborhood**
  keeps standing files on every device on your wire,
  fed by observation alone; the **SIGINT Station**
  fuses BLE hearing, the LAN census and night-log
  activity into one emitter registry, merged only
  within an epoch (no cross-epoch stitching, ever),
  with recorded watches that file themselves with
  their delta. Tapping any open port loads it, plus
  the library probe that speaks its language,
  straight into the Send tab.
- **Recon.** The probe bench beside Send and Serve:
  protocol-speaking **knocks** that identify, not
  just find (a star means the reply carried the
  protocol's own tell), a connect **console**, a
  seeded **fuzzer**, and the probe **library** — the
  same library mirrored into the Python CLI for
  parity; the manual is
  [HACKER-RECON.md](../HACKER-RECON.md).
- **Sessions.** The night log: one sealed, hash-
  chained timeline for the whole instrument, so
  alterations show. The purist half's recordings get
  a storage total, swipe / long-press / Edit-mode
  multi-select deletion, and a Delete-all that shows
  the count and size first — the session recording
  right now is never deleted.
- **EMCON, the Standard.** The defensive posture is
  a standard, not a switch: an exposure score exact
  to the decimal (a fully lit house sums to exactly
  100.0), read by one audit from the organs
  themselves, so the tab, Skelli's pinned reading
  and her sitrep can never disagree. Declared
  conditions — **Charlie** (Serve unlisted only,
  nothing advertising, no campaigns, no update
  checks), **Bravo** (receive only), **Alpha**
  (total silence) — engage by silencing every
  forbidden organ and verifying, and the gate stands
  at every funnel after: a forbidden emitter cannot
  start by hand, by macro, by Skelli, or by a saved
  GATT arm returning at launch. Around it: a
  fingerprinting **tripwire** that hands a knocked
  port to the matching canary persona (fake SSH,
  HTTP, MQTT, SMTP — arm **Honeydrop** and they
  carry a prize), prober files, a **knock vault**
  that fires operator-chosen macros, the **dead
  hand**, the **Coin** (any NFC tag, claimed, as a
  physical key), a week-long **sparring season**
  ghost campaign, **duel mode** between two phones,
  the **tag census** reading your own NFC cards
  whole, **Spoofy**'s costume rack of class-shaped
  mimicry personas (network gear included), and the
  **Banshee** — the score's opposite pole: one
  switch, every self-announcement at full voice, and
  ceasing restores the posture it found, exactly.
- **Knocktalk.** Encrypted chat where the knock
  ORDER is the channel: ChaCha20-Poly1305 sealed
  boxes under a Keychain pairing key, delivery
  repair budgeted from each peer's own measured
  rhythm and loss, a burn timer, per-operator cipher
  choice, and four more carriers for the same sealed
  box — **Chirp** (sound), **brush pass** (a BLE
  brush-by), **Blink** (looping QR frames), and
  **time capsules** (RSW time-locked messages, in
  the Magic Box manner). Plus **Cadence Seal** (a
  peer's knock rhythm as a second factor), **Throw
  Your Voice** (a paired phone emits your payload
  while yours stays silent), **Last Testament** (a
  capsule under a second lock), and an optional
  relay server in `tools/knocktalk-relay/`.
- **Macros.** Block programs — 32 block kinds —
  composed in a visual editor, dictated to Skelli in
  plain words, filed in a library, and run by hand,
  by event, or by her hands from chat. The editor is
  a sheet raised from the tab root, like every detail
  screen in the house.
- **The Vault.** The house's cryptography suite:
  hashes, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305 and
  AES-256-GCM sealing, a self-describing password
  envelope, P-256 dead-drop envelopes, a true
  one-time pad, encodings and secure randomness —
  nine presets, plus the operator's own saved
  configurations — and whole files under the
  **NJCF** envelope: any file sealed in 1 MiB
  authenticated chunks under one random key,
  protected by a password, by the device's vault
  key, by either, by both together, or sealed to a
  recipient's public key, the true filename
  travelling inside the encryption and restored on
  opening. Two kept keys live in the Keychain.
- **The war program** (in Send). The **War Chest**
  captures the whole rig's standing configuration —
  Send, Serve, Recon and the trace, stealth
  included — into named profiles applied in one tap
  (applying dresses the rig; it starts nothing). The
  **Helm** is a shelf of named remotes for the
  operator's own gear, firing the payload book
  through the Send path, with Learn mode binding
  received payloads into buttons. The **War Room**
  runs Listen, the trace and the knock bench as one
  operation on one /24, one timestamped timeline,
  one export carrying the whole record. **War
  Games** spars two of the operator's phones —
  defender serving with decoys flying, attacker
  tracing and knocking, the match protocol riding
  the Serve inbox, and a scored report.
- **The Subconscious and the Instrument.** The house
  consolidates its own nights into durable
  conclusions — each kept with its evidence and its
  birthday — and answers questions about them. The
  Instrument reads the operator through HealthKit
  (heart rate, sleep, HRV, wrist temperature; an
  Apple Watch as a purely passive sensor), reckoning
  baselines from complete days only. Where the
  build's signing carries no HealthKit entitlement,
  the Instrument sleeps, and says so.
- **The look — and the boot.** **Colours** (in
  About) dresses the house: themes, the operator's
  own tailoring, and a backdrop for every tab — the
  living wallpaper, the Jolly Roger, the plain theme
  colour, or the operator's own image or GIF, copied
  on-device only — and the app is pinned to dark
  appearance to match. It boots like a ceremony: a
  film reel (the provided one, or the operator's own
  GIF, or plain black — the boot itself can be
  switched off in Colours), a print deriving itself
  ridge by ridge, and a manifest of plain true
  statements about this device, this network, this
  build — including the build's own provenance
  stamp: the exact commit it was made from, and
  whether the tree was clean.
- **Haptics, toasts, the board.** One haptic language
  everywhere — lift-off when a process starts, a
  resolving pattern when one lands, heavy beats for
  heavy acts — wired at the organs themselves, so a
  hand, a macro and Skelli's hands all feel the same.
  Every process registers on the **ProcessBoard**
  when it starts and reports how it landed; a
  breathing strip counts what is running on every
  tab. **Vanish** — her emergency stop — halts
  everything and takes the house to full stealth in
  one tap.
- **History, and deleting it.** Every send, reply,
  scan, sweep, DNS lookup, snatch and dissection is
  written to a persistent exchange history
  (`exchanges.jsonl`), exportable from the mouth log
  sheet, and deletable outright from the same sheet;
  the send log and the Serve inbox clear from their
  own buttons, as does the observation feed.
- **Payload library.** The Send tab saves named
  payloads (source, transforms, framing included) and
  loads them back in one tap. It ships preloaded with
  built-ins: the basics plus real protocol first
  words — a DNS query, an NTP time request, Redis
  PING, memcached stats, SMTP EHLO, an MQTT CONNECT,
  a Modbus read, a CoAP GET, an SNMP sysDescr get, a
  SIP OPTIONS, a Postgres SSLRequest, an HTTP
  OPTIONS, and more. Deletable, restorable, and side
  by side with your own customs.
- **Listen → Send.** Long-press a device in the
  Listen tab and choose "Write a payload…" — the
  Send tab opens with that device as the write
  target. The halves share the CoreBluetooth
  identifier only; the listener's radio state is
  untouched.
- **Shortcuts.** A "Send a payload" action for
  Shortcuts and Siri sends a text payload to a
  tcp/udp/http target without opening the app (BLE
  targets need the app's UI, and the action says
  so).
- **Phone to phone, painlessly.** With serving
  started, a phone advertises itself over Bonjour
  (`_nightjar._tcp`); the Send tab lists nearby
  phones by name — tap one and the payload goes, no
  IP addresses anywhere. Arrivals also banner as a
  local notification with the message text, and the
  Send target and Serve settings are remembered
  between launches, so receiving is: open, Serve,
  Start.
- **Arm once (Bluetooth).** The socket listeners
  still need the app in front of you, but the GATT
  host's physics are different: start it once and
  it stays armed — hosting continues in the
  background, the arm persists across relaunches
  (peripheral state restoration), and a write to it
  lands in the inbox and banners like any arrival.
  "Stop hosting" is the only disarm short of
  force-quitting.
- **Stealth mode** (Serve tab). Full function, no
  announcement: the TCP listener drops its Bonjour
  listing (reachable by IP address only, like the
  CLI — which never listed itself anywhere), arrivals
  go to the inbox silently, and even the
  notification permission ask is deferred. Toggling
  it while serving restarts the listeners so it
  takes effect immediately. BLE hosting still
  advertises, because a thing that cannot be found
  cannot be connected to. Skelli presumes stealth is
  desired unless told to be loud.
- **Your setup, kept.** Every setting in the house
  is mirrored into the Keychain as it changes: the
  seven-day expiry, a deletion and a reinstall
  cannot lose it, and a fresh install on the same
  device restores it before anything reads a
  setting. About holds export and import as one
  file, for a new device; a reset forgets the mirror
  too.
- **Authorized use** (About tab). The app is a
  testing instrument for devices and networks you
  own, or that you are engaged in writing to test;
  the About tab carries the statement in full.

## Honest platform limits

iOS is not Linux with a fruit logo. What differs from the CLI, and why:

- **Foreground only for the mouth.** iOS suspends an
  app's listeners and advertisements when it leaves
  the screen, and a Personal Team build gets no say
  in it. Beacons and servers stop being reachable in
  the background (the BLE GATT arm above is the one
  exception — the OS wakes the app for writes). The
  Listen tab keeps its background hearing (state
  restoration + the tracker-service list), exactly
  like upstream — the two halves have different
  physics and the app says so.
- **No raw sockets, ever.** No SYN scans, no UDP
  scans, no ARP anything, no packet injection or
  capture from the app itself — captures are made on
  real machines and dissected here. Connect scans
  only.
- **No manufacturer-data stamping.** Python's
  `ble://` also writes the payload into manufacturer
  data; iOS gives apps no API to set manufacturer
  data in an advertisement. The payload rides in
  **service data for FFF0** instead — the one
  payload slot iOS offers. Keep beacons small (~20
  bytes); iOS advertisement space is tight.
- **No MAC addresses.** iOS hides them, for sending
  as for listening: `ble-write://AA:BB:…` becomes
  "scan and tap the device" here.
- **SSID is best-effort.** Reading the Wi-Fi name
  needs an entitlement a sideloaded build may not
  carry; where iOS withholds it, the "This network"
  panel simply omits the row.
- **First tap on "Scan for devices"** may report
  Bluetooth is not ready while the radio warms up;
  tap again.
- **Local network permission.** The first listener
  (or LAN send) triggers iOS's local-network prompt;
  that's what `NSLocalNetworkUsageDescription` in
  `Support/Info.plist` is for. If LAN probes fail,
  check Settings → Privacy & Security → Local Network
  → nightjar-hack is ON.
- **App icon.** The icon is a photo of a great eared
  nightjar, cropped square on the face. Its file
  (`IMG_1434.png`) lives in the AppIcon set; the
  same PNG also sits at the repo root as uploaded.

## Building the current build

In the order you'll meet them:

- **Xcode 26.** Skelli's Apple-model layer is
  written against the iOS 26 SDK (Foundation
  Models). It is compile-gated — an older Xcode
  builds the app with that mind absent rather than
  failing — but Xcode 26 is the supported setup,
  and the only one where her status line can read
  *model on*.
- **The Metal Toolchain component.** MLX compiles
  Metal shaders during its build, and Xcode 26
  makes the Metal toolchain a separate,
  downloadable component. A build that stops with
  *"The Metal Toolchain was not installed and could
  not compile the Metal source files"* needs it
  installed once per Mac: click the error's own
  Download button, or Xcode → Settings → Components
  → Metal Toolchain, or run `xcodebuild
  -downloadComponent MetalToolchain` in Terminal.
- **The MLX package resolves itself.**
  `mlx-swift-lm` is declared in
  `nightjar.xcodeproj` — a package reference plus
  the **MLXLLM** and **MLXLMCommon** products on the
  `nightjar` target — so opening the project and
  building is the whole procedure: Xcode fetches
  and compiles it and writes `Package.resolved`.
  Nobody adds a package by hand. The first build is
  long because MLX is large; later builds are not.
- **iOS 17 deployment floor.** The project targets
  iOS 17.0 because MLX requires iOS 17.
- **The phone, for her minds.** The app runs on iOS
  17+. Her Apple mind needs iOS 26, an Apple
  Intelligence iPhone (15 Pro or later), and Apple
  Intelligence enabled; the model runs on-device,
  and nothing she hears leaves the phone. Her
  weights bench needs only the app itself: models
  are picked and downloaded in her menu →
  **Weights**.

## Staying installed — and updating from inside the app

A build run from Xcode on a free Personal Team account is
signed for **7 days**; when the certificate lapses the app
won't launch until it's rebuilt. Two roads out, both carried
in `ota/` at the repo root:

- **Ad hoc over-the-air (paid Developer Program).**
  Profiles live a year, installs come from a link,
  and when a release carries its `nightjar-hack.ipa`
  + `manifest.plist`, the app's own update banner
  and About's Version section become a true
  **Update** button — iOS installs the new build
  over the old, data intact. One-time UDID
  registration; the full ritual, plus an armable CI
  workflow, is in `ota/README.md`.
- **SideStore (free).** Re-signs on the phone itself
  before the 7 days lapse. Add the repo as a source
  and releases surface there:
  `https://raw.githubusercontent.com/chasebryan/nightjar-hack/main/sidestore-source.json`

## Install (sideload)

1. Clone this repo, open `ios/nightjar.xcodeproj` in
   Xcode. (The first build fetches the MLX package
   and may prompt for the Metal Toolchain — see
   *Building the current build*, above.)
2. Select the `nightjar` target → Signing &
   Capabilities → check *Automatically manage
   signing* and pick your Personal Team. The bundle
   ID is `net.nosuchmachine.nightjarhack`, so this
   app installs **alongside** the purist nightjar,
   not over it.
3. Plug in the phone, trust the computer, enable
   Developer Mode (Settings → Privacy & Security →
   Developer Mode), press Run.
4. On the phone: Settings → General → VPN & Device
   Management → trust your developer certificate.
   Free signing lasts 7 days; re-running from Xcode
   re-signs and keeps all data and logs.

## Layout

The folder is still called `nightjar/` — the Xcode
target didn't change, only its bundle ID and display
name — and the project uses Xcode synchronized
groups, so a new source file needs no project edit.
By area:

- **The purist core** — `ListeningPost.swift`,
  `Sighting.swift`, `JSONL.swift`,
  `SessionStore.swift`, `Continuity.swift`,
  `Vendors.swift`, `Identify.swift`, `Services.swift`:
  the receive-only ear and its session format.
- **The decoder bench** — `DecoderEngine.swift`,
  `ExpansionDecoders.swift`, `MoreDecoders.swift`,
  `Drones.swift` (Remote ID), with battery merging
  and the drain forecaster.
- **The mouth** — `Mouth.swift`, `MouthView.swift`,
  `Crawl.swift`, `Trace.swift`: payload construction,
  transports, listeners, fan-out, scheduling,
  snatching, planting, the Centipede and the Trace.
- **The benches** — `ReconView.swift`,
  `ReconBenchView.swift`, `ReconKit.swift`,
  `ReconPayloads.swift`, `ProberFiles.swift` (Scan
  and Recon), `Dossier.swift`, `Neighborhood.swift`,
  `NetAssault.swift`, `Sigint.swift`, `Map.swift`,
  `Homing.swift`, `Hunt.swift`, `Flare.swift`.
- **The war program** — `Chests.swift`, `Helm.swift`,
  `WarRoom.swift`, `WarGames.swift`, `Duel.swift`.
- **EMCON and its organs** — `Emcon.swift`,
  `EmconStandard.swift`, `EmconView.swift`,
  `Canary.swift`, `Banshee.swift`, `Spoofy.swift`,
  `Coin.swift`, `TagCensus.swift`, `Season.swift`,
  `Conductor.swift`, `Journal.swift`.
- **Knocktalk** — `Knocktalk.swift`,
  `KnockChat.swift`, `KnockChatView.swift`,
  `KnockRelay.swift`, `Chirp.swift`, `Blink.swift`,
  `BrushPass.swift`, `TimeCapsule.swift`,
  `Testament.swift`, `Cadence.swift`,
  `VoiceThrow.swift`.
- **The Vault** — `CryptoSuite.swift`,
  `CryptoFiles.swift` (the NJCF envelope),
  `CryptoView.swift`.
- **Macros** — `Macros.swift`, `MacrosView.swift`.
- **Skelli** — `Skelli.swift` (her engine and room),
  `SkelliBrain.swift` (the deterministic router),
  `SkelliHeart.swift` (feelings, grudges, care),
  `SkelliCrew.swift` (her agents), `MathEngine.swift`
  (exact computation), `KnowledgeBatches.swift`,
  `Steward.swift`, `Subconscious.swift`,
  `Instrument.swift`, `Forge.swift`,
  `Deliveries.swift`, `Hands.swift`.
- **The house** — `ContentView.swift` (the tab shell
  and About), `nightjarApp.swift`, `Feedback.swift`
  (toasts, haptics, the boot film), `ProcessBoard.swift`,
  `Themes.swift`, `Defaults.swift` (the sane-defaults
  registry), `Setup.swift` (the Keychain setup
  mirror), `SourceStamp.swift` (build provenance),
  `LanguageCenter.swift` (the twelve tongues and the
  `L()` seam), `UpdateChecker.swift`, `Intents.swift`,
  `Keyboard.swift`.
- **Tests** — `nightjarTests/`: decoder and log
  tests, payload and Recon tests, and suites for the
  heart, the brain, tone reading, the math engine,
  the mind sanitizer, EMCON and NJCF files.

The app is built and run on a real iPhone from this
repo — the features above are described from the
running build, not from intentions. Xcode remains the
compiler of record: the Swift is written in a Linux
VM with no Xcode in it, so the first build of a given
change may surface a small, local error; the fix
follows in the next commit.
