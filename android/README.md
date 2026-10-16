# nightjar-hack for Android

The Kotlin/Jetpack Compose Android app for the **v3.0.0** release.
Package: `net.nosuchmachine.nightjarhack`; version code: **300**.
Requires **Android 8.0 (API 26) or newer** and Bluetooth LE.

## Download and install

[**Download nightjar-hack v3.0.0 APK**](https://github.com/chasebryan/nightjar-hack/releases/download/v3.0.0/nightjar-hack-v3.0.0.apk)

Open the link on your Android phone, open the downloaded APK, and allow
installation from your browser/file manager if Android asks. No ZIP extraction,
Android Studio, or account is needed to download the public release asset.
For USB installation: `adb install -r nightjar-hack-v3.0.0.apk`.

This is a release build, signed with the dedicated Nightjar Android release
key. The previous repository APK (v2.6.0) used a different debug certificate:
**export any sessions, presets, or other data you want to keep before
uninstalling that build**, then install v3.0.0. Uninstalling removes app data.
Future APKs signed with the same release key can update v3.0.0 in place.

The APK packages the Android implementation present at the v3.0.0 tag,
with corrected version metadata and a standard Gradle build. Its six tabs
are **Listen, Send, Serve, Scan, Sessions, and More**. It does **not** include
the iOS-only v3.0.0 Recon tab, EMCON, canary/Honeydrop, Knocktalk, Chirp,
brush pass, Blink, or time-capsule features. A shared version number does
not imply feature parity. See [the release notes](RELEASE.md) for build
provenance, verification, and the signing certificate.

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
    automatically when the run ends. In 2.6.0 the export
    is schema v2: the Listen tab's BLE sightings are filed
    in the map and the logbook (heard, never probed), and
    the Send setup (scope, ports, rules, route) saves as
    named presets — apply, share, import. The Listen
    decoders (`Decoders.kt` + `MoreDecoders.kt`) also grew:
    Xiaomi MiBeacon, BTHome v2, Govee, RuuviTag 3 + 5,
    AltBeacon, strict Swift Pair, Tile, SwitchBot,
    SmartThings Find — fewer "unknown device" rows.
  - `Engines.kt` — SnatchSteal, PayPlant (+ verify), timed
    delivery.
  - UI in Compose: boot splash, Jolly Roger backdrop, folding
    sections, Listen rows + per-device detail pages, the
    centipede splash playing the same `centipede.gif`.

## Platform differences from the iOS build (by design of the OSes)

- Android shows **real BLE MAC addresses**; iOS hides them
  behind per-host UUIDs. Listen rows/detail show the MAC,
  and a BLE write targets the address directly.
- Other iOS-only pieces: Shortcuts/Siri intents and
  peripheral-manager state-restoration wake.
- Android-only realities: runtime Bluetooth permissions,
  NSD instead of Bonjour.framework (same wire protocol).

## Building

Install JDK 17 and the Android SDK (platform 34 and build-tools 34.0.0),
then run from this directory:

```sh
export ANDROID_HOME=/absolute/path/to/android-sdk
./gradlew testReleaseUnitTest assembleDebug assembleRelease
```

The checked-in wrapper pins Gradle 8.7 and verifies its distribution checksum.
AGP is 8.5.2; Kotlin and the Compose compiler are 2.0.20. Version name, version
code, SDK levels, and the About screen derive from the Gradle configuration.
`assembleDebug` makes a locally debug-signed APK. `assembleRelease` makes an
**unsigned** APK; it is not the downloadable signed release.

To produce the release APK, use the private signing backup (never commit it):

```sh
export NIGHTJAR_KEYSTORE=/absolute/path/to/nightjar-android-release.p12
read -rsp 'Keystore password: ' NIGHTJAR_KEYSTORE_PASSWORD; echo
export NIGHTJAR_KEYSTORE_PASSWORD
./build-release.sh
unset NIGHTJAR_KEYSTORE_PASSWORD
```

This runs the parity tests, builds the release, signs it, verifies the APK
signature and alignment, and writes the APK, SHA-256 checksum, and certificate
report to `android/dist/`. `NIGHTJAR_KEY_ALIAS` defaults to `nightjar-release`.
The old machine-specific manual compiler pipeline has been replaced by this
Gradle pipeline; `manual-build.sh` forwards to `build-release.sh`.
