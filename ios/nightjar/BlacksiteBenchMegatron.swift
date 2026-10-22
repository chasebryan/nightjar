import Foundation
import Security
import CryptoKit
import CoreBluetooth

// MARK: - MEGATRON — the robotics and machinery program
//
// Every Optimus has one. The bench's all-encompassing
// robotics and machinery battery (Chase's orders,
// 2026-10-22): graded fingerprint reads and posture
// batteries for any robot or machine that presents a
// network surface — industrial arms and cobots, mobile
// robots, drones and their ground stations, CNC and
// additive machines, farm and construction machinery,
// building plant — with the Musk fleet as flagship
// prey: Optimus first, then the vehicles, the Boring
// Company drills, the energy gear, the dishes.
//
// THE SPINE, unbent (the ICS/street line, doubled):
// reads and grades ONLY. Never a control, motion,
// drive or actuation command to any robot or machine;
// never a publish to a robot topic; never an ICS write
// or control function code; never a SET of any kind.
// A humanoid robot is a physical-safety system, and
// heavy machinery can hurt people — the battery reads
// nameplates, doors, papers and discovery traffic,
// and grades the roads it finds. It never walks them.
//
// A fingerprint is a CLAIM: identification prints with
// its evidence and a confidence grade, never as proof.
// Unnamed stays unnamed; a sign is not a name.
//
// Verify-or-degrade, per read: the ROS master XML-RPC
// grammar, the rosbridge WebSocket census (RFC 6455),
// the ADB greeting, the RTPS discovery parse and the
// MAVLink heartbeat were each proven in Python against
// constructed spec fixtures before this file existed
// (nightjar-verify/megatron-verify/). What could not
// be verified is degraded in the open: a neighbour's
// MAC is not readable from iOS, so no OUI claim is made
// for wire hosts; the DDS vendor registry's numbers
// could not be verified from a source in hand, so
// vendor bytes print raw rather than named.

extension BlacksiteBench {

    // MARK: dispatch

    static func benchMegatron(
        name: String, arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        switch name {
        case "megatron":
            megaMarquee(
                arg.isEmpty ? nil : arg,
                emit: emit, done: done)
        case "primeprobe":
            megaProbeVerb(
                arg, optimus: true,
                emit: emit, done: done)
        case "botprobe":
            megaProbeVerb(
                arg, optimus: false,
                emit: emit, done: done)
        case "primecensus":
            megaPrimeCensus(
                arg.isEmpty ? nil : arg,
                file: false,
                emit: emit, done: done)
        case "rosprobe":
            megaROSProbe(
                arg, emit: emit, done: done)
        case "fleetprobe":
            megaFleetVerb(
                arg, emit: emit, done: done)
        case "botdoors":
            megaBotDoors(
                arg, emit: emit, done: done)
        case "botble":
            megaBotBLE(emit: emit, done: done)
        case "puppetprobe":
            megaPuppetProbe(
                arg, emit: emit, done: done)
        case "cyberprobe":
            megaCyberProbe(
                arg, emit: emit, done: done)
        case "boreprobe":
            megaBoreProbe(
                arg, emit: emit, done: done)
        case "voltprobe":
            megaVoltProbe(
                arg, emit: emit, done: done)
        default:
            done()
        }
    }

    // MARK: plumbing (mirrors the magdump shapes)

    /// A nonblocking connect with a poll
    /// deadline — a filtered door answers
    /// with silence, and silence must not
    /// stall the battery.
    private static func megaDoorOpen(
        ip: String, port: Int,
        deadline: Double = 0.7) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM,
                        IPPROTO_TCP)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL,
                  flags | O_NONBLOCK)
        var dest = BlacksiteNet.sockaddrIn(
            ip: ip, port: UInt16(clamping: port))
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

    private static func megaDoorScan(
        ip: String, doors: [Int],
        deadline: Double = 0.7) -> [Int] {
        var open: [Int] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 24)
        for port in doors {
            group.enter()
            DispatchQueue.global().async {
                sem.wait()
                if megaDoorOpen(ip: ip,
                                port: port,
                                deadline: deadline) {
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

    /// The step chain: steps run one at a
    /// time, in order, each completing
    /// before the next begins.
    private static func megaChain(
        _ steps: [(@escaping BlacksiteEmit,
                   @escaping () -> Void)
                    -> Void],
        _ i: Int,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if i >= steps.count {
            done()
            return
        }
        steps[i](emit) {
            megaChain(steps, i + 1,
                      emit: emit, done: done)
        }
    }

    /// The name the resolver knows an
    /// address by, if it knows one —
    /// magdump's road, borrowed.
    private static func megaPTRName(
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

    /// Read whatever a fresh door says
    /// first, up to a short window — the
    /// banner grab, read-only.
    private static func megaFirstLine(
        ip: String, port: Int,
        window: Double = 1.2) -> String? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(port),
            timeout: window) else {
            return nil
        }
        defer { close(fd) }
        var buf = [UInt8](
            repeating: 0, count: 1024)
        let got = recv(fd, &buf, buf.count, 0)
        guard got > 0 else { return nil }
        let text = String(
            decoding: Array(buf[0..<got]),
            as: UTF8.self)
        let line = text
            .split(separator: "\n")
            .first.map(String.init) ?? text
        let clean = line
            .trimmingCharacters(
                in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// A web door's nameplate: the Server
    /// header and the page title, read
    /// from the door's own answer.
    private static func megaWebNameplate(
        host: String, port: Int)
        -> (server: String?, title: String?,
            status: Int) {
        let scheme = (port == 443
            || port == 8443) ? "https" : "http"
        var text = "\(scheme)://\(host)"
        if !((scheme == "http" && port == 80)
            || (scheme == "https"
                && port == 443)) {
            text += ":\(port)"
        }
        text += "/"
        guard let url = URL(string: text),
              let got = satFetch(url) else {
            return (nil, nil, 0)
        }
        let title = streetTag(got.body, "title")
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines)
            }
        return (got.headers["server"], title,
                got.status)
    }

    /// One plain-HTTP exchange over a raw
    /// socket (the ROS master's shape):
    /// send the request, read to close or
    /// deadline, split head from body.
    private static func megaHTTPExchange(
        ip: String, port: Int,
        request: [UInt8],
        window: Double = 4.0)
        -> (status: Int, body: [UInt8])? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(port),
            timeout: 2) else {
            return nil
        }
        defer { close(fd) }
        var sent = 0
        var sendOK = true
        while sent < request.count {
            let n = request.withUnsafeBufferPointer {
                buffer in
                send(fd,
                     buffer.baseAddress! + sent,
                     request.count - sent, 0)
            }
            if n <= 0 { sendOK = false; break }
            sent += n
        }
        guard sendOK else { return nil }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 0.5)
        var all: [UInt8] = []
        let deadline = Date()
            .addingTimeInterval(window)
        while Date() < deadline
            && all.count < 1_000_000 {
            var chunk = [UInt8](
                repeating: 0, count: 16384)
            let got = recv(fd, &chunk,
                           chunk.count, 0)
            if got < 0 { continue }
            if got == 0 { break }
            all.append(contentsOf:
                chunk[0..<got])
        }
        guard let split = megaFindCRLFCRLF(all)
        else {
            let headText = String(
                decoding: all, as: UTF8.self)
            let status = megaHTTPStatus(headText)
            return (status, [])
        }
        let headText = String(
            decoding: Array(all[0..<split]),
            as: UTF8.self)
        var body = Array(all[(split + 4)...])
        // Chunked answers are de-chunked;
        // a Content-Length body rides as-is.
        if headText.lowercased().contains(
            "transfer-encoding: chunked") {
            body = megaDechunk(body)
        }
        return (megaHTTPStatus(headText), body)
    }

    private static func megaFindCRLFCRLF(
        _ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0..<(bytes.count - 3) {
            if bytes[i] == 13, bytes[i + 1] == 10,
               bytes[i + 2] == 13,
               bytes[i + 3] == 10 {
                return i
            }
        }
        return nil
    }

    private static func megaHTTPStatus(
        _ head: String) -> Int {
        let first = head
            .split(separator: " ")
        guard first.count >= 2 else { return 0 }
        return Int(first[1]) ?? 0
    }

    private static func megaDechunk(
        _ body: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < body.count {
            var lineEnd = i
            while lineEnd + 1 < body.count,
                  !(body[lineEnd] == 13
                    && body[lineEnd + 1] == 10) {
                lineEnd += 1
            }
            guard lineEnd + 1 < body.count
            else { break }
            let sizeText = String(
                decoding: Array(body[i..<lineEnd]),
                as: UTF8.self)
            let size = Int(sizeText
                .split(separator: ";").first
                .map(String.init) ?? "",
                radix: 16) ?? 0
            if size == 0 { break }
            let start = lineEnd + 2
            guard start + size <= body.count
            else { break }
            out.append(contentsOf:
                body[start..<(start + size)])
            i = start + size + 2
        }
        return out
    }

    private static func megaHex(
        _ bytes: [UInt8]) -> String {
        bytes.map {
            String(format: "%02x", $0)
        }.joined()
    }
}

extension BlacksiteBench {

    // MARK: the claim tables
    //
    // Built by sequential appends — a
    // large array literal of rules can
    // exceed the type-checker's budget
    // (the house lesson). A rule reads a
    // lowercase haystack of the unit's own
    // claims (its names, banners, papers)
    // and weighs in for a family: weight 3
    // names the family outright, 2 is
    // likely, 1 is a possible sign.

    struct MegaRule {
        var needle: String
        var family: String
        var weight: Int
    }

    static let megaFamilies: [String] = [
        "tesla optimus", "tesla vehicle",
        "tesla energy", "boring / tunnel plant",
        "starlink terminal",
        "industrial arm / cobot",
        "mobile robot (agv / amr)",
        "drone / ground station",
        "cnc / additive",
        "agricultural machinery",
        "construction machinery",
        "building plant",
        "ros robot (maker unnamed)",
        "android machinery",
        "general machinery",
    ]

    static let megaNameRules: [MegaRule] = {
        var a: [MegaRule] = []
        func r(_ needle: String,
               _ family: String,
               _ weight: Int) {
            a.append(MegaRule(
                needle: needle, family: family,
                weight: weight))
        }
        r("optimus", "tesla optimus", 3)
        r("tesla", "tesla optimus", 1)
        r("tesla", "tesla vehicle", 1)
        r("cybertruck", "tesla vehicle", 3)
        r("model 3", "tesla vehicle", 2)
        r("model s", "tesla vehicle", 2)
        r("model x", "tesla vehicle", 2)
        r("model y", "tesla vehicle", 2)
        r("powerwall", "tesla energy", 3)
        r("megapack", "tesla energy", 3)
        r("supercharger", "tesla energy", 2)
        r("energy gateway", "tesla energy", 2)
        r("teg-", "tesla energy", 2)
        r("boring", "boring / tunnel plant", 2)
        r("tbm", "boring / tunnel plant", 2)
        r("tunnel", "boring / tunnel plant", 1)
        r("starlink", "starlink terminal", 3)
        r("dishy", "starlink terminal", 3)
        r("kuka", "industrial arm / cobot", 3)
        r("universal robots", "industrial arm / cobot", 3)
        r("ur3", "industrial arm / cobot", 2)
        r("ur5", "industrial arm / cobot", 2)
        r("ur10", "industrial arm / cobot", 2)
        r("fanuc", "industrial arm / cobot", 3)
        r("yaskawa", "industrial arm / cobot", 3)
        r("motoman", "industrial arm / cobot", 3)
        r("staubli", "industrial arm / cobot", 3)
        r("comau", "industrial arm / cobot", 3)
        r("abb", "industrial arm / cobot", 1)
        r("robot", "industrial arm / cobot", 1)
        r("cobot", "industrial arm / cobot", 2)
        r("agv", "mobile robot (agv / amr)", 2)
        r("amr", "mobile robot (agv / amr)", 2)
        r("mir", "mobile robot (agv / amr)", 1)
        r("locus", "mobile robot (agv / amr)", 2)
        r("fetch robotics", "mobile robot (agv / amr)", 3)
        r("roomba", "mobile robot (agv / amr)", 3)
        r("irobot", "mobile robot (agv / amr)", 3)
        r("roborock", "mobile robot (agv / amr)", 3)
        r("deebot", "mobile robot (agv / amr)", 3)
        r("ecovacs", "mobile robot (agv / amr)", 3)
        r("dreame", "mobile robot (agv / amr)", 2)
        r("spot", "mobile robot (agv / amr)", 1)
        r("unitree", "mobile robot (agv / amr)", 3)
        r("dji", "drone / ground station", 3)
        r("mavic", "drone / ground station", 3)
        r("phantom", "drone / ground station", 2)
        r("inspire", "drone / ground station", 2)
        r("matrice", "drone / ground station", 3)
        r("parrot", "drone / ground station", 2)
        r("anafi", "drone / ground station", 3)
        r("skydio", "drone / ground station", 3)
        r("pixhawk", "drone / ground station", 3)
        r("ardupilot", "drone / ground station", 3)
        r("px4", "drone / ground station", 2)
        r("drone", "drone / ground station", 2)
        r("octoprint", "cnc / additive", 3)
        r("klipper", "cnc / additive", 3)
        r("moonraker", "cnc / additive", 3)
        r("prusa", "cnc / additive", 3)
        r("bambu", "cnc / additive", 3)
        r("creality", "cnc / additive", 3)
        r("ender", "cnc / additive", 2)
        r("cnc", "cnc / additive", 2)
        r("haas", "cnc / additive", 3)
        r("mazak", "cnc / additive", 3)
        r("hurco", "cnc / additive", 3)
        r("printer", "cnc / additive", 1)
        r("john deere", "agricultural machinery", 3)
        r("case ih", "agricultural machinery", 3)
        r("new holland", "agricultural machinery", 3)
        r("agco", "agricultural machinery", 3)
        r("fendt", "agricultural machinery", 3)
        r("trimble", "agricultural machinery", 2)
        r("tractor", "agricultural machinery", 2)
        r("caterpillar", "construction machinery", 3)
        r("komatsu", "construction machinery", 3)
        r("volvo ce", "construction machinery", 3)
        r("hitachi construction", "construction machinery", 3)
        r("excavator", "construction machinery", 2)
        r("otis", "building plant", 2)
        r("kone", "building plant", 2)
        r("schindler", "building plant", 2)
        r("elevator", "building plant", 2)
        r("lift", "building plant", 1)
        r("hvac", "building plant", 2)
        r("trane", "building plant", 3)
        r("carrier", "building plant", 2)
        r("bacnet", "building plant", 2)
        r("siemens", "general machinery", 1)
        r("omron", "general machinery", 1)
        r("mitsubishi", "general machinery", 1)
        r("plc", "general machinery", 1)
        r("ros", "ros robot (maker unnamed)", 1)
        r("rosbridge", "ros robot (maker unnamed)", 3)
        r("rosapi", "ros robot (maker unnamed)", 3)
        r("android", "android machinery", 1)
        return a
    }()

