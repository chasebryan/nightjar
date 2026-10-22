# Blacksite OS — the complete command reference

Every command the console answers to, with the signature it takes and what it does — generated from the same table the console's own `help` command reads, so this page cannot drift from the shipped truth. Inside the console: `help` shows the sections, `help <section>` opens one whole, `help <word>` searches every command.

**413 commands in 9 sections.**

## the house (29)

| Command | What it does |
| --- | --- |
| `sys` | the whole house state |
| `ps` | processes, live and recent |
| `fastfetch` | the machine's calling card |
| `diagnose` | put the whole house through its paces — engines, kernel, containment drills |
| `limits` | what this room honestly cannot do — the true limits, named |
| `neofetch` | the same card, under a crescent moon |
| `jobs` | the kernel's live programs |
| `kill <pid>` | stop a program — the kernel reclaims it |
| `run x.py &` | a trailing & backgrounds a program |
| `scan [port]` | sweep the /24 on a port (default 80) |
| `knock <host> [ports]` | knock a host (default: the top doors) |
| `census` | knock every device on the neighborhood board |
| `eazy [target]` | the full battery — doors, then the probe that belongs to each door, then a filed report; no target means this network, a name means an access point |
| `decode <hex>` | raw advertisement bytes through the decoders |
| `company <id>` | who a company id belongs to |
| `port <n> [udp]` | what a port is for |
| `emcon [open\|charlie\|bravo\|alpha\|off]` | read or set the condition |
| `macro list \| run <name>` | the macro library, run from here |
| `gauntlet` | run the gauntlet |
| `freedoom` | play freedoom — the big one |
| `journal [n]` | the house journal |
| `log [n]` | the flight recorder |
| `tomato list\|throw\|wipe` | the standing marks |
| `theme [name]` | list or switch the house theme |
| `haptics on\|off` | the house's motor |
| `skelli <words>` | ask her — she answers in her room |
| `open <tab>` | go to a tab |
| `halt` | stop everything, now |
| `stop` | stop whatever is running in this room — a sweep, a knock, a walk, a program |

## the wire (14)

| Command | What it does |
| --- | --- |
| `ping <host> [-c n]` | ICMP echo, by hand |
| `traceroute <host>` | the road, hop by hop |
| `dig [@server] <name> [type]` | ask DNS directly, wire format |
| `nslookup <name>` | A + AAAA, the short way |
| `host <name\|ip>` | resolve — or reverse an address |
| `whois <domain>` | whose name is it |
| `curl [-I] [-H h] [-o f] <url>` | fetch a page, see its papers |
| `wget <url> [file]` | fetch it into the files |
| `nc [-u] [-z] <host> <port> [words]` | a raw conversation |
| `telnet <host> [port]` | the old handshake |
| `ifconfig` | this phone's interfaces |
| `arp` | the neighborhood board — our arp table |
| `netstat` | this house's doors and wires |
| `hostname` | who this phone is on the wire |

## pentest bench (290)

