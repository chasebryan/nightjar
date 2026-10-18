import Foundation
import SwiftUI

/// The app's tongue. One setting, chosen in About,
/// applied everywhere instantly and without a
/// relaunch: every localized string in the house is
/// looked up through here, against the .lproj table
/// for the chosen language.
///
/// English is both the key and the fallback: a call
/// site writes L("Sweep the wire"), the table for
/// the chosen language answers in that language,
/// and a string not yet translated shows in English
/// — never blank, never missing — so no language
/// ever loses a feature to an untranslated line.
///
/// Fonts need no bundling: the app draws with the
/// device's system fonts, which carry every script
/// it supports natively — Latin, Cyrillic, Arabic,
/// Devanagari, CJK, Hangul — at every size the
/// system offers, Dynamic Type included.
final class LanguageCenter: ObservableObject {
    static let shared = LanguageCenter()

    struct Language: Identifiable {
        let code: String
        /// The language's own name for itself —
        /// the one list that is never translated.
        let name: String
        var id: String { code }
    }

    static let languages: [Language] = [
        Language(code: "system", name: "System"),
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Español"),
        Language(code: "fr", name: "Français"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "pt", name: "Português"),
        Language(code: "it", name: "Italiano"),
        Language(code: "ru", name: "Русский"),
        Language(code: "ja", name: "日本語"),
        Language(code: "ko", name: "한국어"),
        Language(code: "zh-Hans", name: "简体中文"),
        Language(code: "ar", name: "العربية"),
        Language(code: "hi", name: "हिन्दी"),
    ]

    @Published var code: String {
        didSet {
            UserDefaults.standard.set(code,
                                      forKey: "app.language")
        }
    }

    init() {
        code = UserDefaults.standard.string(
            forKey: "app.language") ?? "system"
    }

    /// The language actually in force: the choice,
    /// or the device's own first language when the
    /// choice is to follow the system.
    var effective: String {
        if code != "system" { return code }
        let preferred = Locale.preferredLanguages
            .first ?? "en"
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        let base = preferred.split(separator: "-")
            .first.map(String.init) ?? "en"
        return Self.languages.contains { $0.code == base }
            ? base : "en"
    }

    var isRTL: Bool { effective == "ar" }

    var locale: Locale { Locale(identifier: effective) }

    private var bundleCache: [String: Bundle] = [:]

    private func tableBundle() -> Bundle? {
        let code = effective
        if code == "en" { return nil }
        if let cached = bundleCache[code] { return cached }
        guard let path = Bundle.main.path(
                forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        bundleCache[code] = bundle
        return bundle
    }

    /// Look a string up in the chosen language.
    /// The English text is the key; untranslated
    /// falls back to it verbatim.
    func string(_ key: String) -> String {
        guard let bundle = tableBundle() else { return key }
        return bundle.localizedString(
            forKey: key, value: key, table: nil)
    }

    static func t(_ key: String) -> String {
        shared.string(key)
    }
}

/// The one seam every localized call site uses:
/// L("Sweep the wire").
func L(_ key: String) -> String {
    LanguageCenter.t(key)
}
