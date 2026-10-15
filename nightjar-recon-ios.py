#!/usr/bin/env python3
"""nightjar-hack recon for iOS - one file, installs itself and zips the result.

    python3 nightjar-recon-ios.py                 # install + write the zip
    python3 nightjar-recon-ios.py --check         # report only, no writes
    python3 nightjar-recon-ios.py --zip-only      # only rewrite the zip

Adds a Recon tab to the iOS app - knock, connect, fuzz, over a wire-exact
protocol library - and the same library to the Python CLI for parity.
New Swift files land in ios/nightjar/ (the synchronized folder picks them
up: no .xcodeproj edit). ContentView.swift gets one tab. The zip mirrors
repo paths, so extracting it over the repo replaces exactly the right
files. Idempotent; existing files are backed up to *.orig.
"""

from __future__ import annotations

import argparse
import shutil
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ZIP_NAME = "nightjar-recon-ios.zip"


# =============================================================================
# ios/nightjar/ReconPayloads.swift
# =============================================================================

RECON_PAYLOADS_SWIFT = r'''import Foundation

/// Wire-exact protocol first words.
///
/// The first thing a client says to a service: the bytes that make a
/// stranger introduce itself. `Recon.knock` speaks the right one at every
/// open port; `ReconBenchView` hands one to the Send tab in a tap.
///
/// Server-first protocols (ssh, mysql) carry an empty probe: the knocker
/// just listens. Every length, offset and BER/BSON/TLV envelope is
/// computed rather than remembered.

enum ReconError: Error, CustomStringConvertible {
    case unknownProbe(String, [String])

    var description: String {
        switch self {
        case .unknownProbe(let name, let near):
            let hint = near.isEmpty ? "" : " (did you mean \(near.joined(separator: ", "))?)"
            return "no preset '\(name)'\(hint)"
        }
    }
}

struct ReconProbe {
    let name: String
    let port: Int
    let udp: Bool
    let tls: Bool
    let family: String
    /// Bytes that mean "that really was the service" — empty means
    /// any reply confirms.
    let hint: Data
    let summary: String
    let build: () -> Data
}

enum ReconPayloads {

    // MARK: - encoders

    static func u16(_ value: Int) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    static func u32be(_ value: Int) -> Data {
        Data([UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
              UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    static func u64be(_ value: Int) -> Data {
        u32be(value >> 32) + u32be(value & 0xFFFF_FFFF)
    }

    static func le32(_ value: Int) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
              UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)])
    }

    static func u64le(_ value: Int) -> Data {
        le32(value & 0xFFFF_FFFF) + le32(value >> 32)
    }

    static func hx(_ text: String) -> Data {
        var out = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex)
                ?? text.endIndex
            if let byte = UInt8(text[index..<next], radix: 16) { out.append(byte) }
            index = next
        }
        return out
    }

    static func berLen(_ size: Int) -> Data {
        if size < 0x80 { return Data([UInt8(size)]) }
        var out = Data()
        var value = size
        while value > 0 { out.insert(UInt8(value & 0xFF), at: 0); value >>= 8 }
        return Data([0x80 | UInt8(out.count)]) + out
    }

    static func ber(_ tag: UInt8, _ payload: Data) -> Data {
        Data([tag]) + berLen(payload.count) + payload
    }

    static func berInt(_ value: Int) -> Data {
        if value == 0 { return ber(0x02, Data([0x00])) }
        var out = Data()
        var v = value
        while v > 0 { out.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        if out[0] & 0x80 != 0 { out.insert(0x00, at: 0) }
        return ber(0x02, out)
    }

    static func berBase128(_ value: Int) -> Data {
        var chunks: [UInt8] = [UInt8(value & 0x7F)]
        var v = value >> 7
        while v > 0 { chunks.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        return Data(chunks.reversed())
    }

    static func berOID(_ dotted: String) -> Data {
        let parts = dotted.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return ber(0x06, Data()) }
        var body = Data([UInt8(40 * parts[0] + parts[1])])
        for part in parts.dropFirst(2) { body += berBase128(part) }
        return ber(0x06, body)
    }

    static func resp(_ parts: [String]) -> Data {
        var out = Data("*\(parts.count)\r\n".utf8)
        for part in parts { out += Data("$\(part.utf8.count)\r\n\(part)\r\n".utf8) }
        return out
    }

    static func mqttStr(_ text: String) -> Data { u16(text.utf8.count) + Data(text.utf8) }

    static func mqttRemaining(_ size: Int) -> Data {
        var out = Data()
        var value = size
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            out.append(byte)
        } while value > 0
        return out
    }

    static func dnsName(_ name: String) -> Data {
        var out = Data()
        let trimmed = name.hasSuffix(".") ? String(name.dropLast()) : name
        for label in trimmed.split(separator: ".") {
            let raw = Data(String(label).utf8)
            out.append(UInt8(raw.count))
            out += raw
        }
        out.append(0)
        return out
    }

    /// NetBIOS first-level encoding: 16 characters, each split into two
    /// nibbles offset by 'A'. "*" pads with spaces, which is 0x2A.
    static func nbtName(_ name: String = "*") -> Data {
        var padded: [UInt8]
        if name == "*" {
            padded = [0x2A] + Array(repeating: 0x20, count: 15)
        } else {
            var bytes = Array(name.uppercased().utf8).prefix(16)
            while bytes.count < 16 { bytes.append(0x20) }
            padded = Array(bytes)
        }
        var out = Data([0x20])
        for char in padded {
            out.append(UInt8(0x41 + (char >> 4)))
            out.append(UInt8(0x41 + (char & 0x0F)))
        }
        out.append(0)
        return out
    }

    static func http(_ method: String, _ path: String, host: String = "localhost",
                     headers: [(String, String)] = [], body: Data = Data()) -> Data {
        var lines = ["\(method) \(path) HTTP/1.1", "Host: \(host)",
                     "User-Agent: nightjar", "Accept: */*"]
        if !body.isEmpty { lines.append("Content-Length: \(body.count)") }
        for (key, value) in headers { lines.append("\(key): \(value)") }
        lines.append("Connection: close")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
    }

    static func bsonInt32(_ doc: [(String, Int)]) -> Data {
        var body = Data()
        for (key, value) in doc {
            body.append(0x10)
            body += Data(key.utf8)
            body.append(0)
            body += le32(value)
        }
        let size = 4 + body.count + 1
        return le32(size) + body + Data([0])
    }

    // MARK: - builders

    static let qtypes: [String: Int] = ["A": 1, "NS": 2, "CNAME": 5, "SOA": 6,
                                        "PTR": 12, "MX": 15, "TXT": 16,
                                        "AAAA": 28, "SRV": 33, "ANY": 255]
    static let qclasses: [String: Int] = ["IN": 1, "CH": 3, "HS": 4]

    static func dnsQuery(_ name: String, _ qtype: String = "A",
                         _ qclass: String = "IN", rd: Bool = true,
                         edns: Bool = true) -> Data {
        var out = u16(0x1234)
        out += u16(rd ? 0x0100 : 0x0000)
        out += u16(1); out += u16(0); out += u16(0); out += u16(edns ? 1 : 0)
        out += dnsName(name)
        out += u16(qtypes[qtype] ?? 1)
        out += u16(qclasses[qclass] ?? 1)
        if edns {
            out.append(0)             // root name
            out += u16(41)            // OPT
            out += u16(4096)          // UDP payload size
            out += u32be(0)           // extended rcode + flags
            out += u16(0)             // RDLEN
        }
        return out
    }

    static func nbnsQuery() -> Data {
        var out = Data([0x12, 0x34, 0x00, 0x00, 0x00, 0x01,
                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        out += nbtName()
        out += u16(0x0021)
        out += u16(0x0001)
        return out
    }

    static func ntpRequest() -> Data { Data([0x1B]) + Data(repeating: 0, count: 47) }

    static func snmpSysdescr() -> Data {
        let varbind = ber(0x30, berOID("1.3.6.1.2.1.1.1.0") + ber(0x05, Data()))
        let pdu = ber(0xA0, berInt(0x0A0B0C0D) + berInt(0) + berInt(0)
                      + ber(0x30, varbind))
        return ber(0x30, berInt(0) + ber(0x04, Data("public".utf8)) + pdu)
    }

    static func ssdpMsearch() -> Data {
        Data("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
             .utf8)
        + Data("MAN: \"ssdp:discover\"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n".utf8)
    }

    static func dhcpDiscover() -> Data {
        var out = Data([0x01, 0x01, 0x06, 0x00])
        out += Data([0x12, 0x34, 0x56, 0x78])
        out += Data(repeating: 0, count: 4)
        out += Data(repeating: 0, count: 16)
        out += Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01])
        out += Data(repeating: 0, count: 10)
        out += Data(repeating: 0, count: 64)
        out += Data(repeating: 0, count: 128)
        out += Data([0x63, 0x82, 0x53, 0x63])
        out += Data([53, 1, 1])
        out += Data([55, 4, 1, 3, 6, 15])
        out += Data([255])
        return out
    }

    static func tftpRead() -> Data {
        Data([0x00, 0x01]) + Data("nightjar".utf8) + Data([0])
            + Data("octet".utf8) + Data([0])
    }

    static func stunBinding() -> Data {
        Data([0x00, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42])
            + Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    }

    static func syslogLine() -> Data { Data("<14>nightjar speaking syslog\r\n".utf8) }

    static func wireguardInit() -> Data {
        Data([0x01, 0x00, 0x00, 0x00])
            + Data(repeating: 0x11, count: 4)
            + Data(repeating: 0x22, count: 32)
            + Data(repeating: 0x33, count: 48)
            + Data(repeating: 0x44, count: 28)
            + Data(repeating: 0x55, count: 16)
            + Data(repeating: 0x00, count: 16)
    }

    static func mqttConnect(_ clientID: String = "nightjar") -> Data {
        let body = mqttStr("MQTT") + Data([0x04, 0x02]) + u16(60) + mqttStr(clientID)
        return Data([0x10]) + mqttRemaining(body.count) + body
    }

    static func mqttPublish(_ topic: String = "nightjar",
                            _ payload: Data = Data("alive".utf8),
                            retain: Bool = true) -> Data {
        let body = mqttStr(topic) + payload
        return Data([retain ? 0x31 : 0x30]) + mqttRemaining(body.count) + body
    }

    /// CONNECT then a retained PUBLISH, one shot: a payload that stays living.
    static func mqttPlant() -> Data { mqttConnect() + mqttPublish() }

    static func mssqlPrelogin() -> Data {
        let options: [(UInt8, Int)] = [(0x00, 6), (0x01, 1), (0x02, 1),
                                       (0x03, 4), (0x04, 1)]
        var offset = options.count * 5 + 1
        var head = Data()
        for (token, length) in options {
            head.append(token)
            head += u16(offset)
            head += u16(length)
            offset += length
        }
        head.append(0xFF)
        let data = Data(repeating: 0, count: 6) + Data([0x00, 0x00])
            + u32be(0x1234) + Data([0x00])
        let payload = head + data
        return Data([0x12, 0x01]) + u16(8 + payload.count)
            + Data([0x00, 0x00, 0x01, 0x00]) + payload
    }

    static func smb1Negotiate() -> Data {
        var dialects = Data()
        for dialect in ["NT LM 0.12", "SMB 2.002", "SMB 2.???"] {
            dialects.append(0x02)
            dialects += Data(dialect.utf8)
            dialects.append(0)
        }
        var smb = Data([0xFF]) + Data("SMB".utf8) + Data([0x72])
        smb += Data([0x00, 0x00, 0x00, 0x00])   // status
        smb.append(0x18)                        // flags
        smb += Data([0x53, 0xC8])               // flags2
        smb += Data([0x00, 0x00])               // pid high
        smb += Data(repeating: 0, count: 8)     // signature
        smb += Data([0x00, 0x00])               // reserved
        smb += Data([0xFF, 0xFE])               // tid
        smb += Data([0x00, 0x00])               // pid
        smb += Data([0x00, 0x00])               // uid
        smb += Data([0x00, 0x00])               // mid
        smb.append(0x00)                        // word count
        smb += u16(dialects.count)
        smb += dialects
        let length = smb.count
        return Data([0x00, UInt8((length >> 16) & 0xFF),
                     UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]) + smb
    }

    static func smb2Negotiate() -> Data {
        var header = Data([0xFE]) + Data("SMB".utf8)
        header += u16(64)                       // StructureSize
        header += u16(0)                        // CreditCharge
        header += u32be(0)                      // Status
        header += u16(0)                        // Command = NEGOTIATE
        header += u16(1)                        // CreditRequest
        header += u32be(0)                      // Flags
        header += u32be(0)                      // NextCommand
        header += u64be(1)                      // MessageId
        header += u32be(0)                      // Reserved
        header += u32be(0)                      // TreeId
        header += u64be(0)                      // SessionId
        header += Data(repeating: 0, count: 16) // Signature
        var request = u16(36) + u16(5) + u16(0) + u16(0) + u32be(0)
        request += Data((0..<16).map { UInt8($0) })
        for dialect in [0x0202, 0x0210, 0x0300, 0x0302, 0x0311] {
            request += u16(dialect)
        }
        request += u32be(0) + u16(0) + u16(0)
        let message = header + request
        let length = message.count
        return Data([0x00, UInt8((length >> 16) & 0xFF),
                     UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]) + message
    }

    static func rpcNull() -> Data {
        u32be(0x12345678) + u32be(0) + u32be(2) + u32be(100000)
            + u32be(2) + u32be(0)
            + u32be(0) + u32be(0)
            + u32be(0) + u32be(0)
    }

    static func mongodbIsmaster(_ database: String = "admin") -> Data {
        let query = bsonInt32([("ismaster", 1), ("helloOk", 1)])
        var body = le32(0)
        body += Data(database.utf8) + Data(".$cmd".utf8) + Data([0])
        body += le32(0) + le32(-1)
        body += query
        return le32(16 + body.count) + le32(1) + le32(0) + le32(2004) + body
    }

    static func zookeeperMntr() -> Data { Data([0, 0, 0, 4]) + Data("mntr".utf8) }

    static func cassandraOptions() -> Data {
        Data([0x04, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00])
    }

    static func coapGet(_ path: String = "nightjar") -> Data {
        var out = Data([0x40, 0x01, 0x30, 0x39])
        for (index, segment) in path.split(separator: "/").enumerated() {
            let delta = index == 0 ? 11 : 0
            out.append(UInt8((delta << 4) | segment.utf8.count))
            out += Data(String(segment).utf8)
        }
        return out
    }

    static func modbusRead() -> Data {
        Data([0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01,
              0x03, 0x00, 0x00, 0x00, 0x01])
    }

    static func ldapAnonBind() -> Data {
        ber(0x30, berInt(1) + ber(0x60, berInt(3) + ber(0x04, Data())
                                 + ber(0x80, Data())))
    }

    static func adbVersion() -> Data { Data([0, 0, 0, 12]) + Data("host:version".utf8) }

    static func wolMagic(_ mac: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]) -> Data {
        var out = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { out += Data(mac) }
        return out
    }

    static func zabbixVersion() -> Data {
        let body = Data("{\"request\":\"agent.version\"}".utf8)
        return Data("ZBXD".utf8) + Data([0x01]) + u64le(body.count) + body
    }

    static func graphqlIntrospection() -> Data {
        let body = Data("{\"query\":\"{__schema{queryType{name} types{name kind}}}\"}".utf8)
        return http("POST", "/graphql",
                    headers: [("Content-Type", "application/json")], body: body)
    }

    static func httpGet(_ path: String = "/") -> Data { http("GET", path) }
    static func httpOptions() -> Data { http("OPTIONS", "/") }
    static func httpHead() -> Data { http("HEAD", "/") }
    static func httpTrace() -> Data { http("TRACE", "/") }
    static func httpProxyGet() -> Data { http("GET", "http://example.com/", host: "example.com") }
    static func httpConnect() -> Data {
        Data("CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n".utf8)
    }
    static func influxPing() -> Data {
        Data("GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n".utf8)
    }

    static func sipOptions(_ user: String = "nightjar",
                           _ host: String = "127.0.0.1") -> Data {
        Data(("OPTIONS sip:\(user)@\(host) SIP/2.0\r\n"
              + "Via: SIP/2.0/UDP \(host):5060;branch=z9hG4bKnj\r\n"
              + "Max-Forwards: 70\r\n"
              + "From: <sip:\(user)@\(host)>;tag=nj\r\n"
              + "To: <sip:\(user)@\(host)>\r\n"
              + "Call-ID: nightjar@\(host)\r\n"
              + "CSeq: 1 OPTIONS\r\n"
              + "Contact: <sip:\(user)@\(host)>\r\n"
              + "Content-Length: 0\r\n\r\n").utf8)
    }

    static func rtspOptions() -> Data {
        Data("OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n".utf8)
    }

    static func socks5Greeting() -> Data { Data([0x05, 0x01, 0x00]) }

    static func socks4Connect() -> Data {
        Data([0x04, 0x01, 0x00, 0x50, 0x7F, 0x00, 0x00, 0x01])
            + Data("nightjar".utf8) + Data([0])
    }

    static func telnetNegotiate() -> Data {
        Data([0xFF, 0xFD, 0x03, 0xFF, 0xFB, 0x18, 0xFF, 0xFB, 0x1F])
    }

    static func vncClient() -> Data { Data("RFB 003.008\n".utf8) }

    static func rdpNegotiate() -> Data {
        Data([0x03, 0x00, 0x00, 0x13, 0x0E, 0xE0, 0x00, 0x00, 0x00, 0x00,
              0x00, 0x01, 0x00, 0x08, 0x00, 0x03, 0x00, 0x00, 0x00])
    }

    static func x11Setup() -> Data {
        Data([0x6C, 0x00, 0x0B, 0x00]) + Data(repeating: 0, count: 8)
    }

    static func postgresSSLRequest() -> Data {
        Data([0x00, 0x00, 0x00, 0x08, 0x04, 0xD2, 0x16, 0x2F])
    }

    static func postgresStartup() -> Data {
        let params = Data("user\u{0}nightjar\u{0}database\u{0}nightjar\u{0}\u{0}".utf8)
        return u32be(8 + params.count) + Data([0x00, 0x03, 0x00, 0x00]) + params
    }

    static func mysqlPing() -> Data { Data([0x01, 0x00, 0x00, 0x00, 0x0E]) }
    static func mysqlQuery() -> Data {
        Data([0x01, 0x00, 0x00, 0x00, 0x03]) + Data("SELECT 1".utf8)
    }

    // MARK: - the registry

    static let all: [String: ReconProbe] = makeAll()

    private static func makeAll() -> [String: ReconProbe] {
        var out: [String: ReconProbe] = [:]
        func add(_ name: String, _ port: Int, _ family: String,
                 udp: Bool = false, tls: Bool = false, hint: Data = Data(),
                 summary: String, _ build: @escaping () -> Data) {
            out[name] = ReconProbe(name: name, port: port, udp: udp, tls: tls,
                                   family: family, hint: hint,
                                   summary: summary, build: build)
        }

        // name resolution
        add("dns-a", 53, "dns", udp: true, hint: hx("8180"), summary: "A query") { dnsQuery("example.com", "A") }
        add("dns-aaaa", 53, "dns", udp: true, hint: hx("8180"), summary: "AAAA query") { dnsQuery("example.com", "AAAA") }
        add("dns-mx", 53, "dns", udp: true, hint: hx("8180"), summary: "MX query") { dnsQuery("example.com", "MX") }
        add("dns-txt", 53, "dns", udp: true, hint: hx("8180"), summary: "TXT query") { dnsQuery("example.com", "TXT") }
        add("dns-any", 53, "dns", udp: true, hint: hx("8180"), summary: "ANY query") { dnsQuery("example.com", "ANY") }
        add("dns-version", 53, "dns", udp: true, hint: hx("8180"),
            summary: "CHAOS version.bind - names the resolver") { dnsQuery("version.bind", "TXT", "CH") }
        add("dns-sd", 5353, "mdns", udp: true, hint: hx("8400"),
            summary: "mDNS service enumeration") { dnsQuery("_services._dns-sd._udp.local", "PTR", rd: false, edns: false) }
        add("llmnr", 5355, "llmnr", udp: true, hint: hx("8000"),
            summary: "LLMNR hostname query") { dnsQuery("nightjar", "A", rd: false, edns: false) }
        add("nbns", 137, "netbios-ns", udp: true, hint: hx("8400"),
            summary: "NBNS node-status request") { nbnsQuery() }

        // time, discovery, infrastructure
        add("ntp", 123, "ntp", udp: true, hint: hx("1c"), summary: "NTP client request") { ntpRequest() }
        add("snmp-sysdescr", 161, "snmp", udp: true, hint: hx("a2"),
            summary: "SNMP v1 sysDescr - names the device") { snmpSysdescr() }
        add("ssdp", 1900, "ssdp", udp: true, hint: Data("HTTP/1.1".utf8),
            summary: "SSDP M-SEARCH - UPnP discovery") { ssdpMsearch() }
        add("dhcp-discover", 67, "dhcp", udp: true, hint: hx("020106"),
            summary: "DHCP DISCOVER - ask the LAN to name itself") { dhcpDiscover() }
        add("tftp", 69, "tftp", udp: true, hint: hx("0003"), summary: "TFTP read request") { tftpRead() }
        add("stun", 3478, "stun", udp: true, hint: hx("0101"),
            summary: "STUN binding request - reveals the public address") { stunBinding() }
        add("syslog", 514, "syslog", udp: true, summary: "Syslog datagram") { syslogLine() }
        add("wireguard", 51820, "wireguard", udp: true, hint: hx("02"),
            summary: "WireGuard handshake initiation") { wireguardInit() }

        // data stores
        add("redis-ping", 6379, "redis", hint: Data("+PONG".utf8), summary: "PING") { resp(["PING"]) }
        add("redis-info", 6379, "redis", hint: Data("# Server".utf8), summary: "INFO") { resp(["INFO"]) }
        add("redis-keys", 6379, "redis", hint: Data("*".utf8), summary: "KEYS * - the whole keyspace") { resp(["KEYS", "*"]) }
        add("redis-set", 6379, "redis", hint: Data("+OK".utf8),
            summary: "SET nightjar was-here - a payload that stays living") { resp(["SET", "nightjar", "was-here"]) }
        add("memcached-stats", 11211, "memcached", hint: Data("STAT".utf8), summary: "stats") { Data("stats\r\n".utf8) }
        add("memcached-version", 11211, "memcached", hint: Data("VERSION".utf8), summary: "version") { Data("version\r\n".utf8) }
        add("memcached-get", 11211, "memcached", hint: Data("VALUE".utf8), summary: "get nightjar") { Data("get nightjar\r\n".utf8) }
        add("mongodb-ismaster", 27017, "mongodb", hint: Data("ismaster".utf8),
            summary: "legacy OP_QUERY ismaster") { mongodbIsmaster() }
        add("cassandra-options", 9042, "cassandra", hint: hx("84"), summary: "CQL native OPTIONS") { cassandraOptions() }
        add("couchdb-root", 5984, "couchdb", hint: Data("CouchDB".utf8), summary: "GET /") { httpGet() }
        add("elasticsearch-root", 9200, "elasticsearch", hint: Data("cluster_name".utf8), summary: "GET /") { httpGet() }
        add("zookeeper-mntr", 2181, "zookeeper", hint: Data("zk_".utf8), summary: "mntr four-letter word") { zookeeperMntr() }
        add("etcd-version", 2379, "etcd", hint: Data("etcdserver".utf8), summary: "GET /version") { httpGet("/version") }
        add("consul-leader", 8500, "consul", hint: Data("\"".utf8), summary: "GET /v1/status/leader") { httpGet("/v1/status/leader") }
        add("vault-health", 8200, "vault", hint: Data("initialized".utf8), summary: "GET /v1/sys/health") { httpGet("/v1/sys/health") }

        // messaging
        add("mqtt-connect", 1883, "mqtt", hint: hx("200200"), summary: "CONNECT - clean session") { mqttConnect() }
        add("mqtt-plant", 1883, "mqtt", hint: hx("200200"),
            summary: "CONNECT + retained PUBLISH - the broker keeps it") { mqttPlant() }
        add("amqp-header", 5672, "amqp", hint: Data("AMQP".utf8), summary: "protocol header 0-9-1") { Data([0x41, 0x4D, 0x51, 0x50, 0x00, 0x00, 0x09, 0x01]) }
        add("stomp-connect", 61613, "stomp", hint: Data("CONNECTED".utf8), summary: "STOMP CONNECT") { Data("CONNECT\naccept-version:1.2\nhost:nightjar\n\n\u{0}".utf8) }
        add("rabbitmq-overview", 15672, "rabbitmq", hint: Data("rabbitmq_version".utf8), summary: "management overview") { httpGet("/api/overview") }

        // mail and real-time
        add("smtp-ehlo", 25, "smtp", hint: Data("250".utf8), summary: "EHLO - capabilities") { Data("EHLO nightjar.local\r\n".utf8) }
        add("smtp-vrfy", 25, "smtp", hint: Data("250".utf8), summary: "VRFY root") { Data("VRFY root\r\n".utf8) }
        add("smtp-quit", 25, "smtp", hint: Data("221".utf8), summary: "QUIT") { Data("QUIT\r\n".utf8) }
        add("pop3-capa", 110, "pop3", hint: Data("+OK".utf8), summary: "CAPA") { Data("CAPA\r\n".utf8) }
        add("pop3-capa-tls", 995, "pop3s", tls: true, hint: Data("+OK".utf8), summary: "CAPA over TLS") { Data("CAPA\r\n".utf8) }
        add("imap-capa", 143, "imap", hint: Data("CAPABILITY".utf8), summary: "CAPABILITY") { Data("a1 CAPABILITY\r\n".utf8) }
        add("imap-capa-tls", 993, "imaps", tls: true, hint: Data("CAPABILITY".utf8), summary: "CAPABILITY over TLS") { Data("a1 CAPABILITY\r\n".utf8) }
        add("irc-register", 6667, "irc", hint: Data("001".utf8), summary: "NICK/USER registration") { Data("NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n".utf8) }
        add("sip-options", 5060, "sip", hint: Data("SIP/2.0".utf8), summary: "OPTIONS - what the PBX will tell you") { sipOptions() }
        add("sip-options-tls", 5061, "sips", tls: true, hint: Data("SIP/2.0".utf8), summary: "OPTIONS over TLS") { sipOptions() }
        add("rtsp-options", 554, "rtsp", hint: Data("RTSP/1.0".utf8), summary: "RTSP OPTIONS") { rtspOptions() }

        // databases
        add("postgres-sslrequest", 5432, "postgres", hint: Data("S".utf8),
            summary: "SSLRequest - 'S' means TLS is offered") { postgresSSLRequest() }
        add("postgres-startup", 5432, "postgres", hint: Data("R".utf8),
            summary: "startup message - proves the service") { postgresStartup() }
        add("mysql-ping", 3306, "mysql", summary: "COM_PING") { mysqlPing() }
        add("mysql-query", 3306, "mysql", summary: "COM_QUERY SELECT 1") { mysqlQuery() }
        add("mssql-prelogin", 1433, "mssql", hint: hx("04"),
            summary: "TDS PRELOGIN - the SQL Server opener") { mssqlPrelogin() }

        // file, directory, remote access
        add("smb1-negotiate", 139, "smb1", hint: Data([0xFF]) + Data("SMB".utf8),
            summary: "SMB1 NEGOTIATE") { smb1Negotiate() }
        add("smb2-negotiate", 445, "smb2", hint: Data([0xFE]) + Data("SMB".utf8),
            summary: "SMB2 NEGOTIATE - dialect list") { smb2Negotiate() }
        add("rpc-null", 111, "portmapper", hint: hx("00000001"),
            summary: "ONC RPC NULL call to the portmapper") { rpcNull() }
        add("rsync-modules", 873, "rsync", hint: Data("@RSYNCD".utf8),
            summary: "version handshake - lists modules") { Data("@RSYNCD: 31.0\n".utf8) }
        add("ftp-user", 21, "ftp", hint: Data("331".utf8), summary: "USER anonymous") { Data("USER anonymous\r\n".utf8) }
        add("ssh-banner", 22, "ssh", hint: Data("SSH-".utf8), summary: "nothing - the server speaks first") { Data() }
        add("telnet-negotiate", 23, "telnet", hint: hx("ff"), summary: "DO/WILL option negotiation") { telnetNegotiate() }
        add("vnc-client", 5900, "vnc", hint: Data("RFB".utf8), summary: "client version handshake") { vncClient() }
        add("rdp-negotiate", 3389, "rdp", hint: hx("0300"), summary: "TPKT + X.224 connection request") { rdpNegotiate() }
        add("x11-setup", 6000, "x11", hint: hx("01"), summary: "X11 connection setup") { x11Setup() }
        add("socks5-greeting", 1080, "socks5", hint: hx("05"), summary: "no-auth greeting") { socks5Greeting() }
        add("socks4-connect", 1080, "socks4", hint: hx("005a"), summary: "SOCKS4 CONNECT to 127.0.0.1:80") { socks4Connect() }
        add("adb-version", 5555, "adb", hint: Data("OKAY".utf8), summary: "host:version") { adbVersion() }
        add("ldap-anon-bind", 389, "ldap", hint: hx("61"), summary: "anonymous simple bind") { ldapAnonBind() }
        add("ldap-anon-bind-tls", 636, "ldaps", tls: true, hint: hx("61"), summary: "anonymous bind over TLS") { ldapAnonBind() }
        add("wol", 9, "wake-on-lan", udp: true, summary: "magic packet - wakes a sleeping NIC") { wolMagic() }
        add("coap-get", 5683, "coap", udp: true, hint: hx("60"), summary: "GET /nightjar (CON)") { coapGet() }
        add("modbus-read", 502, "modbus", hint: hx("0001"), summary: "read holding registers") { modbusRead() }
        add("zabbix-agent", 10050, "zabbix", hint: Data("ZBXD".utf8), summary: "agent.version request") { zabbixVersion() }

        // web, proxies, orchestration
        add("http-get", 80, "http", hint: Data("HTTP/1.".utf8), summary: "GET /") { httpGet() }
        add("http-options", 80, "http", hint: Data("HTTP/1.".utf8), summary: "OPTIONS - the Allow header") { httpOptions() }
        add("http-head", 80, "http", hint: Data("HTTP/1.".utf8), summary: "HEAD / - headers, no body") { httpHead() }
        add("http-trace", 80, "http", hint: Data("HTTP/1.".utf8), summary: "TRACE - echoes the request back") { httpTrace() }
        add("https-get", 443, "https", tls: true, hint: Data("HTTP/1.".utf8), summary: "GET / over TLS") { httpGet() }
        add("graphql-introspection", 80, "graphql", hint: Data("__schema".utf8),
            summary: "POST /graphql - dump the whole schema") { graphqlIntrospection() }
        add("http-proxy-get", 3128, "http-proxy", hint: Data("HTTP/1.".utf8),
            summary: "absolute-URI GET - is it an open proxy?") { httpProxyGet() }
        add("http-connect", 3128, "http-proxy", hint: Data("HTTP/1.".utf8), summary: "CONNECT tunnel request") { httpConnect() }
        add("docker-version", 2375, "docker", hint: Data("ApiVersion".utf8),
            summary: "GET /version - unauthenticated?") { httpGet("/version") }
        add("docker-version-tls", 2376, "docker", tls: true, hint: Data("ApiVersion".utf8),
            summary: "GET /version over TLS") { httpGet("/version") }
        add("docker-registry", 5000, "docker-registry", hint: Data("200".utf8), summary: "GET /v2/") { httpGet("/v2/") }
        add("kubernetes-version", 6443, "kubernetes", tls: true, hint: Data("gitVersion".utf8),
            summary: "GET /version (TLS)") { httpGet("/version") }
        add("kubelet-health", 10250, "kubelet", tls: true, hint: Data("ok".utf8),
            summary: "GET /healthz (TLS)") { httpGet("/healthz") }
        add("jenkins-api", 8080, "jenkins", hint: Data("Jenkins".utf8), summary: "GET /api/json") { httpGet("/api/json") }
        add("prometheus-metrics", 9090, "prometheus", hint: Data("HELP".utf8), summary: "GET /metrics") { httpGet("/metrics") }
        add("grafana-health", 3000, "grafana", hint: Data("database".utf8), summary: "GET /api/health") { httpGet("/api/health") }
        add("kibana-status", 5601, "kibana", hint: Data("version".utf8), summary: "GET /api/status") { httpGet("/api/status") }
        add("solr-admin", 8983, "solr", hint: Data("lucene".utf8), summary: "admin info/system") { httpGet("/solr/admin/info/system") }
        add("influxdb-ping", 8086, "influxdb", hint: Data("204".utf8), summary: "GET /ping") { influxPing() }
        add("minio-health", 9000, "minio", hint: Data("200".utf8), summary: "health/live") { httpGet("/minio/health/live") }
        add("neo4j-root", 7474, "neo4j", hint: Data("neo4j".utf8), summary: "GET /") { httpGet() }
        add("gitea-version", 3000, "gitea", hint: Data("version".utf8), summary: "GET /api/v1/version") { httpGet("/api/v1/version") }
        add("gitlab-readiness", 80, "gitlab", hint: Data("GitLab".utf8), summary: "GET /-/readiness") { httpGet("/-/readiness") }

        // small talk
        add("echo", 7, "echo", summary: "nothing - echo") { Data() }
        add("daytime", 13, "daytime", summary: "nothing") { Data() }
        add("chargen", 19, "chargen", summary: "nothing") { Data() }
        add("discard", 9, "discard", summary: "throw it away") { Data("nightjar\r\n".utf8) }
        add("whois", 43, "whois", summary: "query a whois server") { Data("example.com\r\n".utf8) }
        add("finger", 79, "finger", summary: "finger a user") { Data("nightjar\r\n".utf8) }
        add("gopher", 70, "gopher", summary: "gopher selector") { Data("nightjar\r\n".utf8) }
        add("gemini", 1965, "gemini", hint: Data("20 ".utf8), summary: "Gemini request") { Data("gemini://nightjar/\r\n".utf8) }

        return out
    }

    /// One probe per port for the knocker; the rest stay available by name.
    static let portMap: [Int: String] = [
        7: "echo", 9: "discard", 13: "daytime", 19: "chargen", 21: "ftp-user",
        22: "ssh-banner", 23: "telnet-negotiate", 25: "smtp-ehlo", 43: "whois",
        53: "dns-version", 67: "dhcp-discover", 69: "tftp", 70: "gopher",
        79: "finger", 80: "http-get", 110: "pop3-capa", 111: "rpc-null",
        123: "ntp", 137: "nbns", 139: "smb1-negotiate", 143: "imap-capa",
        161: "snmp-sysdescr", 389: "ldap-anon-bind", 443: "https-get",
        445: "smb2-negotiate", 502: "modbus-read", 554: "rtsp-options",
        587: "smtp-ehlo", 636: "ldap-anon-bind-tls", 873: "rsync-modules",
        993: "imap-capa-tls", 995: "pop3-capa-tls", 1080: "socks5-greeting",
        1433: "mssql-prelogin", 1883: "mqtt-connect", 1965: "gemini",
        2181: "zookeeper-mntr", 2375: "docker-version",
        2376: "docker-version-tls", 2379: "etcd-version", 3000: "grafana-health",
        3128: "http-proxy-get", 3306: "mysql-ping", 3389: "rdp-negotiate",
        5000: "docker-registry", 5060: "sip-options", 5061: "sip-options-tls",
        5432: "postgres-sslrequest", 5555: "adb-version", 5601: "kibana-status",
        5672: "amqp-header", 5900: "vnc-client", 5984: "couchdb-root",
        6000: "x11-setup", 61613: "stomp-connect", 6379: "redis-ping",
        6443: "kubernetes-version", 7474: "neo4j-root", 8000: "http-get",
        8080: "jenkins-api", 8086: "influxdb-ping", 8200: "vault-health",
        8443: "https-get", 8500: "consul-leader", 8983: "solr-admin",
        9000: "minio-health", 9042: "cassandra-options", 9090: "prometheus-metrics",
        9200: "elasticsearch-root", 10050: "zabbix-agent",
        10250: "kubelet-health", 11211: "memcached-stats",
        15672: "rabbitmq-overview", 27017: "mongodb-ismaster",
    ]

    static let udpPortMap: [Int: String] = [
        9: "wol", 53: "dns-a", 67: "dhcp-discover", 69: "tftp", 123: "ntp",
        137: "nbns", 161: "snmp-sysdescr", 514: "syslog", 1900: "ssdp",
        3478: "stun", 5353: "dns-sd", 5355: "llmnr", 5683: "coap-get",
        51820: "wireguard",
    ]

    /// The knocker's default sweep: every port the library can name.
    static let defaultPorts: [Int] = portMap.keys.sorted()

    static var names: [String] { all.keys.sorted() }

    static func probe(forPort port: Int, udp: Bool) -> ReconProbe? {
        let table = udp ? udpPortMap : portMap
        guard let name = table[port] else { return nil }
        return all[name]
    }

    static func build(_ name: String) throws -> Data {
        guard let probe = all[name] else {
            let near = all.keys.filter {
                $0.lowercased().contains(name.lowercased())
            }.sorted().prefix(5)
            throw ReconError.unknownProbe(name, Array(near))
        }
        return probe.build()
    }

    static func firstLine(_ data: Data, limit: Int = 160) -> String {
        guard !data.isEmpty else { return "" }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty,
               !trimmed.unicodeScalars.contains(where: {
                   CharacterSet.controlCharacters.contains($0)
               }) {
                return String(trimmed.prefix(limit))
            }
        }
        return data.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func libraryText() -> String {
        let header = "\(all.count) protocol first words "
            + "(\(portMap.count) tcp ports, \(udpPortMap.count) udp)"
        let rows = names.map { name -> String in
            let probe = all[name]!
            return "  \(name.padding(toLength: 24, withPad: " ", startingAt: 0)) "
                + "\(probe.udp ? "udp" : "tcp")/\(probe.port)  \(probe.summary)"
        }
        return ([header, ""] + rows).joined(separator: "\n")
    }
}
'''


