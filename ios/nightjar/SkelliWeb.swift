import Foundation
import PDFKit
import SwiftUI
import WebKit

/// Her outward eye — and now, her own browser.
///
/// The strategy comes first: she only knocks on
/// doors that open cleanly for a machine. Keyless,
/// CAPTCHA-free endpoints are her scouts — instant
/// answers, Wikipedia, the RFC Editor, arXiv, Open
/// Library, GitHub, Stack Exchange — each chosen by
/// what the question is about. For the open web she
/// searches DuckDuckGo's lite index, visits the top
/// results herself, and reads them: page text
/// distilled to the passage that answers, PDFs read
/// whole, and — when a page only exists once its
/// scripts run — her real browser (a WKWebView that
/// is hers alone, non-persistent, no accounts, no
/// cookies kept) renders it and reads the result.
/// Walls, checks, and paywalls she walks past, not
/// through: another source almost always holds the
/// same truth in the open. Every answer names its
/// sources, so it can be judged like any testimony.
enum SkelliWeb {
    struct Finding {
        var text: String
        var source: String
        var url: String
        var score: Int = 0
        var preformatted: Bool = false
    }

    static func research(_ query: String,
                         completion: @escaping (String) -> Void) {
        let group = DispatchGroup()
        let collect = DispatchQueue(label: "skelli.web.collect")
        var instant: Finding?
        var wiki: Finding?
        var scouted: Finding?
        var pages: [Finding] = []
        var walls = 0
        let terms = searchTerms(query)

        // Fast path: instant answers + Wikipedia.
        if let url = endpoint("https://api.duckduckgo.com/",
                              items: [
                                  URLQueryItem(name: "q",
                                               value: query),
                                  URLQueryItem(name: "format",
                                               value: "json"),
                                  URLQueryItem(name: "no_html",
                                               value: "1"),
                                  URLQueryItem(name: "skip_disambig",
                                               value: "1"),
                              ]) {
            group.enter()
            fetchJSON(url) { dict in
                let found = duckDuckGoFinding(dict)
                collect.sync { instant = found }
                group.leave()
            }
        }
        if let url = endpoint("https://en.wikipedia.org/w/api.php",
                              items: [
                                  URLQueryItem(name: "action",
                                               value: "query"),
                                  URLQueryItem(name: "generator",
                                               value: "search"),
                                  URLQueryItem(name: "gsrsearch",
                                               value: query),
                                  URLQueryItem(name: "gsrlimit",
                                               value: "3"),
                                  URLQueryItem(name: "prop",
                                               value: "extracts|info"),
                                  URLQueryItem(name: "exintro",
                                               value: "1"),
                                  URLQueryItem(name: "explaintext",
                                               value: "1"),
                                  URLQueryItem(name: "inprop",
                                               value: "url"),
                                  URLQueryItem(name: "format",
                                               value: "json"),
                              ]) {
            group.enter()
            fetchJSON(url) { dict in
                let found = wikipediaFinding(dict)
                collect.sync { wiki = found }
                group.leave()
            }
        }

        // The scout her strategist sends first.
        group.enter()
        scout(query: query, terms: terms) { found in
            collect.sync { scouted = found }
            group.leave()
        }

        // Her browser: search lite, then go and read.
        group.enter()
        if let lite = endpoint(
            "https://lite.duckduckgo.com/lite/",
            items: [URLQueryItem(name: "q", value: query)]) {
            fetchText(lite) { html in
                let results = html.map(liteResults) ?? []
                for result in results.prefix(3) {
                    group.enter()
                    gatherPage(result, terms: terms) {
                        finding, hitWall in
                        collect.sync {
                            if let finding = finding {
                                pages.append(finding)
                            }
                            if hitWall { walls += 1 }
                        }
                        group.leave()
                    }
                }
                group.leave()
            }
        } else {
            group.leave()
        }

        group.notify(queue: .main) {
            completion(compose(query: query, scout: scouted,
                               pages: pages, instant: instant,
                               wiki: wiki, walls: walls))
        }
    }