    /// Fragments that make a topic or a
    /// service name read as actuation-
    /// shaped. A claim about shape only —
    /// such entries are printed, never
    /// invoked, never published to.
    static let megaActuationHints: [String] = {
        var a: [String] = []
        a.append("cmd_vel")
        a.append("move")
        a.append("joint")
        a.append("gripper")
        a.append("motor")
        a.append("drive")
        a.append("navigate")
        a.append("trajectory")
        a.append("servo")
        a.append("wheel")
        a.append("estop")
        a.append("e_stop")
        a.append("enable")
        a.append("goal")
        a.append("arm")
        a.append("set_")
        a.append("/control")
        return a
    }()

    static func megaActuationShaped(
        _ name: String) -> Bool {
        let n = name.lowercased()
        return megaActuationHints.contains {
            n.contains($0)
        }
    }

    /// The robot-weighted door board.
    static let megaDoors: [Int] = [
        22, 80, 443, 502, 554, 631, 1883,
        3000, 4840, 5555, 5900, 7125, 8080,
        8443, 8883, 9090, 9100, 11311,
    ]

    static let megaDoorNames: [Int: String] = [
        22: "SSH", 80: "HTTP", 443: "HTTPS",
        502: "Modbus", 554: "RTSP",
        631: "IPP print", 1883: "MQTT",
        3000: "web console",
        4840: "OPC UA", 5555: "ADB",
        5900: "VNC", 7125: "Moonraker",
        8080: "HTTP-alt", 8443: "HTTPS-alt",
        8883: "MQTT-TLS", 9090: "rosbridge",
        9100: "raw print", 11311: "ROS master",
    ]

    // MARK: evidence

    struct MegaEvidence {
        var host: String
        var ip: String
        var open: [Int] = []
        var ptr: String? = nil
        var banners: [Int: String] = [:]
        var neighborName: String? = nil
        var announcements: [String] = []
    }

    /// Gather one host's wire testimony:
    /// doors, its resolver name, what its
    /// web doors and shell door say first,
    /// and what the house already knows of
    /// it. Synchronous — callers ride
    /// BlacksitePentest.run.
    static func megaGather(
        host: String, ip: String,
        doors: [Int]) -> MegaEvidence {
        var ev = MegaEvidence(host: host, ip: ip)
        ev.open = megaDoorScan(ip: ip, doors: doors)
        ev.ptr = megaPTRName(ip)
        if let neighbor = NeighborhoodStore
            .shared.neighbors.first(
                where: { $0.ip == ip }) {
            ev.neighborName = neighbor.name
            ev.announcements =
                neighbor.announcements
        }
        for port in ev.open {
            if port == 80 || port == 8080
                || port == 3000 || port == 443
                || port == 8443 {
                let plate = megaWebNameplate(
                    host: host, port: port)
                var bits: [String] = []
                if let server = plate.server {
                    bits.append(server)
                }
                if let title = plate.title,
                   !title.isEmpty {
                    bits.append(title)
                }
                if !bits.isEmpty {
                    ev.banners[port] = bits
                        .joined(separator: " — ")
                } else if port == 443
                    || port == 8443 {
                    ev.banners[port] =
                        "(tls door; papers read by fleetprobe)"
                }
            } else if port == 22 || port == 21
                || port == 25 {
                if let line = megaFirstLine(
                    ip: ip, port: port) {
                    ev.banners[port] = line
                }
            }
        }
        return ev
    }

    /// The haystack of a unit's own words.
    static func megaHaystack(
        _ ev: MegaEvidence) -> String {
        var parts: [String] = []
        if let ptr = ev.ptr { parts.append(ptr) }
        if let name = ev.neighborName {
            parts.append(name)
        }
        parts.append(contentsOf: ev.announcements)
        for port in ev.banners.keys.sorted() {
            if let banner = ev.banners[port] {
                parts.append(banner)
            }
        }
        return parts.joined(separator: " \n ")
            .lowercased()
    }

    struct MegaGrade {
        var family: String
        var score: Int
        var reasons: [String]
        var word: String {
            if score >= 3 {
                return L("claimed — strong signs")
            }
            if score == 2 {
                return L("claimed — likely")
            }
            return L("claimed — possible")
        }
    }

