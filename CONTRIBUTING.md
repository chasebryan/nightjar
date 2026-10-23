# Contributing to nightjar

The house is open. Contributions that keep the instrument honest, useful, and true to its posture are welcome.

nightjar is a native network instrument for iPhone and Mac, plus a Python overlay for an existing listening-post checkout. It is developed under the GNU Affero General Public License, version 3. By contributing, you agree that your work will be licensed under the same terms.

## Ways to help

- **Report** a reproducible bug or propose a feature with the issue templates.
- **Improve** documentation, especially platform limits, build notes, or Blacksite command help.
- **Add or strengthen** tests in `ios/nightjarTests` or the Python suite.
- **Polish** the CLI overlay, the OTA/SideStore flow, or the recon bench.
- **Review** open pull requests for correctness, especially around BLE advertising budgets, EMCON gates, and Knocktalk framing.

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

CI is path-aware. Changes under `ios/` run the Swift checks; changes under `nightjar/`, `tools/`, or `*.py` run the Python checks.

## Code style

- Prefer clarity and honesty over cleverness. The instrument reports what the platform actually allows.
- Keep platform limits explicit. Do not claim a capability the OS withholds.
- BLE advertising, GATT, and Knocktalk paths have tight budgets and framing rules. Respect them.
- New user-facing strings should be prepared for the twelve languages already present.
- Secrets, private captures, and real keys never belong in the repository or in issue attachments.

## What the house values

- Evidence over assertion.
- Fail-closed posture when a gate is set.
- Local-first behavior for Skelli and the Vault.
- A single, consistent voice across the app, the console, and the manuals.

Thank you for keeping the watch.
