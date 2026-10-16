# Nightjar — Privacy Policy

_Last updated: October 16, 2026_

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
