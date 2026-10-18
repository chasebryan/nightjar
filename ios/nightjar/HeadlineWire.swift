import Foundation
import SwiftUI

/// Her headline wire. The activity line, when
/// she is not narrating work, scrolls the
/// world's latest past her — major events
/// from global desks, the United States given
/// a full share of the turns, and the
/// cybersecurity wires (CISA's advisories,
/// the trade press) braided through it.
///
/// The desks are chosen independent — no
/// party's organ among them: wire-style
/// world services (Euronews, Sky News,
/// France 24), the USA drawn from the center
/// (The Hill, RealClearPolitics) and the
/// right of center (Washington Examiner,
/// Just the News), so the list leans a
/// degree right without belonging to anyone.
/// Titles run exactly as the desks wrote
/// them — the leaning lives in the choosing,
/// never in a rewritten word, and the line
/// itself carries no label for any of it.
///
/// It keeps itself latest: a fetch on first
/// appearance, on every return to the front
/// of the phone, and on a fifteen-minute
/// timer while she lives — the operator
/// never asks it to update, and there is no
/// button. What she holds is cached, so a
/// cold start scrolls the last set instantly
/// while the fresh one is fetched behind it.
///
/// Plain public RSS, fetched the way her
/// research eye fetches — and governed by the
/// same switch: web off, no wire, and the
/// line goes back to her own readout. Every
/// failure is silent: a desk that cannot be
/// reached simply misses a turn, and if no
/// desk answers, the readout speaks instead.
/// Titles only — no links kept, no bodies
/// read, nothing of the house sent out.
final class HeadlineWire: ObservableObject {
    static let shared = HeadlineWire()

    @Published private(set) var headlines: [String] = []
    @Published private(set) var fetchedAt: Date?

    /// The operator's switch for the wire,
    /// living in her options beside her other
    /// switches. Off silences the ticker and
    /// stops the fetching — the line falls
    /// back to her own readout. On is the
    /// house default, and a reset restores it.
    @Published var enabled: Bool = true {
        didSet {
            UserDefaults.standard.set(
                enabled, forKey: "headlines.enabled")
            if enabled { start() }
        }
    }

    private enum Desk { case world, usa, cyber }
    private struct Feed {
        let url: String
        let desk: Desk
    }

    private static let feeds: [Feed] = [
        Feed(url: "https://www.euronews.com/rss",
             desk: .world),
        Feed(url: "https://feeds.skynews.com/feeds/rss/world.xml",
             desk: .world),
        Feed(url: "https://www.france24.com/en/rss",
             desk: .world),
        Feed(url: "https://thehill.com/feed/",
             desk: .usa),
        Feed(url: "https://www.realclearpolitics.com/index.xml",
             desk: .usa),
        Feed(url: "https://www.washingtonexaminer.com/feed",
             desk: .usa),
        Feed(url: "https://justthenews.com/rss.xml",
             desk: .usa),
        Feed(url: "https://www.cisa.gov/cybersecurity-advisories/all.xml",
             desk: .cyber),
        Feed(url: "https://www.bleepingcomputer.com/feed/",
             desk: .cyber),
        Feed(url: "https://feeds.feedburner.com/TheHackersNews",
             desk: .cyber),
    ]

    private var fetching = false
    private var timer: Timer?
    private let cacheKey = "headlines.cache"
    private let cacheDateKey = "headlines.fetchedAt"

    private init() {
        headlines = UserDefaults.standard
            .stringArray(forKey: cacheKey) ?? []
        fetchedAt = UserDefaults.standard.object(
            forKey: cacheDateKey) as? Date
        enabled = UserDefaults.standard.object(
            forKey: "headlines.enabled")
            as? Bool ?? true
    }

    /// The ribbon, when there is anything to
    /// scroll: the latest set she holds,
    /// joined for the marquee.
    var tickerText: String? {
        guard enabled, !headlines.isEmpty
        else { return nil }
        return headlines.joined(
            separator: "  ···  ") + "  ···  "
    }

    /// Start the wire — fetch now if the held
    /// set is older than five minutes, and
    /// keep it fresh on its timer for as long
    /// as she lives.
    func start() {
        if timer == nil {
            timer = Timer.scheduledTimer(
                withTimeInterval: 900,
                repeats: true) { [weak self] _ in
                self?.fetch()
            }
        }
        if let fetchedAt,
           Date().timeIntervalSince(fetchedAt) < 300,
           !headlines.isEmpty {
            return
        }
        fetch()
    }

    /// The app has come back to the front:
    /// the latest, again, unasked.
    func refreshOnForeground() {
        if let fetchedAt,
           Date().timeIntervalSince(fetchedAt) < 120 {
            return
        }
        fetch()
    }

