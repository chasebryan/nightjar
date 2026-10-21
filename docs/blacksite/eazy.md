# EAZY — the full battery, one word

EAZY is the bench, sequenced. One tap of the **EAZY** button, one console line (`eazy [target]`), or one ask to Skelli ("run eazy", "eazy scanme.nmap.org") — and the room runs the whole audit battery against a target, streams it live, counts the findings, and files the report in **Deliveries** (the Skelli tab's doors) where it can be read, kept, and shared.

## The three shapes of target

- **No target** — your whole network: the gateway first, then every device on the neighborhood board, capped at twelve hosts so the run stays a battery and not a siege.
- **An address or a hostname** — that one host, the full battery.
- **An access point's name** — the AP is graded from the air: its band, channel width, and the strength of the lock it advertises. On **macOS**, where the system lets an app read the air, a named AP you are joined to then takes the full battery by address as well. On **iOS** the system shows no app a census of the air, and EAZY says so plainly instead of pretending: join the AP and run the battery, or aim it at the address.

## What runs, per host

Sixteen doors are knocked: `21 22 25 53 80 443 445 389 1883 2375 3306 3389 5900 6379 8080 8443`. Each open door gets the probe that belongs to it:

| Door | Probe |
| --- | --- |
| 21 | `ftpprobe` — the anonymous hello |
| 25 | `smtpprobe` — banner, STARTTLS, the relay manners |
| 389 | `ldapprobe` — the anonymous bind |
| 1883 | `mqttprobe` — the unnamed guest |
| 2375 | `dockerprobe` — the API papers |
| 3389 | `rdpprobe` — the negotiation |
| 5900 | `vncprobe` — the offered security types |
| 6379 | `redisprobe` — one PING |
| 80, 8080 | `robots`, `webaudit`, `corsprobe` over HTTP |
| 443, 8443 | `tlsgrade`, `webaudit`, `corsprobe` over HTTPS |
| 22, 53, 445, 3306 | Noted as open — the bench has no dedicated probe for these, and says so rather than improvising one |

The **gateway** takes three extras, because the gateway is where a network's posture is decided: `snmpaudit` (the NSA's six, graded), `reflect` (the amplification doors), and `dnsaudit` — your router's answers for a public name, witnessed against three public resolvers.

## Reading the run

- Output streams live; every finding is written as a finding, in the open, as it lands.
- The last line is the count: **"eazy: N findings across M hosts — the full run is filed in Deliveries."**
- Zero findings is a real result and is reported as one. A door that never answered is reported as never answered — not as closed, not as safe: *unseen* is a different word from *sound*, and EAZY keeps them apart.

## The gates

EAZY is probing, and the house's law applies (see [gates.md](gates.md)): it refuses under an EMCON condition that forbids probing, it will not start from the room's own shell while the house is capturing traffic (ask Skelli instead — her live runs carry that privilege), and `stop` ends it mid-run like anything else in the room.

## A first run to try

Your own gateway, then a practice range:

```
eazy
eazy scanme.nmap.org
```

The first grades the house you live in; the second knocks on a door the Nmap project keeps open for exactly this. The [bench guide](bench.md) lists more ranges and what each instrument inside the battery is really asking.