    // MARK: fetching

    private static func endpoint(
        _ base: String, items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items
        return components?.url
    }

    private static func fetchData(
        _ url: URL,
        completion: @escaping (Data?, HTTPURLResponse?) -> Void) {
        var request = URLRequest(url: url,
                                 timeoutInterval: 12)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 "
                + "like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 "
                + "Mobile/15E148 Safari/604.1 Skelli",
            forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) {
            data, response, _ in
            completion(data, response as? HTTPURLResponse)
        }.resume()
    }

    private static func fetchText(
        _ url: URL, completion: @escaping (String?) -> Void) {
        fetchData(url) { data, response in
            guard let http = response,
                  (200...299).contains(http.statusCode),
                  let data = data
            else {
                completion(nil)
                return
            }
            completion(
                String(data: data, encoding: .utf8)
                    ?? String(data: data,
                              encoding: .isoLatin1))
        }
    }

    private static func fetchJSON(
        _ url: URL,
        completion: @escaping ([String: Any]?) -> Void) {
        fetchData(url) { data, response in
            guard let http = response,
                  (200...299).contains(http.statusCode),
                  let data = data,
                  let object = try? JSONSerialization
                      .jsonObject(with: data),
                  let dict = object as? [String: Any]
            else {
                completion(nil)
                return
            }
            completion(dict)
        }
    }

    // MARK: the instant parsers

    private static func duckDuckGoFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let dict = dict else { return nil }
        let source = (dict["AbstractSource"] as? String)
            ?? "DuckDuckGo"
        if let answer = dict["Answer"] as? String,
           !answer.isEmpty {
            return Finding(text: answer, source: source,
                           url: (dict["AbstractURL"]
                               as? String)
                               ?? "https://duckduckgo.com")
        }
        if let abstract = dict["AbstractText"] as? String,
           !abstract.isEmpty {
            return Finding(text: abstract, source: source,
                           url: (dict["AbstractURL"]
                               as? String)
                               ?? "https://duckduckgo.com")
        }
        return firstTopic(dict["RelatedTopics"])
    }

    private static func firstTopic(_ any: Any?) -> Finding? {
        guard let topics = any as? [[String: Any]] else {
            return nil
        }
        for topic in topics {
            if let text = topic["Text"] as? String,
               !text.isEmpty {
                return Finding(
                    text: text, source: "DuckDuckGo",
                    url: (topic["FirstURL"] as? String)
                        ?? "https://duckduckgo.com")
            }
            if let nested = firstTopic(topic["Topics"]) {
                return nested
            }
        }
        return nil
    }

    private static func wikipediaFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let query = dict?["query"] as? [String: Any],
              let pages = query["pages"]
                  as? [String: [String: Any]]
        else { return nil }
        let ordered = pages.values.sorted {
            (($0["index"] as? Int) ?? 99)
                < (($1["index"] as? Int) ?? 99)
        }
        for page in ordered {
            if let extract = page["extract"] as? String,
               !extract.isEmpty {
                return Finding(
                    text: extract, source: "Wikipedia",
                    url: (page["fullurl"] as? String)
                        ?? "https://en.wikipedia.org")
            }
        }
        return nil
    }

    // MARK: the scouts — friendly doors, chosen by intent

    private static func scout(
        query: String, terms: [String],
        completion: @escaping (Finding?) -> Void) {
        let q = query.lowercased()

        // A standard, by number: the RFC Editor's own
        // plain text, no gate at all.
        if let number = firstCapture(
            "rfc\\s*#?\\s*(\\d{1,5})", in: q),
           let url = URL(string: "https://www.rfc-editor.org"
                         + "/rfc/rfc" + number + ".txt") {
            fetchText(url) { text in
                completion(text.map {
                    Finding(
                        text: bestExcerpt(
                            $0, terms: terms + ["abstract"],
                            maxChars: 640),
                        source: "RFC " + number
                            + " — the RFC Editor",
                        url: "https://www.rfc-editor.org"
                            + "/info/rfc" + number,
                        score: 100, preformatted: true)
                })
            }
            return
        }

        // Papers: arXiv's open API.
        if q.contains("arxiv") || q.contains("paper")
            || q.contains("study")
            || q.contains("journal article") {
            let encoded = query.addingPercentEncoding(
                withAllowedCharacters:
                    .urlQueryAllowed) ?? query
            if let url = URL(string: "https://export.arxiv.org"
                             + "/api/query?search_query=all:"
                             + encoded
                             + "&start=0&max_results=2") {
                fetchText(url) { xml in
                    completion(xml.flatMap(arxivFinding))
                }
                return
            }
        }

        // Books: Open Library's open index.
        if q.contains("book") || q.contains("author")
            || q.contains("novel") || q.contains("isbn") {
            if let url = endpoint(
                "https://openlibrary.org/search.json",
                items: [URLQueryItem(name: "q",
                                     value: query),
                        URLQueryItem(name: "limit",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(openLibraryFinding(dict))
                }
                return
            }
        }

        // Code and projects: GitHub's public search.
        if q.contains("github") || q.contains("repository")
            || q.contains("repositories")
            || q.contains(" repo ")
            || q.hasSuffix(" repo") {
            if let url = endpoint(
                "https://api.github.com/search/repositories",
                items: [URLQueryItem(name: "q",
                                     value: query),
                        URLQueryItem(name: "sort",
                                     value: "stars"),
                        URLQueryItem(name: "per_page",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(githubFinding(dict))
                }
                return
            }
        }

        // Programming questions: Stack Exchange's API.
        if q.contains("stack overflow")
            || q.contains("stackoverflow") {
            let cleaned = q
                .replacingOccurrences(
                    of: "stack overflow", with: "")
                .replacingOccurrences(
                    of: "stackoverflow", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let url = endpoint(
                "https://api.stackexchange.com/2.3"
                    + "/search/advanced",
                items: [URLQueryItem(name: "order",
                                     value: "desc"),
                        URLQueryItem(name: "sort",
                                     value: "relevance"),
                        URLQueryItem(name: "q",
                                     value: cleaned),
                        URLQueryItem(name: "site",
                                     value: "stackoverflow"),
                        URLQueryItem(name: "pagesize",
                                     value: "3")]) {
                fetchJSON(url) { dict in
                    completion(stackExchangeFinding(dict))
                }
                return
            }
        }

        completion(nil)
    }

    private static func arxivFinding(_ xml: String)
        -> Finding? {
        let entries = regexMatches(
            "(?s)<entry>(.*?)</entry>", in: xml)
        guard !entries.isEmpty else { return nil }
        var lines: [String] = []
        var firstURL = "https://arxiv.org"
        for entry in entries.prefix(2) {
            let block = entry[1]
            let title = clean(decodeEntities(
                firstCapture("<title>(.*?)</title>",
                             in: block) ?? ""))
            let summary = clean(decodeEntities(
                firstCapture("<summary>(.*?)</summary>",
                             in: block) ?? ""))
            let link = firstCapture("<id>(.*?)</id>",
                                    in: block) ?? firstURL
            if lines.isEmpty { firstURL = link }
            lines.append(title + " — "
                         + excerpt(summary, maxChars: 300))
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "arXiv", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func openLibraryFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let docs = dict?["docs"]
                as? [[String: Any]], !docs.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://openlibrary.org"
        for doc in docs.prefix(3) {
            let title = (doc["title"] as? String)
                ?? "Untitled"
            let authors = (doc["author_name"]
                as? [String])?.joined(separator: ", ")
            let year = doc["first_publish_year"] as? Int
            var line = title
            if let authors = authors { line += " by " + authors }
            if let year = year { line += " (\(year))" }
            lines.append(line)
            if lines.count == 1,
               let key = doc["key"] as? String {
                firstURL = "https://openlibrary.org" + key
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "Open Library", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func githubFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let items = dict?["items"]
                as? [[String: Any]], !items.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://github.com"
        for item in items.prefix(3) {
            let name = (item["full_name"] as? String)
                ?? "unknown"
            let stars = (item["stargazers_count"] as? Int)
                ?? 0
            let about = (item["description"] as? String)
                ?? "no description"
            lines.append(name + " (★\(stars)): " + about)
            if lines.count == 1,
               let url = item["html_url"] as? String {
                firstURL = url
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "GitHub", url: firstURL,
                       score: 60, preformatted: true)
    }

    private static func stackExchangeFinding(
        _ dict: [String: Any]?) -> Finding? {
        guard let items = dict?["items"]
                as? [[String: Any]], !items.isEmpty
        else { return nil }
        var lines: [String] = []
        var firstURL = "https://stackoverflow.com"
        for item in items.prefix(3) {
            let title = clean(decodeEntities(
                stripTags((item["title"] as? String) ?? "")))
            let answers = (item["answer_count"] as? Int)
                ?? 0
            lines.append(title + " — \(answers) answer"
                         + (answers == 1 ? "" : "s"))
            if lines.count == 1,
               let link = item["link"] as? String {
                firstURL = link
            }
        }
        return Finding(text: lines.joined(separator: "\n"),
                       source: "Stack Overflow", url: firstURL,
                       score: 60, preformatted: true)
    }

    // MARK: her browser — search, visit, read

    private static func liteResults(_ html: String)
        -> [(title: String, url: URL)] {
        var out: [(title: String, url: URL)] = []
        var seen = Set<String>()
        for match in regexMatches(
            "(?is)<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>",
            in: html) {
            var href = match[1]
            if let marker = href.range(of: "uddg=") {
                let tail = href[marker.upperBound...]
                let raw = tail.split(separator: "&")
                    .first.map(String.init) ?? ""
                href = raw.removingPercentEncoding ?? raw
            }
            guard href.hasPrefix("http"),
                  let url = URL(string: href),
                  let host = url.host,
                  !host.contains("duckduckgo.com"),
                  !skippedDomain(host),
                  !seen.contains(href)
            else { continue }
            let title = clean(decodeEntities(
                stripTags(match[2])))
            guard title.count >= 3 else { continue }
            seen.insert(href)
            out.append((title: title, url: url))
        }
        return out
    }

    /// Domains that wall a machine on sight — paywalls,
    /// login gates, check pages. She doesn't knock.
    private static func skippedDomain(_ host: String)
        -> Bool {
        ["nytimes.com", "wsj.com", "ft.com",
         "bloomberg.com", "linkedin.com",
         "facebook.com", "instagram.com", "x.com",
         "twitter.com", "pinterest.com", "quora.com",
         "scribd.com", "researchgate.net"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func gatherPage(
        _ result: (title: String, url: URL),
        terms: [String],
        completion: @escaping (Finding?, Bool) -> Void) {
        fetchData(result.url) { data, response in
            guard let data = data, let http = response,
                  (200...299).contains(http.statusCode)
            else {
                completion(nil, false)
                return
            }
            let mime = http.mimeType ?? ""
            if mime.contains("pdf")
                || result.url.pathExtension
                    .lowercased() == "pdf" {
                if let text = pdfText(data) {
                    completion(Finding(
                        text: bestExcerpt(text, terms: terms),
                        source: result.title,
                        url: result.url.absoluteString,
                        score: score(text, terms: terms),
                        preformatted: true), false)
                } else {
                    completion(nil, false)
                }
                return
            }
            guard let html = String(data: data,
                                    encoding: .utf8)
                    ?? String(data: data,
                              encoding: .isoLatin1)
            else {
                completion(nil, false)
                return
            }
            if hostile(html) {
                completion(nil, true)
                return
            }
            let title = pageTitle(html) ?? result.title
            let extracted = extractText(html)
            if extracted.count >= 600 {
                completion(Finding(
                    text: bestExcerpt(extracted,
                                      terms: terms),
                    source: title,
                    url: result.url.absoluteString,
                    score: score(extracted, terms: terms),
                    preformatted: true), false)
                return
            }
            // Thin as served — her real browser renders
            // it and reads what the scripts build.
            DispatchQueue.main.async {
                SkelliWebRenderer.shared.render(
                    url: result.url) { rendered in
                    if let rendered = rendered,
                       rendered.count > extracted.count {
                        if hostile(rendered) {
                            completion(nil, true)
                            return
                        }
                        completion(Finding(
                            text: bestExcerpt(rendered,
                                              terms: terms),
                            source: title,
                            url: result.url.absoluteString,
                            score: score(rendered,
                                         terms: terms),
                            preformatted: true), false)
                    } else if extracted.count >= 200 {
                        completion(Finding(
                            text: bestExcerpt(extracted,
                                              terms: terms),
                            source: title,
                            url: result.url.absoluteString,
                            score: score(extracted,
                                         terms: terms),
                            preformatted: true), false)
                    } else {
                        completion(nil, false)
                    }
                }
            }
        }
    }

    /// Block pages announce themselves. If a page is
    /// a check, a wall, or a demand to prove humanity,
    /// it is not a source — it is a door she skips.
    private static func hostile(_ page: String) -> Bool {
        let low = page.lowercased()
        return ["are you a robot", "verify you are human",
                "unusual traffic from your computer",
                "challenge-platform",
                "checking your browser before accessing",
                "request blocked",
                "please complete the security check",
                "enable javascript and cookies to continue"]
            .contains { low.contains($0) }
    }

    private static func pageTitle(_ html: String)
        -> String? {
        guard let raw = firstCapture(
            "(?is)<title[^>]*>(.*?)</title>", in: html)
        else { return nil }
        let title = clean(decodeEntities(stripTags(raw)))
        return title.isEmpty ? nil
            : String(title.prefix(90))
    }

    /// Read a page the way a reader does: structure
    /// and chrome stripped, the prose kept.
    private static func extractText(_ html: String)
        -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg",
                    "header", "footer", "nav", "aside",
                    "form", "iframe"] {
            s = regexReplace(
                s, "(?is)<" + tag + "\\b[^>]*>.*?</"
                    + tag + ">", " ")
        }
        s = regexReplace(s, "(?is)<br\\s*/?>", "\n")
        s = regexReplace(
            s, "(?is)</(p|div|li|h1|h2|h3|h4|tr)>", "\n")
        s = decodeEntities(stripTags(s))
        let lines = s.components(separatedBy: "\n")
            .map { clean($0) }
            .filter { $0.count >= 25 }
        return lines.joined(separator: "\n")
    }

    private static func pdfText(_ data: Data) -> String? {
        guard data.count <= 12_000_000,
              let doc = PDFDocument(data: data)
        else { return nil }
        var out = ""
        for index in 0..<doc.pageCount {
            if let page = doc.page(at: index),
               let text = page.string {
                out += text + "\n"
            }
            if out.count > 24_000 { break }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: composing the answer

    private static func compose(query: String,
                                scout: Finding?,
                                pages: [Finding],
                                instant: Finding?,
                                wiki: Finding?,
                                walls: Int) -> String {
        var blocks: [String] = []
        if let scout = scout {
            blocks.append(block(scout))
        }
        for page in pages.sorted(by: {
            $0.score > $1.score
        }) {
            if blocks.count >= 3 { break }
            blocks.append(block(page))
        }
        if !blocks.isEmpty {
            var out = "I went out through my browser. "
                + "What holds up:\n\n"
                + blocks.joined(separator: "\n\n")
            if walls > 0 {
                out += "\n\n(" + "\(walls) result"
                    + (walls == 1 ? "" : "s")
                    + " hid behind a wall or a check — "
                    + "I walk past those, and work the "
                    + "sources that let me in cleanly.)"
            }
            return out
        }
        if let instant = instant {
            var lines = ["From the web — "
                         + instant.source + ":",
                         excerpt(instant.text),
                         "Source: " + instant.url]
            if let wiki = wiki, wiki.url != instant.url {
                lines.append("Also: " + wiki.source
                             + " — " + wiki.url)
            }
            return lines.joined(separator: "\n")
        }
        if let wiki = wiki {
            return "From the web — " + wiki.source + ":\n"
                + excerpt(wiki.text)
                + "\nSource: " + wiki.url
        }
        var failure = "I went out through my browser "
            + "for '" + query + "' and the sources "
            + "that let a machine in cleanly — the "
            + "open indexes, the lite index, the pages "
            + "themselves — brought nothing solid back."
        if walls > 0 {
            failure += " " + "\(walls) result"
                + (walls == 1 ? "" : "s")
                + " hid behind a wall or a check; I "
                + "don't climb those."
        }
        failure += " Rephrase it, or name the thing "
            + "more plainly, and I'll go again."
        return failure
    }

    private static func block(_ finding: Finding)
        -> String {
        "— " + finding.source + ": " + finding.text
            + "\nSource: " + finding.url
    }

    // MARK: text work

    private static func searchTerms(_ query: String)
        -> [String] {
        let stop: Set<String> = [
            "what", "is", "the", "a", "an", "of", "for",
            "in", "on", "to", "and", "or", "how", "does",
            "do", "did", "who", "when", "where", "why",
            "can", "could", "should", "would", "tell",
            "me", "about", "search", "web", "online",
            "research", "look", "up", "find", "explain",
        ]
        var seen = Set<String>()
        var out: [String] = []
        for word in query.lowercased().components(
            separatedBy: CharacterSet.alphanumerics
                .inverted) {
            if word.count >= 3, !stop.contains(word),
               !seen.contains(word) {
                seen.insert(word)
                out.append(word)
            }
        }
        return Array(out.prefix(8))
    }

    private static func score(_ text: String,
                              terms: [String]) -> Int {
        let low = text.lowercased()
        var total = 0
        for term in terms {
            total += min(
                low.components(separatedBy: term)
                    .count - 1, 8)
        }
        return total
    }

    private static func sentences(_ text: String)
        -> [String] {
        clean(text).components(separatedBy: ". ")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    /// The passage that answers: the best-matching
    /// sentence, with its neighbours, capped.
    private static func bestExcerpt(_ text: String,
                                    terms: [String],
                                    maxChars: Int = 520)
        -> String {
        let all = sentences(text)
        guard !all.isEmpty else {
            return excerpt(text, maxChars: maxChars)
        }
        var best = 0
        var bestScore = -1
        for (index, sentence) in all.enumerated() {
            let value = score(sentence, terms: terms)
            if value > bestScore {
                bestScore = value
                best = index
            }
        }
        if bestScore <= 0 {
            return excerpt(text, maxChars: maxChars)
        }
        var out = all[best]
        var step = 1
        while out.count < maxChars, step <= all.count {
            if best + step < all.count {
                out += " " + all[best + step]
            }
            if out.count >= maxChars { break }
            if best - step >= 0 {
                out = all[best - step] + " " + out
            }
            step += 1
        }
        return out.count > maxChars + 160
            ? excerpt(out, maxChars: maxChars) : out
    }

    /// Whole sentences from the top, capped — for the
    /// instant sources that already lead with the gist.
    private static func excerpt(_ text: String,
                                maxChars: Int = 720)
        -> String {
        let cleaned = clean(text)
        if cleaned.count <= maxChars { return cleaned }
        var out = ""
        for part in cleaned.components(separatedBy: ". ") {
            let sentence = part.hasSuffix(".")
                ? part : part + "."
            if out.isEmpty {
                if sentence.count > maxChars { break }
                out = sentence
            } else if (out + " " + sentence).count
                        <= maxChars {
                out += " " + sentence
            } else {
                break
            }
            if out.count > maxChars - 120 { break }
        }
        return out.isEmpty
            ? String(cleaned.prefix(maxChars)) + "…"
            : out
    }

    private static func clean(_ text: String) -> String {
        text.components(
            separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func stripTags(_ html: String)
        -> String {
        regexReplace(html, "(?s)<[^>]+>", " ")
    }

    private static func decodeEntities(_ text: String)
        -> String {
        var out = text
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"),
            ("&#39;", "'"), ("&#x27;", "'"),
            ("&nbsp;", " "), ("&#8217;", "’"),
            ("&#8220;", "“"), ("&#8221;", "”"),
            ("&#8211;", "–"), ("&#8212;", "—"),
            ("&#038;", "&"),
        ] {
            out = out.replacingOccurrences(
                of: entity, with: replacement)
        }
        return out
    }

    private static func regexReplace(_ s: String,
                                     _ pattern: String,
                                     _ template: String)
        -> String {
        s.replacingOccurrences(of: pattern, with: template,
                               options: .regularExpression)
    }

    private static func regexMatches(_ pattern: String,
                                     in s: String)
        -> [[String]] {
        guard let re = try? NSRegularExpression(
            pattern: pattern) else { return [] }
        let range = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, range: range).map {
            match in
            (0..<match.numberOfRanges).map { index in
                guard let r = Range(
                    match.range(at: index), in: s)
                else { return "" }
                return String(s[r])
            }
        }
    }

    private static func firstCapture(_ pattern: String,
                                     in s: String)
        -> String? {
        regexMatches(pattern, in: s)
            .first.flatMap {
                $0.count > 1 && !$0[1].isEmpty
                    ? $0[1] : nil
            }
    }
}

/// Her browser itself: one WKWebView, hers alone.
/// Non-persistent data store — no cookies kept, no
/// accounts, no history; it exists to render a page
/// whose text only exists once its scripts run, and
/// to hand the words back. Hosted invisibly in her
/// tab; foreground only, like everything in the house.
final class SkelliWebRenderer: NSObject,
                               WKNavigationDelegate {
    static let shared = SkelliWebRenderer()

    private weak var webView: WKWebView?
    private var completion: ((String?) -> Void)?
    private var timeout: DispatchWorkItem?

    func attach(_ view: WKWebView) {
        webView = view
        view.navigationDelegate = self
    }

    /// One page at a time. Busy, or unhosted — she
    /// goes without, and the caller carries on.
    func render(url: URL,
                completion: @escaping (String?) -> Void) {
        guard let view = webView, self.completion == nil
        else {
            completion(nil)
            return
        }
        self.completion = completion
        view.stopLoading()
        view.load(URLRequest(url: url,
                             timeoutInterval: 15))
        let work = DispatchWorkItem { [weak self] in
            self?.finish(nil)
        }
        timeout = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 18, execute: work)
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            "document.body ? document.body.innerText : ''"
        ) { [weak self] result, _ in
            self?.finish(result as? String)
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation
                     navigation: WKNavigation!,
                 withError error: Error) {
        finish(nil)
    }

    private func finish(_ text: String?) {
        timeout?.cancel()
        timeout = nil
        let done = completion
        completion = nil
        webView?.stopLoading()
        done?(text)
    }
}

/// The browser's berth in her tab: a point of light,
/// untouchable, just present enough for WebKit to
/// do its work.
struct SkelliWebHost: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences
            .allowsContentJavaScript = true
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            configuration: config)
        view.alpha = 0.02
        view.isUserInteractionEnabled = false
        SkelliWebRenderer.shared.attach(view)
        return view
    }

    func updateUIView(_ uiView: WKWebView,
                      context: Context) { }
}