# =============================================================================
# ios/nightjar/ReconKit.swift
# =============================================================================

RECON_KIT_SWIFT = r'''import Combine
import Foundation
import Network

/// The recon bench engine: knock, connect, fuzz.
///
/// Same shape as `ScanModel`: a concurrent worker queue gated by a
/// semaphore, and a separate serial queue for NWConnection starts and
/// deadlines so a connection is never starved behind its own gating.
final class Recon: NSObject, ObservableObject {

    struct Hit: Identifiable {
        let id = UUID()
        let port: Int
        let udp: Bool
        let state: String
        let service: String
        let banner: String
        let confirmed: Bool
        let reply: Data
        var label: String { "\(port)/\(udp ? "udp" : "tcp")" }
        var isOpen: Bool { state == "open" }
    }

    @Published private(set) var hits: [Hit] = []
    @Published private(set) var knocking = false
    @Published private(set) var probed = 0
    @Published private(set) var total = 0
    @Published private(set) var lastKnocked = ""

    @Published private(set) var console: [String] = []
    @Published private(set) var connected = false
    @Published var connectTarget = ""

    @Published private(set) var fuzzing = false
    @Published private(set) var fuzzLines: [String] = []
    @Published private(set) var fuzzDead = 0

    weak var mouth: Mouth?

    private let queue = DispatchQueue(label: "nightjar-recon",
                                      attributes: .concurrent)
    private let connectionQueue = DispatchQueue(label: "nightjar-recon-connections")
    private let lock = NSLock()
    private var generation = 0
    private var consoleConnection: NWConnection?
    private var fuzzToken = 0

    // MARK: - knock

    func knock(host rawHost: String, ports: [Int], udp: Bool,
               timeout: TimeInterval = 1.5, jobs: Int = 24,
               speak: Bool = true) {
        let host = rawHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !ports.isEmpty, !knocking else { return }
        knocking = true
        hits = []
        probed = 0
        total = ports.count
        lastKnocked = host
        generation += 1
        let gen = generation
        var found: [Hit] = []
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: max(1, min(jobs, 64)))
        for port in ports {
            group.enter()
            queue.async { [weak self] in
                guard let self = self else { group.leave(); return }
                semaphore.wait()
                self.probe(host: host, port: port, udp: udp,
                           timeout: timeout, speak: speak) { hit in
                    if let hit = hit {
                        self.lock.lock()
                        found.append(hit)
                        self.lock.unlock()
                    }
                    DispatchQueue.main.async { self.probed += 1 }
                    semaphore.signal()
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self, self.generation == gen else { return }
            let sorted = found.sorted { ($0.port, $0.udp ? 1 : 0) < ($1.port, $1.udp ? 1 : 0) }
            self.hits = sorted
            self.knocking = false
            let open = sorted.filter { $0.isOpen }
            self.console.append("knock \(host): \(open.count) open of \(ports.count)")
            if let mouth = self.mouth {
                mouth.logRecon("knock", host, lines: open.map {
                    "\($0.label) \($0.service) \($0.banner)"
                })
                mouth.uiSuccess("Knock: \(open.count) open of \(ports.count)")
            }
        }
    }

    func cancelKnock() {
        generation += 1
        knocking = false
    }

    private func probe(host: String, port: Int, udp: Bool, timeout: TimeInterval,
                       speak: Bool, done: @escaping (Hit?) -> Void) {
        guard (1...65535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            done(nil)
            return
        }
        let spec = speak ? ReconPayloads.probe(forPort: port, udp: udp) : nil
        let params: NWParameters
        if udp {
            params = .udp
        } else if spec?.tls == true {
            params = NWParameters(tls: NWProtocolTLS.Options())
        } else {
            params = .tcp
        }
        let connection = NWConnection(host: NWEndpoint.Host(host),
                                      port: nwPort, using: params)
        var reply = Data()
        var finished = false
        var wasReady = false
        let finishLock = NSLock()

        func finish(_ state: String) {
            finishLock.lock()
            if finished { finishLock.unlock(); return }
            finished = true
            finishLock.unlock()
            connection.cancel()
            let service = spec?.family ?? "?"
            let banner = ReconPayloads.firstLine(reply)
            var confirmed = false
            if let hint = spec?.hint {
                confirmed = hint.isEmpty ? !reply.isEmpty
                                         : reply.range(of: hint) != nil
            }
            done(Hit(port: port, udp: udp, state: state, service: service,
                     banner: banner, confirmed: confirmed, reply: reply))
        }

        func isReady() -> Bool {
            finishLock.lock()
            defer { finishLock.unlock() }
            return wasReady
        }

        func drain() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty { reply += data }
                if isComplete || error != nil {
                    finish("open")
                } else {
                    drain()
                }
            }
        }

        // Connect deadline: only until the connection is up. Once .ready
        // fires the port IS open and nothing later may un-open it.
        connectionQueue.asyncAfter(deadline: .now() + timeout) {
            if !isReady() {
                finish(udp ? "open|filtered" : "closed")
            } else {
                finish("open")
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finishLock.lock(); wasReady = true; finishLock.unlock()
                if let spec = spec, !spec.build().isEmpty {
                    connection.send(content: spec.build(),
                                    completion: .contentProcessed { _ in drain() })
                } else {
                    drain()
                }
            case .failed, .cancelled:
                if !isReady() { finish(udp ? "open|filtered" : "closed") }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    // MARK: - connect (a console, not a terminal)

    func open(_ rawTarget: String) {
        let text = rawTarget.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        guard let target = try? SendTarget.parse(text) else {
            console.append("nightjar: cannot parse \(text)")
            return
        }
        close()
        switch target {
        case .tcp(let host, let port, let tls):
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: tls ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp),
                    label: target.raw)
        case .udp(let host, let port):
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: .udp),
                    label: target.raw)
        case .http(let url, let https):
            let host = url.host ?? ""
            let port = url.port ?? (https ? 443 : 80)
            connect(NWConnection(host: NWEndpoint.Host(host),
                                 port: NWEndpoint.Port(rawValue: UInt16(clamping: port))!,
                                 using: https ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp),
                    label: target.raw)
        default:
            console.append("nightjar: \(target.raw) is not a network target")
        }
    }

    private func connect(_ connection: NWConnection, label: String) {
        consoleConnection = connection
        console.append("— connecting to \(label) —")
        func pump() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                [weak self] data, _, isComplete, error in
                guard let self = self else { return }
                if let data = data, !data.isEmpty { self.append(data) }
                if isComplete || error != nil {
                    self.console.append("— remote closed —")
                    DispatchQueue.main.async { self.connected = false }
                    return
                }
                pump()
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.connected = true
                    self.console.append("— connected —")
                }
                pump()
            case .failed(let error):
                DispatchQueue.main.async {
                    self.connected = false
                    self.console.append("nightjar: \(error.localizedDescription)")
                }
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
    }

    func sendLine(_ text: String, crlf: Bool = true) {
        guard let connection = consoleConnection else { return }
        let payload = Data((crlf ? text + "\r\n" : text).utf8)
        console.append("» \(text)")
        connection.send(content: payload, completion: .contentProcessed { _ in })
    }

    func sendBytes(_ data: Data, label: String) {
        guard let connection = consoleConnection else { return }
        console.append("» \(label) (\(data.count) bytes)")
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    func close() {
        consoleConnection?.cancel()
        consoleConnection = nil
        DispatchQueue.main.async { [weak self] in self?.connected = false }
    }

    private func append(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        if text.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.subtracting(CharacterSet.newlines)
                .contains($0)
        }) {
            for line in PayloadKit.hexdump(data).components(separatedBy: "\n") {
                console.append(line)
            }
        } else {
            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                console.append("  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }

    func clearConsole() { console = [] }

    // MARK: - fuzz

    func startFuzz(target rawTarget: String, seed: Data?, count: Int,
                   length: Int, mutations: Int, seedValue: UInt64?,
                   read: Bool, timeout: TimeInterval) {
        guard !fuzzing, count > 0 else { return }
        guard let target = try? SendTarget.parse(
                rawTarget.trimmingCharacters(in: .whitespaces)) else {
            fuzzLines = ["nightjar: cannot parse \(rawTarget)"]
            return
        }
        fuzzing = true
        fuzzDead = 0
        fuzzLines = ["fuzz \(target.raw) — \(count) mutation(s)"]
        fuzzToken += 1
        let token = fuzzToken
        var rng = seedValue.map { SplitMix64(seed: $0) } ?? SplitMix64(seed: 0x9E3779B97F4A7C15)
        var base = seed ?? Data()
        if base.isEmpty {
            base = Data((0..<max(1, length)).map { _ in UInt8(rng.next() & 0xFF) })
        }
        step(target: target, base: base, index: 1, count: count,
             mutations: mutations, read: read, timeout: timeout,
             rng: &rng, token: token)
    }

    private func step(target: SendTarget, base: Data, index: Int, count: Int,
                      mutations: Int, read: Bool, timeout: TimeInterval,
                      rng: inout SplitMix64, token: Int) {
        guard token == fuzzToken else { return }
        if index > count {
            fuzzing = false
            fuzzLines.append("done — \(fuzzDead) dead connection(s)")
            return
        }
        var blob = [UInt8](base)
        for _ in 0..<max(1, mutations) { mutate(&blob, &rng) }
        let payload = Data(blob)
        exchange(target: target, payload: payload, read: read, timeout: timeout) {
            [weak self] reply, failed in
            guard let self = self, token == self.fuzzToken else { return }
            if failed { self.fuzzDead += 1 }
            let head = failed ? "DEAD" : ReconPayloads.firstLine(reply, limit: 60)
            DispatchQueue.main.async {
                self.fuzzLines.append(
                    "  \(String(format: "%5d", index))  len=\(payload.count)  "
                    + "reply=\(reply.count)  \(head)")
                if self.fuzzLines.count > 400 {
                    self.fuzzLines.removeFirst(self.fuzzLines.count - 400)
                }
                self.step(target: target, base: base, index: index + 1,
                          count: count, mutations: mutations, read: read,
                          timeout: timeout, rng: &rng, token: token)
            }
        }
    }

    func stopFuzz() { fuzzToken += 1; fuzzing = false }

    private func mutate(_ data: inout [UInt8], _ rng: inout SplitMix64) {
        guard !data.isEmpty else { data.append(UInt8(rng.next() & 0xFF)); return }
        switch Int(rng.next() % 7) {
        case 0:
            let i = Int(rng.next() % UInt64(data.count))
            data[i] ^= 1 << UInt8(rng.next() % 8)
        case 1:
            data[Int(rng.next() % UInt64(data.count))] = UInt8(rng.next() & 0xFF)
        case 2:
            data.insert(UInt8(rng.next() & 0xFF), at: Int(rng.next() % UInt64(data.count + 1)))
        case 3 where data.count > 1:
            data.remove(at: Int(rng.next() % UInt64(data.count)))
        case 4:
            let start = Int(rng.next() % UInt64(data.count))
            let end = min(data.count, start + 1 + Int(rng.next() % 16))
            data.insert(contentsOf: data[start..<end], at: start)
        case 5:
            let start = Int(rng.next() % UInt64(data.count))
            let end = min(data.count, start + 1 + Int(rng.next() % 8))
            for i in start..<end { data[i] = UInt8(rng.next() & 0xFF) }
        default:
            data.removeSubrange(Int(rng.next() % UInt64(data.count))..<data.count)
        }
    }

    private func exchange(target: SendTarget, payload: Data, read: Bool,
                          timeout: TimeInterval,
                          done: @escaping (Data, Bool) -> Void) {
        let host: String
        let port: Int
        let params: NWParameters
        switch target {
        case .tcp(let h, let p, let tls):
            host = h; port = p
            params = tls ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        case .udp(let h, let p):
            host = h; port = p
            params = .udp
        case .http(let url, let https):
            host = url.host ?? ""
            port = url.port ?? (https ? 443 : 80)
            params = https ? NWParameters(tls: NWProtocolTLS.Options()) : .tcp
        default:
            done(Data(), true)
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            done(Data(), true)
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort,
                                      using: params)
        var reply = Data()
        var finished = false
        let finishLock = NSLock()
        func finish(_ failed: Bool) {
            finishLock.lock()
            if finished { finishLock.unlock(); return }
            finished = true
            finishLock.unlock()
            connection.cancel()
            done(reply, failed)
        }
        func drain() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) {
                data, _, isComplete, error in
                if let data = data, !data.isEmpty { reply += data }
                if isComplete || error != nil { finish(false) } else { drain() }
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { _ in
                    if read { drain() } else { finish(false) }
                })
            case .failed:
                finish(true)
            default:
                break
            }
        }
        connection.start(queue: connectionQueue)
        connectionQueue.asyncAfter(deadline: .now() + timeout + 1) { finish(false) }
    }

    // MARK: - library handoff

    func payload(for preset: String) -> Data? {
        try? ReconPayloads.build(preset)
    }
}

/// A tiny deterministic RNG, so a fuzz run reproduces from a seed.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
'''


