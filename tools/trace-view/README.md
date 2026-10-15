# Trace viewer

A standalone viewer for nightjar-hack **Network Trace** exports
(`net.nosuchmachine.nightjar.network-trace`, schema v1 and v2).
One self-contained HTML file — no build step, no dependencies,
no network requests. It draws the map the export describes.

## Open it

Double-click `trace-view.html`, then either:

- drag & drop a `nightjar-trace-*.json` export anywhere on the
  page, or
- click **Open a trace JSON…** and pick the file.

To try it without a real trace, serve the folder over http and
click **Load the sample trace** (browsers block the sample fetch
from `file://`, so the button hides itself in that case):

```sh
cd tools/trace-view
python3 -m http.server
# then open http://localhost:8000/trace-view.html
```

## What it shows

- **Header** — scope, run window, how the run ended, the
  settings it ran with, and the export's summary counts.
- **Map** — the phone at the center; hosts on a ring (IP +
  door count, click one to jump to its table row); service
  dots around each host; evidence edges from the export
  (`references` in amber, `bonjour` in teal — hover anything
  for the evidence text); BLE devices, when the export has
  them (schema v2), on a violet outer ring.
- **Hosts & doors** — every dossier: open services with
  banner first lines, notes, and probes used; tags; first /
  last seen and sighting counts. Hosts new in this trace are
  tinted green; services the diff marks changed get an amber
  dot, new services a green dot.
- **Side lists** — Bonjour announcements; external references
  (recorded, never contacted — the trace writes them down and
  does not touch them); the run's diff against the logbook
  (new / missing hosts, new / missing / changed services);
  the export's limitations, verbatim.

Rendering is defensive: a field the export omits is shown as
absent, never as an error.

## Privacy

The viewer runs **fully offline**. The trace file is parsed
in your browser and never leaves the machine — there is no
upload, no analytics, and the page makes zero external
requests. A trace describes your network in detail; treat
the export (and this folder) accordingly anyway.

## Files

- `trace-view.html` — the viewer (all CSS/JS inline).
- `sample-trace.json` — a synthetic, schema-faithful sample
  (a 192.168.4.0/24 home network: gateway, NAS, Pi, printer,
  an IoT plug that names the Pi's MQTT broker, a camera the
  diff has never seen before, and three BLE devices).
