import Foundation

/// The house's setup, kept: every personal
/// configuration — the settings layer, not the
/// data — gathered into one snapshot that the
/// app itself maintains.
///
/// Three roads keep it safe. It is mirrored
/// into the Keychain as it changes, and the
/// Keychain survives what the app cannot: the
/// seven-day expiry, a deletion, a reinstall —
/// a fresh install on this device finds the
/// mirror and restores it before anything
/// reads a setting. It can be exported as one
/// file (nightjar-setup.json) for keeping
/// anywhere, and imported on any device.
/// And ordinary updates and re-signs never
/// needed either: the data container belongs
/// to the bundle, not the signature, so an
/// install-over keeps everything already.
///
/// Data is not settings: payloads, macros,
/// chests, sessions and logs keep their own
/// export roads and are not in the snapshot.
enum HouseSetup {
    static let formatID =
        "net.nosuchmachine.nightjar.setup"
    private static let service = "nightjar.setup"
    private static let account = "house"

    // MARK: - The snapshot

    /// The app's settings domain, filtered to
    /// what a snapshot may carry: strings,
    /// numbers, booleans, and collections of
    /// them. Blobs (saved data wearing a
    /// settings key) stay home.
    static func snapshot() -> [String: Any] {
        guard let bundle = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard
                .persistentDomain(forName: bundle)
        else { return [:] }
        var out: [String: Any] = [:]
        for (key, value) in domain {
            if key.hasPrefix("NS")
                || key.hasPrefix("Apple") { continue }
            if let kept = portable(value) {
                out[key] = kept
            }
        }
        return out
    }

    private static func portable(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            return string.count <= 65_536 ? string : nil
        case is NSNumber:
            return value
        case let array as [Any]:
            return array.compactMap(portable)
        case let dict as [String: Any]:
            return dict.compactMapValues(portable)
        default:
            return nil
        }
    }

    static func apply(_ settings: [String: Any]) {
        let defaults = UserDefaults.standard
        for (key, value) in settings {
            defaults.set(value, forKey: key)
        }
    }

    // MARK: - The file road

    static func exportData() -> Data? {
        let root: [String: Any] = [
            "format": formatID,
            "version": 1,
            "exported": ISO8601DateFormatter()
                .string(from: Date()),
            "settings": snapshot(),
        ]
        return try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    static func importData(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any],
              root["format"] as? String == formatID,
              let settings = root["settings"]
                as? [String: Any]
        else { return false }
        apply(settings)
        mirror()
        return true
    }

    // MARK: - The Keychain mirror

    /// Called once, as the app launches: a
    /// fresh install restores from the mirror
    /// before anything reads a setting; then
    /// the mirror begins watching for changes
    /// and refreshes itself.
    static func prepare() {
        MacroStore.seedPresetsIfNeeded()
        MacroStore.repairSeededFieldsV2()
        restoreIfFresh()
        HouseSetupMirror.shared.start()
        mirror()
    }

    private static func restoreIfFresh() {
        guard let bundle = Bundle.main.bundleIdentifier
        else { return }
        let domain = UserDefaults.standard
            .persistentDomain(forName: bundle)
        // A configured house has settings on
        // file; a fresh one has (almost) none.
        guard (domain?.count ?? 0) < 3 else { return }
        guard let data = keychainRead(),
              let root = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: Any],
              root["format"] as? String == formatID,
              let settings = root["settings"]
                as? [String: Any]
        else { return }
        apply(settings)
    }

    static func mirror() {
        guard let data = exportData() else { return }
        keychainWrite(data)
    }

    /// A true reset forgets the mirror too —
    /// otherwise the old setup would restore
    /// itself into the next fresh install.
    static func forgetMirror() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func keychainRead() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] =
            kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(
                query as CFDictionary, &item)
                == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return data
    }

    private static func keychainWrite(_ data: Data) {
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data]
                as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }
}

/// Watches the settings and refreshes the
/// mirror a breath after they settle — never
/// on every keystroke, always before long.
final class HouseSetupMirror: NSObject {
    static let shared = HouseSetupMirror()
    private var pending: DispatchWorkItem?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil)
    }

    @objc private func settingsChanged() {
        pending?.cancel()
        let work = DispatchWorkItem {
            HouseSetup.mirror()
        }
        pending = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2, execute: work)
    }
}
