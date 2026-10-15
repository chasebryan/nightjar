# nightjar-hack for Android

A full Kotlin/Jetpack Compose port of the iOS app in
`chasebryan/nightjar-hack` (`ios/`), built 2026-10-15.
Same bundle id (`net.nosuchmachine.nightjarhack`), same
version (2.5.0), same six tabs, same engines.

## What's here

- `app/src/main/java/net/nosuchmachine/nightjarhack/` —
  ~7,900 lines of Kotlin:
  - `ListeningPost.kt` + `Decoders.kt` — receive-only BLE
    scanning, the Continuity/Services/Vendors/Remote ID
    decoders ported from the Swift, the device registry with
    smoothed-RSSI hysteresis ordering, and JSONL sessions in
    upstream nightjar's exact format.
  - `Mouth.kt`, `PayloadKit.kt`, `PayloadBook.kt` — payload
    building/framing/templating, the 19 library built-ins,
    TCP/UDP/TLS/HTTP sends with the note-before-completion
    reply invariant, fan-out, exchanges.jsonl history.
  - `Serve.kt` — TCP/UDP/HTTP listeners, static/echo/file
    replies, NSD (Bonjour) advertisement + phone discovery,
    stealth, arrival notifications, inbox.
  - `BleMouth.kt` — FFF0 service-data beacons, FFF0/FFF1
    GATT hosting, writes by MAC.
  - `ScanKit.kt` — port scanner + banners, TLS inspector,
    Bonjour sweep (the same ten types), subnet sweep, DNS
    toolkit, classic-pcap dissector.
  - `Crawl.kt` — the Centipede (route grammar, chain/seed,
    per-device walks, return leg, smart seed, harvest,
    subnet discovery) and Crosstalk.
  - `Trace.kt` — Network Trace: a bounded, operator-started
    map of one /24 (discovery knock, per-host profiling,
    library probes, reference-following to depth 3,
    frontier exhaustion), adaptive rules
    (`contains X => followup/tag/stop`) shared with the
    Centipede, the persistent crawl logbook, and the
    versioned JSON trace export
    (`net.nosuchmachine.nightjar.network-trace`). A
    "Trace & set up the Centipede" button loads every
    door a trace finds into the Centipede's route
    automatically when the run ends.
  - `Engines.kt` — SnatchSteal, PayPlant (+ verify), timed
    delivery.
  - UI in Compose: boot splash, Jolly Roger backdrop, folding
    sections, Listen rows + per-device detail pages, the
    centipede splash playing the same `centipede.gif`.

## Platform differences from the iOS build (by design of the OSes)

- Android shows **real BLE MAC addresses**; iOS hides them
  behind per-host UUIDs. Listen rows/detail show the MAC,
  and a BLE write targets the address directly.
- iOS-only pieces with no Android twin: Shortcuts/Siri
  intent, peripheral-manager state-restoration wake.
- Android-only realities: runtime Bluetooth permissions,
  NSD instead of Bonjour.framework (same wire protocol).

## Building

Standard Gradle project (AGP 8.5.2, Kotlin 2.0.20,
minSdk 26, targetSdk 34): open in Android Studio or run
`gradle assembleDebug`. The shipped APK was built in a
sandbox where the Gradle daemon could not run, so it was
produced by an equivalent manual pipeline (aapt2 + the
Kotlin embeddable compiler + d8 + zipalign + apksigner) —
see `manual-build.sh` for the exact steps used.
