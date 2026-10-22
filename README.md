<p align="center">
  <img src="assets/readme/nightjar-hero.svg" width="100%" alt="nightjar — a NIGHTWARE LABZ network instrument">
</p>

<p align="center">
  <strong>The listening post. The mouth. The bench.</strong><br>
  A native network instrument for iPhone and Mac, with Skelli at the controls.
</p>

<p align="center">
  <a href="https://github.com/nightwarelabz/nightjar/releases"><img src="assets/readme/badge-release.svg" width="178" alt="Version 11.0 — churring"></a>
  <a href="#build-for-iphone"><img src="assets/readme/badge-ios.svg" width="130" alt="iOS 17 or later"></a>
  <a href="#build-for-mac"><img src="assets/readme/badge-macos.svg" width="154" alt="macOS 14 or later"></a>
  <a href="LICENSE"><img src="assets/readme/badge-license.svg" width="174" alt="GNU AGPLv3"></a>
</p>

<p align="center">
  <a href="https://github.com/nightwarelabz/nightjar/actions/workflows/nightjar-checks.yml"><img src="https://github.com/nightwarelabz/nightjar/actions/workflows/nightjar-checks.yml/badge.svg" alt="Nightjar checks"></a>
</p>

<p align="center">
  <a href="#get-started"><strong>Get started</strong></a> ·
  <a href="#inside-the-house">Features</a> ·
  <a href="docs/blacksite/README.md">Blacksite manual</a> ·
  <a href="#python-cli">Python CLI</a> ·
  <a href="https://github.com/nightwarelabz/nightjar/releases">Releases</a> ·
  <a href="#documentation">Documentation</a>
</p>

---

## Meet nightjar

nightjar began as an overlay that gave a receive-only BLE listening post a mouth. It has grown into its own instrument: a listening post, a protocol and recon bench, a defensive posture standard, an encrypted messenger, a cryptography vault, and **Blacksite**, the console inside the house.

**Skelli** is its onboard specialist. She reads the instrument's live state, works its controls, runs its console, and files what she makes in Deliveries. Her model inference runs on the device; requested research and model downloads use the network.

The **iPhone app is the flagship**. The native Mac app brings the same house to a sidebar and a larger screen. The Python send/serve overlay remains available for the desktop; the earlier Android port is preserved as a discontinued line.

