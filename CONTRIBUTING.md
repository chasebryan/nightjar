# Contributing to nightjar

The house is open. Contributions that keep the instrument honest, useful, and true to its posture are welcome.

nightjar is a native network instrument for iPhone and Mac, plus a Python send/serve overlay. It is developed under the [GNU AGPLv3](LICENSE): a contribution is offered under that same license.

Use the instrument on devices and networks you own or have written authorization to test.

## Ways to help

- **Report** a reproducible bug or propose a feature with the issue templates.
- **Improve** documentation, especially platform limits, build notes, or Blacksite command help.
- **Add or strengthen** tests in `ios/nightjarTests` or the Python suite.
- **Polish** the CLI overlay, the OTA/SideStore flow, or the recon bench.
- **Review** open pull requests for correctness, especially around BLE advertising budgets, EMCON gates, and Knocktalk framing.

## Reports

Bugs and feature requests use the [issue forms](https://github.com/nightwarelabz/nightjar/issues/new/choose). Include the version from About, or from `ver` in the Blacksite console, the device, and the steps. `log` shows the flight recorder. About's Developer section can export a diagnostic file.

Issues are public. Leave out passwords, keys, private captures, and personal information. A vulnerability goes through [SECURITY.md](SECURITY.md), not a public issue.

## Before you start

1. Read the [README](README.md) and the relevant manual:
   - [iOS app](ios/README.md)
   - [Blacksite](docs/blacksite/README.md)
   - [CLI](HACKER.md)
   - [Privacy](PRIVACY.md)
2. Confirm the issue is not already open.
3. For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Development setup

### iOS / macOS

- Mac with Xcode 27 / Swift 6.4 (see [docs/development.md](docs/development.md)).
- Metal Toolchain component installed.
- Signing team for device builds.

```bash
git clone https://github.com/nightwarelabz/nightjar.git
cd nightjar
open ios/nightjar.xcodeproj
```

Select the `nightjar` or `nightjar-mac` scheme, pick a destination, and run. Free Personal Team signing lasts seven days.

### Python CLI overlay

```bash
python3 apply_overlay.py /path/to/listening-post --check
python3 apply_overlay.py /path/to/listening-post
cd /path/to/listening-post
python3 -m venv .venv && . .venv/bin/activate
python -m pip install -e '.[tx]'
```

## What you can run

The native app builds with Xcode. [docs/development.md](docs/development.md) is the command reference: Xcode 27 / Swift 6.4, the Metal toolchain for the MLX build, the iOS simulator tests, the Mac scheme, and the standalone kernel test. This repository is often edited where Xcode is not installed; a green Python or kernel run does not replace the app tests.

On a machine with Python 3.11 or newer:

```bash
python3 -m pip install pytest
python3 -m pytest tests/ -q
```

Optional WebSocket and serial tests skip when their packages are absent.

`send.py` and `nightjar/send.py` are the same file. The single-file installer and `nightjar-hack-bundle.txt` embed that same text. The Python suite checks all four stay in step, so a change to the overlay has to update each copy.

The kernel lifecycle tests need Swift 5.9 or later and XCTest, and no simulator:

```bash
tools/test-kernel.sh
```

## Localization

English is the source language. The twelve `Localizable.strings` tables (Spanish, French, German, Swiss German, Portuguese, Italian, Russian, Japanese, Korean, Simplified Chinese, Arabic, and Hindi) are held empty on purpose, by the 2026-10-21 ruling. A wholly empty table is the current state. A partially filled table is not: the in-app language check treats that as a failure. Leave the tables empty, or replace one whole, with format specifiers matching the English key.

## Pull requests

1. Branch from `main`.
2. Keep changes focused. One concern per PR.
3. Match the existing voice and naming. The house has a consistent register; do not invent a second one.
4. Add or update tests when behavior changes.
5. Run the relevant checks locally when possible:
   - iOS: the Xcode test target
   - Python: the suite under `tests/`
6. Update `CHANGELOG.md` and any affected release notes for user-visible changes.
7. Open the PR against `main` with a clear title and description. Reference the issue if one exists.

CI is path-aware. Changes under `ios/` run the Swift checks; changes under `nightjar/`, `tools/`, or `*.py` run the Python checks. Under the house's PR-first rule, a pull request merges only when its checks are green.

## Code style

- Prefer clarity and honesty over cleverness. The instrument reports what the platform actually allows.
- Keep platform limits explicit. Do not claim a capability the OS withholds.
- BLE advertising, GATT, and Knocktalk paths have tight budgets and framing rules. Respect them.
- Secrets, private captures, and real keys never belong in the repository or in issue attachments.

## What the house values

- Evidence over assertion.
- Fail-closed posture when a gate is set.
- Local-first behavior for Skelli and the Vault.
- A single, consistent voice across the app, the console, and the manuals.

Thank you for keeping the watch.
