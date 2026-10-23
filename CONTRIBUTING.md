# Contributing to nightjar

nightjar is a native network instrument for iPhone and Mac, plus a Python
send/serve overlay. Changes should match the code that is already here.
The license is the [GNU AGPLv3](LICENSE): a contribution is offered under
that same license.

Use the instrument on devices and networks you own or have written
authorization to test.

## Reports

Bugs and feature requests use the [issue forms](https://github.com/nightwarelabz/nightjar/issues/new/choose).
Include the version from About, or from `ver` in the Blacksite console, the
device, and the steps. `log` shows the flight recorder. About's Developer
section can export a diagnostic file.

Issues are public. Leave out passwords, keys, private captures, and personal
information. A vulnerability goes through [SECURITY.md](SECURITY.md), not a
public issue.

## What you can run

The native app builds with Xcode. [docs/development.md](docs/development.md)
is the command reference: Xcode 27 / Swift 6.4, the Metal toolchain for the
MLX build, the iOS simulator tests, the Mac scheme, and the standalone
kernel test. This repository is often edited where Xcode is not installed;
a green Python or kernel run does not replace the app tests.

On a machine with Python 3.11 or newer:

```bash
python3 -m pip install pytest
python3 -m pytest tests/ -q
```

Optional WebSocket and serial tests skip when their packages are absent.

`send.py` and `nightjar/send.py` are the same file. The single-file
installer and `nightjar-hack-bundle.txt` embed that same text. The Python
suite checks all four stay in step, so a change to the overlay has to
update each copy.

The kernel lifecycle tests need Swift 5.9 or later and XCTest, and no
simulator:

```bash
tools/test-kernel.sh
```

## Localization

English is the source language. The twelve `Localizable.strings` tables
(Spanish, French, German, Swiss German, Portuguese, Italian, Russian,
Japanese, Korean, Simplified Chinese, Arabic, and Hindi) are held empty
on purpose, by the 2026-10-21 ruling. A wholly empty table is the current
state. A partially filled table is not: the in-app language check treats
that as a failure. Leave the tables empty, or replace one whole, with
format specifiers matching the English key.

## Changes

Keep a change small enough to read against the file it touches. Describe
what the code does now. The [changelog](CHANGELOG.md) records releases;
a pull request does not need a changelog entry unless the maintainer asks
for one.

Do not commit signing material, provisioning profiles, tokens, or private
captures.