    /// Does the haystack carry the needle
    /// as its own word? Short needles must
    /// stand between non-alphanumerics —
    /// 'ros' inside 'across' is not a
    /// claim, and 'abb' inside 'rabbit'
    /// names no robot arm.
    static func megaClaimContains(
        _ hay: String, _ needle: String)
        -> Bool {
        if needle.count > 5 {
            return hay.contains(needle)
        }
        let h = Array(hay)
        let n = Array(needle)
        guard !n.isEmpty, h.count >= n.count
        else { return false }
        func alnum(_ c: Character) -> Bool {
            c.isLetter || c.isNumber
        }
        var i = 0
        while i + n.count <= h.count {
            if Array(h[i..<(i + n.count)]) == n {
                let beforeOK = i == 0
                    || !alnum(h[i - 1])
                let after = i + n.count
                let afterOK = after >= h.count
                    || !alnum(h[after])
                if beforeOK && afterOK {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    /// Grade the claims: name rules over
    /// the haystack, then the door shapes.
    static func megaGrades(
        _ ev: MegaEvidence) -> [MegaGrade] {
        let hay = megaHaystack(ev)
        var scores: [String: Int] = [:]
        var reasons: [String: [String]] = [:]
        func weigh(_ family: String,
                   _ weight: Int,
                   _ reason: String) {
            scores[family, default: 0] += weight
            reasons[family, default: []]
                .append(reason)
        }
        for rule in megaNameRules
        where megaClaimContains(hay, rule.needle) {
            weigh(rule.family, rule.weight,
                  String(format: L("its own words carry '%@'"), rule.needle))
        }
        if ev.open.contains(11311) {
            weigh("ros robot (maker unnamed)", 3,
                  L("the ROS master door (11311) answers"))
        }
        if ev.open.contains(9090) {
            weigh("ros robot (maker unnamed)", 3,
                  L("the rosbridge door (9090) answers"))
        }
        if ev.open.contains(5555) {
            weigh("android machinery", 2,
                  L("the ADB door (5555) answers"))
        }
        if ev.open.contains(502)
            || ev.open.contains(4840) {
            weigh("general machinery", 2,
                  L("a plant door (Modbus / OPC UA) answers"))
        }
        if ev.open.contains(7125) {
            weigh("cnc / additive", 3,
                  L("the Moonraker door (7125) answers — a Klipper machine's API"))
        }
        var out: [MegaGrade] = []
        for family in megaFamilies {
            guard let score = scores[family],
                  score > 0 else { continue }
            out.append(MegaGrade(
                family: family, score: score,
                reasons: reasons[family] ?? []))
        }
        return out.sorted {
            $0.score > $1.score
        }
    }

    static func megaIsFlagship(
        _ grades: [MegaGrade]) -> Bool {
        grades.contains {
            $0.family.hasPrefix("tesla")
                || $0.family.hasPrefix("boring")
                || $0.family == "starlink terminal"
        }
    }

    /// Print the claim table for one unit.
    static func megaPrintGrades(
        _ ev: MegaEvidence,
        emit: @escaping BlacksiteEmit) {
        let grades = megaGrades(ev)
        if grades.isEmpty {
            icsSay(emit, L("identity: nothing this unit says names a maker or a family — it stays unnamed here, as it presents itself"), .out)
            return
        }
        for grade in grades {
            icsSay(emit, String(
                format: L("claim: %@ — %@"),
                grade.family, grade.word), .ok)
            for reason in grade.reasons {
                icsSay(emit, "  · " + reason)
            }
        }
        icsSay(emit, L("a claim is the unit's own testimony weighed — evidence, never proof of a name"), .out)
    }
}

extension BlacksiteBench {

    // MARK: primeprobe / botprobe — the fingerprint read

    /// Resolve, gather, grade: the shared
    /// body of primeprobe (Optimus-weighted)
    /// and botprobe (the universal read).
    private static func megaProbeCore(
        host: String, ip: String,
        optimus: Bool,
        emit: @escaping BlacksiteEmit) {
        let ev = megaGather(
            host: host, ip: ip, doors: megaDoors)
        icsSay(emit, String(
            format: L("%@ — %@ (%@)"),
            optimus ? "primeprobe" : "botprobe",
            host, ip), .sys)
        if let ptr = ev.ptr {
            icsSay(emit, String(
                format: L("the resolver names it %@ — a claim the wire's book makes, printed as such"), ptr))
        }
        if let name = ev.neighborName {
            icsSay(emit, String(
                format: L("this house knows it as %@"), name))
        }
        for ann in ev.announcements.prefix(6) {
            icsSay(emit, String(
                format: L("it announces %@"), ann))
        }
        if ev.open.isEmpty {
            icsSay(emit, L("none of the machine doors answer — from here this host presents no robotics surface"), .err)
        } else {
            let named = ev.open.map {
                "\(megaDoorNames[$0] ?? "door") \($0)"
            }
            icsSay(emit, String(
                format: L("machine doors answering: %@"),
                named.joined(separator: " · ")))
        }
        for port in ev.banners.keys.sorted() {
            if let banner = ev.banners[port] {
                icsSay(emit, String(
                    format: L("door %lld says: %@"),
                    Int64(port), banner))
            }
        }
        megaPrintGrades(ev, emit: emit)
        icsSay(emit, L("note: a neighbour's MAC address is not readable from iOS, so no OUI claim is made for wire hosts — the claims above ride on the unit's own words and doors, which is the testimony available"))
        if optimus {
            let grades = megaGrades(ev)
            if grades.contains(where: {
                $0.family == "tesla optimus"
                    && $0.score >= 3
            }) {
                icsSay(emit, L("flagship prey: the signs read Optimus-shaped. What it trusts is fleetprobe's read; whether it could be puppeted is puppetprobe's grade"), .err)
            } else if ev.open.contains(9090)
                || ev.open.contains(11311) {
                icsSay(emit, L("a ROS-shaped unit: the Optimus battery's doors answer, but nothing yet names it Tesla's — the claim stays with what the wire said"), .out)
            }
        }
    }

    static func megaProbeVerb(
        _ arg: String, optimus: Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let target = arg
            .split(separator: " ").first
            .map(String.init) ?? ""
        guard !target.isEmpty,
              let resolved = icsResolve(
                target, 80) else {
            icsSay(emit, optimus
                ? L("primeprobe: give the unit's host — primeprobe 192.168.1.42")
                : L("botprobe: give the machine's host — botprobe 192.168.1.42"), .err)
            done()
            return
        }
        BlacksitePentest.run {
            megaProbeCore(
                host: resolved.host,
                ip: resolved.ip,
                optimus: optimus, emit: emit)
            if !optimus {
                // The universal read rides the
                // plant bench where plant
                // doors answered: nameplates
                // by the ICS wave's own hand,
                // chained on the verb's own
                // completion so nothing is
                // spoken after the board ends.
                let open = megaDoorScan(
                    ip: resolved.ip,
                    doors: [502, 4840])
                if !open.isEmpty {
                    icsSay(emit, L("botprobe — the plant nameplates, by the ICS bench:"), .sys)
                    benchICS(
                        "plcensus",
                        resolved.host,
                        emit: emit, done: done)
                    return
                }
            }
            done()
        }
    }

    // MARK: botdoors — the robot-weighted doors census

    static func megaBotDoors(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let target = arg
                .split(separator: " ").first
                .map(String.init) ?? ""
            guard !target.isEmpty,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("botdoors: give the machine's host — botdoors 192.168.1.42"), .err)
                return
            }
            let open = megaDoorScan(
                ip: resolved.ip, doors: megaDoors)
            icsSay(emit, String(
                format: L("botdoors — %@ (%@): the doors a machine keeps"),
                resolved.host, resolved.ip), .sys)
            if open.isEmpty {
                icsSay(emit, L("no machine door answers — the unit keeps its doors shut, or it is not listening on this wire"), .err)
                return
            }
            for port in open {
                let name = megaDoorNames[port]
                    ?? L("unlisted door")
                var line = String(
                    format: L("door %lld — %@"),
                    Int64(port), name)
                if port == 80 || port == 8080
                    || port == 3000 {
                    let plate = megaWebNameplate(
                        host: resolved.host,
                        port: port)
                    if let server = plate.server {
                        line += " — " + server
                    }
                    if let title = plate.title,
                       !title.isEmpty {
                        line += " · " + title
                    }
                } else if port == 22 {
                    if let banner = megaFirstLine(
                        ip: resolved.ip, port: 22) {
                        line += " — " + banner
                    }
                }
                icsSay(emit, line, .ok)
            }
            let ev = MegaEvidence(
                host: resolved.host,
                ip: resolved.ip, open: open)
            let grades = megaGrades(ev)
            for grade in grades {
                icsSay(emit, String(
                    format: L("the door shape claims: %@ — %@"),
                    grade.family, grade.word))
            }
            if open.contains(5555) {
                icsSay(emit, L("ADB stands open: on Android machinery that door is a shell waiting for a greeting — puppetprobe reads its manners"), .err)
            }
            if open.contains(9090)
                || open.contains(11311) {
                icsSay(emit, L("ROS doors stand open: the master's registry and the bridge are the robot's public squares — rosprobe reads their posture"), .err)
            }
            icsSay(emit, L("grade: a door census is a knock, not an entry — what each door would say to a greeting is the probes' own reads"))
        }
    }

    // MARK: fleetprobe — the papers a unit presents

    /// The fleet-link section, shared by
    /// fleetprobe, cyberprobe, voltprobe
    /// and the marquee: TLS knocks on the
    /// unit's answered TLS doors, the leaf
    /// read whole, the chain named.
    static func megaFleetSection(
        host: String, ip: String,
        open: [Int],
        emit: @escaping BlacksiteEmit) {
        let tlsDoors = open.filter {
            $0 == 443 || $0 == 8443
                || $0 == 8883
        }
        icsSay(emit, L("fleetprobe — the papers it presents"), .sys)
        if tlsDoors.isEmpty {
            icsSay(emit, L("no TLS door answers — the unit shows no papers on this wire; its trust, if any, rides elsewhere"), .out)
            return
        }
        for port in tlsDoors {
            let knock = lockTLSKnock(
                ip: ip, port: port, host: host,
                minV: .tlsProtocol12,
                maxV: .tlsProtocol13,
                onlySuite: nil)
            guard knock.answered,
                  let trust = knock.trust else {
                icsSay(emit, String(
                    format: L("door %lld: a TLS knock went unanswered in the modern range"),
                    Int64(port)), .err)
                continue
            }
            icsSay(emit, String(
                format: L("door %lld — the chain it presents:"),
                Int64(port)), .sys)
            let count = SecTrustGetCertificateCount(
                trust)
            for index in 0..<count {
                guard let cert =
                    SecTrustGetCertificateAtIndex(
                        trust, index) else {
                    continue
                }
                if index == 0 {
                    let der = [UInt8](
                        SecCertificateCopyData(
                            cert) as Data)
                    if let parsed = lockCertParse(
                        der) {
                        lockDescribeCert(
                            parsed, emit: emit)
                    } else {
                        let summary =
                            (SecCertificateCopySubjectSummary(
                                cert) as String?)
                            ?? L("an unnamed paper")
                        icsSay(emit, String(
                            format: L("subject: %@"),
                            summary))
                    }
                } else {
                    let summary =
                        (SecCertificateCopySubjectSummary(
                            cert) as String?)
                        ?? L("an unnamed paper")
                    icsSay(emit, String(
                        format: L("chain %lld: %@"),
                        Int64(index), summary))
                }
            }
            if count > 0,
               let leaf = SecTrustGetCertificateAtIndex(
                trust, 0),
               let parsed = lockCertParse(
                [UInt8](SecCertificateCopyData(
                    leaf) as Data)) {
                if parsed.issuerRaw
                    == parsed.subjectRaw {
                    icsSay(emit, L("grade: the unit's papers are self-issued — it trusts its own word, and so must anything that talks to it"), .err)
                } else {
                    icsSay(emit, String(
                        format: L("grade: the unit answers to %@ — that is whose word it carries on this wire"),
                        parsed.issuerLine))
                }
            }
        }
    }

    static func megaFleetVerb(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let target = arg
                .split(separator: " ").first
                .map(String.init) ?? ""
            guard !target.isEmpty,
                  let resolved = icsResolve(
                    target, 443) else {
                icsSay(emit, L("fleetprobe: give the unit's host — fleetprobe 192.168.1.42"), .err)
                return
            }
            let open = megaDoorScan(
                ip: resolved.ip,
                doors: [443, 8443, 8883])
            megaFleetSection(
                host: resolved.host,
                ip: resolved.ip, open: open,
                emit: emit)
        }
    }
}

extension BlacksiteBench {

    // MARK: the ROS master — XML-RPC registry queries
    //
    // Only registry queries are ever sent:
    // getUri and getSystemState. No setParam
    // (a SET), no shutdown, no node control —
    // the master is read the way a phone book
    // is read. The parser is the Python-
    // verified recursive value reader.

    enum MegaXML {
        case int(Int)
        case text(String)
        case list([MegaXML])
    }

    private static func megaXMLParseValue(
        _ bytes: [UInt8], _ i: inout Int)
        -> MegaXML? {
        // Scan helpers over raw UTF-8 bytes.
        func skipWS() {
            while i < bytes.count,
                  bytes[i] == 32 || bytes[i] == 9
                    || bytes[i] == 10
                    || bytes[i] == 13 {
                i += 1
            }
        }
        func readTag() -> String? {
            skipWS()
            guard i < bytes.count,
                  bytes[i] == 60 else { return nil }
            var j = i + 1
            while j < bytes.count,
                  bytes[j] != 62 {
                j += 1
            }
            guard j < bytes.count else {
                return nil
            }
            let tag = String(
                decoding: bytes[(i + 1)..<j],
                as: UTF8.self)
                .trimmingCharacters(
                    in: .whitespaces)
            i = j + 1
            return tag
        }
        func readText(_ close: String)
            -> String? {
            let needle = [UInt8](
                ("</" + close + ">").utf8)
            var j = i
            while j + needle.count <= bytes.count {
                if Array(bytes[j..<(j
                    + needle.count)]) == needle {
                    let text = String(
                        decoding: bytes[i..<j],
                        as: UTF8.self)
                    i = j + needle.count
                    return text
                }
                j += 1
            }
            return nil
        }
        guard readTag() == "value" else {
            return nil
        }
        let save = i
        guard let kind = readTag() else {
            return nil
        }
        if kind == "/value" || kind == "value" {
            i = save
            guard let bare = readText("value")
            else { return nil }
            return .text(bare)
        }
        switch kind {
        case "i4", "int":
            guard let t = readText(kind)
            else { return nil }
            guard readTag() == "/value"
            else { return nil }
            return .int(Int(t
                .trimmingCharacters(
                    in: .whitespaces)) ?? 0)
        case "string":
            guard let t = readText("string")
            else { return nil }
            guard readTag() == "/value"
            else { return nil }
            return .text(t)
        case "boolean":
            guard let t = readText("boolean")
            else { return nil }
            guard readTag() == "/value"
            else { return nil }
            return .int(t
                .trimmingCharacters(
                    in: .whitespaces) == "1"
                ? 1 : 0)
        case "double":
            guard let t = readText("double")
            else { return nil }
            guard readTag() == "/value"
            else { return nil }
            return .text(t)
        case "array":
            guard readTag() == "data"
            else { return nil }
            var out: [MegaXML] = []
            while true {
                let mark = i
                guard let next = readTag()
                else { return nil }
                if next == "/data" { break }
                i = mark
                guard let v = megaXMLParseValue(
                    bytes, &i) else {
                    return nil
                }
                out.append(v)
            }
            guard readTag() == "/array"
            else { return nil }
            guard readTag() == "/value"
            else { return nil }
            return .list(out)
        default:
            return nil
        }
    }

    private static func megaXMLStrings(
        _ value: MegaXML) -> [String] {
        switch value {
        case .text(let s): return [s]
        case .list(let items):
            return items.flatMap {
                megaXMLStrings($0)
            }
        case .int: return []
        }
    }

    /// The topic names of one state arm
    /// ([[topic, [nodes]], ...] → [topic]).
    private static func megaXMLTopics(
        _ value: MegaXML) -> [String] {
        guard case .list(let arms) = value
        else { return [] }
        var out: [String] = []
        for arm in arms {
            if case .list(let pair) = arm,
               let first = pair.first,
               case .text(let topic) = first {
                out.append(topic)
            }
        }
        return out
    }

    struct MegaMaster {
        var uri: String?
        var publishers: [String] = []
        var subscribers: [String] = []
        var services: [String] = []
    }

    private static func megaMasterCall(
        ip: String, method: String)
        -> MegaXML? {
        let body = "<?xml version=\"1.0\"?>\n"
            + "<methodCall><methodName>"
            + method
            + "</methodName><params><param>"
            + "<value><string>/megatron"
            + "</string></value></param>"
            + "</params></methodCall>"
        var request = "POST / HTTP/1.1\r\n"
        request += "Host: \(ip):11311\r\n"
        request += "Content-Type: text/xml\r\n"
        request += "Content-Length: "
            + "\(body.utf8.count)\r\n"
        request += "Connection: close\r\n\r\n"
        request += body
        guard let got = megaHTTPExchange(
            ip: ip, port: 11311,
            request: [UInt8](request.utf8))
        else { return nil }
        // Find the response's first <value>.
        let bytes = got.body
        var start: Int? = nil
        let open = [UInt8]("<value>".utf8)
        if bytes.count >= open.count {
            for at in 0..<(bytes.count
                - open.count + 1) {
                if Array(bytes[at..<(at
                    + open.count)]) == open {
                    start = at
                    break
                }
            }
        }
        guard var i = start else { return nil }
        return megaXMLParseValue(bytes, &i)
    }

    static func megaMasterRead(
        ip: String) -> MegaMaster? {
        guard let uriReply = megaMasterCall(
            ip: ip, method: "getUri") else {
            return nil
        }
        var master = MegaMaster(uri: nil)
        if case .list(let parts) = uriReply,
           parts.count >= 3,
           case .text(let uri) = parts[2] {
            master.uri = uri
        }
        if let stateReply = megaMasterCall(
            ip: ip, method: "getSystemState"),
           case .list(let parts) = stateReply,
           parts.count >= 3,
           case .list(let arms) = parts[2],
           arms.count == 3 {
            master.publishers =
                megaXMLTopics(arms[0])
            master.subscribers =
                megaXMLTopics(arms[1])
            master.services =
                megaXMLTopics(arms[2])
        }
        return master
    }

    // MARK: rosbridge — the WebSocket query census
    //
    // The bridge is asked, through its own
    // rosapi query services, what topics,
    // services and nodes it knows. Queries
    // only: nothing is published, nothing
    // subscribed, no service beyond the
    // rosapi census is ever called.