| Command | What it does |
| --- | --- |
| `discover [a.b.c]` | who lives on the /24 — ICMP sweep |
| `portscan <host> [top\|a-b\|all\|list]` | every door, banners too |
| `banner <host> <port>` | make a door introduce itself |
| `revdns [a.b.c] [server]` | reverse-walk a /24 |
| `nbstat <host>` | NetBIOS names and the adapter |
| `snmp <host> [community]` | ask the agent (default public) |
| `snmpaudit <host>` | the NSA's six SNMP mitigations (2026 CSI), graded from the wire |
| `router` | which neighbor is the router — crowned by the default route, ranked by signs |
| `mndp [seconds]` | hear MikroTik introduce itself (UDP 5678) |
| `cred set <host>` | keep a credential for your own gear — typed in secret, held in the Keychain |
| `cred set3 <host> <user> <md5\|sha> [des\|aes] [read\|write]` | keep an SNMPv3 user — its auth and privacy words, typed in secret; read and write are kept apart |
| `cred hosts` | the hosts holding a kept credential (never the secrets) |
| `cred forget <host>` | let a kept credential go |
| `snmpwalk <host> [community] [root]` | walk the MIB with the kept or given community |
| `snmpset <host> <oid> <s\|i\|t\|a\|o> <value>` | write one object on your own gear, then read it back |
| `snmp3walk <host> <user> [root]` | walk the MIB as a kept SNMPv3 user — signed, and sealed when privacy is kept |
| `snmp3set <host> <user> <oid> <s\|i\|t\|a\|o> <value>` | write one object as that v3 user, then read it back |
| `ssh [-p port] [user@]host [command]` | open SSH to your own gear — no command opens a shell; her client, curve25519 + AES-GCM |
| `sshkey [make\|forget]` | the house SSH identity — an ed25519 key whose private half never leaves the Keychain |
| `sshhosts [forget <host>]` | the host keys you have trusted, kept by fingerprint |
| `sshbackup [user@]host <command>` | run a command and seal its output into the Vault, filed in Deliveries |
| `cred setssh <host> <user>` | keep an SSH word for a host — typed in secret, held in the Keychain |
| `cred setunifi <host> <user>` | keep a UniFi controller login — typed in secret, held in the Keychain |
| `unifi <host> devices\|clients` | the controller's adopted devices, or who is on the wire through it |
| `unifi <host> restart <device>` | restart one adopted device — asks first |
| `unifi <host> block\|unblock <client>` | bar a client from the network, or readmit it — asks first |
| `upnp` | UPnP on this wire, read deep — every SSDP description document censused |
| `bonjour` | the wire's own service index — DNS-SD enumeration, instances and papers censused |
| `cert <host> [port]` | audit the TLS papers |
| `webaudit <url>` | headers, cookies, posture |
| `robots <url>` | the map the site posts of itself — disallowed paths and the sitemap |
| `vhost <host> [domain]` | who else lives at this address — virtual hosts by their answers |
| `axfr <domain> <server>` | ask a nameserver for its whole zone — handed over is critical |
| `tlsgrade <host>[:port]` | which TLS versions still turn — anything under 1.2 is a finding |
| `reflect <host>` | the amplification audit — one packet at the old UDP doors, graded by the answer |
| `mqttprobe <host>[:port]` | does the broker let an unnamed guest in, and what does it tell them |
| `dnsaudit <domain>` | do the resolvers agree — your router against three public witnesses |
| `corsprobe <url>` | cross-origin policy — reflected origins, wildcards, credentials |
| `openredirect <url>` | do the exit parameters walk off the site |
| `graphqlprobe <url>` | is the schema posted on the door |
| `jwtcheck <token>` | a JWT, decoded and graded — no wire |
| `proxyprobe <host[:port]>` | will it fetch the outside for strangers |
| `vncprobe <host>` | the framebuffer's security types — 'None' is critical |
| `rdpprobe <host>` | which RDP dialect it will speak — legacy, TLS, or NLA |
| `ftpprobe <host>` | banner, and the conventional anonymous word |
| `smtpprobe <host>` | the mail door's manners — VRFY, STARTTLS, relay posture |
| `ldapprobe <host>` | anonymous bind, and what the RootDSE tells strangers |
| `redisprobe <host>` | one PING — PONG without a password is critical |
| `dockerprobe <host>` | an unauthenticated Docker API is the host itself |
| `headersdeep <url>` | every header on the answer, read whole |
| `cookieaudit <url>` | every cookie, and the flags each keeps or breaks |
| `cacheprobe <url>` | how caches are told to treat the answer |
| `wafdetect <url>` | which shield shows its badge on an ordinary knock |
| `techstack <url>` | the stack, fingerprinted from what the answer gives away |
| `sitemap <url>` | the house's own map of itself |
| `faviconhash <url>` | the icon's MurmurHash3 — the badge hunters search by |
| `httpversion <url>` | which HTTP the house speaks, read off its status lines |
| `hstsprobe <url>` | the https-only promise — set, long, and honored |
| `certprobe <url>` | the leaf's papers against the name you knocked on |
| `certchain <url>` | every paper in the chain, leaf to root |
| `ocspprobe <url>` | where revocation lives — responder, stapling, must-staple |
| `redirectchain <url>` | the chain walked hop by hop — downgrades and circles |
| `jsendpoints <url>` | the API doors the page's own scripts name |
| `swaggerprobe <url>` | the API's published spec doors |
| `oidcprobe <url>` | the OpenID discovery document, read whole |
| `graphqldeep <url>` | the endpoint's manners — schema, suggestions, batching |
| `jwtdeep <token>` | a token read to the bottom — header edges and claims |
| `compressprobe <url>` | gzip, deflate, brotli — does the house squeeze |
| `methoddeep <url>` | the write verbs tried empty-handed on a nothing path |
| `robotsdeep <url>` | robots.txt graded — and the doors its map advertises |
| `apicensus <url>` | one answer as an API citizen — limits, pages, challenges |
| `urlextract <url>` | every road out of the page, sorted |
| `wayback <domain>` | what the public archive remembers of the house |
| `corsdeep <url>` | cross-origin, deepened — null origins, subdomains, preflight |
| `smbprobe <host>` | one SMB2 negotiate — the dialect, and whether signing is truly required; no session, no name offered |
| `nfsprobe <host>` | the export list mountd publishes to strangers — what is shared, and with whom |
| `rpcprobe <host>` | the portmapper's whole directory — every registered program, version and door |
| `mysqlprobe <host>` | the greeting read — version, capabilities, the password door it names; no answer is ever sent back |
| `pgprobe <host>` | will it seal the road — S, N or E to the SSL and GSS questions; no startup packet follows |
| `mssqlprobe <host>` | the TDS prelogin — version, instance, and the encryption word; no login packet |
| `mongoprobe <host>` | the unauthenticated hello — wire versions and posture, by the protocol's own design |
| `elasticprobe <host>` | the cluster's own introduction — name, node, version, handed to a stranger |
| `couchprobe <host>` | the welcome mat — version and features, public by design |
| `kafkaprobe <host>` | the dialect table — every verb the broker speaks, which dates it |
| `zkprobe <host>` | four letters, read — stat and envi: version, mode, the tree it watches |
| `memcacheprobe <host>` | version, then the whole stats ledger — classic memcached keeps no names at all |
| `solrprobe <host>` | the admin system document — Solr and Lucene versions, and the ensemble it names |
| `jenkinsprobe <host>` | the version in the letterhead — and whether the dashboard opens unnamed |
| `gitlabprobe <host>` | the version door's challenge — a 401 keeps the forge's papers indoors |
| `registryprobe <host>` | the /v2/ threshold — a greeting, or the token challenge read and never answered |
| `k8sprobe <host>` | the API server's version papers — and /api, when the first door answers unnamed |
| `etcdprobe <host>` | the version door — server and cluster versions, published by design |
| `consulprobe <host>` | who leads the raft, asked with no token — the agent API is a control plane |
| `vaultprobe <host>` | the seal-status — sealed or unsealed, initialized, and the version beside it |
| `rabbitprobe <host>` | the AMQP introduction — dialect and mechanisms before any name; the management door read the same way |
| `printerprobe <host>` | the printer introduces itself — name, model, state, and where it sits |
| `rtspprobe <host>` | the camera's OPTIONS — the published verbs and the Server letterhead |
| `sipprobe <host>` | one SIP OPTIONS — the Allow list and the PBX's letterhead; no call is placed |
| `starttlscensus <host>` | the mail doors graded — STARTTLS offered, demanded, or missing; no name is ever given |
| `dnsdeep <domain>` | every record family of one name, read whole — A, AAAA, MX, NS, TXT, SOA, CAA |
| `zonetransfer <domain> [server]` | ask a nameserver for its whole zone, once — handed over is critical, refused is correct |
| `reverseprobe <ip>[/28]` | the names behind the numbers — one address, or a small street read as a summary |
| `dnscensus <domain>` | the same question to your router and three public witnesses — disagreement is the story |
| `wildcardprobe <domain>` | ask for a name that cannot exist — if it answers, the zone answers everything |
| `caacheck <domain>` | who may issue certificates for the name, and whether a watch stands (CAA) |
| `ttlprobe <domain>` | how long each family's answer may be remembered — the cache posture |
| `soacheck <domain>` | the zone's own ledger — the serial's convention, the refresh rhythm, the negative lifetime |
| `nsecprobe <domain>` | can the zone be walked — NSEC names the neighbours, NSEC3 hashes them first |
| `dnssecgrade <domain>` | the DNSSEC chain as far as the wire shows it — DS, keys, signatures, the resolver's AD word |
| `mxprobe <domain>` | where the mail goes — the exchangers in their order, the null MX, both roads |
| `smtpdeep <host>` | the mail door's greeting and EHLO census — no mail sent, no AUTH ever tried |
| `smtptls <host>[:port]` | rise the sealed road on the mail door itself, and grade the papers it shows |
| `spfprobe <domain>` | who may sign letters with this name — the ten-lookup budget counted, the terminal word graded |
| `dkimprobe <domain>` | the signing keys under the twelve common selectors — their weights and revocations |
| `dmarcprobe <domain>` | what a forgery costs — the policy, the enforcement share, where the reports flow |
| `mtasts <domain>` | the mail road's published seal — the DNS half and the policy, read together |
| `tlsrpt <domain>` | where broken mail seals are reported — or that nobody anywhere is told |
| `bimi <domain>` | the face beside the letter — the brand mark, and whether it stands verified |
| `certtrans <domain>` | every certificate the public logs remember for the name — issuers, coverage, the last minting |
| `subdomains <domain>` | the subdomains the public certificate logs confess — no dictionary, no brute force |
| `whoisdeep <domain>` | the registry's ledger, parsed — keeper, birth, lapse, and the standing words |
| `rdap <domain\|ip>` | the registry's modern ledger for a domain or an address, structured and whole |
| `asnprobe <ip>` | whose road a number runs on — the autonomous system, the prefix, the registry |
| `danglingprobe <name>` | a CNAME that points at a ghost — the takeover risk, graded and never touched |
| `modbusprobe <host>[:port]` | the PLC's device identification, read aloud — the one Modbus read this bench allows |
| `s7probe <host>[:port]` | the Siemens nameplate over RFC 1006 — module, component, firmware, protection level |
| `iec61850probe <host>[:port]` | the substation door over RFC 1006 — where an MMS nameplate would be read |
| `enipprobe <host>[:port]` | List Identity — vendor, device type, product, revision, serial, in the clear |
| `pcccprobe <host>[:port]` | the legacy Allen-Bradley door, knocked once — presence, graded plainly |
| `dnp3probe <host>[:port]` | link status and the outstation's own attribute ledger — read only, never a control |
| `bacnetprobe <host>[:port]` | Who-Is, then the device object's own nameplate — vendor, model, firmware |
| `opcuaprobe <host>[:port]` | HEL and the endpoint menu — the security policies offered, graded; no session is opened |
| `finsprobe <host>[:port]` | the Omron controller's data and status reads — model, version, run state; never a write |
| `melsecprobe <host>[:port]` | the SLMP type-name read — the Mitsubishi module names itself |
| `iec104probe <host>[:port]` | the telecontrol handshake — STARTDT and TESTFR only; nothing is interrogated or controlled |
| `knxprobe <host>[:port]` | the building bus describes itself — device, families, the name it answers to |
| `foxprobe <host>[:port]` | the Niagara hello, parsed — version and host disclosure graded |
| `hartprobe <host>[:port]` | a HART-IP session and universal command 0 — maker, device, revision |
| `srtpprobe <host>[:port]` | the GE door, knocked once — presence, graded plainly |
| `adsprobe <host>[:port]` | the Beckhoff device info and state reads — name, version, run state |
| `dlmsprobe <host>[:port]` | the meter association posture — what an unauthenticated knock is offered is the grade |
| `moxaprobe <host>[:port]` | the serial gateway's door, knocked once by UDP — presence, graded plainly |
| `pmuprobe <host>[:port]` | the PMU's own configuration frame — the only frame this bench ever asks it for |
| `plcensus <host>` | one light knock on every plant door — the board of what this host runs |
| `selprobe <host>[:port]` | the SEL relay's ID report — the one page it shows the world |
| `rocprobe <host>[:port]` | the flow computer's system-parameters read, checksum verified before a byte is believed |
| `mtconnectprobe <host>[:port]` | the machine-tool agent's published census — devices, makers, serials |
| `focasprobe <host>[:port]` | the Fanuc door, knocked once — presence, graded plainly |
| `codesysprobe <host>` | the runtime's two doors, knocked once each — presence, graded plainly |
| `umasprobe <host>[:port]` | Schneider's UMAS nameplate subfunctions only — never reservation, never start or stop |
| `happrobe <host>[:port]` | the DirectLOGIC door, knocked once by UDP — presence, graded plainly |
| `pcomprobe <host>[:port]` | the Unitronics door, knocked once — presence, graded plainly |
| `pcworxprobe <host>[:port]` | the Phoenix door, knocked once — presence, graded plainly |
| `lonprobe <host>[:port]` | the LonWorks/IP door, knocked once by UDP — presence, graded plainly |
| `mbusprobe <host>[:port]` | one meter woken at address 0 — its nameplate, and none of its readings |
| `secsprobe <host>[:port]` | the HSMS are-you-there — Select, S1F1, S1F13; the equipment names itself |
| `ffprobe <host>[:port]` | the Fieldbus HSE door, knocked once by UDP — presence, graded plainly |
| `ptpprobe <host>[:port]` | one management GET — the clock describes itself; its time is never touched |
| `sep2probe <host>[:port]` | the smart-grid capability document and the end-device nameplates behind it |
| `sunspecprobe <host>[:port]` | the SunSpec nameplate block — the one bounded register read in the whole wave |
| `lantronixprobe <host>[:port]` | the gateway's discovery answer — MAC, hardware type, firmware, in the clear |
| `c1222probe <host>[:port]` | the C12.22 meter door, knocked once — presence, graded plainly |
| `cspprobe <host>[:port]` | a libcsp spacecraft bus — CMP IDENT, uptime and a ping; the reboot service is never touched |
| `ccsdsprobe <host>[:port]` | a CCSDS stream census — listen-only: APIDs, telemetry against telecommand, sequence gaps |
| `aprsprobe [host][:port]` | the APRS-IS feed through the read-only login — heard, never spoken into |
| `kissprobe <host>[:port]` | a KISS TNC heard only — AX.25 frames counted, nothing transmitted, no parameter writes |
| `agwprobe <host>[:port]` | an AGW packet engine — version, ports and the monitor feed; no transmit frame is ever built |
| `rotprobe <host>[:port]` | a rotctld rotator's pointing and range — read only; set_pos is never sent |
| `rigprobe <host>[:port]` | a rigctld radio's tuning and mode — read only; nothing set, nothing keyed |
| `gpsdprobe <host>[:port]` | gpsd's version and receivers — no ?WATCH, so no fix is ever streamed or printed |
| `nmeaprobe <host>[:port]` | an NMEA stream census — sentence shapes, checksums and the sky view; positions never printed |
| `ubxprobe <host>[:port]` | a u-blox receiver's MON-VER nameplate — one poll; the CFG class is never sent |
| `ntripprobe <host>[:port]` | an NTRIP caster's sourcetable — the mountpoint menu, read; no stream is joined |
| `comtechprobe <host>[:port]` | a Comtech modem's firmware and serial, asked with query packets only — '=' is never sent |
| `bucprobe <host>[:port]` | a BUC amplifier's web nameplate — its binary M&C is never guessed at or spoken |
| `iridiumprobe <host>[:port]` | an Iridium modem's AT identification — maker, model, firmware, IMEI; nothing originated |
| `starlinkprobe [host]` | the dish's local doors, censused — the gRPC API door named, its framing honestly not reproduced |
| `satipprobe <host>[:port]` | a SAT>IP tuner census by RTSP — OPTIONS and DESCRIBE; SETUP and PLAY are never sent |
| `yamcsprobe <host>[:port]` | a YAMCS server's mission instances, listed — operations data read, never operated |
| `satintel [norad|name]` | Celestrak's ledger — one satellite's identity and orbit, its element-set checksum verified |
| `satnogsprobe [station]` | the SatNOGS network's ground stations — who listens to the sky, and whether they are up |
| `satcensus [host]` | every satellite door at one address, knocked once each — and the RF limit stated plainly |
| `signalprobe <host>` | an NTCIP signal controller's nameplate by SNMP GET — identification only; no phase or timing object exists in this verb |
| `ascprobe <host>` | an ASC-class controller's nameplate plus its 1202 sizing — counts, never states |
| `dmsprobe <host>` | a dynamic message sign's 1203 identification branch — the sign's makeup, never its message |
| `rwisprobe <host>` | a road-weather station's 1204 identification — its category and the site it names |
| `rsuprobe <host>` | a roadside unit's network nameplate — the 1218 radio side is never touched or transmitted to |
| `spatprobe <url>` | a published SPaT feed read as published — intersections and phase states from the agency's own snapshot |
| `flockcensus <place>` | the ALPR census from the public map (OpenStreetMap/DeFlock) — the map only; no camera, plate or hotlist is touched |
| `dotprobe <url>` | a state DOT's published camera ledger, censused as the agency itself lists it |
| `onvifprobe <host>[:port]` | an ONVIF camera's nameplate — maker, model, firmware, serial; the identification reads only |
| `camdeep <host>[:port]` | the vendor nameplate doors — Axis VAPIX, Hikvision ISAPI, Dahua system info; unauthenticated disclosure graded |
| `ptzprobe <host>[:port]` | an ONVIF PTZ node census — proves a steerable camera; a move command does not exist in this verb |
| `ridprobe` | six seconds of listening for drone Remote ID (ASTM F3411) — IDs as broadcast; listen-only |
| `streetlightprobe <host>[:port]` | a streetlight gateway's web door — TALQ itself is authenticated and vendor-run, and the verb says so |
| `sirenprobe <host>` | a warning siren controller's management doors and web nameplate — identification only; activation is never framed |
| `transitprobe <url>` | a published GTFS-realtime feed — the agency's vehicle census off the wire format |
| `gaugeprobe <place>` | USGS stream and flood gauges around a place — the public water ledger, latest levels as published |
| `airprobe <place>` | OpenAQ air stations around a place — the ledger now demands a key, and the verb reports exactly that |
| `gbfsprobe <url>` | a bike-share system's published GBFS feeds — stations, bikes and docks as published |
| `towerprobe <place>` | masts and towers around a place from the public map — the FCC registry named, the map read |
| `streetcensus [host]` | one light knock per street door at an address — and the limits (clouds, plates, RF) stated plainly |
| `ssdpdeep` | the SSDP census, deepened — every device, its description document read whole, and the service ledger |
| `mdnsdeep` | the DNS-SD enumeration census — every service type the wire announces, its instances and their papers |
| `dhcpprobe` | one DHCP DISCOVER, read-only — who offers addresses here, and whether more than one authority answers |
| `wsdprobe` | the WS-Discovery Probe census — the cameras and printers that introduce themselves |
| `ntpprobe [server]` | the time plane read — stratum, offset and root doubt for a server and your router |
| `smallsvc <host>` | the retired small services of 1983 — echo, discard, daytime, qotd, chargen; a chargen that answers is a finding |
| `v6probe` | the house's IPv6 posture — this console's own addresses and the resolver's two-stack answers |
| `bgprobe <AS\|prefix>` | the BGP ledger — who originates a prefix, and the paths the collectors see |
| `ripeprobe <host\|AS>` | RIPEstat's papers — the containing prefix, its holder and its blocklist posture |
| `torprobe <host>` | Onionoo's ledger — whether an address is a published Tor relay, and its exit policy as published |
| `rblprobe <host>` | the DNS blocklist census — five public ledgers, per-list verdicts, sanity-checked |
| `geoprobe <host>` | geolocation by consensus — the keyless ledgers compared, agreement graded, inference labelled |
| `cveprobe <product\|CVE>` | NVD's ledger — a product's published CVE census by severity, or one CVE read whole |
| `kevprobe <CVE\|product>` | CISA's KEV catalog — confirmed exploited in the wild; presence outranks any score |
| `ghprobe <user\|org>` | a GitHub account's published footprint — repos, languages and stars, as the account itself published them |
| `gleifprobe <name\|LEI>` | the GLEIF legal-entity ledger — who a company is, legally, and its LEI |
| `urlscanprobe <domain\|IP>` | urlscan's published scans touching a name — verdicts included, as its engines judged them |
| `passivedns <domain>` | the names a domain has worn — the keyless passive-DNS ledgers, limits stated |
| `macprobe <mac>` | the maker in a MAC address — the house OUI table and the address's own bits |
| `wirecensus [host]` | the board — SSDP, mDNS, WS-Discovery, DHCP and one host's NetBIOS papers in one pass, limits stated |
| `keyprobe <file\|string>` | what key is this — family, size, strength and its fingerprints; private keys are named, never decoded |
| `hashprobe <file\|digest\|string>` | hash a file, name a digest by its shape, or hash a literal string |
| `entropyprobe <file>` | the shape of a blob's bytes — entropy, chi-square, min-entropy and a runs pass, limits stated |
| `b64deep <string>` | peel an encoded onion — base64, base64url, base32, hex and base58, layer by labelled layer |
| `x509probe <file>` | a certificate or bundle read from paper — names, validity, key and usages, graded |
| `pgpprobe <file>` | walk an OpenPGP file packet by packet — keys, fingerprints, user IDs, signatures |
| `sshkeydeep <host\|file>` | a host's offered algorithms and presented SSH key, or every key in a file — read, never pinned |
| `tlscensus <host>` | which TLS versions answer, which cipher families the door still shares, and the papers chained in |
| `cipherprobe <code\|name>` | a cipher suite from its IANA code or either common name — components and posture |
| `randprobe [file] [bytes]` | would-be random bytes under the yardstick — entropy, chi-square and a runs pass |
| `kdfprobe <alg> <word> <salt> <iters>` | derive a key with PBKDF2 where you can watch it — the word is used in place and never printed |
| `aesprobe mode=… key=… data=…` | raw AES by hand — ECB, CBC and CTR with your own key and IV; no MAC rides with it |
| `xorprobe <file> [keylen=n]` | repeating-key XOR read statistically — key length by coincidence, key bytes by letter shape; an estimate |
| `rsaprobe <key\|hex> [second]` | an RSA modulus's cheap shapes — small factors, Fermat-close factors, a factor shared with a second modulus |
| `eccprobe <file\|point>` | an EC point proven on its curve, exactly — compressed points expanded by the root |
| `enccensus <file>` | whose papers are these — NJCF, OpenSSL-salted, age, LUKS, OpenPGP, ZIP and the archive magics |
| `sigprobe <key> <msg> <sig>` | verify a signature over a file — exactly VALID or NOT VALID |
| `totpprobe <seed>` | the current time-based code for your own seed, with its neighbours — the seed is never printed |
| `passprobe <word>` | a passphrase graded on shape alone — classes, a charset estimate, the common lists; the word is never printed |
| `lockcensus <host>` | one host's locks on one board — TLS, the papers, and the SSH key with its pin state |
| `shieldcensus <host>` | one host, the whole shield board — doors, the versions it presents, SSH and SMB grades, its papers, its clock, and the federal ledger |
| `mgmtprobe <host>` | the management plane door by door — shells, panels, VNC, RDP, AMT, and the r-services |
| `anonprobe <host>` | the four anonymous knocks, exactly once each — SNMP 'public', FTP anonymous, an unnamed MQTT guest, an LDAP bind with no name |
| `certwatch <host>` | every implicit-TLS door's certificate on one host, by days left to live |
| `smbposture <host>` | the file door graded: dialect, signing, encryption, and whether SMB1 still sits at the table |
| `sshposture <host>` | the shell door graded: algorithm lists, the auth methods, and the host key against the house pin |
| `snmposture <host>` | the NSA's six mitigations read as the owner of the gear — the house audit, owned, plus what the agent volunteers |
| `backupprobe <host>` | the doors your backups ride — AFP, SMB, rsync's module list, the Time Capsule's own door |
| `upnpgrade [gateway]` | your gateway's UPnP forwarding ledger — every standing port mapping, read as its owner |
| `dnsposture <resolver>` | your resolver graded: recursion, DNSSEC validation, and whether it confesses its version |
| `mailposture <domain>` | a domain's mail defences rung by rung — SPF, DMARC, MTA-STS — graded at their weakest |
| `patchprobe <host>` | the versions a host presents, against the bench's bounded end-of-life table — a claim graded, never a bill of health |
| `kevcheck <host>` | the products a host presents, against the CISA KEV ledger — confirmed exploitation, not scores |
| `iotposture <host>` | the small-machine doors graded: the broker, CoAP's map, the stream's own description |
| `guestprobe [gateway]` | the house as a guest meets it — the gateway's doors, its resolver, its announcers; inference, labelled |
| `timeprobe <host>` | a clock graded against true time — offset, stratum, and what the drift would cost |
| `v6posture <host>` | the second stack's doors: what answers on IPv6 that IPv4 keeps shut |
| `headerposture <url\|host>` | one of your servers' headers, deep-read, with the owner's roll-up of the five defensive headers |
| `cookieposture <host[:port]>` | the cookies your root page hands out, graded flag by flag: Secure, HttpOnly, SameSite |
| `dirposture <host[:port]>` | open directory listings, followed only where the page itself holds the door open — nothing guessed |
| `metadataprobe` | the cloud's link-local door, knocked on once; the status line read, the body discarded unread |
| `printposture <host>` | a printer's whole posture: the house read, plus the raw 9100 door and the old LPD |
| `nasposture <host>` | a file box's whole face on one board — shares, NFS, AFP, WebDAV, and its consoles |
| `cameraposture <host[:port]>` | a camera's papers and its stream: the ONVIF nameplate as claim, the vendor doors, RTSP's answer |
| `watchprobe [save] <host>` | the shield board against the last baseline on file — what changed on your wire while you weren't looking |
| `filecensus <file>` | the identity board for a file you have never seen — what its bytes say, what its name claims, its digests and texture |
| `magicprobe <file>` | sixteen bytes and a verdict — what the head of the file says, and whether its name agrees |
| `stringsdeep <file>` | the strings census — runs counted and sampled, URL- and domain-shaped strings printed as strings |
| `exifprobe <file>` | the papers a picture carries — camera, software, timestamps, and a GPS claim if it makes one |
| `pdfprobe <file>` | a document read as claims — objects, pages counted against the page tree's claim, scripts and carried files |
| `zipprobe <file>` | the archive ledger — entries, methods, seals and path escapes; listing only, never unpacked |
| `machoprobe <file>` | a Mach-O read — slices, libraries claimed, encryption papers, runpaths, build version |
| `elfprobe <file>` | an ELF read — PIE, interpreter, stack and RELRO posture, the needed ledger |
| `peprobe <file>` | the Windows papers — hardening flags graded, sections, imports, bytes past the last section |
| `imgdeep <file>` | the image censuses — JPEG markers, PNG chunks and CRCs, GIF frames, the WebP ledger, bytes past the end |
| `audiofile <file>` | the songs' papers — WAV chunks, FLAC blocks, the MP3 tag and frame walk, Ogg tenants |
| `sqliteprobe <file>` | a database's ledger — pages, the freelist, schema objects; rows never dumped |
| `plistprobe <file>` | plists, entitlements and provisioning profiles — powers asked for, printed as asks |
| `scriptprobe <file>` | a script read as text and never run — dialect by shape, its strings, its reach-out call names counted |
| `logprobe <file>` | a log read as testimony — shape guess, the span the lines claim, error and status tallies |
| `dataprobe <file>` | the shape of data — JSON key and kind censuses, delimited columns inferred; values not dumped |
| `fontprobe <file>` | a font's papers — the table directory, the name it claims, glyph and em counts |
| `certfile <file>` | a bundle's ledger — every PEM block in the file's own order, the chain graded; deep reads stay with x509probe |
| `dupprobe <dir>` | a directory's duplicates by size and then SHA-256 — bytes paid for twice, priced |
| `fileboard <dir>` | a directory read at once — kinds, totals, the largest tenants, and every mismatch in the room |
| `methods <url>` | OPTIONS, and the TRACE question |
| `dirb <url>` | the path dictionary |
| `wol <mac>` | wake a sleeping machine |

