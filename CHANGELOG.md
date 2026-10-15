# Changelog

## 2.1.0

Many ears, one brain — and a post that notices when the pattern breaks.

### Fusion (many posts)
- A session now carries a **post**: which ear heard it (the Mac, the
  phone, a sniffer by the door), separate from the *place* it was in.
  `--post NAME` / `$NIGHTJAR_POST` on `scan` and `watch` (default: the
  hostname); the iOS app writes its configurable post name. Logs from
  1.x and 2.0 load unchanged (no post).
- `report` shows which posts heard each device; `trackers` reports which
  posts a suspect was heard by.
- **Simultaneity exoneration**: when two posts at two different places
  hear one device within the same moment, it can't be a single tag
  riding with you — `trackers` now *clears* it, in a "Cleared by fusion"
  section, instead of flagging it. A tag carried from place to place in
  sequence is still a suspect. Postless logs behave exactly as 2.0.
- Loader gains `default_post` and `post_by_path`, so logs that never
  named a post can still be assigned one at read time.

### Anomalies (it thinks in places)
- New `nightjar anomalies <logs>` command: splits history into a
  baseline and a recent window and raises two things —
  **missing regulars** (a device normally here at this hour, in this
  place, that didn't show) and **new-at-odd-hour** arrivals (a
  never-seen, stable-identity device turning up when the place is
  normally quiet). `--observation-days`, `--json`.
- Honest by construction: it stays silent with too little baseline, and
  never judges a device whose identity rotates across epochs (it can't
  be matched day to day — the stitching problem, left unsolved on
  purpose).

### iOS
- An **update banner**: the app checks GitHub Releases and, when a newer
  version is tagged, shows a banner linking to it — honest that a
  sideloaded build can't self-install and must be re-run from Xcode.
  Manual "Check for updates" on the About tab.
- A settable **post name** (About tab) written into every session, so
  the Mac's fusion can tell the phone apart from the other posts.

## 2.0.0

The identity release. Summaries, the radar and the alerts now think
in *devices* rather than addresses, and the post is honest about what
its radio does.

### Scanning
- Passive scanning is requested first, with a one-line notice and a
  fallback to active scanning where the platform can't do passive
  (macOS never can; Linux needs BlueZ experimental features). `--active`
  and `--passive` pick a mode outright. The mode in force is recorded in
  the session header.
- `--adapter` selects the radio on Linux.
- Sightings now carry service data and, where the radio reports it, the
  address type (public / random static / resolvable private…).

### Identification
- Service-data decoders: Google Fast Pair, Eddystone UID/URL/TLM/EID,
  Google Find My Device network beacons, Tile, Samsung SmartThings Find,
  Exposure Notification.
- Microsoft CDP beacons name the device class (Windows desktop/laptop,
  Xbox, Surface Hub…); Swift Pair reports the display name.
- Ruuvi RAWv2 environmental readings.
- AirPods decoding follows the OpenPods layout: left/right buds (with
  the flipped-nibble rule), charging flags, case battery from the low
  nibble, colour, and a much larger model table.
- Find My: battery from the status byte's top bits, and the short
  "with owner" broadcast is recognized and *not* treated as a tracker.
- Nearby Action types and Tethering Source (hotspot battery/bars)
  are decoded; Nearby Info's action code is read from the low nibble.
- A curated company-id table and a table of well-known service UUIDs.
- Identity resolution keys named devices by name + fingerprint, keeps
  an address with the identity it was first assigned to, and upgrades a
  device's kind only to something more specific.

### Analysis
- `report`: per-device 24-hour activity profile, usual days, median
  signal, first/last seen and average stay (`--wide`), `--since`,
  `--place`, `--min-sessions`, `--sort`, `--json`; logs may be files,
  directories or globs.
- `trackers`: a close-range criterion, presence hours instead of
  first-to-last span, a threshold of 5 so a tag that merely lives
  somewhere you go doesn't qualify on persistence alone, `--ignore` for
  your own tags, confidence words, `--json`.
- New `show` command: everything the logs know about one device.
- New `demo` command: writes a labelled multi-day log with a following
  AirTag and runs the analysis on it.
- Log loading is per-file and tolerant: corrupt lines are skipped and
  counted, headed sessions are never split on quiet spells, footers set
  session ends, empty sessions are kept.

### Watch
- Alerts are objects: logged into the session file as `alert`
  records, printed, streamed with `--json`, and delivered by a
  background thread to Discord, Slack, ntfy or any JSON webhook.
- `--ignore`, `--warmup` and the tracker thresholds are flags.
- `--live` works in watch mode, with recent alerts under the radar.

### Everywhere
- `--help` and `--version` at the top level (they used to be swallowed
  by the implicit `scan`).
- `NIGHTJAR_LOG`, `NIGHTJAR_LABEL`, `NIGHTJAR_IGNORE`,
  `NIGHTJAR_WEBHOOK_URL`, `NIGHTJAR_WEBHOOK_FORMAT`.
- The live radar draws on the alternate screen, fits the terminal,
  shows range bands and time since last heard, and works in the
  Windows console.
- Place detection tries `system_profiler` on macOS and `iw` on Linux.
- `python -m unittest discover` works from the repository root; ruff,
  mypy and a CI matrix across Linux, macOS and Windows.
- An iOS companion app (`ios/`) that records sessions in the same log
  format.

## 1.1.0

Levels 1–5 and watch mode: collection, registry, Continuity decoding,
Find My recognition, identity resolution, pattern of life, tracker
hunting, Discord alerts, the live radar, Wi-Fi place labels.
