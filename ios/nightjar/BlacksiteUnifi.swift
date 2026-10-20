import Foundation
import Security
import CryptoKit

/// The UniFi playbook — Netadmin Phase 4's
/// first vendor. It speaks to the operator's
/// OWN UniFi controller (UniFi OS on a Dream
/// Machine, or the classic controller) over
/// HTTPS, with the login the operator kept
/// for it (cred setunifi) and no other: no
/// default is ever tried, no word is ever
/// guessed. The controller's certificate is
/// pinned at first sight and a changed one
/// refused — the SSH host-key doctrine
/// carried over TLS, because a LAN
/// controller's self-signed papers are
/// exactly where a silent swap would live.
/// State-changing acts (restart, block,
/// unblock) are the console case's to
/// confirm with the operator before they
/// reach this client.
enum UnifiPlaybook {

    struct Failure: Error {
        let line: String
    }

    /// One logged-in controller session:
    /// the base that answered, the flavor,
    /// the CSRF token UniFi OS demands on
    /// writes, and the URLSession whose
    /// delegate enforces the pin.
    final class Session: NSObject,
        URLSessionDelegate {
        let host: String
        let base: URL
        let osFlavor: Bool
        var csrf: String?
        var pinNote: String?
        private(set) var session: URLSession!
        private var seenFingerprint: String?
        private var pinMismatch = false

        init(host: String, base: URL,
             osFlavor: Bool) {
            self.host = host
            self.base = base
            self.osFlavor = osFlavor
            super.init()
            let config =
                URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = true
            config.httpCookieAcceptPolicy =
                .always
            config.timeoutIntervalForRequest =
                20
            session = URLSession(
                configuration: config,
                delegate: self,
                delegateQueue: nil)
        }

        // MARK: The pin

        static func fingerprint(
            of trust: SecTrust) -> String? {
            guard let chain =
                SecTrustCopyCertificateChain(
                    trust) as? [SecCertificate],
                  let leaf = chain.first
            else { return nil }
            let der = SecCertificateCopyData(
                leaf) as Data
            return SHA256.hash(data: der)
                .map {
                    String(format: "%02x", $0)
                }.joined()
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge:
                URLAuthenticationChallenge,
            completionHandler:
                @escaping (
                    URLSession
                        .AuthChallengeDisposition,
                    URLCredential?) -> Void) {
            guard challenge.protectionSpace
                    .authenticationMethod
                    == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge
                    .protectionSpace.serverTrust,
                  let print = Self.fingerprint(
                    of: trust)
            else {
                completionHandler(
                    .cancelAuthenticationChallenge,
                    nil)
                return
            }
            seenFingerprint = print
            if let pinned = CryptoSuite
                .NetCred.unifiCert(host: host) {
                if pinned == print {
                    completionHandler(
                        .useCredential,
                        URLCredential(trust: trust))
                } else {
                    pinMismatch = true
                    completionHandler(
                        .cancelAuthenticationChallenge,
                        nil)
                }
            } else {
                completionHandler(
                    .useCredential,
                    URLCredential(trust: trust))
            }
        }

        /// After the first answered request:
        /// pin what was seen, if nothing is
        /// pinned yet, and say so once.
        func finishPin() {
            guard CryptoSuite.NetCred
                    .unifiCert(host: host)
                    == nil,
                  let print = seenFingerprint
            else { return }
            CryptoSuite.NetCred.keepUnifiCert(
                host: host, fingerprint: print)
            pinNote = "the controller's "
                + "certificate was pinned at "
                + "first sight — a changed "
                + "one will be refused."
        }

        // MARK: The wire

        /// One request, waited out on the
        /// caller's (background) thread.
        /// Returns the HTTP status and the
        /// decoded JSON object, if any.
        func call(_ method: String,
                  _ path: String,
                  _ body: [String: Any]? = nil)
            throws -> (Int, [String: Any]) {
            guard let url = URL(
                string: path,
                relativeTo: base)
            else {
                throw Failure(
                    line: "that address does "
                        + "not parse.")
            }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 20
            if let body = body {
                request.setValue(
                    "application/json",
                    forHTTPHeaderField:
                        "Content-Type")
                request.httpBody = try?
                    JSONSerialization.data(
                        withJSONObject: body)
            }
            if let csrf = csrf {
                request.setValue(
                    csrf,
                    forHTTPHeaderField:
                        "X-CSRF-Token")
            }
            var result: (Data, HTTPURLResponse)?
            var failure: Error?
            let gate = DispatchSemaphore(
                value: 0)
            let task = session.dataTask(
                with: request) {
                data, response, error in
                if let data = data,
                   let http = response
                    as? HTTPURLResponse {
                    result = (data, http)
                } else {
                    failure = error
                }
                gate.signal()
            }
            task.resume()
            _ = gate.wait(
                timeout: .now() + 25)
            if pinMismatch {
                throw Failure(
                    line: "the controller's "
                        + "certificate has "
                        + "CHANGED since it "
                        + "was pinned — "
                        + "refusing. If the "
                        + "controller was "
                        + "rebuilt on purpose, "
                        + "cred forget clears "
                        + "the pin with the "
                        + "login.")
            }
            guard let (data, http) = result
            else {
                throw Failure(
                    line: "the controller at "
                        + "\(host) did not "
                        + "answer — "
                        + (failure?
                            .localizedDescription
                           ?? "timed out."))
            }
            if csrf == nil,
               let token = http.value(
                forHTTPHeaderField:
                    "x-csrf-token") {
                csrf = token
            }
            var json: [String: Any] = [:]
            if let decoded = try?
                JSONSerialization.jsonObject(
                    with: data)
                as? [String: Any] {
                json = decoded
            }
            return (http.statusCode, json)
        }

        /// One controller API call under
        /// the site's root, with the
        /// controller's own verdict read:
        /// meta.rc must say ok.
        func api(_ method: String,
                 _ path: String,
                 _ body: [String: Any]? = nil)
            throws -> [[String: Any]] {
            let prefix = osFlavor
                ? "/proxy/network" : ""
            let (status, json) = try call(
                method,
                prefix + "/api/s/default"
                    + path, body)
            let meta = json["meta"]
                as? [String: Any]
            let rc = meta?["rc"] as? String
            guard status == 200, rc == "ok"
            else {
                let word = meta?["msg"]
                    as? String
                    ?? "HTTP \(status)"
                throw Failure(
                    line: "the controller "
                        + "refused: \(word)")
            }
            return json["data"]
                as? [[String: Any]] ?? []
        }

        // MARK: The playbook's verbs

        func devices() throws
            -> [[String: Any]] {
            try api("GET", "/stat/device")
        }

        func clients() throws
            -> [[String: Any]] {
            try api("GET", "/stat/sta")
        }

        func restart(mac: String) throws {
            _ = try api("POST", "/cmd/devmgr",
                        ["cmd": "restart",
                         "mac": mac])
        }

        func block(mac: String,
                   unblock: Bool) throws {
            _ = try api("POST", "/cmd/stamgr",
                        ["cmd": unblock
                            ? "unblock-sta"
                            : "block-sta",
                         "mac": mac])
        }
    }