## files — the console's own tree (26)

| Command | What it does |
| --- | --- |
| `pwd · cd <dir>` | where you stand · move |
| `ls [-l] [path]` | list a directory |
| `tree [path]` | the whole branch, drawn |
| `cat <file>` | read a file (or a pipe) |
| `echo [-n] <words>` | say it back |
| `mkdir · touch <name>` | make a directory · a file |
| `cp · mv <a> <b>` | copy · move |
| `rm [-r] <path>` | remove |
| `head · tail [-n N]` | the first · last lines |
| `wc [file]` | lines, words, chars |
| `grep [-i] <pat> [file]` | lines that match |
| `find [path] [-name x]` | every file below |
| `stat <path>` | what a thing is |
| `sort [-rnuf] · uniq [-cdu]` | order the lines · drop repeated neighbours |
| `cut -d X -f 1,3 · tr A-Z a-z` | take fields apart · translate letters |
| `sed [-n] [-i] 's/a/b/g'` | the stream editor — addresses, d, p, the honest subset |
| `rev · tac · nl` | letters backwards · lines backwards · lines numbered |
| `diff <a> <b>` | what changed, hunk by hunk |
| `tee [-a] <file>` | the stream, copied to a file as it passes |
| `xargs [-n N] [-I {}] <cmd>` | run a command on what arrives |
| `file · strings · du [-h]` | what a thing is · its readable runs · its weight |
| `xxd · base64 · md5sum · sha256sum` | look at the bytes · carry them safely · their sums |
| `printf <fmt> [args] · seq [a [s]] b · yes` | say it precisely · count · say it forever (a thousand times) |
| `cal [month [year]]` | the month, drawn |
| `figlet [-f slim] <words>` | big letters — banner is the wire tool of the same name |
| `sleep <n>` | the room waits (300 seconds at most) |

