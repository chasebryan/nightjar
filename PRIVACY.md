# Nightjar — Privacy Policy

_Last updated: October 17, 2026_

Nightjar is built to watch networks, not people — and it starts
with its own developer.

## What Nightjar collects

**Nothing.** Nightjar has no accounts, no analytics, no
advertising, no crash-reporting SDKs, and no server of its own.
The developer receives no data from your use of the app — not
your captures, not your logs, not your messages, not usage
statistics. Nothing to sell, nothing to leak, nothing to hand
over.

## What Nightjar stores, and where

Everything the app records lives in the app's private storage
on your device: Bluetooth sighting logs, listening sessions,
messages you send and receive, packet captures in the inbox,
tripwire records, and your settings. The app offers export
(share sheets, files) for much of this — exporting is always an
action you take, to a destination you choose. Deleting the app
deletes all of it.

Message retention is yours to set: Knocktalk conversations can
be configured to delete themselves after an interval you choose.

## Permissions, and why

- **Bluetooth** — to hear nearby Bluetooth LE advertisements
  (Listen), optionally to advertise or host a payload you
  configure (Send), and to write to devices you pick. Listening
  never connects to anything.
- **Local Network** — to send payloads to, and receive payloads
  from, addresses you type (Send, Serve, Scan, Recon), to
  discover services with Bonjour, and to notice inbound probes
  (EMCON). Traffic goes only where you point it.
- **Notifications** — only to tell you something arrived, and
  never while stealth mode is on.
- **Camera** — to read Knocktalk Blink QR frames you point
  it at. Nothing is photographed or kept.
- **Microphone** — for Chirp, Knocktalk's sound carrier,
  when you use it.
- **Location** — iOS requires it before an app may learn
  the name of the Wi-Fi network it is on (shown in Scan),
  and the Map's compass uses it. The app does not track
  or record where you are.
- **Health** — the Instrument reads a paired Apple Watch's
  passive readings (heart rate, sleep, and kin) through
  HealthKit, only when you open its section. Read-only;
  the readings are never logged and never leave the phone.
- **NFC** — the Coin: reading tags you hold to the phone
  to claim or check in.

## Connections the app itself makes

Three, all of them ordinary web requests that carry no
account, no identifier, and nothing about your captures,
logs, or messages:

- **Update checks.** The app periodically asks GitHub
  whether a newer release of Nightjar exists. GitHub's
  servers see the request the way any web server does
  (including your IP address); nothing else is sent.
  This is compiled out of store builds.
- **Skelli's research.** When you ask Skelli to look
  something up, she queries public sources with your
  question. Details of your own house — private
  addresses, device names — are scrubbed before
  anything is sent. She only goes out when asked.
- **Model downloads, and the support door.** If you
  download an open-weights model from Skelli's Weights
  bench, it comes from the Hugging Face hub, which sees
  the download request like any file server. The
  support door in About likewise opens the author's
  Buy Me a Coffee page in your browser; the app never
  sees or touches payment details.

## Connections you configure

If you point Nightjar at a server — for example your own
Knocktalk relay — the app connects where you told it to. That
server is yours (or your peer's); it is not operated by the
developer, and what it can see is governed by you, not by this
policy. Knocktalk message content is end-to-end encrypted
between the two phones in all cases; a relay sees connection
timing and message sizes, never message text.

## Children

Nightjar is a professional network tool; it is not directed at
children, and it collects no data from anyone, of any age.

## Changes

If a future version ever changes any of the above — it would
have to gain a network service of its own to do so — this
policy will be updated and the version that ships will say so.

## Contact

Questions: open an issue at
https://github.com/chasebryan/nightjar-hack/issues