    private static func megaWSFrame(
        payload: [UInt8], opcode: UInt8,
        maskKey: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x80 | opcode]
        let n = payload.count
        if n < 126 {
            out.append(0x80 | UInt8(n))
        } else if n < 65536 {
            out.append(0x80 | 126)
            out.append(UInt8((n >> 8) & 0xFF))
            out.append(UInt8(n & 0xFF))
        } else {
            out.append(0x80 | 127)
            for shift in stride(
                from: 56, through: 0, by: -8) {
                out.append(UInt8(
                    (n >> shift) & 0xFF))
            }
        }
        out.append(contentsOf: maskKey)
        for (index, byte) in payload
            .enumerated() {
            out.append(byte ^ maskKey[index % 4])
        }
        return out
    }

    /// Open a WebSocket to the bridge and
    /// prove the handshake (the accept is
    /// checked against the key we sent).
    private static func megaWSOpen(
        ip: String, port: Int, host: String)
        -> Int32? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(port),
            timeout: 3) else {
            return nil
        }
        let keyBytes: [UInt8] = (0..<16).map {
            _ in UInt8.random(in: 0...255)
        }
        let key = Data(keyBytes)
            .base64EncodedString()
        var request = "GET / HTTP/1.1\r\n"
        request += "Host: \(host):\(port)\r\n"
        request += "Upgrade: websocket\r\n"
        request += "Connection: Upgrade\r\n"
        request += "Sec-WebSocket-Key: "
            + key + "\r\n"
        request += "Sec-WebSocket-Version: 13"
            + "\r\n\r\n"
        let reqBytes = [UInt8](request.utf8)
        var sent = 0
        var ok = true
        while sent < reqBytes.count {
            let n = reqBytes
                .withUnsafeBufferPointer {
                    buffer in
                    send(fd,
                         buffer.baseAddress!
                            + sent,
                         reqBytes.count - sent, 0)
                }
            if n <= 0 { ok = false; break }
            sent += n
        }
        guard ok else {
            close(fd)
            return nil
        }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 3)
        var head: [UInt8] = []
        var chunk = [UInt8](
            repeating: 0, count: 4096)
        while megaFindCRLFCRLF(head) == nil,
              head.count < 16384 {
            let got = recv(fd, &chunk,
                           chunk.count, 0)
            if got <= 0 { break }
            head.append(contentsOf:
                chunk[0..<got])
        }
        let headText = String(
            decoding: head, as: UTF8.self)
        guard headText.contains("101") else {
            close(fd)
            return nil
        }
        let guid = "258EAFA5-E914-47DA-95CA"
            + "-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(
            data: Data((key + guid).utf8))
        let expect = Data(digest)
            .base64EncodedString()
        // The accept must be the SHA-1
        // proof over the key we sent — a
        // 101 without it is not the bridge
        // keeping the protocol's word.
        guard headText.lowercased().contains(
            "sec-websocket-accept: "
                + expect.lowercased()) else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Read one complete message, answering
    /// pings with pongs along the way.
    private static func megaWSReadMessage(
        fd: Int32, maskKey: [UInt8],
        deadline: Date)
        -> (opcode: UInt8, payload: [UInt8])? {
        var assembled: [UInt8] = []
        var assembledOpcode: UInt8 = 0
        func readMore(
            _ count: Int) -> [UInt8]? {
            var out: [UInt8] = []
            while out.count < count {
                if Date() > deadline {
                    return nil
                }
                var chunk = [UInt8](
                    repeating: 0,
                    count: count - out.count)
                let got = recv(
                    fd, &chunk, chunk.count, 0)
                if got < 0 { continue }
                if got == 0 { return nil }
                out.append(contentsOf:
                    chunk[0..<got])
            }
            return out
        }
        while Date() < deadline {
            guard let head = readMore(2) else {
                return nil
            }
            let fin = head[0] & 0x80 != 0
            let opcode = head[0] & 0x0F
            var length = Int(head[1] & 0x7F)
            let masked = head[1] & 0x80 != 0
            if length == 126 {
                guard let ext = readMore(2)
                else { return nil }
                length = Int(ext[0]) << 8
                    | Int(ext[1])
            } else if length == 127 {
                guard let ext = readMore(8)
                else { return nil }
                length = 0
                for b in ext {
                    length = length << 8 | Int(b)
                }
            }
            guard length < 4_000_000 else {
                return nil
            }
            var mask: [UInt8] = [0, 0, 0, 0]
            if masked {
                guard let m = readMore(4)
                else { return nil }
                mask = m
            }
            guard let raw = readMore(length)
            else { return nil }
            var payload = raw
            if masked {
                for index in payload.indices {
                    payload[index] = raw[index]
                        ^ mask[index % 4]
                }
            }
            if opcode == 9 {
                // A ping: answer with a pong
                // carrying the same payload.
                let pong = megaWSFrame(
                    payload: payload, opcode: 0xA,
                    maskKey: maskKey)
                _ = pong.withUnsafeBufferPointer {
                    buffer in
                    send(fd, buffer.baseAddress!,
                         pong.count, 0)
                }
                continue
            }
            if opcode == 8 { return nil }
            if opcode == 0 {
                assembled.append(
                    contentsOf: payload)
                if fin {
                    return (assembledOpcode,
                            assembled)
                }
                continue
            }
            assembledOpcode = opcode
            assembled = payload
            if fin { return (opcode, payload) }
        }
        return nil
    }

    struct MegaBridge {
        var topics: [String] = []
        var services: [String] = []
        var nodes: [String] = []
    }

    /// The rosapi census over one bridge
    /// connection: topics, services, nodes
    /// — the bridge's own answers to its
    /// own query services.
    static func megaBridgeCensus(
        ip: String, host: String)
        -> MegaBridge? {
        let maskKey: [UInt8] = [0x4D, 0x45,
                                0x47, 0x41]
        guard let fd = megaWSOpen(
            ip: ip, port: 9090, host: host)
        else { return nil }
        defer { close(fd) }
        var bridge = MegaBridge()
        let asks: [(String, String)] = [
            ("/rosapi/topics", "topics"),
            ("/rosapi/services", "services"),
            ("/rosapi/nodes", "nodes"),
        ]
        for (service, idTag) in asks {
            let call: [String: Any] = [
                "op": "call_service",
                "service": service,
                "args": [Any](),
                "id": "megatron-" + idTag,
            ]
            guard let data = try?
                JSONSerialization.data(
                    withJSONObject: call),
                  megaWSSend(fd, [UInt8](data),
                             maskKey) else {
                continue
            }
            let deadline = Date()
                .addingTimeInterval(5)
            while Date() < deadline {
                guard let message =
                    megaWSReadMessage(
                        fd: fd, maskKey: maskKey,
                        deadline: deadline)
                else { break }
                guard message.opcode == 1
                    || message.opcode == 2
                else { continue }
                guard let object = try?
                    JSONSerialization.jsonObject(
                        with: Data(
                            message.payload)),
                      let dict = object
                        as? [String: Any],
                      dict["id"] as? String
                        == "megatron-" + idTag,
                      let values = dict["values"]
                        as? [String: Any]
                else { continue }
                if idTag == "topics",
                   let list = values["topics"]
                    as? [String] {
                    bridge.topics = list
                }
                if idTag == "services",
                   let list = values["services"]
                    as? [String] {
                    bridge.services = list
                }
                if idTag == "nodes",
                   let list = values["nodes"]
                    as? [String] {
                    bridge.nodes = list
                }
                break
            }
        }
        return bridge
    }

    private static func megaWSSend(
        _ fd: Int32, _ payload: [UInt8],
        _ maskKey: [UInt8]) -> Bool {
        let frame = megaWSFrame(
            payload: payload, opcode: 1,
            maskKey: maskKey)
        var sent = 0
        while sent < frame.count {
            let n = frame
                .withUnsafeBufferPointer {
                    buffer in
                    send(fd,
                         buffer.baseAddress!
                            + sent,
                         frame.count - sent, 0)
                }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}

extension BlacksiteBench {

    // MARK: DDS — the discovery census, listened to
    //
    // SPDP announcements are multicast to
    // 239.255.0.1:7400 (domain 0 — the
    // ROS 2 default). The bench joins the
    // group and LISTENS: it never announces
    // a participant of its own. The parse
    // below is the Python-verified walk:
    // header, submessage walk, the DATA
    // payload's parameter list.

    struct MegaParticipant {
        var fromIP: String
        var guidHex: String
        var vendorRaw: String
        var protoMajor: Int
        var protoMinor: Int
        var leaseSeconds: Int?
        var locators: [String] = []
        var builtinSet: UInt32 = 0
        var properties: [(String, String)] = []
        var security: Bool {
            properties.contains {
                $0.0.hasPrefix("dds.sec.")
            }
        }
        var nameClaims: [String] {
            properties
                .filter {
                    $0.0.lowercased()
                        .contains("name")
                        && !$0.1.isEmpty
                }
                .map { "\($0.0)=\($0.1)" }
        }
    }

    private static func megaU16LE(
        _ b: [UInt8], _ at: Int) -> Int {
        guard at + 1 < b.count else { return 0 }
        return Int(b[at]) | (Int(b[at + 1]) << 8)
    }

    private static func megaU32LE(
        _ b: [UInt8], _ at: Int) -> Int {
        guard at + 3 < b.count else { return 0 }
        return Int(b[at])
            | (Int(b[at + 1]) << 8)
            | (Int(b[at + 2]) << 16)
            | (Int(b[at + 3]) << 24)
    }

    static func megaParseSPDP(
        _ pkt: [UInt8], from: String)
        -> MegaParticipant? {
        guard pkt.count > 20,
              Array(pkt[0..<4])
                == [UInt8]("RTPS".utf8) else {
            return nil
        }
        var found: MegaParticipant? = nil
        var i = 20
        while i + 4 <= pkt.count {
            let sid = pkt[i]
            let flags = pkt[i + 1]
            let length = megaU16LE(pkt, i + 2)
            let bodyStart = i + 4
            guard bodyStart + length
                <= pkt.count else { break }
            let body = Array(
                pkt[bodyStart..<(bodyStart
                    + length)])
            if sid == 0x15, body.count >= 18 {
                // DATA: payload begins after
                // octetsToInlineQos(2) +
                // readerId(4) + writerId(4)
                // + sequenceNumber(8).
                let pay = Array(body[18...])
                if pay.count >= 4 {
                    var participant =
                        MegaParticipant(
                            fromIP: from,
                            guidHex: "",
                            vendorRaw: megaHex(
                                Array(pkt[6..<8])),
                            protoMajor: Int(pkt[4]),
                            protoMinor: Int(pkt[5]))
                    var j = 4
                    while j + 4 <= pay.count {
                        let pid = megaU16LE(
                            pay, j)
                        let plen = megaU16LE(
                            pay, j + 2)
                        if pid == 0x0001 { break }
                        guard j + 4 + plen
                            <= pay.count else {
                            break
                        }
                        let valEnd = j + 4 + plen
                        let val = Array(
                            pay[(j + 4)..<valEnd])
                        switch pid {
                        case 0x0050:
                            participant.guidHex =
                                megaHex(val)
                        case 0x0015:
                            if val.count >= 2 {
                                participant
                                    .protoMajor =
                                    Int(val[0])
                                participant
                                    .protoMinor =
                                    Int(val[1])
                            }
                        case 0x0002:
                            participant
                                .leaseSeconds =
                                megaU32LE(val, 0)
                        case 0x0031, 0x0032,
                             0x0033, 0x0048:
                            if val.count >= 24 {
                                let port =
                                    megaU32LE(
                                        val, 4)
                                let ip = val[20..<24]
                                    .map {
                                        String($0)
                                    }.joined(
                                        separator: ".")
                                participant.locators
                                    .append(
                                        "\(ip):\(port)")
                            }
                        case 0x0058:
                            participant.builtinSet =
                                UInt32(megaU32LE(
                                    val, 0))
                        case 0x0059:
                            participant.properties =
                                megaParseProperties(
                                    val)
                        default:
                            break
                        }
                        j += 4 + plen
                        while j % 4 != 0 { j += 1 }
                    }
                    if !participant.guidHex
                        .isEmpty {
                        found = participant
                    }
                }
            }
            i = bodyStart + length
            _ = flags
        }
        return found
    }

    private static func megaParseProperties(
        _ val: [UInt8]) -> [(String, String)] {
        guard val.count >= 4 else { return [] }
        let count = megaU32LE(val, 0)
        var k = 4
        var out: [(String, String)] = []
        func readString() -> String? {
            guard k + 4 <= val.count else {
                return nil
            }
            let len = megaU32LE(val, k)
            guard len > 0,
                  k + 4 + len <= val.count
            else { return nil }
            let raw = Array(
                val[(k + 4)..<(k + 4 + len)])
            let text = String(
                decoding: raw.dropLast(),
                as: UTF8.self)
            k += 4 + len
            while k % 4 != 0 { k += 1 }
            return text
        }
        for _ in 0..<min(count, 64) {
            guard let key = readString(),
                  let value = readString()
            else { break }
            out.append((key, value))
        }
        return out
    }

    /// Listen on the discovery group for a
    /// window; returns the participants
    /// heard, deduplicated by GUID.
    static func megaDDSListen(
        seconds: Double = 5.0)
        -> (heard: [MegaParticipant],
            bound: Bool) {
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return ([], false) }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET,
                   SO_REUSEADDR, &one,
                   socklen_t(MemoryLayout<
                    Int32>.size))
        var local = BlacksiteNet.sockaddrIn(
            ip: "0.0.0.0", port: 7400)
        let bound = withUnsafeMutablePointer(
            to: &local) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self, capacity: 1) {
                    sa in
                    bind(fd, sa, socklen_t(
                        MemoryLayout<
                            sockaddr_in>.size))
                }
            } == 0
        guard bound else { return ([], false) }
        // Join the SPDP group on this
        // phone's own interface.
        var mreq = ip_mreq()
        inet_pton(AF_INET, "239.255.0.1",
                  &mreq.imr_multiaddr)
        if let own = BlacksiteNet.primaryIPv4() {
            inet_pton(AF_INET, own,
                      &mreq.imr_interface)
        }
        _ = setsockopt(fd, IPPROTO_IP,
                       IP_ADD_MEMBERSHIP,
                       &mreq, socklen_t(
                        MemoryLayout<
                            ip_mreq>.size))
        var byGUID: [String: MegaParticipant]
            = [:]
        let deadline = Date()
            .addingTimeInterval(seconds)
        while Date() < deadline {
            BlacksiteNet.setRecvTimeout(
                fd, seconds: 0.4)
            var buffer = [UInt8](
                repeating: 0, count: 65536)
            var from = sockaddr_in()
            var fromLen = socklen_t(
                MemoryLayout<sockaddr_in>.size)
            let got = withUnsafeMutablePointer(
                to: &from) { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1) { sa in
                    recvfrom(fd, &buffer,
                             buffer.count, 0,
                             sa, &fromLen)
                }
            }
            guard got > 20 else { continue }
            var addr = from.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &addr, &text,
                      socklen_t(text.count))
            let sender = String(cString: text)
            if let participant =
                megaParseSPDP(
                    Array(buffer[0..<got]),
                    from: sender) {
                byGUID[participant.guidHex] =
                    participant
            }
        }
        return (byGUID.values.sorted {
            $0.guidHex < $1.guidHex
        }, true)
    }

    // MARK: MAVLink — the heartbeat census, listened to
    //
    // Ground stations and drones trade
    // heartbeats on UDP 14550. The bench
    // binds the door and listens; the
    // framing and the X.25 checksum are
    // the Python-verified parse.

    struct MegaHeartbeat {
        var fromIP: String
        var version: String
        var sysid: Int
        var compid: Int
        var vehicleType: Int
        var autopilot: Int
        var crcOK: Bool
    }

    private static func megaX25(
        _ bytes: [UInt8], extra: UInt8)
        -> UInt16 {
        var crc: UInt16 = 0xFFFF
        func acc(_ b: UInt8) {
            var tmp = b ^ UInt8(crc & 0xFF)
            tmp = tmp ^ (tmp << 4)
            crc = (crc >> 8) ^ (UInt16(tmp) << 8)
                ^ (UInt16(tmp) << 3)
                ^ (UInt16(tmp) >> 4)
        }
        for b in bytes { acc(b) }
        acc(extra)
        return crc
    }

    static func megaMAVParse(
        _ buf: [UInt8], from: String)
        -> [MegaHeartbeat] {
        var out: [MegaHeartbeat] = []
        var i = 0
        while i + 8 < buf.count {
            let magic = buf[i]
            if magic == 0xFD {
                let len = Int(buf[i + 1])
                guard i + 12 + len <= buf.count
                else { break }
                let sysid = Int(buf[i + 5])
                let compid = Int(buf[i + 6])
                let msgid = Int(buf[i + 7])
                    | (Int(buf[i + 8]) << 8)
                    | (Int(buf[i + 9]) << 16)
                if msgid == 0, len >= 9 {
                    let pay = Array(
                        buf[(i + 10)..<(i + 10
                            + len)])
                    let crcGiven = UInt16(
                        buf[i + 10 + len])
                        | (UInt16(
                            buf[i + 11 + len])
                            << 8)
                    let crcCalc = megaX25(
                        Array(buf[(i + 1)..<(i
                            + 10 + len)]),
                        extra: 50)
                    out.append(MegaHeartbeat(
                        fromIP: from,
                        version: "v2",
                        sysid: sysid,
                        compid: compid,
                        vehicleType: Int(pay[5]),
                        autopilot: Int(pay[6]),
                        crcOK: crcGiven == crcCalc))
                }
                i += 12 + len
            } else if magic == 0xFE {
                let len = Int(buf[i + 1])
                guard i + 8 + len <= buf.count
                else { break }
                let sysid = Int(buf[i + 3])
                let compid = Int(buf[i + 4])
                let msgid = Int(buf[i + 5])
                if msgid == 0, len >= 9 {
                    let pay = Array(
                        buf[(i + 6)..<(i + 6
                            + len)])
                    let crcGiven = UInt16(
                        buf[i + 6 + len])
                        | (UInt16(buf[i + 7
                            + len]) << 8)
                    let crcCalc = megaX25(
                        Array(buf[(i + 1)..<(i
                            + 6 + len)]),
                        extra: 50)
                    out.append(MegaHeartbeat(
                        fromIP: from,
                        version: "v1",
                        sysid: sysid,
                        compid: compid,
                        vehicleType: Int(pay[5]),
                        autopilot: Int(pay[6]),
                        crcOK: crcGiven == crcCalc))
                }
                i += 8 + len
            } else {
                i += 1
            }
        }
        return out
    }

    static func megaMAVListen(
        seconds: Double = 4.0)
        -> [MegaHeartbeat] {
        let fd = socket(AF_INET, SOCK_DGRAM,
                        IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET,
                   SO_REUSEADDR, &one,
                   socklen_t(MemoryLayout<
                    Int32>.size))
        var local = BlacksiteNet.sockaddrIn(
            ip: "0.0.0.0", port: 14550)
        let bound = withUnsafeMutablePointer(
            to: &local) { ptr in
            ptr.withMemoryRebound(
                to: sockaddr.self, capacity: 1) {
                    sa in
                    bind(fd, sa, socklen_t(
                        MemoryLayout<
                            sockaddr_in>.size))
                }
            } == 0
        guard bound else { return [] }
        var heard: [MegaHeartbeat] = []
        let deadline = Date()
            .addingTimeInterval(seconds)
        while Date() < deadline {
            BlacksiteNet.setRecvTimeout(
                fd, seconds: 0.4)
            var buffer = [UInt8](
                repeating: 0, count: 65536)
            var from = sockaddr_in()
            var fromLen = socklen_t(
                MemoryLayout<sockaddr_in>.size)
            let got = withUnsafeMutablePointer(
                to: &from) { ptr in
                ptr.withMemoryRebound(
                    to: sockaddr.self,
                    capacity: 1) { sa in
                    recvfrom(fd, &buffer,
                             buffer.count, 0,
                             sa, &fromLen)
                }
            }
            guard got > 8 else { continue }
            var addr = from.sin_addr
            var text = [CChar](
                repeating: 0, count: 64)
            inet_ntop(AF_INET, &addr, &text,
                      socklen_t(text.count))
            heard.append(contentsOf:
                megaMAVParse(
                    Array(buffer[0..<got]),
                    from: String(cString: text)))
        }
        return heard
    }

    static func megaMAVTypeName(
        _ type: Int) -> String {
        switch type {
        case 0: return L("generic")
        case 1: return L("fixed-wing")
        case 2: return L("quadrotor")
        case 3: return L("coaxial helicopter")
        case 4: return L("helicopter")
        case 5: return L("antenna tracker")
        case 6: return L("ground station")
        case 10: return L("ground rover")
        case 11: return L("surface boat")
        case 12: return L("submarine")
        case 13: return L("hexarotor")
        case 14: return L("octorotor")
        case 15: return L("tricopter")
        default:
            return String(
                format: L("type %lld"),
                Int64(type))
        }
    }

    static func megaMAVAutopilotName(
        _ ap: Int) -> String {
        switch ap {
        case 0: return L("generic")
        case 3: return "ArduPilot"
        case 12: return "PX4"
        default:
            return String(
                format: L("autopilot %lld"),
                Int64(ap))
        }
    }

    // MARK: rosprobe — the ROS posture read

    static func megaROSSection(
        host: String, ip: String,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, L("rosprobe — the ROS posture"), .sys)
        // The master.
        if megaDoorOpen(ip: ip, port: 11311,
                        deadline: 0.9) {
            if let master = megaMasterRead(
                ip: ip) {
                icsSay(emit, String(
                    format: L("the ROS master answers at 11311 — its registry is read by query, the way a phone book is read")), .ok)
                if let uri = master.uri {
                    icsSay(emit, String(
                        format: L("the master names its own address %@ — the claim it makes of itself"), uri))
                }
                icsSay(emit, String(
                    format: L("published topics: %lld · subscribed topics: %lld · services: %lld"),
                    Int64(master.publishers.count),
                    Int64(master.subscribers.count),
                    Int64(master.services.count)))
                let pubAct = master.publishers
                    .filter {
                        megaActuationShaped($0)
                    }
                let svcAct = master.services
                    .filter {
                        megaActuationShaped($0)
                    }
                for name in pubAct.prefix(8) {
                    icsSay(emit, String(
                        format: L("actuation-shaped topic, claimed by the registry: %@ — printed, never published to"), name), .err)
                }
                for name in svcAct.prefix(8) {
                    icsSay(emit, String(
                        format: L("actuation-shaped service, claimed by the registry: %@ — printed, never invoked"), name), .err)
                }
                if !pubAct.isEmpty
                    || !svcAct.isEmpty {
                    icsSay(emit, L("grade: ROS 1's master keeps no authentication at all — any caller may read this registry, and the registry itself is the map of what the robot can be told to do"), .err)
                }
            } else {
                icsSay(emit, L("door 11311 answers a knock but speaks no XML-RPC this bench can parse — named as a limit, not a posture"), .err)
            }
        } else {
            icsSay(emit, L("no ROS master answers at 11311 — ROS 1's registry is not on this wire for this host"), .out)
        }
        // The bridge.
        if megaDoorOpen(ip: ip, port: 9090,
                        deadline: 0.9) {
            if let bridge = megaBridgeCensus(
                ip: ip, host: host) {
                icsSay(emit, String(
                    format: L("rosbridge answers at 9090 and gave up its census to a query — %lld topics, %lld services, %lld nodes — without asking who was asking"),
                    Int64(bridge.topics.count),
                    Int64(bridge.services.count),
                    Int64(bridge.nodes.count)), .err)
                let act = bridge.topics.filter {
                    megaActuationShaped($0)
                } + bridge.services.filter {
                    megaActuationShaped($0)
                }
                for name in act.prefix(10) {
                    icsSay(emit, String(
                        format: L("actuation-shaped, claimed by the bridge: %@ — printed, never used"), name), .err)
                }
            } else {
                icsSay(emit, L("door 9090 answers a knock but completes no WebSocket handshake this bench can prove — the bridge's posture stays unread"), .err)
            }
        } else {
            icsSay(emit, L("no rosbridge answers at 9090"), .out)
        }
        // The DDS air.
        let dds = megaDDSListen(seconds: 5)
        if !dds.bound {
            icsSay(emit, L("the discovery door (udp 7400) could not be bound — the DDS census is a limit of this room, stated plainly"), .err)
        } else if dds.heard.isEmpty {
            icsSay(emit, L("five seconds on the DDS discovery group: silence — no participant announced. Silence is not proof of absence: another domain, or a quiet wire, hears the same"), .out)
        } else {
            let mine = dds.heard.filter {
                $0.fromIP == ip
                    || $0.locators.contains {
                        $0.hasPrefix(ip + ":")
                    }
            }
            let others = dds.heard.count
                - mine.count
            icsSay(emit, String(
                format: L("DDS discovery: %lld participant(s) heard on the group; %lld of them this host's"),
                Int64(dds.heard.count),
                Int64(mine.count)), .sys)
            for participant in dds.heard {
                megaPrintParticipant(
                    participant,
                    isTarget: mine.contains {
                        $0.guidHex
                            == participant.guidHex
                    },
                    emit: emit)
            }
            if others > 0 {
                icsSay(emit, L("the other participants are the wire's, not this host's — printed because the discovery group is a public square"), .out)
            }
        }
    }

    static func megaPrintParticipant(
        _ p: MegaParticipant,
        isTarget: Bool,
        emit: @escaping BlacksiteEmit) {
        icsSay(emit, String(
            format: L("participant %@ — from %@, RTPS %lld.%lld, stack bytes %@ (this bench's table does not name vendor bytes rather than guess)"),
            String(p.guidHex.prefix(12)),
            p.fromIP,
            Int64(p.protoMajor),
            Int64(p.protoMinor),
            p.vendorRaw),
            isTarget ? .ok : .out)
        for name in p.nameClaims {
            icsSay(emit, String(
                format: L("  it claims %@"), name))
        }
        if !p.locators.isEmpty {
            icsSay(emit, String(
                format: L("  it asks to be reached at %@"),
                p.locators.joined(
                    separator: " · ")))
        }
        if let lease = p.leaseSeconds {
            icsSay(emit, String(
                format: L("  lease %lld s"), Int64(lease)))
        }
        if p.security {
            let sec = p.properties
                .filter {
                    $0.0.hasPrefix("dds.sec.")
                }
                .map { $0.0 }
            icsSay(emit, String(
                format: L("  DDS Security ANNOUNCED: %@ — the participant claims authenticated, access-controlled discovery"),
                sec.joined(separator: " · ")), .ok)
        } else {
            icsSay(emit, L("  no DDS Security properties ride its announcement — discovery is unauthenticated, the DDS default"), .err)
        }
    }

    static func megaROSProbe(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let target = arg
                .split(separator: " ").first
                .map(String.init) ?? ""
            guard !target.isEmpty,
                  let resolved = icsResolve(
                    target, 11311) else {
                icsSay(emit, L("rosprobe: give the robot's host — rosprobe 192.168.1.42"), .err)
                return
            }
            icsSay(emit, String(
                format: L("rosprobe — %@ (%@)"),
                resolved.host, resolved.ip), .sys)
            megaROSSection(
                host: resolved.host,
                ip: resolved.ip, emit: emit)
        }
    }
}

