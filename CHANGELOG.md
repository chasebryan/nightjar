# Changelog

## Unreleased

- **The great presenter audit.** Every sheet, cover,
  dialog, importer, and share in the app was inventoried
  and moved to the one level that has never failed on
  device: the screen's outermost view. Scan's Map cover,
  dossier and name sheets, and pcap importer, the Recon
  bench's protocol library, Knocktalk's conversation,
  blink, and chirp importer, and Send's preset importer
  all hang on their NavigationStacks now; and every
  share that lived inside a list — the tripwire log, the
  morning brief, the night log, dossiers, prober files,
  session files, presets, trace exports, the crawl
  logbook, the inbox, chirps, and capsules — is now a
  button that raises the share sheet from the screen's
  root, the way the after-action report learned to.
  The Net-Assault section itself was then rebuilt
  as true list rows — one control per row — after
  its single stuffed cell (pitch, warning, both
  pickers, both buttons in one row) misrouted the
  report button's taps to Arm once the button
  appeared after a run.
- **The Night log folds.** Its entries — up to three
  hundred sealed rows — now sit behind an Entries
  dropdown, closed on arrival, with the count printed
  on the door; and the log can be cleared from the
  same section, behind a confirmation: the file is
  deleted on the journal's own queue and the seal
  chain starts fresh.
- **The clear-and-fold doctrine.** What the Night log
  got, everything collected now gets. Clears, each
  behind a confirmation: the Neighborhood (devices,
  names, drift — and their Map placements), the Map
  itself (rooms and placements; the devices stay),
  the Subconscious's memory (drift baselines and the
  operator's verdicts), every Knocktalk thread, and
  every cadence profile (the seal's reset, previously
  unwired). Folds, so no screen is a forced march:
  the Neighborhood board and Scan's dossiers open
  by a counted door, and EMCON's tripwire feed and
  prober files show six with a door to the rest.
- **The Map (iOS Scan).** A special section of its own:
  the house on one canvas. The operator names rooms and
  places each neighbor where the device physically sits;
  nodes carry freshness, drift, and a doorway into their
  dossiers, and a sweep lights the house up room by room.
  Placement is the operator's testimony — the app keeps
  it and never invents a location of its own.
- **Net-Assault (iOS EMCON).** A dedicated section
  under a drawn skull and crossbones, second only to the
  status board: one arming turns every organ in the house
  loose on the wire in a continuous autonomous run —
  subnet sweeps on rotating ports, the Bonjour browse,
  and the recon bench knocking the full census against
  every known neighbor, pass after pass, until the
  operator stands it down. Findings walk the usual
  roads (Neighborhood, Map, sealed log, the watching
  Subconscious); the dashboard counts passes, new
  devices, drift, and knocks; the finished run exports
  an after-action report. It is loud by design and says
  so twice — a permanent warning in the section and a
  confirmation that names the consequence (watchers,
  intrusion detection, questions) before the first pass.
  Depth (sweep / +Bonjour / full) and rest between
  passes are the operator's. It runs while the app is
  awake; sleep pauses it, waking resumes it.
  Arming plays an ignition reel full-screen — the
  operator's GIF (an "Assault" asset or assault.gif)
  over the run's first pass, tap to skip, with a
  flickering skull card standing in until the reel
  is bundled.
- **The Compass and the Matrix (iOS).** The Map is a
  matrix now — black field, dot grid in the house colors,
  a slow radar sweep, rooms and devices glowing by their
  freshness. Beneath it, an "In the air" strip lists what
  the ear is hearing autonomously, and any of them can be
  walked to: a compass face whose ring fills as you close
  in, signal in honest bands with paw-prints for distance,
  and a bearing that condenses out of your own footsteps —
  gains laid along the courses that earned them, wide and
  unsure at first, sharpening as you walk. No wedge until
  you have walked, and no precision the signal never gave:
  Bluetooth gives up a loudness, never a direction, so the
  direction is learned from you.
- **The Subconscious, second mind (iOS).** It keeps a
  fortnight's hourly baseline now, and reads against it:
  days that run loud or quiet against the house's habit;
  regulars who have gone silent past three times their
  own rhythm; the next regular named before it knocks,
  as a printed forecast. It correlates — a fresh face
  within three hours of night activity, foreign hands,
  or its own drift is read as one story, not three small
  ones. And it learns from its operator: every finding
  takes a True / Not so verdict, kept per kind, and its
  printed confidence bends toward the record. Asking
  grew up too: about a device by any of its names, who
  has gone quiet, when the house is busiest.
