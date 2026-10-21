# The pentest bench

Twenty-three graded audit instruments live in the console, beside the general wire tools (`ping`, `dig`, `curl`, `nc`, the port scanner). Every instrument follows the same contract: **one knock, one read, one grade — in the open.** This guide is what each one sends and how to read what it says.

Run any of them from the console, or ask Skelli to run it (see [skelli.md](skelli.md)). The full signatures are in [commands.md](commands.md).

## The web read

| Instrument | What it does |
| --- | --- |
| `robots <url>` | Fetches `/robots.txt`: the disallowed paths are a map of what the site would rather you not enumerate, and the declared sitemaps are handed over as leads. Paths the site names but refuses everyone are not probed — naming them was the finding. |
| `webaudit <url>` | The posture audit: the six security headers, cookie flags (Secure, HttpOnly, SameSite), and what the server banner admits. Missing armour is a finding; present armour is read for quality, not just presence. |
| `vhost <host> [domain]` | Virtual-host discovery: a bogus-Host request sets the baseline, then a wordlist of names is asked at the same address. A name whose answer differs in status or size from the baseline is a different site living at that address. |
| `dirb <url>` | A directory wordlist walked politely — found, redirected, and forbidden are three different answers and are reported as such. A 403 is a door that exists. |
| `subdomains <domain>` | The common names under a name, resolved one by one. What answers is the surface the domain admits to. |
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
