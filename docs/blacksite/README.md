# Blacksite OS — the manual

Blacksite is the console inside **nightjar**: a small operating system that lives in a tab. It has a shell that answers to 413 commands, a kernel that runs real programs (Python and JavaScript, written by you, in its own editors), a files tree, a graphics bench — and a working pentest bench of 290 graded instruments and censuses, all of it operable either by typing or by asking Skelli, the intelligence who shares the house.

This folder is its full documentation.

## The room

Open the **Blacksite** tab and you get:

- **The header** — `BLACKSITE OS <version>`, the house's EMCON condition, resident memory, the clock.
- **The programs wheel** — hold and spin: the house's programs (the game room, the fetchers of the house card, the Grok and OpenAI-shaped clients, and more) launch from here.
- **The transcript** — everything the room says, kept to the last 400 lines; text can be selected and copied.
- **The command row** — the prompt, an **EAZY** button (the full audit battery, one tap — see [eazy.md](eazy.md)), and **RUN**.

Type `help` for the section index, `help <section>` for one section whole, `help <word>` to search every command. Type `stop` to stop whatever the room is doing. Type `halt` to stand the whole house down.

## The guides

- **[commands.md](commands.md)** — the complete command reference: every command, its signature, and what it does, generated from the same table the console's `help` reads.
- **[bench.md](bench.md)** — the pentest bench: the 290 bench commands in ten waves, what each one sends, how to read its grades, and the public practice ranges where using them is invited.
- **[eazy.md](eazy.md)** — the EAZY battery: doors, probes, the gateway's extras, access-point grading, and the filed report.
- **[skelli.md](skelli.md)** — Skelli at the console: running the room by asking, in plain words, from her chat.
- **[programs.md](programs.md)** — writing programs: the kernel, the Python dialect, the JavaScript engine, packages, the editors.
- **[gates.md](gates.md)** — the gates: EMCON, the stop word, captures, lockdown and quarantine — what can refuse a command, and why it will always tell you.

## The house rules, in one paragraph

Everything on the bench knocks once, reads the answer, and grades it in the open. Nothing floods, nothing sprays, nothing guesses credentials in bulk. The only secrets the tools ever try are the conventional anonymous ones — an SNMP `public` read, an anonymous FTP or LDAP hello, an unnamed MQTT connect — exactly once, as a posture check, because a door that opens for a stranger's default word is a finding. And every instrument grades only what it actually saw: a lock that cannot be tested from this device is reported as untestable, never as passed.
