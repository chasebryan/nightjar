# nightjar for iOS

The listening post in your pocket. A native SwiftUI + CoreBluetooth
companion app that captures listening sessions on an iPhone and writes
logs in nightjar's exact JSON Lines format, so a session recorded on
the phone feeds straight into `nightjar report` and `nightjar trackers`
on the Mac. Analysis stays on the Mac; the phone is ears.

**Receive-only.** The app scans for advertisements and logs them. It
never connects, pairs or transmits data: the only CoreBluetooth calls
in the source are `scanForPeripherals` and `stopScan` — `grep -r
"connect(" nightjar/` finds nothing.

Zero third-party dependencies, so it builds clean for sideloading.

## What it does

- **Sessions.** Start and stop a listening session, with an optional
  place label ("home", "office") typed at start. Each session is one
  `.jsonl` file.
- **Live list.** Everything in earshot, strongest first: name or decoded
  kind, RSSI with a trend arrow, a range band (immediate / near / far /
  faint), time since last heard, the decoded detail (AirPods battery,
  Find My state, Fast Pair model…), and the address. Quiet devices sink
  and dim.
- **Decoding.** The same identification the Mac does, ported from the
  Python: Apple Continuity (AirPods/Beats, iBeacon, Nearby Info, Nearby
  Action, Instant Hotspot), Find My separated and with-owner formats,
  Google Fast Pair, Eddystone and the Find My Device network, Tile,
  SmartThings Find, Exposure Notification, Microsoft CDP and Swift Pair,
  Ruuvi, and a maker table by company id. Tracker-shaped devices get a
  tag icon.
- **Getting logs to the Mac.** Three roads: the share sheet on the
  Sessions tab (AirDrop, Files, iCloud Drive, Mail…), the Files app
  (On My iPhone › nightjar › sessions — the app enables file sharing),
  or a cable (the same folder shows in Finder under the phone's Files
  tab).
- **Keep the screen awake** while listening (About tab; on by default),
  because foreground sessions hear the most.

Out of scope, on purpose: no analysis UI, no accounts, no networking,
no notifications.

## Install (sideloading with a free Apple ID)

You don't need a paid developer account. Xcode's free "Personal Team"
signing installs the app on your own phone.

1. Install Xcode from the Mac App Store (Xcode 16 or newer) and open it
   once so it finishes installing its components.
2. Open `ios/nightjar.xcodeproj` from this repository.
3. Sign in: Xcode › Settings › Accounts › `+` › Apple ID.
4. In the project navigator select the **nightjar** project, then the
   **nightjar** target › **Signing & Capabilities**. Tick *Automatically
   manage signing* and pick your Personal Team. If Xcode complains the
   bundle identifier is taken, change `net.nosuchmachine.nightjar` to
   something of your own (any reverse-DNS string).
5. Plug in the iPhone, unlock it, and tap *Trust* if it asks. Enable
   Developer Mode when iOS prompts for it (Settings › Privacy &
   Security › Developer Mode; the phone restarts).
6. Pick the phone in the scheme's device menu at the top of the Xcode
   window and press **Run** (⌘R).
7. The first launch is blocked until you trust the certificate on the
   phone: Settings › General › VPN & Device Management › your Apple ID
   › *Trust*. Then launch nightjar from the home screen.
8. Allow Bluetooth when asked. The permission text says what the app
   does: it listens and logs, and never connects.

To run the unit tests (decoder vectors and the log contract): Product ›
Test (⌘U). They run on the simulator too, where there is no Bluetooth
radio but the decoders don't need one.

### The 7-day expiry

Apps signed with a free Personal Team stop launching after **7 days**.
Nothing is lost: plug the phone in, open the project, press Run again,
and the app is re-signed in place. Logs live in the app's container
and survive the reinstall (and are in the Files app regardless).

## iOS realities

- **Foreground sessions hear everything.** Keep the app open (and the
  screen awake, the default) for a proper capture.
