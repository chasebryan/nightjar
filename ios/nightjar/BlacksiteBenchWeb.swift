import Foundation
import Network
import Security

// BlacksiteBenchWeb — the bench, wave
// three (fix-wave: the web read, deep).
// Twenty-five more engines in the
// bench's manner: each is a single
// operator-fired run at an address the
// operator named, making the minimum
// fetches its question needs, reading
// what answers, and grading it in the
// open. Nothing here fires a payload,
// guesses a credential, or walks a
// wordlist — the doors knocked on are
// the ones sites publish for strangers.

extension BlacksiteBench {

    // MARK: shared plumbing

    /// Wave three speaks through the
    /// house emit; a kindless call
    /// reads .out.
    private static func webSay(
        _ emit: BlacksiteEmit,
        _ text: String,
        _ kind: BlacksiteShell.Line.Kind = .out) {
        emit(text, kind)
    }

    /// One fetch through the house web
    /// session — the verb's whole wire
    /// budget is spent in lines like
    /// this.
    private static func webFetch(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        follow: Bool = false)
        -> (Data, HTTPURLResponse)? {
        let (session, _) = BlacksitePentest
            .webSession(follow: follow)
        defer {
            session.invalidateAndCancel()
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue(
            BlacksiteNet.userAgent,
            forHTTPHeaderField: "User-Agent")
        for (name, value) in headers {
            request.setValue(
                value, forHTTPHeaderField: name)
        }
        if let body = body {
            request.httpBody = body
        }
        guard let (data, http) =
            BlacksitePentest.syncFetch(
                session, request),
              let http = http else {
            return nil
        }
        return (data, http)
    }

    /// The target URL, or the verb's
    /// complaint already half-formed:
    /// callers guard on this.
    private static func webTarget(
        _ text: String) -> URL? {
        BlacksitePentest.normalizedURL(text)
    }

    /// A sibling path on the same
    /// house — /robots.txt of a URL,
    /// whatever its own path was.
    private static func webSibling(
        _ url: URL, _ path: String) -> URL? {
        var comps = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false)
        comps?.path = path
        comps?.query = nil
        comps?.fragment = nil
        return comps?.url
    }

