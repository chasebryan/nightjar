# nightjar

A passive Bluetooth Low Energy listening post.

Everything around you is gossiping in BLE advertisements — phones,
watches, earbuds, TVs, cars, tracker tags — each one broadcasting what
it is and how loud it is. Almost nobody listens. nightjar does: it
collects the advertisements, folds them into a registry of devices,
and over time learns the pattern of life of the space it sits in.

**Receive-only, by design.** nightjar never transmits, never connects,
never pairs. There is nothing to detect, because nothing is sent.

## Install

```sh
pip install .
```

For development:

```sh
pip install -e .
python -m unittest discover
```

## Use

Listen until you stop it:

```sh
nightjar
```

Listen for a minute, saving everything. Label the session with where
you're listening — the analysis commands use labels as places:

```sh
nightjar scan --duration 60 --label home --log sightings.jsonl --out devices.json
```

No Bluetooth hardware handy? Run against a fake neighbourhood —
a few resident devices, a tracker tag, and one phone that rotates its
address the way real phones do:

```sh
nightjar --simulate --duration 20
```

Every newly discovered device is announced as it appears; on exit you
get a summary: address, closest approach (strongest RSSI), sighting
count, name and maker where the broadcasts offer them.

## Analyze

Pattern of life over everything you've logged — who is a regular, on
which days, in which places, at what hours, and whose broadcasts get
decoded into plain language:

```sh
nightjar report --log sightings.jsonl
```

Hunt for a tag that is following you — tracker-shaped, turning up in
session after session, in more than one place, present at both ends
of a listening session. Suspects are reported with their evidence:

```sh
nightjar trackers --log sightings.jsonl
```

## Platform notes

- **macOS** — works out of the box, but CoreBluetooth hides real MAC
  addresses: devices appear under per-host UUIDs instead.
- **Linux** — needs BlueZ; the process needs Bluetooth capability
  (run as root, or grant `CAP_NET_RAW`/`CAP_NET_ADMIN` to the Python
  binary).
- **Windows** — works out of the box.

## The build, in levels

1. **Collection** — log every advertisement. ✅
2. **Registry** — fold sightings into devices with histories. ✅
3. **Identification** — read *what* a device is from its broadcast
   format and see through address rotation. Apple payloads are the
   rich vein: nightjar decodes the Continuity message chain,
   including Proximity Pairing — an AirPods sighting resolves to its
   model, both buds' battery levels, and whether the lid is open.
   Rotating phones are re-identified by a fingerprint of the stable
   core of their broadcasts. The fingerprint is *epoch-scoped*: a
   phone rotates those bytes along with its address on a schedule,
   so correlation is strong inside an epoch and fades across epochs —
   that fade is the privacy design working, and nightjar labels the
   basis of every identity honestly. AirPods model codes are
   best-effort, from public Continuity documentation. ✅
4. **Pattern of life** — presence over days and sessions: regulars,
   days present, usual hours, places heard. ✅
5. **Counter-detection** — flag the tag that keeps turning up near
   *you*: tracker-shaped, persistent across sessions and places,
   present at both ends of a session — the unwanted-tracking pattern
   the Apple/Google spec describes, scored with the evidence shown.
   ✅

## Scope

nightjar observes broadcast advertisements — signals devices send to
everyone, on purpose. Run it in spaces where you have a right to
listen. It does not intercept connections or private traffic, because
it cannot: it only hears what is shouted.

## License

AGPL-3.0 — see `LICENSE`.