| Platform | Place in the project | Start here |
| --- | --- | --- |
| **iOS 17+** | Flagship native app; no jailbreak required | [Build and sideload](#build-for-iphone) |
| **macOS 14+** | Native desktop app, built from the same Xcode project | [Build for Mac](#build-for-mac) |
| **Python CLI** | Send/serve overlay for an existing listening-post checkout | [CLI setup](#python-cli) |
| **Android** | Discontinued; historical source and build notes remain available | [Android archive](android/README.md) |

## Get started

Build from source with Xcode, or inspect the available assets on the [releases page](https://github.com/nightwarelabz/nightjar/releases). An iOS release package still needs signing and provisioning suitable for your device; the project has no App Store or TestFlight listing.

### Requirements

| Requirement | What you need |
| --- | --- |
| **Build tools** | A Mac with **Xcode 27 / Swift 6.4**, required by the checked-in package resolutions; see [development checks](docs/development.md) |
| **Metal Toolchain** | Install Xcode's Metal Toolchain component for the MLX build |
| **iPhone** | **iOS 17 or later**; a signing team selected in Xcode |
| **Mac app** | **macOS 14 or later**; select the `nightjar-mac` scheme |
| **Skelli's Apple model** | iOS 26, Apple Intelligence-capable hardware, and Apple Intelligence enabled |
| **Skelli's open-weights models** | Select and download a model inside **Skelli → Weights**; availability depends on the device's memory |

The project declares its MLX dependencies. Xcode resolves and builds them automatically; you do not add the packages by hand. The first build takes longer while those dependencies compile.

```bash
git clone https://github.com/nightwarelabz/nightjar.git
cd nightjar
open ios/nightjar.xcodeproj
```

### Build for iPhone

1. Select the **nightjar** target and open **Signing & Capabilities**. Enable **Automatically manage signing** and choose your team. Add your Apple ID in **Xcode → Settings → Accounts** if needed.
2. If the bundle identifier is unavailable for your team, choose a unique one. The source uses `net.nosuchmachine.nightjarhack`.
3. On the iPhone, enable **Settings → Privacy & Security → Developer Mode** and complete the requested restart.
4. Connect the phone, trust the Mac, select the phone as the run destination, and press **Run**.
5. If iOS asks you to trust the developer, open **Settings → General → VPN & Device Management**, select the signing identity, and trust it.
6. Launch nightjar, choose the house's language, and grant permissions as you use the relevant features.

**Free Personal Team signing lasts seven days.** Run the app from Xcode again to re-sign an existing installation. Each iPhone needs its own signing and trust setup. Settings are mirrored to the Keychain and can also be exported from About.

<details>
<summary><strong>Build stops because the Metal Toolchain is missing?</strong></summary>

Install it from **Xcode → Settings → Components**, use the download button shown with the build error, or run:

```bash
xcodebuild -downloadComponent MetalToolchain
```

This is a one-time component installation on that Mac. See the [full iOS build notes](ios/README.md#building-the-current-build) for the supported build setup.

</details>

### Build for Mac

Open the same project, select the **nightjar-mac** scheme and **My Mac** as the destination, choose a signing team if prompted, and press **Run**. The native Mac target uses macOS 14 as its deployment floor and presents the instrument in a sidebar shell.

### Stay current

The app checks GitHub for newer releases and shows available updates in Listen and About. When a release includes a compatible ad hoc build and install manifest, the app can hand the installation to iOS; otherwise it links to the release. Updates require your action.

The repository also carries a [SideStore source](sidestore-source.json). Its source address is:

```text
https://raw.githubusercontent.com/nightwarelabz/nightjar/main/sidestore-source.json
```

Signing, ad hoc distribution, and update setup are covered in the [installation and OTA guide](ota/README.md). Rebuilding from source remains available.

## Inside the house

**Fourteen rooms, one instrument.** A shared process board reports running work across the app. EMCON gates operations, the night log keeps the timeline, and themes, backdrops, haptics, language, and saved setup carry across the house.

| Room | What happens here |
| --- | --- |
| **Skelli** | On-device intelligence with live app state, real controls, a packet Forge, a code Workbench, a planning crew, and Deliveries. |
| **Listen** | Receive-only BLE sightings, a decoder bench, JSONL sessions, battery trends, tracker hunt, paired-operator flares, and device details. Listening never connects or pairs. |
| **Send** | A destination → payload → send flow, protocol payloads, per-target templates, fan-out, timed delivery, Centipede and Network Trace, plus War Chest, Helm, War Room, and War Games. |
| **Serve** | TCP, UDP, and HTTP listeners, fixed or echo replies, a receive inbox, stealth mode, BLE GATT hosting, and canary personas for SSH, HTTP, MQTT, and SMTP. |
| **Blacksite** | The built-in console: a shell, program editors, files, graphics, protocol and security audit instruments, and the EAZY battery. |
| **Sessions** | The night log: one hash-chained timeline for the instrument, designed to make alterations evident. |
| **Scan** | Connect scanning, subnet sweeps, TLS inspection, DNS, Bonjour, imported pcap dissection, device dossiers, Neighborhood, the SIGINT Station, and a floor-plan Map. |
| **Recon** | Protocol-speaking probes, a connection console, a seeded fuzzer, and a probe library that hands payloads to Send. |
| **EMCON** | A shared exposure audit and declared Charlie, Bravo, and Alpha conditions, with operation gates, tripwires, canaries, macros, and physical-key controls. |
| **Knocktalk** | Encrypted messaging carried by knock order, with repair, burn timers, an optional relay, and additional sound, BLE, QR, and time-lock carriers. |
| **Macros** | Block programs for the house, composed in the editor or dictated to Skelli, then run manually or from events. |
| **Vault** | Hashes, key derivation, authenticated encryption, password and public-key envelopes, encodings, randomness, and chunked file encryption. |
| **Onion** | Evidence-backed LAYERS posture scoring and a fail-closed SOCKS5 wrap for supported bench connections, coupled to EMCON. |
| **About** | Identity, permissions and policies, build provenance, setup import/export, diagnostics, updates, Colours, language, and support. |

### Blacksite: the console inside nightjar

Blacksite is a working room of its own: a command shell, a kernel for its Python dialect and JavaScript programs, editors, a file tree, and a graphics bench. The command reference is generated from the same table that feeds the console's help.

The audit bench speaks the protocols it examines and reports the evidence behind its grades. **EAZY** runs a coordinated battery and files its report in Deliveries. Skelli can work the console from her own chat, run the requested commands, and read the results back.

```text
help          Show the command sections
help bench    Read the audit bench help
ver           Show the build's version
log           Read the flight recorder
```

**[Open the Blacksite manual →](docs/blacksite/README.md)**

[Commands](docs/blacksite/commands.md) · [Audit bench](docs/blacksite/bench.md) · [EAZY](docs/blacksite/eazy.md) · [Programs](docs/blacksite/programs.md) · [Skelli at the console](docs/blacksite/skelli.md) · [Gates](docs/blacksite/gates.md)

### Skelli: the house's specialist

Skelli answers from the app's manual and live state, then works the relevant controls. Sweeps, serving, macros, posture changes, console work, packets, and code are actions she can perform inside the instrument.

- **Local minds.** Apple's on-device model is available on eligible devices; the Weights bench downloads and runs open-weights models locally.
- **Computed mathematics.** Her on-device evaluator computes supported expressions instead of estimating their answers. Requested STEM research can include source links.
- **Real work, kept.** Forge builds packets, Workbench drafts and runs code, and Deliveries keeps the results. Planner, hands, Critic, and Scribe can work a multistep request together.
- **A house with memory.** Her heart tracks tone and feelings; the Subconscious consolidates observations with their evidence. The optional Instrument reads passive HealthKit measurements, including Apple Watch data, on the device.
- **A shared language.** Skelli and the house follow the language selected in About.

Model inference is local. Research requests, model downloads, update checks, and connections you configure have their own network behavior; the [privacy policy](PRIVACY.md) describes those paths.

<details>
<summary><strong>More of the instrument: posture, messaging, cryptography, and the war program</strong></summary>

#### Defensive posture

EMCON's conditions use one audit so the tab, Skelli's pinned reading, and her situation report share the same exposure inventory. A condition silences forbidden operations and gates subsequent starts, including requests made through macros or Skelli.

Its controls include a fingerprinting tripwire, canary services and Honeydrop, an operator-configured knock vault, the dead hand, the NFC **Coin**, sparring seasons, two-phone duels, **Spoofy** personas, and **Banshee**, which restores the previous posture when stopped.

Onion adds a separate, evidenced view of tunnels, DNS posture, emissions, listeners, identity, and metadata. Its SOCKS5 wrap applies to supported shared-bench connections; the room identifies unsupported routes and does not claim to route other apps' traffic.

#### Knocktalk

The sealed message is carried by the **order of knocks**. Delivery repair follows the peer's measured rhythm and loss. Conversations support burn timers, per-operator cipher choice, and an optional [relay server](tools/knocktalk-relay/knocktalk_relay.py).

The same sealed box can travel through **Chirp** (sound), **brush pass** (BLE), **Blink** (QR frames), or **time capsules** (RSW time locks). Cadence Seal uses a peer's rhythm as a second factor; Throw Your Voice hands emission to a paired phone; Last Testament adds a dead-hand gate before its time-lock work can begin.

#### The Vault

The cryptography bench includes hashes, HMAC, HKDF, PBKDF2, ChaCha20-Poly1305, AES-256-GCM, password envelopes, P-256 dead-drop envelopes, a one-time pad, encodings, and secure randomness.

Whole files use the **NJCF** envelope: authenticated chunks under a random key, with password, device-key, combined, alternative, or recipient-public-key protection. The original filename travels inside the encryption.

#### The war program

**War Chest** applies a saved mission profile without starting its operations. **Helm** keeps named remotes for your own gear and a Learn mode. **War Room** coordinates Listen, the trace, and the knock bench on a subnet. **War Games** lets two of your phones spar and keeps score.

</details>

### Twelve languages

English · Español · Français · Deutsch · Português · Italiano · Русский · 日本語 · 한국어 · 中文 · العربية · हिन्दी

The first launch offers a language choice. It remains available in **About → Language** afterward; Arabic uses a right-to-left layout. Colours holds the themes, per-tab backdrops, boot-screen appearance, and the operator's own tailoring.

## Platform boundaries

The instrument reports what its platform can do. On iOS:

- **Scanning uses connections.** Network discovery uses connect scans. Raw SYN scans, ARP manipulation, packet injection, and live packet capture are outside the app's iOS interface; captures from another machine can be imported for dissection.
- **Foreground work follows iOS lifecycle rules.** Socket listeners and scheduled work depend on the app remaining active. BLE background hearing and armed GATT hosting have separate state-restoration behavior; force-quitting affects that behavior.
- **BLE identifiers are platform identifiers.** iOS withholds peripheral MAC addresses; choose a discovered device in the app. Advertisement payload space is limited, and the Send tab uses the fields iOS exposes.
- **Permissions follow the feature.** Bluetooth and Local Network enable the core benches; camera, microphone, NFC, location, and HealthKit support their corresponding tools. Wi-Fi name visibility depends on the available entitlement.

The [iOS manual](ios/README.md#honest-platform-limits) covers these boundaries in detail.

## Python CLI

The Python tools are supplied as an **overlay for an existing nightjar listening-post checkout** containing `nightjar/cli.py` and `pyproject.toml`. The overlay adds `send` and `serve` while preserving the scanner's receive-only path and log format.

### Apply the overlay

From this repository's directory, point the installer at your base checkout:

```bash
# Check that the expected patch anchors are present.
python3 apply_overlay.py /path/to/listening-post --check

# Apply to that same checkout, then install from the base directory.
python3 apply_overlay.py /path/to/listening-post
cd /path/to/listening-post
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
```

For BLE peripheral hosting, WebSocket, and serial transports, enable the optional transmit extra **inside the patched base checkout**:

```bash
python -m pip install -e '.[tx]'
```

BLE writes use the base scanner's `bleak` dependency. The `tx` extra supplies `bless`, `websockets`, and `pyserial`; the standard TCP, UDP, TLS, and HTTP paths use Python's standard library.

### Try a local exchange

In the first terminal:

```bash
nightjar send --help
nightjar send tcp://127.0.0.1:9000 --payload "hello" --dry-run
nightjar serve --host 127.0.0.1 --tcp 9000 --reply "ack"
```

In a second terminal, using the same environment:

```bash
nightjar send tcp://127.0.0.1:9000 --payload "hello from the other side" --read
```

| Command | Transports and behavior |
| --- | --- |
| `nightjar send TARGET [TARGET ...]` | TCP, UDP, TLS, HTTP(S), WebSocket, serial, BLE advertising, GATT hosting, and BLE writes; multiple targets fan out. |
| `nightjar serve` | TCP, UDP, HTTP, WebSocket, serial, and BLE GATT receiving; static, echo, or file replies, JSONL recording, and a relay tap. |

The [CLI manual](HACKER.md) covers payload sources, framing, transforms, `--expect`, `--follow`, `--replay`, and transport-specific options. The [Recon manual](HACKER-RECON.md) covers its probe bench.

<details>
<summary><strong>Single-file installer and removing the overlay</strong></summary>

The historical [nightjar-hack-single.py](nightjar-hack-single.py) bundle writes its embedded files into a base checkout and runs its embedded installer. For the current source files, use `apply_overlay.py` from this checkout.

The overlay leaves its edits in the base checkout's working tree. Inspect `git diff` there before rolling them back. If those files contain only the overlay changes, restore the tracked files and remove the added module:

```bash
git restore -- nightjar/cli.py pyproject.toml nightjar/__init__.py
rm nightjar/send.py
```

</details>

## Documentation

| Guide | What it covers |
| --- | --- |
| **[Blacksite OS](docs/blacksite/README.md)** | The console, command reference, audit bench, EAZY, programs, Skelli, and operation gates |
| **[iOS app](ios/README.md)** | Native app behavior, build setup, installation, and platform limits |
| **[Installation and OTA](ota/README.md)** | Signing, ad hoc distribution, SideStore, and update setup |
| **[CLI manual](HACKER.md)** | Transports, payloads, framing, transforms, replies, and recording |
| **[Recon manual](HACKER-RECON.md)** | The protocol probe bench |
| **[Trace viewer](tools/trace-view/README.md)** | Working with exported Network Trace data |
| **[11.0 release notes](release-notes-11.0.md)** | The churring release and its changes |
| **[Changelog](CHANGELOG.md)** | The project's release history |
| **[Privacy policy](PRIVACY.md)** | Local storage, permissions, research, downloads, and configured connections |
| **[Security policy](SECURITY.md)** | Private vulnerability reporting |
| **[License](LICENSE)** | GNU Affero General Public License, version 3 |

## Reports and contributions

**[Open an issue](https://github.com/nightwarelabz/nightjar/issues/new/choose)** for a reproducible bug or a feature request. Include the version, device, steps, and what you expected. Find the version in About or with `ver` in Blacksite; `log` shows the flight recorder. About's Developer section can export a diagnostic file.

Issues are public. Remove passwords, keys, private captures, and personal information from anything you attach. For a vulnerability, follow [SECURITY.md](SECURITY.md) and use the repository's private reporting route.

Use nightjar on devices and networks you own or have written authorization to test. The app carries the same authorized-use statement in About.

## About me

I'm Chase Bryan — cryptographer and builder. nightjar is my instrument: I build the tools I want to exist, and I build them in the open.

The rest of the shelf: **orange**, a language for specifying and verifying cryptography; **snoot**, a post-quantum crypto-inventory scanner; **mawkbox**, an encrypted text-to-audio modem; and **Magic Box**, keyless time-lock encryption.

<p align="center">
  <img src="assets/the-world-is-yours.gif" width="560" alt="The world is yours">
</p>

---

<p align="center">
  <a href="LICENSE">GNU AGPLv3</a> · <a href="PRIVACY.md">Privacy</a> · <a href="SECURITY.md">Security</a> · <a href="#">Back to top</a>
</p>