# =============================================================================
# ios/nightjar/ReconBenchView.swift
# =============================================================================

RECON_BENCH_VIEW_SWIFT = r'''import SwiftUI

/// The Recon tab: knock a host with the right protocol on every open
/// port, hold a console against one target, or throw mangled bytes at
/// it. Any probe hands straight to the Send tab in a tap.
struct ReconBenchView: View {
    @Binding var tab: Int
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var toasts: ToastCenter
    @EnvironmentObject private var book: PayloadBook
    @StateObject private var recon = Recon()

    @State private var host = ""
    @State private var ports = ""
    @State private var knockUDP = false
    @State private var jobs = 24.0
    @State private var timeout = 1.5
    @State private var showPresets = false
    @State private var presetFilter = ""
    @State private var connectLine = ""
    @State private var connectCRLF = true
    @State private var fuzzTarget = ""
    @State private var fuzzSeed = ""
    @State private var fuzzCount = 200.0
    @State private var fuzzMutations = 1.0

    private var portList: [Int] {
        let trimmed = ports.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ReconPayloads.defaultPorts }
        var out: [Int] = []
        for chunk in trimmed.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let text = String(chunk)
            if let dash = text.firstIndex(of: "-"), dash != text.startIndex {
                let low = Int(text[text.startIndex..<dash]) ?? 0
                let high = Int(text[text.index(after: dash)...]) ?? 0
                if low > 0, high >= low, high - low <= 1024 {
                    out.append(contentsOf: low...min(high, 65535))
                }
            } else if let port = Int(text), (1...65535).contains(port) {
                out.append(port)
            }
        }
        return Array(Set(out)).sorted().prefix(1024).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                knockSection
                if !recon.hits.isEmpty { resultsSection }
                connectSection
                fuzzSection
                librarySection
            }
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .navigationTitle("Recon")
            .onAppear { recon.mouth = mouth }
            .sheet(isPresented: $showPresets) { presetSheet }
        }
    }

    // MARK: knock

    @ViewBuilder private var knockSection: some View {
        Section {
            TextField("host or IP (192.168.1.1)", text: $host)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
            TextField("ports — blank for the usual suspects, or 22,80,443 or 1-1024",
                      text: $ports)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Toggle("Also knock the UDP service ports", isOn: $knockUDP)
            HStack {
                Text("At a time")
                Slider(value: $jobs, in: 4...64, step: 4)
                Text("\(Int(jobs))").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("Timeout")
                Slider(value: $timeout, in: 0.5...5, step: 0.5)
                Text(String(format: "%.1fs", timeout))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                recon.knock(host: host, ports: portList, udp: knockUDP,
                            timeout: timeout, jobs: Int(jobs))
            } label: {
                Label(recon.knocking
                      ? "Knocking… \(recon.probed)/\(recon.total)"
                      : "Knock \(portList.count) port(s)",
                      systemImage: "target")
            }
            .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty
                      || recon.knocking)
            if recon.knocking {
                Button("Stop") { recon.cancelKnock() }
            }
        } header: {
            Text("Knock")
        } footer: {
            Text("Connects to each port and speaks the protocol that port "
                 + "expects. A star means the reply carried the protocol's "
                 + "own tell — the port answered as that service, not merely "
                 + "opened. Tap a hit to load it into Send.")
        }
    }

    @ViewBuilder private var resultsSection: some View {
        Section("Open — \(recon.hits.filter { $0.isOpen }.count)") {
            ForEach(recon.hits.filter { $0.isOpen }) { hit in
                Button {
                    Haptics.select()
                    handoff(hit)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hit.confirmed ? "★" : "·")
                            .foregroundStyle(hit.confirmed ? .green : .secondary)
                        Text(hit.label)
                            .font(.callout.monospacedDigit())
                        Text(hit.service).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(hit.banner)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func handoff(_ hit: Recon.Hit) {
        let base = recon.lastKnocked.isEmpty
            ? host.trimmingCharacters(in: .whitespaces) : recon.lastKnocked
        mouth.scanHandoffTarget = hit.udp
            ? "udp://\(base):\(hit.port)" : "tcp://\(base):\(hit.port)"
        mouth.scanHandoffPayload = nil
        if let name = ReconPayloads.probe(forPort: hit.port, udp: hit.udp)?.name,
           let data = try? ReconPayloads.build(name) {
            mouth.scanHandoffPayload = name
            mouth.scanHandoffHex = data.map { String(format: "%02x", $0) }.joined()
        }
        toasts.show("Loaded \(hit.label) into Send")
        tab = 1
    }

    // MARK: connect

    @ViewBuilder private var connectSection: some View {
        Section {
            TextField("tcp://host:port", text: $recon.connectTarget)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            HStack {
                Button(recon.connected ? "Close" : "Open") {
                    Haptics.tap()
                    recon.connected ? recon.close() : recon.open(recon.connectTarget)
                }
                .disabled(recon.connectTarget.isEmpty)
                Spacer()
                Toggle("CRLF", isOn: $connectCRLF).fixedSize()
            }
            if recon.connected {
                HStack {
                    TextField("send a line", text: $connectLine)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onSubmit {
                            recon.sendLine(connectLine, crlf: connectCRLF)
                            connectLine = ""
                        }
                    Button("Send") {
                        Haptics.tap()
                        recon.sendLine(connectLine, crlf: connectCRLF)
                        connectLine = ""
                    }
                }
            }
            if !recon.console.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(recon.console.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 220)
                Button("Clear console") { recon.clearConsole() }
                    .font(.caption)
            }
        } header: {
            Text("Connect")
        } footer: {
            Text("A console, not a terminal: open the socket, send lines, "
                 + "watch what comes back. Binary replies print as hexdumps.")
        }
    }

    // MARK: fuzz

    @ViewBuilder private var fuzzSection: some View {
        Section {
            TextField("target (tcp://host:port or udp://…)", text: $fuzzTarget)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            TextField("seed hex (optional)", text: $fuzzSeed)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            HStack {
                Text("Rounds")
                Slider(value: $fuzzCount, in: 10...2000, step: 10)
                Text("\(Int(fuzzCount))").monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text("Mutations")
                Slider(value: $fuzzMutations, in: 1...8, step: 1)
                Text("\(Int(fuzzMutations))").monospacedDigit().foregroundStyle(.secondary)
            }
            Button {
                Haptics.tap()
                let seed = fuzzSeed.isEmpty ? nil : try? PayloadKit.decodeHex(fuzzSeed)
                recon.startFuzz(target: fuzzTarget, seed: seed,
                                count: Int(fuzzCount), length: 32,
                                mutations: Int(fuzzMutations), seedValue: 1,
                                read: true, timeout: 2)
            } label: {
                Label(recon.fuzzing ? "Fuzzing…" : "Fuzz", systemImage: "waveform.path.ecg")
            }
            .disabled(fuzzTarget.isEmpty || recon.fuzzing)
            if recon.fuzzing {
                Button("Stop") { recon.stopFuzz() }
            }
            if !recon.fuzzLines.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(recon.fuzzLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption2.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        } header: {
            Text("Fuzz")
        } footer: {
            Text("Seven mutators, a reproducible seed, and a reply digest "
                 + "per round. DEAD means the connection was refused or reset.")
        }
    }

    // MARK: library

    @ViewBuilder private var librarySection: some View {
        Section {
            Button {
                Haptics.tap()
                showPresets = true
            } label: {
                Label("Protocol library — \(ReconPayloads.all.count) probes",
                      systemImage: "book")
            }
            Button {
                Haptics.tap()
                addAllToLibrary()
            } label: {
                Label("Add every probe to the payload library",
                      systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Library")
        } footer: {
            Text("Wire-exact first words for \(ReconPayloads.portMap.count) "
                 + "TCP ports and \(ReconPayloads.udpPortMap.count) UDP ports. "
                 + "Adding them to the payload library makes every one "
                 + "sendable by hand from the Send tab.")
        }
    }

    private func addAllToLibrary() {
        var added = 0
        for name in ReconPayloads.names {
            guard let probe = ReconPayloads.all[name] else { continue }
            let data = probe.build()
            book.add(SavedPayload(
                name: "probe · \(name)",
                source: "hex",
                text: data.map { String(format: "%02x", $0) }.joined(separator: " "),
                xorKey: "", useGzip: false, framing: "raw"))
            added += 1
        }
        toasts.show("Added \(added) probes to the payload library")
    }

    @ViewBuilder private var presetSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredPresets, id: \.name) { probe in
                    Button {
                        Haptics.select()
                        showPresets = false
                        mouth.scanHandoffTarget = probe.udp
                            ? "udp://\(host):\(probe.port)"
                            : "tcp://\(host):\(probe.port)"
                        mouth.scanHandoffPayload = probe.name
                        mouth.scanHandoffHex = probe.build()
                            .map { String(format: "%02x", $0) }.joined()
                        toasts.show("Loaded \(probe.name) into Send")
                        tab = 1
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(probe.name).font(.callout)
                                Text(probe.summary)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(probe.udp ? "udp" : "tcp")/\(probe.port)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $presetFilter)
            .navigationTitle("Protocol library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showPresets = false }
                }
            }
        }
    }

    private var filteredPresets: [ReconProbe] {
        let needle = presetFilter.lowercased()
        let all = ReconPayloads.names.compactMap { ReconPayloads.all[$0] }
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(needle)
                || $0.summary.lowercased().contains(needle)
                || $0.family.lowercased().contains(needle)
        }
    }
}
'''


