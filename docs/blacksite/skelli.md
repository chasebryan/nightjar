# Skelli at the console

Skelli — the intelligence in the Skelli tab — holds her own Blacksite shell. Anything the console can do, you can ask her to do in plain words from her chat, and she runs it herself: she never answers a request to run something by telling you where to tap.

## Asking

- **"run `<command>`"** — "run whois example.org", "run portscan 192.168.1.1 top". She executes the line on her shell and reads the results back to you with judgment, not as a raw dump.
- **Bare commands** — a short list of everyday lines also run directly when they are the whole message: `whois`, `dig`, `ping`, `census`, `eazy`, `diagnose`, `ps`, `jobs`, `fastfetch`, `neofetch`, and their kin. And `eazy <target>` works as a sentence of its own.
- **Near-misses forgiven** — mistype a tool's name by one letter ("whosis") and she runs the tool you meant, and tells you she did. Only names of five letters or more earn the forgiveness, so short words never get hijacked.
- **The battery by name** — "run eazy", "eazy demo.testfire.net": the full EAZY run, hers to drive (see [eazy.md](eazy.md)).
- **The bench by name** — every one of the bench's 290 commands runs from her chat the same ways: prefixed ("console: smbprobe 192.168.1.1"), by "run" ("run dnsdeep example.com"), or as the line itself with its target ("webaudit example.com"). The hostless instruments — the censuses and wire reads whose bare form is a real run — also answer to their name alone: "wirecensus", "satcensus", "randprobe". A bench verb whose bare form could only print its usage stays a question she answers from the manual instead. The gates bind her runs exactly as they bind the console's — when EMCON refuses a run of hers, she names the condition, in words.

## How a run comes back

- **Live, then settled.** Her runs use the room's live privileges — a command that talks to the wire is allowed to while she runs it, even in situations where the room's own shell would refuse (a capture in progress is the standing example). She waits until the output settles — a beat of quiet — and then answers once, with the head of what mattered.
- **Long output is filed, not dumped.** When a run outgrows chat, the full text is filed in **Deliveries** under the command's name and she tells you where it lives, speaking the findings rather than pasting the scroll.
- **A second line queues.** Ask for another run while one is live and the second waits its turn briefly rather than colliding.
- **On deadline, partial truth.** If a run hits its limit, she brings back what it produced and says it was cut — partial output is never dressed as complete.

## The fences

Some of the house stays hers to refuse, and she will say so in words rather than silently: Skelli runs audits and reads; exploitation, flooding, and credential guessing are not things she does at any wording (see the bench's own rules in [bench.md](bench.md)). The gates in [gates.md](gates.md) bind her shell as they bind yours — EMCON's probing condition refuses her runs too, and she names the condition when it does.

## Why ask her instead of typing

Because she reads the board before she answers. Ask her to collect the street's addresses and she runs the census and reports the house; ask what a result *means* and the run becomes a lesson. The console is the instrument; Skelli is the operator standing beside you at it.