- **One back button, everywhere (iOS).** Dossiers and
  Knocktalk conversations now present as sheets with a
  single Done — the cure Colours took — instead of pushes
  that doubled the back chevron inside More-tab screens.
- **Every road leads to the Map (iOS).** The Map is
  populated by anything any feature discovers, through one
  LAN-guarded door in the Neighborhood store: recon
  answers, replies the mouth collects (every centipede
  hop among them), knocktalk peers, honeydrop takers —
  alongside the sweeps, Bonjour resolutions, and arrivals
  that already fed it. Relay labels, the ghost, and
  anything off this wire are turned away at the door.
- **Given names (iOS).** Every device on the wire can be
  given the operator's own name and a mark to tell it
  apart — and the name follows the device everywhere it
  is presented: the Neighborhood board, the Map, Scan's
  dossiers, its own dossier, and the Subconscious's
  findings. The wire's own name is never overwritten,
  only outranked, and the journal keeps the naming. The
  Bluetooth air keeps its classification labels instead:
  a passerby is not yours to name.
- **The Subconscious (iOS EMCON).** An underlying
  intelligence that reads across every organ — the sealed
  night log, the Neighborhood, the Map, cadence, the
  season, the dead hand — and names what breaks the
  house's pattern: findings with their journal citations
  and printed confidence, a narrative brief ("the night,
  understood"), and a query line over the operator's own
  data. It never acts and never touches the network; it
  advises, and the Steward still asks.

## 4.0.0 — 2026-10-16 — the masquerade

The release where the instrument grows a second of
everything: a second factor, a second mouth, a second
lock, a second phone.

- **Cadence Seal (iOS Knocktalk).** The pairing key decides
  what opens; cadence decides what is believed. The engine
  profiles each peer's knock timing — pacing, pauses,
  hesitations — from its first messages, then flags any
  later message that arrives in foreign hands: right key,
  wrong rhythm. It never blocks a message; it marks it,
  shows the verdict in the thread, and seals the warning
  into the night log.
- **Throw Your Voice (iOS Knocktalk).** One phone stays
  silent while a paired phone speaks for it. The hand seals
  a small instruction into an ordinary Knocktalk message;
  the mouth — if it has been lent — performs the send from
  its own radios and knocks a receipt back the same road,
  which settles the throw in the thread. Payloads are
  signals: a word, a command, a wake-up.
- **The Coin (iOS EMCON).** Any NDEF tag — a transit card,
  a hotel key, a blank — can be claimed as a physical key.
  The app keeps a hash of the tag, never its contents. Tap
  it to check in the dead hand, tap it to raise the knock
  vault, or stand it guard over Knocktalk itself. The
  factor is possession, like every key ever cut. NFC
  reading requires a paid developer team's profile;
  under free Personal Team signing the Coin ships
  dormant — present, honest about why, and live the
  moment the app is signed by a paid team.
- **Last Testament (iOS Knocktalk).** A message under two
  locks: an RSW time capsule, and the dead hand. The phone
  will not even begin the grind until the hand has fallen
  and stayed down for the author's chosen span. The
  capsule never leaves the phone's keeping — a capsule
  alone can be ground by anyone holding it, so the
  testament holds it until both locks agree.
- **Sparring Season (iOS EMCON).** Self-sparring grown
  into a campaign: nine ghost visits across seven days —
  loud ones that spell, quiet ones that slip under the
  grader, and two polite attempts with the vault
  combination printed in the manual. Every visit runs
  through the real defenses, the score is kept in the
  open, and the week closes with a grade sealed into the
  night log.
- **The Neighborhood (iOS Scan).** Standing files on
  every device on the operator's own wire, fed only by
  observation: sweeps Scan ran, Bonjour announcements that
  resolved, knocks at this phone's own door. First
  sightings, new ports, and changed names are journaled
  as drift; each neighbor opens into its full dossier.
- **Duel Mode (iOS EMCON).** Two of the operator's
  phones, one wire, three scored rounds. The host's phone
  is the ground — its arena dealt from the surface it
  truly runs, padded with decoys — and the guest strikes
  three ports a round. The defender's own event log
  referees: an answered strike scores for the blade, a
  heard strike for the ground, and an answer nobody heard
  slips a bonus.
- **The face (iOS).** The boot screen is a reel now: the
  operator's film plays full-screen while the true boot
  log types itself over it in glowing phosphor, loading
  in twenty-six lit blocks. Inside, the Jolly Roger
  wallpaper is retired for a living one — a second reel,
  decoded once and shared by every tab, looping from its
  beginning to its end and back, forever.

- **Colours (iOS).** The app's wardrobe, in the More
  section: six built-in themes (Phosphor, Bloodwork,
  Ultraviolet, Arctic Signal, Amber Deck, Bone) driving
  the accent of every control and a tint washed over the
  backdrop, plus a theme editor to tailor your own. Every
  tab may wear its own backdrop — the living wallpaper,
  the Jolly Roger the app was born wearing, the plain
  theme colour, or the operator's own image or GIF,
  copied onto the device and never uploaded anywhere.
  The same pass fixes the Knocktalk tab, whose lists had
  never worn the backdrop at all.


## 3.0.0 — 2026-10-16 — the ventriloquist

The release where the instrument starts speaking in other
voices — and learns to keep silence like a professional.

- **EMCON (iOS).** A defensive posture tab: an exposure
  score (0 GHOST – 100 BEACONING) computed from the phone's
  own live emissions, a silence switch (stealth on, GATT
  host and beacon down — standing down never re-opens an
  emission), a Bonjour/mDNS self-audit, a TCP+UDP tripwire
  that fingerprints inbound first words, a persistent
  tripwire log, a one-tap go-dark drill, and home-subnet
  memory. Closing the loop: **Answer in character** — a
  fingerprinted knock makes the tripwire hand its port to
  the matching canary persona for ten minutes, then take
  it back.
- **Canary personas + Honeydrop (iOS Serve).** Fake SSH /
  HTTP / MQTT / SMTP services that answer probers in
  character and file their full transcripts into the inbox.
  The Honeydrop activate phase arms a persona with a prize
  — a bait file, a published message, a receipt, a framed
  SSH KEXINIT — and a taken drop is journaled on the spot
  and stamped into the transcript.
- **Knocktalk (iOS).** Encrypted messaging where the knock
  ORDER is the channel: fragmented AEAD sealed boxes
  (ChaCha20-Poly1305 or AES-256-GCM, per-operator choice,
  no matching required) with ACK/NACK repair, a burn timer,
  its own tab and threads, a knock vault whose combination
  now fires operator-chosen **macros** (hidden Serve, raise
  EMCON, burn threads, raise the canary), and an optional
  operator-run **relay server**
  (`tools/knocktalk-relay/`) that carries the knocks across
  the internet while seeing nothing but port numbers.
- **Three more transports for the same sealed box (iOS).**
  **Chirp** — mawkbox-style 4-tone FSK, speaker to
  microphone, plus **Chirp mail**: the song rendered to a
  .wav for any audio carrier, decoded on arrival by the
  same decoder. **Brush pass** — a sealed drop armed in
  the GATT host, taken by a paired phone in BLE range; the
  host never learns it was taken. **Blink** — the payload
  as a looping QR-frame sequence, camera to screen.
- **The interlinkages (iOS).** The **night log**: one
  sealed timeline for the whole instrument — now a SHA-256
  **hash chain**, with a verify action that proves no
  sealed line was altered, reordered, or cut from the
  middle. **Counter-knock**: a tripwire row pivots into a
  loaded Recon bench. **Self-sparring**: EMCON replays a
  captured knock, mutated, at the phone's own Serve.
  **Device dossiers** with **drift watch**: keep a knock
  as a baseline and later knocks report what opened and
  what closed since. **Tracker hunt**: an RSSI Geiger
  counter for walking onto one advertiser.
- **Sane defaults (iOS).** Every setting the app keeps, in
  one census in the About tab, resettable to defaults in
  one confirmed action — configuration only; payloads,
  presets, sessions and logs are not configuration.
- **Store hygiene (iOS).** Privacy manifest
  (UserDefaults + file-timestamp reasons declared), the
  Bonjour service types declared, export-compliance flag
  set (CryptoKit only), `PRIVACY.md` at the repo root, and
  the GitHub update checker compiled out of store builds
  behind `STORE_BUILD` (default builds unchanged).
- **The second wave (iOS, same evening).** **Prober
  files** — dossiers for everyone who knocks, assembled
  from the tripwire log. **Dead hand** — miss a deliberate
  check-in and the next opening burns the Knocktalk
  threads and raises EMCON. **The board** — the relay now
  reports when each mailbox was last seen. **Night
  maneuvers** — a one-press self-test (seal chain, census,
  spar) graded into the sealed log. **Flare** — a keyed
  rotating beacon token: paired operators recognize each
  other in Listen, and the token names nobody. **Time
  capsule** — Knocktalk messages under an RSW time-lock
  (hand-rolled Montgomery bignum, forged primes, the φ
  shortcut for the sealer and the sequential grind for
  everyone else), in the Magic Box manner.

## 2.6.0 — 2026-10-15 — the cartographer

- **Network Trace + adaptive Centipede + crawl logbook
  (iOS Send, mirrored in the Android port).** A new Send-tab
  section: name one /24 (blank = the phone's own) and start
  a foreground trace that walks until its frontier is
  exhausted — every address knocked on the discovery ports,
  every answering host profiled across the usual ports with
  banners grabbed, every open door spoken to with its
  library probe, and every endpoint a banner or reply
  references (an IP:port in a page, a redirect target)
  queued and explored in turn, three levels deep. Endpoints
  referenced outside the named /24 are recorded as leads
  and never contacted. Bonjour services found along the way
  join the map. One rule syntax now steers both the trace
  and ordinary Centipede walks — `contains Redis =>
  followup Redis PING (RESP)`, `contains HTTP => tag web`,
  `contains SSH => stop` — a follow-up fires a second,
  chosen probe at the same door, tags stick to the dossier,
  and `stop` keeps that reply out of the chain. Every walk
  and trace feeds a persistent **crawl logbook**: per-host
  dossiers (first/last seen, services, banners, reply
  signatures, tags) kept between launches. Each trace
  writes a downloadable JSON map — hosts, services, a
  node/edge graph, Bonjour finds, external references, the
  diff against the logbook (new/vanished hosts, changed
  banners), and an honest limitations block (TCP-connect
  only, no ICMP/ARP, a silent or drop-firewalled host can
  still hide) — in a versioned schema
  (`net.nosuchmachine.nightjar.network-trace`) meant to be
  ingested by other tools. A **Trace & set up the
  Centipede** button closes the loop: run the trace and,
  when it ends, every door it found is loaded into the
  Centipede as its route — one port train per host, ready
  to release, no manual configuration. (It can also be
  armed mid-trace.)
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
- **Trace schema v2: Bluetooth joins the map (both apps).**
  A finished trace now files the Listen tab's BLE sightings
  alongside the IP hosts — per-device entries (name, maker,
  services, sighting count, closest and smoothed RSSI,
  first/last heard) in the export's `bleDevices`, graph nodes
  heard by the phone, and the crawl logbook, which keeps them
  between runs. Sightings are passive: heard, never probed,
  connected to, or written to. Android exports carry the same
  `firstHeard`/`lastHeard` fields as iOS.
- **Presets (both apps).** The whole Send-side setup — trace
  scope, discovery and profile port sets, Bonjour, adaptive
  rules, the Centipede route — saves under a name, applies in
  one tap, and travels as a small JSON file: share it out,
  import it on the other platform, same behavior.
- **More decoders in Listen (both apps).** Full decoders for
  Xiaomi MiBeacon, BTHome v2, and Govee thermometer
  advertisements — real sensor readings, not just a name —
  plus RuuviTag format 3 alongside 5, AltBeacon, and strict
  Microsoft Swift Pair; recognition for Tile trackers,
  SwitchBot, and Samsung SmartThings Find tags. Encrypted
  MiBeacon and BTHome frames are named and flagged as
  encrypted, never decrypted. Fewer "unknown device" rows.
- **In the repo:** `tools/trace-view/` — a single-file, fully
  offline viewer for trace exports (drop a trace JSON on it;
  the file never leaves the machine) — and `tools/parity/` —
  shared fixtures pinning what the Swift and Kotlin trace
  engines provably do identically (rule parsing, reply
  signatures, reference extraction), with generated tests for
  both platforms. The rule parsers themselves were aligned to
  match: strict keywords, port range 1–65535, CRLF-safe —
  the same rule file now behaves the same on both phones.

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