extension BlacksiteBench {

    // MARK: puppetprobe — the plausibility grade
    //
    // Could this unit plausibly be remotely
    // controlled by someone who is not its
    // owner? Answered from READ EVIDENCE
    // ONLY. The final step — a control
    // command actually honored — is NEVER
    // taken by this bench, so no grade here
    // claims proven control. "Plausible"
    // means the road is open as far as the
    // bench is willing to walk it.

    struct MegaADB {
        var banner: String?
        var authDemanded: Bool = false
        var silent: Bool = false
    }

    /// The ADB greeting read: our CNXN
    /// handshake packet, its answer parsed
    /// — the Python-verified framing. A
    /// greeting, never a session: no shell,
    /// no command, no file ever rides it.
    static func megaADBRead(
        ip: String) -> MegaADB? {
        guard let fd = icsSocket(
            ip: ip, port: 5555, timeout: 3)
        else { return nil }
        defer { close(fd) }
        func packet(_ cmd: [UInt8],
                    _ arg0: UInt32,
                    _ arg1: UInt32,
                    _ payload: [UInt8]) -> [UInt8] {
            var sum: UInt32 = 0
            for b in payload { sum &+= UInt32(b) }
            var magic: UInt32 = 0
            for (index, b) in cmd.enumerated() {
                magic |= UInt32(b)
                    << UInt32(index * 8)
            }
            magic = magic ^ 0xFFFFFFFF
            var out = cmd
            for value in [arg0, arg1,
                          UInt32(payload.count),
                          sum, magic] {
                out.append(UInt8(value & 0xFF))
                out.append(UInt8(
                    (value >> 8) & 0xFF))
                out.append(UInt8(
                    (value >> 16) & 0xFF))
                out.append(UInt8(
                    (value >> 24) & 0xFF))
            }
            out.append(contentsOf: payload)
            return out
        }
        let hello = packet(
            [UInt8]("CNXN".utf8), 0x01000000,
            0x100000, [UInt8]("host::\0".utf8))
        var sent = 0
        var ok = true
        while sent < hello.count {
            let n = hello
                .withUnsafeBufferPointer {
                    buffer in
                    send(fd,
                         buffer.baseAddress!
                            + sent,
                         hello.count - sent, 0)
                }
            if n <= 0 { ok = false; break }
            sent += n
        }
        guard ok else { return nil }
        BlacksiteNet.setRecvTimeout(
            fd, seconds: 3)
        var head = [UInt8](
            repeating: 0, count: 24)
        var got = 0
        while got < 24 {
            let n = head
                .withUnsafeMutableBufferPointer {
                    buffer in
                    recv(fd,
                         buffer.baseAddress!
                            + got,
                         24 - got, 0)
                }
            if n <= 0 { break }
            got += n
        }
        guard got == 24 else {
            return MegaADB(silent: true)
        }
        let cmd = String(
            decoding: Array(head[0..<4]),
            as: UTF8.self)
        let arg0 = megaU32LE(head, 4)
        let length = megaU32LE(head, 12)
        var payload: [UInt8] = []
        if length > 0, length < 65536 {
            payload = [UInt8](
                repeating: 0, count: length)
            var read = 0
            while read < length {
                let n = payload
                    .withUnsafeMutableBufferPointer {
                        buffer in
                        recv(fd,
                             buffer.baseAddress!
                                + read,
                             length - read, 0)
                    }
                if n <= 0 { break }
                read += n
            }
            payload = Array(payload[0..<read])
        }
        if cmd == "CNXN" {
            let text = String(
                decoding: payload, as: UTF8.self)
                .replacingOccurrences(
                    of: "\0", with: "")
            return MegaADB(banner: text)
        }
        if cmd == "AUTH" {
            _ = arg0
            return MegaADB(authDemanded: true)
        }
        return MegaADB(silent: true)
    }