- **Background sessions hear only tracker tags.** The app declares the
  `bluetooth-central` background mode and restores its state if iOS
  relaunches it, so a session survives being backgrounded. But iOS
  does not deliver results for a background scan that asks for
  *everything*; it only delivers advertisements that carry one of an
  explicit list of service UUIDs. nightjar therefore switches a
  backgrounded session to scanning for the tracker services (Tile,
  SmartThings Find, Eddystone/Find My Device network, Fast Pair). That
  keeps hearing tags, and stops hearing phones, AirTags and anything
  else that broadcasts only manufacturer data — AirTags in particular
  carry no service UUID in their separated-mode broadcast. iOS also
  coalesces and throttles background results. The session file records
  what was heard either way; it doesn't invent what wasn't.
- **Addresses are UUIDs.** CoreBluetooth hides real MAC addresses and
  hands out a per-host identifier instead — the same limitation the Mac
  has. The identifier is stable for a device until it rotates its
  address, and different between the phone and the Mac. The Python
  side's identity resolution (payload fingerprints, names) is what
  stitches the two views together.
- **Scanning is active.** CoreBluetooth has no passive mode on iOS; the
  session header records `"scan_mode": "active"` so the Mac side knows.
- **Nothing is sent.** No analytics, no network access of any kind.

## The log contract

One file per session. The first line is the header, the last (when a
session ends cleanly) is the footer, and every line between is a
sighting:

```json
{"type": "session", "session_id": "1a2b3c4d5e6f", "label": "home", "label_source": "manual", "started_at": 1760000000.000, "scan_mode": "active", "format": 1, "nightjar_version": "ios-1.0"}
{"type": "sighting", "seen_at": 1760000001.250, "address": "778F707E-A2F9-1661-F38D-75A6A13CFCB5", "name": "AirPods Pro", "rssi": -58, "manufacturer_data": {"76": "0719010e20..."}, "service_uuids": ["0000feed-0000-1000-8000-00805f9b34fb"], "tx_power": null}
{"type": "session_end", "session_id": "1a2b3c4d5e6f", "ended_at": 1760003600.000, "sightings": 4312}
```

- `session_id`: 12 lowercase hex characters. `label`/`label_source`:
  the typed label and `"manual"`, or `null`/`null`. `started_at`,
  `seen_at`, `ended_at`: epoch seconds with three decimals.
- `address`: `peripheral.identifier.uuidString`.
- `manufacturer_data`: keys are the company id as a decimal string
  (`"76"` is Apple, `"6"` Microsoft, `"117"` Samsung); values are the
  payload *without* the two-byte little-endian company id, lowercase
  hex.
- `service_uuids`: full 128-bit lowercase UUIDs, including the
  overflow service UUIDs iOS reports for backgrounded Apple devices.
- `service_data` (present only when the advertisement carries any):
  full UUID → lowercase hex. `tx_power`, `name`, `rssi`: `null` when
  not in the advertisement (RSSI 127 means "unavailable" to
  CoreBluetooth and is logged as `null`).
- Records are assembled by hand (`JSONL.swift`), not by
  `JSONSerialization`, so field order and number formatting are fixed.
  `LogFormatTests.swift` pins the exact byte sequence of a sighting
  line; the Python test-suite in `tests/` reads the same vectors.

Everything the Mac's 2.x loader accepts is produced here; everything
the phone produces, the Mac's loader accepts, including a session cut
short without a footer (listed as unfinished on the phone, loaded as a
normal session on the Mac).

## Layout

```
ios/
  nightjar.xcodeproj/          project (Xcode 16 synchronized folders), shared scheme
  Support/Info.plist           Bluetooth usage string, background mode, file sharing
  nightjar/
    nightjarApp.swift          entry point, scene-phase handling
    ContentView.swift          Listen / Sessions / About
    ListeningPost.swift        CBCentralManager, sessions, state restoration
    Sighting.swift             the advertisement → log record
    JSONL.swift                encoding and the buffered writer
    SessionStore.swift         session files, listing, header/footer reading
    Continuity.swift           Apple decoders (port of nightjar/continuity.py)
    Services.swift             service UUID/data decoders (port of nightjar/services.py)
    Vendors.swift              Microsoft, Ruuvi, company table (port of vendors.py)
    Identify.swift             classification and the live-list row model
    Assets.xcassets            icon and accent colour
  nightjarTests/
    DecoderTests.swift         decoder vectors shared with the Python tests
    LogFormatTests.swift       the log contract, byte for byte
```
