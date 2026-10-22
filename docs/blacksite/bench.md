# The pentest bench

The bench stands at 290 commands: the original graded instruments below, and ten waves of expansion after them — every one built under the same contract: **one knock, one read, one grade — in the open.** This guide is what each one sends and how to read what it says.

Run any of them from the console, or ask Skelli to run it (see [skelli.md](skelli.md)). The full signatures are in [commands.md](commands.md).

## The web read

| Instrument | What it does |
| --- | --- |
| `robots <url>` | Fetches `/robots.txt`: the disallowed paths are a map of what the site would rather you not enumerate, and the declared sitemaps are handed over as leads. Paths the site names but refuses everyone are not probed — naming them was the finding. |
| `webaudit <url>` | The posture audit: the six security headers, cookie flags (Secure, HttpOnly, SameSite), and what the server banner admits. Missing armour is a finding; present armour is read for quality, not just presence. |
| `vhost <host> [domain]` | Virtual-host discovery: a bogus-Host request sets the baseline, then a wordlist of names is asked at the same address. A name whose answer differs in status or size from the baseline is a different site living at that address. |
| `dirb <url>` | A directory wordlist walked politely — found, redirected, and forbidden are three different answers and are reported as such. A 403 is a door that exists. |
| `subdomains <domain>` | The names the certificate-transparency logs confess: every certificate ever issued to the domain is a public act, and the names on them are censused from the logs (crt.sh). Nothing is guessed and no wordlist is walked — a name that was never certified is not invented. |
| `methods <url>` | Which HTTP verbs the door honours. TRACE enabled is cross-site tracing waiting to happen; PUT and DELETE on a public door are findings. |

## Names and locks

| Instrument | What it does |
| --- | --- |
| `axfr <domain> <server>` | Asks a nameserver for its whole zone, once. Handed over is critical — the zone is the map of everything. REFUSED is the sound posture, and is reported as health. |
| `dnsaudit <domain>` | Asks four resolvers — your router and three public witnesses — and compares the answer sets. Disagreement is the finding: filtering, interception, or a resolver lying to someone. |
| `tlsgrade <host>[:port]` | Attempts a handshake pinned to each TLS version and reads **the version actually negotiated** — an attempt only counts as accepted when the negotiated version is the pinned one. Anything under TLS 1.2 that turns is a finding. When this device's own stack cannot offer an old version, the tool says the lock cannot be tested from here instead of guessing. |
| `cert <host> [port]` | The TLS papers: chain, expiry, names covered, and whether the certificate matches the door it guards. |

## The loud old doors

| Instrument | What it does |
| --- | --- |
| `reflect <host>` | The amplification audit: one small question at the old UDP doors — echo, chargen, daytime, the NTP monlist — and a DNS question for a name the server does not own. A door that answers a stranger with more than it was sent is reflector material; graded by the ratio. Silence is health. |
| `snmpaudit <host>` | The NSA's six SNMP mitigations (2026 CSI), graded from the wire: does v1 or v2c answer at all, do the conventional community words open it, does v3 stand where the old versions stood down. |

## Brokers, directories, and service doors

| Instrument | What it does |
| --- | --- |
| `mqttprobe <host>[:port]` | An unnamed MQTT CONNECT. Accepted is the finding's door; then a wildcard subscription listens briefly — a broker that lets a guest read everyone's topics is graded on what it volunteers. |
| `ldapprobe <host>[:port]` | An anonymous LDAP bind and a root-DSE read: what the directory tells a stranger about itself. |
| `ftpprobe <host>` | An anonymous FTP hello — accepted or refused, and the banner's confession either way. |
| `smtpprobe <host>` | The mail door's manners: banner, STARTTLS offered or not, and an external relay test that stops before DATA. It never sends mail. |
| `redisprobe <host>` | One PING. A Redis that answers an unnamed stranger is a finding, full stop. |
| `dockerprobe <host>` | The Docker API door: unauthenticated version/papers. An open Docker API is remote root wearing a name tag. |
| `proxyprobe <host:port>` | Asks the door to fetch a public page like a proxy would. A door that fetches for strangers is an open proxy — other people's floods leave from your address. |
| `vncprobe <host>` | The VNC handshake: which security types are offered. "None" offered is the finding. |
| `rdpprobe <host>` | The RDP negotiation: which protocol and encryption the door settles for; the old native mode is graded as the weaker lock. |
| `corsprobe <url>` | Cross-origin policy: a foreign origin and the `null` origin are offered. A reflected origin — above all with credentials allowed — is the finding; a flat refusal is health. |
| `openredirect <url>` | The classic redirect parameters are aimed at a witness address. A 3xx that follows the aim is an open redirect; a page that stays home is health. |
| `graphqlprobe <url>` | Asks the endpoint for its introspection. A schema volunteered to a stranger is counted — types, queries, mutations — because the map is the finding. |
| `jwtcheck <token>` | Pure local inspection — no wire at all: the header and claims read aloud, `alg: none` and a missing expiry flagged, staleness dated. |