# =============================================================================
# ios/nightjarTests/ReconTests.swift
# =============================================================================

RECON_TESTS_SWIFT = r'''import XCTest
@testable import nightjar

/// The library builds, the maps are sane, the wire shapes are what
/// they claim to be.
final class ReconTests: XCTestCase {

    func testEveryProbeBuilds() {
        for name in ReconPayloads.names {
            XCTAssertNotNil(ReconPayloads.all[name])
            _ = try? ReconPayloads.build(name)
        }
    }

    func testPortMapsPointAtRealProbes() {
        for (_, name) in ReconPayloads.portMap {
            XCTAssertNotNil(ReconPayloads.all[name], "tcp map names \(name)")
        }
        for (_, name) in ReconPayloads.udpPortMap {
            XCTAssertNotNil(ReconPayloads.all[name], "udp map names \(name)")
        }
    }

    func testDNSQueryShape() {
        let blob = ReconPayloads.dnsQuery("example.com", "A")
        XCTAssertEqual(blob[0], 0x12)
        XCTAssertEqual(blob[2], 0x01)            // RD set
        XCTAssertEqual(blob[5], 0x01)            // QDCOUNT = 1
        XCTAssertTrue(blob.range(of: Data("\u{7}example\u{3}com".utf8)) != nil)
    }

    func testSNMPSysdescrIsBER() {
        let blob = ReconPayloads.snmpSysdescr()
        XCTAssertEqual(blob[0], 0x30)            // SEQUENCE
        XCTAssertTrue(blob.range(of: Data("public".utf8)) != nil)
        // 1.3.6.1.2.1.1.1.0 packed
        XCTAssertTrue(blob.range(of: Data([0x06, 0x08, 0x2B, 0x06, 0x01,
                                           0x02, 0x01, 0x01, 0x01, 0x00])) != nil)
    }

    func testMSSQLPreloginLengthMatches() {
        let blob = ReconPayloads.mssqlPrelogin()
        XCTAssertEqual(blob[0], 0x12)
        let declared = Int(blob[2]) << 8 | Int(blob[3])
        XCTAssertEqual(declared, blob.count)
    }

    func testSMB2Header() {
        let blob = ReconPayloads.smb2Negotiate()
        XCTAssertEqual(Array(blob[4..<8]), Array("SMB".utf8) + [0x00][0...0] + [])
        XCTAssertEqual(blob[4], 0xFE)
        let structure = Int(blob[8]) | Int(blob[9]) << 8
        XCTAssertEqual(structure, 64)
    }

    func testSMB1NegotiateLengthMatches() {
        let blob = ReconPayloads.smb1Negotiate()
        XCTAssertEqual(blob[1], 0xFF)
        let declared = Int(blob[1]) << 16 | Int(blob[2]) << 8 | Int(blob[3])
        XCTAssertEqual(declared, blob.count - 4)
    }

    func testWireguardInitIs148Bytes() {
        XCTAssertEqual(ReconPayloads.wireguardInit().count, 148)
    }

    func testWOLShape() {
        let blob = ReconPayloads.wolMagic()
        XCTAssertEqual(Array(blob.prefix(6)), Array(repeating: 0xFF, count: 6))
        XCTAssertEqual(blob.count, 6 + 16 * 6)
    }

    func testMQTTPlantConnectsThenPublishes() {
        let blob = ReconPayloads.mqttPlant()
        XCTAssertEqual(blob[0], 0x10)                    // CONNECT first
        XCTAssertTrue(blob.dropFirst(2).contains(0x31))  // retained PUBLISH
    }

    func testUnknownProbeSuggests() {
        XCTAssertThrowsError(try ReconPayloads.build("redis-pig")) { error in
            XCTAssertTrue("\(error)".contains("redis-ping"))
        }
    }

    func testFirstLineFallsBackToHex() {
        XCTAssertEqual(ReconPayloads.firstLine(Data("+PONG\r\nx".utf8)), "+PONG")
        XCTAssertFalse(ReconPayloads.firstLine(Data([0x00, 0x01, 0x02])).isEmpty)
    }
}
'''


