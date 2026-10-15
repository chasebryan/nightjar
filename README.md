# nightjar-hack — quickstart

**2.6.0.** An overlay that gives the nightjar BLE listening post the
ability to send payloads out over the network and Bluetooth, without
disturbing the receive-only scanning it was built around — and, in
`ios/`, a full iOS app: the listening post, the mouth, and a pocket
recon kit in one Jolly-Roger-wearing build.

## 60 seconds (the CLI)

    # 1. get the upstream repo (nothing was uploaded; just clone)
    git clone https://github.com/chasebryan/nightjar
    cd nightjar

    # 2. lay the overlay on top
    python3 /path/to/nightjar-hack/apply_overlay.py .

    # 3. install
    pip install -e .
    pip install 'nightjar[tx]'      # only needed for ble:// and ble-gatt://

    # 4. try it
    nightjar send --help
    nightjar send tcp://127.0.0.1:9000 --payload "hello" --dry-run
    nightjar serve --tcp 9000

Then, in a second terminal:

    nightjar send tcp://127.0.0.1:9000 --payload "hello from the other side" --read

The first terminal prints the hexdump and answers. The full manual —
every transport, framing, transform, and trick (`--expect`,
`--follow`, `--replay`, serve responders and the relay tap) — is
[HACKER.md](HACKER.md).

## Single-file route

If you would rather not unzip anything, use nightjar-hack-single.py: it
writes the same files into the checkout and then calls apply_overlay.py.

## What the CLI adds

    nightjar send TARGET [TARGET...]   payload out: tcp, udp, tls, http(s), ws(s), serial, ble, ble-gatt, ble-write — several targets fan out
    nightjar serve [...]               payload in: tcp, udp, http, ws, serial, ble-gatt; static/echo/file replies; a relay tap

## The iOS app

`ios/` merges upstream nightjar's iOS listening post (unchanged where
it counts, Remote ID drone decoding included) with the mouth and a
recon bench:

- **Listen** — the purist half: receive-only BLE, sessions in the
  same JSONL the Mac tools read.
- **Send** — the 1-2-3 flow with a 19-payload protocol library,
  `{{host}}`/`{{port}}` templating, one-tap phone-to-phone targets,
  a **fan-out** list (typed, imported, harvested from scans, or
  ranges like `192.168.1.10-40:6379`), **timed delivery** (delay
  and repeat), **SnatchSteal** (knock, then drain everything the
  target sends back), and **PayPlant** (MQTT retained publishes,
  Redis/memcached stores — payloads that stay living on a service).
- **Serve** — TCP/UDP/HTTP listeners with fixed or echo replies,
  a notification-bannering inbox, stealth mode, and an arm-once
  BLE GATT host that survives backgrounding and relaunches.
- **Scan** — TCP connect scanner with banner grabs, a /24 subnet
  sweep, an **observation feed** that narrates hosts and services
  coming and going, a TLS certificate inspector (hand-rolled DER
  validity parsing — iOS offers no API for it), a real DNS toolkit,
  Bonjour services that resolve to addresses on tap, and a **pcap
  dissector** that takes apart captures from your own machines in
  plain text. Everything the tabs do lands in one exportable
  history file — which the log sheet can also delete.
- It boots like an OS: Jolly Roger emblem, wordmark, and a live
  boot log (your device, your IP, your library) over a progress
  bar. Build and install notes are in [ios/README.md](ios/README.md).

## What it does not do

It does not change how scanning works, does not touch the log
format, and does not add a dependency to the default install.
Network sending is pure standard library. BLE writes reuse the
`bleak` that scanning already needs. Only the peripheral role
(broadcasting / GATT server) and the 2.4 transports pull in the
optional `tx` extra, and only if you ask for it.

It is a testing instrument for devices and networks you own, or
that you are engaged in writing to test — the app carries the same
statement in its About tab.

## Uninstall

    git checkout nightjar/cli.py pyproject.toml nightjar/__init__.py
    rm nightjar/send.py

Nothing was committed, so `git status` shows the overlay as your working
tree changes and `git diff` shows exactly the six edits.