    private func fetch() {
        guard !fetching, enabled else { return }
        guard SkelliCenter.shared.webResearchEnabled
        else { return }
        fetching = true
        let group = DispatchGroup()
        let lock = NSLock()
        var byDesk: [Desk: [String]] = [:]
        for feed in Self.feeds {
            guard let url = URL(string: feed.url)
            else { continue }
            group.enter()
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(
                "nightjar-hack headline wire",
                forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(
                with: request) { data, _, _ in
                defer { group.leave() }
                guard let data else { return }
                let titles = RSSHeadlines.titles(
                    from: data, limit: 8)
                guard !titles.isEmpty else { return }
                lock.lock()
                byDesk[feed.desk, default: []]
                    .append(contentsOf: titles)
                lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.fetching = false
            let mixed = Self.mix(byDesk)
            guard !mixed.isEmpty else { return }
            self.headlines = mixed
            self.fetchedAt = Date()
            UserDefaults.standard.set(
                mixed, forKey: self.cacheKey)
            UserDefaults.standard.set(
                self.fetchedAt,
                forKey: self.cacheDateKey)
        }
    }

    /// The braid: world, USA, cyber, repeating
    /// — globally based, the USA given its
    /// full share of turns, no story twice.
    private static func mix(
        _ byDesk: [Desk: [String]]) -> [String] {
        var pools: [[String]] = []
        for desk in [Desk.world, .usa, .cyber] {
            var seen = Set<String>()
            pools.append((byDesk[desk] ?? []).filter {
                seen.insert($0.lowercased()).inserted
            })
        }
        var out: [String] = []
        var used = Set<String>()
        var idx = [0, 0, 0]
        while out.count < 15 {
            var progressed = false
            for d in 0..<3 {
                guard idx[d] < pools[d].count
                else { continue }
                let item = pools[d][idx[d]]
                idx[d] += 1
                progressed = true
                if used.insert(
                    item.lowercased()).inserted {
                    out.append(item)
                }
                if out.count >= 15 { break }
            }
            if !progressed { break }
        }
        return out
    }
}

/// The smallest honest RSS reader: item and
/// entry titles, nothing else.
private final class RSSHeadlines: NSObject,
    XMLParserDelegate {
    private var titles: [String] = []
    private var inItem = false
    private var inTitle = false
    private var buffer = ""
    private var limit = 8

    static func titles(from data: Data,
                       limit: Int) -> [String] {
        let reader = RSSHeadlines()
        reader.limit = limit
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.titles
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict:
                    [String: String] = [:]) {
        if elementName == "item"
            || elementName == "entry" {
            inItem = true
        }
        if inItem && elementName == "title" {
            inTitle = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser,
                foundCharacters string: String) {
        if inTitle { buffer += string }
    }

    func parser(_ parser: XMLParser,
                foundCDATA CDATABlock: Data) {
        if inTitle,
           let s = String(data: CDATABlock,
                          encoding: .utf8) {
            buffer += s
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "title", inTitle {
            inTitle = false
            let title = Self.clean(buffer)
            if title.count >= 12 {
                titles.append(title)
            }
            if titles.count >= limit {
                parser.abortParsing()
            }
        }
        if elementName == "item"
            || elementName == "entry" {
            inItem = false
        }
    }

    private static func clean(_ raw: String)
        -> String {
        var s = raw
            .components(separatedBy:
                .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if s.count > 120 {
            let cut = s.prefix(120)
            if let space = cut.lastIndex(of: " ") {
                s = String(cut[..<space]) + "…"
            } else {
                s = String(cut) + "…"
            }
        }
        return s
    }
}

/// The marquee: the ribbon scrolls left at a
/// reading pace, two copies nose-to-tail so
/// the loop never shows its seam. If the
/// ribbon is shorter than the line, it simply
/// rests.
///
/// Second construction (2026-10-18): the
/// first hung its motion on a Boolean state
/// flip driving an animation — and on device
/// the scroll died, because this view's
/// parents re-render constantly and a
/// stranded flip never restarts. Now the
/// offset is a pure function of the clock,
/// recomputed every frame by a TimelineView:
/// there is no state to strand, no animation
/// to drop. A refresh restarts the ribbon
/// from its head, as a wire's should.
struct HeadlineTicker: View {
    let text: String

    @State private var copyWidth: CGFloat = 0
    @State private var born = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { ctx in
                let wide = copyWidth
                    > geo.size.width
                let elapsed = max(0, ctx.date
                    .timeIntervalSince(born))
                let travel = wide
                    ? CGFloat(elapsed) * 45 : 0
                let off = wide && copyWidth > 0
                    ? -(travel.truncatingRemainder(
                        dividingBy: copyWidth))
                    : 0
                HStack(spacing: 0) {
                    ribbon
                    ribbon
                }
                .offset(x: off)
            }
        }
        .frame(height: 17)
        .clipped()
        .onChange(of: text) { _ in
            copyWidth = 0
            born = Date()
        }
    }

    private var ribbon: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true,
                       vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            copyWidth =
                                proxy.size.width
                        }
                        .onChange(
                            of: proxy.size.width
                        ) { w in
                            copyWidth = w
                        }
                })
    }
}
