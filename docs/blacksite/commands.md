# Blacksite OS — the complete command reference

Every command the console answers to, with the signature it takes and what it does — generated from the same table the console's own `help` command reads, so this page cannot drift from the shipped truth. Inside the console: `help` shows the sections, `help <section>` opens one whole, `help <word>` searches every command.

**226 commands in 9 sections.**

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

## pentest bench (103)

| Command | What it does |
| --- | --- |
| `discover [a.b.c]` | who lives on the /24 — ICMP sweep |
| `portscan <host> [top\|a-b\|all\|list]` | every door, banners too |
| `banner <host> <port>` | make a door introduce itself |
| `subdomains <domain>` | the names under a name |
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
| `upnp` | who runs UPnP on this wire |
| `bonjour` | service announcements, censused |
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
