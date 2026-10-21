# The gates — what can refuse a command, and why it tells you

Blacksite is a loud instrument in a house that takes silence seriously. Four gates stand between a command and the wire. Every one of them refuses **in words**: a command that cannot run is told why, by name — never silently swallowed.

## EMCON — the house's condition

The EMCON Standard grades the whole house's emissions: **Open**, **Charlie** (guarded), **Bravo** (receive-only), **Alpha** (total silence). The console reads the condition in its header, and `emcon` in the console reads or sets it.

Wire-touching commands check the Standard before they run — the sweeps, knocks, censuses, port scans, the SNMP family, the bench, EAZY. Probing is an organ of its own: under a condition that forbids probing, those commands refuse and **name the condition**:

```
the Standard forbids this: emcon bravo is receive-only.
```

One-shot, hand-fired transmissions — a single payload you send yourself — are you speaking, and the doctrine treats the operator's own speech differently from standing emissions. Ask Skelli to run something and the same gates bind her shell; she names a forbidding condition the same way.

## Captures

While the house is capturing traffic, the room's own shell refuses wire commands — a capture is a listening posture, and the room will not talk over it. The exception is deliberate: **Skelli's live runs** are privileged, so work you asked her for in chat is not blocked by a capture you started. Your own next move, when the shell refuses, is to end the capture — or ask her.

## The stop word

`stop` is the room's brake, and it reaches everything: a sweep, a knock, a census, a port scan, an SNMP walk or audit, a directory search, a bench instrument, a program parked in `input()` (it is let go, answered with nothing), a secret prompt (answered with nothing), an open SSH session (disconnected). Wire commands check the word between steps, so the stop lands mid-run, not at the end of one. `halt` is the bigger word: the whole house stands down.

## Lockdown and quarantine

Two Sentinel instruments live in the room's command set:

- **`lockdown`** — the Sentinel's severe posture: total silence falls, every standing emission is stood down. It falls at your word, at Skelli's word, or on its own when two severe signs stack inside ten minutes. **`lockdown lift`** raises it and restores the condition that stood before.
- **`quarantine <ip> [via <gear>]`** — removes a device from your network *through your own credentialed gear*: its switch port is shut, and the shut is read back to prove it landed. `quarantine lift` opens the port again. It needs gear that can be administered — a house whose router offers no such lever is told so plainly; the command never pretends.

## Credentials, kept properly

The bench's credential commands (`cred set`, `cred set3`, `cred setssh`, `cred setunifi`) take secrets **typed in secret** — echoed as bullets, never written in a command line or the history — and hold them in the **Keychain**. SNMP read and write credentials are kept apart, by design, and a written object is always read back to show what landed. SSH host keys are trust-on-first-use: the first contact shows the fingerprint and asks; a key that ever changes is refused outright, and the Sentinel ledgers the change as a severe sign.

The complete inventory of commands these gates govern is [commands.md](commands.md).