## editors (4)

| Command | What it does |
| --- | --- |
| `vim [file]` | the modal church — :help inside |
| `emacs [file]` | the chord church — M-x help inside |
| `nano [file]` | the plain church — ^G lists its keys |
| `edit [file]` | whichever $EDITOR names |

## code — the engine room (23)

| Command | What it does |
| --- | --- |
| `js <code>` | JavaScript, compiled + run (node works too) |
| `linuxbox <applet>` | a real linux userspace in wasm: ls cat echo pwd wc head tail cp mv rm mkdir touch env uname grep sleep |
| `run <file.wasm>` | compiled webassembly, run as a kernel process — its syscalls are mediated, its memory is its own |
| `run <file.js>` | run a program from the files |
| `run <file.sh> · sh` | run a shell script |
| `python3 <file.py>` | the house's small python — python3 alone lists its edges |
| `run <file.py>` | run a python program |
| `NAME=value · export` | shell variables — $NAME ${NAME} $? |
| `a \| b` | pipe one command through another |
| `cmd > file · >>` | write · append output to a file |
| `$(cmd)` | run it, use what it said |
| `a ; b · a && b` | then · then-if-it-worked |
| `cmd < file` | a file becomes the input |
| `cat <<EOF … EOF` | a here-doc — the lines between are the input; <<'EOF' keeps them literal |
| `$((x + 1))` | arithmetic in place — names, the full operator ladder, ?: too |
| `name() { …; }` | a function — call it by name; $1…$9, $#, $@ inside, local keeps its variables its own, return N leaves early |
| `for x in a b *.txt; do …; done` | the loop, spelled out — globs open here |
| `while test …; do …; done` | until runs the other way — the condition is any command, judged by its status |
| `if …; then …; elif …; else …; fi` | the fork in the road |
| `case $x in a\|b) …;; *) …;; esac` | pattern by pattern — * ? [set] speak glob |
| `test <expr> · [ <expr> ]` | the judge: -e -f -d -s -z -n, = !=, -eq -ne -lt -le -gt -ge, ! -a -o |
| `require('./mod') — js` | javascript modules from the files beside the script, or a package name from /packages — circular loads come back partial, like node's |
| `setTimeout — js` | timers are the kernel's clock lent out: a run ends when its timers drain, its limit arrives, or the kernel speaks |

