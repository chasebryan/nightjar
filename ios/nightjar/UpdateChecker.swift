#if !STORE_BUILD
// The update checker exists for the direct (sideloaded)
// distribution only. App Store builds define STORE_BUILD
// and compile this whole file out: updates arrive through
// the App Store, and no traffic goes to GitHub.
import Foundation

/// Watches GitHub Releases for a newer nightjar and surfaces it.
///
/// When the release carries an over-the-air build — an ad hoc .ipa
/// with its manifest.plist attached — the surface is a true Update
/// button: no app may install a package itself, but an app may hand
/// iOS a manifest, and iOS installs the new build over this one,
/// data intact. When the release has no OTA build (the Personal
/// Team world), the surface is what it honestly is there: a link
/// to the release and the Xcode next step. Quietly does nothing
/// when the repo has no releases yet or the network is unreachable.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let tag: String
        let name: String
        let url: URL
        let notes: String
        /// Set when the release carries an OTA build:
        /// the itms-services address iOS installs from.
        var installURL: URL? = nil
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    /// True when GitHub answered 404: no releases published yet.
    /// Distinct from "up to date" — there is nothing to be up to
    /// date with — and About displays it as its own state.
    @Published private(set) var noReleasesYet = false

    let repo: String
    private let current: String
    private let session: URLSession
    private static let lastCheckKey = "nightjar.update.lastCheck"
    private static let minInterval: TimeInterval = 6 * 3600

    init(current: String = AppInfo.version, repo: String = "chasebryan/nightjar-hack",
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
            // Only an actual HTTP response counts as a check: stamp
            // lastChecked here, never on a transport failure.
            guard let http = response as? HTTPURLResponse else { return }
            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)
            if http.statusCode == 404 {
                // No releases published yet — its own state, not
                // "up to date".
                available = nil
                noReleasesYet = true
                return
            }
            // Any other non-200 (rate limit, server error…) says
            // nothing about releases: leave the known state —
            // an available update, the no-releases flag, all of
            // it — exactly as it was.
            guard http.statusCode == 200 else { return }
            noReleasesYet = false
            var parsed = Self.parse(data, current: current)
            if parsed != nil {
                parsed?.installURL = await Self.installURL(
                    repo: repo, session: session)
            }
            available = parsed
        } catch {
            // Offline or transport failure: lastChecked stays where
            // it was and any prior result stands; surface nothing.
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

    /// Where a release's OTA manifest would live, if it has one.
    nonisolated static func manifestURL(repo: String) -> URL {
        URL(string: "https://github.com/\(repo)"
            + "/releases/latest/download/manifest.plist")!
    }

    /// The install address, when the latest release carries an
    /// OTA build — probed with a single HEAD, so a release
    /// without one costs one request and changes nothing. The
    /// manifest's own address rides inside, fully encoded: iOS
    /// does the rest.
    static func installURL(repo: String,
                           session: URLSession) async -> URL? {
        let manifest = manifestURL(repo: repo)
        var probe = URLRequest(url: manifest)
        probe.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(
                for: probe),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = manifest.absoluteString
            .addingPercentEncoding(
                withAllowedCharacters: allowed)
        else { return nil }
        return URL(string: "itms-services://?action="
            + "download-manifest&url=" + encoded)
    }

    /// Compare "v2.1.0" against "2.0" numerically, component by component.
    nonisolated static func isNewer(_ latest: String, than current: String) -> Bool {
        let a = components(latest)
        let b = components(current)
        // A malformed tag (or current build version) is not comparable.
        guard !a.isEmpty, !b.isEmpty else { return false }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("v") { text.removeFirst() }
        // Compare release numbers only: "2.1.0-rc1" -> "2.1.0".
        if let dash = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<dash])
        }
        // Keep empty fields so "3..0" and "3." cannot become valid.
        let fields = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return [] }
        var numbers: [Int] = []
        for field in fields {
            // Reject non-decimal digits, empty fields, signs and Int overflow.
            guard !field.isEmpty,
                  field.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let value = Int(field) else { return [] }
            numbers.append(value)
        }
        return numbers
    }
}
#endif