# =============================================================================
# docs
# =============================================================================

HACKER_RECON_MD = r'''# nightjar-hack recon

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
'''


IOS_README_SECTION = r'''
## Recon (2.7.0)

A **Recon** tab, beside Send and Serve: knock, connect, fuzz, over a
library of wire-exact protocol first words.

- **Knock** — every port the library can name, each knocked with the
  protocol that port expects. A star means the reply carried the
  protocol's own tell, so the port is *identified*, not merely open.
  Tap a hit to load it into Send.
- **Connect** — a console against one target, with hexdump rendering
  for binary replies.
- **Fuzz** — seven mutators, a reproducible seed, a reply digest per
  round.
- **Library** — 105 probes over 78 TCP and 14 UDP ports, with one
  button to add every one to the payload library so they are sendable
  by hand from the Send tab too.

The Listen tab is untouched: the ear still never connects. The same
library is mirrored into the Python CLI (`nightjar send --preset`,
`nightjar knock`) for parity, and the manual is
[HACKER-RECON.md](../HACKER-RECON.md).
'''


# =============================================================================
# the ContentView tab
# =============================================================================

CONTENTVIEW_OLD = """            AboutView()
                .appThemed()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(5)
        }
"""

CONTENTVIEW_NEW = """            AboutView()
                .appThemed()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(5)
            ReconBenchView(tab: $tab)
                .appThemed()
                .tabItem { Label("Recon", systemImage: "target") }
                .tag(6)
        }
"""