## packages (8)

| Command | What it does |
| --- | --- |
| `pkg list` | installed + the bundled shelf |
| `pkg install <name>` | install a bundled package |
| `pkg install <url>` | install a package from the wire |
| `pkg remove <name>` | uninstall |
| `pkg commands` | the commands packages gave the shell |
| `pkg install grok · grok login · grok <words>` | ask xAI's grok from here — the house's own client (not the Rust CLI): SuperGrok sign-in via X, then questions with file + shell tools |
| `pkg install git · git clone <url> · git commit · git push` | real git in the console (isomorphic-git over the house's files and wire): clone a repo here, edit it with the house editors, commit it, push it back |
| `pkg install gh · gh auth login <token> · gh repo view` | github from here — the house's own client over the REST api: sign-in, repos, issues, pull requests |

## graphics (5)

| Command | What it does |
| --- | --- |
| `gfx demo` | the engine draws the house card |
| `gfx mandelbrot · plasma · stars` | computed pictures, filed as PNG |
| `gfx show <png>` | put a picture in the terminal |
| `view <file>` | pictures shown, text read |
| `wallpaper [stars\|plasma\|mandelbrot]` | the room's own wallpaper — generated, changeable |

## the room (14)

| Command | What it does |
| --- | --- |
| `history` | what you have run |
| `watch on\|off\|status` | the standing passives — browse, MNDP ear, gateway heartbeat |
| `sentinel` | the Sentinel's alert ledger — what the signs judged |
| `sentinel clear` | clear the alert ledger and its baselines |
| `lockdown` | go dark: EMCON Alpha, assault and watch stood down, all of it journaled |
| `lockdown lift` | lift the lockdown and restore the condition that stood before |
| `quarantine <ip> [via <gear>]` | remove a device through your own credentialed gear — its port shut, read back |
| `quarantine lift <ip> [via <gear>]` | open the port again |
| `date` | when it is |
| `which <cmd>` | where a command lives |
| `betafisch [file]` | betafisch — the packet dissector: open a capture, read every frame |
| `driftnet [file]` | driftnet — the pictures in a capture, lifted off the wire and pinned to a wall |
| `ver` | what this is |
| `clear` | wipe this screen |
