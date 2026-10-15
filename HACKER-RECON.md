# nightjar-hack recon

`nightjar listen`s. This adds the words. It lands **in the iOS app first**
— a Recon tab beside Send and Serve — and the same protocol library is
mirrored into the Python CLI so the two halves speak identically.

## iOS: the Recon tab

- **Knock.** Type a host, leave the port field blank, press Knock. Every
  port the library can name is knocked with the protocol that port
  expects, and the banner is filed. A **star** means the reply carried
  the protocol's own tell — the port answered *as that service*, not
  merely opened. Tap any hit to load it into Send.
- **Connect.** A console, not a terminal: open the socket, send lines,
  watch what comes back. Binary replies print as hexdumps.
- **Fuzz.** Seven mutators, a reproducible seed, a reply digest per
  round. `DEAD` means the connection was refused or reset.
- **Library.** 105 protocol first words over 78 TCP and 14 UDP ports.
  One button adds every probe to the payload library, so all of them
  become sendable by hand from the Send tab too.

Nothing here touches the Listen tab: the ear still never connects.

## What it speaks

Name resolution (DNS A/AAAA/MX/TXT/ANY, CHAOS version.bind, mDNS,
LLMNR, NBNS), time and discovery (NTP, SNMP sysDescr, SSDP, DHCP,
TFTP, STUN, syslog, WireGuard), data stores (Redis, memcached, Mongo,
Cassandra, CouchDB, Elasticsearch, ZooKeeper, etcd, Consul, Vault),
messaging (MQTT incl. a retained plant, AMQP, STOMP, RabbitMQ), mail
and real-time (SMTP, POP3, IMAP and their TLS forms, IRC, SIP, RTSP),
databases (Postgres SSLRequest, MySQL, MSSQL PRELOGIN), file and
directory (SMB1/SMB2, portmapper, rsync, FTP), remote access (SSH,
telnet, VNC, RDP, X11, SOCKS4/5, ADB, LDAP), web and orchestration
(HTTP, GraphQL introspection, open-proxy test, Docker, Kubernetes,
kubelet, Jenkins, Prometheus, Grafana, Kibana, Solr, InfluxDB, MinIO,
Neo4j, Gitea, GitLab) and small talk (echo, daytime, chargen, whois,
finger, gopher, Gemini).

Every length, offset and BER/BSON/TLV envelope is computed, not
remembered. Server-first protocols (ssh, mysql, echo) carry an empty
probe: the knocker just listens. Probes that need TLS wrap the socket
themselves.

## Python: the same library

    nightjar send --presets                        # the library
    nightjar send --preset redis-ping 10.0.0.7     # the port is filled in
    nightjar send --preset snmp-sysdescr --read udp://10.0.0.7:161
    nightjar send tcp://10.0.0.9:80 --lines words.txt --expect 200 --jitter 0.2
    nightjar knock 192.168.1.1 --ports 1-1024 --udp
    nightjar connect 10.0.0.9:23
    nightjar fuzz udp://10.0.0.9:53 --count 5000 --seed 1 --stop-on-dead

## Honest limits

- iOS gives an app no raw sockets: knock is a connect scan, and there
  is no SYN, no ARP, no packet capture from the app itself.
- UDP `open|filtered` means no reply, which is the correct answer.
- The `Host:` header on HTTP probes is `localhost`; the target's own
  name is not guessed. Use Connect or a raw payload when the vhost
  matters.
- Probes run while the app is on screen, like every other listener.
