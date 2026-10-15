import Foundation

/// Watches GitHub Releases for a newer nightjar and surfaces it.
///
/// A sideloaded app can't install its own update — iOS won't let it, and
/// a free Personal Team build has to be re-run from Xcode anyway. So this
/// doesn't pretend to self-update: it notices when a newer release is
/// tagged and shows a banner that links to it, with the honest next step
/// (open the project, press Run). Quietly does nothing when the repo has
/// no releases yet or the network is unreachable.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let tag: String
        let name: String
        let url: URL
        let notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?

    let repo: String
    private let current: String
    private let session: URLSession
    private static let lastCheckKey = "nightjar.update.lastCheck"
    private static let minInterval: TimeInterval = 6 * 3600

    init(current: String = AppInfo.version, repo: String = "chasebryan/nightjar",
         session: URLSession = .shared) {
        self.current = current
        self.repo = repo
        self.session = session
        let stored = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        self.lastChecked = stored
    }

    var releasesURL: URL {
        URL(string: "https://github.com/\(repo)/releases")!
    }

    /// Check at most every few hours unless forced.
    func checkIfDue(force: Bool = false) async {
        if !force, let last = lastChecked,
           Date().timeIntervalSince(last) < Self.minInterval {
            return
        }
        await check()
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let endpoint = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("nightjar-ios", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // 404 = no releases published yet. Not an error worth showing.
                available = nil
                return
            }
            available = Self.parse(data, current: current)
        } catch {
            // Offline or rate-limited: leave any prior result, surface nothing.
        }
    }

    // MARK: - Pure helpers (unit-tested, actor-free)

    nonisolated static func parse(_ data: Data, current: String) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let urlString = object["html_url"] as? String,
              let url = URL(string: urlString) else {
            return nil
        }
        if object["draft"] as? Bool == true || object["prerelease"] as? Bool == true {
            return nil
        }
        guard isNewer(tag, than: current) else { return nil }
        let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag
        let notes = (object["body"] as? String) ?? ""
        return Release(tag: tag, name: name, url: url, notes: notes)
    }

    /// Compare "v2.1.0" against "2.0" numerically, component by component.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = components(latest)
        let b = components(current)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("v") { text.removeFirst() }
        // Drop any pre-release/build suffix: "2.1.0-rc1" -> "2.1.0".
        if let dash = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<dash])
        }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }
}