    /// The sanctioned anonymous posture
    /// check, first half only: an unnamed
    /// CONNECT, the CONNACK read. (The
    /// subscribe-and-listen half is
    /// mqttprobe's own board.)
    static func megaMQTTAnon(
        ip: String, port: Int) -> Int? {
        guard let fd = icsSocket(
            ip: ip, port: UInt16(port),
            timeout: 3) else {
            return nil
        }
        defer { close(fd) }
        let built = ForgeKit.mqtt(
            clientID: "nightjar-probe")
        guard let connect = try?
            PayloadKit.build(
                source: built.source,
                text: built.text,
                hex: built.text, b64: "",
                xorSpec: "", useGzip: false),
              !connect.isEmpty else {
            return nil
        }
        var sent = 0
        let bytes = [UInt8](connect)
        var ok = true
        while sent < bytes.count {
            let n = bytes
                .withUnsafeBufferPointer {
                    buffer in
                    send(fd,
                         buffer.baseAddress!
                            + sent,
                         bytes.count - sent, 0)
                }
            if n <= 0 { ok = false; break }
            sent += n
        }
        guard ok else { return nil }
        var head = [UInt8](
            repeating: 0, count: 4)
        var got = 0
        while got < 4 {
            let n = recv(fd, &head + got,
                         4 - got, 0)
            if n <= 0 { break }
            got += n
        }
        guard got == 4, head[0] == 0x20 else {
            return nil
        }
        return Int(head[3])
    }

    struct MegaPath {
        var title: String
        var grade: String
        var kind: BlacksiteShell.Line.Kind
        var chain: [String]
    }