## The ten waves

The expansion was built wave by wave, each wave one country of the wire. The doctrine never moved: knock once, read what answers, grade it in the open — and where a reading cannot be verified from this device, the instrument says so instead of dressing a guess as a grade. Every instrument below runs from the console, and every one runs from Skelli's chat by name (see [skelli.md](skelli.md)).

### Wave 1 — the web, read deep

The web instruments grow past the first read: `headersdeep` and `cookieaudit` grade the armour and the cookie flags line by line; `certchain` and `ocspprobe` read the certificate's whole family and its revocation witness; `hstsprobe`, `corsdeep`, and `csrftoken` test the policies a site declares against the ones it keeps. `faviconhash` fingerprints a site by the icon it cannot help showing. `techstack` and `wafdetect` report what a site *claims* to be — a fingerprint is the server's own confession, graded as a claim, never as proof. `redirectchain` walks a chain of doors to the last one; `oidcprobe` and `swaggerprobe` read the identity papers and API maps a site publishes; `wayback` and `sitemap` read what the public record kept.

### Wave 2 — the service doors

Every database and service door gets its nameplate read: `smbprobe`, `mysqlprobe`, `pgprobe`, `mssqlprobe`, `mongoprobe`, `memcacheprobe`, `kafkaprobe`, `etcdprobe`, `consulprobe`, `vaultprobe`, `k8sprobe`, `registryprobe`, and their kin each speak the door's own greeting protocol once — version, papers, posture — and grade what a stranger is told. Mail doors are read whole (`imap`, `pop3`, the `smtp` read); `starttlscensus` walks the doors that can upgrade to TLS and grades which ones insist. A door that answers an unnamed guest with its version and build has confessed the finding; the probes take the confession and leave.

### Wave 3 — names and mail

A domain's whole public posture: `dnsdeep` reads the record book entire, `spfprobe`, `dkimprobe`, `dmarcprobe`, `bimi`, `mtasts`, and `tlsrpt` grade the mail-authentication stack record by record — a missing DMARC policy is graded as the invitation it is. `dnssecgrade` reads the chain of trust and says where it thins; `danglingprobe` finds CNAMEs pointing at services nobody owns anymore, the takeover-shaped hole, and reports the shape without ever claiming the name. `certtrans` and `subdomains` census the certificate-transparency logs. `zonetransfer` asks once, as `axfr` always has: handed over is critical, refused is health.

### Wave 4 — industrial control

The factory floor, under the strictest line on the bench: **identification and posture only — no coil or register writes, no control function codes, ever.** `modbusprobe`, `s7probe`, `bacnetprobe`, `dnp3probe`, `enipprobe`, `opcuaprobe`, `iec104probe`, and thirty more read a device's nameplate in its own protocol — make, model, firmware, the identity it publishes to anyone who asks — and `plcensus` rolls a street of them into one board. Where a protocol's identity frame could not be verified byte-for-byte against its specification, the probe degrades honestly to a presence knock and prints that limit. The one read past the nameplate is `sunspecprobe`, which reads the SunSpec Common Model block — a published, read-only identity register, read as published.

### Wave 5 — the satellite ledger

Ground segment and public ledgers, never the spacecraft: **the bench never transmits a telecommand, never sends a SET or control command, and never originates RF.** `cspprobe` and `ccsdsprobe` census the ground-station doors; `aprsprobe`, `kissprobe`, and `agwprobe` read the amateur-radio gateways; `rotprobe` and `rigprobe` read a rotator's and a radio's reported position and state — reads, never a move. `gpsdprobe`, `nmeaprobe`, `ubxprobe`, and `ntripprobe` read the position services; `starlinkprobe`, `comtechprobe`, `bucprobe`, and `iridiumprobe` read the terminals' own identity pages. `satintel` and `satnogsprobe` read the public ledgers — Celestrak's element sets, checksum verified, and the SatNOGS station book — as published.

### Wave 6 — the street

The city's machinery, read with both hands visible. Signal and street furniture are read by SNMP **GET of identification objects only — never a SET, never a phase command**: `signalprobe`, `dmsprobe`, `rwisprobe`, `rsuprobe`, and `streetlightprobe` take nameplates, and `spatprobe` reads a published SPaT feed as published. Cameras answer `onvifprobe` and `camdeep` with their nameplates; `ptzprobe` censuses a camera's PTZ nodes and **never moves one**. `ridprobe` is a passive census of drone Remote ID broadcasts — it transmits nothing. `sirenprobe` reads a siren controller's identity and **never activates one**. The rest are public ledgers read as published: `flockcensus` counts the ALPR cameras the OpenStreetMap and DeFlock ledgers record for a place — the bench never touches any vendor's cloud, any plate database, or any captured data — and `dotprobe`, `towerprobe`, `gaugeprobe`, `gbfsprobe`, and `transitprobe` read the DOT camera ledgers, the FCC tower book, USGS gauges, air-quality and transit feeds.

