#if !STORE_BUILD
// The update checker exists for the direct (sideloaded)
// distribution only. App Store builds define STORE_BUILD
// and compile this whole file out: updates arrive through
// the App Store, and no traffic goes to GitHub.
import BackgroundTasks
import Foundation
import UserNotifications

/// Watches GitHub Releases for a newer nightjar and surfaces it.
///
/// The watch is constant while the app is open: a check at
/// launch, a check whenever the app returns to the front, and a
/// check every few minutes in between — conditional requests
/// (GitHub answers 304 when nothing changed, and doesn't count
/// those against the rate limit) keep that nearly free. While
/// the app is closed, a background refresh asks iOS for the
/// same check whenever the system grants the time, and speaks
/// up with a notification — only when notifications are already
/// allowed; the checker never asks for that permission itself.
/// Nothing is ever installed unasked: the surface is a choice.
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
    private static let dismissedKey = "nightjar.update.dismissedTag"
    private static let notifiedKey = "nightjar.update.notifiedTag"
    private static let minInterval: TimeInterval = 90
    /// How often the live watch re-checks while the app is open.
    private static let watchInterval: TimeInterval = 5 * 60
    /// The ETag of the last releases answer this instance
    /// processed, sent back as If-None-Match so an unchanged
    /// answer comes back as a bare 304 — headers only, and not
    /// counted against GitHub's rate limit. Kept in memory on
    /// purpose: a fresh instance must earn its own first 200
    /// before it may trust a 304.
    private var etag: String?
    private var watchTask: Task<Void, Never>?

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

    /// The update the operator hasn't waved off. The banner
    /// shows this; About shows `available` regardless, so a
    /// dismissed update is silenced, never lost.
    var visibleUpdate: Release? {
        guard let release = available,
              release.tag != UserDefaults.standard.string(
                forKey: Self.dismissedKey)
        else { return nil }
        return release
    }

    /// "Not this one." The banner folds until a *newer* tag
    /// appears — a new release is a new question.
    func dismiss() {
        guard let tag = available?.tag else { return }
        UserDefaults.standard.set(tag, forKey: Self.dismissedKey)
        objectWillChange.send()
    }

    /// Begin (or resume) the live watch: an immediate check,
    /// then another every few minutes for as long as the app
    /// is in front of the operator. Cheap by construction —
    /// see `etag`.
    func watch() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(
                    for: .seconds(Self.watchInterval))
            }
        }
    }

    /// Stand the watch down (the app has gone to background;
    /// the background refresh takes over from there).
    func unwatch() {
        watchTask?.cancel()
        watchTask = nil
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
        request.timeoutInterval = 25
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
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
            if http.statusCode == 304 {
                // Unchanged since this instance's last 200:
                // the known state stands, by definition.
                return
            }
            // Any other non-200 (rate limit, server error…) says
            // nothing about releases: leave the known state —
            // an available update, the no-releases flag, all of
            // it — exactly as it was.
            guard http.statusCode == 200 else { return }
            etag = http.value(forHTTPHeaderField: "ETag")
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

    // MARK: - Background refresh

    /// The background task's registered name; it must match
    /// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    nonisolated static let backgroundID =
        "net.nosuchmachine.nightjarhack.updatecheck"

    /// Register the background handler. Must run before the
    /// app finishes launching, on every launch — NightjarApp's
    /// init is the caller.
    nonisolated static func registerBackgroundCheck() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundID, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleBackgroundCheck(refresh)
        }
    }

    /// Ask iOS for background time to check again. iOS picks
    /// the moment — soon after the earliest date for an app
    /// that is used often, later for one that isn't; nothing
    /// here can promise sooner, and nothing pretends to.
    nonisolated static func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(
            identifier: backgroundID)
        request.earliestBeginDate =
            Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// One background run: schedule the next one first (so
    /// the chain survives anything below), check, and — if a
    /// release this operator hasn't seen announced or waved
    /// off is waiting — say so, once, and only where
    /// notifications are already welcome.
    nonisolated private static func handleBackgroundCheck(
        _ task: BGAppRefreshTask
    ) {
        scheduleBackgroundCheck()
        let gate = CompletionGate()
        let work = Task {
            let checker = await UpdateChecker()
            await checker.check()
            if let release = await checker.available {
                let defaults = UserDefaults.standard
                let alreadyAnnounced = defaults.string(
                    forKey: notifiedKey) == release.tag
                let wavedOff = defaults.string(
                    forKey: dismissedKey) == release.tag
                if !alreadyAnnounced && !wavedOff {
                    defaults.set(release.tag, forKey: notifiedKey)
                    await postNotification(for: release)
                }
            }
            if gate.claim() {
                task.setTaskCompleted(
                    success: !Task.isCancelled)
            }
        }
        task.expirationHandler = {
            work.cancel()
            if gate.claim() {
                task.setTaskCompleted(success: false)
            }
        }
    }

    /// A local notification for a waiting update — posted
    /// only when the operator has already allowed this app
    /// notifications. The checker never requests permission:
    /// that conversation belongs to the operator's own first
    /// non-stealth Serve start, as it always has.
    nonisolated private static func postNotification(
        for release: Release
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "Update available"
        content.body = "\(release.name) is out. "
            + "Open nightjar-hack to install it."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "nightjar.update.\(release.tag)",
            content: content, trigger: nil)
        try? await center.add(request)
    }

    /// Exactly-once completion for a background task: both
    /// the work and the expiration handler may reach the
    /// finish line; the system accepts only one arrival.
    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
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