    static func megaPuppetProbe(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let target = arg
                .split(separator: " ").first
                .map(String.init) ?? ""
            guard !target.isEmpty,
                  let resolved = icsResolve(
                    target, 80) else {
                icsSay(emit, L("puppetprobe: give the unit's host — puppetprobe 192.168.1.42"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            icsSay(emit, String(
                format: L("puppetprobe — %@ (%@): could this unit plausibly be puppeteered by a stranger? Graded from read evidence only"),
                host, ip), .sys)
            let open = megaDoorScan(
                ip: ip, doors: megaDoors)
            var paths: [MegaPath] = []
            // rosbridge.
            if open.contains(9090) {
                if let bridge = megaBridgeCensus(
                    ip: ip, host: host) {
                    let act = bridge.topics
                        .filter {
                            megaActuationShaped($0)
                        }
                        + bridge.services
                            .filter {
                                megaActuationShaped($0)
                            }
                    var chain = [
                        L("door 9090 (rosbridge) answers"),
                        L("the bridge gave its rosapi census to a query without asking who was asking — no authentication stood on the query road"),
                    ]
                    if act.isEmpty {
                        chain.append(L("no actuation-shaped topic or service stands in the census — the road is open but nothing at its end is shaped like a command"))
                        paths.append(MegaPath(
                            title: L("the rosbridge road"),
                            grade: L("unlikely"),
                            kind: .out,
                            chain: chain))
                    } else {
                        chain.append(String(
                            format: L("the census itself names actuation-shaped roads: %@"),
                            act.prefix(4).joined(
                                separator: " · ")))
                        chain.append(L("rosbridge, unauthenticated, is a publish/subscribe square: a stranger's client is the protocol working as designed"))
                        paths.append(MegaPath(
                            title: L("the rosbridge road"),
                            grade: L("PLAUSIBLE"),
                            kind: .err,
                            chain: chain))
                    }
                } else {
                    paths.append(MegaPath(
                        title: L("the rosbridge road"),
                        grade: L("no path seen"),
                        kind: .out,
                        chain: [L("door 9090 answers a knock but completes no provable WebSocket handshake — its manners stay unread")]))
                }
            }
            // The ROS master.
            if open.contains(11311) {
                if let master = megaMasterRead(
                    ip: ip) {
                    let act = master.services
                        .filter {
                            megaActuationShaped($0)
                        }
                        + master.publishers
                            .filter {
                                megaActuationShaped($0)
                            }
                    var chain = [
                        L("door 11311 (the ROS master) answers registry queries from any caller — ROS 1's design carries no authentication"),
                    ]
                    if act.isEmpty {
                        chain.append(L("the registry names no actuation-shaped service or topic — the map is public but shows no command road"))
                        paths.append(MegaPath(
                            title: L("the ROS master road"),
                            grade: L("unlikely"),
                            kind: .out,
                            chain: chain))
                    } else {
                        chain.append(String(
                            format: L("the registry names actuation-shaped roads: %@"),
                            act.prefix(4).joined(
                                separator: " · ")))
                        paths.append(MegaPath(
                            title: L("the ROS master road"),
                            grade: L("PLAUSIBLE"),
                            kind: .err,
                            chain: chain))
                    }
                }
            }
            // DDS.
            let dds = megaDDSListen(seconds: 4)
            if dds.bound {
                let mine = dds.heard.filter {
                    $0.fromIP == ip
                        || $0.locators.contains {
                            $0.hasPrefix(ip + ":")
                        }
                }
                if let participant = mine.first {
                    var chain = [
                        L("the unit announces itself on the DDS discovery group — its endpoints are public claims"),
                    ]
                    if participant.security {
                        chain.append(L("its announcement carries DDS Security properties — authenticated discovery is claimed, and unauthenticated publication is refused by design"))
                        paths.append(MegaPath(
                            title: L("the DDS road"),
                            grade: L("unlikely"),
                            kind: .out,
                            chain: chain))
                    } else {
                        chain.append(L("no DDS Security properties ride its announcement — DDS without its security plugins authenticates no publisher: any participant on the wire may speak, and subscribers cannot tell a stranger's voice from the owner's"))
                        paths.append(MegaPath(
                            title: L("the DDS road"),
                            grade: L("PLAUSIBLE"),
                            kind: .err,
                            chain: chain))
                    }
                }
            }
            // ADB.
            if open.contains(5555) {
                if let adb = megaADBRead(ip: ip) {
                    if let banner = adb.banner {
                        var chain = [
                            L("door 5555 (ADB) answers the greeting with its own banner — no key was demanded"),
                        ]
                        let claims = banner
                            .split(separator: ";")
                            .map(String.init)
                            .filter {
                                $0.hasPrefix(
                                    "ro.product")
                            }
                        for claim in claims
                            .prefix(3) {
                            chain.append(String(
                                format: L("it claims %@"),
                                claim))
                        }
                        chain.append(L("ADB is a shell protocol: a completed greeting is a command line on the device. Nothing past the greeting was read, and no command was sent"))
                        paths.append(MegaPath(
                            title: L("the ADB road"),
                            grade: L("PLAUSIBLE"),
                            kind: .err,
                            chain: chain))
                    } else if adb.authDemanded {
                        paths.append(MegaPath(
                            title: L("the ADB road"),
                            grade: L("unlikely"),
                            kind: .out,
                            chain: [L("door 5555 answers but demands an RSA key's signature before any banner — the greeting stops at the locked door")]))
                    } else {
                        paths.append(MegaPath(
                            title: L("the ADB road"),
                            grade: L("no path seen"),
                            kind: .out,
                            chain: [L("door 5555 answers a knock but says nothing in the greeting window")]))
                    }
                }
            }
            // Brokers.
            for port in [1883] where
                open.contains(port) {
                if let code = megaMQTTAnon(
                    ip: ip, port: port) {
                    if code == 0 {
                        paths.append(MegaPath(
                            title: L("the broker road"),
                            grade: L("PLAUSIBLE"),
                            kind: .err,
                            chain: [
                                L("the MQTT broker accepted an unnamed CONNECT — no credential was asked"),
                                L("machines that take their orders as broker topics take them from whoever may publish; an open broker is an open square (what it tells guests is mqttprobe's own board)"),
                            ]))
                    } else {
                        paths.append(MegaPath(
                            title: L("the broker road"),
                            grade: L("unlikely"),
                            kind: .out,
                            chain: [L("the MQTT broker refused the unnamed guest — a name is demanded at the door")]))
                    }
                }
            }
            if open.contains(8883) {
                paths.append(MegaPath(
                    title: L("the broker road (tls)"),
                    grade: L("no path seen"),
                    kind: .out,
                    chain: [L("the encrypted broker door (8883) answers — its guest policy rides inside TLS and is not read here; the plain door's manners, if any, are graded above")]))
            }
            // Web consoles.
            let consoles = open.filter {
                $0 == 80 || $0 == 8080
                    || $0 == 3000 || $0 == 443
                    || $0 == 8443
            }
            if !consoles.isEmpty {
                var chain: [String] = []
                var walled = false
                var named = false
                for port in consoles {
                    let plate = megaWebNameplate(
                        host: host, port: port)
                    if let title = plate.title,
                       !title.isEmpty {
                        named = true
                        chain.append(String(
                            format: L("door %lld introduces itself: %@"),
                            Int64(port), title))
                        let lower = title
                            .lowercased()
                        if lower.contains("login")
                            || lower.contains(
                                "sign in") {
                            walled = true
                        }
                    }
                }
                if chain.isEmpty {
                    chain.append(L("web doors answer but introduce nothing — no console surface is claimed"))
                }
                paths.append(MegaPath(
                    title: L("the console road"),
                    grade: (named && !walled)
                        ? L("PLAUSIBLE")
                        : L("unlikely"),
                    kind: (named && !walled)
                        ? .err : .out,
                    chain: chain + [
                        walled
                            ? L("a login wall is the surface's own claim — the road stops at a demanded name")
                            : L("no login wall was seen in what the doors introduced — a console that shows its face to strangers is graded on that face"),
                    ]))
            }
            // The board.
            if paths.isEmpty {
                icsSay(emit, L("no control-bearing surface answered at all — no path seen, on this wire, today"), .ok)
            }
            for path in paths {
                icsSay(emit, String(
                    format: L("%@: %@"),
                    path.title, path.grade),
                    path.kind)
                for step in path.chain {
                    icsSay(emit, "  → " + step)
                }
            }
            let grades = megaGrades(
                MegaEvidence(
                    host: host, ip: ip, open: open))
            if grades.contains(where: {
                $0.family.contains("machinery")
                    || $0.family.contains(
                        "plant")
                    || $0.family.contains("arm")
            }) {
                icsSay(emit, L("the stakes, plainly: things that can move can hurt people. That is exactly why this bench grades the road and never walks it"), .err)
            }
            icsSay(emit, L("THE HONESTY RULE: plausibility is argued from evidence. The final step — a control command actually honored — is NEVER taken by this bench, so no grade here claims proven control. 'Plausible' means the road is open as far as the bench is willing to walk it"), .sys)
        }
    }

    // MARK: cyberprobe — the vehicles

    static func megaCyberProbe(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let target = arg
                .split(separator: " ").first
                .map(String.init) ?? ""
            guard !target.isEmpty,
                  let resolved = icsResolve(
                    target, 443) else {
                icsSay(emit, L("cyberprobe: give the vehicle's host — cyberprobe 192.168.1.42"), .err)
                return
            }
            let host = resolved.host
            let ip = resolved.ip
            icsSay(emit, String(
                format: L("cyberprobe — %@ (%@): the vehicle read"),
                host, ip), .sys)
            let vehicleDoors = [22, 80, 443,
                                3000, 8080, 8443,
                                8883]
            let ev = megaGather(
                host: host, ip: ip,
                doors: vehicleDoors)
            if ev.open.isEmpty {
                icsSay(emit, L("the vehicle presents no doors on this wire — a parked Tesla is a quiet radio; what it says, it says to its maker's cloud"), .out)
            } else {
                let named = ev.open.map {
                    "\(megaDoorNames[$0] ?? "door") \($0)"
                }
                icsSay(emit, String(
                    format: L("doors answering: %@"),
                    named.joined(
                        separator: " · ")))
            }
            for port in ev.banners.keys.sorted() {
                if let banner = ev.banners[port] {
                    icsSay(emit, String(
                        format: L("door %lld says: %@"),
                        Int64(port), banner))
                }
            }
            megaPrintGrades(ev, emit: emit)
            megaFleetSection(
                host: host, ip: ip,
                open: ev.open, emit: emit)
            icsSay(emit, L("remote control — the plausibility section"), .sys)
            icsSay(emit, L("the app road: a Tesla takes its owner's commands through the maker's cloud, signed by keys this wire never sees. Nothing on the local wire speaks for that road, and no door this vehicle answered offers a command surface to strangers — grade for this wire: no path seen"), .out)
            icsSay(emit, L("the key road: the phone key is Bluetooth, and its posture is the air's — botble reads what the air claims. A relay attempt is an attack, not an assessment, and is never made by this bench"), .out)
            icsSay(emit, L("the diagnostic road: no diagnostic write was made and no CAN frame was originated — this bench reads presented surfaces only, and a vehicle's service doors are read as nameplates or not at all"), .out)
            icsSay(emit, L("THE HONESTY RULE: plausibility is argued from evidence; the final step is never taken, so no grade here claims proven control"), .sys)
        }
    }

    // MARK: voltprobe — the energy gear

    static func megaVoltProbe(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let target = arg
            .split(separator: " ").first
            .map(String.init) ?? ""
        guard !target.isEmpty,
              let resolved = icsResolve(
                target, 443) else {
            icsSay(emit, L("voltprobe: give the gateway's host — voltprobe 192.168.1.42"), .err)
            done()
            return
        }
        BlacksitePentest.run {
            let host = resolved.host
            let ip = resolved.ip
            icsSay(emit, String(
                format: L("voltprobe — %@ (%@): the energy read"),
                host, ip), .sys)
            let energyDoors = [22, 80, 443,
                               502, 4840, 8080,
                               8443]
            let ev = megaGather(
                host: host, ip: ip,
                doors: energyDoors)
            if ev.open.isEmpty {
                icsSay(emit, L("no energy door answers — the gateway keeps its own counsel on this wire"), .err)
            } else {
                let named = ev.open.map {
                    "\(megaDoorNames[$0] ?? "door") \($0)"
                }
                icsSay(emit, String(
                    format: L("doors answering: %@"),
                    named.joined(
                        separator: " · ")))
            }
            for port in ev.banners.keys.sorted() {
                if let banner = ev.banners[port] {
                    icsSay(emit, String(
                        format: L("door %lld says: %@"),
                        Int64(port), banner))
                }
            }
            megaPrintGrades(ev, emit: emit)
            megaFleetSection(
                host: host, ip: ip,
                open: ev.open, emit: emit)
            icsSay(emit, L("nameplates only: no setting was touched and no charge command exists in this bench's hands — the energy gear is read, never driven"), .out)
            if ev.open.contains(502)
                || ev.open.contains(4840) {
                icsSay(emit, L("voltprobe — the plant nameplate, by the ICS bench:"), .sys)
                benchICS(
                    "plcensus", host,
                    emit: emit, done: done)
                return
            }
            done()
        }
    }

    // MARK: boreprobe — the drills and the tunnel plant

    static func megaBoreProbe(
        _ arg: String,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        let target = arg
            .split(separator: " ").first
            .map(String.init) ?? ""
        guard !target.isEmpty,
              icsResolve(target, 502) != nil
        else {
            icsSay(emit, L("boreprobe: give the plant's host — boreprobe 192.168.1.42"), .err)
            done()
            return
        }
        icsSay(emit, String(
            format: L("boreprobe — %@: the boring plant read, by the ICS bench. Identification and posture only — the ICS line verbatim: no writes, no control function codes, ever"),
            target), .sys)
        typealias Step =
            (@escaping BlacksiteEmit,
             @escaping () -> Void) -> Void
        var steps: [Step] = []
        func ics(_ verb: String) {
            steps.append { e, d in
                BlacksiteBench.benchICS(
                    verb, target,
                    emit: e, done: d)
            }
        }
        ics("plcensus")
        ics("modbusprobe")
        ics("s7probe")
        ics("enipprobe")
        ics("opcuaprobe")
        ics("bacnetprobe")
        ics("iec104probe")
        steps.append { e, d in
            icsSay(e, L("boreprobe — the grade, the ICS way: control plausibility is read off anonymous answers on control-bearing doors, never off a write. A plant door that names itself to strangers and asks no credential is graded on that answer; the bench does not walk through it"), .sys)
            icsSay(e, L("the stakes, plainly: a boring machine is tons of turning steel. This bench reads its nameplates and grades its doors — it does not so much as knock toward a control"), .err)
            d()
        }
        megaChain(steps, 0, emit: emit,
                  done: done)
    }
}

extension BlacksiteBench {

    // MARK: primecensus — the hunt

    struct MegaClaim {
        var ip: String
        var open: [Int]
        var grades: [MegaGrade]
        var flagship: Bool
    }

    /// The hunt itself: sweep the /24 on
    /// the machine doors, fold in what the
    /// house already knows, listen to the
    /// two machine airs (DDS, MAVLink), and
    /// grade every candidate. Prints the
    /// board; returns the claimed units.
    static func megaHunt(
        prefix: String,
        emit: @escaping BlacksiteEmit)
        -> [MegaClaim] {
        icsSay(emit, String(
            format: L("primecensus — hunting %@.0/24 for machine-shaped presence"),
            prefix), .sys)
        let huntDoors = [11311, 9090, 5555,
                         1883, 502, 80, 443]
        var found: [String: [Int]] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        let sem = DispatchSemaphore(value: 40)
        for octet in 1...254 {
            let ip = "\(prefix).\(octet)"
            group.enter()
            DispatchQueue.global().async {
                sem.wait()
                let open = huntDoors.filter {
                    megaDoorOpen(ip: ip,
                                 port: $0,
                                 deadline: 0.35)
                }
                if !open.isEmpty {
                    lock.lock()
                    found[ip] = open
                    lock.unlock()
                }
                sem.signal()
                group.leave()
            }
        }
        group.wait()
        // The house's own knowledge of the
        // same wire joins the hunt.
        for neighbor in NeighborhoodStore
            .shared.neighbors
        where neighbor.ip.hasPrefix(
            prefix + ".") {
            if found[neighbor.ip] == nil,
               !neighbor.ports.isEmpty {
                found[neighbor.ip] =
                    neighbor.ports.filter {
                        huntDoors.contains($0)
                    }
            }
        }
        // The two airs.
        let mav = megaMAVListen(seconds: 4)
        var mavByIP: [String: [MegaHeartbeat]]
            = [:]
        for beat in mav where beat.crcOK {
            mavByIP[beat.fromIP, default: []]
                .append(beat)
        }
        let dds = megaDDSListen(seconds: 5)
        var ddsIPs = Set<String>()
        for participant in dds.heard {
            ddsIPs.insert(participant.fromIP)
            for locator in participant.locators {
                if let ipPart = locator
                    .split(separator: ":")
                    .first {
                    ddsIPs.insert(String(ipPart))
                }
            }
        }
        var claims: [MegaClaim] = []
        let candidates = Set(found.keys)
            .union(mavByIP.keys)
            .union(ddsIPs)
        for ip in candidates.sorted(
            by: {
                BlacksiteNet.ipSortKey($0)
                    .lexicographicallyPrecedes(
                        BlacksiteNet.ipSortKey($1))
            }) {
            var ev = MegaEvidence(
                host: ip, ip: ip,
                open: found[ip] ?? [])
            ev.ptr = megaPTRName(ip)
            if let neighbor = NeighborhoodStore
                .shared.neighbors.first(
                    where: { $0.ip == ip }) {
                ev.neighborName = neighbor.name
                ev.announcements =
                    neighbor.announcements
            }
            var grades = megaGrades(ev)
            func boost(_ family: String,
                       _ weight: Int,
                       _ reason: String) {
                if let index = grades
                    .firstIndex(where: {
                        $0.family == family
                    }) {
                    grades[index].score += weight
                    grades[index].reasons
                        .append(reason)
                } else {
                    grades.append(MegaGrade(
                        family: family,
                        score: weight,
                        reasons: [reason]))
                }
            }
            if let beats = mavByIP[ip] {
                let kinds = beats.map {
                    megaMAVTypeName(
                        $0.vehicleType)
                }
                boost("drone / ground station",
                      3,
                      String(format: L("it speaks MAVLink heartbeats — %@, checksummed and read"),
                             kinds.joined(
                                separator: " · ")))
            }
            if ddsIPs.contains(ip) {
                boost("ros robot (maker unnamed)",
                      3,
                      L("it announces itself on the DDS discovery group — a ROS 2 citizen"))
            }
            grades.sort { $0.score > $1.score }
            let claim = MegaClaim(
                ip: ip, open: ev.open,
                grades: grades,
                flagship: megaIsFlagship(grades))
            claims.append(claim)
            // The board line for this unit.
            var head = ip
            if let ptr = ev.ptr {
                head += " (\(ptr))"
            }
            if claim.flagship {
                icsSay(emit, String(
                    format: L("%@ — FLAGSHIP PREY"),
                    head), .err)
            } else {
                icsSay(emit, head, .sys)
            }
            if !ev.open.isEmpty {
                let named = ev.open.map {
                    "\(megaDoorNames[$0] ?? "door") \($0)"
                }
                icsSay(emit, String(
                    format: L("  doors: %@"),
                    named.joined(
                        separator: " · ")))
            }
            if grades.isEmpty {
                icsSay(emit, L("  machine doors answer but nothing names a family — recorded unnamed"), .out)
            }
            for grade in grades {
                icsSay(emit, String(
                    format: L("  claim: %@ — %@"),
                    grade.family, grade.word))
                for reason in grade.reasons {
                    icsSay(emit, "    · " + reason)
                }
            }
        }
        if claims.isEmpty {
            icsSay(emit, L("the wire is quiet: no machine-shaped presence answered the hunt on this /24 — silence is a reading, not a proof of absence"), .out)
        } else {
            let flagshipCount = claims.filter {
                $0.flagship
            }.count
            icsSay(emit, String(
                format: L("primecensus: %lld machine-shaped unit(s) on this wire, %lld of them flagship prey"),
                Int64(claims.count),
                Int64(flagshipCount)), .sys)
        }
        icsSay(emit, L("limits: the hunt knocks the machine doors on this /24 and listens to the DDS and MAVLink airs for a few seconds each. A unit with its doors shut and its radios quiet is not seen — the board claims only what answered"), .out)
        return claims
    }