    /// The response's headers as a
    /// lowercased map (webaudit's way).
    private static func webHeaders(
        _ http: HTTPURLResponse)
        -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in http
            .allHeaderFields {
            out[String(describing: key)
                .lowercased()] =
                String(describing: value)
        }
        return out
    }

    /// The cookies of one answer, split
    /// out of the combined header — an
    /// Expires date carries a comma, so
    /// a piece with no '=' rejoins the
    /// cookie before it.
    private static func webCookies(
        _ http: HTTPURLResponse)
        -> [String] {
        guard let combined = http.value(
            forHTTPHeaderField: "Set-Cookie")
        else { return [] }
        var out: [String] = []
        for piece in combined.components(
            separatedBy: ", ") {
            if piece.contains("=")
                || out.isEmpty {
                out.append(piece)
            } else {
                out[out.count - 1] +=
                    ", " + piece
            }
        }
        return out
    }

    // MARK: the papers — trust and DER

    /// Shake the TLS hand and keep the
    /// papers it shows (the cert
    /// engine's own road).
    private static func webTrust(
        host: String, port: Int)
        -> SecTrust? {
        let probe = CertProbe()
        let config = URLSessionConfiguration
            .ephemeral
        config.timeoutIntervalForRequest =
            12
        let session = URLSession(
            configuration: config,
            delegate: probe,
            delegateQueue: OperationQueue())
        guard let url = URL(
            string: "https://\(host)"
            + ":\(port)/") else {
            return nil
        }
        let semaphore = DispatchSemaphore(
            value: 0)
        let task = session.dataTask(
            with: url) { _, _, _ in
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(
            timeout: .now() + 15)
        session.invalidateAndCancel()
        return probe.trust
    }

    /// Host and port out of a URL or a
    /// bare name — the cert family's
    /// shared parsing.
    private static func webCertTarget(
        _ text: String)
        -> (host: String, port: Int)? {
        guard let url = BlacksitePentest
            .normalizedURL(text),
              let host = url.host else {
            return nil
        }
        return (host, url.port ?? 443)
    }

    /// One extension's payload bytes,
    /// walked from the DER the way
    /// certSANs walks: the [3] wrapper
    /// holds the extensions sequence,
    /// each a sequence whose first
    /// child names it.
    private static func webCertExtension(
        _ cert: SecCertificate,
        _ oid: String) -> [UInt8]? {
        guard let tbs = BlacksitePentest
            .certTBS(cert) else {
            return nil
        }
        var kids = BlacksitePentest
            .berChildren(tbs)
        if kids.first?.0 == 0xA0 {
            kids.removeFirst()
        }
        guard let wrapper = kids.first(
                where: { $0.0 == 0xA3 }),
              let extSeq = BlacksitePentest
                .berChildren(wrapper.1).first,
              extSeq.0 == 0x30 else {
            return nil
        }
        for ext in BlacksitePentest
            .berChildren(extSeq.1) {
            guard ext.0 == 0x30 else {
                continue
            }
            let fields = BlacksitePentest
                .berChildren(ext.1)
            guard fields.count >= 2,
                  fields[0].0 == 0x06,
                  BlacksitePentest
                    .berDecodeOID(fields[0].1)
                    == oid,
                  let payload = fields.last,
                  payload.0 == 0x04 else {
                continue
            }
            return payload.1
        }
        return nil
    }

    /// The TBS children after the
    /// version tag is skipped: serial,
    /// algorithm, issuer, validity,
    /// subject, public key.
    private static func webTBSKids(
        _ cert: SecCertificate)
        -> [(UInt8, [UInt8])] {
        guard let tbs = BlacksitePentest
            .certTBS(cert) else {
            return []
        }
        var kids = BlacksitePentest
            .berChildren(tbs)
        if kids.first?.0 == 0xA0 {
            kids.removeFirst()
        }
        return kids
    }

    /// One field of a certificate name
    /// (issuer's or subject's), read
    /// out of its RDN sets.
    private static func webCertName(
        _ cert: SecCertificate,
        issuer: Bool,
        oid: String) -> String? {
        let kids = webTBSKids(cert)
        let index = issuer ? 2 : 4
        guard kids.count > index,
              kids[index].0 == 0x30 else {
            return nil
        }
        for set in BlacksitePentest
            .berChildren(kids[index].1)
            where set.0 == 0x31 {
            for pair in BlacksitePentest
                .berChildren(set.1)
                where pair.0 == 0x30 {
                let fields = BlacksitePentest
                    .berChildren(pair.1)
                guard fields.count == 2,
                      fields[0].0 == 0x06,
                      BlacksitePentest
                        .berDecodeOID(
                            fields[0].1) == oid
                else { continue }
                let value = fields[1]
                if value.0 == 0x0C
                    || value.0 == 0x13
                    || value.0 == 0x16 {
                    return String(
                        bytes: value.1,
                        encoding: .utf8)
                }
            }
        }
        return nil
    }

    /// The signature algorithm's OID,
    /// from the TBS's second child.
    private static func webCertSigOID(
        _ cert: SecCertificate)
        -> String? {
        let kids = webTBSKids(cert)
        guard kids.count > 1,
              kids[1].0 == 0x30,
              let first = BlacksitePentest
                .berChildren(kids[1].1).first,
              first.0 == 0x06 else {
            return nil
        }
        return BlacksitePentest
            .berDecodeOID(first.1)
    }

    /// The public key, named and sized
    /// from the subjectPublicKeyInfo.
    private static func webCertKey(
        _ cert: SecCertificate)
        -> String? {
        let kids = webTBSKids(cert)
        guard kids.count > 5,
              kids[5].0 == 0x30 else {
            return nil
        }
        let fields = BlacksitePentest
            .berChildren(kids[5].1)
        guard fields.count == 2,
              fields[0].0 == 0x30,
              fields[1].0 == 0x03 else {
            return nil
        }
        let alg = BlacksitePentest
            .berChildren(fields[0].1)
        guard let algOID = alg.first,
              algOID.0 == 0x06 else {
            return nil
        }
        let oid = BlacksitePentest
            .berDecodeOID(algOID.1)
        if oid == "1.2.840.113549.1.1.1" {
            var keyBytes = fields[1].1
            if !keyBytes.isEmpty {
                keyBytes.removeFirst()
            }
            guard let seq = BlacksitePentest
                .berRead(keyBytes, at: 0),
                  seq.0 == 0x30,
                  let modulus = BlacksitePentest
                    .berChildren(seq.1).first,
                  modulus.0 == 0x02 else {
                return nil
            }
            var body = modulus.1
            while body.first == 0
                && body.count > 1 {
                body.removeFirst()
            }
            return String(format: L("RSA — a %lld-bit modulus"), body.count * 8)
        }
        if oid == "1.2.840.10045.2.1" {
            var curve = L("an unnamed curve")
            if alg.count > 1,
               alg[1].0 == 0x06 {
                let curveOID =
                    BlacksitePentest
                        .berDecodeOID(alg[1].1)
                switch curveOID {
                case "1.2.840.10045.3.1.7":
                    curve = "P-256"
                case "1.3.132.0.34":
                    curve = "P-384"
                case "1.3.132.0.35":
                    curve = "P-521"
                default:
                    curve = curveOID
                }
            }
            return String(format: L("EC — %@"), curve)
        }
        return oid
    }

    /// The AIA extension's doors:
    /// (method OID, URI) pairs — the
    /// OCSP responder and the issuer's
    /// own papers live here.
    private static func webAIADoors(
        _ cert: SecCertificate)
        -> [(String, String)] {
        guard let payload =
            webCertExtension(
                cert, "1.3.6.1.5.5.7.1.1"),
              let seq = BlacksitePentest
                .berRead(payload, at: 0),
              seq.0 == 0x30
        else { return [] }
        var out: [(String, String)] = []
        for desc in BlacksitePentest
            .berChildren(seq.1)
            where desc.0 == 0x30 {
            let fields = BlacksitePentest
                .berChildren(desc.1)
            guard fields.count == 2,
                  fields[0].0 == 0x06 else {
                continue
            }
            let method = BlacksitePentest
                .berDecodeOID(fields[0].1)
            let loc = fields[1]
            if loc.0 == 0x86,
               let uri = String(
                    bytes: loc.1,
                    encoding: .ascii) {
                out.append((method, uri))
            }
        }
        return out
    }

    // MARK: faviconhash's arithmetic

    /// MurmurHash3 x86_32 — the
    /// fingerprint the hunting engines
    /// match favicons by, computed the
    /// same way here.
    private static func webMurmur3(
        _ data: Data) -> UInt32 {
        let bytes = [UInt8](data)
        var h: UInt32 = 0
        let c1: UInt32 = 0xcc9e2d51
        let c2: UInt32 = 0x1b873593
        let blocks = bytes.count / 4
        for i in 0..<blocks {
            var k = UInt32(bytes[i * 4])
                | UInt32(bytes[i * 4 + 1]) << 8
                | UInt32(bytes[i * 4 + 2]) << 16
                | UInt32(bytes[i * 4 + 3]) << 24
            k = k &* c1
            k = (k << 15) | (k >> 17)
            k = k &* c2
            h ^= k
            h = (h << 13) | (h >> 19)
            h = h &* 5 &+ 0xe6546b64
        }
        let tail = Array(
            bytes[(blocks * 4)...])
        var k: UInt32 = 0
        if tail.count == 3 {
            k ^= UInt32(tail[2]) << 16
        }
        if tail.count >= 2 {
            k ^= UInt32(tail[1]) << 8
        }
        if tail.count >= 1 {
            k ^= UInt32(tail[0])
            k = k &* c1
            k = (k << 15) | (k >> 17)
            k = k &* c2
            h ^= k
        }
        h ^= UInt32(bytes.count)
        h ^= h >> 16
        h = h &* 0x85ebca6b
        h ^= h >> 13
        h = h &* 0xc2b2ae35
        h ^= h >> 16
        return h
    }

    // MARK: the header family

    /// headersdeep <url> — every
    /// header the house answers with,
    /// printed whole. webaudit grades
    /// a checklist; this is the census
    /// behind the checklist.
    static func headersdeep(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("headersdeep: give a URL — headersdeep https://example.com"), .err)
                return
            }
            guard let (_, http) = webFetch(target, follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            webSay(emit, String(format: L("HTTP %lld — the whole answer, header by header"), http.statusCode), .sys)
            let headers = webHeaders(http)
            for name in headers.keys.sorted() {
                guard let value = headers[name] else { continue }
                let shown = value.count > 140 ? String(value.prefix(140)) + "…" : value
                webSay(emit, String(format: L("  %@: %@"), name, shown))
            }
            webSay(emit, String(format: L("%lld headers on the answer"), headers.count), .sys)
            if let server = headers["server"],
               server.range(of: "[0-9]/", options: .regularExpression) != nil {
                webSay(emit, String(format: L("the server banner carries a version — '%@' is a fingerprint any hunter can match"), server), .err)
            }
            if headers["x-powered-by"] != nil {
                webSay(emit, L("x-powered-by is showing — the stack names itself to strangers"), .err)
            }
            if headers["via"] != nil || headers["x-cache"] != nil {
                webSay(emit, L("a middleman signed the answer (via / x-cache) — a proxy or cache stands in front of this house"))
            }
            webSay(emit, L("read them all: most houses leak more in this list than in any page"), .sys)
        }
    }

    /// cookieaudit <url> — every
    /// cookie the house sets, and the
    /// promises each one keeps or
    /// breaks: Secure, HttpOnly,
    /// SameSite, the __Host- rules.
    static func cookieaudit(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("cookieaudit: give a URL — cookieaudit https://example.com"), .err)
                return
            }
            guard let (_, http) = webFetch(target) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let jars = webCookies(http)
            guard !jars.isEmpty else {
                webSay(emit, L("the house sets no cookies on this answer"), .sys)
                return
            }
            let https = target.scheme == "https"
            var unguarded = 0
            for raw in jars {
                let parts = raw.components(separatedBy: ";")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = parts.first, let eq = first.firstIndex(of: "=") else { continue }
                let name = String(first[..<eq])
                let attrs = parts.dropFirst().map { $0.lowercased() }
                let secure = attrs.contains("secure")
                let httpOnly = attrs.contains("httponly")
                var sameSite = L("unset")
                for attr in attrs where attr.hasPrefix("samesite=") {
                    sameSite = String(attr.dropFirst("samesite=".count))
                }
                let persistent = attrs.contains(where: { $0.hasPrefix("expires=") || $0.hasPrefix("max-age=") })
                webSay(emit, String(format: L("cookie %@: Secure %@, HttpOnly %@, SameSite %@, %@"),
                                    name,
                                    secure ? L("yes") : L("NO"),
                                    httpOnly ? L("yes") : L("NO"),
                                    sameSite,
                                    persistent ? L("kept past the session") : L("dies with the session")))
                if https && !secure {
                    unguarded += 1
                    webSay(emit, String(format: L("  %@: no Secure flag — this cookie will ride plain http too"), name), .err)
                }
                if !httpOnly {
                    unguarded += 1
                    webSay(emit, String(format: L("  %@: no HttpOnly — any script in the page can read it"), name), .err)
                }
                if sameSite == L("unset") {
                    webSay(emit, String(format: L("  %@: SameSite unset — the browser's default is the only guard"), name))
                }
                if name.hasPrefix("__Host-") && (!secure || attrs.contains(where: { $0.hasPrefix("domain=") }) || !attrs.contains("path=/")) {
                    webSay(emit, String(format: L("  %@: wears the __Host- name but breaks its rules (Secure, Path=/, no Domain) — browsers will refuse it"), name), .err)
                }
                if name.hasPrefix("__Secure-") && !secure {
                    webSay(emit, String(format: L("  %@: wears the __Secure- name without the Secure flag — browsers will refuse it"), name), .err)
                }
            }
            if unguarded == 0 {
                webSay(emit, L("every cookie keeps its promises"), .ok)
            } else {
                webSay(emit, String(format: L("%lld cookie promises broken"), unguarded), .err)
            }
        }
    }

    /// cacheprobe <url> — how the
    /// house tells caches to treat the
    /// answer, and whether shared
    /// caches may keep it.
    static func cacheprobe(url: String,
                           emit: @escaping BlacksiteEmit,
                           done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("cacheprobe: give a URL — cacheprobe https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(target, follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            let control = headers["cache-control"] ?? ""
            webSay(emit, String(format: L("HTTP %lld, %lld bytes"), http.statusCode, data.count), .sys)
            if control.isEmpty {
                webSay(emit, L("no Cache-Control at all — every cache invents its own rule for this answer"), .err)
            } else {
                webSay(emit, String(format: L("Cache-Control: %@"), control))
            }
            let lowered = control.lowercased()
            if lowered.contains("no-store") {
                webSay(emit, L("no-store: no cache may keep this — the strictest word there is"), .ok)
            }
            if lowered.contains("private") {
                webSay(emit, L("private: shared caches must not keep it; the visitor's own browser may"))
            }
            if lowered.contains("public") {
                webSay(emit, L("public: any cache on the road may keep and re-serve this answer"))
            }
            if let spot = lowered.range(of: "max-age=") {
                let digits = lowered[spot.upperBound...].prefix(while: { $0.isNumber })
                if let age = Int(String(digits)) {
                    webSay(emit, String(format: L("max-age %lld seconds — the answer may be re-served stale for %lld days"), age, age / 86400))
                }
            }
            if let etag = headers["etag"] {
                webSay(emit, String(format: L("ETag: %@ — revalidation rides on this fingerprint"), etag))
            }
            if let modified = headers["last-modified"] {
                webSay(emit, String(format: L("Last-Modified: %@"), modified))
            }
            if let expires = headers["expires"] {
                webSay(emit, String(format: L("Expires: %@"), expires))
            }
            if let age = headers["age"] {
                webSay(emit, String(format: L("Age: %@ — a cache in front has already held this answer that long"), age))
            }
            if let vary = headers["vary"] {
                webSay(emit, String(format: L("Vary: %@ — caches key their copies on these"), vary))
            }
            if headers["x-cache"] != nil || headers["cf-cache-status"] != nil {
                webSay(emit, String(format: L("a CDN answers here (x-cache %@)"),
                                    headers["cf-cache-status"] ?? headers["x-cache"] ?? ""))
            }
            webSay(emit, L("a page with secrets wants no-store; a page anyone may keep wants a long public max-age — anything between is a shrug caches will decide for you"), .sys)
        }
    }

    /// wafdetect <url> — which
    /// shield, if any, shows its badge
    /// on an ordinary knock. Nothing
    /// hostile is sent; most shields
    /// sign their work.
    static func wafdetect(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("wafdetect: give a URL — wafdetect https://example.com"), .err)
                return
            }
            guard let (_, http) = webFetch(target, follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            var badges: [String] = []
            if headers["cf-ray"] != nil || (headers["server"] ?? "").lowercased().contains("cloudflare") {
                badges.append("Cloudflare")
            }
            if headers["x-sucuri-id"] != nil || headers["x-sucuri-cache"] != nil {
                badges.append("Sucuri")
            }
            if headers["x-akamai-transformed"] != nil || headers["akamai-grn"] != nil {
                badges.append("Akamai")
            }
            if headers["x-amzn-requestid"] != nil || headers["x-amz-cf-id"] != nil {
                badges.append("AWS (CloudFront / ALB)")
            }
            if headers["x-azure-ref"] != nil {
                badges.append("Azure Front Door")
            }
            if headers["x-fastly-request-id"] != nil || (headers["server"] ?? "").lowercased().contains("fastly") {
                badges.append("Fastly")
            }
            if headers["x-datadome"] != nil {
                badges.append("DataDome")
            }
            if headers["x-perimeterx"] != nil {
                badges.append("PerimeterX / HUMAN")
            }
            let cookieNames = webCookies(http).map { jar in
                String(jar.prefix(while: { $0 != "=" })).lowercased()
            }
            if cookieNames.contains(where: { $0.hasPrefix("__cf") || $0 == "_cfuvid" }) {
                badges.append(L("Cloudflare (its cookies ride along)"))
            }
            if cookieNames.contains(where: { $0.hasPrefix("ak_bmsc") || $0.hasPrefix("bm_") }) {
                badges.append(L("Akamai Bot Manager (its cookies ride along)"))
            }
            if cookieNames.contains(where: { $0.hasPrefix("incap_") || $0.hasPrefix("visid_incap") }) {
                badges.append("Imperva Incapsula")
            }
            if cookieNames.contains(where: { $0.hasPrefix("awsalb") }) {
                badges.append("AWS Application Load Balancer")
            }
            guard !badges.isEmpty else {
                webSay(emit, L("no shield shows a badge on an ordinary knock — there may be none, or it keeps its name to itself"), .sys)
                return
            }
            for badge in badges {
                webSay(emit, String(format: L("badge: %@"), badge))
            }
            webSay(emit, L("a badge is not the shield's strength — only its signature. What it stops is another day's question"), .sys)
        }
    }

    /// techstack <url> — the stack,
    /// fingerprinted from what the
    /// answer itself gives away:
    /// headers, cookies, and the
    /// shapes in the page.
    static func techstack(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("techstack: give a URL — techstack https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(target, follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            let body = String(decoding: data, as: UTF8.self)
            let low = body.lowercased()
            var found: [(String, String)] = []
            if let server = headers["server"] {
                found.append((L("server"), server))
            }
            if let powered = headers["x-powered-by"] {
                found.append((L("powered by"), powered))
            }
            if let aspnet = headers["x-aspnet-version"] ?? headers["x-aspnetmvc-version"] {
                found.append(("ASP.NET", aspnet))
            }
            if let generator = headers["x-generator"] {
                found.append((L("generator"), generator))
            }
            if low.contains("wp-content") || low.contains("wp-includes") {
                found.append(("WordPress", L("the page loads wp-content / wp-includes")))
            }
            if low.contains("cdn.shopify.com") || low.contains("shopify") && low.contains("myshopify") {
                found.append(("Shopify", L("the page rides Shopify's CDN")))
            }
            if low.contains("/_next/") || low.contains("__next_data__") {
                found.append(("Next.js", L("the page carries _next assets")))
            }
            if low.contains("data-reactroot") || low.contains("react-dom") {
                found.append(("React", L("the page carries React's marks")))
            }
            if low.contains("ng-version") || low.contains("ng-app") {
                found.append(("Angular", L("the page carries Angular's marks")))
            }
            if low.contains("drupal-settings-json") || low.contains("sites/default/files") {
                found.append(("Drupal", L("the page carries Drupal's marks")))
            }
            if low.contains("static.parastorage.com") || low.contains("wixstatic") {
                found.append(("Wix", L("the page rides Wix's CDN")))
            }
            if low.contains("squarespace") {
                found.append(("Squarespace", L("the page names Squarespace")))
            }
            if low.contains("ghost/") && low.contains("content=\"ghost") || low.contains("generator\" content=\"ghost") {
                found.append(("Ghost", L("the page names Ghost as its generator")))
            }
            if let genAt = low.range(of: "name=\"generator\" content=\"") {
                let tail = low[genAt.upperBound...]
                if let end = tail.firstIndex(of: "\"") {
                    found.append((L("generator meta"), String(tail[..<end])))
                }
            }
            let cookieNames = webCookies(http).map { jar in
                String(jar.prefix(while: { $0 != "=" }))
            }
            for name in cookieNames {
                switch name {
                case "PHPSESSID":
                    found.append(("PHP", L("a PHPSESSID cookie")))
                case "JSESSIONID":
                    found.append(("Java (servlet)", L("a JSESSIONID cookie")))
                case "ASP.NET_SessionId":
                    found.append(("ASP.NET", L("a session cookie in its shape")))
                case "laravel_session":
                    found.append(("Laravel", L("a laravel_session cookie")))
                case "csrftoken":
                    found.append(("Django", L("a csrftoken cookie — Django's tell")))
                case "_session_id":
                    found.append(("Ruby on Rails", L("a _session_id cookie")))
                default:
                    if name.hasPrefix("wordpress_") {
                        found.append(("WordPress", L("a wordpress_ cookie")))
                    }
                }
            }
            guard !found.isEmpty else {
                webSay(emit, L("the house keeps its stack to itself — no header, cookie, or page mark names it"), .sys)
                return
            }
            var seen = Set<String>()
            for (name, evidence) in found where !seen.contains(name) {
                seen.insert(name)
                webSay(emit, String(format: L("%@: %@"), name, evidence))
            }
            webSay(emit, L("a stack named is a stack matched against every known hole in it — quiet houses make hunters guess"), .sys)
        }
    }

    /// sitemap <url> — the house's
    /// own map of itself, followed
    /// through its index.
    static func sitemap(url: String,
                        emit: @escaping BlacksiteEmit,
                        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let mapURL = webSibling(target, "/sitemap.xml")
            else {
                webSay(emit, L("sitemap: give a URL — sitemap https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(mapURL), http.statusCode == 200 else {
                webSay(emit, L("no /sitemap.xml answers — the house publishes no map of itself"), .sys)
                return
            }
            let xml = String(decoding: data, as: UTF8.self)
            func locs(_ text: String) -> [String] {
                var out: [String] = []
                var rest = Substring(text)
                while let open = rest.range(of: "<loc>"),
                      let close = rest.range(of: "</loc>", range: open.upperBound..<rest.endIndex) {
                    out.append(String(rest[open.upperBound..<close.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines))
                    rest = rest[close.upperBound...]
                }
                return out
            }
            var pages = locs(xml)
            var total = pages.count
            if xml.contains("<sitemapindex") {
                let children = pages
                total = 0
                pages = []
                webSay(emit, String(format: L("an index of %lld child maps — reading the first three"), children.count), .sys)
                for child in children.prefix(3) {
                    guard let childURL = URL(string: child),
                          let (childData, childHTTP) = webFetch(childURL),
                          childHTTP.statusCode == 200 else { continue }
                    let childPages = locs(String(decoding: childData, as: UTF8.self))
                    total += childPages.count
                    if pages.count < 15 {
                        pages.append(contentsOf: childPages.prefix(15 - pages.count))
                    }
                }
            }
            for page in pages.prefix(15) {
                webSay(emit, String(format: L("  %@"), page))
            }
            if total > 15 {
                webSay(emit, String(format: L("  … %lld mapped URLs in all"), total))
            } else {
                webSay(emit, String(format: L("%lld mapped URLs in all"), total), .sys)
            }
            webSay(emit, L("the map is written for search engines — it is also the truest list of what the house admits exists"), .sys)
        }
    }

    /// faviconhash <url> — the little
    /// icon, fingerprinted the way the
    /// hunting engines fingerprint it:
    /// MurmurHash3 of the raw bytes.
    static func faviconhash(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("faviconhash: give a URL — faviconhash https://example.com"), .err)
                return
            }
            var iconData: Data? = nil
            var iconFrom = "/favicon.ico"
            if let iconURL = webSibling(target, "/favicon.ico"),
               let (data, http) = webFetch(iconURL), http.statusCode == 200 {
                iconData = data
            }
            if iconData == nil, let (page, pageHTTP) = webFetch(target, follow: true),
               pageHTTP.statusCode == 200 {
                let html = String(decoding: page, as: UTF8.self)
                let low = html.lowercased()
                if let relAt = low.range(of: "rel=\"icon\"") ?? low.range(of: "rel=\"shortcut icon\"") ?? low.range(of: "rel='icon'") {
                    let window = low[relAt.lowerBound...].prefix(300)
                    let doubleQuoted = window.range(of: "href=\"")
                    let hrefAt = doubleQuoted ?? window.range(of: "href='")
                    if let hrefAt = hrefAt {
                        let quote: Character = doubleQuoted != nil ? "\"" : "'"
                        let tail = window[hrefAt.upperBound...]
                        if let end = tail.firstIndex(of: quote) {
                            let href = String(tail[..<end])
                            if let iconURL = URL(string: href, relativeTo: target)?.absoluteURL,
                               let (data, http) = webFetch(iconURL), http.statusCode == 200 {
                                iconData = data
                                iconFrom = href
                            }
                        }
                    }
                }
            }
            guard let data = iconData else {
                webSay(emit, L("no favicon answers — the house wears no badge, or hides it well"), .sys)
                return
            }
            let hash = Int64(Int32(bitPattern: webMurmur3(data)))
            webSay(emit, String(format: L("favicon (%@): %lld bytes"), iconFrom, data.count), .sys)
            webSay(emit, String(format: L("MurmurHash3: %lld"), hash))
            webSay(emit, L("that number is the badge hunters search the whole internet by — every house wearing it runs the same thing"), .sys)
        }
    }

    // MARK: the wire's own words

    /// Speak one plain HTTP request by
    /// hand — over a bare socket, or
    /// inside TLS — and keep the status
    /// line the house answers with.
    /// HTTP/2 rides binary framing and
    /// ALPN this read does not speak;
    /// what returns here is the 1.x
    /// answer, honestly come by.
    private static func webRawStatus(
        host: String, port: Int,
        tls: Bool, version: String)
        -> String? {
        guard let nwPort = NWEndpoint.Port(
            rawValue: UInt16(clamping: port))
        else { return nil }
        let params: NWParameters = tls
            ? NWParameters(tls: NWProtocolTLS.Options())
            : NWParameters.tcp
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort, using: params)
        let semaphore = DispatchSemaphore(
            value: 0)
        var text = ""
        connection.stateUpdateHandler = {
            state in
            switch state {
            case .ready:
                let asked = "GET / HTTP/"
                    + version + "\r\n"
                    + "Host: " + host + "\r\n"
                    + "User-Agent: \(BlacksiteNet.userAgent)\r\n"
                    + "Connection: close\r\n\r\n"
                connection.send(
                    content: Data(asked.utf8),
                    completion: .contentProcessed {
                        _ in
                        connection.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: 16384) {
                            data, _, _, _ in
                            if let data = data {
                                text = String(
                                    decoding: data,
                                    as: UTF8.self)
                            }
                            semaphore.signal()
                        }
                    })
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(
            label: "nightjar.webraw"))
        _ = semaphore.wait(
            timeout: .now() + 8)
        connection.cancel()
        let line = text
            .components(separatedBy: "\r\n")
            .first ?? ""
        return line.isEmpty ? nil : line
    }

    /// httpversion <url> — which HTTP
    /// the house actually speaks, read
    /// off its own status lines, plain
    /// door and TLS door alike.
    static func httpversion(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let host = target.host else {
                webSay(emit, L("httpversion: give a URL — httpversion https://example.com"), .err)
                return
            }
            let plainPort = target.port ?? 80
            if let line = webRawStatus(host: host, port: plainPort, tls: false, version: "1.1") {
                webSay(emit, String(format: L("plain door: %@"), line))
                if line.hasPrefix("HTTP/1.0") {
                    webSay(emit, L("the plain door leads with HTTP/1.0 — an old dialect, kept for old clients"), .err)
                }
            } else {
                webSay(emit, L("the plain door does not answer HTTP at all"))
            }
            if let line = webRawStatus(host: host, port: plainPort, tls: false, version: "1.0") {
                let token = line.components(separatedBy: " ").first ?? line
                webSay(emit, String(format: L("asked in HTTP/1.0, answered %@ — the old dialect still works here"), token))
            }
            let tlsPort = target.port ?? 443
            if target.scheme == "https" || target.port == nil {
                if let line = webRawStatus(host: host, port: tlsPort, tls: true, version: "1.1") {
                    webSay(emit, String(format: L("TLS door: %@"), line))
                } else {
                    webSay(emit, L("the TLS door would not speak plain 1.1 to this knock"))
                }
                webSay(emit, L("HTTP/2 and HTTP/3 ride ALPN and binary frames this read does not speak — the 1.x answers above are what a hand knock can prove"), .sys)
            }
        }
    }

    /// hstsprobe <url> — the promise
    /// that browsers must only ever
    /// come back over TLS, graded:
    /// set or not, long or short,
    /// subdomains or not — and whether
    /// the plain door gives the first
    /// visit away.
    static func hstsprobe(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let host = target.host else {
                webSay(emit, L("hstsprobe: give a URL — hstsprobe https://example.com"), .err)
                return
            }
            guard let (_, http) = webFetch(target) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            if target.scheme != "https" {
                webSay(emit, L("the target itself is plain http — HSTS is a promise only an https answer can make"), .err)
            }
            if let hsts = headers["strict-transport-security"] {
                webSay(emit, String(format: L("Strict-Transport-Security: %@"), hsts))
                let low = hsts.lowercased()
                if let spot = low.range(of: "max-age=") {
                    let digits = low[spot.upperBound...].prefix(while: { $0.isNumber })
                    if let age = Int(String(digits)) {
                        if age == 0 {
                            webSay(emit, L("max-age 0 — the promise is being WITHDRAWN; browsers will forget it"), .err)
                        } else if age < 15552000 {
                            webSay(emit, String(format: L("max-age %lld seconds (%lld days) — under the 180-day floor the graders want"), age, age / 86400), .err)
                        } else {
                            webSay(emit, String(format: L("max-age %lld seconds (%lld days) — a long memory"), age, age / 86400), .ok)
                        }
                    }
                } else {
                    webSay(emit, L("no max-age in the header — a promise with no term is no promise"), .err)
                }
                if low.contains("includesubdomains") {
                    webSay(emit, L("includeSubDomains: every subdomain is under the same promise"), .ok)
                } else {
                    webSay(emit, L("no includeSubDomains — subdomains fend for themselves"))
                }
                if low.contains("preload") {
                    webSay(emit, L("preload is declared — the house asks to be born into browsers' lists"))
                }
            } else {
                webSay(emit, L("no Strict-Transport-Security header — nothing stops a browser's first plain-http visit from being intercepted"), .err)
            }
            if let plainURL = URL(string: "http://\(host)/"),
               let (_, plainHTTP) = webFetch(plainURL) {
                let location = webHeaders(plainHTTP)["location"] ?? ""
                if plainHTTP.statusCode >= 300 && plainHTTP.statusCode < 400 && location.hasPrefix("https://") {
                    webSay(emit, L("the plain door redirects to https — the first visit is at least hurried indoors"), .ok)
                } else if plainHTTP.statusCode == 200 {
                    webSay(emit, L("the plain door serves the page itself, unredirected — the first visit travels in the clear"), .err)
                } else {
                    webSay(emit, String(format: L("the plain door answers HTTP %lld without an https redirect"), plainHTTP.statusCode))
                }
            }
        }
    }

    // MARK: the cert family, deep

    /// certprobe <url|host> — the
    /// leaf's papers, graded against
    /// the name you knocked on: does
    /// it cover this host, how is it
    /// signed, how strong is the key,
    /// who issued it, does the chain
    /// of trust hold.
    static func certprobe(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webCertTarget(url) else {
                webSay(emit, L("certprobe: give an https URL or a host — certprobe https://example.com"), .err)
                return
            }
            guard let trust = webTrust(host: target.host, port: target.port),
                  let leaf = certChain(trust).first else {
                webSay(emit, L("no papers were shown — the TLS door is shut or the handshake failed"), .err)
                return
            }
            if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                webSay(emit, String(format: L("subject: %@"), summary), .sys)
            }
            if let issuer = webCertName(leaf, issuer: true, oid: "2.5.4.3")
                ?? webCertName(leaf, issuer: true, oid: "2.5.4.10") {
                webSay(emit, String(format: L("issuer: %@"), issuer))
            }
            let kids = webTBSKids(leaf)
            if kids.count > 4 && kids[2].1 == kids[4].1 {
                webSay(emit, L("issuer and subject are the same name — this paper is self-signed"), .err)
            }
            let sans = BlacksitePentest.certSANs(leaf)
            if sans.isEmpty {
                webSay(emit, L("no subjectAltName at all — modern browsers refuse a cert without one"), .err)
            } else {
                webSay(emit, String(format: L("%lld names on the paper"), sans.count))
                let host = target.host.lowercased()
                var covered = false
                for name in sans {
                    let candidate = name.lowercased()
                    if candidate == host {
                        covered = true
                    }
                    if candidate.hasPrefix("*.") {
                        let suffix = String(candidate.dropFirst(2))
                        if host.hasSuffix("." + suffix) {
                            let label = host.dropLast(suffix.count + 1)
                            if !label.isEmpty && !label.contains(".") {
                                covered = true
                            }
                        }
                    }
                }
                if covered {
                    webSay(emit, String(format: L("%@ is covered by the paper"), target.host), .ok)
                } else {
                    webSay(emit, String(format: L("%@ is NOT among the paper's names — visitors' browsers will warn"), target.host), .err)
                }
            }
            if let sigOID = webCertSigOID(leaf) {
                switch sigOID {
                case "1.2.840.113549.1.1.11":
                    webSay(emit, L("signed sha256WithRSAEncryption"), .ok)
                case "1.2.840.113549.1.1.12":
                    webSay(emit, L("signed sha384WithRSAEncryption"), .ok)
                case "1.2.840.113549.1.1.13":
                    webSay(emit, L("signed sha512WithRSAEncryption"), .ok)
                case "1.2.840.10045.4.3.2":
                    webSay(emit, L("signed ecdsa-with-SHA256"), .ok)
                case "1.2.840.10045.4.3.3":
                    webSay(emit, L("signed ecdsa-with-SHA384"), .ok)
                case "1.2.840.113549.1.1.5":
                    webSay(emit, L("signed with SHA-1 — a broken hash; browsers distrust these papers"), .err)
                case "1.2.840.113549.1.1.4":
                    webSay(emit, L("signed with MD5 — a broken hash; these papers should not exist"), .err)
                default:
                    webSay(emit, String(format: L("signature algorithm %@"), sigOID))
                }
            }
            if let key = webCertKey(leaf) {
                webSay(emit, String(format: L("key: %@"), key))
                if key.hasPrefix("RSA — a 1024") || key.hasPrefix("RSA — a 512") {
                    webSay(emit, L("that key is short enough to factor with patience and money — it is a lock in name only"), .err)
                }
            }
            if let times = BlacksitePentest.certTimes(leaf) {
                let days = Int(times.1.timeIntervalSinceNow / 86400)
                webSay(emit, String(format: L("valid for %lld more days"), days))
                if days < 0 {
                    webSay(emit, L("the paper has EXPIRED"), .err)
                } else if days < 30 {
                    webSay(emit, L("under thirty days left — renewal is overdue to be scheduled"), .err)
                }
            }
            var trustError: CFError?
            if SecTrustEvaluateWithError(trust, &trustError) {
                webSay(emit, L("the chain of trust holds"), .ok)
            } else {
                let why = trustError.map { CFErrorCopyDescription($0) as String } ?? L("untrusted")
                webSay(emit, String(format: L("the chain of trust does NOT hold: %@"), why), .err)
            }
        }
    }

    /// certchain <url|host> — every
    /// paper in the chain, leaf to
    /// root, with its issuer and its
    /// remaining days; the chain is
    /// graded as a whole.
    static func certchain(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webCertTarget(url) else {
                webSay(emit, L("certchain: give an https URL or a host — certchain https://example.com"), .err)
                return
            }
            guard let trust = webTrust(host: target.host, port: target.port) else {
                webSay(emit, L("no papers were shown — the TLS door is shut or the handshake failed"), .err)
                return
            }
            let chain = certChain(trust)
            let count = chain.count
            webSay(emit, String(format: L("%lld papers in the chain"), count), .sys)
            var expired = 0
            for index in 0..<count {
                let cert = chain[index]
                let subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? L("an unnamed paper")
                let issuer = webCertName(cert, issuer: true, oid: "2.5.4.3")
                    ?? webCertName(cert, issuer: true, oid: "2.5.4.10")
                    ?? L("an unnamed issuer")
                var daysText = ""
                if let times = BlacksitePentest.certTimes(cert) {
                    let days = Int(times.1.timeIntervalSinceNow / 86400)
                    daysText = String(format: L(", %lld days left"), days)
                    if days < 0 { expired += 1 }
                }
                let role = index == 0 ? L("leaf") : (index == count - 1 ? L("root-ward anchor") : L("intermediate"))
                webSay(emit, String(format: L("%lld. [%@] %@ — issued by %@%@"), index + 1, role, subject, issuer, daysText))
            }
            if count > 4 {
                webSay(emit, L("a long chain — cross-signing usually explains it, and every extra paper is handshake weight and another expiry to track"))
            }
            if expired > 0 {
                webSay(emit, String(format: L("%lld papers in this chain have expired"), expired), .err)
            }
            var trustError: CFError?
            if SecTrustEvaluateWithError(trust, &trustError) {
                webSay(emit, L("the whole chain verifies"), .ok)
            } else {
                let why = trustError.map { CFErrorCopyDescription($0) as String } ?? L("untrusted")
                webSay(emit, String(format: L("the chain does NOT verify: %@"), why), .err)
            }
        }
    }

    /// ocspprobe <url|host> — where
    /// revocation lives for this
    /// house: the responder its paper
    /// names, the issuer's door, the
    /// must-staple mark — and one
    /// knock to prove the responder
    /// answers at all.
    static func ocspprobe(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webCertTarget(url) else {
                webSay(emit, L("ocspprobe: give an https URL or a host — ocspprobe https://example.com"), .err)
                return
            }
            guard let trust = webTrust(host: target.host, port: target.port),
                  let leaf = certChain(trust).first else {
                webSay(emit, L("no papers were shown — the TLS door is shut or the handshake failed"), .err)
                return
            }
            let doors = webAIADoors(leaf)
            let ocsp = doors.filter { $0.0 == "1.3.6.1.5.5.7.48.1" }.map { $0.1 }
            let issuers = doors.filter { $0.0 == "1.3.6.1.5.5.7.48.2" }.map { $0.1 }
            if ocsp.isEmpty {
                webSay(emit, L("the paper names NO OCSP responder — revocation rides on CRLs alone, which browsers check loosely or not at all"), .err)
            } else {
                for uri in ocsp {
                    webSay(emit, String(format: L("OCSP responder: %@"), uri))
                    if uri.hasPrefix("http://") {
                        webSay(emit, L("the responder rides plain http — normal for OCSP (its answers are signed), worth knowing"))
                    }
                    if let responderURL = URL(string: uri),
                       let (_, responderHTTP) = webFetch(responderURL) {
                        webSay(emit, String(format: L("the responder answers (HTTP %lld to an empty knock) — it is alive"), responderHTTP.statusCode), .ok)
                    } else {
                        webSay(emit, L("the responder did not answer an empty knock"), .err)
                    }
                }
            }
            for uri in issuers {
                webSay(emit, String(format: L("issuer's papers posted at: %@"), uri))
            }
            if let staple = webCertExtension(leaf, "1.3.6.1.5.5.7.1.24"),
               let seq = BlacksitePentest.berRead(staple, at: 0), seq.0 == 0x30 {
                let features = BlacksitePentest.berChildren(seq.1)
                    .filter { $0.0 == 0x02 }
                    .map { $0.1.reduce(0) { ($0 << 8) | Int($1) } }
                if features.contains(5) {
                    webSay(emit, L("the must-staple mark is set: browsers demand a stapled OCSP answer with this paper, or refuse it"), .ok)
                } else {
                    webSay(emit, L("a TLS-features mark is present, but status_request is not in it — stapling is not demanded"))
                }
            } else {
                webSay(emit, L("no must-staple mark — stapling is this house's choice, not its paper's demand"))
            }
        }
    }

    // MARK: the road, and the scripts

    /// redirectchain <url> — the
    /// chain walked by hand, hop by
    /// hop, watching for the two sins:
    /// stepping DOWN from https to
    /// http, and walking in circles.
    static func redirectchain(url: String,
                              emit: @escaping BlacksiteEmit,
                              done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard var current = webTarget(url)
            else {
                webSay(emit, L("redirectchain: give a URL — redirectchain https://example.com"), .err)
                return
            }
            var visited = Set<String>()
            var downgraded = false
            var hops = 0
            while hops < 10 {
                let key = current.absoluteString
                if visited.contains(key) {
                    webSay(emit, String(format: L("the chain walks in a circle — %@ again"), key), .err)
                    return
                }
                visited.insert(key)
                guard let (_, http) = webFetch(current) else {
                    webSay(emit, L("a hop went unanswered"), .err)
                    return
                }
                let location = webHeaders(http)["location"]
                webSay(emit, String(format: L("hop %lld: %@ → HTTP %lld"), hops + 1, key, http.statusCode))
                guard http.statusCode >= 300 && http.statusCode < 400,
                      let location = location,
                      let next = URL(string: location, relativeTo: current)?.absoluteURL else {
                    if hops == 0 {
                        webSay(emit, L("no chain — the first door is the destination"), .sys)
                    } else {
                        webSay(emit, String(format: L("the chain ends after %lld hops"), hops), .sys)
                    }
                    if downgraded {
                        webSay(emit, L("somewhere on the road the chain stepped DOWN from https to http — everything after that step travels in the clear"), .err)
                    }
                    return
                }
                if current.scheme == "https" && next.scheme == "http" {
                    downgraded = true
                    webSay(emit, L("  this hop steps DOWN from https to http"), .err)
                }
                current = next
                hops += 1
            }
            webSay(emit, L("ten hops and still walking — browsers give up around here too"), .err)
        }
    }

    /// jsendpoints <url> — the doors
    /// the page's own scripts name:
    /// script files read, and the API
    /// paths quoted inside them and
    /// the page. Nothing is fetched
    /// but the scripts themselves.
    static func jsendpoints(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("jsendpoints: give a URL — jsendpoints https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(target, follow: true), http.statusCode == 200 else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let page = String(decoding: data, as: UTF8.self)
            var scriptURLs: [URL] = []
            var rest = Substring(page)
            while let srcAt = rest.range(of: "src=\""),
                  scriptURLs.count < 8 {
                let tail = rest[srcAt.upperBound...]
                guard let end = tail.firstIndex(of: "\"") else { break }
                let src = String(tail[..<end])
                if src.hasSuffix(".js"), let resolved = URL(string: src, relativeTo: target)?.absoluteURL {
                    scriptURLs.append(resolved)
                }
                rest = tail[end...]
            }
            var texts: [(String, String)] = [(L("the page itself"), page)]
            for scriptURL in scriptURLs {
                if let (jsData, jsHTTP) = webFetch(scriptURL), jsHTTP.statusCode == 200 {
                    texts.append((scriptURL.lastPathComponent, String(decoding: jsData, as: UTF8.self)))
                }
            }
            webSay(emit, String(format: L("read %lld scripts plus the page"), texts.count - 1), .sys)
            var found: [(String, String)] = []
            var seen = Set<String>()
            let markers = ["/api/", "/v1/", "/v2/", "/v3/", "/graphql", "/rest/", "/wp-json/"]
            for (source, text) in texts {
                for marker in markers {
                    var scan = Substring(text)
                    while let at = scan.range(of: marker) {
                        var start = at.lowerBound
                        while start > scan.startIndex {
                            let before = scan.index(before: start)
                            let ch = scan[before]
                            if ch == "\"" || ch == "'" || ch == "`" || ch == "(" || ch == " " {
                                break
                            }
                            start = before
                        }
                        var end = at.upperBound
                        while end < scan.endIndex {
                            let ch = scan[end]
                            if ch == "\"" || ch == "'" || ch == "`" || ch == ")" || ch == " " || ch == "<" {
                                break
                            }
                            end = scan.index(after: end)
                        }
                        let path = String(scan[start..<end])
                        if path.count > 2 && path.count < 120 && !seen.contains(path) {
                            seen.insert(path)
                            found.append((path, source))
                        }
                        scan = scan[at.upperBound...]
                    }
                }
            }
            guard !found.isEmpty else {
                webSay(emit, L("the scripts name no API doors — the page keeps its roads to itself, or has none"), .sys)
                return
            }
            for (path, source) in found.prefix(40) {
                webSay(emit, String(format: L("  %@ (named in %@)"), path, source))
            }
            if found.count > 40 {
                webSay(emit, String(format: L("  … %lld doors named in all"), found.count))
            } else {
                webSay(emit, String(format: L("%lld doors named in all"), found.count), .sys)
            }
            webSay(emit, L("these are the doors the house's own code knocks on — each one exists, and each one answers strangers or it doesn't"), .sys)
        }
    }

    // MARK: the published doors

    /// swaggerprobe <url> — the API's
    /// own documentation doors, the
    /// canonical few every framework
    /// publishes at: a spec that
    /// answers strangers is the API's
    /// whole map, gift-wrapped.
    static func swaggerprobe(url: String,
                             emit: @escaping BlacksiteEmit,
                             done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("swaggerprobe: give a URL — swaggerprobe https://example.com"), .err)
                return
            }
            let candidates = ["/swagger.json", "/openapi.json", "/v3/api-docs",
                              "/swagger/v1/swagger.json", "/api-docs", "/swagger-ui.html"]
            var answered = 0
            for path in candidates {
                guard let probeURL = webSibling(target, path),
                      let (data, http) = webFetch(probeURL),
                      http.statusCode == 200 else { continue }
                answered += 1
                let body = String(decoding: data, as: UTF8.self)
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let dict = json as? [String: Any],
                   dict["swagger"] != nil || (dict["openapi"] as? String) != nil {
                    let version = (dict["swagger"] as? String) ?? (dict["openapi"] as? String) ?? "?"
                    let info = dict["info"] as? [String: Any]
                    let title = (info?["title"] as? String) ?? L("untitled")
                    var pathCount = 0
                    if let paths = dict["paths"] as? [String: Any] {
                        pathCount = paths.count
                    }
                    webSay(emit, String(format: L("%@: a live spec — %@, '%@', %lld documented paths"), path, version, title, pathCount), .err)
                } else if body.lowercased().contains("swagger ui") || body.lowercased().contains("swagger-ui") {
                    webSay(emit, String(format: L("%@: the Swagger UI page answers — the API's map, browsable"), path), .err)
                } else {
                    webSay(emit, String(format: L("%@: something answers here (%lld bytes) but it is not a spec"), path, data.count))
                }
            }
            if answered == 0 {
                webSay(emit, L("none of the canonical doc doors answers — the API keeps its map to itself"), .ok)
            } else {
                webSay(emit, L("a public spec is not a hole by itself — but it is the whole map of holes to look for"), .sys)
            }
        }
    }

    /// oidcprobe <url|domain> — the
    /// house's OpenID Connect
    /// discovery document, read whole:
    /// endpoints, algorithms, grants —
    /// and its keys, counted.
    static func oidcprobe(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let disco = webSibling(target, "/.well-known/openid-configuration")
            else {
                webSay(emit, L("oidcprobe: give a URL or a domain — oidcprobe https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(disco, follow: true), http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let dict = json as? [String: Any] else {
                webSay(emit, L("no discovery document answers at /.well-known/openid-configuration"), .sys)
                return
            }
            func field(_ name: String) -> String? { dict[name] as? String }
            webSay(emit, L("the discovery document answers:"), .sys)
            if let issuer = field("issuer") {
                webSay(emit, String(format: L("  issuer: %@"), issuer))
                if issuer.hasPrefix("http://") {
                    webSay(emit, L("  the issuer itself is plain http — identity over a clear channel"), .err)
                }
                if let base = webTarget(url)?.absoluteString, !issuer.isEmpty && !base.hasPrefix(issuer) && !issuer.hasPrefix(base) {
                    webSay(emit, L("  the issuer names a different house than the one knocked on — normal for hosted identity, worth knowing"))
                }
            }
            for name in ["authorization_endpoint", "token_endpoint", "userinfo_endpoint", "jwks_uri", "end_session_endpoint"] {
                if let value = field(name) {
                    webSay(emit, String(format: L("  %@: %@"), name, value))
                    if value.hasPrefix("http://") {
                        webSay(emit, String(format: L("  %@: plain http — credentials or codes cross it in the clear"), name), .err)
                    }
                }
            }
            if let algs = dict["id_token_signing_alg_values_supported"] as? [String] {
                webSay(emit, String(format: L("  signing algorithms: %@"), algs.joined(separator: ", ")))
                if algs.contains("none") {
                    webSay(emit, L("  'none' is an accepted signing algorithm — unsigned identity tokens will pass"), .err)
                }
            }
            if let grants = dict["grant_types_supported"] as? [String] {
                webSay(emit, String(format: L("  grants: %@"), grants.joined(separator: ", ")))
                if grants.contains("password") {
                    webSay(emit, L("  the password grant lives — raw credentials traded at the token door"), .err)
                }
            }
            if let methods = dict["token_endpoint_auth_methods_supported"] as? [String],
               methods.contains("none") {
                webSay(emit, L("  the token door accepts 'none' client authentication — public clients need no secret at all"), .err)
            }
            if let jwksURI = field("jwks_uri"),
               let jwksURL = URL(string: jwksURI),
               let (keyData, keyHTTP) = webFetch(jwksURL, follow: true), keyHTTP.statusCode == 200,
               let keyJSON = try? JSONSerialization.jsonObject(with: keyData),
               let keyDict = keyJSON as? [String: Any],
               let keys = keyDict["keys"] as? [[String: Any]] {
                webSay(emit, String(format: L("  %lld signing keys published at the jwks door"), keys.count))
            }
            webSay(emit, L("discovery is meant to be public — the grade is in whether what it publishes is sane"), .sys)
        }
    }

    /// graphqldeep <url> — deeper
    /// than a knock: the endpoint's
    /// manners. Does it answer the
    /// smallest query, teach through
    /// its errors, accept a batch, and
    /// open its schema to strangers.
    static func graphqldeep(url: String,
                            emit: @escaping BlacksiteEmit,
                            done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("graphqldeep: give the endpoint URL — graphqldeep https://example.com/graphql"), .err)
                return
            }
            func post(_ payload: String) -> (Data, HTTPURLResponse)? {
                webFetch(target, method: "POST",
                         headers: ["Content-Type": "application/json"],
                         body: Data(payload.utf8))
            }
            guard let (firstData, firstHTTP) = post("{\"query\":\"{__typename}\"}") else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let firstBody = String(decoding: firstData, as: UTF8.self)
            guard firstHTTP.statusCode == 200 && firstBody.contains("__typename") else {
                webSay(emit, String(format: L("HTTP %lld — no GraphQL answer to the smallest query; this may not be an endpoint"), firstHTTP.statusCode), .sys)
                return
            }
            webSay(emit, L("the endpoint answers the smallest query"), .ok)
            if let (data, http) = post("{\"query\":\"{ __schema { queryType { name } mutationType { name } types { name } } }\"}"),
               http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data),
               let dict = json as? [String: Any],
               let payload = dict["data"] as? [String: Any],
               let schema = payload["__schema"] as? [String: Any] {
                let types = (schema["types"] as? [[String: Any]]) ?? []
                webSay(emit, String(format: L("INTROSPECTION IS OPEN — the whole schema, %lld types, handed to a stranger"), types.count), .err)
                let queryName = (schema["queryType"] as? [String: Any])?["name"] as? String
                if let queryName = queryName {
                    webSay(emit, String(format: L("  query root: %@"), queryName))
                }
                if let mutation = schema["mutationType"] as? [String: Any],
                   let mutationName = mutation["name"] as? String {
                    webSay(emit, String(format: L("  mutation root: %@ — the write side has a name and a door"), mutationName))
                }
                let own = types.compactMap { $0["name"] as? String }.filter { !$0.hasPrefix("__") }
                webSay(emit, String(format: L("  types: %@"), own.prefix(20).joined(separator: ", ")))
            } else {
                webSay(emit, L("introspection is closed to strangers"), .ok)
            }
            if let (data, http) = post("{\"query\":\"{ __typenme }\"}"), http.statusCode == 200 || http.statusCode == 400 {
                let body = String(decoding: data, as: UTF8.self)
                if body.contains("Did you mean") {
                    webSay(emit, L("its errors teach: a mistyped field earns a 'Did you mean' — the schema leaks one suggestion at a time"), .err)
                } else {
                    webSay(emit, L("its errors keep their counsel — no field suggestions leak"))
                }
            }
            if let (data, http) = post("[{\"query\":\"{__typename}\"},{\"query\":\"{__typename}\"}]"),
               http.statusCode == 200 {
                let body = String(decoding: data, as: UTF8.self)
                if body.hasPrefix("[") && body.components(separatedBy: "__typename").count > 2 {
                    webSay(emit, L("batching is accepted — one knock can carry many queries, which is how rate limits get walked around"), .err)
                } else {
                    webSay(emit, L("a batched knock was not answered as a batch"))
                }
            }
            webSay(emit, L("none of this fired a mutation or a heavy query — manners only"), .sys)
        }
    }

    /// jwtdeep <token> — a bearer
    /// token read to the bottom: its
    /// header's sharp edges (kid,
    /// jku, x5u), its claims' sanity,
    /// its lifespan. No wire at all.
    static func jwtdeep(url: String,
                        emit: @escaping BlacksiteEmit,
                        done: @escaping () -> Void) {
        defer { done() }
        func decode(_ segment: String) -> [String: Any]? {
            var base = segment
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while base.count % 4 != 0 { base += "=" }
            guard let data = Data(base64Encoded: base),
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let dict = json as? [String: Any] else { return nil }
            return dict
        }
        let segments = url.components(separatedBy: ".")
        guard segments.count == 3,
              let header = decode(segments[0]),
              let payload = decode(segments[1]) else {
            webSay(emit, L("jwtdeep: give a token — three base64url parts joined by dots"), .err)
            return
        }
        let alg = (header["alg"] as? String) ?? "?"
        webSay(emit, String(format: L("algorithm: %@"), alg), .sys)
        if alg == "none" {
            webSay(emit, L("alg 'none' — the token asks to be believed unsigned"), .err)
        }
        if let kid = header["kid"] as? String {
            webSay(emit, String(format: L("kid: %@ — a key name the VERIFIER looks up; if it is treated as a path or a query, the token chooses the key"), kid), .err)
        }
        if let jku = header["jku"] as? String {
            webSay(emit, String(format: L("jku: %@ — the token names a URL to fetch its key from; a verifier that obeys lets the token bring its own key"), jku), .err)
        }
        if let x5u = header["x5u"] as? String {
            webSay(emit, String(format: L("x5u: %@ — the token names a URL for its certificate; same danger as jku"), x5u), .err)
        }
        if header["x5c"] != nil {
            webSay(emit, L("x5c: the token carries its own certificate — a verifier must chain it to a trusted root or it proves nothing"), .err)
        }
        if header["crit"] != nil {
            webSay(emit, L("crit is present — a verifier that ignores critical headers accepts terms it never read"))
        }
        if let typ = header["typ"] as? String {
            webSay(emit, String(format: L("typ: %@"), typ))
            if typ.lowercased() != "jwt" && typ.lowercased() != "at+jwt" {
                webSay(emit, L("an unusual typ — doors that accept many token kinds invite confusion between them"))
            }
        }
        func claim(_ name: String) -> String? {
            if let text = payload[name] as? String { return text }
            if let number = payload[name] as? NSNumber { return number.stringValue }
            return nil
        }
        if let iss = claim("iss") {
            webSay(emit, String(format: L("issuer: %@"), iss))
        } else {
            webSay(emit, L("no iss claim — the token does not say who minted it"))
        }
        if payload["aud"] == nil {
            webSay(emit, L("no aud claim — nothing in the token says which door it was minted for; any door that takes the issuer may take it"))
        }
        if payload["jti"] == nil {
            webSay(emit, L("no jti — the token has no serial number; a stolen one cannot be singled out for revocation"))
        }
        if let scope = claim("scope") ?? claim("scp") {
            webSay(emit, String(format: L("scope: %@"), scope))
        }
        if let iat = (payload["iat"] as? NSNumber)?.doubleValue,
           let exp = (payload["exp"] as? NSNumber)?.doubleValue {
            let life = Int(exp - iat)
            webSay(emit, String(format: L("minted to live %lld seconds (%lld hours)"), life, life / 3600))
            if life > 86400 {
                webSay(emit, L("a life over a day — a stolen token is a long-lived key; short lives are the whole point of these"), .err)
            }
            if exp < Date().timeIntervalSince1970 {
                webSay(emit, L("this one is already expired"), .err)
            }
        } else if payload["exp"] == nil {
            webSay(emit, L("no exp claim — the token never dies"), .err)
        }
        if let nbf = (payload["nbf"] as? NSNumber)?.doubleValue,
           let iat = (payload["iat"] as? NSNumber)?.doubleValue, nbf > iat {
            webSay(emit, L("nbf sits after iat — minted before it may be used; clock games live in gaps like that"))
        }
        if segments[1].count > 900 {
            webSay(emit, L("a fat payload — every claim in here is readable by anyone holding the token; secrets do not belong in it"))
        }
        webSay(emit, L("read locally only — nothing was sent anywhere"), .sys)
    }

    /// compressprobe <url> — does the
    /// house squeeze its answers, and
    /// with what: gzip, deflate, or
    /// the better brotli.
    static func compressprobe(url: String,
                              emit: @escaping BlacksiteEmit,
                              done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("compressprobe: give a URL — compressprobe https://example.com"), .err)
                return
            }
            guard let (squeezed, http) = webFetch(target,
                                                  headers: ["Accept-Encoding": "gzip, deflate, br"],
                                                  follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            let encoding = headers["content-encoding"]
            let mime = headers["content-type"] ?? ""
            webSay(emit, String(format: L("HTTP %lld, %@, %lld bytes as sent"), http.statusCode, mime, squeezed.count), .sys)
            if let encoding = encoding {
                webSay(emit, String(format: L("Content-Encoding: %@ — the house squeezes"), encoding), .ok)
                if encoding.contains("br") {
                    webSay(emit, L("brotli is offered — the best squeeze of the three"))
                }
            } else if mime.contains("text") || mime.contains("json") || mime.contains("javascript") {
                webSay(emit, L("no compression on a text answer — every visitor pays full fare in bytes and time"), .err)
            } else {
                webSay(emit, L("no compression — for already-squeezed media that is the right call"))
            }
            if let vary = headers["vary"] {
                webSay(emit, String(format: L("Vary: %@"), vary))
                if !vary.lowercased().contains("accept-encoding") && encoding != nil {
                    webSay(emit, L("Vary does not name Accept-Encoding — a shared cache may serve the squeezed copy to a client that cannot unsqueeze it, or the reverse"))
                }
            } else if encoding != nil {
                webSay(emit, L("no Vary header on a squeezed answer — caches are guessing"))
            }
        }
    }

    /// methoddeep <url> — the verbs,
    /// deeper than a knock on OPTIONS:
    /// the write verbs are tried
    /// against a path that does not
    /// exist, with an empty hand, so
    /// the answer grades the door's
    /// manners, not its furniture.
    static func methoddeep(url: String,
                           emit: @escaping BlacksiteEmit,
                           done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let nothing = webSibling(target, "/nightjar-method-probe-nothing-here")
            else {
                webSay(emit, L("methoddeep: give a URL — methoddeep https://example.com"), .err)
                return
            }
            if let (_, http) = webFetch(target, method: "OPTIONS") {
                let headers = webHeaders(http)
                let allow = headers["allow"] ?? headers["public"] ?? L("unlisted")
                webSay(emit, String(format: L("OPTIONS on the house: HTTP %lld, Allow: %@"), http.statusCode, allow), .sys)
            }
            for verb in ["PUT", "DELETE", "PATCH", "PROPFIND"] {
                guard let (_, http) = webFetch(nothing, method: verb) else { continue }
                if http.statusCode < 300 {
                    webSay(emit, String(format: L("%@ on a path that does not exist: HTTP %lld — the verb is ACCEPTED; on a real path that is a write door standing open"), verb, http.statusCode), .err)
                } else if http.statusCode == 405 || http.statusCode == 501 {
                    webSay(emit, String(format: L("%@: refused outright (HTTP %lld)"), verb, http.statusCode), .ok)
                } else {
                    webSay(emit, String(format: L("%@: HTTP %lld — the door exists but this path earns nothing"), verb, http.statusCode))
                }
            }
            if let (_, http) = webFetch(target, method: "TRACE") {
                if http.statusCode < 300 {
                    webSay(emit, L("TRACE is answered — cross-site tracing's old road is open"), .err)
                } else {
                    webSay(emit, String(format: L("TRACE: HTTP %lld"), http.statusCode), .ok)
                }
            }
            webSay(emit, L("the write verbs were tried empty-handed on a nothing path — manners, not breakage"), .sys)
        }
    }

    /// robotsdeep <url> — robots.txt
    /// graded as a document: its
    /// structure, its agent groups,
    /// and the doors its own map
    /// advertises. The file is only
    /// read; nothing in it is visited.
    static func robotsdeep(url: String,
                           emit: @escaping BlacksiteEmit,
                           done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let robotsURL = webSibling(target, "/robots.txt")
            else {
                webSay(emit, L("robotsdeep: give a URL — robotsdeep https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(robotsURL) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            guard http.statusCode == 200 else {
                webSay(emit, String(format: L("robots.txt answers HTTP %lld — crawlers read a missing file as 'everything is allowed'"), http.statusCode), .sys)
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            var agents = 0
            var wildcard = false
            var disallows: [String] = []
            var allows = 0
            var delays: [String] = []
            var sitemaps = 0
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                let low = line.lowercased()
                if low.hasPrefix("user-agent:") {
                    agents += 1
                    if low.contains("*") { wildcard = true }
                } else if low.hasPrefix("disallow:") {
                    let path = String(line.dropFirst("disallow:".count)).trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty { disallows.append(path) }
                } else if low.hasPrefix("allow:") {
                    allows += 1
                } else if low.hasPrefix("crawl-delay:") {
                    delays.append(String(line.dropFirst("crawl-delay:".count)).trimmingCharacters(in: .whitespaces))
                } else if low.hasPrefix("sitemap:") {
                    sitemaps += 1
                }
            }
            webSay(emit, String(format: L("%lld user-agent groups, %lld disallows, %lld allows, %lld sitemap lines"), agents, disallows.count, allows, sitemaps), .sys)
            if !wildcard {
                webSay(emit, L("no wildcard group — a crawler nobody named answers to no rules here"), .err)
            }
            if disallows.contains("/") {
                webSay(emit, L("the wildcard group disallows the whole house — the strongest word the file can say"))
            }
            for delay in delays {
                webSay(emit, String(format: L("crawl-delay %@ — politeness asked, honored only by the polite"), delay))
            }
            let telling = disallows.filter { path in
                let low = path.lowercased()
                return low.contains("admin") || low.contains(".git") || low.contains("backup")
                    || low.contains("config") || low.contains("private") || low.contains("internal")
                    || low.contains("staging") || low.contains("dev")
            }
            if !telling.isEmpty {
                webSay(emit, String(format: L("the map advertises %lld doors worth a hunter's knock: %@"), telling.count, telling.prefix(8).joined(separator: ", ")), .err)
                webSay(emit, L("robots.txt is a request, not a lock — anything named here still needs its own door"), .sys)
            }
            if disallows.isEmpty {
                webSay(emit, L("nothing is disallowed — the whole house is open to every polite crawler"), .sys)
            }
        }
    }

    // MARK: censuses, and the last door

    /// apicensus <url> — one answer
    /// read as an API citizen: its
    /// rate-limit manners, its
    /// pagination doors, the shape of
    /// its body, the challenge it
    /// issues when it refuses.
    static func apicensus(url: String,
                          emit: @escaping BlacksiteEmit,
                          done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url)
            else {
                webSay(emit, L("apicensus: give a URL — apicensus https://example.com/api"), .err)
                return
            }
            guard let (data, http) = webFetch(target, follow: true) else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let headers = webHeaders(http)
            let mime = headers["content-type"] ?? ""
            webSay(emit, String(format: L("HTTP %lld — %@ — %lld bytes"), http.statusCode, mime, data.count), .sys)
            var rateSeen = false
            for name in ["x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset",
                         "ratelimit-limit", "ratelimit-remaining", "retry-after"] {
                if let value = headers[name] {
                    rateSeen = true
                    webSay(emit, String(format: L("  %@: %@"), name, value))
                }
            }
            if mime.contains("json") {
                if !rateSeen {
                    webSay(emit, L("a JSON door with no rate-limit manners showing — either the limit rides elsewhere or there is none"), .err)
                }
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let dict = json as? [String: Any] {
                    webSay(emit, String(format: L("a JSON object of %lld keys: %@"), dict.count, dict.keys.sorted().prefix(12).joined(separator: ", ")))
                    let doors = ["next", "previous", "_links", "links", "meta", "pagination", "total", "count"]
                        .filter { dict[$0] != nil }
                    if !doors.isEmpty {
                        webSay(emit, String(format: L("pagination / census doors in the body: %@"), doors.joined(separator: ", ")))
                    }
                } else if let json = try? JSONSerialization.jsonObject(with: data),
                          let array = json as? [Any] {
                    webSay(emit, String(format: L("a JSON array of %lld entries — count what one knock carries home"), array.count))
                }
                if let link = headers["link"] {
                    webSay(emit, String(format: L("Link: %@ — the road onward, published"), link))
                }
            }
            if http.statusCode == 401, let challenge = headers["www-authenticate"] {
                webSay(emit, String(format: L("the refusal's challenge: %@"), challenge))
                if challenge.lowercased().hasPrefix("basic") {
                    webSay(emit, L("Basic — credentials in a hat, readable by anyone on the road; it wants https and a better scheme"), .err)
                }
                if challenge.lowercased().contains("bearer") {
                    webSay(emit, L("Bearer — a token door; jwtcheck and jwtdeep read what knocks with"))
                }
            }
            if let powered = headers["x-powered-by"] {
                webSay(emit, String(format: L("x-powered-by: %@"), powered))
            }
            webSay(emit, L("one knock's census — the API's manners to strangers, not its depths"), .sys)
        }
    }

    /// urlextract <url> — every road
    /// out of the page, gathered and
    /// sorted: where the house's own
    /// links lead, whose other houses
    /// it leans on, and whether any
    /// piece of it loads in the clear.
    static func urlextract(url: String,
                           emit: @escaping BlacksiteEmit,
                           done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let host = target.host
            else {
                webSay(emit, L("urlextract: give a URL — urlextract https://example.com"), .err)
                return
            }
            guard let (data, http) = webFetch(target, follow: true), http.statusCode == 200 else {
                webSay(emit, L("nothing answered — the name may not resolve, or the door is shut"), .err)
                return
            }
            let page = String(decoding: data, as: UTF8.self)
            var found: [String] = []
            var seen = Set<String>()
            for attr in ["href=\"", "src=\"", "action=\"", "href='", "src='"] {
                var rest = Substring(page)
                while let at = rest.range(of: attr) {
                    let tail = rest[at.upperBound...]
                    let quote: Character = attr.hasSuffix("\"") ? "\"" : "'"
                    guard let end = tail.firstIndex(of: quote) else { break }
                    let raw = String(tail[..<end])
                    if !raw.isEmpty && !seen.contains(raw) {
                        seen.insert(raw)
                        found.append(raw)
                    }
                    rest = tail[end...]
                }
            }
            var internalPaths = Set<String>()
            var externalHosts: [String: Int] = [:]
            var mail = 0
            var fragmentOnly = 0
            var clearLoaded: [String] = []
            for raw in found {
                if raw.hasPrefix("#") {
                    fragmentOnly += 1
                    continue
                }
                if raw.lowercased().hasPrefix("mailto:") || raw.lowercased().hasPrefix("tel:") {
                    mail += 1
                    continue
                }
                guard let resolved = URL(string: raw, relativeTo: target)?.absoluteURL,
                      let foundHost = resolved.host else { continue }
                if foundHost == host {
                    internalPaths.insert(resolved.path.isEmpty ? "/" : resolved.path)
                } else {
                    externalHosts[foundHost, default: 0] += 1
                }
                if target.scheme == "https" && resolved.scheme == "http" && raw.lowercased().hasPrefix("http://") {
                    clearLoaded.append(raw)
                }
            }
            webSay(emit, String(format: L("%lld links and loads in the page"), found.count), .sys)
            for path in internalPaths.sorted().prefix(25) {
                webSay(emit, String(format: L("  here: %@"), path))
            }
            if internalPaths.count > 25 {
                webSay(emit, String(format: L("  … %lld internal roads in all"), internalPaths.count))
            }
            for name in externalHosts.keys.sorted() {
                webSay(emit, String(format: L("  away: %@ (%lld)"), name, externalHosts[name] ?? 0))
            }
            if mail > 0 {
                webSay(emit, String(format: L("%lld mail / phone links"), mail))
            }
            if fragmentOnly > 0 {
                webSay(emit, String(format: L("%lld links go nowhere but this page's own anchors"), fragmentOnly))
            }
            if !clearLoaded.isEmpty {
                webSay(emit, String(format: L("MIXED CONTENT — %lld pieces of an https page load over plain http: %@"), clearLoaded.count, clearLoaded.prefix(4).joined(separator: ", ")), .err)
            }
            webSay(emit, L("the census is the page's own account of who it trusts and where it sends its visitors"), .sys)
        }
    }

    /// wayback <domain|url> — what
    /// the public archive remembers
    /// of this house: its first
    /// capture, its latest, and the
    /// road to the nearest snapshot.
    static func wayback(url: String,
                        emit: @escaping BlacksiteEmit,
                        done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            var hostText = url.trimmingCharacters(in: .whitespaces)
            if let parsed = BlacksitePentest.normalizedURL(url), let host = parsed.host {
                hostText = host
            }
            guard !hostText.isEmpty, hostText.contains(".") else {
                webSay(emit, L("wayback: give a domain — wayback example.com"), .err)
                return
            }
            let stamp: (String) -> String = { raw in
                guard raw.count >= 8 else { return raw }
                let year = String(raw.prefix(4))
                let month = String(raw.dropFirst(4).prefix(2))
                let day = String(raw.dropFirst(6).prefix(2))
                return year + "-" + month + "-" + day
            }
            if let api = URL(string: "https://archive.org/wayback/available?url=\(hostText)"),
               let (data, http) = webFetch(api, follow: true), http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data),
               let dict = json as? [String: Any],
               let results = dict["archived_snapshots"] as? [String: Any],
               let closest = results["closest"] as? [String: Any],
               let when = closest["timestamp"] as? String {
                let snapshot = (closest["url"] as? String) ?? ""
                let status = (closest["status"] as? String) ?? "?"
                webSay(emit, String(format: L("nearest snapshot: %@ (HTTP %@ when taken)"), stamp(when), status), .sys)
                if !snapshot.isEmpty {
                    webSay(emit, String(format: L("  %@"), snapshot))
                }
            } else {
                webSay(emit, L("the archive holds no snapshot near now for this house"), .sys)
            }
            if let cdx = URL(string: "https://web.archive.org/cdx/search/cdx?url=\(hostText)&output=json&limit=200&collapse=timestamp:8"),
               let (data, http) = webFetch(cdx, follow: true), http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data),
               let rows = json as? [[String]], rows.count > 1 {
                let stamps = rows.dropFirst().compactMap { $0.first }
                if let first = stamps.first, let last = stamps.last {
                    webSay(emit, String(format: L("captures on record from %@ to %@ — %lld sampled days"), stamp(first), stamp(last), stamps.count))
                }
            } else {
                webSay(emit, L("the archive's index names no captures for this house — either it is new, or it asked to be forgotten"))
            }
            webSay(emit, L("the archive is public memory: what a house has ever shown, it may remember forever"), .sys)
        }
    }

    /// corsdeep <url> — corsprobe's
    /// questions, deepened: stranger
    /// origins, the null origin, the
    /// house's own subdomain shape,
    /// and a true preflight carrying
    /// a method and a header.
    static func corsdeep(url: String,
                         emit: @escaping BlacksiteEmit,
                         done: @escaping () -> Void) {
        BlacksitePentest.run {
            defer { done() }
            guard let target = webTarget(url),
                  let host = target.host
            else {
                webSay(emit, L("corsdeep: give a URL — corsdeep https://example.com/api"), .err)
                return
            }
            let origins: [(String, String)] = [
                (L("a stranger"), "https://stranger.example.net"),
                (L("the null origin"), "null"),
                (L("a subdomain shape"), "https://sub.\(host)"),
                (L("the house over http"), "http://\(host)")
            ]
            func grade(origin: String, label: String, http: HTTPURLResponse) {
                let headers = webHeaders(http)
                guard let acao = headers["access-control-allow-origin"] else {
                    webSay(emit, String(format: L("%@ (%@): no answer to a cross-origin knock — the door is shut to it"), label, origin), .ok)
                    return
                }
                let credentials = (headers["access-control-allow-credentials"] ?? "").lowercased() == "true"
                if acao == "*" && credentials {
                    webSay(emit, String(format: L("%@: '*' WITH credentials — the combination browsers refuse, and a server confessing it never thought about either"), label), .err)
                } else if acao == "*" {
                    webSay(emit, String(format: L("%@: '*' — every origin on earth may read the answer"), label), .err)
                } else if acao == origin {
                    webSay(emit, String(format: L("%@: the origin is REFLECTED — any site that asks is let in%@"), label, credentials ? L(", credentials and all") : ""), .err)
                } else {
                    webSay(emit, String(format: L("%@: the answer names '%@' — a fixed guest list"), label, acao), .ok)
                }
                if headers["vary"]?.lowercased().contains("origin") != true {
                    webSay(emit, L("  and no Vary: Origin — a shared cache can hand one origin's answer to another"), .err)
                }
            }
            for (label, origin) in origins {
                if let (_, http) = webFetch(target, headers: ["Origin": origin], follow: true) {
                    grade(origin: origin, label: label, http: http)
                }
            }
            if let (_, http) = webFetch(target, method: "OPTIONS", headers: [
                "Origin": "https://stranger.example.net",
                "Access-Control-Request-Method": "PUT",
                "Access-Control-Request-Headers": "authorization"]) {
                let headers = webHeaders(http)
                webSay(emit, L("the preflight, as a stranger asking to PUT with an authorization header:"), .sys)
                webSay(emit, String(format: L("  methods allowed: %@"), headers["access-control-allow-methods"] ?? L("none named")))
                webSay(emit, String(format: L("  headers allowed: %@"), headers["access-control-allow-headers"] ?? L("none named")))
                if let maxAge = headers["access-control-max-age"] {
                    webSay(emit, String(format: L("  the permission is cached for %@ seconds — that long between a change of heart and its effect"), maxAge))
                }
                if let acao = headers["access-control-allow-origin"], acao == "*" || acao == "https://stranger.example.net" {
                    webSay(emit, L("  the stranger's preflight is welcomed — the write road is open to any site's script"), .err)
                }
            }
            webSay(emit, L("CORS is the browser's promise, not the server's wall — these grades are about what any web page may read and send"), .sys)
        }
    }

    // MARK: the switchboard

    /// Wave three's dispatch — the
    /// netCommand case in Blacksite
    /// hands the verb and its target
    /// here, the way wave two's verbs
    /// ride benchTwo.
    static func benchWeb(
        _ name: String, _ target: String,
        stopped: @escaping () -> Bool,
        emit: @escaping BlacksiteEmit,
        done: @escaping () -> Void) {
        if stopped() { done(); return }
        let live: BlacksiteEmit = { text, kind in
            if !stopped() { emit(text, kind) }
        }
        switch name {
        case "headersdeep":
            headersdeep(url: target, emit: live, done: done)
        case "cookieaudit":
            cookieaudit(url: target, emit: live, done: done)
        case "cacheprobe":
            cacheprobe(url: target, emit: live, done: done)
        case "wafdetect":
            wafdetect(url: target, emit: live, done: done)
        case "techstack":
            techstack(url: target, emit: live, done: done)
        case "sitemap":
            sitemap(url: target, emit: live, done: done)
        case "faviconhash":
            faviconhash(url: target, emit: live, done: done)
        case "httpversion":
            httpversion(url: target, emit: live, done: done)
        case "hstsprobe":
            hstsprobe(url: target, emit: live, done: done)
        case "certprobe":
            certprobe(url: target, emit: live, done: done)
        case "certchain":
            certchain(url: target, emit: live, done: done)
        case "ocspprobe":
            ocspprobe(url: target, emit: live, done: done)
        case "redirectchain":
            redirectchain(url: target, emit: live, done: done)
        case "jsendpoints":
            jsendpoints(url: target, emit: live, done: done)
        case "swaggerprobe":
            swaggerprobe(url: target, emit: live, done: done)
        case "oidcprobe":
            oidcprobe(url: target, emit: live, done: done)
        case "graphqldeep":
            graphqldeep(url: target, emit: live, done: done)
        case "jwtdeep":
            jwtdeep(url: target, emit: live, done: done)
        case "compressprobe":
            compressprobe(url: target, emit: live, done: done)
        case "methoddeep":
            methoddeep(url: target, emit: live, done: done)
        case "robotsdeep":
            robotsdeep(url: target, emit: live, done: done)
        case "apicensus":
            apicensus(url: target, emit: live, done: done)
        case "urlextract":
            urlextract(url: target, emit: live, done: done)
        case "wayback":
            wayback(url: target, emit: live, done: done)
        case "corsdeep":
            corsdeep(url: target, emit: live, done: done)
        default:
            done()
        }
    }
}