    /// Log in. UniFi OS answers on 443 at
    /// /api/auth/login; the classic
    /// controller on 8443 at /api/login.
    /// An explicit port tries both flavors
    /// at that port. A changed certificate
    /// stops the whole attempt at once.
    static func login(host: String,
                      port: Int?,
                      user: String,
                      word: String)
        throws -> Session {
        let attempts: [(Int, Bool)]
        if let port = port {
            attempts = [(port, true),
                        (port, false)]
        } else {
            attempts = [(443, true),
                        (8443, false)]
        }
        var lastWord = "no controller "
            + "answered"
        for (port, os) in attempts {
            var baseText = "https://" + host
            if port != 443 {
                baseText += ":\(port)"
            }
            guard let base = URL(
                string: baseText)
            else { continue }
            let session = Session(
                host: host, base: base,
                osFlavor: os)
            do {
                let (status, json) =
                    try session.call(
                        "POST",
                        os ? "/api/auth/login"
                           : "/api/login",
                        ["username": user,
                         "password": word,
                         "remember": true])
                let meta = json["meta"]
                    as? [String: Any]
                if status == 200,
                   (meta?["rc"] as? String)
                    == "ok" {
                    session.finishPin()
                    return session
                }
                lastWord = (meta?["msg"]
                    as? String)
                    ?? "HTTP \(status)"
            } catch let failure as Failure {
                if failure.line.contains(
                    "CHANGED") {
                    throw failure
                }
                lastWord = failure.line
            }
        }
        throw Failure(
            line: "no UniFi controller at "
                + "\(host) took the kept "
                + "login (\(lastWord)) — "
                + "UniFi OS answers on 443, "
                + "the classic controller "
                + "on 8443.")
    }

    // MARK: Reading the records

    static func name(of record: [String: Any])
        -> String {
        for key in ["name", "alias",
                    "hostname"] {
            if let value = record[key]
                as? String,
               !value.isEmpty {
                return value
            }
        }
        return (record["mac"] as? String)
            ?? "unnamed"
    }

    static func macKey(_ mac: String)
        -> String {
        mac.lowercased()
            .filter {
                $0.isLetter || $0.isNumber
            }
    }

    /// Find one record by MAC or by name
    /// — exact first, then a unique
    /// partial name.
    static func resolve(
        _ target: String,
        in records: [[String: Any]])
        -> [String: Any]? {
        let wanted = macKey(target)
        let lowered = target.lowercased()
        for record in records {
            if let mac = record["mac"]
                as? String,
               macKey(mac) == wanted {
                return record
            }
            if name(of: record).lowercased()
                == lowered {
                return record
            }
        }
        let partial = records.filter {
            name(of: $0).lowercased()
                .contains(lowered)
        }
        return partial.count == 1
            ? partial.first : nil
    }

    static func deviceLine(
        _ device: [String: Any]) -> String {
        let kind = (device["type"]
            as? String) ?? "device"
        let model = (device["model"]
            as? String) ?? kind
        let version = (device["version"]
            as? String) ?? "?"
        let ip = (device["ip"] as? String)
            ?? "no address"
        let state = (device["state"]
            as? Int) ?? -1
        let word = state == 1
            ? "connected"
            : state == 0
                ? "down"
                : "state \(state)"
        return "\(name(of: device)) — "
            + "\(model), UniFi \(version), "
            + "\(ip), \(word)"
    }

    static func clientLine(
        _ client: [String: Any]) -> String {
        let ip = (client["ip"] as? String)
            ?? "no address"
        var line = "\(name(of: client)) — "
            + ip
        if let essid = client["essid"]
            as? String {
            line += ", on \(essid)"
        }
        if let signal = client["signal"]
            as? Int {
            line += ", \(signal) dBm"
        }
        if let wired = client["is_wired"]
            as? Bool, wired {
            line += ", wired"
        }
        return line
    }
}