    static func megaPrimeCensus(
        _ arg: String?, file: Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let prefix: String
            if let arg = arg, !arg.isEmpty {
                let parts = arg
                    .split(separator: ".")
                if parts.count >= 3 {
                    prefix = parts[0..<3]
                        .joined(separator: ".")
                } else {
                    icsSay(emit, L("primecensus: give a prefix — primecensus 192.168.1 — or nothing for this wire"), .err)
                    return
                }
            } else if let own = BlacksiteNet
                .primaryIPv4() {
                prefix = own
                    .split(separator: ".")
                    [0..<3]
                    .joined(separator: ".")
            } else {
                icsSay(emit, L("primecensus: this phone has no wire address to hunt from"), .err)
                return
            }
            _ = megaHunt(prefix: prefix,
                         emit: emit)
            _ = file
        }
    }

    // MARK: megatron — the marquee

    static func megaMarquee(
        _ arg: String?,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        // The board is filed like eazy's:
        // every line is collected as it is
        // spoken, then handed to Deliveries.
        let lock = NSLock()
        var lines: [(String,
                      BlacksiteShell.Line.Kind)]
            = []
        let collect: BlacksiteEmit = {
            text, kind in
            lock.lock()
            lines.append((text, kind))
            lock.unlock()
            emit(text, kind)
        }
        func finish(_ label: String) {
            lock.lock()
            let board = lines
            lock.unlock()
            guard !board.isEmpty else {
                done()
                return
            }
            let findings = board.filter {
                $0.1 == .err
            }.count
            DeliveriesCenter.shared.add(
                name: String(
                    format: L("megatron — %@"),
                    label),
                text: board.map { $0.0 }
                    .joined(separator: "\n"),
                ext: "txt")
            emit(String(
                format: L("megatron: the hunt is filed — %lld findings across the boards. The full record is in Deliveries"),
                Int64(findings)),
                findings > 0 ? .err : .ok)
            done()
        }
        typealias Step =
            (@escaping BlacksiteEmit,
             @escaping () -> Void) -> Void
        func batterySteps(
            _ host: String) -> [Step] {
            var steps: [Step] = []
            steps.append { e, d in
                icsSay(e, String(
                    format: L("megatron — the battery on %@"),
                    host), .sys)
                d()
            }
            steps.append { e, d in
                megaBotDoors(host, emit: e,
                             done: d)
            }
            steps.append { e, d in
                megaProbeVerb(
                    host, optimus: false,
                    emit: e, done: d)
            }
            steps.append { e, d in
                megaFleetVerb(host, emit: e,
                              done: d)
            }
            steps.append { e, d in
                megaROSProbe(host, emit: e,
                             done: d)
            }
            steps.append { e, d in
                megaPuppetProbe(host, emit: e,
                                done: d)
            }
            return steps
        }
        if let target = arg?
            .split(separator: " ").first
            .map(String.init), !target.isEmpty {
            guard icsResolve(target, 80)
                != nil else {
                icsSay(collect, L("megatron: that target does not resolve from here — nothing to hunt"), .err)
                finish(target)
                return
            }
            var steps = batterySteps(target)
            steps.append { e, d in
                // A dish at the target rides
                // the satellite wave's own
                // read, by name.
                if let resolved = icsResolve(
                    target, 80),
                   megaDoorOpen(
                    ip: resolved.ip, port: 9200,
                    deadline: 0.5)
                    || target.lowercased()
                        .contains("starlink")
                    || target == "192.168.100.1" {
                    icsSay(e, L("megatron — the dish's own read, by the satellite bench:"), .sys)
                    benchSat(
                        "starlinkprobe", target,
                        emit: e, done: d)
                    return
                }
                d()
            }
            megaChain(steps, 0, emit: collect) {
                finish(target)
            }
            return
        }
        // Bare: hunt, then board every
        // claimed unit (the first six — a
        // wire richer than that gets its
        // census board and a stated limit).
        BlacksitePentest.run {
            guard let own = BlacksiteNet
                .primaryIPv4() else {
                icsSay(collect, L("megatron: this phone has no wire address to hunt from"), .err)
                finish("the wire")
                return
            }
            let prefix = own
                .split(separator: ".")[0..<3]
                .joined(separator: ".")
            let claims = megaHunt(
                prefix: prefix, emit: collect)
            var steps: [Step] = []
            let units = claims.prefix(6)
            for claim in units {
                steps += batterySteps(claim.ip)
            }
            if claims.count > units.count {
                steps.append { e, d in
                    icsSay(e, String(
                        format: L("megatron: %lld further claimed unit(s) stand on the census board above — six batteries is this run's magazine; name one to board it whole"),
                        Int64(claims.count
                            - units.count)), .err)
                    d()
                }
            }
            if claims.isEmpty {
                finish("the wire")
                return
            }
            megaChain(steps, 0, emit: collect) {
                finish("the wire")
            }
        }
    }

    // MARK: botble — the Bluetooth air, graded for robots

    static func megaBotBLE(
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            let scanner = MegaBLEScanner()
            scanner.begin()
            _ = scanner.gate.wait(
                timeout: .now() + 10.0)
            scanner.stop()
            switch scanner.finalState {
            case .poweredOff:
                icsSay(emit, L("botble: Bluetooth is off — the ear is closed"), .err)
                return
            case .unauthorized:
                icsSay(emit, L("botble: Bluetooth is not permitted for this app — the ear is closed"), .err)
                return
            case .unsupported:
                icsSay(emit, L("botble: this device has no Bluetooth LE ear to listen with"), .err)
                return
            default:
                break
            }
            let heard = scanner.collected()
            icsSay(emit, L("botble — eight seconds of the Bluetooth air, listened to only"), .sys)
            if heard.isEmpty {
                icsSay(emit, L("nothing advertised within reach in the window"), .out)
                return
            }
            var robotClaims = 0
            var continuity = 0
            var trackers = 0
            var other = 0
            for adv in heard {
                if adv.company == 0x004C,
                   adv.isFindMy {
                    trackers += 1
                    continue
                }
                if adv.company == 0x004C {
                    continuity += 1
                    continue
                }
                let name = adv.name ?? ""
                let ev = MegaEvidence(
                    host: name, ip: "",
                    neighborName: adv.name)
                var grades = megaGrades(ev)
                grades = grades.filter {
                    $0.score >= 2
                }
                if !name.isEmpty,
                   !grades.isEmpty {
                    robotClaims += 1
                    let top = grades[0]
                    icsSay(emit, String(
                        format: L("%@ — claim: %@ (%@) · rssi %lld"),
                        name, top.family,
                        top.word,
                        Int64(adv.rssi)), .ok)
                    for reason in top.reasons {
                        icsSay(emit, "  · "
                            + reason)
                    }
                } else {
                    other += 1
                }
            }
            icsSay(emit, String(
                format: L("botble: %lld advertiser(s) heard — %lld robot-shaped claim(s), %lld Apple continuity (the phone-and-earbud weather, separated), %lld tracker-shaped (FindMy), %lld other or unnamed"),
                Int64(heard.count),
                Int64(robotClaims),
                Int64(continuity),
                Int64(trackers),
                Int64(other)), .sys)
            icsSay(emit, L("listen-only: nothing was transmitted, paired or connected. An advertiser's name is its own claim — graded as a claim, never proof"), .out)
        }
    }
}

// MARK: - the Bluetooth ear (file scope)
//
// botble's own bounded listener, ridprobe's
// shape: an eight-second passive scan for
// every advertiser, names and maker marks
// kept. Receive-only by construction: it
// never connects, never pairs, and stops
// on its own.

private final class MegaBLEScanner:
    NSObject, CBCentralManagerDelegate {

    struct Advert {
        var name: String?
        var company: UInt16?
        var isFindMy: Bool
        var rssi: Int
    }

    private var manager: CBCentralManager?
    private let queue = DispatchQueue(
        label: "blacksite.megatron.ble")
    let gate = DispatchSemaphore(value: 0)
    private var finished = false
    private(set) var finalState:
        CBManagerState = .unknown
    private var byPeripheral:
        [String: Advert] = [:]

    func begin() {
        manager = CBCentralManager(
            delegate: self, queue: queue)
        queue.asyncAfter(
            deadline: .now() + 9.5) {
            [weak self] in
            self?.finish()
        }
    }

    func stop() {
        manager?.stopScan()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        if let manager = manager {
            finalState = manager.state
        }
        manager?.stopScan()
        gate.signal()
    }

    func collected() -> [Advert] {
        queue.sync {
            byPeripheral.values.sorted {
                ($0.name ?? "")
                    < ($1.name ?? "")
            }
        }
    }

    func centralManagerDidUpdateState(
        _ central: CBCentralManager) {
        finalState = central.state
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(
                withServices: nil,
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey:
                        true])
            queue.asyncAfter(
                deadline: .now() + 8.0) {
                [weak self] in
                self?.finish()
            }
        case .poweredOff, .unauthorized,
             .unsupported:
            finish()
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber) {
        let key = peripheral.identifier
            .uuidString
        var name = advertisementData[
            CBAdvertisementDataLocalNameKey]
            as? String
        if name == nil {
            name = peripheral.name
        }
        var company: UInt16? = nil
        var isFindMy = false
        if let mfr = advertisementData[
            CBAdvertisementDataManufacturerDataKey]
            as? Data, mfr.count >= 2 {
            let bytes = [UInt8](mfr)
            company = UInt16(bytes[0])
                | (UInt16(bytes[1]) << 8)
            if company == 0x004C,
               bytes.count > 2,
               bytes[2] == 0x19 {
                isFindMy = true
            }
        }
        let rssi = RSSI.intValue
        if let existing = byPeripheral[key] {
            var merged = existing
            if merged.name == nil {
                merged.name = name
            }
            if merged.company == nil {
                merged.company = company
            }
            merged.isFindMy = merged.isFindMy
                || isFindMy
            merged.rssi = max(merged.rssi, rssi)
            byPeripheral[key] = merged
        } else {
            byPeripheral[key] = Advert(
                name: name, company: company,
                isFindMy: isFindMy, rssi: rssi)
        }
    }
}