CONTENTVIEW_OLD_ALT = """            ReconBenchView(tab: $tab)
                .appThemed()
                .tabItem { Label("Recon", systemImage: "target") }
                .tag(6)
        }
"""


# =============================================================================
# Python parity: nightjar/payloads.py and nightjar/recon.py
# =============================================================================

PAYLOADS_PY = r'''"""nightjar payloads - protocol first words, wire-exact.

The Python mirror of ios/nightjar/ReconPayloads.swift. `nightjar knock`
speaks the right probe at every open port; `nightjar send --preset NAME`
uses one as a payload and fills in the service's own port when you leave
it off. Keep the two tables in step - tools/parity is the place to prove
it.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from functools import partial
from typing import Callable


def _ber_len(size: int) -> bytes:
    if size < 0x80:
        return bytes([size])
    out = b""
    while size:
        out = bytes([size & 0xFF]) + out
        size >>= 8
    return bytes([0x80 | len(out)]) + out


def _ber(tag: int, payload: bytes) -> bytes:
    return bytes([tag]) + _ber_len(len(payload)) + payload


def _ber_int(value: int) -> bytes:
    if value == 0:
        return _ber(0x02, b"\x00")
    out = b""
    while value:
        out = bytes([value & 0xFF]) + out
        value >>= 8
    if out[0] & 0x80:
        out = b"\x00" + out
    return _ber(0x02, out)


def _ber_base128(value: int) -> bytes:
    chunks = [value & 0x7F]
    value >>= 7
    while value:
        chunks.append((value & 0x7F) | 0x80)
        value >>= 7
    return bytes(reversed(chunks))


def _ber_oid(dotted: str) -> bytes:
    parts = [int(p) for p in dotted.split(".")]
    body = bytes([40 * parts[0] + parts[1]])
    for part in parts[2:]:
        body += _ber_base128(part)
    return _ber(0x06, body)


def _resp(*parts) -> bytes:
    out = [b"*%d\r\n" % len(parts)]
    for part in parts:
        raw = part.encode("utf-8") if isinstance(part, str) else part
        out.append(b"$%d\r\n%s\r\n" % (len(raw), raw))
    return b"".join(out)


def _mqtt_str(text: str) -> bytes:
    raw = text.encode("utf-8")
    return struct.pack("!H", len(raw)) + raw


def _mqtt_remaining(size: int) -> bytes:
    out = b""
    while True:
        byte = size % 128
        size //= 128
        if size:
            byte |= 0x80
        out += bytes([byte])
        if not size:
            return out


def _dns_name(name: str) -> bytes:
    name = name.rstrip(".")
    out = b""
    for label in name.split("."):
        raw = label.encode("ascii")
        out += bytes([len(raw)]) + raw
    return out + b"\x00"


def _nbt_name(name: str = "*") -> bytes:
    padded = ("*" + " " * 15) if name == "*" else name.upper().ljust(16)[:16]
    out = b"\x20"
    for char in padded:
        code = ord(char)
        out += bytes([ord("A") + (code >> 4), ord("A") + (code & 0x0F)])
    return out + b"\x00"


def _http(method: str = "GET", path: str = "/", *, host: str = "localhost",
          headers: tuple = (), body: bytes = b"") -> bytes:
    lines = [f"{method} {path} HTTP/1.1", f"Host: {host}",
             "User-Agent: nightjar", "Accept: */*"]
    if body:
        lines.append(f"Content-Length: {len(body)}")
    lines.extend(f"{key}: {value}" for key, value in headers)
    lines.append("Connection: close")
    return ("\r\n".join(lines) + "\r\n\r\n").encode() + body


QTYPES = {"A": 1, "NS": 2, "CNAME": 5, "SOA": 6, "PTR": 12, "MX": 15,
          "TXT": 16, "AAAA": 28, "SRV": 33, "ANY": 255}
QCLASSES = {"IN": 1, "CH": 3, "HS": 4}


def dns_query(qname: str, qtype: str = "A", qclass: str = "IN",
              rd: bool = True, edns: bool = True) -> bytes:
    flags = 0x0100 if rd else 0x0000
    header = struct.pack("!HHHHHH", 0x1234, flags, 1, 0, 0, 1 if edns else 0)
    out = header + _dns_name(qname)
    out += struct.pack("!HH", QTYPES.get(qtype, 1), QCLASSES.get(qclass, 1))
    if edns:
        out += b"\x00" + struct.pack("!HHIH", 41, 4096, 0, 0)
    return out


def nbns_query() -> bytes:
    return (b"\x12\x34\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00"
            + _nbt_name() + struct.pack("!HH", 0x0021, 0x0001))


def ntp_request() -> bytes:
    return b"\x1b" + b"\x00" * 47


def snmp_sysdescr() -> bytes:
    varbind = _ber(0x30, _ber_oid("1.3.6.1.2.1.1.1.0") + _ber(0x05, b""))
    pdu = _ber(0xA0, _ber_int(0x0A0B0C0D) + _ber_int(0) + _ber_int(0)
               + _ber(0x30, varbind))
    return _ber(0x30, _ber_int(0) + _ber(0x04, b"public") + pdu)


def ssdp_msearch() -> bytes:
    return (b"M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n"
            b'MAN: "ssdp:discover"\r\nMX: 1\r\nST: ssdp:all\r\n\r\n')


def dhcp_discover() -> bytes:
    return (b"\x01\x01\x06\x00" + b"\x12\x34\x56\x78" + b"\x00" * 4
            + b"\x00" * 16 + b"\xde\xad\xbe\xef\x00\x01" + b"\x00" * 10
            + b"\x00" * 64 + b"\x00" * 128 + b"\x63\x82\x53\x63"
            + bytes([53, 1, 1]) + bytes([55, 4, 1, 3, 6, 15]) + bytes([255]))


def tftp_read() -> bytes:
    return b"\x00\x01" + b"nightjar\x00octet\x00"


def stun_binding() -> bytes:
    return b"\x00\x01\x00\x00\x21\x12\xa4\x42" + bytes(range(12))


def syslog_line() -> bytes:
    return b"<14>nightjar speaking syslog\r\n"


def wireguard_init() -> bytes:
    return (b"\x01\x00\x00\x00" + b"\x11" * 4 + b"\x22" * 32 + b"\x33" * 48
            + b"\x44" * 28 + b"\x55" * 16 + b"\x00" * 16)


def mqtt_connect(client_id: str = "nightjar") -> bytes:
    body = _mqtt_str("MQTT") + bytes([4, 0x02]) + struct.pack("!H", 60)
    body += _mqtt_str(client_id)
    return b"\x10" + _mqtt_remaining(len(body)) + body


def mqtt_publish(topic: str = "nightjar", payload: bytes = b"alive",
                 retain: bool = True) -> bytes:
    body = _mqtt_str(topic) + payload
    return bytes([0x31 if retain else 0x30]) + _mqtt_remaining(len(body)) + body


def mqtt_plant() -> bytes:
    return mqtt_connect() + mqtt_publish()


def mssql_prelogin() -> bytes:
    options = ((0x00, 6), (0x01, 1), (0x02, 1), (0x03, 4), (0x04, 1))
    offset = len(options) * 5 + 1
    head = b""
    for token, length in options:
        head += bytes([token]) + struct.pack("!HH", offset, length)
        offset += length
    head += b"\xff"
    payload = head + b"\x00" * 6 + b"\x00\x00" + struct.pack("!I", 0x1234) + b"\x00"
    return (b"\x12\x01" + struct.pack("!H", 8 + len(payload))
            + b"\x00\x00\x01\x00" + payload)


def smb1_negotiate() -> bytes:
    dialects = b"".join(b"\x02" + d + b"\x00"
                        for d in (b"NT LM 0.12", b"SMB 2.002", b"SMB 2.???"))
    smb = (b"\xffSMB" + b"\x72" + b"\x00" * 4 + b"\x18" + b"\x53\xc8"
           + b"\x00\x00" + b"\x00" * 8 + b"\x00\x00" + b"\xff\xfe"
           + b"\x00" * 6 + b"\x00" + struct.pack("<H", len(dialects)) + dialects)
    return b"\x00" + len(smb).to_bytes(3, "big") + smb


def smb2_negotiate() -> bytes:
    dialects = (0x0202, 0x0210, 0x0300, 0x0302, 0x0311)
    header = (b"\xfeSMB" + struct.pack("<HH", 64, 0) + struct.pack("<I", 0)
              + struct.pack("<H", 0) + struct.pack("<H", 1) + struct.pack("<I", 0)
              + struct.pack("<I", 0) + struct.pack("<Q", 1) + struct.pack("<I", 0)
              + struct.pack("<I", 0) + struct.pack("<Q", 0) + b"\x00" * 16)
    request = (struct.pack("<HHHHI", 36, len(dialects), 0, 0, 0)
               + bytes(range(16))
               + b"".join(struct.pack("<H", d) for d in dialects)
               + struct.pack("<IHH", 0, 0, 0))
    msg = header + request
    return b"\x00" + len(msg).to_bytes(3, "big") + msg


def rpc_null() -> bytes:
    return (struct.pack("!IIII", 0x12345678, 0, 2, 100000)
            + struct.pack("!II", 2, 0) + struct.pack("!II", 0, 0)
            + struct.pack("!II", 0, 0))


def mongodb_ismaster() -> bytes:
    body = struct.pack("<i", 0) + b"admin.$cmd\x00" + struct.pack("<ii", 0, -1)
    body += struct.pack("<i", 4 + 12 + 1) + b"\x10ismaster\x00" + struct.pack("<i", 1) + b"\x00"
    return struct.pack("<iiii", 16 + len(body), 1, 0, 2004) + body


def zookeeper_mntr() -> bytes:
    return b"\x00\x00\x00\x04mntr"


def cassandra_options() -> bytes:
    return b"\x04\x00\x00\x00\x05\x00\x00\x00\x00"


def coap_get(path: str = "nightjar") -> bytes:
    out = b"\x40\x01\x30\x39"
    for index, segment in enumerate(path.split("/")):
        out += bytes([((11 if index == 0 else 0) << 4) | len(segment)])
        out += segment.encode()
    return out


def modbus_read() -> bytes:
    return struct.pack("!HHHB", 1, 0, 6, 1) + b"\x03" + struct.pack("!HH", 0, 1)


def ldap_anon_bind() -> bytes:
    return _ber(0x30, _ber_int(1) + _ber(
        0x60, _ber_int(3) + _ber(0x04, b"") + _ber(0x80, b"")))


def adb_version() -> bytes:
    return b"\x00\x00\x00\x0chost:version"


def wol_magic() -> bytes:
    return b"\xff" * 6 + bytes.fromhex("aabbccddeeff") * 16


def zabbix_version() -> bytes:
    body = b'{"request":"agent.version"}'
    return b"ZBXD\x01" + struct.pack("<Q", len(body)) + body


def graphql_introspection() -> bytes:
    body = b'{"query":"{__schema{queryType{name} types{name kind}}}"}'
    return _http("POST", "/graphql",
                 headers=(("Content-Type", "application/json"),), body=body)


def http_get(path: str = "/") -> bytes:
    return _http("GET", path)


def sip_options() -> bytes:
    return (b"OPTIONS sip:nightjar@127.0.0.1 SIP/2.0\r\n"
            b"Via: SIP/2.0/UDP 127.0.0.1:5060;branch=z9hG4bKnj\r\n"
            b"Max-Forwards: 70\r\n"
            b"From: <sip:nightjar@127.0.0.1>;tag=nj\r\n"
            b"To: <sip:nightjar@127.0.0.1>\r\n"
            b"Call-ID: nightjar@127.0.0.1\r\n"
            b"CSeq: 1 OPTIONS\r\n"
            b"Contact: <sip:nightjar@127.0.0.1>\r\n"
            b"Content-Length: 0\r\n\r\n")


def postgres_sslrequest() -> bytes:
    return struct.pack("!II", 8, 80877103)


def postgres_startup() -> bytes:
    params = b"user\x00nightjar\x00database\x00nightjar\x00\x00"
    return struct.pack("!II", 8 + len(params), 196608) + params


def mysql_ping() -> bytes:
    return b"\x01\x00\x00\x00\x0e"


def mysql_query() -> bytes:
    return b"\x01\x00\x00\x00\x03SELECT 1"


@dataclass(frozen=True)
class Probe:
    name: str
    port: int
    proto: str
    family: str
    hint: bytes
    build: Callable[[], bytes]
    tls: bool = False
    summary: str = ""


PROBES: dict[str, Probe] = {}


def _probe(name, port, proto, family, hint, build, *, tls=False, summary=""):
    PROBES[name] = Probe(name, port, proto, family, hint, build, tls,
                         summary or family)


def _register() -> None:
    add = _probe
    add("dns-a", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "A"), summary="A query")
    add("dns-aaaa", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "AAAA"), summary="AAAA query")
    add("dns-mx", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "MX"), summary="MX query")
    add("dns-txt", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "TXT"), summary="TXT query")
    add("dns-any", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "example.com", "ANY"), summary="ANY query")
    add("dns-version", 53, "udp", "dns", b"\x81\x80", partial(dns_query, "version.bind", "TXT", "CH"), summary="CHAOS version.bind")
    add("dns-sd", 5353, "udp", "mdns", b"\x84\x00", partial(dns_query, "_services._dns-sd._udp.local", "PTR", rd=False, edns=False), summary="mDNS enumeration")
    add("llmnr", 5355, "udp", "llmnr", b"\x80\x00", partial(dns_query, "nightjar", "A", rd=False, edns=False), summary="LLMNR query")
    add("nbns", 137, "udp", "netbios-ns", b"\x84\x00", nbns_query, summary="NBNS node-status")
    add("ntp", 123, "udp", "ntp", b"\x1c", ntp_request, summary="NTP request")
    add("snmp-sysdescr", 161, "udp", "snmp", b"\xa2", snmp_sysdescr, summary="SNMP sysDescr")
    add("ssdp", 1900, "udp", "ssdp", b"HTTP/1.1", ssdp_msearch, summary="SSDP M-SEARCH")
    add("dhcp-discover", 67, "udp", "dhcp", b"\x02\x01\x06", dhcp_discover, summary="DHCP DISCOVER")
    add("tftp", 69, "udp", "tftp", b"\x00\x03", tftp_read, summary="TFTP read")
    add("stun", 3478, "udp", "stun", b"\x01\x01", stun_binding, summary="STUN binding")
    add("syslog", 514, "udp", "syslog", b"", syslog_line, summary="syslog datagram")
    add("wireguard", 51820, "udp", "wireguard", b"\x02", wireguard_init, summary="WireGuard init")
    add("redis-ping", 6379, "tcp", "redis", b"+PONG", partial(_resp, "PING"), summary="PING")
    add("redis-info", 6379, "tcp", "redis", b"# Server", partial(_resp, "INFO"), summary="INFO")
    add("redis-keys", 6379, "tcp", "redis", b"*", partial(_resp, "KEYS", "*"), summary="KEYS *")
    add("redis-set", 6379, "tcp", "redis", b"+OK", partial(_resp, "SET", "nightjar", "was-here"), summary="SET - a plant")
    add("memcached-stats", 11211, "tcp", "memcached", b"STAT", lambda: b"stats\r\n", summary="stats")
    add("memcached-version", 11211, "tcp", "memcached", b"VERSION", lambda: b"version\r\n", summary="version")
    add("memcached-get", 11211, "tcp", "memcached", b"VALUE", lambda: b"get nightjar\r\n", summary="get")
    add("mongodb-ismaster", 27017, "tcp", "mongodb", b"ismaster", mongodb_ismaster, summary="OP_QUERY ismaster")
    add("cassandra-options", 9042, "tcp", "cassandra", b"\x84", cassandra_options, summary="CQL OPTIONS")
    add("couchdb-root", 5984, "tcp", "couchdb", b"CouchDB", http_get, summary="GET /")
    add("elasticsearch-root", 9200, "tcp", "elasticsearch", b"cluster_name", http_get, summary="GET /")
    add("zookeeper-mntr", 2181, "tcp", "zookeeper", b"zk_", zookeeper_mntr, summary="mntr")
    add("etcd-version", 2379, "tcp", "etcd", b"etcdserver", partial(http_get, "/version"), summary="GET /version")
    add("consul-leader", 8500, "tcp", "consul", b'"', partial(http_get, "/v1/status/leader"), summary="status/leader")
    add("vault-health", 8200, "tcp", "vault", b"initialized", partial(http_get, "/v1/sys/health"), summary="sys/health")
    add("mqtt-connect", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_connect, summary="CONNECT")
    add("mqtt-plant", 1883, "tcp", "mqtt", b"\x20\x02\x00", mqtt_plant, summary="CONNECT + retained PUBLISH")
    add("amqp-header", 5672, "tcp", "amqp", b"AMQP", lambda: b"AMQP\x00\x00\x09\x01", summary="AMQP 0-9-1")
    add("stomp-connect", 61613, "tcp", "stomp", b"CONNECTED", lambda: b"CONNECT\naccept-version:1.2\nhost:nightjar\n\n\x00", summary="STOMP CONNECT")
    add("rabbitmq-overview", 15672, "tcp", "rabbitmq", b"rabbitmq_version", partial(http_get, "/api/overview"), summary="management overview")
    add("smtp-ehlo", 25, "tcp", "smtp", b"250", lambda: b"EHLO nightjar.local\r\n", summary="EHLO")
    add("smtp-vrfy", 25, "tcp", "smtp", b"250", lambda: b"VRFY root\r\n", summary="VRFY root")
    add("smtp-quit", 25, "tcp", "smtp", b"221", lambda: b"QUIT\r\n", summary="QUIT")
    add("pop3-capa", 110, "tcp", "pop3", b"+OK", lambda: b"CAPA\r\n", summary="CAPA")
    add("pop3-capa-tls", 995, "tcp", "pop3s", b"+OK", lambda: b"CAPA\r\n", tls=True, summary="CAPA over TLS")
    add("imap-capa", 143, "tcp", "imap", b"CAPABILITY", lambda: b"a1 CAPABILITY\r\n", summary="CAPABILITY")
    add("imap-capa-tls", 993, "tcp", "imaps", b"CAPABILITY", lambda: b"a1 CAPABILITY\r\n", tls=True, summary="CAPABILITY over TLS")
    add("irc-register", 6667, "tcp", "irc", b"001", lambda: b"NICK nightjar\r\nUSER nightjar 0 * :nightjar\r\n", summary="NICK/USER")
    add("sip-options", 5060, "tcp", "sip", b"SIP/2.0", sip_options, summary="OPTIONS")
    add("sip-options-tls", 5061, "tcp", "sips", b"SIP/2.0", sip_options, tls=True, summary="OPTIONS over TLS")
    add("rtsp-options", 554, "tcp", "rtsp", b"RTSP/1.0", lambda: b"OPTIONS rtsp://127.0.0.1 RTSP/1.0\r\nCSeq: 1\r\n\r\n", summary="RTSP OPTIONS")
    add("postgres-sslrequest", 5432, "tcp", "postgres", b"S", postgres_sslrequest, summary="SSLRequest")
    add("postgres-startup", 5432, "tcp", "postgres", b"R", postgres_startup, summary="startup message")
    add("mysql-ping", 3306, "tcp", "mysql", b"", mysql_ping, summary="COM_PING")
    add("mysql-query", 3306, "tcp", "mysql", b"", mysql_query, summary="COM_QUERY")
    add("mssql-prelogin", 1433, "tcp", "mssql", b"\x04", mssql_prelogin, summary="TDS PRELOGIN")
    add("smb1-negotiate", 139, "tcp", "smb1", b"\xffSMB", smb1_negotiate, summary="SMB1 NEGOTIATE")
    add("smb2-negotiate", 445, "tcp", "smb2", b"\xfeSMB", smb2_negotiate, summary="SMB2 NEGOTIATE")
    add("rpc-null", 111, "tcp", "portmapper", b"\x00\x00\x00\x01", rpc_null, summary="RPC NULL")
    add("rsync-modules", 873, "tcp", "rsync", b"@RSYNCD", lambda: b"@RSYNCD: 31.0\n", summary="version handshake")
    add("ftp-user", 21, "tcp", "ftp", b"331", lambda: b"USER anonymous\r\n", summary="USER anonymous")
    add("ssh-banner", 22, "tcp", "ssh", b"SSH-", lambda: b"", summary="server speaks first")
    add("telnet-negotiate", 23, "tcp", "telnet", b"\xff", lambda: b"\xff\xfd\x03\xff\xfb\x18\xff\xfb\x1f", summary="option negotiation")
    add("vnc-client", 5900, "tcp", "vnc", b"RFB", lambda: b"RFB 003.008\n", summary="client handshake")
    add("rdp-negotiate", 3389, "tcp", "rdp", b"\x03\x00", lambda: b"\x03\x00\x00\x13\x0e\xe0\x00\x00\x00\x00\x00\x01\x00\x08\x00\x03\x00\x00\x00", summary="TPKT + X.224")
    add("x11-setup", 6000, "tcp", "x11", b"\x01", lambda: b"l\x00\x0b\x00" + b"\x00" * 8, summary="X11 setup")
    add("socks5-greeting", 1080, "tcp", "socks5", b"\x05", lambda: b"\x05\x01\x00", summary="no-auth greeting")
    add("socks4-connect", 1080, "tcp", "socks4", b"\x00\x5a", lambda: b"\x04\x01\x00\x50\x7f\x00\x00\x01nightjar\x00", summary="SOCKS4 CONNECT")
    add("adb-version", 5555, "tcp", "adb", b"OKAY", adb_version, summary="host:version")
    add("ldap-anon-bind", 389, "tcp", "ldap", b"\x61", ldap_anon_bind, summary="anonymous bind")
    add("ldap-anon-bind-tls", 636, "tcp", "ldaps", b"\x61", ldap_anon_bind, tls=True, summary="anonymous bind over TLS")
    add("wol", 9, "udp", "wake-on-lan", b"", wol_magic, summary="magic packet")
    add("coap-get", 5683, "udp", "coap", b"\x60", coap_get, summary="GET /nightjar")
    add("modbus-read", 502, "tcp", "modbus", b"\x00\x01", modbus_read, summary="read holding registers")
    add("zabbix-agent", 10050, "tcp", "zabbix", b"ZBXD", zabbix_version, summary="agent.version")
    add("http-get", 80, "tcp", "http", b"HTTP/1.", http_get, summary="GET /")
    add("http-options", 80, "tcp", "http", b"HTTP/1.", lambda: _http("OPTIONS", "/"), summary="OPTIONS")
    add("http-head", 80, "tcp", "http", b"HTTP/1.", lambda: _http("HEAD", "/"), summary="HEAD /")
    add("http-trace", 80, "tcp", "http", b"HTTP/1.", lambda: _http("TRACE", "/"), summary="TRACE")
    add("https-get", 443, "tcp", "https", b"HTTP/1.", http_get, tls=True, summary="GET / over TLS")
    add("graphql-introspection", 80, "tcp", "graphql", b"__schema", graphql_introspection, summary="POST /graphql")
    add("http-proxy-get", 3128, "tcp", "http-proxy", b"HTTP/1.", lambda: _http("GET", "http://example.com/", host="example.com"), summary="open proxy test")
    add("http-connect", 3128, "tcp", "http-proxy", b"HTTP/1.", lambda: b"CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n", summary="CONNECT tunnel")
    add("docker-version", 2375, "tcp", "docker", b"ApiVersion", partial(http_get, "/version"), summary="GET /version")
    add("docker-version-tls", 2376, "tcp", "docker", b"ApiVersion", partial(http_get, "/version"), tls=True, summary="GET /version over TLS")
    add("docker-registry", 5000, "tcp", "docker-registry", b"200", partial(http_get, "/v2/"), summary="GET /v2/")
    add("kubernetes-version", 6443, "tcp", "kubernetes", b"gitVersion", partial(http_get, "/version"), tls=True, summary="GET /version")
    add("kubelet-health", 10250, "tcp", "kubelet", b"ok", partial(http_get, "/healthz"), tls=True, summary="GET /healthz")
    add("jenkins-api", 8080, "tcp", "jenkins", b"Jenkins", partial(http_get, "/api/json"), summary="GET /api/json")
    add("prometheus-metrics", 9090, "tcp", "prometheus", b"HELP", partial(http_get, "/metrics"), summary="GET /metrics")
    add("grafana-health", 3000, "tcp", "grafana", b"database", partial(http_get, "/api/health"), summary="GET /api/health")
    add("kibana-status", 5601, "tcp", "kibana", b"version", partial(http_get, "/api/status"), summary="GET /api/status")
    add("solr-admin", 8983, "tcp", "solr", b"lucene", partial(http_get, "/solr/admin/info/system"), summary="admin info")
    add("influxdb-ping", 8086, "tcp", "influxdb", b"204", lambda: b"GET /ping HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n", summary="GET /ping")
    add("minio-health", 9000, "tcp", "minio", b"200", partial(http_get, "/minio/health/live"), summary="health/live")
    add("neo4j-root", 7474, "tcp", "neo4j", b"neo4j", http_get, summary="GET /")
    add("gitea-version", 3000, "tcp", "gitea", b"version", partial(http_get, "/api/v1/version"), summary="GET /api/v1/version")
    add("gitlab-readiness", 80, "tcp", "gitlab", b"GitLab", partial(http_get, "/-/readiness"), summary="GET /-/readiness")
    add("echo", 7, "tcp", "echo", b"", lambda: b"", summary="nothing - echo")
    add("daytime", 13, "tcp", "daytime", b"", lambda: b"", summary="nothing")
    add("chargen", 19, "tcp", "chargen", b"", lambda: b"", summary="nothing")
    add("discard", 9, "tcp", "discard", b"", lambda: b"nightjar\r\n", summary="throw it away")
    add("whois", 43, "tcp", "whois", b"", lambda: b"example.com\r\n", summary="whois query")
    add("finger", 79, "tcp", "finger", b"", lambda: b"nightjar\r\n", summary="finger")
    add("gopher", 70, "tcp", "gopher", b"", lambda: b"nightjar\r\n", summary="gopher selector")
    add("gemini", 1965, "tcp", "gemini", b"20 ", lambda: b"gemini://nightjar/\r\n", summary="Gemini request")


_register()

PORT_PROBES: dict[int, str] = {
    7: "echo", 9: "discard", 13: "daytime", 19: "chargen", 21: "ftp-user",
    22: "ssh-banner", 23: "telnet-negotiate", 25: "smtp-ehlo", 43: "whois",
    53: "dns-version", 67: "dhcp-discover", 69: "tftp", 70: "gopher",
    79: "finger", 80: "http-get", 110: "pop3-capa", 111: "rpc-null",
    123: "ntp", 137: "nbns", 139: "smb1-negotiate", 143: "imap-capa",
    161: "snmp-sysdescr", 389: "ldap-anon-bind", 443: "https-get",
    445: "smb2-negotiate", 502: "modbus-read", 554: "rtsp-options",
    587: "smtp-ehlo", 636: "ldap-anon-bind-tls", 873: "rsync-modules",
    993: "imap-capa-tls", 995: "pop3-capa-tls", 1080: "socks5-greeting",
    1433: "mssql-prelogin", 1883: "mqtt-connect", 1965: "gemini",
    2181: "zookeeper-mntr", 2375: "docker-version", 2376: "docker-version-tls",
    2379: "etcd-version", 3000: "grafana-health", 3128: "http-proxy-get",
    3306: "mysql-ping", 3389: "rdp-negotiate", 5000: "docker-registry",
    5060: "sip-options", 5061: "sip-options-tls", 5432: "postgres-sslrequest",
    5555: "adb-version", 5601: "kibana-status", 5672: "amqp-header",
    5900: "vnc-client", 5984: "couchdb-root", 6000: "x11-setup",
    61613: "stomp-connect", 6379: "redis-ping", 6443: "kubernetes-version",
    7474: "neo4j-root", 8000: "http-get", 8080: "jenkins-api",
    8086: "influxdb-ping", 8200: "vault-health", 8443: "https-get",
    8500: "consul-leader", 8983: "solr-admin", 9000: "minio-health",
    9042: "cassandra-options", 9090: "prometheus-metrics",
    9200: "elasticsearch-root", 10050: "zabbix-agent",
    10250: "kubelet-health", 11211: "memcached-stats",
    15672: "rabbitmq-overview", 27017: "mongodb-ismaster",
}

PORT_PROBES_UDP: dict[int, str] = {
    9: "wol", 53: "dns-a", 67: "dhcp-discover", 69: "tftp", 123: "ntp",
    137: "nbns", 161: "snmp-sysdescr", 514: "syslog", 1900: "ssdp",
    3478: "stun", 5353: "dns-sd", 5355: "llmnr", 5683: "coap-get",
    51820: "wireguard",
}

DEFAULT_KNOCK_PORTS: tuple[int, ...] = tuple(sorted(PORT_PROBES))


def probe_names() -> list[str]:
    return sorted(PROBES)


def build_probe(name: str) -> bytes:
    probe = PROBES.get(name)
    if probe is None:
        near = [n for n in PROBES if name.lower() in n.lower()]
        hint = f" (did you mean {', '.join(near[:5])}?)" if near else ""
        raise KeyError(f"no preset {name!r}{hint}")
    return probe.build()


def probe_for_port(port: int, proto: str = "tcp") -> Probe | None:
    table = PORT_PROBES_UDP if proto == "udp" else PORT_PROBES
    name = table.get(port)
    return PROBES[name] if name else None


def describe(name: str) -> str:
    probe = PROBES[name]
    return f"{name:<24} {probe.proto}/{probe.port:<6} {probe.summary}"


def library() -> str:
    lines = [f"{len(PROBES)} protocol first words "
             f"({len(PORT_PROBES)} tcp ports, {len(PORT_PROBES_UDP)} udp)\n"]
    for name in probe_names():
        lines.append("  " + describe(name))
    return "\n".join(lines)


__all__ = [
    "Probe", "PROBES", "PORT_PROBES", "PORT_PROBES_UDP", "DEFAULT_KNOCK_PORTS",
    "build_probe", "probe_for_port", "probe_names", "library", "describe",
]
'''