### Wave 7 — the wire itself, and the public record

The local protocols read deep: `ssdpdeep` and `mdnsdeep` (where `upnp` and `bonjour` now lead) census every description document and service paper on the wire; `dhcpprobe`, `wsdprobe`, `v6probe`, `ntpprobe`, and `smallsvc` read the wire's housekeeping — who hands out addresses, what the old small doors still answer, whether the clocks agree. `wirecensus` rolls the whole wire into one board. The wave's other half is the public record, read as published: `kevprobe` and `cveprobe` (the known-exploited ledger outranks any score), `passivedns`, `rblprobe`, `urlscanprobe`, `torprobe`, `macprobe`, `geoprobe`, `ripeprobe`, `gleifprobe`, `ghprobe` — other people's ledgers, quoted, never embellished.

### Wave 8 — locks and ciphers

The locksmith's bench, and most of it never touches the wire: `cipherprobe`, `hashprobe`, `kdfprobe`, `aesprobe`, `eccprobe`, and `xorprobe` work a value you hand them — what algorithm, what strength, what it would cost to be wrong. `keyprobe`, `x509probe`, `pgpprobe`, and `sigprobe` read the papers of keys and certificates from files. `sshkeydeep` reads a host's presented SSH keys and grades the set; `tlscensus` censuses a host's whole TLS posture in one pass. `entropyprobe` and `randprobe` grade randomness by sampling it — `randprobe` bare samples this device's own system random, 65,536 bytes, and grades what it drew. Nothing here cracks, guesses, or sprays: it reads locks and says what they are.

### Wave 9 — the shield

The bench turned around: the same doors, graded as a defender. `sshposture`, `smbposture`, `snmposture`, `mailposture`, `headerposture`, `cookieposture`, `dirposture`, `dnsposture`, `printposture`, `nasposture`, `iotposture`, and `cameraposture` each take one surface of your own house and grade it against the published best practice. `guestprobe` grades the guest network's isolation from the wire it sits on; `metadataprobe` reads what a wire leaks about itself; `upnpgrade` grades the UPnP surface the wire census found. `patchprobe`, `kevcheck`, and `certwatch` watch the ledgers that matter — known-exploited first, expiry always — and `shieldcensus` rolls the whole shield into one board: what stands, what leans, what is open, in the open.

### Wave 10 — files

The evidence bench: files read, never executed. `magicprobe` names a file by its bytes, not its name; `peprobe`, `elfprobe`, and `machoprobe` read the executables' papers — hardening flags, sections, imports, the bytes past the last section where things hide. `exifprobe` and `imgdeep` read what images confess — camera, place, hour — and `pdfprobe`, `zipprobe`, `sqliteprobe`, `plistprobe`, `fontprobe`, `scriptprobe`, and `logprobe` open each format's book the same way. `stringsdeep` lifts a file's words; `dupprobe` finds the same bytes wearing two names; `dataprobe` grades a data file's shape; `filecensus` and `fileboard` roll a shelf of files into one graded board. A file's claims are read as claims — a header that lies is reported as lying, from the bytes.

## Practice ranges

Using the bench somewhere is only sporting where it's invited. These are kept for exactly that:

- **scanme.nmap.org** — the Nmap project's own scanning target.
- **demo.testfire.net** — a deliberately vulnerable banking demo (Altoro Mutual).
- **badssl.com** and its family (`expired.`, `self-signed.`, `tls-v1-0.` …) — TLS postures of every temper, for `tlsgrade` and `cert`.
- **test.mosquitto.org** — the public MQTT test broker, for `mqttprobe`.
- **zonetransfer.me** (server `81.4.108.41`) — a zone kept transferable, for `axfr`.
- **neverssl.com** — cleartext only, forever: the full HTTP stack with no secure side to hide behind.
- **countries.trevorblades.com/graphql** — a public GraphQL API with introspection on, for `graphqlprobe`.

And your own network is always in scope — that's the bench's home ground, and what [EAZY](eazy.md) is for.

## What the bench will not do

It does not flood, spray, brute-force, or exploit. It tries no credential beyond the conventional anonymous words, once each, as posture checks. An instrument that cannot see a thing says so — from inside a LAN, no tool here can tell you what your router shows the WAN, and none will pretend to.
