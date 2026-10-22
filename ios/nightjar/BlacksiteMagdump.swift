import Foundation
import Network
import Security

// BlacksiteMagdump — MAGDUMP, the automated
// targeting program (Chase's order,
// 2026-10-21). A program in EAZY's class,
// not a bench wave: ONE target the operator
// named — an address or a name — and the
// finished bench emptied at it in stages:
// the doors, the web battery, TLS and the
// keys it shows, the name and mail ledgers,
// the wire's public ledgers, and the
// shield's single-host singles, all
// appending into one graded board the
// console files to Deliveries.
//
// Nothing here is new machinery. Every
// stage rides an engine the waves already
// shipped, called exactly the way the
// console calls it by hand — one knock,
// read, grade, the sanctioned anonymous
// checks exactly as their waves defined
// them. A stage that cannot run prints
// its limit and the battery continues;
// the stop word halts the chain between
// stages like it halts EAZY's. If a stage
// would need machinery the waves did not
// ship, the stage does not exist.

extension BlacksiteBench {

    // MARK: plumbing

    /// MAGDUMP speaks through the house
    /// emit; a kindless call reads .out.
    private static func magSay(
        _ emit: BlacksiteEmit,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    /// The magazine's door list: every door
    /// any stage of the battery knows how to
    /// read. 53 is knocked and noted — the
    /// name stage reads DNS as a ledger, not
    /// as this host's door.
    private static let magDoors = [
        21, 22, 25, 53, 80, 111, 389, 443,
        445, 554, 631, 1433, 1883, 2049,
        2181, 2375, 2379, 3306, 3389, 5000,
        5060, 5432, 5672, 5900, 5984, 6379,
        6443, 8080, 8200, 8443, 8500, 8983,
        9092, 9100, 9200, 10250, 11211,
        15672, 27017,
    ]

    /// The doors no stage reads a probe
    /// against — noted on the board when
    /// they answer, never dressed up.
    private static let magUnprobed = [53]

    /// A nonblocking connect with a poll
    /// deadline, EAZY's doorOpen in shape:
    /// a filtered door answers with
    /// silence, and silence must not
    /// stall the battery.
    private static func magDoorOpen(
        ip: String, port: Int,
        deadline: Double = 0.9) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM,
                        IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL,
                  flags | O_NONBLOCK)
        var dest = BlacksiteNet.sockaddrIn(
            ip: ip,
            port: UInt16(clamping: port))
        let rc = withUnsafeMutablePointer(
            to: &dest) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1) { sa in
                connect(fd, sa, socklen_t(
                    MemoryLayout<sockaddr_in>
                        .size))
            }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else {
            return false
        }
        var pfd = pollfd(fd: fd,
                         events: Int16(POLLOUT),
                         revents: 0)
        guard poll(&pfd, 1,
                   Int32(deadline * 1000)) > 0
        else { return false }
        var err: Int32 = 0
        var len = socklen_t(
            MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET,
                         SO_ERROR, &err,
                         &len) == 0
        else { return false }
        return err == 0
    }

    private static func magDoorScan(
        ip: String) -> [Int] {
        var open: [Int] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 24)
        for port in magDoors {
            group.enter()
            DispatchQueue.global().async {
                sem.wait()
                if magDoorOpen(ip: ip,
                               port: port) {
                    lock.lock()
                    open.append(port)
                    lock.unlock()
                }
                sem.signal()
                group.leave()
            }
        }
        group.wait()
        return open.sorted()
    }

    /// The stage chain: steps run one at a
    /// time, in order; the operator's stop
    /// word is honored between steps and
    /// says so on the board.
    private static func magChain(
        _ steps: [(@escaping BlacksiteEmit,
                   @escaping () -> Void)
                    -> Void],
        _ i: Int,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if i >= steps.count {
            done()
            return
        }
        if stopped() {
            emit(L("magdump: stopped by the operator — the board stands as it was read."),
                 .err)
            done()
            return
        }
        steps[i](emit) {
            magChain(steps, i + 1,
                     stopped: stopped,
                     emit: emit, done: done)
        }
    }

    /// The name the resolver knows an
    /// address by, if it knows one — the
    /// host command's own road (NI_NAMEREQD
    /// and the canonical name), borrowed
    /// so the ledgers can be read under it.
    private static func magPTRName(
        _ ip: String) -> String? {
        var hints = addrinfo(
            ai_flags: NI_NAMEREQD,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0, ai_addrlen: 0,
            ai_canonname: nil, ai_addr: nil,
            ai_next: nil)
        var result:
            UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(ip, nil, &hints,
                          &result) == 0,
              let first = result
        else { return nil }
        defer { freeaddrinfo(result) }
        guard let canon = first.pointee
            .ai_canonname else { return nil }
        let found = String(cString: canon)
        return found.isEmpty || found == ip
            ? nil : found
    }

    // MARK: the battery

    /// MAGDUMP itself: the stages composed
    /// from the shipped engines, in the
    /// brief's order, against one target.
    /// `host` is the name or address as the
    /// operator gave it (what URLs and
    /// banners are read under), `ip` the
    /// address the doors knock, `name` the
    /// given name when one was given.
    static func magdumpRun(
        host: String, ip: String,
        name: String?,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            if stopped() {
                emit(L("magdump: stopped by the operator — the board stands as it was read."),
                     .err)
                done()
                return
            }
            magSay(emit,
                   String(format: L("magdump: target lock — %@ (%@). The whole bench, emptied in stages; the board files when the magazine is empty."),
                          host, ip),
                   .sys)
            let open = magDoorScan(ip: ip)
            let openSet = Set(open)
            let domain = name
                ?? magPTRName(ip)
            let webPorts = [80, 443, 8080, 8443]
                .filter { openSet.contains($0) }
            func webURL(_ port: Int)
                -> String {
                let scheme = port == 443
                    || port == 8443
                    ? "https" : "http"
                if (scheme == "http"
                        && port == 80)
                    || (scheme == "https"
                        && port == 443) {
                    return "\(scheme)://\(host)/"
                }
                return "\(scheme)://\(host):\(port)/"
            }
            let primaryURL = webPorts.first
                .map { webURL($0) }

            typealias Step =
                (@escaping BlacksiteEmit,
                 @escaping () -> Void) -> Void
            var steps: [Step] = []
            func header(_ text: String) {
                steps.append { e, d in
                    magSay(e, text, .sys)
                    d()
                }
            }
            func line(_ text: String) {
                steps.append { e, d in
                    magSay(e, text)
                    d()
                }
            }
            func two(_ verb: String,
                     _ target: String) {
                steps.append { e, d in
                    BlacksiteBench.benchTwo(
                        verb, target,
                        emit: e, done: d)
                }
            }
            func doors(_ verb: String,
                       _ target: String) {
                steps.append { e, d in
                    BlacksiteBench.benchDoors(
                        verb, target,
                        emit: e, done: d)
                }
            }
            func web(_ verb: String,
                     _ url: String) {
                steps.append { e, d in
                    BlacksiteBench.benchWeb(
                        verb, url,
                        emit: e, done: d)
                }
            }
            func names(_ verb: String,
                       _ target: String) {
                steps.append { e, d in
                    BlacksiteBench.benchNames(
                        verb, target,
                        emit: e, done: d)
                }
            }
            func wire(_ verb: String,
                      _ target: String) {
                steps.append { e, d in
                    BlacksiteBench.benchWire(
                        verb, target,
                        emit: e, done: d)
                }
            }
            func shield(_ verb: String,
                        _ arg: String) {
                steps.append { e, d in
                    BlacksiteBench.benchShield(
                        name: verb, arg: arg,
                        emit: e, done: d)
                }
            }
            func locks(_ verb: String,
                       _ arg: String) {
                steps.append { e, d in
                    BlacksiteBench.benchLocks(
                        name: verb, arg: arg,
                        emit: e, done: d)
                }
            }

            // Stage one — the doors (wave
            // two's cores and the wire
            // bench's per-door probes).
            header(L("magdump: stage one — the doors"))
            if open.isEmpty {
                line(L("magdump: no doors answered — the lock holds an address that keeps its doors shut; the ledgers below still speak."))
            } else {
                line(String(format: L("magdump: doors open: %@"),
                            open.map {
                                String($0)
                            }.joined(
                                separator: ", ")))
                let noted = open.filter {
                    magUnprobed.contains($0)
                }
                if !noted.isEmpty {
                    line(String(format: L("magdump: noted without a probe of their own in the magazine: %@"),
                                noted.map {
                                    String($0)
                                }.joined(
                                    separator: ", ")))
                }
                for port in open {
                    let door = "\(host):\(port)"
                    switch port {
                    case 21:
                        two("ftpprobe", door)
                    case 25:
                        two("smtpprobe", door)
                    case 111:
                        doors("rpcprobe", door)
                    case 389:
                        two("ldapprobe", door)
                    case 445:
                        doors("smbprobe", door)
                    case 554:
                        doors("rtspprobe", door)
                    case 631, 9100:
                        doors("printerprobe", door)
                    case 1433:
                        doors("mssqlprobe", door)
                    case 1883:
                        steps.append { e, d in
                            BlacksiteBench
                                .mqttprobe(
                                    target: door,
                                    emit: e,
                                    done: d)
                        }
                    case 2049:
                        doors("nfsprobe", door)
                    case 2181:
                        doors("zkprobe", door)
                    case 2375:
                        two("dockerprobe", door)
                    case 2379:
                        doors("etcdprobe", door)
                    case 3306:
                        doors("mysqlprobe", door)
                    case 3389:
                        two("rdpprobe", door)
                    case 5000:
                        doors("registryprobe", door)
                    case 5060:
                        doors("sipprobe", door)
                    case 5432:
                        doors("pgprobe", door)
                    case 5672, 15672:
                        doors("rabbitprobe", door)
                    case 5900:
                        two("vncprobe", door)
                    case 5984:
                        doors("couchprobe", door)
                    case 6379:
                        two("redisprobe", door)
                    case 6443, 10250:
                        doors("k8sprobe", door)
                    case 8200:
                        doors("vaultprobe", door)
                    case 8500:
                        doors("consulprobe", door)
                    case 8983:
                        doors("solrprobe", door)
                    case 9092:
                        doors("kafkaprobe", door)
                    case 9200:
                        doors("elasticprobe", door)
                    case 11211:
                        doors("memcacheprobe", door)
                    case 27017:
                        doors("mongoprobe", door)
                    default:
                        break
                    }
                }
            }

            // Stage two — the web battery
            // (wave one's deep reads, per
            // web door that answered).
            header(L("magdump: stage two — the web battery"))
            if webPorts.isEmpty {
                line(L("magdump: no web door answered — the web battery stands down."))
            } else {
                let webBattery = [
                    "headersdeep", "wafdetect",
                    "techstack", "faviconhash",
                    "httpversion", "cookieaudit",
                    "cacheprobe", "compressprobe",
                    "methoddeep", "robotsdeep",
                    "redirectchain", "corsdeep",
                    "swaggerprobe", "oidcprobe",
                    "graphqldeep", "apicensus",
                    "jsendpoints", "sitemap",
                    "urlextract", "wayback",
                ]
                for port in webPorts {
                    let url = webURL(port)
                    for verb in webBattery {
                        web(verb, url)
                    }
                    if port == 8080 {
                        doors("jenkinsprobe",
                              "\(host):8080")
                    }
                    if port == 80
                        || port == 443 {
                        doors("gitlabprobe",
                              "\(host):\(port)")
                    }
                }
            }

            // Stage three — TLS and the keys
            // it shows (the grade, the
            // papers, the census, the shell
            // door's offered keys).
            header(L("magdump: stage three — tls and the keys it shows"))
            let tlsPorts = [443, 8443]
                .filter { openSet.contains($0) }
            for port in tlsPorts {
                let door = "\(host):\(port)"
                steps.append { e, d in
                    BlacksiteBench.tlsgrade(
                        target: door,
                        emit: e, done: d)
                }
                web("certprobe", webURL(port))
                web("certchain", webURL(port))
                web("ocspprobe", webURL(port))
                locks("tlscensus", door)
            }
            if openSet.contains(22) {
                locks("sshkeydeep", host)
            }
            if tlsPorts.isEmpty
                && !openSet.contains(22) {
                line(L("magdump: no tls door and no shell door answered — no papers to read."))
            }

            // Stage four — names and mail
            // (wave three's ledgers, read
            // under the target's name).
            header(L("magdump: stage four — names and mail"))
            names("reverseprobe", ip)
            names("asnprobe", ip)
            if let domain = domain {
                if name == nil {
                    line(String(format: L("magdump: the address answers to %@ — its ledgers are read under that name."),
                                domain))
                }
                for verb in [
                    "dnsdeep", "dnscensus",
                    "wildcardprobe", "caacheck",
                    "ttlprobe", "soacheck",
                    "nsecprobe", "dnssecgrade",
                    "zonetransfer", "subdomains",
                    "whoisdeep", "rdap",
                    "danglingprobe",
                ] {
                    names(verb, domain)
                }
                for verb in [
                    "mxprobe", "smtpdeep",
                    "smtptls", "spfprobe",
                    "dkimprobe", "dmarcprobe",
                    "mtasts", "tlsrpt", "bimi",
                ] {
                    names(verb, domain)
                }
                doors("starttlscensus", domain)
            } else {
                line(L("magdump: the address carries no name the resolver knows — the name and mail ledgers belong to names; aim magdump at the name to read them."))
            }

            // Stage five — the wire's
            // ledgers (wave seven's public
            // books, read on the address).
            header(L("magdump: stage five — the wire's ledgers"))
            for verb in [
                "geoprobe", "ripeprobe",
                "bgprobe", "torprobe",
                "rblprobe", "passivedns",
            ] {
                wire(verb, ip)
            }
            if let domain = domain {
                wire("passivedns", domain)
            }
            if let primaryURL = primaryURL {
                wire("urlscanprobe", primaryURL)
            }

            // Stage six — the shield's
            // singles (wave nine's posture
            // reads, aimed at this one host).
            header(L("magdump: stage six — the shield's singles"))
            shield("anonprobe", host)
            shield("snmposture", host)
            shield("certwatch", host)
            if openSet.contains(22) {
                shield("sshposture", host)
            }
            if openSet.contains(445) {
                shield("smbposture", host)
            }
            if let primaryURL = primaryURL {
                shield("headerposture",
                       primaryURL)
                shield("dirposture",
                       primaryURL)
            }
            if let plain = webPorts.first(
                where: { $0 == 80
                    || $0 == 8080 }) {
                shield("cookieposture",
                       "\(host):\(plain)")
            }

            magChain(steps, 0,
                     stopped: stopped,
                     emit: emit) {
                done()
            }
        }
    }
}