# =============================================================================
# installer
# =============================================================================

FILES: dict[str, str] = {
    "ios/nightjar/ReconPayloads.swift": RECON_PAYLOADS_SWIFT,
    "ios/nightjar/ReconKit.swift": RECON_KIT_SWIFT,
    "ios/nightjar/ReconBenchView.swift": RECON_BENCH_VIEW_SWIFT,
    "ios/nightjarTests/ReconTests.swift": RECON_TESTS_SWIFT,
    "HACKER-RECON.md": HACKER_RECON_MD,
    "nightjar/payloads.py": PAYLOADS_PY,
}

APPENDS: dict[str, str] = {
    "ios/README.md": IOS_README_SECTION,
}

PATCHES: list[tuple[str, tuple[str, ...], str]] = [
    ("ios/nightjar/ContentView.swift",
     (CONTENTVIEW_OLD, CONTENTVIEW_OLD_ALT), CONTENTVIEW_NEW),
]


def patch_text(text: str, olds: tuple[str, ...], new: str) -> tuple[str, str]:
    if new in text and not any(old in text for old in olds):
        return text, "already"
    for old in olds:
        if old in text:
            if text.count(old) != 1:
                return text, f"ambiguous({text.count(old)})"
            return text.replace(old, new, 1), "patched"
    return text, "anchor-not-found"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="nightjar-recon-ios",
        description="Install the iOS recon tab and write the upload zip.")
    parser.add_argument("repo", nargs="?", default=str(HERE))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--zip-only", action="store_true")
    parser.add_argument("--out", default=ZIP_NAME)
    args = parser.parse_args(argv)

    repo = Path(args.repo).expanduser().resolve()
    if not (repo / "ios" / "nightjar").is_dir():
        print(f"not a nightjar-hack repo (no ios/nightjar under {repo})",
              file=sys.stderr)
        return 2
    write = not args.check and not args.zip_only
    print(f"nightjar-hack repo: {repo}"
          f"{'  [check only]' if args.check else ''}")

    bundle: dict[str, str] = {}
    problems = 0

    for relative, content in FILES.items():
        path = repo / relative
        exists = path.exists()
        if exists and path.read_text(encoding="utf-8") == content:
            print(f"  = {relative}")
        else:
            if write:
                path.parent.mkdir(parents=True, exist_ok=True)
                if exists:
                    backup = path.with_name(path.name + ".orig")
                    if not backup.exists():
                        shutil.copyfile(path, backup)
                path.write_text(content, encoding="utf-8")
            print(f"  {'~' if exists else '+'} {relative}")
        bundle[relative] = content

    for relative, section in APPENDS.items():
        path = repo / relative
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        marker = "## Recon (2.7.0)"
        if marker in text:
            print(f"  = {relative}")
            bundle[relative] = text
            continue
        updated = text.rstrip("\n") + "\n" + section
        if write:
            path.write_text(updated, encoding="utf-8")
        print(f"  ~ {relative}")
        bundle[relative] = updated

    for relative, olds, new in PATCHES:
        path = repo / relative
        if not path.exists():
            print(f"  ! {relative}: missing")
            problems += 1
            continue
        text = path.read_text(encoding="utf-8")
        updated, outcome = patch_text(text, olds, new)
        if outcome.startswith("anchor"):
            print(f"  ! {relative}: {outcome}")
            problems += 1
        elif outcome == "already":
            print(f"  = {relative}")
        else:
            if write:
                path.write_text(updated, encoding="utf-8")
            print(f"  ~ {relative}")
        bundle[relative] = updated

    zip_path = repo / args.out
    if not args.check:
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
            for relative in sorted(bundle):
                archive.writestr(relative, bundle[relative])
        print(f"\n  zip: {zip_path}  ({len(bundle)} files)")

    print()
    if problems:
        print(f"{problems} anchor(s) need a hand.")
    print("next:")
    print("  open ios/nightjar.xcodeproj in Xcode and press Run")
    print("  # the Recon tab is the last one, after About")
    print("  xcodebuild test -project ios/nightjar.xcodeproj "
          "-scheme nightjar -only-testing:nightjarTests/ReconTests")
    print(f"  # upload: extract {args.out} over the repo, or unzip and push")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
